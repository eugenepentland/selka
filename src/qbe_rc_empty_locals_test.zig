//! Concrete journals retain every uncertain writer while dropping proven borrows.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const source =
    \\record Point:
    \\    x: int
    \\    y: int
    \\record Holder:
    \\    values: list[Point]
    \\def advance(items: mut list[Point], index: int) -> int:
    \\    old = items[index]
    \\    items[index].x = old.x + 1
    \\    return len(items)
    \\def rebind(items: mut list[Point], index: int) -> int:
    \\    items = [Point(3, 5)]
    \\    items[index].x = 7
    \\    return len(items)
    \\def change(items: mut list[Point]) -> int:
    \\    items.append(Point(9, 11))
    \\    return 0
    \\def callback(items: mut list[Point]) -> int:
    \\    items[change(mut items)].x = 7
    \\    return len(items)
    \\def iterate(items: list[Point]) -> int:
    \\    total = 0
    \\    for item in items:
    \\        total += item.x
    \\    return total
    \\def referenced(holder: mut Holder, index: int) -> int:
    \\    holder.values.append(Point(2, 3))
    \\    return holder.values[index].x
    \\def pattern(candidate: Option[list[Point]]) -> int:
    \\    match candidate:
    \\        case Some(items):
    \\            return items[0].x
    \\        case None:
    \\            return 0
    \\def main() -> int:
    \\    items = [Point(1, 2)]
    \\    return advance(mut items, 0)
;

fn emitted() !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "rc_empty.my", source);
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

// spec-case: RC-EMPTY-LOCAL-JOURNAL-1
test "RC empty local journals keep parameter operand scratch and trap linkage" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    const il = try named(manifest.value, "advance");
    try t.expect(contains(il, "%rcentries =l alloc8 128"));
    try t.expect(contains(il, "myl_qbe_rc_frame_enter"));
    try t.expect(contains(il, "myl_qbe_rc_frame_cleanup"));
    try t.expect(contains(try named(manifest.value, "rebind"), "myl_qbe_rc_unique_local"));
    try t.expect(contains(try named(manifest.value, "callback"), "myl_qbe_rc_scope_pin"));
    try t.expect(contains(try named(manifest.value, "iterate"), "myl_rc_hold_acquire"));
    try t.expect(contains(try named(manifest.value, "referenced"), "myl_rc_native_loan"));
    try t.expect(contains(try named(manifest.value, "pattern"), "myl_rc_native_loan"));
}
