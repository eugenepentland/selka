//! Binary64 bit patterns have specified NaNs, signed zeros, conversions and rounding.
const std = @import("std");
const t = std.testing;
const floats = @import("floats.zig");
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
fn binary(op: @import("typed.zig").BinaryOp, a: f64, b: f64) !u64 {
    return @intCast((try floats.binary(op, @bitCast(a), @bitCast(b))).integer.value);
}
// spec: FLOAT-DOMAIN-1
test "binary64 IEEE boundaries canonical NaNs signed zero and FloatConversion" {
    try t.expectEqual(@as(u64, 0), try binary(.f64_add, -0.0, 0.0));
    try t.expectEqual(@as(u64, 0x8000000000000000), try binary(.f64_mul, -0.0, 1.0));
    try t.expectEqual(@as(u64, 0x7ff0000000000000), try binary(.f64_div, 1.0, 0.0));
    try t.expectEqual(floats.canonical_nan, try binary(.f64_div, 0.0, 0.0));
    try t.expectEqual(floats.canonical_nan, try floats.unary(.f64_sqrt, @bitCast(@as(f64, -1.0))));
    try t.expectEqual(@as(u64, 1), try binary(.f64_mul, @bitCast(@as(u64, 2)), 0.5));
    try t.expectEqual(@as(u64, @bitCast(@as(f64, 1.0))), try binary(.f64_add, 1.0, 0x1p-53));
    try t.expect((try floats.binary(.f64_eq, 0, 0x8000000000000000)).bool);
    try t.expect(!(try floats.binary(.f64_eq, floats.canonical_nan, floats.canonical_nan)).bool);
    try t.expectError(error.FloatConversion, floats.unary(.f64_to_u64, 0x7ff0000000000000));
    try t.expectError(error.FloatConversion, floats.unary(.f64_to_u64, @bitCast(@as(f64, 18446744073709551616.0))));
    try t.expectEqual(@as(u64, 0), try floats.unary(.f64_to_u64, @bitCast(@as(f64, -0.75))));
}

const intrinsic_source =
    \\def main() -> int:
    \\    root = int(__float_sqrt(1764.0))
    \\    return root
;
fn intrinsicScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "float.my", intrinsic_source);
    defer c.deinit();
    try t.expectEqual(@as(i64, 42), (try native.run(&c)).value);
}
// spec-case: FLOAT-DOMAIN-1
test "float intrinsics evaluate at runtime and reject raw operands" {
    var bad = try language.Compilation.init(t.allocator, "float.my",
        \\def main() -> int:
        \\    return int(__float_sqrt(1))
    );
    defer bad.deinit();
    try t.expectError(error.SourceError, bad.check());
    try t.expectEqualStrings("E_TYPE", bad.diagnostics.items[0].code);
    try intrinsicScenario(t.allocator);
}

// spec-case: FLOAT-DOMAIN-1
test "ordinary float values reach the same binary64 semantics without a nominal domain" {
    var c = try language.Compilation.init(t.allocator, "float.my", "def main() -> int:\n" ++
        "    if 0.1 + 0.2 == 0.3:\n" ++
        "        return 1\n" ++
        "    if 1.0 / 0.0 <= 1.7976931348623157e308:\n" ++
        "        return 2\n" ++
        "    nan = 0.0 / 0.0\n" ++
        "    if nan == nan:\n" ++
        "        return 3\n" ++
        "    if 0.0 - 0.0 != 0.0:\n" ++
        "        return 4\n" ++
        "    return int(21.0 * 2.0)\n");
    defer c.deinit();
    try t.expectEqual(@as(i64, 42), (try native.run(&c)).value);
}

// spec: FLOAT-INTRINSIC-FLOAT-1
test "a float-in float-out intrinsic takes a float operand and answers a float" {
    var c = try language.Compilation.init(t.allocator, "float.my",
        \\def main() -> int:
        \\    value = 1764.0
        \\    root = sqrt(value)
        \\    if root != 42.0:
        \\        return 1
        \\    if floor(0.0 - 1.5) != 0.0 - 2.0 or ceil(0.0 - 1.5) != 0.0 - 1.0:
        \\        return 2
        \\    if trunc(0.0 - 1.9) != 0.0 - 1.0 or abs(0.0 - 2.5) != 2.5:
        \\        return 3
        \\    if __float_sqrt(value) != root:
        \\        return 4
        \\    return int(abs(0.0 - root))
    );
    defer c.deinit();
    try t.expectEqual(@as(i64, 42), (try native.run(&c)).value);
    // Every removed raw spelling is a located migration diagnostic.
    var raw = try language.Compilation.init(t.allocator, "float.my",
        \\def main() -> int:
        \\    return int(f64_to_u64(f64_sqrt(1764.0)))
    );
    defer raw.deinit();
    try t.expectError(error.SourceError, raw.check());
    try t.expectEqualStrings("E_REMOVED_SPELLING", raw.diagnostics.items[0].code);
}
