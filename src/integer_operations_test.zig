//! Named integer operations retain width semantics in constants and guest execution.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const typed = @import("typed.zig");
const integers = @import("integers.zig");
fn widths() !void {
    const types = [_]typed.Type{ .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64 };
    for (types) |ty| try boundaries(ty);
}
fn boundaries(ty: typed.Type) !void {
    try t.expectEqual(typed.Value.number(ty, ty.min()), try integers.binary(ty, .wrapping_add, ty.max(), 1));
    try t.expectEqual(typed.Value.number(ty, ty.max()), try integers.binary(ty, .wrapping_sub, ty.min(), 1));
    try t.expectEqual(typed.Value.number(ty, ty.max()), try integers.binary(ty, .saturating_add, ty.max(), 1));
    try t.expectEqual(typed.Value.number(ty, ty.min()), try integers.binary(ty, .saturating_sub, ty.min(), 1));
    try t.expectEqual(typed.Value.number(ty, ty.max()), try integers.binary(ty, .saturating_mul, ty.max(), ty.max()));
    try t.expectEqual(typed.Value.number(ty, 0), try integers.binary(ty, .bit_xor, ty.max(), ty.max()));
    try t.expectError(error.InvalidShift, integers.binary(ty, .shift_left, 1, ty.integer().?.bits));
    if (ty.integer().?.signed) try t.expectError(error.InvalidShift, integers.binary(ty, .shift_right, 1, -1));
}
// spec: NAMED-INTEGER-BITWISE-1
test "a complement answers in the operand's own width" {
    try t.expectEqual(typed.Value.number(.u8, 255), try integers.bitNot(.u8, 0));
    try t.expectEqual(typed.Value.number(.u8, 250), try integers.bitNot(.u8, 5));
    try t.expectEqual(typed.Value.number(.i8, -1), try integers.bitNot(.i8, 0));
    try t.expectEqual(typed.Value.number(.i8, 127), try integers.bitNot(.i8, -128));
    try t.expectEqual(typed.Value.number(.i8, -128), try integers.bitNot(.i8, 127));
    try t.expectEqual(typed.Value.number(.i64, -8), try integers.bitNot(.i64, 7));
    try t.expectEqual(typed.Value.number(.u64, 18446744073709551615), try integers.bitNot(.u64, 0));
    try t.expectError(error.InternalError, integers.bitNot(.bool, 0));
}

// spec: NAMED-INTEGER-BITWISE-1
test "bit_not reads its width at run time and survives a reformat" {
    var compilation = try language.Compilation.init(t.allocator, "bitnot.selka",
        \\func main() -> i64:
        \\    const wide = bit_not(0u8)
        \\    const signed = bit_not(7)
        \\    const small = bit_not(127i8)
        \\    return i64(wide) + signed + i64(small)
    );
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 119), (try native.run(&compilation)).value);
    const formatted = try compilation.format(t.allocator);
    defer t.allocator.free(formatted);
    var again = try language.Compilation.init(t.allocator, "bitnot_formatted.selka", formatted);
    defer again.deinit();
    try t.expectEqual(@as(i64, 119), (try native.run(&again)).value);
}

// spec: INTEGER-EXTENDED-1
test "named integer width boundaries reject InvalidShift and DivisionByZero" {
    try widths();
    try t.expectError(error.DivisionByZero, integers.binary(.i64, .div, 1, 0));
}
fn guest(allocator: std.mem.Allocator) !void {
    const source =
        \\const MASK: u8 = bit_or(128u8, 1u8)
        \\
        \\
        \\func add[T: integer](a: T, b: T) -> T:
        \\    return wrapping_add(a, b)
        \\
        \\
        \\func main() -> i64:
        \\    mut a = add[u8](MASK, 127u8)
        \\    mut b = shift_right(-8i8, 2i8)
        \\    mut c = wrapping_mul(255u8, 255u8)
        \\    return i64(a) + i64(b) + i64(c) + i64(bit_and(7u8, 3u8))
    ;
    var compilation = try language.Compilation.init(allocator, "numbers.selka", source);
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 2), (try native.run(&compilation)).value);
    const formatted = try compilation.format(allocator);
    defer allocator.free(formatted);
    var again = try language.Compilation.init(allocator, "formatted.selka", formatted);
    defer again.deinit();
    try t.expectEqual(@as(i64, 2), (try native.run(&again)).value);
}
test "named integer operations share constant generic and runtime semantics across a reformat" {
    try guest(t.allocator);
}
test "invalid runtime shifts are located and constant shifts reject before execution" {
    var runtime = try language.Compilation.init(t.allocator, "shift.selka",
        \\func main() -> i64:
        \\    return shift_left(1, 64)
    );
    defer runtime.deinit();
    const result = try native.run(&runtime);
    try t.expectEqualStrings("R_INVALID_SHIFT", result.trap.code);
    var constant = try language.Compilation.init(t.allocator, "shift.selka",
        \\const X: i64 = shift_right(1, -1)
        \\
        \\
        \\func main() -> i64:
        \\    return X
    );
    defer constant.deinit();
    try t.expectError(error.SourceError, constant.check());
    try t.expectEqualStrings("E_CONSTANT_ARITHMETIC", constant.diagnostics.items[0].code);
}
