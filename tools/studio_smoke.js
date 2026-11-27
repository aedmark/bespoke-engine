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
//   5. a saved setting the page cannot use is reported and replaced for the visit;
//   6. (P47-06, D-195) The Sunken Vault, PNG art and all, builds and plays in the play
//      window's own module: the clock runs, the gadgets drive it, a package the runtime refuses
//      and a trap mid-run each leave a working Studio, and Run starts the game again;
//   7. (P47-02, D-196) the pixel editor paints one pixel of a Vault sheet in a palette colour,
//      undoes and redoes it, Check and Play use the edit before Save, and Save writes that one
//      PNG and nothing else; the command line then compiles the saved project;
//   8. (P47-10, D-197) a new image and a PNG import each add one `image` line after the Vault's
//      last image and one PNG; an import outside the palette is refused with its pixel and adds
//      nothing; Save creates both files and writes the script, and nothing else changes.
'use strict';

const fs = require('fs');
const http = require('http');
const os = require('os');
const path = require('path');
const { spawn, spawnSync } = require('child_process');

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

// The Sunken Vault as it ships: its script and the PNG sheets it names (D-193).
const VAULT = (() => {
  const dir = path.join(path.resolve(__dirname, '..'), 'scenarios', 'sunken_vault');
  const out = { 'main.bespoke': fs.readFileSync(path.join(dir, 'main.bespoke')).toString('base64') };
  for (const name of fs.readdirSync(path.join(dir, 'art')).filter((n) => n.endsWith('.png')).sort()) {
    out[`art/${name}`] = fs.readFileSync(path.join(dir, 'art', name)).toString('base64');
  }
  return out;
})();

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

    // Play on a project that does not compile shows the check's diagnostic and runs nothing.
    await evaluate('window.bespokeStudio.play(); true');
    await requester('Script check');
    await key('Escape', 'Escape', 27);
    await noRequester();
    s = await state();
    if (s.play.status !== 'idle' || s.windows.includes('play')) throw new Error(`broken play: ${JSON.stringify(s.play)}`);
    console.log('ok  Play on a broken project shows its diagnostic and starts nothing');

    // 6. Play. A real-time project first: the clock runs on its own, Pause holds it, Step
    // moves it one tick.
    await evaluate(WRITE_FIXTURE(VALID));
    await evaluate(`${PROJECT_DIR}.then((d) => window.bespokeStudio.openDirectory(d))`);
    await click('[data-window="project"] [data-gadget="play"]');
    await waitFor('the yard running', async () => {
      const p = (await state()).play;
      return p.status === 'running' && p.tick >= 3 ? p : null;
    });
    await click('[data-window="play"] [data-gadget="play-pause"]');
    await delay(200);
    const held = (await state()).play.tick;
    await delay(400);
    if ((await state()).play.tick !== held) throw new Error('Pause did not stop the clock');
    await click('[data-window="play"] [data-gadget="play-step"]');
    await waitFor('one step', async () => ((await state()).play.tick === held + 1 ? true : null));
    await click('[data-window="play"] [data-gadget="play-pause"]');
    await waitFor('the clock again', async () => ((await state()).play.tick > held + 2 ? true : null));
    console.log(`ok  a real-time game plays in its own module; Pause holds tick ${held}, Step moves one`);

    // The Sunken Vault, PNG art and all, on its turn clock: a typed command is one turn.
    await evaluate(WRITE_FIXTURE(VAULT));
    await evaluate(`${PROJECT_DIR}.then((d) => window.bespokeStudio.openDirectory(d))`);
    s = await state();
    if (!s.result || !s.result.valid) throw new Error(`vault check: ${JSON.stringify(s.result)}`);
    await click('[data-window="project"] [data-gadget="play"]');
    const playing = await waitFor('the Vault running', async () => {
      const p = (await state()).play;
      return p.status === 'running' && p.runs === 2 ? p : null;
    });
    await delay(300);
    const painted = await evaluate(`(() => {
      const c = document.querySelector('[data-window="play"] canvas');
      const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
      const seen = new Set();
      for (let i = 0; i < d.length; i += 4 * 97) seen.add((d[i] << 16) | (d[i + 1] << 8) | d[i + 2]);
      return seen.size;
    })()`);
    if (painted < 8) throw new Error(`the play frame shows ${painted} colours`);
    const turn = (await state()).play.tick;
    await click('[data-window="play"] .bar');
    await key('Enter', 'Enter', 13);
    for (const ch of 'look') await cdp.send('Input.dispatchKeyEvent', { type: 'keyDown', key: ch, text: ch, code: `Key${ch.toUpperCase()}`, windowsVirtualKeyCode: ch.toUpperCase().charCodeAt(0) });
    await key('Enter', 'Enter', 13);
    await waitFor('a turn for "look"', async () => ((await state()).play.tick > turn ? true : null));
    await click('[data-window="play"] [data-gadget="play-hint"]');
    await click('[data-window="play"] [data-gadget="play-state"]');
    await click('[data-window="play"] [data-gadget="play-state"]');
    if ((await state()).play.status !== 'running') throw new Error(`gadgets: ${JSON.stringify((await state()).play)}`);
    console.log(`ok  the Vault plays from its PNGs (${painted} colours sampled); "look" took turn ${turn} to ${(await state()).play.tick}; Hint, State`);

    await evaluate('window.bespokeStudio.playBytes([0x42, 0x53, 0x50, 0x4b, 9, 9]); true');
    await requester('Play');
    await key('Escape', 'Escape', 27);
    await noRequester();
    s = await state();
    if (s.play.status !== 'failed' || !s.play.failure || s.compiler.state !== 'ready') throw new Error(`refused package: ${JSON.stringify(s.play)}`);
    console.log(`ok  a refused package: requester (${s.play.failure}), Studio still ready`);

    await click('[data-window="play"] [data-gadget="play-run"]');
    await waitFor('the Vault again', async () => ((await state()).play.status === 'running' ? true : null));
    await evaluate("window.bespokeStudio.playTrap('test trap'); true");
    await waitFor('fault panel', async () => ((await state()).fault ? true : null));
    s = await state();
    if (s.play.status !== 'stopped' || !/test trap/.test(s.play.failure)) throw new Error(`trap: ${JSON.stringify(s.play)}`);
    await click('.fault');
    await waitFor('fault panel to close', async () => (!(await state()).fault ? true : null));
    const rechecked = await evaluate('window.bespokeStudio.check().then((r) => r && r.valid)');
    if (!rechecked) throw new Error('the compiler did not check after the game trapped');
    const runsBefore = (await state()).play.runs;
    await click('[data-window="play"] [data-gadget="play-run"]');
    const again = await waitFor('a fresh play module', async () => {
      const p = (await state()).play;
      return p.status === 'running' && p.runs === runsBefore + 1 ? p : null;
    });
    await evaluate("document.querySelector('[data-window=\"play\"] .g-close').click(); true");
    await waitFor('Play closed', async () => (!(await state()).windows.includes('play') ? true : null));
    console.log(`ok  a trap mid-run: fault panel, Studio checks on, Run starts a fresh module (run ${again.runs})`);

    // 7. The pixel editor on the Vault.
    await evaluate(WRITE_FIXTURE(VAULT));
    await delay(20);
    const vaultBefore = await evaluate(SNAPSHOT);
    await evaluate(`${PROJECT_DIR}.then((d) => window.bespokeStudio.openDirectory(d))`);
    await evaluate('window.bespokeStudio.openArt().then(() => true)');
    s = await state();
    if (!s.windows.includes('art') || !s.paint.images.length || !s.paint.palette) throw new Error(`art listing: ${JSON.stringify(s.paint)}`);
    const sheet = s.paint.images.find((i) => i.file);
    await evaluate(`window.bespokeStudio.openImage(${JSON.stringify(sheet.name)}).then(() => true)`);
    const paintWin = `[data-window="paint:${sheet.name}"]`;
    const was = await evaluate(`window.bespokeStudio.pixelAt(${JSON.stringify(sheet.name)}, 0, 0)`);
    // A palette colour other than the pixel's own.
    const swatchIndex = await evaluate(`(() => {
      const list = [...document.querySelectorAll('${paintWin} .swatch')];
      const want = ${JSON.stringify(was)};
      return list.findIndex((b) => b.getAttribute('aria-label') !== 'Colour ' + want.slice(0, 3).join(' '));
    })()`);
    if (swatchIndex < 0) throw new Error('no other palette colour to paint with');
    await click(`${paintWin} [data-gadget="colour:${swatchIndex}"]`);
    await waitFor('colour chosen', async () => ((await state()).paint.editors[0].tool === 'pencil' ? true : null));
    const colour = (await state()).paint.editors[0].colour;
    await evaluate(`window.bespokeStudio.paintAt(${JSON.stringify(sheet.name)}, 0, 0, 'pencil')`);
    const now = await evaluate(`window.bespokeStudio.pixelAt(${JSON.stringify(sheet.name)}, 0, 0)`);
    if (JSON.stringify(now) !== JSON.stringify([...colour, 255])) throw new Error(`painted ${JSON.stringify(now)}, wanted ${JSON.stringify(colour)}`);
    await click(`${paintWin} [data-gadget="undo"]`);
    await waitFor('undo', async () => (JSON.stringify(await evaluate(`window.bespokeStudio.pixelAt(${JSON.stringify(sheet.name)}, 0, 0)`)) === JSON.stringify(was) ? true : null));
    s = await state();
    if (s.project.files.find((f) => f.path === sheet.file).dirty) throw new Error('undo to the opened pixels left the file marked edited');
    await click(`${paintWin} [data-gadget="redo"]`);
    await waitFor('redo', async () => ((await state()).project.files.find((f) => f.path === sheet.file).dirty ? true : null));
    const checked = await evaluate('window.bespokeStudio.check().then((r) => r && r.valid)');
    if (!checked) throw new Error('the edited sheet does not check');
    const anim = await evaluate(`document.querySelector('${paintWin} [data-gadget="anim:0"]') !== null`);
    if (anim) {
      await click(`${paintWin} [data-gadget="anim:0"]`);
      await waitFor('animation preview', async () => ((await state()).paint.editors[0].frame !== null ? true : null));
    }
    await evaluate('window.__save = window.bespokeStudio.save(); true');
    await requester('Save');
    await click('.req-buttons .gad');
    await noRequester();
    const wrote = await evaluate('window.__save');
    if (wrote.written !== 1 || wrote.failed.length || wrote.changed.length) throw new Error(`paint save: ${JSON.stringify(wrote)}`);
    const vaultAfter = await evaluate(SNAPSHOT);
    for (const [p, before] of Object.entries(vaultBefore)) {
      const after = vaultAfter[p];
      if (p === sheet.file) {
        if (after.b64 === before.b64) throw new Error(`Save did not write ${p}`);
      } else if (!after || after.b64 !== before.b64 || after.modified !== before.modified) throw new Error(`Save touched ${p}`);
    }
    s = await state();
    if (s.project.files.some((f) => f.dirty)) throw new Error('files still marked edited after Save');
    // The command line compiles the saved project, PNG and all, when the CLI is built.
    const cli = path.join(root, 'zig-out', 'bin', 'bespoke');
    let cliNote = 'command line not built, not run';
    if (fs.existsSync(cli)) {
      const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bespoke-studio-vault-'));
      try {
        for (const [p, f] of Object.entries(vaultAfter)) {
          fs.mkdirSync(path.dirname(path.join(dir, p)), { recursive: true });
          fs.writeFileSync(path.join(dir, p), Buffer.from(f.b64, 'base64'));
        }
        const run = spawnSync(cli, ['check', path.join(dir, 'main.bespoke')], { encoding: 'utf8' });
        if (run.status !== 0) throw new Error(`bespoke check on the saved Vault: ${run.stdout}${run.stderr}`);
        cliNote = 'bespoke check passes on the saved files';
      } finally {
        fs.rmSync(dir, { recursive: true, force: true });
      }
    }
    // The animation preview plays the script's own steps: a two-frame idle shows both frames.
    const LAMP_PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAwAAAAICAYAAADN5B7xAAAAHklEQVR4nGNgIAecmKbxHxmTrcGm4sR/ZDysNJACAPPNbhWGp3A1AAAAAElFTkSuQmCC';
    await evaluate(WRITE_FIXTURE({
      'main.bespoke': b64('scene Quay:\n  cast: Hero\n  props: Lamp\n  marks: Steps, Pier\n\nimage LampSheet from "art/lamp.png" frames 6x8\n\nsprite Lamp: LampSheet\n  idle: 0 for 12, 1 for 12\n\nroutine Walk(Hero):\n  walk Hero to Pier\n'),
      'art/lamp.png': LAMP_PNG,
    }));
    await evaluate(`${PROJECT_DIR}.then((d) => window.bespokeStudio.openDirectory(d)).then(() => true)`);
    await evaluate("window.bespokeStudio.openImage('LampSheet').then(() => true)");
    await click('[data-window="paint:LampSheet"] [data-gadget="anim:0"]');
    const seen = new Set();
    await waitFor('both idle frames in the preview', async () => {
      const ed = (await state()).paint.editors.find((e) => e.name === 'LampSheet');
      if (ed && ed.frame !== null) seen.add(ed.frame);
      return seen.size === 2 ? true : null;
    });
    console.log(`ok  pixel editor: painted ${sheet.file} (0,0) in a palette colour, undo/redo, Check uses it, Save wrote 1 file and touched no other; ${cliNote}; the preview plays frames 0 and 1`);

    // 8. New images and import on the Vault.
    await evaluate(WRITE_FIXTURE(VAULT));
    await delay(20);
    const addBefore = await evaluate(SNAPSHOT);
    await evaluate(`${PROJECT_DIR}.then((d) => window.bespokeStudio.openDirectory(d)).then(() => true)`);
    await evaluate('window.bespokeStudio.openArt().then(() => true)');
    const fillForm = (values) => evaluate(`(() => {
      const v = ${JSON.stringify(values)};
      for (const [k, val] of Object.entries(v)) {
        const el = document.querySelector('[data-window="new-image"] input[name="' + k + '"]');
        el.value = val;
        el.dispatchEvent(new Event('input', { bubbles: true }));
      }
      return true;
    })()`);
    await evaluate('window.bespokeStudio.newImageForm()');
    await fillForm({ name: 'Torch', width: '12', height: '12', fw: '6', fh: '12' });
    const fileField = await evaluate(`document.querySelector('[data-window="new-image"] input[name="file"]').value`);
    if (fileField !== 'art/torch.png') throw new Error(`new image file field: ${fileField}`);
    await click('[data-window="new-image"] [data-gadget="form-add"]');
    await waitFor('Paint Torch', async () => ((await state()).windows.includes('paint:Torch') ? true : null));
    // An import in colours the Vault's palette does not hold: refused, nothing added.
    await evaluate(`window.bespokeStudio.importForm('lamp.png', Array.from(atob(${JSON.stringify(LAMP_PNG)}), (c) => c.charCodeAt(0)))`);
    await click('[data-window="new-image"] [data-gadget="form-add"]');
    await requester('Script check');
    s = await state();
    if (!/palette/.test(s.result.message) || s.project.files.some((f) => f.path === 'art/lamp.png')) throw new Error(`off-palette import: ${JSON.stringify(s.result)}`);
    await key('Escape', 'Escape', 27);
    await noRequester();
    // A transparent sheet imports, under a name taken from its file.
    const CLEAR_PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAC0lEQVR4nGNgQAcAABIAAXfx+gAAAAAASUVORK5CYII=';
    await evaluate(`window.bespokeStudio.importForm('crest.png', Array.from(atob(${JSON.stringify(CLEAR_PNG)}), (c) => c.charCodeAt(0)))`);
    await click('[data-window="new-image"] [data-gadget="form-add"]');
    await waitFor('Crest listed', async () => ((await state()).paint.images.some((i) => i.name === 'Crest') ? true : null));
    s = await state();
    const added = s.project.files.filter((f) => f.isNew).map((f) => f.path).sort();
    if (JSON.stringify(added) !== JSON.stringify(['art/crest.png', 'art/torch.png'])) throw new Error(`new files: ${added.join(', ')}`);
    await evaluate('window.__save = window.bespokeStudio.save(); true');
    await requester('Save');
    await click('.req-buttons .gad');
    await noRequester();
    const addSaved = await evaluate('window.__save');
    if (addSaved.written !== 3 || addSaved.failed.length) throw new Error(`add save: ${JSON.stringify(addSaved)}`);
    const addAfter = await evaluate(SNAPSHOT);
    const text = (f) => Buffer.from(f.b64, 'base64').toString('latin1');
    const beforeLines = text(addBefore['main.bespoke']).split('\n');
    const afterLines = text(addAfter['main.bespoke']).split('\n');
    const last = beforeLines.findIndex((l) => l.startsWith('image ReliquaryArt'));
    const expectLines = [...beforeLines.slice(0, last + 1), 'image Torch from "art/torch.png" frames 6x12', 'image Crest from "art/crest.png"', ...beforeLines.slice(last + 1)];
    if (afterLines.join('\n') !== expectLines.join('\n')) throw new Error('main.bespoke is not the old script plus the two image lines after the last image');
    if (addAfter['art/crest.png'].b64 !== CLEAR_PNG) throw new Error('the import was not copied byte for byte');
    if (!addAfter['art/torch.png']) throw new Error('art/torch.png was not created');
    for (const [p, before] of Object.entries(addBefore)) {
      if (p === 'main.bespoke') continue;
      const after = addAfter[p];
      if (!after || after.b64 !== before.b64 || after.modified !== before.modified) throw new Error(`adding images touched ${p}`);
    }
    if (Object.keys(addAfter).length !== Object.keys(addBefore).length + 2) throw new Error('adding images made other files');
    let addCli = 'command line not built, not run';
    if (fs.existsSync(path.join(root, 'zig-out', 'bin', 'bespoke'))) {
      const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bespoke-studio-add-'));
      try {
        for (const [p, f] of Object.entries(addAfter)) {
          fs.mkdirSync(path.dirname(path.join(dir, p)), { recursive: true });
          fs.writeFileSync(path.join(dir, p), Buffer.from(f.b64, 'base64'));
        }
        const run = spawnSync(path.join(root, 'zig-out', 'bin', 'bespoke'), ['check', path.join(dir, 'main.bespoke')], { encoding: 'utf8' });
        if (run.status !== 0) throw new Error(`bespoke check after adding images: ${run.stdout}${run.stderr}`);
        addCli = 'bespoke check passes';
      } finally {
        fs.rmSync(dir, { recursive: true, force: true });
      }
    }
    console.log(`ok  new image and import: two lines after the last image, two PNGs created, an off-palette import refused, nothing else touched; ${addCli}`);

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
    await evaluate('window.bespokeStudio.play(); true');
    await requester('Play');
    await key('Escape', 'Escape', 27);
    await noRequester();
    await cdp.send('Page.removeScriptToEvaluateOnNewDocument', { identifier: hook.identifier });
    console.log('ok  compiler fault: fault panel, then a working workspace that opens a project and explains Check and Play');

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
