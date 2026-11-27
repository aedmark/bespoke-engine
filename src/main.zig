//! `bespoke`: the engine CLI. Runs, compiles, and checks BeSpoke scripts and packages.
//!
//! This binary carries no scenario content. Proofs of concept (vertical slices) live in
//! `proofs/` and build as `bespoke-proofs` (D-031).
const std = @import("std");
const bespoke = @import("root.zig");
const scaffold = @import("scaffold.zig");
/// The engine checkout this binary was built from; `bespoke init` records it as the new
/// project's engine dependency (P29-01, D-063).
const build_options = @import("build_options");

const usage = (if (build_options.desktop) "" else "Static CLI: runs scripts headless. Use the SDL2 desktop build for a window.\n\n") ++
    \\BeSpoke Engine - Standalone Simulation Spine & Narrative Game DSL
    \\
    \\Usage:
    \\  bespoke run <script.bespoke | game.bspk> [--headless] [--ticks N] [--input <file>] [--facts] [--seed N]
    \\  bespoke compile <script.bespoke> -o <game.bspk> [--deps <file.d>]
    \\  bespoke check <script.bespoke> [--kind]
    \\  bespoke import <art.png> --name <Image> [--frames WxH] [--script <script.bespoke>] [-o <file>]
    \\  bespoke init <name> [--template stage|text] [--engine <engine checkout>]
    \\  bespoke --version
    \\
    \\Sample scripts live in scenarios/. Proofs of concept (vertical slices) are a
    \\separate binary: `zig build proofs`, then `bespoke-proofs --help`.
    \\
;

const Subcommand = enum { run, compile, check, init, import, help };

pub fn main(init: std.process.Init) !void {
    // Zig 0.16+: the process supplies the allocator and the I/O that file reads, package
    // writes, and the window's clock go through (P37-01). Standard output is unbuffered, so a
    // message printed just before `std.process.exit` is not lost.
    const io = init.io;
    const allocator = init.gpa;
    var stdout_writer = std.Io.File.stdout().writer(io, &.{});
    const stdout = &stdout_writer.interface;

    var headless = !build_options.desktop;
    var ticks: usize = 20;
    var subcommand: Subcommand = .help;
    var target_file: ?[]const u8 = null;
    var output_file: ?[]const u8 = null;
    var engine_root: []const u8 = build_options.engine_root;
    var template: scaffold.Template = .stage;
    var image_name: ?[]const u8 = null;
    var frames: ?[2]u16 = null;
    var script_file: ?[]const u8 = null;
    var input_file: ?[]const u8 = null;
    var print_facts = false;
    var seed: ?u64 = null;
    var print_kind = false;
    var deps_file: ?[]const u8 = null;

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args.deinit();
    _ = args.next();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "run") or std.mem.eql(u8, arg, "compile") or std.mem.eql(u8, arg, "check") or std.mem.eql(u8, arg, "init") or std.mem.eql(u8, arg, "import")) {
            subcommand = std.meta.stringToEnum(Subcommand, arg).?;
            target_file = args.next();
        } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            output_file = args.next();
        } else if (std.mem.eql(u8, arg, "--name")) {
            image_name = args.next() orelse return fail(stdout, "'--name' needs the image's name");
        } else if (std.mem.eql(u8, arg, "--script")) {
            script_file = args.next() orelse return fail(stdout, "'--script' needs a script path");
        } else if (std.mem.eql(u8, arg, "--frames")) {
            const text = args.next() orelse return fail(stdout, "'--frames' needs a size such as 16x24");
            frames = parse_frames(text) orelse return fail(stdout, "'--frames' needs a size such as 16x24");
        } else if (std.mem.eql(u8, arg, "--engine")) {
            engine_root = args.next() orelse return fail(stdout, "'--engine' needs the engine checkout's path");
        } else if (std.mem.eql(u8, arg, "--template")) {
            const text = args.next() orelse return fail(stdout, "'--template' needs 'stage' or 'text'");
            template = std.meta.stringToEnum(scaffold.Template, text) orelse return fail(stdout, "'--template' must be 'stage' or 'text'");
        } else if (std.mem.eql(u8, arg, "--ticks")) {
            if (args.next()) |t| ticks = std.fmt.parseInt(usize, t, 10) catch 20;
        } else if (std.mem.eql(u8, arg, "--headless")) {
            headless = true;
        } else if (std.mem.eql(u8, arg, "--input")) {
            input_file = args.next() orelse return fail(stdout, "'--input' needs a file of '<tick> <command>' lines");
        } else if (std.mem.eql(u8, arg, "--seed")) {
            const text = args.next() orelse return fail(stdout, "'--seed' needs a whole number");
            seed = std.fmt.parseInt(u64, text, 10) catch return fail(stdout, "'--seed' needs a whole number");
        } else if (std.mem.eql(u8, arg, "--facts")) {
            print_facts = true;
        } else if (std.mem.eql(u8, arg, "--deps")) {
            deps_file = args.next() orelse return fail(stdout, "'--deps' needs a path for the dependency file");
        } else if (std.mem.eql(u8, arg, "--kind")) {
            print_kind = true;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try stdout.print("bespoke {s}\n", .{build_options.version});
            return;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "help")) {
            subcommand = .help;
        } else if (!std.mem.startsWith(u8, arg, "-") and target_file == null) {
            subcommand = .run;
            target_file = arg;
        } else {
            // Former scenario flags (--tavern, --bell-tower, ...) now belong to bespoke-proofs (D-031).
            try stdout.print("error: unknown argument '{s}'. Proofs of concept moved to `bespoke-proofs {s}`.\n\n", .{ arg, arg });
            try stdout.writeAll(usage);
            std.process.exit(1);
        }
    }

    switch (subcommand) {
        .help => try stdout.writeAll(usage),
        .check => {
            const path = target_file orelse return fail(stdout, "'bespoke check' requires a script file path");
            if (!try bespoke.runner.check_file_with(allocator, io, path, stdout, .{ .kind = print_kind })) std.process.exit(1);
        },
        .compile => {
            const path = target_file orelse return fail(stdout, "'bespoke compile' requires an input script file path");
            try bespoke.runner.compile_file_with(allocator, io, path, output_file orelse "game.bspk", stdout, .{ .deps = deps_file });
        },
        .init => {
            const name = target_file orelse return fail(stdout, "'bespoke init' requires a project name");
            // A relative --engine path is made absolute, because the project's build resolves
            // `.path` from its own directory, not from where init ran.
            if (engine_root.len == 0) return fail(stdout, "pass --engine <path> to the matching BeSpoke source checkout");
            const root = std.Io.Dir.cwd().realPathFileAlloc(io, engine_root, allocator) catch
                return fail(stdout, "the engine checkout was not found; pass --engine <path>");
            defer allocator.free(root);
            scaffold.generate_with(allocator, io, std.Io.Dir.cwd(), name, root, @embedFile("engine_license"), template) catch |err| switch (err) {
                error.InvalidProjectName => return fail(stdout, "a project name is a lowercase letter, then lowercase letters, digits, or underscores (at most 32)"),
                error.ProjectExists => return fail(stdout, "that directory already exists; choose another name"),
                else => return err,
            };
            try stdout.print("Created {s}/ (engine: {s})\n\n  cd {s}\n  zig build test\n  zig build run\n", .{ name, root, name });
        },
        .import => {
            const path = target_file orelse return fail(stdout, "'bespoke import' requires a PNG file path");
            const name = image_name orelse return fail(stdout, "'bespoke import' requires '--name <Image>'");
            const options = bespoke.runner.ImportOptions{ .name = name, .frames = frames, .script = script_file };
            if (output_file) |out_path| {
                var buf = std.Io.Writer.Allocating.init(allocator);
                defer buf.deinit();
                if (!try bespoke.runner.import_art(allocator, io, path, options, &buf.writer)) {
                    try stdout.writeAll(buf.written());
                    std.process.exit(1);
                }
                try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = buf.written() });
                try stdout.print("Wrote image '{s}' to {s}\n", .{ name, out_path });
            } else if (!try bespoke.runner.import_art(allocator, io, path, options, stdout)) std.process.exit(1);
        },
        .run => {
            const path = target_file orelse return fail(stdout, "'bespoke run' requires a script or package path");
            const input = if (input_file) |file|
                std.Io.Dir.cwd().readFileAlloc(io, file, allocator, .limited(1024 * 1024)) catch
                    return fail(stdout, "the '--input' file could not be read")
            else
                "";
            defer if (input_file != null) allocator.free(input);
            try bespoke.runner.run_file_with_presenter(build_options.desktop, allocator, io, path, .{
                .ticks = ticks,
                .is_headless = headless,
                .verbose = true,
                .input = input,
                .print_facts = print_facts,
                .seed = seed,
            }, stdout);
        },
    }
}

/// `16x24` as a frame width and height.
fn parse_frames(text: []const u8) ?[2]u16 {
    const x = std.mem.indexOfScalar(u8, text, 'x') orelse return null;
    const w = std.fmt.parseInt(u16, text[0..x], 10) catch return null;
    const h = std.fmt.parseInt(u16, text[x + 1 ..], 10) catch return null;
    return .{ w, h };
}

fn fail(stdout: anytype, msg: []const u8) !void {
    try stdout.print("error: {s}\n", .{msg});
    std.process.exit(1);
}

test {
    // The authoring guide's examples are compiled and played here, where the build records the
    // engine checkout that holds docs/ (P29-02, D-064).
    _ = @import("authoring_guide_test.zig");
}
