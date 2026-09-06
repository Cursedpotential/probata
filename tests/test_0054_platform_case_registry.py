"""Static and optional database-backed contract tests for migration 0054.

Byline: Codex · GPT-5.6-Sol · 2026-08-30.
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SQL = (ROOT / "sql" / "0054_platform_case_registry.sql").read_text(encoding="utf-8")


def test_0054_is_platform_only_narrow_and_receipted() -> None:
    assert "current_database() <> 'platform'" in SQL
    assert "SET LOCAL ROLE platform_admin" in SQL
    assert SQL.count("CREATE TABLE") == 4
    for table in ("analysis.matter", "analysis.court_case", "analysis.matter_knowledge_partition"):
        assert f"CREATE TABLE IF NOT EXISTS {table}" in SQL
    assert "CREATE TABLE analysis.case_registry_import_receipt" in SQL
    for forbidden in ("evidence.", "working.", "ops.", "INSERT INTO analysis.matter", "Primary matter"):
        assert forbidden not in SQL


def test_0054_enforces_both_uiw_scope_boundaries() -> None:
    for marker in (
        "source_version_matter_case_pair_check",
        "source_version_court_case_scope_fk",
        "proffer_source_context_court_case_scope_fk",
        "FOREIGN KEY (court_case_id, matter_id)",
        "REFERENCES analysis.court_case(id, matter_id)",
    ):
        assert marker in SQL


def test_0054_has_bounded_runtime_grants() -> None:
    assert "GRANT SELECT ON" in SQL
    assert "GRANT USAGE ON SCHEMA analysis TO platform_runtime" in SQL
    assert "GRANT ALL" not in SQL
    assert "GRANT DELETE" not in SQL
    assert "has_schema_privilege('platform_runtime', 'analysis', 'CREATE')" in SQL
    assert "REVOKE ALL ON" in SQL
    assert "FROM agno_app" in SQL


def test_0054_adopts_existing_0030_registry_without_duplicate_triggers() -> None:
    assert "migration 0054 refuses mismatched or additional canonical registry rows" in SQL
    assert "analysis.set_case_management_updated_at" in SQL
    assert "matter_set_updated_at" in SQL
    assert "court_case_set_updated_at" in SQL
    assert "touch_case_registry_updated_at" not in SQL


@pytest.mark.integration
def test_0054_live_catalog_when_test_dsn_is_explicit() -> None:
    dsn = os.getenv("PLATFORM_0054_TEST_DSN")
    if not dsn:
        pytest.skip("PLATFORM_0054_TEST_DSN is not set; no disposable migrated database was authorized")
    import psycopg

    with psycopg.connect(dsn) as conn:
        row = conn.execute(
            """SELECT current_database(), to_regclass('analysis.matter') IS NOT NULL,
                      to_regclass('analysis.court_case') IS NOT NULL,
                      to_regclass('analysis.matter_knowledge_partition') IS NOT NULL"""
        ).fetchone()
    assert row == ("platform", True, True, True)
