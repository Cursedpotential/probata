"""Apply scripts/docstore/schema/*.surql to the EMBEDDED docstore.

Byline: Claude Code · Opus 5 · 2026-09-09

Reads SURREAL_URL from .docstore/.env when no URL argument is given.
Needed because surrealkit / surreal sql / surreal import all require a remote
endpoint and cannot reach an embedded datastore."""
import asyncio, os, pathlib, re, sys
from surrealdb import AsyncSurreal


def _env_file(path=".docstore/.env"):
    """Parse a KEY=value env file tolerantly. Never sourced, never printed."""
    out = {}
    f = pathlib.Path(path)
    if f.exists():
        for line in f.read_text(encoding="utf-8", errors="ignore").splitlines():
            m = re.match(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+?)\s*$", line)
            if m:
                out[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    return out


_ENV = _env_file()


def _cfg(key, default=None):
    return os.environ.get(key) or _ENV.get(key) or default


# URL argument is optional: fall back to SURREAL_URL from .docstore/.env, as the
# module docstring has always promised.
URL = sys.argv[1] if len(sys.argv) > 1 else _cfg("SURREAL_URL")
if not URL:
    raise SystemExit("no URL argument and no SURREAL_URL in env/.docstore/.env")
NS, DB = (sys.argv[2], sys.argv[3]) if len(sys.argv) > 3 else (
    _cfg("SURREAL_NS", "probata"), _cfg("SURREAL_DB", "docs")
)
SCHEMA = pathlib.Path("scripts/docstore/schema")

async def main():
    db = AsyncSurreal(URL)
    await db.connect()
    # Embedded (surrealkv://, mem://, file://) needs no auth; a remote server does.
    if not URL.startswith(("surrealkv://", "mem://", "memory", "file://")):
        user, password = _cfg("SURREAL_USER"), _cfg("SURREAL_PASS")
        if user and password:
            creds = {"username": user, "password": password}
            # A namespace-scoped user must sign in WITH its namespace.
            if _cfg("SURREAL_SIGNIN_NS"):
                creds["namespace"] = _cfg("SURREAL_SIGNIN_NS")
            await db.signin(creds)
    await db.use(NS, DB)
    failed = 0
    for f in sorted(SCHEMA.glob("*.surql")):
        try:
            await db.query(f.read_text(encoding="utf-8"))
            print(f"  ok   {f.name}")
        except Exception as e:
            failed += 1
            print(f"  FAIL {f.name}: {str(e).splitlines()[0][:160]}")
    await db.close()
    print("schema applied clean" if not failed else f"{failed} file(s) FAILED")
    return 1 if failed else 0

raise SystemExit(asyncio.run(main()))
