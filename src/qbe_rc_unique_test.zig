//! Payload parameters keep caller uniqueness; rebound parameters check caller storage.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const source =
    \\def stable(items: mut list[int], at: int) -> int:
    \\    items[at] = 7
    \\    return len(items)
    \\def rebound(items: mut list[int], other: list[int]) -> int:
    \\    items = other
    \\    items[0] = 7
    \\    return len(items)
    \\def main() -> int:
    \\    values = [1, 2]
    \\    return stable(mut values, 0)
;
fn emitted() !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "rc_mut_contract.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}

// spec: RC-MUT-UNIQUE-1
test "RC-MUT-UNIQUE-1 an unchanged scalar-list mut parameter uses caller uniqueness" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    try t.expect(std.mem.indexOf(u8, try named(manifest.value, "stable"), "myl_qbe_rc_unique_local") == null);
    try t.expect(std.mem.indexOf(u8, try named(manifest.value, "rebound"), "myl_qbe_rc_unique_field") != null);
}
