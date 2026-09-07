//! Executed generic provider contracts and cleanup under failed host/VM operations.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const fixture = @import("nominal_provider_fixture.zig");
fn scenario(allocator: std.mem.Allocator) !void {
    var fake: fixture.Fake = .{};
    defer std.debug.assert(fake.counts.live == 0);
    var compilation = try language.Compilation.init(allocator, "nominal-providers.my", fixture.program);
    defer compilation.deinit();
    const result = compilation.executeWithOptions(allocator, .{ .resources = .{ .filesystem = fake.provider() } }) catch |err| {
        if (err != error.OutOfMemory) @import("diagnostics_test.zig").report(compilation.diagnostics.items);
        return err;
    };
    try t.expectEqual(@as(i64, 37), result.value);
    try t.expectEqualSlices(u8, &.{ 9, 7, 8 }, fake.written[0..fake.written_length]);
    try t.expectEqual(fixture.Counts{ .acquired = 1, .completed = 1, .completions = 2, .reads = 2, .writes = 2 }, fake.counts);
}
// spec: NOMINAL-PROVIDER-1
test "nominal providers specialize named payloads byte inputs and completion retry ownership" {
    try scenario(t.allocator);
}
test "nominal providers unwind every compiler and VM allocation failure" {
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
test "nominal providers propagate host failures and release acquired owners exactly once" {
    var compilation = try language.Compilation.init(t.allocator, "host-failure.my", fixture.program);
    defer compilation.deinit();
    var fake: fixture.Fake = .{ .failure = error.Failed };
    try t.expectEqual(@as(i64, -3), (try compilation.executeWithOptions(t.allocator, .{ .resources = .{ .filesystem = fake.provider() } })).value);
    try t.expectEqual(fixture.Counts{ .acquired = 1, .released = 1, .reads = 1 }, fake.counts);
    fake = .{ .failure = error.OutOfMemory };
    try t.expectError(error.OutOfMemory, compilation.executeWithOptions(t.allocator, .{ .resources = .{ .filesystem = fake.provider() } }));
    try t.expectEqual(fixture.Counts{ .acquired = 1, .released = 1, .reads = 1 }, fake.counts);
}

test "nominal providers unwind traps at every instruction including failed completion ownership transfer" {
    var compilation = try language.Compilation.init(t.allocator, "nominal-traps.my", fixture.program);
    defer compilation.deinit();
    var completed = false;
    for (1..500) |budget| {
        var fake: fixture.Fake = .{};
        const result = try compilation.executeWithOptions(t.allocator, .{ .resources = .{ .filesystem = fake.provider() }, .max_steps = budget });
        try t.expectEqual(@as(usize, 0), fake.counts.live);
        try t.expectEqual(fake.counts.acquired, fake.counts.released + fake.counts.completed);
        if (result == .value) {
            try t.expectEqual(@as(i64, 37), result.value);
            completed = true;
            break;
        }
        try t.expectEqualStrings("R_STEP_LIMIT", result.trap.code);
    }
    try t.expect(completed);
}
