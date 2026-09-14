//! Environment capability contracts, bounded provider output and generic execution tests.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const env = @import("environment.zig");
const declarations =
    \\class Entry:
    \\    present: bool
    \\    bytes: [4]u8
    \\    length: u64
    \\
    \\
    \\result Lookup:
    \\    err: i64,
    \\    ok: Entry
    \\
    \\
    \\
;
const Fake = struct {
    calls: usize = 0,
    value: ?[]const u8 = "\x00\xff",
    failure: ?env.CallError = null,
    invalid_length: bool = false,
    fn get(context: *anyopaque, name: []const u8, output: []u8) env.CallError!?usize {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.calls += 1;
        if (!std.mem.eql(u8, name, "K")) return error.Denied;
        if (self.failure) |err| return err;
        @memset(output, 99); // Runtime must clear all unspecified tail/missing bytes.
        if (self.invalid_length) return output.len + 1;
        const value = self.value orelse return null;
        if (value.len > output.len) return error.NoCapacity;
        @memcpy(output[0..value.len], value);
        return value.len;
    }
    fn provider(self: *Fake) env.Provider {
        return .{ .context = self, .get = get };
    }
};
fn reject(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "environment.my", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
const forwarded = declarations ++
    \\class Authority:
    \\    env: environment_cap
    \\
    \\
    \\def lookup(auth: Authority) -> Lookup effects(environment):
    \\    return environment_get[Lookup](auth.env, [75u8])
    \\
    \\
    \\def main(environment: environment_cap) -> i64 noio:
    \\    match lookup(Authority(env=environment)):
    \\        case Lookup.ok(entry):
    \\            if entry.present:
    \\                return 10 + i64(entry.length) + i64(entry.bytes[3])
    \\            else:
    \\                return i64(entry.length) + i64(entry.bytes[0])
    \\        case Lookup.err(code):
    \\            return -code
;
fn scenario(allocator: std.mem.Allocator) !void {
    var fake: Fake = .{};
    var c = try language.Compilation.init(allocator, "environment.my", forwarded);
    defer c.deinit();
    try t.expectEqual(@as(i64, 12), (try c.executeWithOptions(allocator, .{ .environment = fake.provider() })).value);
    try t.expectEqual(@as(usize, 1), fake.calls);
    const dump = try c.dump(allocator);
    defer allocator.free(dump);
    try t.expect(std.mem.indexOf(u8, dump, "ENVIRONMENT_GET") != null);
    var duplicates = try language.duplicates.discover(allocator, c.program.?, .{ .min_nodes = 1 });
    defer duplicates.deinit();
}
// spec: OWN-10
test "environment grants delegate explicitly and missing empty and present values remain distinct" {
    try scenario(t.allocator);
    var c = try language.Compilation.init(t.allocator, "environment.my", forwarded);
    defer c.deinit();
    var fake: Fake = .{ .value = null };
    try t.expectEqual(@as(i64, 0), (try c.executeWithOptions(t.allocator, .{ .environment = fake.provider() })).value);
    fake.value = "";
    try t.expectEqual(@as(i64, 10), (try c.executeWithOptions(t.allocator, .{ .environment = fake.provider() })).value);
    fake.value = "12345";
    try t.expectEqual(@as(i64, -4), (try c.executeWithOptions(t.allocator, .{ .environment = fake.provider() })).value);
    try t.expectEqual(@as(usize, 3), fake.calls);
}
test "environment returns raw bytes and canonical zero padding" {
    var c = try language.Compilation.init(t.allocator, "bytes.my", declarations ++
        \\def main(env: environment_cap) -> i64:
        \\    match environment_get[Lookup](env, [75u8]):
        \\        case Lookup.ok(entry):
        \\            return i64(entry.bytes[0]) + i64(entry.bytes[1]) + i64(entry.bytes[2]) + i64(entry.bytes[3])
        \\        case Lookup.err(code):
        \\            return -code
    );
    defer c.deinit();
    var fake: Fake = .{};
    try t.expectEqual(@as(i64, 255), (try c.executeWithOptions(t.allocator, .{ .environment = fake.provider() })).value);
}
test "readValue maps environment provider failures while propagating host OOM and invalid counts" {
    var c = try language.Compilation.init(t.allocator, "environment.my", forwarded);
    defer c.deinit();
    for ([_]env.CallError{ error.Unavailable, error.Denied, error.Failed, error.NoCapacity, error.OutOfMemory }, 1..) |failure, code| {
        var fake: Fake = .{ .failure = failure };
        if (failure == error.OutOfMemory) {
            try t.expectError(error.OutOfMemory, c.executeWithOptions(t.allocator, .{ .environment = fake.provider() }));
        } else try t.expectEqual(-@as(i64, @intCast(code)), (try c.executeWithOptions(t.allocator, .{ .environment = fake.provider() })).value);
        try t.expectEqual(@as(usize, 1), fake.calls);
    }
    var invalid: Fake = .{ .invalid_length = true };
    try t.expectError(error.InvalidProvider, c.executeWithOptions(t.allocator, .{ .environment = invalid.provider() }));
}
test "environment identities reject foreign and closed grants before provider invocation" {
    var fake: Fake = .{};
    var first = env.Runtime.init(1, fake.provider());
    var second = env.Runtime.init(2, fake.provider());
    const cap = try first.grant();
    var output: [4]u8 = undefined;
    try t.expectError(error.InvalidCapability, second.get(cap, "K", &output));
    first.close();
    try t.expectError(error.InvalidCapability, first.get(cap, "K", &output));
    try t.expectError(error.InvalidCapability, first.grant());
    try t.expectEqual(@as(usize, 0), fake.calls);
}
test "environment execution reporting and byte conversions release all failed allocations" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), scenario, .{});
}
test "zero capacity environment values distinguish absent empty and too large" {
    var c = try language.Compilation.init(t.allocator, "zero.my",
        \\class Entry:
        \\    bytes: [0]u8
        \\    length: u64
        \\    present: bool
        \\
        \\
        \\result Lookup:
        \\    ok: Entry,
        \\    err: i64
        \\
        \\
        \\def main(env: environment_cap) -> i64:
        \\    match environment_get[Lookup](env, [75u8]):
        \\        case Lookup.ok(entry):
        \\            if entry.present:
        \\                return 1
        \\            else:
        \\                return 0
        \\        case Lookup.err(code):
        \\            return -code
    );
    defer c.deinit();
    var fake: Fake = .{ .value = null };
    try t.expectEqual(@as(i64, 0), (try c.executeWithOptions(t.allocator, .{ .environment = fake.provider() })).value);
    fake.value = "";
    try t.expectEqual(@as(i64, 1), (try c.executeWithOptions(t.allocator, .{ .environment = fake.provider() })).value);
    fake.value = "x";
    try t.expectEqual(@as(i64, -4), (try c.executeWithOptions(t.allocator, .{ .environment = fake.provider() })).value);
}
const generic_environment = declarations ++
    \\def lookup[G](cap: environment_cap) -> Lookup effects(environment):
    \\    name: [1]u8 = [75u8]
    \\    return environment_get[Lookup](cap, name)
    \\
    \\
    \\def main(cap: environment_cap) -> i64:
    \\    match lookup[bool](cap):
    \\        case Lookup.ok(e):
    \\            return i64(e.length) + i64(e.bytes[0]) + i64(e.bytes[1])
    \\        case Lookup.err(e):
    \\            return e
;
fn genericEnvironmentScenario(allocator: std.mem.Allocator) !void {
    var fake: Fake = .{};
    var c = try language.Compilation.init(allocator, "generic-environment.my", generic_environment);
    defer c.deinit();
    try t.expectEqual(@as(i64, 257), (try c.executeWithOptions(allocator, .{ .environment = fake.provider() })).value);
    try t.expectEqual(@as(usize, 1), fake.calls);
}
test "generic environment lookup preserves bounded bytes and callback allocation failures" {
    try genericEnvironmentScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), genericEnvironmentScenario, .{});
}
