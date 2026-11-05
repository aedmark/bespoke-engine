# Session Handoff

Read this first when resuming unfinished work. Rewrite the top half whenever current state changes materially or work pauses with context another session needs.
The session log below it is append-only history. "Current state" fits on a screen or two (about 80 lines); what does not fit is history, and belongs in the session log.

Protocol: see [AGENTS.md](../AGENTS.md) (`CLAUDE.md` imports it). Plan: [ROADMAP.md](../ROADMAP.md).
Architecture: [ARCHITECTURE.md](ARCHITECTURE.md). Decisions: [DECISIONS.md](DECISIONS.md).
Tests: [TESTING.md](TESTING.md). Security: [SECURITY.md](SECURITY.md).
Changes: [CHANGELOG.md](CHANGELOG.md). Older sessions: [archive/](archive/README.md).

---

## Current state

_Last updated: 2026-11-04, session 3, on `main`: completed Phase 7 (Adventure Game Primitives: Verbs, Inventory, Dialog & Hotspots)._

**Where things stand, in one paragraph:**
Phase 1 through Phase 7 are complete and operational. The BeSpoke Engine is a fully functioning "Engine-as-Spine" runtime, language, and graphical simulation: raw BeSpoke scripts compile directly to compact bytecode, executing over contiguous relational state arenas and discrete waypoint graphs with cooperative fibers and priority preemption. Phase 7 expands BeSpoke with first-class point-and-click adventure primitives: static scene hotspots (Fireplace, Bar Counter, Wine Cask), classic adventure verbs (`WALK`, `LOOK`, `TALK`, `TAKE`, `USE`) with active highlighting and right-click cycling, a relational inventory system querying `InInventory` and `Carries` facts into an on-screen inventory tray, and branching dialogue trees with parchment speech balloons and interactive choice pills. Headless simulation is fully supported via `--headless`.

**Verified** (2026-11-04, on `main`, Linux x86_64, Zig 0.13.0)

| Suite | Result |
| --- | --- |
| `python3 tools/check_docs.py` | **0 errors, 0 warnings** |
| `zig test src/world.zig` | **4/4 passed** |
| `zig test src/bytecode.zig` | **5/5 passed** |
| `zig test src/spatial.zig` | **7/7 passed** |
| `zig test src/vm.zig` | **11/11 passed** |
| `zig test src/compiler/lexer.zig` | **2/2 passed** |
| `zig test src/compiler/parser.zig` | **3/3 passed** |
| `zig test -lc -lSDL2 src/display.zig` | **16/16 passed** |
| `zig test -lc -lSDL2 src/root.zig` | **23/23 passed** |
| `zig build test` | **passed** |
| `zig build run -- --headless` | **Tavern Heist full simulation with live rewind passed** |

**What works**
- **World Relational Database:** Contiguous arena, `MultiArrayList(Fact)`, TTL decay, query iterators (`World.query`), and CRC32-checked snapshots (P1-01 through P1-04, P7-03).
- **Bytecode VM & Scheduler:** Compact opcodes, cooperative fibers, `wait_ticks`, `wait_until`, and interrupt stacks (P2-01 through P2-04).
- **Spatial Topology & Hotspots:** 2D integer waypoints, rooms, A* graph pathfinding, asynchronous motor intents (`walk_to`), and static scene hotspots (`Fireplace`, `BarCounter`, `WineCask`) with examine text and spatial hitboxes (P3-01, P3-02, P7-01, D-005, D-009).
- **Compiler Front-End:** Lexer, AST parser, and bytecode code generator (`compile_source`), with extended grammar for `verb Name(args)` and `say Speaker: "text"` dialogue statements lowered to `emit_cue` (P4-01 through P4-03, P7-02, P7-04, D-002, D-009).
- **Display Bridge & Time-Travel:** Double-buffered render frames (`DisplayBridge`), text/terminal visualizer, and instant snapshot rewind (P5-01, P5-02, D-001).
- **SDL2 Peripheral 2D Display & Controls:** Hardware-accelerated 2D renderer, built-in 5x7 bitmap font, room/waypoint scene graph, animated actor tokens, point-and-click mouse navigation for Cat, and live time-travel rewind hotkey (P6-01 through P6-04, D-008).
- **Adventure Game Primitives:** 5-verb UI bar (`WALK`, `LOOK`, `TALK`, `TAKE`, `USE`) with active button highlights and right-click cycling, actor and prop interaction, relational inventory tray rendering, and branching dialogue parchment balloons with interactive choice buttons (P7-01 through P7-04, D-009).

**Not verified**
- Peripheral audio sound effects / music playback; visual cues, floating banners, and speech balloons are fully verified.

**Gotchas for the next session**
- When restoring snapshots via `restore_state`, the world memory buffer is rewound in place; external display layers should call `DisplayBridge.capture_frame()` immediately following a restore to synchronize visualization.
- Dialogue balloons are rendered by the display peripheral based on high-level state; clicking a dialogue choice dismisses the balloon and can emit cues or remember facts in the simulation spine.

---

## Session log

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
