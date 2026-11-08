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

/// High-level compiler entry point: lowers BeSpoke DSL source text directly to VM bytecode (P4-01, P4-02, P4-03).
pub fn compile_source(
    allocator: std.mem.Allocator,
    world: *World,
    spatial: ?*SpatialSystem,
    source: []const u8,
) !CompiledProgram {
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

pub const CheckResult = struct {
    is_valid: bool,
    diagnostic: ?Diagnostic = null,
    entity_count: usize = 0,
    routine_count: usize = 0,
    rule_count: usize = 0,
    scene_count: usize = 0,
    bytecode_len: usize = 0,
};

/// Validates syntax and semantic compilation of BeSpoke DSL source without permanent side effects (P15-03, D-018).
pub fn check_source(allocator: std.mem.Allocator, source: []const u8) CheckResult {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(alloc, source);
    defer lex.deinit();

    var parse = Parser.init(alloc, &lex) catch |err| {
        return .{
            .is_valid = false,
            .diagnostic = .{
                .line = 1,
                .column = 1,
                .message = @errorName(err),
            },
        };
    };

    const ast = parse.parse_program() catch {
        return .{
            .is_valid = false,
            .diagnostic = parse.diagnostic orelse Diagnostic{
                .line = parse.current.line,
                .column = parse.current.col,
                .message = "syntax error",
            },
        };
    };

    var dummy_world = World.init(alloc, 1024 * 1024) catch |err| {
        return .{
            .is_valid = false,
            .diagnostic = .{ .line = 1, .column = 1, .message = @errorName(err) },
        };
    };
    defer dummy_world.deinit();

    var dummy_spatial = SpatialSystem.init(alloc);
    defer dummy_spatial.deinit();

    var cg = Codegen.init(alloc, &dummy_world, &dummy_spatial);
    var compiled = cg.compile(&ast) catch |err| {
        return .{
            .is_valid = false,
            .diagnostic = .{
                .line = 1,
                .column = 1,
                .message = @errorName(err),
            },
        };
    };
    defer compiled.deinit();

    return .{
        .is_valid = true,
        .diagnostic = null,
        .entity_count = ast.entities.items.len,
        .routine_count = ast.routines.items.len,
        .rule_count = ast.when_rules.items.len,
        .scene_count = if (ast.scene_defs.items.len > 0) ast.scene_defs.items.len else ast.scenes.items.len,
        .bytecode_len = compiled.chunk.count(),
    };
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
    try testing.expect(res.diagnostic == null);
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
    try testing.expect(res.diagnostic != null);
    try testing.expectEqual(@as(u32, 1), res.diagnostic.?.line);
    try testing.expectEqual(@as(u32, 16), res.diagnostic.?.column);
    try testing.expect(std.mem.indexOf(u8, res.diagnostic.?.message, "expected lparen") != null);
}
