// Browser gameplay smoke test in an emulated landscape iPhone.
// node tools/web/web_test.mjs <url> <outdir> [webkit|chromium]
import { createRequire } from "module";
const require = createRequire(import.meta.url);
const { webkit, chromium, devices } = require(process.env.PLAYWRIGHT ?? "/home/abdul/workspace/projects/FireDev/node_modules/playwright");
const [baseUrl, out, engine = "webkit"] = process.argv.slice(2);
if (!baseUrl || !out) throw new Error("usage: web_test.mjs <url> <outdir> [webkit|chromium]");
const device = devices["iPhone 13 landscape"];
const browser = await (engine === "chromium" ? chromium : webkit).launch({
  args: engine === "chromium" ? ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"] : [],
});
const context = await browser.newContext({ ...device });
const page = await context.newPage();
const logs = [];
page.on("console", m => logs.push(`[${m.type()}] ${m.text()}`));
page.on("pageerror", e => logs.push(`[pageerror] ${e.message}`));
const checks = [];
const check = (ok, msg) => { checks.push([!!ok, msg]); console.log(`${ok ? "ok  " : "FAIL"} ${msg}`); };
const state = () => page.evaluate(() => window.__cs ?? null);
async function waitFor(predicate, timeout = 30000) {
  const end = Date.now() + timeout;
  let s = await state();
  while (Date.now() < end && !predicate(s)) { await page.waitForTimeout(200); s = await state(); }
  return s;
}
const started = Date.now();
await page.goto(`${baseUrl}${baseUrl.includes("?") ? "&" : "?"}debug=1&seed=6`, { waitUntil: "load" });
let s = await waitFor(v => v?.state === "title", 120000);
check(s?.state === "title", `game booted in ${((Date.now() - started) / 1000).toFixed(1)}s`);
const rect = await page.evaluate(() => {
  const b = document.querySelector("canvas").getBoundingClientRect();
  return { x: b.x, y: b.y, w: b.width, h: b.height };
});
const at = (fx, fy) => [rect.x + fx * rect.w, rect.y + fy * rect.h];
const shot = name => page.screenshot({ path: `${out}/${engine}_${name}.png` });
check(rect.w >= 700 && rect.h >= 300 && rect.w > rect.h, `landscape canvas ${rect.w}x${rect.h}`);
await shot("1_title");
await page.touchscreen.tap(...at(0.5, 0.59));  // "Free Swing" (Training sits above it on a fresh save)
s = await waitFor(v => v?.state === "playing", 30000);
check(s?.state === "playing", "Free Swing starts with an iPhone touch");
await page.waitForTimeout(2500);
await shot("2_rooftop");
s = await state();
const k = rect.h / 720;
const swing = [rect.x + rect.w - 150 * k, rect.y + rect.h - 150 * k];
const jump = [rect.x + rect.w - 338 * k, rect.y + rect.h - 92 * k];
const pause = [rect.x + rect.w - 44 * k, rect.y + 44 * k];
const active = new Map();
async function send(type, id, lifted) {
  const pts = [...active.entries()].map(([i, [x, y]]) => ({ id: i, x, y }));
  const changed = type === "touchend" ? [{ id, x: lifted[0], y: lifted[1] }] : pts.filter(p => p.id === id);
  await page.evaluate(({ type, pts, changed }) => {
    const c = document.querySelector("canvas");
    const mk = p => new Touch({ identifier: p.id, target: c, clientX: p.x, clientY: p.y,
      pageX: p.x, pageY: p.y, radiusX: 4, radiusY: 4, force: 1 });
    c.dispatchEvent(new TouchEvent(type, { touches: pts.map(mk), targetTouches: pts.map(mk),
      changedTouches: changed.map(mk), bubbles: true, cancelable: true }));
  }, { type, pts, changed });
}
const down = async (id, x, y) => { active.set(id, [x, y]); await send("touchstart", id); };
const move = async (id, x, y) => { active.set(id, [x, y]); await send("touchmove", id); };
const up = async id => { const xy = active.get(id); active.delete(id); await send("touchend", id, xy); };
if (engine === "chromium") {
  const fired = s?.webs_fired ?? 0;
  await down(1, ...swing);
  s = await waitFor(v => (v?.webs_fired ?? 0) > fired && v?.line === 2, 30000);
  check((s?.webs_fired ?? 0) > fired && s?.line === 2, "holding SWING attaches a web");
  check(s?.touch_web === 1, "the holding finger owns the web");
  await shot("3_holding_swing");
  const oldYaw = s?.look_yaw ?? 0;
  await down(2, ...at(0.77, 0.33));
  s = await waitFor(v => v?.touch_web === 2 && v?.line !== 0, 20000);
  check(s?.touch_web === 2, "another right-side touch reattaches");
  await up(1);
  s = await waitFor(v => v?.touch_web === 2, 8000);
  check(s?.line !== 0, "lifting the old finger keeps the new web");
  await down(3, ...jump);
  s = await state();
  check(s?.touch_web === 2, "JUMP does not steal the web");
  await up(3);
  const stick = at(0.15, 0.77);
  await down(4, ...stick);
  await move(4, stick[0], stick[1] - 55 * k);
  await page.waitForTimeout(500);
  await up(4);
  s = await state();
  check(Math.abs((s?.look_yaw ?? 0) - oldYaw) < 0.01, "touches do not orbit the camera");
  await up(2);
  s = await waitFor(v => v?.line === 0, 15000);
  check(s?.line === 0, "lifting the owning finger releases the web");
  await shot("4_released");
} else {
  // Linux WebKit cannot construct held Touch objects; Playwright sends real taps.
  const fired = s?.webs_fired ?? 0;
  await page.touchscreen.tap(...swing);
  s = await waitFor(v => (v?.webs_fired ?? 0) > fired || v?.last_tap?.reason === "waiting", 15000);
  check((s?.webs_fired ?? 0) > fired,
    "Safari touch on SWING fires a web from the rooftop");
  s = await waitFor(v => v?.line === 0, 12000);
  check(s?.line === 0, "Safari tap release leaves no held web");
  await shot("3_after_tap");
}
await page.touchscreen.tap(...pause);
s = await waitFor(v => v?.state === "paused", 15000);
check(s?.state === "paused", "pause touch opens the menu");
await shot("5_pause");
const errors = [...new Set(logs.filter(l => /SCRIPT ERROR|pageerror|ERROR:/i.test(l)))];
check(errors.length === 0, `no runtime errors (${errors.length})`);
for (const error of errors.slice(0, 8)) console.log(`  ${error}`);
console.log(`RESULT ${engine}: ${checks.filter(c => c[0]).length}/${checks.length} passed`);
await browser.close();
process.exit(checks.every(c => c[0]) ? 0 : 1);
