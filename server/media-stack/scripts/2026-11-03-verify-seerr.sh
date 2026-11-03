#!/usr/bin/env bash
# Verify Seerr (Phase 6). Exits non-zero on any failure. Prints no secrets.
# shellcheck disable=SC2015  # pass/nope helpers always return 0
# RESTART_TEST=1 adds a restart + settings-persistence check.
# State-separation test creates (and removes) a temporary Jellyfin user, Seerr user,
# Seerr request and Radarr movie. It only deletes objects it created.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK="$(dirname "$HERE")"
ENV="${ENV_FILE:-/opt/chithram-media/media-stack.env}"
set -a
# shellcheck disable=SC1090
. "$ENV"
set +a
S="$SECRETS_ROOT"
BASE="http://127.0.0.1:${SEERR_PORT}"
fail=0
pass() { echo "PASS $*"; }
nope() { echo "FAIL $*"; fail=1; }
check() { local d="$1"; shift; if "$@"; then pass "$d"; else nope "$d"; fi; }
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
umask 077
if compgen -G "$S/.verify-seerr.*" >/dev/null; then
  echo "FAIL leftover temp dir from an interrupted run: $(compgen -G "$S/.verify-seerr.*" | tr '\n' ' ')" >&2
  echo "     Cleanup (manual): rm -rf the dir(s) above (they hold only throwaway tokens), then remove any" >&2
  echo "     seerr-test-* user in Jellyfin (Dashboard > Users) and Seerr (Users), any test request, and the" >&2
  echo "     Night of the Living Dead movie (TMDB 10331) in Radarr (delete WITHOUT files)." >&2
  exit 1
fi
TMP="$(mktemp -d "$S/.verify-seerr.XXXXXX")"

# ---- cleanup state (only objects this run created)
T_JF_ID=""; T_SEERR_ID=""; T_REQ_ID=""; T_MEDIA_ID=""; T_RADARR_ID=""; MOVIES_BEFORE=""
# remove only EMPTY movie folders that did not exist before the test (rmdir fails if not empty)
rmnew() {
  local d
  [ -n "$MOVIES_BEFORE" ] || return 0
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    printf '%s\n' "$MOVIES_BEFORE" | grep -qxF -- "$d" || rmdir "$DATA_ROOT/media/movies/$d" 2>/dev/null
  done < <(ls -A "$DATA_ROOT/media/movies")
}
cleanup() {
  set +e
  [ -n "$T_RADARR_ID" ] && curl -s -o /dev/null -K "$TMP/radarr.cfg" -X DELETE "http://127.0.0.1:${RADARR_PORT}/api/v3/movie/${T_RADARR_ID}?deleteFiles=false&addImportExclusion=false"
  [ -n "$T_REQ_ID" ] && curl -s -o /dev/null -K "$TMP/api.cfg" -K "$TMP/csrf.cfg" -X DELETE "$BASE/api/v1/request/${T_REQ_ID}"
  [ -n "$T_MEDIA_ID" ] && curl -s -o /dev/null -K "$TMP/api.cfg" -K "$TMP/csrf.cfg" -X DELETE "$BASE/api/v1/media/${T_MEDIA_ID}"
  [ -n "$T_SEERR_ID" ] && curl -s -o /dev/null -K "$TMP/api.cfg" -K "$TMP/csrf.cfg" -X DELETE "$BASE/api/v1/user/${T_SEERR_ID}"
  [ -n "$T_JF_ID" ] && curl -s -o /dev/null -K "$TMP/jf.cfg" -X DELETE "http://127.0.0.1:${JELLYFIN_PORT}/Users/${T_JF_ID}"
  rmnew
  rm -rf "$TMP"
}
trap cleanup EXIT

{ printf 'header = "X-Api-Key: '; tr -d '\n' < "$S/seerr_api_key"; printf '"\n'; } > "$TMP/api.cfg"
{ printf 'header = "X-Api-Key: '; tr -d '\n' < "$S/radarr_api_key"; printf '"\n'; } > "$TMP/radarr.cfg"
{ printf 'header = "X-Api-Key: '; tr -d '\n' < "$S/sonarr_api_key"; printf '"\n'; } > "$TMP/sonarr.cfg"
{ printf 'header = "Authorization: MediaBrowser Token=\\"'; tr -d '\n' < "$S/jellyfin_api_key"; printf '\\""\n'; } > "$TMP/jf.cfg"

# CSRF header/cookie for API-key calls (csrfProtection is on)
prime_csrf() {
  : > "$TMP/csrf.cfg"; rm -f "$TMP/jar"
  curl -fsS -c "$TMP/jar" -o /dev/null "$BASE/api/v1/status"
  local c x
  c="$(awk -F'\t' '{sub(/^#HttpOnly_/,"",$1)} $6=="_csrf"{print $7}' "$TMP/jar")"
  x="$(awk -F'\t' '{sub(/^#HttpOnly_/,"",$1)} $6=="XSRF-TOKEN"{print $7}' "$TMP/jar")"
  [ -n "$c" ] && printf 'header = "X-XSRF-TOKEN: %s"\nheader = "Cookie: _csrf=%s; XSRF-TOKEN=%s"\n' "$x" "$c" "$x" > "$TMP/csrf.cfg"
  return 0
}
prime_csrf
if [ "$(curl -fsS -K "$TMP/jf.cfg" "http://127.0.0.1:${JELLYFIN_PORT}/Users" | jq '[.[]|select(.Name|startswith("seerr-test-"))]|length')" != 0 ] \
  || [ "$(curl -fsS -K "$TMP/api.cfg" "$BASE/api/v1/user?take=100" | jq '[.results[]|select((.jellyfinUsername//"")|startswith("seerr-test-"))]|length')" != 0 ]; then
  echo "FAIL leftover seerr-test-* user(s) from an interrupted run in Jellyfin and/or Seerr." >&2
  echo "     Cleanup (manual): delete them in Jellyfin (Dashboard > Users) and Seerr (Users), then re-run." >&2
  exit 1
fi
sg() { curl -fsS -K "$TMP/api.cfg" "$BASE/api/v1$1"; }                               # GET
sp() { curl -fsS -K "$TMP/api.cfg" -K "$TMP/csrf.cfg" -X "$1" -H 'Content-Type: application/json' --data @- "$BASE/api/v1$2"; } # body on stdin
sn() { curl -fsS -K "$TMP/api.cfg" -K "$TMP/csrf.cfg" -X "$1" "$BASE/api/v1$2"; }    # no body
rg() { curl -fsS -K "$TMP/radarr.cfg" "http://127.0.0.1:${RADARR_PORT}/api/v3$1"; }
sgr() { curl -fsS -K "$TMP/sonarr.cfg" "http://127.0.0.1:${SONARR_PORT}/api/v3$1"; }

cd "$STACK"
echo "== 1 config and inspect"
check "compose config valid" docker compose --env-file "$ENV" config -q
if env -i PATH="$PATH" HOME="$HOME" docker compose --env-file /dev/null config -q >/dev/null 2>&1; then nope "compose does NOT fail closed"; else pass "compose fails closed with empty env"; fi
insp="$(docker inspect seerr)"
j() { printf '%s' "$insp" | jq -r "$1"; }
img="$(j '.[0].Config.Image')"
check "image pinned tag@digest ($(printf '%s' "$img" | sed -E 's|(@sha256:.{12}).*|\1...|'))" grep -Eq ':v[0-9.]+@sha256:[0-9a-f]{64}$' <<<"$img"
check "ports only 127.0.0.1 ($(j '[.[0].NetworkSettings.Ports[][]?|.HostIp+":"+.HostPort]|join(",")'))" [ "$(j '[.[0].NetworkSettings.Ports[][]?|.HostIp+":"+.HostPort]|join(",")')" = "127.0.0.1:${SEERR_PORT}" ]
echo "     caps: drop=$(j '.[0].HostConfig.CapDrop|join(",")') add=[$(j '(.[0].HostConfig.CapAdd//[])|join(",")')] secopt=$(j '.[0].HostConfig.SecurityOpt|join(",")') readonly=$(j '.[0].HostConfig.ReadonlyRootfs') user=$(j '.[0].Config.User')"
check "cap_drop ALL, no cap_add, no-new-privileges, read_only" [ "$(j '(.[0].HostConfig.CapDrop|join(","))+"|"+((.[0].HostConfig.CapAdd//[])|join(","))+"|"+(.[0].HostConfig.SecurityOpt|join(","))+"|"+(.[0].HostConfig.ReadonlyRootfs|tostring)')" = "ALL||no-new-privileges:true|true" ]
check "runs as $PUID:$PGID" [ "$(j '.[0].Config.User')" = "$PUID:$PGID" ]
check "pids_limit/mem_limit set ($(j '.[0].HostConfig.PidsLimit') / $(j '.[0].HostConfig.Memory'))" [ "$(j '(.[0].HostConfig.PidsLimit>0 and .[0].HostConfig.Memory>0)|tostring')" = true ]
check "only mount is config dir (no /data)" [ "$(j '[.[0].Mounts[]|.Destination]|join(",")')" = "/app/config" ]
check "on media network" [ "$(j '.[0].NetworkSettings.Networks|keys|join(",")')" = "chithram-media_media" ]
check "healthy" [ "$(j '.[0].State.Health.Status')" = healthy ]
check "no secrets in env (only TZ, LOG_LEVEL set by us)" [ "$(j '[.[0].Config.Env[]|select(test("KEY|PASS|SECRET|TOKEN"))]|length')" = 0 ]

echo "== 2 reachability and auth"
ps() { powershell.exe -NoProfile -Command "$1" 2>/dev/null | tr -d '\r'; }
wc_status="$(ps "(Invoke-WebRequest -UseBasicParsing http://127.0.0.1:${SEERR_PORT}/api/v1/status).StatusCode")"
check "Windows Invoke-WebRequest /api/v1/status = 200 (got ${wc_status:-n/a})" [ "$wc_status" = 200 ]
wc_req="$(ps "try { (Invoke-WebRequest -UseBasicParsing http://127.0.0.1:${SEERR_PORT}/api/v1/request).StatusCode } catch { \$_.Exception.Response.StatusCode.value__ }")"
check "Windows unauthenticated /api/v1/request = 401/403 (got ${wc_req:-n/a})" grep -Eq '^(401|403)$' <<<"$wc_req"
c="$(code "$BASE/api/v1/request")"
check "WSL unauthenticated /api/v1/request = 401/403 (got $c)" grep -Eq '^(401|403)$' <<<"$c"
c="$(code "$BASE/api/v1/settings/main")"
check "unauthenticated /settings/main = 401/403 (got $c)" grep -Eq '^(401|403)$' <<<"$c"
c="$(code -X POST -H 'Content-Type: application/json' -d '{}' "$BASE/api/v1/settings/main")"
check "unauthenticated POST /settings/main rejected (got $c)" grep -Eq '^(401|403)$' <<<"$c"
mapfile -t addrs < <(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 || true)
for ad in "${addrs[@]}"; do
  if curl -fsS --max-time 3 "http://${ad}:${SEERR_PORT}/api/v1/status" >/dev/null 2>&1; then nope "reachable on $ad"; fi
done
pass "not reachable on ${#addrs[@]} non-loopback addresses"

echo "== 3 API state"
check "status reports version" [ -n "$(curl -fsS "$BASE/api/v1/status" | jq -r '.version')" ]
pub="$(curl -fsS "$BASE/api/v1/settings/public")"
check "initialized=true, media server Jellyfin" [ "$(printf '%s' "$pub" | jq -r '(.initialized|tostring)+":"+(.mediaServerType|tostring)')" = "true:2" ]
jf="$(sg /settings/jellyfin)"
check "Jellyfin settings: jellyfin:8096, no SSL, server id set" [ "$(printf '%s' "$jf" | jq -r '[.ip,(.port|tostring),(.useSsl|tostring),((.serverId|length)>0|tostring)]|join(",")')" = "jellyfin,8096,false,true" ]
check "Jellyfin connection works (users listed via Seerr)" [ "$(sg /settings/jellyfin/users | jq -r --rawfile n "$S/jellyfin_admin_user" '[.[]|select(.username==$n)]|length')" = 1 ]
libs="$(sg /settings/jellyfin/library)"
echo "     libraries: $(printf '%s' "$libs" | jq -r 'map(.name+"("+.type+"):"+(.enabled|tostring))|join(" ")')"
check "Movies+TV libraries listed and enabled" [ "$(printf '%s' "$libs" | jq -r '[.[]|select(.enabled)|.type]|sort|join(",")')" = "movie,show" ]
rs="$(sg /settings/radarr)"; ss="$(sg /settings/sonarr)"
check "one Radarr server: radarr:7878, /data/media/movies, default, 4K off, sync off, search on" [ "$(printf '%s' "$rs" | jq -r 'length as $n|.[0]|[$n,.hostname,.port,.activeDirectory,.isDefault,.is4k,.syncEnabled,.preventSearch]|map(tostring)|join(",")')" = "1,radarr,7878,/data/media/movies,true,false,false,false" ]
check "one Sonarr server: sonarr:8989, /data/media/tv, default, season folders, 4K off, sync off" [ "$(printf '%s' "$ss" | jq -r 'length as $n|.[0]|[$n,.hostname,.port,.activeDirectory,.isDefault,.is4k,.syncEnabled,.preventSearch,.enableSeasonFolders]|map(tostring)|join(",")')" = "1,sonarr,8989,/data/media/tv,true,false,false,false,true" ]
for k in radarr sonarr; do
  port="$([ $k = radarr ] && echo 7878 || echo 8989)"
  c="$(jq -n --rawfile k "$S/${k}_api_key" --arg h "$k" --argjson p "$port" '{hostname:$h,port:$p,apiKey:$k,useSsl:false,baseUrl:""}' \
    | curl -s -o /dev/null -w '%{http_code}' -K "$TMP/api.cfg" -K "$TMP/csrf.cfg" -X POST -H 'Content-Type: application/json' --data @- "$BASE/api/v1/settings/$k/test")"
  check "$k test endpoint OK (HTTP $c)" [ "$c" = 200 ]
done
main="$(sg /settings/main)"
check "defaultPermissions == 32 (REQUEST only; no AUTO_APPROVE 128/256/512, no MANAGE_REQUESTS 16, no ADMIN 2)" [ "$(printf '%s' "$main" | jq -r '.defaultPermissions')" = 32 ]
check "applicationUrl empty, hideAvailable off, partial requests off, local login off, new Jellyfin sign-up off, version check off" [ "$(printf '%s' "$main" | jq -r '[.applicationUrl,(.hideAvailable|tostring),(.partialRequestsEnabled|tostring),(.localLogin|tostring),(.newPlexLogin|tostring),(.versionCheck|tostring)]|join(",")')" = ",false,false,false,false,false" ]
check "CSRF protection flag on" [ "$(sg /settings/network | jq -r '.csrfProtection')" = true ]
c="$(curl -s -o /dev/null -w '%{http_code}' -K "$TMP/api.cfg" -X POST "$BASE/api/v1/settings/initialize")"
check "CSRF ENFORCED: API-key POST without csrf cookie/header = 403 (got $c)" [ "$c" = 403 ]
check "owner (user 1) is the Jellyfin admin with ADMIN bit" [ "$(sg /user/1 | jq -r --rawfile n "$S/jellyfin_admin_user" '(.jellyfinUsername==$n and .permissions==2)|tostring')" = true ]

echo "== 4 state separation (temporary users and request)"
TMDB=10331 # Night of the Living Dead (1968), public domain
pre="$(sg "/movie/$TMDB" | jq -c '{id:(.mediaInfo.id // null),st:(.mediaInfo.status // 0)}')"
if [ "$(printf '%s' "$pre" | jq -r '.st')" -ge 4 ]; then echo "FAIL test film already available in the library; pick another"; exit 1; fi
PRE_MEDIA_ID="$(printf '%s' "$pre" | jq -r '.id // empty')" # Seerr media row that existed before the test: never deleted
if rg /movie | jq -e --argjson t "$TMDB" 'map(select(.tmdbId==$t))|length>0' >/dev/null; then
  echo "FAIL test movie already in Radarr; refusing to touch it"; exit 1
fi
if sg "/request?take=100&filter=all" | jq -e --argjson t "$TMDB" '.results|map(select(.media.tmdbId==$t))|length>0' >/dev/null; then
  echo "FAIL a request for the test movie already exists; refusing"; exit 1
fi
movies_snapshot="$(ls -A "$DATA_ROOT/media/movies")"
MOVIES_BEFORE="$movies_snapshot"
TU="seerr-test-$$"
openssl rand -base64 24 | tr -d '\n' > "$TMP/tu.pw"
jq -n --arg n "$TU" --rawfile p "$TMP/tu.pw" '{Name:$n,Password:$p}' \
  | curl -fsS -K "$TMP/jf.cfg" -X POST -H 'Content-Type: application/json' --data @- "http://127.0.0.1:${JELLYFIN_PORT}/Users/New" > "$TMP/jfu.json"
T_JF_ID="$(jq -er '.Id' "$TMP/jfu.json")"
pass "temporary Jellyfin user created"
imp="$(jq -n --arg i "$T_JF_ID" '{jellyfinUserIds:[$i]}' | sp POST /user/import-from-jellyfin)"
T_SEERR_ID="$(printf '%s' "$imp" | jq -er '.[0].id')"
check "import gave REQUEST-only permissions (32)" [ "$(printf '%s' "$imp" | jq -r '.[0].permissions')" = 32 ]
# sign in as the test user (session cookie + CSRF) and request as that user
UJ="$TMP/ujar"; rm -f "$UJ"
curl -fsS -c "$UJ" -b "$UJ" -o /dev/null "$BASE/api/v1/status"
uc() { # METHOD PATH [body on stdin]
  local m="$1" p="$2" x
  x="$(awk -F'\t' '$6=="XSRF-TOKEN"{print $7}' "$UJ" | tail -1)"
  printf 'header = "X-XSRF-TOKEN: %s"\n' "$x" > "$TMP/u.cfg"
  if [ -t 0 ] || [ "${UNOBODY:-}" = 1 ]; then
    curl -sS -c "$UJ" -b "$UJ" -K "$TMP/u.cfg" -X "$m" -w '\n%{http_code}' "$BASE/api/v1$p"
  else
    curl -sS -c "$UJ" -b "$UJ" -K "$TMP/u.cfg" -X "$m" -H 'Content-Type: application/json' --data @- -w '\n%{http_code}' "$BASE/api/v1$p"
  fi
}
login="$(jq -n --arg n "$TU" --rawfile p "$TMP/tu.pw" '{username:$n,password:$p}' | uc POST /auth/jellyfin)"
check "test user signs in via Jellyfin (HTTP $(printf '%s' "$login" | tail -1))" [ "$(printf '%s' "$login" | tail -1)" = 200 ]
rq="$(jq -n --argjson t "$TMDB" '{mediaType:"movie",mediaId:$t}' | uc POST /request)"
rqc="$(printf '%s' "$rq" | tail -1)"; rqb="$(printf '%s' "$rq" | sed '$d')"
check "request created by test user (HTTP $rqc)" [ "$rqc" = 201 ]
T_REQ_ID="$(printf '%s' "$rqb" | jq -er '.id')"
T_MEDIA_ID="$(printf '%s' "$rqb" | jq -r '.media.id // empty')"
[ -n "$PRE_MEDIA_ID" ] && T_MEDIA_ID="" # media row pre-existed; only the request is ours
check "request status PENDING (1), requested by test user" [ "$(printf '%s' "$rqb" | jq -r '[(.status|tostring),(.requestedBy.id|tostring)]|join(",")')" = "1,$T_SEERR_ID" ]
check "pending: NOT in Radarr" [ "$(rg /movie | jq --argjson t "$TMDB" 'map(select(.tmdbId==$t))|length')" = 0 ]
UNOBODY=1 uc GET "/request/$T_REQ_ID" >/dev/null
c="$(UNOBODY=1 uc POST "/request/$T_REQ_ID/approve" </dev/null | tail -1)"
check "test user cannot approve own request (HTTP $c)" grep -Eq '^(401|403)$' <<<"$c"
check "still PENDING after the denied approve" [ "$(sg "/request/$T_REQ_ID" | jq -r '.status')" = 1 ]
# admin approves (API key acts as the owner)
ap="$(sn POST "/request/$T_REQ_ID/approve")"
check "admin approve -> APPROVED (2)" [ "$(printf '%s' "$ap" | jq -r '.status')" = 2 ]
rid=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  rid="$(rg /movie | jq -r --argjson t "$TMDB" '[.[]|select(.tmdbId==$t)][0].id // empty')"
  [ -n "$rid" ] && break; sleep 2
done
[ -n "$rid" ] && T_RADARR_ID="$rid"
check "movie appears in Radarr" [ -n "$rid" ]
mv_json="$(rg "/movie/${rid:-0}" 2>/dev/null || echo '{}')"
check "Radarr movie monitored, no file" [ "$(printf '%s' "$mv_json" | jq -r '[(.monitored|tostring),(.hasFile|tostring)]|join(",")')" = "true,false" ]
check "no download clients, empty Radarr queue" [ "$(rg /downloadclient | jq length):$(rg /queue | jq -r '.totalRecords')" = "0:0" ]
check "no download clients, empty Sonarr queue" [ "$(sgr /downloadclient | jq length):$(sgr /queue | jq -r '.totalRecords')" = "0:0" ]
ms="$(sg "/movie/$TMDB" | jq -r '.mediaInfo.status')"
check "Seerr media status not available (status $ms; 5=available, 4=partial)" grep -Eq '^[123]$' <<<"$ms"
# ---- cleanup of exactly what the test created
[ -n "$T_RADARR_ID" ] && rg "/movie/$T_RADARR_ID" >/dev/null 2>&1 && curl -fsS -o /dev/null -K "$TMP/radarr.cfg" -X DELETE "http://127.0.0.1:${RADARR_PORT}/api/v3/movie/${T_RADARR_ID}?deleteFiles=false&addImportExclusion=false"
T_RADARR_ID=""
check "test movie removed from Radarr (files untouched)" [ "$(rg /movie | jq --argjson t "$TMDB" 'map(select(.tmdbId==$t))|length')" = 0 ]
sn DELETE "/request/$T_REQ_ID" >/dev/null; T_REQ_ID=""
[ -n "$T_MEDIA_ID" ] && sn DELETE "/media/$T_MEDIA_ID" >/dev/null; T_MEDIA_ID=""
check "test request removed from Seerr" [ "$(sg "/request?take=100&filter=all" | jq --argjson t "$TMDB" '.results|map(select(.media.tmdbId==$t))|length')" = 0 ]
sn DELETE "/user/$T_SEERR_ID" >/dev/null; T_SEERR_ID=""
check "test Seerr user removed" [ "$(sg "/user?take=100" | jq --arg n "$TU" '.results|map(select(.jellyfinUsername==$n))|length')" = 0 ]
curl -fsS -o /dev/null -K "$TMP/jf.cfg" -X DELETE "http://127.0.0.1:${JELLYFIN_PORT}/Users/${T_JF_ID}"; T_JF_ID=""
check "test Jellyfin user removed" [ "$(curl -fsS -K "$TMP/jf.cfg" "http://127.0.0.1:${JELLYFIN_PORT}/Users" | jq --arg n "$TU" 'map(select(.Name==$n))|length')" = 0 ]
rmnew; MOVIES_BEFORE=""
check "media/movies listing unchanged" [ "$(ls -A "$DATA_ROOT/media/movies")" = "$movies_snapshot" ]
rm -f "$TMP/tu.pw" "$TMP/jfu.json" "$UJ"

if [ "${RESTART_TEST:-0}" = 1 ]; then
  echo "== restart recovery"
  docker compose --env-file "$ENV" restart seerr >/dev/null
  ok=0
  for _ in $(seq 1 36); do
    [ "$(docker inspect -f '{{.State.Health.Status}}' seerr)" = healthy ] && { ok=1; break; }; sleep 5
  done
  check "healthy after restart" [ "$ok" = 1 ]
  prime_csrf
  check "settings persist (initialized, Jellyfin, 1 Radarr, 1 Sonarr, defaultPermissions 32, CSRF)" [ "$(curl -fsS "$BASE/api/v1/settings/public" | jq -r '.initialized')$(sg /settings/radarr | jq length)$(sg /settings/sonarr | jq length)$(sg /settings/main | jq -r .defaultPermissions)$(sg /settings/network | jq -r .csrfProtection)" = "true1132true" ]
fi

echo "== 5 secret hygiene"
check "secrets dir mode 700" [ "$(stat -c %a "$S")" = 700 ]
check "secret files mode 600" [ -z "$(find "$S" -maxdepth 1 -type f ! -perm 600)" ]
check "seerr_api_key present" [ -s "$S/seerr_api_key" ]
check "seerr config dir 700 owned $PUID:$PGID" [ "$(stat -c '%a %u:%g' "$CONFIG_ROOT/seerr")" = "700 $PUID:$PGID" ]
check "seerr settings.json mode 600" [ "$(stat -c %a "$CONFIG_ROOT/seerr/settings.json")" = 600 ]
leaks=0
for f in "$S"/*; do
  [ -f "$f" ] || continue
  case "$f" in *_user|*.old) continue ;; esac # user names are not secrets; .old = rotated keys (checked by rotate-key.sh)
  [ -s "$f" ] || { nope "secret file missing/empty: $(basename "$f")"; continue; }
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

echo "== 6 other services untouched"
for c in jellyfin prowlarr radarr sonarr lidarr; do check "$c healthy" [ "$(docker inspect -f '{{.State.Health.Status}}' "$c")" = healthy ]; done
check "jellyfin 3 libraries" [ "$(curl -fsS -K "$TMP/jf.cfg" "http://127.0.0.1:${JELLYFIN_PORT}/Library/VirtualFolders" | jq length)" = 3 ]
check "radarr/sonarr still 0 download clients, 0 indexers" [ "$(rg /downloadclient | jq length)$(rg /indexer | jq length)$(sgr /downloadclient | jq length)$(sgr /indexer | jq length)" = 0000 ]

[ "$fail" = 0 ] && echo "VERIFY PASS" || { echo "VERIFY FAIL"; exit 1; }
