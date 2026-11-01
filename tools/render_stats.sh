#!/usr/bin/env bash
# Render cost at fixed views (draw calls, triangles, objects, memory) under
# Xvfb, Mobile renderer. Views re-picked for the organic-road island (2026-11-01):
# street = Diagonal boulevard at kerb height, cross = Spine roundabout.
# Device-independent numbers – compare before/after.
#   tools/render_stats.sh [quality 0-2] [extra user args...]
set -euo pipefail
cd "$(dirname "$0")/.."
q=${1:-2}; shift || true
mkdir -p screenshots/stats
views=(
  "street:499.4,23.7,-173.9,565.2,25,-219.3"
  "cross:600,28,-30,575,22,10"
  "swing:520,70,-40,560,40,-180"
  "aerial:200,260,200,560,0,-200"
)
for v in "${views[@]}"; do
  n=${v%%:*}; c=${v#*:}
  xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-method mobile --resolution 960x540 --fixed-fps 30 -- \
    --cam=$c --nohud --quality=$q --stats --shot="$PWD/screenshots/stats/${n}_q$q.png" --shot-at=3 "$@" 2>&1 \
    | grep -E "RENDER_STATS|SCRIPT ERROR" || true
done
