#!/usr/bin/env bash
# Verify the Jellyfin deployment. Exits non-zero on any failure. Prints no secrets.
# shellcheck disable=SC2015  # pass/nope helpers always return 0
# Set RESTART_TEST=1 to also run the restart-recovery check.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK="$(dirname "$HERE")"
ENV="${ENV_FILE:-/opt/chithram-media/media-stack.env}"
set -a
# shellcheck disable=SC1090
. "$ENV"
set +a
S="$SECRETS_ROOT"
BASE="http://127.0.0.1:${JELLYFIN_PORT}"
fail=0
pass() { echo "PASS $*"; }
nope() { echo "FAIL $*"; fail=1; }
check() { # desc, command...
  local d="$1"; shift
  if "$@"; then pass "$d"; else nope "$d"; fi
}
umask 077
TMP="$(mktemp -d "$S/.verify.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
apicfg() { { printf 'header = "Authorization: MediaBrowser Token=\\"'; tr -d '\n' < "$S/jellyfin_api_key"; printf '\\""\n'; } > "$TMP/auth.cfg"; }
api() { apicfg; curl -fsS -K "$TMP/auth.cfg" "$BASE$1"; }

cd "$STACK"
echo "== 1 config and inspect"
docker compose --env-file "$ENV" config -q && pass "compose config valid" || nope "compose config"
insp="$(docker inspect jellyfin)"
j() { printf '%s' "$insp" | jq -r "$1"; }
check "image pinned by digest ($(j '.[0].Config.Image' | cut -c1-60)...)" grep -q '@sha256:' <<<"$(j '.[0].Config.Image')"
check "image spec has @sha256" grep -q '@sha256:' <<<"$(grep -E '^\s*image:' compose.yaml)"
check "port bound only 127.0.0.1:${JELLYFIN_PORT} ($(j '[.[0].NetworkSettings.Ports[][]?|.HostIp+":"+.HostPort]|join(",")'))" \
  [ "$(j '[.[0].NetworkSettings.Ports[][]?|.HostIp+":"+.HostPort]|join(",")')" = "127.0.0.1:${JELLYFIN_PORT}" ]
check "/data/media mounted ro" [ "$(j '.[0].Mounts[]|select(.Destination=="/data/media")|.RW')" = "false" ]
check "user $(j '.[0].Config.User')" [ "$(j '.[0].Config.User')" = "1000:1000" ]
check "cap_drop ALL, no-new-privileges, read-only rootfs" \
  [ "$(j '(.[0].HostConfig.CapDrop|join(","))+"|"+(.[0].HostConfig.SecurityOpt|join(","))+"|"+(.[0].HostConfig.ReadonlyRootfs|tostring)')" = "ALL|no-new-privileges:true|true" ]

echo "== 2 reachability"
check "/health on 127.0.0.1 = Healthy" [ "$(curl -fsS "$BASE/health")" = "Healthy" ]
mapfile -t addrs < <(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 || true)
if [ "${#addrs[@]}" -eq 0 ]; then
  echo "     no global IPv4 addresses found; non-loopback test skipped"
fi
for a in "${addrs[@]}"; do
  if curl -fsS --max-time 5 "http://${a}:${JELLYFIN_PORT}/health" >/dev/null 2>&1; then nope "reachable on ${a}"; else pass "NOT reachable on ${a}:${JELLYFIN_PORT}"; fi
done

echo "== 3 read-only"
if out="$(docker exec jellyfin sh -c 'touch /data/media/movies/x' 2>&1)"; then nope "write to /data/media succeeded"; else pass "write refused: $out"; fi

echo "== 4 libraries"
libs="$(api /Library/VirtualFolders)"
check "3 libraries (Movies, Music, TV)" [ "$(printf '%s' "$libs" | jq -r '[.[].Name]|sort|join(",")')" = "Movies,Music,TV" ]
for name in Movies TV Music; do
  id="$(printf '%s' "$libs" | jq -r --arg n "$name" '.[]|select(.Name==$n)|.ItemId')"
  n="$(api "/Items?ParentId=${id}&Recursive=true&IncludeItemTypes=Movie,Episode,Audio" | jq -r '.TotalRecordCount')"
  echo "     $name items: $n"
  if [ "$name" != "TV" ]; then check "$name has >=1 item" [ "$n" -ge 1 ]; fi
done
mv_json="$(api "/Items?Recursive=true&IncludeItemTypes=Movie&Fields=Overview" | jq -c '.Items[]|{Name,HasPrimary:(.ImageTags.Primary!=null),Overview:((.Overview//"")|length>0)}')"
echo "     movie metadata: $mv_json"

if [ "${RESTART_TEST:-0}" = 1 ]; then
  echo "== 5 restart recovery"
  docker compose --env-file "$ENV" restart jellyfin >/dev/null
  ok=0
  for _ in $(seq 1 36); do
    [ "$(docker inspect -f '{{.State.Health.Status}}' jellyfin)" = healthy ] && { ok=1; break; }
    sleep 5
  done
  check "healthy after restart" [ "$ok" = 1 ]
  check "libraries persist" [ "$(api /Library/VirtualFolders | jq 'length')" = 3 ]
  check "admin persists (api key valid)" [ "$(api /Users | jq -r '[.[].Name]|join(",")')" = "$(tr -d '\n' < "$S/jellyfin_admin_user")" ]
fi

echo "== 7 secret hygiene"
check "secrets dir mode 700" [ "$(stat -c %a "$S")" = 700 ]
check "secret files mode 600" [ -z "$(find "$S" -maxdepth 1 -type f ! -perm 600)" ]
leaks=0
for f in "$S"/jellyfin_admin_password "$S"/jellyfin_api_key; do
  # patterns come from the file (-f), never from process arguments
  hits=$(
    { grep -rlF -f "$f" "$STACK" 2>/dev/null || true
      docker compose --env-file "$ENV" config 2>/dev/null | grep -F -f "$f" | head -1 || true
      docker inspect jellyfin | grep -F -f "$f" | head -1 || true
      grep -lF -f "$f" "$ENV" 2>/dev/null || true; } | wc -l)
  leaks=$((leaks + hits))
done
check "0 secret-value hits in work dir, compose config, inspect, env file" [ "$leaks" = 0 ]

[ "$fail" = 0 ] && echo "VERIFY PASS" || { echo "VERIFY FAIL"; exit 1; }
