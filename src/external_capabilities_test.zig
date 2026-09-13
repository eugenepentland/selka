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
const forwarded = declarations ++ "struct Authority { clock: clock_cap } fn read(auth: Authority) -> Time " ++
    "effects(clock) { return clock_now<Time>(auth.clock); } fn main(rng: random_cap, " ++
    "clock: clock_cap) -> i64 noio { match read(new " ++
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
const cleanup = declarations ++ "fn read(c: clock_cap) -> Time { let sample = " ++
    "clock_now<Time>(c)?; return new Time.ok(sample); } fn main(" ++
    "c: clock_cap) -> i64 { match read(c) { Time.ok(v) => { return v; }, " ++
    "Time.err(e) => { return e; } } }";
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
    "fn read<G:copy>(clock:clock_cap,random:random_cap)->Time effects(clock,random){let n=clock_now<Time>(clock)?;" ++
    "let word=random_u64<Random>(random)?;if word==18446744073709551615u64{return new Time.ok(n);}return new Time.err(9);}" ++
    "fn main(clock:clock_cap,random:random_cap)->i64{match read::<bool>(clock,random){Time.ok(n)=>{return n;},Time.err(e)=>{return e;}}}";
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
