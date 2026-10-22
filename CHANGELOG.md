# Changelog

Release notes are taken from the section of the version being tagged.

## 0.2.0 (in progress)

### Added
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
- The Android player plugin was no longer registered after the TV shell merge; `chithram_player` is an app
  dependency again and `depend_on_referenced_packages` is an analyzer error.

## 0.1.0

- Phase 0 scaffold: Flutter app skeleton (dark theme with a saffron accent,
  Poppins, a D-pad navigation rail, a Home page with a hero billboard and
  rails of placeholder tiles), Android phone + TV manifest, and placeholder
  packages (`innertube`, `iptv`, `chithram_player`) and `native/torrent`.
- CI (analyze and test) and a release pipeline (per-ABI APKs, Windows
  installer, Linux AppImage and tarball, smoke tests).
