# Spikes

Five parallel spikes branch from main after S0 prep. Each owns disjoint paths so
merges never conflict.

| Branch | Owns |
|---|---|
| `spike/torrent` | `native/torrent/**`, `packages/torrent/**`, `app/lib/src/spikes/torrent_page.dart` |
| `spike/player` | `packages/chithram_player/**`, `app/lib/src/spikes/player_page.dart` |
| `spike/nova` | `packages/nova_host/**`, `native/sandbox/**`, `python/nova/**`, `app/lib/src/spikes/nova_page.dart`, and the only edits to `app/android/settings.gradle.kts` |
| `spike/tv-shell` | `app/lib/src/ui/**`, `app/integration_test/**`, `.github/tv-emulator.sh` |
| `spike/youtube` | `packages/innertube/**` |

Each spike also owns its own `.github/workflows/spike-<name>.yml`.

## Rules

- Edit only owned paths and your own workflow. Need a change elsewhere? Ask; do not edit it.
- Do not commit `pubspec.lock`. The lockfile is regenerated on main from the CI artifact.
- Rust crates are standalone (own `Cargo.lock`, no cargo workspace).
- Spike workflows use `paths:` filters plus `workflow_dispatch`, to save Actions minutes.
- No local Flutter/Dart/cargo/pip runs on the dev machine (OpenSnitch); CI compiles.
- Do not tag. Do not merge to main without review.

## Spike pages (debug only)

Placeholders live in `app/lib/src/spikes/`, wired by `registry.dart`. Android:
`adb shell am start -n dev.chithram.chithram/.MainActivity --es route /spike/<torrent|player|nova>`.
Desktop: `flutter run --dart-define=SPIKE=<name>`. Guard is `kDebugMode`, a
compile-time constant: release and profile builds tree-shake the pages and the
routes resolve to nothing (unknown routes fall back to the normal shell).
The registry and the `app.dart` hook are set in S0; spikes edit only their own page file.

## Acceptance checks

### spike/torrent
- rqbit cdylib over `dart:ffi`. Verify its licence is Apache-2.0.
- Contract: `start(dir, quota, socks5?)` returns `{port, token}`; `add(magnet|bytes)` returns `{id, files}`; `GET /{token}/stream/{id}/{idx}` with Range; stats; remove. Loopback only, Host header check.
- Build: cargo-ndk for 3 ABIs, MSVC (Windows), gnu on ubuntu-22.04 (Linux).
- Accept: `cargo test` and `cargo deny` pass; local seeder/leecher (`initial_peers`) 200 MB; Range sha matches at 0/50/90%; seek < 10 s; `/health` 200; no token or foreign Host returns 403; TV emulator streams 50 MB with RSS < 400 MB.

### spike/player
- Media3 SurfaceView PlatformView with MergingMediaSource on Android; media_kit on desktop.
- Accept: ffmpeg fixtures served via `adb reverse`; first-frame logcat marker < 2.5 s on TV emulator; seek works; DPAD_CENTER pauses and resumes; merged duration matches; media_kit plays under Xvfb.

### spike/nova
- Official CPython in an `isolatedProcess` service on Android; python-build-standalone 3.13 on desktop.
- Child process has no network; host brokers HTTP with a per-engine domain allowlist.
- Sandbox: seccomp/Landlock on Linux, AppContainer + Job on Windows, `:nova` isolatedProcess on Android.
- Signed minisign repos with TOFU key pin. Vendor qBittorrent `helpers.py`, `novaprinter.py`, `socks.py` (BSD-3).
- Accept: malicious fixture engines all blocked or killed; tampered or rotated-key repo refused; APK size delta reported.

### spike/tv-shell
- Focus system, nav rail, focus-remembering rails, on-screen-keyboard search, 5% overscan.
- Accept via `integration_test` on `system-images;android-36;android-tv;x86_64`: reach every nav item; 200 random keys never lose focus; typing "sintel" works; screenshots and uiautomator dumps uploaded; `am start -W` < 3 s (emulator-only).

### spike/youtube
- Port Paattu's resolver (`/home/rajeevrama/Work/paattu/app/lib/src/sources/youtube.dart`, `http.dart`) plus DASH video formats. Tiers: VISIONOS, android_vr, tv, youtube_explode_dart.
- Accept: fixture unit tests pass; live 20-video panel: at least 18 at >= 1080p with 206 Range (non-blocking).
