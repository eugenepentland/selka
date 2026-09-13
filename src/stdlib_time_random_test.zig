//! Standard time arithmetic and reproducible random streams preserve explicit authority.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const external = @import("external_capabilities.zig");
const fixture = @import("stdlib_fixture.zig");

// spec: STANDARD-TIME-RANDOM-1
test "standard time random boundary arithmetic and pinned deterministic vectors" {
    try fixture.run(t.allocator, @embedFile("stdlib/fixtures/time_random.my"), 0);
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
    try fixture.expect(t.allocator, provider_source, success.options(), 0);
    try t.expectEqual(@as(usize, 2), success.calls);
    var partial: Provider = .{ .fail_random = true };
    try fixture.expect(t.allocator, provider_source, partial.options(), 9);
    var denied: Provider = .{ .failure = error.Denied };
    try fixture.expect(t.allocator, provider_source, denied.options(), 42);
    var absent: Provider = .{ .failure = error.Unavailable };
    try fixture.expect(t.allocator, provider_source, absent.options(), 43);
    var failed: Provider = .{ .failure = error.Failed };
    try fixture.expect(t.allocator, provider_source, failed.options(), 44);
    var oom: Provider = .{ .failure = error.OutOfMemory };
    try t.expectError(error.OutOfMemory, fixture.expect(t.allocator, provider_source, oom.options(), 0));
    try t.expectError(error.CapabilityUnavailable, fixture.expect(t.allocator, provider_source, .{}, 0));
}

// spec: STANDARD-TIME-RANDOM-3
test "standard time random calls preserve effect ceilings and reproducible draws" {
    try fixture.reject(t.allocator, "module main\nimport time\ndef main(c: clock_cap) -> int effects():\n    _ = time.now(c)\n    return 0\n");
    try fixture.reject(t.allocator, "module main\nimport random\ndef main(c: random_cap) -> int noalloc:\n    _ = random.from_entropy(c)\n    return 0\n");
    var provider: Provider = .{};
    try fixture.expect(t.allocator, "module main\nimport random\n" ++
        "def main(entropy: random_cap) -> int:\n" ++
        "    match random.from_entropy(entropy):\n" ++
        "        case Ok(generator):\n" ++
        "            replay = random.from_word(generator.state[0])\n" ++
        "            if random.next_word(generator) != random.next_word(replay):\n" ++
        "                return 1\n" ++
        "            return 42\n" ++
        "        case Err(_):\n" ++
        "            return 2\n", provider.options(), 42);
    try t.expectEqual(@as(usize, 1), provider.calls);
}
