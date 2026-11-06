#!/usr/bin/env bash
# Gallery v3 hero photography: bash tools/marketing/hero_shots.sh <out> <WxH> [ids]
set -euo pipefail
cd "$(dirname "$0")/../.."
out=${1:-store/marketing/v3/scout}
resolution=${2:-1434x660}
selection=${3:-}
mkdir -p "$out"
git rev-parse HEAD > "$out/source-revision.txt"
xvfb-run -a -s "-screen 0 ${resolution}x24" godot --rendering-method mobile --resolution "$resolution" --fixed-fps 30 -s res://tools/marketing/hero_shots.gd -- --mode=free --quality=2 --look=clean --seed=1207 --time=16 --weather=clear --save="user://marketing-v3.json" --photo-out="$out" --photo-family=action --photo-select="$selection" > "$out/capture.log" 2>&1
if grep -qE 'SCRIPT ERROR|Parse Error|Assertion failed' "$out/capture.log"; then cat "$out/capture.log" | grep -E -A3 'ERROR|Parse|Assert' | head -40; exit 1; fi
grep -E 'PHOTO|REJECT' "$out/capture.log"
