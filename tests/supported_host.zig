//! P38-03 compile contract: this file stands outside `src/` and uses only the API listed in
//! docs/API.md. If a supported name or signature moves, `zig build test-engine` fails here.
const std = @import("std");
const bespoke = @import("bespoke");

const source =
    \\scene Room:
    \\  cast: Hero
    \\  marks: Door
    \\
    \\relation Ready(who)
    \\remember Ready(Hero)
    \\routine Idle(Hero):
    \\  wait 1 ticks
;

const BrowserHooks = struct {
    fn setup(runtime: *bespoke.wasm.WasmRuntime) anyerror!void {
        const world = runtime.active_world();
        const hero = try world.intern_entity("Hero");
        runtime.set_player(hero);
        _ = runtime.player();
        _ = runtime.spatial_system();
        _ = runtime.virtual_machine();
        _ = runtime.compiled_program();
        runtime.set_banner("Ready");
        runtime.queue_message("Hero", "Ready");
        runtime.bind();
    }
};

const browser_deck = bespoke.wasm.script_deck_with("API fixture", source, .{
    .setup = BrowserHooks.setup,
});

comptime {
    const hypervisor = bespoke.hypervisor;
    if (@hasDecl(hypervisor, "TangentCollapseState") or
        @hasDecl(hypervisor.TemporalHypervisor, "fork_tangent") or
        @hasDecl(hypervisor.TemporalHypervisor, "collapse_tangent") or
        @hasDecl(hypervisor.TemporalHypervisor, "set_vortex_target") or
        @hasField(hypervisor.TemporalHypervisor, "tangent_active") or
        @hasField(hypervisor.TemporalHypervisor, "living_receiver") or
        @hasField(hypervisor.TemporalHypervisor, "artifact_entity") or
        @hasField(hypervisor.TemporalHypervisor, "vortex_waypoint") or
        std.meta.stringToEnum(hypervisor.UniverseBranchKind, "tangent") != null or
        std.meta.stringToEnum(hypervisor.BranchCollapseState, "collapsed_singularity") != null or
        std.meta.stringToEnum(hypervisor.HypervisorStepResult, "singularity_collapse") != null)
    {
        @compileError("P38-03: a deprecated D-044 API alias remains");
    }
}

/// P48-04: every name `API.md` lists for the namespaces Phases 44 to 46 added (and the host calls
/// they brought) must exist, so renaming a supported name fails `zig build test-engine` here.
fn require(comptime Container: type, comptime names: []const []const u8, comptime where: []const u8) void {
    inline for (names) |name| {
        if (!@hasDecl(Container, name)) @compileError("P48-04: " ++ where ++ "." ++ name ++ " is listed in docs/API.md but missing");
    }
}

comptime {
    require(bespoke.spell, &.{ "Book", "Spell", "Word", "Kind", "Refusal", "Outcome", "MAX_BOOKS", "DEFAULT_WORDS_PER_KIND", "MAX_WORDS_PER_KIND", "DEFAULT_SPELLS", "MAX_SPELLS", "resolve", "named", "named_text", "knows", "check", "cast", "combine" }, "spell");
    require(bespoke.decision, &.{ "Decision", "Option", "Pick", "Clause", "Choices", "Stage", "DEFAULT_DECISIONS", "MAX_DECISIONS", "MAX_CLAUSES", "DEFAULT_OPTIONS", "MAX_OPTIONS", "MAX_PICKS", "MAX_POINTS", "validate", "seed", "triggered", "stage_of", "chosen", "score_of", "step" }, "decision");
    require(bespoke.image, &.{ "ART_WIDTH", "ART_HEIGHT", "SCALE", "MAX_COLOURS", "TRANSPARENT", "Colour", "Pixel", "from_indices", "Image", "Art", "Anim", "Step", "Backdrop", "Sprite", "Area", "Look", "Part", "MAX_PART_OFFSET", "frame_in", "MAX_IMAGES", "MAX_SHEET_SIDE", "MAX_SHEET_PIXELS", "MAX_ART_PIXELS", "MAX_NAME", "MAX_BINDINGS", "Error" }, "image");
    require(bespoke.image.Pixel, &.{"opaque_colour"}, "image.Pixel");
    require(bespoke.image.Image, &.{ "columns", "frame_count", "frame_pixel", "validate" }, "image.Image");
    require(bespoke.image.Art, &.{ "is_empty", "find", "backdrop_for", "sprite_for", "area_for", "look_named", "part_for", "validate", "dupe", "deinit_owned" }, "image.Art");
    require(bespoke.image.Sprite, &.{"frame_at"}, "image.Sprite");
    require(bespoke.image.Look, &.{"frame_at"}, "image.Look");
    require(bespoke.png, &.{ "MAX_FILE", "Error", "Rgba", "decode" }, "png");
    require(bespoke.png.Rgba, &.{"deinit"}, "png.Rgba");
    require(bespoke.qoi, &.{ "Error", "HEADER_LEN", "encode", "decode", "header_size" }, "qoi");
    require(bespoke.dice, &.{ "Dice", "DEFAULT_SEED", "ENCODED_LEN", "branch_seed" }, "dice");
    require(bespoke.dice.Dice, &.{ "init", "roll", "write", "read" }, "dice.Dice");
    require(bespoke.vm.VM, &.{ "set_seed", "active_dice" }, "vm.VM dice");
    require(bespoke.host.Session, &.{ "seed", "clock_runs", "take_turn" }, "host.Session");
    require(bespoke.hypervisor.TemporalHypervisor, &.{"active_dice"}, "hypervisor dice");
    require(bespoke.art_import, &.{ "MapError", "PixelError", "Where", "map", "to_pixels", "CodeError", "assign_codes", "free_codes", "write_palette_lines", "write_image_block" }, "art_import");
    require(bespoke.runner, &.{ "RunConfig", "CheckOptions", "check_file_with", "check_file", "compile_file", "run_file", "run_bytes", "import_art", "ImportOptions", "ScriptFiles" }, "runner");
    require(bespoke.compiler, &.{ "compile_source", "compile_source_with", "check_source", "check_source_with", "FileSource", "script_palette", "ScriptPalette", "CheckResult", "Diagnostic", "CompiledProgram" }, "compiler");
    require(bespoke.host, &.{ "present", "appeal", "AppealOutcome", "cast", "combine", "restart_routines" }, "host");
    require(bespoke.world, &.{"ObjectKind"}, "world");
    require(bespoke.world.World, &.{ "intern_relation_kind", "declare_object_kind", "object_kind", "set_display_name", "display_text", "set_phrase", "phrase_override" }, "world.World");
    require(bespoke.reserved, &.{ "Release", "LANGUAGE", "AuthorRelation", "AUTHOR_FACING", "newer_than_language", "engine_may_use", "is_bookkeeping" }, "reserved");
    require(bespoke.compiler, &.{ "CheckWarning", "check_source_against", "includes" }, "compiler");
    require(bespoke.compiler.CheckResult, &.{"file"}, "compiler.CheckResult");
    require(bespoke.compiler.CheckWarning, &.{"file"}, "compiler.CheckWarning");
    require(bespoke.compiler.includes, &.{ "expand", "Expanded", "Segment", "Place", "Failure" }, "compiler.includes");
    require(bespoke.display, &.{ "capture_debug_facts", "story_fact_count", "is_engine_relation", "RenderLook", "look_of" }, "display");
    require(bespoke.phrase, &.{ "Key", "Entry", "ENTRIES", "Arg", "Error", "find", "entry", "text", "validate", "render", "fill" }, "phrase");
    require(bespoke.save, &.{ "ProgramIdentity", "format_build_mismatch", "read_save_state_for", "read_save_state_with_temporal_for", "PRE_1_0_SAVE_MAGIC" }, "save");
    require(bespoke.package, &.{ "PACKAGE_MAGIC", "PRE_1_0_MAGIC", "PACKAGE_FORMAT", "PackageHeader", "Section", "SECTION_TAGS", "SectionSet", "ALL_SECTIONS", "SECTION_REQUIRED", "save_package", "load_package", "load_package_linked", "sections_in", "save_package_file", "load_package_file", "version_from_bytes", "is_pre_1_0", "format_unsupported_version", "PRE_1_0_MESSAGE" }, "package");
    require(bespoke.package.Section, &.{ "tag", "from_tag" }, "package.Section");
    require(bespoke.compiler.CompiledProgram, &.{"identity"}, "compiler.CompiledProgram");
}

test "P38-03: a host compiles against only the supported API" {
    const testing = std.testing;
    _ = browser_deck;

    const checked = bespoke.compiler.check_source(testing.allocator, source);
    try testing.expect(checked.is_valid);

    var world = try bespoke.World.init(testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var program = try bespoke.compile_source(testing.allocator, &world, &spatial, source);
    defer program.deinit();
    var vm = try bespoke.host.init_vm(testing.allocator, &world, &spatial, &program);
    defer vm.deinit();

    const player = try bespoke.host.start_script(&world, &spatial, &vm, &program);
    _ = try bespoke.host.tick(&vm, &program);

    const ready = world.lookup_relation("Ready").?;
    try testing.expect(world.has_fact(player, ready, null));
    var query = world.query(player, ready, null);
    try testing.expect(query.next() != null);

    var bridge = bespoke.DisplayBridge.init();
    bridge.set_active_character(player);
    bridge.capture_frame(&world, &spatial, &vm);
    bridge.swap();
    _ = bridge.get_frame().get_current_scene();

    var speech_buf: [128]u8 = undefined;
    _ = bespoke.host.speech_this_tick(&world, &vm, &speech_buf);
}
