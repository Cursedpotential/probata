#!/usr/bin/env python3
"""
smart_explore.py — standalone, persistent, AST-based code exploration.

A self-contained rebuild of the claude-mem `smart-explore` skill with the
claude-mem MCP dependency removed. Parsing is done locally with tree-sitter
(via tree-sitter-language-pack), and the symbol index is persisted in a
per-project DuckDB file so it survives across sessions and only re-parses
changed files.

Subcommands:
  index   <path>                     build/refresh the symbol index for a dir
  indexes                            list all indexes in the central store (alias: list)
  search  <query> [--path P] [--max N] [--file-pattern G]
  outline <file>
  unfold  <file> <symbol>
  refs    <symbol> [--path P]        find usages/call sites across the indexed tree
          [--lsp [--timeout S]]      type-resolved via a language server when one is
                                     available (see `lsp`); falls back to lexical scan
  lsp                                show LSP server availability per language
  imports [--file F | --module M]    list a file's imports, or who imports a module
  changed [--since 24h|7d]           symbols added/removed/modified since a cutoff
  prune   [--yes]                    quarantine indexes whose project path no longer exists

Every subcommand accepts --json for machine-readable output and --db to
target an explicit index file.

Index location: central store ~/.agents/smart-explore/indexes/<slug>-<hash>.duckdb,
shared by every agent/CLI tool that indexes the same project path. Override the
store root with SMART_EXPLORE_HOME, or a single index with --db. A pre-existing
legacy <path-root>/.smart-explore/index.duckdb is still honored.

> Byline: Claude Code · Opus 4.8 · 2026-06-21
> Byline: Claude Code · Fable 5 · 2026-07-28 (cross-tool: central index store, moved to ~/.agents/skills)
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import queue
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.parse
from pathlib import Path

import duckdb

_CAMEL = re.compile(r"(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])")


def tokenize(*parts: str) -> str:
    """Split camelCase / snake_case / dotted identifiers into searchable words
    so a query like 'shutdown' matches 'performGracefulShutdown'."""
    words = []
    for part in parts:
        if not part:
            continue
        spaced = _CAMEL.sub(" ", part)
        spaced = re.sub(r"[^A-Za-z0-9]+", " ", spaced)
        words.append(spaced.lower())
        words.append(part.lower())  # keep the whole token too
    return " ".join(words)

try:
    from tree_sitter_language_pack import get_parser
except Exception as e:  # pragma: no cover
    sys.stderr.write(
        "tree-sitter-language-pack not available in this environment: %s\n" % e
    )
    raise

# ---------------------------------------------------------------------------
# Language + symbol configuration
# ---------------------------------------------------------------------------

# file extension -> tree-sitter-language-pack language name
EXT_LANG = {
    ".py": "python", ".pyw": "python",
    ".js": "javascript", ".mjs": "javascript", ".cjs": "javascript", ".jsx": "javascript",
    ".ts": "typescript",
    ".tsx": "tsx",
    ".go": "go",
    ".rs": "rust",
    ".rb": "ruby",
    ".java": "java",
    ".c": "c", ".h": "c",
    ".cpp": "cpp", ".cc": "cpp", ".cxx": "cpp", ".hpp": "cpp", ".hh": "cpp",
    ".cs": "csharp",
    ".kt": "kotlin", ".kts": "kotlin",
    ".swift": "swift",
    ".php": "php",
    ".sh": "bash", ".bash": "bash",
    ".lua": "lua",
}

# tree-sitter node type -> human "kind". Anything in here is captured as a symbol.
NODE_KIND = {
    # python
    "function_definition": "function",
    "class_definition": "class",
    # js / ts / tsx
    "function_declaration": "function",
    "method_definition": "method",
    "class_declaration": "class",
    "interface_declaration": "interface",
    "type_alias_declaration": "type",
    "enum_declaration": "enum",
    # go
    "method_declaration": "method",
    "type_declaration": "type",
    # rust
    "function_item": "function",
    "struct_item": "struct",
    "enum_item": "enum",
    "trait_item": "trait",
    "impl_item": "impl",
    "mod_item": "module",
    # ruby
    "method": "method",
    "class": "class",
    "module": "module",
    # c / c++
    "struct_specifier": "struct",
    "class_specifier": "class",
    # c#
    "struct_declaration": "struct",
    "record_declaration": "class",
    "constructor_declaration": "method",
    "namespace_declaration": "namespace",
    # kotlin
    "object_declaration": "object",
    # swift
    "protocol_declaration": "protocol",
    # php
    "trait_declaration": "trait",
    # lua (grammar variants)
    "function_declaration_statement": "function",
    "local_function_declaration_statement": "function",
}

# node types whose text is an import/include/use statement
IMPORT_KINDS = {
    "import_statement", "import_from_statement",   # python, js/ts
    "import_declaration",                          # go, java, swift
    "use_declaration",                             # rust
    "preproc_include",                             # c / c++
    "using_directive",                             # c#
    "import_header",                               # kotlin
    "namespace_use_declaration",                   # php
}

# node types that act as containers (their children get them as `parent`)
CONTAINER_TYPES = {
    "class_definition", "class_declaration", "class_specifier", "class",
    "impl_item", "trait_item", "struct_item", "module", "mod_item",
    "interface_declaration", "type_declaration",
    "struct_declaration", "record_declaration", "namespace_declaration",
    "object_declaration", "protocol_declaration", "trait_declaration",
}

SKIP_DIRS = {
    ".git", ".svn", ".hg", "node_modules", "__pycache__", ".venv", "venv",
    "dist", "build", ".smart-explore", ".mypy_cache", ".pytest_cache",
    "target", ".next", ".cache", "vendor",
}

# ---------------------------------------------------------------------------
# DuckDB index
# ---------------------------------------------------------------------------


def connect(db_path: Path) -> duckdb.DuckDBPyConnection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + float(os.environ.get("SMART_EXPLORE_LOCK_TIMEOUT", "60"))
    while True:
        try:
            con = duckdb.connect(str(db_path))
            break
        except duckdb.IOException as exc:
            message = str(exc).lower()
            if time.monotonic() >= deadline or not any(
                    marker in message for marker in ("used by another process", "conflicting lock", "could not set lock")):
                raise
            time.sleep(0.25)
    con.execute("INSTALL fts; LOAD fts;")
    con.execute(
        """
        CREATE TABLE IF NOT EXISTS files (
            path     VARCHAR PRIMARY KEY,
            mtime    DOUBLE,
            lang     VARCHAR,
            nsym     INTEGER
        );
        """
    )
    con.execute(
        """
        CREATE TABLE IF NOT EXISTS symbols (
            id          BIGINT,
            path        VARCHAR,
            name        VARCHAR,
            kind        VARCHAR,
            parent      VARCHAR,
            start_line  INTEGER,
            end_line    INTEGER,
            signature   VARCHAR,
            search_text VARCHAR
        );
        """
    )
    con.execute("CREATE SEQUENCE IF NOT EXISTS sym_id START 1;")
    con.execute(
        """
        CREATE TABLE IF NOT EXISTS meta (
            key   VARCHAR PRIMARY KEY,
            value VARCHAR
        );
        CREATE TABLE IF NOT EXISTS imports (
            path   VARCHAR,
            module VARCHAR,
            line   INTEGER
        );
        CREATE TABLE IF NOT EXISTS history (
            ts     DOUBLE,
            path   VARCHAR,
            name   VARCHAR,
            kind   VARCHAR,
            action VARCHAR
        );
        """
    )
    return con


# NOTE: the pinned tree-sitter-language-pack 1.9.1 binding exposes node accessors
# as methods: node.kind(), node.start_byte(), node.child(i), node.child_count(),
# node.start_position().row, tree.root_node(). parse() takes str; offsets are
# byte offsets, so slice the utf-8 `src` bytes.


def node_name(node, src: bytes) -> str | None:
    field = node.child_by_field_name("name")
    if field is not None:
        return src[field.start_byte():field.end_byte()].decode("utf8", "replace")
    # fallback: first identifier-ish descendant at shallow depth
    for i in range(node.child_count()):
        child = node.child(i)
        ck = child.kind()
        if ck in (
            "identifier", "type_identifier", "field_identifier",
            "constant", "property_identifier", "scoped_identifier",
            "simple_identifier",
        ):
            return src[child.start_byte():child.end_byte()].decode("utf8", "replace")
        # C-style: name lives inside a declarator
        if "declarator" in ck:
            n = node_name(child, src)
            if n:
                return n
    return None


def signature(node, src: bytes) -> str:
    """First line of the symbol (up to the body), trimmed."""
    text = src[node.start_byte():node.end_byte()].decode("utf8", "replace")
    first = text.split("\n", 1)[0].strip()
    return first[:200]


def extract_symbols(tree, src: bytes):
    """Walk the AST, yield (name, kind, parent, start_line, end_line, signature)."""
    out = []

    def walk(node, parent_name):
        nt = node.kind()
        kind = NODE_KIND.get(nt)
        cur_parent = parent_name
        if kind:
            name = node_name(node, src)
            if name:
                out.append(
                    (
                        name, kind, parent_name,
                        node.start_position().row + 1, node.end_position().row + 1,
                        signature(node, src),
                    )
                )
                if nt in CONTAINER_TYPES:
                    cur_parent = name
        elif nt in CONTAINER_TYPES:
            # container without its own captured symbol still scopes children
            cur_parent = node_name(node, src) or parent_name
        for i in range(node.child_count()):
            walk(node.child(i), cur_parent)

    walk(tree.root_node(), None)
    return out


def extract_imports(tree, src: bytes):
    """Collect import/use/include statements as (statement_text, line)."""
    out = []

    def walk(node, depth):
        if node.kind() in IMPORT_KINDS:
            text = src[node.start_byte():node.end_byte()].decode("utf8", "replace")
            out.append((text.split("\n", 1)[0].strip()[:300], node.start_position().row + 1))
            return
        if depth >= 3:  # imports live at/near the top of the tree
            return
        for i in range(node.child_count()):
            walk(node.child(i), depth + 1)

    walk(tree.root_node(), 0)
    return out


def iter_code_files(root: Path, file_pattern: str | None):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            ext = os.path.splitext(fn)[1].lower()
            if ext not in EXT_LANG:
                continue
            p = Path(dirpath) / fn
            if file_pattern and file_pattern not in str(p):
                continue
            yield p, EXT_LANG[ext]


def index_path(con, root: Path, file_pattern: str | None = None, quiet: bool = False):
    """Incrementally (re)index all code files under root. Returns (n_files, n_changed)."""
    n_files = n_changed = 0
    con.execute(
        "INSERT INTO meta VALUES ('root', ?), ('last_indexed', ?) "
        "ON CONFLICT (key) DO UPDATE SET value = excluded.value",
        [str(root), str(time.time())],
    )
    for p, lang in iter_code_files(root, file_pattern):
        n_files += 1
        try:
            mtime = p.stat().st_mtime
        except OSError:
            continue
        rel = str(p)
        row = con.execute("SELECT mtime FROM files WHERE path = ?", [rel]).fetchone()
        if row and abs(row[0] - mtime) < 1e-6:
            continue  # unchanged
        try:
            src_text = p.read_text("utf8", "replace")
            src = src_text.encode("utf8")          # byte view for offset slicing
            parser = get_parser(lang)
            tree = parser.parse(src_text)
            syms = extract_symbols(tree, src)
            imps = extract_imports(tree, src)
        except Exception as e:
            if not quiet:
                sys.stderr.write(f"  skip {rel}: {e}\n")
            continue
        if row:
            # known file being reparsed -> record symbol-level changes
            now = time.time()
            old = {(n, k): s for n, k, s in con.execute(
                "SELECT name, kind, signature FROM symbols WHERE path = ?", [rel]).fetchall()}
            new = {(s[0], s[1]): s[5] for s in syms}
            for (n, k) in new.keys() - old.keys():
                con.execute("INSERT INTO history VALUES (?, ?, ?, ?, 'added')", [now, rel, n, k])
            for (n, k) in old.keys() - new.keys():
                con.execute("INSERT INTO history VALUES (?, ?, ?, ?, 'removed')", [now, rel, n, k])
            for key in new.keys() & old.keys():
                if old[key] != new[key]:
                    con.execute("INSERT INTO history VALUES (?, ?, ?, ?, 'modified')",
                                [now, rel, key[0], key[1]])
        con.execute("DELETE FROM imports WHERE path = ?", [rel])
        for (itext, iline) in imps:
            con.execute("INSERT INTO imports VALUES (?, ?, ?)", [rel, itext, iline])
        con.execute("DELETE FROM symbols WHERE path = ?", [rel])
        for (name, kind, parent, sl, el, sig) in syms:
            stext = tokenize(name, parent or "")
            con.execute(
                "INSERT INTO symbols VALUES (nextval('sym_id'), ?, ?, ?, ?, ?, ?, ?, ?)",
                [rel, name, kind, parent, sl, el, sig, stext],
            )
        con.execute(
            "INSERT INTO files VALUES (?, ?, ?, ?) "
            "ON CONFLICT (path) DO UPDATE SET mtime = excluded.mtime, "
            "lang = excluded.lang, nsym = excluded.nsym",
            [rel, mtime, lang, len(syms)],
        )
        n_changed += 1
    if n_changed:
        # (re)build the BM25 full-text index over symbol name + signature
        con.execute(
            "PRAGMA create_fts_index('symbols', 'id', 'search_text', 'signature', "
            "stemmer='none', overwrite=1);"
        )
    return n_files, n_changed


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------


def cmd_index(args):
    root = Path(args.path).resolve()
    con = connect(db_for(root, args.db))
    t0 = time.time()
    n_files, n_changed = index_path(con, root, args.file_pattern)
    dt = time.time() - t0
    total = con.execute("SELECT count(*) FROM symbols").fetchone()[0]
    if args.json:
        print(json.dumps({"root": str(root), "files_seen": n_files,
                          "reparsed": n_changed, "symbols_total": total, "seconds": round(dt, 1)}))
        return
    print(f"Indexed {root}")
    print(f"  files seen: {n_files}  reparsed: {n_changed}  symbols total: {total}  ({dt:.1f}s)")


def cmd_search(args):
    root = Path(args.path).resolve()
    con = connect(db_for(root, args.db))
    index_path(con, root, args.file_pattern, quiet=True)
    q = tokenize(args.query)
    like = f"%{args.query.lower()}%"
    # BM25 concept match over tokenized text + signature, UNION substring match
    # on the raw name (so partial identifiers like 'shut' still resolve).
    sql = """
        WITH bm AS (
            SELECT s.id, fts_main_symbols.match_bm25(s.id, ?) AS score
            FROM symbols s
        )
        SELECT s.name, s.kind, s.path, s.start_line, s.parent, s.signature,
               GREATEST(COALESCE(bm.score, 0),
                        CASE WHEN lower(s.name) LIKE ? THEN 0.5 ELSE 0 END) AS score
        FROM symbols s LEFT JOIN bm USING (id)
        WHERE bm.score IS NOT NULL OR lower(s.name) LIKE ?
        ORDER BY score DESC, length(s.name)
        LIMIT ?
        """
    params = [q, like, like, args.max]
    if not con.execute("SELECT count(*) FROM symbols").fetchone()[0]:
        rows = []
    else:
        try:
            rows = con.execute(sql, params).fetchall()
        except duckdb.CatalogException as exc:
            if "fts_main_symbols.match_bm25" not in str(exc):
                raise
            con.execute(
                "PRAGMA create_fts_index('symbols', 'id', 'search_text', 'signature', "
                "stemmer='none', overwrite=1);"
            )
            rows = con.execute(sql, params).fetchall()
    results = [
        {"name": name, "kind": kind, "file": os.path.relpath(path, root), "line": line,
         "parent": parent, "signature": sig, "score": round(score, 3)}
        for name, kind, path, line, parent, sig, score in rows
    ]
    if args.json:
        print(json.dumps({"query": args.query, "root": str(root), "results": results}, indent=1))
        return
    if not results:
        print(f"No symbols matched '{args.query}' under {root}")
        return
    print("-- Matching Symbols --")
    files = {}
    for r in results:
        qual = f"{r['parent']}." if r["parent"] else ""
        print(f"  {r['kind']} {qual}{r['name']}  ({r['file']}:{r['line']})")
        files[r["file"]] = files.get(r["file"], 0) + 1
    print("\n-- Folded File Views --")
    for rel, n in sorted(files.items(), key=lambda x: -x[1]):
        print(f"  {rel} ({n} symbols)")


def cmd_outline(args):
    fp = Path(args.file).resolve()
    root = fp.parent
    con = connect(db_for(root, args.db))
    index_path(con, root, str(fp.name), quiet=True)
    rows = con.execute(
        "SELECT kind, name, parent, start_line, signature FROM symbols "
        "WHERE path = ? ORDER BY start_line",
        [str(fp)],
    ).fetchall()
    if args.json:
        print(json.dumps({"file": str(fp), "symbols": [
            {"kind": k, "name": n, "parent": p, "line": l, "signature": s}
            for k, n, p, l, s in rows]}, indent=1))
        return
    if not rows:
        print(f"No symbols found in {fp} (unsupported language or empty).")
        return
    print(f"# Outline: {fp.name}")
    for kind, name, parent, line, sig in rows:
        indent = "  " if parent else ""
        print(f"{indent}{kind} {name}  (L{line})")


def cmd_unfold(args):
    fp = Path(args.file).resolve()
    root = fp.parent
    con = connect(db_for(root, args.db))
    index_path(con, root, str(fp.name), quiet=True)
    rows = con.execute(
        "SELECT start_line, end_line, kind, parent FROM symbols "
        "WHERE path = ? AND name = ? ORDER BY start_line",
        [str(fp), args.symbol],
    ).fetchall()
    if not rows:
        if args.json:
            print(json.dumps({"file": str(fp), "symbol": args.symbol, "matches": []}))
        else:
            print(f"Symbol '{args.symbol}' not found in {fp.name}.")
        return
    lines = fp.read_text("utf8", "replace").splitlines()
    if args.json:
        print(json.dumps({"file": str(fp), "symbol": args.symbol, "matches": [
            {"kind": kind, "parent": parent, "start_line": sl, "end_line": el,
             "source": "\n".join(lines[sl - 1:el])}
            for sl, el, kind, parent in rows]}, indent=1))
        return
    for sl, el, kind, parent in rows:
        qual = f"{parent}." if parent else ""
        print(f"# {kind} {qual}{args.symbol}  ({fp.name}:{sl}-{el})")
        print("\n".join(lines[sl - 1:el]))
        print()


def central_store() -> Path:
    return Path(os.environ.get("SMART_EXPLORE_HOME", str(Path.home() / ".agents" / "smart-explore"))) / "indexes"


def db_for(root: Path, override: str | None) -> Path:
    if override:
        return Path(override).resolve()
    legacy = root / ".smart-explore" / "index.duckdb"
    if legacy.exists():
        return legacy
    slug = re.sub(r"[^A-Za-z0-9]+", "-", root.name).strip("-") or "root"
    digest = hashlib.sha256(str(root).lower().encode()).hexdigest()[:12]
    return central_store() / f"{slug}-{digest}.duckdb"


# ---------------------------------------------------------------------------
# LSP (type-resolved references)
# ---------------------------------------------------------------------------

# language -> candidate server commands, tried in order via PATH lookup
LSP_SERVERS = {
    "python": [["pyright-langserver", "--stdio"], ["pylsp"], ["jedi-language-server"]],
    "typescript": [["typescript-language-server", "--stdio"]],
    "tsx": [["typescript-language-server", "--stdio"]],
    "javascript": [["typescript-language-server", "--stdio"]],
    "go": [["gopls"]],
    "rust": [["rust-analyzer"]],
    "c": [["clangd"]],
    "cpp": [["clangd"]],
    "csharp": [["csharp-ls"], ["OmniSharp", "-lsp"]],
    "kotlin": [["kotlin-language-server"]],
    "swift": [["sourcekit-lsp"]],
    "php": [["intelephense", "--stdio"]],
    "bash": [["bash-language-server", "start"]],
    "lua": [["lua-language-server"]],
    "ruby": [["solargraph", "stdio"]],
    "java": [["jdtls"]],
}


def find_lsp_server(lang: str):
    """Return an argv for the first available LSP server for `lang`, else None."""
    for cand in LSP_SERVERS.get(lang, []):
        exe = shutil.which(cand[0])
        if exe:
            return [exe] + cand[1:]
    if lang == "python":
        # the skill venv bundles python-lsp-server as a zero-setup fallback
        try:
            import pylsp  # noqa: F401
            return [sys.executable, "-m", "pylsp"]
        except ImportError:
            pass
    return None


def uri_to_path(uri: str) -> str:
    p = urllib.parse.unquote(urllib.parse.urlparse(uri).path)
    if re.match(r"^/[A-Za-z]:", p):  # windows: /C:/...
        p = p[1:]
    return str(Path(p))


class LSPClient:
    """Minimal JSON-RPC-over-stdio LSP client: initialize, didOpen, references."""

    def __init__(self, cmd, root: Path):
        self.proc = subprocess.Popen(
            cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, cwd=str(root))
        self._id = 0
        self._q: queue.Queue = queue.Queue()
        threading.Thread(target=self._reader, daemon=True).start()

    def _reader(self):
        f = self.proc.stdout
        while True:
            headers = {}
            line = f.readline()
            if not line:
                return
            while line and line.strip():
                k, _, v = line.decode("ascii", "replace").partition(":")
                headers[k.strip().lower()] = v.strip()
                line = f.readline()
            n = int(headers.get("content-length", 0))
            if n <= 0:
                continue
            body = f.read(n)
            try:
                self._q.put(json.loads(body))
            except ValueError:
                pass

    def _send(self, msg):
        data = json.dumps(msg).encode()
        self.proc.stdin.write(b"Content-Length: %d\r\n\r\n" % len(data) + data)
        self.proc.stdin.flush()

    def notify(self, method, params):
        self._send({"jsonrpc": "2.0", "method": method, "params": params})

    def request(self, method, params, timeout=60.0):
        self._id += 1
        rid = self._id
        self._send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        deadline = time.time() + timeout
        while True:
            remain = deadline - time.time()
            if remain <= 0:
                raise TimeoutError(f"LSP request {method} timed out after {timeout}s")
            try:
                msg = self._q.get(timeout=min(remain, 1.0))
            except queue.Empty:
                if self.proc.poll() is not None:
                    raise RuntimeError("LSP server exited unexpectedly")
                continue
            if msg.get("id") == rid and ("result" in msg or "error" in msg):
                if "error" in msg:
                    raise RuntimeError(f"LSP error: {msg['error']}")
                return msg["result"]
            if "method" in msg and "id" in msg:
                # server-initiated request: answer generically so it can proceed
                result = None
                if msg["method"] == "workspace/configuration":
                    result = [None] * len(msg.get("params", {}).get("items", []))
                self._send({"jsonrpc": "2.0", "id": msg["id"], "result": result})
            # notifications (diagnostics, progress, logs) are dropped

    def close(self):
        try:
            self.request("shutdown", None, timeout=5)
            self.notify("exit", None)
        except Exception:
            pass
        try:
            self.proc.kill()
        except OSError:
            pass


def lsp_references(root: Path, def_file: Path, line0: int, char0: int,
                   lang: str, timeout: float):
    """Ask the language server for type-resolved references at a position."""
    cmd = find_lsp_server(lang)
    if not cmd:
        return None, f"no LSP server for {lang} on PATH " \
                     f"(tried: {', '.join(c[0] for c in LSP_SERVERS.get(lang, []))})"
    client = LSPClient(cmd, root)
    try:
        client.request("initialize", {
            "processId": None,
            "rootUri": root.as_uri(),
            "workspaceFolders": [{"uri": root.as_uri(), "name": root.name}],
            "capabilities": {},
        }, timeout=timeout)
        client.notify("initialized", {})
        client.notify("textDocument/didOpen", {"textDocument": {
            "uri": def_file.as_uri(), "languageId": lang, "version": 1,
            "text": def_file.read_text("utf8", "replace"),
        }})
        locs = client.request("textDocument/references", {
            "textDocument": {"uri": def_file.as_uri()},
            "position": {"line": line0, "character": char0},
            "context": {"includeDeclaration": True},
        }, timeout=timeout) or []
        return locs, None
    finally:
        client.close()


def cmd_lsp(args):
    """Report which LSP servers are available per language."""
    langs = sorted(set(EXT_LANG.values()))
    rows = []
    for lang in langs:
        cmd = find_lsp_server(lang)
        rows.append({"language": lang, "server": " ".join(cmd) if cmd else None,
                     "candidates": [c[0] for c in LSP_SERVERS.get(lang, [])]})
    if args.json:
        print(json.dumps({"servers": rows}, indent=1))
        return
    print("-- LSP server availability --")
    for r in rows:
        status = r["server"] or f"none (would use: {', '.join(r['candidates']) or '-'})"
        print(f"  {r['language']:<11} {status}")


def store_entries():
    """Scan the central store; yield one info dict per index db."""
    store = central_store()
    dbs = sorted(store.glob("*.duckdb")) if store.exists() else []
    for db in dbs:
        entry = {"db": str(db), "name": db.name, "size_kb": db.stat().st_size // 1024,
                 "updated": time.strftime("%Y-%m-%d %H:%M", time.localtime(db.stat().st_mtime))}
        wal = db.with_suffix(db.suffix + ".wal")
        if wal.exists():
            entry.update(root=None, files=None, symbols=None, langs=[], stale=False,
                         error="active_or_unclean_wal; metadata inspection skipped")
            yield entry
            continue
        try:
            con = duckdb.connect(str(db), read_only=True)
            has_meta = con.execute(
                "SELECT count(*) FROM information_schema.tables WHERE table_name='meta'").fetchone()[0]
            root = (con.execute("SELECT value FROM meta WHERE key='root'").fetchone() or [None])[0] \
                if has_meta else None
            entry.update(
                root=root,
                files=con.execute("SELECT count(*) FROM files").fetchone()[0],
                symbols=con.execute("SELECT count(*) FROM symbols").fetchone()[0],
                langs=[r[0] for r in con.execute(
                    "SELECT lang FROM files GROUP BY lang ORDER BY count(*) DESC LIMIT 4").fetchall()],
                stale=bool(root) and not Path(root).exists(),
                error=None,
            )
            con.close()
        except Exception as e:
            entry.update(root=None, files=None, symbols=None, langs=[],
                         stale=False, error=str(e)[:80])
        yield entry


def cmd_indexes(args):
    """List every index in the central store with its project and stats."""
    entries = list(store_entries())
    if args.json:
        print(json.dumps({"store": str(central_store()), "indexes": entries}, indent=1))
        return
    if not entries:
        print(f"No indexes in {central_store()}")
        return
    print(f"-- Indexes in {central_store()} --")
    for e in entries:
        if e["error"]:
            print(f"  {e['name']}  ({e['size_kb']}K)  [unreadable: {e['error']}]")
            continue
        root = e["root"] or "<pre-meta index; re-run any command on it to record its root>"
        stale = "  [project path missing]" if e["stale"] else ""
        print(f"  {e['name']}")
        print(f"    project: {root}{stale}")
        print(f"    files: {e['files']}  symbols: {e['symbols']}  langs: {', '.join(e['langs']) or '-'}"
              f"  size: {e['size_kb']}K  updated: {e['updated']}")


def refs_via_lsp(args, root: Path, con) -> bool:
    """Type-resolved references via a language server. Returns True on success."""
    d = con.execute(
        "SELECT path, start_line FROM symbols WHERE name = ? ORDER BY path LIMIT 1",
        [args.symbol]).fetchone()
    if not d:
        sys.stderr.write(f"[lsp] no indexed definition of '{args.symbol}' to anchor on; "
                         "falling back to lexical scan\n")
        return False
    def_file, def_line = Path(d[0]), d[1]
    lang = EXT_LANG.get(def_file.suffix.lower())
    try:
        line_text = def_file.read_text("utf8", "replace").splitlines()[def_line - 1]
        char0 = max(line_text.find(args.symbol), 0)
    except (OSError, IndexError):
        return False
    try:
        locs, err = lsp_references(root, def_file, def_line - 1, char0, lang, args.timeout)
    except Exception as e:
        sys.stderr.write(f"[lsp] {e}; falling back to lexical scan\n")
        return False
    if err:
        sys.stderr.write(f"[lsp] {err}; falling back to lexical scan\n")
        return False
    results = []
    def_file = def_file.resolve()
    for loc in locs:
        fpath = str(Path(uri_to_path(loc["uri"])).resolve())
        ln = loc["range"]["start"]["line"] + 1
        try:
            text = Path(fpath).read_text("utf8", "replace").splitlines()[ln - 1].strip()[:160]
        except (OSError, IndexError):
            text = ""
        enc = con.execute(
            "SELECT name, kind FROM symbols WHERE path = ? AND start_line <= ? "
            "AND end_line >= ? ORDER BY (end_line - start_line) LIMIT 1",
            [fpath, ln, ln]).fetchone()
        is_def = (str(Path(fpath)) == str(def_file) and ln == def_line)
        try:
            rel = os.path.relpath(fpath, root)
        except ValueError:
            rel = fpath
        results.append({"file": rel, "line": ln, "type": "def" if is_def else "ref",
                        "in": f"{enc[1]} {enc[0]}" if enc else None, "text": text})
    if args.json:
        print(json.dumps({"symbol": args.symbol, "root": str(root), "resolver": "lsp",
                          "definitions": [r for r in results if r["type"] == "def"],
                          "references": [r for r in results if r["type"] == "ref"]}, indent=1))
        return True
    print(f"-- Type-resolved references for '{args.symbol}' (LSP, {len(results)} locations) --")
    for r in results:
        tag = "def" if r["type"] == "def" else "ref"
        where = f"  [in {r['in']}]" if r["in"] else ""
        print(f"  {tag}  {r['file']}:{r['line']}{where}  {r['text']}")
    return True


def cmd_refs(args):
    """Find usages/call sites of a symbol name across the indexed tree."""
    root = Path(args.path).resolve()
    con = connect(db_for(root, args.db))
    index_path(con, root, args.file_pattern, quiet=True)
    if args.lsp and refs_via_lsp(args, root, con):
        return
    pat = re.compile(r"\b" + re.escape(args.symbol) + r"\b")
    def_lines = {(p, sl) for p, sl in con.execute(
        "SELECT path, start_line FROM symbols WHERE name = ?", [args.symbol]).fetchall()}
    hits = []
    for (fpath,) in con.execute("SELECT path FROM files ORDER BY path").fetchall():
        try:
            text = Path(fpath).read_text("utf8", "replace")
        except OSError:
            continue
        for i, line in enumerate(text.splitlines(), 1):
            if pat.search(line):
                enc = con.execute(
                    "SELECT name, kind FROM symbols WHERE path = ? AND start_line <= ? "
                    "AND end_line >= ? ORDER BY (end_line - start_line) LIMIT 1",
                    [fpath, i, i]).fetchone()
                hits.append({
                    "file": os.path.relpath(fpath, root), "line": i,
                    "type": "def" if (fpath, i) in def_lines else "ref",
                    "in": f"{enc[1]} {enc[0]}" if enc else None,
                    "text": line.strip()[:160],
                })
        if sum(1 for h in hits if h["type"] == "ref") >= args.max:
            break
    refs = [h for h in hits if h["type"] == "ref"][: args.max]
    defs = [h for h in hits if h["type"] == "def"]
    if args.json:
        print(json.dumps({"symbol": args.symbol, "root": str(root),
                          "definitions": defs, "references": refs}, indent=1))
        return
    if not hits:
        print(f"No occurrences of '{args.symbol}' under {root}")
        return
    if defs:
        print("-- Definitions --")
        for h in defs:
            print(f"  {h['file']}:{h['line']}  {h['text']}")
    print(f"-- References ({len(refs)}) --")
    for h in refs:
        where = f"  [in {h['in']}]" if h["in"] else ""
        print(f"  {h['file']}:{h['line']}{where}  {h['text']}")


def cmd_imports(args):
    """List a file's imports, or find which files import a given module."""
    root = Path(args.path).resolve()
    con = connect(db_for(root, args.db))
    index_path(con, root, None, quiet=True)
    if args.file:
        fp = str(Path(args.file).resolve())
        rows = con.execute(
            "SELECT module, line FROM imports WHERE path = ? ORDER BY line", [fp]).fetchall()
        data = {"file": fp, "imports": [{"import": m, "line": l} for m, l in rows]}
        if args.json:
            print(json.dumps(data, indent=1)); return
        print(f"# Imports: {Path(fp).name}")
        for m, l in rows:
            print(f"  L{l}: {m}")
        if not rows:
            print("  (none recorded)")
    elif args.module:
        rows = con.execute(
            "SELECT path, module, line FROM imports WHERE module ILIKE ? ORDER BY path, line",
            [f"%{args.module}%"]).fetchall()
        data = {"module": args.module, "imported_by": [
            {"file": os.path.relpath(p, root), "import": m, "line": l} for p, m, l in rows]}
        if args.json:
            print(json.dumps(data, indent=1)); return
        print(f"-- Files importing '{args.module}' ({len(rows)}) --")
        for p, m, l in rows:
            print(f"  {os.path.relpath(p, root)}:{l}  {m}")
    else:
        rows = con.execute(
            "SELECT module, count(*) AS n FROM imports GROUP BY module ORDER BY n DESC LIMIT ?",
            [args.max]).fetchall()
        data = {"root": str(root), "top_imports": [{"import": m, "count": n} for m, n in rows]}
        if args.json:
            print(json.dumps(data, indent=1)); return
        print(f"-- Most-imported modules under {root} --")
        for m, n in rows:
            print(f"  {n:>4}  {m}")


def parse_since(s: str) -> float:
    m = re.fullmatch(r"(\d+)([mhd])", s.strip().lower())
    if not m:
        raise SystemExit(f"bad --since '{s}' (use e.g. 90m, 24h, 7d)")
    return int(m.group(1)) * {"m": 60, "h": 3600, "d": 86400}[m.group(2)]


def cmd_changed(args):
    """List symbols added/removed/modified since a time cutoff."""
    root = Path(args.path).resolve()
    con = connect(db_for(root, args.db))
    index_path(con, root, None, quiet=True)  # pick up the latest edits first
    cutoff = time.time() - parse_since(args.since)
    rows = con.execute(
        "SELECT ts, path, name, kind, action FROM history WHERE ts >= ? "
        "ORDER BY ts DESC LIMIT ?", [cutoff, args.max]).fetchall()
    changes = [{"when": time.strftime("%Y-%m-%d %H:%M", time.localtime(ts)),
                "file": os.path.relpath(p, root), "name": n, "kind": k, "action": a}
               for ts, p, n, k, a in rows]
    if args.json:
        print(json.dumps({"root": str(root), "since": args.since, "changes": changes}, indent=1))
        return
    if not changes:
        print(f"No recorded symbol changes under {root} in the last {args.since}.")
        print("(Changes are recorded when a previously-indexed file is reparsed.)")
        return
    print(f"-- Symbol changes in the last {args.since} ({len(changes)}) --")
    for c in changes:
        print(f"  {c['when']}  {c['action']:<9} {c['kind']} {c['name']}  ({c['file']})")


def cmd_prune(args):
    """Quarantine central-store indexes whose project path no longer exists."""
    stale = [e for e in store_entries()
             if e["stale"] or (e["error"] and not e["error"].startswith("active_or_unclean_wal"))]
    if args.json and not args.yes:
        print(json.dumps({"would_quarantine": stale, "note": "re-run with --yes to move into to_be_deleted"}, indent=1))
        return
    if not stale:
        print("Nothing to prune — every index maps to an existing project path.")
        return
    if not args.yes:
        print("-- Would quarantine (dry run; re-run with --yes to move into to_be_deleted) --")
        for e in stale:
            why = e["error"] and f"unreadable: {e['error']}" or f"project path missing: {e['root']}"
            print(f"  {e['name']}  ({e['size_kb']}K)  [{why}]")
        return
    removed = []
    quarantine = central_store() / "to_be_deleted" / time.strftime("prune-%Y%m%dT%H%M%SZ", time.gmtime())
    quarantine.mkdir(parents=True, exist_ok=True)
    for e in stale:
        try:
            shutil.move(e["db"], quarantine / e["name"])
            removed.append(e["name"])
        except OSError as err:
            print(f"  failed to remove {e['name']}: {err}")
    if args.json:
        print(json.dumps({"quarantined": removed, "destination": str(quarantine)}))
    else:
        print(f"Quarantined {len(removed)} stale index(es) at {quarantine}: {', '.join(removed)}")


def _reconcile_module():
    import reconciliation
    return reconciliation


def cmd_stores(args):
    rec = _reconcile_module()
    print(json.dumps({"schema": rec.SCHEMA, "operation": "stores",
                      "project_root": str(Path(args.path).resolve()),
                      "stores": rec.inventory(args.path)}, indent=1))


def _selected(args):
    selected = []
    for value in args.stores or []:
        selected.extend(x.strip() for x in value.split(",") if x.strip())
    return selected


def cmd_recall(args):
    rec = _reconcile_module()
    payload = rec.recall(args.query, args.path, args.mode, _selected(args), args.limit)
    payload["operation"] = args.output_operation
    if args.output_operation == "conflicts":
        payload["results"] = []
    elif args.output_operation == "decisions":
        payload["results"] = payload["decisions"] + payload["contracts"]
    print(json.dumps(payload, indent=1))


def _ccc_command(args, command):
    rec = _reconcile_module()
    root = str(Path(args.path).resolve())
    ccc = rec.inventory(root)["ccc"]
    if not ccc["adapter"]:
        raise SystemExit("ccc is not installed")
    argv = [ccc["adapter"], command]
    if command == "search":
        for lang in args.lang or []:
            argv.extend(["--lang", lang])
        if args.file_path:
            argv.extend(["--path", args.file_path])
        argv.extend(["--offset", str(args.offset), "--limit", str(args.limit), "--json", args.query])
    elif command == "grep":
        argv.append(args.query)
    env = os.environ.copy()
    env.setdefault("PYTHONUTF8", "1")
    cp = subprocess.run(argv, cwd=root, text=True, capture_output=True, env=env,
                        encoding="utf-8", errors="replace")
    if cp.returncode:
        raise SystemExit(cp.stderr.strip() or f"ccc {command} failed ({cp.returncode})")
    print(cp.stdout, end="" if cp.stdout.endswith("\n") else "\n")


def cmd_semantic(args):
    _ccc_command(args, "search")


def cmd_ccc_lifecycle(args):
    _ccc_command(args, args.ccc_action)


def cmd_reconcile(args):
    rec = _reconcile_module()
    if args.action in {"run", "repair"}:
        payload = rec.recall(args.query, args.path, args.mode, _selected(args), args.limit)
        payload["operation"] = "reconcile_repair" if args.action == "repair" else "reconcile_run"
        payload = rec.persist_packet(payload, args.output_dir)
        if args.action == "repair":
            payload["repair_requested"] = True
            payload["repair_status"] = "clean_no_action" if payload["attribution_clean"] else "agent_action_required"
    else:
        packet = Path(args.packet).resolve()
        saved = json.loads(packet.read_text(encoding="utf-8"))
        payload = {"schema": rec.SCHEMA, "operation": "reconcile_status",
                   "packet": str(packet), "run_id": saved.get("run_id"),
                   "attribution_clean": saved.get("attribution_clean"),
                   "agent_loop": saved.get("agent_loop"),
                   "conflict_count": len(saved.get("conflicts", [])),
                   "errors": saved.get("errors", [])}
    print(json.dumps(payload, indent=1))


def cmd_export(args):
    packet = Path(args.packet).resolve()
    payload = json.loads(packet.read_text(encoding="utf-8"))
    if args.format == "json":
        text = json.dumps(payload, indent=2)
    else:
        text = (f"# Reconciliation export {payload.get('run_id', 'unknown')}\n\n"
                f"Query: {payload.get('query', '')}\n\n"
                f"Attribution clean: **{payload.get('attribution_clean', False)}**\n\n"
                f"Conflicts: {len(payload.get('conflicts', []))}\n"
                f"Decisions: {len(payload.get('decisions', []))}\n"
                f"Contracts: {len(payload.get('contracts', []))}\n")
    if args.output:
        Path(args.output).write_text(text, encoding="utf-8")
        print(json.dumps({"operation": "export", "output": str(Path(args.output).resolve())}, indent=1))
    else:
        print(text)


def _packet_graph(packet_path):
    packet = Path(packet_path).resolve()
    payload = json.loads(packet.read_text(encoding="utf-8"))
    return packet, payload, payload.get("graph", {"nodes": [], "edges": []})


def cmd_graph_query(args):
    packet, payload, graph = _packet_graph(args.packet)
    nodes = graph.get("nodes", [])
    if args.node_type: nodes = [n for n in nodes if n.get("type") == args.node_type]
    if args.store: nodes = [n for n in nodes if n.get("store") == args.store or n.get("id") == f"store:{args.store}"]
    if args.text:
        needle = args.text.lower()
        nodes = [n for n in nodes if needle in json.dumps(n, default=str).lower()]
    nodes = nodes[:args.limit]; ids = {n.get("id") for n in nodes}
    edges = [e for e in graph.get("edges", []) if e.get("from") in ids or e.get("to") in ids]
    print(json.dumps({"operation":"reconcile_graph_query","packet":str(packet),"run_id":payload.get("run_id"),"nodes":nodes,"edges":edges,"next_actions":payload.get("next_actions",[])}, indent=1))


def cmd_graph_preview(args):
    packet, payload, graph = _packet_graph(args.packet)
    nodes=graph.get("nodes",[]); edges=graph.get("edges",[])
    print(json.dumps({"operation":"reconcile_graph_preview","packet":str(packet),"run_id":payload.get("run_id"),"attribution_clean":payload.get("attribution_clean"),"counts":{"nodes":len(nodes),"edges":len(edges),"conflicts":len(payload.get("conflicts",[])),"decisions":len(payload.get("decisions",[])),"contracts":len(payload.get("contracts",[]))},"nodes":nodes[:args.limit],"edges":edges[:args.limit],"actionable_backlog":payload.get("actionable_backlog",[]),"next_actions":payload.get("next_actions",[])}, indent=1))


def main():
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--db", help="explicit path to the index .duckdb file")
    common.add_argument("--json", action="store_true", help="machine-readable JSON output")

    ap = argparse.ArgumentParser(prog="smart_explore", description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("index", parents=[common])
    p.add_argument("path"); p.add_argument("--file-pattern")
    p.set_defaults(func=cmd_index)

    p = sub.add_parser("indexes", aliases=["list"], parents=[common],
                       help="list all indexes in the central store")
    p.set_defaults(func=cmd_indexes)

    p = sub.add_parser("search", parents=[common])
    p.add_argument("query"); p.add_argument("--path", default=".")
    p.add_argument("--max", type=int, default=20); p.add_argument("--file-pattern")
    p.set_defaults(func=cmd_search)

    p = sub.add_parser("outline", parents=[common]); p.add_argument("file")
    p.set_defaults(func=cmd_outline)

    p = sub.add_parser("unfold", parents=[common])
    p.add_argument("file"); p.add_argument("symbol")
    p.set_defaults(func=cmd_unfold)

    p = sub.add_parser("refs", parents=[common], help="find usages/call sites of a symbol")
    p.add_argument("symbol"); p.add_argument("--path", default=".")
    p.add_argument("--max", type=int, default=30); p.add_argument("--file-pattern")
    p.add_argument("--lsp", action="store_true",
                   help="type-resolved references via a language server (falls back to lexical)")
    p.add_argument("--timeout", type=float, default=60.0,
                   help="LSP request timeout in seconds")
    p.set_defaults(func=cmd_refs)

    p = sub.add_parser("lsp", parents=[common], help="show LSP server availability per language")
    p.set_defaults(func=cmd_lsp)

    p = sub.add_parser("imports", parents=[common],
                       help="list a file's imports, or who imports a module")
    p.add_argument("--file"); p.add_argument("--module")
    p.add_argument("--path", default="."); p.add_argument("--max", type=int, default=40)
    p.set_defaults(func=cmd_imports)

    p = sub.add_parser("changed", parents=[common],
                       help="symbols added/removed/modified since a cutoff")
    p.add_argument("--since", default="24h"); p.add_argument("--path", default=".")
    p.add_argument("--max", type=int, default=100)
    p.set_defaults(func=cmd_changed)

    p = sub.add_parser("prune", parents=[common],
                       help="quarantine indexes whose project path no longer exists")
    p.add_argument("--yes", action="store_true", help="move into to_be_deleted (default: dry run)")
    p.set_defaults(func=cmd_prune)

    p = sub.add_parser("stores", parents=[common], help="inventory selectable code, docs, and memory stores")
    p.add_argument("--path", default="."); p.set_defaults(func=cmd_stores)

    p = sub.add_parser("semantic", parents=[common], help="direct natural-language CCC code search")
    p.add_argument("query"); p.add_argument("--path", default=".")
    p.add_argument("--lang", action="append"); p.add_argument("--file-path")
    p.add_argument("--offset", type=int, default=0); p.add_argument("--limit", type=int, default=10)
    p.set_defaults(func=cmd_semantic)

    for action, help_text in (("ccc-index", "refresh the separate CCC code index"),
                              ("ccc-status", "show CCC code-index status"),
                              ("ccc-doctor", "run CCC health checks")):
        p = sub.add_parser(action, parents=[common], help=help_text)
        p.add_argument("--path", default=".")
        p.set_defaults(func=cmd_ccc_lifecycle, ccc_action=action.split("-", 1)[1])
    p = sub.add_parser("ccc-grep", parents=[common], help="structural grep via CCC")
    p.add_argument("--path", default="."); p.add_argument("--query", required=True)
    p.set_defaults(func=cmd_ccc_lifecycle, ccc_action="grep")

    def add_recall_options(parser):
        parser.add_argument("query"); parser.add_argument("--path", default=".")
        parser.add_argument("--mode", choices=["auto", "all", "selected"], default="auto")
        parser.add_argument("--stores", action="append", help="comma separated; repeatable")
        parser.add_argument("--limit", type=int, default=20)

    p = sub.add_parser("recall", parents=[common], help="query selected structural, semantic, docs, and memory stores")
    add_recall_options(p); p.set_defaults(func=cmd_recall, output_operation="recall")
    p = sub.add_parser("conflicts", parents=[common], help="discover cross-store conflicts with provenance")
    add_recall_options(p); p.set_defaults(func=cmd_recall, output_operation="conflicts")
    p = sub.add_parser("decisions", parents=[common], help="find governing decisions and final contracts")
    add_recall_options(p); p.set_defaults(func=cmd_recall, output_operation="decisions")

    p = sub.add_parser("reconcile", parents=[common], help="run or inspect an adjudication packet")
    rp = p.add_subparsers(dest="action", required=True)
    run = rp.add_parser("run"); add_recall_options(run); run.add_argument("--output-dir")
    repair = rp.add_parser("repair"); add_recall_options(repair); repair.add_argument("--output-dir")
    status = rp.add_parser("status"); status.add_argument("packet")
    p.set_defaults(func=cmd_reconcile)

    p = sub.add_parser("graph-query", parents=[common], help="query nodes and incident edges in a reconciliation graph")
    p.add_argument("packet"); p.add_argument("--node-type"); p.add_argument("--store"); p.add_argument("--text"); p.add_argument("--limit",type=int,default=50); p.set_defaults(func=cmd_graph_query)

    p = sub.add_parser("graph-preview", parents=[common], help="preview graph counts, samples, and valid next actions")
    p.add_argument("packet"); p.add_argument("--limit",type=int,default=10); p.set_defaults(func=cmd_graph_preview)

    p = sub.add_parser("export", parents=[common], help="export a persisted reconciliation packet")
    p.add_argument("packet"); p.add_argument("--format", choices=["json", "md"], default="md")
    p.add_argument("--output"); p.set_defaults(func=cmd_export)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
