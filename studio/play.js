// BeSpoke Studio, the play window (P47-06, D-195): the game the project builds, running in its
// own WebAssembly module beside the editors. The Studio module builds the package; this window
// hands it to the play module (bespoke-play.wasm, the engine's browser runtime) and draws the
// runtime's 1280x720 frame, with its own State drawer (I) and rewind (R).
//
// The play module is a second instance on purpose (D-195): a game that traps or runs out of
// memory ends only this instance. The window then says so, the fault panel reports it, and Run
// starts a fresh one; the project window, the compiler, and every open file are untouched
// (D-192 item 5).
//
// The Facts panel (P47-09, D-205) lists the game's live facts, read from the play module, and
// Show line finds the `remember` lines in the script that could have written one (the Studio
// module's lookup), or names the engine system that writes it.
'use strict';

// eslint-disable-next-line no-unused-vars
function createPlay(desk, screen, hooks) {
  const W = 1280;
  const H = 720;
  const TICK_MS = 50;
  // The runtime's own keys (src/wasm.zig): the gadgets press them, so a gadget and its key can
  // never disagree about what Pause, Step, Rewind, Hint, or State do.
  const KEY = { pause: 32, step: 110, rewind: 114, hint: 104, state: 105 };
  const NAMED = { ArrowLeft: 37, ArrowRight: 39, Enter: 13, Backspace: 8, Home: 36 };
  const EDIT = { Enter: 13, Backspace: 8, Escape: 27, Tab: 9, ArrowUp: 38, ArrowDown: 40 };

  const P = {
    status: 'idle', // idle, starting, running, failed, stopped
    failure: '',
    tick: 0,
    runs: 0,
    sound: false,
    factsOpen: false,
    facts: [],
    filter: '',
  };

  let compiled = null; // WebAssembly.Module, compiled once
  let x = null; // the live instance's exports
  let timer = null;
  let win = null;
  let canvas = null;
  let ctx = null;
  let image = null;
  let statusRow = null;
  let started = 0;

  function errText(err) {
    return String((err && err.message) || err || 'unknown error').slice(0, 200);
  }

  // ------------------------------------------------------------ the module

  async function instance() {
    if (x) return x;
    if (typeof WebAssembly === 'undefined') throw new Error('this browser has no WebAssembly');
    if (!STUDIO_BUILD.play) throw new Error('this page was built without its play module');
    if (!compiled) {
      const bytes = Uint8Array.from(atob(STUDIO_BUILD.play), (c) => c.charCodeAt(0));
      compiled = await WebAssembly.compile(bytes);
    }
    const made = await WebAssembly.instantiate(compiled, {});
    x = made.exports || made.instance.exports;
    return x;
  }

  // Every call into a running game goes through here. A trap ends the instance and leaves the
  // window showing why; nothing propagates into the Studio's own handlers.
  function guard(fn) {
    if (!x) return null;
    try { return fn(x); } catch (err) { stop(err); return null; }
  }

  function stop(err) {
    clearInterval(timer);
    timer = null;
    soundOff();
    x = null;
    P.status = 'stopped';
    P.failure = errText(err);
    render();
    hooks.reportFault([`The game stopped: ${P.failure}`, 'The Studio and your files are fine. Run starts the game again.']);
  }

  function readFailure(e) {
    const len = e.play_failure_len();
    if (!len) return '';
    return new TextDecoder().decode(new Uint8Array(e.memory.buffer, e.play_failure_ptr(), len));
  }

  // Hands `pkg` (a .bspk package) to the play module and starts it with a fresh seed. Returns
  // the window's state; a package the runtime refuses is reported in a requester.
  // `label` names what is running, the main script, in the window's title.
  async function run(pkg, label) {
    open();
    if (label) win.setTitle(`Play ${label}`);
    clearInterval(timer);
    timer = null;
    P.status = 'starting';
    P.failure = '';
    P.tick = 0;
    render();
    let e;
    try {
      e = await instance();
    } catch (err) {
      x = null;
      P.status = 'failed';
      P.failure = `the play module did not start: ${errText(err)}`;
      render();
      await desk.requester(win, { title: 'Play', tone: 'fault', lines: ["The game can't run here.", P.failure, 'The Studio still checks and saves.'] });
      return state();
    }
    const failure = guard((m) => {
      const ptr = m.play_alloc(Math.max(1, pkg.length));
      if (!ptr) return 'OutOfMemory';
      new Uint8Array(m.memory.buffer, ptr, pkg.length).set(pkg);
      // A new run rolls from the clock; the seed stays with the run through rewinds (D-184).
      m.wasm_init(0, Date.now() >>> 0, (Math.random() * 0x100000000) >>> 0);
      return readFailure(m);
    });
    if (failure === null) return state(); // trapped; stop() has reported it
    if (failure) {
      P.status = 'failed';
      P.failure = failure;
      render();
      await desk.requester(win, { title: 'Play', tone: 'fault', lines: ["The game didn't start:", failure] });
      return state();
    }
    P.status = 'running';
    P.runs += 1;
    started = performance.now();
    timer = setInterval(() => { guard((m) => m.wasm_step_tick()); draw(); }, TICK_MS);
    draw();
    render();
    return state();
  }

  // ------------------------------------------------------------ drawing and input

  function draw() {
    guard((m) => {
      m.wasm_set_animation_clock(Math.floor((performance.now() - started) * 60 / 1000));
      m.wasm_render_frame();
      image.data.set(new Uint8Array(m.memory.buffer, m.wasm_framebuffer_ptr(), m.wasm_framebuffer_len()));
      ctx.putImageData(image, 0, 0);
      P.tick = m.wasm_get_tick();
    });
    updateStatus();
  }

  // The canvas keeps 16:9 inside the window (object-fit: contain), so a point is mapped
  // through the drawn frame, not the element's box.
  function toFrame(e) {
    const r = canvas.getBoundingClientRect();
    const scale = Math.min(r.width / W, r.height / H) || 1;
    const left = r.left + (r.width - W * scale) / 2;
    const top = r.top + (r.height - H * scale) / 2;
    return [Math.round((e.clientX - left) / scale), Math.round((e.clientY - top) / scale)];
  }

  function key(code) {
    guard((m) => m.wasm_on_key_down(code));
    draw();
  }

  function onKey(e) {
    if (!win || desk.activeWindow !== win || !x || P.status !== 'running') return;
    if (e.ctrlKey || e.metaKey || e.altKey || document.querySelector('.veil')) return;
    // A typed-command bar, if the game has one, takes every key while it has the keyboard.
    if (guard((m) => m.wasm_command_bar_focused())) {
      e.preventDefault();
      const edit = EDIT[e.key];
      if (edit) guard((m) => m.wasm_on_key_down(edit));
      else if (e.key.length === 1) guard((m) => m.wasm_on_char(e.key.charCodeAt(0)));
      draw();
      return;
    }
    const code = NAMED[e.key] || (e.key.length === 1 ? e.key.charCodeAt(0) : 0);
    if (!code) return;
    e.preventDefault();
    key(code);
  }
  document.addEventListener('keydown', onKey);

  // ------------------------------------------------------------ sound

  // The engine's synthesizer, as the generated game page plays it: the module renders stereo
  // samples here and an AudioWorklet plays them a fifth of a second ahead.
  const PLAYER = `class P extends AudioWorkletProcessor {
    constructor() { super(); this.q = []; this.o = 0; this.port.onmessage = (e) => this.q.push(e.data); }
    process(_, outs) {
      const l = outs[0][0], r = outs[0][1] || l; let i = 0;
      while (i < l.length) {
        const c = this.q[0]; if (!c) { l.fill(0, i); r.fill(0, i); break; }
        const n = Math.min(l.length - i, c.l.length - this.o);
        l.set(c.l.subarray(this.o, this.o + n), i); r.set(c.r.subarray(this.o, this.o + n), i);
        i += n; this.o += n; if (this.o >= c.l.length) { this.q.shift(); this.o = 0; }
      }
      return true;
    }
  }
  registerProcessor('bespoke-engine', P);`;
  let audio = null;
  let pump = null;

  function soundOff() {
    clearInterval(pump);
    pump = null;
    if (audio) audio.close();
    audio = null;
    P.sound = false;
  }

  async function soundOn() {
    if (!x || audio) return;
    const rate = guard((m) => m.wasm_audio_sample_rate());
    if (!rate) return;
    audio = new AudioContext({ sampleRate: rate });
    await audio.audioWorklet.addModule(`data:text/javascript;charset=utf-8,${encodeURIComponent(PLAYER)}`);
    const node = new AudioWorkletNode(audio, 'bespoke-engine', { numberOfInputs: 0, outputChannelCount: [2] });
    node.connect(audio.destination);
    const t0 = audio.currentTime;
    let queued = 0;
    P.sound = true;
    pump = setInterval(() => {
      if (!audio) return;
      const played = (audio.currentTime - t0) * audio.sampleRate;
      if (queued < played) queued = played;
      while (x && queued - played < 0.2 * audio.sampleRate) {
        const chunk = guard((m) => {
          const pcm = new Int16Array(m.memory.buffer, m.wasm_audio_render(1024), 2048);
          const l = new Float32Array(1024);
          const r = new Float32Array(1024);
          for (let i = 0; i < 1024; i += 1) { l[i] = pcm[2 * i] / 32768; r[i] = pcm[2 * i + 1] / 32768; }
          return { l, r };
        });
        if (!chunk) return;
        node.port.postMessage(chunk, [chunk.l.buffer, chunk.r.buffer]);
        queued += 1024;
      }
    }, 25);
  }

  // ------------------------------------------------------------ the window

  function updateStatus() {
    if (!statusRow) return;
    const text = {
      idle: 'Not running. Run builds the project and starts it.',
      starting: 'Starting...',
      running: `Tick ${P.tick}`,
      failed: `Not running: ${P.failure}`,
      stopped: `Stopped: ${P.failure}`,
    }[P.status];
    if (statusRow.dataset.text === text) return;
    statusRow.dataset.text = text;
    statusRow.className = `line ${P.status === 'failed' || P.status === 'stopped' ? 'err' : ''}`.trim();
    statusRow.replaceChildren(desk.label(text));
  }

  function render() {
    if (!win) return;
    const row = document.createElement('div');
    row.className = 'row';
    const live = P.status === 'running';
    const add = (id, text, on) => {
      const b = desk.button(win, id, text);
      if (!on) { b.disabled = true; b.classList.add('disabled'); }
      row.appendChild(b);
    };
    add('play-run', P.status === 'idle' ? 'Run' : 'Run again', true);
    add('play-pause', 'Pause', live);
    add('play-step', 'Step', live);
    add('play-rewind', 'Rewind', live);
    add('play-hint', 'Hint', live);
    add('play-verb', 'Verb', live);
    add('play-state', 'State', live);
    add('play-sound', P.sound ? 'Sound off' : 'Sound on', live);
    add('play-facts', P.factsOpen ? 'Hide facts' : 'Facts', live);
    statusRow = document.createElement('div');
    statusRow.dataset.text = '';
    const parts = [row, canvas, statusRow];
    if (P.factsOpen) parts.push(...factsPanel());
    win.body.replaceChildren(...parts);
    updateStatus();
  }

  // ------------------------------------------------------------ facts (P47-09, D-205)

  function readFacts() {
    const text = guard((m) => {
      const len = m.play_facts();
      return new TextDecoder().decode(new Uint8Array(m.memory.buffer, m.play_facts_ptr(), len));
    });
    P.facts = (text || '').split('\n').filter((l) => l).map((l) => {
      const [relation, subject, object] = l.split('\t');
      return { relation, subject, object: object || '' };
    });
  }

  function factText(f) {
    return f.object ? `${f.relation}(${f.subject}, ${f.object})` : `${f.relation}(${f.subject})`;
  }

  function factsPanel() {
    const wrap = document.createElement('label');
    wrap.className = 'line field';
    wrap.appendChild(desk.label('Relation'));
    const input = document.createElement('input');
    input.className = 'strgad';
    input.name = 'fact-filter';
    input.value = P.filter;
    input.setAttribute('aria-label', 'Filter facts by relation');
    input.onkeydown = (e) => e.stopPropagation();
    input.oninput = () => { P.filter = input.value; render(); const again = win.body.querySelector('input[name="fact-filter"]'); if (again) { again.focus(); again.setSelectionRange(again.value.length, again.value.length); } };
    wrap.appendChild(input);
    const list = document.createElement('div');
    list.className = 'list cast-list';
    const want = P.filter.trim().toLowerCase();
    P.facts.forEach((f, i) => {
      if (want && !f.relation.toLowerCase().includes(want)) return;
      const b = desk.button(win, `fact:${i}`, factText(f), { cls: 'item' });
      b.setAttribute('aria-label', `Show the line that wrote ${factText(f)}`);
      list.appendChild(b);
    });
    const refresh = document.createElement('div');
    refresh.className = 'row';
    refresh.appendChild(desk.button(win, 'facts-refresh', `Refresh (${P.facts.length} facts)`));
    return [wrap, list, refresh];
  }

  // Show line for one fact: one candidate opens the script there, several are offered, and an
  // engine fact names its system and the declaration that drove it (D-205).
  async function showWriter(f) {
    const r = hooks.writers(f);
    if (!r) return;
    const lines = [];
    const buttons = [];
    if (r.engine) lines.push(`Written by the engine (${r.engine}).`);
    if (r.declaration) buttons.push({ id: 'decl', label: `${r.declaration.kind} ${r.declaration.name}`, at: r.declaration });
    if (r.candidates.length === 1 && !r.engine) { hooks.openScript(r.candidates[0].script, r.candidates[0].line, 0); return; }
    if (r.candidates.length) {
      lines.push(r.candidates.length === 1 ? 'This script line can also write it:' : `${r.candidates.length} script lines could have written it; which one ran is not recorded:`);
      r.candidates.slice(0, 6).forEach((c, i) => buttons.push({ id: `c${i}`, label: `${c.script}:${c.line}`, at: c }));
    } else if (!r.engine) lines.push('No line in the script writes it.');
    buttons.push({ id: 'ok', label: 'OK' });
    const pick = await desk.requester(win, { title: factText(f), lines, buttons: buttons.map(({ id, label }) => ({ id, label })) });
    const chosen = buttons.find((b) => b.id === pick && b.at);
    if (chosen) hooks.openScript(chosen.at.script, chosen.at.line, 0);
  }

  function open() {
    if (win) { win.toFront(); win.activate(); return win; }
    canvas = document.createElement('canvas');
    canvas.width = W;
    canvas.height = H;
    canvas.className = 'stage';
    canvas.setAttribute('aria-label', 'The game');
    ctx = canvas.getContext('2d');
    image = new ImageData(W, H);
    ctx.fillStyle = '#1c2028';
    ctx.fillRect(0, 0, W, H);
    // The secondary button is the game's verb key on its frame; held menus still open from
    // anywhere else on the screen.
    canvas.addEventListener('pointerdown', (e) => {
      if (!x || P.status !== 'running') return;
      if (e.button === 2) {
        e.stopPropagation();
        e.preventDefault();
        guard((m) => m.wasm_on_right_click(...toFrame(e)));
      } else if (e.button === 0) {
        guard((m) => m.wasm_on_pointer_down(...toFrame(e)));
      }
      draw();
    });
    canvas.addEventListener('pointermove', (e) => { if (x && P.status === 'running') guard((m) => m.wasm_on_pointer_move(...toFrame(e))); });
    const a = screen.area.getBoundingClientRect();
    const w = Math.min(680, a.width);
    win = desk.window(screen, {
      id: 'play', title: 'Play', x: Math.max(0, a.width - w - 8), y: 24, w, h: Math.min(470, a.height - 24), minW: 220, minH: 160,
      onMessage: async (msg) => {
        if (msg.kind === 'close') { close(); return; }
        if (msg.kind !== 'gadget') return;
        switch (msg.id) {
          case 'play-run': await hooks.build(); return;
          case 'play-pause': key(KEY.pause); return;
          case 'play-step': key(KEY.step); return;
          case 'play-rewind': key(KEY.rewind); return;
          case 'play-hint': key(KEY.hint); return;
          case 'play-state': key(KEY.state); return;
          case 'play-verb': guard((m) => m.wasm_on_right_click(0, 0)); draw(); return;
          case 'play-sound': if (P.sound) soundOff(); else await soundOn(); render(); return;
          case 'play-facts': P.factsOpen = !P.factsOpen; if (P.factsOpen) readFacts(); render(); return;
          case 'facts-refresh': readFacts(); render(); return;
          default:
            if (msg.id.startsWith('fact:')) { const f = P.facts[Number(msg.id.slice(5))]; if (f) await showWriter(f); }
        }
      },
    });
    render();
    return win;
  }

  // Closing the window ends the game; the instance stays for the next Run.
  function close() {
    clearInterval(timer);
    timer = null;
    soundOff();
    if (win) win.close();
    win = null;
    canvas = null;
    statusRow = null;
    if (P.status === 'running' || P.status === 'starting') P.status = 'idle';
  }

  function state() {
    return { status: P.status, failure: P.failure, tick: P.tick, runs: P.runs, sound: P.sound, open: Boolean(win), title: win ? win.el.getAttribute('aria-label') : null, factsOpen: P.factsOpen, facts: P.facts.map(factText) };
  }

  return { open, run, close, state, key, guard, gadget: (id) => { if (win) win.port.post({ kind: 'gadget', id }); return Boolean(win); } };
}
