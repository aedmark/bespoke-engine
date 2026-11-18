//! Lantern Watch's transcript and browser form adapt the stock Wasm host.
const std = @import("std");
const bespoke = @import("bespoke");
const Runtime = bespoke.wasm.WasmRuntime;

var interpreter: bespoke.command.Interpreter = .{};
var input: [160]u8 = undefined;
var output: [4096]u8 = undefined;
var output_len: usize = 0;

export fn watch_input_ptr() [*]u8 {
    return &input;
}
export fn watch_input_capacity() usize {
    return input.len;
}
export fn watch_text_ptr() [*]const u8 {
    return &output;
}
export fn watch_text_len() usize {
    return output_len;
}
export fn watch_text_clear() void {
    output_len = 0;
}

fn append(comptime fmt: []const u8, args: anytype) void {
    const line = std.fmt.bufPrint(output[output_len..], fmt ++ "\n", args) catch return;
    output_len += line.len;
}

fn setup(_: *Runtime) !void {
    interpreter = .{};
    output_len = 0;
    append("You are at the bell landing. The rope hangs within reach.", .{});
}

fn afterTick(rt: *Runtime) !void {
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
    if (reply.fired) try rt.step_tick();
}

fn formSubmit(rt: *Runtime, len: u8) !void {
    if (len == 0 or len > input.len) return;
    try typed(rt, input[0..len]);
}

comptime {
    bespoke.wasm.export_runtime(&[_]bespoke.wasm.Deck{
        bespoke.wasm.script_deck_with("Lantern Watch", @embedFile("game_package"), .{
            .setup = setup,
            .after_tick = afterTick,
            .command_bar = true,
            .on_typed = typed,
            .on_action = formSubmit,
        }),
    });
}
