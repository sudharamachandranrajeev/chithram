#!/usr/bin/env bash
# Preflight checks for the media stack. Exits non-zero on any failure.
# shellcheck disable=SC2015  # ok/bad helpers always return 0
set -euo pipefail

ENV_FILE="${ENV_FILE:-/opt/chithram-media/media-stack.env}"
[ -r "$ENV_FILE" ] || { echo "FAIL env file missing: $ENV_FILE"; exit 1; }
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

MIN_FREE_GB="${MIN_FREE_GB:-20}"
fail=0
ok()  { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

command -v docker >/dev/null && ok "docker $(docker version --format '{{.Server.Version}}' 2>/dev/null)" || bad "docker missing"
docker compose version --short >/dev/null 2>&1 && ok "compose $(docker compose version --short)" || bad "docker compose missing"
for c in curl jq openssl; do command -v "$c" >/dev/null && ok "$c present" || bad "$c missing"; done

for d in downloads/movies downloads/tv downloads/music media/movies media/tv media/music; do
  p="$DATA_ROOT/$d"
  if [ -d "$p" ]; then
    own="$(stat -c '%u:%g' "$p")"; mode="$(stat -c '%a' "$p")"
    if [ "$own" = "$PUID:$PGID" ] && [ "$mode" = "2775" ]; then ok "$p $own $mode"; else bad "$p is $own $mode (want $PUID:$PGID 2775)"; fi
  else
    bad "$p missing"
  fi
done

fst="$(stat -f -c '%T' "$DATA_ROOT")"
case "$fst" in ext2/ext3|ext4) ok "$DATA_ROOT filesystem $fst" ;; *) bad "$DATA_ROOT filesystem $fst (want ext4)" ;; esac

a="$DATA_ROOT/downloads/.preflight-$$"; b="$DATA_ROOT/media/.preflight-$$"
if : > "$a" 2>/dev/null && ln "$a" "$b" 2>/dev/null && [ "$(stat -c %i "$a")" = "$(stat -c %i "$b")" ]; then
  ok "hardlink downloads -> media"
else
  bad "hardlink downloads -> media failed"
fi
rm -f "$a" "$b"

free_gb="$(df -BG --output=avail "$DATA_ROOT" | tail -1 | tr -dc '0-9')"
[ "$free_gb" -ge "$MIN_FREE_GB" ] && ok "free space ${free_gb}G" || bad "free space ${free_gb}G < ${MIN_FREE_GB}G"

[ -d "$CONFIG_ROOT" ] && [ -w "$CONFIG_ROOT" ] && ok "$CONFIG_ROOT writable" || bad "$CONFIG_ROOT not writable"
[ "$BIND_IP" = "127.0.0.1" ] && ok "BIND_IP 127.0.0.1" || bad "BIND_IP is $BIND_IP (must be 127.0.0.1)"

# Each port must be free, unless our own compose-managed container owns it.
check_port() { # container port-var inner-port
  local c="$1" port="${!2}" inner="$3" out published proj
  if out="$(ss -Hltn "sport = :$port")"; then
    if [ -z "$out" ]; then
      ok "port $port free on $BIND_IP ($c)"
    else
      published="$(docker port "$c" "$inner/tcp" 2>/dev/null | head -1 || true)"
      proj="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$c" 2>/dev/null || true)"
      if [ "$published" = "$BIND_IP:$port" ] && [ "$proj" = "chithram-media" ]; then
        ok "port $port held by our $c container"
      else
        bad "port $port ($c) in use by something else"
      fi
    fi
  else
    bad "ss failed"
  fi
}
check_port jellyfin JELLYFIN_PORT 8096
check_port prowlarr PROWLARR_PORT 9696
check_port radarr RADARR_PORT 7878
check_port sonarr SONARR_PORT 8989
check_port lidarr LIDARR_PORT 8686
check_port seerr SEERR_PORT 5055
command -v python3 >/dev/null && ok "python3 present" || bad "python3 missing"

[ "$fail" -eq 0 ] && echo "PREFLIGHT PASS" || { echo "PREFLIGHT FAIL"; exit 1; }
