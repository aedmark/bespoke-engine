// BeSpoke Studio, the room editor (P47-03, D-198, D-199, D-200): the Rooms window lists the
// scenes the main script declares, and a Room window lays one out over its backdrop: move marks
// and props, draw a prop's area, join marks with walkways, and set exits. Each change is
// written by the Studio module as that scene's whole room block (rewritten in place, or added
// after its `scene` block), checked with the compiler, and kept only if it checks. The Grid tool
// (P47-12, D-201) paints cell attributes and places marks on cells, and a settings form sets the
// grid's size, cell, origin, and rates; the grid block is written whole like the room block, and
// a mark moved onto the grid leaves the room block in the same checked edit. The backdrop is
// shown, not chosen (D-200 item 4).
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

  const ATTRIBUTES = ['flammable', 'liquid', 'blocking', 'burning', 'smoke'];
  const RATES = ['burn', 'spread', 'dissipate', 'flow'];
  const FILL = { blocking: 'rgba(28,27,31,0.45)', liquid: 'rgba(58,102,144,0.45)', flammable: 'rgba(208,96,42,0.35)', burning: 'rgba(208,96,42,0.7)', smoke: 'rgba(169,163,152,0.6)' };

  function gridOf(g) {
    if (!g) return null;
    const cells = {};
    for (const a of ATTRIBUTES) cells[a] = new Set();
    for (const r of g.rects) {
      for (let y = r.y; y < r.y + r.height; y += 1) for (let x = r.x; x < r.x + r.width; x += 1) if (cells[r.attribute]) cells[r.attribute].add(`${x},${y}`);
    }
    return {
      name: g.name, width: g.width, height: g.height, cell: g.cell, origin_x: g.origin_x, origin_y: g.origin_y,
      rates: { burn: g.burn, spread: g.spread, dissipate: g.dissipate, flow: g.flow },
      cells, places: g.places.map((pl) => ({ ...pl })), comments: g.block.comments,
    };
  }

  function modelOf(sc) {
    return {
      places: sc.places.map((p) => ({ name: p.name, prop: p.prop, x: p.x, y: p.y, by_grid: p.by_grid })),
      areas: sc.areas.map((a) => ({ ...a })),
      walkways: sc.walkways.map(([a, b]) => [a, b]),
      exits: sc.exits.map((e) => ({ ...e })),
      chained: sc.chained,
      grid: gridOf(sc.grids[0]),
    };
  }

  function cloneModel(m) {
    const out = structuredClone({ ...m, grid: null });
    if (m.grid) {
      out.grid = { ...structuredClone({ ...m.grid, cells: null }), cells: {} };
      for (const a of ATTRIBUTES) out.grid.cells[a] = new Set(m.grid.cells[a]);
    }
    return out;
  }

  // A grid cell's world rectangle, on the art.
  function cellRect(g, x, y) {
    const a = worldToArt({ x: g.origin_x + x * g.cell, y: g.origin_y + y * g.cell });
    const b = worldToArt({ x: g.origin_x + (x + 1) * g.cell, y: g.origin_y + (y + 1) * g.cell });
    return { x: a.x, y: a.y, w: Math.max(1, b.x - a.x), h: Math.max(1, b.y - a.y) };
  }

  // The grid cell under art pixel `p`, or null outside the grid.
  function cellAt(g, p) {
    const w = artToWorld(p.x, p.y);
    const x = Math.floor((w.x - g.origin_x) / g.cell);
    const y = Math.floor((w.y - g.origin_y) / g.cell);
    return x >= 0 && y >= 0 && x < g.width && y < g.height ? { x, y } : null;
  }

  // The default chain as explicit walkways, so a first walkway edit keeps what was joined.
  function chainOf(model) {
    const marks = model.places.filter((p) => !p.prop).map((p) => p.name);
    const out = [];
    for (let i = 1; i < marks.length; i += 1) out.push([marks[i - 1], marks[i]]);
    return out;
  }

  // The edit records the module writes as the blocks (studio/project.zig, `RoomEdit`): the
  // room block when `which.room`, the grid block when `which.grid`. A mark the grid places has
  // no room line (D-201 item 3).
  function recordsOf(name, model, which = { room: true }) {
    const out = [`scene\t${name}`];
    if (which.grid && model.grid) {
      const g = model.grid;
      out.push(`grid\t${g.name}`, `size\t${g.width}\t${g.height}`, `cell\t${g.cell}`, `origin\t${g.origin_x}\t${g.origin_y}`);
      for (const r of RATES) if (g.rates[r]) out.push(`rate\t${r}\t${g.rates[r]}`);
      for (const a of ATTRIBUTES) {
        for (const k of g.cells[a]) {
          const [x, y] = k.split(',').map(Number);
          if (x < g.width && y < g.height) out.push(`set\t${a}\t${x}\t${y}`);
        }
      }
      for (const pl of g.places) out.push(`place\t${pl.mark}\t${pl.x}\t${pl.y}`);
    }
    if (!which.room) return `${out.join('\n')}\n`;
    out.push('room');
    const onGrid = new Set(model.grid ? model.grid.places.map((pl) => pl.mark) : []);
    for (const p of model.places.filter((q) => !q.prop && !onGrid.has(q.name))) out.push(`mark\t${p.name}\t${p.x}\t${p.y}`);
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
      paint: 'flammable', // the Grid tool's attribute, 'erase', or 'place'
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

    // Where a place is drawn: its snapped position, or its cell's centre when the grid
    // places it (D-054).
    function drawnOf(p) {
      const g = E.model.grid;
      const gp = g && !p.prop && g.places.find((q) => q.mark === p.name);
      if (gp) {
        const half = Math.trunc(g.cell / 2);
        return worldToArt({ x: g.origin_x + gp.x * g.cell + half, y: g.origin_y + gp.y * g.cell + half });
      }
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
      // Grid cells: each set attribute filled, and the cell lines while the Grid tool is on.
      const g = E.model.grid;
      if (g) {
        for (const a of ATTRIBUTES) {
          ctx.fillStyle = FILL[a];
          for (const k of g.cells[a]) {
            const [x, y] = k.split(',').map(Number);
            const r = cellRect(g, x, y);
            ctx.fillRect(r.x * z, r.y * z, r.w * z, r.h * z);
          }
        }
        if (E.tool === 'grid' && !E.preview) {
          ctx.strokeStyle = 'rgba(244,240,228,0.35)';
          ctx.lineWidth = 1;
          for (let y = 0; y < g.height; y += 1) {
            for (let x = 0; x < g.width; x += 1) {
              const r = cellRect(g, x, y);
              ctx.strokeRect(r.x * z + 0.5, r.y * z + 0.5, r.w * z - 1, r.h * z - 1);
            }
          }
        }
      }
      // The settings form's footprint, as typed.
      if (E.preview && E.preview.cell > 0 && E.preview.width > 0 && E.preview.height > 0) {
        const pv = E.preview;
        const a0 = worldToArt({ x: pv.origin_x, y: pv.origin_y });
        const b0 = worldToArt({ x: pv.origin_x + pv.width * pv.cell, y: pv.origin_y + pv.height * pv.cell });
        ctx.strokeStyle = '#d0602a';
        ctx.lineWidth = Math.max(1, z);
        ctx.strokeRect(a0.x * z, a0.y * z, (b0.x - a0.x) * z, (b0.y - a0.y) * z);
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
    async function commit(model, which = { room: true }) {
      const gridComments = which.grid && E.model.grid && E.model.grid.comments;
      if (((which.room && E.scene.block && E.scene.block.comments) || gridComments) && !E.commentsOk) {
        const pick = await desk.requester(E.win, {
          title: 'Room', lines: [`The ${gridComments ? 'grid' : 'room'} block for ${E.name} has comments.`, 'The editor rewrites the block whole, so they will be lost.'],
          buttons: [{ id: 'rewrite', label: 'Rewrite' }, { id: 'cancel', label: 'Cancel' }],
        });
        if (pick !== 'rewrite') { render(); return false; }
        E.commentsOk = true;
      }
      // Every script's bytes before the edit: a room and a grid block may sit in two files.
      const before = hooks.scriptBytes();
      const r = hooks.writeRoom(recordsOf(E.name, model, which));
      if (!r) { render(); return false; }
      if (!r.written) {
        E.error = r.refused || r.result.message;
        render();
        if (r.refused) await desk.requester(E.win, { title: 'Room', tone: 'fault', lines: ['Nothing was written:', r.refused] });
        else await hooks.showResult(r.result);
        return false;
      }
      E.error = '';
      for (const path of r.scripts) hooks.scriptWritten(path);
      E.undo.push(r.scripts.map((path) => ({ path, bytes: before[path] })));
      if (E.undo.length > UNDO_DEPTH) E.undo.shift();
      E.redo = [];
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
      to.push(step.map((s) => ({ path: s.path, bytes: hooks.fileBytes(s.path) })));
      for (const s of step) hooks.setScript(s.path, s.bytes);
      await reload();
    }

    // ---------------------------------------------- input

    canvas.addEventListener('pointerdown', async (e) => {
      if (e.button !== 0) return;
      e.preventDefault();
      const p = at(e);
      if (E.tool === 'grid') {
        await gridDown(p, e);
        return;
      }
      if (E.tool === 'move') {
        const q = hit(p);
        E.selected = q ? { name: q.name, prop: q.prop } : null;
        if (q && onGrid(q)) {
          render();
          await desk.requester(E.win, { title: 'Room', lines: [`The grid places ${q.name} on a cell.`, 'Use the Grid tool to move or unplace it.'] });
          return;
        }
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
        const model = cloneModel(E.model);
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
      if (E.drag.cells) { paintCell(p); return; }
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
      if (d.cells) {
        if (!d.changed) { draw(); return; }
        const model = cloneModel(E.model);
        E.model.grid.cells = d.before;
        await commit(model, { grid: true });
        return;
      }
      if (d.place) {
        if (d.place.x === d.from.x && d.place.y === d.from.y) { draw(); return; }
        const model = cloneModel(E.model);
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
        const model = cloneModel(E.model);
        model.areas = model.areas.filter((a) => a.prop !== d.prop);
        model.areas.push({ prop: d.prop, x: d.rect.x, y: d.rect.y, w: d.rect.w, h: d.rect.h, in_block: true });
        await commit(model);
      }
    };
    canvas.addEventListener('pointerup', finish);
    canvas.addEventListener('pointercancel', () => { E.drag = null; draw(); });

    // ---------------------------------------------- the grid (P47-12, D-201)

    function onGrid(q) {
      return Boolean(!q.prop && E.model.grid && E.model.grid.places.some((pl) => pl.mark === q.name));
    }

    // A painting stroke sets the chosen attribute (or clears every attribute) on each cell it
    // crosses; the stroke is written once, when it ends.
    function paintCell(p) {
      const g = E.model.grid;
      const c = cellAt(g, p);
      if (!c) return;
      const key = `${c.x},${c.y}`;
      let changed = false;
      if (E.paint === 'erase') {
        for (const a of ATTRIBUTES) if (g.cells[a].delete(key)) changed = true;
      } else if (!g.cells[E.paint].has(key)) {
        g.cells[E.paint].add(key);
        changed = true;
      }
      if (changed) { E.drag.changed = true; draw(); }
    }

    async function gridDown(p, e) {
      const g = E.model.grid;
      if (!g) { await openGridForm(); return; }
      if (E.paint === 'place') {
        const q = hit(p, false);
        if (q) { E.selected = { name: q.name, prop: false }; render(); return; }
        const c = cellAt(g, p);
        if (!c || !E.selected) return;
        // The mark leaves the room block and joins the grid in one checked edit.
        const model = cloneModel(E.model);
        model.grid.places = model.grid.places.filter((pl) => pl.mark !== E.selected.name);
        model.grid.places.push({ mark: E.selected.name, x: c.x, y: c.y });
        E.selected = null;
        await commit(model, { grid: true, room: Boolean(E.scene.block) });
        return;
      }
      const before = {};
      for (const a of ATTRIBUTES) before[a] = new Set(g.cells[a]);
      E.drag = { cells: true, before, changed: false };
      try { canvas.setPointerCapture(e.pointerId); } catch { /* a synthetic event */ }
      paintCell(p);
    }

    async function unplace() {
      if (!E.selected || !E.model.grid) return;
      const name = E.selected.name;
      const model = cloneModel(E.model);
      const p = model.places.find((q) => q.name === name && !q.prop);
      const d = drawnOf(p);
      p.x = d.x;
      p.y = d.y;
      model.grid.places = model.grid.places.filter((pl) => pl.mark !== name);
      E.selected = null;
      await commit(model, { grid: true, room: Boolean(E.scene.block) });
    }

    // The grid's geometry and rates (D-201 item 4), in world units, with the footprint drawn
    // on the art as the fields change. A first grid covers the whole art.
    let formWin = null;
    async function openGridForm() {
      if (formWin) { formWin.toFront(); formWin.activate(); return formWin; }
      const g = E.model.grid || {
        name: `${E.name.replace(/[^A-Za-z0-9_]+/g, '') || 'Room'}Grid`.replace(/^[^A-Za-z]/, 'G'),
        width: 14, height: 12, cell: 5, origin_x: -15, origin_y: -31,
        rates: { burn: 0, spread: 0, dissipate: 0, flow: 0 }, cells: null, places: [],
      };
      const fields = {};
      const input = (id, label, value) => {
        const wrap = document.createElement('label');
        wrap.className = 'line field';
        wrap.appendChild(desk.label(label));
        const el = document.createElement('input');
        el.className = 'strgad';
        el.name = id;
        el.value = String(value);
        el.autocomplete = 'off';
        el.spellcheck = false;
        el.setAttribute('aria-label', label);
        el.addEventListener('keydown', (ev) => ev.stopPropagation());
        el.addEventListener('input', () => { E.preview = read(); draw(); });
        wrap.appendChild(el);
        fields[id] = el;
        return wrap;
      };
      function read() {
        const n = (id) => Number(fields[id].value.trim());
        return { name: fields.name.value.trim(), width: n('width'), height: n('height'), cell: n('cell'), origin_x: n('origin_x'), origin_y: n('origin_y'), rates: Object.fromEntries(RATES.map((r) => [r, n(r)])) };
      }
      const a = screen.area.getBoundingClientRect();
      formWin = desk.window(screen, {
        id: `grid-form:${E.name}`, title: `Grid ${E.name}`, x: Math.max(0, Math.min(260, a.width - 380)), y: 70, w: Math.min(380, a.width), h: Math.min(520, a.height - 70), minW: 220, minH: 200,
        onMessage: async (msg) => {
          if (msg.kind === 'close' || (msg.kind === 'gadget' && msg.id === 'grid-cancel')) { closeForm(); return; }
          if (msg.kind !== 'gadget' || msg.id !== 'grid-ok') return;
          const v = read();
          const whole = (x, lo) => Number.isInteger(x) && x >= lo;
          if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(v.name) || !whole(v.width, 1) || !whole(v.height, 1) || !whole(v.cell, 1) || !Number.isInteger(v.origin_x) || !Number.isInteger(v.origin_y) || RATES.some((r) => !whole(v.rates[r], 0))) {
            await desk.requester(formWin, { title: 'Grid', lines: ['The name is one word; size and cell are whole numbers from 1, origin is whole, and rates are whole from 0.'] });
            return;
          }
          if (v.width * v.height > 4096) { await desk.requester(formWin, { title: 'Grid', lines: [`${v.width}x${v.height} is ${v.width * v.height} cells; a grid holds at most 4096.`] }); return; }
          const model = cloneModel(E.model);
          const cells = model.grid ? model.grid.cells : Object.fromEntries(ATTRIBUTES.map((x) => [x, new Set()]));
          const places = model.grid ? model.grid.places.filter((pl) => pl.x < v.width && pl.y < v.height) : [];
          model.grid = { ...v, cells, places, comments: model.grid ? model.grid.comments : false };
          closeForm();
          // A place cut off by a smaller grid leaves the mark unplaced, which the room block
          // must then hold, so both blocks are written when a room block exists.
          await commit(model, { grid: true, room: Boolean(E.scene.block) });
        },
      });
      const body = [input('name', 'Name', g.name), input('width', 'Width', g.width), input('height', 'Height', g.height), input('cell', 'Cell', g.cell), input('origin_x', 'Origin x', g.origin_x), input('origin_y', 'Origin y', g.origin_y)];
      for (const r of RATES) body.push(input(r, r.charAt(0).toUpperCase() + r.slice(1), g.rates[r]));
      body.push(line('World units; rates in ticks, 0 off.'));
      const row = document.createElement('div');
      row.className = 'row';
      row.append(desk.button(formWin, 'grid-ok', E.model.grid ? 'Set' : 'Add grid'), desk.button(formWin, 'grid-cancel', 'Cancel'));
      body.push(row);
      formWin.body.replaceChildren(...body);
      E.preview = read();
      draw();
      return formWin;
    }

    function closeForm() {
      if (formWin) formWin.close();
      formWin = null;
      E.preview = null;
      draw();
    }

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
      for (const [id, text] of [['move', 'Move'], ['walkway', 'Walkway'], ['exit', 'Exit'], ['area', 'Area'], ['grid', 'Grid']]) {
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
        grid: !E.model.grid ? 'This scene has no grid. Grid settings adds one.'
          : E.paint === 'place' ? (E.selected ? `Pick a cell for ${E.selected.name}.` : 'Pick a mark, then a cell.')
            : E.paint === 'erase' ? 'Drag over cells to clear them.' : `Drag over cells to make them ${E.paint}.`,
      }[E.tool];
      const out = [tools, actions];
      if (E.tool === 'grid') {
        const row = document.createElement('div');
        row.className = 'row';
        if (E.model.grid) {
          for (const id of [...ATTRIBUTES, 'erase', 'place']) {
            const b = desk.button(E.win, `paint:${id}`, id.charAt(0).toUpperCase() + id.slice(1));
            if (E.paint === id) b.classList.add('selected');
            row.appendChild(b);
          }
          if (E.paint === 'place' && E.selected && onGrid(E.selected)) row.appendChild(desk.button(E.win, 'grid-unplace', `Unplace ${E.selected.name}`));
        }
        row.appendChild(desk.button(E.win, 'grid-settings', E.model.grid ? 'Grid settings...' : 'Add grid...'));
        out.push(row);
      }
      out.push(view, line(fit(hint, n)));
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
        if (id.startsWith('paint:')) { E.paint = id.slice(6); E.selected = null; render(); return; }
        if (id === 'grid-settings') { await openGridForm(); return; }
        if (id === 'grid-unplace') { await unplace(); return; }
        if (id === 'undo') { await stepUndo(E.undo, E.redo); return; }
        if (id === 'redo') { await stepUndo(E.redo, E.undo); return; }
        if (id === 'zoom-in') { E.zoom = ZOOMS.find((z) => z > E.zoom) || E.zoom; render(); return; }
        if (id === 'zoom-out') { E.zoom = [...ZOOMS].reverse().find((z) => z < E.zoom) || E.zoom; render(); return; }
        if (id === 'exit-none' || id.startsWith('exit-to:')) {
          const mark = E.selected && E.selected.name;
          if (!mark) return;
          const model = cloneModel(E.model);
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
      closeForm();
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
      grid: E.model.grid && { ...E.model.grid, cells: Object.fromEntries(ATTRIBUTES.map((a) => [a, [...E.model.grid.cells[a]].sort()])) },
      paint: E.paint,
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
