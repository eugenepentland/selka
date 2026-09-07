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

fn bulkProvider(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
    const source = if (std.mem.eql(u8, path, "io.my"))
        "module io;export length;export byte;export put;export Block;export read_block;export write_block;" ++
            "struct Block{bytes:[256]u8,count:i64}" ++
            "host fn length()->i64 effects(host);host fn byte(index:i64)->u8 effects(host);" ++
            "host fn put(value:u8)->i64 effects(host);host fn read_block(offset:i64)->Block effects(host);" ++
            "host fn write_block(block:Block)->i64 effects(host);"
    else if (std.mem.eql(u8, path, "main.my"))
        "module main;import io;fn main()->i64{let size=io::length();let mut offset=0;" ++
            "while offset<size{let block=io::read_block(offset);let count=block.count;" ++
            "if io::write_block(block)!=count{return 1;}offset+=count;}return 0;}"
    else
        return error.NotFound;
    if (source.len > limit) return error.TooLarge;
    return allocator.dupe(u8, source);
}
fn bulkScenario(allocator: std.mem.Allocator, code: language.bytecode.Program) !void {
    var input: [777]u8 = undefined;
    for (&input, 0..) |*byte, i| byte.* = @truncate(i);
    var context: bridge.Context = .{ .allocator = allocator, .input = &input, .output_limit = input.len };
    defer context.deinit();
    var registry = try language.vm_host.Registry.init(allocator, code);
    defer registry.deinit();
    try context.install(&registry);
    // Four reads, four writes, one length call; byte-at-a-time requires 1555.
    const result = try language.vm.runWithHost(allocator, code, .{}, &registry, .{ .max_calls = 9, .max_work = 1572 });
    try t.expectEqual(@as(i64, 0), result.value);
    try t.expectEqualSlices(u8, &input, context.output.items);
    context.output.clearRetainingCapacity();
    context.output_limit = 260;
    const short = try language.vm.runWithHost(allocator, code, .{}, &registry, .{});
    try t.expectEqual(@as(i64, 1), short.value);
    try t.expectEqualSlices(u8, input[0..260], context.output.items);
}
// spec: BYTE-IO-BULK-1
test "copied byte blocks use bounded callbacks and preserve short writes under allocation failure" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = bulkProvider });
    defer program.deinit();
    try bulkScenario(t.allocator, program.compilation.code.?);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), bulkScenario, .{program.compilation.code.?});
}
test "bulk EOF zero padding invalid offsets counts and budget failure do not append output" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = bulkProvider });
    defer program.deinit();
    var context: bridge.Context = .{ .allocator = t.allocator, .input = "\xff\x00", .output_limit = 1 };
    defer context.deinit();
    var registry = try language.vm_host.Registry.init(t.allocator, program.compilation.code.?);
    defer registry.deinit();
    try context.install(&registry);
    const session = try registry.begin(t.allocator, program.compilation.code.?, .{ .max_work = 17 });
    defer session.close() catch unreachable;
    const read = try registry.registry.resolve("io::read_block");
    const write = try registry.registry.resolve("io::write_block");
    const block = try session.call(read, &.{.{ .i64 = 0 }});
    defer block.release(t.allocator);
    try t.expectEqual(@as(i64, 2), block.aggregate.fields[1].i64);
    try t.expectEqual(@as(i128, 0), block.aggregate.fields[0].aggregate.fields[255].integer.value);
    try t.expectEqual(@as(i64, 1), (try session.call(write, &.{block})).i64);
    try t.expectEqual(@as(i64, 0), (try session.call(write, &.{block})).i64);
    const eof = try session.call(read, &.{.{ .i64 = 2 }});
    defer eof.release(t.allocator);
    try t.expectEqual(@as(i64, 0), eof.aggregate.fields[1].i64);
    try hostFailure(error.HostFailure, session.call(read, &.{.{ .i64 = -1 }}));
    try hostFailure(error.HostFailure, session.call(read, &.{.{ .i64 = 3 }}));
    const invalid = try language.vm.Value.create(t.allocator, block.aggregate.ty, &.{ block.aggregate.fields[0], .{ .i64 = 257 } });
    defer invalid.release(t.allocator);
    try hostFailure(error.HostFailure, session.call(write, &.{invalid}));
    try hostFailure(error.HostWorkLimit, session.call(read, &.{.{ .i64 = 0 }}));
    try t.expectEqualSlices(u8, "\xff", context.output.items);
}
// spec: BYTE-IO-LIMITS-1
test "runner limits accept explicit zero storage but reject duplicate overflow and zero execution budgets" {
    const limits = @import("limits.zig");
    const options = try limits.parse(&.{ "io", "--project", ".", "--max-input=0", "--max-output=3", "--max-steps=4", "--max-calls=5", "--max-work=6" });
    try t.expectEqual(@as(usize, 0), options.input);
    try t.expectEqual(@as(usize, 3), options.output);
    try t.expectEqual(@as(u64, 4), options.execution.steps);
    try t.expectEqual(@as(u64, 5), options.execution.calls);
    try t.expectEqual(@as(u64, 6), options.execution.work);
    for ([_][]const u8{ "--unknown=1", "--max-steps=0", "--max-input=-1", "--max-output=+1", "--max-work=18446744073709551616", "--max-calls=" }) |invalid|
        try t.expectError(error.InvalidArguments, limits.parse(&.{ "io", "--project", ".", invalid }));
    try t.expectError(error.InvalidArguments, limits.parse(&.{ "io", "--project", ".", "--max-work=1", "--max-work=2" }));
}

// spec: RUNTIME-BYTES-2
test "runner memory quotas parse zero limits and reject duplicate InvalidArguments" {
    const parse = @import("limits.zig").parse;
    const parsed = try parse(&.{ "mylang-io", "--project", ".", "--max-runtime-bytes=100", "--max-vm-bytes=80", "--max-host-bytes=0", "--memory-report" });
    try t.expectEqual(@as(usize, 100), parsed.memory.total);
    try t.expectEqual(@as(usize, 80), parsed.memory.vm);
    try t.expectEqual(@as(usize, 0), parsed.memory.host);
    try t.expect(parsed.memory.output);
    try t.expectError(error.InvalidArguments, parse(&.{ "mylang-io", "--project", ".", "--max-vm-bytes=1", "--max-vm-bytes=2" }));
    try t.expectError(error.InvalidArguments, parse(&.{ "mylang-io", "--project", ".", "--memory-report", "--memory-report" }));
    try t.expectError(error.InvalidArguments, parse(&.{ "mylang-io", "--project", ".", "--max-host-bytes=-1" }));
}
