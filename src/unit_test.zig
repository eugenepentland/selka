//! Unit procedures preserve effectful calls without dummy values or implicit result loss.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const program =
    "fn set(x:i64)->unit{_ = x;}" ++
    "fn skip<T:copy>(x:T)->unit{_ = x;}" ++
    "fn noop()->unit{return;}" ++
    "fn main()->i64{let mut x=0;x=42;set(x);skip::<i64>(x);noop();return x;}";

fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "unit.my", program);
    defer c.deinit();
    for ([_]bool{ false, true }) |optimized| {
        const result = try c.executeWithOptions(allocator, .{ .memory = .{ .optimize_dispatch = optimized } });
        try t.expectEqual(@as(i64, 42), result.value);
    }
}
// spec: UNIT-1
test "unit calls bare returns and generic fallthrough preserve results with allocation failures" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}

// spec: UNIT-3
test "unit data and host boundaries reject unsupported ABI values explicitly" {
    const typed = @import("typed.zig");
    try t.expectEqual(typed.Type.unit, @as(typed.Value, .unit).typeOf());
    try t.expect(!typed.Type.unit.isAggregate());
    try t.expect(!typed.Type.unit.isInteger());
    try t.expectEqual(@as(?u3, null), typed.Type.unit.capabilityIndex());
    try t.expectError(error.NotDataType, @import("data_type.zig").check(t.allocator, &.{}, .unit, true));
    var c = try language.Compilation.init(t.allocator, "host.my", "host fn f()->unit effects(host);fn main()->i64{return 0;}");
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_HOST_SIGNATURE", c.diagnostics.items[0].code);
}

fn publicUnit(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
    if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
    return allocator.dupe(u8, "module main;export finish;fn finish()->unit{}fn main()->i64{finish();return 42;}");
}
// spec: UNIT-6
test "public unit schemas describe a distinct type while unsupported copied ABIs reject invocation" {
    var guest: language.embedded_project.Program = undefined;
    try guest.init(t.allocator, .{ .context = null, .read = publicUnit });
    defer guest.deinit();
    const schema = try language.schema.render(t.allocator, &guest.compilation);
    defer t.allocator.free(schema);
    const parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, schema, .{});
    defer parsed.deinit();
    try t.expect(std.mem.indexOf(u8, schema, "\"kind\":\"unit\"") != null);
    try t.expectError(error.NotDataType, guest.compilation.invokePublic(t.allocator, "main::finish", &.{}, .{}));
    try t.expectEqual(@as(i64, 42), (try language.vm.run(t.allocator, guest.compilation.code.?)).value);
}
