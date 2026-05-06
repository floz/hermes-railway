#!/bin/bash
# Hermes Agent on Railway — orchestration script.
#
# Runs as the unprivileged `hermes` user (UID 10000) after the upstream
# entrypoint has bootstrapped the /opt/data volume and dropped privileges
# via gosu.
#
# Steps:
#   1. Validate required env vars.
#   2. Bcrypt-hash the admin password and export for Caddy.
#   3. Launch hermes dashboard on 127.0.0.1:9119 (background, loopback only).
#   4. Launch hermes gateway (Telegram/Discord/Slack/...) in background.
#   5. Launch Caddy reverse proxy in background.
#   6. wait -n: if any process exits, propagate code → container restart.
#
# We launch the dashboard ourselves rather than relying on the upstream
# entrypoint's HERMES_DASHBOARD=1 feature — that logic only exists on
# upstream main, not in pinned releases like v2026.4.30.

set -e

: "${ADMIN_PASSWORD:?must be set as a Railway env var}"
: "${PORT:?must be provided by Railway}"

export ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
export ADMIN_PASSWORD_HASH
ADMIN_PASSWORD_HASH=$(caddy hash-password --plaintext "$ADMIN_PASSWORD")

cleanup() {
	# On SIGTERM (Railway stop) or any process exit, kill remaining children
	# so the container shuts down cleanly instead of leaking processes.
	local pids
	pids=$(jobs -p)
	if [ -n "$pids" ]; then
		kill $pids 2>/dev/null || true
		wait 2>/dev/null || true
	fi
}
trap cleanup EXIT TERM INT

# Dashboard binds to loopback only — never reachable from internet without
# going through Caddy's basic_auth. No --insecure flag needed (which would
# only be required to bind to 0.0.0.0).
echo "[start] Launching hermes dashboard on 127.0.0.1:9119 (background)..."
hermes dashboard --host 127.0.0.1 --port 9119 --no-open 2>&1 | sed -u 's/^/[dashboard] /' &

echo "[start] Launching hermes gateway (background)..."
hermes gateway run 2>&1 | sed -u 's/^/[gateway] /' &

echo "[start] Launching Caddy reverse proxy on :${PORT} (background)..."
caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &

# Block until any child exits. Propagate its exit code so Railway can
# decide whether to restart based on restartPolicyType.
wait -n
exit $?
