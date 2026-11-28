const std = @import("std");
const ListWriter = @import("list_writer.zig").ListWriter;
const world_mod = @import("world.zig");
const phrase_mod = @import("phrase.zig");
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
const hint_mod = @import("hint.zig");
const spell_mod = @import("spell.zig");
const decision_mod = @import("decision.zig");
const value_mod = @import("value.zig");
const dilemma_mod = @import("dilemma.zig");
const image_mod = @import("image.zig");
const qoi_mod = @import("qoi.zig");
const command_mod = @import("command.zig");
const mml = @import("mml.zig");

const World = world_mod.World;
const EntityId = world_mod.EntityId;
const RelationKind = world_mod.RelationKind;
const RelationType = world_mod.RelationType;
const PatternClause = world_mod.PatternClause;
const PatternTerm = world_mod.PatternTerm;
const SpatialSystem = spatial_mod.SpatialSystem;
const BytecodeChunk = bytecode_mod.BytecodeChunk;
const Opcode = bytecode_mod.Opcode;
const CompiledProgram = codegen_mod.CompiledProgram;
const CompiledWhenRule = codegen_mod.CompiledWhenRule;
const WhenEdge = parser_mod.WhenEdge;

/// The 1.0 package format (P48-17, D-172, D-174, D-187): a 16-byte header (`BSP1`, the format
/// number, a CRC32 of the payload, and the payload's length), then sections. Each section is a
/// four-character tag, a flags byte whose bit 0 says a reader must understand it, its length,
/// and its bytes. A reader refuses an unknown required section and skips an unknown optional
/// one, so a 1.x addition is a new section rather than a new format; every 1.0 section is
/// required. A package writes only the sections its program uses, which is also how a browser
/// build knows which readers to link (`sections_in`). Every section is read through its own
/// bounded reader and must be consumed exactly.
pub const PACKAGE_MAGIC = [4]u8{ 'B', 'S', 'P', '1' };
/// The magic of packages written before 1.0, which 1.0 does not read (D-174).
pub const PRE_1_0_MAGIC = [4]u8{ 'B', 'S', 'P', 'B' };
pub const PACKAGE_FORMAT: u32 = 1;
pub const MAX_PACKAGE_PAYLOAD_SIZE: u32 = 64 * 1024 * 1024;
/// Upper bound on cast entries a package may declare; a larger count is corrupt input.
const MAX_CAST: u32 = 4096;
/// The most display names a package may hold; a larger count is corrupt input.
const MAX_DISPLAY_NAMES: usize = 4096;
/// Upper bounds on package section counts so corrupt streams fail fast without huge allocations.
const MAX_SOCIETY_ITEMS: u16 = 256;
const MAX_SOCIETIES: u32 = 64;
const MAX_DUELS: u32 = 64;
const MAX_DEGRADATIONS: u32 = 64;
const MAX_WAYPOINTS: u32 = std.math.maxInt(u16);
const MAX_EDGES: u32 = 65535;
const MAX_HOTSPOTS: u32 = 65535;

pub const PackageHeader = extern struct {
    magic: [4]u8 = PACKAGE_MAGIC,
    format: u32 = PACKAGE_FORMAT,
    crc32: u32 = 0,
    payload_size: u32 = 0,
};

/// The parts of a program, in the order a reader takes them: each later one may refer to an
/// earlier one (an agenda to entities, a guard to a cue handler, a dilemma to axes).
pub const Section = enum(u8) {
    names,
    places,
    code,
    rules,
    drafts,
    societies,
    duels,
    degradations,
    grids,
    agendas,
    commands,
    scores,
    cast,
    guards,
    goals,
    spellbooks,
    decisions,
    axes,
    red_lines,
    dilemmas,
    images,
    art,
    text,
    cycles,
    /// A script's room-block exits (P47-11, D-199). Required: a reader without it would play
    /// the game with its doorways shut, so it refuses the package by name instead.
    exits,

    pub fn tag(self: Section) [4]u8 {
        return SECTION_TAGS[@intFromEnum(self)];
    }

    /// Flags byte written in the section header: `cycles` is optional (`0`) so 1.0 readers
    /// skip it and draw static QOI art (P49-01, D-190).
    pub fn flags(self: Section) u8 {
        return switch (self) {
            .cycles => 0,
            else => SECTION_REQUIRED,
        };
    }

    pub fn from_tag(t: [4]u8) ?Section {
        for (SECTION_TAGS, 0..) |known, k| if (std.mem.eql(u8, &known, &t)) return @enumFromInt(k);
        return null;
    }
};

pub const SECTION_TAGS = [_][4]u8{
    "NAME".*, "PLAC".*, "CODE".*, "RULE".*, "DRFT".*, "SOCI".*, "DUEL".*, "DGRD".*,
    "GRID".*, "AGND".*, "CMND".*, "SCOR".*, "CAST".*, "GURD".*, "GOAL".*, "SPEL".*,
    "DCSN".*, "AXIS".*, "REDL".*, "DLMA".*, "IMGS".*, "ARTB".*, "TEXT".*, "CYCL".*,
    "EXIT".*,
};

comptime {
    if (SECTION_TAGS.len != @typeInfo(Section).@"enum".field_names.len) @compileError("one tag per section");
}

pub const SectionSet = std.EnumSet(Section);
pub const ALL_SECTIONS = SectionSet.full;
/// Flags bit 0: a reader that does not know the section must refuse the package.
pub const SECTION_REQUIRED: u8 = 1;
const SECTION_HEADER_LEN = 4 + 1 + 4;

/// The diagnostic for a package this engine cannot read: one from before 1.0 (D-174), or a
/// format newer than it knows.
pub fn format_unsupported_version(buf: []u8, found: u32) []const u8 {
    return std.fmt.bufPrint(buf, "unsupported .bspk format {d}; this engine reads format {d}", .{ found, PACKAGE_FORMAT }) catch "unsupported .bspk format";
}

pub const PRE_1_0_MESSAGE = "this package was built by a BeSpoke before 1.0, which 1.0 does not read; rebuild it from its script with `bespoke compile`";

/// The format number of an in-memory package, or null when it is not a 1.0 package. The
/// loader remains the authority for the checksum, bounds, and sections.
pub fn version_from_bytes(bytes: []const u8) ?u32 {
    if (bytes.len < 8 or !std.mem.eql(u8, bytes[0..4], &PACKAGE_MAGIC)) return null;
    return std.mem.readInt(u32, bytes[4..8], .little);
}

pub fn is_pre_1_0(bytes: []const u8) bool {
    return bytes.len >= 4 and std.mem.eql(u8, bytes[0..4], &PRE_1_0_MAGIC);
}

/// The sections a package holds, read when the module is built from bytes it embeds, so a
/// browser build links only the readers its game needs (D-172, D-187). A package this cannot
/// read is a compile error.
pub fn sections_in(comptime bytes: []const u8) SectionSet {
    @setEvalBranchQuota(100_000);
    if (bytes.len < @sizeOf(PackageHeader) or !std.mem.eql(u8, bytes[0..4], &PACKAGE_MAGIC)) @compileError("not a 1.0 package");
    var set = SectionSet.empty;
    var at: usize = @sizeOf(PackageHeader);
    while (at + SECTION_HEADER_LEN <= bytes.len) {
        const t: [4]u8 = bytes[at..][0..4].*;
        const len = std.mem.readInt(u32, bytes[at + 5 ..][0..4], .little);
        if (Section.from_tag(t)) |known| set.insert(known);
        at += SECTION_HEADER_LEN + len;
    }
    return set;
}

fn write_str(writer: anytype, str: []const u8) !void {
    try writer.writeInt(u16, @intCast(str.len), .little);
    try writer.writeAll(str);
}

fn read_str(allocator: std.mem.Allocator, reader: anytype) ![]const u8 {
    const len = try reader.takeInt(u16, .little);
    const buf = try allocator.alloc(u8, len);
    errdefer allocator.free(buf);
    try reader.readSliceAll(buf);
    return buf;
}

fn write_text_ref(world: *const World, writer: anytype, value: []const u8) !void {
    const entity = world.lookup_entity(value) orelse return error.UninternedProgramText;
    try writer.writeInt(u32, entity.to_int(), .little);
}

fn read_text_ref(world: *const World, reader: anytype) ![]const u8 {
    const raw = try reader.takeInt(u32, .little);
    return world.get_entity_name(EntityId.from_int(raw)) orelse error.InvalidProgramTextRef;
}

fn write_optional_index(writer: anytype, value: ?usize) !void {
    try writer.writeInt(i32, if (value) |v| @intCast(v) else -1, .little);
}

fn write_optional_waypoint(writer: anytype, value: ?spatial_mod.WaypointId) !void {
    try writer.writeInt(i32, if (value) |v| @intCast(v) else -1, .little);
}

fn write_societies(world: *const World, writer: anytype, compiled: *const CompiledProgram) !void {
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

}

fn write_duels(world: *const World, writer: anytype, compiled: *const CompiledProgram) !void {
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
        try writer.writeByte(@intCast(decl.config.fallbacks.len));
        for (decl.config.fallbacks) |line| try write_text_ref(world, writer, line);
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

}

fn write_degradations(world: *const World, writer: anytype, compiled: *const CompiledProgram) !void {
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

}

fn write_grids(world: *const World, writer: anytype, compiled: *const CompiledProgram) !void {
    _ = world;
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

}

fn write_agendas(world: *const World, writer: anytype, compiled: *const CompiledProgram) !void {
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

fn write_commands(world: *const World, writer: anytype, compiled: *const CompiledProgram) !void {
    _ = world;
    try writer.writeInt(u32, @intCast(compiled.commands.items.len), .little);
    for (compiled.commands.items) |c| {
        try write_str(writer, c.cue);
        try write_str(writer, c.text);
    }
    try writer.writeInt(u32, @intCast(compiled.aliases.items.len), .little);
    for (compiled.aliases.items) |a| {
        try writer.writeInt(u32, a.entity.to_int(), .little);
        try writer.writeByte(@intCast(a.phrases.len));
        for (a.phrases) |phrase| try write_str(writer, phrase);
    }

}

fn write_scores(world: *const World, writer: anytype, compiled: *const CompiledProgram) !void {
    _ = world;
    try writer.writeInt(u32, @intCast(compiled.scores.items.len), .little);
    for (compiled.scores.items) |score| {
        try write_str(writer, score.name);
        try writer.writeByte(@intCast(score.scenes.len));
        for (score.scenes) |scene| try write_str(writer, scene);
        for (score.parts) |text| try write_str(writer, text);
    }

}

fn write_cast(world: *const World, writer: anytype, compiled: *const CompiledProgram) !void {
    _ = world;
    try writer.writeInt(u32, @intCast(compiled.cast.items.len), .little);
    for (compiled.cast.items) |place| {
        try writer.writeInt(u32, place.actor.to_int(), .little);
        try writer.writeInt(u16, place.mark, .little);
    }

}

fn write_guards(world: *const World, writer: anytype, compiled: *const CompiledProgram) !void {
    _ = world;
    try writer.writeInt(u32, @intCast(compiled.cue_guards.items.len), .little);
    for (compiled.cue_guards.items) |guard| {
        try writer.writeInt(u32, @intCast(guard.handler_pc), .little);
        for (guard.param_slots) |slot| try writer.writeByte(slot orelse NO_GUARD_SLOT);
        try writer.writeInt(u16, @intCast(guard.clauses.len), .little);
        for (guard.clauses) |clause| try write_pattern_clause(writer, clause);
    }

}

fn write_goals(world: *const World, writer: anytype, compiled: *const CompiledProgram) !void {
    try writer.writeInt(u32, @intCast(compiled.goals.items.len), .little);
    for (compiled.goals.items) |decl| {
        try writer.writeInt(u32, decl.goal.entity.to_int(), .little);
        try writer.writeInt(u32, @intCast(decl.goal.needs.len), .little);
        for (decl.goal.needs) |need| {
            try writer.writeInt(u32, need.entity.to_int(), .little);
            try write_text_ref(world, writer, need.relation);
            // Zero is the `_` wildcard, as in an agenda clause.
            try writer.writeInt(u32, if (need.subject) |e| e.to_int() else 0, .little);
            try writer.writeInt(u32, if (need.object) |e| e.to_int() else 0, .little);
            try writer.writeInt(u32, if (need.room) |e| e.to_int() else 0, .little);
            try writer.writeByte(@intCast(need.after.len));
            for (need.after) |prerequisite| try writer.writeInt(u32, prerequisite.to_int(), .little);
            try writer.writeByte(@intCast(need.hints.len));
            for (need.hints) |hint| {
                try writer.writeByte(@intFromEnum(hint.tier));
                try write_str(writer, hint.text);
            }
        }
    }

}

fn write_spellbooks(world: *const World, writer: anytype, compiled: *const CompiledProgram) !void {
    _ = world;
    try writer.writeInt(u32, @intCast(compiled.spellbooks.items.len), .little);
    for (compiled.spellbooks.items) |decl| {
        try writer.writeInt(u32, decl.book.entity.to_int(), .little);
        try writer.writeInt(u32, @intCast(decl.book.words.len), .little);
        for (decl.book.words) |word| {
            try writer.writeInt(u32, word.entity.to_int(), .little);
            try writer.writeByte(@intFromEnum(word.kind));
            try writer.writeInt(u16, word.tier, .little);
        }
        try writer.writeInt(u32, @intCast(decl.book.spells.len), .little);
        for (decl.book.spells) |spell| {
            try writer.writeInt(u32, spell.entity.to_int(), .little);
            for (spell.words) |word| try writer.writeInt(u32, word.to_int(), .little);
        }
    }

}

fn write_decisions(world: *const World, writer: anytype, compiled: *const CompiledProgram) !void {
    try writer.writeInt(u32, @intCast(compiled.decisions.items.len), .little);
    for (compiled.decisions.items) |decl| {
        const decision = decl.decision;
        try writer.writeInt(u32, decision.entity.to_int(), .little);
        try writer.writeInt(u32, decision.actor.to_int(), .little);
        try writer.writeInt(u32, decision.cue.to_int(), .little);
        try writer.writeByte(@intCast(decision.clauses.len));
        for (decision.clauses) |clause| try write_decision_clause(world, writer, clause);
        try writer.writeByte(@intCast(decision.options.len));
        for (decision.options) |option| {
            try writer.writeInt(u32, option.entity.to_int(), .little);
            try writer.writeByte(@intCast(option.picks.len));
            for (option.picks) |pick| {
                try writer.writeInt(i32, pick.points, .little);
                try write_decision_clause(world, writer, pick.clause);
            }
        }
    }

}

fn write_red_lines(world: *const World, writer: anytype, compiled: *const CompiledProgram) !void {
    _ = world;
    try writer.writeInt(u32, @intCast(compiled.red_lines.items.len), .little);
    for (compiled.red_lines.items) |decl| {
        try writer.writeInt(u32, decl.red_lines.actor.to_int(), .little);
        try writer.writeByte(@intCast(decl.red_lines.options.len));
        for (decl.red_lines.options) |option| try writer.writeInt(u32, option.to_int(), .little);
    }

}

fn write_dilemmas(world: *const World, writer: anytype, compiled: *const CompiledProgram) !void {
    try writer.writeInt(u32, @intCast(compiled.dilemmas.items.len), .little);
    for (compiled.dilemmas.items) |decl| {
        const d = decl.dilemma;
        try writer.writeInt(u32, d.entity.to_int(), .little);
        try writer.writeInt(u32, d.actor.to_int(), .little);
        try writer.writeInt(u32, d.cue.to_int(), .little);
        try writer.writeByte(@intCast(d.clauses.len));
        for (d.clauses) |clause| try write_decision_clause(world, writer, clause);
        try writer.writeInt(u16, d.axis.to_int(), .little);
        try writer.writeInt(u16, d.counter.to_int(), .little);
        try writer.writeByte(@intCast(d.leans.len));
        for (d.leans) |lean| {
            try writer.writeInt(i32, lean.points, .little);
            try write_decision_clause(world, writer, lean.clause);
        }
        for (d.responses) |response| {
            try writer.writeInt(u32, response.line.to_int(), .little);
            try writer.writeInt(u32, response.action.to_int(), .little);
        }
        try writer.writeByte(@intCast(d.drifts.len));
        for (d.drifts) |drift| {
            try writer.writeInt(u16, drift.axis.to_int(), .little);
            try writer.writeInt(i32, drift.points, .little);
            try write_decision_clause(world, writer, drift.clause);
        }
        try writer.writeByte(@intCast(d.appeals.len));
        for (d.appeals) |appeal| {
            try writer.writeInt(u16, appeal.axis.to_int(), .little);
            try writer.writeInt(u32, appeal.entity.to_int(), .little);
            try writer.writeInt(i32, appeal.points, .little);
        }
        // The author's numbers (D-183).
        try writer.writeAll(&.{ d.strong_at, d.moderate_at, d.drift_cap });
    }

}

/// Version 27: each (handler pc, next handler pc) link of handlers sharing a signature
/// (D-160), in ascending pc order so the same program always writes the same bytes. Links are
/// few (one per repeated guarded handler), so finding each next-smallest pc in turn costs
/// nothing worth an allocation.
fn write_cue_chain(writer: anytype, compiled: *const CompiledProgram) !void {
    const chain = &compiled.cue_handler_chain;
    try writer.writeInt(u32, chain.count(), .little);
    var last: ?usize = null;
    var written: u32 = 0;
    while (written < chain.count()) : (written += 1) {
        var best: ?usize = null;
        var it = chain.keyIterator();
        while (it.next()) |pc| {
            if (last != null and pc.* <= last.?) continue;
            if (best == null or pc.* < best.?) best = pc.*;
        }
        const pc = best.?;
        try writer.writeInt(u32, @intCast(pc), .little);
        try writer.writeInt(u32, @intCast(chain.get(pc).?), .little);
        last = pc;
    }
}

/// Version 31: display names by entity, then phrase overrides by key, each sorted so the same
/// program writes the same bytes (P48-09, D-179).
fn write_player_text(world: *const World, writer: anytype) !void {
    if (world.display_names.count() > MAX_DISPLAY_NAMES) return error.InvalidPlayerText;
    var ids: [MAX_DISPLAY_NAMES]u32 = undefined;
    var n: usize = 0;
    var names = world.display_names.keyIterator();
    while (names.next()) |id| : (n += 1) ids[n] = id.*;
    std.mem.sort(u32, ids[0..n], {}, std.sort.asc(u32));
    try writer.writeInt(u32, @intCast(n), .little);
    for (ids[0..n]) |id| {
        try writer.writeInt(u32, id, .little);
        try write_str(writer, world.display_names.get(id).?);
    }
    var count: u32 = 0;
    for (phrase_mod.ENTRIES) |entry| {
        if (world.phrase_override(entry.name) != null) count += 1;
    }
    try writer.writeInt(u32, count, .little);
    for (phrase_mod.ENTRIES) |entry| {
        const text = world.phrase_override(entry.name) orelse continue;
        try write_str(writer, entry.name);
        try write_str(writer, text);
    }
}

/// Version 33: named looks (name, image, animations as in the version 25 sprites), then parts
/// (entity, host, offset) (P48-11, D-181).
const NO_OWNER_SLOT: u8 = 0xFF;

fn write_art_looks(writer: anytype, art: image_mod.Art) !void {
    try writer.writeInt(u32, @intCast(art.looks.len), .little);
    for (art.looks) |look| {
        try write_str(writer, look.name);
        try writer.writeInt(u16, look.image, .little);
        for (look.animations) |steps| {
            try writer.writeByte(@intCast(steps.len));
            for (steps) |step| {
                try writer.writeInt(u16, step.frame, .little);
                try writer.writeInt(u16, step.duration, .little);
            }
        }
    }
    try writer.writeInt(u32, @intCast(art.parts.len), .little);
    for (art.parts) |part| {
        try writer.writeInt(u32, part.entity.to_int(), .little);
        try writer.writeInt(u32, part.host.to_int(), .little);
        try writer.writeInt(i16, part.dx, .little);
        try writer.writeInt(i16, part.dy, .little);
    }
}

/// Untrusted input: counts are bounded before allocation, entities must exist, and
/// `Art.validate` checks images, frames, names, and offsets.
fn read_art_looks(allocator: std.mem.Allocator, world: *const World, reader: anytype, art: *image_mod.Art) !void {
    const look_count = try reader.takeInt(u32, .little);
    if (look_count > image_mod.MAX_BINDINGS) return error.InvalidImageBinding;
    const looks = try allocator.alloc(image_mod.Look, look_count);
    for (looks) |*look| look.* = .{ .name = &.{}, .image = 0 };
    art.looks = looks;
    for (looks) |*look| {
        look.name = try read_str(allocator, reader);
        look.image = try reader.takeInt(u16, .little);
        for (&look.animations) |*steps| {
            const count = try reader.takeByte();
            if (count > image_mod.MAX_STEPS) return error.InvalidImageBinding;
            const own = try allocator.alloc(image_mod.Step, count);
            steps.* = own;
            for (own) |*step| step.* = .{
                .frame = try reader.takeInt(u16, .little),
                .duration = try reader.takeInt(u16, .little),
            };
        }
    }
    const part_count = try reader.takeInt(u32, .little);
    if (part_count > image_mod.MAX_BINDINGS) return error.InvalidImageBinding;
    const parts = try allocator.alloc(image_mod.Part, part_count);
    art.parts = parts;
    for (parts) |*part| {
        const entity = read_entity_ref(world, reader) catch |err| return if (err == error.EndOfStream) err else error.InvalidImageBinding;
        const host = read_entity_ref(world, reader) catch |err| return if (err == error.EndOfStream) err else error.InvalidImageBinding;
        part.* = .{ .entity = entity, .host = host, .dx = try reader.takeInt(i16, .little), .dy = try reader.takeInt(i16, .little) };
    }
    art.validate() catch |err| return switch (err) {
        error.InvalidImageBinding => error.InvalidImageBinding,
        else => err,
    };
}

/// Untrusted input: counts are bounded, each name belongs to an entity in the package, and each
/// phrase names a known key and only its placeholders.
fn read_player_text(allocator: std.mem.Allocator, world: *World, reader: anytype) !void {
    const names = try reader.takeInt(u32, .little);
    if (names > MAX_DISPLAY_NAMES) return error.InvalidPlayerText;
    for (0..names) |_| {
        const entity = read_entity_ref(world, reader) catch |err| return if (err == error.EndOfStream) err else error.InvalidPlayerText;
        const text = try read_str(allocator, reader);
        defer allocator.free(text);
        try world.set_display_name(entity, text);
    }
    const phrases = try reader.takeInt(u32, .little);
    if (phrases > phrase_mod.ENTRIES.len) return error.InvalidPlayerText;
    for (0..phrases) |_| {
        const key_name = try read_str(allocator, reader);
        defer allocator.free(key_name);
        const text = try read_str(allocator, reader);
        defer allocator.free(text);
        const key = phrase_mod.find(key_name) orelse return error.InvalidPlayerText;
        phrase_mod.validate(key, text) catch return error.InvalidPlayerText;
        try world.set_phrase(key_name, text);
    }
}

fn read_cue_chain(
    allocator: std.mem.Allocator,
    reader: anytype,
    entries: *const std.StringHashMap(usize),
    bytecode_len: u32,
) !std.AutoHashMapUnmanaged(usize, usize) {
    const count = try reader.takeInt(u32, .little);
    if (count > MAX_CUE_GUARDS) return error.InvalidCueChain;
    var chain: std.AutoHashMapUnmanaged(usize, usize) = .empty;
    errdefer chain.deinit(allocator);
    try chain.ensureTotalCapacity(allocator, count);
    var nexts: std.AutoHashMapUnmanaged(usize, void) = .empty;
    defer nexts.deinit(allocator);
    try nexts.ensureTotalCapacity(allocator, count);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const pc: usize = try reader.takeInt(u32, .little);
        const next: usize = try reader.takeInt(u32, .little);
        if (next >= bytecode_len) return error.InvalidCueChain;
        if (!nexts.contains(pc) and !is_first_handler(entries, pc)) return error.InvalidCueChain;
        if (chain.contains(pc) or nexts.contains(next) or is_first_handler(entries, next)) return error.InvalidCueChain;
        chain.putAssumeCapacity(pc, next);
        nexts.putAssumeCapacity(next, {});
    }
    return chain;
}

fn is_chained_handler(chain: *const std.AutoHashMapUnmanaged(usize, usize), pc: usize) bool {
    var it = chain.valueIterator();
    while (it.next()) |v| {
        if (v.* == pc) return true;
    }
    return false;
}

fn is_first_handler(entries: *const std.StringHashMap(usize), pc: usize) bool {
    var it = entries.valueIterator();
    while (it.next()) |v| {
        if (v.* == pc) return true;
    }
    return false;
}

/// Untrusted input: the count is bounded before allocation, entities must exist, and
/// `Art.validate` checks each rectangle against the art.
fn read_art_areas(allocator: std.mem.Allocator, world: *const World, reader: anytype, art: *image_mod.Art) !void {
    const count = try reader.takeInt(u32, .little);
    if (count > image_mod.MAX_BINDINGS) return error.InvalidImageBinding;
    const areas = try allocator.alloc(image_mod.Area, count);
    art.areas = areas;
    for (areas) |*a| {
        const entity = read_entity_ref(world, reader) catch |err| return if (err == error.EndOfStream) err else error.InvalidImageBinding;
        var v: [4]u16 = undefined;
        for (&v) |*n| n.* = try reader.takeInt(u16, .little);
        a.* = .{ .entity = entity, .x = v[0], .y = v[1], .w = v[2], .h = v[3] };
    }
    art.validate() catch |err| return switch (err) {
        error.InvalidImageBinding => error.InvalidImageBinding,
        else => err,
    };
}

/// Version 25: each backdrop's scene and image, then each sprite's entity, image, and its
/// animations in `image.Anim` order as a step count and (frame, duration) pairs.
fn write_art_bindings(writer: anytype, art: image_mod.Art) !void {
    try writer.writeInt(u32, @intCast(art.backdrops.len), .little);
    for (art.backdrops) |b| {
        try writer.writeInt(u32, b.scene.to_int(), .little);
        try writer.writeInt(u16, b.image, .little);
    }
    try writer.writeInt(u32, @intCast(art.sprites.len), .little);
    for (art.sprites) |sprite| {
        try writer.writeInt(u32, sprite.entity.to_int(), .little);
        try writer.writeInt(u16, sprite.image, .little);
        for (sprite.animations) |steps| {
            try writer.writeByte(@intCast(steps.len));
            for (steps) |step| {
                try writer.writeInt(u16, step.frame, .little);
                try writer.writeInt(u16, step.duration, .little);
            }
        }
    }
}

/// Untrusted input: counts are bounded before anything is allocated, entities must exist in the
/// loaded table, and `Art.validate` checks every image index, backdrop size, and step.
fn read_art_bindings(allocator: std.mem.Allocator, world: *const World, reader: anytype, art: *image_mod.Art) !void {
    const backdrop_count = try reader.takeInt(u32, .little);
    if (backdrop_count > image_mod.MAX_BINDINGS) return error.InvalidImageBinding;
    const backdrops = try allocator.alloc(image_mod.Backdrop, backdrop_count);
    art.backdrops = backdrops;
    for (backdrops) |*b| {
        b.scene = read_entity_ref(world, reader) catch |err| return if (err == error.EndOfStream) err else error.InvalidImageBinding;
        b.image = try reader.takeInt(u16, .little);
    }
    const sprite_count = try reader.takeInt(u32, .little);
    if (sprite_count > image_mod.MAX_BINDINGS) return error.InvalidImageBinding;
    const sprites = try allocator.alloc(image_mod.Sprite, sprite_count);
    for (sprites) |*sprite| sprite.* = .{ .entity = .none, .image = 0 };
    art.sprites = sprites;
    for (sprites) |*sprite| {
        sprite.entity = read_entity_ref(world, reader) catch |err| return if (err == error.EndOfStream) err else error.InvalidImageBinding;
        sprite.image = try reader.takeInt(u16, .little);
        for (&sprite.animations) |*steps| {
            const count = try reader.takeByte();
            if (count > image_mod.MAX_STEPS) return error.InvalidImageBinding;
            const own = try allocator.alloc(image_mod.Step, count);
            steps.* = own;
            for (own) |*step| step.* = .{
                .frame = try reader.takeInt(u16, .little),
                .duration = try reader.takeInt(u16, .little),
            };
        }
    }
    art.validate() catch |err| return switch (err) {
        error.InvalidImageBinding => error.InvalidImageBinding,
        else => err,
    };
}

/// The image count, then each image's name, sheet size, frame size, and QOI stream with its
/// byte length (D-182).
fn write_art(allocator: std.mem.Allocator, writer: anytype, art: image_mod.Art) !void {
    try art.validate();
    try writer.writeInt(u32, @intCast(art.images.len), .little);
    for (art.images) |image| {
        try write_str(writer, image.name);
        for ([_]u16{ image.width, image.height, image.frame_width, image.frame_height }) |side| try writer.writeInt(u16, side, .little);
        const stream = try qoi_mod.encode(allocator, image.pixels, image.width, image.height);
        defer allocator.free(stream);
        try writer.writeInt(u32, @intCast(stream.len), .little);
        try writer.writeAll(stream);
    }
}

/// Untrusted input. Each count and size is checked before the bytes behind it are read, so a
/// corrupt package can ask for at most one bounded sheet at a time and 8 MiB of art in all,
/// and `Art.validate` runs on the whole set before the program sees it. Errors name the first
/// thing wrong (D-153, D-182).
fn read_art(allocator: std.mem.Allocator, reader: anytype) !image_mod.Art {
    const image_count = try reader.takeInt(u32, .little);
    if (image_count > image_mod.MAX_IMAGES) return error.InvalidImageCount;
    var images = try std.ArrayListUnmanaged(image_mod.Image).initCapacity(allocator, image_count);
    errdefer {
        for (images.items) |image| image_mod.free_image(allocator, image);
        images.deinit(allocator);
    }
    var total: usize = 0;
    for (0..image_count) |_| {
        const name = try read_str(allocator, reader);
        errdefer allocator.free(name);
        try image_mod.validate_name(name);
        var sides: [4]u16 = undefined;
        for (&sides) |*side| side.* = try reader.takeInt(u16, .little);
        try image_mod.validate_size(sides[0], sides[1], sides[2], sides[3]);
        const count = @as(usize, sides[0]) * sides[1];
        total += count;
        if (total > image_mod.MAX_ART_PIXELS) return error.InvalidImageSize;
        // No stream codes a pixel in more than five bytes, so a longer length is corrupt.
        const len = try reader.takeInt(u32, .little);
        if (len > qoi_mod.HEADER_LEN + 8 + 5 * count) return error.InvalidImageData;
        const stream = try reader.take(len);
        const pixels = qoi_mod.decode(allocator, stream, sides[0], sides[1]) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.QoiAlpha => error.InvalidImagePixel,
            else => error.InvalidImageData,
        };
        images.appendAssumeCapacity(.{
            .name = name,
            .width = sides[0],
            .height = sides[1],
            .frame_width = sides[2],
            .frame_height = sides[3],
            .pixels = pixels,
        });
    }
    var art = image_mod.Art{ .images = try images.toOwnedSlice(allocator) };
    errdefer art.deinit_owned(allocator);
    try art.validate();
    return art;
}

fn write_art_cycles(writer: anytype, art: image_mod.Art) !void {
    try writer.writeInt(u16, @intCast(art.cycles.len), .little);
    for (art.cycles) |cycle| {
        try writer.writeInt(u16, cycle.every, .little);
        try writer.writeInt(u16, @intCast(cycle.colours.len), .little);
        for (cycle.colours) |c| try writer.writeAll(&.{ c.r, c.g, c.b });
    }
}

/// Untrusted input: cycle count and per-cycle colour count are bounded before allocating, and
/// `art.validate()` checks intervals, non-zero bounds, and disjoint RGBs (P49-01, D-190).
fn read_art_cycles(allocator: std.mem.Allocator, reader: anytype, art: *image_mod.Art) !void {
    const count = try reader.takeInt(u16, .little);
    if (count > image_mod.MAX_CYCLES) return error.InvalidImageBinding;
    const cycles = try allocator.alloc(image_mod.ColourCycle, count);
    for (cycles) |*c| c.* = .{ .colours = &.{} };
    art.cycles = cycles;
    for (cycles) |*cycle| {
        cycle.every = try reader.takeInt(u16, .little);
        const len = try reader.takeInt(u16, .little);
        if (len < 2 or len >= image_mod.MAX_COLOURS) return error.InvalidImageBinding;
        const colours = try allocator.alloc(image_mod.Colour, len);
        cycle.colours = colours;
        for (colours) |*c| {
            var rgb: [3]u8 = undefined;
            try reader.readSliceAll(&rgb);
            c.* = .{ .r = rgb[0], .g = rgb[1], .b = rgb[2] };
        }
    }
    art.validate() catch |err| return switch (err) {
        error.InvalidImageBinding => error.InvalidImageBinding,
        else => err,
    };
}

/// Untrusted input: entities must exist; `dilemma.validate` checks the axis, the axis entity,
/// and the points when the whole set is validated.
fn read_appeals(allocator: std.mem.Allocator, world: *const World, reader: anytype) ![]const dilemma_mod.Appeal {
    const count = try reader.takeByte();
    if (count > dilemma_mod.MAX_APPEALS) return error.InvalidDilemmaConfig;
    const appeals = try allocator.alloc(dilemma_mod.Appeal, count);
    errdefer allocator.free(appeals);
    for (appeals) |*appeal| appeal.* = .{
        .axis = RelationKind.from_int(try reader.takeInt(u16, .little)),
        .entity = try read_entity_ref(world, reader),
        .points = try reader.takeInt(i32, .little),
    };
    return appeals;
}

/// Untrusted input: the axis must be a bounded relation; the generated accumulator and step
/// relations are interned from its name, as the compiler does, and validated with the dilemma.
fn read_drifts(allocator: std.mem.Allocator, world: *World, reader: anytype) ![]const dilemma_mod.Drift {
    const count = try reader.takeByte();
    if (count > dilemma_mod.MAX_DRIFTS) return error.InvalidDilemmaConfig;
    const drifts = try allocator.alloc(dilemma_mod.Drift, count);
    errdefer allocator.free(drifts);
    for (drifts) |*drift| {
        const axis = RelationKind.from_int(try reader.takeInt(u16, .little));
        if (world.value_bound(axis) == null) return error.InvalidDilemmaConfig;
        const points = try reader.takeInt(i32, .little);
        const clause = try read_decision_clause(world, reader);
        const rels = dilemma_mod.drift_relations(world, axis) catch return error.InvalidDilemmaConfig;
        drift.* = .{ .axis = axis, .points = points, .clause = clause, .accumulator = rels.accumulator, .spent = rels.spent };
    }
    return drifts;
}

/// Untrusted input: counts are bounded and entities must exist; the caller validates the whole
/// set against the loaded axes, decisions, and red lines, as the compiler does (P45-03).
fn read_dilemma(allocator: std.mem.Allocator, world: *World, axes: []const value_mod.Axis, reader: anytype) !dilemma_mod.Declaration {
    const entity = try read_entity_ref(world, reader);
    const actor = try read_entity_ref(world, reader);
    const cue = try read_entity_ref(world, reader);
    const clause_count = try reader.takeByte();
    if (clause_count == 0 or clause_count > dilemma_mod.MAX_CLAUSES) return error.InvalidDilemmaConfig;
    const clauses = try allocator.alloc(decision_mod.Clause, clause_count);
    errdefer allocator.free(clauses);
    for (clauses) |*clause| clause.* = try read_decision_clause(world, reader);
    const axis = RelationKind.from_int(try reader.takeInt(u16, .little));
    const counter = RelationKind.from_int(try reader.takeInt(u16, .little));
    const lean_count = try reader.takeByte();
    if (lean_count > dilemma_mod.MAX_LEANS) return error.InvalidDilemmaConfig;
    const leans = try allocator.alloc(dilemma_mod.Lean, lean_count);
    errdefer allocator.free(leans);
    for (leans) |*lean| lean.* = .{
        .points = try reader.takeInt(i32, .little),
        .clause = try read_decision_clause(world, reader),
    };
    var responses: [dilemma_mod.TIER_COUNT]dilemma_mod.Response = undefined;
    for (&responses) |*response| response.* = .{
        .line = try read_entity_ref(world, reader),
        .action = try read_entity_ref(world, reader),
    };
    const drifts = try read_drifts(allocator, world, reader);
    errdefer allocator.free(drifts);
    // Each drift line takes its axis's points per step, as the compiler does (D-183).
    for (@constCast(drifts)) |*drift| drift.step = value_mod.drift_step_of(axes, drift.axis);
    const appeals = try read_appeals(allocator, world, reader);
    errdefer allocator.free(appeals);
    const numbers = try reader.takeArray(3);
    return .{ .dilemma = .{
        .entity = entity,
        .actor = actor,
        .cue = cue,
        .clauses = clauses,
        .axis = axis,
        .counter = counter,
        .leans = leans,
        .responses = responses,
        .drifts = drifts,
        .appeals = appeals,
        .strong_at = numbers[0],
        .moderate_at = numbers[1],
        .drift_cap = numbers[2],
    } };
}

/// Untrusted input: counts are bounded and entities must exist; the caller validates the sets
/// against the loaded decisions, as the compiler does (P45-02).
fn read_red_lines(allocator: std.mem.Allocator, world: *const World, reader: anytype) !decision_mod.RedLineDeclaration {
    const actor = try read_entity_ref(world, reader);
    const count = try reader.takeByte();
    if (count == 0 or count > decision_mod.MAX_RED_LINES) return error.InvalidRedLineConfig;
    const options = try allocator.alloc(EntityId, count);
    errdefer allocator.free(options);
    for (options) |*option| option.* = try read_entity_ref(world, reader);
    return .{ .red_lines = .{ .actor = actor, .options = options } };
}

/// Writes the value axes (P45-01): each axis's property relation and its two pole entities.
fn write_axes(writer: anytype, compiled: *const CompiledProgram) !void {
    try writer.writeInt(u32, @intCast(compiled.axes.items.len), .little);
    for (compiled.axes.items) |axis| {
        try writer.writeInt(u16, axis.relation.to_int(), .little);
        for (axis.poles) |pole| try writer.writeInt(u32, pole.to_int(), .little);
        try writer.writeByte(axis.drift_step);
    }
}

/// Untrusted input: the relation must already be a property in the package's relation table,
/// the poles must be entities, and the loader bounds the relation before validating, so a
/// package cannot declare an axis whose range differs from the compiler's (D-144).
fn read_axis(world: *World, reader: anytype) !value_mod.Axis {
    const relation = RelationKind.from_int(try reader.takeInt(u16, .little));
    const meta = world.get_relation_meta(relation) orelse return error.InvalidAxisConfig;
    if (meta.rel_type != .property) return error.InvalidAxisConfig;
    const axis = value_mod.Axis{
        .relation = relation,
        .poles = .{ try read_entity_ref(world, reader), try read_entity_ref(world, reader) },
        .drift_step = try reader.takeByte(),
    };
    world.bound_relation(relation, value_mod.MIN, value_mod.MAX) catch return error.InvalidAxisConfig;
    value_mod.validate(world, axis) catch return error.InvalidAxisConfig;
    return axis;
}

/// Writes one trigger or scoring line; a null subject or object is the `_` wildcard.
fn write_decision_clause(world: *const World, writer: anytype, clause: decision_mod.Clause) !void {
    try write_text_ref(world, writer, clause.relation);
    try writer.writeInt(u32, if (clause.subject) |e| e.to_int() else 0, .little);
    try writer.writeInt(u32, if (clause.object) |e| e.to_int() else 0, .little);
    try writer.writeByte(if (clause.negated) 1 else 0);
}

/// Marks a cue parameter with no guard variable slot in a package (D-072).
const NO_GUARD_SLOT: u8 = 0xFF;
const MAX_CUE_GUARDS: u32 = 4096;
const MAX_GUARD_CLAUSES: u16 = 64;

fn write_pattern_term(writer: anytype, term: PatternTerm) !void {
    switch (term) {
        .wildcard => {
            try writer.writeByte(0);
            try writer.writeInt(u32, 0, .little);
        },
        .constant => |val| {
            try writer.writeByte(1);
            try writer.writeInt(u32, val, .little);
        },
        .variable => |v| {
            try writer.writeByte(2);
            try writer.writeInt(u32, @as(u32, v), .little);
        },
    }
}

fn write_pattern_clause(writer: anytype, clause: PatternClause) !void {
    try writer.writeInt(u16, clause.relation.to_int(), .little);
    try write_pattern_term(writer, clause.subject);
    try write_pattern_term(writer, clause.object);
}

/// Untrusted input: a variable index must name one of the eight binding slots
/// (`VariableBindings`); a larger value would truncate when narrowed to `u8`.
fn read_pattern_term(reader: anytype) !PatternTerm {
    const tag = try reader.takeByte();
    const val = try reader.takeInt(u32, .little);
    return switch (tag) {
        0 => .{ .wildcard = {} },
        1 => .{ .constant = val },
        2 => if (val < 8) .{ .variable = @intCast(val) } else error.InvalidPatternVariable,
        else => error.InvalidPatternTermTag,
    };
}

fn read_pattern_clause(reader: anytype) !PatternClause {
    const rel_kind = try reader.takeInt(u16, .little);
    return .{
        .relation = RelationKind.from_int(rel_kind),
        .subject = try read_pattern_term(reader),
        .object = try read_pattern_term(reader),
    };
}

fn read_entity_ref(world: *const World, reader: anytype) !EntityId {
    const raw = try reader.takeInt(u32, .little);
    if (world.get_entity_name(EntityId.from_int(raw)) == null) return error.InvalidProgramEntity;
    return EntityId.from_int(raw);
}

fn read_optional_index(reader: anytype) !?usize {
    const raw = try reader.takeInt(i32, .little);
    if (raw < -1) return error.InvalidProgramIndex;
    return if (raw < 0) null else @intCast(raw);
}

fn read_optional_waypoint(reader: anytype, waypoint_count: usize) !?spatial_mod.WaypointId {
    const raw = try reader.takeInt(i32, .little);
    if (raw < -1 or raw > waypoint_count or raw == 0) return error.InvalidProgramWaypoint;
    return if (raw < 0) null else @intCast(raw);
}

fn read_waypoint(reader: anytype, waypoint_count: usize) !spatial_mod.WaypointId {
    const value = try reader.takeInt(u16, .little);
    if (value == 0 or value > waypoint_count) return error.InvalidProgramWaypoint;
    return value;
}

fn read_activity(reader: anytype) !society_mod.Activity {
    const raw = try reader.takeByte();
    if (raw > @intFromEnum(society_mod.Activity.arrested)) return error.InvalidProgramActivity;
    return @enumFromInt(raw);
}

fn read_society_declaration(allocator: std.mem.Allocator, world: *const World, reader: anytype, waypoint_count: usize) !society_mod.Declaration {
    const need_count = try reader.takeInt(u32, .little);
    if (need_count == 0 or need_count > society_mod.MAX_NEEDS) return error.InvalidSocietyConfig;
    const needs = try allocator.alloc(society_mod.Need, need_count);
    errdefer allocator.free(needs);
    for (needs) |*need| {
        const name = try read_text_ref(world, reader);
        const worse_raw = try reader.takeByte();
        if (worse_raw > 1) return error.InvalidSocietyConfig;
        const max = try reader.takeInt(u32, .little);
        const rate = try reader.takeInt(u32, .little);
        const resting_rate = try reader.takeInt(u32, .little);
        const seek = try reader.takeInt(u32, .little);
        const kind = try reader.takeByte();
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
                    .restore = try reader.takeInt(u32, .little),
                    .until = try reader.takeInt(u32, .little),
                    .activity = try read_activity(reader),
                    .unaware = switch (try reader.takeByte()) {
                        0 => false,
                        1 => true,
                        else => return error.InvalidSocietyConfig,
                    },
                    .state = try read_text_ref(world, reader),
                    .verb = try read_text_ref(world, reader),
                } },
                1 => blk: {
                    const provider = try read_optional_index(reader);
                    const price = try reader.takeInt(u32, .little);
                    const relief = try reader.takeInt(u32, .little);
                    const floor = try reader.takeInt(u32, .little);
                    const critical_raw = try reader.takeInt(i64, .little);
                    if (critical_raw < -1 or critical_raw > std.math.maxInt(u32)) return error.InvalidSocietyConfig;
                    break :blk .{ .trade = .{
                        .provider = provider,
                        .price = price,
                        .relief = relief,
                        .floor = floor,
                        .critical = if (critical_raw < 0) null else @intCast(critical_raw),
                        .theft_relief = try reader.takeInt(u32, .little),
                        .theft_floor = try reader.takeInt(u32, .little),
                        .item = try read_text_ref(world, reader),
                    } };
                },
                else => return error.InvalidSocietyConfig,
            },
        };
    }

    const member_count = try reader.takeInt(u32, .little);
    if (member_count == 0 or member_count > society_mod.MAX_MEMBERS) return error.InvalidSocietyConfig;
    for (needs) |need| switch (need.satisfy) {
        .trade => |trade| if (trade.provider) |idx| if (idx >= member_count) return error.InvalidSocietyConfig,
        .stay => {},
    };
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
        const member_need_count = try reader.takeInt(u32, .little);
        if (member_need_count != need_count) return error.InvalidSocietyConfig;
        const member_needs = try allocator.alloc(society_mod.MemberNeed, member_need_count);
        errdefer allocator.free(member_needs);
        for (member_needs) |*need| {
            const value = try reader.takeInt(u32, .little);
            const rate_raw = try reader.takeInt(i64, .little);
            if (rate_raw < -1 or rate_raw > std.math.maxInt(u32)) return error.InvalidSocietyConfig;
            const provider = try read_optional_index(reader);
            if (provider) |idx| if (idx >= member_count) return error.InvalidSocietyConfig;
            need.* = .{ .value = value, .rate = if (rate_raw < 0) null else @intCast(rate_raw), .provider = provider };
        }
        const gold = try reader.takeInt(u32, .little);
        const idle = try read_activity(reader);
        const routine_activity_raw = try reader.takeByte();
        if (routine_activity_raw != 255 and routine_activity_raw > @intFromEnum(society_mod.Activity.arrested)) return error.InvalidProgramActivity;
        const stop_count = try reader.takeInt(u16, .little);
        if (stop_count > society_mod.MAX_STOPS) return error.InvalidSocietyConfig;
        const stops = try allocator.alloc(spatial_mod.WaypointId, stop_count);
        errdefer allocator.free(stops);
        for (stops) |*stop| stop.* = try read_waypoint(reader, waypoint_count);
        const period = try reader.takeInt(u64, .little);
        const has_work = try reader.takeByte();
        const work: ?society_mod.Work = switch (has_work) {
            0 => null,
            1 => .{ .at = try read_waypoint(reader, waypoint_count), .every = try reader.takeInt(u64, .little), .earn = try reader.takeInt(u32, .little), .restock = switch (try reader.takeByte()) {
                0 => false,
                1 => true,
                else => return error.InvalidSocietyConfig,
            } },
            else => return error.InvalidSocietyConfig,
        };
        const has_merchant = try reader.takeByte();
        const merchant: ?society_mod.Merchant = switch (has_merchant) {
            0 => null,
            1 => .{ .post = try read_waypoint(reader, waypoint_count), .goods = try read_entity_ref(world, reader) },
            else => return error.InvalidSocietyConfig,
        };
        const broadcaster = switch (try reader.takeByte()) {
            0 => false,
            1 => true,
            else => return error.InvalidSocietyConfig,
        };
        const owns_count = try reader.takeInt(u16, .little);
        if (owns_count > MAX_SOCIETY_ITEMS) return error.InvalidSocietyConfig;
        const owns = try allocator.alloc(EntityId, owns_count);
        errdefer allocator.free(owns);
        for (owns) |*item| item.* = try read_entity_ref(world, reader);
        const carries_count = try reader.takeInt(u16, .little);
        if (carries_count > MAX_SOCIETY_ITEMS) return error.InvalidSocietyConfig;
        const carries = try allocator.alloc(EntityId, carries_count);
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
    if (enforcer) |idx| if (idx >= member_count) return error.InvalidSocietyConfig;
    const holding = try read_optional_waypoint(reader, waypoint_count);
    const gathering = try read_waypoint(reader, waypoint_count);
    const flight_to = try read_waypoint(reader, waypoint_count);
    const flight_then = try read_optional_waypoint(reader, waypoint_count);
    const flight_every = try reader.takeInt(u64, .little);
    const radii = society_mod.Radii{
        .witness = try reader.takeInt(i32, .little),
        .culprit = try reader.takeInt(i32, .little),
        .rumor = try reader.takeInt(i32, .little),
        .arrest = try reader.takeInt(i32, .little),
    };
    const witness_grudge_ticks = try reader.takeInt(u64, .little);
    const rumor_grudge_ticks = try reader.takeInt(u64, .little);
    const warrant_priority = try reader.takeInt(u16, .little);
    const currency_unit = try read_text_ref(world, reader);
    var relation_names: [14][]const u8 = undefined;
    for (&relation_names) |*name| name.* = try read_text_ref(world, reader);
    const friend_count = try reader.takeInt(u32, .little);
    if (friend_count > society_mod.MAX_MEMBERS * society_mod.MAX_MEMBERS) return error.InvalidSocietyConfig;
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
    const pair_count = try reader.takeInt(u32, .little);
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
        const variant_count = try reader.takeByte();
        if (variant_count >= duel_mod.MAX_TIERS) return error.InvalidDuelConfig;
        const variants = try allocator.alloc([]const u8, variant_count);
        errdefer allocator.free(variants);
        for (variants) |*variant| variant.* = try read_text_ref(world, reader);
        pair.* = .{ .name = name, .challenge = challenge, .reply = reply, .variants = variants };
        built += 1;
    }
    const fallback_count = try reader.takeByte();
    const fallback_limit: usize = duel_mod.MAX_FALLBACKS;
    if (fallback_count > fallback_limit) return error.InvalidDuelConfig;
    const fallbacks = try allocator.alloc([]const u8, fallback_count);
    errdefer allocator.free(fallbacks);
    for (fallbacks) |*line| line.* = try read_text_ref(world, reader);
    const win_raw = try reader.takeInt(i64, .little);
    if (win_raw < -1 or win_raw > std.math.maxInt(u32)) return error.InvalidDuelConfig;
    var relations: [7][]const u8 = undefined;
    for (&relations) |*name| name.* = try read_text_ref(world, reader);
    const count_relation = try read_text_ref(world, reader);
    const calm_label = try read_text_ref(world, reader);
    const stage_count = try reader.takeByte();
    if (stage_count == 0 or stage_count > duel_mod.MAX_STAGES) return error.InvalidFatigueConfig;
    const stages = try allocator.alloc(duel_mod.Stage, stage_count);
    errdefer allocator.free(stages);
    for (stages) |*stage| stage.* = .{ .relation = try read_text_ref(world, reader), .at = try reader.takeInt(u32, .little), .ttl = try reader.takeInt(u64, .little), .label = try read_text_ref(world, reader) };
    const tier_count = try reader.takeByte();
    const tiers = try allocator.alloc(duel_mod.TierAssignment, tier_count);
    errdefer allocator.free(tiers);
    for (tiers) |*tier| tier.* = .{ .opponent = try read_entity_ref(world, reader), .tier = try reader.takeInt(u32, .little) };
    return .{
        .config = .{
            .pairs = pairs,
            .fallbacks = fallbacks,
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
fn read_grid_declaration(allocator: std.mem.Allocator, world: *const World, reader: anytype) !grid_mod.Declaration {
    const grid = grid_mod.Grid{
        .entity = try read_entity_ref(world, reader),
        .room = try read_entity_ref(world, reader),
        .width = try reader.takeInt(u16, .little),
        .height = try reader.takeInt(u16, .little),
        .cell_size = try reader.takeInt(u32, .little),
        .origin_x = try reader.takeInt(i32, .little),
        .origin_y = try reader.takeInt(i32, .little),
    };
    grid_mod.validate_grid(grid) catch return error.InvalidGridConfig;
    const attribute_count: usize = std.meta.tags(grid_mod.Attribute).len;
    const cell_count = try reader.takeInt(u32, .little);
    if (cell_count > grid.cell_count() * attribute_count) return error.InvalidGridConfig;
    const cells = try allocator.alloc(grid_mod.InitialCell, cell_count);
    errdefer allocator.free(cells);
    for (cells) |*cell| {
        const index = try reader.takeInt(u32, .little);
        const raw = try reader.takeByte();
        if (raw >= attribute_count) return error.InvalidGridConfig;
        cell.* = .{ .index = index, .attribute = @enumFromInt(raw) };
    }
    var rules = grid_mod.Rules{};
    rules.burn_ticks = try reader.takeInt(u32, .little);
    rules.spread_ticks = try reader.takeInt(u32, .little);
    rules.dissipate_ticks = try reader.takeInt(u32, .little);
    rules.flow_ticks = try reader.takeInt(u32, .little);
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
    const priority = try reader.takeInt(u16, .little);
    const cooldown_ticks = try reader.takeInt(u32, .little);
    const once = try read_flag(reader);
    const clause_count = try reader.takeByte();
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

/// Untrusted input: every entity and text reference, count, tier byte, and hint string is
/// checked before the need reaches the program.
fn read_goal_need(allocator: std.mem.Allocator, world: *const World, reader: anytype) !hint_mod.Need {
    const entity = try read_entity_ref(world, reader);
    const relation = try read_text_ref(world, reader);
    const subject = try read_optional_entity_ref(world, reader);
    const object = try read_optional_entity_ref(world, reader);
    const room = try read_optional_entity_ref(world, reader);
    const after_count = try reader.takeByte();
    if (after_count > hint_mod.MAX_AFTER) return error.InvalidGoalConfig;
    const after = try allocator.alloc(EntityId, after_count);
    errdefer allocator.free(after);
    for (after) |*prerequisite| prerequisite.* = try read_entity_ref(world, reader);
    const hint_count = try reader.takeByte();
    if (hint_count > hint_mod.MAX_TIERS) return error.InvalidGoalConfig;
    const hints = try allocator.alloc(hint_mod.Authored, hint_count);
    var made: usize = 0;
    errdefer {
        for (hints[0..made]) |hint| allocator.free(hint.text);
        allocator.free(hints);
    }
    for (hints) |*hint| {
        const tier = hint_mod.Tier.fromInt(try reader.takeByte()) orelse return error.InvalidGoalConfig;
        hint.* = .{ .tier = tier, .text = try read_str(allocator, reader) };
        made += 1;
    }
    return .{
        .entity = entity,
        .relation = relation,
        .subject = subject,
        .object = object,
        .after = after,
        .room = room,
        .hints = hints,
    };
}

fn read_goal_declaration(allocator: std.mem.Allocator, world: *const World, reader: anytype) !hint_mod.Declaration {
    const entity = try read_entity_ref(world, reader);
    const need_count = try reader.takeInt(u32, .little);
    if (need_count == 0 or need_count > hint_mod.MAX_NEEDS) return error.InvalidGoalConfig;
    const needs = try allocator.alloc(hint_mod.Need, need_count);
    var made: usize = 0;
    errdefer {
        for (needs[0..made]) |need| {
            for (need.hints) |hint| allocator.free(hint.text);
            allocator.free(need.hints);
            allocator.free(need.after);
        }
        allocator.free(needs);
    }
    while (made < needs.len) : (made += 1) needs[made] = try read_goal_need(allocator, world, reader);
    const declaration = hint_mod.Declaration{ .goal = .{ .entity = entity, .needs = needs } };
    hint_mod.validate(declaration) catch return error.InvalidGoalConfig;
    return declaration;
}

/// Untrusted input: counts are bounded, entity ids must exist, and the book is validated again
/// so a package cannot resolve a triple the compiler would have rejected (P44-04).
fn read_decision_clause(world: *const World, reader: anytype) !decision_mod.Clause {
    return .{
        .relation = try read_text_ref(world, reader),
        .subject = try read_optional_entity_ref(world, reader),
        .object = try read_optional_entity_ref(world, reader),
        .negated = try read_flag(reader),
    };
}

fn read_decision_declaration(allocator: std.mem.Allocator, world: *const World, reader: anytype) !decision_mod.Declaration {
    const entity = try read_entity_ref(world, reader);
    const actor = try read_entity_ref(world, reader);
    const cue = try read_entity_ref(world, reader);
    const clause_count = try reader.takeByte();
    if (clause_count == 0 or clause_count > decision_mod.MAX_CLAUSES) return error.InvalidDecisionConfig;
    const clauses = try allocator.alloc(decision_mod.Clause, clause_count);
    errdefer allocator.free(clauses);
    for (clauses) |*clause| clause.* = try read_decision_clause(world, reader);
    const option_count = try reader.takeByte();
    if (option_count == 0 or option_count > decision_mod.MAX_OPTIONS) return error.InvalidDecisionConfig;
    const options = try allocator.alloc(decision_mod.Option, option_count);
    var built: usize = 0;
    errdefer {
        for (options[0..built]) |option| allocator.free(option.picks);
        allocator.free(options);
    }
    for (options) |*option| {
        const option_entity = try read_entity_ref(world, reader);
        const pick_count = try reader.takeByte();
        if (pick_count == 0 or pick_count > decision_mod.MAX_PICKS) return error.InvalidDecisionConfig;
        const picks = try allocator.alloc(decision_mod.Pick, pick_count);
        errdefer allocator.free(picks);
        for (picks) |*pick| pick.* = .{
            .points = try reader.takeInt(i32, .little),
            .clause = try read_decision_clause(world, reader),
        };
        option.* = .{ .entity = option_entity, .picks = picks };
        built += 1;
    }
    const decision = decision_mod.Decision{
        .entity = entity,
        .actor = actor,
        .cue = cue,
        .clauses = clauses,
        .options = options,
    };
    decision_mod.validate(decision) catch return error.InvalidDecisionConfig;
    return .{ .decision = decision };
}

fn read_spellbook_declaration(allocator: std.mem.Allocator, world: *const World, reader: anytype) !spell_mod.Declaration {
    const entity = try read_entity_ref(world, reader);
    const word_count = try reader.takeInt(u32, .little);
    if (word_count == 0 or word_count > spell_mod.MAX_WORDS) return error.InvalidSpellbookConfig;
    const words = try allocator.alloc(spell_mod.Word, word_count);
    errdefer allocator.free(words);
    for (words) |*word| {
        word.entity = try read_entity_ref(world, reader);
        word.kind = spell_mod.Kind.fromInt(try reader.takeByte()) orelse return error.InvalidSpellbookConfig;
        word.tier = try reader.takeInt(u16, .little);
    }
    const spell_count = try reader.takeInt(u32, .little);
    if (spell_count == 0 or spell_count > spell_mod.MAX_SPELLS) return error.InvalidSpellbookConfig;
    const spells = try allocator.alloc(spell_mod.Spell, spell_count);
    errdefer allocator.free(spells);
    for (spells) |*spell| {
        spell.entity = try read_entity_ref(world, reader);
        for (&spell.words) |*word| word.* = try read_entity_ref(world, reader);
    }
    const declaration = spell_mod.Declaration{ .book = .{ .entity = entity, .words = words, .spells = spells } };
    spell_mod.validate(declaration) catch return error.InvalidSpellbookConfig;
    return declaration;
}

/// Untrusted input: frame text must parse, and alias entities, phrase counts, and phrase
/// characters are checked before use.
fn read_command_declaration(allocator: std.mem.Allocator, reader: anytype) !command_mod.CommandDecl {
    const cue = try read_str(allocator, reader);
    errdefer allocator.free(cue);
    const text = try read_str(allocator, reader);
    errdefer allocator.free(text);
    const decl = command_mod.CommandDecl{ .cue = cue, .text = text };
    _ = decl.frame() catch return error.InvalidCommandConfig;
    return decl;
}

fn read_alias_declaration(allocator: std.mem.Allocator, world: *const World, reader: anytype) !command_mod.AliasDecl {
    const entity = try read_entity_ref(world, reader);
    const count = try reader.takeByte();
    if (count == 0 or count > command_mod.MAX_ALIAS_PHRASES) return error.InvalidCommandConfig;
    const phrases = try allocator.alloc([]const u8, count);
    var made: usize = 0;
    errdefer {
        for (phrases[0..made]) |p| allocator.free(p);
        allocator.free(phrases);
    }
    for (phrases) |*phrase| {
        phrase.* = try read_str(allocator, reader);
        made += 1;
    }
    const decl = command_mod.AliasDecl{ .entity = entity, .phrases = phrases };
    decl.validate() catch return error.InvalidCommandConfig;
    return decl;
}

/// Untrusted input: scene counts are bounded and every part's MML is parsed again, so a
/// package cannot hand the audio thread a score the compiler would have rejected.
fn read_score_declaration(allocator: std.mem.Allocator, reader: anytype) !mml.ScoreDecl {
    var decl = mml.ScoreDecl{ .name = try read_str(allocator, reader) };
    var scenes_made: usize = 0;
    var parts_made: usize = 0;
    var scenes: []([]const u8) = &.{};
    errdefer {
        allocator.free(decl.name);
        for (scenes[0..scenes_made]) |scene| allocator.free(scene);
        allocator.free(scenes);
        for (decl.parts[0..parts_made]) |text| allocator.free(text);
    }
    const scene_count = try reader.takeByte();
    if (scene_count > mml.MAX_SCORE_SCENES) return error.InvalidScoreConfig;
    scenes = try allocator.alloc([]const u8, scene_count);
    for (scenes) |*scene| {
        scene.* = try read_str(allocator, reader);
        scenes_made += 1;
    }
    for (&decl.parts) |*text| {
        text.* = try read_str(allocator, reader);
        parts_made += 1;
    }
    decl.scenes = scenes;
    if (decl.name.len == 0) return error.InvalidScoreConfig;
    var diag = mml.Diagnostic{};
    var part: usize = 0;
    decl.validate(allocator, &diag, &part) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidScore => error.InvalidScoreConfig,
    };
    return decl;
}

fn read_flag(reader: anytype) !bool {
    return switch (try reader.takeByte()) {
        0 => false,
        1 => true,
        else => error.InvalidAgendaConfig,
    };
}

fn read_optional_entity_ref(world: *const World, reader: anytype) !?EntityId {
    const raw = try reader.takeInt(u32, .little);
    if (raw == 0) return null;
    if (world.get_entity_name(EntityId.from_int(raw)) == null) return error.InvalidProgramEntity;
    return EntityId.from_int(raw);
}

fn read_degradation_declaration(allocator: std.mem.Allocator, world: *const World, reader: anytype) !container_mod.Declaration {
    const substance = try read_entity_ref(world, reader);
    const spill_per_moving_tick = try reader.takeInt(u32, .little);
    const stage_count = try reader.takeByte();
    if (stage_count < 2 or stage_count > container_mod.MAX_STAGES) return error.InvalidContainerConfig;
    const stages = try allocator.alloc(container_mod.Stage, stage_count);
    errdefer allocator.free(stages);
    for (stages, 0..) |*stage, i| {
        stage.* = .{ .entity = try read_entity_ref(world, reader), .duration_ticks = try reader.takeInt(u64, .little) };
        if ((i == stages.len - 1) != (stage.duration_ticks == 0)) return error.InvalidContainerConfig;
        for (stages[0..i]) |prior| if (prior.entity == stage.entity) return error.InvalidContainerConfig;
    }
    const vessel_count = try reader.takeByte();
    if (vessel_count == 0 or vessel_count > container_mod.MAX_VESSELS) return error.InvalidContainerConfig;
    const vessels = try allocator.alloc(container_mod.Vessel, vessel_count);
    errdefer allocator.free(vessels);
    for (vessels, 0..) |*vessel, i| {
        vessel.* = .{
            .entity = try read_entity_ref(world, reader),
            .capacity = try reader.takeInt(u32, .little),
            .initial_volume = try reader.takeInt(u32, .little),
            .initial_stage = try reader.takeByte(),
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
    var payload = std.array_list.Managed(u8).init(allocator);
    defer payload.deinit();
    var body = std.array_list.Managed(u8).init(allocator);
    defer body.deinit();
    inline for (comptime std.enums.values(Section)) |which| {
        body.clearRetainingCapacity();
        var bw = ListWriter.init(&body);
        if (try write_section(allocator, which, &bw.writer, compiled, world, spatial)) {
            var pw = ListWriter.init(&payload);
            try pw.writer.writeAll(&which.tag());
            try pw.writer.writeByte(which.flags());
            try pw.writer.writeInt(u32, @intCast(body.items.len), .little);
            try pw.writer.writeAll(body.items);
        }
    }
    if (payload.items.len > MAX_PACKAGE_PAYLOAD_SIZE) return error.PackagePayloadTooLarge;
    const crc = std.hash.Crc32.hash(payload.items);
    const payload_size: u32 = @intCast(payload.items.len);
    try writer.writeAll(&PACKAGE_MAGIC);
    try writer.writeInt(u32, PACKAGE_FORMAT, .little);
    try writer.writeInt(u32, crc, .little);
    try writer.writeInt(u32, payload_size, .little);
    try writer.writeAll(payload.items);
}

fn sorted_map_keys(allocator: std.mem.Allocator, map: anytype) ![][]const u8 {
    const keys = try allocator.alloc([]const u8, map.count());
    var i: usize = 0;
    var it = map.keyIterator();
    while (it.next()) |k| : (i += 1) keys[i] = k.*;
    std.mem.sort([]const u8, keys, {}, struct {
        fn less(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.less);
    return keys;
}

/// Writes one section's bytes and says whether the program uses it; an unused section is not
/// written at all. Names and code are always written.
fn write_section(allocator: std.mem.Allocator, comptime which: Section, w: anytype, compiled: *const CompiledProgram, world: *const World, spatial: ?*const SpatialSystem) !bool {
    switch (which) {
        .names => {
            try w.writeInt(u32, @intCast(world.entity_names.items.len), .little);
            for (world.entity_names.items) |name| try write_str(w, name);
            try w.writeInt(u32, @intCast(world.relation_meta.items.len), .little);
            for (world.relation_meta.items) |rel| {
                try write_str(w, rel.name);
                // Low bits: bit 0 is RelationType, bit 1 is `script_owned` (D-180, P48-23).
                // High four bits: ObjectKind (D-178).
                try w.writeByte(
                    @as(u8, if (rel.rel_type == .property) 1 else 0) |
                        (@as(u8, if (rel.script_owned) 2 else 0)) |
                        (@as(u8, @intFromEnum(rel.object_kind)) << 4),
                );
            }
            return true;
        },
        .places => {
            const sp = spatial orelse return false;
            if (sp.graph.waypoints.items.len == 0 and sp.graph.edges.items.len == 0 and sp.hotspots.items.len == 0) return false;
            try w.writeInt(u32, @intCast(sp.graph.waypoints.items.len), .little);
            for (sp.graph.waypoints.items) |wp| {
                try w.writeInt(u32, wp.room.to_int(), .little);
                try w.writeInt(i32, wp.pos.x, .little);
                try w.writeInt(i32, wp.pos.y, .little);
                try write_str(w, wp.name);
            }
            try w.writeInt(u32, @intCast(sp.graph.edges.items.len), .little);
            for (sp.graph.edges.items) |edge| {
                try w.writeInt(u16, edge.from, .little);
                try w.writeInt(u16, edge.to, .little);
                try w.writeInt(u32, edge.cost, .little);
            }
            try w.writeInt(u32, @intCast(sp.hotspots.items.len), .little);
            for (sp.hotspots.items) |hs| {
                try w.writeInt(u32, hs.entity.to_int(), .little);
                try w.writeInt(u32, hs.room.to_int(), .little);
                try w.writeInt(i32, hs.pos.x, .little);
                try w.writeInt(i32, hs.pos.y, .little);
                try w.writeInt(u32, hs.radius, .little);
                try write_str(w, hs.name);
                try write_str(w, hs.examine_text);
            }
            return true;
        },
        .code => {
            if (compiled.chunk.code.items.len > bytecode_mod.MAX_BYTECODE_LEN) return error.BytecodeTooLarge;
            try w.writeInt(u32, @intCast(compiled.chunk.code.items.len), .little);
            try w.writeAll(compiled.chunk.code.items);
            try w.writeInt(i64, if (compiled.initial_entry) |ie| @intCast(ie) else -1, .little);
            const r_keys = try sorted_map_keys(allocator, &compiled.routine_entries);
            defer allocator.free(r_keys);
            try w.writeInt(u32, @intCast(r_keys.len), .little);
            for (r_keys) |key| {
                try write_str(w, key);
                try w.writeInt(u32, @intCast(compiled.routine_entries.get(key).?), .little);
                try write_str(w, compiled.routine_entities.get(key) orelse "");
            }
            const c_keys = try sorted_map_keys(allocator, &compiled.cue_handler_entries);
            defer allocator.free(c_keys);
            try w.writeInt(u32, @intCast(c_keys.len), .little);
            for (c_keys) |key| {
                try write_str(w, key);
                try w.writeInt(u32, @intCast(compiled.cue_handler_entries.get(key).?), .little);
            }
            try write_cue_chain(w, compiled);
            // Which build this is, for saves (D-162), and whether rewinds reroll (D-184).
            try w.writeInt(u32, compiled.save_version, .little);
            try w.writeInt(u64, compiled.fingerprint, .little);
            try w.writeByte(@intFromBool(compiled.rewinds_reroll));
            // The game's clock (D-188).
            try w.writeByte(@intFromBool(compiled.turn_clock));
            return true;
        },
        .rules => {
            if (compiled.when_rule_entries.items.len == 0 and compiled.reactive_rules.items.len == 0) return false;
            try w.writeInt(u32, @intCast(compiled.when_rule_entries.items.len), .little);
            for (compiled.when_rule_entries.items) |pc| try w.writeInt(u32, @intCast(pc), .little);
            try w.writeInt(u32, @intCast(compiled.reactive_rules.items.len), .little);
            for (compiled.reactive_rules.items) |r| {
                try w.writeInt(u32, r.target_entity.to_int(), .little);
                try w.writeInt(u16, r.priority, .little);
                try w.writeInt(u32, @intCast(r.handler_pc), .little);
                try w.writeByte(@intFromEnum(r.edge));
                // `when each` and the variable whose entity runs its body (D-186).
                try w.writeAll(&.{ @intFromBool(r.each), r.owner_slot orelse NO_OWNER_SLOT });
                try w.writeInt(u16, @intCast(r.clauses.len), .little);
                for (r.clauses) |clause| try write_pattern_clause(w, clause);
            }
            return true;
        },
        .drafts => {
            if (compiled.drafts.items.len == 0) return false;
            try w.writeInt(u32, @intCast(compiled.drafts.items.len), .little);
            for (compiled.drafts.items) |d| {
                try w.writeInt(u32, d.entity.to_int(), .little);
                for (d.notes) |n| try w.writeByte(@intFromEnum(n));
                try w.writeByte(if (d.inverse != null) 1 else 0);
                try w.writeInt(u32, if (d.inverse) |inv| inv.to_int() else 0, .little);
            }
            return true;
        },
        .societies => return used(compiled.societies.items.len) and try done(write_societies(world, w, compiled)),
        .duels => return used(compiled.duels.items.len) and try done(write_duels(world, w, compiled)),
        .degradations => return used(compiled.degradations.items.len) and try done(write_degradations(world, w, compiled)),
        .grids => return used(compiled.grids.items.len) and try done(write_grids(world, w, compiled)),
        .agendas => return used(compiled.agendas.items.len) and try done(write_agendas(world, w, compiled)),
        .commands => return used(compiled.commands.items.len + compiled.aliases.items.len) and try done(write_commands(world, w, compiled)),
        .scores => return used(compiled.scores.items.len) and try done(write_scores(world, w, compiled)),
        .cast => return used(compiled.cast.items.len) and try done(write_cast(world, w, compiled)),
        .guards => return used(compiled.cue_guards.items.len) and try done(write_guards(world, w, compiled)),
        .goals => return used(compiled.goals.items.len) and try done(write_goals(world, w, compiled)),
        .spellbooks => return used(compiled.spellbooks.items.len) and try done(write_spellbooks(world, w, compiled)),
        .decisions => return used(compiled.decisions.items.len) and try done(write_decisions(world, w, compiled)),
        .axes => return used(compiled.axes.items.len) and try done(write_axes(w, compiled)),
        .red_lines => return used(compiled.red_lines.items.len) and try done(write_red_lines(world, w, compiled)),
        .dilemmas => return used(compiled.dilemmas.items.len) and try done(write_dilemmas(world, w, compiled)),
        .images => return used(compiled.art.images.len) and try done(write_art(compiled.chunk.allocator, w, compiled.art)),
        .art => {
            const a = compiled.art;
            if (a.backdrops.len + a.sprites.len + a.areas.len + a.looks.len + a.parts.len == 0) return false;
            try write_art_bindings(w, a);
            try w.writeInt(u32, @intCast(a.areas.len), .little);
            for (a.areas) |area| {
                try w.writeInt(u32, area.entity.to_int(), .little);
                for ([_]u16{ area.x, area.y, area.w, area.h }) |v| try w.writeInt(u16, v, .little);
            }
            try write_art_looks(w, a);
            return true;
        },
        .text => {
            var any = world.display_names.count() > 0;
            for (phrase_mod.ENTRIES) |entry| {
                if (world.phrase_override(entry.name) != null) any = true;
            }
            if (!any) return false;
            try write_player_text(world, w);
            return true;
        },
        .cycles => return used(compiled.art.cycles.len) and try done(write_art_cycles(w, compiled.art)),
        .exits => return used(compiled.exits.items.len) and try done(write_exits(w, compiled.exits.items)),
    }
}

/// The most exits a package may hold; one per mark at most, so the waypoint limit bounds it.
const MAX_EXITS: usize = std.math.maxInt(u16);

fn write_exits(w: anytype, exits: []const spatial_mod.Exit) !void {
    try w.writeInt(u16, @intCast(exits.len), .little);
    for (exits) |e| for ([_][]const u8{ e.scene, e.mark, e.to_scene, e.to_mark }) |text| try write_str(w, text);
}

/// Reads the exits and checks each against the loaded world and graph: both scenes are
/// entities, and each mark is a waypoint of its scene. Untrusted input (D-151 item 2).
fn read_exits(allocator: std.mem.Allocator, reader: anytype, world: *const World, spatial: ?*const SpatialSystem) !std.ArrayListUnmanaged(spatial_mod.Exit) {
    var list: std.ArrayListUnmanaged(spatial_mod.Exit) = .empty;
    errdefer free_exits(allocator, &list);
    const count = try reader.takeInt(u16, .little);
    try list.ensureTotalCapacity(allocator, count);
    for (0..count) |_| {
        var texts: [4][]const u8 = undefined;
        var got: usize = 0;
        errdefer for (texts[0..got]) |t| allocator.free(t);
        while (got < 4) : (got += 1) texts[got] = try read_str(allocator, reader);
        list.appendAssumeCapacity(.{ .scene = texts[0], .mark = texts[1], .to_scene = texts[2], .to_mark = texts[3] });
    }
    for (list.items) |e| {
        const from = world.lookup_entity(e.scene) orelse return error.InvalidProgramExit;
        const to = world.lookup_entity(e.to_scene) orelse return error.InvalidProgramExit;
        if (spatial) |sp| {
            if (sp.graph.find_waypoint_in_room(from, e.mark) == null) return error.InvalidProgramExit;
            if (sp.graph.find_waypoint_in_room(to, e.to_mark) == null) return error.InvalidProgramExit;
        }
    }
    return list;
}

fn free_exits(allocator: std.mem.Allocator, list: *std.ArrayListUnmanaged(spatial_mod.Exit)) void {
    for (list.items) |e| for ([_][]const u8{ e.scene, e.mark, e.to_scene, e.to_mark }) |t| allocator.free(t);
    list.deinit(allocator);
}

fn used(count: usize) bool {
    return count > 0;
}

fn done(result: anytype) !bool {
    try result;
    return true;
}

/// The bytes of each section a package holds, found before any is read.
const SectionTable = struct {
    bytes: [SECTION_TAGS.len]?[]const u8 = @splat(null),

    fn get(self: *const SectionTable, which: Section) ?[]const u8 {
        return self.bytes[@intFromEnum(which)];
    }
};

/// Untrusted input: section lengths stay inside the payload, a known tag appears once, flag
/// bits other than `SECTION_REQUIRED` are zero, and an unknown section is skipped only when it
/// is optional.
fn read_section_table(payload: []const u8) !SectionTable {
    var table = SectionTable{};
    var at: usize = 0;
    while (at < payload.len) {
        if (payload.len - at < SECTION_HEADER_LEN) return error.InvalidSection;
        const t: [4]u8 = payload[at..][0..4].*;
        const flags = payload[at + 4];
        const len = std.mem.readInt(u32, payload[at + 5 ..][0..4], .little);
        at += SECTION_HEADER_LEN;
        if (flags & ~SECTION_REQUIRED != 0) return error.InvalidSection;
        if (len > payload.len - at) return error.InvalidSection;
        const bytes = payload[at .. at + len];
        at += len;
        const which = Section.from_tag(t) orelse {
            if (flags & SECTION_REQUIRED != 0) return error.UnknownRequiredSection;
            continue;
        };
        if (table.bytes[@intFromEnum(which)] != null) return error.InvalidSection;
        table.bytes[@intFromEnum(which)] = bytes;
    }
    if (table.get(.names) == null or table.get(.code) == null) return error.InvalidSection;
    return table;
}

/// A section's reader must use every byte of it.
fn finish(stream: *const std.Io.Reader) !void {
    if (stream.seek != stream.end) return error.InvalidSection;
}

/// Loads and validates a binary package stream into a World, SpatialSystem, and CompiledProgram (P15-02, D-018).
pub fn load_package(
    allocator: std.mem.Allocator,
    reader: anytype,
    world: *World,
    spatial: ?*SpatialSystem,
) !CompiledProgram {
    return load_package_linked(ALL_SECTIONS, allocator, reader, world, spatial);
}

/// `load_package` with only the readers for `linked` in the build (D-187); a package holding a
/// section outside it is refused with `UnlinkedSection`. A host whose package is fixed when it
/// is built passes `sections_in` of it.
pub fn load_package_linked(
    comptime linked: SectionSet,
    allocator: std.mem.Allocator,
    reader: anytype,
    world: *World,
    spatial: ?*SpatialSystem,
) !CompiledProgram {
    var raw_header: [16]u8 = undefined;
    const bytes_read = try reader.readSliceShort(&raw_header);
    if (bytes_read < raw_header.len) return error.EndOfStream;
    const magic = raw_header[0..4];
    if (std.mem.eql(u8, magic, &PRE_1_0_MAGIC)) return error.PackageFromBeforeOne;
    if (!std.mem.eql(u8, magic, &PACKAGE_MAGIC)) return error.InvalidPackageMagic;
    const format = std.mem.readInt(u32, raw_header[4..8], .little);
    if (format != PACKAGE_FORMAT) return error.UnsupportedPackageVersion;
    const expected_crc = std.mem.readInt(u32, raw_header[8..12], .little);
    const payload_size = std.mem.readInt(u32, raw_header[12..16], .little);
    if (payload_size > MAX_PACKAGE_PAYLOAD_SIZE) return error.PackagePayloadTooLarge;

    const payload = try allocator.alloc(u8, payload_size);
    defer allocator.free(payload);
    try reader.readSliceAll(payload);
    if (std.hash.Crc32.hash(payload) != expected_crc) return error.ChecksumMismatch;

    const table = try read_section_table(payload);
    inline for (comptime std.enums.values(Section)) |which| {
        if (comptime !linked.contains(which)) {
            if (table.get(which) != null) return error.UnlinkedSection;
        }
    }

    // Names: every entity and relation, so later sections can refer to them by id.
    {
        var stream: std.Io.Reader = .fixed(table.get(.names).?);
        const pr = &stream;
        const entity_count = try pr.takeInt(u32, .little);
        for (0..entity_count) |_| {
            const name = try read_str(allocator, pr);
            defer allocator.free(name);
            _ = try world.intern_entity(name);
        }
        const relation_count = try pr.takeInt(u32, .little);
        for (0..relation_count) |_| {
            const name = try read_str(allocator, pr);
            defer allocator.free(name);
            const flags = try pr.takeByte();
            const low = flags & 0x0f;
            if (low & ~@as(u8, 0x03) != 0) return error.InvalidRelationKind;
            const relation = try world.intern_relation(name, if (low & 0x01 != 0) .property else .set);
            if (low & 0x02 != 0) world.claim_relation(relation);
            const kind = std.enums.fromInt(world_mod.ObjectKind, flags >> 4) orelse return error.InvalidRelationKind;
            world.declare_object_kind(relation, kind) catch return error.InvalidRelationKind;
        }
        try finish(pr);
    }

    // Places: marks, walkways, and hotspots.
    var waypoint_count: usize = 0;
    if (comptime linked.contains(.places)) if (table.get(.places)) |bytes| {
        var stream: std.Io.Reader = .fixed(bytes);
        const pr = &stream;
        const wp_count = try pr.takeInt(u32, .little);
        if (wp_count > MAX_WAYPOINTS) return error.InvalidSection;
        waypoint_count = wp_count;
        for (0..wp_count) |_| {
            const room_int = try pr.takeInt(u32, .little);
            const x = try pr.takeInt(i32, .little);
            const y = try pr.takeInt(i32, .little);
            const name = try read_str(allocator, pr);
            defer allocator.free(name);
            if (spatial) |sp| _ = try sp.graph.add_waypoint(EntityId.from_int(room_int), x, y, name);
        }
        const edge_count = try pr.takeInt(u32, .little);
        if (edge_count > MAX_EDGES) return error.InvalidSection;
        for (0..edge_count) |_| {
            const from = try pr.takeInt(u16, .little);
            const to = try pr.takeInt(u16, .little);
            const cost = try pr.takeInt(u32, .little);
            // The section holds every edge in both directions, as the graph stores them, so
            // each is added as written; `connect` would add its reverse a second time.
            if (spatial) |sp| {
                if (sp.graph.get_waypoint(from) == null or sp.graph.get_waypoint(to) == null) return error.WaypointNotFound;
                try sp.graph.edges.append(.{ .from = from, .to = to, .cost = cost });
            }
        }
        const hotspot_count = try pr.takeInt(u32, .little);
        if (hotspot_count > MAX_HOTSPOTS) return error.InvalidSection;
        for (0..hotspot_count) |_| {
            const ent_int = try pr.takeInt(u32, .little);
            const room_int = try pr.takeInt(u32, .little);
            const x = try pr.takeInt(i32, .little);
            const y = try pr.takeInt(i32, .little);
            const radius = try pr.takeInt(u32, .little);
            const name = try read_str(allocator, pr);
            defer allocator.free(name);
            const desc = try read_str(allocator, pr);
            defer allocator.free(desc);
            if (spatial) |sp| try sp.add_hotspot(EntityId.from_int(ent_int), EntityId.from_int(room_int), .{ .x = x, .y = y }, radius, name, desc);
        }
        try finish(pr);
    };

    // Code: bytecode, entry points, the handler chain, and the program's identity.
    var chunk = BytecodeChunk.init(allocator);
    errdefer chunk.deinit();
    var routine_entries = std.StringHashMap(usize).init(allocator);
    errdefer routine_entries.deinit();
    var routine_entities = std.StringHashMap([]const u8).init(allocator);
    errdefer routine_entities.deinit();
    var allocated_cue_keys = std.array_list.Managed([]const u8).init(allocator);
    errdefer {
        for (allocated_cue_keys.items) |k| allocator.free(k);
        allocated_cue_keys.deinit();
    }
    var cue_handler_entries = std.StringHashMap(usize).init(allocator);
    errdefer cue_handler_entries.deinit();
    var cue_handler_chain: std.AutoHashMapUnmanaged(usize, usize) = .empty;
    errdefer cue_handler_chain.deinit(allocator);
    var initial_entry: ?usize = null;
    var save_version: u32 = 1;
    var fingerprint: u64 = 0;
    var rewinds_reroll = false;
    var turn_clock = false;
    {
        var stream: std.Io.Reader = .fixed(table.get(.code).?);
        const pr = &stream;
        const code_len = try pr.takeInt(u32, .little);
        if (code_len > bytecode_mod.MAX_BYTECODE_LEN) return error.BytecodeTooLarge;
        try chunk.code.appendSlice(try pr.take(code_len));
        bytecode_mod.validate(chunk.code.items) catch |err| return switch (err) {
            error.BytecodeTooLarge => error.BytecodeTooLarge,
            else => error.InvalidBytecode,
        };
        const ie = try pr.takeInt(i64, .little);
        if (ie < -1 or ie >= @as(i64, code_len)) return error.InvalidProgramIndex;
        initial_entry = if (ie >= 0) @intCast(ie) else null;
        const routine_count = try pr.takeInt(u32, .little);
        for (0..routine_count) |_| {
            const rname = try read_str(allocator, pr);
            var rname_owned = true;
            errdefer if (rname_owned) allocator.free(rname);
            const pc = try pr.takeInt(u32, .little);
            if (pc >= code_len) return error.InvalidProgramIndex;
            const actor = try read_str(allocator, pr);
            var actor_owned = true;
            errdefer if (actor_owned) allocator.free(actor);
            try allocated_cue_keys.ensureUnusedCapacity(2);
            allocated_cue_keys.appendAssumeCapacity(rname);
            rname_owned = false;
            allocated_cue_keys.appendAssumeCapacity(actor);
            actor_owned = false;
            try routine_entries.put(rname, pc);
            try routine_entities.put(rname, actor);
        }
        const cue_count = try pr.takeInt(u32, .little);
        for (0..cue_count) |_| {
            const sig = try read_str(allocator, pr);
            var sig_owned = true;
            errdefer if (sig_owned) allocator.free(sig);
            const pc = try pr.takeInt(u32, .little);
            if (pc >= code_len) return error.InvalidProgramIndex;
            try allocated_cue_keys.append(sig);
            sig_owned = false;
            try cue_handler_entries.put(sig, pc);
        }
        cue_handler_chain = try read_cue_chain(allocator, pr, &cue_handler_entries, code_len);
        save_version = try pr.takeInt(u32, .little);
        fingerprint = try pr.takeInt(u64, .little);
        // Zero means "unknown program" in a save, so no build may claim it (D-162).
        if (save_version == 0 or fingerprint == 0) return error.InvalidProgramIdentity;
        const flag = try pr.takeByte();
        if (flag > 1) return error.InvalidProgramIdentity;
        rewinds_reroll = flag == 1;
        const clock = try pr.takeByte();
        if (clock > 1) return error.InvalidProgramIdentity;
        turn_clock = clock == 1;
        try finish(pr);
    }
    const code_len = chunk.code.items.len;

    // Rules: `when` entry points and reactive rules.
    var when_rule_entries = std.array_list.Managed(usize).init(allocator);
    errdefer when_rule_entries.deinit();
    var reactive_rules = std.array_list.Managed(CompiledWhenRule).init(allocator);
    errdefer {
        for (reactive_rules.items) |r| allocator.free(r.clauses);
        reactive_rules.deinit();
    }
    if (comptime linked.contains(.rules)) if (table.get(.rules)) |bytes| {
        var stream: std.Io.Reader = .fixed(bytes);
        const pr = &stream;
        const entry_count = try pr.takeInt(u32, .little);
        if (entry_count > bytes.len / 4) return error.InvalidSection;
        try when_rule_entries.ensureTotalCapacity(entry_count);
        for (0..entry_count) |_| {
            const pc = try pr.takeInt(u32, .little);
            if (pc >= code_len) return error.InvalidProgramIndex;
            when_rule_entries.appendAssumeCapacity(pc);
        }
        const rule_count = try pr.takeInt(u32, .little);
        for (0..rule_count) |_| {
            const tent = try pr.takeInt(u32, .little);
            const priority = try pr.takeInt(u16, .little);
            const handler_pc = try pr.takeInt(u32, .little);
            if (handler_pc >= code_len) return error.InvalidProgramIndex;
            const edge: WhenEdge = switch (try pr.takeByte()) {
                0 => .rising,
                1 => .falling,
                2 => .on_expire,
                3 => .on_arrive,
                else => return error.InvalidWhenEdge,
            };
            const each_bytes = try pr.takeArray(2);
            const clause_count = try pr.takeInt(u16, .little);
            if (clause_count > MAX_GUARD_CLAUSES) return error.InvalidSection;
            const clauses = try allocator.alloc(PatternClause, clause_count);
            var clauses_owned = true;
            errdefer if (clauses_owned) allocator.free(clauses);
            for (clauses) |*cl| cl.* = try read_pattern_clause(pr);
            var rule = CompiledWhenRule{ .clauses = clauses, .target_entity = EntityId.from_int(tent), .priority = priority, .handler_pc = handler_pc, .edge = edge };
            try read_each(&rule, each_bytes.*);
            try reactive_rules.append(rule);
            clauses_owned = false;
        }
        try finish(pr);
    };

    // Drafts. Untrusted input: note bytes and entity ids are checked against the note range
    // and the entity table loaded above before entering the program.
    var drafts = std.array_list.Managed(draft_mod.CompiledDraft).init(allocator);
    errdefer drafts.deinit();
    if (comptime linked.contains(.drafts)) if (table.get(.drafts)) |bytes| {
        var stream: std.Io.Reader = .fixed(bytes);
        const pr = &stream;
        const draft_count = try pr.takeInt(u32, .little);
        const entity_limit = world.entity_names.items.len;
        for (0..draft_count) |_| {
            const ent_raw = try pr.takeInt(u32, .little);
            var notes: draft_mod.Notes = undefined;
            for (&notes) |*n| n.* = draft_mod.Note.from_int(try pr.takeByte()) orelse return error.InvalidDraftNote;
            const has_inverse = try pr.takeByte();
            const inv_raw = try pr.takeInt(u32, .little);
            if (ent_raw == 0 or ent_raw > entity_limit) return error.InvalidDraftEntity;
            if (has_inverse > 1) return error.InvalidDraftEntity;
            if (has_inverse == 1 and (inv_raw == 0 or inv_raw > entity_limit)) return error.InvalidDraftEntity;
            try drafts.append(.{ .entity = EntityId.from_int(ent_raw), .notes = notes, .inverse = if (has_inverse == 1) EntityId.from_int(inv_raw) else null });
        }
        try finish(pr);
    };

    var societies = std.array_list.Managed(society_mod.Declaration).init(allocator);
    errdefer {
        for (societies.items) |*decl| decl.deinit_owned(allocator);
        societies.deinit();
    }
    if (comptime linked.contains(.societies)) if (table.get(.societies)) |bytes| {
        var stream: std.Io.Reader = .fixed(bytes);
        const count = try stream.takeInt(u32, .little);
        if (count > MAX_SOCIETIES) return error.InvalidSocietyConfig;
        for (0..count) |_| {
            var decl = try read_society_declaration(allocator, world, &stream, waypoint_count);
            societies.append(decl) catch |err| {
                decl.deinit_owned(allocator);
                return err;
            };
        }
        try finish(&stream);
    };
    var duels = std.array_list.Managed(duel_mod.Declaration).init(allocator);
    errdefer {
        for (duels.items) |*decl| decl.deinit_owned(allocator);
        duels.deinit();
    }
    if (comptime linked.contains(.duels)) if (table.get(.duels)) |bytes| {
        var stream: std.Io.Reader = .fixed(bytes);
        const count = try stream.takeInt(u32, .little);
        if (count > MAX_DUELS) return error.InvalidDuelConfig;
        for (0..count) |_| {
            var decl = try read_duel_declaration(allocator, world, &stream);
            duels.append(decl) catch |err| {
                decl.deinit_owned(allocator);
                return err;
            };
        }
        try finish(&stream);
    };
    var degradations = std.array_list.Managed(container_mod.Declaration).init(allocator);
    errdefer {
        for (degradations.items) |*decl| decl.deinit_owned(allocator);
        degradations.deinit();
    }
    if (comptime linked.contains(.degradations)) if (table.get(.degradations)) |bytes| {
        var stream: std.Io.Reader = .fixed(bytes);
        const count = try stream.takeInt(u32, .little);
        if (count > MAX_DEGRADATIONS) return error.InvalidContainerConfig;
        for (0..count) |_| {
            var decl = try read_degradation_declaration(allocator, world, &stream);
            degradations.append(decl) catch |err| {
                decl.deinit_owned(allocator);
                return err;
            };
        }
        try finish(&stream);
    };
    var grids = std.array_list.Managed(grid_mod.Declaration).init(allocator);
    errdefer {
        for (grids.items) |*decl| decl.deinit_owned(allocator);
        grids.deinit();
    }
    if (comptime linked.contains(.grids)) if (table.get(.grids)) |bytes| {
        var stream: std.Io.Reader = .fixed(bytes);
        const count = try stream.takeInt(u32, .little);
        if (count > grid_mod.MAX_GRIDS) return error.InvalidGridConfig;
        for (0..count) |_| {
            var decl = try read_grid_declaration(allocator, world, &stream);
            grids.append(decl) catch |err| {
                decl.deinit_owned(allocator);
                return err;
            };
            if (spatial) |sp| sp.add_grid(decl.grid) catch return error.InvalidGridConfig;
        }
        try finish(&stream);
    };
    var agendas = std.array_list.Managed(agency_mod.Declaration).init(allocator);
    errdefer {
        for (agendas.items) |*decl| decl.deinit_owned(allocator);
        agendas.deinit();
    }
    if (comptime linked.contains(.agendas)) if (table.get(.agendas)) |bytes| {
        var stream: std.Io.Reader = .fixed(bytes);
        const count = try stream.takeInt(u32, .little);
        if (count > agency_mod.MAX_AGENDAS) return error.InvalidAgendaConfig;
        for (0..count) |_| {
            var decl = try read_agenda_declaration(allocator, world, &stream);
            agendas.append(decl) catch |err| {
                decl.deinit_owned(allocator);
                return err;
            };
        }
        agency_mod.validate_all(agendas.items) catch return error.InvalidAgendaConfig;
        try finish(&stream);
    };
    var commands = std.array_list.Managed(command_mod.CommandDecl).init(allocator);
    errdefer {
        for (commands.items) |*decl| decl.deinit_owned(allocator);
        commands.deinit();
    }
    var aliases = std.array_list.Managed(command_mod.AliasDecl).init(allocator);
    errdefer {
        for (aliases.items) |*decl| decl.deinit_owned(allocator);
        aliases.deinit();
    }
    if (comptime linked.contains(.commands)) if (table.get(.commands)) |bytes| {
        var stream: std.Io.Reader = .fixed(bytes);
        const command_count = try stream.takeInt(u32, .little);
        if (command_count > 256) return error.InvalidCommandConfig;
        for (0..command_count) |_| {
            var decl = try read_command_declaration(allocator, &stream);
            commands.append(decl) catch |err| {
                decl.deinit_owned(allocator);
                return err;
            };
        }
        const alias_count = try stream.takeInt(u32, .little);
        if (alias_count > 256) return error.InvalidCommandConfig;
        for (0..alias_count) |_| {
            var decl = try read_alias_declaration(allocator, world, &stream);
            aliases.append(decl) catch |err| {
                decl.deinit_owned(allocator);
                return err;
            };
        }
        try finish(&stream);
    };
    var scores = std.array_list.Managed(mml.ScoreDecl).init(allocator);
    errdefer {
        for (scores.items) |*decl| decl.deinit_owned(allocator);
        scores.deinit();
    }
    if (comptime linked.contains(.scores)) if (table.get(.scores)) |bytes| {
        var stream: std.Io.Reader = .fixed(bytes);
        const count = try stream.takeInt(u32, .little);
        if (count > 256) return error.InvalidScoreConfig;
        for (0..count) |_| {
            var decl = try read_score_declaration(allocator, &stream);
            scores.append(decl) catch |err| {
                decl.deinit_owned(allocator);
                return err;
            };
        }
        try finish(&stream);
    };
    var cast = std.ArrayListUnmanaged(codegen_mod.CastPlace).empty;
    errdefer cast.deinit(allocator);
    if (comptime linked.contains(.cast)) if (table.get(.cast)) |bytes| {
        var stream: std.Io.Reader = .fixed(bytes);
        const count = try stream.takeInt(u32, .little);
        if (count > MAX_CAST) return error.InvalidCastConfig;
        try cast.ensureTotalCapacity(allocator, count);
        for (0..count) |_| {
            const actor = try read_entity_ref(world, &stream);
            const mark = try read_waypoint(&stream, waypoint_count);
            cast.appendAssumeCapacity(.{ .actor = actor, .mark = mark });
        }
        try finish(&stream);
    };
    var cue_guards = std.ArrayListUnmanaged(codegen_mod.CueGuard).empty;
    errdefer {
        for (cue_guards.items) |guard| allocator.free(guard.clauses);
        cue_guards.deinit(allocator);
    }
    if (comptime linked.contains(.guards)) if (table.get(.guards)) |bytes| {
        var stream: std.Io.Reader = .fixed(bytes);
        const pr = &stream;
        const count = try pr.takeInt(u32, .little);
        if (count > MAX_CUE_GUARDS) return error.InvalidCueGuard;
        try cue_guards.ensureTotalCapacity(allocator, count);
        for (0..count) |_| {
            const handler_pc = try pr.takeInt(u32, .little);
            // A guard belongs to a cue handler: the first of its signature or a chained one.
            if (handler_pc >= code_len) return error.InvalidCueGuard;
            if (!is_first_handler(&cue_handler_entries, handler_pc) and !is_chained_handler(&cue_handler_chain, handler_pc)) return error.InvalidCueGuard;
            var guard = codegen_mod.CueGuard{ .handler_pc = handler_pc, .clauses = &.{} };
            for (&guard.param_slots) |*slot| {
                const raw = try pr.takeByte();
                slot.* = if (raw == NO_GUARD_SLOT) null else if (raw < 8) raw else return error.InvalidCueGuard;
            }
            const clause_count = try pr.takeInt(u16, .little);
            if (clause_count == 0 or clause_count > MAX_GUARD_CLAUSES) return error.InvalidCueGuard;
            const clauses = try allocator.alloc(PatternClause, clause_count);
            errdefer allocator.free(clauses);
            for (clauses) |*cl| cl.* = try read_pattern_clause(pr);
            guard.clauses = clauses;
            cue_guards.appendAssumeCapacity(guard);
        }
        try finish(pr);
    };
    var goals = std.array_list.Managed(hint_mod.Declaration).init(allocator);
    errdefer {
        for (goals.items) |*decl| decl.deinit_owned(allocator);
        goals.deinit();
    }
    if (comptime linked.contains(.goals)) if (table.get(.goals)) |bytes| {
        var stream: std.Io.Reader = .fixed(bytes);
        const count = try stream.takeInt(u32, .little);
        if (count > hint_mod.MAX_GOALS) return error.InvalidGoalConfig;
        for (0..count) |_| {
            var decl = try read_goal_declaration(allocator, world, &stream);
            goals.append(decl) catch |err| {
                decl.deinit_owned(allocator);
                return err;
            };
        }
        hint_mod.validate_all(goals.items) catch return error.InvalidGoalConfig;
        try finish(&stream);
    };
    var spellbooks = std.array_list.Managed(spell_mod.Declaration).init(allocator);
    errdefer {
        for (spellbooks.items) |*decl| decl.deinit_owned(allocator);
        spellbooks.deinit();
    }
    if (comptime linked.contains(.spellbooks)) if (table.get(.spellbooks)) |bytes| {
        var stream: std.Io.Reader = .fixed(bytes);
        const count = try stream.takeInt(u32, .little);
        if (count > spell_mod.MAX_BOOKS) return error.InvalidSpellbookConfig;
        for (0..count) |_| {
            var decl = try read_spellbook_declaration(allocator, world, &stream);
            spellbooks.append(decl) catch |err| {
                decl.deinit_owned(allocator);
                return err;
            };
        }
        spell_mod.validate_all(spellbooks.items) catch return error.InvalidSpellbookConfig;
        try finish(&stream);
    };
    var decisions = std.array_list.Managed(decision_mod.Declaration).init(allocator);
    errdefer {
        for (decisions.items) |*decl| decl.deinit_owned(allocator);
        decisions.deinit();
    }
    if (comptime linked.contains(.decisions)) if (table.get(.decisions)) |bytes| {
        var stream: std.Io.Reader = .fixed(bytes);
        const count = try stream.takeInt(u32, .little);
        if (count > decision_mod.MAX_DECISIONS) return error.InvalidDecisionConfig;
        for (0..count) |_| {
            var decl = try read_decision_declaration(allocator, world, &stream);
            decisions.append(decl) catch |err| {
                decl.deinit_owned(allocator);
                return err;
            };
        }
        decision_mod.validate_all(decisions.items) catch return error.InvalidDecisionConfig;
        try finish(&stream);
    };
    var axes = std.array_list.Managed(value_mod.Axis).init(allocator);
    errdefer axes.deinit();
    if (comptime linked.contains(.axes)) if (table.get(.axes)) |bytes| {
        var stream: std.Io.Reader = .fixed(bytes);
        const count = try stream.takeInt(u32, .little);
        if (count > value_mod.MAX_AXES) return error.InvalidAxisConfig;
        for (0..count) |_| try axes.append(try read_axis(world, &stream));
        value_mod.validate_all(world, axes.items) catch return error.InvalidAxisConfig;
        try finish(&stream);
    };
    var red_lines = std.array_list.Managed(decision_mod.RedLineDeclaration).init(allocator);
    errdefer {
        for (red_lines.items) |*decl| decl.deinit_owned(allocator);
        red_lines.deinit();
    }
    if (comptime linked.contains(.red_lines)) if (table.get(.red_lines)) |bytes| {
        var stream: std.Io.Reader = .fixed(bytes);
        const count = try stream.takeInt(u32, .little);
        if (count > decision_mod.MAX_RED_LINE_SETS) return error.InvalidRedLineConfig;
        for (0..count) |_| {
            var decl = try read_red_lines(allocator, world, &stream);
            red_lines.append(decl) catch |err| {
                decl.deinit_owned(allocator);
                return err;
            };
        }
        decision_mod.validate_red_lines(decisions.items, red_lines.items) catch return error.InvalidRedLineConfig;
        try finish(&stream);
    };
    var dilemmas = std.array_list.Managed(dilemma_mod.Declaration).init(allocator);
    errdefer {
        for (dilemmas.items) |*decl| decl.deinit_owned(allocator);
        dilemmas.deinit();
    }
    if (comptime linked.contains(.dilemmas)) if (table.get(.dilemmas)) |bytes| {
        var stream: std.Io.Reader = .fixed(bytes);
        const count = try stream.takeInt(u32, .little);
        if (count > dilemma_mod.MAX_DILEMMAS) return error.InvalidDilemmaConfig;
        for (0..count) |_| {
            var decl = try read_dilemma(allocator, world, axes.items, &stream);
            dilemmas.append(decl) catch |err| {
                decl.deinit_owned(allocator);
                return err;
            };
        }
        dilemma_mod.validate_all(world, dilemmas.items, decisions.items, red_lines.items) catch return error.InvalidDilemmaConfig;
        try finish(&stream);
    };
    var art = image_mod.Art{};
    errdefer art.deinit_owned(allocator);
    if (comptime linked.contains(.images)) if (table.get(.images)) |bytes| {
        var stream: std.Io.Reader = .fixed(bytes);
        art = try read_art(allocator, &stream);
        try finish(&stream);
    };
    if (comptime linked.contains(.art)) if (table.get(.art)) |bytes| {
        var stream: std.Io.Reader = .fixed(bytes);
        try read_art_bindings(allocator, world, &stream, &art);
        try read_art_areas(allocator, world, &stream, &art);
        try read_art_looks(allocator, world, &stream, &art);
        try finish(&stream);
    };
    if (comptime linked.contains(.text)) if (table.get(.text)) |bytes| {
        var stream: std.Io.Reader = .fixed(bytes);
        try read_player_text(allocator, world, &stream);
        try finish(&stream);
    };
    if (comptime linked.contains(.cycles)) if (table.get(.cycles)) |bytes| {
        var stream: std.Io.Reader = .fixed(bytes);
        try read_art_cycles(allocator, &stream, &art);
        try finish(&stream);
    };
    var exits: std.ArrayListUnmanaged(spatial_mod.Exit) = .empty;
    errdefer free_exits(allocator, &exits);
    if (comptime linked.contains(.exits)) if (table.get(.exits)) |bytes| {
        var stream: std.Io.Reader = .fixed(bytes);
        exits = try read_exits(allocator, &stream, world, spatial);
        try finish(&stream);
    };

    return CompiledProgram{
        .drafts = drafts,
        .chunk = chunk,
        .routine_entries = routine_entries,
        .routine_entities = routine_entities,
        .when_rule_entries = when_rule_entries,
        .cue_handler_entries = cue_handler_entries,
        .allocated_cue_keys = allocated_cue_keys,
        .allocated_routine_names = std.array_list.Managed([]const u8).init(allocator),
        .reactive_rules = reactive_rules,
        .initial_entry = initial_entry,
        .societies = societies,
        .duels = duels,
        .degradations = degradations,
        .grids = grids,
        .agendas = agendas,
        .goals = goals,
        .spellbooks = spellbooks,
        .decisions = decisions,
        .axes = axes,
        .red_lines = red_lines,
        .dilemmas = dilemmas,
        .commands = commands,
        .aliases = aliases,
        .scores = scores,
        .cast = cast,
        .cue_guards = cue_guards,
        .cue_handler_chain = cue_handler_chain,
        .save_version = save_version,
        .rewinds_reroll = rewinds_reroll,
        .turn_clock = turn_clock,
        .fingerprint = fingerprint,
        .art = art,
        .exits = exits,
    };
}

/// Untrusted input: `each` is only on a rising rule, and an owner slot must be the variable the
/// first clause's subject is (D-186).
fn read_each(rule: *CompiledWhenRule, bytes: [2]u8) !void {
    if (bytes[0] > 1) return error.InvalidWhenEdge;
    rule.each = bytes[0] == 1;
    if (rule.each and rule.edge != .rising) return error.InvalidWhenEdge;
    if (bytes[1] == NO_OWNER_SLOT) return;
    if (!rule.each or rule.clauses.len == 0) return error.InvalidWhenEdge;
    switch (rule.clauses[0].subject) {
        .variable => |slot| if (slot != bytes[1]) return error.InvalidWhenEdge,
        else => return error.InvalidWhenEdge,
    }
    rule.owner_slot = bytes[1];
}

/// Saves a compiled program package directly to a file on disk (P15-02).
pub fn save_package_file(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    compiled: *const CompiledProgram,
    world: *const World,
    spatial: ?*const SpatialSystem,
) !void {
    const file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    var buf: [4096]u8 = undefined;
    var file_writer = file.writer(io, &buf);
    try save_package(allocator, &file_writer.interface, compiled, world, spatial);
    try file_writer.interface.flush();
}

/// Loads a compiled program package directly from a file on disk (P15-02).
pub fn load_package_file(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    world: *World,
    spatial: ?*SpatialSystem,
) !CompiledProgram {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    var buf: [4096]u8 = undefined;
    var file_reader = file.reader(io, &buf);
    return try load_package(allocator, &file_reader.interface, world, spatial);
}

// =========================================================================
// Unit Tests (P15-02)
// =========================================================================


// --- Tests (P48-17, D-172, D-187) ---

fn compile_for_test(allocator: std.mem.Allocator, world: *World, spatial: ?*SpatialSystem, source: []const u8) !CompiledProgram {
    return @import("compiler.zig").compile_source(allocator, world, spatial, source);
}

/// Writes `source`'s program as a package into `out`.
fn package_of(allocator: std.mem.Allocator, source: []const u8, out: *std.array_list.Managed(u8)) !void {
    var world = try World.init(allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(allocator);
    defer spatial.deinit();
    var compiled = try compile_for_test(allocator, &world, &spatial, source);
    defer compiled.deinit();
    var lw = ListWriter.init(out);
    try save_package(allocator, &lw.writer, &compiled, &world, &spatial);
}

fn load_for_test(bytes: []const u8) !CompiledProgram {
    var world = try World.init(std.testing.allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(std.testing.allocator);
    defer spatial.deinit();
    var stream: std.Io.Reader = .fixed(bytes);
    return load_package(std.testing.allocator, &stream, &world, &spatial);
}

/// The sections a package holds, read at run time, for tests.
fn sections_of(bytes: []const u8) !SectionSet {
    const table = try read_section_table(bytes[@sizeOf(PackageHeader)..]);
    var set = SectionSet.empty;
    for (table.bytes, 0..) |b, k| if (b != null) set.insert(@enumFromInt(k));
    return set;
}

/// The mutable bytes of one section, for tests that break it.
fn section_slice(bytes: []u8, which: Section) []u8 {
    var at: usize = @sizeOf(PackageHeader);
    while (at + SECTION_HEADER_LEN <= bytes.len) {
        const len = std.mem.readInt(u32, bytes[at + 5 ..][0..4], .little);
        if (std.mem.eql(u8, bytes[at..][0..4], &which.tag())) return bytes[at + SECTION_HEADER_LEN ..][0..len];
        at += SECTION_HEADER_LEN + len;
    }
    unreachable;
}

/// Recomputes a package's checksum after a test changed its payload.
fn reseal_for_test(bytes: []u8) void {
    const header: *align(1) PackageHeader = @ptrCast(bytes[0..@sizeOf(PackageHeader)]);
    header.payload_size = @intCast(bytes.len - @sizeOf(PackageHeader));
    header.crc32 = std.hash.Crc32.hash(bytes[@sizeOf(PackageHeader)..]);
}

/// One script per part of a program, each read from `tests/fixtures/sections/` when the test
/// runs, with the section it must produce.
const ROUND_TRIPS = [_]struct { file: []const u8, section: Section }{
    .{ .file = "drafts.bespoke", .section = .drafts },
    .{ .file = "degradations.bespoke", .section = .degradations },
    .{ .file = "grids.bespoke", .section = .grids },
    .{ .file = "agendas.bespoke", .section = .agendas },
    .{ .file = "commands.bespoke", .section = .commands },
    .{ .file = "scores.bespoke", .section = .scores },
    .{ .file = "paths.bespoke", .section = .code },
    .{ .file = "arrival.bespoke", .section = .rules },
    .{ .file = "society-and-duel.bespoke", .section = .societies },
    .{ .file = "cast.bespoke", .section = .cast },
    .{ .file = "guards.bespoke", .section = .guards },
    .{ .file = "goals.bespoke", .section = .goals },
    .{ .file = "looks-and-parts.bespoke", .section = .art },
    .{ .file = "spellbook.bespoke", .section = .spellbooks },
    .{ .file = "decision.bespoke", .section = .decisions },
    .{ .file = "axes.bespoke", .section = .axes },
    .{ .file = "red-lines.bespoke", .section = .red_lines },
    .{ .file = "dilemma.bespoke", .section = .dilemmas },
    .{ .file = "drift.bespoke", .section = .dilemmas },
    .{ .file = "appeal.bespoke", .section = .dilemmas },
    .{ .file = "sprites.bespoke", .section = .images },
    .{ .file = "areas.bespoke", .section = .art },
    .{ .file = "tuning.bespoke", .section = .dilemmas },
};

fn round_trip_source(allocator: std.mem.Allocator, index: usize) ![]u8 {
    var path_buf: [96]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "tests/fixtures/sections/{s}", .{ROUND_TRIPS[index].file});
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, allocator, .limited(64 * 1024));
}

test "P48-17: every part of a program round-trips through its own section, byte for byte" {
    const testing = std.testing;
    for (ROUND_TRIPS, 0..) |case, k| {
        errdefer std.debug.print("round trip '{s}'\n", .{case.file});
        const source = try round_trip_source(testing.allocator, k);
        defer testing.allocator.free(source);
        var first = std.array_list.Managed(u8).init(testing.allocator);
        defer first.deinit();
        try package_of(testing.allocator, source, &first);
        try testing.expectEqualSlices(u8, &PACKAGE_MAGIC, first.items[0..4]);
        try testing.expectEqual(PACKAGE_FORMAT, version_from_bytes(first.items).?);
        const sections = try sections_of(first.items);
        try testing.expect(sections.contains(.names) and sections.contains(.code) and sections.contains(case.section));

        // Loading and saving again writes the same bytes.
        var world = try World.init(testing.allocator, 1024 * 1024);
        defer world.deinit();
        var spatial = SpatialSystem.init(testing.allocator);
        defer spatial.deinit();
        var stream: std.Io.Reader = .fixed(first.items);
        var loaded = try load_package(testing.allocator, &stream, &world, &spatial);
        defer loaded.deinit();
        var again = std.array_list.Managed(u8).init(testing.allocator);
        defer again.deinit();
        var lw = ListWriter.init(&again);
        try save_package(testing.allocator, &lw.writer, &loaded, &world, &spatial);
        try testing.expectEqualSlices(u8, first.items, again.items);
    }
}

const SMALL_SCRIPT =
    \\entity Hero
    \\relation Ready(who)
    \\routine Idle(Hero):
    \\  wait 1 ticks
    \\  remember Ready(Hero)
    \\
;

test "P48-17: a package writes only the sections its program uses" {
    const testing = std.testing;
    var bytes = std.array_list.Managed(u8).init(testing.allocator);
    defer bytes.deinit();
    try package_of(testing.allocator, SMALL_SCRIPT, &bytes);
    const sections = try sections_of(bytes.items);
    try testing.expectEqual(@as(usize, 2), sections.count());
    try testing.expect(sections.contains(.names) and sections.contains(.code));
    var compiled = try load_for_test(bytes.items);
    defer compiled.deinit();
    try testing.expect(compiled.routine_entries.contains("Idle"));
    try testing.expect(compiled.art.is_empty());
}

test "P48-17: an unknown optional section is skipped and an unknown required one refused" {
    const testing = std.testing;
    var bytes = std.array_list.Managed(u8).init(testing.allocator);
    defer bytes.deinit();
    try package_of(testing.allocator, SMALL_SCRIPT, &bytes);
    const Case = struct { tag: [4]u8, flags: u8, err: ?anyerror };
    const cases = [_]Case{
        // A later 1.x section a 1.0 reader does not know, marked optional: the program loads.
        .{ .tag = "LIPS".*, .flags = 0, .err = null },
        .{ .tag = "LIPS".*, .flags = SECTION_REQUIRED, .err = error.UnknownRequiredSection },
        // A flag bit 1.0 does not define, and a known section twice, are corrupt.
        .{ .tag = "LIPS".*, .flags = 2, .err = error.InvalidSection },
        .{ .tag = "CODE".*, .flags = SECTION_REQUIRED, .err = error.InvalidSection },
    };
    for (cases) |case| {
        var extended = std.array_list.Managed(u8).init(testing.allocator);
        defer extended.deinit();
        try extended.appendSlice(bytes.items);
        try extended.appendSlice(&case.tag);
        try extended.append(case.flags);
        var len: [4]u8 = undefined;
        std.mem.writeInt(u32, &len, 3, .little);
        try extended.appendSlice(&len);
        try extended.appendSlice(&.{ 1, 2, 3 });
        reseal_for_test(extended.items);
        if (case.err) |err| {
            try testing.expectError(err, load_for_test(extended.items));
        } else {
            var compiled = try load_for_test(extended.items);
            compiled.deinit();
        }
    }
}

test "P48-17: a package's framing is checked before any section is read" {
    const testing = std.testing;
    var bytes = std.array_list.Managed(u8).init(testing.allocator);
    defer bytes.deinit();
    try package_of(testing.allocator, SMALL_SCRIPT, &bytes);

    // Before 1.0, another magic, a later format, a bad checksum, and an oversized payload.
    const Case = struct { at: usize, bytes: []const u8, err: anyerror, reseal: bool = false };
    const cases = [_]Case{
        .{ .at = 0, .bytes = &PRE_1_0_MAGIC, .err = error.PackageFromBeforeOne },
        .{ .at = 0, .bytes = "NOPE", .err = error.InvalidPackageMagic },
        .{ .at = 4, .bytes = &.{ 2, 0, 0, 0 }, .err = error.UnsupportedPackageVersion },
        .{ .at = @sizeOf(PackageHeader) + 2, .bytes = &.{0x5a}, .err = error.ChecksumMismatch },
        .{ .at = 12, .bytes = &.{ 0xff, 0xff, 0xff, 0x7f }, .err = error.PackagePayloadTooLarge },
        // A section longer than what is left of the payload.
        .{ .at = @sizeOf(PackageHeader) + 5, .bytes = &.{ 0xff, 0xff, 0, 0 }, .err = error.InvalidSection, .reseal = true },
    };
    for (cases) |case| {
        const bad = try testing.allocator.dupe(u8, bytes.items);
        defer testing.allocator.free(bad);
        @memcpy(bad[case.at..][0..case.bytes.len], case.bytes);
        if (case.reseal) reseal_for_test(bad);
        try testing.expectError(case.err, load_for_test(bad));
    }

    // A section with a byte its reader does not use is corrupt, as is a package without code.
    var padded = std.array_list.Managed(u8).init(testing.allocator);
    defer padded.deinit();
    const names = section_slice(bytes.items, .names);
    const names_end = @intFromPtr(names.ptr) - @intFromPtr(bytes.items.ptr) + names.len;
    try padded.appendSlice(bytes.items[0..names_end]);
    try padded.append(0);
    try padded.appendSlice(bytes.items[names_end..]);
    std.mem.writeInt(u32, padded.items[names_end - names.len - 4 ..][0..4], @intCast(names.len + 1), .little);
    reseal_for_test(padded.items);
    try testing.expectError(error.InvalidSection, load_for_test(padded.items));
    const code_only = try testing.allocator.dupe(u8, bytes.items[0..names_end]);
    defer testing.allocator.free(code_only);
    reseal_for_test(code_only);
    try testing.expectError(error.InvalidSection, load_for_test(code_only));
}

test "P48-17: a build that links fewer readers refuses a package that needs another" {
    const testing = std.testing;
    var bytes = std.array_list.Managed(u8).init(testing.allocator);
    defer bytes.deinit();
    const source = try round_trip_source(testing.allocator, 0);
    defer testing.allocator.free(source);
    try package_of(testing.allocator, source, &bytes);
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    comptime var core = SectionSet.empty;
    comptime core.insert(.names);
    comptime core.insert(.code);
    var stream: std.Io.Reader = .fixed(bytes.items);
    try testing.expectError(error.UnlinkedSection, load_package_linked(core, testing.allocator, &stream, &world, null));

    // `sections_in` reads the tags of a package known when the module is built.
    const header = PackageHeader{};
    const fake = comptime std.mem.asBytes(&header) ++ "NAME".* ++ [_]u8{ 1, 0, 0, 0, 0 } ++ "IMGS".* ++ [_]u8{ 1, 0, 0, 0, 0 };
    const found = comptime sections_in(fake);
    try testing.expect(found.contains(.names) and found.contains(.images) and !found.contains(.code));
}

test "P48-17: a section's own contents are still checked" {
    const testing = std.testing;
    var bytes = std.array_list.Managed(u8).init(testing.allocator);
    defer bytes.deinit();
    const source = try round_trip_source(testing.allocator, 0);
    defer testing.allocator.free(source);
    try package_of(testing.allocator, source, &bytes);
    // A draft note past B.
    const bad = try testing.allocator.dupe(u8, bytes.items);
    defer testing.allocator.free(bad);
    section_slice(bad, .drafts)[4 + 4] = 99;
    reseal_for_test(bad);
    try testing.expectError(error.InvalidDraftNote, load_for_test(bad));
    // A zero program identity, which would read as "unknown program" in a save (D-162).
    const code = section_slice(bytes.items, .code);
    @memset(code[code.len - 2 - 8 .. code.len - 2], 0);
    reseal_for_test(bytes.items);
    try testing.expectError(error.InvalidProgramIdentity, load_for_test(bytes.items));
}

test "P48-17: an image stream that is not QOI, or holds partial alpha, is refused" {
    const testing = std.testing;
    var bytes = std.array_list.Managed(u8).init(testing.allocator);
    defer bytes.deinit();
    const source = try round_trip_source(testing.allocator, 20);
    defer testing.allocator.free(source);
    try package_of(testing.allocator, source, &bytes);
    // Image count, then the first image's name (u16 length and text), four sides, stream length.
    const images = section_slice(bytes.items, .images);
    const name_len = std.mem.readInt(u16, images[4..6], .little);
    const stream_at = 4 + 2 + name_len + 8 + 4;
    const Case = struct { at: usize, bytes: []const u8, err: anyerror };
    const cases = [_]Case{
        .{ .at = stream_at, .bytes = "QOIF", .err = error.InvalidImageData },
        .{ .at = stream_at + 14, .bytes = &.{ 0xff, 1, 2, 3, 128 }, .err = error.InvalidImagePixel },
        .{ .at = 0, .bytes = &.{ 0x40, 0x42, 0x0f, 0x00 }, .err = error.InvalidImageCount },
    };
    for (cases) |case| {
        const bad = try testing.allocator.dupe(u8, bytes.items);
        defer testing.allocator.free(bad);
        @memcpy(section_slice(bad, .images)[case.at..][0..case.bytes.len], case.bytes);
        reseal_for_test(bad);
        try testing.expectError(case.err, load_for_test(bad));
    }
}

test "P48-17: checked-in 1.0 package fixture loads every part" {
    const testing = std.testing;
    const fixture = try std.Io.Dir.cwd().readFileAlloc(testing.io, "tests/fixtures/compat/format-1-package.bspk", testing.allocator, .limited(1024 * 1024));
    defer testing.allocator.free(fixture);
    try testing.expectEqual(PACKAGE_FORMAT, version_from_bytes(fixture).?);
    var compiled = try load_for_test(fixture);
    defer compiled.deinit();
    try testing.expect(compiled.rewinds_reroll);
    try testing.expect(compiled.turn_clock);
    try testing.expectEqual(@as(u32, 2), compiled.save_version);
    try testing.expectEqual(@as(u8, 8), compiled.dilemmas.items[0].dilemma.strong_at);
    try testing.expect(compiled.reactive_rules.items[0].each);
    try testing.expectEqual(@as(usize, 2), compiled.art.looks.len);
    const sections = try sections_of(fixture);
    for ([_]Section{ .names, .places, .code, .rules, .goals, .axes, .dilemmas, .images, .art, .text }) |which| try testing.expect(sections.contains(which));
}

test "P48-23: packages preserve script_owned, reject reserved relation bits, and sort CODE maps" {
    const testing = std.testing;
    const reserved = @import("reserved.zig");
    const source =
        \\entity Hero
        \\relation Claimed(who)
        \\routine Alpha(Hero):
        \\  remember Claimed(Hero)
        \\routine Beta(Hero):
        \\  wait 1 ticks
        \\on cue Uses(Hero, _):
        \\  wait 1 ticks
        \\on cue LooksAt(Hero, _):
        \\  wait 1 ticks
        \\
    ;
    var world0 = try World.init(testing.allocator, 1024 * 1024);
    defer world0.deinit();
    var compiled0 = try compile_for_test(testing.allocator, &world0, null, source);
    defer compiled0.deinit();
    world0.claim_relation(world0.lookup_relation("Claimed").?);
    var bytes = std.array_list.Managed(u8).init(testing.allocator);
    defer bytes.deinit();
    var lw0 = ListWriter.init(&bytes);
    try save_package(testing.allocator, &lw0.writer, &compiled0, &world0, null);

    // Loading restores script_owned so reserved.engine_may_use honors it.
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var stream: std.Io.Reader = .fixed(bytes.items);
    var loaded = try load_package(testing.allocator, &stream, &world, null);
    defer loaded.deinit();
    const claimed = world.lookup_relation("Claimed").?;
    try testing.expect(world.get_relation_meta(claimed).?.script_owned);
    try testing.expect(!reserved.engine_may_use(&world, "Claimed"));

    // Saving again produces identical CODE bytes even across different HashMap orders.
    var again = std.array_list.Managed(u8).init(testing.allocator);
    defer again.deinit();
    var lw = ListWriter.init(&again);
    try save_package(testing.allocator, &lw.writer, &loaded, &world, null);
    try testing.expectEqualSlices(u8, section_slice(bytes.items, .code), section_slice(again.items, .code));

    // Reserved low flag bits (bit 2+) in NAME are refused.
    const names = section_slice(bytes.items, .names);
    names[names.len - 1] |= 0x04;
    reseal_for_test(bytes.items);
    try testing.expectError(error.InvalidRelationKind, load_for_test(bytes.items));
}

test "P48-24: read_str frees buffer on truncated stream and package bounds refuse corrupt counts/PCs" {
    const testing = std.testing;

    // 1. Truncated read_str does not leak under testing.allocator.
    var trunc_stream: std.Io.Reader = .fixed(&.{ 10, 0, 'a', 'b' });
    try testing.expectError(error.EndOfStream, read_str(testing.allocator, &trunc_stream));

    // 2. Out-of-range PCs in CODE (routine and cue) and RULE are rejected.
    const rule_src =
        \\entity Hero
        \\relation Flag(who)
        \\routine Alpha(Hero):
        \\  wait 1 ticks
        \\on cue Uses(Hero, _):
        \\  wait 1 ticks
        \\when Flag(?who):
        \\  wait 1 ticks
        \\
    ;
    var base = std.array_list.Managed(u8).init(testing.allocator);
    defer base.deinit();
    try package_of(testing.allocator, rule_src, &base);
    {
        const bad = try testing.allocator.dupe(u8, base.items);
        defer testing.allocator.free(bad);
        const code = section_slice(bad, .code);
        const code_len = std.mem.readInt(u32, code[0..4], .little);
        // After code_len(4) + code + initial_entry(8) + routine_count(4) + rname(u16 + text) sits routine pc.
        const rname_off = 4 + code_len + 8 + 4;
        const rname_len = std.mem.readInt(u16, code[rname_off..][0..2], .little);
        std.mem.writeInt(u32, code[rname_off + 2 + rname_len ..][0..4], code_len, .little);
        reseal_for_test(bad);
        try testing.expectError(error.InvalidProgramIndex, load_for_test(bad));
    }
    {
        const bad = try testing.allocator.dupe(u8, base.items);
        defer testing.allocator.free(bad);
        const rules = section_slice(bad, .rules);
        // entry_count(4) + entries + rule_count(4) + tent(4) + priority(2) + handler_pc(4)
        const entry_count = std.mem.readInt(u32, rules[0..4], .little);
        const pc_off = 4 + entry_count * 4 + 4 + 4 + 2;
        std.mem.writeInt(u32, rules[pc_off..][0..4], 0x7fffffff, .little);
        reseal_for_test(bad);
        try testing.expectError(error.InvalidProgramIndex, load_for_test(bad));
    }

    // 3. Oversized PLAC waypoint count is rejected.
    const stage_src = try round_trip_source(testing.allocator, 7); // arrival.bespoke uses marks/PLAC
    defer testing.allocator.free(stage_src);
    var stage_pkg = std.array_list.Managed(u8).init(testing.allocator);
    defer stage_pkg.deinit();
    try package_of(testing.allocator, stage_src, &stage_pkg);
    {
        const bad = try testing.allocator.dupe(u8, stage_pkg.items);
        defer testing.allocator.free(bad);
        const plac = section_slice(bad, .places);
        std.mem.writeInt(u32, plac[0..4], MAX_WAYPOINTS + 1, .little);
        reseal_for_test(bad);
        try testing.expectError(error.InvalidSection, load_for_test(bad));
    }

    // 4. Out-of-range society enforcer / friend_count is rejected cleanly without leaks.
    const soc_src = try round_trip_source(testing.allocator, 8); // society-and-duel.bespoke
    defer testing.allocator.free(soc_src);
    var soc_pkg = std.array_list.Managed(u8).init(testing.allocator);
    defer soc_pkg.deinit();
    try package_of(testing.allocator, soc_src, &soc_pkg);
    {
        const bad = try testing.allocator.dupe(u8, soc_pkg.items);
        defer testing.allocator.free(bad);
        const soci = section_slice(bad, .societies);
        // Trailing friend_count sits after society FriendLink array; zero friend_links means last 4 bytes are friend_count = 0.
        // Instead patch society count? No, patch trailing 4 bytes if friend_count == 0, or walk to friend_count via known layout:
        // Verify InvalidSocietyConfig when last 4 bytes are overwritten with a huge friend_count (or when FriendLink count is patched).
        // Let's write society count > MAX_SOCIETIES cleanly first, and test bad enforcer on a known society buffer.
        std.mem.writeInt(u32, soci[0..4], MAX_SOCIETIES + 1, .little);
        reseal_for_test(bad);
        try testing.expectError(error.InvalidSocietyConfig, load_for_test(bad));
    }
    // Out-of-range enforcer index inside read_society_declaration is rejected cleanly without leaks.
    var w = try World.init(testing.allocator, 256 * 1024);
    defer w.deinit();
    var sp_mut = SpatialSystem.init(testing.allocator);
    defer sp_mut.deinit();
    var cp = try compile_for_test(testing.allocator, &w, &sp_mut, soc_src);
    defer cp.deinit();
    const orig_enforcer = cp.societies.items[0].config.enforcer;
    cp.societies.items[0].config.enforcer = 99;
    defer cp.societies.items[0].config.enforcer = orig_enforcer;
    var soc_buf = std.array_list.Managed(u8).init(testing.allocator);
    defer soc_buf.deinit();
    var sw = ListWriter.init(&soc_buf);
    try write_societies(&w, &sw.writer, &cp);
    var soc_stream: std.Io.Reader = .fixed(soc_buf.items[4..]);
    try testing.expectError(error.InvalidSocietyConfig, read_society_declaration(testing.allocator, &w, &soc_stream, sp_mut.graph.waypoints.items.len));

    // 5. Malformed bytecode in CODE is rejected at package load time (D-189).
    var code_pkg = std.array_list.Managed(u8).init(testing.allocator);
    defer code_pkg.deinit();
    try package_of(testing.allocator, "entity Hero\nroutine Go(Hero):\n  wait 1 ticks\n", &code_pkg);
    {
        const bad = try testing.allocator.dupe(u8, code_pkg.items);
        defer testing.allocator.free(bad);
        const code = section_slice(bad, .code);
        code[4] = 0xFF; // undefined opcode at byte 0 of chunk
        reseal_for_test(bad);
        try testing.expectError(error.InvalidBytecode, load_for_test(bad));
    }
    {
        const bad = try testing.allocator.dupe(u8, code_pkg.items);
        defer testing.allocator.free(bad);
        const code = section_slice(bad, .code);
        code[4] = @intFromEnum(Opcode.emit_cue);
        std.mem.writeInt(u16, code[5..7], 2, .little);
        code[7] = 5; // arg_count > MAX_CUE_ARGS
        reseal_for_test(bad);
        try testing.expectError(error.InvalidBytecode, load_for_test(bad));
    }
    {
        const bad = try testing.allocator.dupe(u8, code_pkg.items);
        defer testing.allocator.free(bad);
        const code = section_slice(bad, .code);
        const code_len = std.mem.readInt(u32, code[0..4], .little);
        code[4 + code_len - 1] = @intFromEnum(Opcode.push_const); // truncated operand
        reseal_for_test(bad);
        try testing.expectError(error.InvalidBytecode, load_for_test(bad));
    }
    {
        const bad = try testing.allocator.dupe(u8, code_pkg.items);
        defer testing.allocator.free(bad);
        const code = section_slice(bad, .code);
        std.mem.writeInt(u32, code[0..4], bytecode_mod.MAX_BYTECODE_LEN + 1, .little);
        reseal_for_test(bad);
        try testing.expectError(error.BytecodeTooLarge, load_for_test(bad));
    }
}

test "D-199: room exits round-trip in a required EXIT section that a reader without it refuses" {
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
    var compiled = try compile_for_test(testing.allocator, &world, &spatial, src);
    defer compiled.deinit();
    var bytes: std.Io.Writer.Allocating = .init(testing.allocator);
    defer bytes.deinit();
    try save_package(testing.allocator, &bytes.writer, &compiled, &world, &spatial);
    const table = try read_section_table(bytes.written()[@sizeOf(PackageHeader)..]);
    const exit_bytes = table.get(.exits).?;
    // Required: the flags byte sits just before the section's length.
    const header_at = @intFromPtr(exit_bytes.ptr) - @intFromPtr(bytes.written().ptr) - SECTION_HEADER_LEN;
    try testing.expectEqualStrings("EXIT", bytes.written()[header_at..][0..4]);
    try testing.expectEqual(SECTION_REQUIRED, bytes.written()[header_at + 4]);
    {
        var w2 = try World.init(testing.allocator, 1024 * 1024);
        defer w2.deinit();
        var s2 = SpatialSystem.init(testing.allocator);
        defer s2.deinit();
        var stream: std.Io.Reader = .fixed(bytes.written());
        var loaded = try load_package(testing.allocator, &stream, &w2, &s2);
        defer loaded.deinit();
        try testing.expectEqual(@as(usize, 1), loaded.exits.items.len);
        try testing.expectEqualStrings("Door", loaded.exits.items[0].to_mark);
        try testing.expectEqual(compiled.fingerprint, loaded.fingerprint);
    }
    {
        var w3 = try World.init(testing.allocator, 1024 * 1024);
        defer w3.deinit();
        var stream: std.Io.Reader = .fixed(bytes.written());
        const without = comptime ALL_SECTIONS.differenceWith(SectionSet.initOne(.exits));
        try testing.expectError(error.UnlinkedSection, load_package_linked(without, testing.allocator, &stream, &w3, null));
    }
}

test "P49-01: colour cycles round-trip in optional CYCL section and 1.0 readers skip it cleanly" {
    const testing = std.testing;
    const script =
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
        \\image Beacon:
        \\  "ab"
        \\  "de"
        \\sprite Hero: Beacon
        \\routine Idle(Hero):
        \\  wait 1 ticks
    ;
    var bytes = std.array_list.Managed(u8).init(testing.allocator);
    defer bytes.deinit();
    try package_of(testing.allocator, script, &bytes);

    // 1. Verify CYCL section header has flags == 0 (optional).
    const payload = bytes.items[@sizeOf(PackageHeader)..];
    const table = try read_section_table(payload);
    const cycl_bytes = table.get(.cycles).?;
    const cycl_header_offset = @intFromPtr(cycl_bytes.ptr) - @intFromPtr(bytes.items.ptr) - SECTION_HEADER_LEN;
    try testing.expectEqualStrings("CYCL", bytes.items[cycl_header_offset..][0..4]);
    try testing.expectEqual(@as(u8, 0), bytes.items[cycl_header_offset + 4]);

    // 2. Full round-trip loads both cycles intact.
    {
        var world = try World.init(testing.allocator, 256 * 1024);
        defer world.deinit();
        var spatial = SpatialSystem.init(testing.allocator);
        defer spatial.deinit();
        var stream: std.Io.Reader = .fixed(bytes.items);
        var loaded = try load_package(testing.allocator, &stream, &world, &spatial);
        defer loaded.deinit();
        try testing.expectEqual(@as(usize, 2), loaded.art.cycles.len);
        try testing.expectEqual(@as(u16, 8), loaded.art.cycles[0].every);
        try testing.expectEqual(@as(usize, 3), loaded.art.cycles[0].colours.len);
        try testing.expectEqual(image_mod.Colour{ .r = 70, .g = 80, .b = 90 }, loaded.art.cycles[0].colours[2]);
        try testing.expectEqual(@as(u16, image_mod.DEFAULT_CYCLE_INTERVAL), loaded.art.cycles[1].every);
        try testing.expectEqual(@as(usize, 2), loaded.art.cycles[1].colours.len);
    }

    // 3. A build that omits .cycles refuses it as UnlinkedSection, while a 1.0 reader that does
    // not know the tag skips it cleanly when flags == 0.
    {
        var world = try World.init(testing.allocator, 256 * 1024);
        defer world.deinit();
        var spatial = SpatialSystem.init(testing.allocator);
        defer spatial.deinit();
        const v1_sections = comptime ALL_SECTIONS.differenceWith(SectionSet.initOne(.cycles));
        var stream: std.Io.Reader = .fixed(bytes.items);
        try testing.expectError(error.UnlinkedSection, load_package_linked(v1_sections, testing.allocator, &stream, &world, &spatial));
    }
    {
        const unknown_opt = try testing.allocator.dupe(u8, bytes.items);
        defer testing.allocator.free(unknown_opt);
        @memcpy(unknown_opt[cycl_header_offset..][0..4], "CYC9");
        reseal_for_test(unknown_opt);
        var world = try World.init(testing.allocator, 256 * 1024);
        defer world.deinit();
        var spatial = SpatialSystem.init(testing.allocator);
        defer spatial.deinit();
        var stream: std.Io.Reader = .fixed(unknown_opt);
        var loaded = try load_package(testing.allocator, &stream, &world, &spatial);
        defer loaded.deinit();
        try testing.expectEqual(@as(usize, 0), loaded.art.cycles.len);
        try testing.expectEqual(@as(usize, 1), loaded.art.images.len);
    }

    // 4. Corrupt CYCL payloads fail cleanly with zero leaks.
    const BadCycl = struct { bytes: []const u8, err: anyerror };
    const corrupt_cases = [_]BadCycl{
        .{ .bytes = &.{ 65, 0 }, .err = error.InvalidImageBinding }, // count > MAX_CYCLES
        .{ .bytes = &.{ 1, 0, 8, 0, 1, 0, 1, 2, 3 }, .err = error.InvalidImageBinding }, // len == 1 (< 2)
        .{ .bytes = &.{ 1, 0, 0, 0, 2, 0, 1, 2, 3, 4, 5, 6 }, .err = error.InvalidImageBinding }, // every == 0
        .{ .bytes = &.{ 1, 0, 8, 0, 2, 0, 1, 2, 3, 1, 2, 3 }, .err = error.InvalidImageBinding }, // duplicate RGB
        .{ .bytes = &.{ 1, 0, 8, 0, 2, 0, 1, 2, 3 }, .err = error.EndOfStream }, // truncated
        .{ .bytes = &.{ 1, 0, 8, 0, 2, 0, 1, 2, 3, 4, 5, 6, 99 }, .err = error.InvalidSection }, // trailing byte
    };
    for (corrupt_cases) |bad_cycl| {
        const prefix = bytes.items[0 .. cycl_header_offset + SECTION_HEADER_LEN];
        const suffix = bytes.items[cycl_header_offset + SECTION_HEADER_LEN + cycl_bytes.len ..];
        var bad = std.array_list.Managed(u8).init(testing.allocator);
        defer bad.deinit();
        try bad.appendSlice(prefix);
        try bad.appendSlice(bad_cycl.bytes);
        try bad.appendSlice(suffix);
        std.mem.writeInt(u32, bad.items[cycl_header_offset + 5 ..][0..4], @intCast(bad_cycl.bytes.len), .little);
        std.mem.writeInt(u32, bad.items[@sizeOf(PackageHeader) - 4 ..][0..4], @intCast(bad.items.len - @sizeOf(PackageHeader)), .little);
        reseal_for_test(bad.items);
        try testing.expectError(bad_cycl.err, load_for_test(bad.items));
    }
}

test "P49-01: compatibility fixture format-1-cycles.bspk loads with its colour cycle" {
    const testing = std.testing;
    const fixture = try std.Io.Dir.cwd().readFileAlloc(testing.io, "tests/fixtures/compat/format-1-cycles.bspk", testing.allocator, .limited(1024 * 1024));
    defer testing.allocator.free(fixture);
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var stream: std.Io.Reader = .fixed(fixture);
    var loaded = try load_package(testing.allocator, &stream, &world, &spatial);
    defer loaded.deinit();
    try testing.expectEqual(@as(usize, 1), loaded.art.cycles.len);
    try testing.expectEqual(@as(u16, 8), loaded.art.cycles[0].every);
    try testing.expectEqual(@as(usize, 3), loaded.art.cycles[0].colours.len);
}

