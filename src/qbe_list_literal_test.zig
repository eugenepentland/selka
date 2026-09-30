//! Large primitive list images retain native COW and bounded compilation.
const std = @import("std");
const compiler = @import("compiler.zig");
const outputs = @import("qbe_build_outputs.zig");
const native = @import("native_execute.zig");
const bytecode = @import("bytecode.zig");
const t = std.testing;

fn listSource(allocator: std.mem.Allocator, ty: []const u8, value: []const u8, count: usize) ![]u8 {
    const prefix = try std.fmt.allocPrint(allocator, "def main() -> int:\n    items: list[{s}] = [", .{ty});
    defer allocator.free(prefix);
    return literalSource(allocator, prefix, value, count, "]\n    return len(items)\n");
}

fn literalSource(allocator: std.mem.Allocator, prefix: []const u8, value: []const u8, count: usize, suffix: []const u8) ![]u8 {
    var source: std.Io.Writer.Allocating = .init(allocator);
    defer source.deinit();
    try source.writer.writeAll(prefix);
    for (0..count) |index| try source.writer.print("{s}{s}", .{ if (index == 0) "" else ", ", value });
    try source.writer.writeAll(suffix);
    return source.toOwnedSlice();
}
// spec: LIST-LITERAL-PAYLOAD-1
test "LIST-LITERAL-PAYLOAD-1 thousand primitive elements emit bounded code and one static image" {
    const source = try listSource(t.allocator, "int", "17", 1000);
    defer t.allocator.free(source);
    var c = try compiler.Compilation.init(t.allocator, "list_image.my", source);
    defer c.deinit();
    try c.emit();
    const instructions = c.code.?.functions[@backingInt(c.code.?.main)].scope.instructions;
    try t.expect(instructions.len < 20);
    try t.expectEqual(@as(usize, 8000), instructions[0].op.make_record.payload.len);
    const manifest = try c.emitQbe(t.allocator);
    defer t.allocator.free(manifest);
    var parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, manifest, .{ .allocate = .alloc_always });
    defer parsed.deinit();
    const il = parsed.value.object.get("functions").?.array.items[0].object.get("il").?.string;
    try t.expect(il.len < 30_000);
    try t.expect(std.mem.indexOf(u8, il, "call $myl_native_list_new") == null);
    try t.expect(std.mem.indexOf(u8, il, "call $myl_rc_list_append") == null);
    const metadata = try outputs.metadata(t.allocator, parsed.value);
    defer t.allocator.free(metadata);
    try t.expect(std.mem.indexOf(u8, metadata, "MYL_NATIVE_OBJECT_LITERAL_MARK | MYL_NATIVE_OBJECT_SHARED") != null);
    try t.expect(std.mem.indexOf(u8, metadata, "&myl_native_list_header_descriptor") != null);
    try t.expectEqual(@as(i64, 1000), (try native.runWithOptions(&c, .{})).value);
}
// spec-case: LIST-LITERAL-PAYLOAD-1
test "LIST-LITERAL-PAYLOAD-1 primitive widths signed bits boolean and float domains remain exact" {
    const types = [_][]const u8{ "i8", "u8", "i16", "u16", "i32", "u32", "int", "u64", "bool", "float" };
    const values = [_][]const u8{ "-1", "255", "-32768", "65535", "-2147483648", "4294967295", "-9223372036854775808", "18446744073709551615", "True", "1.5" };
    const widths = [_]usize{ 1, 1, 2, 2, 4, 4, 8, 8, 1, 8 };
    const bits = [_][]const u8{
        &.{0xff},
        &.{0xff},
        &.{ 0, 0x80 },
        &.{ 0xff, 0xff },
        &.{ 0, 0, 0, 0x80 },
        &.{ 0xff, 0xff, 0xff, 0xff },
        &.{ 0, 0, 0, 0, 0, 0, 0, 0x80 },
        &.{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff },
        &.{1},
        &.{ 0, 0, 0, 0, 0, 0, 0xf8, 0x3f },
    };
    for (types, values, widths, bits) |ty, value, width, expected| {
        const source = try listSource(t.allocator, ty, value, 64);
        defer t.allocator.free(source);
        var c = try compiler.Compilation.init(t.allocator, "list_width.my", source);
        defer c.deinit();
        try c.emit();
        const code = c.code.?.functions[@backingInt(c.code.?.main)].scope.instructions;
        try t.expect(code[0].op == .make_record);
        try t.expectEqual(@as(usize, 64) * width, code[0].op.make_record.payload.len);
        try t.expectEqualSlices(u8, expected, code[0].op.make_record.payload[0..width]);
        try t.expectEqual(@as(i64, 64), (try native.runWithOptions(&c, .{ .gc_stress = true })).value);
    }
}

// spec-case: LIST-LITERAL-PAYLOAD-1
test "LIST-LITERAL-PAYLOAD-1 legacy literal evaluations allocate distinct mutable lists" {
    const legacy = @import("test_support.zig").LegacySharing.enter();
    defer legacy.restore();
    const source = try literalSource(t.allocator, "def image() -> list[int]:\n    return [", "0", 64,
        \\]
        \\def main() -> int:
        \\    first = image()
        \\    second = image()
        \\    alias = first
        \\    first[0] = 99
        \\    return alias[0] + second[0]
        \\
    );
    defer t.allocator.free(source);
    var c = try compiler.Compilation.init(t.allocator, "list_legacy.my", source);
    defer c.deinit();
    try c.emit();
    try t.expectEqual(@as(i64, 99), (try native.runWithOptions(&c, .{ .gc_stress = true })).value);
}

// spec-case: LIST-LITERAL-PAYLOAD-1
test "LIST-LITERAL-PAYLOAD-1 thousand immortal text and byte elements emit bounded code" {
    for ([_][]const u8{ "str", "bytes" }, [_][]const u8{ "\"é😀\"", "b\"\\x00\\xff\"" }) |ty, value| {
        const source = try listSource(t.allocator, ty, value, 1000);
        defer t.allocator.free(source);
        var c = try compiler.Compilation.init(t.allocator, "list_immortal.my", source);
        defer c.deinit();
        try c.emit();
        const code = c.code.?.functions[@backingInt(c.code.?.main)].scope.instructions;
        try t.expect(code.len < 20);
        try t.expect(code[0].op == .make_record);
        try t.expect(code[0].op.make_record.payload.len < 12_000);
        try t.expectEqual(@as(i64, 1000), (try native.runWithOptions(&c, .{ .gc_stress = true })).value);
    }
}

// spec-case: LIST-LITERAL-PAYLOAD-1
test "LIST-LITERAL-PAYLOAD-1 indexed immortal children keep samples after parent detachment" {
    var text: [480]u8 = undefined;
    for (0..80) |index| @memcpy(text[index * 6 ..][0..6], "é😀");
    const value = try std.fmt.allocPrint(t.allocator, "\"{s}\"", .{text});
    defer t.allocator.free(value);
    const source = try literalSource(t.allocator, "def main() -> int:\n    items: list[str] = [", value, 64,
        \\]
        \\    saved = items
        \\    items[0] = "changed"
        \\    if saved[0][95] != "😀" or saved[63][128] != "é":
        \\        return 1
        \\    if saved[0][127:] != saved[63][127:]:
        \\        return 2
        \\    return len(saved[0])
        \\
    );
    defer t.allocator.free(source);
    var c = try compiler.Compilation.init(t.allocator, "list_indexed_child.my", source);
    defer c.deinit();
    try c.emit();
    const manifest = try c.emitQbe(t.allocator);
    defer t.allocator.free(manifest);
    var parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, manifest, .{ .allocate = .alloc_always });
    defer parsed.deinit();
    const metadata = try outputs.sharedMetadata(t.allocator, parsed.value);
    defer t.allocator.free(metadata);
    try t.expect(std.mem.indexOf(u8, metadata, "MYL_TEXT_STATIC_INDEX") != null);
    try t.expectEqual(@as(i64, 160), (try native.runWithOptions(&c, .{ .gc_stress = true })).value);
}

// spec-case: LIST-LITERAL-PAYLOAD-1
test "LIST-LITERAL-PAYLOAD-1 malformed immutable element framing and UTF8 are rejected" {
    const rows = @import("constant_list_text.zig");
    try t.expect(!rows.valid(&.{ 1, 0, 0 }, true));
    try t.expect(!rows.valid(&.{ 1, 0, 0, 0, 3, 0, 0, 0, 'a' }, true));
    try t.expect(!rows.valid(&.{ 1, 0, 0, 0, 1, 0, 0, 0, 0xff }, true));
    try t.expect(rows.valid(&.{ 1, 0, 0, 0, 1, 0, 0, 0, 0xff }, false));
    try t.expect(!rows.valid(&.{ 1, 0, 0, 0, 0, 0, 0, 0, 1 }, false));
    try t.expect(!rows.valid(&.{ 0, 0, 0, 0 }, false));
    var truncated = rows.Rows.init(&.{ 1, 0, 0, 0, 3, 0, 0, 0, 'a' }).?;
    try t.expectError(error.InvalidPayload, truncated.next());
}

// spec-case: LIST-LITERAL-PAYLOAD-1
test "LIST-LITERAL-PAYLOAD-1 shared immutable images are independent of physical unit order" {
    const first = try literalSource(t.allocator, "def first() -> list[str]:\n    return [", "\"é\"", 64, "]\n");
    defer t.allocator.free(first);
    const second = try literalSource(t.allocator, "def second() -> list[str]:\n    return [", "\"😀\"", 64,
        \\]
        \\def main() -> int:
        \\    return len(first()) + len(second())
        \\
    );
    defer t.allocator.free(second);
    const source = try std.fmt.allocPrint(t.allocator, "{s}{s}", .{ first, second });
    defer t.allocator.free(source);
    var c = try compiler.Compilation.init(t.allocator, "list_order.my", source);
    defer c.deinit();
    try c.emit();
    const manifest = try c.emitQbe(t.allocator);
    defer t.allocator.free(manifest);
    var parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, manifest, .{ .allocate = .alloc_always });
    defer parsed.deinit();
    const before = try outputs.sharedMetadata(t.allocator, parsed.value);
    defer t.allocator.free(before);
    std.mem.reverse(std.json.Value, parsed.value.object.getPtr("functions").?.array.items);
    const after = try outputs.sharedMetadata(t.allocator, parsed.value);
    defer t.allocator.free(after);
    try t.expectEqualSlices(u8, before, after);
    try t.expectEqual(@as(usize, 2), std.mem.count(u8, before, "void *storage[64]"));
}

// spec-case: LIST-LITERAL-PAYLOAD-1
test "LIST-LITERAL-PAYLOAD-1 older image evaluations retain younger-store refusal" {
    const mode = @import("runtime_mode.zig");
    const previous = mode.get();
    defer mode.set(previous);
    mode.set(.rc);
    const prefix = "def stash(items: mut list[str], value: str):\n    items[0] = value\ndef main() -> int:\n    items: list[str] = [";
    const source = try literalSource(t.allocator, prefix, "\"base\"", 64,
        \\]
        \\    with arena():
        \\        stash(mut items, "abc"[1:])
        \\    return 0
        \\
    );
    defer t.allocator.free(source);
    var c = try compiler.Compilation.init(t.allocator, "list_older.my", source);
    defer c.deinit();
    try c.emit();
    for ([_]bool{ false, true }) |stress| {
        const outcome = try native.runWithOptions(&c, .{ .gc_stress = stress });
        try t.expect(outcome.trapped());
        try t.expectEqualStrings("R_ARENA_ESCAPE", outcome.trap.code);
    }
}

// spec-case: LIST-LITERAL-PAYLOAD-1
test "LIST-LITERAL-PAYLOAD-1 malformed stride and boolean payloads fail the bytecode boundary" {
    for ([_][]const u8{ "bool", "int" }) |ty| {
        const source = try listSource(t.allocator, ty, if (std.mem.eql(u8, ty, "bool")) "True" else "17", 64);
        defer t.allocator.free(source);
        var c = try compiler.Compilation.init(t.allocator, "list_invalid.my", source);
        defer c.deinit();
        try c.emit();
        const op = &@constCast(c.code.?.functions[@backingInt(c.code.?.main)].scope.instructions)[0].op;
        try t.expect(op.* == .make_record);
        if (std.mem.eql(u8, ty, "bool")) @constCast(op.make_record.payload)[0] = 2 else op.make_record.payload = op.make_record.payload[0 .. op.make_record.payload.len - 1];
        try t.expectError(error.InternalError, bytecode.validate(t.allocator, c.code.?));
    }
}

// spec-case: LIST-LITERAL-PAYLOAD-1
test "LIST-LITERAL-PAYLOAD-1 a packed list rejects competing embedded blob authority" {
    for ([_][]const u8{ "int", "str", "bytes" }, [_][]const u8{ "17", "\"é\"", "b\"x\"" }) |ty, value| {
        const source = try listSource(t.allocator, ty, value, 64);
        defer t.allocator.free(source);
        var c = try compiler.Compilation.init(t.allocator, "list_blob_conflict.my", source);
        defer c.deinit();
        try c.emit();
        try bytecode.validate(t.allocator, c.code.?);
        const op = &@constCast(c.code.?.functions[@backingInt(c.code.?.main)].scope.instructions)[0].op;
        try t.expect(op.* == .make_record and op.make_record.payload.len != 0);
        const blob: @import("typed.zig").Blob = .{ .digest = @splat(0), .length = op.make_record.payload.len };
        op.make_record.blob = &blob;
        try t.expectError(error.InternalError, bytecode.validate(t.allocator, c.code.?));
    }
}
