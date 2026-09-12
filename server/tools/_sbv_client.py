"""Shared SBV HTTP client (underscore prefix -> NOT a tool module; excluded
from registry auto-discovery, same convention as _common.py).

SBV = "SMS Backup Viewer" (ghcr.io/lowcarbdev/sbv, deployed git-0.1.11), a Go
microservice with a session-cookie-authenticated REST API. This client wraps
the auth + the `/api/` surface so both the primary parser (sbv_sms.py) and the
tools-facade SBV proxy talk to SBV through ONE place.

AUTH (cracked from sbv-upstream-main.zip internal/auth.go + verified live
2026-06-25): the API prefix is `/api/` (NOT `/api/v1/` — the old sbv-client.ts
is stale). Auth is a `session_id` HttpOnly cookie obtained from
`POST /api/auth/login` (or `/api/auth/register` — registration is OPEN). We
authenticate with a dedicated service account: login first, and if the user
doesn't exist yet, register it (idempotent bootstrap). Sessions last 30 days;
we just re-login whenever a call returns 401.

Endpoints (all under /api/, protected ones need the cookie):
  PUBLIC : GET /api/health, GET /api/version,
           POST /api/auth/{register,login,logout}
  COOKIE : POST /api/upload (multipart file=<xml>),
           GET  /api/messages, /api/conversations, /api/calls, /api/analytics,
           GET  /api/progress, /api/search, /api/media, /api/media-items,
           GET  /api/activity, /api/daterange, GET/PUT /api/settings
  (There is NO /api/export route in this build — the frontend exports
   client-side; export-as-a-function is served by the facade, not SBV.)

Uses only the stdlib (urllib) + json so it adds NO dependency to the slim
tools-facade image (which has just fastapi/uvicorn/pydantic).
"""

from __future__ import annotations

import hashlib
import http.client
import json
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from typing import Any

# Defaults match the deployed container (SBV listens on :8085 inside
# tool-runtime). Override via env for local/proxy use.
SBV_BASE_URL = os.getenv("SBV_BASE_URL", "http://localhost:8085").rstrip("/")
SBV_API = f"{SBV_BASE_URL}/api"

# Service-account credentials. The integration registers/logs-in this account
# to obtain a session cookie. Override in the tool-runtime env at cutover.
SBV_SERVICE_USER = os.getenv("SBV_SERVICE_USER", "mcp_service")
SBV_SERVICE_PASS = os.getenv("SBV_SERVICE_PASS", "")  # set in env at cutover

DEFAULT_TIMEOUT = float(os.getenv("SBV_TIMEOUT", "60"))
DEFAULT_IMPORT_PAGE = 500
MAX_IMPORT_PAGE = 1000
_SAFE_ATTACHMENT_NAME = re.compile(r"[^A-Za-z0-9._-]+")


def _safe_attachment_name(name: str, attachment_id: int) -> str:
    """Turn an untrusted manifest name into one local filename component."""
    base = os.path.basename(name or "")
    base = _SAFE_ATTACHMENT_NAME.sub("_", base).strip("._")
    return base[:180] or f"attachment-{attachment_id}"


def _check_attachment_destination(dest: str, destination_root: str | None) -> None:
    """Reject traversal and symlink destinations before opening a child file."""
    if os.path.lexists(dest) and os.path.islink(dest):
        raise ValueError("attachment destination must not be a symlink")
    if destination_root is None:
        return
    root = os.path.realpath(destination_root)
    parent = os.path.realpath(os.path.dirname(dest))
    try:
        if os.path.commonpath((root, parent)) != root:
            raise ValueError("attachment destination escapes destination_root")
    except ValueError as exc:
        raise ValueError("attachment destination escapes destination_root") from exc


class SBVError(RuntimeError):
    """SBV API error (non-2xx or transport failure)."""

    def __init__(self, message: str, status: int | None = None) -> None:
        super().__init__(message)
        self.status = status


class SBVClient:
    """Minimal session-cookie SBV API client (stdlib only).

    Lifecycle: construct -> .login() (lazy, auto-called) -> call methods. The
    client holds the `session_id` cookie and re-authenticates on 401.
    """

    def __init__(
        self,
        base_url: str | None = None,
        username: str | None = None,
        password: str | None = None,
        timeout: float = DEFAULT_TIMEOUT,
    ) -> None:
        self.base = (base_url or SBV_BASE_URL).rstrip("/")
        self.api = f"{self.base}/api"
        self.username = username or SBV_SERVICE_USER
        self.password = password or SBV_SERVICE_PASS
        self.timeout = timeout
        self._session_id: str | None = None

    # -- transport ---------------------------------------------------------

    def _request(
        self,
        method: str,
        path: str,
        *,
        params: dict[str, Any] | None = None,
        json_body: dict[str, Any] | None = None,
        data: bytes | None = None,
        content_type: str | None = None,
        auth: bool = True,
        _retry: bool = True,
    ) -> tuple[int, bytes, dict[str, str]]:
        url = f"{self.api}{path}"
        if params:
            clean = {k: v for k, v in params.items() if v is not None}
            if clean:
                url = f"{url}?{urllib.parse.urlencode(clean)}"

        body = data
        headers: dict[str, str] = {}
        if json_body is not None:
            body = json.dumps(json_body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        elif content_type:
            headers["Content-Type"] = content_type

        if auth:
            if self._session_id is None:
                self.login()
            headers["Cookie"] = f"session_id={self._session_id}"

        req = urllib.request.Request(url, data=body, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                return resp.status, resp.read(), dict(resp.headers)
        except urllib.error.HTTPError as exc:
            payload = exc.read()
            # session expired/invalid -> re-login once and retry
            if exc.code == 401 and auth and _retry:
                self._session_id = None
                self.login()
                return self._request(
                    method,
                    path,
                    params=params,
                    json_body=json_body,
                    data=data,
                    content_type=content_type,
                    auth=auth,
                    _retry=False,
                )
            raise SBVError(
                f"SBV {method} {path} -> HTTP {exc.code}: {payload[:300].decode('utf-8', 'replace')}",
                status=exc.code,
            ) from exc
        except urllib.error.URLError as exc:
            raise SBVError(f"SBV {method} {path} -> transport error: {exc.reason}") from exc

    def _stream_request(
        self,
        method: str,
        path: str,
        *,
        file_path: str,
        filename: str,
        form_fields: dict[str, str] | None = None,
        _retry: bool = True,
    ) -> tuple[int, bytes, dict[str, str]]:
        """Send a multipart request without materializing the source file.

        ``urllib.request`` only accepts bytes for request bodies.  The universal
        import endpoint is explicitly intended for multi-gigabyte sources, so
        use the stdlib HTTP connection directly and copy the file in bounded
        chunks.  The JSON response remains bounded and is read normally.
        """
        if not os.path.isfile(file_path):
            raise FileNotFoundError(file_path)
        if self._session_id is None:
            self.login()
        fields = form_fields or {}
        boundary = f"----sbvmcp{uuid.uuid4().hex}"
        safe_name = _safe_attachment_name(filename, 0)
        prefix = bytearray()
        for key, value in fields.items():
            prefix.extend(f'--{boundary}\r\nContent-Disposition: form-data; name="{key}"\r\n\r\n{value}\r\n'.encode())
        prefix.extend(
            (
                f"--{boundary}\r\n"
                f'Content-Disposition: form-data; name="file"; filename="{safe_name}"\r\n'
                "Content-Type: application/octet-stream\r\n\r\n"
            ).encode()
        )
        suffix = f"\r\n--{boundary}--\r\n".encode("ascii")
        size = os.path.getsize(file_path)
        parsed = urllib.parse.urlsplit(f"{self.api}{path}")
        connection_cls = http.client.HTTPSConnection if parsed.scheme == "https" else http.client.HTTPConnection
        conn = connection_cls(parsed.netloc, timeout=self.timeout)
        target = parsed.path or "/"
        if parsed.query:
            target += f"?{parsed.query}"
        headers = {
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "Content-Length": str(len(prefix) + size + len(suffix)),
            "Cookie": f"session_id={self._session_id}",
        }
        try:
            conn.putrequest(method, target)
            for key, value in headers.items():
                conn.putheader(key, value)
            conn.endheaders()
            conn.send(prefix)
            with open(file_path, "rb") as source:
                while True:
                    chunk = source.read(1024 * 1024)
                    if not chunk:
                        break
                    conn.send(chunk)
            conn.send(suffix)
            response = conn.getresponse()
            raw = response.read()
            response_headers = {str(k): str(v) for k, v in response.getheaders()}
            if response.status == 401 and _retry:
                self._session_id = None
                self.login()
                return self._stream_request(
                    method,
                    path,
                    file_path=file_path,
                    filename=filename,
                    form_fields=form_fields,
                    _retry=False,
                )
            if response.status < 200 or response.status >= 300:
                raise SBVError(
                    f"SBV {method} {path} -> HTTP {response.status}: {raw[:300].decode('utf-8', 'replace')}",
                    status=response.status,
                )
            return response.status, raw, response_headers
        except (OSError, http.client.HTTPException) as exc:
            raise SBVError(f"SBV {method} {path} -> transport error: {exc}") from exc
        finally:
            conn.close()

    @staticmethod
    def _json(raw: bytes) -> Any:
        if not raw:
            return {}
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            return {"_raw": raw.decode("utf-8", "replace")}

    @staticmethod
    def _session_from_response(raw: bytes, headers: dict[str, str]) -> str | None:
        """SBV returns the session id in the JSON body AND a Set-Cookie header.
        Prefer the body (explicit); fall back to parsing Set-Cookie."""
        data = SBVClient._json(raw)
        sess = (data or {}).get("session") or {}
        if isinstance(sess, dict) and sess.get("id"):
            return str(sess["id"])
        cookie = headers.get("Set-Cookie", "")
        for part in cookie.split(";"):
            part = part.strip()
            if part.startswith("session_id="):
                return part[len("session_id=") :]
        return None

    # -- auth --------------------------------------------------------------

    def login(self) -> str:
        """Obtain a session cookie. Login first; if the service account does
        not exist yet, register it (open registration), then proceed. Returns
        the session id."""
        if not self.password:
            raise SBVError("SBV service password not set (SBV_SERVICE_PASS) — cannot authenticate")
        # try login
        try:
            _status, raw, headers = self._request(
                "POST",
                "/auth/login",
                json_body={"username": self.username, "password": self.password},
                auth=False,
            )
            sid = self._session_from_response(raw, headers)
            if sid:
                self._session_id = sid
                return sid
        except SBVError as exc:
            # 401 == user/pass mismatch; only auto-register on "not found"-style
            # 401, which we can't distinguish — so fall through to register and
            # let a genuine bad-password surface as a register conflict/secondary
            # login failure.
            if exc.status not in (401,):
                raise
        # register (idempotent bootstrap) then it returns a session directly
        _status, raw, headers = self._request(
            "POST",
            "/auth/register",
            json_body={"username": self.username, "password": self.password},
            auth=False,
        )
        sid = self._session_from_response(raw, headers)
        if not sid:
            raise SBVError("SBV register/login succeeded but no session id returned")
        self._session_id = sid
        return sid

    # -- public surface ----------------------------------------------------

    def health(self) -> bool:
        status, _raw, _ = self._request("GET", "/health", auth=False)
        return status == 200

    def version(self) -> dict[str, Any]:
        _, raw, _ = self._request("GET", "/version", auth=False)
        return self._json(raw)

    # -- protected surface -------------------------------------------------

    def upload(self, file_path: str, filename: str | None = None) -> dict[str, Any]:
        """Legacy ``/api/upload`` wrapper, now streamed from disk."""
        _, raw, _ = self._stream_request(
            "POST", "/upload", file_path=file_path, filename=filename or os.path.basename(file_path)
        )
        return self._json(raw)

    def import_file(self, file_path: str, filename: str | None = None, format: str | None = None) -> dict[str, Any]:
        """Create one universal, immutable SBV import and return its ID."""
        fields = {"format": format} if format else None
        _, raw, _ = self._stream_request(
            "POST",
            "/imports",
            file_path=file_path,
            filename=filename or os.path.basename(file_path),
            form_fields=fields,
        )
        result = self._json(raw)
        if not isinstance(result, dict):
            raise SBVError("SBV universal import returned a non-object response")
        import_id = result.get("import_id")
        if not isinstance(import_id, int) or import_id <= 0:
            nested = result.get("import")
            if isinstance(nested, dict):
                result = {**nested, **result}
                import_id = result.get("import_id")
        if not isinstance(import_id, int) or import_id <= 0:
            raise SBVError("SBV universal import response did not include a valid import_id")
        return result

    # Explicit spelling for callers that prefer the API term.
    universal_import = import_file

    def progress(self) -> dict[str, Any]:
        _, raw, _ = self._request("GET", "/progress")
        return self._json(raw)

    def wait_for_processing(self, poll_s: float = 1.0, timeout_s: float = 600.0) -> dict[str, Any]:
        """Poll /api/progress until status is terminal (completed/error/idle)."""
        deadline = time.time() + timeout_s
        last: dict[str, Any] = {}
        while time.time() < deadline:
            last = self.progress()
            status = (last or {}).get("status")
            if status in ("completed", "error", "idle", None):
                # `idle` with processed>0 also means done; None == no job field
                if status == "error":
                    raise SBVError(f"SBV processing error: {last.get('error_message')}")
                if status in ("completed", "idle"):
                    return last
            time.sleep(poll_s)
        raise SBVError(f"SBV processing timed out after {timeout_s}s (last={last})")

    def wait_for_import(self, import_id: int, poll_s: float = 0.25, timeout_s: float = 600.0) -> dict[str, Any]:
        """Poll one immutable universal import until it is terminal.

        ``/api/progress`` belongs to SBV's legacy upload workflow and can report
        ``no_upload`` after a successful ``POST /api/imports``. Universal imports
        must therefore be observed through their explicit import identity.
        """
        if int(import_id) <= 0:
            raise ValueError("import_id must be positive")
        deadline = time.time() + timeout_s
        last_status: Any = None
        while time.time() < deadline:
            detail = self.import_detail(import_id)
            last_status = detail.get("status")
            if last_status == "completed":
                return detail
            if last_status in ("error", "failed"):
                raise SBVError(f"SBV import {import_id} failed: {detail.get('error') or 'unknown error'}")
            time.sleep(poll_s)
        raise SBVError(f"SBV import {import_id} timed out after {timeout_s}s (status={last_status!r})")

    def messages(
        self,
        address: str | None = None,
        limit: int | None = None,
        offset: int | None = None,
        start_date: str | None = None,
        end_date: str | None = None,
    ) -> Any:
        """GET /api/messages?address=<addr>. The deployed SBV (git-0.1.11)
        REQUIRES `address` (returns 400 without it) and uses `start`/`end`
        (RFC3339) — there is no "all messages" endpoint. Returns a bare
        []Message array. To fetch everything, use all_activity()."""
        _, raw, _ = self._request(
            "GET",
            "/messages",
            params={"address": address, "limit": limit, "offset": offset, "start": start_date, "end": end_date},
        )
        return self._json(raw)

    def conversations(self) -> Any:
        """GET /api/conversations -> bare []Conversation array."""
        _, raw, _ = self._request("GET", "/conversations")
        return self._json(raw)

    def all_messages(self, address: str | None = None) -> list[dict[str, Any]]:
        """All messages. If `address` is given, fetch that thread; otherwise
        walk every conversation (SBV has no list-all-messages endpoint)."""
        if address:
            data = self.messages(address=address)
            return data if isinstance(data, list) else (data.get("messages") or [])
        out: list[dict[str, Any]] = []
        convs = self.conversations()
        convs = convs if isinstance(convs, list) else (convs.get("conversations") or [])
        seen: set[str] = set()
        for conv in convs:
            addr = conv.get("address")
            if not addr or addr in seen:
                continue
            seen.add(addr)
            data = self.messages(address=addr)
            out.extend(data if isinstance(data, list) else (data.get("messages") or []))
        return out

    def calls(self, limit: int | None = None, offset: int | None = None) -> Any:
        """GET /api/calls -> bare []CallLog array (no address needed)."""
        _, raw, _ = self._request("GET", "/calls", params={"limit": limit, "offset": offset})
        return self._json(raw)

    def all_calls(self, page: int = 1000) -> list[dict[str, Any]]:
        out: list[dict[str, Any]] = []
        offset = 0
        while True:
            data = self.calls(limit=page, offset=offset)
            batch = data if isinstance(data, list) else (data.get("calls") or [])
            out.extend(batch)
            if len(batch) < page:
                break
            offset += page
        return out

    def activity(self, limit: int | None = None, offset: int | None = None) -> Any:
        """GET /api/activity -> bare []ActivityItem array (messages + calls
        across ALL conversations, paginated). The clean 'get everything' path."""
        _, raw, _ = self._request("GET", "/activity", params={"limit": limit, "offset": offset})
        return self._json(raw)

    def all_activity(self, page: int = 1000) -> list[dict[str, Any]]:
        """Auto-paginate /api/activity until exhausted -> all messages + calls."""
        out: list[dict[str, Any]] = []
        offset = 0
        while True:
            data = self.activity(limit=page, offset=offset)
            batch = data if isinstance(data, list) else (data.get("activities") or [])
            out.extend(batch)
            if len(batch) < page:
                break
            offset += page
        return out

    def analytics(self) -> Any:
        _, raw, _ = self._request("GET", "/analytics")
        return self._json(raw)

    def hashes(self, import_id: str | int = "latest") -> dict[str, Any]:
        """GET /api/hashes/{importID} -> forensic custody hashes for one import
        batch: {import_id, file_hash (H1), chain_hash (H3), record_count,
        imported_at, ...canon versions}. `import_id="latest"` (default) returns
        the most recent import — the batch a just-finished upload produced. Added
        by the SBV forensic fork; on the stock upstream build this 404s."""
        _, raw, _ = self._request("GET", f"/hashes/{import_id}")
        data = self._json(raw)
        return data if isinstance(data, dict) else {}

    def import_detail(self, import_id: int) -> dict[str, Any]:
        """Fetch custody/accounting status for one explicit import ID."""
        if int(import_id) <= 0:
            raise ValueError("import_id must be positive")
        _, raw, _ = self._request("GET", f"/imports/{int(import_id)}")
        data = self._json(raw)
        if not isinstance(data, dict):
            raise SBVError(f"SBV import {import_id} returned a non-object detail")
        return data

    @staticmethod
    def _page_size(page: int) -> int:
        return max(1, min(int(page), MAX_IMPORT_PAGE))

    def import_records(self, import_id: int, *, page: int = DEFAULT_IMPORT_PAGE) -> list[dict[str, Any]]:
        """Read every canonical record by import ID, using bounded pages."""
        page = self._page_size(page)
        out: list[dict[str, Any]] = []
        offset = 0
        while True:
            _, raw, _ = self._request(
                "GET", f"/imports/{int(import_id)}/records", params={"limit": page, "offset": offset}
            )
            data = self._json(raw)
            rows = data.get("records", []) if isinstance(data, dict) else data
            if not isinstance(rows, list):
                raise SBVError(f"SBV import {import_id} records response was not a list")
            out.extend(row for row in rows if isinstance(row, dict))
            total = data.get("total") if isinstance(data, dict) else None
            if len(rows) < page or (isinstance(total, int) and len(out) >= total):
                return out
            offset += len(rows)

    def import_rejections(self, import_id: int, *, page: int = DEFAULT_IMPORT_PAGE) -> list[dict[str, Any]]:
        """Read every rejection by import ID, using bounded pages."""
        page = self._page_size(page)
        out: list[dict[str, Any]] = []
        offset = 0
        while True:
            _, raw, _ = self._request(
                "GET", f"/imports/{int(import_id)}/rejections", params={"limit": page, "offset": offset}
            )
            data = self._json(raw)
            rows = data.get("rejections", []) if isinstance(data, dict) else data
            if not isinstance(rows, list):
                raise SBVError(f"SBV import {import_id} rejections response was not a list")
            out.extend(row for row in rows if isinstance(row, dict))
            total = data.get("total") if isinstance(data, dict) else None
            if len(rows) < page or (isinstance(total, int) and len(out) >= total):
                return out
            offset += len(rows)

    def import_attachments(self, import_id: int) -> list[dict[str, Any]]:
        _, raw, _ = self._request("GET", f"/imports/{int(import_id)}/attachments")
        data = self._json(raw)
        rows = data.get("attachments", []) if isinstance(data, dict) else data
        if not isinstance(rows, list):
            raise SBVError(f"SBV import {import_id} attachments response was not a list")
        return [row for row in rows if isinstance(row, dict)]

    def download_attachment(
        self, import_id: int, attachment_id: int, destination: str, *, destination_root: str | None = None
    ) -> dict[str, Any]:
        """Stream one import-scoped attachment to ``destination`` safely.

        The server binds the attachment ID to the import.  The client additionally
        requires a plain destination filename/path and verifies the returned
        byte count and SHA-256 when the manifest provides them.
        """
        if int(import_id) <= 0 or int(attachment_id) <= 0:
            raise ValueError("import_id and attachment_id must be positive")
        dest = os.path.abspath(destination)
        _check_attachment_destination(dest, destination_root)
        return self.download_attachment_stream(import_id, attachment_id, dest)

    def download_attachment_to_dir(self, import_id: int, attachment_id: int, destination_root: str) -> dict[str, Any]:
        """Resolve a manifest filename under ``destination_root`` then stream it."""
        manifest = next(
            (item for item in self.import_attachments(import_id) if str(item.get("id")) == str(attachment_id)),
            None,
        )
        if manifest is None:
            raise SBVError(f"attachment {attachment_id} is not part of import {import_id}")
        root = os.path.abspath(destination_root)
        os.makedirs(root, exist_ok=True)
        dest = os.path.join(root, _safe_attachment_name(str(manifest.get("original_name") or ""), attachment_id))
        result = self.download_attachment_stream(import_id, attachment_id, dest, destination_root=root)
        expected_count = manifest.get("byte_count")
        expected_hash = str(manifest.get("decoded_hash") or "").lower()
        count_ok = not isinstance(expected_count, int) or result["byte_count"] == expected_count
        hash_ok = not expected_hash or result["sha256"].lower() == expected_hash
        if not count_ok or not hash_ok:
            quarantine = os.path.join(root, "to_be_deleted")
            os.makedirs(quarantine, exist_ok=True)
            quarantined = os.path.join(quarantine, os.path.basename(dest) + ".integrity-mismatch")
            os.replace(dest, quarantined)
            raise SBVError(f"attachment {attachment_id} integrity mismatch; quarantined at {quarantined}")
        result["verified"] = bool(isinstance(expected_count, int) and expected_hash)
        return result

    def download_attachment_stream(
        self, import_id: int, attachment_id: int, destination: str, *, destination_root: str | None = None
    ) -> dict[str, Any]:
        """Stream an attachment response directly to disk and hash it."""
        if int(import_id) <= 0 or int(attachment_id) <= 0:
            raise ValueError("import_id and attachment_id must be positive")
        dest = os.path.abspath(destination)
        _check_attachment_destination(dest, destination_root)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        if self._session_id is None:
            self.login()
        parsed = urllib.parse.urlsplit(f"{self.api}/imports/{int(import_id)}/attachments/{int(attachment_id)}")
        cls = http.client.HTTPSConnection if parsed.scheme == "https" else http.client.HTTPConnection
        conn = cls(parsed.netloc, timeout=self.timeout)
        target = parsed.path or "/"
        try:
            conn.request("GET", target, headers={"Cookie": f"session_id={self._session_id}"})
            response = conn.getresponse()
            if response.status == 401:
                self._session_id = None
                self.login()
                return self.download_attachment_stream(import_id, attachment_id, destination)
            if response.status < 200 or response.status >= 300:
                detail = response.read(300).decode("utf-8", "replace")
                raise SBVError(
                    f"SBV GET /imports/{import_id}/attachments/{attachment_id} -> HTTP {response.status}: {detail}",
                    status=response.status,
                )
            digest = hashlib.sha256()
            count = 0
            with open(dest, "wb") as fh:
                while True:
                    chunk = response.read(1024 * 1024)
                    if not chunk:
                        break
                    fh.write(chunk)
                    digest.update(chunk)
                    count += len(chunk)
            return {"path": dest, "byte_count": count, "sha256": digest.hexdigest()}
        except (OSError, http.client.HTTPException) as exc:
            raise SBVError(f"SBV attachment download transport error: {exc}") from exc
        finally:
            conn.close()

    def search(self, query: str, limit: int | None = None) -> Any:
        _, raw, _ = self._request("GET", "/search", params={"q": query, "limit": limit})
        return self._json(raw)
