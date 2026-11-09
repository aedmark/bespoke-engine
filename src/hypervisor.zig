const std = @import("std");
const world_mod = @import("world.zig");
const spatial_mod = @import("spatial.zig");
const World = world_mod.World;
const EntityId = world_mod.EntityId;
const RelationKind = world_mod.RelationKind;
const WaypointId = spatial_mod.WaypointId;
const SpatialSystem = spatial_mod.SpatialSystem;

/// Universe branch classification in the Roberta Sparrow temporal model (P31-01, D-027).
pub const UniverseBranchKind = enum {
    primary,
    tangent,
};

/// Lifecycle state of a Tangent Universe branch (P31-01, D-027).
pub const TangentCollapseState = enum {
    dormant,
    active,
    collapsed_singularity,
    resolved_and_merged,
};

/// Residual memory or emotional impression that survives Tangent Universe collapse (P31-01, D-027).
pub const DreamFact = struct {
    subject: EntityId,
    relation: RelationKind,
    object_or_value: u32,
};

/// Teleological prerequisite dependency edge for backward-chaining goal resolution (P31-01, D-027).
pub const TeleologicalDependency = struct {
    prerequisite_relation: RelationKind,
    target_goal_relation: RelationKind,
};

/// Outcome of advancing the temporal hypervisor by one discrete simulation tick (P31-01, D-027).
pub const HypervisorStepResult = enum {
    running,
    singularity_collapse,
    loop_resolved,
};

/// Temporal Hypervisor orchestrating Primary and Tangent Universe fact arenas (P31-01, D-027).
/// Manages ephemeral copy-on-write branching, collapse countdown budgets, teleological Horn clauses,
/// and dream-residue memory merges upon causal loop closure.
pub const TemporalHypervisor = struct {
    allocator: std.mem.Allocator,
    primary_world: *World,
    tangent_world: ?World,
    tangent_active: bool,

    living_receiver: ?EntityId,
    artifact_entity: ?EntityId,
    vortex_waypoint: ?WaypointId,

    collapse_budget_ticks: u64,
    ticks_elapsed: u64,
    collapse_state: TangentCollapseState,

    teleological_dependencies: std.ArrayList(TeleologicalDependency),
    dream_residue_facts: std.ArrayList(DreamFact),

    pub fn init(allocator: std.mem.Allocator, primary_world: *World) TemporalHypervisor {
        return TemporalHypervisor{
            .allocator = allocator,
            .primary_world = primary_world,
            .tangent_world = null,
            .tangent_active = false,
            .living_receiver = null,
            .artifact_entity = null,
            .vortex_waypoint = null,
            .collapse_budget_ticks = 0,
            .ticks_elapsed = 0,
            .collapse_state = .dormant,
            .teleological_dependencies = std.ArrayList(TeleologicalDependency).init(allocator),
            .dream_residue_facts = std.ArrayList(DreamFact).init(allocator),
        };
    }

    pub fn deinit(self: *TemporalHypervisor) void {
        if (self.tangent_world) |*tw| {
            tw.deinit();
            self.tangent_world = null;
        }
        self.teleological_dependencies.deinit();
        self.dream_residue_facts.deinit();
    }

    /// Forks the Primary Universe into an ephemeral Tangent Universe with a strict tick budget (P31-01, D-027).
    pub fn fork_tangent(
        self: *TemporalHypervisor,
        budget_ticks: u64,
        receiver: EntityId,
        artifact: EntityId,
    ) !*World {
        if (self.tangent_world) |*tw| {
            tw.deinit();
            self.tangent_world = null;
        }

        self.tangent_world = try self.primary_world.clone(self.allocator);
        self.tangent_active = true;
        self.collapse_budget_ticks = budget_ticks;
        self.ticks_elapsed = 0;
        self.living_receiver = receiver;
        self.artifact_entity = artifact;
        self.collapse_state = .active;

        return &self.tangent_world.?;
    }

    /// Sets the designated spatial vortex waypoint for Artifact ejection (P31-01, D-027).
    pub fn set_vortex_target(self: *TemporalHypervisor, waypoint: WaypointId) void {
        self.vortex_waypoint = waypoint;
    }

    /// Registers a teleological Horn clause dependency: prerequisite must precede goal (P31-01, D-027).
    pub fn register_teleological_dependency(
        self: *TemporalHypervisor,
        prerequisite: RelationKind,
        goal: RelationKind,
    ) !void {
        try self.teleological_dependencies.append(.{
            .prerequisite_relation = prerequisite,
            .target_goal_relation = goal,
        });
    }

    /// Backward-chaining teleological Horn clause solver: evaluates if candidate advances target goal (P31-01, D-027).
    pub fn is_teleologically_justified(
        self: *const TemporalHypervisor,
        candidate_relation: RelationKind,
        target_goal_relation: RelationKind,
    ) bool {
        if (candidate_relation == target_goal_relation) return true;

        for (self.teleological_dependencies.items) |dep| {
            if (dep.prerequisite_relation == candidate_relation) {
                if (dep.target_goal_relation == target_goal_relation) return true;
                if (self.is_teleologically_justified(dep.target_goal_relation, target_goal_relation)) {
                    return true;
                }
            }
        }
        return false;
    }

    /// Evaluates whether the Roberta Sparrow loop closure invariants are satisfied (P31-01, D-027).
    pub fn check_loop_closure(
        self: *const TemporalHypervisor,
        spatial: ?*const SpatialSystem,
    ) bool {
        if (!self.tangent_active or self.tangent_world == null) return false;
        const tw = &self.tangent_world.?;

        // 1. The Artifact must be positioned at the designated vortex waypoint
        if (self.artifact_entity) |art| {
            if (self.vortex_waypoint) |vortex_wp| {
                if (spatial) |sp| {
                    if (sp.agents.get(art)) |agent| {
                        if (agent.current_wp != vortex_wp) return false;
                    } else {
                        // Check if artifact has InRoom or AtWaypoint relational fact
                        if (tw.lookup_relation("AtWaypoint")) |at_rel| {
                            if (!tw.has_fact(art, at_rel, vortex_wp)) return false;
                        } else return false;
                    }
                }
            }
        }

        // 2. Check relational VortexReady / LoopClosed state fact
        const closed_rel = tw.lookup_relation("VortexReady") orelse
            tw.lookup_relation("LoopClosed") orelse return false;

        return tw.has_fact(null, closed_rel, null);
    }

    /// Records a dream residue fact to be committed to the Primary Universe upon loop resolution (P31-01, D-027).
    pub fn add_dream_residue(self: *TemporalHypervisor, fact: DreamFact) !void {
        try self.dream_residue_facts.append(fact);
    }

    /// Steps the Tangent Universe by one tick, enforcing countdown budget and singularity collapse (P31-01, D-027).
    pub fn step_tick(
        self: *TemporalHypervisor,
        spatial: ?*const SpatialSystem,
    ) !HypervisorStepResult {
        if (!self.tangent_active or self.tangent_world == null) {
            return .running;
        }

        self.ticks_elapsed += 1;
        _ = self.tangent_world.?.step_tick();

        // Check if loop closure invariants have been achieved
        if (self.check_loop_closure(spatial)) {
            try self.collapse_tangent(true);
            self.collapse_state = .resolved_and_merged;
            return .loop_resolved;
        }

        // Check if countdown budget has expired
        if (self.ticks_elapsed >= self.collapse_budget_ticks) {
            self.collapse_state = .collapsed_singularity;
            try self.collapse_tangent(false);
            return .singularity_collapse;
        }

        return .running;
    }

    /// Collapses the Tangent Universe, either committing the Artifact and dream residue or purging (P31-01, D-027).
    pub fn collapse_tangent(self: *TemporalHypervisor, commit_artifact: bool) !void {
        if (self.tangent_world) |*tw| {
            if (commit_artifact) {
                // 1. Commit the Artifact of Metal to the Primary Universe
                if (self.artifact_entity) |art| {
                    const primary_art_rel = try self.primary_world.intern_relation("ArtifactMaterialized", .set);
                    _ = try self.primary_world.remember(art, primary_art_rel, 1, 0);
                }

                // 2. Commit dream residue facts into the Primary Universe
                for (self.dream_residue_facts.items) |df| {
                    _ = try self.primary_world.remember(df.subject, df.relation, df.object_or_value, 0);
                }
            }

            tw.deinit();
            self.tangent_world = null;
        }
        self.tangent_active = false;
    }

    /// Returns remaining simulation ticks before catastrophic singularity collapse (P31-01, D-027).
    pub fn ticks_remaining(self: *const TemporalHypervisor) u64 {
        if (!self.tangent_active) return 0;
        if (self.ticks_elapsed >= self.collapse_budget_ticks) return 0;
        return self.collapse_budget_ticks - self.ticks_elapsed;
    }

    /// Formats remaining ticks into Roberta Sparrow's DD:HH:MM:SS countdown format (P31-01, D-027).
    pub fn format_countdown(self: *const TemporalHypervisor, buf: []u8) []const u8 {
        return format_countdown_ticks(self.ticks_remaining(), buf);
    }
};

/// Freestanding formatter converting discrete ticks into Roberta Sparrow's DD:HH:MM:SS countdown format (P31-01, D-027).
pub fn format_countdown_ticks(rem: u64, buf: []u8) []const u8 {
    const total_seconds = rem * 60;
    const days = total_seconds / 86400;
    const hours = (total_seconds % 86400) / 3600;
    const minutes = (total_seconds % 3600) / 60;
    const seconds = total_seconds % 60;

    return std.fmt.bufPrint(buf, "{d:0>2}:{d:0>2}:{d:0>2}:{d:0>2}", .{
        days,
        hours,
        minutes,
        seconds,
    }) catch "00:00:00:00";
}

pub const format_countdown = format_countdown_ticks;

// --- Unit Tests (P31-01, D-027) ---

test "P31-01: TemporalHypervisor forks Tangent Universe, counts ticks, and triggers singularity on budget expiration" {
    const testing = std.testing;
    var primary = try World.init(testing.allocator, 1024 * 1024);
    defer primary.deinit();

    const donnie = try primary.intern_entity("Donnie");
    const jet_engine = try primary.intern_entity("JetEngine");
    const bedroom = try primary.intern_entity("Bedroom");
    const in_room = try primary.intern_relation("InRoom", .property);
    _ = try primary.remember(donnie, in_room, bedroom.to_int(), 0);

    var hypervisor = TemporalHypervisor.init(testing.allocator, &primary);
    defer hypervisor.deinit();

    // 1. Fork Tangent Universe with 10-tick collapse countdown budget
    const tangent = try hypervisor.fork_tangent(10, donnie, jet_engine);
    try testing.expect(hypervisor.tangent_active);
    try testing.expectEqual(@as(u64, 10), hypervisor.ticks_remaining());

    var count_buf: [32]u8 = undefined;
    const initial_str = hypervisor.format_countdown(&count_buf);
    try testing.expect(initial_str.len > 0);

    // Donnie wanders to Golf Course in Tangent Universe
    const golf_course = try tangent.intern_entity("GolfCourse");
    _ = try tangent.remember(donnie, in_room, golf_course.to_int(), 0);

    // Step 9 ticks -> still running
    for (0..9) |_| {
        const res = try hypervisor.step_tick(null);
        try testing.expectEqual(HypervisorStepResult.running, res);
    }
    try testing.expectEqual(@as(u64, 1), hypervisor.ticks_remaining());

    // 10th tick -> countdown expires without loop closure -> singularity collapse!
    const collapse_res = try hypervisor.step_tick(null);
    try testing.expectEqual(HypervisorStepResult.singularity_collapse, collapse_res);
    try testing.expectEqual(TangentCollapseState.collapsed_singularity, hypervisor.collapse_state);
    try testing.expect(!hypervisor.tangent_active);

    // Primary world is unharmed and Donnie is still in Bedroom
    try testing.expect(primary.has_fact(donnie, in_room, bedroom.to_int()));
}

test "P31-01: TemporalHypervisor resolves loop closure, commits Artifact and dream residue to Primary Universe" {
    const testing = std.testing;
    var primary = try World.init(testing.allocator, 1024 * 1024);
    defer primary.deinit();

    const donnie = try primary.intern_entity("Donnie");
    const jet_engine = try primary.intern_entity("JetEngine");
    const vortex_rel = try primary.intern_relation("VortexReady", .set);
    const dream_rel = try primary.intern_relation("DreamPrecognition", .set);

    var hypervisor = TemporalHypervisor.init(testing.allocator, &primary);
    defer hypervisor.deinit();

    const tangent = try hypervisor.fork_tangent(50, donnie, jet_engine);

    // Record dream residue fact that will survive loop resolution
    try hypervisor.add_dream_residue(.{
        .subject = donnie,
        .relation = dream_rel,
        .object_or_value = 1,
    });

    // In Tangent Universe, Donnie completes teleological tasks and opens the vortex
    _ = try tangent.remember(jet_engine, vortex_rel, 1, 0);

    // Step tick detects loop closure
    const res = try hypervisor.step_tick(null);
    try testing.expectEqual(HypervisorStepResult.loop_resolved, res);
    try testing.expectEqual(TangentCollapseState.resolved_and_merged, hypervisor.collapse_state);
    try testing.expect(!hypervisor.tangent_active);

    // Artifact and dream residue successfully committed to Primary Universe!
    const artifact_mat_rel = primary.lookup_relation("ArtifactMaterialized").?;
    try testing.expect(primary.has_fact(jet_engine, artifact_mat_rel, 1));
    try testing.expect(primary.has_fact(donnie, dream_rel, 1));
}

test "P31-01: backward-chaining teleological Horn clause solver verifies prerequisite chains" {
    const testing = std.testing;
    var primary = try World.init(testing.allocator, 1024 * 1024);
    defer primary.deinit();

    var hypervisor = TemporalHypervisor.init(testing.allocator, &primary);
    defer hypervisor.deinit();

    // Define teleological chain: AxeWaterPipe -> SchoolFlooded -> SchoolClosed -> MovieDate -> RidgeVortex
    const axe_pipe = try primary.intern_relation("AxeWaterPipe", .set);
    const school_flooded = try primary.intern_relation("SchoolFlooded", .set);
    const school_closed = try primary.intern_relation("SchoolClosed", .set);
    const movie_date = try primary.intern_relation("MovieDate", .set);
    const ridge_vortex = try primary.intern_relation("RidgeVortex", .set);
    const unrelated_action = try primary.intern_relation("BuyCandy", .set);

    try hypervisor.register_teleological_dependency(axe_pipe, school_flooded);
    try hypervisor.register_teleological_dependency(school_flooded, school_closed);
    try hypervisor.register_teleological_dependency(school_closed, movie_date);
    try hypervisor.register_teleological_dependency(movie_date, ridge_vortex);

    // AxeWaterPipe teleologically advances RidgeVortex through 4-hop Horn clause chain
    try testing.expect(hypervisor.is_teleologically_justified(axe_pipe, ridge_vortex));
    try testing.expect(hypervisor.is_teleologically_justified(school_flooded, ridge_vortex));
    try testing.expect(hypervisor.is_teleologically_justified(movie_date, ridge_vortex));

    // Unrelated action does not advance the terminal vortex goal
    try testing.expect(!hypervisor.is_teleologically_justified(unrelated_action, ridge_vortex));
}
