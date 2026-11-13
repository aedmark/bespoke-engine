const std = @import("std");

/// Opaque 32-bit entity identifier (D-003). 0 is reserved for 'none'.
pub const EntityId = enum(u32) {
    none = 0,
    _,

    pub fn to_int(self: EntityId) u32 {
        return @intFromEnum(self);
    }

    pub fn from_int(val: u32) EntityId {
        return @enumFromInt(val);
    }
};

/// 16-bit identifier for relation types (D-003). 0 is reserved for 'none'.
pub const RelationKind = enum(u16) {
    none = 0,
    _,

    pub fn to_int(self: RelationKind) u16 {
        return @intFromEnum(self);
    }

    pub fn from_int(val: u16) RelationKind {
        return @enumFromInt(val);
    }
};

/// Semantics of a relation (D-007).
pub const RelationType = enum(u8) {
    /// Multiple facts allowed per subject (e.g. Carries(Holder, ItemA) and Carries(Holder, ItemB)).
    set = 0,
    /// Single scalar value or entity per subject; remember auto-overwrites existing value (e.g. Alertness, Gold).
    property = 1,
};

/// Flat 4-tuple relational row stored in contiguous SoA layout (D-003, D-007).
pub const Fact = struct {
    subject: EntityId,
    relation: RelationKind,
    object_or_value: u32, // EntityId or immediate scalar (D-007)
    expires_at_tick: u64, // 0 = permanent, >0 = tick when fact expires (D-003)
};

pub const RelationMeta = struct {
    name: []const u8,
    rel_type: RelationType,
};

/// Multi-clause pattern matching slot (P8-01, D-010).
pub const PatternTerm = union(enum) {
    wildcard: void,
    constant: u32,
    variable: u8, // Variable slot index 0..7
};

/// Single relational pattern clause with subject and object terms (P8-01, D-010).
pub const PatternClause = struct {
    relation: RelationKind,
    subject: PatternTerm,
    object: PatternTerm,
};

/// Variable bindings result from relational pattern unification (P8-01, D-010).
pub const VariableBindings = struct {
    values: [8]?u32 = [_]?u32{null} ** 8,

    pub fn get(self: VariableBindings, var_idx: u8) ?u32 {
        if (var_idx >= 8) return null;
        return self.values[var_idx];
    }

    pub fn set(self: *VariableBindings, var_idx: u8, val: u32) bool {
        if (var_idx >= 8) return false;
        if (self.values[var_idx]) |existing| {
            return existing == val; // Must match consistently across joined clauses
        }
        self.values[var_idx] = val;
        return true;
    }
};

pub const DEFAULT_ARENA_SIZE: usize = 4 * 1024 * 1024; // 4 MB
pub const DEFAULT_MAX_FACTS: usize = 8192;

pub const SnapshotHeader = extern struct {
    magic: [4]u8 = [_]u8{ 'B', 'S', 'P', 'K' },
    version: u32 = 1,
    current_tick: u64,
    facts_len: usize,
    entity_count: usize,
    relation_count: usize,
    checksum: u32,
};

pub const SnapshotError = error{
    InvalidMagic,
    UnsupportedVersion,
    ChecksumMismatch,
    CapacityExceeded,
};

/// The relational state database and entity registry for BeSpoke Engine.
pub const World = struct {
    backing_allocator: std.mem.Allocator,
    arena_buffer: []u8,
    fba: std.heap.FixedBufferAllocator,

    facts: std.MultiArrayList(Fact),
    current_tick: u64,

    // Dynamic String Interner (D-007)
    entity_names: std.ArrayListUnmanaged([]const u8),
    entity_map: std.StringHashMapUnmanaged(EntityId),

    relation_meta: std.ArrayListUnmanaged(RelationMeta),
    relation_map: std.StringHashMapUnmanaged(RelationKind),

    // TTL Expiration tracking (P10-02, D-012)
    recently_expired: [16]Fact,
    recently_expired_count: usize,

    pub fn init(backing_allocator: std.mem.Allocator, arena_size: usize) !World {
        return initWithMaxFacts(backing_allocator, arena_size, DEFAULT_MAX_FACTS);
    }

    pub fn initWithMaxFacts(backing_allocator: std.mem.Allocator, arena_size: usize, max_facts: usize) !World {
        const buffer = try backing_allocator.alloc(u8, arena_size);
        var fba = std.heap.FixedBufferAllocator.init(buffer);
        const alloc = fba.allocator();

        var facts = std.MultiArrayList(Fact){};
        try facts.ensureTotalCapacity(alloc, max_facts);

        return World{
            .backing_allocator = backing_allocator,
            .arena_buffer = buffer,
            .fba = fba,
            .facts = facts,
            .current_tick = 0,
            .entity_names = .{},
            .entity_map = .{},
            .relation_meta = .{},
            .relation_map = .{},
            .recently_expired = undefined,
            .recently_expired_count = 0,
        };
    }

    pub fn deinit(self: *World) void {
        self.backing_allocator.free(self.arena_buffer);
        self.* = undefined;
    }

    /// Allocator backed by the contiguous fixed arena buffer.
    pub fn allocator(self: *World) std.mem.Allocator {
        return self.fba.allocator();
    }

    // --- Entity & Relation Interning ---

    /// Interns or retrieves an EntityId by name.
    pub fn intern_entity(self: *World, name: []const u8) !EntityId {
        if (self.entity_map.get(name)) |existing_id| {
            return existing_id;
        }

        const alloc = self.allocator();
        const owned_name = try alloc.dupe(u8, name);
        const next_id_val: u32 = @intCast(self.entity_names.items.len + 1);
        const new_id = EntityId.from_int(next_id_val);

        try self.entity_names.append(alloc, owned_name);
        try self.entity_map.put(alloc, owned_name, new_id);

        return new_id;
    }

    /// Gets the human-readable name of an EntityId.
    pub fn get_entity_name(self: *const World, id: EntityId) ?[]const u8 {
        const int_val = id.to_int();
        if (int_val == 0 or int_val > self.entity_names.items.len) {
            return null;
        }
        return self.entity_names.items[int_val - 1];
    }

    /// Interns or retrieves a RelationKind by name with specified semantics.
    pub fn intern_relation(self: *World, name: []const u8, rel_type: RelationType) !RelationKind {
        if (self.relation_map.get(name)) |existing_kind| {
            return existing_kind;
        }

        const alloc = self.allocator();
        const owned_name = try alloc.dupe(u8, name);
        const next_kind_val: u16 = @intCast(self.relation_meta.items.len + 1);
        const new_kind = RelationKind.from_int(next_kind_val);

        try self.relation_meta.append(alloc, .{
            .name = owned_name,
            .rel_type = rel_type,
        });
        try self.relation_map.put(alloc, owned_name, new_kind);

        return new_kind;
    }

    /// Read-only lookup of an interned EntityId by name.
    pub fn lookup_entity(self: *const World, name: []const u8) ?EntityId {
        return self.entity_map.get(name);
    }

    /// Read-only lookup of an interned RelationKind by name.
    pub fn lookup_relation(self: *const World, name: []const u8) ?RelationKind {
        return self.relation_map.get(name);
    }

    /// Gets the metadata of a RelationKind.
    pub fn get_relation_meta(self: *const World, kind: RelationKind) ?RelationMeta {
        const int_val = kind.to_int();
        if (int_val == 0 or int_val > self.relation_meta.items.len) {
            return null;
        }
        return self.relation_meta.items[int_val - 1];
    }

    pub fn fact_count(self: *const World) usize {
        return self.facts.len;
    }

    // --- Declarative Mutations (P1-02, D-003, D-007) ---

    /// Remembers a fact. If ttl_ticks > 0, the fact expires at current_tick + ttl_ticks.
    /// For Property relations, existing facts with the same (subject, relation) are overwritten (D-007).
    pub fn remember(
        self: *World,
        subject: EntityId,
        relation: RelationKind,
        object_or_value: u32,
        ttl_ticks: u64,
    ) !void {
        const expires_at_tick: u64 = if (ttl_ticks > 0) self.current_tick + ttl_ticks else 0;
        const meta = self.get_relation_meta(relation) orelse RelationMeta{ .name = "", .rel_type = .set };

        if (meta.rel_type == .property) {
            // Functional property: overwrite existing entry if present
            var i: usize = 0;
            const slice = self.facts.slice();
            const subjects = slice.items(.subject);
            const relations = slice.items(.relation);

            while (i < self.facts.len) : (i += 1) {
                if (subjects[i] == subject and relations[i] == relation) {
                    slice.items(.object_or_value)[i] = object_or_value;
                    slice.items(.expires_at_tick)[i] = expires_at_tick;
                    return;
                }
            }
        } else {
            // Set relation: check if identical fact already exists to prevent duplicate rows
            var i: usize = 0;
            const slice = self.facts.slice();
            const subjects = slice.items(.subject);
            const relations = slice.items(.relation);
            const objects = slice.items(.object_or_value);

            while (i < self.facts.len) : (i += 1) {
                if (subjects[i] == subject and relations[i] == relation and objects[i] == object_or_value) {
                    // Update expiration if new TTL extends the life
                    if (expires_at_tick > slice.items(.expires_at_tick)[i] or expires_at_tick == 0) {
                        slice.items(.expires_at_tick)[i] = expires_at_tick;
                    }
                    return;
                }
            }
        }

        // New fact row: append using pre-allocated capacity
        if (self.facts.len >= self.facts.capacity) {
            return SnapshotError.CapacityExceeded;
        }
        self.facts.appendAssumeCapacity(.{
            .subject = subject,
            .relation = relation,
            .object_or_value = object_or_value,
            .expires_at_tick = expires_at_tick,
        });
    }

    /// Forgets facts matching (subject, relation, optional object_or_value).
    /// If object_or_value is null, forgets all facts with (subject, relation).
    /// Returns true if at least one fact was removed.
    pub fn forget(
        self: *World,
        subject: EntityId,
        relation: RelationKind,
        object_or_value: ?u32,
    ) bool {
        var removed = false;
        var i: usize = 0;

        while (i < self.facts.len) {
            const slice = self.facts.slice();
            const match_subj = slice.items(.subject)[i] == subject;
            const match_rel = slice.items(.relation)[i] == relation;
            const match_obj = if (object_or_value) |ov| slice.items(.object_or_value)[i] == ov else true;

            if (match_subj and match_rel and match_obj) {
                self.facts.swapRemove(i);
                removed = true;
                // Swap-remove places the last item at index i; do not increment i
            } else {
                i += 1;
            }
        }

        return removed;
    }

    /// Generalized item ownership transfer between two entities (P21-01, D-025).
    /// Executes an atomic relational swap: forgets ownership from sender and remembers for recipient.
    /// Supports InInventory and Carries relations, preserving zero-overhead matter conservation.
    pub fn transfer_item(
        self: *World,
        item: EntityId,
        from: EntityId,
        to: EntityId,
    ) !bool {
        var transferred = false;
        if (self.lookup_relation("InInventory")) |inv_rel| {
            if (self.has_fact(from, inv_rel, item.to_int())) {
                _ = self.forget(from, inv_rel, item.to_int());
                _ = try self.remember(to, inv_rel, item.to_int(), 0);
                transferred = true;
            }
        }
        if (self.lookup_relation("Carries")) |carr_rel| {
            if (self.has_fact(from, carr_rel, item.to_int())) {
                _ = self.forget(from, carr_rel, item.to_int());
                _ = try self.remember(to, carr_rel, item.to_int(), 0);
                transferred = true;
            }
        }
        return transferred;
    }

    /// Advances the simulation clock by 1 tick and prunes expired facts (P1-02).
    /// Returns the number of pruned facts.
    pub fn step_tick(self: *World) usize {
        self.current_tick += 1;
        return self.prune_expired();
    }

    /// Prunes facts whose expires_at_tick is non-zero and <= current_tick.
    pub fn prune_expired(self: *World) usize {
        self.recently_expired_count = 0;
        var pruned: usize = 0;
        var i: usize = 0;

        while (i < self.facts.len) {
            const slice = self.facts.slice();
            const exp = slice.items(.expires_at_tick)[i];

            if (exp > 0 and exp <= self.current_tick) {
                if (self.recently_expired_count < self.recently_expired.len) {
                    self.recently_expired[self.recently_expired_count] = .{
                        .subject = slice.items(.subject)[i],
                        .relation = slice.items(.relation)[i],
                        .object_or_value = slice.items(.object_or_value)[i],
                        .expires_at_tick = exp,
                    };
                    self.recently_expired_count += 1;
                }
                self.facts.swapRemove(i);
                pruned += 1;
            } else {
                i += 1;
            }
        }

        return pruned;
    }

    /// Gets slice of facts that expired during the most recent step_tick() (P10-02, D-012).
    pub fn get_recently_expired(self: *const World) []const Fact {
        return self.recently_expired[0..self.recently_expired_count];
    }

    // --- Pattern Matching & Queries (P1-03, D-006) ---

    /// Checks if any fact matches the given pattern. Null arguments act as wildcards (`_`).
    pub fn has_fact(
        self: *const World,
        subject: ?EntityId,
        relation: ?RelationKind,
        object_or_value: ?u32,
    ) bool {
        return self.find_first(subject, relation, object_or_value) != null;
    }

    /// Finds the first fact matching the pattern, or null if none found.
    pub fn find_first(
        self: *const World,
        subject: ?EntityId,
        relation: ?RelationKind,
        object_or_value: ?u32,
    ) ?Fact {
        if (self.facts.len == 0) return null;
        const slice = self.facts.slice();
        const subjects = slice.items(.subject);
        const relations = slice.items(.relation);
        const objects = slice.items(.object_or_value);
        const expirations = slice.items(.expires_at_tick);

        for (0..self.facts.len) |i| {
            if (subject != null and subjects[i] != subject.?) continue;
            if (relation != null and relations[i] != relation.?) continue;
            if (object_or_value != null and objects[i] != object_or_value.?) continue;

            return Fact{
                .subject = subjects[i],
                .relation = relations[i],
                .object_or_value = objects[i],
                .expires_at_tick = expirations[i],
            };
        }

        return null;
    }

    /// Gets the scalar value of a property relation on an entity (D-007).
    pub fn get_property(self: *const World, subject: EntityId, relation: RelationKind) ?u32 {
        if (self.find_first(subject, relation, null)) |f| {
            return f.object_or_value;
        }
        return null;
    }

    pub const QueryIterator = struct {
        world: *const World,
        subject: ?EntityId,
        relation: ?RelationKind,
        object_or_value: ?u32,
        index: usize = 0,

        pub fn next(self: *QueryIterator) ?Fact {
            if (self.world.facts.len == 0) return null;
            const slice = self.world.facts.slice();
            const subjects = slice.items(.subject);
            const relations = slice.items(.relation);
            const objects = slice.items(.object_or_value);
            const expirations = slice.items(.expires_at_tick);

            while (self.index < self.world.facts.len) {
                const i = self.index;
                self.index += 1;
                if (self.subject != null and subjects[i] != self.subject.?) continue;
                if (self.relation != null and relations[i] != self.relation.?) continue;
                if (self.object_or_value != null and objects[i] != self.object_or_value.?) continue;

                return Fact{
                    .subject = subjects[i],
                    .relation = relations[i],
                    .object_or_value = objects[i],
                    .expires_at_tick = expirations[i],
                };
            }
            return null;
        }
    };

    /// Iterates over all facts matching the given pattern with wildcards (P1-03, P7-03, D-006).
    pub fn query(
        self: *const World,
        subject: ?EntityId,
        relation: ?RelationKind,
        object_or_value: ?u32,
    ) QueryIterator {
        return QueryIterator{
            .world = self,
            .subject = subject,
            .relation = relation,
            .object_or_value = object_or_value,
        };
    }

    // --- Multi-Clause Pattern Matching & Relational Joins (P8-01, D-006, D-010) ---

    /// Recursively backtracks across multi-clause patterns against the fact table (P8-01).
    fn match_multi_step(
        self: *const World,
        clauses: []const PatternClause,
        clause_idx: usize,
        bindings: VariableBindings,
    ) ?VariableBindings {
        if (clause_idx >= clauses.len) {
            return bindings;
        }

        const clause = clauses[clause_idx];
        const slice = self.facts.slice();
        const subjects = slice.items(.subject);
        const relations = slice.items(.relation);
        const objects = slice.items(.object_or_value);

        for (0..self.facts.len) |i| {
            if (relations[i] != clause.relation) continue;

            var next_bindings = bindings;

            // Check & unify subject
            const fact_subj = subjects[i].to_int();
            switch (clause.subject) {
                .wildcard => {},
                .constant => |c| if (fact_subj != c) continue,
                .variable => |v| if (!next_bindings.set(v, fact_subj)) continue,
            }

            // Check & unify object
            const fact_obj = objects[i];
            switch (clause.object) {
                .wildcard => {},
                .constant => |c| if (fact_obj != c) continue,
                .variable => |v| if (!next_bindings.set(v, fact_obj)) continue,
            }

            // Unification succeeded for this fact; advance to next clause
            if (self.match_multi_step(clauses, clause_idx + 1, next_bindings)) |solution| {
                return solution;
            }
        }

        return null;
    }

    /// Finds the first satisfying set of variable bindings for a conjunction of relational clauses (P8-01).
    pub fn find_first_match(self: *const World, clauses: []const PatternClause) ?VariableBindings {
        return self.find_first_match_from(clauses, VariableBindings{});
    }

    /// Like `find_first_match`, but starts from bindings already set, so a variable bound by the
    /// caller (a cue argument, D-072) must match that value in every clause that mentions it.
    pub fn find_first_match_from(self: *const World, clauses: []const PatternClause, initial: VariableBindings) ?VariableBindings {
        if (clauses.len == 0) return initial;
        return self.match_multi_step(clauses, 0, initial);
    }

    /// Tests whether a conjunction of relational clauses is satisfied in the active fact store (P8-01).
    pub fn has_multi_match(self: *const World, clauses: []const PatternClause) bool {
        return self.find_first_match(clauses) != null;
    }

    fn collect_multi_matches(
        self: *const World,
        clauses: []const PatternClause,
        clause_idx: usize,
        bindings: VariableBindings,
        results: *std.ArrayList(VariableBindings),
    ) !void {
        if (clause_idx >= clauses.len) {
            try results.append(bindings);
            return;
        }

        const clause = clauses[clause_idx];
        const slice = self.facts.slice();
        const subjects = slice.items(.subject);
        const relations = slice.items(.relation);
        const objects = slice.items(.object_or_value);

        for (0..self.facts.len) |i| {
            if (relations[i] != clause.relation) continue;

            var next_bindings = bindings;

            const fact_subj = subjects[i].to_int();
            switch (clause.subject) {
                .wildcard => {},
                .constant => |c| if (fact_subj != c) continue,
                .variable => |v| if (!next_bindings.set(v, fact_subj)) continue,
            }

            const fact_obj = objects[i];
            switch (clause.object) {
                .wildcard => {},
                .constant => |c| if (fact_obj != c) continue,
                .variable => |v| if (!next_bindings.set(v, fact_obj)) continue,
            }

            try self.collect_multi_matches(clauses, clause_idx + 1, next_bindings, results);
        }
    }

    /// Finds all satisfying variable bindings for a multi-clause join query (P8-01).
    pub fn find_all_matches(
        self: *const World,
        alloc: std.mem.Allocator,
        clauses: []const PatternClause,
    ) ![]VariableBindings {
        var results = std.ArrayList(VariableBindings).init(alloc);
        if (clauses.len == 0) return results.toOwnedSlice();
        try self.collect_multi_matches(clauses, 0, VariableBindings{}, &results);
        return results.toOwnedSlice();
    }

    // --- Deterministic Snapshot Serialization (P1-04, D-001, D-003) ---

    /// Writes a complete deterministic memory snapshot of the World state to a writer.
    /// Serializes current tick, entity & relation names, and SoA fact column slices.
    pub fn save_state(self: *const World, writer: anytype) !void {
        var hasher = std.hash.Crc32.init();

        const slice = self.facts.slice();
        const subjects_bytes = std.mem.sliceAsBytes(slice.items(.subject)[0..self.facts.len]);
        const relations_bytes = std.mem.sliceAsBytes(slice.items(.relation)[0..self.facts.len]);
        const objects_bytes = std.mem.sliceAsBytes(slice.items(.object_or_value)[0..self.facts.len]);
        const expirations_bytes = std.mem.sliceAsBytes(slice.items(.expires_at_tick)[0..self.facts.len]);

        hasher.update(subjects_bytes);
        hasher.update(relations_bytes);
        hasher.update(objects_bytes);
        hasher.update(expirations_bytes);

        const header = SnapshotHeader{
            .current_tick = self.current_tick,
            .facts_len = self.facts.len,
            .entity_count = self.entity_names.items.len,
            .relation_count = self.relation_meta.items.len,
            .checksum = hasher.final(),
        };

        try writer.writeAll(std.mem.asBytes(&header));

        // Write SoA fact columns
        try writer.writeAll(subjects_bytes);
        try writer.writeAll(relations_bytes);
        try writer.writeAll(objects_bytes);
        try writer.writeAll(expirations_bytes);

        // Write entity names
        for (self.entity_names.items) |name| {
            const len: u16 = @intCast(name.len);
            try writer.writeInt(u16, len, .little);
            try writer.writeAll(name);
        }

        // Write relation metadata
        for (self.relation_meta.items) |meta| {
            const len: u16 = @intCast(meta.name.len);
            try writer.writeInt(u16, len, .little);
            try writer.writeAll(meta.name);
            try writer.writeByte(@intFromEnum(meta.rel_type));
        }
    }

    /// Restores the complete World state from a reader.
    pub fn restore_state(self: *World, reader: anytype) !void {
        var header: SnapshotHeader = undefined;
        try reader.readNoEof(std.mem.asBytes(&header));

        if (!std.mem.eql(u8, &header.magic, "BSPK")) {
            return SnapshotError.InvalidMagic;
        }
        if (header.version != 1) {
            return SnapshotError.UnsupportedVersion;
        }
        if (header.facts_len > self.facts.capacity) {
            return SnapshotError.CapacityExceeded;
        }

        self.facts.len = header.facts_len;
        const slice = self.facts.slice();

        const subjects_bytes = std.mem.sliceAsBytes(slice.items(.subject)[0..header.facts_len]);
        const relations_bytes = std.mem.sliceAsBytes(slice.items(.relation)[0..header.facts_len]);
        const objects_bytes = std.mem.sliceAsBytes(slice.items(.object_or_value)[0..header.facts_len]);
        const expirations_bytes = std.mem.sliceAsBytes(slice.items(.expires_at_tick)[0..header.facts_len]);

        try reader.readNoEof(subjects_bytes);
        try reader.readNoEof(relations_bytes);
        try reader.readNoEof(objects_bytes);
        try reader.readNoEof(expirations_bytes);

        var hasher = std.hash.Crc32.init();
        hasher.update(subjects_bytes);
        hasher.update(relations_bytes);
        hasher.update(objects_bytes);
        hasher.update(expirations_bytes);

        if (hasher.final() != header.checksum) {
            return SnapshotError.ChecksumMismatch;
        }

        self.current_tick = header.current_tick;

        // Restore entity names and map
        self.entity_names.clearRetainingCapacity();
        self.entity_map.clearRetainingCapacity();
        const alloc = self.allocator();

        for (0..header.entity_count) |_| {
            const len = try reader.readInt(u16, .little);
            const name_buf = try alloc.alloc(u8, len);
            try reader.readNoEof(name_buf);
            const id_val: u32 = @intCast(self.entity_names.items.len + 1);
            const id = EntityId.from_int(id_val);
            try self.entity_names.append(alloc, name_buf);
            try self.entity_map.put(alloc, name_buf, id);
        }

        // Restore relation metadata and map
        self.relation_meta.clearRetainingCapacity();
        self.relation_map.clearRetainingCapacity();

        for (0..header.relation_count) |_| {
            const len = try reader.readInt(u16, .little);
            const name_buf = try alloc.alloc(u8, len);
            try reader.readNoEof(name_buf);
            const rel_type_byte = try reader.readByte();
            const rel_type: RelationType = @enumFromInt(rel_type_byte);
            const kind_val: u16 = @intCast(self.relation_meta.items.len + 1);
            const kind = RelationKind.from_int(kind_val);
            try self.relation_meta.append(alloc, .{
                .name = name_buf,
                .rel_type = rel_type,
            });
            try self.relation_map.put(alloc, name_buf, kind);
        }
    }

    /// Creates a complete independent deep copy of this World arena (D-003, D-027).
    /// Used by TemporalHypervisor to fork the Tangent Universe from the Primary Universe.
    pub fn clone(self: *const World, backing_allocator: std.mem.Allocator) !World {
        var cloned = try World.init(backing_allocator, self.arena_buffer.len);
        errdefer cloned.deinit();

        var stream_buf = std.ArrayList(u8).init(backing_allocator);
        defer stream_buf.deinit();

        try self.save_state(stream_buf.writer());
        var read_stream = std.io.fixedBufferStream(stream_buf.items);
        try cloned.restore_state(read_stream.reader());

        return cloned;
    }
};

// --- Unit Tests (P1-01, P1-02, P1-03, P1-04) ---

test "P1-01: world init and string interning" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    const guard = try world.intern_entity("Guard");
    const cheese = try world.intern_entity("Cheese");
    const guard_again = try world.intern_entity("Guard");

    try testing.expectEqual(guard, guard_again);
    try testing.expect(guard != cheese);
    try testing.expectEqualStrings("Guard", world.get_entity_name(guard).?);
    try testing.expectEqualStrings("Cheese", world.get_entity_name(cheese).?);

    const carries = try world.intern_relation("Carries", .set);
    const carries_again = try world.intern_relation("Carries", .set);
    try testing.expectEqual(carries, carries_again);
    try testing.expectEqualStrings("Carries", world.get_relation_meta(carries).?.name);
    try testing.expectEqual(RelationType.set, world.get_relation_meta(carries).?.rel_type);
}

test "P1-02: declarative remember, forget, and TTL pruning" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    const guard = try world.intern_entity("Guard");
    const cheese = try world.intern_entity("Cheese");
    const key = try world.intern_entity("Key");
    const carries = try world.intern_relation("Carries", .set);
    const alertness = try world.intern_relation("Alertness", .property);

    // Set relation: multiple items can be carried
    try world.remember(guard, carries, cheese.to_int(), 0); // permanent
    try world.remember(guard, carries, key.to_int(), 10); // expires at tick 10
    try testing.expectEqual(@as(usize, 2), world.fact_count());

    // Property relation: auto-overwrites
    try world.remember(guard, alertness, 100, 0);
    try testing.expectEqual(@as(usize, 3), world.fact_count());
    try testing.expectEqual(@as(u32, 100), world.get_property(guard, alertness).?);

    try world.remember(guard, alertness, 75, 0);
    try testing.expectEqual(@as(usize, 3), world.fact_count()); // count stays 3, value updated
    try testing.expectEqual(@as(u32, 75), world.get_property(guard, alertness).?);

    // Forget key
    try testing.expect(world.forget(guard, carries, key.to_int()));
    try testing.expectEqual(@as(usize, 2), world.fact_count());

    // Add temporary charmed buff
    const bard = try world.intern_entity("Bard");
    const charmed = try world.intern_relation("CharmedBy", .set);
    try world.remember(guard, charmed, bard.to_int(), 5); // expires at current_tick (0) + 5 = 5
    try testing.expectEqual(@as(usize, 3), world.fact_count());

    // Advance 4 ticks: should not expire yet
    _ = world.step_tick(); // tick 1
    _ = world.step_tick(); // tick 2
    _ = world.step_tick(); // tick 3
    _ = world.step_tick(); // tick 4
    try testing.expectEqual(@as(usize, 3), world.fact_count());

    // Advance to tick 5: should expire
    const pruned = world.step_tick(); // tick 5
    try testing.expectEqual(@as(usize, 1), pruned);
    try testing.expectEqual(@as(usize, 2), world.fact_count());
    try testing.expect(!world.has_fact(guard, charmed, bard.to_int()));
}

test "P1-03: pattern matching queries and wildcards" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    const guard = try world.intern_entity("Guard");
    const cat = try world.intern_entity("Cat");
    const cheese = try world.intern_entity("Cheese");
    const bard = try world.intern_entity("Bard");

    const carries = try world.intern_relation("Carries", .set);
    const charmed = try world.intern_relation("CharmedBy", .set);

    try world.remember(guard, carries, cheese.to_int(), 0);
    try world.remember(guard, charmed, bard.to_int(), 0);

    // Exact matches
    try testing.expect(world.has_fact(guard, carries, cheese.to_int()));
    try testing.expect(!world.has_fact(cat, carries, cheese.to_int()));

    // Wildcard matches: where Carries(Guard, _)
    try testing.expect(world.has_fact(guard, carries, null));
    try testing.expect(!world.has_fact(cat, carries, null));

    // Wildcard matches: where CharmedBy(_, Bard)
    try testing.expect(world.has_fact(null, charmed, bard.to_int()));

    // Pattern query finding loot: where Carries(Guard, loot)
    const match = world.find_first(guard, carries, null);
    try testing.expect(match != null);
    try testing.expectEqual(cheese.to_int(), match.?.object_or_value);
}

test "P1-04: deterministic save_state and restore_state" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    const guard = try world.intern_entity("Guard");
    const cheese = try world.intern_entity("Cheese");
    const carries = try world.intern_relation("Carries", .set);
    const alertness = try world.intern_relation("Alertness", .property);

    try world.remember(guard, carries, cheese.to_int(), 0);
    try world.remember(guard, alertness, 100, 0);

    // Advance 12 ticks
    for (0..12) |_| {
        _ = world.step_tick();
    }
    try testing.expectEqual(@as(u64, 12), world.current_tick);

    // Save state to buffer
    var save_stream = std.ArrayList(u8).init(testing.allocator);
    defer save_stream.deinit();
    try world.save_state(save_stream.writer());

    // Mutate world after save: alter alertness, add facts, advance ticks
    try world.remember(guard, alertness, 20, 0);
    const cat = try world.intern_entity("Cat");
    try world.remember(cat, carries, cheese.to_int(), 0);
    for (0..50) |_| {
        _ = world.step_tick();
    }
    try testing.expectEqual(@as(u64, 62), world.current_tick);
    try testing.expectEqual(@as(u32, 20), world.get_property(guard, alertness).?);

    // Restore state from snapshot
    var read_stream = std.io.fixedBufferStream(save_stream.items);
    try world.restore_state(read_stream.reader());

    // Verify tick and state are precisely restored
    try testing.expectEqual(@as(u64, 12), world.current_tick);
    try testing.expectEqual(@as(u32, 100), world.get_property(guard, alertness).?);
    try testing.expect(world.has_fact(guard, carries, cheese.to_int()));
    try testing.expectEqual(@as(usize, 2), world.fact_count());
    // Also verify Cat is gone from restored world
    try testing.expect(!world.has_fact(cat, carries, cheese.to_int()));
}

test "P8-01: multi-clause relational pattern matcher and variable join queries" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    const guard = try world.intern_entity("Guard");
    const bard = try world.intern_entity("Bard");
    const cat = try world.intern_entity("Cat");
    const cheese = try world.intern_entity("Cheese");
    const key = try world.intern_entity("Key");

    const carries = try world.intern_relation("Carries", .set);
    const charmed_by = try world.intern_relation("CharmedBy", .set);
    const in_room = try world.intern_relation("InRoom", .property);
    const tavern = try world.intern_entity("Tavern");
    const cellar = try world.intern_entity("Cellar");

    // Facts:
    // Guard carries Cheese, is CharmedBy Bard, is InRoom Tavern
    try world.remember(guard, carries, cheese.to_int(), 0);
    try world.remember(guard, charmed_by, bard.to_int(), 0);
    try world.remember(guard, in_room, tavern.to_int(), 0);

    // Cat carries Key, is InRoom Tavern
    try world.remember(cat, carries, key.to_int(), 0);
    try world.remember(cat, in_room, tavern.to_int(), 0);

    // Query 1: Join on ?holder (var 0): Carries(?holder, Cheese) and CharmedBy(?holder, Bard)
    const clauses1 = [_]PatternClause{
        .{
            .relation = carries,
            .subject = .{ .variable = 0 },
            .object = .{ .constant = cheese.to_int() },
        },
        .{
            .relation = charmed_by,
            .subject = .{ .variable = 0 },
            .object = .{ .constant = bard.to_int() },
        },
    };

    try testing.expect(world.has_multi_match(&clauses1));
    const match1 = world.find_first_match(&clauses1);
    try testing.expect(match1 != null);
    try testing.expectEqual(guard.to_int(), match1.?.get(0).?);

    // Query 2: Contradictory join: Carries(?holder, Key) and CharmedBy(?holder, Bard)
    // Cat carries Key, but is NOT CharmedBy Bard -> should return null
    const clauses2 = [_]PatternClause{
        .{
            .relation = carries,
            .subject = .{ .variable = 0 },
            .object = .{ .constant = key.to_int() },
        },
        .{
            .relation = charmed_by,
            .subject = .{ .variable = 0 },
            .object = .{ .constant = bard.to_int() },
        },
    };
    try testing.expect(!world.has_multi_match(&clauses2));
    try testing.expect(world.find_first_match(&clauses2) == null);

    // Query 3: Multi-variable join: Carries(?actor, ?item) and InRoom(?actor, Tavern)
    // Both Guard and Cat should match!
    const clauses3 = [_]PatternClause{
        .{
            .relation = carries,
            .subject = .{ .variable = 0 }, // ?actor
            .object = .{ .variable = 1 }, // ?item
        },
        .{
            .relation = in_room,
            .subject = .{ .variable = 0 }, // ?actor
            .object = .{ .constant = tavern.to_int() },
        },
    };

    const all_matches = try world.find_all_matches(testing.allocator, &clauses3);
    defer testing.allocator.free(all_matches);

    try testing.expectEqual(@as(usize, 2), all_matches.len);
    // Verify one of them is Guard with Cheese, and one is Cat with Key
    var found_guard = false;
    var found_cat = false;
    for (all_matches) |m| {
        if (m.get(0).? == guard.to_int() and m.get(1).? == cheese.to_int()) {
            found_guard = true;
        }
        if (m.get(0).? == cat.to_int() and m.get(1).? == key.to_int()) {
            found_cat = true;
        }
    }
    try testing.expect(found_guard);
    try testing.expect(found_cat);

    // Cellar has nobody in it
    const clauses_cellar = [_]PatternClause{
        .{
            .relation = in_room,
            .subject = .{ .variable = 0 },
            .object = .{ .constant = cellar.to_int() },
        },
    };
    try testing.expect(!world.has_multi_match(&clauses_cellar));
}

test "P21-01: transfer_item atomic relational swap and conservation of matter" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    const hoagie = try world.intern_entity("Hoagie");
    const bernard = try world.intern_entity("Bernard");
    const wine = try world.intern_entity("VintageWine");
    const carries = try world.intern_relation("Carries", .set);

    // Initially, Bernard possesses the wine
    _ = try world.remember(bernard, carries, wine.to_int(), 0);
    try testing.expect(world.has_fact(bernard, carries, wine.to_int()));
    try testing.expect(!world.has_fact(hoagie, carries, wine.to_int()));

    // Transfer wine from Bernard to Hoagie
    const ok = try world.transfer_item(wine, bernard, hoagie);
    try testing.expect(ok);

    // Bernard no longer carries wine; Hoagie now carries wine
    try testing.expect(!world.has_fact(bernard, carries, wine.to_int()));
    try testing.expect(world.has_fact(hoagie, carries, wine.to_int()));

    // Attempting to transfer wine from Bernard again fails because Bernard does not possess it
    const ok2 = try world.transfer_item(wine, bernard, hoagie);
    try testing.expect(!ok2);
}

test "P31-01: World.clone creates independent deep copy for Tangent Universe forking" {
    const testing = std.testing;
    var primary = try World.init(testing.allocator, 1024 * 1024);
    defer primary.deinit();

    const donnie = try primary.intern_entity("Donnie");
    const bedroom = try primary.intern_entity("Bedroom");
    const in_room = try primary.intern_relation("InRoom", .property);
    _ = try primary.remember(donnie, in_room, bedroom.to_int(), 0);

    var tangent = try primary.clone(testing.allocator);
    defer tangent.deinit();

    // Verify tangent inherited facts and entity names
    try testing.expectEqual(primary.current_tick, tangent.current_tick);
    try testing.expect(tangent.has_fact(donnie, in_room, bedroom.to_int()));
    try testing.expectEqualStrings("Donnie", tangent.get_entity_name(donnie).?);

    // Mutating tangent does not mutate primary
    const golf_course = try tangent.intern_entity("GolfCourse");
    _ = try tangent.remember(donnie, in_room, golf_course.to_int(), 0);
    _ = tangent.step_tick();

    try testing.expect(tangent.has_fact(donnie, in_room, golf_course.to_int()));
    try testing.expectEqual(@as(u64, 1), tangent.current_tick);
    try testing.expect(primary.has_fact(donnie, in_room, bedroom.to_int()));
    try testing.expectEqual(@as(u64, 0), primary.current_tick);
}
