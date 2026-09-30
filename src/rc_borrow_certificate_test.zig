//! Negative and positive physical return certificates over real lowered code.
const std = @import("std");
const compiler = @import("compiler.zig");
const native = @import("native_types.zig");
const shapes = @import("rc_shape.zig");
const calls = @import("rc_calls.zig");
const model = @import("rc_model.zig");
const t = std.testing;

fn certificate(source: []const u8) !?model.BorrowCertificate {
    const text = try std.mem.concat(t.allocator, u8, &.{ source, "\n\ndef main() -> int:\n    return 0\n" });
    defer t.allocator.free(text);
    var compilation = try compiler.Compilation.init(t.allocator, "rc_borrow.my", text);
    defer compilation.deinit();
    try compilation.emit();
    const program = compilation.code.?;
    var layouts = try native.Catalog.initRecords(t.allocator, program.records);
    defer layouts.deinit();
    var catalog = try shapes.Catalog.init(t.allocator, &layouts);
    defer catalog.deinit();
    for (program.functions) |function| if (std.mem.eql(u8, function.name, "selected")) {
        return calls.borrowedIn(t.allocator, &catalog, program.functions, function, "rc-v5");
    };
    return error.TestUnexpectedResult;
}

// spec: RC-BORROW-ENTRY-1
test "RC-BORROW-ENTRY-1 public call contract certifies physical field and array anchors" {
    const field = (try certificate(
        \\record Child:
        \\    items: bytes
        \\record Parent:
        \\    child: Child
        \\    sibling: bytes
        \\def selected(value: Parent) -> bytes:
        \\    return value.child.items
    )).?;
    const index = (try certificate(
        \\def selected(values: [2]bytes) -> bytes:
        \\    return values[0]
    )).?;
    const identity = (try certificate(
        \\def selected(values: bytes) -> bytes:
        \\    return values
    )).?;
    try t.expectEqual(@as(u32, 0), field.parameter);
    try t.expectEqual(@as(u32, 0), index.parameter);
    try t.expectEqual(@as(u32, 0), identity.parameter);
    try t.expect(!std.mem.eql(u8, &field.dependency_identity, &index.dependency_identity));
}

// spec-case: RC-BORROW-ENTRY-1
test "RC-BORROW-ENTRY-1 mixed fresh branches and wrappers never borrow" {
    try t.expectEqual(null, try certificate(
        \\def selected(values: [2]list[int], fresh: bool) -> list[int]:
        \\    if fresh:
        \\        return [7]
        \\    return values[0]
    ));
    try t.expectEqual(null, try certificate(
        \\def selected(values: list[int]) -> list[list[int]]:
        \\    return [values]
    ));
    try t.expectEqual(null, try certificate(
        \\record Pair:
        \\    borrowed: list[int]
        \\    fresh: list[int]
        \\def selected(values: list[int]) -> Pair:
        \\    return Pair(values, [7])
    ));
}

// spec-case: RC-BORROW-ENTRY-1
test "RC-BORROW-ENTRY-1 mutating and uncertified call returns stay owned" {
    try t.expectEqual(null, try certificate(
        \\def selected(values: mut list[int]) -> list[int]:
        \\    values.append(7)
        \\    return values
    ));
    try t.expectEqual(null, try certificate(
        \\def alias(values: list[int]) -> list[int]:
        \\    return values
        \\def selected(values: list[int]) -> list[int]:
        \\    return alias(values)
    ));
    try t.expectEqual(null, try certificate(
        \\def selected(values: list[int]) -> list[int]:
        \\    return values.copy()
    ));
}

// spec-case: RC-BORROW-ENTRY-1
test "RC-BORROW-ENTRY-1 physical anchor and projection edits change certificate dependencies" {
    const first = (try certificate(
        \\def selected(first: bytes, second: bytes) -> bytes:
        \\    return first
    )).?;
    const second = (try certificate(
        \\def selected(first: bytes, second: bytes) -> bytes:
        \\    return second
    )).?;
    const at_zero = (try certificate(
        \\def selected(values: [2]bytes) -> bytes:
        \\    return values[0]
    )).?;
    const at_one = (try certificate(
        \\def selected(values: [2]bytes) -> bytes:
        \\    return values[1]
    )).?;
    try t.expectEqual(@as(u32, 1), second.parameter);
    try t.expect(!std.mem.eql(u8, &first.dependency_identity, &second.dependency_identity));
    try t.expect(!std.mem.eql(u8, &at_zero.dependency_identity, &at_one.dependency_identity));
    try t.expectEqualSlices(u8, &at_zero.shape_identity, &at_one.shape_identity);
}

// spec-case: RC-BORROW-ENTRY-1
test "RC-BORROW-ENTRY-1 branch projections and immortal inline fallback certify" {
    const answer = (try certificate(
        \\record Span:
        \\    source: bytes
        \\    start: int
        \\record Node:
        \\    span: Span
        \\    next: int
        \\def empty() -> Span:
        \\    return Span(b"", 0)
        \\def selected(nodes: list[Node], index: int) -> Node:
        \\    if index < 0 or index >= len(nodes):
        \\        return Node(empty(), len(nodes))
        \\    return nodes[index]
    )).?;
    try t.expectEqual(@as(u32, 0), answer.parameter);
}

// spec-case: RC-BORROW-ENTRY-1
test "RC-BORROW-ENTRY-1 different parameter paths and fresh factory fallback decline" {
    try t.expectEqual(null, try certificate(
        \\def selected(first: bytes, second: bytes, choice: bool) -> bytes:
        \\    if choice:
        \\        return first
        \\    return second
    ));
    try t.expectEqual(null, try certificate(
        \\record Span:
        \\    source: list[int]
        \\def empty() -> Span:
        \\    return Span([7])
        \\def selected(nodes: list[Span], index: int) -> Span:
        \\    if index < 0:
        \\        return empty()
        \\    return nodes[index]
    ));
}

const fallback =
    \\record Span:
    \\    source: bytes
    \\    start: int
    \\def empty() -> Span:
    \\    return Span(b"", OFFSET)
    \\def selected(nodes: list[Span], index: int) -> Span:
    \\    if index < 0:
    \\        return empty()
    \\    return nodes[index]
;

// spec-case: RC-BORROW-ENTRY-1
test "RC-BORROW-ENTRY-1 immortal helper edits change transitive dependency identity" {
    const first_source = try std.mem.replaceOwned(u8, t.allocator, fallback, "OFFSET", "0");
    defer t.allocator.free(first_source);
    const second_source = try std.mem.replaceOwned(u8, t.allocator, fallback, "OFFSET", "1");
    defer t.allocator.free(second_source);
    const first = (try certificate(first_source)).?;
    const second = (try certificate(second_source)).?;
    try t.expect(!std.mem.eql(u8, &first.dependency_identity, &second.dependency_identity));
    try t.expectEqual(first.parameter, second.parameter);
}

fn oversizedProof() !?model.BorrowCertificate {
    var source: std.Io.Writer.Allocating = .init(t.allocator);
    defer source.deinit();
    try source.writer.writeAll("def selected(values: list[int]) -> list[int]:\n    count = 0\n");
    for (0..256) |_| try source.writer.writeAll("    count += 1\n");
    try source.writer.writeAll("    return values\n");
    return certificate(source.written());
}

// spec: RC-BORROW-BOUND-1
test "RC borrowed entry proof declines recursive and oversized queries" {
    try t.expectEqual(null, try certificate(
        \\def selected(values: list[int]) -> list[int]:
        \\    return selected(values)
    ));
    try t.expectEqual(null, try certificate(
        \\def other(values: list[int]) -> list[int]:
        \\    return selected(values)
        \\def selected(values: list[int]) -> list[int]:
        \\    return other(values)
    ));
    try t.expectEqual(null, try oversizedProof());
}

// spec-case: RC-SEMANTIC-LOWERING-1
test "RC semantic history prevents borrowed entries from erasing mutable return copies" {
    try t.expectEqual(null, try certificate(
        \\def selected(values: list[int]) -> list[int]:
        \\    return values
    ));
    try t.expectEqual(null, try certificate(
        \\record Row:
        \\    items: list[int]
        \\def selected(row: Row) -> list[int]:
        \\    return row.items
    ));
}

// spec: RC-BORROW-LOOP-1
test "RC-BORROW-LOOP-1 search loops converge to one anchor and immortal fallback" {
    const source =
        \\record Node:
        \\    text: bytes
        \\    id: int
        \\def empty() -> Node:
        \\    return Node(b"", -1)
        \\def selected(nodes: list[Node], key: int) -> Node:
        \\    i = 0
        \\    while i < len(nodes):
        \\        node = nodes[i]
        \\        if node.id == key:
        \\            return node
        \\        i += 1
        \\    return empty()
    ;
    const first = (try certificate(source)).?;
    const second = (try certificate(source)).?;
    try t.expectEqual(@as(u32, 0), first.parameter);
    try t.expectEqualSlices(u8, &first.dependency_identity, &second.dependency_identity);
}

// spec-case: RC-BORROW-LOOP-1
test "RC-BORROW-LOOP-1 backedge reaching an earlier return changes the anchor" {
    try t.expectEqual(null, try certificate(
        \\def selected(first: bytes, second: bytes) -> bytes:
        \\    answer = first
        \\    i = 0
        \\    while i < 2:
        \\        if i > 0:
        \\            return answer
        \\        answer = second
        \\        i += 1
        \\    return first
    ));
    try t.expectEqual(null, try certificate(
        \\def selected(values: list[bytes], count: int) -> bytes:
        \\    i = 0
        \\    while i < count:
        \\        unused = [i]
        \\        i += 1
        \\    return values[0]
    ));
}

// spec-case: RC-BORROW-LOOP-1
test "RC-BORROW-LOOP-1 unavailable joins never regain immortal or parameter facts" {
    const flow = @import("rc_borrow_flow.zig");
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var work: usize = 64;
    var graph = try flow.Graph.init(arena.allocator(), 4, 1, &work);
    defer graph.deinit();
    var present = [_]?flow.Value{.{ .ty = .i64 }};
    var missing = [_]?flow.Value{null};
    try t.expect(try graph.publish(1, .{ .stack = &.{}, .locals = &present }));
    try t.expectEqual(@as(?usize, 1), graph.take());
    try t.expect(try graph.publish(1, .{ .stack = &.{}, .locals = &missing }));
    try t.expectEqual(@as(?usize, 1), graph.take());
    try t.expect(try graph.publish(1, .{ .stack = &.{}, .locals = &present }));
    try t.expectEqual(null, graph.incoming[1].?.locals[0]);
    try t.expectEqual(null, graph.take());
    work = 0;
    try t.expect(!try graph.publish(2, .{ .stack = &.{}, .locals = &present }));
}

// spec: RC-BORROW-COMPOSE-1
test "RC-BORROW-COMPOSE-1 direct and scalar callees map exact actual argument anchors" {
    const answer = (try certificate(
        \\record Node:
        \\    text: bytes
        \\    key: int
        \\def first(nodes: list[Node]) -> Node:
        \\    if len(nodes) == 0:
        \\        return Node(b"", -1)
        \\    return nodes[0]
        \\def depth(node: Node) -> int:
        \\    return node.key
        \\def swapped(left: list[Node], right: list[Node]) -> Node:
        \\    a = first(right)
        \\    b = first(right)
        \\    if depth(a) < depth(b):
        \\        return a
        \\    return b
        \\def selected(left: list[Node], right: list[Node]) -> Node:
        \\    return swapped(right, left)
    )).?;
    try t.expectEqual(@as(u32, 0), answer.parameter);
}

// spec-case: RC-BORROW-COMPOSE-1
test "RC-BORROW-COMPOSE-1 callee mapping conflicts and allocating scalar bodies refuse" {
    try t.expectEqual(null, try certificate(
        \\def same(value: bytes) -> bytes:
        \\    return value
        \\def selected(first: bytes, second: bytes) -> bytes:
        \\    answer = same(first)
        \\    i = 0
        \\    while i < 2:
        \\        if i > 0:
        \\            return answer
        \\        answer = same(second)
        \\        i += 1
        \\    return first
    ));
    try t.expectEqual(null, try certificate(
        \\def hidden() -> int:
        \\    unused = [7]
        \\    return 0
        \\def selected(nodes: list[bytes]) -> bytes:
        \\    return nodes[hidden()]
    ));
}

// spec-case: RC-BORROW-COMPOSE-1
test "RC-BORROW-COMPOSE-1 completed memo preserves independent callee admission" {
    var source: std.Io.Writer.Allocating = .init(t.allocator);
    defer source.deinit();
    try source.writer.writeAll("def selected(nodes: list[bytes], index: int) -> bytes:\n    i = index\n");
    for (0..30) |_| try source.writer.writeAll("    i += 1\n");
    try source.writer.writeAll("    if i < len(nodes):\n        return nodes[i]\n    return nodes[0]\n");
    const standalone = (try certificate(source.written())).?;
    const helper = try std.mem.replaceOwned(u8, t.allocator, source.written(), "def selected(", "def picked(");
    defer t.allocator.free(helper);
    source.clearRetainingCapacity();
    try source.writer.writeAll(helper);
    try source.writer.writeAll("\ndef selected(nodes: list[bytes], index: int) -> bytes:\n    a = picked(nodes, index)\n    b = picked(nodes, index + 1)\n    if index < 0:\n        return a\n    return b\n");
    const composed = (try certificate(source.written())).?;
    try t.expectEqual(standalone.parameter, composed.parameter);
}

fn dependencySource() ![]u8 {
    var source: std.Io.Writer.Allocating = .init(t.allocator);
    defer source.deinit();
    for (0..17) |i| try source.writer.print("def helper{d}(value: bytes) -> bytes:\n    if len(value) == {d}:\n        return b\"\"\n    return value\n\n", .{ i, i });
    try source.writer.writeAll("def selected(value: bytes) -> bytes:\n    result = value\n");
    for (0..16) |i| try source.writer.print("    result = helper{d}(result)\n", .{i});
    try source.writer.writeAll("    return result\n");
    return t.allocator.dupe(u8, source.written());
}

// spec-case: RC-BORROW-COMPOSE-1
test "RC-BORROW-COMPOSE-1 dependency count is bounded without memo eviction" {
    const source = try dependencySource();
    defer t.allocator.free(source);
    try t.expect((try certificate(source)) != null);
    const seventeenth = try std.mem.replaceOwned(u8, t.allocator, source, "    return result\n", "    result = helper16(result)\n    return result\n");
    defer t.allocator.free(seventeenth);
    try t.expectEqual(null, try certificate(seventeenth));
}

// spec-case: RC-BORROW-COMPOSE-1
test "RC-BORROW-COMPOSE-1 different callee parameters may name the same caller anchor" {
    const answer = (try certificate(
        \\def left(first: bytes, second: bytes) -> bytes:
        \\    if len(second) == 0:
        \\        return b""
        \\    return first
        \\def right(first: bytes, second: bytes) -> bytes:
        \\    if len(first) == 0:
        \\        return b""
        \\    return second
        \\def selected(value: bytes, choice: bool) -> bytes:
        \\    a = left(value, value)
        \\    b = right(value, value)
        \\    if choice:
        \\        return a
        \\    return b
    )).?;
    try t.expectEqual(@as(u32, 0), answer.parameter);
}

// spec: RC-BORROW-MATCH-1
test "RC-BORROW-MATCH-1 match arms bind payloads with the scrutinee's anchor" {
    const matched = (try certificate(
        \\record Text:
        \\    chars: bytes
        \\    hash: u32
        \\union Obj:
        \\    free,
        \\    text: Text
        \\record Table:
        \\    objects: list[Obj]
        \\def selected(table: Table, at: int) -> Text:
        \\    match table.objects[at]:
        \\        case Obj.text(payload):
        \\            return payload
        \\        case _:
        \\            return Text(chars=b"", hash=0u32)
    )).?;
    try t.expectEqual(@as(u32, 0), matched.parameter);
}

// spec-case: RC-BORROW-MATCH-1
test "RC-BORROW-MATCH-1 fresh arm values still decline" {
    try t.expectEqual(null, try certificate(
        \\record Text:
        \\    chars: bytes
        \\union Obj:
        \\    free,
        \\    text: Text
        \\def selected(objects: list[Obj], at: int, extra: bytes) -> Text:
        \\    match objects[at]:
        \\        case Obj.text(payload):
        \\            return payload
        \\        case _:
        \\            return Text(extra + b"!")
    ));
}
