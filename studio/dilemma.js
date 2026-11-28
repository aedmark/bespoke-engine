// BeSpoke Studio, the dilemma editor (P47-13, D-203): the Dilemmas window lists the script's
// dilemmas and edits one as a form holding every line of its block as written (actor, fires,
// trigger lines, weighs, tiers, leans, the five tier lines, drifts, appeals), with clauses as
// typed text. Apply rewrites the block whole, checked with the compiler before it is kept; a
// new dilemma starts from a template of the required lines. A preview gives the tier the actor
// lands in for two values and the leans that count, computed by the Studio module with the
// engine's own `dilemma.tier_in`. Red lines are a checklist in the Cast window (cast.js).
'use strict';

// eslint-disable-next-line no-unused-vars
function createDilemmas(desk, screen, hooks) {
  const TIERS = ['strong toward the first axis', 'moderate toward the first axis', 'neutral', 'moderate toward the second axis', 'strong toward the second axis'];
  const D = {
    listing: null,
    cast: null,
    selected: null, // a dilemma's name, or '' for a new one
    lines: [], // the form's lines, as text
    name: '',
    counting: new Set(), // the indexes of leans that count in the preview
    preview: null,
    error: '',
  };
  let win = null;
  const fields = {};

  function line(text, cls) {
    const row = document.createElement('div');
    row.className = `line ${cls || ''}`.trim();
    row.appendChild(desk.label(text));
    return row;
  }

  function cols() {
    return Math.max(12, Math.floor((win.rect.w - 16 * desk.px()) / (desk.advance * desk.px())));
  }

  function fit(text, n) {
    const chars = [...text];
    return chars.length <= n ? text : `${chars.slice(0, Math.max(1, n - 3)).join('')}...`;
  }

  function input(id, label, value) {
    const wrap = document.createElement('label');
    wrap.className = 'line field';
    if (label) wrap.appendChild(desk.label(label));
    const el = document.createElement('input');
    el.className = 'strgad';
    el.name = id;
    el.value = String(value);
    el.autocomplete = 'off';
    el.spellcheck = false;
    el.setAttribute('aria-label', label || id);
    el.onkeydown = (e) => e.stopPropagation();
    fields[id] = el;
    wrap.appendChild(el);
    return wrap;
  }

  function row(pairs) {
    const r = document.createElement('div');
    r.className = 'row';
    for (const [id, text, selected] of pairs) {
      const b = desk.button(win, id, text);
      if (selected) b.classList.add('selected');
      r.appendChild(b);
    }
    return r;
  }

  function refresh() {
    const r = hooks.listDilemmas();
    D.listing = r && r.valid ? r : null;
    const c = hooks.listCast();
    D.cast = c && c.valid ? c : null;
    return D.listing;
  }

  function current() {
    return D.listing && D.listing.dilemmas.find((x) => x.name === D.selected);
  }

  // A new dilemma's required lines, from the script's own axes and first cast member, for the
  // author to finish; the compiler names whatever is still missing at Apply.
  function template() {
    const axes = (D.cast && D.cast.axes.map((a) => a.name)) || [];
    const first = axes[0] || 'FirstAxis';
    const second = axes[1] || 'SecondAxis';
    const actor = (D.cast && D.cast.scenes.flatMap((s) => s.cast)[0]) || 'Someone';
    return [
      `actor ${actor}`,
      'fires Decided',
      'requires Fact(Thing)',
      `weighs ${first} against ${second}`,
      `strong ${first}: "..." -> ActionOne`,
      `moderate ${first}: "..." -> ActionTwo`,
      'neutral: "..." -> Wait',
      `moderate ${second}: "..." -> ActionThree`,
      `strong ${second}: "..." -> ActionFour`,
    ];
  }

  function select(name) {
    D.selected = name;
    D.preview = null;
    D.counting = new Set();
    D.error = '';
    if (name === '') {
      D.name = 'NewDilemma';
      D.lines = template();
    } else {
      const x = current();
      D.name = x ? x.name : '';
      D.lines = x ? x.lines.slice() : [];
    }
  }

  async function open() {
    if (!await hooks.ready('Dilemmas')) return null;
    const r = hooks.listDilemmas();
    if (r && !r.valid) { await hooks.showResult(r); return null; }
    refresh();
    if (!win) {
      const a = screen.area.getBoundingClientRect();
      win = desk.window(screen, {
        id: 'dilemmas', title: 'Dilemmas', x: Math.max(0, Math.min(140, a.width - 600)), y: 24, w: Math.min(600, a.width), h: Math.min(640, a.height - 24), minW: 240, minH: 220,
        onMessage: (msg) => handle(msg),
      });
    }
    if (D.selected === null && D.listing && D.listing.dilemmas.length) select(D.listing.dilemmas[0].name);
    render();
    win.toFront();
    win.activate();
    return win;
  }

  // The form's lines as they stand in the fields.
  function readLines() {
    const out = [];
    for (let i = 0; i < D.lines.length; i += 1) {
      const el = fields[`l${i}`];
      out.push(el ? el.value : D.lines[i]);
    }
    return out;
  }

  function render() {
    if (!win) return;
    for (const k of Object.keys(fields)) delete fields[k];
    const out = [];
    if (!D.listing) {
      out.push(line(fit('No listing: the main script did not check.', cols())));
      win.body.replaceChildren(...out);
      return;
    }
    const list = document.createElement('div');
    list.className = 'list cast-list';
    for (const x of D.listing.dilemmas) {
      const b = desk.button(win, `pick:${x.name}`, fit(`${x.name}: ${x.actor} weighs ${x.axis} against ${x.counter}`, cols() - 2), { cls: 'item' });
      if (x.name === D.selected) b.classList.add('selected');
      list.appendChild(b);
    }
    out.push(list, row([['new', 'New dilemma']]));
    if (D.selected !== null) {
      const scroll = document.createElement('div');
      scroll.className = 'cast-scroll';
      const parts = [input('name', 'Name', D.name)];
      D.lines.forEach((text, i) => {
        const r = document.createElement('div');
        r.className = 'row field-row';
        r.append(input(`l${i}`, '', text), desk.button(win, `del:${i}`, 'Remove'));
        parts.push(r);
      });
      parts.push(row([['add-line', 'Add line'], ['apply', 'Apply']]));
      const x = current();
      if (x && D.selected !== '') {
        // The preview, from the actor's starting values (D-203 item 3).
        const v = (axis) => {
          const found = D.cast && D.cast.values.find((y) => y.axis === axis && y.character === x.actor);
          return found ? found.value : 0;
        };
        parts.push(line(fit(`Preview: ${x.actor}'s values and the leans that count`, cols())));
        parts.push(input('pv-axis', x.axis, v(x.axis)));
        parts.push(input('pv-counter', x.counter, v(x.counter)));
        if (x.leans.length) {
          const r = document.createElement('div');
          r.className = 'row';
          x.leans.forEach((l, i) => {
            const b = desk.button(win, `lean:${i}`, `${l.points} toward ${l.toward}${l.unless ? ' (unless)' : ''}`);
            if (D.counting.has(i)) b.classList.add('selected');
            b.setAttribute('aria-pressed', String(D.counting.has(i)));
            r.appendChild(b);
          });
          parts.push(r);
        }
        parts.push(row([['preview', 'Preview']]));
        if (D.preview) {
          const p = D.preview;
          parts.push(line(fit(`Delta ${p.delta}: ${TIERS[p.tier]}`, cols())));
          parts.push(line(fit(`"${p.text}" -> ${p.action}`, cols())));
        }
      }
      if (D.error) parts.push(line(fit(D.error, cols()), 'err'));
      scroll.append(...parts);
      out.push(scroll);
    }
    win.body.replaceChildren(...out);
  }

  async function apply() {
    const name = fields.name.value.trim();
    const lines = readLines().map((t) => t.trim()).filter((t) => t);
    const x = current();
    if (x && x.comments && !D.commentsOk) {
      const pick = await desk.requester(win, {
        title: 'Dilemma', lines: [`The block for ${x.name} has comments.`, 'Apply rewrites the block whole, so they will be lost.'],
        buttons: [{ id: 'rewrite', label: 'Rewrite' }, { id: 'cancel', label: 'Cancel' }],
      });
      if (pick !== 'rewrite') return;
      D.commentsOk = true;
    }
    if (x && name !== x.name) {
      await desk.requester(win, { title: 'Dilemma', lines: ['Renaming a dilemma is not part of this editor; its name is fixed once written.'] });
      return;
    }
    const r = await hooks.writeDilemma([`dilemma\t${name}`, ...lines.map((t) => `line\t${t}`)].join('\n'));
    if (!r) return;
    if (!r.written) {
      D.lines = readLines();
      D.error = r.refused || (r.result && r.result.message) || 'the edit was refused';
      render();
      if (r.refused) await desk.requester(win, { title: 'Dilemma', tone: 'fault', lines: ['Nothing was written:', r.refused] });
      else await hooks.showResult(r.result);
      return;
    }
    refresh();
    select(name);
    render();
  }

  async function handle(msg) {
    if (msg.kind === 'close') { close(); return; }
    if (msg.kind === 'resize') { D.lines = D.selected !== null ? readLines() : D.lines; render(); return; }
    if (msg.kind !== 'gadget') return;
    const id = msg.id;
    if (id.startsWith('pick:')) { select(id.slice(5)); render(); return; }
    if (id === 'new') { select(''); render(); return; }
    if (id === 'add-line') { D.lines = [...readLines(), '']; render(); const el = fields[`l${D.lines.length - 1}`]; if (el) el.focus(); return; }
    if (id.startsWith('del:')) { const keep = readLines(); keep.splice(Number(id.slice(4)), 1); D.lines = keep; render(); return; }
    if (id === 'apply') { await apply(); return; }
    if (id.startsWith('lean:')) {
      D.lines = readLines();
      const i = Number(id.slice(5));
      if (D.counting.has(i)) D.counting.delete(i); else D.counting.add(i);
      render();
      return;
    }
    if (id === 'preview') {
      D.lines = readLines();
      const a = Number(fields['pv-axis'].value);
      const c = Number(fields['pv-counter'].value);
      if (!Number.isInteger(a) || !Number.isInteger(c)) { await desk.requester(win, { title: 'Preview', lines: ['Values are whole numbers.'] }); return; }
      let mask = 0;
      for (const i of D.counting) mask |= 1 << i;
      D.preview = hooks.previewTier(D.selected, a, c, mask >>> 0);
      render();
    }
  }

  function close() {
    if (win) win.close();
    win = null;
  }

  function reset() {
    D.listing = null;
    D.cast = null;
    D.selected = null;
    D.lines = [];
    D.preview = null;
    D.error = '';
    D.commentsOk = false;
    if (win) render();
  }

  async function relist() {
    if (!win) return;
    refresh();
    if (D.selected && !current()) D.selected = null;
    render();
  }

  return {
    open,
    reset,
    relist,
    state: () => ({ open: Boolean(win), selected: D.selected, lines: D.lines, preview: D.preview, error: D.error, dilemmas: D.listing ? D.listing.dilemmas.map((x) => x.name) : [] }),
    gadget: (id) => { if (win) win.port.post({ kind: 'gadget', id }); return Boolean(win); },
    field: (id, value) => { const el = fields[id]; if (!el) return false; el.value = value; return true; },
  };
}
