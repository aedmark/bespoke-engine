# Engine / Proof Separation

How the project keeps engine mechanics in `src/` and proof-of-concept code in `proofs/`, and the method for auditing, testing, and extracting each proof. Decisions: [D-031](DECISIONS.md) (module boundary) and [D-032](DECISIONS.md) (emergent society is an engine mechanic). Work items: Phase 32 in [ROADMAP.md](../ROADMAP.md).

## The rule

The engine provides mechanics. A proof employs them and demonstrates that they work. Nothing in `src/` names a proof, its entities, its scenes, or its art, and nothing generic enough for a second game stays trapped in `proofs/`.

Separation fails in two directions, and every audit checks both:

| Direction | Symptom | Example today |
| --- | --- | --- |
| **Leak** (proof content in the engine) | An engine file names a proof's entity, scene, or theme, or branches on it | `SpatialSystem.can_access_portal` special-cases `"Laverne"`; `RenderFrame` carries `goat_is_tangled` |
| **Trap** (engine mechanic in a proof) | A proof contains logic another game would need, parameterized only by that proof's names | `VillageSimulation` (needs, witnesses, rumors, justice); `DialogueDuelSystem` in Insult Sword Fighting |

## Classification rubric

Every unit of code found in an audit (a function, type, table, branch, or block of art) gets exactly one class.

| Class | Test | Home |
| --- | --- | --- |
| **Engine mechanic** | A second game with different names and theme would need the same behaviour. | `src/`, data-driven, named by what it does |
| **Host kit** | Reusable plumbing for driving the engine from a host program (tick and dispatch, reading speech, history and rewind, the interactive loop). | `src/` host-support module, no game names |
| **Theme hook** | Presentation that varies per game (backdrops, props, tokens, music, footer hints, keys) and that the engine must call without knowing the game. | Interface in `src/`; implementations in `proofs/` |
| **Proof content** | Names, scripts, text, art, layout, and tuning specific to one proof. | `proofs/` (scripts in the DSL where possible) |
| **Proof assertion** | Checks that the proof achieved its outcome (`evaluate_*_solved`, headless step checks). | `proofs/` |

Tie-breakers: if a unit mixes classes, split it before moving it. If the only reason to keep logic in Zig is that the DSL cannot express it yet, classify it as proof content and record the missing language feature as a roadmap item rather than moving the logic into the engine.

## Audit procedure (per proof)

Each proof audit is one roadmap item and produces one short findings table in this document. It changes no code.

1. **Inventory leaks.** Run the separation lint (below) and read each hit in non-test engine code. Include comments, which mislead even when harmless.
2. **Inventory traps.** List every type and function in the proof file other than `run_headless`, `run_interactive`, and script constants. For each, ask the rubric's second-game question.
3. **Find duplication.** Compare with the other proofs. Code copied into two or more proofs is a host-kit candidate.
4. **Classify** every finding with the rubric, and name its target home and interface.
5. **File follow-ups.** Each extraction becomes its own roadmap item with acceptance criteria. Language gaps become their own items.

## Extraction procedure (per finding)

Extraction is test-first and behaviour-preserving.

1. **Characterize.** Before touching code, capture the proof's observable behaviour (see Characterization below) and commit the golden output.
2. **Specify the interface** in the roadmap item: the engine API, its configuration data, and what the proof supplies. Ask the maintainer when the interface changes an invariant in [ARCHITECTURE.md](ARCHITECTURE.md).
3. **Extract** into `src/`, renaming by function, not by theme (`EmergentSociety`, not `VillageSimulation`).
4. **Rewire the proof** as a client of the new API.
5. **Verify** with three checks: the characterization output is unchanged, the new engine module has unit tests with no proof names, and a **second-theme test** drives the module with a different roster or setting. A mechanic that works for only one theme has not been extracted.
6. **Ratchet** the lint baseline down by the hits removed.

## Checks

| Check | What it enforces | Status |
| --- | --- | --- |
| Module boundary | `src/` cannot import `proofs/` (compiler: "import of file outside module path") | In place (P32-01) |
| Separation lint | Names declared by each proof (cast, props, marks, scenes, drafts, and `lookup_entity` literals) must not appear in non-test `src/` code beyond a committed baseline; the baseline may only shrink | Planned (P32-06) |
| Characterization | Each proof's headless run produces a normalized transcript and final-state digest that matches a committed golden file | Planned (P32-07) |
| Second-theme tests | Each extracted mechanic runs under a second, unrelated configuration | Per extraction |
| Review checklist | No proof names in new engine code; new engine code named by function; proof keeps only content and assertions | Every change |

**Separation lint design (P32-06).** `tools/check_separation.py`, stdlib Python like the other tools. It parses names from each proof's embedded script and `lookup_entity("...")` literals, ignores a short list of generic words, scans `src/**/*.zig` up to the first `test "` block, and compares hit counts per file and proof against `tools/separation_baseline.json`. More hits than baseline is an error; fewer prints a reminder to lower the baseline. It runs in the fast test set and in `tools/check_docs.py`.

**Characterization design (P32-07).** Each `run_headless` already writes its steps to a writer. A `zig build test-proofs` test runs each proof into a buffer, strips run-varying lines (paths, timings), and also hashes the final fact table, then compares both with `proofs/golden/<proof>.txt`. Updating a golden file is an explicit, reviewed change.

## Baseline inventory (2026-11-09)

Leak hits: occurrences of each proof's declared names in non-test engine code, from a one-off run of the lint design above. Comments are included.

| Proof | Engine hits | Engine files touched |
| --- | ---: | --- |
| Tavern Heist | 16 | parser (comment), display, renderer, save, wasm |
| Spitting Contest | 29 | parser (comment), display, renderer, save, wasm |
| GK3 Cat Moustache | 51 | audio, display, renderer, save, wasm |
| Insult Sword Fighting | 41 | audio, parser (comment), display, renderer, save, wasm |
| Living Village | 56 | display, renderer, wasm |
| Lochmarne Goat | 33 | audio, display, renderer, wasm |
| Day of the Tentacle Trio | 56 | audio, display, renderer, spatial, wasm |
| Middlesex Anomaly | 27 | display, renderer, spatial, vm (comment) |
| Bell Tower | 14 | audio, display, renderer, draft (comment) |

Trap and duplication candidates found in the first survey:

| Finding | Where | Proposed class |
| --- | --- | --- |
| `VillageSimulation`: needs, witnesses, rumors, justice | `proofs/village.zig` | Engine mechanic (P32-05) |
| `DialogueDuelSystem`: challenge/response knowledge base, learning, mood and inquiry fatigue | `proofs/sword_fighting.zig` | Engine mechanic candidate |
| `get_latest_say_message_since`, `execute_look_at`, `SayLog`, `act`, `tick` | dott, darko, loom | Host kit (also fixes the stale cue-index bug in HANDOFF) |
| History, scrub, rewind, and save-action handling in each interactive loop | tavern, spitting, gk3, goat, village, loom | Host kit (interactive scaffold with proof hooks) |
| `run_initial_statements`, `place`, `has_state` | loom (and inline variants elsewhere) | Host kit |
| `get_*_look_description` fallback text | dott, darko | Proof content; belongs in each script's `LooksAt` handlers |
| `evaluate_*` outcome checks | every proof | Proof assertion (stays) |
| Hypervisor vocabulary (`Artifact of Metal`, vortex, the Manipulated Dead) | `src/hypervisor.zig`, `src/vm.zig` comments | Leak in naming; audit whether the API is generic under other names |

## Order of work

1. **Safety net:** separation lint (P32-06) and characterization goldens (P32-07).
2. **Audits:** one per proof (P32-08 to P32-15). Fast, no code changes, and they finalize the extraction list.
3. **Extractions:** host kit, emergent society (P32-05), dialogue duel, and whatever the audits add.
4. **Presentation and core purge:** theme hooks (P32-02), core logic (P32-03), wasm split (P32-04). These remove most leak hits and benefit from the host kit and goldens being in place.
