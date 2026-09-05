//! Reusable typed-handle pools for graph and region experiments. No raw element
//! references escape. Source-language schemas and allocator scopes are separate.
const std = @import("std");
pub const Error = std.mem.Allocator.Error || error{ PoolClosed, ForeignPool, InvalidHandle, CapacityLimit, IdentityExhausted };
var identities: std.atomic.Value(u64) = .init(1);
fn nextIdentity(counter: *std.atomic.Value(u64)) Error!u64 {
    var current = counter.load(.monotonic);
    while (true) {
        if (current == std.math.maxInt(u64)) return error.IdentityExhausted;
        if (counter.cmpxchgWeak(current, current + 1, .monotonic, .monotonic)) |observed| current = observed else return current;
    }
}
/// Tag establishes a nominal handle category without depending on the node layout.
/// Recursive graphs can put Handle(NodeTag) in Node before defining Pool(NodeTag, Node).
pub fn Handle(comptime Tag: type) type {
    return struct {
        pub const Category = Tag;
        pool: u64,
        index: usize,
        generation: u64,
    };
}
pub const Statistics = struct { live: usize = 0, retired: usize = 0, inserted: u64 = 0, removed: u64 = 0 };
/// T must be copyable under Hooks. Retain/release must not fail or reenter the pool.
/// Default hooks suit plain values/handles; reference-counted values supply hooks.
/// The pool and allocator ownership must not be copied after initialization.
pub fn Pool(comptime Tag: type, comptime T: type) type {
    return struct {
        const Self = @This();
        pub const Id = Handle(Tag);
        pub const Hooks = struct {
            retain: *const fn (T) T = retainPlain,
            release: *const fn (T, std.mem.Allocator) void = releasePlain,
        };
        const Entry = struct { generation: u64 = 1, value: ?T = null, next: ?usize = null };
        allocator: std.mem.Allocator,
        identity: u64,
        max_slots: usize,
        hooks: Hooks,
        entries: std.ArrayList(Entry) = .empty,
        free_head: ?usize = null,
        statistics: Statistics = .{},
        fn retainPlain(value: T) T {
            return value;
        }
        fn releasePlain(_: T, _: std.mem.Allocator) void {}
        pub fn init(allocator: std.mem.Allocator, max_slots: usize, hooks: Hooks) Error!Self {
            return .{ .allocator = allocator, .identity = try nextIdentity(&identities), .max_slots = max_slots, .hooks = hooks };
        }
        /// Prepares registry capacity. Slot identities and live values are unchanged
        /// on allocation failure. max_slots bounds issued slots, including retired ones.
        pub fn reserve(self: *Self, count: usize) Error!void {
            if (self.identity == 0) return error.PoolClosed;
            if (count > self.max_slots) return error.CapacityLimit;
            try self.entries.ensureTotalCapacity(self.allocator, count);
        }
        fn entry(self: *Self, id: Id) Error!*Entry {
            if (self.identity == 0) return error.PoolClosed;
            if (id.pool != self.identity) return error.ForeignPool;
            if (id.index >= self.entries.items.len) return error.InvalidHandle;
            const found = &self.entries.items[id.index];
            if (found.generation != id.generation or found.value == null) return error.InvalidHandle;
            return found;
        }
        /// Borrows input ownership. Registry growth occurs before retaining it.
        pub fn insert(self: *Self, value: T) Error!Id {
            if (self.identity == 0) return error.PoolClosed;
            if (self.free_head == null) {
                if (self.entries.items.len >= self.max_slots) return error.CapacityLimit;
                const index = self.entries.items.len;
                try self.entries.append(self.allocator, .{});
                self.free_head = index;
            }
            const index = self.free_head.?;
            const found = &self.entries.items[index];
            self.free_head = found.next;
            found.next = null;
            found.value = self.hooks.retain(value);
            self.statistics.live += 1;
            self.statistics.inserted +|= 1;
            return .{ .pool = self.identity, .index = index, .generation = found.generation };
        }
        /// Returns an independent snapshot under Hooks; callers release retained
        /// snapshots with the same policy. No pointer to movable slot storage escapes.
        pub fn get(self: *Self, id: Id) Error!T {
            return self.hooks.retain((try self.entry(id)).value.?);
        }
        pub fn replace(self: *Self, id: Id, value: T) Error!void {
            const found = try self.entry(id);
            const retained = self.hooks.retain(value);
            self.hooks.release(found.value.?, self.allocator);
            found.value = retained;
        }
        fn removeIndex(self: *Self, index: usize) void {
            const found = &self.entries.items[index];
            self.hooks.release(found.value.?, self.allocator);
            found.value = null;
            if (found.generation == std.math.maxInt(u64)) {
                self.statistics.retired += 1;
            } else {
                found.generation += 1;
                found.next = self.free_head;
                self.free_head = index;
            }
            self.statistics.live -= 1;
            self.statistics.removed +|= 1;
        }
        pub fn remove(self: *Self, id: Id) Error!void {
            _ = try self.entry(id);
            self.removeIndex(id.index);
        }
        /// Bulk invalidation keeps allocated slot capacity for reuse. Payloads
        /// release in descending slot order; graph edges are inert typed IDs.
        pub fn clear(self: *Self) Error!void {
            if (self.identity == 0) return error.PoolClosed;
            var index = self.entries.items.len;
            while (index != 0) {
                index -= 1;
                if (self.entries.items[index].value != null) self.removeIndex(index);
            }
        }
        pub fn deinit(self: *Self) void {
            if (self.identity == 0) return;
            self.clear() catch unreachable;
            self.entries.deinit(self.allocator);
            self.entries = .empty;
            self.free_head = null;
            self.identity = 0;
        }
    };
}

test "pool identity allocation never wraps" {
    var counter: std.atomic.Value(u64) = .init(std.math.maxInt(u64) - 1);
    try std.testing.expectEqual(std.math.maxInt(u64) - 1, try nextIdentity(&counter));
    try std.testing.expectError(error.IdentityExhausted, nextIdentity(&counter));
}
