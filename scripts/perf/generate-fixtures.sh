#!/bin/bash
# Generate small looping clips for scripts/perf/measure.sh.
# Requires ffmpeg. Does not commit the binaries.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${LIVELY_PERF_FIXTURES:-$ROOT/perf/fixtures}"
mkdir -p "$OUT"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "generate-fixtures: ffmpeg not found. Install it (e.g. brew install ffmpeg)." >&2
  exit 1
fi

make_clip() {
  local name="$1"
  shift
  local dest="$OUT/$name"
  if [[ -f "$dest" ]]; then
    echo "exists: $dest"
    return
  fi
  echo "generating: $dest"
  ffmpeg -hide_banner -loglevel error -y "$@" "$dest"
}

# 2-second patterns, hardware-friendly tags (hvc1 / avc1).
make_clip "1080p30-hevc-silent.mp4" \
  -f lavfi -i "testsrc2=size=1920x1080:rate=30" -t 2 \
  -c:v libx265 -pix_fmt yuv420p -tag:v hvc1 -an -g 30

make_clip "1080p30-hevc-audio.mp4" \
  -f lavfi -i "testsrc2=size=1920x1080:rate=30" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000" -t 2 \
  -c:v libx265 -pix_fmt yuv420p -tag:v hvc1 -c:a aac -ac 2 -shortest -g 30

make_clip "1080p30-h264-silent.mp4" \
  -f lavfi -i "testsrc2=size=1920x1080:rate=30" -t 2 \
  -c:v libx264 -pix_fmt yuv420p -tag:v avc1 -an -g 30

make_clip "4k60-hevc-silent.mp4" \
  -f lavfi -i "testsrc2=size=3840x2160:rate=60" -t 2 \
  -c:v libx265 -pix_fmt yuv420p -tag:v hvc1 -an -g 60

echo "fixtures in $OUT"
ls -lh "$OUT"/*.mp4
