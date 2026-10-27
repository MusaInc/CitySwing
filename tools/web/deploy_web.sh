#!/usr/bin/env bash
# Temporary browser-test build: Godot web export (Compatibility renderer,
# single-threaded) served privately at https://musastudios.co.uk/cityswing/
# behind the workspace sign-in (Caddy route serves /srv/cityswing).
# Does not touch the iOS preset or build/ios.
set -euo pipefail
cd "$(dirname "$0")/../.."
rm -rf build/web && mkdir -p build/web
godot --headless --export-release "Web" build/web/index.html 2>&1 | grep -E "^ERROR" | grep -v "resources still" || true
test -f build/web/index.wasm || { echo "web export failed"; exit 1; }
rm -rf /srv/cityswing/* && cp -a build/web/. /srv/cityswing/
# Pre-compress the wasm and js (Caddy serves the .gz). Never the pck.
gzip -9 -k -f /srv/cityswing/index.wasm /srv/cityswing/index.js
echo "Deployed: https://musastudios.co.uk/cityswing/  ($(du -sh /srv/cityswing | cut -f1) on disk)"
