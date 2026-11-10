//! The engine's own WebAssembly module (`zig build wasm`, P32-04, D-042): the browser runtime
//! with one neutral demo deck, so the engine builds and runs in a browser without any proof.
//! The proofs' decks build separately (`zig build wasm-proofs`, `proofs/wasm_main.zig`).
const wasm = @import("wasm.zig");

fn load_stage(rt: *wasm.WasmRuntime) anyerror!void {
    const stage = try rt.world.intern_entity("Stage");
    const walker = try rt.world.intern_entity("Walker");
    const left = try rt.spatial.graph.add_waypoint(stage, 0, 0, "Left");
    const centre = try rt.spatial.graph.add_waypoint(stage, 20, 0, "Centre");
    const right = try rt.spatial.graph.add_waypoint(stage, 40, 0, "Right");
    try rt.spatial.graph.connect(left, centre, null);
    try rt.spatial.graph.connect(centre, right, null);
    try rt.spatial.add_hotspot(try rt.world.intern_entity("Signpost"), stage, .{ .x = 20, .y = -8 }, 6, "Signpost", "A blank signpost.");
    try rt.spatial.register_entity(walker, left, 10);
    rt.player_entity = walker;
    rt.set_banner("BeSpoke stage: click a mark to walk.");
}

const decks = [_]wasm.Deck{.{ .title = "BESPOKE STAGE", .load = load_stage }};

comptime {
    wasm.export_runtime(&decks);
}
