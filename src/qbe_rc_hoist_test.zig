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
    \\        mutation_result_24 = callback(mut items)
    \\        items[mutation_result_24] = at
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

const buffer_source =
    \\def appended(count: int) -> byte_buffer:
    \\    empty: list[int] = []
    \\    buffer = byte_buffer(empty)
    \\    piece = b"ab"
    \\    for at in range(count):
    \\        _ = buffer.append_range(piece, 0, 2)
    \\        _ = buffer.append_byte(at % 256)
    \\    return buffer
    \\def snapshots(count: int) -> bytes:
    \\    empty: list[int] = []
    \\    buffer = byte_buffer(empty)
    \\    before = bytes(buffer)
    \\    for at in range(count):
    \\        before = bytes(buffer)
    \\        _ = buffer.append_byte(at % 256)
    \\    return before
    \\def grow(buffer: mut byte_buffer) -> int:
    \\    _ = buffer.append_byte(1)
    \\    return 2
    \\def calls(count: int) -> byte_buffer:
    \\    empty: list[int] = []
    \\    buffer = byte_buffer(empty)
    \\    for at in range(count):
    \\        value = grow(mut buffer)
    \\        _ = buffer.append_byte(value)
    \\    return buffer
    \\def main() -> int:
    \\    return len(appended(2))
;
fn emittedBuffers() !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "rc_buffer_hoist.my", buffer_source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
// spec: RC-BUFFER-HOIST-1
test "RC-BUFFER-HOIST-1 a byte_buffer append loop checks uniqueness once at its entry" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emittedBuffers();
    defer manifest.deinit();
    const appended = try named(manifest.value, "appended");
    const entry = std.mem.indexOf(u8, appended, "@ce") orelse return error.TestUnexpectedResult;
    const check = std.mem.indexOf(u8, appended, "$myl_qbe_rc_unique_local(") orelse return error.TestUnexpectedResult;
    try t.expect(check > entry);
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, appended, "$myl_qbe_rc_unique_local("));
    try t.expect(std.mem.indexOf(u8, try named(manifest.value, "snapshots"), "@ce") == null);
    try t.expect(std.mem.indexOf(u8, try named(manifest.value, "calls"), "@ce") == null);
}
