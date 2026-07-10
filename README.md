# OpenScience — Docker Setup

Run [OpenScience](https://github.com/synthetic-sciences/openscience) in a container
on a Linux server. The AI workbench for scientific research, isolated from your
host system.

## How networking works (read this first)

OpenScience's server **binds to `127.0.0.1` only** — upstream has no remote mode,
no `--host` flag, and no authentication. It also enforces a Host/Origin allowlist
(only `localhost` / `127.0.0.1`) as a DNS-rebinding defense.

This image works around both restrictions with a small forwarder inside the
container (`proxy.js`: `0.0.0.0:3000` → `127.0.0.1:4096`, rewriting the `Host`
header to the loopback value the guard expects). The Origin allowlist still
applies — extend it with `OPENSCIENCE_CORS_DOMAINS` when serving over HTTPS on
your own domain or tailnet.

Because the UI has **no login**, the compose file publishes the port on the
server's loopback only. Reach it via **Tailscale** (recommended) or an
**SSH tunnel** — never expose the raw port to a network.

## Quick start (Linux server + Tailscale) — recommended

On the server:

```bash
cp .env.example .env               # put your API key(s) in .env
# Add your tailnet DNS name (Admin console → DNS, e.g. tail1a2b3c.ts.net):
echo "OPENSCIENCE_CORS_DOMAINS=tail1a2b3c.ts.net" >> .env

docker compose up -d --build

# Publish to your tailnet over HTTPS (persists across reboots)
tailscale serve --bg 3000
```

From any device in your tailnet, open:

```
https://<server-name>.<tail1a2b3c>.ts.net
```

That's it — TLS certificates, access control, and connectivity from anywhere
are handled by Tailscale. To stop sharing: `tailscale serve --https=443 off`.

> Note: `tailscale funnel` would expose this to the **public internet** with no
> login — don't. Stick to `tailscale serve` (tailnet-only).

## Quick start (SSH tunnel, no Tailscale)

```bash
# On the server: build and run, publishing only to the server's loopback
docker build -t openscience .

docker run -d --name openscience \
  -p 127.0.0.1:3000:3000 \
  -e ANTHROPIC_API_KEY="sk-ant-..." \
  -v ~/openscience-workspace:/workspace \
  openscience

# On your machine: open a tunnel, then browse http://localhost:3000
ssh -L 3000:localhost:3000 user@your-server
```

> ⚠️ Do not use `-p 3000:3000` (all interfaces). The UI has **no login** — anyone
> who can reach the port gets an agent with shell access and your API keys.

## Docker Compose

```bash
cp .env.example .env   # put your key(s) in .env
docker compose up -d
```

The bundled `docker-compose.yml` already publishes to `127.0.0.1` only and
persists the workspace (`./workspace`) and config (named volume).

## API Keys

Pass any provider key via environment variables: `ANTHROPIC_API_KEY`,
`OPENAI_API_KEY`, `GEMINI_API_KEY`, `GOOGLE_API_KEY`, `OPENROUTER_API_KEY` —
or log in via Atlas (`docker exec -it openscience openscience login`).

## Volumes

| Mount | Purpose |
|-------|---------|
| `/workspace` | Your research projects, code, data |
| `/home/researcher/.config/openscience` | Config (`openscience.json`) |
| `/home/researcher/.local/share/openscience` | `auth.json` (API keys added via UI/CLI), sessions/chat history, logs |

Note: OpenScience uses XDG paths (`~/.config/...`, `~/.local/share/...`),
not `~/.openscience`.

## Optional: expose over HTTPS with your own reverse proxy

If you don't use Tailscale and an SSH tunnel is impractical, put an
authenticating reverse proxy on the server (nginx, Caddy, Authelia, …) in
front of the published port, and allow your domain's origin via
`OPENSCIENCE_CORS_DOMAINS` (comma-separated apex domains; only HTTPS
**subdomains** match, e.g. `openscience.example.com` for
`OPENSCIENCE_CORS_DOMAINS=example.com`). The `Host` header is already
rewritten inside the container, so the proxy config is plain:

```nginx
server {
    listen 443 ssl;
    server_name openscience.example.com;
    # ... ssl_certificate, auth_basic ...

    location / {
        proxy_pass http://127.0.0.1:3000;
        # SSE support
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_buffering off;
        proxy_read_timeout 1h;
    }
}
```

And in `.env`: `OPENSCIENCE_CORS_DOMAINS=example.com`.

## Platforms

| Platform | Status |
|----------|--------|
| Linux x64 | ✅ Native binary |
| Linux arm64 | ✅ Native binary (Oracle ARM, AWS Graviton, Raspberry Pi 5) |
| macOS x64 / arm64 | ✅ Via Docker Desktop |
| Windows | ✅ Via Docker Desktop or WSL2 |

## Why Docker?

OpenScience's agent is **not sandboxed** — it has shell, file, and network access.
Running in Docker isolates it from your host system. This is recommended by the
project's own security docs ("Run inside a container or VM if you need isolation").

## What's included

- OpenScience CLI (latest from npm — a standalone Bun-compiled binary)
- Node.js 22 (runs the npm bin wrapper and `proxy.js`; the app itself doesn't need Node)
- Git, ripgrep, Python 3 (for agent tools)
- `proxy.js` (loopback → container-interface forwarder with Host rewrite, see above)

## Customization

Pin a specific version:

```dockerfile
RUN npm install -g @synsci/openscience@1.3.2
```

Add more system packages (e.g., LaTeX for paper compilation):

```dockerfile
RUN apt-get update && apt-get install -y texlive-full
```

Change ports: the internal server port and the published listener are
`OPENSCIENCE_INTERNAL_PORT` (default 4096) and `OPENSCIENCE_LISTEN_PORT`
(default 3000), both read by `entrypoint.sh`.
 