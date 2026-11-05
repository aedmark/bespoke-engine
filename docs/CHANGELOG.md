# Changelog

User-visible changes to the BeSpoke Engine, newest first.

## Unreleased

### Added
- Completed Phase 2 (Bytecode VM & Fiber Scheduler): implemented `src/bytecode.zig` and `src/vm.zig` with compact instruction set, fiber scheduler, temporal waits, and interrupt preemption (P2-01 through P2-04).
- Implemented `wait_ticks` and `wait_until` condition block evaluation (P2-03, D-004).
- Implemented `interrupt_entity` and `resume_routine` stack preemption for priority event handling (P2-04, D-004).
- Implemented tabletop dice rolling primitive (`roll_dice`, e.g. `2d6`) and peripheral cue emissions (`emit_cue`) (D-001, D-002).
- Completed Phase 1 (Foundations): implemented Zig `World` relational database in `src/world.zig` using contiguous arena and `MultiArrayList(Fact)` Structure-of-Arrays layout (P1-01).
- Dynamic string interner for Entities and Relations with human-readable lookup (D-007).
- Declarative `remember` and `forget` with automatic TTL expiration tick pruning (`expires_at_tick = current_tick + ttl`) and functional property auto-overwrites (P1-02).
- Sub-microsecond pattern matching queries (`has_fact`, `find_first`, `get_property`) with wildcard support (P1-03, D-006).
- Deterministic memory snapshot save/restore with CRC32 integrity verification and time-travel rewind demo (P1-04, D-001).
- Initial specification of the BeSpoke Engine architecture (Engine-as-Spine, D-001).
- Decision records for Zero-LLVM Zig Bytecode VM (D-002), Flat Relational Fact Model (D-003), Fiber Temporal Primitives (D-004), Room/Waypoint Graph Spatial Topology (D-005), Linear Scan Baseline (D-006), and Unified Ternary Facts (D-007).
- The Manifold repository memory framework adoption and self-verification test suite via `tools/check_docs.py`.
- Formal 5-phase engineering roadmap spanning core world store, bytecode VM, spatial topology, compiler front-end, and display bridge.
