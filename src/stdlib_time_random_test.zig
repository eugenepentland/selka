//! Standard time arithmetic and reproducible random streams preserve explicit authority.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const external = @import("external_capabilities.zig");
const Fixture = struct {
    text: []const u8,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Fixture = @ptrCast(@alignCast(context.?));
        if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
        if (self.text.len > limit) return error.TooLarge;
        return allocator.dupe(u8, self.text);
    }
};
fn run(allocator: std.mem.Allocator, text: []const u8, options: language.vm.Options, expected: i64) !void {
    var fixture: Fixture = .{ .text = text };
    var program: language.embedded_project.Program = undefined;
    try program.init(allocator, .{ .context = &fixture, .read = Fixture.read });
    defer program.deinit();
    const outcome = try language.vm.runWithOptions(allocator, program.compilation.code.?, options);
    try t.expectEqual(expected, outcome.value);
}
// spec: STANDARD-TIME-RANDOM-1
test "standard time random boundary arithmetic and pinned deterministic vectors" {
    try run(t.allocator, @embedFile("stdlib/fixtures/time_random.my"), .{}, 0);
}
const Provider = struct {
    calls: usize = 0,
    failure: ?external.CallError = null,
    fail_random: bool = false,
    fn clock(context: *anyopaque) external.CallError!i64 {
        const self: *Provider = @ptrCast(@alignCast(context));
        if (self.failure) |failure| return failure;
        return -7;
    }
    fn random(context: *anyopaque) external.CallError!u64 {
        const self: *Provider = @ptrCast(@alignCast(context));
        self.calls += 1;
        if (self.fail_random and self.calls == 2) return error.Failed;
        return 0x0102030405060708;
    }
    fn options(self: *Provider) language.vm.Options {
        return .{ .external = .{
            .clock = .{ .context = self, .read = clock },
            .random = .{ .context = self, .read = random },
        } };
    }
};
const provider_source = @embedFile("stdlib/fixtures/time_random_provider.my");
// spec: STANDARD-TIME-RANDOM-2
test "standard time random providers retain typed failures at every capability" {
    var success: Provider = .{};
    try run(t.allocator, provider_source, success.options(), 0);
    try t.expectEqual(@as(usize, 2), success.calls);
    var partial: Provider = .{ .fail_random = true };
    try run(t.allocator, provider_source, partial.options(), 9);
    var denied: Provider = .{ .failure = error.Denied };
    try run(t.allocator, provider_source, denied.options(), 42);
    var absent: Provider = .{ .failure = error.Unavailable };
    try run(t.allocator, provider_source, absent.options(), 43);
    var failed: Provider = .{ .failure = error.Failed };
    try run(t.allocator, provider_source, failed.options(), 44);
    var oom: Provider = .{ .failure = error.OutOfMemory };
    try t.expectError(error.OutOfMemory, run(t.allocator, provider_source, oom.options(), 0));
    try t.expectError(error.CapabilityUnavailable, run(t.allocator, provider_source, .{}, 0));
}

// spec: STANDARD-TIME-RANDOM-2
test "standard time random providers retain failures and partial initialized output" {
    var success: Provider = .{};
    try run(t.allocator, provider_source, success.options(), 0);
    try t.expectEqual(@as(usize, 4), success.calls);
    var partial: Provider = .{ .fail_random = true };
    try run(t.allocator, provider_source, partial.options(), 45);
    var denied: Provider = .{ .failure = error.Denied };
    try run(t.allocator, provider_source, denied.options(), 42);
    var absent: Provider = .{ .failure = error.Unavailable };
    try run(t.allocator, provider_source, absent.options(), 43);
    var failed: Provider = .{ .failure = error.Failed };
    try run(t.allocator, provider_source, failed.options(), 44);
    var oom: Provider = .{ .failure = error.OutOfMemory };
    try t.expectError(error.OutOfMemory, run(t.allocator, provider_source, oom.options(), 0));
    try t.expectError(error.CapabilityUnavailable, run(t.allocator, provider_source, .{}, 0));
}
