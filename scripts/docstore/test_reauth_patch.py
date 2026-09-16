"""test_reauth_patch.py - prove the SurrealDB reconnect re-auth patch works.

Byline: Claude Code - Opus 5 - 2026-09-16

The patch lives in flow_docs.py (see the comment block above
_install_reauth_on_reconnect). flow_docs imports cocoindex, which is not
installed on the desktop, so this test re-implements the SAME patch body
against the real installed SDK and proves the behaviour end to end:

  1. sign in, use ns/db, run a query               -> works
  2. kill the socket underneath the connection     -> simulates the real drop
  3. run another query                              -> must SUCCEED, because the
     patched _connect_locked replays signin + use

Without the patch step 3 fails with "Anonymous access not allowed: Not enough
permissions to perform this action" - the exact error that killed runs
17567c42, f745dac3, ad5a5ced, 5a0b4213, c7421349 and 3d894018.

Run:
  "C:/Users/matts/.local/bin/python3.exe" scripts/docstore/test_reauth_patch.py
  ... --no-patch    run the same scenario WITHOUT the patch (expect step 3 to fail)
"""
from __future__ import annotations

import argparse
import asyncio
import pathlib
import re
import sys

import surrealdb.connections.async_ws as aws
from surrealdb import AsyncSurreal


def env_file(path: pathlib.Path) -> dict:
    out = {}
    if path.is_file():
        for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
            m = re.match(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+?)\s*$", line)
            if m:
                out[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    return out


SECRETS = env_file(pathlib.Path.home() / ".secrets" / "probata-docstore.env")


def install() -> str:
    """Same logic as flow_docs._install_reauth_on_reconnect.

    Hooked at _send, not _connect_locked: _send -> connect() holds a
    non-reentrant lock around _connect_locked, so replaying signin from inside
    it deadlocks (measured - the first version of this probe hung forever).
    """
    cls = getattr(aws, "AsyncWsSurrealConnection", None)
    if cls is None or not all(hasattr(cls, m) for m in ("signin", "use", "connect")):
        return "skipped: SDK shape not recognised"

    orig_signin, orig_use, orig_connect = cls.signin, cls.use, cls.connect

    async def signin(self, vars, session_id=None):
        result = await orig_signin(self, vars, session_id=session_id)
        self._docstore_auth = (vars, session_id)
        self._docstore_sock = getattr(self, "socket", None)
        return result

    async def use(self, namespace, database, session_id=None):
        result = await orig_use(self, namespace, database, session_id=session_id)
        self._docstore_scope = (namespace, database, session_id)
        return result

    async def connect(self, url=None):
        await orig_connect(self, url)
        auth = getattr(self, "_docstore_auth", None)
        if auth is None or getattr(self, "_docstore_reauthing", False):
            return
        sock = getattr(self, "socket", None)
        if sock is None or sock is getattr(self, "_docstore_sock", None):
            return
        self._docstore_reauthing = True
        try:
            await orig_signin(self, auth[0], session_id=auth[1])
            scope = getattr(self, "_docstore_scope", None)
            if scope is not None:
                await orig_use(self, scope[0], scope[1], session_id=scope[2])
            self._docstore_sock = sock
            print("      [patch] socket reconnected; auth and namespace replayed")
        except Exception as exc:
            print(f"      [patch] reauth FAILED: {type(exc).__name__}")
        finally:
            self._docstore_reauthing = False

    cls.signin, cls.use, cls.connect = signin, use, connect
    return "installed"


async def kill_socket(db) -> str:
    """Drop the underlying websocket without going through close(), the way a
    server-side close / proxy timeout does."""
    conn = getattr(db, "_connection", db)
    for attr in ("socket", "_socket", "ws", "_ws"):
        sock = getattr(conn, attr, None)
        if sock is not None and hasattr(sock, "close"):
            await sock.close()
            return f"closed via .{attr}"
    return "could not reach the socket"


async def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-patch", action="store_true")
    a = ap.parse_args()

    print(f"patch: {'NOT installed (--no-patch)' if a.no_patch else install()}")

    db = AsyncSurreal(SECRETS["SURREAL_DOCS_URL"])
    await db.connect()
    await db.signin({"username": SECRETS["SURREAL_DOCS_USER"],
                     "password": SECRETS["SURREAL_DOCS_PASS"]})
    await db.use("probata", "docs")

    r1 = await db.query("RETURN 1;")
    print(f"[1] query before the drop: {r1!r}")

    print(f"[2] killing the socket: {await kill_socket(db)}")
    await asyncio.sleep(1)

    ok = False
    try:
        r2 = await db.query("SELECT count() AS n FROM document GROUP ALL;")
        print(f"[3] query after the drop: {r2!r}")
        ok = True
    except Exception as e:
        print(f"[3] query after the drop FAILED: {type(e).__name__}: {str(e)[:160]}")
    try:
        await db.close()
    except Exception:
        pass

    if a.no_patch:
        print("\nRESULT: without the patch this is EXPECTED to fail with "
              "'Anonymous access not allowed'." if not ok else
              "\nRESULT: succeeded without the patch - the SDK recovered on its own here.")
        return 0
    print("\nRESULT: PASS - the connection survived a socket drop."
          if ok else "\nRESULT: FAIL - still broken after a socket drop.")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
