#!/usr/bin/env bash
# Writes the test media into $1 (default fixtures): a 1080p H.264 video-only
# mp4, an AAC audio-only m4a (both 60 s, like a YouTube DASH pair), and a short
# two-rung HLS ladder (1080p + 480p, 2 s segments).
set -euo pipefail
out=${1:-fixtures}
mkdir -p "$out/hls"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc2=size=1920x1080:rate=30" -t 60 \
  -c:v libx264 -preset veryfast -profile:v high -level 4.1 -pix_fmt yuv420p -g 60 -an \
  -movflags +faststart "$out/video.mp4"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "sine=frequency=440:sample_rate=48000" -t 60 \
  -c:a aac -b:a 96k -movflags +faststart "$out/audio.m4a"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc2=size=1920x1080:rate=30" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000" -t 60 \
  -filter_complex "[0:v]split=2[hi][lo0];[lo0]scale=854:480[lo]" \
  -map "[hi]" -map 1:a -map "[lo]" -map 1:a \
  -c:v libx264 -preset veryfast -pix_fmt yuv420p -g 60 -sc_threshold 0 -c:a aac -b:a 96k \
  -b:v:0 4M -b:v:1 1M \
  -f hls -hls_time 2 -hls_playlist_type vod -master_pl_name master.m3u8 \
  -var_stream_map "v:0,a:0 v:1,a:1" \
  -hls_segment_filename "$out/hls/v%v_%03d.ts" "$out/hls/v%v.m3u8"

ls -laR "$out"
for f in video.mp4 audio.m4a; do
  echo "$f duration: $(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out/$f")"
done
