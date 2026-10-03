//! Modulo replacement and scalar-domain loop proofs retain original fallback.
const std = @import("std");
const t = std.testing;
const compiler = @import("compiler.zig");
const native = @import("native_execute.zig");
const runtime = @import("runtime_mode.zig");
const source =
    \\def calculate(count: int, seed: int) -> int:
    \\    total = seed
    \\    for at in range(count):
    \\        total = (total + at * 7) % 1000003
    \\    return total
    \\def affine(at: int) -> int:
    \\    return at * 7
    \\def inlined(count: int, seed: int) -> int:
    \\    total = seed
    \\    for at in range(count):
    \\        total = (total + affine(at)) % 1000003
    \\    return total
    \\def domains(count: int) -> int:
    \\    value = 0.0
    \\    checksum = 0
    \\    for at in range(count):
    \\        value += float(at) * 0.5
    \\        checksum += at
    \\    return int(value) + checksum
    \\def convert_loop(count: int, value: float) -> int:
    \\    checksum = 0
    \\    for at in range(count):
    \\        checksum = int(i8(value))
    \\    return checksum
    \\def main() -> int:
    \\    return inlined(32, 17) + domains(32)
;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}
fn copied(body: []const u8) ![]const u8 {
    const start = std.mem.indexOf(u8, body, "\n@fi") orelse return error.TestUnexpectedResult;
    const end = std.mem.indexOf(u8, body, "\n@oi") orelse return error.TestUnexpectedResult;
    return body[start..end];
}
fn emitted(steps: bool) !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "bounded_write.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbeWithOptions(t.allocator, .{ .step_checks = steps, .frame_checks = false });
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}

// spec: QBE-LOOP-BOUNDED-WRITE-1
test "bounded write loop removes modular accumulator checks after guarding its entry" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted(false);
    defer manifest.deinit();
    const body = try named(manifest.value, "calculate");
    const fast = try copied(body);
    try t.expect(std.mem.indexOf(u8, fast, "myl_qbe_fail_") == null);
    try t.expect(std.mem.indexOf(u8, body, "myl_qbe_fail_overflow_op") != null);
    try t.expect(std.mem.indexOf(u8, body, " =l umulh ") != null);
    var compilation = try compiler.Compilation.init(t.allocator, "bounded_write.my", source);
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 4233), (try native.runUnaccounted(&compilation, .{})).value);
}

// spec: RC-SCALAR-LOOP-COMPOSE-1
test "bounded write loop composes inline provenance and float domains without dropping conversion checks" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted(false);
    defer manifest.deinit();
    try t.expect(std.mem.indexOf(u8, try copied(try named(manifest.value, "inlined")), "myl_qbe_fail_") == null);
    const domain = try copied(try named(manifest.value, "domains"));
    try t.expect(std.mem.indexOf(u8, domain, " =d sltof ") != null);
    try t.expect(std.mem.indexOf(u8, domain, "myl_qbe_fail_overflow_op") == null);
    try t.expect(std.mem.indexOf(u8, try copied(try named(manifest.value, "convert_loop")), "myl_qbe_float_integer") != null);
    var counted = try emitted(true);
    defer counted.deinit();
    try t.expect(std.mem.indexOf(u8, try named(counted.value, "inlined"), "\n@fi") == null);
    try t.expect(std.mem.indexOf(u8, try named(counted.value, "domains"), "\n@fi") == null);
}

fn floatConversion(value: []const u8, traps: bool) !void {
    const input = try std.fmt.allocPrint(t.allocator, "def calculate(count: int, value: float) -> int:\n    result = 0\n    for at in range(count):\n" ++
        "        result = int(i8(value))\n    return result\ndef main() -> int:\n    return calculate(32, {s})\n", .{value});
    defer t.allocator.free(input);
    var compilation = try compiler.Compilation.init(t.allocator, "float_loop.my", input);
    defer compilation.deinit();
    const ordinary = try native.run(&compilation);
    const fast = try native.runUnaccounted(&compilation, .{});
    try t.expectEqual(traps, fast.failed);
    try t.expectEqual(ordinary.failed, fast.failed);
    try t.expectEqual(ordinary.value, fast.value);
    try t.expectEqualStrings(ordinary.stderr, fast.stderr);
    try t.expect(std.meta.eql(ordinary.trap.detail, fast.trap.detail));
}

// spec-case: RC-SCALAR-LOOP-COMPOSE-1
test "bounded write loop float conversion keeps finite overflow infinity and NaN outcomes" {
    try floatConversion("1.5", false);
    try floatConversion("128.0", true);
    try floatConversion("divtrunc(1.0, 0.0)", true);
    try floatConversion("divtrunc(0.0, 0.0)", true);
    try t.expect(true);
}

fn fallback(seed: i64, count: i64) !void {
    const input = try std.fmt.allocPrint(t.allocator, "def calculate(count: int, seed: int) -> int:\n    total = seed\n    for at in range(count):\n" ++
        "        total = (total + at * 7) % 1000003\n    return total\ndef main() -> int:\n    return calculate({d}, {d})\n", .{ count, seed });
    defer t.allocator.free(input);
    var compilation = try compiler.Compilation.init(t.allocator, "bounded_fallback.my", input);
    defer compilation.deinit();
    const ordinary = try native.run(&compilation);
    const fast = try native.runUnaccounted(&compilation, .{});
    try t.expectEqual(ordinary.failed, fast.failed);
    try t.expectEqual(ordinary.value, fast.value);
    try t.expectEqualStrings(ordinary.stderr, fast.stderr);
    try t.expect(std.meta.eql(ordinary.trap.detail, fast.trap.detail));
}

// spec-case: QBE-LOOP-BOUNDED-WRITE-1
test "bounded write loop keeps overflow negative large entry and empty short-loop fallback exact" {
    try fallback(std.math.maxInt(i64), 32);
    try fallback(std.math.minInt(i64), 32);
    try fallback(-31, 32);
    try fallback(std.math.maxInt(i64), 0);
    try fallback(17, 4);
    try t.expect(true);
}
