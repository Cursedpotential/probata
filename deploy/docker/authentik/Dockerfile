# syntax=docker/dockerfile:1

# Keep the runtime and blueprint schema on the same pinned authentik release.
FROM ghcr.io/goauthentik/server:2026.8.0@sha256:7421753cfea67e89a6d295a1f0173ccea3866b33768c88dad90453b151cdcfd5

# File-based blueprints under /blueprints are discovered and reconciled by
# authentik. Baking the non-secret application definition into the image avoids
# Coolify's broken relative repo-file bind behavior.
COPY deploy/docker/authentik/blueprints/probata-workbench.yaml /blueprints/probata-workbench.yaml
