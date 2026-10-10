//! LLVM emission tests: checks, traps and the entry wrapper in the emitted text.
const std = @import("std");
const support = @import("test_support.zig");

const checked =
    \\func scale(x: int, d: int) -> int:
    \\    return (x * 3 + 1) // d
    \\
    \\
    \\func main(args: str[], out: Stream) -> int:
    \\    out.print(scale(len(args), 2))
    \\    return 0
    \\
;

// spec: NEW-CORE-LLVM-1
test "exact checks become overflow intrinsics and range tests branching to a cold trap with a site pointer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.llvmText(arena.allocator(), checked);
    try std.testing.expect(std.mem.indexOf(u8, text, "@llvm.smul.with.overflow.i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "@llvm.sadd.with.overflow.i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "call void @myl_core_trap(ptr @myl.site.0,") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "@myl.site.0 = private constant %myl.site") != null);
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

fn emitHand(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *const ir.Module) emit_llvm.Error![]u8 {
    const context: u8 = 0;
    return emit_llvm.emitModuleWithScratch(arena, backing, module, .{ .locator = .{ .context = &context, .locate = noLocation }, .source_path = "hand.my", .main = .{} });
}

fn repeatedText(a: std.mem.Allocator, backing: std.mem.Allocator, module: *const ir.Module) ![12][]const u8 {
    var texts: [12][]const u8 = undefined;
    for (&texts) |*text| text.* = try emitHand(a, backing, module);
    return texts;
}

// spec-case: NEW-CORE-LLVM-1
test "LLVM emission retains only final text in an arena caller across repeated emissions" {
    var ir_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer ir_arena.deinit();
    const module = try handModule(ir_arena.allocator(), .fadd, .f64, &.{});
    const expected = try emitHand(std.testing.allocator, std.testing.allocator, &module);
    defer std.testing.allocator.free(expected);
    // Exactly the output bytes fit; even one retained temporary or an arena
    // backed by the caller would exhaust this allocator on the first render.
    const storage = try std.testing.allocator.alloc(u8, expected.len * 12);
    defer std.testing.allocator.free(storage);
    var caller = std.heap.FixedBufferAllocator.init(storage);
    const texts = try repeatedText(caller.allocator(), std.testing.allocator, &module);
    // All emitter scratch arenas have already been destroyed, and later
    // renders reused their pages. Earlier output must still be intact.
    for (texts) |text| try std.testing.expectEqualStrings(expected, text);
    try std.testing.expectEqual(storage.len, caller.end_index);
}

// spec-case: NEW-CORE-LLVM-1
test "LLVM emission failure releases scratch without allocating caller storage" {
    var ir_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer ir_arena.deinit();
    const module = try handModule(ir_arena.allocator(), .add, .f64, &.{});
    var caller = std.heap.FixedBufferAllocator.init(&.{});
    try std.testing.expectError(error.UnsupportedInstruction, emitHand(caller.allocator(), std.testing.allocator, &module));
    try std.testing.expectEqual(@as(usize, 0), caller.end_index);
}

/// An unused unmanaged memory phi whose entry operand is undef.
fn unmanagedUndefPhi(arena: std.mem.Allocator) !ir.Module {
    var module: ir.Module = .{};
    const holder = try module.intern(arena, .{ .record = &.{ .i64, .i64, .i64, .i64, .i64 } });
    var h = try support.Hand.init(arena, &module, "main", .{ .params = &.{}, .ret = .i64 });
    const header = try h.newBlock();
    const latch = try h.newBlock();
    const exit = try h.newBlock();
    const undef = try h.loose(.{ .op = .undef, .ty = holder });
    try h.jump(header);
    h.block = header;
    const phi = try h.loose(.{ .op = .phi, .ty = holder });
    try h.function.blocks.items[header.index()].insts.append(arena, phi);
    const condition = try h.int(.bool, 0);
    try h.branch(condition, latch, exit);
    h.block = latch;
    const one = try h.int(.i64, 1);
    const next = try h.emit(.{ .op = .record_make, .ty = holder, .data = try h.extra(&.{ one, one, one, one, one }) });
    try h.jump(header);
    h.function.insts.items[phi.index()].data = try h.extra(&.{ undef, next });
    h.block = exit;
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    _ = try h.finish();
    return module;
}

// spec-case: NEW-CORE-RC-11
test "unmanaged undef memory phis leave their undefined edge alone without copying from poison" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const module = try unmanagedUndefPhi(arena.allocator());
    try support.verified(arena.allocator(), &module, &.{});
    const text = try emitHand(arena.allocator(), std.testing.allocator, &module);
    try std.testing.expect(std.mem.indexOf(u8, text, "@myl.zeros") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "ptr poison") == null);
    const entry = std.mem.indexOf(u8, text, "b0:\n") orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.startsWith(u8, text[entry..], "b0:\n  br label %b1\n"));
    // The latch's construction is built straight in the phi's home (NEW-CORE-CE-RECORDS-1): no copy.
    try std.testing.expect(std.mem.indexOf(u8, text, "call void @llvm.memmove.p0.p0.i64") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "call void @llvm.memcpy.p0.p0.i64") == null);
}

// spec-case: NEW-CORE-LLVM-1
test "an instruction or entry signature the emitter cannot lower is an error, not wrong code" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const float_add = try handModule(arena.allocator(), .add, .f64, &.{});
    try std.testing.expectError(error.UnsupportedInstruction, emitHand(arena.allocator(), std.testing.allocator, &float_add));
    const integer_main = try handModule(arena.allocator(), .fadd, .f64, &.{.i64});
    try std.testing.expectError(error.UnsupportedEntry, emitHand(arena.allocator(), std.testing.allocator, &integer_main));
    const valid = try handModule(arena.allocator(), .fadd, .f64, &.{});
    const text = try emitHand(arena.allocator(), std.testing.allocator, &valid);
    try std.testing.expect(std.mem.indexOf(u8, text, "fadd double 0x0000000000000000, 0x0000000000000000") != null);
}

const searching =
    \\func search(values: int[], key: int) -> int:
    \\    mut low = 0
    \\    mut high = len(values)
    \\    while low < high:
    \\        mut middle = (low + high) // 2
    \\        if values[middle] < key:
    \\            low = middle + 1
    \\        else:
    \\            high = middle
    \\    return low
    \\
    \\
    \\func main(args: str[], out: Stream) -> int:
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
    const search = functionText(text, "define internal fastcc i64 @\"my.search\"");
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
    const search = functionText(text, "define internal fastcc i64 @\"my.search\"");
    try std.testing.expect(search.len != 0);
    try std.testing.expect(std.mem.indexOf(u8, text, "below the list length") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "at most the list length") != null);
    try std.testing.expect(std.mem.indexOf(u8, search, "nuw") == null);
    try std.testing.expect(std.mem.indexOf(u8, search, "icmp ult i64 %v") == null);
    // Every proven check is still emitted: the read's bounds test and both overflow intrinsics.
    try std.testing.expect(std.mem.indexOf(u8, search, "icmp uge i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, search, "@llvm.sadd.with.overflow.i64") != null);
}

const narrow_extern =
    \\extern func pack(host: Host, a: i8, b: u16, c: bool, d: i32) -> i64 effects(host)
    \\
    \\
    \\func main(args: str[], host: Host, out: Stream) -> int:
    \\    mut flag = len(args) > 1
    \\    out.print(pack(host, i8(len(args)), 7u16, flag, -1i32))
    \\    return 0
    \\
;

const from_end_index =
    \\func pick(xs: int[], i: int) -> int:
    \\    return xs[i]
    \\
    \\
    \\func main() -> int:
    \\    return pick([1, 2, 3], -1)
    \\
;

/// The label of the block that holds `needle`'s first line, or null.
fn blockOf(text: []const u8, needle: []const u8) ?[]const u8 {
    const at = std.mem.indexOf(u8, text, needle) orelse return null;
    var lines = std.mem.splitBackwardsScalar(u8, text[0..at], '\n');
    while (lines.next()) |line| {
        if (line.len != 0 and line[line.len - 1] == ':' and line[0] != ' ') return line;
    }
    return null;
}

// spec: NEW-CORE-S5-COLD-INDEX-1
test "a bounds trap recovers the index the program wrote on the trap's cold path only" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.llvmText(arena.allocator(), from_end_index);
    // A list index is tested as written first (NEW-CORE-F2-WRAP-1), so its trap reports the
    // written index `%p1` itself, from the trap's cold block, with nothing to recover.
    const block = blockOf(text, "i64 %p1, i64 %len") orelse return error.TestExpectedRecovery;
    try std.testing.expect(std.mem.startsWith(u8, block, "trap"));
}

const runtime_bool_helpers =
    \\func main(out: Stream) -> int:
    \\    mut word = "Mixed"
    \\    out.print(word.upper(), word.lower(), repr(word))
    \\    return 0
    \\
;

// spec: NEW-CORE-S5-RUNTIME-ABI-1
test "a C runtime helper's bool parameter carries zeroext on its declaration and its calls" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.llvmText(arena.allocator(), runtime_bool_helpers);
    try std.testing.expect(std.mem.indexOf(u8, text, "@myl_core_text_case(ptr, i1 zeroext)") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "call ptr @myl_core_text_case(ptr @myl.str.0, i1 zeroext true)") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "call ptr @myl_core_text_repr(ptr @myl.str.0, i1 zeroext false)") != null);
}

// spec: NEW-CORE-S5-EXTERN-ABI-1
test "a source extern's i8, i16, u8, u16 and bool parameters carry their SysV extension; an i32 passes as it is" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.llvmText(arena.allocator(), narrow_extern);
    try std.testing.expect(std.mem.indexOf(u8, text, "declare i64 @pack(i8 signext, i16 zeroext, i1 zeroext, i32) nounwind\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "call i64 @pack(i8 signext %") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, ", i16 zeroext 7, i1 zeroext %") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, ", i32 -1)") != null);
}

/// Separate physical entries reproduce a fresh lowering pool before snapshot interning.
fn repeatedLiteralModule(a: std.mem.Allocator, second: ir.Type) !ir.Module {
    var module: ir.Module = .{};
    try module.strings.appendSlice(a, &.{ "abc", "abc" });
    for ([_]ir.Type{ .str, second }, 0..) |ty, index| {
        var h = try support.Hand.init(a, &module, if (index == 0) "first" else "second", .{ .params = &.{}, .ret = ty });
        const literal = try h.loose(.{ .op = .str_const, .ty = ty, .data = index });
        _ = try h.emit(.{ .op = .ret, .ty = .void, .a = literal });
        _ = try h.finish();
    }
    module.entry = 2;
    var main = try support.Hand.init(a, &module, "main", .{ .params = &.{}, .ret = .i64 });
    _ = try main.emit(.{ .op = .ret, .ty = .void, .a = try main.int(.i64, 0) });
    _ = try main.finish();
    return module;
}

// spec-case: NEW-CORE-LLVM-1
test "equal literal bytes emit identical pools before and after snapshot interning" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module = try repeatedLiteralModule(a, .str);
    const fresh = try emitHand(a, std.testing.allocator, &module);
    const snapshot = @import("ir_snapshot.zig");
    const context = try snapshot.Context.init(a, &module, null);
    const wire = try snapshot.capture(a, context, module.functions.items[1]);
    module.functions.items[1] = try snapshot.restore(a, context, wire);
    try std.testing.expectEqual(@as(u64, 0), module.functions.items[1].insts.items[0].data);
    const restored = try emitHand(a, std.testing.allocator, &module);
    try std.testing.expectEqualStrings(fresh, restored);
    try std.testing.expect(std.mem.indexOf(u8, fresh, "@myl.str.1") == null);
}

// spec-case: NEW-CORE-LLVM-1
test "equal string and byte literals preserve shared raw metadata across physical IDs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module = try repeatedLiteralModule(a, .bytes);
    const separate = try emitHand(a, std.testing.allocator, &module);
    module.functions.items[1].insts.items[0].data = 0;
    const shared = try emitHand(a, std.testing.allocator, &module);
    try std.testing.expectEqualStrings(shared, separate);
    try std.testing.expect(std.mem.indexOf(u8, separate, "@myl.str.1") == null);
}
