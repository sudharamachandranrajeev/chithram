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
# DEVICE (tv_1080p), E2E_TARGET (default e2e_all_test.dart), E2E_FORM (tv; the
# form factor the suite expects), AVD_LCD (e.g. 1264x2780@480: screen size and
# density), AVD_KEYBOARD (hw.keyboard, no = soft keyboard shows), PHONE_SHOTS=1
# (after the suite: build a debug APK for arm64 + x86_64, run phone-shots.sh on
# the emulator, keep the APK in <out-dir>/apk). Needs Flutter, the Android SDK,
# cargo-ndk and /dev/kvm.
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

# Screen size and soft keyboard of the AVD (AVD_LCD=WxH@dpi, AVD_KEYBOARD=no|yes).
configure_avd() {
  local ini=$1
  set_ini() { sed -i "/^$1=/d" "$ini"; echo "$1=$2" >>"$ini"; }
  if [[ -n ${AVD_LCD:-} ]]; then
    local w=${AVD_LCD%%x*} rest=${AVD_LCD#*x}
    local h=${rest%%@*} dpi=${rest#*@}
    # A device skin overrides the LCD size.
    sed -i '/^skin\./d' "$ini"
    set_ini hw.lcd.width "$w"; set_ini hw.lcd.height "$h"; set_ini hw.lcd.density "$dpi"
    set_ini showDeviceFrame no
  fi
  [[ -z ${AVD_KEYBOARD:-} ]] || set_ini hw.keyboard "$AVD_KEYBOARD"
  grep -E '^(hw\.lcd|hw\.keyboard|skin)' "$ini" || true
}

android() {
  local out; out=$(realpath -m "$1")
  local IMAGE=${IMAGE:-system-images;android-36;android-tv;x86_64}
  local DEVICE=${DEVICE:-tv_1080p}
  local TARGET=${E2E_TARGET:-e2e_all_test.dart}
  mkdir -p "$out"
  local sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}
  export PATH="$sdk/cmdline-tools/latest/bin:$sdk/emulator:$sdk/platform-tools:$PATH"

  host_services "$out/fixtures"
  mapfile -t defines <"$out/fixtures/e2e.env"
  defines+=("--dart-define=E2E_FORM=${E2E_FORM:-tv}")

  # Build first: the emulator is the slow, flaky part.
  phase "torrent library (x86_64)"
  (cd "$root/native/torrent" && cargo ndk -P 24 -t x86_64 \
    -o ../../packages/torrent/android/src/main/jniLibs build --release --locked --lib)
  phase "build the e2e APK"
  (cd "$root/app" && flutter build apk --debug --target-platform android-x64 \
    --target=integration_test/$TARGET "${defines[@]}")
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
  configure_avd "$ANDROID_AVD_HOME/ci.avd/config.ini"
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
      --driver=integration_test/driver.dart --target=integration_test/$TARGET \
      --use-application-binary="$out/e2e-debug.apk" "${defines[@]}" \
      -d emulator-5554 2>&1 | tee "$out/drive-$attempt.log" || status=$?
    cp "$out/drive-$attempt.log" "$out/drive.log"
    [[ $status -eq 0 ]] && break
    adb logcat -d >"$out/logcat-drive-$attempt.txt" || true
  done
  adb logcat -d >"$out/logcat.txt" || true
  if [[ $status -ne 0 ]]; then echo "::error::e2e suite failed"; fi
  if [[ ${PHONE_SHOTS:-} == 1 ]]; then phone_shots "$out" || status=$?; fi
  phase "done (status $status)"
  rm -f "$out"/*.apk
  return $status
}

# The app itself (not the test target), for arm64 phones and the emulator: kept
# as <out>/apk/chithram-debug.apk, and driven by phone-shots.sh on the emulator.
phone_shots() {
  local out=$1
  phase "debug APK (arm64 + x86_64)"
  (cd "$root/native/torrent" && cargo ndk -P 24 -t arm64-v8a -t x86_64 \
    -o ../../packages/torrent/android/src/main/jniLibs build --release --locked --lib)
  (cd "$root/app" && flutter build apk --debug --target-platform android-arm64,android-x64)
  mkdir -p "$out/apk"
  cp "$root/app/build/app/outputs/flutter-apk/app-debug.apk" "$out/apk/chithram-debug.apk"
  phase "phone-shots on the emulator"
  bash "$root/.github/phone-shots.sh" "$out/shots" "$out/apk/chithram-debug.apk" || {
    echo "::error::phone-shots failed"; return 1; }
}

case ${1:-} in
  host-services) host_services "${2:?usage: e2e.sh host-services <dir>}" ;;
  android) android "${2:-e2e-out}" ;;
  *) echo "usage: e2e.sh host-services <dir> | android <out-dir>" >&2; exit 2 ;;
esac
