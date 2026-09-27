//! Room append admission retains the dynamic refusal and original slow helper.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const source =
    \\def scalar(items: mut list[int], value: int) -> unit:
    \\    items.append(value)
    \\def narrow(items: mut list[u8], value: u8) -> unit:
    \\    items.append(value)
    \\def floating(items: mut list[float], value: float) -> unit:
    \\    items.append(value)
    \\def managed(items: mut list[list[int]], value: list[int]) -> unit:
    \\    items.append(value)
    \\def aggregate(items: mut list[tuple[int, int]], value: tuple[int, int]) -> unit:
    \\    items.append(value)
    \\def main() -> int:
    \\    return 0
;
fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}
// spec: RC-PLAIN-APPEND-1
test "RC-PLAIN-APPEND-1 room stores retain queue capacity generation and fallback guards" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "rc_append.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    var manifest = try std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer manifest.deinit();
    for ([_][]const u8{ "scalar", "narrow", "floating" }) |name| {
        const il = try named(manifest.value, name);
        try t.expect(std.mem.indexOf(u8, il, "myl_rc_list_plain_ready") != null);
        try t.expect(std.mem.indexOf(u8, il, " =w cultl ") != null);
        try t.expect(std.mem.indexOf(u8, il, " =w cnel ") != null);
        try t.expect(std.mem.indexOf(u8, il, ", -1\n") != null);
        try t.expect(std.mem.indexOf(u8, il, "myl_rc_list_append") != null);
        try t.expect(std.mem.indexOf(u8, il, "myl_qbe_fail_allocation") != null);
    }
    try refused(manifest.value);
}
fn refused(manifest: Manifest) !void {
    for ([_][]const u8{ "managed", "aggregate" }) |name| {
        const il = try named(manifest, name);
        try t.expect(std.mem.indexOf(u8, il, "myl_rc_list_plain_ready") == null);
        try t.expect(std.mem.indexOf(u8, il, "myl_rc_list_append") != null);
    }
}
