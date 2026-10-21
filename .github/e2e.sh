#!/usr/bin/env bash
# End-to-end harness (Linux and Android TV emulator).
#
#   e2e.sh host-services <dir>   fixtures + local servers; writes <dir>/e2e.env
#   e2e.sh android <out-dir>     host-services, then the suite on an emulator
#
# host-services makes the ffmpeg fixtures (make_fixtures.sh) plus a muxed
# movie.mkv and a playlist.m3u (HLS master, movie.mkv, a dead URL), serves them
# on 127.0.0.1:8000 (serve.py) and seeds movie.mkv on 127.0.0.1:16881 (the
# torrent seeder example). <dir>/e2e.env holds the dart-defines.
#
# Env for android: IMAGE (default system-images;android-36;android-tv;x86_64),
# DEVICE (tv_1080p). Needs Flutter, the Android SDK, cargo-ndk and /dev/kvm.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
PKG=dev.chithram.chithram
BASE=http://127.0.0.1:8000
PEER=127.0.0.1:16881

phase() { # timestamped phase marker, also in the job summary
  local line; line="$(date -u +%H:%M:%S) $*"
  echo "::notice::$line"
  echo "- $line" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
}

host_services() {
  local dir; dir=$(realpath -m "$1")
  mkdir -p "$dir"
  phase "fixtures"
  bash "$root/packages/chithram_player/tool/make_fixtures.sh" "$dir" >/dev/null
  # A muxed file: the shape of a torrent video and of a plain media link.
  ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "testsrc2=size=1280x720:rate=30" -f lavfi -i "sine=frequency=440:sample_rate=48000" -t 60 \
    -c:v libx264 -preset veryfast -pix_fmt yuv420p -g 60 -c:a aac -b:a 96k "$dir/movie.mkv"
  cat >"$dir/playlist.m3u" <<M3U
#EXTM3U
#EXTINF:-1 tvg-id="e2e.hls" group-title="E2E",E2E HLS
$BASE/hls/master.m3u8
#EXTINF:-1 tvg-id="e2e.movie" group-title="E2E",E2E Movie
$BASE/movie.mkv
#EXTINF:-1 tvg-id="e2e.dead" group-title="E2E",E2E Dead
$BASE/missing/dead.m3u8
M3U

  phase "serve fixtures on :8000"
  setsid nohup python3 "$root/packages/chithram_player/tool/serve.py" "$dir" 8000 >"$dir/serve.log" 2>&1 &
  for _ in $(seq 1 20); do curl -sfI "$BASE/movie.mkv" >/dev/null && break; sleep 0.5; done
  curl -sfI "$BASE/movie.mkv" >/dev/null || { cat "$dir/serve.log"; echo "::error::fixture server is not up"; exit 1; }

  phase "seed movie.mkv on :16881"
  cargo build --release --locked --example seeder --manifest-path "$root/native/torrent/Cargo.toml"
  setsid nohup "$root/native/torrent/target/release/examples/seeder" --file "$dir/movie.mkv" --port 16881 \
    --dir "$dir/seed" --out "$dir/magnet.txt" >"$dir/seeder.log" 2>&1 &
  for _ in $(seq 1 60); do [[ -s $dir/magnet.txt ]] && break; sleep 1; done
  [[ -s $dir/magnet.txt ]] || { cat "$dir/seeder.log"; echo "::error::seeder did not write a magnet"; exit 1; }
  {
    echo "--dart-define=E2E_BASE=$BASE"
    echo "--dart-define=E2E_MAGNET=$(cat "$dir/magnet.txt")"
    echo "--dart-define=E2E_PEER=$PEER"
  } >"$dir/e2e.env"
  cat "$dir/seeder.log"
}

android() {
  local out; out=$(realpath -m "$1")
  local IMAGE=${IMAGE:-system-images;android-36;android-tv;x86_64}
  local DEVICE=${DEVICE:-tv_1080p}
  mkdir -p "$out"
  local sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}
  export PATH="$sdk/cmdline-tools/latest/bin:$sdk/emulator:$sdk/platform-tools:$PATH"

  host_services "$out/fixtures"
  mapfile -t defines <"$out/fixtures/e2e.env"

  # Build first: the emulator is the slow, flaky part.
  phase "torrent library (x86_64)"
  (cd "$root/native/torrent" && cargo ndk -P 24 -t x86_64 \
    -o ../../packages/torrent/android/src/main/jniLibs build --release --locked --lib)
  phase "build the e2e APK"
  (cd "$root/app" && flutter build apk --debug --target-platform android-x64 \
    --target=integration_test/e2e_all_test.dart "${defines[@]}")
  cp "$root/app/build/app/outputs/flutter-apk/app-debug.apk" "$out/e2e-debug.apk"
  # The torrent build tree is large; the TV image needs the room.
  rm -rf "$root/native/torrent/target/release/deps" "$root/native/torrent/target/release/build" || true

  phase "install system image and create AVD"
  export ANDROID_AVD_HOME="$HOME/.android/avd"
  mkdir -p "$ANDROID_AVD_HOME"
  set +o pipefail
  yes | sdkmanager --licenses >/dev/null 2>&1
  set -o pipefail
  sdkmanager --install "emulator" "platform-tools" "$IMAGE" >/dev/null
  echo no | avdmanager create avd --force -n ci -k "$IMAGE" -d "$DEVICE"
  emulator -list-avds | grep -qx ci || { echo "::error::AVD ci was not created"; exit 1; }
  phase "boot emulator"
  nohup emulator -avd ci -no-window -no-audio -no-boot-anim -no-snapshot -accel on \
    -gpu swiftshader_indirect -memory 3072 -no-metrics >"$out/emulator.log" 2>&1 &
  local emu=$!
  adb start-server
  for _ in $(seq 1 180); do
    kill -0 $emu 2>/dev/null || { tail -20 "$out/emulator.log"; echo "::error::emulator exited"; exit 1; }
    [[ $(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r') == 1 ]] && break
    sleep 5
  done
  [[ $(adb shell getprop sys.boot_completed | tr -d '\r') == 1 ]] || { echo "::error::emulator did not boot"; exit 1; }
  phase "emulator booted"
  sleep 10
  for s in window_animation_scale transition_animation_scale animator_duration_scale; do
    adb shell settings put global "$s" 0
  done
  adb reverse tcp:8000 tcp:8000
  adb reverse tcp:16881 tcp:16881
  adb logcat -c

  # The player must hold the screen on while it plays: sample the window flags
  # during the run (they are only set while a video is playing).
  : >"$out/keep-screen-on.txt"
  (
    while true; do
      adb shell dumpsys window windows 2>/dev/null | tr -d '\r' \
        | awk '/Window #/ { w = ($0 ~ /dev\.chithram\.chithram/) } w && /KEEP_SCREEN_ON/ { f = 1 } END { exit !f }' \
        && echo seen >>"$out/keep-screen-on.txt"
      sleep 2
    done
  ) &
  local sampler=$!

  phase "flutter drive"
  cd "$root/app"
  local status=0
  # The VM service sometimes never connects on a fresh emulator: retry once.
  for attempt in 1 2; do
    phase "flutter drive attempt $attempt"
    adb shell am force-stop $PKG || true
    adb shell input keyevent KEYCODE_HOME || true
    status=0
    SCREENSHOT_DIR="$out/screenshots" timeout 900 flutter drive \
      --driver=integration_test/driver.dart --target=integration_test/e2e_all_test.dart \
      --use-application-binary="$out/e2e-debug.apk" "${defines[@]}" \
      -d emulator-5554 2>&1 | tee "$out/drive-$attempt.log" || status=$?
    cp "$out/drive-$attempt.log" "$out/drive.log"
    [[ $status -eq 0 ]] && break
    adb logcat -d >"$out/logcat-drive-$attempt.txt" || true
  done
  kill $sampler 2>/dev/null || true
  adb logcat -d >"$out/logcat.txt" || true
  if [[ $status -eq 0 ]]; then
    # Player checks that only logcat and dumpsys can see.
    if ! grep -q 'CHITHRAM_OPEN' "$out/logcat.txt"; then
      echo "::error::no CHITHRAM_OPEN line in logcat"; status=1
    elif grep -E 'CHITHRAM_OPEN.*[?@]' "$out/logcat.txt"; then
      echo "::error::CHITHRAM_OPEN logged a URL with a query or credentials"; status=1
    fi
    grep -q seen "$out/keep-screen-on.txt" || { echo "::error::KEEP_SCREEN_ON never set during playback"; status=1; }
    # The first open pays for codec loading; the fastest one is the warm figure.
    first=$(grep -oE 'CHITHRAM_FIRST_FRAME [0-9]+' "$out/logcat.txt" | grep -oE '[0-9]+$' | sort -n | head -1 || true)
    echo "fastest first frame (emulator only): ${first:-none} ms"
    if [[ -z $first || $first -ge 2500 ]]; then
      echo "::error::first frame ${first:-missing} ms, expected under 2500"; status=1
    fi
  fi
  if [[ $status -ne 0 ]]; then echo "::error::e2e suite failed"; fi
  phase "done (status $status)"
  rm -f "$out"/*.apk
  return $status
}

case ${1:-} in
  host-services) host_services "${2:?usage: e2e.sh host-services <dir>}" ;;
  android) android "${2:-e2e-out}" ;;
  *) echo "usage: e2e.sh host-services <dir> | android <out-dir>" >&2; exit 2 ;;
esac
