//! Named integer operations retain width semantics in constants and guest execution.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
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
        \\def add[T: integer](a: T, b: T) -> T:
        \\    return wrapping_add(a, b)
        \\
        \\
        \\def main() -> i64:
        \\    a = add[u8](MASK, 127u8)
        \\    b = shift_right(-8i8, 2i8)
        \\    c = wrapping_mul(255u8, 255u8)
        \\    return i64(a) + i64(b) + i64(c) + i64(bit_and(7u8, 3u8))
    ;
    var compilation = try language.Compilation.init(allocator, "numbers.my", source);
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 2), (try compilation.execute(allocator)).value);
    const formatted = try compilation.format(allocator);
    defer allocator.free(formatted);
    var again = try language.Compilation.init(allocator, "formatted.my", formatted);
    defer again.deinit();
    try t.expectEqual(@as(i64, 2), (try again.execute(allocator)).value);
}
test "named integer operations share constants generic and runtime semantics under allocation failure" {
    try guest(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), guest, .{});
}
test "invalid runtime shifts are located and constant shifts reject before execution" {
    var runtime = try language.Compilation.init(t.allocator, "shift.my",
        \\def main() -> i64:
        \\    return shift_left(1, 64)
    );
    defer runtime.deinit();
    const result = try runtime.execute(t.allocator);
    try t.expectEqualStrings("R_INVALID_SHIFT", result.trap.code);
    var constant = try language.Compilation.init(t.allocator, "shift.my",
        \\const X: i64 = shift_right(1, -1)
        \\
        \\
        \\def main() -> i64:
        \\    return X
    );
    defer constant.deinit();
    try t.expectError(error.SourceError, constant.check());
    try t.expectEqualStrings("E_CONSTANT_ARITHMETIC", constant.diagnostics.items[0].code);
}
