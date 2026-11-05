# Session Handoff

Read this first when resuming unfinished work. Rewrite the top half whenever current state changes materially or work pauses with context another session needs.
The session log below it is append-only history. "Current state" fits on a screen or two (about 80 lines); what does not fit is history, and belongs in the session log.

Protocol: see [AGENTS.md](../AGENTS.md) (`CLAUDE.md` imports it). Plan: [ROADMAP.md](../ROADMAP.md).
Architecture: [ARCHITECTURE.md](ARCHITECTURE.md). Decisions: [DECISIONS.md](DECISIONS.md).
Tests: [TESTING.md](TESTING.md). Security: [SECURITY.md](SECURITY.md).
Changes: [CHANGELOG.md](CHANGELOG.md). Older sessions: [archive/](archive/README.md).

---

## Current state

_Last updated: 2026-11-04, session 1, on `main`: completed Phase 1 foundations, implementing World relational database, string interning, declarative mutations, wildcard queries, and snapshot serialization in Zig._

**Where things stand, in one paragraph:**
Phase 1 (Foundations) is complete. The Zig runtime has a functional `World` relational database backed by a contiguous arena and `MultiArrayList(Fact)` (P1-01). Declarative `remember`, `forget`, and TTL expiration tick pruning are implemented and verified (P1-02). Linear pattern matching queries with wildcards (`has_fact`, `find_first`, `get_property`) are operational (P1-03). Deterministic save state snapshot serialization and restoration with CRC32 integrity checks are implemented and tested (P1-04). Next work begins Phase 2 (P2-01: opcode set definition and fiber scheduler).

**Verified** (2026-11-04, on `main`, Linux x86_64, Zig 0.13.0)

| Suite | Result |
| --- | --- |
| `python3 tools/check_docs.py` | **0 errors, 0 warnings** |
| `zig test src/world.zig` | **4/4 passed** |
| `zig build test` | **passed** |
| `zig build run` | **Tavern Heist slice demo passed** |

**What works**
- **Zig Toolchain & World Arena:** Zig 0.13.0 installed to `~/.local/bin`. Contiguous pre-allocated arena buffer initializes `MultiArrayList(Fact)` and dynamic string interner for entities and relations (P1-01, D-002, D-003).
- **Declarative Mutations & Decay:** `remember` supports permanent facts, TTL expiration (`expires_at_tick = current_tick + ttl`), and functional property auto-overwrites (P1-02, D-003, D-007). `step_tick` prunes expired facts deterministically.
- **Pattern Queries:** `has_fact`, `find_first`, and `get_property` support wildcard matching over SoA slices in sub-microsecond time (P1-03, D-006).
- **Save States & Rewind:** `save_state` and `restore_state` serialize and deserialize exact simulation states with CRC32 verification (P1-04, D-001).

**Not verified**
- Bytecode interpretation and fiber scheduling (Phase 2).
- Spatial room/waypoint navigation (Phase 3).

**Gotchas for the next session**
- When instantiating `World` in tests with small arena buffers, ensure `DEFAULT_MAX_FACTS` (8192 facts = ~144 KB) fits comfortably within the assigned arena size.

---

## Session log

### Session 1 (2026-11-04)
- **Goal:** Synthesize architectural brainstorming, adopt The Manifold repository framework, produce formal engineering spec, and implement Phase 1 foundations.
- **Work:** Analyzed initial brainstorming files (`whitepaper.md`, `architecture.md`, `script_spec.md`). Debated boundary of responsibility (drop-in decision box vs. unified engine-as-spine). Selected BeSpoke standalone engine path (D-001). Initialized git repository. Adopted The Manifold documentation system with `tools/check_docs.py`. Authored `AGENTS.md`, `CLAUDE.md`, `README.md`, `ROADMAP.md`, `docs/ARCHITECTURE.md`, `docs/DECISIONS.md`, `docs/TESTING.md`, `docs/SECURITY.md`, `docs/CONTRIBUTING.md`, and `docs/CHANGELOG.md`. Resolved Q-001, Q-002, and Q-003 into D-005 (Room/Waypoint Graph), D-006 (Linear Scan Baseline), and D-007 (Unified Ternary Facts). Installed Zig 0.13.0. Built `src/world.zig`, `src/root.zig`, `src/main.zig`, and `build.zig`. Completed P1-01, P1-02, P1-03, and P1-04.
- **Outcome:** All 4 unit tests passing. Demo binary verified with live rewind. Documentation check passing with 0 errors and 0 warnings. Phase 1 complete.
