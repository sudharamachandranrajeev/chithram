#!/usr/bin/env bash
# Verify the gateway (Phase 7a). Exits non-zero on any failure. Prints no secret values.
# shellcheck disable=SC2015  # pass/nope helpers always return 0
# RESTART_TEST=1 adds gateway restart + rollback->deploy (pairings must survive) and re-runs
# verify-jellyfin / verify-arr / verify-seerr.
# The end-to-end test creates (and removes) temporary Jellyfin users, their Seerr users, gateway
# devices, one Seerr request and one Radarr movie. It only deletes objects it created.
# Never use `bash -x` on this script: variables hold tokens and pairing codes.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK="$(dirname "$HERE")"
ENV="${ENV_FILE:-/opt/chithram-media/media-stack.env}"
export ENV_FILE="$ENV"
set -a
# shellcheck disable=SC1090
. "$ENV"
set +a
S="$SECRETS_ROOT"
GW="https://127.0.0.1:${GATEWAY_PORT}"
SEERR="http://127.0.0.1:${SEERR_PORT}"
JF="http://127.0.0.1:${JELLYFIN_PORT}"
fail=0
pass() { echo "PASS $*"; }
nope() { echo "FAIL $*"; fail=1; }
check() { local d="$1"; shift; if "$@"; then pass "$d"; else nope "$d"; fi; }
umask 077
if compgen -G "$S/.verify-gateway.*" >/dev/null; then
  echo "FAIL leftover temp dir from an interrupted run: $(compgen -G "$S/.verify-gateway.*" | tr '\n' ' ')" >&2
  echo "     Cleanup (manual): remove the dir(s) (throwaway tokens only); delete any gwtest-* user in" >&2
  echo "     Jellyfin and Seerr; 'gateway users remove gwtest-...' for leftovers; remove the TMDB 10331" >&2
  echo "     request and the Radarr movie (delete WITHOUT files)." >&2
  exit 1
fi
TMP="$(mktemp -d "$S/.verify-gateway.XXXXXX")"

gwx() { docker compose --env-file "$ENV" exec -T gateway /app/gateway "$@"; }

# ---- cleanup state (only objects this run created)
T_RADARR_ID=""; T_REQ_ID=""; T_MEDIA_ID=""; MOVIES_BEFORE=""
T_JF_REQ=""; T_JF_VIEW=""; T_JF_HID=""; T_SEERR_REQ=""; T_SEERR_VIEW=""; T_SEERR_HID=""
ADMIN_PREEXISTED=1; ADMIN_ROLE=""; T_DEVICES=""
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
  local d
  [ -n "$T_RADARR_ID" ] && curl -s -o /dev/null -K "$TMP/radarr.cfg" -X DELETE "http://127.0.0.1:${RADARR_PORT}/api/v3/movie/${T_RADARR_ID}?deleteFiles=false&addImportExclusion=false"
  [ -n "$T_REQ_ID" ] && curl -s -o /dev/null -K "$TMP/api.cfg" -K "$TMP/csrf.cfg" -X DELETE "$SEERR/api/v1/request/${T_REQ_ID}"
  [ -n "$T_MEDIA_ID" ] && curl -s -o /dev/null -K "$TMP/api.cfg" -K "$TMP/csrf.cfg" -X DELETE "$SEERR/api/v1/media/${T_MEDIA_ID}"
  for d in $T_DEVICES; do gwx devices revoke "$d" >/dev/null 2>&1; done
  gwx users remove "$T_JF_REQ" >/dev/null 2>&1
  gwx users remove "$T_JF_VIEW" >/dev/null 2>&1
  [ -n "$T_JF_HID" ] && gwx users remove "$T_JF_HID" >/dev/null 2>&1
  [ "$ADMIN_PREEXISTED" = 0 ] && [ -s "$S/jellyfin_admin_user" ] && gwx users remove "$(cat "$S/jellyfin_admin_user")" >/dev/null 2>&1
  [ "$ADMIN_PREEXISTED" = 1 ] && [ -n "$ADMIN_ROLE" ] && [ -s "$S/jellyfin_admin_user" ] && gwx users set-role --user "$(cat "$S/jellyfin_admin_user")" --role "$ADMIN_ROLE" >/dev/null 2>&1
  [ -n "$T_SEERR_REQ" ] && curl -s -o /dev/null -K "$TMP/api.cfg" -K "$TMP/csrf.cfg" -X DELETE "$SEERR/api/v1/user/${T_SEERR_REQ}"
  [ -n "$T_SEERR_VIEW" ] && curl -s -o /dev/null -K "$TMP/api.cfg" -K "$TMP/csrf.cfg" -X DELETE "$SEERR/api/v1/user/${T_SEERR_VIEW}"
  [ -n "$T_SEERR_HID" ] && curl -s -o /dev/null -K "$TMP/api.cfg" -K "$TMP/csrf.cfg" -X DELETE "$SEERR/api/v1/user/${T_SEERR_HID}"
  [ -n "$T_JF_REQ" ] && curl -s -o /dev/null -K "$TMP/jf.cfg" -X DELETE "$JF/Users/${T_JF_REQ}"
  [ -n "$T_JF_VIEW" ] && curl -s -o /dev/null -K "$TMP/jf.cfg" -X DELETE "$JF/Users/${T_JF_VIEW}"
  [ -n "$T_JF_HID" ] && curl -s -o /dev/null -K "$TMP/jf.cfg" -X DELETE "$JF/Users/${T_JF_HID}"
  rmnew
  rm -rf "$TMP"
}
trap cleanup EXIT

{ printf 'header = "X-Api-Key: '; tr -d '\n' < "$S/seerr_api_key"; printf '"\n'; } > "$TMP/api.cfg"
{ printf 'header = "X-Api-Key: '; tr -d '\n' < "$S/radarr_api_key"; printf '"\n'; } > "$TMP/radarr.cfg"
{ printf 'header = "X-Api-Key: '; tr -d '\n' < "$S/sonarr_api_key"; printf '"\n'; } > "$TMP/sonarr.cfg"
{ printf 'header = "Authorization: MediaBrowser Token=\\"'; tr -d '\n' < "$S/jellyfin_api_key"; printf '\\""\n'; } > "$TMP/jf.cfg"

prime_csrf() {
  : > "$TMP/csrf.cfg"; rm -f "$TMP/jar"
  curl -fsS -c "$TMP/jar" -o /dev/null "$SEERR/api/v1/status"
  local c x
  c="$(awk -F'\t' '{sub(/^#HttpOnly_/,"",$1)} $6=="_csrf"{print $7}' "$TMP/jar")"
  x="$(awk -F'\t' '{sub(/^#HttpOnly_/,"",$1)} $6=="XSRF-TOKEN"{print $7}' "$TMP/jar")"
  [ -n "$c" ] && printf 'header = "X-XSRF-TOKEN: %s"\nheader = "Cookie: _csrf=%s; XSRF-TOKEN=%s"\n' "$x" "$c" "$x" > "$TMP/csrf.cfg"
  return 0
}
prime_csrf
sg() { curl -fsS -K "$TMP/api.cfg" "$SEERR/api/v1$1"; }
sn() { curl -fsS -K "$TMP/api.cfg" -K "$TMP/csrf.cfg" -X "$1" "$SEERR/api/v1$2"; }
rg() { curl -fsS -K "$TMP/radarr.cfg" "http://127.0.0.1:${RADARR_PORT}/api/v3$1"; }
sgr() { curl -fsS -K "$TMP/sonarr.cfg" "http://127.0.0.1:${SONARR_PORT}/api/v3$1"; }

# gateway call: gw TOKENFILE METHOD PATH [body-file]  -> "<body>\n<http status>"; token only via -K file
gw() {
  local tf="$1" m="$2" p="$3" b="${4:-}"
  if [ "$tf" != - ]; then { printf 'header = "Authorization: Bearer '; tr -d '\n' < "$tf"; printf '"\n'; } > "$TMP/auth.cfg"; else : > "$TMP/auth.cfg"; fi
  if [ -n "$b" ]; then
    curl -sS --cacert "$S/gateway_tls_cert" -K "$TMP/auth.cfg" -X "$m" -H 'Content-Type: application/json' --data "@$b" -w '\n%{http_code}' "$GW$p"
  else
    curl -sS --cacert "$S/gateway_tls_cert" -K "$TMP/auth.cfg" -X "$m" -w '\n%{http_code}' "$GW$p"
  fi
}
gws() { gw "$@" | tail -1; }          # status only
gwb() { gw "$@" | sed '$d'; }         # body only
# pair USER ROLE OUTFILE -> pairing code into OUTFILE (never printed)
mkcode() {
  gwx pair --user "$1" --role "$2" | sed -n '1s/.*): \([0-9]\{6\}\)$/\1/p' | tr -d '\n' > "$3"
  [ "$(wc -c < "$3")" = 6 ]
}
# redeem CODEFILE DEVNAME -> HTTP status; token (if any) to $TMP/last.json
redeem() {
  jq -n --rawfile c "$1" --arg d "$2" '{code:$c,deviceName:$d}' > "$TMP/pairbody.json"
  gw - POST /v1/pair "$TMP/pairbody.json" > "$TMP/pairout"
  sed '$d' "$TMP/pairout" > "$TMP/last.json"; tail -1 "$TMP/pairout"
}

cd "$STACK"
echo "== 1 config and inspect"
check "compose config valid" docker compose --env-file "$ENV" config -q
if env -i PATH="$PATH" HOME="$HOME" docker compose --env-file /dev/null config -q >/dev/null 2>&1; then nope "compose does NOT fail closed"; else pass "compose fails closed with empty env"; fi
if env -i PATH="$PATH" HOME="$HOME" docker compose --env-file <(grep -v '^GATEWAY_PORT=' "$ENV") config -q >/dev/null 2>&1; then nope "compose accepts missing GATEWAY_PORT"; else pass "compose requires GATEWAY_PORT"; fi
insp="$(docker inspect gateway)"
j() { printf '%s' "$insp" | jq -r "$1"; }
check "Dockerfile FROM lines are all digest-pinned" [ "$(grep -c '^FROM ' gateway/Dockerfile)" = "$(grep -cE '^FROM [^ ]+@sha256:[0-9a-f]{64}( |$)' gateway/Dockerfile)" ]
check "ports only 127.0.0.1 ($(j '[.[0].NetworkSettings.Ports[][]?|.HostIp+":"+.HostPort]|join(",")'))" [ "$(j '[.[0].NetworkSettings.Ports[][]?|.HostIp+":"+.HostPort]|join(",")')" = "127.0.0.1:${GATEWAY_PORT}" ]
echo "     caps: drop=$(j '.[0].HostConfig.CapDrop|join(",")') add=[$(j '(.[0].HostConfig.CapAdd//[])|join(",")')] secopt=$(j '.[0].HostConfig.SecurityOpt|join(",")') readonly=$(j '.[0].HostConfig.ReadonlyRootfs') user=$(j '.[0].Config.User')"
check "cap_drop ALL, no cap_add, no-new-privileges, read_only" [ "$(j '(.[0].HostConfig.CapDrop|join(","))+"|"+((.[0].HostConfig.CapAdd//[])|join(","))+"|"+(.[0].HostConfig.SecurityOpt|join(","))+"|"+(.[0].HostConfig.ReadonlyRootfs|tostring)')" = "ALL||no-new-privileges:true|true" ]
check "runs as $PUID:$PGID" [ "$(j '.[0].Config.User')" = "$PUID:$PGID" ]
check "pids_limit/mem_limit set ($(j '.[0].HostConfig.PidsLimit') / $(j '.[0].HostConfig.Memory'))" [ "$(j '(.[0].HostConfig.PidsLimit>0 and .[0].HostConfig.Memory>0)|tostring')" = true ]
check "mounts: state dir + 6 file secrets only" [ "$(j '[.[0].Mounts[]|.Destination]|sort|join(",")')" = "/run/secrets/gateway_tls_cert,/run/secrets/gateway_tls_key,/run/secrets/jellyfin_api_key,/run/secrets/radarr_api_key,/run/secrets/seerr_api_key,/run/secrets/sonarr_api_key,/state" ]
check "secret mounts read-only" [ "$(j '[.[0].Mounts[]|select(.Destination|startswith("/run/secrets"))|select(.RW)]|length')" = 0 ]
check "on media network" [ "$(j '.[0].NetworkSettings.Networks|keys|join(",")')" = "chithram-media_media" ]
check "healthy" [ "$(j '.[0].State.Health.Status')" = healthy ]
check "no secrets in env" [ "$(j '[.[0].Config.Env[]|select(test("KEY|PASS|SECRET|TOKEN|CODE"))]|length')" = 0 ]

echo "== 2 reachability, TLS, auth (from Windows)"
FP_CLI="$(gwx fingerprint | tr -d '\r\n')"
FP_TLS="$(openssl s_client -connect "127.0.0.1:${GATEWAY_PORT}" </dev/null 2>/dev/null | openssl x509 -noout -fingerprint -sha256 | cut -d= -f2)"
check "CLI fingerprint printed" [ -n "$FP_CLI" ]
check "served certificate fingerprint == printed fingerprint (WSL)" [ "$FP_CLI" = "$FP_TLS" ]
PS_FP="[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; \$ErrorActionPreference='Stop'; \$t=New-Object Net.Sockets.TcpClient('127.0.0.1',${GATEWAY_PORT}); \$cb=[Net.Security.RemoteCertificateValidationCallback]{param(\$s,\$c,\$ch,\$e) \$true}; \$l=New-Object Net.Security.SslStream(\$t.GetStream(),\$false,\$cb); \$l.AuthenticateAsClient('localhost'); \$x=New-Object Security.Cryptography.X509Certificates.X509Certificate2(\$l.RemoteCertificate); \$h=[Security.Cryptography.SHA256]::Create().ComputeHash(\$x.RawData); (\$h | ForEach-Object { \$_.ToString('X2') }) -join ':'"
WIN_FP="$(powershell.exe -NoProfile -Command "$PS_FP" 2>/dev/null | tr -d '\r\n' || true)"
check "Windows TLS fingerprint == printed fingerprint (got ${WIN_FP:-n/a})" [ "$WIN_FP" = "$FP_CLI" ]
PS_REQ() { # token-or-empty
  local hdr=""
  [ -n "$1" ] && hdr="-Headers @{Authorization='Bearer $1'}"
  powershell.exe -NoProfile -Command "Add-Type 'using System.Net;using System.Security.Cryptography.X509Certificates;public class TP:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}'; [Net.ServicePointManager]::CertificatePolicy=New-Object TP; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; try { (Invoke-WebRequest -UseBasicParsing $hdr https://127.0.0.1:${GATEWAY_PORT}/v1/me).StatusCode } catch { if (\$_.Exception.Response) { \$_.Exception.Response.StatusCode.value__ } else { 'ERR' } }" 2>/dev/null | tr -d '\r\n'
}
c="$(PS_REQ '')"
check "Windows GET /v1/me without token = 401 (got ${c:-n/a})" [ "$c" = 401 ]
c="$(PS_REQ 'wrongwrongwrongwrongwrongwrong1234567890')"
check "Windows GET /v1/me with wrong token = 401 (got ${c:-n/a})" [ "$c" = 401 ]
c="$(gws - GET /v1/me)"; check "WSL no token = 401 (got $c)" [ "$c" = 401 ]
c="$(gws - GET /v1/library?type=movies)"; check "WSL no token library = 401 (got $c)" [ "$c" = 401 ]
c="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:${GATEWAY_PORT}/v1/me" || true)"
check "plain HTTP on the TLS port is not served (got ${c:-000})" [ "$c" != 200 ]
mapfile -t addrs < <(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 || true)
for ad in "${addrs[@]}"; do
  if curl -sk --max-time 3 -o /dev/null "https://${ad}:${GATEWAY_PORT}/healthz" 2>/dev/null; then nope "gateway reachable on $ad"; fi
done
pass "not reachable on ${#addrs[@]} non-loopback addresses"

echo "== 3 pairing (temporary Jellyfin users)"
ADMIN_NAME="$(cat "$S/jellyfin_admin_user")"
gwx users list | grep -qF "  $ADMIN_NAME  " || ADMIN_PREEXISTED=0
# pairing the admin overwrites its role in the gateway: remember it and restore it at the end
[ "$ADMIN_PREEXISTED" = 1 ] && ADMIN_ROLE="$(gwx users list | awk -v n="$ADMIN_NAME" '$2==n{print $3}' | head -1 | tr -d '\r\n')"
if [ "$(curl -fsS -K "$TMP/jf.cfg" "$JF/Users" | jq '[.[]|select(.Name|startswith("gwtest-"))]|length')" != 0 ] \
  || [ "$(sg "/user?take=100" | jq '[.results[]|select((.jellyfinUsername//"")|startswith("gwtest-"))]|length')" != 0 ]; then
  echo "FAIL leftover gwtest-* user(s) in Jellyfin and/or Seerr; delete them manually and re-run." >&2; exit 1
fi
mkuser() { # NAME -> id on stdout; password only in a 600 temp file
  openssl rand -base64 24 | tr -d '\n' > "$TMP/pw.$1"
  jq -n --arg n "$1" --rawfile p "$TMP/pw.$1" '{Name:$n,Password:$p}' \
    | curl -fsS -K "$TMP/jf.cfg" -X POST -H 'Content-Type: application/json' --data @- "$JF/Users/New" | jq -er '.Id'
}
NAME_REQ="gwtest-req-$$"; NAME_VIEW="gwtest-view-$$"
T_JF_REQ="$(mkuser "$NAME_REQ")"; T_JF_VIEW="$(mkuser "$NAME_VIEW")"
pass "temporary Jellyfin users created (requester, viewer)"

mkcode "$NAME_REQ" requester "$TMP/code.req"
WRONG=000000; [ "$(cat "$TMP/code.req")" = 000000 ] && WRONG=111111
printf '%s' "$WRONG" > "$TMP/code.wrong"
res=""; for _ in 1 2 3 4 5; do res="$res $(redeem "$TMP/code.wrong" attacker)"; done
check "5 wrong attempts all 401 ($res )" [ "$res" = " 401 401 401 401 401" ]
c="$(redeem "$TMP/code.req" phone)"
check "6th attempt with the RIGHT code is locked out = 401 (got $c)" [ "$c" = 401 ]
mkcode "$NAME_REQ" requester "$TMP/code.req"
c="$(redeem "$TMP/code.req" "Test Phone")"
check "fresh code pairs (HTTP $c)" [ "$c" = 200 ]
jq -er '.token' "$TMP/last.json" | tr -d '\n' > "$TMP/tok.req"
T_DEVICES="$T_DEVICES $(jq -er '.deviceId' "$TMP/last.json")"
check "pair response role = requester" [ "$(jq -r '.role' "$TMP/last.json")" = requester ]
c="$(redeem "$TMP/code.req" "Test Phone")"; check "same code a second time = 401 (got $c)" [ "$c" = 401 ]
c="$(redeem "$TMP/code.wrong" "x")"; check "malformed device name accepted only when valid (wrong code 401, got $c)" [ "$c" = 401 ]
printf '{"code":"12ab56","deviceName":"x"}' > "$TMP/bad.json"; c="$(gws - POST /v1/pair "$TMP/bad.json")"
check "non-numeric code = 400 (got $c)" [ "$c" = 400 ]
me="$(gwb "$TMP/tok.req" GET /v1/me)"
check "token works: /v1/me = {$NAME_REQ, requester}" [ "$(printf '%s' "$me" | jq -r '.user+","+.role')" = "$NAME_REQ,requester" ]
mkcode "$NAME_VIEW" viewer "$TMP/code.view"
c="$(redeem "$TMP/code.view" "Viewer Tablet")"; check "viewer pairs (HTTP $c)" [ "$c" = 200 ]
jq -er '.token' "$TMP/last.json" | tr -d '\n' > "$TMP/tok.view"
T_DEVICES="$T_DEVICES $(jq -er '.deviceId' "$TMP/last.json")"
check "viewer /v1/me role viewer" [ "$(gwb "$TMP/tok.view" GET /v1/me | jq -r '.role')" = viewer ]
mkcode "$ADMIN_NAME" admin "$TMP/code.adm"
c="$(redeem "$TMP/code.adm" "Admin Laptop")"; check "admin pairs (HTTP $c)" [ "$c" = 200 ]
jq -er '.token' "$TMP/last.json" | tr -d '\n' > "$TMP/tok.adm"
T_DEVICES="$T_DEVICES $(jq -er '.deviceId' "$TMP/last.json")"
check "admin /v1/me role admin" [ "$(gwb "$TMP/tok.adm" GET /v1/me | jq -r '.role')" = admin ]
check "devices list shows the paired devices without tokens" [ "$(gwx devices list | grep -c .)" -ge 3 ]

echo "== 4 search, request, approval (TMDB 10331, nothing downloads)"
TMDB=10331
pre="$(sg "/movie/$TMDB" | jq -c '{id:(.mediaInfo.id // null),st:(.mediaInfo.status // 0)}')"
if [ "$(printf '%s' "$pre" | jq -r '.st')" -ge 4 ]; then echo "FAIL test film already available; pick another"; exit 1; fi
PRE_MEDIA_ID="$(printf '%s' "$pre" | jq -r '.id // empty')"
if rg /movie | jq -e --argjson t "$TMDB" 'map(select(.tmdbId==$t))|length>0' >/dev/null; then echo "FAIL test movie already in Radarr; refusing"; exit 1; fi
if sg "/request?take=100&filter=all" | jq -e --argjson t "$TMDB" '.results|map(select(.media.tmdbId==$t))|length>0' >/dev/null; then echo "FAIL a request for the test movie exists; refusing"; exit 1; fi
MOVIES_BEFORE="$(ls -A "$DATA_ROOT/media/movies")"
snap="$MOVIES_BEFORE"

sr="$(gwb "$TMP/tok.req" GET '/v1/search?q=Night%20of%20the%20Living%20Dead')"
item="$(printf '%s' "$sr" | jq -c --argjson t "$TMDB" '[.results[]|select(.tmdbId==$t and .type=="movie")][0]')"
check "search finds TMDB $TMDB with a status ($(printf '%s' "$item" | jq -r '.title+" ("+(.year|tostring)+") -> "+.mediaStatus'))" [ "$(printf '%s' "$item" | jq -r '.mediaStatus')" != null ]
check "search status is none before any request" [ "$(printf '%s' "$item" | jq -r '.mediaStatus')" = none ]
check "viewer may search" [ "$(gws "$TMP/tok.view" GET '/v1/search?q=Night')" = 200 ]
check "empty search query = 400" [ "$(gws "$TMP/tok.req" GET '/v1/search?q=')" = 400 ]

jq -n --argjson t "$TMDB" '{tmdbId:$t,type:"movie"}' > "$TMP/req.json"
c="$(gws "$TMP/tok.view" POST /v1/requests "$TMP/req.json")"; check "viewer POST /v1/requests = 403 (got $c)" [ "$c" = 403 ]
check "still no request in Seerr after the viewer attempt" [ "$(sg "/request?take=100&filter=all" | jq --argjson t "$TMDB" '.results|map(select(.media.tmdbId==$t))|length')" = 0 ]
printf '{"tmdbId":"10331","type":"movie"}' > "$TMP/bad.json"; c="$(gws "$TMP/tok.req" POST /v1/requests "$TMP/bad.json")"
check "string tmdbId = 400 (got $c)" [ "$c" = 400 ]
printf '{"tmdbId":10331,"type":"album"}' > "$TMP/bad.json"; c="$(gws "$TMP/tok.req" POST /v1/requests "$TMP/bad.json")"
check "bad type = 400 (got $c)" [ "$c" = 400 ]
rq="$(gw "$TMP/tok.req" POST /v1/requests "$TMP/req.json")"
rqc="$(printf '%s' "$rq" | tail -1)"; rqb="$(printf '%s' "$rq" | sed '$d')"
check "requester POST /v1/requests = 201 (got $rqc)" [ "$rqc" = 201 ]
check "request status awaitingApproval ($(printf '%s' "$rqb" | jq -r '.status'))" [ "$(printf '%s' "$rqb" | jq -r '.status')" = awaitingApproval ]
T_REQ_ID="$(printf '%s' "$rqb" | jq -er '.id')"
mi="$(sg "/movie/$TMDB" | jq -r '.mediaInfo.id // empty')"
if [ -z "$PRE_MEDIA_ID" ] && [ -n "$mi" ]; then T_MEDIA_ID="$mi"; fi
T_SEERR_REQ="$(sg "/request/$T_REQ_ID" | jq -er '.requestedBy.id')"
check "Seerr request is PENDING (1) by an imported Seerr user with REQUEST-only (32)" [ "$(sg "/request/$T_REQ_ID" | jq -r '.status')$(sg "/user/$T_SEERR_REQ" | jq -r '.permissions')" = "132" ]
check "pending: NOT in Radarr" [ "$(rg /movie | jq --argjson t "$TMDB" 'map(select(.tmdbId==$t))|length')" = 0 ]
c="$(gws "$TMP/tok.req" POST "/v1/requests/$T_REQ_ID/approve")"; check "requester approve = 403 (got $c)" [ "$c" = 403 ]
c="$(gws "$TMP/tok.view" POST "/v1/requests/$T_REQ_ID/approve")"; check "viewer approve = 403 (got $c)" [ "$c" = 403 ]
c="$(gws "$TMP/tok.req" POST "/v1/requests/$T_REQ_ID/decline")"; check "requester decline = 403 (got $c)" [ "$c" = 403 ]
check "still PENDING after denied approvals" [ "$(sg "/request/$T_REQ_ID" | jq -r '.status')" = 1 ]
c="$(gws "$TMP/tok.req" POST /v1/requests "$TMP/req.json")"; check "duplicate request = 409 (got $c)" [ "$c" = 409 ]
check "requester sees own request as awaitingApproval" [ "$(gwb "$TMP/tok.req" GET /v1/requests | jq -r --argjson i "$T_REQ_ID" '[.requests[]|select(.id==$i)][0]|.status+"|"+.title')" = "awaitingApproval|Night of the Living Dead" ]
check "viewer sees none of it (empty list)" [ "$(gwb "$TMP/tok.view" GET /v1/requests | jq '.requests|length')" = 0 ]
check "search now shows awaitingApproval" [ "$(gwb "$TMP/tok.req" GET '/v1/search?q=Night%20of%20the%20Living%20Dead' | jq -r --argjson t "$TMDB" '[.results[]|select(.tmdbId==$t and .type=="movie")][0].mediaStatus')" = awaitingApproval ]
c="$(gws "$TMP/tok.req" GET /v1/downloads)"; check "requester GET /v1/downloads = 403 (got $c)" [ "$c" = 403 ]
check "admin sees the request (all requests)" [ "$(gwb "$TMP/tok.adm" GET /v1/requests | jq -r --argjson i "$T_REQ_ID" '[.requests[]|select(.id==$i)]|length')" = 1 ]
ap="$(gw "$TMP/tok.adm" POST "/v1/requests/$T_REQ_ID/approve")"
check "admin approve = 200, status approved ($(printf '%s' "$ap" | sed '$d' | jq -r '.status'))" [ "$(printf '%s' "$ap" | tail -1)$(printf '%s' "$ap" | sed '$d' | jq -r '.status')" = "200approved" ]
rid=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  rid="$(rg /movie | jq -r --argjson t "$TMDB" '[.[]|select(.tmdbId==$t)][0].id // empty')"
  [ -n "$rid" ] && break; sleep 2
done
[ -n "$rid" ] && T_RADARR_ID="$rid"
check "movie appears in Radarr" [ -n "$rid" ]
check "Radarr movie monitored, no file" [ "$(rg "/movie/${rid:-0}" | jq -r '[(.monitored|tostring),(.hasFile|tostring)]|join(",")')" = "true,false" ]
check "0 download clients, empty queues (Radarr, Sonarr)" [ "$(rg /downloadclient | jq length):$(rg /queue | jq -r '.totalRecords'):$(sgr /downloadclient | jq length):$(sgr /queue | jq -r '.totalRecords')" = "0:0:0:0" ]
sleep 4
st="$(gwb "$TMP/tok.req" GET /v1/requests | jq -r --argjson i "$T_REQ_ID" '[.requests[]|select(.id==$i)][0].status')"
check "requester sees approved/searching, not available (got $st)" grep -Eq '^(approved|searching)$' <<<"$st"
check "admin GET /v1/downloads = empty list" [ "$(gwb "$TMP/tok.adm" GET /v1/downloads | jq -c '.downloads')" = "[]" ]
check "invalid request id = 400" [ "$(gws "$TMP/tok.adm" POST /v1/requests/abc/approve)" = 400 ]

echo "== 5 library, images, streaming"
lib="$(gwb "$TMP/tok.req" GET '/v1/library?type=movies')"
bbb="$(printf '%s' "$lib" | jq -c '[.items[]|select(.title=="Big Buck Bunny")][0]')"
check "requester library/movies includes Big Buck Bunny" [ "$(printf '%s' "$bbb" | jq -r '.title')" = "Big Buck Bunny" ]
BBB_ID="$(printf '%s' "$bbb" | jq -er '.id')"
check "library item has id/year/poster path" [ "$(printf '%s' "$bbb" | jq -r '(.id|length==32) and (.poster|startswith("/v1/images/"))|tostring')" = true ]
check "library type tv/music accepted (200)" [ "$(gws "$TMP/tok.req" GET '/v1/library?type=tv')$(gws "$TMP/tok.view" GET '/v1/library?type=music')" = 200200 ]
check "bad library type = 400, bad cursor = 400" [ "$(gws "$TMP/tok.req" GET '/v1/library?type=x')$(gws "$TMP/tok.req" GET '/v1/library?type=movies&cursor=-1')" = 400400 ]
curl -sS --cacert "$S/gateway_tls_cert" -K <({ printf 'header = "Authorization: Bearer '; tr -d '\n' < "$TMP/tok.req"; printf '"\n'; }) -D "$TMP/img.hdr" -o "$TMP/img.bin" "$GW/v1/images/${BBB_ID}?w=200"
check "image proxy returns image/* ($(grep -i '^content-type' "$TMP/img.hdr" | tr -d '\r' | head -1))" grep -Eiq '^content-type: image/' "$TMP/img.hdr"
check "image non-empty" [ -s "$TMP/img.bin" ]
check "image without token = 401, bad id = 400, bad width = 400" [ "$(gws - GET "/v1/images/${BBB_ID}")$(gws "$TMP/tok.req" GET /v1/images/zzz)$(gws "$TMP/tok.req" GET "/v1/images/${BBB_ID}?w=99999")" = 401400400 ]
curl -sS --cacert "$S/gateway_tls_cert" -K <({ printf 'header = "Authorization: Bearer '; tr -d '\n' < "$TMP/tok.req"; printf '"\n'; }) -H 'Range: bytes=0-99' -D "$TMP/st.hdr" -o "$TMP/st.bin" "$GW/v1/stream/${BBB_ID}"
check "stream Range bytes=0-99 = 206 with 100 bytes ($(head -1 "$TMP/st.hdr" | tr -d '\r'))" [ "$(head -1 "$TMP/st.hdr" | grep -c ' 206')$(wc -c < "$TMP/st.bin")" = 1100 ]
check "stream without token = 401" [ "$(gws - GET "/v1/stream/${BBB_ID}")" = 401 ]
rm -f "$TMP/img.bin" "$TMP/st.bin"

echo "== 5b library scoping is enforced by Jellyfin (user without library access)"
NAME_HID="gwtest-hid-$$"
T_JF_HID="$(mkuser "$NAME_HID")"
curl -fsS -K "$TMP/jf.cfg" "$JF/Users/$T_JF_HID" | jq '.Policy|.EnableAllFolders=false|.EnabledFolders=[]' \
  | curl -fsS -o /dev/null -K "$TMP/jf.cfg" -X POST -H 'Content-Type: application/json' --data @- "$JF/Users/$T_JF_HID/Policy"
mkcode "$NAME_HID" viewer "$TMP/code.hid"
c="$(redeem "$TMP/code.hid" "Hidden Tablet")"; check "restricted user pairs (HTTP $c)" [ "$c" = 200 ]
jq -er '.token' "$TMP/last.json" | tr -d '\n' > "$TMP/tok.hid"
T_DEVICES="$T_DEVICES $(jq -er '.deviceId' "$TMP/last.json")"
check "restricted user: library lacks Big Buck Bunny (and is empty)" [ "$(gwb "$TMP/tok.hid" GET '/v1/library?type=movies' | jq -r '[.items[]|select(.title=="Big Buck Bunny")]|length')" = 0 ]
check "restricted user: /v1/images/BBB = 404" [ "$(gws "$TMP/tok.hid" GET "/v1/images/${BBB_ID}")" = 404 ]
check "restricted user: /v1/stream/BBB = 404" [ "$(gws "$TMP/tok.hid" GET "/v1/stream/${BBB_ID}")" = 404 ]
check "control: requester still gets BBB image + stream" [ "$(gws "$TMP/tok.req" GET "/v1/images/${BBB_ID}")" = 200 ]
T_SEERR_HID="$(sg "/user?take=100" | jq -r --arg i "$T_JF_HID" '[.results[]|select((.jellyfinUserId//""|gsub("-";""))==$i)][0].id // empty')"
check "restricted user has a Seerr user" [ -n "$T_SEERR_HID" ]
seerr_perm() { sg "/user/$T_SEERR_HID" | jq -r '.permissions'; }
gwx users set-role --user "$NAME_HID" --role admin >/dev/null
check "set-role admin -> Seerr permissions 2 (got $(seerr_perm))" [ "$(seerr_perm)" = 2 ]
gwx users set-role --user "$NAME_HID" --role viewer >/dev/null
check "demote admin->viewer -> Seerr permissions 0 (got $(seerr_perm))" [ "$(seerr_perm)" = 0 ]
check "demoted device now viewer in the gateway" [ "$(gwb "$TMP/tok.hid" GET /v1/me | jq -r '.role')" = viewer ]
gwx users set-role --user "$NAME_HID" --role admin >/dev/null
check "re-promote -> Seerr permissions 2 again" [ "$(seerr_perm)" = 2 ]
gwx users remove "$NAME_HID" >/dev/null
check "users remove -> Seerr permissions 0 (got $(seerr_perm))" [ "$(seerr_perm)" = 0 ]
check "removed user's device token = 401" [ "$(gws "$TMP/tok.hid" GET /v1/me)" = 401 ]

echo "== 6 cleanup of what the test created"
[ -n "$T_RADARR_ID" ] && rg "/movie/$T_RADARR_ID" >/dev/null 2>&1 && curl -fsS -o /dev/null -K "$TMP/radarr.cfg" -X DELETE "http://127.0.0.1:${RADARR_PORT}/api/v3/movie/${T_RADARR_ID}?deleteFiles=false&addImportExclusion=false"
T_RADARR_ID=""
check "test movie removed from Radarr (files untouched)" [ "$(rg /movie | jq --argjson t "$TMDB" 'map(select(.tmdbId==$t))|length')" = 0 ]
sn DELETE "/request/$T_REQ_ID" >/dev/null; T_REQ_ID=""
[ -n "$T_MEDIA_ID" ] && sn DELETE "/media/$T_MEDIA_ID" >/dev/null; T_MEDIA_ID=""
check "test request removed from Seerr" [ "$(sg "/request?take=100&filter=all" | jq --argjson t "$TMDB" '.results|map(select(.media.tmdbId==$t))|length')" = 0 ]
# viewer never created a request, but the gateway may still have imported its Seerr user
T_SEERR_VIEW="$(sg "/user?take=100" | jq -r --arg i "$T_JF_VIEW" '[.results[]|select((.jellyfinUserId//""|gsub("-";""))==$i)][0].id // empty')"

echo "== 7 secret hygiene"
check "secrets dir mode 700" [ "$(stat -c %a "$S")" = 700 ]
check "secret files mode 600" [ -z "$(find "$S" -maxdepth 1 -type f ! -perm 600)" ]
check "gateway config dir 700 owned $PUID:$PGID" [ "$(stat -c '%a %u:%g' "$CONFIG_ROOT/gateway")" = "700 $PUID:$PGID" ]
check "state files mode 600" [ -z "$(find "$CONFIG_ROOT/gateway" -maxdepth 1 -type f ! -perm 600)" ]
check "state.json exists" [ -s "$CONFIG_ROOT/gateway/state.json" ]
check "state holds only hashes (every tokenHash/hash is 64 hex)" [ "$(jq -r '[.devices[].tokenHash, .codes[].hash]|map(select(test("^[0-9a-f]{64}$")|not))|length' "$CONFIG_ROOT/gateway/state.json")" = 0 ]
# One pattern file (every secret value line + this run's device tokens) against one corpus
# (compose config, inspect + logs of all containers, state file, env file) and the work dir.
# 6-digit pairing codes are not scanned (they collide with timestamps); they are covered
# structurally: only salted hashes in state, fixed log keys.
: > "$TMP/patterns"
for f in "$S"/*; do
  [ -f "$f" ] || continue
  case "$f" in *_user|*.old|*gateway_tls_cert) continue ;; esac
  [ -s "$f" ] || { nope "secret file missing/empty: $(basename "$f")"; continue; }
  grep -v -e '^-----' -e '^$' "$f" >> "$TMP/patterns" || true
  [ "$(tail -c1 "$f" | wc -l)" = 0 ] && echo >> "$TMP/patterns"
done
for f in "$TMP"/tok.*; do [ -s "$f" ] && { cat "$f"; echo; } >> "$TMP/patterns"; done
sed -i '/^$/d' "$TMP/patterns"
{ docker compose --env-file "$ENV" config 2>/dev/null
  for c in $(docker ps -aq); do docker inspect "$c"; docker logs "$c" 2>&1; done
  cat "$CONFIG_ROOT/gateway/state.json" "$ENV"; } > "$TMP/corpus"
npat="$(wc -l < "$TMP/patterns")"
h1="$(grep -cF -f "$TMP/patterns" "$TMP/corpus" || true)"
h2="$(grep -rlF --exclude-dir=.pub-cache --exclude-dir=.dart_tool -f "$TMP/patterns" "$STACK" 2>/dev/null | wc -l || true)"
check "$npat secret/token values: 0 hits in compose config, inspect+logs of all containers, state file, env file ($h1) and work dir ($h2)" [ "$h1$h2" = 00 ]
rm -f "$TMP/corpus" "$TMP/patterns"
check "gateway log lines carry only method/path template/status/latency/device hash" [ "$(docker logs gateway 2>&1 | grep '^{' | jq -c 'keys|join(",")' | sort -u | tr -d '\n')" = '"d,m,ms,p,s,t"' ]

if [ "${RESTART_TEST:-0}" = 1 ]; then
  echo "== 8 restart and rollback -> deploy keep pairings"
  waitgw() { for _ in $(seq 1 24); do [ "$(docker inspect -f '{{.State.Health.Status}}' gateway 2>/dev/null || echo none)" = healthy ] && return 0; sleep 5; done; return 1; }
  docker compose --env-file "$ENV" restart gateway >/dev/null
  check "healthy after restart" waitgw
  check "admin token still works after restart" [ "$(gwb "$TMP/tok.adm" GET /v1/me | jq -r '.role')" = admin ]
  check "requester token still works after restart" [ "$(gwb "$TMP/tok.req" GET /v1/me | jq -r '.role')" = requester ]
  check "certificate fingerprint unchanged after restart" [ "$(gwx fingerprint | tr -d '\r\n')" = "$FP_CLI" ]
  "$HERE/2026-11-03-rollback.sh" >/dev/null
  check "gateway container gone after rollback" [ -z "$(docker ps -aq --filter name='^gateway$')" ]
  "$HERE/2026-11-03-deploy.sh" >/dev/null
  prime_csrf
  check "gateway healthy after deploy" waitgw
  check "admin token still works after rollback->deploy" [ "$(gwb "$TMP/tok.adm" GET /v1/me | jq -r '.role')" = admin ]
  check "requester token still works after rollback->deploy" [ "$(gwb "$TMP/tok.req" GET /v1/me | jq -r '.role')" = requester ]
  check "certificate fingerprint unchanged after deploy" [ "$(gwx fingerprint | tr -d '\r\n')" = "$FP_CLI" ]
fi

echo "== 9 other services still pass (after test objects are removed)"
# remove the temp users now so the other verify scripts see a clean system
for d in $T_DEVICES; do gwx devices revoke "$d" >/dev/null 2>&1 || true; done
c="$(gws "$TMP/tok.req" GET /v1/me)"; check "revoked device token = 401 (got $c)" [ "$c" = 401 ]
T_DEVICES=""
gwx users remove "$T_JF_REQ" >/dev/null; gwx users remove "$T_JF_VIEW" >/dev/null
[ "$ADMIN_PREEXISTED" = 0 ] && gwx users remove "$ADMIN_NAME" >/dev/null
if [ "$ADMIN_PREEXISTED" = 1 ] && [ -n "$ADMIN_ROLE" ]; then
  gwx users set-role --user "$ADMIN_NAME" --role "$ADMIN_ROLE" >/dev/null
  check "pre-existing admin record restored (role $ADMIN_ROLE)" [ "$(gwx users list | awk -v n="$ADMIN_NAME" '$2==n{print $3}' | head -1 | tr -d '\r\n')" = "$ADMIN_ROLE" ]
fi
check "gateway users restored (no test users left)" [ "$(gwx users list | grep -c "gwtest-")" = 0 ]
[ -n "$T_SEERR_REQ" ] && sn DELETE "/user/$T_SEERR_REQ" >/dev/null; T_SEERR_REQ=""
[ -n "$T_SEERR_VIEW" ] && sn DELETE "/user/$T_SEERR_VIEW" >/dev/null; T_SEERR_VIEW=""
[ -n "$T_SEERR_HID" ] && sn DELETE "/user/$T_SEERR_HID" >/dev/null; T_SEERR_HID=""
curl -fsS -o /dev/null -K "$TMP/jf.cfg" -X DELETE "$JF/Users/${T_JF_REQ}"; T_JF_REQ=""
curl -fsS -o /dev/null -K "$TMP/jf.cfg" -X DELETE "$JF/Users/${T_JF_VIEW}"; T_JF_VIEW=""
curl -fsS -o /dev/null -K "$TMP/jf.cfg" -X DELETE "$JF/Users/${T_JF_HID}"; T_JF_HID=""
check "no gwtest-* users left in Jellyfin or Seerr" [ "$(curl -fsS -K "$TMP/jf.cfg" "$JF/Users" | jq '[.[]|select(.Name|startswith("gwtest-"))]|length')$(sg "/user?take=100" | jq '[.results[]|select((.jellyfinUsername//"")|startswith("gwtest-"))]|length')" = 00 ]
rmnew; MOVIES_BEFORE=""
check "media/movies listing unchanged" [ "$(ls -A "$DATA_ROOT/media/movies")" = "$snap" ]
if [ "${RESTART_TEST:-0}" = 1 ]; then
  "$HERE/2026-11-03-verify-jellyfin.sh" > "$TMP/vj.out" 2>&1 && pass "verify-jellyfin PASS" || { nope "verify-jellyfin"; tail -5 "$TMP/vj.out"; }
  RESTART_TEST=1 "$HERE/2026-11-03-verify-arr.sh" > "$TMP/va.out" 2>&1 && pass "verify-arr PASS" || { nope "verify-arr"; tail -5 "$TMP/va.out"; }
  RESTART_TEST=1 "$HERE/2026-11-03-verify-seerr.sh" > "$TMP/vs.out" 2>&1 && pass "verify-seerr PASS" || { nope "verify-seerr"; tail -5 "$TMP/vs.out"; }
fi

[ "$fail" = 0 ] && echo "VERIFY PASS" || { echo "VERIFY FAIL"; exit 1; }
