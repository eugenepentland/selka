//! Symbolic environment payloads preserve raw bytes, absence, and bounded failures.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const environment = @import("environment.zig");
const declarations =
    \\class Entry[T]:
    \\    present: bool
    \\    length: u64
    \\    bytes: [4]u8
    \\
    \\
    \\result Lookup[T]:
    \\    err: i64,
    \\    ok: Entry[T]
;
const program = declarations ++
    \\def singleton[T](x: T) -> [1]T:
    \\    return [x]
    \\
    \\
    \\def lookup[T](env: environment_cap) -> Lookup[T]:
    \\    return environment_get[Lookup[T]](env, singleton[u8](75u8))
    \\
    \\
    \\def main(env: environment_cap) -> i64:
    \\    match lookup[bool](env):
    \\        case Lookup.ok(entry):
    \\            sum = i64(entry.length) + i64(entry.bytes[0]) + i64(entry.bytes[1]) + i64(entry.bytes[2]) + i64(entry.bytes[3])
    \\            if entry.present:
    \\                return 100 + sum
    \\            return sum
    \\        case Lookup.err(e):
    \\            return -e
;
const Fake = struct {
    calls: usize = 0,
    value: ?[]const u8 = "\x00\xff",
    failure: ?environment.CallError = null,
    invalid_length: bool = false,
    fn get(context: *anyopaque, name: []const u8, output: []u8) environment.CallError!?usize {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.calls += 1;
        if (!std.mem.eql(u8, name, "K")) return error.Denied;
        @memset(output, 99);
        if (self.failure) |err| return err;
        if (self.invalid_length) return output.len + 1;
        const bytes = self.value orelse return null;
        if (bytes.len > output.len) return error.NoCapacity;
        @memcpy(output[0..bytes.len], bytes);
        return bytes.len;
    }
    fn provider(self: *Fake) environment.Provider {
        return .{ .context = self, .get = get };
    }
};
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "nominal-environment.my", program);
    defer compilation.deinit();
    var fake: Fake = .{};
    const result = compilation.executeWithOptions(allocator, .{ .environment = fake.provider() }) catch |err| {
        if (err != error.OutOfMemory) @import("diagnostics_test.zig").report(compilation.diagnostics.items);
        return err;
    };
    try t.expectEqual(@as(i64, 357), result.value);
    try t.expectEqual(@as(usize, 1), fake.calls);
}
test "nominal environment wrappers preserve binary bytes and zero unspecified padding" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
test "nominal environment distinguishes absent empty oversize and failed host values" {
    var compilation = try language.Compilation.init(t.allocator, "nominal-environment.my", program);
    defer compilation.deinit();
    const Case = struct { value: ?[]const u8, failure: ?environment.CallError = null, expected: i64 };
    for ([_]Case{ .{ .value = null, .expected = 0 }, .{ .value = "", .expected = 100 }, .{ .value = "12345", .expected = -4 }, .{ .value = "x", .failure = error.Failed, .expected = -3 } }) |case| {
        var fake: Fake = .{ .value = case.value, .failure = case.failure };
        try t.expectEqual(case.expected, (try compilation.executeWithOptions(t.allocator, .{ .environment = fake.provider() })).value);
        try t.expectEqual(@as(usize, 1), fake.calls);
    }
    var fake: Fake = .{ .failure = error.OutOfMemory };
    try t.expectError(error.OutOfMemory, compilation.executeWithOptions(t.allocator, .{ .environment = fake.provider() }));
    fake = .{ .invalid_length = true };
    try t.expectError(error.InvalidProvider, compilation.executeWithOptions(t.allocator, .{ .environment = fake.provider() }));
}
