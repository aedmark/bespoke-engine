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

## D-011 In-Engine Developer Dashboard, Snapshot Scrubber, and Live REPL Console (2026-11-04, status: accepted)
**Context:** Need immediate live visibility into the running simulation (active facts, fibers, call stacks, spatial coordinates) and the ability to scrub historical state and inject facts or commands on the fly.
**Decision:** Implement an in-engine developer dashboard overlay, an interactive timeline scrubber bar, and an in-game live REPL console directly within the peripheral window consumer (`src/display/renderer.zig`) reading double-buffered `RenderFrame` debug state. Commands (`remember`, `forget`, `walk`, `rewind`, `step`) modify the simulation spine directly without pausing or recompiling.
**Alternatives:**
- External web-based debugger / WebSocket server: rejected as external bloat; native SDL2 rendering gives instant 60 Hz zero-latency in-game inspection.
- GDB / lldb CLI only: rejected because low-level memory debuggers do not understand high-level relational facts, fibers, or simulation ticks.
**Consequences:** Developers can inspect active facts, rewind to any tick with a single click, and inject systemic facts live in running simulations.

## D-012 High-Level Stageplay Taxonomy, Falling-Edge Triggers, and TTL Expiration Hooks (2026-11-06, status: accepted)
**Context:** Authors writing systemic adventure games need natural theater-like script syntax (`scene:`, `cast:`, `props:`, `marks:`, `now <X> is <State>`) and reactive lifecycle hooks for when states terminate or temporary facts expire (`when <X> stops being <Y>:`, `when <Entity> forgets <Relation>:`), demonstrated by the classic Monkey Island 2 Spitting Contest puzzle.
**Decision:** Extend the BeSpoke compiler front-end with stageplay taxonomy declarations that register rooms, agents, hotspots, and waypoints directly from script text. Lower natural state assertions (`now X is Y`, `now X is not Y`) into relational database operations on `World`. Extend the VM reactive rule engine to support falling-edge transitions (`true -> false`) and TTL fact expiration events, firing interrupts without manual timer bookkeeping or polling.
**Alternatives:**
- Requiring authors to write low-level `entity`, `relation`, and Zig setup code for every waypoint/hotspot: rejected as overly verbose and hostile to narrative designers.
- Polling in background routines to check if a timer ended: rejected because it reintroduces frame-based polling boilerplate that BeSpoke's Engine-as-Spine explicitly eliminates (D-004, D-010).
**Consequences:** Authors can write readable, theater-like scripts with ambient routines, natural state transitions, and edge-triggered event cascades.

## D-013 Two-Operand Inventory Combining and In-Hand Crafting (2026-11-06, status: accepted)
**Context:** Classic adventure games require combining items in inventory (e.g. `Use Syrup on CatHairTape` or `Combine Tape + Wire`) to create composite items before applying them to the world. Currently, the BeSpoke engine only handles unary verbs (`Use Item on WorldHotspot`) with 2 cue parameters `(Actor, Target)`.
**Decision:** Extend the cue system and language front-end to support ternary `Uses` cue signatures: `Uses(Actor, ItemA, ItemB)`. When the player selects an inventory item and clicks a second inventory item in the tray, the engine emits a 3-argument cue `(actor, primary_item, secondary_item)`. The cue matcher treats item combining as commutative by default: a handler declared as `on cue Uses(Gabriel, MapleSyrup, CatHairTape):` will match whether the player applies syrup to tape or tape to syrup.
**Alternatives:**
- Requiring authors to write two separate cue declarations for every combination (`Uses(A, B)` and `Uses(B, A)`): rejected as error-prone script duplication.
- Inventing a separate `combine` keyword and subsystem distinct from `Uses`: rejected because conceptually "combining" is simply using one item on another, and keeping `Uses` preserves uniform cue mechanics (D-009).
**Consequences:** The compiler lowers 3-parameter cue declarations with composite signature indexing; the VM cue dispatcher matches commutative item pairs; and the display renderer tracks an `active_in_hand_item` state allowing players to click an item, see an in-hand cursor indicator, and click either a world object or another inventory item.

## D-014 Multi-Scene Graph Partitioning, Routine Scoping, and Dynamic Backdrop Transitions (2026-11-06, status: accepted)
**Context:** Systemic adventure simulations require multiple distinct narrative locales (e.g., Tavern Common Room vs. Wine Cellar, or Hotel Corridor vs. Garden Fence in GK3). Navigating between them requires switching active waypoints, stage marks, and visual backdrop palettes, while ambient behaviors specific to the previous scene pause and target scene routines start or resume. Crucially, all global relational facts (player inventory, item states, cross-scene puzzle progression) must persist uninterrupted in the relational World arena.
**Decision:** Implement first-class multi-scene simulation support across compiler, VM, spatial system, and renderer:
1. **DSL Syntax & Opcode:** Add `transition to scene: <TargetScene>` to BeSpoke grammar and `Opcode.transition_scene` (0x44) to bytecode. The VM tracks `current_scene: ?EntityId`.
2. **Routine Scoping:** When transitioning between scenes, the VM pauses fibers whose owner is the departed scene and wakes or resumes fibers associated with the target scene.
3. **Spatial Partitioning:** Partition `SpatialGraph` waypoints and `SpatialSystem` hotspots by `room: EntityId`. Introduce `transition_actor` to reposition actors onto entry marks in the new topological environment.
4. **Display Renderer Dynamic Backdrops:** Extend `RenderFrame` with `current_scene`. The peripheral renderer switches backdrops dynamically (e.g. Booty Island outdoor field, Tavern interior, Wine Cellar) and scopes visible waypoints and interactables to the active scene.
5. **Relational Fact Invariant:** Relational facts in `World` remain global and continuous across scene boundaries, preserving inventory, functional properties, and causal state without manual serialization.
**Alternatives:**
- Destroying and reinitializing the entire simulation World per scene: rejected because cross-scene inventory, character knowledge, and relational world states would require cumbersome save/load serialization cycles.
- Monolithic single-scene coordinate planes with all waypoints active simultaneously: rejected because unrelated scene marks and background routines would clutter the renderer and leak ambient events across distant rooms.
**Consequences:** Multiple narrative locations can be authored within a single unified script; scene transitions smoothly swap ambient audio/visual context while preserving relational puzzle progression.

## D-015 Relational Dialogue Choice Trees and Dynamic Fact-Based Pruning (2026-11-06, status: accepted)
**Context:** Narrative adventure games require branching conversation trees where dialogue choices dynamically appear, disappear, or modify based on active relational world facts (e.g. asking to rent a motorcycle requires carrying a driver's license; inquiring about a mystery clue disappears once answered). Hardcoding choice trees in host-language if/else ladders causes script fragmentation and breaks hot-reloading and time-travel rewinds.
**Decision:** Implement first-class conditionally guarded dialogue choices in BeSpoke DSL (`P13-01`), VM runtime pruning (`P13-02`), and display renderer balloon UX (`P13-03`):
1. **Grammar & AST:** Add `kw_choice` keyword to lexer and parser. A choice statement `choice "Option text" [if Condition]: <body stmts>` supports relational fact patterns (`if HasFact(...)`, `if not HasFact(...)`, `if Carries(...)`). Consecutive choice statements compile into a unified choice block.
2. **VM Runtime Pruning:** The VM evaluates choice condition expressions against the contiguous `World` fact store at balloon spawn time (`eval_expr`, `prune_dialogue_choices`). Unsatisfied branches are culled before rendering, ensuring the player is presented only with valid conversational options.
3. **Display Renderer Dynamic Sizing & Hotkeys:** Extend `SpeechBalloon` to support variable-length choice sets (up to 9 choices) with dynamic height calculation (`bh = 48 + choice_count * 26`). Add dual input handling: clicking with mouse or pressing keyboard number keys (`1-9` / numpad `1-9`) selects corresponding dialogue options.
**Alternatives:**
- Static dialogue trees where unavailable options are shown grayed out: rejected as default because narrative immersion in detective/investigation games requires secret or unearned leads to remain hidden until discovered.
- External dialogue node editors (Yarn/Twine/Ink JSON): rejected because external dialogue graphs lack direct sub-microsecond access to BeSpoke's contiguous SoA relational fact store and cannot participate seamlessly in simulation time-travel rewinds (D-001, D-003).
**Consequences:** Authors can declare rich, responsive branching dialogues directly in script text; dialogue options react systemically to inventory, knowledge facts, and world states with zero runtime garbage collection.

## Open questions

Questions requiring maintainer or stakeholder input. This is their one home: HANDOFF and the roadmap refer to them by ID. Numbers are permanent; an answered question stays, with the answer and its date.

- **Q-001** ~~Spatial topology representation: Should the default spatial model in the spine be a discrete 2D tile grid, a room/waypoint node graph, or a hybrid?~~ Answered 2026-11-04: Room/waypoint node graph adopted for graphical adventure game priority; 2D tile grids deferred, D-005.
- **Q-002** ~~Fact query indexing: At what scale does linear scanning over `MultiArrayList(Fact)` need to be augmented with sparse bitsets or entity-indexed hash tables?~~ Answered 2026-11-04: Linear scan over SoA columns adopted as baseline; cache-efficient and preserves zero-overhead `memcpy` saves, D-006.
- **Q-003** ~~Continuous numerical stats representation: Should continuous/metered stats be stored in a dedicated numeric table/struct per entity, or represented as ternary relational facts?~~ Answered 2026-11-04: Unified ternary facts with functional property auto-overwrite adopted, D-007.
