# SFTPGo as the platform's file surface

> _Byline: Claude Code · Sonnet 5 · 2026-09-06._
> **STATUS: PROPOSED — not deployed.** No Coolify app exists, no compose file
> is in `deploy/`, no code change has been made. This is a spec for review.

Owner, 2026-09-06: *"Filestash/SFTPGo/FileBrowser… could be used for the
server also, and for machine to machine."* This spec answers that with
SFTPGo specifically: a human-facing browse/upload surface plus a manual
intake path that starts a real proffer run, while machine reads keep going
through the existing S3 resolvers untouched.

## 1. Role split

| Surface | Who uses it | Reads/writes | Status |
|---|---|---|---|
| `rclone` | operator, ad hoc | bulk mirrors, corpus sync, R2↔OneDrive/local | existing, unchanged |
| S3 resolvers (`acquisition.NewSchemeRouter`, `object_store_client.py`) | machines (engine, tool-gateway, workbench) | `r2://`, `b2://` locator reads, per D-132/D-138 | existing, unchanged |
| **SFTPGo** (this spec) | humans (browse/upload via web/SFTP/WebDAV) + manual intake | R2-backed virtual folders; read-only vault, read-write intake bucket; REST API for scripted listing/move | new |

SFTPGo does not replace either existing lane. It adds a *front door* for a
human dropping files in without a terminal, and it re-exposes the same R2
buckets the engine already reads, so nothing downstream needs a new source
type — just a new way bytes arrive in `casebible-testing/inbox`.

## 2. `deploy/sftpgo.yaml` (DRAFT — not written to `deploy/`)

House style per `tool-gateway.yaml`/`proffer-starter.yaml`: host networking,
`/data/agno/secrets/*` read-only bind mounts, tailnet-only exposure, own
Tailscale identity per D-134.

```yaml
# files-sftpgo — human file surface + manual intake trigger.
# Byline: Claude Code · Sonnet 5 · 2026-09-06. PROPOSED, not deployed.
#
# Coolify watch paths: deploy/docker/sftpgo/**, deploy/sftpgo.yaml
services:
  files-sftpgo:
    image: drakkan/sftpgo:v2.7.5
    restart: unless-stopped
    network_mode: host  # matches tool-gateway/proffer-starter; direct tailnet routing
    environment:
      SFTPGO_HTTPD__BINDINGS__0__ADDRESS: ${BIND_IP:?set}
      SFTPGO_HTTPD__BINDINGS__0__PORT: "8098"
      SFTPGO_SFTPD__BINDINGS__0__ADDRESS: ${BIND_IP:?set}
      SFTPGO_SFTPD__BINDINGS__0__PORT: "2022"
      SFTPGO_WEBDAVD__BINDINGS__0__ADDRESS: ${BIND_IP:?set}
      SFTPGO_WEBDAVD__BINDINGS__0__PORT: "8099"
      SFTPGO_DATA_PROVIDER__DRIVER: sqlite   # bundled DB is config-only (users/folders), no evidence
      SFTPGO_DATA_PROVIDER__NAME: /srv/sftpgo/data/sftpgo.db
      SFTPGO_DEFAULT_ADMIN_USERNAME: admin
      SFTPGO_DEFAULT_ADMIN_PASSWORD_FILE: /run/secrets/sftpgo-admin-password
    volumes:
      - /data/agno/volumes/sftpgo/data:/srv/sftpgo/data
      - /data/agno/volumes/sftpgo/backups:/srv/sftpgo/backups
      - /data/agno/secrets/sftpgo/admin-password:/run/secrets/sftpgo-admin-password:ro
      # Reuse the platform's existing R2 credential shape (same fields Go's
      # acquisition/config_file.go and Python's object_store_client.py read:
      # endpoint_url, region, access_key_id, secret_access_key) — SFTPGo's own
      # per-folder JSON uses different key NAMES for the same values, so this
      # file is a reference for filling the folder config below, not something
      # SFTPGo parses directly.
      - /data/agno/secrets/casebible-r2.json:/run/secrets/casebible-r2.json:ro
    # tailnet exposure: SFTPGo has no tsnet/embed option (Go binary is
    # closed-source-adjacent build, no tsnet library hook). Use Tailscale
    # Serve on the host per the Workbench pattern (D-134 §2 fallback):
    #   tailscale serve --bg --https=443 --set-path /files http://127.0.0.1:8098
    # i.e. reached at https://files-sftpgo.<tailnet>.ts.net — NOT a Coolify
    # proxy hostname (D-133: Traefik only for genuinely external surfaces).
```

Host prep (once, mirrors tool-gateway's pattern):
```
install -d -o 10001 -g 10001 -m 0750 \
  /data/agno/volumes/sftpgo/data /data/agno/volumes/sftpgo/backups
```

## 3. SFTPGo config: folders + intake user

Two virtual folders, both backed by R2 (fs provider `1` = S3-compatible),
one intake user. Values in `<>` come from `casebible-r2.json`.

```json
// Folder: vault (read-only browse of casebible-sorted)
{
  "name": "vault",
  "mapped_path": "/vault",
  "filesystem": {
    "provider": 1,
    "s3config": {
      "bucket": "casebible-sorted",
      "region": "auto",
      "endpoint": "<endpoint_url from casebible-r2.json>",
      "access_key": "<access_key_id>",
      "access_secret": "<secret_access_key>",
      "force_path_style": true,
      "key_prefix": ""
    }
  }
}
```
```json
// Folder: testing (read-write intake landing zone)
{
  "name": "testing",
  "mapped_path": "/testing",
  "filesystem": {
    "provider": 1,
    "s3config": {
      "bucket": "casebible-testing",
      "region": "auto",
      "endpoint": "<endpoint_url>",
      "access_key": "<access_key_id or a dedicated scoped R2 key>",
      "access_secret": "<secret_access_key>",
      "force_path_style": true,
      "key_prefix": "inbox/"
    }
  }
}
```
```json
// User: intake (SFTP + WebDAV + web client; REST API scoped separately)
{
  "username": "intake",
  "permissions": {"/": ["list"], "/vault": ["list", "download"], "/testing": ["*"]},
  "virtual_folders": [
    {"name": "vault", "virtual_path": "/vault", "read_only": true},
    {"name": "testing", "virtual_path": "/testing", "read_only": false}
  ]
}
```

R2 endpoint form: `https://<ACCOUNT_ID>.r2.cloudflarestorage.com`,
`region: auto`, `force_path_style: true` (path-style is the safer default
against non-AWS S3-compatible services per SFTPGo's own docs; R2 supports
virtual-hosted style too but path-style avoids subdomain-resolution
surprises). `key_prefix` scopes a folder to a sub-path without a second
bucket — used here for `inbox/` inside the shared testing bucket.

## 4. Upload webhook → n8n → proffer start

SFTPGo's Event Manager fires an `upload` filesystem event; the action is an
HTTP webhook (placeholders, not a fixed schema): `{{.Name}}` (username),
`{{.VirtualPath}}`, `{{.FsPath}}`, `{{.FileSize}}`, `{{.Protocol}}`,
`{{.IP}}`, `{{.Timestamp}}`. No `{{.ObjectHash}}` placeholder exists —
SFTPGo does not hash on upload; computing a hash via its own API reads the
whole file and is billed/logged as a *download* (own quota, own permission,
own event trigger) — never an implicit part of the upload event.

Flow, following the `proffer/*` webhook convention already live in
`deploy/docker/n8n/workflows/proffer/` (`headerAuth`-protected POST
webhooks named `proffer/<verb>`):

1. SFTPGo `upload` rule → HTTP POST to a new n8n webhook
   `proffer/sftpgo-intake` (same `headerAuth` credential pattern as
   `wf-start-import.json`), body:
   ```json
   {"user": "{{.Name}}", "virtual_path": "{{.VirtualPath}}",
    "size": {{.FileSize}}, "protocol": "{{.Protocol}}",
    "ip": "{{.IP}}", "timestamp": "{{.Timestamp}}"}
   ```
2. n8n node chain: Webhook → Function (strip `virtual_path` leading
   `/testing/`, join with `inbox/` key_prefix to get the true R2 key) →
   HTTP Request `POST /reference-import/start` with
   `source_ref = r2://casebible-testing/<key>`.
3. **One required code change:** `validateAuthorizedSourceRef` in
   `modules/engine/runtimeapi/source_ref.go:47` only admits
   `parsed.Host == "casebible-sorted"` (or the dev-fixture bucket at
   line 46). It must additionally admit `casebible-testing` under the
   existing `PLATFORM_DEV_AUTH_BYPASS` dev-fixture gate (mirroring the
   `devFixtureBucket`/`devFixturePrefix` pattern at lines 20–23), so a
   manual intake upload can start a run without widening production
   source authority. This is the only code change this spec requires.

## 5. What SFTPGo does NOT do

- **No custody hashing.** H1 happens at retain (D-136); SFTPGo's own hash
  API is an on-demand download-equivalent operation, never wired to upload.
- **No cross-host disk.** It reads/writes R2 only through its S3 backend —
  no shared volume with the engine or tool-gateway (consistent with D-132's
  "cross-host source bytes travel via object storage, never a shared disk").
- **Not the vault's authority.** `casebible-sorted` stays read-only through
  SFTPGo; PostgreSQL/the Case Bible pipeline remain the writers of custody
  and provenance. SFTPGo is a window, not a second store.

## 6. Coolify app spec

| Field | Value |
|---|---|
| App name | `files-sftpgo` |
| Server | `ovh-app` (co-located with tool-gateway/platform-tools; R2-only backend so host choice is otherwise free) |
| Watch paths | `deploy/docker/sftpgo/**`, `deploy/sftpgo.yaml` |
| Env names (no values) | `BIND_IP`, `SFTPGO_DEFAULT_ADMIN_PASSWORD_FILE` (secret path), R2 folder values sourced from `casebible-r2.json` or a dedicated `sftpgo-r2.json` key |
| Secrets (bind-mounted, not env) | `/data/agno/secrets/sftpgo/admin-password`, `/data/agno/secrets/casebible-r2.json` (ro) |

## 7. Pre-mortem: 5 failure modes

1. **R2 multipart on large uploads** — SFTPGo's default `upload_part_size`
   may not match R2's multipart limits; large chat exports (GB-scale)
   could fail mid-upload with no clean resume. Mitigate: set explicit
   `upload_part_size`/`upload_concurrency` and test with a real multi-GB
   file before relying on it for intake.
2. **Path-style vs virtual-hosted endpoint mismatch** — getting
   `force_path_style` wrong against R2 produces opaque `SignatureDoesNotMatch`
   or DNS-resolution errors, not a clear config error. Verify with one
   real upload+download per folder before wiring the webhook.
3. **Webhook retries / idempotency** — SFTPGo's event webhook has no
   documented delivery-guarantee/retry contract confirmed here; a network
   blip could either drop an intake trigger silently or double-fire it.
   The n8n → `/reference-import/start` call must be idempotent per
   `source_ref` (dedupe on R2 key + size) or a flaky retry double-starts
   a run.
4. **Auth exposure** — SFTP/WebDAV/web-client all sit behind Tailscale
   Serve, but a misconfigured intake user with `["*"]` on `/testing` plus a
   weak password is a real write path into the R2 bucket the proffer
   worker reads from. Enforce key-based SFTP auth (not password) for the
   intake user once this moves past rehearsal.
5. **WebDAV vs SFTP client quirks** — WebDAV clients (Windows/macOS Finder
   mounts) are notorious for partial-write and lock-file artifacts
   (`.~lock`, `.DS_Store`, `~$*`); an upload-event rule firing on those
   junk files would spuriously start proffer runs. Filter the event rule
   on file extension/pattern, not just the upload event type.

## Facts not verified from official docs

1. SFTPGo's upload-webhook **retry/delivery-guarantee behavior** (at-most-once
   vs at-least-once, backoff) — not found in the fetched docs pages.
2. Whether the **REST API v2** (`/api/v2`) machine-listing/move endpoints
   support the same S3 virtual-folder abstraction transparently, or expose
   raw R2 object paths differently from the SFTP/WebDAV view — not directly
   confirmed.
3. Whether `docs/reviews/2026-09-02-ingest-day-board.md` contains a prior
   Filestash/SFTPGo/FileBrowser comparison — grepped and found **no** mention
   of any of the three tools in that file; the 2026-09-03 discussion the
   task described was not located in this repo's `docs/reviews/`.
