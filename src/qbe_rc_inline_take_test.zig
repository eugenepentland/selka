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
        \\def forwarded() -> Pair:
        \\    return made()
        \\def copied(items: list[int]) -> list[int]:
        \\    return items
        \\def escaped() -> Pair:
        \\    with arena() as scratch:
        \\        value = made()
        \\        return scratch.escape(value)
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

// spec: RC-PRODUCED-OWNER-1
test "RC-PRODUCED-OWNER-1 fresh call results move without an initialization branch" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    const forwarded = try named(manifest.value, "forwarded");
    try t.expect(contains(forwarded, "@rcmoveheader"));
    try t.expect(!contains(forwarded, "@rccopy"));
    try t.expect(contains(try named(manifest.value, "copied"), "@rccopy"));
}

// spec: RC-DISJOINT-TAKE-1
test "RC-DISJOINT-TAKE-1 completed operand publications occupy separate pending buffers" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc_counting);
    var manifest = try emitted();
    defer manifest.deinit();
    const forwarded = try named(manifest.value, "forwarded");
    try t.expect(!contains(forwarded, "@rcmovecheck"));
    try t.expect(contains(forwarded, "@rcmoveheader"));
    try t.expect(contains(forwarded, "call $myl_rc_native_take"));
    try t.expect(contains(try named(manifest.value, "copied"), "@rcmovecheck"));
}

// spec: RC-FRAME-REGION-1
test "RC-FRAME-REGION-1 stable frames read depth once while arena bodies stay dynamic" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    const made = try named(manifest.value, "made");
    const escaped = try named(manifest.value, "escaped");
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, made, "call $myl_qbe_region_mark"));
    try t.expect(contains(made, "copy %rcregion"));
    try t.expect(!contains(escaped, "copy %rcregion"));
    try t.expect(std.mem.count(u8, escaped, "call $myl_qbe_region_mark") > 1);
}

// spec: RC-NO-TRACING-ROOTS-1
test "RC-NO-TRACING-ROOTS-1 counted frames use journals while GC retains traced roots" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.gc);
    var gc = try emitted();
    defer gc.deinit();
    try t.expect(contains(try named(gc.value, "made"), "%root0"));
    runtime.set(.rc_counting);
    var rc = try emitted();
    defer rc.deinit();
    const made = try named(rc.value, "made");
    try t.expect(!contains(made, "%root0"));
    try t.expect(!contains(made, "%root_mark"));
    try t.expect(!contains(made, "=l add %heap, 16"));
    try t.expect(contains(made, "call $myl_qbe_rc_frame_enter"));
    try t.expect(contains(made, "call $myl_qbe_rc_frame_cleanup"));
    try t.expect(contains(made, "%heap =l call $myl_qbe_heap"));
    try t.expect(!contains(try named(rc.value, "escaped"), "%root_mark"));
}
