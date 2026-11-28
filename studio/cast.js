// BeSpoke Studio, the cast editor (P47-05, D-202): the Cast window lists each scene's cast,
// props, and marks with their display names, each character's routines and cue handlers (opened
// in the read-only script view at their line), and the script's value axes with each
// character's starting values. It adds a name to a scene, sets display names, declares axes, and
// sets starting values. Every change is one line written by the Studio module (a new list line
// at the end of a scene's block, a `name` line, an `axis` line, or a top-level `remember` line),
// checked with the compiler, and kept only if it checks. Dilemmas, appeals, and red lines are
// P47-13.
'use strict';

// eslint-disable-next-line no-unused-vars
function createCast(desk, screen, hooks) {
  const UNDO_DEPTH = 32;
  const C = {
    listing: null,
    scene: null, // selected scene name
    member: null, // { name, kind: 'cast' | 'props' | 'marks' }
    axis: null, // selected axis name
    adding: null, // 'cast' | 'props' | 'marks' while the add field shows
    undo: [],
    redo: [],
    error: '',
  };
  let win = null;
  const fields = {};

  function line(text, cls) {
    const row = document.createElement('div');
    row.className = `line ${cls || ''}`.trim();
    row.appendChild(desk.label(text));
    return row;
  }

  function cols() {
    return Math.max(12, Math.floor((win.rect.w - 16 * desk.px()) / (desk.advance * desk.px())));
  }

  function fit(text, n) {
    const chars = [...text];
    return chars.length <= n ? text : `${chars.slice(0, Math.max(1, n - 3)).join('')}...`;
  }

  function input(id, label, value) {
    const wrap = document.createElement('label');
    wrap.className = 'line field';
    wrap.appendChild(desk.label(label));
    const el = fields[id] && fields[id].isConnected ? fields[id] : document.createElement('input');
    el.className = 'strgad';
    el.name = id;
    if (!fields[id] || !fields[id].isConnected) el.value = String(value);
    el.autocomplete = 'off';
    el.spellcheck = false;
    el.setAttribute('aria-label', label);
    el.onkeydown = (e) => e.stopPropagation();
    fields[id] = el;
    wrap.appendChild(el);
    return wrap;
  }

  function list(items) {
    const el = document.createElement('div');
    el.className = 'list cast-list';
    for (const it of items) el.appendChild(it);
    return el;
  }

  function item(id, text, selected) {
    const b = desk.button(win, id, fit(text, cols() - 2), { cls: 'item' });
    if (selected) b.classList.add('selected');
    b.setAttribute('aria-label', text);
    return b;
  }

  function row(pairs) {
    const r = document.createElement('div');
    r.className = 'row';
    for (const [id, text, on = true] of pairs) {
      const b = desk.button(win, id, text);
      if (!on) b.disabled = true;
      r.appendChild(b);
    }
    return r;
  }

  async function refresh() {
    const r = hooks.listCast();
    C.listing = r && r.valid ? r : null;
    if (C.listing && C.scene && !C.listing.scenes.some((s) => s.name === C.scene)) C.scene = null;
    if (!C.scene && C.listing && C.listing.scenes.length) C.scene = C.listing.scenes[0].name;
    return C.listing;
  }

  async function open() {
    if (!await hooks.ready('Cast')) return null;
    const r = hooks.listCast();
    if (r && !r.valid) { await hooks.showResult(r); return null; }
    await refresh();
    if (!win) {
      const a = screen.area.getBoundingClientRect();
      win = desk.window(screen, {
        id: 'cast', title: 'Cast', x: Math.max(0, Math.min(80, a.width - 520)), y: 30, w: Math.min(520, a.width), h: Math.min(600, a.height - 30), minW: 220, minH: 200,
        onMessage: (msg) => handle(msg),
      });
    }
    render();
    win.toFront();
    win.activate();
    return win;
  }

  function displayName(name) {
    const n = C.listing.names.find((x) => x.entity === name);
    return n ? n.text : '';
  }

  function render() {
    if (!win) return;
    const out = [];
    const L = C.listing;
    if (!L) {
      out.push(line(fit('No listing: the main script did not check.', cols())));
      win.body.replaceChildren(...out);
      return;
    }
    out.push(row([['undo', 'Undo', C.undo.length > 0], ['redo', 'Redo', C.redo.length > 0]]));
    const scroll = document.createElement('div');
    scroll.className = 'cast-scroll';
    const parts = [];
    // Scenes.
    parts.push(line('Scenes'));
    parts.push(list(L.scenes.map((s) => item(`scene:${s.name}`, s.name, s.name === C.scene))));
    const sc = L.scenes.find((s) => s.name === C.scene);
    if (sc) {
      const members = [];
      for (const kind of ['cast', 'props', 'marks']) {
        for (const name of sc[kind]) {
          const shown = displayName(name);
          const label = `${{ cast: 'Cast', props: 'Prop', marks: 'Mark' }[kind]}: ${name}${shown ? ` ("${shown}")` : ''}`;
          members.push(item(`member:${kind}\u0000${name}`, label, C.member && C.member.name === name && C.member.kind === kind));
        }
      }
      parts.push(line(fit(`In ${sc.name}`, cols())));
      parts.push(list(members));
      parts.push(row([['add:cast', 'Add cast'], ['add:props', 'Add prop'], ['add:marks', 'Add mark']]));
      if (C.adding) {
        parts.push(input('add-name', `New ${{ cast: 'cast member', props: 'prop', marks: 'mark' }[C.adding]}`, ''));
        parts.push(row([['add-ok', 'Add'], ['add-cancel', 'Cancel']]));
      }
    }
    // The selected member.
    if (C.member) {
      const name = C.member.name;
      parts.push(line(fit(`${name}`, cols())));
      parts.push(input('display', 'Display name', displayName(name)));
      parts.push(row([['set-name', 'Set name']]));
      if (C.member.kind === 'cast') {
        for (const ax of L.axes) {
          const v = L.values.find((x) => x.axis === ax.name && x.character === name);
          parts.push(input(`value:${ax.name}`, ax.name, v ? v.value : ''));
        }
        if (L.axes.length) parts.push(row([['set-values', 'Set values']]));
        const code = L.code.filter((k) => k.actor === name);
        if (code.length) {
          parts.push(line('Routines and handlers'));
          parts.push(list(code.map((k) => item(`code:${L.code.indexOf(k)}`, `${k.handler ? 'on cue' : 'routine'} ${k.name} (${k.at.script}:${k.at.line})`, false))));
        }
      }
    }
    // Axes.
    parts.push(line('Value axes'));
    parts.push(list(L.axes.map((ax) => item(`axis:${ax.name}`, `${ax.name}: ${ax.low} .. ${ax.high}`, ax.name === C.axis))));
    const ax = L.axes.find((x) => x.name === C.axis);
    parts.push(input('axis-name', 'Virtue', ax ? ax.name : ''));
    parts.push(input('axis-low', 'Fails as', ax ? ax.low : ''));
    parts.push(input('axis-high', 'And as', ax ? ax.high : ''));
    parts.push(row([['axis-set', ax ? 'Set poles' : 'Add axis'], ['axis-new', 'Clear']]));
    if (C.error) parts.push(line(fit(C.error, cols()), 'err'));
    scroll.append(...parts);
    out.push(scroll);
    win.body.replaceChildren(...out);
  }

  // Writes one record; a refusal says why and keeps every field as typed.
  async function write(record) {
    const before = hooks.scriptBytes();
    const r = hooks.writeCast(record);
    if (!r) return false;
    if (!r.written) {
      C.error = r.refused || (r.result && r.result.message) || 'the edit was refused';
      render();
      if (r.refused) await desk.requester(win, { title: 'Cast', tone: 'fault', lines: ['Nothing was written:', r.refused] });
      else await hooks.showResult(r.result);
      return false;
    }
    C.error = '';
    for (const path of r.scripts) hooks.scriptWritten(path);
    hooks.castChanged();
    C.undo.push(r.scripts.map((path) => ({ path, bytes: before[path] })));
    if (C.undo.length > UNDO_DEPTH) C.undo.shift();
    C.redo = [];
    return true;
  }

  async function reload() {
    for (const k of Object.keys(fields)) delete fields[k];
    await refresh();
    render();
  }

  async function stepUndo(from, to) {
    const step = from.pop();
    if (!step) return;
    to.push(step.map((s) => ({ path: s.path, bytes: hooks.fileBytes(s.path) })));
    for (const s of step) hooks.setScript(s.path, s.bytes);
    await reload();
  }

  async function handle(msg) {
    if (msg.kind === 'close') { close(); return; }
    if (msg.kind === 'resize') { render(); return; }
    if (msg.kind !== 'gadget') return;
    const id = msg.id;
    const L = C.listing;
    if (id === 'undo') { await stepUndo(C.undo, C.redo); return; }
    if (id === 'redo') { await stepUndo(C.redo, C.undo); return; }
    if (id.startsWith('scene:')) { C.scene = id.slice(6); C.member = null; C.adding = null; await reload(); return; }
    if (id.startsWith('member:')) {
      const [kind, name] = id.slice(7).split('\u0000');
      C.member = { kind, name };
      await reload();
      return;
    }
    if (id.startsWith('add:')) { C.adding = id.slice(4); render(); if (fields['add-name']) fields['add-name'].focus(); return; }
    if (id === 'add-cancel') { C.adding = null; render(); return; }
    if (id === 'add-ok') {
      const name = fields['add-name'].value.trim();
      if (!name) return;
      if (await write(`add\t${C.scene}\t${C.adding}\t${name}`)) {
        C.member = { kind: C.adding, name };
        C.adding = null;
        await reload();
      }
      return;
    }
    if (id === 'set-name') {
      if (await write(`name\t${C.member.name}\t${fields.display.value.trim()}`)) await reload();
      return;
    }
    if (id === 'set-values') {
      // One checked line per changed value, in axis order; the first refusal stops the rest.
      for (const ax of L.axes) {
        const el = fields[`value:${ax.name}`];
        if (!el) continue;
        const typed = el.value.trim();
        const was = L.values.find((x) => x.axis === ax.name && x.character === C.member.name);
        if (typed === '' || (was && String(was.value) === typed)) continue;
        if (!await write(`value\t${ax.name}\t${C.member.name}\t${typed}`)) return;
      }
      await reload();
      return;
    }
    if (id.startsWith('code:')) {
      const k = L.code[Number(id.slice(5))];
      if (k) hooks.openScript(k.at.script, k.at.line, 0);
      return;
    }
    if (id.startsWith('axis:')) { C.axis = id.slice(5); await reload(); return; }
    if (id === 'axis-new') { C.axis = null; await reload(); return; }
    if (id === 'axis-set') {
      const name = fields['axis-name'].value.trim();
      if (await write(`axis\t${name}\t${fields['axis-low'].value.trim()}\t${fields['axis-high'].value.trim()}`)) {
        C.axis = name;
        await reload();
      }
    }
  }

  function close() {
    if (win) win.close();
    win = null;
  }

  // As a new project opens or another main script is chosen: the window lists the new script.
  function reset() {
    C.listing = null;
    C.scene = null;
    C.member = null;
    C.axis = null;
    C.adding = null;
    C.undo = [];
    C.redo = [];
    for (const k of Object.keys(fields)) delete fields[k];
    if (win) render();
  }

  async function relist() {
    if (!win) return;
    await refresh();
    render();
  }

  return {
    open,
    reset,
    relist,
    state: () => ({
      open: Boolean(win), scene: C.scene, member: C.member, axis: C.axis, error: C.error, undo: C.undo.length,
      listing: C.listing && { scenes: C.listing.scenes, names: C.listing.names, axes: C.listing.axes, values: C.listing.values, code: C.listing.code },
    }),
    gadget: (id) => { if (win) win.port.post({ kind: 'gadget', id }); return Boolean(win); },
    field: (id, value) => { const el = fields[id]; if (!el) return false; el.value = value; return true; },
  };
}
