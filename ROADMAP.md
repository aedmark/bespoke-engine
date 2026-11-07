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

## Phase 14: The Gabriel Knight 3 Cat Moustache Scenario

Goal: Implement the complete *Gabriel Knight 3* Rennes-le-Château Cat Moustache vertical slice in `src/gk3_moustache.zig`, runnable via `--gk3`.

- [x] P14-01 Full GK3 puzzle script implementation in BeSpoke DSL: Mosely room break-in, fence hole taping, cat water squirting, syrup lip adhesive, cat moustache crafting, and Buthane rental shop validation. (D-001, D-012, D-013, D-015, D-016; completed 2026-11-06, verified via `zig test -lc -lSDL2 src/root.zig` and `zig build run -- --gk3 --headless`)
- [x] P14-02 Visual renderer backdrop for Rennes-le-Château (hotel corridor, garden fence, bike rental desk) and custom actor tokens (Gabriel in trench coat, Mosely, Buthane, Stray Cat). (D-008, D-009, D-012, D-014, D-016; completed 2026-11-06, verified via `zig test -lc -lSDL2 src/display.zig` and `zig build test`)
- [x] P14-03 CLI option `--gk3` / `--cat-moustache` with end-to-end headless simulation verification and interactive 60 Hz playability with time-travel rewind. (D-001, D-008, D-011, D-016; completed 2026-11-06, verified via `zig build run -- --gk3 --headless` and `zig build test`)

## Phase 15: Standalone Script File Execution & Compiler CLI

Goal: Support executing external `.bespoke` scenario files directly from disk via CLI, with script file parsing, syntax verification, and optional bytecode binary compilation.

- [ ] P15-01 CLI script runner (`bespoke run <script.bespoke>`) parsing and compiling external text files from the host filesystem in both headless and GUI modes. (D-001, D-002)
- [ ] P15-02 Bytecode binary emission and standalone asset loader (`bespoke compile <script.bespoke> -o game.bspk`), serializing and deserializing compiled bytecode chunks with versioning and validation. (D-002)
- [ ] P15-03 Script diagnostics and validation tooling (`bespoke check <script.bespoke>`) with file, line, and column error reporting. (D-002)

## Phase 16: Peripheral Audio Subsystem & Procedural Sound Synthesizer

Goal: Connect an SDL2 audio peripheral callback to the `DisplayBridge` cue stream, synthesizing procedural chiptune sound effects and background musical melodies triggered by simulation cues.

- [ ] P16-01 Audio bridge buffer and peripheral audio consumer in `src/display.zig` consuming audio cue events decoupled from simulation ticks. (D-001)
- [ ] P16-02 Procedural square-wave and noise sound synthesizer in pure Zig (zero audio asset dependencies) for action SFX (footsteps, pickups, splashes, alert stingers). (D-001)
- [ ] P16-03 Scene background musical accompaniment with track switching triggered on scene transitions and narrative dramatic shifts. (D-001, D-014)

## Phase 17: Persistent Save/Load Disk Storage & Slot Management

Goal: Extend memory snapshot serialization to disk files, providing durable save/load slot management with metadata headers and in-engine UI.

- [ ] P17-01 File-backed save state format (`.sav`) with versioning, CRC32 integrity checksums, and metadata headers (playtime, tick, scene, thumbnail/frame snapshot). (D-001, D-003)
- [ ] P17-02 Slot management API supporting numbered save slots, quick-save, quick-load, and corrupted save recovery. (D-003)
- [ ] P17-03 In-engine save/load drawer and pause menu overlay integrated into the SDL2 renderer. (D-008, D-011)

## Phase 18: Systemic Emergent Simulation Sandbox ("The Living Village")

Goal: Implement a multi-agent systemic emergent simulation sandbox in `src/village.zig` demonstrating dozens of autonomous NPCs driven by relational needs, social memory, property ownership, and emergent justice cascades.

- [ ] P18-01 Village relational schema and autonomous NPC drive system: physiological needs (Hunger, Energy), emotional states, and social relationships (Friend, Rival, Trust) updated via continuous relational rules. (D-003, D-007, D-010)
- [ ] P18-02 Emergence engine: systemic crime, witness detection, rumor propagation, property theft, and autonomous sheriff investigation/arrest cascades. (D-004, D-010)
- [ ] P18-03 Village spatial topology and settlement visualization: multi-building settlement (bakery, tavern, houses, sheriff's post, farm, town square) with live social graph HUD and event chronicle. (D-005, D-008, D-011)

## Phase 19: WebAssembly & HTML5 Canvas Browser Target

Goal: Compile BeSpoke Engine to WebAssembly using Zig's cross-compilation toolchain, rendering to an HTML5 canvas and embedding interactive simulations directly into the 3x documentation.

- [ ] P19-01 Zig build target and runtime harness for `wasm32-freestanding` or Emscripten with WebGL/Canvas rendering. (D-001)
- [ ] P19-02 Browser event bridge mapping mouse, keyboard, and touch events to BeSpoke motor and dialogue intents. (D-008)
- [ ] P19-03 Interactive embedded manual simulator hosting live BeSpoke vertical slices inside `docs/manual.html`. (D-001, D-011)

