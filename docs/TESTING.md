# Testing

How to run tests for the BeSpoke Engine, what each proves, and what it cannot. Read this before claiming anything works. The current verification results live in [HANDOFF.md](HANDOFF.md)'s "Current state".

## The Suites

| Suite | File / Command | Proves | Does not prove | Time, needs |
| --- | --- | --- | --- | --- |
| Documentation Invariants | `python3 tools/check_docs.py` | Internal consistency: references, roadmap items, decisions, links, handoff limits, and 3x manual validation | Code execution correctness | < 1s, Python 3 stdlib |
| 3x Manual Validation & Tests | `python3 tools/manual.py check scheme/bespoke.manual.json --check-evidence --root . && python3 -m unittest discover -s tests -v` | 3x What/How/Why schema conformance, evidence link validity, and manual generator unit tests | Graphical browser layout | < 1s, Python 3 stdlib |
| World Store Unit Tests | `zig test src/world.zig` | Fact insertion, TTL expiration pruning, queries, `memcpy` snapshots | VM execution or parser | < 2s, Zig compiler |
| VM & Fiber Scheduler Tests | `zig test src/vm.zig` | Bytecode dispatch, fiber yielding on `wait`, interrupt stack pushes | Spatial pathfinding | < 2s, Zig compiler |
| Full Engine Test Suite | `zig build test` | End-to-end integration across compiler, VM, and spatial graph | Peripheral display output (Raylib/Sokol) | < 5s, Zig compiler |

**The fast set** (before every commit):
```bash
python3 tools/check_docs.py
zig test src/world.zig
```

**The full set** (before merging or cutting a release):
```bash
python3 tools/check_docs.py
zig build test
```

## Before Any Run

1. Ensure Python 3.9+ is available for documentation checks.
2. Ensure the Zig compiler (0.13.0+) is installed and accessible in `PATH`.
3. Verify that memory arenas tested for serialization do not allocate external heap memory outside their assigned arena buffer.

## Known Pitfalls

- **Timer sensitivity:** Ticks are discrete integer simulation increments, not wall-clock floats. Tests must increment ticks explicitly rather than calling sleep.
- **Snapshot validation:** Always test `restore_state` on a separate buffer to prove memory independence from the original arena.
