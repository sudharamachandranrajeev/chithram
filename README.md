<h1 align="center">
  <br>
  <a href="https://github.com/sudharamachandranrajeev/chithram"><img src="branding/chithram-512.png" alt="Chithram" width="140"></a>
  <br>
  Chithram
  <br>
</h1>

<h4 align="center">A bring-your-own-sources video app: YouTube without an account, live TV from IPTV playlists and torrent streaming, with no ads. Android TV first, then Android phones, Windows and Linux.</h4>

<p align="center">
  <a href="https://github.com/sudharamachandranrajeev/chithram/releases"><img src="https://img.shields.io/github/v/release/sudharamachandranrajeev/chithram?include_prereleases&color=f5a300" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/sudharamachandranrajeev/chithram?color=555" alt="License"></a>
  <img src="https://img.shields.io/badge/platforms-Android%20TV%20%7C%20Android%20%7C%20Windows%20%7C%20Linux-555" alt="Platforms">
  <img src="https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter" alt="Flutter">
</p>

<p align="center">
  <a href="#key-features">Key Features</a> •
  <a href="#how-to-use">How To Use</a> •
  <a href="#download">Download</a> •
  <a href="#credits">Credits</a> •
  <a href="#related">Related</a> •
  <a href="#license">License</a>
</p>

<p align="center">
  <img src="docs/screenshots/hero.png" alt="Chithram on a TV and a phone" width="100%">
</p>

*Chithram* is Malayalam for "picture". It has a streaming-style interface built for the D-pad first,
and a separate touch design for phones.

## Key Features

* **YouTube without an account** – Home is YouTube: a billboard and rails of what is popular in your
  region (music, live, sports, news, gaming). It learns on the device from what you watch and search
  and adds Continue watching, Recommended for you and Because you watched. Playback is ad-free.
* **Live TV** – add M3U playlists by link, with refresh, group chips and a fast channel list (10,000
  channels); dead channels are dimmed and skipped. iptv-org and Free-TV are offered as opt-in
  suggestions: nothing is fetched until you confirm.
* **Torrent streaming** – paste a magnet, pick a file and stream it while it downloads. You choose
  SOCKS5 or a direct connection first; one torrent at a time, removed with its files when the player
  closes, so it seeds only while you watch.
* **Torrent Home and Find** – popular rails ("today", "this week", "this month", "most seeded") built
  from your own Torznab indexers and search plugins, ranked by seeders.
* **Search plugins** – signed repositories, pinned domains, health checks and automatic updates of
  plugins you have already installed; plugins run in a sandbox.
* **Receive** – links, magnets and `.torrent` files sent from the LocalSend phone app on the same
  Wi-Fi. Private networks only, optional PIN, every transfer asks first.
* **Telegram receiver** – sign in with your own account and video or audio sent to your Saved
  Messages plays while it downloads. Only Saved Messages is read.
* **A player that stays out of the way** – audio and subtitle tracks, Up Next autoplay, a seek bar
  with thumbnails, resume where you stopped, and a display that fades out.
* **Two designs** – a D-pad TV and desktop design, and a touch design for phones with the system
  keyboard. The form is detected once from the device; desktop has a "10-foot TV mode".
* **Themes** – seven dark looks, an AMOLED black background and a custom accent colour.

## Screenshots

All screenshots are rendered from the app with made-up titles, channels and torrents, and generated
placeholder thumbnails (see `app/test/screenshots_test.dart`).

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/tv-livetv.png" width="380"><br><sub>Live TV on a TV</sub></td>
    <td align="center"><img src="docs/screenshots/tv-torrents.png" width="380"><br><sub>Torrent Home on a TV</sub></td>
  </tr>
</table>
<table>
  <tr>
    <td align="center"><img src="docs/screenshots/phone-home.png" width="200"><br><sub>Home on a phone</sub></td>
    <td align="center"><img src="docs/screenshots/phone-livetv.png" width="200"><br><sub>Live TV on a phone</sub></td>
    <td align="center"><img src="docs/screenshots/phone-torrents.png" width="200"><br><sub>Torrents on a phone</sub></td>
  </tr>
</table>

## How To Use

To clone and run this application, you'll need [Git](https://git-scm.com) and
[Flutter](https://flutter.dev) installed. The Dart packages and the app form a
[pub workspace](https://dart.dev/tools/pub/workspaces), so run `flutter pub get` at the repository root:

```bash
# Clone this repository
$ git clone https://github.com/sudharamachandranrajeev/chithram

# Go into the repository
$ cd chithram

# Install dependencies
$ flutter pub get

# Run the app
$ cd app
$ flutter run -d linux

# Run the tests
$ flutter test
```

Screenshots: `CHITHRAM_SHOTS=/tmp/shots FLUTTER_ROOT=<flutter sdk> flutter test test/screenshots_test.dart`
renders the TV (1920x1080) and phone screens to PNG files.

Everything is built in GitHub Actions; no local toolchain is needed or assumed.

- `ci.yml` analyzes and tests the app and packages on every push.
- `release.yml` builds Android (signed per-ABI APKs), the Windows installer and the Linux AppImage and
  tarball, and smoke-tests them (emulator, silent install, Xvfb). Pushing a `v*` tag publishes a
  GitHub release; running it by hand or on the weekly schedule only builds.

Set the Android signing secrets `CHITHRAM_KEYSTORE_BASE64`, `CHITHRAM_KEYSTORE_PASSWORD`,
`CHITHRAM_KEY_ALIAS` and `CHITHRAM_KEY_PASSWORD` in the repository to sign releases (without them the
APKs use a debug key).

<details>
<summary><b>Repository layout</b></summary>

| Path | What |
| --- | --- |
| `app/` | The Flutter app (`dev.chithram.chithram`) |
| `packages/innertube/` | YouTube InnerTube client (pure Dart) |
| `packages/iptv/` | M3U / Xtream / XMLTV parsers |
| `packages/localsend_rx/` | LocalSend receiver |
| `packages/tdlib/` | Telegram client: TDLib's JSON interface over FFI, typed objects, a fake for tests |
| `packages/chithram_player/` | Player engine interface |
| `native/torrent/` | Rust torrent engine over librqbit |
| `docs/` | Research, decisions and roadmap |

More packages (`torznab`, `tmdb`, `media_names`, `nova_host`, `torrent`) are listed in `packages/`.

</details>

## Download

Builds are on the [releases page](https://github.com/sudharamachandranrajeev/chithram/releases).

* **Android TV and phones** – one APK, per-ABI (arm64-v8a, armeabi-v7a, x86_64).
* **Windows** – installer and portable zip.
* **Linux** – AppImage (`Chithram-<version>-linux-x86_64.AppImage`, bundles its own libmpv: `chmod +x`
  and run) and tarball, or the one-command installer below.

### Install on Linux

One command, for Arch, Omarchy, Ubuntu, Debian and Fedora (x86_64):

```sh
curl -fsSL https://raw.githubusercontent.com/sudharamachandranrajeev/chithram/main/install-linux.sh | bash
```

On **Arch and Omarchy** this is all you need. Step by step, the script:

1. installs the runtime libraries with `sudo pacman -S --needed mpv libsecret gtk3`
   (`apt` and `dnf` equivalents are used on Debian/Ubuntu and Fedora);
2. downloads the newest release's `linux-x64.tar.gz` from GitHub and checks it against the release's
   `SHA256SUMS.txt`;
3. unpacks it to `~/.local/share/chithram`, links `~/.local/bin/chithram` and adds an app-launcher entry,
   so Chithram shows up in your menu (on Omarchy: `Super + Space`).

Everything stays in your home directory; only step 1 needs `sudo`.

- **Update:** run the same command again.
- **Uninstall:** `curl -fsSL https://raw.githubusercontent.com/sudharamachandranrajeev/chithram/main/install-linux.sh | bash -s -- --uninstall`
- **Libraries already installed?** Add `--no-deps`: `... | bash -s -- --no-deps`.
- **Prefer to read it first?** The script is [install-linux.sh](install-linux.sh), about 90 lines.

On a desktop you can turn on *Settings > 10-foot TV mode* for the TV layout.

### Content-neutral

Chithram ships **no** indexers, plugins or addon URLs, and no channel lists. Users add their own
sources. The one exception is an opt-in first-run suggestion of two public IPTV catalogues (iptv-org
and Free-TV): nothing loads until you choose one. Chithram does not circumvent DRM and does not play
DRM-protected services.

See [docs/decisions.md](docs/decisions.md) for decisions, [docs/roadmap.md](docs/roadmap.md) for the
plan and [docs/research.md](docs/research.md) for the research behind it.

## Credits

This software uses the following open source packages and services:

- [Flutter](https://flutter.dev), [media_kit](https://pub.dev/packages/media_kit) (libmpv) for desktop video
- [drift](https://drift.simonbinder.eu) and
  [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage)
- [librqbit](https://github.com/ikatson/rqbit) for torrent streaming
- [TDLib](https://github.com/tdlib/td) for the Telegram receiver (Boost Software License)
- [LocalSend](https://localsend.org) protocol for Receive
- [iptv-org](https://github.com/iptv-org/iptv) and [Free-TV](https://github.com/Free-TV/IPTV) as opt-in playlist suggestions
- [Poppins](https://fonts.google.com/specimen/Poppins) (SIL Open Font License)
- This product uses the TMDB API but is not endorsed or certified by TMDB. See [NOTICE](NOTICE).

## Related

* [Brahma](https://github.com/sudharamachandranrajeev/brahma) – the author's life-management suite (a
  separate project)
* [Paattu](https://github.com/sudharamachandranrajeev/paattu) – a music player by the same author,
  whose YouTube resolver this app's `innertube` package grew from

## License

[MIT](LICENSE). Poppins is under the SIL Open Font License (`app/assets/fonts/OFL.txt`); the TMDB logo
is covered by TMDB's own terms (see [NOTICE](NOTICE)).

---

> GitHub [@sudharamachandranrajeev](https://github.com/sudharamachandranrajeev)
