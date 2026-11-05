#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=${1:-screenshots/cleanup/final}
mkdir -p "$out"
case ${2:-world} in
 world)
  timeout 600 xvfb-run -a godot --rendering-method mobile --resolution 960x540 --fixed-fps 30 -s res://tools/cleanup_review.gd -- --mode=free --touch --time=15 --weather=clear --quality=2 --review-out="$out" > "$out/review.log" 2>&1 ;;
 hero)
  timeout 600 xvfb-run -a godot --rendering-method mobile --resolution 640x480 --fixed-fps 30 -s res://tools/pose_lab.gd -- "$out" idle,run,jump,swingfast,land > "$out/hero.log" 2>&1 ;;
 gameplay)
  timeout 600 xvfb-run -a godot --rendering-method mobile --resolution 1520x720 --fixed-fps 30 -s res://tools/cleanup_gameplay.gd -- --mode=free --touch --time=15 --weather=clear --quality=1 --review-out="$out" > "$out/gameplay.log" 2>&1 ;;
 collision)
  timeout 600 xvfb-run -a godot --rendering-method mobile --resolution 320x240 -s res://tools/collision_audit.gd -- 6 city > "$out/collision.log" 2>&1 ;;
 *) exit 2 ;;
esac

if rg -q "SCRIPT ERROR|Parse Error|GAMEPLAY FAIL|no visual geometry" "$out"/*.log; then
 exit 1
fi
