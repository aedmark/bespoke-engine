// Browser wrapper for the proof WebAssembly module embedded in docs/manual.html (P32-29).
// The six decks live in proofs/wasm_deck.zig; this file supplies no scenes or simulation state.
(() => {
  const canvas = document.querySelector('#bespoke-manual-canvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  const factCount = document.querySelector('#sim-fact-count');
  const statusEl = document.querySelector('#sim-wasm-status');
  const timeline = document.querySelector('#sim-timeline');
  const tickReadout = document.querySelector('#sim-tick-readout');
  const verbEls = [...document.querySelectorAll('[data-verb]')];
  const VERBS = ['WALK', 'LOOK', 'TALK', 'TAKE', 'USE'];
  const DECK_COUNT = 6;
  const WASM_BASE64 = '__BESPOKE_PROOFS_WASM_BASE64__';

  let exp = null;
  let maxTick = 0;
  let verb = 'WALK';

  function decodeBase64(value) {
    const binary = atob(value);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
    return bytes;
  }

  function currentTick() {
    return exp ? Number(exp.wasm_get_tick()) : 0;
  }

  function syncTabs(index) {
    document.querySelectorAll('[data-scenario]').forEach((button) => {
      button.classList.toggle('active', Number(button.dataset.scenario) === index);
    });
  }

  function syncVerbs() {
    verbEls.forEach((button) => {
      button.classList.toggle('active', button.dataset.verb === verb);
    });
  }

  function drawFrame() {
    if (!exp) return;
    exp.wasm_render_frame();
    const pointer = exp.wasm_framebuffer_ptr();
    const length = exp.wasm_framebuffer_len();
    const pixels = new Uint8ClampedArray(exp.memory.buffer, pointer, length);
    ctx.putImageData(new ImageData(pixels, 640, 360), 0, 0);
  }

  function refresh() {
    if (!exp) return;
    const tick = currentTick();
    if (tick > maxTick) maxTick = tick;
    timeline.max = String(maxTick);
    timeline.value = String(tick);
    tickReadout.textContent =
      `Tick ${String(tick).padStart(2, '0')} / ${String(maxTick).padStart(2, '0')}`;
    factCount.textContent = String(exp.wasm_get_fact_count());
    drawFrame();
  }

  function loadDeck(index) {
    if (!exp || index < 0 || index >= DECK_COUNT) return;
    exp.wasm_init(index);
    maxTick = 0;
    verb = 'WALK';
    syncTabs(index);
    syncVerbs();
    statusEl.textContent = `Deck ${index + 1} of ${DECK_COUNT} loaded from bespoke-proofs.wasm.`;
    refresh();
  }

  function sendKey(code) {
    if (!exp) return;
    exp.wasm_on_key_down(code);
    refresh();
  }

  function clickVerb(index) {
    if (!exp) return;
    verb = VERBS[index];
    syncVerbs();
    exp.wasm_on_pointer_down(12 + index * 58 + 26, 338);
    refresh();
  }

  function scrubTo(value) {
    if (!exp) return;
    exp.wasm_scrub_to_tick(value);
    refresh();
  }

  function canvasCoords(event) {
    const box = canvas.getBoundingClientRect();
    return [
      Math.round(((event.clientX - box.left) / box.width) * 640),
      Math.round(((event.clientY - box.top) / box.height) * 360),
    ];
  }

  canvas.addEventListener('pointerdown', (event) => {
    if (!exp) return;
    const [x, y] = canvasCoords(event);
    exp.wasm_on_pointer_down(x, y);
    if (y >= 324 && y <= 354) {
      VERBS.forEach((name, index) => {
        const left = 12 + index * 58;
        if (x >= left && x <= left + 52) verb = name;
      });
      syncVerbs();
    }
    refresh();
  });

  canvas.addEventListener('contextmenu', (event) => {
    event.preventDefault();
    if (!exp) return;
    exp.wasm_on_right_click(0, 0);
    verb = VERBS[(VERBS.indexOf(verb) + 1) % VERBS.length];
    syncVerbs();
    refresh();
  });

  canvas.addEventListener('touchstart', (event) => {
    if (event.touches.length < 2 || !exp) return;
    event.preventDefault();
    const [x, y] = canvasCoords(event.touches[0]);
    exp.wasm_on_touch(0, x, y, 2);
    verb = VERBS[(VERBS.indexOf(verb) + 1) % VERBS.length];
    syncVerbs();
    refresh();
  }, { passive: false });

  document.querySelectorAll('[data-scenario]').forEach((button) => {
    button.addEventListener('click', () => loadDeck(Number(button.dataset.scenario)));
  });
  verbEls.forEach((button) => {
    button.addEventListener('click', () => clickVerb(VERBS.indexOf(button.dataset.verb)));
  });
  document.querySelector('#sim-step-btn').addEventListener('click', () => sendKey(78));
  document.querySelector('#sim-catalyst-btn').addEventListener('click', () => sendKey(83));
  document.querySelector('#sim-pause-btn').addEventListener('click', () => sendKey(32));
  document.querySelector('#sim-rewind-btn').addEventListener('click', () => sendKey(82));
  timeline.addEventListener('input', () => scrubTo(Number(timeline.value)));

  window.addEventListener('keydown', (event) => {
    if (document.activeElement && ['INPUT', 'TEXTAREA'].includes(document.activeElement.tagName)) return;
    if (event.key >= '1' && event.key <= '6') {
      event.preventDefault();
      loadDeck(Number(event.key) - 1);
    } else if (event.key === ' ') {
      event.preventDefault();
      sendKey(32);
    } else if (['n', 'N', 's', 'S', 'r', 'R'].includes(event.key)) {
      sendKey(event.key.charCodeAt(0));
    }
  });

  async function boot() {
    try {
      if (typeof WebAssembly === 'undefined') throw new Error('WebAssembly is unavailable');
      const result = await WebAssembly.instantiate(decodeBase64(WASM_BASE64), {});
      exp = result.instance.exports;
      for (const name of ['wasm_init', 'wasm_step_tick', 'wasm_render_frame', 'wasm_on_pointer_down']) {
        if (typeof exp[name] !== 'function') throw new Error(`missing export ${name}`);
      }
      exp.wasm_init(0);
      syncTabs(0);
      syncVerbs();
      statusEl.textContent = 'bespoke-proofs.wasm ready. Six proof decks are embedded.';
      refresh();
    } catch (error) {
      statusEl.textContent = `WebAssembly load failed: ${error.message}`;
      console.error(error);
    }
  }

  boot();
})();
