//! Environment capability contracts, bounded host values and generic execution tests.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const module = "environment.my";
const declarations =
    \\record Entry:
    \\    present: bool
    \\    bytes: [4]u8
    \\    length: u64
    \\
    \\
    \\result Lookup:
    \\    err: i64,
    \\    ok: Entry
    \\
    \\
    \\
;
fn reject(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, module, source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
/// Run one program against a guest environment holding `K` only when given.
fn lookup(source: []const u8, value: ?[]const u8, arguments: []const []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, module, source);
    defer c.deinit();
    var guest: std.process.Environ.Map = .init(t.allocator);
    defer guest.deinit();
    if (value) |bytes| try guest.put("K", bytes);
    const outcome = native.runWithOptions(&c, .{ .environment = &guest, .arguments = arguments }) catch |err| {
        @import("diagnostics_test.zig").report(c.diagnostics.items);
        return err;
    };
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(expected, outcome.value);
}
const forwarded = declarations ++
    \\class Authority:
    \\    env: Environment
    \\
    \\
    \\def lookup(auth: Authority) -> Lookup effects(environment):
    \\    return environment_get[Lookup](auth.env, [75u8])
    \\
    \\
    \\def main(environment: Environment) -> i64 noio:
    \\    match lookup(Authority(env=environment)):
    \\        case Lookup.ok(entry):
    \\            if entry.present:
    \\                return 10 + i64(entry.length) + i64(entry.bytes[3])
    \\            else:
    \\                return i64(entry.length) + i64(entry.bytes[0])
    \\        case Lookup.err(code):
    \\            return -code
;
fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, module, forwarded);
    defer c.deinit();
    try c.emit();
    const dump = try c.dump(allocator);
    defer allocator.free(dump);
    try t.expect(std.mem.indexOf(u8, dump, "ENVIRONMENT_GET") != null);
    var duplicates = try language.duplicates.discover(allocator, c.program.?, .{ .min_nodes = 1 });
    defer duplicates.deinit();
}
// spec: OWN-10
test "environment grants delegate explicitly and missing empty and present values remain distinct" {
    try scenario(t.allocator);
    try lookup(forwarded, "ab", &.{}, 12);
    try lookup(forwarded, null, &.{}, 0);
    try lookup(forwarded, "", &.{}, 10);
    try lookup(forwarded, "12345", &.{}, -4);
}
test "environment returns raw bytes and canonical zero padding" {
    try lookup(declarations ++
        \\def main(env: Environment) -> i64:
        \\    match environment_get[Lookup](env, [75u8]):
        \\        case Lookup.ok(entry):
        \\            return i64(entry.bytes[0]) + i64(entry.bytes[1]) + i64(entry.bytes[2]) + i64(entry.bytes[3])
        \\        case Lookup.err(code):
        \\            return -code
    , "\xff", &.{}, 255);
}
test "environment reads outside an explicit allowlist are denied before the host is asked" {
    try lookup(forwarded, "ab", &.{ "--restrict", "--allow-env=OTHER" }, -2);
    try lookup(forwarded, "ab", &.{ "--restrict", "--allow-env=K,OTHER" }, 12);
    var c = try language.Compilation.init(t.allocator, module, forwarded);
    defer c.deinit();
    const withheld = try native.runWithOptions(&c, .{ .arguments = &.{"--restrict"} });
    try t.expectEqualStrings("CapabilityUnavailable", withheld.trap.code);
    try t.expectEqual(@as(u8, 2), withheld.status);
}
test "environment grants are rejected outside a capability parameter" {
    try reject(declarations ++
        \\def main() -> i64:
        \\    match environment_get[Lookup](7, [75u8]):
        \\        case Lookup.ok(entry):
        \\            return i64(entry.length)
        \\        case Lookup.err(code):
        \\            return -code
    , "E_TYPE");
}
test "environment execution reporting and byte conversions release all failed allocations" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), scenario, .{});
}
const zero_capacity = declarations ++
    \\class Empty:
    \\    bytes: [0]u8
    \\    length: u64
    \\    present: bool
    \\
    \\
    \\result Absent:
    \\    ok: Empty,
    \\    err: i64
    \\
    \\
    \\def main(env: Environment) -> i64:
    \\    match environment_get[Absent](env, [75u8]):
    \\        case Absent.ok(entry):
    \\            if entry.present:
    \\                return 1
    \\            else:
    \\                return 0
    \\        case Absent.err(code):
    \\            return -code
;
test "zero capacity environment values distinguish absent empty and too large" {
    try lookup(zero_capacity, null, &.{}, 0);
    try lookup(zero_capacity, "", &.{}, 1);
    try lookup(zero_capacity, "x", &.{}, -4);
}
const generic_environment = declarations ++
    \\def lookup[G](cap: Environment) -> Lookup effects(environment):
    \\    name: [1]u8 = [75u8]
    \\    return environment_get[Lookup](cap, name)
    \\
    \\
    \\def main(cap: Environment) -> i64:
    \\    match lookup[bool](cap):
    \\        case Lookup.ok(e):
    \\            return i64(e.length) + i64(e.bytes[0]) + i64(e.bytes[1])
    \\        case Lookup.err(e):
    \\            return e
;
fn genericEnvironmentScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "generic-environment.my", generic_environment);
    defer c.deinit();
    try c.emit();
    try t.expect(c.code.?.functions.len != 0);
}
test "generic environment lookup preserves bounded bytes and callback allocation failures" {
    try lookup(generic_environment, "ab", &.{}, 2 + 'a' + 'b');
    try genericEnvironmentScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), genericEnvironmentScenario, .{});
}
