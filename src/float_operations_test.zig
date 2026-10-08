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
    \\    root = int(sqrt(1764.0))
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
        \\    return int(sqrt(1))
    );
    defer bad.deinit();
    try t.expectError(error.SourceError, bad.check());
    try t.expectEqualStrings("E_TYPE", bad.diagnostics.items[0].code);
    try intrinsicScenario(t.allocator);
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
        \\    if sqrt(value) != root:
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

// spec: INTERNAL-NAME-1
test "the reserved intrinsic spelling is rejected in ordinary source" {
    var c = try language.Compilation.init(t.allocator, "float.my",
        \\def main() -> int:
        \\    return int(__float_sqrt(1764.0))
    );
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_INTERNAL_NAME", c.diagnostics.items[0].code);
    // A source path that merely looks like the embedded library does not grant
    // the intrinsic: the bytes must be the compiler-owned module.
    var spoof = try language.Compilation.init(t.allocator, "@stdlib/math.my",
        \\def main() -> int:
        \\    return int(__float_sqrt(1764.0))
    );
    defer spoof.deinit();
    try t.expectError(error.SourceError, spoof.check());
    try t.expectEqualStrings("E_INTERNAL_NAME", spoof.diagnostics.items[0].code);
}

// spec-case: STANDARD-MATH-TRIG-1
test "trigonometric intrinsics retain native bits and require trusted library source" {
    const negative_zero: f64 = -0.0;
    const tiny: f64 = @bitCast(@as(u64, 1));
    try t.expectEqual(@as(u64, @bitCast(negative_zero)), try floats.unary(.f64_sin, @bitCast(negative_zero)));
    try t.expectEqual(@as(u64, @bitCast(@as(f64, 1.0))), try floats.unary(.f64_cos, @bitCast(negative_zero)));
    try t.expectEqual(@as(u64, 1), try floats.unary(.f64_sin, @bitCast(tiny)));
    try t.expectEqual(@as(u64, @bitCast(@sin(@as(f64, 1.0e300)))), try floats.unary(.f64_sin, @bitCast(@as(f64, 1.0e300))));
    try t.expectEqual(@as(u64, @bitCast(@cos(@as(f64, 1.0e300)))), try floats.unary(.f64_cos, @bitCast(@as(f64, 1.0e300))));
    var raw = try language.Compilation.init(t.allocator, "trig.my", "def main() -> int:\n    return int(__float_sin(0.0))\n");
    defer raw.deinit();
    try t.expectError(error.SourceError, raw.check());
    try t.expectEqualStrings("E_INTERNAL_NAME", raw.diagnostics.items[0].code);
    var spoof = try language.Compilation.init(t.allocator, "@stdlib/math.my", "def main() -> int:\n    return int(__float_cos(0.0))\n");
    defer spoof.deinit();
    try t.expectError(error.SourceError, spoof.check());
    try t.expectEqualStrings("E_INTERNAL_NAME", spoof.diagnostics.items[0].code);
}

// spec-case: FLOAT-INTEGER-CAST-1
test "checked float conversion truncates before exact half-open range checks" {
    try t.expectEqual(@as(i128, -128), try floats.toInteger(.i8, @bitCast(@as(f64, -128.5))));
    try t.expectEqual(@as(i128, 0), try floats.toInteger(.u8, @bitCast(@as(f64, -0.75))));
    try t.expectEqual(@as(i128, -9223372036854775808), try floats.toInteger(.i64, @bitCast(@as(f64, -9223372036854775808.0))));
    try t.expectEqual(@as(i128, 18446744073709549568), try floats.toInteger(.u64, @bitCast(@as(f64, 18446744073709549568.0))));
    try t.expectError(error.FloatConversion, floats.toInteger(.i64, @bitCast(@as(f64, 9223372036854775808.0))));
    try t.expectError(error.FloatConversion, floats.toInteger(.u64, @bitCast(@as(f64, 18446744073709551616.0))));
}

/// Add the program converting `value` to `target`, which must trap at the conversion.
fn conversionTrap(programs: *native.Batch, target: []const u8, value: []const u8) !void {
    const text = try std.fmt.allocPrint(t.allocator, "def main() -> int:\n    value = {s}\n    _ = {s}(value)\n    return 0\n", .{ value, target });
    defer t.allocator.free(text);
    try programs.add("float-cast.my", text, .{});
}

/// Run every conversion program as one batch: each traps with `R_FLOAT_CONVERSION`
/// on its third line.
fn expectConversionTraps(programs: *native.Batch) !void {
    for (try programs.run()) |result| {
        try t.expect(result.trapped());
        try t.expectEqualStrings("R_FLOAT_CONVERSION", result.trap.code);
        try t.expectEqual(@as(u64, 3), result.trap.line);
    }
}

// spec-case: FLOAT-INTEGER-CAST-1
test "every fixed-width float conversion traps for NaN infinities and range violations" {
    var programs: native.Batch = .init(t.allocator);
    defer programs.deinit();
    for ([_]struct { target: []const u8, lower: []const u8, upper: []const u8 }{
        .{ .target = "i8", .lower = "-129.0", .upper = "128.0" },
        .{ .target = "i16", .lower = "-32769.0", .upper = "32768.0" },
        .{ .target = "i32", .lower = "-2147483649.0", .upper = "2147483648.0" },
        .{ .target = "i64", .lower = "-9223372036854777856.0", .upper = "9223372036854775808.0" },
        .{ .target = "u8", .lower = "-1.0", .upper = "256.0" },
        .{ .target = "u16", .lower = "-1.0", .upper = "65536.0" },
        .{ .target = "u32", .lower = "-1.0", .upper = "4294967296.0" },
        .{ .target = "u64", .lower = "-1.0", .upper = "18446744073709551616.0" },
        .{ .target = "int", .lower = "-9223372036854777856.0", .upper = "9223372036854775808.0" },
    }) |row| {
        try conversionTrap(&programs, row.target, "0.0 / 0.0");
        try conversionTrap(&programs, row.target, "1.0 / 0.0");
        try conversionTrap(&programs, row.target, "-1.0 / 0.0");
        try conversionTrap(&programs, row.target, row.lower);
        try conversionTrap(&programs, row.target, row.upper);
    }
    try expectConversionTraps(&programs);
}
