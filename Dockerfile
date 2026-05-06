# syntax=docker/dockerfile:1.6

# Pin Hermes Agent version. Override via Railway env var (build-arg) without
# touching this file: Settings → Variables → HERMES_VERSION = v2026.x.y.
# Latest releases: https://github.com/NousResearch/hermes-agent/releases
ARG HERMES_VERSION=v2026.4.30

FROM nousresearch/hermes-agent:${HERMES_VERSION}

# Install Caddy from the official Cloudsmith repo. Caddy fronts the Hermes
# dashboard with HTTP basic_auth (bcrypt) and exposes /healthz for Railway's
# healthcheck. Bound to Railway's $PORT; reverse-proxies to the dashboard
# on loopback.
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        debian-keyring debian-archive-keyring apt-transport-https curl gnupg && \
    curl -fsSL 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
        | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg && \
    curl -fsSL 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
        | tee /etc/apt/sources.list.d/caddy-stable.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends caddy && \
    rm -rf /var/lib/apt/lists/*

COPY Caddyfile /etc/caddy/Caddyfile
COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

# Keep Caddy state ephemeral (out of /opt/data volume — would just pollute it).
ENV XDG_DATA_HOME=/tmp/caddy-data \
    XDG_CONFIG_HOME=/tmp/caddy-config

# Keep upstream ENTRYPOINT (tini + bootstrap script that drops privileges via
# gosu, sets up /opt/data, launches the dashboard). Override CMD only.
CMD ["/usr/local/bin/start.sh"]
