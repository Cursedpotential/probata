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
FROM kasmweb/ubuntu-noble-desktop:1.17.0

USER root
ENV DEBIAN_FRONTEND=noninteractive

# System tooling
RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl ca-certificates gnupg ripgrep fd-find jq tmux build-essential pkg-config \
        python3 python3-venv python3-pip unzip less openssh-client \
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
    && apt-get update && apt-get install -y --no-install-recommends xrdp xorgxrdp dbus-x11 syncthing \
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
# digests + indexes into the SAME Zilliz collection (config mirrored into ~/persist/.memsearch by the mirror script)
RUN UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin uv tool install --python 3.12 memsearch==0.4.19 \
    && chmod -R a+rX /opt/uv-tools

# Same tool set as sprisa/opencode-server (owner 17:24 "add the same programs as described"):
# apt for ruby/wget/vim/nano, mise (system config) for the lazy github/core-backed tools.
RUN apt-get update && apt-get install -y --no-install-recommends ruby-full wget vim nano \
    && apt-get clean && rm -r /var/lib/apt/lists \
    && curl -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh \
    && mkdir -p /etc/mise && printf 'eval "$(/usr/local/bin/mise activate bash)"\n' > /etc/profile.d/mise.sh
COPY deploy/docker/devbox/mise-config.toml /etc/mise/config.toml

# Agent CLIs (owner 16:22: claude + opencode)
RUN npm install -g @anthropic-ai/claude-code opencode-ai @sprisa/localhost && npm cache clean --force
# @sprisa/localhost = reserve HTTPS-on-tailnet proxy (owner 17:30: Tailscale certs are the direction; keep this as a tool)

# Passwordless sudo for the desktop user: needed for xrdp daemons at session start; the
# container is the security boundary of this sandbox.
RUN echo "kasm-user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/kasm-user && chmod 440 /etc/sudoers.d/kasm-user

# Kasm startup hook: starts xrdp + syncthing beside the desktop session
COPY deploy/docker/devbox/custom_startup.sh /dockerstartup/custom_startup.sh
RUN chmod +x /dockerstartup/custom_startup.sh

# Desktop launchers for the agent CLIs
RUN for a in claude opencode; do printf '[Desktop Entry]\nType=Application\nName=%s\nExec=xfce4-terminal -e %s\nTerminal=false\nCategories=Development;\n' "$a" "$a" > "/usr/share/applications/$a.desktop"; done

# mise/uv/npm write under ~/.local and ~/.config at first use — make sure the image's home is owned by
# the desktop user (Kasm ships parts of it root-owned; seen as "tracked-configs: Permission denied")
RUN mkdir -p /home/kasm-user/.local/state /home/kasm-user/.local/share /home/kasm-user/.config \
    && chown -R 1000:0 /home/kasm-user

USER 1000
ENV PATH=/home/kasm-user/.local/bin:$PATH
WORKDIR /home/kasm-user
