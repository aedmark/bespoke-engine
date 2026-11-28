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
| `compiler` | `compile_source`, `compile_source_with`, `check_source`, `check_source_with`, `FileSource`, `script_palette`, `ScriptPalette` (P46-04), `art_sources`, `ArtSources`, `ArtImage`, and `ArtAnimation` (P47-02, D-196), `room_sources`, `SceneRoom`, `RoomPlace`, and `ScriptLines` (P47-03, D-200), `CheckResult` and its `message` / `diagnostic` / `kind` / `file` methods (`kind`, P48-18; `file`, the included file a diagnostic is in, P48-15) and `warnings` / `warning_count` fields, `CheckWarning` and its `file` method, `check_source_against` (P48-10), `includes` with `expand`, `Expanded`, `Segment`, `Place`, and `Failure` (P48-15, D-185), `Diagnostic`, `CompiledProgram`, `CompiledProgram.deinit`, and `CompiledProgram.identity` (P48-08) |
| `package` | `PACKAGE_MAGIC`, `PRE_1_0_MAGIC`, `PACKAGE_FORMAT`, `PackageHeader`, `Section` and its `tag` / `flags` / `from_tag`, `SECTION_TAGS`, `SectionSet`, `ALL_SECTIONS`, `SECTION_REQUIRED`, `save_package`, `load_package`, `load_package_linked` (only the readers a build needs), `sections_in` (a package's sections when the module is built), `save_package_file`, `load_package_file`, `version_from_bytes`, `is_pre_1_0`, `format_unsupported_version`, `PRE_1_0_MESSAGE` (P48-17, D-187; `Section.flags`, P49-01) |
| `reserved` | `Release`, `LANGUAGE`, `AuthorRelation`, `AUTHOR_FACING`, `newer_than_language`, `engine_may_use`, `is_bookkeeping` (P48-10, D-180) |
| `phrase` | `Key`, `Entry`, `ENTRIES`, `Arg`, `Error`, `find`, `entry`, `text`, `validate`, `render`, `fill` (P48-09, D-179) |
| `image` | `ART_WIDTH`, `ART_HEIGHT`, `SCALE`, `MAX_COLOURS`, `Colour`, `Pixel` and its `opaque_colour`, `TRANSPARENT`, `from_indices`, `Image` and its `columns`, `frame_count`, `frame_pixel`, and `validate` methods, `Art` and its `is_empty`, `find`, `backdrop_for`, `sprite_for`, `validate`, `dupe`, and `deinit_owned` methods, `Anim`, `Step`, `Backdrop`, `Sprite` and its `frame_at` method, `Area` and `Art.area_for` (P46-05), `Look` and its `frame_at` method, `Part`, `MAX_PART_OFFSET`, `frame_in`, `Art.look_named` and `Art.part_for` (P48-11), `ColourCycle`, `ColourMap`, `MAX_CYCLES`, and `DEFAULT_CYCLE_INTERVAL` (P49-01, D-190), the limits `MAX_IMAGES`, `MAX_SHEET_SIDE`, `MAX_SHEET_PIXELS`, `MAX_ART_PIXELS`, `MAX_NAME`, and `MAX_BINDINGS`, `Error` (P46-01, P46-03). Pixels are RGBA with alpha 0 or 255, and `Art` holds no palette (P48-12, D-166, D-182) |
| `png` | `MAX_FILE`, `Error`, `Rgba` and its `deinit`, `decode` (P46-04) |
| `qoi` | `Error`, `HEADER_LEN`, `encode`, `decode`, `header_size`: standard QOI streams of `image.Pixel`, as the package stores art (P48-12, D-182) |
| `art_import` | `MapError`, `PixelError`, `Where`, `map`, `to_pixels` (P48-12), `CodeError`, `assign_codes`, `free_codes`, `write_palette_lines`, `write_image_block` (P46-04) |
| `runner` | `RunConfig` (its `input` and `print_facts` fields, P48-18), `CheckOptions`, `check_file_with`, `check_file`, `compile_file`, `compile_file_with` and `CompileOptions` (its `deps` field, P49-06, D-194), `run_file`, `run_bytes`, `import_art`, `ImportOptions`, `ScriptFiles` (P46-04) |

`CompiledProgram` owns its compiled data and must outlive every VM using it. Its fields, bytecode chunk, routine maps, and declaration tables are internal. Use `host.init_vm`, `host.start_script`, and `host.start_routine` instead of reading those tables.

## World and spatial state

| Namespace | Supported surface |
| --- | --- |
| `world` | `DEFAULT_ARENA_SIZE`, `EntityId`, `RelationKind`, `RelationType`, `ObjectKind` (P48-08), `Fact`, `PatternTerm`, `PatternClause`, `VariableBindings`, `World`, `QueryIterator` |
| `spatial` | `WaypointId`, `Point2D`, `Waypoint`, `Hotspot`, `SpatialSystem`, `SpatialSystem.Portal`, `SpatialSystem.TransferPolicy`, `Exit` (the type behind `host.Exit`), `art_to_world` (P47-11, D-199), and `world_to_art` (P47-03, D-200) |

Supported `World` methods are `init`, `deinit`, `intern_entity`, `intern_relation`, `intern_relation_kind`, `declare_object_kind`, `object_kind` (P48-08, D-178), `set_display_name`, `display_text`, `set_phrase`, `phrase_override` (P48-09, D-179), `claim_relation` (P48-10), `lookup_entity`, `lookup_relation`, `get_entity_name`, `get_relation_meta`, `fact_count`, `remember`, `forget`, `transfer_item`, `has_fact`, `find_first`, `get_property`, `query`, `find_first_match`, `find_first_match_from`, `has_multi_match`, `find_all_matches`, `get_recently_expired`, `save_state`, `restore_state`, and `clone`. `EntityId.to_int` / `from_int`, `RelationKind.to_int` / `from_int`, `QueryIterator.next`, and `VariableBindings.get` / `set` are supported.

Supported `SpatialSystem` methods are `init`, `deinit`, `add_grid`, `grid_in_room`, `find_grid`, `waypoint_cell`, `agent_cell`, `clear_hotspots`, `register_portal`, `get_portal_in_room`, `add_hotspot`, `find_hotspot_at`, `find_hotspot_at_in_room`, `count_hotspots_in_room`, `transition_actor`, `register_entity`, `walk_to`, `walk_to_with_world`, `waypoint_blocked`, `is_moving`, `has_arrived`, `get_position`, `get_current_waypoint`, `can_transfer_item`, `can_access_portal`, and `can_transfer_item_with_world`. Its graph, agent, hotspot, grid, and portal storage fields are internal.

## VM and host kit

| Namespace | Supported surface |
| --- | --- |
| `vm` | `VM`, `FiberId`, tick interval constants and `step_tick_interval_slower` / `step_tick_interval_faster` |
| `dice` | `Dice` with `init`, `roll`, `write`, and `read`, `DEFAULT_SEED`, `ENCODED_LEN`, `branch_seed` (P48-14, D-184) |
| `host` | `Session`, `Exit`, `AppealOutcome`, `CommandReply`, `Interpreted`, `SpeechLine`, `SpeechLog`, `ScriptSoundtrack`, `ScriptSociety`, and the functions listed below |
| `dialogue` | `View`, `Selection`, `view` |
| `command` | `Interpreter`, `WordList`, `Command` |
| `spell` | `Book`, `Spell`, `Word`, `Kind`, `Refusal`, `Outcome`, `MAX_BOOKS`, `DEFAULT_WORDS_PER_KIND`, `MAX_WORDS_PER_KIND`, `DEFAULT_SPELLS`, `MAX_SPELLS` (the `MAX_` names are the safety caps a `limit` may reach and the default ceilings are `DEFAULT_`, P48-13, D-183), `resolve`, `named`, `named_text`, `knows`, `check`, `cast`, `combine` |
| `decision` | `Decision`, `Option`, `Pick`, `Clause`, `Choices`, `Stage`, `Status`, `DEFAULT_DECISIONS`, `MAX_DECISIONS`, `MAX_CLAUSES`, `DEFAULT_OPTIONS`, `MAX_OPTIONS`, `MAX_PICKS`, `MAX_POINTS`, `validate`, `seed`, `triggered`, `stage_of`, `chosen`, `score_of`, `step` |
| `hint` | `Hint`, `Tier` (with `fromInt`, `number`, `generated`, and `label`), `Path` (the rest of `hint` is internal, P48-19, D-176) |
| `dilemma` | `Stage`, `Status` (the rest of `dilemma` is internal, P48-19, D-176) |
| `value` | `KnownValue` (the rest of `value` is internal, P48-19, D-176) |

Supported direct VM methods are `fire_cue`, `select_path`, `weave_draft`, `weave_notes`, `set_dialogue_speaker`, `open_generated_dialogue`, `dialogue_view`, `choose`, `sync_dialogue`, `transition_to_scene`, `evaluates_belief`, `assert_belief`, and `reject_belief`. Construct a VM with `host.init_vm`; advance it with `host.tick` or `Session.advance`, never bare `VM.step_tick`.

Supported host functions are `init_vm`, `initialize_subsystems`, `start_script`, `start_routine`, `run_initial_statements`, `place_cast`, `player_actor`, `tick`, `run_command`, `interpret_command`, `dispatch_command`, `command_words`, `speech_lines`, `speech_this_tick`, `act`, `present`, `appeal`, `cast`, `restart_routines`, `combine`, `hint`, `decision`, `dilemma`, `known_value`, `has_state`, `place_waypoint`, `add_exit_marks`, `take_exit_here`, and `take_any_exit_here` (a host's exits, then the script's room-block exits; P47-11, D-199).

`host.present(vm, compiled, actor, evidence, person)` records `Presented(person, evidence)` as a set fact and fires `Presents(actor, person, evidence)`; it returns whether a handler answered (P44-03). The record holds one row per distinct piece of evidence. The default typed frames `present <thing> to <thing>` and `show <thing> to <thing>` use the same action.

`host.appeal(vm, compiled, actor, person, value)` appeals to `person`'s value on the axis the entity `value` names and returns `AppealOutcome`: `.made`, `.unknown_value` when the actor does not know `<Axis> of <person>`, or `.no_dilemma` when no open dilemma of that person lists the value (P45-05, D-149). A made appeal counts at the dilemma's next weighing, records `Appealed(person, value)`, and fires `Appeals(actor, person, value)`. The default typed frame `appeal to <thing>` uses the same action for the first such person in the speaker's room.

`host.cast(vm, compiled, caster, name, target)` resolves a spell in the script's book, checks every word against what the caster knows, and fires the cue named after the spell only when the combination is accepted; it returns `spell.Outcome`, either the resolved spell or a `Refusal` (P44-04). `host.combine(vm, compiled, caster, power, element, form, target)` takes the same path for a player who builds a phrase from three words instead of naming a spell, and returns the same `spell.Outcome`. Words come from `Knows` or `Believes` about the caster, and `Rejects` overrides both.

`host.tick` steps declared decisions after agendas and fires each winner's cue for the next tick (P44-05). `decision.chosen(world, decision)` reports the option at the open decision point, or null between points; `decision.stage_of` reports `Idle` or `Done`, and `decision.score_of(world, option)` reports what an option's offered lines total now. A host that runs a table itself may call `decision.seed` once before play and `decision.step` with the compiled declarations after a tick; the choice is the set fact `Chose(Decision, Option)` and the stage is the property `DecisionState`, so save, rewind, and branch restore need no decision snapshot. Scoring reads facts and draws no random number. The trigger lines and option scores are the script's; the engine only offers, sums, and fires.

A run's dice (P48-14, D-168, D-184): `VM.set_seed(seed)` starts them, before the first tick, and `VM.dice` is a supported field holding the seed and the generator; `Session.seed(seed)` does the same for a session and restarts its timeline. A `Session` in a real window seeds from the clock when it starts; a headless window keeps 42. `TemporalHypervisor.run_seed` is the seed a branch's dice are mixed from, which a session copies from the VM, and `TemporalHypervisor.active_dice()` is the branch's generator while one is live, which a host that binds the VM to the branch world sets as `VM.branch_dice`. A session's rewind restores the whole run, dice included, unless the program's `rewinds_reroll` is set.

A turn clock (P48-22, D-188): `CompiledProgram.turn_clock` is true for `clock: turns`. `CommandReply.turn` says a typed line resolved to an action and so takes a turn, whether or not a handler answered. Under a turn clock `Session.clock_runs()` is true only while the player walks, so `tick_due` waits for the player, and a host calls `Session.take_turn()` after a resolved command or a click that acts; engine actions never do.

All public methods on `Session`, `SpeechLog`, and `ScriptSoundtrack` are supported. `Session` is the preferred owner of ticking, pause, rewind, save/load actions, dialogue selection, frame refresh, and temporal active-world routing. Their storage fields are internal.

`ScriptSociety.init(world, compiled, index)` selects a script declaration by zero-based source order and seeds its initial facts. Construct it once before play or before restoring a matching save. `ScriptSociety.step(vm)` runs society rules once after `host.tick`; the VM must have a spatial system and still use the original world's registries. The compiled program and registries must outlive the society. Do not reinitialize after restore, since that would reseed the saved facts. The wrapper's fields and its diagnostic chronicle are internal (P41-02).

`host.hint(world, compiled, actor, tier, buf)` returns the active hint (`?hint.Hint`) for `actor` at `tier`, falling back to the highest authored tier below `tier`, or null when every need of every declared goal holds (P48-19, D-176). `host.decision(world, entity)` reports a decision's stage and chosen option (`decision.Status`), `host.dilemma(world, entity)` reports a dilemma's stage and chosen outcome (`dilemma.Status`), and `host.known_value(world, observer, character, axis)` reports `character`'s value on `axis` and whether `observer` knows it (`value.KnownValue`). None takes an internal `CompiledProgram` table; all other `hint`, `value`, and `dilemma` declarations stay internal.

## Display and sound

| Namespace | Supported surface |
| --- | --- |
| `display` | `DisplayBridge`, `RenderFrame`, `DisplayWindow`, `UserAction`, `StatusHook`, `RenderEntity`, `RenderWaypoint`, `RenderHotspot`, `RenderInventoryItem`, `RenderDialogue`, `Theme`, `Canvas` (with `draw_image(image, frame, x, y)` and `draw_image_cycled(image, frame, x, y, colour_map)`, P46-02, P49-01; P48-12 dropped its palette argument), `DisplayWindow.set_art` and `DisplayWindow.animation_clock` (P46-03), `Color`, `current_score_entity`, `DisplayWindow.show_engine_facts` and `DisplayWindow.shown_facts`, `capture_debug_facts`, `story_fact_count`, `is_engine_relation` (P48-10), `RenderLook` and `look_of`, the look each thing's `Looks` fact names (P48-11) |
| `audio` | `AudioBridge`, `Sound`, `Soundtrack`, `SoundEffectKind`, `ChiptuneSynth` |

All public methods on `DisplayBridge`, `RenderFrame`, and `DisplayWindow` are supported. `DisplayBridge.capture_scene(world, spatial, vm, scene)` fills a frame from a named room without moving the VM (P44-06); `capture_frame` is the same call with the VM's scene. The frame is labelled as that room and carries its `#SceneScore`, so the renderer, theme, and audio treat it as that room. Capture is read-only: the VM's scene, fibers, and rules are untouched, and a host that shows a watched view keeps interaction off it. `Theme` is a host configuration record, so its callback, key, thumbnail, and soundtrack fields are supported. The frame's storage layout and the `display.renderer`, `font`, `text_layout`, `dialogue_panel`, `beats`, and `state_graph` implementation namespaces are internal. A theme or status callback uses the documented types but must not depend on unlisted renderer helpers.

## Saves and branch worlds

| Namespace | Supported surface |
| --- | --- |
| `save` | `SAVE_MAGIC`, `SAVE_VERSION`, `MIN_SAVE_VERSION`, `MAX_SLOTS`, `QUICKSAVE_SLOT`, `SaveError` (with `SaveFromOtherBuild` and `SaveNotTranslatable`, P48-08, and `SaveFromBeforeOne`, P48-17), `PRE_1_0_SAVE_MAGIC`, `ProgramIdentity` and its `known` method, `format_build_mismatch`, `SaveOptions`, `SaveMetadata`, `SaveSlotInfo`, `LoadResult`, `ThumbnailPainter`, `SaveManager`, `write_save_state`, `write_save_state_with_temporal`, `read_save_state`, `read_save_state_with_temporal`, `read_save_state_for`, `read_save_state_with_temporal_for`, `inspect_save_stream`, `version_from_bytes`, and `format_unsupported_version` |
| `hypervisor` | `TemporalHypervisor`, `BranchCollapseState`, `HypervisorStepResult`, `DreamFact`, `TeleologicalDependency`, `validate_novikov_consistency`, `format_countdown` |

`SaveManager.program`, `SaveManager.last_load_restarted_routines`, `SaveMetadata.program`, and `SaveMetadata.routines_restarted` are supported fields (P48-08, D-162): a host sets the first to `compiled.identity()` so its saves name the build and its loads refuse another's. After a load whose `routines_restarted` is true, call `host.restart_routines`; `host.Session` and the stock window do both themselves. All public `SaveManager`, `SaveMetadata`, `SaveSlotInfo`, `ThumbnailPainter`, and `TemporalHypervisor` methods are supported. Hypervisor storage fields are internal. D-044's tangent, vortex, artifact, and singularity aliases were removed in P38-03; use branch, convergence, keystone, and budget-expiry names.

## Browser decks

Supported `wasm` declarations are `Deck`, `ScriptDeckOptions`, `WasmRuntime`, `WasmVerb`, `VerbCues`, `Exit`, `RgbaColor`, `BrowserEventKind`, `BrowserInputEvent`, `BrowserActionTag`, `script_deck`, `script_deck_with`, and `export_runtime`. The fields of `Deck`, `ScriptDeckOptions`, `VerbCues`, `Exit`, and `BrowserInputEvent` are supported host configuration; `WasmRuntime` fields are not.

A deck callback receives `*WasmRuntime`, but only these methods are supported: `set_banner`, `get_banner`, `active_world`, `spatial_system`, `virtual_machine`, `compiled_program`, `player`, `set_player`, `queue_message`, `answer`, `attach_hypervisor`, `clock`, `bind`, `step_tick`, `record_snapshot`, `scrub_to_tick`, `deck_action`, `submit_command`, `trigger_catalyst`, `capture`, and `render_frame`. Runtime fields are internal.

Prefer `script_deck` or `script_deck_with` for a script-backed game. A custom `Deck.load` callback may call `load_program`, or `load_package_bytes` for a `.bspk` package handed over at run time, which links every package section reader and copies what it needs from the bytes (P47-06, D-195); direct `WasmRuntime.init` and `deinit` are supported for an embedding host.

## Browser module exports

A page that loads a BeSpoke WebAssembly module may call these exports (D-175, D-176, D-191). They are the ones the page and smoke test from `bespoke init` and browser feature queries depend on: `wasm_init`, `wasm_step_tick`, `wasm_get_tick`, `wasm_get_fact_count`, `wasm_render_frame`, `wasm_set_animation_clock`, `wasm_framebuffer_ptr`, `wasm_framebuffer_len`, `wasm_on_pointer_down`, `wasm_on_pointer_move`, `wasm_on_right_click`, `wasm_on_key_down`, `wasm_on_char`, `wasm_command_bar_focused`, `wasm_submit_command`, `wasm_audio_render`, `wasm_audio_sample_rate`, `wasm_query_ptr`, `wasm_query_len`, `wasm_hint`, `wasm_decision`, `wasm_dilemma`, and `wasm_known_value`. `tests/test_browser_exports.py` fails when one of them is not exported, or when a generated page calls an export this list omits.

Every other `wasm_*` export is internal: the showcase pages' deck, verb, dialogue, inspector, and message calls, and `wasm_load_scenario`, `wasm_on_touch`, and `wasm_scrub_to_tick`. A script never learns which platform runs it; a capability that differs by platform reaches scripts, if ever, as a feature fact (D-175).

`wasm_init(scenario, seed_low, seed_high)` takes the run's seed as two 32-bit halves (P48-14, D-184). Zeros, as a page that passes only the scenario sends, mean seed 42; the generated page and the showcase pages pass the clock, so each new game rolls differently and keeps its seed through rewinds.

## Stability rule

Supported names, signatures, and behavior follow the [deprecation policy](CONTRIBUTING.md#deprecation-policy) (P38-04, D-108). Internal declarations may change without a compatibility promise. [COMPATIBILITY.md](COMPATIBILITY.md) governs file compatibility.
