// Reads the engine's 5x7 face out of bespoke-studio.wasm (`studio_glyph`, D-192 item 7) and
// prints it as JSON: {"width":5,"height":7,"glyphs":{"<code point>":[c0,c1,c2,c3,c4]}}.
// Called by tools/build_studio.py; the page draws every label from this table.
'use strict';
const fs = require('fs');

async function main() {
  const wasmPath = process.argv[2];
  if (!wasmPath) throw new Error('usage: node studio/font_table.js <bespoke-studio.wasm>');
  const { instance } = await WebAssembly.instantiate(fs.readFileSync(wasmPath), {});
  const glyphOf = instance.exports.studio_glyph;
  const glyphs = {};
  // ASCII, Latin-1, Latin Extended-A, and General Punctuation through the currency block:
  // every range font.zig fills. Anything the font answers with its placeholder is left out,
  // so the page draws the placeholder for it exactly as the engine does.
  const ranges = [[32, 126], [0xa0, 0x17f], [0x2000, 0x20cf]];
  for (const [lo, hi] of ranges) {
    for (let cp = lo; cp <= hi; cp += 1) {
      const v = glyphOf(cp);
      if (!(v & (1n << 40n)) || (v & (1n << 41n))) continue;
      const cols = [];
      for (let i = 0n; i < 5n; i += 1n) cols.push(Number((v >> (i * 8n)) & 0xffn));
      glyphs[cp] = cols;
    }
  }
  process.stdout.write(JSON.stringify({ width: 5, height: 7, placeholder: 63, glyphs }));
}

main().catch((err) => { console.error(err.message); process.exit(1); });
