// Node Wasm smoke test for The Sunken Vault (P49-03): verifies turn clock, victory route,
// flood fail-state, 60 Hz colour cycling, hints, and quiet MML soundtrack.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');

const wasmBytes = fs.readFileSync(process.argv[2]);
const mod = new WebAssembly.Module(wasmBytes);
const enc = new TextEncoder();
const dec = new TextDecoder();

function makeGame() {
  const w = new WebAssembly.Instance(mod, {}).exports;
  w.wasm_init(0, 42, 0);
  const drain = () => {
    const len = w.game_text_len();
    if (!len) return '';
    const text = dec.decode(new Uint8Array(w.memory.buffer, w.game_text_ptr(), len));
    w.game_text_clear();
    return text;
  };
  const submit = (line) => {
    const bytes = enc.encode(line);
    new Uint8Array(w.memory.buffer, w.wasm_query_ptr(), bytes.length).set(bytes);
    assert.equal(w.wasm_submit_command(bytes.length), 1, `submit ${line}`);
    return drain();
  };
  return { w, drain, submit };
}

// 1. Opening prose, refusal = 0 turns, colour cycling, hint, and victory route.
{
  const { w, drain, submit } = makeGame();
  assert.match(drain(), /keep courtyard/);

  const t0 = w.wasm_get_tick();
  const f0 = w.wasm_get_fact_count();
  w.wasm_set_animation_clock(0);
  w.wasm_render_frame();
  const ptr = w.wasm_framebuffer_ptr();
  const len = w.wasm_framebuffer_len();
  const frame0 = new Uint8Array(w.memory.buffer, ptr, len).slice();
  w.wasm_set_animation_clock(12);
  w.wasm_render_frame();
  const frame12 = new Uint8Array(w.memory.buffer, ptr, len);
  let diff = 0;
  for (let i = 0; i < len; i += 4) {
    if (frame0[i] !== frame12[i] || frame0[i + 1] !== frame12[i + 1] || frame0[i + 2] !== frame12[i + 2]) diff++;
  }
  assert(diff > 100, `expected colour-cycled pixels to change (got ${diff})`);
  assert.equal(w.wasm_get_tick(), t0);
  assert.equal(w.wasm_get_fact_count(), f0);

  const hLen = w.wasm_hint(1);
  assert(hLen > 0);
  const hint = dec.decode(new Uint8Array(w.memory.buffer, w.wasm_query_ptr(), hLen));
  assert.match(hint, /guardhouse/);

  const bad = submit('xyzzy');
  assert.match(bad, /don't know/);
  assert.equal(w.wasm_get_tick(), t0);

  const route = [
    'east', 'take flint', 'take torch', 'take key', 'read ledger',
    'west', 'down', 'east', 'turn wheel', 'west',
    'light torch', 'north', 'unlock gate with key', 'north',
    'take crown', 'south', 'south', 'up',
  ];
  let last = '';
  for (const cmd of route) last = submit(cmd);
  assert.match(last, /Crown of Tides shining/);
  assert.equal(w.wasm_get_tick(), t0 + route.length);
  assert.equal(w.wasm_hint(1), 0);

  // Quiet MML soundtrack check (matching Lantern Watch tolerances).
  let peak = 0;
  let energy = 0;
  let edges = 0;
  let prev = 0;
  for (let f = 0; f < 256; f++) {
    const pcm = new Int16Array(w.memory.buffer, w.wasm_audio_render(1024), 2048);
    for (let i = 0; i < pcm.length; i += 2) {
      const s = pcm[i];
      peak = Math.max(peak, Math.abs(s));
      energy += s * s;
      edges += (s - prev) * (s - prev);
      prev = s;
    }
  }
  const rms = Math.sqrt(energy / (256 * 1024));
  assert(rms > 150 && peak < 4500, `VaultScore audio out of range: peak=${peak} rms=${rms.toFixed(0)}`);
  assert(Math.sqrt(edges / energy) < 0.12, 'VaultScore sharp-edge ratio too high');
  console.log(`ok  Sunken Vault Wasm victory & audio: tick=${w.wasm_get_tick()} diffPx=${diff} peak=${peak} rms=${rms.toFixed(0)}`);
}

// 2. Un-drained sluice floods the vault after 9 turns.
{
  const { w, drain, submit } = makeGame();
  drain();
  const setup = [
    'east', 'take flint', 'take torch', 'take key',
    'west', 'down', 'light torch', 'north',
    'unlock gate with key', 'north', 'take crown',
  ];
  for (const cmd of setup) submit(cmd);
  let flooded = '';
  for (let i = 0; i < 9; i++) flooded += submit('wait');
  assert.match(flooded, /sealing the vault/);
  const blocked = submit('south');
  assert.match(blocked, /descent is over/);
  console.log(`ok  Sunken Vault Wasm flood fail-state: tick=${w.wasm_get_tick()}`);
}
