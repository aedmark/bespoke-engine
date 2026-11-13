# BeSpoke Engine

**A small engine and scripting language for story-driven games, written in Zig.**

BeSpoke runs games where the story comes from rules interacting: a guard who gets distracted, a rumour that spreads, a cup that leaks on the way to the door. You write the game as a script of scenes, characters, facts, and rules. The engine plays it one tick at a time, the same way every run, and can rewind to any recent moment.

It suits point-and-click adventures and small simulations. It is not a 3D or physics engine.

Drawing spiritual inspiration from the tight, deterministic simulation models of Chris Sawyer's *RollerCoaster Tycoon*, the actor/cue architecture of Sierra's *SCI* and LucasArts' *SCUMM*, and the emergent relationship graphs of *Dwarf Fortress*, BeSpoke treats **the language runtime as the spine of the engine**.

---

## Core Tenets

1. **The engine runs the game; the screen only shows it (Engine-as-Spine).** The engine owns the clock, the characters, the map, and the facts. The window (SDL2 on the desktop, a canvas in the browser) and the audio draw and play what the engine reports, and pass player input back; they never change the world directly.
2. **Scripts compile to bytecode.** A hand-written compiler in Zig turns a `.bespoke` script into compact instructions for the engine's virtual machine (VM), either when the game starts or ahead of time into a checked `.bspk` package.
3. **The world is a table of facts.** Everything the game knows is a row of four values: `(subject, relation, object, expires_at_tick)`, such as "the Guard carries the Cheese". A fact with an expiry tick disappears on its own. The rows sit in four flat columns (`std.MultiArrayList(Fact)`) with no pointers, so a snapshot copies those columns and the name tables as raw bytes, and rewinding copies them back.
4. **Time is whole ticks.** A routine can `wait`, `wait until` a fact holds, or be interrupted by a rule and then resume where it paused. The clock counts whole ticks (one per second by default, adjustable while playing); nothing in the simulation depends on frame timing or fractional seconds.

---

## A First Script: The Tavern Heist

This is [`scenarios/tavern_heist.bespoke`](scenarios/tavern_heist.bespoke), runnable with the stock engine CLI:

```
scene Tavern:
  cast: Guard, Bard, Cat
  props: Fireplace, BarCounter, WineCask
  marks: Hearth, Bar, Cellar

relation Carries(holder, item)
relation CharmedBy(listener, musician)

entity Cheese

remember Carries(Guard, Cheese)

routine Patrol(Guard):
  walk Guard to Cellar
  wait 5 ticks
  walk Guard to Hearth

when CharmedBy(Guard, Bard):
  interrupt Guard with:
    face Guard toward Bard
    wait 4 ticks

when Carries(Cat, Cheese):
  interrupt Guard with:
    face Guard toward Cat
    wait 2 ticks
```

```bash
zig build run -- run scenarios/tavern_heist.bespoke --headless
```

Read it as: the Guard patrols; if the Bard charms him, or the Cat gets the Cheese, he stops to look before carrying on. The language also covers dialogue choices, several scenes, combining items, what characters believe, and short melodies that act as spells (`draft Kindle(C, D, E, C) reverse Douse`, `weave Kindle on Brazier`). See the [authoring guide](docs/AUTHORING.md), the [script reference](script_spec.md), the [manual](docs/manual.html), and the [glossary](docs/GLOSSARY.md) for the terms used here.

---

## What the Engine Provides

| Area | Highlights |
| --- | --- |
| Relational spine | Facts in one fixed memory block, expiry ticks, single-value properties, multi-clause pattern queries, raw-byte snapshots with a checksum |
| VM & fibers | Cooperative routines, `wait` / `wait until`, priority interrupts, edge-triggered `when` rules |
| Language | Hand-written lexer, parser, and code generator; `bespoke check` diagnostics with line and column |
| Spatial | Waypoint graphs, A* pathfinding, scene partitioning, hotspots, portals |
| Narrative | Dialogue choices pruned by facts, NPC beliefs, item combining and transfer, musical drafts on a distaff |
| Emergent society | Autonomous needs-driven agents, witnesses, rumor spread, and justice cascades over the fact store, configured per game: any roster, needs, roles, and places (`src/society.zig`) |
| Time | Rewind and timeline scrubbing; temporary branch worlds on a countdown (`TemporalHypervisor`) |
| Peripherals | SDL2 window with verb bar and HUD, procedural chiptune audio, CRC32-checked `.sav` slots, `wasm32-freestanding` target |

---

## Quick Start

```bash
# Engine and proof tests, and the WebAssembly builds
zig build test
zig build wasm wasm-proofs
python3 tools/build_site.py

# The engine CLI: run, compile, and check scripts
zig build run -- check scenarios/tavern_heist.bespoke
zig build run -- compile scenarios/tavern_heist.bespoke -o scenarios/tavern_heist.bspk
zig build run -- run scenarios/tavern_heist.bspk --headless

# Start your own game beside this checkout, then build and test it
./zig-out/bin/bespoke init lighthouse
cd lighthouse && zig build test && zig build run
```

To write your own story, follow the [authoring guide](docs/AUTHORING.md): scenes, dialogue, reactive puzzles, testing, and the host API.

The repository has three layers:

| Path | What it is |
| --- | --- |
| `src/` | The engine, exported as the `bespoke` module and built as the `bespoke` CLI |
| `scenarios/` | Sample `.bespoke` scripts: game content the stock CLI runs |
| `proofs/` | Proofs of concept: Zig programs that drive the engine to demonstrate a feature end to end, built as `bespoke-proofs` |

---

## Proofs of Concept

Each proof is a small playable scene that shows an engine feature working end to end. It runs headless (no window) and checks its own outcome, and it opens in the SDL2 window for play. Twelve of the thirteen also rewind and check that the world matches; Algiers does not yet. Proofs depend on the engine; the engine never imports a proof (the compiler enforces this, see [D-031](docs/DECISIONS.md)).

```bash
zig build run-proof -- --loom             # interactive
zig build run-proof -- --loom --headless  # scripted verification
zig build test-proofs                     # every proof's tests
```

| Flag | Proof | Demonstrates |
| --- | --- | --- |
| `--tavern` (default) | The Tavern Heist | Facts, a patrolling routine, rules that interrupt it, rewind |
| `--spitting-contest` | Booty Island Spitting Contest | Rules that fire when a fact stops holding or expires |
| `--gk3` | Gabriel Knight 3: The Cat Moustache | Several scenes; combining items in the inventory |
| `--sword-fighting` | Insult Sword Fighting | Replies learned during play; characters tire of repeated questions |
| `--village` | The Living Village | The society mechanic: six villagers with needs, rumours, and an arrest |
| `--goat` | Broken Sword: The Lochmarne Goat | A hazard that interrupts the player, timed windows, moving down to a new scene |
| `--dott` | Day of the Tentacle Trio | Three playable characters, items passed between them, the past changing the future |
| `--darko` | The Middlesex Anomaly | A temporary copy of the world on a countdown that merges back or collapses |
| `--loom` | The Bell Tower | Four-note tunes (drafts) that act as spells, forwards or reversed |
| `--grog` | Caustic Grog | Containers that wear out, pouring between them, spilling while carried |
| `--atlantis` | The Fate of Atlantis: Algiers | Three routes through one puzzle; choosing one locks the others and limits the dialogue |
| `--grid` | The Castle Fire Escape | Fire, smoke, and water spreading across a grid of cells |
| `--observatory` | The Larkspur Observatory | Characters with goals who chase and intercept the player; typed commands |

---

## Known Limitations

- `where` guards on `on cue` handlers are parsed but not evaluated, and the compiler accepts them without a warning, so the handler runs whether or not the guard holds. Dialogue-choice `where` guards and `when` rule patterns are evaluated. Put the check inside the handler with `if`.
- Cue handler parameters such as `target` in `on cue PlayLute(Bard, target):` match any entity but are not bound to it in the body.
- A society has one enforcer.
- The Bell Tower, Caustic Grog, and Algiers windows have not been hand-played on a desktop, and the Castle Fire Escape has not been replayed since its speech fix; macOS and Windows builds have never run (the template's CI workflow is untested). See [Phase 34](ROADMAP.md) and the [release hand-test](docs/runbooks/release-hand-test.md).
- The showcase site embeds `bespoke-proofs.wasm`, so its eleven decks run their proofs' scripts in the real browser runtime from `file://`, with the engine's own audio; the manual is a static reference and no longer bundles the module (`D-047`). Run `zig build wasm-proofs` before `python3 tools/build_site.py`. The Castle Fire Escape and The Larkspur Observatory are desktop-only for now.

---

## Repository Documentation

The [documentation map](docs/README.md) says which document owns which fact. The [manual](docs/manual.html) answers What, How, and Why for each component and links the code that backs it.

| Document | Purpose |
| :--- | :--- |
| [`AGENTS.md`](AGENTS.md) | Canonical instructions and standing conventions for coding agents |
| [`ROADMAP.md`](ROADMAP.md) | Planned and finished work by phase, with stable IDs (`P<phase>-<nn>`) |
| [`docs/AUTHORING.md`](docs/AUTHORING.md) | Authoring guide: scenes, dialogue, reactive puzzles, testing, and the host API |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Component map, data flows, invariants, and trust boundaries |
| [`docs/DECISIONS.md`](docs/DECISIONS.md) | Append-only design decisions (`D-NNN`), held tensions, and open questions (`Q-NNN`) |
| [`docs/GLOSSARY.md`](docs/GLOSSARY.md) | Plain-language definitions of the project's terms, and which word to use |
| [`docs/HANDOFF.md`](docs/HANDOFF.md) | Current project state, verification tally, and session log |
| [`docs/TESTING.md`](docs/TESTING.md) | Verification suites, commands, and proof boundaries |
| [`docs/SECURITY.md`](docs/SECURITY.md) | Security model, bytecode/package/save bounds verification, and reporting |
| [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) | Contribution workflow for human and agent contributors |
| [`docs/CHANGELOG.md`](docs/CHANGELOG.md) | User-visible change notes |
| [`docs/manual.html`](docs/manual.html) | Standalone interactive 3x What/How/Why manual and developer guide |
| [`site/index.html`](site/index.html) | Public showcase website with the embedded proof WebAssembly playground |
| [`whitepaper.md`](whitepaper.md) | The original vision statement (2026-11-04), kept as written |

---

## Verifying Documentation

The project includes an invariant checker that verifies document consistency, link validity, and roadmap references:

```bash
python3 tools/check_docs.py
```
