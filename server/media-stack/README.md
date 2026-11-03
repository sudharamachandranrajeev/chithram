# Chithram media stack

Docker Compose stack for the Chithram media section. Phase 3: Jellyfin.
Phase 5: Prowlarr, Radarr, Sonarr, Lidarr. Later phases add services to
`compose.yaml` on the same `media` network.

## Services (all `127.0.0.1` only)
| Service  | Port (env var)        | Image (linuxserver.io, tag@digest pinned) |
|----------|-----------------------|-------------------------------------------|
| jellyfin | 8096 `JELLYFIN_PORT`  | jellyfin/jellyfin                          |
| prowlarr | 9696 `PROWLARR_PORT`  | lscr.io/linuxserver/prowlarr               |
| radarr   | 7878 `RADARR_PORT`    | lscr.io/linuxserver/radarr                 |
| sonarr   | 8989 `SONARR_PORT`    | lscr.io/linuxserver/sonarr                 |
| lidarr   | 8686 `LIDARR_PORT`    | lscr.io/linuxserver/lidarr                 |

**No download client until the VPN phase.** Nothing in this stack can download:
no qBittorrent, and no indexers.
**The owner adds only authorized indexers in Prowlarr** (UI at
`http://127.0.0.1:9696`, login `chithram-admin`). Prowlarr already syncs
(fullSync) to Radarr, Sonarr and Lidarr, so added indexers propagate.

The *arr containers start as root (s6) and drop to PUID/PGID. Caps: drop ALL,
add back `CHOWN DAC_OVERRIDE SETUID SETGID` (each tested required), plus
`no-new-privileges`. `read_only` is not used: s6 must edit `/etc/passwd` to
apply PUID/PGID.

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
`{prowlarr,radarr,sonarr,lidarr}_api_key`, `arr_ui_user`, `arr_ui_password`.

*arr settings: radarr `/data/media/movies`, sonarr `/data/media/tv`, lidarr
`/data/media/music`; hardlinks on; completed-download handling on; no
automatic removal of completed/failed downloads (owner policy needed first).
Whole `$DATA_ROOT` is mounted at `/data` so downloads and media share one
filesystem (hardlinks).

## Rollback
    scripts/2026-11-03-rollback.sh          # docker compose down, NO -v
Stops all five services; config (incl. *arr databases), cache, media and secrets
are kept. Run deploy again to return (arr-setup is idempotent).
Never use `down -v` or delete `/opt/chithram-media/config`.

## Optional future
GPU transcoding is not configured: WSL transcoding support is unconfirmed.
Add device passthrough only after testing.
