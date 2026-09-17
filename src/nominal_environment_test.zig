//! Symbolic environment payloads preserve raw bytes, absence, and bounded refusals.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const declarations =
    \\record Entry[T]:
    \\    present: bool
    \\    length: u64
    \\    bytes: [4]u8
    \\
    \\
    \\result Lookup[T]:
    \\    err: i64,
    \\    ok: Entry[T]
    \\
    \\
    \\
;
const program = declarations ++
    \\def singleton[T](x: T) -> [1]T:
    \\    return [x]
    \\
    \\
    \\def lookup[T](env: Environment) -> Lookup[T]:
    \\    return environment_get[Lookup[T]](env, singleton[u8](75u8))
    \\
    \\
    \\def main(env: Environment) -> i64:
    \\    match lookup[bool](env):
    \\        case Lookup.ok(entry):
    \\            sum = i64(entry.length) + i64(entry.bytes[0]) + i64(entry.bytes[1]) + i64(entry.bytes[2]) + i64(entry.bytes[3])
    \\            if entry.present:
    \\                return 100 + sum
    \\            return sum
    \\        case Lookup.err(e):
    \\            return -e
;
/// Run the symbolic lookup against a guest environment holding `K` only when given.
fn lookup(value: ?[]const u8, arguments: []const []const u8, expected: i64) !void {
    var compilation = try language.Compilation.initTrusted(t.allocator, "nominal-environment.my", program);
    defer compilation.deinit();
    var guest: std.process.Environ.Map = .init(t.allocator);
    defer guest.deinit();
    if (value) |bytes| try guest.put("K", bytes);
    const outcome = native.runWithOptions(&compilation, .{ .environment = &guest, .arguments = arguments }) catch |err| {
        @import("diagnostics_test.zig").report(compilation.diagnostics.items);
        return err;
    };
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(expected, outcome.value);
}
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.initTrusted(allocator, "nominal-environment.my", program);
    defer compilation.deinit();
    try compilation.emit();
    const dump = try compilation.dump(allocator);
    defer allocator.free(dump);
    try t.expect(std.mem.indexOf(u8, dump, "ENVIRONMENT_GET") != null);
}
test "nominal environment wrappers preserve binary bytes and zero unspecified padding" {
    // Two present bytes and two zeroed tail bytes: 100 + 2 + 0xfe + 0xff.
    try lookup("\xfe\xff", &.{}, 611);
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
test "nominal environment distinguishes absent empty oversize and denied host values" {
    try lookup(null, &.{}, 0);
    try lookup("", &.{}, 100);
    try lookup("12345", &.{}, -4);
    try lookup("x", &.{ "--restrict", "--allow-env=OTHER" }, -2);
}
