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
