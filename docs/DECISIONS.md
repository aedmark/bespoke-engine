# Decisions

Short, append-only record of choices that a future session might otherwise re-litigate. One entry per decision.
Newest at the bottom. To reverse a decision, add a new entry that supersedes it; the old one keeps its text and only
its status changes ("superseded by D-MMM"). An "Update, same session" note at the end of an entry is fine while it is
still on the working branch.

Format:

```
## D-NNN Title  (YYYY-MM-DD, status: proposed | accepted | rejected | superseded by D-MMM)
**Context:** why this came up.
**Decision:** what we chose.
**Alternatives:** what else was considered, and why not.
**Consequences:** what it costs or constrains; what was left out and why.
**Review trigger:** an event that should cause reconsideration. Optional.
```

---

## D-001 Unified Engine-as-Spine Architecture (2026-11-04, status: accepted)
**Context:** Debated whether BeSpoke should be a drop-in behavioral script plugin for external general-purpose engines (Godot, Unity, Unreal) or an independent engine runtime.
**Decision:** Build BeSpoke as a unified standalone engine runtime where the language runtime is `main()` and owns simulation state, ticks, and spatial topology.
**Alternatives:**
- Drop-in decision box / plugin for Godot or Unity: rejected due to the "split-brain" dual-truth problem, heavy FFI glue code tax, and having to nerf high-level spatial semantics like `walk` to the lowest common denominator across disparate physics/gravity setups.
- Text-only narrative plugin (Ink/Yarn model): rejected because our target is embodied systemic and physical agent simulation, not dialogue trees.
**Consequences:** We must implement our own discrete spatial model (node/waypoint graphs or tilemaps) and a downstream display bridge (Raylib/Sokol), but we gain absolute simulation determinism, zero-cost memory snapshot saves, time-travel debugging, and pristine domain-level verbs.

## D-002 Custom Bytecode VM in Zig (2026-11-04, status: accepted)
**Context:** Need a fast, lightweight, self-contained compilation and runtime environment without multi-gigabyte compiler toolchains.
**Decision:** Implement both the compiler front-end and the execution virtual machine in Zig, compiling source directly to a custom, compact bytecode.
**Alternatives:**
- Heavyweight optimizing compiler backend: rejected because of slow compilation times, heavy dependencies, and bloated binary footprints.
- Embed Lua or WASM: rejected because we require direct control over memory layout arenas, custom fiber stacks, and cache-coherent Structure-of-Arrays (SoA) fact storage.
**Consequences:** Hand-written lexer, parser, and bytecode emitter are required; in return, we get sub-millisecond compile times, instant script reloading, and zero external build dependencies beyond the Zig compiler.

## D-003 Flat Relational Fact Model with Built-in Expiration (2026-11-04, status: accepted)
**Context:** Entities in systemic narrative games need rich dynamic relationships (possession, moods, temporary status effects, charm, alerts) without complex pointer graphs or GC fragmentation.
**Decision:** All mutable game state is represented as flat 4-tuple relational facts: `(subject: EntityId, relation: RelationKind, object: EntityId, expires_at_tick: u64)`, stored contiguously in a Zig `std.MultiArrayList(Fact)`. State changes occur via declarative `remember` and `forget`. Temporary effects specify `for N ticks`, setting `expires_at_tick = current_tick + N`.
**Alternatives:**
- Traditional OOP scene graph / component pointers: rejected due to pointer swizzling overhead on save/load, cache misses, and memory fragmentation.
- Archetype-based ECS (e.g. Flecs): rejected because binary and ternary relationships between multiple entities (e.g., `Carries(Guard, Cheese)` or `CharmedBy(Target, Bard)`) are awkward to model as single-entity archetypes.
**Consequences:** Memory snapshots for save games and replays are trivial `memcpy` operations over contiguous arenas. Status effects decay naturally without manual timer bookkeeping.

## D-004 Fiber-Based Temporal Primitives and Interrupt Stacks (2026-11-04, status: accepted)
**Context:** Game scripting often degenerates into state-machine boilerplate, tick counters, and callback spaghetti when managing long-running behaviors (patrols, waiting, interruptions).
**Decision:** Entity routines run as lightweight bytecode fibers with first-class `wait <ticks>` and `wait until <condition>` suspension. Preemptive events (`when <condition>: interrupt <entity> with:`) pause the active routine, push an execution frame onto the entity's interrupt stack, execute the interruption sub-routine, and pop to resume the prior routine once the condition clears.
**Alternatives:**
- Frame delta callbacks (`_process(delta)` in Godot / `Update()` in Unity): rejected because state machine boilerplate and timer variables proliferate rapidly.
- Behavior Trees: rejected because linear narrative flows with interrupts become overly complex node trees.
**Consequences:** Writing complex multi-step behaviors with emergency interruptions feels like sequential code while running fully cooperatively and deterministically.

## D-005 Room/Waypoint Node Graphs for Spatial Topology (2026-11-04, status: accepted)
**Context:** Choosing the initial spatial representation model for the BeSpoke Engine spine.
**Decision:** Implement a Room and Waypoint Node Graph model as the primary spatial topology, tailored for graphical point-and-click adventure games (in the tradition of Sierra SCI and LucasArts SCUMM). Rooms are container entities; waypoints and walk-boxes define navigation within rooms; portals link rooms. 2D discrete tile grids are deferred to future roadmap phases.
**Alternatives:**
- 2D Discrete Tile Grid as primary: deferred; better suited for top-down construction/management simulations, but less natural for cinematic adventure scenes with perspective scaling and walk-polygons.
- Full continuous 3D physics mesh: rejected per D-001; creates unnecessary complexity and bloat.
**Consequences:** Pathfinding is fast A* graph traversal over sparse waypoint networks. Moving between rooms is modeled as discrete portal transitions.

## D-006 Linear Scan Baseline for Relational Queries (2026-11-04, status: accepted)
**Context:** Determining indexing strategy for pattern-matching queries like `where Relation(subject, _)`.
**Decision:** Use contiguous linear scans over `MultiArrayList(Fact)` Structure-of-Arrays (SoA) columns as the engine's query baseline.
**Alternatives:**
- Secondary hash tables or entity-indexed sparse bitsets: rejected for initial phases; secondary indices add overhead to every `remember`/`forget` mutation and complicate pure `memcpy` arena serialization.
**Consequences:** In adventure game scenes with hundreds to low thousands of facts, scanning contiguous 2-byte relation slices in L1 cache executes in nanoseconds with zero allocation overhead. Secondary indexing can be introduced transparently in the future if profiling indicates a bottleneck.

## D-007 Unified Ternary Facts with Functional Property Overwrites (2026-11-04, status: accepted)
**Context:** Deciding how to represent continuous stats (e.g. Health, Gold, Alertness) vs. entity-entity relations.
**Decision:** Unify all state into ternary relational facts where the third slot (`object_or_value: u32`) can hold either an `EntityId` or an immediate scalar value. Relations are categorized as either sets (multiple rows allowed per subject, e.g. `Carries`) or functional properties (single row per subject, e.g. `Alertness`), where `remember Property(subject, new_val)` automatically overwrites any existing value for that property.
**Alternatives:**
- Dedicated component stats tables per entity: rejected; bifurcates the query syntax and introduces multiple distinct storage paradigms into the engine.
**Consequences:** The entire engine state remains in one contiguous fact table with uniform DSL query syntax (`where Alertness(Guard, lvl) and lvl > 50`).

## D-008 SDL2 Peripheral Display Consumer (2026-11-04, status: accepted)
**Context:** Need a fast, portable 2D graphical display peripheral to consume double-buffered `RenderFrame` snapshots, render waypoints, rooms, actors, and HUD, and capture mouse input for point-and-click adventure gameplay.
**Decision:** Implement an SDL2 display consumer (`src/display/renderer.zig`) linked strictly as a downstream peripheral. The core simulation engine remains self-contained with zero external dependencies. Mouse clicks on waypoints emit high-level motor intents (`walk_to`) targeting the designated player character.
**Alternatives:**
- Sokol (`sokol_app` + `sokol_gfx`): rejected for initial graphics window because SDL2 is already installed natively on the host environment and provides built-in 2D primitive rendering (`SDL_Renderer`) and immediate event queues without writing custom OpenGL shaders.
- Raylib: rejected because SDL2 is directly available and links cleanly via `-lSDL2` without package installation or vendoring.
**Consequences:** Core engine (`bespoke` static library) remains pure Zig with zero dependencies. Executables that include the graphical frontend link against `SDL2` and `libc`.

## D-009 Unifying Adventure Verbs as Cues and Hotspots as Entities (2026-11-04, status: accepted)
**Context:** Need a clean model for classic point-and-click adventure interactions (LookAt, PickUp, TalkTo, Use) and static scene hotspots (examine text, props) without bloating the runtime with separate scripting subsystems.
**Decision:** Treat all classic adventure verbs as discrete cues (`on cue LookAt(actor, target)`), and model scene hotspots as first-class `EntityId`s registered in the spatial graph with interaction bounds, examine descriptions, and hover tags.
**Alternatives:**
- Hardcoded verb tables and bespoke hotspot script callbacks: rejected because it introduces a duplicate state and handler pipeline alongside the existing VM cue dispatcher.
- Full UI-driven interaction scripting in host/peripheral: rejected because it violates D-001 (Engine-as-Spine) by shifting game interaction logic into the display consumer.
**Consequences:** Hotspots participate in the uniform relational fact database (`InRoom`, `Carries`, etc.), can be dynamically enabled or disabled via relational facts, and are examined or triggered using the existing `VM` cue mechanism.

## D-010 Reactive Simulation Engine with Multi-Clause Relational Joins and Priority Rule Cascades (2026-11-04, status: accepted)
**Context:** Need continuous reactive rule evaluation (`when <conditions>:`) in the simulation engine spine so NPC behaviors, systemic alertness, and world reactions respond immediately without manual polling boilerplate in routine loops.
**Decision:** Implement a multi-clause relational pattern matcher in `World` supporting relational conjunctions (`where A and B and C`) and variable joins across active facts. Implement a reactive rule engine in `VM` that tracks edge-triggered condition satisfaction (`false -> true`), evaluating rules on tick boundaries and fact mutations, and automatically preempts target fibers via priority-tiered interrupt stacks.
**Alternatives:**
- Manual polling in fiber routines (`wait 1 tick`, `if has_fact(...)`): rejected because it litters entity routine scripts with defensive polling and causes latency/jitter in reaction times.
- RETE algorithm network: rejected as overly complex for hundreds to thousands of facts; backtracking join over contiguous SoA fact columns in L1 cache executes in microseconds and preserves zero-overhead `memcpy` state serialization (D-001, D-003, D-006).
**Consequences:** Entities react systemically to world changes (e.g. theft, alerts, charm) with deterministic priority resolution and clean resumption once interrupts complete.

## Open questions

Questions requiring maintainer or stakeholder input. This is their one home: HANDOFF and the roadmap refer to them by ID. Numbers are permanent; an answered question stays, with the answer and its date.

- **Q-001** ~~Spatial topology representation: Should the default spatial model in the spine be a discrete 2D tile grid, a room/waypoint node graph, or a hybrid?~~ Answered 2026-11-04: Room/waypoint node graph adopted for graphical adventure game priority; 2D tile grids deferred, D-005.
- **Q-002** ~~Fact query indexing: At what scale does linear scanning over `MultiArrayList(Fact)` need to be augmented with sparse bitsets or entity-indexed hash tables?~~ Answered 2026-11-04: Linear scan over SoA columns adopted as baseline; cache-efficient and preserves zero-overhead `memcpy` saves, D-006.
- **Q-003** ~~Continuous numerical stats representation: Should continuous/metered stats be stored in a dedicated numeric table/struct per entity, or represented as ternary relational facts?~~ Answered 2026-11-04: Unified ternary facts with functional property auto-overwrite adopted, D-007.
