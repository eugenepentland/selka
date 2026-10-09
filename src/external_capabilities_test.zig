//! Capability-typed external access: clock and entropy reads, their declared
//! effects, and the rejections that keep authority out of ambient scope.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const module = "external.selka";
const declarations =
    \\result Time:
    \\    ok: i64,
    \\    err: i64
    \\
    \\
    \\result Random:
    \\    ok: u64,
    \\    err: i64
    \\
    \\
    \\
;
fn reject(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.initTrusted(t.allocator, module, source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
/// An ordinary, non-trusted compilation may not spell the raw provider reads.
fn rejectRaw(source: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, module, source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_INTERNAL_NAME", c.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, c.diagnostics.items[0].message, "time") != null);
    try t.expect(std.mem.indexOf(u8, c.diagnostics.items[0].message, "random") != null);
}
// spec: CLOCK-INTRINSIC-1
test "ordinary source cannot spell the raw clock and random provider reads" {
    try rejectRaw(declarations ++
        \\func main(c: Clock) -> i64:
        \\    _ = clock_now[Time](c)
        \\    return 0
    );
    try rejectRaw(declarations ++
        \\func main(r: Entropy) -> i64:
        \\    _ = random_u64[Random](r)
        \\    return 0
    );
}
// The runtime's pinned SplitMix64 stream draws 16294208416658607535 first from
// seed zero, and that word's high bit proves the sample keeps all its bits.
const forwarded = declarations ++
    \\record Authority:
    \\    clock: Clock
    \\
    \\
    \\func read(auth: Authority) -> Time effects(clock):
    \\    return clock_now[Time](auth.clock)
    \\
    \\
    \\func main(rng: Entropy, clock: Clock) -> i64 noio:
    \\    match read(Authority(clock=clock)):
    \\        case Time.ok(now):
    \\            match random_u64[Random](rng):
    \\                case Random.ok(word):
    \\                    if word == 16294208416658607535u64:
    \\                        return now
    \\                    else:
    \\                        return 0
    \\                case Random.err(e):
    \\                    return e
    \\        case Time.err(e):
    \\            return e
;
fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.initTrusted(allocator, module, forwarded);
    defer c.deinit();
    try c.check();
}
test "external execution and emission release every failed allocation" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), scenario, .{});
}
test "every grant an entry point names is materialized before its body runs" {
    var c = try language.Compilation.init(t.allocator, module,
        \\func main(rng: Entropy, clock: Clock) -> i64 effects():
        \\    _ = rng
        \\    _ = clock
        \\    return 1
    );
    defer c.deinit();
    const withheld = try native.runWithOptions(&c, .{ .arguments = &.{ "--restrict", "--allow-random=0" } });
    try t.expectEqualStrings("CapabilityUnavailable", withheld.trap.code);
    try t.expectEqualStrings("", withheld.stdout);
    var unused = try language.Compilation.initTrusted(t.allocator, "unused.selka",
        \\func main(clock: Clock) -> i64 effects():
        \\    _ = clock
        \\    return 1
    );
    defer unused.deinit();
    try t.expectEqual(@as(i64, 1), (try native.run(&unused)).value);
    const refused = try native.runWithOptions(&unused, .{ .arguments = &.{"--restrict"} });
    try t.expectEqualStrings("CapabilityUnavailable", refused.trap.code);
}
const generic_provider_source = declarations ++
    \\func read[G](clock: Clock, random: Entropy) -> Time effects(clock,random):
    \\    mut now = try clock_now[Time](clock)
    \\    mut first = try random_u64[Random](random)
    \\    mut second = try random_u64[Random](random)
    \\    if first == second:
    \\        return Time.err(9)
    \\    if now <= 0:
    \\        return Time.err(8)
    \\    return Time.ok(42)
    \\
    \\
    \\func main(clock: Clock, random: Entropy) -> i64:
    \\    match read[bool](clock, random):
    \\        case Time.ok(n):
    \\            return n
    \\        case Time.err(e):
    \\            return e
;
fn genericProviderScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.initTrusted(allocator, "generic-provider.selka", generic_provider_source);
    defer c.deinit();
    try c.check();
}
test "clock and random bounds propagate through calls independently of noio and noalloc" {
    try reject(declarations ++
        \\func read(c: Clock) -> Time:
        \\    return clock_now[Time](c)
        \\
        \\
        \\func main(c: Clock) -> i64 effects():
        \\    _ = read(c)
        \\    return 0
    , "E_EFFECT_BOUND");
    try reject(declarations ++
        \\func read(r: Entropy) -> Random:
        \\    return random_u64[Random](r)
        \\
        \\
        \\func main(r: Entropy, c: Clock) -> i64 effects(clock):
        \\    _ = c
        \\    _ = read(r)
        \\    return 0
    , "E_EFFECT_BOUND");
    var c = try language.Compilation.initTrusted(t.allocator, module, declarations ++
        \\func main(c: Clock, r: Entropy) -> i64 noalloc:
        \\    _ = clock_now[Time](c)
        \\    _ = random_u64[Random](r)
        \\    return 0
    );
    defer c.deinit();
    try c.check();
}
