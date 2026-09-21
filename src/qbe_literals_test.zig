//! Frozen `str`/`bytes` literals lowered as shared immortal image data.
const std = @import("std");
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const outputs = @import("qbe_build_outputs.zig");
const Unit = struct { name: []const u8, symbol: []const u8, il: []const u8 };
const Manifest = struct { version: []const u8, abi: []const u8, functions: []Unit, entry: []const u8 };
fn emitted(a: std.mem.Allocator, input: []const u8) !std.json.Parsed(Manifest) {
    var c = try language.Compilation.init(a, "a_il.my", input);
    defer c.deinit();
    const manifest = try c.emitQbe(a);
    defer a.free(manifest);
    return std.json.parseFromSlice(Manifest, a, manifest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn named(manifest: Manifest, name: []const u8) ?Unit {
    for (manifest.functions) |unit| if (std.mem.eql(u8, unit.name, name)) return unit;
    return null;
}
// spec: QBE-LITERAL-1
test "a constant literal lowers to one shared image load instead of a constructor" {
    var parsed = try emitted(std.testing.allocator,
        \\def main() -> i64:
        \\    text = "abc"
        \\    data = b"xy"
        \\    return int(len(text) + len(data))
    );
    defer parsed.deinit();
    const il = named(parsed.value, "main").?.il;
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, il, "myl_native_list_new"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, il, "myl_native_list_append"));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, il, "# myl-lit "));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, il, "loadl $myl_lit_"));
}
// spec-case: QBE-LITERAL-1
test "repeated literal text emits exactly one immortal image object" {
    const a = std.testing.allocator;
    var c = try language.Compilation.init(a, "b_dedup.my",
        \\def main() -> i64:
        \\    first = "abc"
        \\    second = "abc"
        \\    return int(len(first) + len(second))
    );
    defer c.deinit();
    const manifest = try c.emitQbe(a);
    defer a.free(manifest);
    var parsed = try std.json.parseFromSlice(std.json.Value, a, manifest, .{ .allocate = .alloc_always });
    defer parsed.deinit();
    const generated = try outputs.metadata(a, parsed.value);
    defer a.free(generated);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, generated, "const void *const myl_lit_"));
    try std.testing.expect(std.mem.indexOf(u8, generated, ".mark = MYL_NATIVE_OBJECT_LITERAL_MARK") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "#include \"native_collections.h\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "0x61,0x00,0x00,0x00,0x62,0x00,0x00,0x00,0x63,0x00,0x00,0x00,") != null);
}
// spec-case: QBE-LITERAL-1
test "a frozen literal keeps its content type and length under collection stress" {
    const a = std.testing.allocator;
    var c = try language.Compilation.init(a, "c_run.my",
        \\def main() -> i64:
        \\    text = "abc"
        \\    data = b"xy"
        \\    assert text == "a" + "b" + "c", "content"
        \\    assert len(text) == 3, "length"
        \\    assert len(data) == 2, "bytes"
        \\    assert text[0] == "a", "index"
        \\    return 5
    );
    defer c.deinit();
    try std.testing.expectEqual(@as(i64, 5), (try native.runWithOptions(&c, .{ .gc_stress = true })).value);
}
