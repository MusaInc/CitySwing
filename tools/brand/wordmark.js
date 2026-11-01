// Flat Outfit lettering and a single ascent symbol. No raster artwork or external fonts.
function drawWordmark(svg, opts = {}) {
  const horizontal = opts.horizontal;
  svg.setAttribute("viewBox", horizontal ? "0 0 1470 240" : "0 0 1120 440");
  svg.innerHTML = horizontal
    ? `<text x="12" y="184" fill="#F7F3EA" font-size="200" font-weight="900" letter-spacing="-7">CITY</text>
       <text x="490" y="184" fill="#FFC93C" font-size="200" font-weight="900" letter-spacing="-7">SWING</text>`
    : `<svg x="0" y="20" width="380" height="380" viewBox="0 0 512 512">
         <path d="M348 136 A172 172 0 1 0 376 352" fill="none" stroke="#FFC93C" stroke-width="62"/>
         <path d="M230 304 L395 111" fill="none" stroke="#F7F3EA" stroke-width="28"/>
         <circle cx="395" cy="111" r="23" fill="#F7F3EA"/>
       </svg>
       <text x="430" y="166" fill="#F7F3EA" font-size="134" font-weight="900" letter-spacing="20">CITY</text>
       <text x="420" y="348" fill="#FFC93C" font-size="198" font-weight="900" letter-spacing="-6">SWING</text>`;
}
