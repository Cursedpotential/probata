"""Static contract checks against THE database file (sql/bootstrap/schema_snapshot_<date>.sql).

Replaces the retired migration-text tests (tests/_stale/test_temporal_projection_sql_contract.py.retired-20260907):
the snapshot is the only DDL source (D-142 §3, 2026-09-06 18:51, D-152, 2026-09-07 07:24).
Byline: Claude Code · Fable 5.1 · 2026-09-07
"""

import re
from pathlib import Path

BOOTSTRAP = Path(__file__).resolve().parents[1] / "sql" / "bootstrap"


def _snapshot() -> str:
    files = sorted(BOOTSTRAP.glob("schema_snapshot_*.sql"))
    assert files, "no schema snapshot under sql/bootstrap"
    # DDL only: the header comments narrate the old names on purpose (history), so drop `--` lines.
    return "\n".join(line for line in files[-1].read_text(encoding="utf-8").splitlines() if not line.lstrip().startswith("--"))


def test_snapshot_has_the_ruled_shape() -> None:
    sql = _snapshot()
    assert "CREATE TABLE context.proffer_preview_binding" in sql
    assert "uiw_" not in sql, "uiw names must not reappear (D-140)"
    # word-bounded: ai.agno_approvals is a table that legitimately survives; the agno_app ROLE is what must be gone
    assert not re.search(r"\bagno_app\b", sql), "agno_app role is dead (owner 2026-09-06)"
    assert "CREATE TABLE reference.human_label (" in sql and "analysis.human_label" not in sql
    assert "CREATE TABLE working.normalized_record_chunk" in sql
    assert "CREATE TABLE raw.raw_sms" in sql


def test_intake_tables_default_to_context_fingerprints_not_custody_tags() -> None:
    sql = _snapshot()
    assert "DEFAULT 'h2-rawelement-v1'" not in sql, "intake tables must not default to a custody H-tag (D-124, D-149, D-152)"
    assert sql.count("DEFAULT 'context-rawrecord-fingerprint-v1'") >= 6


def test_no_numbered_migrations_remain_in_sql_root() -> None:
    root = BOOTSTRAP.parent
    assert not list(root.glob("0*.sql")), "numbered migrations are retired; edit the snapshot and rebuild"
