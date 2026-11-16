// The engine's synthesizer in the browser through an AudioWorklet (P34-05), replacing the
// deprecated ScriptProcessorNode (D-071). tools/build_site.py embeds this file ahead of the page
// script on the showcase and every proof page. The module renders samples on the main thread,
// where it lives; the worklet only plays what it is sent. The main thread keeps about a fifth of
// a second queued, so a slow frame does not starve the audio thread. The worklet is loaded from
// a data: URL, so the page stays one file and plays from file:// as well as over HTTP.
(() => {
  const PROCESSOR = `
class BespokeEnginePlayer extends AudioWorkletProcessor {
  constructor() {
    super();
    this.queue = [];
    this.offset = 0;
    this.port.onmessage = (event) => {
      if (event.data === 'clear') { this.queue = []; this.offset = 0; } else this.queue.push(event.data);
    };
  }
  process(inputs, outputs) {
    const left = outputs[0][0];
    const right = outputs[0][1] || left;
    let i = 0;
    while (i < left.length) {
      const chunk = this.queue[0];
      if (!chunk) { left.fill(0, i); right.fill(0, i); break; }
      const n = Math.min(left.length - i, chunk.left.length - this.offset);
      left.set(chunk.left.subarray(this.offset, this.offset + n), i);
      right.set(chunk.right.subarray(this.offset, this.offset + n), i);
      i += n;
      this.offset += n;
      if (this.offset >= chunk.left.length) { this.queue.shift(); this.offset = 0; }
    }
    return true;
  }
}
registerProcessor('bespoke-engine', BespokeEnginePlayer);
`;
  const AHEAD_SECONDS = 0.2;
  const CHUNK_FRAMES = 1024;
  const PUMP_MS = 25;

  window.BespokeEngineAudio = class {
    constructor(exports) {
      this.exp = exports;
      this.ctx = null;
      this.node = null;
      this.timer = null;
      this.loaded = false;
    }

    // Starts playback; call from a click, since browsers start audio only after one. Rejects
    // when the browser has no AudioWorklet (for example a page served over plain HTTP from
    // another machine, which is not a secure context).
    async start() {
      if (this.node) return;
      if (!this.ctx) this.ctx = new (window.AudioContext || window.webkitAudioContext)({ sampleRate: this.exp.wasm_audio_sample_rate() });
      if (this.ctx.state === 'suspended') await this.ctx.resume();
      if (!this.ctx.audioWorklet) throw new Error('this browser has no AudioWorklet');
      if (!this.loaded) {
        // A data: URL, not a Blob URL: a page opened from file:// has an opaque origin, and
        // Chrome refuses a worklet from its blob:null URL but loads one from data:.
        await this.ctx.audioWorklet.addModule('data:text/javascript;charset=utf-8,' + encodeURIComponent(PROCESSOR));
        this.loaded = true;
      }
      this.node = new AudioWorkletNode(this.ctx, 'bespoke-engine', { numberOfInputs: 0, outputChannelCount: [2] });
      this.node.connect(this.ctx.destination);
      this.startTime = this.ctx.currentTime;
      this.queued = 0;
      this.pump();
      this.timer = setInterval(() => this.pump(), PUMP_MS);
    }

    // Renders until the queue holds AHEAD_SECONDS past what has played. After a stall (a
    // background tab throttles timers) it drops the gap instead of playing stale sound late.
    pump() {
      if (!this.node) return;
      const rate = this.ctx.sampleRate;
      const played = (this.ctx.currentTime - this.startTime) * rate;
      if (this.queued < played) this.queued = played;
      while (this.queued - played < AHEAD_SECONDS * rate) {
        const pcm = new Int16Array(this.exp.memory.buffer, this.exp.wasm_audio_render(CHUNK_FRAMES), 2 * CHUNK_FRAMES);
        const left = new Float32Array(CHUNK_FRAMES);
        const right = new Float32Array(CHUNK_FRAMES);
        for (let i = 0; i < CHUNK_FRAMES; i++) {
          left[i] = pcm[2 * i] / 32768;
          right[i] = pcm[2 * i + 1] / 32768;
        }
        this.node.port.postMessage({ left, right }, [left.buffer, right.buffer]);
        this.queued += CHUNK_FRAMES;
      }
    }

    stop() {
      if (this.timer) clearInterval(this.timer);
      this.timer = null;
      if (this.node) {
        this.node.port.postMessage('clear');
        this.node.disconnect();
        this.node = null;
      }
    }

    get playing() {
      return this.node !== null;
    }
  };
})();
