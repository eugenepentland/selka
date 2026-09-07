//! Exercise raw bytes, failure bounds and allocation cleanup through the real registry.
const std = @import("std");
const t = std.testing;
const language = @import("mylang");
const bridge = @import("host.zig");
fn provider(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
    const bytes = if (std.mem.eql(u8, path, "io.my"))
        "module io;export length;export byte;export put;host fn length()->i64 effects(host);host fn byte(index:i64)->u8 effects(host);host fn put(value:u8)->i64 effects(host);"
    else if (std.mem.eql(u8, path, "main.my"))
        "module main;import io;fn main()->i64{discard io::put(io::byte(0));return io::length();}"
    else
        return error.NotFound;
    if (bytes.len > limit) return error.TooLarge;
    return allocator.dupe(u8, bytes);
}
fn scenario(allocator: std.mem.Allocator, code: language.bytecode.Program) !void {
    var context: bridge.Context = .{ .allocator = allocator, .input = "\x00\xff", .output_limit = 2 };
    defer context.deinit();
    var registry = try language.vm_host.Registry.init(allocator, code);
    defer registry.deinit();
    try context.install(&registry);
    const session = try registry.begin(allocator, code, .{});
    defer session.close() catch |err| std.debug.panic("byte I/O session cleanup: {s}", .{@errorName(err)});
    const length = try registry.registry.resolve("io::length");
    const byte = try registry.registry.resolve("io::byte");
    const put = try registry.registry.resolve("io::put");
    try t.expectEqual(@as(i64, 2), (try session.call(length, &.{})).i64);
    for ([_]u8{ 0, 255 }, 0..) |expected, index| {
        const value = try session.call(byte, &.{.{ .i64 = @intCast(index) }});
        try t.expectEqual(@as(i128, expected), value.integer.value);
        _ = try session.call(put, &.{value});
    }
    try t.expectEqualSlices(u8, "\x00\xff", context.output.items);
    try hostFailure(error.HostFailure, session.call(byte, &.{.{ .i64 = -1 }}));
    try hostFailure(error.HostFailure, session.call(byte, &.{.{ .i64 = 2 }}));
    try hostFailure(error.HostWorkLimit, session.call(put, &.{language.vm.Value.number(.u8, 65)}));
}
// spec: BYTE-IO-1
test "raw byte registry preserves invalid text and rejects bounds with allocation cleanup" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = provider });
    defer program.deinit();
    try scenario(t.allocator, program.compilation.code.?);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{program.compilation.code.?});
}

fn hostFailure(expected: anyerror, result: language.host_functions.Error!language.vm.Value) !void {
    const value = result catch |err| {
        if (err == error.OutOfMemory) return err;
        try t.expectEqual(expected, err);
        return;
    };
    value.release(t.allocator);
    try t.expect(false);
}
test {
    _ = @import("runner.zig");
}

fn textProvider(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
    if (!std.mem.eql(u8, path, "main.my")) return provider(null, allocator, path, limit);
    const source = "module main;import std_text;fn main()->i64{" ++
        "discard std_text::emit(\"é:\");discard std_text::number(-9223372036854775808);" ++
        "discard std_text::emit(\",\");discard std_text::number(9223372036854775807);" ++
        "discard std_text::emit(\",\");return std_text::number(0);}";
    if (source.len > limit) return error.TooLarge;
    return allocator.dupe(u8, source);
}
// spec: STANDARD-TEXT-1
test "standard text emits UTF8 and all signed integer endpoints through the ordinary host" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = textProvider });
    defer program.deinit();
    var context: bridge.Context = .{ .allocator = t.allocator, .input = "" };
    defer context.deinit();
    var registry = try language.vm_host.Registry.init(t.allocator, program.compilation.code.?);
    defer registry.deinit();
    try context.install(&registry);
    const result = try language.vm.runWithHost(t.allocator, program.compilation.code.?, .{}, &registry, .{});
    try t.expectEqual(@as(i64, 0), result.value);
    try t.expectEqualStrings("é:-9223372036854775808,9223372036854775807,0", context.output.items);
}
