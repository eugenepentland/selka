//! Plain RC element stores retain checks without an ownership helper call.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const source =
    \\def scalar(items: mut list[int], index: int) -> unit:
    \\    items[index] = 7
    \\def floating(items: mut list[float], index: int) -> unit:
    \\    items[index] = 7.5
    \\def managed(items: mut list[list[int]], index: int, value: list[int]) -> unit:
    \\    items[index] = value
    \\def main() -> int:
    \\    items = [1]
    \\    scalar(mut items, -1)
    \\    return 0
;
fn emitted() !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "rc_plain_write.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}
// spec: RC-PLAIN-LIST-WRITE-1
test "RC-PLAIN-LIST-WRITE-1 scalar stores keep bounds and managed stores keep ownership" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    try t.expect(std.mem.indexOf(u8, try named(manifest.value, "scalar"), "myl_rc_list_set") == null);
    try t.expect(std.mem.indexOf(u8, try named(manifest.value, "floating"), "myl_rc_list_set") == null);
    try t.expect(std.mem.indexOf(u8, try named(manifest.value, "scalar"), "myl_qbe_fail_normalized_index_bounds") != null);
    try t.expect(std.mem.indexOf(u8, try named(manifest.value, "managed"), "myl_rc_list_set") != null);
}
