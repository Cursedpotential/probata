"""Offline contract for the host's Docker forwarding boundary.

The public exception is deliberately limited to the original published ports
owned by Traefik. All other public container forwarding remains denied, while
tailnet and internal-network allowances remain ahead of the public drop.

Byline: Codex · GPT-5 · 2026-09-12
"""

from pathlib import Path


FIREWALL_PATH = Path("deploy/host/docker-user-firewall.sh")


def _lines() -> list[str]:
    return FIREWALL_PATH.read_text(encoding="utf-8").splitlines()


def _index(lines: list[str], exact: str) -> int:
    return lines.index(exact)


def test_public_traefik_exceptions_precede_ipv4_default_drop() -> None:
    lines = _lines()
    drop = _index(lines, 'ipt -A DOCKER-USER -i "$PUB_IF" -j DROP')

    assert _index(lines, "for dport in 80 443; do") < drop
    assert _index(
        lines,
        '  ipt -A DOCKER-USER -i "$PUB_IF" -p tcp -m conntrack --ctorigdstport "$dport" -j ACCEPT',
    ) < drop
    assert _index(
        lines,
        'ipt -A DOCKER-USER -i "$PUB_IF" -p udp -m conntrack --ctorigdstport 443 -j ACCEPT',
    ) < drop


def test_public_traefik_exceptions_precede_ipv6_default_drop() -> None:
    lines = _lines()
    drop = _index(lines, 'ipt6 -A DOCKER-USER -i "$PUB_IF" -j DROP')

    assert _index(
        lines,
        '  ipt6 -A DOCKER-USER -i "$PUB_IF" -p tcp -m conntrack --ctorigdstport "$dport" -j ACCEPT',
    ) < drop
    assert _index(
        lines,
        'ipt6 -A DOCKER-USER -i "$PUB_IF" -p udp -m conntrack --ctorigdstport 443 -j ACCEPT',
    ) < drop


def test_exception_matches_original_public_port_not_post_dnat_container_port() -> None:
    text = FIREWALL_PATH.read_text(encoding="utf-8")

    assert "--ctorigdstport" in text
    assert '-i "$PUB_IF" -p tcp --dport' not in text
    assert '-i "$PUB_IF" -p udp --dport' not in text


def test_tailnet_allowance_remains_before_public_drop() -> None:
    lines = _lines()
    tailnet = _index(
        lines,
        "for src in 100.64.0.0/10 127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do",
    )
    drop = _index(lines, 'ipt -A DOCKER-USER -i "$PUB_IF" -j DROP')

    assert tailnet < drop
