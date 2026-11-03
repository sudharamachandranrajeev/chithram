#!/usr/bin/env bash
# Rotate the API key of one *arr app: radarr | sonarr | lidarr | prowlarr.
#   rotate-key.sh <app>
# Keys never appear in argv, env or output. The old key is kept as <app>_api_key.old (600);
# the OWNER deletes it after confirming everything works. Safe to re-run after an interruption:
# an unused .new is reused, and a rotation that already reached config.xml resumes at the
# re-linking step. A leftover .old from a finished rotation makes the script refuse.
set -euo pipefail

APP="${1:-}"
case "$APP" in radarr|sonarr|lidarr|prowlarr) ;; *) echo "usage: $0 radarr|sonarr|lidarr|prowlarr" >&2; exit 2 ;; esac

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK="$(dirname "$HERE")"
ENV="${ENV_FILE:-/opt/chithram-media/media-stack.env}"
export ENV_FILE="$ENV"
set -a
# shellcheck disable=SC1090
. "$ENV"
set +a
S="$SECRETS_ROOT"
umask 077
CFG="$CONFIG_ROOT/$APP/config.xml"
KEY="$S/${APP}_api_key"; OLD="$KEY.old"; NEW="$KEY.new"

case "$APP" in
  prowlarr) PORT="$PROWLARR_PORT"; API=v1 ;; radarr) PORT="$RADARR_PORT"; API=v3 ;;
  sonarr) PORT="$SONARR_PORT"; API=v3 ;; lidarr) PORT="$LIDARR_PORT"; API=v1 ;;
esac

TMP="$(mktemp -d "$S/.rotate.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[ -s "$KEY" ] || { echo "no $APP key file" >&2; exit 1; }
[ -r "$CFG" ] || { echo "cannot read $CFG" >&2; exit 1; }

cfg_key_is() { # file : does config.xml ApiKey equal the content of file?
  python3 -I - "$CFG" "$1" <<'PY'
import sys, xml.etree.ElementTree as ET
cfg, kf = sys.argv[1:3]
cur = (ET.parse(cfg).getroot().findtext("ApiKey") or "").strip()
sys.exit(0 if cur and cur == open(kf).read().strip() else 1)
PY
}
set_cfg_key() { # file : write its content into config.xml ApiKey (atomic)
  python3 -I - "$CFG" "$1" <<'PY'
import os, sys, tempfile
import xml.etree.ElementTree as ET
cfg, kf = sys.argv[1:3]
key = open(kf).read().strip()
tree = ET.parse(cfg); root = tree.getroot()
e = root.find("ApiKey")
if e is None:
    e = ET.SubElement(root, "ApiKey")
e.text = key
ET.indent(tree, space="  ")
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(cfg), prefix=".config.xml.")
try:
    with os.fdopen(fd, "w") as f:
        f.write(ET.tostring(root, encoding="unicode"))
    os.chmod(tmp, 0o600)
    os.replace(tmp, cfg)
except BaseException:
    try:
        os.unlink(tmp)
    except FileNotFoundError:
        pass
    raise
PY
}
wait_healthy() {
  for _ in $(seq 1 36); do
    [ "$(docker inspect -f '{{.State.Health.Status}}' "$APP" 2>/dev/null || echo none)" = healthy ] && return 0
    sleep 5
  done
  return 1
}

cd "$STACK"
resume=0
if [ -e "$OLD" ]; then
  if ! cmp -s "$OLD" "$KEY" && cfg_key_is "$KEY"; then
    echo "$APP: previous rotation already reached config.xml; resuming at re-link"; resume=1
  else
    echo "$APP: $OLD exists from an earlier rotation. Delete it (owner) or investigate before rotating again." >&2
    exit 1
  fi
fi

if [ "$resume" = 0 ]; then
  # 1. old key kept, new key generated
  cp "$KEY" "$OLD"; chmod 600 "$OLD"
  if [ ! -s "$NEW" ]; then openssl rand -hex 16 | tr -d '\n' > "$NEW"; fi
  chmod 600 "$NEW"
  # 2. stop, write config.xml, swap secret, start
  docker compose --env-file "$ENV" stop "$APP" >/dev/null
  set_cfg_key "$NEW"
  mv "$NEW" "$KEY"
  docker compose --env-file "$ENV" start "$APP" >/dev/null
  echo "$APP: key written (not shown); waiting for healthy"
fi
wait_healthy || { echo "$APP not healthy after rotation" >&2; exit 1; }

# 3. re-link
"$HERE/2026-11-03-arr-setup.sh" configure
case "$APP" in radarr|sonarr) "$HERE/2026-11-03-seerr-setup.sh" ;; esac

# 4. checks
fail=0
mk() { { printf 'header = "X-Api-Key: '; tr -d '\n' < "$1"; printf '"\n'; } > "$2"; }
mk "$OLD" "$TMP/old.cfg"; mk "$KEY" "$TMP/new.cfg"
URL="http://127.0.0.1:$PORT/api/$API/system/status"
c_old="$(curl -s -o /dev/null -w '%{http_code}' -K "$TMP/old.cfg" "$URL")"
c_new="$(curl -s -o /dev/null -w '%{http_code}' -K "$TMP/new.cfg" "$URL")"
echo "old key -> HTTP $c_old (want 401); new key -> HTTP $c_new (want 200)"
[ "$c_old" = 401 ] && [ "$c_new" = 200 ] || fail=1
scan() { # paths (not values) where the old key still appears; our own temp dir and the .old file are excluded
  grep -rlF --exclude-dir='.rotate.*' -f "$OLD" /opt/chithram-media /home/media/work 2>/dev/null | grep -vxF "$OLD" || true
}
hits="$(scan)"
if printf '%s\n' "$hits" | grep -q '\.db$'; then
  # SQLite free pages / WAL can keep the old key: checkpoint + VACUUM each hit DB with its app stopped
  while IFS= read -r db; do
    case "$db" in /opt/chithram-media/config/*/*.db) ;; *) continue ;; esac
    owner="$(basename "$(dirname "$db")")"
    echo "old key remains in $db; VACUUM with $owner stopped"
    docker compose --env-file "$ENV" stop "$owner" >/dev/null
    python3 -I - "$db" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("PRAGMA wal_checkpoint(TRUNCATE)")
c.execute("VACUUM")
c.close()
PY
    docker compose --env-file "$ENV" start "$owner" >/dev/null
  done < <(printf '%s\n' "$hits" | grep '\.db$')
  for c in prowlarr radarr sonarr lidarr; do
    for _ in $(seq 1 36); do [ "$(docker inspect -f '{{.State.Health.Status}}' "$c")" = healthy ] && break; sleep 5; done
  done
  hits="$(scan)"
fi
if [ -n "$hits" ]; then
  echo "old key ALSO found in (paths only):"; printf '%s\n' "$hits" | sed 's/^/  /'
  fail=1
else
  echo "old key found only in $OLD"
fi
"$HERE/2026-11-03-verify-arr.sh" | tail -1 | sed 's/^/verify-arr: /' | tee "$TMP/va"
grep -q 'VERIFY PASS' "$TMP/va" || fail=1
"$HERE/2026-11-03-verify-seerr.sh" | tail -1 | sed 's/^/verify-seerr: /' | tee "$TMP/vs"
grep -q 'VERIFY PASS' "$TMP/vs" || fail=1

echo "The old key is kept in $OLD (mode 600). The owner deletes it after confirming."
if [ "$fail" = 0 ]; then echo "ROTATE OK"; else echo "ROTATE CHECKS FAILED"; exit 1; fi
