# Chithram research brief (2026-10-20)

Goal (user's words): all-in-one video entertainment system "Chithram"; OTT-inspired design (Netflix/Prime/Hotstar);
plays YouTube, torrent files, IPTV repos, live TV repos; ad-free, short start delay; secure, reliable, efficient;
GitHub repo; Windows app, Android app (phone + TV), Linux program. "Research reverse engineering with rea."
"Use Opus for decision making, Sonnet for build." Interview user before building.

## Owner context
- Ships Paattu (~/Work/paattu): Flutter 3.47.7 music app, Android/Windows/Linux, built ONLY in GitHub Actions
  (no local Flutter/Dart; OpenSnitch firewall prompts on new network binaries). release.yml builds APK, Inno Setup
  installer, AppImage + tarball, with smoke tests (Windows silent install, Android API 34 emulator, Xvfb Linux).
  ~90 Actions minutes per tag. Android signing key kept outside repo; secrets in Actions.
- Paattu has a working Dart YouTube resolver: InnerTube VISIONOS client + visitor data from sw.js_data, direct URLs
  (no cipher/n), fallback youtube_explode_dart; learned GET w/o Range is throttled (pass `Range: bytes=0-`).
- Paattu uses media_kit (libmpv) on desktop, ExoPlayer via just_audio/video_player on Android. Lessons: libmpv soname
  patching for tarball, Windows VS 2026 build breaks only caught on tag runs.
- GitHub account sudharamachandranrajeev, private repos by default, gh CLI ready.

## YouTube
- SABR (UMP, server-driven ABR) being forced on web clients. PO tokens required for android/ios/web/mweb.
- No-PO-token clients (yt-dlp table): tv (DRM w/o cookies, sometimes SABR), web_embedded (embeddable only),
  android_vr (no kids videos; Mar 2026 reports of 360p-only SABR experiment). VISIONOS used by NewPipeExtractor,
  LibreTube (v32 implements SABR+UMP client with VISIONOS + cached content-bound PoTokens), youtubei.js v18.
- yt-dlp: Unlicense, needs Deno JS runtime; desktop sidecar only, slow start. NewPipeExtractor GPL-3 Java (Android only
  via channel). youtube_explode_dart BSD-3 pure Dart. youtubei.js MIT TS (needs JS runtime). Invidious/Piped AGPL servers,
  unreliable public instances. rustypipe GPL-3.
- Ref apps: LibreTube (best SABR ref), NewPipe/Tubular/PipePipe, SmartTube (Android TV; dev env malware incident, new
  signing key), FreeTube, Clipious (Flutter + Invidious), Grayjay (source-first, not OSI).
- 1080p+ = DASH only (separate A/V). ExoPlayer: MergingMediaSource or generated MPD. mpv: --audio-file / local MPD;
  localhost range-chunking proxy against throttling.
- Extras: SponsorBlock, DeArrow, Return YouTube Dislike = plain HTTP APIs.
- Recommendation: shared Dart resolver (VISIONOS → android_vr/tv → youtube_explode); SABR port only if needed.
  Don't bundle yt-dlp. ToS violation (contract), no DRM circumvention for normal YT; no Play Store.

## Torrent
- libtorrent_flutter 2.0.0: GPL-3, young (980 downloads), localhost range server, all platforms.
- TorrServer: GPL-3 Go HTTP stream server, de facto Android TV engine, 2026 maintenance unconfirmed.
- rqbit: Rust, Apache-2.0 (confirm), HTTP `/torrents/{id}/stream/{idx}` with Range + piece priority, SOCKS5,
  tens of MB RAM; Android not documented (Rust NDK cross-compile plausible, unverified).
- anacrolix/torrent: MPL-2.0 Go library, write own HTTP layer. Raw libtorrent BSD-3, heavy FFI work.
- Recommendation: rqbit sidecar (desktop exe; Android NDK build via ProcessBuilder/JNI), one `/stream` URL contract,
  swap engines behind it. Prototype Android first.
- Security: bind 127.0.0.1, random port + per-launch token, disk quota LRU + clear on exit, SOCKS5/VPN bind + kill
  switch, opt-in with IP-exposure warning, play only media extensions, cleartext only for localhost.

## IPTV / Live TV
- iptv-org/iptv (CC0/Unlicense, links only, takedown process); iptv-org/api JSON (channels/streams/guides/blocklist,
  stream referrer + user_agent); iptv-org/epg grabbers → XMLTV. Free-TV/IPTV m3u8 (no license). i.mjh.nz FAST
  aggregators (Pluto/Samsung/Plex/Roku) — ToS risk, don't bundle.
- Xtream Codes API (player_api.php live/vod/series, short EPG, xmltv.php, timeshift catch-up). M3U catchup tags.
- XMLTV 50-100 MB: SAX parse in isolate → SQLite indexed, gzip.
- Health check pool (8-16, TTFB, 0x47 TS sync, 24 h cache, mark dead). Fast zap: single player swap, pre-open N±1,
  mpv low-latency profile + small probe; ExoPlayer small bufferForPlaybackMs + live target offset + chunkless HLS.
- References: Kodi PVR IPTV Simple, Hypnotix, IPTVnator, Open-TV, TiviMate (UX ref: groups, EPG grid, multiview).
- Stremio addon protocol: open JSON/HTTP (manifest, catalog, meta, stream, subtitles); own client possible without
  Stremio code; community addons return infoHash streams → torrent sidecar. Ship no addon URLs.
- Jellyfin/Plex/Emby/DLNA optional later.
- Legal: content-neutral tech; ship no infringing sources/indexers; user supplies sources; disclaimer; GitHub/F-Droid.

## Player / platforms / design
- media_kit: Android supported (mediacodec hwdec), ~18-20 MB/ABI, Amlogic TV box green-frame bug reports;
  desktop strong (ASS, HDR tone-map, odd containers). video_player_android on Media3 but no tunneling/AFR/merging;
  custom thin Media3 plugin needed for TV-grade playback. fvp (mdk) closed-ish binary licence. VLC options weak.
- Recommendation: PlayerEngine interface; Android phone+TV = custom Media3 plugin (MergingMediaSource, tunneling,
  AFR) with media_kit fallback; desktop = media_kit.
- Android TV in Flutter: LEANBACK_LAUNCHER, leanback/touchscreen required=false, 320x180 banner, one APK.
  Watch Next/channels need Kotlin MethodChannel + androidx.tvprovider. `dpad` 3.0.0 package (region focus memory);
  TextField D-pad bug flutter#147772 (workarounds tv_textfield/native_textfield_tv). ~20-30% UI is TV-specific.
  No big Flutter TV streaming apps found; Compose-for-TV tv-material 1.1.0 is Google's path. KMP/Compose MP = rewrite;
  Tauri/Electron no TV; Qt licence friction.
- OTT design: hero billboard w/ muted autoplay trailer, rails, Top-10, continue watching w/ progress, profile picker,
  details page, focus scale 1.05-1.1 + glow, overscan-safe, mini-player, skip intro, dark theme, ≥24sp TV type.
  FOSS refs: Wholphin, Moonfin, Jellyfin Android TV, Findroid, Kodi skins.
- Security/reliability: cleartext only player/sidecar layer, system trust, sidecar sandbox (bubblewrap/Job Object),
  local crash log w/ share (no telemetry), updater = GitHub Releases + signed asset, TV memory caps (1-2 GB boxes).

## rea (reverse engineering) assessment — by main session
rea MCP offers: APK/DEX inspection + resource decode, Dart AOT/Flutter build inspection, web bundle/page/network
capture + screenshots, ADB device control (install, screen capture, logcat), Frida/gdb runtime instrumentation.
Legit uses for Chithram:
1. Design study: capture screenshots/layout/CSS tokens of public OTT web pages (landing, public catalogue) for
   spacing/type/motion reference; study FOSS APKs (SmartTube, LibreTube) — but their source is open, so source wins.
2. Interop study of closed but non-DRM apps (e.g. TiviMate UX flows, Xtream panel quirks) — UX reference only;
   interoperability RE is lawful in many jurisdictions but don't copy code/assets.
3. QA of OUR OWN builds: ADB install on a real Android TV box, screen capture of D-pad focus, logcat crash triage,
   Frida tracing of ExoPlayer start latency; inspect our APK/AppImage for leaked secrets/sizes.
Out of bounds: reversing Netflix/Prime/Hotstar apps or Widevine to extract DRM-protected streams or bypass ads in
paid OTT services (DMCA §1201 / IT Act; also not ethical). Chithram does not touch DRM content.
