// BeSpoke Studio, P47-01 (D-151, D-192): the workspace screen, a project window that opens a
// folder or files, checks a script with the engine's compiler, and shows its diagnostics in
// place; and the play window (P47-06, D-195, play.js), which runs the built game in a module of
// its own. No editors yet. The Studio keeps no project state of its own (D-151 item 6): files are
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
    acc.files.push({ path, bytes, dirty: false, ...extra });
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

  async function finishOpen(meta, acc) {
    S.project = { ...meta, files: acc.files, skipped: acc.skipped, main: chooseMain(acc.files) };
    S.result = null;
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
    return true;
  }

  async function openFolder() {
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
    return player.run(built.pkg);
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

  // Writes only files an editor changed. P47-01 has no editors, so nothing is ever dirty; Save
  // still compares every opened file with the disk, so an author learns when another program
  // changed a file underneath the Studio before any editor could overwrite it.
  async function save() {
    const win = projectWindow();
    const p = S.project;
    if (!p) { await desk.requester(win, { title: 'Save', lines: ['No project is open.'] }); return { written: 0, changed: [] }; }
    const dirty = p.files.filter((f) => f.dirty);
    if (dirty.length) throw new Error('an edited file has no writer yet');
    const changed = [];
    if (p.writable) {
      for (const f of p.files) {
        if (!f.handle) continue;
        try {
          const disk = new Uint8Array(await (await f.handle.getFile()).arrayBuffer());
          if (!sameBytes(disk, f.bytes)) changed.push(f.path);
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
      if (pick === 'reload' && p.handle) await openDirectory(p.handle);
    } else {
      const lines = [`Nothing to save: ${p.files.length} file(s) are unchanged.`];
      if (!p.writable) lines.push('This browser opened the folder read-only, so the Studio could not write to it anyway.');
      await desk.requester(win, { title: 'Save', lines });
    }
    return { written: 0, changed };
  }

  function sameBytes(a, b) {
    if (a.length !== b.length) return false;
    for (let i = 0; i < a.length; i += 1) if (a[i] !== b[i]) return false;
    return true;
  }

  // ------------------------------------------------------------ windows

  const screen = desk.screen(`BeSpoke Studio ${STUDIO_BUILD.version}`);
  let projectWin = null;
  const player = createPlay(desk, screen, { build: () => play(), reportFault });

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
        if (msg.id.startsWith('main:')) { S.project.main = msg.id.slice(5); S.result = null; renderProject(); await check(); return; }
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
      out.push(buttons(win, [['check', 'Check'], ['play', 'Play'], ['save', 'Save'], ['open-folder', 'Open folder']]));
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
  function openScript(path, lineNo, column) {
    const f = findFile(path);
    if (!f) { desk.requester(projectWindow(), { title: 'Show line', lines: [`${path} is not in the opened project.`] }); return null; }
    const id = `script:${path}`;
    let win = screen.windows.find((w) => w.id === id);
    if (!win) {
      let text = new TextDecoder('utf-8').decode(f.bytes);
      if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
      const lines = text.split(/\r\n|\n|\r/).map((l) => l.replace(/\t/g, '  '));
      const a = screen.area.getBoundingClientRect();
      const view = document.createElement('div');
      view.className = 'view';
      const rows = document.createElement('div');
      rows.className = 'rows';
      const state = { lines, mark: lineNo, column, top: 0 };
      const prop = desk.propGadget((top) => { state.top = top; draw(); });
      view.append(rows, prop.el);
      function visible() {
        return Math.max(1, Math.floor(rows.getBoundingClientRect().height / (9 * desk.px())));
      }
      function draw() {
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
      rows.addEventListener('wheel', (e) => { e.preventDefault(); prop.moveTo(state.top + Math.sign(e.deltaY) * 3); }, { passive: false });
      win = desk.window(screen, {
        id, title: path, x: Math.min(120, a.width * 0.1), y: 90, w: Math.min(640, a.width), h: Math.min(320, a.height - 90), minW: 160, minH: 90,
        onMessage: (msg) => {
          if (msg.kind === 'close') win.close();
          if (msg.kind === 'resize') draw();
          if (msg.kind === 'goto') { state.mark = msg.line; state.column = msg.column; state.top = Math.max(0, msg.line - 1 - Math.floor(visible() / 2)); draw(); }
        },
      });
      win.body.appendChild(view);
    }
    win.toFront();
    win.activate();
    win.port.post({ kind: 'goto', line: lineNo, column });
    return win;
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
      'Open a project folder to check its scripts, then Play to run the game.',
      menuHint(),
      'Drag the screen down by its title bar.',
    ];
    if (!S.storage) lines.push('This browser will not keep settings.');
    const out = [];
    for (const l of lines) for (const part of desk.wrapText(l, n)) out.push(line(part));
    out.push(buttons(aboutWin, [['open-folder', 'Open folder'], ['about-ok', 'OK']]));
    aboutWin.body.replaceChildren(...out);
    return aboutWin;
  }

  // ------------------------------------------------------------ menus and keys

  function menus() {
    const scale = (n) => ({ id: `scale-${n}`, label: `${S.scale === n ? '* ' : '  '}${n}x`, checked: S.scale === n });
    return [
      {
        title: 'Project',
        items: [
          { id: 'open-folder', label: 'Open folder...', key: 'O' },
          { id: 'open-files', label: 'Open files...' },
          { id: 'check', label: 'Check script', key: 'K' },
          { id: 'play', label: 'Play game', key: 'G' },
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
        ],
      },
      { title: 'Settings', items: [scale(1), scale(2), scale(3)] },
    ];
  }

  async function command(id) {
    switch (id) {
      case 'open-folder': return openFolder();
      case 'open-files': return openFiles();
      case 'check': return check();
      case 'play': return play();
      case 'win-play': return player.open();
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
    check,
    play,
    // Hands raw bytes to the play window as if they were a built package, so a test can show
    // that a package the runtime refuses leaves a working Studio.
    playBytes: (bytes) => player.run(Uint8Array.from(bytes)),
    playKey: (code) => player.key(code),
    // Raises a trap inside the play window's guard, as a game that fails mid-run would, so a
    // test can show the Studio outlives it and Run starts a fresh module.
    playTrap: (msg) => player.guard(() => { throw new WebAssembly.RuntimeError(msg); }),
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
        files: S.project.files.map((f) => ({ path: f.path, size: f.bytes.length })),
        skipped: S.project.skipped.slice(),
      },
      result: S.result,
      play: player.state(),
      faults: S.faults.slice(),
      windows: screen.windows.map((w) => w.id),
      requester: (document.querySelector('.req') || { getAttribute: () => null }).getAttribute('aria-label'),
      fault: Boolean(document.querySelector('.fault')),
    }),
  };
}());
