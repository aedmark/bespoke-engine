# Decisions

Short, append-only record of choices that a future session might otherwise re-litigate. One entry per decision.
Newest at the bottom. To reverse a decision, add a new entry that supersedes it; the old one keeps its text and only
its status changes ("superseded by D-MMM"). An "Update, same session" note at the end of an entry is fine while it is
still on the working branch.

Record pre-existing choices too, the first time a session has to understand them ("status: accepted, recorded
YYYY-MM-DD"): the reason something is the way it is gets lost faster than the code. Every constraint in the codebase is
an answer to an earlier question or failure mode; recording that originating question here stops a future session from
removing a fence whose purpose it forgot.

Format:

```
## D-NNN Title  (YYYY-MM-DD, status: proposed | accepted | rejected | superseded by D-MMM)
**Context:** the originating question, failure mode, or measurement this choice answers (and the roadmap item or bug).
**Decision:** what we chose (numbered points if there are several).
**Alternatives:** what else was considered, and why not (one line each). Optional, but it is what stops the
re-litigation.
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

## D-016 The Gabriel Knight 3 Cat Moustache Puzzle Scenario and Multi-Scene Narrative Integration (2026-11-06, status: accepted)
**Context:** Proving the engine's capability for systemic adventure game narratives requires executing a complex, multi-scene puzzle with multi-step item crafting, dynamic inventory interactions, and relational dialogue pruning. The infamous "Cat Moustache" puzzle from *Gabriel Knight 3* represents the ultimate stress test: breaking into a room, taping a fence hole, startling a cat with a water spray, peeling fur from adhesive, crafting fake facial hair with breakfast syrup, altering a passport photo with a marker, and deceiving a skeptical French shopkeeper through dynamically guarded dialogue trees.
**Decision:** Implement the complete Gabriel Knight 3 vertical slice in `src/gk3_moustache.zig` (`P14-01`), integrate multi-scene backdrops and custom actor tokens in `src/display/renderer.zig` (`P14-02`), and provide `--gk3` CLI execution with headless simulation and interactive 60 Hz playability (`P14-03`):
1. **BeSpoke DSL Narrative Scenario:** Author `GK3_MOUSTACHE_SCRIPT` declaring 3 partitioned scenes (`Hotel Corridor`, `Hotel Garden`, `Bike Rental Shop`), ambient routines (`MoselyPacing`, `CatNapping`), item-on-item crafting (`Uses(Gabriel, CatHair, Syrup)`, `Uses(Gabriel, Marker, MoselyPassport)`), and fact-guarded dialogue choice blocks (`choice "..." if Disguised(Gabriel):`).
2. **2D Scene Visual Backdrops & Actor Tokens:** Extend `DisplayBridge` and `renderer.zig` to render authentic French provincial backdrops: Burgundy damask wallpaper and room doors 25/33 for the hotel corridor, stone walls and picketed fence with taped hole for the courtyard garden, and timber beams and motorcycle display for the bike rental shop. Draw custom tokens for Gabriel Knight (tan trench coat, blonde hair, dark shades, and cat moustache when disguised), Franklin Mosely (detective suit with moustache), Madame Buthane (auburn hair, crimson vest), and the stray cat.
3. **Headless & Interactive Playability:** Support `--gk3` and `--cat-moustache` flags in `src/main.zig` with 13-step deterministic headless simulation verification (including time-travel rewinds restoring pre-disguise state) and 60 Hz interactive play with scene jumping hotkeys (`[H]`, `[G]`, `[B]`), puzzle progression hotkeys (`[1]`..`[8]`), and interactive speech balloons.
**Alternatives:**
- Hardcoding the GK3 puzzle in an isolated C/Python script: rejected because BeSpoke's purpose is to prove that complex systemic adventure game scenarios can be scripted cleanly and natively in BeSpoke DSL without engine modifications.
- Implementing a simpler single-room toy puzzle: rejected because the Cat Moustache puzzle exercises every major subsystem built in Phases 1 through 13 (multi-scene transitions, item-on-item combining, falling-edge triggers, spatial waypoints, relational inventory, and dynamic dialogue choice pruning).
**Consequences:** Demonstrates BeSpoke's readiness for production-grade narrative adventure games, validating that complex systemic puzzles with multi-step crafting, spatial movement, and dynamic dialogue trees run deterministically with zero garbage collection and instant time-travel reversibility.

## D-017 Relational Epistemology, Insult Sword Fighting Combinatorial Queries, and Repetition Fatigue Mood Decay (2026-11-07, status: accepted)
**Context:** Dialogue trees in classic adventure games often drown in ad-hoc boolean flag spaghetti (e.g., tracking 16 heard insults and 16 mastered counters across roaming pirates and the Sword Master Carla in *The Secret of Monkey Island*). Furthermore, conventional engines (Inform, TADS, AGS) model conversations as static vending machines: NPCs repeat identical monologues indefinitely without acknowledging player pestering.
**Decision:** Implement relational epistemological dialogue modeling in BeSpoke DSL (`P13-04`), runtime combinatorial queries (`P13-05`), and CLI playability (`P13-06`):
1. **Combinatorial Dialogue Memory:** Model conversational knowledge as relational facts (`HeardInsult(fighter, insult)`, `MasteredReply(fighter, reply)`, `Counters(reply, insult)`, `SwordMasterVariant(carla_insult, standard_insult)`). Dialogue choices are generated and pruned dynamically via relational queries over the world fact arena rather than hardcoded flag trees.
2. **Sword Master Target Invariant:** Enforce target-specific validity rules natively in the query layer. When confronting standard pirates, Sword Master insults are pruned or rejected ("if you try to use a Sword Master insult on a regular pirate it won't fly"), while challenging Carla maps her unique elevated retorts to standard counters via `SwordMasterVariant`.
3. **Conversational Repetition Fatigue and Mood Decay:** Track conversational frequency with `Inquired(speaker, topic, count)`. Escalating repetitions transition NPC mood from `.welcoming` to `.annoyed` (`AnnoyedWith(npc, speaker)` for 100 ticks) to `.furious` (`FuriousWith(npc, speaker)` for 250 ticks). When furious, the NPC slams the door and dialogue choices are blocked. As simulation ticks advance via `step_tick()`, the temporary mood facts expire automatically from the contiguous SoA arena, cooling the NPC down.
4. **Tangled World State Interconnection:** Expose player traits and achievements (`DuelsWon`, `Swagger`, `PathChosen`) to dialogue choices, enabling branching paths inspired by *Disco Elysium* and *Indiana Jones and the Fate of Atlantis*.
**Alternatives:**
- 32 mutable boolean flags per character: rejected because combinatorial flag checking creates exponential branching logic that is impossible to maintain and inspect cleanly.
- Static cooldown timers in host script variables: rejected because host-language variables cannot participate in BeSpoke's zero-copy `memcpy` snapshots and instant time-travel rewinds (D-001, D-003).
**Consequences:** Authors can author complex conversational duels and living, reactive NPCs using concise relational rules without flag fluff; conversational state deterministically rewinds alongside physical simulation.

## D-018 Standalone Script File Execution, Bytecode Package Serialization (.bspk), and Diagnostic Tooling (2026-11-07, status: accepted)
**Context:** BeSpoke previously executed scenarios compiled from in-memory Zig string constants (`TAVERN_SCRIPT`, `GK3_MOUSTACHE_SCRIPT`, etc.). Narrative designers need to author external `.bespoke` text files on disk, validate them with compiler line/column diagnostics, compile them into standalone binary asset packages (`.bspk`), and run them in both headless and 60 Hz GUI modes without recompiling the Zig engine spine.
**Decision:** Implement external script execution, binary serialization, and diagnostic tooling across Phases 15-01 through 15-03:
1. **CLI Subcommand Structure (P15-01):** Establish first-class subcommands in `src/main.zig` and `src/runner.zig`:
   - `bespoke run <script.bespoke | game.bspk> [--headless] [--ticks N]`: loads and executes source or bytecode in headless or interactive GUI mode.
   - `bespoke compile <script.bespoke> -o <game.bspk>`: compiles source text into an optimized binary package.
   - `bespoke check <script.bespoke>`: validates syntax and semantics without execution.
2. **Bytecode Binary Asset Specification (.bspk, P15-02):** Implement `src/package.zig` defining a self-contained binary container:
   - Header: 4-byte magic (`BSPB` - BeSpoke Binary), schema version (`u32 = 1`), payload size, and CRC32 checksum over the payload.
   - Payload: Interned entity & relation dictionary tables, spatial waypoints & hotspots, raw bytecode chunk, and entry tables (routines with actor metadata, cue handlers, when rules, and reactive simulation rules).
3. **Untrusted Boundary Validation (P15-02, SECURITY.md):** The asset loader validates magic header, version, CRC32 checksum, element counts, and slice bounds before allocating structures, ensuring malformed or maliciously crafted packages cannot cause buffer overflows or host crashes.
4. **Diagnostic Error Reporting (P15-03):** Enhance `src/compiler/parser.zig` and `src/compiler.zig` with a structured `Diagnostic` type (`line: u32, column: u32, message: []const u8`). The parser emits standard Unix compiler error diagnostics (`<file>:<line>:<col>: error: <message>`) and exits with non-zero code on failure.
**Alternatives:**
- Embedding an external scripting runtime (Lua/Wren): rejected because BeSpoke's Engine-as-Spine architecture requires zero external dependencies, deterministic memory layout, and full integration with continuous `when` rules.
- JSON-based bytecode serialization: rejected for a CRC32-checksummed binary format matching BeSpoke's snapshot serialization architecture (D-001, D-003).
**Consequences:** Complete decoupling of narrative authoring from the Zig toolchain. Game creators can write `.bespoke` files on disk, validate them in CI via `bespoke check`, compile them to `.bspk`, and distribute them to end users running the standalone `bespoke` engine binary.

## D-019 Peripheral Audio Subsystem, Procedural Chiptune Synthesizer, and Decoupled Audio Cue Bridge (2026-11-07, status: accepted)
**Context:** Narrative adventure games require rich auditory feedback—action sound effects (footsteps, pickups, combining items, ship horn blasts, splashes, sword clashes, alert stingers, NPC dialogue chirps, UI clicks) and dynamic scene-specific musical accompaniment. However, BeSpoke's Engine-as-Spine architecture (D-001) mandates that the core simulation runs deterministically on discrete ticks, with zero hardware dependencies, zero external WAV/MP3 asset files, and zero runtime audio thread blocking.
**Decision:** Implement a peripheral procedural chiptune audio subsystem in pure Zig (`src/audio.zig`) with a thread-safe `AudioBridge` consumer in `src/display.zig` and SDL2 callback:
1. **Decoupled Audio Cue Bridge (P16-01, D-001):** The simulation spine emits discrete audio cues into an atomic/mutex-guarded ring buffer inside `AudioBridge`. The peripheral audio thread (SDL2 audio callback at 44.1 kHz) drains events asynchronously without stalling simulation ticks or modifying simulation state. In headless mode or environments lacking audio drivers, the audio device safely bypasses hardware playback while preserving deterministic cue recording and offline PCM buffer rendering for test suites.
2. **Procedural Chiptune Synthesizer (P16-02):** Pure Zig integer DSP engine with zero audio asset files (no WAV/MP3/OGG dependencies). Borrowing phase accumulation and waveform generation techniques from `/home/gordonk/PycharmProjects/whimsy-machine/`:
   - 32-bit phase accumulators (`phase += phase_inc`) with precomputed 44.1 kHz MIDI phase increment lookup table.
   - Pure integer waveforms: variable-duty pulse (12.5%, 25%, 50%, 75%), linear triangle, sawtooth, and 32-bit LCG pseudo-random noise generator.
   - Attack/Decay envelope generators, pitch sweeps (falling sweeps for kicks/splashes, rising sweeps for pickups), and polyphonic voice pooling.
   - Procedural action SFX: `footstep`, `pickup`, `combine`, `horn`, `splash`, `sword_clash`, `alert`, `dialogue_blip`, `click`, `whistle`.
3. **Dynamic Scene Musical Accompaniment (P16-03, D-014):** 4-channel procedural step sequencer (Bass, Lead, Harmony/Chords, Percussion) synthesizing looping thematic melodies tailored to narrative locations:
   - The Tavern Heist (`.tavern`): lively G-Dorian pipe/lute jig.
   - The Wine Cellar (`.cellar`): moody subterranean bassline with ambient triangle echoes.
   - Booty Island Spitting Contest (`.spitting_contest`): jaunty Caribbean pirate march with bouncy pulse bass and snappy snare crack.
   - Mêlée Island High Road (`.high_road`): adventurous seafaring shanty progression.
   - Carla's Sanctuary (`.sanctuary`): dramatic dueling cadence with rapid arpeggios.
   - The Scumm Bar (`.scumm_bar`): rowdy pirate tavern waltz in 3/4 time.
   - French Hotel Courtyard Garden (`.courtyard`): peaceful provincial waltz.
   - French Bike Rental Shop (`.bike_shop`): breezy café accordion/lead rhythm.
   Track switching occurs automatically upon scene transitions (`RenderFrame.get_current_scene()`) or narrative cue triggers.
**Alternatives:**
- Loading external WAV/OGG audio files from disk: rejected because BeSpoke aims for zero external asset dependencies, instant load times, and self-contained executable distribution.
- Embedding a third-party audio engine (SoLoud, FMOD, miniaudio): rejected to maintain zero C/C++ dependencies in core synthesis logic and ensure deterministic integer sample synthesis across all platforms.
**Consequences:** Complete auditory immersion with zero audio asset files, zero audio thread contention on simulation ticks, seamless graceful headless fallback for CI, and reproducible verification via offline PCM buffer rendering.

## D-020 Persistent Save/Load Disk Storage (.sav), Slot Management API, and In-Engine Save Drawer (2026-11-07, status: accepted)
**Context:** While BeSpoke Engine's contiguous memory arena and `World.save_state` / `World.restore_state` (D-003) provide instantaneous in-memory time-travel scrubbing, durable cross-session persistence requires a file-backed save state format on disk, a slot management API supporting numbered slots, quick-save/quick-load, and automatic corrupted save recovery, as well as an interactive in-engine Save/Load drawer and pause menu overlay.
**Decision:** Implement persistent disk save/load storage, slot management, and UI overlay across Phases 17-01 through 17-03 (`src/save.zig` and `src/display/renderer.zig`):
1. **File-Backed Save State Format (`.sav`, P17-01):** Define a self-contained binary save container in `src/save.zig` starting with a fixed header: 4-byte magic (`BSAV`), format version (`u32 = 1`), 32-bit CRC32 integrity checksum computed over the entire payload, and payload byte size. The payload embeds rich slot metadata (`SaveMetadata`: slot ID, simulation tick, playtime in seconds, Unix timestamp, active fact and entity counts, active scene entity ID and human-readable scene name, description string, actor preview coordinates, and a 16x12 RGB332 miniature graphical frame thumbnail), followed by the deterministic `World` snapshot (`World.save_state`), spatial motor agent states (`MotorAgent` positions, waypoints, and active A* path segments), and VM execution state (`current_scene`, cooperative fiber stacks, program counters, wait states, interrupt call stacks, and reactive rule edge states).
2. **Slot Management API & Corrupted Save Recovery (`SaveManager`, P17-02):** Manage 8 numbered save slots (`slot_1.sav` .. `slot_8.sav`) plus a dedicated quick-save slot (` slot 0`, `quicksave.sav`) inside a configurable directory (`saves/`). Before overwriting an existing valid `.sav` file, `SaveManager` preserves a backup copy at `<slot>.sav.bak`. If loading a primary `.sav` file fails magic, version, truncation, or CRC32 checksum verification, `SaveManager` automatically falls back to `<slot>.sav.bak`, restoring the valid state and repairing the primary slot file transparently.
3. **In-Engine Save/Load Drawer & Pause Menu Overlay (P17-03, D-008, D-011):** Integrate a modal Pause & Save/Load Drawer overlay into `DisplayWindow` (`src/display/renderer.zig`), toggled via `[P]`, `[F2]` (Save mode), or `[F3]` (Load mode), alongside direct `[F5]` Quick-Save and `[F9]` Quick-Load hotkeys. The overlay renders each slot card with its 16x12 RGB332 graphical scene thumbnail, occupation/corruption badge, scene name, simulation tick, fact count, and playtime, and emits `UserAction` intents (`save_slot`, `load_slot`, `quick_save`, `quick_load`) handled across all interactive scenario loops.
**Alternatives:**
- Saving only the `World` fact table without spatial motor agents or VM fiber stacks: rejected because mid-walk actor positions, active scene IDs, and suspended fiber wait/interrupt states must resume seamlessly upon loading a disk save.
- Unchecked raw binary dumps without backup files: rejected because disk truncation or bit rot would cause unrecoverable slot loss or unchecked memory corruption at the host filesystem boundary (SECURITY.md).
**Consequences:** Full cross-session durability with CRC32 integrity verification, automatic `.bak` corruption recovery, miniature visual slot thumbnails, and 1-key quick-save/quick-load across all BeSpoke scenarios.

## D-021 Systemic Emergent Simulation Sandbox ("The Living Village"), Autonomous Physiological Drives, Rumor Propagation, and Justice Cascades (2026-11-08, status: accepted)
**Context:** Phases 1 through 17 established BeSpoke Engine's relational fact database, multi-clause joins, continuous reactive `when` rules, A* spatial navigation, and deterministic time-travel and disk persistence across classic adventure game vertical slices. Phase 18 (`P18-01` through `P18-03`) validates BeSpoke's systemic simulation ambition ("The Living Village"): an unscripted settlement where autonomous NPCs act on continuous physiological drives, social relationships, witness detection, rumor propagation, and emergent law enforcement cascades without hard-coded plot trees.
**Decision:** Implement the Living Village systemic emergent simulation sandbox in `src/village.zig` and `src/display/renderer.zig`:
1. **Relational Physiological Drives & Social Schema (`P18-01`, `D-003`, `D-007`, `D-010`):** Represent every villager's internal needs (`Hunger` `0..100`, `Energy` `0..100`, `Gold` `0..100`, `Activity`, `Mood`) as `.property` relations with automatic scalar overwrite (`D-007`), alongside `.set` social and ownership relations (`Friend(a, b)`, `Rival(a, b)`, `Trust(a, b)`, `Grudge(victim, offender)` with TTL, `Owns(owner, item)`, `Carries(holder, item)`). Every discrete simulation tick metabolizes villager drives (`Hunger` rises, `Energy` falls during work/patrol) and evaluates autonomous utility transitions (working at trade posts to earn gold, walking to the `Bakery` or `Tavern` to purchase food when hungry with gold, or walking to `Cottages` to sleep when exhausted).
2. **Emergence Engine: Desperation Theft, Witness Detection, Rumor Propagation, and Justice Cascade (`P18-02`, `D-004`, `D-010`):**
   - *Desperation Crime:* When an impoverished villager's `Hunger` crosses the desperation threshold (`>= 80`) while `Gold == 0`, they navigate to the `Bakery` and commit emergent property theft (`StolenFrom(thief, Baker)`, `CrimeScene(thief, Bakery)`), consuming a stolen `BreadLoaf` to survive.
   - *Witness Detection:* Any non-sleeping villager co-located at or adjacent to the crime scene detects the act, asserting `Witnessed(witness, thief)`, `KnowsRumor(witness, thief)`, and a TTL-bounded `Grudge(witness, thief)`.
   - *Rumor Propagation:* During each tick, co-located villagers connected by `Friend` links or sharing a landmark with the `Sheriff` propagate `KnowsRumor(speaker, thief)` -> `KnowsRumor(listener, thief)` across the social graph.
   - *Sheriff Investigation & Arrest Cascade:* When `KnowsRumor(Sheriff, thief)` is asserted, a high-priority reactive interrupt (`D-004`) preempts the `Sheriff`'s routine patrol, issuing `WarrantFor(Sheriff, thief)`, dispatching the `Sheriff` to inspect the crime scene and pursue the suspect across the waypoint graph, executing `Arrested(thief, Sheriff)`, and escorting the offender to `SheriffsPost` (`SheriffJail`) while logging each step to a bounded `ChronicleEntry` ring buffer.
3. **Settlement Spatial Topology & Social Graph / Chronicle Visualization (`P18-03`, `D-005`, `D-008`, `D-011`):** Construct a 6-building settlement (`Bakery`, `Farm`, `TownSquare`, `Cottages`, `Tavern`, `SheriffsPost`) interconnected by cobblestone village roads. Extend `RenderFrame` (`src/display.zig`) and `DisplayWindow` (`src/display/renderer.zig`) to render the multi-building settlement, villager drive/status badges, and a live **Village Social Graph & Event Chronicle HUD** panel displaying active `Friend`/`Rival`/`Grudge`/`KnowsRumor`/`WarrantFor` edges alongside real-time emergent chronicle events.
**Alternatives:**
- Pre-scripted timed cutscenes for the theft and arrest: rejected because BeSpoke's core thesis is that narrative events emerge from relational state rules, metabolic drives, spatial co-location, and social graph topology.
- Storing NPC needs in private struct fields outside `World`: rejected because keeping `Hunger`, `Energy`, `Gold`, and `KnowsRumor` as first-class `World` facts ensures that in-memory time-travel scrubbing (`P9-02`), live REPL queries (`P9-03`), and `.sav` disk snapshots (`P17-01`) automatically capture and restore the entire emergent simulation state.
**Consequences:** Demonstrates a full autonomous systemic simulation running on the exact same relational fact store, fiber VM, and spatial spine as the point-and-click adventure slices, with deterministic headless verification and interactive catalyst controls.

## D-022 WebAssembly (wasm32-freestanding) Runtime Harness, Browser Event Bridge, and Embedded 3x Manual Simulator (2026-11-08, status: accepted)
**Context:** Phase 19 (`P19-01` through `P19-03`) brings the BeSpoke Engine to web browsers and interactive documentation: compiling the core simulation spine to `wasm32-freestanding` using Zig's native cross-compiler, bridging browser mouse/keyboard/touch events to BeSpoke motor and adventure verb intents, and embedding an interactive HTML5 Canvas simulator directly inside `docs/manual.html`.
**Decision:** Implement the WebAssembly target, browser event bridge, and embedded manual simulator across `src/wasm.zig`, `build.zig`, `tools/manual.py`, and `docs/manual.html`:
1. **`wasm32-freestanding` Build Target & RGBA8888 Canvas Harness (`P19-01`, `D-001`):** Create `src/wasm.zig` backed by a static `FixedBufferAllocator` (zero libc or OS syscalls required) and a pure Zig `640x360` RGBA8888 software framebuffer (`WasmCanvas`) using the 5x7 bitmap font (`src/display/font.zig`). Add a `zig build wasm` step in `build.zig` targeting `wasm32-freestanding` (`.entry = .disabled`, `.rdynamic = true`) that produces `zig-out/bin/bespoke.wasm` exporting C-ABI symbols (`wasm_init`, `wasm_step_tick`, `wasm_render_frame`, `wasm_framebuffer_ptr`, `wasm_framebuffer_len`, `wasm_load_scenario`, `wasm_scrub_to_tick`, `wasm_exec_repl`).
2. **Browser Event Bridge (`P19-02`, `D-008`):** Implement `BrowserInputEvent` and `WasmRuntime.dispatch_event` in `src/wasm.zig` (exposed via `wasm_on_pointer_down`, `wasm_on_pointer_move`, `wasm_on_right_click`, `wasm_on_key_down`, `wasm_on_touch`) translating normalized canvas coordinates and DOM key codes into BeSpoke intents: timeline bar scrubbing, 5-verb bar selection (`WALK`, `LOOK`, `TALK`, `TAKE`, `USE`), right-click/two-finger verb cycling, A* waypoint navigation (`walk_to`), hotspot/actor inspection, and scenario catalyst hotkeys.
3. **Interactive Embedded Manual Simulator (`P19-03`, `D-001`, `D-011`):** Extend `tools/manual.py` to generate an interactive HTML5 `<canvas>` simulator deck inside `docs/manual.html` hosting live playable vertical slices (*The Tavern Heist*, *Booty Island Spitting Contest*, *GK3 Cat Moustache*, and *The Living Village*) with point-and-click/touch canvas controls, timeline scrubbing, live relational fact inspection, and REPL command execution, capable of running standalone in any browser or binding to `bespoke.wasm`.
**Alternatives:**
- Requiring Emscripten SDK (`emcc`) and external SDL2-wasm ports: rejected because Zig's built-in `wasm32-freestanding` target compiles pure Zig code out-of-the-box with zero external toolchains, and rendering directly to a linear-memory RGBA8888 framebuffer (`ImageData`) keeps the binary compact and deterministic.
- Hosting the simulator only on an external server: rejected because `docs/manual.html` is designed as a 100% portable, self-contained single-file developer guide that works offline from `file://` URLs.
**Consequences:** Complete browser portability via `zig build wasm` with zero external SDK dependencies, unified mouse/keyboard/touch input translation tested in pure Zig, and a live playable simulator embedded directly inside `docs/manual.html`.

**Update, 2026-11-10 (P32-29):** The manual now embeds `bespoke-proofs.wasm` and runs the six proof decks through the browser runtime. The fact-list and REPL controls are gone because the module exports a fact count, not fact rows or an injection API.

## D-023 The Broken Sword Lochmarne Goat Puzzle Scenario, Dynamic Threat-Radius Tethering, and Subterranean Scene Transition (2026-11-08, status: accepted)
**Context:** The Lochmarne Castle Goat Puzzle from *Broken Sword: The Shadow of the Templars* (1996) subverts traditional static point-and-click adventure pacing: an aggressive tethered Billy Goat guards the entrance to an archaeological excavation, knocking the player down whenever they approach the pit. The solution requires seizing a fleeting recovery window while the goat retreats to its stake to drag a heavy farm plough into the rope path, tangling the goat and clearing the ladder to the subterranean Templar crypt.
**Decision:** Implement the Broken Sword Goat Puzzle vertical slice in `src/goat_puzzle.zig`, `src/display/renderer.zig`, and `src/audio.zig`:
1. **DSL Stageplay & Reactive Threat-Radius Modeling (`P20-01`, `D-001`, `D-004`, `D-010`, `D-012`):** Represent Lochmarne Castle Courtyard and Subterranean Templar Dig Crypt with `cast: George, BillyGoat`, `props: CellarEntrance, FarmPlough, TetherStake, CarvedMural`, and spatial waypoints (`CourtyardEntrance`, `PloughMark`, `TetherCenter`, `DigOpening`, `FallMark`, `CryptLadder`, `AltarMark`). Model the goat's autonomous reactive loop: entering the cellar threat zone triggers a high-priority charge interrupt (`D-004`), knocking George back to `FallMark` and initiating a 30-tick retreat window (`GoatRetreating(BillyGoat, true) for 30 ticks`).
2. **Dynamic Tether Constraint & Plough Dragging (`P20-01`, `D-003`, `D-007`):** Interacting with `FarmPlough` during the active retreat window hauls the plough into the rope line, asserting `TangledWith(BillyGoat, FarmPlough)` and `now BillyGoat is tangled`. The goat's tether constraint shifts from the center stake to the plough, locking its movement radius away from the dig entrance.
3. **Subterranean Scene Transition (`P20-01`, `D-014`):** Once tangled, descending `CellarEntrance` executes `transition to scene: Templar Crypt`, preserving global facts while switching spatial waypoints and visual backdrops to the ancient underground vault.
4. **Visual Backdrops, Actor Tokens, and Procedural Audio (`P20-02`, `P20-03`, `D-008`, `D-019`):** Render authentic Irish castle ruins (stone towers, mossy turf, cellar pit with ladder, wooden stake, dynamic rope line that wraps around the plough when tangled) and dark subterranean crypt (carved Templar cross, torchlight sconces, altar), custom actor tokens (George in trench/leather jacket, Billy Goat with curved horns, beard, and tangled stars), procedural Celtic whistle melody in 6/8 jig time (`.lochmarne`), and action SFX (`goat_bleat`, `headbutt_thud`).
**Alternatives:**
- Hard-coded timer outside VM: rejected because BeSpoke's core principle is that timing and reactive states emerge deterministically from discrete ticks, relational fact TTLs, and fiber interrupts, ensuring 100% determinism and seamless time-travel rewind.
- Single courtyard scene: rejected because testing multi-scene transitions (`transition to scene`) validates the complete narrative payoff of descending into the Templar crypt.
**Consequences:** Demonstrates reactive threat-radius mechanics, finite temporal recovery windows, dynamic physical constraint shifting, and multi-scene descent within pure BeSpoke DSL.

## D-024 Centralized Text Layout Resolver, Floating Label Collision Avoidance, and Visual Hierarchy Standardization (2026-11-08, status: accepted)
**Context:** When multiple actors, waypoints, and interactive hotspots occupy close spatial proximity (such as George Stobbart, FallMark, and the Billy Goat in the Lochmarne Castle courtyard), naive static label offsets produce illegible overlapping text (e.g. `[StandiFallMarkarding Dig Entrance]`). Hardcoding scene-specific pixel nudges is fragile and violates the systemic design of the engine.
**Decision:** Implement a centralized, deterministic 2D label layout engine (`TextLayoutResolver`) in `src/display/text_layout.zig` and integrate it into `src/display/renderer.zig`:
1. **Deterministic Multi-Tier Collision Resolver (`P20-02`, `D-008`, `D-024`):** Centralize all floating in-world text labels into `TextLayoutResolver` (`MAX_LABELS = 64`, `MAX_OBSTACLES = 32`, zero heap allocations). Register actor and waypoint tokens as physical obstacles.
2. **Priority-Based Placement Order:** Sort candidate labels by descending priority (`hover_tooltip = 10`, `actor_alert = 9`, `actor_name = 8`, `actor_status = 7`, `waypoint_target = 6`, `waypoint_idle = 2`, `backdrop_prop = 1`). Higher priority labels claim their preferred bounding boxes first.
3. **Visual Hierarchy & Scale Standardization:** Standardize actor status tags and idle waypoints to font scale 1 (crisp 5x7 bitmap font, 6px width per char), cutting width by 50% compared to scale 2 while preserving scale 2 (12px per char) for primary actor names and active hover tooltips.
4. **Collision Avoidance Strategies:** When collision occurs, actor statuses stagger downward across vertical tiers (Tiers 1-3) or flip above; actor names stagger upward or nudge horizontally; idle waypoints yield by testing alternative placement or suppressing their idle text (while ground circles remain visible and hover prompts retain highest priority).
5. **Elimination of Redundant Backdrop Text:** Remove hardcoded static text banners on interactive props (such as `FARM PLOUGH` and `PEAGRAM'S DIG`) that collide with interactive waypoint and hotspot prompts.
**Alternatives:**
- Ad-hoc pixel offsetting per scenario: rejected because it introduces fragile coupling between scene layout and renderer code and breaks whenever entities move dynamically.
- Hiding all actor statuses when clustered: rejected because persistent status feedback (e.g. `[Guarding Dig Entrance]`, `[Standing]`, `[KNOCKED DOWN!]`) provides vital emergent narrative clues.
**Consequences:** Complete elimination of floating text collisions across all point-and-click and systemic simulation scenes, standardized crisp visual hierarchy (scale 2 names, scale 1 statuses), and 100% deterministic, zero-allocation rendering verified in pure Zig.

## D-025 Multi-Character Party Coordination, Generalized Item Transfer, and Temporal Epistemic Dialogue (2026-11-08, status: accepted)
**Context:** Multi-character adventure scenarios (such as *Day of the Tentacle*, *Maniac Mansion*, or ensemble party simulations) require players to control multiple distinct protagonists, switch active perspective across geographically or temporally partitioned scenes, exchange inventory items across characters without physical contact, and engage in dialogue where NPCs evaluate player propositions against their active world knowledge and beliefs.
**Decision:** Implement generalized party coordination, atomic inventory transfer, and epistemic belief evaluation in `src/spatial.zig`, `src/vm.zig`, `src/display.zig`, and `src/display/renderer.zig`:
1. **Generalized Party Inventory Transfer (`P21-01`, `D-001`, `D-003`, `D-009`):** Track registered party members (`party: []const EntityId`) and the currently active player protagonist (`active_player_character: EntityId`). Implement `transfer_item(item, from, to)` as an atomic relational fact swap: `world.forget(from, Carries, item)` followed by `world.remember(to, Carries, item, 0)`, emitting the `ItemTransferred(from, to, item)` simulation cue. Support configurable transfer policies: `.remote` (instantaneous transmission regardless of scene, such as Chron-o-Johns or telecom) and `.colocated` (requiring co-location in the same spatial room).
2. **Party Perspective Switching & Portrait HUD (`P21-01`, `D-008`, `D-014`):** Provide in-engine perspective switching (`switch_actor(target)`) via hotkeys (`[1]`, `[2]`, `[3]`) and interactive HUD portrait tokens. Switching active perspective synchronously swaps the active camera viewport, room scene graph, and visible inventory tray. Using an in-hand item on another party member's portrait initiates `transfer_item`.
3. **Epistemological Dialogue Belief Evaluation (`P21-02`, `D-015`, `D-017`):** Extend the relational dialogue engine (`D-015`, `D-017`) so NPCs dynamically evaluate candidate dialogue options against their active beliefs, knowledge facts (`Believes`, `Knows`, `Rejects`), and historical precedents before rendering choice blocks. Persuading historical figures (e.g. Betsy Ross or George Washington) requires asserting prerequisite evidence facts in the world.
4. **Forward-Propagating Temporal Causality (`P21-02`, `D-010`, `D-014`):** Enforce strict Directed Acyclic Graph (DAG) temporal propagation (Past -> Present -> Future). Actions executed in earlier eras project downstream into future topologies and prop states via reactive rule cascades (`when Past has X: mutate Present and Future`), preventing paradoxical retrocausal cycles. Model container duration catalysts (such as wine aging into vinegar inside sealed time capsules across centuries).
5. **The Day of the Tentacle Trio Scenario (`P21-03`, `D-008`, `D-011`, `D-019`):** Implement the three-era *Day of the Tentacle* milestone (*The Chrono-Mansion Trio*) in `src/dott_puzzle.zig` with 1790 Colonial Workshop (Hoagie), 1993 Motel Lobby (Bernard), and 2193 Dystopian Guard Post (Laverne), verifying the complete parallel puzzle diamond, item transfers, epistemic dialogue, and time-travel rewind.
**Alternatives:**
- Hardcoding a scenario-specific "Chron-o-John" flush action in the engine core: rejected because inventory exchange between party members is a fundamental game simulation mechanic that belongs in the general runtime, with narrative framing (time toilets, carrier pigeons, teleporters) provided by DSL scripts.
- Bidirectional temporal simulation: rejected because retrocausal loops introduce unsolvable constraint cycles; forward-only DAG propagation is 100% deterministic and preserves instantaneous time-travel snapshot rewinds.
**Consequences:** Enables multi-protagonist party simulations, seamless cross-character inventory logistics, belief-aware dialogue branches, and deterministic multi-era temporal causality verified in pure Zig.

## D-026 Portal-Anchored Transfers, Scene-Local Spatial Topology, Relational Constraint Logic, and Temporal Feedback Asymmetry (2026-11-08, status: accepted)
**Context:** Multi-era time-travel simulations (such as *Day of the Tentacle*) and parallel split-party adventures raise four fundamental design tensions:
1. **Geometric Topology vs. Relational State:** Naive implementations attempt to unify eras onto an overlaid Euclidean coordinate space $(x, y)$, assuming the mansion or location has a 1:1 spatial bijection across centuries. In reality, physical room layouts diverge completely over 400 years (open colonial lawn vs. commercial motel vs. dystopian security checkpoint).
2. **Diegetic Backtracking vs. Abstract UI Transparency:** Requiring characters to physically walk all the way back to their temporal portal (Chron-o-John) for every item swap destroys puzzle momentum and game pacing, while pure telepathic transfer ignores physical portal constraints (such as Laverne being trapped in a tree, or an unpowered portal).
3. **Imperative Scripting vs. Relational Constraint Solving (Prolog/Datalog):** As relational fact systems scale across multiple eras and actors, writing manual imperative state pipelines becomes unmanageable; the engine acts as a declarative constraint solver evaluating Horn clause conditions, invariants, and reactive rules.
4. **Temporal Telegraphing Asymmetry:** Players need to understand how past interventions affect downstream eras, but broadcasting cutscenes for every temporal interaction causes narrative fatigue.
**Decision:** Formalize and implement the following architecture across `src/spatial.zig`, `src/world.zig`, `src/vm.zig`, and `docs/ARCHITECTURE.md`:
1. **Topology is Scene-Local; Causality is Relational:** Never enforce coordinate overlays or geometric congruence across different eras or parallel dimensions. Each scene maintains its own discrete waypoint graph and visual perspective. The unified `World` relational fact arena serves as the singular cross-epoch truth (D-001, D-003, D-025).
2. **`TransferPolicy.portal_anchored` and Sender/Recipient Accessibility:** Implement an anti-backtracking transfer policy in `src/spatial.zig` that permits transparent inventory swaps from anywhere *provided* both sender and recipient can physically access their respective scene's transit portal (`SpatialSystem.can_access_portal`, `can_transfer_item_with_world`). Accessibility is an implied baseline for unblocked actors (Bernard in 1993 Motel Lobby and Hoagie in 1790 Colonial Workshop have open routes to their Chron-o-Johns); obstructed actors (Laverne in 2193 Dystopian Guard Post) can access their Chron-o-John *only* once physical obstacles are cleared (`not Trapped`) *and* security constraints are satisfied (she is granted bathroom yard escort `DoingBusiness` / `InYard` or disguised in the tentacle costume `TentacleDisguiseActive`). When an actor is physically proximate to the portal waypoint, the engine promotes the transfer to a concrete scene prop interaction (`ToiletFlush`, item in bowl).
3. **Constraint Logic over Imperative Plumbing:** Frame simulation rules declaratively: facts represent assertions, queries evaluate Horn clause conjunctions, and reactive `when` rules enforce invariants without imperative state plumbing.
4. **Asymmetric Downstream Feedback (Structural Mutation vs. Incubation):** Downstream physical mutations (e.g., felling a tree, altering a national flag pattern, modifying a statue's posture) telegraph their consequence to the player via reactive interrupt cutscenes (`interrupt Laverne with: ...`). Passive temporal incubations (e.g., running a sweater in a dryer for 200 years, aging wine in a time capsule) do not trigger interrupts; their transformed state is discovered organically upon future player inspection or retrieval.
**Alternatives:**
- Forcing a unified 3D/2D coordinate grid across all eras: rejected because historical architectural drift makes geometric congruence non-existent and arbitrarily limits level design.
- Mandatory physical transit to portal for every transfer: rejected because repetitive backtracking degrades puzzle pacing.
- Playing cutscenes for every temporal item transfer: rejected because predictable container incubations are more satisfying when discovered through natural inspection.
**Consequences:** Enables flexible, era-specific spatial level designs with transparent inventory logistics, grounded in diegetic portal constraints and clear narrative telegraphing rules.

## D-027 Cinematic Temporal Hypervisors, The Roberta Sparrow Tangent Model, and Pre-Cognitive Spatial Conduits (2026-11-08, status: accepted)
**Context:** Traditional adventure game time-travel (such as *Day of the Tentacle*, D-025, D-026) operates on sequential, unidirectional forward cascades across distinct epochs. Cinematic time-travel narratives introduce deeper simulation dynamics:
1. *Donnie Darko* ("The Philosophy of Time Travel" by Roberta Sparrow): Ephemeral Tangent Universe forking from a Primary Universe at $T_0$, bounded by an inevitable collapse countdown budget ($T_{\text{collapse}}$), teleological NPC manipulation ("The Ensured Trap"), illegal mass duplication ("The Artifact of Metal"), and fourth-dimensional pre-cognitive spatial pathways ("Vector Worms").
2. *Frequency*: Real-time bitemporal point-to-point synchronization across decades, where past physical alterations (carving letters into wood) instantly scorch and materialize on the corresponding object in the present viewport without resetting scene state.
3. *The Butterfly Effect*: Sensory anchor snapshot rewinding to historical keyframes, followed by fast-forward delta re-simulation that deposits the protagonist in an altered present with dual epistemic memory dissonance.
4. *12 Monkeys*: Strict Novikov self-consistency where all interventions are revealed to be the historical preconditions of the disaster.
5. *Back to the Future*: Asynchronous propagation latency where alterations cause gradual existence probability decay (photographic fading).
**Decision:** Formalize Phase 31 in `ROADMAP.md` and define the following engine architecture:
1. **Tangent Universe Hypervisor (`World.fork_tangent` / `collapse_tangent`):** An ephemeral copy-on-write world arena tracking a strict tick countdown deadline (`collapse_tick`). If the player satisfies the Roberta Sparrow loop invariants before expiration, the Artifact of Metal is committed to $T_0$ of the Primary Universe and the Tangent arena collapses safely into emotional dream residue; otherwise, the hypervisor executes a gravitational singularity fail-state.
2. **Pre-Cognitive Vector Conduits:** Expose the deterministic spatial A* planner's future waypoint trajectory across $K$ ticks in `DisplayBridge` and render it as a fluid, translucent Fourth-Dimensional conduit projecting from an actor's token to their destination.
3. **Teleological Horn Clause Solving:** Supplement greedy NPC behavior with backward-chaining teleological guidance, allowing future entities ("The Manipulated Dead", e.g. Frank the Rabbit) to emit priority interrupts and guidance cues back to the Living Receiver in the present.
4. **Concurrent Bitemporal Transceivers & Latency Decay:** Support synchronous dual-scene rendering for *Frequency*-style instant materialization, and probabilistic existence decay for *Back to the Future*-style fading.
**Alternatives:**
- Treating time travel as static branch trees: rejected because static trees cannot model dynamic countdown budgets, pre-cognitive spatial conduits, or bitemporal real-time materialization.
- Purely scripted cutscene time jumps: rejected because interactive emergence requires physical simulation over discrete relational facts.
**Consequences:** Establishes BeSpoke as an expressive engine for complex cinematic time mechanics, supporting countdown collapse budgets, visible spatial intention, and teleological puzzle design in pure Zig.

## D-028 Centralized Master Clock Frequency, 1.0 Hz Narrative Pacing, and Interactive Speed Scaling (2026-11-08, status: accepted)
**Context:** Simulation clock intervals in interactive runners were previously hardcoded between 150ms and 250ms (4 to 7 Hz), with *The Living Village* stepping every 20 frames (~333ms). This pacing caused rapid state expiration (threat-radius and distraction TTL windows vanishing in 3 to 6 seconds) and gave users insufficient real-world time to read narrative banners, inspect hotspots, or observe emergent relational cascades.
**Decision:**
1. **Centralized Master Clock Constants:** Define canonical simulation timing constants in `src/vm.zig` (`DEFAULT_TICK_INTERVAL_MS = 1000` ms / 1.0 Hz, `MIN_TICK_INTERVAL_MS = 100` ms / 10.0 Hz, `MAX_TICK_INTERVAL_MS = 3000` ms / 0.33 Hz) and provide stepping helper functions (`step_tick_interval_slower`, `step_tick_interval_faster`), re-exported in `src/root.zig`.
2. **Interactive Speed Adjustment:** Track `current_tick_interval_ms` in `DisplayWindow`, binding `[-]` / `[NumPad-]` to decrease speed and `[+]` / `[=]` / `[NumPad+]` to increase speed. Display active clock speed in the top-left HUD (`[RUNNING 1.0s] ([-]/[+] speed)` or `[PAUSED] (Space to run, N to step)`) and control prompt bar.
3. **Uniform Runner Integration:** Standardize all interactive scenario runners (`src/main.zig`, `src/dott_puzzle.zig`, `src/darko_puzzle.zig`, `src/goat_puzzle.zig`, `src/gk3_moustache.zig`, `src/spitting_contest.zig`, `src/runner.zig`, and `src/village.zig`) to drive simulation clock progression against `window.current_tick_interval_ms` using real-time millisecond timestamps (`std.time.milliTimestamp()`) rather than frame counters or scenario-specific constants.
4. **Decoupled Simulation and Display Rates:** Maintain complete decoupling between 60 Hz display rendering and discrete simulation clock steps. Single-step stepping (`[N]`) and pause toggling (`[Space]`) remain fully orthogonal to tick speed scaling.
**Alternatives:**
- Hardcoding a 500ms (2.0 Hz) fixed interval: rejected because 1000ms (1.0 Hz) matches deliberate theatrical timing for adventure dialogues and puzzles, and runtime speed controls allow instant acceleration when desired.
- Continuous delta-time (`dt`) accumulation in simulation logic: rejected because deterministic discrete integer ticks are a core architectural invariant of BeSpoke; variable time steps break replayability and snapshot serialization.
**Consequences:** Establishes deliberate, human-readable simulation pacing across all scenarios, eliminates hurried TTL window expiration, and gives players granular runtime control over simulation speed.

## D-029 Musical Drafts as Program Data, Reverse Entries, and Host Re-Dispatch of In-Script Weaves (2026-11-08, status: accepted)
**Context:** Phase 22 adds pitch-based spellcraft: a caster plays four diatonic notes, the sequence names a draft, and the draft acts on a target. Playing a draft backwards yields its complementary effect. Two forces shape the design. First, the VM executes bytecode without holding the `CompiledProgram`, so a `weave` statement cannot jump to a cue handler mid-tick. Second, save/restore must stay a pure arena copy (D-003), so draft data cannot grow pointer-bearing structures inside the world.
**Decision:**
1. **Grammar:** `draft <Name>(n1, n2, n3, n4) [reverse <Inverse>]` at top level; `weave <Draft> on <Target>` inside routine, cue, and rule bodies, with the executing fiber's owner as caster. Notes are `C D E F G A B` (`draft.Note`, values 0 to 6). Top-level `weave` is a compile error because it has no caster.
2. **Drafts are program data:** `CompiledProgram.drafts` holds `CompiledDraft{entity, notes, inverse}`. A declared reverse becomes its own entry with reversed notes, so note lookup needs no direction flag. Learning a draft is an ordinary fact the script asserts. Any caster may play any draft; gating is the script's job.
3. **Unambiguous sequences:** The parser rejects wrong note counts, unknown notes, a palindrome with a declared reverse, a draft named as its own reverse, duplicate names, and any draft whose notes match another draft forward or reversed. A played sequence therefore names at most one draft.
4. **Dispatch through the `Weave` cue (D-009):** `VM.weave_notes` and `VM.weave_draft` run the handler keyed `Weave:caster:draft:target`, then `Weave:caster:draft`. Matching is exact and ordered: no operand swap and no bare-name fallback, because either would run a different draft's effect where the weave should fail. A non-draft entity, or no matching handler, records a `WeaveFizzled` peripheral cue (draft id 0 for unrecognized notes).
5. **Host re-dispatch for in-script weaves:** Opcode `weave` (0x51) appends to `VM.pending_weaves`. The host calls `VM.dispatch_pending_weaves(&compiled)` after every `step_tick`; handlers run on the following tick. A chain of weaves advances one link per tick. `src/runner.zig` performs this call.
6. **Save safety:** `save.write_save_state` returns `error.PendingWeavesNotDispatched` while the queue is non-empty, and VM restore clears the queue. The `.sav` format is unchanged.
7. **Package format version 2:** `.bspk` appends the draft table to the payload tail. Version 1 packages still load with an empty table. Loaded note bytes and entity ids are range-checked.
**Alternatives:**
- Transient fact `WovenOn(target, draft)` with one-tick TTL consumed by `when` rules: rejected by the maintainer in favour of cue dispatch; it keeps weaves in the relational store but blocks re-weaving the same draft on the same target until the fact clears.
- Giving the VM a pointer to the compiled handler table for immediate dispatch: rejected for P22-01 because it widens the VM/program boundary; revisit if more opcodes need handler access.
- Implicit inverses for every draft: rejected because an undeclared inverse has no name for handlers to key on; reversing an undeclared draft fizzles unless it matches another draft, which rule 3 forbids.
**Consequences:** Musical drafts reuse the verb/cue path and the existing handler table. Hosts that drive `step_tick` directly must call `dispatch_pending_weaves`, or in-script weaves never fire and saves are refused. Cue handler `where` guards are not evaluated (see Claims vs. code in ARCHITECTURE), so weave affordances are expressed with `if` checks in handler bodies or with separate handler keys.

## D-030 Distaff Input as Host-Side Peripheral State, Mode-Gated Note Keys, and Degree-Only Audio (2026-11-08, status: accepted)
**Context:** P22-02 adds note input, note audio, and a staff HUD for the drafts of D-029. A half-played phrase, the set of playable notes, and the result of the last phrase all need a home. Only seven letter keys suit note input, and three of them already have global meanings (`c` console, `d` debug, `f`/`g` scenario actions).
**Decision:**
1. **Phrase state lives in the host:** `draft.DistaffInput` holds the phrase in progress, `reach` (playable notes counted from C), and the last `WeaveOutcome`. The runner owns it; `DisplayBridge.attach_distaff` copies it by value into `RenderFrame.distaff` each capture. It never enters the world arena, so snapshots and rewinds never capture a half-played phrase. The host sets `reach` from script facts.
2. **Mode-gated keys:** While `frame.distaff.enabled` and no dialogue balloon is open, the letters C D E F G A B play notes and Backspace clears the phrase. They shadow `c`, `d`, `f`, and `g` only in that mode; F1 (debug) and the backquote (console) stay available, and the footer advertises them. Notes beyond `reach` click and do nothing.
3. **Degree-only audio:** `AudioEvent.play_note` carries the raw degree (0 to 6), mapped to C4..B4 by `audio.DISTAFF_MIDI`. The synthesizer imports nothing from the simulation. Out-of-range degrees are dropped. `weave_success` and `weave_fizzle` are ordinary SFX the host triggers from the weave result.
4. **Immediate note feedback:** The window enqueues each note's audio on input, before the host processes the action, so the sound does not wait for a tick (D-001, D-019).
**Alternatives:**
- Phrase as world facts (`Played(Caster, Note)` with TTL): rejected because rewind would replay half-typed input and every keystroke would grow the fact table.
- Number keys 1 to 7: rejected because 1 to 4 already switch party members and select dialogue choices.
- Passing `draft.Note` to audio: rejected to keep `src/audio.zig` free of simulation imports.
**Consequences:** P22-03's runner owns a `DistaffInput`, attaches it, handles `.play_note` and `.clear_distaff`, calls `VM.weave_notes` on a full phrase, and sets `outcome` and the matching stinger. The wasm target and the manual simulator have no distaff yet.

## D-031 Engine and Proofs of Concept Separated by Module Boundary, Staged Purge of Proof Content (2026-11-08, status: accepted)
**Context:** Eight vertical slices (`dott_puzzle`, `gk3_moustache`, `spitting_contest`, `goat_puzzle`, `darko_puzzle`, `sword_fighting`, `loom_puzzle`, `village`) lived in `src/` beside the engine and were exported from the engine's root module, and The Tavern Heist was written inline in the engine CLI's `main()`. The maintainer clarified that these are proofs of concept: empirical evidence that engine features exist and work, not engine components. The coupling also runs the other way: engine files name proof entities and carry proof art, music, and flags.
**Decision:**
1. **Location:** All nine proofs live in `proofs/`. The Tavern Heist is extracted to `proofs/tavern_heist.zig`. `scenarios/` stays as sample `.bespoke` scripts for the stock CLI; those are game content, not host programs.
2. **Module boundary:** `build.zig` exports `src/root.zig` as the `bespoke` module. Proofs import it by name. Because `proofs/` lies outside the module's path, the compiler rejects any import from engine code into a proof.
3. **Binaries:** `bespoke` is engine-only (`run`, `compile`, `check`, `help`); former scenario flags print a pointer to the new binary. `bespoke-proofs` (`zig build proofs`, `zig build run-proof -- --<proof>`) keeps the old flag spellings.
4. **Tests:** `zig build test` runs both sides; `test-engine` and `test-proofs` run each alone.
5. **Staged purge:** Stage 1 (P32-01) moves files and splits the build. Proof content remaining inside engine files is removed in later, separately reviewable stages: presentation extension hooks for renderer and audio (P32-02), proof-specific logic and flags out of core logic and `RenderFrame` (P32-03), and the wasm deck split (P32-04).
**Alternatives:**
- Same binary with scenario flags, proofs linked as a second module: rejected by the maintainer so the engine binary links no scenario code.
- Full decoupling in one change: rejected by the maintainer; the renderer alone carries over 240 proof-specific lines, and one change would be hard to review.
- Leaving proof content in the engine permanently: rejected; it would keep the engine's core files coupled to demo names.
**Consequences:** Engine and proofs can evolve and be reviewed separately, and new proofs cannot leak into the engine by import. Until P32-02 to P32-04 land, engine files still name proof content (recorded under Claims vs. code in ARCHITECTURE). Commands of the form `bespoke --dott` become `bespoke-proofs --dott`.

## D-032 Emergent Society Simulation Is an Engine Mechanic; The Living Village Is Its Proof (2026-11-08, status: accepted)
**Context:** D-031 moved `village.zig` to `proofs/` with the other vertical slices. The maintainer clarified that the Living Village's emergent society simulation is a core mechanic, meant to be scalable and customizable/themeable, not only a demonstration. The current `VillageSimulation` hardcodes six named villagers, their need thresholds, and the settlement map, so it cannot serve other games as written.
**Decision:**
1. **Split:** A data-driven emergent society module moves into `src/` (P32-05): any roster size, configurable needs and thresholds, locations, and theme hooks supplied by the host or script. It names no villager, building, or setting.
2. **Proof:** `proofs/village.zig` keeps The Living Village content (Sheriff, Baker, Bakery, and the rest) and becomes a client of the engine module, verifying it end to end.
3. **Until P32-05 lands:** the simulation stays in `proofs/village.zig`. Front-facing docs present emergent society simulation as an engine feature being generalized, with The Living Village as its proof.
This amends D-031 rule 1 for `village.zig` only; the rest of D-031 stands.
**Alternatives:**
- Move `village.zig` back to `src/` unchanged: rejected by the maintainer; it would put demo names back into the engine that D-031 is removing.
- Leave the mechanic in `proofs/` permanently: rejected; other games could not reuse it.
**Consequences:** The engine gains a reusable social simulation layer, and the village proof gains the same role as the other proofs. Generalizing the drives, witness, rumor, and justice systems is new design work with its own review.

## D-033 Host Kit Module and One Time-Travel Model for Interactive Hosts (2026-11-09, status: accepted)
**Context:** Every proof carried its own copy of the plumbing around the VM: speech readers, look-at helpers, tick and dispatch, top-level statement runners, and an interactive loop with pause, step, scrub, rewind, and save handling. The copies drifted. Three speech readers took a cue index before `step_tick`, which clears `emitted_cues`, so later lines silently fell back to Zig-coded text or kept only the last speaker's line. Scrub semantics differed: some proofs kept the future while scrubbing, others truncated it immediately. One loop stepped the VM every display frame, contrary to D-028.
**Decision:**
1. **`src/host.zig`** provides `tick` (step plus weave re-dispatch), `SpeechLog` and `speech_this_tick` (speech read after the tick, every line attributed to its speaker, optionally filtered to one speaker), `act`, `run_initial_statements`, `has_state`, `place_waypoint`, `Timeline`, and `Session`. `DistaffInput.set_reach_from` covers the reach-from-fact pattern.
2. **One time-travel model:** scrubbing restores a snapshot and pauses without discarding the future; advancing from a past point discards the future first (a divergent timeline). This is the model TESTING's manual checks already describe. `[R]` steps back one snapshot by default.
3. **Proof overrides:** a proof may claim an action before `Session.handle_common` sees it. The Tavern Heist keeps `[R]` jumping to tick 2, Spitting Contest and Village to tick 0 (`Session.jump_to`). The Middlesex Anomaly disables scrub and rewind, because the hypervisor's tangent world and countdown live outside the world snapshot.
4. **Recording order:** a proof with post-tick rules ticks through `host.tick`, runs its rules, then calls `Session.record_now`, so snapshots include those effects.
**Alternatives:**
- Keep each proof's loop and fix the speech bug in place: rejected; the duplication is what let the bug and the drift spread.
- A callback-driven `Session.run(hooks)` that owns the loop: rejected for now; proofs have very different action handling, and a host-owned loop with shared pieces is easier to read and migrate.
**Consequences:** The DOTT and Middlesex Anomaly goldens changed in four lines: scripted dialogue the old readers dropped now appears (reviewed). DOTT, Middlesex Anomaly, and Insult Sword Fighting gain shared save actions; DOTT and Sword Fighting gain scrub and rewind; Sword Fighting now ticks at the D-028 interval instead of every frame. Interactive behaviour was verified only by offscreen launches, not by hand.

## D-034 Emergent Society Module: Host Config, Data Needs, Data Roles (2026-11-09, status: accepted)
**Context:** D-032 makes emergent society simulation an engine mechanic. P32-05 extracts it from `proofs/village.zig`, where six named villagers, their needs, their schedules, and the settlement were hardcoded. The maintainer chose (2026-11-09): host-supplied Zig configuration, an arbitrary need list, roles as data, and a byte-identical village golden.
**Decision:**
1. **Module:** `src/society.zig` provides `Society`, built from a `Config`: needs, a roster of members, an optional enforcer, holding and gathering waypoints, a flight route, radii, grudge durations, a currency unit, and themeable relation names. The config is copied into fixed capacities (32 members, 8 needs, 8 routine stops), so the society owns no heap memory.
2. **Needs are data:** each need is a property relation with a direction (`worse = .high` or `.low`), a per-tick rate, a resting rate, and a seek threshold, met either by a `Stay` (go to a place and recover until a value) or a `Trade` (buy relief from a merchant, or steal it past a critical value without the price). Internally every need is compared as pressure (0 is satisfied, `max` is worst).
3. **Roles are data:** a member may be a merchant (post and goods), a broadcaster (shares with anyone and seeks the enforcer with news), or the single enforcer (config index). Routines cycle through stops every `period` ticks, with optional work that earns currency and restocks goods.
4. **Fixed priority:** each tick a member takes the first applicable branch: held, staying, decay, enforcer on duty, start a stay, desperation theft, flight, trade, broadcast, routine. Then witnesses, rumors (one hop per tick), and justice run for everyone.
5. **State in facts only:** all society state is World facts, including the new `Tending` property (which stay need a member is meeting), so world snapshots, rewind, and saves cover it. The chronicle is presentation and is not part of the snapshot.
6. **Host order:** the host ticks the VM (`host.tick`), then calls `Society.step`.
**Alternatives:**
- Script declarations (`society:` blocks in the DSL): deferred to P32-22; it touches the parser, compiler, and package format.
- Fixed Hunger, Energy, and Gold drives with tunable thresholds: rejected by the maintainer; other games need other needs.
- Host callbacks for roles and routines: rejected by the maintainer; role behaviour would stay in proof code.
**Consequences:** The village proof is a client of the module and its golden is byte-identical. Behaviour outside the golden changed in reviewed ways: grudge expiry is now relative (the old code passed an absolute tick as a TTL, doubling it); members return to their idle activity after a meal (the Gossip and Drifter now show Socializing, not Working); an arrest without stolen goods no longer claims to recover bread; the unused `Mood` relation is gone. One enforcer per society. `RenderFrame` villager drives in `src/display.zig` still read `Hunger`, `Energy`, and `Gold` by name (P32-03), and the wasm village deck still runs its own copy (P32-04). D-032 rule 3 (the interim state) no longer applies.

## D-035 Dialogue Duel Module: Host Config, Choices Through the Dialogue Engine, Fatigue per Speaker and NPC (2026-11-09, status: accepted; learning rule superseded by D-078, scoring by D-079)
**Context:** The P32-11 audit found `DialogueDuelSystem` trapped in `proofs/sword_fighting.zig`: a challenge/response duel and an inquiry-fatigue mechanic, parameterized only by that proof's names (D-017). It built its candidate lists with its own World queries instead of the engine's fact-guarded choices, stored knowledge on raw entity ids 1 to 16 and 101 to 116 (ids that also belong to interned entities), and counted inquiries per speaker while ignoring its topic argument, so pestering one NPC tired every NPC. The maintainer chose (2026-11-09): host-supplied Zig configuration, candidates through `VM.prune_dialogue_choices`, and fatigue keyed per speaker and NPC.
**Decision:**
1. **Module:** `src/duel.zig` provides `Duel` and `InquiryFatigue`, each built from a config whose slices are borrowed. Ids are copied into fixed capacities (64 pairs, 4 tiers, 8 fatigue stages), so neither owns heap memory.
2. **Pairs and tiers are data:** a `Pair` is a name stem, a challenge line, the reply that counters it, and up to three tier variants of the challenge. Every challenge, variant, and reply is an interned entity (`<name>Challenge`, `<name>ChallengeT<tier>`, `<name>Reply`); `init` asserts `Counters(reply, challenge)` and `VariantOf(variant, challenge)` as permanent facts. An opponent's tier is a property fact. A variant of tier N is usable only against an opponent of exactly tier N; base challenges work against anyone.
3. **Candidates are dialogue choices:** `Duel.challenges` and `Duel.replies` build one `DialogueChoice` per line with `where` patterns over the knowledge facts (heard, mastered, tier) and filter them with `VM.prune_dialogue_choices` (D-015). Candidates come back in table order. With no reply mastered, the configured fallback line is the only reply.
4. **Rounds:** `resolve_round` teaches the defender the challenge, moves one point of advantage to whoever took the round, and on a failed reply teaches the defender the correct one. An optional `win_at` threshold raises the winner's win count and resets both advantages.
5. **Fatigue:** `InquiryFatigue.record(speaker, npc)` raises a count stored as a property on an entity interned per pair (`<speaker>-><npc>`), then asserts the highest stage that count reaches as `stage(npc, speaker)` with the stage's TTL. Stages are data (relation, count threshold, TTL, label). The count does not decay; moods do.
6. **State in facts only:** knowledge, tiers, advantage, wins, counts, and moods are World facts, so snapshots, rewind, and saves cover them. `init` runs before the first snapshot a host may restore.
**Alternatives:**
- A duel block in the DSL: deferred to P32-24; it touches the lexer, parser, codegen, and package format.
- Moving the proof's direct World queries into `src/` unchanged: rejected by the maintainer; the duel would sit beside the dialogue engine instead of on it.
- Keeping the per-speaker inquiry count: rejected by the maintainer; a second NPC would inherit the first one's irritation.
- A count packed into a fact's object beside the NPC id: rejected; the debug overlay and scripts could not read it. The per-pair entity keeps the count a plain property.
- Fatigue keyed by topic as D-017 rule 3 words it (`Inquired(speaker, topic, count)`): not done; a fact holds one subject and one object, and the proof never used the topic. D-017 rule 3 is amended to per speaker and NPC.
**Consequences:** The sword-fighting proof is a client of the module and its golden is byte-identical. Its fact vocabulary keeps `HeardInsult`, `MasteredReply`, `Counters`, `SwordMasterVariant`, and `IsSwordMaster` through the config's relation names, but the objects of those facts are now named entities, not raw numbers, and the inquiry count moves from `Inquired(speaker)` to `Inquiries(<speaker>-><npc>)`. Tier matching is exact because fact patterns test equality only. Each candidate query resolves entity names through pattern strings, a cost linear in the table size per call. The proof leaves `win_at` unset and scripts its own victory, so the win threshold is covered by engine tests only. The interactive sword-fighting loop still handles none of the duel keys it prints (P32-23).

**Update (P32-23, 2026-11-10):** The proof now declares `win 3`, so `Duel.resolve_round` owns its win threshold, and the interactive loop drives rounds through runtime-generated dialogue choices. The consequences above that the proof leaves `win_at` unset and that the loop ignores its duel keys are superseded. The sword-fighting golden remains byte-identical.

## D-036 Arrival Rules: `when <Actor> arrives at <Mark>:` as a Reactive Edge Fired Inside the Tick (2026-11-09, status: accepted)
**Context:** The P32-12 audit found the goat proof's interactive loop deciding, in Zig, what happens when George reaches the dig or the plough: the DSL had no way to react to an arrival, so the rule could not live in the script. The loop's check was a level (true on every tick George stood on the mark), which also sent him back down the ladder on the tick after he climbed out. The maintainer chose (2026-11-09) the rule form over an engine-fired cue, and chose to make arrival the single home of the goat proof's dig and plough rules.
**Decision:**
1. **Form:** `when <Actor> arrives at <Mark>:` is a fourth `when` form beside rising, `stops being`, and `forgets` (D-010, D-012). `arrives` is a keyword; `at` is matched as an ordinary word, so names may still contain it. The mark must be declared; an unknown mark or a missing `at` is a located compile error.
2. **What counts as arriving:** a walk intent completing at the mark, including a walk to the mark the actor already stands on. Resting on a mark, walking through it toward another mark, an abandoned walk, and being placed there (`SpatialSystem.transition_actor`) are not arrivals.
3. **Where it fires:** `MotorAgent` raises `arrival_pending` when a walk completes. `VM.evaluate_reactive_rules` checks arrival rules after the motor has stepped in the same tick, then clears every pending arrival, so each arrival is seen by exactly one rule pass. A walk completing in tick N fires in tick N; a zero-length walk issued by a fiber fires in tick N+1. No host dispatch is involved.
4. **Dispatch:** like other reactive rules, an arrival rule interrupts the actor's routine at the rule's priority, or spawns a routine for the actor when none is running.
5. **Encoding:** the compiled rule has one clause, `ArrivesAt(actor, waypoint id)`, with edge `on_arrive`. `ArrivesAt` is never asserted as a fact. `.bspk` format version 3 adds edge byte 3; the layout is unchanged, versions 1 and 2 still load, and a version 2 package carrying edge 3 is rejected.
**Alternatives:**
- An engine-fired `Arrives(Actor, Mark)` cue dispatched by the host after the tick, as weaves are (D-029): rejected by the maintainer; a host that steps the VM itself would miss arrivals, and cue handlers do not interrupt the actor's routine.
- A level rule (`when George is at DigOpening`): rejected; it re-fires or needs re-arming by leaving, which is what made the old loop bounce George between scenes.
- Counting a placement as an arrival: rejected; a host placing an actor in a new scene would re-trigger the rule that changed the scene.
- Excluding the zero-length walk: rejected; a player clicking the hotspot beside the actor would get no response.
**Consequences:** The goat proof's `Uses(George, CellarEntrance)` and `Uses(George, FarmPlough)` handlers only walk George; the charge, the retreat window, the tangle, the descent, and the climb back out are arrival rules, and the headless run now walks and waits for them, with a byte-identical golden. In the window a knocked-down George walks back to `FallMark` instead of snapping there, because the DSL has no placement statement, and clicking the ladder while standing on it climbs out. A rule whose body walks its actor to the same mark re-fires every tick; authors must avoid it. Arrival state lives in the motor, which world snapshots do not cover, so an arrival pending at the moment of a snapshot is not restored (one tick wide). A host that drives motors without a VM never clears `arrival_pending`; `SpatialSystem.clear_arrivals` is public for that case. P32-25 later made a mid-edge walk back to the waypoint just left replace the in-flight path with a return path and report arrival normally.

## D-037 Cue Dispatch Without a Bare-Name Fallback; Variable Parameters as Wildcards (2026-11-09, status: accepted)
**Context:** Codegen registered the first handler of every cue name under the bare name as a "fallback key", and `find_cue_handler` fell back to it. A cue fired for a pair no handler named ran that first handler: `Uses(George, TetherStake)` ran `Uses(George, CellarEntrance)`, and looking at an undescribed object repeated the first description in the script. P32-19 found two proofs carrying Zig fallback tables that this made unreachable. The same key was the only route to handlers declared with variable parameters (`verb TalkTo(speaker, target):`, `on cue PlayLute(Bard, target):` in `script_spec.md`), whose signatures were stored under the literal variable names. The maintainer chose (2026-11-09) to remove fallback to other targets.
**Decision:**
1. **No bare-name key.** A cue that no declared signature covers has no handler; `fire_cue` returns null and nothing runs.
2. **Variable parameters are wildcards.** A handler parameter starting with a lowercase letter, `_`, or `?` (the rule `when` triggers already use) is stored as `*` and matches any entity in that position. This keeps generic handlers reachable by declaration, not by accident.
3. **Order, most specific first:** the exact signature (two targets also swapped, D-013), then signatures with wildcards, then the actor-only handler `on cue X(Actor):`, which is the declared default for that actor.
4. **A handler needs an actor.** `on cue X():` is a located compile error; it could never be fired.
**Alternatives:**
- A parameterless handler as a catch-all for any actor: not chosen by the maintainer; `on cue X(anyone):` now says the same thing explicitly.
- Leaving dispatch as it was and requiring defaults in every script: rejected by the maintainer.
- Removing the fallback without wildcards: rejected during implementation; it would have made the spec's variable-parameter handlers unreachable.
**Consequences:** No proof golden changed. Interactive proofs that fire a cue for an unscripted pair now get no response where they used to get an unrelated handler. Variable parameters are still not bound in handler bodies: a body that names `target` refers to an entity called `target` (ARCHITECTURE, Claims vs. code). `.bspk` packages compiled before this change keep their old keys; handlers with variable parameters in them are unreachable until recompiled, and their bare-name keys are ignored.

## D-038 Proactive Social Agency: Dynamic Pursuit Agendas and Epistemic Contests (2026-11-09, status: accepted; refined by D-056)
**Context:** Classic mystery games (*The Colonel's Bequest*, *The Dagger of Amon Ra*) present wandering characters on static schedules that respond passively when interrogated. In BeSpoke, autonomous actors can possess social survival instincts: reacting to player actions or omissions by dynamically intercepting the player to persuade, dissuade, warn, or plant false alibis. The maintainer chose (2026-11-09) to architect this as a generalized, data-driven engine subsystem in `src/agency.zig` coordinating between `Society`, `SpatialSystem`, and `VM`, backed by idiomatic relational `World` facts and validated by "The Bayou Estate" vertical slice (`proofs/bayou_puzzle.zig`, `--bayou`).
**Decision:**
1. **Engine module (`src/agency.zig`):** `AgencySystem` is a reusable engine component holding data-driven `AgendaDef` configurations. It names no characters or narrative tokens (D-031).
2. **State is World facts:** All agenda states (`AgendaState(NPC, Pursuing)`, `AgendaState(NPC, Succeeded)`, `AgendaOutcome`), action telemetry, and epistemic beliefs exist as flat relational tuples in `World`. Zero internal agency state bypasses snapshot save/restore.
3. **Telemetry and omissions:** Actions write standard facts (e.g. `Investigated(Laura, CarriageHouse)`). Omission clauses evaluate negation against current facts (`where not Fact(...)`); temporal omission windows use TTL decay on prerequisite facts.
4. **Dynamic waypoint pursuit:** Alerted NPCs continuously track the target actor across the spatial waypoint graph via A* path recalculation on target movement or periodic intervals.
5. **Soft interrupts:** When an NPC achieves co-presence with the target, the interaction yields until the target completes their current edge and becomes idle. This launches the dialogue routine fiber without corrupting motor queues.
6. **Contention resolution:** If multiple NPCs target the player simultaneously, candidate agendas are resolved by highest priority, with graph distance as the tie-breaker. Unselected agendas pause or queue.
7. **Epistemic branching dialogue:** Interception encounters branch through fact-guarded dialogue trees (`VM.prune_dialogue_choices`). Rebuttals require physical evidence or witness facts; absence of evidence leaves the player vulnerable to persuasion or intimidation, writing outcome facts into `World`.
**Alternatives:**
- A direct extension to `src/society.zig`: rejected; `Society` focuses on schedules, roles, needs, and rumors. Separating agency into `src/agency.zig` keeps modular responsibilities clean.
- Automatic VM verb logging into a dedicated journal: rejected; idiomatic `World` facts asserted by cue handlers keep memory layout contiguous and debuggable via the existing fact inspector and snapshot engine.
- Hard mid-edge interrupts: rejected; freezing player movement mid-path corrupts motor agent state and camera transitions.
- Multi-turn social duel minigame: rejected; standard epistemic dialogue choice trees with evidence pruning naturally resolve persuasion and leverage while staying integrated with the narrative DSL.
**Consequences:** Actors actively counter player investigations in real time. The subsystem will be validated by Phase 33 ("The Bayou Estate" vertical slice).

## D-039 Presentation Through a Theme of Callbacks; Proof Art in One Shared Module (2026-11-09, status: accepted)
**Context:** After D-031 the engine's `render_frame` still chose a look by scene-name substring (20 flags), drew every proof's backdrop, drew props by hotspot-name substring and tokens by entity name, and picked footer hints per proof: about 2,400 lines of proof art and 62 proof colours inside `src/display/renderer.zig`, and the engine's default backdrop was the tavern. The maintainer chose (2026-11-09) callbacks over declarative art data, a staged delivery (P32-02a to P32-02d), and pixel goldens before the move.
**Decision:**
1. **Hook:** `renderer.Theme` is a struct of optional callbacks registered with `DisplayWindow.set_theme`: `backdrop`, `prop`, `actor`, `walkway`, `shows_walkways`, and `footer`. A drawing callback returns true when it drew the element; false hands it back to the engine. The theme draws with the window's public drawing functions and receives a `PropView` or `ActorView` holding the element, its screen position, and the label resolver.
2. **Engine defaults are neutral:** a plain framed stage titled with the scene name, a box for a prop, a labelled disc for an actor, a corridor line for a walkway, the generic key hints. The tavern is no longer the engine's default scene.
3. **Proof art lives in `proofs/art.zig`** as one theme shared by all nine proofs, with its scene detection, backdrops, prop and token chains, walkway style, footer hints, and palette. Each proof window calls `window.set_theme(&art.theme)`.
4. **Behaviour preserved by test:** the move had to leave every hash in `proofs/golden/render.txt` unchanged, and did.
5. **Keys (P32-02c):** `Theme.keys` lists `KeyBinding`s (an SDL keycode, a `u16` action, an optional SFX). `poll_events` checks them after the console, save drawer, dialogue, distaff, and party keys and before the engine's own letters, and returns `UserAction{ .custom = action }`. A proof binds keys with `art.with_keys(&...)` and decodes the action with its own enum. The engine's five scenario actions (`spit_contest_spit`, `sound_horn`, `drink_green_drink`, `tamper_flags`, `darko_follow_conduit`) and their global letter keys are gone, as is per-frame keyboard polling in proof loops.
**Alternatives:**
- Declarative art data interpreted by the engine: not chosen by the maintainer; every drawing would be rewritten as data and conditional art needs an expression format.
- One theme per proof: not done in this change. The prop chain matches generic substrings (`Door`, `Desk`, `Bar`) in a fixed order shared across proofs, so splitting it per proof risks changing which branch a prop takes. The boundary does not need the split; it can follow as its own change, checked by the same hashes.
- A theme that owns the whole frame: rejected; labels, hover prompts, HUD, and overlays are engine behaviour every game shares.
**Consequences:** The renderer shrinks from 6,214 to about 3,570 lines and names no proof scene, prop, or character outside tests (lint: 219 hits to 0 in that file; total 351 to 132). A proof without a theme still runs, with the neutral look. The theme is borrowed and must outlive the window. Callbacks run inside `render_frame` and must only draw. Bound keys fire once per press (plus OS key repeat); the GK3 and goat proofs polled `SDL_GetKeyboardState` every frame, so a held key used to act about 60 times a second. A binding wins over an engine letter: the goat proof's `[C]` now only changes scene, where it also toggled the REPL (still on `` ` `` and `[Tab]`). Still in the renderer and tracked elsewhere: HUD elements driven by proof-specific `RenderFrame` fields, such as the collapse countdown and the collapse modal (P32-03). The render goldens cover default states only, so progress-dependent art (a moved plough, a tampered flag) moved without pixel coverage; it was moved mechanically with the rest.

## D-040 Sounds as Data: Effect Patches and a Host Soundtrack (2026-11-10, status: accepted)
**Context:** After D-039 the audio module still held every proof's sound: an 11-value `MusicTrackKind` with each proof's 32-step pattern, a scene-name substring chain that picked a proof track (and the tavern for any unknown scene), and 18 sound effects, 9 of them proof-specific, each written as its own voice setup and its own per-sample mixing code. The maintainer chose (2026-11-10) effects as data patches over callbacks, the engine keeping only interface and distaff sounds, and audio goldens before the move.
**Decision:**
1. **Effects are `SfxPatch` data.** A patch gives two oscillator notes, a list of mix terms (oscillator 1 or 2 through a pulse, triangle, or saw shape; the noise generator, drawn once per sample; or a ring product of the two oscillators), a weight per term, a shift or truncating divide, duty, pitch sweep, envelope, length, and note steps that may loop. One generic voice renders every patch. The engine's nine sounds (`footstep`, `pickup`, `combine`, `alert`, `dialogue_blip`, `click`, and the three distaff sounds) are patches in `STOCK_SFX`.
2. **A host registers a `Soundtrack`:** named `Music` patterns, `SfxPatch`es, and a `track_for_scene` callback, all referred to by index. `AudioBridge.set_soundtrack` hands it to the audio thread through the event queue; `Theme.soundtrack` registers it when a window's theme is set. `Sound` names either an engine effect or a soundtrack effect.
3. **No engine music or default track.** Without a soundtrack the engine plays no music; with one, the callback decides, including the fallback for unknown scenes.
4. **Behaviour preserved by test:** `proofs/audio_golden_test.zig` hashes every effect, distaff note, track, a crossfade, and the track chosen for each proof scene; the move left `proofs/golden/audio.txt` unchanged.
**Alternatives:**
- Callbacks for voice setup and per-sample synthesis: not chosen by the maintainer; host code would run on the SDL audio thread.
- Keeping splash, whistle, sword clash, and thud as stock effects: not chosen by the maintainer; only effects the engine plays itself stay in it.
- An engine default track: rejected; the old default was the tavern's music.
**Consequences:** `MusicTrackKind` is gone and tracks are `?u8` indices; `SoundEffectKind` lists only engine sounds. The proofs' 11 tracks, scene rule, and 9 effects live in `proofs/art.zig` (`art.track`, `art.sfx`). A program that opens a window without a soundtrack, including the stock `bespoke run` runner, now plays no music where it played the tavern jig. The mix-term model reproduces the 18 existing effects exactly but is not a general synthesizer: an effect with a different per-sample rule needs a new term kind. A soundtrack is read by the audio thread and must not change after registration; a dropped queue event (queue full) would leave the synth on the old soundtrack. The separation lint reports no proof names in `src/audio.zig` (total 132 to 117).

## D-041 Proof Status in a Host Block; Guard Rule and Thumbnails From Host Data (2026-11-10, status: accepted)
**Context:** After D-039 and D-040 the core still knew the proofs in three places. `RenderFrame` carried 41 proof fields (goat, bell, DOTT, Middlesex, village drives, the tavern's cheese) that `capture_frame` filled by probing proof relation names, and the engine HUD drew the Middlesex countdown banner and collapse modal from them; `capture_frame` also guessed the player from a list of proof characters. `SpatialSystem.can_access_portal` special-cased the entity name `"Laverne"` and the relation `TentacleDisguiseActive`. Save thumbnails chose colours by proof scene and character name, and a save without a scene was named `Tavern`. The maintainer chose (2026-11-10) a host status block, theme overlay callbacks, a guard rule from facts the script or host asserts, and a thumbnail painter, with the render golden widened to progress states first.
**Decision:**
1. **Host status block:** `RenderFrame.host_status_bytes` is 2,048 bytes the engine never reads. A host registers a `StatusHook` with `DisplayBridge.set_status_hook`; it runs at the end of every `capture_frame` and fills the block, which the host's theme reads as its own type (`frame.host_status(T)`, size and alignment checked at compile time). The type must be valid when every byte is zero. The block is not cleared between frames.
2. **HUD and overlays:** `Theme.hud` draws after the top status bar and `Theme.overlay` last, above the save drawer, the two places the countdown banner and collapse modal were drawn.
3. **Player:** the inventory tray shows the player the host names (`set_party` or `set_active_character`), or none.
4. **Guard rule:** a `Guarded` (or `Detained`) actor reaches a portal only while it holds `PassesGuard` or `DoingBusiness` / `InYard`, or stands at the portal. The engine names no actor or disguise.
5. **Thumbnails:** a `ThumbnailPainter` (backdrop pixel and actor colour callbacks, each may decline) passes through `SaveOptions.thumbnail` and `SaveManager.thumbnails`, which `Theme.thumbnails` sets. The default is a neutral two-tone stage with gold actor dots; a save without a scene has an empty scene name.
6. **Preserved by test:** the render golden draws each scene once per piece of proof status (85 lines) and hashes each scene's thumbnail (20 lines); recorded before the move, unchanged after it.
**Alternatives:**
- A generic named flag table in `RenderFrame`: not chosen by the maintainer; the village panel and countdown text would need a second mechanism.
- Generic engine countdown and fail-state HUD elements: not chosen by the maintainer.
- Configurable relation names for the guard rule: not chosen by the maintainer; the script or host states the facts instead.
**Consequences:** All proof status, its capture, the countdown banner, the collapse modal, the guard facts, and the thumbnail palettes live in `proofs/` (`art.Status`, `art.capture_status`, `art.thumbnails`; DOTT asserts `Guarded` and `PassesGuard`). `DisplayBridge.set_tangent_countdown` and `set_singularity_collapsed` are gone (`art.set_countdown`, `art.set_collapsed`). Four engine renderer tests that rendered proof scenes from proof fields were removed; the render golden covers those scenes. A host that never names its player gets an empty inventory tray where the engine used to guess from proof names. Status a host writes directly to `back_buffer` lands in one of two swapped buffers, so it alternates frames unless rewritten each frame or captured by the hook (as before). The separation lint now skips `proofs/art.zig`, whose names all belong to proof scripts, and `--update-baseline` refuses a key the baseline has never seen unless `--accept-increase` is given. Engine lint hits: 117 to 79, all in `src/wasm.zig` (P32-04).

## D-042 Browser Runtime Decks Supplied by the Host; Two WebAssembly Modules (2026-11-10, status: accepted)
**Context:** `src/wasm.zig` held the browser runtime and, inside it, six proof decks: each deck's stage, the village's hand-written hunger and arrest rule, `[S]` catalysts, titles, and colours, chosen by a `WasmScenario` enum. It was the last engine file naming proofs (79 lint hits). Its `export fn`s were compiled into every build of the engine module. The manual's "Wasm32" simulator turned out to be a JavaScript model that never loads the module, and the committed `bespoke.wasm` faulted on its first call: `WasmRuntime.init` returns a 1.2 MB struct by value and the default wasm stack is 1 MB. The maintainer chose (2026-11-10) a deck table with an export builder, correcting the manual's claim, a wasm golden first, and fixing the stack in this change.
**Decision:**
1. **Decks are data:** `wasm.Deck` has a title, a background colour, and `load`, `after_tick`, and `catalyst` callbacks. `WasmRuntime.init(allocator, decks, index)` and `load_deck(index)` replace the scenario enum; keys `[1]` to `[9]` pick decks in table order.
2. **Exports are built per module:** `wasm.export_runtime(comptime decks)` emits the fourteen `wasm_*` C-ABI exports with `@export`, so the engine module itself exports nothing. `src/wasm_engine.zig` is the root of `zig build wasm` (`bespoke.wasm`, one neutral demo deck); `proofs/wasm_main.zig` is the root of the new `zig build wasm-proofs` (`bespoke-proofs.wasm`, the six proof decks from `proofs/wasm_deck.zig`). Both export the same names.
3. **The proofs' wasm module uses the engine as a module:** `build.zig` builds `src/root.zig` for `wasm32-freestanding` and imports it as `bespoke`, as the native proofs do (D-031); the wasm build references none of the SDL code.
4. **8 MB wasm stack** for both modules.
5. **The manual's simulator is a JavaScript model** and is described as one. `tools/wasm_smoke.js` runs both real modules in Node.
**Alternatives:**
- Moving the whole runtime into `proofs/`: not chosen by the maintainer; the engine would have no browser target of its own.
- Loading `bespoke-proofs.wasm` in the manual now: not chosen by the maintainer; a `file://` page cannot fetch it, so it would be embedded (about 1.2 MB).
- Building the runtime in place instead of returning it by value: a smaller stack would do, but it changes the runtime's API; a larger stack fixes the fault without that.
**Consequences:** `proofs/golden/wasm.txt` (six decks through a ten-step event script) was unchanged by the split. The separation lint finds no proof names in `src/` (79 to 0). Engine wasm tests drive two neutral test decks; the proof decks' behaviour is covered by the golden. Node is used only by the optional smoke check, not by the build. Neither module has run in a browser page here; Node exercised their exports.

**Update, 2026-11-10 (P32-29):** The manual now embeds `bespoke-proofs.wasm` as base64 and loads it without `fetch`, so it works from `file://`; the wrapper is `tools/manual_simulator.js`. `python3 tools/manual.py build` requires `zig build wasm-proofs` first and fails with a clear error when the artifact is missing. The fact list and REPL were removed because the module exports only `wasm_get_fact_count`, not fact rows or injection.

**Update, 2026-11-10 (P30-01 partial):** `site/index.html` uses the same embedded module through `tools/build_site.py` and `tools/site_simulator.js`. It remains a single self-contained page that runs from `file://`. The six decks auto-tick and use the module's pointer, key, catalyst, pause, and timeline exports. Its JavaScript model, fact rows, action bank, and deterministic event stream are gone. The site clamps the timeline to the runtime's 32-snapshot window; `Reset Deck` returns to tick 0. Audio and the remaining three decks are open.

**Update, 2026-11-10 (P23-03):** The proofs' module now carries seven decks; Caustic Grog joined the table with its own after-tick spill and stage rule. `proofs/golden/wasm.txt` records seven decks. The deck is proof content, so the engine's boundary is unchanged.

## D-043 Unary States Modelled as Predicate Presence (2026-11-10, status: accepted)
**Context:** `true` had three conflicting meanings in the codebase (P32-28): `now X is Y` interned the entity `true` as `object_or_value`; `VM.has_fact_pattern` read string `"true"` as numeric value 1; `when` reactive triggers parsed lowercase `"true"` as an unbound pattern variable `?true`. A host asserting a state fact with value 1 was invisible to script conditions.
**Decision:**
1. Unary states (`now X is Y`, `if X is Y`, `when X is Y`) represent predicate presence `Y(X)` without a synthetic second argument.
2. In `Fact`, `object_or_value` is 0 (`EntityId.none.to_int()`) when a state fact is asserted.
3. `if X is Y` compiles to `query_has` with mask `0x03` (`has_fact(X, Y, null)`).
4. `now X is not Y` forgets `(X, Y, null)`, clearing the predicate.
5. `when X is Y` and `when X stops being Y` trigger on rising and falling edges of `Y(X)` with wildcard object matching.
6. Host code asserts a state with `world.remember(subject, state, 0, ttl)` without interning `"true"`.
**Alternatives:**
- Numerical booleans (`1` and `0`): rejected because reserving `"true"` and `"false"` as numeric literals across the DSL complicates pattern variables and forces arbitrary integer values onto relational predicates.
- Reserved canonical entities (`EntityId.TRUE = 1`): rejected because unary predicates do not have objects; forcing an object entity creates an artificial dependency on entity IDs.
**Consequences:** Eliminates the synthetic `"true"` string and entity interning hack. All nine proof goldens remain unchanged. Unit test in `src/compiler/codegen.zig` verifies state lifecycle without entity interning.

## D-044 Neutral Mechanic Vocabulary for Temporal Hypervisors (2026-11-10, status: accepted)
**Context:** `TemporalHypervisor` used film-specific terminology from Donnie Darko (Tangent Universe, Artifact of Metal, vortex, singularity collapse) for generic branch-world mechanics (P32-21, P32-14 audit).
**Decision:**
1. The subsystem retains `TemporalHypervisor` as its core module name.
2. Branch classification uses `UniverseBranchKind` with `.primary` and `.branch` (aliasing `.tangent`).
3. Branch states use `BranchCollapseState` with `.dormant`, `.active`, `.budget_expired`, and `.resolved_and_merged` (aliasing `TangentCollapseState` and `.collapsed_singularity`).
4. Step results use `HypervisorStepResult` with `.running`, `.budget_expired`, and `.loop_resolved` (aliasing `.singularity_collapse`).
5. Hypervisor methods use `fork_branch`, `collapse_branch`, and `set_convergence_target` (aliasing `fork_tangent`, `collapse_tangent`, and `set_vortex_target`).
6. Entities and marks are named `keystone_entity`, `convergence_waypoint`, and `receiver_entity` (aliasing `artifact_entity`, `vortex_waypoint`, and `living_receiver`).
**Alternatives:**
- Full breaking purge without aliases: rejected because maintaining backwards-compatible aliases preserves existing proof callers and characterization goldens.
**Consequences:** Hypervisor API is completely generic and decoupled from narrative film vocabulary. All nine proof goldens remain unchanged.

## D-045 Society and Duel Configuration as Script-Owned Program Data (2026-11-10, status: accepted)
**Context:** D-034 and D-035 extracted reusable society and dialogue-duel mechanics, but every game still needed Zig arrays to configure them. P32-22 and P32-24 require those tables in the language and distributable package. The maintainer accepted complete script authority over both proof configurations while retaining the direct Zig APIs for engine embedding and tests.
**Decision:**
1. Top-level `society Name:` declarations define needs, member initial values, roles, routines, places, friendships, tuning, currency, and relation vocabulary. Top-level `duel Name:` declarations define challenge/reply pairs, tier variants and opponent assignments, win threshold, fallback reply, relation vocabulary, and inquiry-fatigue stages.
2. Declaration directives use one canonical positional grammar. Nested blocks express member and pair data. Names resolve during code generation; missing members, providers, activities, waypoints, and invalid capacities are compile errors.
3. `CompiledProgram` owns `societies` and `duels` declaration arrays and their allocated slices. Declaration text is interned in the World's entity-name table, giving it the same lifetime as other compiled program symbols.
4. Runtime modules keep their direct config APIs. A host selects a compiled declaration, calls `Society.init`, `Duel.init`, or `InquiryFatigue.init`, and applies a duel declaration's tier assignments. This supports multiple independent declarations without embedding proof content in the engine.
5. `.bspk` format version 4 appends society and duel tables to the payload. The loader validates capacities, references, enum values, indexes, and waypoints. Versions 1 through 3 remain loadable and produce empty declaration tables.
**Alternatives:**
- Retaining host-authored Zig tables as the game-facing format: rejected because games could not ship or theme these mechanics from `.bespoke` source alone.
- Encoding configuration as ordinary startup bytecode facts: rejected because routines need typed, immutable topology and tuning data, while runtime state belongs in facts.
- A free-form named-argument grammar: deferred. The positional grammar supplies a single representation and keeps this phase bounded; future syntax can lower to the same declaration types.
**Consequences:** The Living Village and Insult Sword Fighting scripts own their complete mechanic configurations. Their proofs contain no corresponding Zig config tables, and their goldens remain unchanged. Package v4 must be used to distribute these declarations. Program declarations borrow stable World text and therefore cannot outlive the World used to compile or load them.

## D-046 Executable Dialogue Lifecycle in World Facts (2026-11-10, status: accepted)
**Context:** Phase 13 introduced `choice` blocks and fact-based pruning, but codegen executed the first eligible choice body immediately; no fiber suspended for a player's selection. Hosts that wanted interactive dialogue kept their own if-ladders and `show_dialogue` calls (the GK3 proof did), so dialogue could not carry the same state through snapshots or serve as the foundation for P32-23's duel UI and Phase 33's epistemic encounters.
**Decision:**
1. A `choice` block compiles to `choices_begin`, one `offer_choice` per choice after its `if` and `where` guards, `choices_end`, then each body. The VM writes the offered set as World facts and suspends the fiber at `choices_end`; selecting a choice resumes that fiber at the selected body. With no eligible choice, the fiber continues at the instruction after the set and never suspends.
2. `src/dialogue.zig` owns the fact vocabulary: `DialogueRevision`, `DialogueOpen`, `DialoguePrompt`, `DialogueFiber`, `DialogueEnd`, `DialogueOption`, `DialogueBody`, `DialogueAction`, `DialogueChosen`, and `DialogueSpeaker`. Option entities are named `<owner>#<n>`; at most 9 are offered. The module names no game, speaker, or line.
3. The same lifecycle serves runtime-generated choices through `open_generated` and `VM.open_generated_dialogue`: text and an opaque host action id are stored as facts, no fiber is involved, and `choose` returns the action for the host to resolve. This is the interface P32-23's duel and Phase 33's encounters use.
4. Dialogue state is World facts, not host fields or VM-only state. Snapshots, `.sav` files, and timeline rewinds therefore carry the open set; `VM.sync_dialogue` reconciles a suspended fiber after a restore, releasing it when the restored world no longer contains its set. Save tag 6 preserves a `waiting_dialogue` fiber.
5. `RenderFrame.dialogue` publishes the open set to peripherals by revision; the renderer mirrors it into the speech balloon and dismisses it when the set closes. `DialogueSpeaker` lets a host present an NPC as speaking while the set stays keyed by the fiber owner for unambiguous selection.
6. `host.Session.choose_dialogue` selects a choice, advances one tick for scripted sets so the body runs, and records generated selections without ticking. Hosts call it from their dialogue-choice action.
**Alternatives:**
- Keep host-side if-ladders and only extend `prune_dialogue_choices`: rejected because the script's bodies would remain host logic and selection would not survive a rewind.
- Store the open set in the VM: rejected because `World` is the snapshot boundary, and dialogue must rewind with the facts it reads.
- Encode the display speaker in bytecode: rejected because a `choice` block does not name its conversation partner; presentation is host intent, not script structure.
**Consequences:** The GK3 Buthane conversation now runs through its script's choices with an unchanged headless transcript. `script_spec.md` documents the lifecycle, and `src/dialogue.zig` has fact-layer tests plus a compiler-to-VM test covering pruning, suspension, selection, generated actions, and snapshot restore. Older saves remain readable.

## D-047 Removal of Embedded WebAssembly Simulator from the Technical Manual in Favor of the Standalone Showcase (2026-11-10, status: accepted)
**Context:** P19-03 and P32-29 embedded `bespoke-proofs.wasm` into `docs/manual.html` as a base64 payload to provide an interactive canvas simulator deck. In practice, the simulator duplicated minimal wireframe scenarios without running full DSL scripts or fibers, provided minimal feedback on tick, inflated `docs/manual.html` from ~240 KB to 1.8 MB, and required `zig build wasm-proofs` before building manual documentation. The standalone showcase site (`site/index.html`) already contains the full interactive simulation viewport and browser event wrapper (`tools/site_simulator.js`, `tools/build_site.py`).
**Decision:** Remove the embedded simulator deck, canvas styles, base64 payload, and `tools/manual_simulator.js` wrapper from `tools/manual.py` and `docs/manual.html`. Retain the standalone `wasm32-freestanding` compilation pipeline and exports (`src/wasm.zig`, `proofs/wasm_deck.zig`, `zig build wasm`, `zig build wasm-proofs`) powering `site/index.html` and headless Node checks (`tools/wasm_smoke.js`).
**Alternatives:**
- Keep the simulator in `docs/manual.html` and expand `proofs/wasm_deck.zig` with full scripted routines: rejected because it duplicates the showcase website, inflates documentation size, and adds build coupling to offline developer docs.
- Revert to the JavaScript-only mock simulator: rejected because an inaccurate mock contradicts the 3x documentation contract.
**Consequences:** `docs/manual.html` is restored to a standalone ~240 KB document without binary bloat. `python3 tools/manual.py build` no longer depends on pre-building WebAssembly binaries. `tools/manual_simulator.js` is deleted. The WebAssembly target and browser bridge remain fully supported and verified via `site/index.html` and `tools/wasm_smoke.js`.

## D-048 Atomic Temporal Snapshots for Hypervisor Branch State and Saves (2026-11-10, status: accepted)
**Context:** D-033 disabled scrub and rewind in the Middlesex Anomaly because `TemporalHypervisor` keeps its branch world and countdown outside `World`'s snapshot. The save drawer still exposed save/load for that proof, so a restore could rewind the primary world while leaving the branch and countdown ahead. This was an inconsistency between the claimed timeline and the persisted state, not a limitation of the hypervisor model.
**Decision:**
1. Define a versioned temporal envelope in `src/temporal_snapshot.zig` carrying the branch world, branch active flag, budget and elapsed ticks, collapse state, receiver and keystone entities, convergence waypoint, teleological dependencies, and dream residue.
2. `host.Timeline` records and restores `World` plus the optional envelope as one snapshot. `Session.initWithHypervisor` opts a host into temporal recording; `restore_with_temporal` rejects a snapshot that has no envelope.
3. Write `.sav` version 2 with a length-delimited temporal section before the world, spatial, and VM sections. Decode and validate the envelope before mutating primary state, then apply it only after the primary restore. Version 1 saves remain readable by non-temporal loaders; a temporal loader rejects a version 1 or envelope-less save with `MissingTemporalState`.
4. Darko uses `initWithHypervisor`, records after actions and hypervisor ticks, and no longer intercepts scrub or rewind.
**Alternatives:**
- Keep the fixed timeline and disable save/load in Darko: rejected because it hides state the UI already offered and leaves the phase's rewind claim false.
- Store the branch world and countdown as ordinary `World` facts: rejected because the branch is a separate arena with its own tick and clone lifecycle; flattening it would collapse the hypervisor boundary.
- Write a world-only version 2 and reconstruct the branch on load: rejected because countdown, dependencies, and residue cannot be reconstructed deterministically.
**Consequences:** `.sav` version 2 is larger by one encoded branch world for temporal sessions. Existing version 1 saves still load in non-temporal tools; they cannot be loaded into a temporal session. Darko's timeline and saves now restore branch and countdown atomically. D-033's fixed-timeline override is retired. D-049 closes the subsequent action-routing gap.

## D-049 The Active Temporal Branch Is the Gameplay Action World (2026-11-10, status: accepted)
**Context:** D-048 made the primary and branch arenas one atomic persistence unit, but Darko's interactive VM, display, and direct actions still targeted primary while `TemporalHypervisor.check_loop_closure` inspected the branch. Player actions therefore appeared in the window yet could not close the loop. The maintainer required P31-05 to close before Phase 23.
**Decision:**
1. `TemporalHypervisor.active_world` returns its branch while the branch is active and its primary world otherwise.
2. A temporal `host.Session` binds the VM to the active world and captures display and dialogue state from it. Initialization, refresh, tick advancement, timeline restore, and save restore re-establish the binding because applying a temporal snapshot replaces the branch arena.
3. Game actions query and mutate `Session.active_world`; they never mirror ordinary mutations into both arenas. Primary and branch remain separately serialized under D-048.
4. Branch collapse returns action authority to primary. The generic hypervisor commits only the keystone and declared dream residue. A proof or game explicitly projects any additional causal consequences that its narrative preserves after collapse.
**Alternatives:**
- Mirror every interactive mutation into primary and branch: rejected because primary would accumulate events that occurred only in a failed branch.
- Leave VM and display on primary while routing only loop facts to branch: rejected because inventory, dialogue guards, status, and rewind would show different worlds.
- Give Darko a proof-local arena selector: rejected because every temporal host needs the same lifecycle boundary.
**Consequences:** Darko's inventory actions, cue execution, dialogue effects, and loop-closure facts share the arena the hypervisor evaluates. Timeline scrub, rewind, and save/load replace and rebind the branch without leaving a stale VM pointer. Hosts that advance a hypervisor outside `Session.advance` call `Session.sync_active_world` before using the VM; `Session.refresh` does this automatically.

## D-050 Script-Declared Fact-Backed Container Degradation (2026-11-10, status: accepted)
**Context:** Phase 23 originally named proof-specific mug states inside `World` and placed its proof in `src/`, which conflicts with D-031. The maintainer accepted a generic engine subsystem, temporary stage overrides rather than entity replacement, complete rewind state, script authority, and an engine-owned lifecycle before implementation.
**Decision:**
1. `src/container.zig` defines generic degradation profiles. A vessel retains one stable entity; ordered stage entities express its current physical condition. The final stage has zero duration and represents terminal failure.
2. Contents, volume, stage, exposure deadline, and failure waypoint are World facts. Terminal failure removes the configured substance, sets volume to zero, and records the vessel's current waypoint when available. Reconstructing `ContainerSystem` around restored facts does not reseed or repair them.
3. A top-level `degradation Name:` declaration owns the substance, stages, vessels, initial volume and stage, capacity, and optional five-name fact vocabulary. `CompiledProgram` owns any number of declarations; proof names and themes do not enter `src/`.
4. `host.initialize_subsystems` seeds declared profiles before the initial snapshot. `host.tick` initializes idempotently before `VM.step_tick`, then advances degradation before dispatching pending weaves. The stock runner uses the same lifecycle.
5. Advancement scans the declaration's governed vessels for an absent current-stage exposure fact. It does not consume `World.recently_expired`, whose fixed 16-entry diagnostic ring cannot safely govern simultaneous transitions.
6. `.bspk` format version 5 appends degradation declarations. The loader bounds counts and validates entity references, capacities, stage order, durations, initial values, and relation text. Versions 1 through 4 remain readable with an empty degradation table.
7. P23-02 adds atomic pouring and movement spill rules. P23-03 belongs in `proofs/grog_puzzle.zig`; the native proof receives headless, interactive, golden, save, and rewind coverage before any separate browser deck.
**Alternatives:**
- Replace the vessel entity at every stage: rejected because inventory and spatial identity would need transfer bookkeeping and a rewind could observe discontinuous ownership.
- Store timers or volume in a host struct: rejected because World is the ordinary snapshot boundary and the maintainer requires full rewind.
- Drive degradation through `on_expire` or `recently_expired`: rejected because the expiration ring is bounded and reactive expiration matching does not provide a lossless multi-profile lifecycle.
- Configure profiles only in proof Zig: rejected because distributable scripts and packages must own game-facing mechanic data.
**Consequences:** Container degradation is reusable across themes and multiple declarations. Hosts using `host.tick` receive the lifecycle automatically. Direct callers of bare `VM.step_tick` do not advance declared subsystems and remain outside the supported host lifecycle. Package v5 is required to distribute degradation declarations.

## D-051 Atomic Pouring, Persistent Damage, and Movement Spill (2026-11-10, status: accepted)
**Context:** P23-02 needs rapid transfers to preserve liquid as matter while damage belongs to physical vessels. The maintainer accepted full-volume atomic pouring, no magical repair, exposure reset at the destination's current stage, empty-vessel suspension, movement-based spill, and a delivered-volume threshold.
**Decision:**
1. `ContainerSystem.pour(source, target)` transfers the complete source volume or returns an error before mutation. Both vessels must belong to the same profile; the target must be empty, nonterminal, and large enough. Profile membership is compatibility.
2. Vessel stages never transfer or reset. The emptied source retains its damage and loses its contents and exposure fact. The destination retains its damage and receives a new exposure deadline for that stage.
3. `spill_per_moving_tick` removes bounded volume before degradation evaluation. A vessel spills while it is a moving motor agent or is held by a moving subject through the canonical `Carries` relation. Reaching zero removes contents and exposure, so an expiry on the same tick cannot degrade an empty vessel.
4. `has_volume_at_least` exposes a generic delivery-threshold query; lock identity and required volume remain proof data.
5. A `spill N` directive supplies the rate. `.bspk` version 6 adds the field; version 5 declarations load with zero spill.
**Alternatives:**
- Partial pours into smaller vessels: rejected because a failed rapid transfer would become a hidden lossy mutation and complicate atomic interaction feedback.
- Restore the destination to its first stage: rejected because pouring liquid cannot repair physical damage.
- Reset the source timer or keep empty vessels degrading: rejected because exposure belongs to the vessel currently holding the substance.
- Store a lock threshold in the engine profile: rejected because delivery goals are game rules, while the engine only needs a volume predicate.
**Consequences:** Games can build transfer chains without duplicating or silently destroying liquid. The only modeled loss is the declared movement spill. Callers surface pour errors as interaction feedback and decide which volume threshold satisfies their goal.

## D-052 Stageplay Paths as World Facts and Guarded Routines (2026-11-10, status: accepted)
**Context:** Phase 24 needs operational approaches whose incompatible facts and routines cannot both run. The DSL had fact-guarded dialogue pruning but no declaration of a route, no active-route state, and no way to mute a routine that belonged to another approach. The roadmap specifies `path Wits:`, `path Fists:`, and `path Team:` declarations with path-locked facts and muted alternative routines.
**Decision:**
1. A top-level `path <Name>:` block owns fact statements (`remember`, `forget`, `now`) and nested routines. Path names are entities; `PathActive(<Name>)` is the single active-route predicate.
2. `VM.select_path(compiled, name)` may select one path. It asserts `PathActive(Name)` immediately, then spawns the path's fact initializer, which runs on the next tick. Selecting the same path again is a no-op; selecting a different path returns `error.PathAlreadyChosen`. Switching paths is deliberately deferred.
3. Path initializer bytecode is stored under the reserved routine key `#path:<Name>`. The `#` prefix is not a DSL identifier, so it cannot collide. No `.bspk` version bump is needed: the existing routine table carries the initializer and the relation table carries `PathActive`.
4. Every path-owned routine starts with a `PathActive(<Name>)` guard. If the path is not active, the guard jumps to the routine's trailing halt before any body instruction. Inactive route routines are muted even when a host spawns them directly.
5. Path routine names share the top-level routine namespace; a collision is a compile error. `CompiledProgram.find_path` resolves an initializer, and scripts query the route with `if PathActive(Wits):`.
6. Path facts are ordinary World facts after selection. Save, rewind, and temporal restore capture them without VM state.
**Alternatives:**
- Keep route selection in a VM field: rejected because save and rewind would need a new serialized state channel.
- Compile alternative paths out of the program entirely: rejected because the host chooses at runtime and a loaded package must retain every route.
- Put guards only in cue dispatch: rejected because hosts also spawn routines directly; a routine-local guard covers both paths.
**Consequences:** P24-01 provides the route-selection and muting primitive. P24-02 can layer topology and dialogue mutation on `PathActive` facts. P24-03 supplies the player-facing selector. Switching an active path is not supported yet; a later change must decide how to retract the previous path's facts and fibers.

## D-053 Fact-Backed Waypoint Locks and Route-Scoped Repertoires (2026-11-10, status: accepted)
**Context:** P24-02 must alter spatial topology and dialogue when a path is selected. The graph is static engine data and `SpatialSystem.walk_to` had no World, so scripts could not lock a route's waypoint. Dialogue already pruned from facts, but no documented route pattern existed.
**Decision:**
1. `WaypointBlocked(<Mark>)` is the single waypoint-lock predicate. The waypoint is matched to its mark entity by name, the same convention as arrival marks and hotspots.
2. `SpatialGraph.find_path_avoiding` excludes blocked waypoints during A*. A blocked goal yields no path; a blocked start may still be left. `SpatialSystem.walk_to_with_world` builds the blocked set from World facts and plans the path. `walk_to` remains a lock-free graph-only convenience for hosts; the VM's `walk_to` opcode calls the world-aware form.
3. Locks apply when a walk is planned. An agent already in transit keeps its path; this change does not interrupt or reroute fibers mid-edge.
4. Existing obstacle rules (`Trapped`, `PortalBlocked`, `Guarded`, `Detained`, `PassesGuard`, `DoingBusiness`, `InYard`) remain fact predicates. Path initializers may assert or clear them, and `SpatialSystem.can_access_portal` reads current World state.
5. NPC repertoires use the existing choice guard: a top-level handler offers route-specific options with `if PathActive(<Name>):`; `VM.prune_dialogue_choices` removes the others. No dialogue state is added.
6. Locks and path facts are ordinary World facts. No `.bspk` bump is needed; save and rewind restore the route and its topology effects together.
**Alternatives:**
- Store locks on `SpatialGraph`: rejected because graph mutation would need a save format and path facts would duplicate state.
- Add a path argument to `walk_to`: rejected because path selection is already represented by active facts; the engine can read the World instead of naming routes in call sites.
- Interrupt in-flight walks when a lock appears: deferred because it needs a route-change policy and fiber resumption semantics; P24-02 shapes the next walk intent only.
**Consequences:** P24-03 can select a route, lock its incompatible waypoints, and prune its dialogue. Switching paths still requires retracting the previous path's facts and fibers (D-052).

## D-054 Discrete Grid Overlay With Sparse Fact-Backed Cell Attributes (2026-11-10, status: accepted)
**Context:** P25-01 adds the discrete 2D grid that D-005 and Q-001 deferred, as an optional overlay that complements the waypoint graph rather than replacing it. Phase 25's automata (P25-02) will mutate cells every tick, and the maintainer requires full save, rewind, and branch restore. The maintainer accepted static geometry on the grid, mutable attributes as facts, a script declaration with `.bspk` version 7, one grid per room with waypoints mapped by position, blocking cells honored at walk planning, and a fixed attribute set.
**Decision:**
1. `src/grid.zig` defines `Grid` geometry: entity, room, width, height, cell size, and origin in room coordinates. `SpatialSystem.grids` holds at most one overlay per room; geometry is program data and is never written to `.sav`.
2. Cell attributes are the fixed set `flammable`, `liquid`, `blocking`. Each set attribute is one World fact on the grid entity (`CellFlammable`, `CellLiquid`, `CellBlocking`, set relations) whose value is the row-major cell index. An unset attribute has no fact, so the fact table grows with populated cells, not grid area. A grid holds at most 4096 cells.
3. A top-level `grid <Name> in <Room>:` declaration owns size, cell size, origin, attribute cells or rectangles, and `place <Mark> x y`, which moves a mark of that room to a cell centre and refreshes its edge costs. `host.initialize_subsystems` seeds the initial layout once and asserts `GridSeeded(Grid)`; later calls, including after a restore, leave runtime changes in place.
4. A waypoint maps to the cell containing its position in its room's grid. `SpatialSystem.waypoint_blocked` treats a `blocking` cell like `WaypointBlocked`: world-aware walks plan around it, a blocking destination refuses the walk, and an in-flight walk keeps its path (D-053). The lock-free `walk_to` ignores cells.
5. `.bspk` version 7 appends the grid table. The loader bounds grid and cell counts and validates entity references, geometry, cell indexes, attribute bytes, duplicates, and one grid per room. Versions 1 through 6 load with no grids.
**Alternatives:**
- A dense cell array owned by the grid, saved in a new `.sav` section: rejected because World is the snapshot boundary, and a second state channel would need its own rewind and hypervisor-branch handling.
- One World entity per cell: rejected because interning an entity per cell spends names and entity slots on empty cells and gives scripts no way to address a cell by coordinate.
- Script-declared attribute names: deferred; P25-02's rules need a known vocabulary, and a fixed enum keeps package validation exact.
- Grid as the primary topology: rejected by D-005; adventure scenes stay waypoint-first.
**Consequences:** Grid cell state is saved, rewound, and branched for free. `host.tick` reseeds nothing after the first tick, but calls the seed check each tick (one fact scan per grid). Scripts address cells only through their index value; DSL coordinate queries and automata rules arrive with P25-02. Liquid is a presence flag with no depth; flow volume, if needed, is a P25-02 decision.

## D-055 Grid Automata as Synchronous Rules Over Fact Lifetimes (2026-11-10, status: accepted)
**Context:** P25-02 adds fire spreading, smoke dissipation, water flow, and reactive interrupts on actors in hazardous cells. The rules mutate cells every tick and must survive save, rewind, and branch restore exactly. The maintainer accepted script-owned rates with `.bspk` version 8, fact lifetimes as timers, synchronous deterministic updates, flow without depth, hazard presence facts on agents, and a step after the VM tick.
**Decision:**
1. Two attributes join the fixed set: `burning` (`CellBurning`) and `smoke` (`CellSmoke`). A grid declaration may set four rates, each zero (off) by default: `burn N` (ticks a fire lasts), `spread N` (ticks a fire burns before it ignites neighbours), `dissipate N` (ticks smoke lingers after its fire last fed it), and `flow N` (liquid floods on ticks divisible by N).
2. Timers are fact lifetimes. Ignition removes `flammable` and remembers `CellBurning` with a TTL of `burn`; World pruning ends the fire, leaving a spent cell that cannot relight. A fire's age is `burn` minus its remaining lifetime. A permanent fire (no `burn`) counts as old enough to spread. Each fire refreshes its cell's `CellSmoke` lifetime; declared permanent smoke stays permanent.
3. `grid.step` reads every cell once, decides all ignitions (flammable, dry, unlit 4-neighbours of fires old enough) and floods (non-blocking dry 4-neighbours of liquid, on the flow cadence) from that start-of-step state, then applies them. Liquid then douses any fire in its cell, and remaining fires refresh smoke. No randomness; results do not depend on cell order.
4. `SpatialSystem.update_grid_hazards` mirrors the agent's cell as unary states `InBurningCell`, `InSmokeCell`, and `InLiquidCell` (D-043). Scripts react with existing edge-triggered rules (`when Hero is InBurningCell:`), which can interrupt fibers. An agent outside every grid has none.
5. `host.tick` runs each grid's step after the VM tick and container step, then the hazard update, before weave dispatch. Rules therefore see a hazard on the tick after it appears. Programs without grids skip both, so their relation tables and goldens are unchanged. Temporal sessions tick the active branch world the same way.
6. `grid.ignite` is the host action for a torch or spell: it lights a flammable, dry, unlit cell with the declared lifetime.
7. `.bspk` version 8 adds the two attribute bytes and four rates per grid. Version 7 grids load with every rule off and reject attribute bytes above `blocking`.
**Alternatives:**
- A per-cell ignition-tick fact or a deadline relation like D-050: rejected because the fact's own expiry already carries the deadline and pruning ends the fire with no extra scan.
- In-place updates in scan order: rejected because fire would race along the scan direction and rewinds would depend on iteration order.
- Random ignition chances: rejected for now; deterministic spread is easier to author and verify, and a seeded roll can be added as a rate later.
- Liquid depth and source cells: deferred; a presence flag with a flow cadence covers dousing and flooding, and depth would need a property relation per cell.
- Cue dispatch on entering a hazard: rejected in favour of state facts, which give rising and falling edges, survive rewinds, and need no new dispatch path.
- Interrupting an in-flight walk when its path catches fire: deferred, as in D-053; the hazard state lets a script interrupt the walker instead.
**Consequences:** Hazard state is ordinary World state, so saving, rewinding, and branching need nothing new. Each grid step costs one pass over the fact table plus fixed work per cell (bounded by 4096 cells). Flooding is unbounded within a room unless blocking cells contain it. Hazard reactions lag one tick behind the cell change.

## D-056 Script-Declared Agendas, Owned Trigger Clauses, and Per-Agenda State (2026-11-10, status: accepted)
**Context:** P33-01 begins D-038's agency subsystem. D-038 predates D-043 (unary states as presence), D-045 (mechanic configuration owned by scripts), and D-055 (timers as fact lifetimes), and its state shape `AgendaState(NPC, Pursuing)` cannot hold two agendas for one NPC. `when` rule clauses cannot be negated, so omission triggers need a home. The maintainer accepted the defaults below; this decision refines D-038 without reversing it.
**Decision:**
1. A top-level `agenda <Name>:` declaration owns its actor, target, priority, optional `cooldown N`, optional `once`, and trigger lines. `CompiledProgram.agendas` holds them; `.bspk` version 9 stores them.
2. Trigger lines are `requires Rel(A, B)` (must hold) and `unless Rel(A, B)` (must not hold), with constant names or `_` wildcards and no variables; a one-argument line matches any object. An agenda is triggered when every line holds. Omission windows use expiring prerequisite facts (D-038 point 3). The `when` rule engine is unchanged.
3. Each agenda is an entity. Its stage is the property `AgendaState(Agenda, Idle | Pursuing | Done)`; `Done` is reached only by `once` agendas. A cooldown is the presence fact `AgendaCooldown(Agenda)` expiring after N ticks.
4. `agency.step` runs in `host.tick` after the grid step when a program declares agendas. A pursuing agenda whose trigger stops holding returns to `Idle` without a cooldown. Each idle, triggered, cooled-down agenda is a candidate; per target, one agenda pursues at a time, chosen by highest priority, then shortest route cost from actor to target, then declaration order. An existing pursuit is not preempted, and an actor pursues one agenda at a time.
5. `agency.resolve` ends a pursuit: a `once` agenda becomes `Done`; any other returns to `Idle` and starts its cooldown. P33-02 calls it after the interception cue; until then hosts may call it directly.
6. P33-02 will add a `Pursuing(NPC)` unary state that `Society.step` honours by not moving that NPC, so society routines and pursuit do not issue competing walks.
**Alternatives:**
- Configure agendas in host Zig only: rejected; distributable games own mechanic data in scripts since D-045.
- Add negation to `when` clauses: deferred; it would change reactive rule matching, codegen, and package layout for every script, while agendas need only constant clauses.
- `AgendaState(NPC, Stage)` as D-038 wrote it: rejected because one NPC may hold several agendas.
- Preempt a lower-priority pursuit when a higher one triggers: deferred; without interception (P33-02) there is no observable cost to waiting, and preemption needs a policy for the abandoned agenda.
**Consequences:** Agenda state saves, rewinds, and branches with the World. Script clauses cannot bind variables, so an agenda names its own actor and target. The P33-03 slice will use an original cast and setting; the planned homage would recreate an existing game's characters.

## D-057 Typed Commands: Engine Default Frames, Script Commands and Aliases, Scoped Nouns, a Focused Command Bar (2026-11-10, status: accepted)
**Context:** Phase 26 adds Infocom-style typed commands that fire the same cues as mouse verbs. The engine has no fixed verb-to-cue table (each proof chooses cue names), `verb X(...)` is only another spelling of `on cue X(...)`, the window already owns one text field (the REPL), and letter keys are bound by the engine, the distaff, and proofs. The maintainer accepted the defaults below.
**Decision:**
1. `src/command.zig` is an engine module naming no proof content. It lowercases input, splits words, drops the articles `a`, `an`, `the`, and tags the prepositions `with`, `on`, `to`, `about`, `into`, `in`, `at`, `from`.
2. A frame is a sentence shape: literal words and up to two `<thing>` slots, mapped to a cue (`pour <thing> into <thing>` to `Pours`). The engine ships default frames for `LooksAt` (`look at`, `examine`, `x`), `Uses` (`use <thing> with/on <thing>`, `use <thing>`), `TalksTo` (`talk to`, `ask <thing> about <thing>`), and `WalksTo` (`go to`, `walk to`). A script `command <Cue>: <frame>` declaration adds a frame, tried before the defaults.
3. Nouns: an entity answers to the words of its name, split at case changes, spaces, and underscores (`ExposureSlip` answers to "exposure slip" and "slip"), plus words from script `alias <Entity>: phrase, phrase` declarations. A noun phrase matches an entity when every word of the phrase is one of the entity's words. Only entities in scope resolve: agents, hotspots, and marks in the actor's room, and entities the actor holds through `Carries` or `InInventory`.
4. One match resolves; several matches produce no cue and a "Which do you mean" question that a following bare noun answers; none produces "I don't know" for an unknown word. A sentence whose cue has no handler produces "Nothing happens" (P26-02).
5. `go to <mark>` starts a world-aware walk and also fires `WalksTo` when the script handles it (P26-02).
6. The command bar (P26-03) is separate from the REPL and enabled per host. Enter focuses it; while focused every key is text, so no engine or proof binding fires; Enter submits and Esc leaves; Up/Down walk the history; Tab completes from frame words and nouns in scope.
7. Script commands and aliases are program data: `CompiledProgram.commands` and `.aliases`, stored by `.bspk` version 10. The Larkspur Observatory verifies the phase in its transcript and window.
**Alternatives:**
- A fixed engine verb table only: rejected; proofs and games name their own cues (`Takes`, `Pours`).
- Script-only frames with no defaults: rejected; every game would redeclare looking, using, talking, and walking.
- Typing into the REPL console: rejected; the REPL evaluates engine commands for developers and must not run game commands.
- Resolving nouns against the whole World: rejected; typed commands would reach entities the player cannot see.
**Consequences:** Typed and clicked actions meet at the same cue handlers. Matching is word-subset, not fuzzy, so misspellings fail with "I don't know the word". A noun such as "key" is ambiguous whenever two keys are in scope, by design.

## D-058 State Inspector: a Drawer Tab, 128 Captured Facts, a Fixed Ego Layout, and a Next-to-Happen List (2026-11-10, status: accepted)
**Context:** Phase 27 adds a live view of world state. The `D` overlay lists 10 of the 32 facts each frame copies, as text; the `P` drawer holds save and load. The maintainer accepted the defaults below.
**Decision:**
1. The inspector is a third "State" tab of the `P` drawer (Tab cycles Save, Load, State), so the game is paused while it is read. The `D` overlay is unchanged.
2. Each frame copies up to 128 facts (was 32), adding the subject and object ids, whether the object names an entity, and a flag for facts in `World.recently_expired`.
3. Entities are nodes. A fact whose object names an entity is a directed edge labelled with its relation; value and state facts are listed under their subject. `Believes`, `Knows`, and `Rejects` edges use a belief colour. Fact colours: permanent white; green, amber, then red as the remaining ticks fall below 60 and 20; grey for just-expired.
4. The layout is fixed and deterministic: the focused entity in the centre, its neighbours on a ring in entity-id order. The default focus is the entity with the most edges (lowest id on ties). Every redraw of the same state draws the same picture.
5. P27-02 shows the open dialogue's options in source order with pruned ones and their first failed guard. Newly compiled scripts use `offer_choice_inspected` and `reject_choice` opcodes to write `DialogueBranchCount`, `DialogueBranchText`, `DialogueBranchActive`, and `DialogueBranchFailure` World facts beside the selectable set. These facts save, rewind, and branch with the dialogue. Generated and pre-P27-02 sets have no diagnostic facts and present every offered option as active.
6. The "next to happen" list shows the next six live fact expirations ordered by absolute tick, then stable fact identity. It projects only deadlines already present in the captured frame; it does not clone the World or speculatively execute reactive rules. P27-03 adds keyboard navigation (move, recentre) and relation filters. The browser simulator part of P27-03 moves to Phase 30, because the wasm runtime keeps no VM state of this kind.
**Alternatives:**
- A force-directed layout of the whole world: rejected; it is unreadable past a few dozen facts and changes between runs, so no golden can pin it.
- A separate overlay key: rejected; free letters are scarce and an inspector belongs with pause.
- Capturing every fact: rejected; the frame is copied by value twice per tick.
- Keeping rejected branches only in a VM or render cache: rejected because restoring a World snapshot would show an open dialogue without the pruning evidence that produced it.
- Predicting future reactive cascades by cloning and ticking the World: rejected for P27-02 because the inspector is read-only and an expiry deadline is the only future event the current frame can state without executing game logic.
**Consequences:** The frame grows by about 16 KB after both P27-01 and P27-02. Facts carry no type for their object, so a numeric value equal to an entity id is drawn as an edge, as the text inspector already shows it; the engine's known numeric cell, volume, and dialogue lifecycle relations are always treated as values. Worlds with more than 128 facts show the first 128 in fact-table order. The first failed guard is diagnostic text interned at compile time; later guards are not evaluated after that failure.

## D-059 State Inspector Navigation: Window-Owned Focus, a Ring Selection, Eight-Step History, and a Cycling Relation Filter (2026-11-10, status: accepted)
**Context:** D-058 point 6 leaves P27-03 to add keyboard navigation (move, recentre) and relation filters to the State tab. The maintainer accepted the defaults below.
**Decision:**
1. Navigation is window state (`inspector_focus`, `inspector_selected`, `inspector_history`, `inspector_filter` on `DisplayWindow`), never World state. It survives closing the drawer and is not saved, rewound, or branched.
2. Left and Right move a selection around the ring in ring order (clockwise from the top), wrapping. The selected node has an accent outline. Enter centres on the selected node and pushes the old centre onto a history of eight; the oldest drops off when full. Backspace pops the history. Home clears the focus and the history, returning to the default focus. A left click on a ring node recentres as Enter does.
3. F cycles the filter: all, beliefs (`Believes`, `Knows`, `Rejects`), then each relation in the frame in byte order, then all. The filter limits edges, ring neighbours, and the states list, and the default focus counts only matching edges; when nothing matches, the default falls back to the unfiltered one. The dialogue panel and the "Next to Happen" list ignore the filter, because they describe the whole paused moment. A relation that left the frame advances to the next name after it.
4. A focus the frame no longer mentions (after a rewind, a load, or an expiry) is dropped with its history, and the default focus returns. The selection is clamped to the ring each frame.
5. The filter copies its relation name into a 24-byte buffer, the width of a captured relation, because each capture overwrites the frame it came from.
**Alternatives:**
- A free text filter typed into the tab: rejected; the drawer has no text field, and the command bar owns typing (D-057).
- Selecting by number keys: rejected; digits mean slots in the Save and Load tabs, and the ring holds up to 16 nodes.
- Filtering the "Next to Happen" list too: rejected; a deadline outside the filter is still about to happen, and hiding it misstates the moment.
- Keeping navigation in World facts so it rewinds: rejected; the inspector is read-only (D-058), and a debugging view must not change a save.
**Consequences:** Neighbours beyond the ring's 16 slots stay unreachable by keys until a filter narrows the ring. The relation filter is exact and case-sensitive. The State tab footer now names the filter and the keys, which moved the `inspector/` render golden.

## D-060 MML Scores: a Std-Only Parser, Integer Ticks, Re-Read Repeats, Drum Letters, and Coexistence With Grid Patterns (2026-11-11, status: accepted)
**Context:** Phase 28 lets scripts compose music in Music Macro Language. The engine's music is a `BgmPattern`: 32 sixteenth steps, one note per step on four fixed channels, with no note lengths, volumes, or loop points, used by the proofs' 11 tracks. The maintainer chose the four defaults below (2026-11-11).
**Decision:**
1. **Command set (core plus loops).** `t` tempo (32 to 255), `o` octave (0 to 8), `>` up and `<` down an octave, `l` default length, notes `a` to `g` with `+`/`#` sharp or `-` flat, lengths 1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64 with dots, `r` rest, `&` tie, `v` volume (0 to 15), `[ ]n` repeat (n 1 to 99, default 2, four deep), `L` loop point, `@` envelope preset (0 to 7, defined by P28-02). Commands are case-sensitive (`l` length, `L` loop); o4 `c` is MIDI 60.
2. **Integer time.** 192 ticks per whole note. A length that does not divide 192, or a dot that would halve an odd tick count, is an error rather than a rounded value.
3. **"Synthesizer bytecode" is an event list.** `mml.parse` turns one track's text into a slice of `Event`s (note, rest, hit, tempo, volume, envelope) with a loop-start index and total ticks. It is data, as effects are data (D-040), not VM opcodes. The module is `src/mml.zig` and imports only `std`, so the audio thread (P28-02) and the compiler (P28-03) can both use it without importing each other.
4. **Repeats are re-read, not copied.** Each pass of `[ ]n` parses the body again, so relative commands (`>`, `<`, `l`) apply on every pass as in an MML player. The work of re-reading is bounded (262,144 characters) along with events (4,096) and depth (4), because score text comes from scripts.
5. **Percussion uses drum letters.** A track is melodic or percussion. A percussion track plays `k` kick, `s` snare, and `h` hat (the engine's three drum voices) and refuses notes and octaves; a melodic track refuses drum letters.
6. **Ties and loop points are checked.** `&` must follow a note, rest, or hit and may repeat only the same symbol. One `L` per track, outside repeats, followed by at least one tick of time, so a looping track always advances.
7. **MML coexists with grid patterns.** P28-02 adds MML scores beside `BgmPattern`; the proofs' tracks and `proofs/golden/audio.txt` stay as they are.
**Alternatives:**
- The minimal set without repeats or envelopes, or a full MCK-style set with detune, sweep, and duty macros: not chosen by the maintainer.
- Copying a repeat's events: rejected; `[c >]2` would replay one pitch where MML players climb.
- Noise-coloured percussion notes: not chosen; it cannot reproduce the engine's kick and snare.
- Converting the proofs' grid tracks to MML: not chosen; it would change every music golden for no new capability.
- Parsing inside `src/compiler/`: rejected; the audio thread would then import compiler code.
**Consequences:** Tempo is a per-track event; how four tracks with different tempo events stay in step is decided in P28-02. `@` presets parse but mean nothing until P28-02 defines them. Errors carry offset, line, and column within the score text; P28-03 maps them to the script position.

## D-061 MML Playback: One Integer Clock, a Whole-Score Loop, an Envelope Table, and the Grid Voices (2026-11-11, status: accepted)
**Context:** P28-02 plays the event lists P28-01 parses (D-060) as four simultaneous parts. D-060 left open how parts share tempo and what `@0` to `@7` mean; the roadmap asks for cross-channel synchronization and loop points. The maintainer chose the defaults below (2026-11-11).
**Decision:**
1. **A score is four borrowed parts.** `MmlScore` holds lead, bass, chords, and percussion `MmlTrack`s (event slices with a loop start). `Music` gains an optional `score`; when set it plays and `pattern` is ignored, and `pattern` now defaults to `SILENT_PATTERN`. Grid tracks are unchanged.
2. **One integer clock.** A `t` in any part sets the tempo for every part from that tick. The clock gains `tempo * 48` per sample and spends `sample_rate * 60` per tick, so ticks never drift and no floating point enters MML timing. Each tick, parts count down and read events in fixed order (lead, bass, chords, percussion); within one tick the last tempo read wins.
3. **Whole-score loop.** A part that reaches its end waits. When every part has ended, each part with an `L` restarts there, all on the same tick, and parts without `L` stay silent; with no `L` anywhere the music ends. Parts of unequal length therefore re-align on every pass.
4. **Envelopes are a fixed table.** `@0` is the grid voice's own sound (fixed peak and decay, no note-off). `@1` organ, `@2` pluck, `@3` long fade, `@4` swell, `@5` staccato, `@6` tremolo (about 6 Hz, half to full level), and `@7` soft pad have an attack, decay, sustain level, and release, and release when the note's written length ends. Envelopes do not apply to drums.
5. **Parts play the grid voices.** Lead, bass, and chords drive the existing pulse-with-vibrato, triangle, and pad voices; the MML envelope overwrites the voice's level every sample. Percussion triggers the existing kick, snare, and hat. `v` scales a note's peak or a hit's level by n/15.
6. **The audio thread trusts nothing.** Tempo, volume, and envelope values are clamped at playback; a drum hit on a melodic part or a note on percussion keeps its time but makes no sound; a loop restart happens at most once per tick, so a hand-built score with a zero-length loop cannot stall the thread.
**Alternatives:**
- Per-part tempo: not chosen; parts drift apart unless tempos match.
- Independent per-part loops, as classic MML players do: not chosen; unequal loop lengths slide out of phase.
- Eight decay speeds with no note-off: not chosen; written lengths would only set when the next note starts.
- New MML-only voices: rejected for now; the grid voices give scores the engine's existing timbre and keep one set of synthesis code.
**Consequences:** Every grid golden line is unchanged; `proofs/golden/audio.txt` gains `mml/demo`. A part rests at its end until the longest part finishes, so an author who wants a short phrase to repeat under a long one writes the repeat (`[ ]n`) rather than relying on independent loops. Scripts still cannot declare scores; P28-03 adds `score` and scene triggering.

## D-062 Script Scores: Block Declarations, Scene Defaults and Overrides as World Facts, and Name-Matched Tracks (2026-11-11, status: accepted)
**Context:** P28-03 lets scripts declare MML scores (D-060) and choose when they play (D-061 plays them). Scene music has come from a host `track_for_scene` callback, which cannot see compiled script data. The maintainer chose the defaults below (2026-11-11).
**Decision:**
1. **Syntax.** `score <Name>:` opens a block of `lead`, `bass`, `chords`, and `drums` lines, each with one MML string, and `scene <Scene>` lines (up to 16). The roadmap's one-line `score <Name>: "<MML>"` is a lead-only score with no scenes. Each part is parsed at compile time; an MML error reports the script line and the column inside the string. A score name is declared once, and a scene has at most one score.
2. **Choosing music is World state.** `scene` lines seed `SceneScore(Scene, Score)` facts before the script's own top-level statements. `play score <Name>` sets the `PlayingScore` property of the `Music` entity, and `stop score` removes it; both work in routines, cue handlers, `when` rules, and at top level, and `play score` must name a declared score. Saves, rewinds, and temporal branches therefore restore the music with the World.
3. **The override persists.** While `PlayingScore` is set it plays in every scene; scene defaults return only after `stop score`. A scene with no score and no override is silent.
4. **The frame names the score.** `DisplayBridge.capture_frame` resolves the override, else the current scene's `SceneScore`, into `RenderFrame.current_score` from World facts alone (`display.current_score_entity`). `AudioBridge.process_scene_and_cues` takes the scene and score names; `track_for` plays the soundtrack track whose `Music.name` equals the score, else the soundtrack's scene rule.
5. **Hosts register script music.** `host.ScriptSoundtrack` parses a program's scores into one `Music` per score, named after it, in declaration order. `bespoke run` registers it with its window, and its headless mode prints each change of music.
6. **Packages store text.** `.bspk` version 11 appends each score's name, scenes, and four MML strings; loading re-parses every part and rejects the package if one fails, because a package is untrusted. Versions 1 to 10 load with no scores.
**Alternatives:**
- One-line scores split by `|`: not chosen; long scores become unreadable lines.
- Statements only, without scene binding: not chosen; every scene change would need its own `play score`.
- Clearing the override on a scene transition: not chosen; chase music would stop at every door.
- Keeping the selection in the VM or the host: rejected; a rewind would restore the World without its music.
- A new opcode for `play score`: rejected; `remember` and `forget` of an engine relation already express it.
**Consequences:** `score` and `play` are now keywords. `Music`, `PlayingScore`, and `SceneScore` are engine names in a script's World; a script entity named `Music` shares that entity. Proof soundtracks are unchanged: proofs declare no scores, so `current_score` is empty and their scene rule still chooses. The stock runner, which played nothing since D-040, now plays a script's own scores.

## D-063 Project Scaffolding: Embedded Templates, a Relative Path Dependency, and a Script-Only Starter (2026-11-11, status: accepted)
**Context:** P29-01 adds `bespoke init <name>` so an author can start a standalone game on the engine. The maintainer chose a local path dependency over a git URL or a vendored copy, and script declarations over a separate actor data file (2026-11-11).
**Decision:**
1. **Templates are embedded.** `src/scaffold/*.tmpl` are compiled into the `bespoke` binary with `@embedFile`; `src/scaffold.zig` fills in the project name and the engine path and writes seven files: `build.zig`, `build.zig.zon`, `src/main.zig`, `src/game_test.zig`, `scripts/main.bespoke`, `README.md`, `.gitignore`.
2. **The engine is a relative path dependency.** The binary records its own checkout (`build_options.engine_root`, set by the engine's `build.zig`); `--engine <dir>` overrides it. `build.zig.zon` stores the engine's path relative to the new project, because Zig 0.13 rejects absolute `.path` dependencies. The project uses the engine's exported `bespoke` module (with SDL2) through `b.dependency("bespoke", ...)`.
3. **Names are lowercase identifiers.** A project name is a lowercase letter followed by lowercase letters, digits, or underscores, at most 32 characters, because it becomes a directory, a package name, and an executable name. `init` refuses a name whose path already exists and creates files exclusively, so it never overwrites work.
4. **The starter is one script and a thin host.** `scripts/main.bespoke` configures its actors the engine's own way: a scene with cast, props, and marks; routines; an agenda; an interception cue with a dialogue choice; a scene score and a `when` rule that plays another. `src/main.zig` calls `bespoke.run_file` (window, or `--headless --ticks N`), reading the script at run time so edits need no rebuild. `src/game_test.zig` compiles the script and checks the interception and music by World facts; `zig build test` and `zig build run` run from the project root.
**Alternatives:**
- A git URL and hash dependency: not chosen now; it needs a tagged release. P29-03 can switch the template.
- Copying the engine's `src/` into each project: not chosen; copies drift from the engine.
- An `actors.zon` read by the host: not chosen; it would add a second configuration format beside the DSL.
- Templates as a directory read at run time: rejected; the binary would need to find its own install tree.
**Consequences:** A generated project builds only beside the engine checkout it names; moving either means editing `.path`. On Windows, an engine on another drive than the project cannot be expressed and `init` refuses. The starter's whole-line comments avoid language keywords until the comment-lexing fix lands. The starter's names (Hero, Keeper, Lighthouse) live in `src/` as template text, not as engine code paths.

## D-064 Authoring Guide: Tested Examples and an Interactive Stock Runner (2026-11-12, status: accepted)
**Context:** P29-02 asks for an authoring guide that walks through scenes, dialogues, and reactive puzzles. The stock runner (`bespoke run`, and every project `bespoke init` writes) drew dialogue choices but ignored them, had no command bar, and printed no speech headless, so a reader could not play the guide's dialogue or puzzle. The maintainer chose to wire the runner and to compile every guide example in the test suite (2026-11-12).
**Decision:**
1. **The guide lives in `docs/AUTHORING.md`.** It teaches in order: start a project, the model, three walkthroughs (a scene, a dialogue, a reactive puzzle), more mechanics, testing, the host API, and known limits. `script_spec.md` stays the syntax reference. The manual gains an "Authoring Games" section that points to it.
2. **Every `bespoke` block is a whole script and is compiled.** `src/authoring_guide_test.zig`, run with the CLI's tests, reads the guide from the engine checkout the build records and compiles each block in a fresh World. Fragments are fenced as `text`. The walkthroughs carry `<!-- example: scene|dialogue|puzzle -->` markers and are played headless; the test checks the facts, speech, scene, and music the guide describes. `build.zig` declares the guide as an input of the test run, so editing it re-runs the tests.
3. **The window acts for one player, chosen from the script.** The player is the actor of the first top-level routine in source order (the routine with the lowest entry address, which packages keep); path initializers are skipped. Before, the runner took whichever routine a hash map listed first. With no routine the player is `Player`, as before.
4. **The window answers dialogue and typed commands.** A click or number key on an offered choice calls `VM.choose`, and a scripted choice ticks at once so its body runs. The command bar is enabled; a submitted line runs through `host.run_command` for the player, shows any reply as a banner, and ticks when a cue fired. Completion words refresh after every tick, and each tick's `say` lines show as the window's banner, because the window draws script speech only from a banner.
5. **Headless runs print the story.** After each tick the runner prints `say` lines, a change of scene, and each newly offered set of choices, with the tick. Headless runs cannot answer choices.
**Alternatives:**
- Documentation only, driving dialogue from tests: not chosen; the program every project starts from would contradict the guide.
- Scenario files quoted by the guide and checked for equality: not chosen; reference snippets would stay unchecked.
- A `player` declaration in the language: not chosen now; source order already gives a stable rule without a new keyword.
- Clicking a person to talk: not chosen in this change; typing `talk to <name>` covers it.
- Placing cast members that have no routine: out of scope; recorded under Claims vs. code.
**Consequences:** `bespoke run` output gains `Scene:`, speech, and `Choices for` lines; tools that parse it must allow them. A script whose first routine belongs to a non-player character now gives that character the player's clicks; reorder the routines to choose. The engine tests read a file outside `src/`, so they run from a checkout, as they already do.

## D-065 Cast Members Start on Their Scene's First Mark, Placed by the Host Kit (2026-11-12, status: accepted)
**Context:** A `scene` block's `cast` names were only interned. Hosts registered an actor on a mark only when one of its routines started, and the stock runner used the script's first mark whatever the actor's scene. A cast member with no routine could not be seen, named in a typed command, or talked to (found writing the P29-02 dialogue walkthrough; recorded under Claims vs. code). Registering cast members inside compilation changed 103 render goldens across 12 of the 13 proofs, because proofs place their own actors and the extra early registrations changed what they draw. The maintainer chose placement through the host kit (2026-11-12).
**Decision:**
1. **Compilation records, it does not place.** For each scene with marks, every cast member not already recorded gets a `CastPlace { actor, mark }` with that scene's first mark, in source order; a scene without marks records nothing. `CompiledProgram.cast` holds them. Compilation without a SpatialSystem records none.
2. **`host.place_cast(spatial, compiled)` places them.** It registers each recorded actor at its mark with `host.CAST_SPEED` unless the SpatialSystem already has that actor, so a host's own placement wins and repeated calls change nothing. Hosts call it after placing actors by hand and before starting routines.
3. **The stock hosts call it.** `bespoke run` calls it before spawning routines; routine actors no scene lists still start on the script's first mark. The `bespoke init` test template and the authoring guide test call it too. Proofs do not, so their goldens are unchanged.
4. **Packages carry the table.** `.bspk` version 12 appends a count and, per place, the actor's entity id and the waypoint id. Loading checks both references and caps the count at 4,096. Versions 1 to 11 load with no places, so a host places nobody for them.
**Alternatives:**
- Register cast members during compilation: not chosen; every host would get it, but 103 proof render goldens change and proofs lose control of their opening layout.
- Place cast in `host.initialize_subsystems`: not chosen; that function takes no SpatialSystem and runs on every tick, and proofs call it.
- A per-actor `at <Mark>` clause in `cast:` lines: deferred; first-mark placement needs no syntax, and a later clause can extend `CastPlace`.
**Consequences:** In the stock runner a routine actor that is in a cast now starts in its own scene rather than on the script's first mark; scripts whose routines walk between scenes may start differently. Old packages run as before. The guide's dialogue walkthrough drops its workaround routine and serves as the end-to-end check.

## D-066 Reference Starter Template: Bundled Packages, Browser Script Decks, and CI Across Platforms (2026-11-12, status: accepted)
**Context:** P29-03 asks for a reference starter template with verified tests, asset bundling, and reproducible builds on Linux, Windows, macOS, and WebAssembly. The browser runtime ran only decks built in Zig and could not run a script. Only Linux is available to verify on, and SDL2 for the other platforms is not installed. The maintainer chose (2026-11-12): script decks in wasm, a GitHub Actions workflow in the template, an embedded compiled package for releases, and `bespoke init` output as the template, checked by a separate build step.
**Decision:**
1. **The template is what `bespoke init` writes.** It gains `src/web.zig`, `web/index.html`, `web/smoke.js`, and `.github/workflows/build.yml`. `zig build test-template` in the engine generates a project into `.zig-cache/tmp/template_check` and runs its `zig build test`, `zig build -Dbundle -Doptimize=ReleaseSafe`, and `zig build web`; `zig build test` does not run it, because it takes about a minute.
2. **Releases embed a compiled package.** With `-Dbundle`, the game's build runs the engine's own `bespoke compile` (built for the build machine) on `scripts/main.bespoke` and embeds the `.bspk`; `src/main.zig` then calls `bespoke.run_bytes`. Without it, `zig build run` reads the script live. A script error fails the build. The option is `-Dbundle`, not `-Drelease`, because `-Drelease` belongs to Zig's own optimize option.
3. **The browser runs scripts.** `wasm.script_deck(title, program)` makes a deck from an embedded package or source; `WasmRuntime.load_program` loads it, starts it with `host.start_script`, and ticks through `host.tick`. Speech and offered choices show in the banner, and while a dialogue is open the number keys answer it instead of switching decks. The engine's `bespoke.wasm` gains a script deck so its own build and smoke check exercise this. Typed commands are not bridged to the browser.
4. **One start-up sequence.** `host.start_script` runs top-level statements (bounded, as `run_initial_statements` was), places the cast, starts every routine, and returns the player; `host.player_actor` moves from the runner. The runner, the guide test, and the wasm runtime use it.
5. **The exported module builds for wasm.** For a wasm target the `bespoke` module links neither libc nor SDL2, so a game can depend on the engine for its browser build.
6. **CI lives in the template.** The workflow builds and tests on `ubuntu-latest`, `macos-latest`, and `windows-latest` (SDL2 from apt, Homebrew, and MSYS2 with `-Dtarget=x86_64-windows-gnu`), runs the bundled release headless, and builds and smoke-tests the browser version. It fetches the engine from `aedmark/bespoke-engine` at `BESPOKE_ENGINE_REF` (default `main`) and rewrites `.path` to it.
7. **The static library is `bespoke-core`.** `Dependency.artifact` refuses a name two installed artifacts share, and the game's build fetches the `bespoke` CLI by name.
**Alternatives:**
- A dist folder that copies `scripts/`: not chosen; the executable would still depend on files beside it.
- Deferring wasm: not chosen; the roadmap item names WebAssembly.
- Cross-compiling Windows and macOS from Linux: not possible without their SDL2 libraries.
- A committed example project: not chosen; it would drift from the templates.
**Consequences:** Windows and macOS builds are verified only when a generated project is pushed to GitHub; the Windows SDL2 setup is the least certain. The browser runtime's 2 MiB heap bounds how large a game can be in the browser. The runner's top-level statements now stop after 64 ticks, as every other host's did. `zig-out/lib/libbespoke.a` is now `libbespoke-core.a`.

## D-067 Showcase Deployment: Static Export, Neocities Upload by Hash, and a Small Wasm Module (2026-11-12, status: accepted; upload superseded by D-074)
**Context:** P30-02 asks for a Neocities deployment pipeline that optimizes the wasm asset size, adds metadata, and caches the site offline. The showcase page embedded a 1.28 MB `bespoke-proofs.wasm` as base64 (a 1.78 MB page), of which 1.18 MB was zero bytes: the browser runtime's state was a global `?WasmRuntime = null`, which the compiler emitted as initialised data. Neocities allows no custom response headers. The maintainer chose (2026-11-12): API upload with a dry run by default, the module kept embedded, the public URL passed as an option, and a service worker.
**Decision:**
1. **The runtime's state is uninitialised.** `export_runtime` holds the runtime as `undefined` with a ready flag, so the module carries no zero data: `bespoke-proofs.wasm` is 97 KB and `bespoke.wasm` 324 KB, and the page 200 KB. `tools/wasm_smoke.js` fails a module over 1 MiB.
2. **The page stays one file.** The module stays embedded as base64 in `site/index.html`, which still opens from `file://` and needs no `.wasm` file type on the host.
3. **`tools/deploy_site.py export` writes `dist/site/`.** It refuses a stale page (the same rendering `build_site.py --check` compares), then adds sharing metadata built from the page's own title and description (OpenGraph, Twitter, theme colour; canonical and `og:url` only with `--site-url https://...`), and a service-worker registration guarded to http(s). The repository page is not changed. `dist/` is ignored by git.
4. **`sw.js` caches by content.** Its cache name carries a hash of the exported page, so each deploy installs a new cache and deletes the old ones. Fetches go to the network first and fall back to the cache, so online visitors always get the deployed page.
5. **`upload` sends only changed files.** It reads `NEOCITIES_API_KEY` from the environment, lists the site through the API, compares SHA-1 hashes, and uploads files that differ in one request. Without `--yes` it only lists them. It never deletes remote files and never prints the key. `NEOCITIES_API_URL` points it at a test server.
**Alternatives:**
- A separate `.wasm` file with streaming compilation: not chosen; after the fix the gain is small, and Neocities' free plan restricts file types.
- Stripping or `wasm-opt`: not needed; the zero data was the whole problem, and neither tool is a dependency.
- Export only, with manual upload: not chosen; re-uploading unchanged files by hand invites mistakes.
- Cache-first service worker: rejected; visitors would see the previous deploy until a second visit.
**Consequences:** The service worker has not run in a real browser: the desktop app's browser pane refuses service workers, so it was checked by syntax only. Uploads are tested against a local mock of the API, not Neocities. Removing a file from the site is still done in the Neocities dashboard.

## D-068 Showcase Gallery, Script Viewer, and Architecture Diagrams (2026-11-12, status: accepted)
**Context:** P30-03 asks for an interactive scenario gallery, architecture diagram embeds, and a live script source viewer beside each playable slice. The page's five scenario cards carried hand-written script snippets that had drifted from the proofs (one named a scene the proof does not have), and covered ten of thirteen proofs. The seven browser decks rebuild their stages in Zig (`proofs/wasm_deck.zig`) and do not run the proofs' scripts. The maintainer chose (2026-11-12): show each proof's real script, labelled as the desktop proof's source; a generated gallery whose viewer follows the active deck; and hand-drawn inline SVG diagrams.
**Decision:**
1. **The gallery is generated.** `tools/site_gallery.json` lists all thirteen proofs with a title, tag, blurb, script source, playground deck (or none), and `bespoke-proofs` flag. `tools/build_site.py` renders a second generated region (`SITE_GALLERY_START`/`END`) with one card per proof: Play here switches the viewport to its deck, desktop-only proofs show their `zig build run-proof` command, and View script opens the viewer.
2. **Scripts come from their sources.** A source is a `.bespoke` file or `file.zig#CONSTANT`, a Zig multiline string read line by line. The Tavern Heist proof builds its stage in Zig, so its card shows `scenarios/tavern_heist.bespoke` and says so. Scripts are highlighted at build time with the keyword list read from `src/compiler/lexer.zig`, escaped, and embedded as JSON whose `</` is escaped so it cannot close its element.
3. **The viewer follows the deck.** A panel under the viewport shows the active deck's script with line numbers and a note that the browser deck is a Zig reconstruction. It fills before the module loads, so it works even if WebAssembly fails.
4. **Diagrams are inline SVG.** A How It Works section draws Engine-as-Spine, the cue-to-story-beat cycle, and the script-to-platform build, styled by CSS classes on the page's theme variables. No external files; the page still opens from `file://`.
5. **Staleness is one check.** `build_site.py --check` and `deploy_site.py export` compare the whole page, gallery included, with a fresh render, so a changed proof script or gallery entry makes the page stale.
**Alternatives:**
- Converting the browser decks to script decks (D-066) so what plays is what is shown: not chosen now; proof catalysts and after-tick rules would move into scripts and every wasm golden would change. A candidate roadmap item.
- Keeping static cards with real code: not chosen; nothing would connect the code to the viewport.
- Reusing manual figures: the manual has no diagrams of these flows.
**Consequences:** The page grew from 200 KB to 360 KB with thirteen scripts. Blurbs are prose in the JSON and are checked only for presence; the scripts, decks, and flags are checked by tests.

## D-069 Browser Decks Run the Proofs' Scripts (2026-11-12, status: accepted)
**Context:** P30-05 (from D-068) asks that the showcase play the script its viewer shows. The seven browser decks were hand-built Zig stages whose `[S]` catalyst wrote the solved facts directly, and the Living Village faked its society with a Zig rule. Running the real scripts showed four gaps: proof scripts do not name the player, the browser's verbs fired nothing, multi-scene scripts drew every scene's marks on top of each other and wide scenes ran off the canvas, and the village's society needs a host to start it. The maintainer chose (2026-11-12): verbs fire cues and `[S]` plays the desktop proof's solution; a per-deck player option; draw the current scene fitted to the stage; and the real society.
**Decision:**
1. **Each proof deck is a script deck.** `wasm.script_deck_with(title, script, options)` compiles the proof's own script in the browser and starts it with `host.start_script`. Options name the `player`, an `intro` banner, a `setup` hook for host work the desktop proof does in Zig (the opening scene, the goat at its tether, DOTT's starting inventory), the `catalyst`, and an `after_tick` rule. The Tavern Heist deck runs `scenarios/tavern_heist.bespoke`, passed in as an anonymous import because the proof builds its stage in Zig.
2. **Verbs fire cues.** In a script deck, LOOK, TALK, TAKE, and USE on a person or prop fire `LooksAt`, `TalksTo`, `Takes`, or `Uses` for the player and run the tick that answers. Without a handler the banner says "Nothing happens.", and LOOK at a prop falls back to its examine text. WALK still walks.
3. **`[S]` plays the desktop proof's solution.** Each deck lists beats in `proofs/wasm_deck.zig`; a beat is a short list of actions: a cue, ticks (answering an open dialogue with its first option, as the proofs do), a walk, a scene change, a fact the desktop host sets directly, an item transfer, or a container pour. Progress is the `SolveBeat` property of a `SolveKey` entity, so a rewind rewinds it. The grog sprint is one beat, because the cups fail about nine ticks after the scene opens.
4. **The Living Village runs the engine society.** Its setup starts `society.Society` from the script's declaration, its after-tick rule steps it, and `[S]` is the desktop proof's desperation catalyst. The fake Zig rule is gone.
5. **The stage shows one room, fitted.** The room is the VM's current scene, else the first mark's room. Its marks and props set the bounds; the scale is at most the old fixed 10 by 7 pixels per unit. Drawing and click tests use the same `Projection`, and people, props, and marks of other rooms are hidden.
6. **The VM is re-bound at every entry point.** `WasmRuntime.init` returns by value, so `bind` points the VM at the runtime's World, SpatialSystem, and chunk before a tick, a catalyst, a verb, or a dialogue answer; firing a cue before re-binding read a stale World.
7. **The page sends number keys to an open dialogue.** `wasm_dialogue_open` is exported; the site sends 1 to 9 to the runtime while a dialogue is open, and switches decks otherwise.
**Alternatives:**
- A `player` line in the language: deferred; a deck option needed no language change.
- Keeping each deck's hand-made layout over the script: rejected; the stage would not match the script's scenes.
- Running the whole solution on one key press: not chosen; a beat per press lets a visitor watch each step.
**Consequences:** `bespoke-proofs.wasm` now carries the compiler and grew from 97 KB to 383 KB, under the 1 MiB guard; the page is about 722 KB. Every wasm golden line changed; the desktop transcript and render goldens did not. DOTT's solution is mostly host facts, as on desktop, so its browser beats set those facts rather than fire cues. Typed commands are still desktop only. The engine's own Zig deck also renders through the fitted projection.

## D-070 Browser State Inspector: the Desktop Inspector Drawn in the Canvas (2026-11-12, status: accepted)
**Context:** P30-04 (moved from P27-03 by D-058) waited for the browser runtime to hold fact and dialogue state, which D-069 provided. The desktop State tab (D-058, D-059) is drawn by the SDL renderer, but its fact capture (`display.zig`) and its layout, filter, and expiry logic (`display/state_graph.zig`) use no SDL. The maintainer chose (2026-11-12) to draw the inspector in the wasm canvas and to pause while it is open.
**Decision:**
1. **One capture, one layout.** `display.capture_debug_facts` is the desktop frame's 128-fact capture, made a public function; the desktop frame and the browser both call it. `src/wasm_inspector.zig` lays out the graph with `state_graph.build`, cycles filters with `next_filter`, and lists deadlines with `next_expiring`, so both inspectors draw the same state the same way.
2. **The overlay replaces the stage.** `I` toggles it. It draws the focus in the centre with neighbours on a ring and labelled edges (labels of several facts between the same pair stack), the focus's values and states, the open dialogue's branches with pruned ones in red, and the next six expirations, in the desktop's colours. The HUD, timeline, banner, and verb bar stay visible.
3. **It pauses.** Opening pauses the clock and remembers the run state; closing restores it. While open, clock, deck, and solve keys wait; R and the timeline still rewind and scrub, and a focus the World no longer mentions is dropped with its history.
4. **The desktop's keys, as DOM key codes.** The runtime's key event is one byte, so the page sends the DOM `keyCode` for Left (37), Right (39), Enter (13), Backspace (8), and Home (36); F filters. A click on a ring node recentres. Navigation lives in the runtime, not the World, and is never saved.
5. **Pages forward the keys.** The showcase and the `bespoke init` page send `I` and the named keys; `wasm_inspector_open` lets the showcase stop deck and clock keys while it is open and label the state INSPECTING.
**Alternatives:**
- An HTML panel fed by a JSON export: not chosen; only the showcase would have it, and the layout logic would be redone in JavaScript.
- A live inspector that keeps ticking: not chosen; the desktop pauses, and a moving graph is hard to read.
**Consequences:** Every wasm build, including generated projects' web builds, has the inspector. The canvas is 640 by 360, so long names are clipped. The wasm golden records the overlay for every deck. The proofs module grew to 412 KB.

## D-071 The Last Four Browser Decks: Generated Choices, Notes, Engine Audio, and Tangent Worlds (2026-11-13, status: accepted)
**Context:** P30-01 left four proofs desktop-only and the browser silent. Each needed something the browser runtime lacked: Insult Sword Fighting and Algiers resolve host-generated dialogue choices; the Bell Tower is played with notes on a distaff; the Middlesex Anomaly runs on the `TemporalHypervisor`. All four scripts compile and run in the browser in under 300 KB. The engine synthesizer (`AudioBridge.render_samples`) uses no SDL. The maintainer chose (2026-11-12): the hypervisor in the runtime, the engine synthesizer streamed to Web Audio, and letter keys C to B for notes.
**Decision:**
1. **Generated choices go to the deck.** `WasmRuntime.answer` answers the open dialogue; a scripted choice resumes its fiber, a host-generated one passes its action id to the deck's `on_choice`. Sword Fighting runs the engine `Duel` configured by its script; Algiers reuses its proof's own `configure` and path table.
2. **Verbs name their cues per deck.** `VerbCues` replaces the fixed verb-to-cue map, so a script that answers `Talk` or `PicksUp` names them.
3. **Notes play on a distaff.** In a deck whose script declares drafts, C D E F G A B add notes up to the player's `DistaffReach`, and the fourth weaves the phrase on the last person or prop acted on, then ticks twice so in-script weaves dispatch, as on desktop. `[S]` is the only solve key; F and G no longer trigger it. A distaff line on the stage shows the notes, the reach, and the target.
4. **The engine synthesizer plays in the browser.** The runtime owns an `AudioBridge`, gives it the script's scores (or a deck's `soundtrack`, such as a proof's desktop music), tells it the scene and score after every tick, and sends clicks, dialogue blips, notes, and weave results. `wasm_audio_render` fills a stereo buffer at `wasm_audio_sample_rate` (44.1 kHz); the showcase and `bespoke init` pages play it through a Web Audio ScriptProcessor once the visitor turns sound on. A script deck that never names its opening scene opens in its first mark's room, so music has a scene.
5. **A deck can own a temporal hypervisor.** `attach_hypervisor` creates it over the primary world. While a branch is live the VM, story, dialogue, inspector, distaff, and audio follow the branch (`active_world`); the deck's after-tick rule steps the hypervisor, as the desktop host does. Snapshots carry the branch world, countdown, and collapse state, and a rewind restores them in place, re-creating a branch a collapse had dropped.
6. **One clock.** The runtime's clock is the active world's tick; when a branch collapses, the primary world takes up the branch's tick so the timeline never runs backwards.
7. **A capped general allocator.** The browser heap is `std.heap.wasm_allocator` behind `CappedAllocator` (16 MiB). The fixed 2 MiB bump allocator never reused freed memory, so each branch re-created by a rewind would have leaked 256 KiB; the cap keeps memory bounded.
**Alternatives:**
- Splitting the Middlesex deck into its own item: not chosen.
- Page-only beeps instead of the engine synthesizer: not chosen; scores and effects would differ from desktop.
- On-screen note buttons: not chosen; letters match the desktop distaff keys.
- A larger fixed buffer instead of a reusing allocator: rejected; a repeated rewind across a collapse would still exhaust it.
**Consequences:** `bespoke-proofs.wasm` is 475 KB. Typed commands remain desktop-only, as do The Castle Fire Escape and The Larkspur Observatory. Audio has not been heard by a person; the tests measure non-silent samples. The page's ScriptProcessor is a deprecated API that browsers still ship; an AudioWorklet would need a second file or a Blob URL.

## D-072 Cue `where` Guards Bind the Handler's Parameters and Fall Through When They Fail (2026-11-13, status: accepted)
**Context:** Since the first parser, `on cue X(...) where ...:` compiled, and the handler ran whether or not the guard held, with no warning (Claims vs. code since 2026-11-08). `script_spec.md` opens with this form. Q-006 asked whether to reject, warn, or implement; the maintainer chose to implement.
**Decision:**
1. Codegen compiles a guard into join clauses (`CueGuard`) over the existing multi-clause matcher. The handler's variable parameters take the first variable slots in parameter order; a variable that appears only in the guard (`loot`) is an existential join variable. A pattern has one argument (a state) or two (a fact); eight variables in all. Anything else is a compile error.
2. `CompiledProgram.select_cue_handler` walks the same signature forms as before, most specific first. A handler whose guard fails is skipped and the search continues with the next form, so an unguarded `on cue Steal(thief, victim):` serves as the default. When every candidate declines, the cue runs nothing and records no emission, as an unmatched cue does (D-037). A form matched with two targets swapped binds the parameters in the order the handler declares them.
3. `VM.fire_cue` evaluates the guard at the cue, before spawning, so a save between the cue and the handler's first tick cannot change the outcome.
4. `.bspk` version 13 carries guards; versions 1 to 12 load with none, which is exactly how they behaved. The loader checks that each guard names a cue handler entry, slot bytes, and clause counts, and now rejects pattern variable indexes of 8 or more in reactive rules too (before, an index over 255 would panic when narrowed).
**Alternatives:**
- Reject or warn on the guard: rejected by the maintainer in favour of implementing it.
- Evaluate the guard as bytecode at the start of the handler fiber: rejected because the fiber has no access to the cue's arguments, and a save before the first tick would re-decide the guard against a different world.
- Allow several handlers with one signature, told apart by guards: deferred; a signature still maps to one handler, and the fall-through goes to less specific signatures.
**Consequences:** Guards behave as `script_spec.md` describes. Handler bodies still read lowercase parameters as entity names (Claims vs. code). `find_cue_handler` stays as the name-only lookup and ignores guards.

## D-073 Time-Branch Helpers Do What Their Names Say; the Proof's Relation Name Leaves the Engine (2026-11-13, status: accepted)
**Context:** Q-004: `validate_novikov_consistency` discarded its `candidate_action`; `is_teleologically_justified` recursed without a bound, so a cycle in the declared dependencies never returned; `check_loop_closure` looked up `VortexReady`, the Middlesex Anomaly's name, in engine code (against D-031 and D-044); and `CausalDecayTracker` returned an `f32`. The maintainer chose to implement them.
**Decision:**
1. `hypervisor.leads_to` follows registered prerequisite-to-goal edges with a search bounded by the edge count; `is_teleologically_justified` uses it.
2. Novikov self-consistency moves to `src/hypervisor.zig` and takes the declared consequences: a candidate action is inconsistent when the actor holds the paradox fact, when the action is the paradox, or when the consequences lead from the action to the paradox. `TemporalHypervisor.is_novikov_consistent` applies the hypervisor's own dependencies in the active world. `bespoke.validate_novikov_consistency` keeps its export name with a new `consequences` parameter.
3. Loop closure reads `ConvergenceReady` or `LoopClosed` only.
4. `CausalDecayTracker.existence_permille` returns integer per mille; `is_erased` is decided from ticks so rounding cannot erase early.
**Alternatives:**
- Keep the functions as documented stubs, or remove them: rejected by the maintainer.
- A paradox table keyed by action: rejected because the cause-to-effect edges the hypervisor already holds express "this action brings that about" with no new data.
**Consequences:** The Middlesex Anomaly's transcript and goldens are unchanged (its paradox is not reachable from its candidate action). The proof's art still reads `VortexReady` for its status; P35-07 renames the proof's vocabulary.

## D-074 The Showcase Is Exported by Tool and Uploaded by Hand (2026-11-13, status: accepted)
**Context:** D-067 added `tools/deploy_site.py upload`, which read a Neocities API key from the environment and uploaded changed files by hash. The maintainer did not ask for an upload tool and uploads the site by hand (Q-007, answered 2026-11-13).
**Decision:** Keep `export` (sharing metadata, the service worker, the stale-page refusal). Remove `upload`, the Neocities API client, its mock-API tests, and the API key from the security model. A test asserts the tool has no upload command.
**Alternatives:**
- Remove the whole tool: rejected by the maintainer; the export still prepares the page for any static host.
- Keep upload as an option: rejected; it put a credential path in the repository that nobody uses.
**Consequences:** Publishing is a manual step outside the repository. The release hand-test checks the live site after the maintainer's upload. The page links the manual at `docs/manual.html`, the path the maintainer uploads it to (Q-007); the export does not copy the manual, so it is uploaded separately.

## D-075 Third-Party Name Lint: Counted Terms, Digested Lines, a Shrink-Only Baseline (2026-11-13, status: accepted)
**Context:** Phase 35 (Q-005) rewrites the proofs that borrow from commercial games and a film. Without a count, a rename can miss a file, and a later change can bring a name back.
**Decision:**
1. `tools/third_party_terms.json` lists names per source; `tools/check_third_party.py` counts them in `src/`, `proofs/` (goldens included), `scenarios/`, `scheme/`, the site, the gallery data, `README.md`, and `docs/state.html`, and compares with `tools/third_party_baseline.json`, which only shrinks (the separation lint's pattern, D-031).
2. Names match case-sensitively as whole words, also as CamelCase parts and identifier parts (`BillyGoat`, `darko_puzzle`).
3. Quoted lines are stored as SHA-256 digests of their lowercased, whitespace-collapsed text, so the term list does not copy the text it exists to remove. Matching strips HTML tags and JSON escapes first, so the site's highlighted script viewer counts.
4. History is not scanned: DECISIONS, CHANGELOG, the archive, and finished roadmap items record what was true. `docs/manual.html` is built from `scheme/` and is not counted twice. Naming an engine as an inspiration (SCUMM, SCI) is attribution and is not listed.
**Alternatives:**
- Fold into `check_separation.py`: rejected; that lint asks whether engine code names a proof, which is a different question with a different scope.
- Store quoted lines as text: rejected; it would add another copy of the material.
**Consequences:** `check_docs.py` fails if a listed term rises in any file. Each P35 item ends by lowering the baseline. The list holds what a review found; a term nobody listed is not counted.

## D-076 A Duel Rotates Through Several Fallback Lines, Picked by a Fumble Count (2026-11-13, status: accepted)
**Context:** P35-02's approved duel gives the player three lines to stammer when they know no comeback. `duel.Config` held one optional fallback line, and `.bspk` stored it as a 0 or 1 flag. The maintainer chose rotation: one line per fumbled round, in order.
**Decision:**
1. A duel declares any number of `fallback "..."` lines, up to `duel.MAX_FALLBACKS` (8); `Config.fallbacks` is the list.
2. `Duel.replies` offers `fallbacks[fumbles % len]`, where `fumbles` is the fighter's `DuelFumbles` property. `resolve_round` raises it by one when the reply is the fallback (`.none`). The rotation is a fact, so it saves, rewinds, and replays with the world, and each fighter rotates separately.
3. `DuelFumbles` is a field of `duel.Relations` with a default; the script's `relations` line still names seven relations, so existing scripts compile unchanged.
4. `.bspk` version 14 reads the old flag byte as a line count. Versions 1 to 13 wrote 0 or 1, which reads the same, so they load unchanged; a count above 1 in a pre-14 package, or above 8 in any, is rejected as `InvalidDuelConfig`.
**Alternatives:**
- Offer all three lines as choices at once: rejected by the maintainer in favour of one line per round.
- Pick by tick or a random draw: rejected; the line would change with timing, and the engine's simulation keeps no unseeded randomness.
- Add `DuelFumbles` as an eighth name on the `relations` line: rejected; it would break every script that themes the vocabulary.
**Consequences:** One more property fact per fighter who has fumbled. The relation name is not themeable from a script; a host can still set it in `duel.Relations`.

## D-077 Dialogue Shows in a Wrapped Panel Along the Bottom, on Desktop and in the Browser (2026-11-13, status: accepted)
**Context:** The maintainer's hand test of Brackwater Barbs found the dialogue unreadable. The desktop balloon never wrapped: the speaker's name and line shared one row, the width ignored the name so text ran past the edge, and choices were cut at 80 bytes. The browser had no dialogue view; it wrote the choices into a one-row, 96-byte banner and never showed the prompt. Speaker labels were raw entity names (`BosunPike`).
**Decision:**
1. One layout, `src/display/dialogue_panel.zig`, word-wraps the speaker, the prompt, and numbered choices into a panel of fixed width. It is pure (no SDL, no drawing) so the window and the browser draw the same rows, and it reports each choice's vertical span for clicks.
2. The panel spans the stage along the bottom, above the action sentence and verb bar on desktop (and above the command bar when shown) and above the banner in the browser, and grows upward. It replaces the balloon anchored over the speaker; the `show_dialogue` signature keeps its speaker position so callers are unchanged.
3. Speaker names are shown through `display_name`, which splits CamelCase (`BosunPike` reads `Bosun Pike`, `NPCGuard` reads `NPC Guard`). Scripts do not change.
4. The browser answers a click on a choice row, keeps number keys, and wraps its banner (now 256 bytes) over two rows. Choice text holds 160 bytes in `RenderDialogue` and the balloon.
**Alternatives:**
- A wrapped balloon over the speaker: rejected by the maintainer; it covers other characters and moves with the speaker.
- Balloons for speech and a panel for choices: rejected; two layouts to keep in step.
- A script-declared display name: rejected for now; it is a language and `.bspk` change, and CamelCase covers today's names.
**Consequences:** A name with an inner capital (`McAllister`) splits wrongly until a script gives it a space. The panel names the dialogue's display speaker, which for a choice in the player's own cue handler is the player. Every browser frame hash and the two desktop renders with dialogue open changed once.

## D-078 Duel Fighters Learn What They Hear, and the Duel Proof Takes Turns (2026-11-13, status: accepted)
**Context:** D-035's duel taught the defender the correct reply whenever a round was lost, "from the attacker's taunt". The maintainer's hand test showed the result: the opponent answered his own barb, which no fencer would do. An attacker presses on with another barb or claims victory.
**Decision:**
1. `Duel.resolve_round` teaches each fighter what it hears: the defender the challenge, the attacker the reply it got back (when the reply is a real one). Losing a round teaches the defender nothing more.
2. `Duel.answer(fighter, challenge)` gives a host-driven opponent's reply: the countering comeback if the fighter has mastered it, else the fallback.
3. The duel proof takes turns in a shared `Bout`: whoever wins a round attacks next; an attacking opponent moves to `Duel.next_challenge`. A fencing master (tier 1 or above) always attacks: she knows every comeback, so a parried attack would only trade the lead back and forth and no one would reach three. The player leads a duel when she has a barb to throw at a non-master.
4. What each opponent knows is game content in the script, as top-level `remember MasteredComeback(...)` lines: Bosun Pike knows comebacks 1 to 8, Old Gannet 1 and 9 to 15, Mistress Vell all fifteen. Victory lines are `on cue WinsDuel(winner, loser):` handlers the host fires when a duel ends.
**Alternatives:**
- Keep the engine rule and hide the comeback (silent learning): rejected by the maintainer; the player would learn a line they never heard.
- Let a master defend too: rejected; with full knowledge she cannot lose a defence, so the duel would never end.
**Consequences:** The duel needs opponents who know some comebacks; a script that declares none gives the player no way to learn them. The window gains a G key for Old Gannet. The proof transcript, the browser deck, and its tests changed with the rule.

## D-079 Duel Rounds Score Points, and Each Barb Is Thrown Once per Duel (2026-11-13, status: accepted)
**Context:** The maintainer felt the player should win sometimes. A simulation of the Brackwater Barbs duel found Bosun Pike unbeatable and Old Gannet beaten only by repeating one barb he could not answer. D-035's round rule moved a point of advantage: the round's winner gained one and the loser lost one. A defender who parried then had to attack, and against an opponent who knew every barb she had, the next parried barb took the point back, so she could never reach three.
**Decision:** (maintainer's choice, 2026-11-13)
1. `Duel.resolve_round` adds a point for the round's winner and takes nothing from the loser. The first fighter to `win_at` points wins; both reset, as before.
2. The duel proof's `Bout` lets the player throw each barb once per duel (`ThrownThisDuel` facts, cleared when a duel starts or ends). A player who wins a round with no barb left to throw defends instead.
3. The opponents' knowledge from D-078 is unchanged. Simulated over 40 players who try barbs an opponent failed to answer before, Tamsin beats Gannet from their second duel and Pike from about their sixth; a player who always picks the first barb never wins.
**Alternatives:**
- Keep the tug of war: rejected by the maintainer; parries would not count.
- Allow repeats: rejected by the maintainer; one unanswerable barb would win three rounds.
- Thin the opponents' knowledge (Pike odd comebacks, Gannet even): simulated and not taken; it made both opponents slower to beat, and the split is approved game content.
**Consequences:** Every duel built on `src/duel.zig` scores this way. No golden changed. Vell, a master, still always attacks (D-078), so beating her means parrying three of her barbs before she lands three.

## D-080 Click-Through Messages Show One Piece at a Time (2026-11-13, status: accepted)
**Context:** After a duel round the desktop showed one banner: the opponent's line, who took the round, and the points. It was too long for the banner's scale-2 font, so the banner fell back to scale 1, which was hard to read, and it disappeared on a timer whether or not the player had read it. The maintainer asked that each piece be its own window, in succession, clicked through before play continues.
**Decision:**
1. `src/display/beats.zig` holds a queue of up to eight messages, each a speaker (stored as a display name, D-077) and a line, copied in. It is pure data, shared by the window and the browser.
2. `dialogue_panel.layout_message` lays out a message in the dialogue panel's place and width: the speaker, the wrapped line, and a continue hint on the last row.
3. While a message waits, it covers the dialogue panel. A left click anywhere, Enter, or Space dismisses it (in the browser, also the solve key). The number keys cannot answer the choices it hides, and the hint and choices stay hidden until the queue is empty. Hosts queue with `DisplayWindow.queue_message` or `WasmRuntime.queue_message`.
4. `host.speech_lines` gives each `say` line of the most recent tick on its own, so a host can queue them one by one instead of joining them as `SpeechLog` does.
5. Brackwater Barbs queues each round as up to four messages, in the order an adventure game shows an exchange (maintainer, 2026-11-13): the line the player chose, echoed in Tamsin's voice; the opponent's reply, when she attacked; "Your point." or "Their point."; and the points; a duel's end queues the opponent's line and the script's victory line. Points are worded "Points", since "score" is the glossary's word for music.
**Alternatives:**
- A larger banner that waits for a click: rejected; one box still holds every piece at once.
- Messages that time out: rejected; the maintainer wants the player to have time to read.
- Script-level syntax for pauses: not needed yet; hosts queue messages, and other proofs keep their banners.
**Consequences:** The clock keeps running while a message waits. Timed banners remain for short notices. No golden changed.

## D-081 Tamsin Can Answer with a Joke in Every Defence (2026-11-13, status: accepted)
**Context:** A defending player saw only her known comebacks, or one stammered fallback line when she knew none. The maintainer asked for joke answers she can pick when she lacks the real one, and wrote five (2026-11-13).
**Decision:**
1. The script's duel declares eight `fallback` lines: the three stammers from P35-02 and the maintainer's five jokes, as written. Eight is the declaration's limit (`DUEL_MAX_FALLBACKS`).
2. In every defence the proof's `Bout` offers two of them after the player's known comebacks (maintainer's choice), so their presence never shows whether she knows the answer. The player's fumble count picks the pair, so each defence offers new ones and the rotation rewinds with the world (D-076). A joke always loses the round and is echoed in Tamsin's voice (D-080).
3. A joke's action id is `Bout.JOKE_ACTION` plus its line index, far above any entity id. The engine is unchanged: `Duel.replies` still offers its single fallback, which the proof replaces with the pair.
**Alternatives:**
- Jokes only when no known comeback counters the barb: rejected by the maintainer; seeing jokes would tell the player she lacks the answer.
- An engine option for how many fallbacks to offer: not needed yet; it would touch the grammar and the package format for one proof.
**Consequences:** Opponents fumble with the same eight lines. With nine choices at most, a player who knows more than seven comebacks sees the first seven in table order. The browser golden's two deck 7 frames changed (the panel shows two choices; three more text entities).

## Held tensions

A tension is two claims that are true and do not fit together yet. It is not an open question. An open question has
an unknown answer; a held tension has two known answers and a price. Hold it only while the price of holding is
lower than the price of choosing badly.

Each tension names an owner, a review trigger, and the cost of holding both. A tension with no owner or no trigger is
deleted at consolidation. A tension that survives review becomes a decision, with the losing claim recorded as an
alternative.

Format:

```
### T-NNN Title  (YYYY-MM-DD, status: held | resolved by D-MMM)
**Owner:** ...
**Claim A:** ...
**Claim B:** ...
**Why both hold:** ...
**Cost of holding both:** ...
**Review trigger:** ...
```

*(None held currently. When two true claims cannot yet be reconciled, record them here as `T-NNN` with owner, claims, cost, and review trigger rather than forcing a premature compromise.)*

---

## Open questions

Questions requiring maintainer or stakeholder input. This is their one home: HANDOFF and the roadmap refer to them by ID. Numbers are permanent; an answered question stays, with the answer and its date.

- **Q-001** ~~Spatial topology representation: Should the default spatial model in the spine be a discrete 2D tile grid, a room/waypoint node graph, or a hybrid?~~ Answered 2026-11-04: Room/waypoint node graph adopted for graphical adventure game priority; 2D tile grids deferred, D-005. Revisited 2026-11-10: an optional grid overlay complements the graph, D-054.
- **Q-002** ~~Fact query indexing: At what scale does linear scanning over `MultiArrayList(Fact)` need to be augmented with sparse bitsets or entity-indexed hash tables?~~ Answered 2026-11-04: Linear scan over SoA columns adopted as baseline; cache-efficient and preserves zero-overhead `memcpy` saves, D-006.
- **Q-003** ~~Continuous numerical stats representation: Should continuous/metered stats be stored in a dedicated numeric table/struct per entity, or represented as ternary relational facts?~~ Answered 2026-11-04: Unified ternary facts with functional property auto-overwrite adopted, D-007.
- **Q-004** ~~Time-branch helpers that claim more than they do (raised 2026-11-13, session 58).~~ Answered 2026-11-13: implement them, D-073. Correction: the question said the two checks had no caller outside unit tests; `proofs/darko_puzzle.zig` asserts both in its headless run. `validate_novikov_consistency` ignores its `candidate_action` argument; it and `TemporalHypervisor.is_teleologically_justified` have no caller outside their unit tests; `check_loop_closure` looks up the proof-derived relation name `VortexReady`; `CausalDecayTracker` returns an `f32`. Options: implement the checks the names promise, keep them as documented stubs, or remove them and the `VortexReady` alias (the Middlesex Anomaly uses `LoopClosed`). See Claims vs. code in `ARCHITECTURE.md`.
- **Q-005** ~~Third-party names and text in public material (raised 2026-11-13, session 58).~~ Answered 2026-11-13: rewrite each commercial source as a generalized original, one at a time with the maintainer; Phase 35 in `ROADMAP.md`. Several proofs reuse titles, character names, and places from commercial games and a film (Monkey Island, Gabriel Knight 3, Broken Sword, Day of the Tentacle, Indiana Jones and the Fate of Atlantis, Loom, Donnie Darko), and the Insult Sword Fighting script contains the original game's insult and comeback lines verbatim. The showcase gallery publishes those scripts. Should the public site and the proofs keep these names and lines, rename them to original ones, or keep them in the repository but leave them off the published site? Renaming changes scripts, goldens, and render hashes.
- **Q-006** ~~Cue `where` guards that compile and do nothing (raised 2026-11-13, session 58; recorded under Claims vs. code since 2026-11-08).~~ Answered 2026-11-13: implement them, D-072. The parser accepts `on cue X(...) where ...:` and the handler runs whether or not the guard holds, with no warning. Should the compiler reject the guard until it is implemented, warn, or should the guard be implemented? `script_spec.md` opens with this form.
- **Q-007** The showcase's Manual link on the published site (raised 2026-11-13, session 58). Answered 2026-11-13: the maintainer uploads by hand; `export` stays and `upload` is gone (D-074). The live site serves the manual at `docs/manual.html` beside `index.html`, and the page links there. Opened from the repository over `file://`, `site/index.html` now looks for `site/docs/manual.html`, which does not exist. `site/index.html` links `../docs/manual.html`, but `tools/deploy_site.py export` writes only the page, so the link breaks on Neocities. Options: export the manual beside the page, link the repository's copy, or drop the link from the published page.
