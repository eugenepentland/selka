//! Immutable-byte iteration composes existing guarded storage/lifetime proofs.
const std = @import("std");
const t = std.testing;
const compiler = @import("compiler.zig");
const native = @import("native_execute.zig");
const runtime = @import("runtime_mode.zig");
const source =
    \\def xor_sum(raw: bytes, mask: int, seed: int) -> int:
    \\    total = seed
    \\    for value in raw:
    \\        total += value ^ mask
    \\        _ = value ^ 1
    \\    return total
    \\def mutable(raw: mut byte_buffer) -> int:
    \\    total = 0
    \\    for value in raw:
    \\        total += value
    \\        _ = raw.append_byte(value)
    \\    return total
    \\def observed(raw: bytes, out: Stream) -> int:
    \\    total = 0
    \\    for value in raw:
    \\        out.print(value)
    \\        total += value
    \\    return total
    \\def main() -> int:
    \\    return xor_sum(b"abcd", 7, 13)
;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };

fn emitted(steps: bool) !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "byte_iteration.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbeWithOptions(t.allocator, .{ .step_checks = steps, .frame_checks = false });
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, name, function.name)) return function.il;
    return error.TestUnexpectedResult;
}
fn sameOutcome(length: usize, mask: i64, seed: i64) !void {
    const input = try std.fmt.allocPrint(t.allocator, "def main() -> int:\n    raw = bytes([(i * 37) % 256 for i in range({d})])\n" ++
        "    total = {d}\n    for value in raw:\n        total += value ^ {d}\n    return total\n", .{ length, seed, mask });
    defer t.allocator.free(input);
    var compilation = try compiler.Compilation.init(t.allocator, "byte_iteration_boundary.my", input);
    defer compilation.deinit();
    const ordinary = try native.run(&compilation);
    const fast = try native.runUnaccounted(&compilation, .{});
    try t.expectEqual(ordinary.failed, fast.failed);
    try t.expectEqual(ordinary.value, fast.value);
    try t.expectEqualStrings(ordinary.trap.code, fast.trap.code);
    try t.expectEqualDeep(ordinary.trap.detail, fast.trap.detail);
    try t.expectEqualStrings(ordinary.stdout, fast.stdout);
    try t.expectEqualStrings(ordinary.stderr, fast.stderr);
}
fn boundaries() !void {
    for ([_]usize{ 0, 1, 15, 16, 17, 1024, 1041 }) |length| try sameOutcome(length, 255, 13);
    for ([_]i64{ -1, 256, std.math.minInt(i64), std.math.maxInt(i64) }) |mask| try sameOutcome(32, mask, 0);
    try sameOutcome(32, 0, std.math.maxInt(i64) - 1);
    try sameOutcome(32, 0, std.math.minInt(i64));
}

// spec: RC-READ-BYTE-ITERATION-1
test "RC immutable byte iteration retains arithmetic traps and ownership fallback" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var fast = try emitted(false);
    defer fast.deinit();
    const il = try named(fast.value, "xor_sum");
    const start = std.mem.indexOf(u8, il, "\n@fi") orelse return error.TestUnexpectedResult;
    const end = std.mem.indexOf(u8, il, "\n@oi") orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.indexOf(u8, il, "# RC-READ-LIST-VERSION-1") != null);
    try t.expect(std.mem.indexOf(u8, il[start..end], "myl_qbe_fail_iteration") == null);
    try t.expect(std.mem.indexOf(u8, il[start..end], "myl_qbe_fail_overflow_op") != null);
    try t.expect(std.mem.indexOf(u8, try named(fast.value, "mutable"), "\n@fi") == null);
    try t.expect(std.mem.indexOf(u8, try named(fast.value, "observed"), "\n@fi") == null);
    var counted = try emitted(true);
    defer counted.deinit();
    try t.expect(std.mem.indexOf(u8, try named(counted.value, "xor_sum"), "\n@fi") == null);
    try boundaries();
}
