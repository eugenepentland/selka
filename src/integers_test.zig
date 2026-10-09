//! Fixed-width integer semantics: suffixed literals, width-preserving arithmetic,
//! checked casts and the diagnostics that reject implicit conversions.
const std = @import("std");
const testing = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const Type = @import("typed.zig").Type;

/// `main` returning `expression` returns `expected`.
fn evaluate(programs: *native.Cases, expression: []const u8, expected: i64) !void {
    const text = try std.fmt.allocPrint(testing.allocator, "func main() -> i64:\n    return {s}\n", .{expression});
    defer testing.allocator.free(text);
    try programs.returns("integer.selka", text, expected);
}

/// Evaluating `expression` on `main`'s second line traps with `code`.
fn trapped(programs: *native.Cases, expression: []const u8, code: []const u8) !void {
    const text = try std.fmt.allocPrint(testing.allocator, "func main() -> i64:\n    _ = {s}\n    return 0\n", .{expression});
    defer testing.allocator.free(text);
    try programs.traps("integer.selka", text, code, 2);
}

test "checked signed and unsigned operations retain each declared width" {
    var programs: native.Cases = .init(testing.allocator);
    defer programs.deinit();
    try evaluate(&programs, "i64(100i8 + 20i8)", 120);
    try evaluate(&programs, "i64(divtrunc(-7i16, 3i16))", -2);
    try evaluate(&programs, "i64(remtrunc(-7i32, 3i32))", -1);
    try evaluate(&programs, "i64(remtrunc(-128i8, -1i8))", 0);
    try evaluate(&programs, "i64(divtrunc(18446744073709551615u64, 3u64))", 6148914691236517205);
    try evaluate(&programs, "i64(65535u16 - 1u16)", 65534);
    try evaluate(&programs, "i64(remtrunc(4294967295u32, 10u32))", 5);
    try evaluate(&programs, "i64(-0u8)", 0);
    for ([_][]const u8{ "127i8 + 1i8", "-128i8 - 1i8", "--128i8", "divtrunc(-128i8, -1i8)", "0u8 - 1u8", "255u8 + 1u8", "-1u8", "18446744073709551615u64 * 18446744073709551615u64" }) |expr| try trapped(&programs, expr, "R_OVERFLOW");
    try trapped(&programs, "divtrunc(1u32, 0u32)", "R_DIVISION_BY_ZERO");
    try trapped(&programs, "remtrunc(1i16, 0i16)", "R_DIVISION_BY_ZERO");
    try programs.check();
}

test "integer casts check narrowing signedness and retain operand traps" {
    var programs: native.Cases = .init(testing.allocator);
    defer programs.deinit();
    try evaluate(&programs, "i64(u8(255))", 255);
    try evaluate(&programs, "i64(i8(-128))", -128);
    try evaluate(&programs, "i64(u64(9223372036854775807))", 9223372036854775807);
    for ([_][]const u8{ "u8(-1)", "i8(128)", "u16(65536)", "i64(18446744073709551615u64)" }) |expr| try trapped(&programs, expr, "R_OVERFLOW");
    try trapped(&programs, "u8(divtrunc(1, 0))", "R_DIVISION_BY_ZERO");
    try trapped(&programs, "i64(127i8 + 1i8)", "R_OVERFLOW");
    try programs.check();
}

test "integer widths remain distinct in functions records compound assignment and conversions" {
    const source =
        \\record Small:
        \\    n: u8
        \\
        \\
        \\record Wide:
        \\    n: u64
        \\
        \\
        \\conversion func widen(x: Small) -> Wide:
        \\    return Wide(n=u64(x.n))
        \\
        \\
        \\func bump(n: u8) -> u8:
        \\    mut result = n
        \\    result += 1u8
        \\    result -= 2u8
        \\    return result
        \\
        \\
        \\func main() -> i64:
        \\    return i64(widen(Small(n=bump(9u8))).n)
    ;
    var compilation = try language.Compilation.init(testing.allocator, "widths.selka", source);
    defer compilation.deinit();
    try testing.expectEqual(@as(i64, 8), (try native.run(&compilation)).value);
    try compilation.check();
    var discovery = try language.duplicates.discover(testing.allocator, compilation.program.?, .{});
    defer discovery.deinit();
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "widths.selka",
        \\record Small:
        \\    n: u8
        \\
        \\
        \\func f(n: u8) -> u8:
        \\    return n + 1u8
        \\
        \\
        \\func main() -> i64:
        \\    mut n = Small(n=f(254u8))
        \\    return i64(u64(n.n) * 2u64)
    );
    defer compilation.deinit();
    try compilation.check();
    var discovery = try language.duplicates.discover(allocator, compilation.program.?, .{});
    defer discovery.deinit();
}

test "integer widths casts and record values release storage under allocation failure" {
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
}

test "integer widths and casts remain distinct in duplicate discovery" {
    var compilation = try language.Compilation.init(testing.allocator, "duplicates.selka",
        \\func a(n: u8) -> u8:
        \\    return n + 1u8
        \\
        \\
        \\func b(n: i8) -> i8:
        \\    return n + 1i8
        \\
        \\
        \\func c(n: u8) -> u16:
        \\    return u16(n)
        \\
        \\
        \\func d(n: u8) -> u32:
        \\    return u32(n)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    );
    defer compilation.deinit();
    try compilation.check();
    var analysis = try language.duplicates.discover(testing.allocator, compilation.program.?, .{ .min_nodes = 1 });
    defer analysis.deinit();
    try testing.expectEqual(@as(usize, 0), analysis.groups.len);
}

test "every signed and unsigned byte addition and multiplication has checked bounds" {
    const integers = @import("integers.zig");
    for ([_]Type{ .i8, .u8 }) |ty| {
        const low: i16 = if (ty == .i8) -128 else 0;
        const high: i16 = if (ty == .i8) 127 else 255;
        var left: i16 = low;
        while (left <= high) : (left += 1) {
            var right: i16 = low;
            while (right <= high) : (right += 1) {
                for ([_]@import("typed.zig").BinaryOp{ .add, .mul }) |op| {
                    const expected: i32 = if (op == .add) @as(i32, left) + right else @as(i32, left) * right;
                    if (expected < low or expected > high) {
                        try testing.expectError(error.Overflow, integers.binary(ty, op, left, right));
                    } else {
                        const value = try integers.binary(ty, op, left, right);
                        try testing.expectEqual(@as(i128, expected), try value.asInteger());
                    }
                }
            }
        }
    }
}

// spec: CORE-4
test "all integer widths accept their limits and reject one-past literals" {
    var programs: native.Cases = .init(testing.allocator);
    defer programs.deinit();
    const widths = [_]Type{ .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64 };
    for (widths) |ty| {
        const expression = try std.fmt.allocPrint(testing.allocator, "{d}{s} == {d}{s}", .{ ty.max(), @tagName(ty), ty.max(), @tagName(ty) });
        defer testing.allocator.free(expression);
        const text = try std.fmt.allocPrint(testing.allocator, "func main() -> i64:\n    if {s}:\n        return 1\n    return 0\n", .{expression});
        defer testing.allocator.free(text);
        try programs.returns("limits.selka", text, 1);
        const minimum = try std.fmt.allocPrint(testing.allocator, "i64({d}{s})", .{ ty.min(), @tagName(ty) });
        defer testing.allocator.free(minimum);
        try evaluate(&programs, minimum, @intCast(ty.min()));
        const bad = try std.fmt.allocPrint(testing.allocator, "func main() -> i64:\n    _ = {d}{s}\n    return 0\n", .{ ty.max() + 1, @tagName(ty) });
        defer testing.allocator.free(bad);
        var invalid = try language.Compilation.init(testing.allocator, "range.selka", bad);
        defer invalid.deinit();
        try testing.expectError(error.SourceError, invalid.check());
        try testing.expectEqualStrings("E_INTEGER_RANGE", invalid.diagnostics.items[0].code);
    }
    try programs.check();
}

test "no implicit width or boolean conversions and unknown suffixes are rejected" {
    const cases = [_]struct { body: []const u8, code: []const u8 }{
        .{ .body = "const source = 1\n    const n: i8 = source\n    return 0", .code = "E_TYPE" },
        .{ .body = "_ = 1u8 + 1u16\n    return 0", .code = "E_TYPE" },
        .{ .body = "_ = u8(True)\n    return 0", .code = "E_TYPE" },
        .{ .body = "_ = bool(1)\n    return 0", .code = "E_EXPRESSION" },
        .{ .body = "_ = 1i7\n    return 0", .code = "E_INTEGER_SUFFIX" },
        .{ .body = "_ = 1bool\n    return 0", .code = "E_INTEGER_SUFFIX" },
        .{ .body = "_ = -(128i8 + 0i8)\n    return 0", .code = "E_INTEGER_RANGE" },
    };
    for (cases) |case| {
        const source = try std.fmt.allocPrint(testing.allocator,
            \\func main() -> i64:
            \\    {s}
        , .{case.body});
        defer testing.allocator.free(source);
        var compilation = try language.Compilation.init(testing.allocator, "invalid.selka", source);
        defer compilation.deinit();
        try testing.expectError(error.SourceError, compilation.check());
        try testing.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}

test "inlined multiplication keeps every width and traps past its bounds" {
    var programs: native.Cases = .init(testing.allocator);
    defer programs.deinit();
    try evaluate(&programs, "i64(100i8 * 1i8)", 100);
    try evaluate(&programs, "i64(-64i8 * 2i8)", -128);
    try evaluate(&programs, "i64(15u8 * 17u8)", 255);
    try evaluate(&programs, "i64(46340i32 * 46340i32)", 2147395600);
    try evaluate(&programs, "i64(65535u32 * 65535u32)", 4294836225);
    try evaluate(&programs, "3037000499 * 3037000499", 9223372030926249001);
    try evaluate(&programs, "-9223372036854775808 * 1", -9223372036854775808);
    try evaluate(&programs, "i64(divtrunc(4294967295u64 * 4294967295u64, 4294967295u64))", 4294967295);
    const cases = [_][]const u8{
        "127i8 * 2i8",
        "-128i8 * -1i8",
        "16u8 * 16u8",
        "2147483647i32 * 2i32",
        "-2147483648i32 * -1i32",
        "65536u32 * 65536u32",
        "9223372036854775807 * 2",
        "-9223372036854775808 * -1",
        "3037000500 * 3037000500",
        "18446744073709551615u64 * 2u64",
        "18446744073709551615u64 * 18446744073709551615u64",
    };
    for (cases) |expr| try trapped(&programs, expr, "R_OVERFLOW");
    try programs.check();
}

test "inlined division and remainder trap zero and narrow overflow only" {
    var programs: native.Cases = .init(testing.allocator);
    defer programs.deinit();
    try evaluate(&programs, "i64(divtrunc(-7i16, 3i16))", -2);
    try evaluate(&programs, "i64(remtrunc(-7i32, 3i32))", -1);
    try evaluate(&programs, "(-7) // 3", -3);
    try evaluate(&programs, "(-7) % 3", 2);
    try evaluate(&programs, "7 // (-3)", -3);
    try evaluate(&programs, "7 % (-3)", -2);
    try evaluate(&programs, "(-7) // (-3)", 2);
    try evaluate(&programs, "(-7) % (-3)", -1);
    try evaluate(&programs, "i64(17u8 // 5u8)", 3);
    try evaluate(&programs, "i64(17u8 % 5u8)", 2);
    try evaluate(&programs, "i64(-128i8 % -1i8)", 0);
    try evaluate(&programs, "i64(-32768i16 % -1i16)", 0);
    try evaluate(&programs, "i64(-2147483648i32 % -1i32)", 0);
    try evaluate(&programs, "-9223372036854775808 % -1", 0);
    try evaluate(&programs, "i64(remtrunc(-9223372036854775808, -1))", 0);
    try evaluate(&programs, "i64(18446744073709551615u64 // 2u64)", 9223372036854775807);
    const cases = [_]struct { expression: []const u8, code: []const u8 }{
        .{ .expression = "-128i8 // -1i8", .code = "R_OVERFLOW" },
        .{ .expression = "-32768i16 // -1i16", .code = "R_OVERFLOW" },
        .{ .expression = "-2147483648i32 // -1i32", .code = "R_OVERFLOW" },
        .{ .expression = "-9223372036854775808 // -1", .code = "R_OVERFLOW" },
        .{ .expression = "divtrunc(-9223372036854775808, -1)", .code = "R_OVERFLOW" },
        .{ .expression = "10 // 0", .code = "R_DIVISION_BY_ZERO" },
        .{ .expression = "10 % 0", .code = "R_DIVISION_BY_ZERO" },
        .{ .expression = "divtrunc(10, 0)", .code = "R_DIVISION_BY_ZERO" },
        .{ .expression = "remtrunc(10, 0)", .code = "R_DIVISION_BY_ZERO" },
        .{ .expression = "1u8 // 0u8", .code = "R_DIVISION_BY_ZERO" },
        .{ .expression = "1u16 % 0u16", .code = "R_DIVISION_BY_ZERO" },
        .{ .expression = "1i32 // 0i32", .code = "R_DIVISION_BY_ZERO" },
        .{ .expression = "1u64 % 0u64", .code = "R_DIVISION_BY_ZERO" },
    };
    for (cases) |case| try trapped(&programs, case.expression, case.code);
    try programs.check();
}

test "inlined shifts wrap within the width and reject out of range counts" {
    var programs: native.Cases = .init(testing.allocator);
    defer programs.deinit();
    try evaluate(&programs, "i64(shift_left(1i8, 7i8))", -128);
    try evaluate(&programs, "i64(shift_left(1u8, 7u8))", 128);
    try evaluate(&programs, "i64(shift_left(1i16, 15i16))", -32768);
    try evaluate(&programs, "i64(shift_left(1i32, 31i32))", -2147483648);
    try evaluate(&programs, "shift_left(1, 63)", -9223372036854775808);
    try evaluate(&programs, "i64(shift_right(-128i8, 7i8))", -1);
    try evaluate(&programs, "i64(shift_right(-8i8, 2i8))", -2);
    try evaluate(&programs, "i64(shift_right(255u8, 4u8))", 15);
    try evaluate(&programs, "shift_right(-1, 63)", -1);
    try evaluate(&programs, "i64(divtrunc(shift_left(1u64, 63u64), 2u64))", 4611686018427387904);
    const cases = [_][]const u8{
        "shift_left(1i8, 8i8)",
        "shift_right(1i8, 8i8)",
        "shift_left(1u8, 8u8)",
        "shift_left(1i16, 16i16)",
        "shift_left(1u32, 32u32)",
        "shift_left(1, 64)",
        "shift_left(1u64, 64u64)",
        "shift_right(1i8, -1i8)",
    };
    for (cases) |expr| try trapped(&programs, expr, "R_INVALID_SHIFT");
    try programs.check();
}

test "inlined negation traps only at each signed width's minimum" {
    var programs: native.Cases = .init(testing.allocator);
    defer programs.deinit();
    try evaluate(&programs, "i64(-(-127i8))", 127);
    try evaluate(&programs, "i64(-(-32767i16))", 32767);
    try evaluate(&programs, "i64(-(-2147483647i32))", 2147483647);
    try evaluate(&programs, "i64(-0u8)", 0);
    const cases = [_][]const u8{
        "-(-128i8)",
        "-(-32768i16)",
        "-(-2147483648i32)",
        "-(-9223372036854775807 - 1)",
        "-1u8",
        "-1u16",
        "-1u32",
        "-1u64",
    };
    for (cases) |expr| try trapped(&programs, expr, "R_OVERFLOW");
    try programs.check();
}
