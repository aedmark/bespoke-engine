// Chrome CDP browser check for The Sunken Vault standalone page (P49-03):
// verifies 375 px touch targets & layout, 60 Hz colour cycling on #stage while turn=0,
// picture toggle, hint button, refusal taking 0 turns, and full parser victory route.
'use strict';

const fs = require('fs');
const http = require('http');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const htmlPath = path.resolve(process.argv[2]);
const htmlBytes = fs.readFileSync(htmlPath);
const chrome = process.env.CHROME || 'google-chrome';
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'bespoke-sv-chrome-'));

function delay(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function waitFor(label, fn, timeoutMs = 15000) {
  const deadline = Date.now() + timeoutMs;
  let last;
  while (Date.now() < deadline) {
    try {
      last = await fn();
      if (last) return last;
    } catch (err) {
      last = err.message;
    }
    await delay(50);
  }
  throw new Error(`timed out waiting for ${label}${last ? ` (${last})` : ''}`);
}

class Cdp {
  constructor(url) {
    this.nextId = 1;
    this.pending = new Map();
    this.ws = new WebSocket(url);
    this.ws.addEventListener('message', (ev) => {
      const msg = JSON.parse(ev.data);
      if (!msg.id || !this.pending.has(msg.id)) return;
      const { resolve, reject } = this.pending.get(msg.id);
      this.pending.delete(msg.id);
      if (msg.error) reject(new Error(msg.error.message));
      else resolve(msg.result);
    });
  }
  async open() {
    if (this.ws.readyState === WebSocket.OPEN) return;
    await new Promise((resolve, reject) => {
      this.ws.addEventListener('open', resolve, { once: true });
      this.ws.addEventListener('error', () => reject(new Error('CDP WebSocket failed')), { once: true });
    });
  }
  send(method, params = {}) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }
  close() { this.ws.close(); }
}

async function main() {
  const server = http.createServer((req, res) => {
    if (req.url === '/' || req.url === '/index.html') {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(htmlBytes);
    } else {
      res.writeHead(404);
      res.end();
    }
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const { port } = server.address();
  const baseUrl = `http://127.0.0.1:${port}/index.html`;

  const args = [
    '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
    '--remote-debugging-port=0', `--user-data-dir=${profile}`,
  ];
  if (process.env.BESPOKE_BENCH_CHROME_NO_SANDBOX === '1' || process.getuid() === 0) args.push('--no-sandbox');
  args.push('about:blank');

  const proc = spawn(chrome, args, { stdio: ['ignore', 'ignore', 'pipe'] });
  let stderr = '';
  proc.stderr.on('data', (c) => { stderr += c.toString(); });

  try {
    const activePortPath = path.join(profile, 'DevToolsActivePort');
    const portText = await waitFor('Chrome DevToolsActivePort', () =>
      fs.existsSync(activePortPath) ? fs.readFileSync(activePortPath, 'utf8').trim() : null, 45000
    );
    const [cdpPort] = portText.split('\n');
    const targets = await (await fetch(`http://127.0.0.1:${cdpPort}/json/list`)).json();
    const cdp = new Cdp(targets.find((t) => t.type === 'page').webSocketDebuggerUrl);
    await cdp.open();

    const evalJs = async (expression) => {
      const res = await cdp.send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
      if (res.exceptionDetails) throw new Error(res.exceptionDetails.text);
      return res.result.value;
    };

    await cdp.send('Emulation.setDeviceMetricsOverride', { width: 375, height: 812, deviceScaleFactor: 1, mobile: true });
    await cdp.send('Page.enable');
    await cdp.send('Page.navigate', { url: baseUrl });
    await waitFor('Sunken Vault boot', () => evalJs(
      "document.querySelector('#room-name')?.textContent === 'Keep Courtyard' && document.querySelectorAll('#turns .story').length >= 1"
    ));

    // Touch targets >= 44 px and zero horizontal overflow at 375 px.
    const layout = await evalJs(`(() => {
      const nodes = [...document.querySelectorAll('a, button, input, summary')];
      const short = nodes.filter(n => { const b = n.getBoundingClientRect(); return (b.width || b.height) && b.height < 44; });
      return {
        shortCount: short.length,
        overflow: document.documentElement.scrollWidth > document.documentElement.clientWidth,
        turn: document.querySelector('#turn-count').textContent,
      };
    })()`);
    if (layout.shortCount > 0 || layout.overflow) throw new Error(`375px layout check failed: ${JSON.stringify(layout)}`);
    if (layout.turn !== '1') throw new Error(`expected initial turn 1, got ${layout.turn}`);

    // 60 Hz colour cycling changes #stage pixels while turn stays 1.
    const digest = () => evalJs(`(() => {
      const d = document.querySelector('#stage').getContext('2d').getImageData(0, 0, 1280, 720).data;
      let h = 2166136261;
      for (let i = 0; i < d.length; i += 64) h = Math.imul(h ^ d[i] ^ (d[i + 1] << 8) ^ (d[i + 2] << 16), 16777619) >>> 0;
      return h;
    })()`);
    const hA = await digest();
    await waitFor('60 Hz colour cycling on #stage', async () => (await digest()) !== hA);
    if ((await evalJs("document.querySelector('#turn-count').textContent")) !== '1') {
      throw new Error('colour cycling changed turn counter');
    }

    // Picture toggle and hint button work without advancing turns.
    await evalJs("document.querySelector('#picture-toggle').click()");
    if (!await evalJs("document.querySelector('#picture-wrap').hidden")) throw new Error('picture did not hide');
    await evalJs("document.querySelector('#picture-toggle').click()");
    if (await evalJs("document.querySelector('#picture-wrap').hidden")) throw new Error('picture did not show');
    await evalJs("document.querySelector('#hint-btn').click()");
    await waitFor('hint row', () => evalJs("document.querySelectorAll('#turns .hint').length === 1"));
    if ((await evalJs("document.querySelector('#turn-count').textContent")) !== '1') throw new Error('hint advanced turn');

    // Submit refusal + full victory route through #command-form.
    const submit = async (line) => {
      await evalJs(`(() => {
        document.querySelector('#command').value = ${JSON.stringify(line)};
        document.querySelector('#command-form').dispatchEvent(new Event('submit', { cancelable: true }));
      })()`);
    };
    await submit('xyzzy');
    await waitFor('refusal line', () => evalJs("[...document.querySelectorAll('#turns .story')].some(p => p.textContent.includes(\"don't know\"))"));
    if ((await evalJs("document.querySelector('#turn-count').textContent")) !== '1') throw new Error('refusal advanced turn');

    const route = [
      'east', 'take flint', 'take torch', 'take key', 'read ledger',
      'west', 'down', 'east', 'turn wheel', 'west',
      'light torch', 'north', 'unlock gate with key', 'north',
      'take crown', 'south', 'south', 'up',
    ];
    for (const cmd of route) await submit(cmd);
    await waitFor('victory prose', () => evalJs(
      "document.querySelector('#room-name').textContent === 'Keep Courtyard' && document.querySelector('#turn-count').textContent === '19' && [...document.querySelectorAll('#turns .story')].some(p => p.textContent.includes('Crown of Tides shining'))"
    ));

    console.log('ok  Sunken Vault Chrome: 375px touch targets, 60Hz colour cycling, hint, and 18-turn victory');
    cdp.close();
  } finally {
    proc.kill('SIGTERM');
    server.close();
    try { fs.rmSync(profile, { recursive: true, force: true }); } catch (err) { console.warn(`WARN could not remove Chrome profile: ${err.message}`); }
    if (stderr.includes('FATAL')) console.error(stderr);
  }
}

main().catch((err) => {
  console.error(`FAIL Sunken Vault Chrome: ${err.message}`);
  process.exit(1);
});
