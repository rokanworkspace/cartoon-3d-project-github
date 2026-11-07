#!/usr/bin/env bash
# Full-length BridgeShort render, chunked so a crash/OOM only loses one chunk.
# Measured on this VM (4 cores, 7 GB RAM, no GPU; WebGL via SwiftShader):
#   ~26 s/frame at --concurrency 1  =>  2025 frames ≈ 15 h total.
#   --concurrency 4 OOM-crashes Chrome ("ran out of memory") — do not raise it.
# Usage:  bash scripts/render-full-chunks.sh
# Resume: re-run; finished chunks are skipped. When all 8 chunks exist, they are
# concatenated into out/bridge/video.mp4 (silent picture). Then mux the audio:
#   ffmpeg -i out/bridge/video.mp4 -i ../bridge-short/audio/mix.wav \
#     -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 192k out/bridge/final.mp4
set -u
cd "$(dirname "$0")/.."
export TEMP="$PWD/remotion-tmp" TMP="$PWD/remotion-tmp" REMOTION_TMP="$PWD/remotion-tmp"
mkdir -p out/chunks
CHUNKS=("0-269" "270-539" "540-809" "810-1079" "1080-1349" "1350-1619" "1620-1889" "1890-2024")
i=0
for range in "${CHUNKS[@]}"; do
  i=$((i + 1))
  out="out/chunks/chunk_${i}.mp4"
  if [ -s "$out" ]; then echo "skip $out (exists)"; continue; fi
  echo "=== chunk $i frames $range $(date) ==="
  npx remotion render src/index.ts BridgeShort "$out" --codec h264 --crf 16 \
    --frames="$range" --gl swangle --concurrency 1 --timeout 600000 || {
      echo "CHUNK $i FAILED — re-run this script to resume"; exit 1; }
done
# concat (same codec/params, silent picture)
: > out/chunks/list.txt
for f in out/chunks/chunk_*.mp4; do echo "file '$PWD/$f'" >> out/chunks/list.txt; done
ffmpeg -y -v error -f concat -safe 0 -i out/chunks/list.txt -c copy out/bridge/video.mp4
echo "DONE: out/bridge/video.mp4"
