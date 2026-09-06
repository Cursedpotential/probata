"""Rollback-only validation for migration 0054 against database ``platform``.

Authentication is delegated to a libpq service/passfile; this script accepts no
password argument and never prints connection material.

Byline: Codex · GPT-5.6-Sol · 2026-08-30.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from datetime import date, datetime
from pathlib import Path
from typing import Final
from uuid import UUID

import psycopg

ROOT: Final = Path(__file__).resolve().parent.parent
MIGRATION: Final = ROOT / "sql" / "0054_platform_case_registry.sql"
MIGRATION_ID: Final = "0054"
MIGRATION_LABEL: Final = "0054_platform_case_registry"
DDL_URI: Final = "sql/0054_platform_case_registry.sql"
APPLIES_TO: Final = "analysis case registry and context UIW matter scope"
TARGET_DATABASE: Final = "platform"
DEFAULT_SERVICE: Final = "platform-migration"
AUTHORITATIVE_MATTER_ID: Final = "01a03136-c5cc-71c7-ac77-5c00a29a2ea8"
AUTHORITATIVE_COURT_CASE_ID: Final = "01a03136-c5cc-76f9-98df-702058d423d9"
SOURCE_MIGRATION_URI: Final = "sql/0030_matter_case_foundation.sql"
SOURCE_MIGRATION_SHA256: Final = "b19959119c0f040adcdc442aa7772503fd2d1439a90b1565eaa6c17e0883eb70"
SOURCE_GIT_COMMIT: Final = "97f48b172b1d31aa5a0005b45170d72af1299773"
PAYLOAD_SCHEMA_VERSION: Final = "0030-platform-registry-handoff-v1"
PAYLOAD_BYTE_LENGTH: Final = 1075
CANONICAL_PAYLOAD_SHA256: Final = "8e0a8e2d86027add31f9470976d1378e039d6efb5312ecae4cfec0ebd10690e6"
API_PAYLOAD_SHA256: Final = "cd370f6c9c00e620f39f283e2d0d7d1a83a463b14097b99537b886d438618a6d"

REPLAY_FILES: Final[tuple[tuple[str, Path], ...]] = (
    ("0000_platform_foundation", ROOT / "sql" / "bootstrap" / "platform_foundation.sql"),
    ("0036", ROOT / "sql" / "0036_context_import_foundation.sql"),
    ("0037", ROOT / "sql" / "0037_platform_runtime_connect.sql"),
    ("0038", ROOT / "sql" / "0038_platform_runtime_schema_version_probe.sql"),
    ("0039", ROOT / "sql" / "0039_context_source_retention_lock.sql"),
    ("0042", ROOT / "sql" / "0042_context_hash_bytea_slice.sql"),
    ("0048", ROOT / "sql" / "0048_context_fingerprint_uiw_repair.sql"),
    ("0050", ROOT / "sql" / "0050_uiw_preview_projection_store.sql"),
    ("0051", ROOT / "sql" / "0051_uiw_repair_activity_store.sql"),
    ("0053", ROOT / "sql" / "0053_uiw_source_context_revision.sql"),
    ("0054", MIGRATION),
)

# Live platform truth predates foundation/0048 ledger receipts. Those two
# contracts are admitted only through exact catalog/function checks below;
# disposable replay still records the complete explicit allowlist.
LIVE_LEDGER_FILES: Final[tuple[tuple[str, Path], ...]] = tuple(
    item for item in REPLAY_FILES[:-1] if item[0] not in {"0000_platform_foundation", "0048"}
)

SCOPE_FKS: Final[tuple[tuple[str, str, str, tuple[str, ...], tuple[str, ...]], ...]] = (
    ("context.source_version", "source_version_matter_fk", "registry.matter", ("matter_id",), ("id",)),
    (
        "context.source_version",
        "source_version_court_case_scope_fk",
        "registry.court_case",
        ("court_case_id", "matter_id"),
        ("id", "matter_id"),
    ),
    (
        "context.source_version",
        "source_version_source_context_scope_fk",
        "context.proffer_source_context_revision",
        ("source_context_ref", "matter_id", "court_case_id"),
        ("source_context_ref", "matter_id", "court_case_id"),
    ),
    (
        "context.proffer_source_context_revision",
        "proffer_source_context_matter_fk",
        "registry.matter",
        ("matter_id",),
        ("id",),
    ),
    (
        "context.proffer_source_context_revision",
        "proffer_source_context_court_case_scope_fk",
        "registry.court_case",
        ("court_case_id", "matter_id"),
        ("id", "matter_id"),
    ),
)


def connection_string(service: str, database: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", service):
        raise ValueError("libpq service name contains unsupported characters")
    if database != TARGET_DATABASE:
        raise ValueError("migration 0054 may target only database 'platform'")
    return f"service={service} dbname={database}"


def strip_transaction_control(source: str) -> str:
    return re.sub(r"(?im)^\s*(BEGIN|COMMIT)\s*;\s*$", "", source)


def migration_hash(path: Path) -> bytes:
    return hashlib.sha256(path.read_bytes()).digest()


def assert_expand_prestate(cursor: psycopg.Cursor[object]) -> None:
    cursor.execute("SELECT count(*) FROM public.schema_version WHERE migration_id='0043' AND status='active'")
    if int((cursor.fetchone() or (0,))[0]) != 0:
        raise RuntimeError("legacy migration 0043 is active; 0054 expansion is refused")
    cursor.execute(
        """SELECT count(*) FROM information_schema.columns WHERE table_schema='context'
           AND table_name='source_version' AND column_name IN ('matter_id','court_case_id')"""
    )
    if int((cursor.fetchone() or (0,))[0]) != 0:
        raise RuntimeError("pre-existing source_version matter/case columns require manual reconciliation")
    cursor.execute(
        """SELECT count(*) FROM pg_constraint WHERE conname=ANY(%s)""",
        ([name for _, name, _, _, _ in SCOPE_FKS] + ["source_version_source_context_scope_check"],),
    )
    if int((cursor.fetchone() or (0,))[0]) != 0:
        raise RuntimeError("pre-existing 0054 constraint identity requires manual reconciliation")


def assert_prerequisite_ledger(cursor: psycopg.Cursor[object]) -> None:
    expected = {migration_id: migration_hash(path) for migration_id, path in LIVE_LEDGER_FILES}
    cursor.execute(
        """SELECT migration_id, ddl_hash FROM public.schema_version
           WHERE migration_id = ANY(%s) AND status = 'active'""",
        (list(expected),),
    )
    actual = {str(row[0]): bytes(row[1]) for row in cursor.fetchall()}
    if actual != expected:
        raise RuntimeError("0054 prerequisite ledger is incomplete or does not match repository SHA-256 values")

    cursor.execute(
        """SELECT column_name,data_type FROM information_schema.columns
           WHERE table_schema='public' AND table_name='schema_version'
             AND column_name=ANY(%s)""",
        (["migration_id", "ddl_hash", "status", "created_by"],),
    )
    if {str(row[0]) for row in cursor.fetchall()} != {"migration_id", "ddl_hash", "status", "created_by"}:
        raise RuntimeError("platform foundation ledger shape is incomplete")
    cursor.execute(
        """SELECT conname FROM pg_constraint WHERE conrelid=ANY(%s::regclass[])
           AND conname=ANY(%s) AND convalidated""",
        (
            ["context.raw_record_identity", "context.hash_batch", "context.hash_manifest", "context.hash_receipt"],
            [
                "raw_record_context_fingerprint_canon_check",
                "hash_batch_context_kind_check",
                "hash_manifest_context_kind_check",
                "hash_receipt_context_kind_check",
            ],
        ),
    )
    if len(cursor.fetchall()) != 4:
        raise RuntimeError("unledgered 0048 contract is not exactly present in the live schema")


def assert_constraint_identity(cursor: psycopg.Cursor[object], *, validated: bool) -> None:
    for relation, name, referenced, columns, referenced_columns in SCOPE_FKS:
        cursor.execute(
            """SELECT c.conrelid::regclass::text,c.confrelid::regclass::text,c.contype,c.convalidated,c.confdeltype,
                      ARRAY(SELECT a.attname FROM unnest(c.conkey) WITH ORDINALITY k(attnum,ord)
                            JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.attnum ORDER BY k.ord),
                      ARRAY(SELECT a.attname FROM unnest(c.confkey) WITH ORDINALITY k(attnum,ord)
                            JOIN pg_attribute a ON a.attrelid=c.confrelid AND a.attnum=k.attnum ORDER BY k.ord)
               FROM pg_constraint c WHERE c.conrelid=%s::regclass AND c.conname=%s""",
            (relation, name),
        )
        rows = cursor.fetchall()
        expected = (relation, referenced, "f", validated, "r", list(columns), list(referenced_columns))
        if len(rows) != 1 or tuple(rows[0]) != expected:
            raise RuntimeError(f"constraint identity mismatch for {relation}.{name}")
    cursor.execute(
        """SELECT conname,conrelid::regclass::text,contype,convalidated,pg_get_constraintdef(oid)
           FROM pg_constraint
           WHERE conrelid='context.source_version'::regclass
             AND conname=ANY(ARRAY['source_version_matter_case_pair_check',
                                   'source_version_source_context_scope_check'])
           ORDER BY conname"""
    )
    checks = cursor.fetchall()
    expected_check_validation = {
        "source_version_matter_case_pair_check": True,
        "source_version_source_context_scope_check": validated,
    }
    if len(checks) != 2 or any(
        row[1:3] != ("context.source_version", "c") or bool(row[3]) is not expected_check_validation.get(str(row[0]))
        for row in checks
    ):
        raise RuntimeError("source_version scope checks are missing or unvalidated")
    check_defs = {str(row[0]): str(row[4]) for row in checks}
    if "matter_id IS NULL" not in check_defs["source_version_matter_case_pair_check"] or any(
        token not in check_defs["source_version_source_context_scope_check"]
        for token in ("source_context_ref IS NULL", "matter_id IS NOT NULL", "court_case_id IS NOT NULL")
    ):
        raise RuntimeError("source_version scope check definitions are not exact")
    cursor.execute(
        """SELECT c.contype,c.convalidated,
                  ARRAY(SELECT a.attname FROM unnest(c.conkey) WITH ORDINALITY k(attnum,ord)
                        JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.attnum ORDER BY k.ord)
           FROM pg_constraint c
           WHERE c.conrelid='context.proffer_source_context_revision'::regclass
             AND c.conname='proffer_source_context_scope_key'"""
    )
    if cursor.fetchall() != [("u", True, ["source_context_ref", "matter_id", "court_case_id"])]:
        raise RuntimeError("UIW source-context composite identity is missing or malformed")


def validate_scope_constraints(cursor: psycopg.Cursor[object]) -> None:
    cursor.execute("SET LOCAL ROLE platform_admin")
    for relation, name, _, _, _ in SCOPE_FKS:
        cursor.execute(f"ALTER TABLE {relation} VALIDATE CONSTRAINT {name}")
    cursor.execute("ALTER TABLE context.source_version VALIDATE CONSTRAINT source_version_source_context_scope_check")


def assert_scope_consistency(cursor: psycopg.Cursor[object]) -> None:
    cursor.execute(
        """SELECT count(*) FROM context.source_version sv
           LEFT JOIN context.proffer_source_context_revision scr
             ON scr.source_context_ref=sv.source_context_ref
            AND scr.matter_id=sv.matter_id AND scr.court_case_id=sv.court_case_id
           WHERE (sv.matter_id IS NULL) <> (sv.court_case_id IS NULL)
              OR (sv.source_context_ref IS NOT NULL AND scr.source_context_ref IS NULL)"""
    )
    if int((cursor.fetchone() or (0,))[0]) != 0:
        raise RuntimeError("source_version/UIW source-context scope is inconsistent")


def assert_schema(cursor: psycopg.Cursor[object]) -> None:
    cursor.execute("SELECT current_database(), current_user")
    database, current_user = cursor.fetchone() or (None, None)
    if database != TARGET_DATABASE:
        raise RuntimeError(f"refusing database {database!r}; platform is required")
    cursor.execute("SELECT pg_has_role(current_user, 'platform_admin', 'MEMBER')")
    if not bool((cursor.fetchone() or (False,))[0]):
        raise RuntimeError(f"session role {current_user!r} cannot assume platform_admin")

    cursor.execute(
        """SELECT c.relname, pg_get_userbyid(c.relowner)
           FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
           WHERE n.nspname='analysis' AND c.relkind='r'
             AND c.relname = ANY(%s) ORDER BY c.relname""",
        (["matter", "court_case", "matter_knowledge_partition", "case_registry_import_receipt"],),
    )
    rows = cursor.fetchall()
    if rows != [
        ("case_registry_import_receipt", "platform_admin"),
        ("court_case", "platform_admin"),
        ("matter", "platform_admin"),
        ("matter_knowledge_partition", "platform_admin"),
    ]:
        raise RuntimeError("0054 requires exactly four platform_admin-owned case-registry tables")

    required_columns = {
        ("source_version", "matter_id"),
        ("source_version", "court_case_id"),
        ("proffer_source_context_revision", "matter_id"),
        ("proffer_source_context_revision", "court_case_id"),
    }
    cursor.execute(
        """SELECT table_name, column_name FROM information_schema.columns
           WHERE table_schema='context'
             AND table_name = ANY(%s) AND column_name = ANY(%s)""",
        (["source_version", "proffer_source_context_revision"], ["matter_id", "court_case_id"]),
    )
    if {(str(a), str(b)) for a, b in cursor.fetchall()} != required_columns:
        raise RuntimeError("0054 context matter/case columns are incomplete")

    assert_constraint_identity(cursor, validated=True)
    assert_scope_consistency(cursor)

    cursor.execute(
        """SELECT has_schema_privilege('platform_runtime','analysis','USAGE'),
                  has_schema_privilege('platform_runtime','analysis','CREATE'),
                  has_table_privilege('platform_runtime','registry.matter','SELECT'),
                  has_table_privilege('platform_runtime','registry.matter','INSERT'),
                  has_table_privilege('platform_runtime','registry.matter','UPDATE'),
                  has_table_privilege('platform_runtime','registry.matter','DELETE'),
                  has_table_privilege('platform_runtime','public.schema_version','INSERT'),
                  CASE WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname='agno_app')
                       THEN has_table_privilege('agno_app','registry.matter','INSERT')
                         OR has_table_privilege('agno_app','registry.matter','UPDATE')
                         OR has_table_privilege('agno_app','registry.matter','DELETE')
                         OR has_table_privilege('agno_app','registry.court_case','INSERT')
                         OR has_table_privilege('agno_app','registry.court_case','UPDATE')
                         OR has_table_privilege('agno_app','registry.court_case','DELETE')
                         OR has_table_privilege('agno_app','analysis.matter_knowledge_partition','INSERT')
                         OR has_table_privilege('agno_app','analysis.matter_knowledge_partition','UPDATE')
                         OR has_table_privilege('agno_app','analysis.matter_knowledge_partition','DELETE')
                       ELSE false END"""
    )
    usage, create, select, insert, update, delete, ledger_insert, agno_mutation = cursor.fetchone() or (False,) * 8
    if not usage or create or not select or insert or update or delete or ledger_insert or agno_mutation:
        raise RuntimeError("0054 runtime grants are not bounded")
    cursor.execute(
        """SELECT count(*) FROM pg_proc p,
                  LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) acl
           WHERE p.oid='analysis.set_case_management_updated_at()'::regprocedure
             AND acl.grantee=0 AND acl.privilege_type='EXECUTE'"""
    )
    if int((cursor.fetchone() or (0,))[0]) != 0:
        raise RuntimeError("case-registry trigger function must not be executable by PUBLIC")
    cursor.execute(
        """SELECT count(*) FROM analysis.case_registry_import_receipt
           WHERE matter_id=%s::uuid AND court_case_id=%s::uuid
             AND source_migration_uri=%s AND encode(source_migration_sha256,'hex')=%s
             AND source_git_commit=%s AND payload_schema_version=%s AND payload_byte_length=%s
             AND encode(canonical_payload_sha256,'hex')=%s AND encode(api_payload_sha256,'hex')=%s
             AND approved_by='owner' AND approved_on=DATE '2026-08-23'""",
        (
            AUTHORITATIVE_MATTER_ID,
            AUTHORITATIVE_COURT_CASE_ID,
            SOURCE_MIGRATION_URI,
            SOURCE_MIGRATION_SHA256,
            SOURCE_GIT_COMMIT,
            PAYLOAD_SCHEMA_VERSION,
            PAYLOAD_BYTE_LENGTH,
            CANONICAL_PAYLOAD_SHA256,
            API_PAYLOAD_SHA256,
        ),
    )
    if int((cursor.fetchone() or (0,))[0]) != 1:
        raise RuntimeError("0054 requires one immutable receipt for the authoritative matter/court-case identity")


def load_registry_manifest(path: Path) -> tuple[dict[str, object], bytes]:
    raw = path.read_bytes()
    manifest = json.loads(raw.decode("utf-8"))
    if not isinstance(manifest, dict) or set(manifest) != {
        "source",
        "matter",
        "court_case",
        "partition",
        "approved_by",
        "approved_on",
        "imported_by",
    }:
        raise ValueError("registry import manifest has unexpected top-level fields")
    source = manifest["source"]
    matter = manifest["matter"]
    court_case = manifest["court_case"]
    partition = manifest["partition"]
    if not all(isinstance(value, dict) for value in (source, matter, court_case, partition)):
        raise ValueError("registry import manifest sections must be objects")
    expected = {
        "source": {
            "migration_uri",
            "migration_sha256",
            "git_commit",
            "payload_schema_version",
            "payload_byte_length",
            "canonical_payload_sha256",
            "api_payload_sha256",
            "observed_at",
        },
        "matter": {"id", "title", "description", "status", "created_by", "created_at", "updated_at"},
        "court_case": {
            "id",
            "matter_id",
            "caption",
            "docket_number",
            "court_name",
            "jurisdiction",
            "case_type",
            "status",
            "filed_on",
            "closed_on",
            "is_primary",
            "created_by",
            "created_at",
            "updated_at",
        },
        "partition": {"partition_key", "matter_id", "default_court_case_id", "created_by", "created_at"},
    }
    for section, keys in expected.items():
        if set(manifest[section]) != keys:
            raise ValueError(f"registry import {section} fields are incomplete or unexpected")
    UUID(str(matter["id"]))
    UUID(str(court_case["id"]))
    if str(matter["id"]) != AUTHORITATIVE_MATTER_ID or str(court_case["id"]) != AUTHORITATIVE_COURT_CASE_ID:
        raise ValueError("registry import does not contain the owner-approved authoritative identities")
    if str(court_case["matter_id"]) != str(matter["id"]):
        raise ValueError("court_case.matter_id does not match matter.id")
    if str(partition["matter_id"]) != str(matter["id"]) or str(partition["default_court_case_id"]) != str(
        court_case["id"]
    ):
        raise ValueError("partition scope does not match the authoritative matter/court case")
    for value in (
        source["observed_at"],
        matter["created_at"],
        matter["updated_at"],
        court_case["created_at"],
        court_case["updated_at"],
        partition["created_at"],
    ):
        datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    date.fromisoformat(str(manifest["approved_on"]))
    for value in (court_case["filed_on"], court_case["closed_on"]):
        if value is not None:
            date.fromisoformat(str(value))
    if source["migration_uri"] != SOURCE_MIGRATION_URI or source["migration_sha256"] != SOURCE_MIGRATION_SHA256:
        raise ValueError("registry import source migration provenance is not authoritative")
    expected_provenance = (
        SOURCE_GIT_COMMIT,
        PAYLOAD_SCHEMA_VERSION,
        PAYLOAD_BYTE_LENGTH,
        CANONICAL_PAYLOAD_SHA256,
        API_PAYLOAD_SHA256,
    )
    actual_provenance = (
        source["git_commit"],
        source["payload_schema_version"],
        source["payload_byte_length"],
        source["canonical_payload_sha256"],
        source["api_payload_sha256"],
    )
    if actual_provenance != expected_provenance:
        raise ValueError("canonical registry payload provenance does not match live proof")
    for value_name, value in (
        ("approved_by", manifest["approved_by"]),
        ("imported_by", manifest["imported_by"]),
    ):
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"{value_name} is required")
    if manifest["approved_by"] != "owner" or manifest["approved_on"] != "2026-08-23":
        raise ValueError("owner approval provenance must match the tracked 0030 ruling")
    return manifest, hashlib.sha256(raw).digest()


def import_registry(cursor: psycopg.Cursor[object], manifest: dict[str, object], manifest_hash: bytes) -> str:
    source = manifest["source"]
    matter = manifest["matter"]
    court_case = manifest["court_case"]
    partition = manifest["partition"]
    assert (
        isinstance(source, dict)
        and isinstance(matter, dict)
        and isinstance(court_case, dict)
        and isinstance(partition, dict)
    )
    cursor.execute("SET LOCAL ROLE platform_admin")
    cursor.execute(
        "SELECT matter_id::text,court_case_id::text,partition_key,source_migration_uri,encode(source_migration_sha256,'hex'),source_git_commit,payload_schema_version,payload_byte_length,encode(canonical_payload_sha256,'hex'),encode(api_payload_sha256,'hex'),approved_by,approved_on,imported_by FROM analysis.case_registry_import_receipt WHERE manifest_sha256=%s",
        (manifest_hash,),
    )
    receipt = cursor.fetchone()
    expected_receipt = (
        str(matter["id"]),
        str(court_case["id"]),
        partition["partition_key"],
        source["migration_uri"],
        source["migration_sha256"],
        source["git_commit"],
        source["payload_schema_version"],
        source["payload_byte_length"],
        source["canonical_payload_sha256"],
        source["api_payload_sha256"],
        manifest["approved_by"],
        date.fromisoformat(str(manifest["approved_on"])),
        manifest["imported_by"],
    )
    if receipt is not None:
        if tuple(receipt) != expected_receipt:
            raise RuntimeError("existing registry import receipt conflicts with the manifest")
        return "NO-OP"
    cursor.execute(
        "SELECT (SELECT count(*) FROM registry.matter),(SELECT count(*) FROM registry.court_case),(SELECT count(*) FROM analysis.matter_knowledge_partition),(SELECT count(*) FROM analysis.case_registry_import_receipt)"
    )
    counts = tuple(cursor.fetchone() or ())
    if counts not in {(0, 0, 0, 0), (1, 1, 1, 0)}:
        raise RuntimeError("registry has mismatched/additional or partially receipted rows")
    if counts == (0, 0, 0, 0):
        cursor.execute(
            """INSERT INTO registry.matter(id,title,description,status,created_by,created_at,updated_at)
               VALUES(%s,%s,%s,%s,%s,%s,%s)""",
            tuple(
                matter[key]
                for key in ("id", "title", "description", "status", "created_by", "created_at", "updated_at")
            ),
        )
        cursor.execute(
            """INSERT INTO registry.court_case(id,matter_id,caption,docket_number,court_name,jurisdiction,case_type,status,filed_on,closed_on,is_primary,created_by,created_at,updated_at)
               VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
            tuple(
                court_case[key]
                for key in (
                    "id",
                    "matter_id",
                    "caption",
                    "docket_number",
                    "court_name",
                    "jurisdiction",
                    "case_type",
                    "status",
                    "filed_on",
                    "closed_on",
                    "is_primary",
                    "created_by",
                    "created_at",
                    "updated_at",
                )
            ),
        )
        cursor.execute(
            """INSERT INTO analysis.matter_knowledge_partition(partition_key,matter_id,default_court_case_id,created_by,created_at)
               VALUES(%s,%s,%s,%s,%s)""",
            tuple(
                partition[key]
                for key in ("partition_key", "matter_id", "default_court_case_id", "created_by", "created_at")
            ),
        )
    else:
        cursor.execute(
            """SELECT id::text,title,description,status,created_by,created_at,updated_at
               FROM registry.matter"""
        )
        actual_matter = tuple(cursor.fetchone() or ())
        expected_matter = (
            str(matter["id"]),
            matter["title"],
            matter["description"],
            matter["status"],
            matter["created_by"],
            datetime.fromisoformat(str(matter["created_at"]).replace("Z", "+00:00")),
            datetime.fromisoformat(str(matter["updated_at"]).replace("Z", "+00:00")),
        )
        cursor.execute(
            """SELECT id::text,matter_id::text,caption,docket_number,court_name,jurisdiction,case_type,status,
                      filed_on,closed_on,is_primary,created_by,created_at,updated_at FROM registry.court_case"""
        )
        actual_case = tuple(cursor.fetchone() or ())
        expected_case = (
            str(court_case["id"]),
            str(court_case["matter_id"]),
            court_case["caption"],
            court_case["docket_number"],
            court_case["court_name"],
            court_case["jurisdiction"],
            court_case["case_type"],
            court_case["status"],
            date.fromisoformat(str(court_case["filed_on"])) if court_case["filed_on"] is not None else None,
            date.fromisoformat(str(court_case["closed_on"])) if court_case["closed_on"] is not None else None,
            court_case["is_primary"],
            court_case["created_by"],
            datetime.fromisoformat(str(court_case["created_at"]).replace("Z", "+00:00")),
            datetime.fromisoformat(str(court_case["updated_at"]).replace("Z", "+00:00")),
        )
        cursor.execute(
            """SELECT partition_key,matter_id::text,default_court_case_id::text,created_by,created_at
               FROM analysis.matter_knowledge_partition"""
        )
        actual_partition = tuple(cursor.fetchone() or ())
        expected_partition = (
            partition["partition_key"],
            str(partition["matter_id"]),
            str(partition["default_court_case_id"]),
            partition["created_by"],
            datetime.fromisoformat(str(partition["created_at"]).replace("Z", "+00:00")),
        )
        if (actual_matter, actual_case, actual_partition) != (expected_matter, expected_case, expected_partition):
            raise RuntimeError("existing canonical registry rows do not exactly match the attestation manifest")
    cursor.execute(
        """INSERT INTO analysis.case_registry_import_receipt
           (manifest_sha256,source_migration_uri,source_migration_sha256,source_git_commit,payload_schema_version,payload_byte_length,canonical_payload_sha256,api_payload_sha256,source_observed_at,matter_id,court_case_id,partition_key,approved_by,approved_on,imported_by)
           VALUES(%s,%s,decode(%s,'hex'),%s,%s,%s,decode(%s,'hex'),decode(%s,'hex'),%s,%s,%s,%s,%s,%s,%s)""",
        (
            manifest_hash,
            source["migration_uri"],
            source["migration_sha256"],
            source["git_commit"],
            source["payload_schema_version"],
            source["payload_byte_length"],
            source["canonical_payload_sha256"],
            source["api_payload_sha256"],
            source["observed_at"],
            matter["id"],
            court_case["id"],
            partition["partition_key"],
            manifest["approved_by"],
            manifest["approved_on"],
            manifest["imported_by"],
        ),
    )
    return "IMPORTED"


def backfill_source_version_scope(cursor: psycopg.Cursor[object]) -> None:
    cursor.execute("SET LOCAL ROLE platform_admin")
    cursor.execute(
        """SELECT count(*) FROM context.source_version sv
           JOIN context.proffer_source_context_revision scr ON scr.source_context_ref=sv.source_context_ref
           WHERE sv.source_context_ref IS NOT NULL
             AND (sv.matter_id IS NOT NULL OR sv.court_case_id IS NOT NULL)
             AND (sv.matter_id IS DISTINCT FROM scr.matter_id OR sv.court_case_id IS DISTINCT FROM scr.court_case_id)"""
    )
    if int((cursor.fetchone() or (0,))[0]) != 0:
        raise RuntimeError("pre-existing source_version scope conflicts with its source-context revision")
    cursor.execute(
        """UPDATE context.source_version sv SET matter_id=scr.matter_id,court_case_id=scr.court_case_id
           FROM context.proffer_source_context_revision scr
           WHERE sv.source_context_ref=scr.source_context_ref
             AND sv.matter_id IS NULL AND sv.court_case_id IS NULL"""
    )


def assert_cross_matter_rejected(cursor: psycopg.Cursor[object]) -> None:
    cursor.execute("SAVEPOINT scope_probe")
    try:
        cursor.execute("SAVEPOINT runtime_write_probe")
        cursor.execute("SET LOCAL ROLE platform_runtime")
        try:
            cursor.execute("INSERT INTO registry.matter(title,created_by) VALUES('forbidden','0054-validator')")
        except psycopg.errors.InsufficientPrivilege:
            cursor.execute("ROLLBACK TO SAVEPOINT runtime_write_probe")
        else:
            raise RuntimeError("platform_runtime unexpectedly wrote to the case registry")
        cursor.execute("SET LOCAL ROLE platform_admin")
        cursor.execute("INSERT INTO registry.matter(title,created_by) VALUES('probe-a','0054-validator') RETURNING id")
        matter_a = cursor.fetchone()[0]
        cursor.execute("INSERT INTO registry.matter(title,created_by) VALUES('probe-b','0054-validator') RETURNING id")
        matter_b = cursor.fetchone()[0]
        cursor.execute(
            """INSERT INTO registry.court_case(matter_id,caption,is_primary,created_by)
               VALUES(%s,'probe case',true,'0054-validator') RETURNING id""",
            (matter_a,),
        )
        case_a = cursor.fetchone()[0]
        cursor.execute("SAVEPOINT cross_scope")
        try:
            cursor.execute(
                """INSERT INTO analysis.matter_knowledge_partition
                   (partition_key,matter_id,default_court_case_id,created_by)
                   VALUES('invalid-cross-scope',%s,%s,'0054-validator')""",
                (matter_b, case_a),
            )
        except psycopg.errors.ForeignKeyViolation:
            cursor.execute("ROLLBACK TO SAVEPOINT cross_scope")
        else:
            raise RuntimeError("cross-matter case binding was accepted")
    finally:
        cursor.execute("ROLLBACK TO SAVEPOINT scope_probe")


def assert_ledger_entry(cursor: psycopg.Cursor[object], expected_hash: bytes) -> None:
    cursor.execute(
        """SELECT version_label, applies_to, ddl_uri, ddl_hash, created_by
           FROM public.schema_version WHERE migration_id=%s AND status='active'""",
        (MIGRATION_ID,),
    )
    rows = cursor.fetchall()
    expected = (MIGRATION_LABEL, APPLIES_TO, DDL_URI, expected_hash, "platform_admin")
    if rows != [expected]:
        raise RuntimeError("migration 0054 requires one exact active SHA-256 ledger receipt")


def main() -> int:
    parser = argparse.ArgumentParser(description="rollback-only validation for migration 0054")
    parser.add_argument("--service", default=DEFAULT_SERVICE)
    parser.add_argument("--database", default=TARGET_DATABASE)
    parser.add_argument("--registry-import", type=Path, required=True)
    args = parser.parse_args()
    dsn = connection_string(args.service, args.database)
    before_hash = migration_hash(MIGRATION)
    source = MIGRATION.read_text(encoding="utf-8")
    with psycopg.connect(dsn, connect_timeout=10) as conn:
        conn.autocommit = False
        cursor = conn.cursor()
        cursor.execute("SET LOCAL lock_timeout='5s'")
        cursor.execute("SET LOCAL statement_timeout='30s'")
        cursor.execute("SELECT pg_advisory_xact_lock(hashtext('validate-0054-platform-case-registry'))")
        assert_prerequisite_ledger(cursor)
        assert_expand_prestate(cursor)
        cursor.execute(strip_transaction_control(source))
        assert_constraint_identity(cursor, validated=False)
        manifest, manifest_hash = load_registry_manifest(args.registry_import)
        import_registry(cursor, manifest, manifest_hash)
        backfill_source_version_scope(cursor)
        validate_scope_constraints(cursor)
        assert_schema(cursor)
        assert_cross_matter_rejected(cursor)
        if migration_hash(MIGRATION) != before_hash:
            raise RuntimeError("migration 0054 changed during validation")
        conn.rollback()
    print(f"PASS: migration 0054 rollback validation; sha256={before_hash.hex()}; target=platform")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
