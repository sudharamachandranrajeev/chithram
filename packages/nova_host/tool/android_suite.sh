#!/usr/bin/env bash
# Runs on the Android TV emulator (called by spike-nova.yml): installs the debug
# APK, opens the nova spike route (which auto-runs the acceptance suite), waits
# for SUITE_DONE in logcat and writes a summary.
set -uo pipefail
apk=$1
out=${2:-nova-android}
mkdir -p "$out"
sum=${GITHUB_STEP_SUMMARY:-$out/summary.md}

adb install -r -t "$apk" || { echo "install failed"; exit 1; }
adb logcat -c
adb shell am start -W -n dev.chithram.chithram/.MainActivity --es route /spike/nova
done_flag=0
for _ in $(seq 1 100); do
  sleep 5
  if adb logcat -d -s flutter:I | grep -q 'NOVA_SPIKE SUITE_DONE'; then done_flag=1; break; fi
done
adb logcat -d >"$out/logcat.txt" || true
adb exec-out screencap -p >"$out/screen.png" || true
grep -E 'NOVA_SPIKE' "$out/logcat.txt" | sed 's/^.*NOVA_SPIKE /NOVA_SPIKE /' >"$out/nova_spike.txt" || true
grep -E 'NovaService|NovaHostPlugin|python|chaquopy' "$out/logcat.txt" | grep -v 'NOVA_SPIKE' | head -80 >"$out/service_log.txt" || true

{
  echo "### nova acceptance on Android TV emulator (x86_64, API 36)"
  echo
  if [ "$done_flag" != 1 ]; then echo "**suite did not finish within 500 s**"; fi
  echo '```'
  grep -E 'NOVA_SPIKE (CHECK|SUITE_DONE|NOVA_ISOLATED|suite start)|NOVA_ISOLATED' "$out/nova_spike.txt" || true
  echo '```'
  echo "Service log (isolatedProcess attempt, Chaquopy start):"
  echo '```'
  head -40 "$out/service_log.txt" || true
  echo '```'
  echo "Details:"
  echo '```'
  grep -E 'NOVA_SPIKE (PASS|FAIL)' "$out/nova_spike.txt" | cut -c1-400 || true
  echo '```'
} >>"$sum"

if [ "$done_flag" != 1 ]; then exit 1; fi
grep -q 'SUITE_DONE passed=[0-9]* failed=0' "$out/nova_spike.txt"
