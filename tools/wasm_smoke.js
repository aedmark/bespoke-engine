// Smoke check for the WebAssembly modules (P32-04, D-042): instantiate each with no imports,
// load every deck, tick, click, press the catalyst key, render, and check the framebuffer is
// not blank. Run after `zig build wasm wasm-proofs`:  node tools/wasm_smoke.js
// Needs Node.js 18 or later; it is a convenience check, not a project dependency.
const fs = require('fs');
const path = require('path');
const bin = path.join(__dirname, '..', 'zig-out', 'bin');
const modules = [['bespoke.wasm', 2], ['bespoke-proofs.wasm', 18]];
let failed = false;
// Each module stays under its budget (1.5 MiB, D-159). The runtime's 1.2 MB of state must stay uninitialised; held
// as an initialised global it ships as zero bytes in the data section (D-067).
const { wasmModuleBytes: MAX_MODULE_BYTES } = require('./web_budgets.json');
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
// The engine synthesizer in the browser (D-071): a proof deck plays its soundtrack, which fades
// in, so several buffers are rendered after loading the Tavern deck.
{
  const exp = new WebAssembly.Instance(new WebAssembly.Module(fs.readFileSync(path.join(bin, 'bespoke-proofs.wasm'))), {}).exports;
  exp.wasm_init(0);
  for (let k = 0; k < 3; k++) exp.wasm_step_tick();
  let energy = 0;
  for (let b = 0; b < 6; b++) {
    const ptr = exp.wasm_audio_render(4096);
    const samples = new Int16Array(exp.memory.buffer, ptr, 2 * 4096);
    for (let k = 0; k < samples.length; k += 7) energy += Math.abs(samples[k]);
  }
  const ok = energy > 0 && exp.wasm_audio_sample_rate() === 44100;
  console.log(`${ok ? 'ok  ' : 'FAIL'} bespoke-proofs.wasm audio: energy ${energy}, ${exp.wasm_audio_sample_rate()} Hz`);
  if (!ok) failed = true;
}
// P48-19 / D-176: feature query exports and browser hint key work across the Wasm ABI.
{
  const enc = new TextEncoder();
  const dec = new TextDecoder();
  const readText = (exp) => {
    const len = exp.wasm_query_len();
    return dec.decode(new Uint8Array(exp.memory.buffer, exp.wasm_query_ptr(), len));
  };
  const writeNames = (exp, ...parts) => {
    const buf = new Uint8Array(exp.memory.buffer, exp.wasm_query_ptr(), 256);
    let offset = 0;
    const lens = [];
    for (const part of parts) {
      const bytes = enc.encode(part);
      buf.set(bytes, offset);
      offset += bytes.length;
      lens.push(bytes.length);
    }
    return lens;
  };
  const exp = new WebAssembly.Instance(new WebAssembly.Module(fs.readFileSync(path.join(bin, 'bespoke-proofs.wasm'))), {}).exports;

  // Deck 12 (The Larkspur Observatory): ask for a hint directly and via the H key.
  exp.wasm_init(12);
  const hLen = exp.wasm_hint(1);
  const hintText = readText(exp);
  if (hLen === 0 || !hintText.includes('Archive')) {
    console.log(`FAIL bespoke-proofs.wasm hint: len=${hLen} text=${JSON.stringify(hintText)}`);
    failed = true;
  } else {
    exp.wasm_on_key_down('h'.charCodeAt(0));
    exp.wasm_render_frame();
    console.log(`ok  bespoke-proofs.wasm hint (deck 12): ${JSON.stringify(hintText)}`);
  }

  // Deck 13 (Valerius and the Bread): query decision, dilemma, and known value across S steps.
  exp.wasm_init(13);
  for (let k = 0; k < 3; k++) exp.wasm_step_tick();
  const [decLen] = writeNames(exp, 'BrannsCounsel');
  const decStage = exp.wasm_decision(decLen);
  const decChoice = readText(exp);
  const [dilLen] = writeNames(exp, 'StolenLoaf');
  const dilStage = exp.wasm_dilemma(dilLen);
  const dilOutcome = readText(exp);
  const [cLen1, aLen1] = writeNames(exp, 'Valerius', 'Mercy');
  const valBefore = exp.wasm_known_value(cLen1, aLen1);
  // Advance until Valerius reveals his Mercy via [S], then re-query known_value.
  exp.wasm_on_key_down('S'.charCodeAt(0));
  const [cLen2, aLen2] = writeNames(exp, 'Valerius', 'Mercy');
  const valAfter = exp.wasm_known_value(cLen2, aLen2);
  if (decStage !== 1 || decChoice !== 'HearTheCase' || dilStage !== 2 || dilOutcome !== 'Weigh' || valBefore !== -128 || valAfter !== 3) {
    console.log(`FAIL bespoke-proofs.wasm queries (deck 13): dec=(${decStage},${decChoice}) dil=(${dilStage},${dilOutcome}) val=(${valBefore}->${valAfter})`);
    failed = true;
  } else {
    console.log(`ok  bespoke-proofs.wasm queries (deck 13): BrannsCounsel=${decChoice}, StolenLoaf=${dilOutcome}, Mercy=${valBefore}->${valAfter}`);
  }
}
process.exit(failed ? 1 : 0);
