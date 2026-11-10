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
    try testing.expectEqual(@as(u32, 5), no_at.diagnostic.?.line);
    try testing.expect(std.mem.indexOf(u8, no_at.diagnostic.?.message, "expected 'at'") != null);

    const unknown = check_source(testing.allocator,
        \\scene: Yard
        \\cast: Scout
        \\marks: Gate
        \\
        \\when Scout arrives at Cellar:
        \\  remember ReachedGate(Scout, true)
    );
    try testing.expect(!unknown.is_valid);
    try testing.expectEqual(@as(u32, 5), unknown.diagnostic.?.line);
    try testing.expectEqual(@as(u32, 23), unknown.diagnostic.?.column);
    try testing.expect(std.mem.indexOf(u8, unknown.diagnostic.?.message, "undeclared mark 'Cellar'") != null);

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
    try testing.expect(std.mem.indexOf(u8, empty.diagnostic.?.message, "needs an actor") != null);
}
