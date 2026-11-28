const std = @import("std");
pub const lexer = @import("compiler/lexer.zig");
pub const parser = @import("compiler/parser.zig");
pub const codegen = @import("compiler/codegen.zig");

pub const Lexer = lexer.Lexer;
pub const Parser = parser.Parser;
pub const Codegen = codegen.Codegen;
pub const CompiledProgram = codegen.CompiledProgram;
pub const AST = parser.AST;

const world_mod = @import("world.zig");
const reserved_mod = @import("reserved.zig");
const image_mod = @import("image.zig");
const spatial_mod = @import("spatial.zig");
const dilemma_mod = @import("dilemma.zig");
const World = world_mod.World;
const SpatialSystem = spatial_mod.SpatialSystem;

pub const MAX_SOURCE_SIZE: usize = 16 * 1024 * 1024;

/// High-level compiler entry point: lowers BeSpoke DSL source text directly to VM bytecode (P4-01, P4-02, P4-03).
pub fn compile_source(
    allocator: std.mem.Allocator,
    world: *World,
    spatial: ?*SpatialSystem,
    source: []const u8,
) !CompiledProgram {
    return compile_source_with(allocator, world, spatial, source, null);
}

/// Reads the files a script names, such as `image X from "lamp.png"` (P46-04).
pub const FileSource = parser.FileSource;
pub const includes = @import("compiler/includes.zig");

/// `compile_source` with the files a script may name; the command line passes one that reads
/// beside the script, and every other caller passes null (P46-04, D-156).
pub fn compile_source_with(
    allocator: std.mem.Allocator,
    world: *World,
    spatial: ?*SpatialSystem,
    source: []const u8,
    files: ?FileSource,
) !CompiledProgram {
    if (source.len > MAX_SOURCE_SIZE) return error.ScriptTooLarge;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Includes expand first, so the program reads as one text in source order (D-169).
    var failure = includes.Failure{};
    const expanded = try includes.expand(alloc, source, files, &failure);

    var lex = Lexer.init(alloc, expanded.text);
    defer lex.deinit();

    var parse = try Parser.init(alloc, &lex);
    parse.files = files;
    const ast = try parse.parse_program();

    var cg = Codegen.init(allocator, world, spatial);
    defer {
        for (cg.warnings.items) |w| allocator.free(w.message);
        cg.warnings.deinit(allocator);
    }
    return try cg.compile(&ast);
}

pub const Diagnostic = parser.Diagnostic;
const Suggestions = @import("compiler/diagnostic.zig").Suggestions;

/// Bytes a `CheckResult` keeps for its diagnostic message; matches `Parser.diag_buf`, so a
/// parser message is never cut.
pub const check_message_capacity = 256;

/// Outcome of `check_source`. It owns its diagnostic text: the parser's message lives in a
/// stack-local `Parser.diag_buf` or the check arena, both gone once `check_source` returns,
/// so the message is copied into `message_buf` before they are freed.
/// One warning `check_source` reports (P48-10, D-180), owning its text.
pub const CheckWarning = struct {
    line: u32,
    column: u32,
    /// The included file the warning is in; empty for the main script.
    file_buf: [128]u8 = undefined,
    file_len: usize = 0,
    text: [check_message_capacity]u8 = undefined,
    len: usize = 0,

    pub fn message(self: *const CheckWarning) []const u8 {
        return self.text[0..self.len];
    }

    pub fn file(self: *const CheckWarning) []const u8 {
        return self.file_buf[0..self.file_len];
    }
};

pub const CheckResult = struct {
    is_valid: bool,
    line: u32 = 0,
    column: u32 = 0,
    /// The included file the diagnostic is in, as its include line wrote it; empty for the
    /// main script (P48-15, D-185).
    file_buf: [128]u8 = undefined,
    file_len: usize = 0,
    message_buf: [check_message_capacity]u8 = undefined,
    message_len: usize = 0,
    hint_buf: [Suggestions.max_len]u8 = undefined,
    hint_len: usize = 0,
    /// The error's name, such as `UnboundVariable` (D-173): with the line and column, the part
    /// of a diagnostic 1.0 promises. The message wording may improve in 1.x.
    kind_name: []const u8 = "",
    /// Warnings from a script that compiles (P48-10, D-180): the first four, each owning its text.
    warnings: [4]CheckWarning = undefined,
    warning_count: usize = 0,
    entity_count: usize = 0,
    routine_count: usize = 0,
    rule_count: usize = 0,
    scene_count: usize = 0,
    bytecode_len: usize = 0,

    fn failure(line: u32, column: u32, text: []const u8) CheckResult {
        var res = CheckResult{ .is_valid = false, .line = line, .column = column };
        res.message_len = @min(text.len, res.message_buf.len);
        @memcpy(res.message_buf[0..res.message_len], text[0..res.message_len]);
        return res;
    }

    fn with_kind(self: CheckResult, err: anyerror) CheckResult {
        var res = self;
        res.kind_name = @errorName(err);
        return res;
    }

    /// The file the diagnostic is in: empty for the main script, else an included file's path
    /// from the main script's folder.
    pub fn file(self: *const CheckResult) []const u8 {
        return self.file_buf[0..self.file_len];
    }

    fn in_file(self: CheckResult, path: []const u8) CheckResult {
        var res = self;
        res.file_len = @min(path.len, res.file_buf.len);
        @memcpy(res.file_buf[0..res.file_len], path[0..res.file_len]);
        return res;
    }

    /// The diagnostic's error kind; empty when the source is valid.
    pub fn kind(self: *const CheckResult) []const u8 {
        return self.kind_name;
    }

    fn with_hint(self: CheckResult, hint: ?[]const u8) CheckResult {
        var res = self;
        if (hint) |name| {
            const len = @min(name.len, res.hint_buf.len);
            res.hint_len = len;
            @memcpy(res.hint_buf[0..len], name[0..len]);
        }
        return res;
    }

    pub fn suggestion(self: *const CheckResult) ?[]const u8 {
        return if (self.hint_len == 0) null else self.hint_buf[0..self.hint_len];
    }

    /// The diagnostic text; empty when the source is valid. Borrows from `self`.
    pub fn message(self: *const CheckResult) []const u8 {
        return self.message_buf[0..self.message_len];
    }

    /// The diagnostic, or null when the source is valid. Its message borrows from `self`, so
    /// read it while `self` lives (copying the result moves the bytes, not the slice).
    pub fn diagnostic(self: *const CheckResult) ?Diagnostic {
        if (self.is_valid) return null;
        return .{ .line = self.line, .column = self.column, .message = self.message() };
    }
};

/// Validates syntax and semantic compilation of BeSpoke DSL source without permanent side effects (P15-03, D-018).
/// A script's palette: its colours and the codes its `palette:` block declares, which
/// `bespoke import` extends (P46-04). Everything is allocated in `arena`.
pub const ScriptPalette = struct { colours: []const image_mod.Colour, codes: []const []const u8 };

/// Parses `source` far enough to read its palette; a script that does not parse returns the
/// parse error, which `check_source` describes.
pub fn script_palette(arena: std.mem.Allocator, source: []const u8, files: ?FileSource) !ScriptPalette {
    var failure = includes.Failure{};
    const expanded = try includes.expand(arena, source, files, &failure);
    var lex = Lexer.init(arena, expanded.text);
    var parse = try Parser.init(arena, &lex);
    parse.files = files;
    const ast = try parse.parse_program();
    return .{ .colours = ast.art.palette, .codes = ast.art.palette_codes };
}

/// One image a script declares (P47-02, D-196): its name, the PNG it reads (`file`, empty for
/// inline rows) as the `from` line wrote it, the script file and line that declare it, and its
/// size and frames.
pub const ArtImage = struct {
    name: []const u8,
    file: []const u8,
    script: []const u8,
    line: u32,
    width: u16,
    height: u16,
    frame_width: u16,
    frame_height: u16,
};

/// One animation of a `sprite` or `look` block: the frames its owner shows for `anim`.
pub const ArtAnimation = struct {
    owner: []const u8,
    look: bool,
    image: u16,
    anim: image_mod.Anim,
    steps: []const image_mod.Step,
};

/// What a tool needs to edit a script's art: its images, their animations, and the colours a
/// declared `palette:` allows (empty when the script declares none, so any colour is allowed).
pub const ArtSources = struct {
    images: []const ArtImage,
    animations: []const ArtAnimation,
    palette: []const image_mod.Colour,
};

/// Parses `source` far enough to list its art, as `script_palette` does: everything lives in
/// `arena`. A script that does not parse returns the parse error, which `check_source_with`
/// describes. Used by the Studio's pixel editor to find the PNG behind each image (D-196).
pub fn art_sources(arena: std.mem.Allocator, source: []const u8, files: ?FileSource) !ArtSources {
    var failure = includes.Failure{};
    const expanded = try includes.expand(arena, source, files, &failure);
    var lex = Lexer.init(arena, expanded.text);
    var parse = try Parser.init(arena, &lex);
    parse.files = files;
    const ast = try parse.parse_program();
    const images = try arena.alloc(ArtImage, ast.art.images.len);
    // The parser resolves images in declaration order, one per source, so index i of both
    // lists is the same image.
    for (images, ast.art.images, parse.image_srcs.items) |*out, img, src| {
        const at = expanded.locate(@intCast(src.at.line));
        out.* = .{
            .name = img.name,
            .file = if (src.file) |f| f.slice else "",
            .script = at.file,
            .line = at.line,
            .width = img.width,
            .height = img.height,
            .frame_width = img.frame_width,
            .frame_height = img.frame_height,
        };
    }
    var anims: std.ArrayList(ArtAnimation) = .empty;
    for (ast.art.sprites) |sp| for (sp.animations, 0..) |steps, a| if (steps.len > 0)
        try anims.append(arena, .{ .owner = sp.target, .look = false, .image = sp.image, .anim = @enumFromInt(a), .steps = steps });
    for (ast.art.looks) |lk| for (lk.animations, 0..) |steps, a| if (steps.len > 0)
        try anims.append(arena, .{ .owner = lk.name, .look = true, .image = lk.image, .anim = @enumFromInt(a), .steps = steps });
    // The declared colours follow the transparent first code; a script with no `palette:`
    // block declares none and allows every colour (D-166).
    const declared = ast.art.palette_codes.len;
    return .{ .images = images, .animations = anims.items, .palette = if (declared > 1) ast.art.palette[1..declared] else &.{} };
}

/// Where something in a scene stands, for a room editor (P47-03, D-200): the art pixel a
/// room block gives (`placed`), or, for one it does not place, the art pixel nearest its
/// default spot. `drawn_x`/`drawn_y` is the art pixel where the engine draws it, after the
/// snap (`spatial.art_to_world`).
pub const RoomPlace = struct {
    name: []const u8,
    prop: bool,
    x: u32,
    y: u32,
    drawn_x: u32,
    drawn_y: u32,
    placed: bool,
    /// A grid's `place` line positions this mark (D-201); the room block leaves it out.
    by_grid: bool = false,
};

pub const RoomArea = struct { prop: []const u8, x: u16, y: u16, w: u16, h: u16, in_block: bool };
pub const RoomWalkway = struct { a: []const u8, b: []const u8 };
pub const RoomExit = struct { mark: []const u8, to_scene: []const u8, to_mark: []const u8 };
pub const RoomGridRect = struct { attribute: []const u8, x: u32, y: u32, width: u32, height: u32 };
pub const RoomGridPlace = struct { mark: []const u8, x: u32, y: u32 };
pub const RoomGrid = struct {
    name: []const u8,
    width: u32,
    height: u32,
    cell: u32,
    origin_x: i32,
    origin_y: i32,
    burn: u32,
    spread: u32,
    dissipate: u32,
    flow: u32,
    rects: []const RoomGridRect,
    places: []const RoomGridPlace,
    /// Where the `grid` block is written, for the grid editor to rewrite it (D-201).
    block: ScriptLines,
};
/// A range of lines in one script file: `script` as an include line wrote it (empty for the
/// main script) and lines `line` to `end_line`, counted in that file.
pub const ScriptLines = struct { script: []const u8, line: u32, end_line: u32 };

/// One scene as a room editor sees it: where it is declared, its backdrop's image name, its
/// marks then props, the walkways (or `chained` for the default chain), exits, areas for its
/// props, grids, and its room block, if any.
pub const SceneRoom = struct {
    name: []const u8,
    declared: ScriptLines,
    backdrop: []const u8,
    places: []const RoomPlace,
    chained: bool,
    walkways: []const RoomWalkway,
    exits: []const RoomExit,
    areas: []const RoomArea,
    grids: []const RoomGrid,
    block: ?ScriptLines,
};

/// Parses `source` far enough to list its scenes and room blocks, as `art_sources` does:
/// everything lives in `arena`, and a script that does not parse returns the parse error.
/// Only scenes declared with `scene <Name>:` are listed, since only they take room blocks.
pub fn room_sources(arena: std.mem.Allocator, source: []const u8, files: ?FileSource) ![]const SceneRoom {
    var failure = includes.Failure{};
    const expanded = try includes.expand(arena, source, files, &failure);
    var lex = Lexer.init(arena, expanded.text);
    var parse = try Parser.init(arena, &lex);
    parse.files = files;
    const ast = try parse.parse_program();
    const out = try arena.alloc(SceneRoom, ast.scene_defs.items.len);
    for (ast.scene_defs.items, out) |sd, *room_out| {
        const room: ?parser.RoomDecl = for (ast.rooms) |r| {
            if (std.mem.eql(u8, r.scene, sd.name)) break r;
        } else null;
        var places: std.ArrayList(RoomPlace) = .empty;
        for ([_]bool{ false, true }) |prop| {
            const names = if (prop) sd.props.items else sd.marks.items;
            for (names, 0..) |name, idx| {
                var item = RoomPlace{ .name = name, .prop = prop, .x = 0, .y = 0, .drawn_x = 0, .drawn_y = 0, .placed = false };
                if (room) |r| for (r.places) |p| if (p.prop == prop and std.mem.eql(u8, p.name, name)) {
                    item.x = p.x;
                    item.y = p.y;
                    item.placed = true;
                };
                // A grid's `place` puts a mark at its cell's centre (D-054, D-201).
                var by_grid: ?spatial_mod.Point2D = null;
                if (!prop) for (ast.grids.items) |g| if (std.mem.eql(u8, g.room, sd.name)) for (g.places) |gp| if (std.mem.eql(u8, gp.mark, name)) {
                    const half: i32 = @intCast(g.cell_size / 2);
                    const size: i32 = @intCast(g.cell_size);
                    by_grid = .{ .x = g.origin_x + @as(i32, @intCast(gp.x)) * size + half, .y = g.origin_y + @as(i32, @intCast(gp.y)) * size + half };
                };
                item.by_grid = by_grid != null;
                const world: spatial_mod.Point2D = if (by_grid) |w| w else if (item.placed) spatial_mod.art_to_world(item.x, item.y) else if (prop)
                    .{ .x = 10 + codegen.stage_x(idx, names.len), .y = -6 }
                else
                    .{ .x = codegen.stage_x(idx, names.len), .y = 0 };
                const drawn = spatial_mod.world_to_art(world);
                if (!item.placed or item.by_grid) {
                    item.x = drawn.x;
                    item.y = drawn.y;
                }
                item.drawn_x = drawn.x;
                item.drawn_y = drawn.y;
                try places.append(arena, item);
            }
        }
        var walkways: std.ArrayList(RoomWalkway) = .empty;
        var exits: std.ArrayList(RoomExit) = .empty;
        if (room) |r| {
            for (r.walkways) |w| try walkways.append(arena, .{ .a = w.a, .b = w.b });
            for (r.exits) |e| try exits.append(arena, .{ .mark = e.mark, .to_scene = e.to_scene, .to_mark = e.to_mark });
        }
        var areas: std.ArrayList(RoomArea) = .empty;
        for (ast.art.areas) |a| for (sd.props.items) |p| if (std.mem.eql(u8, p, a.target)) {
            const line: u32 = @intCast(a.at.line);
            const in_block = if (room) |r| line >= r.at.line and line <= r.end_line else false;
            try areas.append(arena, .{ .prop = a.target, .x = a.x, .y = a.y, .w = a.w, .h = a.h, .in_block = in_block });
        };
        var grids: std.ArrayList(RoomGrid) = .empty;
        for (ast.grids.items) |g| if (std.mem.eql(u8, g.room, sd.name)) {
            const rects = try arena.alloc(RoomGridRect, g.rects.len);
            for (g.rects, rects) |src, *dst| dst.* = .{ .attribute = src.attribute, .x = src.x, .y = src.y, .width = src.width, .height = src.height };
            const gplaces = try arena.alloc(RoomGridPlace, g.places.len);
            for (g.places, gplaces) |src, *dst| dst.* = .{ .mark = src.mark, .x = src.x, .y = src.y };
            const from = expanded.locate(g.line);
            const to = expanded.locate(g.end_line);
            try grids.append(arena, .{
                .name = g.name,
                .width = g.width,
                .height = g.height,
                .cell = g.cell_size,
                .origin_x = g.origin_x,
                .origin_y = g.origin_y,
                .burn = g.burn_ticks,
                .spread = g.spread_ticks,
                .dissipate = g.dissipate_ticks,
                .flow = g.flow_ticks,
                .rects = rects,
                .places = gplaces,
                .block = .{ .script = from.file, .line = from.line, .end_line = to.line },
            });
        };
        const declared_at = expanded.locate(sd.line);
        const declared_end = expanded.locate(sd.end_line);
        room_out.* = .{
            .name = sd.name,
            .declared = .{ .script = declared_at.file, .line = declared_at.line, .end_line = declared_end.line },
            .backdrop = if (sd.backdrop) |b| b.slice else "",
            .places = places.items,
            .chained = if (room) |r| r.walkways.len == 0 else true,
            .walkways = walkways.items,
            .exits = exits.items,
            .areas = areas.items,
            .grids = grids.items,
            .block = if (room) |r| blk: {
                const from = expanded.locate(@intCast(r.at.line));
                const to = expanded.locate(r.end_line);
                break :blk .{ .script = from.file, .line = from.line, .end_line = to.line };
            } else null,
        };
    }
    return out;
}

/// A scene as the cast editor sees it (P47-05, D-202): its lists, where it is declared, and
/// whether it has a room block, which a new mark or prop must then be placed in.
pub const CastScene = struct {
    name: []const u8,
    declared: ScriptLines,
    cast: []const []const u8,
    props: []const []const u8,
    marks: []const []const u8,
    room_block: ?ScriptLines,
};
pub const CastName = struct { entity: []const u8, text: []const u8, at: ScriptLines };
pub const CastAxis = struct { name: []const u8, low: []const u8, high: []const u8, at: ScriptLines };
/// A top-level `remember <Axis>(<Character>, N)`: a starting value.
pub const CastValue = struct { axis: []const u8, character: []const u8, value: i32, at: ScriptLines };
/// A routine (`name` its routine name, `actor` its entity) or a cue handler (`name` its cue,
/// `actor` its first parameter).
pub const CastCode = struct { handler: bool, name: []const u8, actor: []const u8, at: ScriptLines };
pub const CastSources = struct {
    scenes: []const CastScene,
    names: []const CastName,
    axes: []const CastAxis,
    values: []const CastValue,
    code: []const CastCode,
};

/// Parses `source` far enough to list what the cast editor edits (P47-05, D-202), as
/// `room_sources` does: everything lives in `arena`, and a script that does not parse returns
/// the parse error. Each line is given in the file that holds it.
pub fn cast_sources(arena: std.mem.Allocator, source: []const u8, files: ?FileSource) !CastSources {
    var failure = includes.Failure{};
    const expanded = try includes.expand(arena, source, files, &failure);
    var lex = Lexer.init(arena, expanded.text);
    var parse = try Parser.init(arena, &lex);
    parse.files = files;
    const ast = try parse.parse_program();
    const lines = struct {
        fn of(e: includes.Expanded, from: u32, to: u32) ScriptLines {
            const a = e.locate(from);
            const b = e.locate(to);
            return .{ .script = a.file, .line = a.line, .end_line = b.line };
        }
    }.of;
    const scenes = try arena.alloc(CastScene, ast.scene_defs.items.len);
    for (ast.scene_defs.items, scenes) |sd, *out| {
        const room: ?parser.RoomDecl = for (ast.rooms) |r| {
            if (std.mem.eql(u8, r.scene, sd.name)) break r;
        } else null;
        out.* = .{
            .name = sd.name,
            .declared = lines(expanded, sd.line, sd.end_line),
            .cast = sd.cast.items,
            .props = sd.props.items,
            .marks = sd.marks.items,
            .room_block = if (room) |r| lines(expanded, @intCast(r.at.line), r.end_line) else null,
        };
    }
    const names = try arena.alloc(CastName, ast.display_names.items.len);
    for (ast.display_names.items, names) |n, *out| out.* = .{ .entity = n.entity, .text = n.text, .at = lines(expanded, n.line, n.line) };
    const axes = try arena.alloc(CastAxis, ast.axes.items.len);
    for (ast.axes.items, axes) |a, *out| out.* = .{ .name = a.name, .low = a.poles[0], .high = a.poles[1], .at = lines(expanded, a.line, a.end_line) };
    var values: std.ArrayList(CastValue) = .empty;
    for (parse.initial_fact_lines.items) |f| {
        if (f.args.len != 2) continue;
        for (ast.axes.items) |a| if (std.mem.eql(u8, a.name, f.relation)) {
            const v = std.fmt.parseInt(i32, f.args[1], 10) catch break;
            try values.append(arena, .{ .axis = a.name, .character = f.args[0], .value = v, .at = lines(expanded, f.line, f.line) });
            break;
        };
    }
    var code: std.ArrayList(CastCode) = .empty;
    for (ast.routines.items) |r| try code.append(arena, .{ .handler = false, .name = r.name, .actor = r.entity, .at = lines(expanded, r.line, r.line) });
    for (ast.cue_handlers.items) |h| try code.append(arena, .{ .handler = true, .name = h.cue_name, .actor = if (h.params.len > 0) h.params[0] else "", .at = lines(expanded, h.line, h.line) });
    return .{ .scenes = scenes, .names = names, .axes = axes, .values = values.items, .code = code.items };
}

/// One `leans` line as the dilemma editor's preview needs it (P47-13, D-203).
pub const DilemmaLean = struct { points: u32, toward: []const u8, unless: bool };
pub const DilemmaTierLine = struct { text: []const u8, action: []const u8 };
/// A dilemma with what its tier preview needs and where its block is written.
pub const DilemmaInfo = struct {
    name: []const u8,
    actor: []const u8,
    axis: []const u8,
    counter: []const u8,
    strong: u8,
    moderate: u8,
    leans: []const DilemmaLean,
    /// Indexed by `dilemma.Tier`: strong and moderate toward `axis`, neutral, moderate and
    /// strong toward `counter`.
    tiers: [dilemma_mod.TIER_COUNT]DilemmaTierLine,
    block: ScriptLines,
};
pub const DecisionInfo = struct { name: []const u8, actor: []const u8, options: []const []const u8, block: ScriptLines };
pub const RedLineInfo = struct { actor: []const u8, options: []const []const u8, at: ScriptLines };
pub const DilemmaSources = struct {
    dilemmas: []const DilemmaInfo,
    decisions: []const DecisionInfo,
    red_lines: []const RedLineInfo,
};

/// Parses `source` far enough to list its dilemmas, decisions, and red lines for the Studio's
/// dilemma editor (P47-13, D-203), as `cast_sources` does: everything lives in `arena`, and a
/// script that does not parse returns the parse error.
pub fn dilemma_sources(arena: std.mem.Allocator, source: []const u8, files: ?FileSource) !DilemmaSources {
    var failure = includes.Failure{};
    const expanded = try includes.expand(arena, source, files, &failure);
    var lex = Lexer.init(arena, expanded.text);
    var parse = try Parser.init(arena, &lex);
    parse.files = files;
    const ast = try parse.parse_program();
    const lines = struct {
        fn of(e: includes.Expanded, from: u32, to: u32) ScriptLines {
            const a = e.locate(from);
            const b = e.locate(to);
            return .{ .script = a.file, .line = a.line, .end_line = b.line };
        }
    }.of;
    const dilemmas = try arena.alloc(DilemmaInfo, ast.dilemmas.items.len);
    for (ast.dilemmas.items, dilemmas) |d, *out| {
        const leans = try arena.alloc(DilemmaLean, d.leans.len);
        for (d.leans, leans) |l, *o| o.* = .{ .points = l.points, .toward = l.toward, .unless = l.negated };
        var tiers: [dilemma_mod.TIER_COUNT]DilemmaTierLine = undefined;
        for (d.responses, &tiers) |r, *t| t.* = .{ .text = r.line, .action = r.action };
        const bounds = d.tiers orelse .{ dilemma_mod.DEFAULT_STRONG_AT, dilemma_mod.DEFAULT_MODERATE_AT };
        out.* = .{
            .name = d.name,
            .actor = d.actor,
            .axis = d.axis,
            .counter = d.counter,
            .strong = bounds[0],
            .moderate = bounds[1],
            .leans = leans,
            .tiers = tiers,
            .block = lines(expanded, d.line, d.end_line),
        };
    }
    const decisions = try arena.alloc(DecisionInfo, ast.decisions.items.len);
    for (ast.decisions.items, decisions) |d, *out| {
        const options = try arena.alloc([]const u8, d.options.len);
        for (d.options, options) |o, *n| n.* = o.name;
        out.* = .{ .name = d.name, .actor = d.actor, .options = options, .block = lines(expanded, d.line, d.end_line) };
    }
    const red = try arena.alloc(RedLineInfo, ast.red_lines.items.len);
    for (ast.red_lines.items, red) |r, *out| out.* = .{ .actor = r.actor, .options = r.options, .at = lines(expanded, r.line, r.line) };
    return .{ .dilemmas = dilemmas, .decisions = decisions, .red_lines = red };
}

/// One line of a conversation for the dialogue map (P47-04, D-204): a `say` (`choice` false,
/// `speaker` set) or a `choice` (its guard as written and whether it can hold). `depth` is how
/// many choices it sits under; a node's children follow it at `depth + 1`.
pub const DialogueNode = struct {
    choice: bool,
    depth: u16,
    speaker: []const u8 = "",
    text: []const u8,
    guard: []const u8 = "",
    /// 0 when the guard can hold (or there is none), 1 when it never holds, 2 when it always
    /// holds because it is `not` a relation nothing writes.
    never: u8 = 0,
    line: u32,
};
/// A body that holds choices: a routine, a cue handler, a `when` rule, or the top level.
pub const Conversation = struct { title: []const u8, at: ScriptLines, nodes: []const DialogueNode };

/// Parses `source` far enough to list every conversation with choices (P47-04, D-204), as
/// `cast_sources` does. A guard's relation the script declares and nothing writes is marked,
/// by the same rule as the compiler's warning (`codegen.written_relations`).
pub fn dialogue_sources(arena: std.mem.Allocator, source: []const u8, files: ?FileSource) ![]const Conversation {
    var failure = includes.Failure{};
    const expanded = try includes.expand(arena, source, files, &failure);
    var lex = Lexer.init(arena, expanded.text);
    var parse = try Parser.init(arena, &lex);
    parse.files = files;
    const ast = try parse.parse_program();
    const written = try codegen.written_relations(arena, &ast);
    var declared = std.StringHashMap(void).init(arena);
    for (ast.relations.items) |r| try declared.put(r.name, {});
    const Build = struct {
        e: includes.Expanded,
        a: std.mem.Allocator,
        written: ?std.StringHashMap(void),
        declared: *const std.StringHashMap(void),
        nodes: std.ArrayList(DialogueNode) = .empty,
        any: bool = false,

        fn pattern(b: *@This(), out: *std.ArrayList(u8), p: parser.FactPattern) !void {
            try out.appendSlice(b.a, p.relation);
            try out.append(b.a, '(');
            for (p.args, 0..) |arg, i| {
                if (i > 0) try out.appendSlice(b.a, ", ");
                try out.appendSlice(b.a, arg);
            }
            try out.append(b.a, ')');
        }

        fn guard_text(b: *@This(), c: parser.DialogueChoice) ![]const u8 {
            var out: std.ArrayList(u8) = .empty;
            if (c.guard) |g| switch (g) {
                .has_fact => |p| try b.pattern(&out, p),
                .not_fact => |p| {
                    try out.appendSlice(b.a, "not ");
                    try b.pattern(&out, p);
                },
                .count_at_least => |x| {
                    try out.print(b.a, "{d} of ", .{x.threshold});
                    try b.pattern(&out, x.pattern);
                },
                .points_at_least => |x| {
                    try out.print(b.a, "{d} points of ", .{x.threshold});
                    try b.pattern(&out, x.pattern);
                },
                .roll_gte => |r| try out.print(b.a, "roll {d}d{d} at least {d}", .{ r.count, r.sides, r.threshold }),
            };
            for (c.where_patterns, 0..) |p, i| {
                try out.appendSlice(b.a, if (i == 0) (if (out.items.len > 0) " where " else "where ") else " and ");
                try b.pattern(&out, p);
            }
            return out.items;
        }

        fn walk(b: *@This(), stmts: []const parser.Stmt, depth: u16) !void {
            for (stmts) |st| switch (st) {
                .say => |x| try b.nodes.append(b.a, .{ .choice = false, .depth = depth, .speaker = x.speaker, .text = x.text, .line = b.e.locate(x.line).line }),
                .loop_stmt => |body| try b.walk(body, depth),
                .if_stmt => |x| try b.walk(x.body, depth),
                .interrupt_with => |x| try b.walk(x.body, depth),
                .choice_block => |cs| {
                    b.any = true;
                    for (cs) |c| {
                        var never: u8 = 0;
                        if (b.written) |w| {
                            var buf: [9]parser.FactPattern = undefined;
                            for (codegen.guard_patterns(c, &buf)) |p| {
                                if (!b.declared.contains(p.relation) or w.contains(p.relation)) continue;
                                const negated = if (c.guard) |g| g == .not_fact and std.mem.eql(u8, g.not_fact.relation, p.relation) else false;
                                never = if (negated) 2 else 1;
                                break;
                            }
                        }
                        try b.nodes.append(b.a, .{ .choice = true, .depth = depth, .text = c.text, .guard = try b.guard_text(c), .never = never, .line = b.e.locate(c.line).line });
                        try b.walk(c.body, depth + 1);
                    }
                },
                else => {},
            };
        }
    };
    var out: std.ArrayList(Conversation) = .empty;
    const add = struct {
        fn one(list: *std.ArrayList(Conversation), b: *Build, title: []const u8, line: u32, stmts: []const parser.Stmt) !void {
            b.nodes = .empty;
            b.any = false;
            try b.walk(stmts, 0);
            if (!b.any) return;
            const at = b.e.locate(line);
            try list.append(b.a, .{ .title = title, .at = .{ .script = at.file, .line = at.line, .end_line = at.line }, .nodes = b.nodes.items });
        }
    }.one;
    var b = Build{ .e = expanded, .a = arena, .written = written, .declared = &declared };
    const first_line: u32 = if (parse.initial_fact_lines.items.len > 0) parse.initial_fact_lines.items[0].line else 1;
    try add(&out, &b, "Top level", first_line, ast.initial_stmts.items);
    for (ast.cue_handlers.items) |h| {
        var title: std.ArrayList(u8) = .empty;
        try title.print(arena, "on cue {s}(", .{h.cue_name});
        for (h.params, 0..) |p, i| try title.print(arena, "{s}{s}", .{ if (i > 0) ", " else "", p });
        try title.append(arena, ')');
        try add(&out, &b, title.items, h.line, h.body);
    }
    for (ast.routines.items) |r| try add(&out, &b, try std.fmt.allocPrint(arena, "routine {s}({s})", .{ r.name, r.entity }), r.line, r.body);
    return out.items;
}

pub fn check_source(allocator: std.mem.Allocator, source: []const u8) CheckResult {
    return check_source_with(allocator, source, null);
}

pub fn check_source_with(allocator: std.mem.Allocator, source: []const u8, files: ?FileSource) CheckResult {
    return check_source_against(allocator, source, files, &reserved_mod.AUTHOR_FACING);
}

/// `check_source_with` against a given table of engine relations (P48-10, D-180), so a test can
/// stand in for a later release.
pub fn check_source_against(allocator: std.mem.Allocator, source: []const u8, files: ?FileSource, engine_relations: []const reserved_mod.AuthorRelation) CheckResult {
    if (source.len > MAX_SOURCE_SIZE) return CheckResult.failure(1, 1, "script exceeds the 16 MiB source limit").with_kind(error.ScriptTooLarge);
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Includes expand first (D-169); every position below is in the expanded text, and
    // `placed` maps it back to its file and line (D-185).
    var include_failure = includes.Failure{};
    const expanded = includes.expand(alloc, source, files, &include_failure) catch |err| switch (err) {
        error.IncludeFailed => return CheckResult.failure(include_failure.line, include_failure.column, include_failure.message).in_file(include_failure.file).with_kind(err),
        error.OutOfMemory => return CheckResult.failure(1, 1, failure_message(err)).with_kind(err),
    };
    const text = expanded.text;

    var lex = Lexer.init(alloc, text);
    defer lex.deinit();

    var parse = Parser.init(alloc, &lex) catch |err| return placed(expanded, lexer_failure(&lex, err));
    parse.files = files;

    const ast = parse.parse_program() catch |err| {
        // `parse.diagnostic.message` points into `parse.diag_buf`; `failure` copies it out.
        if (parse.diagnostic) |d| return placed(expanded, CheckResult.failure(d.line, d.column, d.message).with_hint(parse.suggestion).with_kind(err));
        return placed(expanded, lexer_failure(&lex, err));
    };

    var dummy_world = World.init(alloc, 1024 * 1024) catch |err| return CheckResult.failure(1, 1, failure_message(err)).with_kind(err);
    defer dummy_world.deinit();

    var dummy_spatial = SpatialSystem.init(alloc);
    defer dummy_spatial.deinit();

    var cg = Codegen.init(alloc, &dummy_world, &dummy_spatial);
    cg.engine_relations = engine_relations;
    var compiled = cg.compile(&ast) catch |err| {
        var line = cg.error_line;
        var col = cg.error_column;
        if (line == 0) {
            const pos = source_position(text, cg.error_context);
            line = pos[0];
            col = pos[1];
        }
        if (err == error.UnreachableCueHandler) {
            // Name both handlers: the refused one by position, the one that covers it by line,
            // with its file when it is in another one.
            var buf: [check_message_capacity]u8 = undefined;
            const earlier = expanded.locate(source_position(text, cg.error_related)[0]);
            const here = expanded.locate(line);
            const message_text = if (std.mem.eql(u8, earlier.file, here.file))
                std.fmt.bufPrint(&buf, "this handler can never run: the handler on line {d} has the same signature and no guard", .{earlier.line}) catch failure_message(err)
            else
                std.fmt.bufPrint(&buf, "this handler can never run: the handler on line {d} of {s} has the same signature and no guard", .{ earlier.line, if (earlier.file.len > 0) earlier.file else "the main script" }) catch failure_message(err);
            return placed(expanded, CheckResult.failure(line, col, message_text).with_kind(err));
        }
        return placed(expanded, CheckResult.failure(line, col, failure_message(err)).with_hint(cg.error_suggestion).with_kind(err));
    };
    defer compiled.deinit();

    var result = CheckResult{
        .is_valid = true,
        .entity_count = ast.entities.items.len,
        .routine_count = ast.routines.items.len,
        .rule_count = ast.when_rules.items.len,
        .scene_count = if (ast.scene_defs.items.len > 0) ast.scene_defs.items.len else ast.scenes.items.len,
        .bytecode_len = compiled.chunk.count(),
    };
    for (cg.warnings.items) |w| {
        if (result.warning_count == result.warnings.len) break;
        const pos = source_position(text, w.context);
        const at = expanded.locate(pos[0]);
        var line = &result.warnings[result.warning_count];
        line.* = .{ .line = at.line, .column = pos[1] };
        line.file_len = @min(at.file.len, line.file_buf.len);
        @memcpy(line.file_buf[0..line.file_len], at.file[0..line.file_len]);
        line.len = @min(w.message.len, line.text.len);
        @memcpy(line.text[0..line.len], w.message[0..line.len]);
        result.warning_count += 1;
    }
    return result;
}

/// Moves a diagnostic from its line in the expanded text to the file and line it came from.
fn placed(expanded: includes.Expanded, res: CheckResult) CheckResult {
    const at = expanded.locate(res.line);
    var moved = res;
    moved.line = at.line;
    return moved.in_file(at.file);
}

fn lexer_failure(lex: *const Lexer, err: anyerror) CheckResult {
    if (lex.string_start) |tok| return CheckResult.failure(tok.line, tok.col, "unterminated string; add a closing double quote").with_kind(err);
    return CheckResult.failure(lex.line, lex.col, failure_message(err)).with_kind(err);
}

fn source_position(source: []const u8, context: []const u8) struct { u32, u32 } {
    const start = @intFromPtr(source.ptr);
    const pos = @intFromPtr(context.ptr);
    // Some AST names are assembled in the arena or synthesized. Never search for their
    // spelling in the source: that could point at an earlier, unrelated use.
    if (pos < start or pos - start > source.len) return .{ 1, 1 };
    const prefix = source[0 .. pos - start];
    const line = std.mem.count(u8, prefix, "\n") + 1;
    const line_start = if (std.mem.lastIndexOfScalar(u8, prefix, '\n')) |i| i + 1 else 0;
    return .{ @intCast(line), @intCast(prefix.len - line_start + 1) };
}

fn failure_message(err: anyerror) []const u8 {
    return switch (err) {
        // Bytecode's ListWriter translates allocation failure to WriteFailed.
        error.OutOfMemory, error.WriteFailed => "not enough memory to check this script",
        error.Overflow => "number is outside the supported range",
        error.InvalidCharacter => "invalid numeric literal",
        error.DuplicateRoutineName => "routine name is already in use",
        error.UnboundVariable => "a lowercase name is a variable, and nothing binds this one here; names of things start with a capital letter",
        error.VariableNotAllowedHere => "a cue parameter cannot be used in this statement",
        error.WhenBodyVariable => "a when rule's variables cannot be used in its body yet; name the entity",
        error.LowercaseName => "names of things start with a capital letter",
        error.CaseTwinName => "this name differs from an existing name only in letter case; names are case-sensitive",
        error.UnknownLook => "this names a look the script does not declare with 'look'",
        error.NameForUnknownThing => "this gives a name to something the script never mentions",
        error.MixedRelationObject => "this relation's object is an entity in one place and a number in another; each relation holds one kind",
        error.MissingCueArguments => "a cue handler's arguments were read outside the handler",
        error.UnreachableCueHandler => "this handler can never run: an earlier handler has the same signature and no guard",
        error.UnknownArrivalMark => "this arrival rule needs a declared mark",
        error.InvalidProgramText => "could not store this declaration's text",
        error.UnknownSocietyMember => "no society member has this name",
        error.SocietyNeedsSpatialSystem => "this society needs a spatial system",
        error.InvalidSocietyWorse => "a society need must say whether 'high' or 'low' is worse",
        error.InvalidSocietyMemberNeeds => "member needs must match the society's need declarations in order",
        error.UnknownSocietyActivity => "unknown society activity",
        error.UnknownSocietyPlace => "no society waypoint has this name",
        error.UnknownGridAttribute => "unknown grid cell attribute",
        error.UnknownGridMark => "no grid placement mark has this name",
        error.GridMarkOutsideRoom => "this mark belongs to a different room than the grid",
        error.InvalidGrid => "invalid grid dimensions, origin, or number of grids",
        error.CellOutOfBounds => "cell is outside the grid",
        error.DuplicateRoomGrid => "this room already has a grid",
        error.DuplicateGrid => "this grid name is already in use",
        error.UnknownDegradationStage => "no degradation stage has this name",
        error.InvalidConfig => "invalid degradation profile; check stage durations, vessel capacities, and relation names",
        error.DialogueTooLarge => "too many options in one choice set",
        error.TooManyCueParameters => "a cue handler can have at most three parameters",
        error.InvalidCueGuardPattern => "a cue guard needs one or two arguments per fact",
        error.TooManyCueGuardVariables => "a pattern or cue guard can bind at most eight variables",
        error.InvalidAgenda => "invalid agenda or too many agendas",
        error.UnknownHintRoom => "a need names no room, and no scene declares the prop or mark it names",
        error.InvalidGoal => "invalid goal or too many goals; check need names, prerequisites, rooms, and hint tiers",
        error.InvalidSpellbook => "invalid spellbook; check word kinds and tiers, and that each spell names a power, an element, and a form",
        error.InvalidDecision => "invalid decision; check its actor, cue, trigger lines, and scored options",
        error.InvalidRedLine => "invalid red lines; each must name an option a decision offers that character, and a decision needs one option left",
        error.InvalidArt => "invalid pixel art; the parser should have named the declaration, so please report this script",
        error.InvalidDilemma => "invalid dilemma; check its actor, cue, trigger lines, and that no decision shares its name",
        error.UnknownDilemmaAxis => "a dilemma weighs an axis that no 'axis' line declares",
        error.DilemmaCrossesRedLine => "this action is on the actor's red lines, so no tier may take it",
        error.InvalidAxis => "invalid axis; its name is already a relation, or the script declares too many axes",
        error.InvalidAxisValue => "a value on an axis needs a character and a whole number from -10 to +10",
        error.NegativeValueOutsideAxis => "only a value on a declared axis may be negative",
        error.HintTextTooLong => "a generated hint does not fit the caller's buffer",
        error.InvalidAlias => "alias phrases may use letters, digits, spaces, and apostrophes",
        error.InvalidFrame => "invalid command frame",
        error.InputTooLong => "command text is too long",
        error.TooManyWords => "command has too many words",
        // The declaration validator shares its error set with the container runtime.
        error.UnknownVessel => "vessel is not declared in this degradation profile",
        error.SameVessel => "source and target must be different vessels",
        error.SourceEmpty => "source vessel is empty",
        error.TargetNotEmpty => "target vessel is not empty",
        error.InsufficientCapacity => "target vessel cannot hold the source volume",
        error.VesselFailed => "vessel is in its terminal stage",
        error.InvalidState => "invalid vessel state",
        error.EntityLimitExceeded => "too many distinct entity names",
        error.EntityNameTooLong => "entity name exceeds 65,535 bytes",
        error.RelationLimitExceeded => "too many distinct relation names",
        error.RelationNameTooLong => "relation name exceeds 65,535 bytes",
        error.ReservedBookkeepingName => "names starting with '#' are reserved for the engine",
        error.WaypointNotFound => "waypoint could not be resolved",
        error.WaypointLimitExceeded => "too many waypoints (exceeds 65,535)",
        error.BytecodeTooLarge => "compiled bytecode exceeds the 65,535-byte format 1 limit",
        error.JumpOffsetTooLarge => "block or branch is too large for a 16-bit jump offset",
        else => "compiler could not validate this script",
    };
}

test "P40-01: every code generation error has a user-facing message" {
    const result = @typeInfo(@TypeOf(Codegen.compile)).@"fn".return_type.?;
    const errors = @typeInfo(result).error_union.error_set;
    var missing: usize = 0;
    inline for (@typeInfo(errors).error_set.error_names.?) |name| {
        const err = @field(errors, name);
        if (std.mem.eql(u8, failure_message(err), "compiler could not validate this script")) {
            std.debug.print("missing compiler diagnostic for {s}\n", .{name});
            missing += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 0), missing);
}

test {
    _ = @import("compiler/lexer.zig");
    _ = @import("compiler/parser.zig");
    _ = @import("compiler/codegen.zig");
}

test "P15-03: check_source validates valid script and returns counts" {
    const testing = std.testing;
    const script =
        \\entity Guard, Cheese
        \\relation Carries(holder, item)
        \\
        \\routine Patrol(Guard):
        \\  wait 5 ticks
    ;

    const res = check_source(testing.allocator, script);
    try testing.expect(res.is_valid);
    try testing.expect(res.diagnostic() == null);
    try testing.expectEqual(@as(usize, 2), res.entity_count);
    try testing.expectEqual(@as(usize, 1), res.routine_count);
    try testing.expect(res.bytecode_len > 0);
}

test "P15-03: check_source reports diagnostic on invalid script syntax" {
    const testing = std.testing;
    const script =
        \\routine Patrol Guard):
        \\  wait 5 ticks
    ;

    const res = check_source(testing.allocator, script);
    try testing.expect(!res.is_valid);
    try testing.expect(res.diagnostic() != null);
    try testing.expectEqual(@as(u32, 1), res.diagnostic().?.line);
    try testing.expectEqual(@as(u32, 21), res.diagnostic().?.column);
    try testing.expect(std.mem.indexOf(u8, res.diagnostic().?.message, "expected '('") != null);
}

test "P39-01: incomplete quoted names fail source validation" {
    for ([_][]const u8{ "entity \"", "entity \"Unfinished" }) |source| {
        const result = check_source(std.testing.allocator, source);
        try std.testing.expect(!result.is_valid);
        try std.testing.expect(result.diagnostic() != null);
    }
}

test "P40-01: lexical, syntax, numeric, and semantic diagnostics retain their source positions" {
    const testing = std.testing;
    const cases = [_]struct {
        source: []const u8,
        message: []const u8,
        line: u32,
        column: u32,
        hint: ?[]const u8 = null,
    }{
        .{ .source = "\"first\nsecond", .message = "unterminated string; add a closing double quote", .line = 1, .column = 1 },
        .{ .source = "routine Patrol(Guard):\n  say Guard: \"unfinished\nnext", .message = "unterminated string; add a closing double quote", .line = 2, .column = 14 },
        .{ .source = "# header\nrouitne Patrol(Guard):\n  wait 1 ticks", .message = "unexpected top-level text 'rouitne Patrol'", .line = 2, .column = 1, .hint = "routine" },
        .{ .source = "routine Patrol(Guard):\n  wiat 1 ticks", .message = "unexpected statement 'wiat 1'", .line = 2, .column = 3, .hint = "wait" },
        .{ .source = "routine Patrol(Guard):\n  walt 1 ticks", .message = "unexpected statement 'walt 1'", .line = 2, .column = 3 },
        .{ .source = "routine Patrol(Guard):\n  wait 1 tikcs", .message = "expected 'ticks', found 'tikcs'", .line = 2, .column = 10, .hint = "ticks" },
        .{ .source = "routine Patrol(Guard):\n  wait 4294967296 ticks", .message = "invalid tick count: '4294967296'", .line = 2, .column = 8 },
        .{ .source = "routine Patrol(Guard):\n  if roll 2d >= 8:", .message = "invalid dice expression: '2d'", .line = 2, .column = 11 },
        .{ .source = "play score Huming\nscore Humming: \"c\"", .message = "play of undeclared score 'Huming'", .line = 1, .column = 12, .hint = "Humming" },
        .{ .source = "play score Hump\nscore Hums: \"c\"\nscore Humpa: \"d\"", .message = "play of undeclared score 'Hump'", .line = 1, .column = 12 },
        .{ .source = "draft Signal(C, D, E, F)\nroutine Patrol(Guard):\n  weave Singal on Door", .message = "weave of undeclared draft 'Singal'", .line = 3, .column = 9, .hint = "Signal" },
        .{ .source = "marks: Gate\nwhen Guard arrives at Gtae:\n  wait 1 ticks", .message = "arrival at undeclared mark 'Gtae'", .line = 2, .column = 23, .hint = "Gate" },
        .{ .source = "scene Yard:\n  marks: Gate\ngrid Floor in Yard:\n  size 2 2\n  cell 10\n  place Gtae 0 0", .message = "no grid placement mark has this name", .line = 6, .column = 9, .hint = "Gate" },
        .{ .source = "entity Guard\nalias Guard: \"guard!\"", .message = "alias phrases may use letters, digits, spaces, and apostrophes", .line = 2, .column = 7 },
    };
    for (cases) |case| {
        const result = check_source(testing.allocator, case.source);
        errdefer std.debug.print("diagnostic source:\n{s}\n", .{case.source});
        try testing.expect(!result.is_valid);
        try testing.expectEqualStrings(case.message, result.message());
        try testing.expectEqual(case.line, result.line);
        try testing.expectEqual(case.column, result.column);
        if (case.hint) |hint| {
            try testing.expectEqualStrings(hint, result.suggestion() orelse "");
        } else try testing.expect(result.suggestion() == null);
    }
}

test "P40-01: a lexer allocation failure is reported instead of using a missing base indent" {
    const check = check_source(std.testing.failing_allocator, "entity Guard");
    try std.testing.expectEqualStrings("not enough memory to check this script", check.message());
}

test "P39-02: both compiler entry points reject oversized source" {
    const testing = std.testing;
    const source = try testing.allocator.alloc(u8, MAX_SOURCE_SIZE + 1);
    defer testing.allocator.free(source);
    @memset(source, ' ');
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    try testing.expectError(error.ScriptTooLarge, compile_source(testing.allocator, &world, null, source));
    const result = check_source(testing.allocator, source);
    try testing.expect(!result.is_valid);
    try testing.expectEqualStrings("script exceeds the 16 MiB source limit", result.message());
}

/// Fills a large stack frame with a byte pattern, so any slice still pointing at a returned
/// function's frame reads garbage. `noinline` keeps the frame real in release builds.
noinline fn scribble_stack(byte: u8) u8 {
    var junk: [8192]u8 = undefined;
    @memset(&junk, byte);
    std.mem.doNotOptimizeAway(&junk);
    return junk[junk.len / 2];
}

test "CheckResult owns its message after check_source returns" {
    const testing = std.testing;
    const res = check_source(testing.allocator, "routine Patrol Guard):\n  wait 5 ticks\n");
    // Reuse the stack the parser's `diag_buf` lived in, and the heap the arena held.
    _ = scribble_stack(0xAA);
    const noise = try testing.allocator.alloc(u8, 4096);
    defer testing.allocator.free(noise);
    @memset(noise, 0x55);

    const d = res.diagnostic().?;
    try testing.expectEqualStrings("expected '(', found ')'", d.message);
    try testing.expectEqualStrings(d.message, res.message());
    try testing.expectEqual(@as(u32, 1), d.line);
    try testing.expectEqual(@as(u32, 21), d.column);

    // A copied result carries the bytes, not a slice into the original.
    const copy = res;
    _ = scribble_stack(0x33);
    try testing.expectEqualStrings("expected '(', found ')'", copy.message());
}

test "routine names are unique across top-level, path, and during declarations" {
    const testing = std.testing;
    const top_level_duplicate =
        \\entity Guard, Hero
        \\routine Patrol(Guard):
        \\  wait 1 ticks
        \\routine Patrol(Hero):
        \\  wait 1 ticks
    ;
    const during_duplicate =
        \\during Crowd:
        \\  wait 1 ticks
        \\routine Crowd(Crowd):
        \\  wait 1 ticks
    ;
    const during_after_routine =
        \\routine Crowd(Crowd):
        \\  wait 1 ticks
        \\during Crowd:
        \\  wait 1 ticks
    ;
    const quoted_duplicate =
        \\routine "Judge Marrow"("Judge Marrow"):
        \\  wait 1 ticks
        \\routine "Judge Marrow"("Judge Marrow"):
        \\  wait 1 ticks
    ;
    const path_duplicate =
        \\entity Hero, Guard
        \\routine WitsPlan(Hero):
        \\  wait 1 ticks
        \\path Wits:
        \\  routine WitsPlan(Guard):
        \\    wait 1 ticks
    ;
    const two_path_duplicates =
        \\entity Hero, Guard
        \\path Wits:
        \\  routine Plan(Hero):
        \\    wait 1 ticks
        \\  routine Plan(Guard):
        \\    wait 1 ticks
    ;

    const cases = [_]struct { source: []const u8, line: u32, column: u32 }{
        .{ .source = top_level_duplicate, .line = 4, .column = 9 },
        .{ .source = during_duplicate, .line = 3, .column = 9 },
        .{ .source = during_after_routine, .line = 3, .column = 8 },
        .{ .source = quoted_duplicate, .line = 3, .column = 9 },
        .{ .source = path_duplicate, .line = 5, .column = 11 },
        .{ .source = two_path_duplicates, .line = 5, .column = 11 },
    };
    for (cases) |case| {
        const res = check_source(testing.allocator, case.source);
        try testing.expect(!res.is_valid);
        const d = res.diagnostic() orelse return error.TestUnexpectedResult;
        try testing.expectEqual(case.line, d.line);
        try testing.expectEqual(case.column, d.column);
        try testing.expectEqualStrings("routine name is already in use", d.message);
    }
}

const ARRIVAL_SCRIPT =
    \\scene: Stall at Dusk
    \\cast: Scout
    \\marks: Well, Gate, Barn
    \\
    \\routine Idle(Scout):
    \\  wait 500 ticks
    \\
    \\when Scout arrives at Gate:
    \\  remember ReachedGate(Scout, true)
;

test "P32-18: an arrival rule fires once per completed walk, not while resting or when placed" {
    const testing = std.testing;
    const vm_mod = @import("vm.zig");

    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try compile_source(testing.allocator, &world, &spatial, ARRIVAL_SCRIPT);
    defer compiled.deinit();

    // `at` is still an ordinary word inside names.
    const yard = world.lookup_entity("Stall at Dusk").?;
    const scout = world.lookup_entity("Scout").?;
    const well = spatial.graph.find_waypoint_in_room(yard, "Well").?;
    const gate = spatial.graph.find_waypoint_in_room(yard, "Gate").?;
    const barn = spatial.graph.find_waypoint_in_room(yard, "Barn").?;
    spatial.graph.waypoints.items[well - 1].pos = .{ .x = 0, .y = 0 };
    spatial.graph.waypoints.items[gate - 1].pos = .{ .x = 20, .y = 0 };
    spatial.graph.waypoints.items[barn - 1].pos = .{ .x = 40, .y = 0 };
    spatial.graph.edges.clearRetainingCapacity();
    try spatial.graph.connect(well, gate, null);
    try spatial.graph.connect(gate, barn, null);
    try spatial.register_entity(scout, well, 10);

    var vm = vm_mod.VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.load_compiled_rules(&compiled);
    const idle = try vm.spawn_routine(scout, compiled.routine_entries.get("Idle").?);

    const reached = world.lookup_relation("ReachedGate").?;
    const Check = struct {
        fn ticks(v: *vm_mod.VM, n: usize) !void {
            for (0..n) |_| try v.step_tick();
        }
    };

    // Standing at the Well without having walked is not an arrival anywhere.
    try Check.ticks(&vm, 2);
    try testing.expect(!world.has_fact(scout, reached, null));

    // Two ticks of walking: the rule fires on the tick the walk completes.
    _ = try spatial.walk_to(scout, gate);
    try vm.step_tick();
    try testing.expect(!world.has_fact(scout, reached, null));
    try vm.step_tick();
    try testing.expect(world.has_fact(scout, reached, null));

    // The rule interrupted the actor's routine and handed control back to it.
    const fiber = vm.fibers.items[idle - 1];
    try testing.expectEqual(@as(usize, 0), fiber.interrupt_stack.items.len);
    try testing.expectEqual(vm_mod.FiberStateTag.waiting_ticks, std.meta.activeTag(fiber.state));

    // Resting at the mark is a level, not an edge: no second firing.
    _ = world.forget(scout, reached, null);
    try Check.ticks(&vm, 3);
    try testing.expect(!world.has_fact(scout, reached, null));

    // Being placed on the mark is not an arrival.
    _ = try spatial.transition_actor(scout, yard, barn);
    _ = try spatial.transition_actor(scout, yard, gate);
    try Check.ticks(&vm, 2);
    try testing.expect(!world.has_fact(scout, reached, null));

    // A walk to the mark the actor already stands on completes at once and counts.
    _ = try spatial.walk_to(scout, gate);
    try vm.step_tick();
    try testing.expect(world.has_fact(scout, reached, null));
    _ = world.forget(scout, reached, null);

    // Arriving elsewhere does not fire, and neither does walking through the mark on the way
    // to another one.
    _ = try spatial.walk_to(scout, barn);
    try Check.ticks(&vm, 3);
    try testing.expectEqual(barn, spatial.get_current_waypoint(scout).?);
    try testing.expect(!world.has_fact(scout, reached, null));
    _ = try spatial.walk_to(scout, well);
    try Check.ticks(&vm, 5);
    try testing.expectEqual(well, spatial.get_current_waypoint(scout).?);
    try testing.expect(!world.has_fact(scout, reached, null));

    // Walking back to the mark fires again.
    _ = try spatial.walk_to(scout, gate);
    try Check.ticks(&vm, 2);
    try testing.expect(world.has_fact(scout, reached, null));
}

test "P32-18: arrival rules report a missing 'at' and an undeclared mark with a location" {
    const testing = std.testing;

    const no_at = check_source(testing.allocator,
        \\scene: Yard
        \\cast: Scout
        \\marks: Gate
        \\
        \\when Scout arrives Gate:
        \\  remember ReachedGate(Scout, true)
    );
    try testing.expect(!no_at.is_valid);
    try testing.expectEqual(@as(u32, 5), no_at.diagnostic().?.line);
    try testing.expect(std.mem.indexOf(u8, no_at.diagnostic().?.message, "expected 'at'") != null);

    const unknown = check_source(testing.allocator,
        \\scene: Yard
        \\cast: Scout
        \\marks: Gate
        \\
        \\when Scout arrives at Cellar:
        \\  remember ReachedGate(Scout, true)
    );
    try testing.expect(!unknown.is_valid);
    try testing.expectEqual(@as(u32, 5), unknown.diagnostic().?.line);
    try testing.expectEqual(@as(u32, 23), unknown.diagnostic().?.column);
    try testing.expect(std.mem.indexOf(u8, unknown.diagnostic().?.message, "undeclared mark 'Cellar'") != null);

    const valid = check_source(testing.allocator, ARRIVAL_SCRIPT);
    try testing.expect(valid.is_valid);
    try testing.expectEqual(@as(usize, 1), valid.rule_count);
}

test "P32-27: an unmatched cue has no handler; defaults and variable parameters are explicit" {
    const testing = std.testing;
    const script =
        \\scene: Yard
        \\cast: Scout, Warden
        \\props: Gate, Well, Lamp, Oil
        \\
        \\on cue Uses(Scout, Gate):
        \\  remember Opened(Gate, true)
        \\
        \\on cue LooksAt(Scout, Gate):
        \\  say Scout: "A gate."
        \\
        \\on cue LooksAt(Scout):
        \\  say Scout: "Nothing special."
        \\
        \\on cue Greets(visitor, Warden):
        \\  say Warden: "State your business."
        \\
        \\on cue Uses(Scout, Lamp, Oil):
        \\  remember Lit(Lamp, true)
        \\
        \\verb Waves(waver, target):
        \\  say Warden: "Hm."
    ;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try compile_source(testing.allocator, &world, &spatial, script);
    defer compiled.deinit();

    const gate = compiled.find_cue_handler("Uses", "Scout", "Gate", null).?;

    // No handler names the Well or the Warden, so nothing runs: not the Gate handler.
    try testing.expectEqual(@as(?usize, null), compiled.find_cue_handler("Uses", "Scout", "Well", null));
    try testing.expectEqual(@as(?usize, null), compiled.find_cue_handler("Uses", "Warden", "Gate", null));
    try testing.expectEqual(@as(?usize, null), compiled.find_cue_handler("Uses", "Scout", null, null));
    try testing.expectEqual(@as(?usize, null), compiled.find_cue_handler("Unknown", "Scout", "Gate", null));

    // An actor-only handler is the declared default for that actor, and only for that actor.
    const specific = compiled.find_cue_handler("LooksAt", "Scout", "Gate", null).?;
    const default = compiled.find_cue_handler("LooksAt", "Scout", "Well", null).?;
    try testing.expect(specific != default);
    try testing.expectEqual(default, compiled.find_cue_handler("LooksAt", "Scout", null, null).?);
    try testing.expectEqual(@as(?usize, null), compiled.find_cue_handler("LooksAt", "Warden", "Well", null));

    // A parameter declared as a variable matches any entity in that position.
    const greets = compiled.find_cue_handler("Greets", "Scout", "Warden", null).?;
    try testing.expectEqual(greets, compiled.find_cue_handler("Greets", "Warden", "Warden", null).?);
    try testing.expectEqual(@as(?usize, null), compiled.find_cue_handler("Greets", "Scout", "Gate", null));
    try testing.expect(compiled.find_cue_handler("Waves", "Scout", "Well", null) != null);

    // Two items combine in either order, and only those two.
    const lit = compiled.find_cue_handler("Uses", "Scout", "Lamp", "Oil").?;
    try testing.expect(lit != gate);
    try testing.expectEqual(lit, compiled.find_cue_handler("Uses", "Scout", "Oil", "Lamp").?);
    try testing.expectEqual(@as(?usize, null), compiled.find_cue_handler("Uses", "Scout", "Lamp", "Gate"));

    // A handler with no parameters could never be fired, so it is a compile error.
    const empty = check_source(testing.allocator, "entity Scout\non cue Rings():\n  wait 1 ticks\n");
    try testing.expect(!empty.is_valid);
    try testing.expect(std.mem.indexOf(u8, empty.diagnostic().?.message, "needs an actor") != null);
}

test "D-072: cue where guards bind cue parameters and fall through to the next handler" {
    const testing = std.testing;
    const script =
        \\entity Cat, Guard, Bard, Cheese, Fish, Lamp, Oil
        \\
        \\on cue Steal(Cat, victim) where CharmedBy(victim, _) and Carries(victim, loot):
        \\  remember Stolen(Cat)
        \\
        \\on cue Steal(thief, victim):
        \\  remember Caught(thief)
        \\
        \\on cue Fills(Cat, Lamp, fuel) where Fuel(fuel):
        \\  remember Lit(Lamp)
    ;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try compile_source(testing.allocator, &world, null, script);
    defer compiled.deinit();
    try testing.expectEqual(@as(usize, 2), compiled.cue_guards.items.len);

    const cat = world.lookup_entity("Cat").?;
    const guard = world.lookup_entity("Guard").?;
    const bard = world.lookup_entity("Bard").?;
    const cheese = world.lookup_entity("Cheese").?;
    const fish = world.lookup_entity("Fish").?;
    const carries = world.lookup_relation("Carries").?;
    const charmed = world.lookup_relation("CharmedBy").?;

    const guarded = compiled.find_cue_handler("Steal", "Cat", "Guard", null).?;
    const fallback = compiled.find_cue_handler("Steal", "Bard", "Guard", null).?;
    try testing.expect(guarded != fallback);

    // Neither fact holds: the guarded handler declines and the variable handler runs.
    try testing.expectEqual(fallback, compiled.select_cue_handler(&world, "Steal", cat, guard, null).?);

    // The facts hold for the Bard, not for the Guard the cue names: `victim` is bound to the
    // cue's target, so the guard still fails.
    _ = try world.remember(bard, charmed, guard.to_int(), 0);
    _ = try world.remember(bard, carries, cheese.to_int(), 0);
    try testing.expectEqual(fallback, compiled.select_cue_handler(&world, "Steal", cat, guard, null).?);
    try testing.expectEqual(guarded, compiled.select_cue_handler(&world, "Steal", cat, bard, null).?);

    // Both clauses must hold for the same victim.
    _ = try world.remember(guard, charmed, bard.to_int(), 0);
    try testing.expectEqual(fallback, compiled.select_cue_handler(&world, "Steal", cat, guard, null).?);
    _ = try world.remember(guard, carries, fish.to_int(), 0);
    try testing.expectEqual(guarded, compiled.select_cue_handler(&world, "Steal", cat, guard, null).?);

    // Two items combine in either order (D-013). Fired as (Oil, Lamp), the handler matches with
    // the targets swapped, so `fuel` binds to the Oil, not to the cue's second target.
    const oil = world.lookup_entity("Oil").?;
    const lamp = world.lookup_entity("Lamp").?;
    _ = try world.remember(oil, try world.intern_relation("Fuel", .set), 0, 0);
    const fills = compiled.find_cue_handler("Fills", "Cat", "Lamp", "Oil").?;
    try testing.expectEqual(fills, compiled.select_cue_handler(&world, "Fills", cat, lamp, oil).?);
    try testing.expectEqual(fills, compiled.select_cue_handler(&world, "Fills", cat, oil, lamp).?);
    try testing.expectEqual(@as(?usize, null), compiled.select_cue_handler(&world, "Fills", cat, lamp, fish));

    // A guard pattern names a state or a fact; three arguments are a compile error.
    const wide = check_source(testing.allocator,
        \\entity Cat
        \\on cue Pounce(Cat, prey) where Near(Cat, prey, 3):
        \\  wait 1 ticks
    );
    try testing.expect(!wide.is_valid);
    try testing.expectEqualStrings("a cue guard needs one or two arguments per fact", wide.message());
    try testing.expectEqual(@as(u32, 2), wide.line);
    try testing.expectEqual(@as(u32, 32), wide.column);
}

test "D-072: VM.fire_cue runs nothing when every matching handler's guard fails" {
    const testing = std.testing;
    const vm_mod = @import("vm.zig");
    const script =
        \\entity Cat, Guard, Cheese
        \\on cue Steal(Cat, victim) where Carries(victim, Cheese):
        \\  remember Stolen(Cheese)
    ;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try compile_source(testing.allocator, &world, null, script);
    defer compiled.deinit();
    var vm = vm_mod.VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    const cat = world.lookup_entity("Cat").?;
    const guard = world.lookup_entity("Guard").?;
    const cheese = world.lookup_entity("Cheese").?;

    try testing.expectEqual(@as(?vm_mod.FiberId, null), try vm.fire_cue(&compiled, "Steal", cat, guard, null));
    try testing.expectEqual(@as(usize, 0), vm.emitted_cues.items.len);

    _ = try world.remember(guard, try world.intern_relation("Carries", .set), cheese.to_int(), 0);
    try testing.expect((try vm.fire_cue(&compiled, "Steal", cat, guard, null)) != null);
    _ = try vm.step_tick();
    try testing.expect(world.has_fact(cheese, world.lookup_relation("Stolen").?, null));
}

pub const ORDERED_HANDLERS =
    \\entity Scout, Lamp, Oil, Cask
    \\
    \\on cue Uses(Scout, Lamp) where Lit(Lamp):
    \\  remember Burning(Scout)
    \\
    \\on cue Uses(Scout, Lamp) where Full(Oil):
    \\  remember Fills(Scout)
    \\
    \\on cue Uses(Scout, Lamp):
    \\  remember Dry(Scout)
    \\
    \\on cue Uses(Scout, Cask) where Full(Oil):
    \\  remember Spills(Scout)
    \\
    \\on cue Uses(Scout, Cask) where Lit(Lamp):
    \\  remember Warms(Scout)
    \\
    \\on cue Uses(Scout, thing):
    \\  remember Fiddles(Scout)
;

/// Fires `Uses(Scout, target)`, runs the handler, and reports whether it remembered `state`.
fn uses_answers(vm: anytype, compiled: *const CompiledProgram, world: *World, target: []const u8, state: []const u8) !bool {
    const scout = world.lookup_entity("Scout").?;
    _ = (try vm.fire_cue(compiled, "Uses", scout, world.lookup_entity(target).?, null)) orelse return false;
    _ = try vm.step_tick();
    const relation = world.lookup_relation(state) orelse return false;
    return world.has_fact(scout, relation, null);
}

test "P48-01: handlers that share a signature run in source order, each failed guard falling through" {
    const testing = std.testing;
    const vm_mod = @import("vm.zig");
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try compile_source(testing.allocator, &world, null, ORDERED_HANDLERS);
    defer compiled.deinit();
    var vm = vm_mod.VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    const lit = try world.intern_relation("Lit", .set);
    const full = try world.intern_relation("Full", .set);

    // No guard holds: the unguarded third handler is the default for the Lamp.
    try testing.expect(try uses_answers(&vm, &compiled, &world, "Lamp", "Dry"));
    // The second guard holds; the first still fails, so the second runs.
    _ = try world.remember(world.lookup_entity("Oil").?, full, 0, 0);
    try testing.expect(try uses_answers(&vm, &compiled, &world, "Lamp", "Fills"));
    // Both hold: the first in source order wins.
    _ = try world.remember(world.lookup_entity("Lamp").?, lit, 0, 0);
    try testing.expect(try uses_answers(&vm, &compiled, &world, "Lamp", "Burning"));

    // The Cask's two guarded handlers both hold, so the first runs; with neither, the
    // search leaves the signature for the broader `Uses(Scout, thing)` (D-072).
    try testing.expect(try uses_answers(&vm, &compiled, &world, "Cask", "Spills"));
    _ = world.forget(world.lookup_entity("Oil").?, full, null);
    try testing.expect(try uses_answers(&vm, &compiled, &world, "Cask", "Warms"));
    _ = world.forget(world.lookup_entity("Lamp").?, lit, null);
    try testing.expect(try uses_answers(&vm, &compiled, &world, "Cask", "Fiddles"));

    // The name-only lookup still names a signature's first handler.
    const first = compiled.find_cue_handler("Uses", "Scout", "Lamp", null).?;
    try testing.expect(compiled.cue_handler_chain.get(first) != null);
}

test "P48-01: a handler after an unguarded one of the same signature is refused, naming both lines" {
    const testing = std.testing;
    const cases = [_]struct { source: []const u8, line: u32, column: u32, earlier: u32 }{
        .{ .source =
        \\entity Scout, Lamp
        \\on cue Uses(Scout, Lamp):
        \\  wait 1 ticks
        \\on cue Uses(Scout, Lamp) where Lit(Lamp):
        \\  wait 1 ticks
        , .line = 4, .column = 8, .earlier = 2 },
        // Variable parameters share one signature whatever they are called.
        .{ .source =
        \\entity Scout, Lamp
        \\on cue Uses(Scout, thing) where Lit(thing):
        \\  wait 1 ticks
        \\on cue Uses(Scout, item):
        \\  wait 1 ticks
        \\on cue Uses(Scout, other):
        \\  wait 1 ticks
        , .line = 6, .column = 8, .earlier = 4 },
    };
    for (cases) |case| {
        const res = check_source(testing.allocator, case.source);
        try testing.expect(!res.is_valid);
        const d = res.diagnostic() orelse return error.TestUnexpectedResult;
        try testing.expectEqual(case.line, d.line);
        try testing.expectEqual(case.column, d.column);
        var buf: [128]u8 = undefined;
        const want = try std.fmt.bufPrint(&buf, "this handler can never run: the handler on line {d} has the same signature and no guard", .{case.earlier});
        try testing.expectEqualStrings(want, d.message);
    }
}

test "P48-02: a cue handler body reads the entities its cue was fired with" {
    const testing = std.testing;
    const bound_bodies =
        \\entity Cat, Guard, Bard, Cheese, Lamp, Oil, Hero
        \\
        \\on cue Steal(Cat, victim) where Carries(victim, loot):
        \\  remember Robbed(victim)
        \\  remember Holds(Cat, loot)
        \\  forget Carries(victim, loot)
        \\
        \\on cue Greets(Hero, other):
        \\  remember Met(Hero, other)
        \\  if Charmed(other):
        \\    remember Smitten(other)
        \\  say other: "Well met."
        \\
        \\on cue Fills(Cat, Lamp, fuel):
        \\  remember Burns(Lamp, fuel)
        \\
        \\on cue Waits(Hero, thing):
        \\  wait until thing is lit
        \\  remember Saw(Hero, thing)
    ;
    const vm_mod = @import("vm.zig");
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try compile_source(testing.allocator, &world, null, bound_bodies);
    defer compiled.deinit();
    var vm = vm_mod.VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    const e = struct {
        fn of(w: *World, name: []const u8) world_mod.EntityId {
            return w.lookup_entity(name).?;
        }
    }.of;
    const carries = world.lookup_relation("Carries").?;

    // `victim` is the cue's target and `loot` what the guard matched; neither is interned as
    // a name of its own.
    _ = try world.remember(e(&world, "Guard"), carries, e(&world, "Cheese").to_int(), 0);
    _ = (try vm.fire_cue(&compiled, "Steal", e(&world, "Cat"), e(&world, "Guard"), null)).?;
    _ = try vm.step_tick();
    try testing.expect(world.has_fact(e(&world, "Guard"), world.lookup_relation("Robbed").?, null));
    try testing.expect(world.has_fact(e(&world, "Cat"), world.lookup_relation("Holds").?, e(&world, "Cheese").to_int()));
    try testing.expect(!world.has_fact(e(&world, "Guard"), carries, e(&world, "Cheese").to_int()));
    try testing.expect(world.lookup_entity("victim") == null);
    try testing.expect(world.lookup_entity("loot") == null);

    // An unguarded handler binds too, in a condition and as a speaker.
    _ = try world.remember(e(&world, "Bard"), try world.intern_relation("Charmed", .set), 0, 0);
    _ = (try vm.fire_cue(&compiled, "Greets", e(&world, "Hero"), e(&world, "Bard"), null)).?;
    _ = try vm.step_tick();
    try testing.expect(world.has_fact(e(&world, "Hero"), world.lookup_relation("Met").?, e(&world, "Bard").to_int()));
    try testing.expect(world.has_fact(e(&world, "Bard"), world.lookup_relation("Smitten").?, null));
    var said = false;
    for (vm.emitted_cues.items) |cue| {
        if (cue.cue_id == 2 and cue.args[0] == e(&world, "Bard").to_int()) said = true;
    }
    try testing.expect(said);

    // Two items combine in either order (D-013): fired as (Oil, Lamp), `fuel` is still the Oil.
    _ = (try vm.fire_cue(&compiled, "Fills", e(&world, "Cat"), e(&world, "Oil"), e(&world, "Lamp"))).?;
    _ = try vm.step_tick();
    try testing.expect(world.has_fact(e(&world, "Lamp"), world.lookup_relation("Burns").?, e(&world, "Oil").to_int()));

    // A `wait until` reads the binding on each tick it is checked.
    _ = (try vm.fire_cue(&compiled, "Waits", e(&world, "Hero"), e(&world, "Lamp"), null)).?;
    _ = try vm.step_tick();
    _ = try vm.step_tick();
    try testing.expect(world.lookup_relation("Saw") == null or !world.has_fact(e(&world, "Hero"), world.lookup_relation("Saw").?, null));
    _ = try world.remember(e(&world, "Lamp"), world.lookup_relation("Lit").?, 0, 0);
    _ = try vm.step_tick();
    _ = try vm.step_tick();
    try testing.expect(world.has_fact(e(&world, "Hero"), world.lookup_relation("Saw").?, e(&world, "Lamp").to_int()));
}

test "P48-02: a state word and its capitalised relation are one fact" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try compile_source(testing.allocator, &world, null,
        \\entity Lamp
        \\Lamp is lit
    );
    defer compiled.deinit();
    try testing.expect(world.lookup_relation("lit") == null);
    try testing.expect(world.lookup_relation("Lit") != null);
}

test "P48-02: lowercase names of things and unbound variables are refused where they are written" {
    const testing = std.testing;
    const cases = [_]struct { source: []const u8, line: u32, column: u32, message: []const u8, help: ?[]const u8 }{
        .{ .source = "entity Hero\nroutine Idle(Hero):\n  remember Holds(Hero, sword)\n", .line = 3, .column = 24, .message = "a lowercase name is a variable, and nothing binds this one here; names of things start with a capital letter", .help = "Sword" },
        .{ .source = "entity Hero, hero\n", .line = 1, .column = 14, .message = "names of things start with a capital letter", .help = "Hero" },
        .{ .source = "relation lit(thing)\n", .line = 1, .column = 10, .message = "names of things start with a capital letter", .help = "Lit" },
        .{ .source = "entity Hero, Sword\nwhen Holds(who, Sword):\n  remember Armed(who)\n", .line = 3, .column = 18, .message = "a when rule's variables cannot be used in its body yet; name the entity", .help = null },
        .{ .source = "entity Hero\nscene: Yard\nmarks: Gate\non cue Goes(Hero, place):\n  transition to scene place\n", .line = 5, .column = 23, .message = "a cue parameter cannot be used in this statement", .help = null },
    };
    for (cases) |case| {
        const res = check_source(testing.allocator, case.source);
        try testing.expect(!res.is_valid);
        const d = res.diagnostic() orelse return error.TestUnexpectedResult;
        try testing.expectEqualStrings(case.message, d.message);
        try testing.expectEqual(case.line, d.line);
        try testing.expectEqual(case.column, d.column);
        if (case.help) |help| try testing.expectEqualStrings(help, res.suggestion() orelse "") else try testing.expect(res.suggestion() == null);
    }
}

test "P48-08: a script declares its save version, and its build has a fingerprint" {
    const testing = std.testing;
    const base =
        \\entity Hero
        \\routine Idle(Hero):
        \\  wait 1 ticks
        \\
    ;
    const Build = struct {
        fn identity(source: []const u8) !@import("save.zig").ProgramIdentity {
            var world = try World.init(testing.allocator, 1024 * 1024);
            defer world.deinit();
            var compiled = try compile_source(testing.allocator, &world, null, source);
            defer compiled.deinit();
            return compiled.identity();
        }
    };
    const plain = try Build.identity(base);
    try testing.expectEqual(@as(u32, 1), plain.save_version);
    try testing.expect(plain.known());

    // A comment changes nothing the program does, so the build is the same.
    try testing.expectEqual(plain.fingerprint, (try Build.identity("# a note\n" ++ base)).fingerprint);
    // Waiting longer is a different build; declaring a save version changes only the version.
    try testing.expect(plain.fingerprint != (try Build.identity("entity Hero\nroutine Idle(Hero):\n  wait 2 ticks\n")).fingerprint);
    const declared = try Build.identity("save version 3\n" ++ base);
    try testing.expectEqual(@as(u32, 3), declared.save_version);
    try testing.expectEqual(plain.fingerprint, declared.fingerprint);

    const cases = [_]struct { source: []const u8, line: u32, column: u32 }{
        .{ .source = "save version 2\nsave version 3\n", .line = 2, .column = 1 },
        .{ .source = "save version 0\n", .line = 1, .column = 14 },
        .{ .source = "save version two\n", .line = 1, .column = 14 },
    };
    for (cases) |case| {
        const res = check_source(testing.allocator, case.source);
        try testing.expect(!res.is_valid);
        const d = res.diagnostic() orelse return error.TestUnexpectedResult;
        try testing.expectEqual(case.line, d.line);
        try testing.expectEqual(case.column, d.column);
    }
    // `save` and `version` stay usable as names.
    try testing.expect(check_source(testing.allocator, "entity Save, Version\n").is_valid);
}

test "P48-08: a relation's object kind is inferred, and using it both ways is refused" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try compile_source(testing.allocator, &world, null,
        \\axis Mercy between Cruelty and Weakness
        \\entity Hero, Coin, Lamp
        \\remember Holds(Hero, Coin)
        \\remember Gold(Hero, 3)
        \\remember Mercy(Hero, 2)
        \\remember Lit(Lamp)
        \\on cue Gives(Hero, thing):
        \\  remember Owes(Hero, thing)
    );
    defer compiled.deinit();
    const kind = struct {
        fn of(w: *const World, name: []const u8) world_mod.ObjectKind {
            return w.object_kind(w.lookup_relation(name).?);
        }
    }.of;
    try testing.expectEqual(world_mod.ObjectKind.entity, kind(&world, "Holds"));
    try testing.expectEqual(world_mod.ObjectKind.number, kind(&world, "Gold"));
    try testing.expectEqual(world_mod.ObjectKind.number, kind(&world, "Mercy"));
    try testing.expectEqual(world_mod.ObjectKind.entity, kind(&world, "Owes"));
    try testing.expectEqual(world_mod.ObjectKind.unknown, kind(&world, "Lit"));

    const mixed = check_source(testing.allocator,
        \\entity Hero, Coin
        \\remember Holds(Hero, Coin)
        \\routine Idle(Hero):
        \\  if Holds(Hero, 2):
        \\    wait 1 ticks
    );
    try testing.expect(!mixed.is_valid);
    try testing.expectEqualStrings("MixedRelationObject", mixed.kind());
    try testing.expectEqual(@as(u32, 4), mixed.diagnostic().?.line);
    try testing.expectEqual(@as(u32, 18), mixed.diagnostic().?.column);
}

test "P48-09: name and phrase lines set what players read, and their mistakes are named" {
    const testing = std.testing;
    const hint_mod = @import("hint.zig");
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try compile_source(testing.allocator, &world, null,
        \\scene: PlateArchive
        \\cast: Ines
        \\props: ExposureSlip
        \\marks: Table
        \\name ExposureSlip: "the slip from the darkroom"
        \\name PlateArchive: "Archive des plaques"
        \\phrase HintRoom: "Cherchez dans {room}."
        \\phrase HintThing: "Il vous faut {thing}."
        \\phrase HintFact: "{subject} doit {relation} {object}."
        \\phrase HintState: "{subject} doit {relation}."
        \\relation Carries(holder, item)
        \\goal RecoverTheSlip:
        \\  need Slip:
        \\    met Carries(Ines, ExposureSlip)
        \\    room PlateArchive
        \\goal Rest:
        \\  need Sit:
        \\    met Seated(Ines)
        \\    room PlateArchive
        \\routine Idle(Ines):
        \\  wait 1 ticks
    );
    defer compiled.deinit();
    const ines = world.lookup_entity("Ines").?;
    try testing.expectEqualStrings("the slip from the darkroom", world.display_text(world.lookup_entity("ExposureSlip").?).?);

    // A replaced table changes every generated hint (P48-09 acceptance).
    var buf: [128]u8 = undefined;
    try testing.expectEqualStrings("Cherchez dans Archive des plaques.", (try hint_mod.query(compiled.goals.items[0..1], &world, ines, .room, &buf)).?.text);
    try testing.expectEqualStrings("Il vous faut the slip from the darkroom.", (try hint_mod.query(compiled.goals.items[0..1], &world, ines, .thing, &buf)).?.text);
    try testing.expectEqualStrings("Ines doit Carries the slip from the darkroom.", (try hint_mod.query(compiled.goals.items[0..1], &world, ines, .relation, &buf)).?.text);
    try testing.expectEqualStrings("Ines doit Seated.", (try hint_mod.query(compiled.goals.items[1..2], &world, ines, .relation, &buf)).?.text);

    const cases = [_]struct { source: []const u8, kind: []const u8, line: u32, column: u32, help: ?[]const u8 = null }{
        .{ .source = "phrase HintRom: \"x\"\n", .kind = "UnexpectedToken", .line = 1, .column = 8, .help = "HintRoom" },
        .{ .source = "phrase HintRoom: \"Look for {thing}.\"\n", .kind = "UnexpectedToken", .line = 1, .column = 18 },
        .{ .source = "phrase NotHere: \"a\"\nphrase NotHere: \"b\"\n", .kind = "UnexpectedToken", .line = 2, .column = 8 },
        .{ .source = "entity Hero\nname Hero: \"A\"\nname Hero: \"B\"\n", .kind = "UnexpectedToken", .line = 3, .column = 6 },
        .{ .source = "entity Hero\nname Heor: \"A\"\n", .kind = "NameForUnknownThing", .line = 2, .column = 6 },
    };
    for (cases) |case| {
        const res = check_source(testing.allocator, case.source);
        try testing.expect(!res.is_valid);
        try testing.expectEqualStrings(case.kind, res.kind());
        try testing.expectEqual(case.line, res.diagnostic().?.line);
        try testing.expectEqual(case.column, res.diagnostic().?.column);
        if (case.help) |help| try testing.expectEqualStrings(help, res.suggestion() orelse "");
    }
    // `name` and `phrase` stay usable as names.
    try testing.expect(check_source(testing.allocator, "entity Name, Phrase\n").is_valid);
}

test "P48-10: a script declaring a relation a later release adopted keeps it, with a warning" {
    const testing = std.testing;
    const later = [_]reserved_mod.AuthorRelation{.{ .name = "Hears", .since = .{ .major = 1, .minor = 1 } }};
    const source =
        \\entity Hero, Bell
        \\relation Hears(who, sound)
        \\remember Hears(Hero, Bell)
    ;
    const res = check_source_against(testing.allocator, source, null, &later);
    try testing.expect(res.is_valid);
    try testing.expectEqual(@as(usize, 1), res.warning_count);
    try testing.expectEqual(@as(u32, 2), res.warnings[0].line);
    try testing.expectEqual(@as(u32, 10), res.warnings[0].column);
    try testing.expectEqualStrings("BeSpoke 1.1 also uses 'Hears'; this game keeps its own, and the engine's 'Hears' is off for it", res.warnings[0].message());
    // Against the real table nothing is newer than 1.0, so the same script is quiet.
    try testing.expectEqual(@as(usize, 0), check_source(testing.allocator, source).warning_count);

    // The claim is recorded, so a later feature can ask before it uses the name.
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = @import("spatial.zig").SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var lex = Lexer.init(testing.allocator, source);
    defer lex.deinit();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var parse = try Parser.init(arena.allocator(), &lex);
    const ast = try parse.parse_program();
    var cg = Codegen.init(testing.allocator, &world, &spatial);
    cg.engine_relations = &later;
    var compiled = try cg.compile(&ast);
    defer compiled.deinit();
    defer {
        for (cg.warnings.items) |w| testing.allocator.free(w.message);
        cg.warnings.deinit(testing.allocator);
    }
    try testing.expect(!reserved_mod.engine_may_use(&world, "Hears"));
    try testing.expect(reserved_mod.engine_may_use(&world, "Knows"));
}

test "P48-10: engine bookkeeping cannot be named in a script, and a plain name is the script's own" {
    const testing = std.testing;
    try testing.expect(!check_source(testing.allocator, "entity Hero\nremember #DialogueOpen(Hero)\n").is_valid);
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try compile_source(testing.allocator, &world, null, "entity Hero\nremember DialogueOpen(Hero)\n");
    defer compiled.deinit();
    try testing.expect(world.lookup_relation("DialogueOpen") != null);
    try testing.expect(world.lookup_relation("#DialogueOpen") == null);
}

test "P48-11: looks and parts compile, and their mistakes are named" {
    const testing = std.testing;
    const base =
        \\scene: Shop
        \\cast: Clerk
        \\props: Bell
        \\marks: Till
        \\palette:
        \\  "." transparent
        \\  "r" 200 40 40
        \\image BellSheet frames 2x2:
        \\  "r.r."
        \\  "rr.r"
        \\
    ;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try compile_source(testing.allocator, &world, null, base ++
        \\look BellQuiet: BellSheet
        \\  idle: 0
        \\look BellRinging: BellSheet
        \\  idle: 0 for 4, 1 for 4
        \\sprite Bell: BellQuiet
        \\sprite Clapper: BellSheet
        \\part Clapper of Bell at 0 -2
        \\remember Looks(Bell, BellRinging)
    );
    defer compiled.deinit();
    const a = compiled.art;
    try testing.expectEqual(@as(usize, 2), a.looks.len);
    try testing.expectEqual(@as(u16, 1), a.look_named("BellRinging").?.frame_at(.idle, 5));
    try testing.expectEqual(@as(i16, -2), a.part_for(world.lookup_entity("Clapper").?).?.dy);
    try testing.expectEqual(world.lookup_entity("Bell").?, a.part_for(world.lookup_entity("Clapper").?).?.host);
    try testing.expectEqual(world_mod.RelationType.property, world.get_relation_meta(world.lookup_relation("Looks").?).?.rel_type);

    const cases = [_]struct { tail: []const u8, kind: []const u8, line: u32, column: u32, help: ?[]const u8 = null }{
        .{ .tail = "look BellQuiet: BellSheet\nremember Looks(Bell, BellQiet)\n", .kind = "UnknownLook", .line = 12, .column = 22, .help = "BellQuiet" },
        .{ .tail = "look BellSheet: BellSheet\n", .kind = "UnexpectedToken", .line = 11, .column = 6 },
        .{ .tail = "look BellQuiet: BellSheet\nsprite Bell: BellQuiet\n  idle: 1\n", .kind = "UnexpectedToken", .line = 13, .column = 9 },
        .{ .tail = "part Clapper of Nobody at 0 0\n", .kind = "UnexpectedToken", .line = 11, .column = 6 },
        .{ .tail = "part Bell of Bell at 0 0\n", .kind = "UnexpectedToken", .line = 11, .column = 6 },
    };
    for (cases) |case| {
        var buf: [512]u8 = undefined;
        const source = try std.fmt.bufPrint(&buf, "{s}{s}", .{ base, case.tail });
        const res = check_source(testing.allocator, source);
        try testing.expect(!res.is_valid);
        try testing.expectEqualStrings(case.kind, res.kind());
        try testing.expectEqual(case.line, res.diagnostic().?.line);
        try testing.expectEqual(case.column, res.diagnostic().?.column);
        if (case.help) |help| try testing.expectEqualStrings(help, res.suggestion() orelse "");
    }
}

const ART_BASE =
    \\scene: Shop
    \\cast: Clerk
    \\props: Bell
    \\marks: Till
    \\
    \\palette:
    \\  "." transparent
    \\  "r" 200 40 40
    \\  "y" 240 220 60
    \\
    \\image BellSheet frames 2x2:
    \\  "r.yy"
    \\  "rr.y"
    \\
;

test "P46-03: art declarations compile into the program with their bindings" {
    const testing = std.testing;
    const script = ART_BASE ++
        \\sprite Bell: BellSheet
        \\  idle: 0 for 30, 1
        \\sprite Clerk: BellSheet
        \\  walk left: 1 for 4
        \\image sprite:
        \\  "ry"
    ;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try compile_source(testing.allocator, &world, null, script);
    defer compiled.deinit();
    const art = compiled.art;
    const sheet = art.find("BellSheet").?;
    try testing.expectEqual(@as(u32, 2), sheet.frame_count());
    // Codes become the palette's colours; the transparent code is no colour at all (D-166).
    const palette = [_]image_mod.Colour{ .{ .r = 0, .g = 0, .b = 0 }, .{ .r = 200, .g = 40, .b = 40 }, .{ .r = 240, .g = 220, .b = 60 } };
    try testing.expectEqualSlices(image_mod.Pixel, &comptime image_mod.from_indices(&palette, &.{ 1, 0, 2, 2, 1, 1, 0, 2 }), sheet.pixels);
    // An image may be named with an art word: the words are matched by position, not reserved.
    try testing.expectEqual(@as(u16, 2), art.find("sprite").?.width);
    const bell = art.sprite_for(world.lookup_entity("Bell").?).?;
    try testing.expectEqual(@as(u16, 0), bell.frame_at(.idle, 29));
    // A step with no `for` shows six display frames (D-152's ten a second).
    try testing.expectEqual(@as(u16, 1), bell.frame_at(.idle, 35));
    try testing.expectEqual(@as(u16, 0), bell.frame_at(.idle, 36));
    const clerk = art.sprite_for(world.lookup_entity("Clerk").?).?;
    try testing.expectEqual(@as(u16, 1), clerk.frame_at(.walk_left, 0));
    try testing.expectEqual(@as(u16, 0), clerk.frame_at(.walk_right, 0));

    // The art words stay usable where lowercase words go (D-161): as variables and as state
    // words.
    const names = check_source(testing.allocator,
        \\relation Lit(thing)
        \\entity Lamp, Hero
        \\on cue Shows(Hero, image):
        \\  remember Lit(image)
        \\on cue Hides(Hero, sprite) where Lit(sprite):
        \\  forget Lit(sprite)
        \\Lamp is palette
    );
    try testing.expect(names.is_valid);
}

test "P46-03: art mistakes are reported on their own line" {
    const testing = std.testing;
    const Case = struct { source: []const u8, message: []const u8, line: u32, hint: ?[]const u8 = null };
    const cases = [_]Case{
        .{ .source = ART_BASE ++ "sprite Bell: BelSheet", .message = "sprite 'Bell' names image 'BelSheet', which is not declared", .line = 14, .hint = "BellSheet" },
        .{ .source = ART_BASE ++ "sprite Bell: BellSheet\n  idle: 0, 2", .message = "image 'BellSheet' has 2 frame(s), numbered from 0; frame 2 does not exist", .line = 15 },
        .{ .source = ART_BASE ++ "sprite Bel: BellSheet", .message = "sprite 'Bel' is for a person or prop no scene declares in 'cast:' or 'props:', and no 'part' line names it", .line = 14, .hint = "Bell" },
        .{ .source = ART_BASE ++ "sprite Bell: BellSheet\n  idle: 0 for 0", .message = "sprite 'Bell' shows a frame for 0 display frames; use 1 to 600", .line = 15 },
        .{ .source = ART_BASE ++ "sprite Bell: BellSheet\n  walk sideways: 0", .message = "sprite 'Bell' walks up, down, left, or right, not 'sideways'", .line = 15 },
        .{ .source = ART_BASE ++ "sprite Bell: BellSheet\n  idle: 0\n  idle: 1", .message = "sprite 'Bell' declares the 'idle' animation twice", .line = 16 },
        .{ .source = ART_BASE ++ "image Odd:\n  \"rq\"", .message = "image 'Odd' row 1 uses code \"q\", which the palette does not declare", .line = 15 },
        .{ .source = ART_BASE ++ "image Odd:\n  \"ry\"\n  \"r\"", .message = "image 'Odd' row 2 is 1 characters wide; its first row is 2", .line = 16 },
        .{ .source = ART_BASE ++ "image Odd frames 3x2:\n  \"ryry\"\n  \"ryry\"", .message = "image 'Odd' is 4x2, which frames of 3x2 do not tile", .line = 14 },
        .{ .source = ART_BASE ++ "image BellSheet:\n  \"r\"", .message = "image 'BellSheet' is declared twice", .line = 14 },
        .{ .source = "scene: Shop\nbackdrop: Wall\n" ++ ART_BASE[12..] ++ "image Wall:\n  \"r\"", .message = "backdrop 'Wall' of scene 'Shop' is 1x1; a backdrop is one 320x180 frame (D-152)", .line = 2 },
        .{ .source = "scene: Shop\nbackdrop: Wal\nimage Wall:\n  \"r\"\npalette:\n  \".\" transparent\n  \"r\" 1 2 3", .message = "scene 'Shop' names image 'Wal', which is not declared", .line = 2, .hint = "Wall" },
        .{ .source = "backdrop: Wall", .message = "a backdrop belongs to a scene; put it under a 'scene:' line", .line = 1 },
        .{ .source = "image Lone:\n  \"r\"", .message = "image 'Lone' needs a 'palette:' declaration for its codes", .line = 1 },
        .{ .source = "palette:\n  \"r\" 1 2 3", .message = "the palette's first line is its transparent code, such as '\".\" transparent'; index 0 is never drawn", .line = 2 },
        .{ .source = "palette:\n  \".\" transparent\n  \"rr\" 1 2 3", .message = "palette code \"rr\" is 2 characters wide, but the first code is 1; every code is the same width", .line = 3 },
        .{ .source = "palette:\n  \".\" transparent\n  \"r\" 1 2 300", .message = "palette code \"r\" has a colour value of 300; each of red, green, and blue is 0 to 255", .line = 3 },
        .{ .source = "palette:\n  \".\" transparent\npalette:\n  \".\" transparent", .message = "the palette is declared twice; a game has one palette (D-152)", .line = 3 },
        .{ .source = ART_BASE ++ "area Bel: 0 0 4 4", .message = "area 'Bel' is for a prop no scene declares in 'props:'", .line = 14, .hint = "Bell" },
        .{ .source = ART_BASE ++ "area Bell: 300 0 30 4", .message = "area 'Bell' is 30x4 at (300, 0); an area is at least 1x1 and inside the 320x180 art", .line = 14 },
    };
    for (cases) |case| {
        const result = check_source(testing.allocator, case.source);
        errdefer std.debug.print("art diagnostic source:\n{s}\ngot: {d}: {s}\n", .{ case.source, result.line, result.message() });
        try testing.expect(!result.is_valid);
        try testing.expectEqualStrings(case.message, result.message());
        try testing.expectEqual(case.line, result.line);
        if (case.hint) |hint| try testing.expectEqualStrings(hint, result.suggestion() orelse "");
    }
}

test "P48-13: limits raise a ceiling up to its cap, hints may have six tiers, and tuning lines compile" {
    const testing = std.testing;
    const goal =
        \\entity Ines, Slip, Archive
        \\relation Carries(holder, item)
        \\goal Recover:
        \\  need Take:
        \\    met Carries(Ines, Slip)
        \\    room Archive
        \\    hint 4 "Look under the press."
        \\    hint 5 "The drawer sticks."
        \\    hint 6 "Pull hard."
        \\
    ;
    // A limit may follow what it limits.
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try compile_source(testing.allocator, &world, null, goal ++ "limit hints 6\n");
    defer compiled.deinit();
    const need = compiled.goals.items[0].goal.needs[0];
    try testing.expectEqual(@as(usize, 6), @import("hint.zig").tier_count(need));

    const cases = [_]struct { source: []const u8, line: u32, column: u32, message: []const u8 }{
        // Without the limit, the first tier past 3 is named, with the limit the script needs.
        .{ .source = goal, .line = 7, .column = 10, .message = "4 hint tiers in one need is past the limit of 3; add 'limit hints 6' to raise it, up to 24 (D-183)" },
        .{ .source = "limit hints 25\n" ++ goal, .line = 1, .column = 13, .message = "'limit hints' is 25; it may raise the default of 3 hint tiers in one need up to 24" },
        .{ .source = "limit hints 2\n" ++ goal, .line = 1, .column = 13, .message = "'limit hints' is 2; it may raise the default of 3 hint tiers in one need up to 24" },
        .{ .source = "limit leans 4\n", .line = 1, .column = 7, .message = "there is no limit on 'leans'; a script may raise goals, needs, decisions, options, dilemmas, axes, spells, words, or hints" },
        .{ .source = "limit hints 6\nlimit hints 7\n", .line = 2, .column = 1, .message = "'limit hints' is declared twice" },
    };
    for (cases) |case| {
        const res = check_source(testing.allocator, case.source);
        try testing.expect(!res.is_valid);
        try testing.expectEqualStrings(case.message, res.message());
        try testing.expectEqual(case.line, res.diagnostic().?.line);
        try testing.expectEqual(case.column, res.diagnostic().?.column);
    }

    // A count ceiling: the 65th axis is past the default of 64 until `limit axes 65`.
    var axes = std.array_list.Managed(u8).init(testing.allocator);
    defer axes.deinit();
    for (0..65) |i| try axes.print("axis Virtue{d} between Fault{d} and Excess{d}\n", .{ i, i, i });
    const over = check_source(testing.allocator, axes.items);
    try testing.expectEqualStrings("65 axes is past the limit of 64; add 'limit axes 65' to raise it, up to 512 (D-183)", over.message());
    try testing.expectEqual(@as(u32, 65), over.diagnostic().?.line);
    try axes.appendSlice("limit axes 65\n");
    try testing.expect(check_source(testing.allocator, axes.items).is_valid);

    // An axis's drift step and a dilemma's tiers and drift cap reach the program.
    const tuned =
        \\entity Valerius, Thief
        \\relation Accused(who)
        \\axis Justice between Cruelty and Leniency
        \\axis Mercy between Vengeance and "Condoning Harm"
        \\  drift step 4
        \\dilemma StolenBread:
        \\  actor Valerius
        \\  fires Judged
        \\  requires Accused(Thief)
        \\  weighs Justice against Mercy
        \\  tiers 8 and 4
        \\  drift cap 3
        \\  drifts 2 toward Mercy when Accused(Thief)
        \\  strong Justice: "The law is the law." -> Hang
        \\  moderate Justice: "A night in the cells." -> Jail
        \\  neutral: "Show me why." -> Wait
        \\  moderate Mercy: "Pay for the loaf." -> Fine
        \\  strong Mercy: "Go." -> Pardon
        \\
    ;
    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();
    var program = try compile_source(testing.allocator, &world2, null, tuned);
    defer program.deinit();
    try testing.expectEqual(@as(u8, 5), program.axes.items[0].drift_step);
    try testing.expectEqual(@as(u8, 4), program.axes.items[1].drift_step);
    const d = program.dilemmas.items[0].dilemma;
    try testing.expectEqual(@as(u8, 8), d.strong_at);
    try testing.expectEqual(@as(u8, 4), d.moderate_at);
    try testing.expectEqual(@as(u8, 3), d.drift_cap);
    try testing.expectEqual(@as(u8, 4), d.drifts[0].step);
}

test "D-199: a room block places marks and props in art pixels, and its walkways replace the chain" {
    const testing = std.testing;
    const src =
        \\scene Yard:
        \\  cast: Hero
        \\  props: Bucket
        \\  marks: Gate, Well, Shed
        \\
        \\scene Hall:
        \\  marks: Door, Hearth
        \\
        \\room Yard:
        \\  mark Gate at 40 120
        \\  mark Well at 200 132
        \\  mark Shed at 120 60
        \\  prop Bucket at 214 128
        \\  walkway Gate to Well
        \\  exit Well to Hall at Door
        \\
        \\room Hall:
        \\  mark Door at 30 140
        \\  mark Hearth at 250 140
        \\
        \\routine Stroll(Hero):
        \\  walk Hero to Well
        \\
    ;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try compile_source(testing.allocator, &world, &spatial, src);
    defer compiled.deinit();
    const yard = world.lookup_entity("Yard").?;
    const hall = world.lookup_entity("Hall").?;
    const gate = spatial.graph.find_waypoint_in_room(yard, "Gate").?;
    const well = spatial.graph.find_waypoint_in_room(yard, "Well").?;
    const shed = spatial.graph.find_waypoint_in_room(yard, "Shed").?;
    try testing.expectEqual(spatial_mod.art_to_world(40, 120), spatial.graph.get_waypoint(gate).?.pos);
    try testing.expectEqual(spatial_mod.art_to_world(120, 60), spatial.graph.get_waypoint(shed).?.pos);
    // Only the declared walkway joins the yard's marks: Gate and Well, both ways; Shed stands
    // apart. The hall declares none, so its marks keep the default chain.
    var joined: [3]bool = @splat(false);
    for (spatial.graph.edges.items) |e| {
        if (spatial.graph.get_waypoint(e.from).?.room != yard) continue;
        if (e.from == gate and e.to == well) joined[0] = true;
        if (e.from == well and e.to == gate) joined[1] = true;
        if (e.from == shed or e.to == shed) joined[2] = true;
    }
    try testing.expect(joined[0] and joined[1] and !joined[2]);
    const door = spatial.graph.find_waypoint_in_room(hall, "Door").?;
    const hearth = spatial.graph.find_waypoint_in_room(hall, "Hearth").?;
    var chained = false;
    for (spatial.graph.edges.items) |e| if (e.from == door and e.to == hearth) {
        chained = true;
    };
    try testing.expect(chained);
    // The prop's hotspot stands where the block puts it, and the exit is the program's.
    const bucket = world.lookup_entity("Bucket").?;
    var found = false;
    for (spatial.hotspots.items) |hs| if (hs.entity == bucket) {
        try testing.expectEqual(spatial_mod.art_to_world(214, 128), hs.pos);
        found = true;
    };
    try testing.expect(found);
    try testing.expectEqual(@as(usize, 1), compiled.exits.items.len);
    try testing.expectEqualStrings("Well", compiled.exits.items[0].mark);
    try testing.expectEqualStrings("Hall", compiled.exits.items[0].to_scene);
    try testing.expectEqualStrings("Door", compiled.exits.items[0].to_mark);
}

test "D-199: room block refusals name the line and the missing thing" {
    const testing = std.testing;
    const head = "scene Yard:\n  marks: Gate, Well\n\nscene Hall:\n  marks: Door\n\n";
    const Case = struct { body: []const u8, line: u32, says: []const u8 };
    const cases = [_]Case{
        .{ .body = "room Yard:\n  mark Gate at 1 1\n", .line = 7, .says = "does not place mark 'Well'" },
        .{ .body = "room Yard:\n  mark Gate at 1 1\n  mark Well at 2 2\n  mark Pond at 3 3\n", .line = 10, .says = "does not list" },
        .{ .body = "room Yard:\n  mark Gate at 320 1\n  mark Well at 2 2\n", .line = 8, .says = "outside the 320x180 art" },
        .{ .body = "room Yard:\n  mark Gate at 1 1\n  mark Well at 2 2\n  exit Gate to Cellar at Door\n", .line = 10, .says = "not a scene" },
        .{ .body = "room Yard:\n  mark Gate at 1 1\n  mark Well at 2 2\n  exit Gate to Hall at Hearth\n", .line = 10, .says = "not a mark of scene 'Hall'" },
        .{ .body = "room Yard:\n  mark Gate at 1 1\n  mark Well at 2 2\n  walkway Gate to Door\n", .line = 10, .says = "not a mark of scene 'Yard'" },
        .{ .body = "room Cellar:\n  mark Gate at 1 1\n", .line = 7, .says = "names no scene" },
        .{ .body = "room Hall:\n  mark Door at 1 1\n\nroom Hall:\n  mark Door at 2 2\n", .line = 10, .says = "two room blocks" },
        .{ .body = "room Yard:\n  mark Gate 1 1\n  mark Well at 2 2\n", .line = 8, .says = "expects 'at <x> <y>'" },
    };
    for (cases) |c| {
        var buf: [512]u8 = undefined;
        const src = try std.fmt.bufPrint(&buf, "{s}{s}", .{ head, c.body });
        const res = check_source(testing.allocator, src);
        if (res.is_valid or res.line != c.line or std.mem.indexOf(u8, res.message(), c.says) == null) {
            std.debug.print("case {s}: valid={} line={d} message={s}\n", .{ c.body, res.is_valid, res.line, res.message() });
            return error.TestUnexpectedResult;
        }
    }
}

test "D-204: dialogue_sources gives each conversation's tree with guards, lines, and never-holding marks" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const src =
        \\scene Quay:
        \\  cast: Hero, Guide
        \\
        \\relation Carries(who, thing)
        \\relation Paid(who)
        \\
        \\on cue TalksTo(Hero, Guide):
        \\  say Guide: "Well?"
        \\  choice "Pay the toll." if not Paid(Hero):
        \\    remember Paid(Hero)
        \\    say Guide: "Thank you."
        \\    choice "Ask the way.":
        \\      say Guide: "North."
        \\  choice "Show the sigil." if Carries(Hero, Guide):
        \\    say Guide: "Pass."
        \\
        \\routine Idle(Hero):
        \\  wait 1 ticks
        \\
    ;
    const conv = try dialogue_sources(arena.allocator(), src, null);
    try testing.expectEqual(@as(usize, 1), conv.len);
    try testing.expectEqualStrings("on cue TalksTo(Hero, Guide)", conv[0].title);
    const n = conv[0].nodes;
    try testing.expectEqual(@as(usize, 7), n.len);
    try testing.expect(!n[0].choice and n[0].line == 8);
    try testing.expectEqualStrings("not Paid(Hero)", n[1].guard);
    try testing.expectEqual(@as(u8, 0), n[1].never);
    try testing.expectEqual(@as(u16, 1), n[3].depth);
    try testing.expectEqualStrings("Ask the way.", n[3].text);
    try testing.expectEqual(@as(u16, 2), n[4].depth);
    try testing.expectEqual(@as(u8, 1), n[5].never);
    try testing.expectEqual(@as(u32, 14), n[5].line);
}

test "D-204: a choice whose guard nothing remembers warns, at the choice, and a remembered one does not" {
    const testing = std.testing;
    const head =
        \\scene Quay:
        \\  cast: Hero, Guide
        \\
        \\relation Carries(who, thing)
        \\relation Sigil(thing)
        \\
        \\on cue TalksTo(Hero, Guide):
        \\  choice "Ask about the gate.":
        \\    say Guide: "It opens at dawn."
        \\  choice "Show the sigil." if Carries(Hero, Sigil):
        \\    say Guide: "Then you may pass."
        \\  choice "Beg." if not Carries(Hero, Sigil):
        \\    say Guide: "No."
        \\
    ;
    const res = check_source(testing.allocator, head);
    try testing.expect(res.is_valid);
    try testing.expectEqual(@as(usize, 2), res.warning_count);
    try testing.expectEqual(@as(u32, 10), res.warnings[0].line);
    try testing.expect(std.mem.indexOf(u8, res.warnings[0].message(), "never offered") != null);
    try testing.expect(std.mem.indexOf(u8, res.warnings[1].message(), "always offered") != null);
    // Once something remembers the relation, neither choice warns.
    const fixed = head ++ "routine Find(Hero):\n  remember Carries(Hero, Sigil)\n";
    const ok = check_source(testing.allocator, fixed);
    try testing.expectEqual(@as(usize, 0), ok.warning_count);
}

test "D-203: dilemma_sources lists dilemmas, decisions, and red lines with their line ranges" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const src =
        \\scene Court:
        \\  cast: Valerius, Thief
        \\
        \\relation Accused(who)
        \\relation Criminal(who)
        \\relation Chose(decision, option)
        \\axis Justice between Cruelty and Leniency
        \\axis Mercy between Vengeance and "Condoning Harm"
        \\
        \\decision Sentence:
        \\  actor Valerius
        \\  fires Sentenced
        \\  requires Accused(Thief)
        \\  option Execute:
        \\    picks 1 when Criminal(Thief)
        \\  option Pardon:
        \\    picks 1 when Accused(Thief)
        \\
        \\red lines Valerius: Execute
        \\
        \\dilemma StolenBread:
        \\  actor Valerius
        \\  fires Judged
        \\  requires Accused(Thief)
        \\  weighs Justice against Mercy
        \\  tiers 8 and 4
        \\  leans 3 toward Justice when Criminal(Thief)
        \\  strong Justice: "The law is the law." -> Hang
        \\  moderate Justice: "A night in the cells." -> Jail
        \\  neutral: "Show me why." -> Wait
        \\  moderate Mercy: "Pay for the loaf." -> Fine
        \\  strong Mercy: "Let him go." -> Pardon
        \\
    ;
    const d = try dilemma_sources(arena.allocator(), src, null);
    try testing.expectEqual(@as(usize, 1), d.dilemmas.len);
    const b = d.dilemmas[0];
    try testing.expectEqual(@as(u32, 21), b.block.line);
    try testing.expectEqual(@as(u32, 32), b.block.end_line);
    try testing.expectEqual(@as(u8, 8), b.strong);
    try testing.expectEqual(@as(u8, 4), b.moderate);
    try testing.expectEqual(@as(u32, 3), b.leans[0].points);
    try testing.expectEqualStrings("Jail", b.tiers[@intFromEnum(dilemma_mod.Tier.moderate_axis)].action);
    try testing.expectEqual(@as(u32, 10), d.decisions[0].block.line);
    try testing.expectEqual(@as(u32, 17), d.decisions[0].block.end_line);
    try testing.expectEqual(@as(usize, 2), d.decisions[0].options.len);
    try testing.expectEqual(@as(u32, 19), d.red_lines[0].at.line);
}

test "D-202: cast_sources lists scenes, display names, axes, starting values, and code with their lines" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const src =
        \\scene Court:
        \\  cast: Valerius, Ines
        \\  marks: Bench
        \\
        \\name Valerius: "Judge Valerius"
        \\
        \\axis Mercy between Vengeance and "Condoning Harm"
        \\  drift step 4
        \\
        \\remember Mercy(Valerius, -3)
        \\
        \\routine Sit(Valerius):
        \\  wait 1 ticks
        \\
        \\on cue TalksTo(Ines, Valerius):
        \\  say Valerius: "Speak."
        \\
    ;
    const c = try cast_sources(arena.allocator(), src, null);
    try testing.expectEqual(@as(usize, 1), c.scenes.len);
    try testing.expectEqual(@as(u32, 3), c.scenes[0].declared.end_line);
    try testing.expectEqual(@as(usize, 2), c.scenes[0].cast.len);
    try testing.expectEqualStrings("Judge Valerius", c.names[0].text);
    try testing.expectEqual(@as(u32, 5), c.names[0].at.line);
    try testing.expectEqualStrings("Condoning Harm", c.axes[0].high);
    try testing.expectEqual(@as(u32, 7), c.axes[0].at.line);
    try testing.expectEqual(@as(u32, 8), c.axes[0].at.end_line);
    try testing.expectEqual(@as(i32, -3), c.values[0].value);
    try testing.expectEqual(@as(u32, 10), c.values[0].at.line);
    try testing.expectEqual(@as(usize, 2), c.code.len);
    try testing.expectEqual(@as(u32, 12), c.code[0].at.line);
    try testing.expect(c.code[1].handler);
    try testing.expectEqualStrings("Ines", c.code[1].actor);
    try testing.expectEqual(@as(u32, 15), c.code[1].at.line);
}

test "D-200: room_sources lists each scene's lines, places, and room block across files" {
    const testing = std.testing;
    const Files = struct {
        fn read(context: *anyopaque, allocator: std.mem.Allocator, path: []const u8) anyerror![]const u8 {
            _ = context;
            if (std.mem.eql(u8, path, "rooms.bespoke")) return allocator.dupe(u8,
                \\# The yard's layout.
                \\room Yard:
                \\  mark Gate at 40 120
                \\  mark Well at 200 132
                \\  prop Bucket at 214 128
                \\  area Bucket: 210 120 8 9
                \\  walkway Gate to Well
                \\
            );
            return error.FileNotFound;
        }
    };
    var dummy: u8 = 0;
    const files = FileSource{ .context = &dummy, .read = Files.read };
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const src =
        \\scene Yard:
        \\  cast: Hero
        \\  props: Bucket
        \\  marks: Gate, Well
        \\
        \\scene Hall:
        \\  marks: Door, Hearth
        \\
        \\include "rooms.bespoke"
        \\
    ;
    const scenes = try room_sources(arena.allocator(), src, files);
    try testing.expectEqual(@as(usize, 2), scenes.len);
    const yard = scenes[0];
    try testing.expectEqualStrings("", yard.declared.script);
    try testing.expectEqual(@as(u32, 1), yard.declared.line);
    try testing.expectEqual(@as(u32, 4), yard.declared.end_line);
    try testing.expectEqualStrings("rooms.bespoke", yard.block.?.script);
    try testing.expectEqual(@as(u32, 2), yard.block.?.line);
    try testing.expectEqual(@as(u32, 7), yard.block.?.end_line);
    try testing.expect(!yard.chained);
    try testing.expectEqual(@as(usize, 3), yard.places.len);
    try testing.expect(yard.places[0].placed and yard.places[2].prop);
    try testing.expect(yard.areas[0].in_block);
    // The hall has no block: its marks sit on their default spots, drawn where the engine draws them.
    const hall = scenes[1];
    try testing.expect(hall.block == null and hall.chained);
    try testing.expect(!hall.places[0].placed);
    const w = spatial_mod.art_to_world(hall.places[1].x, hall.places[1].y);
    try testing.expectEqual(spatial_mod.Point2D{ .x = codegen.stage_x(1, 2), .y = 0 }, w);
}

test "D-196: art_sources names each image's script, line, and frames, and its animations" {
    const testing = std.testing;
    const Files = struct {
        fn read(context: *anyopaque, allocator: std.mem.Allocator, path: []const u8) anyerror![]const u8 {
            _ = context;
            if (std.mem.eql(u8, path, "art.bespoke")) return allocator.dupe(u8,
                \\
                \\image Lamp frames 1x1:
                \\  "bl"
                \\
                \\sprite Lantern: Lamp
                \\  idle: 1 for 50, 0 for 4
                \\
            );
            return error.FileNotFound;
        }
    };
    var dummy: u8 = 0;
    const files = FileSource{ .context = &dummy, .read = Files.read };
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const src =
        \\scene Room:
        \\  props: Lantern
        \\  marks: Door
        \\
        \\palette:
        \\  "." transparent
        \\  "b" 176 128 56
        \\  "l" 250 214 96
        \\
        \\include "art.bespoke"
        \\
    ;
    const art = try art_sources(arena.allocator(), src, files);
    try testing.expectEqual(@as(usize, 1), art.images.len);
    const lamp = art.images[0];
    try testing.expectEqualStrings("Lamp", lamp.name);
    try testing.expectEqualStrings("", lamp.file);
    try testing.expectEqualStrings("art.bespoke", lamp.script);
    try testing.expectEqual(@as(u32, 2), lamp.line);
    try testing.expectEqual(@as(u16, 2), lamp.width);
    try testing.expectEqual(@as(u16, 1), lamp.frame_width);
    try testing.expectEqual(@as(usize, 1), art.animations.len);
    try testing.expectEqualStrings("Lantern", art.animations[0].owner);
    try testing.expectEqual(image_mod.Anim.idle, art.animations[0].anim);
    try testing.expectEqual(@as(usize, 2), art.animations[0].steps.len);
    try testing.expectEqual(@as(u16, 50), art.animations[0].steps[0].duration);
    // The declared colours, without the transparent code.
    try testing.expectEqual(@as(usize, 2), art.palette.len);
    try testing.expectEqual(@as(u8, 176), art.palette[0].r);
}

test "P48-15: an included program compiles in source order, and its errors name their file" {
    const testing = std.testing;
    const Files = struct {
        fn read(context: *anyopaque, allocator: std.mem.Allocator, path: []const u8) anyerror![]const u8 {
            _ = context;
            if (std.mem.indexOf(u8, path, "..") != null) return error.PathOutsideScriptFolder;
            if (std.mem.eql(u8, path, "guarded.bespoke")) return allocator.dupe(u8, "on cue Uses(Scout, Lamp) where Lit(Lamp):\n  remember Saw(Scout, Lamp)\n");
            if (std.mem.eql(u8, path, "default.bespoke")) return allocator.dupe(u8, "on cue Uses(Scout, Lamp):\n  remember Lit(Lamp)\n");
            if (std.mem.eql(u8, path, "typo.bespoke")) return allocator.dupe(u8, "\n\nremember Lit(lamp)\n");
            return error.FileNotFound;
        }
    };
    var dummy: u8 = 0;
    const files = FileSource{ .context = &dummy, .read = Files.read };
    const head = "entity Scout, Lamp\nrelation Lit(thing)\nrelation Saw(who, thing)\n";

    // Guarded first, then the default: valid, and a repeated include is skipped.
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try compile_source_with(testing.allocator, &world, null, head ++ "include \"guarded.bespoke\"\ninclude \"default.bespoke\"\ninclude \"guarded.bespoke\"\n", files);
    defer compiled.deinit();
    try testing.expectEqual(@as(usize, 1), compiled.cue_handler_chain.count());

    // The default first makes the guarded handler unreachable; both lines are named by file.
    const order = check_source_with(testing.allocator, head ++ "include \"default.bespoke\"\ninclude \"guarded.bespoke\"\n", files);
    try testing.expectEqualStrings("UnreachableCueHandler", order.kind());
    try testing.expectEqualStrings("guarded.bespoke", order.file());
    try testing.expectEqual(@as(u32, 1), order.line);
    try testing.expectEqualStrings("this handler can never run: the handler on line 1 of default.bespoke has the same signature and no guard", order.message());

    // An error inside an included file has that file's line; the main script's lines after an
    // include keep their own numbers.
    const typo = check_source_with(testing.allocator, head ++ "include \"typo.bespoke\"\n", files);
    try testing.expectEqualStrings("typo.bespoke", typo.file());
    try testing.expectEqual(@as(u32, 3), typo.line);
    try testing.expectEqual(@as(u32, 14), typo.column);
    const after = check_source_with(testing.allocator, head ++ "include \"guarded.bespoke\"\nremember Lit(lamp)\n", files);
    try testing.expectEqualStrings("", after.file());
    try testing.expectEqual(@as(u32, 5), after.line);

    // A missing file and an escaping path are refused at the include line.
    const missing = check_source_with(testing.allocator, head ++ "include \"gone.bespoke\"\n", files);
    try testing.expectEqualStrings("include cannot read \"gone.bespoke\" (FileNotFound)", missing.message());
    try testing.expectEqual(@as(u32, 4), missing.line);
    const escaping = check_source_with(testing.allocator, "include \"../up.bespoke\"\n", files);
    try testing.expectEqualStrings("include cannot read \"../up.bespoke\" (PathOutsideScriptFolder)", escaping.message());
    // Without a file source, as in the browser, an include is refused like a PNG.
    try testing.expectEqualStrings("IncludeFailed", check_source(testing.allocator, "include \"guarded.bespoke\"\n").kind());
}

test "P48-24: quoted # bookkeeping names and #path routines are refused" {
    const testing = std.testing;
    const cases = [_][]const u8{
        "entity Hero\nnow Hero is \"#DialogueOpen\"\n",
        "entity Hero\nwhen Hero is \"#GridSeeded\":\n  wait 1 ticks\n",
        "entity Hero\nroutine Go(Hero):\n  now Hero is \"#Secret\"\n",
        "entity Hero\nroutine \"#path:Wits\"(Hero):\n  wait 1 ticks\n",
        "entity Hero\nroutine \"#DialogueChoice\"(Hero):\n  wait 1 ticks\n",
    };
    for (cases) |source| {
        const res = check_source(testing.allocator, source);
        try testing.expect(!res.is_valid);
        try testing.expectEqualStrings("ReservedBookkeepingName", res.kind());
    }
}

test "P48-24: parser bounds, 9-variable when rules, and failed compile cleanup leak nothing" {
    const testing = std.testing;

    // 1. 0-arg fact pattern, u32 area addition overflow, and priority > 65535 fail cleanly.
    const bad_parse = [_][]const u8{
        "entity Hero\nrelation Flag(who)\nwhen Flag():\n  wait 1 ticks\n",
        "scene Room:\n  props Lamp\npalette:\n  \".\" transparent\nimage Bg:\n  \"..\"\narea Lamp: 4294967290 0 10 10\n",
        "entity Guard, Coin\nscene S:\n  marks Gate\nsociety Town:\n  need Hunger rate 1 seek 50 at Gate\n  member Guard owns Coin\n  gathering Gate\n  flight Gate\n  priority 70000\n",
    };
    for (bad_parse) |src| {
        const res = check_source(testing.allocator, src);
        try testing.expect(!res.is_valid);
    }

    // 2. A `when` rule with 9 distinct variables is refused instead of wrapping or out-of-bounds.
    const nine_vars =
        \\entity E
        \\relation R(a, b)
        \\when R(?a, ?b) and R(?c, ?d) and R(?e, ?f) and R(?g, ?h) and R(?i, _):
        \\  wait 1 ticks
        \\
    ;
    const nine_res = check_source(testing.allocator, nine_vars);
    try testing.expect(!nine_res.is_valid);
    try testing.expectEqualStrings("TooManyCueGuardVariables", nine_res.kind());

    // 3. A script that allocates routines, cues, and rules before failing late in compile()
    //    must leak zero bytes under testing.allocator.
    const late_fail =
        \\entity Hero
        \\relation Ready(who)
        \\routine Alpha(Hero):
        \\  remember Ready(Hero)
        \\on cue Uses(Hero, _):
        \\  wait 1 ticks
        \\when Ready(?who):
        \\  remember Looks(Hero, MissingLook)
        \\
    ;
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    try testing.expectError(error.UnknownLook, compile_source(testing.allocator, &world, null, late_fail));
}

test "P48-20: case-only twins of entity, relation, routine, and scene names are refused with the existing spelling" {
    const testing = std.testing;

    // 1. Entity case twin.
    const entity_twin =
        \\entity Lamp, LAMP
        \\
    ;
    const entity_res = check_source(testing.allocator, entity_twin);
    try testing.expect(!entity_res.is_valid);
    try testing.expectEqualStrings("CaseTwinName", entity_res.kind());
    try testing.expectEqualStrings("Lamp", entity_res.suggestion().?);

    // 2. Relation case twin.
    const rel_twin =
        \\entity Lamp
        \\relation Lit(x)
        \\routine Light(Lamp):
        \\  remember LIT(Lamp)
        \\
    ;
    const rel_res = check_source(testing.allocator, rel_twin);
    try testing.expect(!rel_res.is_valid);
    try testing.expectEqualStrings("CaseTwinName", rel_res.kind());
    try testing.expectEqualStrings("Lit", rel_res.suggestion().?);

    // 3. Routine case twin.
    const routine_twin =
        \\entity Hero
        \\routine Patrol(Hero):
        \\  wait 1 ticks
        \\routine PATROL(Hero):
        \\  wait 1 ticks
        \\
    ;
    const routine_res = check_source(testing.allocator, routine_twin);
    try testing.expect(!routine_res.is_valid);
    try testing.expectEqualStrings("CaseTwinName", routine_res.kind());
    try testing.expectEqualStrings("Patrol", routine_res.suggestion().?);

    // 4. Scene case twin.
    const scene_twin =
        \\scene Garden:
        \\  marks: Gate
        \\scene GARDEN:
        \\  marks: Corner
        \\
    ;
    const scene_res = check_source(testing.allocator, scene_twin);
    try testing.expect(!scene_res.is_valid);
    try testing.expectEqualStrings("CaseTwinName", scene_res.kind());
    try testing.expectEqualStrings("Garden", scene_res.suggestion().?);

    // 5. Lowercase variable parameters, same-spelling cross-namespace names, and spoken prose remain allowed.
    const allowed =
        \\entity Lamp, Scout, Mercy
        \\axis Mercy between Cruelty and Weakness
        \\relation Holds(who, item)
        \\on cue Uses(Scout, lamp):
        \\  say Scout: "LAMP"
        \\  remember Holds(Scout, Lamp)
        \\  choice "lamp":
        \\    wait 1 ticks
        \\
    ;
    const allowed_res = check_source(testing.allocator, allowed);
    try testing.expect(allowed_res.is_valid);

    // 6. Lowercase declarations and exact duplicate routines keep their existing errors.
    const lower_res = check_source(testing.allocator, "entity Hero, hero\n");
    try testing.expect(!lower_res.is_valid);
    try testing.expectEqualStrings("LowercaseName", lower_res.kind());

    const dup_routine =
        \\entity Hero
        \\routine Patrol(Hero):
        \\  wait 1 ticks
        \\routine Patrol(Hero):
        \\  wait 1 ticks
        \\
    ;
    const dup_res = check_source(testing.allocator, dup_routine);
    try testing.expect(!dup_res.is_valid);
    try testing.expectEqualStrings("DuplicateRoutineName", dup_res.kind());
}

test "codegen refuses scripts exceeding 65535 bytecode bytes or 16-bit jump offsets cleanly" {
    const testing = std.testing;
    // 1. An `if` body exceeding 32767 bytes returns JumpOffsetTooLarge instead of panicking.
    var big_if = std.array_list.Managed(u8).init(testing.allocator);
    defer big_if.deinit();
    try big_if.appendSlice("entity Hero\nrelation Flag(who)\nroutine Patrol(Hero):\n  if Flag(Hero):\n");
    // Each `remember Flag(Hero)` emits push_entity(5) + push_relation(3) + push_const(5) + remember(5) = 18 bytes.
    // 1,900 statements = ~34,200 bytes > 32,767.
    for (0..1900) |_| {
        try big_if.appendSlice("    remember Flag(Hero)\n");
    }
    const if_res = check_source(testing.allocator, big_if.items);
    try testing.expect(!if_res.is_valid);
    try testing.expectEqualStrings("JumpOffsetTooLarge", if_res.kind());

    // 2. Multiple routines totaling > 65535 bytes return BytecodeTooLarge instead of panicking.
    var big_prog = std.array_list.Managed(u8).init(testing.allocator);
    defer big_prog.deinit();
    try big_prog.appendSlice("entity Hero\nrelation Flag(who)\n");
    for (0..10) |ri| {
        var hdr: [64]u8 = undefined;
        try big_prog.appendSlice(try std.fmt.bufPrint(&hdr, "routine R{d}(Hero):\n", .{ri}));
        for (0..400) |_| {
            try big_prog.appendSlice("  remember Flag(Hero)\n");
        }
    }
    const prog_res = check_source(testing.allocator, big_prog.items);
    try testing.expect(!prog_res.is_valid);
    try testing.expectEqualStrings("BytecodeTooLarge", prog_res.kind());
}

test "parser rejects statement nesting deeper than MAX_STMT_DEPTH" {
    const testing = std.testing;
    var src = std.array_list.Managed(u8).init(testing.allocator);
    defer src.deinit();
    try src.appendSlice("entity Hero\nrelation Flag(who)\nroutine Deep(Hero):\n");
    for (0..parser.MAX_STMT_DEPTH + 2) |depth| {
        for (0..depth + 1) |_| try src.appendSlice("  ");
        try src.appendSlice("if Flag(Hero):\n");
    }
    for (0..parser.MAX_STMT_DEPTH + 3) |_| try src.appendSlice("  ");
    try src.appendSlice("remember Flag(Hero)\n");

    const res = check_source(testing.allocator, src.items);
    try testing.expect(!res.is_valid);
    try testing.expectEqualStrings("NestingTooDeep", res.kind());
}

test "P49-01: colour cycles compile with explicit or default intervals and reject invalid declarations" {
    const testing = std.testing;
    const valid =
        \\scene Shore:
        \\  cast: Hero
        \\  marks: Pier
        \\palette:
        \\  "." transparent
        \\  "a" 10 20 30
        \\  "b" 40 50 60
        \\  "c" 70 80 90
        \\  "d" 100 110 120
        \\  "e" 130 140 150
        \\cycle "a" "b" "c" every 8
        \\cycle "d" "e"
        \\entity Cycle
        \\routine CycleCheck(Cycle):
        \\  wait 1 ticks
    ;
    var world = try World.init(testing.allocator, world_mod.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try compile_source(testing.allocator, &world, &spatial, valid);
    defer compiled.deinit();
    try testing.expectEqual(@as(usize, 2), compiled.art.cycles.len);
    try testing.expectEqual(@as(u16, 8), compiled.art.cycles[0].every);
    try testing.expectEqual(@as(usize, 3), compiled.art.cycles[0].colours.len);
    try testing.expectEqual(@as(u16, image_mod.DEFAULT_CYCLE_INTERVAL), compiled.art.cycles[1].every);
    try testing.expectEqual(@as(usize, 2), compiled.art.cycles[1].colours.len);

    const Case = struct { src: []const u8, line: u32, needle: []const u8 };
    const cases = [_]Case{
        .{ .src = "cycle \"a\" \"b\"\n", .line = 1, .needle = "palette:" },
        .{ .src = "palette:\n  \".\" transparent\n  \"a\" 1 2 3\ncycle \"a\"\n", .line = 4, .needle = "at least two" },
        .{ .src = "palette:\n  \".\" transparent\n  \"a\" 1 2 3\ncycle \"a\" \"z\"\n", .line = 4, .needle = "does not declare" },
        .{ .src = "palette:\n  \".\" transparent\n  \"a\" 1 2 3\ncycle \".\" \"a\"\n", .line = 4, .needle = "transparent" },
        .{ .src = "palette:\n  \".\" transparent\n  \"a\" 1 2 3\n  \"b\" 1 2 3\ncycle \"a\" \"b\"\n", .line = 5, .needle = "repeats colour" },
        .{ .src = "palette:\n  \".\" transparent\n  \"a\" 1 2 3\n  \"b\" 4 5 6\n  \"c\" 7 8 9\ncycle \"a\" \"b\"\ncycle \"b\" \"c\"\n", .line = 7, .needle = "repeats colour" },
        .{ .src = "palette:\n  \".\" transparent\n  \"a\" 1 2 3\n  \"b\" 4 5 6\ncycle \"a\" \"b\" every 0\n", .line = 5, .needle = "1 to 600" },
        .{ .src = "palette:\n  \".\" transparent\n  \"a\" 1 2 3\n  \"b\" 4 5 6\ncycle \"a\" \"b\" every 601\n", .line = 5, .needle = "1 to 600" },
        .{ .src = "palette:\n  \".\" transparent\n  \"a\" 1 2 3\n  \"b\" 4 5 6\ncycle \"a\" \"b\" extra\n", .line = 5, .needle = "optional 'every <N>'" },
    };
    for (cases) |c| {
        const res = check_source(testing.allocator, c.src);
        try testing.expect(!res.is_valid);
        try testing.expectEqual(c.line, res.line);
        try testing.expect(std.mem.indexOf(u8, res.message(), c.needle) != null);
    }
}
