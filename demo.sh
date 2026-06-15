#!/usr/bin/env bash
# Build demo.gif from the two demo tapes (gameplay loop + veteran stats ladder).
# Requires: vhs, ffmpeg.
set -euo pipefail
cd "$(dirname "$0")"

vhs demo_play.tape
vhs demo_stats.tape

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf "file '%s/demo_play.mp4'\nfile '%s/demo_stats.mp4'\n" "$PWD" "$PWD" > "$tmp/list.txt"

# Concat (re-encode — vhs clips can differ in SPS/PPS, so copy isn't safe)
ffmpeg -y -loglevel error -f concat -safe 0 -i "$tmp/list.txt" \
  -vf "fps=24,format=yuv420p" "$tmp/combined.mp4"

# High-quality gif via per-clip palette
ffmpeg -y -loglevel error -i "$tmp/combined.mp4" \
  -vf "fps=24,scale=1200:-1:flags=lanczos,palettegen=stats_mode=diff" "$tmp/pal.png"
ffmpeg -y -loglevel error -i "$tmp/combined.mp4" -i "$tmp/pal.png" \
  -lavfi "fps=24,scale=1200:-1:flags=lanczos,paletteuse=dither=bayer:bayer_scale=3" demo.gif

rm -f demo_play.mp4 demo_stats.mp4
echo "demo.gif: $(du -h demo.gif | cut -f1)"
