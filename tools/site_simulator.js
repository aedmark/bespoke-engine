// Browser wrapper for the standalone showcase site (P30-01, D-042).
// tools/build_site.py embeds this file and bespoke-proofs.wasm into site/index.html.
// The seven decks live in proofs/wasm_deck.zig; this wrapper supplies no scenes or facts.
(() => {
  const canvas = document.querySelector('#sim-canvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  if (!ctx) return;

  const btnPlayPause = document.querySelector('#btn-play-pause');
  const btnStep = document.querySelector('#btn-step');
  const btnCatalyst = document.querySelector('#btn-catalyst');
  const btnRewind = document.querySelector('#btn-rewind');
  const btnReset = document.querySelector('#btn-reset');
  const timeline = document.querySelector('#timeline-slider');
  const timelineLabel = document.querySelector('#timeline-label');
  const tickCounter = document.querySelector('#tick-counter');
  const factCounter = document.querySelector('#fact-counter');
  const simLed = document.querySelector('#sim-led');
  const simStateText = document.querySelector('#sim-state-text');
  const sceneBanner = document.querySelector('#scene-banner');
  const eventLog = document.querySelector('#terminal-event-log');
  const toggleCrt = document.querySelector('#toggle-crt');
  const toggleSound = document.querySelector('#toggle-sound');
  const statusEl = document.querySelector('#sim-wasm-status');
  const factCountEl = document.querySelector('#sim-fact-count');
  const runtimeTick = document.querySelector('#runtime-tick');
  const runtimeDeck = document.querySelector('#runtime-deck');
  const runtimeDeckIndex = document.querySelector('#runtime-deck-index');
  const runtimePaused = document.querySelector('#runtime-paused');
  const scenarioTabs = [...document.querySelectorAll('[data-scenario]')];
  const verbButtons = [...document.querySelectorAll('[data-verb]')];
  // Script viewer (P30-03, D-068): build_site.py embeds every proof's script as JSON beside the
  // gallery. The viewer follows the active deck; a gallery card's View script opens any proof.
  const scriptData = (() => {
    const el = document.querySelector('#proof-scripts');
    try { return el ? JSON.parse(el.textContent) : {}; } catch (_) { return {}; }
  })();
  const scriptTitle = document.querySelector('#script-view-title');
  const scriptSource = document.querySelector('#script-view-source');
  const scriptNote = document.querySelector('#script-view-note');
  const scriptCode = document.querySelector('#script-view-code');
  const DEFAULT_SCRIPT_NOTE = scriptNote ? scriptNote.textContent : '';

  const VERBS = ['WALK', 'LOOK', 'TALK', 'TAKE', 'USE'];
  const DECK_NAMES = [
    'Tavern Heist',
    'Booty Island Spitting Contest',
    'GK3 Cat Moustache',
    'The Living Village',
    'Lochmarne Goat',
    'Day of the Tentacle Trio',
    'Caustic Grog',
  ];
  const DECK_BANNERS = [
    'TAVERN HEIST',
    'BOOTY ISLAND SPITTING CONTEST',
    'GK3 CAT MOUSTACHE',
    'THE LIVING VILLAGE',
    'LOCHMARNE GOAT',
    'DAY OF THE TENTACLE TRIO',
    'CAUSTIC GROG',
  ];
  const DECK_COUNT = DECK_NAMES.length;
  const TICK_INTERVAL_MS = 250;
  const SNAPSHOT_WINDOW = 32; // Keep in step with src/wasm.zig MAX_WASM_SNAPSHOTS.
  const WASM_BASE64 = '__BESPOKE_PROOFS_WASM_BASE64__';

  let exp = null;
  let currentDeck = 0;
  let maxTick = 0;
  let paused = false;
  let lastTickTime = 0;
  let verb = 'WALK';
  let audioCtx = null;
  let soundEnabled = false;

  function playBeep(freq = 440, type = 'square', duration = 0.06, volume = 0.08) {
    if (!soundEnabled) return;
    try {
      if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      if (audioCtx.state === 'suspended') audioCtx.resume();
      const osc = audioCtx.createOscillator();
      const gain = audioCtx.createGain();
      osc.type = type;
      osc.frequency.setValueAtTime(freq, audioCtx.currentTime);
      gain.gain.setValueAtTime(volume, audioCtx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + duration);
      osc.connect(gain);
      gain.connect(audioCtx.destination);
      osc.start();
      osc.stop(audioCtx.currentTime + duration);
    } catch (error) {
      // Interface audio is optional; a blocked AudioContext must not stop the simulator.
    }
  }

  function decodeBase64(value) {
    const binary = atob(value);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
    return bytes;
  }

  function currentTick() {
    return exp ? Number(exp.wasm_get_tick()) : 0;
  }

  function oldestTick() {
    return Math.max(0, maxTick - (SNAPSHOT_WINDOW - 1));
  }

  function syncTabs(index) {
    scenarioTabs.forEach((button) => {
      button.classList.toggle('active', Number(button.dataset.scenario) === index);
    });
  }

  function syncVerbs() {
    verbButtons.forEach((button) => {
      button.classList.toggle('active', button.dataset.verb === verb);
    });
  }

  function updatePausedUI() {
    btnPlayPause.innerHTML = paused ? '<span>▶</span> Resume' : '<span>[||]</span> Pause';
    simLed.className = `led-dot ${paused ? 'amber' : 'green'}`;
    simStateText.textContent = paused ? 'SIMULATION PAUSED' : 'SIMULATION RUNNING';
    runtimePaused.textContent = paused ? 'PAUSED' : 'RUNNING';
  }

  function drawFrame() {
    if (!exp) return;
    exp.wasm_render_frame();
    const pointer = exp.wasm_framebuffer_ptr();
    const length = exp.wasm_framebuffer_len();
    if (length !== 640 * 360 * 4) throw new Error(`unexpected framebuffer length ${length}`);
    const pixels = new Uint8ClampedArray(exp.memory.buffer, pointer, length);
    ctx.putImageData(new ImageData(pixels, 640, 360), 0, 0);
  }

  function showScript(id) {
    const entry = scriptData[id];
    if (!entry || !scriptCode) return;
    scriptTitle.textContent = `${entry.title}: script`;
    scriptSource.textContent = entry.source;
    scriptNote.textContent = entry.note || DEFAULT_SCRIPT_NOTE;
    scriptCode.innerHTML = entry.html;
    scriptCode.parentElement.scrollTop = 0;
  }

  function scriptForDeck(index) {
    return Object.keys(scriptData).find((id) => scriptData[id].deck === index);
  }

  function log(prefix, message, type = 'info') {
    if (!eventLog) return;
    const entry = document.createElement('div');
    entry.className = `log-entry log-${type}`;
    entry.innerHTML = `<span style="opacity:0.6;">[T:${currentTick()}]</span> <strong>[${prefix}]</strong> ${message}`;
    eventLog.appendChild(entry);
    while (eventLog.children.length > 30) eventLog.removeChild(eventLog.firstChild);
    eventLog.scrollTop = eventLog.scrollHeight;
  }

  function refresh() {
    if (!exp) return;
    const tick = currentTick();
    if (tick > maxTick) maxTick = tick;
    tickCounter.textContent = String(tick);
    factCounter.textContent = String(exp.wasm_get_fact_count());
    factCountEl.textContent = String(exp.wasm_get_fact_count());
    runtimeTick.textContent = String(tick);
    runtimeDeck.textContent = DECK_NAMES[currentDeck];
    runtimeDeckIndex.textContent = `${currentDeck + 1} / ${DECK_COUNT}`;
    sceneBanner.textContent = DECK_BANNERS[currentDeck];
    timeline.min = String(oldestTick());
    timeline.max = String(maxTick);
    timeline.value = String(Math.max(oldestTick(), Math.min(tick, maxTick)));
    timelineLabel.textContent = `${tick}/${maxTick}`;
    updatePausedUI();
    drawFrame();
  }

  function loadDeck(index) {
    if (!exp || index < 0 || index >= DECK_COUNT) return;
    currentDeck = index;
    maxTick = 0;
    paused = false;
    verb = 'WALK';
    exp.wasm_init(index);
    syncTabs(index);
    syncVerbs();
    lastTickTime = performance.now();
    log('DECK', `Loaded ${DECK_NAMES[index]} from bespoke-proofs.wasm.`, 'cue');
    const id = scriptForDeck(index);
    if (id) showScript(id);
    refresh();
  }

  function step() {
    if (!exp) return;
    exp.wasm_on_key_down(78);
    lastTickTime = performance.now();
    log('STEP', `Advanced to tick ${currentTick()}.`, 'info');
    refresh();
  }

  function catalyst() {
    if (!exp) return;
    exp.wasm_on_key_down(83);
    lastTickTime = performance.now();
    log('CATALYST', `Deck catalyst dispatched. Facts: ${exp.wasm_get_fact_count()}.`, 'rule');
    refresh();
    playBeep(700, 'triangle', 0.12, 0.12);
  }

  function togglePause() {
    if (!exp) return;
    exp.wasm_on_key_down(32);
    paused = !paused;
    if (!paused) lastTickTime = performance.now();
    log('PAUSE', paused ? 'Simulation paused.' : 'Simulation resumed.', 'info');
    refresh();
    playBeep(paused ? 400 : 600, 'sine', 0.05);
  }

  function rewindTo(target) {
    if (!exp) return;
    const requested = Number(target);
    const floor = oldestTick();
    const bounded = Math.max(floor, Math.min(maxTick, requested));
    exp.wasm_scrub_to_tick(bounded);
    paused = true;
    lastTickTime = performance.now();
    const suffix = requested < floor ? ' (oldest retained snapshot)' : '';
    log('REWIND', `Scrubbed to tick ${currentTick()}${suffix}.`, 'rule');
    refresh();
    playBeep(300, 'sawtooth', 0.06, 0.08);
  }

  function applyVerb(index) {
    if (!exp || index < 0 || index >= VERBS.length) return;
    verb = VERBS[index];
    syncVerbs();
    exp.wasm_on_pointer_down(12 + index * 58 + 26, 338);
    refresh();
    playBeep(520, 'sine', 0.04);
  }

  function canvasCoords(event) {
    const box = canvas.getBoundingClientRect();
    return [
      Math.round(((event.clientX - box.left) / box.width) * 640),
      Math.round(((event.clientY - box.top) / box.height) * 360),
    ];
  }

  btnPlayPause.addEventListener('click', togglePause);
  btnStep.addEventListener('click', step);
  btnCatalyst.addEventListener('click', catalyst);
  btnRewind.addEventListener('click', () => rewindTo(0));
  btnReset.addEventListener('click', () => {
    loadDeck(currentDeck);
    log('RESET', `Reloaded ${DECK_NAMES[currentDeck]}.`, 'info');
    playBeep(350, 'sine', 0.08);
  });
  timeline.addEventListener('input', () => rewindTo(Number(timeline.value)));

  scenarioTabs.forEach((button) => {
    button.addEventListener('click', () => {
      loadDeck(Number(button.dataset.scenario));
      playBeep(700, 'triangle', 0.08);
    });
  });
  verbButtons.forEach((button, index) => {
    button.addEventListener('click', () => applyVerb(index));
  });

  document.querySelectorAll('[data-play-deck]').forEach((button) => {
    button.addEventListener('click', () => {
      loadDeck(Number(button.dataset.playDeck));
      document.querySelector('#playground').scrollIntoView({ behavior: 'smooth' });
    });
  });
  document.querySelectorAll('[data-view-script]').forEach((button) => {
    button.addEventListener('click', () => {
      showScript(button.dataset.viewScript);
      document.querySelector('#script-viewer').scrollIntoView({ behavior: 'smooth', block: 'start' });
    });
  });
  // The viewer works before the module loads and when it fails to.
  const firstScript = scriptForDeck(0);
  if (firstScript) showScript(firstScript);

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
    playBeep(460, 'sine', 0.04);
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

  toggleCrt.addEventListener('click', () => {
    document.body.classList.toggle('scanlines');
    const active = document.body.classList.contains('scanlines');
    toggleCrt.textContent = active ? 'CRT: ON' : 'CRT: OFF';
    toggleCrt.classList.toggle('active', active);
    playBeep(600, 'sine', 0.04);
  });

  toggleSound.addEventListener('click', () => {
    soundEnabled = !soundEnabled;
    toggleSound.textContent = soundEnabled ? 'AUDIO: ON' : 'AUDIO: MUTED';
    toggleSound.classList.toggle('active', soundEnabled);
    if (soundEnabled) playBeep(880, 'sine', 0.1, 0.2);
  });

  window.addEventListener('keydown', (event) => {
    if (event.target && ['INPUT', 'TEXTAREA'].includes(event.target.tagName)) return;
    if (event.key >= '1' && event.key <= '7') {
      event.preventDefault();
      loadDeck(Number(event.key) - 1);
    } else if (event.key === 'n' || event.key === 'N') {
      event.preventDefault();
      step();
    } else if (event.key === 's' || event.key === 'S') {
      event.preventDefault();
      catalyst();
    } else if (event.key === 'r' || event.key === 'R') {
      event.preventDefault();
      rewindTo(0);
    } else if (event.key === ' ') {
      event.preventDefault();
      togglePause();
    } else if (event.key === ',' || event.key === 'ArrowLeft') {
      event.preventDefault();
      rewindTo(currentTick() - 1);
    }
  });

  function loop(now) {
    if (exp && !paused && now - lastTickTime >= TICK_INTERVAL_MS) {
      exp.wasm_step_tick();
      lastTickTime = now;
      refresh();
    }
    requestAnimationFrame(loop);
  }

  async function boot() {
    try {
      if (typeof WebAssembly === 'undefined') throw new Error('WebAssembly is unavailable');
      const result = await WebAssembly.instantiate(decodeBase64(WASM_BASE64), {});
      exp = result.instance.exports;
      for (const name of [
        'wasm_init',
        'wasm_step_tick',
        'wasm_render_frame',
        'wasm_framebuffer_ptr',
        'wasm_framebuffer_len',
        'wasm_on_pointer_down',
        'wasm_on_key_down',
        'wasm_scrub_to_tick',
        'wasm_get_tick',
        'wasm_get_fact_count',
      ]) {
        if (typeof exp[name] !== 'function') throw new Error(`missing export ${name}`);
      }
      statusEl.textContent = 'bespoke-proofs.wasm ready. Seven proof decks embedded.';
      log('BOOT', 'Instantiated the embedded proof runtime.', 'cue');
      loadDeck(0);
      lastTickTime = performance.now();
      requestAnimationFrame(loop);
    } catch (error) {
      statusEl.textContent = `WebAssembly load failed: ${error.message}`;
      console.error(error);
    }
  }

  boot();
})();
