//! List comprehensions build a fresh list through one checked loop.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const typed = @import("typed.zig");

fn reject(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "comprehension.my", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

// spec: PY-COMPREHENSION-2
test "comprehensions reject shadowing, non-Boolean filters and uniterable sources" {
    try reject(
        \\def main() -> int:
        \\    value = 1
        \\    _ = [value for value in [1, 2]]
        \\    return 0
    , "E_SHADOWING");
    try reject(
        \\def main() -> int:
        \\    _ = [x for x in [1, 2] if x]
        \\    return 0
    , "E_TYPE");
    try reject(
        \\def main() -> int:
        \\    _ = [x for x in 3]
        \\    return 0
    , "E_COLLECTION_METHOD");
}

fn listCapacities(source: []const u8, tags: *std.ArrayList(std.meta.Tag(@FieldType(typed.Node, "data")))) !void {
    var c = try language.Compilation.init(t.allocator, "comprehension.my", source);
    defer c.deinit();
    try c.check();
    for (c.program.?.nodes) |node| if (node.data == .acquire_buffer) {
        const capacity = c.program.?.nodes[@backingInt(node.data.acquire_buffer.capacity)];
        try tags.append(t.allocator, std.meta.activeTag(capacity.data));
    };
}

// spec-case: PY-COMPREHENSION-1
// spec-case: PY-COMPREHENSION-3
test "known-size unfiltered comprehensions reserve their bound while filters retain growth" {
    const Tag = std.meta.Tag(@FieldType(typed.Node, "data"));
    var collection: std.ArrayList(Tag) = .empty;
    defer collection.deinit(t.allocator);
    try listCapacities(
        \\def copy[T: copy + storable](values: list[T]) -> list[T]:
        \\    return [value for value in values]
        \\
        \\def main() -> int:
        \\    return len(copy([1, 2, 3]))
    , &collection);
    try t.expect(std.mem.indexOfScalar(Tag, collection.items, .local) != null);

    var range: std.ArrayList(Tag) = .empty;
    defer range.deinit(t.allocator);
    try listCapacities(
        \\def span[T: integer](start: T, end: T) -> list[T]:
        \\    return [value for value in range(start, end)]
        \\
        \\def main() -> int:
        \\    return len(span(-2i16, 3i16))
    , &range);
    try t.expect(std.mem.indexOfScalar(Tag, range.items, .block_value) != null);

    var filtered: std.ArrayList(Tag) = .empty;
    defer filtered.deinit(t.allocator);
    try listCapacities("def main() -> int:\n    return len([value for value in range(5) if value > 2])\n", &filtered);
    try t.expect(std.mem.indexOfScalar(Tag, filtered.items, .integer) != null);
}
