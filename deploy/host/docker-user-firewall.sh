#!/usr/bin/env bash
# docker-user-firewall.sh — tailnet-only forwarding for every published container port.
# Byline: Claude Code · Fable 5.1 · 2026-09-07 (owner directive: nothing platform-side is reachable
# from the public internet; services bind the tailnet and talk over it).
#
# Why DOCKER-USER: Docker DNATs before FORWARD and bypasses ufw/INPUT for published ports
# (lessons recorded 2026-07-29, memory weaviate-public-exposure). Rules here are evaluated before
# Docker's own FORWARD rules. RELATED,ESTABLISHED must be first or container replies die.
# Effect: anything arriving on the public NIC ($PUB_IF) for a container is dropped unless it is a
# reply to a connection the container opened. Tailnet (100.64/10, fd7a:115c:a1e0::/48), loopback and
# docker-internal ranges are allowed. Host-level INPUT (sshd 22, tailscaled UDP) is untouched.
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
ipt -A DOCKER-USER -i "$PUB_IF" -j DROP
ipt -A DOCKER-USER -j RETURN

ipt6 -N DOCKER-USER 2>/dev/null || true
ipt6 -F DOCKER-USER
ipt6 -A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
ipt6 -A DOCKER-USER -s fd7a:115c:a1e0::/48 -j ACCEPT
ipt6 -A DOCKER-USER -s ::1/128 -j ACCEPT
ipt6 -A DOCKER-USER -s fc00::/7 -j ACCEPT
ipt6 -A DOCKER-USER -i "$PUB_IF" -j DROP
ipt6 -A DOCKER-USER -j RETURN
echo "docker-user-firewall applied on $(hostname) via $PUB_IF"
