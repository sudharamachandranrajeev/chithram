#!/usr/bin/env bash
# One screenshot per bottom-navigation tab, and a check that Home stays in
# portrait when the system is told to rotate. Drives whichever device adb
# talks to (set ANDROID_SERIAL to choose one) with the real app, not a test.
#
#   phone-shots.sh <out-dir> [apk]
#
# With an apk it is installed first (adb install -r). Then for each tab the
# nav item is found with `uiautomator dump` (Flutter's Semantics labels are the
# content descriptions), tapped at its centre, and after 1 s the screen is
# saved as <out-dir>/<tab>.png. Finally user_rotation=1 (landscape) is forced:
# <out-dir>/rotated.png must still be portrait. The rotation settings are put
# back afterwards.
set -euo pipefail

out=${1:?usage: phone-shots.sh <out-dir> [apk]}
apk=${2:-}
PKG=dev.chithram.chithram
mkdir -p "$out"

adb get-state >/dev/null || { echo "no device: adb get-state failed" >&2; exit 1; }
if [[ -n $apk ]]; then adb install -r "$apk" >/dev/null; fi

setting() { adb shell settings get system "$1" | tr -d '\r'; }
old_auto=$(setting accelerometer_rotation)
old_user=$(setting user_rotation)
restore() {
  adb shell settings put system user_rotation "${old_user/null/0}" || true
  adb shell settings put system accelerometer_rotation "${old_auto/null/1}" || true
}
trap restore EXIT

adb shell settings put system accelerometer_rotation 0
adb shell settings put system user_rotation 0
adb shell am force-stop "$PKG"
adb shell am start -W -n "$PKG/.MainActivity" >/dev/null
sleep 4

# A loaded CI emulator sometimes shows "System UI isn't responding" over the
# app; that dialog hides the app from uiautomator. Press its "Wait" button.
dismiss_anr() {
  adb shell uiautomator dump /sdcard/chithram-ui.xml >/dev/null
  local xy
  xy=$(adb exec-out cat /sdcard/chithram-ui.xml | python3 -I -c '
import re, sys, xml.etree.ElementTree as ET
nodes = list(ET.fromstring(sys.stdin.read()).iter("node"))
if not any("isn’t responding" in n.get("text", "") or "isn'"'"'t responding" in n.get("text", "") for n in nodes):
    sys.exit(1)
for n in nodes:
    if n.get("text", "") == "Wait":
        x1, y1, x2, y2 = map(int, re.findall(r"\d+", n.get("bounds", "")))
        print((x1 + x2) // 2, (y1 + y2) // 2)
        break
') || return 0
  if [[ -n $xy ]]; then
    echo "::notice::dismissed a System UI ANR dialog"
    # shellcheck disable=SC2086
    adb shell input tap $xy
    sleep 1
  fi
}

# Prints "x y" of the bottom-bar item labelled $1 (its description is the label
# and "Tab n of m").
find_tab() {
  dismiss_anr
  adb shell uiautomator dump /sdcard/chithram-ui.xml >/dev/null
  adb exec-out cat /sdcard/chithram-ui.xml | python3 -I -c '
import re, sys, xml.etree.ElementTree as ET
label = sys.argv[1]
best = None
for n in ET.fromstring(sys.stdin.read()).iter("node"):
    lines = n.get("content-desc", "").split("\n")
    if label not in lines:
        continue
    m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.get("bounds", ""))
    if not m:
        continue
    x1, y1, x2, y2 = map(int, m.groups())
    # The bottom bar is the lowest match; a "Tab n of m" line marks it.
    key = (any(l.startswith("Tab ") for l in lines), y1)
    if best is None or key > best[0]:
        best = (key, ((x1 + x2) // 2, (y1 + y2) // 2))
if best is None:
    sys.exit(1)
print(*best[1])
' "$1"
}

png_size() { # "<width> <height>" from the PNG header
  python3 -I -c '
import struct, sys
d = open(sys.argv[1], "rb").read(24)
print(*struct.unpack(">II", d[16:24]))
' "$1"
}

# Wait (up to 60 s) for the bottom bar to be on screen.
for _ in $(seq 1 30); do find_tab Home >/dev/null 2>&1 && break; sleep 2; done

fail=0
for tab in "Home:home" "Search:search" "Live TV:livetv" "YouTube:youtube" "Torrents:torrents"; do
  label=${tab%%:*}; slug=${tab##*:}
  if ! xy=$(find_tab "$label"); then
    echo "::error::no bottom-bar item labelled '$label'" >&2
    adb exec-out screencap -p >"$out/missing-$slug.png" || true
    fail=1; continue
  fi
  # shellcheck disable=SC2086
  adb shell input tap $xy
  sleep 1
  adb exec-out screencap -p >"$out/$slug.png"
  echo "$label: tapped $xy -> $out/$slug.png"
done

# Back on Home, ask the system to rotate: the app must stay portrait.
if xy=$(find_tab Home); then
  # shellcheck disable=SC2086
  adb shell input tap $xy
fi
sleep 1
adb shell settings put system user_rotation 1
sleep 2
adb exec-out screencap -p >"$out/rotated.png"
read -r w h < <(png_size "$out/rotated.png")
if (( w < h )); then
  echo "Home stays portrait with user_rotation=1 (${w}x${h})"
else
  echo "::error::Home rotated to landscape (${w}x${h})" >&2
  fail=1
fi
exit $fail
