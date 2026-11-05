const std = @import("std");
const world_mod = @import("world.zig");
const spatial_mod = @import("spatial.zig");
const vm_mod = @import("vm.zig");

pub const World = world_mod.World;
pub const EntityId = world_mod.EntityId;
pub const SpatialSystem = spatial_mod.SpatialSystem;
pub const WaypointId = spatial_mod.WaypointId;
pub const VM = vm_mod.VM;
pub const EmittedCue = vm_mod.EmittedCue;

/// A lightweight, read-only representation of an entity for display peripherals (D-001, P5-01).
pub const RenderEntity = struct {
    entity: EntityId,
    name: [32]u8,
    name_len: u8,
    x: i32,
    y: i32,
    current_wp: WaypointId,
    is_moving: bool,

    pub fn get_name(self: *const RenderEntity) []const u8 {
        return self.name[0..self.name_len];
    }
};

/// An external visual/audio cue emitted during a simulation tick (D-001).
pub const RenderCue = struct {
    cue_id: u16,
    args: [4]u32,
    arg_count: u8,
};

/// A double-buffered render state slice captured at a discrete simulation tick (D-001, P5-01).
pub const RenderFrame = struct {
    tick: u64,
    entities: [64]RenderEntity,
    entity_count: usize,
    cues: [16]RenderCue,
    cue_count: usize,
    fact_count: usize,
};

/// Double-buffered display bridge separating simulation spine from peripheral consumers (D-001, P5-01).
pub const DisplayBridge = struct {
    front_buffer: RenderFrame,
    back_buffer: RenderFrame,

    pub fn init() DisplayBridge {
        return DisplayBridge{
            .front_buffer = std.mem.zeroes(RenderFrame),
            .back_buffer = std.mem.zeroes(RenderFrame),
        };
    }

    /// Captures a read-only snapshot of simulation state into the back buffer (D-001).
    pub fn capture_frame(
        self: *DisplayBridge,
        world: *const World,
        spatial: *const SpatialSystem,
        vm: *const VM,
    ) void {
        self.back_buffer.tick = world.current_tick;
        self.back_buffer.fact_count = world.fact_count();

        // 1. Capture entities and positions
        var e_count: usize = 0;
        var it = spatial.agents.iterator();
        while (it.next()) |entry| {
            if (e_count >= self.back_buffer.entities.len) break;
            const agent = entry.value_ptr;
            var re = RenderEntity{
                .entity = agent.entity,
                .name = undefined,
                .name_len = 0,
                .x = agent.pos.x,
                .y = agent.pos.y,
                .current_wp = agent.current_wp,
                .is_moving = agent.is_moving,
            };
            if (world.get_entity_name(agent.entity)) |n| {
                const len = @min(n.len, re.name.len);
                @memcpy(re.name[0..len], n[0..len]);
                re.name_len = @intCast(len);
            }
            self.back_buffer.entities[e_count] = re;
            e_count += 1;
        }
        self.back_buffer.entity_count = e_count;

        // 2. Capture emitted cues
        var c_count: usize = 0;
        for (vm.emitted_cues.items) |cue| {
            if (c_count >= self.back_buffer.cues.len) break;
            self.back_buffer.cues[c_count] = .{
                .cue_id = cue.cue_id,
                .args = cue.args,
                .arg_count = cue.arg_count,
            };
            c_count += 1;
        }
        self.back_buffer.cue_count = c_count;
    }

    /// Swaps front and back buffers so display consumer reads the latest completed tick (D-001).
    pub fn swap(self: *DisplayBridge) void {
        const temp = self.front_buffer;
        self.front_buffer = self.back_buffer;
        self.back_buffer = temp;
    }

    /// Gets read-only reference to current display frame.
    pub fn get_frame(self: *const DisplayBridge) *const RenderFrame {
        return &self.front_buffer;
    }

    /// Built-in text/terminal renderer displaying tavern waypoints and actor positions (P5-01).
    pub fn render_terminal(self: *const DisplayBridge, writer: anytype) !void {
        const f = &self.front_buffer;
        try writer.print("+-------------------------------------------------------------------+\n", .{});
        try writer.print("| [Tick {d:03}] Active Facts: {d:<3}                                           |\n", .{ f.tick, f.fact_count });
        try writer.print("+-------------------------------------------------------------------+\n", .{});
        try writer.print("| Hearth (0,0)  <===========>  Bar (20,0)  <===========>  Cellar (40,0) |\n", .{});
        try writer.print("|                                                                   |\n", .{});

        for (f.entities[0..f.entity_count]) |e| {
            const name = e.get_name();
            const status = if (e.is_moving) "in transit" else "at waypoint";
            try writer.print("| Actor: {s:<10} Pos: ({d:>2}, {d:>2}) | Status: {s:<14}            |\n", .{
                name,
                e.x,
                e.y,
                status,
            });
        }

        if (f.cue_count > 0) {
            try writer.print("| Cues Emitted: {d} cue event(s)                                      |\n", .{f.cue_count});
        }
        try writer.print("+-------------------------------------------------------------------+\n", .{});
    }
};

test "P5-01: display bridge captures double-buffered render frames" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();

    const tavern = EntityId.from_int(1);
    const guard = try world.intern_entity("Guard");
    const wp1 = try spatial.graph.add_waypoint(tavern, 0, 0, "Hearth");
    try spatial.register_entity(guard, wp1, 5);

    var chunk = vm_mod.BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();

    var vm = VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();

    var bridge = DisplayBridge.init();

    // Capture initial frame
    bridge.capture_frame(&world, &spatial, &vm);
    bridge.swap();

    const frame = bridge.get_frame();
    try testing.expectEqual(@as(u64, 0), frame.tick);
    try testing.expectEqual(@as(usize, 1), frame.entity_count);
    try testing.expectEqualStrings("Guard", frame.entities[0].get_name());
    try testing.expectEqual(@as(i32, 0), frame.entities[0].x);
}
