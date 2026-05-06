# hermes-railway

Minimal, auditable Railway template for self-hosting [Hermes Agent](https://github.com/NousResearch/hermes-agent) by Nous Research.

**No custom Python proxy, no extra UI.** Just the official Hermes Docker image with [Caddy](https://caddyserver.com) in front for HTTPS termination and HTTP basic_auth, deployed in one click on Railway.

## What this gives you

- Hermes Agent gateway (Telegram, Discord, Slack, WhatsApp, Email, Matrix, ...) running 24/7 on Railway.
- The native Hermes dashboard reachable from any browser at your Railway URL, protected by HTTP basic_auth (bcrypt).
- Persistent volume for sessions, memories, skills, and config.
- Bump Hermes version by changing one Railway variable — no code change.

## Architecture

```
Railway URL (HTTPS) → :$PORT → Caddy (basic_auth bcrypt)
                                  ├── /healthz  → 200 OK   (no auth, for Railway healthcheck)
                                  └── /*        → reverse_proxy 127.0.0.1:9119
                                                  (Hermes dashboard)
                                                                ↓
                                       hermes gateway run ← Telegram, Discord, ...
                                                                ↓
                                       Volume → /opt/data (.env, sessions, skills, ...)
```

The Hermes dashboard binds to `127.0.0.1` inside the container — it is never reachable from the public internet without going through Caddy's auth. The `--insecure` flag (which would bind to `0.0.0.0` and expose API keys on the network) is never used.

## Trust path

Total third-party code added on top of the official Hermes image:

| Component | Lines | What it does |
|---|---|---|
| `Caddyfile` | ~25 | Reverse proxy + basic_auth + healthcheck |
| `start.sh` | ~35 | Hash password, launch gateway + Caddy |
| `Dockerfile` | ~30 | Layer Caddy on top of `nousresearch/hermes-agent` |

That's it. No Python proxy, no custom UI to audit. The Hermes image itself is pinned to a specific tag (overridable via Railway env var).

## Deploy on Railway

### 1. Click deploy

1. Go to railway.com → **New Project** → **Deploy from GitHub repo** → select this repo (or your fork).
2. Railway detects the `Dockerfile` and starts building.

### 2. Set required variables

In **Settings → Variables**, add:

| Variable | Required | Value |
|---|---|---|
| `ADMIN_PASSWORD` | yes | Strong random password. Generate: `openssl rand -base64 32`. Mark as **sealed**. |
| `ADMIN_USERNAME` | no | Default `admin`. Override if you want. |
| `HERMES_VERSION` | no | Default pinned in `Dockerfile`. Set to bump (e.g. `v2026.5.7`). |

You can also pre-set Hermes provider/channel keys here (`OPENROUTER_API_KEY`, `TELEGRAM_BOT_TOKEN`, etc.) — or configure them later via the dashboard. See [`.env.example`](./.env.example) for the full list.

### 3. Attach a volume

**Settings → Volumes → New Volume**:

- Mount path: `/opt/data`
- Size: 1 GB minimum (Hermes stores sessions, memories, skills here)

### 4. Redeploy and login

Once the build is green and the healthcheck passes:

1. Open the public URL Railway gave you.
2. Browser prompts for basic_auth → user `admin`, password = your `ADMIN_PASSWORD`.
3. You land on the native Hermes dashboard. Configure your LLM provider, channels, and tools.

## Configure Hermes

Two ways to provide provider/channel credentials:

- **Via the dashboard** (easiest for first-time): click around, fill API keys in the appropriate sections, save.
- **Via Railway variables**: any var you set in Railway is exported into the container and read by Hermes from `/opt/data/.env` at gateway start. Useful for keys you want to manage as deploy config.

### Use OpenCode Zen as a provider

[OpenCode Zen](https://opencode.ai/zen) exposes an OpenAI-compatible endpoint. In the Hermes dashboard, add a custom OpenAI-compatible provider:

- Base URL: `https://opencode.ai/zen/v1`
- API key: your OpenCode Zen key
- Model ID format: `opencode/<model>` (e.g. `opencode/gpt-5.5`)

## Bump Hermes version

No code change required:

1. **Settings → Variables** → set `HERMES_VERSION=v2026.x.y`.
2. Save → Railway rebuilds and redeploys automatically.

Check the latest stable release:

```bash
gh release view --repo NousResearch/hermes-agent
# or visit https://github.com/NousResearch/hermes-agent/releases
```

Avoid `HERMES_VERSION=latest` in production — a breaking upstream change can break your deploy at the next rebuild.

## Security model

**What is protected:**

- Public URL is HTTPS-terminated by Railway → password never on the wire in clear.
- Hermes dashboard is `127.0.0.1`-only inside the container — only reachable via Caddy.
- `basic_auth` uses bcrypt; the hash is generated at container boot from `ADMIN_PASSWORD` and never written to disk or committed.
- `ADMIN_PASSWORD` lives only in Railway's sealed env vars.

**What is NOT protected (trust assumptions):**

- Anyone with `ADMIN_PASSWORD` has full agent access. Hermes can execute arbitrary shell commands via its `terminal` tool — this is by design (see [Hermes SECURITY.md](https://github.com/NousResearch/hermes-agent/blob/main/SECURITY.md)).
- Anyone with access to your Railway account can read all env vars, including `ADMIN_PASSWORD` and any provider API key. **Enable 2FA on your Railway account.**
- No rate-limiting on basic_auth (Caddy v2 has no built-in module). With a 32-char random password this is impractical to brute-force, but a weak password is game over.

**Recommended hardening:**

- `ADMIN_PASSWORD` ≥ 32 random chars (`openssl rand -base64 32`).
- 2FA on your Railway account.
- Periodically check Railway access logs for repeated `401 Unauthorized` (sign of brute-force attempt).

## Local development / test

If you have Docker installed:

```bash
docker build --build-arg HERMES_VERSION=v2026.4.30 -t hermes-railway-test .

docker run --rm -p 8080:8080 \
  -e PORT=8080 \
  -e ADMIN_PASSWORD=test1234 \
  -v hermes-test-vol:/opt/data \
  hermes-railway-test

# In another terminal:
curl http://localhost:8080/healthz                # → ok (200)
curl -i http://localhost:8080/                    # → 401 Unauthorized
curl -u admin:test1234 http://localhost:8080/     # → dashboard HTML (200)
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Layers Caddy on top of `nousresearch/hermes-agent`. |
| `Caddyfile` | Reverse proxy + basic_auth + healthcheck. |
| `start.sh` | Hashes the password, launches gateway and Caddy, propagates exit codes. |
| `railway.toml` | Railway build/deploy config. |
| `.env.example` | Documents all env vars. |

## License

MIT — see [LICENSE](./LICENSE).

Hermes Agent itself is MIT-licensed by Nous Research. This template only adds packaging and a reverse proxy.

## Credits

- [Nous Research](https://nousresearch.com) for [Hermes Agent](https://github.com/NousResearch/hermes-agent).
- [Caddy](https://caddyserver.com) for the reverse proxy.
