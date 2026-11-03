#!/usr/bin/env bash
# Preflight, bring the stack up, wait for healthy. Never uses `down -v`.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK="$(dirname "$HERE")"
ENV="${ENV_FILE:-/opt/chithram-media/media-stack.env}"
export ENV_FILE="$ENV"

"$HERE/2026-11-03-preflight.sh"

set -a
# shellcheck disable=SC1090
. "$ENV"
set +a
mkdir -p "$CONFIG_ROOT/jellyfin/config" "$CONFIG_ROOT/jellyfin/cache"
chmod 700 "$CONFIG_ROOT/jellyfin"
mkdir -p "$CONFIG_ROOT/seerr"; chmod 700 "$CONFIG_ROOT/seerr"
# arr config dirs (700) and API keys + config.xml are prepared BEFORE first start.
"$HERE/2026-11-03-arr-setup.sh" prepare

"$HERE/2026-11-03-gateway-setup.sh"

cd "$STACK"
# The gateway mounts key files that a first deploy creates only after these services are up
# (jellyfin/seerr keys), so it is started last.
SERVICES="jellyfin prowlarr radarr sonarr lidarr seerr"
# shellcheck disable=SC2086  # word splitting of the fixed service list is intended
docker compose --env-file "$ENV" up -d $SERVICES
echo "waiting for health (max 180s): $SERVICES"
for _ in $(seq 1 36); do
  pending=""
  for c in $SERVICES; do
    st="$(docker inspect -f '{{.State.Health.Status}}' "$c" 2>/dev/null || echo none)"
    [ "$st" = "healthy" ] || pending="$pending $c($st)"
  done
  if [ -z "$pending" ]; then
    echo "all healthy"
    "$HERE/2026-11-03-jellyfin-setup.sh"
    "$HERE/2026-11-03-arr-setup.sh" configure
    "$HERE/2026-11-03-seerr-setup.sh"
    docker compose --env-file "$ENV" build -q gateway >/dev/null
    docker compose --env-file "$ENV" up -d gateway
    for _ in $(seq 1 12); do
      [ "$(docker inspect -f '{{.State.Health.Status}}' gateway 2>/dev/null || echo none)" = healthy ] && { echo "gateway healthy"; exit 0; }
      sleep 5
    done
    echo "gateway not healthy" >&2
    docker compose --env-file "$ENV" logs --tail 30 gateway >&2 || true
    exit 1
  fi
  sleep 5
done
echo "not healthy:$pending" >&2
docker compose --env-file "$ENV" logs --tail 30 >&2 || true
exit 1
