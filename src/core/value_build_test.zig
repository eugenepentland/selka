//! S1 lane V: the Core IR the builder makes for records, unions, `?`, element writes,
//! `pop`, writes through hidden receivers and `mut` parameters, and what it refuses.
const std = @import("std");
const support = @import("test_support.zig");
const build = @import("build.zig");

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

const records =
    \\record Point:
    \\    x: int
    \\    y: int
    \\
    \\
    \\record Line:
    \\    from_point: Point
    \\    to_point: Point
    \\    on: bool
    \\
    \\
    \\def shift(line: Line, dx: int) -> int:
    \\    line.to_point.x = line.to_point.x + dx
    \\    return line.to_point.x - line.from_point.x
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    out.print(shift(Line(from_point=Point(x=1, y=2), to_point=Point(x=5, y=6), on=True), 3))
    \\    return 0
    \\
;

// spec: NEW-CORE-RECORD-2
test "records are built with record_make, read with record_get and written with record_set along the field path" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), records);
    try std.testing.expect(contains(text, "record_make record{i64, i64} 1:i64, 2:i64"));
    try std.testing.expect(contains(text, "record_make record{record{i64, i64}, record{i64, i64}, bool}"));
    // `line.to_point.x = ...` reads the inner record, replaces its field, and replaces the outer field.
    try std.testing.expect(contains(text, "record_get record{i64, i64} param0, field1"));
    try std.testing.expect(contains(text, "record_set record{i64, i64}"));
    try std.testing.expect(contains(text, "record_set record{record{i64, i64}, record{i64, i64}, bool} param0, field1"));
}

const unions =
    \\union Shape:
    \\    circle: int,
    \\    square: int,
    \\    unit
    \\
    \\
    \\def fail(x: int) -> Result[int, str]:
    \\    if x < 0:
    \\        return Err("neg")
    \\    return Ok(x)
    \\
    \\
    \\def go(x: int) -> Result[int, str]:
    \\    v = fail(x)?
    \\    return Ok(v + 1)
    \\
    \\
    \\def pick(s: Shape) -> int:
    \\    match s:
    \\        case Shape.circle(r):
    \\            return r
    \\        case Shape.square(w):
    \\            return w + 1
    \\        case Shape.unit:
    \\            return 0
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    out.print(pick(Shape.circle(3)))
    \\    match go(3):
    \\        case Ok(v):
    \\            out.print(v)
    \\        case Err(e):
    \\            out.print(e)
    \\    return 0
    \\
;

// spec: NEW-CORE-UNION-2
test "a union is built with union_make, matched on its tag and read through union_payload, enums and Result included" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), unions);
    try std.testing.expect(contains(text, "union_make union{i64, i64, void} tag0 3:i64"));
    try std.testing.expect(contains(text, "union_payload i64 tag1 param0"));
    try std.testing.expect(contains(text, "union_make union{i64, str} tag0"));
}

// spec: NEW-CORE-TRY-1
test "a failing Err starts an error trace and a ? that propagates one appends its site before it returns the converted failure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), unions);
    // `fail` builds the Err (origin); `go` tests the tag, appends and returns on the error arm.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text, "err_trace origin"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text, "err_trace append"));
    try std.testing.expect(contains(text, "cmp.eq bool %2, 1:u32"));
}

const element_writes =
    \\record Cell:
    \\    code: int
    \\    flag: bool
    \\
    \\
    \\def set_one(cells: list[Cell], v: int) -> int:
    \\    copy = cells
    \\    copy[1].code = v
    \\    return copy[1].code
    \\
    \\
    \\def pop_last(xs: list[int]) -> int:
    \\    copy = xs
    \\    last = copy.pop()
    \\    return last + len(copy)
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    out.print(set_one([Cell(code=1, flag=True), Cell(code=2, flag=False)], 5), pop_last([1, 2, 3]))
    \\    return 0
    \\
;

// spec: NEW-CORE-LIST-2
test "an element write is a list_set of the rebuilt element and a pop reads the last element before list_pop drops it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), element_writes);
    try std.testing.expect(contains(text, "list_set.exact list[record{i64, bool}]"));
    try std.testing.expect(contains(text, "record_set record{i64, bool}"));
    // The popped element is read at index `len - 1` (wrapping), then the list loses its last element.
    try std.testing.expect(contains(text, "%3 = sub u64 %1, 1:u64"));
    try std.testing.expect(contains(text, "%4 = list_get.exact i64 param0, %3"));
    try std.testing.expect(contains(text, "list_pop.exact list[i64]"));
}

const receivers =
    \\record Hold:
    \\    items: list[int]
    \\    n: int
    \\
    \\
    \\def hold(h0: Hold, v: int) -> int:
    \\    h = h0
    \\    h.items.append(v)
    \\    return len(h.items)
    \\
    \\
    \\def fill(items: mut list[int], n: int) -> int:
    \\    for i in range(n):
    \\        items.append(i)
    \\    return len(items)
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    h = Hold(items=[], n=0)
    \\    xs: list[int] = []
    \\    out.print(hold(h, 4), fill(mut xs, 3), len(xs))
    \\    return 0
    \\
;

// spec: NEW-CORE-PLACE-1
test "a write through a hidden receiver stores the new list back into the record it came from" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), receivers);
    // `h.items.append(v)`: read the field, push (onto a copy: the parameter's list is shared), put it back.
    try std.testing.expect(contains(text, "record_get list[i64] param0, field0"));
    try std.testing.expect(contains(text, "list_push list[i64]"));
    try std.testing.expect(contains(text, "record_set record{list[i64], i64} param0, field0"));
}

// spec-case: NEW-CORE-MUT-1
test "a function with a mut parameter and a result returns a record of both and the caller stores each back" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), receivers);
    try std.testing.expect(contains(text, "fn fill(list[i64], i64) -> record{i64, list[i64]}"));
    try std.testing.expect(contains(text, "call record{i64, list[i64]} fill("));
    // The caller takes the result with record_get field 0 and writes field 1 into `xs`.
    try std.testing.expect(contains(text, "record_get i64 %"));
    try std.testing.expect(contains(text, "record_get list[i64] %"));
}

const recursive =
    \\union Expr:
    \\    num(value: int),
    \\    add(left: Expr, right: Expr)
    \\
    \\
    \\def evaluate(e: Expr) -> int:
    \\    match e:
    \\        case Expr.num(v):
    \\            return v
    \\        case Expr.add(l, r):
    \\            return evaluate(l) + evaluate(r)
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    out.print(evaluate(Expr.add(Expr.num(1), Expr.num(2))))
    \\    return 0
    \\
;

// spec: NEW-CORE-BOX-1
test "a recursive union stores the payload that closes the cycle in a box and reads it back out" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), recursive);
    try std.testing.expect(contains(text, "box_make box[#"));
    try std.testing.expect(contains(text, "box_get record{union{"));
}

const array_field =
    \\record Grid:
    \\    cells: [4]int
    \\    label: str
    \\
    \\
    \\def use(a: Grid, b: Grid) -> int:
    \\    return len(a.label) + len(b.label)
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    out.print(use(Grid(cells=[1, 2, 3, 4], label="a"), Grid(cells=[1, 2, 3, 4], label="b")))
    \\    return 0
    \\
;

// spec-case: NEW-CORE-IR-2
test "a record holding an unsupported type is refused with its reason, every time it is used" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: build.Refusal = .{};
    // A type that failed to map stays unmapped: the second use is refused for the same reason.
    try std.testing.expectError(error.Unsupported, support.buildSource(arena.allocator(), array_field, &refusal));
    try std.testing.expectEqualStrings("fixed array type", refusal.reason);
}

const projections =
    \\record Item:
    \\    code: int
    \\    bias: int
    \\
    \\
    \\union Value:
    \\    integer: int,
    \\    pair: Item
    \\
    \\
    \\def read_code(items: list[Item], i: int) -> int:
    \\    return items[i].code + items[i].bias
    \\
    \\
    \\def peek(vs: list[Value], i: int) -> int:
    \\    match vs[i]:
    \\        case Value.integer(n):
    \\            return n
    \\        case Value.pair(p):
    \\            return p.code * 10 + p.bias
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    out.print(read_code([Item(code=1, bias=2)], 0), peek([Value.integer(5)], 0))
    \\    return 0
    \\
;

// spec: NEW-CORE-FUSE-1
test "a field read of a list element and a match on a union element read the parts they use, not the whole element" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), projections);
    try std.testing.expect(!contains(text, "list_get.exact record"));
    try std.testing.expect(!contains(text, "list_get.exact union"));
    // `items[i].code`: one field read; `match vs[i]`: the tag with the bounds check, then the payload without one.
    try std.testing.expect(contains(text, "list_get_field.exact i64 param0, %9, path 0"));
    try std.testing.expect(contains(text, "list_get_field.exact u32 param0, %9, path 0"));
    try std.testing.expect(contains(text, "list_get_field i64 param0, %9, path 1"));
    // The payload record's fields are paths of two steps: case 1's payload (step 2), then the field.
    try std.testing.expect(contains(text, "list_get_field i64 param0, %9, path 2.0"));
    try std.testing.expect(contains(text, "list_get_field i64 param0, %9, path 2.1"));
}

const append_to_element =
    \\def grow(rows: list[list[int]], i: int, v: int) -> int:
    \\    copy = rows
    \\    copy[i].append(v)
    \\    return len(copy[i])
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    out.print(grow([[1], [2, 3]], 1, 9))
    \\    return 0
    \\
;

const text_equality =
    \\def same(a: str, b: str) -> bool:
    \\    return a == b
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    out.print(same("a", "b"))
    \\    return 0
    \\
;

const callback_in_index =
    \\record Frame:
    \\    code: list[int]
    \\    ip: int
    \\
    \\
    \\def replace(frame: mut Frame) -> int:
    \\    frame.code = [17, 19]
    \\    return 0
    \\
    \\
    \\def selected(frame: mut Frame) -> int:
    \\    return frame.code[replace(mut frame)]
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    frame = Frame([7, 11], 0)
    \\    out.print(selected(mut frame))
    \\    return 0
    \\
;

// spec-case: NEW-CORE-PLACE-1
test "an append to a list element is a push onto the element and a list_set of it; a str comparison and a read through a place a callback rewrites are refused" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), append_to_element);
    // `copy[i].append(v)`: read the element, push onto it, store it back with `list_set`: the append is not dropped.
    try std.testing.expect(contains(text, "list_push list[i64]"));
    try std.testing.expect(contains(text, "list_set.exact list[list[i64]]"));
    var refusal: build.Refusal = .{};
    try std.testing.expectError(error.Unsupported, support.buildSource(arena.allocator(), text_equality, &refusal));
    try std.testing.expectEqualStrings("str equality", refusal.reason);
    try std.testing.expectError(error.Unsupported, support.buildSource(arena.allocator(), callback_in_index, &refusal));
    try std.testing.expectEqualStrings("write to a receiver's place while its arguments are evaluated", refusal.reason);
}

const recursive_equality =
    \\union Expr:
    \\    num(value: int),
    \\    add(left: Expr, right: Expr)
    \\
    \\
    \\def same(a: Expr, b: Expr) -> bool:
    \\    return a == b
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    out.print(same(Expr.num(1), Expr.num(1)))
    \\    return 0
    \\
;

// spec-case: NEW-CORE-EQ-1
test "equality of a recursive value is refused instead of expanding forever" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: build.Refusal = .{};
    try std.testing.expectError(error.Unsupported, support.buildSource(arena.allocator(), recursive_equality, &refusal));
    try std.testing.expectEqualStrings("equality of a recursive value", refusal.reason);
}

const converting =
    \\union Failure:
    \\    text: str,
    \\    code: int
    \\
    \\
    \\def parse(x: int) -> Result[int, str]:
    \\    if x < 0:
    \\        return Err("negative")
    \\    return Ok(x)
    \\
    \\
    \\def forward(x: int) -> Result[int, str]:
    \\    r = parse(x)
    \\    return r
    \\
    \\
    \\def same(x: int) -> Result[int, str]:
    \\    v = parse(x)?
    \\    return Ok(v)
    \\
    \\
    \\def lift(x: int) -> Result[int, Failure]:
    \\    v = parse(x)?
    \\    return Ok(v)
    \\
    \\
    \\
    \\def good(r: Result[int, str]) -> bool:
    \\    match r:
    \\        case Ok(_):
    \\            return True
    \\        case Err(_):
    \\            return False
    \\
    \\
    \\def good_failure(r: Result[int, Failure]) -> bool:
    \\    match r:
    \\        case Ok(_):
    \\            return True
    \\        case Err(_):
    \\            return False
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    out.print(good(forward(1)), good(same(1)), good_failure(lift(1)))
    \\    return 0
    \\
;

// spec-case: NEW-CORE-TRY-1
test "a ? that passes the error on appends its site, one that wraps it into a case of the caller's union is converted and names Union.case, a return of a variable Err is returned" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), converting);
    const same = text[std.mem.indexOf(u8, text, "fn same").?..std.mem.indexOf(u8, text, "fn lift").?];
    try std.testing.expect(contains(same, "err_trace append"));
    const lift = text[std.mem.indexOf(u8, text, "fn lift").?..];
    try std.testing.expect(contains(lift, "err_trace converted"));
    // `return r` of a variable: the tag is tested and `returned` recorded on the Err arm.
    const forward = text[std.mem.indexOf(u8, text, "fn forward").?..std.mem.indexOf(u8, text, "fn same").?];
    try std.testing.expect(contains(forward, "err_trace returned"));
}

/// A program in which a late-declared callee takes an element read as an argument: the
/// call's `a` operand is a function index larger than the calling function's instruction table.
fn lateCallee(arena: std.mem.Allocator) ![]const u8 {
    var source: std.ArrayList(u8) = .empty;
    try source.appendSlice(arena, "record Item:\n    a: int\n    b: int\n\n\n");
    for (0..16) |i| try source.print(arena, "def g{d}() -> int:\n    return {d}\n\n\n", .{ i, i });
    try source.appendSlice(arena, "def take(item: Item) -> int:\n    return item.a + item.b\n\n\n");
    try source.appendSlice(arena, "def pick(xs: list[Item]) -> int:\n    return take(xs[0])\n\n\n");
    try source.appendSlice(arena, "def main(out: Stream) -> int:\n    xs = [Item(a=1, b=2)]\n    out.print(g0() + g1() + g2() + g3() + pick(xs))\n    return 0\n");
    return source.items;
}

// spec-case: NEW-CORE-FUSE-1
test "an element read passed to a call is not a projection: fusion never treats a call's callee index as a value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), try lateCallee(arena.allocator()));
    const pick = text[std.mem.indexOf(u8, text, "fn pick").?..std.mem.indexOf(u8, text, "fn take").?];
    // The whole element is passed, so it stays a `list_get`, whose use is the call.
    try std.testing.expect(contains(pick, "list_get"));
    try std.testing.expect(!contains(pick, "list_get_field"));
}

const conditional_rebind =
    \\def conditional(items: mut list[int], other: list[int], use_other: bool) -> list[int]:
    \\    if use_other:
    \\        items = other
    \\    items[0] = 7
    \\    return items
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    original = [1]
    \\    out.print(len(conditional(mut original, [2], False)))
    \\    return 0
    \\
;

const loop_rebind =
    \\def loop_rebind(items: mut list[int], other: list[int]) -> int:
    \\    items.append(0)
    \\    for i in range(2):
    \\        items = other
    \\    return len(items)
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    original = [1]
    \\    out.print(loop_rebind(mut original, [2]))
    \\    return 0
    \\
;

// spec-case: NEW-CORE-MUT-2
test "a rebinding of a mut list parameter on only some of the paths that join, or inside a loop, is refused" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: build.Refusal = .{};
    try std.testing.expectError(error.Unsupported, support.buildSource(arena.allocator(), conditional_rebind, &refusal));
    try std.testing.expectEqualStrings("conditional rebinding of a mut collection parameter", refusal.reason);
    try std.testing.expectError(error.Unsupported, support.buildSource(arena.allocator(), loop_rebind, &refusal));
    try std.testing.expectEqualStrings("rebinding of a mut collection parameter in a loop", refusal.reason);
}
