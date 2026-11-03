#!/usr/bin/env bash
# Idempotent setup of Seerr via its API (no browser wizard). Called by deploy.sh after health.
#   - Jellyfin is the media server (admin sign-in creates the Seerr owner)
#   - Movies/TV libraries enabled and synced; Music library stays disabled (Seerr has no music support)
#   - Radarr + Sonarr connected; main/network settings; role defaults (REQUEST only, no auto-approve)
# Secrets are read from files; they never appear in args, env, logs or stdout.
set -euo pipefail

ENV="${ENV_FILE:-/opt/chithram-media/media-stack.env}"
set -a
# shellcheck disable=SC1090
. "$ENV"
set +a

S="$SECRETS_ROOT"
BASE="http://127.0.0.1:${SEERR_PORT}"
umask 077
mkdir -p "$S"
chmod 700 "$S"
TMP="$(mktemp -d "$S/.seerr.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# Permission bits (see README): REQUEST=32. No AUTO_APPROVE (128/256/512), no MANAGE_REQUESTS (16).
DEFAULT_PERMISSIONS=32
JF_HOST=jellyfin
JF_PORT=8096

curl -fsS "$BASE/api/v1/status" >/dev/null || { echo "seerr not reachable at $BASE" >&2; exit 1; }
[ -s "$S/jellyfin_admin_user" ] || { echo "jellyfin admin user missing; run jellyfin-setup first" >&2; exit 1; }
[ -s "$S/jellyfin_admin_password" ] || { echo "jellyfin admin secrets missing; run jellyfin-setup first" >&2; exit 1; }
for a in radarr sonarr; do [ -s "$S/${a}_api_key" ] || { echo "${a}_api_key missing; run arr-setup first" >&2; exit 1; }; done

# CSRF: when network.csrfProtection is on, every POST/PUT needs the _csrf cookie and the XSRF-TOKEN
# value as header. Prime a jar and build the header/cookie curl config (tokens live only in $TMP).
prime_csrf() {
  : > "$TMP/csrf.cfg"
  rm -f "$TMP/jar"
  curl -fsS -c "$TMP/jar" -o /dev/null "$BASE/api/v1/status"
  local c x
  c="$(awk -F'\t' '{sub(/^#HttpOnly_/,"",$1)} $6=="_csrf"{print $7}' "$TMP/jar")"
  x="$(awk -F'\t' '{sub(/^#HttpOnly_/,"",$1)} $6=="XSRF-TOKEN"{print $7}' "$TMP/jar")"
  if [ -n "$c" ] && [ -n "$x" ]; then
    printf 'header = "X-XSRF-TOKEN: %s"\nheader = "Cookie: _csrf=%s; XSRF-TOKEN=%s"\n' "$x" "$c" "$x" > "$TMP/csrf.cfg"
  fi
}
prime_csrf

# sx METHOD PATH  (JSON body on stdin); sxn METHOD PATH (no body). API key via -K file.
sx()  { curl -sS --fail-with-body -K "$TMP/api.cfg" -K "$TMP/csrf.cfg" -X "$1" -H 'Content-Type: application/json' --data @- "$BASE/api/v1$2"; }
sxn() { curl -sS --fail-with-body -K "$TMP/api.cfg" -K "$TMP/csrf.cfg" -X "$1" "$BASE/api/v1$2"; }

# ---------------------------------------------------------- media server + admin
pub="$(curl -fsS "$BASE/api/v1/settings/public")"
mst="$(printf '%s' "$pub" | jq -r '.mediaServerType')"
if [ "$mst" = 4 ]; then # NOT_CONFIGURED
  echo "signing in the Jellyfin admin to create the Seerr owner"
  jq -n --rawfile u "$S/jellyfin_admin_user" --rawfile p "$S/jellyfin_admin_password" \
    --arg h "$JF_HOST" --argjson port "$JF_PORT" \
    '{username:$u,password:$p,hostname:$h,port:$port,useSsl:false,urlBase:"",serverType:2}' \
    | curl -fsS -K "$TMP/csrf.cfg" -X POST -H 'Content-Type: application/json' --data @- -o /dev/null "$BASE/api/v1/auth/jellyfin" \
    || { echo "seerr: Jellyfin admin sign-in failed" >&2; exit 1; }
  echo "media server set to Jellyfin, owner created"
elif [ "$mst" = 2 ]; then
  echo "media server already Jellyfin"
else
  echo "seerr media server type is $mst (not Jellyfin); refusing" >&2; exit 1
fi

# ---------------------------------------------------------- API key (adopt, never regenerate)
CFGJSON="$CONFIG_ROOT/seerr/settings.json"
if [ ! -s "$S/seerr_api_key" ]; then
  [ -r "$CFGJSON" ] || { echo "seerr settings.json not readable and no seerr_api_key secret" >&2; exit 1; }
  jq -er '.main.apiKey | select(length>0)' "$CFGJSON" | tr -d '\n' > "$S/seerr_api_key"
  chmod 600 "$S/seerr_api_key"
  echo "seerr API key adopted from settings.json (stored, not shown)"
fi
{ printf 'header = "X-Api-Key: '; tr -d '\n' < "$S/seerr_api_key"; printf '"\n'; } > "$TMP/api.cfg"
sxn GET /settings/main | jq -e '.apiKey|length>0' >/dev/null || { echo "seerr API key rejected" >&2; exit 1; }
if [ -r "$CFGJSON" ] && ! jq -e --rawfile k "$S/seerr_api_key" '.main.apiKey==$k' "$CFGJSON" >/dev/null; then
  echo "seerr settings.json API key differs from secrets file; refusing to change it" >&2; exit 1
fi

# ---------------------------------------------------------- main settings
# applicationUrl empty; hideAvailable off; local (email/password) login off: sign-in is Jellyfin only,
# and the owner is a Jellyfin user; new Jellyfin users cannot self-register (newPlexLogin=false):
# they must be imported by an admin; partial requests off; version check (outbound call) off.
jq -n --argjson dp "$DEFAULT_PERMISSIONS" \
  '{applicationUrl:"",hideAvailable:false,localLogin:false,mediaServerLogin:true,newPlexLogin:false,
    partialRequestsEnabled:false,defaultPermissions:$dp,versionCheck:false,cacheImages:false}' \
  | sx POST /settings/main >/dev/null
echo "main settings applied (defaultPermissions=$DEFAULT_PERMISSIONS)"

# ---------------------------------------------------------- libraries
sxn POST /settings/jellyfin/library/sync | jq -c '[.[]|{name,type,enabled}]' >/dev/null
ids="$(sxn GET /settings/jellyfin/library)"
printf '%s' "$ids" | jq -r '.[]|[.id,.type,.name]|@tsv' | while IFS=$'\t' read -r id type name; do
  case "$type" in movie|show) want=true ;; *) want=false ;; esac
  jq -n --argjson e "$want" '{enabled:$e}' | sx PUT "/settings/jellyfin/library/$id" >/dev/null
  echo "library $name ($type): enabled=$want"
done
jq -n '{start:true}' | sx POST /settings/jellyfin/sync >/dev/null
echo "library scan triggered"

# ---------------------------------------------------------- Radarr / Sonarr
dvr() { # kind(radarr|sonarr) inner-port root-dir
  local kind="$1" port="$2" root="$3" name test pid pname body id
  name="${kind^}"
  test="$(jq -n --rawfile k "$S/${kind}_api_key" --arg h "$kind" --argjson p "$port" \
    '{hostname:$h,port:$p,apiKey:$k,useSsl:false,baseUrl:""}' | sx POST "/settings/$kind/test")" \
    || { echo "$kind: connection test failed" >&2; exit 1; }
  printf '%s' "$test" | jq -e --arg r "$root" '[.rootFolders[].path|rtrimstr("/")]|index($r)!=null' >/dev/null \
    || { echo "$kind: root folder $root not offered by $kind" >&2; exit 1; }
  # default quality profile: the one named "Any" if present, else the first
  pid="$(printf '%s' "$test" | jq -er '(([.profiles[]|select(.name=="Any")][0]) // .profiles[0]).id')"
  pname="$(printf '%s' "$test" | jq -er --argjson i "$pid" '.profiles[]|select(.id==$i)|.name')"
  body="$(jq -n --rawfile k "$S/${kind}_api_key" --arg n "$name" --arg h "$kind" --argjson p "$port" \
    --arg r "$root" --argjson pid "$pid" --arg pn "$pname" \
    '{name:$n,hostname:$h,port:$p,apiKey:$k,useSsl:false,baseUrl:"",externalUrl:"",
      activeProfileId:$pid,activeProfileName:$pn,activeDirectory:$r,tags:[],is4k:false,isDefault:true,
      syncEnabled:false,preventSearch:false,tagRequests:false,overrideRule:[]}')"
  if [ "$kind" = radarr ]; then
    body="$(printf '%s' "$body" | jq '.minimumAvailability="released"')"
  else
    body="$(printf '%s' "$body" | jq '.seriesType="standard"|.animeSeriesType="standard"|.enableSeasonFolders=true|.monitorNewItems="all"|.animeTags=[]')"
  fi
  id="$(sxn GET "/settings/$kind" | jq -r --arg n "$name" '[.[]|select(.name==$n and .is4k==false)][0].id // empty')"
  if [ -n "$id" ]; then
    printf '%s' "$body" | sx PUT "/settings/$kind/$id" >/dev/null # id is read-only in the body
    echo "$kind: server updated (profile $pname, root $root)"
  else
    printf '%s' "$body" | sx POST "/settings/$kind" >/dev/null
    echo "$kind: server created (profile $pname, root $root)"
  fi
}
dvr radarr 7878 /data/media/movies
dvr sonarr 8989 /data/media/tv

# Lidarr: Seerr has no music support. Music requests come later through the gateway.

# ---------------------------------------------------------- initialize + CSRF
sxn POST /settings/initialize >/dev/null
echo "initialized=true"

# csrfProtection is read at server start, so the stored flag alone proves nothing (an interrupted
# run can leave flag=true but unenforced). Probe enforcement: an idempotent state-changing POST with
# the API key and NO csrf cookie/header must be refused with 403; if not, restart and test again.
csrf_enforced() { [ "$(curl -s -o /dev/null -w '%{http_code}' -K "$TMP/api.cfg" -X POST "$BASE/api/v1/settings/initialize")" = 403 ]; }
wait_healthy() {
  for _ in $(seq 1 36); do
    [ "$(docker inspect -f '{{.State.Health.Status}}' seerr)" = healthy ] && return 0
    sleep 5
  done
  return 1
}
if [ "$(sxn GET /settings/network | jq -r '.csrfProtection')" != true ]; then
  jq -n '{csrfProtection:true,trustProxy:false}' | sx POST /settings/network >/dev/null
  echo "csrfProtection flag set"
fi
if csrf_enforced; then
  echo "csrfProtection enforced"
else
  echo "csrfProtection not enforced yet; restarting seerr to apply"
  docker restart seerr >/dev/null
  wait_healthy || { echo "seerr not healthy after restart" >&2; exit 1; }
  csrf_enforced || { echo "csrfProtection still NOT enforced after restart" >&2; exit 1; }
  echo "csrfProtection enforced"
fi
chmod 600 "$CFGJSON" 2>/dev/null || true # settings.json holds the downstream API keys
echo "seerr-setup done"
