#!/usr/bin/env bash
# Runs on the Android TV emulator (CI). Usage: emulator_check.sh APK OUTDIR
# Fixtures must be served on the host's 127.0.0.1:8000. Numbers are emulator-only.
set -uo pipefail

apk=$1
out=${2:-emu-out}
pkg=dev.chithram.chithram
mkdir -p "$out"
summary="$out/summary.txt"
: >"$summary"
failed=0

log() { echo "$*" | tee -a "$summary"; }
check() { # name, ok(0/1), detail
  if [[ $2 == 0 ]]; then log "PASS $1 ($3)"; else log "FAIL $1 ($3)"; failed=1; fi
}
plog() { adb logcat -d -s ChithramPlayer:I 2>/dev/null | tr -d '\r'; }
count() { plog | grep -c -E "$1" || true; }
# wait_for PATTERN SECONDS -> prints the first matching line
wait_for() {
  local i=0
  while (( i < $2 * 4 )); do
    local l
    l=$(plog | grep -E "$1" | head -1 || true)
    if [[ -n $l ]]; then echo "$l"; return 0; fi
    sleep 0.25; i=$((i + 1))
  done
  return 1
}
wait_count() { # PATTERN MIN SECONDS
  local i=0
  while (( i < $3 * 4 )); do
    if (( $(count "$1") >= $2 )); then return 0; fi
    sleep 0.25; i=$((i + 1))
  done
  return 1
}
num() { sed -E 's/.*[ =]([0-9]+)$/\1/' <<<"$1"; }

adb reverse tcp:8000 tcp:8000
adb install -r -g "$apk"
adb shell wm size || true

launch() { # name, video, audio
  adb shell am force-stop "$pkg"
  adb logcat -c
  local args=(--es route /spike/player --es video_url "$2")
  [[ -n ${3:-} ]] && args+=(--es audio_url "$3")
  adb shell am start -W -n "$pkg/.MainActivity" "${args[@]}" >/dev/null
}

# ---- Warm-up: the very first open pays for codec and class loading on a cold
# emulator. Report it, but assert on the second (warm) open.
log "== warm-up: video.mp4 + audio.m4a"
launch warmup http://127.0.0.1:8000/video.mp4 http://127.0.0.1:8000/audio.m4a
ff=$(wait_for 'CHITHRAM_FIRST_FRAME' 60) || ff=""
[[ -n $ff ]] && log "INFO cold first frame $(num "$ff") ms (emulator-only, not asserted)"
sleep 2

# ---- Case A: progressive video + separate audio, merged (YouTube DASH shape).
log "== merged: video.mp4 + audio.m4a"
launch merged http://127.0.0.1:8000/video.mp4 http://127.0.0.1:8000/audio.m4a
ff=$(wait_for 'CHITHRAM_FIRST_FRAME' 60) || ff=""
if [[ -n $ff ]]; then
  ms=$(num "$ff")
  check "first frame < 2500 ms" $(( ms < 2500 ? 0 : 1 )) "${ms} ms, emulator-only"
else
  check "first frame appears" 1 "no CHITHRAM_FIRST_FRAME in 60 s"
fi
dur=$(wait_for 'CHITHRAM_DURATION' 20) || dur=""
if [[ -n $dur ]]; then
  d=$(num "$dur")
  check "merged duration ~60000 ms" $(( d >= 59000 && d <= 61000 ? 0 : 1 )) "${d} ms"
else
  check "duration logged" 1 "none"
fi
tr_line=$(plog | grep 'CHITHRAM_TRACKS' | tail -1 || true)
check "video and audio tracks selected" $([[ $tr_line == *"video=1 audio=1"* ]] && echo 0 || echo 1) "${tr_line:-none}"
sleep 3
adb exec-out screencap -p >"$out/merged-playing.png" || true

# DPAD_CENTER (23) pauses, again resumes.
before=$(count 'PLAY_WHEN_READY false')
adb shell input keyevent KEYCODE_DPAD_CENTER
wait_count 'PLAY_WHEN_READY false' $((before + 1)) 8 && r=0 || r=1
check "DPAD_CENTER pauses" $r "PLAY_WHEN_READY false x$(count 'PLAY_WHEN_READY false')"
sleep 1
adb exec-out screencap -p >"$out/merged-paused.png" || true
before=$(count 'PLAY_WHEN_READY true')
adb shell input keyevent KEYCODE_DPAD_CENTER
wait_count 'PLAY_WHEN_READY true' $((before + 1)) 8 && r=0 || r=1
check "DPAD_CENTER resumes" $r "PLAY_WHEN_READY true x$(count 'PLAY_WHEN_READY true')"

# DPAD_RIGHT seeks +10 s; the seek is done when playback runs past the target.
sleep 1
adb shell input keyevent KEYCODE_DPAD_RIGHT
sd=$(wait_for 'CHITHRAM_SEEK_DONE' 15) || sd=""
if [[ -n $sd ]]; then
  p=$(sed -E 's/.*pos=([0-9]+).*/\1/' <<<"$sd")
  check "seek completes at >= 10000 ms" $(( p >= 10000 ? 0 : 1 )) "$sd"
else
  check "seek completes" 1 "no CHITHRAM_SEEK_DONE in 15 s"
fi
sleep 1
adb exec-out screencap -p >"$out/merged-after-seek.png" || true
plog >"$out/player-merged.log"
adb logcat -d | grep -E "CHITHRAM_PAGE|flutter" | tail -15 | tee -a "$summary" || true
adb logcat -d >"$out/logcat-merged.txt" || true

# ---- Case B: HLS ladder.
log "== hls: master.m3u8"
launch hls http://127.0.0.1:8000/hls/master.m3u8
ff=$(wait_for 'CHITHRAM_FIRST_FRAME' 60) || ff=""
if [[ -n $ff ]]; then
  ms=$(num "$ff")
  log "INFO hls first frame ${ms} ms (emulator-only)"
  check "hls first frame < 5000 ms" $(( ms < 5000 ? 0 : 1 )) "${ms} ms"
else
  check "hls first frame appears" 1 "none in 60 s"
fi
dur=$(wait_for 'CHITHRAM_DURATION' 20) || dur=""
if [[ -n $dur ]]; then
  d=$(num "$dur")
  check "hls duration ~60000 ms" $(( d >= 58000 && d <= 62000 ? 0 : 1 )) "${d} ms"
else
  check "hls duration logged" 1 "none"
fi
sleep 3
adb exec-out screencap -p >"$out/hls-playing.png" || true
plog >"$out/player-hls.log"
adb logcat -d >"$out/logcat-hls.txt" || true

if adb logcat -d | grep -q 'FATAL EXCEPTION'; then
  log "FAIL no crash (FATAL EXCEPTION in logcat)"; failed=1
fi
exit $failed
