//! Fresh loop roots need real temporary release, not semantic move spelling.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const source =
    \\def grow(count: int) -> int:
    \\    items: list[int] = []
    \\    for at in range(count):
    \\        items.append(at)
    \\    return len(items)
    \\def literal(count: int) -> int:
    \\    items = [7, 8]
    \\    for at in range(count):
    \\        items.append(at)
    \\    return len(items)
    \\def comprehension(count: int) -> int:
    \\    items = [at for at in range(count)]
    \\    return len(items)
    \\def terminal(count: int) -> tuple[int, int]:
    \\    items = [at for at in range(2)]
    \\    at = 0
    \\    while True:
    \\        if at == count:
    \\            return items[0], at
    \\        items[0] = at
    \\        at += 1
    \\def shared(count: int) -> int:
    \\    items = [1]
    \\    snapshot = items
    \\    for at in range(count):
    \\        items.append(at)
    \\    return snapshot[0]
    \\def later_alias(count: int) -> int:
    \\    items = [1]
    \\    snapshot: list[int] = []
    \\    for outer in range(2):
    \\        for at in range(count):
    \\            items.append(at)
    \\        snapshot = items
    \\    return len(snapshot)
    \\def inside(count: int) -> int:
    \\    items = [1]
    \\    snapshot: list[int] = []
    \\    for at in range(count):
    \\        snapshot = items
    \\        items.append(at)
    \\    return len(snapshot)
    \\def handoff_alias(count: int) -> int:
    \\    original = [at for at in range(2)]
    \\    items = original
    \\    for at in range(count):
    \\        items.append(at)
    \\    return original[0]
    \\def callback(items: mut list[int]) -> int:
    \\    items.append(9)
    \\    return 0
    \\def calls(count: int) -> int:
    \\    items = [1]
    \\    for at in range(count):
    \\        mutation_result_62 = callback(mut items)
    \\        items.append(mutation_result_62)
    \\    return len(items)
    \\def main() -> int:
    \\    return grow(0)
;
fn emitted() !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "fresh_roots.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}
// spec: RC-FRESH-ROOT-HOIST-1
test "RC fresh loop roots retain entry checks and real owner journals" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    const grow = try named(manifest.value, "grow");
    try t.expect(std.mem.indexOf(u8, grow, "@ce") != null);
    try t.expect(std.mem.indexOf(u8, grow, "# rc-frame") != null);
    try t.expect(std.mem.indexOf(u8, grow, "myl_qbe_rc_unique_local") != null);
    const literal = try named(manifest.value, "literal");
    try t.expect(std.mem.indexOf(u8, literal, "myl_native_list_new") != null);
    try t.expect(std.mem.indexOf(u8, literal, "@ce") != null);
    try t.expect(std.mem.indexOf(u8, try named(manifest.value, "comprehension"), "@ce") != null);
    try t.expectEqual(@as(usize, 2), std.mem.count(u8, try named(manifest.value, "terminal"), "@ce"));
    try t.expect(std.mem.indexOf(u8, try named(manifest.value, "shared"), "@ce") == null);
    try t.expect(std.mem.indexOf(u8, try named(manifest.value, "later_alias"), "@ce") == null);
    try t.expect(std.mem.indexOf(u8, try named(manifest.value, "inside"), "@ce") == null);
    // The fresh comprehension is admitted; its later named alias is not.
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, try named(manifest.value, "handoff_alias"), "@ce"));
    try t.expect(std.mem.indexOf(u8, try named(manifest.value, "calls"), "@ce") == null);
}
