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
