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
        return calls.borrowedIn(t.allocator, &catalog, program.functions, function, "rc-v2");
    };
    return error.TestUnexpectedResult;
}

// spec: RC-BORROW-ENTRY-1
test "RC-BORROW-ENTRY-1 public call contract certifies physical field and array anchors" {
    const field = (try certificate(
        \\record Child:
        \\    items: list[int]
        \\record Parent:
        \\    child: Child
        \\    sibling: list[int]
        \\def selected(value: Parent) -> list[int]:
        \\    return value.child.items
    )).?;
    const index = (try certificate(
        \\def selected(values: [2]list[int]) -> list[int]:
        \\    return values[0]
    )).?;
    const identity = (try certificate(
        \\def selected(values: list[int]) -> list[int]:
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
        \\def selected(first: list[int], second: list[int]) -> list[int]:
        \\    return first
    )).?;
    const second = (try certificate(
        \\def selected(first: list[int], second: list[int]) -> list[int]:
        \\    return second
    )).?;
    const at_zero = (try certificate(
        \\def selected(values: [2]list[int]) -> list[int]:
        \\    return values[0]
    )).?;
    const at_one = (try certificate(
        \\def selected(values: [2]list[int]) -> list[int]:
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
