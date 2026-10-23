# Roadmap, 0.2.0 to 1.0.0

Each version is one short serial prep PR (interfaces, stubs, dependencies, wiring), merged first, then up to five
parallel work packages that own disjoint paths. After the packages merge, the changelog, the decisions addendum and the
lockfile are updated and the tag is pushed. Releases before 1.0 are prereleases.

Cross-version decisions are in [decisions.md](decisions.md) (0.2.0 section). Every user-supplied link goes through one
intake path; every source produces a `PlayRequest`; item ids are stable and prefixed by source.

**Owner decision (IPTV first run).** iptv-org and Free-TV are offered as opt-in suggestions on first run. Nothing loads
until the user taps one. The iptv-org blocklist is mandatory. Chithram still ships no playlist, indexer, plugin or addon
URL beyond those two suggestions.

## 0.2.0 First light

From inside the TV shell: watch a YouTube video, a channel from a playlist you added, and a torrent from a magnet you
pasted. Links can be sent from a phone through LocalSend. Resume works.

- Prep: re-register the Android player plugin, lint as error, artifact retention, service and interface stubs, end-to-end
  harness (Linux under Xvfb and an Android TV emulator, against local fixtures, no real network).
- Work packages: player route and on-screen display; YouTube search and playback; Live TV (M3U sources, groups, channel
  zapping); torrents (magnet, file list, network-choice guard); LocalSend receive.
- Out of scope: database, history UI, favourites, playlists, programme guide, Xtream, secure storage, subtitles and track
  pickers, background audio, Android intents, plugins, addons, profiles, updater.

## 0.3.0 Media Home + Find

With their own TMDB key, a user opens to a populated Home from cache (Featured hero, film and TV rails, genres, language
rails), browses details with cast, seasons, episodes and trailers, and presses Find sources. Find searches the search
plugins (nova3 format), Torznab endpoints, YouTube and IPTV playlists they added, ranks and deduplicates the results,
and plays the best one. Plugins and Torznab endpoints are managed in the app with health status.

- Prep (`feat/home-core`): the drift database (HTTP cache, plugins, Torznab, provider health), SecretStore, the TMDB,
  media_names and torznab package skeletons, the interfaces and fakes the work packages build against, the
  performance harness, and the UI folders (`ui/tv`, `ui/phone`, `ui/common`).
- Work packages: TMDB catalogue and Home data; image cache and Home engine; Home and details UI; plugins and Torznab;
  Find sources.
- Out of scope: Library features, accounts and profiles, adult content, Addons, person pages, OS background jobs,
  automatic plugin updates. No built-in plugin, repository, Torznab endpoint or TMDB key.

## 0.4.0 Library + VPN guard v2

Favourites, watch later, playlists, history with Continue watching, an Up Next queue with radio and next episode, across
every source including TMDB titles (`items.meta_id` links a played item to its `tmdb:` id). Search history. VPN guard v2
and network hardening. The spike pages and their workflows are removed.

## 0.5.0 Live TV proper

Xtream live sources; XMLTV programme guide with now/next and a guide grid; catch-up; sports rail; preloading neighbouring
channels for fast zapping; channel number entry; health probes with hide-dead; source management. IPTV moves into the
database with full-text search.

## 0.6.0 Player

Audio, subtitle and quality selection remembered per series; external subtitles; speed; aspect and zoom; sleep timer;
stats; keyboard shortcuts and gestures; skip intro and credits; opt-in community segment skipping for YouTube;
background audio, picture-in-picture and a desktop mini player; frame-rate matching and HDR on Android TV.

## 0.7.0 Sources depth

YouTube local subscriptions and feed, captions, chapters, search filters; torrent library features (open `.torrent`,
season packs, subtitles inside the torrent); Android and desktop link intake; local media folders; Xtream VOD and series.

## 0.8.0 Household

Local profiles with PIN, kids profiles with allow-lists and a content gate, an age-gated adult category (off by default),
on-device recommendations, the Addons client, full export and import, and polish. No sync, no accounts.

## 0.9.0 v1 candidate

Signed in-app updater (minisign over a checksum file) for all platforms; Android TV Watch Next row; local crash log
with no telemetry; hardening (fuzzing the LocalSend server, parser limits, firewall rule in the Windows installer, a
licences page, a user guide).

## 1.0.0

Stabilization only. Update from 0.9.x to 1.0.0 through the in-app updater on every platform; re-check the performance
budgets on real TV hardware (cold start under 3 s, YouTube median first frame under 2.5 s, zap under 1.5 s, torrent first
frame under 20 s, memory under 400 MB). The owner signs off before tagging.

Excluded from 1.0: recording, multiview, casting, network shares, online subtitle search, YouTube login and downloads,
account sync, and any built-in sources.
