# Supported Zig API

This is the compatibility contract for Zig hosts built against the `bespoke` module (P38-03, D-107). A public Zig declaration is supported only when this page lists it. Other `pub` declarations remain reachable for engine tests and proofs, but may move without deprecation.

The preferred host boundary is `bespoke.host.Session`. The lower-level types below remain supported for custom clocks, interfaces, tests, and browser decks. Struct storage fields are internal unless this page explicitly names a field; use methods instead.

## Root conveniences

New code may use these short names:

`World`, `EntityId`, `SpatialSystem`, `VM`, `CompiledProgram`, `DisplayBridge`, and `compile_source`.

Everything else uses its namespace. Older root aliases such as `run_file`, `SaveManager`, and `TemporalHypervisor` are reachable conveniences, not supported names.

## Compiler and packages

| Namespace | Supported surface |
| --- | --- |
| `compiler` | `compile_source`, `compile_source_with`, `check_source`, `check_source_with`, `FileSource`, `script_palette`, `ScriptPalette` (P46-04), `CheckResult` and its `message` / `diagnostic` / `kind` methods (`kind`, P48-18) and `warnings` / `warning_count` fields, `CheckWarning`, `check_source_against` (P48-10), `Diagnostic`, `CompiledProgram`, `CompiledProgram.deinit`, and `CompiledProgram.identity` (P48-08) |
| `package` | `PACKAGE_MAGIC`, `PACKAGE_VERSION`, `MIN_PACKAGE_VERSION`, `save_package`, `load_package`, `save_package_file`, `load_package_file`, `version_from_bytes`, `format_unsupported_version` |
| `reserved` | `Release`, `LANGUAGE`, `AuthorRelation`, `AUTHOR_FACING`, `newer_than_language`, `engine_may_use`, `is_bookkeeping` (P48-10, D-180) |
| `phrase` | `Key`, `Entry`, `ENTRIES`, `Arg`, `Error`, `find`, `entry`, `text`, `validate`, `render`, `fill` (P48-09, D-179) |
| `image` | `ART_WIDTH`, `ART_HEIGHT`, `SCALE`, `MAX_COLOURS`, `TRANSPARENT`, `Colour`, `Image` and its `columns`, `frame_count`, `frame_pixel`, and `validate` methods, `Art` and its `is_empty`, `find`, `backdrop_for`, `sprite_for`, `validate`, `dupe`, and `deinit_owned` methods, `Anim`, `Step`, `Backdrop`, `Sprite` and its `frame_at` method, `Area` and `Art.area_for` (P46-05), the limits `MAX_IMAGES`, `MAX_SHEET_SIDE`, `MAX_SHEET_PIXELS`, `MAX_NAME`, and `MAX_BINDINGS`, `Error` (P46-01, P46-03). D-166 replaces indexed art with true colour in P48-12, which revises this row |
| `png` | `MAX_FILE`, `Error`, `Rgba` and its `deinit`, `decode` (P46-04) |
| `art_import` | `MapError`, `Where`, `map`, `CodeError`, `assign_codes`, `free_codes`, `write_palette_lines`, `write_image_block` (P46-04) |
| `runner` | `RunConfig` (its `input` and `print_facts` fields, P48-18), `CheckOptions`, `check_file_with`, `check_file`, `compile_file`, `run_file`, `run_bytes`, `import_art`, `ImportOptions`, `ScriptFiles` (P46-04) |

`CompiledProgram` owns its compiled data and must outlive every VM using it. Its fields, bytecode chunk, routine maps, and declaration tables are internal. Use `host.init_vm`, `host.start_script`, and `host.start_routine` instead of reading those tables.

## World and spatial state

| Namespace | Supported surface |
| --- | --- |
| `world` | `DEFAULT_ARENA_SIZE`, `EntityId`, `RelationKind`, `RelationType`, `ObjectKind` (P48-08), `Fact`, `PatternTerm`, `PatternClause`, `VariableBindings`, `World`, `QueryIterator` |
| `spatial` | `WaypointId`, `Point2D`, `Waypoint`, `Hotspot`, `SpatialSystem`, `SpatialSystem.Portal`, `SpatialSystem.TransferPolicy` |

Supported `World` methods are `init`, `deinit`, `intern_entity`, `intern_relation`, `intern_relation_kind`, `declare_object_kind`, `object_kind` (P48-08, D-178), `set_display_name`, `display_text`, `set_phrase`, `phrase_override` (P48-09, D-179), `claim_relation` (P48-10), `lookup_entity`, `lookup_relation`, `get_entity_name`, `get_relation_meta`, `fact_count`, `remember`, `forget`, `transfer_item`, `has_fact`, `find_first`, `get_property`, `query`, `find_first_match`, `find_first_match_from`, `has_multi_match`, `find_all_matches`, `get_recently_expired`, `save_state`, `restore_state`, and `clone`. `EntityId.to_int` / `from_int`, `RelationKind.to_int` / `from_int`, `QueryIterator.next`, and `VariableBindings.get` / `set` are supported.

Supported `SpatialSystem` methods are `init`, `deinit`, `add_grid`, `grid_in_room`, `find_grid`, `waypoint_cell`, `agent_cell`, `clear_hotspots`, `register_portal`, `get_portal_in_room`, `add_hotspot`, `find_hotspot_at`, `find_hotspot_at_in_room`, `count_hotspots_in_room`, `transition_actor`, `register_entity`, `walk_to`, `walk_to_with_world`, `waypoint_blocked`, `is_moving`, `has_arrived`, `get_position`, `get_current_waypoint`, `can_transfer_item`, `can_access_portal`, and `can_transfer_item_with_world`. Its graph, agent, hotspot, grid, and portal storage fields are internal.

## VM and host kit

| Namespace | Supported surface |
| --- | --- |
| `vm` | `VM`, `FiberId`, tick interval constants and `step_tick_interval_slower` / `step_tick_interval_faster` |
| `host` | `Session`, `Exit`, `AppealOutcome`, `CommandReply`, `Interpreted`, `SpeechLine`, `SpeechLog`, `ScriptSoundtrack`, `ScriptSociety`, and the functions listed below |
| `dialogue` | `View`, `Selection`, `view` |
| `command` | `Interpreter`, `WordList`, `Command` |
| `spell` | `Book`, `Spell`, `Word`, `Kind`, `Refusal`, `Outcome`, `MAX_BOOKS`, `MAX_WORDS_PER_KIND`, `MAX_SPELLS`, `resolve`, `named`, `named_text`, `knows`, `check`, `cast`, `combine` |
| `decision` | `Decision`, `Option`, `Pick`, `Clause`, `Choices`, `Stage`, `MAX_DECISIONS`, `MAX_CLAUSES`, `MAX_OPTIONS`, `MAX_PICKS`, `MAX_POINTS`, `validate`, `seed`, `triggered`, `stage_of`, `chosen`, `score_of`, `step` |

Supported direct VM methods are `fire_cue`, `select_path`, `weave_draft`, `weave_notes`, `set_dialogue_speaker`, `open_generated_dialogue`, `dialogue_view`, `choose`, `sync_dialogue`, `transition_to_scene`, `evaluates_belief`, `assert_belief`, and `reject_belief`. Construct a VM with `host.init_vm`; advance it with `host.tick` or `Session.advance`, never bare `VM.step_tick`.

Supported host functions are `init_vm`, `initialize_subsystems`, `start_script`, `start_routine`, `run_initial_statements`, `place_cast`, `player_actor`, `tick`, `run_command`, `interpret_command`, `dispatch_command`, `command_words`, `speech_lines`, `speech_this_tick`, `act`, `present`, `appeal`, `cast`, `restart_routines`, `combine`, `has_state`, `place_waypoint`, `add_exit_marks`, and `take_exit_here`.

`host.present(vm, compiled, actor, evidence, person)` records `Presented(person, evidence)` as a set fact and fires `Presents(actor, person, evidence)`; it returns whether a handler answered (P44-03). The record holds one row per distinct piece of evidence. The default typed frames `present <thing> to <thing>` and `show <thing> to <thing>` use the same action.

`host.appeal(vm, compiled, actor, person, value)` appeals to `person`'s value on the axis the entity `value` names and returns `AppealOutcome`: `.made`, `.unknown_value` when the actor does not know `<Axis> of <person>`, or `.no_dilemma` when no open dilemma of that person lists the value (P45-05, D-149). A made appeal counts at the dilemma's next weighing, records `Appealed(person, value)`, and fires `Appeals(actor, person, value)`. The default typed frame `appeal to <thing>` uses the same action for the first such person in the speaker's room.

`host.cast(vm, compiled, caster, name, target)` resolves a spell in the script's book, checks every word against what the caster knows, and fires the cue named after the spell only when the combination is accepted; it returns `spell.Outcome`, either the resolved spell or a `Refusal` (P44-04). `host.combine(vm, compiled, caster, power, element, form, target)` takes the same path for a player who builds a phrase from three words instead of naming a spell, and returns the same `spell.Outcome`. Words come from `Knows` or `Believes` about the caster, and `Rejects` overrides both.

`host.tick` steps declared decisions after agendas and fires each winner's cue for the next tick (P44-05). `decision.chosen(world, decision)` reports the option at the open decision point, or null between points; `decision.stage_of` reports `Idle` or `Done`, and `decision.score_of(world, option)` reports what an option's offered lines total now. A host that runs a table itself may call `decision.seed` once before play and `decision.step` with the compiled declarations after a tick; the choice is the set fact `Chose(Decision, Option)` and the stage is the property `DecisionState`, so save, rewind, and branch restore need no decision snapshot. Scoring reads facts and draws no random number. The trigger lines and option scores are the script's; the engine only offers, sums, and fires.

All public methods on `Session`, `SpeechLog`, and `ScriptSoundtrack` are supported. `Session` is the preferred owner of ticking, pause, rewind, save/load actions, dialogue selection, frame refresh, and temporal active-world routing. Their storage fields are internal.

`ScriptSociety.init(world, compiled, index)` selects a script declaration by zero-based source order and seeds its initial facts. Construct it once before play or before restoring a matching save. `ScriptSociety.step(vm)` runs society rules once after `host.tick`; the VM must have a spatial system and still use the original world's registries. The compiled program and registries must outlive the society. Do not reinitialize after restore, since that would reseed the saved facts. The wrapper's fields and its diagnostic chronicle are internal (P41-02).

`hint`, `value`, and `dilemma` are internal (D-176). A host asks about goals, decisions, dilemmas, and values through `host` calls; P48-19 adds one per declared feature, and until then the proofs that read those namespaces are engine code, not examples to copy.

## Display and sound

| Namespace | Supported surface |
| --- | --- |
| `display` | `DisplayBridge`, `RenderFrame`, `DisplayWindow`, `UserAction`, `StatusHook`, `RenderEntity`, `RenderWaypoint`, `RenderHotspot`, `RenderInventoryItem`, `RenderDialogue`, `Theme`, `Canvas` (with `draw_image`, P46-02), `DisplayWindow.set_art` and `DisplayWindow.animation_clock` (P46-03), `Color`, `current_score_entity`, `DisplayWindow.show_engine_facts` and `DisplayWindow.shown_facts`, `capture_debug_facts`, `story_fact_count`, `is_engine_relation` (P48-10) |
| `audio` | `AudioBridge`, `Sound`, `Soundtrack`, `SoundEffectKind`, `ChiptuneSynth` |

All public methods on `DisplayBridge`, `RenderFrame`, and `DisplayWindow` are supported. `DisplayBridge.capture_scene(world, spatial, vm, scene)` fills a frame from a named room without moving the VM (P44-06); `capture_frame` is the same call with the VM's scene. The frame is labelled as that room and carries its `#SceneScore`, so the renderer, theme, and audio treat it as that room. Capture is read-only: the VM's scene, fibers, and rules are untouched, and a host that shows a watched view keeps interaction off it. `Theme` is a host configuration record, so its callback, key, thumbnail, and soundtrack fields are supported. The frame's storage layout and the `display.renderer`, `font`, `text_layout`, `dialogue_panel`, `beats`, and `state_graph` implementation namespaces are internal. A theme or status callback uses the documented types but must not depend on unlisted renderer helpers.

## Saves and branch worlds

| Namespace | Supported surface |
| --- | --- |
| `save` | `SAVE_MAGIC`, `SAVE_VERSION`, `MIN_SAVE_VERSION`, `MAX_SLOTS`, `QUICKSAVE_SLOT`, `SaveError` (with `SaveFromOtherBuild` and `SaveNotTranslatable`, P48-08), `ProgramIdentity` and its `known` method, `format_build_mismatch`, `SaveOptions`, `SaveMetadata`, `SaveSlotInfo`, `LoadResult`, `ThumbnailPainter`, `SaveManager`, `write_save_state`, `write_save_state_with_temporal`, `read_save_state`, `read_save_state_with_temporal`, `read_save_state_for`, `read_save_state_with_temporal_for`, `inspect_save_stream`, `version_from_bytes`, and `format_unsupported_version` |
| `hypervisor` | `TemporalHypervisor`, `BranchCollapseState`, `HypervisorStepResult`, `DreamFact`, `TeleologicalDependency`, `validate_novikov_consistency`, `format_countdown` |

`SaveManager.program`, `SaveManager.last_load_restarted_routines`, `SaveMetadata.program`, and `SaveMetadata.routines_restarted` are supported fields (P48-08, D-162): a host sets the first to `compiled.identity()` so its saves name the build and its loads refuse another's. After a load whose `routines_restarted` is true, call `host.restart_routines`; `host.Session` and the stock window do both themselves. All public `SaveManager`, `SaveMetadata`, `SaveSlotInfo`, `ThumbnailPainter`, and `TemporalHypervisor` methods are supported. Hypervisor storage fields are internal. D-044's tangent, vortex, artifact, and singularity aliases were removed in P38-03; use branch, convergence, keystone, and budget-expiry names.

## Browser decks

Supported `wasm` declarations are `Deck`, `ScriptDeckOptions`, `WasmRuntime`, `WasmVerb`, `VerbCues`, `Exit`, `RgbaColor`, `BrowserEventKind`, `BrowserInputEvent`, `BrowserActionTag`, `script_deck`, `script_deck_with`, and `export_runtime`. The fields of `Deck`, `ScriptDeckOptions`, `VerbCues`, `Exit`, and `BrowserInputEvent` are supported host configuration; `WasmRuntime` fields are not.

A deck callback receives `*WasmRuntime`, but only these methods are supported: `set_banner`, `get_banner`, `active_world`, `spatial_system`, `virtual_machine`, `compiled_program`, `player`, `set_player`, `queue_message`, `answer`, `attach_hypervisor`, `clock`, `bind`, `step_tick`, `record_snapshot`, `scrub_to_tick`, `deck_action`, `trigger_catalyst`, `capture`, and `render_frame`. Runtime fields are internal.

Prefer `script_deck` or `script_deck_with` for a script-backed game. A custom `Deck.load` callback may call `load_program`; direct `WasmRuntime.init` and `deinit` are supported for an embedding host.

## Browser module exports

A page that loads a BeSpoke WebAssembly module may call these exports (D-175). They are the ones the page and smoke test from `bespoke init` use, so a generated project depends on them: `wasm_init`, `wasm_step_tick`, `wasm_get_tick`, `wasm_get_fact_count`, `wasm_render_frame`, `wasm_framebuffer_ptr`, `wasm_framebuffer_len`, `wasm_on_pointer_down`, `wasm_on_pointer_move`, `wasm_on_right_click`, `wasm_on_key_down`, `wasm_on_char`, `wasm_command_bar_focused`, `wasm_audio_render`, and `wasm_audio_sample_rate`. `tests/test_browser_exports.py` fails when one of them is not exported, or when a generated page calls an export this list omits.

Every other `wasm_*` export is internal: the showcase pages' deck, verb, dialogue, inspector, message, and animation-clock calls, and `wasm_load_scenario`, `wasm_on_touch`, and `wasm_scrub_to_tick`. A script never learns which platform runs it; a capability that differs by platform reaches scripts, if ever, as a feature fact (D-175).

## Stability rule

Supported names, signatures, and behavior follow the [deprecation policy](CONTRIBUTING.md#deprecation-policy) (P38-04, D-108). Internal declarations may change without a compatibility promise. [COMPATIBILITY.md](COMPATIBILITY.md) governs file compatibility.
