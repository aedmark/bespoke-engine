// Exercise the shipped Wasm command bar with the same key and character events the page sends.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const moduleBytes = fs.readFileSync(process.argv[2]);
const w = new WebAssembly.Instance(new WebAssembly.Module(moduleBytes), {}).exports;

function line(text, advances) {
  const tick = w.wasm_get_tick();
  if (!w.wasm_command_bar_focused()) w.wasm_on_key_down(13);
  assert.equal(w.wasm_command_bar_focused(), 1, 'Enter opens the parser');
  for (const ch of text) w.wasm_on_char(ch.charCodeAt(0));
  w.wasm_on_key_down(13);
  assert.equal(w.wasm_dialogue_open(), 0, 'no menu or number key is needed');
  assert.equal(w.wasm_get_tick(), tick + advances, text);
}

function ticks(n) { for (let i = 0; i < n; i++) w.wasm_step_tick(); }

function transcript() {
  const text = new TextDecoder().decode(new Uint8Array(w.memory.buffer, w.watch_text_ptr(), w.watch_text_len()));
  w.watch_text_clear();
  return text;
}

function quietScore(name) {
  let peak = 0;
  let energy = 0;
  let edges = 0;
  let last = 0;
  for (let frame = 0; frame < 256; frame++) {
    const pcm = new Int16Array(w.memory.buffer, w.wasm_audio_render(1024), 2048);
    for (let i = 0; i < pcm.length; i += 2) {
      const sample = pcm[i];
      peak = Math.max(peak, Math.abs(sample));
      energy += sample ** 2;
      edges += (sample - last) ** 2;
      last = sample;
    }
  }
  const rms = Math.sqrt(energy / (256 * 1024));
  // Check the raw game soundtrack before any page gain or filtering. The edge
  // check catches a bright pulse voice making an accidental comeback.
  assert(rms > 200 && peak < 4500, name + ': quiet but audible');
  assert(Math.sqrt(edges / energy) < 0.10, name + ': few sharp edges');
  console.log(name + ': PCM peak ' + peak + ', RMS ' + rms.toFixed(0));
}

w.wasm_init(0);
const start = w.wasm_get_fact_count();
line('ring bell', 1);
assert.equal(w.wasm_get_fact_count(), start, 'the jammed bell does not warn the ship');
assert.match(transcript(), /the bell doesn't move/);
line('go watch room', 0);
ticks(6);
line('take oilcan', 1);
line('go bell landing', 0);
ticks(6);
line('oil bell', 1);
assert.match(transcript(), /the pivot gives/);
line('ring bell', 1);
assert.match(transcript(), /We all sleep soundly tonight/);
const afterBell = new Set();
for (let i = 0; i < 18; i++) {
  ticks(1);
  afterBell.add(w.wasm_get_fact_count());
}
assert.deepEqual(afterBell, new Set([start + 2, start + 3]), 'knocks come and go, without entry');
quietScore('Tide');

w.wasm_init(0);
line('go to gallery', 0);
ticks(6);
line('ask keeper to open shutter', 1);
assert.match(transcript(), /And soon you will too/);
line('open shutter', 1);
assert.match(transcript(), /The beacon shines out over the water/);
ticks(16);
assert.match(transcript(), /from inside the door/);
quietScore('Inside');

console.log('ok  Lantern Watch Wasm: keyboard-only bell and shutter routes');
