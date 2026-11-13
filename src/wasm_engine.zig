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

/// A second deck that compiles and runs a script in the browser (P29-03, D-066), so the
/// engine's own module exercises script decks and the smoke check covers them.
const STAGE_SCRIPT =
    \\scene Stage:
    \\  cast: Walker, Greeter
    \\  props: Signpost
    \\  marks: Left, Centre, Right
    \\
    \\relation Greeted(who)
    \\
    \\routine Stroll(Walker):
    \\  walk Walker to Right
    \\  remember Greeted(Walker)
    \\
    \\when Greeted(Walker):
    \\  say Greeter: "Welcome to the stage."
    \\
    \\on cue TalksTo(Walker, Greeter):
    \\  choice "Hello.":
    \\    say Greeter: "Hello yourself."
    \\  choice "Goodbye.":
    \\    say Greeter: "Come back soon."
;

const decks = [_]wasm.Deck{
    .{ .title = "BESPOKE STAGE", .load = load_stage },
    wasm.script_deck("BESPOKE SCRIPT STAGE", STAGE_SCRIPT),
};

comptime {
    wasm.export_runtime(&decks);
}
