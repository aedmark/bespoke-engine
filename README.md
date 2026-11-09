# BeSpoke Engine

**A bespoke narrative and systemic simulation engine & language.**
*Engine-as-Spine Architecture · Custom Zig Bytecode VM · Relational & Temporal Primitives*

BeSpoke is a game development language and standalone simulation runtime designed from the ground up for systemic depth, emergent behavior, and whimsical narrative games. 

Drawing spiritual inspiration from the tight, deterministic simulation models of Chris Sawyer's *RollerCoaster Tycoon*, the actor/cue architecture of Sierra's *SCI* and LucasArts' *SCUMM*, and the emergent relationship graphs of *Dwarf Fortress*, BeSpoke treats **the language runtime as the spine of the engine**.

---

## Core Tenets

1. **Engine-as-Spine:** The Zig runtime is `main()`. It owns the master tick clock, entity lifecycles, spatial topology, and relational facts. Rendering and audio (Raylib, Sokol) are downstream, stateless display peripherals.
2. **Custom Bytecode VM:** A hand-written Zig compiler front-end compiles BeSpoke source code directly into compact bytecode. Instant compilation, sub-millisecond hot-reloading, and lightweight runtime execution.
3. **Flat Relational State with Built-in TTL:** No pointer graphs or nested object hierarchies. Facts are contiguous rows (`subject, relation, object, expires_at_tick`) stored in `std.MultiArrayList(Fact)`. Save states, time travel, and replays are pure `memcpy` operations.
4. **Temporal Primitives & Interrupt Stacks:** Built-in `wait`, `wait until`, and `interrupt ... with` eliminate state-machine boilerplate, frame timers, and callback spaghetti.

---

## Vertical Slice: The Tavern Heist

```
entity Guard, Bard, Cat, Cheese
relation Carries(holder, item)
relation CharmedBy(listener, musician)

remember Carries(Guard, Cheese)

routine Patrol(Guard):
  loop:
    walk Guard to Cellar
    wait 120 ticks
    walk Guard to Hearth
    wait 120 ticks

on cue PlayLute(Bard, target):
  if roll 2d6 >= 8:
    remember CharmedBy(target, Bard) for 180 ticks

when CharmedBy(listener, musician):
  interrupt listener with:
    face listener toward musician
    wait until not CharmedBy(listener, musician)

on cue Steal(Cat, victim) where CharmedBy(victim, _) and Carries(victim, loot):
  forget Carries(victim, loot)
  remember Carries(Cat, loot)
```

See [`script_spec.md`](script_spec.md) for the complete vertical slice specification.

---

## Quick Start & Interactive Vertical Slices

Build and run the BeSpoke Engine in interactive 60 Hz SDL2 graphical mode, headless verification mode, or compile to freestanding WebAssembly (`wasm32-freestanding`):

```bash
# Run the full test suite and WebAssembly build
zig build test
zig build wasm

# Run interactive or headless vertical slices
zig build run                                    # 1. The Tavern Heist (60 Hz GUI; add --headless for CLI)
zig build run -- --spitting-contest              # 2. Booty Island Spitting Contest
zig build run -- --gk3                           # 3. Gabriel Knight 3 Cat Moustache
zig build run -- --sword-fighting                # 4. Monkey Island Insult Sword Fighting
zig build run -- --village                       # 5. The Living Village (Emergent Sandbox)
zig build run -- --goat                          # 6. Broken Sword Lochmarne Goat
zig build run -- --dott                          # 7. Day of the Tentacle Trio
zig build run -- --darko                         # 8. The Middlesex Anomaly
zig build run -- --loom                          # 9. The Bell Tower (musical drafts on the distaff)

# Standalone script & binary package CLI toolchain
zig build run -- check scenarios/tavern_heist.bespoke
zig build run -- compile scenarios/tavern_heist.bespoke -o scenarios/tavern_heist.bspk
zig build run -- run scenarios/tavern_heist.bspk --headless
```

---

## Repository Documentation

BeSpoke adopts [The Manifold](docs/README.md) repository memory framework and the [3x Documentation Scheme](docs/manual.html) for durable, self-verifying engineering:

| Document | Purpose |
| :--- | :--- |
| [`AGENTS.md`](AGENTS.md) | Canonical instructions and standing conventions for coding agents |
| [`ROADMAP.md`](ROADMAP.md) | Stable-ID engineering phases and implementation tasks (`P1-01` .. `P19-03`) |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Component map, data flows, invariants, and trust boundaries |
| [`docs/DECISIONS.md`](docs/DECISIONS.md) | Append-only architectural decisions (`D-001` .. `D-022`), held tensions, and resolved questions (`Q-001` .. `Q-003`) |
| [`docs/HANDOFF.md`](docs/HANDOFF.md) | Current project state, verification tally, and session log |
| [`docs/TESTING.md`](docs/TESTING.md) | Verification suites, commands, and proof boundaries |
| [`docs/SECURITY.md`](docs/SECURITY.md) | Security model, bytecode/package/save bounds verification, and reporting |
| [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) | Contribution workflow for human and agent contributors |
| [`docs/CHANGELOG.md`](docs/CHANGELOG.md) | User-visible change notes |
| [`docs/manual.html`](docs/manual.html) | Standalone 3x What/How/Why interactive manual with embedded HTML5 Canvas simulator |
| [`site/index.html`](site/index.html) | Public showcase website with interactive retro EGA simulation playground |
| [`whitepaper.md`](whitepaper.md) | Original foundational vision whitepaper |

---

## Verifying Documentation

The project includes an invariant checker that verifies document consistency, link validity, and roadmap references:

```bash
python3 tools/check_docs.py
```
