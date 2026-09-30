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
    try std.testing.expect(std.mem.indexOf(u8, generated, "#include \"native_text.h\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, ".length = 3, .bytes = 3, .flags = 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, ".hash = 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, ".storage = {0x61,0x62,0x63,}") != null);
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
const constant_literal = @import("constant_literal.zig");
const typed = @import("typed.zig");
/// A repeating run of source text with an escape and multi-byte scalars, which decodes to 9 scalars for a `str`.
/// decodes to 20 octets in 11 scalars for a `str` and to its 12 ASCII-escaped
const mixed_text = "ab (é→😀)\\n";
const ascii_run = "(sym 1.5)\\n";
/// Metadata for a generated literal, with storage freed by its caller.
fn literalMetadata(a: std.mem.Allocator, run: []const u8, repeats: usize) ![]const u8 {
    const source = try longLiteral(a, "", run, repeats);
    defer a.free(source);
    var c = try language.Compilation.init(a, "indexed_literal.my", source);
    defer c.deinit();
    const manifest = try c.emitQbe(a);
    defer a.free(manifest);
    var parsed = try std.json.parseFromSlice(std.json.Value, a, manifest, .{ .allocate = .alloc_always });
    defer parsed.deinit();
    return outputs.metadata(a, parsed.value);
}
// spec: TEXT-INDEX-4
test "literal indexes preserve scalar samples and aligned runtime layout" {
    const a = std.testing.allocator;
    const generated = try literalMetadata(a, "é😀a", 130);
    defer a.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "unsigned char storage[912]") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "const struct { uint64_t scalar, octet; uint32_t sample[3]; } index") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, ".sample={300,597,896,}") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "MYL_TEXT_INDEXED|MYL_TEXT_SAMPLED|MYL_TEXT_STATIC_INDEX") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "sizeof(myl_native_text)+912") != null);
}
// spec-case: TEXT-INDEX-4
test "short and ASCII literal payloads keep their original unindexed layout" {
    const a = std.testing.allocator;
    const short = try literalMetadata(a, "é", 127);
    defer a.free(short);
    const ascii = try literalMetadata(a, "a", 1000);
    defer a.free(ascii);
    const exact = try literalMetadata(a, "é", 128);
    defer a.free(exact);
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, short, "MYL_TEXT_STATIC_INDEX"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, ascii, "MYL_TEXT_STATIC_INDEX"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, exact, "MYL_TEXT_STATIC_INDEX"));
    try std.testing.expect(std.mem.indexOf(u8, exact, ".sample={0}") != null);
}
// spec: TEXT-VIEW-5
test "omitted text upper endpoints select tails while bounded slices keep their helper" {
    var parsed = try emitted(std.testing.allocator,
        \\def tail(text: str, start: int) -> str:
        \\    return text[start:]
        \\def bounded(text: str, start: int, end: int) -> str:
        \\    return text[start:end]
        \\def main() -> i64:
        \\    return int(len(tail("abcdefghijklmnop", 2)) + len(bounded("abcdefghijklmnop", 2, 12)))
    );
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, named(parsed.value, "tail").?.il, "$myl_native_text_tail"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, named(parsed.value, "bounded").?.il, "$myl_native_text_slice"));
    const mutation = @import("mutation.zig").buffer(.text_tail, false);
    try std.testing.expect(!mutation.writes_receiver and mutation.severs_outer);
    try std.testing.expectEqual(@import("mutation.zig").Operation.shallow_copy, mutation.operation);
    const runtime: @import("qbe_build_llvm_runtime.zig").Table = .{};
    const signature = runtime.signature("myl_native_text_tail").?;
    try std.testing.expectEqualStrings("ptr", signature.result);
    try std.testing.expectEqualDeep(@as([]const []const u8, &.{ "ptr", "ptr", "i64", "i64" }), signature.parameters);
}
/// A `main` returning how many scalars or octets a literal of `repeats` runs holds.
fn longLiteral(a: std.mem.Allocator, prefix: []const u8, run: []const u8, repeats: usize) ![]u8 {
    var source: std.ArrayList(u8) = .empty;
    errdefer source.deinit(a);
    try source.appendSlice(a, "def main() -> i64:\n    data = ");
    try source.appendSlice(a, prefix);
    try source.append(a, '"');
    for (0..repeats) |_| try source.appendSlice(a, run);
    try source.appendSlice(a, "\"\n    return int(len(data))\n");
    return source.toOwnedSlice(a);
}
// spec: LITERAL-PAYLOAD-1
test "a long constant literal is one payload instruction and linear IL" {
    const a = std.testing.allocator;
    // 5400 runs of 10 decoded octets: 54 000 octets, under the 65 536 literal limit.
    const source = try longLiteral(a, "b", ascii_run, 5400);
    defer a.free(source);
    var parsed = try emitted(a, source);
    defer parsed.deinit();
    const il = named(parsed.value, "main").?.il;
    // One hex marker carries the octets (two digits each); the per-element
    // form spent about 200 bytes of IL, a step check and a frame slot on each.
    try std.testing.expect(il.len < 54_000 * 3 + 16_384);
    try std.testing.expect(std.mem.count(u8, il, "alloc8") < 64);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, il, "# myl-lit "));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, il, "loadl $myl_lit_"));
}
// spec-case: LITERAL-PAYLOAD-1
test "a long literal lowers to one instruction whose payload is its content" {
    const a = std.testing.allocator;
    const source = try longLiteral(a, "", ascii_run, 5400);
    defer a.free(source);
    var c = try language.Compilation.init(a, "f_shape.my", source);
    defer c.deinit();
    try c.emit();
    const program = c.code.?;
    const code = program.functions[@backingInt(program.main)].scope.instructions;
    // The literal, the store to `data`, the length read and the return: the
    // per-element form spent one push for each of the 54 000 elements.
    try std.testing.expect(code.len < 16);
    try std.testing.expectEqual(@as(usize, 0), code[0].op.make_record.fields);
    try std.testing.expectEqual(@as(usize, 54_000), code[0].op.make_record.payload.len);
    try std.testing.expectEqualStrings("(sym 1.5)\n(sym 1.5)\n", code[0].op.make_record.payload[0 .. 2 * 10]);
}
// spec-case: LITERAL-PAYLOAD-1
test "a long str and bytes literal reach the program intact" {
    const a = std.testing.allocator;
    const text_source = try longLiteral(a, "", mixed_text, 2000);
    defer a.free(text_source);
    var text = try language.Compilation.init(a, "d_text.my", text_source);
    defer text.deinit();
    // 2000 runs of 9 scalars each (`ab (é→😀)` plus the newline escape).
    try std.testing.expectEqual(@as(i64, 2000 * 9), (try native.runWithOptions(&text, .{})).value);
    const bytes_source = try longLiteral(a, "b", "\\x00\\xff\\n", 5000);
    defer a.free(bytes_source);
    var bytes = try language.Compilation.init(a, "e_bytes.my", bytes_source);
    defer bytes.deinit();
    try std.testing.expectEqual(@as(i64, 5000 * 3), (try native.runWithOptions(&bytes, .{ .gc_stress = true })).value);
}
// spec-case: LITERAL-PAYLOAD-1
test "only a constant literal of valid octets collapses to a payload" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const span: @import("source.zig").Span = .{ .start = 0, .end = 0 };
    const nodes = [_]typed.Node{
        .{ .ty = .u32, .span = span, .data = .{ .integer = 'a' } },
        .{ .ty = .u32, .span = span, .data = .{ .integer = 0x1f600 } },
        .{ .ty = .u32, .span = span, .data = .{ .integer = 0xd800 } },
        .{ .ty = .u8, .span = span, .data = .{ .integer = 0xff } },
        .{ .ty = .u8, .span = span, .data = .{ .integer = 256 } },
        .{ .ty = .u32, .span = span, .data = .{ .boolean = true } },
    };
    const ids = [_]typed.NodeId{ @fromBackingInt(@intCast(0)), @fromBackingInt(@intCast(1)), @fromBackingInt(@intCast(2)), @fromBackingInt(@intCast(3)), @fromBackingInt(@intCast(4)), @fromBackingInt(@intCast(5)) };
    const text = (try constant_literal.payload(arena.allocator(), &nodes, ids[0..2], true)).?;
    try std.testing.expectEqualStrings("a\u{1f600}", text);
    const octets = (try constant_literal.payload(arena.allocator(), &nodes, ids[3..4], false)).?;
    try std.testing.expectEqualSlices(u8, &.{0xff}, octets);
    try std.testing.expectEqual(@as(?[]const u8, null), try constant_literal.payload(arena.allocator(), &nodes, ids[0..0], true));
    try std.testing.expectEqual(@as(?[]const u8, null), try constant_literal.payload(arena.allocator(), &nodes, ids[1..3], true));
    try std.testing.expectEqual(@as(?[]const u8, null), try constant_literal.payload(arena.allocator(), &nodes, ids[3..5], false));
    try std.testing.expectEqual(@as(?[]const u8, null), try constant_literal.payload(arena.allocator(), &nodes, ids[5..6], true));
    try std.testing.expectEqual(@as(?[]const u8, null), try constant_literal.payload(arena.allocator(), &nodes, ids[3..4], true));
}
