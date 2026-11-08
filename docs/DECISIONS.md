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

## Open questions

Questions requiring maintainer or stakeholder input. This is their one home: HANDOFF and the roadmap refer to them by ID. Numbers are permanent; an answered question stays, with the answer and its date.

- **Q-001** ~~Spatial topology representation: Should the default spatial model in the spine be a discrete 2D tile grid, a room/waypoint node graph, or a hybrid?~~ Answered 2026-11-04: Room/waypoint node graph adopted for graphical adventure game priority; 2D tile grids deferred, D-005.
- **Q-002** ~~Fact query indexing: At what scale does linear scanning over `MultiArrayList(Fact)` need to be augmented with sparse bitsets or entity-indexed hash tables?~~ Answered 2026-11-04: Linear scan over SoA columns adopted as baseline; cache-efficient and preserves zero-overhead `memcpy` saves, D-006.
- **Q-003** ~~Continuous numerical stats representation: Should continuous/metered stats be stored in a dedicated numeric table/struct per entity, or represented as ternary relational facts?~~ Answered 2026-11-04: Unified ternary facts with functional property auto-overwrite adopted, D-007.
