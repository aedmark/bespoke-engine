// BeSpoke Studio, the dialogue map (P47-04, D-204): the Dialogue window lists every
// conversation with choices (a cue handler, a routine, or the top level) and draws one as a
// tree, top-down: a box holds what is said, and an arrow per choice leads to what follows, with
// the choice's text and guard on it. A guard whose relation nothing in the script writes is
// marked (the compiler warns about the same choices). A click on a box or an arrow opens the
// script view at that line.
//
// A `dialogue` block (P47-15, D-206) can be edited (P47-14): a form of its lines, each with
// its nesting depth and indent and outdent buttons, beside the map, which redraws from what is
// typed through the Studio module's preview. Apply rewrites the block whole, checked with the
// compiler before it is kept; New dialogue starts from a template. Handlers and routines stay
// read-only (D-202).
'use strict';

// eslint-disable-next-line no-unused-vars
function createTalk(desk, screen, hooks) {
  const BOX_W = 220;
  const LINE_H = 14;
  const PAD = 6;
  const GAP_X = 24;
  const GAP_Y = 54;
  const T = { listing: null, index: 0, zoom: 1, edit: null, preview: null, error: '', commentsOk: false };
  let win = null;
  let regions = [];

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

  // The node list as a tree: a box holds the says at one depth, and each choice leads to the
  // box of what follows it.
  function treeOf(nodes) {
    let i = 0;
    function box(depth, line) {
      const b = { says: [], choices: [], line };
      while (i < nodes.length && nodes[i].depth >= depth) {
        const n = nodes[i];
        if (n.depth > depth) { i += 1; continue; }
        i += 1;
        if (!n.choice) b.says.push(n);
        else b.choices.push({ node: n, child: box(depth + 1, n.line) });
      }
      return b;
    }
    return box(0, nodes.length ? nodes[0].line : 0);
  }

  // Top-down layout: leaves side by side, each parent centred over its children.
  function layout(root) {
    let next = 0;
    function place(b, depth) {
      b.depth = depth;
      b.h = PAD * 2 + Math.max(1, b.says.length) * LINE_H;
      if (!b.choices.length) { b.x = next; next += BOX_W + GAP_X; return; }
      for (const c of b.choices) place(c.child, depth + 1);
      const first = b.choices[0].child.x;
      const last = b.choices[b.choices.length - 1].child.x;
      b.x = (first + last) / 2;
    }
    place(root, 0);
    const rows = [];
    (function heights(b) {
      rows[b.depth] = Math.max(rows[b.depth] || 0, b.h);
      for (const c of b.choices) heights(c.child);
    }(root));
    const tops = [];
    let y = 8;
    rows.forEach((h, d) => { tops[d] = y; y += h + GAP_Y; });
    (function tops_of(b) {
      b.y = tops[b.depth];
      for (const c of b.choices) tops_of(c.child);
    }(root));
    return { width: Math.max(next, BOX_W + GAP_X) + 8, height: y };
  }

  function clip(ctx, text, width) {
    if (ctx.measureText(text).width <= width) return text;
    let t = text;
    while (t.length > 1 && ctx.measureText(`${t}...`).width > width) t = t.slice(0, -1);
    return `${t}...`;
  }

  function draw(canvas, conv) {
    const nodes = T.edit ? ((T.preview && T.preview.nodes) || []) : conv.nodes;
    const root = treeOf(nodes);
    const size = layout(root);
    const z = T.zoom;
    canvas.width = Math.ceil((size.width + 8) * z);
    canvas.height = Math.ceil(size.height * z);
    const ctx = canvas.getContext('2d');
    ctx.setTransform(z, 0, 0, z, 0, 0);
    ctx.fillStyle = '#f4f0e4';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.font = '11px monospace';
    ctx.textBaseline = 'top';
    regions = [];
    (function paint(b) {
      const x = b.x + 4;
      // The box: what is said here, or a quiet mark when nothing is.
      ctx.fillStyle = '#a9a398';
      ctx.fillRect(x, b.y, BOX_W, b.h);
      ctx.strokeStyle = '#1c1b1f';
      ctx.strokeRect(x + 0.5, b.y + 0.5, BOX_W - 1, b.h - 1);
      ctx.fillStyle = '#1c1b1f';
      if (!b.says.length) ctx.fillText('(nothing said)', x + PAD, b.y + PAD);
      b.says.forEach((s, k) => {
        ctx.fillText(clip(ctx, `${s.speaker}: "${s.text}"`, BOX_W - PAD * 2), x + PAD, b.y + PAD + k * LINE_H);
        regions.push({ x, y: b.y + PAD + k * LINE_H, w: BOX_W, h: LINE_H, line: s.line, what: `say ${s.text}` });
      });
      for (const c of b.choices) {
        const cx = c.child.x + 4 + BOX_W / 2;
        const top = c.child.y;
        // The arrow, and the choice on it.
        ctx.strokeStyle = c.node.never === 1 ? '#d0602a' : '#1c1b1f';
        ctx.setLineDash(c.node.never === 1 ? [4, 3] : []);
        ctx.beginPath();
        ctx.moveTo(x + BOX_W / 2, b.y + b.h);
        ctx.lineTo(cx, top - 2);
        ctx.stroke();
        ctx.setLineDash([]);
        ctx.beginPath();
        ctx.moveTo(cx - 4, top - 7);
        ctx.lineTo(cx, top - 1);
        ctx.lineTo(cx + 4, top - 7);
        ctx.stroke();
        const label = clip(ctx, `"${c.node.text}"`, BOX_W);
        const guard = c.node.guard ? clip(ctx, `if ${c.node.guard}${c.node.never === 1 ? ' (never)' : c.node.never === 2 ? ' (always)' : ''}`, BOX_W) : '';
        const ly = top - (guard ? 34 : 20);
        ctx.fillStyle = '#3a6690';
        ctx.fillText(label, c.child.x + 4, ly);
        if (guard) {
          ctx.fillStyle = c.node.never ? '#d0602a' : '#1c1b1f';
          ctx.fillText(guard, c.child.x + 4, ly + LINE_H);
        }
        regions.push({ x: c.child.x + 4, y: ly, w: BOX_W, h: guard ? LINE_H * 2 : LINE_H, line: c.node.line, what: `choice ${c.node.text}` });
        paint(c.child);
      }
    }(root));
  }

  async function open() {
    if (!await hooks.ready('Dialogue')) return null;
    const r = hooks.listDialogue();
    if (r && !r.valid) { await hooks.showResult(r); return null; }
    T.listing = r;
    if (T.index >= T.listing.conversations.length) T.index = 0;
    if (!win) {
      const a = screen.area.getBoundingClientRect();
      win = desk.window(screen, {
        id: 'dialogue', title: 'Dialogue', x: Math.max(0, Math.min(100, a.width - 680)), y: 28, w: Math.min(680, a.width), h: Math.min(560, a.height - 28), minW: 220, minH: 200,
        onMessage: async (msg) => {
          if (msg.kind === 'close') { win.close(); win = null; T.edit = null; return; }
          if (msg.kind === 'resize') { render(); return; }
          if (msg.kind !== 'gadget') return;
          if (msg.id.startsWith('conv:')) { T.index = Number(msg.id.slice(5)); render(); return; }
          if (msg.id === 'zoom-in') { T.zoom = Math.min(3, T.zoom + 0.5); render(); return; }
          if (msg.id === 'zoom-out') { T.zoom = Math.max(0.5, T.zoom - 0.5); render(); return; }
          await editMessage(msg.id);
        },
      });
    }
    render();
    win.toFront();
    win.activate();
    return win;
  }

  function render() {
    if (!win) return;
    const out = [];
    const L = T.listing;
    if (!L) { out.push(line('No listing: the main script did not check.')); win.body.replaceChildren(...out); return; }
    if (!L.conversations.length && !T.edit) {
      out.push(line(fit('This script has no choices or dialogues.', cols())));
      out.push(editRow());
      win.body.replaceChildren(...out);
      return;
    }
    const list = document.createElement('div');
    list.className = 'list cast-list';
    L.conversations.forEach((c, i) => {
      const never = c.nodes.filter((n) => n.never).length;
      const b = desk.button(win, `conv:${i}`, fit(`${c.title} (${c.script}:${c.line})${never ? `, ${never} guard(s) never change` : ''}`, cols() - 2), { cls: `item ${never ? 'err' : ''}` });
      if (i === T.index) b.classList.add('selected');
      list.appendChild(b);
    });
    const zoom = document.createElement('div');
    zoom.className = 'row';
    zoom.append(desk.button(win, 'zoom-out', 'Zoom -'), desk.button(win, 'zoom-in', 'Zoom +'));
    const view = document.createElement('div');
    view.className = 'paint-view';
    const canvas = document.createElement('canvas');
    canvas.className = 'talk-canvas';
    canvas.setAttribute('aria-label', `Dialogue map of ${L.conversations[T.index].title}`);
    view.appendChild(canvas);
    const conv = L.conversations[T.index] || { nodes: [], script: '', title: '' };
    draw(canvas, conv);
    canvas.addEventListener('click', (e) => {
      const r = canvas.getBoundingClientRect();
      const x = (e.clientX - r.left) * (canvas.width / r.width) / T.zoom;
      const y = (e.clientY - r.top) * (canvas.height / r.height) / T.zoom;
      const hit = regions.find((g) => x >= g.x && x < g.x + g.w && y >= g.y && y < g.y + g.h);
      if (hit) hooks.openScript(conv.script, hit.line, 0);
    });
    out.push(list, editRow(), zoom, view);
    if (T.edit) out.push(...editForm());
    else out.push(line(fit('Click a line or a choice to open it in the script.', cols())));
    win.body.replaceChildren(...out);
  }

  // ------------------------------------------------------------ editing (P47-14, D-206)

  function current() {
    return T.listing && T.listing.conversations[T.index];
  }

  function editRow() {
    const r = document.createElement('div');
    r.className = 'row';
    const c = current();
    if (!T.edit && c && c.dialogue) r.appendChild(desk.button(win, 'dlg-edit', `Edit ${c.dialogue}`));
    if (!T.edit) r.appendChild(desk.button(win, 'dlg-new', 'New dialogue'));
    return r;
  }

  const fields = {};
  function field(id, value, label) {
    const el = document.createElement('input');
    el.className = 'strgad';
    el.name = id;
    el.value = value;
    el.autocomplete = 'off';
    el.spellcheck = false;
    el.setAttribute('aria-label', label);
    el.onkeydown = (e) => e.stopPropagation();
    el.oninput = () => schedulePreview();
    fields[id] = el;
    return el;
  }

  function editForm() {
    for (const k of Object.keys(fields)) delete fields[k];
    const out = [];
    const nameWrap = document.createElement('label');
    nameWrap.className = 'line field';
    nameWrap.appendChild(desk.label('Dialogue'));
    nameWrap.appendChild(field('dlg-name', T.edit.name, 'Dialogue name'));
    out.push(nameWrap);
    const scroll = document.createElement('div');
    scroll.className = 'cast-scroll';
    T.edit.lines.forEach((l, i) => {
      const r = document.createElement('div');
      r.className = 'row field-row';
      const pad = document.createElement('span');
      pad.className = 'dlg-indent';
      pad.style.setProperty('--depth', l.depth);
      r.append(desk.button(win, `dlg-out:${i}`, '<'), desk.button(win, `dlg-in:${i}`, '>'), pad, field(`dlg-l${i}`, l.text, `Line ${i + 1}`), desk.button(win, `dlg-del:${i}`, 'Remove'));
      scroll.appendChild(r);
    });
    out.push(scroll);
    const r = document.createElement('div');
    r.className = 'row';
    r.append(desk.button(win, 'dlg-add', 'Add line'), desk.button(win, 'dlg-apply', 'Apply'), desk.button(win, 'dlg-cancel', 'Close editor'));
    out.push(r);
    if (T.error) out.push(line(fit(T.error, cols()), 'err'));
    return out;
  }

  function readLines() {
    if (!T.edit) return [];
    return T.edit.lines.map((l, i) => ({ depth: l.depth, text: fields[`dlg-l${i}`] ? fields[`dlg-l${i}`].value : l.text }));
  }

  function records() {
    const name = fields['dlg-name'] ? fields['dlg-name'].value.trim() : T.edit.name;
    return [`dialogue\t${name}`, ...readLines().map((l) => `line\t${l.depth}\t${l.text}`)].join('\n');
  }

  let previewTimer = 0;
  function schedulePreview() {
    clearTimeout(previewTimer);
    previewTimer = setTimeout(() => { runPreview(); redrawMap(); }, 150);
  }

  function runPreview() {
    if (!T.edit) return;
    const r = hooks.previewDialogue(records());
    T.preview = r && r.nodes ? r : T.preview;
    T.error = r && r.error ? `Line ${Math.max(1, r.line - 1)}: ${r.error}` : (r && r.refused ? r.refused : '');
  }

  // Redraws only the map and the error line, so the field being typed in keeps its focus.
  function redrawMap() {
    const canvas = win && win.body.querySelector('canvas');
    if (!canvas) return;
    draw(canvas, current() || { nodes: [] });
    const err = win.body.querySelector('.dlg-error');
    if (err) err.remove();
    if (T.error) {
      const e = line(fit(T.error, cols()), 'err dlg-error');
      win.body.appendChild(e);
    }
  }

  function startEdit(name, lines) {
    T.edit = { name, lines: lines.map((l) => ({ ...l })) };
    T.error = '';
    T.commentsOk = false;
    runPreview();
    render();
  }

  async function editMessage(id) {
    if (id === 'dlg-edit') {
      const c = current();
      if (c && c.dialogue) startEdit(c.dialogue, c.lines || []);
      return;
    }
    if (id === 'dlg-new') {
      const speaker = hooks.firstCast() || 'Someone';
      startEdit('NewDialogue', [
        { depth: 0, text: `speaker ${speaker}` },
        { depth: 0, text: 'say "Hello."' },
        { depth: 0, text: 'choice "Goodbye.":' },
        { depth: 1, text: 'say "Farewell."' },
      ]);
      return;
    }
    if (!T.edit) return;
    T.edit.lines = readLines();
    T.edit.name = fields['dlg-name'] ? fields['dlg-name'].value.trim() : T.edit.name;
    const at = (prefix) => Number(id.slice(prefix.length));
    if (id === 'dlg-cancel') { T.edit = null; T.preview = null; T.error = ''; render(); return; }
    if (id === 'dlg-add') { T.edit.lines.push({ depth: T.edit.lines.length ? T.edit.lines[T.edit.lines.length - 1].depth : 0, text: '' }); render(); const el = fields[`dlg-l${T.edit.lines.length - 1}`]; if (el) el.focus(); return; }
    if (id.startsWith('dlg-del:')) { T.edit.lines.splice(at('dlg-del:'), 1); runPreview(); render(); return; }
    if (id.startsWith('dlg-in:')) { const i = at('dlg-in:'); const max = i === 0 ? 0 : T.edit.lines[i - 1].depth + 1; T.edit.lines[i].depth = Math.min(max, T.edit.lines[i].depth + 1); runPreview(); render(); return; }
    if (id.startsWith('dlg-out:')) { const i = at('dlg-out:'); T.edit.lines[i].depth = Math.max(0, T.edit.lines[i].depth - 1); runPreview(); render(); return; }
    if (id === 'dlg-apply') {
      const c = T.listing && T.listing.conversations.find((x) => x.dialogue === T.edit.name);
      if (c && c.block && c.block.comments && !T.commentsOk) {
        const pick = await desk.requester(win, {
          title: 'Dialogue', lines: [`The block for ${T.edit.name} has comments.`, 'Apply rewrites the block whole, so they will be lost.'],
          buttons: [{ id: 'rewrite', label: 'Rewrite' }, { id: 'cancel', label: 'Cancel' }],
        });
        if (pick !== 'rewrite') return;
        T.commentsOk = true;
      }
      const r = hooks.writeDialogue(records());
      if (!r) return;
      if (!r.written) {
        T.error = r.refused || (r.result && r.result.message) || 'the edit was refused';
        render();
        if (r.refused) await desk.requester(win, { title: 'Dialogue', tone: 'fault', lines: ['Nothing was written:', r.refused] });
        else await hooks.showResult(r.result);
        return;
      }
      const name = T.edit.name;
      T.listing = hooks.listDialogue();
      const i = T.listing.conversations.findIndex((x) => x.dialogue === name);
      if (i >= 0) T.index = i;
      const c2 = current();
      startEdit(name, (c2 && c2.lines) || T.edit.lines);
    }
  }

  function reset() {
    T.listing = null;
    T.index = 0;
    T.edit = null;
    T.preview = null;
    T.error = '';
    if (win) render();
  }

  async function relist() {
    if (!win) return;
    const r = hooks.listDialogue();
    T.listing = r && r.valid ? r : null;
    render();
  }

  return {
    open,
    reset,
    relist,
    state: () => ({ open: Boolean(win), index: T.index, conversations: T.listing ? T.listing.conversations : [], regions: regions.map((g) => ({ what: g.what, line: g.line, x: g.x, y: g.y, w: g.w, h: g.h })), edit: T.edit && { name: T.edit.name, lines: readLines() }, preview: T.preview, error: T.error }),
    gadget: (id) => { if (win) win.port.post({ kind: 'gadget', id }); return Boolean(win); },
    field: (id, value) => { const el = fields[id]; if (!el) return false; el.value = value; el.dispatchEvent(new Event('input')); return true; },
    // For tests: a click on a region of the drawn map, in map units.
    clickRegion: (what) => {
      const g = regions.find((x) => x.what === what);
      const canvas = win && win.body.querySelector('canvas');
      if (!g || !canvas) return false;
      const r = canvas.getBoundingClientRect();
      const px = (g.x + 2) * T.zoom * (r.width / canvas.width);
      const py = (g.y + 2) * T.zoom * (r.height / canvas.height);
      canvas.dispatchEvent(new MouseEvent('click', { bubbles: true, clientX: r.left + px, clientY: r.top + py }));
      return true;
    },
  };
}
