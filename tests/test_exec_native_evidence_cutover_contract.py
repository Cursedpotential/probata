"""Production composition contracts for the native evidence cutover.

Byline: Codex · GPT-5 · 2026-08-18
Byline amendment: Codex · GPT-5.6-Sol · 2026-08-29 (plain Platform API host)
"""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAIN = ROOT / "server" / "api" / "main.py"
EXEC_MANIFEST = ROOT / "deploy" / "exec.yaml"


def test_platform_host_constructs_no_agno_knowledge_bases() -> None:
    """The production host has no framework-owned selectable Knowledge surface."""
    source = MAIN.read_text(encoding="utf-8")

    for retired_symbol in ("_KNOWLEDGE_BASES", "KnowledgeHandle", "create_knowledge", "evidence_knowledge"):
        assert retired_symbol not in source


def test_native_routes_are_registered_only_behind_the_activation_gate() -> None:
    """Disabled native evidence exposes no search route and no legacy substitute."""
    source = MAIN.read_text(encoding="utf-8")
    gate = "if native_runtime is not None:"
    registration = "register_native_evidence_search_routes(app, native_runtime=native_runtime)"

    gate_at = source.index(gate, source.index("register_ingest_routes(app, native_projector)"))
    registration_at = source.index(registration)
    assert gate_at < registration_at
    assert source[gate_at:registration_at].strip().endswith(gate)


def test_exec_manifest_requires_native_activation_inputs_and_blue_ports() -> None:
    """Coolify supplies activation/security/target values without checked-in secrets."""
    manifest = EXEC_MANIFEST.read_text(encoding="utf-8")

    required_inputs = {
        "NATIVE_EVIDENCE_ENABLED": "${NATIVE_EVIDENCE_ENABLED:?",
        "WEAVIATE_HTTP_HOST": "${WEAVIATE_HTTP_HOST:?",
        "WALK_PASS_SIGNING_KEY": "${WALK_PASS_SIGNING_KEY:?",
    }
    for key, interpolation in required_inputs.items():
        assert f"{key}: {interpolation}" in manifest

    assert "WEAVIATE_HTTP_PORT: ${WEAVIATE_HTTP_PORT:-8082}" in manifest
    assert "WEAVIATE_GRPC_PORT: ${WEAVIATE_GRPC_PORT:-50052}" in manifest
    assert "EVIDENCE_OPERATOR_SECURITY_KEY:" not in manifest
    assert "target: /run/secrets/evidence-operator-security-key" in manifest
    assert "source: /data/probata/secrets/platform/evidence-operator-security-key" in manifest
