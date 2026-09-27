//! Canonical read-only bodies retain their ABI without temporary owner traffic.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const source =
    \\record Node:
    \\    next: Option[Node]
    \\def count(node: Node) -> int:
    \\    next = node.next
    \\    if next is None:
    \\        return 1
    \\    return 1 + count(next)
    \\def change(items: mut list[int]) -> int:
    \\    items.append(2)
    \\    return len(items)
    \\def allocated(items: list[int]) -> int:
    \\    fresh = [1, 2]
    \\    return len(fresh) + len(items)
    \\def callback(items: list[int], body: def(list[int]) -> int) -> int:
    \\    return body(items)
    \\def returned(items: list[int]) -> list[int]:
    \\    return items
    \\union Wrapped:
    \\    empty,
    \\    leaf: list[int],
    \\    next: Wrapped
    \\def variant(items: list[int]) -> int:
    \\    wrapped = Wrapped.leaf(items)
    \\    match wrapped:
    \\        case Wrapped.leaf(values):
    \\            return 1
    \\        case _:
    \\            return 0
    \\def recursive_variant(items: list[int]) -> int:
    \\    wrapped = Wrapped.next(Wrapped.leaf(items))
    \\    match wrapped:
    \\        case Wrapped.next(inner):
    \\            return 1
    \\        case _:
    \\            return 0
    \\union PlainWrapped:
    \\    empty,
    \\    leaf: bytes
    \\def plain_variant(items: bytes) -> int:
    \\    wrapped = PlainWrapped.leaf(items)
    \\    match wrapped:
    \\        case PlainWrapped.leaf(value):
    \\            return 1
    \\        case _:
    \\            return 0
    \\def main() -> int:
    \\    return count(Node(None))
;
fn emitted() !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "rc_readonly.my", source);
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

// spec: RC-READONLY-BODY-1
test "RC-READONLY-BODY-1 recursive scalar reader has no ownership journal but retains frame failure" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    const count = try named(manifest.value, "count");
    try t.expect(!contains(count, "myl_rc_native_copy"));
    try t.expect(!contains(count, "myl_qbe_rc_frame_enter"));
    try t.expect(!contains(count, " storeb "));
    try t.expect(contains(count, "myl_qbe_fail_frame"));
    try t.expect(contains(count, "call $"));
}

// spec-case: RC-READONLY-BODY-1
test "RC-READONLY-BODY-1 mutation allocation callback and owned result retain journals" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    try t.expect(contains(try named(manifest.value, "change"), "myl_qbe_rc_frame_enter"));
    try t.expect(contains(try named(manifest.value, "allocated"), "myl_qbe_rc_frame_enter"));
    try t.expect(contains(try named(manifest.value, "callback"), "myl_qbe_rc_frame_enter"));
    try t.expect(contains(try named(manifest.value, "returned"), "myl_qbe_rc_frame_enter"));
}

// spec-case: RC-READONLY-BODY-1
test "RC-READONLY-BODY-1 only history-free inline union wrappers borrow" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    try t.expect(!contains(try named(manifest.value, "plain_variant"), "myl_qbe_rc_frame_enter"));
    try t.expect(contains(try named(manifest.value, "variant"), "myl_qbe_rc_frame_enter"));
    try t.expect(contains(try named(manifest.value, "variant"), "# RC-GLUE-1 publish"));
    try t.expect(contains(try named(manifest.value, "recursive_variant"), "myl_qbe_rc_frame_enter"));
}

// spec: RC-SCALAR-LENGTH-BODY-1
test "RC scalar readonly body admits list lengths with managed element reads" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    const text =
        \\record Item:
        \\    data: bytes
        \\    number: int
        \\def scan(items: list[Item]) -> int:
        \\    i = 0
        \\    total = 0
        \\    while i < len(items):
        \\        item = items[i]
        \\        total += item.number
        \\        i += 1
        \\    return total
        \\def main() -> int:
        \\    return scan([Item(b"label", 7)])
    ;
    var compilation = try compiler.Compilation.init(t.allocator, "rc_length_body.my", text);
    defer compilation.deinit();
    const generated = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(generated);
    var manifest = try std.json.parseFromSlice(Manifest, t.allocator, generated, .{ .ignore_unknown_fields = true });
    defer manifest.deinit();
    const il = try named(manifest.value, "scan");
    try t.expect(std.mem.indexOf(u8, il, "call $myl_rc_native_loan") == null);
    try t.expect(std.mem.indexOf(u8, il, "# RC-GLUE-1 loan") == null);
    try t.expect(std.mem.indexOf(u8, il, "call $myl_rc_native_retain") == null);
    try t.expect(std.mem.indexOf(u8, il, "# RC-GLUE-1 retain") == null);
    try t.expect(std.mem.indexOf(u8, il, "call $myl_qbe_rc_frame_enter") == null);
    try t.expect(std.mem.indexOf(u8, il, "call $myl_qbe_fail_normalized_index_bounds") != null);
}
