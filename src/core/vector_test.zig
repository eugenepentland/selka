//! Release-pass tests: leaf inlining and the narrow-lane vector lowering.
const std = @import("std");
const support = @import("test_support.zig");
const vector = @import("vector.zig");

const affine =
    \\def affine(x: int) -> int:
    \\    return x * 3 + 7
    \\
    \\
    \\def main(args: list[str], out: Stream) -> int:
    \\    n = len(args) + 100
    \\    values = [(j * 37) % 1009 for j in range(n)]
    \\    total = 0
    \\    for j in range(n):
    \\        total += affine(values[j] + 5)
    \\    out.print(total)
    \\    return 0
    \\
;

// spec: NEW-CORE-INLINE-1
test "a release build inlines a single-block helper, so its arithmetic is proven in the caller" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.optimizedText(arena.allocator(), affine);
    const main_start = std.mem.indexOf(u8, text, "fn main(").?;
    const main_text = text[main_start..][0..std.mem.indexOf(u8, text[main_start..], "fn affine").?];
    try std.testing.expect(std.mem.indexOf(u8, main_text, "call i64 affine") == null);
    try std.testing.expect(std.mem.indexOf(u8, main_text, "mul.proven i64") != null);
}

const kernel =
    \\def main(args: list[str], out: Stream) -> int:
    \\    n = len(args) + 100
    \\    values = [(j * 37 + 5) % 1009 for j in range(n)]
    \\    total = 0
    \\    for j in range(n):
    \\        total += ((values[j] + 3) * 17 + 23) // 7 % 1009
    \\    out.print(total)
    \\    return 0
    \\
;

// spec: NEW-CORE-VECTOR-1
test "a counted reduction over a list with 16-bit facts becomes packed loads, multiply-high division and pmaddwd" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.releaseLlvmText(arena.allocator(), kernel);
    try std.testing.expect(std.mem.indexOf(u8, text, "@llvm.x86.avx2.packusdw") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "@llvm.x86.avx2.pmulhu.w") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "@llvm.x86.avx2.pmadd.wd") != null);
    // The scalar loop stays, entered after the vector part with its counter and sum.
    try std.testing.expect(std.mem.indexOf(u8, text, "[ %vc1, %vexit1 ]") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "[ %va1, %vexit1 ]") != null);
}

// spec-case: NEW-CORE-VECTOR-1
test "the multiply-high reciprocal is exact over the whole proven dividend range" {
    const seven = vector.reciprocal(7, 0, 5000).?;
    const quotient = (@as(u64, 4999) * seven.multiplier) >> (16 + @as(u6, seven.shift));
    try std.testing.expectEqual(@as(u64, 4999 / 7), quotient);
    const thousand = vector.reciprocal(1009, 0, 2000).?;
    const check = (@as(u64, 2000) * thousand.multiplier) >> (16 + @as(u6, thousand.shift));
    try std.testing.expectEqual(@as(u64, 1), check);
    try std.testing.expectEqual(@as(?vector.Reciprocal, null), vector.reciprocal(0, 0, 10));
}

const branchy =
    \\def main(args: list[str], out: Stream) -> int:
    \\    n = len(args) + 100
    \\    values = [(j * 37 + 5) % 1009 for j in range(n)]
    \\    flags = [(values[j] * 73 + j) % 101 < 50 for j in range(n)]
    \\    total = 0
    \\    for j in range(n):
    \\        x = values[j]
    \\        value = 0
    \\        if flags[j]:
    \\            value = x * 3 + 1
    \\        else:
    \\            value = x * 5 + 7
    \\        total += value
    \\    out.print(total)
    \\    return 0
    \\
;

// spec: NEW-CORE-VECTOR-2
test "an if/else over a list[bool] becomes a lane select whose mask is permuted like the packed values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.releaseLlvmText(arena.allocator(), branchy);
    try std.testing.expect(std.mem.indexOf(u8, text, "select <16 x i1>") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "load <16 x i8>") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "<i32 0, i32 1, i32 4, i32 5, i32 8, i32 9, i32 12, i32 13, i32 2, i32 3, i32 6, i32 7, i32 10, i32 11, i32 14, i32 15>") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "@llvm.x86.avx2.packusdw") != null);
}

const float_sum =
    \\def main(args: list[str], out: Stream) -> int:
    \\    n = len(args) + 100
    \\    values = [(j * 37) % 1009 for j in range(n)]
    \\    total = 0
    \\    for j in range(n):
    \\        total += int((float(values[j]) / 8.0 + 0.5) * 128000.0)
    \\    out.print(total)
    \\    return 0
    \\
;

// spec: NEW-CORE-FLOAT-1
test "float intervals prove int(float) in range, and proven-i32 conversions go through i32" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.optimizedText(arena.allocator(), float_sum);
    try std.testing.expect(std.mem.indexOf(u8, text, "float_to_int.proven i64") != null);
    const llvm = try support.releaseLlvmText(arena.allocator(), float_sum);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "sitofp i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "fptosi double") != null);
}

// spec: NEW-CORE-VERSION-1
test "a reduction too wide for 2^47 trips gets a guarded copy where its sum is proven" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.optimizedText(arena.allocator(), float_sum);
    // The guard compares the bound with the largest safe trip count.
    try std.testing.expect(std.mem.indexOf(u8, text, ":i64\n  branch") != null);
    // The original keeps its exact sum; the copy's sum is proven.
    try std.testing.expect(std.mem.indexOf(u8, text, "add.exact i64") != null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, text, "float_to_int.proven i64"));
}
