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
pub const Manager = struct {
    allocator: std.mem.Allocator,
    registry: Registry,

    pub fn init(allocator: std.mem.Allocator, max_regions: usize) Error!Manager {
        return .{ .allocator = allocator, .registry = Registry.init(allocator, max_regions, .{}) catch return error.IdentityExhausted };
    }
    fn get(self: *Manager, id: Id) Error!*Region {
        return self.registry.get(id) catch return error.InvalidCapability;
    }
    pub fn check(self: *Manager, id: Id) Error!void {
        _ = try self.get(id);
    }
    pub fn begin(self: *Manager, parent: ?Id) Error!Id {
        const ancestor = if (parent) |id| try self.get(id) else null;
        if (ancestor) |region| if (region.children == std.math.maxInt(usize)) return error.CapacityLimit;
        const region = try self.allocator.create(Region);
        errdefer self.allocator.destroy(region);
        // Each arena owns independent chunks from the execution allocator. The
        // parent relation constrains lifetime, not the allocator of those chunks.
        region.* = .{ .arena = .init(self.allocator), .parent = parent };
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
    pub fn retain(self: *Manager, id: Id) Error!std.mem.Allocator {
        const region = try self.get(id);
        if (region.users == std.math.maxInt(usize)) return error.CapacityLimit;
        region.users += 1;
        return region.arena.allocator();
    }
    pub fn release(self: *Manager, id: Id) void {
        const region = self.get(id) catch unreachable;
        std.debug.assert(region.users != 0);
        region.users -= 1;
    }
    /// Release unused chunks without closing the scope or changing its authority.
    /// No owner/child may still depend on the backing; rejection changes nothing.
    /// Retained snapshots use the execution allocator and remain independent.
    pub fn reset(self: *Manager, id: Id) Error!void {
        const region = try self.get(id);
        if (region.children != 0) return error.ChildrenActive;
        if (region.users != 0) return error.RegionInUse;
        region.arena.deinit();
        region.arena = .init(self.allocator);
    }
    /// Preflight all lifetime constraints; rejection leaves authority and backing
    /// unchanged. Success invalidates the capability even if its slot is reused.
    pub fn end(self: *Manager, id: Id) Error!void {
        const region = try self.get(id);
        if (region.children != 0) return error.ChildrenActive;
        if (region.users != 0) return error.RegionInUse;
        if (region.parent) |parent| (try self.get(parent)).children -= 1;
        self.registry.remove(id) catch unreachable;
        region.arena.deinit();
        self.allocator.destroy(region);
    }
    /// Terminal cleanup after all storage users have unwound. Chunk independence
    /// permits teardown in registry order even when scopes ended out of order.
    pub fn deinit(self: *Manager) void {
        if (self.registry.identity == 0) return;
        for (self.registry.entries.items) |entry| if (entry.value) |region| {
            std.debug.assert(region.users == 0);
            region.arena.deinit();
            self.allocator.destroy(region);
        };
        self.registry.deinit();
    }
};
