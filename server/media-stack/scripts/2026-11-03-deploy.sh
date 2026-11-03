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
# arr config dirs (700) and API keys + config.xml are prepared BEFORE first start.
"$HERE/2026-11-03-arr-setup.sh" prepare

cd "$STACK"
docker compose --env-file "$ENV" up -d

SERVICES="jellyfin prowlarr radarr sonarr lidarr"
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
    exit 0
  fi
  sleep 5
done
echo "not healthy:$pending" >&2
docker compose --env-file "$ENV" logs --tail 30 >&2 || true
exit 1
