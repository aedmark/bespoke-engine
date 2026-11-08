const std = @import("std");
const world_mod = @import("world.zig");
const spatial_mod = @import("spatial.zig");
const vm_mod = @import("vm.zig");

pub const World = world_mod.World;
pub const EntityId = world_mod.EntityId;
pub const SpatialSystem = spatial_mod.SpatialSystem;
pub const WaypointId = spatial_mod.WaypointId;
pub const MotorAgent = spatial_mod.MotorAgent;
pub const VM = vm_mod.VM;
pub const Fiber = vm_mod.Fiber;
pub const FiberState = vm_mod.FiberState;
pub const FiberStateTag = vm_mod.FiberStateTag;
pub const InterruptFrame = vm_mod.InterruptFrame;

/// 4-byte magic identifier for BeSpoke persistent save files (P17-01, D-020).
pub const SAVE_MAGIC = [4]u8{ 'B', 'S', 'A', 'V' };
pub const SAVE_VERSION: u32 = 1;

/// Number of user-addressable save slots (1..8), plus slot 0 reserved for Quick-Save (P17-02, D-020).
pub const MAX_SLOTS: u8 = 8;
pub const QUICKSAVE_SLOT: u8 = 0;

/// Miniature graphical thumbnail dimensions stored in every save header (16x12 RGB332 = 192 bytes).
pub const THUMB_WIDTH: usize = 16;
pub const THUMB_HEIGHT: usize = 12;
pub const THUMB_SIZE: usize = THUMB_WIDTH * THUMB_HEIGHT;

/// Upper bound on save payload allocation at untrusted disk boundary (SECURITY.md).
pub const MAX_SAVE_PAYLOAD_SIZE: u32 = 32 * 1024 * 1024;

pub const SaveError = error{
    InvalidSaveMagic,
    UnsupportedSaveVersion,
    ChecksumMismatch,
    SavePayloadTooLarge,
    InvalidSlotId,
    EmptySlot,
    CorruptedSaveUnrecoverable,
};

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
    name: [24]u8 = [_]u8{0} ** 24,
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
    scene_name: [32]u8 = [_]u8{0} ** 32,
    scene_name_len: u8 = 0,
    description: [64]u8 = [_]u8{0} ** 64,
    description_len: u8 = 0,
    actor_count: u8 = 0,
    actors: [8]SaveActorPreview = [_]SaveActorPreview{.{}} ** 8,
    thumbnail: [THUMB_SIZE]u8 = [_]u8{0} ** THUMB_SIZE,

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
};

/// Generates a 16x12 RGB332 miniature frame snapshot from active scene and spatial state (P17-01).
pub fn generate_thumbnail(
    world: *const World,
    spatial: ?*const SpatialSystem,
    scene_name: []const u8,
) [THUMB_SIZE]u8 {
    var thumb: [THUMB_SIZE]u8 = undefined;

    const is_spit = std.mem.indexOf(u8, scene_name, "Spit") != null or std.mem.indexOf(u8, scene_name, "Booty") != null;
    const is_cellar = std.mem.indexOf(u8, scene_name, "Cellar") != null;
    const is_garden = std.mem.indexOf(u8, scene_name, "Garden") != null or std.mem.indexOf(u8, scene_name, "Courtyard") != null;
    const is_bike = std.mem.indexOf(u8, scene_name, "Bike") != null or std.mem.indexOf(u8, scene_name, "Shop") != null;
    const is_hotel = std.mem.indexOf(u8, scene_name, "Hotel") != null or std.mem.indexOf(u8, scene_name, "Corridor") != null;
    const is_road = std.mem.indexOf(u8, scene_name, "Road") != null;
    const is_sanctuary = std.mem.indexOf(u8, scene_name, "Sanctuary") != null or std.mem.indexOf(u8, scene_name, "Carla") != null;

    var y: usize = 0;
    while (y < THUMB_HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < THUMB_WIDTH) : (x += 1) {
            var pix: u8 = undefined;
            if (is_spit) {
                if (y < 4) {
                    pix = pack_rgb332(25, 45, 95); // Dusk sky
                } else if (y < 7) {
                    pix = pack_rgb332(20, 90, 150); // Ocean
                } else {
                    pix = if (x < 10) pack_rgb332(45, 110, 55) else pack_rgb332(190, 170, 110); // Grass & beach
                }
            } else if (is_garden) {
                if (y < 4) {
                    pix = pack_rgb332(135, 185, 230); // French sky
                } else if (y < 7) {
                    pix = pack_rgb332(160, 110, 60); // Courtyard fence & stone
                } else {
                    pix = pack_rgb332(55, 125, 50); // Courtyard lawn
                }
            } else if (is_bike) {
                if (y < 6) {
                    pix = pack_rgb332(85, 75, 65); // Shop plaster wall
                } else {
                    pix = pack_rgb332(150, 95, 45); // Shop floor & counter
                }
            } else if (is_hotel) {
                if (y < 6) {
                    pix = pack_rgb332(110, 30, 40); // Burgundy wallpaper
                } else {
                    pix = pack_rgb332(55, 25, 20); // Mahogany wainscot & carpet
                }
            } else if (is_cellar) {
                if (y < 6) {
                    pix = pack_rgb332(25, 35, 55); // Subterranean cellar wall
                } else {
                    pix = pack_rgb332(40, 50, 70); // Stone floor
                }
            } else if (is_road) {
                if (y < 5) {
                    pix = pack_rgb332(15, 30, 70); // Night sky
                } else {
                    pix = pack_rgb332(40, 75, 50); // Forest path
                }
            } else if (is_sanctuary) {
                if (y < 5) {
                    pix = pack_rgb332(70, 20, 35); // Dramatic sanctuary
                } else {
                    pix = pack_rgb332(45, 35, 45); // Duel arena
                }
            } else {
                // Default Tavern warm hearth & timber
                if (y < 6) {
                    pix = pack_rgb332(55, 38, 28);
                } else {
                    pix = pack_rgb332(80, 52, 34);
                }
                if (x >= 1 and x <= 3 and y >= 3 and y <= 5) {
                    pix = pack_rgb332(245, 140, 30); // Hearth fire glow
                }
            }
            thumb[y * THUMB_WIDTH + x] = pix;
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
            if (world.get_entity_name(agent.entity)) |ename| {
                if (std.mem.eql(u8, ename, "Guard") or std.mem.eql(u8, ename, "Guybrush") or std.mem.eql(u8, ename, "Mosely")) {
                    actor_col = pack_rgb332(50, 130, 245); // Blue
                } else if (std.mem.eql(u8, ename, "Cat") or std.mem.eql(u8, ename, "Gabriel")) {
                    actor_col = pack_rgb332(240, 120, 30); // Orange / Tan
                } else if (std.mem.eql(u8, ename, "Bard") or std.mem.eql(u8, ename, "Carla")) {
                    actor_col = pack_rgb332(180, 70, 240); // Purple
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
    }
}

fn read_fiber_state(reader: anytype) !FiberState {
    const tag = try reader.readByte();
    const val = try reader.readInt(u64, .little);
    return switch (tag) {
        0 => FiberState{ .ready = {} },
        1 => FiberState{ .waiting_ticks = val },
        2 => FiberState{ .waiting_cond = @intCast(val) },
        3 => FiberState{ .waiting_motor = EntityId.from_int(@intCast(val)) },
        4 => FiberState{ .halted = {} },
        5 => FiberState{ .paused = {} },
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
    meta.version = try reader.readInt(u32, .little);
    meta.slot_id = try reader.readByte();
    meta.current_tick = try reader.readInt(u64, .little);
    meta.playtime_secs = try reader.readInt(u64, .little);
    meta.timestamp = try reader.readInt(i64, .little);
    meta.fact_count = try reader.readInt(u32, .little);
    meta.entity_count = try reader.readInt(u32, .little);
    meta.scene_id = try reader.readInt(u32, .little);
    meta.scene_name_len = @min(32, try reader.readByte());
    try reader.readNoEof(&meta.scene_name);
    meta.description_len = @min(64, try reader.readByte());
    try reader.readNoEof(&meta.description);
    meta.actor_count = @min(8, try reader.readByte());
    for (0..8) |i| {
        meta.actors[i].entity_id = try reader.readInt(u32, .little);
        meta.actors[i].x = try reader.readInt(i32, .little);
        meta.actors[i].y = try reader.readInt(i32, .little);
        meta.actors[i].name_len = @min(24, try reader.readByte());
        try reader.readNoEof(&meta.actors[i].name);
    }
    try reader.readNoEof(&meta.thumbnail);
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
        .timestamp = options.timestamp orelse std.time.timestamp(),
        .fact_count = @intCast(world.fact_count()),
        .entity_count = @intCast(world.entity_names.items.len),
        .scene_id = 0,
    };

    var resolved_scene: []const u8 = "Tavern";
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

    meta.thumbnail = generate_thumbnail(world, spatial, meta.get_scene_name());
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
    const meta = build_metadata(world, spatial, vm, options);

    var payload = std.ArrayList(u8).init(allocator);
    defer payload.deinit();
    const pw = payload.writer();

    // 1. Metadata header block
    try serialize_metadata(pw, &meta);

    // 2. World relational arena snapshot
    try world.save_state(pw);

    // 3. Spatial motor agents
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

    // 4. VM execution state (current_scene, fibers, interrupt stacks, reactive rule edge flags)
    if (vm) |v| {
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
    const crc = std.hash.Crc32.hash(payload.items);
    const payload_len: u32 = @intCast(payload.items.len);

    // Write outer file envelope: magic (4B) + version (4B) + crc32 (4B) + payload_len (4B) + payload
    try writer.writeAll(&SAVE_MAGIC);
    try writer.writeInt(u32, SAVE_VERSION, .little);
    try writer.writeInt(u32, crc, .little);
    try writer.writeInt(u32, payload_len, .little);
    try writer.writeAll(payload.items);

    return meta;
}

/// Validates a save stream's outer header and CRC32 checksum, returning the verified payload slice.
fn read_verified_payload(allocator: std.mem.Allocator, reader: anytype) ![]u8 {
    var magic: [4]u8 = undefined;
    const m_read = try reader.readAll(&magic);
    if (m_read < 4) return error.EndOfStream;
    if (!std.mem.eql(u8, &magic, &SAVE_MAGIC)) return SaveError.InvalidSaveMagic;

    const version = try reader.readInt(u32, .little);
    if (version != SAVE_VERSION) return SaveError.UnsupportedSaveVersion;

    const expected_crc = try reader.readInt(u32, .little);
    const payload_len = try reader.readInt(u32, .little);
    if (payload_len == 0 or payload_len > MAX_SAVE_PAYLOAD_SIZE) {
        return SaveError.SavePayloadTooLarge;
    }

    const payload = try allocator.alloc(u8, payload_len);
    errdefer allocator.free(payload);
    try reader.readNoEof(payload);

    const actual_crc = std.hash.Crc32.hash(payload);
    if (actual_crc != expected_crc) {
        return SaveError.ChecksumMismatch;
    }

    return payload;
}

/// Inspects and verifies a save stream's integrity and returns its SaveMetadata without mutating world state (P17-01).
pub fn inspect_save_stream(allocator: std.mem.Allocator, reader: anytype) !SaveMetadata {
    const payload = try read_verified_payload(allocator, reader);
    defer allocator.free(payload);

    var fbs = std.io.fixedBufferStream(payload);
    return try deserialize_metadata(fbs.reader());
}

/// Restores a complete persistent save state (.sav) into World, SpatialSystem, and VM after verifying CRC32 integrity (P17-01, D-020).
pub fn read_save_state(
    allocator: std.mem.Allocator,
    reader: anytype,
    world: *World,
    spatial: ?*SpatialSystem,
    vm: ?*VM,
) !SaveMetadata {
    const payload = try read_verified_payload(allocator, reader);
    defer allocator.free(payload);

    var fbs = std.io.fixedBufferStream(payload);
    const pr = fbs.reader();

    // 1. Metadata
    const meta = try deserialize_metadata(pr);

    // 2. World relational state
    try world.restore_state(pr);
    world.recently_expired_count = 0;

    // 3. Spatial motor agents
    const has_spatial = try pr.readByte();
    if (has_spatial != 0) {
        const agent_count = try pr.readInt(u32, .little);
        if (spatial) |sp| {
            var old_it = sp.agents.valueIterator();
            while (old_it.next()) |ag| {
                ag.deinit(sp.allocator);
            }
            sp.agents.clearRetainingCapacity();

            var ai: u32 = 0;
            while (ai < agent_count) : (ai += 1) {
                const ent_raw = try pr.readInt(u32, .little);
                const px = try pr.readInt(i32, .little);
                const py = try pr.readInt(i32, .little);
                const cur_wp = try pr.readInt(u16, .little);
                const target_wp_raw = try pr.readInt(u16, .little);
                const speed = try pr.readInt(u32, .little);
                const is_moving = (try pr.readByte()) != 0;
                const arrived = (try pr.readByte()) != 0;
                const path_index = try pr.readInt(u16, .little);
                const path_len = try pr.readInt(u16, .little);

                var path_slice: ?[]WaypointId = null;
                if (path_len > 0) {
                    const pbuf = try sp.allocator.alloc(WaypointId, path_len);
                    for (0..path_len) |pi| {
                        pbuf[pi] = try pr.readInt(u16, .little);
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
                _ = try pr.readInt(u32, .little);
                _ = try pr.readInt(i32, .little);
                _ = try pr.readInt(i32, .little);
                _ = try pr.readInt(u16, .little);
                _ = try pr.readInt(u16, .little);
                _ = try pr.readInt(u32, .little);
                _ = try pr.readByte();
                _ = try pr.readByte();
                _ = try pr.readInt(u16, .little);
                const path_len = try pr.readInt(u16, .little);
                var pi: u16 = 0;
                while (pi < path_len) : (pi += 1) {
                    _ = try pr.readInt(u16, .little);
                }
            }
        }
    }

    // 4. VM execution state
    const has_vm = try pr.readByte();
    if (has_vm != 0) {
        const cur_scene_raw = try pr.readInt(u32, .little);
        const next_fib_id = try pr.readInt(u32, .little);
        const fiber_count = try pr.readInt(u32, .little);

        if (vm) |v| {
            v.current_scene = if (cur_scene_raw == 0) null else EntityId.from_int(cur_scene_raw);
            v.next_fiber_id = next_fib_id;
            v.emitted_cues.clearRetainingCapacity();

            for (v.fibers.items) |*f| {
                f.deinit();
            }
            v.fibers.clearRetainingCapacity();

            var fi: u32 = 0;
            while (fi < fiber_count) : (fi += 1) {
                const fid = try pr.readInt(u32, .little);
                const owner_raw = try pr.readInt(u32, .little);
                const pc = try pr.readInt(u32, .little);
                const sp_val = try pr.readInt(u16, .little);
                const active_prio = try pr.readInt(u16, .little);

                var fib = Fiber.init(v.allocator, fid, EntityId.from_int(owner_raw), pc);
                errdefer fib.deinit();
                fib.sp = @min(sp_val, vm_mod.MAX_STACK);
                fib.active_priority = active_prio;

                var si: u16 = 0;
                while (si < sp_val) : (si += 1) {
                    const sval = try pr.readInt(u32, .little);
                    if (si < vm_mod.MAX_STACK) {
                        fib.stack[si] = sval;
                    }
                }
                fib.state = try read_fiber_state(pr);

                const int_depth = try pr.readInt(u16, .little);
                var ii: u16 = 0;
                while (ii < int_depth) : (ii += 1) {
                    const ipc = try pr.readInt(u32, .little);
                    const isp = try pr.readInt(u16, .little);
                    const iprio = try pr.readInt(u16, .little);
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

            const rule_count = try pr.readInt(u32, .little);
            var ri: u32 = 0;
            while (ri < rule_count) : (ri += 1) {
                const is_act = (try pr.readByte()) != 0;
                if (ri < v.reactive_rules.items.len) {
                    v.reactive_rules.items[ri].is_active = is_act;
                }
            }
        }
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
pub const SaveManager = struct {
    allocator: std.mem.Allocator,
    save_dir: []const u8,
    slots: [MAX_SLOTS + 1]SaveSlotInfo,
    session_start_ms: i64,
    accumulated_playtime_secs: u64,

    pub fn init(allocator: std.mem.Allocator, save_dir: []const u8) !SaveManager {
        const owned_dir = try allocator.dupe(u8, save_dir);
        var sm = SaveManager{
            .allocator = allocator,
            .save_dir = owned_dir,
            .slots = undefined,
            .session_start_ms = std.time.milliTimestamp(),
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
        const now = std.time.milliTimestamp();
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
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        return try inspect_save_stream(self.allocator, file.reader());
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
        if (slot_id > MAX_SLOTS) return SaveError.InvalidSlotId;

        try std.fs.cwd().makePath(self.save_dir);

        var path_buf: [256]u8 = undefined;
        var bak_buf: [256]u8 = undefined;
        const slot_path = try self.format_slot_path(slot_id, &path_buf);
        const bak_path = try self.format_backup_path(slot_id, &bak_buf);

        // If an existing valid save is present at slot_path, preserve it as slot_path.bak before overwriting
        if (self.inspect_file(slot_path)) |_| {
            std.fs.cwd().copyFile(slot_path, std.fs.cwd(), bak_path, .{}) catch {};
        } else |_| {}

        const file = try std.fs.cwd().createFile(slot_path, .{ .truncate = true });
        defer file.close();

        const meta = try write_save_state(self.allocator, file.writer(), world, spatial, vm, .{
            .slot_id = slot_id,
            .playtime_secs = self.current_playtime_secs(),
            .description = description,
        });

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
        if (slot_id > MAX_SLOTS) return SaveError.InvalidSlotId;

        var path_buf: [256]u8 = undefined;
        var bak_buf: [256]u8 = undefined;
        const slot_path = try self.format_slot_path(slot_id, &path_buf);
        const bak_path = try self.format_backup_path(slot_id, &bak_buf);

        // 1. Attempt primary save file
        if (std.fs.cwd().openFile(slot_path, .{})) |file| {
            defer file.close();
            if (read_save_state(self.allocator, file.reader(), world, spatial, vm)) |meta| {
                self.accumulated_playtime_secs = meta.playtime_secs;
                self.session_start_ms = std.time.milliTimestamp();
                self.slots[slot_id].occupied = true;
                self.slots[slot_id].corrupted = false;
                self.slots[slot_id].recovered_from_backup = false;
                self.slots[slot_id].metadata = meta;
                return LoadResult{
                    .metadata = meta,
                    .recovered_from_backup = false,
                };
            } else |_| {
                // Primary file failed checksum/magic/version/EOF -> fall through to backup recovery
                self.slots[slot_id].corrupted = true;
            }
        } else |err| {
            if (err != error.FileNotFound) return err;
        }

        // 2. Corrupted or missing primary file: attempt recovery from .sav.bak (P17-02)
        const bak_file = std.fs.cwd().openFile(bak_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                if (self.slots[slot_id].corrupted) return SaveError.CorruptedSaveUnrecoverable;
                return SaveError.EmptySlot;
            }
            return err;
        };
        defer bak_file.close();

        const recovered_meta = read_save_state(self.allocator, bak_file.reader(), world, spatial, vm) catch {
            return SaveError.CorruptedSaveUnrecoverable;
        };

        // Self-heal primary slot file from the verified backup
        std.fs.cwd().copyFile(bak_path, std.fs.cwd(), slot_path, .{}) catch {};

        self.accumulated_playtime_secs = recovered_meta.playtime_secs;
        self.session_start_ms = std.time.milliTimestamp();
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

    /// Restores state from dedicated Quick-Save slot 0 (`quicksave.sav`, P17-02).
    pub fn quick_load(
        self: *SaveManager,
        world: *World,
        spatial: ?*SpatialSystem,
        vm: ?*VM,
    ) !LoadResult {
        return self.load_slot(QUICKSAVE_SLOT, world, spatial, vm);
    }

    /// Deletes a save slot and its backup file from disk.
    pub fn delete_slot(self: *SaveManager, slot_id: u8) !void {
        if (slot_id > MAX_SLOTS) return SaveError.InvalidSlotId;

        var path_buf: [256]u8 = undefined;
        var bak_buf: [256]u8 = undefined;
        const slot_path = try self.format_slot_path(slot_id, &path_buf);
        const bak_path = try self.format_backup_path(slot_id, &bak_buf);

        std.fs.cwd().deleteFile(slot_path) catch {};
        std.fs.cwd().deleteFile(bak_path) catch {};
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

    const thumb = generate_thumbnail(&world, &spatial, "Tavern");
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
    var save_buf = std.ArrayList(u8).init(testing.allocator);
    defer save_buf.deinit();

    const written_meta = try write_save_state(
        testing.allocator,
        save_buf.writer(),
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
    var inspect_stream = std.io.fixedBufferStream(save_buf.items);
    const inspected = try inspect_save_stream(testing.allocator, inspect_stream.reader());
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
    var restore_stream = std.io.fixedBufferStream(save_buf.items);
    const restored_meta = try read_save_state(
        testing.allocator,
        restore_stream.reader(),
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

    var save_buf = std.ArrayList(u8).init(testing.allocator);
    defer save_buf.deinit();
    _ = try write_save_state(testing.allocator, save_buf.writer(), &world, null, null, .{});

    // 1. Corrupt payload byte -> ChecksumMismatch
    var corrupted = try testing.allocator.dupe(u8, save_buf.items);
    defer testing.allocator.free(corrupted);
    corrupted[corrupted.len - 1] ^= 0xFF;

    var s1 = std.io.fixedBufferStream(corrupted);
    try testing.expectError(SaveError.ChecksumMismatch, read_save_state(testing.allocator, s1.reader(), &world, null, null));

    // 2. Corrupt magic header -> InvalidSaveMagic
    var bad_magic = try testing.allocator.dupe(u8, save_buf.items);
    defer testing.allocator.free(bad_magic);
    bad_magic[0] = 'X';

    var s2 = std.io.fixedBufferStream(bad_magic);
    try testing.expectError(SaveError.InvalidSaveMagic, read_save_state(testing.allocator, s2.reader(), &world, null, null));

    // 3. Unsupported version -> UnsupportedSaveVersion
    var bad_ver = try testing.allocator.dupe(u8, save_buf.items);
    defer testing.allocator.free(bad_ver);
    bad_ver[4] = 99;

    var s3 = std.io.fixedBufferStream(bad_ver);
    try testing.expectError(SaveError.UnsupportedSaveVersion, read_save_state(testing.allocator, s3.reader(), &world, null, null));
}

test "P17-02: SaveManager numbered slots, quick-save/load, and corrupted save .bak recovery" {
    const testing = std.testing;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const base_path = try tmp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(base_path);

    var sm = try SaveManager.init(testing.allocator, base_path);
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
        const f = try std.fs.cwd().openFile(slot1_path, .{ .mode = .read_write });
        defer f.close();
        try f.seekTo(20);
        try f.writer().writeAll("CORRUPTED_BYTES!");
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
