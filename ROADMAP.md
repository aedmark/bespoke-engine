# Roadmap

Item IDs are permanent: `P<phase>-<nn>`. Never renumber; append new items at the end of their phase.
`[ ]` open · `[~]` in progress · `[x]` done · `[-]` dropped.

Phases 1 through 38 are complete and archived in [the November 2026 roadmap archive](docs/archive/ROADMAP_2026_11.md). The maintainer closed the first roadmap on 2026-11-15. The remaining phases prepare BeSpoke 1.0 for other developers.

What the most recent phases taught:
- Phase 34 (loose ends): deferrals recorded inside finished items were real work, and each browser deck added to close one exposed a host gap (path routines started at load, walks that ignored locks, a bar the browser could not type into); the release pass itself was accepted on the maintainer's own play, with the macOS, Windows, and uploaded-site checks still unrun.
- Phase 35 (original proofs): a rewrite goes fastest as an approved draft that keeps every mechanic and transcript step and changes only names and lines; renaming turned up name collisions between proofs, and making each proof playable by hand on its own page turned up engine gaps that no transcript showed.
- Phase 36 (one presentation): once desktop and browser drew the same frame, each later browser page cost little; what still differed was host plumbing (how scripts start, how walks are planned, where doorways are), not drawing.
- Phase 38 taught that retiring source names and preserving serialized files require separate compatibility rules.

## Era 2: BeSpoke 1.0 for Other Developers

Goal (maintainer, 2026-11-15): BeSpoke ships as an engine and language that other developers install to make their own games, supported on Linux desktop and in the browser. macOS and Windows are not 1.0 targets. Order: the toolchain moves first, so the surface that 1.0 freezes is written once against the Zig that users will have; input hardening comes before the freeze. Q-009 (license) and Q-010 (release hosting) are answered.

## Phase 39: Hardening Untrusted Input

Goal: no script, package, save, score, or typed line can crash the engine; bad input gives an error.

- [ ] P39-01 Fuzzing harnesses for the lexer and parser, codegen, the `.bspk` loader, the `.sav` loader, MML scores, and the command interpreter, run in CI for a fixed time budget, with a corpus checked in. Acceptance: each harness runs in CI; every crash found becomes a fix with its input added as a regression test.
- [ ] P39-02 Resource limits written down and enforced: facts, entities, fibers, script size, package size, save size, wasm heap. Acceptance: `docs/SECURITY.md` lists each limit with the code that enforces it, and a test hits each limit and gets an error, not a panic.
- [ ] P39-03 A real vulnerability reporting channel (GitHub private advisories or an address) in `docs/SECURITY.md`, and the template stops defaulting its engine fetch to `main` once releases exist. Acceptance: the channel is named; the template's CI pins a release tag.

## Phase 40: The Author's Experience

Goal: a developer new to BeSpoke can write, debug, and publish a small game without reading the engine source.

- [ ] P40-01 Compiler diagnostics with file, line, column, the source line, and a caret, plus a suggestion where one is clear (a misspelt keyword or name). Acceptance: `bespoke check` prints them; tests cover each error kind's message.
- [ ] P40-02 A tutorial from `bespoke init` to a published browser page, whose steps CI runs as written. Acceptance: the tutorial in `docs/`; a CI job follows it and fails if a step breaks.
- [ ] P40-03 Editor support: a syntax-highlighting grammar for `.bespoke` files generated from the lexer's keyword table. Acceptance: the grammar in the repo, a test that it lists every keyword, and install notes.

## Phase 41: Scale

Goal: know how big a BeSpoke game can be before 1.0, and say so.

- [ ] P41-01 Benchmarks: facts, entities, fibers, and ticks per second on Linux and in the browser, with budgets for the wasm module size and page weight. Acceptance: `zig build bench` prints results; CI fails when a budget is exceeded.
- [ ] P41-02 A reference game larger than the proofs (at least ten scenes, a society, typed commands, saves), built only on the supported API of P38-03, used to revisit Q-002 (fact query indexing). Acceptance: the game runs headless with a golden and in the browser; a decision on indexing (D-NNN) cites its benchmark numbers.

## Phase 42: Release 1.0

Goal: tag 1.0 with binaries, docs, and a full hand-test behind it.

- [ ] P42-01 Release artifacts: static Linux binaries for `bespoke` and the browser runtime package, attached to the GitHub Release (D-105). Acceptance: a clean machine runs the downloaded binary and `bespoke init` without a Zig install for playing, and with one for building.
- [ ] P42-02 License housekeeping (Q-009 answered: MIT, encouraging disclosure of agentic use): the license now carries its copyright line and MIT's notice condition, with disclosure of agentic use strongly encouraged (done 2026-11-15); what remains is a license for projects that `bespoke init` generates. Acceptance: `bespoke init` writes a license file or its README says why it does not.
- [ ] P42-03 The release hand-test runbook run in full on Linux and in Firefox and Chromium, every row filled in HANDOFF, and the uploaded site checked. Acceptance: no row reads "not run".
- [ ] P42-04 Tag `v1.0.0`. Acceptance: Phases 37 to 41 are done or their open items are moved past 1.0 by the maintainer, and the tag's notes list what 1.0 promises (P38).
