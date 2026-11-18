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

## Phase 43: The Band Rule Where Proofs Are Drawn

Goal: make the D-124 message-band rule measure what players see on every surface, rather than one layout at one size, and keep proof layouts from drifting away from it. Origin: the ranked follow-up review after the band check landed (2026-11-18, session 95). Items are in value order.

- [x] P43-01 Stage every proof's host layout in the render golden and its band check. Each proof's own public layout function places the marks, props, exit marks, and cast starts its script does not, so neither the hashes nor the band rule keeps drawing a scene no player sees. Done 2026-11-18 (session 95): `stage_host` in `proofs/render_golden_test.zig` calls nine host layouts; `spitting_contest.stage` is shared by both runners, and the Grog and Weathercock layouts are public. The Well of Three Tides is staged from its script alone because the script declares every mark and prop. Staging changed 97 `render.txt` lines and 11 deck 3 `wasm.txt` lines with no transcript change, and the check found The Living Village's cottages marker at 540, which moved onto its mark's row (D-124).
- [x] P43-02 Record what the frame actually draws, and list the allowed backdrop overflows. Done 2026-11-18 (session 96): `Canvas.RectProbe` records every rectangle, line, circle, and sprite with its layer and, for a prop, its name; the renderer labels props, marks, actors, walkways, backdrops, chrome, and overlays, and `check_band` measures prop art by the shapes it drew while skipping the exempt backdrop and the window's own layers by kind. The backdrop exemption is the `.backdrop` layer rather than a list of shapes, because the village roof and Beacon Hill lights are drawn as many rectangles. Its first run measured mark discs and people painting the band's first rows, held open as Q-013, which moved the affected marks up one world unit on 2026-11-18 (session 97) and extended the check to marks and people.
- [ ] P43-03 Check the band at more than one window size. `check_band` reads one height while `message_band_top` and `world_to_screen` both derive from screen height and step the world scale at 1200 and 700 pixels; check the staged frames at 640x360 and 1920x1080 as well, without new goldens.
- [ ] P43-04 Stage hover prompts, and decide whether a dialogue panel may cover the band. No proof frame is drawn hovered, so the widest prompts never face the check; the dialogue panel has no recorded rule, which needs a decision or an open question first.
- [ ] P43-05 Apply the band check to the Wasm deck golden through one shared helper. The browser decks stage their own configure and progress beats; D-097 draws both surfaces at 1280x720, so one helper can enforce the rule there too.
- [ ] P43-06 Make the band check tamper-evident. Deleting the check's call leaves every hash unchanged, so count checked frames against the lines each golden records.
- [ ] P43-07 Derive the band numbers quoted in documentation, or stop quoting them. 504, 582, and the prop marker limits appear in D-123, D-124, TESTING, and HANDOFF; `check_docs.py` can compare them with `message_band_top(720)`.
- [ ] P43-08 Add a clearance budget per scene. The check passes a prop whose marker ends one pixel above the band though its name then flips and its prompt has nowhere to sit; report each scene's smallest clearance so crowded rooms show up before they fail.
