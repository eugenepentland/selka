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
    \\func shift(input: Line, dx: int) -> int:
    \\    mut line = input
    \\    line.to_point.x = line.to_point.x + dx
    \\    return line.to_point.x - line.from_point.x
    \\
    \\
    \\func main(out: Stream) -> int:
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
    \\enum Shape:
    \\    circle(value: int)
    \\    square(value: int)
    \\    unit
    \\
    \\
    \\func failure(x: int) -> Result[int, str]:
    \\    if x < 0:
    \\        return Err("neg")
    \\    return Ok(x)
    \\
    \\
    \\func go(x: int) -> Result[int, str]:
    \\    mut v = try failure(x)
    \\    return Ok(v + 1)
    \\
    \\
    \\func pick(s: Shape) -> int:
    \\    match s:
    \\        case Shape.circle(value=r):
    \\            return r
    \\        case Shape.square(value=w):
    \\            return w + 1
    \\        case Shape.unit:
    \\            return 0
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(pick(Shape.circle(value=3)))
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
    try std.testing.expect(contains(text, "union_make union{record{i64}, record{i64}, void} tag0"));
    try std.testing.expect(contains(text, "union_payload record{i64} tag1 param0"));
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
    \\func set_one(cells: Cell[], v: int) -> int:
    \\    mut copy = cells
    \\    copy[1].code = v
    \\    return copy[1].code
    \\
    \\
    \\func pop_last(xs: int[]) -> int:
    \\    mut copy = xs
    \\    mut last = copy.pop()
    \\    return last + len(copy)
    \\
    \\
    \\func main(out: Stream) -> int:
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
    \\    items: int[]
    \\    n: int
    \\
    \\
    \\func hold(h0: Hold, v: int) -> int:
    \\    mut h = h0
    \\    h.items.append(v)
    \\    return len(h.items)
    \\
    \\
    \\func fill(mut items: int[], n: int) -> int:
    \\    for i in range(n):
    \\        items.append(i)
    \\    return len(items)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut h = Hold(items=[], n=0)
    \\    mut xs: int[] = []
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
    \\enum Expr:
    \\    num(value: int)
    \\    add(left: Expr, right: Expr)
    \\
    \\
    \\func evaluate(e: Expr) -> int:
    \\    match e:
    \\        case Expr.num(value=v):
    \\            return v
    \\        case Expr.add(left=l, right=r):
    \\            return evaluate(l) + evaluate(r)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(evaluate(Expr.add(left=Expr.num(value=1), right=Expr.num(value=2))))
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

const capability_array_field =
    \\record Grid:
    \\    ports: FixedArray[Stream, 2]
    \\    label: str
    \\
    \\
    \\func use(a: Grid, b: Grid) -> int:
    \\    return len(a.label) + len(b.label)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(use(Grid(ports=FixedArray[stream_cap, 2]([out, out]), label="a"), Grid(ports=FixedArray[stream_cap, 2]([out, out]), label="b")))
    \\    return 0
    \\
;

const capability_field =
    \\record Grid:
    \\    port: Stream
    \\    label: str
    \\
    \\
    \\func use(a: Grid, b: Grid) -> int:
    \\    return len(a.label) + len(b.label)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(use(Grid(port=out, label="a"), Grid(port=out, label="b")))
    \\    return 0
    \\
;

const rendered_capability =
    \\record Grid:
    \\    port: Stream
    \\    label: str
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(Grid(port=out, label="a"))
    \\    return 0
    \\
;

// spec: NEW-CORE-IR-2
test "a construct the core does not support is refused with its reason and source position" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: build.Refusal = .{};
    // Printing a record that holds a capability token: the old core failed at run time.
    try std.testing.expectError(error.Unsupported, support.buildSource(arena.allocator(), rendered_capability, &refusal));
    try std.testing.expectEqualStrings("rendering a non-value source type", refusal.reason);
    try std.testing.expectEqual(@as(u32, @intCast(std.mem.indexOf(u8, rendered_capability, "out.print").?)), refusal.span);
}

// spec-case: NEW-CORE-S5-CAP-COLLECTIONS-1
test "a record holding a fixed array of capability tokens builds: the array is a value of uncounted tokens" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: build.Refusal = .{};
    const text = try support.irText(arena.allocator(), capability_array_field);
    try std.testing.expect(contains(text, "record_make record{[2]cap, str}"));
    _ = try support.buildSource(arena.allocator(), capability_array_field, &refusal);
    try std.testing.expectEqualStrings("", refusal.reason);
}

// spec: NEW-CORE-S4-CAP-FIELD-1
test "a record holding a capability token builds: the token is a plain i64 field" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: build.Refusal = .{};
    _ = try support.buildSource(arena.allocator(), capability_field, &refusal);
    try std.testing.expectEqualStrings("", refusal.reason);
}

const projections =
    \\record Item:
    \\    code: int
    \\    bias: int
    \\
    \\
    \\enum Value:
    \\    integer(value: int)
    \\    pair(value: Item)
    \\
    \\
    \\func read_code(items: Item[], i: int) -> int:
    \\    return items[i].code + items[i].bias
    \\
    \\
    \\func peek(vs: Value[], i: int) -> int:
    \\    match vs[i]:
    \\        case Value.integer(value=n):
    \\            return n
    \\        case Value.pair(value=p):
    \\            return p.code * 10 + p.bias
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(read_code([Item(code=1, bias=2)], 0), peek([Value.integer(value=5)], 0))
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
    // Named payload field `value` adds a record step before the Item's own field.
    try std.testing.expect(contains(text, "list_get_field i64 param0, %9, path 2.0.0"));
    try std.testing.expect(contains(text, "list_get_field i64 param0, %9, path 2.0.1"));
}

const append_to_element =
    \\func grow(rows: int[][], i: int, v: int) -> int:
    \\    mut copy = rows
    \\    copy[i].append(v)
    \\    return len(copy[i])
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(grow([[1], [2, 3]], 1, 9))
    \\    return 0
    \\
;

const text_equality =
    \\func same(a: str, b: str) -> bool:
    \\    return a == b
    \\
    \\
    \\func differ(a: str, b: str) -> bool:
    \\    return a != b
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(same("a", "b"), differ("a", "b"))
    \\    return 0
    \\
;

const text_ordering =
    \\func before(a: str, b: str) -> bool:
    \\    return a < b
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(before("a", "b"))
    \\    return 0
    \\
;

const callback_in_index =
    \\record Frame:
    \\    code: int[]
    \\    ip: int
    \\
    \\
    \\func replace(mut frame: Frame) -> int:
    \\    frame.code = [17, 19]
    \\    return 0
    \\
    \\
    \\func selected(mut frame: Frame) -> int:
    \\    return frame.code[replace(mut frame)]
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut frame = Frame(code=[7, 11], ip=0)
    \\    out.print(selected(mut frame))
    \\    return 0
    \\
;

// spec-case: NEW-CORE-PLACE-1
test "nested append and text ordering build and a callback index reads its captured receiver" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), append_to_element);
    // `copy[i].append(v)`: read the element, push onto it, store it back with `list_set`: the append is not dropped.
    try std.testing.expect(contains(text, "list_push list[i64]"));
    try std.testing.expect(contains(text, "list_set.exact list[list[i64]]"));
    var refusal: build.Refusal = .{};
    _ = try support.buildSource(arena.allocator(), text_ordering, &refusal);
    try std.testing.expectEqualStrings("", refusal.reason);
    // A read through a receiver a callback rewrites the place of sees the receiver as captured.
    const selected = try support.irText(arena.allocator(), callback_in_index);
    try std.testing.expect(contains(selected, "list_get.exact i64 %1"));
}

const recursive_equality =
    \\enum Expr:
    \\    num(value: int)
    \\    add(left: Expr, right: Expr)
    \\
    \\
    \\func same(a: Expr, b: Expr) -> bool:
    \\    return a == b
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(same(Expr.num(value=1), Expr.num(value=1)))
    \\    return 0
    \\
;

// spec-case: NEW-CORE-EQ-1
test "equality of a recursive value builds without recursively expanding its type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: build.Refusal = .{};
    _ = try support.buildSource(arena.allocator(), recursive_equality, &refusal);
    try std.testing.expectEqualStrings("", refusal.reason);
}

const converting =
    \\enum Failure:
    \\    text(value: str)
    \\    code(value: int)
    \\
    \\
    \\func parse(x: int) -> Result[int, str]:
    \\    if x < 0:
    \\        return Err("negative")
    \\    return Ok(x)
    \\
    \\
    \\func forward(x: int) -> Result[int, str]:
    \\    mut r = parse(x)
    \\    return r
    \\
    \\
    \\func same(x: int) -> Result[int, str]:
    \\    mut v = try parse(x)
    \\    return Ok(v)
    \\
    \\
    \\func lift(x: int) -> Result[int, Failure]:
    \\    mut v = try parse(x)
    \\    return Ok(v)
    \\
    \\
    \\
    \\func good(r: Result[int, str]) -> bool:
    \\    match r:
    \\        case Ok(_):
    \\            return True
    \\        case Err(_):
    \\            return False
    \\
    \\
    \\func good_failure(r: Result[int, Failure]) -> bool:
    \\    match r:
    \\        case Ok(_):
    \\            return True
    \\        case Err(_):
    \\            return False
    \\
    \\
    \\func main(out: Stream) -> int:
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
    for (0..16) |i| try source.print(arena, "func g{d}() -> int:\n    return {d}\n\n\n", .{ i, i });
    try source.appendSlice(arena, "func take(item: Item) -> int:\n    return item.a + item.b\n\n\n");
    try source.appendSlice(arena, "func pick(xs: Item[]) -> int:\n    return take(xs[0])\n\n\n");
    try source.appendSlice(arena, "func main(out: Stream) -> int:\n    mut xs = [Item(a=1, b=2)]\n    out.print(g0() + g1() + g2() + g3() + pick(xs))\n    return 0\n");
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
    \\func conditional(mut items: int[], other: int[], use_other: bool) -> int[]:
    \\    if use_other:
    \\        items = other
    \\    items[0] = 7
    \\    return items
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut original = [1]
    \\    out.print(len(conditional(mut original, [2], False)))
    \\    return 0
    \\
;

const loop_rebind =
    \\func loop_rebind(mut items: int[], other: int[]) -> int:
    \\    items.append(0)
    \\    for i in range(2):
    \\        items = other
    \\    return len(items)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut original = [1]
    \\    out.print(loop_rebind(mut original, [2]))
    \\    return 0
    \\
;

// spec-case: NEW-CORE-MUT-2
test "a mut collection rebinding through conditional paths and loops builds final caller writeback" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: build.Refusal = .{};
    _ = try support.buildSource(arena.allocator(), conditional_rebind, &refusal);
    _ = try support.buildSource(arena.allocator(), loop_rebind, &refusal);
}

// spec: NEW-CORE-STR-1
test "str == and != call the authorized runtime byte comparison declared once" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), text_equality);
    const same = text[std.mem.indexOf(u8, text, "fn same").?..std.mem.indexOf(u8, text, "fn differ").?];
    try std.testing.expect(contains(same, "call bool myl_core_str_eq(param0, param1)"));
    const differ = text[std.mem.indexOf(u8, text, "fn differ").?..std.mem.indexOf(u8, text, "fn myl_core_str_eq").?];
    try std.testing.expect(contains(differ, "call bool myl_core_str_eq(param0, param1)"));
    try std.testing.expect(contains(differ, "not bool"));
    // One declaration serves both.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text, "fn myl_core_str_eq(str, str) -> bool runtime"));
}

const arena_scopes =
    \\func main(out: Stream) -> int:
    \\    mut kept: int[] = []
    \\    mut built = [1, 2, 3]
    \\    kept = built
    \\    out.print(len(kept))
    \\    return 0
    \\
;

// spec: NEW-CORE-ARENA-1
test "migrated arena values lower without region operations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), arena_scopes);
    try std.testing.expect(contains(text, "list_push list[i64]"));
    try std.testing.expect(contains(text, "list_len"));
    try std.testing.expect(!contains(text, "call"));
}

const assertions =
    \\func clamp(x: int) -> int:
    \\    assert x >= 0, "negative"
    \\    return x
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(clamp(3))
    \\    return 0
    \\
;

// spec: NEW-CORE-ASSERT-1
test "an assert is a branch on its condition to a block that ends in a trap carrying the message" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), assertions);
    const clamp = text[std.mem.indexOf(u8, text, "fn clamp").?..];
    try std.testing.expect(contains(clamp, "branch"));
    try std.testing.expect(contains(clamp, "unreachable"));
}

const stale_write =
    \\func poke(mut xs: int[]) -> int:
    \\    xs[0] = 50
    \\    return 1
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut a = [1, 2, 3]
    \\    a[poke(mut a)] = 9
    \\    out.print(len(a))
    \\    return 0
    \\
;

// spec-case: NEW-CORE-PLACE-3
test "the checker rejects a receiver whose place an evaluated mut argument overlaps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: build.Refusal = .{};
    try std.testing.expectError(error.SourceError, support.buildSource(arena.allocator(), stale_write, &refusal));
}

const changed_mut_entry =
    \\func replace_entry(mut root: int[][]) -> int[][]:
    \\    root[0] = [21]
    \\    return root
    \\
    \\func rebind_selected(mut target: int[], source: int[][]) -> int:
    \\    mut before = target[0]
    \\    target = [13]
    \\    return before * 10000 + target[0] * 100 + source[0][0]
    \\
    \\func main() -> int:
    \\    mut items = [[7]]
    \\    return rebind_selected(mut items[0], replace_entry(mut items))
;

const changed_mut_field =
    \\record Box:
    \\    items: int[]
    \\
    \\func replace_field(mut box: Box) -> Box:
    \\    box.items = [21]
    \\    return box
    \\
    \\func rebind_selected(mut target: int[], source: Box) -> int:
    \\    mut before = target[0]
    \\    target = [13]
    \\    return before * 10000 + target[0] * 100 + source.items[0]
    \\
    \\func main() -> int:
    \\    mut box = Box(items=[7])
    \\    return rebind_selected(mut box.items, replace_field(mut box))
;

// spec-case: NEW-CORE-MUT-1
test "interior mut arguments capture the leaf and guard publishing after ancestor replacement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: build.Refusal = .{};
    _ = try support.buildSource(arena.allocator(), changed_mut_entry, &refusal);
    try std.testing.expectEqualStrings("", refusal.reason);
    _ = try support.buildSource(arena.allocator(), changed_mut_field, &refusal);
    try std.testing.expectEqualStrings("", refusal.reason);
}

const changed_mut_root =
    \\func replace_root(mut items: int[]) -> int[]:
    \\    items = [21]
    \\    return items
    \\
    \\func append_current(mut items: int[], source: int[]) -> int:
    \\    items.append(13)
    \\    return len(items) + source[0]
    \\
    \\func main() -> int:
    \\    mut items = [7]
    \\    return append_current(mut items, replace_root(mut items))
;

// spec-case: NEW-CORE-MUT-1
test "whole mut arguments reread the current caller root after later rebinding" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: build.Refusal = .{};
    _ = try support.buildSource(arena.allocator(), changed_mut_root, &refusal);
    try std.testing.expectEqualStrings("", refusal.reason);
}

const stable_mut_entry =
    \\func rebind_selected(mut target: int[], source: int[][]) -> int:
    \\    mut before = target[0]
    \\    target = [13]
    \\    return before + target[0] + source[0][0]
    \\
    \\func main() -> int:
    \\    mut items = [[7]]
    \\    return rebind_selected(mut items[0], items)
;

// spec-case: NEW-CORE-MUT-1
test "interior mut arguments with later readonly snapshots still build caller writeback" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), stable_mut_entry);
    try std.testing.expect(contains(text, "call record{i64, list[i64]} rebind_selected("));
    try std.testing.expect(contains(text, "list_set.exact list[list[i64]]"));
}
