#!/usr/bin/env bash
# Performance runs on a real device (the owner's phone or TV box) over adb.
#
#   perf-device.sh coldstart [runs]   cold starts: "Fully drawn" and am start -W time
#   perf-device.sh scroll             scripted swipe (phone) or D-pad (TV box) scroll
#                                     of Home; gfxinfo frame times and PSS
#
# Install the release APK first (a release build, ideally with
# --dart-define=PERF_PROBE=true for the CHITHRAM_* frame lines). The device
# stays awake and on Home. Targets: cold start <= 2.0 s on the TV box, <= 1.0 s on
# a mid-range phone; no scroll frame over 32 ms in max(build, raster), at most 5%
# over 16 ms. Results go in the release checklist. Not run by CI.
#
# Env: ADB_SERIAL (adb -s), PKG (default dev.chithram.chithram), FORM (phone|tv,
# default: phone when the screen is taller than wide).
set -euo pipefail

PKG=${PKG:-dev.chithram.chithram}
ACT=$PKG/.MainActivity
adb=(adb)
[[ -z ${ADB_SERIAL:-} ]] || adb=(adb -s "$ADB_SERIAL")
a() { "${adb[@]}" "$@" | tr -d '\r'; }

fully_ms() { # first "+XsYms" after "Fully drawn" in stdin
  python3 -c '
import re, sys
for l in sys.stdin:
    if "Fully drawn" in l:
        m = re.search(r"\+(?:(\d+)s)?(\d+)ms", l)
        if m:
            print(int(m.group(1) or 0) * 1000 + int(m.group(2))); break
'
}

coldstart() {
  local runs=${1:-7} results=()
  for i in $(seq 1 "$runs"); do
    a shell am force-stop "$PKG"; sleep 3
    a logcat -c
    local total; total=$(a shell am start -W -n "$ACT" | awk '/TotalTime/ {print $2}')
    local ms=""
    for _ in $(seq 1 40); do
      ms=$(a logcat -d | fully_ms || true)
      [[ -n $ms ]] && break
      sleep 0.5
    done
    echo "run $i: Fully drawn ${ms:-missing} ms, am start -W TotalTime ${total:-?} ms"
    [[ $i -gt 1 && -n $ms ]] && results+=("$ms")
  done
  [[ ${#results[@]} -gt 0 ]] || { echo "no measurements"; return 1; }
  printf '%s\n' "${results[@]}" | sort -n | awk '{a[NR]=$1} END {printf "median of %d (first discarded): %d ms\n", NR, (NR%2)?a[(NR+1)/2]:(a[NR/2]+a[NR/2+1])/2}'
}

scroll() {
  local size w h; size=$(a shell wm size | awk '/Physical size/ {print $3}'); w=${size%x*}; h=${size#*x}
  local form=${FORM:-}; [[ -n $form ]] || { [[ $h -gt $w ]] && form=phone || form=tv; }
  a shell am force-stop "$PKG"; a shell am start -W -n "$ACT" >/dev/null; sleep 6
  a shell dumpsys gfxinfo "$PKG" reset >/dev/null; a logcat -c
  if [[ $form == phone ]]; then
    local x=$((w / 2)) y1=$((h * 3 / 4)) y2=$((h / 4))
    for _ in $(seq 1 6); do a shell input swipe "$x" "$y1" "$x" "$y2" 350; sleep 0.3; done
    for _ in $(seq 1 6); do a shell input swipe "$x" "$y2" "$x" "$y1" 350; sleep 0.3; done
    local hx1=$((w * 4 / 5)) hx2=$((w / 5)) hy=$((h / 2))
    for _ in $(seq 1 4); do a shell input swipe "$hx1" "$hy" "$hx2" "$hy" 300; sleep 0.3; done
  else
    a shell 'for r in 1 2 3 4; do for i in 1 2 3 4 5 6 7 8 9 10 11 12; do input keyevent 22; sleep 0.12; done; input keyevent 20; sleep 0.12; done'
  fi
  sleep 2
  echo "--- gfxinfo (frame times include raster on this device)"
  a shell dumpsys gfxinfo "$PKG" | grep -E "Total frames|Janky|percentile|Number (Missed|High input|Slow)" || true
  echo "--- probe (needs PERF_PROBE build)"
  a logcat -d | grep -E "CHITHRAM_(JANK|FRAMES)" | tail -20 || true
  echo "--- PSS"
  a shell dumpsys meminfo "$PKG" | grep -E "TOTAL PSS|TOTAL" | head -1
}

case ${1:-} in
  coldstart) coldstart "${2:-7}" ;;
  scroll) scroll ;;
  *) echo "usage: perf-device.sh coldstart [runs] | scroll" >&2; exit 2 ;;
esac
