//! Constant-divisor recipes, emitted code, and observable trap counterexamples.
const std = @import("std");
const t = std.testing;
const division = @import("qbe_constant_divisor.zig");
const compiler = @import("compiler.zig");
const native = @import("native_execute.zig");

fn sweep() !void {
    for (1..257) |divisor| {
        const recipe = division.plan(divisor).?;
        for (0..65536) |numerator| try t.expectEqual(numerator / divisor, division.quotient(recipe, numerator));
    }
    for (1..64) |bit| {
        const power = @as(u64, 1) << @intCast(bit);
        for ([_]u64{ power - 1, power, power + 1, std.math.maxInt(u64) - power, std.math.maxInt(u64) }) |divisor| {
            const recipe = division.plan(divisor).?;
            for ([_]u64{ 0, 1, divisor - 1, divisor, divisor +% 1, power - 1, power, std.math.maxInt(u64) - 1, std.math.maxInt(u64) }) |numerator|
                try t.expectEqual(numerator / divisor, division.quotient(recipe, numerator));
        }
    }
}

// spec: QBE-CONSTANT-DIVISOR-1
test "constant divisor recipes cover exhaustive low values and every high-bit boundary" {
    try t.expect(division.plan(0) == null);
    try sweep();
}

const source =
    \\def seven(x: int) -> int:
    \\    return x // 7
    \\def power(x: int) -> int:
    \\    return x // 8
    \\def negative(x: int) -> int:
    \\    return remtrunc(x, -7)
    \\def wide(x: u64) -> u64:
    \\    return x // 18446744073709551615u64
    \\def variable(x: int, d: int) -> int:
    \\    return x // d
    \\def main() -> int:
    \\    return seven(-100) + power(100) + negative(-100) + int(wide(18446744073709551615u64))
;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}

// spec-case: QBE-CONSTANT-DIVISOR-1
test "constant divisor lowering emits multiply-high and shifts while variable division stays checked" {
    var compilation = try compiler.Compilation.init(t.allocator, "constant_divisor.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    var parsed = try std.json.parseFromSlice(Manifest, t.allocator, text, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    const seven = try named(parsed.value, "seven");
    try t.expect(std.mem.indexOf(u8, seven, " =l umulh ") != null);
    try t.expect(std.mem.indexOf(u8, seven, " =l div ") == null);
    try t.expect(std.mem.indexOf(u8, seven, " =l rem ") == null);
    try t.expect(std.mem.indexOf(u8, try named(parsed.value, "power"), " =l sar ") != null);
    try t.expect(std.mem.indexOf(u8, try named(parsed.value, "negative"), " =l umulh ") != null);
    try t.expect(std.mem.indexOf(u8, try named(parsed.value, "wide"), " =l umulh ") != null);
    try t.expect(std.mem.indexOf(u8, try named(parsed.value, "variable"), "myl_qbe_fail_division") != null);
    try t.expectEqual(@as(i64, -4), (try native.run(&compilation)).value);
}

fn trapCase(divisor: i64, numerator: i64, comptime remainder: bool) !void {
    const expression = if (remainder) "remtrunc(x, {d})" else "divtrunc(x, {d})";
    const operation = try std.fmt.allocPrint(t.allocator, expression, .{divisor});
    defer t.allocator.free(operation);
    const input = try std.fmt.allocPrint(t.allocator, "def divide(out: Stream, x: int) -> int:\n    out.print(17)\n    value = {s}\n" ++
        "    out.print(23)\n    return value\ndef main(out: Stream) -> int:\n    return divide(out, {d})\n", .{ operation, numerator });
    defer t.allocator.free(input);
    var compilation = try compiler.Compilation.init(t.allocator, "constant_trap.my", input);
    defer compilation.deinit();
    const ordinary = try native.run(&compilation);
    const fast = try native.runUnaccounted(&compilation, .{});
    try t.expectEqual(ordinary.failed, fast.failed);
    try t.expectEqual(ordinary.value, fast.value);
    try t.expectEqualStrings(ordinary.stdout, fast.stdout);
    try t.expectEqualStrings(ordinary.stderr, fast.stderr);
    try t.expect(std.meta.eql(ordinary.trap.detail, fast.trap.detail));
    try t.expect(std.mem.indexOf(u8, ordinary.stdout, "17") != null);
    if (divisor == 0 or (!remainder and divisor == -1)) {
        try t.expect(fast.failed);
        try t.expect(std.mem.indexOf(u8, fast.stdout, "23") == null);
        try t.expectEqual(@as(u64, 3), fast.trap.line);
    } else {
        try t.expect(!fast.failed);
        try t.expectEqual(@as(i64, 0), fast.value);
    }
}

// spec-case: QBE-CONSTANT-DIVISOR-1
test "constant divisor zero and minimum-over-negative-one preserve trap provenance and partial output" {
    try trapCase(0, 31, false);
    try trapCase(0, -31, true);
    try trapCase(-1, std.math.minInt(i64), false);
    try trapCase(-1, std.math.minInt(i64), true);
    try t.expect(true);
}

// spec-case: QBE-CONSTANT-DIVISOR-1
test "constant divisor multiply-high translates by widening before multiplication" {
    const llvm = @import("qbe_build_llvm.zig");
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const signatures: llvm.Signatures = .empty;
    const table: llvm.RuntimeTable = .{};
    var diagnostic: llvm.Diagnostic = .{ .unit = "high" };
    const ir = try llvm.translate(arena.allocator(), "export function l $high(l %a, l %b) {\n@start\n %v =l umulh %a, %b\n ret %v\n}\n", .{ .signatures = &signatures, .runtime = &table }, &diagnostic);
    try t.expect(std.mem.indexOf(u8, ir, " = mul i128 ") != null);
    try t.expect(std.mem.indexOf(u8, ir, " = lshr i128 ") != null);
}
