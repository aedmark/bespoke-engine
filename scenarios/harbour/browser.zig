const std = @import("std");
const harbour = @import("game.zig");
var game: harbour.Game = undefined;
var active = false;
var input: [160]u8 = undefined;

export fn harbour_init() bool {
    if (active) game.deinit();
    active = false;
    game.init(std.heap.wasm_allocator) catch return false;
    active = true;
    return true;
}

export fn harbour_input() [*]u8 {
    return &input;
}
export fn harbour_text() [*]const u8 {
    return &game.text;
}
export fn harbour_text_len() usize {
    return game.text_len;
}
export fn harbour_clear_text() void {
    game.text_len = 0;
}
export fn harbour_room() usize {
    return game.room();
}
export fn harbour_clear() bool {
    return active and game.has("Packet", "PacketClear");
}
export fn harbour_facts() usize {
    return game.world.fact_count();
}
export fn harbour_sample_ticks() usize {
    return harbour.sample_ticks;
}
export fn harbour_samples() usize {
    return harbour.samples;
}

export fn harbour_command(len: usize) bool {
    if (!active or len > input.len) return false;
    game.command(input[0..len]) catch return false;
    return true;
}

export fn harbour_tick() bool {
    if (!active) return false;
    game.tick() catch return false;
    return true;
}

export fn harbour_bench_setup(extra: u32) bool {
    if ((extra != 0 and extra != 4096) or !harbour_init()) return false;
    game.prepareSample(extra) catch return false;
    return true;
}

export fn harbour_bench_sample() bool {
    if (!active) return false;
    game.advance(harbour.sample_ticks) catch return false;
    return harbour_clear();
}
