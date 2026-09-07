# Byline amendment: Codex · GPT-5 · 2026-08-18 (combined-change hygiene)
"""Workspace-level guardrails for the disposable Surreal surface.

Byline: Codex · GPT-5 · 2026-08-16
"""

from pathlib import Path

ROOT = Path(__file__).parents[1]


def test_new_compose_is_isolated_and_legacy_compose_is_not_reused() -> None:
    compose = (ROOT / "deploy/compose.surreal-phase1.yaml").read_text(encoding="utf-8")
    assert "data-surreal-phase1-t0-r1" in compose
    assert "/data/probata/experiments/phase1-surreal-t0-r1" in compose
    assert "phase1-surreal-t0-r1" in compose
    assert "compose.data-surreal.yaml" not in compose
    assert "/data/probata/volumes/surrealdb" not in compose
    assert "100.119.96.29" not in compose
    assert "external: true" not in compose
    assert "--allow-rpc=attach,detach,version,signin,use,query,authenticate,info,invalidate" in compose
    assert "--allow-rpc" in compose
    assert "--allow-rpc=" in compose
    assert "t0_slice_r1_restore" not in compose


def test_workbench_incorporates_surrealdb_studio_without_credentials() -> None:
    page = (ROOT / "modules/workbench/web/src/app/surreal/page.tsx").read_text(encoding="utf-8")
    sidebar = (ROOT / "modules/workbench/web/src/components/layout/app-sidebar.tsx").read_text(encoding="utf-8")
    assert "SurrealDB Studio" in page
    assert "https://studio.surrealdb.com" in page
    assert "projection, not authority" in page.lower()
    assert "SURREALDB_PASS" not in page
    assert "100.119.96.29" not in page
    assert 'href: "/surreal"' in sidebar


def test_runner_wires_resume_rewalk_and_restore_parity_without_legacy_target() -> None:
    runner = (ROOT / "deploy/docker/surreal-phase1-runner/src/horizon_surreal_phase1/runner.py").read_text(
        encoding="utf-8"
    )
    assert "walk_checkpoint" in runner
    assert "revision=REVISION_1" in runner
    assert "revision=REVISION_2" in runner
    assert "healthy_resume_same_identity" in runner
    assert 'snapshot["state_hash"] == checkpoint["state_hash"]' in runner
    assert 'snapshot["trace_hash"] == checkpoint["trace_hash"]' in runner
    assert "linked_rewalk_exact" in runner
    assert "export_import_exact_parity" in runner
    assert "restored_retrieval_equal" in runner
    assert "compose.data-surreal.yaml" not in runner
    assert "/data/probata/volumes/surrealdb" not in runner
