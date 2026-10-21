#!/usr/bin/env bash
# Runs inside the Android TV emulator (reactivecircus/android-emulator-runner).
# Installs the debug APK, opens the torrent spike page (which leeches a 50 MB
# file from the host seeder through `adb reverse` and range-reads it back over
# the loopback URL), and records the app's RSS while it runs.
set -uo pipefail

apk=$1
out=$2
pkg=dev.chithram.chithram
limit_kb=409600 # 400 MB
mkdir -p "$out"

adb reverse tcp:16881 tcp:16881
adb install -r -t "$apk" || { echo "install failed"; exit 1; }
adb logcat -c
adb shell am start -W -n "$pkg/.MainActivity" --es route /spike/torrent | tee "$out/am-start.txt"

echo "t_s,rss_kb" >"$out/rss.csv"
max=0
result=""
start=$(date +%s)
while (( $(date +%s) - start < 420 )); do
  pid=$(adb shell pidof "$pkg" | tr -d '\r')
  if [[ -n $pid ]]; then
    rss=$(adb shell "grep VmRSS /proc/$pid/status" | tr -d '\r' | awk '{print $2}')
    if [[ -n $rss ]]; then
      echo "$(( $(date +%s) - start )),$rss" >>"$out/rss.csv"
      (( rss > max )) && max=$rss
    fi
  else
    echo "app not running" >>"$out/rss.csv"
  fi
  if adb logcat -d -s flutter | grep -q 'TORRENT_AUTOTEST RESULT'; then
    result=$(adb logcat -d -s flutter | grep 'TORRENT_AUTOTEST RESULT' | tail -1)
    break
  fi
  sleep 2
done
# Keep sampling a few more seconds so teardown spikes are seen.
for _ in 1 2 3; do
  pid=$(adb shell pidof "$pkg" | tr -d '\r')
  [[ -n $pid ]] && rss=$(adb shell "grep VmRSS /proc/$pid/status" | tr -d '\r' | awk '{print $2}') && (( rss > max )) && max=$rss
  sleep 1
done

adb logcat -d >"$out/logcat.txt"
adb logcat -d -s flutter | grep TORRENT_AUTOTEST >"$out/autotest.txt" || true
adb exec-out screencap -p >"$out/screen.png" || true
adb shell dumpsys meminfo "$pkg" >"$out/meminfo.txt" || true

echo "max RSS: ${max} kB (limit ${limit_kb} kB)" | tee "$out/summary.txt"
echo "result: ${result:-none}" | tee -a "$out/summary.txt"
cat "$out/autotest.txt" || true
if [[ $result != *PASS* ]]; then echo "::error::autotest did not pass"; exit 1; fi
if (( max >= limit_kb )); then echo "::error::RSS ${max} kB over limit"; exit 1; fi
echo OK
