# Byline: Claude Code · Sonnet (agent) · 2026-07-19 (agno 2.8 MCP door migration + Graphiti pane wiring 2026-07-23)
# Byline: Codex · GPT-5 · 2026-08-16 (Portkey-routed neutral chat settings)
# Byline: Codex · GPT-5 · 2026-08-18 (owner-only evidence-search capability)
# Byline: Codex · GPT-5 · 2026-08-29 (runtime-read Platform API bearer file)
"""Workbench settings for the fixed Case Bible source and governed Platform services.

Env var names are the pydantic-settings default (uppercase of the field name)
and must match compose.workbench.yaml exactly — see that file for the deployed
defaults and the Coolify env-literal-rendering gotcha.
"""

from __future__ import annotations

import ipaddress
import json
import os

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # --- Object store: runtime credentials; fixed buckets live in the repo adapter ---
    object_store_prefix: str = "workbench/staging"

    # --- LanceDB local whole-file staging store (no S3, no AWS env vars) ---
    lancedb_path: str = "/data/lancedb"

    # --- Existing platform ingestion API (the promote target + the run spine) ---
    platform_api_url: str = "http://100.72.169.40:8000"
    # Non-secret location only. The Platform API bearer itself is read
    # from this mounted file for every outbound Platform API request so rotation
    # does not require a Workbench restart or redeployment.
    platform_api_bearer_secret_file: str = "/run/secrets/platform-api-bearer"
    # Non-secret path to the runtime-read Cloudflare R2 credentials document.
    # Buckets are fixed in the adapter: ``casebible-sorted`` for source reads
    # and ``nexus`` for new Workbench staging writes.
    casebible_r2_config_path: str = "/run/secrets/casebible-r2.json"
    # Direct-tailnet Proffer starter boundary; blank values fail closed in the adapter.
    proffer_starter_url: str = ""
    # Explicit TEST/REAL matter identities for the Proffer intake surface.
    # Neither identity is discovered by title. Blank or malformed values fail
    # the corresponding mode closed at the BFF boundary.
    proffer_test_matter_id: str = "deadbeef-dead-beef-dead-beefdeadbeef"
    proffer_real_matter_id: str = ""
    proffer_test_court_case_id: str = "cafebabe-cafe-babe-cafe-babecafebabe"
    proffer_real_court_case_id: str = ""
    # Non-secret location only. Read once per outbound request for rotation.
    proffer_service_token_file: str = "/run/secrets/proffer-service-token"
    # Separate runtime-read operator capability. Only the Workbench receives
    # the mounted file; bounded agent tasks use Temporal-provided walk context.
    evidence_operator_bearer_secret_file: str = "/run/secrets/evidence-operator-security-key"

    # --- MCP tool servers (Tool Explorer) ---
    # ContextForge is the authored registry; Portkey is the downstream audited
    # gateway. Default empty is intentional: an unprovisioned chain exposes no
    # tools instead of falling back to a direct ContextForge door. Each
    # entry may carry its own literal "token" (bearer), or a "token_env" —
    # the NAME of an env var holding the bearer, resolved at read time via
    # mcp_servers_parsed (never baked into the JSON literal itself, so the
    # actual secret value lives only in the process env / Coolify env editor,
    # never in this file or compose.workbench.yaml's MCP_SERVERS string).
    # Each normal entry declares gateway:"portkey" and names Portkey's
    # /<server-slug>/mcp endpoint. ContextForge's /servers/<uuid>/mcp URL is
    # an upstream publication target, never a normal Workbench client door.
    mcp_servers: str = "[]"
    # Temporary diagnostics may explicitly opt into a direct door. This must
    # never become the production default or an automatic failure fallback.
    mcp_direct_bypass_allowed: bool = False
    # Back-compat only: used to fill the "contextforge" entry's token when
    # that entry carries neither "token" nor a resolvable "token_env" (a
    # pre-C4 MCP_SERVERS literal that hasn't been migrated to the token_env
    # convention above yet) — see mcp_servers_parsed.
    contextforge_token: str | None = None

    # --- OpenCode headless server (Ops Copilot, C2.5) ---
    # Basic auth is native to `opencode serve` via these two env names — see
    # compose.gateway.yaml (OPENCODE_SERVER_USERNAME/OPENCODE_SERVER_PASSWORD,
    # the C2.5 build's key-leak fix: GET /provider returns plaintext provider
    # keys unauth'd). When opencode_password is empty, no Authorization
    # header is sent — matches the pre-redeploy, still-unauthenticated
    # tailnet state (see app/repo/opencode_client.py).
    opencode_url: str = "http://100.72.169.40:4096"
    opencode_username: str = "opencode"
    opencode_password: str | None = None
    # provider/model, e.g. "groq/llama-3.3-70b-versatile" — overridable per request
    opencode_model: str = "groq/llama-3.3-70b-versatile"
    # SINGLE shared session-workspace directory for ALL copilot sessions (not
    # per-session) — the workbench container can't mkdir on the gateway host,
    # so isolation comes from opencode's own session model, not per-session
    # dirs. See app/repo/opencode_client.py module docstring + the
    # compose.gateway.yaml HOST-PREP comment (bind mount + one-time mkdir).
    opencode_workspace_dir: str = "/workspace/copilot"

    # --- Neutral operator chat (Portkey is the normal audited route) ---
    # PORTKEY_CONFIG is intentionally required by the route: saved configs own
    # fallback/load-balancing policy, while direct providers remain confined to
    # the explicitly labeled diagnostic model lab.
    portkey_api_key: str = ""
    portkey_base_url: str = "https://api.portkey.ai/v1"
    portkey_config: str = ""
    portkey_environment: str = "development"

    # --- Copilot preset prompts (optional JSON override, merged over
    # in-code defaults — see app/service/copilot_presets.py) ---
    copilot_presets_path: str = "/data/copilot/presets.json"

    # --- Graphiti knowledge-graph memory (C4 Graph memory pane) ---
    # The tailnet "graphiti-hostfix" nginx sidecar (compose.data-graphiti.yaml)
    # — NOT graphiti-mcp directly. Read-only wiring only (search_memory_facts/
    # search_nodes/get_episodes); see app/repo/graphiti_client.py for the
    # transport quirk (server-side Host-header rewrite, nothing special
    # needed client-side) and app/service/graphiti.py for the tool contract.
    # No auth today (tailnet-only, matches the `grc` CLI's --via direct).
    graphiti_mcp_url: str = "http://100.119.96.29:8071/mcp"
    # Temporary operator boundary until authenticated Matter/Run grants land.
    # Comma-separated namespaces; browser input never expands this allowlist.
    graphiti_allowed_groups: str = "platform"

    @property
    def graphiti_allowed_group_set(self) -> frozenset[str]:
        """Configured read-only Graphiti namespaces, normalized fail-closed."""
        return frozenset(group.strip() for group in self.graphiti_allowed_groups.split(",") if group.strip())

    # --- Authentication: Traefik+Authentik trusted-proxy ingress ---
    # Comma-separated CIDRs of trusted proxies (e.g., Traefik). Empty/fail-closed.
    # Only socket peers inside these CIDRs are accepted for protected routes.
    # Invalid/empty config denies all protected traffic — no silent trust.
    trusted_auth_proxy_cidrs: str = ""
    # Explicit testing feature flag. When enabled, a request forwarded by the
    # trusted Traefik peer may authenticate from a configured Tailscale CIDR
    # without Authentik. The flag is off by default in application code.
    tailnet_auth_bypass_enabled: bool = False
    tailnet_auth_bypass_cidrs: str = "100.64.0.0/10"
    # Exact local proxy addresses used by Tailscale Serve's direct loopback
    # mapping. Every entry must be a single-host /32 or /128 network.
    trusted_tailscale_serve_proxy_cidrs: str = ""

    # --- App ---
    app_port: int = 8020
    static_dir: str = "/app/static"
    max_upload_mb: int = 200
    # Compatibility read only: older local .env files may contain this key.
    # The Workbench boundary does not consult or deploy it.
    workbench_api_key: str = ""

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="allow")

    @property
    def max_upload_bytes(self) -> int:
        return self.max_upload_mb * 1024 * 1024

    @property
    def mcp_servers_parsed(self) -> list[dict]:
        """Parse MCP_SERVERS (json) into [{key, label, url, token?}, ...].

        Token resolution order per entry:
        1. A literal "token" already on the entry wins as-is (rare — mostly
           a manual override).
        2. "token_env": the name of an env var holding the bearer, resolved
           via `os.environ` at read time so the raw secret never has to be
           embedded in the MCP_SERVERS JSON literal itself.
        3. Back-compat: the bare CONTEXTFORGE_TOKEN env fills in the
           "contextforge"-keyed entry specifically, when it has neither of
           the above (a pre-C4 MCP_SERVERS literal that predates the
           token_env convention).

        Malformed/non-list JSON degrades to an empty list rather than
        raising. Entries without gateway:"portkey" are filtered unless the
        explicit diagnostic bypass is enabled.
        """
        try:
            servers = json.loads(self.mcp_servers)
        except (TypeError, ValueError):
            return []
        if not isinstance(servers, list):
            return []
        allowed_servers = []
        for server in servers:
            if not isinstance(server, dict):
                continue
            if server.get("gateway") != "portkey" and not self.mcp_direct_bypass_allowed:
                continue
            if server.get("token"):
                allowed_servers.append(server)
                continue
            token_env = server.get("token_env")
            resolved = os.environ.get(token_env) if token_env else None
            if resolved:
                server["token"] = resolved
            elif server.get("key") == "contextforge" and self.contextforge_token:
                server["token"] = self.contextforge_token
            allowed_servers.append(server)
        return allowed_servers

    @property
    def trusted_auth_proxy_cidrs_parsed(self) -> list[ipaddress.IPv4Network | ipaddress.IPv6Network]:
        """Parse TRUSTED_AUTH_PROXY_CIDRS into a list of IP networks.

        Fail-closed: empty string, missing, or any malformed CIDR returns
        an empty list, which causes the auth middleware to deny all protected
        traffic. No silent trust of Docker-wide or tailnet-wide ranges.
        """
        if not self.trusted_auth_proxy_cidrs:
            return []
        cidrs = []
        for part in self.trusted_auth_proxy_cidrs.split(","):
            part = part.strip()
            if not part:
                return []
            try:
                cidrs.append(ipaddress.ip_network(part, strict=True))
            except ValueError:
                return []
        return cidrs

    @property
    def tailnet_auth_bypass_cidrs_parsed(self) -> list[ipaddress.IPv4Network | ipaddress.IPv6Network]:
        """Parse the feature-gated tailnet testing ranges fail-closed."""
        if not self.tailnet_auth_bypass_cidrs:
            return []
        cidrs = []
        for part in self.tailnet_auth_bypass_cidrs.split(","):
            part = part.strip()
            if not part:
                return []
            try:
                network = ipaddress.ip_network(part, strict=True)
            except ValueError:
                return []
            if not network.subnet_of(ipaddress.ip_network("100.64.0.0/10")):
                return []
            cidrs.append(network)
        return cidrs

    @property
    def trusted_tailscale_serve_proxy_cidrs_parsed(
        self,
    ) -> list[ipaddress.IPv4Network | ipaddress.IPv6Network]:
        """Parse exact trusted Tailscale Serve proxy addresses fail-closed."""
        if not self.trusted_tailscale_serve_proxy_cidrs:
            return []
        cidrs = []
        for part in self.trusted_tailscale_serve_proxy_cidrs.split(","):
            part = part.strip()
            try:
                network = ipaddress.ip_network(part, strict=True)
            except ValueError:
                return []
            if network.num_addresses != 1:
                return []
            cidrs.append(network)
        return cidrs


settings = Settings()
