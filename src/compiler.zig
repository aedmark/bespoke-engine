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
const spatial_mod = @import("spatial.zig");
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
    if (source.len > MAX_SOURCE_SIZE) return error.ScriptTooLarge;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(alloc, source);
    defer lex.deinit();

    var parse = try Parser.init(alloc, &lex);
    const ast = try parse.parse_program();

    var cg = Codegen.init(allocator, world, spatial);
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
pub const CheckResult = struct {
    is_valid: bool,
    line: u32 = 0,
    column: u32 = 0,
    message_buf: [check_message_capacity]u8 = undefined,
    message_len: usize = 0,
    hint_buf: [Suggestions.max_len]u8 = undefined,
    hint_len: usize = 0,
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

    fn with_hint(self: CheckResult, hint: ?[]const u8) CheckResult {
        var res = self;
        if (hint) |name| {
            res.hint_len = name.len;
            @memcpy(res.hint_buf[0..name.len], name);
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
pub fn check_source(allocator: std.mem.Allocator, source: []const u8) CheckResult {
    if (source.len > MAX_SOURCE_SIZE) return CheckResult.failure(1, 1, "script exceeds the 16 MiB source limit");
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(alloc, source);
    defer lex.deinit();

    var parse = Parser.init(alloc, &lex) catch |err| return lexer_failure(&lex, err);

    const ast = parse.parse_program() catch |err| {
        // `parse.diagnostic.message` points into `parse.diag_buf`; `failure` copies it out.
        if (parse.diagnostic) |d| return CheckResult.failure(d.line, d.column, d.message).with_hint(parse.suggestion);
        return lexer_failure(&lex, err);
    };

    var dummy_world = World.init(alloc, 1024 * 1024) catch |err| return CheckResult.failure(1, 1, failure_message(err));
    defer dummy_world.deinit();

    var dummy_spatial = SpatialSystem.init(alloc);
    defer dummy_spatial.deinit();

    var cg = Codegen.init(alloc, &dummy_world, &dummy_spatial);
    var compiled = cg.compile(&ast) catch |err| {
        var line = cg.error_line;
        var col = cg.error_column;
        if (line == 0) {
            const pos = source_position(source, cg.error_context);
            line = pos[0];
            col = pos[1];
        }
        return CheckResult.failure(line, col, failure_message(err)).with_hint(cg.error_suggestion);
    };
    defer compiled.deinit();

    return .{
        .is_valid = true,
        .entity_count = ast.entities.items.len,
        .routine_count = ast.routines.items.len,
        .rule_count = ast.when_rules.items.len,
        .scene_count = if (ast.scene_defs.items.len > 0) ast.scene_defs.items.len else ast.scenes.items.len,
        .bytecode_len = compiled.chunk.count(),
    };
}

fn lexer_failure(lex: *const Lexer, err: anyerror) CheckResult {
    if (lex.string_start) |tok| return CheckResult.failure(tok.line, tok.col, "unterminated string; add a closing double quote");
    return CheckResult.failure(lex.line, lex.col, failure_message(err));
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
        error.TooManyCueParameters => "a guarded cue can have at most three parameters",
        error.InvalidCueGuardPattern => "a cue guard needs one or two arguments per fact",
        error.TooManyCueGuardVariables => "a cue guard can bind at most eight variables",
        error.InvalidAgenda => "invalid agenda or too many agendas",
        error.UnknownHintRoom => "a need names no room, and no scene declares the prop or mark it names",
        error.InvalidGoal => "invalid goal or too many goals; check need names, prerequisites, rooms, and hint tiers",
        error.InvalidSpellbook => "invalid spellbook; check word kinds and tiers, and that each spell names a power, an element, and a form",
        error.InvalidDecision => "invalid decision; check its actor, cue, trigger lines, and scored options",
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
        error.WaypointNotFound => "waypoint could not be resolved",
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
