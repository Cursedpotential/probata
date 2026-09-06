"""Replay the explicit platform migration allowlist into an empty disposable PG18 database.

The target database must be named ``platform`` and dedicated to rehearsal. The
script never discovers migrations by glob and refuses any pre-existing active
ledger row. Authentication uses a libpq service/passfile, not a password flag.

Byline: Codex · GPT-5.6-Sol · 2026-08-30.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from uuid import uuid4

import psycopg

from validate_0054_live import (
    REPLAY_FILES,
    TARGET_DATABASE,
    assert_cross_matter_rejected,
    assert_constraint_identity,
    assert_schema,
    backfill_source_version_scope,
    connection_string,
    import_registry,
    load_registry_manifest,
    migration_hash,
    strip_transaction_control,
    validate_scope_constraints,
)


def _assert_empty_target(cursor: psycopg.Cursor[object]) -> None:
    cursor.execute("SELECT current_database()")
    if (cursor.fetchone() or (None,))[0] != TARGET_DATABASE:
        raise RuntimeError("replay target must be database platform")
    cursor.execute("SELECT to_regclass('public.schema_version')")
    ledger = (cursor.fetchone() or (None,))[0]
    if ledger is not None:
        cursor.execute("SELECT count(*) FROM public.schema_version WHERE status='active'")
        if int((cursor.fetchone() or (0,))[0]) != 0:
            raise RuntimeError("replay target already has active migration receipts")
    cursor.execute(
        """SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
           WHERE c.relkind='r' AND n.nspname IN ('context','analysis')"""
    )
    if int((cursor.fetchone() or (0,))[0]) != 0:
        raise RuntimeError("replay target already contains context/analysis tables")


def _ledger(cursor: psycopg.Cursor[object], migration_id: str, path: object, ddl_hash: bytes) -> None:
    ddl_uri = str(path).replace("\\", "/")
    marker = "/sql/"
    if marker in ddl_uri:
        ddl_uri = "sql/" + ddl_uri.split(marker, 1)[1]
    cursor.execute("SET LOCAL ROLE platform_admin")
    cursor.execute(
        """INSERT INTO public.schema_version
           (version_label,applies_to,ddl_uri,ddl_hash,migration_id,status,notes,created_by)
           VALUES(%s,%s,%s,%s,%s,'active',%s,current_user)""",
        (
            migration_id if migration_id.startswith("0000_") else path.stem,
            "database=platform; explicit replay allowlist",
            ddl_uri,
            ddl_hash,
            migration_id,
            "Replayed by scripts/rehearse_platform_migrations.py into a disposable PG18 platform database.",
        ),
    )


def _seed_preexisting_uiw_scope(cursor: psycopg.Cursor[object], manifest: dict[str, object]) -> None:
    matter = manifest["matter"]
    court_case = manifest["court_case"]
    assert isinstance(matter, dict) and isinstance(court_case, dict)
    source_id, version_id, context_ref = uuid4(), uuid4(), uuid4()
    cursor.execute("SET LOCAL ROLE context_owner")
    cursor.execute(
        """INSERT INTO context.source(id,source_key,provenance_class)
           VALUES(%s,%s,'first_party_authored')""",
        (source_id, f"0054-rehearsal-{source_id}"),
    )
    cursor.execute(
        """INSERT INTO context.proffer_source_context_revision
           (source_context_ref,request_id,revision,matter_id,court_case_id,source_ref,observed_source,
            assertions,change_reason,actor_subject_uid,actor_username,idempotency_key,content_digest,receipt_ref)
           VALUES(%s,%s,1,%s,%s,%s,'{}','{}','rehearsal','rehearsal','rehearsal',%s,decode(%s,'hex'),%s)""",
        (
            context_ref,
            f"0054-rehearsal-{version_id}",
            matter["id"],
            court_case["id"],
            str(version_id),
            f"0054-rehearsal-context-{context_ref}",
            "11" * 32,
            f"0054-rehearsal-receipt-{context_ref}",
        ),
    )
    cursor.execute(
        """INSERT INTO context.source_version
           (id,source_id,version_ordinal,workflow_id,submission_idempotency_key,declared_format,
            acquired_at,status,source_context_ref)
           VALUES(%s,%s,1,%s,%s,'json',now(),'registered',%s)""",
        (version_id, source_id, f"0054-rehearsal-{version_id}", f"0054-rehearsal-submit-{version_id}", context_ref),
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="replay the explicit platform migration allowlist")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--service", default="platform-migration-rehearsal")
    parser.add_argument("--database", default=TARGET_DATABASE)
    parser.add_argument("--registry-import", type=Path, required=True)
    args = parser.parse_args()
    if not args.apply:
        parser.error("refusing to rehearse without explicit --apply")
    dsn = connection_string(args.service, args.database)
    manifest, manifest_hash = load_registry_manifest(args.registry_import)

    with psycopg.connect(dsn, connect_timeout=10, autocommit=True) as conn:
        _assert_empty_target(conn.cursor())

    applied: list[tuple[str, bytes]] = []
    for migration_id, path in REPLAY_FILES:
        before = migration_hash(path)
        source = strip_transaction_control(path.read_text(encoding="utf-8"))
        with psycopg.connect(dsn, connect_timeout=10) as conn:
            conn.autocommit = False
            cursor = conn.cursor()
            cursor.execute("SET LOCAL lock_timeout='5s'")
            cursor.execute("SET LOCAL statement_timeout='120s'")
            cursor.execute("SELECT pg_advisory_xact_lock(hashtext('rehearse-platform-migrations'))")
            if migration_id == "0054":
                _seed_preexisting_uiw_scope(cursor, manifest)
            cursor.execute(source)
            if migration_hash(path) != before:
                raise RuntimeError(f"migration {migration_id} changed during replay")
            if migration_id == "0054":
                if import_registry(cursor, manifest, manifest_hash) != "IMPORTED":
                    raise RuntimeError("first registry import did not produce a receipt")
                backfill_source_version_scope(cursor)
                validate_scope_constraints(cursor)
                assert_constraint_identity(cursor, validated=True)
                assert_schema(cursor)
            _ledger(cursor, migration_id, path, before)
            conn.commit()
            applied.append((migration_id, before))

    with psycopg.connect(dsn, connect_timeout=10) as conn:
        cursor = conn.cursor()
        cursor.execute(
            "SELECT migration_id,ddl_hash FROM public.schema_version WHERE status='active' ORDER BY migration_id"
        )
        actual = [(str(row[0]), bytes(row[1])) for row in cursor.fetchall()]
        if actual != sorted(applied):
            raise RuntimeError("replay ledger does not exactly match the explicit allowlist and repository hashes")
        assert_schema(cursor)
        if import_registry(cursor, manifest, manifest_hash) != "NO-OP":
            raise RuntimeError("identical registry import retry was not an idempotent no-op")
        assert_cross_matter_rejected(cursor)
        cursor.execute("SAVEPOINT mismatch_negative")
        try:
            cursor.execute("SET LOCAL ROLE platform_admin")
            cursor.execute(
                "UPDATE context.source_version SET court_case_id=%s WHERE source_context_ref IS NOT NULL",
                (uuid4(),),
            )
        except psycopg.errors.ForeignKeyViolation:
            cursor.execute("ROLLBACK TO SAVEPOINT mismatch_negative")
        else:
            raise RuntimeError("source_version accepted a mismatched court-case scope")
        conn.rollback()

    summary = ",".join(migration_id for migration_id, _ in applied)
    print(f"PASS: explicit platform migration replay; target=platform; migrations={summary}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
