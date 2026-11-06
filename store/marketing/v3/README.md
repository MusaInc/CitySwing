# CitySwing App Store gallery v3 (2026-11-06)

Hero-forward redesign: the real hero, in a real Shop look (Tangerine top), filmed
close with a longer lens so he reads at thumbnail size, at golden hour / blue
hour / rain in the actual game. Brand type (Outfit Black, ivory + Signal Gold)
over a left scrim (iPhone) or top scrim (iPad).

- `upload/<device>/*.jpg` – upload-ready (iPhone 6.9" 2868x1320, iPad 13" 2752x2064).
- `final/<device>/*.png` – lossless masters (git-ignored size; regenerate).
- `contact-<device>.jpg` – review sheets.

Reproduce (from the project root):

    IDS=canyon_14_dive,gold_16_low34,dusk_18_low34,neon_18_side,rain_22_chase,perch_gold_2_back
    bash tools/marketing/hero_shots.sh store/marketing/v3/native/iphone69 2868x1320 $IDS
    bash tools/marketing/hero_shots.sh store/marketing/v3/native/ipad13 2752x2064 $IDS
    xvfb-run -a -s "-screen 0 1400x1400x24" godot --rendering-method mobile --resolution 1024x1024 \
      --fixed-fps 60 -s res://tools/marketing/lineup_render.gd -- store/marketing/v3/lineup
    for i in 0 1 2 3 4; do convert store/marketing/v3/lineup/look_$i.png -trim +repage store/marketing/v3/cut/look_$i.png; done
    node tools/marketing/v3/compose.mjs

Copy lives in `tools/marketing/v3/slides.json`; layout in `tools/marketing/v3/slide.html`.
Scout a new scene with `bash tools/marketing/hero_shots.sh store/marketing/v3/scout 1434x660`.
To publish: copy `upload/*` into `store/screenshots/<device>/` and run the
App Store listing workflow with `-f screenshots=true`.
