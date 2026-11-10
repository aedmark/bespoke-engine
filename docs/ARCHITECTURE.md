# Architecture

How the BeSpoke Engine fits together. This document maps the core components, data flow, invariants, and boundaries. Rationale and alternatives live in [DECISIONS.md](DECISIONS.md).

## The Shape, in One Paragraph

The BeSpoke Engine inverts traditional game engine architecture into an **Engine-as-Spine** model (D-001). The Zig runtime is `main()`, owning the master simulation clock, entity IDs, contiguous relational fact tables (`MultiArrayList(Fact)`), and cooperative fiber scheduler. Game scripts written in the BeSpoke domain-specific language are compiled by a hand-written Zig front-end directly into compact custom bytecode (D-002). Downstream graphics and audio (e.g. Raylib or Sokol) act as stateless peripheral consumers that read a double-buffered snapshot of the simulation state each frame.

## Code Map

The engine lives in `src/` and is exported as the `bespoke` module. Proofs of concept live in `proofs/`, import only `bespoke`, and build as the separate `bespoke-proofs` binary (D-031). Rows below with a `proofs/` path are proofs, not engine components.

| Area | Where | Entry point | Talks to |
| --- | --- | --- | --- |
| Host Kit | `src/host.zig` | `host.tick()`, `host.Session` | VM, World, display bridge, window; shared tick/dispatch, speech, timeline, and interactive loop scaffold for any host (D-033) |
| Proofs Launcher | `proofs/main.zig` | `bespoke-proofs --<proof>` | Every proof module; the engine through `@import("bespoke")` |
| The Tavern Heist | `proofs/tavern_heist.zig` | `run()` | World, Spatial, VM, display; the original Engine-as-Spine slice |
| Relational Store | `src/world.zig` | `World.init()` | Memory allocator; stores entities and facts (D-003) |
| Fiber VM & Scheduler | `src/vm.zig` | `VM.step_tick()` | Relational store; dispatches bytecode routines (D-004) |
| Spatial Topology | `src/spatial.zig` | `SpatialGraph.init()` | World store; resolves waypoints, line-of-sight, pathfinding |
| Compiler Front-End | `src/compiler/` | `compile_source()` | Lexer, parser, bytecode emitter; outputs VM bytecode |
| Display Bridge | `src/display.zig` | `DisplayBridge.poll()` | External multimedia frontend (Raylib/Sokol); read-only |
| Audio Subsystem & Synth | `src/audio.zig` | `AudioBridge.init()` | Display bridge & SDL2 audio callback; procedural chiptune SFX and scene music (D-019) |
| Persistent Save Storage | `src/save.zig` | `SaveManager.init()` | World, Spatial, & VM stores; CRC32-checksummed `.sav` slots, thumbnails, and `.bak` recovery (D-020) |
| Emergent Society | `src/society.zig` | `Society.init(world, config)` / `Society.step()` | World, Spatial, & VM stores; data-driven needs, roles, and routines; witness detection, rumor propagation, and justice cascades over facts (D-032, D-034) |
| Dialogue Duel & Inquiry Fatigue | `src/duel.zig` | `Duel.init(world, config)` / `Duel.resolve_round()` / `InquiryFatigue.record()` | World and VM; data-driven challenge/reply pairs, opponent tiers, advantage, and staged mood decay, offered through `VM.prune_dialogue_choices` (D-017, D-035) |
| The Living Village | `proofs/village.zig` | `run_headless()` / `run_interactive()` | Society client: six villagers, settlement map, catalysts (D-021) |
| WebAssembly Browser Target | `src/wasm.zig` | `WasmRuntime.init()` | World, Spatial, & VM stores; `wasm32-freestanding` RGBA8888 software canvas, browser event bridge, and C-ABI exports (D-022) |
| Musical Drafts | `src/draft.zig` | `VM.weave_notes()` / `VM.dispatch_pending_weaves()` / `DistaffInput.press()` | Compiler (draft table), VM (`weave` opcode, `Weave` cue handlers), package loader, display bridge (`RenderFrame.distaff` staff HUD), audio (`AudioEvent.play_note`); pitch-based spellcraft (D-029, D-030) |
| The Bell Tower | `proofs/loom_puzzle.zig` | `run_headless()` / `run_interactive()` | World, Spatial, VM, and display bridge; musical draft slice with distaff reach, reversed-draft puzzle, and host re-dispatch (D-029, D-030) |
| Day of the Tentacle Trio | `proofs/dott_puzzle.zig` | `run_headless()` / `run_interactive()` | World, Spatial, & VM stores; 3-era parallel puzzle DAG, multi-party item transfer, epistemic dialogue, and time-travel rewind (D-025) |

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
- **Unidirectional DAG temporal causality:** Time-travel causality cascades strictly forward along a Directed Acyclic Graph (Past -> Present -> Future). Past physical state mutations trigger deterministic reactive interrupts across subsequent eras without retrocausal paradox loops. Enforced by: forward topological ordering and reactive rules in `src/vm.zig` and `proofs/dott_puzzle.zig` (D-025).
- **Epistemic belief dialogue guards:** Persuasive or contextual dialogue choices evaluate dynamic NPC belief states (`Believes`, `Knows`, `Rejects`) where negative rejection facts strictly supersede unverified claims until physical evidence facts are remembered. Enforced by: `VM.evaluates_belief` in `src/vm.zig` (D-015, D-017, D-025).
- **Spatial locality vs. relational causality:** Spatial topologies (rooms, waypoints, geometry) are scene-local; causality is relational. Different time periods or parallel spaces never force geometric coordinate overlays; cross-era state synchronization occurs purely through flat relational facts and reactive rule cascades. Enforced by: independent `SpatialGraph` room meshes in `src/spatial.zig` synchronized through global facts in `src/world.zig` (D-001, D-003, D-026).
- **Portal-anchored inventory transfer policy:** Multi-character party transfers under `.portal_anchored` policy operate as an anti-backtracking UI abstraction that succeeds *if and only if* both sender and recipient can physically access their respective Chron-o-John portals (`SpatialSystem.can_access_portal`). Physical accessibility is implied for unblocked actors (Bernard in 1993 Motel, Hoagie in 1790 Workshop); obstructed actors (Laverne in 2193) can only reach the portal once freed from obstacles (`not Trapped`) *and* granted yard access (`DoingBusiness` / `InYard`) or wearing the disguise (`TentacleDisguiseActive`). Enforced by: `SpatialSystem.can_access_portal` and `can_transfer_item_with_world` in `src/spatial.zig` (D-025, D-026).
- **Temporal Hypervisors and Mass Conservation (`TemporalHypervisor`, D-027):** Tangent Universe branching is an ephemeral copy-on-write fork (`World.clone`). The duplicated Artifact of Metal violates mass conservation until returned to the designated vortex threshold waypoint before countdown expiration (`collapse_budget_ticks`). If the countdown expires before loop closure, the universe collapses into a terminal gravitational singularity (`singularity_collapsed = true`). If loop closure invariants are satisfied, the Tangent Universe merges cleanly, the Artifact is committed to the Primary Universe at $T_0$, and dream residue memories are transferred to the Living Receiver. Enforced by: `TemporalHypervisor` in `src/hypervisor.zig`, `World.clone` in `src/world.zig`, and `proofs/darko_puzzle.zig` (D-027).
- **Pre-Cognitive Vector Conduits & Novikov Consistency (`VectorConduit`, `validate_novikov_consistency`, D-027):** Fourth-Dimensional vector conduits project ahead-of-time deterministic A* path trajectories directly from actor origin coordinates to goal waypoints, rendered as translucent fluid tendrils with energy cores. Paradoxical actions that would contradict established timeline facts are validated through Novikov self-consistency checking, ensuring deterministic loop stability without retrocausal contradictions. Enforced by: `VectorConduit`, `compute_vector_conduit`, and `validate_novikov_consistency` in `src/spatial.zig` and `DisplayWindow.render_frame` in `src/display/renderer.zig` (D-027).
- **Asymmetric downstream feedback (Mutations vs. Continuations):** Structural physical mutations in the past that alter downstream reality telegraph their consequences via reactive interrupt cutscenes (`when` interrupts); temporal continuations (container incubation over time) are discovered organically through player inspection in downstream eras without narrative interruption. Enforced by: edge-triggered VM reactive interrupts vs. passive relational fact queries in `src/vm.zig` and `proofs/dott_puzzle.zig` (D-010, D-025, D-026).
- **Unambiguous musical drafts and dispatched weaves (D-029):** A played four-note sequence names at most one draft, forward or reversed, and weaves dispatch only through exact `Weave:caster:draft[:target]` handler keys. In-script weaves wait in `VM.pending_weaves` until the host calls `dispatch_pending_weaves` after `step_tick`. A half-played distaff phrase is host-side input state (`DistaffInput`, D-030) and never enters the world arena. Enforced by: parser draft validation in `src/compiler/parser.zig`, `CompiledProgram.find_weave_handler`, and the `PendingWeavesNotDispatched` save refusal in `src/save.zig`.
- **Society state is facts (D-034):** `Society` holds only configuration and relation ids; every need, activity, stay, crime, rumor, warrant, and arrest is a World fact, so snapshots and saves capture the whole society. Enforced by: `Society` field list in `src/society.zig` and the snapshot-restore test there.
- **Arrival is an edge, fired inside the tick (D-036):** a `when <Actor> arrives at <Mark>:` rule fires once per completed walk at that mark, in the tick the walk completes, and never for resting, passing through, or being placed. Enforced by: `MotorAgent.arrival_pending`, the arrival pass and `clear_arrivals` call in `VM.evaluate_reactive_rules`, and the P32-18 tests in `src/compiler.zig`.
- **Duel and fatigue state is facts (D-035):** `Duel` and `InquiryFatigue` hold only borrowed configuration and interned ids; what a fighter has heard and mastered, tiers, advantage, wins, inquiry counts, and moods are World facts, and duel lines reach the player only through `VM.prune_dialogue_choices`. Enforced by: the struct field lists in `src/duel.zig` and the snapshot-restore test there.
- **One time-travel model for interactive hosts (D-033):** scrubbing restores a snapshot without discarding the future; advancing from a past point discards it. Hosts tick through `host.tick` (or `Session.advance`) so in-script weaves are re-dispatched, and read speech after each tick. Enforced by: `host.Timeline` and `host.Session` tests in `src/host.zig`, and the proof goldens.
- **Centralized Master Simulation Clock & Decoupled Pacing:** Simulation clock ticks advance at a deliberate canonical base rate (`DEFAULT_TICK_INTERVAL_MS = 1000` ms / 1.0 Hz) defined in `src/vm.zig`, strictly decoupled from peripheral 60 Hz display rendering. Interactive runners evaluate clock progression against `DisplayWindow.current_tick_interval_ms`, bounded between 100ms (10 Hz fast-forward) and 3000ms (0.33 Hz slow-motion) with runtime scaling via `[-]`/`[+]` hotkeys, preserving deterministic discrete integer ticks without floating-point delta accumulation. Enforced by: `DEFAULT_TICK_INTERVAL_MS` in `src/vm.zig`, `DisplayWindow.current_tick_interval_ms` in `src/display/renderer.zig`, and runner loops across `src/main.zig`, `proofs/dott_puzzle.zig`, `proofs/darko_puzzle.zig`, `proofs/goat_puzzle.zig`, `proofs/gk3_moustache.zig`, `proofs/spitting_contest.zig`, `src/runner.zig`, and `proofs/village.zig` (D-001, D-028).

### Visual Standoff & Actor Separation

To prevent visual clutter and overlapping text in crowded scenes:
1. **Actor Physical Standoff (`get_entity_screen_layout`):** Entities sharing identical or near-identical world coordinates (within a 32px Euclidean radius) are automatically dispersed horizontally by ±30px in screen space.
2. **Text Collision Avoidance (`TextLayoutResolver`, D-024):** All floating labels are submitted with anchor coordinates, preferred offsets, font scales, categories, and priority tiers (`hover_tooltip = 10` down to `backdrop_prop = 1`). Living actor tokens and waypoint anchors register as rectangular obstacles.
3. **Visual Hierarchy:** Actor names use font scale 2 (12px character width) placed above tokens; actor status badges use font scale 1 (6px character width) placed below tokens. In contested spaces, status badges stagger downward across vertical tiers (Tiers 1-3) or flip above, while idle waypoint names yield to preserve legibility without hiding the physical ground anchor. Hover tooltips always take highest priority.

## Boundaries

| Boundary | Comes in as | Checked by | Rule |
| --- | --- | --- | --- |
| Engine / proofs (D-031) | `@import` | Zig module paths: `src/` code cannot import a file under `proofs/` ("import of file outside module path") | Proofs depend on the engine; the engine never depends on a proof. Scenario knowledge still inside engine files is debt tracked by P32-02 to P32-04 |
| DSL Source Script | UTF-8 text file | Compiler lexer & parser | Reject malformed grammar, undefined relations, or invalid entity declarations |
| Bytecode Package File (.bspk) | Binary container on disk | Package loader (`src/package.zig`) | Check magic bytes (`BSPB`), version (`1` to `3`), payload CRC32 checksum, element counts, slice bounds, draft note range (0 to 6), and draft entity ids, and that the arrival edge appears only in version 3, before loading into World/VM |
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

- **Engine files still carry proof content** (observed 2026-11-08, session 28). After the D-031 move, `src/` no longer imports any proof, but it still names proof entities and art: `RenderFrame` scenario status flags and their capture by entity name in `src/display.zig`, scenario themes, backdrops, props, actor tokens, footer hints, and keys in `src/display/renderer.zig`, scenario music tracks, SFX, and scene-name mapping in `src/audio.zig`, scene-name thumbnail palettes in `src/save.zig`, embedded scenario decks in `src/wasm.zig`, and a hardcoded `"Laverne"` and `TentacleDisguiseActive` rule in `SpatialSystem.can_access_portal` (`src/spatial.zig`). Tracked by P32-02 to P32-04.
- **Cue handler `where` guards are parsed but not evaluated** (observed 2026-11-08, session 28). `script_spec.md` shows `on cue Steal(Cat, victim) where CharmedBy(victim, _) and Carries(victim, loot):`, and the parser stores `CueHandler.where_patterns`, but `Codegen.compile` compiles only the handler body and `VM.fire_cue` spawns it unconditionally. Only dialogue choices evaluate `where` patterns (`VM.prune_dialogue_choices`). Weave handlers (D-029) express affordances with `if` checks instead. Fixing this changes behaviour of every existing script that relies on the guard text; ask the maintainer before changing it.
- **`walk_to` back to the waypoint just left does not turn the agent around** (observed 2026-11-09, session 29). `SpatialSystem.walk_to` returns early when `current_wp == dest` and sets `arrived`, but an agent between waypoints still has `current_wp` set to the last one it reached: its old path keeps running and it ends at the old destination. Arrival rules do not fire in this case (D-036). Turning the agent around changes the village golden at line 20, so the fix needs its own reviewed change (P32-25).
- **An unmatched cue runs the first handler with that cue name** (observed 2026-11-09, session 29). Codegen registers each cue name's first handler under the bare name as a "fallback key", and `CompiledProgram.find_cue_handler` falls back to it after the exact, actor-only, and commutative signatures. `fire_cue("Uses", George, TetherStake)` therefore runs `Uses(George, CellarEntrance)`. The Zig look-at tables in two proofs were unreachable for this reason. Proofs now declare a per-actor default (`on cue LooksAt(<Actor>):`), which wins over the bare name. Tracked by P32-27; ask the maintainer before changing dispatch.
- **`true` has three meanings** (observed 2026-11-09, session 29). `now X is Y` and `remember R(X, true)` store the interned entity `true` as the object, and `if X is Y` compares against it (`Codegen.resolve_entity_or_value`); `VM.has_fact_pattern` (dialogue choices) reads `true` as 1; `when` trigger patterns read a lowercase `true` as a variable that matches anything. Hosts that assert a state must use the entity `true` to be seen by script conditions. Tracked by P32-28.
