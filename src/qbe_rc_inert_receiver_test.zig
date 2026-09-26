//! Structural scope admission over source-level receiver evaluation regions.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const source =
    \\def scalar(items: mut list[int], index: int) -> int:
    \\    items[index] = 7
    \\    return len(items)
    \\def nested(items: mut list[list[int]], row: int, column: int) -> int:
    \\    items[row][column] = 7
    \\    return len(items)
    \\def mutating_index(items: mut list[int]) -> int:
    \\    items.append(9)
    \\    return 0
    \\def callback(items: mut list[int]) -> int:
    \\    items[mutating_index(mut items)] = 7
    \\    return len(items)
    \\def managed(items: mut list[list[int]], value: list[int]) -> int:
    \\    items[0] = value
    \\    return len(items)
    \\def main() -> int:
    \\    values = [1, 2]
    \\    return scalar(mut values, 0)
;
fn emitted() !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "rc_inert.my", source);
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

// spec: RC-INERT-RECEIVER-1
test "RC-INERT-RECEIVER-1 scalar index regions omit pins but callback and publication retain scopes" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    try t.expect(!contains(try named(manifest.value, "scalar"), "myl_qbe_rc_scope_pin"));
    try t.expect(!contains(try named(manifest.value, "nested"), "myl_qbe_rc_scope_pin"));
    try t.expect(contains(try named(manifest.value, "nested"), "myl_qbe_rc_unique_field"));
    try t.expect(contains(try named(manifest.value, "callback"), "myl_qbe_rc_scope_pin"));
    try t.expect(contains(try named(manifest.value, "managed"), "myl_qbe_rc_scope_pin"));
}
