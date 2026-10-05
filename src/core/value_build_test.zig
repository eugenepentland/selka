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

const managed_write =
    \\record Item:
    \\    payload: list[int]
    \\
    \\
    \\def touch(xs: list[Item]) -> int:
    \\    copy = xs
    \\    copy[0] = Item(payload=[1])
    \\    return len(copy)
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    out.print(touch([Item(payload=[2])]))
    \\    return 0
    \\
;

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
test "an element write of a managed element and a record holding an unsupported type are refused with their reason, every time" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: build.Refusal = .{};
    try std.testing.expectError(error.Unsupported, support.buildSource(arena.allocator(), managed_write, &refusal));
    try std.testing.expectEqualStrings("element write of a managed element (needs ownership)", refusal.reason);
    // A type that failed to map stays unmapped: the second use is refused for the same reason.
    try std.testing.expectError(error.Unsupported, support.buildSource(arena.allocator(), array_field, &refusal));
    try std.testing.expectEqualStrings("fixed array type", refusal.reason);
}
