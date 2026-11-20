//! Release-pass tests: leaf inlining and the narrow-lane vector lowering.
const std = @import("std");
const support = @import("test_support.zig");
const vector = @import("vector.zig");
const ir = @import("ir.zig");
const facts = @import("facts.zig");
const passes = @import("passes.zig");

const affine =
    \\func affine(x: int) -> int:
    \\    return x * 3 + 7
    \\
    \\
    \\func main(args: str[], out: Stream) -> int:
    \\    mut n = len(args) + 100
    \\    mut values: int[] = []
    \\    for j in range(n):
    \\        append(mut values, (j * 37) % 1009)
    \\    mut total = 0
    \\    for j in range(n):
    \\        total += affine(values[j] + 5)
    \\    print(out, total)
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

// spec-case: NEW-CORE-INLINE-1
test "a bounded signed remainder leaf inlines for both unknown and constant negative inputs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.optimizedText(arena.allocator(), "func bounded(x: int) -> int:\n    return x % 1000 + 1\n" ++
        "func main(args: str[], out: Stream) -> int:\n    print(out, bounded(len(args) - 2000), bounded(-1))\n    return 0\n");
    const start = std.mem.indexOf(u8, text, "fn main(").?;
    const main_text = text[start..][0..std.mem.indexOf(u8, text[start..], "fn bounded").?];
    try std.testing.expect(std.mem.indexOf(u8, main_text, "call i64 bounded") == null);
}

const kernel =
    \\func main(args: str[], out: Stream) -> int:
    \\    mut n = len(args) + 100
    \\    mut values: int[] = []
    \\    for j in range(n):
    \\        append(mut values, (j * 37 + 5) % 1009)
    \\    mut total = 0
    \\    for j in range(n):
    \\        total += ((values[j] + 3) * 17 + 23) // 7 % 1009
    \\    print(out, total)
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
    \\func main(args: str[], out: Stream) -> int:
    \\    mut n = len(args) + 100
    \\    mut values: int[] = []
    \\    for j in range(n):
    \\        append(mut values, (j * 37 + 5) % 1009)
    \\    mut flags: bool[] = []
    \\    for j in range(n):
    \\        append(mut flags, (values[j] * 73 + j) % 101 < 50)
    \\    mut total = 0
    \\    for j in range(n):
    \\        mut x = values[j]
    \\        mut value = 0
    \\        if flags[j]:
    \\            value = x * 3 + 1
    \\        else:
    \\            value = x * 5 + 7
    \\        total += value
    \\    print(out, total)
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
    \\func main(args: str[], out: Stream) -> int:
    \\    mut n = len(args) + 100
    \\    mut values: int[] = []
    \\    for j in range(n):
    \\        append(mut values, (j * 37) % 1009)
    \\    mut total = 0
    \\    for j in range(n):
    \\        total += int((float(values[j]) / 8.0 + 0.5) * 128000.0)
    \\    print(out, total)
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

const dispatch =
    \\func main(args: str[], out: Stream) -> int:
    \\    mut kind = len(args)
    \\    mut n = len(args) + 100
    \\    mut values: int[] = []
    \\    for j in range(n):
    \\        append(mut values, (j * 37 + 5) % 1009)
    \\    mut total = 0
    \\    for j in range(n):
    \\        mut x = values[j]
    \\        mut value = 0
    \\        if kind == 0:
    \\            value = x * 3
    \\        elif kind == 1:
    \\            value = x + 7
    \\        total += value
    \\    print(out, total)
    \\    return 0
    \\
;

// spec-case: NEW-CORE-UNSWITCH-1
test "a branch on a loop-invariant comparison is decided once before the loop, leaving straight loops that vectorize" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.releaseLlvmText(arena.allocator(), dispatch);
    // One vector loop for kind 0 and one for kind 1; the remaining copy only adds zero.
    try std.testing.expect(std.mem.indexOf(u8, text, "vexit1:") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "vexit2:") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "@llvm.x86.avx2.pmadd.wd") != null);
}

const invariant_widths =
    \\func main(args: str[], out: Stream) -> int:
    \\    mut n = len(args) + 100
    \\    mut values: int[] = []
    \\    mut bs: u8[] = []
    \\    for j in range(n):
    \\        append(mut values, (j * 37 + 5) % 1009)
    \\        append(mut bs, u8((j * 13 + 1) % 200))
    \\    const c8: u8 = u8(len(args) % 8) + 40u8
    \\    const c16: u16 = u16(len(args) % 8) + 90u16
    \\    const c32: i32 = i32(len(args) % 8) + 100i32
    \\    mut divided = 0
    \\    for j in range(n):
    \\        divided += values[j] % 1009 + int(c8 // 7u8)
    \\    mut widened = 0
    \\    for j in range(n):
    \\        widened += values[j] % 1009 + int(c8)
    \\    mut masked16 = 0
    \\    for j in range(n):
    \\        mut v = values[j] % 1009
    \\        if u16(bs[j]) < c16:
    \\            v = v + 3
    \\        masked16 += v
    \\    mut masked32 = 0
    \\    for j in range(n):
    \\        mut v = values[j] % 1009
    \\        if i32(bs[j]) < c32:
    \\            v = v + 5
    \\        masked32 += v
    \\    print(out, divided, widened, masked16, masked32)
    \\    return 0
    \\
;

// spec-case: NEW-CORE-VECTOR-1
test "a loop-invariant operand narrower than, as wide as or wider than the lanes is splatted from its own width" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // FX7: the splat read every invariant as an `i64` (`trunc i64 %v44 to i16` of a `u8`), which clang refused.
    const text = try support.releaseLlvmText(a, invariant_widths);
    try std.testing.expect(std.mem.indexOf(u8, text, "vexit4:") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, ".t = zext i8 ") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, ".t = add i16 ") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, ".t = trunc i32 ") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, ".t = trunc i64 %v") == null);
    // Compiled and run, the four vector loops give what the scalar loops give (`--unoptimized`).
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, invariant_widths, &refusal);
    const result = try support.runPasses(a, &module, .trusted);
    const ran = try support.runOwned(a, &module, .{ .own = false, .analysis = support.analysis(&result), .main = .{ .parameters = &.{ "args", "out" } } });
    try std.testing.expectEqualStrings("47935 51435 47579 47700\n", ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
}

/// A function of `loops` copies of a select loop on one loop-invariant comparison: unswitching splits each, and the vector
/// part of every copy is emitted into the one function.
fn manyLoops(a: std.mem.Allocator, loops: usize) ![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(a, "func main(args: str[], out: Stream) -> int:\n    mut values: int[] = []\n    for j in range(len(args) + 100):\n" ++
        "        append(mut values, (j * 37 + 5) % 1009)\n    const flag = len(args) > 3\n    mut total = 0\n");
    for (0..loops) |k| try text.print(a, "    for j in range(len(values)):\n        mut v = 0\n        if flag:\n            v = values[j] % 100 + {d}\n" ++
        "        else:\n            v = values[j] % 50 + {d}\n        total += v\n", .{ k, k });
    try text.appendSlice(a, "    print(out, total)\n    return 0\n");
    return text.items;
}

// spec-case: NEW-CORE-VECTOR-1
test "a function with more than twenty vector loops names each loop's values apart" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // FX7: `%vtot2{d}` of the first loop and `%vtot{d}` of the 21st were both `%vtot21`, which clang refused.
    const source = try manyLoops(a, 18);
    const text = try support.releaseLlvmText(a, source);
    try std.testing.expect(std.mem.indexOf(u8, text, "vexit21:") != null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text, "%vtot21 = "));
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const result = try support.runPasses(a, &module, .trusted);
    const ran = try support.runOwned(a, &module, .{ .own = false, .analysis = support.analysis(&result), .main = .{ .parameters = &.{ "args", "out" } } });
    try std.testing.expectEqualStrings("60030\n", ran.stdout);
}

const targets = @import("target.zig");
const c_abi = @import("c_abi.zig");

// spec: NEW-CORE-TARGET-1
test "target choices come from one description, and without x86 intrinsics the vector code is generic LLVM" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqual(@as(u16, 256), targets.host.vector.bits);
    try std.testing.expectEqual(@as(i128, 1) << 47, targets.host.maxListLength());
    const generic = try support.releaseLlvmTextFor(arena.allocator(), branchy, targets.generic_256);
    try std.testing.expect(std.mem.indexOf(u8, generic, "@llvm.x86.") == null);
    try std.testing.expect(std.mem.indexOf(u8, generic, "select <16 x i1>") != null);
    try std.testing.expect(std.mem.indexOf(u8, generic, "@llvm.vector.reduce.add.v16i64") != null);
    try std.testing.expectEqualStrings("runtime_bench_now", c_abi.symbol("int_math::runtime_bench_now"));
}

const counter_arm =
    \\func main(args: str[], out: Stream) -> int:
    \\    mut n = len(args) + 100
    \\    mut second: int[] = []
    \\    for j in range(n):
    \\        append(mut second, (j * 38 + 3) % 64)
    \\    mut flags: bool[] = []
    \\    for j in range(n):
    \\        append(mut flags, j % 3 != 0)
    \\    mut total = 0
    \\    for j in range(n):
    \\        mut v = second[j]
    \\        if flags[j]:
    \\            v = j
    \\        else:
    \\            v = v + 101
    \\        total += v
    \\    print(out, total)
    \\    return 0
    \\
;

// spec-case: NEW-CORE-VECTOR-2
test "a select arm that is the loop counter keeps the loop scalar instead of splatting a value defined in the loop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // Fuzz seed 80 case 36: the counter was splatted before the vector part, where it does not exist yet.
    const text = try support.releaseLlvmText(arena.allocator(), counter_arm);
    try std.testing.expect(std.mem.indexOf(u8, text, "%vexit1") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "select <") == null);
}

// Three byte passes exceed the reader inliner's two-loop limit. Both calls must
// survive so these tests exercise the callee's all-call parameter range.
// spec: PY-SET-OPS-1
const byte_helper =
    \\func score(raw: bytes, mask: int) -> int:
    \\    mut total = 0
    \\    for value in raw:
    \\        total += bit_xor(value, mask)
    \\    mut plain = 0
    \\    for value in raw:
    \\        plain += value
    \\    mut masked = 0
    \\    for value in raw:
    \\        masked += value % 128
    \\    return total + plain + masked
    \\
    \\
    \\func main(args: str[], out: Stream) -> int:
    \\    mut octets: int[] = []
    \\    for j in range(len(args) + 100):
    \\        append(mut octets, (j * 37) % 256)
    \\    mut raw = bytes(octets)
    \\    print(out, score(raw, 3) + score(raw, 200))
    \\    return 0
    \\
;

/// The text of `name`'s definition in LLVM module `text`.
fn definition(text: []const u8, name: []const u8) []const u8 {
    const start = std.mem.indexOf(u8, text, name).?;
    const end = std.mem.indexOf(u8, text[start..], "\n}\n").?;
    return text[start..][0..end];
}

// spec: NEW-CORE-VECTOR-3
test "a byte reduction that only converts and XORs runs in 8-bit lanes summed by psadbw, and widens on a generic target" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const x86 = definition(try support.releaseLlvmText(arena.allocator(), byte_helper), "define internal fastcc i64 @\"my.score\"(");
    try std.testing.expect(std.mem.indexOf(u8, x86, "load <32 x i8>") != null);
    try std.testing.expect(std.mem.indexOf(u8, x86, "xor <32 x i8>") != null);
    try std.testing.expect(std.mem.indexOf(u8, x86, "@llvm.x86.avx2.psad.bw") != null);
    const generic = definition(try support.releaseLlvmTextFor(arena.allocator(), byte_helper, @import("target.zig").generic_256), "define internal fastcc i64 @\"my.score\"(");
    try std.testing.expect(std.mem.indexOf(u8, generic, "psad") == null);
    try std.testing.expect(std.mem.indexOf(u8, generic, "zext <32 x i8>") != null);
}

// spec: NEW-CORE-FACTS-10
test "a parameter takes the hull of every call's argument, so a helper's byte sum needs no overflow check, and verify builds assert it on entry" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const optimized = try support.optimizedText(a, byte_helper);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, optimized, "call i64 score("));
    const released = definition(try support.releaseLlvmText(a, byte_helper), "define internal fastcc i64 @\"my.score\"(");
    try std.testing.expect(std.mem.indexOf(u8, released, "with.overflow") == null);
    try std.testing.expect(std.mem.indexOf(u8, try support.verifyLlvmText(a, byte_helper), "range [3, 200]") != null);
}

// spec-case: NEW-CORE-VECTOR-3
test "a callable three-pass byte score agrees with scalar arithmetic in release and verify builds" {
    for ([_]passes.Mode{ .trusted, .verify }) |mode| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var refusal: @import("build.zig").Refusal = .{};
        var module = try support.buildSource(a, byte_helper, &refusal);
        const result = try support.runPasses(a, &module, mode);
        const ran = try support.runOwned(a, &module, .{
            .own = false,
            .release = true,
            .verify = mode == .verify,
            .analysis = support.analysis(&result),
            .main = .{ .parameters = &.{ "args", "out" } },
        });
        try std.testing.expectEqual(@as(u8, 0), ran.status);
        try std.testing.expectEqualStrings("62740\n", ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
    }
}

/// The index of the function called `name`, or null.
fn functionIndex(module: *const ir.Module, name: []const u8) ?u32 {
    for (module.functions.items, 0..) |function, index| {
        if (std.mem.eql(u8, function.name, name)) return @intCast(index);
    }
    return null;
}

/// The caller-derived interval of `score`'s mask in `module`, or null.
fn maskRange(arena: std.mem.Allocator, module: *ir.Module) !?facts.Interval {
    const first = try arena.alloc(?facts.Facts, module.functions.items.len);
    for (module.functions.items, first) |*function, *slot| {
        slot.* = if (function.signature.linkage == .internal) try facts.analyze(arena, function, .{ .mark = false }) else null;
    }
    const ranges = try passes.parameterRanges(arena, module, first);
    for (module.functions.items, ranges) |function, params| {
        if (std.mem.eql(u8, function.name, "score")) return if (params.len == 2) params[1] else null;
    }
    return null;
}

// spec-case: NEW-CORE-FACTS-10
test "a function a function value names gets no caller-derived parameter intervals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, byte_helper, &refusal);
    const direct = (try maskRange(a, &module)).?;
    try std.testing.expectEqual(@as(i128, 3), direct.lo);
    try std.testing.expectEqual(@as(i128, 200), direct.hi);
    // Naming `score` as a value anywhere means some call may come from elsewhere.
    const score = functionIndex(&module, "score").?;
    const main = &module.functions.items[functionIndex(&module, "main").?];
    try main.insts.append(a, .{ .op = .func_ref, .ty = .i64, .data = score });
    try std.testing.expectEqual(@as(?facts.Interval, null), try maskRange(a, &module));
}

// spec: NEW-CORE-INLINE-S4-1
test "loop helper inlining verifies cloned edges and projects mut return values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\func find(mut parent: int[], start: int) -> int:
        \\    mut x = start
        \\    while parent[x] != x:
        \\        parent[x] = parent[parent[x]]
        \\        x = parent[x]
        \\    return x
        \\func main(out: Stream) -> int:
        \\    mut parent = [0, 0, 1]
        \\    print(out, find(mut parent, 2), parent[2])
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(arena.allocator(), source, &refusal);
    var origins: @import("inline_origins.zig").Table = .{};
    try std.testing.expect(try @import("inline.zig").inlineLeaves(arena.allocator(), &module, &origins) > 0);
    var failure: @import("verify_ir.zig").Failure = .{};
    try @import("verify_ir.zig").verifyModule(arena.allocator(), &module, &failure);
    const main = module.functions.items[functionIndex(&module, "main").?];
    for (main.insts.items) |inst| try std.testing.expect(inst.op != .call);
    const result = try support.runOwned(arena.allocator(), &module, .{});
    try std.testing.expectEqualStrings("0 0\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}
