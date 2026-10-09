//! S3 scalar emission and verification premises.
const std = @import("std");
const support = @import("test_support.zig");

const numeric_source =
    \\func shifted(x: u8, count: u8) -> u8:
    \\    return shift_right(x, count)
    \\func saturated(x: i8) -> i8:
    \\    return saturating_add(x, 100i8)
    \\func multiplied(x: i8) -> i8:
    \\    return saturating_mul(x, -100i8)
    \\func subtracted(x: u64) -> u64:
    \\    return saturating_sub(x, 100u64)
    \\func transformed(x: float) -> float:
    \\    return sqrt(abs(x)) + trunc(x) + floor(x) + ceil(x)
    \\func main() -> int:
    \\    return int(transformed(float(shifted(200u8, 2u8)))) + int(saturated(40i8)) + int(multiplied(2i8)) + int(subtracted(5u64))
;

// spec: NEW-CORE-S3-NUMERIC-1
test "S3 numeric operations emit width checked shifts saturation add sub mul and float intrinsics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), numeric_source);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "icmp uge i8") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "lshr i8") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "llvm.sadd.sat.i8") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "myl_core_saturating_integer") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "llvm.sqrt.f64") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "llvm.fabs.f64") != null);
}

// spec-case: NEW-CORE-S3-NUMERIC-1
test "S3 verify mode retains checks for inferred shift count premises" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.verifyLlvmText(arena.allocator(), numeric_source);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "shiftbad") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "range [") != null);
}

// spec-case: NEW-CORE-S3-NUMERIC-1
test "S3 unchecked signed bits converted to unsigned retain a sound fact interval" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ir = @import("ir.zig");
    const facts = @import("facts.zig");
    var module: ir.Module = .{};
    var hand = try support.Hand.init(a, &module, "main", .{ .params = &.{}, .ret = .u64 });
    const converted = try hand.emit(.{ .op = .convert, .ty = .u64, .a = try hand.int(.i64, -12) });
    _ = try hand.emit(.{ .op = .ret, .ty = .void, .a = converted });
    _ = try hand.finish();
    const known = try facts.analyze(a, &module.functions.items[0], .{ .mark = false });
    try std.testing.expectEqual(facts.typeRange(.u64).?, known.ranges[converted.index()].?);
    try std.testing.expect(known.ranges[converted.index()].?.hi >= (@as(i128, 1) << 64) - 12);
}
