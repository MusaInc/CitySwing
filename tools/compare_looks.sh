#!/usr/bin/env bash
# Renders the same autopilot flight once per post-process look and tiles the
# frames into a grid (rows = times, columns = looks) for side-by-side review.
#   tools/compare_looks.sh <name> "<t1,t2,...>" "<look1 look2 ...>" [extra user args...]
# Output: screenshots/<name>_grid.png
set -euo pipefail
cd "$(dirname "$0")/.."
name=$1; times=$2; looks=$3; shift 3
for l in $looks; do
  tools/filmstrip.sh "${name}-$l" "$times" --look="$l" "$@" >/dev/null 2>&1 || true
done
python3 - "$name" "$times" $looks <<'PY'
import subprocess, sys, os
name, times, looks = sys.argv[1], sys.argv[2].split(","), sys.argv[3:]
rows = [[f"screenshots/{name}-{l}_{i}.png" if len(times) > 1 else f"screenshots/{name}-{l}.png"
         for l in looks] for i in range(len(times))]
frames = [f for r in rows for f in r if os.path.exists(f)]
cols = len(looks)
cells, fc = [], ""
for i, f in enumerate(frames):
    c, r = i % cols, i // cols
    x = "+".join(["w0"] * c) or "0"
    y = "+".join(["h0"] * r) or "0"
    cells.append(f"{x}_{y}")
    fc += f"[{i}:v]scale=480:-1,drawtext=text='{looks[c]}':x=8:y=8:fontsize=18:fontcolor=white:box=1:boxcolor=black@0.5[s{i}];"
fc += "".join(f"[s{i}]" for i in range(len(frames)))
fc += f"xstack=inputs={len(frames)}:layout={'|'.join(cells)}:fill=black"
inputs = sum((["-i", f] for f in frames), [])
out = f"screenshots/{name}_grid.png"
subprocess.run(["ffmpeg", "-loglevel", "error", "-y", *inputs, "-filter_complex", fc, out], check=True)
print("GRID", out)
PY
