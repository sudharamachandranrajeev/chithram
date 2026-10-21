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
