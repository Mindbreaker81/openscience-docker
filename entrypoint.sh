#!/bin/sh
set -e

# OpenScience binds to 127.0.0.1 only (hardcoded upstream, no remote mode).
# proxy.js re-exposes it on 0.0.0.0:3000 with the Host header rewritten to
# 127.0.0.1, so requests arriving through Docker / tailscale serve / a
# reverse proxy pass the upstream Host guard. The Origin guard still applies:
# set OPENSCIENCE_CORS_DOMAINS for non-localhost HTTPS origins (e.g. your
# tailnet's tailXXXX.ts.net).
INTERNAL_PORT="${OPENSCIENCE_INTERNAL_PORT:-4096}"

node /usr/local/lib/openscience-proxy/proxy.js &

# `serve` is the headless server (the default `web` command tries to open a
# browser). It serves the workspace UI rooted at the current directory.
exec openscience serve --port "${INTERNAL_PORT}" "$@"
