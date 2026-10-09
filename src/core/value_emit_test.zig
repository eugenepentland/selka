//! S1 lane V emission: records and unions over four words live in memory (never as LLVM
//! aggregates), a construction is stored straight into its consumer, and a `match` on a union
//! element reads its tag and then only the payload the arm uses.
const std = @import("std");
const support = @import("test_support.zig");

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

/// The LLVM text of the function `name` (from its `define` line to the closing brace).
fn functionText(llvm: []const u8, name: []const u8) []const u8 {
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, llvm, from, "define ")) |start| : (from = start + 1) {
        const line_end = std.mem.indexOfPos(u8, llvm, start, "\n").?;
        if (std.mem.indexOf(u8, llvm[start..line_end], name) == null) continue;
        return llvm[start..std.mem.indexOfPos(u8, llvm, start, "\n}\n").?];
    }
    unreachable;
}

const wide =
    \\record Wide:
    \\    a: int
    \\    b: int
    \\    c: int
    \\    d: int
    \\    e: int
    \\    f: int
    \\
    \\
    \\func mk(i: int) -> Wide:
    \\    return Wide(a=i, b=i + 1, c=i + 2, d=i + 3, e=i + 4, f=i + 5)
    \\
    \\
    \\func widen(input: Wide, k: int) -> Wide:
    \\    mut w = input
    \\    w.a = w.a + k
    \\    w.f = w.f * 2
    \\    return w
    \\
    \\
    \\func swap_loop(a0: Wide, b0: Wide, n: int) -> int:
    \\    mut a = a0
    \\    mut b = b0
    \\    for i in range(n):
    \\        mut t = a
    \\        a = widen(b, i)
    \\        b = t
    \\    return a.a * 1000 + b.a
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(swap_loop(mk(1), mk(100), 5))
    \\    return 0
    \\
;

// spec: NEW-CORE-LLVM-3
test "a record over four words is a pointer to a stack slot: never an LLVM aggregate, read in place and returned through sret" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), wide);
    try std.testing.expect(!contains(llvm, "insertvalue { i64, i64, i64, i64, i64, i64 }"));
    try std.testing.expect(!contains(llvm, "extractvalue { i64, i64, i64, i64, i64, i64 }"));
    const widen = functionText(llvm, "@\"my.widen\"");
    try std.testing.expect(contains(widen, "ptr noalias sret([48 x i8]) align 8 %ret, ptr noalias readonly align 8 %p0, i64 %p1"));
    // The first write copies the parameter (its caller's memory is read-only) into the caller's
    // destination; the second writes that copy where it is, and the return copies nothing.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, widen, "@llvm.memcpy"));
    // Built in place in the return slot: the stores go to `%ret`, with no copy.
    const make = functionText(llvm, "@\"my.mk\"");
    try std.testing.expect(!contains(make, "memcpy"));
    try std.testing.expect(contains(make, "store i64 %p0, ptr %ret"));
}

// spec: NEW-CORE-LLVM-5
test "a loop-carried record in memory owns a stack slot filled on each edge, with no phi of pointers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), wide);
    const loop = functionText(llvm, "@\"my.swap_loop\"");
    try std.testing.expect(!contains(loop, "phi ptr"));
    // Two such phis swap values: the back edge first copies `a` into `b`'s home, then the call's
    // result into `a`'s (a parallel copy in order, NEW-CORE-CE-RECORDS-1), with no temporary; the
    // entry copies the read-only parameters in.
    try std.testing.expectEqual(@as(usize, 4), std.mem.count(u8, loop, "@llvm.memcpy"));
    try std.testing.expect(contains(loop, "= alloca [48 x i8]"));
}

const stores =
    \\record Cell:
    \\    code: int
    \\    weight: int
    \\    flag: bool
    \\
    \\
    \\enum Value:
    \\    integer(value: int)
    \\    cell(value: Cell)
    \\
    \\
    \\func values(n: int) -> Value[]:
    \\    mut vs: Value[] = []
    \\    for i in range(n):
    \\        vs.append(Value.cell(value=Cell(code=i, weight=i, flag=True)))
    \\        vs.append(Value.integer(value=i))
    \\    return vs
    \\
    \\
    \\func peek(vs: Value[], i: int) -> int:
    \\    match vs[i]:
    \\        case Value.integer(value=n):
    \\            return n
    \\        case Value.cell(value=c):
    \\            return c.code * 10 + c.weight
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(peek(values(3), 4))
    \\    return 0
    \\
;

// spec: NEW-CORE-LLVM-4
test "a record or union pushed onto a list is stored field by field into the element: no temporary, no memcpy, no aggregate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), stores);
    const values = functionText(llvm, "@\"my.values\"");
    try std.testing.expect(!contains(values, "memcpy"));
    try std.testing.expect(!contains(values, "insertvalue"));
    // The cell case: tag word 1... then the three fields of the payload at +8, +16 and +24.
    try std.testing.expect(contains(values, "store i64 1, ptr %elt."));
    try std.testing.expect(contains(values, "store i8 %sb."));
    // The integer case: tag word 0 and the payload word.
    try std.testing.expect(contains(values, "store i64 0, ptr %elt."));
}

// spec: NEW-CORE-LLVM-6
test "a match on a union list element loads its tag word, then only the payload fields the arm reads" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), stores);
    const peek = functionText(llvm, "@\"my.peek\"");
    // No whole element is loaded: no struct is built from the union's words.
    try std.testing.expect(!contains(peek, "insertvalue"));
    try std.testing.expect(!contains(peek, "memcpy"));
    // One tag load (with the bounds check), then loads of the two payload fields of the cell arm.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, peek, "icmp uge i64"));
    try std.testing.expect(std.mem.count(u8, peek, "load i64, ptr") >= 4);
}
