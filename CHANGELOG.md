# Changelog

Release notes are taken from the section of the version being tagged.

## 0.4.0

### Changed
- Player: new on-screen controls. A top bar with Back, the title, playback speed and (desktop) fullscreen and window
  buttons; large centre controls (back 10 s, play/pause, forward 10 s, previous/next); a seek bar; volume and mute on
  desktop. Esc leaves fullscreen and then closes the player; Space/K, J/L, M and F work as on video sites, and the mouse
  back button goes back.
- Desktop: the title bar stays on every page and has a Back button, so pages opened over the main screen (player,
  results, channel lists) always have a way back. Esc and Alt+Left go back too.
- Live TV: filter channels by category, country, language and quality, search by name, and sort by name, channel
  number, country or recently watched. Favourites and a recently watched list (last 50). Grid or list view. Country,
  language and quality are worked out from the playlist (tvg-id, group and name), so existing playlists get them too.
- YouTube: a new home page on desktop, phone and TV with search suggestions, topic chips (For you, Continue watching,
  Music, Live, Sports, News, Gaming), a rotating featured banner and rows of video cards with watch progress and
  duration. Search results are a grid on desktop and a list on phone, load more as you scroll, and Back returns to
  where you were. Loading placeholders, and a Retry when loading fails.
- App Home uses the same banner, cards and rows as the YouTube home.

### Known issues
- Pages with their own back arrow (Find, Plugins, YouTube results) show it under the title-bar Back on desktop.
- Video cards do not show upload age yet.
- Android: playback speed and volume are new and not yet tested on a device.

## 0.3.1

### Added
- Media section (redesign part 5), off by default: turn on Media to pair the app with your own Chithram media gateway
  using a 6-digit code and the gateway's certificate fingerprint. Then search, request films and series, approve
  requests (admins), follow downloads, browse the library and play films. What you see depends on your role. The app
  never holds a Jellyfin, Seerr or other service key; its device token sits in secure storage and every connection is
  pinned to the gateway's certificate. On desktop it is a sidebar group, on TV a rail item, on phones a top-bar button.
- Not yet: episode and track browsing (series and albums are listed, only films play), posters in search results, and
  scanning the fingerprint as a QR code.

## 0.2.2

### Fixed
- Windows: opening Chithram could open Paattu (or Paattu open Chithram). The installer reused Paattu's setup ID, so
  Windows Setup put Chithram into the Paattu folder and the two apps shared, and overwrote, each other's app code.
  Chithram now has its own setup ID and its own folder, and Setup refuses a folder that holds another app. Updating
  takes Chithram out of the Paattu folder; if it was there, reinstall Paattu afterwards to repair it.

## 0.3.0

### Changed
- New look (redesign parts 1 to 4): design tokens for spacing, corners, motion and type, and a new default dark look,
  Night. The TV rail, hero, rails and tiles are restyled with a focus ring and glow, 16:9 thumbnails and less motion
  when the system asks for it. The phone has a glass top bar, a pill bottom bar (a rail on tablets), a rounded hero
  card and rails that show how much you watched, and it holds large text sizes without overflowing.
- Themes are now six looks: Night (default), Saffron, Noir, Mint, Ocean and Graphite. A look that was removed maps to
  the nearest one kept. Installs that never picked a look stay on Saffron; new installs start on Night.
- TV fit: everything is about a quarter smaller on a 1080p TV (it lays out at 960x540): text floor 18 instead of 24,
  tiles at their base size, a narrower nav rail and tighter pages, so Home, Settings and dialogs fit one screen.
  Telegram sign-in shows a smaller QR code beside its steps, and the phone-number view has a way back to the QR code.
- The drop-down keyboard is smaller (32 dp keys, narrower panel) and its suggestions sit in rows under the keys,
  labelled by source: YouTube suggestions, and on Search also matching Live TV channels. Text-entry dialogs (links,
  magnets, PINs, keys, phone numbers) now open compact and drop the same keyboard down only when you select the field.

### Added
- Media section (off by default; Settings > Media section): Search, Requests, Downloads (admins), Library and the
  pairing/server screen, talking only to the Chithram media gateway over HTTPS with its certificate pinned by
  SHA-256 fingerprint. Roles (admin, requester, viewer) hide what the server would refuse. The device token lives in
  secure storage only. Playback runs through a loopback proxy so the token never appears in a URL.
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
- Player: Up Next plays the next video on its own, and the seek bar is redrawn.
- Desktop shell (Windows and Linux): a title bar with search (Ctrl+K), a sidebar that collapses under 1200 dp or with
  Ctrl+B, a hero and paged rows on Home, and keyboard shortcuts (Esc, Alt+Left, F11 and more) that also work on
  pages opened over it. The 10-foot TV mode setting still gives the TV layout.
- Search plugins: add plugin repositories, which are signed, with domains pinned on first use, a warning for unsigned
  ones, health, and automatic updates you review. Plugins also run on desktop.
- One-command Linux install (`install-linux.sh`): Arch and Omarchy first, also Debian and Fedora.
- Media stack (optional, off by default, the app does not use it yet): a Docker Compose setup in `server/media-stack/` with
  Jellyfin, Prowlarr, Radarr, Sonarr, Lidarr and Seerr requests with admin, requester and viewer roles, plus a small
  gateway that holds every service key so the app never sees one. It has no download client and no indexers: nothing
  downloads until the owner adds authorised sources.

### Fixed
- Live TV: Free-TV and iptv-org catalogues showed 0 channels because gzipped lists were not decoded.
- Windows: the 0.2.2 installer fix (own setup ID and folder, never Paattu's) is included.

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
