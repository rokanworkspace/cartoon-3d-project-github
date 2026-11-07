#!/usr/bin/env bash
# GPU benchmark for BridgeShort on a rented GPU box (e.g. Hostinger RTX 4090).
#
# Purpose: answer ONE question cheaply — how fast does a real GPU draw our
# three.js/WebGL frames through headless Chromium (Remotion --gl angle)?
# Local baseline (no GPU, SwiftShader): ~26 s/frame, 2,025 frames ≈ 15 h.
#
# Usage on a FRESH Ubuntu GPU instance (root SSH, instance clock is billing!):
#   git clone <this repo> && cd cartoon-3d-project   # or rsync the project up
#   bash scripts/gpu-benchmark.sh                    # setup + 30-frame bench
#   FRAMES=0-269 bash scripts/gpu-benchmark.sh       # bigger sample
#
# The script is idempotent: setup steps are skipped when already done.
# IMPORTANT billing hygiene (Hostinger): the instance is billed per started
# hour while it EXISTS. Download results, then DELETE the instance.
set -eu
cd "$(dirname "$0")/.."
FRAMES="${FRAMES:-0-29}"
GL="${GL:-angle}"   # try 'angle' first; fallback: GL=egl

echo "=== 0. GPU check ==="
if command -v nvidia-smi >/dev/null; then nvidia-smi; else
  echo "WARNING: nvidia-smi not found — is this really a GPU instance?"
fi

echo "=== 1. Node.js 20 ==="
if ! command -v node >/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi
node --version

echo "=== 2. Chromium system libraries + ffmpeg ==="
if [ ! -f .gpu-bench-deps-done ]; then
  apt-get update
  apt-get install -y \
    libnss3 libdbus-1-3 libatk1.0-0 libatk-bridge2.0-0 libcups2 \
    libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 \
    libxrandr2 libgbm1 libasound2t64 libpango-1.0-0 libcairo2 \
    libatspi2.0-0 libgtk-3-0 ffmpeg
  touch .gpu-bench-deps-done
fi

echo "=== 3. Project dependencies ==="
[ -d node_modules ] || npm ci

echo "=== 4. Benchmark: frames $FRAMES with --gl $GL ==="
mkdir -p out/bench
start=$(date +%s)
npx remotion render src/index.ts BridgeShort out/bench/bench.mp4 \
  --codec h264 --crf 16 --frames="$FRAMES" --gl "$GL" \
  --concurrency 1 --timeout 600000
end=$(date +%s)

first="${FRAMES%-*}"; last="${FRAMES#*-}"
count=$((last - first + 1))
elapsed=$((end - start))
echo
echo "=============================================================="
echo "BENCHMARK RESULT"
echo "  frames rendered : $count  (range $FRAMES, gl=$GL)"
echo "  elapsed         : ${elapsed}s"
awk -v e="$elapsed" -v c="$count" 'BEGIN {
  spf = e / c
  printf "  seconds per frame: %.2f\n", spf
  printf "  projected full render (2025 frames, concurrency 1): %.1f min\n", spf * 2025 / 60
  printf "  (local SwiftShader baseline: ~26 s/frame, ~15 h)\n"
}'
echo "=============================================================="
echo "If seconds/frame is dramatically lower than 26, the GPU route works:"
echo "  full render: npx remotion render src/index.ts BridgeShort out/bridge.mp4 \\"
echo "    --codec h264 --crf 16 --gl $GL --concurrency 2 --timeout 600000"
echo "Then download out/ and DELETE the instance to stop billing."
