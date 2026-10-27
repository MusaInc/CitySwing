// Browser test of the web export, emulating an iPhone in landscape.
//   node tools/web/web_test.mjs <url> <outdir> [webkit|chromium]
// The page is opened with ?debug=1 so the game publishes its state to
// window.__cs (line state, anchor screen position, a tappable building pixel…).
// This is SIMULATED touch in desktop browser engines – not a physical iPhone.
import { createRequire } from "module";
const require = createRequire(import.meta.url);
const { webkit, chromium, devices } = require(process.env.PLAYWRIGHT ?? "/home/abdul/workspace/projects/FireDev/node_modules/playwright");

const [baseUrl, out, engine = "webkit"] = process.argv.slice(2);
const url = baseUrl + (baseUrl.includes("?") ? "&" : "?") + "debug=1";
const dev = devices["iPhone 13 landscape"];
const browser = await (engine === "chromium" ? chromium : webkit).launch({
  args: engine === "chromium" ? ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"] : [],
});
const ctx = await browser.newContext({ ...dev });
const page = await ctx.newPage();
const logs = [];
page.on("console", (m) => logs.push(`[${m.type()}] ${m.text()}`));
page.on("pageerror", (e) => logs.push(`[pageerror] ${e.message}`));
await page.addInitScript(() => {
  const wrap = (fn) => async (...a) => {
    const r = await fn(...a);
    const inst = r.instance ?? r;
    for (const v of Object.values(inst.exports ?? {})) if (v instanceof WebAssembly.Memory) window.__wasmMem = v;
    return r;
  };
  WebAssembly.instantiate = wrap(WebAssembly.instantiate.bind(WebAssembly));
  if (WebAssembly.instantiateStreaming) WebAssembly.instantiateStreaming = wrap(WebAssembly.instantiateStreaming.bind(WebAssembly));
});
const results = [];
const check = (ok, msg) => { results.push([ok, msg]); console.log(`${ok ? "ok  " : "FAIL"} ${msg}`); };
const vw = dev.viewport.width, vh = dev.viewport.height;
const t0 = Date.now();
await page.goto(url, { waitUntil: "load" });
const shot = (n) => page.screenshot({ path: `${out}/${engine}_${n}.png` });
const state = () => page.evaluate(() => window.__cs ?? null);
// Software rendering here can run at ~1 fps, so wait for game state, not wall time.
async function waitFor(pred, ms = 20000) {
  const end = Date.now() + ms;
  let st = await state();
  while (Date.now() < end && !pred(st)) { await page.waitForTimeout(200); st = await state(); }
  return st;
}
const mem = () => page.evaluate(() => ({
  wasmMB: window.__wasmMem ? +(window.__wasmMem.buffer.byteLength / 1048576).toFixed(0) : null,
  jsMB: performance.memory ? +(performance.memory.usedJSHeapSize / 1048576).toFixed(0) : null,
}));
let rect = { x: 0, y: 0, w: vw, h: vh };
const px = (fx, fy) => [rect.x + fx * rect.w, rect.y + fy * rect.h];

let booted = false;
for (let i = 0; i < 240 && !booted; i++) { await page.waitForTimeout(500); booted = logs.some((l) => l.includes("Initial city build")); }
const loadS = (Date.now() - t0) / 1000;
// Measure the canvas only once Godot has sized it (it starts at 300×150).
rect = await page.evaluate(() => { const b = document.querySelector("canvas").getBoundingClientRect(); return { x: b.x, y: b.y, w: b.width, h: b.height }; });
console.log(`canvas rect ${JSON.stringify(rect)}`);
check(booted, `engine booted and city built in ${loadS.toFixed(1)} s`);
console.log(`memory after boot: ${JSON.stringify(await mem())}`);
await page.waitForTimeout(2500);
await shot("1_title");
await page.touchscreen.tap(...px(0.5, 0.545));          // "Free Swing"
let st = await waitFor((s) => s?.state === "playing");
check(st?.state === "playing", `menu tap starts Free Swing (state=${st?.state})`);
await page.waitForTimeout(4000);  // let the spawn camera settle
await shot("2_rooftop_spawn");
for (let i = 0; i < 12 && !(st?.suggest?.length); i++) { await page.waitForTimeout(300); st = await state(); }
check(!!st?.suggest?.length, `a building is tappable on screen (${JSON.stringify(st?.suggest)})`);
const web = px(...(st?.suggest ?? [0.65, 0.3]));
const fired0 = st?.webs_fired ?? 0;

// Touch helpers: real per-finger DOM TouchEvents dispatched on the canvas (what
// Godot's web input reads), identical in Chromium and WebKit. Each event lists
// every finger still down in `touches` and the moving/lifting one in
// `changedTouches`.
const active = new Map();
async function send(type, id) {
  const pts = [...active.entries()].map(([i, [x, y]]) => ({ id: i, x, y }));
  const changed = type === "touchend" ? [{ id, x: lifted[0], y: lifted[1] }] : pts.filter((p) => p.id === id);
  return page.evaluate(({ type, pts, changed }) => {
    const c = document.querySelector("canvas");
    const mk = (p) => new Touch({ identifier: p.id, target: c, clientX: p.x, clientY: p.y, pageX: p.x, pageY: p.y, radiusX: 4, radiusY: 4, force: 1 });
    c.dispatchEvent(new TouchEvent(type, { touches: pts.map(mk), targetTouches: pts.map(mk),
      changedTouches: changed.map(mk), bubbles: true, cancelable: true }));
  }, { type, pts, changed });
}
let lifted = [0, 0];
async function down(id, x, y) { active.set(id, [x, y]); return send("touchstart", id); }
async function move(id, x, y) { active.set(id, [x, y]); return send("touchmove", id); }
async function up(id) { lifted = active.get(id); active.delete(id); return send("touchend", id); }

// Tap an invalid target (sky / too far / street): it must never fire a web,
// and the game must say why.
st = await waitFor((s) => s?.invalid?.length, 10000);
if (st?.invalid?.length) {
  const firedBefore = st.webs_fired ?? 0;
  const [ix, iy, why] = st.invalid;
  await page.touchscreen.tap(...px(ix, iy));
  st = await waitFor((s) => s?.last_tap?.reason, 8000);
  check(st?.last_tap?.reason === why && (st?.webs_fired ?? 0) === firedBefore,
    `tap on an invalid target ("${why}") is rejected with feedback and fires nothing (got ${JSON.stringify(st?.last_tap)})`);
} else {
  check(false, "an invalid target exists on screen to tap");
}
let touchWorks = true;
try { await down(1, ...web); } catch (e) { touchWorks = false; console.log(`synthetic touch unavailable in this engine: ${e.message}`); }
if (!touchWorks) {
  // WebKit here can't construct Touch objects, so only Playwright's real tap
  // (press + lift) is possible: the web fires, then releases as the finger lifts.
  await page.touchscreen.tap(...web);
  st = await waitFor((s) => (s?.webs_fired ?? 0) > fired0);
  check((st?.webs_fired ?? 0) > fired0, `tap on a building fires a web (single real tap; holds not simulatable in this engine)`);
  st = await waitFor((s) => s?.line === 0);
  check(st?.line === 0, `lifting the finger releases the web (line=${st?.line})`);
} else {
  st = await waitFor((s) => (s?.webs_fired ?? 0) > fired0 && s?.anchor?.length);
  check((st?.webs_fired ?? 0) > fired0, `touch on the building fired a web`);
  const af = st?.anchor ?? [];
  if (af.length) {
    const ax = rect.x + af[0] * rect.w, ay = rect.y + af[1] * rect.h;
    const err = Math.hypot(ax - web[0], ay - web[1]);
    check(err < 70, `anchor appears where the finger landed (${err.toFixed(0)} px off)`);
  } else check(false, "anchor visible after the tap");
  st = await waitFor((s) => s?.line === 2);
  check(st?.line === 2, `holding the finger keeps the web attached (line=${st?.line})`);
  await shot("3_holding_web");
  // Second finger on the left: the movement stick, while the web is held.
  await down(2, ...px(0.15, 0.75));
  for (let i = 1; i <= 5; i++) { await move(2, px(0.15, 0.75)[0], px(0.15, 0.75)[1] - i * 10); await page.waitForTimeout(30); }
  // Third finger: drag the LOOK pad to look around (never fires).
  const k = rect.h / 720;
  const look = [rect.x + rect.w - 292 * k, rect.y + rect.h - 104 * k];
  const yaw0 = (await state())?.look_yaw ?? 0;
  await down(3, ...look);
  for (let i = 1; i <= 8; i++) { await move(3, look[0] - i * 12, look[1]); await page.waitForTimeout(30); }
  st = await waitFor((s) => Math.abs((s?.look_yaw ?? 0) - yaw0) > 0.02, 8000);
  check(Math.abs((st?.look_yaw ?? 0) - yaw0) > 0.02, `dragging the LOOK pad turns the camera (Δ=${((st?.look_yaw ?? 0) - yaw0).toFixed(3)})`);
  check(st?.line === 2, `camera drag doesn't release the web (line=${st?.line})`);
  await up(3);
  await up(2);
  await page.waitForTimeout(250);
  st = await state();
  check(st?.line === 2, `lifting other fingers keeps the web (line=${st?.line})`);
  const swings0 = st?.swings ?? 0;
  await up(1);
  st = await waitFor((s) => s?.line === 0);
  check(st?.line === 0 && (st?.swings ?? 0) > swings0, `lifting the web finger releases it (line=${st?.line}, swings=${st?.swings})`);
  await shot("4_released");
}
await page.touchscreen.tap(rect.x + rect.w - 44 * (rect.h / 720), rect.y + 44 * (rect.h / 720));
st = await waitFor((s) => s?.state === "paused");
check(st?.state === "paused", `pause button opens the menu (state=${st?.state})`);
await shot("5_pause");
const m = await mem();
console.log(`memory at end: ${JSON.stringify(m)}  fps(sw render)=${st?.fps}`);
const bad = logs.filter((l) => /SCRIPT ERROR|pageerror|ERROR:/i.test(l));
check(bad.length === 0, `no script/page errors (${bad.length})`);
for (const l of [...new Set(bad)].slice(0, 10)) console.log("   " + l);
const warn = [...new Set(logs.filter((l) => /WARNING|WebGL/i.test(l)))].slice(0, 6);
for (const l of warn) console.log("   note: " + l);
console.log(`RESULT ${engine}: ${results.filter((r) => r[0]).length}/${results.length} passed, boot ${loadS.toFixed(1)} s, wasm ${m.wasmMB} MB`);
await browser.close();
process.exit(results.every((r) => r[0]) ? 0 : 1);
