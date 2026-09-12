# =============================================================================
# tool-runtime — one container hosting Probata's executable tool capabilities
# =============================================================================
# Hosts, under supervisord:
#   - SBV (SMS Backup & Restore viewer/extractor) — binary LIFTED from the fork's
#     CI-built image ghcr.io/cursedpotential/sbv-forensic (GitHub Actions in the
#     Cursedpotential/sbv-forensic repo builds it; the local working checkout is
#     modules/forks/sbv, an independent repo gitignored by the platform since the
#     2026-09-01 restructure), carrying our H1/H2/H3 custody hooks. REST API + GUI :8085.
#   - tools-facade (FastAPI, :8090) — one HTTP/MCP surface over the ported
#     parsers/extractors (chat exports, messaging, location, pdf/unstructured)
# Media conversion deps (HEIC/3GP/AMR) come from ffmpeg + libheif.
#
# BUILD CONTEXT = the REPOSITORY ROOT.
#
# Corrected 2026-09-05. The previous note claimed the context was `deploy/`,
# because the compose spec resolves a relative `context:` against the compose
# file's directory. Coolify does NOT run compose that way: its deployment log
# shows `docker compose --project-directory <repo root> -f <repo root>/deploy/
# tool-runtime.yaml build`, so `context: .` is the repo root. The file was
# also internally inconsistent — it mixed `COPY docker/tools/...` (deploy/
# context) with `COPY server/...` (repo-root context), and no single context
# satisfied both. Every COPY below is now repo-root-relative, matching the
# working reference deploy/proffer-worker.yaml.
#   deploy/docker/tool-runtime/...   this dir's facade + supervisord
#   server/                   the platform server package
# =============================================================================

# -----------------------------------------------------------------------------
# SBV: lift the binary from the FORK'S CI-BUILT IMAGE (built by GitHub Actions
# in Cursedpotential/sbv-forensic, carrying our H1/H2/H3
# custody hooks). We do NOT build SBV from source here: the exec box is 4CPU/8GB
# and a Go/CGO/node build is too heavy for it; GH runners build it for free/fast.
# The fork image's final stage is alpine:3 (musl) with /app/sbv + /app/frontend/
# dist — same layout the old ghcr.io/lowcarbdev/sbv image had, so the final-stage
# COPYs below are unchanged.
# NOTE: this v0.2.x build has HEIC transcode DISABLED (pinned libheif-go no longer
# compiles vs current Alpine libheif — see restore-heic TODO in docs/COORDINATION.md).
# HEIC attachment bytes are still ingested + custody-hashed; only in-app HEIC
# display is off. The immutable multi-arch digest below is the successful
# swift-mvp universal import build (historical CI run name; that lane was renamed proffer, D-140) (GitHub Actions run 31959522422). To bump SBV,
# publish a new fork image and replace the digest only after its test/build gates pass.
# -----------------------------------------------------------------------------
FROM ghcr.io/cursedpotential/sbv-forensic@sha256:18a2a21cceb22433ad2ec9a458b0fd0f0788a1811b7635451b1b3159bb7c07fc AS sbv

# -----------------------------------------------------------------------------
# Final image: python facade + the SBV binary/assets lifted from the sbv stage.
# The SBV binary is musl-linked (Alpine), so we also carry the musl loader and
# Alpine's shared libs (libheif & friends); supervisord runs it with
# LD_LIBRARY_PATH=/opt/sbv-libs. (These three COPYs are unchanged from the
# ghcr-image version — only the SBV *source* changed, not this layout.)
# -----------------------------------------------------------------------------
FROM python:3.12-slim-bookworm@sha256:782412e85d0f0984994c290652577d4018aff08145c85b262bb63dc0c7522254
ARG POPPLER_UTILS_VERSION=22.12.0-2+deb12u3
RUN apt-get update && apt-get install -y --no-install-recommends \
        ffmpeg libheif1 nodejs npm supervisor curl \
        poppler-utils=${POPPLER_UTILS_VERSION} tesseract-ocr \
    && rm -rf /var/lib/apt/lists/*

COPY --from=sbv /app /opt/sbv
COPY --from=sbv /lib/ld-musl-x86_64.so.1 /lib/ld-musl-x86_64.so.1
COPY --from=sbv /usr/lib /opt/sbv-libs

# tools facade (parsers/extractors API) — registry-backed. The `server` package
# is BAKED IN at build (COPY server/ below), NOT bind-mounted: Coolify does not
# honor relative bind mounts, and the runtime app rebuilds this image from its
# scoped watch paths, so a self-contained image is strictly better than a runtime
# mount. facade.py imports `server.tools.registry` + `load_builtin_tools()`,
# which resolves from the baked /opt/tools/server tree.
# pydantic = NormalizedRecord schema dep for the parser tools. Repair and
# extraction dependencies are pinned to the repository lock/requirements
# versions rather than installing the whole application dependency graph. That
# keeps this capability image small and prevents an optional local model stack
# from arriving through an unrelated extra.
WORKDIR /opt/tools
COPY deploy/docker/tool-runtime/tools/ /opt/tools/
# The whole server tree: server.tools.registry pulls in server.contracts.records
# (the NormalizedRecord schema, ADR-0035) + server.tools/parsers/* +
# server.tools._sbv_client + server.vendored.chatminer transitively.
# All lightweight; heavy modules (api/workflows/core) are never imported by
# load_builtin_tools. Optional repair imports remain function-local, but every
# engine advertised by this production image must be present.
COPY server/ /opt/tools/server/
RUN pip install --no-cache-dir \
        fastapi uvicorn python-multipart pydantic \
        beautifulsoup4==4.15.0 \
        charset-normalizer==3.4.9 \
        clevercsv==0.8.5 \
        ijson==3.5.1 \
        json-repair==0.62.0 \
        lxml==6.1.1 \
        pdf2image==1.17.0 \
        pdfplumber==0.11.10 \
        pikepdf==10.11.0 \
        pillow==12.3.0 \
        pypdf==6.15.0 \
        pytesseract==0.3.13 \
    && python -c "from server.tools.repair.engines import manifest; expected={'xml','html','json','ndjson','csv','pdf','image'}; rows=manifest(); ready={row['format'] for row in rows if row['ready']}; missing=sorted(expected-ready); assert not missing, f'repair engines unavailable: {missing}; manifest={rows}'" \
    && python -c "import pikepdf; assert pikepdf.__version__" \
    && command -v tesseract >/dev/null \
    && command -v pdftoppm >/dev/null \
    && python -c "from server.tools.engine_profiles import inspect_poppler; result=inspect_poppler({'expected_profile_id':'poppler-linux-amd64','expected_package_version':'${POPPLER_UTILS_VERSION}'}); assert result['ready'], result"

COPY deploy/docker/tool-runtime/supervisord.conf /etc/supervisor/conf.d/tool-runtime.conf
EXPOSE 8085 8090
CMD ["supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]

# Byline amendment: Codex · GPT-5 · 2026-09-12 (`platform-tools` -> `tool-runtime`)
