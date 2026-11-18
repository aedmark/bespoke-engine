// P41-02: native golden and save, real Chrome parser play, matched timings.
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const { pathToFileURL } = require('node:url');

function run(file, args) {
  const result = spawnSync(file, args, { encoding: 'utf8', timeout: 90_000, maxBuffer: 4 * 1024 * 1024 });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(file + ': ' + result.stderr.trim());
  return result.stdout;
}

function verifyBrowser() {
  start.click();
  clearInterval(timer);
  const submit = text => { input.value = text; form.requestSubmit(); };
  for (let i = 0; i < 8; i++) tick();
  if (!log.textContent.includes('The watch has changed.')) throw new Error('society did not advance in Chrome');
  const tasks = ['read tide board', 'read duty book', 'read market slate', 'take wick',
    'take flag', 'read manifest', 'turn lever', 'read bell code', 'secure mooring', 'signal packet'];
  for (const [room, task] of tasks.entries()) {
    if (room) submit(room % 2 ? 'go forward' : 'go to forward');
    for (let i = 0; i < 32 && harbour.harbour_room() !== room; i++) tick();
    if (harbour.harbour_room() !== room) throw new Error('unreachable browser room ' + room);
    submit(task);
  }
  if (!harbour.harbour_clear() || !log.textContent.includes('The dawn packet is clear.')) {
    throw new Error('browser parser did not clear the packet');
  }
  if (document.getElementById('map').open) throw new Error('route required the map');
  submit('go back');
  for (let i = 0; i < 32 && harbour.harbour_room() !== 8; i++) tick();
  if (harbour.harbour_room() !== 8) throw new Error('return doorway did not work');

  return [0, 4096].map(extra => {
    if (!harbour.harbour_bench_setup(extra)) throw new Error('Wasm benchmark setup failed');
    const facts = harbour.harbour_facts();
    const times = [];
    for (let i = 0; i < harbour.harbour_samples(); i++) {
      const before = performance.now();
      if (!harbour.harbour_bench_sample()) throw new Error('Wasm benchmark sample failed');
      times.push(performance.now() - before);
    }
    times.sort((a, b) => a - b);
    return { extra, facts, endFacts: harbour.harbour_facts(), ticks: harbour.harbour_sample_ticks(),
      ms: times[Math.floor(times.length / 2)] };
  });
}

function main() {
  const [exe, wasm, template, golden, license, out] = process.argv.slice(2);
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'bespoke-harbour-'));
  try {
    const escape = s => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
    const html = fs.readFileSync(template, 'utf8').replace('__HARBOUR_WASM__', fs.readFileSync(wasm).toString('base64'))
      .replace('</body>', '<template id="bespoke-license"><pre>' + escape(fs.readFileSync(license, 'utf8')) + '</pre></template>\n</body>');
    const limit = require('../../tools/web_budgets.json').standalonePageBytes;
    if (Buffer.byteLength(html) > limit) throw new Error('reference page exceeds standalone page budget');
    const transcript = run(exe, [path.join(work, 'customs.sav')]);
    assert.equal(transcript, fs.readFileSync(golden, 'utf8'), 'native transcript differs from the golden');
    const native = run(exe, ['--bench']).trim().split('\n').map(line => JSON.parse(line));
    const testPage = path.join(work, 'test.html');
    fs.writeFileSync(testPage, html.replace('</body>',
      '<pre id="result"></pre><script>try { document.getElementById("result").textContent = JSON.stringify((' +
      verifyBrowser.toString() + ')()); } catch (e) { document.getElementById("result").textContent = JSON.stringify({error: e.message}); }</script></body>'));
    const candidates = process.env.CHROME ? [process.env.CHROME] : ['google-chrome', 'google-chrome-stable', 'chromium'];
    const chrome = candidates.find(candidate => spawnSync(candidate, ['--version'], { stdio: 'ignore' }).status === 0);
    if (!chrome) throw new Error('Chrome or Chromium was not found; set CHROME');
    const args = ['--headless=new', '--disable-gpu', '--disable-background-networking', '--no-first-run',
      '--user-data-dir=' + path.join(work, 'profile'), '--dump-dom'];
    if (process.env.BESPOKE_BENCH_CHROME_NO_SANDBOX === '1') args.push('--no-sandbox');
    const dom = run(chrome, [...args, pathToFileURL(testPage).href]);
    const match = dom.match(/<pre id="result">([^<]*)<\/pre>/);
    if (!match || !match[1]) throw new Error('Chrome returned no reference game result');
    const browser = JSON.parse(match[1]);
    if (!Array.isArray(browser)) throw new Error(browser.error || 'invalid Chrome result');
    assert.equal(browser.length, native.length);
    console.log('Harbour: native golden and .sav restore; all ten scenes via parser in Chrome');
    console.log(run(chrome, ['--version']).trim() + '; ReleaseFast, median of 3 samples; rendering excluded');
    for (const [i, n] of native.entries()) {
      const b = browser[i];
      for (const key of ['extra', 'facts', 'endFacts', 'ticks']) assert.equal(b[key], n[key], key);
      for (const row of [n, b]) assert(Number.isFinite(row.ms) && row.ms > 0, 'invalid sample time');
      const rate = row => (1000 * row.ticks / row.ms).toFixed(0);
      console.log(n.facts + ' initial facts (' + n.extra + ' ballast), ' + n.endFacts +
        ' final: Linux ' + rate(n) + ', Chrome ' + rate(b) + ' ticks/s');
    }
    fs.writeFileSync(out, html);
    console.log('Packed Harbour page: ' + Buffer.byteLength(html).toLocaleString('en-US') + ' / ' + limit + ' bytes');
  } finally {
    fs.rmSync(work, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
  }
}

try {
  main();
} catch (err) {
  console.error('Harbour: ' + err.message);
  process.exitCode = 1;
}
