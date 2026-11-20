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
    \\func main() -> int:
    \\    mut root = int(sqrt(1764.0))
    \\    return root
;
fn intrinsicScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "float.selka", intrinsic_source);
    defer c.deinit();
    try t.expectEqual(@as(i64, 42), (try native.run(&c)).value);
}
// spec-case: FLOAT-DOMAIN-1
test "float intrinsics evaluate at runtime and reject raw operands" {
    var bad = try language.Compilation.init(t.allocator, "float.selka",
        \\func main() -> int:
        \\    return int(sqrt(1))
    );
    defer bad.deinit();
    try t.expectError(error.SourceError, bad.check());
    try t.expectEqualStrings("E_TYPE", bad.diagnostics.items[0].code);
    try intrinsicScenario(t.allocator);
}

// spec: FLOAT-INTRINSIC-FLOAT-1
test "a float-in float-out intrinsic takes a float operand and answers a float" {
    var c = try language.Compilation.init(t.allocator, "float.selka",
        \\func main() -> int:
        \\    mut value = 1764.0
        \\    mut root = sqrt(value)
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
    var raw = try language.Compilation.init(t.allocator, "float.selka",
        \\func main() -> int:
        \\    return int(f64_to_u64(f64_sqrt(1764.0)))
    );
    defer raw.deinit();
    try t.expectError(error.SourceError, raw.check());
    try t.expectEqualStrings("E_REMOVED_SPELLING", raw.diagnostics.items[0].code);
}

// spec: INTERNAL-NAME-1
test "the reserved intrinsic spelling is rejected in ordinary source" {
    var c = try language.Compilation.init(t.allocator, "float.selka",
        \\func main() -> int:
        \\    return int(__float_sqrt(1764.0))
    );
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_INTERNAL_NAME", c.diagnostics.items[0].code);
    // A source path that merely looks like the embedded library does not grant
    // the intrinsic: the bytes must be the compiler-owned module.
    var spoof = try language.Compilation.init(t.allocator, "@stdlib/math.selka",
        \\func main() -> int:
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
    var raw = try language.Compilation.init(t.allocator, "trig.selka", "func main() -> int:\n    return int(__float_sin(0.0))\n");
    defer raw.deinit();
    try t.expectError(error.SourceError, raw.check());
    try t.expectEqualStrings("E_INTERNAL_NAME", raw.diagnostics.items[0].code);
    var spoof = try language.Compilation.init(t.allocator, "@stdlib/math.selka", "func main() -> int:\n    return int(__float_cos(0.0))\n");
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
    const text = try std.fmt.allocPrint(t.allocator, "func main() -> int:\n    const value = {s}\n    _ = {s}(value)\n    return 0\n", .{ value, target });
    defer t.allocator.free(text);
    try programs.add("float-cast.selka", text, .{});
}

/// Run one target's five conversion programs; each traps with
/// `R_FLOAT_CONVERSION` on its third line.
fn expectConversionTraps(programs: *native.Batch) !void {
    const results = try programs.run();
    try t.expectEqual(@as(usize, 5), results.len);
    for (results) |result| {
        try t.expect(result.trapped());
        try t.expectEqualStrings("R_FLOAT_CONVERSION", result.trap.code);
        try t.expectEqual(@as(u64, 3), result.trap.line);
    }
}

/// Keep all five invalid inputs for one target together while allowing the
/// Guardian shard plan to schedule different conversion targets independently.
fn expectTargetConversionTraps(target: []const u8, lower: []const u8, upper: []const u8) !void {
    var programs: native.Batch = .init(t.allocator);
    defer programs.deinit();
    try conversionTrap(&programs, target, "0.0 / 0.0");
    try conversionTrap(&programs, target, "1.0 / 0.0");
    try conversionTrap(&programs, target, "-1.0 / 0.0");
    try conversionTrap(&programs, target, lower);
    try conversionTrap(&programs, target, upper);
    try expectConversionTraps(&programs);
}

// spec-case: FLOAT-INTEGER-CAST-1
test "i8 float conversion traps for NaN infinities and range violations" {
    try expectTargetConversionTraps("i8", "-129.0", "128.0");
}

// spec-case: FLOAT-INTEGER-CAST-1
test "i16 float conversion traps for NaN infinities and range violations" {
    try expectTargetConversionTraps("i16", "-32769.0", "32768.0");
}

// spec-case: FLOAT-INTEGER-CAST-1
test "i32 float conversion traps for NaN infinities and range violations" {
    try expectTargetConversionTraps("i32", "-2147483649.0", "2147483648.0");
}

// spec-case: FLOAT-INTEGER-CAST-1
test "i64 float conversion traps for NaN infinities and range violations" {
    try expectTargetConversionTraps("i64", "-9223372036854777856.0", "9223372036854775808.0");
}

// spec-case: FLOAT-INTEGER-CAST-1
test "u8 float conversion traps for NaN infinities and range violations" {
    try expectTargetConversionTraps("u8", "-1.0", "256.0");
}

// spec-case: FLOAT-INTEGER-CAST-1
test "u16 float conversion traps for NaN infinities and range violations" {
    try expectTargetConversionTraps("u16", "-1.0", "65536.0");
}

// spec-case: FLOAT-INTEGER-CAST-1
test "u32 float conversion traps for NaN infinities and range violations" {
    try expectTargetConversionTraps("u32", "-1.0", "4294967296.0");
}

// spec-case: FLOAT-INTEGER-CAST-1
test "u64 float conversion traps for NaN infinities and range violations" {
    try expectTargetConversionTraps("u64", "-1.0", "18446744073709551616.0");
}

// spec-case: FLOAT-INTEGER-CAST-1
test "int float conversion traps for NaN infinities and range violations" {
    try expectTargetConversionTraps("int", "-9223372036854777856.0", "9223372036854775808.0");
}

test "binary32 operations round to nearest, keep subnormals and canonicalize NaN" {
    const floats32 = @import("floats.zig");
    const one_tenth: u64 = @as(u32, @bitCast(@as(f32, 0.1)));
    const two_tenths: u64 = @as(u32, @bitCast(@as(f32, 0.2)));
    const sum = try floats32.binary32(.f32_add, one_tenth, two_tenths);
    try t.expectEqual(@as(u64, @as(u32, @bitCast(@as(f32, 0.1) + @as(f32, 0.2)))), @as(u64, @intCast(sum.integer.value)));
    const overflow = try floats32.binary32(.f32_mul, @as(u32, @bitCast(@as(f32, 3.0e38))), @as(u32, @bitCast(@as(f32, 10.0))));
    try t.expect(std.math.isInf(@as(f32, @bitCast(@as(u32, @intCast(overflow.integer.value))))));
    const subnormal = try floats32.binary32(.f32_add, 1, 0);
    try t.expectEqual(@as(u64, 1), @as(u64, @intCast(subnormal.integer.value)));
    const nan = try floats32.binary32(.f32_div, 0, 0);
    try t.expectEqual(floats32.canonical_nan32, @as(u32, @intCast(nan.integer.value)));
    const less = try floats32.binary32(.f32_lt, @as(u32, @bitCast(@as(f32, 1.0))), @as(u64, @intCast(nan.integer.value)));
    try t.expect(!less.bool);
}

test "f32 conversions widen exactly, round once and check integer ranges" {
    const floats32 = @import("floats.zig");
    const widened = try floats32.unary32(.f64_from_f32, @as(u32, @bitCast(@as(f32, 0.1))));
    try t.expectEqual(@as(u64, @bitCast(@as(f64, @as(f32, 0.1)))), widened);
    const rounded = try floats32.unary32(.f32_from_f64, @bitCast(@as(f64, 0.1)));
    try t.expectEqual(@as(u64, @as(u32, @bitCast(@as(f32, 0.1)))), rounded);
    try t.expectEqual(@as(i128, 7), try floats32.toInteger(.i64, @bitCast(@as(f64, @as(f32, 7.9)))));
    try t.expectError(error.FloatConversion, floats32.unary32(.f32_to_i8, @as(u32, @bitCast(@as(f32, 200.0)))));
}
