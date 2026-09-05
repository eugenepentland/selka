const std = @import("std");
const t = std.testing;
const resources = @import("external_resources.zig");
const external = @import("external_capabilities.zig");
const Fake = struct {
    next: u64 = 0,
    live: usize = 0,
    acquire_calls: usize = 0,
    complete_calls: usize = 0,
    release_calls: usize = 0,
    fail_acquire: ?external.CallError = null,
    fail_complete: ?external.CallError = null,
    events: [16]u64 = @splat(0),
    fn acquire(context: *anyopaque, request: []const u8, _: resources.Permissions) external.CallError!u64 {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.acquire_calls += 1;
        if (self.fail_acquire) |err| return err;
        if (!std.mem.eql(u8, request, "restricted target")) return error.Denied;
        self.next += 1;
        self.live += 1;
        return self.next;
    }
    fn complete(context: *anyopaque, _: u64) external.CallError!void {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.complete_calls += 1;
        if (self.fail_complete) |err| return err;
        self.live -= 1;
    }
    fn release(context: *anyopaque, handle: u64) void {
        const self: *Fake = @ptrCast(@alignCast(context));
        if (self.release_calls < self.events.len) self.events[self.release_calls] = handle;
        self.release_calls += 1;
        self.live -= 1;
    }
    fn provider(self: *Fake) resources.Provider {
        return .{ .context = self, .acquire = acquire, .complete = complete, .release = release };
    }
};
const target = "restricted target";
test "external partial acquisition unwinds once without implying completion" {
    var fake: Fake = .{};
    var store = try resources.Store.init(t.allocator, .filesystem, fake.provider(), 4);
    defer store.deinit();
    const cap = try store.grant();
    _ = try store.acquire(cap, target);
    fake.fail_acquire = error.Failed;
    try t.expectError(error.Failed, store.acquire(cap, target));
    store.deinit();
    try t.expectEqual(@as(usize, 0), fake.live);
    try t.expectEqual(@as(usize, 1), fake.release_calls);
    try t.expectEqual(@as(usize, 0), fake.complete_calls);
}
test "failed completion retains authority for retry while successful completion consumes owner" {
    var fake: Fake = .{};
    var store = try resources.Store.init(t.allocator, .filesystem, fake.provider(), 1);
    defer store.deinit();
    const owner = try store.acquire(try store.grant(), target);
    for ([_]external.CallError{ error.Unavailable, error.Denied, error.Failed, error.OutOfMemory }) |err| {
        fake.fail_complete = err;
        try t.expectError(err, store.complete(owner));
        try t.expectEqual(@as(usize, 1), store.statistics.live);
        try t.expectEqual(@as(usize, 1), fake.live);
    }
    fake.fail_complete = null;
    try store.complete(owner);
    try t.expectError(error.InvalidOwner, store.complete(owner));
    try t.expectError(error.InvalidOwner, store.release(owner));
    store.deinit();
    try t.expectEqual(@as(usize, 0), fake.release_calls);
    try t.expectEqual(@as(u64, 1), store.statistics.completed);
}
test "fallback release follows failed completion and is never retried by deinit" {
    var fake: Fake = .{ .fail_complete = error.Failed };
    var store = try resources.Store.init(t.allocator, .network, fake.provider(), 1);
    defer store.deinit();
    const owner = try store.acquire(try store.grant(), target);
    try t.expectError(error.Failed, store.complete(owner));
    try store.release(owner);
    store.deinit();
    try t.expectEqual(@as(usize, 1), fake.release_calls);
    try t.expectEqual(@as(usize, 0), fake.live);
    try t.expectEqual(@as(u64, 0), store.statistics.completed);
}
test "reverse acquisition cleanup survives slot recycling middle removal and transfers" {
    var fake: Fake = .{};
    var store = try resources.Store.init(t.allocator, .filesystem, fake.provider(), 4);
    defer store.deinit();
    const cap = try store.grant();
    const a = try store.acquire(cap, target);
    const b = try store.acquire(cap, target);
    _ = try store.acquire(cap, target);
    try store.release(b);
    const d = try store.acquire(cap, target);
    try t.expectEqual(b.index, d.index);
    const moved = try store.transfer(a);
    try t.expectError(error.InvalidOwner, store.release(a));
    try t.expectError(error.InvalidOwner, store.release(b));
    try t.expectEqual(a.index, moved.index);
    store.deinit();
    try t.expectEqualSlices(u64, &.{ 2, 4, 3, 1 }, fake.events[0..4]);
    try t.expectEqual(@as(usize, 0), fake.live);
}
test "capability kind store identity limits and closed stores reject before provider calls" {
    var fake: Fake = .{};
    var first = try resources.Store.init(t.allocator, .filesystem, fake.provider(), 1);
    defer first.deinit();
    var second = try resources.Store.init(t.allocator, .filesystem, fake.provider(), 1);
    defer second.deinit();
    const cap = try first.grant();
    try t.expectError(error.InvalidCapability, second.acquire(cap, target));
    var wrong = cap;
    wrong.kind = .network;
    try t.expectError(error.InvalidCapability, first.acquire(wrong, target));
    try t.expectEqual(@as(usize, 0), fake.acquire_calls);
    const owner = try first.acquire(cap, target);
    try t.expectError(error.ResourceLimit, first.acquire(cap, target));
    try t.expectError(error.InvalidOwner, second.complete(owner));
    try t.expectEqual(@as(usize, 1), fake.acquire_calls);
    first.deinit();
    try t.expectError(error.Closed, first.acquire(cap, target));
    try t.expectError(error.Closed, first.release(owner));
}
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var fake: Fake = .{};
    defer std.debug.assert(fake.live == 0);
    var store = try resources.Store.init(allocator, .filesystem, fake.provider(), 100);
    defer store.deinit();
    const cap = try store.grant();
    for (0..40) |_| _ = try store.acquire(cap, target);
}
test "bookkeeping allocation failures never strand successful host acquisitions" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
}
test "move completion release and unwind do not allocate registry storage" {
    var fake: Fake = .{};
    var failing = t.FailingAllocator.init(t.allocator, .{});
    var store = try resources.Store.init(failing.allocator(), .network, fake.provider(), 3);
    defer store.deinit();
    const cap = try store.grant();
    const a = try store.acquire(cap, target);
    const b = try store.acquire(cap, target);
    _ = try store.acquire(cap, target);
    failing.fail_index = failing.alloc_index;
    try store.complete(try store.transfer(a));
    try store.release(b);
    store.deinit();
    try t.expectEqual(@as(usize, 0), fake.live);
    try t.expectEqual(@as(usize, 2), fake.release_calls);
}
test "recycled external registry has bounded live memory" {
    var fake: Fake = .{};
    var limited: @import("test_support.zig").LimitedLiveAllocator = .{ .parent = t.allocator, .limit = 4096 };
    var store = try resources.Store.init(limited.allocator(), .network, fake.provider(), 1);
    defer store.deinit();
    const cap = try store.grant();
    for (0..10000) |_| {
        const owner = try store.acquire(cap, target);
        try store.release(try store.transfer(owner));
    }
    try t.expectEqual(@as(usize, 1), store.entries.items.len);
    store.deinit();
    try t.expectEqual(@as(usize, 0), limited.live);
    try t.expectEqual(@as(usize, 0), fake.live);
}

test "external scopes move cleanup obligations and retain failed completion" {
    var fake: Fake = .{};
    var store = try resources.Store.init(t.allocator, .filesystem, fake.provider(), 4);
    defer store.deinit();
    var outer = resources.Scope.init(&store);
    defer outer.deinit();
    var inner = resources.Scope.init(&store);
    defer inner.deinit();
    const cap = try store.grant();
    _ = try outer.acquire(cap, target);
    const b = try inner.acquire(cap, target);
    _ = try inner.acquire(cap, target);
    const transferred = try inner.moveTo(b, &outer);
    try t.expectError(error.InvalidOwner, inner.release(b));
    inner.deinit();
    fake.fail_complete = error.Failed;
    try t.expectError(error.Failed, outer.complete(transferred));
    try t.expectEqual(@as(usize, 2), outer.owners.items.len);
    outer.deinit();
    try t.expectEqualSlices(u64, &.{ 3, 2, 1 }, fake.events[0..3]);
    try t.expectEqual(@as(usize, 0), fake.live);
}
test "failed destination bookkeeping preserves source ownership and take survives scope cleanup" {
    var fake: Fake = .{};
    var failing = t.FailingAllocator.init(t.allocator, .{});
    var store = try resources.Store.init(failing.allocator(), .network, fake.provider(), 2);
    defer store.deinit();
    var source = resources.Scope.init(&store);
    defer source.deinit();
    var destination = resources.Scope.init(&store);
    defer destination.deinit();
    const owner = try source.acquire(try store.grant(), target);
    failing.fail_index = failing.alloc_index;
    try t.expectError(error.OutOfMemory, source.moveTo(owner, &destination));
    try t.expectEqual(@as(usize, 1), source.owners.items.len);
    try t.expectEqual(@as(usize, 0), destination.owners.items.len);
    const taken = try source.take(owner);
    source.deinit();
    try t.expectEqual(@as(usize, 1), fake.live);
    try t.expectError(error.OutOfMemory, destination.adopt(taken));
    try store.complete(taken);
    try t.expectEqual(@as(usize, 0), fake.live);
}
fn scopeScenario(allocator: std.mem.Allocator) !void {
    var fake: Fake = .{};
    defer std.debug.assert(fake.live == 0);
    var store = try resources.Store.init(allocator, .filesystem, fake.provider(), 30);
    defer store.deinit();
    var source = resources.Scope.init(&store);
    defer source.deinit();
    var destination = resources.Scope.init(&store);
    defer destination.deinit();
    const cap = try store.grant();
    for (0..20) |_| {
        const owner = try source.acquire(cap, target);
        _ = try source.moveTo(owner, &destination);
    }
    const external_owner = try destination.take(destination.owners.items[0]);
    const adopted = try source.adopt(external_owner);
    try source.complete(adopted);
}
test "all scoped acquisition and transfer allocation failures release resources" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), scopeScenario, .{});
}
test "exhausted generations retain live owners and retire released slots without wrapping" {
    var fake: Fake = .{};
    var store = try resources.Store.init(t.allocator, .filesystem, fake.provider(), 1);
    defer store.deinit();
    const cap = try store.grant();
    var owner = try store.acquire(cap, target);
    store.entries.items[owner.index].generation = std.math.maxInt(u64);
    owner.generation = std.math.maxInt(u64);
    try t.expectError(error.IdentityExhausted, store.transfer(owner));
    try store.release(owner);
    const next = try store.acquire(cap, target);
    try t.expect(next.index != owner.index);
    try t.expectEqual(@as(u64, 1), next.generation);
    try t.expectError(error.InvalidOwner, store.complete(owner));
    try store.complete(next);
}
