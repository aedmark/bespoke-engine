// P37-02: open a generated standalone proof page from file:// in real headless Chrome,
// start its AudioWorklet through a click, and advance its engine state through the solve key.
// This uses Chrome's DevTools protocol directly so the repository needs no browser package.
//
// Run after `zig build wasm-proofs && python3 tools/build_site.py`:
//   CHROME=/path/to/chrome node tools/browser_smoke.js
// P40-02: --starter path/to/index.html serves and checks a packed starter game instead.
// P42-03: --showcase-layout checks the showcase at a 375 CSS-pixel viewport.
// P42-06: --touch-targets fails when any control on any showcase page measures under 44 px tall.
'use strict';

const fs = require('fs');
const http = require('http');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const { pathToFileURL } = require('url');

const root = path.resolve(__dirname, '..');
const chrome = process.env.CHROME || 'google-chrome';
// A loaded CI runner can take well over 15 seconds to create DevToolsActivePort. Keep the
// startup budget separate from the short waits for page state once Chrome is attached.
const CHROME_START_TIMEOUT_MS = 60000;
// The floor a thumb needs on a phone (P42-06). Every link, button, field, and disclosure on the
// showcase pages is measured against it, so the size is enforced rather than remembered.
const TOUCH_TARGET_MIN = 44;
// Every gallery card with a page gets a Play link. Counted from the gallery source rather than
// written as a number, so a new proof page (P45-06 made fourteen) does not break the layout check.
const PROOF_PAGE_COUNT = JSON.parse(fs.readFileSync(path.join(root, 'tools', 'site_gallery.json'), 'utf8'))
  .proofs.filter((proof) => proof.page).length;
const measureTargets = `(() => {
  const nodes = [...document.querySelectorAll('a, button, input, select, textarea, summary, [role="button"]')];
  const short = [];
  for (const node of nodes) {
    const box = node.getBoundingClientRect();
    if (!box.width && !box.height) continue;
    if (box.height < ${TOUCH_TARGET_MIN}) {
      short.push({ tag: node.tagName.toLowerCase(),
        label: (node.textContent || node.id || node.getAttribute('aria-label') || '').trim().slice(0, 30),
        height: Math.round(box.height * 10) / 10 });
    }
  }
  const root = document.documentElement;
  const overflow = root.scrollWidth > root.clientWidth
    ? { scrollWidth: root.scrollWidth, clientWidth: root.clientWidth } : null;
  return { measured: nodes.length, short, overflow };
})()`;
// Each page reports its own readiness: the proof pages once their embedded engine is up, the
// homepage once the Harbour frame beside it has loaded, and the Harbour page once it parses.
// Measuring earlier would read a half-built layout, and a fixed delay would be a guess.
const pageReady = `(async () => {
  if (document.readyState !== 'complete') return false;
  if (document.fonts && document.fonts.status !== 'loaded') await document.fonts.ready;
  if (document.querySelector('#game-canvas')) {
    return Boolean(window.bespokePageState && window.bespokePageState().ready);
  }
  const frame = document.querySelector('#harbour-demo');
  if (frame) {
    const inside = frame.contentDocument;
    return Boolean(inside && inside.readyState === 'complete' && inside.querySelector('#start'));
  }
  // A plain page has no deck to wait on: the document and its fonts are all there is to load.
  return true;
})()`;
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

async function smoke(pageUrl, starter, layout = false, touchTargets = false, touchPageNames = []) {
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
    }, CHROME_START_TIMEOUT_MS);
    const target = await waitFor('game page target', async () => {
      const response = await fetch(`http://127.0.0.1:${port}/json/list`);
      const targets = await response.json();
      return targets.find((item) => item.type === 'page' && item.url === pageUrl);
    }, CHROME_START_TIMEOUT_MS);
    const cdp = new Cdp(target.webSocketDebuggerUrl);
    await cdp.open();
    await cdp.send('Runtime.enable');
    await cdp.send('Page.enable');

    const evaluate = async (expression) => {
      const result = await cdp.send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
      if (result.exceptionDetails) throw new Error(result.exceptionDetails.text);
      return result.result.value;
    };
    if (touchTargets) {
      await cdp.send('Emulation.setDeviceMetricsOverride', {
        width: 375, height: 820, deviceScaleFactor: 1, mobile: false,
      });
      const origin = new URL(pageUrl).origin;
      const problems = [];
      for (const name of touchPageNames) {
        await cdp.send('Page.navigate', { url: `${origin}/site/${name}` });
        await waitFor(`${name} to be ready`, async () => (await evaluate(pageReady)) === true, 30000);
        const result = await evaluate(measureTargets);
        if (result.overflow) {
          problems.push(`${name}: the page scrolls sideways (${result.overflow.scrollWidth} > ${result.overflow.clientWidth})`);
        }
        for (const item of result.short) {
          problems.push(`${name}: <${item.tag}> "${item.label}" is ${item.height} px tall`);
        }
        if (!result.short.length && !result.overflow) {
          console.log(`ok  ${name}: ${result.measured} controls at least ${TOUCH_TARGET_MIN} px tall at 375 px`);
        }
      }
      if (problems.length) {
        throw new Error(`controls under ${TOUCH_TARGET_MIN} px at 375 px:\n  ${problems.join('\n  ')}`);
      }
      console.log(`ok  touch targets: ${touchPageNames.length} showcase pages, every control at least ${TOUCH_TARGET_MIN} px tall at 375 px`);
      cdp.close();
      return;
    }
    if (layout) {
      await cdp.send('Emulation.setDeviceMetricsOverride', {
        width: 375, height: 820, deviceScaleFactor: 1, mobile: false,
      });
      const harbour = "document.querySelector('#harbour-demo').contentDocument";
      await waitFor('Harbour Start button', () => evaluate(
        `Boolean(${harbour}?.querySelector('#start:not(:disabled)'))`
      ));
      const sizes = await evaluate(`(() => {
        const root = document.documentElement;
        const frame = document.querySelector('#harbour-demo');
        const inside = frame.contentDocument.documentElement;
        return { viewport: innerWidth, visible: root.clientWidth, content: root.scrollWidth,
          stageRight: frame.getBoundingClientRect().right, gameVisible: inside.clientWidth, gameContent: inside.scrollWidth };
      })()`);
      if (sizes.viewport !== 375 || sizes.content > sizes.visible || sizes.stageRight > sizes.visible ||
          sizes.gameContent > sizes.gameVisible) {
        throw new Error(`375 px showcase overflows: ${JSON.stringify(sizes)}`);
      }
      await delay(1100);
      if (!await evaluate(`(() => {
        const game = ${harbour};
        return document.querySelectorAll('iframe').length === 1 && !document.querySelector('#sim-canvas') &&
          game.querySelector('#command').disabled && game.querySelectorAll('#log p').length === 1 &&
          document.activeElement !== document.querySelector('#harbour-demo');
      })()`)) throw new Error('the only live demo must be idle and leave homepage focus alone before Start');
      await evaluate(`${harbour}.querySelector('#start').click()`);
      if (!await evaluate(`${harbour}.activeElement.id === 'command'`)) throw new Error('Start must focus the parser');
      const command = text => evaluate(`(() => {
        const game = ${harbour};
        game.querySelector('#command').value = ${JSON.stringify(text)};
        game.querySelector('#form').requestSubmit();
      })()`);
      await command('read tide board');
      await command('go forward');
      await waitFor('parser-only arrival at the Watch office', () => evaluate(`(() => {
        const game = ${harbour};
        const log = game.querySelector('#log').textContent;
        return !game.querySelector('#map').open && log.includes('Ebb tide.') && log.includes('Watch office.');
      })()`));
      const route = await evaluate(`(() => {
        const links = [...document.querySelectorAll('#scenarios .gallery-actions a')];
        if (links.filter(a => a.textContent === 'Play this proof').length !== ${PROOF_PAGE_COUNT}) throw Error('missing standalone proof links');
        return links.find(a => a.getAttribute('href') === 'observatory.html').href;
      })()`);
      console.log('ok  375 px showcase fits; The Harbour starts on request and plays with the map closed');
      await cdp.send('Page.navigate', { url: route });
      await waitFor('Observatory deck on its own page', () => evaluate(
        "document.querySelector('#game-canvas')?.dataset.deck === '12' && Boolean(window.bespokePageState && window.bespokePageState().ready)"
      ));
      console.log('ok  gallery opens each proof on its own page, including the Observatory deck');
      cdp.close();
      return;
    }
    if (starter) {
      const hasIntro = await evaluate("document.querySelector('#start-watch') !== null");
      if (hasIntro) {
        await waitFor('Start watch button', () =>
          evaluate("!document.querySelector('#start-watch').disabled")
        );
        const opening = await evaluate("document.querySelector('#transcript #watch-intro').textContent.trim()");
        if (!opening) throw new Error('the opening narration is missing from the transcript');
        // Wait longer than one simulation interval. The stage must still have no tick.
        await delay(1250);
        if (!await evaluate("!document.querySelector('#watch-stage').hidden && document.querySelector('#command').matches(':disabled') && document.querySelector('#stage').dataset.tick === undefined")) {
          throw new Error('the gameplay window should be visible but idle before Start');
        }
        if (!await evaluate("document.activeElement === document.querySelector('#start-watch')")) {
          throw new Error('the intro did not focus the Start button');
        }
        await cdp.send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, text: '\r', unmodifiedText: '\r' });
        await cdp.send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13 });
        const initial = await waitFor('watch to start from keyboard', () =>
          evaluate("document.querySelector('#start-prompt').hidden && !document.querySelector('#command').matches(':disabled') && { tick: Number(document.querySelector('#stage').dataset.tick) }")
        );
        await waitFor('watch clock to advance', () =>
          evaluate("Number(document.querySelector('#stage').dataset.tick) > " + initial.tick)
        );
        if (!await evaluate("document.querySelector('#transcript #watch-intro').textContent.trim() === " + JSON.stringify(opening))) {
          throw new Error('Start removed the opening narration');
        }
        console.log('ok  opening prose stays in the transcript; clock waits for Start');
      }
      if (await evaluate("document.querySelector('#command-form') !== null")) {
        if (!await evaluate("document.querySelector('#watch-map').hidden && document.activeElement.id === 'command'")) {
          throw new Error('the command field should be focused and the map hidden at start');
        }
        const typeCommand = async (line) => {
          await evaluate("document.querySelector('#command').value = " + JSON.stringify(line));
          await cdp.send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, text: '\r', unmodifiedText: '\r' });
          await cdp.send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13 });
        };
        const storyCount = (needle, count) => evaluate(
          "[...document.querySelectorAll('#transcript .story')].filter(p => p.textContent.includes(" +
          JSON.stringify(needle) + ")).length === " + count
        );
        await typeCommand('Go to watch room');
        await waitFor('first watch room arrival', () => storyCount('You enter the watch room.', 1));
        await typeCommand('go gallery');
        await waitFor('gallery arrival', () => storyCount('You reach the gallery.', 1));
        await typeCommand('go watch room');
        await waitFor('second watch room arrival', () => storyCount('You enter the watch room.', 2));
        await typeCommand('xyzzy');
        await waitFor('parser failure in the transcript', () => storyCount("I don't know the word", 1));
        if (!await evaluate("document.querySelector('#watch-map').hidden && document.querySelectorAll('#transcript .command').length === 4")) {
          throw new Error('typed movement should retain the transcript without opening the map');
        }
        await typeCommand('take oilcan');
        await waitFor('oilcan pickup', () => storyCount('You take the oilcan.', 1));
        await typeCommand('go bell landing');
        await waitFor('bell landing arrival', () => storyCount('You reach the bell landing.', 1));
        await typeCommand('ring bell');
        await waitFor('jammed bell', () => storyCount("the bell doesn't move.", 1));
        await typeCommand('oil bell');
        await waitFor('bell repair', () => storyCount('the pivot gives.', 1));
        await typeCommand('ring bell');
        await waitFor('Keeper closes the watch', () => storyCount('We all sleep soundly tonight.', 1));
        await evaluate("document.querySelector('#map-toggle').click()");
        console.log('ok  text-only bell repair, both go forms, and optional map');
      }
      // Read pixels back from the actual canvas. A fetched page or a successful
      // WebAssembly instantiation alone would miss a broken renderer bootstrap.
      const colours = await waitFor('starter game frame', async () => {
        const count = await evaluate(`(() => {
          const canvas = document.querySelector('#stage');
          if (!canvas) return 0;
          const pixels = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
          const colours = new Set();
          for (let i = 0; i < pixels.length; i += 4 * 101) {
            if (pixels[i + 3]) colours.add((pixels[i] << 16) | (pixels[i + 1] << 8) | pixels[i + 2]);
          }
          return colours.size;
        })()`);
        return count > 3 ? count : null;
      });
      console.log(`ok  packed starter page over HTTP: ${colours} canvas colours`);
      if (await evaluate("document.querySelector('#volume') !== null")) {
        await evaluate("document.querySelector('#sound').click()");
        await waitFor('starter audio graph', () =>
          evaluate("document.querySelector('#sound').textContent === 'Sound: on'")
        );
        console.log('ok  packed starter page: AudioWorklet and volume controls ready');
      }
      cdp.close();
      return;
    }
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

async function main() {
  const args = process.argv.slice(2);
  if (args.length === 0) {
    await smoke(pathToFileURL(path.join(root, 'site', 'pips.html')).href, false);
    return;
  }
  if (args.length === 1 && args[0] === '--showcase-layout') {
    const names = ['index.html', 'harbour.html', 'observatory.html'];
    const pages = new Map(names.map(name => [`/site/${name}`, fs.readFileSync(path.join(root, 'site', name))]));
    await servePages(pages, '/site/index.html', url => smoke(url, false, true));
    return;
  }
  if (args.length === 1 && args[0] === '--touch-targets') {
    const names = fs.readdirSync(path.join(root, 'site')).filter((name) => name.endsWith('.html')).sort();
    const pages = new Map(names.map(name => [`/site/${name}`, fs.readFileSync(path.join(root, 'site', name))]));
    await servePages(pages, '/site/index.html', url => smoke(url, false, false, true, names));
    return;
  }
  if (args.length !== 2 || args[0] !== '--starter') {
    throw new Error('usage: node tools/browser_smoke.js [--starter path/to/index.html | --showcase-layout | --touch-targets]');
  }

  const page = fs.readFileSync(args[1]);
  // Serve only the exact upload artifact, at a subdirectory path like a hosted game.
  await servePages(new Map([['/game/', page]]), '/game/', url => smoke(url, true));
}

async function servePages(pages, entry, run) {
  const server = http.createServer((req, res) => {
    const page = req.method === 'GET' && pages.get(new URL(req.url, 'http://localhost').pathname);
    if (!page) {
      res.writeHead(404).end();
      return;
    }
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }).end(page);
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  try {
    await run(`http://127.0.0.1:${server.address().port}${entry}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

main().catch((error) => {
  console.error(`FAIL browser smoke: ${error.message}`);
  if (stderr.trim()) console.error(stderr.trim());
  process.exit(1);
});
