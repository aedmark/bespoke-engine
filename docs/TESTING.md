# Testing

How to run tests for the BeSpoke Engine, what each proves, and what it cannot. Read this before claiming anything works. The current verification results live in [HANDOFF.md](HANDOFF.md)'s "Current state".

## The Suites

| Suite | File / Command | Proves | Does not prove | Time, needs |
| --- | --- | --- | --- | --- |
| Documentation Invariants | `python3 tools/check_docs.py` | Internal consistency: references, roadmap items, decisions, links, handoff limits, and 3x manual validation | Code execution correctness | < 1s, Python 3 stdlib |
| 3x Manual & Site Tests | `python3 tools/manual.py check scheme/bespoke.manual.json --check-evidence --root . && python3 -m unittest discover -s tests -v` | 3x What/How/Why schema conformance, evidence link validity, and manual and showcase-site build unit tests | Graphical browser layout | < 1s, Python 3 stdlib |
| Showcase Site Build | `python3 tools/build_site.py --check` | `site/index.html` embeds the current `bespoke-proofs.wasm` and browser wrapper in one simulator region | Browser rendering or interaction | < 1s, built wasm artifact |
| World Store Unit Tests | `zig test src/world.zig` | Fact insertion, TTL expiration pruning, queries, `memcpy` snapshots | VM execution or parser | < 2s, Zig compiler |
| Temporal Snapshot Unit Tests | `zig test src/temporal_snapshot.zig` | Branch world, countdown, collapse state, teleology, and dream residue round-trip; corrupt branch headers are rejected (P31-04) | Save and timeline integration | < 2s, Zig compiler |
| VM & Fiber Scheduler Tests | `zig test src/vm.zig` | Bytecode dispatch, fiber yielding on `wait`, interrupt stack pushes | Spatial pathfinding | < 2s, Zig compiler |
| WebAssembly Target & Event Bridge | `zig test src/wasm.zig && zig build wasm wasm-proofs && node tools/wasm_smoke.js` | `WasmCanvas` rendering, browser event routing, deck loading and rules on neutral test decks; both modules build, instantiate in Node, and run every deck | A browser page; the showcase DOM controls | < 10s, Zig compiler; Node.js 18+ for the smoke check (optional) |
| Wasm Golden | `zig build test-proofs` (`proofs/wasm_golden_test.zig`) | Each proof deck, driven natively through a ten-step event script, shows the pixels, facts, ticks, and banners in `proofs/golden/wasm.txt` (P32-04) | The wasm32 build itself (see the smoke check) | < 1s |
| Separation Lint | `python3 tools/check_separation.py` (also inside `check_docs.py`); `--report` for every hit | Proof names in non-test `src/` code do not exceed `tools/separation_baseline.json` | That engine code is free of proof *logic* expressed without proof names; audits cover that | < 1s, Python 3 |
| Engine Tests | `zig build test-engine` | Every test reachable from `src/root.zig` and `src/main.zig` | Proof scenarios | < 5s, Zig compiler, SDL2 headers |
| Proof-of-Concept Tests | `zig build test-proofs` | Every proof's scripted run and rewind (`proofs/main.zig` imports each proof), and that each headless transcript matches `proofs/golden/<proof>.txt` (P32-07) | Engine internals not exercised by a proof | < 5s, Zig compiler, SDL2 headers |
| Render Goldens | `zig build test-proofs` (`proofs/render_golden_test.zig`) | Every proof scene, staged from its script, draws the pixels hashed in `proofs/golden/render.txt` in its default state and once per piece of proof status that changes it (P32-02a, P32-03a); each scene's save thumbnail hashes as recorded (P32-03d) | Combinations of status, HUD overlays beyond the countdown and collapse modal, input, audio; hashes are tied to the SDL build | about 7s, SDL2 library, no display |
| Audio Goldens | `zig build test-proofs` (`proofs/audio_golden_test.zig`) | Every effect, distaff note, and proof track renders offline to the samples hashed in `proofs/golden/audio.txt`, a crossfade too, and each proof scene picks its recorded track (P32-02d) | How it sounds through a real device; mixing of overlapping voices beyond one effect at a time | < 1s, no audio device |
| Full Engine Test Suite | `zig build test` | End-to-end integration across compiler, VM, and spatial graph | Peripheral display output (Raylib/Sokol) | < 5s, Zig compiler |

**The fast set** (before every commit):
```bash
python3 tools/check_docs.py          # includes the separation lint
zig test src/world.zig
```

**The full set** (before merging or cutting a release):
```bash
python3 tools/check_docs.py
zig build test
```

Expected results live in [HANDOFF.md](HANDOFF.md)'s "Verified" table, with the date and commit they were measured on. A count written anywhere else goes stale without anyone noticing: point to HANDOFF instead.

## Adding a Check

- Where new checks go: unit tests belong in `test` blocks at the bottom of the relevant Zig source file (`src/world.zig`, `src/vm.zig`, `src/save.zig`, `src/wasm.zig`, etc.); documentation checks belong in `tools/check_docs.py`, `tests/test_manual.py`, and `tests/test_site.py`.
- Assert on what happened (a fact in the arena, an entity coordinate reached, a return code or event emitted), not on words in a message: a message can mention the right word for the wrong reason.
- Before trusting a new check, make it fail: undo the fix (only the fix) and run it. A check that passes either way proves nothing.

## Runs That Vary

The BeSpoke core simulation spine is 100% deterministic (D-001): ticks are discrete integer counts, and PRNG rolls (e.g. `roll 2d6`) use deterministic seedable sequences. However, when testing emergent multi-agent simulations or asynchronous peripheral integrations:

- **Read the failure before blaming the code:** Say in the handoff whether a miss was engine logic, peripheral timing, or environment configuration.
- **To test how code handles rare edge cases:** Inject the condition directly (asserting the relational fact or error state into `World`) rather than waiting for low-probability rolls to trigger it.
- **Measure one case in isolation:** Run the specific scenario or unit test (`zig test src/world.zig`) before running the full battery.

## Change-to-Check Matrix

| Changed area | Minimum checks | Additional evidence |
| --- | --- | --- |
| Documentation only | `python3 tools/check_docs.py` | `python3 tools/manual.py check scheme/bespoke.manual.json --check-evidence --root .` |
| Relational Store (`src/world.zig`) | `zig test src/world.zig` | `zig build test` (mutation check on TTL decay or snapshot) |
| VM, Bytecode, Compiler (`src/vm.zig`, `src/compiler/`) | `zig test src/vm.zig`, `zig test src/compiler.zig` | `zig build test`, `bespoke check scenarios/tavern_heist.bespoke` |
| Spatial Graph (`src/spatial.zig`) | `zig test src/spatial.zig` | Waypoint pathfinding verification in headless scenarios |
| Agency (`src/agency.zig`) | `zig test src/agency.zig`, `zig test src/host.zig`, `zig test src/society.zig` (pursuit guard) | `zig test src/package.zig` (v9 round-trip, bad flag, v8 load); `zig test src/compiler.zig` (declaration and diagnostics) |
| Grid Overlay and Automata (`src/grid.zig`) | `zig test src/grid.zig`, `zig test src/spatial.zig`, `zig test src/host.zig` | `zig test src/package.zig` (v8 round-trip, corrupt cells, v6 and v7 loads); `zig test src/compiler.zig` (declaration, `place`, rates) |
| Save / Load System (`src/save.zig`) | `zig test src/save.zig` | CRC32 corruption fallback test; quicksave verification; version 1/2 compatibility and temporal envelope round-trip |
| Audio Synthesizer (`src/audio.zig`) | `zig test src/audio.zig` | Offline PCM buffer test; headless fallback run |
| Emergent Village (`proofs/village.zig`) | `zig build test-proofs` | `zig build run-proof -- --village --headless` cascade run |
| Dialogue Duel (`src/duel.zig`) | `zig build test-engine` | `zig build test-proofs` (sword-fighting golden) |
| WebAssembly Target (`src/wasm.zig`, `proofs/wasm_deck.zig`) | `zig test src/wasm.zig && zig build wasm wasm-proofs`, `zig build test-proofs` (wasm golden) | `node tools/wasm_smoke.js`, `python3 tools/build_site.py --check` |
| Peripheral SDL2 Display (`src/display/`) | `zig test -lc -lSDL2 src/display.zig` | Interactive GUI run verifying 60 Hz rendering and controls |

## Manual Checks (Before a Release)

What only a person can check, and how. Record who checked what, where, and when in HANDOFF:

- Open each interactive vertical slice in desktop GUI mode (`zig build run`, `--spitting-contest`, `--gk3`, `--sword-fighting`, `--village`). Verify window scaling, 5-verb mouse cycling, and audio output.
- Scrub backward and forward across the interactive timeline scrubber (`[<]`, `[>]`, click scrubber) and verify instant visual replay and divergent timeline truncation.
- In the Middlesex Anomaly, scrub across a temporal snapshot and load a save, then verify the tangent countdown, branch facts, and primary facts agree (P31-04).
- Toggle Pause & Save/Load drawer (`[P]`, `[F2]`, `[F3]`), save a slot, verify the 16x12 RGB332 graphical thumbnail, and load back.
- **HUD layout without a display:** render a frame offscreen and inspect the image. `DisplayWindow.init_offscreen` with `save_frame_bmp` does this from a test (P32-02a); the older route is a small harness that calls `DisplayWindow.init`, fills a `RenderFrame`, calls `render_frame`, then `SDL_RenderReadPixels` and `SDL_SaveBMP`, and run it with `SDL_VIDEODRIVER=offscreen SDL_AUDIODRIVER=dummy zig run -I/usr/include/SDL2 -lc -lSDL2 --dep bespoke -Mroot=<harness>.zig -I/usr/include/SDL2 -Mbespoke=src/root.zig`. This checks layout only, not audio or input.
- Run `python3 tools/manual.py build scheme/bespoke.manual.json --output docs/manual.html` and verify `docs/manual.html` opens cleanly in a browser via `file://` with search and navigation.
- Rebuild the showcase with `python3 tools/build_site.py`, open `site/index.html`, and exercise `#playground`: switch all seven decks, step, trigger a catalyst, pause and resume, scrub the recent-timeline window, and reset the deck. Check that the canvas renders and the host bridge log records the dispatches.

## Before Any Run

1. Ensure Python 3.9+ is available for documentation checks.
2. Ensure the Zig compiler (0.13.0+) is installed and accessible in `PATH`.
3. Verify that memory arenas tested for serialization do not allocate external heap memory outside their assigned arena buffer.

## Known Pitfalls

- **Timer sensitivity:** Ticks are discrete integer simulation increments, not wall-clock floats. Tests must increment ticks explicitly rather than calling sleep.
- **Snapshot validation:** Always test `restore_state` on a separate buffer to prove memory independence from the original arena.
- **Test filters and the root module:** `zig test src/root.zig --test-filter X` runs 0 tests, because the filter also drops the named test that imports every module. Filter through a file that imports what you need, e.g. `zig test -I/usr/include/SDL2 -lc -lSDL2 src/package.zig --test-filter P22-01`. Files under `src/compiler/` cannot be run alone (they import `../`).
- **Proof files cannot be tested alone:** files in `proofs/` import the engine as `@import("bespoke")`, a module only the build graph provides, so `zig test proofs/x.zig` fails. Use `zig build test-proofs`.
- **Golden mismatches:** a failing `test-proofs` run names the proof and first differing line and writes `proofs/golden/<proof>.actual.txt`. If the change is intended, regenerate with `zig build test-proofs -Dupdate-goldens` and review `git diff proofs/golden`. A later passing run served from the build cache does not delete a stale `.actual.txt`; it is gitignored, so remove it by hand.
- **Audio golden mismatches:** a failing run prints each differing line and writes `proofs/golden/audio.actual.txt`. The synth is integer arithmetic with a seeded noise generator, so a change is never machine noise.
- **Render golden mismatches:** a failing run names each changed scene and writes `proofs/golden/render.actual.txt` plus one `<proof>_<scene>.actual.bmp` per changed scene (gitignored). Look at the image before regenerating with `-Dupdate-goldens`. If every scene changes at once with no renderer change, suspect an SDL upgrade.
- **Headless runs read stdin:** scenario binaries wait for input after printing SUCCESS. Run them with `</dev/null` in scripts and loops.
- **Mutation check discipline:** A mutation check must break the fix, not the test. Reverting a whole file can fail a test for an unrelated reason. Remove just the fix.
