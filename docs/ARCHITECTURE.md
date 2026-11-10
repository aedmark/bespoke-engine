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
| Audio Subsystem & Synth | `src/audio.zig` | `AudioBridge.init()` | Display bridge & SDL2 audio callback; procedural chiptune synth; engine interface sounds as `SfxPatch` data; plays a host `Soundtrack` of tracks, effects, and scene rule (D-019, D-040) |
| Persistent Save Storage | `src/save.zig` | `SaveManager.init()` | World, Spatial, & VM stores; CRC32-checksummed `.sav` slots, thumbnails, and `.bak` recovery (D-020) |
| Emergent Society | `src/society.zig` | `Society.init(world, config)` / `Society.step()` | World, Spatial, & VM stores; data-driven needs, roles, and routines from Zig or a compiled `society` declaration; witness detection, rumor propagation, and justice cascades over facts (D-032, D-034, D-045) |
| Dialogue Duel & Inquiry Fatigue | `src/duel.zig` | `Duel.init(world, config)` / `Duel.resolve_round()` / `InquiryFatigue.record()` | World and VM; challenge/reply pairs, opponent tiers, advantage, and staged mood decay from Zig or a compiled `duel` declaration, offered through `VM.prune_dialogue_choices` and runtime-generated dialogue choice sets (D-017, D-035, D-045, D-046) |
| Executable Dialogue | `src/dialogue.zig` | `dialogue.begin()` / `dialogue.choose()` / `VM.choose()` | World; fact-backed choice sets, scripted suspension and selected-body resume, runtime-generated host actions, and `RenderFrame.dialogue` (D-046) |
| Proactive Social Agency | `src/agency.zig` | `AgencySystem.init(world, config)` / `AgencySystem.step()` | World, Spatial, VM, Society; data-driven agendas, omission triggers, dynamic A* pursuit, soft interrupts, and epistemic contests (D-038) |
| Proof Presentation | `proofs/art.zig` | `art.theme` | The `Theme` every proof registers with its window: backdrops, props, tokens, walkways, footer hints, and the proofs' `Soundtrack` of music, scene rule, and effects (D-039, D-040) |
| The Living Village | `proofs/village.zig` | `run_headless()` / `run_interactive()` | Society client: six villagers, settlement map, catalysts (D-021) |
| The Bayou Estate | `proofs/bayou_puzzle.zig` | `run_headless()` / `run_interactive()` | Agency client: Laura Bow mystery slice with wandering suspects, omission triggers, Carriage House dissuasion, and alibi inoculation (P33, D-038) |
| WebAssembly Browser Target | `src/wasm.zig`, `src/wasm_engine.zig` | `WasmRuntime.init(allocator, decks, index)`, `export_runtime(decks)` | World, Spatial, & VM stores; `wasm32-freestanding` RGBA8888 software canvas, browser event bridge, and C-ABI exports built per module from a host `Deck` table; `bespoke.wasm` carries one neutral deck (D-022, D-042) |
| Proof Browser Decks | `proofs/wasm_deck.zig`, `proofs/wasm_main.zig` | `decks` | The six proof decks for `bespoke-proofs.wasm` (`zig build wasm-proofs`) (D-042) |
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
| Bytecode package (.bspk) | Asset Compiler (`src/package.zig`) | Runner / Asset Loader | Standalone CRC32-checksummed binary container (`BSPB`) with symbol tables, waypoints, bytecode, drafts, and compiled society and duel declarations |
| State snapshot | World Store | Disk / Memory Buffer | Flat contiguous memory arena; restorable via `memcpy` |
| Persistent Save File (.sav) | Save Manager (`src/save.zig`) | Save / Slot Loader | CRC32-checksummed binary save (`BSAV`) with metadata header, 16x12 RGB332 thumbnail, World/Spatial/VM state, and `.bak` recovery (D-020) |
| Render state slice | VM / World Store | Display Peripheral | Read-only double-buffered struct containing active entity positions, facing, and visual cues |
| External cues | Input / Peripheral | VM Cue Dispatcher | Named cue events (e.g. `PlayLute(Bard, Target)`) queued for next tick |
| Audio cue stream | Simulation spine / GUI | AudioBridge / Synth | Decoupled thread-safe event queue synthesizing procedural action SFX and BGM (D-019) |
| WebAssembly Framebuffer & Event Bridge | `WasmRuntime` (`src/wasm.zig`) | Browser HTML5 `<canvas>` | Contiguous `640x360x4` RGBA8888 linear-memory byte buffer and C-ABI mouse/keyboard/touch exports (`wasm_init(deck)`, `wasm_step_tick`, `wasm_on_pointer_down`), the same in `bespoke.wasm` and `bespoke-proofs.wasm`; 8 MB stack (D-022, D-042) |

## Invariants

Rules that hold everywhere across the engine and runtime:

- **The VM is the single source of truth:** Downstream renderers never modify game state directly. Enforced by: display bridge read-only pointer semantics (D-001).
- **Decoupled non-blocking audio peripheral:** Sound synthesis never blocks discrete simulation ticks or alters world state; audio events are consumed asynchronously from a ring buffer by peripheral callbacks or offline test buffers. Enforced by: `AudioBridge` ring buffer and procedural synthesis architecture in `src/audio.zig` (D-001, D-019).
- **Pointerless relational facts:** All facts are flat integer tuples `(subject, relation, object_or_value, expires_at_tick)`. Enforced by: `Fact` struct definition in `src/world.zig` (D-003, D-007).
- **Deterministic save/restore:** The entire active game state resides in a contiguous arena such that saving or restoring is a pure memory copy without pointer swizzling. Enforced by: arena allocator layout in `src/world.zig` (D-003).
- **A cue runs only a handler declared for it (D-037):** dispatch tries the exact signature, wildcard signatures from variable parameters, then the actor-only default; there is no fallback to a handler written for another actor or target. Enforced by: `CompiledProgram.find_cue_handler` and the P32-27 test in `src/compiler.zig`.
- **The engine knows no game's status (D-041):** proof progress reaches the frame only through the host status block, which the engine never reads; the portal guard rule and save thumbnails read host facts and host colours. Enforced by: `RenderFrame.host_status`, the P32-03c portal test in `src/spatial.zig`, the P32-03d thumbnail test in `src/save.zig`, and the render golden's progress and thumbnail lines.
- **The engine plays no game's sound (D-040):** music, the scene-to-track rule, and game effects come from the host's `Soundtrack`; the engine has only its interface and distaff effects and no default track. Enforced by: the separation lint (0 hits in `src/audio.zig`), the P32-02d tests there, and `proofs/golden/audio.txt`.
- **The engine draws no game's look (D-039):** scene backdrops, prop art, actor tokens, walkway styles, footer hints, and game keys come from the host's `Theme`; the renderer supplies neutral defaults and names no scene, prop, or character. Enforced by: the separation lint (0 hits in `src/display/renderer.zig`), the P32-02b theme test there, and `proofs/golden/render.txt`.
- **Reversible interruption:** An interrupt block must push the fiber's program counter and local registers to the entity's interrupt stack and restore them when the condition clears. Enforced by: interrupt frame management in `src/vm.zig` (D-004).
- **Continuous global facts across scenes:** Scene transitions (`transition to scene: TargetScene`, D-014) swap active spatial waypoints, pause/wake ambient scene routines, and switch visual backdrops, but all relational world facts persist continuously across scene boundaries. Enforced by: `World` remaining the singular simulation spine across scene transitions in `src/vm.zig` (D-001, D-014).
- **Centralized floating label collision resolution:** All in-world floating text labels (actor names, status badges, waypoint names, and hotspot prompts) resolve through a deterministic 2D collision solver (`TextLayoutResolver`) prior to rasterization, ensuring zero overlapping text labels across actors, waypoints, and props regardless of camera framing or entity clustering. Enforced by: `TextLayoutResolver` in `src/display/text_layout.zig` and integration pass in `DisplayWindow.render_frame` (D-024).
- **Conservation of matter in item transfers:** Item transfer between party actors (`World.transfer_item`, D-025) is an atomic relational mutation forgetting prior possession facts before asserting new possession facts, guaranteeing zero item duplication across actors or scene partitions. Enforced by: `World.transfer_item` in `src/world.zig` and `SpatialSystem.can_transfer_item` in `src/spatial.zig` (D-025).
- **Unidirectional DAG temporal causality:** Time-travel causality cascades strictly forward along a Directed Acyclic Graph (Past -> Present -> Future). Past physical state mutations trigger deterministic reactive interrupts across subsequent eras without retrocausal paradox loops. Enforced by: forward topological ordering and reactive rules in `src/vm.zig` and `proofs/dott_puzzle.zig` (D-025).
- **Epistemic belief dialogue guards:** Persuasive or contextual dialogue choices evaluate dynamic NPC belief states (`Believes`, `Knows`, `Rejects`) where negative rejection facts strictly supersede unverified claims until physical evidence facts are remembered. Enforced by: `VM.evaluates_belief` in `src/vm.zig` (D-015, D-017, D-025).
- **Spatial locality vs. relational causality:** Spatial topologies (rooms, waypoints, geometry) are scene-local; causality is relational. Different time periods or parallel spaces never force geometric coordinate overlays; cross-era state synchronization occurs purely through flat relational facts and reactive rule cascades. Enforced by: independent `SpatialGraph` room meshes in `src/spatial.zig` synchronized through global facts in `src/world.zig` (D-001, D-003, D-026).
- **Portal-anchored inventory transfer policy:** Multi-character party transfers under `.portal_anchored` policy succeed *if and only if* both sender and recipient can physically access their room's portal (`SpatialSystem.can_access_portal`): the portal is not `PortalBlocked`, the actor is not `Trapped`, and a `Guarded` or `Detained` actor holds `PassesGuard` or `DoingBusiness` / `InYard` or stands at the portal. In the DOTT proof, Laverne is `Guarded` and her tentacle disguise grants `PassesGuard`. Enforced by: `SpatialSystem.can_access_portal` and `can_transfer_item_with_world` in `src/spatial.zig` (D-025, D-026, D-041).
- **Temporal Hypervisors and Mass Conservation (`TemporalHypervisor`, D-027):** Tangent Universe branching is an ephemeral copy-on-write fork (`World.clone`). The duplicated Artifact of Metal violates mass conservation until returned to the designated vortex threshold waypoint before countdown expiration (`collapse_budget_ticks`). If the countdown expires before loop closure, the universe collapses into a terminal gravitational singularity (`singularity_collapsed = true`). If loop closure invariants are satisfied, the Tangent Universe merges cleanly, the Artifact is committed to the Primary Universe at $T_0$, and dream residue memories are transferred to the Living Receiver. Enforced by: `TemporalHypervisor` in `src/hypervisor.zig`, `World.clone` in `src/world.zig`, and `proofs/darko_puzzle.zig` (D-027).
- **Pre-Cognitive Vector Conduits & Novikov Consistency (`VectorConduit`, `validate_novikov_consistency`, D-027):** Fourth-Dimensional vector conduits project ahead-of-time deterministic A* path trajectories directly from actor origin coordinates to goal waypoints, rendered as translucent fluid tendrils with energy cores. Paradoxical actions that would contradict established timeline facts are validated through Novikov self-consistency checking, ensuring deterministic loop stability without retrocausal contradictions. Enforced by: `VectorConduit`, `compute_vector_conduit`, and `validate_novikov_consistency` in `src/spatial.zig` and `DisplayWindow.render_frame` in `src/display/renderer.zig` (D-027).
- **Asymmetric downstream feedback (Mutations vs. Continuations):** Structural physical mutations in the past that alter downstream reality telegraph their consequences via reactive interrupt cutscenes (`when` interrupts); temporal continuations (container incubation over time) are discovered organically through player inspection in downstream eras without narrative interruption. Enforced by: edge-triggered VM reactive interrupts vs. passive relational fact queries in `src/vm.zig` and `proofs/dott_puzzle.zig` (D-010, D-025, D-026).
- **Unambiguous musical drafts and dispatched weaves (D-029):** A played four-note sequence names at most one draft, forward or reversed, and weaves dispatch only through exact `Weave:caster:draft[:target]` handler keys. In-script weaves wait in `VM.pending_weaves` until the host calls `dispatch_pending_weaves` after `step_tick`. A half-played distaff phrase is host-side input state (`DistaffInput`, D-030) and never enters the world arena. Enforced by: parser draft validation in `src/compiler/parser.zig`, `CompiledProgram.find_weave_handler`, and the `PendingWeavesNotDispatched` save refusal in `src/save.zig`.
- **Society state is facts (D-034):** `Society` holds only configuration and relation ids; every need, activity, stay, crime, rumor, warrant, and arrest is a World fact, so snapshots and saves capture the whole society. Enforced by: `Society` field list in `src/society.zig` and the snapshot-restore test there.
- **Arrival is an edge, fired inside the tick (D-036):** a `when <Actor> arrives at <Mark>:` rule fires once per completed walk at that mark, in the tick the walk completes, and never for resting, passing through, or being placed. Enforced by: `MotorAgent.arrival_pending`, the arrival pass and `clear_arrivals` call in `VM.evaluate_reactive_rules`, and the P32-18 tests in `src/compiler.zig`.
- **Duel and fatigue state is facts (D-035):** `Duel` and `InquiryFatigue` hold only borrowed configuration and interned ids; what a fighter has heard and mastered, tiers, advantage, wins, inquiry counts, and moods are World facts, and duel lines reach the player only through `VM.prune_dialogue_choices`. Enforced by: the struct field lists in `src/duel.zig` and the snapshot-restore test there.
- **Dialogue state is facts (D-046):** A scripted `choice` block writes `DialogueOpen`, `DialogueOption`, `DialogueBody`, and `DialogueFiber` facts, suspends its fiber, and resumes at the selected body; host-generated sets use the same facts with `DialogueAction` instead of a body pc. Snapshots and rewinds carry the open set, and `VM.sync_dialogue` releases a fiber whose set the restored world does not contain. Enforced by: `src/dialogue.zig` tests and the P32-30 compiler-to-VM test in `src/compiler/codegen.zig`.
- **Script declarations are owned program data (D-045):** `CompiledProgram` owns compiled society and duel declarations. Their slices may borrow stable text from the World's entity-name table and remain valid until `CompiledProgram.deinit`. Hosts initialize `Society`, `Duel`, and `InquiryFatigue` from those declarations; runtime state remains in World facts.
- **Agency and agenda state is facts (D-038):** `AgencySystem` holds only borrowed configuration and tracking counters; agenda states, triggers, outcomes, and epistemic beliefs exist as World facts. Dynamic A* pursuit tracks moving targets across discrete waypoints, and soft interrupts yield until the target actor reaches their waypoint and becomes idle, preserving motor and animation invariants. Enforced by: `AgencySystem` in `src/agency.zig`.
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
| Engine / proofs (D-031) | `@import` | Zig module paths: `src/` code cannot import a file under `proofs/` ("import of file outside module path"); the separation lint finds no proof names in non-test `src/` code (baseline 0) | Proofs depend on the engine; the engine never depends on a proof. Games supply their presentation, sound, status, and browser decks through hooks (D-039 to D-042) |
| DSL Source Script | UTF-8 text file | Compiler lexer & parser | Reject malformed grammar, undefined relations, or invalid entity declarations |
| Bytecode Package File (.bspk) | Binary container on disk | Package loader (`src/package.zig`) | Check magic bytes (`BSPB`), version (`1` to `4`), payload CRC32 checksum, element counts, slice bounds, draft note range (0 to 6), declaration capacities, enum and entity references, waypoint and member indexes, and that the arrival edge appears only in version 3 or later, before loading into World/VM. Versions 1 to 3 load with empty society and duel declaration tables. |
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

- **Cue handler `where` guards are parsed but not evaluated** (observed 2026-11-08, session 28). `script_spec.md` shows `on cue Steal(Cat, victim) where CharmedBy(victim, _) and Carries(victim, loot):`, and the parser stores `CueHandler.where_patterns`, but `Codegen.compile` compiles only the handler body and `VM.fire_cue` spawns it unconditionally. Only dialogue choices evaluate `where` patterns (`VM.prune_dialogue_choices`). Weave handlers (D-029) express affordances with `if` checks instead. Fixing this changes behaviour of every existing script that relies on the guard text; ask the maintainer before changing it.
- **Cue handler variables are matched but not bound** (observed 2026-11-09, session 29). After D-037 a parameter such as `target` in `on cue PlayLute(Bard, target):` matches any entity, but codegen does not bind it: `remember CharmedBy(target, Bard)` in the body writes a fact about an entity named `target`. `script_spec.md` shows the bound form. Cue `where` guards (above) are the same gap.
