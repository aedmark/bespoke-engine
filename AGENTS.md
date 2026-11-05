# BeSpoke Engine

BeSpoke is a bespoke game development language and standalone simulation engine ("Engine-as-Spine") written in Zig, designed from the ground up for systemic, emergent, and narrative game simulations.

This is the canonical instruction file for coding agents. `CLAUDE.md` imports it; do not duplicate these rules in tool-specific files. Project facts belong in the documents linked below, not in an agent's private memory.

## Start here

1. Read `docs/HANDOFF.md` for the current state, active work, and gotchas.
2. Read the relevant roadmap item in `ROADMAP.md` and the parts of `docs/ARCHITECTURE.md` and `docs/TESTING.md` that apply.
3. Inspect `git status` and recent history. Do not overwrite work you did not create.
4. Verify important inherited claims before relying on them. Use the fastest relevant check first.
5. State the intended scope briefly, then work on one independently reviewable change at a time.

If the repository is new or unfamiliar, read `README.md` and `docs/README.md` first.

## While working

- Reference roadmap or issue IDs where one exists (`P<phase>-<nn>`). Do not invent an ID for an incidental fix.
- Keep changes scoped. Do not mix opportunistic refactors with requested work.
- Preserve user changes. Never reset, clean, or rewrite history without explicit permission.
- Record an architectural decision in `docs/DECISIONS.md` (`D-NNN`) when a design choice or trade-off is accepted.
- Update documentation in the same change when behaviour, interfaces, commands, risks, or project structure change.
- Prefer enforcement to prose: important invariants should have a test, type, or runtime check.
- Treat external script input as untrusted at boundary layers.

## Finishing a change

1. Run the checks appropriate to the change, following `docs/TESTING.md`. Record failures and anything not run.
2. Review the diff for unrelated edits, generated files, credentials, stale names, and documentation drift.
3. Update `docs/HANDOFF.md` if work will continue in another session or if the repository's current state changed.
4. Update the roadmap item, decision record, architecture, security notes, and changelog only when their documented update trigger applies (see `docs/README.md`).
5. Run `python3 tools/check_docs.py` and report the result.

## Working agreement

- Default branch: `main`.
- Working branch pattern: `feature/<topic>`.
- Commit format: Imperative present tense, referencing roadmap IDs where applicable.
- Release scheme: Semantic versioning (`0.1.0-dev`).

Never force-push, rewrite shared history, or delete production data without explicit permission.

## Maintainer preferences

- **Writing:** Clear, concise, system-first terminology. Avoid bloated abstractions.
- **Code comments:** Explain *why* an invariant holds, especially regarding memory layout, arena boundaries, and tick mechanics.
- **Engine scope:** Keep BeSpoke focused on narrative/systemic simulation. Do not dilute into a generic 3D physics sandbox.

## Names and terms

| Canonical term | Meaning | Formerly / not to be confused with |
| --- | --- | --- |
| BeSpoke Engine | The entire runtime, language compiler, and simulation spine | Generic scripting plugin |
| Engine-as-Spine | Architectural model where VM is `main()` and owns clock/entities/state | Embedded scripting in Unity/Godot |
| Fact | Flat 4-tuple relational row `(subject, relation, object, expires_at_tick)` | OOP object property |
| Routine | Fiber-based entity execution flow suspended by `wait` | Thread or frame callback |
| Cue | Discrete external or systemic event triggering handlers | Godot signal / Unity event |

## Layout

| Path | Purpose |
| --- | --- |
| `AGENTS.md` | Canonical agent instructions |
| `CLAUDE.md` | Single-line import of AGENTS.md |
| `README.md` | Project overview, tenets, and getting started |
| `ROADMAP.md` | Planned work with stable IDs |
| `script_spec.md` | Vertical slice DSL syntax specification |
| `whitepaper.md` | Foundational design vision document |
| `docs/README.md` | Documentation map and update triggers |
| `docs/HANDOFF.md` | Current state, next steps, gotchas, and bounded session history |
| `docs/ARCHITECTURE.md` | Components, boundaries, invariants, state, and failure modes |
| `docs/DECISIONS.md` | Append-only architectural and product decisions; open questions |
| `docs/TESTING.md` | Test strategy, commands, limitations, and environment recipes |
| `docs/SECURITY.md` | Assets, trust boundaries, secret handling, and reporting |
| `docs/CONTRIBUTING.md` | Human and agent contribution workflow |
| `docs/CHANGELOG.md` | User-visible release notes |
| `docs/archive/` | Historical material no longer current |
| `tools/check_docs.py` | Documentation consistency checks |

## Engineering conventions

- **Language:** Zig (0.13+) for runtime and compiler; Python 3 stdlib for documentation tooling.
- **Dependencies:** Zero external C/C++ or LLVM dependencies for the core compiler and VM. Optional Raylib or Sokol C bindings strictly for peripheral display.
- **Memory:** Contiguous arena allocation for world state; zero raw pointers inside serialized fact structures.
- **Timing:** Pure discrete tick clock (e.g. 20 or 60 Hz). No floating-point delta accumulation in core simulation logic.

## Environments

| Environment | Can access | Cannot access / caveats |
| --- | --- | --- |
| Local Linux x86_64 | Local filesystem, Zig toolchain, Python 3 | No GPU requirement for headless simulation |

## Run and verify

- Documentation check: `python3 tools/check_docs.py`.
- Unit tests: `zig test src/world.zig`.
- Full build and test: `zig build test`.
