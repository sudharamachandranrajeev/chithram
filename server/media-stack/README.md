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

## Rollback
    scripts/2026-11-03-rollback.sh          # docker compose down, NO -v
Stops all six services (Seerr's SQLite DB and settings stay in `$CONFIG_ROOT/seerr`); config (incl. *arr databases), cache, media and secrets
are kept. Run deploy again to return (arr-setup is idempotent).
Never use `down -v` or delete `/opt/chithram-media/config`.

## Optional future
GPU transcoding is not configured: WSL transcoding support is unconfirmed.
Add device passthrough only after testing.
