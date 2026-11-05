"""CitySwing app icon v3 – composed from real game renders.

    <venv with pillow+numpy>/bin/python -I tools/brand/icon_compose.py

art/skyline_sea.png : the downtown skyline from the sea at sunset (game render,
                      tools/store_shots.sh --cam … --nohud)
art/hero_swing.png  : the hero mid-swing on a real web (tools/brand/hero_render.gd)
A hard-edged sun disc sits behind the towers (the sky is keyed out of the
render column by column), the towers go to near-silhouette with their lit
windows kept, and the hero crosses the disc, web line out of frame.
Writes assets/brand/icon_1024.png and assets/icon_1024.png.
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
S = 1024
SS = 3  # supersampling for the vector shapes


def sky_mask(img):
    """1 where the pixel is sky: per column, from the top down until the colour
    departs from the smooth sky gradient."""
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    h, w, _ = a.shape
    tops = np.full(w, h)
    for x in range(w):
        col = a[:, x]
        for y in range(40, h):
            # Sky brightens/shifts slowly downward; buildings/water break it.
            exp = a[max(0, y - 6):y, x].mean(axis=0)
            if np.abs(col[y] - exp).sum() > 26:
                tops[x] = y
                break
    # Thin things (beacon light beams, masts, antennas) trip single columns:
    # a running median over neighbours keeps only real rooflines.
    k = 9
    pad = np.pad(tops, k, mode="edge")
    tops = np.array([np.median(pad[i:i + 2 * k + 1]) for i in range(w)]).astype(int)
    mask = np.zeros((h, w), np.uint8)
    for x in range(w):
        mask[:tops[x], x] = 255
    return Image.fromarray(mask)


def main():
    city = Image.open(os.path.join(HERE, "art", "skyline_sea.png")).convert("RGB")
    # Frame: skyline low in the square, a little zoom.
    # Skyline into the lower third: shift the render down, extend its sky up.
    src = city.resize((int(S * 1.1), int(S * 1.1)), Image.LANCZOS).crop((50, 0, 50 + S, S))
    drop = 300
    arr = np.asarray(src).astype(np.float32)
    top = arr[:24].mean(axis=(0, 1))
    ext = np.zeros((drop, S, 3), np.float32)
    for y in range(drop):
        t = y / drop
        ext[y] = top * (0.55 + 0.45 * t) + np.array([17, 13, 38]) * (0.45 - 0.45 * t)
    city = Image.fromarray(np.clip(np.concatenate([ext, arr[:S - drop]]), 0, 255).astype(np.uint8))
    mask = sky_mask(city)

    # Sky: the render's own sunset gradient, deepened toward the top.
    sky = np.asarray(city).astype(np.float32)
    yy = np.linspace(0, 1, S)[:, None, None]
    ink = np.array([17, 13, 38], np.float32)
    sky = sky * (0.55 + 0.45 * yy) + ink * (1 - (0.55 + 0.45 * yy)) * 0.9
    sky_img = Image.fromarray(np.clip(sky, 0, 255).astype(np.uint8))

    # Sun disc (hard edge, warm gradient), behind the towers.
    cx, cy, r = 556, 452, 318
    disc = Image.new("RGBA", (S * SS, S * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(disc)
    for i in range(r * SS, 0, -SS):
        t = 1 - i / (r * SS)
        c = (255, int(150 + 80 * t ** 0.6), int(60 + 90 * t ** 1.5))  # orange rim → pale gold centre
        d.ellipse((cx * SS - i, cy * SS - i, cx * SS + i, cy * SS + i), fill=c + (255,))
    disc = disc.resize((S, S), Image.LANCZOS)
    glow = disc.filter(ImageFilter.GaussianBlur(60))
    base = sky_img.convert("RGBA")
    base.alpha_composite(Image.blend(Image.new("RGBA", (S, S), (0, 0, 0, 0)), glow, 0.55))
    base.alpha_composite(disc)
    # Keep the sun only in the sky; towers in front, graded to near-silhouette
    # (lit windows survive as small bright points).
    towers = ImageEnhance.Brightness(city).enhance(0.5)
    towers = ImageEnhance.Contrast(towers).enhance(1.35)
    tw = np.asarray(towers).astype(np.float32)
    tw = tw * 0.75 + ink * 0.25
    towers = Image.fromarray(np.clip(tw, 0, 255).astype(np.uint8)).convert("RGBA")
    inv = Image.eval(mask, lambda v: 255 - v)
    towers.putalpha(inv)
    base.alpha_composite(towers)

    # Hero: large, crossing the disc; dark with its gold rim.
    hero = Image.open(os.path.join(HERE, "art", "hero_swing.png")).convert("RGBA")
    # The web line keeps its full white: it's the near-white thin pixels.
    hv = np.asarray(hero).astype(np.float32)
    line = (hv[..., :3].min(axis=2) > 175) & (hv[..., 3] > 100)
    hero = ImageEnhance.Brightness(hero).enhance(0.62)
    hd = np.asarray(hero).copy()
    hd[line] = [250, 247, 238, 255]
    hero = Image.fromarray(hd)
    hs = 1000
    hero = hero.resize((hs, hs), Image.LANCZOS)
    # A thin dark edge so the figure cuts cleanly out of the bright disc.
    a = hero.split()[3]
    edge = Image.new("RGBA", hero.size, (10, 8, 24, 0))
    edge.putalpha(a.filter(ImageFilter.MaxFilter(5)).point(lambda v: int(v * 0.85)))
    hx, hy = -96, -26
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    layer.alpha_composite(edge, (hx, hy) if hx >= 0 else (0, 0), (max(0, -hx), max(0, -hy)))
    layer.alpha_composite(hero, (0, 0), (max(0, -hx), max(0, -hy)))
    base.alpha_composite(layer)

    # Vignette for depth.
    v = Image.new("L", (S, S), 0)
    ImageDraw.Draw(v).ellipse((-260, -220, S + 260, S + 300), fill=255)
    v = v.filter(ImageFilter.GaussianBlur(140))
    dark = Image.new("RGBA", (S, S), (17, 13, 38, 255))
    dark.putalpha(Image.eval(v, lambda q: int((255 - q) * 0.75)))
    base.alpha_composite(dark)

    out = base.convert("RGB")
    out.save(os.path.join(ROOT, "assets", "brand", "icon_1024.png"))
    out.save(os.path.join(ROOT, "assets", "icon_1024.png"))
    out.resize((256, 256), Image.LANCZOS).save(os.path.join(ROOT, "assets", "icon.png"))
    print("icon composed")


if __name__ == "__main__":
    main()
