const std = @import("std");
const world_mod = @import("world.zig");
const spatial_mod = @import("spatial.zig");
const World = world_mod.World;
const EntityId = world_mod.EntityId;
const RelationKind = world_mod.RelationKind;
const WaypointId = spatial_mod.WaypointId;
const SpatialSystem = spatial_mod.SpatialSystem;

/// Universe branch classification in the branching causal model (P31-01, P32-21, D-027, D-044).
pub const UniverseBranchKind = enum {
    primary,
    branch,

    pub const tangent = UniverseBranchKind.branch;
};

/// Lifecycle state of a branch universe (P31-01, P32-21, D-027, D-044).
pub const BranchCollapseState = enum {
    dormant,
    active,
    budget_expired,
    collapsed_singularity, // backwards-compatible tag
    resolved_and_merged,
};

pub const TangentCollapseState = BranchCollapseState;

/// Residual memory or emotional impression that survives branch collapse (P31-01, P32-21, D-027, D-044).
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

/// Outcome of advancing the temporal hypervisor by one discrete simulation tick (P31-01, P32-21, D-027, D-044).
pub const HypervisorStepResult = enum {
    running,
    budget_expired,
    singularity_collapse, // backwards-compatible tag
    loop_resolved,
};

/// Temporal Hypervisor orchestrating Primary and Branch World fact arenas (P31-01, P32-21, D-027, D-044).
/// Manages ephemeral copy-on-write branching, collapse countdown budgets, teleological Horn clauses,
/// and dream-residue memory merges upon causal loop closure.
pub const TemporalHypervisor = struct {
    allocator: std.mem.Allocator,
    primary_world: *World,
    branch_world: ?World,
    branch_active: bool,
    tangent_active: bool,

    receiver_entity: ?EntityId,
    living_receiver: ?EntityId,
    keystone_entity: ?EntityId,
    artifact_entity: ?EntityId,
    convergence_waypoint: ?WaypointId,
    vortex_waypoint: ?WaypointId,

    collapse_budget_ticks: u64,
    ticks_elapsed: u64,
    collapse_state: BranchCollapseState,

    teleological_dependencies: std.ArrayList(TeleologicalDependency),
    dream_residue_facts: std.ArrayList(DreamFact),

    pub fn init(allocator: std.mem.Allocator, primary_world: *World) TemporalHypervisor {
        return TemporalHypervisor{
            .allocator = allocator,
            .primary_world = primary_world,
            .branch_world = null,
            .branch_active = false,
            .tangent_active = false,
            .receiver_entity = null,
            .living_receiver = null,
            .keystone_entity = null,
            .artifact_entity = null,
            .convergence_waypoint = null,
            .vortex_waypoint = null,
            .collapse_budget_ticks = 0,
            .ticks_elapsed = 0,
            .collapse_state = .dormant,
            .teleological_dependencies = std.ArrayList(TeleologicalDependency).init(allocator),
            .dream_residue_facts = std.ArrayList(DreamFact).init(allocator),
        };
    }

    pub fn deinit(self: *TemporalHypervisor) void {
        if (self.branch_world) |*bw| {
            bw.deinit();
            self.branch_world = null;
        }
        self.teleological_dependencies.deinit();
        self.dream_residue_facts.deinit();
    }

    /// Returns the world that currently receives simulation actions. A live branch is the
    /// authoritative arena until it resolves or expires; outside a branch the primary world is
    /// authoritative. Hosts use this boundary instead of choosing an arena from proof state.
    pub fn active_world(self: *TemporalHypervisor) *World {
        if (self.branch_active) {
            if (self.branch_world) |*branch| return branch;
        }
        return self.primary_world;
    }

    /// Forks the Primary World into an ephemeral branch arena with a strict tick budget (P31-01, P32-21, D-027, D-044).
    pub fn fork_branch(
        self: *TemporalHypervisor,
        budget_ticks: u64,
        receiver: EntityId,
        keystone: EntityId,
    ) !*World {
        if (self.branch_world) |*bw| {
            bw.deinit();
            self.branch_world = null;
        }

        self.branch_world = try self.primary_world.clone(self.allocator);
        self.branch_active = true;
        self.tangent_active = true;
        self.collapse_budget_ticks = budget_ticks;
        self.ticks_elapsed = 0;
        self.receiver_entity = receiver;
        self.living_receiver = receiver;
        self.keystone_entity = keystone;
        self.artifact_entity = keystone;
        self.collapse_state = .active;

        return &self.branch_world.?;
    }

    pub fn fork_tangent(
        self: *TemporalHypervisor,
        budget_ticks: u64,
        receiver: EntityId,
        artifact: EntityId,
    ) !*World {
        return self.fork_branch(budget_ticks, receiver, artifact);
    }

    /// Sets the designated spatial convergence waypoint for keystone resolution (P31-01, P32-21, D-027, D-044).
    pub fn set_convergence_target(self: *TemporalHypervisor, waypoint: WaypointId) void {
        self.convergence_waypoint = waypoint;
        self.vortex_waypoint = waypoint;
    }

    pub fn set_vortex_target(self: *TemporalHypervisor, waypoint: WaypointId) void {
        self.set_convergence_target(waypoint);
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

    /// Evaluates whether causal loop closure invariants are satisfied (P31-01, P32-21, D-027, D-044).
    pub fn check_loop_closure(
        self: *const TemporalHypervisor,
        spatial: ?*const SpatialSystem,
    ) bool {
        if (!self.branch_active or self.branch_world == null) return false;
        const bw = &self.branch_world.?;

        // 1. The Keystone must be positioned at the designated convergence waypoint
        const target_keystone = self.keystone_entity orelse self.artifact_entity;
        const target_waypoint = self.convergence_waypoint orelse self.vortex_waypoint;

        if (target_keystone) |keystone| {
            if (target_waypoint) |conv_wp| {
                if (spatial) |sp| {
                    if (sp.agents.get(keystone)) |agent| {
                        if (agent.current_wp != conv_wp) return false;
                    } else {
                        // Check if keystone has InRoom or AtWaypoint relational fact
                        if (bw.lookup_relation("AtWaypoint")) |at_rel| {
                            if (!bw.has_fact(keystone, at_rel, conv_wp)) return false;
                        } else return false;
                    }
                }
            }
        }

        // 2. Check relational ConvergenceReady / VortexReady / LoopClosed state fact
        const closed_rel = bw.lookup_relation("ConvergenceReady") orelse
            bw.lookup_relation("VortexReady") orelse
            bw.lookup_relation("LoopClosed") orelse return false;

        return bw.has_fact(null, closed_rel, null);
    }

    /// Records a dream residue fact to be committed to the Primary World upon loop resolution (P31-01, D-027).
    pub fn add_dream_residue(self: *TemporalHypervisor, fact: DreamFact) !void {
        try self.dream_residue_facts.append(fact);
    }

    /// Steps the branch world by one tick, enforcing countdown budget and expiration (P31-01, P32-21, D-027, D-044).
    pub fn step_tick(
        self: *TemporalHypervisor,
        spatial: ?*const SpatialSystem,
    ) !HypervisorStepResult {
        if (!self.branch_active or self.branch_world == null) {
            return .running;
        }

        self.ticks_elapsed += 1;
        _ = self.branch_world.?.step_tick();

        // Check if loop closure invariants have been achieved
        if (self.check_loop_closure(spatial)) {
            try self.collapse_branch(true);
            self.collapse_state = .resolved_and_merged;
            return .loop_resolved;
        }

        // Check if countdown budget has expired
        if (self.ticks_elapsed >= self.collapse_budget_ticks) {
            self.collapse_state = .budget_expired;
            try self.collapse_branch(false);
            return .budget_expired;
        }

        return .running;
    }

    /// Collapses the branch world, either committing the keystone and dream residue or purging (P31-01, P32-21, D-027, D-044).
    pub fn collapse_branch(self: *TemporalHypervisor, commit_keystone: bool) !void {
        if (self.branch_world) |*bw| {
            if (commit_keystone) {
                // 1. Commit the Keystone Entity to the Primary World
                const target_keystone = self.keystone_entity orelse self.artifact_entity;
                if (target_keystone) |keystone| {
                    const primary_key_rel = try self.primary_world.intern_relation("KeystoneMaterialized", .set);
                    _ = try self.primary_world.remember(keystone, primary_key_rel, 1, 0);
                    const primary_art_rel = try self.primary_world.intern_relation("ArtifactMaterialized", .set);
                    _ = try self.primary_world.remember(keystone, primary_art_rel, 1, 0);
                }

                // 2. Commit dream residue facts into the Primary World
                for (self.dream_residue_facts.items) |df| {
                    _ = try self.primary_world.remember(df.subject, df.relation, df.object_or_value, 0);
                }
            }

            bw.deinit();
            self.branch_world = null;
        }
        self.branch_active = false;
        self.tangent_active = false;
    }

    pub fn collapse_tangent(self: *TemporalHypervisor, commit_artifact: bool) !void {
        return self.collapse_branch(commit_artifact);
    }

    /// Returns remaining simulation ticks before countdown budget expiration (P31-01, P32-21, D-027, D-044).
    pub fn ticks_remaining(self: *const TemporalHypervisor) u64 {
        if (!self.branch_active) return 0;
        if (self.ticks_elapsed >= self.collapse_budget_ticks) return 0;
        return self.collapse_budget_ticks - self.ticks_elapsed;
    }

    /// Formats remaining ticks into DD:HH:MM:SS countdown format (P31-01, D-027).
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

    // 10th tick -> countdown expires without loop closure -> budget expired!
    const collapse_res = try hypervisor.step_tick(null);
    try testing.expect(collapse_res == .budget_expired or collapse_res == .singularity_collapse);
    try testing.expect(hypervisor.collapse_state == .budget_expired or hypervisor.collapse_state == .collapsed_singularity);
    try testing.expect(!hypervisor.tangent_active);

    // Primary world is unharmed and Donnie is still in Bedroom
    try testing.expect(primary.has_fact(donnie, in_room, bedroom.to_int()));
}

test "P31-05: active world follows the branch lifecycle" {
    const testing = std.testing;
    var primary = try World.init(testing.allocator, 1024 * 1024);
    defer primary.deinit();

    const actor = try primary.intern_entity("Actor");
    const keystone = try primary.intern_entity("Keystone");
    const changed = try primary.intern_relation("Changed", .set);

    var hypervisor = TemporalHypervisor.init(testing.allocator, &primary);
    defer hypervisor.deinit();
    try testing.expect(hypervisor.active_world() == &primary);

    const branch = try hypervisor.fork_branch(2, actor, keystone);
    try testing.expect(hypervisor.active_world() == branch);
    _ = try hypervisor.active_world().remember(actor, changed, 1, 0);
    try testing.expect(branch.has_fact(actor, changed, 1));
    try testing.expect(!primary.has_fact(actor, changed, 1));

    _ = try hypervisor.step_tick(null);
    _ = try hypervisor.step_tick(null);
    try testing.expect(!hypervisor.branch_active);
    try testing.expect(hypervisor.active_world() == &primary);
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

test "P32-21: TemporalHypervisor neutral vocabulary (fork_branch, convergence target, budget_expired)" {
    const testing = std.testing;
    var primary = try World.init(testing.allocator, 1024 * 1024);
    defer primary.deinit();

    const actor = try primary.intern_entity("Hero");
    const keystone = try primary.intern_entity("KeystoneKey");
    const room = try primary.intern_entity("Sanctuary");
    const in_room = try primary.intern_relation("InRoom", .property);
    _ = try primary.remember(actor, in_room, room.to_int(), 0);

    var hypervisor = TemporalHypervisor.init(testing.allocator, &primary);
    defer hypervisor.deinit();

    // 1. fork_branch with budget ticks
    _ = try hypervisor.fork_branch(10, actor, keystone);
    try testing.expect(hypervisor.branch_active);
    try testing.expectEqual(@as(u64, 10), hypervisor.ticks_remaining());

    // 2. Set convergence target waypoint
    hypervisor.set_convergence_target(42);
    try testing.expectEqual(@as(?u16, 42), hypervisor.convergence_waypoint);

    // 3. Step until budget expired
    for (0..9) |_| {
        const res = try hypervisor.step_tick(null);
        try testing.expectEqual(HypervisorStepResult.running, res);
    }
    const final_res = try hypervisor.step_tick(null);
    try testing.expectEqual(HypervisorStepResult.budget_expired, final_res);
    try testing.expectEqual(BranchCollapseState.budget_expired, hypervisor.collapse_state);
    try testing.expect(!hypervisor.branch_active);

    // 4. Test loop resolution and keystone commit via fork_branch
    const branch2 = try hypervisor.fork_branch(20, actor, keystone);
    const conv_rel = try branch2.intern_relation("ConvergenceReady", .set);
    const at_wp = try branch2.intern_relation("AtWaypoint", .property);
    _ = try branch2.remember(keystone, at_wp, 42, 0);
    _ = try branch2.remember(keystone, conv_rel, 1, 0);

    const res_resolve = try hypervisor.step_tick(null);
    try testing.expectEqual(HypervisorStepResult.loop_resolved, res_resolve);
    try testing.expectEqual(BranchCollapseState.resolved_and_merged, hypervisor.collapse_state);

    const key_mat_rel = primary.lookup_relation("KeystoneMaterialized").?;
    try testing.expect(primary.has_fact(keystone, key_mat_rel, 1));
}
