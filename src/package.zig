const std = @import("std");
const world_mod = @import("world.zig");
const spatial_mod = @import("spatial.zig");
const bytecode_mod = @import("bytecode.zig");
const codegen_mod = @import("compiler/codegen.zig");
const parser_mod = @import("compiler/parser.zig");
const draft_mod = @import("draft.zig");
const society_mod = @import("society.zig");
const duel_mod = @import("duel.zig");
const container_mod = @import("container.zig");
const grid_mod = @import("grid.zig");
const agency_mod = @import("agency.zig");

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
/// unchanged, so versions 1 and 2 still load. Version 4 appends script-declared society and
/// duel configuration tables (P32-22, P32-24); versions 1 through 3 load empty tables. Version 5
/// appends degradation profiles (P23-01); versions 1 through 4 load an empty profile table.
/// Version 6 adds per-moving-tick spill volume to each profile (P23-02); version 5 profiles load
/// with spill disabled. Version 7 appends grid overlays with their initial cell layouts
/// (P25-01, D-054); versions 1 through 6 load with no grids. Version 8 adds the `burning` and
/// `smoke` attributes and four automata rates per grid (P25-02, D-055); version 7 grids load
/// with every rule off. Version 9 appends agendas (P33-01, D-056); versions 1 through 8 load
/// with none.
pub const PACKAGE_VERSION: u32 = 9;
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

fn write_text_ref(world: *const World, writer: anytype, value: []const u8) !void {
    const entity = world.lookup_entity(value) orelse return error.UninternedProgramText;
    try writer.writeInt(u32, entity.to_int(), .little);
}

fn read_text_ref(world: *const World, reader: anytype) ![]const u8 {
    const raw = try reader.readInt(u32, .little);
    return world.get_entity_name(EntityId.from_int(raw)) orelse error.InvalidProgramTextRef;
}

fn write_optional_index(writer: anytype, value: ?usize) !void {
    try writer.writeInt(i32, if (value) |v| @intCast(v) else -1, .little);
}

fn write_optional_waypoint(writer: anytype, value: ?spatial_mod.WaypointId) !void {
    try writer.writeInt(i32, if (value) |v| @intCast(v) else -1, .little);
}

fn write_program_declarations(world: *const World, writer: anytype, compiled: *const CompiledProgram) !void {
    try writer.writeInt(u32, @intCast(compiled.societies.items.len), .little);
    for (compiled.societies.items) |decl| {
        const config = decl.config;
        try writer.writeInt(u32, @intCast(config.needs.len), .little);
        for (config.needs) |need| {
            try write_text_ref(world, writer, need.name);
            try writer.writeByte(@intFromEnum(need.worse));
            try writer.writeInt(u32, need.max, .little);
            try writer.writeInt(u32, need.rate, .little);
            try writer.writeInt(u32, need.resting_rate, .little);
            try writer.writeInt(u32, need.seek, .little);
            switch (need.satisfy) {
                .stay => |stay| {
                    try writer.writeByte(0);
                    try writer.writeInt(u16, stay.at, .little);
                    try writer.writeInt(u32, stay.restore, .little);
                    try writer.writeInt(u32, stay.until, .little);
                    try writer.writeByte(@intCast(@intFromEnum(stay.activity)));
                    try writer.writeByte(@intFromBool(stay.unaware));
                    try write_text_ref(world, writer, stay.state);
                    try write_text_ref(world, writer, stay.verb);
                },
                .trade => |trade| {
                    try writer.writeByte(1);
                    try write_optional_index(writer, trade.provider);
                    try writer.writeInt(u32, trade.price, .little);
                    try writer.writeInt(u32, trade.relief, .little);
                    try writer.writeInt(u32, trade.floor, .little);
                    try writer.writeInt(i64, if (trade.critical) |value| @intCast(value) else -1, .little);
                    try writer.writeInt(u32, trade.theft_relief, .little);
                    try writer.writeInt(u32, trade.theft_floor, .little);
                    try write_text_ref(world, writer, trade.item);
                },
            }
        }
        try writer.writeInt(u32, @intCast(config.members.len), .little);
        for (config.members) |member| {
            try writer.writeInt(u32, member.entity.to_int(), .little);
            try writer.writeInt(u32, @intCast(member.needs.len), .little);
            for (member.needs) |need| {
                try writer.writeInt(u32, need.value, .little);
                try writer.writeInt(i64, if (need.rate) |value| @intCast(value) else -1, .little);
                try write_optional_index(writer, need.provider);
            }
            try writer.writeInt(u32, member.gold, .little);
            try writer.writeByte(@intCast(@intFromEnum(member.idle)));
            try writer.writeByte(if (member.routine.activity) |activity| @intCast(@intFromEnum(activity)) else 255);
            try writer.writeInt(u16, @intCast(member.routine.stops.len), .little);
            for (member.routine.stops) |stop| try writer.writeInt(u16, stop, .little);
            try writer.writeInt(u64, member.routine.period, .little);
            try writer.writeByte(@intFromBool(member.routine.work != null));
            if (member.routine.work) |work| {
                try writer.writeInt(u16, work.at, .little);
                try writer.writeInt(u64, work.every, .little);
                try writer.writeInt(u32, work.earn, .little);
                try writer.writeByte(@intFromBool(work.restock));
            }
            try writer.writeByte(@intFromBool(member.merchant != null));
            if (member.merchant) |merchant| {
                try writer.writeInt(u16, merchant.post, .little);
                try writer.writeInt(u32, merchant.goods.to_int(), .little);
            }
            try writer.writeByte(@intFromBool(member.broadcaster));
            try writer.writeInt(u16, @intCast(member.owns.len), .little);
            for (member.owns) |item| try writer.writeInt(u32, item.to_int(), .little);
            try writer.writeInt(u16, @intCast(member.carries.len), .little);
            for (member.carries) |item| try writer.writeInt(u32, item.to_int(), .little);
        }
        try write_optional_index(writer, config.enforcer);
        try write_optional_waypoint(writer, config.holding);
        try writer.writeInt(u16, config.gathering, .little);
        try writer.writeInt(u16, config.flight.to, .little);
        try write_optional_waypoint(writer, config.flight.then);
        try writer.writeInt(u64, config.flight.every, .little);
        try writer.writeInt(i32, config.radii.witness, .little);
        try writer.writeInt(i32, config.radii.culprit, .little);
        try writer.writeInt(i32, config.radii.rumor, .little);
        try writer.writeInt(i32, config.radii.arrest, .little);
        try writer.writeInt(u64, config.witness_grudge_ticks, .little);
        try writer.writeInt(u64, config.rumor_grudge_ticks, .little);
        try writer.writeInt(u16, config.warrant_priority, .little);
        try write_text_ref(world, writer, config.currency_unit);
        const r = config.relations;
        for ([_][]const u8{ r.currency, r.activity, r.tending, r.friend, r.rival, r.grudge, r.owns, r.carries, r.stolen_from, r.crime_scene, r.witnessed, r.knows_rumor, r.warrant_for, r.arrested }) |name| try write_text_ref(world, writer, name);
        try writer.writeInt(u32, @intCast(config.friends.len), .little);
        for (config.friends) |friend| {
            try writer.writeInt(u32, friend.a.to_int(), .little);
            try writer.writeInt(u32, friend.b.to_int(), .little);
        }
    }

    try writer.writeInt(u32, @intCast(compiled.duels.items.len), .little);
    for (compiled.duels.items) |decl| {
        try writer.writeInt(u32, @intCast(decl.config.pairs.len), .little);
        for (decl.config.pairs) |pair| {
            try write_text_ref(world, writer, pair.name);
            try write_text_ref(world, writer, pair.challenge);
            try write_text_ref(world, writer, pair.reply);
            try writer.writeByte(@intCast(pair.variants.len));
            for (pair.variants) |variant| try write_text_ref(world, writer, variant);
        }
        try writer.writeByte(@intFromBool(decl.config.fallback != null));
        if (decl.config.fallback) |fallback| try write_text_ref(world, writer, fallback);
        try writer.writeInt(i64, if (decl.config.win_at) |value| @intCast(value) else -1, .little);
        const r = decl.config.relations;
        for ([_][]const u8{ r.heard, r.mastered, r.counters, r.variant_of, r.tier, r.advantage, r.wins }) |name| try write_text_ref(world, writer, name);
        try write_text_ref(world, writer, decl.fatigue.count_relation);
        try write_text_ref(world, writer, decl.fatigue.calm_label);
        try writer.writeByte(@intCast(decl.fatigue.stages.len));
        for (decl.fatigue.stages) |stage| {
            try write_text_ref(world, writer, stage.relation);
            try writer.writeInt(u32, stage.at, .little);
            try writer.writeInt(u64, stage.ttl, .little);
            try write_text_ref(world, writer, stage.label);
        }
        try writer.writeByte(@intCast(decl.tiers.len));
        for (decl.tiers) |tier| {
            try writer.writeInt(u32, tier.opponent.to_int(), .little);
            try writer.writeInt(u32, tier.tier, .little);
        }
    }

    try writer.writeInt(u32, @intCast(compiled.degradations.items.len), .little);
    for (compiled.degradations.items) |decl| {
        const config = decl.config;
        try writer.writeInt(u32, config.substance.to_int(), .little);
        try writer.writeInt(u32, config.spill_per_moving_tick, .little);
        try writer.writeByte(@intCast(config.stages.len));
        for (config.stages) |stage| {
            try writer.writeInt(u32, stage.entity.to_int(), .little);
            try writer.writeInt(u64, stage.duration_ticks, .little);
        }
        try writer.writeByte(@intCast(config.vessels.len));
        for (config.vessels) |vessel| {
            try writer.writeInt(u32, vessel.entity.to_int(), .little);
            try writer.writeInt(u32, vessel.capacity, .little);
            try writer.writeInt(u32, vessel.initial_volume, .little);
            try writer.writeByte(@intCast(vessel.initial_stage));
        }
        const r = config.relations;
        for ([_][]const u8{ r.contains, r.volume, r.stage, r.exposure, r.failed_at }) |name| try write_text_ref(world, writer, name);
    }

    try writer.writeInt(u32, @intCast(compiled.grids.items.len), .little);
    for (compiled.grids.items) |decl| {
        const grid = decl.grid;
        try writer.writeInt(u32, grid.entity.to_int(), .little);
        try writer.writeInt(u32, grid.room.to_int(), .little);
        try writer.writeInt(u16, grid.width, .little);
        try writer.writeInt(u16, grid.height, .little);
        try writer.writeInt(u32, grid.cell_size, .little);
        try writer.writeInt(i32, grid.origin_x, .little);
        try writer.writeInt(i32, grid.origin_y, .little);
        try writer.writeInt(u32, @intCast(decl.cells.len), .little);
        for (decl.cells) |cell| {
            try writer.writeInt(u32, cell.index, .little);
            try writer.writeByte(@intFromEnum(cell.attribute));
        }
        const r = decl.rules;
        for ([_]u32{ r.burn_ticks, r.spread_ticks, r.dissipate_ticks, r.flow_ticks }) |rate| try writer.writeInt(u32, rate, .little);
    }

    try writer.writeInt(u32, @intCast(compiled.agendas.items.len), .little);
    for (compiled.agendas.items) |decl| {
        const a = decl.agenda;
        try writer.writeInt(u32, a.entity.to_int(), .little);
        try writer.writeInt(u32, a.actor.to_int(), .little);
        try writer.writeInt(u32, a.target.to_int(), .little);
        try writer.writeInt(u16, a.priority, .little);
        try writer.writeInt(u32, a.cooldown_ticks, .little);
        try writer.writeByte(@intFromBool(a.once));
        try writer.writeByte(@intCast(a.clauses.len));
        for (a.clauses) |clause| {
            try write_text_ref(world, writer, clause.relation);
            // Zero is the `_` wildcard; EntityId.none is never a real entity.
            try writer.writeInt(u32, if (clause.subject) |e| e.to_int() else 0, .little);
            try writer.writeInt(u32, if (clause.object) |e| e.to_int() else 0, .little);
            try writer.writeByte(@intFromBool(clause.negated));
        }
    }
}

fn read_entity_ref(world: *const World, reader: anytype) !EntityId {
    const raw = try reader.readInt(u32, .little);
    if (world.get_entity_name(EntityId.from_int(raw)) == null) return error.InvalidProgramEntity;
    return EntityId.from_int(raw);
}

fn read_optional_index(reader: anytype) !?usize {
    const raw = try reader.readInt(i32, .little);
    if (raw < -1) return error.InvalidProgramIndex;
    return if (raw < 0) null else @intCast(raw);
}

fn read_optional_waypoint(reader: anytype, waypoint_count: usize) !?spatial_mod.WaypointId {
    const raw = try reader.readInt(i32, .little);
    if (raw < -1 or raw > waypoint_count or raw == 0) return error.InvalidProgramWaypoint;
    return if (raw < 0) null else @intCast(raw);
}

fn read_waypoint(reader: anytype, waypoint_count: usize) !spatial_mod.WaypointId {
    const value = try reader.readInt(u16, .little);
    if (value == 0 or value > waypoint_count) return error.InvalidProgramWaypoint;
    return value;
}

fn read_activity(reader: anytype) !society_mod.Activity {
    const raw = try reader.readByte();
    if (raw > @intFromEnum(society_mod.Activity.arrested)) return error.InvalidProgramActivity;
    return @enumFromInt(raw);
}

fn read_society_declaration(allocator: std.mem.Allocator, world: *const World, reader: anytype, waypoint_count: usize) !society_mod.Declaration {
    const need_count = try reader.readInt(u32, .little);
    if (need_count == 0 or need_count > society_mod.MAX_NEEDS) return error.InvalidSocietyConfig;
    const needs = try allocator.alloc(society_mod.Need, need_count);
    errdefer allocator.free(needs);
    for (needs) |*need| {
        const name = try read_text_ref(world, reader);
        const worse_raw = try reader.readByte();
        if (worse_raw > 1) return error.InvalidSocietyConfig;
        const max = try reader.readInt(u32, .little);
        const rate = try reader.readInt(u32, .little);
        const resting_rate = try reader.readInt(u32, .little);
        const seek = try reader.readInt(u32, .little);
        const kind = try reader.readByte();
        need.* = .{
            .name = name,
            .worse = @enumFromInt(worse_raw),
            .max = max,
            .rate = rate,
            .resting_rate = resting_rate,
            .seek = seek,
            .satisfy = switch (kind) {
                0 => .{ .stay = .{
                    .at = try read_waypoint(reader, waypoint_count),
                    .restore = try reader.readInt(u32, .little),
                    .until = try reader.readInt(u32, .little),
                    .activity = try read_activity(reader),
                    .unaware = switch (try reader.readByte()) {
                        0 => false,
                        1 => true,
                        else => return error.InvalidSocietyConfig,
                    },
                    .state = try read_text_ref(world, reader),
                    .verb = try read_text_ref(world, reader),
                } },
                1 => blk: {
                    const provider = try read_optional_index(reader);
                    const price = try reader.readInt(u32, .little);
                    const relief = try reader.readInt(u32, .little);
                    const floor = try reader.readInt(u32, .little);
                    const critical_raw = try reader.readInt(i64, .little);
                    if (critical_raw < -1 or critical_raw > std.math.maxInt(u32)) return error.InvalidSocietyConfig;
                    break :blk .{ .trade = .{
                        .provider = provider,
                        .price = price,
                        .relief = relief,
                        .floor = floor,
                        .critical = if (critical_raw < 0) null else @intCast(critical_raw),
                        .theft_relief = try reader.readInt(u32, .little),
                        .theft_floor = try reader.readInt(u32, .little),
                        .item = try read_text_ref(world, reader),
                    } };
                },
                else => return error.InvalidSocietyConfig,
            },
        };
    }

    const member_count = try reader.readInt(u32, .little);
    if (member_count == 0 or member_count > society_mod.MAX_MEMBERS) return error.InvalidSocietyConfig;
    const members = try allocator.alloc(society_mod.Member, member_count);
    var built: usize = 0;
    errdefer {
        for (members[0..built]) |member| {
            allocator.free(member.needs);
            allocator.free(member.routine.stops);
            allocator.free(member.owns);
            allocator.free(member.carries);
        }
        allocator.free(members);
    }
    for (members) |*member| {
        const entity = try read_entity_ref(world, reader);
        const member_need_count = try reader.readInt(u32, .little);
        if (member_need_count != need_count) return error.InvalidSocietyConfig;
        const member_needs = try allocator.alloc(society_mod.MemberNeed, member_need_count);
        errdefer allocator.free(member_needs);
        for (member_needs) |*need| {
            const value = try reader.readInt(u32, .little);
            const rate_raw = try reader.readInt(i64, .little);
            if (rate_raw < -1 or rate_raw > std.math.maxInt(u32)) return error.InvalidSocietyConfig;
            const provider = try read_optional_index(reader);
            need.* = .{ .value = value, .rate = if (rate_raw < 0) null else @intCast(rate_raw), .provider = provider };
        }
        const gold = try reader.readInt(u32, .little);
        const idle = try read_activity(reader);
        const routine_activity_raw = try reader.readByte();
        if (routine_activity_raw != 255 and routine_activity_raw > @intFromEnum(society_mod.Activity.arrested)) return error.InvalidProgramActivity;
        const stop_count = try reader.readInt(u16, .little);
        if (stop_count > society_mod.MAX_STOPS) return error.InvalidSocietyConfig;
        const stops = try allocator.alloc(spatial_mod.WaypointId, stop_count);
        errdefer allocator.free(stops);
        for (stops) |*stop| stop.* = try read_waypoint(reader, waypoint_count);
        const period = try reader.readInt(u64, .little);
        const has_work = try reader.readByte();
        const work: ?society_mod.Work = switch (has_work) {
            0 => null,
            1 => .{ .at = try read_waypoint(reader, waypoint_count), .every = try reader.readInt(u64, .little), .earn = try reader.readInt(u32, .little), .restock = switch (try reader.readByte()) {
                0 => false,
                1 => true,
                else => return error.InvalidSocietyConfig,
            } },
            else => return error.InvalidSocietyConfig,
        };
        const has_merchant = try reader.readByte();
        const merchant: ?society_mod.Merchant = switch (has_merchant) {
            0 => null,
            1 => .{ .post = try read_waypoint(reader, waypoint_count), .goods = try read_entity_ref(world, reader) },
            else => return error.InvalidSocietyConfig,
        };
        const broadcaster = switch (try reader.readByte()) {
            0 => false,
            1 => true,
            else => return error.InvalidSocietyConfig,
        };
        const owns = try allocator.alloc(EntityId, try reader.readInt(u16, .little));
        errdefer allocator.free(owns);
        for (owns) |*item| item.* = try read_entity_ref(world, reader);
        const carries = try allocator.alloc(EntityId, try reader.readInt(u16, .little));
        errdefer allocator.free(carries);
        for (carries) |*item| item.* = try read_entity_ref(world, reader);
        member.* = .{
            .entity = entity,
            .needs = member_needs,
            .gold = gold,
            .idle = idle,
            .routine = .{ .activity = if (routine_activity_raw == 255) null else @enumFromInt(routine_activity_raw), .stops = stops, .period = period, .work = work },
            .merchant = merchant,
            .broadcaster = broadcaster,
            .owns = owns,
            .carries = carries,
        };
        built += 1;
    }

    const enforcer = try read_optional_index(reader);
    const holding = try read_optional_waypoint(reader, waypoint_count);
    const gathering = try read_waypoint(reader, waypoint_count);
    const flight_to = try read_waypoint(reader, waypoint_count);
    const flight_then = try read_optional_waypoint(reader, waypoint_count);
    const flight_every = try reader.readInt(u64, .little);
    const radii = society_mod.Radii{
        .witness = try reader.readInt(i32, .little),
        .culprit = try reader.readInt(i32, .little),
        .rumor = try reader.readInt(i32, .little),
        .arrest = try reader.readInt(i32, .little),
    };
    const witness_grudge_ticks = try reader.readInt(u64, .little);
    const rumor_grudge_ticks = try reader.readInt(u64, .little);
    const warrant_priority = try reader.readInt(u16, .little);
    const currency_unit = try read_text_ref(world, reader);
    var relation_names: [14][]const u8 = undefined;
    for (&relation_names) |*name| name.* = try read_text_ref(world, reader);
    const friend_count = try reader.readInt(u32, .little);
    const friends = try allocator.alloc(society_mod.FriendLink, friend_count);
    errdefer allocator.free(friends);
    for (friends) |*friend| friend.* = .{ .a = try read_entity_ref(world, reader), .b = try read_entity_ref(world, reader) };
    return .{ .config = .{
        .needs = needs,
        .members = members,
        .enforcer = enforcer,
        .holding = holding,
        .gathering = gathering,
        .flight = .{ .to = flight_to, .then = flight_then, .every = flight_every },
        .radii = radii,
        .witness_grudge_ticks = witness_grudge_ticks,
        .rumor_grudge_ticks = rumor_grudge_ticks,
        .warrant_priority = warrant_priority,
        .currency_unit = currency_unit,
        .relations = .{
            .currency = relation_names[0],
            .activity = relation_names[1],
            .tending = relation_names[2],
            .friend = relation_names[3],
            .rival = relation_names[4],
            .grudge = relation_names[5],
            .owns = relation_names[6],
            .carries = relation_names[7],
            .stolen_from = relation_names[8],
            .crime_scene = relation_names[9],
            .witnessed = relation_names[10],
            .knows_rumor = relation_names[11],
            .warrant_for = relation_names[12],
            .arrested = relation_names[13],
        },
        .friends = friends,
    } };
}

fn read_duel_declaration(allocator: std.mem.Allocator, world: *const World, reader: anytype) !duel_mod.Declaration {
    const pair_count = try reader.readInt(u32, .little);
    if (pair_count == 0 or pair_count > duel_mod.MAX_PAIRS) return error.InvalidDuelConfig;
    const pairs = try allocator.alloc(duel_mod.Pair, pair_count);
    var built: usize = 0;
    errdefer {
        for (pairs[0..built]) |pair| allocator.free(pair.variants);
        allocator.free(pairs);
    }
    for (pairs) |*pair| {
        const name = try read_text_ref(world, reader);
        const challenge = try read_text_ref(world, reader);
        const reply = try read_text_ref(world, reader);
        const variant_count = try reader.readByte();
        if (variant_count >= duel_mod.MAX_TIERS) return error.InvalidDuelConfig;
        const variants = try allocator.alloc([]const u8, variant_count);
        errdefer allocator.free(variants);
        for (variants) |*variant| variant.* = try read_text_ref(world, reader);
        pair.* = .{ .name = name, .challenge = challenge, .reply = reply, .variants = variants };
        built += 1;
    }
    const has_fallback = try reader.readByte();
    const fallback: ?[]const u8 = switch (has_fallback) {
        0 => null,
        1 => try read_text_ref(world, reader),
        else => return error.InvalidDuelConfig,
    };
    const win_raw = try reader.readInt(i64, .little);
    if (win_raw < -1 or win_raw > std.math.maxInt(u32)) return error.InvalidDuelConfig;
    var relations: [7][]const u8 = undefined;
    for (&relations) |*name| name.* = try read_text_ref(world, reader);
    const count_relation = try read_text_ref(world, reader);
    const calm_label = try read_text_ref(world, reader);
    const stage_count = try reader.readByte();
    if (stage_count == 0 or stage_count > duel_mod.MAX_STAGES) return error.InvalidFatigueConfig;
    const stages = try allocator.alloc(duel_mod.Stage, stage_count);
    errdefer allocator.free(stages);
    for (stages) |*stage| stage.* = .{ .relation = try read_text_ref(world, reader), .at = try reader.readInt(u32, .little), .ttl = try reader.readInt(u64, .little), .label = try read_text_ref(world, reader) };
    const tier_count = try reader.readByte();
    const tiers = try allocator.alloc(duel_mod.TierAssignment, tier_count);
    errdefer allocator.free(tiers);
    for (tiers) |*tier| tier.* = .{ .opponent = try read_entity_ref(world, reader), .tier = try reader.readInt(u32, .little) };
    return .{
        .config = .{
            .pairs = pairs,
            .fallback = fallback,
            .win_at = if (win_raw < 0) null else @intCast(win_raw),
            .relations = .{ .heard = relations[0], .mastered = relations[1], .counters = relations[2], .variant_of = relations[3], .tier = relations[4], .advantage = relations[5], .wins = relations[6] },
        },
        .fatigue = .{ .stages = stages, .count_relation = count_relation, .calm_label = calm_label },
        .tiers = tiers,
    };
}

/// Untrusted input: entity references, geometry, cell indexes, and attribute bytes are checked
/// before anything reaches the World or SpatialSystem. The cell count is bounded by the grid
/// area times the attribute count, the largest layout a valid declaration can hold.
fn read_grid_declaration(allocator: std.mem.Allocator, world: *const World, reader: anytype, has_rules: bool) !grid_mod.Declaration {
    const grid = grid_mod.Grid{
        .entity = try read_entity_ref(world, reader),
        .room = try read_entity_ref(world, reader),
        .width = try reader.readInt(u16, .little),
        .height = try reader.readInt(u16, .little),
        .cell_size = try reader.readInt(u32, .little),
        .origin_x = try reader.readInt(i32, .little),
        .origin_y = try reader.readInt(i32, .little),
    };
    grid_mod.validate_grid(grid) catch return error.InvalidGridConfig;
    // Version 7 knew only flammable, liquid, and blocking; a later attribute byte there is corrupt.
    const attribute_count: usize = if (has_rules) @typeInfo(grid_mod.Attribute).Enum.fields.len else 3;
    const cell_count = try reader.readInt(u32, .little);
    if (cell_count > grid.cell_count() * attribute_count) return error.InvalidGridConfig;
    const cells = try allocator.alloc(grid_mod.InitialCell, cell_count);
    errdefer allocator.free(cells);
    for (cells) |*cell| {
        const index = try reader.readInt(u32, .little);
        const raw = try reader.readByte();
        if (raw >= attribute_count) return error.InvalidGridConfig;
        cell.* = .{ .index = index, .attribute = @enumFromInt(raw) };
    }
    var rules = grid_mod.Rules{};
    if (has_rules) {
        rules.burn_ticks = try reader.readInt(u32, .little);
        rules.spread_ticks = try reader.readInt(u32, .little);
        rules.dissipate_ticks = try reader.readInt(u32, .little);
        rules.flow_ticks = try reader.readInt(u32, .little);
    }
    const declaration = grid_mod.Declaration{ .grid = grid, .cells = cells, .rules = rules };
    declaration.validate() catch return error.InvalidGridConfig;
    return declaration;
}

/// Untrusted input: every entity and text reference, the clause count, and flag bytes are
/// checked before the agenda reaches the World.
fn read_agenda_declaration(allocator: std.mem.Allocator, world: *const World, reader: anytype) !agency_mod.Declaration {
    const entity = try read_entity_ref(world, reader);
    const actor = try read_entity_ref(world, reader);
    const target = try read_entity_ref(world, reader);
    const priority = try reader.readInt(u16, .little);
    const cooldown_ticks = try reader.readInt(u32, .little);
    const once = try read_flag(reader);
    const clause_count = try reader.readByte();
    if (clause_count == 0 or clause_count > agency_mod.MAX_CLAUSES) return error.InvalidAgendaConfig;
    const clauses = try allocator.alloc(agency_mod.Clause, clause_count);
    errdefer allocator.free(clauses);
    for (clauses) |*clause| {
        clause.* = .{
            .relation = try read_text_ref(world, reader),
            .subject = try read_optional_entity_ref(world, reader),
            .object = try read_optional_entity_ref(world, reader),
            .negated = try read_flag(reader),
        };
    }
    const agenda = agency_mod.Agenda{
        .entity = entity,
        .actor = actor,
        .target = target,
        .priority = priority,
        .cooldown_ticks = cooldown_ticks,
        .once = once,
        .clauses = clauses,
    };
    agency_mod.validate(agenda) catch return error.InvalidAgendaConfig;
    return .{ .agenda = agenda };
}

fn read_flag(reader: anytype) !bool {
    return switch (try reader.readByte()) {
        0 => false,
        1 => true,
        else => error.InvalidAgendaConfig,
    };
}

fn read_optional_entity_ref(world: *const World, reader: anytype) !?EntityId {
    const raw = try reader.readInt(u32, .little);
    if (raw == 0) return null;
    if (world.get_entity_name(EntityId.from_int(raw)) == null) return error.InvalidProgramEntity;
    return EntityId.from_int(raw);
}

fn read_degradation_declaration(allocator: std.mem.Allocator, world: *const World, reader: anytype, has_spill: bool) !container_mod.Declaration {
    const substance = try read_entity_ref(world, reader);
    const spill_per_moving_tick = if (has_spill) try reader.readInt(u32, .little) else 0;
    const stage_count = try reader.readByte();
    if (stage_count < 2 or stage_count > container_mod.MAX_STAGES) return error.InvalidContainerConfig;
    const stages = try allocator.alloc(container_mod.Stage, stage_count);
    errdefer allocator.free(stages);
    for (stages, 0..) |*stage, i| {
        stage.* = .{ .entity = try read_entity_ref(world, reader), .duration_ticks = try reader.readInt(u64, .little) };
        if ((i == stages.len - 1) != (stage.duration_ticks == 0)) return error.InvalidContainerConfig;
        for (stages[0..i]) |prior| if (prior.entity == stage.entity) return error.InvalidContainerConfig;
    }
    const vessel_count = try reader.readByte();
    if (vessel_count == 0 or vessel_count > container_mod.MAX_VESSELS) return error.InvalidContainerConfig;
    const vessels = try allocator.alloc(container_mod.Vessel, vessel_count);
    errdefer allocator.free(vessels);
    for (vessels, 0..) |*vessel, i| {
        vessel.* = .{
            .entity = try read_entity_ref(world, reader),
            .capacity = try reader.readInt(u32, .little),
            .initial_volume = try reader.readInt(u32, .little),
            .initial_stage = try reader.readByte(),
        };
        if (vessel.capacity == 0 or vessel.initial_volume > vessel.capacity or vessel.initial_stage >= stages.len - 1)
            return error.InvalidContainerConfig;
        for (vessels[0..i]) |prior| if (prior.entity == vessel.entity) return error.InvalidContainerConfig;
    }
    var relations: [5][]const u8 = undefined;
    for (&relations) |*name| name.* = try read_text_ref(world, reader);
    const config = container_mod.Config{
        .substance = substance,
        .stages = stages,
        .vessels = vessels,
        .spill_per_moving_tick = spill_per_moving_tick,
        .relations = .{ .contains = relations[0], .volume = relations[1], .stage = relations[2], .exposure = relations[3], .failed_at = relations[4] },
    };
    try container_mod.validate(config);
    return .{ .config = config };
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

    // 10. Script-declared subsystem configuration (version 4+, degradation in version 5+).
    try write_program_declarations(world, pw, compiled);

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

    var societies = std.ArrayList(society_mod.Declaration).init(allocator);
    errdefer {
        for (societies.items) |*decl| decl.deinit_owned(allocator);
        societies.deinit();
    }
    var duels = std.ArrayList(duel_mod.Declaration).init(allocator);
    errdefer {
        for (duels.items) |*decl| decl.deinit_owned(allocator);
        duels.deinit();
    }
    var degradations = std.ArrayList(container_mod.Declaration).init(allocator);
    errdefer {
        for (degradations.items) |*decl| decl.deinit_owned(allocator);
        degradations.deinit();
    }
    if (header.version >= 4) {
        const society_count = try pr.readInt(u32, .little);
        var si: u32 = 0;
        while (si < society_count) : (si += 1) try societies.append(try read_society_declaration(allocator, world, pr, header.waypoint_count));
        const duel_count = try pr.readInt(u32, .little);
        var di: u32 = 0;
        while (di < duel_count) : (di += 1) try duels.append(try read_duel_declaration(allocator, world, pr));
    }
    if (header.version >= 5) {
        const degradation_count = try pr.readInt(u32, .little);
        var ci: u32 = 0;
        while (ci < degradation_count) : (ci += 1) try degradations.append(try read_degradation_declaration(allocator, world, pr, header.version >= 6));
    }
    var grids = std.ArrayList(grid_mod.Declaration).init(allocator);
    errdefer {
        for (grids.items) |*decl| decl.deinit_owned(allocator);
        grids.deinit();
    }
    if (header.version >= 7) {
        const grid_count = try pr.readInt(u32, .little);
        if (grid_count > grid_mod.MAX_GRIDS) return error.InvalidGridConfig;
        var gi: u32 = 0;
        while (gi < grid_count) : (gi += 1) {
            var decl = try read_grid_declaration(allocator, world, pr, header.version >= 8);
            grids.append(decl) catch |err| {
                decl.deinit_owned(allocator);
                return err;
            };
            if (spatial) |sp| sp.add_grid(decl.grid) catch return error.InvalidGridConfig;
        }
    }
    var agendas = std.ArrayList(agency_mod.Declaration).init(allocator);
    errdefer {
        for (agendas.items) |*decl| decl.deinit_owned(allocator);
        agendas.deinit();
    }
    if (header.version >= 9) {
        const agenda_count = try pr.readInt(u32, .little);
        if (agenda_count > agency_mod.MAX_AGENDAS) return error.InvalidAgendaConfig;
        var ai: u32 = 0;
        while (ai < agenda_count) : (ai += 1) {
            var decl = try read_agenda_declaration(allocator, world, pr);
            agendas.append(decl) catch |err| {
                decl.deinit_owned(allocator);
                return err;
            };
        }
        agency_mod.validate_all(agendas.items) catch return error.InvalidAgendaConfig;
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
        .societies = societies,
        .duels = duels,
        .degradations = degradations,
        .grids = grids,
        .agendas = agendas,
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
    // Version 9 follows the draft table with empty society, duel, degradation, grid, and agenda
    // counts.
    const declaration_tail_len = 20;
    const tail_len = 4 + 4 + 4 + 1 + 4;
    const first_note = buffer.items.len - declaration_tail_len - tail_len + 8;
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
        // A real version 4 payload ends after the duel table and loads no degradation profiles.
        const v4 = try testing.allocator.dupe(u8, buffer.items[0 .. buffer.items.len - 12]);
        defer testing.allocator.free(v4);
        reseal_for_test(v4, 4);
        var world2 = try World.init(testing.allocator, 1024 * 1024);
        defer world2.deinit();
        var stream = std.io.fixedBufferStream(v4);
        var loaded = try load_package(testing.allocator, stream.reader(), &world2, null);
        defer loaded.deinit();
        try testing.expectEqual(@as(usize, 0), loaded.degradations.items.len);
    }
    {
        // A version 1 package is the same payload without the draft tail.
        const v1 = try testing.allocator.dupe(u8, buffer.items[0 .. buffer.items.len - tail_len - declaration_tail_len]);
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

test "P23-01/P23-02: package round-trips degradation declarations and loads version 5" {
    const testing = std.testing;
    const compiler = @import("compiler.zig");
    const script =
        \\degradation TestProfile:
        \\  substance TestReagent
        \\  stage Sound 3
        \\  stage Etched 2
        \\  stage Failed 0
        \\  vessel TestVial 8 5 Sound
        \\  spill 2
        \\  relations HoldsReagent ReagentVolume VialState ReagentExposure VialFailedAt
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
    try testing.expectEqual(@as(usize, 1), compiled2.degradations.items.len);
    const declaration = &compiled2.degradations.items[0];
    try testing.expectEqual(@as(usize, 3), declaration.config.stages.len);
    try testing.expectEqual(@as(u32, 8), declaration.config.vessels[0].capacity);
    try testing.expectEqual(@as(u32, 2), declaration.config.spill_per_moving_tick);
    var system = try container_mod.ContainerSystem.init(&world2, declaration.config);
    const vial = world2.lookup_entity("TestVial").?;
    _ = world2.step_tick();
    try system.step(&world2, null);
    try testing.expectEqual(world2.lookup_entity("Sound").?.to_int(), world2.get_property(vial, system.rel.stage).?);

    // Version 5 stored the same declaration without the u32 spill field and had no grid or
    // agenda count.
    const grid_count_len = 4 + 4;
    const bytes_after_spill = 1 + 3 * (4 + 8) + 1 + (4 + 4 + 4 + 1) + 5 * 4 + grid_count_len;
    const spill_offset = buffer.items.len - bytes_after_spill - 4;
    var v5 = std.ArrayList(u8).init(testing.allocator);
    defer v5.deinit();
    try v5.appendSlice(buffer.items[0..spill_offset]);
    try v5.appendSlice(buffer.items[spill_offset + 4 .. buffer.items.len - grid_count_len]);
    reseal_for_test(v5.items, 5);
    var world3 = try World.init(testing.allocator, 1024 * 1024);
    defer world3.deinit();
    var v5_stream = std.io.fixedBufferStream(v5.items);
    var compiled3 = try load_package(testing.allocator, v5_stream.reader(), &world3, null);
    defer compiled3.deinit();
    try testing.expectEqual(@as(u32, 0), compiled3.degradations.items[0].config.spill_per_moving_tick);
}

test "P25-01/P25-02: package round-trips grids and rules, rejects bad cells, and loads versions 6 and 7" {
    const testing = std.testing;
    const compiler = @import("compiler.zig");
    const script =
        \\scene: Armory
        \\marks: ArmoryDoor, ArmoryRack
        \\
        \\grid ArmoryFloor in Armory:
        \\  size 3 2
        \\  cell 10
        \\  origin 5 5
        \\  liquid 0 1 3 1
        \\  blocking 2 0
        \\  place ArmoryRack 2 0
        \\  burn 5
        \\  spread 2
        \\  dissipate 7
        \\  flow 3
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

    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();
    var spatial2 = SpatialSystem.init(testing.allocator);
    defer spatial2.deinit();
    var stream = std.io.fixedBufferStream(buffer.items);
    var compiled2 = try load_package(testing.allocator, stream.reader(), &world2, &spatial2);
    defer compiled2.deinit();
    try testing.expectEqual(@as(usize, 1), compiled2.grids.items.len);
    const grid = spatial2.grid_in_room(world2.lookup_entity("Armory").?).?;
    try testing.expectEqual(@as(i32, 5), grid.origin_x);
    try testing.expectEqual(@as(usize, 4), compiled2.grids.items[0].cells.len);
    try testing.expectEqual(grid_mod.Rules{ .burn_ticks = 5, .spread_ticks = 2, .dissipate_ticks = 7, .flow_ticks = 3 }, compiled2.grids.items[0].rules);
    const rack = spatial2.graph.find_waypoint("ArmoryRack").?;
    try testing.expectEqual(grid_mod.Cell{ .x = 2, .y = 0 }, spatial2.waypoint_cell(rack).?.cell);
    try @import("host.zig").initialize_subsystems(&world2, &compiled2);
    try testing.expect(spatial2.waypoint_blocked(&world2, rack));
    try testing.expect(grid_mod.has_attribute(&world2, grid, .{ .x = 1, .y = 1 }, .liquid));

    // Tail layout: grid count, entity, room, width, height, cell size, origin x/y, cell count,
    // four (index u32, attribute u8) cells, four u32 rates (version 8), then the empty agenda
    // count (version 9).
    const cells_len = 4 * (4 + 1);
    const rules_len = 4 * 4;
    const agenda_count_len = 4;
    const first_cell_index = buffer.items.len - agenda_count_len - rules_len - cells_len;
    {
        const bad = try testing.allocator.dupe(u8, buffer.items);
        defer testing.allocator.free(bad);
        std.mem.writeInt(u32, bad[first_cell_index..][0..4], 6, .little); // one past the 3x2 area
        reseal_for_test(bad, PACKAGE_VERSION);
        var world3 = try World.init(testing.allocator, 1024 * 1024);
        defer world3.deinit();
        var bad_stream = std.io.fixedBufferStream(bad);
        try testing.expectError(error.InvalidGridConfig, load_package(testing.allocator, bad_stream.reader(), &world3, null));
    }
    {
        const bad = try testing.allocator.dupe(u8, buffer.items);
        defer testing.allocator.free(bad);
        bad[first_cell_index + 4] = 5; // past smoke, the last attribute
        reseal_for_test(bad, PACKAGE_VERSION);
        var world3 = try World.init(testing.allocator, 1024 * 1024);
        defer world3.deinit();
        var bad_stream = std.io.fixedBufferStream(bad);
        try testing.expectError(error.InvalidGridConfig, load_package(testing.allocator, bad_stream.reader(), &world3, null));
    }
    {
        // A version 7 payload has no rates; its grids load with every rule off.
        const v7 = try testing.allocator.dupe(u8, buffer.items[0 .. buffer.items.len - agenda_count_len - rules_len]);
        defer testing.allocator.free(v7);
        reseal_for_test(v7, 7);
        var world3 = try World.init(testing.allocator, 1024 * 1024);
        defer world3.deinit();
        var v7_stream = std.io.fixedBufferStream(v7);
        var loaded = try load_package(testing.allocator, v7_stream.reader(), &world3, null);
        defer loaded.deinit();
        try testing.expect(!loaded.grids.items[0].rules.any());

        // Version 7 predates the burning attribute, so its byte is corrupt there.
        v7[first_cell_index + 4] = @intFromEnum(grid_mod.Attribute.burning);
        reseal_for_test(v7, 7);
        var world4 = try World.init(testing.allocator, 1024 * 1024);
        defer world4.deinit();
        var bad_stream = std.io.fixedBufferStream(v7);
        try testing.expectError(error.InvalidGridConfig, load_package(testing.allocator, bad_stream.reader(), &world4, null));
    }
    {
        // A version 6 payload ends before the grid table and loads no grids.
        const grid_section_len = 4 + 4 + 4 + 2 + 2 + 4 + 4 + 4 + 4 + cells_len + rules_len + agenda_count_len;
        const v6 = try testing.allocator.dupe(u8, buffer.items[0 .. buffer.items.len - grid_section_len]);
        defer testing.allocator.free(v6);
        reseal_for_test(v6, 6);
        var world3 = try World.init(testing.allocator, 1024 * 1024);
        defer world3.deinit();
        var spatial3 = SpatialSystem.init(testing.allocator);
        defer spatial3.deinit();
        var v6_stream = std.io.fixedBufferStream(v6);
        var loaded = try load_package(testing.allocator, v6_stream.reader(), &world3, &spatial3);
        defer loaded.deinit();
        try testing.expectEqual(@as(usize, 0), loaded.grids.items.len);
        try testing.expectEqual(@as(usize, 0), spatial3.grids.items.len);
    }
}

test "P33-01: package version 9 round-trips agendas, rejects bad flags, and loads version 8" {
    const testing = std.testing;
    const compiler = @import("compiler.zig");
    const script =
        \\relation Investigated(who, place)
        \\agenda WarnOff:
        \\  actor Keeper
        \\  target Hero
        \\  priority 4
        \\  cooldown 12
        \\  requires Investigated(Hero, _)
        \\  unless Warned(Hero)
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
    try testing.expectEqual(@as(usize, 1), compiled2.agendas.items.len);
    const agenda = compiled2.agendas.items[0].agenda;
    try testing.expectEqual(@as(u16, 4), agenda.priority);
    try testing.expectEqual(@as(u32, 12), agenda.cooldown_ticks);
    try testing.expectEqualStrings("Hero", world2.get_entity_name(agenda.target).?);
    try testing.expectEqual(@as(usize, 2), agenda.clauses.len);
    try testing.expect(agenda.clauses[0].object == null and !agenda.clauses[0].negated);
    try testing.expect(agenda.clauses[1].negated and agenda.clauses[1].object == null);
    try testing.expectEqualStrings("Warned", agenda.clauses[1].relation);

    // Tail: each clause is text ref, subject, object (u32 each) and a negated byte.
    const clause_len = 4 + 4 + 4 + 1;
    {
        const bad = try testing.allocator.dupe(u8, buffer.items);
        defer testing.allocator.free(bad);
        bad[bad.len - 1] = 2; // the last clause's negated flag
        reseal_for_test(bad, PACKAGE_VERSION);
        var world3 = try World.init(testing.allocator, 1024 * 1024);
        defer world3.deinit();
        var bad_stream = std.io.fixedBufferStream(bad);
        try testing.expectError(error.InvalidAgendaConfig, load_package(testing.allocator, bad_stream.reader(), &world3, null));
    }
    {
        // A version 8 payload ends before the agenda table and loads none.
        const agenda_section_len = 4 + 4 + 4 + 4 + 2 + 4 + 1 + 1 + 2 * clause_len;
        const v8 = try testing.allocator.dupe(u8, buffer.items[0 .. buffer.items.len - agenda_section_len]);
        defer testing.allocator.free(v8);
        reseal_for_test(v8, 8);
        var world3 = try World.init(testing.allocator, 1024 * 1024);
        defer world3.deinit();
        var v8_stream = std.io.fixedBufferStream(v8);
        var loaded = try load_package(testing.allocator, v8_stream.reader(), &world3, null);
        defer loaded.deinit();
        try testing.expectEqual(@as(usize, 0), loaded.agendas.items.len);
    }
}

test "P24-01: package round-trips path initializers and guarded routines" {
    const testing = std.testing;
    const compiler = @import("compiler.zig");
    const vm_mod = @import("vm.zig");
    const script =
        \\entity Hero
        \\relation ChosenWits(flag)
        \\relation ChosenFists(flag)
        \\relation WitsSolved(flag)
        \\relation FistsSolved(flag)
        \\path Wits:
        \\  remember ChosenWits(Hero)
        \\  routine WitsPlan(Hero):
        \\    remember WitsSolved(Hero)
        \\path Fists:
        \\  remember ChosenFists(Hero)
        \\  routine FistsPlan(Hero):
        \\    remember FistsSolved(Hero)
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

    try testing.expect(compiled2.find_path("Wits") != null);
    try testing.expect(compiled2.find_path("Fists") != null);

    var vm = vm_mod.VM.init(testing.allocator, &world2, &compiled2.chunk);
    defer vm.deinit();
    _ = try vm.select_path(&compiled2, "Wits");
    _ = try vm.step_tick();

    const hero = world2.lookup_entity("Hero").?;
    const chosen_wits = world2.lookup_relation("ChosenWits").?;
    try testing.expect(world2.has_fact(hero, chosen_wits, null));

    _ = try vm.spawn_routine(hero, compiled2.routine_entries.get("WitsPlan").?);
    _ = try vm.spawn_routine(hero, compiled2.routine_entries.get("FistsPlan").?);
    _ = try vm.step_tick();
    try testing.expect(world2.has_fact(hero, world2.lookup_relation("WitsSolved").?, null));
    try testing.expect(!world2.has_fact(hero, world2.lookup_relation("FistsSolved").?, null));
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

test "P32-22/P32-24: package version 6 round-trips society and duel declarations" {
    const testing = std.testing;
    const compiler = @import("compiler.zig");
    const script =
        \\scene: Test Square
        \\cast: Alice, Merchant, Rival
        \\marks: Home, Market, Square
        \\society TestSociety:
        \\  need Hunger high 100 1 0 50 trade Merchant 2 20 0 80 30 0 "a meal"
        \\  member Alice 5 working:
        \\    need Hunger 10 none Merchant
        \\    routine working 2 Home, Square
        \\  member Merchant 10 working:
        \\    need Hunger 10 none Merchant
        \\    routine working 2 Market
        \\    merchant Market Goods
        \\    owns Goods
        \\    carries Goods
        \\  gathering Square
        \\  flight Home none 4
        \\  friend Alice Merchant
        \\duel TestDuel:
        \\  pair Riddle:
        \\    challenge "What speaks without a mouth?"
        \\    reply "An echo."
        \\    variant 1 "Voiceless, I answer."
        \\  fallback "I do not know."
        \\  win 3
        \\  tier Rival 1
        \\  fatigue Inquiries "calm":
        \\    stage AnnoyedWith 2 10 "annoyed"
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

    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();
    var spatial2 = SpatialSystem.init(testing.allocator);
    defer spatial2.deinit();
    var stream = std.io.fixedBufferStream(buffer.items);
    var compiled2 = try load_package(testing.allocator, stream.reader(), &world2, &spatial2);
    defer compiled2.deinit();
    try testing.expectEqual(@as(usize, 1), compiled2.societies.items.len);
    try testing.expectEqual(@as(usize, 1), compiled2.duels.items.len);
    var society = try society_mod.Society.init(&world2, compiled2.societies.items[0].config);
    const alice = world2.lookup_entity("Alice").?;
    try testing.expectEqual(@as(u32, 10), society.get_need(&world2, alice, 0));
    var duel = try duel_mod.Duel.init(&world2, compiled2.duels.items[0].config);
    try compiled2.duels.items[0].apply_tiers(&duel);
    const rival = world2.lookup_entity("Rival").?;
    try testing.expectEqual(@as(u32, 1), world2.get_property(rival, duel.tier_rel).?);
}
