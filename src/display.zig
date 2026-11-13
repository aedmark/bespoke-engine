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
const draft_mod = @import("draft.zig");
pub const DistaffInput = draft_mod.DistaffInput;
const dialogue_mod = @import("dialogue.zig");
const mml_mod = @import("mml.zig");
pub const WeaveOutcome = draft_mod.WeaveOutcome;

pub const font = @import("display/font.zig");
pub const text_layout = @import("display/text_layout.zig");
pub const TextLayoutResolver = text_layout.TextLayoutResolver;
pub const renderer = @import("display/renderer.zig");
pub const state_graph = @import("display/state_graph.zig");
pub const DisplayWindow = renderer.DisplayWindow;
pub const UserAction = renderer.UserAction;
pub const audio = @import("audio.zig");
pub const AudioBridge = audio.AudioBridge;
pub const SoundEffectKind = audio.SoundEffectKind;
pub const Sound = audio.Sound;
pub const Soundtrack = audio.Soundtrack;
pub const ChiptuneSynth = audio.ChiptuneSynth;

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

/// A read-only representation of a waypoint node for peripheral rendering (D-001, D-005, P6-02).
pub const RenderWaypoint = struct {
    id: WaypointId,
    room: EntityId,
    x: i32,
    y: i32,
    name: [32]u8,
    name_len: u8,

    pub fn get_name(self: *const RenderWaypoint) []const u8 {
        return self.name[0..self.name_len];
    }
};

/// A read-only representation of a corridor/edge between waypoints (D-001, D-005, P6-02).
pub const RenderEdge = struct {
    from: WaypointId,
    to: WaypointId,
};

/// A read-only representation of a scene hotspot / inspectable prop (P7-01, D-009).
pub const RenderHotspot = struct {
    entity: EntityId,
    room: EntityId,
    x: i32,
    y: i32,
    radius: u32,
    name: [32]u8,
    name_len: u8,
    examine_text: [128]u8,
    examine_len: u8,

    pub fn get_name(self: *const RenderHotspot) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn get_examine_text(self: *const RenderHotspot) []const u8 {
        return self.examine_text[0..self.examine_len];
    }
};

/// An external visual/audio cue emitted during a simulation tick (D-001).
pub const RenderCue = struct {
    cue_id: u16,
    args: [4]u32,
    arg_count: u8,
};

/// An inventory item held by the player (P7-03, D-007).
pub const RenderInventoryItem = struct {
    entity: EntityId,
    name: [32]u8,
    name_len: u8,

    pub fn get_name(self: *const RenderInventoryItem) []const u8 {
        return self.name[0..self.name_len];
    }
};

/// A party member in a multi-protagonist scenario (P21-01, D-025).
pub const MAX_PARTY_MEMBERS = 4;
/// Facts copied into each frame for the inspectors (D-058; was 32).
pub const MAX_DEBUG_FACTS = 128;

/// Relations the engine itself fills with numbers, never entity ids, whatever the number
/// happens to equal (D-058).
const VALUE_RELATIONS = [_][]const u8{
    "CellFlammable",  "CellLiquid",          "CellBlocking",         "CellBurning",
    "CellSmoke",      "Volume",              "DialogueOpen",         "DialogueFiber",
    "DialogueEnd",    "DialogueRevision",    "DialogueBody",         "DialogueAction",
    "DialogueChosen", "DialogueBranchCount", "DialogueBranchActive",
};

/// Copies the World's facts for the inspectors (P9-01, D-011, D-058): live facts first, then the
/// ones that expired this tick, up to `out.len`. Returns the count. The browser runtime calls this
/// too, so both inspectors read the same capture (P30-04, D-070).
pub fn capture_debug_facts(world: *const World, out: []RenderDebugFact) usize {
    var count: usize = 0;
    const slice = world.facts.slice();
    for (0..world.facts.len) |fi| {
        if (count == out.len) break;
        out[count] = debug_fact(world, slice.get(fi), false);
        count += 1;
    }
    for (world.get_recently_expired()) |fact| {
        if (count == out.len) break;
        out[count] = debug_fact(world, fact, true);
        count += 1;
    }
    return count;
}

fn debug_fact(world: *const World, fact: world_mod.Fact, expired: bool) RenderDebugFact {
    var df = RenderDebugFact{
        .subject_name = undefined,
        .subject_len = 0,
        .relation_name = undefined,
        .relation_len = 0,
        .object_name = undefined,
        .object_len = 0,
        .expires_at_tick = fact.expires_at_tick,
        .subject = fact.subject,
        .object_raw = fact.object_or_value,
        .recently_expired = expired,
    };
    if (world.get_entity_name(fact.subject)) |sn| {
        const len = @min(sn.len, df.subject_name.len);
        @memcpy(df.subject_name[0..len], sn[0..len]);
        df.subject_len = @intCast(len);
    }
    var value_relation = false;
    if (world.get_relation_meta(fact.relation)) |rm| {
        const len = @min(rm.name.len, df.relation_name.len);
        @memcpy(df.relation_name[0..len], rm.name[0..len]);
        df.relation_len = @intCast(len);
        for (VALUE_RELATIONS) |v| if (std.mem.eql(u8, v, rm.name)) {
            value_relation = true;
        };
    }
    const object_name = if (value_relation or fact.object_or_value == 0) null else world.get_entity_name(EntityId.from_int(fact.object_or_value));
    if (object_name) |on| {
        const len = @min(on.len, df.object_name.len);
        @memcpy(df.object_name[0..len], on[0..len]);
        df.object_len = @intCast(len);
        df.object_is_entity = true;
    } else {
        var num_buf: [16]u8 = undefined;
        const formatted = std.fmt.bufPrint(&num_buf, "{d}", .{fact.object_or_value}) catch "?";
        const len = @min(formatted.len, df.object_name.len);
        @memcpy(df.object_name[0..len], formatted[0..len]);
        df.object_len = @intCast(len);
    }
    return df;
}
pub const RenderPartyMember = struct {
    entity: EntityId,
    name: [32]u8 = undefined,
    name_len: u8 = 0,
    is_active: bool = false,

    pub fn get_name(self: *const RenderPartyMember) []const u8 {
        return self.name[0..self.name_len];
    }
};

/// Debug information for an active relational fact (P9-01, D-011).
pub const RenderDebugFact = struct {
    subject_name: [24]u8,
    subject_len: u8,
    relation_name: [24]u8,
    relation_len: u8,
    object_name: [24]u8,
    object_len: u8,
    expires_at_tick: u64,
    /// State inspector fields (P27-01, D-058).
    subject: EntityId = .none,
    object_raw: u32 = 0,
    /// The object names an entity, so the inspector draws the fact as an edge.
    object_is_entity: bool = false,
    /// Copied from `World.recently_expired`: gone this tick, drawn grey.
    recently_expired: bool = false,

    pub fn get_subject(self: *const RenderDebugFact) []const u8 {
        return self.subject_name[0..self.subject_len];
    }
    pub fn get_relation(self: *const RenderDebugFact) []const u8 {
        return self.relation_name[0..self.relation_len];
    }
    pub fn get_object(self: *const RenderDebugFact) []const u8 {
        return self.object_name[0..self.object_len];
    }
};

/// Debug information for an active fiber and its call/interrupt stack (P9-01, D-011).
pub const RenderDebugFiber = struct {
    id: u32,
    owner_name: [24]u8,
    owner_len: u8,
    pc: usize,
    sp: usize,
    interrupt_depth: usize,
    priority: u16,
    state_name: [24]u8,
    state_len: u8,

    pub fn get_owner(self: *const RenderDebugFiber) []const u8 {
        return self.owner_name[0..self.owner_len];
    }
    pub fn get_state(self: *const RenderDebugFiber) []const u8 {
        return self.state_name[0..self.state_len];
    }
};

/// Pre-cognitive Fourth-Dimensional vector conduit render slice (P31-02, D-027).
pub const RenderVectorConduit = struct {
    entity: EntityId = EntityId.from_int(0),
    points_x: [16]i32 = [_]i32{0} ** 16,
    points_y: [16]i32 = [_]i32{0} ** 16,
    point_count: usize = 0,
    terminal_wp: WaypointId = 0,
    color_r: u8 = 100,
    color_g: u8 = 200,
    color_b: u8 = 255,
    alpha: u8 = 160,
};

/// Distaff staff HUD snapshot (P22-02, D-029). Copied by value from the host's `DistaffInput`
/// so the renderer never reads input state the host is mutating. Zeroed frames are disabled.
pub const RenderDistaff = struct {
    enabled: bool = false,
    played: [draft_mod.DRAFT_LEN]u8 = [_]u8{0} ** draft_mod.DRAFT_LEN,
    played_len: u8 = 0,
    reach: u8 = 0,
    outcome: WeaveOutcome = .none,
    target_name: [24]u8 = [_]u8{0} ** 24,
    target_len: u8 = 0,

    pub fn get_played(self: *const RenderDistaff) []const u8 {
        return self.played[0..self.played_len];
    }

    pub fn get_target(self: *const RenderDistaff) []const u8 {
        return self.target_name[0..self.target_len];
    }
};

/// One source-order branch of the open dialogue, including rejected choices (P27-02, D-058).
pub const RenderDialogueBranch = struct {
    active: bool = false,
    text: [80]u8 = undefined,
    text_len: u8 = 0,
    failure: [96]u8 = undefined,
    failure_len: u8 = 0,

    pub fn get_text(self: *const RenderDialogueBranch) []const u8 {
        return self.text[0..self.text_len];
    }

    pub fn get_failure(self: *const RenderDialogueBranch) []const u8 {
        return self.failure[0..self.failure_len];
    }
};

/// A read-only snapshot of the open dialogue set (P32-30, D-046). The engine owns the facts;
/// the host renders this channel. `revision` changes when a new set opens.
pub const RenderDialogue = struct {
    active: bool = false,
    revision: u32 = 0,
    speaker: EntityId = EntityId.from_int(0),
    x: i32 = 0,
    y: i32 = 0,
    speaker_name: [32]u8 = undefined,
    speaker_name_len: u8 = 0,
    prompt: [160]u8 = undefined,
    prompt_len: u8 = 0,
    choices: [dialogue_mod.MAX_CHOICES][80]u8 = undefined,
    choice_lens: [dialogue_mod.MAX_CHOICES]u8 = [_]u8{0} ** dialogue_mod.MAX_CHOICES,
    choice_count: u8 = 0,
    /// Source-order active and pruned branches for the paused inspector (P27-02, D-058).
    branches: [dialogue_mod.MAX_CHOICES]RenderDialogueBranch = [_]RenderDialogueBranch{.{}} ** dialogue_mod.MAX_CHOICES,
    branch_count: u8 = 0,

    pub fn get_speaker_name(self: *const RenderDialogue) []const u8 {
        return self.speaker_name[0..self.speaker_name_len];
    }

    pub fn get_prompt(self: *const RenderDialogue) []const u8 {
        return self.prompt[0..self.prompt_len];
    }

    pub fn get_choice(self: *const RenderDialogue, index: usize) []const u8 {
        if (index >= self.choice_count) return "";
        return self.choices[index][0..self.choice_lens[index]];
    }
};

/// A double-buffered render state slice captured at a discrete simulation tick (D-001, P5-01, P6-02).
pub const RenderFrame = struct {
    tick: u64,
    entities: [64]RenderEntity,
    entity_count: usize,
    waypoints: [32]RenderWaypoint,
    waypoint_count: usize,
    edges: [64]RenderEdge,
    edge_count: usize,
    hotspots: [16]RenderHotspot,
    hotspot_count: usize,
    inventory: [8]RenderInventoryItem,
    inventory_count: usize,
    cues: [16]RenderCue,
    cue_count: usize,
    fact_count: usize,
    vector_conduits: [4]RenderVectorConduit = [_]RenderVectorConduit{.{}} ** 4,
    vector_conduit_count: usize = 0,
    // Multi-character party coordination state (P21-01, D-025)
    party: [MAX_PARTY_MEMBERS]RenderPartyMember = [_]RenderPartyMember{.{ .entity = EntityId.from_int(0) }} ** MAX_PARTY_MEMBERS,
    party_count: usize = 0,
    active_party_index: usize = 0,
    // Distaff staff HUD for musical drafts (P22-02, D-029)
    distaff: RenderDistaff = .{},
    // Executable dialogue channel (P32-30, D-046)
    dialogue: RenderDialogue = .{},
    debug_facts: [MAX_DEBUG_FACTS]RenderDebugFact,
    debug_fact_count: usize,
    debug_fibers: [8]RenderDebugFiber,
    debug_fiber_count: usize,
    current_scene: [32]u8 = undefined,
    current_scene_len: u8 = 0,
    /// The script score that should play (P28-03, D-062): the `play score` override, else the
    /// current scene's `SceneScore`; empty when neither names one.
    current_score: [32]u8 = undefined,
    current_score_len: u8 = 0,
    max_history_tick: u64,
    /// The host's own status for its presentation (P32-03b, D-041): bytes the engine never
    /// reads, filled by the bridge's status hook and read back typed with `host_status`.
    host_status_bytes: [HOST_STATUS_BYTES]u8 align(8) = [_]u8{0} ** HOST_STATUS_BYTES,

    /// The host status block as the host's own type. `T` must fit the block and must be valid
    /// when every byte is zero, which is how the block starts.
    pub fn host_status(self: *const RenderFrame, comptime T: type) *const T {
        comptime check_host_status(T);
        return @ptrCast(@alignCast(&self.host_status_bytes));
    }

    pub fn host_status_mut(self: *RenderFrame, comptime T: type) *T {
        comptime check_host_status(T);
        return @ptrCast(@alignCast(&self.host_status_bytes));
    }

    pub fn get_current_scene(self: *const RenderFrame) []const u8 {
        return self.current_scene[0..self.current_scene_len];
    }

    pub fn get_current_score(self: *const RenderFrame) []const u8 {
        return self.current_score[0..self.current_score_len];
    }
};

/// Size of `RenderFrame.host_status_bytes`.
pub const HOST_STATUS_BYTES: usize = 2048;

fn check_host_status(comptime T: type) void {
    if (@sizeOf(T) > HOST_STATUS_BYTES) @compileError("host status type is larger than HOST_STATUS_BYTES");
    if (@alignOf(T) > 8) @compileError("host status type needs more than 8-byte alignment");
}

/// Fills the host's status block from the world after the engine has captured a frame; the
/// frame's entities, scene, and other engine fields are already set. Must only read the world.
pub const StatusHook = *const fn (world: *const World, frame: *RenderFrame) void;

fn capture_distaff(world: *const World, maybe_input: ?*const DistaffInput) RenderDistaff {
    const input = maybe_input orelse return .{};
    var out = RenderDistaff{
        .enabled = true,
        .played_len = input.len,
        .reach = input.reach,
        .outcome = input.outcome,
    };
    for (input.current(), 0..) |n, i| out.played[i] = @intFromEnum(n);
    if (input.target != .none) {
        if (world.get_entity_name(input.target)) |name| {
            const len = @min(name.len, out.target_name.len);
            @memcpy(out.target_name[0..len], name[0..len]);
            out.target_len = @intCast(len);
        }
    }
    return out;
}

/// Double-buffered display bridge separating simulation spine from peripheral consumers (D-001, P5-01).
/// Publishes the open dialogue set, if any, into the frame channel (P32-30, D-046). Reads only
/// World facts, so it is safe on a capture tick with no host involvement.
fn capture_dialogue(world: *const World, frame: *RenderFrame) void {
    frame.dialogue = .{};
    const open = dialogue_mod.view(world) orelse return;

    var speaker_name: []const u8 = world.get_entity_name(open.display_speaker) orelse "";
    var x: i32 = 0;
    var y: i32 = 0;
    for (frame.entities[0..frame.entity_count]) |entity| {
        if (entity.entity != open.display_speaker) continue;
        speaker_name = entity.get_name();
        x = entity.x;
        y = entity.y;
        break;
    }

    var out = &frame.dialogue;
    out.active = true;
    out.revision = open.revision;
    out.speaker = open.display_speaker;
    out.x = x;
    out.y = y;

    const nlen = @min(speaker_name.len, out.speaker_name.len);
    @memcpy(out.speaker_name[0..nlen], speaker_name[0..nlen]);
    out.speaker_name_len = @intCast(nlen);

    const plen = @min(open.prompt.len, out.prompt.len);
    @memcpy(out.prompt[0..plen], open.prompt[0..plen]);
    out.prompt_len = @intCast(plen);

    for (0..open.count) |i| {
        const text = open.text(i);
        const len = @min(text.len, out.choices[i].len);
        @memcpy(out.choices[i][0..len], text[0..len]);
        out.choice_lens[i] = @intCast(len);
    }
    out.choice_count = @intCast(open.count);

    for (0..open.branch_count) |i| {
        const branch = open.branch(i);
        out.branches[i].active = branch.active;
        const text_len = @min(branch.text.len, out.branches[i].text.len);
        @memcpy(out.branches[i].text[0..text_len], branch.text[0..text_len]);
        out.branches[i].text_len = @intCast(text_len);
        const failure_len = @min(branch.failure.len, out.branches[i].failure.len);
        @memcpy(out.branches[i].failure[0..failure_len], branch.failure[0..failure_len]);
        out.branches[i].failure_len = @intCast(failure_len);
    }
    out.branch_count = @intCast(open.branch_count);
}

/// The score a script wants now: the `PlayingScore` property of `Music` if set, else the
/// `SceneScore` of the current scene (P28-03, D-062). Null without script music.
pub fn current_score_entity(world: *const world_mod.World, scene: ?EntityId) ?EntityId {
    if (world.lookup_relation(mml_mod.PLAYING_RELATION)) |rel| {
        if (world.lookup_entity(mml_mod.MUSIC_ENTITY)) |music| {
            if (world.get_property(music, rel)) |raw| return EntityId.from_int(raw);
        }
    }
    const scene_id = scene orelse return null;
    const rel = world.lookup_relation(mml_mod.SCENE_RELATION) orelse return null;
    const fact = world.find_first(scene_id, rel, null) orelse return null;
    return EntityId.from_int(fact.object_or_value);
}

pub const DisplayBridge = struct {
    front_buffer: RenderFrame,
    back_buffer: RenderFrame,
    audio_bridge: ?*audio.AudioBridge = null,
    status_hook: ?StatusHook = null,
    distaff: ?*const DistaffInput = null,
    active_player_character: ?EntityId = null,
    active_party_index: ?usize = null,
    party: [MAX_PARTY_MEMBERS]EntityId = [_]EntityId{EntityId.from_int(0)} ** MAX_PARTY_MEMBERS,
    party_count: usize = 0,

    pub fn init() DisplayBridge {
        return DisplayBridge{
            .front_buffer = std.mem.zeroes(RenderFrame),
            .back_buffer = std.mem.zeroes(RenderFrame),
            .audio_bridge = null,
            .active_player_character = null,
            .active_party_index = null,
            .party = [_]EntityId{EntityId.from_int(0)} ** MAX_PARTY_MEMBERS,
            .party_count = 0,
        };
    }

    /// Registers party members for multi-protagonist party management (P21-01, D-025).
    pub fn set_party(self: *DisplayBridge, members: []const EntityId) void {
        const count = @min(members.len, self.party.len);
        for (0..count) |i| {
            self.party[i] = members[i];
        }
        self.party_count = count;
        if (count > 0 and self.active_player_character == null) {
            self.active_player_character = members[0];
            self.active_party_index = 0;
        }
    }

    /// Explicitly sets the active party member index (P21-01, D-025).
    pub fn set_active_party_index(self: *DisplayBridge, idx: usize) void {
        self.active_party_index = idx;
    }

    /// Sets the active player-controlled protagonist in the party (P21-01, D-025).
    pub fn set_active_character(self: *DisplayBridge, id: EntityId) void {
        self.active_player_character = id;
        for (self.party[0..self.party_count], 0..) |pid, idx| {
            if (pid == id) {
                self.active_party_index = idx;
                break;
            }
        }
    }

    /// Attaches an optional peripheral audio bridge to consume cues (P16-01, D-001).
    pub fn attach_audio_bridge(self: *DisplayBridge, ab: *audio.AudioBridge) void {
        self.audio_bridge = ab;
    }

    /// Attaches the host's distaff phrase buffer so frames carry the staff HUD (P22-02, D-029).
    pub fn attach_distaff(self: *DisplayBridge, input: *const DistaffInput) void {
        self.distaff = input;
    }

    /// Sets the maximum simulation tick reached in recorded history for the timeline scrubber (P9-02, D-011).
    pub fn set_max_history_tick(self: *DisplayBridge, max_tick: u64) void {
        self.back_buffer.max_history_tick = max_tick;
        self.front_buffer.max_history_tick = max_tick;
    }

    /// Registers the host's status capture, called at the end of every `capture_frame`
    /// (P32-03b, D-041). The block is not cleared between frames, so status a host sets
    /// directly on `back_buffer` persists until the hook or the host changes it.
    pub fn set_status_hook(self: *DisplayBridge, hook: ?StatusHook) void {
        self.status_hook = hook;
    }

    /// Explicitly registers a pre-cognitive vector conduit into the back buffer (P31-02, D-027).
    pub fn add_vector_conduit(self: *DisplayBridge, conduit: spatial_mod.VectorConduit) void {
        if (self.back_buffer.vector_conduit_count >= self.back_buffer.vector_conduits.len) return;
        var rc = &self.back_buffer.vector_conduits[self.back_buffer.vector_conduit_count];
        rc.entity = conduit.entity;
        rc.terminal_wp = conduit.terminal_waypoint;
        rc.point_count = @min(conduit.point_count, 16);
        for (0..rc.point_count) |i| {
            rc.points_x[i] = conduit.points[i].x;
            rc.points_y[i] = conduit.points[i].y;
        }
        self.back_buffer.vector_conduit_count += 1;
    }

    /// Captures a read-only snapshot of simulation state into the back buffer (D-001, P6-02).
    pub fn capture_frame(
        self: *DisplayBridge,
        world: *const World,
        spatial: *const SpatialSystem,
        vm: *const VM,
    ) void {
        const prev_max_history = self.back_buffer.max_history_tick;
        self.back_buffer.tick = world.current_tick;
        self.back_buffer.fact_count = world.fact_count();
        const active_scene_id = vm.current_scene;

        // 1. Capture entities and positions (scoped to active scene if set)
        var e_count: usize = 0;
        var it = spatial.agents.iterator();
        while (it.next()) |entry| {
            if (e_count >= self.back_buffer.entities.len) break;
            const agent = entry.value_ptr;

            if (active_scene_id) |cur_sc| {
                if (spatial.graph.get_waypoint(agent.current_wp)) |wp| {
                    if (wp.room != cur_sc) continue;
                }
            }

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
        capture_dialogue(world, &self.back_buffer);

        // 2. Capture spatial waypoints (scoped to active scene if set)
        var wp_count: usize = 0;
        for (spatial.graph.waypoints.items) |wp| {
            if (wp_count >= self.back_buffer.waypoints.len) break;
            if (active_scene_id) |cur_sc| {
                if (wp.room != cur_sc) continue;
            }

            var rw = RenderWaypoint{
                .id = wp.id,
                .room = wp.room,
                .x = wp.pos.x,
                .y = wp.pos.y,
                .name = undefined,
                .name_len = 0,
            };
            const len = @min(wp.name.len, rw.name.len);
            @memcpy(rw.name[0..len], wp.name[0..len]);
            rw.name_len = @intCast(len);
            self.back_buffer.waypoints[wp_count] = rw;
            wp_count += 1;
        }
        self.back_buffer.waypoint_count = wp_count;

        // 3. Capture spatial edges (scoped to active scene if set)
        var edge_count: usize = 0;
        for (spatial.graph.edges.items) |e| {
            if (edge_count >= self.back_buffer.edges.len) break;
            if (active_scene_id) |cur_sc| {
                const wp_a = spatial.graph.get_waypoint(e.from);
                const wp_b = spatial.graph.get_waypoint(e.to);
                if (wp_a == null or wp_b == null or wp_a.?.room != cur_sc or wp_b.?.room != cur_sc) {
                    continue;
                }
            }

            self.back_buffer.edges[edge_count] = .{
                .from = e.from,
                .to = e.to,
            };
            edge_count += 1;
        }
        self.back_buffer.edge_count = edge_count;

        // 4. Capture spatial hotspots (scoped to active scene if set)
        var hs_count: usize = 0;
        for (spatial.hotspots.items) |hs| {
            if (hs_count >= self.back_buffer.hotspots.len) break;
            if (active_scene_id) |cur_sc| {
                if (hs.room != cur_sc) continue;
            }

            var rh = RenderHotspot{
                .entity = hs.entity,
                .room = hs.room,
                .x = hs.pos.x,
                .y = hs.pos.y,
                .radius = hs.radius,
                .name = undefined,
                .name_len = 0,
                .examine_text = undefined,
                .examine_len = 0,
            };
            const n_len = @min(hs.name.len, rh.name.len);
            @memcpy(rh.name[0..n_len], hs.name[0..n_len]);
            rh.name_len = @intCast(n_len);

            const e_len = @min(hs.examine_text.len, rh.examine_text.len);
            @memcpy(rh.examine_text[0..e_len], hs.examine_text[0..e_len]);
            rh.examine_len = @intCast(e_len);

            self.back_buffer.hotspots[hs_count] = rh;
            hs_count += 1;
        }
        self.back_buffer.hotspot_count = hs_count;

        // 5. Capture emitted cues
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

        // 5e. Capture party coordination state (P21-01, D-025)
        var p_count: usize = 0;
        var active_p_idx: usize = 0;
        for (self.party[0..self.party_count], 0..) |pid, idx| {
            if (p_count >= self.back_buffer.party.len) break;
            const is_act = if (self.active_party_index) |api|
                (idx == api)
            else
                ((self.active_player_character != null and self.active_player_character.? == pid) or (self.active_player_character == null and idx == 0));
            var member = RenderPartyMember{
                .entity = pid,
                .name = undefined,
                .name_len = 0,
                .is_active = is_act,
            };
            if (is_act) {
                active_p_idx = idx;
            }
            if (world.get_entity_name(pid)) |n| {
                const len = @min(n.len, member.name.len);
                @memcpy(member.name[0..len], n[0..len]);
                member.name_len = @intCast(len);
            }
            self.back_buffer.party[p_count] = member;
            p_count += 1;
        }
        self.back_buffer.party_count = p_count;
        self.back_buffer.active_party_index = active_p_idx;

        // Capture active pre-cognitive vector conduits from moving or designated actors (P31-02, D-027)
        self.back_buffer.vector_conduit_count = 0;
        if (spatial.agents.count() > 0) {
            var it_agents = spatial.agents.iterator();
            while (it_agents.next()) |entry| {
                if (self.back_buffer.vector_conduit_count >= self.back_buffer.vector_conduits.len) break;
                if (spatial.get_agent_vector_conduit(entry.key_ptr.*)) |conduit| {
                    var rc = &self.back_buffer.vector_conduits[self.back_buffer.vector_conduit_count];
                    rc.entity = conduit.entity;
                    rc.terminal_wp = conduit.terminal_waypoint;
                    rc.point_count = @min(conduit.point_count, 16);
                    for (0..rc.point_count) |ci| {
                        rc.points_x[ci] = conduit.points[ci].x;
                        rc.points_y[ci] = conduit.points[ci].y;
                    }
                    self.back_buffer.vector_conduit_count += 1;
                }
            }
        }

        // 6. Capture player inventory (P7-03, D-007, D-025)
        var inv_count: usize = 0;
        // The host names its player (`set_party` or `set_active_character`); the engine no
        // longer guesses one from a list of proof characters (P32-03b).
        const player_id = self.active_player_character;
        if (player_id) |pid| {
            if (world.lookup_relation("InInventory")) |inv_rel| {
                var it_inv = world.query(pid, inv_rel, null);
                while (it_inv.next()) |f| {
                    if (inv_count >= self.back_buffer.inventory.len) break;
                    var item = RenderInventoryItem{
                        .entity = EntityId.from_int(f.object_or_value),
                        .name = undefined,
                        .name_len = 0,
                    };
                    if (world.get_entity_name(item.entity)) |n| {
                        const len = @min(n.len, item.name.len);
                        @memcpy(item.name[0..len], n[0..len]);
                        item.name_len = @intCast(len);
                    }
                    self.back_buffer.inventory[inv_count] = item;
                    inv_count += 1;
                }
            }
            if (world.lookup_relation("Carries")) |carries_rel| {
                var it_carr = world.query(pid, carries_rel, null);
                while (it_carr.next()) |f| {
                    if (inv_count >= self.back_buffer.inventory.len) break;
                    var item = RenderInventoryItem{
                        .entity = EntityId.from_int(f.object_or_value),
                        .name = undefined,
                        .name_len = 0,
                    };
                    if (world.get_entity_name(item.entity)) |n| {
                        const len = @min(n.len, item.name.len);
                        @memcpy(item.name[0..len], n[0..len]);
                        item.name_len = @intCast(len);
                    }
                    self.back_buffer.inventory[inv_count] = item;
                    inv_count += 1;
                }
            }
        }
        self.back_buffer.inventory_count = inv_count;

        // 7. Capture relational facts for the inspectors (P9-01, D-011, D-058): live facts first,
        // then the ones that expired this tick, up to MAX_DEBUG_FACTS.
        self.back_buffer.debug_fact_count = capture_debug_facts(world, &self.back_buffer.debug_facts);

        // 8. Capture active fibers for debug inspector (P9-01, D-011)
        var fib_count: usize = 0;
        for (vm.fibers.items) |f| {
            if (fib_count >= self.back_buffer.debug_fibers.len) break;
            var dfib = RenderDebugFiber{
                .id = f.id,
                .owner_name = undefined,
                .owner_len = 0,
                .pc = f.pc,
                .sp = f.sp,
                .interrupt_depth = f.interrupt_stack.items.len,
                .priority = f.active_priority,
                .state_name = undefined,
                .state_len = 0,
            };

            if (world.get_entity_name(f.owner)) |on| {
                const len = @min(on.len, dfib.owner_name.len);
                @memcpy(dfib.owner_name[0..len], on[0..len]);
                dfib.owner_len = @intCast(len);
            }

            const s_tag = std.meta.activeTag(f.state);
            const s_str = @tagName(s_tag);
            const slen = @min(s_str.len, dfib.state_name.len);
            @memcpy(dfib.state_name[0..slen], s_str[0..slen]);
            dfib.state_len = @intCast(slen);

            self.back_buffer.debug_fibers[fib_count] = dfib;
            fib_count += 1;
        }
        self.back_buffer.debug_fiber_count = fib_count;

        // 8. Capture active scene (P12-03, D-014)
        if (vm.current_scene) |scene_id| {
            if (world.get_entity_name(scene_id)) |sname| {
                const len = @min(sname.len, self.back_buffer.current_scene.len);
                @memcpy(self.back_buffer.current_scene[0..len], sname[0..len]);
                self.back_buffer.current_scene_len = @intCast(len);
            } else {
                self.back_buffer.current_scene_len = 0;
            }
        } else {
            self.back_buffer.current_scene_len = 0;
        }

        // 8a. Choose script music from World facts alone (P28-03, D-062), so a restored save
        // or rewind brings its music back without the compiled program.
        self.back_buffer.current_score_len = 0;
        if (current_score_entity(world, vm.current_scene)) |score_id| {
            if (world.get_entity_name(score_id)) |name| {
                const len = @min(name.len, self.back_buffer.current_score.len);
                @memcpy(self.back_buffer.current_score[0..len], name[0..len]);
                self.back_buffer.current_score_len = @intCast(len);
            }
        }

        self.back_buffer.max_history_tick = prev_max_history;

        // 8b. Capture distaff staff HUD (P22-02, D-029)
        self.back_buffer.distaff = capture_distaff(world, self.distaff);

        // 8c. The host's own status, after every engine field is set (P32-03b, D-041)
        if (self.status_hook) |hook| hook(world, &self.back_buffer);

        // 9. Forward scene and cues to attached audio bridge (P16-01, P16-03, D-019)
        if (self.audio_bridge) |ab| {
            ab.process_scene_and_cues(self.back_buffer.get_current_scene(), self.back_buffer.get_current_score());
        }
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
    try testing.expectEqual(@as(usize, 1), frame.waypoint_count);
    try testing.expectEqualStrings("Hearth", frame.waypoints[0].get_name());
}

test "P12-03: DisplayBridge.capture_frame scopes waypoints, hotspots, and entities to active scene" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();

    const room_a = try world.intern_entity("RoomA");
    const room_b = try world.intern_entity("RoomB");

    const wp_a = try spatial.graph.add_waypoint(room_a, 0, 0, "WP_A");
    const wp_b = try spatial.graph.add_waypoint(room_b, 10, 0, "WP_B");

    const prop_a = try world.intern_entity("PropA");
    const prop_b = try world.intern_entity("PropB");
    try spatial.add_hotspot(prop_a, room_a, .{ .x = 0, .y = -5 }, 5, "PropA", "Prop in Room A");
    try spatial.add_hotspot(prop_b, room_b, .{ .x = 10, .y = -5 }, 5, "PropB", "Prop in Room B");

    const actor_a = try world.intern_entity("ActorA");
    const actor_b = try world.intern_entity("ActorB");
    try spatial.register_entity(actor_a, wp_a, 5);
    try spatial.register_entity(actor_b, wp_b, 5);

    var chunk = vm_mod.BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();

    var vm = VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();

    var bridge = DisplayBridge.init();

    // 1. Scoped to RoomA
    vm.current_scene = room_a;
    bridge.capture_frame(&world, &spatial, &vm);
    bridge.swap();
    const frame_a = bridge.get_frame();
    try testing.expectEqual(@as(usize, 1), frame_a.waypoint_count);
    try testing.expectEqualStrings("WP_A", frame_a.waypoints[0].get_name());
    try testing.expectEqual(@as(usize, 1), frame_a.hotspot_count);
    try testing.expectEqualStrings("PropA", frame_a.hotspots[0].get_name());
    try testing.expectEqual(@as(usize, 1), frame_a.entity_count);
    try testing.expectEqualStrings("ActorA", frame_a.entities[0].get_name());

    // 2. Scoped to RoomB
    vm.current_scene = room_b;
    bridge.capture_frame(&world, &spatial, &vm);
    bridge.swap();
    const frame_b = bridge.get_frame();
    try testing.expectEqual(@as(usize, 1), frame_b.waypoint_count);
    try testing.expectEqualStrings("WP_B", frame_b.waypoints[0].get_name());
    try testing.expectEqual(@as(usize, 1), frame_b.hotspot_count);
    try testing.expectEqualStrings("PropB", frame_b.hotspots[0].get_name());
    try testing.expectEqual(@as(usize, 1), frame_b.entity_count);
    try testing.expectEqualStrings("ActorB", frame_b.entities[0].get_name());

    // 3. Unscoped (vm.current_scene == null, e.g. Tavern Heist overview)
    vm.current_scene = null;
    bridge.capture_frame(&world, &spatial, &vm);
    bridge.swap();
    const frame_all = bridge.get_frame();
    try testing.expectEqual(@as(usize, 2), frame_all.waypoint_count);
    try testing.expectEqual(@as(usize, 2), frame_all.hotspot_count);
    try testing.expectEqual(@as(usize, 2), frame_all.entity_count);
}

test "P16-01: DisplayBridge attaches AudioBridge and forwards scene context" {
    const testing = std.testing;
    var db = DisplayBridge.init();
    var ab = audio.AudioBridge.init();
    db.attach_audio_bridge(&ab);

    try testing.expect(db.audio_bridge != null);
    try testing.expectEqual(@as(*audio.AudioBridge, &ab), db.audio_bridge.?);
}

test "P21-01: DisplayBridge captures multi-character party state and active inventory" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();

    const room = try world.intern_entity("ColonialWorkshop");
    const wp = try spatial.graph.add_waypoint(room, 0, 0, "WP1");

    const hoagie = try world.intern_entity("Hoagie");
    const bernard = try world.intern_entity("Bernard");
    const laverne = try world.intern_entity("Laverne");
    const battery = try world.intern_entity("SuperBattery");
    const flyer = try world.intern_entity("TentacleFlyer");

    try spatial.register_entity(hoagie, wp, 4);
    try spatial.register_entity(bernard, wp, 4);
    try spatial.register_entity(laverne, wp, 4);

    const carries = try world.intern_relation("Carries", .set);
    _ = try world.remember(hoagie, carries, battery.to_int(), 0);
    _ = try world.remember(bernard, carries, flyer.to_int(), 0);

    var chunk = vm_mod.BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();

    var vm = VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();

    var bridge = DisplayBridge.init();
    const party_members = [_]EntityId{ hoagie, bernard, laverne };
    bridge.set_party(&party_members);
    bridge.set_active_character(hoagie);

    bridge.capture_frame(&world, &spatial, &vm);
    bridge.swap();

    const frame1 = bridge.get_frame();
    try testing.expectEqual(@as(usize, 3), frame1.party_count);
    try testing.expectEqual(@as(usize, 0), frame1.active_party_index);
    try testing.expectEqualStrings("Hoagie", frame1.party[0].get_name());
    try testing.expect(frame1.party[0].is_active);
    try testing.expectEqualStrings("Bernard", frame1.party[1].get_name());
    try testing.expect(!frame1.party[1].is_active);
    try testing.expectEqualStrings("Laverne", frame1.party[2].get_name());
    try testing.expect(!frame1.party[2].is_active);

    // Hoagie has SuperBattery in inventory
    try testing.expectEqual(@as(usize, 1), frame1.inventory_count);
    try testing.expectEqualStrings("SuperBattery", frame1.inventory[0].get_name());

    // Switch active protagonist to Bernard
    bridge.set_active_character(bernard);
    bridge.capture_frame(&world, &spatial, &vm);
    bridge.swap();

    const frame2 = bridge.get_frame();
    try testing.expectEqual(@as(usize, 1), frame2.active_party_index);
    try testing.expect(!frame2.party[0].is_active);
    try testing.expect(frame2.party[1].is_active);

    // Bernard has TentacleFlyer in inventory
    try testing.expectEqual(@as(usize, 1), frame2.inventory_count);
    try testing.expectEqualStrings("TentacleFlyer", frame2.inventory[0].get_name());
}

test {
    _ = renderer;
    _ = font;
}

test "P22-02: DisplayBridge copies the attached distaff phrase into frames" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    const bytecode_mod = @import("bytecode.zig");
    var chunk = bytecode_mod.BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();
    var vm = VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();

    var db = DisplayBridge.init();
    db.capture_frame(&world, &spatial, &vm);
    db.swap();
    try testing.expect(!db.get_frame().distaff.enabled);

    var input = DistaffInput{};
    input.set_reach(4);
    _ = input.press(.C);
    _ = input.press(.F);
    db.attach_distaff(&input);
    db.capture_frame(&world, &spatial, &vm);
    db.swap();
    const d = db.get_frame().distaff;
    try testing.expect(d.enabled);
    try testing.expectEqual(@as(u8, 4), d.reach);
    try testing.expectEqualSlices(u8, &[_]u8{ 0, 3 }, d.get_played());

    // Later input changes do not leak into an already captured frame.
    _ = input.press(.D);
    try testing.expectEqual(@as(usize, 2), db.get_frame().distaff.get_played().len);
}
