// Drives bespoke-studio.wasm the way the page does (P47-01): files in as raw bytes, one check,
// JSON out. Positions match `bespoke check` on the same files (yard.bespoke:6:1 below).
// Run after `zig build studio`:  node studio/check_wasm.js zig-out/bin/bespoke-studio.wasm
'use strict';
const fs = require('fs');
const path = require('path');

function fail(message) {
  console.error(`FAIL ${message}`);
  process.exit(1);
}

async function main() {
  const wasmPath = process.argv[2];
  if (!wasmPath) fail('usage: node studio/check_wasm.js <bespoke-studio.wasm>');
  const { instance } = await WebAssembly.instantiate(fs.readFileSync(wasmPath), {});
  const x = instance.exports;
  const enc = new TextEncoder();

  function put(bytes) {
    const ptr = x.studio_alloc(bytes.length || 1);
    if (!ptr) fail('studio_alloc returned null');
    new Uint8Array(x.memory.buffer, ptr, bytes.length).set(bytes);
    return [ptr, bytes.length || 1, bytes.length];
  }
  function add(path, text) {
    const p = put(enc.encode(path));
    const d = put(typeof text === 'string' ? enc.encode(text) : text);
    const ok = x.studio_add_file(p[0], p[2], d[0], d[2]);
    x.studio_free(p[0], p[1]);
    x.studio_free(d[0], d[1]);
    return ok;
  }
  function check(main) {
    const p = put(enc.encode(main));
    const status = x.studio_check(p[0], p[2]);
    x.studio_free(p[0], p[1]);
    const bytes = new Uint8Array(x.memory.buffer, x.studio_result_ptr(), x.studio_result_len());
    return { status, result: JSON.parse(new TextDecoder().decode(bytes)) };
  }

  const yard = 'scene Yard:\n  cast: Walker\n  marks: Gate, Well\n\nroutine Stroll(Walker):\n  walk Walker to Well\n';
  x.studio_reset();
  add('scripts/main.bespoke', 'include "rooms/yard.bespoke"\n');
  add('scripts/rooms/yard.bespoke', yard);
  let r = check('scripts/main.bespoke');
  if (r.status !== 1 || !r.result.valid || r.result.scenes !== 1) fail(`valid project: ${JSON.stringify(r)}`);
  console.log('ok  a project with an include checks valid');

  add('scripts/rooms/yard.bespoke', 'scene Yard:\n  cast: Walker\n\nroutine Stroll(Walker):\n  walk Walker to\n');
  r = check('scripts/main.bespoke');
  if (r.status !== 0 || r.result.valid) fail(`broken include must fail: ${JSON.stringify(r)}`);
  if (r.result.file !== 'scripts/rooms/yard.bespoke' || r.result.line !== 6 || r.result.column !== 1 || r.result.kind !== 'UnexpectedToken') {
    fail(`diagnostic must name the included file and line: ${JSON.stringify(r.result)}`);
  }
  console.log(`ok  a broken include names ${r.result.file}:${r.result.line} (${r.result.kind})`);

  x.studio_reset();
  add('scripts/main.bespoke', 'include "../secret.bespoke"\n');
  add('secret.bespoke', yard);
  r = check('scripts/main.bespoke');
  if (r.result.valid || !/Outside/.test(`${r.result.kind} ${r.result.message}`)) {
    fail(`a path outside the script folder must be refused by name: ${JSON.stringify(r.result)}`);
  }
  console.log('ok  an include outside the script folder is refused');

  x.studio_reset();
  r = check('scripts/main.bespoke');
  if (r.result.kind !== 'MainScriptMissing') fail(`missing main: ${JSON.stringify(r.result)}`);
  if (add('../escape.bespoke', 'x')) fail('the table must refuse a path with ..');
  console.log('ok  a missing main script is a diagnostic; unclean paths are refused');

  // PNG art (D-193): The Sunken Vault checks valid both as the scenario folder sits in the
  // repository and as tools/build_sunken_vault.py lays out its generated project (script in
  // scripts/, images in scripts/art/), and fails as `bespoke check` does when an image is missing.
  const vault = path.join(__dirname, '..', 'scenarios', 'sunken_vault');
  const pngs = fs.readdirSync(path.join(vault, 'art')).filter((n) => n.endsWith('.png')).sort();
  for (const [main, dir] of [['main.bespoke', 'art'], ['scripts/main.bespoke', 'scripts/art']]) {
    x.studio_reset();
    add(main, fs.readFileSync(path.join(vault, 'main.bespoke')));
    for (const n of pngs) add(`${dir}/${n}`, fs.readFileSync(path.join(vault, 'art', n)));
    r = check(main);
    if (!r.result.valid) fail(`Sunken Vault at ${main}: ${JSON.stringify(r.result)}`);
  }
  console.log(`ok  PNG art decodes: The Sunken Vault checks valid in place and as generated, ${pngs.length} images (${r.result.scenes} scenes)`);
  x.studio_reset();
  add('main.bespoke', fs.readFileSync(path.join(vault, 'main.bespoke')));
  for (const n of pngs.slice(1)) add(`art/${n}`, fs.readFileSync(path.join(vault, 'art', n)));
  r = check('main.bespoke');
  if (r.result.valid || r.result.file !== 'main.bespoke' || !/cannot read "art\/cistern.png" \(FileNotFound\)/.test(r.result.message)) {
    fail(`a missing image must fail as bespoke check does: ${JSON.stringify(r.result)}`);
  }
  console.log(`ok  a missing image reports main.bespoke:${r.result.line}:${r.result.column} FileNotFound, as bespoke check does`);

  // Repeated checks must not grow memory without bound: the compiler's arena is freed per check.
  x.studio_reset();
  add('main.bespoke', yard);
  check('main.bespoke');
  const before = x.memory.buffer.byteLength;
  for (let i = 0; i < 40; i += 1) check('main.bespoke');
  const after = x.memory.buffer.byteLength;
  if (after > before + 16 * 1024 * 1024) fail(`memory grew from ${before} to ${after} over 40 checks`);
  console.log(`ok  40 checks hold memory at ${Math.round(after / 1048576)} MiB`);
}

main().catch((err) => fail(err.stack || err.message));
