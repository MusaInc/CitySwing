#!/usr/bin/env bash
# Genuine App Store screenshots: the real game (autopilot run, HUD on) rendered
# at an exact store size under Xvfb (software Vulkan, Mobile renderer).
#   tools/store_shots.sh <outdir> <WxH> <name> "<t1,t2,...>" [extra game args...]
set -euo pipefail
cd "$(dirname "$0")/.."
out=$1; res=$2; name=$3; times=$4; shift 4
w=${res%x*}; h=${res#*x}
mkdir -p "$out"
xvfb-run -a -s "-screen 0 $((w + 64))x$((h + 64))x24" godot --rendering-method mobile --resolution "$res" \
  --fixed-fps 30 -- --shot="$PWD/$out/${name}.png" --shot-at="$times" "$@" 2>&1 \
  | grep -E "SCREENSHOT|SCRIPT ERROR" || true
