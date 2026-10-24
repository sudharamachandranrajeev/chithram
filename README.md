# Chithram

*Chithram* (Malayalam for "picture") is a bring-your-own-sources video app with
a streaming-style, D-pad-first interface: YouTube without an account, live TV
from IPTV playlists, and torrent streaming, with short start delays and no ads.

**Status: Phase 0.** This is a runnable scaffold: the navigation rail, a Home
page with a hero billboard and rails of placeholder tiles, and the CI and
release pipeline. There are no features yet. See [docs/decisions.md](docs/decisions.md)
for decisions, [docs/roadmap.md](docs/roadmap.md) for the plan and [docs/research.md](docs/research.md) for the research behind it.

## Platforms

- **Android TV first** (D-pad, 10-foot UI), then Android phones, in one APK
  (per-ABI: arm64-v8a, armeabi-v7a, x86_64).
- Windows (installer and portable zip) and Linux (AppImage and tarball).

## Install on Linux

One command, for Arch, Omarchy, Ubuntu, Debian and Fedora (x86_64):

```sh
curl -fsSL https://raw.githubusercontent.com/sudharamachandranrajeev/chithram/main/install-linux.sh | bash
```

On **Arch and Omarchy** this is all you need. Step by step, the script:

1. installs the runtime libraries with `sudo pacman -S --needed mpv libsecret gtk3`
   (`apt` and `dnf` equivalents are used on Debian/Ubuntu and Fedora);
2. downloads the newest release's `linux-x64.tar.gz` from GitHub and checks it
   against the release's `SHA256SUMS.txt`;
3. unpacks it to `~/.local/share/chithram`, links `~/.local/bin/chithram` and adds
   an app-launcher entry, so Chithram shows up in your menu (on Omarchy: `Super + Space`).

Everything stays in your home directory; only step 1 needs `sudo`.

- **Update:** run the same command again.
- **Uninstall:** `curl -fsSL https://raw.githubusercontent.com/sudharamachandranrajeev/chithram/main/install-linux.sh | bash -s -- --uninstall`
- **Libraries already installed?** Add `--no-deps`: `... | bash -s -- --no-deps`.
- **Prefer to read it first?** The script is [install-linux.sh](install-linux.sh), about 90 lines.
- **Prefer an AppImage?** Download `Chithram-<version>-linux-x86_64.AppImage` from the
  [releases page](https://github.com/sudharamachandranrajeev/chithram/releases),
  then `chmod +x` it and run it. It bundles its own libmpv.

Chithram opens full screen on a TV; on a desktop, turn on *Settings > 10-foot TV mode*
for the TV layout.

## Content-neutral

Chithram ships **no** indexers, plugins or addon URLs, and no channel lists.
Users add their own sources. The one exception is an opt-in first-run
suggestion of two public IPTV catalogues (iptv-org and Free-TV): nothing loads
until you choose one. Chithram does not circumvent DRM and does not
play DRM-protected services.

## Layout

| Path | What |
| --- | --- |
| `app/` | The Flutter app (`dev.chithram.chithram`) |
| `packages/innertube/` | YouTube InnerTube client (pure Dart; placeholder) |
| `packages/iptv/` | M3U / Xtream / XMLTV parsers (placeholder) |
| `packages/localsend_rx/` | LocalSend receiver (skeleton) |
| `packages/tdlib/` | Telegram client: TDLib's JSON interface over FFI, typed objects, a fake for tests |
| `packages/chithram_player/` | Player engine interface (placeholder) |
| `native/torrent/` | Rust torrent engine over librqbit (placeholder) |
| `docs/` | Research and decisions |

The Dart packages and the app form a [pub workspace](https://dart.dev/tools/pub/workspaces):
run `flutter pub get` at the repository root.

## Building

Everything is built in GitHub Actions; no local toolchain is needed or assumed.

- `ci.yml` analyzes and tests the app and packages on every push.
- `release.yml` builds Android (signed per-ABI APKs), the Windows installer and
  the Linux AppImage and tarball, and smoke-tests them (emulator, silent
  install, Xvfb). Pushing a `v*` tag publishes a GitHub release; running it by
  hand or on the weekly schedule only builds.

Set the Android signing secrets `CHITHRAM_KEYSTORE_BASE64`,
`CHITHRAM_KEYSTORE_PASSWORD`, `CHITHRAM_KEY_ALIAS` and `CHITHRAM_KEY_PASSWORD`
in the repository to sign releases (without them the APKs use a debug key).

## Licence

[MIT](LICENSE). Poppins is under the SIL Open Font License
(`app/assets/fonts/OFL.txt`).
