//! Checked arena lifetimes shared by buffer and pool backing. Region metadata and
//! snapshots use the execution allocator; an arena owns only reserved storage.
const std = @import("std");
const pools = @import("typed_pool.zig");
const Tag = struct {};
pub const Id = pools.Handle(Tag);
pub const Error = std.mem.Allocator.Error || error{ InvalidCapability, CapacityLimit, IdentityExhausted, RegionInUse, ChildrenActive };
const Region = struct {
    arena: std.heap.ArenaAllocator,
    parent: ?Id,
    users: usize = 0,
    children: usize = 0,
};
const Registry = pools.Pool(Tag, *Region);
/// Generation-checked region registry with parent/child and retained backing lifetime accounting.
pub const RegionStore = struct {
    allocator: std.mem.Allocator,
    registry: Registry,
    /// Optional chunk allocator; metadata continues to use allocator.
    backing_allocator: ?std.mem.Allocator = null,

    /// Initialize an empty region registry with a maximum number of live region slots.
    pub fn init(allocator: std.mem.Allocator, max_regions: usize) Error!RegionStore {
        return .{ .allocator = allocator, .registry = try Registry.init(allocator, max_regions, .{}) };
    }
    fn get(self: *RegionStore, id: Id) Error!*Region {
        return self.registry.get(id) catch return error.InvalidCapability;
    }
    /// Reject a stale or unknown region identity without changing region state.
    pub fn check(self: *RegionStore, id: Id) Error!void {
        _ = try self.get(id);
    }
    /// Create a child region after validating its parent and capacity; return its generation-checked identity.
    pub fn begin(self: *RegionStore, parent: ?Id) Error!Id {
        const ancestor = if (parent) |id| try self.get(id) else null;
        if (ancestor) |region| if (region.children == std.math.maxInt(usize)) return error.CapacityLimit;
        const region = try self.allocator.create(Region);
        errdefer self.allocator.destroy(region);
        // Each arena owns independent chunks from the execution allocator. The
        // parent relation constrains lifetime, not the allocator of those chunks.
        region.* = .{ .arena = .init(self.backing_allocator orelse self.allocator), .parent = parent };
        const id = self.registry.insert(region) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.CapacityLimit => error.CapacityLimit,
            else => error.InvalidCapability,
        };
        if (ancestor) |outer| outer.children += 1;
        return id;
    }
    /// Acquire before allocating backing. Every retained user must release before
    /// the scope can end, including zero-capacity buffers and pools.
    pub fn retain(self: *RegionStore, id: Id) Error!std.mem.Allocator {
        const region = try self.get(id);
        if (region.users == std.math.maxInt(usize)) return error.CapacityLimit;
        region.users += 1;
        return region.arena.allocator();
    }
    /// Drop one previously retained backing user; the region must still be live.
    pub fn release(self: *RegionStore, id: Id) void {
        // A retained backing lease prevents end/reset of this exact region.
        std.debug.assert(id.pool == self.registry.identity);
        std.debug.assert(id.index < self.registry.entries.items.len);
        const entry = self.registry.entries.items[id.index];
        std.debug.assert(entry.generation == id.generation);
        std.debug.assert(entry.value != null);
        const region = entry.value.?;
        std.debug.assert(region.users != 0);
        region.users -= 1;
    }
    /// Release unused chunks without closing the scope or changing its authority.
    /// No owner/child may still depend on the backing; rejection changes nothing.
    /// Retained snapshots use the execution allocator and remain independent.
    pub fn reset(self: *RegionStore, id: Id) Error!void {
        const region = try self.get(id);
        if (region.children != 0) return error.ChildrenActive;
        if (region.users != 0) return error.RegionInUse;
        region.arena.deinit();
        region.arena = .init(self.backing_allocator orelse self.allocator);
    }
    /// Preflight all lifetime constraints; rejection leaves authority and backing
    /// unchanged. Success invalidates the capability even if its slot is reused.
    pub fn end(self: *RegionStore, id: Id) Error!void {
        const region = try self.get(id);
        if (region.children != 0) return error.ChildrenActive;
        if (region.users != 0) return error.RegionInUse;
        const parent = if (region.parent) |id_parent| try self.get(id_parent) else null;
        self.registry.remove(id) catch return error.InvalidCapability;
        if (parent) |ancestor| ancestor.children -= 1;
        region.arena.deinit();
        self.allocator.destroy(region);
    }
    /// Terminal cleanup after all storage users have unwound. Chunk independence
    /// permits teardown in registry order even when scopes ended out of order.
    pub fn deinit(self: *RegionStore) void {
        if (self.registry.identity == 0) return;
        for (self.registry.entries.items) |entry| if (entry.value) |region| {
            std.debug.assert(region.users == 0);
            region.arena.deinit();
            self.allocator.destroy(region);
        };
        self.registry.deinit();
    }
};
