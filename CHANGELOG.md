# Changelog

Release notes are taken from the section of the version being tagged.

## 0.2.1 (in progress)

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
