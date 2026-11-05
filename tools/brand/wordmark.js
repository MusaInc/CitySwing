// CitySwing identity v2 ("Hero in the Arc", 2026-11-05).
//   Emblem  – the real hero's silhouette (art/hero_silhouette.png, from the
//             in-game render) hanging on its web inside the gold swing arc.
//   Wordmark – one word, CITYSWING: Outfit Black with a forward lean, CITY in
//             Web White, SWING in Signal Gold, swept by the same arc.
// Flat colours, local Outfit only, no stock art.
const GOLD = "#FFC93C", WEB = "#F7F3EA";

// Emblem in a 512 box – the app icon reduced to its essentials: the hero's
// silhouette (from the in-game render) cut out of the gold sunset disc, the
// white web line running up to its anchor.
function emblemSVG(size = 512, x = 0, y = 0) {
  const W = 372, ix = 74, iy = 70;
  const hx = ix + 760 * W / 1024, hy = iy + 298 * W / 1024;   // the web hand
  const ax = hx + 0.363 * 150, ay = hy - 0.932 * 150;          // along the web
  return `<svg x="${x}" y="${y}" width="${size}" height="${size}" viewBox="0 0 512 512">
    <defs><radialGradient id="sun" cx="50%" cy="55%" r="55%">
      <stop offset="0" stop-color="#FFE7A0"/><stop offset=".55" stop-color="${GOLD}"/><stop offset="1" stop-color="#FF9A4D"/>
    </radialGradient></defs>
    <circle cx="252" cy="268" r="182" fill="url(#sun)"/>
    <image href="art/hero_silhouette_ink.png" x="${ix}" y="${iy}" width="${W}" height="${W}"/>
    <line x1="${hx}" y1="${hy}" x2="${ax}" y2="${ay}" stroke="${WEB}" stroke-width="9" stroke-linecap="round"/>
    <circle cx="${ax}" cy="${ay}" r="15" fill="${WEB}"/>
  </svg>`;
}

// The lean: SWING-forward italic built by skewing upright Outfit Black.
function word(x, y, size, extra = "") {
  return `<g transform="translate(${x} ${y}) skewX(-10)">
    <text x="0" y="0" font-size="${size}" font-weight="900" letter-spacing="${-size * 0.035}" ${extra}><tspan fill="${WEB}">CITY</tspan><tspan fill="${GOLD}">SWING</tspan></text>
  </g>`;
}

function drawWordmark(svg, opts = {}) {
  if (opts.horizontal) {
    // 1470 x 240: the word, with the arc sweeping under it and up past the G.
    svg.setAttribute("viewBox", "0 0 1470 240");
    svg.innerHTML = `
      <path d="M40 216 C 520 240 1060 238 1172 206 S 1370 92 1428 40" fill="none" stroke="${GOLD}" stroke-width="12" stroke-linecap="round" opacity=".9"/>
      <circle cx="1432" cy="36" r="13" fill="${WEB}"/>
      ${word(30, 182, 196)}`;
  } else if (opts.emblem) {
    svg.setAttribute("viewBox", "0 0 512 512");
    svg.innerHTML = emblemSVG(512);
  } else {
    // Lockup (title screen, splash): emblem, then the word in one line.
    svg.setAttribute("viewBox", "0 0 1120 440");
    svg.innerHTML = `${emblemSVG(400, 0, 20)}
      ${word(410, 288, 118)}`;
  }
}
