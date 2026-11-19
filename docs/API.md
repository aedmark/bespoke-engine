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
| `compiler` | `compile_source`, `check_source`, `CheckResult` and its `message` / `diagnostic` methods, `Diagnostic`, `CompiledProgram` and `CompiledProgram.deinit` |
| `package` | `PACKAGE_MAGIC`, `PACKAGE_VERSION`, `MIN_PACKAGE_VERSION`, `save_package`, `load_package`, `save_package_file`, `load_package_file`, `version_from_bytes`, `format_unsupported_version` |
| `runner` | `RunConfig`, `check_file`, `compile_file`, `run_file`, `run_bytes` |

`CompiledProgram` owns its compiled data and must outlive every VM using it. Its fields, bytecode chunk, routine maps, and declaration tables are internal. Use `host.init_vm`, `host.start_script`, and `host.start_routine` instead of reading those tables.

## World and spatial state

| Namespace | Supported surface |
| --- | --- |
| `world` | `DEFAULT_ARENA_SIZE`, `EntityId`, `RelationKind`, `RelationType`, `Fact`, `PatternTerm`, `PatternClause`, `VariableBindings`, `World`, `QueryIterator` |
| `spatial` | `WaypointId`, `Point2D`, `Waypoint`, `Hotspot`, `SpatialSystem`, `SpatialSystem.Portal`, `SpatialSystem.TransferPolicy` |

Supported `World` methods are `init`, `deinit`, `intern_entity`, `intern_relation`, `lookup_entity`, `lookup_relation`, `get_entity_name`, `get_relation_meta`, `fact_count`, `remember`, `forget`, `transfer_item`, `has_fact`, `find_first`, `get_property`, `query`, `find_first_match`, `find_first_match_from`, `has_multi_match`, `find_all_matches`, `get_recently_expired`, `save_state`, `restore_state`, and `clone`. `EntityId.to_int` / `from_int`, `RelationKind.to_int` / `from_int`, `QueryIterator.next`, and `VariableBindings.get` / `set` are supported.

Supported `SpatialSystem` methods are `init`, `deinit`, `add_grid`, `grid_in_room`, `find_grid`, `waypoint_cell`, `agent_cell`, `clear_hotspots`, `register_portal`, `get_portal_in_room`, `add_hotspot`, `find_hotspot_at`, `find_hotspot_at_in_room`, `count_hotspots_in_room`, `transition_actor`, `register_entity`, `walk_to`, `walk_to_with_world`, `waypoint_blocked`, `is_moving`, `has_arrived`, `get_position`, `get_current_waypoint`, `can_transfer_item`, `can_access_portal`, and `can_transfer_item_with_world`. Its graph, agent, hotspot, grid, and portal storage fields are internal.

## VM and host kit

| Namespace | Supported surface |
| --- | --- |
| `vm` | `VM`, `FiberId`, tick interval constants and `step_tick_interval_slower` / `step_tick_interval_faster` |
| `host` | `Session`, `Exit`, `CommandReply`, `Interpreted`, `SpeechLine`, `SpeechLog`, `ScriptSoundtrack`, `ScriptSociety`, and the functions listed below |
| `dialogue` | `View`, `Selection`, `view` |
| `command` | `Interpreter`, `WordList`, `Command` |

Supported direct VM methods are `fire_cue`, `select_path`, `weave_draft`, `weave_notes`, `set_dialogue_speaker`, `open_generated_dialogue`, `dialogue_view`, `choose`, `sync_dialogue`, `transition_to_scene`, `evaluates_belief`, `assert_belief`, and `reject_belief`. Construct a VM with `host.init_vm`; advance it with `host.tick` or `Session.advance`, never bare `VM.step_tick`.

Supported host functions are `init_vm`, `initialize_subsystems`, `start_script`, `start_routine`, `run_initial_statements`, `place_cast`, `player_actor`, `tick`, `run_command`, `interpret_command`, `dispatch_command`, `command_words`, `speech_lines`, `speech_this_tick`, `act`, `present`, `has_state`, `place_waypoint`, `add_exit_marks`, and `take_exit_here`.

`host.present(vm, compiled, actor, evidence, person)` records `Presented(person, evidence)` as a set fact and fires `Presents(actor, person, evidence)`; it returns whether a handler answered (P44-03). The record holds one row per distinct piece of evidence. The default typed frames `present <thing> to <thing>` and `show <thing> to <thing>` use the same action.

All public methods on `Session`, `SpeechLog`, and `ScriptSoundtrack` are supported. `Session` is the preferred owner of ticking, pause, rewind, save/load actions, dialogue selection, frame refresh, and temporal active-world routing. Their storage fields are internal.

`ScriptSociety.init(world, compiled, index)` selects a script declaration by zero-based source order and seeds its initial facts. Construct it once before play or before restoring a matching save. `ScriptSociety.step(vm)` runs society rules once after `host.tick`; the VM must have a spatial system and still use the original world's registries. The compiled program and registries must outlive the society. Do not reinitialize after restore, since that would reseed the saved facts. The wrapper's fields and its diagnostic chronicle are internal (P41-02).

## Display and sound

| Namespace | Supported surface |
| --- | --- |
| `display` | `DisplayBridge`, `RenderFrame`, `DisplayWindow`, `UserAction`, `StatusHook`, `RenderEntity`, `RenderWaypoint`, `RenderHotspot`, `RenderInventoryItem`, `RenderDialogue`, `Theme`, `Canvas`, `Color`, `current_score_entity` |
| `audio` | `AudioBridge`, `Sound`, `Soundtrack`, `SoundEffectKind`, `ChiptuneSynth` |

All public methods on `DisplayBridge`, `RenderFrame`, and `DisplayWindow` are supported. `Theme` is a host configuration record, so its callback, key, thumbnail, and soundtrack fields are supported. The frame's storage layout and the `display.renderer`, `font`, `text_layout`, `dialogue_panel`, `beats`, and `state_graph` implementation namespaces are internal. A theme or status callback uses the documented types but must not depend on unlisted renderer helpers.

## Saves and branch worlds

| Namespace | Supported surface |
| --- | --- |
| `save` | `SAVE_MAGIC`, `SAVE_VERSION`, `MIN_SAVE_VERSION`, `MAX_SLOTS`, `QUICKSAVE_SLOT`, `SaveError`, `SaveOptions`, `SaveMetadata`, `SaveSlotInfo`, `LoadResult`, `ThumbnailPainter`, `SaveManager`, `write_save_state`, `write_save_state_with_temporal`, `read_save_state`, `read_save_state_with_temporal`, `inspect_save_stream`, `version_from_bytes`, and `format_unsupported_version` |
| `hypervisor` | `TemporalHypervisor`, `BranchCollapseState`, `HypervisorStepResult`, `DreamFact`, `TeleologicalDependency`, `validate_novikov_consistency`, `format_countdown` |

All public `SaveManager`, `SaveMetadata`, `SaveSlotInfo`, `ThumbnailPainter`, and `TemporalHypervisor` methods are supported. Hypervisor storage fields are internal. D-044's tangent, vortex, artifact, and singularity aliases were removed in P38-03; use branch, convergence, keystone, and budget-expiry names.

## Browser decks

Supported `wasm` declarations are `Deck`, `ScriptDeckOptions`, `WasmRuntime`, `WasmVerb`, `VerbCues`, `Exit`, `RgbaColor`, `BrowserEventKind`, `BrowserInputEvent`, `BrowserActionTag`, `script_deck`, `script_deck_with`, and `export_runtime`. The fields of `Deck`, `ScriptDeckOptions`, `VerbCues`, `Exit`, and `BrowserInputEvent` are supported host configuration; `WasmRuntime` fields are not.

A deck callback receives `*WasmRuntime`, but only these methods are supported: `set_banner`, `get_banner`, `active_world`, `spatial_system`, `virtual_machine`, `compiled_program`, `player`, `set_player`, `queue_message`, `answer`, `attach_hypervisor`, `clock`, `bind`, `step_tick`, `record_snapshot`, `scrub_to_tick`, `deck_action`, `trigger_catalyst`, `capture`, and `render_frame`. Runtime fields are internal.

Prefer `script_deck` or `script_deck_with` for a script-backed game. A custom `Deck.load` callback may call `load_program`; direct `WasmRuntime.init` and `deinit` are supported for an embedding host.

## Stability rule

Supported names, signatures, and behavior follow the [deprecation policy](CONTRIBUTING.md#deprecation-policy) (P38-04, D-108). Internal declarations may change without a compatibility promise. [COMPATIBILITY.md](COMPATIBILITY.md) governs file compatibility.
