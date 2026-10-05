//! LLVM emission tests: checks, traps and the entry wrapper in the emitted text.
const std = @import("std");
const support = @import("test_support.zig");

const checked =
    \\def scale(x: int, d: int) -> int:
    \\    return (x * 3 + 1) // d
    \\
    \\
    \\def main(args: list[str], out: Stream) -> int:
    \\    out.print(scale(len(args), 2))
    \\    return 0
    \\
;

// spec: NEW-CORE-LLVM-1
test "exact checks become overflow intrinsics and range tests branching to a cold trap with a site index" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.llvmText(arena.allocator(), checked);
    try std.testing.expect(std.mem.indexOf(u8, text, "@llvm.smul.with.overflow.i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "@llvm.sadd.with.overflow.i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "call void @myl_core_trap(i32 0,") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "@myl_core_sites = constant [") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "!prof !0") != null);
}

// spec-case: NEW-CORE-LLVM-1
test "floor division by a variable checks zero and MIN // -1, then adjusts toward negative infinity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.llvmText(arena.allocator(), checked);
    try std.testing.expect(std.mem.indexOf(u8, text, "icmp eq i64 %p1, 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "icmp eq i64 %p1, -1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "sdiv i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "icmp slt i64") != null);
}

// spec-case: NEW-CORE-LLVM-1
test "the C entry builds main's argument list and returns its result as the exit status" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.llvmText(arena.allocator(), checked);
    try std.testing.expect(std.mem.indexOf(u8, text, "define i32 @main(i32 %argc, ptr %argv)") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "call ptr @myl_core_args(i32 %argc, ptr %argv)") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "call i32 @myl_core_exit(i64 %r)") != null);
}

const ir = @import("ir.zig");
const emit_llvm = @import("emit_llvm.zig");

/// A one-block `main(params) -> i64` that computes `op` on a float constant and returns 0.
fn handModule(arena: std.mem.Allocator, op: ir.Op, ty: ir.Type, params: []const ir.Type) !ir.Module {
    var module: ir.Module = .{};
    var function: ir.Function = .{ .name = "main", .signature = .{ .params = params, .ret = .i64 } };
    try function.insts.append(arena, .{ .op = .fconst, .ty = .f64 });
    try function.insts.append(arena, .{ .op = op, .ty = ty, .a = @fromBackingInt(@intCast(0)), .b = @fromBackingInt(@intCast(0)) });
    try function.insts.append(arena, .{ .op = .iconst, .ty = .i64 });
    try function.insts.append(arena, .{ .op = .ret, .ty = .void, .a = @fromBackingInt(@intCast(2)) });
    var block: ir.Block = .{};
    try block.insts.appendSlice(arena, &.{ @fromBackingInt(@intCast(1)), @fromBackingInt(@intCast(3)) });
    try function.blocks.append(arena, block);
    try module.functions.append(arena, function);
    return module;
}

fn noLocation(_: *const anyopaque, _: u32) emit_llvm.Location {
    return .{ .line = 1, .column = 1 };
}

fn emitHand(arena: std.mem.Allocator, module: *const ir.Module) emit_llvm.Error![]u8 {
    const context: u8 = 0;
    return emit_llvm.emitModule(arena, module, .{ .locator = .{ .context = &context, .locate = noLocation }, .source_path = "hand.my", .main = .{} });
}

// spec-case: NEW-CORE-LLVM-1
test "an instruction or entry signature the emitter cannot lower is an error, not wrong code" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const float_add = try handModule(arena.allocator(), .add, .f64, &.{});
    try std.testing.expectError(error.UnsupportedInstruction, emitHand(arena.allocator(), &float_add));
    const integer_main = try handModule(arena.allocator(), .fadd, .f64, &.{.i64});
    try std.testing.expectError(error.UnsupportedEntry, emitHand(arena.allocator(), &integer_main));
    const valid = try handModule(arena.allocator(), .fadd, .f64, &.{});
    const text = try emitHand(arena.allocator(), &valid);
    try std.testing.expect(std.mem.indexOf(u8, text, "fadd double 0x0000000000000000, 0x0000000000000000") != null);
}

const searching =
    \\def search(values: list[int], key: int) -> int:
    \\    low = 0
    \\    high = len(values)
    \\    while low < high:
    \\        middle = (low + high) // 2
    \\        if values[middle] < key:
    \\            low = middle + 1
    \\        else:
    \\            high = middle
    \\    return low
    \\
    \\
    \\def main(args: list[str], out: Stream) -> int:
    \\    out.print(search([1, 3, 5], len(args)))
    \\    return 0
    \\
;

/// The text of one emitted function, from its `define` to its closing brace.
fn functionText(text: []const u8, name: []const u8) []const u8 {
    const start = std.mem.indexOf(u8, text, name) orelse return "";
    const end = std.mem.indexOfPos(u8, text, start, "\n}\n") orelse return "";
    return text[start..end];
}

// spec: NEW-CORE-LLVM-2
test "proven arithmetic on non-negative values is nuw nsw, their comparisons are unsigned, and a proven search reads without a bounds test" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.releaseLlvmText(arena.allocator(), searching);
    const search = functionText(text, "define internal i64 @\"my.search\"");
    try std.testing.expect(search.len != 0);
    // `low + high` and `middle + 1`; `low < high` compares unsigned; `// 2` divides unsigned.
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, search, "add nuw nsw i64"));
    try std.testing.expect(std.mem.indexOf(u8, search, "icmp ult i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, search, "udiv i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, search, "icmp slt i64 %v6") == null);
    // The element comparison `values[middle] < key` stays signed: neither side is known non-negative.
    try std.testing.expect(std.mem.indexOf(u8, search, "icmp slt i64") != null);
    // No bounds test on `values[middle]`; what traps remain sit behind the folded `middle < 0`.
    try std.testing.expect(std.mem.indexOf(u8, search, "icmp uge i64") == null);
    try std.testing.expect(std.mem.indexOf(u8, search, "br i1 false") != null);
}

// spec: NEW-CORE-VERIFY-2
test "a verify build asserts each length bound and gives LLVM no unsigned promise" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.verifyLlvmText(arena.allocator(), searching);
    const search = functionText(text, "define internal i64 @\"my.search\"");
    try std.testing.expect(search.len != 0);
    try std.testing.expect(std.mem.indexOf(u8, text, "below the list length") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "at most the list length") != null);
    try std.testing.expect(std.mem.indexOf(u8, search, "nuw") == null);
    try std.testing.expect(std.mem.indexOf(u8, search, "icmp ult i64 %v") == null);
    // Every proven check is still emitted: the read's bounds test and both overflow intrinsics.
    try std.testing.expect(std.mem.indexOf(u8, search, "icmp uge i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, search, "@llvm.sadd.with.overflow.i64") != null);
}
