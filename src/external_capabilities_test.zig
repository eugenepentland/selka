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
// The monotonic reading, sleep and capturing streams are trusted-stdlib intrinsics too: an ordinary program may not spell them.
test "an ordinary program may not spell the clock monotonic reading, sleep, stand-in failure or capturing stream intrinsic" {
    try rejectRaw(
        \\func main(clock: Clock) -> int:
        \\    return len([__clock_monotonic(clock)])
    );
    try rejectRaw(
        \\func main(clock: Clock) -> int:
        \\    __clock_sleep(clock, 5)
        \\    return 0
    );
    try rejectRaw(
        \\func main(clock: Clock) -> int:
        \\    return __stand_fail(clock, 5)
    );
    try rejectRaw(
        \\func main(out: Stream) -> int:
        \\    const capture = __stream_memory(0)
        \\    print(out, __stream_text(capture))
        \\    return 0
    );
}

test "an ordinary program may not build a Process stand-in, a trusted source builds one from bytes" {
    try rejectRaw(
        \\func main() -> int:
        \\    const proc = __stand_in[Process](b"")
        \\    return 0
    );
    var built = try language.Compilation.initTrusted(t.allocator, module,
        \\func build(script: bytes) -> Process:
        \\    return __stand_in[Process](script)
        \\func main() -> int:
        \\    return 0
    );
    defer built.deinit();
    try built.check();
    var counted = try language.Compilation.initTrusted(t.allocator, module,
        \\func build() -> Process:
        \\    return __stand_in[Process](0)
        \\func main() -> int:
        \\    return 0
    );
    defer counted.deinit();
    try t.expectError(error.SourceError, counted.check());
    try t.expectEqualStrings("E_TYPE", counted.diagnostics.items[0].code);
}

test "a trusted source arms a stand-in Clock or Entropy with __stand_fail and no other capability" {
    var armed = try language.Compilation.initTrusted(t.allocator, module,
        \\func main(clock: Clock, entropy: Entropy) -> int:
        \\    return __stand_fail(clock, 3) + __stand_fail(entropy, 0)
    );
    defer armed.deinit();
    try armed.check();
    var refused = try language.Compilation.initTrusted(t.allocator, module,
        \\func main(fs: Filesystem) -> int:
        \\    return __stand_fail(fs, 3)
    );
    defer refused.deinit();
    try t.expectError(error.SourceError, refused.check());
    try t.expectEqualStrings("E_STAND_IN", refused.diagnostics.items[0].code);
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
    \\func read(auth: Authority) -> Time:
    \\    return clock_now[Time](auth.clock)
    \\
    \\
    \\func main(rng: Entropy, clock: Clock) -> i64:
    \\    const authority = Authority(clock=clock)
    \\    match read(authority):
    \\        case ok(now):
    \\            match random_u64[Random](rng):
    \\                case ok(word):
    \\                    if word == 16294208416658607535u64:
    \\                        return now
    \\                    else:
    \\                        return 0
    \\                case err(e):
    \\                    return e
    \\        case err(e):
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
        \\func main(rng: Entropy, env: Environment) -> i64:
        \\    _ = rng
        \\    _ = env
        \\    return 1
    );
    defer c.deinit();
    const withheld = try native.runWithOptions(&c, .{ .arguments = &.{ "--restrict", "--allow-random=0" } });
    try t.expectEqualStrings("CapabilityUnavailable", withheld.trap.code);
    try t.expectEqualStrings("", withheld.stdout);
    var unused = try language.Compilation.initTrusted(t.allocator, "unused.selka",
        \\func main(env: Environment) -> i64:
        \\    _ = env
        \\    return 1
    );
    defer unused.deinit();
    try t.expectEqual(@as(i64, 1), (try native.run(&unused)).value);
    const refused = try native.runWithOptions(&unused, .{ .arguments = &.{"--restrict"} });
    try t.expectEqualStrings("CapabilityUnavailable", refused.trap.code);
    // A `Clock` needs no grant to start (CAPGRANT): its monotonic reading reveals nothing about the world.
    var timed = try language.Compilation.initTrusted(t.allocator, "timed.selka",
        \\func main(clock: Clock) -> i64:
        \\    _ = clock
        \\    return 1
    );
    defer timed.deinit();
    try t.expectEqual(@as(i64, 1), (try native.runWithOptions(&timed, .{ .arguments = &.{"--restrict"} })).value);
}
const generic_provider_source = declarations ++
    \\func read[G](clock: Clock, random: Entropy) -> Time:
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
    \\        case ok(n):
    \\            return n
    \\        case err(e):
    \\            return e
;
fn genericProviderScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.initTrusted(allocator, "generic-provider.selka", generic_provider_source);
    defer c.deinit();
    try c.check();
}
// spec-case: EFFECTS-REMOVED-1
test "clock and random operations are checked through capability argument types" {
    var compilation = try language.Compilation.initTrusted(t.allocator, module, declarations ++
        \\func main(clock: Clock, entropy: Entropy) -> i64:
        \\    _ = clock_now[Time](clock)
        \\    _ = random_u64[Random](entropy)
        \\    return 0
    );
    defer compilation.deinit();
    try compilation.check();
}
