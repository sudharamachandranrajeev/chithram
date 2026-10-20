# Chithram decisions (Opus pass, 2026-10-20; confirmed in the owner interview)

The "Interview answers" section at the end overrides the earlier defaults.

Architecture: Flutter 3.47.7 monorepo `chithram` (pub workspace), CI-only builds like Paattu.
- app/ Flutter app; packages/innertube (pure Dart, seeded by COPYING Paattu app/lib/src/sources/youtube.dart + http.dart);
  packages/iptv (M3U/Xtream/XMLTV parsers); packages/chithram_player (federated PlayerEngine: Android Media3 Kotlin,
  desktop media_kit); native/torrent (Rust cdylib over librqbit, C header, dart:ffi in-process on all platforms).
- Android player: Media3 SurfaceView PlatformView fullscreen (tunneling, HDR, Surface.setFrameRate), Texture for inline
  trailers, MergingMediaSource for YT DASH, media_kit fallback; per-ABI APKs incl armeabi-v7a.
- Desktop: media_kit, `audio-files` for YT DASH.
- YouTube tiers: VISIONOS → android_vr → tv → youtube_explode_dart → (if forced) MIT SABR port from youtubei.js/googlevideo.
  Codec by HW decoders AV1>VP9>H.264, cap at display height, always Range. SponsorBlock/DeArrow/RYD opt-in. No yt-dlp.
- Torrent FFI contract: start(dir, quota, socks5?)→{port,token}; add(magnet|bytes)→{id,files};
  GET /{token}/stream/{id}/{idx} Range; stats; remove. Loopback, 128-bit token, reject non-loopback Host, no CORS/UI,
  media extensions only, LRU quota. In-process avoids Android phantom-process killer.
- Live TV: M3U/Xtream/XMLTV; iptv-org API optional + blocklist; EPG gunzip+xml events in isolate → SQLite batch,
  window -1d..+3d, 12 h ETag refresh; health probe pool 8, 24 h cache; zap via Media3 DefaultPreloadManager N±1.
- Stremio protocol client (user-pasted manifests) in v1.
- Storage: drift SQLite (FTS5); secrets flutter_secure_storage (Linux fallback 0600 file + notice).
- Security: HTTPS everywhere except user stream URLs; warn Xtream creds over http; parser limits; no WebView; no
  telemetry, local crash log; lockfiles, cargo deny, Actions pinned by SHA.
- Updater: GitHub Releases + minisign over SHA256SUMS; PackageInstaller / silent Inno / AppImage replace. Needs public releases.
- CI: copy Paattu ci.yml/release.yml; add native Rust job (cargo-ndk, MSVC, gnu ubuntu-22.04, rust-cache); smoke checks
  torrent /health; weekly scheduled release dry-run to catch Windows breaks.
- Licence: MIT, no GPL linked (no libtorrent_flutter/TorrServer/NewPipeExtractor/LibreTube port). Ship rqbit LICENSE/NOTICE.

Roadmap:
1 Native spikes (Sintel magnet first frame <20 s, seek 50% <10 s, 30 min no kill, RSS <400 MB on 2 GB box, A/V sync,
  D-pad grid + search, CI /health 200).
2 Core + release pipeline (18/20 YT panel ≥1080p on 3 OS, median first frame <2.5 s, v0.1.0 green).
3 Live TV (10k M3U <10 s, 100 MB XMLTV <120 s with p95 frame <16 ms, median zap <1.5 s).
4 OTT shell MVP v0.5 (billboard, rails, details, continue watching, unified search, profiles; adb keyevent reaches all
  screens; rea captures focus visible + 5% overscan; cold start <3 s).
5 Torrent product + hardening + Stremio (nmap clean, 403 w/o token/foreign Host, VPN drop pause <5 s, quota holds).
6 v1 (updater 0.9→1.0 all OS, tampered sig refused, Watch Next row, crash log).

## Interview answers (owner, 2026-10-20): these override the defaults above
- Licence MIT; GitHub repo private until MVP, then public.
- MVP sources: YouTube + IPTV + torrent WITH search. Torrent search = Torznab (Jackett/Prowlarr) + plugin repos,
  including qBittorrent-compatible Python search plugins (nova2 API) on every platform: embed CPython via Chaquopy (MIT) on
  Android, system/bundled Python on desktop; plugins sandboxed (network only, no file access, time/output limits).
  Chithram ships NO indexers/plugins/piracy-site scrapers and does NOT do mirror-domain hopping (declined: court-ordered
  blocks in India). Users add plugin repos / Torznab URLs themselves.
- Dynamic sources: health checks prune dead streams/sources; catalogues + user-added plugin repos refresh in background at
  runtime so new channels/indexers appear without app updates.
- Device priority: Android TV first (D-pad, 10-ft), then phone, desktop. TV box model not yet named — ask.
- Design: Hotstar-style (left nav rail, hero billboard, rounded tiles), own accent colour, Poppins.
- Torrent: VPN/SOCKS5 required by default (guard can be turned off), seed only while watching, IP-exposure warning.
- IPTV first-run one-tap: iptv-org, Free-TV/IPTV, FAST services via user-pasted URL. User mentioned "tcpbl/tcbpl" as
  inspiration — unidentified, asked for link.
- Profiles: local profiles only (PIN + kids filter OK), no sync; export/import file.
- YouTube: no login; local subscriptions (Takeout/NewPipe import), local feed/history/watch later.
- rea: QA of own builds (ADB captures, logcat, Frida start-delay traces, APK secret audit) + public OTT web design study.
  Never DRM/paid OTT app reversing.
- Metadata: TMDB with user's own free key; filename fallback.
- Defaults set by main session (user didn't object yet): GitHub Releases + Obtainium; Stremio addons v1 user-pasted.
- Model routing per user: Opus decides, Sonnet builds.
