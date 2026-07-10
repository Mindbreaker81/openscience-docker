# ─────────────────────────────────────────────
# Dockerfile for OpenScience (synthetic-sciences)
# Multi-arch: amd64 + arm64
#
# NOTE: OpenScience's server binds to 127.0.0.1 only (no remote mode
# upstream). proxy.js (started by entrypoint.sh) re-exposes it on
# 0.0.0.0:3000 with the Host header rewritten so upstream's Host guard
# accepts the request. See README for how to access it securely
# (Tailscale / SSH tunnel / reverse proxy).
# ─────────────────────────────────────────────

# ---------- Stage 1: Base ----------
FROM node:22-slim AS base

# System deps: curl is used by the healthcheck, the rest are common agent tools.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    ripgrep \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# ---------- Stage 2: Install OpenScience ----------
FROM base AS installer

# Install OpenScience CLI globally via npm
# (downloads the standalone platform binary as an optional dependency)
RUN npm install -g @synsci/openscience

# ---------- Stage 3: Runtime ----------
FROM base AS runtime

# Copy installed CLI (node wrapper + platform binary) from installer stage.
# Recreate the bin symlink instead of COPYing it: COPY dereferences symlinks,
# and the wrapper only finds the platform binary when it runs from inside
# node_modules.
COPY --from=installer /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/@synsci/openscience/bin/openscience /usr/local/bin/openscience

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY proxy.js /usr/local/lib/openscience-proxy/proxy.js
RUN chmod +x /usr/local/bin/entrypoint.sh

# Create workspace directory
WORKDIR /workspace

# Create a non-root user for running the agent
# (the agent has shell access, so don't run as root).
# Pre-create the XDG dirs so mounted volumes inherit their ownership:
#   ~/.config/openscience      → config (openscience.json)
#   ~/.local/share/openscience → auth.json (API keys), sessions, logs
RUN useradd -m -s /bin/bash researcher && \
    mkdir -p /home/researcher/.config/openscience \
             /home/researcher/.local/share/openscience && \
    chown -R researcher:researcher /workspace /home/researcher/.config /home/researcher/.local

USER researcher

# Port proxy.js listens on inside the container (publish this one).
# OpenScience itself listens on 127.0.0.1:4096 (its upstream default).
EXPOSE 3000

# Healthcheck — hit the OpenScience server directly on its internal port
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -sf http://127.0.0.1:4096/ || exit 1

# entrypoint.sh starts proxy.js, then execs `openscience serve --port 4096 <args>`
# (headless server, rooted at WORKDIR /workspace)
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["--print-logs"]
