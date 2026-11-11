#!/bin/bash
set -euo pipefail
out="$RUNNER_TEMP/cityswing-ios-smoke"
mkdir -p "$out"
xcode=$(ls -d /Applications/Xcode_26*.app | sort -V | tail -1)
sudo xcode-select -s "$xcode/Contents/Developer"
xcodebuild -version
base="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable"
curl -fsSL --retry 3 -o "$RUNNER_TEMP/godot.zip" "$base/Godot_v${GODOT_VERSION}-stable_macos.universal.zip"
curl -fsSL --retry 3 -o "$RUNNER_TEMP/templates.tpz" "$base/Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
unzip -q "$RUNNER_TEMP/godot.zip" -d "$RUNNER_TEMP/godot"
unzip -q "$RUNNER_TEMP/templates.tpz" -d "$RUNNER_TEMP/templates"
dest="$HOME/Library/Application Support/Godot/export_templates/${GODOT_VERSION}.stable"
mkdir -p "$dest"
cp -R "$RUNNER_TEMP/templates/templates/." "$dest/"
godot="$RUNNER_TEMP/godot/Godot.app/Contents/MacOS/Godot"
cd candidate
# Required by the exporter; the simulator build is explicitly unsigned.
sed -i '' 's/^application\/app_store_team_id=.*/application\/app_store_team_id="SIMULATOR1"/' export_presets.cfg
mkdir -p build/ios
"$godot" --headless --editor --import --quit > "$out/import.log" 2>&1
"$godot" --headless --export-release iOS build/ios/CitySwing.ipa > "$out/export.log" 2>&1
xcodebuild -project build/ios/CitySwing.xcodeproj -scheme CitySwing -configuration Release \
 -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
 -derivedDataPath "$RUNNER_TEMP/cityswing-derived" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO EXCLUDED_ARCHS= \
 build > "$out/build.log" 2>&1
app="$RUNNER_TEMP/cityswing-derived/Build/Products/Release-iphonesimulator/CitySwing.app"
test -d "$app"
xcrun simctl list devices available -j > "$out/devices.json"
python3 - "$out/devices.json" "$out/selected.tsv" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))['devices']
choices=[]
for runtime,devices in sorted(r.items(),reverse=True):
 if 'iOS-26' not in runtime: continue
 for family in ['iPhone','iPad']:
  ds=[d for d in devices if d['isAvailable'] and family in d['name']]
  if ds: choices.append((family,ds[0]['udid'],ds[0]['name'],runtime))
 if len(choices)==2: break
assert len(choices)==2,choices
open(sys.argv[2],'w').write(''.join('\t'.join(d)+'\n' for d in choices))
PY
failed=0
while IFS=$'\t' read -r family udid name runtime; do
 echo "Testing $name on $runtime"
 xcrun simctl boot "$udid"
 xcrun simctl bootstatus "$udid" -b
 xcrun simctl install "$udid" "$app"
 # This is a new simulator installation: no settings or saved game.
 xcrun simctl launch --terminate-running-process --stdout="$out/$family.stdout.log" --stderr="$out/$family.stderr.log" \
  "$udid" com.musastudios.cityswing > "$out/$family.launch.txt"
 cat "$out/$family.launch.txt"
 pid=$(awk '{print $NF}' "$out/$family.launch.txt")
 for iteration in $(seq 1 12); do
  sleep 5
  if ! ps -p "$pid" -o pid=,rss=,etime= >> "$out/$family.process.txt"; then
   echo "$family exited during startup" | tee -a "$out/result.txt"
   failed=1
   break
  fi
  if [ "$iteration" = 4 ] || [ "$iteration" = 12 ]; then
   xcrun simctl io "$udid" screenshot "$out/$family-$iteration.png"
  fi
 done
 xcrun simctl spawn "$udid" log show --last 3m --style compact --predicate 'process == "CitySwing"' > "$out/$family.system.log" 2>&1 || true
 xcrun simctl terminate "$udid" com.musastudios.cityswing || true
 xcrun simctl shutdown "$udid"
done < "$out/selected.tsv"
mkdir -p "$out/crashes"
find "$HOME/Library/Logs/DiagnosticReports" -name '*CitySwing*' -type f -exec cp '{}' "$out/crashes/" \; || true
printf 'Simulator startup failures: %s\n' "$failed" | tee -a "$out/result.txt"
exit "$failed"
