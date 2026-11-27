// The Studio's window layer (P47-01, D-192): screens, windows, gadgets, held menus, requesters,
// and one message queue per window. Studio code only; the engine has no windowing module
// (D-192 item 4). Every label is drawn in the engine's 5x7 face from the table the build bakes
// in (D-192 item 7), so this layer runs before, and without, the compiler module (item 5).
'use strict';

// Glyph rows are bits 0..6 of each column byte, top to bottom; columns are 5 wide with one
// column of spacing, as `font.char_width` draws them in the engine.
const GLYPH_W = 5;
const GLYPH_H = 7;
const ADVANCE = 6;

function createDesk(root, fontTable) {
  const glyphs = fontTable.glyphs;
  const placeholder = glyphs[fontTable.placeholder];
  const pathCache = new Map();
  const log = [];
  const screens = [];
  let activeWin = null;
  let menuState = null;

  // ---------------------------------------------------------------- text

  function codepoints(text) {
    const out = [];
    for (const ch of String(text)) out.push(ch.codePointAt(0));
    return out;
  }

  // One SVG path per text: each glyph column becomes vertical runs, so a label is a handful of
  // rectangles that CSS colours (fill: currentColor) and scales (--px) without redrawing.
  function textPath(text) {
    const hit = pathCache.get(text);
    if (hit) return hit;
    let d = '';
    let x = 0;
    let count = 0;
    for (const cp of codepoints(text)) {
      count += 1;
      if (cp === 9 || cp === 32) { x += ADVANCE; continue; }
      const cols = cp < 32 || cp === 127 ? null : (glyphs[cp] || placeholder);
      if (cols) {
        for (let c = 0; c < GLYPH_W; c += 1) {
          let r = 0;
          while (r < GLYPH_H) {
            if (!((cols[c] >> r) & 1)) { r += 1; continue; }
            const start = r;
            while (r < GLYPH_H && ((cols[c] >> r) & 1)) r += 1;
            d += `M${x + c} ${start}h1v${r - start}h-1z`;
          }
        }
      }
      x += ADVANCE;
    }
    const out = { d, width: Math.max(1, count * ADVANCE - 1) };
    if (pathCache.size > 4000) pathCache.clear();
    pathCache.set(text, out);
    return out;
  }

  const SVG = 'http://www.w3.org/2000/svg';

  // A label: the pixel text for the eye and a visually hidden copy for screen readers, search,
  // and the accessible name of the gadget it sits in.
  function label(text, cls = '') {
    const wrap = document.createElement('span');
    wrap.className = `label ${cls}`.trim();
    setLabel(wrap, text);
    return wrap;
  }

  function setLabel(wrap, text) {
    const t = String(text);
    if (wrap.dataset.text === t && wrap.firstChild) return;
    wrap.dataset.text = t;
    const { d, width } = textPath(t);
    const svg = document.createElementNS(SVG, 'svg');
    svg.setAttribute('class', 'px');
    svg.setAttribute('viewBox', `0 0 ${width} ${GLYPH_H}`);
    svg.setAttribute('aria-hidden', 'true');
    svg.style.setProperty('--w', width);
    const path = document.createElementNS(SVG, 'path');
    path.setAttribute('d', d);
    svg.appendChild(path);
    const sr = document.createElement('span');
    sr.className = 'sr';
    sr.textContent = t;
    wrap.replaceChildren(svg, sr);
  }

  // Splits `text` into lines of at most `cols` characters, at spaces where it can.
  function wrapText(text, cols) {
    const lines = [];
    for (const para of String(text).split('\n')) {
      let line = '';
      for (const word of para.split(' ')) {
        let w = word;
        while ([...w].length > cols) {
          if (line) { lines.push(line); line = ''; }
          const chars = [...w];
          lines.push(chars.slice(0, cols).join(''));
          w = chars.slice(cols).join('');
        }
        if (!line) line = w;
        else if ([...line].length + 1 + [...w].length <= cols) line += ` ${w}`;
        else { lines.push(line); line = w; }
      }
      lines.push(line);
    }
    return lines;
  }

  function px() {
    return parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--px')) || 2;
  }

  // ---------------------------------------------------------------- messages

  // One queue per window, drained in order after the event that posted to it. A handler never
  // runs inside a DOM event, so a handler that opens a requester or closes its own window sees
  // a settled layout, and messages a handler posts wait their turn.
  class Port {
    constructor(win) {
      this.win = win;
      this.queue = [];
      this.draining = false;
    }
    post(msg) {
      const full = { ...msg, window: this.win.id, at: performance.now() };
      log.push(full);
      if (log.length > 100) log.shift();
      this.queue.push(full);
      if (!this.draining) {
        this.draining = true;
        queueMicrotask(() => this.drain());
      }
    }
    async drain() {
      while (this.queue.length) {
        const msg = this.queue.shift();
        try {
          if (this.win.onMessage) await this.win.onMessage(msg);
        } catch (err) {
          desk.onHandlerError(err, msg);
        }
      }
      this.draining = false;
    }
  }

  // ---------------------------------------------------------------- gadgets

  function gadget(text, opts = {}) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = `gad ${opts.cls || ''}`.trim();
    if (opts.id) b.dataset.gadget = opts.id;
    if (opts.title) b.setAttribute('aria-label', opts.title);
    if (text !== null) b.appendChild(label(text));
    if (opts.onPick) b.addEventListener('click', (e) => { e.stopPropagation(); opts.onPick(); });
    return b;
  }

  // A gadget whose release posts { kind: 'gadget', id } to its window's port.
  function button(win, id, text, opts = {}) {
    return gadget(text, { ...opts, id, onPick: () => win.port.post({ kind: 'gadget', id }) });
  }

  // A vertical proportional gadget: knob size is the visible share, position the offset. It
  // reports with `onMove(top)` and is driven with `set(total, visible, top)`.
  function propGadget(onMove) {
    const track = document.createElement('div');
    track.className = 'prop';
    track.setAttribute('role', 'scrollbar');
    track.setAttribute('aria-orientation', 'vertical');
    const knob = document.createElement('div');
    knob.className = 'knob';
    track.appendChild(knob);
    const state = { total: 1, visible: 1, top: 0 };
    function layout() {
      const share = Math.min(1, state.visible / Math.max(1, state.total));
      const span = Math.max(0, state.total - state.visible);
      knob.style.height = `${share * 100}%`;
      knob.style.top = `${span ? (state.top / span) * (1 - share) * 100 : 0}%`;
      track.setAttribute('aria-valuemax', String(span));
      track.setAttribute('aria-valuenow', String(state.top));
      track.classList.toggle('full', share >= 1);
    }
    function moveTo(top) {
      const span = Math.max(0, state.total - state.visible);
      const t = Math.max(0, Math.min(span, Math.round(top)));
      if (t !== state.top) { state.top = t; layout(); onMove(t); }
    }
    knob.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      e.stopPropagation();
      knob.setPointerCapture(e.pointerId);
      const startY = e.clientY;
      const startTop = state.top;
      const h = track.getBoundingClientRect().height;
      const span = Math.max(1, state.total - state.visible);
      const free = Math.max(1, h * (1 - Math.min(1, state.visible / state.total)));
      const move = (ev) => moveTo(startTop + ((ev.clientY - startY) / free) * span);
      const up = () => { knob.removeEventListener('pointermove', move); knob.removeEventListener('pointerup', up); };
      knob.addEventListener('pointermove', move);
      knob.addEventListener('pointerup', up);
    });
    track.addEventListener('pointerdown', (e) => {
      if (e.target !== track) return;
      const k = knob.getBoundingClientRect();
      moveTo(state.top + (e.clientY < k.top ? -state.visible : state.visible));
    });
    return {
      el: track,
      set(total, visible, top) { Object.assign(state, { total, visible, top }); layout(); },
      moveTo,
      get top() { return state.top; },
    };
  }

  // ---------------------------------------------------------------- windows

  let nextId = 1;

  class Win {
    constructor(screen, opts) {
      this.screen = screen;
      this.id = opts.id || `win${nextId++}`;
      this.onMessage = opts.onMessage || null;
      this.port = new Port(this);
      this.minW = opts.minW || 120;
      this.minH = opts.minH || 60;
      this.zoomed = null;
      this.requesters = 0;

      const el = document.createElement('section');
      el.className = 'win';
      el.dataset.window = this.id;
      el.setAttribute('aria-label', opts.title);
      this.el = el;

      const bar = document.createElement('div');
      bar.className = 'bar';
      this.bar = bar;
      if (opts.closable !== false) {
        bar.appendChild(gadget(null, { cls: 'g-close', title: `Close ${opts.title}`, onPick: () => this.port.post({ kind: 'close' }) }));
      }
      this.titleLabel = label(opts.title, 'title');
      bar.appendChild(this.titleLabel);
      const right = document.createElement('span');
      right.className = 'bar-right';
      if (opts.zoomable !== false) right.appendChild(gadget(null, { cls: 'g-zoom', title: `Zoom ${opts.title}`, onPick: () => this.zoom() }));
      right.appendChild(gadget(null, { cls: 'g-depth', title: `Depth ${opts.title}`, onPick: () => this.depth() }));
      bar.appendChild(right);
      el.appendChild(bar);

      this.body = document.createElement('div');
      this.body.className = 'body';
      el.appendChild(this.body);

      if (opts.sizable !== false) {
        const size = document.createElement('div');
        size.className = 'g-size';
        size.setAttribute('aria-hidden', 'true');
        size.addEventListener('pointerdown', (e) => this.dragSize(e));
        el.appendChild(size);
      }

      bar.addEventListener('pointerdown', (e) => this.dragMove(e));
      el.addEventListener('pointerdown', () => this.activate(), true);
      el.addEventListener('focusin', () => this.activate());

      screen.area.appendChild(el);
      this.place(opts.x ?? 24, opts.y ?? 24, opts.w ?? 360, opts.h ?? 200);
      screen.windows.push(this);
      if (screen.narrow()) this.fill();
      this.activate();
    }

    place(x, y, w, h) {
      const a = this.screen.area.getBoundingClientRect();
      const W = Math.max(this.minW, Math.min(w, a.width));
      const H = Math.max(this.minH, Math.min(h, a.height));
      this.rect = {
        x: Math.max(0, Math.min(x, a.width - W)),
        y: Math.max(0, Math.min(y, a.height - H)),
        w: W,
        h: H,
      };
      Object.assign(this.el.style, {
        left: `${this.rect.x}px`, top: `${this.rect.y}px`, width: `${this.rect.w}px`, height: `${this.rect.h}px`,
      });
    }

    fill() {
      const a = this.screen.area.getBoundingClientRect();
      this.place(0, 0, a.width, a.height);
    }

    setTitle(text) {
      setLabel(this.titleLabel, text);
      this.el.setAttribute('aria-label', text);
    }

    activate() {
      if (activeWin === this) return;
      const prev = activeWin;
      activeWin = this;
      if (prev) {
        prev.el.classList.remove('active');
        prev.port.post({ kind: 'deactivate' });
      }
      this.el.classList.add('active');
      this.port.post({ kind: 'activate' });
    }

    toFront() { this.screen.area.appendChild(this.el); }
    toBack() { this.screen.area.insertBefore(this.el, this.screen.area.firstChild); }

    // The depth gadget: to the back when already in front, otherwise to the front.
    depth() {
      if (this.screen.area.lastElementChild === this.el) this.toBack(); else this.toFront();
    }

    // The zoom gadget swaps between the window's place and a second remembered place, which
    // starts as the whole screen.
    zoom() {
      const a = this.screen.area.getBoundingClientRect();
      const other = this.zoomed || { x: 0, y: 0, w: a.width, h: a.height };
      this.zoomed = { ...this.rect };
      this.place(other.x, other.y, other.w, other.h);
      this.port.post({ kind: 'resize', w: this.rect.w, h: this.rect.h });
    }

    close() {
      this.el.remove();
      const list = this.screen.windows;
      list.splice(list.indexOf(this), 1);
      if (activeWin === this) {
        activeWin = null;
        const next = list[list.length - 1];
        if (next) next.activate();
      }
    }

    dragMove(e) {
      if (e.button !== 0 || e.target.closest('.gad')) return;
      e.preventDefault();
      this.bar.setPointerCapture(e.pointerId);
      const sx = e.clientX - this.rect.x;
      const sy = e.clientY - this.rect.y;
      const move = (ev) => this.place(ev.clientX - sx, ev.clientY - sy, this.rect.w, this.rect.h);
      const up = () => { this.bar.removeEventListener('pointermove', move); this.bar.removeEventListener('pointerup', up); };
      this.bar.addEventListener('pointermove', move);
      this.bar.addEventListener('pointerup', up);
    }

    dragSize(e) {
      if (e.button !== 0) return;
      e.preventDefault();
      e.stopPropagation();
      const g = e.currentTarget;
      g.setPointerCapture(e.pointerId);
      const sx = e.clientX - this.rect.w;
      const sy = e.clientY - this.rect.h;
      const move = (ev) => this.place(this.rect.x, this.rect.y, ev.clientX - sx, ev.clientY - sy);
      const up = () => {
        g.removeEventListener('pointermove', move);
        g.removeEventListener('pointerup', up);
        this.port.post({ kind: 'resize', w: this.rect.w, h: this.rect.h });
      };
      g.addEventListener('pointermove', move);
      g.addEventListener('pointerup', up);
    }
  }

  // ---------------------------------------------------------------- requesters

  // A requester blocks its window until answered and resolves with the id of the gadget
  // picked. Return answers the first gadget, Escape the last, as the period's left-yes,
  // right-no layout reads.
  function requester(win, { title, lines = [], buttons = [{ id: 'ok', label: 'OK' }], tone = 'info' }) {
    return new Promise((resolve) => {
      const veil = document.createElement('div');
      veil.className = 'veil';
      const box = document.createElement('div');
      box.className = `req req-${tone}`;
      box.setAttribute('role', 'alertdialog');
      box.setAttribute('aria-label', title);
      const head = document.createElement('div');
      head.className = 'req-title';
      head.appendChild(label(title));
      box.appendChild(head);
      const text = document.createElement('div');
      text.className = 'req-text';
      const cols = Math.max(16, Math.floor((win.rect.w * 0.9 - 8 * px()) / (ADVANCE * px())));
      for (const line of lines) {
        for (const part of wrapText(line, cols)) {
          const row = document.createElement('div');
          row.className = 'line';
          row.appendChild(label(part));
          text.appendChild(row);
        }
      }
      box.appendChild(text);
      const row = document.createElement('div');
      row.className = 'req-buttons';
      const finish = (id) => {
        veil.remove();
        win.requesters -= 1;
        win.el.classList.toggle('blocked', win.requesters > 0);
        win.port.post({ kind: 'requester', id });
        resolve(id);
      };
      for (const b of buttons) row.appendChild(gadget(b.label, { id: b.id, onPick: () => finish(b.id) }));
      box.appendChild(row);
      box.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); finish(buttons[buttons.length - 1].id); }
      });
      veil.appendChild(box);
      win.requesters += 1;
      win.el.classList.add('blocked');
      win.el.appendChild(veil);
      win.activate();
      row.firstChild.focus();
    });
  }

  // ---------------------------------------------------------------- screens and menus

  class Screen {
    constructor(title) {
      this.windows = [];
      this.menus = [];
      const el = document.createElement('div');
      el.className = 'screen';
      this.el = el;
      const bar = document.createElement('div');
      bar.className = 'sbar';
      this.titleLabel = label(title, 'stitle');
      this.menuButton = gadget('Menus', { cls: 'g-menus', onPick: () => openMenus(this, 'sticky') });
      this.strip = document.createElement('div');
      this.strip.className = 'strip';
      this.strip.setAttribute('role', 'menubar');
      const right = document.createElement('span');
      right.className = 'bar-right';
      right.appendChild(gadget(null, { cls: 'g-depth', title: 'Screen to back', onPick: () => this.depth() }));
      bar.append(this.menuButton, this.titleLabel, this.strip, right);
      this.bar = bar;
      this.area = document.createElement('div');
      this.area.className = 'area';
      el.append(bar, this.area);
      root.appendChild(el);
      screens.push(this);
      this.offset = 0;

      // The secondary button opens the menu strip while it is held (desktop pointers); the
      // browser's own context menu never shows on a screen.
      el.addEventListener('contextmenu', (e) => e.preventDefault());
      el.addEventListener('pointerdown', (e) => {
        if (e.button === 2 && e.pointerType === 'mouse') { e.preventDefault(); openMenus(this, 'held', e); }
      });
      bar.addEventListener('pointerdown', (e) => this.dragScreen(e));
      bar.addEventListener('dblclick', (e) => { if (!e.target.closest('.gad')) this.slide(0); });
    }

    narrow() { return window.matchMedia('(max-width: 700px)').matches; }

    setTitle(text) { setLabel(this.titleLabel, text); }

    // Screens slide down by their title bar to show what is behind them, and spring back to
    // the top on a double click.
    dragScreen(e) {
      if (e.button !== 0 || e.target.closest('.gad') || menuState) return;
      e.preventDefault();
      this.bar.setPointerCapture(e.pointerId);
      const start = e.clientY - this.offset;
      const move = (ev) => this.slide(ev.clientY - start);
      const up = () => { this.bar.removeEventListener('pointermove', move); this.bar.removeEventListener('pointerup', up); };
      this.bar.addEventListener('pointermove', move);
      this.bar.addEventListener('pointerup', up);
    }

    slide(y) {
      const max = Math.max(0, window.innerHeight - this.bar.getBoundingClientRect().height);
      this.offset = Math.max(0, Math.min(max, y));
      this.el.style.transform = this.offset ? `translateY(${this.offset}px)` : '';
    }

    depth() {
      if (screens.length < 2) { this.slide(this.offset ? 0 : window.innerHeight * 0.5); return; }
      root.insertBefore(this.el, root.firstChild);
    }

    setMenus(menus) { this.menus = menus; }
  }

  function closeMenus(pick) {
    if (!menuState) return;
    const { screen, onDoc } = menuState;
    screen.bar.classList.remove('menus-open');
    screen.strip.replaceChildren();
    document.removeEventListener('pointerup', onDoc, true);
    document.removeEventListener('pointerdown', onDoc, true);
    document.removeEventListener('keydown', onDoc, true);
    menuState = null;
    if (pick) desk.pickMenu(pick);
  }

  // `held`: the strip lives while the secondary button is down and the item under the pointer
  // at release is picked. `sticky`: a tap opens it, a tap on an item picks, a tap outside or
  // Escape closes. Touch and keyboard users get sticky menus; the items are the same.
  function openMenus(screen, mode) {
    if (menuState) { closeMenus(); if (mode === 'sticky') return; }
    screen.bar.classList.add('menus-open');
    const strip = screen.strip;
    let openTitle = null;
    const titles = [];
    const items = new Map();
    for (const menu of screen.menus) {
      const t = gadget(menu.title, { cls: 'm-title' });
      t.setAttribute('role', 'menuitem');
      t.setAttribute('aria-haspopup', 'true');
      const drop = document.createElement('div');
      drop.className = 'drop';
      drop.setAttribute('role', 'menu');
      for (const item of menu.items) {
        const it = gadget(null, { cls: 'm-item', id: item.id });
        it.setAttribute('role', 'menuitem');
        it.appendChild(label(item.label, 'm-label'));
        if (item.key) it.appendChild(label(desk.keyName(item), 'm-key'));
        if (item.checked) it.classList.add('checked');
        if (item.disabled) it.classList.add('disabled');
        items.set(it, item);
        it.addEventListener('click', (e) => { e.stopPropagation(); if (mode === 'sticky') closeMenus(item.disabled ? null : item); });
        drop.appendChild(it);
      }
      const show = () => {
        if (openTitle === t) return;
        for (const other of titles) other.classList.remove('open');
        t.classList.add('open');
        openTitle = t;
      };
      t.addEventListener('pointerenter', show);
      t.addEventListener('click', (e) => { e.stopPropagation(); show(); });
      t.appendChild(drop);
      titles.push(t);
      strip.appendChild(t);
    }
    // Held menus show each title's items as the pointer crosses it, so a drag across the strip
    // reads every menu without a click; drops are children of their titles for that reason.
    const onDoc = (e) => {
      if (e.type === 'keydown') {
        if (e.key === 'Escape') { e.preventDefault(); closeMenus(); }
        return;
      }
      // The document hears the release first (capture), so it reads the item under the
      // pointer itself rather than waiting for the item's own listener.
      if (mode === 'held' && e.type === 'pointerup') {
        const under = document.elementFromPoint(e.clientX, e.clientY);
        const item = items.get(under && under.closest('.m-item'));
        closeMenus(item && !item.disabled ? item : null);
        return;
      }
      if (mode === 'sticky' && e.type === 'pointerdown' && !e.target.closest('.strip, .g-menus')) closeMenus();
    };
    menuState = { screen, onDoc };
    document.addEventListener('pointerup', onDoc, true);
    document.addEventListener('pointerdown', onDoc, true);
    document.addEventListener('keydown', onDoc, true);
    if (mode === 'sticky' && titles[0]) { titles[0].classList.add('open'); openTitle = titles[0]; titles[0].focus(); }
  }

  // ---------------------------------------------------------------- the fault panel

  // A failed mode reports here before the Studio falls back to its workspace (D-192 item 5):
  // a bordered panel across the top of the screen that waits for a click, Return, or Escape.
  // The border blinks unless the reader asked for reduced motion.
  function fault(lines) {
    return new Promise((resolve) => {
      const panel = document.createElement('div');
      panel.className = 'fault';
      panel.setAttribute('role', 'alert');
      panel.tabIndex = 0;
      for (const line of lines) {
        const row = document.createElement('div');
        row.className = 'line';
        row.appendChild(label(line));
        panel.appendChild(row);
      }
      const done = () => { panel.remove(); resolve(); };
      panel.addEventListener('click', done);
      panel.addEventListener('keydown', (e) => { if (['Enter', 'Escape', ' '].includes(e.key)) { e.preventDefault(); done(); } });
      root.appendChild(panel);
      panel.focus();
    });
  }

  const desk = {
    label, setLabel, wrapText, button, gadget, propGadget, requester, fault, px,
    screen: (title) => new Screen(title),
    window: (screen, opts) => new Win(screen, opts),
    get activeWindow() { return activeWin; },
    get menuOpen() { return Boolean(menuState); },
    log,
    // Set by the app: where a menu pick goes, how a key is named, what a handler error does.
    pickMenu: () => {},
    keyName: (item) => item.key,
    onHandlerError: (err) => console.error(err),
    advance: ADVANCE,
    glyphHeight: GLYPH_H,
  };
  return desk;
}
