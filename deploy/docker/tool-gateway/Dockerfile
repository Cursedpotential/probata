# tool-gateway — the locator-addressed front end for tool-runtime (D-132).
#
# Hermetic vendored build, same contract as the other engine services:
# modules/engine/vendor/ snapshots the full module graph (now including
# tailscale.com for the tsnet identity), so the build needs no network access
# and no sibling modules/forks/sbv checkout. Build context is the repo root
# (see deploy/tool-gateway.yaml `context: .`).
#
# Byline: Claude Code · Opus 5 · 2026-09-02.
# Toolchain pinned to match modules/engine/go.mod (`go 1.26.6`). A 1.25 builder
# fails the build outright with GOTOOLCHAIN=local; do not bump go.mod without
# bumping every Go Dockerfile in this directory in the same change.
FROM golang:1.26-bookworm AS builder

WORKDIR /src/engine
COPY modules/engine/ ./
RUN CGO_ENABLED=1 go build \
    -mod=vendor \
    -tags fts5 \
    -trimpath \
    -ldflags="-s -w" \
    -o /out/tool-gateway \
    ./cmd/tool-gateway

FROM debian:bookworm-slim

# /data/toolgw/materialize MUST be bind-mounted to the same absolute path in the
# tool-runtime container: the gateway hands that path to the tool, and the
# whole point of this service is that the path resolves on the other side.
# /data/toolgw/seal holds objects fetched from R2/B2 before materialization.
# /data/toolgw/tsnet holds the tsnet node state (its machine identity) and must
# be persistent, or the service re-registers as a new node on every deploy.
RUN apt-get update \
    && apt-get install --no-install-recommends -y ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 platform \
    && useradd --system --uid 10001 --gid platform --home-dir /nonexistent --shell /usr/sbin/nologin platform \
    && install -d -o platform -g platform -m 0750 \
       /data/toolgw/materialize \
       /data/toolgw/seal \
       /data/toolgw/tsnet

COPY --from=builder /out/tool-gateway /usr/local/bin/tool-gateway

USER 10001:10001
ENV TOOL_GATEWAY_MATERIALIZE_DIR=/data/toolgw/materialize \
    TOOL_GATEWAY_SEAL_DIR=/data/toolgw/seal \
    TOOL_GATEWAY_TS_STATE_DIR=/data/toolgw/tsnet \
    TOOL_GATEWAY_PORT=8099

ENTRYPOINT ["/usr/local/bin/tool-gateway"]
