#!/usr/bin/env bash
# Idempotent first-run setup of Jellyfin via its API.
# Secrets are read from files; they never appear in args, logs or stdout.
set -euo pipefail

ENV="${ENV_FILE:-/opt/chithram-media/media-stack.env}"
set -a
# shellcheck disable=SC1090
. "$ENV"
set +a

BASE="http://127.0.0.1:${JELLYFIN_PORT}"
S="$SECRETS_ROOT"
umask 077
mkdir -p "$S"
TMP="$(mktemp -d "$S/.setup.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
CLIENT='Client=\"chithram-setup\", Device=\"chithram-media\", DeviceId=\"chithram-setup\", Version=\"1.0\"'

# Write a curl config with the auth header (token read from a file) -> $TMP/auth.cfg
mkauth() { # $1 = token file or empty
  if [ -n "${1:-}" ]; then
    { printf 'header = "Authorization: MediaBrowser %s, Token=\\"' "$CLIENT"; tr -d '\n' < "$1"; printf '\\""\n'; } > "$TMP/auth.cfg"
  else
    printf 'header = "Authorization: MediaBrowser %s"\n' "$CLIENT" > "$TMP/auth.cfg"
  fi
}
# api METHOD PATH [json-body-on-stdin]; response body to stdout, fails on HTTP >= 400
api() {
  local m="$1" p="$2"; shift 2
  if [ -t 0 ] || [ "${NOBODY:-}" = 1 ]; then
    curl -fsS -K "$TMP/auth.cfg" -X "$m" "$BASE$p"
  else
    curl -fsS -K "$TMP/auth.cfg" -X "$m" -H 'Content-Type: application/json' --data @- "$BASE$p"
  fi
}

mkdir -p "$S"; chmod 700 "$S"
[ -s "$S/jellyfin_admin_user" ] || { printf '%s' 'chithram-admin' > "$S/jellyfin_admin_user"; chmod 600 "$S/jellyfin_admin_user"; }
[ -s "$S/jellyfin_admin_password" ] || { openssl rand -base64 32 | tr -d '\n' > "$S/jellyfin_admin_password"; chmod 600 "$S/jellyfin_admin_password"; echo "generated admin password (stored, not shown)"; }

curl -fsS "$BASE/health" >/dev/null || { echo "jellyfin not reachable at $BASE" >&2; exit 1; }
wizard="$(curl -fsS "$BASE/System/Info/Public" | jq -r '.StartupWizardCompleted')"

mkauth ""
if [ "$wizard" != "true" ]; then
  echo "running startup wizard"
  jq -n '{UICulture:"en-US",MetadataCountryCode:"US",PreferredMetadataLanguage:"en"}' | api POST /Startup/Configuration
  NOBODY=1 api GET /Startup/User >/dev/null
  jq -n --rawfile n "$S/jellyfin_admin_user" --rawfile p "$S/jellyfin_admin_password" '{Name:$n,Password:$p}' | api POST /Startup/User
  jq -n '{EnableRemoteAccess:false,EnableAutomaticPortMapping:false}' | api POST /Startup/RemoteAccess
  NOBODY=1 api POST /Startup/Complete </dev/null
else
  echo "startup wizard already completed"
fi

# Authenticate
jq -n --rawfile n "$S/jellyfin_admin_user" --rawfile p "$S/jellyfin_admin_password" '{Username:$n,Pw:$p}' \
  | api POST /Users/AuthenticateByName > "$TMP/auth.json" || { echo "authentication failed (admin user differs from secrets?)" >&2; exit 1; }
# admin user reported by Jellyfin must equal the one in secrets
jq -e --rawfile n "$S/jellyfin_admin_user" '.User.Name == $n' "$TMP/auth.json" >/dev/null || { echo "admin username differs from secrets; refusing" >&2; exit 1; }
jq -er '.AccessToken' "$TMP/auth.json" | tr -d '\n' > "$TMP/session.tok"
[ -s "$TMP/session.tok" ] || { echo "authentication failed" >&2; exit 1; }
mkauth "$TMP/session.tok"

# API key
if [ -s "$S/jellyfin_api_key" ]; then
  mkauth "$S/jellyfin_api_key"
  if NOBODY=1 api GET /System/Info >/dev/null 2>&1; then echo "api key present and valid"; else rm -f "$S/jellyfin_api_key"; fi
  mkauth "$TMP/session.tok"
fi
if [ ! -s "$S/jellyfin_api_key" ]; then
  keys="$(NOBODY=1 api GET /Auth/Keys)"
  if ! printf '%s' "$keys" | jq -e '.Items[] | select(.AppName=="chithram-gateway")' >/dev/null; then
    NOBODY=1 api POST "/Auth/Keys?app=chithram-gateway" </dev/null
  fi
  # take the newest chithram-gateway key (the only one we can read)
  NOBODY=1 api GET /Auth/Keys | jq -er '[.Items[] | select(.AppName=="chithram-gateway")] | sort_by(.DateCreated) | last | .AccessToken' | tr -d '\n' > "$TMP/api_key.new"
  [ -s "$TMP/api_key.new" ] || { echo "api key fetch failed" >&2; exit 1; }
  chmod 600 "$TMP/api_key.new"
  mv "$TMP/api_key.new" "$S/jellyfin_api_key"
  echo "api key created (stored, not shown)"
fi

# Network: remote access off, local subnets limited to loopback + docker bridge range.
net="$(NOBODY=1 api GET /System/Configuration/network)"
printf '%s' "$net" | jq --arg sn "$MEDIA_SUBNET" '.EnableRemoteAccess=false | .EnableUPnP=false | .AutoDiscovery=false | .LocalNetworkSubnets=["127.0.0.1/32",$sn]' \
  | api POST /System/Configuration/network
echo "network: EnableRemoteAccess=false EnableUPnP=false AutoDiscovery=false LocalNetworkSubnets=127.0.0.1/32,${MEDIA_SUBNET}"

# Libraries
have="$(NOBODY=1 api GET /Library/VirtualFolders | jq -r '.[].Name')"
mklib() { # name type path
  if printf '%s\n' "$have" | grep -qx "$1"; then echo "library $1 exists"; return; fi
  jq -n --arg p "$3" '{LibraryOptions:{PathInfos:[{Path:$p}]}}' \
    | api POST "/Library/VirtualFolders?name=$1&collectionType=$2&refreshLibrary=false"
  echo "library $1 created ($3)"
}
mklib Movies movies /data/media/movies
mklib TV tvshows /data/media/tv
mklib Music music /data/media/music

NOBODY=1 api POST /Library/Refresh </dev/null
echo "library scan triggered"
