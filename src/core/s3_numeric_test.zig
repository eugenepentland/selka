//! S3 scalar emission and verification premises.
const std = @import("std");
const support = @import("test_support.zig");

const numeric_source =
    \\def shifted(x: u8, count: u8) -> u8:
    \\    return shift_right(x, count)
    \\def saturated(x: i8) -> i8:
    \\    return saturating_add(x, 100i8)
    \\def transformed(x: float) -> float:
    \\    return sqrt(abs(x)) + trunc(x) + floor(x) + ceil(x)
    \\def main() -> int:
    \\    return int(transformed(float(shifted(200u8, 2u8)))) + int(saturated(40i8))
;

// spec: NEW-CORE-S3-NUMERIC-1
test "S3 numeric operations emit checked shifts saturating width and strict float intrinsics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), numeric_source);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "icmp uge i8") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "lshr i8") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "llvm.sadd.sat.i8") != null);
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
