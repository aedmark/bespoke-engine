const std = @import("std");
const world_mod = @import("world.zig");
const spatial_mod = @import("spatial.zig");
const bytecode_mod = @import("bytecode.zig");
const codegen_mod = @import("compiler/codegen.zig");
const parser_mod = @import("compiler/parser.zig");
const draft_mod = @import("draft.zig");

const World = world_mod.World;
const EntityId = world_mod.EntityId;
const RelationKind = world_mod.RelationKind;
const RelationType = world_mod.RelationType;
const PatternClause = world_mod.PatternClause;
const PatternTerm = world_mod.PatternTerm;
const SpatialSystem = spatial_mod.SpatialSystem;
const BytecodeChunk = bytecode_mod.BytecodeChunk;
const CompiledProgram = codegen_mod.CompiledProgram;
const CompiledWhenRule = codegen_mod.CompiledWhenRule;
const WhenEdge = parser_mod.WhenEdge;

/// 4-byte magic for compiled BeSpoke binary asset packages (P15-02, D-018).
pub const PACKAGE_MAGIC = [4]u8{ 'B', 'S', 'P', 'B' }; // BeSpoke Binary
/// Version 2 appends the draft note table to the payload tail (P22-01, D-029). Version 1
/// packages predate drafts and still load, with an empty draft table.
/// Version 3 adds the arrival edge (byte 3) to reactive rules (P32-18, D-036); the layout is
/// unchanged, so versions 1 and 2 still load.
pub const PACKAGE_VERSION: u32 = 3;
const MIN_PACKAGE_VERSION: u32 = 1;

pub const PackageHeader = extern struct {
    magic: [4]u8 = PACKAGE_MAGIC,
    version: u32 = PACKAGE_VERSION,
    crc32: u32 = 0,
    payload_size: u32 = 0,
    entity_count: u32 = 0,
    relation_count: u32 = 0,
    waypoint_count: u32 = 0,
    edge_count: u32 = 0,
    hotspot_count: u32 = 0,
    bytecode_len: u32 = 0,
    routine_count: u32 = 0,
    when_rule_count: u32 = 0,
    cue_count: u32 = 0,
    reactive_rule_count: u32 = 0,
    initial_entry: i64 = -1,
};

fn write_str(writer: anytype, str: []const u8) !void {
    try writer.writeInt(u16, @intCast(str.len), .little);
    try writer.writeAll(str);
}

fn read_str(allocator: std.mem.Allocator, reader: anytype) ![]const u8 {
    const len = try reader.readInt(u16, .little);
    const buf = try allocator.alloc(u8, len);
    try reader.readNoEof(buf);
    return buf;
}

/// Serializes a CompiledProgram and associated spatial topology to a binary package stream (P15-02, D-018).
pub fn save_package(
    allocator: std.mem.Allocator,
    writer: anytype,
    compiled: *const CompiledProgram,
    world: *const World,
    spatial: ?*const SpatialSystem,
) !void {
    var payload = std.ArrayList(u8).init(allocator);
    defer payload.deinit();
    const pw = payload.writer();

    // 1. Entity table
    const entity_count: u32 = @intCast(world.entity_names.items.len);
    for (world.entity_names.items) |name| {
        try write_str(pw, name);
    }

    // 2. Relation table
    const relation_count: u32 = @intCast(world.relation_meta.items.len);
    for (world.relation_meta.items) |rel| {
        try write_str(pw, rel.name);
        try pw.writeByte(if (rel.rel_type == .property) 1 else 0);
    }

    // 3. Spatial waypoints and edges
    var waypoint_count: u32 = 0;
    var edge_count: u32 = 0;
    var hotspot_count: u32 = 0;

    if (spatial) |sp| {
        waypoint_count = @intCast(sp.graph.waypoints.items.len);
        for (sp.graph.waypoints.items) |wp| {
            try pw.writeInt(u32, wp.room.to_int(), .little);
            try pw.writeInt(i32, wp.pos.x, .little);
            try pw.writeInt(i32, wp.pos.y, .little);
            try write_str(pw, wp.name);
        }

        edge_count = @intCast(sp.graph.edges.items.len);
        for (sp.graph.edges.items) |edge| {
            try pw.writeInt(u16, edge.from, .little);
            try pw.writeInt(u16, edge.to, .little);
            try pw.writeInt(u32, edge.cost, .little);
        }

        hotspot_count = @intCast(sp.hotspots.items.len);
        for (sp.hotspots.items) |hs| {
            try pw.writeInt(u32, hs.entity.to_int(), .little);
            try pw.writeInt(u32, hs.room.to_int(), .little);
            try pw.writeInt(i32, hs.pos.x, .little);
            try pw.writeInt(i32, hs.pos.y, .little);
            try pw.writeInt(u32, hs.radius, .little);
            try write_str(pw, hs.name);
            try write_str(pw, hs.examine_text);
        }
    }

    // 4. Bytecode instructions
    const bytecode_len: u32 = @intCast(compiled.chunk.code.items.len);
    try pw.writeAll(compiled.chunk.code.items);

    // 5. Routine entries
    const routine_count: u32 = @intCast(compiled.routine_entries.count());
    var r_it = compiled.routine_entries.iterator();
    while (r_it.next()) |entry| {
        try write_str(pw, entry.key_ptr.*);
        try pw.writeInt(u32, @intCast(entry.value_ptr.*), .little);
        const actor_name = compiled.routine_entities.get(entry.key_ptr.*) orelse "";
        try write_str(pw, actor_name);
    }

    // 6. When rule entries
    const when_rule_count: u32 = @intCast(compiled.when_rule_entries.items.len);
    for (compiled.when_rule_entries.items) |pc| {
        try pw.writeInt(u32, @intCast(pc), .little);
    }

    // 7. Cue handler entries
    const cue_count: u32 = @intCast(compiled.cue_handler_entries.count());
    var c_it = compiled.cue_handler_entries.iterator();
    while (c_it.next()) |entry| {
        try write_str(pw, entry.key_ptr.*);
        try pw.writeInt(u32, @intCast(entry.value_ptr.*), .little);
    }

    // 8. Reactive simulation rules
    const reactive_rule_count: u32 = @intCast(compiled.reactive_rules.items.len);
    for (compiled.reactive_rules.items) |r| {
        try pw.writeInt(u32, r.target_entity.to_int(), .little);
        try pw.writeInt(u16, r.priority, .little);
        try pw.writeInt(u32, @intCast(r.handler_pc), .little);
        try pw.writeByte(@intFromEnum(r.edge));
        try pw.writeInt(u16, @intCast(r.clauses.len), .little);
        for (r.clauses) |clause| {
            try pw.writeInt(u16, clause.relation.to_int(), .little);
            // Subject PatternTerm
            switch (clause.subject) {
                .wildcard => {
                    try pw.writeByte(0);
                    try pw.writeInt(u32, 0, .little);
                },
                .constant => |val| {
                    try pw.writeByte(1);
                    try pw.writeInt(u32, val, .little);
                },
                .variable => |v| {
                    try pw.writeByte(2);
                    try pw.writeInt(u32, @as(u32, v), .little);
                },
            }
            // Object PatternTerm
            switch (clause.object) {
                .wildcard => {
                    try pw.writeByte(0);
                    try pw.writeInt(u32, 0, .little);
                },
                .constant => |val| {
                    try pw.writeByte(1);
                    try pw.writeInt(u32, val, .little);
                },
                .variable => |v| {
                    try pw.writeByte(2);
                    try pw.writeInt(u32, @as(u32, v), .little);
                },
            }
        }
    }

    // 9. Draft note table (version 2+)
    try pw.writeInt(u32, @intCast(compiled.drafts.items.len), .little);
    for (compiled.drafts.items) |d| {
        try pw.writeInt(u32, d.entity.to_int(), .little);
        for (d.notes) |n| try pw.writeByte(@intFromEnum(n));
        try pw.writeByte(if (d.inverse != null) 1 else 0);
        try pw.writeInt(u32, if (d.inverse) |inv| inv.to_int() else 0, .little);
    }

    // Compute CRC32 checksum over the payload
    const crc = std.hash.Crc32.hash(payload.items);

    var header = PackageHeader{
        .magic = PACKAGE_MAGIC,
        .version = PACKAGE_VERSION,
        .crc32 = crc,
        .payload_size = @intCast(payload.items.len),
        .entity_count = entity_count,
        .relation_count = relation_count,
        .waypoint_count = waypoint_count,
        .edge_count = edge_count,
        .hotspot_count = hotspot_count,
        .bytecode_len = bytecode_len,
        .routine_count = routine_count,
        .when_rule_count = when_rule_count,
        .cue_count = cue_count,
        .reactive_rule_count = reactive_rule_count,
        .initial_entry = if (compiled.initial_entry) |ie| @intCast(ie) else -1,
    };

    // Write header followed by payload
    try writer.writeAll(std.mem.asBytes(&header));
    try writer.writeAll(payload.items);
}

/// Loads and validates a binary package stream into a World, SpatialSystem, and CompiledProgram (P15-02, D-018).
pub fn load_package(
    allocator: std.mem.Allocator,
    reader: anytype,
    world: *World,
    spatial: ?*SpatialSystem,
) !CompiledProgram {
    var header: PackageHeader = undefined;
    const bytes_read = try reader.readAll(std.mem.asBytes(&header));
    if (bytes_read < @sizeOf(PackageHeader)) {
        return error.EndOfStream;
    }

    if (!std.mem.eql(u8, &header.magic, &PACKAGE_MAGIC)) {
        return error.InvalidPackageMagic;
    }

    if (header.version < MIN_PACKAGE_VERSION or header.version > PACKAGE_VERSION) {
        return error.UnsupportedPackageVersion;
    }

    if (header.payload_size > 64 * 1024 * 1024) {
        return error.PackagePayloadTooLarge;
    }

    // Read full payload
    const payload = try allocator.alloc(u8, header.payload_size);
    defer allocator.free(payload);
    try reader.readNoEof(payload);

    // Verify CRC32 checksum
    const computed_crc = std.hash.Crc32.hash(payload);
    if (computed_crc != header.crc32) {
        return error.ChecksumMismatch;
    }

    var stream = std.io.fixedBufferStream(payload);
    const pr = stream.reader();

    // 1. Entities
    var e_idx: u32 = 0;
    while (e_idx < header.entity_count) : (e_idx += 1) {
        const name = try read_str(allocator, pr);
        defer allocator.free(name);
        _ = try world.intern_entity(name);
    }

    // 2. Relations
    var r_idx: u32 = 0;
    while (r_idx < header.relation_count) : (r_idx += 1) {
        const name = try read_str(allocator, pr);
        defer allocator.free(name);
        const is_prop = (try pr.readByte()) == 1;
        _ = try world.intern_relation(name, if (is_prop) .property else .set);
    }

    // 3. Spatial waypoints, edges, hotspots
    var wp_idx: u32 = 0;
    while (wp_idx < header.waypoint_count) : (wp_idx += 1) {
        const room_int = try pr.readInt(u32, .little);
        const x = try pr.readInt(i32, .little);
        const y = try pr.readInt(i32, .little);
        const name = try read_str(allocator, pr);
        defer allocator.free(name);

        if (spatial) |sp| {
            _ = try sp.graph.add_waypoint(EntityId.from_int(room_int), x, y, name);
        }
    }

    var edge_idx: u32 = 0;
    while (edge_idx < header.edge_count) : (edge_idx += 1) {
        const from = try pr.readInt(u16, .little);
        const to = try pr.readInt(u16, .little);
        const cost = try pr.readInt(u32, .little);

        if (spatial) |sp| {
            try sp.graph.connect(from, to, cost);
        }
    }

    var hs_idx: u32 = 0;
    while (hs_idx < header.hotspot_count) : (hs_idx += 1) {
        const ent_int = try pr.readInt(u32, .little);
        const room_int = try pr.readInt(u32, .little);
        const x = try pr.readInt(i32, .little);
        const y = try pr.readInt(i32, .little);
        const radius = try pr.readInt(u32, .little);
        const name = try read_str(allocator, pr);
        defer allocator.free(name);
        const desc = try read_str(allocator, pr);
        defer allocator.free(desc);

        if (spatial) |sp| {
            try sp.add_hotspot(
                EntityId.from_int(ent_int),
                EntityId.from_int(room_int),
                .{ .x = x, .y = y },
                radius,
                name,
                desc,
            );
        }
    }

    // 4. Bytecode instructions
    var chunk = BytecodeChunk.init(allocator);
    errdefer chunk.deinit();
    if (header.bytecode_len > 0) {
        const code_slice = try allocator.alloc(u8, header.bytecode_len);
        defer allocator.free(code_slice);
        try pr.readNoEof(code_slice);
        try chunk.code.appendSlice(code_slice);
    }

    // 5. Routine entries
    var routine_entries = std.StringHashMap(usize).init(allocator);
    errdefer routine_entries.deinit();
    var routine_entities = std.StringHashMap([]const u8).init(allocator);
    errdefer routine_entities.deinit();
    var allocated_cue_keys = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (allocated_cue_keys.items) |k| allocator.free(k);
        allocated_cue_keys.deinit();
    }

    var rout_idx: u32 = 0;
    while (rout_idx < header.routine_count) : (rout_idx += 1) {
        const rname = try read_str(allocator, pr);
        try allocated_cue_keys.append(rname);
        const pc = try pr.readInt(u32, .little);
        const actor = try read_str(allocator, pr);
        try allocated_cue_keys.append(actor);
        try routine_entries.put(rname, pc);
        try routine_entities.put(rname, actor);
    }

    // 6. When rule entries
    var when_rule_entries = std.ArrayList(usize).init(allocator);
    errdefer when_rule_entries.deinit();
    var wr_idx: u32 = 0;
    while (wr_idx < header.when_rule_count) : (wr_idx += 1) {
        const pc = try pr.readInt(u32, .little);
        try when_rule_entries.append(pc);
    }

    // 7. Cue handler entries
    var cue_handler_entries = std.StringHashMap(usize).init(allocator);
    errdefer cue_handler_entries.deinit();
    var cue_idx: u32 = 0;
    while (cue_idx < header.cue_count) : (cue_idx += 1) {
        const sig = try read_str(allocator, pr);
        try allocated_cue_keys.append(sig);
        const pc = try pr.readInt(u32, .little);
        try cue_handler_entries.put(sig, pc);
    }

    // 8. Reactive simulation rules
    var reactive_rules = std.ArrayList(CompiledWhenRule).init(allocator);
    errdefer {
        for (reactive_rules.items) |r| allocator.free(r.clauses);
        reactive_rules.deinit();
    }

    var rr_idx: u32 = 0;
    while (rr_idx < header.reactive_rule_count) : (rr_idx += 1) {
        const tent = try pr.readInt(u32, .little);
        const priority = try pr.readInt(u16, .little);
        const handler_pc = try pr.readInt(u32, .little);
        const edge_byte = try pr.readByte();
        const edge: WhenEdge = switch (edge_byte) {
            0 => .rising,
            1 => .falling,
            2 => .on_expire,
            3 => if (header.version >= 3) .on_arrive else return error.InvalidWhenEdge,
            else => return error.InvalidWhenEdge,
        };
        const clause_count = try pr.readInt(u16, .little);
        const clauses = try allocator.alloc(PatternClause, clause_count);
        for (clauses) |*cl| {
            const rel_kind = try pr.readInt(u16, .little);
            cl.relation = RelationKind.from_int(rel_kind);

            // Subject
            const s_tag = try pr.readByte();
            const s_val = try pr.readInt(u32, .little);
            cl.subject = switch (s_tag) {
                0 => PatternTerm{ .wildcard = {} },
                1 => PatternTerm{ .constant = s_val },
                2 => PatternTerm{ .variable = @intCast(s_val) },
                else => return error.InvalidPatternTermTag,
            };

            // Object
            const o_tag = try pr.readByte();
            const o_val = try pr.readInt(u32, .little);
            cl.object = switch (o_tag) {
                0 => PatternTerm{ .wildcard = {} },
                1 => PatternTerm{ .constant = o_val },
                2 => PatternTerm{ .variable = @intCast(o_val) },
                else => return error.InvalidPatternTermTag,
            };
        }

        try reactive_rules.append(.{
            .clauses = clauses,
            .target_entity = EntityId.from_int(tent),
            .priority = priority,
            .handler_pc = handler_pc,
            .edge = edge,
        });
    }

    // 9. Draft note table (version 2+). Untrusted input: note bytes and entity ids are checked
    // against the note range and the entity table loaded above before entering the program.
    var drafts = std.ArrayList(draft_mod.CompiledDraft).init(allocator);
    errdefer drafts.deinit();
    if (header.version >= 2) {
        const draft_count = try pr.readInt(u32, .little);
        const entity_limit = world.entity_names.items.len;
        var di: u32 = 0;
        while (di < draft_count) : (di += 1) {
            const ent_raw = try pr.readInt(u32, .little);
            var notes: draft_mod.Notes = undefined;
            for (&notes) |*n| {
                n.* = draft_mod.Note.from_int(try pr.readByte()) orelse return error.InvalidDraftNote;
            }
            const has_inverse = try pr.readByte();
            const inv_raw = try pr.readInt(u32, .little);
            if (ent_raw == 0 or ent_raw > entity_limit) return error.InvalidDraftEntity;
            if (has_inverse > 1) return error.InvalidDraftEntity;
            if (has_inverse == 1 and (inv_raw == 0 or inv_raw > entity_limit)) return error.InvalidDraftEntity;
            try drafts.append(.{
                .entity = EntityId.from_int(ent_raw),
                .notes = notes,
                .inverse = if (has_inverse == 1) EntityId.from_int(inv_raw) else null,
            });
        }
    }

    return CompiledProgram{
        .drafts = drafts,
        .chunk = chunk,
        .routine_entries = routine_entries,
        .routine_entities = routine_entities,
        .when_rule_entries = when_rule_entries,
        .cue_handler_entries = cue_handler_entries,
        .allocated_cue_keys = allocated_cue_keys,
        .reactive_rules = reactive_rules,
        .initial_entry = if (header.initial_entry >= 0) @intCast(header.initial_entry) else null,
    };
}

/// Saves a compiled program package directly to a file on disk (P15-02).
pub fn save_package_file(
    allocator: std.mem.Allocator,
    path: []const u8,
    compiled: *const CompiledProgram,
    world: *const World,
    spatial: ?*const SpatialSystem,
) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    var buf_writer = std.io.bufferedWriter(file.writer());
    try save_package(allocator, buf_writer.writer(), compiled, world, spatial);
    try buf_writer.flush();
}

/// Loads a compiled program package directly from a file on disk (P15-02).
pub fn load_package_file(
    allocator: std.mem.Allocator,
    path: []const u8,
    world: *World,
    spatial: ?*SpatialSystem,
) !CompiledProgram {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    var buf_reader = std.io.bufferedReader(file.reader());
    return try load_package(allocator, buf_reader.reader(), world, spatial);
}

// =========================================================================
// Unit Tests (P15-02)
// =========================================================================

test "P15-02: package serializes and deserializes CompiledProgram with CRC32 integrity" {
    const testing = std.testing;
    const compiler = @import("compiler.zig");
    const vm_mod = @import("vm.zig");

    const script =
        \\scene Tavern:
        \\  cast: Guard, Bard, Cat
        \\  props: Fireplace, BarCounter
        \\  marks: Hearth, Bar, Cellar
        \\
        \\relation Carries(holder, item)
        \\relation CharmedBy(listener, musician)
        \\
        \\entity Cheese
        \\remember Carries(Guard, Cheese)
        \\
        \\routine Patrol(Guard):
        \\  walk Guard to Cellar
        \\  wait 5 ticks
        \\  walk Guard to Hearth
        \\
        \\when CharmedBy(Guard, Bard):
        \\  interrupt Guard with:
        \\    wait 4 ticks
    ;

    var world1 = try World.init(testing.allocator, 1024 * 1024);
    defer world1.deinit();
    var spatial1 = SpatialSystem.init(testing.allocator);
    defer spatial1.deinit();

    var compiled1 = try compiler.compile_source(testing.allocator, &world1, &spatial1, script);
    defer compiled1.deinit();

    // Serialize to in-memory buffer
    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();

    try save_package(testing.allocator, buffer.writer(), &compiled1, &world1, &spatial1);
    try testing.expect(buffer.items.len > @sizeOf(PackageHeader));

    // Verify header magic and version
    const header_slice = buffer.items[0..@sizeOf(PackageHeader)];
    const header: *const PackageHeader = @ptrCast(@alignCast(header_slice.ptr));
    try testing.expectEqualStrings("BSPB", &header.magic);
    try testing.expectEqual(PACKAGE_VERSION, header.version);
    try testing.expect(header.crc32 != 0);

    // Deserialize into fresh World and SpatialSystem
    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();
    var spatial2 = SpatialSystem.init(testing.allocator);
    defer spatial2.deinit();

    var stream = std.io.fixedBufferStream(buffer.items);
    var compiled2 = try load_package(testing.allocator, stream.reader(), &world2, &spatial2);
    defer compiled2.deinit();

    // Verify restored entities and relations
    try testing.expect(world2.lookup_entity("Guard") != null);
    try testing.expect(world2.lookup_entity("Bard") != null);
    try testing.expect(world2.lookup_entity("Cheese") != null);
    try testing.expect(world2.lookup_relation("Carries") != null);

    // Verify restored spatial waypoints and hotspots
    try testing.expectEqual(@as(usize, 3), spatial2.graph.waypoints.items.len);
    try testing.expectEqual(@as(usize, 2), spatial2.hotspots.items.len);

    // Verify restored routine entry and metadata
    try testing.expect(compiled2.routine_entries.contains("Patrol"));
    try testing.expectEqualStrings("Guard", compiled2.routine_entities.get("Patrol").?);

    // Verify restored reactive rules
    try testing.expectEqual(@as(usize, 1), compiled2.reactive_rules.items.len);

    // Execute in VM to verify functional bytecode execution
    var vm = vm_mod.VM.init(testing.allocator, &world2, &compiled2.chunk);
    defer vm.deinit();
    vm.spatial = &spatial2;
    try vm.load_compiled_rules(&compiled2);

    const guard_id = world2.lookup_entity("Guard").?;
    const patrol_pc = compiled2.routine_entries.get("Patrol").?;
    _ = try vm.spawn_routine(guard_id, patrol_pc);
    try vm.step_tick();
    try testing.expect(vm.fibers.items.len > 0);
}

test "P15-02: package loader rejects invalid magic header" {
    const testing = std.testing;

    var header = PackageHeader{
        .magic = [_]u8{ 'X', 'Y', 'Z', 'W' },
        .version = 1,
        .payload_size = 0,
        .crc32 = 0,
    };
    var stream = std.io.fixedBufferStream(std.mem.asBytes(&header));

    var dummy_world = try World.init(testing.allocator, 1024 * 1024);
    defer dummy_world.deinit();

    const res = load_package(testing.allocator, stream.reader(), &dummy_world, null);
    try testing.expectError(error.InvalidPackageMagic, res);
}

test "P15-02: package loader rejects corrupted payload with checksum mismatch" {
    const testing = std.testing;
    const compiler = @import("compiler.zig");

    const script = "entity Guard\nroutine Patrol(Guard):\n  wait 2 ticks\n";
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    var compiled = try compiler.compile_source(testing.allocator, &world, null, script);
    defer compiled.deinit();

    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();

    try save_package(testing.allocator, buffer.writer(), &compiled, &world, null);

    // Corrupt one byte in the payload
    buffer.items[buffer.items.len - 1] ^= 0xFF;

    var stream = std.io.fixedBufferStream(buffer.items);
    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();

    const res = load_package(testing.allocator, stream.reader(), &world2, null);
    try testing.expectError(error.ChecksumMismatch, res);
}

test "P15-02: package loader rejects unsupported version" {
    const testing = std.testing;

    var header = PackageHeader{
        .magic = PACKAGE_MAGIC,
        .version = 99,
        .payload_size = 0,
        .crc32 = 0,
    };
    var stream = std.io.fixedBufferStream(std.mem.asBytes(&header));

    var dummy_world = try World.init(testing.allocator, 1024 * 1024);
    defer dummy_world.deinit();

    const res = load_package(testing.allocator, stream.reader(), &dummy_world, null);
    try testing.expectError(error.UnsupportedPackageVersion, res);
}

test "P15-02: package file save and load roundtrip" {
    const testing = std.testing;
    const compiler = @import("compiler.zig");

    const script =
        \\entity Cat, Cheese
        \\relation Carries(holder, item)
        \\remember Carries(Cat, Cheese)
        \\routine Prowl(Cat):
        \\  wait 3 ticks
    ;

    var world1 = try World.init(testing.allocator, 1024 * 1024);
    defer world1.deinit();

    var compiled1 = try compiler.compile_source(testing.allocator, &world1, null, script);
    defer compiled1.deinit();

    const tmp_path = "/tmp/test_scenario.bspk";
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    try save_package_file(testing.allocator, tmp_path, &compiled1, &world1, null);

    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();

    var compiled2 = try load_package_file(testing.allocator, tmp_path, &world2, null);
    defer compiled2.deinit();

    try testing.expect(world2.lookup_entity("Cat") != null);
    try testing.expect(world2.lookup_entity("Cheese") != null);
    try testing.expect(compiled2.routine_entries.contains("Prowl"));
    try testing.expectEqualStrings("Cat", compiled2.routine_entities.get("Prowl").?);
}

/// Re-seals a hand-edited test package: recomputes payload size and CRC32 in the header.
fn reseal_for_test(buf: []u8, version: u32) void {
    const header: *PackageHeader = @ptrCast(@alignCast(buf[0..@sizeOf(PackageHeader)].ptr));
    const payload = buf[@sizeOf(PackageHeader)..];
    header.version = version;
    header.payload_size = @intCast(payload.len);
    header.crc32 = std.hash.Crc32.hash(payload);
}

test "P22-01: package round-trips the draft table including declared reverses" {
    const testing = std.testing;
    const compiler = @import("compiler.zig");
    const script =
        \\entity Player
        \\draft Kindle(C, E, G, E) reverse Douse
        \\draft Mend(D, A, A, D)
    ;
    var world1 = try World.init(testing.allocator, 1024 * 1024);
    defer world1.deinit();
    var compiled1 = try compiler.compile_source(testing.allocator, &world1, null, script);
    defer compiled1.deinit();

    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();
    try save_package(testing.allocator, buffer.writer(), &compiled1, &world1, null);

    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();
    var stream = std.io.fixedBufferStream(buffer.items);
    var compiled2 = try load_package(testing.allocator, stream.reader(), &world2, null);
    defer compiled2.deinit();

    try testing.expectEqual(@as(usize, 3), compiled2.drafts.items.len);
    const douse = compiled2.find_draft_by_notes(.{ .E, .G, .E, .C }).?;
    try testing.expectEqualStrings("Douse", world2.get_entity_name(douse.entity).?);
    try testing.expectEqualStrings("Kindle", world2.get_entity_name(douse.inverse.?).?);
    try testing.expect(compiled2.find_draft_by_notes(.{ .D, .A, .A, .D }).?.inverse == null);
}

test "P22-01: package loader rejects out-of-range draft notes and loads version 1 packages" {
    const testing = std.testing;
    const compiler = @import("compiler.zig");
    const script = "entity Player\ndraft Mend(D, A, A, D)\n";
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try compiler.compile_source(testing.allocator, &world, null, script);
    defer compiled.deinit();

    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();
    try save_package(testing.allocator, buffer.writer(), &compiled, &world, null);

    // Draft tail: count u32, then entity u32, 4 note bytes, inverse flag u8, inverse u32.
    const tail_len = 4 + 4 + 4 + 1 + 4;
    const first_note = buffer.items.len - tail_len + 8;
    {
        const bad = try testing.allocator.dupe(u8, buffer.items);
        defer testing.allocator.free(bad);
        bad[first_note] = 7; // one past B
        reseal_for_test(bad, PACKAGE_VERSION);
        var world2 = try World.init(testing.allocator, 1024 * 1024);
        defer world2.deinit();
        var stream = std.io.fixedBufferStream(bad);
        try testing.expectError(error.InvalidDraftNote, load_package(testing.allocator, stream.reader(), &world2, null));
    }
    {
        // A version 1 package is the same payload without the draft tail.
        const v1 = try testing.allocator.dupe(u8, buffer.items[0 .. buffer.items.len - tail_len]);
        defer testing.allocator.free(v1);
        reseal_for_test(v1, 1);
        var world2 = try World.init(testing.allocator, 1024 * 1024);
        defer world2.deinit();
        var stream = std.io.fixedBufferStream(v1);
        var loaded = try load_package(testing.allocator, stream.reader(), &world2, null);
        defer loaded.deinit();
        try testing.expectEqual(@as(usize, 0), loaded.drafts.items.len);
    }
}

test "P32-18: package round-trips an arrival rule and version 2 rejects its edge" {
    const testing = std.testing;
    const compiler = @import("compiler.zig");
    const script =
        \\scene: Yard
        \\cast: Scout
        \\marks: Well, Gate
        \\
        \\when Scout arrives at Gate:
        \\  remember ReachedGate(Scout, true)
    ;
    var world1 = try World.init(testing.allocator, 1024 * 1024);
    defer world1.deinit();
    var spatial1 = SpatialSystem.init(testing.allocator);
    defer spatial1.deinit();
    var compiled1 = try compiler.compile_source(testing.allocator, &world1, &spatial1, script);
    defer compiled1.deinit();

    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();
    try save_package(testing.allocator, buffer.writer(), &compiled1, &world1, &spatial1);

    {
        var world2 = try World.init(testing.allocator, 1024 * 1024);
        defer world2.deinit();
        var spatial2 = SpatialSystem.init(testing.allocator);
        defer spatial2.deinit();
        var stream = std.io.fixedBufferStream(buffer.items);
        var compiled2 = try load_package(testing.allocator, stream.reader(), &world2, &spatial2);
        defer compiled2.deinit();

        try testing.expectEqual(@as(usize, 1), compiled2.reactive_rules.items.len);
        const rule = compiled2.reactive_rules.items[0];
        try testing.expectEqual(WhenEdge.on_arrive, rule.edge);
        const gate = spatial2.graph.find_waypoint("Gate").?;
        try testing.expectEqual(@as(u32, gate), rule.clauses[0].object.constant);
        try testing.expectEqual(world2.lookup_entity("Scout").?.to_int(), rule.clauses[0].subject.constant);
    }
    {
        // The same payload labelled version 2 must not load: that format has no arrival edge.
        const v2 = try testing.allocator.dupe(u8, buffer.items);
        defer testing.allocator.free(v2);
        reseal_for_test(v2, 2);
        var world2 = try World.init(testing.allocator, 1024 * 1024);
        defer world2.deinit();
        var spatial2 = SpatialSystem.init(testing.allocator);
        defer spatial2.deinit();
        var stream = std.io.fixedBufferStream(v2);
        try testing.expectError(error.InvalidWhenEdge, load_package(testing.allocator, stream.reader(), &world2, &spatial2));
    }
}
