#!/bin/bash
# Hermes Agent on Railway — orchestration script.
#
# Runs as the unprivileged `hermes` user (UID 10000) after the upstream
# entrypoint has bootstrapped the /opt/data volume and dropped privileges
# via gosu. The dashboard has already been launched in background on
# 127.0.0.1:9119 by the upstream entrypoint (HERMES_DASHBOARD=1).
#
# Steps:
#   1. Validate required env vars.
#   2. Bcrypt-hash the admin password and export for Caddy.
#   3. Launch hermes gateway (Telegram/Discord/Slack/...) in background.
#   4. Launch Caddy reverse proxy in background.
#   5. wait -n: if any process exits, propagate code → container restart.

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

echo "[start] Launching hermes gateway (background)..."
hermes gateway run &

echo "[start] Launching Caddy reverse proxy on :${PORT} (background)..."
caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &

# Block until any child exits. Propagate its exit code so Railway can
# decide whether to restart based on restartPolicyType.
wait -n
exit $?
