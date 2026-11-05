# CitySwing 1.0 — App Store submission pack

Everything here describes features that exist in the 1.0 build (checked
against the code and menus on 5 Nov 2026). Paste into App Store Connect →
CitySwing → App Store tab → iOS App 1.0.

## Identity

| Field | Value |
|---|---|
| Name | CitySwing |
| Subtitle (≤30) | Swing a whole city your way |
| Bundle ID | com.musastudios.cityswing |
| Version / build | 1.0.0 / next TestFlight build number |
| SKU | cityswing-ios |
| Primary category | Games → Action |
| Secondary category | Games → Adventure |
| Price | £2.99 (paid up front, no in-app purchases, no ads) |
| Copyright | © 2026 Musa Studios |
| Support URL | https://musastudios.co.uk/support |
| Privacy policy URL | https://musastudios.co.uk/privacy/cityswing *(page in `store/privacy-cityswing.html`; publish before submitting)* |
| Marketing URL | *(optional)* https://musastudios.co.uk/portfolio/ |
| Devices | iPhone and iPad (universal), landscape, iOS 15+ |

## Promotional text (≤170, can change without review)

Fire a web, swing through the skyline and never touch the street. A whole
coastal city to fly through — time trials, rooftop jobs and homes to earn.

## Description

The developer's own text (5 Nov 2026) — kept verbatim in `store/description.txt`,
which the listing workflow uploads. Every feature it lists exists in 1.0.

## Keywords (≤100 chars)

swing,web,rope,parkour,rooftop,open world,city,physics,freerun,time trial,speed,flying,traversal

## What's new (1.0)

First release. Swing, fly and run through a whole city.

## App Review information

**Notes for the reviewer:**

> CitySwing is a single-player game with no account, no network features and
> no in-app purchases. To try it: tap PLAY (Open City). Move with the left
> side of the screen; on the right, the large SWING button fires the web
> (hold to stay on it, lift the finger to let go) and JUMP jumps. Drag
> anywhere else on the right side to look around. Training (main menu)
> teaches the controls step by step.
> Time Trial and Endurance are on the main menu. Pause (top right) has
> Homes, the Job Board and Settings. No login or demo account is needed.

Contact: Musa Studios, support@musastudios.co.uk

## App Privacy (nutrition label)

**Data Not Collected.** The app sends nothing over the network: no
analytics, advertising, crash reporting or third-party SDKs. Progress and
settings are stored on the device only (`user://save.json`,
`user://settings.cfg`).

## Export compliance

`ITSAppUsesNonExemptEncryption = NO` is already set by the build workflow.
No encryption beyond what iOS itself provides.

## Age rating questionnaire (suggested answers — the developer attests these)

| Question | Answer | Why |
|---|---|---|
| Cartoon or fantasy violence | None | No fighting or weapons; the hero can crash into walls and be knocked out, then gets up (no injury shown) |
| Realistic violence | None | |
| Profanity or crude humour | None | |
| Mature or suggestive themes | None | |
| Horror / fear themes | None | |
| Medical / alcohol, tobacco, drugs | None | |
| Simulated gambling | None | |
| Sexual content or nudity | None | |
| Contests | None | |
| Unrestricted web access | No | Only two credit links that open Safari |
| User-generated content / messaging | No | |
| In-app controls (parental) / age assurance | No | |

Optional jobs from "The Fence" (a getaway, a rooftop heist with drones
chasing) are criminal-themed in name only: they are traversal challenges
with no violence. Expected rating: 4+ (or 9+ if you count the
criminal-themed jobs; both are reasonable).

## Screenshots

Genuine in-game captures from the 1.0 build, rendered on the build server
(software renderer). Files in `store/screenshots/`:

* `iphone69/` — 2868 × 1320 (6.9″ iPhone, landscape): accepted for all iPhone sizes
* `ipad13/` — 2752 × 2064 (13″ iPad, landscape): required because the app is universal

## Credits / licences (in-game: Settings → Character credits)

* All sound effects and music: synthesised in code by Musa Studios
  (`tools/audio/gen_audio.py`) — no third-party audio
* Outfit font: SIL Open Font License
* Character clothing adapted from CC BY / CC0 assets (credited in game):
  hooded sweat jacket (Elvaerwyn, CC BY), running shoes (punkduck, CC BY 3.0),
  cargo pants (Cortu Johnstone, CC0), gloves (MRT / toigo, CC0), body and
  weights (MakeHuman contributors, CC0)
* All brands in the city's billboards are fictional
