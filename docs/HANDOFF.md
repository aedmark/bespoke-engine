# Session Handoff

Read this first when resuming unfinished work. Rewrite the top half whenever current state changes materially or work pauses with context another session needs.
The session log below it is append-only history. "Current state" fits on a screen or two (about 80 lines); what does not fit is history, and belongs in the session log.

Protocol: see [AGENTS.md](../AGENTS.md) (`CLAUDE.md` imports it). Plan: [ROADMAP.md](../ROADMAP.md).
Architecture: [ARCHITECTURE.md](ARCHITECTURE.md). Decisions: [DECISIONS.md](DECISIONS.md).
Tests: [TESTING.md](TESTING.md). Security: [SECURITY.md](SECURITY.md).
Changes: [CHANGELOG.md](CHANGELOG.md). Older sessions: [archive/](archive/README.md).

---

## Current state

_Last updated: 2026-11-06, session 6, on `main`: completed Phase 10 (The Booty Island Spitting Contest Scenario & Extended Narrative DSL: Stageplay Syntax, Falling-Edge & Expiration Triggers, Vertical Slice Scenario)._

**Where things stand, in one paragraph:**
All 10 phases of the BeSpoke Engine roadmap are complete, verified, and operational. The BeSpoke Engine is a standalone, systemic simulation engine ("Engine-as-Spine") and domain-specific game development language written in pure Zig. Raw narrative scripts compile directly to bytecode, driving deterministic simulations over flat relational fact arenas, discrete waypoint topologies, cooperative fibers, autonomous reactive rule cascades, and declarative stageplay structures. Phase 10 expands the compiler and VM to natively support stageplay scene taxonomies (`scene:`, `cast:`, `props:`, `marks:`), natural state assertions and expressions (`now X is [not] Y`, `X is [not] Y in the scene`), falling-edge rule triggers (`when X stops being Y:`), and fact TTL expiration hooks (`when Entity forgets Relation:`). The full multi-step *Monkey Island 2* Booty Island Spitting Contest puzzle scenario is implemented in `src/spitting_contest.zig` and runnable via `--spitting-contest`.

**Verified** (2026-11-06, on `main`, Linux x86_64, Zig 0.13.0)

| Suite | Result |
| --- | --- |
| `python3 tools/check_docs.py` | **0 errors, 0 warnings** |
| `zig test src/world.zig` | **5/5 passed** |
| `zig test src/bytecode.zig` | **6/6 passed** |
| `zig test src/spatial.zig` | **8/8 passed** |
| `zig test src/vm.zig` | **16/16 passed** |
| `zig test src/repl.zig` | **16/16 passed** |
| `zig test src/compiler/lexer.zig` | **3/3 passed** |
| `zig test src/compiler/parser.zig` | **6/6 passed** |
| `zig test -lc -lSDL2 src/display.zig` | **20/20 passed** |
| `zig test -lc -lSDL2 src/root.zig` | **35/35 passed** |
| `zig build test` | **passed** |
| `zig build run -- --headless` | **Tavern Heist full simulation with live rewind passed** |
| `zig build run -- --spitting-contest` | **Booty Island Spitting Contest full scenario with rewind passed** |

**What works**
- **World Relational Database:** Contiguous arena, `MultiArrayList(Fact)`, TTL decay, query iterators (`World.query`), multi-clause pattern matcher (`find_first_match`, `has_multi_match`, `find_all_matches`), and CRC32-checked snapshots (P1-01 through P1-04, P7-03, P8-01, D-010).
- **Bytecode VM & Scheduler:** Compact opcodes, cooperative fibers, `wait_ticks`, `wait_until`, priority interrupt stacks (`active_priority`, `interrupt_entity_priority`), and continuous reactive rule evaluation (`evaluate_reactive_rules`, `load_compiled_rules`) (P2-01 through P2-04, P8-02, P8-03, D-004, D-010).
- **Spatial Topology & Hotspots:** 2D integer waypoints, rooms, A* graph pathfinding, asynchronous motor intents (`walk_to`), and static scene hotspots (`Fireplace`, `BarCounter`, `WineCask`) with examine text and spatial hitboxes (P3-01, P3-02, P7-01, D-005, D-009).
- **Compiler Front-End:** Lexer, AST parser, and bytecode code generator (`compile_source`), with grammar for verbs, dialogue (`say`), multi-clause `when` rules (`when Pattern1 and Pattern2:`), and automatic `CompiledWhenRule` generation (P4-01 through P4-03, P7-02, P7-04, P8-01, P8-02, D-002, D-009, D-010).
- **Display Bridge & Time-Travel:** Double-buffered render frames (`DisplayBridge`), text/terminal visualizer, and instant snapshot rewind (P5-01, P5-02, D-001).
- **SDL2 Peripheral 2D Display & Controls:** Hardware-accelerated 2D renderer, built-in 5x7 bitmap font, room/waypoint scene graph, animated actor tokens, point-and-click mouse navigation for Cat, and live time-travel rewind hotkey (P6-01 through P6-04, D-008).
- **Adventure Game Primitives:** 5-verb UI bar (`WALK`, `LOOK`, `TALK`, `TAKE`, `USE`) with active button highlights and right-click cycling, actor and prop interaction, relational inventory tray rendering, and branching dialogue parchment balloons with interactive choice buttons (P7-01 through P7-04, D-009).
- **Reactive Simulation & Systemic AI:** Continuous pattern-matched rule evaluation, edge-triggered fiber interrupts on positive transition (`false -> true`), and priority cascades (e.g., theft alerts preempting charmed states) (P8-01 through P8-03, D-010).
- **Developer Dashboard & Inspector:** Live HUD overlay (`src/display/renderer.zig`, toggle `[F1]`/`[D]`) displaying active relational facts with TTL timers, active fiber call stacks with program counters and priorities, and agent spatial positions (P9-01, D-011).
- **Interactive Timeline Scrubber:** Full graphical scrubber bar with interactive click-to-scrub and `[<]` / `[>]` arrow stepping across serialized snapshots with instantaneous visual replay and divergent timeline truncation (P9-02, D-001, D-003, D-011).
- **Live Interactive REPL Console:** Pure Zig simulation command dispatcher (`src/repl.zig`) and in-engine drawer overlay (`[Tab]`/`[C]`/`[~]`) executing `remember`, `forget`, `cue`, `walk`, `step`, and `facts` commands live during simulation (P9-03, D-011).

**Not verified**
- Peripheral audio sound effects / music playback; visual cues, floating banners, and speech balloons are fully verified.

**Gotchas for the next session**
- When restoring snapshots via `restore_state`, the world memory buffer is rewound in place; external display layers should call `DisplayBridge.capture_frame()` immediately following a restore to synchronize visualization.
- Reactive rules are edge-triggered: they fire once when a condition transitions from false to true. The rule re-arms when the condition clears, preventing infinite interrupt loops while conditions remain active.
- When stepping forward after scrubbing backward in time, subsequent future snapshots are pruned to record the newly divergent simulation timeline.

---

## Session log

### Session 6 (2026-11-06)
- **Goal:** Implement Phase 10: The Booty Island Spitting Contest Scenario & Extended Narrative DSL (P10-01 through P10-03, D-012), calibrate visual layout, and fix actor positioning.
- **Work:** Recorded architectural decision `D-012` (High-Level Stageplay Taxonomy, Falling-Edge Triggers, and TTL Expiration Hooks). Extended lexer (`src/compiler/lexer.zig`) with stageplay keywords (`scene`, `cast`, `props`, `marks`, `now`, `is`, `are`, `stops`, `forgets`, `being`, `animate`, `stop`, `during`, `state`, `resume`, `done`, `currently`, `in`, `the`, `says`), square brackets (`[` / `]`), tilde comments (`~`), and hyphenated animation clip identifiers (`wind-blowing`). Enhanced parser (`src/compiler/parser.zig`) to parse stageplay taxonomy headers, automatic waypoint and hotspot registration for marks and props, natural state assertions (`now X is [not] Y`, `X is [not] Y in the scene`), falling-edge when rules (`when X stops being Y:`), and expiration rules (`when Entity forgets Relation:`). Extended code generator (`src/compiler/codegen.zig`) to lower `.animate` cues and `.resume_stmt` operations. Enhanced `World` (`src/world.zig`) with a `recently_expired: [16]Fact` ring buffer populated during `prune_expired()`. Extended VM reactive rule engine (`src/vm.zig`) with `ReactiveEdge` (`.rising`, `.falling`, `.on_expire`) to evaluate expiration triggers against `recently_expired` and falling edges on `true -> false` transitions. Implemented the complete Booty Island Spitting Contest vertical slice in `src/spitting_contest.zig` with full CLI support in `src/main.zig` (`--spitting-contest`, `--spit`, `--scenario spitting-contest`), featuring crowd egging routine, wind cycling, ship horn distraction, flag tampering, thick spit green drink, wind-timed spit resolution, TTL expiration resumption, and time-travel rewind verification. Fixed waypoint/hotspot string lifetime safety in `src/spatial.zig` via owned duplication to eliminate compiler arena pointer corruption. Calibrated field distance track lines and spread actors across distinct coordinates (`Guybrush` at Starting Line, `Organiser` at Judging Post, `Onlookers` at Spectator Lawn, `Flags` at 2nd Place line). Populated Guybrush's initial inventory (`Horn`, `GreenDrink`) and added direct inventory tray mouse-click hit testing.
- **Outcome:** All 35 tests passing on `src/root.zig`, `zig build test` passing, both `--headless` Tavern Heist and `--spitting-contest` Booty Island scenarios executing cleanly. Documentation verified with 0 errors and 0 warnings. Phase 10 roadmap items (`P10-01` through `P10-03`) complete.

### Session 5 (2026-11-04)
- **Goal:** Implement Phase 9: Interactive Time-Travel Debugger & REPL (P9-01 through P9-03).
- **Work:** Recorded architectural decision `D-011` (In-Engine Developer Dashboard, Snapshot Scrubber, and Live REPL Console). Implemented pure Zig command engine `src/repl.zig` with zero SDL2/GUI dependencies, supporting `help`, `remember`, `forget`, `cue`, `walk`, `step`, and `facts` command execution directly on `World`, `SpatialSystem`, and `VM`. Extended `DisplayBridge` and `RenderFrame` in `src/display.zig` to slice active relational facts, fiber execution stacks, and `max_history_tick` into double buffers. Enhanced peripheral renderer `src/display/renderer.zig` with interactive Timeline Scrubber bar (hit testing, elapsed progress, tick label, arrow key scrubbing), Developer Dashboard overlay (`[F1]`/`[D]`), and Live Interactive REPL Console drawer (`[Tab]`/`[C]`/`[~]`, `SDL_TEXTINPUT`, command execution, history log). Wired timeline scrubbing with divergent timeline handling, REPL command injection, and debug overlays into `src/main.zig`.
- **Outcome:** All 104 unit tests passing across all suites (`zig build test`, `zig test -lc -lSDL2 src/root.zig`, `zig test -lc -lSDL2 src/display.zig`, `zig test src/repl.zig`, `zig test src/world.zig`, `zig test src/spatial.zig`, `zig test src/vm.zig`, `zig test src/bytecode.zig`, `zig test src/compiler/lexer.zig`, `zig test src/compiler/parser.zig`). Headless simulation verified with full Tavern Heist execution and rewind. Documentation verified with 0 errors and 0 warnings. Phase 9 roadmap items (`P9-01` through `P9-03`) complete. All 9 roadmap phases complete.

### Session 4 (2026-11-04)
- **Goal:** Implement Phase 8: Reactive Simulation Rules (`when` Engine in VM).
- **Work:** Recorded architectural decision `D-010` (Reactive Simulation Engine with Multi-Clause Relational Joins and Priority Rule Cascades). Implemented multi-clause relational pattern matcher in `src/world.zig` (`PatternTerm`, `PatternClause`, `VariableBindings`, `find_first_match`, `has_multi_match`, `find_all_matches`) with backtracking variable unification. Extended compiler parser (`src/compiler/parser.zig`) to parse conjoined `when` rules (`when Pattern1 and Pattern2:`). Updated code generator (`src/compiler/codegen.zig`) to lower `when` rules into `CompiledWhenRule` structures with resolved pattern terms and priority. Implemented VM continuous reactive rule engine in `src/vm.zig` (`ReactiveRule`, `add_reactive_rule`, `evaluate_reactive_rules`, `load_compiled_rules`) with edge-triggered preemption (`false -> true`) on tick boundary. Implemented priority-tiered interrupt stacks in `src/vm.zig` (`active_priority`, `interrupt_entity_priority`, `.resume_routine` priority popping) allowing higher-priority interrupts (e.g. theft alert) to preempt lower-priority interrupts (e.g. charm) and cleanly resume routines. Integrated compiled reactive rules into `src/main.zig`, enabling autonomous charm and theft reaction without manual interrupt calls in the application loop.
- **Outcome:** All 81 tests passing across all suites (`zig build test`, `zig test -lc -lSDL2 src/root.zig`, `zig test -lc -lSDL2 src/display.zig`, `zig test src/world.zig`, `zig test src/spatial.zig`, `zig test src/vm.zig`, `zig test src/compiler/lexer.zig`, `zig test src/compiler/parser.zig`). Headless simulation verified. Documentation verified with 0 errors and 0 warnings. Phase 8 roadmap items (`P8-01` through `P8-03`) complete.

### Session 3 (2026-11-04)
- **Goal:** Implement Phase 7: Adventure Game Primitives (Verbs, Inventory, Dialog & Hotspots).
- **Work:** Recorded architectural decision `D-009` unifying classic adventure verbs as cues and hotspots as entities. Added `Hotspot` registration and spatial hit testing in `src/spatial.zig`. Added `kw_verb`, `kw_say`, and string literal parsing in the compiler front-end (`src/compiler/lexer.zig`, `src/compiler/parser.zig`, `src/compiler/codegen.zig`), lowering `say` statements to `emit_cue` with interned text ids. Added `QueryIterator` and `World.query` to `src/world.zig` for scanning multi-row relational facts. Enhanced `src/display.zig` to capture hotspots and inventory items (`InInventory`, `Carries`) into `RenderFrame`. Implemented 5 classic adventure verbs (`WALK`, `LOOK`, `TALK`, `TAKE`, `USE`) with right-click cycling and UI bar in `src/display/renderer.zig`. Implemented parchment speech balloons with speaker name, dialogue text, speech tails, and interactive branching choice options with hover highlights. Wired full interactive verb actions, prop examining/use, and dialogue tree choices into `src/main.zig`.
- **Outcome:** All 55 tests passing across all suites (`zig build test`, `zig test -lc -lSDL2 src/root.zig`, `zig test -lc -lSDL2 src/display.zig`, `zig test src/world.zig`, `zig test src/spatial.zig`, `zig test src/compiler/lexer.zig`, `zig test src/compiler/parser.zig`). Headless simulation verified. Documentation verified with 0 errors and 0 warnings. Phase 7 roadmap items (`P7-01` through `P7-04`) complete.

### Session 2 (2026-11-04)
- **Goal:** Scrub zero-LLVM branding, expand roadmap for Phases 6 through 9, and implement Phase 6 (SDL2 Peripheral Graphics Window).
- **Work:** Scrubbed all zero-LLVM marketing claims across repository docs and banners per user directive. Detailed Phases 6, 7, 8, and 9 in `ROADMAP.md`. Recorded architectural decision `D-008` (SDL2 Peripheral Display Consumer). Extended `build.zig` to link `SDL2` and `libc` for executables and tests. Enhanced `src/display.zig` with richer `RenderFrame` capturing waypoints, edges, and held items. Implemented built-in 5x7 ASCII bitmap font in `src/display/font.zig` with scaling and text measurement. Built `src/display/renderer.zig` providing 2D room visualization (Tavern & Cellar), waypoint glow anchors, A* edge corridors, animated actor tokens (Cat, Guard, Bard, Cheese), point-and-click mouse navigation targeting the Cat, simulation HUD, cue notification banners, and hotkey controls (`[Space]`, `[N]`, `[R]`, `[Esc]`). Updated `src/main.zig` with full interactive GUI loop while supporting headless fallback (`--headless`).
- **Outcome:** All 15 display tests passing (`zig test -lc -lSDL2 src/display.zig`), `zig build test` passing, headless simulation passing, and interactive window operating at 60 Hz. All Phase 6 roadmap items complete (`P6-01` through `P6-04`).

### Session 1 (2026-11-04)
- **Goal:** Synthesize architectural brainstorming, adopt The Manifold repository framework, produce formal engineering spec, and implement the entire 5-phase BeSpoke Engine roadmap.
- **Work:** Analyzed initial brainstorming files (`whitepaper.md`, `architecture.md`, `script_spec.md`). Debated boundary of responsibility (drop-in decision box vs. unified engine-as-spine). Selected BeSpoke standalone engine path (D-001). Initialized git repository. Adopted The Manifold documentation system with `tools/check_docs.py`. Authored `AGENTS.md`, `CLAUDE.md`, `README.md`, `ROADMAP.md`, `docs/ARCHITECTURE.md`, `docs/DECISIONS.md`, `docs/TESTING.md`, `docs/SECURITY.md`, `docs/CONTRIBUTING.md`, and `docs/CHANGELOG.md`. Resolved Q-001, Q-002, and Q-003 into D-005 (Room/Waypoint Graph), D-006 (Linear Scan Baseline), and D-007 (Unified Ternary Facts). Installed Zig 0.13.0. Implemented Phase 1 (`src/world.zig`), Phase 2 (`src/bytecode.zig`, `src/vm.zig`), Phase 3 (`src/spatial.zig`), Phase 4 (`src/compiler/`), and Phase 5 (`src/display.zig`). Connected the full pipeline in `src/main.zig` executing the Tavern Heist with live rewind. Pushed all commits to remote GitHub repository.
- **Outcome:** All 32 unit tests passing. End-to-end simulation executing smoothly. Full repository documentation verified with 0 errors and 0 warnings. Phases 1 through 5 complete.
