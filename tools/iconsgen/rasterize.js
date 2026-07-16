// Rasterize every lucide SVG to a 48x48 white PNG (transparent bg).
const fs = require('fs');
const path = require('path');
const { Resvg } = require('@resvg/resvg-js');

const SRC = path.join(__dirname, 'node_modules/lucide-static/icons');
const OUT = path.join(__dirname, 'png48');
fs.mkdirSync(OUT, { recursive: true });

const files = fs.readdirSync(SRC).filter(f => f.endsWith('.svg'));
let n = 0;
for (const f of files) {
  let svg = fs.readFileSync(path.join(SRC, f), 'utf8');
  // lucide strokes with currentColor; bake it to white so ImageColor3 can tint
  svg = svg.replace(/currentColor/g, '#FFFFFF');
  const png = new Resvg(svg, {
    fitTo: { mode: 'width', value: 48 },
    background: 'rgba(0,0,0,0)',
  }).render().asPng();
  fs.writeFileSync(path.join(OUT, f.replace(/\.svg$/, '.png')), png);
  n++;
}
console.log('rasterized', n, 'icons');
