#!/usr/bin/env bash
# Stop and remove containers/networks. Keeps config, cache, media, secrets. NO -v.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK="$(dirname "$HERE")"
ENV="${ENV_FILE:-/opt/chithram-media/media-stack.env}"
set -a
# shellcheck disable=SC1090
. "$ENV"
set +a

cd "$STACK"
docker compose --env-file "$ENV" down
echo "Stack removed. Kept:"
echo "  config  $CONFIG_ROOT"
echo "  media   $DATA_ROOT"
echo "  secrets $SECRETS_ROOT"
echo "Redeploy with scripts/2026-11-03-deploy.sh"
