#!/usr/bin/env bash
# Release workflow: installs the APK on the emulator, starts Chithram and checks
# it's still up 20 s later with no crash in the log. Leaves a screenshot and
# the log in $1.
set -euo pipefail

out=${1:-smoke}
mkdir -p "$out"
apk=$(ls dist/*x86_64.apk | head -n1)
adb install -r "$apk"
adb logcat -c
adb shell am start -W -n dev.chithram.chithram/.MainActivity
sleep 20
adb exec-out screencap -p >"$out/android.png" || true
adb logcat -d >"$out/logcat.txt" || true

if ! adb shell pidof dev.chithram.chithram >/dev/null; then
  grep -E 'AndroidRuntime|FATAL|flutter' "$out/logcat.txt" | tail -80 || true
  echo "::error::Chithram isn't running 20 s after it started"
  exit 1
fi
if grep -qE 'FATAL EXCEPTION|Unhandled Exception' "$out/logcat.txt"; then
  grep -E -A20 'FATAL EXCEPTION|Unhandled Exception' "$out/logcat.txt" | head -80
  echo "::error::Chithram threw an exception at start"
  exit 1
fi
grep -E ' flutter ' "$out/logcat.txt" | tail -20 || true
echo "Chithram is up on the emulator"
