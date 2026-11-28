// BeSpoke Studio, the room editor (P47-03, D-198, D-199, D-200): the Rooms window lists the
// scenes the main script declares, and a Room window lays one out over its backdrop: move marks
// and props, draw a prop's area, join marks with walkways, and set exits. Each change is
// written by the Studio module as that scene's whole room block (rewritten in place, or added
// after its `scene` block), checked with the compiler, and kept only if it checks. The grid and
// the backdrop are shown, not edited (D-200 items 3 and 4).
//
// Marks are drawn where the engine draws them: a position snaps to the nearest world unit
// (`spatial.art_to_world`) and back to the art (`spatial.world_to_art`). The two functions below
// repeat that arithmetic for live dragging; the module's listing gives the snapped spot of
// every saved position, and the smoke test checks the two agree.
'use strict';

// eslint-disable-next-line no-unused-vars
function createRooms(desk, screen, hooks) {
  const ART_W = 320;
  const ART_H = 180;
  const ZOOMS = [1, 2, 3, 4];
  const UNDO_DEPTH = 32;
  const HIT = 6; // art pixels around a mark or prop that pick it

  // src/spatial.zig: frame (280 + 18 wx, 380 + 12 wy) at 1280x720, art drawn 4x.
  function roundDiv(a, b) {
    return a >= 0 ? Math.trunc((a + Math.trunc(b / 2)) / b) : -Math.trunc((-a + Math.trunc(b / 2)) / b);
  }
  function artToWorld(x, y) {
    return { x: roundDiv(x * 4 + 2 - 280, 18), y: roundDiv(y * 4 + 2 - 380, 12) };
  }
  function worldToArt(w) {
    const clamp = (v, hi) => Math.max(0, Math.min(hi, v));
    return { x: clamp(Math.floor((280 + 18 * w.x - 2) / 4), ART_W - 1), y: clamp(Math.floor((380 + 12 * w.y - 2) / 4), ART_H - 1) };
  }
  function snap(x, y) {
    return worldToArt(artToWorld(x, y));
  }

  let listing = null;
  let listWin = null;
  const editors = new Map();

  function errText(err) {
    return String((err && err.message) || err || 'unknown error').slice(0, 200);
  }

  function line(text, cls) {
    const row = document.createElement('div');
    row.className = `line ${cls || ''}`.trim();
    row.appendChild(desk.label(text));
    return row;
  }

  function cols(win) {
    return Math.max(12, Math.floor((win.rect.w - 16 * desk.px()) / (desk.advance * desk.px())));
  }

  function fit(text, n) {
    const chars = [...text];
    return chars.length <= n ? text : `${chars.slice(0, Math.max(1, n - 3)).join('')}...`;
  }

  async function refresh() {
    const r = hooks.listRooms();
    if (!r) return null;
    if (!r.valid) {
      listing = null;
      await hooks.showResult(r);
      return null;
    }
    listing = r;
    return r;
  }

  // ------------------------------------------------------------ the scene list

  async function openRooms() {
    if (!await hooks.ready('Rooms')) return null;
    if (!await refresh()) return null;
    if (!listWin) {
      const a = screen.area.getBoundingClientRect();
      listWin = desk.window(screen, {
        id: 'rooms', title: 'Rooms', x: 32, y: Math.min(140, a.height * 0.25), w: Math.min(380, a.width), h: Math.min(240, a.height - 40), minW: 200, minH: 110,
        onMessage: async (msg) => {
          if (msg.kind === 'close') { listWin.close(); listWin = null; return; }
          if (msg.kind === 'resize') { renderList(); return; }
          if (msg.kind === 'gadget' && msg.id.startsWith('scene:')) await openScene(msg.id.slice(6));
        },
      });
    }
    renderList();
    listWin.toFront();
    listWin.activate();
    return listWin;
  }

  function renderList() {
    if (!listWin) return;
    const n = cols(listWin);
    const out = [];
    if (!listing) out.push(line(fit('No listing: the main script did not check.', n)));
    else if (!listing.scenes.length) out.push(line(fit(`${hooks.mainScript()} declares no scenes with scene <Name>:.`, n)));
    else {
      const el = document.createElement('div');
      el.className = 'list';
      for (const sc of listing.scenes) {
        const how = sc.block ? `room block in ${sc.block.script}` : 'default layout';
        el.appendChild(desk.button(listWin, `scene:${sc.name}`, fit(`${sc.name}: ${how}`, n - 2), { cls: 'item' }));
      }
      out.push(el);
    }
    listWin.body.replaceChildren(...out);
  }

  // ------------------------------------------------------------ one scene

  function sceneNamed(name) {
    return listing && listing.scenes.find((s) => s.name === name);
  }

  async function openScene(name) {
    if (!listing && !await refresh()) return null;
    let ed = editors.get(name);
    if (ed) { ed.win.toFront(); ed.win.activate(); return ed.win; }
    const sc = sceneNamed(name);
    if (!sc) { await desk.requester(listWin || hooks.home(), { title: 'Rooms', lines: [`The script declares no scene "${name}".`] }); return null; }
    ed = makeEditor(sc);
    editors.set(name, ed);
    return ed.win;
  }

  function modelOf(sc) {
    return {
      places: sc.places.map((p) => ({ name: p.name, prop: p.prop, x: p.x, y: p.y })),
      areas: sc.areas.map((a) => ({ ...a })),
      walkways: sc.walkways.map(([a, b]) => [a, b]),
      exits: sc.exits.map((e) => ({ ...e })),
      chained: sc.chained,
    };
  }

  // The default chain as explicit walkways, so a first walkway edit keeps what was joined.
  function chainOf(model) {
    const marks = model.places.filter((p) => !p.prop).map((p) => p.name);
    const out = [];
    for (let i = 1; i < marks.length; i += 1) out.push([marks[i - 1], marks[i]]);
    return out;
  }

  // The edit records the module writes as the block (studio/project.zig, `RoomEdit`).
  function recordsOf(name, model) {
    const out = [`scene\t${name}`];
    for (const p of model.places.filter((q) => !q.prop)) out.push(`mark\t${p.name}\t${p.x}\t${p.y}`);
    for (const p of model.places.filter((q) => q.prop)) out.push(`prop\t${p.name}\t${p.x}\t${p.y}`);
    for (const a of model.areas.filter((q) => q.in_block)) out.push(`area\t${a.prop}\t${a.x}\t${a.y}\t${a.w}\t${a.h}`);
    if (!model.chained) for (const [a, b] of model.walkways) out.push(`walkway\t${a}\t${b}`);
    for (const e of model.exits) out.push(`exit\t${e.mark}\t${e.to_scene}\t${e.to_mark}`);
    return `${out.join('\n')}\n`;
  }

  function makeEditor(sc) {
    const E = {
      name: sc.name,
      scene: sc,
      model: modelOf(sc),
      tool: 'move',
      zoom: 2,
      selected: null, // { name, prop }
      drag: null,
      undo: [], // { path, bytes } script states to go back to
      redo: [],
      commentsOk: false,
      backdrop: null, // ImageData of the backdrop, or null
      error: '',
    };

    const canvas = document.createElement('canvas');
    canvas.className = 'room-canvas';
    canvas.width = ART_W;
    canvas.height = ART_H;
    canvas.setAttribute('aria-label', `${sc.name} layout`);
    const ctx = canvas.getContext('2d');
    const view = document.createElement('div');
    view.className = 'paint-view';
    view.appendChild(canvas);
    const back = document.createElement('canvas');
    back.width = ART_W;
    back.height = ART_H;
    const bctx = back.getContext('2d');

    function loadBackdrop() {
      E.backdrop = null;
      if (!E.scene.backdrop) return;
      const art = hooks.listArt();
      const img = art && art.valid && art.images.find((i) => i.name === E.scene.backdrop);
      if (!img || !img.file) return;
      const px = hooks.readPixels(img.file);
      if (!px || px.width !== ART_W || px.height !== ART_H) return;
      bctx.putImageData(new ImageData(px.rgba, ART_W, ART_H), 0, 0);
      E.backdrop = true;
    }

    function placeOf(name, prop) {
      return E.model.places.find((p) => p.name === name && p.prop === prop);
    }

    function drawnOf(p) {
      return snap(p.x, p.y);
    }

    function draw() {
      const z = E.zoom;
      const W = ART_W * z;
      const H = ART_H * z;
      if (canvas.width !== W || canvas.height !== H) { canvas.width = W; canvas.height = H; }
      ctx.imageSmoothingEnabled = false;
      if (E.backdrop) ctx.drawImage(back, 0, 0, W, H);
      else { ctx.fillStyle = '#1c2028'; ctx.fillRect(0, 0, W, H); }
      // Grid cells, read-only (D-200 item 3): world rectangles mapped onto the art.
      for (const g of E.scene.grids) {
        for (const r of g.rects) {
          const a = worldToArt({ x: g.origin_x + r.x * g.cell, y: g.origin_y + r.y * g.cell });
          const b = worldToArt({ x: g.origin_x + (r.x + r.width) * g.cell, y: g.origin_y + (r.y + r.height) * g.cell });
          ctx.fillStyle = { blocking: 'rgba(28,27,31,0.35)', liquid: 'rgba(58,102,144,0.35)', flammable: 'rgba(208,96,42,0.3)', burning: 'rgba(208,96,42,0.6)', smoke: 'rgba(169,163,152,0.5)' }[r.attribute] || 'rgba(244,240,228,0.25)';
          ctx.fillRect(a.x * z, a.y * z, Math.max(1, b.x - a.x) * z, Math.max(1, b.y - a.y) * z);
        }
      }
      // Areas: in the block solid, at top level dashed (edited where they are written).
      for (const a of E.model.areas) {
        ctx.strokeStyle = '#f4f0e4';
        ctx.lineWidth = 1;
        ctx.setLineDash(a.in_block ? [] : [3, 3]);
        ctx.strokeRect(a.x * z + 0.5, a.y * z + 0.5, a.w * z - 1, a.h * z - 1);
      }
      ctx.setLineDash([]);
      // Walkways.
      const marks = E.model.places.filter((p) => !p.prop);
      const links = E.model.chained ? chainOf(E.model) : E.model.walkways;
      ctx.strokeStyle = E.model.chained ? 'rgba(244,240,228,0.45)' : '#f4f0e4';
      ctx.lineWidth = Math.max(1, z);
      for (const [a, b] of links) {
        const pa = placeOf(a, false);
        const pb = placeOf(b, false);
        if (!pa || !pb) continue;
        const da = drawnOf(pa);
        const db = drawnOf(pb);
        ctx.beginPath();
        ctx.moveTo((da.x + 0.5) * z, (da.y + 0.5) * z);
        ctx.lineTo((db.x + 0.5) * z, (db.y + 0.5) * z);
        ctx.stroke();
      }
      // Marks, props, and exits, with names.
      ctx.font = `${Math.max(8, 5 * z)}px monospace`;
      ctx.textBaseline = 'top';
      for (const p of E.model.places) {
        const d = drawnOf(p);
        const sel = E.selected && E.selected.name === p.name && E.selected.prop === p.prop;
        ctx.fillStyle = sel ? '#d0602a' : p.prop ? '#3a6690' : '#f4f0e4';
        ctx.strokeStyle = '#1c1b1f';
        ctx.lineWidth = 1;
        const r = 3 * z;
        ctx.beginPath();
        if (p.prop) ctx.rect((d.x + 0.5) * z - r, (d.y + 0.5) * z - r, 2 * r, 2 * r);
        else ctx.arc((d.x + 0.5) * z, (d.y + 0.5) * z, r, 0, Math.PI * 2);
        ctx.fill();
        ctx.stroke();
        const exit = !p.prop && E.model.exits.find((e) => e.mark === p.name);
        const text = exit ? `${p.name} > ${exit.to_scene}: ${exit.to_mark}` : p.name;
        ctx.fillStyle = '#1c1b1f';
        ctx.fillText(text, (d.x + 0.5) * z + r + 2 + 1, (d.y + 0.5) * z - r + 1);
        ctx.fillStyle = exit ? '#d0602a' : '#f4f0e4';
        ctx.fillText(text, (d.x + 0.5) * z + r + 2, (d.y + 0.5) * z - r);
      }
      if (E.drag && E.drag.rect) {
        const r = E.drag.rect;
        ctx.strokeStyle = '#d0602a';
        ctx.strokeRect(r.x * z + 0.5, r.y * z + 0.5, r.w * z - 1, r.h * z - 1);
      }
    }

    function at(e) {
      const r = canvas.getBoundingClientRect();
      const x = Math.floor((e.clientX - r.left) * ART_W / r.width);
      const y = Math.floor((e.clientY - r.top) * ART_H / r.height);
      return { x: Math.max(0, Math.min(ART_W - 1, x)), y: Math.max(0, Math.min(ART_H - 1, y)) };
    }

    function hit(p, wantProp) {
      let best = null;
      let bestD = HIT * HIT + 1;
      for (const q of E.model.places) {
        if (wantProp !== undefined && q.prop !== wantProp) continue;
        const d = drawnOf(q);
        const dd = (d.x - p.x) ** 2 + (d.y - p.y) ** 2;
        if (dd < bestD) { best = q; bestD = dd; }
      }
      return best;
    }

    // ---------------------------------------------- writing

    // Writes the model as the scene's block. A refusal puts the model back and says why; the
    // module has already put the script back (D-197 item 4).
    async function commit(model) {
      if (E.scene.block && E.scene.block.comments && !E.commentsOk) {
        const pick = await desk.requester(E.win, {
          title: 'Room', lines: [`The room block for ${E.name} in ${E.scene.block.script} has comments.`, 'The editor rewrites the block whole, so they will be lost.'],
          buttons: [{ id: 'rewrite', label: 'Rewrite' }, { id: 'cancel', label: 'Cancel' }],
        });
        if (pick !== 'rewrite') { render(); return false; }
        E.commentsOk = true;
      }
      const target = (E.scene.block || E.scene.declared).script;
      const before = hooks.fileBytes(target);
      const r = hooks.writeRoom(recordsOf(E.name, model));
      if (!r) { render(); return false; }
      if (!r.written) {
        E.error = r.refused || r.result.message;
        render();
        if (r.refused) await desk.requester(E.win, { title: 'Room', tone: 'fault', lines: ['Nothing was written:', r.refused] });
        else await hooks.showResult(r.result);
        return false;
      }
      E.error = '';
      hooks.scriptWritten(r.script);
      if (before) {
        E.undo.push({ path: r.script, bytes: before });
        if (E.undo.length > UNDO_DEPTH) E.undo.shift();
        E.redo = [];
      }
      await reload();
      return true;
    }

    async function reload() {
      if (!await refresh()) return;
      const sc = sceneNamed(E.name);
      if (!sc) { close(); return; }
      E.scene = sc;
      E.model = modelOf(sc);
      renderList();
      render();
    }

    async function stepUndo(from, to) {
      const step = from.pop();
      if (!step) return;
      to.push({ path: step.path, bytes: hooks.fileBytes(step.path) });
      hooks.setScript(step.path, step.bytes);
      await reload();
    }

    // ---------------------------------------------- input

    canvas.addEventListener('pointerdown', async (e) => {
      if (e.button !== 0) return;
      e.preventDefault();
      const p = at(e);
      if (E.tool === 'move') {
        const q = hit(p);
        E.selected = q ? { name: q.name, prop: q.prop } : null;
        if (q) {
          E.drag = { place: q, from: { x: q.x, y: q.y } };
          try { canvas.setPointerCapture(e.pointerId); } catch { /* a synthetic event */ }
        }
        render();
        return;
      }
      if (E.tool === 'area') {
        const prop = E.selected && E.selected.prop ? E.selected.name : null;
        if (!prop) {
          const q = hit(p, true);
          E.selected = q ? { name: q.name, prop: true } : null;
          render();
          return;
        }
        E.drag = { rect: { x: p.x, y: p.y, w: 1, h: 1 }, start: p, prop };
        try { canvas.setPointerCapture(e.pointerId); } catch { /* a synthetic event */ }
        draw();
        return;
      }
      const q = hit(p, false);
      if (!q) { E.selected = null; render(); return; }
      if (E.tool === 'walkway') {
        if (!E.selected || E.selected.prop || E.selected.name === q.name) { E.selected = { name: q.name, prop: false }; render(); return; }
        const a = E.selected.name;
        const b = q.name;
        const model = structuredClone(E.model);
        if (model.chained) { model.walkways = chainOf(model); model.chained = false; }
        const i = model.walkways.findIndex(([x, y]) => (x === a && y === b) || (x === b && y === a));
        if (i >= 0) model.walkways.splice(i, 1); else model.walkways.push([a, b]);
        E.selected = null;
        await commit(model);
        return;
      }
      if (E.tool === 'exit') { E.selected = { name: q.name, prop: false }; render(); }
    });
    canvas.addEventListener('pointermove', (e) => {
      if (!E.drag) return;
      const p = at(e);
      if (E.drag.place) { E.drag.place.x = p.x; E.drag.place.y = p.y; draw(); return; }
      if (E.drag.rect) {
        const s = E.drag.start;
        E.drag.rect = { x: Math.min(s.x, p.x), y: Math.min(s.y, p.y), w: Math.abs(p.x - s.x) + 1, h: Math.abs(p.y - s.y) + 1 };
        draw();
      }
    });
    const finish = async () => {
      const d = E.drag;
      E.drag = null;
      if (!d) return;
      if (d.place) {
        if (d.place.x === d.from.x && d.place.y === d.from.y) { draw(); return; }
        const model = structuredClone(E.model);
        d.place.x = d.from.x;
        d.place.y = d.from.y;
        await commit(model);
        return;
      }
      if (d.rect) {
        const existing = E.model.areas.find((a) => a.prop === d.prop);
        if (existing && !existing.in_block) {
          draw();
          await desk.requester(E.win, { title: 'Room', lines: [`${d.prop}'s area is written outside the room block.`, 'Change it there, or remove that line and draw it here.'] });
          return;
        }
        const model = structuredClone(E.model);
        model.areas = model.areas.filter((a) => a.prop !== d.prop);
        model.areas.push({ prop: d.prop, x: d.rect.x, y: d.rect.y, w: d.rect.w, h: d.rect.h, in_block: true });
        await commit(model);
      }
    };
    canvas.addEventListener('pointerup', finish);
    canvas.addEventListener('pointercancel', () => { E.drag = null; draw(); });

    // ---------------------------------------------- the window

    function exitTargets() {
      const out = [];
      for (const other of listing.scenes) {
        if (other.name === E.name) continue;
        for (const p of other.places) if (!p.prop) out.push({ scene: other.name, mark: p.name });
      }
      return out;
    }

    function render() {
      const n = cols(E.win);
      const tools = document.createElement('div');
      tools.className = 'row';
      for (const [id, text] of [['move', 'Move'], ['walkway', 'Walkway'], ['exit', 'Exit'], ['area', 'Area']]) {
        const b = desk.button(E.win, `tool:${id}`, text);
        if (E.tool === id) b.classList.add('selected');
        b.setAttribute('aria-pressed', String(E.tool === id));
        tools.appendChild(b);
      }
      const actions = document.createElement('div');
      actions.className = 'row';
      for (const [id, text, on] of [['undo', 'Undo', E.undo.length > 0], ['redo', 'Redo', E.redo.length > 0], ['zoom-out', 'Zoom -', E.zoom > ZOOMS[0]], ['zoom-in', 'Zoom +', E.zoom < ZOOMS[ZOOMS.length - 1]]]) {
        const b = desk.button(E.win, id, text);
        if (!on) b.disabled = true;
        actions.appendChild(b);
      }
      const hint = {
        move: 'Drag a mark or prop.',
        walkway: E.selected ? `Pick the mark to join to ${E.selected.name}, or ${E.selected.name} again to cancel.` : 'Pick two marks to join or part them.',
        exit: E.selected ? `Where does ${E.selected.name} lead?` : 'Pick a mark to give it an exit.',
        area: E.selected && E.selected.prop ? `Drag ${E.selected.name}'s area.` : 'Pick a prop, then drag its area.',
      }[E.tool];
      const out = [tools, actions, view, line(fit(hint, n))];
      if (E.tool === 'exit' && E.selected && !E.selected.prop) {
        const list = document.createElement('div');
        list.className = 'list room-targets';
        const current = E.model.exits.find((x) => x.mark === E.selected.name);
        const none = desk.button(E.win, 'exit-none', 'No exit', { cls: 'item' });
        if (!current) none.classList.add('selected');
        list.appendChild(none);
        exitTargets().forEach((t, i) => {
          const b = desk.button(E.win, `exit-to:${i}`, fit(`To ${t.scene}: ${t.mark}`, n - 2), { cls: 'item' });
          if (current && current.to_scene === t.scene && current.to_mark === t.mark) b.classList.add('selected');
          list.appendChild(b);
        });
        out.push(list);
      }
      const where = E.scene.block ? `${E.scene.block.script}:${E.scene.block.line}` : `new block after ${E.scene.declared.script}:${E.scene.declared.end_line}`;
      out.push(line(fit(`${E.scene.backdrop ? `Backdrop ${E.scene.backdrop}` : 'No backdrop'} | ${where}`, n), E.error ? 'err' : ''));
      E.win.body.replaceChildren(...out);
      draw();
    }

    const a = screen.area.getBoundingClientRect();
    E.win = desk.window(screen, {
      id: `room:${sc.name}`, title: `Room ${sc.name}`, x: Math.max(0, Math.min(120, a.width - 700)), y: 30, w: Math.min(700, a.width), h: Math.min(560, a.height - 30), minW: 220, minH: 220,
      onMessage: async (msg) => {
        if (msg.kind === 'close') { close(); return; }
        if (msg.kind === 'resize') { render(); return; }
        if (msg.kind !== 'gadget') return;
        const id = msg.id;
        if (id.startsWith('tool:')) { E.tool = id.slice(5); E.selected = null; render(); return; }
        if (id === 'undo') { await stepUndo(E.undo, E.redo); return; }
        if (id === 'redo') { await stepUndo(E.redo, E.undo); return; }
        if (id === 'zoom-in') { E.zoom = ZOOMS.find((z) => z > E.zoom) || E.zoom; render(); return; }
        if (id === 'zoom-out') { E.zoom = [...ZOOMS].reverse().find((z) => z < E.zoom) || E.zoom; render(); return; }
        if (id === 'exit-none' || id.startsWith('exit-to:')) {
          const mark = E.selected && E.selected.name;
          if (!mark) return;
          const model = structuredClone(E.model);
          model.exits = model.exits.filter((x) => x.mark !== mark);
          if (id !== 'exit-none') {
            const t = exitTargets()[Number(id.slice(8))];
            model.exits.push({ mark, to_scene: t.scene, to_mark: t.mark });
          }
          await commit(model);
        }
      },
    });

    function close() {
      if (E.win) E.win.close();
      E.win = null;
      editors.delete(E.name);
    }

    E.close = close;
    E.state = () => ({
      name: E.name, tool: E.tool, zoom: E.zoom, undo: E.undo.length, redo: E.redo.length, error: E.error,
      selected: E.selected, block: E.scene.block, chained: E.model.chained,
      places: E.model.places.map((p) => ({ ...p, drawn: drawnOf(p) })),
      walkways: E.model.walkways, exits: E.model.exits, areas: E.model.areas,
      listed: E.scene.places.map((p) => ({ name: p.name, prop: p.prop, drawn_x: p.drawn_x, drawn_y: p.drawn_y })),
    });
    // For tests: a press, drag, and release at art pixels, through the same handlers.
    E.gesture = (points) => {
      const r = canvas.getBoundingClientRect();
      const ev = (type, p) => new PointerEvent(type, { bubbles: true, button: 0, pointerId: 1, clientX: r.left + (p[0] + 0.5) * r.width / ART_W, clientY: r.top + (p[1] + 0.5) * r.height / ART_H });
      canvas.dispatchEvent(ev('pointerdown', points[0]));
      for (const p of points.slice(1)) canvas.dispatchEvent(ev('pointermove', p));
      canvas.dispatchEvent(ev('pointerup', points[points.length - 1]));
    };
    loadBackdrop();
    render();
    return E;
  }

  // Closes every Room window, as a new project opens or another main script is chosen: a
  // room editor belongs to the script it was opened for, and writing through one after the
  // main script changed would edit the wrong script.
  function reset() {
    for (const ed of [...editors.values()]) ed.close();
    listing = null;
    if (listWin) renderList();
  }

  // Lists the main script's scenes again for an open Rooms window.
  async function relist() {
    if (!listWin) return;
    const r = hooks.listRooms();
    listing = r && r.valid ? r : null;
    renderList();
  }

  return {
    openRooms,
    openScene,
    reset,
    relist,
    snap,
    state: () => ({ scenes: listing ? listing.scenes.map((s) => s.name) : [], editors: [...editors.values()].map((e) => e.state()) }),
    editor: (name) => editors.get(name) || null,
  };
}
