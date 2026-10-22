#!/usr/bin/env bash
# Synthetic poster and backdrop JPEGs for the TMDB fixtures (ffmpeg only).
#
#   make_images.sh <out-dir> [count]
#
# Writes <out-dir>/t/p/<bucket>/fixture_poster_<n>.jpg and fixture_backdrop_<n>.jpg
# for n = 1..count (default 40), in the TMDB size buckets the app asks for, so
# serving <out-dir> as the image host answers every tmdbPoster/tmdbBackdrop URL.
# Each image is a test pattern with its own hue; no real artwork.
set -euo pipefail

out=${1:?usage: make_images.sh <out-dir> [count]}
count=${2:-40}

poster_buckets="92:138 154:231 185:278 342:513 500:750 780:1170"       # width:height (2:3)
backdrop_buckets="300:169 780:439 1280:720"                              # 16:9

make() { # name width height hue
  local file=$1 w=$2 h=$3 hue=$4
  ffmpeg -hide_banner -loglevel error -y -f lavfi -i "testsrc2=size=${w}x${h}:rate=1" \
    -vf "hue=h=${hue}" -frames:v 1 -q:v 5 "$file"
}

for n in $(seq 1 "$count"); do
  hue=$(( (n * 37) % 360 ))
  for b in $poster_buckets; do
    w=${b%%:*}; h=${b##*:}
    mkdir -p "$out/t/p/w$w"
    make "$out/t/p/w$w/fixture_poster_$n.jpg" "$w" "$h" "$hue"
  done
  for b in $backdrop_buckets; do
    w=${b%%:*}; h=${b##*:}
    mkdir -p "$out/t/p/w$w"
    make "$out/t/p/w$w/fixture_backdrop_$n.jpg" "$w" "$h" "$hue"
  done
done
echo "wrote $(find "$out/t" -name '*.jpg' | wc -l) images under $out/t/p"
