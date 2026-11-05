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

Goal: Connect a native 2D display window (e.g. via Sokol or Raylib) as a downstream consumer of the `DisplayBridge`, rendering waypoint topology, actor positions, and handling point-and-click mouse input.

- [ ] P6-01 Window and rendering loop consumer that opens a native display window and polls `DisplayBridge.poll()` at 60 Hz. (D-001)
- [ ] P6-02 2D scene visualization: render room boundaries, waypoint nodes, edge corridors, and actor tokens/sprites with orientations. (D-001, D-005)
- [ ] P6-03 Point-and-click mouse input handling: map clicks on waypoints to simulation motor intents (`walk_to`) or player interaction cues. (D-001, D-005)
- [ ] P6-04 Visual cue HUD and event banner: display floating on-screen cue notifications, dialogue balloons, and simulation clock state. (D-001)

## Phase 7: Adventure Game Primitives (Verbs, Inventory, Dialog & Hotspots)

Goal: Expand the BeSpoke language syntax and runtime with first-class point-and-click adventure game constructs.

- [ ] P7-01 Hotspots and inspectable scene objects: static interactable regions with examine text, hover cursors, and condition-guarded interaction cues. (D-001)
- [ ] P7-02 Classic adventure verbs: grammar and bytecode support for `LookAt`, `PickUp`, `UseWith`, `TalkTo`, and contextual verb interactions. (D-002)
- [ ] P7-03 Relational inventory system: first-class inventory state (`InInventory(Player, Item)`), inventory combining, and inventory bar UI. (D-003, D-007)
- [ ] P7-04 Branching dialogue & speech: `say Actor: "text"` primitive with temporal speech balloon suspension, click-to-dismiss, and dialogue choice trees. (D-002, D-004)

## Phase 8: Reactive Simulation Rules (`when` Engine in VM)

Goal: Implement continuous pattern-matching rule triggers in the engine spine so complex world conditions react without manual polling.

- [ ] P8-01 Multi-clause relational pattern matcher: support relational conjunctions (`where A and B and C`) and join queries across active facts. (D-003, D-006, D-007)
- [ ] P8-02 VM reactive `when` evaluation engine: evaluate `when <condition>:` rules on fact mutation or tick boundary and automatically trigger fiber interrupts. (D-002, D-004)
- [ ] P8-03 Systemic AI behaviors: priority rule cascades for NPC moods, systemic theft, guards chasing thieves, and alert states. (D-003, D-004)

## Phase 9: Interactive Time-Travel Debugger & REPL

Goal: Build an interactive developer dashboard and time-travel timeline scrubber for inspecting and manipulating simulation state live.

- [ ] P9-01 In-engine debug overlay / HUD: live inspector displaying active relational facts, active fibers, call stacks, and spatial coordinates. (D-001)
- [ ] P9-02 Interactive time-travel timeline scrubber: pause, step forward, and scrub backward across historical snapshot states with instantaneous live visual replay. (D-001, D-003)
- [ ] P9-03 Live interactive REPL / console: inject facts (`remember ...`), emit cues (`PlayLute`), and test scripts in a running simulation. (D-001, D-002)
