# Release Hand-Test Pass

The checks only a person can make before a release: play every proof, listen, drive the browser builds, run the template's CI on macOS and Windows, and publish the showcase. Automated suites are in [TESTING.md](../TESTING.md); this runbook starts where they stop. Roadmap item: P34-07.

Work through the sections in order. Each step says what to do and what you should see or hear. Tick the box, or write the failure in the results table at the end. A failure does not stop the pass: note it and move on, unless it blocks the steps after it.

Time: about four hours for everything, or about ninety minutes for sections 1, 2, 6, and 8 alone.

## 0. Prerequisites

- Linux x86_64 with Zig 0.13.0, Python 3.9+, Node.js 18+, and SDL2 (`libsdl2-dev` or your distribution's equivalent).
- Speakers or headphones. Set the volume low before the first sound check: the synthesizer has never been heard through real hardware.
- Firefox and a Chromium-based browser (Chrome, Chromium, or Edge). The desktop app's browser pane refuses service workers, so use a real browser for section 7.
- For section 9: a GitHub account and a new empty repository you are willing to push a sample game to.
- For section 8: access to your Neocities account, to upload `dist/site/` by hand.
- A clean `main`: `git status` shows nothing, and `git log -1` is the commit you are testing. Write that commit in the results table.

## 1. Automated Baseline

Run these first, so that a hand-test failure cannot be a build that was already broken.

```bash
python3 tools/check_docs.py
zig build test
zig build wasm wasm-proofs && node tools/wasm_smoke.js
python3 tools/build_site.py --check
python3 -m unittest discover -s tests
zig build test-template
```

- [ ] `check_docs.py` reports 0 errors.
- [ ] `zig build test` passes with the count in HANDOFF's Verified table.
- [ ] The smoke check prints `ok` for every deck and for `bespoke-proofs.wasm audio`.
- [ ] `build_site.py --check` is clean, and the unit tests pass.
- [ ] `test-template` passes (about a minute).

Then build the binaries the rest of the pass uses:

```bash
zig build && zig build proofs
```

## 2. Desktop Proofs

Start each proof with `zig-out/bin/bespoke-proofs --<flag>`. Before playing one, run it once with `--headless </dev/null` and read its last lines: that is the ending the window should reach.

### 2.1 Controls every proof shares

| Key | Action |
| --- | --- |
| Left click | Walk to a mark, or use the current verb on what you clicked |
| Right click | Cycle the verb |
| Space | Pause and resume |
| N | Step one tick while paused |
| `-` and `=` | Slower and faster |
| R | Rewind |
| Left and Right arrows | Scrub the timeline one tick |
| F1 or D | Debug overlay |
| P | Pause drawer (Save, Load, Resume, Quit, State tabs) |
| F2 / F3 | Open the drawer on Save / Load |
| F5 / F9 | Quick save / quick load |
| `` ` `` or Tab | Console (C also opens it, unless the proof uses C) |
| 1 to 9 | Answer an open dialogue |
| Esc | Dismiss a dialogue, or quit |

A proof's own keys come first, so a proof that binds D or C hides the debug or console shortcut on that letter. Use F1 and `` ` `` there.

### 2.2 Each proof

For every proof: reach the ending, then check the shared items in 2.3 at least once across the set.

| Flag | Proof's own keys | What to check |
| --- | --- | --- |
| `--tavern` | none | The Guard patrols, the Bard's lute charms him, the Cat takes the Cheese while he is distracted. Rewind mid-heist and watch it replay identically. |
| `--spitting-contest` | H horn, G drink, F flags, S spit | Each key's effect shows on stage and in speech; the winning spit needs all three plus the wind. |
| `--gk3` | H hotel, G garden, B bike shop, 0 scavenge, 1 to 8 steps | Scene changes redraw the room; the disguise combines across three scenes; the motorcycle is rented. |
| `--sword-fighting` | D duel Bob, C duel Carla, T talk to the barkeep, W wait 50 ticks | Answer insults with 1 to 5. A lost round teaches the comeback; a repeated question tires the opponent. |
| `--village` | S theft, F feast, G tip | Six villagers run their own days. After S, a witness talks, rumours spread, and the Sheriff arrests someone, with no key presses in between. |
| `--goat` | C courtyard, T crypt, 1 to 4 steps | The goat knocks George down on the way to the cellar until the rope is tangled on the plough. |
| `--dott` | 1 to 4 switch character | Items passed between eras arrive; a change in the past shows in the future. |
| `--darko` | V follow the conduit | The tangent countdown runs; closing the loop collapses the branch safely; letting it run out ends in the singularity. |
| `--loom` | C D E F G A B notes, Backspace clears | Notes sound and show on the distaff; a four-note draft weaves its effect; played backwards it does the opposite. |
| `--grog` | 1 pour A to B, 2 pour B to C, L unlock | Cups visibly degrade; a late pour spills; enough grog at the lock dissolves it. |
| `--atlantis` | 1 Wits, 2 Fists, 3 Team, T talk, S solve | Choosing a path locks the rival gates and prunes the dialogue. Play each of the three paths once. |
| `--grid` | 1 fill, 2 torch, 3 throw | Fire spreads on the grid, smoke follows, and water flows back down the corridor and puts it out. |
| `--observatory` | 1 search, 2 take, 3 read, 4 confront; Enter opens the command bar | Staff walk their routines and intercept you. Type commands (`go to the archive`, `take the slip`, `ask pell about the slip`); Up and Down recall history; an ambiguous noun asks which you meant. |

### 2.3 Shared features (check each in at least one proof)

- [ ] **Window scaling:** resize the window and maximise it; the stage scales without stretching text off screen.
- [ ] **Verbs:** right click cycles all five verbs; the cursor label follows.
- [ ] **Pause and step:** Space pauses; N advances exactly one tick (the tick counter moves by 1).
- [ ] **Speed:** `-` and `=` change the speed; the HUD shows the change.
- [ ] **Scrub:** pause, scrub back ten ticks with Left, then forward with Right. The stage replays exactly. Scrub back, then act: the future timeline is truncated and a new one starts.
- [ ] **Rewind:** R rewinds and the run replays the same way.
- [ ] **Saves:** F2, save to a slot; the slot shows a small colour thumbnail of the stage. Play on, then F3 and load it: the stage returns to the saved moment. Repeat with F5 and F9.
- [ ] **Temporal save (`--darko`):** save while the tangent branch is live, play on past the collapse, load. The countdown, branch facts, and primary facts agree with the moment of the save.
- [ ] **State inspector:** P, then Tab or click STATE. Arrows select, Enter centres, Backspace goes back, Home resets, F cycles the relation filter. Closing the drawer resumes play; the inspector never saves or loads.
- [ ] **Console (`--tavern`, `--spitting-contest`, `--village`, and `bespoke run`):** `` ` `` opens it; `help` lists the commands; `facts` lists the live world; `remember Carries(Cat, Cheese)` changes the stage on the next tick; `forget` undoes it.
- [ ] **Party HUD (`--dott`):** portraits show, and 1 to 4 switch the active character.

## 3. Listening Pass

Do this on real speakers or headphones, at low volume first.

- [ ] **Music:** every proof plays its own track; scene changes crossfade instead of cutting.
- [ ] **Effects:** clicks, pickups, the horn (`--spitting-contest`), sword clashes (`--sword-fighting`), and the sizzle (`--grog`, `--grid`) sound once per action, without clipping or crackle.
- [ ] **Distaff (`--loom`):** C to B play rising pitches; a woven draft plays its stinger.
- [ ] **Script scores:** `zig-out/bin/bespoke run scenarios/night_watch.bespoke` moves through Calm, Chase, Calm, Wind, Calm; each change is audible and the loop point is seamless.
- [ ] **Silence:** pausing stops nothing it should not (music may hold); quitting leaves no hanging note.
- [ ] Write down anything harsh, too loud, or out of tune, with the proof and tick.

## 4. Stock Runner and Scenarios

```bash
zig-out/bin/bespoke check scenarios/tavern_heist.bespoke
zig-out/bin/bespoke run scenarios/tavern_heist.bespoke
zig-out/bin/bespoke run scenarios/guard_patrol.bespoke
zig-out/bin/bespoke run scenarios/night_watch.bespoke
```

- [ ] `check` reports no errors.
- [ ] Each script runs in a window; speech banners appear and fade; dialogue answers work with clicks and number keys.
- [ ] The command bar (Enter) accepts a typed command for the first routine's actor.
- [ ] `bespoke compile scenarios/tavern_heist.bespoke -o /tmp/th.bspk`, then `bespoke run /tmp/th.bspk`, plays the same as the script.
- [ ] Follow one walkthrough in [`docs/AUTHORING.md`](../AUTHORING.md) by hand, typing the script yourself. The guide's quoted output matches what you see.

## 5. Starter Template (Linux)

In a scratch directory outside the repository:

```bash
<repo>/zig-out/bin/bespoke init demo --engine <repo>
cd demo
zig build test
zig build run
zig build -Dbundle -Doptimize=ReleaseSafe
zig build web && node web/smoke.js
```

- [ ] `init` refuses to run again over the existing `demo`.
- [ ] Tests pass; `zig build run` opens a window and the Keeper speaks with choices.
- [ ] The bundled executable runs from another directory with `scripts/` absent.
- [ ] Serve `zig-out/web/` with `python3 -m http.server`, open it in a browser, click a mark, answer a dialogue, and press Sound: on.

## 6. Browser Builds

### 6.1 The manual

- [ ] Open `docs/manual.html` from `file://` in Firefox and in Chromium. Search finds an entry; section navigation works; the embedded simulator runs.

### 6.2 The showcase page

Open `site/index.html` from `file://`, then again over HTTP (`python3 -m http.server -d site`), in both browsers.

- [ ] The playground loads with no console errors (open the developer tools).
- [ ] Number keys 1 to 9 and the tabs switch decks; all eleven decks load: Tavern, Spit, GK3, Village, Goat, DOTT, Grog, Insult Sword Fighting, Algiers, Middlesex, Bell Tower.
- [ ] In each deck: S plays a solve step and the stage advances; verbs fire on a click; a dialogue answers to number keys.
- [ ] Algiers: choosing a path with 1, 2, or 3 locks the others.
- [ ] Middlesex: the tick counter never runs backwards; a rewind across the collapse brings the branch back.
- [ ] Bell Tower: act on something, then C to B notes; the DISTAFF line shows notes, reach, and target, and the tower rings.
- [ ] Pause, step, rewind, scrub, and reset each work on the page.
- [ ] I opens the inspector over the stage, paused; its keys match the desktop's; closing resumes.
- [ ] AUDIO on: music and effects play; AUDIO off: silence. Switching decks with audio on does not stack two soundtracks.
- [ ] The script viewer follows the active deck and shows that proof's real script.
- [ ] Every gallery card's Play opens its deck; desktop-only cards (Castle Fire Escape, Larkspur Observatory) say so.
- [ ] The three diagrams render in light and dark mode.
- [ ] **Phone width:** in responsive mode at 375 px, nothing scrolls sideways; the canvas fits; tabs remain usable. Try a real phone if you have one, including touch on the canvas.
- [ ] Leave a deck running for ten minutes; the page stays responsive and memory in the task manager does not climb without limit.

## 7. Export and Offline Caching

```bash
python3 tools/deploy_site.py export --site-url https://<your-site>.neocities.org/
python3 -m http.server -d dist/site 8000
```

- [ ] Open `http://localhost:8000/` in Chromium. Developer tools, Application, Service Workers: `sw.js` is activated.
- [ ] Stop the server, reload: the page still loads from the cache and the playground runs.
- [ ] Restart the server, change nothing, export again, reload: no second cache appears. After a rebuild that changes the page, the old cache is replaced.
- [ ] View the page source: the OpenGraph and Twitter tags name your site URL.

## 8. Neocities Release

Upload `dist/site/index.html` and `dist/site/sw.js` from section 7 to your site by hand (D-074).

- [ ] Open the live site in a private window. The playground runs, audio plays after a click, and the service worker activates.
- [ ] The Manual link in the page header opens the manual. Upload `docs/manual.html` to `docs/manual.html` on the site: the export does not include it (Q-007).
- [ ] Share the URL in a link preview (a chat app, or an OpenGraph checker): the title and description show. The export adds no preview image, so none is expected.

## 9. macOS and Windows

The engine has no CI of its own; the starter template's GitHub Actions workflow covers Linux, macOS, Windows, and the web build.

1. Generate a project with `bespoke init` (section 5), `git init` it, commit, and push it to your new GitHub repository.
2. Open the repository's Actions tab and wait for the `build` workflow.

- [ ] The `native` job passes on `ubuntu-latest`, `macos-latest`, and `windows-latest`.
- [ ] The web job passes and its smoke check runs.
- [ ] If you have a Mac or a Windows machine: clone the engine, run `zig build test` and one proof in a window, and note the result. If not, write "CI only" in the results table.

The workflow fetches the engine from `main`, so a push to the engine repository changes what the next run tests. Pin `BESPOKE_ENGINE_REF` to the tested commit if you need a repeatable run.

## 10. Recording Results

Copy this table into HANDOFF's session log (the "Verified" table holds only the summary), fill it in, and date it.

| Section | Result | Notes (proof, tick, browser, OS) |
| --- | --- | --- |
| Commit tested | | |
| 1. Automated baseline | | |
| 2. Desktop proofs (13) | | |
| 2.3 Shared features | | |
| 3. Listening | | |
| 4. Stock runner | | |
| 5. Starter template | | |
| 6.1 Manual | | |
| 6.2 Showcase (Firefox / Chromium / phone) | | |
| 7. Export and offline | | |
| 8. Neocities release | | |
| 9. macOS / Windows | | |

For each failure:

- A defect with a clear fix becomes a fix with a check that fails without it.
- Anything larger becomes a roadmap item with its origin (`found during P34-07`) and an acceptance line.
- A failure you cannot reproduce goes in HANDOFF under Corrections, with what you saw and where.

When every row passes or has an item, mark P34-07 done in ROADMAP.
