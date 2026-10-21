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
- MVP sources: YouTube + IPTV + torrent WITH search. Torrent search = Torznab (user-run indexer managers) + plugin repos,
  including Python search plugins that use the nova2-style API, on every platform: official CPython in an
  `isolatedProcess` service on Android (replaced the earlier Chaquopy plan), system/bundled Python on desktop; plugins
  sandboxed (network only, no file access, time/output limits).
  Chithram ships NO indexers/plugins/piracy-site scrapers and does NOT do mirror-domain hopping (declined: court-ordered
  blocks in India). Users add plugin repos / Torznab URLs themselves.
- Dynamic sources: health checks prune dead streams/sources; catalogues + user-added plugin repos refresh in background at
  runtime so new channels/indexers appear without app updates.
- Device priority: Android TV first (D-pad, 10-ft), then phone, desktop. TV box model not yet named — ask.
- Design: streaming-service style (left nav rail, hero billboard, rounded tiles), own accent colour, Poppins.
- Torrent: VPN/SOCKS5 required by default (guard can be turned off), seed only while watching, IP-exposure warning.
- IPTV first-run one-tap: iptv-org, Free-TV/IPTV, FAST services via user-pasted URL.
- Profiles: local profiles only (PIN + kids filter OK), no sync; export/import file.
- YouTube: no login; local subscriptions (Takeout/NewPipe import), local feed/history/watch later.
- rea: QA of own builds (ADB captures, logcat, Frida start-delay traces, APK secret audit) + public OTT web design study.
  Never DRM/paid OTT app reversing.
- Metadata: TMDB with user's own free key; filename fallback.
- Defaults set by main session (user didn't object yet): GitHub Releases + Obtainium; Stremio addons v1 user-pasted.
- Model routing per user: Opus decides, Sonnet builds.

## 0.2.0 "First light" (architect decisions, 2026-10-21)

Full plan: [roadmap.md](roadmap.md). Decisions that bind every later version:
- State: no package. Services are `ChangeNotifier` / `ValueListenable` objects in one `AppServices` object, read through
  an `AppServicesScope` inherited widget; widget tests pass fakes. From 0.3.0 the UI also uses drift `watch()` streams.
- Routing: imperative Navigator. Sections are roots inside `Shell`; drill-downs are pushed routes with their own
  `FocusScope` and `Overscan`. A global `navigatorKey` in `AppServices` lets incoming transfers show prompts.
- One intake path: typed, pasted and received text all go through `classify()` then `handleIntake()`. It confirms
  first and routes to a handler screen; nothing auto-plays.
- Stable item ids, prefixed by source: `yt:`, `ytc:`, `iptv:`, `src:`, `bt:<btih>/<file>`, `url:<sha256[0:16]>`, later
  `file:` and `addon:`. One item table keyed by id from 0.3.0.
- Persistence: JSON files (`JsonFileIptvStore`, `prefs.json`, `resume.json`, written atomically) until 0.3.0 brings one
  drift database that imports them. Generated files are committed, with a CI freshness job.
- Player contract: every source produces a `PlayRequest`; its `resolve()` returns a `MediaSpec`. One player route serves
  all sources. DRM-protected streams fail with a clear message and are never handled.
- Logging: `core/redact.dart` reduces URLs to their host. Tokens, passwords and query strings are never logged.
- Public text: only YouTube, LocalSend, iptv-org, Free-TV and open format or protocol names. The addon client is
  called "Addons".
- Owner decision (overrides the earlier "no built-in URLs" idea): iptv-org and Free-TV stay as opt-in first-run
  suggestions. Nothing loads until the user taps one, `CatalogueEndpoints`, `Source.iptvOrg` and `Source.freeTv` stay,
  and the iptv-org blocklist stays mandatory.
- Fixed in the prep step: `chithram_player` is an app dependency again (Android plugin registration follows the app's
  declared dependencies; a missing one broke the player spike on main), and `depend_on_referenced_packages` is an
  analyzer error. Artifact retention is 2 days everywhere.
- New dependencies: `path_provider`, `package_info_plus`, `crypto` (app); `basic_utils` (LocalSend certificate).
  `targetSdk` is pinned to 36.
