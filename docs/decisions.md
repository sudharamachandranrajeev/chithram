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

## 0.3.0 "Media Home" (architect decisions, 2026-10-21; owner answers 2026-10-21)

Full plan in the project notes; what binds later versions:
- Version order: 0.3.0 Media Home + Find, 0.4.0 Library + VPN guard v2, 0.5.0 Live TV proper, 0.6.0 Player, 0.7.0
  Sources depth, 0.8.0 Household, 0.9.0 v1 candidate, 1.0.0.
- drift lands in 0.3.0 with schema v1 only: `http_cache`, `plugin_repos`, `plugins`, `torznab_endpoints`,
  `provider_runs`. Later versions add tables by migration (v2 Library, v3 IPTV and EPG with FTS5, v4 YouTube
  subscriptions). Each version's prep PR adds its tables and registers empty DAOs; work packages only write queries in
  their own DAO files and never run code generation. Generated `.g.dart` files, the schema dump (`app/drift_schemas`)
  and the migration test helpers (`app/test/data/generated`) are committed; the `codegen` job in `ci.yml` checks them.
- SecretStore (`flutter_secure_storage`) holds the TMDB key and Torznab API keys. On Linux without a keyring it falls
  back to a `secrets.json` created with mode 0600 and Settings shows a notice. Off Linux a keyring failure is an error,
  never a plaintext file.
- Startup: before the first frame the app reads only `prefs.json` and `home_snapshot.json`. The database, SecretStore,
  plugins, the torrent engine, LocalSend and every network request start after the first frame.
- Metadata ids: `tmdb:movie:<id>`, `tmdb:tv:<id>`, `tmdb:tv:<id>/s<n>e<m>`. They are not playable; Play goes through Find.
- Naming: "TMDB" appears only where its terms require attribution (Settings > Metadata, About, the Home setup card, the
  details page footer). "qBittorrent-compatible" may be used as a compatibility statement only (owner, 2026-10-21);
  otherwise public text says "search plugins (nova3 format)".
- TMDB data rules: only the user's own key; `include_adult=false` until 0.8.0; the cache hard-expires after 180 days;
  removing the key purges the cache, the snapshot and the image cache; repository fixtures are synthetic ("Fixture
  Film 1"), never real TMDB content.
- TMDB logo: `app/assets/attribution/tmdb_logo.png` is TMDB's trademark, not MIT. The owner approved committing it with
  the NOTICE entry stating its separate terms. It is used only for attribution, less prominent than Chithram's own name.
- Network etiquette for every background fetcher: token bucket, exponential backoff with +-20% jitter capped at 6 h,
  `Retry-After` honoured, conditional requests when the server sends validators; nothing on the startup critical path.
- Hero tags are scoped to their rail (`'<railId>/<itemId>'`).
- Home is YouTube (owner, 2026-10-24). Popular rails come from YouTube's topic channels (Music, Live, Sports, News,
  Gaming) for the device's region, since YouTube dropped its trending list. Suggestions are learnt on the device only
  (`youtube_taste.json`): each play adds a reward (finished +1, a third +0.5, left within 30 s -0.5) to the channel,
  the title words and the Home rail it came from, with a 30-day half-life. "Recommended for you" ranks the related
  lists of liked plays, new uploads of top channels and popular videos by that profile, at most two per channel.
  Fetched lists live in the cache directory (`youtube_feed.json`, popular 3 h, related 3 days, uploads 6 h). Fetches
  happen only when Home opens, after a play and on pull to refresh; a failure keeps the old lists and is not retried
  on a timer. TMDB rails join Home below the YouTube ones when their work lands.
- Text from the phone: while a field opened with `askText(..., acceptFromPhone: true)` is up, accepted LocalSend text goes
  into it (`ReceiveService.routeTextTo`) instead of the intake path.
- UI folders: `ui/tv/` (D-pad widgets, TV shell and Home), `ui/phone/` (phone shell and widgets), `ui/common/` (shared
  pages, form factor, dims, keys). Feature pages stay in `features/*`; phone views live in `features/*/phone/`.
- Performance is the eighth test layer: `perf.yml` runs a release x86_64 APK on the TV emulator and reports cold start,
  scroll frames, PSS and requests before the first frame against `.github/perf-budget.json` (report mode first).
  `.github/perf-device.sh` is for the owner's phone and TV box. The CI emulator renders in software, so raster time is
  report-only there.
- The plugin Python runtime is bundled on every platform (Linux, Windows; Android already ships CPython for arm64-v8a
  and x86_64). armeabi-v7a: python.org publishes no armv7 Android build; plugins stay off there with a clear reason
  unless CI can build one.

## Telegram receiver (owner, 2026-10-24)
- Reverses "leave Telegram out": the user's own account through TDLib. "Telegram" may appear in UI, docs and the
  changelog as a compatibility statement, like LocalSend.
- Only Saved Messages (chat id equal to the own user id) is read: no chat list, no channels. A video, audio or
  document (mime video/* or audio/*, or a known media extension) that arrives while signed in and running is downloaded
  (priority 32) and auto-played when the app is in front and the player is idle; otherwise the Receive prompt asks
  ("New from Telegram"). Messages TDLib replays from before the app started, and the last 20 on start, are only listed.
  This is the one exception to "nothing auto-plays".
- `packages/tdlib`: own FFI over `td_json_client` (`td_create_client_id`, `td_send`, `td_execute`; `td_receive` loops in
  its own isolate). `TelegramClient` is the interface (`TdClient` over a `TdTransport`, `FakeTelegramClient` for tests);
  there is no live Telegram in CI.
- libtdjson is built by `tdlib.yml` (workflow_dispatch) from a pinned upstream commit, published as the assets of the
  `tdlib-<version>` release, and pinned by sha256 in `packages/tdlib/tool/tdlib.lock.json`. `fetch_tdlib.py` downloads and
  verifies it for ci/e2e/release builds; a platform with no pin builds without TDLib and Telegram says so.
- The app id and hash are `--dart-define` from the repo secrets `CHITHRAM_TG_API_ID` / `CHITHRAM_TG_API_HASH`; never
  committed. Without them the build says "This build has no Telegram app id".
- Play while downloading: a loopback HTTP server (127.0.0.1, random port, per-run token in the path) serves
  `/<token>/tg/<fileId>/<name>` with Range. It moves TDLib's download to the requested offset when that is outside what is
  being fetched (more than 4 MB past the frontier), waits on `updateFile`, then `readFilePart`.
- TDLib database and files live in `<support>/telegram/`; the database key is random, kept in the secret store.
  Retention: 7 days or 4 GB total, oldest first, via `deleteFile` (`planCleanup`). Sign out calls `logOut` and deletes the
  directory.

- Torrent Home ranks what the user's own sources list: Torznab endpoints (latest in Movies 2000 and TV 5000, limit 100, no
  query) and, through `PopularSource`, search plugins (query = current year). Merged by infohash (else normalised title
  plus size), adult dropped (Torznab 6000-6999 at the parser, plus obvious words), ranked by seeders; items with no
  seeders are left out. Windows are cumulative (24 h, 7 d, 30 d); items with no date appear only in "Most seeded".
  Cache `torrent_home.json` in the cache dir, per-window TTLs 3 h / 12 h / 24 h, everything stale when the set of
  sources changes. No timers.
- Torznab traffic: a host on the user's network is reached directly; a public host needs HTTPS and goes through the
  nova HTTP broker and the SOCKS5 proxy when the torrent network choice is SOCKS5. One request per 2 s per endpoint,
  backoff 30 s doubling to 6 h with +-20% jitter, 429 Retry-After honoured. Errors never carry the address (it holds
  the key). No conditional requests: Torznab answers carry no useful validators and callers cache for hours.
- Select on a Torrent Home tile plays without asking only when the torrent has one video or one at least three times
  larger than the next; a pack opens the file list.
