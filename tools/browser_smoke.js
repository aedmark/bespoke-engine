// P37-02: open a generated standalone proof page from file:// in real headless Chrome,
// start its AudioWorklet through a click, and advance its engine state through the solve key.
// This uses Chrome's DevTools protocol directly so the repository needs no browser package.
//
// Run after `zig build wasm-proofs && python3 tools/build_site.py`:
//   CHROME=/path/to/chrome node tools/browser_smoke.js
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const { pathToFileURL } = require('url');

const root = path.resolve(__dirname, '..');
const pageUrl = pathToFileURL(path.join(root, 'site', 'pips.html')).href;
const chrome = process.env.CHROME || 'google-chrome';
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'bespoke-chrome-'));
let stderr = '';

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitFor(label, read, timeoutMs = 15000) {
  const deadline = Date.now() + timeoutMs;
  let last;
  while (Date.now() < deadline) {
    try {
      last = await read();
      if (last) return last;
    } catch (error) {
      last = error.message;
    }
    await delay(50);
  }
  throw new Error(`timed out waiting for ${label}${last ? ` (${last})` : ''}`);
}

class Cdp {
  constructor(url) {
    this.nextId = 1;
    this.pending = new Map();
    this.socket = new WebSocket(url);
    this.socket.addEventListener('message', (event) => {
      const message = JSON.parse(event.data);
      if (!message.id || !this.pending.has(message.id)) return;
      const { resolve, reject } = this.pending.get(message.id);
      this.pending.delete(message.id);
      if (message.error) reject(new Error(message.error.message));
      else resolve(message.result);
    });
  }

  async open() {
    if (this.socket.readyState === WebSocket.OPEN) return;
    await new Promise((resolve, reject) => {
      this.socket.addEventListener('open', resolve, { once: true });
      this.socket.addEventListener('error', () => reject(new Error('DevTools WebSocket failed')), { once: true });
    });
  }

  send(method, params = {}) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.socket.send(JSON.stringify({ id, method, params }));
    });
  }

  close() {
    this.socket.close();
  }
}

async function main() {
  const child = spawn(chrome, [
    '--headless=new',
    '--no-sandbox',
    '--disable-gpu',
    '--disable-background-timer-throttling',
    '--disable-renderer-backgrounding',
    '--autoplay-policy=no-user-gesture-required',
    '--remote-debugging-port=0',
    `--user-data-dir=${profile}`,
    pageUrl,
  ], { stdio: ['ignore', 'ignore', 'pipe'] });
  child.stderr.on('data', (chunk) => { stderr += chunk; });
  child.on('error', (error) => { stderr += error.message; });

  try {
    const portFile = path.join(profile, 'DevToolsActivePort');
    const port = await waitFor('Chrome DevTools port', () => {
      if (!fs.existsSync(portFile)) return null;
      return Number(fs.readFileSync(portFile, 'utf8').split('\n', 1)[0]) || null;
    });
    const target = await waitFor('proof page target', async () => {
      const response = await fetch(`http://127.0.0.1:${port}/json/list`);
      const targets = await response.json();
      return targets.find((item) => item.type === 'page' && item.url === pageUrl);
    });
    const cdp = new Cdp(target.webSocketDebuggerUrl);
    await cdp.open();
    await cdp.send('Runtime.enable');
    await cdp.send('Page.enable');

    const evaluate = async (expression) => {
      const result = await cdp.send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
      if (result.exceptionDetails) throw new Error(result.exceptionDetails.text);
      return result.result.value;
    };
    const state = () => evaluate('window.bespokePageState && window.bespokePageState()');
    const initial = await waitFor('embedded engine', async () => {
      const value = await state();
      return value && value.ready ? value : null;
    });
    if (await evaluate("document.querySelector('#game-status').textContent") !== '') {
      throw new Error('proof page reported a startup error');
    }

    const center = await evaluate(`(() => {
      const button = document.querySelector('#btn-sound');
      button.scrollIntoView({ block: 'center' });
      const box = button.getBoundingClientRect();
      return { x: box.left + box.width / 2, y: box.top + box.height / 2 };
    })()`);
    await cdp.send('Input.dispatchMouseEvent', { type: 'mousePressed', x: center.x, y: center.y, button: 'left', clickCount: 1 });
    await cdp.send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: center.x, y: center.y, button: 'left', clickCount: 1 });
    let sounded;
    try {
      sounded = await waitFor('engine audio', async () => {
        const value = await state();
        return value && value.soundOn && value.audioPlaying ? value : null;
      });
    } catch (error) {
      const value = await state();
      const label = await evaluate("document.querySelector('#btn-sound').textContent");
      throw new Error(`${error.message}; state ${JSON.stringify(value)}, button ${JSON.stringify(label)}`);
    }

    await cdp.send('Input.dispatchKeyEvent', { type: 'keyDown', key: 's', code: 'KeyS', windowsVirtualKeyCode: 83 });
    await cdp.send('Input.dispatchKeyEvent', { type: 'keyUp', key: 's', code: 'KeyS', windowsVirtualKeyCode: 83 });
    const advanced = await waitFor('solve-key state change', async () => {
      const value = await state();
      return value && value.facts !== initial.facts ? value : null;
    });
    console.log(`ok  file proof page: audio playing, S changed facts ${initial.facts} -> ${advanced.facts}, tick ${sounded.tick} -> ${advanced.tick}`);
    cdp.close();
  } finally {
    const exited = new Promise((resolve) => child.once('exit', resolve));
    if (child.exitCode === null) child.kill('SIGTERM');
    await Promise.race([exited, delay(5000)]);
    if (child.exitCode === null) {
      child.kill('SIGKILL');
      await Promise.race([exited, delay(2000)]);
    }
    try {
      fs.rmSync(profile, { recursive: true, force: true, maxRetries: 20, retryDelay: 100 });
    } catch (error) {
      // The runner discards /tmp after the job. A late Chrome helper must not overturn a
      // completed engine check merely because it held its disposable profile a little longer.
      console.warn(`WARN could not remove Chrome profile ${profile}: ${error.message}`);
    }
  }
}

main().catch((error) => {
  console.error(`FAIL browser smoke: ${error.message}`);
  if (stderr.trim()) console.error(stderr.trim());
  process.exit(1);
});
