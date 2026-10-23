#!/usr/bin/env bash
# Performance run on the Android TV emulator (perf.yml). Usage: perf.sh <out-dir>
#
#  1. build a release android-x64 APK with PERF_PROBE=true and the E2E defines
#  2. boot the TV emulator (-memory 2048)
#  3. seed: run once with the fixtures up and wait for CHITHRAM_HOME_REFRESHED
#     (the R0 stub Home never refreshes: the wait times out, with a warning)
#  4. network probe: one start with the fixtures up; /__hits delta by "Fully drawn"
#  5. stop the fixture server
#  6. 7 cold starts, the first discarded: "Fully drawn" from reportFullyDrawn
#  7. scripted D-pad scroll (input keyevent every 120 ms) with the in-app
#     FrameProbe and dumpsys gfxinfo
#  8. dumpsys meminfo (PSS)
#  9. compare with .github/perf-budget.json ("mode":"report" never fails)
#
# Output in <out-dir>: perf.json, logcat-*.txt, gfxinfo.txt, meminfo.txt. A
# table goes to the job summary. Needs Flutter, the Android SDK, cargo-ndk,
# ffmpeg, python3 and /dev/kvm.
set -euo pipefail

out=$(realpath -m "${1:-perf-out}")
root=$(git rev-parse --show-toplevel)
PKG=dev.chithram.chithram
ACT=$PKG/.MainActivity
BASE=http://127.0.0.1:8000
IMAGE=${IMAGE:-system-images;android-36;android-tv;x86_64}
DEVICE=${DEVICE:-tv_1080p}
STARTS=${PERF_STARTS:-7}
mkdir -p "$out"

phase() {
  local line; line="$(date -u +%H:%M:%S) $*"
  echo "::notice::$line"
  echo "- $line" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
}

sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}
export PATH="$sdk/cmdline-tools/latest/bin:$sdk/emulator:$sdk/platform-tools:$PATH"

# --- fixture server (images, and the API fixtures the work packages add) -------
phase "fixtures"
fx="$out/fixtures"
mkdir -p "$fx"
bash "$root/.github/fixtures/make_images.sh" "$fx" 40 >/dev/null
setsid nohup python3 "$root/packages/chithram_player/tool/serve.py" "$fx" 8000 >"$out/serve.log" 2>&1 &
server=$!
for _ in $(seq 1 20); do curl -sf "$BASE/__hits" >/dev/null && break; sleep 0.5; done
curl -sf "$BASE/__hits" >/dev/null || { cat "$out/serve.log"; echo "::error::fixture server is not up"; exit 1; }
defines=(
  --dart-define=PERF_PROBE=true
  --dart-define=E2E_BASE=$BASE
  --dart-define=E2E_TMDB_BASE=$BASE/tmdb
  --dart-define=E2E_TORZNAB=$BASE/torznab/api
  --dart-define=E2E_PLUGIN_REPO=$BASE/plugins/plugins.json
)

# --- build ------------------------------------------------------------------
phase "torrent library (x86_64)"
(cd "$root/native/torrent" && cargo ndk -P 24 -t x86_64 \
  -o ../../packages/torrent/android/src/main/jniLibs build --release --locked --lib)
phase "build release APK (x86_64, PERF_PROBE)"
(cd "$root/app" && flutter build apk --release --target-platform android-x64 "${defines[@]}")
apk="$root/app/build/app/outputs/flutter-apk/app-release.apk"
cp "$apk" "$out/perf-release.apk"
rm -rf "$root/native/torrent/target/release/deps" "$root/native/torrent/target/release/build" || true

# --- emulator ---------------------------------------------------------------
phase "install system image and create AVD"
export ANDROID_AVD_HOME="$HOME/.android/avd"
mkdir -p "$ANDROID_AVD_HOME"
set +o pipefail
yes | sdkmanager --licenses >/dev/null 2>&1
set -o pipefail
sdkmanager --install "emulator" "platform-tools" "$IMAGE" >/dev/null
echo no | avdmanager create avd --force -n perf -k "$IMAGE" -d "$DEVICE"
phase "boot emulator (-memory 2048)"
nohup emulator -avd perf -no-window -no-audio -no-boot-anim -no-snapshot -accel on \
  -gpu swiftshader_indirect -memory 2048 -no-metrics >"$out/emulator.log" 2>&1 &
emu=$!
adb start-server
for _ in $(seq 1 180); do
  kill -0 $emu 2>/dev/null || { tail -20 "$out/emulator.log"; echo "::error::emulator exited"; exit 1; }
  [[ $(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r') == 1 ]] && break
  sleep 5
done
[[ $(adb shell getprop sys.boot_completed | tr -d '\r') == 1 ]] || { echo "::error::emulator did not boot"; exit 1; }
sleep 10
for s in window_animation_scale transition_animation_scale animator_duration_scale; do
  adb shell settings put global "$s" 0
done
adb install -r "$out/perf-release.apk" >/dev/null
adb reverse tcp:8000 tcp:8000

# Waits up to $2 s for $1 in logcat; prints the matching line.
wait_log() {
  local pat=$1 secs=${2:-20} line=
  for _ in $(seq 1 $((secs * 2))); do
    line=$(adb logcat -d 2>/dev/null | tr -d '\r' | grep -E -m1 "$pat" || true)
    [[ -n $line ]] && { echo "$line"; return 0; }
    sleep 0.5
  done
  return 1
}

# --- seed -------------------------------------------------------------------
phase "seed run (fixtures up)"
adb logcat -c
adb shell am force-stop $PKG
adb shell am start -W -n $ACT >/dev/null
seeded=true
wait_log 'CHITHRAM_HOME_REFRESHED' 25 >/dev/null || { seeded=false; echo "::warning::no CHITHRAM_HOME_REFRESHED (the R0 stub Home never refreshes)"; }
adb shell am force-stop $PKG

# --- network probe: requests served before "Fully drawn" -----------------------
phase "network probe"
curl -sf -X POST "$BASE/__hits/reset" >/dev/null
adb logcat -c
adb shell am start -W -n $ACT >/dev/null
wait_log 'Fully drawn' 20 >/dev/null || echo "::warning::no 'Fully drawn' line in the probe run"
requests_before=$(curl -sf "$BASE/__hits" | python3 -c 'import json,sys;print(json.load(sys.stdin)["total"])')
adb shell am force-stop $PKG

phase "stop the fixture server"
kill $server 2>/dev/null || true
sleep 1
! curl -sf -m 2 "$BASE/__hits" >/dev/null || { echo "::error::fixture server still answers"; exit 1; }

# --- cold starts ------------------------------------------------------------
: >"$out/coldstarts.txt"
for i in $(seq 1 "$STARTS"); do
  phase "cold start $i/$STARTS"
  adb shell am force-stop $PKG
  sleep 2
  adb logcat -c
  adb shell am start -W -n $ACT | tr -d '\r' >"$out/start-$i.txt"
  if line=$(wait_log 'Fully drawn' 20); then
    echo "$i $line" >>"$out/coldstarts.txt"
  else
    echo "$i MISSING" >>"$out/coldstarts.txt"
    echo "::warning::start $i: no 'Fully drawn' line"
  fi
  adb logcat -d >"$out/logcat-start-$i.txt" || true
done

# --- scroll -----------------------------------------------------------------
phase "scripted D-pad scroll"
adb shell am force-stop $PKG
adb shell am start -W -n $ACT >/dev/null
wait_log 'Fully drawn' 20 >/dev/null || true
sleep 3
adb shell dumpsys gfxinfo $PKG reset >/dev/null || true
adb logcat -c
# Right x12, Down x1, four times; then Up x4 (keycodes: 22 right, 20 down, 19 up).
adb shell 'for r in 1 2 3 4; do for i in 1 2 3 4 5 6 7 8 9 10 11 12; do input keyevent 22; sleep 0.12; done; input keyevent 20; sleep 0.12; done; for i in 1 2 3 4; do input keyevent 19; sleep 0.12; done'
sleep 2
adb logcat -d >"$out/logcat-scroll.txt" || true
adb shell dumpsys gfxinfo $PKG | tr -d '\r' >"$out/gfxinfo.txt" || true

phase "meminfo"
adb shell dumpsys meminfo $PKG | tr -d '\r' >"$out/meminfo.txt" || true
adb shell am force-stop $PKG

# --- report -----------------------------------------------------------------
OUT="$out" ROOT="$root" REQ="$requests_before" SEEDED="$seeded" python3 - <<'PY'
import json, os, re, statistics, sys

out, root = os.environ["OUT"], os.environ["ROOT"]

def ms(s):
    m = re.search(r"\+(?:(\d+)s)?(\d+)ms", s)
    return int(m.group(1) or 0) * 1000 + int(m.group(2)) if m else None

fully = []
for line in open(f"{out}/coldstarts.txt"):
    n, _, rest = line.partition(" ")
    v = ms(rest) if "MISSING" not in rest else None
    fully.append((int(n), v))
runs = [v for n, v in fully if n > 1 and v is not None]  # the first start is discarded
median = int(statistics.median(runs)) if runs else None

def num(pat, text, cast=int):
    m = re.search(pat, text)
    return cast(m.group(1)) if m else None

gfx = open(f"{out}/gfxinfo.txt").read()
mem = open(f"{out}/meminfo.txt").read()
scroll = open(f"{out}/logcat-scroll.txt").read()
frames = [l for l in scroll.splitlines() if "CHITHRAM_FRAMES" in l]
jank32 = len([l for l in scroll.splitlines() if "CHITHRAM_JANK" in l])
probe_frames = sum(num(r"n=(\d+)", l) or 0 for l in frames)
over16 = sum(num(r"over16=(\d+)", l) or 0 for l in frames)
pss_kb = num(r"TOTAL PSS:\s+(\d+)", mem) or num(r"TOTAL\s+(\d+)", mem)

result = {
    "coldstart_fully_drawn_ms": [v for _, v in fully],
    "coldstart_fully_drawn_ms_median": median,
    "requests_before_first_frame": int(os.environ["REQ"]),
    "seeded_home_refreshed": os.environ["SEEDED"] == "true",
    "jank_frames_build_over_32ms": jank32,
    "probe_frames": probe_frames,
    "probe_frames_over_16ms": over16,
    "gfxinfo_total_frames": num(r"Total frames rendered:\s+(\d+)", gfx),
    "gfxinfo_janky_frames": num(r"Janky frames:\s+(\d+)", gfx),
    "gfxinfo_p90_ms": num(r"90th percentile:\s+(\d+)ms", gfx),
    "gfxinfo_p99_ms": num(r"99th percentile:\s+(\d+)ms", gfx),
    "pss_mb": round(pss_kb / 1024, 1) if pss_kb else None,
}
json.dump(result, open(f"{out}/perf.json", "w"), indent=2)

budget = json.load(open(f"{root}/.github/perf-budget.json"))
checks = [
    ("coldstart_fully_drawn_ms_median", "Cold start to Home (median of %d, ms)" % len(runs)),
    ("jank_frames_build_over_32ms", "Scroll frames with UI build > 32 ms"),
    ("pss_mb", "PSS after scroll (MB)"),
    ("requests_before_first_frame", "Requests before first frame"),
]
rows, misses = [], []
for key, label in checks:
    got, limit = result[key], budget.get(key)
    ok = got is not None and limit is not None and got <= limit
    if not ok:
        misses.append(label)
    rows.append((label, "n/a" if got is None else got, limit, "ok" if ok else "OVER BUDGET"))

lines = [f"### Performance (TV emulator, release x86_64, mode: {budget['mode']})", "",
         "| Metric | Measured | Budget | |", "|---|---|---|---|"]
lines += [f"| {a} | {b} | {c} | {d} |" for a, b, c, d in rows]
lines += ["", "Cold starts (Fully drawn, ms; the first is discarded): " +
          ", ".join("n/a" if v is None else str(v) for _, v in fully),
          f"Probe frames: {probe_frames}, over 16 ms: {over16}. gfxinfo: {result['gfxinfo_total_frames']} frames, "
          f"{result['gfxinfo_janky_frames']} janky, p90 {result['gfxinfo_p90_ms']} ms, p99 {result['gfxinfo_p99_ms']} ms "
          "(software rendering: raster time is report-only).",
          f"Seed saw CHITHRAM_HOME_REFRESHED: {result['seeded_home_refreshed']}."]
text = "\n".join(lines)
print(text)
summary = os.environ.get("GITHUB_STEP_SUMMARY")
if summary:
    open(summary, "a").write(text + "\n")
if misses:
    msg = "over budget: " + "; ".join(misses)
    if budget["mode"] == "enforce":
        print(f"::error::{msg}")
        sys.exit(1)
    print(f"::warning::{msg} (report mode)")
PY
