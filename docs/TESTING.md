# Testing

How to run tests for the BeSpoke Engine, what each proves, and what it cannot. Read this before claiming anything works. The current verification results live in [HANDOFF.md](HANDOFF.md)'s "Current state".

## The Suites

| Suite | File / Command | Proves | Does not prove | Time, needs |
| --- | --- | --- | --- | --- |
| Documentation Invariants | `python3 tools/check_docs.py` | Internal consistency: references, roadmap items, decisions, links, handoff limits, and 3x manual validation | Code execution correctness | < 1s, Python 3 stdlib |
| 3x Manual Validation & Tests | `python3 tools/manual.py check scheme/bespoke.manual.json --check-evidence --root . && python3 -m unittest discover -s tests -v` | 3x What/How/Why schema conformance, evidence link validity, and manual generator unit tests | Graphical browser layout | < 1s, Python 3 stdlib |
| World Store Unit Tests | `zig test src/world.zig` | Fact insertion, TTL expiration pruning, queries, `memcpy` snapshots | VM execution or parser | < 2s, Zig compiler |
| VM & Fiber Scheduler Tests | `zig test src/vm.zig` | Bytecode dispatch, fiber yielding on `wait`, interrupt stack pushes | Spatial pathfinding | < 2s, Zig compiler |
| WebAssembly Target & Event Bridge | `zig test src/wasm.zig && zig build wasm` | `WasmCanvas` RGBA8888 framebuffer rendering, browser mouse/keyboard/touch event routing, and `wasm32-freestanding` binary compilation | Live DOM rendering | < 3s, Zig compiler |
| Separation Lint | `python3 tools/check_separation.py` (also inside `check_docs.py`); `--report` for every hit | Proof names in non-test `src/` code do not exceed `tools/separation_baseline.json` | That engine code is free of proof *logic* expressed without proof names; audits cover that | < 1s, Python 3 |
| Engine Tests | `zig build test-engine` | Every test reachable from `src/root.zig` and `src/main.zig` | Proof scenarios | < 5s, Zig compiler, SDL2 headers |
| Proof-of-Concept Tests | `zig build test-proofs` | Every proof's scripted run and rewind (`proofs/main.zig` imports each proof) | Engine internals not exercised by a proof | < 5s, Zig compiler, SDL2 headers |
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

- Where new checks go: unit tests belong in `test` blocks at the bottom of the relevant Zig source file (`src/world.zig`, `src/vm.zig`, `src/save.zig`, `src/wasm.zig`, etc.); documentation checks belong in `tools/check_docs.py` and `tests/test_manual.py`.
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
| Save / Load System (`src/save.zig`) | `zig test src/save.zig` | CRC32 corruption fallback test; quicksave verification |
| Audio Synthesizer (`src/audio.zig`) | `zig test src/audio.zig` | Offline PCM buffer test; headless fallback run |
| Emergent Village (`proofs/village.zig`) | `zig build test-proofs` | `zig build run-proof -- --village --headless` cascade run |
| WebAssembly Target (`src/wasm.zig`) | `zig test src/wasm.zig && zig build wasm` | Manual canvas simulator deck in `docs/manual.html` |
| Peripheral SDL2 Display (`src/display/`) | `zig test -lc -lSDL2 src/display.zig` | Interactive GUI run verifying 60 Hz rendering and controls |

## Manual Checks (Before a Release)

What only a person can check, and how. Record who checked what, where, and when in HANDOFF:

- Open each interactive vertical slice in desktop GUI mode (`zig build run`, `--spitting-contest`, `--gk3`, `--sword-fighting`, `--village`). Verify window scaling, 5-verb mouse cycling, and audio output.
- Scrub backward and forward across the interactive timeline scrubber (`[<]`, `[>]`, click scrubber) and verify instant visual replay and divergent timeline truncation.
- Toggle Pause & Save/Load drawer (`[P]`, `[F2]`, `[F3]`), save a slot, verify the 16x12 RGB332 graphical thumbnail, and load back.
- **HUD layout without a display:** render a frame offscreen and inspect the image. Write a small harness that calls `DisplayWindow.init`, fills a `RenderFrame`, calls `render_frame`, then `SDL_RenderReadPixels` and `SDL_SaveBMP`, and run it with `SDL_VIDEODRIVER=offscreen SDL_AUDIODRIVER=dummy zig run -I/usr/include/SDL2 -lc -lSDL2 --dep bespoke -Mroot=<harness>.zig -I/usr/include/SDL2 -Mbespoke=src/root.zig`. This checks layout only, not audio or input.
- Open `docs/manual.html` directly in a browser via `file://`; run the embedded interactive Wasm simulator deck (`#live-simulator`).

## Before Any Run

1. Ensure Python 3.9+ is available for documentation checks.
2. Ensure the Zig compiler (0.13.0+) is installed and accessible in `PATH`.
3. Verify that memory arenas tested for serialization do not allocate external heap memory outside their assigned arena buffer.

## Known Pitfalls

- **Timer sensitivity:** Ticks are discrete integer simulation increments, not wall-clock floats. Tests must increment ticks explicitly rather than calling sleep.
- **Snapshot validation:** Always test `restore_state` on a separate buffer to prove memory independence from the original arena.
- **Test filters and the root module:** `zig test src/root.zig --test-filter X` runs 0 tests, because the filter also drops the named test that imports every module. Filter through a file that imports what you need, e.g. `zig test -I/usr/include/SDL2 -lc -lSDL2 src/package.zig --test-filter P22-01`. Files under `src/compiler/` cannot be run alone (they import `../`).
- **Proof files cannot be tested alone:** files in `proofs/` import the engine as `@import("bespoke")`, a module only the build graph provides, so `zig test proofs/x.zig` fails. Use `zig build test-proofs`.
- **Headless runs read stdin:** scenario binaries wait for input after printing SUCCESS. Run them with `</dev/null` in scripts and loops.
- **Mutation check discipline:** A mutation check must break the fix, not the test. Reverting a whole file can fail a test for an unrelated reason. Remove just the fix.
