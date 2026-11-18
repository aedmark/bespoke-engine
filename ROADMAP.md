# Roadmap

Item IDs are permanent: `P<phase>-<nn>`. Never renumber; append new items at the end of their phase.
`[ ]` open · `[~]` in progress · `[x]` done · `[-]` dropped.

Phases 1 through 41 are complete and archived in [the November 2026 roadmap archive](docs/archive/ROADMAP_2026_11.md). The maintainer closed the first roadmap on 2026-11-15. The remaining phase prepares BeSpoke 1.0 for other developers.

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

## Phase 42: Release 1.0

Goal: tag 1.0 with binaries, docs, and a full hand-test behind it.

- [ ] P42-01 Release artifacts: static Linux binaries for `bespoke` and the browser runtime package, attached to the GitHub Release (D-105). Acceptance: a clean machine runs the downloaded binary and `bespoke init` without a Zig install for playing, and with one for building.
- [ ] P42-02 License housekeeping (Q-009 answered: MIT, encouraging disclosure of agentic use): the license now carries its copyright line and MIT's notice condition, with disclosure of agentic use strongly encouraged (done 2026-11-15); what remains is a license for projects that `bespoke init` generates. Acceptance: `bespoke init` writes a license file or its README says why it does not.
- [ ] P42-03 The release hand-test runbook run in full on Linux and in Firefox and Chromium, every row filled in HANDOFF, and the uploaded site checked. Acceptance: no row reads "not run".
- [ ] P42-04 Tag `v1.0.0`. Acceptance: Phases 37 to 41 are done or their open items are moved past 1.0 by the maintainer, and the tag's notes list what 1.0 promises (P38).
