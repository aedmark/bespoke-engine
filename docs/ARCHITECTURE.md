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
| Emergent Village Sandbox | `src/village.zig` | `VillageSimulation.init()` | World, Spatial, & VM stores; autonomous physiological drives, witness detection, rumor propagation, and Sheriff arrest cascades (D-021) |
| WebAssembly Browser Target | `src/wasm.zig` | `WasmRuntime.init()` | World, Spatial, & VM stores; `wasm32-freestanding` RGBA8888 software canvas, browser event bridge, and C-ABI exports (D-022) |
| Day of the Tentacle Trio | `src/dott_puzzle.zig` | `run_headless()` / `run_interactive()` | World, Spatial, & VM stores; 3-era parallel puzzle DAG, multi-party item transfer, epistemic dialogue, and time-travel rewind (D-025) |

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
| WebAssembly Framebuffer & Event Bridge | `WasmRuntime` (`src/wasm.zig`) | Browser HTML5 `<canvas>` | Contiguous `640x360x4` RGBA8888 linear-memory byte buffer and C-ABI mouse/keyboard/touch exports (`wasm_init`, `wasm_step_tick`, `wasm_on_pointer_down`) (D-022) |

## Invariants

Rules that hold everywhere across the engine and runtime:

- **The VM is the single source of truth:** Downstream renderers never modify game state directly. Enforced by: display bridge read-only pointer semantics (D-001).
- **Decoupled non-blocking audio peripheral:** Sound synthesis never blocks discrete simulation ticks or alters world state; audio events are consumed asynchronously from a ring buffer by peripheral callbacks or offline test buffers. Enforced by: `AudioBridge` ring buffer and procedural synthesis architecture in `src/audio.zig` (D-001, D-019).
- **Pointerless relational facts:** All facts are flat integer tuples `(subject, relation, object_or_value, expires_at_tick)`. Enforced by: `Fact` struct definition in `src/world.zig` (D-003, D-007).
- **Deterministic save/restore:** The entire active game state resides in a contiguous arena such that saving or restoring is a pure memory copy without pointer swizzling. Enforced by: arena allocator layout in `src/world.zig` (D-003).
- **Reversible interruption:** An interrupt block must push the fiber's program counter and local registers to the entity's interrupt stack and restore them when the condition clears. Enforced by: interrupt frame management in `src/vm.zig` (D-004).
- **Continuous global facts across scenes:** Scene transitions (`transition to scene: TargetScene`, D-014) swap active spatial waypoints, pause/wake ambient scene routines, and switch visual backdrops, but all relational world facts persist continuously across scene boundaries. Enforced by: `World` remaining the singular simulation spine across scene transitions in `src/vm.zig` (D-001, D-014).
- **Centralized floating label collision resolution:** All in-world floating text labels (actor names, status badges, waypoint names, and hotspot prompts) resolve through a deterministic 2D collision solver (`TextLayoutResolver`) prior to rasterization, ensuring zero overlapping text labels across actors, waypoints, and props regardless of camera framing or entity clustering. Enforced by: `TextLayoutResolver` in `src/display/text_layout.zig` and integration pass in `DisplayWindow.render_frame` (D-024).
- **Conservation of matter in item transfers:** Item transfer between party actors (`World.transfer_item`, D-025) is an atomic relational mutation forgetting prior possession facts before asserting new possession facts, guaranteeing zero item duplication across actors or scene partitions. Enforced by: `World.transfer_item` in `src/world.zig` and `SpatialSystem.can_transfer_item` in `src/spatial.zig` (D-025).
- **Unidirectional DAG temporal causality:** Time-travel causality cascades strictly forward along a Directed Acyclic Graph (Past -> Present -> Future). Past physical state mutations trigger deterministic reactive interrupts across subsequent eras without retrocausal paradox loops. Enforced by: forward topological ordering and reactive rules in `src/vm.zig` and `src/dott_puzzle.zig` (D-025).
- **Epistemic belief dialogue guards:** Persuasive or contextual dialogue choices evaluate dynamic NPC belief states (`Believes`, `Knows`, `Rejects`) where negative rejection facts strictly supersede unverified claims until physical evidence facts are remembered. Enforced by: `VM.evaluates_belief` in `src/vm.zig` (D-015, D-017, D-025).
- **Spatial locality vs. relational causality:** Spatial topologies (rooms, waypoints, geometry) are scene-local; causality is relational. Different time periods or parallel spaces never force geometric coordinate overlays; cross-era state synchronization occurs purely through flat relational facts and reactive rule cascades. Enforced by: independent `SpatialGraph` room meshes in `src/spatial.zig` synchronized through global facts in `src/world.zig` (D-001, D-003, D-026).
- **Portal-anchored inventory transfer policy:** Multi-character party transfers under `.portal_anchored` policy operate as an anti-backtracking UI abstraction that succeeds from anywhere *if and only if* both characters possess unblocked relational access to operational transit portals in their respective scenes. Enforced by: `SpatialSystem.can_transfer_item_with_world` in `src/spatial.zig` (D-025, D-026).
- **Asymmetric downstream feedback (Mutations vs. Continuations):** Structural physical mutations in the past that alter downstream reality telegraph their consequences via reactive interrupt cutscenes (`when` interrupts); temporal continuations (container incubation over time) are discovered organically through player inspection in downstream eras without narrative interruption. Enforced by: edge-triggered VM reactive interrupts vs. passive relational fact queries in `src/vm.zig` and `src/dott_puzzle.zig` (D-010, D-025, D-026).

### Visual Standoff & Actor Separation

To prevent visual clutter and overlapping text in crowded scenes:
1. **Actor Physical Standoff (`get_entity_screen_layout`):** Entities sharing identical or near-identical world coordinates (within a 32px Euclidean radius) are automatically dispersed horizontally by ±30px in screen space.
2. **Text Collision Avoidance (`TextLayoutResolver`, D-024):** All floating labels are submitted with anchor coordinates, preferred offsets, font scales, categories, and priority tiers (`hover_tooltip = 10` down to `backdrop_prop = 1`). Living actor tokens and waypoint anchors register as rectangular obstacles.
3. **Visual Hierarchy:** Actor names use font scale 2 (12px character width) placed above tokens; actor status badges use font scale 1 (6px character width) placed below tokens. In contested spaces, status badges stagger downward across vertical tiers (Tiers 1-3) or flip above, while idle waypoint names yield to preserve legibility without hiding the physical ground anchor. Hover tooltips always take highest priority.

## Boundaries

| Boundary | Comes in as | Checked by | Rule |
| --- | --- | --- | --- |
| DSL Source Script | UTF-8 text file | Compiler lexer & parser | Reject malformed grammar, undefined relations, or invalid entity declarations |
| Bytecode Package File (.bspk) | Binary container on disk | Package loader (`src/package.zig`) | Check magic bytes (`BSPB`), version (`1`), payload CRC32 checksum, element counts, and slice bounds before loading into World/VM |
| External Input / Cues | Hardware event / input packet | Display bridge & cue validator | Validate cue arguments against known entity IDs before dispatching to VM queue |
| State Snapshot Save File | Binary blob on disk | Snapshot loader | Check header magic bytes, version number, and arena checksum before `memcpy` |

## Dependencies

Everything the engine needs that it did not write in-tree. Core compiler, simulation spine, and WebAssembly target require zero external dependencies beyond the Zig compiler and Python standard library.

| Dependency | Version | For | Why this one (and not writing it) |
| --- | --- | --- | --- |
| Zig Toolchain | 0.13.0+ | Runtime, compiler, tests, and WebAssembly build | Native memory arena control, comptime, zero-overhead C-ABI, and freestanding cross-compilation (D-002, D-022) |
| Python 3 Standard Library | 3.9+ | Documentation linter (`tools/check_docs.py`) and manual tool (`tools/manual.py`) | Zero external pip dependencies; portable cross-platform repository memory enforcement |
| SDL2 (libSDL2) | 2.0+ (system C library) | Host peripheral display window, keyboard/mouse input, and audio callback | Peripheral rendering on desktop Linux; optional/peripheral only, with graceful headless fallback (D-001, D-008, D-019) |

## State and caches

Everything a run leaves on disk or elsewhere, and what may delete it.

| What | Where | Written by | Reset by | Committed? |
| --- | --- | --- | --- | --- |
| Binary Save Slots | `saves/slot_*.sav` | Save manager (`src/save.zig`) | User save slot deletion or overwrite | No, gitignored |
| Save Backup Files | `saves/slot_*.sav.bak` | Save manager before slot overwriting | Automatic repair or manual cleanup | No, gitignored |
| Quick-Save State | `saves/quicksave.sav` | In-engine quick-save (`[F5]`) | Quick-save overwrite | No, gitignored |
| Zig Build Cache | `.zig-cache/`, `zig-cache/` | `zig build`, `zig test` | `rm -rf zig-cache` | No, gitignored |
| Compiled Artifacts | `zig-out/` | `zig build`, `zig build wasm` | `rm -rf zig-out` | No, gitignored |

## Failure modes and observability

| Failure | User-visible behaviour | Detection | Recovery / runbook |
| --- | --- | --- | --- |
| Script Syntax or Type Error | Compiler error report with line and column printed to `stderr`; non-zero exit | `Diagnostic` check during parsing (`bespoke check` / `compile`) | Correct script source at indicated line/col |
| Corrupted or Truncated `.sav` File | Load failure badge in pause drawer; automatic fallback to backup | Magic (`BSAV`), version, or CRC32 checksum mismatch in `SaveManager.load_slot` | Transparently falls back to `<slot>.sav.bak` and restores valid state (D-020) |
| Missing Host Audio / Display Hardware | Silent warning; continues running in pure headless simulation | SDL init check failure (`SDL_Init`, `SDL_CreateWindow`, `SDL_OpenAudio`) | Falls back to deterministic headless simulation and offline audio buffers (D-001, D-019) |
| WebAssembly Framebuffer Out-of-Bounds | Drawing coordinate clamped | `WasmCanvas.set_pixel` bounds check (`x < 640`, `y < 360`) | Clamps coordinates silently to prevent buffer overruns (D-022) |

State what may be logged and what must be redacted. Security consequences and reporting belong in [SECURITY.md](SECURITY.md).

## Claims vs. code

Places where a doc, a name or a comment says more than the code does, so nobody builds on the claim. When a session encounters friction where the code contradicts a documented claim (or vice versa), record the mismatch here and ask the maintainer rather than papering over the discrepancy in code. Remove a row when the code catches up or the claim is corrected.

- *(None currently. All 19 roadmap phases and verified claims match the executable Zig codebase.)*
