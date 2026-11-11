//! `bespoke init <name>`: writes a standalone game project that builds against this engine
//! (P29-01, D-063). The templates live in `src/scaffold/` and are embedded in the binary, so
//! the generator needs no files at run time. Engine code here names no proof (D-031).

const std = @import("std");

pub const MAX_NAME_LEN: usize = 32;

pub const Error = error{
    InvalidProjectName,
    ProjectExists,
    InvalidEngineRoot,
};

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
    .{ .path = "scripts/main.bespoke", .template = @embedFile("scaffold/main.bespoke.tmpl") },
    .{ .path = "README.md", .template = @embedFile("scaffold/README.md.tmpl") },
    .{ .path = ".gitignore", .template = @embedFile("scaffold/gitignore.tmpl") },
};

/// A project name becomes a directory, a Zig package name, and an executable name, so it is
/// held to what all three accept everywhere: a lowercase letter, then lowercase letters,
/// digits, or underscores, at most 32 characters.
pub fn validate_name(name: []const u8) Error!void {
    if (name.len == 0 or name.len > MAX_NAME_LEN) return error.InvalidProjectName;
    if (name[0] < 'a' or name[0] > 'z') return error.InvalidProjectName;
    for (name) |ch| {
        const ok = (ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9') or ch == '_';
        if (!ok) return error.InvalidProjectName;
    }
}

/// Replaces `{{name}}` and `{{engine_root}}`. The engine root lands inside a ZON string, so
/// backslashes and quotes are escaped; a control character is refused rather than escaped.
pub fn render(allocator: std.mem.Allocator, template: []const u8, name: []const u8, engine_root: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    var i: usize = 0;
    while (i < template.len) {
        if (std.mem.startsWith(u8, template[i..], "{{name}}")) {
            try out.appendSlice(name);
            i += "{{name}}".len;
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
/// project records it relative to itself, because Zig 0.13 accepts only relative `.path`
/// dependencies. Moving the project or the engine therefore means editing `build.zig.zon`.
pub fn generate(allocator: std.mem.Allocator, parent: std.fs.Dir, name: []const u8, engine_root: []const u8) !void {
    try validate_name(name);
    if (engine_root.len == 0 or !std.fs.path.isAbsolute(engine_root)) return error.InvalidEngineRoot;
    if (parent.access(name, .{})) |_| {
        return error.ProjectExists;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }

    try parent.makeDir(name);
    var project = try parent.openDir(name, .{});
    defer project.close();
    const project_abs = try project.realpathAlloc(allocator, ".");
    defer allocator.free(project_abs);
    const engine_rel = try std.fs.path.relative(allocator, project_abs, engine_root);
    defer allocator.free(engine_rel);
    // On Windows a path on another drive stays absolute, which Zig would reject.
    if (engine_rel.len == 0 or std.fs.path.isAbsolute(engine_rel)) return error.InvalidEngineRoot;
    for (FILES) |file| {
        if (std.fs.path.dirname(file.path)) |dir| try project.makePath(dir);
        const text = try render(allocator, file.template, name, engine_rel);
        defer allocator.free(text);
        try project.writeFile(.{ .sub_path = file.path, .data = text, .flags = .{ .exclusive = true } });
    }
}

const testing = std.testing;

test "P29-01: project names are lowercase identifiers of at most 32 characters" {
    try validate_name("lighthouse");
    try validate_name("game_2");
    for ([_][]const u8{ "", "Game", "2game", "my-game", "my game", "../x", "a" ** 33, "_x" }) |bad| {
        try testing.expectError(error.InvalidProjectName, validate_name(bad));
    }
}

test "P29-01: templates substitute the name and escape the engine path for ZON" {
    const text = try render(testing.allocator, ".name = \"{{name}}\", .path = \"{{engine_root}}\"", "tide", "C:\\eng \"x\"");
    defer testing.allocator.free(text);
    try testing.expectEqualStrings(".name = \"tide\", .path = \"C:\\\\eng \\\"x\\\"\"", text);
    try testing.expectError(error.InvalidEngineRoot, render(testing.allocator, "{{engine_root}}", "a", "bad\npath"));
    // No template keeps a placeholder after rendering.
    for (FILES) |file| {
        const out = try render(testing.allocator, file.template, "tide", "/engine");
        defer testing.allocator.free(out);
        try testing.expect(std.mem.indexOf(u8, out, "{{") == null);
    }
}

test "P29-01: generate writes every file once and never overwrites a project" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    // The engine sits beside the project here, so the recorded path is "../engine".
    try tmp.dir.makeDir("engine");
    const engine = try tmp.dir.realpathAlloc(testing.allocator, "engine");
    defer testing.allocator.free(engine);
    try generate(testing.allocator, tmp.dir, "tide", engine);
    for (FILES) |file| {
        var path_buf: [64]u8 = undefined;
        const text = try tmp.dir.readFileAlloc(testing.allocator, try std.fmt.bufPrint(&path_buf, "tide/{s}", .{file.path}), 1 << 20);
        defer testing.allocator.free(text);
        try testing.expect(text.len > 0);
    }
    const zon = try tmp.dir.readFileAlloc(testing.allocator, "tide/build.zig.zon", 1 << 16);
    defer testing.allocator.free(zon);
    try testing.expect(std.mem.indexOf(u8, zon, ".path = \"../engine\"") != null);
    try testing.expect(std.mem.indexOf(u8, zon, ".name = \"tide\"") != null);

    try testing.expectError(error.ProjectExists, generate(testing.allocator, tmp.dir, "tide", engine));
    try tmp.dir.makeDir("taken");
    try testing.expectError(error.ProjectExists, generate(testing.allocator, tmp.dir, "taken", engine));
    try testing.expectError(error.InvalidProjectName, generate(testing.allocator, tmp.dir, "../escape", engine));
    try testing.expectError(error.InvalidEngineRoot, generate(testing.allocator, tmp.dir, "fresh", "relative/engine"));
}
