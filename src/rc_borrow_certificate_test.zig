//! Negative and positive physical return certificates over real lowered code.
const std = @import("std");
const compiler = @import("compiler.zig");
const native = @import("native_types.zig");
const shapes = @import("rc_shape.zig");
const proof = @import("rc_borrow_certificate.zig");
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
        return proof.certify(t.allocator, &catalog, function, "rc-v1");
    };
    return error.TestUnexpectedResult;
}

// spec: RC-BORROW-ENTRY-1
test "RC-BORROW-ENTRY-1 readonly physical field and array projections certify one anchor" {
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
