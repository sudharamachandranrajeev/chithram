# Chithram media stack

Docker Compose stack for the Chithram media section. Phase 3: Jellyfin.
Phase 5: Prowlarr, Radarr, Sonarr, Lidarr. Phase 6: Seerr (requests). Later phases add services to
`compose.yaml` on the same `media` network.

## Services (all `127.0.0.1` only)
| Service  | Port (env var)        | Image (linuxserver.io, tag@digest pinned) |
|----------|-----------------------|-------------------------------------------|
| jellyfin | 8096 `JELLYFIN_PORT`  | jellyfin/jellyfin                          |
| prowlarr | 9696 `PROWLARR_PORT`  | lscr.io/linuxserver/prowlarr               |
| radarr   | 7878 `RADARR_PORT`    | lscr.io/linuxserver/radarr                 |
| sonarr   | 8989 `SONARR_PORT`    | lscr.io/linuxserver/sonarr                 |
| lidarr   | 8686 `LIDARR_PORT`    | lscr.io/linuxserver/lidarr                 |
| seerr    | 5055 `SEERR_PORT`     | ghcr.io/seerr-team/seerr (v3.5.1)          |
| gateway  | 8443 `GATEWAY_PORT`   | built locally from `gateway/` (HTTPS)      |

**No download client until the VPN phase.** Nothing in this stack can download:
no qBittorrent, and no indexers.
**The owner adds only authorized indexers in Prowlarr** (UI at
`http://127.0.0.1:9696`, login `chithram-admin`). Prowlarr already syncs
(fullSync) to Radarr, Sonarr and Lidarr, so added indexers propagate.

The *arr containers start as root (s6) and drop to PUID/PGID. Caps: drop ALL,
add back `CHOWN DAC_OVERRIDE SETUID SETGID` (each tested required), plus
`no-new-privileges`. `read_only` is not used: s6 must edit `/etc/passwd` to
apply PUID/PGID.

Seerr: `cap_drop: ALL` with nothing added back, `no-new-privileges`, `read_only`
root fs (tmpfs `/tmp`), runs as `PUID:PGID`, only mount is `$CONFIG_ROOT/seerr`
(700) at `/app/config`; no `/data`. Memory `SEERR_MEM` (default 1g), pids 512.
The image has no curl, so the healthcheck uses busybox `wget` on `/api/v1/status`.

## Prerequisites
- Linux with Docker (tested: WSL2), Docker 29+ with Compose v2, `curl`, `jq`, `openssl`.
- `/data/{downloads,media}/{movies,tv,music}` on one ext4 filesystem, owned `media:media`, mode 2775.
- `/opt/chithram-media/{config,secrets}` (secrets dir mode 700).
- Env file `/opt/chithram-media/media-stack.env`: `cp .env.example` there, `chmod 600`.

## Laptop-only binding
Every published port binds to `BIND_IP=127.0.0.1`. Jellyfin is never reachable
from the LAN. Remote access is also disabled inside Jellyfin. No DLNA, no host
networking. Jellyfin mounts media read-only and runs as 1000:1000 with all
capabilities dropped, read-only root fs and `no-new-privileges`.

Prowlarr/Radarr/Sonarr/Lidarr: `cap_drop: ALL` then add back only
`CHOWN DAC_OVERRIDE SETUID SETGID`, plus `no-new-privileges`. The root fs is
writable because s6 edits `/etc/passwd` to apply PUID/PGID; the apps themselves
run as PUID:PGID. Lidarr root folder defaults are monitor `none` (nothing is
monitored automatically) until the owner sets a policy.

## Run
    scripts/2026-11-03-deploy.sh            # preflight + up -d + health wait
    scripts/2026-11-03-jellyfin-setup.sh    # first run: admin, API key, libraries
    scripts/2026-11-03-verify-jellyfin.sh   # checks; non-zero on failure

    scripts/2026-11-03-verify-arr.sh        # arr checks; RESTART_TEST=1 adds restart recovery

`deploy.sh` also runs `arr-setup.sh prepare` before start (API keys written to
each `config.xml`, never into env) and `arr-setup.sh configure` after health
(UI login, root folders, naming, hardlinks, Jellyfin connection, Prowlarr apps).

Secrets (generated once, never printed) live in `$SECRETS_ROOT`:
`jellyfin_admin_user`, `jellyfin_admin_password`, `jellyfin_api_key`,
`{prowlarr,radarr,sonarr,lidarr}_api_key`, `arr_ui_user`, `arr_ui_password`,
`seerr_api_key` (adopted from Seerr's `settings.json`, never regenerated).

*arr settings: radarr `/data/media/movies`, sonarr `/data/media/tv`, lidarr
`/data/media/music`; hardlinks on; completed-download handling on; no
automatic removal of completed/failed downloads (owner policy needed first).
Whole `$DATA_ROOT` is mounted at `/data` so downloads and media share one
filesystem (hardlinks).

## Requests (Seerr, `http://127.0.0.1:5055`)
`scripts/2026-11-03-seerr-setup.sh` (run by `deploy.sh` after health, idempotent)
initializes Seerr through its API, no browser wizard: Jellyfin
(`http://jellyfin:8096`, signed in as the Jellyfin admin from secrets, who becomes
the Seerr owner/admin), Movies+TV libraries enabled and synced (Music stays
disabled), Radarr (`http://radarr:7878`, root `/data/media/movies`, default
profile "Any", default server, 4K off, `syncEnabled` false, `preventSearch`
false) and Sonarr (`http://sonarr:8989`, root `/data/media/tv`, season folders on).
Other settings: `applicationUrl` empty, hide-available off, partial requests off,
local email/password login off (sign-in is Jellyfin only), version check off,
CSRF protection on (one container restart the first time, as Seerr reads it at
start). **Lidarr is not connected: Seerr has no music support.** Music requests
come later through the gateway.

CSRF note for API clients (gateway, scripts): with `csrfProtection` on, every
POST/PUT/DELETE needs the `_csrf` cookie plus the `XSRF-TOKEN` cookie value in an
`X-XSRF-TOKEN` header. GET `/api/v1/status` first to receive both cookies.
API-key calls (`X-Api-Key`) act as the owner; `X-Api-User: <id>` acts as that user.

### Roles and permission bits
Identity comes from Jellyfin users. Approval, acquisition and availability are
separate states. New Jellyfin users cannot sign in to Seerr by themselves
(`newPlexLogin=false`); an admin imports them
(`POST /api/v1/user/import-from-jellyfin {"jellyfinUserIds":[...]}`) and they get
the default permissions.

| Role      | Seerr `permissions` | Bits                                   |
|-----------|---------------------|----------------------------------------|
| admin     | `2`                 | `ADMIN` (the Jellyfin admin, user id 1)|
| requester | `32`                | `REQUEST` (movies and TV)              |
| viewer    | `0`                 | no request permission                  |

`defaultPermissions` = `32`. Requesters have NO `AUTO_APPROVE` (128), `AUTO_APPROVE_MOVIE`
(256), `AUTO_APPROVE_TV` (512) and no `MANAGE_REQUESTS` (16), so requests wait for
an admin. Other relevant bits: `REQUEST_MOVIE` 262144, `REQUEST_TV` 524288,
`REQUEST_VIEW` 16384, `REQUEST_4K` 1024. The Phase 7 gateway maps roles onto
`permissions` via `PUT /api/v1/user/{id}` `{"permissions": N}`.

### Request states
Seerr request status: 1 `PENDING` (waiting for an admin), 2 `APPROVED` (sent to
Radarr/Sonarr), 3 `DECLINED`. Media status: 1 unknown, 2 pending, 3 processing
(approved, not yet acquired), 4 partially available, 5 available. Approval does not
download anything and does not make media available: with no download client and
no indexers, an approved request stays at media status 3.
`scripts/2026-11-03-verify-seerr.sh` proves this with a temporary Jellyfin user
and the public-domain film "Night of the Living Dead" (TMDB 10331); it removes
exactly what it created.

    scripts/2026-11-03-verify-seerr.sh      # RESTART_TEST=1 adds restart recovery

## Rotating an *arr API key
    scripts/2026-11-03-rotate-key.sh radarr|sonarr|lidarr|prowlarr
Keeps the old key as `$SECRETS_ROOT/<app>_api_key.old` (600), stops the app,
writes a new key into `config.xml` and the secret file, restarts, re-runs
`arr-setup.sh configure` (Prowlarr links) and, for radarr/sonarr, `seerr-setup.sh`
(Seerr server entry), then checks old key = 401, new key = 200, scans
`/opt/chithram-media` and `/home/media/work` for the old key, and runs
verify-arr and verify-seerr. **The owner deletes the `.old` file after confirming**;
the script refuses to rotate again while one exists. Keys never appear in argv, env
or output.

## Gateway (Phase 7a, `https://127.0.0.1:8443`)
A small Dart server (`gateway/`, AOT binary in a distroless image) is the only thing the
Chithram app talks to. It holds every service key (Jellyfin, Seerr, Radarr, Sonarr) as file
secrets under `/run/secrets`; the app never sees them. Container: user 1000:1000, `cap_drop: ALL`,
`read_only`, `no-new-privileges`, pids 128, mem `GATEWAY_MEM` (256m), mount `$CONFIG_ROOT/gateway`
(700) at `/state`. Build is a multi-stage Dockerfile (base images pinned by digest) that fails if
`dart analyze` or `dart test` fail. Healthcheck: `/app/gateway healthcheck` (no shell in the image).

**TLS.** `scripts/2026-11-03-gateway-setup.sh` (run by `deploy.sh`) generates a self-signed ECDSA
P-256 cert once into `$SECRETS_ROOT/gateway_tls_{cert,key}` (600). The app pins the SHA-256
fingerprint: `docker compose exec gateway /app/gateway fingerprint`.

**Admin commands** (`docker compose --env-file /opt/chithram-media/media-stack.env exec gateway /app/gateway ...`):

    pair --user <jellyfinUser> --role <requester|viewer|admin>   # prints a 6-digit code ONCE
    users list | users set-role --user U --role R | users remove <user|id>
    devices list | devices revoke <deviceId>
    fingerprint

A code is single use, valid 10 minutes, invalidated after 5 wrong attempts; globally 20 pairing
attempts/minute (429). `pair` sets the user's role; roles map onto Seerr permissions
admin=2, requester=32, viewer=0 (synced at pair time and on first request). The app does
`POST /v1/pair {code, deviceName}` and gets a 256-bit device token **once**; the gateway stores only its
SHA-256 in `$CONFIG_ROOT/gateway/state.json` (600), as it does for codes (salted).

**Identity and auth decision.** Identity = the Jellyfin user. The gateway never stores user
passwords and never hands the app any Jellyfin credential. Jellyfin's API cannot mint a per-user
token without that user's password (or Quick Connect), so the gateway uses its admin key
server-side, always scoped to the paired user (`/Users/{id}/Items...`; an item is served only if
`/Users/{id}/Items/{itemId}` returns it). Playback is therefore proxied: `GET /v1/stream/{itemId}`
direct-plays the file (Range supported, no transcoding) and `GET /v1/images/{itemId}?w=` proxies
posters, both behind the bearer token. Transcoding/HLS is left for Phase 7b.

**API v1** (JSON, `Authorization: Bearer <token>`, bodies <= 4 KB, no CORS):

| Endpoint | Role | Notes |
|---|---|---|
| `GET /healthz` | none | liveness only |
| `POST /v1/pair` | none | `{code, deviceName}` |
| `GET /v1/me` | any | `{user, role}` |
| `GET /v1/search?q=` | any | movies+TV via Seerr/TMDB, each with `mediaStatus` |
| `POST /v1/requests` | requester, admin | `{tmdbId, type: movie or tv}`; made AS the user in Seerr; viewer 403; 409 if duplicate |
| `GET /v1/requests?cursor=` | any | own requests (admin: all) |
| `POST /v1/requests/{id}/approve or decline` | admin | |
| `GET /v1/downloads` | admin | Radarr/Sonarr queue; empty with no download client |
| `GET /v1/library?type=movies, tv or music, cursor=` | any | the user's Jellyfin view, 50 per page |
| `GET /v1/images/{itemId}?w=` | any | image proxy, w 64..1280 |
| `GET /v1/stream/{itemId}` | any | direct-play proxy with Range |

**Status mapping** (`approval`, `acquisition` and `availability` stay distinct):

| Seerr request | Seerr media | Radarr/Sonarr | App status |
|---|---|---|---|
| none | 1 unknown / 7 deleted | | `none` |
| none | 2 pending | | `requested` |
| 1 pending | any (not 4/5) | | `awaitingApproval` |
| 2 approved | not 4/5 | nothing active | `approved` |
| 2 approved | not 4/5 | search command queued/started | `searching` |
| 2 approved | not 4/5 | in queue, downloading | `downloading` |
| 2 approved | not 4/5 | in queue, import pending/importing | `importing` |
| any | 4 partial / 5 available (or request 5 completed) | | `available` |
| 3 declined, 4 failed, or media 6 blocklisted | not 4/5 | | `failed` |

**Hardening and accepted limits.**
- Role changes are all-or-nothing: `pair` and `users set-role` roll the gateway state back and exit 1 if the
  Seerr permission sync fails. `users remove` first sets the user's Seerr permissions to 0 (the Seerr
  owner, id 1, cannot be demoted; the command says so), then drops the role, codes and devices; if
  Seerr is unreachable nothing changes and it can be repeated. Reason: a user removed or demoted
  only in the gateway could still sign in to Seerr directly with the old permissions.
- Fail closed: if Jellyfin cannot be reached the gateway answers 503 (never trusts the token).
  Allow decisions (user active, item visible) are cached at most 10 s. Role, revoke and remove
  changes take effect on the very next request because state is read per request.
- Search: 30 per minute per device (429), at most 8 Seerr detail lookups per search.
  Upstream redirects are never followed. Files need chmod 600 or the gateway refuses to write.
- Library scoping relies on Jellyfin enforcing per-user visibility with the admin key; verify-gateway
  proves it with a user that has no library access (library empty, image and stream 404).
- Accepted: a local process that can reach the port can burn pairing attempts and lock out codes
  (DoS only; the admin re-issues a code). A stream already in flight keeps running after a device
  is revoked or a user removed (new requests fail at once); streams end when the file ends.

Logs are one JSON line per request: time, method, path template (ids replaced), status, latency,
and an 8-char hash prefix of the device id. Never tokens, codes, keys, query strings or bodies.
After `rotate-key.sh` for radarr/sonarr the script recreates the gateway (file secrets are
bind-mounted by inode). `scripts/2026-11-03-verify-gateway.sh` (`RESTART_TEST=1` for restart and
rollback->deploy) proves all of it and removes exactly what it created.

## Rollback
    scripts/2026-11-03-rollback.sh          # docker compose down, NO -v
Stops all seven services (the gateway's pairings stay in `$CONFIG_ROOT/gateway`; Seerr's SQLite DB and settings stay in `$CONFIG_ROOT/seerr`); config (incl. *arr databases), cache, media and secrets
are kept. Run deploy again to return (arr-setup is idempotent).
Never use `down -v` or delete `/opt/chithram-media/config`.

## Optional future
GPU transcoding is not configured: WSL transcoding support is unconfirmed.
Add device passthrough only after testing.
