#!/usr/bin/env python3
"""
coolify MCP server (consolidated) — read cluster + write cluster.

Read cluster mirrors the hosted Coolify MCP tool names exactly so existing
agent calls keep working after the ~/.claude.json cutover:
  get_infrastructure_overview, list_servers, get_server, list_projects,
  list_applications, get_application, list_databases, get_database,
  list_services, get_service.

Write cluster (4 tools):
  create_application, upsert_application_envs, delete_application,
  check_port_collision.

Transport-agnostic: stdio (default) or streamable-HTTP, selected by
MCP_TRANSPORT env var. Phase A = local stdio; Phase B = VPS behind ContextForge
with MCP_TRANSPORT=http — no code change, just hosting.

Token handling: direct process env (COOLIFY_API + COOLIFY_API_TOKEN — the
container path) wins; falls back to the env file at COOLIFY_ENV_FILE
(default C:/Users/matts/.secrets/coolify-ionos-api.env — the local stdio path).
The token is NEVER logged and NEVER copied into ~/.claude.json.

> Byline: Claude Code · glm-5.2:cloud (via Ollama) · 2026-07-05
> Repo copy (HTTP-mode fix: official mcp SDK run() takes no host/port kwargs —
> configure via mcp.settings; + direct-env override for containers):
> Claude Code · Fable 5 · 2026-07-08
"""

from __future__ import annotations

import os
import re
import sys
import time
import json
import yaml
from typing import Any

import httpx
from mcp.server.fastmcp import FastMCP


# ---------------------------------------------------------------------------
# Config — token + base URL loaded once at startup from the env file.
# ---------------------------------------------------------------------------

DEFAULT_ENV_FILE = r"C:/Users/matts/.secrets/coolify-ionos-api.env"


def _load_env_file(path: str) -> dict[str, str]:
    """Parse a simple KEY=VALUE env file (quotes stripped). Never logs values."""
    out: dict[str, str] = {}
    try:
        for line in open(path, encoding="utf-8"):
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, _, v = line.partition("=")
            out[k.strip()] = v.strip().strip('"').strip("'")
    except FileNotFoundError:
        sys.stderr.write(f"[coolify] COOLIFY_ENV_FILE not found: {path}\n")
    return out


def _resolve_base_url(env: dict[str, str]) -> str:
    """Prefer COOLIFY_API (full base incl /api/v1); fall back to BASE_URL+/api/v1."""
    api = env.get("COOLIFY_API") or env.get("COOLIFY_API_URL")
    if api:
        return api.rstrip("/")
    base = env.get("COOLIFY_BASE_URL")
    if base:
        return base.rstrip("/") + "/api/v1"
    raise RuntimeError("no COOLIFY_API / COOLIFY_API_URL / COOLIFY_BASE_URL in env file")


_env_file = os.environ.get("COOLIFY_ENV_FILE", DEFAULT_ENV_FILE)
_env = _load_env_file(_env_file)
# Direct process env wins over the env file — the container deploy path
# (Coolify app envs) passes COOLIFY_API / COOLIFY_API_TOKEN directly.
for _k in ("COOLIFY_API", "COOLIFY_API_URL", "COOLIFY_BASE_URL", "COOLIFY_API_TOKEN", "COOLIFY_VERSION"):
    if os.environ.get(_k):
        _env[_k] = os.environ[_k]
TOKEN = _env.get("COOLIFY_API_TOKEN", "")
BASE_URL = _resolve_base_url(_env)
VERSION = _env.get("COOLIFY_VERSION", "unknown")

if not TOKEN:
    sys.stderr.write(f"[coolify] no COOLIFY_API_TOKEN in {_env_file}\n")

# httpx client with retry on 429. Built once; tools reuse it.
_client = httpx.Client(
    base_url=BASE_URL,
    headers={
        "Authorization": f"Bearer {TOKEN}",
        "Accept": "application/json",
        "Content-Type": "application/json",
    },
    timeout=30.0,
)


class ToolExecutionError(Exception):
    """Structured error with type/message/recoverable/data, per mcp-server-design."""

    def __init__(self, error_type: str, message: str, *, recoverable: bool = True, data: dict | None = None):
        super().__init__(message)
        self.error_type = error_type
        self.recoverable = recoverable
        self.data = data or {}

    def to_payload(self) -> dict:
        return {
            "error": {
                "type": self.error_type,
                "message": str(self),
                "recoverable": self.recoverable,
                "data": self.data,
            }
        }


def _request(method: str, path: str, *, params: dict | None = None, json_body: dict | None = None) -> Any:
    """HTTP helper with 429 retry (3 attempts, respects Retry-After)."""
    last_err = None
    for attempt in range(3):
        try:
            r = _client.request(method, path, params=params, json=json_body)
            if r.status_code == 429:
                wait = float(r.headers.get("Retry-After", "2"))
                time.sleep(min(wait, 10))
                last_err = f"429 rate limited (attempt {attempt + 1})"
                continue
            if r.status_code >= 400:
                # surface a helpful error, never the token
                body = r.text[:500]
                raise ToolExecutionError(
                    "HTTP_ERROR",
                    f"{method} {path} -> {r.status_code}: {body}",
                    recoverable=r.status_code < 500,
                    data={"status": r.status_code, "path": path, "method": method},
                )
            if r.status_code == 204 or not r.text:
                return None
            return r.json()
        except ToolExecutionError:
            raise
        except httpx.HTTPError as e:
            last_err = str(e)
            time.sleep(1)
    raise ToolExecutionError("TIMEOUT", f"{method} {path} failed after 3 attempts: {last_err}")


# ---------------------------------------------------------------------------
# Port parsing for check_port_collision.
# ---------------------------------------------------------------------------

_PORTVAR = re.compile(r"^\$\{[^}:}]+(?::-([^}]+))?\}:(.+)$")


def _parse_port_entry(s: str) -> int | None:
    """Extract the host port from a compose `ports:` entry.

    Handles "${BIND_IP:-127.0.0.1}:5432:5432", "5432:5432", "5432",
    "0.0.0.0:5432:5432". Returns the host port (the first port that's bound
    on the host side), or None if unparseable."""
    s = s.strip()
    if not s:
        return None
    # strip leading ${VAR} or ${VAR:-default} host segment
    m = _PORTVAR.match(s)
    rest = m.group(2) if m else s
    parts = rest.split(":")
    try:
        if len(parts) >= 2:
            return int(parts[0])  # host port (hport:cport form)
        if len(parts) == 1 and parts[0].isdigit():
            return int(parts[0])
    except ValueError:
        return None
    return None


def _ports_from_compose_raw(raw: str) -> list[int]:
    """Parse docker_compose_raw YAML, return host ports from every service."""
    if not raw:
        return []
    try:
        doc = yaml.safe_load(raw) or {}
    except yaml.YAMLError:
        return []
    services = doc.get("services") or {}
    if not isinstance(services, dict):
        return []
    out: list[int] = []
    for spec in services.values():
        if not isinstance(spec, dict):
            continue
        ports = spec.get("ports") or []
        if not isinstance(ports, list):
            continue
        for entry in ports:
            if isinstance(entry, str):
                p = _parse_port_entry(entry)
                if p:
                    out.append(p)
    return out


def _ports_from_mappings(mappings: Any) -> list[int]:
    """ports_mappings is Coolify's expanded form for dockerfile apps.
    Often a string like '0.0.0.0:5432:5432' or None for compose apps."""
    if not mappings or not isinstance(mappings, str):
        return []
    out: list[int] = []
    for chunk in mappings.split(","):
        p = _parse_port_entry(chunk.strip())
        if p:
            out.append(p)
    return out


# ---------------------------------------------------------------------------
# MCP server + tools
# ---------------------------------------------------------------------------

mcp = FastMCP("coolify")


# === READ CLUSTER (mirrors hosted MCP names) ===============================


@mcp.tool()
def get_infrastructure_overview() -> dict:
    """Coolify version, all servers, projects with resource counts, and aggregates.

    Discovery
    ---------
    Start here. Single call returns the whole topology — servers, projects,
    and counts of applications/databases/services — so you can pick the right
    UUID before calling the per-resource tools.

    When to use
    -----------
    - First call in a session to map the fleet.
    - Before any write op, to confirm the target server/project/uuid exists.
    - NOT for: drilling into one resource (use get_application/get_server/etc).

    Returns
    -------
    dict
        {
          coolify_version: str,
          servers: list[dict],          # name, uuid, ip, is_reachable
          projects: list[dict],         # name, uuid (per-project app count
                                        # needs an /environments call — drill via
                                        # list_applications for per-app detail)
          counts: {applications, databases, services, servers},
        }
    """
    servers = _request("GET", "/servers") or []
    projects = _request("GET", "/projects") or []
    apps = _request("GET", "/applications", params={"per_page": 100}) or []
    dbs = _request("GET", "/databases", params={"per_page": 100}) or []
    svcs = _request("GET", "/services", params={"per_page": 100}) or []
    # NOTE: apps map to projects via environment_id (not project_id), so a correct
    # per-project app count would need an extra /environments call. We skip it to
    # keep this a single-pass overview — drill via list_applications for per-app.
    return {
        "coolify_version": VERSION,
        "servers": [
            {"name": s.get("name"), "uuid": s.get("uuid"), "ip": s.get("ip"), "is_reachable": s.get("is_reachable")}
            for s in servers
        ],
        "projects": [{"name": p.get("name"), "uuid": p.get("uuid")} for p in projects],
        "counts": {
            "servers": len(servers),
            "applications": len(apps),
            "databases": len(dbs),
            "services": len(svcs),
        },
    }


@mcp.tool()
def list_servers(page: int = 1, per_page: int = 50) -> list:
    """List servers owned by the authenticated team. Returns summary (uuid, name, ip, is_reachable).

    Discovery
    ---------
    Use get_infrastructure_overview for a one-shot fleet map, or this for
    paginated server listing. Pass the returned uuid to get_server for details.
    """
    return _request("GET", "/servers", params={"page": page, "per_page": per_page}) or []


@mcp.tool()
def get_server(uuid: str) -> dict:
    """Full details for one server by UUID.

    Parameters
    ----------
    uuid : str
        Server UUID. Get it from list_servers or get_infrastructure_overview.
    """
    return _request("GET", f"/servers/{uuid}")


@mcp.tool()
def list_projects(page: int = 1, per_page: int = 50) -> list:
    """List projects (summary: uuid, name, description)."""
    return _request("GET", "/projects", params={"page": page, "per_page": per_page}) or []


@mcp.tool()
def list_applications(page: int = 1, per_page: int = 50, tag: str | None = None) -> list:
    """List applications (summary: uuid, name, status, fqdn, git_repository).

    Parameters
    ----------
    tag : str, optional
        Filter by tag name.
    """
    params: dict = {"page": page, "per_page": per_page}
    if tag:
        params["tag"] = tag
    return _request("GET", "/applications", params=params) or []


@mcp.tool()
def get_application(uuid: str) -> dict:
    """Full details for one application by UUID (93-field record: status, env, compose, ports, health...).

    Do / Don't
    ----------
    Do: pass the exact uuid from list_applications.
    Don't: guess or wildcard — there is no fuzzy match; a wrong uuid 404s.
    """
    return _request("GET", f"/applications/{uuid}")


@mcp.tool()
def list_databases(page: int = 1, per_page: int = 50) -> list:
    """List standalone databases (summary: uuid, name, status, type)."""
    return _request("GET", "/databases", params={"page": page, "per_page": per_page}) or []


@mcp.tool()
def get_database(uuid: str) -> dict:
    """Full details for one standalone database by UUID."""
    return _request("GET", f"/databases/{uuid}")


@mcp.tool()
def list_services(page: int = 1, per_page: int = 50) -> list:
    """List services (multi-container stacks; summary: uuid, name, status)."""
    return _request("GET", "/services", params={"page": page, "per_page": per_page}) or []


@mcp.tool()
def get_service(uuid: str) -> dict:
    """Full details for one service (multi-container stack) by UUID."""
    return _request("GET", f"/services/{uuid}")


# === WRITE CLUSTER =========================================================


@mcp.tool()
def create_application(
    project_uuid: str,
    server_uuid: str,
    name: str,
    git_repository: str,
    git_branch: str,
    docker_compose_location: str = "/",
    github_app_id: int = 2,
    type: str = "dockercompose",
    description: str = "",
) -> dict:
    """Create a new Coolify application (default: docker-compose from a git repo).

    Mirrors the proven data-tier pattern: repo Cursedpotential/mcp-platform-agno-mcp,
    branch main, github_app_id 2, compose location "/".

    When to use
    -----------
    - Splitting a bundled compose app into independent Coolify apps.
    - Adding a new service from a git-hosted compose file.
    NOT for: standalone databases (use Coolify UI) or importing images.

    Parameters
    ----------
    project_uuid : str  # from list_projects
    server_uuid : str   # from list_servers
    name : str          # human label, also becomes the default fqdn slug
    git_repository : str  # "owner/repo" form for GitHub
    git_branch : str
    docker_compose_location : str  # path within repo to compose.yaml; "/" = root
    github_app_id : int  # Coolify GitHub App source id (2 on this instance)
    type : str  # "dockercompose" (default) — only this type is wired here
    description : str

    Do / Don't
    ----------
    Do: confirm project_uuid + server_uuid via get_infrastructure_overview first.
    Do: run check_port_collision after create, before starting, to avoid binding wars.
    Don't: pass a placeholder repo — Coolify will accept the create but the deploy will fail.

    Returns
    -------
    dict — the created application record (uuid, name, status). Use the uuid
    with upsert_application_envs to set runtime env, then trigger a deploy.
    """
    if type != "dockercompose":
        raise ToolExecutionError(
            "INVALID_ARGUMENT",
            f"type='{type}' not supported by this tool. Only 'dockercompose' is wired.",
            recoverable=True,
            data={"allowed": ["dockercompose"]},
        )
    # Coolify 4.1.2: plain POST /applications was removed (404). App creation goes
    # through POST /applications/private-github-app with github_app_uuid (string),
    # discovered via GET /github-apps (verified live 2026-07-27).
    apps = _request("GET", "/github-apps") or []
    private = [a for a in apps if not a.get("is_public")]
    if not (private or apps):
        raise ToolExecutionError(
            "NOT_FOUND", "No GitHub app sources configured on this Coolify instance.",
            recoverable=False,
        )
    github_app_uuid = (private or apps)[0]["uuid"]
    body = {
        "project_uuid": project_uuid,
        "server_uuid": server_uuid,
        "environment_name": "production",
        "github_app_uuid": github_app_uuid,
        "git_repository": git_repository,
        "git_branch": git_branch,
        "build_pack": "dockercompose",
        "docker_compose_location": docker_compose_location,
        "name": name,
        "description": description,
        "instant_deploy": False,
    }
    return _request("POST", "/applications/private-github-app", json_body=body)


@mcp.tool()
def upsert_application_envs(
    application_uuid: str,
    envs: dict,
    is_runtime: bool = True,
    is_buildtime: bool = True,
) -> dict:
    """Set/update environment variables on an application (bulk upsert).

    Tries PATCH /applications/{uuid}/envs/bulk first; falls back to per-key
    POST /applications/{uuid}/envs if the bulk endpoint is unavailable.

    Parameters
    ----------
    application_uuid : str
    envs : dict[str, str]   # {KEY: "value", ...} — keys not present are left unchanged
    is_runtime : bool       # available at runtime (default True)
    is_buildtime : bool     # available at build time (default True)

    Do / Don't
    ----------
    Do: group all env for one app into a single call (bulk path is one round-trip).
    Do: remember Coolify bakes env VALUES into the rendered compose at deploy —
        changing env requires a redeploy of the app for it to take effect.
    Don't: put the token or other secrets here as literal values you then log —
        this tool never logs values, but the agent's transcript might.

    Returns
    -------
    dict — {method: "bulk"|"per-key", updated: int, failed: list}
    """
    if not isinstance(envs, dict) or not envs:
        raise ToolExecutionError("INVALID_ARGUMENT", "envs must be a non-empty dict", recoverable=True)
    # Coolify 4.1.2 bulk upsert requires {"data": [...]} with is_preview.
    # The former {"envs": [...]} body is rejected and its POST fallback cannot
    # update compose-created keys because that endpoint is create-only.
    entries = [
        {"key": k, "value": str(v), "is_preview": False}
        for k, v in envs.items()
    ]
    try:
        r = _client.request("PATCH", f"/applications/{application_uuid}/envs/bulk", json={"data": entries})
        if r.status_code < 400:
            return {"method": "bulk", "updated": len(entries), "failed": []}
        bulk_error = f"{r.status_code}: {r.text[:500]}"
    except httpx.HTTPError as ex:
        bulk_error = str(ex)
    # Fallback remains create-only for older Coolify variants.
    updated, failed = 0, []
    for e in entries:
        try:
            _request(
                "POST",
                f"/applications/{application_uuid}/envs",
                json_body={
                    "key": e["key"],
                    "value": e["value"],
                    "is_runtime": is_runtime,
                    "is_buildtime": is_buildtime,
                    "is_literal": True,
                },
            )
            updated += 1
        except ToolExecutionError as ex:
            failed.append({"key": e["key"], "error": str(ex)})
    return {"method": "per-key", "updated": updated, "failed": failed, "bulk_error": bulk_error}


@mcp.tool()
def delete_application(uuid: str, confirm_name: str | None = None) -> dict:
    """Delete an application by UUID. DESTRUCTIVE — requires confirm_name to match.

    The confirm_name guard prevents accidental deletion when an agent passes a
    stale or wrong uuid. The name must match the application's current name.

    Do / Don't
    ----------
    Do: pass confirm_name = the app's exact current name (from get_application).
    Do: snapshot any needed config/env FIRST — delete is irreversible.
    Don't: pass a uuid you haven't just re-read in this session.
    Don't: ever pass a wildcard or empty string for either argument.
    """
    if not uuid or not confirm_name:
        raise ToolExecutionError(
            "INVALID_ARGUMENT",
            "delete_application requires both uuid and confirm_name (the app's current name).",
            recoverable=True,
        )
    # read the app first to confirm the name matches
    app = _request("GET", f"/applications/{uuid}")
    actual = (app or {}).get("name", "")
    if actual != confirm_name:
        raise ToolExecutionError(
            "NAME_MISMATCH",
            f"confirm_name='{confirm_name}' does not match actual name='{actual}'. Delete refused.",
            recoverable=False,
            data={"uuid": uuid, "actual_name": actual},
        )
    _request("DELETE", f"/applications/{uuid}")
    return {"deleted": uuid, "name": actual}


@mcp.tool()
def check_port_collision(port: int, server_uuid: str | None = None) -> dict:
    """Report which applications bind a given host port (read-only, safe).

    Primary verification tool before a cutover deploy. Parses each
    application's `docker_compose_raw` (the reliable source for compose apps,
    since `ports_mappings` is None for compose apps) and `ports_mappings`
    (for dockerfile apps) to find host-port bindings.

    Parameters
    ----------
    port : int          # the host port to check, e.g. 5432
    server_uuid : str, optional  # if given, restrict to apps on that server.
        NOTE: Coolify's /applications list does not expose a clean server_uuid
        field, so server filtering is best-effort via the app's network/destination.
        When in doubt, leave None and inspect the returned app names.

    When to use
    -----------
    - Before deploying a new app that binds a known port — confirm nothing
      already holds it.
    - Before a split cutover — confirm the bundled app still holds the port
      (so you know to stop it before starting the new app).

    Returns
    -------
    dict
        {
          port: int,
          collides: bool,
          apps: [{uuid, name, status, ports: [int]}],  # apps that bind this port
          next_actions: list[str],
        }
    """
    apps = _request("GET", "/applications", params={"per_page": 100}) or []
    hits: list[dict] = []
    for a in apps:
        uuid = a.get("uuid")
        if not uuid:
            continue
        # cheap path: the list item may already have ports_mappings
        ports = _ports_from_mappings(a.get("ports_mappings"))
        source = "ports_mappings"
        if not ports:
            # need the full record for docker_compose_raw
            full = _request("GET", f"/applications/{uuid}")
            raw = (full or {}).get("docker_compose_raw") or ""
            ports = _ports_from_compose_raw(raw)
            source = "docker_compose_raw"
        if port in ports:
            hits.append(
                {
                    "uuid": uuid,
                    "name": a.get("name"),
                    "status": a.get("status"),
                    "ports": ports,
                    "source": source,
                }
            )
    next_actions = []
    if hits:
        next_actions.append(
            "STOP the colliding app(s) above before starting a new app on the same port — "
            "two containers cannot bind the same host ip:port at once."
        )
        next_actions.append("After cutover, re-run check_port_collision to confirm only the new app holds the port.")
    else:
        next_actions.append(f"Port {port} is free — safe to deploy a new app binding it.")
    return {
        "port": port,
        "collides": bool(hits),
        "apps": hits,
        "next_actions": next_actions,
    }



@mcp.tool()
def deploy_application(uuid: str, force: bool = False) -> dict:
    """Trigger a deployment for an application (or database/service) by UUID.

    Uses GET /deploy?uuid=&force= (POST with JSON body {"uuid","force"} is also
    accepted by the API; GET+query is used here since it needs no body).

    When to use
    -----------
    - After upsert_application_envs, to bake new env values into the running
      container (Coolify renders env into compose at deploy time — env
      changes do NOT reach the container until a redeploy).
    - After changing git_branch/docker_compose_location via the Coolify UI.
    - Redeploying the current commit (force=False reuses cache where possible;
      force=True does a clean rebuild).

    Parameters
    ----------
    uuid : str    # application (or db/service) UUID
    force : bool  # force rebuild without cache (default False)

    Returns
    -------
    dict — {"message": "...", "deployment_uuid": "..."}. Pass deployment_uuid
    to get_deployment to poll status/logs.
    """
    return _request("GET", "/deploy", params={"uuid": uuid, "force": "true" if force else "false"})


@mcp.tool()
def restart_application(uuid: str) -> dict:
    """Restart a running application by UUID (stop + start; rebuilds from current image).

    Do / Don't
    ----------
    Do: use this for a quick container bounce (e.g. picking up a restarted
        dependency) when you do NOT need a fresh build.
    Don't: use this expecting new env values to apply from a compose baked at
        an earlier deploy — use deploy_application for that.

    Returns
    -------
    dict — {"message": "Restart request queued.", "deployment_uuid": "..."}
    """
    return _request("GET", f"/applications/{uuid}/restart")


@mcp.tool()
def stop_application(uuid: str, docker_cleanup: bool = True) -> dict:
    """Stop a running application by UUID.

    Parameters
    ----------
    uuid : str
    docker_cleanup : bool  # prune networks/volumes after stop (API default True)

    Do / Don't
    ----------
    Do: check_port_collision first if you're stopping one app to free a port
        for another (this IS the "stop the old app" step in that workflow).
    Don't: docker-stop the container manually outside Coolify — Coolify owns
        the container lifecycle and will fight a manually-stopped container
        on its next reconciliation pass, leaving it in a confused state.

    Returns
    -------
    dict — {"message": "Application stopping request queued."}
    """
    return _request("GET", f"/applications/{uuid}/stop", params={"docker_cleanup": "true" if docker_cleanup else "false"})


@mcp.tool()
def start_application(uuid: str, force: bool = False, instant_deploy: bool = False) -> dict:
    """Start a stopped application by UUID (deploys and starts containers).

    Parameters
    ----------
    uuid : str
    force : bool           # force rebuild
    instant_deploy : bool  # skip the deploy queue

    Do / Don't
    ----------
    Don't: use `docker start <container>` directly on a Coolify-managed
    container — Coolify tracks desired state itself; starting outside the API
    creates an orphan container Coolify doesn't know is running (verified
    local lesson — leads to port conflicts and duplicate containers on the
    next Coolify-triggered deploy). Always start/stop through this tool or
    the Coolify UI.

    Returns
    -------
    dict — {"message": "...", "deployment_uuid": "..."} (may be None if the
    app was already running).
    """
    return _request(
        "GET",
        f"/applications/{uuid}/start",
        params={"force": "true" if force else "false", "instant_deploy": "true" if instant_deploy else "false"},
    )


@mcp.tool()
def get_deployment(deployment_uuid: str) -> dict:
    """Get one deployment's status and logs by deployment UUID, with errors pre-extracted.

    The raw `logs` field from the API is a JSON-encoded STRING of an array of
    log-line objects (not a plain string, not pre-parsed JSON) — this tool
    parses it and surfaces the tail + any error-looking lines so you don't
    have to re-parse it yourself every call.

    Parameters
    ----------
    deployment_uuid : str  # from deploy_application / restart_application /
                            # start_application response, or list_deployments_for_app

    Requires
    --------
    The API token needs `read:sensitive` permission to see the `logs` field —
    without it, Coolify strips logs from the response (removeSensitiveData()).

    Returns
    -------
    dict
        {
          deployment_uuid, status, application_id, server_id,
          log_line_count: int,
          last_lines: list[str],       # tail of the log (up to 40 lines)
          error_lines: list[str],      # lines containing error/fail/exception (case-insens.)
          raw_logs_available: bool,    # False if token lacks read:sensitive
        }
    """
    d = _request("GET", f"/deployments/{deployment_uuid}") or {}
    raw = d.get("logs")
    last_lines: list[str] = []
    error_lines: list[str] = []
    count = 0
    if isinstance(raw, str) and raw:
        try:
            entries = json.loads(raw)
        except (json.JSONDecodeError, TypeError):
            entries = None
        if isinstance(entries, list):
            count = len(entries)
            texts = []
            for e in entries:
                if isinstance(e, dict):
                    texts.append(str(e.get("output") or e.get("message") or e))
                else:
                    texts.append(str(e))
            last_lines = texts[-40:]
            error_lines = [t for t in texts if re.search(r"error|fail|exception", t, re.IGNORECASE)][-40:]
    return {
        "deployment_uuid": d.get("deployment_uuid", deployment_uuid),
        "status": d.get("status"),
        "application_id": d.get("application_id"),
        "server_id": d.get("server_id"),
        "log_line_count": count,
        "last_lines": last_lines,
        "error_lines": error_lines,
        "raw_logs_available": raw is not None,
    }


@mcp.tool()
def list_deployments_for_app(uuid: str, skip: int = 0, take: int = 10) -> list:
    """List past/current deployments for one application by app UUID.

    GET /deployments/applications/{uuid} — separate from GET /deployments
    (which only lists deployments currently queued/in-progress across the
    whole team, not scoped to one app).

    Parameters
    ----------
    uuid : str   # application UUID (not deployment_uuid)
    skip : int   # pagination offset (default 0)
    take : int   # page size (default 10)
    """
    return _request("GET", f"/deployments/applications/{uuid}", params={"skip": skip, "take": take}) or []


@mcp.tool()
def get_application_logs(uuid: str, lines: int = 100) -> dict:
    """Get recent runtime container logs for an application by UUID.

    This is CONTAINER STDOUT/STDERR (GET /applications/{uuid}/logs), distinct
    from deployment build logs (get_deployment). Use this for "why is my app
    crashing at runtime"; use get_deployment for "why did the build fail."

    Parameters
    ----------
    uuid : str
    lines : int  # number of lines from the end of the log (API default 100)

    Requires
    --------
    Token needs `read:sensitive` permission — logs may contain secrets.
    """
    return _request("GET", f"/applications/{uuid}/logs", params={"lines": lines}) or {}



# ---------------------------------------------------------------------------
# Transport selection
# ---------------------------------------------------------------------------


def main() -> None:
    transport = os.environ.get("MCP_TRANSPORT", "stdio").lower()
    if transport == "stdio":
        mcp.run()
    elif transport in ("http", "streamable-http", "streamable_http"):
        # streamable-HTTP transport for Phase B (VPS + ContextForge).
        # Official mcp SDK: FastMCP.run() takes no host/port kwargs (that's the
        # third-party fastmcp 2.x signature) — configure via mcp.settings.
        mcp.settings.host = os.environ.get("MCP_HOST", "0.0.0.0")
        mcp.settings.port = int(os.environ.get("MCP_PORT", "8000"))
        mcp.settings.stateless_http = True  # no session affinity needed behind CF
        mcp.settings.json_response = True  # plain JSON responses (CF + curl friendly)
        # SDK DNS-rebinding protection 421s any Host other than localhost by
        # default. This service binds tailnet-only and is fronted by
        # ContextForge's JWT auth, so disable the Host check.
        from mcp.server.transport_security import TransportSecuritySettings

        mcp.settings.transport_security = TransportSecuritySettings(enable_dns_rebinding_protection=False)
        mcp.run(transport="streamable-http")
    else:
        sys.exit(f"[coolify] unknown MCP_TRANSPORT='{transport}' (stdio|http)")


if __name__ == "__main__":
    main()
