const std = @import("std");
const ListWriter = @import("list_writer.zig").ListWriter;
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
const hint_mod = @import("hint.zig");
const spell_mod = @import("spell.zig");
const decision_mod = @import("decision.zig");
const value_mod = @import("value.zig");
const dilemma_mod = @import("dilemma.zig");
const image_mod = @import("image.zig");
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
/// with none. Version 10 appends typed-command frames and noun aliases (P26-01, D-057);
/// versions 1 through 9 load with neither. Version 11 appends script scores as MML text with
/// their scenes (P28-03, D-062); versions 1 through 10 load with none. Version 12 appends each
/// cast member's starting mark (D-065); versions 1 through 11 load with none, so a host places
/// nobody for them.
/// Version 13 appends cue handler `where` guards (D-072); versions 1 through 12 load with none,
/// so every handler runs as it did unguarded.
/// Version 14 lets a duel declare up to `duel.MAX_FALLBACKS` fallback lines (D-076); earlier
/// versions wrote 0 or 1, which the same count byte reads unchanged.
/// Version 15 appends goals with their needs and authored hints (P44-01, D-134); versions 1
/// through 14 load with no goals. Version 16 adds the aggregate condition opcodes (P44-02);
/// versions 1 through 15 hold bytecode that cannot contain them, so they load unchanged.
/// Version 17 appends spellbooks with their words and combinations (P44-04); versions 1
/// through 16 load with no spellbook. Version 18 appends decisions with their trigger lines and
/// scored options (P44-05); versions 1 through 17 load with no decisions. Version 19 appends value
/// axes with their poles (P45-01, D-144); versions 1 through 18 load with none. Version 20 appends
/// each character's red lines (P45-02, D-145); versions 1 through 19 load with none. Version 21
/// appends dilemmas with their axes, leans, and tier responses (P45-03, D-146); versions 1 through
/// 20 load with none. Version 22 appends each dilemma's drift lines (P45-04, D-148); versions 1
/// through 21 load dilemmas without drift. Version 23 appends each dilemma's appeal lines (P45-05,
/// D-149); versions 1 through 22 load dilemmas that no appeal moves. Version 24 appends the
/// game's palette and indexed images (P46-01, D-152, D-153); versions 1 through 23 load with no
/// art, which is a game drawn by code.
pub const PACKAGE_VERSION: u32 = 24;
pub const MAX_PACKAGE_PAYLOAD_SIZE: u32 = 64 * 1024 * 1024;
pub const MIN_PACKAGE_VERSION: u32 = 1;
/// Upper bound on cast entries a package may declare; a larger count is corrupt input.
const MAX_CAST: u32 = 4096;

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

/// Formats the actionable diagnostic shown when a package's schema is outside the range this
/// engine can read (P38-02, D-106). The error union stays stable for API callers; the message
/// carries the file's version and the complete supported range.
pub fn format_unsupported_version(buf: []u8, found: u32) []const u8 {
    return std.fmt.bufPrint(buf, "unsupported .bspk format version {d}; this engine supports versions {d} through {d}", .{
        found,
        MIN_PACKAGE_VERSION,
        PACKAGE_VERSION,
    }) catch "unsupported .bspk format version";
}

/// Reads only the version field from an in-memory package envelope. The full loader remains the
/// authority for magic, checksum, bounds, and payload validation.
pub fn version_from_bytes(bytes: []const u8) ?u32 {
    if (bytes.len < 8 or !std.mem.eql(u8, bytes[0..4], &PACKAGE_MAGIC)) return null;
    return std.mem.readInt(u32, bytes[4..8], .little);
}

fn write_str(writer: anytype, str: []const u8) !void {
    try writer.writeInt(u16, @intCast(str.len), .little);
    try writer.writeAll(str);
}

fn read_str(allocator: std.mem.Allocator, reader: anytype) ![]const u8 {
    const len = try reader.takeInt(u16, .little);
    const buf = try allocator.alloc(u8, len);
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
        // Version 14 reads this byte as a line count; earlier versions wrote 0 or 1 here, which
        // reads the same, so older packages load unchanged (D-076).
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

    try writer.writeInt(u32, @intCast(compiled.scores.items.len), .little);
    for (compiled.scores.items) |score| {
        try write_str(writer, score.name);
        try writer.writeByte(@intCast(score.scenes.len));
        for (score.scenes) |scene| try write_str(writer, scene);
        for (score.parts) |text| try write_str(writer, text);
    }

    try writer.writeInt(u32, @intCast(compiled.cast.items.len), .little);
    for (compiled.cast.items) |place| {
        try writer.writeInt(u32, place.actor.to_int(), .little);
        try writer.writeInt(u16, place.mark, .little);
    }

    try writer.writeInt(u32, @intCast(compiled.cue_guards.items.len), .little);
    for (compiled.cue_guards.items) |guard| {
        try writer.writeInt(u32, @intCast(guard.handler_pc), .little);
        for (guard.param_slots) |slot| try writer.writeByte(slot orelse NO_GUARD_SLOT);
        try writer.writeInt(u16, @intCast(guard.clauses.len), .little);
        for (guard.clauses) |clause| try write_pattern_clause(writer, clause);
    }

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

    try write_axes(writer, compiled);

    try writer.writeInt(u32, @intCast(compiled.red_lines.items.len), .little);
    for (compiled.red_lines.items) |decl| {
        try writer.writeInt(u32, decl.red_lines.actor.to_int(), .little);
        try writer.writeByte(@intCast(decl.red_lines.options.len));
        for (decl.red_lines.options) |option| try writer.writeInt(u32, option.to_int(), .little);
    }

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
    }

    // Version 22: drift lines, one group per dilemma in the same order, so the version 21
    // dilemma records above stay byte-for-byte what a version 21 reader expects.
    for (compiled.dilemmas.items) |decl| {
        try writer.writeByte(@intCast(decl.dilemma.drifts.len));
        for (decl.dilemma.drifts) |drift| {
            try writer.writeInt(u16, drift.axis.to_int(), .little);
            try writer.writeInt(i32, drift.points, .little);
            try write_decision_clause(world, writer, drift.clause);
        }
    }

    // Version 23: appeal lines, one group per dilemma in the same order.
    for (compiled.dilemmas.items) |decl| {
        try writer.writeByte(@intCast(decl.dilemma.appeals.len));
        for (decl.dilemma.appeals) |appeal| {
            try writer.writeInt(u16, appeal.axis.to_int(), .little);
            try writer.writeInt(u32, appeal.entity.to_int(), .little);
            try writer.writeInt(i32, appeal.points, .little);
        }
    }

    try write_art(writer, compiled.art);
}

/// Version 24: the palette as RGB triples, then each image's name, sheet size, frame size, and
/// one index byte per pixel, row by row. Raw bytes for now; compression waits for measured
/// pages (D-152).
fn write_art(writer: anytype, art: image_mod.Art) !void {
    try art.validate();
    try writer.writeInt(u16, @intCast(art.palette.len), .little);
    for (art.palette) |colour| try writer.writeAll(&.{ colour.r, colour.g, colour.b });
    try writer.writeInt(u32, @intCast(art.images.len), .little);
    for (art.images) |image| {
        try write_str(writer, image.name);
        for ([_]u16{ image.width, image.height, image.frame_width, image.frame_height }) |side| try writer.writeInt(u16, side, .little);
        try writer.writeAll(image.pixels);
    }
}

/// Untrusted input. Each count and size is checked before the bytes behind it are read, so a
/// corrupt package can ask for at most one bounded sheet at a time, and `Art.validate` runs on
/// the whole set before the program sees it. Errors name the first thing wrong (D-153).
fn read_art(allocator: std.mem.Allocator, reader: anytype) !image_mod.Art {
    const colour_count = try reader.takeInt(u16, .little);
    if (colour_count > image_mod.MAX_COLOURS) return error.InvalidImagePalette;
    const palette = try allocator.alloc(image_mod.Colour, colour_count);
    var art = image_mod.Art{ .palette = palette };
    errdefer art.deinit_owned(allocator);
    for (palette) |*colour| {
        const rgb = try reader.takeArray(3);
        colour.* = .{ .r = rgb[0], .g = rgb[1], .b = rgb[2] };
    }

    const image_count = try reader.takeInt(u32, .little);
    if (image_count > image_mod.MAX_IMAGES) return error.InvalidImageCount;
    if (image_count > 0 and colour_count == 0) return error.InvalidImagePalette;
    var images = try std.ArrayListUnmanaged(image_mod.Image).initCapacity(allocator, image_count);
    errdefer {
        for (images.items) |image| image_mod.free_image(allocator, image);
        images.deinit(allocator);
    }
    for (0..image_count) |_| {
        const name = try read_str(allocator, reader);
        errdefer allocator.free(name);
        try image_mod.validate_name(name);
        var sides: [4]u16 = undefined;
        for (&sides) |*side| side.* = try reader.takeInt(u16, .little);
        try image_mod.validate_size(sides[0], sides[1], sides[2], sides[3]);
        const bytes = try reader.take(@as(usize, sides[0]) * sides[1]);
        try image_mod.validate_indices(bytes, colour_count);
        const pixels = try allocator.dupe(u8, bytes);
        images.appendAssumeCapacity(.{
            .name = name,
            .width = sides[0],
            .height = sides[1],
            .frame_width = sides[2],
            .frame_height = sides[3],
            .pixels = pixels,
        });
    }
    art.images = try images.toOwnedSlice(allocator);
    try art.validate();
    return art;
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
fn read_dilemma(allocator: std.mem.Allocator, world: *const World, reader: anytype) !dilemma_mod.Declaration {
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
    return .{ .dilemma = .{
        .entity = entity,
        .actor = actor,
        .cue = cue,
        .clauses = clauses,
        .axis = axis,
        .counter = counter,
        .leans = leans,
        .responses = responses,
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
        const owns = try allocator.alloc(EntityId, try reader.takeInt(u16, .little));
        errdefer allocator.free(owns);
        for (owns) |*item| item.* = try read_entity_ref(world, reader);
        const carries = try allocator.alloc(EntityId, try reader.takeInt(u16, .little));
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

fn read_duel_declaration(allocator: std.mem.Allocator, world: *const World, reader: anytype, version: u32) !duel_mod.Declaration {
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
    const fallback_limit: usize = if (version >= 14) duel_mod.MAX_FALLBACKS else 1;
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
fn read_grid_declaration(allocator: std.mem.Allocator, world: *const World, reader: anytype, has_rules: bool) !grid_mod.Declaration {
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
    // Version 7 knew only flammable, liquid, and blocking; a later attribute byte there is corrupt.
    const attribute_count: usize = if (has_rules) std.meta.tags(grid_mod.Attribute).len else 3;
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
    if (has_rules) {
        rules.burn_ticks = try reader.takeInt(u32, .little);
        rules.spread_ticks = try reader.takeInt(u32, .little);
        rules.dissipate_ticks = try reader.takeInt(u32, .little);
        rules.flow_ticks = try reader.takeInt(u32, .little);
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

fn read_degradation_declaration(allocator: std.mem.Allocator, world: *const World, reader: anytype, has_spill: bool) !container_mod.Declaration {
    const substance = try read_entity_ref(world, reader);
    const spill_per_moving_tick = if (has_spill) try reader.takeInt(u32, .little) else 0;
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
    var pw_list = ListWriter.init(&payload);
    const pw = &pw_list.writer;

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
        for (r.clauses) |clause| try write_pattern_clause(pw, clause);
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
    if (payload.items.len > MAX_PACKAGE_PAYLOAD_SIZE) return error.PackagePayloadTooLarge;
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
    const bytes_read = try reader.readSliceShort(std.mem.asBytes(&header));
    if (bytes_read < @sizeOf(PackageHeader)) {
        return error.EndOfStream;
    }

    if (!std.mem.eql(u8, &header.magic, &PACKAGE_MAGIC)) {
        return error.InvalidPackageMagic;
    }

    if (header.version < MIN_PACKAGE_VERSION or header.version > PACKAGE_VERSION) {
        return error.UnsupportedPackageVersion;
    }

    if (header.payload_size > MAX_PACKAGE_PAYLOAD_SIZE) {
        return error.PackagePayloadTooLarge;
    }

    // Read full payload
    const payload = try allocator.alloc(u8, header.payload_size);
    defer allocator.free(payload);
    try reader.readSliceAll(payload);

    // Verify CRC32 checksum
    const computed_crc = std.hash.Crc32.hash(payload);
    if (computed_crc != header.crc32) {
        return error.ChecksumMismatch;
    }

    var stream: std.Io.Reader = .fixed(payload);
    const pr = &stream;

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
        const is_prop = (try pr.takeByte()) == 1;
        _ = try world.intern_relation(name, if (is_prop) .property else .set);
    }

    // 3. Spatial waypoints, edges, hotspots
    var wp_idx: u32 = 0;
    while (wp_idx < header.waypoint_count) : (wp_idx += 1) {
        const room_int = try pr.takeInt(u32, .little);
        const x = try pr.takeInt(i32, .little);
        const y = try pr.takeInt(i32, .little);
        const name = try read_str(allocator, pr);
        defer allocator.free(name);

        if (spatial) |sp| {
            _ = try sp.graph.add_waypoint(EntityId.from_int(room_int), x, y, name);
        }
    }

    var edge_idx: u32 = 0;
    while (edge_idx < header.edge_count) : (edge_idx += 1) {
        const from = try pr.takeInt(u16, .little);
        const to = try pr.takeInt(u16, .little);
        const cost = try pr.takeInt(u32, .little);

        if (spatial) |sp| {
            try sp.graph.connect(from, to, cost);
        }
    }

    var hs_idx: u32 = 0;
    while (hs_idx < header.hotspot_count) : (hs_idx += 1) {
        const ent_int = try pr.takeInt(u32, .little);
        const room_int = try pr.takeInt(u32, .little);
        const x = try pr.takeInt(i32, .little);
        const y = try pr.takeInt(i32, .little);
        const radius = try pr.takeInt(u32, .little);
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
        try pr.readSliceAll(code_slice);
        try chunk.code.appendSlice(code_slice);
    }

    // 5. Routine entries
    var routine_entries = std.StringHashMap(usize).init(allocator);
    errdefer routine_entries.deinit();
    var routine_entities = std.StringHashMap([]const u8).init(allocator);
    errdefer routine_entities.deinit();
    var allocated_cue_keys = std.array_list.Managed([]const u8).init(allocator);
    errdefer {
        for (allocated_cue_keys.items) |k| allocator.free(k);
        allocated_cue_keys.deinit();
    }

    var rout_idx: u32 = 0;
    while (rout_idx < header.routine_count) : (rout_idx += 1) {
        const rname = try read_str(allocator, pr);
        try allocated_cue_keys.append(rname);
        const pc = try pr.takeInt(u32, .little);
        const actor = try read_str(allocator, pr);
        try allocated_cue_keys.append(actor);
        try routine_entries.put(rname, pc);
        try routine_entities.put(rname, actor);
    }

    // 6. When rule entries
    var when_rule_entries = std.array_list.Managed(usize).init(allocator);
    errdefer when_rule_entries.deinit();
    var wr_idx: u32 = 0;
    while (wr_idx < header.when_rule_count) : (wr_idx += 1) {
        const pc = try pr.takeInt(u32, .little);
        try when_rule_entries.append(pc);
    }

    // 7. Cue handler entries
    var cue_handler_entries = std.StringHashMap(usize).init(allocator);
    errdefer cue_handler_entries.deinit();
    var cue_idx: u32 = 0;
    while (cue_idx < header.cue_count) : (cue_idx += 1) {
        const sig = try read_str(allocator, pr);
        try allocated_cue_keys.append(sig);
        const pc = try pr.takeInt(u32, .little);
        try cue_handler_entries.put(sig, pc);
    }

    // 8. Reactive simulation rules
    var reactive_rules = std.array_list.Managed(CompiledWhenRule).init(allocator);
    errdefer {
        for (reactive_rules.items) |r| allocator.free(r.clauses);
        reactive_rules.deinit();
    }

    var rr_idx: u32 = 0;
    while (rr_idx < header.reactive_rule_count) : (rr_idx += 1) {
        const tent = try pr.takeInt(u32, .little);
        const priority = try pr.takeInt(u16, .little);
        const handler_pc = try pr.takeInt(u32, .little);
        const edge_byte = try pr.takeByte();
        const edge: WhenEdge = switch (edge_byte) {
            0 => .rising,
            1 => .falling,
            2 => .on_expire,
            3 => if (header.version >= 3) .on_arrive else return error.InvalidWhenEdge,
            else => return error.InvalidWhenEdge,
        };
        const clause_count = try pr.takeInt(u16, .little);
        const clauses = try allocator.alloc(PatternClause, clause_count);
        errdefer allocator.free(clauses);
        for (clauses) |*cl| cl.* = try read_pattern_clause(pr);

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
    var drafts = std.array_list.Managed(draft_mod.CompiledDraft).init(allocator);
    errdefer drafts.deinit();
    if (header.version >= 2) {
        const draft_count = try pr.takeInt(u32, .little);
        const entity_limit = world.entity_names.items.len;
        var di: u32 = 0;
        while (di < draft_count) : (di += 1) {
            const ent_raw = try pr.takeInt(u32, .little);
            var notes: draft_mod.Notes = undefined;
            for (&notes) |*n| {
                n.* = draft_mod.Note.from_int(try pr.takeByte()) orelse return error.InvalidDraftNote;
            }
            const has_inverse = try pr.takeByte();
            const inv_raw = try pr.takeInt(u32, .little);
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

    var societies = std.array_list.Managed(society_mod.Declaration).init(allocator);
    errdefer {
        for (societies.items) |*decl| decl.deinit_owned(allocator);
        societies.deinit();
    }
    var duels = std.array_list.Managed(duel_mod.Declaration).init(allocator);
    errdefer {
        for (duels.items) |*decl| decl.deinit_owned(allocator);
        duels.deinit();
    }
    var degradations = std.array_list.Managed(container_mod.Declaration).init(allocator);
    errdefer {
        for (degradations.items) |*decl| decl.deinit_owned(allocator);
        degradations.deinit();
    }
    if (header.version >= 4) {
        const society_count = try pr.takeInt(u32, .little);
        var si: u32 = 0;
        while (si < society_count) : (si += 1) try societies.append(try read_society_declaration(allocator, world, pr, header.waypoint_count));
        const duel_count = try pr.takeInt(u32, .little);
        var di: u32 = 0;
        while (di < duel_count) : (di += 1) try duels.append(try read_duel_declaration(allocator, world, pr, header.version));
    }
    if (header.version >= 5) {
        const degradation_count = try pr.takeInt(u32, .little);
        var ci: u32 = 0;
        while (ci < degradation_count) : (ci += 1) try degradations.append(try read_degradation_declaration(allocator, world, pr, header.version >= 6));
    }
    var grids = std.array_list.Managed(grid_mod.Declaration).init(allocator);
    errdefer {
        for (grids.items) |*decl| decl.deinit_owned(allocator);
        grids.deinit();
    }
    if (header.version >= 7) {
        const grid_count = try pr.takeInt(u32, .little);
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
    var agendas = std.array_list.Managed(agency_mod.Declaration).init(allocator);
    errdefer {
        for (agendas.items) |*decl| decl.deinit_owned(allocator);
        agendas.deinit();
    }
    if (header.version >= 9) {
        const agenda_count = try pr.takeInt(u32, .little);
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
    if (header.version >= 10) {
        const command_count = try pr.takeInt(u32, .little);
        if (command_count > 256) return error.InvalidCommandConfig;
        var ci2: u32 = 0;
        while (ci2 < command_count) : (ci2 += 1) {
            var decl = try read_command_declaration(allocator, pr);
            commands.append(decl) catch |err| {
                decl.deinit_owned(allocator);
                return err;
            };
        }
        const alias_count = try pr.takeInt(u32, .little);
        if (alias_count > 256) return error.InvalidCommandConfig;
        var ai2: u32 = 0;
        while (ai2 < alias_count) : (ai2 += 1) {
            var decl = try read_alias_declaration(allocator, world, pr);
            aliases.append(decl) catch |err| {
                decl.deinit_owned(allocator);
                return err;
            };
        }
    }

    var scores = std.array_list.Managed(mml.ScoreDecl).init(allocator);
    errdefer {
        for (scores.items) |*decl| decl.deinit_owned(allocator);
        scores.deinit();
    }
    if (header.version >= 11) {
        const score_count = try pr.takeInt(u32, .little);
        if (score_count > 256) return error.InvalidScoreConfig;
        var si2: u32 = 0;
        while (si2 < score_count) : (si2 += 1) {
            var decl = try read_score_declaration(allocator, pr);
            scores.append(decl) catch |err| {
                decl.deinit_owned(allocator);
                return err;
            };
        }
    }

    var cast = std.ArrayListUnmanaged(codegen_mod.CastPlace).empty;
    errdefer cast.deinit(allocator);
    if (header.version >= 12) {
        const cast_count = try pr.takeInt(u32, .little);
        if (cast_count > MAX_CAST) return error.InvalidCastConfig;
        try cast.ensureTotalCapacity(allocator, cast_count);
        var ci: u32 = 0;
        while (ci < cast_count) : (ci += 1) {
            const actor = try read_entity_ref(world, pr);
            const mark = try read_waypoint(pr, header.waypoint_count);
            cast.appendAssumeCapacity(.{ .actor = actor, .mark = mark });
        }
    }

    var cue_guards = std.ArrayListUnmanaged(codegen_mod.CueGuard).empty;
    errdefer {
        for (cue_guards.items) |guard| allocator.free(guard.clauses);
        cue_guards.deinit(allocator);
    }
    if (header.version >= 13) {
        const guard_count = try pr.takeInt(u32, .little);
        if (guard_count > MAX_CUE_GUARDS) return error.InvalidCueGuard;
        try cue_guards.ensureTotalCapacity(allocator, guard_count);
        var gi: u32 = 0;
        while (gi < guard_count) : (gi += 1) {
            const handler_pc = try pr.takeInt(u32, .little);
            // A guard belongs to a cue handler; any other pc would never be consulted.
            if (handler_pc >= header.bytecode_len) return error.InvalidCueGuard;
            var names_handler = false;
            var entries = cue_handler_entries.valueIterator();
            while (entries.next()) |pc| {
                if (pc.* == handler_pc) names_handler = true;
            }
            if (!names_handler) return error.InvalidCueGuard;
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
    }

    var goals = std.array_list.Managed(hint_mod.Declaration).init(allocator);
    errdefer {
        for (goals.items) |*decl| decl.deinit_owned(allocator);
        goals.deinit();
    }
    if (header.version >= 15) {
        const goal_count = try pr.takeInt(u32, .little);
        if (goal_count > hint_mod.MAX_GOALS) return error.InvalidGoalConfig;
        var gi2: u32 = 0;
        while (gi2 < goal_count) : (gi2 += 1) {
            var decl = try read_goal_declaration(allocator, world, pr);
            goals.append(decl) catch |err| {
                decl.deinit_owned(allocator);
                return err;
            };
        }
        hint_mod.validate_all(goals.items) catch return error.InvalidGoalConfig;
    }

    var spellbooks = std.array_list.Managed(spell_mod.Declaration).init(allocator);
    errdefer {
        for (spellbooks.items) |*decl| decl.deinit_owned(allocator);
        spellbooks.deinit();
    }
    if (header.version >= 17) {
        const book_count = try pr.takeInt(u32, .little);
        if (book_count > spell_mod.MAX_BOOKS) return error.InvalidSpellbookConfig;
        var bi: u32 = 0;
        while (bi < book_count) : (bi += 1) {
            var decl = try read_spellbook_declaration(allocator, world, pr);
            spellbooks.append(decl) catch |err| {
                decl.deinit_owned(allocator);
                return err;
            };
        }
        spell_mod.validate_all(spellbooks.items) catch return error.InvalidSpellbookConfig;
    }

    var decisions = std.array_list.Managed(decision_mod.Declaration).init(allocator);
    errdefer {
        for (decisions.items) |*decl| decl.deinit_owned(allocator);
        decisions.deinit();
    }
    if (header.version >= 18) {
        const decision_count = try pr.takeInt(u32, .little);
        if (decision_count > decision_mod.MAX_DECISIONS) return error.InvalidDecisionConfig;
        var di: u32 = 0;
        while (di < decision_count) : (di += 1) {
            var decl = try read_decision_declaration(allocator, world, pr);
            decisions.append(decl) catch |err| {
                decl.deinit_owned(allocator);
                return err;
            };
        }
        decision_mod.validate_all(decisions.items) catch return error.InvalidDecisionConfig;
    }

    var axes = std.array_list.Managed(value_mod.Axis).init(allocator);
    errdefer axes.deinit();
    if (header.version >= 19) {
        const axis_count = try pr.takeInt(u32, .little);
        if (axis_count > value_mod.MAX_AXES) return error.InvalidAxisConfig;
        var ai: u32 = 0;
        while (ai < axis_count) : (ai += 1) try axes.append(try read_axis(world, pr));
        value_mod.validate_all(world, axes.items) catch return error.InvalidAxisConfig;
    }

    var red_lines = std.array_list.Managed(decision_mod.RedLineDeclaration).init(allocator);
    errdefer {
        for (red_lines.items) |*decl| decl.deinit_owned(allocator);
        red_lines.deinit();
    }
    if (header.version >= 20) {
        const set_count = try pr.takeInt(u32, .little);
        if (set_count > decision_mod.MAX_RED_LINE_SETS) return error.InvalidRedLineConfig;
        var ri: u32 = 0;
        while (ri < set_count) : (ri += 1) {
            var decl = try read_red_lines(allocator, world, pr);
            red_lines.append(decl) catch |err| {
                decl.deinit_owned(allocator);
                return err;
            };
        }
        decision_mod.validate_red_lines(decisions.items, red_lines.items) catch return error.InvalidRedLineConfig;
    }

    var dilemmas = std.array_list.Managed(dilemma_mod.Declaration).init(allocator);
    errdefer {
        for (dilemmas.items) |*decl| decl.deinit_owned(allocator);
        dilemmas.deinit();
    }
    if (header.version >= 21) {
        const dilemma_count = try pr.takeInt(u32, .little);
        if (dilemma_count > dilemma_mod.MAX_DILEMMAS) return error.InvalidDilemmaConfig;
        var di: u32 = 0;
        while (di < dilemma_count) : (di += 1) {
            var decl = try read_dilemma(allocator, world, pr);
            dilemmas.append(decl) catch |err| {
                decl.deinit_owned(allocator);
                return err;
            };
        }
        if (header.version >= 22) {
            for (dilemmas.items) |*decl| decl.dilemma.drifts = try read_drifts(allocator, world, pr);
        }
        if (header.version >= 23) {
            for (dilemmas.items) |*decl| decl.dilemma.appeals = try read_appeals(allocator, world, pr);
        }
        dilemma_mod.validate_all(world, dilemmas.items, decisions.items, red_lines.items) catch return error.InvalidDilemmaConfig;
    }

    var art = image_mod.Art{};
    errdefer art.deinit_owned(allocator);
    if (header.version >= 24) art = try read_art(allocator, pr);

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
        .initial_entry = if (header.initial_entry >= 0) @intCast(header.initial_entry) else null,
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
        .art = art,
    };
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
    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();

    var lw1 = ListWriter.init(&buffer);
    try save_package(testing.allocator, &lw1.writer, &compiled1, &world1, &spatial1);
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

    var stream: std.Io.Reader = .fixed(buffer.items);
    var compiled2 = try load_package(testing.allocator, &stream, &world2, &spatial2);
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
    var stream: std.Io.Reader = .fixed(std.mem.asBytes(&header));

    var dummy_world = try World.init(testing.allocator, 1024 * 1024);
    defer dummy_world.deinit();

    const res = load_package(testing.allocator, &stream, &dummy_world, null);
    try testing.expectError(error.InvalidPackageMagic, res);
}

test "P39-02: package loader rejects an oversized payload before reading it" {
    const testing = std.testing;
    const header: PackageHeader = .{
        .magic = PACKAGE_MAGIC,
        .version = PACKAGE_VERSION,
        .payload_size = MAX_PACKAGE_PAYLOAD_SIZE + 1,
    };
    var reader: std.Io.Reader = .fixed(std.mem.asBytes(&header));
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    try testing.expectError(error.PackagePayloadTooLarge, load_package(testing.allocator, &reader, &world, null));
}

test "P15-02: package loader rejects corrupted payload with checksum mismatch" {
    const testing = std.testing;
    const compiler = @import("compiler.zig");

    const script = "entity Guard\nroutine Patrol(Guard):\n  wait 2 ticks\n";
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    var compiled = try compiler.compile_source(testing.allocator, &world, null, script);
    defer compiled.deinit();

    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();

    var lw2 = ListWriter.init(&buffer);
    try save_package(testing.allocator, &lw2.writer, &compiled, &world, null);

    // Corrupt one byte in the payload
    buffer.items[buffer.items.len - 1] ^= 0xFF;

    var stream: std.Io.Reader = .fixed(buffer.items);
    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();

    const res = load_package(testing.allocator, &stream, &world2, null);
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
    var stream: std.Io.Reader = .fixed(std.mem.asBytes(&header));

    var dummy_world = try World.init(testing.allocator, 1024 * 1024);
    defer dummy_world.deinit();

    const res = load_package(testing.allocator, &stream, &dummy_world, null);
    try testing.expectError(error.UnsupportedPackageVersion, res);

    var message_buf: [128]u8 = undefined;
    try testing.expectEqualStrings(
        "unsupported .bspk format version 99; this engine supports versions 1 through 24",
        format_unsupported_version(&message_buf, version_from_bytes(std.mem.asBytes(&header)).?),
    );
}

test "P38-02: checked-in earlier package fixture still loads" {
    const testing = std.testing;
    const fixture = try std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        "tests/fixtures/compat/v0.1.0-package-v14.bspk",
        testing.allocator,
        .limited(1024 * 1024),
    );
    defer testing.allocator.free(fixture);

    try testing.expectEqual(@as(u32, 14), version_from_bytes(fixture).?);

    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var stream: std.Io.Reader = .fixed(fixture);
    var compiled = try load_package(testing.allocator, &stream, &world, &spatial);
    defer compiled.deinit();

    try testing.expect(world.lookup_entity("FixtureHero") != null);
    try testing.expect(world.lookup_relation("Ready") != null);
    try testing.expect(compiled.routine_entries.contains("Idle"));
    try testing.expectEqual(@as(usize, 0), compiled.goals.items.len);
}

test "P44-01: checked-in version 15 package fixture still loads its goal" {
    const testing = std.testing;
    const fixture = try std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        "tests/fixtures/compat/v0.2.0-package-v15.bspk",
        testing.allocator,
        .limited(1024 * 1024),
    );
    defer testing.allocator.free(fixture);

    // The current writer is version 16; this fixture pins that version 15 still loads.
    try testing.expectEqual(@as(u32, 15), version_from_bytes(fixture).?);

    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var stream: std.Io.Reader = .fixed(fixture);
    var compiled = try load_package(testing.allocator, &stream, &world, &spatial);
    defer compiled.deinit();

    try testing.expect(world.lookup_entity("FixtureHero") != null);
    try testing.expect(compiled.routine_entries.contains("Idle"));
    try testing.expectEqual(@as(usize, 1), compiled.goals.items.len);
    const goal = compiled.goals.items[0].goal;
    try testing.expectEqualStrings("FinishShift", world.get_entity_name(goal.entity).?);
    try testing.expectEqual(@as(usize, 1), goal.needs.len);
    try testing.expectEqualStrings("Sit", world.get_entity_name(goal.needs[0].entity).?);
    try testing.expectEqualStrings("Ready", goal.needs[0].relation);
    try testing.expectEqualStrings("Bench", world.get_entity_name(goal.needs[0].room.?).?);
}

const SPELLBOOK_FIXTURE =
    \\entity FixtureHero
    \\relation Ready(subject)
    \\spellbook FixtureGrimoire:
    \\  power FixturePowerA, FixturePowerB
    \\  element FixtureElementA, FixtureElementB
    \\  form FixtureFormA, FixtureFormB
    \\  spell FixtureSpell: FixturePowerB, FixtureElementA, FixtureFormA
    \\routine Idle(FixtureHero):
    \\  wait 1 ticks
;

test "P44-04: package version 17 round-trips a spellbook and loads a version 16 payload with none" {
    const testing = std.testing;
    const compiler = @import("compiler.zig");
    var world1 = try World.init(testing.allocator, 1024 * 1024);
    defer world1.deinit();
    var compiled1 = try compiler.compile_source(testing.allocator, &world1, null, SPELLBOOK_FIXTURE);
    defer compiled1.deinit();
    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();
    var lw17 = ListWriter.init(&buffer);
    try save_package(testing.allocator, &lw17.writer, &compiled1, &world1, null);

    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();
    var stream: std.Io.Reader = .fixed(buffer.items);
    var compiled2 = try load_package(testing.allocator, &stream, &world2, null);
    defer compiled2.deinit();
    try testing.expectEqual(@as(usize, 1), compiled2.spellbooks.items.len);
    const book = &compiled2.spellbooks.items[0].book;
    try testing.expectEqualStrings("FixtureGrimoire", world2.get_entity_name(book.entity).?);
    try testing.expectEqual(@as(usize, 6), book.words.len);
    try testing.expectEqualStrings("FixturePowerB", world2.get_entity_name(book.words[1].entity).?);
    try testing.expectEqual(spell_mod.Kind.power, book.words[1].kind);
    try testing.expectEqual(@as(u16, 2), book.words[1].tier);
    try testing.expectEqual(@as(usize, 1), book.spells.len);
    const beta_word = world2.lookup_entity("FixturePowerB").?;
    const gamma_word = world2.lookup_entity("FixtureElementA").?;
    const epsilon_word = world2.lookup_entity("FixtureFormA").?;
    try testing.expectEqual(book.spells[0].entity, spell_mod.resolve(book, beta_word, gamma_word, epsilon_word).?.entity);

    // A payload that ends before the spellbook table is a version 16 package and loads none.
    const v16 = try testing.allocator.dupe(u8, buffer.items[0 .. buffer.items.len - EMPTY_TAIL_AFTER_V16]);
    defer testing.allocator.free(v16);
    reseal_for_test(v16, 16);
    var world3 = try World.init(testing.allocator, 1024 * 1024);
    defer world3.deinit();
    var v16_stream: std.Io.Reader = .fixed(v16);
    var loaded = try load_package(testing.allocator, &v16_stream, &world3, null);
    defer loaded.deinit();
    try testing.expectEqual(@as(usize, 0), loaded.spellbooks.items.len);
}

test "P44-04: checked-in version 17 package fixture carries a spellbook" {
    const testing = std.testing;
    const fixture = try std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        "tests/fixtures/compat/v0.2.0-package-v17.bspk",
        testing.allocator,
        .limited(1024 * 1024),
    );
    defer testing.allocator.free(fixture);

    try testing.expectEqual(@as(u32, 17), version_from_bytes(fixture).?);

    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var stream: std.Io.Reader = .fixed(fixture);
    var compiled = try load_package(testing.allocator, &stream, &world, &spatial);
    defer compiled.deinit();

    try testing.expect(world.lookup_entity("FixtureHero") != null);
    try testing.expect(compiled.routine_entries.contains("Idle"));
    try testing.expectEqual(@as(usize, 1), compiled.spellbooks.items.len);
    const book = &compiled.spellbooks.items[0].book;
    try testing.expectEqualStrings("FixtureGrimoire", world.get_entity_name(book.entity).?);
    const kindle = book.spells[0].entity;
    try testing.expectEqualStrings("FixtureSpell", world.get_entity_name(kindle).?);
    try testing.expectEqual(kindle, spell_mod.named_text(book, &world, "fixturespell").?.entity);
}

const DECISION_FIXTURE =
    \\entity FixtureDecider
    \\relation Turn(who)
    \\relation Open(who)
    \\decision FixtureDecision:
    \\  actor FixtureDecider
    \\  fires FixtureChoice
    \\  requires Turn(FixtureDecider)
    \\  option FixtureOptionA:
    \\    picks 3 when Open(FixtureDecider)
    \\    drops 1 when Turn(FixtureDecider)
    \\  option FixtureOptionB:
    \\    picks 1 when Open(FixtureDecider)
    \\routine Idle(FixtureDecider):
    \\  wait 1 ticks
;

test "P44-05: package version 18 round-trips a decision and loads a version 17 payload with none" {
    const testing = std.testing;
    const compiler = @import("compiler.zig");
    var world1 = try World.init(testing.allocator, 1024 * 1024);
    defer world1.deinit();
    var compiled1 = try compiler.compile_source(testing.allocator, &world1, null, DECISION_FIXTURE);
    defer compiled1.deinit();
    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();
    var lw = ListWriter.init(&buffer);
    try save_package(testing.allocator, &lw.writer, &compiled1, &world1, null);

    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();
    var stream: std.Io.Reader = .fixed(buffer.items);
    var compiled2 = try load_package(testing.allocator, &stream, &world2, null);
    defer compiled2.deinit();
    try testing.expectEqual(@as(usize, 1), compiled2.decisions.items.len);
    const decision = &compiled2.decisions.items[0].decision;
    try testing.expectEqualStrings("FixtureDecision", world2.get_entity_name(decision.entity).?);
    try testing.expectEqualStrings("FixtureDecider", world2.get_entity_name(decision.actor).?);
    try testing.expectEqualStrings("FixtureChoice", world2.get_entity_name(decision.cue).?);
    try testing.expectEqual(@as(usize, 1), decision.clauses.len);
    try testing.expectEqualStrings("Turn", decision.clauses[0].relation);
    try testing.expectEqual(world2.lookup_entity("FixtureDecider").?, decision.clauses[0].subject.?);
    try testing.expectEqual(@as(usize, 2), decision.options.len);
    try testing.expectEqualStrings("FixtureOptionA", world2.get_entity_name(decision.options[0].entity).?);
    try testing.expectEqual(@as(i32, 3), decision.options[0].picks[0].points);
    try testing.expectEqual(@as(i32, -1), decision.options[0].picks[1].points);
    try testing.expectEqual(@as(i32, 1), decision.options[1].picks[0].points);

    // A payload that ends before the decision table is a version 17 package and loads none.
    const v17 = try testing.allocator.dupe(u8, buffer.items[0 .. buffer.items.len - EMPTY_TAIL_AFTER_V17]);
    defer testing.allocator.free(v17);
    reseal_for_test(v17, 17);
    var world3 = try World.init(testing.allocator, 1024 * 1024);
    defer world3.deinit();
    var v17_stream: std.Io.Reader = .fixed(v17);
    var loaded = try load_package(testing.allocator, &v17_stream, &world3, null);
    defer loaded.deinit();
    try testing.expectEqual(@as(usize, 0), loaded.decisions.items.len);
    try testing.expect(loaded.routine_entries.contains("Idle"));
}

test "P44-05: checked-in version 18 package fixture carries a decision" {
    const testing = std.testing;
    const fixture = try std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        "tests/fixtures/compat/v0.2.0-package-v18.bspk",
        testing.allocator,
        .limited(1024 * 1024),
    );
    defer testing.allocator.free(fixture);

    try testing.expectEqual(@as(u32, 18), version_from_bytes(fixture).?);

    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var stream: std.Io.Reader = .fixed(fixture);
    var compiled = try load_package(testing.allocator, &stream, &world, null);
    defer compiled.deinit();

    try testing.expect(world.lookup_entity("FixtureDecider") != null);
    try testing.expect(compiled.routine_entries.contains("Idle"));
    try testing.expectEqual(@as(usize, 1), compiled.decisions.items.len);
    const decision = &compiled.decisions.items[0].decision;
    try testing.expectEqualStrings("FixtureDecision", world.get_entity_name(decision.entity).?);
    try testing.expectEqualStrings("FixtureChoice", world.get_entity_name(decision.cue).?);
    try testing.expectEqual(@as(usize, 2), decision.options.len);
}

test "P44-02: checked-in current package fixture carries aggregate conditions" {
    const testing = std.testing;
    const fixture = try std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        "tests/fixtures/compat/v0.2.0-package-v16.bspk",
        testing.allocator,
        .limited(1024 * 1024),
    );
    defer testing.allocator.free(fixture);

    // The current writer is version 19; this fixture pins that version 16 still loads.
    try testing.expectEqual(@as(u32, 16), version_from_bytes(fixture).?);

    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var stream: std.Io.Reader = .fixed(fixture);
    var compiled = try load_package(testing.allocator, &stream, &world, &spatial);
    defer compiled.deinit();

    try testing.expect(world.lookup_entity("FixtureHero") != null);
    try testing.expect(compiled.routine_entries.contains("Idle"));
    // The routine's bytecode holds both aggregate opcodes, so the fixture pins version 16.
    const code = compiled.chunk.code.items;
    var saw_count = false;
    var saw_points = false;
    for (code) |byte| {
        if (byte == @intFromEnum(Opcode.query_count)) saw_count = true;
        if (byte == @intFromEnum(Opcode.query_points)) saw_points = true;
    }
    try testing.expect(saw_count and saw_points);
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

    // A private directory per run: two test binaries run this test at the same time.
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir_path = try tmp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(dir_path);
    const tmp_path = try std.fs.path.join(testing.allocator, &.{ dir_path, "test_scenario.bspk" });
    defer testing.allocator.free(tmp_path);

    try save_package_file(testing.allocator, testing.io, tmp_path, &compiled1, &world1, null);

    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();

    var compiled2 = try load_package_file(testing.allocator, testing.io, tmp_path, &world2, null);
    defer compiled2.deinit();

    try testing.expect(world2.lookup_entity("Cat") != null);
    try testing.expect(world2.lookup_entity("Cheese") != null);
    try testing.expect(compiled2.routine_entries.contains("Prowl"));
    try testing.expectEqualStrings("Cat", compiled2.routine_entities.get("Prowl").?);
}

/// Bytes that empty sections added after version 9 append to every package tail: the
/// command and alias counts (version 10) and the score count (version 11). Tests that locate
/// earlier sections from the end of a package add this; a later version that appends a
/// section adds its empty size here, so those tests need no other change.
const EMPTY_TAIL_AFTER_V9: usize = 4 + 4 + EMPTY_TAIL_AFTER_V10;
/// The empty score count (version 11) and cast count (version 12), for tests that locate
/// version 10 sections from the end.
const EMPTY_TAIL_AFTER_V10: usize = 4 + EMPTY_TAIL_AFTER_V11;
/// The empty cast count (version 12) and cue guard count (version 13).
const EMPTY_TAIL_AFTER_V11: usize = 4 + EMPTY_TAIL_AFTER_V12;
/// The empty cue guard count (version 13) and the sections after it.
const EMPTY_TAIL_AFTER_V12: usize = 4 + EMPTY_TAIL_AFTER_V13;
/// The empty goal count (version 15) and the sections after it.
const EMPTY_TAIL_AFTER_V13: usize = 4 + EMPTY_TAIL_AFTER_V16;
/// The spellbook and decision sections after version 16, for tests that locate version 16
/// sections from the end.
const EMPTY_TAIL_AFTER_V16: usize = 4 + EMPTY_TAIL_AFTER_V17;
/// The decision and axis sections after version 17, for tests that locate version 17 sections
/// from the end.
const EMPTY_TAIL_AFTER_V17: usize = 4 + EMPTY_TAIL_AFTER_V18;
/// The axis and red-line sections after version 18, for tests that locate version 18 sections
/// from the end.
const EMPTY_TAIL_AFTER_V18: usize = 4 + EMPTY_TAIL_AFTER_V19;
/// The red-line and dilemma sections after version 19, for tests that locate version 19
/// sections from the end.
const EMPTY_TAIL_AFTER_V19: usize = 4 + EMPTY_TAIL_AFTER_V20;
/// The empty dilemma count (version 21) and the art section after it, for tests that locate
/// version 20 sections from the end. Version 22's drift groups and version 23's appeal groups add
/// nothing when there are no dilemmas.
const EMPTY_TAIL_AFTER_V20: usize = 4 + EMPTY_TAIL_AFTER_V23;
/// The empty art section (version 24): a zero colour count and a zero image count.
const EMPTY_TAIL_AFTER_V23: usize = 2 + 4;

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

    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();
    var lw3 = ListWriter.init(&buffer);
    try save_package(testing.allocator, &lw3.writer, &compiled1, &world1, null);

    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();
    var stream: std.Io.Reader = .fixed(buffer.items);
    var compiled2 = try load_package(testing.allocator, &stream, &world2, null);
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

    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();
    var lw4 = ListWriter.init(&buffer);
    try save_package(testing.allocator, &lw4.writer, &compiled, &world, null);

    // Draft tail: count u32, then entity u32, 4 note bytes, inverse flag u8, inverse u32.
    // The draft table is followed by empty society, duel, degradation, grid, and agenda counts,
    // then the sections added after version 9.
    const declaration_tail_len = 20 + EMPTY_TAIL_AFTER_V9;
    const tail_len = 4 + 4 + 4 + 1 + 4;
    const first_note = buffer.items.len - declaration_tail_len - tail_len + 8;
    {
        const bad = try testing.allocator.dupe(u8, buffer.items);
        defer testing.allocator.free(bad);
        bad[first_note] = 7; // one past B
        reseal_for_test(bad, PACKAGE_VERSION);
        var world2 = try World.init(testing.allocator, 1024 * 1024);
        defer world2.deinit();
        var stream: std.Io.Reader = .fixed(bad);
        try testing.expectError(error.InvalidDraftNote, load_package(testing.allocator, &stream, &world2, null));
    }
    {
        // A real version 4 payload ends after the duel table and loads no degradation profiles.
        const v4 = try testing.allocator.dupe(u8, buffer.items[0 .. buffer.items.len - 12 - EMPTY_TAIL_AFTER_V9]);
        defer testing.allocator.free(v4);
        reseal_for_test(v4, 4);
        var world2 = try World.init(testing.allocator, 1024 * 1024);
        defer world2.deinit();
        var stream: std.Io.Reader = .fixed(v4);
        var loaded = try load_package(testing.allocator, &stream, &world2, null);
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
        var stream: std.Io.Reader = .fixed(v1);
        var loaded = try load_package(testing.allocator, &stream, &world2, null);
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
    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();
    var lw5 = ListWriter.init(&buffer);
    try save_package(testing.allocator, &lw5.writer, &compiled1, &world1, null);

    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();
    var stream: std.Io.Reader = .fixed(buffer.items);
    var compiled2 = try load_package(testing.allocator, &stream, &world2, null);
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
    const grid_count_len = 4 + 4 + EMPTY_TAIL_AFTER_V9;
    const bytes_after_spill = 1 + 3 * (4 + 8) + 1 + (4 + 4 + 4 + 1) + 5 * 4 + grid_count_len;
    const spill_offset = buffer.items.len - bytes_after_spill - 4;
    var v5 = std.array_list.Managed(u8).init(testing.allocator);
    defer v5.deinit();
    try v5.appendSlice(buffer.items[0..spill_offset]);
    try v5.appendSlice(buffer.items[spill_offset + 4 .. buffer.items.len - grid_count_len]);
    reseal_for_test(v5.items, 5);
    var world3 = try World.init(testing.allocator, 1024 * 1024);
    defer world3.deinit();
    var v5_stream: std.Io.Reader = .fixed(v5.items);
    var compiled3 = try load_package(testing.allocator, &v5_stream, &world3, null);
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
    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();
    var lw6 = ListWriter.init(&buffer);
    try save_package(testing.allocator, &lw6.writer, &compiled1, &world1, &spatial1);

    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();
    var spatial2 = SpatialSystem.init(testing.allocator);
    defer spatial2.deinit();
    var stream: std.Io.Reader = .fixed(buffer.items);
    var compiled2 = try load_package(testing.allocator, &stream, &world2, &spatial2);
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
    const agenda_count_len = 4 + EMPTY_TAIL_AFTER_V9;
    const first_cell_index = buffer.items.len - agenda_count_len - rules_len - cells_len;
    {
        const bad = try testing.allocator.dupe(u8, buffer.items);
        defer testing.allocator.free(bad);
        std.mem.writeInt(u32, bad[first_cell_index..][0..4], 6, .little); // one past the 3x2 area
        reseal_for_test(bad, PACKAGE_VERSION);
        var world3 = try World.init(testing.allocator, 1024 * 1024);
        defer world3.deinit();
        var bad_stream: std.Io.Reader = .fixed(bad);
        try testing.expectError(error.InvalidGridConfig, load_package(testing.allocator, &bad_stream, &world3, null));
    }
    {
        const bad = try testing.allocator.dupe(u8, buffer.items);
        defer testing.allocator.free(bad);
        bad[first_cell_index + 4] = 5; // past smoke, the last attribute
        reseal_for_test(bad, PACKAGE_VERSION);
        var world3 = try World.init(testing.allocator, 1024 * 1024);
        defer world3.deinit();
        var bad_stream: std.Io.Reader = .fixed(bad);
        try testing.expectError(error.InvalidGridConfig, load_package(testing.allocator, &bad_stream, &world3, null));
    }
    {
        // A version 7 payload has no rates; its grids load with every rule off.
        const v7 = try testing.allocator.dupe(u8, buffer.items[0 .. buffer.items.len - agenda_count_len - rules_len]);
        defer testing.allocator.free(v7);
        reseal_for_test(v7, 7);
        var world3 = try World.init(testing.allocator, 1024 * 1024);
        defer world3.deinit();
        var v7_stream: std.Io.Reader = .fixed(v7);
        var loaded = try load_package(testing.allocator, &v7_stream, &world3, null);
        defer loaded.deinit();
        try testing.expect(!loaded.grids.items[0].rules.any());

        // Version 7 predates the burning attribute, so its byte is corrupt there.
        v7[first_cell_index + 4] = @intFromEnum(grid_mod.Attribute.burning);
        reseal_for_test(v7, 7);
        var world4 = try World.init(testing.allocator, 1024 * 1024);
        defer world4.deinit();
        var bad_stream: std.Io.Reader = .fixed(v7);
        try testing.expectError(error.InvalidGridConfig, load_package(testing.allocator, &bad_stream, &world4, null));
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
        var v6_stream: std.Io.Reader = .fixed(v6);
        var loaded = try load_package(testing.allocator, &v6_stream, &world3, &spatial3);
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
    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();
    var lw7 = ListWriter.init(&buffer);
    try save_package(testing.allocator, &lw7.writer, &compiled1, &world1, null);

    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();
    var stream: std.Io.Reader = .fixed(buffer.items);
    var compiled2 = try load_package(testing.allocator, &stream, &world2, null);
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
        bad[bad.len - EMPTY_TAIL_AFTER_V9 - 1] = 2; // the last clause's negated flag
        reseal_for_test(bad, PACKAGE_VERSION);
        var world3 = try World.init(testing.allocator, 1024 * 1024);
        defer world3.deinit();
        var bad_stream: std.Io.Reader = .fixed(bad);
        try testing.expectError(error.InvalidAgendaConfig, load_package(testing.allocator, &bad_stream, &world3, null));
    }
    {
        // A version 8 payload ends before the agenda table and loads none.
        const agenda_section_len = 4 + 4 + 4 + 4 + 2 + 4 + 1 + 1 + 2 * clause_len;
        const v8 = try testing.allocator.dupe(u8, buffer.items[0 .. buffer.items.len - agenda_section_len - EMPTY_TAIL_AFTER_V9]);
        defer testing.allocator.free(v8);
        reseal_for_test(v8, 8);
        var world3 = try World.init(testing.allocator, 1024 * 1024);
        defer world3.deinit();
        var v8_stream: std.Io.Reader = .fixed(v8);
        var loaded = try load_package(testing.allocator, &v8_stream, &world3, null);
        defer loaded.deinit();
        try testing.expectEqual(@as(usize, 0), loaded.agendas.items.len);
    }
}

test "P26-01: package version 10 round-trips commands and aliases and loads version 9" {
    const testing = std.testing;
    const compiler = @import("compiler.zig");
    const script =
        \\command Pours: "pour <thing> into <thing>"
        \\alias OilLamp: "lantern"
    ;
    var world1 = try World.init(testing.allocator, 1024 * 1024);
    defer world1.deinit();
    var compiled1 = try compiler.compile_source(testing.allocator, &world1, null, script);
    defer compiled1.deinit();
    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();
    var lw8 = ListWriter.init(&buffer);
    try save_package(testing.allocator, &lw8.writer, &compiled1, &world1, null);

    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();
    var stream: std.Io.Reader = .fixed(buffer.items);
    var compiled2 = try load_package(testing.allocator, &stream, &world2, null);
    defer compiled2.deinit();
    try testing.expectEqualStrings("pour <thing> into <thing>", compiled2.commands.items[0].text);
    try testing.expectEqualStrings("lantern", compiled2.aliases.items[0].phrases[0]);
    try testing.expectEqualStrings("OilLamp", world2.get_entity_name(compiled2.aliases.items[0].entity).?);

    // Tail: command count, cue and frame strings, alias count, entity, phrase count, phrase.
    const alias_section_len = 4 + 4 + 1 + (2 + "lantern".len);
    const command_section_len = 4 + (2 + "Pours".len) + (2 + "pour <thing> into <thing>".len);
    {
        // A frame whose verb is not lowercase is rejected on load.
        const bad = try testing.allocator.dupe(u8, buffer.items);
        defer testing.allocator.free(bad);
        const frame_start = bad.len - EMPTY_TAIL_AFTER_V10 - alias_section_len - "pour <thing> into <thing>".len;
        bad[frame_start] = 'P';
        reseal_for_test(bad, PACKAGE_VERSION);
        var world3 = try World.init(testing.allocator, 1024 * 1024);
        defer world3.deinit();
        var bad_stream: std.Io.Reader = .fixed(bad);
        try testing.expectError(error.InvalidCommandConfig, load_package(testing.allocator, &bad_stream, &world3, null));
    }
    {
        const v9 = try testing.allocator.dupe(u8, buffer.items[0 .. buffer.items.len - EMPTY_TAIL_AFTER_V10 - alias_section_len - command_section_len]);
        defer testing.allocator.free(v9);
        reseal_for_test(v9, 9);
        var world3 = try World.init(testing.allocator, 1024 * 1024);
        defer world3.deinit();
        var v9_stream: std.Io.Reader = .fixed(v9);
        var loaded = try load_package(testing.allocator, &v9_stream, &world3, null);
        defer loaded.deinit();
        try testing.expectEqual(@as(usize, 0), loaded.commands.items.len + loaded.aliases.items.len);
    }
}

test "P28-03: package version 11 round-trips scores, rejects bad MML, and loads version 10" {
    const testing = std.testing;
    const compiler = @import("compiler.zig");
    const script =
        \\score Night:
        \\  lead "t96 o5 l8 c e g e"
        \\  drums "k4 h4"
        \\  scene Courtyard
        \\  scene Wine Cellar
    ;
    var world1 = try World.init(testing.allocator, 1024 * 1024);
    defer world1.deinit();
    var compiled1 = try compiler.compile_source(testing.allocator, &world1, null, script);
    defer compiled1.deinit();
    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();
    var lw9 = ListWriter.init(&buffer);
    try save_package(testing.allocator, &lw9.writer, &compiled1, &world1, null);

    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();
    var stream: std.Io.Reader = .fixed(buffer.items);
    var compiled2 = try load_package(testing.allocator, &stream, &world2, null);
    defer compiled2.deinit();
    const score = compiled2.scores.items[0];
    try testing.expectEqualStrings("Night", score.name);
    try testing.expectEqualStrings("Wine Cellar", score.scenes[1]);
    try testing.expectEqualStrings("t96 o5 l8 c e g e", score.parts[0]);
    try testing.expectEqualStrings("", score.parts[1]);
    try testing.expectEqualStrings("k4 h4", score.parts[3]);

    // Tail: count, name, scene count, two scenes, four parts.
    const score_section_len = 4 + (2 + "Night".len) + 1 + (2 + "Courtyard".len) + (2 + "Wine Cellar".len) +
        (2 + "t96 o5 l8 c e g e".len) + 2 + 2 + (2 + "k4 h4".len);
    {
        // A drum letter smuggled into the lead part is rejected on load, as the compiler would.
        const bad = try testing.allocator.dupe(u8, buffer.items);
        defer testing.allocator.free(bad);
        const lead_start = bad.len - EMPTY_TAIL_AFTER_V11 - (2 + "k4 h4".len) - 2 - 2 - "t96 o5 l8 c e g e".len;
        try testing.expectEqual(@as(u8, 't'), bad[lead_start]);
        bad[lead_start + 4] = 'k';
        reseal_for_test(bad, PACKAGE_VERSION);
        var world3 = try World.init(testing.allocator, 1024 * 1024);
        defer world3.deinit();
        var bad_stream: std.Io.Reader = .fixed(bad);
        try testing.expectError(error.InvalidScoreConfig, load_package(testing.allocator, &bad_stream, &world3, null));
    }
    {
        const v10 = try testing.allocator.dupe(u8, buffer.items[0 .. buffer.items.len - score_section_len - EMPTY_TAIL_AFTER_V11]);
        defer testing.allocator.free(v10);
        reseal_for_test(v10, 10);
        var world3 = try World.init(testing.allocator, 1024 * 1024);
        defer world3.deinit();
        var v10_stream: std.Io.Reader = .fixed(v10);
        var loaded = try load_package(testing.allocator, &v10_stream, &world3, null);
        defer loaded.deinit();
        try testing.expectEqual(@as(usize, 0), loaded.scores.items.len);
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

    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();
    var lw10 = ListWriter.init(&buffer);
    try save_package(testing.allocator, &lw10.writer, &compiled1, &world1, null);

    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();
    var stream: std.Io.Reader = .fixed(buffer.items);
    var compiled2 = try load_package(testing.allocator, &stream, &world2, null);
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

    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();
    var lw11 = ListWriter.init(&buffer);
    try save_package(testing.allocator, &lw11.writer, &compiled1, &world1, &spatial1);

    {
        var world2 = try World.init(testing.allocator, 1024 * 1024);
        defer world2.deinit();
        var spatial2 = SpatialSystem.init(testing.allocator);
        defer spatial2.deinit();
        var stream: std.Io.Reader = .fixed(buffer.items);
        var compiled2 = try load_package(testing.allocator, &stream, &world2, &spatial2);
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
        var stream: std.Io.Reader = .fixed(v2);
        try testing.expectError(error.InvalidWhenEdge, load_package(testing.allocator, &stream, &world2, &spatial2));
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
        \\  fallback "Ask me another."
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
    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();
    var lw12 = ListWriter.init(&buffer);
    try save_package(testing.allocator, &lw12.writer, &compiled1, &world1, &spatial1);

    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();
    var spatial2 = SpatialSystem.init(testing.allocator);
    defer spatial2.deinit();
    var stream: std.Io.Reader = .fixed(buffer.items);
    var compiled2 = try load_package(testing.allocator, &stream, &world2, &spatial2);
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
    // D-076: version 14 keeps both fallback lines in order.
    const fallbacks = compiled2.duels.items[0].config.fallbacks;
    try testing.expectEqual(@as(usize, 2), fallbacks.len);
    try testing.expectEqualStrings("Ask me another.", fallbacks[1]);

    // A version 13 package could only hold one line, so a count of two is corrupt there.
    const v13 = try testing.allocator.dupe(u8, buffer.items);
    defer testing.allocator.free(v13);
    reseal_for_test(v13, 13);
    var world3 = try World.init(testing.allocator, 1024 * 1024);
    defer world3.deinit();
    var spatial3 = SpatialSystem.init(testing.allocator);
    defer spatial3.deinit();
    var stream3: std.Io.Reader = .fixed(v13);
    try testing.expectError(error.InvalidDuelConfig, load_package(testing.allocator, &stream3, &world3, &spatial3));
}

test "D-065: package version 12 round-trips cast places, rejects a bad mark, and loads version 11" {
    const testing = std.testing;
    const compiler = @import("compiler.zig");
    const script =
        \\scene Quay:
        \\  cast: Pilot
        \\  marks: Steps, Pier
        \\scene Ferry:
        \\  cast: Captain
        \\  marks: Deck
    ;
    var world1 = try World.init(testing.allocator, 1024 * 1024);
    defer world1.deinit();
    var spatial1 = SpatialSystem.init(testing.allocator);
    defer spatial1.deinit();
    var compiled1 = try compiler.compile_source(testing.allocator, &world1, &spatial1, script);
    defer compiled1.deinit();
    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();
    var lw13 = ListWriter.init(&buffer);
    try save_package(testing.allocator, &lw13.writer, &compiled1, &world1, &spatial1);

    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();
    var spatial2 = SpatialSystem.init(testing.allocator);
    defer spatial2.deinit();
    var stream: std.Io.Reader = .fixed(buffer.items);
    var compiled2 = try load_package(testing.allocator, &stream, &world2, &spatial2);
    defer compiled2.deinit();
    try testing.expectEqual(@as(usize, 2), compiled2.cast.items.len);
    const captain = compiled2.cast.items[1];
    try testing.expectEqualStrings("Captain", world2.get_entity_name(captain.actor).?);
    try testing.expectEqualStrings("Deck", spatial2.graph.get_waypoint(captain.mark).?.name);

    // Tail: count, then entity and mark per member.
    const cast_section_len = 4 + 2 * (4 + 2);
    {
        const bad = try testing.allocator.dupe(u8, buffer.items);
        defer testing.allocator.free(bad);
        std.mem.writeInt(u16, bad[bad.len - EMPTY_TAIL_AFTER_V12 - 2 ..][0..2], 99, .little);
        reseal_for_test(bad, PACKAGE_VERSION);
        var world3 = try World.init(testing.allocator, 1024 * 1024);
        defer world3.deinit();
        var bad_stream: std.Io.Reader = .fixed(bad);
        try testing.expectError(error.InvalidProgramWaypoint, load_package(testing.allocator, &bad_stream, &world3, null));
    }
    {
        const v11 = try testing.allocator.dupe(u8, buffer.items[0 .. buffer.items.len - cast_section_len - EMPTY_TAIL_AFTER_V12]);
        defer testing.allocator.free(v11);
        reseal_for_test(v11, 11);
        var world3 = try World.init(testing.allocator, 1024 * 1024);
        defer world3.deinit();
        var v11_stream: std.Io.Reader = .fixed(v11);
        var loaded = try load_package(testing.allocator, &v11_stream, &world3, null);
        defer loaded.deinit();
        try testing.expectEqual(@as(usize, 0), loaded.cast.items.len);
    }
}

test "D-072: package version 13 round-trips cue guards, rejects a bad slot, and loads version 12" {
    const testing = std.testing;
    const compiler = @import("compiler.zig");
    const script =
        \\entity Cat, Guard, Cheese
        \\on cue Steal(Cat, victim) where Carries(victim, Cheese):
        \\  remember Stolen(Cheese)
    ;
    var world1 = try World.init(testing.allocator, 1024 * 1024);
    defer world1.deinit();
    var compiled1 = try compiler.compile_source(testing.allocator, &world1, null, script);
    defer compiled1.deinit();
    try testing.expectEqual(@as(usize, 1), compiled1.cue_guards.items.len);
    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();
    var lw14 = ListWriter.init(&buffer);
    try save_package(testing.allocator, &lw14.writer, &compiled1, &world1, null);

    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();
    var stream: std.Io.Reader = .fixed(buffer.items);
    var compiled2 = try load_package(testing.allocator, &stream, &world2, null);
    defer compiled2.deinit();
    try testing.expectEqual(@as(usize, 1), compiled2.cue_guards.items.len);
    const cat = world2.lookup_entity("Cat").?;
    const guard_ent = world2.lookup_entity("Guard").?;
    const cheese = world2.lookup_entity("Cheese").?;
    // The loaded guard still binds `victim` to the cue's target.
    try testing.expectEqual(@as(?usize, null), compiled2.select_cue_handler(&world2, "Steal", cat, guard_ent, null));
    _ = try world2.remember(guard_ent, try world2.intern_relation("Carries", .set), cheese.to_int(), 0);
    try testing.expect(compiled2.select_cue_handler(&world2, "Steal", cat, guard_ent, null) != null);

    // Tail: count, then pc, three slot bytes, clause count, and one clause of 2 + 5 + 5 bytes.
    const guard_section_len = 4 + 4 + 3 + 2 + (2 + 5 + 5);
    {
        // The clause's subject is the bound `victim`, variable slot 0; slot 9 cannot exist.
        const bad = try testing.allocator.dupe(u8, buffer.items);
        defer testing.allocator.free(bad);
        std.mem.writeInt(u32, bad[bad.len - EMPTY_TAIL_AFTER_V13 - 5 - 4 ..][0..4], 9, .little);
        reseal_for_test(bad, PACKAGE_VERSION);
        var world3 = try World.init(testing.allocator, 1024 * 1024);
        defer world3.deinit();
        var bad_stream: std.Io.Reader = .fixed(bad);
        try testing.expectError(error.InvalidPatternVariable, load_package(testing.allocator, &bad_stream, &world3, null));
    }
    {
        const v12 = try testing.allocator.dupe(u8, buffer.items[0 .. buffer.items.len - EMPTY_TAIL_AFTER_V13 - guard_section_len]);
        defer testing.allocator.free(v12);
        reseal_for_test(v12, 12);
        var world3 = try World.init(testing.allocator, 1024 * 1024);
        defer world3.deinit();
        var v12_stream: std.Io.Reader = .fixed(v12);
        var loaded = try load_package(testing.allocator, &v12_stream, &world3, null);
        defer loaded.deinit();
        try testing.expectEqual(@as(usize, 0), loaded.cue_guards.items.len);
    }
}

test "P44-01: package version 15 round-trips goals and loads a version 14 payload with none" {
    const testing = std.testing;
    const compiler = @import("compiler.zig");
    const script =
        \\entity Hero, TelescopeLog
        \\relation Carries(holder, item)
        \\relation Read(who, item)
        \\scene: PlateArchive
        \\props: ExposureSlip
        \\marks: Archive
        \\goal RecoverThePlate:
        \\  need TakeTheSlip:
        \\    met Carries(Hero, ExposureSlip)
        \\    room Archive
        \\    hint 2 "Your notebook names the slip."
        \\  need ReadTheLog after TakeTheSlip:
        \\    met Read(Hero, TelescopeLog)
        \\    room Archive
    ;
    var world1 = try World.init(testing.allocator, 1024 * 1024);
    defer world1.deinit();
    var compiled1 = try compiler.compile_source(testing.allocator, &world1, null, script);
    defer compiled1.deinit();
    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();
    var lw15 = ListWriter.init(&buffer);
    try save_package(testing.allocator, &lw15.writer, &compiled1, &world1, null);

    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();
    var stream: std.Io.Reader = .fixed(buffer.items);
    var compiled2 = try load_package(testing.allocator, &stream, &world2, null);
    defer compiled2.deinit();
    try testing.expectEqual(@as(usize, 1), compiled2.goals.items.len);
    const goal = compiled2.goals.items[0].goal;
    try testing.expectEqualStrings("RecoverThePlate", world2.get_entity_name(goal.entity).?);
    try testing.expectEqual(@as(usize, 2), goal.needs.len);
    const take = goal.needs[0];
    try testing.expectEqualStrings("Carries", take.relation);
    try testing.expectEqualStrings("Hero", world2.get_entity_name(take.subject.?).?);
    try testing.expectEqualStrings("ExposureSlip", world2.get_entity_name(take.object.?).?);
    try testing.expectEqualStrings("Archive", world2.get_entity_name(take.room.?).?);
    try testing.expectEqual(@as(usize, 1), take.hints.len);
    try testing.expectEqual(@as(u2, @intFromEnum(take.hints[0].tier)), @as(u2, @intFromEnum(hint_mod.Tier.thing)));
    try testing.expectEqualStrings("Your notebook names the slip.", take.hints[0].text);
    try testing.expectEqual(@as(usize, 1), goal.needs[1].after.len);
    try testing.expectEqual(take.entity, goal.needs[1].after[0]);

    // A payload that ends before the goal table is a version 14 package and loads no goals.
    {
        const plain =
            \\entity FixtureHero
            \\routine Idle(FixtureHero):
            \\  wait 1 ticks
        ;
        var plain_world = try World.init(testing.allocator, 1024 * 1024);
        defer plain_world.deinit();
        var plain_compiled = try compiler.compile_source(testing.allocator, &plain_world, null, plain);
        defer plain_compiled.deinit();
        var plain_buffer = std.array_list.Managed(u8).init(testing.allocator);
        defer plain_buffer.deinit();
        var lw_plain = ListWriter.init(&plain_buffer);
        try save_package(testing.allocator, &lw_plain.writer, &plain_compiled, &plain_world, null);

        const v14 = try testing.allocator.dupe(u8, plain_buffer.items[0 .. plain_buffer.items.len - EMPTY_TAIL_AFTER_V13]);
        defer testing.allocator.free(v14);
        reseal_for_test(v14, 14);
        var world3 = try World.init(testing.allocator, 1024 * 1024);
        defer world3.deinit();
        var v14_stream: std.Io.Reader = .fixed(v14);
        var loaded = try load_package(testing.allocator, &v14_stream, &world3, null);
        defer loaded.deinit();
        try testing.expectEqual(@as(usize, 0), loaded.goals.items.len);
    }
}

const AXIS_FIXTURE =
    \\entity FixtureCaptain
    \\axis FixtureJustice between Cruelty and Leniency
    \\axis FixtureMercy between Vengeance and "Condoning Harm"
    \\remember FixtureJustice(FixtureCaptain, 8)
    \\remember FixtureMercy(FixtureCaptain, -3)
    \\routine Idle(FixtureCaptain):
    \\  wait 1 ticks
;

test "P45-01: package version 19 round-trips value axes and loads a version 18 payload with none" {
    const testing = std.testing;
    const compiler = @import("compiler.zig");
    var world1 = try World.init(testing.allocator, 1024 * 1024);
    defer world1.deinit();
    var compiled1 = try compiler.compile_source(testing.allocator, &world1, null, AXIS_FIXTURE);
    defer compiled1.deinit();
    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();
    var lw = ListWriter.init(&buffer);
    try save_package(testing.allocator, &lw.writer, &compiled1, &world1, null);

    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();
    var stream: std.Io.Reader = .fixed(buffer.items);
    var compiled2 = try load_package(testing.allocator, &stream, &world2, null);
    defer compiled2.deinit();
    try testing.expectEqual(@as(usize, 2), compiled2.axes.items.len);
    const mercy = compiled2.axes.items[1];
    try testing.expectEqualStrings("FixtureMercy", world2.get_relation_meta(mercy.relation).?.name);
    try testing.expectEqualStrings("Vengeance", world2.get_entity_name(mercy.poles[0]).?);
    try testing.expectEqualStrings("Condoning Harm", world2.get_entity_name(mercy.poles[1]).?);
    // The loaded world clamps the axis as the compiling world did.
    const bound = world2.value_bound(mercy.relation).?;
    try testing.expectEqual(value_mod.MIN, bound.min);
    try testing.expectEqual(value_mod.MAX, bound.max);
    const captain = world2.lookup_entity("FixtureCaptain").?;
    try world2.remember(captain, mercy.relation, 40, 0);
    try testing.expectEqual(@as(i32, value_mod.MAX), value_mod.value_of(&world2, captain, mercy).?);

    // A payload that ends before the axis table is a version 18 package and loads none.
    // The axis table is not empty here, so cut its whole length rather than the empty tail.
    const axis_table_len = 4 + compiled1.axes.items.len * (2 + 4 + 4) + EMPTY_TAIL_AFTER_V19;
    const v18_payload = buffer.items[0 .. buffer.items.len - axis_table_len];
    const v18_owned = try testing.allocator.dupe(u8, v18_payload);
    defer testing.allocator.free(v18_owned);
    reseal_for_test(v18_owned, 18);
    var world3 = try World.init(testing.allocator, 1024 * 1024);
    defer world3.deinit();
    var v18_stream: std.Io.Reader = .fixed(v18_owned);
    var loaded = try load_package(testing.allocator, &v18_stream, &world3, null);
    defer loaded.deinit();
    try testing.expectEqual(@as(usize, 0), loaded.axes.items.len);
    try testing.expect(world3.value_bound(world3.lookup_relation("FixtureMercy").?) == null);
    try testing.expect(loaded.routine_entries.contains("Idle"));
}

test "P45-01: a package axis on a set relation or with a bad pole is refused" {
    const testing = std.testing;
    const compiler = @import("compiler.zig");
    var world1 = try World.init(testing.allocator, 1024 * 1024);
    defer world1.deinit();
    var compiled1 = try compiler.compile_source(testing.allocator, &world1, null, AXIS_FIXTURE);
    defer compiled1.deinit();
    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();
    var lw = ListWriter.init(&buffer);
    try save_package(testing.allocator, &lw.writer, &compiled1, &world1, null);

    // The last axis entry, before the empty red-line count, is relation (u16) then two pole ids (u32). Point its second pole at an
    // entity that does not exist.
    const bad_pole = try testing.allocator.dupe(u8, buffer.items);
    defer testing.allocator.free(bad_pole);
    std.mem.writeInt(u32, bad_pole[bad_pole.len - 4 - EMPTY_TAIL_AFTER_V19 ..][0..4], 0xFFFF_FFF0, .little);
    reseal_for_test(bad_pole, PACKAGE_VERSION);
    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();
    var stream: std.Io.Reader = .fixed(bad_pole);
    try testing.expectError(error.InvalidProgramEntity, load_package(testing.allocator, &stream, &world2, null));

    // Point the axis at relation 0, which no table holds.
    const bad_relation = try testing.allocator.dupe(u8, buffer.items);
    defer testing.allocator.free(bad_relation);
    std.mem.writeInt(u16, bad_relation[bad_relation.len - 10 - EMPTY_TAIL_AFTER_V19 ..][0..2], 0, .little);
    reseal_for_test(bad_relation, PACKAGE_VERSION);
    var world3 = try World.init(testing.allocator, 1024 * 1024);
    defer world3.deinit();
    var stream3: std.Io.Reader = .fixed(bad_relation);
    try testing.expectError(error.InvalidAxisConfig, load_package(testing.allocator, &stream3, &world3, null));
}

test "P45-01: checked-in version 19 package fixture carries value axes" {
    const testing = std.testing;
    const fixture = try std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        "tests/fixtures/compat/v0.3.1-package-v19.bspk",
        testing.allocator,
        .limited(1024 * 1024),
    );
    defer testing.allocator.free(fixture);

    try testing.expectEqual(@as(u32, 19), version_from_bytes(fixture).?);

    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var stream: std.Io.Reader = .fixed(fixture);
    var compiled = try load_package(testing.allocator, &stream, &world, null);
    defer compiled.deinit();

    try testing.expect(compiled.routine_entries.contains("Idle"));
    try testing.expectEqual(@as(usize, 2), compiled.axes.items.len);
    try testing.expectEqualStrings("FixtureJustice", world.get_relation_meta(compiled.axes.items[0].relation).?.name);
    try testing.expectEqualStrings("Condoning Harm", world.get_entity_name(compiled.axes.items[1].poles[1]).?);
}

const RED_LINE_FIXTURE =
    \\entity FixtureJudge
    \\relation Accused(who)
    \\red lines FixtureJudge: FixtureExecute
    \\decision FixtureVerdict:
    \\  actor FixtureJudge
    \\  fires FixtureJudged
    \\  requires Accused(FixtureThief)
    \\  option FixtureExecute:
    \\    picks 9 when Accused(FixtureThief)
    \\  option FixturePardon:
    \\    picks 1 when Accused(FixtureThief)
    \\routine Idle(FixtureJudge):
    \\  wait 1 ticks
;

test "P45-02: package version 20 round-trips red lines and loads a version 19 payload with none" {
    const testing = std.testing;
    const compiler = @import("compiler.zig");
    var world1 = try World.init(testing.allocator, 1024 * 1024);
    defer world1.deinit();
    var compiled1 = try compiler.compile_source(testing.allocator, &world1, null, RED_LINE_FIXTURE);
    defer compiled1.deinit();
    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();
    var lw = ListWriter.init(&buffer);
    try save_package(testing.allocator, &lw.writer, &compiled1, &world1, null);

    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();
    var stream: std.Io.Reader = .fixed(buffer.items);
    var compiled2 = try load_package(testing.allocator, &stream, &world2, null);
    defer compiled2.deinit();
    try testing.expectEqual(@as(usize, 1), compiled2.red_lines.items.len);
    const set = compiled2.red_lines.items[0].red_lines;
    try testing.expectEqualStrings("FixtureJudge", world2.get_entity_name(set.actor).?);
    try testing.expectEqualStrings("FixtureExecute", world2.get_entity_name(set.options[0]).?);

    // A payload that ends before the red-line table is a version 19 package and loads none.
    const red_table_len = 4 + 4 + 1 + 4 + EMPTY_TAIL_AFTER_V20;
    const v19 = try testing.allocator.dupe(u8, buffer.items[0 .. buffer.items.len - red_table_len]);
    defer testing.allocator.free(v19);
    reseal_for_test(v19, 19);
    var world3 = try World.init(testing.allocator, 1024 * 1024);
    defer world3.deinit();
    var v19_stream: std.Io.Reader = .fixed(v19);
    var loaded = try load_package(testing.allocator, &v19_stream, &world3, null);
    defer loaded.deinit();
    try testing.expectEqual(@as(usize, 0), loaded.red_lines.items.len);
    try testing.expectEqual(@as(usize, 1), loaded.decisions.items.len);

    // A package whose red line names an option no decision offers that character is refused.
    const bad = try testing.allocator.dupe(u8, buffer.items);
    defer testing.allocator.free(bad);
    // Point the veto at the judge's own entity, which is not an option of any decision.
    std.mem.writeInt(u32, bad[bad.len - 4 - EMPTY_TAIL_AFTER_V20 ..][0..4], world1.lookup_entity("FixtureJudge").?.to_int(), .little);
    reseal_for_test(bad, PACKAGE_VERSION);
    var world4 = try World.init(testing.allocator, 1024 * 1024);
    defer world4.deinit();
    var bad_stream: std.Io.Reader = .fixed(bad);
    try testing.expectError(error.InvalidRedLineConfig, load_package(testing.allocator, &bad_stream, &world4, null));
}

test "P45-02: checked-in version 20 package fixture carries red lines" {
    const testing = std.testing;
    const fixture = try std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        "tests/fixtures/compat/v0.3.1-package-v20.bspk",
        testing.allocator,
        .limited(1024 * 1024),
    );
    defer testing.allocator.free(fixture);

    try testing.expectEqual(@as(u32, 20), version_from_bytes(fixture).?);

    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var stream: std.Io.Reader = .fixed(fixture);
    var compiled = try load_package(testing.allocator, &stream, &world, null);
    defer compiled.deinit();

    try testing.expect(compiled.routine_entries.contains("Idle"));
    try testing.expectEqual(@as(usize, 1), compiled.decisions.items.len);
    try testing.expectEqual(@as(usize, 1), compiled.red_lines.items.len);
    try testing.expectEqualStrings("FixtureExecute", world.get_entity_name(compiled.red_lines.items[0].red_lines.options[0]).?);
}


const DILEMMA_FIXTURE =
    \\entity FixtureJudge
    \\relation Accused(who)
    \\relation Criminal(who)
    \\axis FixtureJustice between Cruelty and Leniency
    \\axis FixtureMercy between Vengeance and Indulgence
    \\dilemma FixtureDilemma:
    \\  actor FixtureJudge
    \\  fires FixtureJudged
    \\  requires Accused(FixtureThief)
    \\  weighs FixtureJustice against FixtureMercy
    \\  leans 3 toward FixtureJustice when Criminal(FixtureThief)
    \\  strong FixtureJustice: "Fixture strong justice." -> FixtureHang
    \\  moderate FixtureJustice: "Fixture moderate justice." -> FixtureJail
    \\  neutral: "Fixture neutral." -> FixtureWait
    \\  moderate FixtureMercy: "Fixture moderate mercy." -> FixtureFine
    \\  strong FixtureMercy: "Fixture strong mercy." -> FixturePardon
    \\routine Idle(FixtureJudge):
    \\  wait 1 ticks
;

test "P45-03: package version 21 round-trips a dilemma and loads a version 20 payload with none" {
    const testing = std.testing;
    const compiler = @import("compiler.zig");
    var world1 = try World.init(testing.allocator, 1024 * 1024);
    defer world1.deinit();
    var compiled1 = try compiler.compile_source(testing.allocator, &world1, null, DILEMMA_FIXTURE);
    defer compiled1.deinit();
    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();
    var lw = ListWriter.init(&buffer);
    try save_package(testing.allocator, &lw.writer, &compiled1, &world1, null);

    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();
    var stream: std.Io.Reader = .fixed(buffer.items);
    var compiled2 = try load_package(testing.allocator, &stream, &world2, null);
    defer compiled2.deinit();
    try testing.expectEqual(@as(usize, 1), compiled2.dilemmas.items.len);
    const d = compiled2.dilemmas.items[0].dilemma;
    try testing.expectEqualStrings("FixtureDilemma", world2.get_entity_name(d.entity).?);
    try testing.expectEqualStrings("FixtureJustice", world2.get_relation_meta(d.axis).?.name);
    try testing.expectEqualStrings("FixtureMercy", world2.get_relation_meta(d.counter).?.name);
    try testing.expectEqual(@as(i32, 3), d.leans[0].points);
    try testing.expectEqualStrings("Fixture neutral.", world2.get_entity_name(d.responses[2].line).?);
    try testing.expectEqualStrings("FixturePardon", world2.get_entity_name(d.responses[4].action).?);

    // A payload that ends before the dilemma table is a version 20 package and loads none.
    const v20 = try testing.allocator.dupe(u8, buffer.items[0 .. buffer.items.len - dilemma_table_len(d)]);
    defer testing.allocator.free(v20);
    reseal_for_test(v20, 20);
    var world3 = try World.init(testing.allocator, 1024 * 1024);
    defer world3.deinit();
    var v20_stream: std.Io.Reader = .fixed(v20);
    var loaded = try load_package(testing.allocator, &v20_stream, &world3, null);
    defer loaded.deinit();
    try testing.expectEqual(@as(usize, 0), loaded.dilemmas.items.len);
    try testing.expectEqual(@as(usize, 2), loaded.axes.items.len);

    // A dilemma whose counter-axis is not a bounded axis is refused: point it at `Accused`.
    const bad = try testing.allocator.dupe(u8, buffer.items);
    defer testing.allocator.free(bad);
    const counter_at = bad.len - (dilemma_table_len(d) - counter_offset(d));
    std.mem.writeInt(u16, bad[counter_at..][0..2], world1.lookup_relation("Accused").?.to_int(), .little);
    reseal_for_test(bad, PACKAGE_VERSION);
    var world4 = try World.init(testing.allocator, 1024 * 1024);
    defer world4.deinit();
    var bad_stream: std.Io.Reader = .fixed(bad);
    try testing.expectError(error.InvalidDilemmaConfig, load_package(testing.allocator, &bad_stream, &world4, null));
}

/// One decision clause on disk: relation text ref, subject, object, negation flag.
const CLAUSE_BYTES: usize = 4 + 4 + 4 + 1;

/// The bytes of a one-dilemma table: count, three ids, clauses, two axes, leans, five responses,
/// then its version 22 drift group.
fn dilemma_table_len(d: dilemma_mod.Dilemma) usize {
    return 4 + 12 + 1 + d.clauses.len * CLAUSE_BYTES + 4 + 1 + d.leans.len * (4 + CLAUSE_BYTES) + dilemma_mod.TIER_COUNT * 8 +
        1 + d.drifts.len * (2 + 4 + CLAUSE_BYTES) + 1 + d.appeals.len * (2 + 4 + 4) + EMPTY_TAIL_AFTER_V23;
}

/// Where the counter-axis sits within that table.
fn counter_offset(d: dilemma_mod.Dilemma) usize {
    return 4 + 12 + 1 + d.clauses.len * CLAUSE_BYTES + 2;
}

test "P45-03: checked-in version 21 package fixture carries a dilemma" {
    const testing = std.testing;
    const fixture = try std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        "tests/fixtures/compat/v0.3.1-package-v21.bspk",
        testing.allocator,
        .limited(1024 * 1024),
    );
    defer testing.allocator.free(fixture);

    try testing.expectEqual(@as(u32, 21), version_from_bytes(fixture).?);

    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var stream: std.Io.Reader = .fixed(fixture);
    var compiled = try load_package(testing.allocator, &stream, &world, null);
    defer compiled.deinit();

    try testing.expect(compiled.routine_entries.contains("Idle"));
    try testing.expectEqual(@as(usize, 1), compiled.dilemmas.items.len);
    try testing.expectEqualStrings("FixtureHang", world.get_entity_name(compiled.dilemmas.items[0].dilemma.responses[0].action).?);
}


const DRIFT_FIXTURE =
    \\entity FixtureJudge
    \\relation Accused(who)
    \\relation Repaid(who)
    \\axis FixtureJustice between Cruelty and Leniency
    \\axis FixtureMercy between Vengeance and Indulgence
    \\dilemma FixtureDilemma:
    \\  actor FixtureJudge
    \\  fires FixtureJudged
    \\  requires Accused(FixtureThief)
    \\  weighs FixtureJustice against FixtureMercy
    \\  drifts 3 toward FixtureMercy when Repaid(FixtureThief)
    \\  strong FixtureJustice: "Fixture strong justice." -> FixtureHang
    \\  moderate FixtureJustice: "Fixture moderate justice." -> FixtureJail
    \\  neutral: "Fixture neutral." -> FixtureWait
    \\  moderate FixtureMercy: "Fixture moderate mercy." -> FixtureFine
    \\  strong FixtureMercy: "Fixture strong mercy." -> FixturePardon
    \\routine Idle(FixtureJudge):
    \\  wait 1 ticks
;

test "P45-04: package version 22 round-trips drift lines and loads a version 21 dilemma without them" {
    const testing = std.testing;
    const compiler = @import("compiler.zig");
    var world1 = try World.init(testing.allocator, 1024 * 1024);
    defer world1.deinit();
    var compiled1 = try compiler.compile_source(testing.allocator, &world1, null, DRIFT_FIXTURE);
    defer compiled1.deinit();
    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();
    var lw = ListWriter.init(&buffer);
    try save_package(testing.allocator, &lw.writer, &compiled1, &world1, null);

    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();
    var stream: std.Io.Reader = .fixed(buffer.items);
    var compiled2 = try load_package(testing.allocator, &stream, &world2, null);
    defer compiled2.deinit();
    const drifts = compiled2.dilemmas.items[0].dilemma.drifts;
    try testing.expectEqual(@as(usize, 1), drifts.len);
    try testing.expectEqual(@as(i32, 3), drifts[0].points);
    try testing.expectEqualStrings("FixtureMercy", world2.get_relation_meta(drifts[0].axis).?.name);
    try testing.expectEqualStrings("FixtureMercy drift", world2.get_relation_meta(drifts[0].accumulator).?.name);

    // Cutting the drift group off the end gives a version 21 package: the dilemma loads, still
    // weighs, and carries no drift.
    // The version 23 appeal group (one empty byte here) and the empty art section follow it.
    const drift_group = 1 + drifts.len * (2 + 4 + CLAUSE_BYTES) + 1 + EMPTY_TAIL_AFTER_V23;
    const v21 = try testing.allocator.dupe(u8, buffer.items[0 .. buffer.items.len - drift_group]);
    defer testing.allocator.free(v21);
    reseal_for_test(v21, 21);
    var world3 = try World.init(testing.allocator, 1024 * 1024);
    defer world3.deinit();
    var v21_stream: std.Io.Reader = .fixed(v21);
    var loaded = try load_package(testing.allocator, &v21_stream, &world3, null);
    defer loaded.deinit();
    try testing.expectEqual(@as(usize, 1), loaded.dilemmas.items.len);
    try testing.expectEqual(@as(usize, 0), loaded.dilemmas.items[0].dilemma.drifts.len);
}

test "P45-04: checked-in version 22 package fixture carries drift lines" {
    const testing = std.testing;
    const fixture = try std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        "tests/fixtures/compat/v0.3.1-package-v22.bspk",
        testing.allocator,
        .limited(1024 * 1024),
    );
    defer testing.allocator.free(fixture);

    try testing.expectEqual(@as(u32, 22), version_from_bytes(fixture).?);

    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var stream: std.Io.Reader = .fixed(fixture);
    var compiled = try load_package(testing.allocator, &stream, &world, null);
    defer compiled.deinit();

    try testing.expect(compiled.routine_entries.contains("Idle"));
    try testing.expectEqual(@as(usize, 1), compiled.dilemmas.items[0].dilemma.drifts.len);
}


const APPEAL_FIXTURE =
    \\entity FixtureJudge
    \\relation Accused(who)
    \\relation Repaid(who)
    \\axis FixtureJustice between Cruelty and Leniency
    \\axis FixtureMercy between Vengeance and Indulgence
    \\dilemma FixtureDilemma:
    \\  actor FixtureJudge
    \\  fires FixtureJudged
    \\  requires Accused(FixtureThief)
    \\  weighs FixtureJustice against FixtureMercy
    \\  drifts 3 toward FixtureMercy when Repaid(FixtureThief)
    \\  appeals 4 to FixtureMercy
    \\  strong FixtureJustice: "Fixture strong justice." -> FixtureHang
    \\  moderate FixtureJustice: "Fixture moderate justice." -> FixtureJail
    \\  neutral: "Fixture neutral." -> FixtureWait
    \\  moderate FixtureMercy: "Fixture moderate mercy." -> FixtureFine
    \\  strong FixtureMercy: "Fixture strong mercy." -> FixturePardon
    \\routine Idle(FixtureJudge):
    \\  wait 1 ticks
;

test "P45-05: package version 23 round-trips appeal lines and loads a version 22 dilemma without them" {
    const testing = std.testing;
    const compiler = @import("compiler.zig");
    var world1 = try World.init(testing.allocator, 1024 * 1024);
    defer world1.deinit();
    var compiled1 = try compiler.compile_source(testing.allocator, &world1, null, APPEAL_FIXTURE);
    defer compiled1.deinit();
    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();
    var lw = ListWriter.init(&buffer);
    try save_package(testing.allocator, &lw.writer, &compiled1, &world1, null);

    var world2 = try World.init(testing.allocator, 1024 * 1024);
    defer world2.deinit();
    var stream: std.Io.Reader = .fixed(buffer.items);
    var compiled2 = try load_package(testing.allocator, &stream, &world2, null);
    defer compiled2.deinit();
    const appeals = compiled2.dilemmas.items[0].dilemma.appeals;
    try testing.expectEqual(@as(usize, 1), appeals.len);
    try testing.expectEqual(@as(i32, -4), appeals[0].points);
    try testing.expectEqualStrings("FixtureMercy", world2.get_entity_name(appeals[0].entity).?);

    // Cutting the appeal group off the end gives a version 22 package with drift but no appeal.
    const appeal_group = 1 + appeals.len * (2 + 4 + 4) + EMPTY_TAIL_AFTER_V23;
    const v22 = try testing.allocator.dupe(u8, buffer.items[0 .. buffer.items.len - appeal_group]);
    defer testing.allocator.free(v22);
    reseal_for_test(v22, 22);
    var world3 = try World.init(testing.allocator, 1024 * 1024);
    defer world3.deinit();
    var v22_stream: std.Io.Reader = .fixed(v22);
    var loaded = try load_package(testing.allocator, &v22_stream, &world3, null);
    defer loaded.deinit();
    try testing.expectEqual(@as(usize, 1), loaded.dilemmas.items[0].dilemma.drifts.len);
    try testing.expectEqual(@as(usize, 0), loaded.dilemmas.items[0].dilemma.appeals.len);
}

test "P45-05: checked-in version 23 package fixture carries appeal lines" {
    const testing = std.testing;
    const fixture = try std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        "tests/fixtures/compat/v0.3.1-package-v23.bspk",
        testing.allocator,
        .limited(1024 * 1024),
    );
    defer testing.allocator.free(fixture);

    try testing.expectEqual(@as(u32, 23), version_from_bytes(fixture).?);

    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var stream: std.Io.Reader = .fixed(fixture);
    var compiled = try load_package(testing.allocator, &stream, &world, null);
    defer compiled.deinit();

    try testing.expect(compiled.routine_entries.contains("Idle"));
    try testing.expectEqual(@as(usize, 1), compiled.dilemmas.items[0].dilemma.appeals.len);
}

const ART_FIXTURE =
    \\entity FixtureHero
    \\relation Ready(actor)
    \\routine Idle(FixtureHero):
    \\  wait 1 ticks
;

const ART_FIXTURE_PALETTE = [_]image_mod.Colour{
    .{ .r = 0, .g = 0, .b = 0 },
    .{ .r = 34, .g = 32, .b = 52 },
    .{ .r = 217, .g = 160, .b = 102 },
    .{ .r = 251, .g = 242, .b = 54 },
};

/// An 8x4 sheet of two 4x4 frames: a lamp unlit, then lit. Index 0 is the transparent corner.
const ART_FIXTURE_PIXELS = [_]u8{
    0, 1, 1, 0, 0, 1, 1, 0,
    1, 2, 2, 1, 1, 3, 3, 1,
    1, 2, 2, 1, 1, 3, 3, 1,
    0, 1, 1, 0, 0, 1, 1, 0,
};

/// The art section of `ART_FIXTURE` sits at the end of the payload: the colour count, four RGB
/// triples, the image count, the name, four sides, and 32 pixel bytes.
const ART_FIXTURE_NAME = "FixtureLamp";
const ART_SECTION_LEN = 2 + 3 * ART_FIXTURE_PALETTE.len + 4 + 2 + ART_FIXTURE_NAME.len + 8 + ART_FIXTURE_PIXELS.len;

fn write_art_fixture(allocator: std.mem.Allocator, out: *std.array_list.Managed(u8)) !void {
    const compiler = @import("compiler.zig");
    var world = try World.init(allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try compiler.compile_source(allocator, &world, null, ART_FIXTURE);
    defer compiled.deinit();
    compiled.art = try image_mod.Art.dupe(allocator, &ART_FIXTURE_PALETTE, &.{.{
        .name = ART_FIXTURE_NAME,
        .width = 8,
        .height = 4,
        .frame_width = 4,
        .frame_height = 4,
        .pixels = &ART_FIXTURE_PIXELS,
    }});
    var lw = ListWriter.init(out);
    try save_package(allocator, &lw.writer, &compiled, &world, null);
}

fn load_for_test(bytes: []const u8) !CompiledProgram {
    var world = try World.init(std.testing.allocator, 1024 * 1024);
    defer world.deinit();
    var stream: std.Io.Reader = .fixed(bytes);
    return load_package(std.testing.allocator, &stream, &world, null);
}

test "P46-01: package version 24 round-trips the palette and a sprite sheet" {
    const testing = std.testing;
    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();
    try write_art_fixture(testing.allocator, &buffer);

    var compiled = try load_for_test(buffer.items);
    defer compiled.deinit();
    const art = compiled.art;
    try testing.expectEqualSlices(image_mod.Colour, &ART_FIXTURE_PALETTE, art.palette);
    const lamp = art.find(ART_FIXTURE_NAME).?;
    try testing.expectEqual(@as(u32, 2), lamp.frame_count());
    try testing.expectEqualSlices(u8, &ART_FIXTURE_PIXELS, lamp.pixels);
    try testing.expectEqual(@as(u8, 3), lamp.frame_pixel(1, 1, 1));
    try testing.expectEqual(image_mod.TRANSPARENT, lamp.frame_pixel(0, 0, 0));

    // Saving the loaded program again writes the same bytes.
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var again_compiled = try blk: {
        var stream: std.Io.Reader = .fixed(buffer.items);
        break :blk load_package(testing.allocator, &stream, &world, null);
    };
    defer again_compiled.deinit();
    var again = std.array_list.Managed(u8).init(testing.allocator);
    defer again.deinit();
    var lw = ListWriter.init(&again);
    try save_package(testing.allocator, &lw.writer, &again_compiled, &world, null);
    try testing.expectEqualSlices(u8, buffer.items, again.items);
}

test "P46-01: a version 23 package loads with no art" {
    const testing = std.testing;
    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();
    try write_art_fixture(testing.allocator, &buffer);
    const v23 = try testing.allocator.dupe(u8, buffer.items[0 .. buffer.items.len - ART_SECTION_LEN]);
    defer testing.allocator.free(v23);
    reseal_for_test(v23, 23);
    var compiled = try load_for_test(v23);
    defer compiled.deinit();
    try testing.expect(compiled.art.is_empty());
    try testing.expect(compiled.routine_entries.contains("Idle"));
}

test "P46-01: a program with no art writes an empty art section" {
    const testing = std.testing;
    const compiler = @import("compiler.zig");
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try compiler.compile_source(testing.allocator, &world, null, ART_FIXTURE);
    defer compiled.deinit();
    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();
    var lw = ListWriter.init(&buffer);
    try save_package(testing.allocator, &lw.writer, &compiled, &world, null);
    try testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0, 0, 0 }, buffer.items[buffer.items.len - 6 ..]);
    var loaded = try load_for_test(buffer.items);
    defer loaded.deinit();
    try testing.expect(loaded.art.is_empty());
}

/// One way to break the art fixture: the byte offset inside its art section, the bytes written
/// there, and the error the loader must name. `tests/fixtures/fuzz/image-*.bspk` are these.
const ArtBreak = struct { name: []const u8, offset: usize, bytes: []const u8, err: anyerror };

const ART_NAME_AT = 2 + 3 * ART_FIXTURE_PALETTE.len + 4 + 2;
const ART_SIDES_AT = ART_NAME_AT + ART_FIXTURE_NAME.len;
const ART_PIXELS_AT = ART_SIDES_AT + 8;

const ART_BREAKS = [_]ArtBreak{
    // 300 colours: past the one palette of 256 (D-152).
    .{ .name = "palette", .offset = 0, .bytes = &.{ 0x2c, 0x01 }, .err = error.InvalidImagePalette },
    // A million images.
    .{ .name = "count", .offset = 2 + 3 * ART_FIXTURE_PALETTE.len, .bytes = &.{ 0x40, 0x42, 0x0f, 0x00 }, .err = error.InvalidImageCount },
    // A control byte in the name.
    .{ .name = "name", .offset = ART_NAME_AT, .bytes = &.{0x01}, .err = error.InvalidImageName },
    // A frame 5 wide does not tile an 8-wide sheet.
    .{ .name = "frame", .offset = ART_SIDES_AT + 4, .bytes = &.{ 0x05, 0x00 }, .err = error.InvalidImageSize },
    // A sheet 4096 wide, past the side limit, before any pixel is read.
    .{ .name = "size", .offset = ART_SIDES_AT, .bytes = &.{ 0x00, 0x10 }, .err = error.InvalidImageSize },
    // Index 200 in a palette of four colours.
    .{ .name = "index", .offset = ART_PIXELS_AT + 9, .bytes = &.{200}, .err = error.InvalidImageIndex },
};

/// Applies one break to a copy of a version 24 package whose art section is the fixture's,
/// and reseals the checksum so the loader reaches the art.
fn break_art(allocator: std.mem.Allocator, package: []const u8, b: ArtBreak) ![]u8 {
    const out = try allocator.dupe(u8, package);
    const at = out.len - ART_SECTION_LEN + b.offset;
    @memcpy(out[at .. at + b.bytes.len], b.bytes);
    reseal_for_test(out, 24);
    return out;
}

test "P46-01: every malformed art section is refused with a named error" {
    const testing = std.testing;
    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();
    try write_art_fixture(testing.allocator, &buffer);
    for (ART_BREAKS) |b| {
        const broken = try break_art(testing.allocator, buffer.items, b);
        defer testing.allocator.free(broken);
        testing.expectError(b.err, load_for_test(broken)) catch |err| {
            std.debug.print("art break '{s}'\n", .{b.name});
            return err;
        };
    }
    // A truncated sheet ends the stream rather than reading past it.
    const short = try testing.allocator.dupe(u8, buffer.items[0 .. buffer.items.len - 5]);
    defer testing.allocator.free(short);
    reseal_for_test(short, 24);
    try testing.expectError(error.EndOfStream, load_for_test(short));
}

test "P46-01: checked-in version 24 package fixture carries a sprite sheet" {
    const testing = std.testing;
    const fixture = try std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        "tests/fixtures/compat/v0.4.0-package-v24.bspk",
        testing.allocator,
        .limited(1024 * 1024),
    );
    defer testing.allocator.free(fixture);
    try testing.expectEqual(PACKAGE_VERSION, version_from_bytes(fixture).?);
    var compiled = try load_for_test(fixture);
    defer compiled.deinit();
    try testing.expect(compiled.routine_entries.contains("Idle"));
    try testing.expectEqual(@as(usize, 4), compiled.art.palette.len);
    try testing.expectEqualSlices(u8, &ART_FIXTURE_PIXELS, compiled.art.find(ART_FIXTURE_NAME).?.pixels);

    // The checked-in fuzz seeds are this fixture with one break each.
    for (ART_BREAKS) |b| {
        var path_buf: [96]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "tests/fixtures/fuzz/image-{s}.bspk", .{b.name});
        const seed = try std.Io.Dir.cwd().readFileAlloc(testing.io, path, testing.allocator, .limited(64 * 1024));
        defer testing.allocator.free(seed);
        const expected = try break_art(testing.allocator, fixture, b);
        defer testing.allocator.free(expected);
        try testing.expectEqualSlices(u8, expected, seed);
    }
}
