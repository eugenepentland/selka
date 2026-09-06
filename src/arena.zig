//! Arena backing for checked guest buffers and pools. The runtime allocator owns retained
//! payloads and registries so independent snapshots can survive a region reset.
const std = @import("std");
const memory = @import("memory.zig");
/// Chunked guest backing allocator used to reclaim region storage as a unit.
pub const Arena = struct {
    backing: std.heap.ArenaAllocator,
    store: memory.Store,

    /// Initialize at the final address: Store's backing allocator points into self.
    /// Do not copy or move an initialized Arena. Parent must outlive all snapshots.
    pub fn init(self: *Arena, parent: std.mem.Allocator, limits: memory.Limits) memory.Error!void {
        const store = try memory.Store.initWithLimits(parent, limits);
        self.* = .{ .backing = .init(parent), .store = store };
        self.store.backing.allocator = self.backing.allocator();
    }
    /// Failure due to outstanding borrows leaves the entire region unchanged.
    /// On success all owners are invalidated even if capacity retention returns
    /// false. That boolean only reports the host allocator's retention outcome.
    pub fn reset(self: *Arena, mode: std.heap.ArenaAllocator.ResetMode) memory.Error!bool {
        try self.store.reset();
        return self.backing.reset(mode);
    }
    /// External pool owners/backing leases must release first. Terminal cleanup
    /// invalidates outstanding buffer borrows, then frees backing.
    pub fn deinit(self: *Arena) void {
        if (self.store.identity == 0) return;
        self.store.deinit();
        self.backing.deinit();
    }
};
