//! The Sunken Vault in a browser: text-first transcript, command bridge, and animated room art.
const std = @import("std");
const bespoke = @import("bespoke");
const Runtime = bespoke.wasm.WasmRuntime;

var interpreter: bespoke.command.Interpreter = .{};
var output: [8192]u8 = undefined;
var output_len: usize = 0;
var scene_buf: [128]u8 = undefined;
var scene_len: usize = 0;

export fn game_text_ptr() [*]const u8 {
    return &output;
}
export fn game_text_len() usize {
    return output_len;
}
export fn game_text_clear() void {
    output_len = 0;
}
export fn game_scene_ptr() [*]const u8 {
    return &scene_buf;
}
export fn game_scene_len() usize {
    return scene_len;
}
export fn game_has_picture() u8 {
    return 1;
}

fn append(comptime fmt: []const u8, args: anytype) void {
    const line = std.fmt.bufPrint(output[output_len..], fmt ++ "\n", args) catch return;
    output_len += line.len;
}

fn updateScene(rt: *Runtime) void {
    const world = rt.active_world();
    const scene = rt.virtual_machine().current_scene orelse {
        scene_len = 0;
        return;
    };
    const text = world.display_text(scene) orelse world.get_entity_name(scene) orelse "";
    scene_len = @min(text.len, scene_buf.len);
    @memcpy(scene_buf[0..scene_len], text[0..scene_len]);
}

fn setup(rt: *Runtime) !void {
    interpreter = .{};
    output_len = 0;
    updateScene(rt);
    append("Rain sweeps across the keep courtyard. East stands the guardhouse; wet stone steps lead down into the cistern.", .{});
}

fn afterTick(rt: *Runtime) !void {
    updateScene(rt);
    var lines: [16]bespoke.host.SpeechLine = undefined;
    const count = bespoke.host.speech_lines(rt.active_world(), rt.virtual_machine(), &lines);
    for (lines[0..count]) |line| {
        if (std.mem.eql(u8, line.speaker, "Scene")) {
            append("{s}", .{line.text});
        } else append("{s}: {s}", .{ line.speaker, line.text });
    }
}

fn typed(rt: *Runtime, line: []const u8) !void {
    const program = rt.compiled_program() orelse return;
    const actor = rt.player() orelse return;
    var reply_buf: [256]u8 = undefined;
    const reply = try bespoke.host.run_command(rt.virtual_machine(), program, &interpreter, actor, line, &reply_buf);
    if (reply.text) |text| {
        append("{s}", .{text});
        rt.set_banner(text);
    }
    if (reply.turn) {
        try rt.step_tick();
        var guard: usize = 0;
        while (rt.spatial_system().is_moving(actor) and guard < 256) : (guard += 1) {
            try rt.step_tick();
        }
    }
    updateScene(rt);
}

comptime {
    bespoke.wasm.export_runtime(&[_]bespoke.wasm.Deck{
        bespoke.wasm.script_deck_with("The Sunken Vault", @embedFile("game_package"), .{
            .setup = setup,
            .after_tick = afterTick,
            .on_typed = typed,
        }),
    });
}
