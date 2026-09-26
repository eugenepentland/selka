//! Fresh constructor admission must prove physical linearity, not only no SHARE.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const node =
    \\record Node:
    \\    left: Option[Node]
    \\    right: Option[Node]
    \\
;
const fresh =
    \\def make(depth: int) -> Node:
    \\    if depth == 0:
    \\        return Node(None, None)
    \\    return Node(Some(make(depth - 1)), Some(make(depth - 1)))
;
const aliased =
    \\def make(depth: int) -> Node:
    \\    if depth == 0:
    \\        return Node(None, None)
    \\    child: Option[Node] = Some(make(depth - 1))
    \\    return Node(child, child)
;
const foreign =
    \\def other(depth: int) -> Node:
    \\    return Node(None, None)
    \\def make(depth: int) -> Node:
    \\    return Node(Some(other(depth)), None)
;
const mixed =
    \\def make(depth: int) -> Node:
    \\    if depth == 0:
    \\        return Node(None, None)
    \\    child: Option[Node] = Some(make(depth - 1))
    \\    selected: Option[Node] = None
    \\    if depth == 1:
    \\        selected = child
    \\    else:
    \\        selected = None
    \\    return Node(selected, child)
;
const arena =
    \\def make(depth: int) -> Node:
    \\    with arena() as scratch:
    \\        value = Node(None, None)
    \\        return scratch.escape(value)
;

const indirect =
    \\def make(depth: int) -> Node:
    \\    if depth == 0:
    \\        return Node(None, None)
    \\    action = make
    \\    return Node(Some(action(depth - 1)), None)
;
const capture =
    \\def make(depth: int) -> Node:
    \\    items = [Node(None, None)]
    \\    value = items[0]
    \\    return Node(Some(value), None)
;
const held =
    \\def make(depth: int) -> Node:
    \\    mapping = {1: 7}
    \\    view = mapping.values()
    \\    return Node(None, None)
;

fn text(a: std.mem.Allocator, body: []const u8) ![]const u8 {
    const input = try std.fmt.allocPrint(a, "{s}{s}\ndef main() -> int:\n    value = make(3)\n    return 0\n", .{ node, body });
    defer a.free(input);
    return functionText(a, input);
}

fn functionText(a: std.mem.Allocator, input: []const u8) ![]const u8 {
    var compilation = try compiler.Compilation.init(a, "fresh.my", input);
    defer compilation.deinit();
    const output = try compilation.emitQbeWithOptions(a, .{ .step_checks = false, .frame_checks = true });
    defer a.free(output);
    var manifest = try std.json.parseFromSlice(Manifest, a, output, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer manifest.deinit();
    for (manifest.value.functions) |function| if (std.mem.eql(u8, function.name, "make")) return a.dupe(u8, function.il);
    return error.TestUnexpectedResult;
}

fn admitted(a: std.mem.Allocator, source: []const u8) !bool {
    const output = try text(a, source);
    defer a.free(output);
    return std.mem.indexOf(u8, output, "@rcfresh") != null;
}

// spec: RC-FRESH-CONSTRUCTOR-1
test "RC-FRESH-CONSTRUCTOR-1 linear recursive owners relocate into the guarded body" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc_counting);
    const output = try text(t.allocator, fresh);
    defer t.allocator.free(output);
    try t.expect(std.mem.indexOf(u8, output, "@rcfresh") != null);
    try t.expect(std.mem.indexOf(u8, output, "call $myl_rc_native_take") != null);
    try t.expect(std.mem.indexOf(u8, output, "call $myl_qbe_rc_frame_enter") != null);
    try t.expect(std.mem.indexOf(u8, output, "call $myl_qbe_fail_allocation") != null);
}

// spec-case: RC-FRESH-CONSTRUCTOR-1
test "RC-FRESH-CONSTRUCTOR-1 immutable aliases and mixed branch provenance refuse" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc_counting);
    try t.expect(!try admitted(t.allocator, aliased));
    try t.expect(!try admitted(t.allocator, mixed));
}

// spec-case: RC-FRESH-CONSTRUCTOR-1
test "RC-FRESH-CONSTRUCTOR-1 uncertified callees and arena transitions refuse" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc_counting);
    try t.expect(!try admitted(t.allocator, foreign));
    try t.expect(!try admitted(t.allocator, arena));
}

// spec-case: RC-FRESH-CONSTRUCTOR-1
test "RC-FRESH-CONSTRUCTOR-1 indirect calls physical loans and H roles refuse" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc_counting);
    try t.expect(!try admitted(t.allocator, indirect));
    try t.expect(!try admitted(t.allocator, capture));
    try t.expect(!try admitted(t.allocator, held));
}

// spec-case: RC-FRESH-CONSTRUCTOR-1
test "RC-FRESH-CONSTRUCTOR-1 managed incoming obligations refuse even when unused" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc_counting);
    const output = try functionText(t.allocator, node ++
        \\def make(incoming: Node) -> Node:
        \\    return Node(None, None)
        \\def main() -> int:
        \\    result = make(Node(None, None))
        \\    return 0
    );
    defer t.allocator.free(output);
    try t.expect(std.mem.indexOf(u8, output, "@rcfresh") == null);
}
