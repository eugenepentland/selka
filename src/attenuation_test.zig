const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const resources = @import("external_resources.zig");
const external = @import("external_capabilities.zig");
const read_only = resources.permissionBit(.read);
const Fake = struct {
    granted: resources.Permissions = 255,
    acquisitions: usize = 0,
    reads: usize = 0,
    writes: usize = 0,
    completions: usize = 0,
    releases: usize = 0,
    live: usize = 0,
    fn acquire(context: *anyopaque, request: []const u8, permissions: resources.Permissions) external.CallError!u64 {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.granted = permissions;
        if (std.mem.eql(u8, request, "write") and permissions & resources.permissionBit(.write) == 0) return error.Denied;
        self.acquisitions += 1;
        self.live += 1;
        return self.acquisitions;
    }
    fn read(context: *anyopaque, _: u64, _: []u8) external.CallError!resources.Read {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.reads += 1;
        return .{ .length = 0, .eof = true };
    }
    fn write(context: *anyopaque, _: u64, input: []const u8) external.CallError!usize {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.writes += 1;
        return input.len;
    }
    fn complete(context: *anyopaque, _: u64) external.CallError!void {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.completions += 1;
        self.live -= 1;
    }
    fn release(context: *anyopaque, _: u64) void {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.releases += 1;
        self.live -= 1;
    }
    fn provider(self: *Fake) resources.Provider {
        return .{ .context = self, .acquire = acquire, .read = read, .write = write, .complete = complete, .release = release };
    }
};
const source = "resource File: filesystem; result Open { ok: File, err: i64 } struct Chunk { bytes: [0]u8, length: u64, eof: bool } result Read { ok: Chunk, err: i64 } result Written { ok: u64, err: i64 } struct Failure { resource: File, code: i64 } result Finish { ok: bool, err: Failure } struct Authority { fs: filesystem_cap } fn delegate(fs: filesystem_cap) -> Authority effects() { return new Authority { fs: restrict_resource<read>(fs) }; } fn widen(auth: Authority) -> filesystem_cap effects() { return restrict_resource<read, write, complete>(auth.fs); } fn main(fs: filesystem_cap) -> i64 { let limited = widen(delegate(fs)); match acquire_resource<Open>(limited, new [0]u8 []) { Open.ok(input) => { let mut file = input; acknowledge read_resource<Read>(file); match write_resource<Written>(file, new [0]u8 []) { Written.ok(count) => { discard count; return 99; }, Written.err(code) => { if code != 2 { return 98; } } } match complete_resource<Finish>(file) { Finish.ok(done) => { discard done; return 97; }, Finish.err(failure) => { return failure.code; } } }, Open.err(code) => { return -code; } } }";
fn scenario(allocator: std.mem.Allocator) !void {
    var fake: Fake = .{};
    defer std.debug.assert(fake.live == 0);
    var c = try language.Compilation.init(allocator, "attenuation.my", source);
    defer c.deinit();
    try t.expectEqual(@as(i64, 2), (try c.executeWithOptions(allocator, .{ .resources = .{ .filesystem = fake.provider() } })).value);
    try t.expectEqual(read_only, fake.granted);
    try t.expectEqual(@as(usize, 1), fake.reads);
    try t.expectEqual(@as(usize, 0), fake.writes);
    try t.expectEqual(@as(usize, 0), fake.completions);
    try t.expectEqual(@as(usize, 1), fake.releases);
    const dump = try c.dump(allocator);
    defer allocator.free(dump);
    try t.expect(std.mem.indexOf(u8, dump, "RESTRICT_RESOURCE permissions=1") != null);
    var discovery = try language.duplicates.discover(allocator, c.program.?, .{ .min_nodes = 1 });
    defer discovery.deinit();
}
test "source attenuation forwards restricted authority through wrappers and cannot restore removed rights" {
    try scenario(t.allocator);
}
test "embedding entry permissions cap source grants before provider acquisition" {
    var fake: Fake = .{};
    var c = try language.Compilation.init(t.allocator, "attenuation.my", source);
    defer c.deinit();
    try t.expectEqual(@as(i64, 2), (try c.executeWithOptions(t.allocator, .{ .resources = .{ .filesystem = fake.provider(), .filesystem_permissions = 0 } })).value);
    try t.expectEqual(@as(resources.Permissions, 0), fake.granted);
    try t.expectEqual(@as(usize, 0), fake.reads);
    try t.expectEqual(@as(usize, 0), fake.writes);
    try t.expectEqual(@as(usize, 1), fake.releases);
}
test "backend attenuation preserves parent authority quotas transfers and slot reuse" {
    var fake: Fake = .{};
    var store = try resources.Store.init(t.allocator, .network, fake.provider(), 2);
    defer store.deinit();
    const full = try store.grant();
    const limited = try store.restrict(full, read_only);
    const widened = try store.restrict(limited, resources.all_permissions);
    try t.expectEqual(read_only, widened.permissions);
    try t.expectError(error.Denied, store.acquire(limited, "write"));
    try t.expectEqual(@as(usize, 0), fake.acquisitions);
    const parent_owner = try store.acquire(full, "");
    const child_owner = try store.acquire(widened, "");
    try t.expectError(error.ResourceLimit, store.acquire(limited, ""));
    const moved = try store.transfer(child_owner);
    try t.expectError(error.Denied, store.write(moved, "data"));
    try t.expectError(error.Denied, store.complete(moved));
    try t.expectEqual(@as(usize, 4), try store.write(parent_owner, "data"));
    try store.release(moved);
    const reused = try store.acquire(full, "");
    try t.expectEqual(child_owner.index, reused.index);
    try store.complete(reused);
    try store.complete(parent_owner);
    try t.expectEqual(@as(usize, 0), fake.live);
}
test "invalid foreign and closed restrictions fail without invoking providers" {
    var fake: Fake = .{};
    var first = try resources.Store.init(t.allocator, .filesystem, fake.provider(), 1);
    defer first.deinit();
    var other = try resources.Store.init(t.allocator, .filesystem, fake.provider(), 1);
    defer other.deinit();
    const cap = try first.grant();
    try t.expectError(error.InvalidCapability, first.restrict(cap, 8));
    try t.expectError(error.InvalidCapability, other.restrict(cap, read_only));
    first.deinit();
    try t.expectError(error.Closed, first.restrict(cap, read_only));
    try t.expectEqual(@as(usize, 0), fake.acquisitions);
}
fn reject(text: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "invalid.my", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
test "source attenuation validates permissions and capability kinds" {
    try reject("fn main(fs: filesystem_cap) -> i64 { discard restrict_resource<read, read>(fs); return 0; }", "E_PERMISSION");
    try reject("fn main(fs: filesystem_cap) -> i64 { discard restrict_resource<execute>(fs); return 0; }", "E_PERMISSION");
    try reject("fn main(heap: allocator) -> i64 { discard restrict_resource<read>(heap); return 0; }", "E_TYPE");
    var c = try language.Compilation.init(t.allocator, "empty.my", "fn main(fs: filesystem_cap) -> i64 effects() { discard restrict_resource<>(fs); return 7; }");
    defer c.deinit();
    var fake: Fake = .{};
    try t.expectEqual(@as(i64, 7), (try c.executeWithOptions(t.allocator, .{ .resources = .{ .filesystem = fake.provider() } })).value);
    try t.expectEqual(@as(usize, 0), fake.acquisitions);
}
test "attenuated acquisition and denied completion clean up every failed allocation" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), scenario, .{});
}
test "emission and discovery preserve permission sets and reject invalid masks" {
    var c = try language.Compilation.init(t.allocator, "duplicates.my", "fn a(fs: filesystem_cap) -> filesystem_cap { return restrict_resource<read, write>(fs); } fn b(dir: filesystem_cap) -> filesystem_cap { return restrict_resource<write, read>(dir); } fn c(fs: filesystem_cap) -> filesystem_cap { return restrict_resource<read>(fs); } fn main() -> i64 { return 0; }");
    defer c.deinit();
    try c.check();
    var discovery = try language.duplicates.discover(t.allocator, c.program.?, .{ .min_nodes = 1 });
    defer discovery.deinit();
    try t.expectEqual(@as(usize, 1), discovery.groups.len);
    try t.expectEqual(@as(usize, 2), discovery.groups[0].members.len);
    try c.emit();
    for (@constCast(c.code.?.functions[0].instructions)) |*instruction| if (instruction.op == .restrict_resource) {
        const original = instruction.*;
        instruction.op.restrict_resource.permissions = 128;
        try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
        instruction.* = original;
        return;
    };
    return error.TestUnexpectedResult;
}
