// Renders the City Swing brand sources (SVG/HTML in this folder) to PNGs.
//   node tools/brand/render.mjs [name]     → assets/brand/*.png, assets/icon*.png, docs/brand_sheet.png
// Sources: icon.svg (the hero scene), mark.svg, wordmark.js (the logo), *.html. See docs/BRAND.md.
// Uses Playwright's Chromium (FireDev's node_modules, override with PLAYWRIGHT).
import { createRequire } from "module";
import { fileURLToPath } from "url";
import path from "path";
import fs from "fs";
import { execFileSync } from "child_process";
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT ?? "/home/abdul/workspace/projects/FireDev/node_modules/playwright");
const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../..");
const out = path.join(root, "assets/brand");
fs.mkdirSync(out, { recursive: true });

// name, source, width, height, transparent, extra copies
const JOBS = [
  ["icon_1024", "icon.svg", 1024, 1024, false, ["assets/icon_1024.png"]],
  ["icon_256", "icon.svg", 256, 256, false, ["assets/icon.png"]],
  ["mark", "mark.svg", 512, 512, true, []],
  ["wordmark", "wordmark.html", 1600, 560, true, []],
  ["wordmark_stacked", "wordmark_stacked.html", 1200, 900, true, []],
  ["splash", "splash.html", 2340, 1080, false, []],
  ["brand_sheet", "sheet.html", 1600, 2220, false, ["docs/brand_sheet.png"]],
];

const only = process.argv[2];
const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 1 });
for (const [name, src, w, h, transparent, copies] of JOBS) {
  if (only && name !== only) continue;
  await page.setViewportSize({ width: w, height: h });
  await page.goto("file://" + path.join(here, src));
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(150);
  const file = path.join(out, name + ".png");
  await page.screenshot({ path: file, omitBackground: transparent, clip: { x: 0, y: 0, width: w, height: h } });
  // Logos are used as-is by the game: trim the transparent padding (ImageMagick).
  if (name.startsWith("wordmark")) execFileSync("magick", [file, "-trim", "+repage", file]);
  for (const c of copies) fs.copyFileSync(file, path.join(root, c));
  if (name === "brand_sheet") fs.unlinkSync(file);  // docs only: keep it out of the game pack
  console.log("rendered", path.relative(root, file));
}
await browser.close();
