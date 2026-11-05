const std = @import("std");
const parser_mod = @import("parser.zig");
const lexer_mod = @import("lexer.zig");
const bytecode_mod = @import("../bytecode.zig");
const world_mod = @import("../world.zig");
const spatial_mod = @import("../spatial.zig");

pub const AST = parser_mod.AST;
pub const Stmt = parser_mod.Stmt;
pub const Expr = parser_mod.Expr;
pub const BytecodeChunk = bytecode_mod.BytecodeChunk;
pub const Opcode = bytecode_mod.Opcode;
pub const World = world_mod.World;
pub const EntityId = world_mod.EntityId;
pub const RelationKind = world_mod.RelationKind;
pub const SpatialSystem = spatial_mod.SpatialSystem;

pub const CompiledProgram = struct {
    chunk: BytecodeChunk,
    routine_entries: std.StringHashMap(usize),
    when_rule_entries: std.ArrayList(usize),
    cue_handler_entries: std.StringHashMap(usize),

    pub fn deinit(self: *CompiledProgram) void {
        self.chunk.deinit();
        self.routine_entries.deinit();
        self.when_rule_entries.deinit();
        self.cue_handler_entries.deinit();
    }
};

pub const Codegen = struct {
    allocator: std.mem.Allocator,
    world: *World,
    spatial: ?*SpatialSystem,
    chunk: BytecodeChunk,
    routine_entries: std.StringHashMap(usize),
    when_rule_entries: std.ArrayList(usize),
    cue_handler_entries: std.StringHashMap(usize),

    pub fn init(allocator: std.mem.Allocator, world: *World, spatial: ?*SpatialSystem) Codegen {
        return Codegen{
            .allocator = allocator,
            .world = world,
            .spatial = spatial,
            .chunk = BytecodeChunk.init(allocator),
            .routine_entries = std.StringHashMap(usize).init(allocator),
            .when_rule_entries = std.ArrayList(usize).init(allocator),
            .cue_handler_entries = std.StringHashMap(usize).init(allocator),
        };
    }

    /// Compiles an entire AST into a CompiledProgram (P4-03).
    pub fn compile(mut_self: *Codegen, ast: *const AST) !CompiledProgram {
        // 1. Intern declared entities
        for (ast.entities.items) |name| {
            _ = try mut_self.world.intern_entity(name);
        }

        // 2. Intern declared relations
        for (ast.relations.items) |rel| {
            _ = try mut_self.world.intern_relation(
                rel.name,
                if (rel.is_property) .property else .set,
            );
        }

        // 3. Compile initial declarative statements
        for (ast.initial_stmts.items) |stmt| {
            try mut_self.compile_stmt(stmt);
        }

        // 4. Compile routines
        for (ast.routines.items) |routine| {
            const entry_pc = mut_self.chunk.count();
            try mut_self.routine_entries.put(routine.name, entry_pc);

            for (routine.body) |stmt| {
                try mut_self.compile_stmt(stmt);
            }
            _ = try mut_self.chunk.emit_op(.halt);
        }

        // 5. Compile when rules
        for (ast.when_rules.items) |rule| {
            const entry_pc = mut_self.chunk.count();
            try mut_self.when_rule_entries.append(entry_pc);

            for (rule.body) |stmt| {
                try mut_self.compile_stmt(stmt);
            }
            _ = try mut_self.chunk.emit_op(.resume_routine);
        }

        // 6. Compile cue handlers
        for (ast.cue_handlers.items) |cue| {
            const entry_pc = mut_self.chunk.count();
            try mut_self.cue_handler_entries.put(cue.cue_name, entry_pc);

            for (cue.body) |stmt| {
                try mut_self.compile_stmt(stmt);
            }
            _ = try mut_self.chunk.emit_op(.halt);
        }

        return CompiledProgram{
            .chunk = mut_self.chunk,
            .routine_entries = mut_self.routine_entries,
            .when_rule_entries = mut_self.when_rule_entries,
            .cue_handler_entries = mut_self.cue_handler_entries,
        };
    }

    fn compile_stmt(self: *Codegen, stmt: Stmt) !void {
        switch (stmt) {
            .remember => |rem| {
                const subj = try self.resolve_entity(rem.args[0]);
                const rel = try self.resolve_relation(rem.relation);
                const obj = try self.resolve_entity_or_value(rem.args[1]);

                try self.chunk.emit_push_entity(subj);
                try self.chunk.emit_push_relation(rel);
                try self.chunk.emit_push_const(obj);
                try self.chunk.emit_remember(rem.ttl_ticks);
            },
            .forget => |fg| {
                const subj = try self.resolve_entity(fg.args[0]);
                const rel = try self.resolve_relation(fg.relation);
                const has_obj = fg.args.len > 1 and !std.mem.eql(u8, fg.args[1], "_");

                try self.chunk.emit_push_entity(subj);
                try self.chunk.emit_push_relation(rel);
                if (has_obj) {
                    const obj = try self.resolve_entity_or_value(fg.args[1]);
                    try self.chunk.emit_push_const(obj);
                }
                _ = try self.chunk.emit_op(.forget);
                try self.chunk.emit_u8(if (has_obj) 1 else 0);
            },
            .walk => |w| {
                const ent = try self.resolve_entity(w.entity);
                const wp_id = try self.resolve_waypoint(w.target);
                try self.chunk.emit_walk_to(ent, wp_id);
            },
            .face => |f| {
                const ent = try self.resolve_entity(f.entity);
                const target_id = try self.resolve_entity(f.target);
                // Emit peripheral cue for face direction
                try self.chunk.emit_push_entity(ent);
                try self.chunk.emit_push_entity(target_id);
                _ = try self.chunk.emit_op(.emit_cue);
                try self.chunk.emit_u16(1); // cue 1 = face
                try self.chunk.emit_u8(2); // 2 args
            },
            .wait_ticks => |ticks| {
                try self.chunk.emit_wait_ticks(ticks);
            },
            .wait_until => |expr| {
                // Emit condition block inline, with a jump over it
                const jump_over_pc = try self.chunk.emit_op(.jump);
                try self.chunk.emit_i16(0); // placeholder

                const cond_start_pc: u16 = @intCast(self.chunk.count());
                try self.compile_expr(expr);
                _ = try self.chunk.emit_op(.ret);

                // Patch jump over
                const jump_dest = self.chunk.count();
                const offset: i16 = @intCast(jump_dest - (jump_over_pc + 3));
                std.mem.writeInt(i16, self.chunk.code.items[jump_over_pc + 1 ..][0..2], offset, .little);

                // Emit wait_until pointing to cond_start_pc
                _ = try self.chunk.emit_op(.wait_until);
                try self.chunk.emit_u16(cond_start_pc);
            },
            .loop_stmt => |stmts| {
                const loop_start_pc = self.chunk.count();
                for (stmts) |s| {
                    try self.compile_stmt(s);
                }
                const loop_end_pc = self.chunk.count();
                const back_offset: u16 = @intCast((loop_end_pc + 3) - loop_start_pc);
                _ = try self.chunk.emit_op(.loop);
                try self.chunk.emit_u16(back_offset);
            },
            .if_stmt => |ifs| {
                try self.compile_expr(ifs.cond);
                const jump_false_pc = try self.chunk.emit_op(.jump_if_false);
                try self.chunk.emit_i16(0); // placeholder

                for (ifs.body) |s| {
                    try self.compile_stmt(s);
                }

                // Patch jump offset
                const dest_pc = self.chunk.count();
                const offset: i16 = @intCast(dest_pc - (jump_false_pc + 3));
                std.mem.writeInt(i16, self.chunk.code.items[jump_false_pc + 1 ..][0..2], offset, .little);
            },
            .interrupt_with => |iw| {
                const target = try self.resolve_entity(iw.entity);

                // Jump over the interrupt handler in linear execution
                const jump_over_pc = try self.chunk.emit_op(.jump);
                try self.chunk.emit_i16(0);

                const handler_pc: u16 = @intCast(self.chunk.count());
                for (iw.body) |s| {
                    try self.compile_stmt(s);
                }
                _ = try self.chunk.emit_op(.resume_routine);

                // Patch jump over
                const dest_pc = self.chunk.count();
                const offset: i16 = @intCast(dest_pc - (jump_over_pc + 3));
                std.mem.writeInt(i16, self.chunk.code.items[jump_over_pc + 1 ..][0..2], offset, .little);

                // Emit interrupt opcode
                try self.chunk.emit_push_entity(target);
                _ = try self.chunk.emit_op(.interrupt);
                try self.chunk.emit_u16(handler_pc);
            },
            .say => |s| {
                const speaker = try self.resolve_entity(s.speaker);
                const text_id = try self.world.intern_entity(s.text);
                try self.chunk.emit_push_entity(speaker);
                try self.chunk.emit_push_entity(text_id);
                _ = try self.chunk.emit_op(.emit_cue);
                try self.chunk.emit_u16(2); // cue 2 = say
                try self.chunk.emit_u8(2); // 2 args (speaker, text_entity)
            },
        }
    }

    fn compile_expr(self: *Codegen, expr: Expr) !void {
        switch (expr) {
            .roll_gte => |r| {
                try self.chunk.emit_roll_dice(r.count, r.sides);
                try self.chunk.emit_push_const(r.threshold);
                _ = try self.chunk.emit_op(.gte);
            },
            .has_fact => |pat| {
                const subj = try self.resolve_entity(pat.args[0]);
                const rel = try self.resolve_relation(pat.relation);
                const obj = try self.resolve_entity_or_value(pat.args[1]);

                try self.chunk.emit_push_entity(subj);
                try self.chunk.emit_push_relation(rel);
                try self.chunk.emit_push_const(obj);
                _ = try self.chunk.emit_op(.query_has);
                try self.chunk.emit_u8(0x07); // all 3 args provided
            },
            .not_fact => |pat| {
                const subj = try self.resolve_entity(pat.args[0]);
                const rel = try self.resolve_relation(pat.relation);
                const obj = try self.resolve_entity_or_value(pat.args[1]);

                try self.chunk.emit_push_entity(subj);
                try self.chunk.emit_push_relation(rel);
                try self.chunk.emit_push_const(obj);
                _ = try self.chunk.emit_op(.query_has);
                try self.chunk.emit_u8(0x07);
                _ = try self.chunk.emit_op(.not);
            },
        }
    }

    fn resolve_entity(self: *Codegen, name: []const u8) !EntityId {
        return try self.world.intern_entity(name);
    }

    fn resolve_relation(self: *Codegen, name: []const u8) !RelationKind {
        return try self.world.intern_relation(name, .set);
    }

    fn resolve_entity_or_value(self: *Codegen, name: []const u8) !u32 {
        if (std.fmt.parseInt(u32, name, 10)) |val| {
            return val;
        } else |_| {
            const ent = try self.resolve_entity(name);
            return ent.to_int();
        }
    }

    fn resolve_waypoint(self: *Codegen, name: []const u8) !u16 {
        if (self.spatial) |sp| {
            for (sp.graph.waypoints.items) |wp| {
                if (std.mem.eql(u8, wp.name, name)) {
                    return wp.id;
                }
            }
        }
        return 1; // default to first waypoint if spatial not configured
    }
};

test "P4-03: end-to-end compilation from source text to bytecode chunk" {
    const testing = std.testing;
    const vm_mod = @import("../vm.zig");
    const source =
        \\entity Guard, Cheese
        \\relation Carries(holder, item)
        \\remember Carries(Guard, Cheese)
        \\
        \\routine Patrol(Guard):
        \\  wait 10 ticks
        \\  remember Carries(Guard, Cheese)
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var world = try World.init(alloc, 1024 * 1024);
    defer world.deinit();

    var lexer = lexer_mod.Lexer.init(alloc, source);
    defer lexer.deinit();

    var parser = try parser_mod.Parser.init(alloc, &lexer);
    const ast = try parser.parse_program();

    var codegen = Codegen.init(alloc, &world, null);
    var compiled = try codegen.compile(&ast);
    defer compiled.deinit();

    try testing.expect(compiled.chunk.count() > 10);
    try testing.expect(compiled.routine_entries.contains("Patrol"));

    // Execute the compiled chunk on the VM to verify runtime execution
    var vm = vm_mod.VM.init(alloc, &world, &compiled.chunk);
    defer vm.deinit();

    _ = try vm.spawn_routine(try world.intern_entity("Guard"), 0);
    try vm.step_tick();

    try testing.expect(world.has_fact(
        try world.intern_entity("Guard"),
        try world.intern_relation("Carries", .set),
        (try world.intern_entity("Cheese")).to_int(),
    ));
}

test "P7-02: codegen compiles verb declarations and say statements into cue emitters" {
    const testing = std.testing;
    const source =
        \\entity Guard
        \\verb TalkTo(speaker, target):
        \\  say speaker: "Greetings traveler!"
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var world = try World.init(alloc, 1024 * 1024);
    defer world.deinit();

    var lexer = lexer_mod.Lexer.init(alloc, source);
    defer lexer.deinit();

    var parser = try parser_mod.Parser.init(alloc, &lexer);
    const ast = try parser.parse_program();

    var codegen = Codegen.init(alloc, &world, null);
    var compiled = try codegen.compile(&ast);
    defer compiled.deinit();

    try testing.expect(compiled.cue_handler_entries.contains("TalkTo"));
}
