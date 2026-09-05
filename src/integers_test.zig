const std = @import("std");
const testing = std.testing;
const language = @import("compiler.zig");
const Type = @import("typed.zig").Type;

fn evaluate(expression: []const u8, expected: i64) !void {
    const text = try std.fmt.allocPrint(testing.allocator, "fn main() -> i64 {{ return {s}; }}", .{expression});
    defer testing.allocator.free(text);
    var compilation = try language.Compilation.init(testing.allocator, "integer.my", text);
    defer compilation.deinit();
    try testing.expectEqual(expected, (try compilation.execute(testing.allocator)).value);
}
fn trapped(expression: []const u8, code: []const u8) !void {
    const text = try std.fmt.allocPrint(testing.allocator, "fn main() -> i64 {{ discard {s}; return 0; }}", .{expression});
    defer testing.allocator.free(text);
    var compilation = try language.Compilation.init(testing.allocator, "integer.my", text);
    defer compilation.deinit();
    try compilation.check();
    const outcome = try compilation.execute(testing.allocator);
    try testing.expectEqualStrings(code, outcome.trap.code);
    try testing.expect(outcome.trap.span.start < text.len);
}

test "all integer widths accept their limits and reject one-past literals" {
    const widths = [_]Type{ .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64 };
    for (widths) |ty| {
        const expression = try std.fmt.allocPrint(testing.allocator, "{d}{s} == {d}{s}", .{ ty.max(), @tagName(ty), ty.max(), @tagName(ty) });
        defer testing.allocator.free(expression);
        const text = try std.fmt.allocPrint(testing.allocator, "fn main() -> i64 {{ if {s} {{ return 1; }} return 0; }}", .{expression});
        defer testing.allocator.free(text);
        var compilation = try language.Compilation.init(testing.allocator, "limits.my", text);
        defer compilation.deinit();
        try testing.expectEqual(@as(i64, 1), (try compilation.execute(testing.allocator)).value);
        const minimum = try std.fmt.allocPrint(testing.allocator, "cast<i64>({d}{s})", .{ ty.min(), @tagName(ty) });
        defer testing.allocator.free(minimum);
        try evaluate(minimum, @intCast(ty.min()));
        const bad = try std.fmt.allocPrint(testing.allocator, "fn main() -> i64 {{ discard {d}{s}; return 0; }}", .{ ty.max() + 1, @tagName(ty) });
        defer testing.allocator.free(bad);
        var invalid = try language.Compilation.init(testing.allocator, "range.my", bad);
        defer invalid.deinit();
        try testing.expectError(error.SourceError, invalid.check());
        try testing.expectEqualStrings("E_INTEGER_RANGE", invalid.diagnostics.items[0].code);
    }
}

test "checked signed and unsigned operations retain each declared width" {
    try evaluate("cast<i64>(100i8 + 20i8)", 120);
    try evaluate("cast<i64>(-7i16 / 3i16)", -2);
    try evaluate("cast<i64>(-7i32 % 3i32)", -1);
    try evaluate("cast<i64>(-128i8 % -1i8)", 0);
    try evaluate("cast<i64>(18446744073709551615u64 / 3u64)", 6148914691236517205);
    try evaluate("cast<i64>(65535u16 - 1u16)", 65534);
    try evaluate("cast<i64>(4294967295u32 % 10u32)", 5);
    try evaluate("cast<i64>(-0u8)", 0);
    for ([_][]const u8{ "127i8 + 1i8", "-128i8 - 1i8", "--128i8", "-128i8 / -1i8", "0u8 - 1u8", "255u8 + 1u8", "-1u8", "18446744073709551615u64 * 18446744073709551615u64" }) |expr| try trapped(expr, "R_OVERFLOW");
    try trapped("1u32 / 0u32", "R_DIVISION_BY_ZERO");
    try trapped("1i16 % 0i16", "R_DIVISION_BY_ZERO");
}

test "integer casts check narrowing signedness and retain operand traps" {
    try evaluate("cast<i64>(cast<u8>(255))", 255);
    try evaluate("cast<i64>(cast<i8>(-128))", -128);
    try evaluate("cast<i64>(cast<u64>(9223372036854775807))", 9223372036854775807);
    for ([_][]const u8{ "cast<u8>(-1)", "cast<i8>(128)", "cast<u16>(65536)", "cast<i64>(18446744073709551615u64)" }) |expr| try trapped(expr, "R_OVERFLOW");
    try trapped("cast<u8>(1 / 0)", "R_DIVISION_BY_ZERO");
    try trapped("cast<i64>(127i8 + 1i8)", "R_OVERFLOW");
}

test "integer widths remain distinct in functions records compound assignment and conversions" {
    const source = "struct Small { n: u8 } struct Wide { n: u64 } conversion fn widen(x: Small) -> Wide { return new Wide { n: cast<u64>(x.n) }; } fn bump(n: u8) -> u8 { let mut result = n; result += 1u8; result -= 2u8; return result; } fn main() -> i64 { return cast<i64>(widen(new Small { n: bump(9u8) }).n); }";
    var compilation = try language.Compilation.init(testing.allocator, "widths.my", source);
    defer compilation.deinit();
    try testing.expectEqual(@as(i64, 8), (try compilation.execute(testing.allocator)).value);
    const dump = try compilation.dump(testing.allocator);
    defer testing.allocator.free(dump);
    try testing.expect(std.mem.indexOf(u8, dump, "CAST_INT u64") != null);
    var discovery = try language.duplicates.discover(testing.allocator, compilation.program.?, .{});
    defer discovery.deinit();
}

test "no implicit width or boolean conversions and unknown suffixes are rejected" {
    const cases = [_]struct { body: []const u8, code: []const u8 }{
        .{ .body = "let n: i8 = 1; return 0;", .code = "E_TYPE" },
        .{ .body = "discard 1u8 + 1u16; return 0;", .code = "E_TYPE" },
        .{ .body = "discard cast<u8>(true); return 0;", .code = "E_TYPE" },
        .{ .body = "discard cast<bool>(1); return 0;", .code = "E_TYPE" },
        .{ .body = "discard 1i7; return 0;", .code = "E_INTEGER_SUFFIX" },
        .{ .body = "discard 1bool; return 0;", .code = "E_INTEGER_SUFFIX" },
        .{ .body = "discard -(128i8 + 0i8); return 0;", .code = "E_INTEGER_RANGE" },
    };
    for (cases) |case| {
        const source = try std.fmt.allocPrint(testing.allocator, "fn main() -> i64 {{ {s} }}", .{case.body});
        defer testing.allocator.free(source);
        var compilation = try language.Compilation.init(testing.allocator, "invalid.my", source);
        defer compilation.deinit();
        try testing.expectError(error.SourceError, compilation.check());
        try testing.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "widths.my", "struct Small { n: u8 } fn f(n: u8) -> u8 { return n + 1u8; } fn main() -> i64 { let n = new Small { n: f(254u8) }; return cast<i64>(cast<u64>(n.n) * 2u64); }");
    defer compilation.deinit();
    try testing.expectEqual(@as(i64, 510), (try compilation.execute(allocator)).value);
    const dump = try compilation.dump(allocator);
    defer allocator.free(dump);
    var discovery = try language.duplicates.discover(allocator, compilation.program.?, .{});
    defer discovery.deinit();
}

test "integer widths casts and record values release storage under allocation failure" {
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
}

test "integer widths and casts remain distinct in duplicate discovery" {
    var compilation = try language.Compilation.init(testing.allocator, "duplicates.my", "fn a(n: u8) -> u8 { return n + 1u8; } fn b(n: i8) -> i8 { return n + 1i8; } fn c(n: u8) -> u16 { return cast<u16>(n); } fn d(n: u8) -> u32 { return cast<u32>(n); } fn main() -> i64 { return 0; }");
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
