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
| Separation lint | Names declared by each proof (cast, props, marks, scenes, drafts, and `lookup_entity` literals) must not appear in non-test `src/` code beyond a committed baseline; the baseline may only shrink | In place (P32-06): `python3 tools/check_separation.py`, also run by `tools/check_docs.py` |
| Characterization | Each proof's headless transcript matches a committed golden file byte for byte | In place (P32-07): `zig build test-proofs`; final-state digest deferred to P32-16 |
| Audio characterization | Every effect, note, track, crossfade, and scene track choice hashes as in `proofs/golden/audio.txt` | In place (P32-02d): `zig build test-proofs` |
| Browser characterization | Each proof deck, driven through a fixed event script, shows the frames, facts, ticks, and banners in `proofs/golden/wasm.txt` | In place (P32-04): `zig build test-proofs` |
| Render characterization | Each proof scene draws the pixels hashed in `proofs/golden/render.txt` | In place (P32-02a): `zig build test-proofs` |
| Second-theme tests | Each extracted mechanic runs under a second, unrelated configuration | Per extraction |
| Review checklist | No proof names in new engine code; new engine code named by function; proof keeps only content and assertions | Every change |

**Separation lint (P32-06).** `tools/check_separation.py`, stdlib Python like the other tools. It parses names from each proof's embedded script (scene, cast, props, marks, entity, and draft declarations) and `lookup_entity("...")` literals, skips names under four characters and a two-entry generic list (`Player`, `Scene`, each with a recorded reason), blanks out top-level `test` blocks with brace matching that ignores strings and comments, and counts whole-word matches in `src/**/*.zig`, comments included. Counts per file and proof are compared with `tools/separation_baseline.json`: more is an error, fewer is a warning to lower the baseline. `--report` lists every hit as `file:line`; `--update-baseline` only lowers counts unless `--accept-increase` is given. A name declared by two proofs (`Guybrush`) counts once for each. Tests: `tests/test_check_separation.py`.

**Characterization (P32-07).** `proofs/golden_test.zig` runs each proof's headless path into a buffer and compares it byte for byte with `proofs/golden/<proof>.txt`. No normalization is needed: the runs are deterministic (two consecutive runs of every proof were identical, 2026-11-09). On a mismatch the test prints the first differing line and writes `proofs/golden/<proof>.actual.txt` (gitignored). Regenerate with `zig build test-proofs -Dupdate-goldens` and review the diff; that is an explicit, reviewed change. The planned final fact-table digest is still open: each `run_headless` owns its world internally, and P32-16 did not change that. The transcripts already print each step's checked state.

## Baseline inventory (2026-11-09)

Leak hits: occurrences of each proof's declared names in non-test engine code, from a one-off survey before the lint existed. The committed source of truth is now `tools/separation_baseline.json` (339 hits after P32-06 removed 8 example comments from `world.zig`, `vm.zig`, `draft.zig`, and `parser.zig`, which are now at zero).

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
| `VillageSimulation`: needs, witnesses, rumors, justice | `proofs/village.zig` | Engine mechanic (done: `src/society.zig`, P32-05) |
| `DialogueDuelSystem`: challenge/response knowledge base, learning, mood and inquiry fatigue | `proofs/sword_fighting.zig` | Engine mechanic (done: `src/duel.zig`, P32-17) |
| `get_latest_say_message_since`, `execute_look_at`, `SayLog`, `act`, `tick` | dott, darko, loom | Host kit (also fixes the stale cue-index bug in HANDOFF) |
| History, scrub, rewind, and save-action handling in each interactive loop | tavern, spitting, gk3, goat, village, loom | Host kit (interactive scaffold with proof hooks) |
| `run_initial_statements`, `place`, `has_state` | loom (and inline variants elsewhere) | Host kit |
| `get_*_look_description` fallback text | dott, darko | Proof content; belongs in each script's `LooksAt` handlers |
| `evaluate_*` outcome checks | every proof | Proof assertion (stays) |
| Hypervisor vocabulary (`Artifact of Metal`, vortex, the Manipulated Dead) | `src/hypervisor.zig`, `src/vm.zig` comments | Leak in naming; audit whether the API is generic under other names |

## Audit findings (2026-11-09)

Audits P32-08 to P32-15, run against `main` at `29f89ae` with `python3 tools/check_separation.py --report`, a scan for name-free leaks (`RenderFrame` fields, relations read by `DisplayBridge.capture_frame`, `UserAction` variants, SFX and music kinds, renderer theme flags), and a read of every non-runner function in each proof. "Hits" are lint hits; follow-ups name the roadmap item that removes the finding.

### Cross-cutting findings

These recur in most proofs and are handled once, not per proof.

| Finding | Where | Class | Follow-up |
| --- | --- | --- | --- |
| Scene themes chosen by scene-name substring (20 `is_*_scene` flags), backdrops, prop art keyed by hotspot name, actor tokens keyed by entity name | `src/display/renderer.zig` `render_frame` | Theme hook | Done (P32-02b, D-039): `proofs/art.zig` |
| Scenario music tracks and scene-name track mapping; scenario SFX (`goat_bleat`, `toilet_flush`, `snip_shears`, `wood_chop`, `horn`) | `src/audio.zig` | Theme hook | Done (P32-02d, D-040): `proofs/art.zig` soundtrack |
| Scenario `UserAction` variants (`spit_contest_spit`, `sound_horn`, `drink_green_drink`, `tamper_flags`, `darko_follow_conduit`) bound to global letter keys, and raw `SDL_GetKeyboardState` hotkeys in proof loops | `src/display/renderer.zig` `poll_events`; gk3 and goat loops | Theme hook (proof-registered actions and keys) | Done (P32-02c): `Theme.keys` and `UserAction.custom` |
| 41 proof-specific `RenderFrame` status fields, filled by `capture_frame` from 46 relation names, several probed under two or three spellings | `src/display.zig` | Theme hook (host-supplied status channel) | Done (P32-03, D-041) |
| Thumbnail palettes and actor colours chosen by scene and entity name | `src/save.zig` `generate_thumbnail`, `build_metadata` | Theme hook | Done (P32-03, D-041) |
| Browser decks that rebuild six proofs' worlds inside the engine | `src/wasm.zig` `load_scenario`, `trigger_catalyst`, `step_tick` | Proof content | Done (P32-04, D-042): `proofs/wasm_deck.zig` |
| Speech readers that take a cue index captured before `step_tick` (stale after the per-tick clear), look-at helpers, and cue-fire-and-tick | dott, darko, loom | Host kit | Done (P32-16) |
| History, scrub, rewind, and save-action handling copied into each interactive loop | tavern, spitting, gk3, goat, village, loom | Host kit | Done (P32-16) |
| Outcome checks that probe several spellings of one relation (`tampered` / `Tampered` / `TamperedWith`) | spitting, gk3, goat | Proof hygiene: assert the exact facts the script writes | Done (P32-19): one fact per check; scripts made consistent |
| Engine features that no proof exercises: `collapse_tangent`, `VectorConduit` / `compute_vector_conduit`, `BitemporalTransceiver`, `CausalDecayTracker`, `DreamFact`, `reject_belief` | `src/hypervisor.zig`, `src/spatial.zig`, `src/vm.zig` | Unproven engine claim | Done (P32-20, Option B): exercised across darko and dott |

### Tavern Heist (P32-08)

| Finding | Where | Class | Follow-up |
| --- | --- | --- | --- |
| 16 hits: the engine's default backdrop *is* the tavern ("TAVERN - COMMON ROOM", wine cellar), Guard/Bard/Cat tokens, tavern palette | renderer `else` branch, save | Theme hook; the engine needs a neutral default scene | P32-02 |
| `cheese_holder` and `charmed_target` fields read from `Carries` and `CharmedBy` | `src/display.zig` `RenderFrame` | Theme hook | Done (P32-03, D-041) |
| Tavern deck rebuilt in wasm | `src/wasm.zig` | Proof content | Done (P32-04) |
| No traps: the proof's behaviour lives in its script | `proofs/tavern_heist.zig` | (none) | (none) |

### Spitting Contest (P32-09)

| Finding | Where | Class | Follow-up |
| --- | --- | --- | --- |
| 29 hits: contest field theme, flag prop art and "[MOVED!]" label, Guybrush and Organiser tokens | renderer | Theme hook | P32-02 |
| Four keys and actions (spit, horn, green drink, tamper flags) owned by the engine | renderer `UserAction`, `poll_events` | Theme hook | Done (P32-02c) |
| `spit_is_thick`, `flags_tampered`, `wind_blowing`, `organiser_distracted` fields | `src/display.zig` | Theme hook | Done (P32-03, D-041) |
| `evaluate_spit_contest` decides the placement (thick spit, moved flags, wind) in Zig, not in the script | `proofs/spitting_contest.zig` | Proof content in host code; the rule belongs in the DSL | Done (P32-19): `on cue Spits(Guybrush):` writes `Placed`; the other rules the runners still assert from Zig are P32-26 |

### GK3 Cat Moustache (P32-10)

| Finding | Where | Class | Follow-up |
| --- | --- | --- | --- |
| 51 hits: hotel, garden, and bike-shop themes; Gabriel, Mosely, Buthane, and StrayCat tokens; courtyard and bike-shop music | renderer, audio | Theme hook | P32-02 |
| Six fields (`fence_taped`, `cat_startled`, `gabriel_disguised`, `bike_rented`, and others); thumbnail palette | display, save | Theme hook | Done (P32-03, D-041) |
| Twelve raw scancode hotkeys in the interactive loop | `proofs/gk3_moustache.zig` | Theme hook (proof-registered keys) | Done (P32-02c) |
| `evaluate_disguise` accepts either of two fact shapes | `proofs/gk3_moustache.zig` | Proof hygiene | Done (P32-19): asserts `Disguised(Gabriel)`; runners still assert it from Zig (P32-26) |

### Insult Sword Fighting (P32-11)

| Finding | Where | Class | Follow-up |
| --- | --- | --- | --- |
| 41 hits: High Road, Sword Master Sanctuary, and Scumm Bar themes and music; pirate, Carla, and barkeep tokens | renderer, audio, save | Theme hook | P32-02 |
| `DialogueDuelSystem`: challenge/response pairs, learned replies, tiered opponents, advantage and duel wins, inquiry fatigue with mood decay, all as relational facts | `proofs/sword_fighting.zig` | **Engine mechanic** (dialogue duel) | Done: `src/duel.zig` (P32-17, D-035); the proof keeps the insult table, relation names, and stage tuning |
| The duel builds its own candidate lists in Zig instead of using the engine's fact-guarded choices (`prune_dialogue_choices`) | `proofs/sword_fighting.zig` | Engine mechanic design input: the duel should sit on the dialogue engine | Done (P32-17): candidates are `DialogueChoice` values filtered by `prune_dialogue_choices` |
| The 16 insult, counter, and master-variant lines | `MONKEY_ISLAND_INSULTS` | Proof content | (stays) |

### Lochmarne Goat (P32-12)

| Finding | Where | Class | Follow-up |
| --- | --- | --- | --- |
| 33 hits: courtyard and crypt themes, plough and rope art, George and BillyGoat tokens, Celtic music, `goat_bleat` and `thud` SFX | renderer, audio | Theme hook | P32-02 |
| Five fields (`goat_is_tangled`, `goat_is_charging`, `goat_is_retreating`, `george_knocked_down`, `plough_moved`) | `src/display.zig` | Theme hook | Done (P32-03, D-041) |
| The interactive loop fires cues when George *arrives* at the dig or the plough; the DSL has no arrival trigger, so the rule cannot live in the script | `proofs/goat_puzzle.zig` | **Engine mechanic gap** (arrival cues) | Done (P32-18, D-036): `when <Actor> arrives at <Mark>:`; the dig, plough, and ladder rules are in the script |
| Six scancode hotkeys for scene jumps and steps | `proofs/goat_puzzle.zig` | Theme hook | Done (P32-02c) |

### Day of the Tentacle Trio (P32-13)

| Finding | Where | Class | Follow-up |
| --- | --- | --- | --- |
| `SpatialSystem.can_access_portal` branches on the entity name `"Laverne"` and the relation `TentacleDisguiseActive`; four comments describe the proof | `src/spatial.zig` | **Logic leak in core**: the guard rule must come from facts the script declares | Done (P32-03, D-041) |
| 56 hits: three era themes, Chron-o-John and flag art, cast tokens, tentacle march, three SFX | renderer, audio | Theme hook | P32-02 |
| Seven fields (`dott_tree_chopped` to `dott_puzzle_solved`) | `src/display.zig` | Theme hook | Done (P32-03, D-041) |
| `get_dott_look_description` fallback text in Zig | `proofs/dott_puzzle.zig` | Proof content; belongs in `LooksAt` handlers | Done (P32-19): table deleted, per-actor default handlers in the script |
| Item transfer, portals, and beliefs are generic engine APIs; only this proof uses them | `src/world.zig`, `src/spatial.zig`, `src/vm.zig` | Engine mechanic (correctly placed) | (none) |

### Middlesex Anomaly (P32-14)

| Finding | Where | Class | Follow-up |
| --- | --- | --- | --- |
| 27 hits: bedroom, school, and vortex themes; countdown banner; singularity modal; cast tokens | renderer | Theme hook | P32-02 |
| `darko_follow_conduit` action on the global `v` key | renderer | Theme hook | Done (P32-02c) |
| Five `darko_*` fields, `singularity_collapsed`, `tangent_active`, and the countdown; `vector_conduits` is generic | `src/display.zig` | Theme hook (countdown and conduits can be generic HUD channels) | Done (P32-03, D-041) |
| Hypervisor API and docs use the film's vocabulary (Tangent Universe, Artifact of Metal, the Manipulated Dead, vortex) for what is a branch-world mechanic | `src/hypervisor.zig`, `src/vm.zig`, `src/spatial.zig` | Leak in naming; renaming a public API needs a maintainer decision | Done (P32-21, D-044): renamed to neutral mechanic terms |
| Five hypervisor and spatial features unused by this or any proof | see cross-cutting | Unproven engine claim | Done (P32-20) |
| `get_darko_look_description` fallback text in Zig | `proofs/darko_puzzle.zig` | Proof content | Done (P32-19): table deleted, alias and default handlers in the script |

### Bell Tower (P32-15)

| Finding | Where | Class | Follow-up |
| --- | --- | --- | --- |
| 14 hits: base and belfry backdrops, `bell_tower` track, comments | renderer, audio | Theme hook | P32-02 |
| Five `bell_*` fields | `src/display.zig` | Theme hook | Done (P32-03, D-041) |
| `SayLog`, `act`, `tick`, `run_initial_statements`, `place`, `has_state` | `proofs/loom_puzzle.zig` | Host kit | P32-16 |
| `sync_reach` copies a property fact into `DistaffInput.reach`; any draft game needs it | `proofs/loom_puzzle.zig` | Engine mechanic (small: a `DistaffInput` helper) | P32-16 |
| Script, layout (`configure`), `approach_wp`, `follow_scene` | `proofs/loom_puzzle.zig` | Proof content | (stays) |

### Living Village (P32-05, done 2026-11-09)

| Finding | Where | Class | Follow-up |
| --- | --- | --- | --- |
| `VillageSimulation` | `proofs/village.zig` | Engine mechanic (D-032) | Done: `src/society.zig` (P32-05, D-034); the proof keeps names, map, roster tuning, and catalysts |
| 56 hits: village map theme, social-graph HUD panel, villager tokens; drive bars and social edges in `RenderFrame` | renderer, display | Theme hook (the HUD panel can become a generic emergent-society view) | P32-02, P32-03, P32-05 |
| Village deck and its own simulation step in wasm | `src/wasm.zig` `step_tick` | Proof content | Done (P32-04) |

## Order of work

1. **Safety net:** separation lint (P32-06) and characterization goldens (P32-07).
2. **Audits:** one per proof (P32-08 to P32-15), completed 2026-11-09; findings above.
3. **Extractions and fixes:** host kit (P32-16, done), emergent society (P32-05, done), dialogue duel (P32-17, done), arrival rules (P32-18, done), proof hygiene (P32-19, done), unproven features (P32-20, done), neutral hypervisor vocabulary (P32-21, done), one meaning for true (P32-28, done).
4. **Presentation and core purge:** theme hooks (P32-02, staged as P32-02a render goldens (done), P32-02b renderer hook (done, D-039: art in `proofs/art.zig`), P32-02c actions and keys (done), P32-02d audio (done, D-040)), core logic (P32-03, done, D-041), wasm split (P32-04, done, D-042). Phase 32's purge is complete: the lint baseline is 0. These remove most leak hits and benefit from the host kit and goldens being in place.

## Baseline changes

- 2026-11-09, 347 to 339: P32-06 ratchet while the lint was built.
- 2026-11-10, 79 to 0 (P32-04): the browser decks left `src/wasm.zig`. No engine file names a proof.
- 2026-11-10, 117 to 79 (P32-03): proof status, the guard rule, and thumbnail palettes left `src/display.zig`, `src/spatial.zig`, and `src/save.zig`. The lint now skips `proofs/art.zig` (its names belong to proof scripts) and refuses new baseline keys without `--accept-increase`.
- 2026-11-10, 132 to 117 (P32-02d): proof music and effects left `src/audio.zig` (15 hits to 0).
- 2026-11-09, 351 to 132 (P32-02b): proof art left the renderer (219 hits to 0 in that file).
- 2026-11-09, 339 to 351 (P32-19, maintainer approved): the spitting proof now looks up the script entities `Spit` and `Wind` by name, so the lint counts 12 existing engine lines in the renderer, audio, save, and wasm that use those words. No engine file changed. P32-02 to P32-04 remove them.
