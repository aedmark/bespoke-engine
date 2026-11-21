// P41-01: time the headless core in real Chrome, not a Node Wasm stand-in.
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { pathToFileURL } = require('node:url');

function run(file, args) {
  const result = spawnSync(file, args, { encoding: 'utf8', timeout: 90_000, maxBuffer: 4 * 1024 * 1024 });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(file + ' failed: ' + result.stderr.trim());
  return result.stdout;
}

// Printed by --dump-dom after synchronous instantiation and timing. No virtual
// time, network, rendering, or timers are involved in a measured sample.
function measure(exp) {
  const result = [];
  for (let i = 0; i < exp.bench_cases(); i++) {
    if (!exp.bench_setup(i)) throw new Error('Wasm setup failed for case ' + i);
    const times = [];
    for (let j = 0; j < exp.bench_samples(); j++) {
      const start = performance.now();
      if (!exp.bench_sample()) throw new Error('Wasm sample failed for case ' + i);
      times.push(performance.now() - start);
    }
    if (!exp.bench_verify()) throw new Error('Wasm workload state changed for case ' + i);
    times.sort((a, b) => a - b);
    result.push({
      facts: exp.bench_facts(), entities: exp.bench_entities(), fibers: exp.bench_fibers(),
      ticks: exp.bench_ticks(), samples: exp.bench_samples(), ms: times[Math.floor(times.length / 2)],
    });
  }
  return result;
}

function browserRows(chrome, wasmPath) {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'bespoke-bench-'));
  try {
    const html = path.join(work, 'bench.html');
    const wasm = fs.readFileSync(wasmPath).toString('base64');
    fs.writeFileSync(html, '<!doctype html><pre id="result"></pre><script>\n' +
      'const output = document.getElementById("result");\n' +
      'try { const wasm = Uint8Array.from(atob("' + wasm + '"), c => c.charCodeAt(0));\n' +
      'const exp = new WebAssembly.Instance(new WebAssembly.Module(wasm), {}).exports;\n' +
      'output.textContent = JSON.stringify((' + measure.toString() + ')(exp));\n' +
      '} catch (err) { output.textContent = JSON.stringify({ error: err.message }); }\n' +
      // --dump-dom prints the live DOM, which would otherwise repeat the module's base64 and
      // outgrow the capture buffer as the engine grows; the result is all the runner reads.
      'document.currentScript.remove();\n</script>');
    const args = ['--headless=new', '--disable-gpu', '--disable-background-networking', '--no-first-run',
      '--no-default-browser-check', '--user-data-dir=' + path.join(work, 'profile'), '--dump-dom'];
    // CI's Chrome smoke check uses the same option on its disposable runner.
    if (process.env.BESPOKE_BENCH_CHROME_NO_SANDBOX === '1') args.push('--no-sandbox');
    const dom = run(chrome, [...args, pathToFileURL(html).href]);
    const match = dom.match(/<pre id="result">([^<]*)<\/pre>/);
    if (!match || !match[1]) throw new Error('Chrome did not publish a benchmark result');
    const result = JSON.parse(match[1]);
    if (!Array.isArray(result)) throw new Error(result.error || 'invalid Chrome results');
    return result;
  } finally {
    fs.rmSync(work, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
  }
}

function main() {
  const [nativePath, wasmPath] = process.argv.slice(2);
  const candidates = process.env.CHROME ? [process.env.CHROME] : ['google-chrome', 'google-chrome-stable', 'chromium'];
  let chrome;
  let browserVersion;
  for (const candidate of candidates) {
    try {
      browserVersion = run(candidate, ['--version']).trim();
      chrome = candidate;
      break;
    } catch (err) {
      if (process.env.CHROME) throw err;
    }
  }
  if (!chrome) throw new Error('Chrome or Chromium was not found; set CHROME to its executable');
  const native = run(nativePath, []).trim().split('\n').map(line => JSON.parse(line));
  const browser = browserRows(chrome, wasmPath);
  if (!native.length || native.length !== browser.length) throw new Error('native and Chrome case counts differ');
  console.log('BeSpoke P41-01 | ' + os.platform() + '/' + os.arch() + ' | ' + browserVersion + ' | ReleaseFast');
  console.log('CPU: ' + (os.cpus()[0]?.model || 'unknown'));
  console.log('Median of ' + native[0].samples + ' x ' + native[0].ticks +
    ' simulation ticks; setup, rendering and audio excluded.');
  console.log('case'.padEnd(16) + 'facts    entities   fibers   native ticks/s   Chrome ticks/s');
  for (const [i, a] of native.entries()) {
    const b = browser[i];
    for (const key of ['facts', 'entities', 'fibers', 'ticks', 'samples']) {
      if (a[key] !== b[key]) throw new Error(a.name + ': inconsistent ' + key);
    }
    for (const row of [a, b]) {
      if (!(Number.isFinite(row.ms) && row.ms > 0)) throw new Error(a.name + ': invalid elapsed time');
    }
    const rate = row => (1000 * row.ticks / row.ms).toFixed(0);
    console.log(a.name.padEnd(16) + String(a.facts).padEnd(9) + String(a.entities).padEnd(11) +
      String(a.fibers).padEnd(9) + rate(a).padEnd(17) + rate(b));
  }
}

try {
  main();
} catch (err) {
  console.error('benchmark failed: ' + err.message);
  process.exitCode = 1;
}
