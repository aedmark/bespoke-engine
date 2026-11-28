// BeSpoke Studio, the dialogue map (P47-04, D-204): the Dialogue window lists every
// conversation with choices (a cue handler, a routine, or the top level) and draws one as a
// tree, top-down: a box holds what is said, and an arrow per choice leads to what follows, with
// the choice's text and guard on it. A guard whose relation nothing in the script writes is
// marked (the compiler warns about the same choices). It is read-only: a click on a box or an
// arrow opens the script view at that line. Writing dialogue is P47-14.
'use strict';

// eslint-disable-next-line no-unused-vars
function createTalk(desk, screen, hooks) {
  const BOX_W = 220;
  const LINE_H = 14;
  const PAD = 6;
  const GAP_X = 24;
  const GAP_Y = 54;
  const T = { listing: null, index: 0, zoom: 1 };
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
    const root = treeOf(conv.nodes);
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
        onMessage: (msg) => {
          if (msg.kind === 'close') { win.close(); win = null; return; }
          if (msg.kind === 'resize') { render(); return; }
          if (msg.kind !== 'gadget') return;
          if (msg.id.startsWith('conv:')) { T.index = Number(msg.id.slice(5)); render(); return; }
          if (msg.id === 'zoom-in') { T.zoom = Math.min(3, T.zoom + 0.5); render(); return; }
          if (msg.id === 'zoom-out') { T.zoom = Math.max(0.5, T.zoom - 0.5); render(); }
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
    if (!L.conversations.length) { out.push(line(fit('This script has no choices.', cols()))); win.body.replaceChildren(...out); return; }
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
    const conv = L.conversations[T.index];
    draw(canvas, conv);
    canvas.addEventListener('click', (e) => {
      const r = canvas.getBoundingClientRect();
      const x = (e.clientX - r.left) * (canvas.width / r.width) / T.zoom;
      const y = (e.clientY - r.top) * (canvas.height / r.height) / T.zoom;
      const hit = regions.find((g) => x >= g.x && x < g.x + g.w && y >= g.y && y < g.y + g.h);
      if (hit) hooks.openScript(conv.script, hit.line, 0);
    });
    out.push(list, zoom, view, line(fit('Click a line or a choice to open it in the script.', cols())));
    win.body.replaceChildren(...out);
  }

  function reset() {
    T.listing = null;
    T.index = 0;
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
    state: () => ({ open: Boolean(win), index: T.index, conversations: T.listing ? T.listing.conversations : [], regions: regions.map((g) => ({ what: g.what, line: g.line, x: g.x, y: g.y, w: g.w, h: g.h })) }),
    gadget: (id) => { if (win) win.port.post({ kind: 'gadget', id }); return Boolean(win); },
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
