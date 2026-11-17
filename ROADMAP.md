# Roadmap

Item IDs are permanent: `P<phase>-<nn>`. Never renumber; append new items at the end of their phase.
`[ ]` open · `[~]` in progress · `[x]` done · `[-]` dropped.

Every phase, 1 to 36, is done and archived in [`docs/archive/ROADMAP_2026_11.md`](docs/archive/ROADMAP_2026_11.md). The maintainer closed that roadmap on 2026-11-15. The phases below are the next era: BeSpoke 1.0 for other developers.

What the most recent phases taught:
- Phase 34 (loose ends): deferrals recorded inside finished items were real work, and each browser deck added to close one exposed a host gap (path routines started at load, walks that ignored locks, a bar the browser could not type into); the release pass itself was accepted on the maintainer's own play, with the macOS, Windows, and uploaded-site checks still unrun.
- Phase 35 (original proofs): a rewrite goes fastest as an approved draft that keeps every mechanic and transcript step and changes only names and lines; renaming turned up name collisions between proofs, and making each proof playable by hand on its own page turned up engine gaps that no transcript showed.
- Phase 36 (one presentation): once desktop and browser drew the same frame, each later browser page cost little; what still differed was host plumbing (how scripts start, how walks are planned, where doorways are), not drawing.

## Era 2: BeSpoke 1.0 for Other Developers

Goal (maintainer, 2026-11-15): BeSpoke ships as an engine and language that other developers install to make their own games, supported on Linux desktop and in the browser. macOS and Windows are not 1.0 targets. Order: the toolchain moves first, so the surface that 1.0 freezes is written once against the Zig that users will have; input hardening comes before the freeze. Q-009 (license) and Q-010 (release hosting) are answered.

## Phase 37: Toolchain and Continuous Verification

Goal: every change is checked by a machine on every push, against a current Zig, under a real version number.

- [x] P37-01 Upgrade from Zig 0.13 to the current stable Zig release. Acceptance: `zig build test`, `test-template`, `wasm-proofs`, and `wasm_smoke.js` pass on the new version; every golden in `proofs/golden/` is unchanged (or each change is explained in review); `build.zig.zon` sets `minimum_zig_version`; README, AGENTS, and TESTING name the new version; the template pins the same version. Done 2026-11-16: Zig 0.17.1, one release at a time (0.14.1, 0.15.2, 0.16.0, 0.17.1); 660 tests pass and no golden changed (D-104).
- [x] P37-02 Engine CI on Linux (GitHub Actions on push and pull request): build, `zig build test`, `test-template`, `wasm-proofs`, `wasm_smoke.js`, the Python tests, `check_docs.py`, `build_site.py --check`, and a headless Chrome run that opens a proof page from `file://`, starts its audio, and plays a deck by its solve key. Acceptance: the workflow passes on `main`, fails on a deliberately broken golden in a test branch, and its status shows in the README. Done 2026-11-16: main run 44005527938 passed every step; disposable-branch run 44004996016 rejected a changed Tavern golden at its exact line; the README shows the workflow badge.
- [x] P37-03 Versions and releases: `build.zig.zon` and a `bespoke --version` (and `bespoke-proofs --version`) report `0.1.0`; a git tag per release; release notes cut from `docs/CHANGELOG.md`'s Unreleased section and published through GitHub Releases (D-105). Acceptance: a `v0.1.0` tag exists with notes, `--version` prints it, and a test checks the CLI and `build.zig.zon` agree. Done 2026-11-16: both CLIs and the manifest report `0.1.0`; `zig build version-check` runs both binaries and rejects drift; tag `v0.1.0` and its GitHub Release carry the changelog notes.

## Phase 38: What 1.0 Promises

Goal: write down, and test, exactly what a game written today can rely on tomorrow.

- [x] P38-01 Language audit: every construct in `docs/script_spec.md` has a parser and codegen test, nothing the parser accepts is undocumented, and each known gap (cue parameters bound in the `where` guard but not the handler body, D-072) is fixed or listed as a stated limitation. Acceptance: a test table maps each spec section to its tests; README's Known Limitations matches the result. Done 2026-11-17: the specification covers every declaration, statement, condition, and mechanic directive accepted by the parser, with a section-to-test table; a comprehensive codegen fixture covers the core statement set; undocumented top-level text, body statements, malformed `wait`, and `else` now fail with a located diagnostic; the D-072 body-binding gap remains the stated README limitation.
- [x] P38-02 Compatibility policy for `.bspk` packages and `.sav` saves: which version changes a release may make, what loads old files, and what fails with a clear version error. Acceptance: D-106 and `docs/COMPATIBILITY.md`; release-produced `.bspk` v14 and `.sav` v2 fixtures in `tests/fixtures/compat/` load in engine tests; unsupported package and save diagnostics name the found version and supported range.
- [ ] P38-03 The supported Zig API: the `bespoke` module's public surface for hosts (host kit, `wasm.Deck`, display, world queries) is listed, the rest is marked internal or moved, and the deprecated D-044 aliases are removed. Acceptance: a decision (D-NNN) with the list; an API doc page generated or written from it; a test that compiles a host using only the listed surface.
- [ ] P38-04 Deprecation policy: how a name or keyword is retired across releases (warning release, then removal). Acceptance: written in `docs/CONTRIBUTING.md` and referenced by P38-02 and P38-03.

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
