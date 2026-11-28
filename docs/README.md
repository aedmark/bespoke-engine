# Documentation Map

This directory stores durable project knowledge for the BeSpoke Engine. Each fact has one authoritative home; other documents link to it instead of copying it.

## Audiences and Ownership

| Document | Primary audience | Owns | Does not own |
| --- | --- | --- | --- |
| [`../README.md`](../README.md) | Users and newcomers | Purpose, vision, and quick entry points | Internal workflow or session state |
| [`../AGENTS.md`](../AGENTS.md) | Coding agents and maintainers | Standing working rules and repository conventions | Feature history or design rationale |
| [`../ROADMAP.md`](../ROADMAP.md) | Maintainers and contributors | Planned scope and status | Detailed implementation notes |
| [`HANDOFF.md`](HANDOFF.md) | The next work session | Current state, active context, immediate next steps | Permanent design rules |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Developers | System shape, interfaces, invariants, data flow | Chronological history |
| [`API.md`](API.md) | Zig host authors | Supported `bespoke` namespaces, symbols, methods, and stability boundary | Internal engine implementation or script syntax |
| [`DECISIONS.md`](DECISIONS.md) | Future decision-makers | Rationale and alternatives for durable choices, plus held tensions | Routine implementation detail |
| [`TESTING.md`](TESTING.md) | Contributors and release owners | Verification commands, coverage boundaries, known pitfalls | A duplicate of current test results |
| [`COMPATIBILITY.md`](COMPATIBILITY.md) | Game authors and host maintainers | Released `.bspk` and `.sav` version guarantees, failures, and fixture rules | Semantic release procedure or API stability |
| [`SECURITY.md`](SECURITY.md) | Users and developers | Sensitive assets, trust boundaries, reporting, secure defaults | Full operational incident history |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Contributors | Setup, change, review, and submission workflow | Agent-only instructions |
| [`CHANGELOG.md`](CHANGELOG.md) | Users | Released and unreleased user-visible changes | Commit-by-commit history |
| [`state.html`](state.html) | Newcomers and players, and development teams evaluating the engine | What the engine can do today: every capability in plain language with an "Under the hood" line, the language, platforms, performance, demos, limits, and what is next. Update it with each release | Design rationale (DECISIONS), internals (ARCHITECTURE), or session state (HANDOFF) |
| [`GLOSSARY.md`](GLOSSARY.md) | Authors, contributors, and copy writers | Engine and language terms in plain language, and which word to use | Process terms (AGENTS) or syntax (`script_spec.md`) |
| [`AUTHORING.md`](AUTHORING.md) | Game authors | Learning order for the script language, walkthroughs, testing, and the host API contract | Complete syntax (`script_spec.md`) or design rationale |
| [`FIRST_GAME.md`](FIRST_GAME.md) | First-time game authors | Executable tutorial from `bespoke init` to a static HTML upload | Language reference or hosting credentials |
| [`BENCHMARKS.md`](BENCHMARKS.md) | Contributors and release owners | Simulation benchmark method and browser artifact budgets | Performance guarantees for a full game or any particular device |
| [Editor setup](../editors/vscode/README.md) | Game authors | Install and regenerate the TextMate syntax grammar | Compiler diagnostics or language semantics |
| [`SEPARATION.md`](SEPARATION.md) | Developers and auditors | Engine / proof separation rule, classification rubric, audit and extraction method, checks, baseline inventory | Decision rationale (DECISIONS) or task status (ROADMAP) |
| [`runbooks/studio-hand-test.md`](runbooks/studio-hand-test.md) | The maintainer and Studio contributors | The Studio hand-test pass: workspace, open and save, play, each editor, export, and failures, judged by `git diff` on scratch copies, with a results table | Automated Studio checks (TESTING) |
| [`runbooks/release-hand-test.md`](runbooks/release-hand-test.md) | Release owners and the maintainer | The hand-test pass before a release: desktop proofs, listening, browser builds, export, the hand-uploaded site (maintainer only), macOS CI, and its results table | Automated suites and commands (TESTING) |
| [`manual.html`](manual.html) | Developers and agents | Standalone 3x interactive manual & developer guide (What, How, Why) | Raw Markdown sources |

## Where the Code Lives

`src/` and `tools/` are flat folders, and their paths are cited throughout the docs and decisions, so they stay put. This map groups them by role. `AGENTS.md` lists the top-level folders.

**`src/`, the engine (exported as the `bespoke` module by `src/root.zig`):**

| Role | Files |
| --- | --- |
| The world and the clock | `world.zig` (the fact arena), `vm.zig` (fibers, cues, rules), `bytecode.zig`, `dice.zig`, `limits.zig`, `reserved.zig` (the engine's relation names) |
| The language | `compiler.zig` and `compiler/` (`lexer`, `parser`, `codegen`, `includes`, `diagnostic`) |
| Rooms and movement | `spatial.zig` (waypoints, walks, hotspots), `grid.zig` (cells and fire, smoke, water) |
| Story systems | `dialogue.zig`, `command.zig` (typed commands), `phrase.zig`, `hint.zig` (goals), `decision.zig`, `value.zig`, `dilemma.zig`, `agency.zig`, `society.zig`, `duel.zig`, `spell.zig`, `draft.zig` (musical drafts), `container.zig` (things that wear out) |
| Time | `hypervisor.zig` (branch worlds), `temporal_snapshot.zig` |
| Art and sound | `image.zig`, `art_import.zig`, `png.zig`, `qoi.zig`, `audio.zig`, `mml.zig`, and `display.zig` with `display/` (canvas, renderer, font, panels, layout) |
| Files on disk | `package.zig` (`.bspk`), `save.zig` (`.sav`), `list_writer.zig` |
| Hosts | `host.zig` (the host kit), `runner.zig` (the stock runner and window), `main.zig` (the `bespoke` CLI), `repl.zig`, `scaffold.zig` and `scaffold/` (`bespoke init`), `wasm.zig` (the browser runtime), `wasm_engine.zig` (the engine's own browser module) |
| Tests kept in the engine | `authoring_guide_test.zig` (keeps `docs/AUTHORING.md` true) |

**`tools/`, the scripts around the engine:**

| Role | Files |
| --- | --- |
| Build pages and games | `build_site.py` (showcase and proof pages, with `proof_page.js`, `engine_audio.js`, `site_gallery.json`), `build_studio.py`, `build_sunken_vault.py`, `build_lantern_watch.py`, `pack_game_page.py`, `build_editor_grammar.py`, `manual.py` |
| Check the repository | `check_docs.py` (runs the next two), `check_third_party.py` (with `third_party_terms.json` and `third_party_baseline.json`), `check_separation.py` (with `separation_baseline.json`), `check_conformance.py`, `check_version.py`, `check_web_budgets.py` (with `web_budgets.json`), `check_tutorial.py`, `check_template_deps.sh` |
| Drive a browser | `wasm_smoke.js`, `browser_smoke.js`, `studio_smoke.js` (Studio checks also live in `studio/check_wasm.js`) |
| Release and publish | `package_linux_release.py`, `package_browser_release.py`, `release_archive.py`, `check_linux_release.py`, `deploy_site.py` |

## Update Triggers

Update documents because a relevant fact changed, not merely because a session ended.

| Change | Required documentation |
| --- | --- |
| User-visible behaviour | README if onboarding changed; CHANGELOG |
| Component, interface, dependency, or data-flow change | ARCHITECTURE |
| Durable tradeoff or reversal, or a tension held or resolved | DECISIONS; mark the old decision superseded, or resolve the held tension |
| Test command, coverage, fixture, or environment change | TESTING |
| Secret, trust boundary, sensitive data, or reporting-path change | SECURITY |
| Work pauses with context another session needs | HANDOFF |
| Contribution or release workflow change | CONTRIBUTING and, if agents are affected, AGENTS |
| New planned work | ROADMAP, with origin and acceptance evidence |

## Optional Documents

Create these only when the project needs them, and add them to the tables above:

- `docs/api/` for stable public interfaces, preferably generated from executable schemas where practical.
- `docs/runbooks/` for repeatable operational procedures, each with prerequisites, rollback, and verification.
- `docs/data/` for schemas, retention, migrations, and compatibility guarantees.
- `docs/incidents/` for sanitized incident reviews and follow-up actions.
- `SUPPORT.md`, `CODE_OF_CONDUCT.md`, or licensing/contributor policy for public projects.

## Style and Evidence

- Lead with the reader's task or the current truth.
- Use exact commands and repository-relative paths; avoid screenshots for procedures when text will remain searchable.
- Label examples as examples. Do not make sample credentials, hosts, or IDs look real.
- Date volatile observations and identify the environment or commit when it affects reproducibility.
- Link to the source of truth instead of restating it. If duplication is necessary, identify which copy is canonical.
- Keep secrets, personal information, private URLs, and raw production data out of documentation and fixtures.
