#!/usr/bin/env bash
# Boots an Android emulator (default: Android TV, API 36, x86_64) with KVM and
# runs the Chithram UI checks on it. Usage: tv-emulator.sh <out-dir>
#
# Env: IMAGE   system image (default system-images;android-36;android-tv;x86_64)
#      DEVICE  avd hardware profile (default tv_1080p)
#      NAME    label used in output names (default tv)
# Needs Flutter on PATH, the Android SDK (ANDROID_HOME) and /dev/kvm.
#
# Output in <out-dir>: screenshots/*.png (flutter drive), adb-*.png and
# uiautomator-*.xml (real adb key events), cold-start.txt, logcat.txt.
set -euo pipefail

out=$(realpath -m "${1:-tv-out}")
IMAGE=${IMAGE:-system-images;android-36;android-tv;x86_64}
DEVICE=${DEVICE:-tv_1080p}
NAME=${NAME:-tv}
PKG=dev.chithram.chithram
mkdir -p "$out"
phase() { # timestamped phase marker, also in the job summary
  local line; line="$(date -u +%H:%M:%S) $*"
  echo "::notice::$line"
  echo "- $line ($NAME)" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
}
root=$(git rev-parse --show-toplevel)
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}
export PATH="$sdk/cmdline-tools/latest/bin:$sdk/emulator:$sdk/platform-tools:$PATH"

# --- build first: the emulator is the slow, flaky part, so the APKs are ready
# (and Gradle is warm) before it boots ------------------------------------------
cd "$root/app"
phase "build debug test APK"
flutter build apk --debug --target-platform android-x64 --target=integration_test/app_test.dart
cp build/app/outputs/flutter-apk/app-debug.apk "$out/test-debug.apk"
phase "build release APK"
flutter build apk --release --target-platform android-x64
cp build/app/outputs/flutter-apk/app-release.apk "$out/app-release.apk"
cd "$root"

# --- boot -------------------------------------------------------------------
phase "install system image and create AVD"
export ANDROID_AVD_HOME="$HOME/.android/avd"
mkdir -p "$ANDROID_AVD_HOME"
set +o pipefail
yes | sdkmanager --licenses >/dev/null 2>&1
set -o pipefail
sdkmanager --install "emulator" "platform-tools" "$IMAGE" >/dev/null
echo no | avdmanager create avd --force -n ci -k "$IMAGE" -d "$DEVICE"
emulator -list-avds | grep -qx ci || { echo "::error::AVD ci was not created"; exit 1; }
ls -l /dev/kvm
phase "boot emulator"
nohup emulator -avd ci -no-window -no-audio -no-boot-anim -no-snapshot -accel on \
  -gpu swiftshader_indirect -memory 3072 -no-metrics >"$out/emulator.log" 2>&1 &
emu=$!
adb start-server
for _ in $(seq 1 180); do
  kill -0 $emu 2>/dev/null || { tail -20 "$out/emulator.log"; echo "::error::emulator exited"; exit 1; }
  [[ $(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r') == 1 ]] && break
  sleep 5
done
[[ $(adb shell getprop sys.boot_completed | tr -d '\r') == 1 ]] || { echo "::error::emulator did not boot in 15 min"; exit 1; }
phase "emulator booted"
sleep 10
for s in window_animation_scale transition_animation_scale animator_duration_scale; do
  adb shell settings put global "$s" 0
done
adb shell wm size || true
adb shell wm density || true
adb logcat -c

# --- 1. integration tests through flutter drive ------------------------------
phase "flutter drive"
cd "$root/app"
status=0
SCREENSHOT_DIR="$out/screenshots" timeout 1200 flutter drive \
  --driver=integration_test/driver.dart --target=integration_test/app_test.dart \
  --use-application-binary="$out/test-debug.apk" \
  -d emulator-5554 2>&1 | tee "$out/drive.log" || status=$?
adb logcat -d >"$out/logcat.txt" || true
if [[ $status -ne 0 ]]; then
  echo "::error::integration tests failed on $NAME"
fi

# --- 2. release APK: cold start, real adb D-pad keys, uiautomator ----------
phase "cold start, adb keys"
adb uninstall $PKG >/dev/null 2>&1 || true
adb install -r "$out/app-release.apk"

times=()
for i in 1 2 3 4 5; do
  adb shell am force-stop $PKG
  sleep 2
  t=$(adb shell am start -W -n $PKG/.MainActivity | tr -d '\r' | awk '/TotalTime/ {print $2}')
  echo "cold start $i: ${t:-?} ms"
  times+=("${t:-99999}")
  sleep 3
done
median=$(printf '%s\n' "${times[@]}" | sort -n | sed -n 3p)
{
  echo "cold_start_ms_runs=${times[*]}"
  echo "cold_start_ms_median=$median"
  echo "image=$IMAGE (emulator-only number)"
} | tee "$out/cold-start.txt"

shot() { adb exec-out screencap -p >"$out/adb-$1.png" || true; adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 && adb pull /sdcard/ui.xml "$out/uiautomator-$1.xml" >/dev/null || true; }
key() { adb shell input keyevent "$1"; sleep 1.2; }

adb shell am force-stop $PKG
adb shell am start -W -n $PKG/.MainActivity >/dev/null
sleep 6
shot home
if [[ $NAME == tv ]]; then
  key KEYCODE_DPAD_DOWN   # Search
  shot search
  key KEYCODE_DPAD_RIGHT  # into the keyboard
  key KEYCODE_DPAD_CENTER # types "a"
  shot search-typed
  key KEYCODE_DPAD_LEFT   # to the rail
  key KEYCODE_DPAD_UP     # Home
  key KEYCODE_DPAD_RIGHT  # Play
  key KEYCODE_DPAD_DOWN   # first tile
  key KEYCODE_DPAD_CENTER # open details
  sleep 1
  shot details
  key KEYCODE_BACK
  shot home-after-back
fi
adb logcat -d >"$out/logcat-release.txt" || true

if grep -qE 'FATAL EXCEPTION' "$out/logcat-release.txt"; then
  echo "::error::crash in release build"; status=1
fi
if (( ${median:-99999} >= 3000 )); then
  echo "::error::cold start median ${median} ms is not under 3000 ms (emulator-only)"
  status=1
fi
phase "done (status $status)"
rm -f "$out"/*.apk
exit $status
