# Changelog

Release notes are taken from the section of the version being tagged.

## 0.3.0 (in progress)

### Changed
- TV fit: everything is about a quarter smaller on a 1080p TV (it lays out at 960x540): text floor 18 instead of 24,
  tiles at their base size, a narrower nav rail and tighter pages, so Home, Settings and dialogs fit one screen.
  Telegram sign-in shows a smaller QR code beside its steps, and the phone-number view has a way back to the QR code.
- The drop-down keyboard is smaller (32 dp keys, narrower panel) and its suggestions sit in rows under the keys,
  labelled by source: YouTube suggestions, and on Search also matching Live TV channels. Text-entry dialogs (links,
  magnets, PINs, keys, phone numbers) now open compact and drop the same keyboard down only when you select the field.

### Added
- Websites (TV rail; on phones the globe in the top bar): add a site by its link and Chithram reads its pages for
  video and plays it in its own player. Pages are read as text and never run, so the site's ads, pop-ups and scripts
  never load; video found in embedded players is followed two frames deep with the right Referer; links that look like
  ads are left out; HLS streams pass through a loopback filter that cuts ad breaks (cue-out/cue-in, SCTE-35 ranges,
  interstitials, ad-host segments, short stitched-in runs from another host). Pages built entirely by scripts cannot be
  read. Shared or pasted web page links offer "Find video on page".
- Themes: Settings > Theme (TV and phone) picks one of seven dark looks (Chithram, Ocean, Emerald, Rose, Violet, Sunset,
  Graphite), an AMOLED black background for any look, or a custom accent from a 16-colour grid; text on the accent turns
  black or white automatically. Changes fade in at once and are kept. On phones the status and navigation bars follow.
- Foundations for Media Home: a local database (HTTP cache, plugins, Torznab, provider health), secret storage for
  API keys, skeletons of the TMDB, release-name and Torznab packages, and the home, catalogue and Find interfaces with
  fakes. Settings gains Metadata, Search plugins, Torznab and Image cache sections (placeholders until their work lands).
- "Find sources for ..." on the Search page, a first listing of provider results.
- Text sent from a phone can fill the open text field (used for API keys and long tokens).
- A performance run on the TV emulator (`perf.yml`, report mode).
- Home is YouTube: a billboard and rails of what is popular now in the device's region (music, live, sports, news,
  gaming, from YouTube's own topic channels). As you watch and search, Chithram learns on the device and adds
  Continue watching, Recommended for you and Because you watched. Finished videos raise their channel and title words,
  videos left within half a minute lower them, and old interest fades over a month. Lists are cached, so Home opens
  with the last ones; pull down on a phone to refresh. Settings can clear the watch history.
- Telegram receiver: sign in with your own Telegram account (QR code first, phone number and code as the
  fallback, two-step password supported) and any video or audio file you send or forward to your Saved Messages
  is downloaded and starts playing while it downloads (seeking works). If something is already playing, you
  are asked first. Files are kept for 7 days or up to 4 GB; "Clear Telegram downloads" empties them; Sign out
  wipes the local Telegram data. Only Saved Messages is read. Uses TDLib; builds made without the project's
  Telegram app id show "This build has no Telegram app id" and nothing else changes.
- Torznab: add your own indexers in Settings (address and API key; the key sits in the secret store), with a
  capabilities check, test, enable or disable, remove and health. Each enabled endpoint is also a Find provider.
- Torrent Home: the Torrents tab opens on "Popular today / this week / this month" (Films and TV) and "Most seeded"
  rails built from your own Torznab indexers, ranked by seeders and split by upload date. Select adds the torrent
  (network question first) and plays the film; Menu or a long press opens the file list. With no source it offers
  "Add a source". Lists are cached (3 h, 12 h, 24 h) and refreshed on open, pull to refresh and Retry. Search plugins
  join through a small `PopularSource` seam once the plugin registry lands.

- Search on TV and desktop: the keyboard is hidden until you press the search bar, then drops down under it as a
  compact frosted panel (letters, a symbols page, space, Clear and Search) with suggestions as you type. Keys tick,
  click and chime on Android TV; Settings > "Keyboard sounds" turns the sounds off.
- Player: pick the audio track and subtitles (embedded tracks, and YouTube's dubbed audio) from a menu on the display
  (Down to the subtitles button, or the Menu / Info key; a sheet on a phone). The last language and subtitles on/off are
  remembered. The display now fades out slowly after a few seconds of playback and comes back on any key, touch or mouse
  move; the key that wakes it does nothing else. It stays up while paused or while a menu is open.

### Changed
- The TV, phone and shared UI code now live in `ui/tv`, `ui/phone` and `ui/common`.

## 0.2.1

### Added
- Phone views for YouTube, Search, Live TV, Torrents, Receive and Settings, kept apart from the TV
  design (`features/*/phone/`, `ui/phone/`). They share the same controllers and services.
  - YouTube and Search: a search bar at the top that uses the system keyboard, full-width 16:9 result
    cards, vertical result sections, pull down to search again.
  - Live TV: a source list (pull down to refresh every source), group chips that stay pinned while the
    channel list scrolls, tap a channel to play.
  - Torrents: a text field for a magnet link (type or paste), the network choice, and the file list.
  - Receive and Settings: Material 3 list tiles. Receive is reached from Settings on a phone.
- Phone widget tests at 360x640, 421x927, 927x421 and 800x1280 (tap targets, labels, no overflow), and
  phone end-to-end steps for a typed YouTube search, a pasted magnet and Live TV playback.

### Fixed
- A phone no longer shows the TV on-screen keyboard or the "Send from phone" buttons: it types with the
  system keyboard everywhere. The text entry dialog drops "Send from phone" on a phone.

### Note
- Builds tagged 0.2.1 also carry the 0.3.0 foundations, which merged onto main before this release was
  cut: the Media Home database and interfaces, secret storage, and the placeholder Settings sections for
  Metadata, Search plugins, Torznab and Image cache.

## 0.2.0

### Added
- YouTube: search from the Search page and the YouTube section, a result grid and ad-free playback
  (adaptive, live HLS and muxed streams). Search runs when asked, not while typing.
- Player: full-screen route with an on-screen display, resume from where you stopped, keep-screen-on, and
  Up/Down to change channel in Live TV.
- Live TV: add M3U playlists by link, sources with refresh and remove, group chips and a fast channel list
  (10,000 channels), dead channels dimmed and skipped. iptv-org and Free-TV are offered as opt-in
  suggestions; nothing is fetched until you confirm.
- Torrents: paste a magnet, pick a file (streamable and largest first) and stream it. You choose SOCKS5 or a
  direct connection before the first torrent. One torrent at a time, removed with its files when the
  player closes, so it seeds only while you watch.
- Receive: links, magnets and `.torrent` files sent from the LocalSend phone app on the same Wi-Fi.
  Private networks only, optional PIN, every transfer asks first and nothing plays by itself.
- Service layer (`AppServices`), stable item ids, redaction of URLs for logs, preferences file.
- Player route (stub), text entry, link intake and the Live TV, Torrents, YouTube and Receive feature skeletons.
- `localsend_rx` package skeleton.
- End-to-end suite (Linux under Xvfb and Android TV emulator) against local fixtures.
- Phone design: a bottom navigation bar (a rail on tablets), Settings in the top bar, a swipeable hero and
  touch tiles. A TV and desktop keep the D-pad design. Desktop gets a "10-foot TV mode" setting.
- A phone emulator end-to-end job and `.github/phone-shots.sh` for screenshots on a real phone.

### Changed
- The form factor is read from the device once at launch, not guessed from the window size: a phone in
  landscape and a large tablet are no longer treated as a TV. Phones stay in portrait outside the player.
- Mouse hover highlights a tile without moving focus; a click opens it.
- Host widget tests now run in CI on every pull request.
- Settings: torrent network, send from phone and About replace the desktop player test.
- `targetSdk` is pinned to 36.

### Fixed
- The text entry buttons stay on screen when the TV keyboard is open on a small TV.
- The Home hero fills the width on phones.
- The Android player plugin was no longer registered after the TV shell merge; `chithram_player` is an app
  dependency again and `depend_on_referenced_packages` is an analyzer error.

## 0.1.0

- Phase 0 scaffold: Flutter app skeleton (dark theme with a saffron accent,
  Poppins, a D-pad navigation rail, a Home page with a hero billboard and
  rails of placeholder tiles), Android phone + TV manifest, and placeholder
  packages (`innertube`, `iptv`, `chithram_player`) and `native/torrent`.
- CI (analyze and test) and a release pipeline (per-ABI APKs, Windows
  installer, Linux AppImage and tarball, smoke tests).
