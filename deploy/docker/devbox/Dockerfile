# =============================================================================
# devbox — Kasm Workspaces desktop sandbox on the VPS where agents (Claude Code, OpenCode)
# run INSTEAD OF the owner's desktop. Owner orders 2026-09-07 16:18-16:24: "spin up a
# sandbox on the VPS … I'll move you there", "not agno" (-> ovh-files, not the Agno box),
# "custom environment", "just add kasm" (Ubuntu, not Arch), "install claude and opencode",
# "mirror our local skills out there", file link (Syncthing) + backup access (xrdp),
# "sync the ssh keys also".
#
# Byline: Claude Code · Fable 5.1 · 2026-09-07
#
# Base: Kasm's Ubuntu Noble desktop image (KasmVNC streamed to the browser on :6901, HTTPS,
# basic auth user `kasm_user` / VNC_PW). Layered: Node 22 (glibc), Python 3 + uv, git, gh,
# ripgrep, fd, jq, tmux, build-essential, DuckDB CLI, VS Code, Claude Code CLI, OpenCode,
# xrdp (backup access :3389), Syncthing (file link :8384/:22000). Kasm images run as uid
# 1000 `kasm-user`; /home/kasm-user is a persistent bind mount (deploy/devbox.yaml). No
# platform secrets in the image. Skills, plugins and ~/.ssh are mirrored into the persistent
# home by scripts/devbox_mirror_skills.sh, not baked in.
# BUILD CONTEXT = repository root (Coolify runs compose with --project-directory <root>).
# =============================================================================
# Base switched 2026-09-08 11:04 (owner: "kasmweb/claude-code, then add opencode on top"): Kasm's own Claude Code
# workspace image (Ubuntu desktop + Claude Code preinstalled). We layer OpenCode, the toolchain, xrdp, Syncthing, memsearch.
# Base switched AGAIN 2026-09-08 11:46 (owner: lean base — claude-code/ubuntu-desktop images ship LibreOffice,
# Chrome, Signal, Sublime, etc. we don't want). kasmweb/core-ubuntu-noble:1.17.0 = Kasm's core desktop
# image (XFCE + KasmVNC only, tag verified present on Docker Hub 2026-09-08). Claude Code no longer ships
# in the base — reinstated via npm below.
#
# Byline: Claude Code · Sonnet 5 · 2026-09-08 (devbox v2 — full toolchain per plan
# "rosy-wibbling-cosmos", owner-approved 12:10 EDT: Python/Node/Go/Rust dev stack, Docker CLI,
# surreal/ccc/tauri-cli, network+monitoring tools, documents/PDF/image apps, LibreOffice,
# Obsidian, pgAdmin, Surrealist, codex, ollama, terminals (kitty/ghostty), Homebrew via a
# second mapped volume, Playwright browsers. Correction of the "lean base, add exactly the
# tools we use" framing above: that governs the BASE IMAGE choice (Kasm core, not a bloated
# desktop image) — it does not mean a minimal toolchain; the toolchain list below IS "exactly
# the tools we use", just a long list of them.)
FROM kasmweb/core-ubuntu-noble:1.17.0

USER root
ENV DEBIAN_FRONTEND=noninteractive

# System tooling (xfce4-terminal explicit: core-ubuntu-noble is XFCE+KasmVNC only, don't assume a
# terminal emulator ships — our desktop launchers below invoke it directly)
RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl ca-certificates gnupg ripgrep fd-find jq tmux build-essential pkg-config \
        python3 python3-venv python3-pip unzip less openssh-client rclone fuse3 xfce4-terminal \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && apt-get clean && rm -r /var/lib/apt/lists

# Node 22 LTS (NodeSource, glibc build required by the Claude Code native binary)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs && apt-get clean && rm -r /var/lib/apt/lists

# gh CLI + VS Code (vendor apt repos)
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/packages.microsoft.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list \
    && apt-get update && apt-get install -y --no-install-recommends gh code && apt-get clean && rm -r /var/lib/apt/lists

# xrdp (backup access via Windows mstsc over the tailnet) + Syncthing (two-way file link)
RUN curl -fsSL https://syncthing.net/release-key.gpg | gpg --dearmor -o /usr/share/keyrings/syncthing-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable" > /etc/apt/sources.list.d/syncthing.list \
    && apt-get update && apt-get install -y --no-install-recommends xrdp xorgxrdp dbus-x11 syncthing synaptic \
    && apt-get clean && rm -r /var/lib/apt/lists \
    && adduser xrdp ssl-cert \
    && echo 'startxfce4' > /home/kasm-user/.xsession && chown 1000:1000 /home/kasm-user/.xsession

# DuckDB CLI (owner's preferred bulk-scan engine) — direct release zip into /usr/local/bin
# (the install.duckdb.org script ignores --install-dir and drops into $HOME, which is a runtime mount)
RUN curl -fsSL https://github.com/duckdb/duckdb/releases/latest/download/duckdb_cli-linux-amd64.zip -o /tmp/duckdb.zip \
    && unzip -o /tmp/duckdb.zip -d /usr/local/bin && chmod +x /usr/local/bin/duckdb && rm /tmp/duckdb.zip

# uv system-wide (uv-managed Python everywhere, never bare pip); installed as root because
# /home/kasm-user is not writable at build time and is overlaid at runtime anyway
RUN curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh

# memsearch (owner 2026-09-08 08:55 "both systems"): same version as the desktop, system-wide, so the devbox
# digests + indexes into the SAME Zilliz collection (config mirrored into ~/.memsearch by the mirror script —
# corrected 2026-09-08: whole-home design, no more ~/persist indirection)
RUN UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin uv tool install --python 3.12 memsearch==0.4.19 \
    && chmod -R a+rX /opt/uv-tools

# Same tool set as sprisa/opencode-server (owner 17:24 "add the same programs as described"):
# apt for ruby/wget/vim/nano, mise (system config) for the lazy github/core-backed tools.
RUN apt-get update && apt-get install -y --no-install-recommends ruby-full wget vim nano \
    && apt-get clean && rm -r /var/lib/apt/lists \
    && curl -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh \
    && mkdir -p /etc/mise && printf 'eval "$(/usr/local/bin/mise activate bash)"\n' > /etc/profile.d/mise.sh
COPY deploy/docker/devbox/mise-config.toml /etc/mise/config.toml

# Agent CLIs (owner 16:22: claude + opencode). Reinstated @anthropic-ai/claude-code 2026-09-08 11:46 —
# core-ubuntu-noble does NOT ship it (only kasmweb/claude-code did).
# Devbox v2 (2026-09-08): pnpm + bun package managers, and the rest of the "current environment"
# npm globals (owner 11:48-11:55): wrangler, codex, agent-browser, mcporter, defuddle,
# diff2html-cli, n8n-mcp, context-mode, command-code. `@opencode-ai/sdk` included per the
# execution brief's explicit npm -g list — a deviation from the plan's design-table note calling
# it a per-project dep; noted, not re-litigated (harmless as a global, still installable per-project too).
RUN npm install -g pnpm \
    && curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash \
    && npm install -g @anthropic-ai/claude-code opencode-ai @sprisa/localhost wrangler @openai/codex \
       @opencode-ai/sdk agent-browser mcporter defuddle diff2html-cli n8n-mcp context-mode command-code \
    && npm cache clean --force
# @sprisa/localhost = reserve HTTPS-on-tailnet proxy (owner 17:30: Tailscale certs are the direction; keep this as a tool)

# Go (latest stable tarball from go.dev's own JSON index — never hardcode a version)
RUN GOVER=$(curl -fsSL 'https://go.dev/dl/?mode=json' | jq -r '[.[] | select(.stable==true)][0].version') \
    && curl -fsSL "https://go.dev/dl/${GOVER}.linux-amd64.tar.gz" -o /tmp/go.tgz \
    && tar -C /usr/local -xzf /tmp/go.tgz && rm /tmp/go.tgz
ENV PATH=/usr/local/go/bin:$PATH

# Rust via rustup, system-wide install (not under a user home, which is a runtime mount), plus
# tauri-cli and its Linux GTK/WebKit deps (owner 11:51 "anything needed from the current environment")
ENV RUSTUP_HOME=/usr/local/rustup CARGO_HOME=/usr/local/cargo
ENV PATH=/usr/local/cargo/bin:$PATH
RUN apt-get update && apt-get install -y --no-install-recommends \
        libwebkit2gtk-4.1-dev libgtk-3-dev libayatana-appindicator3-dev librsvg2-dev patchelf \
    && apt-get clean && rm -r /var/lib/apt/lists \
    && curl -fsSL https://sh.rustup.rs -o /tmp/rustup.sh && sh /tmp/rustup.sh -y --profile minimal && rm /tmp/rustup.sh \
    && cargo install tauri-cli --locked \
    && chmod -R a+rX /usr/local/rustup /usr/local/cargo

# Docker CLI client only — no daemon/socket in this image (owner 11:48: containers are created
# through Coolify, not from inside the sandbox)
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin \
    && apt-get clean && rm -r /var/lib/apt/lists

# SurrealDB CLI (stable channel) — the install script drops the binary under root's $HOME at build time
RUN curl -sSf https://install.surrealdb.com | sh \
    && mv /root/.surrealdb/surreal /usr/local/bin/surreal && chmod +x /usr/local/bin/surreal

# CocoIndex Code (ccc) — same version as the desktop (private discovery tool; see AGENTS.md)
RUN UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin uv tool install --python 3.12 cocoindex-code==0.2.41 \
    && chmod -R a+rX /opt/uv-tools

# Network / TCP diagnostic tools (owner 11:52)
RUN apt-get update && apt-get install -y --no-install-recommends \
        iproute2 iputils-ping netcat-openbsd dnsutils traceroute mtr-tiny tcpdump nmap socat \
        net-tools whois openssl telnet \
    && apt-get clean && rm -r /var/lib/apt/lists

# Monitoring: btop (terminal) + glances with its web UI via uv (owner 11:52 "dashboard monitor")
RUN apt-get update && apt-get install -y --no-install-recommends btop \
    && apt-get clean && rm -r /var/lib/apt/lists \
    && UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin uv tool install --python 3.12 "glances[web]" \
    && chmod -R a+rX /opt/uv-tools

# Misc CLI utilities from the desktop-parity scan (owner 11:52, 11:55) — yq has no noble apt
# package, so pull the mikefarah static binary; everything else is apt
RUN apt-get update && apt-get install -y --no-install-recommends \
        git-lfs fzf bat htop ncdu tree zip rsync p7zip-full cmake libssl-dev libffi-dev sqlite3 \
        libsqlite3-dev postgresql-client redis-tools aria2 file xdg-utils \
    && apt-get clean && rm -r /var/lib/apt/lists \
    && curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq

# Python extras: pipx + ocrmypdf from apt; json-repair/exifread as uv tools (owner 11:55 scan);
# pymupdf+pypdf go in a SHARED VENV, not `uv pip install --system` — Noble's system python3 is
# externally-managed (PEP 668) and refuses bare installs even with uv.
RUN apt-get update && apt-get install -y --no-install-recommends pipx ocrmypdf \
    && apt-get clean && rm -r /var/lib/apt/lists \
    && UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin uv tool install --python 3.12 json-repair==0.61.2 \
    && UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin uv tool install --python 3.12 exifread==3.5.1 \
    && chmod -R a+rX /opt/uv-tools \
    && uv venv /opt/venv --python 3.12 \
    && uv pip install --python /opt/venv/bin/python pymupdf pypdf \
    && chmod -R a+rX /opt/venv
ENV PATH=/opt/venv/bin:$PATH

# Google Chrome (owner: Chrome/Chromium, not Firefox) — official .deb, root-safe launcher wrapper
RUN curl -fsSL https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -o /tmp/chrome.deb \
    && apt-get update && apt-get install -y --no-install-recommends /tmp/chrome.deb \
    && apt-get clean && rm -r /var/lib/apt/lists && rm /tmp/chrome.deb \
    && printf '#!/bin/sh\nexec /opt/google/chrome/chrome --no-sandbox --disable-dev-shm-usage "$@"\n' > /usr/local/bin/google-chrome \
    && chmod +x /usr/local/bin/google-chrome \
    && sed -i 's#^Exec=.*#Exec=/usr/local/bin/google-chrome %U#' /usr/share/applications/google-chrome.desktop || true

# LibreOffice (owner 12:09 "libreoffice is fine" — OpenOffice was the thing to avoid, not this)
RUN apt-get update && apt-get install -y --no-install-recommends \
        libreoffice-writer libreoffice-calc libreoffice-impress \
    && apt-get clean && rm -r /var/lib/apt/lists

# Documents / PDF stack (owner additions 11:54-12:02)
RUN apt-get update && apt-get install -y --no-install-recommends pandoc ghostwriter qpdf qpdfview poppler-utils \
    && apt-get clean && rm -r /var/lib/apt/lists

# EXIF / image stack (owner: exiv2, gimp, pinta replace PhotoScape — no snapd in Docker and the
# PhotoScape snap is a Wine wrapper anyway)
RUN apt-get update && apt-get install -y --no-install-recommends \
        imagemagick libimage-exiftool-perl exiv2 gimp pinta ffmpeg tesseract-ocr tesseract-ocr-eng \
    && apt-get clean && rm -r /var/lib/apt/lists

# Obsidian — latest GitHub release THAT HAS a .deb asset (the newest tag can lag its deb build)
RUN URL=$(curl -fsSL "https://api.github.com/repos/obsidianmd/obsidian-releases/releases?per_page=10" \
        | jq -r '[.[] | select(.assets[]?.name | test("amd64\\.deb$"))][0].assets[] | select(.name | test("amd64\\.deb$")) | .browser_download_url') \
    && curl -fsSL "$URL" -o /tmp/obsidian.deb \
    && apt-get update && apt-get install -y --no-install-recommends /tmp/obsidian.deb \
    && apt-get clean && rm -r /var/lib/apt/lists && rm /tmp/obsidian.deb \
    && sed -i 's#^Exec=obsidian#Exec=obsidian --no-sandbox#' /usr/share/applications/obsidian.desktop || true

# pgAdmin 4 desktop
RUN curl -fsSL https://www.pgadmin.org/static/packages_pgadmin_org.pub | gpg --dearmor -o /usr/share/keyrings/pgadmin.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/pgadmin.gpg] https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/noble pgadmin4 main" > /etc/apt/sources.list.d/pgadmin4.list \
    && apt-get update && apt-get install -y --no-install-recommends pgadmin4-desktop \
    && apt-get clean && rm -r /var/lib/apt/lists

# Surrealist — latest GitHub release .deb (owner 11:51 "anything needed from the current environment")
RUN URL=$(curl -fsSL "https://api.github.com/repos/surrealdb/surrealist/releases/latest" \
        | jq -r '.assets[] | select(.name | test("amd64\\.deb$")) | .browser_download_url') \
    && curl -fsSL "$URL" -o /tmp/surrealist.deb \
    && apt-get update && apt-get install -y --no-install-recommends /tmp/surrealist.deb \
    && apt-get clean && rm -r /var/lib/apt/lists && rm /tmp/surrealist.deb

# Terminals: kitty from apt, ghostty from the community Ubuntu .deb (noble = 24.04). ghostty uses
# OpenGL — under KasmVNC that's llvmpipe software rendering; kitty is the fallback if it won't start.
RUN apt-get update && apt-get install -y --no-install-recommends kitty \
    && apt-get clean && rm -r /var/lib/apt/lists \
    && URL=$(curl -fsSL "https://api.github.com/repos/mkasberg/ghostty-ubuntu/releases/latest" \
        | jq -r '.assets[] | select(.name | test("amd64_24\\.04\\.deb$")) | .browser_download_url') \
    && curl -fsSL "$URL" -o /tmp/ghostty.deb \
    && apt-get update && apt-get install -y --no-install-recommends /tmp/ghostty.deb \
    && apt-get clean && rm -r /var/lib/apt/lists && rm /tmp/ghostty.deb

# ollama (CPU-only box, no models baked — owner: official install script is enough; no systemd in
# a container so it warns on the service unit, the /usr/local/bin/ollama binary is all we need)
RUN curl -fsSL https://ollama.com/install.sh | sh || true

# Playwright browsers under /opt so they survive being a root-owned build layer, not a user mount
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
RUN PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright npx -y playwright@latest install --with-deps chromium firefox webkit \
    && chmod -R a+rX /opt/ms-playwright

# Passwordless sudo for the desktop user: needed for xrdp daemons at session start; the
# container is the security boundary of this sandbox. MUST precede the Homebrew install below,
# which runs as kasm-user via sudo.
RUN echo "kasm-user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/kasm-user && chmod 440 /etc/sudoers.d/kasm-user

# Homebrew (owner addition 11:54-12:02): refuses to run as root, so install it AS kasm-user into
# /home/linuxbrew/.linuxbrew — a SEPARATE mapped volume (deploy/devbox.yaml) so brew packages
# survive redeploys the same way /home/kasm-user does. /usr/local/bin/brew is a root-callable
# wrapper so `brew ...` works from any shell regardless of the invoking user.
RUN mkdir -p /home/linuxbrew && chown 1000:1000 /home/linuxbrew \
    && su - kasm-user -c 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' \
    && printf '#!/bin/sh\nexec sudo -u kasm-user -H /home/linuxbrew/.linuxbrew/bin/brew "$@"\n' > /usr/local/bin/brew \
    && chmod +x /usr/local/bin/brew

# Kasm startup hook: starts xrdp + syncthing beside the desktop session
COPY deploy/docker/devbox/custom_startup.sh /dockerstartup/custom_startup.sh
COPY deploy/docker/devbox/claude-rc.sh /usr/local/bin/claude-rc
RUN chmod +x /dockerstartup/custom_startup.sh /usr/local/bin/claude-rc

# Desktop launchers for the agent CLIs (codex added devbox v2, same pattern as claude/opencode)
RUN for a in claude opencode codex; do printf '[Desktop Entry]\nType=Application\nName=%s\nExec=xfce4-terminal -e %s\nTerminal=false\nCategories=Development;\n' "$a" "$a" > "/usr/share/applications/$a.desktop"; done

# Desktop launcher for Synaptic (owner addition 2026-09-08 11:46): container runs as root, so no
# pkexec/PolicyKit prompt is needed or wanted — launch it directly, not via `sudo synaptic`.
RUN printf '[Desktop Entry]\nType=Application\nName=Synaptic Package Manager\nExec=synaptic\nIcon=synaptic\nTerminal=false\nCategories=System;PackageManager;\n' > /usr/share/applications/synaptic.desktop

# mise/uv/npm write under ~/.local and ~/.config at first use — make sure the image's home is owned by
# the desktop user (Kasm ships parts of it root-owned; seen as "tracked-configs: Permission denied")
RUN mkdir -p /home/kasm-user/.local/state /home/kasm-user/.local/share /home/kasm-user/.config \
    && chown -R 1000:0 /home/kasm-user

USER 1000
ENV PATH=/home/kasm-user/.local/bin:$PATH
WORKDIR /home/kasm-user
