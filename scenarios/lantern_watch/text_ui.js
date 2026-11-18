  const transcript = document.getElementById('transcript');
  const turns = document.getElementById('turns');
  const command = document.getElementById('command');
  const map = document.getElementById('watch-map');
  const mapToggle = document.getElementById('map-toggle');
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();

  function showLine(text, kind) {
    const atEnd = transcript.scrollHeight - transcript.scrollTop - transcript.clientHeight < 12;
    const row = document.createElement('p');
    row.className = kind;
    row.textContent = text;
    turns.append(row);
    if (turns.childElementCount > 200) turns.firstElementChild.remove();
    if (atEnd || kind === 'command') transcript.scrollTop = transcript.scrollHeight;
  }

  function drainText() {
    const len = w.watch_text_len();
    if (!len) return;
    const text = decoder.decode(new Uint8Array(w.memory.buffer, w.watch_text_ptr(), len));
    w.watch_text_clear();
    for (const line of text.trimEnd().split('\n')) if (line) showLine(line, 'story');
  }

  document.getElementById('command-form').addEventListener('submit', e => {
    e.preventDefault();
    if (!started) return;
    const line = command.value.trim();
    if (!line) return;
    command.value = '';
    showLine('> ' + line, 'command');
    const bytes = encoder.encode(line);
    if (bytes.length > w.watch_input_capacity()) {
      showLine('That command is too long.', 'story');
      return;
    }
    new Uint8Array(w.memory.buffer, w.watch_input_ptr(), bytes.length).set(bytes);
    w.wasm_deck_action(bytes.length);
    draw();
  });

  mapToggle.addEventListener('click', () => {
    map.hidden = !map.hidden;
    mapToggle.setAttribute('aria-expanded', String(!map.hidden));
    mapToggle.textContent = map.hidden ? 'Show map' : 'Hide map';
    draw();
  });
