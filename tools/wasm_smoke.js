// Smoke check for the WebAssembly modules (P32-04, D-042): instantiate each with no imports,
// load every deck, tick, click, press the catalyst key, render, and check the framebuffer is
// not blank. Run after `zig build wasm wasm-proofs`:  node tools/wasm_smoke.js
// Needs Node.js 18 or later; it is a convenience check, not a project dependency.
const fs = require('fs');
const path = require('path');
const bin = path.join(__dirname, '..', 'zig-out', 'bin');
const modules = [['bespoke.wasm', 2], ['bespoke-proofs.wasm', 7]];
let failed = false;
// Each module stays under 1 MiB. The runtime's 1.2 MB of state must stay uninitialised; held
// as an initialised global it ships as zero bytes in the data section (D-067).
const MAX_MODULE_BYTES = 1024 * 1024;
for (const [file, decks] of modules) {
  const bytes = fs.readFileSync(path.join(bin, file));
  if (bytes.length > MAX_MODULE_BYTES) {
    console.log(`FAIL ${file}: ${bytes.length} bytes, over ${MAX_MODULE_BYTES}`);
    failed = true;
  }
  const exp = new WebAssembly.Instance(new WebAssembly.Module(bytes), {}).exports;
  for (let d = 0; d < decks; d++) {
    try {
      exp.wasm_init(d);
      for (let k = 0; k < 3; k++) exp.wasm_step_tick();
      exp.wasm_on_pointer_down(520, 185);
      exp.wasm_on_right_click(100, 100);
      exp.wasm_on_key_down('S'.charCodeAt(0));
      exp.wasm_render_frame();
      const px = new Uint8Array(exp.memory.buffer, exp.wasm_framebuffer_ptr(), exp.wasm_framebuffer_len());
      const distinct = new Set();
      for (let k = 0; k < px.length; k += 4 * 101) distinct.add((px[k] << 16) | (px[k + 1] << 8) | px[k + 2]);
      // Three ticks; a catalyst may run one more (the village's does).
      // The engine's script deck (D-066) must run its script: after a walk it records a fact.
      if (file === 'bespoke.wasm' && d === 1) {
        for (let k = 0; k < 12; k++) exp.wasm_step_tick();
        if (exp.wasm_get_fact_count() === 0) throw new Error('script deck recorded no facts');
      }
      const ok = exp.wasm_get_tick() >= 3 && distinct.size > 3;
      console.log(`${ok ? 'ok  ' : 'FAIL'} ${file} deck ${d}: tick ${exp.wasm_get_tick()}, facts ${exp.wasm_get_fact_count()}, ${distinct.size} colours`);
      if (!ok) failed = true;
    } catch (err) {
      console.log(`FAIL ${file} deck ${d}: ${err.message}`);
      failed = true;
    }
  }
}
process.exit(failed ? 1 : 0);
