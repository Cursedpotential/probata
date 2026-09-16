"""test_ws_keepalive.py - assert the SurrealDB WebSocket keepalive settings.

Byline: Claude Code - Opus 5 - 2026-09-16

WHY THIS EXISTS
  Every full index run died on one document with
      ConnectionUnavailableError: WebSocket connection closed
  at a constant 65-68 s, and the cause is client-side. The SurrealDB SDK opens
  its socket with

      websockets.connect(url, max_size=None, subprotocols=["cbor"])

  passing NO ping settings, so the `websockets` library defaults apply. Read
  off a LIVE connection (websockets 17.0.1): ping_interval=20, ping_timeout=20.
  The library pings every 20 s and, when the pong does not arrive within 20 s,
  CLOSES THE CONNECTION ITSELF - while the server is committing that document's
  chunk transaction and NIM is embedding at ~10 s per request.

  That is consistent with the failure being immovable by everything external,
  each ruled out by measurement: pointing the worker straight at SurrealDB
  instead of the ts.net proxy (67 s), restarting surreal-docs to release
  10.8 GiB with host swap 100% full (66 s), and DOCSTORE_CHUNK_BATCH_ROWS
  64 -> 12 (68 s).

WHAT THIS TEST DOES AND DOES NOT PROVE
  It asserts the effective settings on a real connection: without the fix
  ping_timeout is 20, with the fix it is None while ping_interval stays 20 -
  pings keep flowing (so NAT/proxies still see traffic) but a late pong can no
  longer sever a healthy, busy connection. No retry; write semantics unchanged.

  It does NOT simulate the stall. An honest note, because the obvious
  simulation is wrong: blocking the event loop does NOT reproduce the close,
  because a blocked loop also blocks the keepalive task, so no ping is ever
  sent and no timeout ever starts (measured - a 45 s block survived without the
  fix). The timeout only fires when the loop is healthy and the SERVER's pong
  is late, which is why the functional proof is a real index run over
  consignatio/docs/URGENT-TODO.md, not a local simulation.

RUN
  "C:/Users/matts/.local/bin/python3.exe" scripts/docstore/test_ws_keepalive.py
  ... --stall 45   additionally block the loop for 45s and re-query
"""
from __future__ import annotations

import argparse
import asyncio
import pathlib
import re
import time

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
_ORIG_CONNECT = aws.websockets.connect


def install(interval: float | None = 20.0, timeout: float | None = None) -> str:
    """Same body as flow_docs._install_ws_keepalive."""
    def connect(*a, **kw):
        kw.setdefault("ping_interval", interval)
        kw.setdefault("ping_timeout", timeout)
        return _ORIG_CONNECT(*a, **kw)
    aws.websockets.connect = connect
    return f"installed (ping_interval={interval}, ping_timeout={timeout})"


def uninstall() -> None:
    aws.websockets.connect = _ORIG_CONNECT


def settings_of(db) -> dict:
    conn = getattr(db, "_connection", db)
    sock = getattr(conn, "socket", None)
    out = {}
    for attr in ("ping_interval", "ping_timeout"):
        for holder in (sock, getattr(sock, "protocol", None)):
            if holder is not None and hasattr(holder, attr):
                out[attr] = getattr(holder, attr)
                break
    return out


async def open_db():
    db = AsyncSurreal(SECRETS["SURREAL_DOCS_URL"])
    await db.connect()
    await db.signin({"username": SECRETS["SURREAL_DOCS_USER"],
                     "password": SECRETS["SURREAL_DOCS_PASS"]})
    await db.use("probata", "docs")
    return db


async def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--stall", type=float, default=0.0,
                    help="also block the event loop this many seconds and re-query")
    a = ap.parse_args()
    failures = []

    uninstall()
    db = await open_db()
    before = settings_of(db)
    await db.close()
    print(f"[1] WITHOUT the fix: {before}")
    if before.get("ping_timeout") != 20:
        failures.append(f"expected the SDK default ping_timeout=20, saw {before!r}")

    install()
    db = await open_db()
    after = settings_of(db)
    print(f"[2] WITH the fix   : {after}")
    if after.get("ping_timeout") is not None:
        failures.append(f"ping_timeout should be None, saw {after.get('ping_timeout')!r}")
    if not after.get("ping_interval"):
        failures.append("ping_interval must stay set so pings keep flowing")

    print(f"[3] query on the patched connection: {await db.query('RETURN 1;')!r}")

    if a.stall:
        print(f"[4] blocking the loop {a.stall:.0f}s (note: this does NOT reproduce the "
              f"production close - see the module docstring) ...")
        t0 = time.time()
        time.sleep(a.stall)
        print(f"    blocked {time.time() - t0:.1f}s")
        try:
            print(f"    query after the stall: "
                  f"{await db.query('SELECT count() AS n FROM document GROUP ALL;')!r}")
        except Exception as e:
            failures.append(f"query after a {a.stall}s stall failed: {type(e).__name__}")
    await db.close()

    if failures:
        print("\nRESULT: FAIL")
        for f in failures:
            print("  -", f)
        return 1
    print("\nRESULT: PASS - pings still sent every 20s, a late pong no longer "
          "closes the connection.")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
