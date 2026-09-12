#!/usr/bin/env bash
# docker-user-firewall.sh — default-deny public forwarding with one HTTPS ingress.
# Byline: Claude Code · Fable 5.1 · 2026-09-07 (original tailnet-only rule).
# Byline amendment: Codex · GPT-5 · 2026-09-12 (owner-authorized public Traefik ingress).
#
# Why DOCKER-USER: Docker DNATs before FORWARD and bypasses ufw/INPUT for published ports
# (lessons recorded 2026-07-29, memory weaviate-public-exposure). Rules here are evaluated before
# Docker's own FORWARD rules. RELATED,ESTABLISHED must be first or container replies die.
# Effect: TCP 80/443 and UDP 443 arriving on the public NIC ($PUB_IF) may reach the existing
# Traefik ingress. Every other new public connection to a published container port is dropped.
# Tailnet (100.64/10, fd7a:115c:a1e0::/48), loopback, and Docker-internal ranges remain allowed.
# Host-level INPUT (sshd 22 and tailscaled UDP) is untouched.
set -euo pipefail
PUB_IF="${PUB_IF:-ens3}"
ipt() { iptables -w 5 "$@"; }
ipt6() { ip6tables -w 5 "$@"; }

ipt -N DOCKER-USER 2>/dev/null || true
ipt -F DOCKER-USER
ipt -A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
for src in 100.64.0.0/10 127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do
  ipt -A DOCKER-USER -s "$src" -j ACCEPT
done
# DOCKER-USER runs after DNAT. Match the original published destination port so a different
# host port mapped to container port 80/443 cannot inherit this ingress exception.
for dport in 80 443; do
  ipt -A DOCKER-USER -i "$PUB_IF" -p tcp -m conntrack --ctorigdstport "$dport" -j ACCEPT
done
ipt -A DOCKER-USER -i "$PUB_IF" -p udp -m conntrack --ctorigdstport 443 -j ACCEPT
ipt -A DOCKER-USER -i "$PUB_IF" -j DROP
ipt -A DOCKER-USER -j RETURN

ipt6 -N DOCKER-USER 2>/dev/null || true
ipt6 -F DOCKER-USER
ipt6 -A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
ipt6 -A DOCKER-USER -s fd7a:115c:a1e0::/48 -j ACCEPT
ipt6 -A DOCKER-USER -s ::1/128 -j ACCEPT
ipt6 -A DOCKER-USER -s fc00::/7 -j ACCEPT
for dport in 80 443; do
  ipt6 -A DOCKER-USER -i "$PUB_IF" -p tcp -m conntrack --ctorigdstport "$dport" -j ACCEPT
done
ipt6 -A DOCKER-USER -i "$PUB_IF" -p udp -m conntrack --ctorigdstport 443 -j ACCEPT
ipt6 -A DOCKER-USER -i "$PUB_IF" -j DROP
ipt6 -A DOCKER-USER -j RETURN
echo "docker-user-firewall applied on $(hostname) via $PUB_IF"
