// BeSpoke Studio, P47-01 (D-151, D-192): the workspace screen, a project window that opens a
// folder or files, checks a script with the engine's compiler, and shows its diagnostics in
// place; the play window (P47-06, D-195, play.js), which runs the built game in a module of its
// own; the pixel editor (P47-02, D-196, paint.js), which paints the PNG sheets a script names;
// the room editor (P47-03, D-200, room.js), which lays out a scene as its room block; and the
// cast editor (P47-05, D-202, cast.js), which adds names to scenes and sets display names,
// axes, starting values, and red lines; the dilemma editor (P47-13, D-203, dilemma.js); and
// the read-only dialogue map (P47-04, D-204, talk.js). An edited file's new bytes stay in the page until Save writes them. The Studio keeps no project state of its own (D-151 item 6): files are
// held as the bytes read from disk and nothing is written back unless an editor changed it.
//
// Failed modes fall back to a working screen (D-192 item 5): the workspace and its windows
// depend only on this page's script and the baked font table. The compiler module, a saved
// setting, a project file, and every handler can fail; each failure is shown, and the author is
// left at a workspace that still opens, checks, and saves what it can.
'use strict';

(function studio() {
  const SCALE_KEY = 'bespoke.studio.scale';
  const SCALES = [1, 2, 3];
  const DEFAULT_SCALE = 2;
  // What a project folder contributes: scripts and the images they name. Everything else in
  // the folder is never read and never written, so it stays byte-identical by construction.
  const KEEP = /\.(bespoke|png)$/i;
  const SKIP_DIRS = new Set(['zig-out', '.zig-cache', 'zig-cache', 'node_modules']);
  // The compiler expands at most 256 files (includes.MAX_FILES) and 16 MiB of source; a PNG may
  // be 16 MiB (png.MAX_FILE). The total keeps one page's memory bounded.
  const MAX_FILES = 256;
  const MAX_FILE_BYTES = 16 * 1024 * 1024;
  const MAX_TOTAL_BYTES = 64 * 1024 * 1024;
  const MAX_DEPTH = 8;

  const S = {
    ready: false,
    scale: DEFAULT_SCALE,
    storage: true,
    compiler: { state: 'loading', error: '' },
    project: null,
    result: null,
    faults: [],
  };

  const isMac = /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent || '');
  const root = document.getElementById('studio');
  const desk = createDesk(root, STUDIO_FONT);
  desk.keyName = (item) => `${isMac ? 'Cmd' : 'Ctrl'} ${item.key}`;

  // ------------------------------------------------------------ faults

  let faultShowing = null;
  function reportFault(lines) {
    S.faults.push(lines.join(' '));
    // One panel at a time; a burst of failures adds up behind it instead of stacking panels.
    if (faultShowing) return faultShowing;
    faultShowing = desk.fault([...lines, 'The workspace is still running. Click to go on.']).then(() => { faultShowing = null; });
    return faultShowing;
  }
  desk.onHandlerError = (err) => reportFault(['A Studio window stopped on an error:', errText(err)]);
  window.addEventListener('error', (e) => reportFault(['The Studio hit an error:', e.message || 'unknown error']));
  window.addEventListener('unhandledrejection', (e) => reportFault(['The Studio hit an error:', errText(e.reason)]));

  function errText(err) {
    if (!err) return 'unknown error';
    return String(err.message || err).slice(0, 200);
  }

  // ------------------------------------------------------------ settings

  function applyScale(n) {
    S.scale = n;
    document.documentElement.style.setProperty('--px', `${n}px`);
  }

  // A saved setting the page cannot use is reported and replaced by the default for this visit;
  // the saved value is only overwritten when the author picks a scale.
  function loadSettings() {
    let raw = null;
    try { raw = window.localStorage.getItem(SCALE_KEY); } catch { S.storage = false; }
    if (raw === null) { applyScale(DEFAULT_SCALE); return null; }
    const n = Number(raw);
    if (SCALES.includes(n)) { applyScale(n); return null; }
    applyScale(DEFAULT_SCALE);
    return raw;
  }

  function saveScale(n) {
    applyScale(n);
    try { window.localStorage.setItem(SCALE_KEY, String(n)); } catch { S.storage = false; }
    screen.setMenus(menus());
    for (const w of screen.windows) w.port.post({ kind: 'resize', w: w.rect.w, h: w.rect.h });
  }

  // ------------------------------------------------------------ the compiler

  let wasm = null;

  async function startCompiler() {
    S.compiler = { state: 'loading', error: '' };
    renderProject();
    try {
      if (typeof WebAssembly === 'undefined') throw new Error('this browser has no WebAssembly');
      if (!STUDIO_BUILD.wasm) throw new Error('this page was built without its compiler');
      const bytes = Uint8Array.from(atob(STUDIO_BUILD.wasm), (c) => c.charCodeAt(0));
      const { instance } = await WebAssembly.instantiate(bytes, {});
      wasm = instance.exports;
      S.compiler = { state: 'ready', error: '' };
    } catch (err) {
      stopCompiler(err, 'did not start');
      return false;
    }
    renderProject();
    return true;
  }

  // A trap inside the module (out of memory, a bug) ends that instance; the Studio keeps going
  // without it, says so, and offers Retry, which starts a fresh instance.
  function stopCompiler(err, how) {
    wasm = null;
    S.compiler = { state: 'unavailable', error: errText(err) };
    renderProject();
    reportFault([`The compiler ${how}: ${errText(err)}`, 'You can still open projects and save. Retry is in the Project window.']);
  }

  function withCompiler(fn) {
    if (!wasm) return null;
    try { return fn(wasm); } catch (err) { stopCompiler(err, 'stopped'); return null; }
  }

  const enc = new TextEncoder();
  function put(x, bytes) {
    const len = Math.max(1, bytes.length);
    const ptr = x.studio_alloc(len);
    if (!ptr) throw new Error('the compiler ran out of memory');
    new Uint8Array(x.memory.buffer, ptr, bytes.length).set(bytes);
    return { ptr, len, used: bytes.length };
  }

  function loadIntoCompiler() {
    return withCompiler((x) => {
      x.studio_reset();
      for (const f of S.project.files) {
        const p = put(x, enc.encode(f.path));
        const d = put(x, f.bytes);
        const ok = x.studio_add_file(p.ptr, p.used, d.ptr, d.used);
        x.studio_free(p.ptr, p.len);
        x.studio_free(d.ptr, d.len);
        if (!ok) throw new Error(`the compiler refused ${f.path}`);
      }
      return true;
    });
  }

  // Builds `main` into a package for the play window (D-195). Returns { result, pkg }: the
  // check's JSON either way, and the package bytes, copied out of the module, when it built.
  function runBuild(main) {
    return withCompiler((x) => {
      const p = put(x, enc.encode(main));
      const status = x.studio_build(p.ptr, p.used);
      x.studio_free(p.ptr, p.len);
      if (status < 0) throw new Error('the compiler ran out of memory');
      const bytes = new Uint8Array(x.memory.buffer, x.studio_result_ptr(), x.studio_result_len());
      const result = JSON.parse(new TextDecoder().decode(bytes));
      const pkg = status === 1 ? new Uint8Array(x.memory.buffer, x.studio_package_ptr(), x.studio_package_len()).slice() : null;
      return { result, pkg };
    });
  }

  function runCheck(main) {
    return withCompiler((x) => {
      const p = put(x, enc.encode(main));
      const status = x.studio_check(p.ptr, p.used);
      x.studio_free(p.ptr, p.len);
      if (status < 0) throw new Error('the compiler ran out of memory');
      const bytes = new Uint8Array(x.memory.buffer, x.studio_result_ptr(), x.studio_result_len());
      return JSON.parse(new TextDecoder().decode(bytes));
    });
  }

  // ------------------------------------------------------------ opening projects

  function chooseMain(files) {
    const scripts = files.map((f) => f.path).filter((p) => /\.bespoke$/i.test(p)).sort();
    for (const want of ['scripts/main.bespoke', 'main.bespoke']) if (scripts.includes(want)) return want;
    const mains = scripts.filter((p) => p.endsWith('/main.bespoke')).sort((a, b) => a.split('/').length - b.split('/').length);
    return mains[0] || scripts[0] || null;
  }

  function addFile(acc, path, bytes, extra) {
    if (acc.files.length >= MAX_FILES) { acc.skipped.push({ path, why: `over the ${MAX_FILES}-file limit` }); return; }
    if (bytes.length > MAX_FILE_BYTES) { acc.skipped.push({ path, why: 'larger than 16 MiB' }); return; }
    if (acc.total + bytes.length > MAX_TOTAL_BYTES) { acc.skipped.push({ path, why: 'past the 64 MiB project limit' }); return; }
    if (acc.files.some((f) => f.path === path)) { acc.skipped.push({ path, why: 'a second file with this name' }); return; }
    acc.total += bytes.length;
    // `original` is what was read; Save compares the disk with it, and an edit is dirty while
    // its bytes differ from it.
    acc.files.push({ path, bytes, original: bytes, dirty: false, ...extra });
  }

  async function readHandleTree(dir) {
    const acc = { files: [], skipped: [], total: 0 };
    async function walk(d, prefix, depth) {
      const entries = [];
      for await (const entry of d.values()) entries.push(entry);
      entries.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
      for (const h of entries) {
        if (h.name.startsWith('.')) continue;
        const path = prefix ? `${prefix}/${h.name}` : h.name;
        if (h.kind === 'directory') {
          if (SKIP_DIRS.has(h.name)) continue;
          if (depth >= MAX_DEPTH) { acc.skipped.push({ path, why: 'folders nested too deep' }); continue; }
          await walk(h, path, depth + 1);
        } else if (KEEP.test(h.name)) {
          try {
            const file = await h.getFile();
            if (file.size > MAX_FILE_BYTES) { acc.skipped.push({ path, why: 'larger than 16 MiB' }); continue; }
            addFile(acc, path, new Uint8Array(await file.arrayBuffer()), { handle: h, lastModified: file.lastModified });
          } catch (err) {
            acc.skipped.push({ path, why: errText(err) });
          }
        }
      }
    }
    await walk(dir, '', 0);
    return acc;
  }

  async function openDirectory(handle) {
    let acc;
    try {
      acc = await readHandleTree(handle);
    } catch (err) {
      await desk.requester(projectWindow(), { title: 'Open folder', tone: 'fault', lines: [`The folder "${handle.name}" could not be read.`, errText(err)] });
      return false;
    }
    return finishOpen({ name: handle.name, handle, writable: true }, acc);
  }

  async function openFileHandles(handles) {
    const acc = { files: [], skipped: [], total: 0 };
    for (const h of handles) {
      try {
        const file = await h.getFile();
        addFile(acc, h.name, new Uint8Array(await file.arrayBuffer()), { handle: h, lastModified: file.lastModified });
      } catch (err) {
        acc.skipped.push({ path: h.name, why: errText(err) });
      }
    }
    return finishOpen({ name: 'Opened files', handle: null, writable: true }, acc);
  }

  // The fallback for browsers without the file system access API: a file input. What it reads
  // cannot be written back, so the project is marked read-only and Save says so.
  async function openFileList(list, folder) {
    const acc = { files: [], skipped: [], total: 0 };
    const all = [...list].sort((a, b) => ((a.webkitRelativePath || a.name) < (b.webkitRelativePath || b.name) ? -1 : 1));
    let name = 'Opened files';
    for (const file of all) {
      let path = file.name;
      if (folder && file.webkitRelativePath) {
        const parts = file.webkitRelativePath.split('/');
        name = parts[0];
        path = parts.slice(1).join('/');
        if (parts.slice(1, -1).some((p) => p.startsWith('.') || SKIP_DIRS.has(p))) continue;
      }
      if (!KEEP.test(path) || path.split('/').pop().startsWith('.')) continue;
      try {
        addFile(acc, path, new Uint8Array(await file.arrayBuffer()), { handle: null, lastModified: file.lastModified });
      } catch (err) {
        acc.skipped.push({ path, why: errText(err) });
      }
    }
    return finishOpen({ name, handle: null, writable: false }, acc);
  }

  // Another main script: the art and room editors belonged to the old one, so they close, and
  // open listings are made again for the new one after its check.
  async function chooseScript(main) {
    if (S.project.main === main) return;
    S.project.main = main;
    S.result = null;
    painter.reset();
    roomer.reset();
    caster.reset();
    dilemmer.reset();
    talker.reset();
    renderProject();
    await check();
    await painter.relist();
    await roomer.relist();
    await caster.relist();
    await dilemmer.relist();
    await talker.relist();
  }

  async function finishOpen(meta, acc) {
    S.project = { ...meta, files: acc.files, skipped: acc.skipped, main: chooseMain(acc.files) };
    S.result = null;
    painter.reset();
    roomer.reset();
    caster.reset();
    dilemmer.reset();
    talker.reset();
    for (const w of [...screen.windows]) if (w.id.startsWith('script:') || w.id === 'diagnostics') w.close();
    renderProject();
    if (acc.skipped.length) {
      await desk.requester(projectWindow(), {
        title: 'Open',
        lines: [`${acc.skipped.length} file(s) were not opened:`, ...acc.skipped.slice(0, 6).map((s) => `${s.path}: ${s.why}`)],
      });
    }
    if (!acc.files.length) {
      await desk.requester(projectWindow(), { title: 'Open', lines: [`"${meta.name}" holds no .bespoke scripts or .png images.`] });
      return false;
    }
    if (loadIntoCompiler() === null) return true;
    await check();
    await painter.relist();
    await roomer.relist();
    await caster.relist();
    await dilemmer.relist();
    await talker.relist();
    return true;
  }

  function dirtyFiles() {
    return S.project ? S.project.files.filter((f) => f.dirty) : [];
  }

  // Opening another project drops unsaved edits; the author says so first.
  async function confirmDiscard() {
    const dirty = dirtyFiles();
    if (!dirty.length) return true;
    const pick = await desk.requester(projectWindow(), {
      title: 'Open', lines: [`${dirty.length} edited file(s) are not saved:`, ...dirty.slice(0, 4).map((f) => f.path), 'Open another project and lose them?'],
      buttons: [{ id: 'discard', label: 'Lose edits' }, { id: 'cancel', label: 'Cancel' }],
    });
    return pick === 'discard';
  }

  async function openFolder() {
    if (!await confirmDiscard()) return false;
    if (window.showDirectoryPicker) {
      let handle;
      try { handle = await window.showDirectoryPicker({ id: 'bespoke-project', mode: 'read' }); } catch (err) {
        if (err && err.name === 'AbortError') return false;
        throw err;
      }
      return openDirectory(handle);
    }
    return pickInput(true);
  }

  async function openFiles() {
    if (!await confirmDiscard()) return false;
    if (window.showOpenFilePicker) {
      let handles;
      try {
        handles = await window.showOpenFilePicker({
          id: 'bespoke-files', multiple: true,
          types: [{ description: 'BeSpoke scripts and images', accept: { 'text/plain': ['.bespoke'], 'image/png': ['.png'] } }],
        });
      } catch (err) {
        if (err && err.name === 'AbortError') return false;
        throw err;
      }
      return openFileHandles(handles);
    }
    return pickInput(false);
  }

  function pickInput(folder) {
    return new Promise((resolve) => {
      const input = document.createElement('input');
      input.type = 'file';
      input.multiple = true;
      if (folder) input.webkitdirectory = true; else input.accept = '.bespoke,.png';
      input.hidden = true;
      input.addEventListener('change', async () => { input.remove(); resolve(await openFileList(input.files, folder)); });
      input.addEventListener('cancel', () => { input.remove(); resolve(false); });
      document.body.appendChild(input);
      input.click();
    });
  }

  // One PNG to import (P47-10): the browser's picker, or a file input where it has none.
  async function pickPng() {
    let file = null;
    if (window.showOpenFilePicker) {
      try {
        const [h] = await window.showOpenFilePicker({ id: 'bespoke-import', types: [{ description: 'PNG images', accept: { 'image/png': ['.png'] } }] });
        file = await h.getFile();
      } catch (err) {
        if (err && err.name === 'AbortError') return null;
        throw err;
      }
    } else {
      file = await new Promise((resolve) => {
        const input = document.createElement('input');
        input.type = 'file';
        input.accept = '.png';
        input.hidden = true;
        input.addEventListener('change', () => { input.remove(); resolve(input.files[0] || null); });
        input.addEventListener('cancel', () => { input.remove(); resolve(null); });
        document.body.appendChild(input);
        input.click();
      });
    }
    if (!file) return null;
    if (file.size > MAX_FILE_BYTES) throw new Error(`${file.name} is larger than 16 MiB`);
    return { name: file.name, bytes: new Uint8Array(await file.arrayBuffer()) };
  }

  // ------------------------------------------------------------ check

  // What Check and Play both need before they can run: a project, a script, and a compiler.
  // Returns true when ready; otherwise it has told the author why, in `title`'s requester.
  async function readyToBuild(title, again) {
    const win = projectWindow();
    if (!S.project) { await desk.requester(win, { title, lines: ['Open a project first.'] }); return false; }
    if (!S.project.main) { await desk.requester(win, { title, lines: ['This project has no .bespoke script.'] }); return false; }
    if (S.compiler.state !== 'ready') {
      const pick = await desk.requester(win, {
        title, tone: 'fault',
        lines: ["The compiler isn't running, so scripts can't be checked or built.", S.compiler.error],
        buttons: [{ id: 'retry', label: 'Retry' }, { id: 'ok', label: 'OK' }],
      });
      if (pick === 'retry' && await startCompiler() && loadIntoCompiler() !== null) await again();
      return false;
    }
    return true;
  }

  async function check() {
    if (!await readyToBuild('Check', check)) return null;
    document.body.classList.add('busy');
    const r = runCheck(S.project.main);
    document.body.classList.remove('busy');
    if (!r) return null;
    await showResult(r);
    return r;
  }

  // Builds the project and runs it in the play window. A script that does not compile shows
  // the same diagnostic Check does, and the game keeps whatever it was running.
  async function play() {
    if (!await readyToBuild('Play', play)) return null;
    document.body.classList.add('busy');
    const built = runBuild(S.project.main);
    document.body.classList.remove('busy');
    if (!built) return null;
    await showResult(built.result);
    if (!built.pkg) return null;
    return player.run(built.pkg, S.project.main);
  }

  // ------------------------------------------------------------ export

  // The game's name for its page, in the form `bespoke init` and the packer take: a lower-case
  // letter, then up to 31 letters, digits, or underscores. From the folder, else the script.
  function gameName() {
    return nameFor(S.project.handle ? S.project.name : S.project.main.split('/').pop().replace(/\.bespoke$/i, ''));
  }

  function nameFor(from) {
    const n = from.toLowerCase().replace(/[^a-z0-9_]+/g, '_').replace(/^[^a-z]+/, '').slice(0, 32).replace(/_+$/, '');
    return n || 'game';
  }

  function base64(bytes) {
    let bin = '';
    for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    return btoa(bin);
  }

  // As Python's html.escape, which the packer uses for the license.
  function escapeHtml(text) {
    return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#x27;');
  }

  // One page from init's shell (D-207): `{{name}}` filled as init fills it, the loader swapped
  // as tools/pack_game_page.py swaps it, and its license template added the same way. The new
  // loader instantiates the inlined play module, hands it the package, and resolves the
  // `{ instance }` the shell expects; for the text shell its `wasm_init` names the play
  // module's text deck, which no number key reaches.
  function pageFor(kind, name, pkg) {
    const shell = STUDIO_BUILD.shells[kind].split('{{name}}').join(name);
    const loader = STUDIO_BUILD.shellLoader.split('{{name}}').join(name);
    const at = shell.indexOf(loader);
    if (at < 0 || shell.indexOf(loader, at + 1) >= 0) throw new Error(`the ${kind} shell does not hold one loader`);
    const deck = kind === 'text' ? 1 : 0;
    const bytes = (b) => `Uint8Array.from(atob('${b}'), c => c.charCodeAt(0))`;
    const swapped = `WebAssembly.instantiate(${bytes(STUDIO_BUILD.play)}, {}).then(({ instance }) => { `
      + `const e = instance.exports; const pkg = ${bytes(base64(pkg))}; `
      + 'const p = e.play_alloc(Math.max(1, pkg.length)); if (!p) throw new Error(\'the game does not fit in memory\'); '
      + 'new Uint8Array(e.memory.buffer, p, pkg.length).set(pkg); '
      + `return { instance: { exports: Object.assign({}, e, { wasm_init: (d, a, b) => e.wasm_init(${deck}, a, b) }) } }; })`;
    const page = shell.slice(0, at) + swapped + shell.slice(at + loader.length);
    const close = page.lastIndexOf('</body>');
    if (close < 0) throw new Error(`the ${kind} shell has no closing body tag`);
    return `${page.slice(0, close)}<template id="bespoke-license"><pre>${escapeHtml(STUDIO_BUILD.license)}</pre></template>\n${page.slice(close)}`;
  }

  // Builds the project and downloads it as one page, stage or text (D-207). Nothing is
  // written into the project. `opts.kind` skips the question, and `opts.download: false`
  // returns the page without saving it, for tests.
  async function exportPage(opts = {}) {
    if (!await readyToBuild('Export', () => exportPage(opts))) return null;
    let kind = opts.kind;
    if (!kind) {
      kind = await desk.requester(projectWindow(), {
        title: 'Export page',
        lines: ['One HTML file that plays the game.', 'Stage: the game drawn, played by pointer.', 'Text: typed commands, with the picture above.'],
        buttons: [{ id: 'stage', label: 'Stage' }, { id: 'text', label: 'Text' }, { id: 'cancel', label: 'Cancel' }],
      });
      if (kind !== 'stage' && kind !== 'text') return null;
    }
    if (!STUDIO_BUILD.shells || !STUDIO_BUILD.shells[kind]) throw new Error(`this page was built without the ${kind} shell`);
    document.body.classList.add('busy');
    const built = runBuild(S.project.main);
    document.body.classList.remove('busy');
    if (!built) return null;
    await showResult(built.result);
    if (!built.pkg) return null;
    const name = gameName();
    const page = pageFor(kind, name, built.pkg);
    if (opts.download !== false) {
      const a = document.createElement('a');
      a.href = URL.createObjectURL(new Blob([page], { type: 'text/html' }));
      a.download = `${name}.html`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(a.href), 10000);
      await desk.requester(projectWindow(), { title: 'Export page', lines: [`${name}.html is downloading (${Math.ceil(page.length / 1024)} KB).`, 'It opens from disk in a browser; nothing in the project changed.'] });
    }
    return { name, kind, size: page.length, page: opts.download === false ? page : undefined };
  }

  async function showResult(r) {
    const win = projectWindow();
    S.result = r;
    renderProject();
    renderDiagnostics(!r.valid || r.warnings.length > 0);
    if (!r.valid) {
      const where = r.line ? `${r.file}, line ${r.line}, column ${r.column}` : r.file;
      const lines = [where, r.message];
      if (r.suggestion) lines.push(`Did you mean "${r.suggestion}"?`);
      const found = r.line && findFile(r.file);
      const pick = await desk.requester(win, {
        title: 'Script check', tone: 'fault', lines,
        buttons: found ? [{ id: 'show', label: 'Show line' }, { id: 'ok', label: 'OK' }] : [{ id: 'ok', label: 'OK' }],
      });
      if (pick === 'show') openScript(r.file, r.line, r.column);
    }
  }

  function findFile(path) {
    return S.project && S.project.files.find((f) => f.path === path);
  }

  // ------------------------------------------------------------ save

  // Writes only files an editor changed (D-196 item 5). First every opened file is compared
  // with the disk: if another program changed one since it was opened, nothing is written and
  // the author decides. Write permission is asked for only when an edited file needs it. A
  // folder opened read-only (a browser without the file system access API) offers each edited
  // file as a download instead.
  async function save() {
    const win = projectWindow();
    const p = S.project;
    const none = { written: 0, changed: [], downloaded: 0, failed: [] };
    if (!p) { await desk.requester(win, { title: 'Save', lines: ['No project is open.'] }); return none; }
    const dirty = dirtyFiles();
    const changed = [];
    if (p.writable) {
      for (const f of p.files) {
        if (f.isNew) {
          // A file the Studio will create must still not exist on disk (D-197 item 2).
          if (p.handle && await diskHas(p.handle, f.path)) changed.push(`${f.path} (now exists on disk)`);
          continue;
        }
        if (!f.handle) continue;
        try {
          const disk = new Uint8Array(await (await f.handle.getFile()).arrayBuffer());
          if (!sameBytes(disk, f.original)) changed.push(f.path);
        } catch (err) {
          changed.push(`${f.path} (${errText(err)})`);
        }
      }
    }
    if (changed.length) {
      const pick = await desk.requester(win, {
        title: 'Save', lines: [`${changed.length} file(s) changed on disk since you opened them:`, ...changed.slice(0, 6), 'Nothing was written.'],
        buttons: [{ id: 'reload', label: 'Reload' }, { id: 'leave', label: 'Leave' }],
      });
      if (pick === 'reload' && p.handle && await confirmDiscard()) await openDirectory(p.handle);
      return { ...none, changed };
    }
    if (!dirty.length) {
      const lines = [`Nothing to save: ${p.files.length} file(s) are unchanged.`];
      if (!p.writable) lines.push('This browser opened the folder read-only, so the Studio could not write to it anyway.');
      await desk.requester(win, { title: 'Save', lines });
      return none;
    }
    const written = [];
    const failed = [];
    let downloaded = 0;
    // New files first, so a script is never written naming a PNG that is not there yet.
    dirty.sort((a, b) => Number(Boolean(b.isNew)) - Number(Boolean(a.isNew)));
    for (const f of dirty) {
      if (f.isNew && p.writable && p.handle) {
        try {
          if (p.handle.queryPermission && await p.handle.queryPermission({ mode: 'readwrite' }) !== 'granted') {
            if (await p.handle.requestPermission({ mode: 'readwrite' }) !== 'granted') throw new Error('the browser did not allow writing');
          }
          const parts = f.path.split('/');
          let d = p.handle;
          for (const part of parts.slice(0, -1)) d = await d.getDirectoryHandle(part, { create: true });
          const fh = await d.getFileHandle(parts[parts.length - 1], { create: true });
          const out = await fh.createWritable();
          await out.write(f.bytes);
          await out.close();
          f.handle = fh;
          f.original = f.bytes;
          f.isNew = false;
          f.dirty = false;
          f.lastModified = (await fh.getFile()).lastModified;
          written.push(f.path);
        } catch (err) {
          failed.push(`${f.path} (${errText(err)})`);
          // A script naming a file that was not created is not written either.
          break;
        }
        continue;
      }
      if (p.writable && f.handle) {
        try {
          if (f.handle.queryPermission && await f.handle.queryPermission({ mode: 'readwrite' }) !== 'granted') {
            if (await f.handle.requestPermission({ mode: 'readwrite' }) !== 'granted') throw new Error('the browser did not allow writing');
          }
          const out = await f.handle.createWritable();
          await out.write(f.bytes);
          await out.close();
          f.original = f.bytes;
          f.dirty = false;
          f.lastModified = (await f.handle.getFile()).lastModified;
          written.push(f.path);
        } catch (err) {
          failed.push(`${f.path} (${errText(err)})`);
        }
      } else {
        const a = document.createElement('a');
        a.href = URL.createObjectURL(new Blob([f.bytes], { type: /\.png$/i.test(f.path) ? 'image/png' : 'text/plain' }));
        a.download = f.path.split('/').pop();
        document.body.appendChild(a);
        a.click();
        a.remove();
        setTimeout(() => URL.revokeObjectURL(a.href), 10000);
        downloaded += 1;
      }
    }
    renderProject();
    const lines = [];
    if (written.length) lines.push(`Saved ${written.length} file(s):`, ...written.slice(0, 4));
    if (downloaded) lines.push(`This browser opened the folder read-only, so ${downloaded} edited file(s) were offered as downloads.`);
    if (failed.length) lines.push(`${failed.length} file(s) were not written:`, ...failed.slice(0, 4));
    await desk.requester(win, { title: 'Save', tone: failed.length ? 'fault' : undefined, lines });
    return { written: written.length, changed, downloaded, failed };
  }

  async function diskHas(dir, path) {
    const parts = path.split('/');
    try {
      let d = dir;
      for (const part of parts.slice(0, -1)) d = await d.getDirectoryHandle(part);
      await d.getFileHandle(parts[parts.length - 1]);
      return true;
    } catch {
      return false;
    }
  }

  function sameBytes(a, b) {
    if (a.length !== b.length) return false;
    for (let i = 0; i < a.length; i += 1) if (a[i] !== b[i]) return false;
    return true;
  }

  // ------------------------------------------------------------ windows

  const screen = desk.screen(`BeSpoke Studio ${STUDIO_BUILD.version}`);
  let projectWin = null;
  const player = createPlay(desk, screen, {
    build: () => play(),
    reportFault,
    openScript: (path, l, c) => openScript(path, l, c),
    // The lines that could have written a fact (P47-09, D-205), from the Studio module.
    writers: (f) => withCompiler((x) => {
      const m = put(x, enc.encode(S.project.main));
      const q = put(x, enc.encode(`${f.relation}\t${f.subject}\t${f.object}`));
      const status = x.studio_writers(m.ptr, m.used, q.ptr, q.used);
      x.studio_free(m.ptr, m.len);
      x.studio_free(q.ptr, q.len);
      if (status < 0) throw new Error('the compiler ran out of memory');
      return status === 1 ? decodeJson(x) : null;
    }),
  });

  // The pixel editor's view of the project and the Studio module (D-196).
  function decodeJson(x) {
    return JSON.parse(new TextDecoder().decode(new Uint8Array(x.memory.buffer, x.studio_result_ptr(), x.studio_result_len())));
  }
  function listArt() {
    return withCompiler((x) => {
      const p = put(x, enc.encode(S.project.main));
      const status = x.studio_art(p.ptr, p.used);
      x.studio_free(p.ptr, p.len);
      if (status < 0) throw new Error('the compiler ran out of memory');
      return decodeJson(x);
    });
  }

  function readPixels(path) {
    return withCompiler((x) => {
      const p = put(x, enc.encode(path));
      const status = x.studio_pixels(p.ptr, p.used);
      x.studio_free(p.ptr, p.len);
      if (status < 0) throw new Error('the compiler ran out of memory');
      if (status === 0) return null;
      const rgba = new Uint8ClampedArray(x.memory.buffer, x.studio_blob_ptr(), x.studio_blob_len()).slice();
      return { width: x.studio_blob_width(), height: x.studio_blob_height(), rgba };
    });
  }

  // The bytes the module's table holds for `path` (a script it just wrote).
  function moduleFile(path) {
    return withCompiler((x) => {
      const p = put(x, enc.encode(path));
      const found = x.studio_file(p.ptr, p.used);
      x.studio_free(p.ptr, p.len);
      return found === 1 ? new Uint8Array(x.memory.buffer, x.studio_blob_ptr(), x.studio_blob_len()).slice() : null;
    });
  }

  const painter = createPaint(desk, screen, {
    ready: (title) => readyToBuild(title, () => painter.openArt()),
    home: () => projectWindow(),
    showResult: (r) => showResult(r),
    openScript: (path, l, c) => openScript(path, l, c),
    isDirty: (path) => Boolean(findFile(path) && findFile(path).dirty),
    listArt: () => listArt(),
    readPixels: (path) => readPixels(path),
    encode: (w, h, pixels) => withCompiler((x) => {
      const d = put(x, pixels);
      const ok = x.studio_encode(w, h, d.ptr, d.used);
      x.studio_free(d.ptr, d.len);
      if (!ok) return { ok: false, error: new TextDecoder().decode(new Uint8Array(x.memory.buffer, x.studio_result_ptr(), x.studio_result_len())) };
      return { ok: true, bytes: new Uint8Array(x.memory.buffer, x.studio_blob_ptr(), x.studio_blob_len()).slice() };
    }) || { ok: false, error: 'the compiler is not running' },
    fileReverted: (path) => { const f = findFile(path); if (f) painterFileChanged(path, f.original || f.base); },
    mainScript: () => (S.project ? S.project.main : ''),
    scripts: () => S.project.files.map((f) => f.path).filter((p) => /\.bespoke$/i.test(p)).sort(),
    pickPng: () => pickPng(),
    // One new image (D-197): the module adds the PNG and the line and checks the project; the
    // page then takes the script's new bytes and the new file as edits waiting for Save.
    addImage: (req) => withCompiler((x) => {
      const m = put(x, enc.encode(S.project.main));
      const sc = put(x, enc.encode(req.script));
      const nm = put(x, enc.encode(req.name));
      const fl = put(x, enc.encode(req.file));
      const pn = put(x, req.png);
      const status = x.studio_add_image(m.ptr, m.used, sc.ptr, sc.used, nm.ptr, nm.used, fl.ptr, fl.used, req.fw, req.fh, pn.ptr, pn.used);
      for (const b of [m, sc, nm, fl, pn]) x.studio_free(b.ptr, b.len);
      if (status < 0) throw new Error('the compiler ran out of memory');
      const r = decodeJson(x);
      if (status === 0) return r.added === false ? { refused: r.refused } : { added: false, result: r };
      const p = put(x, enc.encode(r.script));
      x.studio_file(p.ptr, p.used);
      x.studio_free(p.ptr, p.len);
      const scriptBytes = new Uint8Array(x.memory.buffer, x.studio_blob_ptr(), x.studio_blob_len()).slice();
      const f = findFile(r.script);
      f.bytes = scriptBytes;
      f.dirty = !sameBytes(scriptBytes, f.original);
      S.project.files.push({ path: r.file, bytes: req.png, original: null, base: req.png, dirty: true, handle: null, isNew: true });
      S.project.files.sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
      S.result = null;
      renderProject();
      return { added: true, script: r.script, file: r.file, line: r.line };
    }),
    fileChanged: (path, bytes) => painterFileChanged(path, bytes),
  });
  // An edit becomes the file's bytes in the page and in the compiler's table, so Check and Play
  // use it before Save writes it.
  function painterFileChanged(path, bytes) {
    const f = findFile(path);
    if (!f) return;
    f.bytes = bytes;
    f.dirty = f.original ? !sameBytes(bytes, f.original) : true;
    withCompiler((x) => {
      const p = put(x, enc.encode(path));
      const d = put(x, bytes);
      const ok = x.studio_add_file(p.ptr, p.used, d.ptr, d.used);
      x.studio_free(p.ptr, p.len);
      x.studio_free(d.ptr, d.len);
      if (!ok) throw new Error(`the compiler refused ${path}`);
    });
    renderProject();
  }
  const roomer = createRooms(desk, screen, {
    ready: (title) => readyToBuild(title, () => roomer.openRooms()),
    mainScript: () => (S.project ? S.project.main : ''),
    home: () => projectWindow(),
    showResult: (r) => showResult(r),
    listArt: () => listArt(),
    readPixels: (path) => readPixels(path),
    listRooms: () => withCompiler((x) => {
      const p = put(x, enc.encode(S.project.main));
      const status = x.studio_rooms(p.ptr, p.used);
      x.studio_free(p.ptr, p.len);
      if (status < 0) throw new Error('the compiler ran out of memory');
      return decodeJson(x);
    }),
    // One room block written and checked by the module (D-200); the page then takes the
    // script's new bytes as an edit waiting for Save.
    writeRoom: (records) => withCompiler((x) => {
      const m = put(x, enc.encode(S.project.main));
      const r = put(x, enc.encode(records));
      const status = x.studio_write_room(m.ptr, m.used, r.ptr, r.used);
      x.studio_free(m.ptr, m.len);
      x.studio_free(r.ptr, r.len);
      if (status < 0) throw new Error('the compiler ran out of memory');
      const j = decodeJson(x);
      if (status === 1) return j;
      return j.written === false ? { written: false, refused: j.refused } : { written: false, result: j };
    }),
    fileBytes: (path) => { const f = findFile(path); return f ? f.bytes : null; },
    scriptBytes: () => Object.fromEntries(S.project.files.filter((f) => /\.bespoke$/i.test(f.path)).map((f) => [f.path, f.bytes])),
    scriptWritten: (path) => { const bytes = moduleFile(path); if (bytes) painterFileChanged(path, bytes); },
    setScript: (path, bytes) => painterFileChanged(path, bytes),
  });

  function writeDilemmaRecords(records) {
    return withCompiler((x) => {
      const m = put(x, enc.encode(S.project.main));
      const r = put(x, enc.encode(records));
      const status = x.studio_write_dilemma(m.ptr, m.used, r.ptr, r.used);
      x.studio_free(m.ptr, m.len);
      x.studio_free(r.ptr, r.len);
      if (status < 0) throw new Error('the compiler ran out of memory');
      const j = decodeJson(x);
      if (status === 1) return j;
      return j.written === false ? { written: false, refused: j.refused } : { written: false, result: j };
    });
  }

  function listDilemmas() {
    return withCompiler((x) => {
      const p = put(x, enc.encode(S.project.main));
      const status = x.studio_dilemmas(p.ptr, p.used);
      x.studio_free(p.ptr, p.len);
      if (status < 0) throw new Error('the compiler ran out of memory');
      return decodeJson(x);
    });
  }

  const caster = createCast(desk, screen, {
    ready: (title) => readyToBuild(title, () => caster.open()),
    showResult: (r) => showResult(r),
    openScript: (path, l, c) => openScript(path, l, c),
    listCast: () => withCompiler((x) => {
      const p = put(x, enc.encode(S.project.main));
      const status = x.studio_cast(p.ptr, p.used);
      x.studio_free(p.ptr, p.len);
      if (status < 0) throw new Error('the compiler ran out of memory');
      return decodeJson(x);
    }),
    writeCast: (record) => withCompiler((x) => {
      const m = put(x, enc.encode(S.project.main));
      const r = put(x, enc.encode(record));
      const status = x.studio_write_cast(m.ptr, m.used, r.ptr, r.used);
      x.studio_free(m.ptr, m.len);
      x.studio_free(r.ptr, r.len);
      if (status < 0) throw new Error('the compiler ran out of memory');
      const j = decodeJson(x);
      if (status === 1) return j;
      return j.written === false ? { written: false, refused: j.refused } : { written: false, result: j };
    }),
    fileBytes: (path) => { const f = findFile(path); return f ? f.bytes : null; },
    scriptBytes: () => Object.fromEntries(S.project.files.filter((f) => /\.bespoke$/i.test(f.path)).map((f) => [f.path, f.bytes])),
    scriptWritten: (path) => { const bytes = moduleFile(path); if (bytes) painterFileChanged(path, bytes); },
    setScript: (path, bytes) => painterFileChanged(path, bytes),
    // A new mark or prop changes what the room editor shows, so its windows list again.
    castChanged: () => { roomer.reset(); roomer.relist(); dilemmer.relist(); },
    listDilemmas: () => listDilemmas(),
    writeRedLines: (record) => writeDilemmaRecords(record),
  });

  const dilemmer = createDilemmas(desk, screen, {
    ready: (title) => readyToBuild(title, () => dilemmer.open()),
    showResult: (r) => showResult(r),
    listDilemmas: () => listDilemmas(),
    listCast: () => withCompiler((x) => {
      const p = put(x, enc.encode(S.project.main));
      const status = x.studio_cast(p.ptr, p.used);
      x.studio_free(p.ptr, p.len);
      if (status < 0) throw new Error('the compiler ran out of memory');
      return decodeJson(x);
    }),
    // A dilemma block written and checked by the module (D-203); the page takes the script's
    // new bytes as an edit waiting for Save, and the Cast window lists again.
    writeDilemma: (records) => {
      const r = writeDilemmaRecords(records);
      if (r && r.written) {
        for (const path of r.scripts) { const bytes = moduleFile(path); if (bytes) painterFileChanged(path, bytes); }
        caster.relist();
      }
      return r;
    },
    previewTier: (name, a, c, mask) => withCompiler((x) => {
      const m = put(x, enc.encode(S.project.main));
      const n = put(x, enc.encode(name));
      const status = x.studio_preview_tier(m.ptr, m.used, n.ptr, n.used, a, c, mask);
      x.studio_free(m.ptr, m.len);
      x.studio_free(n.ptr, n.len);
      if (status < 0) throw new Error('the compiler ran out of memory');
      return status === 1 ? decodeJson(x) : null;
    }),
  });

  function dialogueCall(fn, ...args) {
    return withCompiler((x) => {
      const m = put(x, enc.encode(S.project.main));
      const r = put(x, enc.encode(args[0]));
      const status = fn === 'write' ? x.studio_write_dialogue(m.ptr, m.used, r.ptr, r.used) : x.studio_preview_dialogue(r.ptr, r.used);
      x.studio_free(m.ptr, m.len);
      x.studio_free(r.ptr, r.len);
      if (status < 0) throw new Error('the compiler ran out of memory');
      const j = decodeJson(x);
      if (fn !== 'write') return j;
      if (status === 1) return j;
      return j.written === false ? { written: false, refused: j.refused } : { written: false, result: j };
    });
  }

  const talker = createTalk(desk, screen, {
    ready: (title) => readyToBuild(title, () => talker.open()),
    previewDialogue: (records) => dialogueCall('preview', records),
    // A dialogue block written and checked by the module (D-206); the page takes the script's
    // new bytes as an edit waiting for Save.
    writeDialogue: (records) => {
      const r = dialogueCall('write', records);
      if (r && r.written) for (const path of r.scripts) { const bytes = moduleFile(path); if (bytes) painterFileChanged(path, bytes); }
      return r;
    },
    firstCast: () => {
      const c = withCompiler((x) => {
        const p = put(x, enc.encode(S.project.main));
        const status = x.studio_cast(p.ptr, p.used);
        x.studio_free(p.ptr, p.len);
        return status === 1 ? decodeJson(x) : null;
      });
      return c && c.scenes.flatMap((sc) => sc.cast)[0];
    },
    showResult: (r) => showResult(r),
    openScript: (path, l, c) => openScript(path, l, c),
    listDialogue: () => withCompiler((x) => {
      const p = put(x, enc.encode(S.project.main));
      const status = x.studio_dialogue(p.ptr, p.used);
      x.studio_free(p.ptr, p.len);
      if (status < 0) throw new Error('the compiler ran out of memory');
      return decodeJson(x);
    }),
  });

  window.addEventListener('beforeunload', (e) => { if (dirtyFiles().length) { e.preventDefault(); e.returnValue = ''; } });

  function line(text, cls) {
    const row = document.createElement('div');
    row.className = `line ${cls || ''}`.trim();
    row.appendChild(desk.label(text));
    return row;
  }

  function buttons(win, list) {
    const row = document.createElement('div');
    row.className = 'row';
    for (const [id, text] of list) row.appendChild(desk.button(win, id, text));
    return row;
  }

  function projectWindow() {
    if (projectWin) return projectWin;
    projectWin = desk.window(screen, {
      id: 'project', title: 'Project', x: 16, y: 16, w: 460, h: 330, minW: 220, minH: 140,
      onMessage: async (msg) => {
        if (msg.kind === 'close') { projectWin.close(); projectWin = null; return; }
        if (msg.kind === 'resize') { renderProject(); return; }
        if (msg.kind !== 'gadget') return;
        if (msg.id.startsWith('main:')) { await chooseScript(msg.id.slice(5)); return; }
        await command(msg.id);
      },
    });
    renderProject();
    return projectWin;
  }

  function cols(win) {
    return Math.max(12, Math.floor((win.rect.w - 16 * desk.px()) / (desk.advance * desk.px())));
  }

  function fit(text, n) {
    const chars = [...text];
    return chars.length <= n ? text : `${chars.slice(0, Math.max(1, n - 3)).join('')}...`;
  }

  function renderProject() {
    const win = projectWin;
    if (!win) return;
    const n = cols(win);
    const out = [];
    const p = S.project;
    if (S.compiler.state === 'unavailable') {
      out.push(line(fit(`Compiler: not running (${S.compiler.error})`, n), 'err'));
      out.push(buttons(win, [['retry', 'Retry']]));
    } else if (S.compiler.state === 'loading') {
      out.push(line('Compiler: starting...'));
    }
    if (!p) {
      out.push(line('No project is open.'));
      out.push(buttons(win, [['open-folder', 'Open folder'], ['open-files', 'Open files']]));
    } else {
      out.push(line(fit(`Folder: ${p.name}${p.writable ? '' : ' (read-only)'}`, n)));
      out.push(line(fit(`Script: ${p.main || 'none'}`, n)));
      const list = document.createElement('div');
      list.className = 'list';
      for (const f of p.files.filter((x) => /\.bespoke$/i.test(x.path))) {
        const b = desk.button(win, `main:${f.path}`, fit(`${f.path === p.main ? '> ' : '  '}${f.path}`, n - 2), { cls: 'item' });
        if (f.path === p.main) b.classList.add('selected');
        list.appendChild(b);
      }
      out.push(list);
      const r = S.result;
      if (r) {
        const counts = `${r.scenes} scene(s), ${r.routines} routine(s), ${r.rules} rule(s)`;
        const warn = r.warnings.length ? `, ${r.warnings.length} warning(s)` : '';
        out.push(line(fit(r.valid ? `Valid: ${counts}${warn}` : `1 error${warn}`, n), r.valid ? '' : 'err'));
      }
      const edited = dirtyFiles().length;
      if (edited) out.push(line(fit(`${edited} edited file(s) not saved`, n), 'err'));
      out.push(buttons(win, [['check', 'Check'], ['play', 'Play'], ['art', 'Art'], ['rooms', 'Rooms'], ['cast', 'Cast'], ['dilemmas', 'Dilemmas'], ['dialogue', 'Dialogue'], ['save', 'Save'], ['open-folder', 'Open folder']]));
    }
    win.body.replaceChildren(...out);
  }

  let diagWin = null;
  function renderDiagnostics(open) {
    const r = S.result;
    if (!diagWin && !open) return;
    if (!diagWin) {
      const a = screen.area.getBoundingClientRect();
      diagWin = desk.window(screen, {
        id: 'diagnostics', title: 'Diagnostics', x: Math.min(500, a.width * 0.4), y: 40, w: 520, h: 220, minW: 200, minH: 100,
        onMessage: (msg) => {
          if (msg.kind === 'close') { diagWin.close(); diagWin = null; return; }
          if (msg.kind === 'resize') { renderDiagnostics(false); return; }
          if (msg.kind === 'gadget' && msg.id.startsWith('at:')) {
            const [, file, l, c] = msg.id.split('\u0000');
            openScript(file, Number(l), Number(c));
          }
        },
      });
    }
    const n = cols(diagWin);
    const out = [];
    if (!r) out.push(line('No check has run yet.'));
    else {
      const items = [];
      if (!r.valid) items.push({ ...r, tag: 'error' });
      for (const w of r.warnings) items.push({ ...w, tag: 'warning' });
      if (!items.length) out.push(line(fit(`No problems in ${r.main}.`, n)));
      const list = document.createElement('div');
      list.className = 'list';
      for (const it of items) {
        const text = it.line ? `${it.file}:${it.line}:${it.column} ${it.tag}: ${it.message}` : `${it.file} ${it.tag}: ${it.message}`;
        const b = desk.button(diagWin, `at:\u0000${it.file}\u0000${it.line}\u0000${it.column}`, fit(text, n - 2), { cls: `item ${it.tag === 'error' ? 'err' : ''}` });
        b.setAttribute('aria-label', text);
        list.appendChild(b);
      }
      out.push(list);
    }
    diagWin.body.replaceChildren(...out);
  }

  // A read-only view of one project file with the diagnostic's line marked and a caret under
  // its column. The text is decoded for display only; the bytes the project holds never change.
  // ------------------------------------------------------------ scripts as text (P47-17, D-211)

  function textOf(bytes) {
    const t = new TextDecoder('utf-8').decode(bytes);
    return t.charCodeAt(0) === 0xfeff ? t.slice(1) : t;
  }

  // Text from the editor back to bytes in the file's own form: its byte-order mark and its
  // line endings (CRLF when it used them), so an edit changes only the lines it touched.
  function bytesLike(old, text) {
    const bom = old.length >= 3 && old[0] === 0xef && old[1] === 0xbb && old[2] === 0xbf;
    let t = text.replace(/\r\n|\r/g, '\n');
    if (/\r\n/.test(textOf(old))) t = t.replace(/\n/g, '\r\n');
    const body = enc.encode(t);
    if (!bom) return body;
    const out = new Uint8Array(body.length + 3);
    out.set([0xef, 0xbb, 0xbf]);
    out.set(body, 3);
    return out;
  }

  // The other editors list what the module holds; after a text edit they list it again.
  async function relistEditors() {
    await painter.relist();
    await roomer.relist();
    await caster.relist();
    await dilemmer.relist();
    await talker.relist();
  }

  // Keeps `text` as the file at `path` only if the project still compiles with it (D-211):
  // the module checks the main script with the new bytes, and a refusal puts the old bytes
  // back. Returns { written } or { written: false, result } with the compiler's report.
  async function applyText(path, text) {
    const f = findFile(path);
    if (!f) return { written: false, refused: `${path} is not in the opened project.` };
    const old = f.bytes;
    const bytes = bytesLike(old, text);
    if (sameBytes(bytes, old)) return { written: true, same: true };
    painterFileChanged(path, bytes);
    const r = runCheck(S.project.main);
    if (!r || !r.valid) {
      painterFileChanged(path, old);
      return { written: false, result: r };
    }
    S.result = r;
    renderProject();
    renderDiagnostics(r.warnings.length > 0);
    await relistEditors();
    return { written: true, result: r };
  }

  // A script in a window: read-only lines with a marked line, or, after Edit, a text area.
  // `opts.edit` opens straight into the text area.
  function openScript(path, lineNo, column, opts = {}) {
    const f = findFile(path);
    if (!f) { desk.requester(projectWindow(), { title: 'Show line', lines: [`${path} is not in the opened project.`] }); return null; }
    const id = `script:${path}`;
    let win = screen.windows.find((w) => w.id === id);
    if (!win) {
      const a = screen.area.getBoundingClientRect();
      const state = { bytes: null, lines: [], mark: lineNo, column, top: 0, editing: false, error: '' };
      const bar = document.createElement('div');
      bar.className = 'row';
      const view = document.createElement('div');
      view.className = 'view';
      const rows = document.createElement('div');
      rows.className = 'rows';
      const prop = desk.propGadget((top) => { state.top = top; draw(); });
      view.append(rows, prop.el);
      const area = document.createElement('textarea');
      area.className = 'strgad script-text';
      area.spellcheck = false;
      area.autocomplete = 'off';
      area.setAttribute('aria-label', `Text of ${path}`);
      area.onkeydown = (e) => e.stopPropagation();
      const note = document.createElement('div');
      function current() {
        const file = findFile(path);
        if (file && file.bytes !== state.bytes) {
          state.bytes = file.bytes;
          state.lines = textOf(file.bytes).split(/\r\n|\n|\r/).map((l) => l.replace(/\t/g, '  '));
        }
        return file;
      }
      function visible() {
        return Math.max(1, Math.floor(rows.getBoundingClientRect().height / (9 * desk.px())));
      }
      function draw() {
        current();
        const vis = visible();
        const width = String(state.lines.length).length;
        const out = [];
        const n = Math.max(8, Math.floor(rows.getBoundingClientRect().width / (desk.advance * desk.px())));
        for (let i = state.top; i < state.lines.length && out.length < vis; i += 1) {
          const no = i + 1;
          out.push(line(fit(`${String(no).padStart(width)} ${state.lines[i]}`, n), no === state.mark ? 'mark' : ''));
          if (no === state.mark && state.column > 0 && out.length < vis) {
            out.push(line(`${' '.repeat(width + state.column)}^`, 'err'));
          }
        }
        rows.replaceChildren(...out);
        prop.set(state.lines.length + (state.mark ? 1 : 0), vis, state.top);
      }
      function layout() {
        const pairs = state.editing ? [['script-apply', 'Apply'], ['script-cancel', 'Cancel']] : [['script-edit', 'Edit']];
        bar.replaceChildren(...pairs.map(([gid, text]) => desk.button(win, gid, text)));
        note.replaceChildren(...(state.error ? [line(fit(state.error, 80), 'err')] : []));
        win.body.replaceChildren(bar, note, state.editing ? area : view);
        if (!state.editing) draw();
      }
      // Puts the caret at the start of a line in the text area.
      function caretTo(no) {
        const text = area.value;
        let at = 0;
        for (let k = 1; k < no && at >= 0; k += 1) at = text.indexOf('\n', at) + (at === -1 ? 0 : 1);
        area.focus();
        area.setSelectionRange(Math.max(0, at), Math.max(0, at));
      }
      function edit() {
        const file = current();
        if (!file) return;
        area.value = textOf(file.bytes);
        state.editing = true;
        state.error = '';
        layout();
        caretTo(state.mark || 1);
      }
      async function apply() {
        const r = await applyText(path, area.value);
        if (r.written) {
          state.editing = false;
          state.error = '';
          layout();
          return;
        }
        const res = r.result;
        state.error = r.refused || (res ? (res.line ? `Not kept: ${res.file}, line ${res.line}: ${res.message}` : `Not kept: ${res.message}`) : 'Not kept: the compiler is not running.');
        layout();
        if (res && res.line && res.file === path) caretTo(res.line);
      }
      rows.addEventListener('wheel', (e) => { e.preventDefault(); prop.moveTo(state.top + Math.sign(e.deltaY) * 3); }, { passive: false });
      win = desk.window(screen, {
        id, title: path, x: Math.min(120, a.width * 0.1), y: 90, w: Math.min(640, a.width), h: Math.min(360, a.height - 90), minW: 160, minH: 110,
        onMessage: async (msg) => {
          if (msg.kind === 'close') {
            if (state.editing && area.value !== textOf(current().bytes)) {
              const pick = await desk.requester(win, { title: path, lines: ['The text has changes that were not applied.', 'Close and lose them?'], buttons: [{ id: 'lose', label: 'Lose them' }, { id: 'cancel', label: 'Cancel' }] });
              if (pick !== 'lose') return;
            }
            win.close();
          }
          if (msg.kind === 'resize' && !state.editing) draw();
          if (msg.kind === 'goto') {
            state.mark = msg.line;
            state.column = msg.column;
            state.top = Math.max(0, msg.line - 1 - Math.floor(visible() / 2));
            if (state.editing) caretTo(msg.line); else draw();
          }
          if (msg.kind === 'gadget') {
            if (msg.id === 'script-edit') edit();
            if (msg.id === 'script-cancel') { state.editing = false; state.error = ''; layout(); }
            if (msg.id === 'script-apply') await apply();
          }
        },
      });
      win.scriptText = (text) => { area.value = text; return true; };
      win.scriptState = () => ({ editing: state.editing, error: state.error, text: state.editing ? area.value : null });
      layout();
    }
    win.toFront();
    win.activate();
    win.port.post({ kind: 'goto', line: lineNo || 1, column: column || 0 });
    if (opts.edit) win.port.post({ kind: 'gadget', id: 'script-edit' });
    return win;
  }

  // ------------------------------------------------------------ new projects and scripts (P47-16, D-211)

  // A one-line question in its own small window; resolves to the text, or null on Cancel.
  function askText(title, label, value) {
    return new Promise((resolve) => {
      const a = screen.area.getBoundingClientRect();
      let done = false;
      const input = document.createElement('input');
      const w = desk.window(screen, {
        id: `ask:${title}`, title, x: Math.max(0, (a.width - 340) / 2), y: 120, w: Math.min(340, a.width), h: 130, minW: 200, minH: 100,
        onMessage: (msg) => {
          if (msg.kind === 'close') finish(null);
          if (msg.kind === 'gadget') finish(msg.id === 'ask-ok' ? input.value : null);
        },
      });
      function finish(v) {
        if (done) return;
        done = true;
        w.close();
        resolve(v);
      }
      input.className = 'strgad';
      input.value = value;
      input.autocomplete = 'off';
      input.spellcheck = false;
      input.setAttribute('aria-label', label);
      input.onkeydown = (e) => {
        e.stopPropagation();
        if (e.key === 'Enter') finish(input.value);
        if (e.key === 'Escape') finish(null);
      };
      const row = document.createElement('label');
      row.className = 'line field';
      row.append(desk.label(label), input);
      w.body.append(row, buttons(w, [['ask-ok', 'OK'], ['ask-cancel', 'Cancel']]));
      w.toFront();
      w.activate();
      input.focus();
      input.select();
    });
  }

  // A new project (D-211): `bespoke init`'s starter script, stage or text, written as
  // scripts/main.bespoke into an empty folder the author picks, then opened. Without folder
  // access the project lives in the page and Save offers the script as a download.
  // `opts.kind` and `opts.handle` skip the questions, for tests.
  async function newProject(opts = {}) {
    if (!await confirmDiscard()) return false;
    const win = projectWindow();
    let kind = opts.kind;
    if (!kind) {
      kind = await desk.requester(win, {
        title: 'New project',
        lines: ['A starter game to build on, in a folder of its own.', 'Stage: drawn, and played by pointer.', 'Text: typed commands, with a picture.'],
        buttons: [{ id: 'stage', label: 'Stage' }, { id: 'text', label: 'Text' }, { id: 'cancel', label: 'Cancel' }],
      });
      if (kind !== 'stage' && kind !== 'text') return false;
    }
    let handle = opts.handle || null;
    if (!handle && window.showDirectoryPicker && !opts.inPage) {
      try { handle = await window.showDirectoryPicker({ id: 'bespoke-new', mode: 'readwrite' }); } catch (err) {
        if (err && err.name === 'AbortError') return false;
        throw err;
      }
    }
    if (handle) {
      for await (const entry of handle.values()) {
        if (entry.name.startsWith('.')) continue;
        await desk.requester(win, { title: 'New project', lines: [`"${handle.name}" is not empty.`, 'Choose an empty folder, or make a new one in the folder picker.'] });
        return false;
      }
    }
    const name = nameFor(handle ? handle.name : 'new_game');
    const bytes = enc.encode(STUDIO_BUILD.starters[kind].split('{{name}}').join(name));
    const file = { path: 'scripts/main.bespoke', bytes, original: null, base: bytes, dirty: true, handle: null, isNew: true };
    const opened = await finishOpen({ name: handle ? handle.name : name, handle, writable: Boolean(handle) }, { files: [file], skipped: [], total: bytes.length });
    if (!opened) return false;
    // The starter is written at once, so the folder is a project from the first moment.
    if (handle) await save();
    return true;
  }

  // A new script beside the main script, with its `include` line in the main script (D-211),
  // both checked together; refused, neither is kept. Opens the new script for editing.
  async function newScript(opts = {}) {
    if (!await readyToBuild('New script', () => newScript(opts))) return null;
    const win = projectWindow();
    const asked = opts.name !== undefined ? opts.name : await askText('New script', 'Name', 'more');
    if (asked === null) return null;
    const name = asked.trim().replace(/\.bespoke$/i, '');
    if (!/^[A-Za-z][A-Za-z0-9_-]{0,31}$/.test(name)) {
      await desk.requester(win, { title: 'New script', lines: [`"${name}" can't name a script.`, 'Use a letter, then up to 31 letters, digits, hyphens, or underscores.'] });
      return null;
    }
    const main = S.project.main;
    const dir = main.includes('/') ? main.slice(0, main.lastIndexOf('/') + 1) : '';
    const path = `${dir}${name}.bespoke`;
    if (findFile(path)) {
      await desk.requester(win, { title: 'New script', lines: [`${path} is already in the project.`] });
      return null;
    }
    const mf = findFile(main);
    const oldMain = mf.bytes;
    const lines = textOf(oldMain).split(/\r\n|\n|\r/);
    // After the last include; with none, after the comment lines that open the script.
    let at = -1;
    lines.forEach((l, i) => { if (/^include\s/.test(l)) at = i + 1; });
    const fresh = at < 0;
    if (fresh) {
      at = 0;
      while (at < lines.length && lines[at].startsWith('#')) at += 1;
    }
    const insert = [`include "${name}.bespoke"`];
    if (fresh && at < lines.length && lines[at].trim() !== '') insert.push('');
    lines.splice(at, 0, ...insert);
    const newMain = bytesLike(oldMain, lines.join('\n'));
    const body = enc.encode(`# ${name}: included by ${main.split('/').pop()}.\n`);
    S.project.files.push({ path, bytes: body, original: null, base: body, dirty: true, handle: null, isNew: true });
    S.project.files.sort((x, y) => (x.path < y.path ? -1 : x.path > y.path ? 1 : 0));
    mf.bytes = newMain;
    mf.dirty = !sameBytes(newMain, mf.original);
    if (loadIntoCompiler() === null) return null;
    const r = runCheck(main);
    if (!r || !r.valid) {
      S.project.files = S.project.files.filter((f) => f.path !== path);
      mf.bytes = oldMain;
      mf.dirty = !sameBytes(oldMain, mf.original);
      loadIntoCompiler();
      renderProject();
      if (r) await showResult(r);
      return null;
    }
    S.result = r;
    renderProject();
    await relistEditors();
    openScript(path, 1, 0, { edit: true });
    return { path, line: at + 1 };
  }

  // Held menus need a secondary mouse button; where the Menus gadget shows instead (touch, or a
  // narrow window), the hint names that.
  function menuHint() {
    return window.matchMedia('(max-width: 700px), (pointer: coarse)').matches
      ? 'Tap Menus for the menus.' : 'Hold the right mouse button for menus.';
  }

  let aboutWin = null;
  function about() {
    if (aboutWin) { aboutWin.toFront(); return aboutWin; }
    const a = screen.area.getBoundingClientRect();
    aboutWin = desk.window(screen, {
      id: 'about', title: 'About the Studio', x: Math.max(0, a.width - 420), y: Math.max(0, a.height - 230), w: 400, h: 210, minW: 200, minH: 100,
      onMessage: async (msg) => {
        if (msg.kind === 'close' || (msg.kind === 'gadget' && msg.id === 'about-ok')) { aboutWin.close(); aboutWin = null; return; }
        if (msg.kind === 'gadget') await command(msg.id);
      },
    });
    const n = cols(aboutWin);
    const lines = [
      `BeSpoke Studio ${STUDIO_BUILD.version}`,
      'Start a New project or open a project folder to check its scripts, Play to run the game, Art to paint its PNGs, Rooms to lay out its scenes, and Cast to name its people and values. A script window edits its text.',
      menuHint(),
      'Drag the screen down by its title bar.',
    ];
    if (!S.storage) lines.push('This browser will not keep settings.');
    const out = [];
    for (const l of lines) for (const part of desk.wrapText(l, n)) out.push(line(part));
    out.push(buttons(aboutWin, [['open-folder', 'Open folder'], ['about-ok', 'OK']]));
    aboutWin.body.replaceChildren(...out);
    // The window grows (upward, so it stays in its corner) until every line shows; the text
    // grew with Play and Art, and a fixed height cut its last line off.
    const short = aboutWin.body.scrollHeight - aboutWin.body.clientHeight;
    if (short > 0) {
      const r = aboutWin.rect;
      aboutWin.place(r.x, r.y - short, r.w, r.h + short);
    }
    return aboutWin;
  }

  // ------------------------------------------------------------ menus and keys

  function menus() {
    const scale = (n) => ({ id: `scale-${n}`, label: `${S.scale === n ? '* ' : '  '}${n}x`, checked: S.scale === n });
    return [
      {
        title: 'Project',
        items: [
          { id: 'new-project', label: 'New project...' },
          { id: 'open-folder', label: 'Open folder...', key: 'O' },
          { id: 'open-files', label: 'Open files...' },
          { id: 'new-script', label: 'New script...' },
          { id: 'check', label: 'Check script', key: 'K' },
          { id: 'play', label: 'Play game', key: 'G' },
          { id: 'export', label: 'Export page...', key: 'E' },
          { id: 'art', label: 'Art...' },
          { id: 'rooms', label: 'Rooms...' },
          { id: 'cast', label: 'Cast...' },
          { id: 'dilemmas', label: 'Dilemmas...' },
          { id: 'dialogue', label: 'Dialogue...' },
          { id: 'save', label: 'Save', key: 'S' },
          { id: 'about', label: 'About the Studio' },
        ],
      },
      {
        title: 'Window',
        items: [
          { id: 'win-project', label: 'Project' },
          { id: 'win-diagnostics', label: 'Diagnostics' },
          { id: 'win-play', label: 'Play' },
          { id: 'win-art', label: 'Art' },
          { id: 'win-rooms', label: 'Rooms' },
          { id: 'win-cast', label: 'Cast' },
          { id: 'win-dilemmas', label: 'Dilemmas' },
          { id: 'win-dialogue', label: 'Dialogue' },
        ],
      },
      { title: 'Settings', items: [scale(1), scale(2), scale(3)] },
    ];
  }

  async function command(id) {
    switch (id) {
      case 'new-project': return newProject();
      case 'new-script': return newScript();
      case 'open-folder': return openFolder();
      case 'open-files': return openFiles();
      case 'check': return check();
      case 'play': return play();
      case 'export': return exportPage();
      case 'win-play': return player.open();
      case 'art':
      case 'win-art': return painter.openArt();
      case 'rooms':
      case 'win-rooms': return roomer.openRooms();
      case 'cast':
      case 'win-cast': return caster.open();
      case 'dilemmas':
      case 'win-dilemmas': return dilemmer.open();
      case 'dialogue':
      case 'win-dialogue': return talker.open();
      case 'save': return save();
      case 'retry': if (await startCompiler() && S.project && loadIntoCompiler() !== null) await check(); return null;
      case 'about': return about();
      case 'win-project': { const w = projectWindow(); w.toFront(); w.activate(); return w; }
      case 'win-diagnostics': renderDiagnostics(true); diagWin.toFront(); return diagWin;
      default:
        if (id.startsWith('scale-')) { saveScale(Number(id.slice(6))); return null; }
        return null;
    }
  }

  desk.pickMenu = (item) => { command(item.id).catch(desk.onHandlerError); };

  document.addEventListener('keydown', (e) => {
    if (!(isMac ? e.metaKey : e.ctrlKey) || e.altKey || e.shiftKey) return;
    if (document.querySelector('.veil')) return;
    const key = e.key.toUpperCase();
    for (const menu of menus()) {
      for (const item of menu.items) {
        if (item.key === key) { e.preventDefault(); command(item.id).catch(desk.onHandlerError); return; }
      }
    }
  });

  // ------------------------------------------------------------ boot

  // The workspace comes up first and owes nothing to the compiler, a project, or a setting;
  // each of those is tried after it and reports through a requester or the fault panel.
  const badSetting = loadSettings();
  screen.setMenus(menus());
  projectWindow();
  about();
  S.ready = true;
  startCompiler();
  if (badSetting !== null) {
    desk.requester(projectWindow(), {
      title: 'Settings',
      lines: [`Your saved scale "${String(badSetting).slice(0, 40)}" can't be used.`, `The Studio is using ${DEFAULT_SCALE}x.`],
      buttons: [{ id: 'use', label: `Use ${DEFAULT_SCALE}x` }, { id: 'ok', label: 'OK' }],
    }).then((pick) => { if (pick === 'use') saveScale(DEFAULT_SCALE); });
  }

  // For tests and embedding hosts: the page's own state and the actions behind its gadgets.
  window.bespokePageState = () => ({ ready: S.ready });
  window.bespokeStudio = {
    version: STUDIO_BUILD.version,
    openDirectory,
    chooseScript,
    check,
    play,
    exportPage,
    newProject,
    newScript,
    openScript: (path, l, c, opts) => Boolean(openScript(path, l || 1, c || 0, opts)),
    // For tests: the script window's text area and gadgets.
    scriptText: (path, text) => { const w = screen.windows.find((x) => x.id === `script:${path}`); return w ? w.scriptText(text) : false; },
    scriptGadget: (path, gid) => { const w = screen.windows.find((x) => x.id === `script:${path}`); if (!w) return false; w.port.post({ kind: 'gadget', id: gid }); return true; },
    scriptState: (path) => { const w = screen.windows.find((x) => x.id === `script:${path}`); return w ? w.scriptState() : null; },
    // Hands raw bytes to the play window as if they were a built package, so a test can show
    // that a package the runtime refuses leaves a working Studio.
    playBytes: (bytes) => player.run(Uint8Array.from(bytes)),
    playKey: (code) => player.key(code),
    playGadget: (id) => player.gadget(id),
    // Raises a trap inside the play window's guard, as a game that fails mid-run would, so a
    // test can show the Studio outlives it and Run starts a fresh module.
    playTrap: (msg) => player.guard(() => { throw new WebAssembly.RuntimeError(msg); }),
    openArt: () => painter.openArt(),
    openImage: (name) => painter.openImage(name),
    // For tests: the New image and Import forms without the browser's file picker.
    newImageForm: () => { painter.openForm(null); return true; },
    openRooms: () => roomer.openRooms().then(() => true),
    openScene: (name) => roomer.openScene(name).then(() => true),
    // For tests: a pointer gesture at art pixels on a scene's room canvas, and its tool.
    roomGesture: (name, points, tool) => { const e = roomer.editor(name); if (!e) return false; if (tool) e.win.port.post({ kind: 'gadget', id: `tool:${tool}` }); setTimeout(() => e.gesture(points), 0); return true; },
    roomGadget: (name, id) => { const e = roomer.editor(name); if (!e) return false; e.win.port.post({ kind: 'gadget', id }); return true; },
    roomSnap: (x, y) => roomer.snap(x, y),
    openCast: () => caster.open().then(() => true),
    castGadget: (id) => caster.gadget(id),
    castField: (id, value) => caster.field(id, value),
    openDilemmas: () => dilemmer.open().then(() => true),
    dilemmaGadget: (id) => dilemmer.gadget(id),
    dilemmaField: (id, value) => dilemmer.field(id, value),
    openDialogue: () => talker.open().then(() => true),
    dialogueClick: (what) => talker.clickRegion(what),
    dialogueGadget: (id) => talker.gadget(id),
    dialogueField: (id, value) => talker.field(id, value),
    importForm: (name, bytes) => { painter.openForm({ name, bytes: Uint8Array.from(bytes) }); return true; },
    // For tests: one click of a tool on a sheet pixel, through the editor's own stroke path.
    paintAt: (name, x, y, tool) => { const e = painter.editor(name); if (!e) return false; e.paintAt(x, y, tool); return true; },
    pixelAt: (name, x, y) => { const e = painter.editor(name); return e ? e.pixel(x, y) : null; },
    save,
    command,
    compilerReady: () => S.compiler.state !== 'loading',
    state: () => ({
      ready: S.ready,
      scale: S.scale,
      compiler: { ...S.compiler },
      project: S.project && {
        name: S.project.name,
        writable: S.project.writable,
        main: S.project.main,
        files: S.project.files.map((f) => ({ path: f.path, size: f.bytes.length, dirty: f.dirty, isNew: Boolean(f.isNew) })),
        skipped: S.project.skipped.slice(),
      },
      result: S.result,
      play: player.state(),
      paint: painter.state(),
      rooms: roomer.state(),
      cast: caster.state(),
      dilemmas: dilemmer.state(),
      dialogue: talker.state(),
      faults: S.faults.slice(),
      windows: screen.windows.map((w) => w.id),
      requester: (document.querySelector('.req') || { getAttribute: () => null }).getAttribute('aria-label'),
      fault: Boolean(document.querySelector('.fault')),
    }),
  };
}());
