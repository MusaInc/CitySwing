#!/usr/bin/env bash
# Fixed-camera tour of the city for before/after review (Xvfb, Mobile renderer).
# Each view: name:cam_x,cam_y,cam_z,look_x,look_y,look_z (absolute metres).
#   tools/world_tour.sh <out_dir> [name ...]   (no names = all views)
set -uo pipefail
cd "$(dirname "$0")/.."
out=${1:?out dir}; shift || true
mkdir -p "$out"
views=(
  "overview:150,420,780,560,0,-60"
  "cbd_street:470,24,-195,560,40,-260"
  "cbd_air:330,140,-60,520,20,-260"
  "bridge_side:-180,30,160,-150,25,-15"
  "bridge_approach:-20,30,60,60,10,-15"
  "west_quay:60,8,110,60,6,-120"
  "midtown_block:620,90,180,690,15,80"
  "docks:150,40,520,260,0,380"
  "old_town:830,70,-40,930,40,-150"
  "rail:520,30,420,640,8,350"
  "east_coast:1150,40,100,1000,20,-50"
  "heights:620,60,-560,720,36,-450"
  "rooftops:420,180,-120,540,120,-260"
  "mainland:-420,60,160,-300,10,-20"
)
want=" $* "
pids=()
for v in "${views[@]}"; do
  n=${v%%:*}; c=${v#*:}
  if [ $# -gt 0 ] && [[ "$want" != *" $n "* ]]; then continue; fi
  xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-method mobile --resolution 1280x720 --fixed-fps 30 -- \
    --cam=$c --nohud --quality=2 --stats --shot="$out/$n.png" --shot-at=3 > "$out/$n.log" 2>&1 &
  pids+=($!)
  if [ ${#pids[@]} -ge ${JOBS:-4} ]; then wait "${pids[0]}"; pids=("${pids[@]:1}"); fi
done
wait
grep -h RENDER_STATS "$out"/*.log || true
