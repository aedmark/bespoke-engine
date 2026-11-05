<!-- Moved to archive 2026-11-04 upon adoption of The Manifold; superseding canonical document is docs/ARCHITECTURE.md -->

# Architecture Specification: The Engine-as-Spine Model (Initial Notes)

## 1. Runtime Ownership
Instead of embedding a script engine inside Unity or Godot, **our Zig runtime is `main()`**. 
- The VM owns the world clock, entity lifecycles, and relational tables.
- The multimedia layer (e.g., Raylib or Sokol) is a stateless display loop that reads a read-only slice of the VM state each frame to draw sprites and play sound cues.

## 2. Memory Layout & Core Structs (Zig)
Relational facts are stored using Zig's native `std.MultiArrayList` for optimal CPU cache utilization:

```zig
const std = @import("std");

pub const EntityId = enum(u32) {
    none = 0,
    _,
};

pub const RelationKind = enum(u16) {
    _,
};

pub const Fact = struct {
    subject: EntityId,
    relation: RelationKind,
    object: EntityId,
    expires_at_tick: u64, // 0 = permanent
};

pub const World = struct {
    facts: std.MultiArrayList(Fact),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) World {
        return .{
            .facts = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *World) void {
        self.facts.deinit(self.allocator);
    }
};
```

## 3. Serialization & Save States
Because the entire world state lives in contiguous Zig memory arenas, saving the game, reloading scripts, or rewinding time is accomplished via clean memory snapshots (`memcpy`) without complex object graph serialization.
