// Gallery v3: lays the brand typography over native Godot renders.
//   node tools/marketing/v3/compose.mjs   (after tools/marketing/hero_shots.sh + lineup_render.gd)
import {createRequire} from 'node:module'; import fs from 'node:fs'; import path from 'node:path'; import {fileURLToPath} from 'node:url'; import {execFileSync} from 'node:child_process';
const require = createRequire(import.meta.url);
const {chromium} = require(process.env.PLAYWRIGHT ?? '/home/abdul/workspace/projects/FireDev/node_modules/playwright');
const here = path.dirname(fileURLToPath(import.meta.url)); const root = path.resolve(here, '../../..');
const v3 = path.join(root, 'store/marketing/v3'); const slides = JSON.parse(fs.readFileSync(path.join(here, 'slides.json')));
const browser = await chromium.launch({args: ['--allow-file-access-from-files']});
try {
  for (const [device, width, height] of [['iphone69', 2868, 1320], ['ipad13', 2752, 2064]]) {
    const page = await browser.newPage({viewport: {width, height}, deviceScaleFactor: 1});
    const out = path.join(v3, 'final', device); fs.mkdirSync(out, {recursive: true}); const files = [];
    for (const [i, s] of slides.entries()) {
      const slide = {...s, lineup: s.lineup?.map(id => 'file://' + path.join(v3, 'cut', id + '.png'))};
      const source = 'file://' + path.join(v3, 'native', device, s.shot + '.png');
      await page.goto('file://' + path.join(here, 'slide.html') + '?' + new URLSearchParams({device, source, slide: JSON.stringify(slide)}));
      await page.evaluate(async () => { await document.fonts.ready; await Promise.all([...document.images].map(im => im.decode())); });
      const fit = await page.evaluate(() => [...document.querySelectorAll('h1,.sub,.chips')].every(e => { const r = e.getBoundingClientRect(); return r.left >= 0 && r.right <= innerWidth && r.bottom <= innerHeight; }));
      if (!fit) throw Error('copy overflows on ' + device + ' ' + s.slug);
      const dest = path.join(out, String(i + 1).padStart(2, '0') + '_' + s.slug + '.png');
      await page.screenshot({path: dest, type: 'png'}); files.push(dest);
    }
    await page.close();
    execFileSync('montage', files.concat(['-thumbnail', device === 'ipad13' ? '688x516' : '956x440', '-geometry', '+10+10', '-tile', '2x3', '-background', '#09081c', path.join(v3, `contact-${device}.jpg`)]));
    console.log(device, files.length);
  }
} finally { await browser.close(); }
