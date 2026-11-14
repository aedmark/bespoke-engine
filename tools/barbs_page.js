// Browser wrapper for the standalone Brackwater Barbs page (D-086).
// tools/build_site.py embeds this file and bespoke-proofs.wasm into site/barbs.html. The page
// plays one deck, the duel proof; the deck itself (proofs/wasm_deck.zig) runs the proof's own
// script and duel, so this wrapper holds no game content.
(() => {
  const canvas = document.querySelector('#barbs-canvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  if (!ctx) return;
  const statusEl = document.querySelector('#barbs-status');
  const btnDuel = document.querySelector('#btn-duel');
  const btnRestart = document.querySelector('#btn-restart');
  const btnSound = document.querySelector('#btn-sound');
  const verbButtons = [...document.querySelectorAll('[data-verb]')];

  // The duel proof's index in the proof module's deck table (proofs/wasm_deck.zig).
  const BARBS_DECK = 7;
  const TICK_INTERVAL_MS = 1000;
  const VERBS = ['WALK', 'LOOK', 'TALK', 'TAKE', 'USE'];
  const WASM_BASE64 = '__BESPOKE_PROOFS_WASM_BASE64__';

  let exp = null;
  let lastTickTime = 0;
  let audioCtx = null;
  let engineNode = null;
  let soundOn = false;

  function decodeBase64(value) {
    const binary = atob(value);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  }

  function draw() {
    if (!exp) return;
    exp.wasm_render_frame();
    const pixels = new Uint8ClampedArray(exp.memory.buffer, exp.wasm_framebuffer_ptr(), exp.wasm_framebuffer_len());
    ctx.putImageData(new ImageData(pixels, 640, 360), 0, 0);
  }

  // The verb bar in the canvas and the buttons under it select the same verb; the canvas
  // keeps the truth, so a click on either sends the click to the runtime.
  function selectVerb(index) {
    if (!exp) return;
    exp.wasm_on_pointer_down(12 + index * 58 + 26, 338);
    verbButtons.forEach((b, i) => b.classList.toggle('active', i === index));
    draw();
  }

  function restart() {
    if (!exp) return;
    exp.wasm_init(BARBS_DECK);
    lastTickTime = performance.now();
    selectVerb(2);
  }

  function key(code) {
    if (!exp) return;
    exp.wasm_on_key_down(code);
    lastTickTime = performance.now();
    draw();
  }

  // The engine's own synthesizer: the proof's soundtrack and effects, started on a click
  // because browsers block audio until the page is touched.
  function startSound() {
    try {
      if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)({ sampleRate: exp.wasm_audio_sample_rate() });
      if (audioCtx.state === 'suspended') audioCtx.resume();
      engineNode = audioCtx.createScriptProcessor(4096, 0, 2);
      engineNode.onaudioprocess = (event) => {
        const frames = event.outputBuffer.length;
        const pcm = new Int16Array(exp.memory.buffer, exp.wasm_audio_render(frames), 2 * frames);
        const left = event.outputBuffer.getChannelData(0);
        const right = event.outputBuffer.getChannelData(1);
        for (let i = 0; i < frames; i++) {
          left[i] = pcm[2 * i] / 32768;
          right[i] = pcm[2 * i + 1] / 32768;
        }
      };
      engineNode.connect(audioCtx.destination);
    } catch (_) {
      // Sound is optional; a blocked AudioContext must not stop the game.
    }
  }

  function stopSound() {
    if (engineNode) engineNode.disconnect();
    engineNode = null;
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
      VERBS.forEach((_, i) => {
        const left = 12 + i * 58;
        if (x >= left && x <= left + 52) verbButtons.forEach((b, j) => b.classList.toggle('active', j === i));
      });
    }
    draw();
  });
  canvas.addEventListener('contextmenu', (event) => {
    event.preventDefault();
    if (!exp) return;
    exp.wasm_on_right_click(0, 0);
    draw();
  });

  window.addEventListener('keydown', (event) => {
    if (!exp) return;
    const pending = exp.wasm_message_pending && exp.wasm_message_pending();
    const open = exp.wasm_dialogue_open && exp.wasm_dialogue_open();
    if (pending && (event.key === 'Enter' || event.key === ' ' || event.key === 's' || event.key === 'S')) {
      event.preventDefault();
      key(13);
    } else if (event.key >= '1' && event.key <= '9') {
      // The number keys answer the duel; with no duel open they do nothing here, since this
      // page holds one deck.
      event.preventDefault();
      if (open && !pending) key(event.key.charCodeAt(0));
    } else if (event.key === 's' || event.key === 'S') {
      // [S] would answer an open duel with its first line; here it only starts the next duel.
      event.preventDefault();
      if (!open) key(83);
    } else if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
    }
  });

  btnDuel.addEventListener('click', () => {
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

  function loop(now) {
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
