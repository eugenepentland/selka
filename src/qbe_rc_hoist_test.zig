//! Physical COW loop proofs include negative callback and publication cases.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const source =
    \\def flat(count: int) -> list[int]:
    \\    items = [0, 0]
    \\    for at in range(count):
    \\        items[at % 2] = at
    \\    return items
    \\def nested(count: int) -> list[list[int]]:
    \\    items = [[0, 0], [0, 0]]
    \\    for at in range(count):
    \\        items[at % 2][0] = at
    \\    return items
    \\def callback(items: mut list[int]) -> int:
    \\    items[0] = 9
    \\    return 0
    \\def calls(count: int) -> list[int]:
    \\    items = [0, 0]
    \\    for at in range(count):
    \\        items[callback(mut items)] = at
    \\    return items
    \\def snapshots(count: int) -> list[int]:
    \\    items = [0, 0]
    \\    before = items
    \\    for at in range(count):
    \\        before = items
    \\        items[0] = at
    \\    return before
    \\def main() -> int:
    \\    return len(flat(2))
;
fn emitted() !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "rc_hoist.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}
// spec: RC-PHYSICAL-HOIST-1
test "RC-PHYSICAL-HOIST-1 loop entries need physical no-publication proof" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    try t.expect(std.mem.indexOf(u8, try named(manifest.value, "flat"), "@ce") != null);
    try t.expect(std.mem.indexOf(u8, try named(manifest.value, "nested"), "myl_qbe_rc_unique_elements") != null);
    try t.expect(std.mem.indexOf(u8, try named(manifest.value, "calls"), "@ce") == null);
    try t.expect(std.mem.indexOf(u8, try named(manifest.value, "snapshots"), "@ce") == null);
}
