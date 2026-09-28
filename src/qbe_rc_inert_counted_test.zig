//! RC-INERT-COUNTED-RECEIVER-1: counted element stores through a stable owner.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const pin = "myl_qbe_rc_scope_pin";
const source =
    \\union Tree:
    \\    leaf,
    \\    node: list[Tree]
    \\record Table:
    \\    rows: list[list[int]]
    \\    grid: list[list[list[int]]]
    \\    trees: list[Tree]
    \\    count: int
    \\def managed(items: mut list[list[int]], value: list[int]) -> int:
    \\    items[0] = value
    \\    return len(items)
    \\def field_store(table: mut Table, index: int, value: list[int]):
    \\    table.rows[index] = value
    \\def field_append(table: mut Table, value: list[int]):
    \\    table.rows.append(value)
    \\def fresh_store(table: mut Table, index: int):
    \\    table.rows[index] = [index, index]
    \\def recursive(table: mut Table, value: Tree):
    \\    table.trees[0] = value
    \\def nested(table: mut Table, row: int, value: list[int]):
    \\    table.grid[row][0] = value
    \\def counted_index(table: mut Table) -> int:
    \\    table.count += 1
    \\    return 0
    \\def callback(table: mut Table, value: list[int]):
    \\    table.rows[counted_index(mut table)] = value
    \\def main() -> int:
    \\    table = Table([[1]], [[[1]]], [Tree.leaf], 0)
    \\    field_store(mut table, 0, [2])
    \\    return len(table.rows)
;
fn emitted() !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "rc_inert_counted.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}
fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

// spec: RC-INERT-COUNTED-RECEIVER-1
test "RC counted element stores through a stable owner omit the receiver scope" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    const expected = [_]struct { []const u8, bool }{
        .{ "managed", false },  .{ "field_store", false }, .{ "field_append", false }, .{ "fresh_store", false },
        .{ "recursive", true }, .{ "nested", true },       .{ "callback", true },
    };
    for (expected) |case| try t.expectEqual(case[1], contains(try named(manifest.value, case[0]), pin));
}

// spec-case: RC-INERT-COUNTED-RECEIVER-1
test "RC counted inert stores keep their uniqueness check and GC lowering is unchanged" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    try t.expect(contains(try named(manifest.value, "field_store"), "myl_qbe_rc_unique_field"));
    runtime.set(.gc);
    var collected = try emitted();
    defer collected.deinit();
    try t.expect(!contains(try named(collected.value, "field_store"), pin));
}
