const std = @import("std");
const bench = @import("workload.zig");

var load: bench.Workload = undefined;
var active = false;

export fn bench_setup(index: u32) bool {
    if (active) load.deinit();
    active = false;
    if (index >= bench.cases.len) return false;
    load.init(std.heap.wasm_allocator, bench.cases[index]) catch return false;
    active = true;
    return true;
}

export fn bench_sample() bool {
    if (!active) return false;
    load.advance(bench.ticks_per_sample) catch return false;
    return true;
}

export fn bench_verify() bool {
    if (!active) return false;
    load.verify(bench.samples * bench.ticks_per_sample) catch return false;
    return true;
}

export fn bench_cases() usize {
    return bench.cases.len;
}
export fn bench_ticks() u32 {
    return bench.ticks_per_sample;
}
export fn bench_samples() u32 {
    return bench.samples;
}
export fn bench_facts() usize {
    return load.facts();
}
export fn bench_entities() usize {
    return load.entities();
}
export fn bench_fibers() usize {
    return load.fibers();
}
