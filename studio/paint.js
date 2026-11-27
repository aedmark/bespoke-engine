// BeSpoke Studio, the pixel editor (P47-02, D-196): the Art window lists the images the main
// script declares, and a Paint window edits one PNG-backed sheet with a pencil, eraser, fill,
// and colour picker, the frame grid from `frames WxH`, undo, and a preview of the script's own
// animations. Inline-row images open in the read-only script view at their rows.
//
// Pixels come from the Studio module, which decodes the PNG with the engine's own reader, so
// the editor shows what the compiler reads. After each stroke the sheet is encoded by the
// Studio module, read back through that same reader, and handed to the project as the file's
// new bytes (hooks.fileChanged): Check and Play then use the edit before it is saved, and Save
// writes only files whose bytes differ from what was opened.
'use strict';

// eslint-disable-next-line no-unused-vars
function createPaint(desk, screen, hooks) {
  const UNDO_DEPTH = 24;
  const ZOOMS = [1, 2, 3, 4, 6, 8, 12, 16, 24];
  const ANIM_LABEL = { idle: 'idle', walk_up: 'walk up', walk_down: 'walk down', walk_left: 'walk left', walk_right: 'walk right' };

  let art = null; // the last listing from the Studio module
  let artWin = null;
  const editors = new Map(); // image name -> editor

  function errText(err) {
    return String((err && err.message) || err || 'unknown error').slice(0, 200);
  }

  // ------------------------------------------------------------ the listing

  // Reads the main script's art. Returns the listing, or null with the reason shown.
  async function list() {
    const r = hooks.listArt();
    if (!r) return null;
    if (!r.valid) {
      art = null;
      await hooks.showResult(r);
      return null;
    }
    art = r;
    return r;
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

  async function openArt() {
    if (!await hooks.ready('Art')) return null;
    if (!await list()) return null;
    if (!artWin) {
      const a = screen.area.getBoundingClientRect();
      artWin = desk.window(screen, {
        id: 'art', title: 'Art', x: 24, y: Math.min(120, a.height * 0.2), w: Math.min(420, a.width), h: Math.min(260, a.height - 40), minW: 200, minH: 110,
        onMessage: async (msg) => {
          if (msg.kind === 'close') { artWin.close(); artWin = null; return; }
          if (msg.kind === 'resize') { renderArt(); return; }
          if (msg.kind === 'gadget' && msg.id.startsWith('img:')) await openImage(msg.id.slice(4));
        },
      });
    }
    renderArt();
    artWin.toFront();
    artWin.activate();
    return artWin;
  }

  function renderArt() {
    if (!artWin) return;
    const n = cols(artWin);
    const out = [];
    if (!art || !art.images.length) out.push(line('This script declares no images.'));
    else {
      out.push(line(fit(art.palette.length ? `Palette: ${art.palette.length} colour(s)` : 'Palette: any colour', n)));
      const listEl = document.createElement('div');
      listEl.className = 'list';
      for (const img of art.images) {
        const where = img.file ? img.file : `rows in ${img.script}:${img.line}`;
        const b = desk.button(artWin, `img:${img.name}`, fit(`${img.name} ${img.width}x${img.height} ${where}`, n - 2), { cls: 'item' });
        b.setAttribute('aria-label', `${img.name}, ${img.width} by ${img.height}, ${where}`);
        listEl.appendChild(b);
      }
      out.push(listEl);
    }
    artWin.body.replaceChildren(...out);
  }

  async function openImage(name) {
    if (!art && !await list()) return null;
    const img = art.images.find((i) => i.name === name);
    if (!img) { await desk.requester(artWin || hooks.home(), { title: 'Art', lines: [`The script declares no image "${name}".`] }); return null; }
    if (!img.file) {
      // Inline rows are script text; P47-02 writes no script (D-196 item 1).
      const pick = await desk.requester(artWin || hooks.home(), {
        title: 'Art', lines: [`${img.name} is written as rows in ${img.script}.`, 'The pixel editor paints PNG images only; the rows open read-only.'],
        buttons: [{ id: 'show', label: 'Show rows' }, { id: 'ok', label: 'OK' }],
      });
      if (pick === 'show') hooks.openScript(img.script, img.line, 0);
      return null;
    }
    let ed = editors.get(name);
    if (ed) { ed.win.toFront(); ed.win.activate(); return ed.win; }
    const px = hooks.readPixels(img.file);
    if (!px) {
      await desk.requester(artWin || hooks.home(), { title: 'Art', tone: 'fault', lines: [`${img.file} could not be read as a PNG.`] });
      return null;
    }
    ed = makeEditor(img, px);
    editors.set(name, ed);
    return ed.win;
  }

  // ------------------------------------------------------------ one editor

  function makeEditor(img, px) {
    const W = px.width;
    const H = px.height;
    const E = {
      img,
      pixels: px.rgba, // Uint8ClampedArray, W*H*4, alpha 0 or 255
      opened: px.rgba.slice(), // as read; back to these pixels means back to the file's own bytes
      tool: 'pencil',
      colour: [0, 0, 0, 255],
      zoom: Math.max(1, Math.min(16, Math.floor(480 / Math.max(W, H)) || 1)),
      grid: img.frame_width < W || img.frame_height < H,
      undo: [],
      redo: [],
      preview: null, // index into the animations for this image
      stroke: null,
      error: '',
    };
    // A starting colour: the first opaque pixel, or the palette's first colour.
    const pal = art.palette;
    if (pal.length) E.colour = [...pal[0], 255];
    else for (let i = 0; i < E.pixels.length; i += 4) if (E.pixels[i + 3]) { E.colour = [E.pixels[i], E.pixels[i + 1], E.pixels[i + 2], 255]; break; }

    const sheet = document.createElement('canvas');
    sheet.width = W;
    sheet.height = H;
    const sctx = sheet.getContext('2d');
    const view = document.createElement('div');
    view.className = 'paint-view';
    const canvas = document.createElement('canvas');
    canvas.className = 'paint-canvas';
    canvas.setAttribute('aria-label', `${img.name} pixels`);
    view.appendChild(canvas);
    const ctx = canvas.getContext('2d');
    const prevCanvas = document.createElement('canvas');
    prevCanvas.className = 'paint-preview';
    prevCanvas.width = img.frame_width;
    prevCanvas.height = img.frame_height;
    const pctx = prevCanvas.getContext('2d');
    const colourInput = document.createElement('input');
    colourInput.type = 'color';
    colourInput.className = 'sr';
    colourInput.tabIndex = -1;
    colourInput.addEventListener('input', () => {
      const v = colourInput.value;
      E.colour = [parseInt(v.slice(1, 3), 16), parseInt(v.slice(3, 5), 16), parseInt(v.slice(5, 7), 16), 255];
      if (E.tool === 'eraser' || E.tool === 'pick') E.tool = 'pencil';
      render();
    });

    function sync() {
      sctx.putImageData(new ImageData(E.pixels, W, H), 0, 0);
      draw();
    }

    function draw() {
      const z = E.zoom;
      if (canvas.width !== W * z || canvas.height !== H * z) { canvas.width = W * z; canvas.height = H * z; }
      ctx.imageSmoothingEnabled = false;
      // A two-tone check shows transparent pixels as transparent, not as a colour.
      ctx.fillStyle = '#d8d4c8';
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      ctx.fillStyle = '#bcb7aa';
      const cell = Math.max(4, z * 2);
      for (let y = 0; y < canvas.height; y += cell) for (let x = (y / cell) % 2 ? cell : 0; x < canvas.width; x += cell * 2) ctx.fillRect(x, y, cell, cell);
      ctx.drawImage(sheet, 0, 0, W * z, H * z);
      if (E.grid && img.frame_width && img.frame_height) {
        ctx.fillStyle = 'rgba(58, 102, 144, 0.8)';
        for (let x = img.frame_width; x < W; x += img.frame_width) ctx.fillRect(x * z, 0, 1, canvas.height);
        for (let y = img.frame_height; y < H; y += img.frame_height) ctx.fillRect(0, y * z, canvas.width, 1);
      }
    }

    function at(e) {
      const r = canvas.getBoundingClientRect();
      const x = Math.floor((e.clientX - r.left) * W / r.width);
      const y = Math.floor((e.clientY - r.top) * H / r.height);
      return x >= 0 && y >= 0 && x < W && y < H ? [x, y] : null;
    }

    function setPixel(x, y, c) {
      const i = (y * W + x) * 4;
      const d = E.pixels;
      if (c[3] === 0) {
        if (d[i + 3] === 0) return false;
        d[i] = 0; d[i + 1] = 0; d[i + 2] = 0; d[i + 3] = 0;
        return true;
      }
      if (d[i] === c[0] && d[i + 1] === c[1] && d[i + 2] === c[2] && d[i + 3] === 255) return false;
      d[i] = c[0]; d[i + 1] = c[1]; d[i + 2] = c[2]; d[i + 3] = 255;
      return true;
    }

    // Same-colour 4-connected fill; transparent pixels match each other whatever their bytes.
    function fill(x0, y0, c) {
      const d = E.pixels;
      const i0 = (y0 * W + x0) * 4;
      const same = d[i0 + 3] === 0
        ? (i) => d[i + 3] === 0
        : ((r, g, b) => (i) => d[i + 3] === 255 && d[i] === r && d[i + 1] === g && d[i + 2] === b)(d[i0], d[i0 + 1], d[i0 + 2]);
      if (c[3] === 0 ? d[i0 + 3] === 0 : (d[i0 + 3] === 255 && d[i0] === c[0] && d[i0 + 1] === c[1] && d[i0 + 2] === c[2])) return false;
      const seen = new Uint8Array(W * H);
      const stack = [y0 * W + x0];
      seen[stack[0]] = 1;
      while (stack.length) {
        const p = stack.pop();
        const x = p % W;
        const y = (p - x) / W;
        setPixel(x, y, c);
        for (const q of [x > 0 ? p - 1 : -1, x < W - 1 ? p + 1 : -1, y > 0 ? p - W : -1, y < H - 1 ? p + W : -1]) {
          if (q >= 0 && !seen[q] && same(q * 4)) { seen[q] = 1; stack.push(q); }
        }
      }
      return true;
    }

    function line2(a, b, c) {
      // Bresenham between stroke samples, so a fast drag leaves no gaps.
      let [x0, y0] = a;
      const [x1, y1] = b;
      const dx = Math.abs(x1 - x0);
      const dy = -Math.abs(y1 - y0);
      const sx = x0 < x1 ? 1 : -1;
      const sy = y0 < y1 ? 1 : -1;
      let err = dx + dy;
      let changed = false;
      for (;;) {
        changed = setPixel(x0, y0, c) || changed;
        if (x0 === x1 && y0 === y1) break;
        const e2 = 2 * err;
        if (e2 >= dy) { err += dy; x0 += sx; }
        if (e2 <= dx) { err += dx; y0 += sy; }
      }
      return changed;
    }

    function beginStroke() {
      E.stroke = { before: E.pixels.slice(), changed: false, last: null };
    }

    function endStroke() {
      const s = E.stroke;
      E.stroke = null;
      if (!s || !s.changed) return;
      E.undo.push(s.before);
      if (E.undo.length > UNDO_DEPTH) E.undo.shift();
      E.redo = [];
      commit();
    }

    // Hands the sheet to the project as PNG bytes. A refusal (which the checked encoder makes
    // only if the engine's reader would not give these pixels back) restores the last good
    // pixels and says so; nothing reaches the project or the disk.
    function commit() {
      // Undone back to the pixels as opened: the file is its own bytes again, not a re-encoding
      // of them, so Save has nothing to write.
      if (samePixels(E.pixels, E.opened)) {
        E.error = '';
        hooks.fileReverted(img.file);
        render();
        return;
      }
      const out = hooks.encode(W, H, E.pixels);
      if (!out.ok) {
        E.error = out.error;
        if (E.undo.length) E.pixels = E.undo.pop();
        sync();
        render();
        desk.requester(E.win, { title: 'Paint', tone: 'fault', lines: ['The Studio could not write this sheet as a PNG:', out.error, 'The last stroke was undone.'] });
        return;
      }
      E.error = '';
      hooks.fileChanged(img.file, out.bytes);
      render();
    }

    function samePixels(a, b) {
      for (let i = 0; i < a.length; i += 4) {
        if (a[i + 3] !== b[i + 3]) return false;
        if (a[i + 3] && (a[i] !== b[i] || a[i + 1] !== b[i + 1] || a[i + 2] !== b[i + 2])) return false;
      }
      return true;
    }

    function stepUndo(from, to) {
      if (!from.length) return;
      to.push(E.pixels.slice());
      E.pixels = from.pop();
      sync();
      commit();
    }

    canvas.addEventListener('pointerdown', (e) => {
      if (e.button !== 0) return;
      const p = at(e);
      if (!p) return;
      e.preventDefault();
      if (E.tool === 'pick') {
        const i = (p[1] * W + p[0]) * 4;
        if (E.pixels[i + 3]) { E.colour = [E.pixels[i], E.pixels[i + 1], E.pixels[i + 2], 255]; E.tool = 'pencil'; }
        render();
        return;
      }
      beginStroke();
      if (E.tool === 'fill') {
        E.stroke.changed = fill(p[0], p[1], E.colour);
        sync();
        endStroke();
        return;
      }
      // A synthetic event (a test's) has no pointer to capture; strokes still work without it.
      try { canvas.setPointerCapture(e.pointerId); } catch { /* no capture */ }
      const c = E.tool === 'eraser' ? [0, 0, 0, 0] : E.colour;
      E.stroke.changed = setPixel(p[0], p[1], c);
      E.stroke.last = p;
      sync();
    });
    canvas.addEventListener('pointermove', (e) => {
      if (!E.stroke || !E.stroke.last) return;
      const p = at(e);
      if (!p) return;
      const c = E.tool === 'eraser' ? [0, 0, 0, 0] : E.colour;
      if (line2(E.stroke.last, p, c)) { E.stroke.changed = true; sync(); }
      E.stroke.last = p;
    });
    const finish = () => { if (E.stroke) endStroke(); };
    canvas.addEventListener('pointerup', finish);
    canvas.addEventListener('pointercancel', finish);
    canvas.addEventListener('lostpointercapture', finish);

    // ---------------------------------------------- animation preview

    const anims = () => art.animations.filter((a) => art.images[a.image] && art.images[a.image].name === img.name);
    let raf = 0;
    let started = 0;
    function animate(now) {
      raf = 0;
      const a = anims()[E.preview];
      if (!a || !E.win) return;
      if (!started) started = now;
      // Display frames at 60 Hz, as the engine counts them (D-152).
      const clock = Math.floor((now - started) * 60 / 1000);
      const total = a.steps.reduce((t, s) => t + Math.max(1, s[1]), 0);
      let t = total ? clock % total : 0;
      let frame = a.steps.length ? a.steps[0][0] : 0;
      for (const [f, d] of a.steps) { if (t < Math.max(1, d)) { frame = f; break; } t -= Math.max(1, d); }
      const colsN = Math.max(1, Math.floor(W / img.frame_width));
      const fx = (frame % colsN) * img.frame_width;
      const fy = Math.floor(frame / colsN) * img.frame_height;
      pctx.clearRect(0, 0, prevCanvas.width, prevCanvas.height);
      pctx.drawImage(sheet, fx, fy, img.frame_width, img.frame_height, 0, 0, img.frame_width, img.frame_height);
      prevCanvas.dataset.frame = String(frame);
      raf = requestAnimationFrame(animate);
    }

    // ---------------------------------------------- the window

    function swatch(c, i) {
      const b = desk.button(E.win, `colour:${i}`, ' ', { cls: 'swatch' });
      b.style.setProperty('--swatch', `rgb(${c[0]}, ${c[1]}, ${c[2]})`);
      b.setAttribute('aria-label', `Colour ${c[0]} ${c[1]} ${c[2]}`);
      if (c[0] === E.colour[0] && c[1] === E.colour[1] && c[2] === E.colour[2] && E.tool !== 'eraser') b.classList.add('selected');
      return b;
    }

    function colours() {
      if (art.palette.length) return art.palette;
      // Without a declared palette, offer the sheet's own colours (most-used first, at most
      // 32) and any colour through the picker (D-166, D-196 item 3).
      const count = new Map();
      for (let i = 0; i < E.pixels.length; i += 4) {
        if (!E.pixels[i + 3]) continue;
        const k = (E.pixels[i] << 16) | (E.pixels[i + 1] << 8) | E.pixels[i + 2];
        count.set(k, (count.get(k) || 0) + 1);
      }
      const cur = (E.colour[0] << 16) | (E.colour[1] << 8) | E.colour[2];
      if (!count.has(cur)) count.set(cur, Infinity);
      return [...count.entries()].sort((a, b) => b[1] - a[1] || a[0] - b[0]).slice(0, 32).map(([k]) => [k >> 16, (k >> 8) & 255, k & 255]);
    }

    let shownColours = [];
    function render() {
      const tools = document.createElement('div');
      tools.className = 'row';
      for (const [id, text] of [['pencil', 'Pencil'], ['eraser', 'Eraser'], ['fill', 'Fill'], ['pick', 'Pick']]) {
        const b = desk.button(E.win, `tool:${id}`, text);
        if (E.tool === id) b.classList.add('selected');
        b.setAttribute('aria-pressed', String(E.tool === id));
        tools.appendChild(b);
      }
      const actions = document.createElement('div');
      actions.className = 'row';
      const act = (id, text, on) => {
        const b = desk.button(E.win, id, text);
        if (!on) { b.disabled = true; }
        actions.appendChild(b);
      };
      act('undo', 'Undo', E.undo.length > 0);
      act('redo', 'Redo', E.redo.length > 0);
      act('zoom-out', 'Zoom -', E.zoom > ZOOMS[0]);
      act('zoom-in', 'Zoom +', E.zoom < ZOOMS[ZOOMS.length - 1]);
      act('grid', E.grid ? 'Grid off' : 'Grid on', true);
      const pal = document.createElement('div');
      pal.className = 'row swatches';
      shownColours = colours();
      shownColours.forEach((c, i) => pal.appendChild(swatch(c, i)));
      if (!art.palette.length) pal.appendChild(desk.button(E.win, 'new-colour', 'Colour...'));
      const info = line(`${W}x${H}, frames ${img.frame_width}x${img.frame_height} | ${img.file}${hooks.isDirty(img.file) ? ' (edited)' : ''}`);
      const out = [tools, actions, pal, view];
      const list2 = anims();
      if (list2.length) {
        const row = document.createElement('div');
        row.className = 'row';
        list2.forEach((a, i) => {
          const b = desk.button(E.win, `anim:${i}`, `${a.owner} ${ANIM_LABEL[a.anim] || a.anim}`);
          if (E.preview === i) b.classList.add('selected');
          row.appendChild(b);
        });
        row.appendChild(prevCanvas);
        out.push(row);
      }
      out.push(info, colourInput);
      E.win.body.replaceChildren(...out);
      prevCanvas.style.setProperty('--fw', img.frame_width);
      prevCanvas.style.setProperty('--fh', img.frame_height);
    }

    const a = screen.area.getBoundingClientRect();
    E.win = desk.window(screen, {
      id: `paint:${img.name}`, title: `Paint ${img.name}`, x: Math.max(0, Math.min(160, a.width - 560)), y: 36, w: Math.min(560, a.width), h: Math.min(520, a.height - 36), minW: 220, minH: 200,
      onMessage: async (msg) => {
        if (msg.kind === 'close') { close(); return; }
        if (msg.kind === 'resize') { render(); return; }
        if (msg.kind !== 'gadget') return;
        const id = msg.id;
        if (id.startsWith('tool:')) { E.tool = id.slice(5); render(); return; }
        if (id.startsWith('colour:')) { E.colour = [...shownColours[Number(id.slice(7))], 255]; if (E.tool === 'eraser' || E.tool === 'pick') E.tool = 'pencil'; render(); return; }
        if (id.startsWith('anim:')) {
          const i = Number(id.slice(5));
          E.preview = E.preview === i ? null : i;
          started = 0;
          // Draw the first frame now; later frames follow the display (a hidden tab pauses them).
          if (E.preview !== null && !raf) animate(performance.now());
          render();
          return;
        }
        switch (id) {
          case 'undo': stepUndo(E.undo, E.redo); return;
          case 'redo': stepUndo(E.redo, E.undo); return;
          case 'zoom-in': E.zoom = ZOOMS.find((z) => z > E.zoom) || E.zoom; draw(); render(); return;
          case 'zoom-out': E.zoom = [...ZOOMS].reverse().find((z) => z < E.zoom) || E.zoom; draw(); render(); return;
          case 'grid': E.grid = !E.grid; draw(); render(); return;
          case 'new-colour': colourInput.click(); return;
          default:
        }
      },
    });

    function close() {
      if (raf) cancelAnimationFrame(raf);
      raf = 0;
      E.win.close();
      E.win = null;
      editors.delete(img.name);
    }

    render();
    sync();
    E.close = close;
    E.state = () => ({ name: img.name, file: img.file, tool: E.tool, colour: E.colour.slice(0, 3), zoom: E.zoom, undo: E.undo.length, redo: E.redo.length, preview: E.preview, frame: prevCanvas.dataset.frame || null, error: E.error });
    E.paintAt = (x, y, tool) => {
      // For tests: one click of `tool` at sheet pixel (x, y), through the same stroke path.
      const r = canvas.getBoundingClientRect();
      const ev = (type) => new PointerEvent(type, { bubbles: true, button: 0, pointerId: 1, clientX: r.left + (x + 0.5) * r.width / W, clientY: r.top + (y + 0.5) * r.height / H });
      if (tool) E.tool = tool;
      canvas.dispatchEvent(ev('pointerdown'));
      canvas.dispatchEvent(ev('pointerup'));
    };
    E.pixel = (x, y) => Array.from(E.pixels.slice((y * W + x) * 4, (y * W + x) * 4 + 4));
    return E;
  }

  // Closes every editor, as a new project opens.
  function reset() {
    for (const ed of [...editors.values()]) ed.close();
    art = null;
    if (artWin) renderArt();
  }

  return {
    openArt,
    openImage,
    reset,
    state: () => ({ art: Boolean(art), images: art ? art.images.map((i) => ({ name: i.name, file: i.file })) : [], palette: art ? art.palette.length : 0, editors: [...editors.values()].map((e) => e.state()) }),
    editor: (name) => editors.get(name) || null,
  };
}
