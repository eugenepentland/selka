const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const external = @import("external_capabilities.zig");
const memory = @import("memory.zig");
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
const forwarded = declarations ++ "struct Authority { clock: clock_cap } fn read(auth: Authority) -> Time " ++
    "effects(clock) { return clock_now<Time>(auth.clock); } fn main(rng: random_cap, " ++
    "heap: allocator, clock: clock_cap) -> i64 noio { discard heap; match read(new " ++
    "Authority { clock: clock }) { Time.ok(now) => { match random_u64<Random>(rng) { " ++
    "Random.ok(word) => { if word == 18446744073709551615u64 { return now; } else { " ++
    "return 0; } }, Random.err(e) => { return e; } } }, Time.err(e) => { return e; } } }";
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
test "all grants are checked before invoking any provider" {
    var fake: Fake = .{};
    var providers = fake.providers();
    providers.clock = null;
    var c = try language.Compilation.init(t.allocator, "external.my", forwarded);
    defer c.deinit();
    try t.expectError(error.CapabilityUnavailable, c.executeWithOptions(t.allocator, .{ .external = providers }));
    try t.expectEqual(@as(usize, 0), fake.calls);
    try t.expectError(error.CapabilityUnavailable, c.execute(t.allocator));
    var unused = try language.Compilation.init(t.allocator, "unused.my", "fn main(clock: clock_cap) -> i64 effects() { discard clock; return 1; }");
    defer unused.deinit();
    try t.expectEqual(@as(i64, 1), (try unused.executeWithOptions(t.allocator, .{ .external = fake.providers() })).value);
    try t.expectEqual(@as(usize, 0), fake.calls);
}
test "external authority cannot be manufactured substituted or duplicated at entry" {
    try reject(declarations ++ "fn main(r: random_cap) -> i64 { acknowledge clock_now<Time>(r); return 0; }", "E_TYPE");
    try reject("fn forge() -> clock_cap { return cast<clock_cap>(0); } fn main() -> i64 { return 0; }", "E_TYPE");
    try reject("fn main(a: clock_cap, b: clock_cap) -> i64 { return 0; }", "E_MAIN");
    try reject("fn main(a: &clock_cap) -> i64 { return 0; }", "E_MAIN");
    try reject(declarations ++ "fn main() -> i64 { acknowledge clock_now<Time>(clock); return 0; }", "E_UNKNOWN_NAME");
    try reject(declarations ++ "fn main(c: clock_cap) -> i64 { acknowledge clock_now<Random>(c); return 0; }", "E_EXTERNAL_RESULT");
}
test "clock and random bounds propagate through calls independently of noio and noalloc" {
    try reject(declarations ++ "fn read(c: clock_cap) -> Time { return clock_now<Time>(c); } fn main(c: clock_cap) -> i64 effects() { acknowledge read(c); return 0; }", "E_EFFECT_BOUND");
    try reject(declarations ++ "fn read(r: random_cap) -> Random { return random_u64<Random>(r); } fn main(r: random_cap) -> i64 effects(clock) { acknowledge read(r); return 0; }", "E_EFFECT_BOUND");
    var c = try language.Compilation.init(t.allocator, "external.my", declarations ++ "fn main(c: clock_cap, r: random_cap) -> i64 noalloc { acknowledge clock_now<Time>(c); acknowledge random_u64<Random>(r); return 0; }");
    defer c.deinit();
    var fake: Fake = .{};
    _ = try c.executeWithOptions(t.allocator, .{ .external = fake.providers() });
    try t.expectEqual(@as(usize, 2), fake.calls);
    const functions = @constCast(c.code.?.functions);
    functions[0].policy.effects = 0;
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
}
const cleanup = declarations ++ "buffer B: i64; result Owned { ok: B, err: i64 } fn read(heap: allocator, c: " ++
    "clock_cap) -> Time { let b = try acquire_buffer<Owned>(heap, 1); let sample = try " ++
    "clock_now<Time>(c); discard b; return new Time.ok(sample); } fn main(heap: allocator," ++
    " c: clock_cap) -> i64 { match read(heap, c) { Time.ok(v) => { return v; }, " ++
    "Time.err(e) => { return e; } } }";
test "provider failures propagate recoverable codes and clean owned resources including host OOM" {
    var c = try language.Compilation.init(t.allocator, "external.my", cleanup);
    defer c.deinit();
    for ([_]external.CallError{ error.Unavailable, error.Denied, error.Failed, error.OutOfMemory }, 1..) |failure, code| {
        var fake: Fake = .{ .failure = failure };
        var stats: memory.Statistics = .{};
        const options: language.vm.Options = .{
            .external = fake.providers(),
            .memory = .{ .statistics = &stats },
        };
        if (failure == error.OutOfMemory) {
            try t.expectError(error.OutOfMemory, c.executeWithOptions(t.allocator, options));
        } else try t.expectEqual(@as(i64, @intCast(code)), (try c.executeWithOptions(t.allocator, options)).value);
        try t.expectEqual(@as(usize, 1), fake.calls);
        try t.expectEqual(@as(u64, 1), stats.created);
        try t.expectEqual(stats.created, stats.released);
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
test "repeated provider reads have bounded live storage" {
    var c = try language.Compilation.init(t.allocator, "external.my", declarations ++ "fn main(c: clock_cap) -> i64 { let mut n = 0; while n < 10000 { acknowledge clock_now<Time>(c); n += 1; } return n; }");
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
    var c = try language.Compilation.init(t.allocator, "external.my", declarations ++ "fn positive(c: clock_cap) -> bool { match clock_now<Time>(c) { Time.ok(v) => { " ++
        "return v > 0; }, Time.err(e) => { discard e; return false; } } } fn main(c: " ++
        "clock_cap) -> i64 { discard false && positive(c); match clock_now<Time>(c) { " ++
        "Time.ok(v) => { return v; }, Time.err(e) => { return e; } } }");
    defer c.deinit();
    for ([_]i64{ std.math.minInt(i64), std.math.maxInt(i64) }) |time| {
        var fake: Fake = .{ .time = time };
        try t.expectEqual(time, (try c.executeWithOptions(t.allocator, .{ .external = fake.providers() })).value);
        try t.expectEqual(@as(usize, 1), fake.calls);
    }
}
test "external emission rejects wrong result shape and VM rejects wrong operand without callback" {
    var c = try language.Compilation.init(t.allocator, "external.my", declarations ++ "fn main(c: clock_cap) -> i64 { acknowledge clock_now<Time>(c); return 0; }");
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
