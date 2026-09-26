//! Native token moves retain the fallible path for pins and unusual layouts.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
fn emitted() !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "rc_inline_take.my",
        \\record Pair:
        \\    left: list[int]
        \\    right: list[int]
        \\def made() -> Pair:
        \\    return Pair([1], [2])
        \\def held(view: DictValues[int, int]) -> DictValues[int, int]:
        \\    return view
        \\def main() -> int:
        \\    value = made()
        \\    return value.left[0]
    );
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

// spec: RC-INLINE-TAKE-1
test "RC-INLINE-TAKE-1 ordinary moves preflight headers and preserve fallible fallback" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    const made = try named(manifest.value, "made");
    try t.expect(contains(made, "@rcmoveheader"));
    try t.expect(contains(made, "@rcmoveslow"));
    try t.expect(contains(made, "=w cnel"));
    try t.expect(contains(made, "call $myl_rc_native_take"));
    try t.expect(!contains(try named(manifest.value, "held"), "@rcmoveheader"));
}

// spec-case: RC-INLINE-TAKE-1
test "RC-INLINE-TAKE-1 counted artifacts share event-free token relocation" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc_counting);
    var manifest = try emitted();
    defer manifest.deinit();
    try t.expect(contains(try named(manifest.value, "made"), "@rcmoveheader"));
    try t.expect(!contains(try named(manifest.value, "held"), "@rcmoveheader"));
}
