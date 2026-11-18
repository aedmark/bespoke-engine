# Roadmap

Item IDs are permanent: `P<phase>-<nn>`. Never renumber; append new items at the end of their phase.
`[ ]` open · `[~]` in progress · `[x]` done · `[-]` dropped.

Phases 1 through 41 are complete and archived in [the November 2026 roadmap archive](docs/archive/ROADMAP_2026_11.md). The maintainer closed the first roadmap on 2026-11-15. Phase 42 covers BeSpoke 0.2.0; 1.0 remains deferred (D-118).

What the most recent phases taught:
- Phase 34 (loose ends): deferrals recorded inside finished items were real work, and each browser deck added to close one exposed a host gap (path routines started at load, walks that ignored locks, a bar the browser could not type into); the release pass itself was accepted on the maintainer's own play, with the macOS, Windows, and uploaded-site checks still unrun.
- Phase 35 (original proofs): a rewrite goes fastest as an approved draft that keeps every mechanic and transcript step and changes only names and lines; renaming turned up name collisions between proofs, and making each proof playable by hand on its own page turned up engine gaps that no transcript showed.
- Phase 36 (one presentation): once desktop and browser drew the same frame, each later browser page cost little; what still differed was host plumbing (how scripts start, how walks are planned, where doorways are), not drawing.
- Phase 38 taught that retiring source names and preserving serialized files require separate compatibility rules.
- Phase 39 taught that input limits need boundary tests and a CI pin needs a generated project build against the exact tag.
- Phase 40 taught that authoring tools stay in sync when the editor grammar comes from the lexer and CI runs the tutorial itself.
- Phase 41 taught that a synthetic load shows scaling costs, while a reference game shows whether they justify changing the engine.

## Era 2: BeSpoke 1.0 for Other Developers

Goal (maintainer, 2026-11-15): BeSpoke ships as an engine and language that other developers install to make their own games, supported on Linux desktop and in the browser. macOS and Windows are not 1.0 targets. Order: the toolchain moves first, so the surface that 1.0 freezes is written once against the Zig that users will have; input hardening comes before the freeze. Q-009 (license) and Q-010 (release hosting) are answered.

## Phase 42: Release Preparation

Goal: prepare 0.2.0 with binaries, docs, and a full hand-test. Tagging or publishing requires separate approval. The 1.0 milestone remains deferred.

- [x] P42-01 Prepare 0.2.0 release artifacts: a static Linux x86_64 CLI, a separate SDL2 desktop download, and the browser runtime package (D-119). The extracted static download runs source and compiled scripts and scaffolds a project in a clean Linux filesystem without Zig or SDL2; the generated project builds and passes its tests with Zig and SDL2 development libraries installed (2026-11-18). Attach the artifacts to GitHub Releases only when publication is approved (D-105, D-118).
- [x] P42-02 License housekeeping: the engine retains its MIT license with voluntary agentic-use disclosure (Q-009). `bespoke init` writes the verbatim engine notice to `LICENSE-BeSpoke`; the generated README explains why no project-wide license is assigned and how to redistribute the notice (D-120).
- [x] P42-03 Release hand-test on Linux, Firefox, and Chromium. HANDOFF records the baseline, local browser checks, 375 px showcase fix, and maintainer sign-off on desktop play, listening, and the uploaded site (2026-11-18), with remaining coverage limits.
- [ ] P42-04 Tag `v1.0.0` when the maintainer approves that milestone. Acceptance: Phases 37 to 41 are done or their open items are moved past 1.0 by the maintainer, and the tag's notes list what 1.0 promises (P38). Deferred beyond 0.2.0 (D-118).
