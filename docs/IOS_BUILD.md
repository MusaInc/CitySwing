# Building City Swing for iPhone / TestFlight

The Linux VPS **cannot** compile, sign or upload an iOS app. It produces the
complete Xcode project; the final build happens on a Mac.

## 1. On the VPS: export the Xcode project

```
IOS_TEAM_ID=<your 10-character Apple team ID> tools/export_ios.sh
```

Output: `build/ios/CitySwing.xcodeproj` (+ `CitySwing.xcframework`,
`MoltenVK.xcframework`, `CitySwing.pck`), zipped as
`build/CitySwing-ios-xcode.zip` (~105 MB). Without `IOS_TEAM_ID` the script
uses the placeholder team `PLACEHOLDR`; you then set the team in Xcode (step 3).

Preset (`export_presets.cfg`, "iOS"):

| Setting | Value |
|---|---|
| Bundle ID | `com.musastudios.cityswing` (change if needed) |
| Version | 0.1.0 (build 1) |
| Minimum iOS | 15.0 |
| Architecture | arm64 |
| Renderer | Mobile (Metal via MoltenVK) |
| Orientation | sensor landscape |
| Icon | `assets/icon_1024.png` (rendered from the game) |
| Launch screen | solid `#0D0F17` |

Copy the zip to the Mac, e.g. `scp vps:~/workspace/projects/CitySwing/build/CitySwing-ios-xcode.zip .`

## 2. Mac prerequisites

- macOS with **Xcode 16** or newer, signed in to your Apple Developer account
  (Xcode → Settings → Accounts).
- An App ID for the bundle ID, and an app record in App Store Connect
  (My Apps → + → New App) using the same bundle ID.
- Optional: install Godot 4.5.1 on the Mac too. Then you can run
  `tools/export_ios.sh` there, or export with *Export Project* turned off to
  get an `.ipa` straight from Godot.

## 3. Build, run on device, archive

1. Unzip and open `ios/CitySwing.xcodeproj`.
2. Target **CitySwing → Signing & Capabilities**: tick *Automatically manage
   signing*, choose your **Team** (this replaces the placeholder), and confirm
   the bundle ID.
3. Plug in the iPhone, select it as the run destination, **Product → Run**.
   Use a *Release* build configuration for performance testing
   (Product → Scheme → Edit Scheme → Run → Build Configuration → Release).
4. **Product → Archive** → Organizer → **Distribute App → App Store Connect →
   Upload**. Once processed (5–30 min) the build appears under TestFlight.
5. In App Store Connect → TestFlight: answer export compliance (the game uses
   no non-exempt encryption) and add internal testers.

## 4. Profile on the device (required, not yet done)

Desktop and headless numbers say nothing about iPhone performance. On the
device:

1. **Settings → Run 45 s benchmark**. It flies a fixed autopilot route through
   the densest district and reports average FPS, 1%-worst and worst frame
   times, frames over 33 ms, draw calls, primitives and CPU process/physics
   time. Results are appended to `benchmark.json` in the app's data folder.
   Run it at Low, Medium and High quality.
2. Turn on **Settings → Performance overlay** while playing (FPS, frame times,
   draw calls, primitives, VRAM).
3. For deeper analysis: Xcode → Product → Profile → *Game Performance* /
   *Metal System Trace* template.

Targets: stable 30 fps at Medium on the baseline device; 60 fps on High where
the device allows. Levers if a device misses them: quality preset (render
scale 0.7/0.85/1.0, shadows, MSAA, draw distance 650/900/1300 m, prop and
traffic density, all in `src/core/settings.gd`), `CityWorld.detail_range`,
and shadow distance in `src/world/atmosphere.gd`.

## 5. Haptics

`Settings.haptic()` calls `Input.vibrate_handheld(ms, amplitude)`, which Godot
maps to iOS haptics on supported iPhones. It can be turned off in Settings.

## Troubleshooting

- *"App Store Team ID not specified"* during export: set `IOS_TEAM_ID`, or let
  the script use the placeholder and pick the team in Xcode.
- Signing errors in Xcode: make sure the bundle ID matches the App ID and the
  team owns it.
- Older devices: the Mobile renderer runs on Metal through MoltenVK. The
  oldest iPhone that holds 30 fps is **unknown until tested**; start with your
  baseline phone and the benchmark above.

## TestFlight without a Mac (GitHub Actions)

`.github/workflows/testflight.yml` does steps 1–4 on a GitHub-hosted Mac
(macos-15, newest Xcode 26): installs Godot 4.5.1 + templates, exports the
Xcode project, archives it unsigned, then signs it with the cloud-managed
distribution certificate during export and uploads the build to TestFlight.
(Archiving with automatic signing made a new Apple Development certificate on
every run until the account hit Apple's certificate limit.) Build number = the workflow run number.
It only runs when started by hand (Actions → TestFlight → Run workflow).

One-time setup:
1. App Store Connect → My Apps → + → New App, bundle ID
   `com.musastudios.cityswing` (the API can't create app records).
2. An App Store Connect API key with the Admin role (cloud signing refuses App Manager keys)
   (Users and Access → Integrations → App Store Connect API).
3. Push this repo to a **private** GitHub repo and add the secrets
   `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`
   (e.g. `gh secret set ASC_KEY_P8 < AuthKey_XXXX.p8`).
4. Run the workflow; after processing, add yourself as an internal tester
   in TestFlight and install from the TestFlight app on the iPhone.
`ITSAppUsesNonExemptEncryption` is already `false` in the exported Info.plist,
so no export-compliance question per build.
