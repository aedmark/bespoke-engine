// Browser wrapper for the standalone proof pages (D-086, D-094, D-122): one page per proof in
// site/, tavern.html through valerius.html. tools/build_site.py embeds this file and
// bespoke-proofs.wasm into each. A page plays one deck, named by its canvas's data-deck
// attribute; the deck itself (proofs/wasm_deck.zig) runs the proof's own script, so this
// wrapper holds no game content.
(() => {
  const canvas = document.querySelector('#game-canvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  if (!ctx) return;
  const statusEl = document.querySelector('#game-status');
  const btnNext = document.querySelector('#btn-next');
  const btnRestart = document.querySelector('#btn-restart');
  const btnSound = document.querySelector('#btn-sound');
  const verbButtons = [...document.querySelectorAll('[data-verb]')];
  // A page's own buttons for its deck's one-off actions (D-095), such as Spit: data-action is
  // the deck's number for it, data-key an optional key that presses it.
  const actionButtons = [...document.querySelectorAll('[data-action]')];

  // The deck's index in the proof module's deck table (proofs/wasm_deck.zig), and the verb
  // selected at start (WALK 0 to USE 4).
  const DECK = Number(canvas.dataset.deck);
  const START_VERB = Number(canvas.dataset.startVerb || 0);
  const TICK_INTERVAL_MS = 1000;
  const WASM_BASE64 = '__BESPOKE_PROOFS_WASM_BASE64__';

  let exp = null;
  let lastTickTime = 0;
  let engineAudio = null;
  let soundOn = false;

  // P37-02: the CI browser check reads the same state a player can observe, without reaching
  // into the WebAssembly instance. Keep this small and read-only so it does not become a host API.
  window.bespokePageState = () => ({
    ready: exp !== null,
    tick: exp && exp.wasm_get_tick ? exp.wasm_get_tick() : null,
    facts: exp && exp.wasm_get_fact_count ? exp.wasm_get_fact_count() : null,
    soundOn,
    audioPlaying: Boolean(engineAudio && engineAudio.playing),
  });

  function decodeBase64(value) {
    const binary = atob(value);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  }

  // The verb bar in the canvas and the buttons under it select the same verb. The canvas
  // keeps the truth (taking an item in hand selects USE), so the buttons follow it each frame.
  function syncVerbButtons() {
    const active = exp.wasm_active_verb ? exp.wasm_active_verb() : -1;
    verbButtons.forEach((b, i) => b.classList.toggle('active', i === active));
  }

  function draw() {
    if (!exp) return;
    exp.wasm_render_frame();
    const pixels = new Uint8ClampedArray(exp.memory.buffer, exp.wasm_framebuffer_ptr(), exp.wasm_framebuffer_len());
    ctx.putImageData(new ImageData(pixels, 1280, 720), 0, 0);
    syncVerbButtons();
  }

  function selectVerb(index) {
    if (!exp) return;
    exp.wasm_set_verb(index);
    draw();
  }

  function restart() {
    if (!exp) return;
    exp.wasm_init(DECK);
    lastTickTime = performance.now();
    selectVerb(START_VERB);
  }

  function key(code) {
    if (!exp) return;
    exp.wasm_on_key_down(code);
    lastTickTime = performance.now();
    draw();
  }

  // The engine's own synthesizer: the proof's soundtrack and effects, played through an
  // AudioWorklet (P34-05, tools/engine_audio.js) and started on a click, because browsers
  // block audio until the page is touched.
  function startSound() {
    if (!engineAudio) engineAudio = new window.BespokeEngineAudio(exp);
    engineAudio.start().catch(() => {
      // Sound is optional; say so instead of stopping the game.
      soundOn = false;
      btnSound.textContent = 'Sound: unavailable';
    });
  }

  function stopSound() {
    if (engineAudio) engineAudio.stop();
  }

  function canvasCoords(event) {
    const box = canvas.getBoundingClientRect();
    return [
      Math.round(((event.clientX - box.left) / box.width) * 1280),
      Math.round(((event.clientY - box.top) / box.height) * 720),
    ];
  }

  canvas.addEventListener('pointerdown', (event) => {
    if (!exp) return;
    const [x, y] = canvasCoords(event);
    exp.wasm_on_pointer_down(x, y);
    draw();
  });
  // Hover highlights the person a click would act on (D-088).
  canvas.addEventListener('pointermove', (event) => {
    if (!exp || !exp.wasm_on_pointer_move) return;
    const [x, y] = canvasCoords(event);
    exp.wasm_on_pointer_move(x, y);
    draw();
  });

  canvas.addEventListener('contextmenu', (event) => {
    event.preventDefault();
    if (!exp) return;
    exp.wasm_on_right_click(0, 0);
    draw();
  });

  function deckAction(button) {
    if (!exp || !exp.wasm_deck_action) return;
    exp.wasm_deck_action(Number(button.dataset.action));
    lastTickTime = performance.now();
    draw();
  }

  window.addEventListener('keydown', (event) => {
    if (!exp) return;
    // The typed-command bar (P34-04): while it has the keyboard every key goes to it, editing
    // keys by code and the rest as characters, and none of this page's shortcuts fire.
    if (exp.wasm_command_bar_focused && exp.wasm_command_bar_focused()) {
      event.preventDefault();
      const edit = { Enter: 13, Backspace: 8, Escape: 27, Tab: 9, ArrowUp: 38, ArrowDown: 40 }[event.key];
      if (edit) exp.wasm_on_key_down(edit);
      else if (event.key.length === 1) exp.wasm_on_char(event.key.charCodeAt(0));
      draw();
      return;
    }
    const action = actionButtons.find((b) => b.dataset.key && b.dataset.key === event.key.toLowerCase());
    if (action) {
      event.preventDefault();
      deckAction(action);
      return;
    }
    // I opens the state inspector, which pauses the game; while it is open the arrows, Enter,
    // Backspace, Home, and F move around it (D-070) and the game's keys wait.
    if (event.key === 'i' || event.key === 'I') {
      event.preventDefault();
      key(73);
      return;
    }
    if (exp.wasm_inspector_open && exp.wasm_inspector_open()) {
      const named = { ArrowLeft: 37, ArrowRight: 39, Enter: 13, Backspace: 8, Home: 36, f: 70, F: 70, r: 114, R: 114 }[event.key];
      if (named) {
        event.preventDefault();
        key(named);
      }
      return;
    }
    const pending = exp.wasm_message_pending && exp.wasm_message_pending();
    const open = exp.wasm_dialogue_open && exp.wasm_dialogue_open();
    if (pending && (event.key === 'Enter' || event.key === ' ' || event.key === 's' || event.key === 'S')) {
      event.preventDefault();
      key(13);
    } else if (event.key >= '1' && event.key <= '9') {
      // The number keys answer an open dialogue; with none open they do nothing here, since
      // in the runtime they would switch decks and this page holds one.
      event.preventDefault();
      if (open && !pending) key(event.key.charCodeAt(0));
    } else if (event.key === 's' || event.key === 'S') {
      // [S] would answer an open dialogue with its first line; here it only plays the next
      // step (or, in the duel, starts the next duel).
      event.preventDefault();
      if (!open) key(83);
    } else if (event.key === ' ') {
      // [Space]: Pause, as the desktop window's key does; a waiting message took it above.
      event.preventDefault();
      key(32);
    } else if (event.key === 'r' || event.key === 'R') {
      // [R]: Rewind to tick 0, as the desktop window's key does.
      event.preventDefault();
      key(114);
    } else if (event.key === 'n' || event.key === 'N') {
      // [N]: Step, as the desktop window's key does (D-094). The runtime steps one tick.
      event.preventDefault();
      key(110);
    } else if ('cdefgab'.includes(event.key.toLowerCase()) && event.key.length === 1) {
      // Distaff notes (D-071): The Bell Tower plays drafts on C to B. Decks whose script
      // declares no drafts ignore them.
      event.preventDefault();
      key(event.key.toUpperCase().charCodeAt(0));
    } else if (event.key === 'Enter') {
      // Enter opens a deck's command bar, if it has one (P34-04).
      event.preventDefault();
      if (!open) key(13);
    }
  });

  btnNext.addEventListener('click', () => {
    if (exp && !(exp.wasm_dialogue_open && exp.wasm_dialogue_open()) && !(exp.wasm_message_pending && exp.wasm_message_pending())) key(83);
  });
  btnRestart.addEventListener('click', restart);
  btnSound.addEventListener('click', () => {
    if (!exp) return;
    soundOn = !soundOn;
    btnSound.textContent = soundOn ? 'Sound: on' : 'Sound: off';
    if (soundOn) startSound(); else stopSound();
  });
  verbButtons.forEach((button, index) => button.addEventListener('click', () => selectVerb(index)));
  actionButtons.forEach((button) => button.addEventListener('click', () => deckAction(button)));

  function loop(now) {
    // Sprite animations run on 60 Hz display frames counted from elapsed time, so a faster
    // monitor or a redraw on input does not speed them up (P46-03, D-152).
    if (exp && exp.wasm_set_animation_clock) exp.wasm_set_animation_clock(Math.floor(now * 60 / 1000) >>> 0);
    if (exp && now - lastTickTime >= TICK_INTERVAL_MS) {
      exp.wasm_step_tick();
      lastTickTime = now;
    }
    draw();
    requestAnimationFrame(loop);
  }

  async function boot() {
    try {
      if (typeof WebAssembly === 'undefined') throw new Error('WebAssembly is unavailable');
      const result = await WebAssembly.instantiate(decodeBase64(WASM_BASE64), {});
      exp = result.instance.exports;
      restart();
      statusEl.textContent = '';
      requestAnimationFrame(loop);
    } catch (error) {
      statusEl.textContent = `Could not start the game: ${error.message}`;
      console.error(error);
    }
  }

  boot();
})();
