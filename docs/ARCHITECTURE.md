# Architecture

How the BeSpoke Engine fits together. This document maps the core components, data flow, invariants, and boundaries. Rationale and alternatives live in [DECISIONS.md](DECISIONS.md).

## The Shape, in One Paragraph

The BeSpoke Engine inverts traditional game engine architecture into an **Engine-as-Spine** model (D-001). The Zig runtime is `main()`, owning the master simulation clock, entity IDs, contiguous relational fact tables (`MultiArrayList(Fact)`), and cooperative fiber scheduler. Game scripts written in the BeSpoke domain-specific language are compiled by a hand-written Zig front-end directly into compact custom bytecode (D-002). Downstream graphics and audio (e.g. Raylib or Sokol) act as stateless peripheral consumers that read a double-buffered snapshot of the simulation state each frame.

## Code Map

| Area | Where | Entry point | Talks to |
| --- | --- | --- | --- |
| Relational Store | `src/world.zig` | `World.init()` | Memory allocator; stores entities and facts (D-003) |
| Fiber VM & Scheduler | `src/vm.zig` | `VM.step_tick()` | Relational store; dispatches bytecode routines (D-004) |
| Spatial Topology | `src/spatial.zig` | `SpatialGraph.init()` | World store; resolves waypoints, line-of-sight, pathfinding |
| Compiler Front-End | `src/compiler/` | `compile_source()` | Lexer, parser, bytecode emitter; outputs VM bytecode |
| Display Bridge | `src/display.zig` | `DisplayBridge.poll()` | External multimedia frontend (Raylib/Sokol); read-only |
| Audio Subsystem & Synth | `src/audio.zig` | `AudioBridge.init()` | Display bridge & SDL2 audio callback; procedural chiptune SFX and scene music (D-019) |
| Persistent Save Storage | `src/save.zig` | `SaveManager.init()` | World, Spatial, & VM stores; CRC32-checksummed `.sav` slots, thumbnails, and `.bak` recovery (D-020) |

## Memory Layout & Core Structs (Zig)

Relational facts are stored using Zig's native `std.MultiArrayList` for optimal CPU cache utilization (Structure-of-Arrays layout):

```zig
const std = @import("std");

pub const EntityId = enum(u32) {
    none = 0,
    _,
};

pub const RelationKind = enum(u16) {
    _,
};

pub const Fact = struct {
    subject: EntityId,
    relation: RelationKind,
    object_or_value: u32, // EntityId or immediate scalar value (D-007)
    expires_at_tick: u64, // 0 = permanent
};

pub const World = struct {
    facts: std.MultiArrayList(Fact),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) World {
        return .{
            .facts = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *World) void {
        self.facts.deinit(self.allocator);
    }
};
```

## Interfaces and Data Flow

```text
BeSpoke Source Script -> Lexer -> Parser -> AST -> Bytecode Emitter -> VM Bytecode
                                                                           |
World Ticks (Discrete Clock) --------------------------------------------->|
                                                                           v
[Relational Fact Database (SoA)] <-> [Fiber Scheduler / Interrupt Stack] <-> [Spatial Graph]
                                     |
                                     v
                 [Double-Buffered Render State & Cue Bus]
                                     |
                                     v
                       [Stateless Peripheral: Raylib / Sokol]
```

| Interface | Producer | Consumer | Contract / compatibility |
| --- | --- | --- | --- |
| Bytecode binary | Compiler | Virtual Machine | Compact opcode stream with opcode table and constant pool |
| Bytecode package (.bspk) | Asset Compiler (`src/package.zig`) | Runner / Asset Loader | Standalone CRC32-checksummed binary container (`BSPB`) with symbol tables, waypoints, and bytecode |
| State snapshot | World Store | Disk / Memory Buffer | Flat contiguous memory arena; restorable via `memcpy` |
| Persistent Save File (.sav) | Save Manager (`src/save.zig`) | Save / Slot Loader | CRC32-checksummed binary save (`BSAV`) with metadata header, 16x12 RGB332 thumbnail, World/Spatial/VM state, and `.bak` recovery (D-020) |
| Render state slice | VM / World Store | Display Peripheral | Read-only double-buffered struct containing active entity positions, facing, and visual cues |
| External cues | Input / Peripheral | VM Cue Dispatcher | Named cue events (e.g. `PlayLute(Bard, Target)`) queued for next tick |
| Audio cue stream | Simulation spine / GUI | AudioBridge / Synth | Decoupled thread-safe event queue synthesizing procedural action SFX and BGM (D-019) |

## Invariants

Rules that hold everywhere across the engine and runtime:

- **The VM is the single source of truth:** Downstream renderers never modify game state directly. Enforced by: display bridge read-only pointer semantics (D-001).
- **Decoupled non-blocking audio peripheral:** Sound synthesis never blocks discrete simulation ticks or alters world state; audio events are consumed asynchronously from a ring buffer by peripheral callbacks or offline test buffers. Enforced by: `AudioBridge` ring buffer and procedural synthesis architecture in `src/audio.zig` (D-001, D-019).
- **Pointerless relational facts:** All facts are flat integer tuples `(subject, relation, object_or_value, expires_at_tick)`. Enforced by: `Fact` struct definition in `src/world.zig` (D-003, D-007).
- **Deterministic save/restore:** The entire active game state resides in a contiguous arena such that saving or restoring is a pure memory copy without pointer swizzling. Enforced by: arena allocator layout in `src/world.zig` (D-003).
- **Reversible interruption:** An interrupt block must push the fiber's program counter and local registers to the entity's interrupt stack and restore them when the condition clears. Enforced by: interrupt frame management in `src/vm.zig` (D-004).
- **Continuous global facts across scenes:** Scene transitions (`transition to scene: TargetScene`, D-014) swap active spatial waypoints, pause/wake ambient scene routines, and switch visual backdrops, but all relational world facts persist continuously across scene boundaries. Enforced by: `World` remaining the singular simulation spine across scene transitions in `src/vm.zig` (D-001, D-014).

## Boundaries

| Boundary | Comes in as | Checked by | Rule |
| --- | --- | --- | --- |
| DSL Source Script | UTF-8 text file | Compiler lexer & parser | Reject malformed grammar, undefined relations, or invalid entity declarations |
| Bytecode Package File (.bspk) | Binary container on disk | Package loader (`src/package.zig`) | Check magic bytes (`BSPB`), version (`1`), payload CRC32 checksum, element counts, and slice bounds before loading into World/VM |
| External Input / Cues | Hardware event / input packet | Display bridge & cue validator | Validate cue arguments against known entity IDs before dispatching to VM queue |
| State Snapshot Save File | Binary blob on disk | Snapshot loader | Check header magic bytes, version number, and arena checksum before `memcpy` |
