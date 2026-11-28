//! `bespoke init <name>`: writes a standalone game project that builds against this engine
//! (P29-01, D-063). The templates live in `src/scaffold/` and are embedded in the binary, so
//! the generator needs no files at run time. Engine code here names no proof (D-031).

const std = @import("std");
const ListWriter = @import("list_writer.zig").ListWriter;

pub const MAX_NAME_LEN: usize = 32;

pub const Error = error{
    InvalidProjectName,
    ProjectExists,
    InvalidEngineRoot,
};

pub const Template = enum { stage, text };

/// One generated file: its path inside the project and its template.
pub const File = struct {
    path: []const u8,
    template: []const u8,
};

pub const FILES = [_]File{
    .{ .path = "build.zig", .template = @embedFile("scaffold/build.zig.tmpl") },
    .{ .path = "build.zig.zon", .template = @embedFile("scaffold/build.zig.zon.tmpl") },
    .{ .path = "src/main.zig", .template = @embedFile("scaffold/main.zig.tmpl") },
    .{ .path = "src/game_test.zig", .template = @embedFile("scaffold/game_test.zig.tmpl") },
    .{ .path = "src/web.zig", .template = @embedFile("scaffold/web.zig.tmpl") },
    .{ .path = "web/index.html", .template = @embedFile("scaffold/index.html.tmpl") },
    .{ .path = "web/smoke.js", .template = @embedFile("scaffold/smoke.js.tmpl") },
    .{ .path = ".github/workflows/build.yml", .template = @embedFile("scaffold/workflow.yml.tmpl") },
    .{ .path = "scripts/main.bespoke", .template = @embedFile("scaffold/main.bespoke.tmpl") },
    .{ .path = "README.md", .template = @embedFile("scaffold/README.md.tmpl") },
    .{ .path = ".gitignore", .template = @embedFile("scaffold/gitignore.tmpl") },
};

pub const TEXT_FILES = [_]File{
    .{ .path = "build.zig", .template = @embedFile("scaffold/build.zig.tmpl") },
    .{ .path = "build.zig.zon", .template = @embedFile("scaffold/build.zig.zon.tmpl") },
    .{ .path = "src/main.zig", .template = @embedFile("scaffold/main.zig.tmpl") },
    .{ .path = "src/game_test.zig", .template = @embedFile("scaffold/text_game_test.zig.tmpl") },
    .{ .path = "src/web.zig", .template = @embedFile("scaffold/text_web.zig.tmpl") },
    .{ .path = "web/index.html", .template = @embedFile("scaffold/text_index.html.tmpl") },
    .{ .path = "web/smoke.js", .template = @embedFile("scaffold/text_smoke.js.tmpl") },
    .{ .path = ".github/workflows/build.yml", .template = @embedFile("scaffold/workflow.yml.tmpl") },
    .{ .path = "scripts/main.bespoke", .template = @embedFile("scaffold/text_main.bespoke.tmpl") },
    .{ .path = "README.md", .template = @embedFile("scaffold/text_README.md.tmpl") },
    .{ .path = ".gitignore", .template = @embedFile("scaffold/gitignore.tmpl") },
};

pub fn files_for(template: Template) []const File {
    return switch (template) {
        .stage => &FILES,
        .text => &TEXT_FILES,
    };
}

/// A project name becomes a directory, a Zig package name, and an executable name, so it is
/// held to what all three accept everywhere: a lowercase letter, then lowercase letters,
/// digits, or underscores, at most 32 characters, and not a Zig keyword (the package name is
/// a bare enum literal in `build.zig.zon` since Zig 0.14).
pub fn validate_name(name: []const u8) Error!void {
    if (name.len == 0 or name.len > MAX_NAME_LEN) return error.InvalidProjectName;
    if (name[0] < 'a' or name[0] > 'z') return error.InvalidProjectName;
    for (name) |ch| {
        const ok = (ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9') or ch == '_';
        if (!ok) return error.InvalidProjectName;
    }
    if (std.zig.Token.getKeyword(name) != null) return error.InvalidProjectName;
}

/// A Zig package fingerprint (Zig 0.14): the name's CRC-32 in the high 32 bits and a random
/// id in the low 32, never 0 or all ones. Each generated project gets its own id.
pub fn fingerprint(name: []const u8, id: u32) u64 {
    std.debug.assert(id != 0 and id != std.math.maxInt(u32));
    return (@as(u64, std.hash.Crc32.hash(name)) << 32) | id;
}

/// Replaces `{{name}}`, `{{fingerprint}}`, and `{{engine_root}}`. The engine root lands inside a ZON string, so
/// backslashes and quotes are escaped; a control character is refused rather than escaped.
/// Any other `{{` is copied as it is: the CI workflow's `${{ expr }}` expressions belong to
/// GitHub Actions, and placeholders never start with a space.
pub fn render(allocator: std.mem.Allocator, template: []const u8, name: []const u8, engine_root: []const u8, id: u32) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    var i: usize = 0;
    while (i < template.len) {
        if (std.mem.startsWith(u8, template[i..], "{{name}}")) {
            try out.appendSlice(name);
            i += "{{name}}".len;
        } else if (std.mem.startsWith(u8, template[i..], "{{fingerprint}}")) {
            var lw1 = ListWriter.init(&out);
            try lw1.writer.print("0x{x:0>16}", .{fingerprint(name, id)});
            i += "{{fingerprint}}".len;
        } else if (std.mem.startsWith(u8, template[i..], "{{engine_root}}")) {
            for (engine_root) |ch| {
                if (ch < 0x20) return error.InvalidEngineRoot;
                if (ch == '\\' or ch == '"') try out.append('\\');
                try out.append(ch);
            }
            i += "{{engine_root}}".len;
        } else {
            try out.append(template[i]);
            i += 1;
        }
    }
    return out.toOwnedSlice();
}

/// Writes the project into `parent/name`. Refuses when that path already exists, so it never
/// overwrites an author's work. `engine_root` is the absolute path of the engine checkout; the
/// project records it relative to itself, because Zig accepts only relative `.path`
/// dependencies. Moving the project or the engine therefore means editing `build.zig.zon`.
pub fn generate(allocator: std.mem.Allocator, io: std.Io, parent: std.Io.Dir, name: []const u8, engine_root: []const u8, engine_license: []const u8) !void {
    return generate_with(allocator, io, parent, name, engine_root, engine_license, .stage);
}

pub fn generate_with(allocator: std.mem.Allocator, io: std.Io, parent: std.Io.Dir, name: []const u8, engine_root: []const u8, engine_license: []const u8, template: Template) !void {
    try validate_name(name);
    if (engine_root.len == 0 or !std.fs.path.isAbsolute(engine_root)) return error.InvalidEngineRoot;
    if (parent.access(io, name, .{})) |_| {
        return error.ProjectExists;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }

    try parent.createDir(io, name, .default_dir);
    var project = try parent.openDir(io, name, .{});
    defer project.close(io);
    const project_abs = try project.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(project_abs);
    // Both paths are absolute, so the working directory and environment play no part.
    const engine_rel = try std.fs.path.relative(allocator, project_abs, null, project_abs, engine_root);
    defer allocator.free(engine_rel);
    // On Windows a path on another drive stays absolute, which Zig would reject.
    if (engine_rel.len == 0 or std.fs.path.isAbsolute(engine_rel)) return error.InvalidEngineRoot;
    // The fingerprint's random half (Zig 0.16 draws randomness through `Io`); 0 and all ones
    // are reserved, so a draw of either is nudged off them.
    var id_bytes: [4]u8 = undefined;
    io.random(&id_bytes);
    var id = std.mem.readInt(u32, &id_bytes, .little);
    if (id == 0 or id == std.math.maxInt(u32)) id = 1;
    for (files_for(template)) |file| {
        if (std.fs.path.dirname(file.path)) |dir| try project.createDirPath(io, dir);
        const text = try render(allocator, file.template, name, engine_rel, id);
        defer allocator.free(text);
        try project.writeFile(io, .{ .sub_path = file.path, .data = text, .flags = .{ .exclusive = true } });
    }
    // Copy the engine's notice byte for byte; it is not a game license or a template.
    try project.writeFile(io, .{ .sub_path = "LICENSE-BeSpoke", .data = engine_license, .flags = .{ .exclusive = true } });
}

const testing = std.testing;

test "P29-01: project names are lowercase identifiers of at most 32 characters" {
    try validate_name("lighthouse");
    try validate_name("game_2");
    for ([_][]const u8{ "", "Game", "2game", "my-game", "my game", "../x", &@as([33]u8, @splat('a')), "_x", "test", "fn", "error" }) |bad| {
        try testing.expectError(error.InvalidProjectName, validate_name(bad));
    }
}

test "P29-01: templates substitute the name and escape the engine path for ZON" {
    const text = try render(testing.allocator, ".name = \"{{name}}\", .path = \"{{engine_root}}\"", "tide", "C:\\eng \"x\"", 7);
    defer testing.allocator.free(text);
    try testing.expectEqualStrings(".name = \"tide\", .path = \"C:\\\\eng \\\"x\\\"\"", text);
    try testing.expectError(error.InvalidEngineRoot, render(testing.allocator, "{{engine_root}}", "a", "bad\npath", 7));
    // No template keeps a placeholder after rendering. A placeholder is `{{` and a name;
    // GitHub Actions expressions (`${{ matrix.os }}`) start with a space and stay.
    for ([_][]const File{ &FILES, &TEXT_FILES }) |set| {
        for (set) |file| {
            const out = try render(testing.allocator, file.template, "tide", "/engine", 7);
            defer testing.allocator.free(out);
            var at: usize = 0;
            while (std.mem.indexOfPos(u8, out, at, "{{")) |i| : (at = i + 2) {
                try testing.expect(i + 2 < out.len and out[i + 2] == ' ');
            }
        }
    }
}

test "P29-01: generate writes every file once and never overwrites a project" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    // The engine sits beside the project here, so the recorded path is "../engine".
    try tmp.dir.createDir(testing.io, "engine", .default_dir);
    const engine = try tmp.dir.realPathFileAlloc(testing.io, "engine", testing.allocator);
    defer testing.allocator.free(engine);
    const notice = "Engine notice, kept verbatim: {{name}}\n";
    try generate(testing.allocator, testing.io, tmp.dir, "tide", engine, notice);
    for (FILES) |file| {
        var path_buf: [64]u8 = undefined;
        const text = try tmp.dir.readFileAlloc(testing.io, try std.fmt.bufPrint(&path_buf, "tide/{s}", .{file.path}), testing.allocator, .limited(1 << 20));
        defer testing.allocator.free(text);
        try testing.expect(text.len > 0);
    }
    const zon = try tmp.dir.readFileAlloc(testing.io, "tide/build.zig.zon", testing.allocator, .limited(1 << 16));
    defer testing.allocator.free(zon);
    try testing.expect(std.mem.indexOf(u8, zon, ".path = \"../engine\"") != null);
    try testing.expect(std.mem.indexOf(u8, zon, ".name = .tide,") != null);
    const workflow = try tmp.dir.readFileAlloc(testing.io, "tide/.github/workflows/build.yml", testing.allocator, .limited(1 << 16));
    defer testing.allocator.free(workflow);
    try testing.expect(std.mem.indexOf(u8, workflow, "\n  BESPOKE_ENGINE_REF: refs/tags/v1.2.0\n") != null);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, workflow, "ref: ${{ env.BESPOKE_ENGINE_REF }}"));
    // Both jobs install Zig from ziglang.org against a pinned checksum; the setup action
    // could not fetch 0.17.1, so a generated project's CI failed before building (P42-06).
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, workflow, "- name: Install Zig\n"));
    try testing.expect(std.mem.indexOf(u8, workflow, "setup-zig") == null);
    // Windows is deferred until a Windows contributor maintains it (D-143).
    try testing.expect(std.mem.indexOf(u8, workflow, "windows") == null);
    // The fingerprint's high half is the name's CRC-32, as Zig checks it.
    var expect_buf: [32]u8 = undefined;
    const checksum = try std.fmt.bufPrint(&expect_buf, ".fingerprint = 0x{x:0>8}", .{std.hash.Crc32.hash("tide")});
    try testing.expect(std.mem.indexOf(u8, zon, checksum) != null);

    const copied_notice = try tmp.dir.readFileAlloc(testing.io, "tide/LICENSE-BeSpoke", testing.allocator, .limited(1 << 16));
    defer testing.allocator.free(copied_notice);
    try testing.expectEqualStrings(notice, copied_notice);
    try testing.expectError(error.FileNotFound, tmp.dir.access(testing.io, "tide/LICENSE", .{}));
    const readme = try tmp.dir.readFileAlloc(testing.io, "tide/README.md", testing.allocator, .limited(1 << 16));
    defer testing.allocator.free(readme);
    try testing.expect(std.mem.indexOf(u8, readme, "[LICENSE-BeSpoke](LICENSE-BeSpoke)") != null);
    try testing.expect(std.mem.indexOf(u8, readme, "There is no project-wide license") != null);

    try testing.expectError(error.ProjectExists, generate(testing.allocator, testing.io, tmp.dir, "tide", engine, notice));
    try tmp.dir.createDir(testing.io, "taken", .default_dir);
    try testing.expectError(error.ProjectExists, generate(testing.allocator, testing.io, tmp.dir, "taken", engine, notice));
    try testing.expectError(error.InvalidProjectName, generate(testing.allocator, testing.io, tmp.dir, "../escape", engine, notice));
    try testing.expectError(error.InvalidEngineRoot, generate(testing.allocator, testing.io, tmp.dir, "fresh", "relative/engine", notice));
}

test "P49-02: text template generates a turn-based parser project with transcript page" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(testing.io, "engine", .default_dir);
    const engine = try tmp.dir.realPathFileAlloc(testing.io, "engine", testing.allocator);
    defer testing.allocator.free(engine);
    const notice = "Engine notice, kept verbatim\n";
    try generate_with(testing.allocator, testing.io, tmp.dir, "watch", engine, notice, .text);

    for (TEXT_FILES) |file| {
        var path_buf: [64]u8 = undefined;
        const text = try tmp.dir.readFileAlloc(testing.io, try std.fmt.bufPrint(&path_buf, "watch/{s}", .{file.path}), testing.allocator, .limited(1 << 20));
        defer testing.allocator.free(text);
        try testing.expect(text.len > 0);
    }
    const html = try tmp.dir.readFileAlloc(testing.io, "watch/web/index.html", testing.allocator, .limited(1 << 16));
    defer testing.allocator.free(html);
    try testing.expect(std.mem.indexOf(u8, html, "id=\"transcript\"") != null);
    try testing.expect(std.mem.indexOf(u8, html, "wasm_submit_command") != null);
    try testing.expect(std.mem.indexOf(u8, html, "WebAssembly.instantiateStreaming(fetch('watch.wasm'), {})") != null);

    const script = try tmp.dir.readFileAlloc(testing.io, "watch/scripts/main.bespoke", testing.allocator, .limited(1 << 16));
    defer testing.allocator.free(script);
    try testing.expect(std.mem.indexOf(u8, script, "clock: turns") != null);

    const readme = try tmp.dir.readFileAlloc(testing.io, "watch/README.md", testing.allocator, .limited(1 << 16));
    defer testing.allocator.free(readme);
    try testing.expect(std.mem.indexOf(u8, readme, "[LICENSE-BeSpoke](LICENSE-BeSpoke)") != null);
    try testing.expect(std.mem.indexOf(u8, readme, "There is no project-wide license") != null);
}
