// Draws the City Swing wordmark into <svg id="wm"> and sizes the viewBox to it.
// Shared by wordmark_stacked.html, wordmark.html, splash.html and sheet.html.
function drawWordmark(svg, opts = {}) {
  const NS = "http://www.w3.org/2000/svg";
  const el = (tag, attrs, parent = g) => {
    const e = document.createElementNS(NS, tag);
    for (const k in attrs) e.setAttribute(k, attrs[k]);
    parent.appendChild(e);
    return e;
  };
  svg.innerHTML = `<defs><linearGradient id="gold" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#FFE08A"/><stop offset="0.55" stop-color="#FFC93C"/><stop offset="1" stop-color="#FFA92E"/>
    </linearGradient></defs>`;
  const g = el("g", { transform: "skewX(-9)" }, svg);
  const city = el("text", { x: 14, y: 150, "font-size": 132, "letter-spacing": 34, fill: "#F7F3EA" });
  city.textContent = "CITY";
  const shadow = el("text", { x: 22, y: 470, "font-size": 330, "letter-spacing": -4, fill: "#110D26" });
  shadow.textContent = "SWING";
  const sw = el("text", { x: 0, y: 452, "font-size": 330, "letter-spacing": -4, fill: "url(#gold)",
    stroke: "#110D26", "stroke-width": 6, "paint-order": "stroke" });
  sw.textContent = "SWING";
  // Web line: taut from an anchor up and right down to the top of the G.
  const gStart = sw.getStartPositionOfChar(4).x, gEnd = sw.getEndPositionOfChar(4).x;
  const grip = { x: gStart + (gEnd - gStart) * 0.42, y: 228 };
  const anchor = { x: gEnd + 70, y: 20 };
  const line = el("line", { x1: anchor.x, y1: anchor.y, x2: grip.x, y2: grip.y, stroke: "#F7F3EA",
    "stroke-width": 9, "stroke-linecap": "round" });
  g.insertBefore(line, city);
  el("circle", { cx: anchor.x, cy: anchor.y, r: 14, fill: "#F7F3EA" });
  el("circle", { cx: grip.x, cy: grip.y, r: 12, fill: "#5CF2D0" });
  if (opts.streaks !== false) {
    el("line", { x1: 30, y1: 540, x2: 380, y2: 540, stroke: "#F7F3EA", "stroke-width": 12, "stroke-linecap": "round", opacity: 0.85 });
    el("line", { x1: 420, y1: 540, x2: 520, y2: 540, stroke: "#F7F3EA", "stroke-width": 12, "stroke-linecap": "round", opacity: 0.85 });
  }
  const b = svg.getBBox();
  const pad = 24;
  svg.setAttribute("viewBox", `${b.x - pad - 60} ${b.y - pad} ${b.width + pad * 2 + 60} ${b.height + pad * 2}`);
}
