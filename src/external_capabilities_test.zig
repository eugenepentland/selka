//! Capability-typed external access: clock, entropy and environment reads, their
//! declared effects, and the rejections that keep authority out of ambient scope.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const external = @import("external_capabilities.zig");
const declarations = "result Time { ok: i64, err: i64 } result Random { ok: u64, err: i64 } ";
const Fake = struct {
    calls: usize = 0,
    failure: ?external.CallError = null,
    time: i64 = -7,
    fn clock(context: *anyopaque) external.CallError!i64 {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.calls += 1;
        if (self.failure) |err| return err;
        return self.time;
    }
    fn random(context: *anyopaque) external.CallError!u64 {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.calls += 1;
        if (self.failure) |err| return err;
        return std.math.maxInt(u64);
    }
    fn providers(self: *Fake) external.Providers {
        return .{ .clock = .{ .context = self, .read = clock }, .random = .{ .context = self, .read = random } };
    }
};
fn reject(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "external.my", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
const forwarded = declarations ++
    \\class Authority:
    \\    clock: clock_cap
    \\
    \\
    \\def read(auth: Authority) -> Time effects(clock):
    \\    return clock_now<Time>(auth.clock)
    \\
    \\
    \\def main(rng: random_cap, clock: clock_cap) -> i64 noio:
    \\    match read(Authority(clock=clock)):
    \\        case Time.ok(now):
    \\            match random_u64<Random>(rng):
    \\                case Random.ok(word):
    \\                    if word == 18446744073709551615u64:
    \\                        return now
    \\                    else:
    \\                        return 0
    \\                case Random.err(e):
    \\                    return e
    \\        case Time.err(e):
    \\            return e
;
fn scenario(allocator: std.mem.Allocator) !void {
    var fake: Fake = .{};
    var c = try language.Compilation.init(allocator, "external.my", forwarded);
    defer c.deinit();
    try t.expectEqual(@as(i64, -7), (try c.executeWithOptions(allocator, .{ .external = fake.providers() })).value);
    try t.expectEqual(@as(usize, 2), fake.calls);
    const dump = try c.dump(allocator);
    defer allocator.free(dump);
    try t.expect(std.mem.indexOf(u8, dump, "EXTERNAL_clock") != null);
}
test "external entry grants forward through wrappers and preserve full width samples" {
    try scenario(t.allocator);
}
const cleanup = declarations ++
    \\def read(c: clock_cap) -> Time:
    \\    sample = clock_now<Time>(c)?
    \\    return Time.ok(sample)
    \\
    \\
    \\def main(c: clock_cap) -> i64:
    \\    match read(c):
    \\        case Time.ok(v):
    \\            return v
    \\        case Time.err(e):
    \\            return e
;
test "provider failures propagate recoverable codes and clean owned resources including host OOM" {
    var c = try language.Compilation.init(t.allocator, "external.my", cleanup);
    defer c.deinit();
    for ([_]external.CallError{ error.Unavailable, error.Denied, error.Failed, error.OutOfMemory }, 1..) |failure, code| {
        var fake: Fake = .{ .failure = failure };
        const options: language.vm.Options = .{ .external = fake.providers() };
        if (failure == error.OutOfMemory) {
            try t.expectError(error.OutOfMemory, c.executeWithOptions(t.allocator, options));
        } else try t.expectEqual(@as(i64, @intCast(code)), (try c.executeWithOptions(t.allocator, options)).value);
        try t.expectEqual(@as(usize, 1), fake.calls);
    }
}
test "external runtime rejects foreign cross-kind and closed grants before callbacks" {
    var fake: Fake = .{};
    var first = external.Runtime.init(1, fake.providers());
    var other = external.Runtime.init(2, fake.providers());
    const cap = try first.grant(.clock);
    try t.expectError(error.InvalidCapability, other.read(.clock, cap));
    try t.expectError(error.InvalidCapability, first.read(.random, cap));
    first.close();
    try t.expectError(error.InvalidCapability, first.read(.clock, cap));
    try t.expectError(error.InvalidCapability, first.grant(.clock));
    try t.expectEqual(@as(usize, 0), fake.calls);
}
test "external execution and emission release every failed allocation" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), scenario, .{});
}
const generic_provider_source = declarations ++
    \\def read[G](clock: clock_cap, random: random_cap) -> Time effects(clock,random):
    \\    n = clock_now<Time>(clock)?
    \\    word = random_u64<Random>(random)?
    \\    if word == 18446744073709551615u64:
    \\        return Time.ok(n)
    \\    return Time.err(9)
    \\
    \\
    \\def main(clock: clock_cap, random: random_cap) -> i64:
    \\    match read[bool](clock, random):
    \\        case Time.ok(n):
    \\            return n
    \\        case Time.err(e):
    \\            return e
;
fn genericProviderScenario(allocator: std.mem.Allocator) !void {
    var fake: Fake = .{};
    var c = try language.Compilation.init(allocator, "generic-provider.my", generic_provider_source);
    defer c.deinit();
    try t.expectEqual(@as(i64, -7), (try c.executeWithOptions(allocator, .{ .external = fake.providers() })).value);
    try t.expectEqual(@as(usize, 2), fake.calls);
}
// spec: GENERIC-PROVIDER-EXEC-1
test "generic provider reads preserve values callback counts and allocation cleanup" {
    try genericProviderScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), genericProviderScenario, .{});
}
test "all grants are checked before invoking any provider" {
    var fake: Fake = .{};
    var providers = fake.providers();
    providers.clock = null;
    var c = try language.Compilation.init(t.allocator, "external.my", forwarded);
    defer c.deinit();
    try t.expectError(error.CapabilityUnavailable, c.executeWithOptions(t.allocator, .{ .external = providers }));
    try t.expectEqual(@as(usize, 0), fake.calls);
    try t.expectError(error.CapabilityUnavailable, c.execute(t.allocator));
    var unused = try language.Compilation.init(t.allocator, "unused.my",
        \\def main(clock: clock_cap) -> i64 effects():
        \\    _ = clock
        \\    return 1
    );
    defer unused.deinit();
    try t.expectEqual(@as(i64, 1), (try unused.executeWithOptions(t.allocator, .{ .external = fake.providers() })).value);
    try t.expectEqual(@as(usize, 0), fake.calls);
}
test "clock and random bounds propagate through calls independently of noio and noalloc" {
    try reject(declarations ++
        \\def read(c: clock_cap) -> Time:
        \\    return clock_now<Time>(c)
        \\
        \\
        \\def main(c: clock_cap) -> i64 effects():
        \\    _ = read(c)
        \\    return 0
    , "E_EFFECT_BOUND");
    try reject(declarations ++
        \\def read(r: random_cap) -> Random:
        \\    return random_u64<Random>(r)
        \\
        \\
        \\def main(r: random_cap) -> i64 effects(clock):
        \\    _ = read(r)
        \\    return 0
    , "E_EFFECT_BOUND");
    var c = try language.Compilation.init(t.allocator, "external.my", declarations ++
        \\def main(c: clock_cap, r: random_cap) -> i64 noalloc:
        \\    _ = clock_now<Time>(c)
        \\    _ = random_u64<Random>(r)
        \\    return 0
    );
    defer c.deinit();
    var fake: Fake = .{};
    _ = try c.executeWithOptions(t.allocator, .{ .external = fake.providers() });
    try t.expectEqual(@as(usize, 2), fake.calls);
    const functions = @constCast(c.code.?.functions);
    functions[0].policy.effects = 0;
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
}
test "repeated provider reads have bounded live storage" {
    var c = try language.Compilation.init(t.allocator, "external.my", declarations ++
        \\def main(c: clock_cap) -> i64:
        \\    n = 0
        \\    while n < 10000:
        \\        _ = clock_now<Time>(c)
        \\        n += 1
        \\    return n
    );
    defer c.deinit();
    try c.emit();
    var limited: @import("test_support.zig").LimitedLiveAllocator = .{ .parent = t.allocator, .limit = 16 * 1024 };
    defer limited.deinit();
    var fake: Fake = .{};
    try t.expectEqual(@as(i64, 10000), (try c.executeWithOptions(limited.allocator(), .{ .external = fake.providers() })).value);
    try t.expectEqual(@as(usize, 10000), fake.calls);
    try t.expectEqual(@as(usize, 0), limited.live);
}
test "clock preserves signed limits and short circuit skips provider calls" {
    var c = try language.Compilation.init(t.allocator, "external.my", declarations ++
        \\def positive(c: clock_cap) -> bool:
        \\    match clock_now<Time>(c):
        \\        case Time.ok(v):
        \\            return v > 0
        \\        case Time.err(e):
        \\            _ = e
        \\            return False
        \\
        \\
        \\def main(c: clock_cap) -> i64:
        \\    _ = False and positive(c)
        \\    match clock_now<Time>(c):
        \\        case Time.ok(v):
        \\            return v
        \\        case Time.err(e):
        \\            return e
    );
    defer c.deinit();
    for ([_]i64{ std.math.minInt(i64), std.math.maxInt(i64) }) |time| {
        var fake: Fake = .{ .time = time };
        try t.expectEqual(time, (try c.executeWithOptions(t.allocator, .{ .external = fake.providers() })).value);
        try t.expectEqual(@as(usize, 1), fake.calls);
    }
}
test "external emission rejects wrong result shape and VM rejects wrong operand without callback" {
    var c = try language.Compilation.init(t.allocator, "external.my", declarations ++
        \\def main(c: clock_cap) -> i64:
        \\    _ = clock_now<Time>(c)
        \\    return 0
    );
    defer c.deinit();
    try c.emit();
    var fake: Fake = .{};
    for (@constCast(c.code.?.functions[0].scope.instructions)) |*instruction| {
        const original = instruction.*;
        if (instruction.op == .external_read) {
            instruction.op.external_read.output = .i64;
            try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
            instruction.* = original;
        } else if (instruction.op == .load_local) {
            instruction.op = .{ .push_i64 = 0 };
            try t.expectError(error.InternalError, language.vm.runWithOptions(t.allocator, c.code.?, .{ .external = fake.providers() }));
            instruction.* = original;
        }
    }
    try t.expectEqual(@as(usize, 0), fake.calls);
}
