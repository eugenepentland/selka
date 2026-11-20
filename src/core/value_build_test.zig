//! S1 lane V: the Core IR the builder makes for records, unions, `?`, element writes,
//! `pop`, writes through hidden receivers and `mut` parameters, and what it refuses.
const std = @import("std");
const transition = @import("ownership_transition_test_support.zig");
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
    \\    print(out, shift(Line(from_point=Point(x=1, y=2), to_point=Point(x=5, y=6), on=True), 3))
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
    \\func failure(x: int) -> int fails str:
    \\    if x < 0:
    \\        fail "neg"
    \\    return x
    \\
    \\
    \\func go(x: int) -> int fails str:
    \\    mut v = try failure(x)
    \\    return v + 1
    \\
    \\
    \\func pick(s: Shape) -> int:
    \\    match s:
    \\        case circle(value=r):
    \\            return r
    \\        case square(value=w):
    \\            return w + 1
    \\        case unit:
    \\            return 0
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, pick(Shape.circle(value=3)))
    \\    match go(3):
    \\        case Ok(v):
    \\            print(out, v)
    \\        case Err(e):
    \\            print(out, e)
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
    \\import lists
    \\
    \\record Cell:
    \\    code: int
    \\    flag: bool
    \\
    \\
    \\func set_one(cells: Cell[], v: int) -> int:
    \\    mut copy = copy(cells)
    \\    copy[1].code = v
    \\    return copy[1].code
    \\
    \\
    \\func pop_last(xs: int[]) -> int:
    \\    mut copy = copy(xs)
    \\    mut last = lists.pop(mut copy)
    \\    return last + len(copy)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, set_one([Cell(code=1, flag=True), Cell(code=2, flag=False)], 5), pop_last([1, 2, 3]))
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
    // The parameter is a list view and its owner (C9 lists), so the copy and its uses are numbered after the owner.
    try std.testing.expect(contains(text, "%2 = list_copy list[i64] param0\n  %3 = list_len u64 %2"));
    try std.testing.expect(contains(text, "%5 = sub u64 %3, 1:u64\n  %6 = list_get.exact i64 %2, %5\n  %7 = list_pop.exact list[i64] %2"));
}

const receivers =
    \\record Hold:
    \\    items: int[]
    \\    n: int
    \\
    \\
    \\func hold(h0: Hold, v: int) -> int:
    \\    mut h = copy(h0)
    \\    append(mut h.items, v)
    \\    return len(h.items)
    \\
    \\
    \\func fill(mut items: int[], n: int) -> int:
    \\    for i in range(n):
    \\        append(mut items, i)
    \\    return len(items)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut h = Hold(items=[], n=0)
    \\    mut xs: int[] = []
    \\    print(out, hold(h, 4), fill(mut xs, 3), len(xs))
    \\    return 0
    \\
;

// spec: NEW-CORE-PLACE-1
test "a write through a hidden receiver stores the new list back into the record it came from" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), receivers);
    // `h.items.append(v)`: copy the input field, reconstruct the owner, then write its updated list back.
    try std.testing.expect(contains(text, "record_get list[i64] param0, field0"));
    try std.testing.expect(contains(text, "list_push list[i64]"));
    try std.testing.expect(contains(text, "%3 = list_copy list[i64] %2"));
    try std.testing.expect(contains(text, "%5 = record_make record{list[i64], i64} %3, %4"));
    try std.testing.expect(contains(text, "%8 = list_push list[i64] %7, param1\n  %9 = record_set record{list[i64], i64} %5, field0, %8"));
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
    \\        case num(value=v):
    \\            return v
    \\        case add(left=l, right=r):
    \\            return evaluate(l) + evaluate(r)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, evaluate(Expr.add(left=Expr.num(value=1), right=Expr.num(value=2))))
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
    \\    return strings.char_count(a.label) + strings.char_count(b.label)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, use(Grid(ports=FixedArray[stream_cap, 2]([out, out]), label="a"), Grid(ports=FixedArray[stream_cap, 2]([out, out]), label="b")))
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
    \\    return strings.char_count(a.label) + strings.char_count(b.label)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, use(Grid(port=out, label="a"), Grid(port=out, label="b")))
    \\    return 0
    \\
;

/// A shape `check` accepts and Core cannot place: a plain `bytes` parameter given to a task (`docs/ownership-rules.md`, Z3). It stands
/// where the printing of a record that holds a capability stood until PRINT-1, which `check` refuses now.
const task_bytes_parameter =
    \\import parallel
    \\
    \\
    \\func measure(value: bytes) -> int:
    \\    return len(value)
    \\
    \\
    \\func go(value: bytes) -> int:
    \\    with parallel.group() as group:
    \\        const job = group.submit(measure, value[0:2])
    \\        return job.result()
    \\
    \\
    \\func main() -> int:
    \\    return go(b"abc")
    \\
;

// spec: NEW-CORE-IR-2
test "a construct the core does not support is refused with its reason and source position" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: build.Refusal = .{ .rule = .Z3 };
    try std.testing.expectError(error.Unsupported, support.buildSource(arena.allocator(), task_bytes_parameter, &refusal));
    try std.testing.expectEqualStrings("a slice of bytes given to a task", refusal.reason);
    try std.testing.expectEqual(@as(u32, @intCast(std.mem.indexOf(u8, task_bytes_parameter, "group.submit").?)), refusal.span);
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
    \\        case integer(value=n):
    \\            return n
    \\        case pair(value=p):
    \\            return p.code * 10 + p.bias
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, read_code([Item(code=1, bias=2)], 0), peek([Value.integer(value=5)], 0))
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
    // The raw i64 index is param1; no hidden negative-index normalization SSA remains.
    // The first projection checks bounds; payload projections reuse that checked index.
    try std.testing.expect(contains(text, "list_get_field.exact i64 param0, param1, path 0"));
    try std.testing.expect(contains(text, "list_get_field.exact u32 param0, param1, path 0"));
    try std.testing.expect(contains(text, "list_get_field i64 param0, param1, path 1"));
    // Named payload field `value` adds a record step before the Item's own field.
    try std.testing.expect(contains(text, "list_get_field i64 param0, param1, path 2.0.0"));
    try std.testing.expect(contains(text, "list_get_field i64 param0, param1, path 2.0.1"));
}

const append_to_element =
    \\func grow(rows: int[][], i: int, v: int) -> int:
    \\    mut copy = copy(rows)
    \\    append(mut copy[i], v)
    \\    return len(copy[i])
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, grow([[1], [2, 3]], 1, 9))
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
    \\    print(out, same("a", "b"), differ("a", "b"))
    \\    return 0
    \\
;

const text_ordering =
    \\func before(a: str, b: str) -> bool:
    \\    return a < b
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, before("a", "b"))
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
    \\    const receiver = copy(frame.code)
    \\    return receiver[replace(mut frame)]
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut frame = Frame(code=[7, 11], ip=0)
    \\    print(out, selected(mut frame))
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
    try std.testing.expect(contains(selected, "%2 = list_copy list[i64] %1\n  %3 = call record{i64, record{list[i64], i64}} replace(param0)"));
    try std.testing.expect(contains(selected, "%4 = record_get i64 %3, field0"));
    try std.testing.expect(contains(selected, "%6 = list_get.exact i64 %2, %4"));
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
    \\    print(out, same(Expr.num(value=1), Expr.num(value=1)))
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
    \\func parse(x: int) -> int fails str:
    \\    if x < 0:
    \\        fail "negative"
    \\    return x
    \\
    \\
    \\func forward(x: int) -> int fails str:
    \\    mut r = parse(x)
    \\    return try own r
    \\
    \\
    \\func same(x: int) -> int fails str:
    \\    mut v = try parse(x)
    \\    return v
    \\
    \\
    \\func lift(x: int) -> int fails Failure:
    \\    mut v = try parse(x)
    \\    return v
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
    \\    print(out, good(forward(1)), good(same(1)), good_failure(lift(1)))
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
    // `return try r` of a variable appends the propagation site, as `same` does.
    const forward = text[std.mem.indexOf(u8, text, "fn forward").?..std.mem.indexOf(u8, text, "fn same").?];
    try std.testing.expect(contains(forward, "err_trace append"));
}

/// A program in which a late-declared callee takes an element read as an argument: the
/// call's `a` operand is a function index larger than the calling function's instruction table.
fn lateCallee(arena: std.mem.Allocator) ![]const u8 {
    var source: std.ArrayList(u8) = .empty;
    try source.appendSlice(arena, "record Item:\n    a: int\n    b: int\n\n\n");
    for (0..16) |i| try source.print(arena, "func g{d}() -> int:\n    return {d}\n\n\n", .{ i, i });
    try source.appendSlice(arena, "func my_take(item: Item) -> int:\n    return item.a + item.b\n\n\n");
    try source.appendSlice(arena, "func pick(xs: Item[]) -> int:\n    return my_take(xs[0])\n\n\n");
    try source.appendSlice(arena, "func main(out: Stream) -> int:\n    mut xs = [Item(a=1, b=2)]\n    print(out, g0() + g1() + g2() + g3() + pick(xs))\n    return 0\n");
    return source.items;
}

// spec-case: NEW-CORE-FUSE-1
test "an element read passed to a call is not a projection: fusion never treats a call's callee index as a value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), try lateCallee(arena.allocator()));
    const pick = text[std.mem.indexOf(u8, text, "fn pick").?..std.mem.indexOf(u8, text, "fn my_take").?];
    // The whole element is passed, so it stays a `list_get`, whose use is the call.
    try std.testing.expect(contains(pick, "list_get"));
    try std.testing.expect(!contains(pick, "list_get_field"));
}

const conditional_rebind =
    \\func conditional(mut items: int[], other: int[], use_other: bool) -> int[]:
    \\    if use_other:
    \\        items = copy(other)
    \\    items[0] = 7
    \\    return copy(items)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut original = [1]
    \\    print(out, len(conditional(mut original, [2], False)))
    \\    return 0
    \\
;

const loop_rebind =
    \\func loop_rebind(mut items: int[], other: int[]) -> int:
    \\    append(mut items, 0)
    \\    for i in range(2):
    \\        items = copy(other)
    \\    return len(items)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut original = [1]
    \\    print(out, loop_rebind(mut original, [2]))
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
    try std.testing.expect(contains(same, "call bool myl_core_span_eq(param0, param1)"));
    const differ = text[std.mem.indexOf(u8, text, "fn differ").?..std.mem.indexOf(u8, text, "fn myl_core_span_eq").?];
    try std.testing.expect(contains(differ, "call bool myl_core_span_eq(param0, param1)"));
    try std.testing.expect(contains(differ, "cmp.eq bool"));
    // One declaration serves both.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text, "fn myl_core_span_eq(str, str) -> bool extern"));
}

const view_needle_source =
    \\import strings
    \\
    \\func find(text: str) -> int:
    \\    const needle = text[1:3]
    \\    return strings.char_find(text, needle)
    \\func main(out: Stream) -> int:
    \\    print(out, find("abcdef"))
    \\    return 0
;

test "a view binding passed to a runtime text helper declares the helper's owned text parameter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), view_needle_source);
    // The helper keeps its `str` parameters and the needle is passed as its span (C9 S1: `myl_core_xc_search` takes the
    // receiver's owner, the receiver's span, a sentinel block for the needle, and the needle's span): no copy at the call.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text, "fn myl_core_xc_search(str, str, str, str, i64, i64, i32) -> i64 extern"));
    try std.testing.expect(!contains(text, "str_view) -> i64 extern"));
    try std.testing.expect(!contains(text, "str_from_view"));
}

const starts_source =
    \\import strings
    \\
    \\func owned_and_view(text: str) -> bool:
    \\    const piece = text[0:2]
    \\    return strings.starts_with(text, "ab") or strings.starts_with(piece, "a")
    \\func main(out: Stream) -> int:
    \\    print(out, owned_and_view("abc"))
    \\    return 0
;

test "starts_with names the span form for owned and view text, and the text form is not declared" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), starts_source);
    // One declaration serves an owned and a view argument: each text argument is one span (C9 batch 1).
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text, "fn myl_core_span_starts(str, str) -> bool extern"));
    try std.testing.expect(!contains(text, "fn myl_core_str_starts("));
}

const char_count_source =
    \\import strings
    \\
    \\func owned_and_view(text: str) -> int:
    \\    const piece = text[0:3]
    \\    return strings.char_count(text) + strings.char_count(piece)
    \\func main(out: Stream) -> int:
    \\    print(out, owned_and_view("abcdef"))
    \\    return 0
;

test "char_count of an owned text keeps the block helper, and a view is counted by its span helper" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), char_count_source);
    // A plain str parameter is a view under C9 (owner-explicit): the parameter and its slice are counted by one owner-explicit helper.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text, "fn myl_core_xc_chars(str, str) -> i64 extern"));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, text, "call i64 myl_core_xc_chars("));
}

const arena_scopes =
    \\func main(out: Stream) -> int:
    \\    mut kept: int[] = []
    \\    mut built = [1, 2, 3]
    \\    kept = own built
    \\    print(out, len(kept))
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
    \\    print(out, clamp(3))
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
    \\    print(out, len(a))
    \\    return 0
    \\
;

// spec-case: NEW-CORE-PLACE-3
test "the checker rejects a receiver whose place an evaluated mut argument overlaps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const checked = try support.checkSource(a, stale_write);
    try std.testing.expect(checked.passed);
    const ownership = @import("single_owner.zig");
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, checked.program.?, checked.src.?, &failure));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_OVERLAP", failure.code);
    try std.testing.expectEqual(@import("selka").ownership_rules.Rule.R2, failure.rule.?);
    var refusal: build.Refusal = .{};
    try std.testing.expectError(error.Unsupported, build.buildModule(a, checked.program.?, &refusal));
    try std.testing.expectEqual(@import("selka").ownership_rules.Rule.Z3, refusal.rule.?);
}

const changed_mut_entry =
    \\func replace_entry(mut root: int[][]) -> int[][] from root:
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
    \\func replace_field(mut box: Box) -> Box from box:
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

fn replacementOverlap(backing: std.mem.Allocator, source: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const checked = try support.checkSource(a, source);
    try std.testing.expect(checked.passed);
    const ownership = @import("single_owner.zig");
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, checked.program.?, checked.src.?, &failure));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_OVERLAP", failure.code);
    try std.testing.expectEqual(@import("selka").ownership_rules.Rule.M5, failure.rule.?);
}

// spec-case: NEW-CORE-MUT-1
test "interior mut argument sources overlap borrowed replacement results" {
    // O3 permits the declared return; the overlapping call accesses still violate M5.
    try replacementOverlap(std.testing.allocator, changed_mut_entry);
    try replacementOverlap(std.testing.allocator, changed_mut_field);
}

const changed_mut_root =
    \\func replace_root(mut items: int[]) -> int[] from items:
    \\    items = [21]
    \\    return items
    \\
    \\func append_current(mut items: int[], source: int[]) -> int:
    \\    append(mut items, 13)
    \\    return len(items) + source[0]
    \\
    \\func main() -> int:
    \\    mut items = [7]
    \\    return append_current(mut items, replace_root(mut items))
;

// spec-case: NEW-CORE-MUT-1
test "whole mut argument sources overlap borrowed replacement results" {
    try replacementOverlap(std.testing.allocator, changed_mut_root);
}

const stable_mut_entry =
    \\func rebind_selected(mut target: int[], source: int[][]) -> int:
    \\    mut before = target[0]
    \\    target = [13]
    \\    return before + target[0] + source[0][0]
    \\
    \\func main() -> int:
    \\    mut items = [[7]]
    \\    const snapshot = copy(items)
    \\    return rebind_selected(mut items[0], snapshot)
;

// spec-case: NEW-CORE-MUT-1
test "interior mut arguments with later readonly snapshots still build caller writeback" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), stable_mut_entry);
    try std.testing.expect(contains(text, "call record{i64, list[i64]} rebind_selected("));
    try std.testing.expect(contains(text, "list_set.exact list[list[i64]]"));
}
