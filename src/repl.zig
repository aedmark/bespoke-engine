const std = @import("std");
const world_mod = @import("world.zig");
const spatial_mod = @import("spatial.zig");
const vm_mod = @import("vm.zig");

pub const World = world_mod.World;
pub const EntityId = world_mod.EntityId;
pub const RelationKind = world_mod.RelationKind;
pub const SpatialSystem = spatial_mod.SpatialSystem;
pub const VM = vm_mod.VM;

pub const ReplResult = struct {
    success: bool,
    output: [160]u8 = undefined,
    output_len: usize = 0,

    pub fn ok(text: []const u8) ReplResult {
        var res = ReplResult{ .success = true };
        const len = @min(text.len, res.output.len);
        @memcpy(res.output[0..len], text[0..len]);
        res.output_len = len;
        return res;
    }

    pub fn err(text: []const u8) ReplResult {
        var res = ReplResult{ .success = false };
        const len = @min(text.len, res.output.len);
        @memcpy(res.output[0..len], text[0..len]);
        res.output_len = len;
        return res;
    }

    pub fn get_text(self: *const ReplResult) []const u8 {
        return self.output[0..self.output_len];
    }
};

/// Live Interactive REPL and Simulation Command Dispatcher (P9-03, D-011).
pub const Repl = struct {
    world: *World,
    spatial: ?*SpatialSystem = null,
    vm: ?*VM = null,

    pub fn init(world: *World, spatial: ?*SpatialSystem, vm: ?*VM) Repl {
        return Repl{
            .world = world,
            .spatial = spatial,
            .vm = vm,
        };
    }

    /// Parses and executes a command string against the live simulation state (P9-03, D-011).
    pub fn execute(self: *Repl, line: []const u8) ReplResult {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0) return ReplResult.ok("");

        var it = std.mem.tokenizeAny(u8, trimmed, " \t");
        const cmd = it.next() orelse return ReplResult.ok("");

        if (std.mem.eql(u8, cmd, "help")) {
            return ReplResult.ok("Commands: remember R(S,O) [ttl] | forget R(S,O) | cue Name [args...] | walk E to W | step | facts | help");
        } else if (std.mem.eql(u8, cmd, "remember")) {
            return self.exec_remember(trimmed[cmd.len..]);
        } else if (std.mem.eql(u8, cmd, "forget")) {
            return self.exec_forget(trimmed[cmd.len..]);
        } else if (std.mem.eql(u8, cmd, "cue")) {
            return self.exec_cue(&it);
        } else if (std.mem.eql(u8, cmd, "walk")) {
            return self.exec_walk(&it);
        } else if (std.mem.eql(u8, cmd, "step")) {
            if (self.vm) |v| {
                v.step_tick() catch return ReplResult.err("Error stepping tick");
                var buf: [64]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "Stepped simulation to Tick {d}", .{self.world.current_tick}) catch "Stepped";
                return ReplResult.ok(msg);
            } else {
                _ = self.world.step_tick();
                var buf: [64]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "Stepped clock to Tick {d}", .{self.world.current_tick}) catch "Stepped";
                return ReplResult.ok(msg);
            }
        } else if (std.mem.eql(u8, cmd, "facts")) {
            var buf: [160]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "Active facts: {d} rows (Tick {d})", .{ self.world.fact_count(), self.world.current_tick }) catch "Facts";
            return ReplResult.ok(msg);
        } else {
            var buf: [96]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "Unknown command '{s}'. Type 'help' for commands.", .{cmd}) catch "Unknown command";
            return ReplResult.err(msg);
        }
    }

    fn exec_remember(self: *Repl, rest: []const u8) ReplResult {
        const trimmed = std.mem.trim(u8, rest, " \t");
        const open_paren = std.mem.indexOfScalar(u8, trimmed, '(') orelse
            return ReplResult.err("Syntax: remember Relation(Subject, Object) [ttl]");
        const close_paren = std.mem.indexOfScalar(u8, trimmed, ')') orelse
            return ReplResult.err("Syntax: remember Relation(Subject, Object) [ttl]");

        if (close_paren <= open_paren) return ReplResult.err("Mismatched parentheses");

        const rel_name = std.mem.trim(u8, trimmed[0..open_paren], " \t");
        const args_str = trimmed[open_paren + 1 .. close_paren];
        const after_paren = std.mem.trim(u8, trimmed[close_paren + 1 ..], " \t");

        var ttl: u64 = 0;
        if (after_paren.len > 0) {
            ttl = std.fmt.parseInt(u64, after_paren, 10) catch 0;
        }

        var arg_it = std.mem.tokenizeAny(u8, args_str, ", \t");
        const subj_name = arg_it.next() orelse return ReplResult.err("Missing subject entity");
        const obj_name = arg_it.next() orelse return ReplResult.err("Missing object or value");

        const subj = self.world.intern_entity(subj_name) catch return ReplResult.err("Out of memory interning subject");
        const rel = self.world.intern_relation(rel_name, .set) catch return ReplResult.err("Out of memory interning relation");

        var obj_val: u32 = 0;
        if (std.fmt.parseInt(u32, obj_name, 10)) |num| {
            obj_val = num;
        } else |_| {
            const obj_ent = self.world.intern_entity(obj_name) catch return ReplResult.err("Out of memory interning object");
            obj_val = obj_ent.to_int();
        }

        self.world.remember(subj, rel, obj_val, ttl) catch return ReplResult.err("Failed to record fact");

        var buf: [160]u8 = undefined;
        const msg = if (ttl > 0)
            std.fmt.bufPrint(&buf, "Remembered {s}({s}, {s}) for {d} ticks", .{ rel_name, subj_name, obj_name, ttl }) catch "Remembered"
        else
            std.fmt.bufPrint(&buf, "Remembered {s}({s}, {s})", .{ rel_name, subj_name, obj_name }) catch "Remembered";
        return ReplResult.ok(msg);
    }

    fn exec_forget(self: *Repl, rest: []const u8) ReplResult {
        const trimmed = std.mem.trim(u8, rest, " \t");
        const open_paren = std.mem.indexOfScalar(u8, trimmed, '(') orelse
            return ReplResult.err("Syntax: forget Relation(Subject, Object)");
        const close_paren = std.mem.indexOfScalar(u8, trimmed, ')') orelse
            return ReplResult.err("Syntax: forget Relation(Subject, Object)");

        const rel_name = std.mem.trim(u8, trimmed[0..open_paren], " \t");
        const args_str = trimmed[open_paren + 1 .. close_paren];

        var arg_it = std.mem.tokenizeAny(u8, args_str, ", \t");
        const subj_name = arg_it.next() orelse return ReplResult.err("Missing subject entity");
        const obj_name = arg_it.next();

        const subj = self.world.lookup_entity(subj_name) orelse return ReplResult.err("Entity not found");
        const rel = self.world.lookup_relation(rel_name) orelse return ReplResult.err("Relation not found");

        var obj_val: ?u32 = null;
        if (obj_name) |oname| {
            if (!std.mem.eql(u8, oname, "_")) {
                if (std.fmt.parseInt(u32, oname, 10)) |num| {
                    obj_val = num;
                } else |_| {
                    if (self.world.lookup_entity(oname)) |oe| {
                        obj_val = oe.to_int();
                    }
                }
            }
        }

        const removed = self.world.forget(subj, rel, obj_val);
        var buf: [96]u8 = undefined;
        if (removed) {
            const msg = std.fmt.bufPrint(&buf, "Forgot fact {s}({s}, ...)", .{ rel_name, subj_name }) catch "Forgot";
            return ReplResult.ok(msg);
        } else {
            return ReplResult.err("No matching fact found to forget");
        }
    }

    fn exec_cue(self: *Repl, it: *std.mem.TokenIterator(u8, .any)) ReplResult {
        const cue_name = it.next() orelse return ReplResult.err("Syntax: cue <CueName> [arg1] [arg2]");
        const v = self.vm orelse return ReplResult.err("VM not available for cue dispatch");

        const cue_ent = self.world.intern_entity(cue_name) catch return ReplResult.err("Out of memory interning cue");
        var cue = vm_mod.EmittedCue{
            .cue_id = @truncate(cue_ent.to_int()),
            .args = [_]u32{0} ** 4,
            .arg_count = 0,
        };

        while (it.next()) |arg_str| {
            if (cue.arg_count >= 4) break;
            if (std.fmt.parseInt(u32, arg_str, 10)) |num| {
                cue.args[cue.arg_count] = num;
            } else |_| {
                const arg_ent = self.world.intern_entity(arg_str) catch return ReplResult.err("Out of memory interning cue argument");
                cue.args[cue.arg_count] = arg_ent.to_int();
            }
            cue.arg_count += 1;
        }

        v.emitted_cues.append(cue) catch return ReplResult.err("Failed to append cue");

        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Emitted cue '{s}' (id: {d}, args: {d})", .{ cue_name, cue.cue_id, cue.arg_count }) catch "Emitted cue";
        return ReplResult.ok(msg);
    }

    fn exec_walk(self: *Repl, it: *std.mem.TokenIterator(u8, .any)) ReplResult {
        const ent_name = it.next() orelse return ReplResult.err("Syntax: walk <Entity> to <Waypoint>");
        const to_kw = it.next() orelse return ReplResult.err("Syntax: walk <Entity> to <Waypoint>");
        if (!std.mem.eql(u8, to_kw, "to")) return ReplResult.err("Syntax: walk <Entity> to <Waypoint>");
        const wp_name = it.next() orelse return ReplResult.err("Syntax: walk <Entity> to <Waypoint>");

        const sp = self.spatial orelse return ReplResult.err("Spatial system not available");
        const ent = self.world.lookup_entity(ent_name) orelse return ReplResult.err("Entity not found");

        var target_wp_id: ?u16 = null;
        for (sp.graph.waypoints.items) |wp| {
            if (std.mem.eql(u8, wp.name, wp_name)) {
                target_wp_id = wp.id;
                break;
            }
        }

        const wp_id = target_wp_id orelse return ReplResult.err("Waypoint not found");
        _ = sp.walk_to(ent, wp_id) catch return ReplResult.err("Pathfinding failed to waypoint");

        var buf: [96]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Directed {s} to walk to {s}", .{ ent_name, wp_name }) catch "Directed";
        return ReplResult.ok(msg);
    }
};

test "P9-03: repl command execution and simulation injection" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    var repl = Repl.init(&world, null, null);

    // 1. Help
    const res_help = repl.execute("help");
    try testing.expect(res_help.success);
    try testing.expect(std.mem.indexOf(u8, res_help.get_text(), "remember") != null);

    // 2. Remember fact
    const res_rem = repl.execute("remember Carries(Cat, Cheese)");
    try testing.expect(res_rem.success);
    const cat = world.lookup_entity("Cat").?;
    const carries = world.lookup_relation("Carries").?;
    const cheese = world.lookup_entity("Cheese").?;
    try testing.expect(world.has_fact(cat, carries, cheese.to_int()));

    // 3. Forget fact
    const res_fgt = repl.execute("forget Carries(Cat, Cheese)");
    try testing.expect(res_fgt.success);
    try testing.expect(!world.has_fact(cat, carries, cheese.to_int()));

    // 4. Remember with TTL
    const res_ttl = repl.execute("remember CharmedBy(Guard, Bard) 15");
    try testing.expect(res_ttl.success);
    const guard = world.lookup_entity("Guard").?;
    const bard = world.lookup_entity("Bard").?;
    const charmed = world.lookup_relation("CharmedBy").?;
    try testing.expect(world.has_fact(guard, charmed, bard.to_int()));

    // 5. Cue dispatch via VM
    const bytecode_mod = @import("bytecode.zig");
    var chunk = bytecode_mod.BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();
    var vm = VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();
    var repl_vm = Repl.init(&world, null, &vm);

    const res_cue = repl_vm.execute("cue PlayLute Bard Guard");
    try testing.expect(res_cue.success);
    try testing.expectEqual(@as(usize, 1), vm.emitted_cues.items.len);
    try testing.expectEqual(@as(u8, 2), vm.emitted_cues.items[0].arg_count);

    // 6. Unknown command
    const res_bad = repl.execute("cast_spell fireball");
    try testing.expect(!res_bad.success);
}
