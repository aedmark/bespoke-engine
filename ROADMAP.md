# Roadmap

Item IDs are permanent: `P<phase>-<nn>`. Never renumber; append new items at the end of their phase.
`[ ]` open · `[~]` in progress · `[x]` done · `[-]` dropped.

## Phase 1: Foundations (Relational World Store & Core Memory)

Goal: Build the contiguous Zig `World` storage, fact tuples, relational pattern matching, and memory snapshot serialization.

- [x] P1-01 Initialize Zig project structure and contiguous `World` memory arena with `MultiArrayList(Fact)`. (D-002, D-003; completed 2026-11-04, verified via `zig test src/world.zig`)
- [x] P1-02 Implement declarative `remember`, `forget`, and tick-based TTL expiration pruning. (D-003, D-007, Q-003; completed 2026-11-04, verified via `zig test src/world.zig`)
- [x] P1-03 Implement linear and wildcard relation pattern-matching queries (`where Relation(a, _)`). (D-003, D-006, Q-002; completed 2026-11-04, verified via `zig test src/world.zig`)
- [x] P1-04 Implement deterministic memory snapshot serialization (`save_state` and `restore_state` via arena `memcpy`). (D-001, D-003; completed 2026-11-04, verified via `zig test src/world.zig`)

## Phase 2: Bytecode VM & Fiber Scheduler

Goal: Build the custom bytecode instruction set, virtual machine dispatcher, and cooperative fiber scheduler with interrupt stacks.

- [x] P2-01 Define core bytecode opcode set (control flow, stack manipulation, relational queries, temporal yields). (D-002; completed 2026-11-04, verified via `zig test src/bytecode.zig`)
- [x] P2-02 Implement fiber runtime with cooperatively scheduled routine fibers and master tick clock. (D-004; completed 2026-11-04, verified via `zig test src/vm.zig`)
- [x] P2-03 Implement `wait <ticks>` and `wait until <cond>` suspension/resumption in the VM. (D-004; completed 2026-11-04, verified via `zig test src/vm.zig`)
- [x] P2-04 Implement `interrupt ... with` stack frame push, execution, and clean resumption. (D-004; completed 2026-11-04, verified via `zig test src/vm.zig`)

## Phase 3: Spatial Topology & Motor Subsystem

Goal: Implement the native spatial graph and asynchronous motor intents in the engine spine.

- [x] P3-01 Implement discrete spatial topology (room/waypoint graph or tilemap) and A* pathfinder in the engine spine. (D-001, D-005, Q-001; completed 2026-11-04, verified via `zig test src/spatial.zig`)
- [x] P3-02 Implement desugared `walk <entity> to <target>` asynchronous motor intent with arrival/obstruction events. (D-001, D-004; completed 2026-11-04, verified via `zig test src/spatial.zig` and `zig test src/vm.zig`)

## Phase 4: Language Front-End & Compiler

Goal: Create the hand-written Zig compiler front-end that compiles the BeSpoke syntax into bytecode.

- [x] P4-01 Hand-written Zig lexer for the BeSpoke language syntax. (D-002; completed 2026-11-04, verified via `zig test src/compiler/lexer.zig`)
- [x] P4-02 Parser generating AST for entities, relations, routines, cues, and rules. (D-002; completed 2026-11-04, verified via `zig test src/compiler/parser.zig`)
- [x] P4-03 Bytecode code generator emitting compact VM binaries from AST. (D-002; completed 2026-11-04, verified via `zig test src/compiler/codegen.zig`)

## Phase 5: Display Bridge & Vertical Slice

Goal: Connect a downstream rendering peripheral and execute the 20-line Tavern Heist vertical slice with live rewind.

- [x] P5-01 Peripheral bridge exporting double-buffered read-only render state and audio cue events to Raylib or Sokol. (D-001; completed 2026-11-04, verified via `zig test src/display.zig`)
- [x] P5-02 Reference implementation executing the Tavern Heist vertical slice with real-time rewind. (D-001, D-003, D-004; completed 2026-11-04, verified via `zig build run`)

## Phase 6: Peripheral Graphics Window (2D Display)

Goal: Connect an SDL2 2D display window as a downstream consumer of the `DisplayBridge`, rendering waypoint topology, actor positions, and handling point-and-click mouse input.

- [x] P6-01 Window and rendering loop consumer that opens an SDL2 display window and polls `DisplayBridge.poll()` at 60 Hz. (D-001, D-008; completed 2026-11-04, verified via `zig test -lc -lSDL2 src/display.zig`)
- [x] P6-02 2D scene visualization: render room boundaries, waypoint nodes, edge corridors, and actor tokens/sprites with orientations. (D-001, D-005, D-008; completed 2026-11-04, verified via `zig test -lc -lSDL2 src/display.zig`)
- [x] P6-03 Point-and-click mouse input handling: map clicks on waypoints to simulation motor intents (`walk_to`) for the player character. (D-001, D-005, D-008; completed 2026-11-04, verified via `zig test -lc -lSDL2 src/display.zig` and interactive run)
- [x] P6-04 Visual cue HUD and event banner: display floating on-screen cue notifications, dialogue balloons, and simulation clock state. (D-001, D-008; completed 2026-11-04, verified via `zig test -lc -lSDL2 src/display.zig` and `zig build run`)

## Phase 7: Adventure Game Primitives (Verbs, Inventory, Dialog & Hotspots)

Goal: Expand the BeSpoke language syntax and runtime with first-class point-and-click adventure game constructs.

- [x] P7-01 Hotspots and inspectable scene objects: static interactable regions with examine text, hover cursors, and condition-guarded interaction cues. (D-001, D-009; completed 2026-11-04, verified via `zig test src/spatial.zig` and `zig test -lc -lSDL2 src/display.zig`)
- [x] P7-02 Classic adventure verbs: grammar and bytecode support for `LookAt`, `PickUp`, `UseWith`, `TalkTo`, and contextual verb interactions. (D-002, D-009; completed 2026-11-04, verified via `zig test src/compiler/lexer.zig`, `zig test src/compiler/parser.zig`, and `zig test -lc -lSDL2 src/root.zig`)
- [x] P7-03 Relational inventory system: first-class inventory state (`InInventory(Player, Item)`), inventory combining, and inventory bar UI. (D-003, D-007; completed 2026-11-04, verified via `zig test src/world.zig`, `zig test -lc -lSDL2 src/display.zig`, and `zig build run -- --headless`)
- [x] P7-04 Branching dialogue & speech: `say Actor: "text"` primitive with temporal speech balloon suspension, click-to-dismiss, and dialogue choice trees. (D-002, D-004, D-009; completed 2026-11-04, verified via `zig test -lc -lSDL2 src/root.zig` and `zig test -lc -lSDL2 src/display.zig`)

## Phase 8: Reactive Simulation Rules (`when` Engine in VM)

Goal: Implement continuous pattern-matching rule triggers in the engine spine so complex world conditions react without manual polling.

- [x] P8-01 Multi-clause relational pattern matcher: support relational conjunctions (`where A and B and C`) and join queries across active facts. (D-003, D-006, D-007, D-010; completed 2026-11-04, verified via `zig test src/world.zig` and `zig test src/compiler/parser.zig`)
- [x] P8-02 VM reactive `when` evaluation engine: evaluate `when <condition>:` rules on fact mutation or tick boundary and automatically trigger fiber interrupts. (D-002, D-004, D-010; completed 2026-11-04, verified via `zig test src/vm.zig` and `zig test -lc -lSDL2 src/root.zig`)
- [x] P8-03 Systemic AI behaviors: priority rule cascades for NPC moods, systemic theft, guards chasing thieves, and alert states. (D-003, D-004, D-010; completed 2026-11-04, verified via `zig test src/vm.zig` and `zig build run -- --headless`)

## Phase 9: Interactive Time-Travel Debugger & REPL

Goal: Build an interactive developer dashboard and time-travel timeline scrubber for inspecting and manipulating simulation state live.

- [x] P9-01 In-engine debug overlay / HUD: live inspector displaying active relational facts, active fibers, call stacks, and spatial coordinates. (D-001, D-011; completed 2026-11-04, verified via `zig test -lc -lSDL2 src/display.zig` and interactive window)
- [x] P9-02 Interactive time-travel timeline scrubber: pause, step forward, and scrub backward across historical snapshot states with instantaneous live visual replay. (D-001, D-003, D-011; completed 2026-11-04, verified via `zig test -lc -lSDL2 src/display.zig`, `zig build run -- --headless`, and timeline scrubber)
- [x] P9-03 Live interactive REPL / console: inject facts (`remember ...`), emit cues (`PlayLute`), and test scripts in a running simulation. (D-001, D-002, D-011; completed 2026-11-04, verified via `zig test src/repl.zig`, `zig build test`, and interactive drawer)

## Phase 10: The Booty Island Spitting Contest Scenario & Extended Narrative DSL

Goal: Expand BeSpoke with high-level stageplay declarations, falling-edge and expiration triggers, and implement the complete Monkey Island 2 Spitting Contest puzzle slice.

- [x] P10-01 Declarative stageplay syntax & state declarations: grammar and compiler support for `scene:`, `cast:`, `props:`, `marks:`, and natural state transitions (`now <Entity> is [not] <State>`). (D-001, D-002, D-012; completed 2026-11-06, verified via `zig test src/compiler/lexer.zig`, `zig test src/compiler/parser.zig`, and `zig test -lc -lSDL2 src/root.zig`)
- [x] P10-02 Falling-edge and TTL expiration hooks: VM reactive rule engine support for falling edges (`when <Condition> stops being <State>:`) and fact expiration triggers (`when <Entity> forgets <Relation>:`). (D-004, D-010, D-012; completed 2026-11-06, verified via `zig test src/world.zig`, `zig test src/vm.zig`, and `zig test -lc -lSDL2 src/root.zig`)
- [x] P10-03 The Booty Island Spitting Contest vertical slice: complete multi-step puzzle scenario featuring Guybrush, crowd egging routine, wind cycling, horn distraction, flag moving, thick spit drink, and wind-timed spit resolution. (D-001, D-008, D-009, D-012; completed 2026-11-06, verified via `zig test -lc -lSDL2 src/root.zig`, `zig build test`, and `zig build run -- --spitting-contest`)

## Phase 11: Item-on-Item Inventory Combining & In-Hand Crafting

Goal: Expand the BeSpoke language, compiler, VM, and display renderer with first-class two-operand inventory interactions (`on cue Uses(actor, item_a, item_b)`), allowing items to be combined or applied in-hand before acting on the world.

- [x] P11-01 Compiler grammar and AST support for two-target `Uses` cue declarations (`on cue Uses(Player, ItemA, ItemB):`). (D-002, D-009, D-013; completed 2026-11-06, verified via `zig test -lc -lSDL2 src/root.zig` and `zig build test`)
- [x] P11-02 VM and cue dispatcher support for 3-argument cues `(actor, primary_item, secondary_item)` with commutative matching. (D-004, D-009, D-013; completed 2026-11-06, verified via `zig test -lc -lSDL2 src/root.zig` and `zig test src/vm.zig`)
- [x] P11-03 Peripheral UI interaction in `src/display/renderer.zig`: selecting an active inventory item and clicking a second inventory item in the tray, with visual highlight, in-hand cursor, and banner feedback. (D-008, D-009, D-013; completed 2026-11-06, verified via `zig test -lc -lSDL2 src/display.zig`, `zig build test`, and `zig build run -- --spitting-contest --headless`)

## Phase 12: Multi-Scene Transitions & Stage Director

Goal: Support multiple narrative scenes in a single simulation (`transition to scene: <TargetScene>`), swapping active spatial graph waypoints and visual backdrops while preserving global relational world facts across scene boundaries.

- [x] P12-01 Language grammar and bytecode instruction for scene transitions (`transition to scene: Name`), pausing current scene routines and activating target scene routines. (D-001, D-002, D-004, D-014; completed 2026-11-06, verified via `zig test src/compiler/parser.zig`, `zig test src/vm.zig`, and `zig test -lc -lSDL2 src/root.zig`)
- [x] P12-02 Spatial graph partitioning by scene/room, allowing actors and stage marks to transition between distinct topological environments. (D-001, D-005, D-014; completed 2026-11-06, verified via `zig test src/spatial.zig` and `zig test -lc -lSDL2 src/root.zig`)
- [x] P12-03 Display renderer support for dynamic scene backdrops and visual themes switched on scene change events. (D-001, D-008, D-014; completed 2026-11-06, verified via `zig test -lc -lSDL2 src/display.zig` and `zig build test`)

## Phase 13: Relational Dialogue Trees & Dynamic Choice Pruning

Goal: Support branching dialogue trees where choices dynamically appear, disappear, or alter based on active relational world facts (`choice "..." if Condition:`).

- [x] P13-01 Grammar and AST support for conditionally guarded dialogue choices (`choice "..." if HasFact(...)` or `choice "..." if not HasFact(...)`). (D-002, D-004, D-009, D-015; completed 2026-11-06, verified via `zig test src/compiler/lexer.zig` and `zig test src/compiler/parser.zig`)
- [x] P13-02 VM runtime evaluation of dialogue choice guards at balloon spawn time, pruning unsatisfied branches. (D-003, D-004, D-009, D-015; completed 2026-11-06, verified via `zig test src/vm.zig` and `zig test -lc -lSDL2 src/root.zig`)
- [x] P13-03 Display renderer dynamic balloon sizing, scrolling, and keyboard hotkey selection (`1-9`) for variable-length choice sets. (D-008, D-009, D-015; completed 2026-11-06, verified via `zig test -lc -lSDL2 src/display.zig` and `zig build test`)
- [x] P13-04 Grammar, AST, and VM support for relational where-pattern conjunctions in dialogue choices (`choice "..." where Pattern1 and Pattern2:`). (D-002, D-004, D-015, D-017; completed 2026-11-07, verified via `zig test src/compiler/parser.zig`, `zig test -lc -lSDL2 src/vm.zig`, and `zig build test`)
- [x] P13-05 The Monkey Island Insult Sword Fighting and Organic NPC Repetition scenario in `src/sword_fighting.zig` with 16 canonical insults, 16 counters, Carla master variants, target validation, and TTL mood decay. (D-001, D-003, D-015, D-017; completed 2026-11-07, verified via `zig test -lc -lSDL2 src/sword_fighting.zig` and `zig build run -- --sword-fighting --headless`)
- [x] P13-06 CLI option `--sword-fighting` / `--insults` with 7-step deterministic headless simulation verification and 60 Hz interactive playability. (D-001, D-008, D-015, D-017; completed 2026-11-07, verified via `zig build run -- --sword-fighting --headless` and `zig build test`)

## Phase 14: The Gabriel Knight 3 Cat Moustache Scenario

Goal: Implement the complete *Gabriel Knight 3* Rennes-le-Château Cat Moustache vertical slice in `src/gk3_moustache.zig`, runnable via `--gk3`.

- [x] P14-01 Full GK3 puzzle script implementation in BeSpoke DSL: Mosely room break-in, fence hole taping, cat water squirting, syrup lip adhesive, cat moustache crafting, and Buthane rental shop validation. (D-001, D-012, D-013, D-015, D-016; completed 2026-11-06, verified via `zig test -lc -lSDL2 src/root.zig` and `zig build run -- --gk3 --headless`)
- [x] P14-02 Visual renderer backdrop for Rennes-le-Château (hotel corridor, garden fence, bike rental desk) and custom actor tokens (Gabriel in trench coat, Mosely, Buthane, Stray Cat). (D-008, D-009, D-012, D-014, D-016; completed 2026-11-06, verified via `zig test -lc -lSDL2 src/display.zig` and `zig build test`)
- [x] P14-03 CLI option `--gk3` / `--cat-moustache` with end-to-end headless simulation verification and interactive 60 Hz playability with time-travel rewind. (D-001, D-008, D-011, D-016; completed 2026-11-06, verified via `zig build run -- --gk3 --headless` and `zig build test`)

## Phase 15: Standalone Script File Execution & Compiler CLI

Goal: Support executing external `.bespoke` scenario files directly from disk via CLI, with script file parsing, syntax verification, and optional bytecode binary compilation.

- [x] P15-01 CLI script runner (`bespoke run <script.bespoke>`) parsing and compiling external text files from the host filesystem in both headless and GUI modes. (D-001, D-002, D-018; completed 2026-11-07, verified via `zig test -lc -lSDL2 src/runner.zig`, `./zig-out/bin/bespoke run scenarios/tavern_heist.bespoke --headless`, and `./zig-out/bin/bespoke run scenarios/tavern_heist.bspk --headless`)
- [x] P15-02 Bytecode binary emission and standalone asset loader (`bespoke compile <script.bespoke> -o game.bspk`), serializing and deserializing compiled bytecode chunks with versioning and validation. (D-002, D-018; completed 2026-11-07, verified via `zig test src/package.zig` and `./zig-out/bin/bespoke compile scenarios/tavern_heist.bespoke -o scenarios/tavern_heist.bspk`)
- [x] P15-03 Script diagnostics and validation tooling (`bespoke check <script.bespoke>`) with file, line, and column error reporting. (D-002, D-018; completed 2026-11-07, verified via `zig test src/compiler.zig`, `zig test src/compiler/parser.zig`, and `./zig-out/bin/bespoke check scenarios/tavern_heist.bespoke`)

## Phase 16: Peripheral Audio Subsystem & Procedural Sound Synthesizer

Goal: Connect an SDL2 audio peripheral callback to the `DisplayBridge` cue stream, synthesizing procedural chiptune sound effects and background musical melodies triggered by simulation cues.

- [x] P16-01 Audio bridge buffer and peripheral audio consumer in `src/display.zig` consuming audio cue events decoupled from simulation ticks. (D-001, D-019; completed 2026-11-07, verified via `zig test -lc -lSDL2 src/display.zig` and `zig test src/audio.zig`)
- [x] P16-02 Procedural square-wave and noise sound synthesizer in pure Zig (zero audio asset dependencies) for action SFX (footsteps, pickups, splashes, alert stingers). (D-001, D-019; completed 2026-11-07, verified via `zig test src/audio.zig` and `zig test -lc -lSDL2 src/root.zig`)
- [x] P16-03 Scene background musical accompaniment with track switching triggered on scene transitions and narrative dramatic shifts. (D-001, D-014, D-019; completed 2026-11-07, verified via `zig test src/audio.zig` and `zig test -lc -lSDL2 src/display.zig`)

## Phase 17: Persistent Save/Load Disk Storage & Slot Management

Goal: Extend memory snapshot serialization to disk files, providing durable save/load slot management with metadata headers and in-engine UI.

- [x] P17-01 File-backed save state format (`.sav`) with versioning, CRC32 integrity checksums, and metadata headers (playtime, tick, scene, thumbnail/frame snapshot). (D-001, D-003, D-020; completed 2026-11-07, verified via `zig test src/save.zig` and `zig test -lc -lSDL2 src/root.zig`)
- [x] P17-02 Slot management API supporting numbered save slots, quick-save, quick-load, and corrupted save recovery. (D-003, D-020; completed 2026-11-07, verified via `zig test src/save.zig`)
- [x] P17-03 In-engine save/load drawer and pause menu overlay integrated into the SDL2 renderer. (D-008, D-011, D-020; completed 2026-11-07, verified via `zig test -lc -lSDL2 src/display.zig` and `zig build test`)

## Phase 18: Systemic Emergent Simulation Sandbox ("The Living Village")

Goal: Implement a multi-agent systemic emergent simulation sandbox in `src/village.zig` demonstrating dozens of autonomous NPCs driven by relational needs, social memory, property ownership, and emergent justice cascades.

- [x] P18-01 Village relational schema and autonomous NPC drive system: physiological needs (Hunger, Energy), emotional states, and social relationships (Friend, Rival, Trust) updated via continuous relational rules. (D-003, D-007, D-010, D-021; completed 2026-11-08, verified via `zig test -lc -lSDL2 src/village.zig` and `zig test -lc -lSDL2 src/root.zig`)
- [x] P18-02 Emergence engine: systemic crime, witness detection, rumor propagation, property theft, and autonomous sheriff investigation/arrest cascades. (D-004, D-010, D-021; completed 2026-11-08, verified via `zig test -lc -lSDL2 src/village.zig` and `zig build run -- --village --headless`)
- [x] P18-03 Village spatial topology and settlement visualization: multi-building settlement (bakery, tavern, houses, sheriff's post, farm, town square) with live social graph HUD and event chronicle. (D-005, D-008, D-011, D-021; completed 2026-11-08, verified via `zig test -lc -lSDL2 src/display.zig` and `zig build test`)

## Phase 19: WebAssembly & HTML5 Canvas Browser Target

Goal: Compile BeSpoke Engine to WebAssembly using Zig's cross-compilation toolchain, rendering to an HTML5 canvas and embedding interactive simulations directly into the 3x documentation.

- [x] P19-01 Zig build target and runtime harness for `wasm32-freestanding` or Emscripten with WebGL/Canvas rendering. (D-001, D-022; completed 2026-11-08, verified via `zig test src/wasm.zig` and `zig build wasm`)
- [x] P19-02 Browser event bridge mapping mouse, keyboard, and touch events to BeSpoke motor and dialogue intents. (D-008, D-022; completed 2026-11-08, verified via `zig test src/wasm.zig`)
- [x] P19-03 Interactive embedded manual simulator hosting live BeSpoke vertical slices inside `docs/manual.html`. (D-001, D-011, D-022; completed 2026-11-08, verified via `python3 tools/manual.py build scheme/bespoke.manual.json --output docs/manual.html --check` and `python3 -m unittest discover -s tests -v`)

## Phase 20: The Broken Sword Lochmarne Goat Puzzle Scenario

Goal: Implement the complete *Broken Sword: The Shadow of the Templars* Lochmarne Goat vertical slice in `src/goat_puzzle.zig`, authentic 1996 reactive charge/retreat timing windows, custom visual backdrops (Castle Courtyard and Subterranean Templar Dig), procedural Celtic whistle and goat bleat audio, and dual headless/interactive CLI modes with time-travel rewind.

- [x] P20-01 Full Broken Sword goat puzzle script implementation in BeSpoke DSL (`src/goat_puzzle.zig`): Irish castle courtyard scene, cellar entrance pit, tethered Billy Goat, farm plough, reactive threat-radius charge interrupt, knockback, 30-tick retreat action window, plough dragging, rope tangling, and cellar descent transition to the Templar crypt. (D-001, D-004, D-010, D-012, D-014, D-023; completed 2026-11-08, verified via `zig test -lc -lSDL2 src/goat_puzzle.zig`)
- [x] P20-02 Visual backdrops for Lochmarne Castle Courtyard and Subterranean Templar Dig Crypt, with custom actor tokens (George Stobbart in jacket and Billy Goat with horns/beard) in `src/display/renderer.zig`. (D-008, D-009, D-012, D-014, D-023; completed 2026-11-08, verified via `zig test -lc -lSDL2 src/display.zig`)
- [x] P20-03 CLI options `--goat`, `--broken-sword` in `src/main.zig`, procedural Celtic whistle melody and goat bleat/thud SFX in `src/audio.zig`, end-to-end headless simulation verification with rewind, and 3x documentation manual update. (D-001, D-008, D-011, D-019, D-023; completed 2026-11-08, verified via `zig build run -- --goat --headless`, `python3 tools/manual.py build scheme/bespoke.manual.json --output docs/manual.html --check`, and `python3 tools/check_docs.py`)

## Phase 21: Multi-Character Party Coordination, Generalized Item Transfer, and Temporal Epistemic Dialogue ("Day of the Tentacle Trio")

Goal: Support multi-protagonist party management with active player switching, generalized party inventory transfer across actors (`transfer_item`), epistemological dialogue belief evaluation, forward-propagating temporal causality cascades, and the complete three-era Day of the Tentacle puzzle scenario (*The Chrono-Mansion Trio*).

- [x] P21-01 Multi-character party coordination, active protagonist switching (`party: []EntityId`, `active_character`, `switch_actor`), and generalized inventory item transfer (`transfer_item`, `give <Item> to <Actor>`) with remote/colocated policies and party portrait HUD. (D-001, D-008, D-009, D-025; completed 2026-11-08, verified via `zig test src/world.zig`, `zig test src/spatial.zig`, and `zig test -lc -lSDL2 src/display.zig`)
- [x] P21-02 Epistemological dialogue belief evaluation (`D-015`, `D-017` extension) where NPCs evaluate choices against active entity beliefs/knowledge facts, combined with forward-propagating temporal causality cascades (strict DAG past-to-future projection) and container duration catalysts. (D-003, D-010, D-014, D-015, D-017, D-025; completed 2026-11-08, verified via `zig test src/vm.zig`)
- [x] P21-03 The Day of the Tentacle three-era milestone scenario implementation (`src/dott_puzzle.zig`, `--dott` / `--tentacle`): 1790 (Colonial), 1993 (Motel), 2193 (Future Dystopia), complete parallel puzzle DAG (Wine/Capsule/Vinegar, Super Battery, Kumquat/Cherry Tree, Tentacle Flag disguise), visual backdrops, actor tokens, procedural audio, and headless/interactive verification with time-travel rewind. (D-001, D-008, D-011, D-019, D-025; completed 2026-11-08, verified via `zig test -lc -lSDL2 src/dott_puzzle.zig`, `zig build run -- --dott --headless`, and `python3 tools/manual.py build scheme/bespoke.manual.json --output docs/manual.html --check`)

## Phase 22: The Loom Musical Weaver System & Pitch-Based Spellcraft

Goal: Implement musical draft spellcasting inspired by *Loom* (1990), where the protagonist weaves 4-note musical drafts on a distaff, learning tunes from environmental observations, playing drafts in reverse for complementary effects, and triggering procedural synthesizer audio.

- [x] P22-01 Language grammar and bytecode primitives for musical drafts (`draft <Name>(<n1>, <n2>, <n3>, <n4>) [reverse <Inverse>]` and `weave <Draft> on <Target>`), with reversible draft inversion semantics. (D-009, D-029; completed 2026-11-08, verified via `zig build test`, `zig test -I/usr/include/SDL2 -lc -lSDL2 src/package.zig --test-filter P22-01` (9 tests), and `bespoke check` / `compile` / `run` on a draft script)
- [x] P22-02 Procedural synthesizer integration in `src/audio.zig`, rendering discrete pitches (C, D, E, F, G, A, B) directly to audio output upon player note input, and distaff staff HUD in `src/display/renderer.zig`. (D-019, D-030; completed 2026-11-08, verified via `zig build test` (135/135), `zig test src/audio.zig`, `zig test src/draft.zig`, and an offscreen SDL render of the HUD; desktop audio not checked by ear)
- [x] P22-03 Original bell-tower vertical slice scenario (`src/loom_puzzle.zig`, `--loom`): drafts learned by observing the environment (`Kindle`/`Douse`, `Bind`/`Loose`, `Toll`/`Hush`), a reversed-draft inversion puzzle (`Loose` is never taught), distaff reach gating, an in-script weave re-dispatched by the host, and dual headless/interactive verification. The setting is original by maintainer decision (2026-11-08); the mechanics carry the phase. (D-029, D-030; completed 2026-11-08, verified via `zig build test` (138/138), `zig build run -- --loom --headless`, offscreen SDL renders of both scenes, and an offscreen interactive launch; not hand-played)

## Phase 23: The Caustic Grog Sprint & Container Degradation Cascades

Goal: Model dynamic physical container degradation cascades inspired by *The Secret of Monkey Island* (1990), where caustic grog eats through pewter mugs across tick-based TTL expiration cascades, requiring rapid item-to-item transfers while navigating spatial waypoints.

- [ ] P23-01 Container durability and caustic corrosion mechanics in `World`, modeling progressive container states (`PewterMug`, `CorrodedMug`, `MeltingMug`, `PuddleOfSlag`) via cascading relational timers.
- [ ] P23-02 Rapid in-hand pouring interactions (`Uses(Player, MeltingMug, FreshMug)`), resetting degradation timers while preserving liquid volume, with spill penalties on waypoint transit delays.
- [ ] P23-03 The Melee Island Prison Break vertical slice scenario (`src/grog_puzzle.zig`, `--grog`): SCUMM Bar kitchen barrel to Otis's cell lock, multi-mug sprint, audio sizzle SFX, and dual headless/interactive verification with time-travel rewind.

## Phase 24: Multi-Path Divergence & Structural Route Pruning

Goal: Implement structural multi-path narrative divergence inspired by *Indiana Jones and the Fate of Atlantis* (1992), where choosing an operational approach (Wits, Fists, Team) prunes incompatible puzzle DAG branches, alters spatial topology, and adjusts dialogue dynamics.

- [ ] P24-01 DSL stageplay path declarations (`path Wits:`, `path Fists:`, `path Team:`) and VM route-pruning engine, asserting path-locked facts and muting alternative branch routines.
- [ ] P24-02 Dynamic spatial topology and puzzle mutation: adjusting waypoint locks, obstacle rules, and NPC dialogue repertoires dynamically based on active path selection.
- [ ] P24-03 The Fate of Atlantis Algiers vertical slice scenario (`src/atlantis_puzzle.zig`, `--atlantis`): Omar's bazaar, three distinct solutions to acquire the lost dialogue manuscript, path selector UI, and dual headless/interactive verification.

## Phase 25: Discrete Tilemaps, Environmental Hazards, and Cellular Automata

Goal: Complement the waypoint navigation graph with an optional discrete 2D grid subsystem (`Q-001`), supporting systemic environmental propagation such as fire spreading across dry terrain, liquid flooding, and line-of-sight stealth detection.

- [ ] P25-01 Discrete 2D grid data structure and spatial overlay in `SpatialSystem`, mapping grid coordinates to room topologies with configurable cell attributes (flammable, liquid, blocking).
- [ ] P25-02 Tick-based cellular automata rules evaluated in engine spine: fire spreading, smoke dissipation, water flow, and reactive interrupts on actors traversing hazardous cells.
- [ ] P25-03 The Castle Fire Escape systemic scenario (`src/grid_puzzle.zig`, `--grid`): flammable tapestry, torch ignition, fire propagation, bucket dousing, and dual headless/interactive verification.

## Phase 26: Hybrid Text Parser & Natural Language Input

Goal: Provide a classic text-command interface (in the style of Infocom and Sierra SCI) that tokenizes natural language commands (`> examine desk`, `> pour grog into mug`, `> ask washington about cherry tree`) and maps them directly to BeSpoke VM cues alongside mouse verbs.

- [ ] P26-01 Command lexer and vocabulary tokenizer supporting verbs, prepositions (`with`, `on`, `to`, `about`), articles, and entity alias resolution against active scene scope.
- [ ] P26-02 Text parser dispatcher mapping recognized sentence structures to BeSpoke cues (`LooksAt`, `Uses`, `TalksTo`, `WalksTo`), with descriptive disambiguation queries when targets are ambiguous.
- [ ] P26-03 In-engine text parser console bar in `DisplayWindow`, with command history (`Up`/`Down` arrows), inline autocompletion, and dual headless/interactive test verification.

## Phase 27: In-Engine Dialogue & State DAG Visualizer

Goal: Build an interactive visual debugging overlay rendering live relational state graphs, NPC belief networks, cooperative fiber execution stacks, and dialogue choice availability DAGs.

- [ ] P27-01 Real-time relational fact and belief network graph renderer in `DisplayWindow`, drawing nodes (entities) and directed edges (relations, beliefs) with color-coded TTL states.
- [ ] P27-02 Dialogue branch and causality DAG inspector, highlighting active dialogue choices, pruned branches with failed guards, and forward-projecting temporal cascades.
- [ ] P27-03 Interactive graph navigation, filtering by entity or relation kind, and integration into the existing `[P]` Pause / Save drawer and WebAssembly manual viewer.

## Phase 28: Music Macro Language (MML) Scripting & In-DSL Chiptune Composition

Goal: Enable game authors to compose procedural background melodies, arpeggios, and action sound effects directly within `.bespoke` scripts using standard Music Macro Language (MML) notation.

- [ ] P28-01 MML text parser in compiler front-end converting MML score strings (tempo, octave, note lengths, volume envelopes) into procedural synthesizer bytecode chunks.
- [ ] P28-02 Multi-channel MML track execution in `src/audio.zig`, supporting 4 simultaneous tracks (Lead, Bass, Chords, Percussion) with cross-channel synchronization and loop points.
- [ ] P28-03 DSL syntax integration (`score <TrackName>: "t120 o4 l8 cdef e2"`) with dynamic track triggering on scene transitions and narrative dramatic shifts.

## Phase 29: Standalone Game Project Boilerplate & Authoring Starter Kit

Goal: Package an independent project boilerplate, scaffolding CLI (`bespoke init <project_name>`), and authoring starter kit for developers building standalone narrative games with BeSpoke.

- [ ] P29-01 CLI scaffolding generator (`bespoke init <name>`), producing a clean project directory with `build.zig`, sample scenario scripts, custom actor configs, and test harness.
- [ ] P29-02 Comprehensive authoring guide and API documentation in `docs/` and `scheme/bespoke.manual.json`, walking through creating custom scenes, dialogues, and reactive puzzles.
- [ ] P29-03 Reference starter game template with verified unit test suites, asset bundling, and reproducible build pipelines across Linux, Windows, macOS, and WebAssembly.

## Phase 30: Interactive Web Showcase & Neocities Release

Goal: Polish the public-facing showcase website in `site/index.html` with the complete freestanding WebAssembly runtime, hosting all scenarios in an interactive retro terminal shell.

- [ ] P30-01 Enhanced retro web terminal and scenario launcher in `site/index.html`, letting visitors launch and play any BeSpoke vertical slice in browser canvas with audio.
- [ ] P30-02 Neocities deployment pipeline and static export tooling (`tools/deploy_site.py`), optimizing WASM asset size, metadata headers, and offline caching.
- [ ] P30-03 Interactive scenario gallery, architecture diagram embeds, and live script source viewer accompanying each playable slice.

## Phase 31: Cinematic Temporal Hypervisors, The Roberta Sparrow Model, and Pre-Cognitive Vector Conduits

Goal: Implement advanced cinematic temporal mechanics inspired by *Donnie Darko* ("The Philosophy of Time Travel"), *Frequency*, *The Butterfly Effect*, *12 Monkeys*, and *Back to the Future*. Features an ephemeral Tangent Universe hypervisor with collapse tick countdowns and black hole singularities, pre-cognitive Fourth-Dimensional vector worms extruding ahead-of-time deterministic A* paths in the spatial renderer, concurrent bitemporal transceivers for real-time past-to-present materialization, Novikov causal loop consistency checks, and a full vertical slice scenario ("The Middlesex Anomaly", `src/darko_puzzle.zig`, `--darko`).

- [x] P31-01 Tangent Universe hypervisor and teleological constraint solver: copy-on-write `World.fork_tangent` and `World.collapse_tangent` arenas, simulation tick countdown budget (`collapse_tick`), terminal gravitational singularity fail-state, backward-chaining teleological Horn clauses ("Ensured Trap"), and hyper-temporal fibers emitting interrupts from future timelines (the "Manipulated Dead").
- [x] P31-02 Pre-cognitive vector conduits and concurrent bitemporal transceivers: `VectorConduit` ahead-of-time deterministic A* path projection and fluid rendering in `DisplayBridge`/renderer, concurrent dual-era bitemporal synchronization (*Frequency* real-time desk carving), Novikov self-fulfilling loop validation (*12 Monkeys*), and asynchronous causal ripple decay with existence probability dithering (*Back to the Future*).
- [x] P31-03 The Middlesex Anomaly vertical slice scenario (`src/darko_puzzle.zig`, `--darko`): Donnie (Living Receiver), Frank (Manipulated Dead), Gretchen, and Roberta Sparrow across three scenes (Suburban Bedroom, High School, Tangent Vortex Ridge), Artifact of Metal routing, vector worm pursuit, and dual headless/interactive verification with time-travel rewind.

## Phase 32: Engine / Proof-of-Concept Separation

Goal: Keep the engine free of scenario content and keep reusable mechanics out of proofs. Vertical slices are proofs of concept that consume the engine through its public module; no engine file names a proof, its entities, or its art, and no mechanic a second game would need stays in `proofs/` (D-031, D-032). Method and order of work: [docs/SEPARATION.md](docs/SEPARATION.md). Origin: maintainer requests, 2026-11-08 and 2026-11-09.

- [x] P32-01 Move the nine proofs to `proofs/`, extract The Tavern Heist from the engine CLI, export the engine as the `bespoke` module, add the `bespoke-proofs` binary and `test-engine` / `test-proofs` steps, and make `bespoke` engine-only. (D-031; completed 2026-11-08, verified via `zig build test-engine`, `zig build test-proofs`, every proof run headless through `bespoke-proofs`, and a compiler probe rejecting an engine-to-proof import)
- [ ] P32-02 Presentation extension hooks: let a host register scene painters (backdrop, props, actor tokens, footer hint, scenario keys) with `DisplayWindow` and music tracks and SFX with `AudioBridge`, then move all proof art, themes, and music from `src/display/renderer.zig` and `src/audio.zig` into `proofs/`. Acceptance: no proof entity or scene name appears in non-test code of those files. Audit additions (2026-11-09): a neutral engine default scene in place of the tavern backdrop; scenario `UserAction` variants and their global letter keys, and raw scancode hotkeys in proof loops, replaced by proof-registered actions and key bindings; scenario SFX kinds registered by the host.
- [ ] P32-03 Proof logic out of core: replace `RenderFrame` scenario flags and their capture by entity name with a host-supplied status hook, remove the hardcoded `"Laverne"` portal rule from `src/spatial.zig` in favour of script-expressed constraints, and remove scene-name palettes from `src/save.zig`. Acceptance: no proof names in non-test code of `src/display.zig`, `src/spatial.zig`, and `src/save.zig`. Audit additions (2026-11-09): all 41 scenario `RenderFrame` fields, including `cheese_holder` and `charmed_target`, replaced by a host-supplied status channel (countdowns and conduits as generic HUD elements); the `can_access_portal` guard rule driven by facts the script declares rather than the name `"Laverne"`.
- [ ] P32-04 Split `src/wasm.zig` into an engine wasm runtime and a proofs deck built from `proofs/`, and repoint the manual's embedded simulator. Acceptance: `zig build wasm` builds an engine-only module and the manual simulator still runs the proofs.
- [ ] P32-05 Emergent society engine module (D-032): extract a data-driven version of `VillageSimulation` (needs and thresholds, witness detection, rumor propagation, justice cascades) into `src/`, configurable for any roster, locations, and theme, and rewrite `proofs/village.zig` as its client. Acceptance: the engine module names no villager or building, the village proof's headless run and rewind still pass, and a second test roster with different needs runs on the same module.
- [x] P32-06 Separation lint: `tools/check_separation.py` with `tools/separation_baseline.json`, scanning non-test `src/` code for names declared by each proof; fails on hits above baseline, and the baseline only shrinks. Run from the fast test set and `tools/check_docs.py`. Acceptance: current baseline committed, and a deliberate new leak fails the check. (completed 2026-11-09, verified via `python3 -m unittest discover -s tests` (8 new tests), a planted leak in `src/world.zig` failing `tools/check_docs.py`, and the baseline ratcheting from 347 to 339)
- [x] P32-07 Characterization goldens: a `test-proofs` test runs each proof headless into a buffer, normalizes it, hashes the final fact table, and compares with `proofs/golden/<proof>.txt`. Acceptance: all nine goldens committed, and changing one proof's script output fails its test. (completed 2026-11-09, verified via `zig build test-proofs` (28/28) and an altered Bell Tower line failing at its first differing line. Deviation: the final fact-table digest is deferred to P32-16, because each `run_headless` owns its world; transcripts cover the checked state)
- [x] P32-08 Tavern Heist audit. Audit (method in docs/SEPARATION.md): classify every leak and trap with the rubric, record a findings table in docs/SEPARATION.md, and file each extraction as its own item. No code changes. (completed 2026-11-09; findings in docs/SEPARATION.md, Audit findings)
- [x] P32-09 Spitting Contest audit. Audit (method in docs/SEPARATION.md): classify every leak and trap with the rubric, record a findings table in docs/SEPARATION.md, and file each extraction as its own item. No code changes. (completed 2026-11-09; findings in docs/SEPARATION.md, Audit findings)
- [x] P32-10 GK3 Cat Moustache audit. Audit (method in docs/SEPARATION.md): classify every leak and trap with the rubric, record a findings table in docs/SEPARATION.md, and file each extraction as its own item. No code changes. (completed 2026-11-09; findings in docs/SEPARATION.md, Audit findings)
- [x] P32-11 Insult Sword Fighting audit. Audit (method in docs/SEPARATION.md): classify every leak and trap with the rubric, record a findings table in docs/SEPARATION.md, and file each extraction as its own item. No code changes. Expected finding: `DialogueDuelSystem` as an engine dialogue-duel mechanic. (completed 2026-11-09; findings in docs/SEPARATION.md, Audit findings)
- [x] P32-12 Lochmarne Goat audit. Audit (method in docs/SEPARATION.md): classify every leak and trap with the rubric, record a findings table in docs/SEPARATION.md, and file each extraction as its own item. No code changes. (completed 2026-11-09; findings in docs/SEPARATION.md, Audit findings)
- [x] P32-13 Day of the Tentacle Trio audit. Audit (method in docs/SEPARATION.md): classify every leak and trap with the rubric, record a findings table in docs/SEPARATION.md, and file each extraction as its own item. No code changes. Includes the `"Laverne"` portal rule in `src/spatial.zig`. (completed 2026-11-09; findings in docs/SEPARATION.md, Audit findings)
- [x] P32-14 Middlesex Anomaly audit. Audit (method in docs/SEPARATION.md): classify every leak and trap with the rubric, record a findings table in docs/SEPARATION.md, and file each extraction as its own item. No code changes. Includes whether the `TemporalHypervisor` API is generic once its proof-derived vocabulary is renamed. (completed 2026-11-09; findings in docs/SEPARATION.md, Audit findings)
- [x] P32-15 Bell Tower audit. Audit (method in docs/SEPARATION.md): classify every leak and trap with the rubric, record a findings table in docs/SEPARATION.md, and file each extraction as its own item. No code changes. Includes promoting `SayLog`, `act`, and `tick` to the host kit. (completed 2026-11-09; findings in docs/SEPARATION.md, Audit findings)
- [x] P32-16 Host kit: a `src/` host-support module providing per-tick speech collection, cue-fire-and-tick, initial-statement execution, state queries, and an interactive loop scaffold (history, scrub, rewind, save actions) with proof hooks; migrate every proof onto it. Acceptance: duplicated loop and speech helpers are gone from `proofs/`, and characterization goldens are unchanged. (completed 2026-11-09, D-033; verified via `zig build test` (8/8 steps), all nine goldens (DOTT and Middlesex Anomaly updated in four reviewed lines where dropped script dialogue now appears), every proof headless, and every interactive loop launched offscreen. The fact-table digest deferred from P32-07 remains open)
- [ ] P32-17 Dialogue duel engine mechanic (from the P32-11 audit): extract `DialogueDuelSystem` into `src/` as a data-driven challenge/response duel (pairs, learned replies, opponent tiers, advantage, inquiry fatigue and mood decay) built on fact-guarded dialogue choices, and rewrite `proofs/sword_fighting.zig` as its client. Acceptance: the engine module names no insult or pirate, the sword-fighting golden is unchanged, and a second duel table (e.g. a riddle contest) runs on it.
- [ ] P32-18 Arrival cues (from the P32-12 audit): let scripts react to an actor arriving at a mark (an engine-fired cue or a `when <Actor> arrives at <Mark>:` form, chosen in a decision record), then move the goat proof's host-loop arrival rules into its script. Acceptance: no `get_current_waypoint` arrival checks remain in proof loops, and the goat golden is unchanged.
- [ ] P32-19 Proof hygiene (from the P32-09, P32-10, P32-13, and P32-14 audits): move the spitting contest's placement rule into its script, move look-at fallback text into `LooksAt` handlers, and make outcome checks assert the exact facts each script writes instead of probing alternate spellings. Acceptance: goldens change only where reviewed, and no proof calls `lookup_relation` with two spellings of one fact.
- [ ] P32-20 Unproven engine features (from the cross-cutting audit): `collapse_tangent`, `VectorConduit` / `compute_vector_conduit`, `BitemporalTransceiver`, `CausalDecayTracker`, `DreamFact`, and `reject_belief` have engine unit tests but no proof that exercises them. Needs a maintainer decision per feature: add proof coverage, or mark it experimental in ARCHITECTURE and the manual.
- [ ] P32-21 Neutral hypervisor vocabulary (from the P32-14 audit): rename the `TemporalHypervisor` API and docs from the film's terms (Tangent Universe, Artifact of Metal, the Manipulated Dead, vortex) to mechanic terms. Public API change; needs a maintainer decision and a decision record before work starts.
