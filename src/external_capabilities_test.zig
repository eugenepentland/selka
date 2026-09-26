//! Capability-typed external access: clock and entropy reads, their declared
//! effects, and the rejections that keep authority out of ambient scope.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const module = "external.my";
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
        \\def main(c: Clock) -> i64:
        \\    _ = clock_now[Time](c)
        \\    return 0
    );
    try rejectRaw(declarations ++
        \\def main(r: Entropy) -> i64:
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
    \\def read(auth: Authority) -> Time effects(clock):
    \\    return clock_now[Time](auth.clock)
    \\
    \\
    \\def main(rng: Entropy, clock: Clock) -> i64 noio:
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
    try c.emit();
    const dump = try c.dump(allocator);
    defer allocator.free(dump);
    try t.expect(std.mem.indexOf(u8, dump, "EXTERNAL_clock") != null);
}
test "external entry grants forward through wrappers and preserve full width samples" {
    try scenario(t.allocator);
    var c = try language.Compilation.initTrusted(t.allocator, module, forwarded);
    defer c.deinit();
    const outcome = try native.runWithOptions(&c, .{ .arguments = &.{"--allow-random=0"} });
    try t.expectEqualStrings("", outcome.trap.code);
    // The entry result is the machine's own clock, so only its sign is fixed.
    try t.expect(outcome.value > 0);
}
test "external execution and emission release every failed allocation" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), scenario, .{});
}
test "every grant an entry point names is materialized before its body runs" {
    var c = try language.Compilation.initTrusted(t.allocator, module, forwarded);
    defer c.deinit();
    const withheld = try native.runWithOptions(&c, .{ .arguments = &.{ "--restrict", "--allow-random=0" } });
    try t.expectEqualStrings("CapabilityUnavailable", withheld.trap.code);
    try t.expectEqualStrings("", withheld.stdout);
    var unused = try language.Compilation.initTrusted(t.allocator, "unused.my",
        \\def main(clock: Clock) -> i64 effects():
        \\    _ = clock
        \\    return 1
    );
    defer unused.deinit();
    try t.expectEqual(@as(i64, 1), (try native.run(&unused)).value);
    const refused = try native.runWithOptions(&unused, .{ .arguments = &.{"--restrict"} });
    try t.expectEqualStrings("CapabilityUnavailable", refused.trap.code);
}
const generic_provider_source = declarations ++
    \\def read[G](clock: Clock, random: Entropy) -> Time effects(clock,random):
    \\    now = clock_now[Time](clock)?
    \\    first = random_u64[Random](random)?
    \\    second = random_u64[Random](random)?
    \\    if first == second:
    \\        return Time.err(9)
    \\    if now <= 0:
    \\        return Time.err(8)
    \\    return Time.ok(42)
    \\
    \\
    \\def main(clock: Clock, random: Entropy) -> i64:
    \\    match read[bool](clock, random):
    \\        case Time.ok(n):
    \\            return n
    \\        case Time.err(e):
    \\            return e
;
fn genericProviderScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.initTrusted(allocator, "generic-provider.my", generic_provider_source);
    defer c.deinit();
    try c.emit();
    try t.expect(c.code.?.functions.len != 0);
}
// spec: GENERIC-PROVIDER-EXEC-1
test "generic provider reads preserve values callback counts and allocation cleanup" {
    var c = try language.Compilation.initTrusted(t.allocator, "generic-provider.my", generic_provider_source);
    defer c.deinit();
    // Two distinct words can only come from two separate entropy reads.
    try t.expectEqual(@as(i64, 42), (try native.run(&c)).value);
    try genericProviderScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), genericProviderScenario, .{});
}
test "clock and random bounds propagate through calls independently of noio and noalloc" {
    try reject(declarations ++
        \\def read(c: Clock) -> Time:
        \\    return clock_now[Time](c)
        \\
        \\
        \\def main(c: Clock) -> i64 effects():
        \\    _ = read(c)
        \\    return 0
    , "E_EFFECT_BOUND");
    try reject(declarations ++
        \\def read(r: Entropy) -> Random:
        \\    return random_u64[Random](r)
        \\
        \\
        \\def main(r: Entropy, c: Clock) -> i64 effects(clock):
        \\    _ = c
        \\    _ = read(r)
        \\    return 0
    , "E_EFFECT_BOUND");
    var c = try language.Compilation.initTrusted(t.allocator, module, declarations ++
        \\def main(c: Clock, r: Entropy) -> i64 noalloc:
        \\    _ = clock_now[Time](c)
        \\    _ = random_u64[Random](r)
        \\    return 0
    );
    defer c.deinit();
    try t.expectEqual(@as(i64, 0), (try native.run(&c)).value);
    const functions = @constCast(c.code.?.functions);
    functions[0].policy.effects = 0;
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
}
test "repeated provider reads keep the guest inside one frame" {
    var c = try language.Compilation.initTrusted(t.allocator, module, declarations ++
        \\def main(c: Clock) -> i64:
        \\    n = 0
        \\    while n < 10000:
        \\        _ = clock_now[Time](c)
        \\        n += 1
        \\    return n
    );
    defer c.deinit();
    // Ten thousand reads that retained anything per call would leave the budget.
    const outcome = try native.runWithOptions(&c, .{ .max_frames = 1, .gc_stress = true });
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, 10000), outcome.value);
}
test "clock reads advance monotonically while a short circuited operand never reads" {
    var c = try language.Compilation.initTrusted(t.allocator, module, declarations ++
        \\def positive(c: Clock) -> bool:
        \\    match clock_now[Time](c):
        \\        case Time.ok(v):
        \\            return v > 0
        \\        case Time.err(e):
        \\            _ = e
        \\            return False
        \\
        \\
        \\def main(c: Clock) -> i64:
        \\    _ = False and positive(c)
        \\    first = 0
        \\    match clock_now[Time](c):
        \\        case Time.ok(v):
        \\            first = v
        \\        case Time.err(e):
        \\            return e
        \\    match clock_now[Time](c):
        \\        case Time.ok(v):
        \\            if v < first or first <= 0:
        \\                return 0
        \\            return 7
        \\        case Time.err(e):
        \\            return e
    );
    defer c.deinit();
    // A short-circuited call cannot read: `positive` would need a second frame.
    const outcome = try native.runWithOptions(&c, .{ .max_frames = 1 });
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, 7), outcome.value);
}
test "external emission rejects a forged result shape before any provider call" {
    var c = try language.Compilation.initTrusted(t.allocator, module, declarations ++
        \\def main(c: Clock) -> i64:
        \\    _ = clock_now[Time](c)
        \\    return 0
    );
    defer c.deinit();
    try c.emit();
    const instruction = try @import("instruction_test.zig").find(@constCast(c.code.?.functions[0].scope.instructions), .external_read);
    const original = instruction.*;
    instruction.op.external_read.output = .i64;
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
    instruction.* = original;
    try language.bytecode.validate(t.allocator, c.code.?);
}
