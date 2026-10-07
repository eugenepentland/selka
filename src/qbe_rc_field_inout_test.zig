//! Direct field inout keeps existing value snapshots and refuses observers.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const native = @import("native_execute.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const marker = "# RC-FIELD-INOUT-1";
const source =
    \\record Rt:
    \\    data: list[int]
    \\    top: int
    \\record It:
    \\    rt: Rt
    \\    tag: int
    \\def put(rt: mut Rt, index: int, value: int):
    \\    rt.data[index] = value
    \\    rt.top += 1
    \\def closed(it: mut It, index: int, value: int):
    \\    rt = it.rt
    \\    put(mut rt, index, value)
    \\    it.rt = rt
    \\def observed(it: mut It):
    \\    rt = it.rt
    \\    put(mut rt, 0, it.tag)
    \\    it.rt = rt
    \\def branched(it: mut It, flag: bool):
    \\    rt = it.rt
    \\    if flag:
    \\        put(mut rt, 0, 7)
    \\    it.rt = rt
    \\def early(it: mut It, stop: bool):
    \\    rt = it.rt
    \\    put(mut rt, 0, 7)
    \\    if stop:
    \\        return
    \\    it.rt = rt
    \\def escaping(it: mut It) -> Rt:
    \\    rt = it.rt
    \\    put(mut rt, 0, 7)
    \\    it.rt = rt
    \\    return rt
    \\def callback(rt: mut Rt, action: def(int) -> int effects()):
    \\    rt.data[0] = action(3)
    \\def callbacks(it: mut It, action: def(int) -> int effects()):
    \\    rt = it.rt
    \\    callback(mut rt, action)
    \\    it.rt = rt
    \\def nonplain(rt: mut Rt, other: list[int]):
    \\    rt.data[0] = len(other)
    \\def nonplain_argument(it: mut It, other: list[int]):
    \\    rt = it.rt
    \\    nonplain(mut rt, other)
    \\    it.rt = rt
    \\def rebind(rt: mut Rt, value: int):
    \\    if value < 0:
    \\        return
    \\    rt = Rt([value], 2)
    \\def detached(it: mut It, value: int):
    \\    rt = it.rt
    \\    rebind(mut rt, value)
    \\    it.rt = rt
    \\def main() -> int:
    \\    it = It(Rt([1,2], 0), 9)
    \\    saved = it
    \\    alias = it.rt.data
    \\    closed(mut it, 0, 7)
    \\    assert it.rt.data == [7,2] and it.rt.top == 1
    \\    assert saved.rt.data == [1,2] and saved.rt.top == 0
    \\    assert alias == [1,2]
    \\    detached(mut it, -1)
    \\    assert it.rt.data == [7,2]
    \\    detached(mut it, 11)
    \\    assert it.rt.data == [11] and it.rt.top == 2
    \\    assert saved.rt.data == [1,2] and alias == [1,2]
    \\    return 0
;

fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

// spec: RC-FIELD-INOUT-1
test "RC field inout removes closed record carriers and refuses observers callbacks and exits" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "field-inout.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbeWithOptions(t.allocator, .{ .step_checks = false });
    defer t.allocator.free(text);
    var manifest = try std.json.parseFromSlice(Manifest, t.allocator, text, .{ .ignore_unknown_fields = true });
    defer manifest.deinit();
    const closed = try named(manifest.value, "closed");
    try t.expect(contains(closed, marker));
    try t.expect(!contains(closed, " blit "));
    try t.expect(contains(try named(manifest.value, "detached"), marker));
    for ([_][]const u8{ "observed", "branched", "early", "escaping", "callbacks", "nonplain_argument" }) |name| {
        try t.expect(!contains(try named(manifest.value, name), marker));
    }
    const counted = try compilation.emitQbeWithOptions(t.allocator, .{ .step_checks = true });
    defer t.allocator.free(counted);
    try t.expect(!contains(counted, marker));
}

// spec-case: RC-FIELD-INOUT-1
test "RC field inout native snapshots detached aliases and callee early return survive GC stress" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "field-inout.my", source);
    defer compilation.deinit();
    for ([_]bool{ false, true }) |_| {
        const outcome = try native.runUnaccounted(&compilation, .{});
        try t.expect(!outcome.failed);
        try t.expectEqual(@as(i64, 0), outcome.value);
    }
}

// spec-case: RC-FIELD-INOUT-1
test "RC field inout trap unwinding preserves exact bounds errors and traces" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    for ([_]i64{ 0, -1, -3, std.math.minInt(i64), std.math.maxInt(i64) }) |index| {
        const main = try std.fmt.allocPrint(t.allocator, "def main() -> int:\n    it = It(Rt([1,2], 0), 9)\n    saved = it\n    closed(mut it, {d}, 7)\n    return 0\n", .{index});
        defer t.allocator.free(main);
        const at = std.mem.indexOf(u8, source, "def main()") orelse return error.TestUnexpectedResult;
        const input = try std.mem.concat(t.allocator, u8, &.{ source[0..at], main });
        defer t.allocator.free(input);
        var compilation = try compiler.Compilation.init(t.allocator, "field-trap.my", input);
        defer compilation.deinit();
        const reference = try native.run(&compilation);
        const fast = try native.runUnaccounted(&compilation, .{});
        try t.expectEqual(reference.failed, fast.failed);
        try t.expectEqual(reference.value, fast.value);
        try t.expectEqualStrings(reference.stderr, fast.stderr);
        try t.expect(std.meta.eql(reference.trap.detail, fast.trap.detail));
    }
}
