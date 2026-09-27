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

fn returnPath(a: std.mem.Allocator, source: []const u8) ![]const u8 {
    const output = try text(a, source);
    defer a.free(output);
    const start = std.mem.indexOf(u8, output, "\n@rcfreshreturn") orelse return a.dupe(u8, "");
    const rest = output[start + 1 ..];
    const end = std.mem.indexOf(u8, rest, "\n@rcfreshreturnslow") orelse return error.TestUnexpectedResult;
    return a.dupe(u8, rest[0..end]);
}

// spec: RC-FRESH-RETURN-1
test "RC-FRESH-RETURN-1 completed linear result skips normal cleanup but keeps leave" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc_counting);
    const output = try returnPath(t.allocator, fresh);
    defer t.allocator.free(output);
    try t.expect(std.mem.indexOf(u8, output, "blit ") != null);
    try t.expect(std.mem.indexOf(u8, output, "call $myl_qbe_rc_frame_leave") != null);
    try t.expect(std.mem.indexOf(u8, output, "call $myl_qbe_rc_frame_cleanup") == null);
    try t.expect(std.mem.indexOf(u8, output, "call $myl_rc_native_take") == null);
    try t.expect(std.mem.indexOf(u8, output, "call $memset") == null);
}

// spec-case: RC-FRESH-RETURN-1
test "RC-FRESH-RETURN-1 aliases managed locals and uncertified calls retain generic return" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc_counting);
    const alias = try returnPath(t.allocator, aliased);
    defer t.allocator.free(alias);
    const called = try returnPath(t.allocator, foreign);
    defer t.allocator.free(called);
    const branch = try returnPath(t.allocator, mixed);
    defer t.allocator.free(branch);
    try t.expectEqual(@as(usize, 0), alias.len);
    try t.expectEqual(@as(usize, 0), called.len);
    try t.expectEqual(@as(usize, 0), branch.len);
}

// spec-case: RC-FRESH-RETURN-1
test "RC-FRESH-RETURN-1 trap journal and ordinary role fallback remain emitted" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc_counting);
    const output = try text(t.allocator, fresh);
    defer t.allocator.free(output);
    try t.expect(std.mem.indexOf(u8, output, "call $myl_qbe_rc_frame_enter") != null);
    try t.expect(std.mem.indexOf(u8, output, "@rcfreshreturnslow") != null);
    try t.expect(std.mem.indexOf(u8, output, "call $myl_rc_native_take") != null);
    try t.expect(std.mem.indexOf(u8, output, "call $myl_qbe_rc_frame_cleanup") != null);
    try t.expect(std.mem.indexOf(u8, output, "call $myl_qbe_fail_frame") != null);
}

// spec-case: RC-FRESH-RETURN-1
test "RC-FRESH-RETURN-1 wide owned results keep the generic ABI handoff" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc_counting);
    const input = node ++
        \\record Wide:
        \\    child: Option[Node]
        \\    padding: [32]int
        \\def make(depth: int) -> Wide:
        \\    return Wide(None, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        \\def main() -> int:
        \\    result = make(0)
        \\    return 0
    ;
    const output = try functionText(t.allocator, input);
    defer t.allocator.free(output);
    try t.expect(std.mem.indexOf(u8, output, "@rcfresh") != null);
    try t.expect(std.mem.indexOf(u8, output, "@rcfreshreturn") == null);
    try t.expect(std.mem.indexOf(u8, output, "@rcspan") == null);
    try t.expect(std.mem.indexOf(u8, output, "call $myl_qbe_rc_frame_cleanup") != null);
}

fn spanPath(a: std.mem.Allocator, body: []const u8, needle: []const u8) ![]const u8 {
    const output = try text(a, body);
    defer a.free(output);
    var rest = output;
    while (std.mem.indexOf(u8, rest, "\n@rcspan")) |start| {
        rest = rest[start + 1 ..];
        if (!std.ascii.isDigit(rest[7])) continue;
        const end = std.mem.indexOf(u8, rest, "\n@rcspanslow") orelse return error.TestUnexpectedResult;
        const candidate = rest[0..end];
        if (std.mem.indexOf(u8, candidate, needle) != null) return a.dupe(u8, candidate);
        rest = rest[end + 1 ..];
    }
    return a.dupe(u8, "");
}

// spec: RC-FRESH-SPAN-1
test "RC-FRESH-SPAN-1 allocation retains inputs then publishes one complete owner" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc_counting);
    const span = try spanPath(t.allocator, fresh, "call $myl_native_heap_alloc");
    defer t.allocator.free(span);
    const allocation = std.mem.indexOf(u8, span, "call $myl_native_heap_alloc") orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.indexOf(u8, span[0..allocation], "storew 0,") == null);
    try t.expect(std.mem.indexOf(u8, span, "call $myl_qbe_fail_allocation") != null);
    try t.expect(std.mem.indexOf(u8, span, "call $myl_rc_native_") == null);
    try t.expect(std.mem.indexOf(u8, span, "storew 4,") == null);
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, span, " storew 1,"));
}

// spec-case: RC-FRESH-SPAN-1
test "RC-FRESH-SPAN-1 whole ordinary fallback retains construction and transfer guards" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc_counting);
    const output = try text(t.allocator, fresh);
    defer t.allocator.free(output);
    try t.expect(std.mem.indexOf(u8, output, "@rcspanslow") != null);
    try t.expect(std.mem.indexOf(u8, output, "storew 4,") != null);
    try t.expect(std.mem.indexOf(u8, output, "call $myl_rc_native_take") != null);
    try t.expect(std.mem.indexOf(u8, output, "call $myl_qbe_rc_frame_enter") != null);
}

// spec-case: RC-FRESH-SPAN-1
test "RC-FRESH-SPAN-1 aliases callbacks holds and arena transitions refuse the span" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc_counting);
    const alias = try text(t.allocator, aliased);
    defer t.allocator.free(alias);
    const callback = try text(t.allocator, indirect);
    defer t.allocator.free(callback);
    const view = try text(t.allocator, held);
    defer t.allocator.free(view);
    const region = try text(t.allocator, arena);
    defer t.allocator.free(region);
    try t.expect(std.mem.indexOf(u8, alias, "@rcspan") == null);
    try t.expect(std.mem.indexOf(u8, callback, "@rcspan") == null);
    try t.expect(std.mem.indexOf(u8, view, "@rcspan") == null);
    try t.expect(std.mem.indexOf(u8, region, "@rcspan") == null);
}

// spec-case: RC-FRESH-SPAN-1
test "RC-FRESH-SPAN-1 fallible result metadata keeps the ordinary constructor" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc_counting);
    const output = try functionText(t.allocator, node ++
        \\def make(depth: int) -> Result[Node, int]:
        \\    return Ok(Node(None, None))
        \\def main() -> int:
        \\    match make(0):
        \\        case Ok(value):
        \\            return 0
        \\        case Err(code):
        \\            return code
    );
    defer t.allocator.free(output);
    try t.expect(std.mem.indexOf(u8, output, "@rcspan") == null);
}

// spec-case: RC-FRESH-SPAN-1
test "RC-FRESH-SPAN-1 incoming unique finalizers retain the complete journal" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc_counting);
    const output = try functionText(t.allocator, node ++
        \\def make(depth: int, input: TextFile) -> Node:
        \\    return Node(None, None)
        \\def main() -> int:
        \\    return 0
    );
    defer t.allocator.free(output);
    try t.expect(std.mem.indexOf(u8, output, "@rcspan") == null);
    try t.expect(std.mem.indexOf(u8, output, "call $myl_qbe_rc_frame_cleanup") != null);
}
