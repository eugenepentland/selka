//! RC construction registers partial ownership before a field transfer can fail.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };

fn pairText() !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "rc_aggregate.my",
        \\record Pair:
        \\    left: list[int]
        \\    right: list[int]
        \\
        \\def pair(items: list[int]) -> Pair:
        \\    return Pair(items, items)
        \\
        \\def main() -> int:
        \\    value = pair([1, 2])
        \\    return len(value.left)
    );
    defer compilation.deinit();
    const manifest = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(manifest);
    return std.json.parseFromSlice(Manifest, t.allocator, manifest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}

fn findFunction(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}

fn location(text: []const u8, needle: []const u8) !usize {
    return std.mem.indexOf(u8, text, needle) orelse error.TestUnexpectedResult;
}

// spec: RC-AGGREGATE-1
test "RC aggregate partial construction is zeroed and journaled before copying fields" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try pairText();
    defer manifest.deinit();
    const text = try findFunction(manifest.value, "pair");
    const cleared = try location(text, "call $memset(l %v");
    const copied = cleared + try location(text[cleared..], "call $myl_rc_native_copy");
    try t.expect(cleared < copied);
    try t.expect(std.mem.indexOf(u8, text[cleared..copied], "storew 1") != null);
    try t.expect(try location(text, "call $myl_qbe_rc_frame_enter") < cleared);
    try t.expect(try location(text, "call $myl_qbe_rc_frame_cleanup") > copied);
}
