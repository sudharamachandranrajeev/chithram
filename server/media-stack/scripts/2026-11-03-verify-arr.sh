#!/usr/bin/env bash
# Verify Prowlarr/Radarr/Sonarr/Lidarr. Exits non-zero on any failure. Prints no secrets.
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
APPS="prowlarr radarr sonarr lidarr"
fail=0
pass() { echo "PASS $*"; }
nope() { echo "FAIL $*"; fail=1; }
check() { local d="$1"; shift; if "$@"; then pass "$d"; else nope "$d"; fi; }
port_of() { case "$1" in prowlarr) echo "$PROWLARR_PORT" ;; radarr) echo "$RADARR_PORT" ;; sonarr) echo "$SONARR_PORT" ;; lidarr) echo "$LIDARR_PORT" ;; esac; }
ver_of() { case "$1" in prowlarr|lidarr) echo v1 ;; *) echo v3 ;; esac; }
umask 077
TMP="$(mktemp -d "$S/.verify-arr.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
for a in $APPS; do
  { printf 'header = "X-Api-Key: '; tr -d '\n' < "$S/${a}_api_key"; printf '"\n'; } > "$TMP/$a.cfg"
done
get()  { curl -fsS -K "$TMP/$1.cfg" "http://127.0.0.1:$(port_of "$1")/api/$(ver_of "$1")$2"; }
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

cd "$STACK"
echo "== 1 config and inspect"
docker compose --env-file "$ENV" config -q && pass "compose config valid" || nope "compose config"
if env -i PATH="$PATH" HOME="$HOME" docker compose --env-file /dev/null config -q >/dev/null 2>&1; then nope "compose does NOT fail closed"; else pass "compose fails closed with empty env"; fi
for a in $APPS; do
  insp="$(docker inspect "$a")"
  j() { printf '%s' "$insp" | jq -r "$1"; }
  check "$a image pinned: $(j '.[0].Config.Image' | sed -E 's|lscr.io/linuxserver/||; s|(@sha256:.{12}).*|\1...|')" grep -q '@sha256:' <<<"$(j '.[0].Config.Image')"
  check "$a ports only 127.0.0.1 ($(j '[.[0].NetworkSettings.Ports[][]?|.HostIp+":"+.HostPort]|join(",")'))" \
    [ "$(j '[.[0].NetworkSettings.Ports[][]?|.HostIp+":"+.HostPort]|join(",")')" = "127.0.0.1:$(port_of "$a")" ]
  echo "     $a caps: drop=$(j '.[0].HostConfig.CapDrop|join(",")') add=$(j '.[0].HostConfig.CapAdd|sort|join(",")') secopt=$(j '.[0].HostConfig.SecurityOpt|join(",")')"
  check "$a cap_drop ALL + no-new-privileges" [ "$(j '(.[0].HostConfig.CapDrop|join(","))+"|"+(.[0].HostConfig.SecurityOpt|join(","))')" = "ALL|no-new-privileges:true" ]
  check "$a pids_limit/mem_limit set ($(j '.[0].HostConfig.PidsLimit') / $(j '.[0].HostConfig.Memory'))" [ "$(j '(.[0].HostConfig.PidsLimit>0 and .[0].HostConfig.Memory>0)|tostring')" = true ]
  check "$a on media network" [ "$(j '.[0].NetworkSettings.Networks|keys|join(",")')" = "chithram-media_media" ]
  check "$a healthy" [ "$(j '.[0].State.Health.Status')" = healthy ]
  check "$a process runs as uid $PUID" [ "$(docker exec "$a" ps -eo uid=,comm= | awk -v n="${a^}" '$2==n{print $1; exit}')" = "$PUID" ]
done

echo "== 2 reachability and auth"
for a in $APPS; do
  p="$(port_of "$a")"
  check "$a /ping 200" [ "$(code "http://127.0.0.1:$p/ping")" = 200 ]
  check "$a unauthenticated /api/$(ver_of "$a")/system/status = 401" [ "$(code "http://127.0.0.1:$p/api/$(ver_of "$a")/system/status")" = 401 ]
  check "$a UI root redirects to login" grep -qi 'login' <<<"$(curl -s -o /dev/null -w '%{redirect_url}' "http://127.0.0.1:$p/")"
done
mapfile -t addrs < <(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 || true)
for ad in "${addrs[@]}"; do
  for a in $APPS; do
    if curl -fsS --max-time 3 "http://${ad}:$(port_of "$a")/ping" >/dev/null 2>&1; then nope "$a reachable on $ad"; else :; fi
  done
done
pass "no arr port reachable on ${#addrs[@]} non-loopback addresses"

echo "== 3 API state"
for a in $APPS; do check "$a system/status with key" [ "$(get "$a" /system/status | jq -r '.appName')" = "${a^}" ]; done
rf() { get "$1" /rootfolder | jq -r --arg p "$2" '[.[]|select(.path|rtrimstr("/")==$p)|.accessible]|first // false'; }
check "radarr root /data/media/movies accessible" [ "$(rf radarr /data/media/movies)" = true ]
check "sonarr root /data/media/tv accessible" [ "$(rf sonarr /data/media/tv)" = true ]
check "lidarr root /data/media/music accessible" [ "$(rf lidarr /data/media/music)" = true ]
jqc() { jq -e "$2" <<<"$(get "$1" "$3")" >/dev/null; } # app filter path
check "radarr naming" jqc radarr '.renameMovies==true and .standardMovieFormat=="{Movie Title} ({Release Year}) {Quality Full}" and .movieFolderFormat=="{Movie Title} ({Release Year})"' /config/naming
check "sonarr naming" jqc sonarr '.renameEpisodes==true and .standardEpisodeFormat=="{Series Title} - S{season:00}E{episode:00} - {Episode Title} {Quality Full}" and .seriesFolderFormat=="{Series Title} ({Series Year})" and .seasonFolderFormat=="Season {season:00}"' /config/naming
check "lidarr naming" jqc lidarr '.renameTracks==true and (.standardTrackFormat|startswith("{Album Title} ({Release Year})/")) and (.standardTrackFormat|endswith("{Artist Name} - {Album Title} - {track:00} - {Track Title}")) and .artistFolderFormat=="{Artist Name}"' /config/naming
for a in radarr sonarr lidarr; do
  check "$a copyUsingHardlinks true, no recycle bin, deleteEmptyFolders false" jqc "$a" '.copyUsingHardlinks==true and (.recycleBin//"")=="" and .deleteEmptyFolders==false and .skipFreeSpaceCheckWhenImporting==false' /config/mediamanagement
  check "$a CDH on; remove* (if present) false" jqc "$a" '.enableCompletedDownloadHandling==true and ((.removeCompletedDownloads//false)==false) and ((.removeFailedDownloads//false)==false)' /config/downloadclient
done
check "radarr autoUnmonitorPreviouslyDownloadedMovies false" jqc radarr '.autoUnmonitorPreviouslyDownloadedMovies==false' /config/mediamanagement
for a in $APPS; do
  check "$a zero download clients" [ "$(get "$a" /downloadclient | jq length)" = 0 ]
  check "$a zero indexers" [ "$(get "$a" /indexer | jq length)" = 0 ]
  check "$a UI user set (forms, enabled)" jqc "$a" '.authenticationMethod=="forms" and .authenticationRequired=="enabled" and .username=="chithram-admin"' /config/host
done
check "prowlarr 3 applications, fullSync" [ "$(get prowlarr /applications | jq -r '[.[]|select(.syncLevel=="fullSync")|.name]|sort|join(",")')" = "Lidarr,Radarr,Sonarr" ]
check "prowlarr health has no application errors" [ "$(get prowlarr /health | jq '[.[]|select(.source|test("Application"))]|length')" = 0 ]
for a in radarr sonarr lidarr; do
  check "$a Jellyfin notification (updateLibrary)" jqc "$a" '[.[]|select(.name=="Jellyfin")][0]|(.fields|map({(.name):.value})|add)|(.host=="jellyfin" and .port==8096 and .useSsl==false and .updateLibrary==true)' /notification
done

echo "== 4 hardlink inside radarr"
HA="/data/downloads/movies/.hltest-$$"; HB="/data/media/movies/.hltest-$$"
if docker exec radarr sh -c "[ -e '$HA' ] || [ -e '$HB' ]"; then
  echo "FAIL hardlink test paths already exist; refusing"; exit 1
fi
hl=""
if docker exec radarr sh -c ": > '$HA' && ln '$HA' '$HB'"; then
  hl="$(docker exec radarr stat -c '%i %h' "$HA" "$HB" | tr '
' '|')"
fi
docker exec radarr rm -f "$HA" "$HB" # only files this test created
echo "     inode/links: $hl"
check "same inode, link count 2" [ "$(printf '%s' "$hl" | awk -F'|' '{split($1,a," ");split($2,b," "); print (a[1]==b[1] && a[2]==2 && b[2]==2) ? "ok" : "bad"}')" = ok ]
check "hltest files removed" [ -z "$(find "$DATA_ROOT" -name ".hltest-$$")" ]

echo "== 5 Jellyfin connection test"
for a in radarr sonarr lidarr; do
  get "$a" /notification | jq -c --rawfile k "$S/jellyfin_api_key" \
    '[.[]|select(.name=="Jellyfin")][0]|.fields|=map(if .name=="apiKey" then .value=$k else . end)' > "$TMP/n.json"
  c="$(curl -s -o "$TMP/n.out" -w '%{http_code}' -K "$TMP/$a.cfg" -X POST -H 'Content-Type: application/json' --data @"$TMP/n.json" "http://127.0.0.1:$(port_of "$a")/api/$(ver_of "$a")/notification/test")"
  check "$a -> jellyfin notification test (HTTP $c)" [ "$c" = 200 ]
  rm -f "$TMP/n.json" "$TMP/n.out"
done

if [ "${RESTART_TEST:-0}" = 1 ]; then
  echo "== restart recovery"
  # shellcheck disable=SC2086  # APPS is a word list
  docker compose --env-file "$ENV" restart $APPS >/dev/null
  ok=0
  for _ in $(seq 1 36); do
    n=0; for a in $APPS; do [ "$(docker inspect -f '{{.State.Health.Status}}' "$a")" = healthy ] && n=$((n+1)); done
    [ "$n" = 4 ] && { ok=1; break; }; sleep 5
  done
  check "all 4 healthy after restart" [ "$ok" = 1 ]
  check "settings persist (3 roots, 3 apps, naming)" [ "$(get radarr /rootfolder | jq length)$(get sonarr /rootfolder | jq length)$(get lidarr /rootfolder | jq length)$(get prowlarr /applications | jq length)" = 1113 ] \
    && jqc radarr '.standardMovieFormat=="{Movie Title} ({Release Year}) {Quality Full}"' /config/naming
fi

echo "== 6 secret hygiene"
check "secrets dir mode 700" [ "$(stat -c %a "$S")" = 700 ]
check "secret files mode 600" [ -z "$(find "$S" -maxdepth 1 -type f ! -perm 600)" ]
for a in $APPS; do
  d="$CONFIG_ROOT/$a"
  check "$a config dir 700 owned $PUID:$PGID" [ "$(stat -c '%a %u:%g' "$d")" = "700 $PUID:$PGID" ]
  m="$(stat -c '%a %u:%g' "$d/config.xml")"
  case "$m" in "600 $PUID:$PGID"|"640 $PUID:$PGID") pass "$a config.xml mode/owner ($m)" ;; *) nope "$a config.xml mode/owner ($m)" ;; esac
done
leaks=0
for f in "$S"/arr_ui_password "$S"/prowlarr_api_key "$S"/radarr_api_key "$S"/sonarr_api_key "$S"/lidarr_api_key "$S"/jellyfin_api_key; do
  [ -s "$f" ] || { nope "secret file missing/empty: $(basename "$f")"; continue; }
  # patterns come from the file (-f), never from process arguments
  hits=$(
    { grep -rlF -f "$f" "$STACK" 2>/dev/null || true
      docker compose --env-file "$ENV" config 2>/dev/null | grep -F -f "$f" | head -1 || true
      for c in $(docker ps -aq); do
        docker inspect "$c" | grep -F -f "$f" | head -1 || true
        docker logs "$c" 2>&1 | grep -F -f "$f" | head -1 || true
      done
      grep -lF -f "$f" "$ENV" 2>/dev/null || true; } | wc -l)
  leaks=$((leaks + hits))
done
check "0 secret-value hits in work dir, compose config, inspect/logs of all containers, env file" [ "$leaks" = 0 ]

echo "== 7 jellyfin untouched"
check "jellyfin healthy" [ "$(docker inspect -f '{{.State.Health.Status}}' jellyfin)" = healthy ]
{ printf 'header = "Authorization: MediaBrowser Token=\\"'; tr -d '\n' < "$S/jellyfin_api_key"; printf '\\""\n'; } > "$TMP/jf.cfg"
check "jellyfin 3 libraries" [ "$(curl -fsS -K "$TMP/jf.cfg" "http://127.0.0.1:${JELLYFIN_PORT}/Library/VirtualFolders" | jq length)" = 3 ]

[ "$fail" = 0 ] && echo "VERIFY PASS" || { echo "VERIFY FAIL"; exit 1; }
