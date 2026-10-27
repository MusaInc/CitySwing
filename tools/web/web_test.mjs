// Browser test of the web export, emulating an iPhone in landscape.
//   node tools/web/web_test.mjs <url> <outdir> [webkit|chromium]
// Loads the game, records console errors, load time and WebAssembly memory,
// then drives it with real touch events: tap "Free Swing", hold the left
// stick + hold SWING, drag-look, pause, and screenshots each step.
import { createRequire } from "module";
const require = createRequire(import.meta.url);
const { webkit, chromium, devices } = require(process.env.PLAYWRIGHT ?? "/home/abdul/workspace/projects/FireDev/node_modules/playwright");

const [url, out, engine = "webkit"] = process.argv.slice(2);
const dev = devices["iPhone 13 landscape"];
const browser = await (engine === "chromium" ? chromium : webkit).launch({
  args: engine === "chromium" ? ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"] : [],
});
const ctx = await browser.newContext({ ...dev, ...(engine === "chromium" ? {} : {}) });
const page = await ctx.newPage();
const logs = [];
page.on("console", (m) => logs.push(`[${m.type()}] ${m.text()}`));
page.on("pageerror", (e) => logs.push(`[pageerror] ${e.message}`));
// Capture the wasm Memory object so we can report the heap size.
await page.addInitScript(() => {
  const wrap = (fn) => async (...a) => {
    const r = await fn(...a);
    const inst = r.instance ?? r;
    for (const v of Object.values(inst.exports ?? {})) if (v instanceof WebAssembly.Memory) window.__wasmMem = v;
    return r;
  };
  WebAssembly.instantiate = wrap(WebAssembly.instantiate.bind(WebAssembly));
  if (WebAssembly.instantiateStreaming) WebAssembly.instantiateStreaming = wrap(WebAssembly.instantiateStreaming.bind(WebAssembly));
  const OrigMem = WebAssembly.Memory;
  WebAssembly.Memory = function (d) { const m = new OrigMem(d); window.__wasmMem = m; return m; };
  WebAssembly.Memory.prototype = OrigMem.prototype;
});
const vw = dev.viewport.width, vh = dev.viewport.height;
const t0 = Date.now();
await page.goto(url, { waitUntil: "load" });
const shot = async (n) => page.screenshot({ path: `${out}/${engine}_${n}.png` });
const mem = async () => page.evaluate(() => ({
  wasmMB: window.__wasmMem ? (window.__wasmMem.buffer.byteLength / 1048576).toFixed(0) : "?",
  jsMB: performance.memory ? (performance.memory.usedJSHeapSize / 1048576).toFixed(0) : "n/a",
}));
// Wait for the engine to finish booting (city build is printed by main.gd).
let booted = false;
for (let i = 0; i < 240 && !booted; i++) {
  await page.waitForTimeout(500);
  booted = logs.some((l) => l.includes("Initial city build"));
}
const loadS = ((Date.now() - t0) / 1000).toFixed(1);
console.log(`booted=${booted} in ${loadS}s  mem=${JSON.stringify(await mem())}`);
await page.waitForTimeout(4000);
await shot("1_title");
// Game is 1280x720 base stretched to the viewport (canvas_items/expand): map game coords.
const sx = vw / 1280 * (720 / vh) > 1 ? vh / 720 : vw / 1280;
const g = (x, y) => [vw / 2 + (x - 640) * (vh / 720), vh / 2 + (y - 360) * (vh / 720)];
// Tap the "Free Swing" button (centre of the title panel, ~y=294 of 540 in 960x540 shots => 0.545 of height).
await page.touchscreen.tap(vw / 2, vh * 0.545);
await page.waitForTimeout(2500);
await shot("2_after_tap_free_swing");
console.log(`after tap mem=${JSON.stringify(await mem())}`);
if (engine === "chromium") {
  const cdp = await ctx.newCDPSession(page);
  const touch = (type, pts) => cdp.send("Input.dispatchTouchEvent", { type, touchPoints: pts.map(([x, y], id) => ({ x, y, id })) });
  // Left thumb stick forward + right thumb hold SWING (bottom-right button), then release.
  const stick0 = [vw * 0.15, vh * 0.75];
  const swing = [vw - 150 * (vh / 720), vh - 150 * (vh / 720)];
  await touch("touchStart", [stick0]);
  for (let i = 1; i <= 6; i++) { await touch("touchMove", [[stick0[0], stick0[1] - i * 8]]); await page.waitForTimeout(30); }
  await touch("touchStart", [[stick0[0], stick0[1] - 48], swing]);
  await page.waitForTimeout(1800);
  await shot("3_holding_swing");
  await touch("touchEnd", []);
  await page.waitForTimeout(800);
  await shot("4_released");
  // Drag-look with the right thumb on empty space.
  const look0 = [vw * 0.7, vh * 0.35];
  await touch("touchStart", [look0]);
  for (let i = 1; i <= 10; i++) { await touch("touchMove", [[look0[0] - i * 15, look0[1]]]); await page.waitForTimeout(30); }
  await touch("touchEnd", []);
  await page.waitForTimeout(800);
  await shot("5_after_look");
  // Pause button (top-right).
  await page.touchscreen.tap(vw - 44 * (vh / 720), 44 * (vh / 720));
  await page.waitForTimeout(1200);
  await shot("6_pause");
}
console.log(`final mem=${JSON.stringify(await mem())}`);
const bad = logs.filter((l) => /error|warn|unsupported|not supported/i.test(l));
console.log(`console lines=${logs.length}, error/warn lines=${bad.length}`);
console.log([...new Set(bad)].slice(0, 40).join("\n"));
await browser.close();
