//! `bespoke`: the engine CLI. Runs, compiles, and checks BeSpoke scripts and packages.
//!
//! This binary carries no scenario content. Proofs of concept (vertical slices) live in
//! `proofs/` and build as `bespoke-proofs` (D-031).
const std = @import("std");
const bespoke = @import("root.zig");

const usage =
    \\BeSpoke Engine - Standalone Simulation Spine & Narrative Game DSL
    \\
    \\Usage:
    \\  bespoke run <script.bespoke | game.bspk> [--headless] [--ticks N]
    \\  bespoke compile <script.bespoke> -o <game.bspk>
    \\  bespoke check <script.bespoke>
    \\
    \\Sample scripts live in scenarios/. Proofs of concept (vertical slices) are a
    \\separate binary: `zig build proofs`, then `bespoke-proofs --help`.
    \\
;

const Subcommand = enum { run, compile, check, help };

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var headless = false;
    var ticks: usize = 20;
    var subcommand: Subcommand = .help;
    var target_file: ?[]const u8 = null;
    var output_file: ?[]const u8 = null;

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "run") or std.mem.eql(u8, arg, "compile") or std.mem.eql(u8, arg, "check")) {
            subcommand = std.meta.stringToEnum(Subcommand, arg).?;
            target_file = args.next();
        } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            output_file = args.next();
        } else if (std.mem.eql(u8, arg, "--ticks")) {
            if (args.next()) |t| ticks = std.fmt.parseInt(usize, t, 10) catch 20;
        } else if (std.mem.eql(u8, arg, "--headless")) {
            headless = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "help")) {
            subcommand = .help;
        } else if (!std.mem.startsWith(u8, arg, "-") and target_file == null) {
            subcommand = .run;
            target_file = arg;
        } else {
            // Former scenario flags (--dott, --loom, ...) now belong to bespoke-proofs (D-031).
            try stdout.print("error: unknown argument '{s}'. Proofs of concept moved to `bespoke-proofs {s}`.\n\n", .{ arg, arg });
            try stdout.writeAll(usage);
            std.process.exit(1);
        }
    }

    switch (subcommand) {
        .help => try stdout.writeAll(usage),
        .check => {
            const path = target_file orelse return fail(stdout, "'bespoke check' requires a script file path");
            if (!try bespoke.runner.check_file(allocator, path, stdout)) std.process.exit(1);
        },
        .compile => {
            const path = target_file orelse return fail(stdout, "'bespoke compile' requires an input script file path");
            try bespoke.runner.compile_file(allocator, path, output_file orelse "game.bspk", stdout);
        },
        .run => {
            const path = target_file orelse return fail(stdout, "'bespoke run' requires a script or package path");
            try bespoke.runner.run_file(allocator, path, .{
                .ticks = ticks,
                .is_headless = headless,
                .verbose = true,
            }, stdout);
        },
    }
}

fn fail(stdout: anytype, msg: []const u8) !void {
    try stdout.print("error: {s}\n", .{msg});
    std.process.exit(1);
}
