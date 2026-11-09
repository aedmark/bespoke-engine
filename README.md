# BeSpoke Engine

**A bespoke narrative and systemic simulation engine & language.**
*Engine-as-Spine Architecture · Custom Zig Bytecode VM · Relational & Temporal Primitives*

BeSpoke is a game development language and standalone simulation runtime designed from the ground up for systemic depth, emergent behavior, and whimsical narrative games.

Drawing spiritual inspiration from the tight, deterministic simulation models of Chris Sawyer's *RollerCoaster Tycoon*, the actor/cue architecture of Sierra's *SCI* and LucasArts' *SCUMM*, and the emergent relationship graphs of *Dwarf Fortress*, BeSpoke treats **the language runtime as the spine of the engine**.

---

## Core Tenets

1. **Engine-as-Spine:** The Zig runtime is `main()`. It owns the master tick clock, entity lifecycles, spatial topology, and relational facts. Rendering and audio (an SDL2 desktop window, or a WebAssembly canvas in the browser) are downstream, read-only peripherals.
2. **Custom Bytecode VM:** A hand-written Zig compiler front-end compiles BeSpoke source directly into compact bytecode, in process or ahead of time into `.bspk` packages.
3. **Flat Relational State with Built-in TTL:** No pointer graphs or nested object hierarchies. Facts are contiguous rows (`subject, relation, object, expires_at_tick`) stored in `std.MultiArrayList(Fact)`. Save states, time travel, and replays are pure memory copies.
4. **Temporal Primitives & Interrupt Stacks:** Built-in `wait`, `wait until`, and `interrupt ... with` replace state-machine boilerplate, frame timers, and callback spaghetti. The clock is a discrete integer tick (1 Hz narrative base rate, adjustable at runtime); there is no floating-point delta time.

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

The language also covers dialogue choice trees, multi-scene staging, item combining, epistemic beliefs, and musical drafts (`draft Kindle(C, D, E, C) reverse Douse`, `weave Kindle on Brazier`). See [`script_spec.md`](script_spec.md) and the [3x manual](docs/manual.html).

---

## What the Engine Provides

| Area | Highlights |
| --- | --- |
| Relational spine | Contiguous fact arena, TTL expiry, functional properties, multi-clause pattern joins, `memcpy` snapshots |
| VM & fibers | Cooperative routines, `wait` / `wait until`, priority interrupts, edge-triggered `when` rules |
| Language | Hand-written lexer, parser, and code generator; `bespoke check` diagnostics with line and column |
| Spatial | Waypoint graphs, A* pathfinding, scene partitioning, hotspots, portals |
| Narrative | Dialogue choices pruned by facts, NPC beliefs, item combining and transfer, musical drafts on a distaff |
| Emergent society | Autonomous needs-driven agents, witnesses, rumor spread, and justice cascades over the fact store; being generalized into a scalable, themeable engine module (P32-05) |
| Time | Rewind and timeline scrubbing; copy-on-write tangent worlds (`TemporalHypervisor`) |
| Peripherals | SDL2 window with verb bar and HUD, procedural chiptune audio, CRC32-checked `.sav` slots, `wasm32-freestanding` target |

---

## Quick Start

```bash
# Engine and proof tests, and the WebAssembly build
zig build test
zig build wasm

# The engine CLI: run, compile, and check scripts
zig build run -- check scenarios/tavern_heist.bespoke
zig build run -- compile scenarios/tavern_heist.bespoke -o scenarios/tavern_heist.bspk
zig build run -- run scenarios/tavern_heist.bspk --headless
```

The repository has three layers:

| Path | What it is |
| --- | --- |
| `src/` | The engine, exported as the `bespoke` module and built as the `bespoke` CLI |
| `scenarios/` | Sample `.bespoke` scripts: game content the stock CLI runs |
| `proofs/` | Proofs of concept: Zig programs that drive the engine to demonstrate a feature end to end, built as `bespoke-proofs` |

---

## Proofs of Concept

Each proof is an empirical demonstration that an engine feature works as advertised: it runs headless with scripted assertions and a rewind check, and interactively in the SDL2 window. Proofs depend on the engine; the engine never imports a proof (the compiler enforces this, see [D-031](docs/DECISIONS.md)).

```bash
zig build run-proof -- --loom             # interactive
zig build run-proof -- --loom --headless  # scripted verification
zig build test-proofs                     # every proof's tests
```

| Flag | Proof | Demonstrates |
| --- | --- | --- |
| `--tavern` (default) | The Tavern Heist | Relational spine, patrol fibers, reactive interrupts, rewind |
| `--spitting-contest` | Booty Island Spitting Contest | Stageplay DSL, falling-edge and TTL-expiry triggers |
| `--gk3` | Gabriel Knight 3: The Cat Moustache | Multi-scene staging, in-hand item crafting |
| `--sword-fighting` | Insult Sword Fighting | Relational dialogue learning, repetition fatigue with mood decay |
| `--village` | The Living Village | The emergent society mechanic, themed as a six-villager settlement |
| `--goat` | Broken Sword: The Lochmarne Goat | Threat-radius interrupts, timed retreat windows, scene descent |
| `--dott` | Day of the Tentacle Trio | Party switching, conserved item transfer, cross-era causality |
| `--darko` | The Middlesex Anomaly | Copy-on-write tangent worlds, countdown budgets, path conduits |
| `--loom` | The Bell Tower | Musical drafts, reversed drafts, distaff reach, in-script weaves |

---

## Known Limitations

- `where` guards on `on cue` handlers are parsed but not yet evaluated (dialogue-choice `where` guards and `when` rule patterns are). Use `if` checks inside cue handlers.
- The emergent society simulation currently lives with its proof in `proofs/village.zig` and hardcodes that settlement; P32-05 moves a data-driven version into the engine.
- Some engine files still name proof content (renderer themes, music tracks, status flags). Removing it is planned as P32-02 to P32-04 in the [roadmap](ROADMAP.md).
- The browser simulator embedded in the manual hosts six proofs; Insult Sword Fighting, The Middlesex Anomaly, and The Bell Tower are desktop-only for now.

---

## Repository Documentation

BeSpoke adopts [The Manifold](docs/README.md) repository memory framework and the [3x Documentation Scheme](docs/manual.html) for durable, self-verifying engineering:

| Document | Purpose |
| :--- | :--- |
| [`AGENTS.md`](AGENTS.md) | Canonical instructions and standing conventions for coding agents |
| [`ROADMAP.md`](ROADMAP.md) | Stable-ID engineering phases and implementation tasks (`P1-01` .. `P32-04`) |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Component map, data flows, invariants, and trust boundaries |
| [`docs/DECISIONS.md`](docs/DECISIONS.md) | Append-only architectural decisions (`D-001` .. `D-031`), held tensions, and resolved questions (`Q-001` .. `Q-003`) |
| [`docs/HANDOFF.md`](docs/HANDOFF.md) | Current project state, verification tally, and session log |
| [`docs/TESTING.md`](docs/TESTING.md) | Verification suites, commands, and proof boundaries |
| [`docs/SECURITY.md`](docs/SECURITY.md) | Security model, bytecode/package/save bounds verification, and reporting |
| [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) | Contribution workflow for human and agent contributors |
| [`docs/CHANGELOG.md`](docs/CHANGELOG.md) | User-visible change notes |
| [`docs/manual.html`](docs/manual.html) | Standalone 3x What/How/Why manual with an embedded WebAssembly simulator |
| [`site/index.html`](site/index.html) | Public showcase website with a JavaScript simulation playground |
| [`whitepaper.md`](whitepaper.md) | Original foundational vision whitepaper |

---

## Verifying Documentation

The project includes an invariant checker that verifies document consistency, link validity, and roadmap references:

```bash
python3 tools/check_docs.py
```
