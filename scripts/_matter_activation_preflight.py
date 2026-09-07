"""Fail-closed, read-only activation preflight for the Matter MVP.

Byline: Codex · GPT-5 · 2026-08-15; native Weaviate amendment 2026-08-18;
Platform API bearer-file cutover 2026-08-29

The command never applies migrations, writes database rows, deploys services, or
prints secret values. Static mode verifies the release contract in the checkout.
Database mode validates a canonical PostgreSQL target without requiring deployed
services. Activation mode additionally requires credentials and live
Workbench/spine/Weaviate/Graphiti paths.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Literal, TypedDict, cast
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin
from urllib.request import Request, urlopen

from sqlalchemy import create_engine, text

Status = Literal["PASS", "FAIL", "BLOCKED"]
PROJECT_ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = tuple(range(26, 31))
REQUIRED_EXTENSIONS = frozenset({"pg_duckdb", "pgcrypto", "postgis", "vector"})
NATIVE_EVIDENCE_COLLECTION_VERSION = 1
NATIVE_EVIDENCE_COLLECTION = "EvidenceChunkV1"
NATIVE_EVIDENCE_ALIAS = "EvidenceChunks"
MIN_WEAVIATE_SERVER_VERSION = (1, 26, 0)
DEFAULT_PLATFORM_API_BEARER_FILE = Path("/run/secrets/platform-api-bearer")
_BEARER_TOKEN = re.compile(r"[A-Za-z0-9\-._~+/]+={0,}")
_MAX_BEARER_BYTES = 4096
REQUIRED_NATIVE_PROPERTIES = {
    "chunk_id": ("uuid", False),
    "artifact_id": ("uuid", False),
    "source_sha256": ("text", False),
    "case_id": ("text", False),
    "disclosure_tier": ("text", False),
    "source_kind": ("text", False),
    "projection_kind": ("text", False),
    "authority_state": ("text", False),
    "source_availability_complete": ("boolean", False),
    "occurred_at": ("date", True),
    "source_available_from": ("date", True),
    "source_available_from_epoch": ("int", True),
    "normalized_record_id": ("uuid", False),
    "conversation_id": ("text", False),
    "chunker_id": ("text", False),
    "embed_model": ("text", False),
    "embed_dimension": ("int", False),
    "embedder_version": ("text", False),
    "projection_version": ("text", False),
    "projection_hash": ("text", False),
    "content_hash": ("text", False),
    "source_content_hash": ("text", False),
    "content": ("text", False),
}


@dataclass(frozen=True)
class Check:
    check_id: str
    status: Status
    summary: str
    detail: str | None = None


class DatabaseSnapshot(TypedDict):
    server_version_num: int
    extensions: list[str]
    markers: dict[str, bool]
    horizon_uses_visible_from: bool


def _check(check_id: str, passed: bool, summary: str, failure: str) -> Check:
    return Check(check_id, "PASS" if passed else "FAIL", summary if passed else failure)


def _data_type_name(property_: Any) -> str:
    data_type = getattr(property_, "dataType", None)
    return str(getattr(data_type, "value", data_type)).lower()


def evaluate_native_evidence_contract(module: Any) -> list[Check]:
    """Evaluate the local native schema without creating a client or contacting Weaviate."""

    properties = {property_.name: property_ for property_ in module.evidence_vector_properties()}
    identity_matches = (
        module.EVIDENCE_VECTOR_COLLECTION_VERSION == NATIVE_EVIDENCE_COLLECTION_VERSION
        and module.EVIDENCE_VECTOR_COLLECTION == NATIVE_EVIDENCE_COLLECTION
        and module.EVIDENCE_VECTOR_ALIAS == NATIVE_EVIDENCE_ALIAS
        and module.EVIDENCE_EMBED_MODEL == "nvidia/nv-embed-v1"
        and module.EVIDENCE_EMBED_DIM == 4096
    )
    required_properties_match = all(
        name in properties
        and _data_type_name(properties[name]) == expected_type
        and (not requires_range or getattr(properties[name], "indexRangeFilters", False) is True)
        for name, (expected_type, requires_range) in REQUIRED_NATIVE_PROPERTIES.items()
    )
    return [
        _check(
            "weaviate.native_contract_identity",
            identity_matches,
            "Native evidence collection is V1 with stable alias and pinned self-provided embedding contract",
            "Native evidence collection name, version, alias, embedder, or dimension does not match V1",
        ),
        _check(
            "weaviate.native_contract_properties",
            required_properties_match and "realized_at" not in properties,
            "Native evidence properties include typed, range-indexed source clocks and no realized_at field",
            "Native evidence properties lost a required type/range index or introduced realized_at",
        ),
    ]


def native_evidence_contract_checks() -> list[Check]:
    try:
        from server.core import evidence_vector_store

        return evaluate_native_evidence_contract(evidence_vector_store)
    except Exception as error:
        return [
            Check(
                "weaviate.native_contract_import",
                "FAIL",
                "Native evidence collection contract could not be evaluated",
                type(error).__name__,
            )
        ]


def pinned_weaviate_version_checks(root: Path = PROJECT_ROOT) -> list[Check]:
    """Validate the declared server image only; this function performs no network I/O."""

    deploy_path = root / "deploy" / "data-weaviate.yaml"
    deploy = deploy_path.read_text(encoding="utf-8") if deploy_path.exists() else ""
    match = re.search(r"image:\s*[^\s#]*weaviate:(\d+)\.(\d+)\.(\d+)", deploy)
    version = tuple(int(part) for part in match.groups()) if match else None
    return [
        _check(
            "weaviate.server_version_floor",
            version is not None and version >= MIN_WEAVIATE_SERVER_VERSION,
            f"Pinned Weaviate server {'.'.join(map(str, version or ()))} meets the >=1.26 contract",
            "Pinned Weaviate server image is missing, unparseable, or older than 1.26",
        )
    ]


def static_checks(root: Path = PROJECT_ROOT) -> list[Check]:
    checks: list[Check] = native_evidence_contract_checks() + pinned_weaviate_version_checks(root)
    migration_paths: list[Path] = []
    for number in MIGRATIONS:
        matches = sorted((root / "sql").glob(f"{number:04d}_*.sql"))
        checks.append(
            _check(
                f"migration.{number:04d}.unique",
                len(matches) == 1,
                f"Migration {number:04d} has one tracked file",
                f"Migration {number:04d} expected one file, found {len(matches)}",
            )
        )
        if len(matches) == 1:
            migration_paths.append(matches[0])

    for path in migration_paths:
        content = path.read_text(encoding="utf-8")
        migration_number = path.name[:4]
        checks.append(
            _check(
                f"migration.{migration_number}.held_banner",
                "HELD FOR OWNER" in content and "NOT APPLIED" in content,
                f"Migration {migration_number} remains visibly held and unapplied",
                f"Migration {migration_number} lost its HELD/NOT APPLIED release banner",
            )
        )

    migration_0030 = root / "sql" / "0030_matter_case_foundation.sql"
    content_0030 = migration_0030.read_text(encoding="utf-8") if migration_0030.exists() else ""
    checks.append(
        _check(
            "migration.0030.order_guard",
            "after migrations 0026-0029" in content_0030,
            "Migration 0030 explicitly requires 0026–0029 first",
            "Migration 0030 does not pin the required 0026–0029 ordering",
        )
    )

    deploy = (root / "deploy" / "workbench.yaml").read_text(encoding="utf-8")
    auth = (root / "modules" / "workbench" / "api" / "app" / "runtime" / "auth.py").read_text(encoding="utf-8")
    platform_bearer_mount = "/data/probata/secrets/platform/api-bearer:/run/secrets/platform-api-bearer:ro"
    checks.extend(
        [
            _check(
                "workbench.platform_api_runtime_auth",
                "PLATFORM_API_URL: ${PLATFORM_API_URL:-http://platform-api:8000}" in deploy
                and "PLATFORM_API_BEARER_SECRET_FILE: /run/secrets/platform-api-bearer" in deploy
                and platform_bearer_mount in deploy
                and "AGENTOS_API_TOKEN" not in deploy
                and "AGENTOS_API_URL" not in deploy
                and "PLATFORM_API_BEARER:" not in deploy,
                "Workbench uses the private Platform API and a read-only runtime bearer file",
                "Workbench Platform API URL/bearer mount is missing or a retired/environment secret contract remains",
            ),
            _check(
                "workbench.inbound_auth_boundary",
                'request.url.path == "/health"' in auth
                and "trusted_auth_proxy_cidrs_parsed" in auth
                and "_AUTHENTIK_UID_HEADER" in auth
                and "status_code=403" in auth,
                "Workbench inbound auth keeps exact /health plus trusted-proxy identity enforcement",
                "Workbench inbound authentication no longer visibly enforces its trusted-proxy identity boundary",
            ),
        ]
    )

    dockerfile = (root / "deploy" / "docker" / "postgres" / "Dockerfile").read_text(encoding="utf-8")
    baseline = (root / "sql" / "bootstrap" / "schema_baseline.sql").read_text(encoding="utf-8")
    image_contract = all(
        marker in dockerfile for marker in ("pgduckdb/pgduckdb:18", "postgresql-18-postgis-3", "postgresql-18-pgvector")
    ) and all(f"CREATE EXTENSION IF NOT EXISTS {name}" in baseline for name in REQUIRED_EXTENSIONS)
    checks.append(
        _check(
            "postgres.canonical_image_contract",
            image_contract,
            "Canonical PG18 image/baseline declares required extensions",
            "Canonical PG18 extension contract is incomplete",
        )
    )
    return checks


def read_platform_api_bearer(path: str | Path) -> str | None:
    """Read and validate the mounted bearer without retaining or reporting it."""

    try:
        raw = Path(path).read_bytes()
    except OSError:
        return None
    if not raw or len(raw) > _MAX_BEARER_BYTES or b"\n" in raw or b"\r" in raw:
        return None
    try:
        token = raw.decode("utf-8")
    except UnicodeDecodeError:
        return None
    return token if _BEARER_TOKEN.fullmatch(token) else None


def credential_checks(bearer_file: str | Path) -> list[Check]:
    bearer = read_platform_api_bearer(bearer_file)
    return [
        _check(
            "credential.platform_api_bearer_file",
            bearer is not None,
            "Platform API runtime bearer file is provisioned and valid",
            "Platform API runtime bearer file is absent or invalid",
        ),
    ]


def evaluate_database_snapshot(snapshot: DatabaseSnapshot, expected: Literal["absent", "present"]) -> list[Check]:
    extensions = set(snapshot["extensions"])
    markers = snapshot["markers"]
    checks = [
        _check(
            "database.postgres18",
            snapshot["server_version_num"] // 10_000 == 18,
            "Database is PostgreSQL 18",
            "Database is not PostgreSQL 18",
        ),
        _check(
            "database.extensions",
            REQUIRED_EXTENSIONS <= extensions,
            "Database has pg_duckdb, pgcrypto, PostGIS, and pgvector",
            f"Database is missing required extensions: {sorted(REQUIRED_EXTENSIONS - extensions)}",
        ),
    ]
    values = [bool(markers.get(f"{number:04d}")) for number in MIGRATIONS]
    desired = expected == "present"
    checks.append(
        _check(
            "database.migration_state",
            values == [desired] * len(MIGRATIONS),
            f"Migrations 0026–0030 are uniformly {expected}",
            f"Migrations 0026–0030 are partial or do not match expected state {expected}: {values}",
        )
    )
    if expected == "present":
        checks.append(
            _check(
                "database.horizon_repoint",
                bool(snapshot.get("horizon_uses_visible_from")),
                "Live horizon view uses working.visible_from",
                "Migration markers exist but the horizon view is not repointed",
            )
        )
    return checks


def database_snapshot(dsn: str) -> DatabaseSnapshot:
    sqlalchemy_dsn = dsn.replace("postgresql://", "postgresql+psycopg://", 1)
    engine = create_engine(sqlalchemy_dsn, pool_pre_ping=True)
    try:
        with engine.connect() as connection:
            transaction = connection.begin()
            try:
                connection.execute(text("SET TRANSACTION READ ONLY"))
                version = int(connection.execute(text("SHOW server_version_num")).scalar_one())
                extensions = set(connection.execute(text("SELECT extname FROM pg_extension")).scalars())
                row = (
                    connection.execute(
                        text(
                            "SELECT "
                            "to_regclass('working.realization_event') IS NOT NULL AS m0026, "
                            "to_regclass('working.walk_ledger') IS NOT NULL AS m0027, "
                            "position('visible_from' in coalesce(pg_get_viewdef(to_regclass('working.horizon_visible'), true), '')) > 0 AS m0028, "
                            "to_regrole('pass_refresher') IS NOT NULL AND to_regrole('pass_reader') IS NOT NULL AS m0029, "
                            "to_regclass('registry.matter') IS NOT NULL AS m0030"
                        )
                    )
                    .mappings()
                    .one()
                )
            finally:
                transaction.rollback()
    finally:
        engine.dispose()
    return {
        "server_version_num": version,
        "extensions": sorted(extensions),
        "markers": {f"00{number}": bool(row[f"m00{number}"]) for number in range(26, 31)},
        "horizon_uses_visible_from": bool(row["m0028"]),
    }


def _probe(check_id: str, base_url: str, path: str, token: str | None = None) -> Check:
    url = urljoin(base_url.rstrip("/") + "/", path.lstrip("/"))
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = Request(url, headers=headers, method="GET")
    try:
        with urlopen(request, timeout=8) as response:  # noqa: S310 - operator-supplied service URL
            status = response.status
    except HTTPError as error:
        status = error.code
    except (TimeoutError, URLError, OSError) as error:
        return Check(check_id, "FAIL", "Service probe failed", type(error).__name__)
    return _check(check_id, 200 <= status < 300, f"Service probe returned {status}", f"Service probe returned {status}")


def service_checks(args: argparse.Namespace) -> list[Check]:
    bearer = read_platform_api_bearer(args.platform_api_bearer_file)
    checks = [
        _probe("service.workbench_health", args.workbench_url, "/health"),
        _probe(
            "service.workbench_matter",
            args.workbench_url,
            "/api/matters?limit=1&offset=0",
        ),
        _probe(
            "service.workbench_knowledge_prefilter",
            args.workbench_url,
            "/api/knowledge/search?q=activation-preflight&case_id=primary&lane=evidence&limit=1",
        ),
    ]
    if bearer is None:
        checks.append(
            Check(
                "service.platform_api_matter",
                "FAIL",
                "Platform API probe blocked because the runtime bearer file is absent or invalid",
            )
        )
    else:
        checks.append(
            _probe(
                "service.platform_api_matter",
                args.platform_api_url,
                "/v1/matters?limit=1&offset=0",
                bearer,
            )
        )
    checks.append(_probe("service.weaviate", args.weaviate_url, "/v1/.well-known/ready"))
    return checks


def git_checks(root: Path = PROJECT_ROOT) -> list[Check]:
    status = subprocess.run(["git", "status", "--porcelain"], cwd=root, text=True, capture_output=True, check=False)
    head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, text=True, capture_output=True, check=False)
    remote = subprocess.run(["git", "rev-parse", "origin/main"], cwd=root, text=True, capture_output=True, check=False)
    return [
        _check(
            "git.clean",
            status.returncode == 0 and not status.stdout.strip(),
            "Worktree is clean",
            "Worktree is dirty or git status failed",
        ),
        _check(
            "git.pushed_main",
            head.returncode == 0 and remote.returncode == 0 and head.stdout.strip() == remote.stdout.strip(),
            "HEAD equals origin/main",
            "HEAD does not equal origin/main",
        ),
    ]


def _blocked(check_id: str, summary: str) -> Check:
    return Check(check_id, "BLOCKED", summary)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scope", choices=("static", "database", "activation"), default="static")
    parser.add_argument("--database-dsn-env", default="MATTER_PREFLIGHT_DATABASE_URL")
    parser.add_argument("--expected-migrations", choices=("absent", "present"))
    parser.add_argument("--workbench-url", default=os.environ.get("WORKBENCH_URL", ""))
    parser.add_argument("--platform-api-url", default=os.environ.get("PLATFORM_API_URL", ""))
    parser.add_argument(
        "--platform-api-bearer-file",
        default=os.environ.get("PLATFORM_API_BEARER_SECRET_FILE", str(DEFAULT_PLATFORM_API_BEARER_FILE)),
    )
    parser.add_argument("--weaviate-url", default=os.environ.get("WEAVIATE_URL", ""))
    parser.add_argument("--json", action="store_true", dest="as_json")
    return parser.parse_args(argv)


def run(args: argparse.Namespace) -> tuple[list[Check], int]:
    checks = static_checks() + git_checks()
    if args.scope in {"database", "activation"}:
        expected_migrations = cast(
            Literal["absent", "present"],
            args.expected_migrations or ("present" if args.scope == "activation" else "absent"),
        )
        dsn = os.environ.get(args.database_dsn_env, "")
        if dsn:
            try:
                checks.extend(evaluate_database_snapshot(database_snapshot(dsn), expected_migrations))
            except Exception as error:  # fail closed without leaking DSN/details
                checks.append(Check("database.connection", "FAIL", "Database preflight failed", type(error).__name__))
        else:
            checks.append(_blocked("database.connection", f"Environment {args.database_dsn_env} is not set"))

    if args.scope == "activation":
        checks.extend(credential_checks(args.platform_api_bearer_file))
        if args.workbench_url and args.platform_api_url and args.weaviate_url:
            checks.extend(service_checks(args))
        else:
            checks.append(_blocked("service.probes", "Workbench, Platform API, and Weaviate URLs are required"))

    exit_code = 0 if all(check.status == "PASS" for check in checks) else 2
    return checks, exit_code


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    checks, exit_code = run(args)
    payload = {
        "scope": args.scope,
        "ready": exit_code == 0,
        "checks": [asdict(check) for check in checks],
    }
    if args.as_json:
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        for check in checks:
            suffix = f" — {check.detail}" if check.detail else ""
            print(f"[{check.status}] {check.check_id}: {check.summary}{suffix}")
        print("READY" if exit_code == 0 else "NOT READY")
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
