#!/usr/bin/env bash
# Idempotent setup of Prowlarr / Radarr / Sonarr / Lidarr.
#   arr-setup.sh prepare    before first start: API keys + config.xml (keys never in env)
#   arr-setup.sh configure  after healthy: UI login, folders, naming, Jellyfin, Prowlarr apps
# Secrets are read from files; they never appear in args, env, logs or stdout.
set -euo pipefail

MODE="${1:-}"
ENV="${ENV_FILE:-/opt/chithram-media/media-stack.env}"
set -a
# shellcheck disable=SC1090
. "$ENV"
set +a

S="$SECRETS_ROOT"
UI_USER="chithram-admin"
APPS="prowlarr radarr sonarr lidarr"
umask 077
mkdir -p "$S"
chmod 700 "$S"

port_of() { case "$1" in
  prowlarr) echo "$PROWLARR_PORT" ;; radarr) echo "$RADARR_PORT" ;;
  sonarr) echo "$SONARR_PORT" ;; lidarr) echo "$LIDARR_PORT" ;; esac; }
inner_port() { case "$1" in prowlarr) echo 9696 ;; radarr) echo 7878 ;; sonarr) echo 8989 ;; lidarr) echo 8686 ;; esac; }
ver_of() { case "$1" in prowlarr|lidarr) echo v1 ;; *) echo v3 ;; esac; }

# ---------------------------------------------------------------- prepare
# Python edits (or creates) config.xml. The key is read from a file, never argv/env.
xml_edit() { # cfg keyfile innerport instance
  python3 -I - "$@" <<'PY'
import os, sys, tempfile
import xml.etree.ElementTree as ET
cfg, keyfile, port, inst = sys.argv[1:5]
key = open(keyfile).read().strip()
if os.path.exists(cfg):
    tree = ET.parse(cfg); root = tree.getroot()
else:
    root = ET.Element("Config"); tree = ET.ElementTree(root)
def get(tag):
    e = root.find(tag)
    if e is None:
        e = ET.SubElement(root, tag)
    return e
cur = get("ApiKey")
if cur.text and cur.text.strip() and cur.text.strip() != key:
    sys.exit("config.xml ApiKey differs from secrets file; refusing to change it")
cur.text = key
want = {"BindAddress": "*", "Port": port, "LaunchBrowser": "False",
        "AuthenticationMethod": "Forms", "AuthenticationRequired": "Enabled",
        "UrlBase": "", "LogLevel": "info", "AnalyticsEnabled": "False"}
for k, v in want.items():
    get(k).text = v
if root.find("InstanceName") is None:
    get("InstanceName").text = inst
ET.indent(tree, space="  ")
new = ET.tostring(root, encoding="unicode")
if os.path.exists(cfg) and open(cfg).read().strip() == new.strip():
    print("unchanged")
    sys.exit(0)
d = os.path.dirname(cfg)
fd, tmp = tempfile.mkstemp(dir=d, prefix=".config.xml.")
try:
    with os.fdopen(fd, "w") as f:
        f.write(new)
    os.chmod(tmp, 0o600)
    os.replace(tmp, cfg)
except BaseException:
    try:
        os.unlink(tmp)
    except FileNotFoundError:
        pass
    raise
print("written")
PY
}

prepare() {
  [ -s "$S/arr_ui_password" ] || { openssl rand -hex 24 | tr -d '\n' > "$S/arr_ui_password"; chmod 600 "$S/arr_ui_password"; echo "generated UI password (stored, not shown)"; }
  [ -s "$S/arr_ui_user" ] || { printf '%s' "$UI_USER" > "$S/arr_ui_user"; chmod 600 "$S/arr_ui_user"; }
  local a cfg kf
  for a in $APPS; do
    mkdir -p "$CONFIG_ROOT/$a"; chmod 700 "$CONFIG_ROOT/$a"
    cfg="$CONFIG_ROOT/$a/config.xml"; kf="$S/${a}_api_key"
    if [ ! -s "$kf" ]; then
      if [ -s "$cfg" ] && existing="$(python3 -I -c 'import sys,xml.etree.ElementTree as E;print((E.parse(sys.argv[1]).getroot().findtext("ApiKey") or "").strip())' "$cfg")" && [ -n "$existing" ]; then
        printf '%s' "$existing" > "$kf"; echo "$a: adopted existing key from config.xml (stored, not shown)"
      else
        openssl rand -hex 16 | tr -d '\n' > "$kf"; echo "$a: generated API key (stored, not shown)"
      fi
      chmod 600 "$kf"
    fi
    if [ "$(docker inspect -f '{{.State.Running}}' "$a" 2>/dev/null || echo false)" = true ]; then
      echo "$a: container running; config.xml left untouched"
    else
      echo "$a: config.xml $(xml_edit "$cfg" "$kf" "$(inner_port "$a")" "${a^}")"
    fi
  done
}

# -------------------------------------------------------------- configure
TMP=""
setup_tmp() {
  TMP="$(mktemp -d "$S/.arr.XXXXXX")"
  trap 'rm -rf "$TMP"' EXIT
  local a
  for a in $APPS; do
    { printf 'header = "X-Api-Key: '; tr -d '\n' < "$S/${a}_api_key"; printf '"\n'; } > "$TMP/$a.cfg"
  done
}
# get APP PATH ; send APP METHOD PATH  (JSON body on stdin)
get()  { curl -fsS -K "$TMP/$1.cfg" "http://127.0.0.1:$(port_of "$1")/api/$(ver_of "$1")$2"; }
send() { curl -fsS -K "$TMP/$1.cfg" -X "$2" -H 'Content-Type: application/json' --data @- "http://127.0.0.1:$(port_of "$1")/api/$(ver_of "$1")$3"; }

# jq helper: set an existing key, fail if the schema lacks it; opt() sets only if present.
# shellcheck disable=SC2016  # jq program, not shell
JQDEF='def s($k;$v): if has($k) then .[$k]=$v else error("missing field "+$k) end;
       def opt($k;$v): if has($k) then .[$k]=$v else . end;'

ui_login() { # app
  local a="$1" cur
  cur="$(get "$a" /config/host)"
  if printf '%s' "$cur" | jq -e --rawfile u "$S/arr_ui_user" '(.username==$u) and (.authenticationMethod=="forms") and (.authenticationRequired=="enabled")' >/dev/null; then
    echo "$a: UI login already set"; return
  fi
  printf '%s' "$cur" | jq --rawfile u "$S/arr_ui_user" --rawfile p "$S/arr_ui_password" \
    "$JQDEF"' s("authenticationMethod";"forms") | s("authenticationRequired";"enabled") | s("username";$u) | s("password";$p) | s("passwordConfirmation";$p)' \
    | send "$a" PUT "/config/host/$(printf '%s' "$cur" | jq -er .id)" >/dev/null
  echo "$a: UI login set (user $UI_USER)"
}

root_folder() { # app path
  local a="$1" p="$2" body
  if get "$a" /rootfolder | jq -e --arg p "$p" 'map(select(.path==$p or .path==($p+"/")))|length>0' >/dev/null; then
    echo "$a: root folder $p exists"
    if [ "$a" = lidarr ]; then # monitor nothing by default until the owner sets a policy
      local rf
      rf="$(get lidarr /rootfolder | jq -c --arg p "$p" '[.[]|select(.path|rtrimstr("/")==$p)][0]')"
      if ! printf '%s' "$rf" | jq -e '.defaultMonitorOption=="none" and .defaultNewItemMonitorOption=="none"' >/dev/null; then
        printf '%s' "$rf" | jq '.defaultMonitorOption="none"|.defaultNewItemMonitorOption="none"' | send lidarr PUT "/rootfolder/$(printf '%s' "$rf" | jq -er .id)" >/dev/null
        echo "lidarr: root folder monitor defaults set to none"
      fi
    fi
    return
  fi
  if [ "$a" = lidarr ]; then
    local qp mp
    qp="$(get lidarr /qualityprofile | jq -er '.[0].id')"
    mp="$(get lidarr /metadataprofile | jq -er '.[0].id')"
    body="$(jq -n --arg p "$p" --argjson q "$qp" --argjson m "$mp" \
      '{name:"Music",path:$p,defaultQualityProfileId:$q,defaultMetadataProfileId:$m,defaultMonitorOption:"none",defaultNewItemMonitorOption:"none",defaultTags:[]}')"
  else
    body="$(jq -n --arg p "$p" '{path:$p}')"
  fi
  printf '%s' "$body" | send "$a" POST /rootfolder >/dev/null
  echo "$a: root folder $p created"
}

put_cfg() { # app name jq-filter  (GET /config/<name>, apply filter, PUT back)
  local a="$1" n="$2" cur
  cur="$(get "$a" "/config/$n")"
  printf '%s' "$cur" | jq "$JQDEF $3" | send "$a" PUT "/config/$n/$(printf '%s' "$cur" | jq -er .id)" >/dev/null
  echo "$a: config/$n updated"
}

cdh() { put_cfg "$1" downloadclient 'opt("enableCompletedDownloadHandling";true) | opt("removeCompletedDownloads";false) | opt("removeFailedDownloads";false)'; }

jellyfin_notify() { # app
  local a="$1" schema body existing id
  schema="$(get "$a" /notification/schema | jq -c '[.[]|select(.implementation=="MediaBrowser")][0]')"
  [ "$schema" != null ] || { echo "$a: no MediaBrowser notification schema" >&2; exit 1; }
  body="$(printf '%s' "$schema" | jq --rawfile k "$S/jellyfin_api_key" '
    def f($n;$v): .fields |= map(if .name==$n then .value=$v else . end);
    .name="Jellyfin"
    | f("host";"jellyfin") | f("port";8096) | f("useSsl";false) | f("apiKey";$k) | f("updateLibrary";true)
    | (to_entries|map(select(.key|test("^on[A-Z]")))|map(.key)) as $ons
    | reduce $ons[] as $k (.; .[$k]=false)
    | reduce (["onDownload","onReleaseImport","onUpgrade","onRename"][] ) as $k (.; if has($k) then .[$k]=true else . end)
    | .includeHealthWarnings=false')"
  id="$(get "$a" /notification | jq -r '[.[]|select(.name=="Jellyfin")][0].id // empty')"
  if [ -n "$id" ]; then
    printf '%s' "$body" | jq --argjson id "$id" '.id=$id' | send "$a" PUT "/notification/$id" >/dev/null
    echo "$a: Jellyfin notification updated"
  else
    printf '%s' "$body" | send "$a" POST /notification >/dev/null
    echo "$a: Jellyfin notification created"
  fi
}

configure_radarr() {
  root_folder radarr /data/media/movies
  put_cfg radarr naming 's("renameMovies";true) | s("standardMovieFormat";"{Movie Title} ({Release Year}) {Quality Full}") | s("movieFolderFormat";"{Movie Title} ({Release Year})")'
  put_cfg radarr mediamanagement 's("copyUsingHardlinks";true) | s("skipFreeSpaceCheckWhenImporting";false) | s("deleteEmptyFolders";false) | s("autoUnmonitorPreviouslyDownloadedMovies";false) | s("recycleBin";"")'
  cdh radarr
}
configure_sonarr() {
  root_folder sonarr /data/media/tv
  put_cfg sonarr naming 's("renameEpisodes";true) | s("standardEpisodeFormat";"{Series Title} - S{season:00}E{episode:00} - {Episode Title} {Quality Full}") | s("seriesFolderFormat";"{Series Title} ({Series Year})") | s("seasonFolderFormat";"Season {season:00}")'
  put_cfg sonarr mediamanagement 's("copyUsingHardlinks";true) | s("skipFreeSpaceCheckWhenImporting";false) | s("deleteEmptyFolders";false) | s("recycleBin";"")'
  cdh sonarr
}
configure_lidarr() {
  root_folder lidarr /data/media/music
  # Lidarr has no separate album-folder setting: the album folder is the first path part of the track format.
  put_cfg lidarr naming 's("renameTracks";true) | s("standardTrackFormat";"{Album Title} ({Release Year})/{Artist Name} - {Album Title} - {track:00} - {Track Title}") | s("multiDiscTrackFormat";"{Album Title} ({Release Year})/{medium:00}-{track:00} - {Artist Name} - {Track Title}") | s("artistFolderFormat";"{Artist Name}")'
  put_cfg lidarr mediamanagement 's("copyUsingHardlinks";true) | s("skipFreeSpaceCheckWhenImporting";false) | s("deleteEmptyFolders";false) | s("recycleBin";"")'
  cdh lidarr
}

prowlarr_apps() {
  local a schema body id impl
  for a in radarr sonarr lidarr; do
    impl="${a^}"
    schema="$(get prowlarr /applications/schema | jq -c --arg i "$impl" '[.[]|select(.implementation==$i)][0]')"
    [ "$schema" != null ] || { echo "prowlarr: no $impl application schema" >&2; exit 1; }
    body="$(printf '%s' "$schema" | jq --rawfile k "$S/${a}_api_key" --arg n "$impl" --arg b "http://$a:$(inner_port "$a")" '
      def f($n;$v): .fields |= map(if .name==$n then .value=$v else . end);
      .name=$n | .syncLevel="fullSync"
      | f("prowlarrUrl";"http://prowlarr:9696") | f("baseUrl";$b) | f("apiKey";$k)')"
    id="$(get prowlarr /applications | jq -r --arg n "$impl" '[.[]|select(.name==$n)][0].id // empty')"
    if [ -n "$id" ]; then
      printf '%s' "$body" | jq --argjson id "$id" '.id=$id' | send prowlarr PUT "/applications/$id" >/dev/null
      echo "prowlarr: application $impl updated"
    else
      printf '%s' "$body" | send prowlarr POST /applications >/dev/null
      echo "prowlarr: application $impl created"
    fi
  done
}

configure() {
  setup_tmp
  local a
  [ -s "$S/jellyfin_api_key" ] || { echo "jellyfin_api_key missing; run jellyfin-setup first" >&2; exit 1; }
  for a in $APPS; do
    curl -fsS "http://127.0.0.1:$(port_of "$a")/ping" >/dev/null || { echo "$a not reachable" >&2; exit 1; }
    ui_login "$a"
  done
  configure_radarr
  configure_sonarr
  configure_lidarr
  for a in radarr sonarr lidarr; do jellyfin_notify "$a"; done
  prowlarr_apps
  echo "arr-setup done"
}

case "$MODE" in
  prepare) prepare ;;
  configure) configure ;;
  *) echo "usage: $0 prepare|configure" >&2; exit 2 ;;
esac
