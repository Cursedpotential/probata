"""
flow_docs.py — CocoIndex flow: probata docs -> SurrealDB `document` + `chunk`.

Byline: Claude Code · Opus 5 · 2026-09-09 (v5 — rewritten FROM the CocoIndex
cookbook patterns, after v1-v4 caused a 17 GB resident set and took the
owner's machine down.)

=============================================================================
WRITTEN FROM THE COOKBOOK, NOT INVENTED
=============================================================================
The cookbook states the core pattern in one line:

    TargetState = Transform(SourceState)
    1. read source state   2. transform   3. declare target state

and all three worked examples apply it the same way:

  Pattern 1 (file transform)  localfs.walk_dir(...) then
                              mount_each(process_file, files.items(), ...),
                              with @coco.fn(memo=True) on the file component.
  Pattern 2 (vector pipeline) process_file splits the text, then
                              `await coco.map(process_chunk, chunks, ...)`;
                              process_chunk declares ONE row for ONE chunk
                              with its embedding. Never a list, never a bundle.
  Pattern 3 (db -> db)        mount_each over a streamed source; the leaf
                              declares a single target row.

v1-v4 did the inverse, and that is the entire bug:

  - v4 built ONE target state per document holding EVERY chunk row and every
    2048-float embedding, so the whole corpus went resident before a single
    write.
  - v4 ran `asyncio.gather` over 489 `use_mount` calls, which keeps every
    component's value alive in the parent until the last finishes.
    `mount_each` is the documented API for a list and retains nothing.
  - v4 registered a custom memo-key function that re-read and re-hashed every
    file, when `FileLike` already carries `content_fingerprint`.
  - v4 hand-rolled a TargetHandler, a sink and its own fingerprinting instead
    of using the connector's table target.

v5 follows the templates. Live memory is one chunk row per in-flight slot,
not one corpus.

CHANGE DETECTION. `@coco.fn(memo=True)` on `process_file(file: FileLike, ...)`
keys on the file resource, whose `content_fingerprint` is content-derived, so a
text edit re-runs that file and nothing else does. The mapping CSV's own
fingerprint is an argument too, so a metadata-only edit (doc_type/status in the
CSV) also invalidates the memo.

THE ONE SCHEMA DEVIATION. The built-in SurrealDB target serialises rows as
JSON, so it cannot write `chunk.document` as `record<document>` — a JSON string
is not coerced into a record link (verified live). The cookbook's own answers
are to denormalise (Pattern 2 keeps `filename: str` on the chunk row) or to use
a relation target (the SurrealDB example links with `mount_relation_target`).
The chunk row carries `source_path` denormalised (Pattern 2) for scope
filtering, and the chunk->document link is a RELATION written by the
connector's RelationTarget as `chunk:x->chunk_of->document:y`. There is no
`chunk.document` field and no backfill pass: CDC owns the edge like any row.
Schema DEFINEs live in scripts/docstore/schema/ and are applied by SurrealKit,
not by this file.

TEXT PASS. `body` stores FileLike.read_text, which does NOT translate newlines
-- CRLF is preserved verbatim -- and `content_hash` is the digest of that same
text, so the two always agree. Any checker must therefore hash
`read_bytes().decode("utf-8")`, NOT `Path.read_text()`: the latter folds
CRLF->LF and reports correctly-written CRLF documents as stale (98 false
positives on this corpus, 2026-09-09). Chunk/embedding text additionally gets a lossless `ftfy.fix_text` with
NFC. ASCII folding for search lives in the `doc_text` analyzer, never in data.

MEMORY GUARD. A sampler thread aborts the process if the resident set crosses
DOCSTORE_MAX_RSS_MB (default 2048). Measured 2026-09-09: ~225 MB is fixed
import cost (litellm alone is ~170 MB) and a full 489-document run peaks near
1350 MB, so 1024 was below the floor rather than a safety margin. This is a workstation, not a server: a
runaway ingest must die rather than swap the desktop to a standstill.

Usage:
    "C:/Users/matts/.local/bin/python3.exe" flow_docs.py
    DOCSTORE_ONLY_FILES="docs/a.md,docs/b.md" ... flow_docs.py   # scoped
"""

from __future__ import annotations

import asyncio
import csv
import hashlib
import os
import pathlib
import re
import sys
import threading
import time
import unicodedata
from dataclasses import dataclass
from typing import Annotated, AsyncIterator, Optional

import cocoindex as coco
import ftfy
import psutil
from cocoindex.connectors import localfs, surrealdb
from cocoindex.connectors.surrealdb import SurrealType
from cocoindex.ops.litellm import LiteLLMEmbedder
from cocoindex.ops.text import RecursiveSplitter
from cocoindex.resources.chunk import Chunk
from cocoindex.resources.file import FileLike, PatternFilePathMatcher
from numpy.typing import NDArray

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
DOCS_DIR = REPO_ROOT / "docs"

# --- state isolation -------------------------------------------------------
# ccc (the cocoindex-code uv tool) runs its own CocoIndex app on this machine.
#
# ISOLATION (docs/advanced_topics/multiple_environments). The docs' own table:
#   "Apps needing separate databases -> Explicit environments with different
#    db_path"
# That is us: this app must not share an internal state database with any other
# CocoIndex app. So we build an explicit coco.Environment and bind it via
# AppConfig(environment=...), rather than mutating the global COCOINDEX_DB.
#
# GOTCHA: @coco.lifespan registers against the DEFAULT environment, so an app
# on an explicit environment receives NO context provider from it and every
# context key fails with KeyError('docstore') (verified live). Context for an
# explicit environment is supplied through that environment's own
# `context_provider` -- see configure_environment() below.
STATE_DB_PATH = pathlib.Path(
    os.environ.get(
        "DOCSTORE_COCOINDEX_DB", str(REPO_ROOT / ".docstore/cocoindex_state.db")
    )
)

# --- tunables --------------------------------------------------------------
# Documented concurrency control: AppConfig > COCOINDEX_MAX_INFLIGHT_COMPONENTS
# > default 1024. The default is what let 489 documents run at once.
MAX_INFLIGHT = int(os.environ.get("COCOINDEX_MAX_INFLIGHT_COMPONENTS", "4"))
MAX_RSS_MB = int(os.environ.get("DOCSTORE_MAX_RSS_MB", "2048"))

NVIDIA_API_BASE = os.environ.get("NVIDIA_API_BASE", "https://integrate.api.nvidia.com/v1")
EMBED_MODEL = os.environ.get("EMBED_MODEL", "nvidia/nemotron-3-embed-1b")
EMBED_DIM = int(os.environ.get("EMBED_DIM", "2048"))

CHUNK_SIZE = int(os.environ.get("DOCSTORE_CHUNK_SIZE", "1200"))
CHUNK_OVERLAP = int(os.environ.get("DOCSTORE_CHUNK_OVERLAP", "150"))
CHUNK_MIN_SIZE = int(os.environ.get("DOCSTORE_CHUNK_MIN_SIZE", "200"))

# Must match 010_documents.surql: confidence float ASSERT 0..1 DEFAULT 0.5
DEFAULT_CONFIDENCE = float(os.environ.get("DOCSTORE_CONFIDENCE", "0.5"))

MAPPING_CSV = pathlib.Path(
    os.environ.get(
        "DOCSTORE_MAPPING_CSV",
        str(REPO_ROOT / "scripts/docstore/mapping/docs-ingest-mapping.csv"),
    )
)

# Scoping goes into the SOURCE, via the connector's own PatternFilePathMatcher.
#
# GOTCHA (CDC): scoping by returning early inside the per-file component is NOT
# a filter. Under CocoIndex's change-data-capture, a component that declares no
# target state is declaring that the row should NOT EXIST -- an early return is a
# DELETE instruction, not a skip. Restricting `included_patterns` keeps
# out-of-scope files out of the source set instead. Patterns are relative to
# DOCS_DIR, so DOCSTORE_ONLY_FILES entries have their "docs/" prefix stripped.
_only = os.environ.get("DOCSTORE_ONLY_FILES", "").strip()
ONLY_PATTERNS: list[str] | None = (
    [
        pat.strip().replace("\\", "/").removeprefix("docs/")
        for pat in _only.split(",")
        if pat.strip()
    ]
    if _only
    else None
)

# The ruled value sets bound by the live schema.
VALID_DOC_TYPES = {"blueprint", "infrastructure", "decision", "todo", "handoff",
                   "review", "reference"}
VALID_DOMAINS = {"probata", "proffer", "consignatio", "advocatio", "vestigia",
                 "indagatio", "intake", "workbench", "knowledge", "memory",
                 "infra", "docs"}
VALID_STATUSES = {"active", "proposed", "unverified", "superseded", "retracted"}

_SLUG_RE = re.compile(r"[^a-z0-9]+")
_DATA_URI_RE = re.compile(r"data:image/[a-zA-Z0-9.+-]+;base64,[A-Za-z0-9+/=]+")
_NON_BMP_RE = re.compile(r"[𐀀-􏿿]")
_HEADING_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*$", re.M)

# The docs tree as a CONTEXT KEY, not a bare Path.
#
# GOTCHA: localfs.walk_dir(<absolute Path>) builds its root FilePath with
# base_dir=None, so every yielded `file.file_path.path` is ABSOLUTE -- and
# "docs/" + an absolute path matches no mapping row, so every file is silently
# skipped and the run reports success having written nothing. Passing a
# ContextKey[Path] instead gives FilePath(base_dir=KEY), which makes `.path`
# relative to the docs tree and keeps memo keys stable if the checkout moves.
DOCS_BASE: coco.ContextKey[pathlib.Path] = coco.ContextKey("docstore_docs_dir")

SURREAL_DB: coco.ContextKey[surrealdb.ConnectionFactory] = coco.ContextKey("docstore")
EMBEDDER: coco.ContextKey[LiteLLMEmbedder] = coco.ContextKey(
    "docstore_embedder", detect_change=True
)

_splitter = RecursiveSplitter()

# Lossless normalisation only: ASCII folding for search lives in the doc_text
# analyzer, never in the stored data.
_FTFY_CFG = ftfy.TextFixerConfig(
    unescape_html=False,
    uncurl_quotes=False,
    fix_latin_ligatures=False,
    fix_character_width=False,
    normalization="NFC",
)


# ---------------------------------------------------------------------------
# Row types — a SUBSET of the live columns. Omitted columns keep their schema
# DEFAULT; managed_by="user" means CocoIndex never redefines them.
# ---------------------------------------------------------------------------


# GOTCHA (typed arrays): the connector maps a bare `list[str]` through
# _OBJECT_MAPPING, whose encoder is json.dumps — so the column is declared
# `object` and the VALUE arrives as the STRING '["docs"]'. A SCHEMAFULL
# `array<string>` field rejects that ("Expected `array` but found
# '\"[\\\"docs\\\"]\"'"), which aborts the whole shared transaction and takes
# every document and chunk in the batch with it. The connector does not raise on
# per-statement errors, so the run still reports success with an empty store.
# `SurrealType("array<string>")` (encoder=None) passes the list through intact.
STR_ARRAY = SurrealType("array<string>")


@dataclass
class DocumentRow:
    """Every NON-OPTIONAL column must appear here, including ones carrying a
    schema DEFAULT.

    GOTCHA: the connector writes rows as `UPSERT ... CONTENT {...}`, and CONTENT
    is a FULL REPLACE. A field's DEFAULT fires only on CREATE, so re-writing an
    existing row drops any defaulted column that the row omits -- the write then
    fails with "Couldn't coerce value for field `confidence` ... Expected
    `float` but found `NONE`". That makes the pipeline write-once: fine on an
    empty store, fatal on every re-ingest (verified live 2026-09-09, 177 of 182
    documents failed this way after a partial run left rows behind).

    So `confidence` (float, DEFAULT 0.5) is supplied explicitly. `observed_at`
    was moved to `VALUE $value ?? time::now()` in 010_documents.surql instead,
    because the connector's json.dumps(default=str) renders a Python datetime as
    '2026-09-09 17:39:47+00:00' -- not valid SurrealQL datetime syntax, rejected
    with "Expected `datetime` but found '...'". `created`/`updated` already use
    VALUE, which recomputes on every write, so they stay absent too.
    """

    id: str
    source_path: str
    content_hash: str
    title: str
    body: str
    doc_type: str
    project: str
    tags: Annotated[list[str], STR_ARRAY]
    domains: Annotated[list[str], STR_ARRAY]
    status: str
    confidence: float


@dataclass
class ChunkRow:
    """One chunk. `source_path` is denormalised (Pattern 2 keeps `filename` on
    the row); the document link is the `chunk_of` relation.

    GOTCHA (`heading` is `str`, never `None`): SurrealDB distinguishes NULL from
    NONE, and `option<string>` accepts NONE but REJECTS NULL. The connector
    serialises a Python `None` as JSON `null`, so a null heading fails with
    "Couldn't coerce value for field `heading` ... Expected `none | string` but
    found `NULL`". Because the connector shares ONE TargetActionSink — and so
    one transaction — across every table handler for a database, that single bad
    row rolls back the whole batch: its documents and chunks vanish while
    relation-only batches commit, leaving orphan edges and an empty store. The
    connector does not raise on per-statement errors, so the run still reports
    success. Empty string means "no heading precedes this chunk".
    """

    id: str
    source_path: str
    ordinal: int
    heading: str
    text: str
    token_est: int
    doc_type: str
    project: str
    status: str
    domains: Annotated[list[str], STR_ARRAY]
    embedding: Annotated[NDArray, EMBEDDER]


# ---------------------------------------------------------------------------
# Mapping metadata (small: one row per file, no content)
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class DocMeta:
    source_path: str
    title: str
    doc_type: str
    domains: tuple[str, ...]
    status: str


def _load_mapping() -> tuple[dict[str, DocMeta], str]:
    """Metadata by source_path, plus a fingerprint of the whole CSV so a
    metadata-only edit invalidates the per-file memo."""
    raw = MAPPING_CSV.read_bytes()
    fingerprint = hashlib.sha256(raw).hexdigest()[:16]
    metas: dict[str, DocMeta] = {}
    for row in csv.DictReader(raw.decode("utf-8").splitlines()):
        sp = row["source_path"].replace("\\", "/")
        if not sp.lower().endswith(".md"):
            continue
        doc_type = row["doc_type"].strip()
        status = row["status"].strip()
        domains = tuple(d.strip() for d in row["domains"].split("|") if d.strip())
        if doc_type not in VALID_DOC_TYPES:
            raise ValueError(f"{sp}: doc_type {doc_type!r} is not in the ruled set")
        if status not in VALID_STATUSES:
            raise ValueError(f"{sp}: status {status!r} is not in the ruled set")
        unknown = set(domains) - VALID_DOMAINS
        if unknown:
            raise ValueError(f"{sp}: domains {sorted(unknown)} are not in the ruled set")
        metas[sp] = DocMeta(sp, row["title"].strip() or sp, doc_type, domains, status)
    return metas, fingerprint


_METAS, _MAPPING_FINGERPRINT = _load_mapping()


# Path rules for documents that have no mapping row (Claude Code - Opus 5 - 2026-09-10).
# First matching prefix wins; filename keywords decide for anything else.
_AUTO_RULES = (
    ("docs/adr/", "decision"),
    ("docs/handoffs/", "handoff"),
    ("docs/COMPACT-SUMMARY", "handoff"),
    ("docs/reviews/", "review"),
    ("docs/reference/", "reference"),
    ("docs/runbooks/", "reference"),
    ("docs/tools/", "reference"),
    ("docs/design/", "blueprint"),
    ("docs/blueprint/", "blueprint"),
    ("docs/plans/", "blueprint"),
)


def _auto_meta(source_path: str, body: str) -> DocMeta:
    name = source_path.rsplit("/", 1)[-1].upper()
    doc_type = next((t for prefix, t in _AUTO_RULES if source_path.startswith(prefix)), None)
    if doc_type is None:
        for keyword, kind in (("TODO", "todo"), ("DECISION", "decision"), ("HANDOFF", "handoff"),
                              ("INFRASTRUCTURE", "infrastructure")):
            if keyword in name:
                doc_type = kind
                break
        else:
            doc_type = "blueprint" if source_path.startswith("docs/planning/") else "reference"
    title = next((line[2:].strip() for line in body.splitlines() if line.startswith("# ")), "") or source_path
    return DocMeta(source_path, title[:300], doc_type, ("docs",), "unverified")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def slug(text: str) -> str:
    return _SLUG_RE.sub("_", text.lower()).strip("_")[:120]


def strip_data_uris(text: str) -> str:
    """NIM returns 503 'image inputs require VLM serving' for text holding a
    data: image URI."""
    return _DATA_URI_RE.sub("[data-uri-stripped]", text)


def fold_non_bmp(text: str) -> str:
    """Replace non-BMP characters with their Unicode name, e.g. "🟡" ->
    ":large_yellow_circle:".

    WHY (upstream defect, cocoindex 1.0.21): the SurrealDB connector writes rows
    as `UPSERT ... CONTENT {json.dumps(row)}` with json's default
    ensure_ascii=True, which renders a non-BMP character as a surrogate PAIR
    (a "u-d-8-3-d" / "u-d-f-e-1" pair, not the character). SurrealQL's
    string parser rejects those outright:
    `Parse error: String contains invalid escape sequence`. Probed live against
    3.2.0 on 2026-09-09: every BMP character passes (em dash, accented Latin,
    CJK, arrows, box-drawing) and ONLY non-BMP is rejected, so this fold is as
    narrow as the bug. `json.dumps(..., ensure_ascii=False)` fixes it upstream
    and is the one-line change to send them; see
    docs/reviews/2026-09-09-cocoindex-surrealdb-non-bmp-bug.md.

    The docstore is derived data and the source .md files are untouched, so when
    upstream lands the fix a plain re-ingest restores the characters.

    Applied ONCE to the raw body, before `content_hash` and before chunking, so
    the document body, its hash and every chunk derive from the same string. A
    checker must therefore hash the folded text, not the file bytes.
    """

    def _name(match: re.Match[str]) -> str:
        ch = match.group(0)
        try:
            return ":" + unicodedata.name(ch).lower().replace(" ", "_") + ":"
        except ValueError:
            return f":u{ord(ch):04x}:"

    return _NON_BMP_RE.sub(_name, text)


def normalize_for_search(text: str) -> str:
    return ftfy.fix_text(text, config=_FTFY_CFG)


def build_heading_index(body: str) -> list[tuple[int, str]]:
    return [(m.start(), m.group(2).strip()) for m in _HEADING_RE.finditer(body)]


def heading_for_offset(index: list[tuple[int, str]], offset: int) -> Optional[str]:
    found = None
    for start, text in index:
        if start <= offset:
            found = text
        else:
            break
    return found


def token_estimate(text: str) -> int:
    return len(text) // 4


# ---------------------------------------------------------------------------
# Memory guard — a workstation, not a server.
# ---------------------------------------------------------------------------


def _start_memory_guard(limit_mb: int) -> None:
    proc = psutil.Process()

    def watch() -> None:
        peak = 0
        while True:
            rss = proc.memory_info().rss // (1024 * 1024)
            peak = max(peak, rss)
            if rss > limit_mb:
                print(
                    f"\ndocstore: ABORTING — resident set {rss} MB crossed the "
                    f"{limit_mb} MB ceiling (peak {peak} MB). Raise "
                    f"DOCSTORE_MAX_RSS_MB only if the machine can take it.",
                    file=sys.stderr,
                    flush=True,
                )
                os._exit(2)
            time.sleep(1.0)

    threading.Thread(target=watch, daemon=True, name="rss-guard").start()


# ---------------------------------------------------------------------------
# Lifespan
# ---------------------------------------------------------------------------


def _load_env_file(path: pathlib.Path) -> None:
    if not path.is_file():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip())


class SharedEmbeddedConnectionFactory:
    """A ConnectionFactory-compatible provider that hands out ONE connection.

    WHY: the connector only ever calls `.acquire()` on whatever object we
    `builder.provide()`, and it calls it once per mounted target (document,
    chunk, chunk_of). The real ConnectionFactory opens a NEW connection each
    time, which is fine for ws:// but fatal embedded: surrealdb[embedded]
    3.0.0b8 allows exactly ONE open handle per datastore path, even inside a
    single process ("IO error: The process cannot access the file because
    another process has locked a portion of the file", os error 33 -- probed
    live 2026-09-09, 3 of 4 concurrent opens failed). Embedded needs no auth,
    so there is no signin to repeat per connection.
    """

    def __init__(self, url: str, *, namespace: str, database: str) -> None:
        self._url = url
        self._namespace = namespace
        self._database = database
        self._conn = None
        self._lock = asyncio.Lock()

    async def acquire(self):
        async with self._lock:
            if self._conn is None:
                from surrealdb import AsyncSurreal

                conn = AsyncSurreal(self._url)
                await conn.connect()
                await conn.use(self._namespace, self._database)
                self._conn = conn
            return self._conn


DOCSTORE_ENV = coco.Environment(
    coco.Settings.from_env(db_path=STATE_DB_PATH),
    name="probata-docstore",
)


def _server_credentials(ns: str) -> dict[str, str]:
    """Credentials for a REMOTE SurrealDB.

    A root user signs in with username/password. A namespace-scoped user
    (`DEFINE USER ... ON NAMESPACE`) must also send `namespace`, otherwise the
    server answers "There was a problem with authentication". Set
    SURREAL_SIGNIN_NS to sign in at namespace level; leave it unset for root.
    cocoindex's ConnectionFactory forwards this dict verbatim to conn.signin().
    """
    creds = {
        "username": os.environ["SURREAL_USER"],
        "password": os.environ["SURREAL_PASS"],
    }
    signin_ns = os.environ.get("SURREAL_SIGNIN_NS")
    if signin_ns:
        creds["namespace"] = signin_ns
    return creds


def configure_environment() -> coco.Environment:
    """Provide this app's context keys on its OWN environment.

    The @coco.lifespan body's equivalent, but targeting DOCSTORE_ENV rather than
    the default environment. Idempotent.
    """
    if getattr(configure_environment, "_done", False):
        return DOCSTORE_ENV

    _load_env_file(
        pathlib.Path(
            os.environ.get("DOCSTORE_ENV_FILE", str(REPO_ROOT / ".docstore/.env"))
        )
    )

    ns = os.environ.get("SURREAL_NS", "probata")
    db = os.environ.get("SURREAL_DB_NAME", os.environ.get("SURREAL_DB", "docs"))
    # SURREAL_BIND in .env is the single source of truth for host:port.
    bind = os.environ.get("SURREAL_BIND", "127.0.0.1:8462")
    url = os.environ.get("SURREAL_URL", f"ws://{bind}/rpc")
    # `{REPO_ROOT}` in an embedded URL expands to this checkout's root, so a
    # moved checkout does not leave .env pointing at a path that no longer
    # exists (it did on 2026-09-09: the store looked empty when it was fine).
    url = url.replace("{REPO_ROOT}", REPO_ROOT.as_posix())

    # EMBEDDED vs SERVER. An embedded URL (surrealkv:// / file:// / mem://) opens
    # the datastore IN-PROCESS -- no server, no port, nothing resident between
    # runs. Embedded has no auth, and signin() against it raises "There was a
    # problem with authentication", so credentials must be omitted entirely.
    embedded = url.split("://", 1)[0] in {"surrealkv", "surrealkv+versioned",
                                          "file", "mem", "memory"}

    provider = DOCSTORE_ENV.context_provider
    provider.provide(DOCS_BASE, DOCS_DIR)
    provider.provide(
        SURREAL_DB,
        SharedEmbeddedConnectionFactory(url, namespace=ns, database=db)
        if embedded
        else surrealdb.ConnectionFactory(
            url=url,
            namespace=ns,
            database=db,
            credentials=_server_credentials(ns),
        ),
    )
    provider.provide(
        EMBEDDER,
        LiteLLMEmbedder(
            f"openai/{EMBED_MODEL}",
            api_base=NVIDIA_API_BASE,
            api_key=os.environ["NVIDIA_API_KEY"],
        ),
    )
    configure_environment._done = True  # type: ignore[attr-defined]
    return DOCSTORE_ENV


configure_environment()

# Arm the memory guard at IMPORT, not just under __main__: the documented
# entry point is the CocoIndex CLI
# (`cocoindex update ...:ProbataDocStore@probata-docstore`), which imports this
# module and never runs __main__. Leaving the ceiling to __main__ is how a CLI
# run would go unguarded -- the condition behind the 17 GB runaway that took
# the workstation down on 2026-09-09. Daemon thread; set DOCSTORE_MAX_RSS_MB=0
# to disable.
if MAX_RSS_MB > 0:
    _start_memory_guard(MAX_RSS_MB)


# ---------------------------------------------------------------------------
# Leaf: one chunk -> one declared row (Pattern 2)
# ---------------------------------------------------------------------------


@coco.fn
async def process_chunk(
    chunk: Chunk,
    doc_id: str,
    meta: DocMeta,
    headings: list[tuple[int, str]],
    ordinals: dict[int, int],
    table: surrealdb.TableTarget[ChunkRow],
    edge: surrealdb.RelationTarget[None],
) -> None:
    offset = chunk.start.char_offset
    ordinal = ordinals[offset]
    chunk_id = slug(f"{doc_id}_c{ordinal}")
    table.declare_record(
        row=ChunkRow(
            id=chunk_id,
            source_path=meta.source_path,
            ordinal=ordinal,
            heading=heading_for_offset(headings, offset) or "",
            text=chunk.text,
            token_est=token_estimate(chunk.text),
            doc_type=meta.doc_type,
            project="probata",
            status=meta.status,
            domains=list(meta.domains),
            embedding=await coco.use_context(EMBEDDER).embed(chunk.text),
        )
    )

    # The chunk->document link. RelationTarget emits a real
    # `RELATE chunk:x->chunk_of->document:y` with raw record ids, so CDC owns
    # the edge exactly as it owns the row: declared here, reconciled and
    # deleted with the chunk. This is why there is no backfill pass.
    edge.declare_relation(from_id=chunk_id, to_id=doc_id)


# ---------------------------------------------------------------------------
# Per-file component (Patterns 1 and 2)
# ---------------------------------------------------------------------------


@coco.fn(memo=True, version=6)
async def process_file(
    file: FileLike,
    mapping_fingerprint: str,
    doc_table: surrealdb.TableTarget[DocumentRow],
    chunk_table: surrealdb.TableTarget[ChunkRow],
    chunk_edge: surrealdb.RelationTarget[None],
) -> None:
    """memo=True keys on the file resource (content_fingerprint) plus the
    mapping fingerprint, so a text edit or a metadata edit re-runs this file and
    nothing else does."""
    # file_path.path is relative to DOCS_BASE (see the ContextKey note above).
    source_path = "docs/" + file.file_path.path.as_posix()
    meta = _METAS.get(source_path)
    if meta is None and source_path.startswith("docs/private/"):
        # docs/private is gitignored on purpose; it is never indexed.
        return
    body = fold_non_bmp(await file.read_text(encoding="utf-8"))
    if meta is None:
        # No mapping row -- typically a document written after the CSV was
        # generated. Skipping made every new handoff and TODO invisible to recall
        # (10 real documents on 2026-09-10, incl. that day's handoffs), so classify
        # from the path and mark it `unverified` until a curated row replaces it.
        meta = _auto_meta(source_path, body)
        print(f"docstore: AUTO-MAPPED {source_path} -> {meta.doc_type}/unverified",
              file=sys.stderr, flush=True)
    doc_id = slug(source_path)

    doc_table.declare_record(
        row=DocumentRow(
            id=doc_id,
            source_path=source_path,
            content_hash=hashlib.sha256(body.encode("utf-8")).hexdigest(),
            title=meta.title,
            body=body,
            doc_type=meta.doc_type,
            project="probata",
            tags=[],
            domains=list(meta.domains),
            status=meta.status,
            confidence=DEFAULT_CONFIDENCE,
        )
    )

    clean = normalize_for_search(strip_data_uris(body))
    chunks = _splitter.split(
        clean,
        CHUNK_SIZE,
        min_chunk_size=CHUNK_MIN_SIZE,
        chunk_overlap=CHUNK_OVERLAP,
        language="markdown",
    )
    headings = build_heading_index(clean)
    ordinals = {c.start.char_offset: i for i, c in enumerate(chunks)}

    # map(): concurrent execution WITHIN this component, no child components,
    # one small row declared per chunk (Pattern 2).
    await coco.map(
        process_chunk, chunks, doc_id, meta, headings, ordinals, chunk_table, chunk_edge
    )


# ---------------------------------------------------------------------------
# App main (Pattern 1)
# ---------------------------------------------------------------------------


@coco.fn
async def app_main() -> None:
    doc_table = await surrealdb.mount_table_target(
        SURREAL_DB,
        "document",
        await surrealdb.TableSchema.from_class(DocumentRow),
        managed_by="user",
    )
    chunk_table = await surrealdb.mount_table_target(
        SURREAL_DB,
        "chunk",
        await surrealdb.TableSchema.from_class(ChunkRow),
        managed_by="user",
    )

    # from_table/to_table are POSITIONAL; table_schema is None because the edge
    # is field-free. managed_by="user" matches the tables above: 040_graph.surql
    # owns the DEFINE, CocoIndex owns only the records.
    chunk_edge = await surrealdb.mount_relation_target(
        SURREAL_DB,
        "chunk_of",
        chunk_table,
        doc_table,
        managed_by="user",
    )

    files = localfs.walk_dir(
        DOCS_BASE,
        recursive=True,
        path_matcher=PatternFilePathMatcher(
            included_patterns=ONLY_PATTERNS or ["**/*.md"],
            excluded_patterns=["private/**", "**/to_be_deleted/**"],
        ),
    )
    await coco.mount_each(
        process_file,
        files.items(),
        _MAPPING_FINGERPRINT,
        doc_table,
        chunk_table,
        chunk_edge,
    )


app = coco.App(
    coco.AppConfig(
        name="ProbataDocStore",
        environment=DOCSTORE_ENV,
        max_inflight_components=MAX_INFLIGHT,
    ),
    app_main,
)


if __name__ == "__main__":
    scope = f" (scoped to {len(ONLY_PATTERNS)} file(s))" if ONLY_PATTERNS else ""
    print(
        f"Running ProbataDocStore{scope} — max_inflight={MAX_INFLIGHT}, "
        f"RSS ceiling {MAX_RSS_MB} MB",
        flush=True,
    )
    app.update_blocking(report_to_stdout=True)
