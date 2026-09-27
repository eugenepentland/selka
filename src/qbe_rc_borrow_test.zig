//! Separate native entries retain source metadata and canonical owned contracts.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Function = struct { name: []const u8, symbol: []const u8, il: []const u8, locations: []const std.json.Value };
const Manifest = struct { functions: []const Function };

// spec-case: RC-BORROW-ENTRY-1
test "RC-BORROW-ENTRY-1 native alternate owns a separate source map and no intermediate owners" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "rc_borrow.my",
        \\record Span:
        \\    source: bytes
        \\    start: int
        \\def empty() -> Span:
        \\    return Span(b"", 0)
        \\def at(nodes: list[Span], index: int) -> Span:
        \\    if index < 0 or index >= len(nodes):
        \\        return empty()
        \\    return nodes[index]
        \\def main() -> int:
        \\    source = b"abc"
        \\    nodes = [Span(source, 2)]
        \\    value = at(nodes, 0)
        \\    return value.start
    );
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    var manifest = try std.json.parseFromSlice(Manifest, t.allocator, text, .{ .ignore_unknown_fields = true });
    defer manifest.deinit();
    const pair = find(manifest.value);
    const ordinary = pair.canonical orelse return error.TestUnexpectedResult;
    const borrowed = pair.alternate orelse return error.TestUnexpectedResult;
    try t.expectEqual(ordinary.locations.len, borrowed.locations.len);
    try t.expect(borrowed.locations.len > 10);
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, borrowed.il, "export function"));
    const own_map = try std.fmt.allocPrint(t.allocator, "${s}_meta", .{borrowed.symbol});
    defer t.allocator.free(own_map);
    try t.expect(std.mem.indexOf(u8, borrowed.il, own_map) != null);
    try t.expect(std.mem.indexOf(u8, borrowed.il, "call $myl_rc_native_copy") == null);
    try t.expect(std.mem.indexOf(u8, ordinary.il, "call $myl_rc_native_retain") != null);
}

const Pair = struct { canonical: ?Function, alternate: ?Function };
fn find(manifest: Manifest) Pair {
    var canonical: ?Function = null;
    var alternate: ?Function = null;
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, "at")) {
        if (std.mem.endsWith(u8, function.symbol, "_rc_borrow")) alternate = function else canonical = function;
    };
    return .{ .canonical = canonical, .alternate = alternate };
}

// spec-case: RC-BORROW-LOOP-1
test "RC-BORROW-LOOP-1 loop alternate keeps its source map and canonical entry" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "rc_borrow_loop.my",
        \\record Node:
        \\    source: bytes
        \\    key: int
        \\def at(nodes: list[Node], key: int) -> Node:
        \\    i = 0
        \\    while i < len(nodes):
        \\        node = nodes[i]
        \\        if node.key == key:
        \\            return node
        \\        i += 1
        \\    return Node(b"", -1)
        \\def main() -> int:
        \\    nodes = [Node(bytes([65]), 7)]
        \\    value = at(nodes, 7)
        \\    selected = at
        \\    other = selected(nodes, 8)
        \\    return value.key + other.key
    );
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    var manifest = try std.json.parseFromSlice(Manifest, t.allocator, text, .{ .ignore_unknown_fields = true });
    defer manifest.deinit();
    const pair = find(manifest.value);
    const ordinary = pair.canonical orelse return error.TestUnexpectedResult;
    const borrowed = pair.alternate orelse return error.TestUnexpectedResult;
    try t.expectEqual(ordinary.locations.len, borrowed.locations.len);
    try t.expect(std.mem.indexOf(u8, borrowed.il, "call $myl_rc_native_loan") == null);
    try t.expect(std.mem.indexOf(u8, borrowed.il, "call $myl_rc_native_retain") == null);
    try t.expect(std.mem.indexOf(u8, ordinary.il, "call $myl_rc_native_retain") != null);
    const map = try std.fmt.allocPrint(t.allocator, "${s}_meta", .{borrowed.symbol});
    defer t.allocator.free(map);
    try t.expect(std.mem.indexOf(u8, borrowed.il, map) != null);
}
