const std = @import("std");
const ListWriter = @import("list_writer.zig").ListWriter;
const world_mod = @import("world.zig");
const spatial_mod = @import("spatial.zig");
const vm_mod = @import("vm.zig");
const hypervisor_mod = @import("hypervisor.zig");
const temporal_mod = @import("temporal_snapshot.zig");

pub const World = world_mod.World;
pub const EntityId = world_mod.EntityId;
pub const SpatialSystem = spatial_mod.SpatialSystem;
pub const WaypointId = spatial_mod.WaypointId;
pub const MotorAgent = spatial_mod.MotorAgent;
pub const VM = vm_mod.VM;
pub const TemporalHypervisor = hypervisor_mod.TemporalHypervisor;
pub const Fiber = vm_mod.Fiber;
pub const FiberState = vm_mod.FiberState;
pub const FiberStateTag = vm_mod.FiberStateTag;
pub const InterruptFrame = vm_mod.InterruptFrame;

/// 4-byte magic identifier for BeSpoke persistent save files (P17-01, D-020).
pub const SAVE_MAGIC = [4]u8{ 'B', 'S', 'A', 'V' };
/// Version 3 (P48-08, D-162) adds the program identity after the metadata, and always carries
/// the temporal flag byte; versions 1 and 2 load unchecked.
pub const SAVE_VERSION: u32 = 3;
pub const MIN_SAVE_VERSION: u32 = 1;

/// Number of user-addressable save slots (1..8), plus slot 0 reserved for Quick-Save (P17-02, D-020).
pub const MAX_SLOTS: u8 = 8;
pub const QUICKSAVE_SLOT: u8 = 0;

/// Miniature graphical thumbnail dimensions stored in every save header (16x12 RGB332 = 192 bytes).
pub const THUMB_WIDTH: usize = 16;
pub const THUMB_HEIGHT: usize = 12;
pub const THUMB_SIZE: usize = THUMB_WIDTH * THUMB_HEIGHT;

/// Upper bound on save payload allocation at untrusted disk boundary (SECURITY.md).
pub const MAX_SAVE_PAYLOAD_SIZE: u32 = 32 * 1024 * 1024;

/// Which compiled program wrote a save (P48-08, D-162): a fingerprint of its build and the
/// script's declared `save version`. A zero fingerprint means unknown, as in saves written
/// before version 3 or by a host that passed no program; such saves load unchecked.
pub const ProgramIdentity = struct {
    fingerprint: u64 = 0,
    save_version: u32 = 0,

    pub fn known(self: ProgramIdentity) bool {
        return self.fingerprint != 0;
    }
};

/// The refusal a player reads when a save comes from another build of the game (D-162).
pub fn format_build_mismatch(buf: []u8, saved: ProgramIdentity, current: ProgramIdentity) []const u8 {
    return std.fmt.bufPrint(buf, "this save is from save version {d} of the game (build {x:0>8}); this build is save version {d} (build {x:0>8}) and cannot load it", .{
        saved.save_version,
        @as(u32, @truncate(saved.fingerprint >> 32)),
        current.save_version,
        @as(u32, @truncate(current.fingerprint >> 32)),
    }) catch "this save is from another build of the game";
}

pub const SaveError = error{
    /// The save was written by a different build of the game, and the builds' save versions do
    /// not make it loadable (D-162). Nothing was restored.
    SaveFromOtherBuild,
    InvalidSaveMagic,
    UnsupportedSaveVersion,
    ChecksumMismatch,
    SavePayloadTooLarge,
    InvalidSlotId,
    EmptySlot,
    CorruptedSaveUnrecoverable,
    MissingTemporalState,
    InvalidTemporalState,
};

/// Formats the actionable diagnostic for a save schema outside this engine's supported range
/// (P38-02, D-106). Save loaders still return `UnsupportedSaveVersion` for programmatic handling.
pub fn format_unsupported_version(buf: []u8, found: u32) []const u8 {
    return std.fmt.bufPrint(buf, "unsupported .sav format version {d}; this engine supports versions {d} through {d}", .{
        found,
        MIN_SAVE_VERSION,
        SAVE_VERSION,
    }) catch "unsupported .sav format version";
}

/// Reads only the version field from an in-memory save envelope. Integrity and payload checks
/// remain the responsibility of `inspect_save_stream` and the restore functions.
pub fn version_from_bytes(bytes: []const u8) ?u32 {
    if (bytes.len < 8 or !std.mem.eql(u8, bytes[0..4], &SAVE_MAGIC)) return null;
    return std.mem.readInt(u32, bytes[4..8], .little);
}

/// Packs 8-bit R, G, B channels into a compact 1-byte RGB332 pixel (P17-01).
pub fn pack_rgb332(r: u8, g: u8, b: u8) u8 {
    return (r & 0xE0) | ((g & 0xE0) >> 3) | (b >> 6);
}

/// Unpacks a 1-byte RGB332 pixel back into 8-bit R, G, B channels (P17-01).
pub fn unpack_rgb332(pixel: u8) struct { r: u8, g: u8, b: u8 } {
    const r3: u16 = (pixel >> 5) & 0x07;
    const g3: u16 = (pixel >> 2) & 0x07;
    const b2: u16 = pixel & 0x03;
    return .{
        .r = @intCast((r3 * 255) / 7),
        .g = @intCast((g3 * 255) / 7),
        .b = @intCast((b2 * 255) / 3),
    };
}

/// Actor coordinate preview entry stored inside the save metadata header (P17-01).
pub const SaveActorPreview = struct {
    entity_id: u32 = 0,
    x: i32 = 0,
    y: i32 = 0,
    name: [24]u8 = @as([24]u8, @splat(0)),
    name_len: u8 = 0,

    pub fn get_name(self: *const SaveActorPreview) []const u8 {
        return self.name[0..self.name_len];
    }
};

/// Metadata header and frame snapshot summary for a save slot (P17-01, D-020).
pub const SaveMetadata = struct {
    version: u32 = SAVE_VERSION,
    slot_id: u8 = 0,
    current_tick: u64 = 0,
    playtime_secs: u64 = 0,
    timestamp: i64 = 0,
    fact_count: u32 = 0,
    entity_count: u32 = 0,
    scene_id: u32 = 0,
    scene_name: [32]u8 = @as([32]u8, @splat(0)),
    scene_name_len: u8 = 0,
    description: [64]u8 = @as([64]u8, @splat(0)),
    description_len: u8 = 0,
    actor_count: u8 = 0,
    actors: [8]SaveActorPreview = @as([8]SaveActorPreview, @splat(.{})),
    thumbnail: [THUMB_SIZE]u8 = @as([THUMB_SIZE]u8, @splat(0)),
    /// The program that wrote the save (version 3); unknown for older saves.
    program: ProgramIdentity = .{},

    pub fn get_scene_name(self: *const SaveMetadata) []const u8 {
        if (self.scene_name_len == 0) return "Default Stage";
        return self.scene_name[0..self.scene_name_len];
    }

    pub fn get_description(self: *const SaveMetadata) []const u8 {
        return self.description[0..self.description_len];
    }
};

pub const SaveOptions = struct {
    slot_id: u8 = 1,
    playtime_secs: u64 = 0,
    timestamp: ?i64 = null,
    description: []const u8 = "",
    scene_override: ?[]const u8 = null,
    thumbnail: ?*const ThumbnailPainter = null,
    /// The running program, recorded so a later load can tell whether it is the same build.
    program: ProgramIdentity = .{},
};

/// How a game colours its save thumbnails (P32-03d, D-041). Both callbacks return an RGB332
/// colour (`pack_rgb332`), or null for the engine's neutral default.
pub const ThumbnailPainter = struct {
    /// The backdrop pixel at (x, y) of a 16x12 thumbnail for a scene.
    backdrop: ?*const fn (scene_name: []const u8, x: usize, y: usize) ?u8 = null,
    /// The dot colour of an actor.
    actor: ?*const fn (name: []const u8) ?u8 = null,
};

/// Generates a 16x12 RGB332 miniature frame snapshot from active scene and spatial state (P17-01).
/// Without a painter the backdrop is a neutral two-tone stage and actors are gold dots.
pub fn generate_thumbnail(
    world: *const World,
    spatial: ?*const SpatialSystem,
    scene_name: []const u8,
    painter: ?*const ThumbnailPainter,
) [THUMB_SIZE]u8 {
    var thumb: [THUMB_SIZE]u8 = undefined;
    const backdrop = if (painter) |p| p.backdrop else null;
    const actor_colour = if (painter) |p| p.actor else null;

    var y: usize = 0;
    while (y < THUMB_HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < THUMB_WIDTH) : (x += 1) {
            const custom = if (backdrop) |paint| paint(scene_name, x, y) else null;
            thumb[y * THUMB_WIDTH + x] = custom orelse if (y < 6) pack_rgb332(34, 38, 48) else pack_rgb332(52, 56, 66);
        }
    }

    // Plot spatial actors onto the thumbnail
    if (spatial) |sp| {
        var it = sp.agents.iterator();
        while (it.next()) |entry| {
            const agent = entry.value_ptr;
            // Map world x in [-10..50] to [2..13], world y in [-12..12] to [3..9]
            const clamped_x = std.math.clamp(agent.pos.x + 10, 0, 60);
            const clamped_y = std.math.clamp(agent.pos.y + 12, 0, 24);
            const tx: usize = @intCast(2 + @divTrunc(clamped_x * 11, 60));
            const ty: usize = @intCast(3 + @divTrunc(clamped_y * 6, 24));

            var actor_col = pack_rgb332(250, 204, 21); // Default gold dot
            if (actor_colour) |colour| {
                if (world.get_entity_name(agent.entity)) |ename| {
                    if (colour(ename)) |col| actor_col = col;
                }
            }

            if (ty < THUMB_HEIGHT and tx < THUMB_WIDTH) {
                thumb[ty * THUMB_WIDTH + tx] = actor_col;
            }
        }
    }

    return thumb;
}

fn write_fiber_state(writer: anytype, state: FiberState) !void {
    switch (state) {
        .ready => {
            try writer.writeByte(0);
            try writer.writeInt(u64, 0, .little);
        },
        .waiting_ticks => |target_tick| {
            try writer.writeByte(1);
            try writer.writeInt(u64, target_tick, .little);
        },
        .waiting_cond => |cond_pc| {
            try writer.writeByte(2);
            try writer.writeInt(u64, cond_pc, .little);
        },
        .waiting_motor => |entity| {
            try writer.writeByte(3);
            try writer.writeInt(u64, entity.to_int(), .little);
        },
        .halted => {
            try writer.writeByte(4);
            try writer.writeInt(u64, 0, .little);
        },
        .paused => {
            try writer.writeByte(5);
            try writer.writeInt(u64, 0, .little);
        },
        .waiting_dialogue => {
            // The open set itself is World facts (P32-30); the fiber only needs its tag back.
            // Loading calls `VM.sync_dialogue` to keep this wait only if those facts survive.
            try writer.writeByte(6);
            try writer.writeInt(u64, 0, .little);
        },
    }
}

fn read_fiber_state(reader: anytype) !FiberState {
    const tag = try reader.takeByte();
    const val = try reader.takeInt(u64, .little);
    return switch (tag) {
        0 => FiberState{ .ready = {} },
        1 => FiberState{ .waiting_ticks = val },
        2 => FiberState{ .waiting_cond = @intCast(val) },
        3 => FiberState{ .waiting_motor = EntityId.from_int(@intCast(val)) },
        4 => FiberState{ .halted = {} },
        5 => FiberState{ .paused = {} },
        6 => FiberState{ .waiting_dialogue = {} },
        else => error.InvalidSaveMagic,
    };
}

fn serialize_metadata(writer: anytype, meta: *const SaveMetadata) !void {
    try writer.writeInt(u32, meta.version, .little);
    try writer.writeByte(meta.slot_id);
    try writer.writeInt(u64, meta.current_tick, .little);
    try writer.writeInt(u64, meta.playtime_secs, .little);
    try writer.writeInt(i64, meta.timestamp, .little);
    try writer.writeInt(u32, meta.fact_count, .little);
    try writer.writeInt(u32, meta.entity_count, .little);
    try writer.writeInt(u32, meta.scene_id, .little);
    try writer.writeByte(meta.scene_name_len);
    try writer.writeAll(&meta.scene_name);
    try writer.writeByte(meta.description_len);
    try writer.writeAll(&meta.description);
    try writer.writeByte(meta.actor_count);
    for (0..8) |i| {
        try writer.writeInt(u32, meta.actors[i].entity_id, .little);
        try writer.writeInt(i32, meta.actors[i].x, .little);
        try writer.writeInt(i32, meta.actors[i].y, .little);
        try writer.writeByte(meta.actors[i].name_len);
        try writer.writeAll(&meta.actors[i].name);
    }
    try writer.writeAll(&meta.thumbnail);
}

fn deserialize_metadata(reader: anytype) !SaveMetadata {
    var meta = SaveMetadata{};
    meta.version = try reader.takeInt(u32, .little);
    meta.slot_id = try reader.takeByte();
    meta.current_tick = try reader.takeInt(u64, .little);
    meta.playtime_secs = try reader.takeInt(u64, .little);
    meta.timestamp = try reader.takeInt(i64, .little);
    meta.fact_count = try reader.takeInt(u32, .little);
    meta.entity_count = try reader.takeInt(u32, .little);
    meta.scene_id = try reader.takeInt(u32, .little);
    meta.scene_name_len = @min(32, try reader.takeByte());
    try reader.readSliceAll(&meta.scene_name);
    meta.description_len = @min(64, try reader.takeByte());
    try reader.readSliceAll(&meta.description);
    meta.actor_count = @min(8, try reader.takeByte());
    for (0..8) |i| {
        meta.actors[i].entity_id = try reader.takeInt(u32, .little);
        meta.actors[i].x = try reader.takeInt(i32, .little);
        meta.actors[i].y = try reader.takeInt(i32, .little);
        meta.actors[i].name_len = @min(24, try reader.takeByte());
        try reader.readSliceAll(&meta.actors[i].name);
    }
    try reader.readSliceAll(&meta.thumbnail);
    return meta;
}

/// Builds a SaveMetadata struct from current simulation state (P17-01).
pub fn build_metadata(
    world: *const World,
    spatial: ?*const SpatialSystem,
    vm: ?*const VM,
    options: SaveOptions,
) SaveMetadata {
    var meta = SaveMetadata{
        .version = SAVE_VERSION,
        .slot_id = options.slot_id,
        .current_tick = world.current_tick,
        .playtime_secs = options.playtime_secs,
        // A save that reaches disk is stamped by `SaveManager`, which has an `Io` clock; an
        // in-memory checkpoint passes none and records 0 (P37-01).
        .timestamp = options.timestamp orelse 0,
        .fact_count = @intCast(world.fact_count()),
        .entity_count = @intCast(world.entity_names.items.len),
        .scene_id = 0,
    };

    var resolved_scene: []const u8 = "";
    if (options.scene_override) |so| {
        resolved_scene = so;
    } else if (vm) |v| {
        if (v.current_scene) |sc_id| {
            meta.scene_id = sc_id.to_int();
            if (world.get_entity_name(sc_id)) |sname| {
                resolved_scene = sname;
            }
        }
    }

    const slen: u8 = @intCast(@min(resolved_scene.len, meta.scene_name.len));
    @memcpy(meta.scene_name[0..slen], resolved_scene[0..slen]);
    meta.scene_name_len = slen;

    const dlen: u8 = @intCast(@min(options.description.len, meta.description.len));
    @memcpy(meta.description[0..dlen], options.description[0..dlen]);
    meta.description_len = dlen;

    if (spatial) |sp| {
        var a_count: u8 = 0;
        var it = sp.agents.iterator();
        while (it.next()) |entry| {
            if (a_count >= 8) break;
            const agent = entry.value_ptr;
            var preview = SaveActorPreview{
                .entity_id = agent.entity.to_int(),
                .x = agent.pos.x,
                .y = agent.pos.y,
            };
            if (world.get_entity_name(agent.entity)) |ename| {
                const nlen: u8 = @intCast(@min(ename.len, preview.name.len));
                @memcpy(preview.name[0..nlen], ename[0..nlen]);
                preview.name_len = nlen;
            }
            meta.actors[a_count] = preview;
            a_count += 1;
        }
        meta.actor_count = a_count;
    }

    meta.thumbnail = generate_thumbnail(world, spatial, meta.get_scene_name(), options.thumbnail);
    return meta;
}

/// Serializes a complete persistent save state (.sav) with metadata, CRC32 checksum, World, SpatialSystem, and VM (P17-01, D-020).
pub fn write_save_state(
    allocator: std.mem.Allocator,
    writer: anytype,
    world: *const World,
    spatial: ?*const SpatialSystem,
    vm: ?*const VM,
    options: SaveOptions,
) !SaveMetadata {
    return write_save_state_versioned(allocator, writer, world, spatial, vm, null, SAVE_VERSION, options);
}

/// Serializes a save that also carries the temporal hypervisor branch and countdown (P31-04, D-048).
pub fn write_save_state_with_temporal(
    allocator: std.mem.Allocator,
    writer: anytype,
    world: *const World,
    spatial: ?*const SpatialSystem,
    vm: ?*const VM,
    temporal: ?*const TemporalHypervisor,
    options: SaveOptions,
) !SaveMetadata {
    return write_save_state_versioned(allocator, writer, world, spatial, vm, temporal, SAVE_VERSION, options);
}

fn write_save_state_versioned(
    allocator: std.mem.Allocator,
    writer: anytype,
    world: *const World,
    spatial: ?*const SpatialSystem,
    vm: ?*const VM,
    temporal: ?*const TemporalHypervisor,
    version: u32,
    options: SaveOptions,
) !SaveMetadata {
    var meta = build_metadata(world, spatial, vm, options);
    meta.version = version;
    meta.program = options.program;

    var payload = std.array_list.Managed(u8).init(allocator);
    defer payload.deinit();
    var pw_list = ListWriter.init(&payload);
    const pw = &pw_list.writer;

    // 1. Metadata header block, then (version 3) the program identity, read before anything is
    // restored so a refused load changes nothing.
    try serialize_metadata(pw, &meta);
    if (version >= 3) {
        try pw.writeInt(u64, meta.program.fingerprint, .little);
        try pw.writeInt(u32, meta.program.save_version, .little);
    }

    // 2. Temporal hypervisor state (format version 2). It precedes the world so a reader can
    // decode and validate the branch before mutating the primary state.
    if (version >= 2) {
        if (temporal) |hypervisor| {
            var temporal_bytes = std.array_list.Managed(u8).init(allocator);
            defer temporal_bytes.deinit();
            var lw1 = ListWriter.init(&temporal_bytes);
            try temporal_mod.TemporalSnapshot.write(hypervisor, &lw1.writer);
            try pw.writeByte(1);
            try pw.writeInt(u32, @intCast(temporal_bytes.items.len), .little);
            try pw.writeAll(temporal_bytes.items);
        } else {
            try pw.writeByte(0);
        }
    }

    // 3. World relational arena snapshot
    try world.save_state(pw);

    // 4. Spatial motor agents
    if (spatial) |sp| {
        try pw.writeByte(1);
        const agent_count: u32 = @intCast(sp.agents.count());
        try pw.writeInt(u32, agent_count, .little);

        var it = sp.agents.iterator();
        while (it.next()) |entry| {
            const agent = entry.value_ptr;
            try pw.writeInt(u32, agent.entity.to_int(), .little);
            try pw.writeInt(i32, agent.pos.x, .little);
            try pw.writeInt(i32, agent.pos.y, .little);
            try pw.writeInt(u16, agent.current_wp, .little);
            try pw.writeInt(u16, agent.target_wp orelse 0, .little);
            try pw.writeInt(u32, agent.speed, .little);
            try pw.writeByte(if (agent.is_moving) 1 else 0);
            try pw.writeByte(if (agent.arrived) 1 else 0);
            try pw.writeInt(u16, @intCast(agent.path_index), .little);
            if (agent.path) |p| {
                try pw.writeInt(u16, @intCast(p.len), .little);
                for (p) |wp_id| {
                    try pw.writeInt(u16, wp_id, .little);
                }
            } else {
                try pw.writeInt(u16, 0, .little);
            }
        }
    } else {
        try pw.writeByte(0);
    }

    // 5. VM execution state (current_scene, fibers, interrupt stacks, reactive rule edge flags)
    if (vm) |v| {
        // Queued weaves are not part of the save format. They exist only between `step_tick`
        // and the host's `dispatch_pending_weaves`; saving inside that window would drop them,
        // so refuse rather than lose a player action (D-029).
        if (v.pending_weaves.items.len > 0) return error.PendingWeavesNotDispatched;
        try pw.writeByte(1);
        const cur_scene_raw: u32 = if (v.current_scene) |sc| sc.to_int() else 0;
        try pw.writeInt(u32, cur_scene_raw, .little);
        try pw.writeInt(u32, v.next_fiber_id, .little);

        const fiber_count: u32 = @intCast(v.fibers.items.len);
        try pw.writeInt(u32, fiber_count, .little);
        for (v.fibers.items) |*f| {
            try pw.writeInt(u32, f.id, .little);
            try pw.writeInt(u32, f.owner.to_int(), .little);
            try pw.writeInt(u32, @intCast(f.pc), .little);
            try pw.writeInt(u16, @intCast(f.sp), .little);
            try pw.writeInt(u16, f.active_priority, .little);
            for (0..f.sp) |si| {
                try pw.writeInt(u32, f.stack[si], .little);
            }
            try write_fiber_state(pw, f.state);

            const int_depth: u16 = @intCast(f.interrupt_stack.items.len);
            try pw.writeInt(u16, int_depth, .little);
            for (f.interrupt_stack.items) |iframe| {
                try pw.writeInt(u32, @intCast(iframe.pc), .little);
                try pw.writeInt(u16, @intCast(iframe.sp), .little);
                try pw.writeInt(u16, iframe.priority, .little);
                try write_fiber_state(pw, iframe.state);
            }
        }

        const rule_count: u32 = @intCast(v.reactive_rules.items.len);
        try pw.writeInt(u32, rule_count, .little);
        for (v.reactive_rules.items) |r| {
            try pw.writeByte(if (r.is_active) 1 else 0);
        }
    } else {
        try pw.writeByte(0);
    }

    // Compute CRC32 integrity checksum over the entire payload
    if (payload.items.len > MAX_SAVE_PAYLOAD_SIZE) return SaveError.SavePayloadTooLarge;
    const crc = std.hash.Crc32.hash(payload.items);
    const payload_len: u32 = @intCast(payload.items.len);

    // Write outer file envelope: magic (4B) + version (4B) + crc32 (4B) + payload_len (4B) + payload
    try writer.writeAll(&SAVE_MAGIC);
    try writer.writeInt(u32, version, .little);
    try writer.writeInt(u32, crc, .little);
    try writer.writeInt(u32, payload_len, .little);
    try writer.writeAll(payload.items);

    return meta;
}

const VerifiedPayload = struct {
    version: u32,
    bytes: []u8,
};

test "P39-02: save reader rejects an oversized payload before reading it" {
    var header: [16]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&header);
    try writer.writeAll(&SAVE_MAGIC);
    try writer.writeInt(u32, SAVE_VERSION, .little);
    try writer.writeInt(u32, 0, .little);
    try writer.writeInt(u32, MAX_SAVE_PAYLOAD_SIZE + 1, .little);
    var reader: std.Io.Reader = .fixed(writer.buffered());
    try std.testing.expectError(SaveError.SavePayloadTooLarge, inspect_save_stream(std.testing.allocator, &reader));
}

test "P39-02: an older save can restore more fibers than a new spawn permits" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    const owner = try world.intern_entity("Actor");
    var chunk = @import("bytecode.zig").BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();
    var vm = VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();

    // Build a VM state that predates the spawn cap, then use the unchanged save format.
    for (0..vm_mod.MAX_FIBERS + 1) |i| {
        try vm.fibers.append(Fiber.init(testing.allocator, @intCast(i + 1), owner, 0));
    }
    vm.next_fiber_id = vm_mod.MAX_FIBERS + 2;
    var bytes = std.array_list.Managed(u8).init(testing.allocator);
    defer bytes.deinit();
    var list_writer = ListWriter.init(&bytes);
    _ = try write_save_state(testing.allocator, &list_writer.writer, &world, null, &vm, .{});

    var reader: std.Io.Reader = .fixed(bytes.items);
    _ = try read_save_state(testing.allocator, &reader, &world, null, &vm);
    try testing.expectEqual(vm_mod.MAX_FIBERS + 1, vm.fibers.items.len);
    try testing.expectError(error.FiberLimitExceeded, vm.spawn_routine(owner, 0));
}

test "P48-02: a cue handler saved while it waits still reads its arguments after a load" {
    const testing = std.testing;
    const compiler = @import("compiler.zig");
    const source =
        \\entity Hero, Bard
        \\on cue Calls(Hero, who):
        \\  wait 2 ticks
        \\  remember Answered(who)
    ;
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    var compiled = try compiler.compile_source(testing.allocator, &world, null, source);
    defer compiled.deinit();
    var vm = VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    _ = (try vm.fire_cue(&compiled, "Calls", world.lookup_entity("Hero").?, world.lookup_entity("Bard").?, null)).?;
    _ = try vm.step_tick();
    var bytes = std.array_list.Managed(u8).init(testing.allocator);
    defer bytes.deinit();
    var list_writer = ListWriter.init(&bytes);
    _ = try write_save_state(testing.allocator, &list_writer.writer, &world, null, &vm, .{});

    // The handler's arguments are stack entries, which the save already carries (D-161).
    var world2 = try World.init(testing.allocator, 256 * 1024);
    defer world2.deinit();
    var compiled2 = try compiler.compile_source(testing.allocator, &world2, null, source);
    defer compiled2.deinit();
    var vm2 = VM.init(testing.allocator, &world2, &compiled2.chunk);
    defer vm2.deinit();
    var reader: std.Io.Reader = .fixed(bytes.items);
    _ = try read_save_state(testing.allocator, &reader, &world2, null, &vm2);
    for (0..3) |_| _ = try vm2.step_tick();
    const answered = world2.lookup_relation("Answered").?;
    try testing.expect(world2.has_fact(world2.lookup_entity("Bard").?, answered, null));
}

test "P48-08: a save names its build, and a load refuses another build's save untouched" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    const hero = try world.intern_entity("Hero");
    const ready = try world.intern_relation("Ready", .set);
    _ = try world.remember(hero, ready, 0, 0);
    const this_build = ProgramIdentity{ .fingerprint = 0x1234_5678_9abc_def0, .save_version = 2 };
    var bytes = std.array_list.Managed(u8).init(testing.allocator);
    defer bytes.deinit();
    var lw = ListWriter.init(&bytes);
    const meta = try write_save_state(testing.allocator, &lw.writer, &world, null, null, .{ .program = this_build });
    try testing.expectEqual(this_build, meta.program);

    var inspect: std.Io.Reader = .fixed(bytes.items);
    try testing.expectEqual(this_build, (try inspect_save_stream(testing.allocator, &inspect)).program);

    // The same build loads, and so does a reader that names no program.
    var same: std.Io.Reader = .fixed(bytes.items);
    _ = try read_save_state_for(testing.allocator, &same, &world, null, null, this_build);
    var unchecked: std.Io.Reader = .fixed(bytes.items);
    _ = try read_save_state(testing.allocator, &unchecked, &world, null, null);

    // Another build is refused before anything changes, whatever its save version.
    var other_world = try World.init(testing.allocator, 256 * 1024);
    defer other_world.deinit();
    _ = try other_world.intern_entity("Somebody");
    for ([_]u32{ 2, 3 }) |version| {
        var other: std.Io.Reader = .fixed(bytes.items);
        try testing.expectError(SaveError.SaveFromOtherBuild, read_save_state_for(testing.allocator, &other, &other_world, null, null, .{ .fingerprint = 0x0fed_cba9_8765_4321, .save_version = version }));
    }
    try testing.expect(other_world.lookup_entity("Hero") == null);
    try testing.expect(other_world.lookup_entity("Somebody") != null);

    var buf: [192]u8 = undefined;
    try testing.expectEqualStrings(
        "this save is from save version 2 of the game (build 12345678); this build is save version 3 (build 0fedcba9) and cannot load it",
        format_build_mismatch(&buf, this_build, .{ .fingerprint = 0x0fed_cba9_8765_4321, .save_version = 3 }),
    );
}

test "P48-08: a slot from another build is refused, not recovered from its backup" {
    const testing = std.testing;
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    const base_path = try tmp_dir.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(base_path);
    var sm = try SaveManager.init(testing.allocator, testing.io, base_path);
    defer sm.deinit();

    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    _ = try world.intern_entity("Hero");
    sm.program = .{ .fingerprint = 11, .save_version = 1 };
    _ = try sm.save_slot(1, &world, null, null, "first");
    _ = try sm.save_slot(1, &world, null, null, "second"); // the first becomes the backup
    try testing.expectEqual(@as(u64, 11), sm.get_slot_info(1).?.metadata.program.fingerprint);

    sm.program = .{ .fingerprint = 12, .save_version = 1 };
    try testing.expectError(SaveError.SaveFromOtherBuild, sm.load_slot(1, &world, null, null));
    sm.program = .{ .fingerprint = 11, .save_version = 1 };
    _ = try sm.load_slot(1, &world, null, null);
}

test "P48-08: checked-in version 3 save fixture names its build" {
    const testing = std.testing;
    const fixture = try std.Io.Dir.cwd().readFileAlloc(testing.io, "tests/fixtures/compat/v0.4.0-save-v3.sav", testing.allocator, .limited(1024 * 1024));
    defer testing.allocator.free(fixture);
    try testing.expectEqual(SAVE_VERSION, version_from_bytes(fixture).?);
    const build = ProgramIdentity{ .fingerprint = 0x5ace_d0c5_0000_0003, .save_version = 2 };
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var stream: std.Io.Reader = .fixed(fixture);
    const meta = try read_save_state_for(testing.allocator, &stream, &world, null, null, build);
    try testing.expectEqual(build, meta.program);
    try testing.expectEqualStrings("P48-08 compatibility fixture", meta.get_description());
    try testing.expect(world.has_fact(world.lookup_entity("FixtureHero").?, world.lookup_relation("Ready").?, null));
    var again: std.Io.Reader = .fixed(fixture);
    try testing.expectError(SaveError.SaveFromOtherBuild, read_save_state_for(testing.allocator, &again, &world, null, null, .{ .fingerprint = 7, .save_version = 2 }));
}

/// Validates a save stream's outer header and CRC32 checksum, returning the verified payload slice.
fn read_verified_payload(allocator: std.mem.Allocator, reader: anytype) !VerifiedPayload {
    var magic: [4]u8 = undefined;
    const m_read = try reader.readSliceShort(&magic);
    if (m_read < 4) return error.EndOfStream;
    if (!std.mem.eql(u8, &magic, &SAVE_MAGIC)) return SaveError.InvalidSaveMagic;

    const version = try reader.takeInt(u32, .little);
    if (version < MIN_SAVE_VERSION or version > SAVE_VERSION) return SaveError.UnsupportedSaveVersion;

    const expected_crc = try reader.takeInt(u32, .little);
    const payload_len = try reader.takeInt(u32, .little);
    if (payload_len == 0 or payload_len > MAX_SAVE_PAYLOAD_SIZE) {
        return SaveError.SavePayloadTooLarge;
    }

    const payload = try allocator.alloc(u8, payload_len);
    errdefer allocator.free(payload);
    try reader.readSliceAll(payload);

    const actual_crc = std.hash.Crc32.hash(payload);
    if (actual_crc != expected_crc) {
        return SaveError.ChecksumMismatch;
    }

    return .{ .version = version, .bytes = payload };
}

/// Inspects and verifies a save stream's integrity and returns its SaveMetadata without mutating world state (P17-01).
pub fn inspect_save_stream(allocator: std.mem.Allocator, reader: anytype) !SaveMetadata {
    const verified = try read_verified_payload(allocator, reader);
    defer allocator.free(verified.bytes);

    var fbs: std.Io.Reader = .fixed(verified.bytes);
    var meta = try deserialize_metadata(&fbs);
    if (verified.version >= 3) {
        meta.program = .{
            .fingerprint = try fbs.takeInt(u64, .little),
            .save_version = try fbs.takeInt(u32, .little),
        };
    }
    return meta;
}

/// Restores a complete persistent save state (.sav) into World, SpatialSystem, and VM after verifying CRC32 integrity (P17-01, D-020).
pub fn read_save_state(
    allocator: std.mem.Allocator,
    reader: anytype,
    world: *World,
    spatial: ?*SpatialSystem,
    vm: ?*VM,
) !SaveMetadata {
    return read_save_state_versioned(allocator, reader, world, spatial, vm, null, false, .{});
}

/// `read_save_state` for a known program (P48-08, D-162): a save written by a different build
/// is refused with `SaveFromOtherBuild` before anything is restored.
pub fn read_save_state_for(
    allocator: std.mem.Allocator,
    reader: anytype,
    world: *World,
    spatial: ?*SpatialSystem,
    vm: ?*VM,
    program: ProgramIdentity,
) !SaveMetadata {
    return read_save_state_versioned(allocator, reader, world, spatial, vm, null, false, program);
}

/// Restores a temporal save, requiring the matching hypervisor envelope (P31-04, D-048).
pub fn read_save_state_with_temporal(
    allocator: std.mem.Allocator,
    reader: anytype,
    world: *World,
    spatial: ?*SpatialSystem,
    vm: ?*VM,
    temporal: *TemporalHypervisor,
) !SaveMetadata {
    return read_save_state_versioned(allocator, reader, world, spatial, vm, temporal, true, .{});
}

/// `read_save_state_with_temporal` for a known program (P48-08, D-162).
pub fn read_save_state_with_temporal_for(
    allocator: std.mem.Allocator,
    reader: anytype,
    world: *World,
    spatial: ?*SpatialSystem,
    vm: ?*VM,
    temporal: *TemporalHypervisor,
    program: ProgramIdentity,
) !SaveMetadata {
    return read_save_state_versioned(allocator, reader, world, spatial, vm, temporal, true, program);
}

fn read_save_state_versioned(
    allocator: std.mem.Allocator,
    reader: anytype,
    world: *World,
    spatial: ?*SpatialSystem,
    vm: ?*VM,
    temporal: ?*TemporalHypervisor,
    require_temporal: bool,
    expected: ProgramIdentity,
) !SaveMetadata {
    const verified = try read_verified_payload(allocator, reader);
    defer allocator.free(verified.bytes);

    var fbs: std.Io.Reader = .fixed(verified.bytes);
    const pr = &fbs;

    // 1. Metadata, then the program identity (version 3). A save from another build is refused
    // here, before any state is touched (D-162). Until compatible loads land, a matching save
    // version does not admit a different build either.
    var meta = try deserialize_metadata(pr);
    if (meta.version != verified.version) return SaveError.InvalidTemporalState;
    if (verified.version >= 3) {
        meta.program = .{
            .fingerprint = try pr.takeInt(u64, .little),
            .save_version = try pr.takeInt(u32, .little),
        };
    }
    if (expected.known() and meta.program.known() and meta.program.fingerprint != expected.fingerprint) {
        return SaveError.SaveFromOtherBuild;
    }

    var pending_temporal: ?temporal_mod.TemporalSnapshot = null;
    defer if (pending_temporal) |*snapshot| snapshot.deinit();

    if (verified.version >= 2) {
        const has_temporal = try pr.takeByte();
        switch (has_temporal) {
            0 => if (require_temporal) return SaveError.MissingTemporalState,
            1 => {
                const temporal_len = try pr.takeInt(u32, .little);
                if (temporal_len == 0 or temporal_len > MAX_SAVE_PAYLOAD_SIZE) {
                    return SaveError.SavePayloadTooLarge;
                }
                const temporal_bytes = try allocator.alloc(u8, temporal_len);
                defer allocator.free(temporal_bytes);
                try pr.readSliceAll(temporal_bytes);
                if (temporal != null or require_temporal) {
                    var temporal_stream: std.Io.Reader = .fixed(temporal_bytes);
                    pending_temporal = try temporal_mod.TemporalSnapshot.read(allocator, world, &temporal_stream);
                }
            },
            else => return SaveError.InvalidTemporalState,
        }
    } else if (require_temporal) {
        return SaveError.MissingTemporalState;
    }

    // 2. World relational state
    try world.restore_state(pr);
    world.recently_expired_count = 0;
    if (pending_temporal) |*snapshot| try snapshot.validate(world);

    // 3. Spatial motor agents
    const has_spatial = try pr.takeByte();
    if (has_spatial != 0) {
        const agent_count = try pr.takeInt(u32, .little);
        if (spatial) |sp| {
            var old_it = sp.agents.valueIterator();
            while (old_it.next()) |ag| {
                ag.deinit(sp.allocator);
            }
            sp.agents.clearRetainingCapacity();

            var ai: u32 = 0;
            while (ai < agent_count) : (ai += 1) {
                const ent_raw = try pr.takeInt(u32, .little);
                const px = try pr.takeInt(i32, .little);
                const py = try pr.takeInt(i32, .little);
                const cur_wp = try pr.takeInt(u16, .little);
                const target_wp_raw = try pr.takeInt(u16, .little);
                const speed = try pr.takeInt(u32, .little);
                const is_moving = (try pr.takeByte()) != 0;
                const arrived = (try pr.takeByte()) != 0;
                const path_index = try pr.takeInt(u16, .little);
                const path_len = try pr.takeInt(u16, .little);

                var path_slice: ?[]WaypointId = null;
                if (path_len > 0) {
                    const pbuf = try sp.allocator.alloc(WaypointId, path_len);
                    for (0..path_len) |pi| {
                        pbuf[pi] = try pr.takeInt(u16, .little);
                    }
                    path_slice = pbuf;
                }

                const ent = EntityId.from_int(ent_raw);
                try sp.agents.put(ent, MotorAgent{
                    .entity = ent,
                    .pos = .{ .x = px, .y = py },
                    .current_wp = cur_wp,
                    .target_wp = if (target_wp_raw == 0) null else target_wp_raw,
                    .path = path_slice,
                    .path_index = path_index,
                    .speed = speed,
                    .is_moving = is_moving,
                    .arrived = arrived,
                });
            }
        } else {
            // Skip spatial section if caller did not pass a SpatialSystem
            var ai: u32 = 0;
            while (ai < agent_count) : (ai += 1) {
                _ = try pr.takeInt(u32, .little);
                _ = try pr.takeInt(i32, .little);
                _ = try pr.takeInt(i32, .little);
                _ = try pr.takeInt(u16, .little);
                _ = try pr.takeInt(u16, .little);
                _ = try pr.takeInt(u32, .little);
                _ = try pr.takeByte();
                _ = try pr.takeByte();
                _ = try pr.takeInt(u16, .little);
                const path_len = try pr.takeInt(u16, .little);
                var pi: u16 = 0;
                while (pi < path_len) : (pi += 1) {
                    _ = try pr.takeInt(u16, .little);
                }
            }
        }
    }

    // 4. VM execution state
    const has_vm = try pr.takeByte();
    if (has_vm != 0) {
        const cur_scene_raw = try pr.takeInt(u32, .little);
        const next_fib_id = try pr.takeInt(u32, .little);
        const fiber_count = try pr.takeInt(u32, .little);

        if (vm) |v| {
            v.current_scene = if (cur_scene_raw == 0) null else EntityId.from_int(cur_scene_raw);
            v.next_fiber_id = next_fib_id;
            v.emitted_cues.clearRetainingCapacity();
            v.pending_weaves.clearRetainingCapacity();

            for (v.fibers.items) |*f| {
                f.deinit();
            }
            v.fibers.clearRetainingCapacity();

            var fi: u32 = 0;
            while (fi < fiber_count) : (fi += 1) {
                const fid = try pr.takeInt(u32, .little);
                const owner_raw = try pr.takeInt(u32, .little);
                const pc = try pr.takeInt(u32, .little);
                const sp_val = try pr.takeInt(u16, .little);
                const active_prio = try pr.takeInt(u16, .little);

                var fib = Fiber.init(v.allocator, fid, EntityId.from_int(owner_raw), pc);
                errdefer fib.deinit();
                fib.sp = @min(sp_val, vm_mod.MAX_STACK);
                fib.active_priority = active_prio;

                var si: u16 = 0;
                while (si < sp_val) : (si += 1) {
                    const sval = try pr.takeInt(u32, .little);
                    if (si < vm_mod.MAX_STACK) {
                        fib.stack[si] = sval;
                    }
                }
                fib.state = try read_fiber_state(pr);

                const int_depth = try pr.takeInt(u16, .little);
                var ii: u16 = 0;
                while (ii < int_depth) : (ii += 1) {
                    const ipc = try pr.takeInt(u32, .little);
                    const isp = try pr.takeInt(u16, .little);
                    const iprio = try pr.takeInt(u16, .little);
                    const istate = try read_fiber_state(pr);
                    try fib.interrupt_stack.append(InterruptFrame{
                        .pc = ipc,
                        .sp = isp,
                        .state = istate,
                        .priority = iprio,
                    });
                }

                try v.fibers.append(fib);
            }

            const rule_count = try pr.takeInt(u32, .little);
            var ri: u32 = 0;
            while (ri < rule_count) : (ri += 1) {
                const is_act = (try pr.takeByte()) != 0;
                if (ri < v.reactive_rules.items.len) {
                    v.reactive_rules.items[ri].is_active = is_act;
                }
            }
        }
    }

    if (pending_temporal) |*snapshot| {
        if (temporal) |hypervisor| try snapshot.apply(hypervisor);
    }

    return meta;
}

/// Slot status and metadata tracked by SaveManager (P17-02, D-020).
pub const SaveSlotInfo = struct {
    slot_id: u8 = 0,
    occupied: bool = false,
    corrupted: bool = false,
    has_backup: bool = false,
    recovered_from_backup: bool = false,
    metadata: SaveMetadata = .{},
};

pub const LoadResult = struct {
    metadata: SaveMetadata,
    recovered_from_backup: bool,
};

/// Persistent Save/Load Slot Manager supporting numbered slots (1..8), Quick-Save (slot 0), and .bak recovery (P17-02, D-020).
/// Monotonic milliseconds for playtime: the awake clock, which wall-clock changes cannot move.
fn now_ms(io: std.Io) i64 {
    return std.Io.Timestamp.now(io, .awake).toMilliseconds();
}

pub const SaveManager = struct {
    /// Thumbnail colours for every save this manager writes; set from a display theme.
    thumbnails: ?*const ThumbnailPainter = null,
    /// The running program (P48-08, D-162). Every save records it, and a load refuses a save
    /// from another build. Hosts set it when they load a program; unknown loads unchecked.
    program: ProgramIdentity = .{},
    allocator: std.mem.Allocator,
    save_dir: []const u8,
    slots: [MAX_SLOTS + 1]SaveSlotInfo,
    session_start_ms: i64,
    accumulated_playtime_secs: u64,
    /// The host's I/O (Zig 0.16+): slot files, the save directory, and the playtime clock.
    io: std.Io,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, save_dir: []const u8) !SaveManager {
        const owned_dir = try allocator.dupe(u8, save_dir);
        var sm = SaveManager{
            .allocator = allocator,
            .io = io,
            .save_dir = owned_dir,
            .slots = undefined,
            .session_start_ms = now_ms(io),
            .accumulated_playtime_secs = 0,
        };
        for (0..MAX_SLOTS + 1) |i| {
            sm.slots[i] = SaveSlotInfo{ .slot_id = @intCast(i) };
        }
        sm.refresh_slots();
        return sm;
    }

    pub fn deinit(self: *SaveManager) void {
        self.allocator.free(self.save_dir);
        self.* = undefined;
    }

    /// Computes total playtime in seconds (accumulated prior save time + current session elapsed seconds).
    pub fn current_playtime_secs(self: *const SaveManager) u64 {
        const now = now_ms(self.io);
        const elapsed_ms = @max(0, now - self.session_start_ms);
        return self.accumulated_playtime_secs + @as(u64, @intCast(@divTrunc(elapsed_ms, 1000)));
    }

    /// Formats the file path for a slot (`quicksave.sav` for slot 0, `slot_N.sav` for 1..8).
    pub fn format_slot_path(self: *const SaveManager, slot_id: u8, buf: []u8) ![]const u8 {
        if (slot_id > MAX_SLOTS) return SaveError.InvalidSlotId;
        if (slot_id == QUICKSAVE_SLOT) {
            return std.fmt.bufPrint(buf, "{s}/quicksave.sav", .{self.save_dir});
        } else {
            return std.fmt.bufPrint(buf, "{s}/slot_{d}.sav", .{ self.save_dir, slot_id });
        }
    }

    /// Formats the backup file path (`.sav.bak`) for a slot (P17-02).
    pub fn format_backup_path(self: *const SaveManager, slot_id: u8, buf: []u8) ![]const u8 {
        if (slot_id > MAX_SLOTS) return SaveError.InvalidSlotId;
        if (slot_id == QUICKSAVE_SLOT) {
            return std.fmt.bufPrint(buf, "{s}/quicksave.sav.bak", .{self.save_dir});
        } else {
            return std.fmt.bufPrint(buf, "{s}/slot_{d}.sav.bak", .{ self.save_dir, slot_id });
        }
    }

    /// Inspects a single save file on disk and returns its SaveMetadata if valid.
    fn inspect_file(self: *const SaveManager, path: []const u8) !SaveMetadata {
        const file = try std.Io.Dir.cwd().openFile(self.io, path, .{});
        defer file.close(self.io);
        var buf: [4096]u8 = undefined;
        var reader = file.reader(self.io, &buf);
        return try inspect_save_stream(self.allocator, &reader.interface);
    }

    /// Scans the save directory and refreshes slot occupancy, metadata, and corruption/backup flags (P17-02).
    pub fn refresh_slots(self: *SaveManager) void {
        var slot_id: u8 = 0;
        while (slot_id <= MAX_SLOTS) : (slot_id += 1) {
            var info = SaveSlotInfo{ .slot_id = slot_id };
            var path_buf: [256]u8 = undefined;
            var bak_buf: [256]u8 = undefined;

            const slot_path = self.format_slot_path(slot_id, &path_buf) catch continue;
            const bak_path = self.format_backup_path(slot_id, &bak_buf) catch continue;

            // Check if backup exists and is valid
            const bak_meta: ?SaveMetadata = self.inspect_file(bak_path) catch null;
            info.has_backup = (bak_meta != null);

            if (self.inspect_file(slot_path)) |meta| {
                info.occupied = true;
                info.corrupted = false;
                info.metadata = meta;
            } else |err| {
                if (err == error.FileNotFound) {
                    if (bak_meta) |bm| {
                        // Primary file missing, but valid backup exists
                        info.occupied = true;
                        info.corrupted = true;
                        info.metadata = bm;
                    }
                } else {
                    // Primary file exists on disk but failed integrity check
                    info.occupied = true;
                    info.corrupted = true;
                    if (bak_meta) |bm| {
                        info.metadata = bm;
                    }
                }
            }

            self.slots[slot_id] = info;
        }
    }

    /// Returns metadata and status for a slot (0..8).
    pub fn get_slot_info(self: *const SaveManager, slot_id: u8) ?SaveSlotInfo {
        if (slot_id > MAX_SLOTS) return null;
        return self.slots[slot_id];
    }

    /// Saves simulation state to the specified slot (0..8), preserving any existing valid save as `.sav.bak` (P17-02).
    pub fn save_slot(
        self: *SaveManager,
        slot_id: u8,
        world: *const World,
        spatial: ?*const SpatialSystem,
        vm: ?*const VM,
        description: []const u8,
    ) !SaveMetadata {
        return self.save_slot_versioned(slot_id, world, spatial, vm, null, description);
    }

    /// Saves a slot with the temporal hypervisor envelope (P31-04, D-048).
    pub fn save_slot_with_temporal(
        self: *SaveManager,
        slot_id: u8,
        world: *const World,
        spatial: ?*const SpatialSystem,
        vm: ?*const VM,
        temporal: *const TemporalHypervisor,
        description: []const u8,
    ) !SaveMetadata {
        return self.save_slot_versioned(slot_id, world, spatial, vm, temporal, description);
    }

    fn save_slot_versioned(
        self: *SaveManager,
        slot_id: u8,
        world: *const World,
        spatial: ?*const SpatialSystem,
        vm: ?*const VM,
        temporal: ?*const TemporalHypervisor,
        description: []const u8,
    ) !SaveMetadata {
        if (slot_id > MAX_SLOTS) return SaveError.InvalidSlotId;

        try std.Io.Dir.cwd().createDirPath(self.io, self.save_dir);

        var path_buf: [256]u8 = undefined;
        var bak_buf: [256]u8 = undefined;
        const slot_path = try self.format_slot_path(slot_id, &path_buf);
        const bak_path = try self.format_backup_path(slot_id, &bak_buf);

        // If an existing valid save is present at slot_path, preserve it as slot_path.bak before overwriting
        if (self.inspect_file(slot_path)) |_| {
            std.Io.Dir.cwd().copyFile(slot_path, std.Io.Dir.cwd(), bak_path, self.io, .{}) catch {};
        } else |_| {}

        const file = try std.Io.Dir.cwd().createFile(self.io, slot_path, .{ .truncate = true });
        defer file.close(self.io);
        var buf: [4096]u8 = undefined;
        var file_writer = file.writer(self.io, &buf);

        const options = SaveOptions{
            .thumbnail = self.thumbnails,
            .slot_id = slot_id,
            .playtime_secs = self.current_playtime_secs(),
            .description = description,
            .timestamp = std.Io.Timestamp.now(self.io, .real).toSeconds(),
            .program = self.program,
        };
        const meta = if (temporal) |hypervisor|
            try write_save_state_with_temporal(self.allocator, &file_writer.interface, world, spatial, vm, hypervisor, options)
        else
            try write_save_state(self.allocator, &file_writer.interface, world, spatial, vm, options);
        try file_writer.interface.flush();

        const has_bak = (self.inspect_file(bak_path) catch null) != null;
        self.slots[slot_id] = SaveSlotInfo{
            .slot_id = slot_id,
            .occupied = true,
            .corrupted = false,
            .has_backup = has_bak,
            .recovered_from_backup = false,
            .metadata = meta,
        };

        return meta;
    }

    /// Loads simulation state from the specified slot (0..8).
    /// Automatically recovers from `.sav.bak` if the primary save file is corrupted or truncated (P17-02, D-020).
    pub fn load_slot(
        self: *SaveManager,
        slot_id: u8,
        world: *World,
        spatial: ?*SpatialSystem,
        vm: ?*VM,
    ) !LoadResult {
        return self.load_slot_versioned(slot_id, world, spatial, vm, null);
    }

    /// Loads a slot with the temporal hypervisor envelope (P31-04, D-048).
    pub fn load_slot_with_temporal(
        self: *SaveManager,
        slot_id: u8,
        world: *World,
        spatial: ?*SpatialSystem,
        vm: ?*VM,
        temporal: *TemporalHypervisor,
    ) !LoadResult {
        return self.load_slot_versioned(slot_id, world, spatial, vm, temporal);
    }

    fn load_slot_versioned(
        self: *SaveManager,
        slot_id: u8,
        world: *World,
        spatial: ?*SpatialSystem,
        vm: ?*VM,
        temporal: ?*TemporalHypervisor,
    ) !LoadResult {
        if (slot_id > MAX_SLOTS) return SaveError.InvalidSlotId;

        var path_buf: [256]u8 = undefined;
        var bak_buf: [256]u8 = undefined;
        const slot_path = try self.format_slot_path(slot_id, &path_buf);
        const bak_path = try self.format_backup_path(slot_id, &bak_buf);

        // 1. Attempt primary save file
        if (std.Io.Dir.cwd().openFile(self.io, slot_path, .{})) |file| {
            defer file.close(self.io);
            var buf: [4096]u8 = undefined;
            var file_reader = file.reader(self.io, &buf);
            const loaded = if (temporal) |hypervisor|
                read_save_state_with_temporal_for(self.allocator, &file_reader.interface, world, spatial, vm, hypervisor, self.program)
            else
                read_save_state_for(self.allocator, &file_reader.interface, world, spatial, vm, self.program);
            if (loaded) |meta| {
                self.accumulated_playtime_secs = meta.playtime_secs;
                self.session_start_ms = now_ms(self.io);
                self.slots[slot_id].occupied = true;
                self.slots[slot_id].corrupted = false;
                self.slots[slot_id].recovered_from_backup = false;
                self.slots[slot_id].metadata = meta;
                return LoadResult{
                    .metadata = meta,
                    .recovered_from_backup = false,
                };
            } else |err| {
                // A save from another build is intact, so its backup is no better: refuse it
                // rather than quietly load an older save (D-162).
                if (err == SaveError.SaveFromOtherBuild) return err;
                // Primary file failed checksum/magic/version/EOF -> fall through to backup recovery
                self.slots[slot_id].corrupted = true;
            }
        } else |err| {
            if (err != error.FileNotFound) return err;
        }

        // 2. Corrupted or missing primary file: attempt recovery from .sav.bak (P17-02)
        const bak_file = std.Io.Dir.cwd().openFile(self.io, bak_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                if (self.slots[slot_id].corrupted) return SaveError.CorruptedSaveUnrecoverable;
                return SaveError.EmptySlot;
            }
            return err;
        };
        defer bak_file.close(self.io);
        var bak_buf_io: [4096]u8 = undefined;
        var bak_reader = bak_file.reader(self.io, &bak_buf_io);

        const recovered_meta = if (temporal) |hypervisor|
            read_save_state_with_temporal_for(self.allocator, &bak_reader.interface, world, spatial, vm, hypervisor, self.program) catch {
                return SaveError.CorruptedSaveUnrecoverable;
            }
        else
            read_save_state_for(self.allocator, &bak_reader.interface, world, spatial, vm, self.program) catch {
                return SaveError.CorruptedSaveUnrecoverable;
            };

        // Self-heal primary slot file from the verified backup
        std.Io.Dir.cwd().copyFile(bak_path, std.Io.Dir.cwd(), slot_path, self.io, .{}) catch {};

        self.accumulated_playtime_secs = recovered_meta.playtime_secs;
        self.session_start_ms = now_ms(self.io);
        self.slots[slot_id] = SaveSlotInfo{
            .slot_id = slot_id,
            .occupied = true,
            .corrupted = false,
            .has_backup = true,
            .recovered_from_backup = true,
            .metadata = recovered_meta,
        };

        return LoadResult{
            .metadata = recovered_meta,
            .recovered_from_backup = true,
        };
    }

    /// Saves state to dedicated Quick-Save slot 0 (`quicksave.sav`, P17-02).
    pub fn quick_save(
        self: *SaveManager,
        world: *const World,
        spatial: ?*const SpatialSystem,
        vm: ?*const VM,
    ) !SaveMetadata {
        return self.save_slot(QUICKSAVE_SLOT, world, spatial, vm, "Quick Save");
    }

    pub fn quick_save_with_temporal(
        self: *SaveManager,
        world: *const World,
        spatial: ?*const SpatialSystem,
        vm: ?*const VM,
        temporal: *const TemporalHypervisor,
    ) !SaveMetadata {
        return self.save_slot_with_temporal(QUICKSAVE_SLOT, world, spatial, vm, temporal, "Quick Save");
    }

    /// Restores state from dedicated Quick-Save slot 0 (`quicksave.sav`, P17-02).
    pub fn quick_load(
        self: *SaveManager,
        world: *World,
        spatial: ?*SpatialSystem,
        vm: ?*VM,
    ) !LoadResult {
        return self.load_slot(QUICKSAVE_SLOT, world, spatial, vm);
    }

    pub fn quick_load_with_temporal(
        self: *SaveManager,
        world: *World,
        spatial: ?*SpatialSystem,
        vm: ?*VM,
        temporal: *TemporalHypervisor,
    ) !LoadResult {
        return self.load_slot_with_temporal(QUICKSAVE_SLOT, world, spatial, vm, temporal);
    }

    /// Deletes a save slot and its backup file from disk.
    pub fn delete_slot(self: *SaveManager, slot_id: u8) !void {
        if (slot_id > MAX_SLOTS) return SaveError.InvalidSlotId;

        var path_buf: [256]u8 = undefined;
        var bak_buf: [256]u8 = undefined;
        const slot_path = try self.format_slot_path(slot_id, &path_buf);
        const bak_path = try self.format_backup_path(slot_id, &bak_buf);

        std.Io.Dir.cwd().deleteFile(self.io, slot_path) catch {};
        std.Io.Dir.cwd().deleteFile(self.io, bak_path) catch {};
        self.slots[slot_id] = SaveSlotInfo{ .slot_id = slot_id };
    }
};

// ============================================================================
// Unit Tests (P17-01, P17-02)
// ============================================================================

test "P17-01: RGB332 thumbnail pixel packing and generation" {
    const testing = std.testing;

    const packed_gold = pack_rgb332(250, 204, 21);
    const unpacked = unpack_rgb332(packed_gold);
    try testing.expect(unpacked.r >= 200);
    try testing.expect(unpacked.g >= 170);
    try testing.expect(unpacked.b <= 85);

    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();

    const tavern = try world.intern_entity("Tavern");
    const cat = try world.intern_entity("Cat");
    const wp = try spatial.graph.add_waypoint(tavern, 10, 0, "Bar");
    try spatial.register_entity(cat, wp, 4);

    const thumb = generate_thumbnail(&world, &spatial, "Stage", null);
    try testing.expectEqual(@as(usize, THUMB_SIZE), thumb.len);

    // Ensure non-zero pixels and hearth/actor variation
    var non_zero: usize = 0;
    for (thumb) |px| {
        if (px != 0) non_zero += 1;
    }
    try testing.expect(non_zero == THUMB_SIZE);
}

test "P17-01: .sav stream serialization, metadata headers, and World/Spatial/VM restoration" {
    const testing = std.testing;
    const bytecode_mod = @import("bytecode.zig");

    var world = try World.init(testing.allocator, 512 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();

    const tavern = try world.intern_entity("Tavern");
    const cellar = try world.intern_entity("CellarRoom");
    const guard = try world.intern_entity("Guard");
    const cheese = try world.intern_entity("Cheese");
    const carries = try world.intern_relation("Carries", .set);

    const wp1 = try spatial.graph.add_waypoint(tavern, 0, 0, "Hearth");
    const wp2 = try spatial.graph.add_waypoint(cellar, 30, 0, "Cellar");
    try spatial.graph.connect(wp1, wp2, null);
    try spatial.register_entity(guard, wp1, 5);
    _ = try spatial.walk_to(guard, wp2);

    try world.remember(guard, carries, cheese.to_int(), 25);
    _ = world.step_tick();
    _ = world.step_tick();
    _ = spatial.step_tick();

    var chunk = bytecode_mod.BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();
    _ = try chunk.emit_op(.halt);

    var vm = VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();
    vm.current_scene = cellar;
    const fid = try vm.spawn_routine(guard, 0);
    try vm.fibers.items[0].push(99);
    vm.fibers.items[0].state = .{ .waiting_ticks = 12 };
    _ = fid;

    // Serialize to memory buffer
    var save_buf = std.array_list.Managed(u8).init(testing.allocator);
    defer save_buf.deinit();
    var save_lw = ListWriter.init(&save_buf);

    const written_meta = try write_save_state(
        testing.allocator,
        &save_lw.writer,
        &world,
        &spatial,
        &vm,
        .{
            .slot_id = 3,
            .playtime_secs = 142,
            .timestamp = 1700000000,
            .description = "Cellar Patrol Mid-Walk",
        },
    );

    try testing.expectEqual(@as(u8, 3), written_meta.slot_id);
    try testing.expectEqual(@as(u64, 2), written_meta.current_tick);
    try testing.expectEqual(@as(u64, 142), written_meta.playtime_secs);
    try testing.expectEqualStrings("CellarRoom", written_meta.get_scene_name());
    try testing.expectEqualStrings("Cellar Patrol Mid-Walk", written_meta.get_description());
    try testing.expectEqual(@as(u8, 1), written_meta.actor_count);

    // Inspect stream without mutating world
    var inspect_stream: std.Io.Reader = .fixed(save_buf.items);
    const inspected = try inspect_save_stream(testing.allocator, &inspect_stream);
    try testing.expectEqual(@as(u64, 2), inspected.current_tick);
    try testing.expectEqualStrings("CellarRoom", inspected.get_scene_name());

    // Mutate live world, spatial, and VM forward
    _ = world.forget(guard, carries, cheese.to_int());
    _ = world.step_tick();
    _ = world.step_tick();
    vm.current_scene = tavern;
    vm.fibers.items[0].state = .{ .halted = {} };
    spatial.agents.getPtr(guard).?.pos = .{ .x = 999, .y = 999 };

    // Restore from .sav buffer
    var restore_stream: std.Io.Reader = .fixed(save_buf.items);
    const restored_meta = try read_save_state(
        testing.allocator,
        &restore_stream,
        &world,
        &spatial,
        &vm,
    );

    try testing.expectEqual(@as(u64, 2), restored_meta.current_tick);
    try testing.expectEqual(@as(u64, 2), world.current_tick);
    try testing.expect(world.has_fact(guard, carries, cheese.to_int()));
    try testing.expectEqual(cellar, vm.current_scene.?);
    try testing.expectEqual(@as(usize, 1), vm.fibers.items.len);
    try testing.expectEqual(@as(u32, 99), try vm.fibers.items[0].peek());
    try testing.expectEqual(FiberStateTag.waiting_ticks, std.meta.activeTag(vm.fibers.items[0].state));
    try testing.expectEqual(@as(i32, 5), spatial.agents.get(guard).?.pos.x);
    try testing.expect(spatial.agents.get(guard).?.is_moving);
}

test "P17-01: .sav rejects corrupted CRC32, invalid magic, and unsupported versions" {
    const testing = std.testing;

    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();

    var save_buf = std.array_list.Managed(u8).init(testing.allocator);
    defer save_buf.deinit();
    var lw2 = ListWriter.init(&save_buf);
    _ = try write_save_state(testing.allocator, &lw2.writer, &world, null, null, .{});

    // 1. Corrupt payload byte -> ChecksumMismatch
    var corrupted = try testing.allocator.dupe(u8, save_buf.items);
    defer testing.allocator.free(corrupted);
    corrupted[corrupted.len - 1] ^= 0xFF;

    var s1: std.Io.Reader = .fixed(corrupted);
    try testing.expectError(SaveError.ChecksumMismatch, read_save_state(testing.allocator, &s1, &world, null, null));

    // 2. Corrupt magic header -> InvalidSaveMagic
    var bad_magic = try testing.allocator.dupe(u8, save_buf.items);
    defer testing.allocator.free(bad_magic);
    bad_magic[0] = 'X';

    var s2: std.Io.Reader = .fixed(bad_magic);
    try testing.expectError(SaveError.InvalidSaveMagic, read_save_state(testing.allocator, &s2, &world, null, null));

    // 3. Unsupported version -> UnsupportedSaveVersion
    var bad_ver = try testing.allocator.dupe(u8, save_buf.items);
    defer testing.allocator.free(bad_ver);
    bad_ver[4] = 99;

    var s3: std.Io.Reader = .fixed(bad_ver);
    try testing.expectError(SaveError.UnsupportedSaveVersion, read_save_state(testing.allocator, &s3, &world, null, null));

    var message_buf: [128]u8 = undefined;
    try testing.expectEqualStrings(
        "unsupported .sav format version 99; this engine supports versions 1 through 3",
        format_unsupported_version(&message_buf, version_from_bytes(bad_ver).?),
    );
}

test "P38-02: checked-in version 2 save fixture loads" {
    const testing = std.testing;
    const fixture = try std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        "tests/fixtures/compat/v0.1.0-save-v2.sav",
        testing.allocator,
        .limited(1024 * 1024),
    );
    defer testing.allocator.free(fixture);

    try testing.expectEqual(@as(u32, 2), version_from_bytes(fixture).?);

    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var stream: std.Io.Reader = .fixed(fixture);
    const meta = try read_save_state(testing.allocator, &stream, &world, null, null);

    try testing.expectEqual(@as(u32, 2), meta.version);
    try testing.expectEqualStrings("P38-02 compatibility fixture", meta.get_description());
    try testing.expect(world.lookup_entity("FixtureHero") != null);
    try testing.expect(world.lookup_relation("Ready") != null);
}

test "P17-02: SaveManager numbered slots, quick-save/load, and corrupted save .bak recovery" {
    const testing = std.testing;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const base_path = try tmp_dir.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(base_path);

    var sm = try SaveManager.init(testing.allocator, testing.io, base_path);
    defer sm.deinit();

    var world = try World.init(testing.allocator, 512 * 1024);
    defer world.deinit();

    const cat = try world.intern_entity("Cat");
    const cheese = try world.intern_entity("Cheese");
    const carries = try world.intern_relation("Carries", .set);

    // 1. Quick-Save at Tick 5
    for (0..5) |_| _ = world.step_tick();
    try world.remember(cat, carries, cheese.to_int(), 0);
    _ = try sm.quick_save(&world, null, null);
    try testing.expect(sm.get_slot_info(QUICKSAVE_SLOT).?.occupied);

    // Advance and clear fact, then Quick-Load
    _ = world.forget(cat, carries, cheese.to_int());
    _ = world.step_tick();
    try testing.expectEqual(@as(u64, 6), world.current_tick);

    const ql_res = try sm.quick_load(&world, null, null);
    try testing.expect(!ql_res.recovered_from_backup);
    try testing.expectEqual(@as(u64, 5), world.current_tick);
    try testing.expect(world.has_fact(cat, carries, cheese.to_int()));

    // 2. Save Slot 1 at Tick 5 (creates initial slot_1.sav)
    _ = try sm.save_slot(1, &world, null, null, "First Save at Tick 5");

    // Advance to Tick 10 and save Slot 1 again (preserves Tick 5 in slot_1.sav.bak)
    for (0..5) |_| _ = world.step_tick();
    _ = try sm.save_slot(1, &world, null, null, "Second Save at Tick 10");
    try testing.expect(sm.get_slot_info(1).?.has_backup);

    // Corrupt primary slot_1.sav on disk!
    var slot1_path_buf: [256]u8 = undefined;
    const slot1_path = try sm.format_slot_path(1, &slot1_path_buf);
    {
        const f = try std.Io.Dir.cwd().openFile(testing.io, slot1_path, .{ .mode = .read_write });
        defer f.close(testing.io);
        try f.writePositionalAll(testing.io, "CORRUPTED_BYTES!", 20);
    }

    sm.refresh_slots();
    try testing.expect(sm.get_slot_info(1).?.corrupted);
    try testing.expect(sm.get_slot_info(1).?.has_backup);

    // Load Slot 1: should automatically recover Tick 5 state from slot_1.sav.bak and repair slot_1.sav!
    const recovered = try sm.load_slot(1, &world, null, null);
    try testing.expect(recovered.recovered_from_backup);
    try testing.expectEqual(@as(u64, 5), world.current_tick);
    try testing.expect(!sm.get_slot_info(1).?.corrupted);

    // Delete Slot 1
    try sm.delete_slot(1);
    try testing.expect(!sm.get_slot_info(1).?.occupied);
}

const TestPainter = struct {
    fn backdrop(scene: []const u8, x: usize, y: usize) ?u8 {
        if (!std.mem.eql(u8, scene, "Marsh")) return null;
        return if (x == 0 and y == 0) pack_rgb332(0, 255, 0) else null;
    }
    fn actor(name: []const u8) ?u8 {
        return if (std.mem.eql(u8, name, "Heron")) pack_rgb332(255, 0, 0) else null;
    }
};

test "P32-03d: thumbnails are neutral by default and take a painter's colours" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    const marsh = try world.intern_entity("Marsh");
    const heron = try world.intern_entity("Heron");
    const frog = try world.intern_entity("Frog");
    const wp = try spatial.graph.add_waypoint(marsh, 10, 0, "Reeds");
    const wp2 = try spatial.graph.add_waypoint(marsh, 40, 0, "Pool");
    try spatial.register_entity(heron, wp, 4);
    try spatial.register_entity(frog, wp2, 4);

    const plain = generate_thumbnail(&world, &spatial, "Marsh", null);
    // Neutral stage: one colour above row 6, another below, gold actor dots.
    try testing.expectEqual(pack_rgb332(34, 38, 48), plain[0]);
    try testing.expectEqual(pack_rgb332(52, 56, 66), plain[11 * THUMB_WIDTH]);

    const painter = ThumbnailPainter{ .backdrop = TestPainter.backdrop, .actor = TestPainter.actor };
    const painted = generate_thumbnail(&world, &spatial, "Marsh", &painter);
    try testing.expectEqual(pack_rgb332(0, 255, 0), painted[0]);
    // Pixels the painter declines keep the default.
    try testing.expectEqual(plain[1], painted[1]);

    var red: usize = 0;
    var gold: usize = 0;
    for (painted) |px| {
        if (px == pack_rgb332(255, 0, 0)) red += 1;
        if (px == pack_rgb332(250, 204, 21)) gold += 1;
    }
    try testing.expectEqual(@as(usize, 1), red); // the heron
    try testing.expectEqual(@as(usize, 1), gold); // the frog, which the painter declines

    // Another scene is untouched by this painter's backdrop.
    const other = generate_thumbnail(&world, &spatial, "Moor", &painter);
    try testing.expectEqual(plain[0], other[0]);
}

test "P31-04: a save restores the hypervisor envelope; one without it stays readable" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    const hero = try world.intern_entity("Hero");
    const engine = try world.intern_entity("Engine");
    const room = try world.intern_entity("Room");
    const in_room = try world.intern_relation("InRoom", .property);
    _ = try world.remember(hero, in_room, room.to_int(), 0);

    var hypervisor = TemporalHypervisor.init(testing.allocator, &world);
    defer hypervisor.deinit();
    _ = try hypervisor.fork_branch(10, hero, engine);
    _ = try hypervisor.step_tick(null);

    var buffer = std.array_list.Managed(u8).init(testing.allocator);
    defer buffer.deinit();
    var buffer_lw = ListWriter.init(&buffer);
    const meta = try write_save_state_with_temporal(
        testing.allocator,
        &buffer_lw.writer,
        &world,
        null,
        null,
        &hypervisor,
        .{},
    );
    try testing.expectEqual(SAVE_VERSION, meta.version);

    // Move both the primary world and the branch past the saved state.
    _ = try world.remember(hero, in_room, engine.to_int(), 0);
    _ = try hypervisor.step_tick(null);

    var loaded_world = try World.init(testing.allocator, 1024 * 1024);
    defer loaded_world.deinit();
    var loaded_hypervisor = TemporalHypervisor.init(testing.allocator, &loaded_world);
    defer loaded_hypervisor.deinit();
    var stream: std.Io.Reader = .fixed(buffer.items);
    const loaded_meta = try read_save_state_with_temporal(
        testing.allocator,
        &stream,
        &loaded_world,
        null,
        null,
        &loaded_hypervisor,
    );
    try testing.expectEqual(SAVE_VERSION, loaded_meta.version);
    try testing.expect(loaded_world.has_fact(hero, in_room, room.to_int()));
    try testing.expectEqual(@as(u64, 1), loaded_hypervisor.ticks_elapsed);
    try testing.expect(loaded_hypervisor.branch_world.?.has_fact(hero, in_room, room.to_int()));
    try testing.expectEqual(@as(u64, 1), loaded_hypervisor.branch_world.?.current_tick);

    // A non-temporal reader skips the envelope and still restores the primary world.
    var plain_world = try World.init(testing.allocator, 1024 * 1024);
    defer plain_world.deinit();
    var plain_stream: std.Io.Reader = .fixed(buffer.items);
    const plain_meta = try read_save_state(testing.allocator, &plain_stream, &plain_world, null, null);
    try testing.expectEqual(SAVE_VERSION, plain_meta.version);
    try testing.expect(plain_world.has_fact(hero, in_room, room.to_int()));

    // A save written without the hypervisor remains readable, but cannot satisfy a temporal
    // restore: its temporal flag is 0.
    var legacy = std.array_list.Managed(u8).init(testing.allocator);
    defer legacy.deinit();
    var lw3 = ListWriter.init(&legacy);
    const legacy_meta = try write_save_state(testing.allocator, &lw3.writer, &world, null, null, .{});
    try testing.expectEqual(SAVE_VERSION, legacy_meta.version);
    var legacy_world = try World.init(testing.allocator, 1024 * 1024);
    defer legacy_world.deinit();
    var legacy_stream: std.Io.Reader = .fixed(legacy.items);
    _ = try read_save_state(testing.allocator, &legacy_stream, &legacy_world, null, null);

    var legacy_temporal_world = try World.init(testing.allocator, 1024 * 1024);
    defer legacy_temporal_world.deinit();
    var legacy_temporal = TemporalHypervisor.init(testing.allocator, &legacy_temporal_world);
    defer legacy_temporal.deinit();
    var legacy_temporal_stream: std.Io.Reader = .fixed(legacy.items);
    try testing.expectError(
        SaveError.MissingTemporalState,
        read_save_state_with_temporal(
            testing.allocator,
            &legacy_temporal_stream,
            &legacy_temporal_world,
            null,
            null,
            &legacy_temporal,
        ),
    );
}
