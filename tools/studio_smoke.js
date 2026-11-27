// P47-01 (D-192): BeSpoke Studio in real headless Chrome, through the DevTools protocol, with no
// browser package. The project folder is the page's origin-private file system, a real
// directory handle the Studio opens exactly as it opens one from the folder picker.
//
// Run after `zig build studio && python3 tools/build_studio.py`:
//   CHROME=/path/to/chrome node tools/studio_smoke.js
//
// Checks, in order:
//   1. the workspace starts with the compiler ready and no fault;
//   2. opening and saving a project without edits leaves every file byte-identical and
//      unwritten (the P47-01 acceptance), including bytes a text round trip would change;
//   3. a project that does not compile opens to a working Studio with its diagnostic shown,
//      and the held secondary-button menu and a command key still work beside it;
//   4. a compiler module that fails to load falls back to the workspace with a fault panel,
//      and the Studio still opens a project (D-192 item 5);
//   5. a saved setting the page cannot use is reported and replaced for the visit.
'use strict';

const fs = require('fs');
const http = require('http');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const root = path.resolve(__dirname, '..');
const chrome = process.env.CHROME || 'google-chrome';
const CHROME_START_TIMEOUT_MS = 60000;
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'bespoke-studio-chrome-'));
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
  throw new Error(`timed out waiting for ${label}${last ? ` (${JSON.stringify(last)})` : ''}`);
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

// Writes a fixture project into the origin-private file system and returns, per file, its
// bytes (base64) and modification time, read back from disk.
const WRITE_FIXTURE = (files) => `(async () => {
  const files = ${JSON.stringify(files)};
  const top = await navigator.storage.getDirectory();
  try { await top.removeEntry('project', { recursive: true }); } catch {}
  const dir = await top.getDirectoryHandle('project', { create: true });
  for (const [p, b64] of Object.entries(files)) {
    const parts = p.split('/');
    let d = dir;
    for (const part of parts.slice(0, -1)) d = await d.getDirectoryHandle(part, { create: true });
    const fh = await d.getFileHandle(parts[parts.length - 1], { create: true });
    const w = await fh.createWritable();
    await w.write(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)));
    await w.close();
  }
  return true;
})()`;

const SNAPSHOT = `(async () => {
  const out = {};
  async function walk(d, prefix) {
    for await (const h of d.values()) {
      const p = prefix ? prefix + '/' + h.name : h.name;
      if (h.kind === 'directory') { await walk(h, p); continue; }
      const f = await h.getFile();
      const bytes = new Uint8Array(await f.arrayBuffer());
      let s = '';
      for (const b of bytes) s += String.fromCharCode(b);
      out[p] = { b64: btoa(s), modified: f.lastModified };
    }
  }
  const top = await navigator.storage.getDirectory();
  await walk(await top.getDirectoryHandle('project'), '');
  return out;
})()`;

const PROJECT_DIR = `navigator.storage.getDirectory().then((t) => t.getDirectoryHandle('project'))`;

function b64(text) {
  return Buffer.from(text, 'latin1').toString('base64');
}

const YARD = 'scene Yard:\n  cast: Walker\n  marks: Gate, Well\n\nroutine Stroll(Walker):\n  walk Walker to Well\n';
const VALID = {
  'scripts/main.bespoke': b64('include "rooms/yard.bespoke"\n'),
  'scripts/rooms/yard.bespoke': b64(YARD),
  // Bytes a decode-and-encode round trip would change: a byte-order mark, CRLF, a lone CR,
  // no final newline, and a byte that is not UTF-8. Opened, never compiled (not included).
  'scripts/notes.bespoke': b64('\xef\xbb\xbf# notes\r\nline two\rline three \xff'),
  'scripts/art/lamp.png': b64('\x89PNG\r\n\x1a\nnot really an image'),
  // Never read by the Studio at all.
  'README.md': b64('# fixture\n'),
  'zig-out/bin/ignored.bespoke': b64('scene Nope:\n'),
};

async function run(pageUrl) {
  const child = spawn(chrome, [
    '--headless=new', '--no-sandbox', '--disable-gpu',
    '--remote-debugging-port=0', `--user-data-dir=${profile}`, 'about:blank',
  ], { stdio: ['ignore', 'ignore', 'pipe'] });
  child.stderr.on('data', (chunk) => { stderr += chunk; });
  child.on('error', (error) => { stderr += error.message; });

  try {
    const portFile = path.join(profile, 'DevToolsActivePort');
    const port = await waitFor('Chrome DevTools port', () => {
      if (!fs.existsSync(portFile)) return null;
      return Number(fs.readFileSync(portFile, 'utf8').split('\n', 1)[0]) || null;
    }, CHROME_START_TIMEOUT_MS);
    const target = await waitFor('blank page target', async () => {
      const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
      return targets.find((item) => item.type === 'page');
    }, CHROME_START_TIMEOUT_MS);
    const cdp = new Cdp(target.webSocketDebuggerUrl);
    await cdp.open();
    await cdp.send('Runtime.enable');
    await cdp.send('Page.enable');
    await cdp.send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 800, deviceScaleFactor: 1, mobile: false });

    const evaluate = async (expression) => {
      const result = await cdp.send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
      if (result.exceptionDetails) {
        throw new Error(result.exceptionDetails.exception?.description || result.exceptionDetails.text);
      }
      return result.result.value;
    };
    const state = () => evaluate('window.bespokeStudio && window.bespokeStudio.state()');
    const load = async (label) => {
      await cdp.send('Page.navigate', { url: pageUrl });
      return waitFor(`${label}: Studio ready`, async () => {
        const s = await state();
        return s && s.ready && (await evaluate('window.bespokeStudio.compilerReady()')) ? s : null;
      });
    };
    const centre = (selector) => evaluate(`(() => {
      const el = document.querySelector(${JSON.stringify(selector)});
      if (!el) return null;
      const b = el.getBoundingClientRect();
      return { x: b.left + b.width / 2, y: b.top + b.height / 2 };
    })()`);
    const mouse = (type, at, button = 'left', buttons = 0) => cdp.send('Input.dispatchMouseEvent', {
      type, x: at.x, y: at.y, button, buttons, clickCount: type === 'mouseMoved' ? 0 : 1, pointerType: 'mouse',
    });
    const click = async (selector) => {
      const at = await waitFor(`${selector} on screen`, () => centre(selector));
      await mouse('mousePressed', at, 'left', 1);
      await mouse('mouseReleased', at, 'left', 0);
    };
    const key = async (keyName, code, vk, modifiers = 0) => {
      await cdp.send('Input.dispatchKeyEvent', { type: 'rawKeyDown', key: keyName, code, windowsVirtualKeyCode: vk, modifiers });
      await cdp.send('Input.dispatchKeyEvent', { type: 'keyUp', key: keyName, code, windowsVirtualKeyCode: vk, modifiers });
    };
    const requester = (title) => waitFor(`requester "${title}"`, async () => ((await state()).requester === title ? true : null));
    const noRequester = () => waitFor('requester to close', async () => ((await state()).requester === null ? true : null));

    // 1. Start.
    let s = await load('start');
    if (s.compiler.state !== 'ready' || s.fault || s.faults.length) throw new Error(`start: ${JSON.stringify(s)}`);
    if (!s.windows.includes('project')) throw new Error('start: no Project window');
    console.log(`ok  workspace up, compiler ready, windows ${s.windows.join(', ')}`);

    // 2. Open and save without edits.
    await evaluate(WRITE_FIXTURE(VALID));
    const before = await evaluate(SNAPSHOT);
    await delay(20);
    await evaluate(`${PROJECT_DIR}.then((d) => window.bespokeStudio.openDirectory(d))`);
    s = await state();
    if (!s.result || !s.result.valid || s.project.main !== 'scripts/main.bespoke') throw new Error(`open: ${JSON.stringify(s)}`);
    const opened = s.project.files.map((f) => f.path).sort();
    const expected = ['scripts/art/lamp.png', 'scripts/main.bespoke', 'scripts/notes.bespoke', 'scripts/rooms/yard.bespoke'];
    if (JSON.stringify(opened) !== JSON.stringify(expected)) throw new Error(`open read ${opened.join(', ')}`);
    await evaluate('window.__save = window.bespokeStudio.save(); true');
    await requester('Save');
    await click('.req-buttons .gad');
    await noRequester();
    const saved = await evaluate('window.__save');
    if (saved.written !== 0 || saved.changed.length) throw new Error(`save: ${JSON.stringify(saved)}`);
    const after = await evaluate(SNAPSHOT);
    for (const [p, was] of Object.entries(before)) {
      const now = after[p];
      if (!now || now.b64 !== was.b64) throw new Error(`save changed the bytes of ${p}`);
      if (now.modified !== was.modified) throw new Error(`save wrote ${p} (modified ${was.modified} -> ${now.modified})`);
    }
    if (Object.keys(after).length !== Object.keys(before).length) throw new Error('save added or removed files');
    console.log(`ok  open and save without edits: ${Object.keys(before).length} files byte-identical and unwritten`);

    // 3. A project that does not compile.
    await evaluate(WRITE_FIXTURE({ ...VALID, 'scripts/rooms/yard.bespoke': b64('scene Yard:\n  cast: Walker\n\nroutine Stroll(Walker):\n  walk Walker to\n') }));
    await evaluate(`${PROJECT_DIR}.then((d) => { window.bespokeStudio.openDirectory(d); return true; })`);
    await requester('Script check');
    s = await state();
    const r = s.result;
    if (r.valid || r.file !== 'scripts/rooms/yard.bespoke' || r.line !== 6 || r.kind !== 'UnexpectedToken') {
      throw new Error(`broken project diagnostic: ${JSON.stringify(r)}`);
    }
    if (!s.windows.includes('diagnostics')) throw new Error('broken project: no Diagnostics window');
    await click('.req-buttons .gad');
    await waitFor('script window', async () => ((await state()).windows.includes('script:scripts/rooms/yard.bespoke') ? true : null));
    const marked = await evaluate("document.querySelector('[data-window=\"script:scripts/rooms/yard.bespoke\"] .mark .sr').textContent");
    if (!/^6\b/.test(marked)) throw new Error(`script window marked ${JSON.stringify(marked)}`);
    console.log(`ok  broken project opens: ${r.file}:${r.line}:${r.column} ${r.kind}, line ${r.line} shown`);

    // The held menu: secondary button down on the workspace, across to Project, down to an
    // item, release. The About window was open from the start; close it so the pick shows.
    await evaluate("document.querySelector('[data-window=\"about\"] .g-close').click(); true");
    await waitFor('About closed', async () => (!(await state()).windows.includes('about') ? true : null));
    const desk = { x: 1000, y: 700 };
    await mouse('mouseMoved', desk);
    await mouse('mousePressed', desk, 'right', 2);
    await waitFor('menu strip', () => evaluate("document.querySelector('.sbar.menus-open') !== null"));
    const title = await centre('.strip .m-title');
    await mouse('mouseMoved', title, 'none', 2);
    const item = await waitFor('About item', () => evaluate(`(() => {
      const el = [...document.querySelectorAll('.m-title.open .m-item')].find((b) => b.dataset.gadget === 'about');
      if (!el) return null;
      const b = el.getBoundingClientRect();
      return { x: b.left + b.width / 2, y: b.top + b.height / 2 };
    })()`));
    await mouse('mouseMoved', item, 'none', 2);
    await mouse('mouseReleased', item, 'right', 0);
    await waitFor('About from the held menu', async () => ((await state()).windows.includes('about') ? true : null));
    if (await evaluate("document.querySelector('.sbar.menus-open') !== null")) throw new Error('menu strip stayed open');
    console.log('ok  held secondary-button menu picks About the Studio');

    // A command key re-checks; Escape answers the requester with its last gadget.
    await key('k', 'KeyK', 75, 2);
    await requester('Script check');
    await key('Escape', 'Escape', 27);
    await noRequester();
    console.log('ok  Ctrl K checks again; Escape closes the requester');

    // 4. The compiler module fails to load.
    const hook = await cdp.send('Page.addScriptToEvaluateOnNewDocument', {
      source: 'WebAssembly.instantiate = () => Promise.reject(new Error("test fault"));',
    });
    s = await load('compiler fault');
    if (s.compiler.state !== 'unavailable' || !/test fault/.test(s.compiler.error)) throw new Error(`fault: ${JSON.stringify(s.compiler)}`);
    await waitFor('fault panel', async () => ((await state()).fault ? true : null));
    await click('.fault');
    await waitFor('fault panel to close', async () => (!(await state()).fault ? true : null));
    await evaluate(WRITE_FIXTURE(VALID));
    await evaluate(`${PROJECT_DIR}.then((d) => window.bespokeStudio.openDirectory(d))`);
    s = await state();
    if (!s.project || s.project.files.length !== 4 || s.result !== null) throw new Error(`fault open: ${JSON.stringify(s)}`);
    await evaluate('window.bespokeStudio.check(); true');
    await requester('Check');
    await key('Escape', 'Escape', 27);
    await noRequester();
    await cdp.send('Page.removeScriptToEvaluateOnNewDocument', { identifier: hook.identifier });
    console.log('ok  compiler fault: fault panel, then a working workspace that opens a project and explains Check');

    // 5. A saved setting the page cannot use.
    await evaluate("localStorage.setItem('bespoke.studio.scale', 'banana'); true");
    s = await load('bad setting');
    await requester('Settings');
    if (s.scale !== 2) throw new Error(`bad setting: scale ${s.scale}`);
    await click('.req-buttons .gad');
    await noRequester();
    const stored = await evaluate("localStorage.getItem('bespoke.studio.scale')");
    if (stored !== '2') throw new Error(`Use 2x stored ${stored}`);
    await evaluate("localStorage.removeItem('bespoke.studio.scale'); true");
    console.log('ok  bad saved scale: reported, 2x used, replaced on request');

    const faults = (await state()).faults;
    if (faults.length) throw new Error(`unexpected faults: ${faults.join(' | ')}`);
    cdp.close();
  } finally {
    const exited = new Promise((resolve) => child.once('exit', resolve));
    if (child.exitCode === null) child.kill('SIGTERM');
    await Promise.race([exited, delay(5000)]);
    if (child.exitCode === null) child.kill('SIGKILL');
    try { fs.rmSync(profile, { recursive: true, force: true, maxRetries: 20, retryDelay: 100 }); } catch (error) {
      console.warn(`WARN could not remove Chrome profile ${profile}: ${error.message}`);
    }
  }
}

async function main() {
  const page = fs.readFileSync(path.join(root, 'site', 'studio.html'));
  const server = http.createServer((req, res) => {
    if (req.method === 'GET' && new URL(req.url, 'http://localhost').pathname === '/studio.html') {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }).end(page);
    } else res.writeHead(404).end();
  });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  try {
    await run(`http://127.0.0.1:${server.address().port}/studio.html`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

main().catch((error) => {
  console.error(`FAIL studio smoke: ${error.message}`);
  if (stderr.trim()) console.error(stderr.trim().split('\n').slice(-5).join('\n'));
  process.exit(1);
});
