//! Empty-edge early returns retain the full ownership path on every refusal.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const source =
    \\record Node:
    \\    left: Option[Node]
    \\    right: Option[Node]
    \\record Tagged:
    \\    node: Option[Node]
    \\    tag: int
    \\union Choice:
    \\    empty,
    \\    full: Node
    \\def variant(flag: bool) -> Choice:
    \\    if flag:
    \\        return Choice.empty
    \\    return Choice.full(make(1))
    \\def make(depth: int) -> Node:
    \\    if depth == 0:
    \\        return Node(None, None)
    \\    return Node(Some(make(depth - 1)), None)
    \\def boolean(flag: bool) -> Node:
    \\    if not flag:
    \\        return Node(None, None)
    \\    return make(1)
    \\def managed(items: list[int], flag: bool) -> Node:
    \\    if flag:
    \\        return Node(None, None)
    \\    return make(len(items))
    \\def resource(file: TextFile, flag: bool) -> Node:
    \\    if flag:
    \\        return Node(None, None)
    \\    return make(1)
    \\def called(flag: bool) -> Node:
    \\    if flag:
    \\        return make(0)
    \\    return make(1)
    \\def named(flag: bool) -> Node:
    \\    if flag:
    \\        value = Node(None, None)
    \\        return value
    \\    return make(1)
    \\def nonzero(flag: bool) -> Tagged:
    \\    if flag:
    \\        return Tagged(None, 7)
    \\    return Tagged(Some(make(1)), 3)
    \\def result(flag: bool) -> Result[int, Node]:
    \\    if flag:
    \\        return Ok(0)
    \\    return Err(make(1))
    \\def allocated(flag: bool) -> Node:
    \\    values = [1]
    \\    if flag:
    \\        return Node(None, None)
    \\    return make(values[0])
    \\def scoped(flag: bool) -> Node:
    \\    with arena() as scratch:
    \\        value = [1]
    \\        flag = len(value) == 1
    \\    if flag:
    \\        return Node(None, None)
    \\    return make(1)
    \\def main() -> int:
    \\    return 0
;

fn emitted(steps: bool, frames: bool) !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "rc_inert_return.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbeWithOptions(t.allocator, .{ .step_checks = steps, .frame_checks = frames });
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

// spec: RC-INERT-RETURN-1
test "RC-INERT-RETURN-1 null constructors return after admission before journal setup" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc_counting);
    var manifest = try emitted(false, false);
    defer manifest.deinit();
    for ([_][]const u8{ "make", "boolean", "variant" }) |name| {
        const text = try named(manifest.value, name);
        const start = std.mem.indexOf(u8, text, "\n@rcinertreturn") orelse return error.TestUnexpectedResult;
        const end = std.mem.indexOf(u8, text, "\n@rcinertfallback") orelse return error.TestUnexpectedResult;
        const enter = std.mem.indexOf(u8, text, "# rc-frame") orelse return error.TestUnexpectedResult;
        const floor = std.mem.indexOf(u8, text, "call $myl_qbe_fail_frame") orelse return error.TestUnexpectedResult;
        try t.expect(floor < start and end < enter);
        try t.expect(contains(text[start..end], " ret %v"));
        try t.expect(!contains(text[start..end], "call $") and !contains(text[start..end], "%rcg"));
        try t.expect(contains(text[enter..], "# rc-exit"));
    }
}

// spec-case: RC-INERT-RETURN-1
test "RC-INERT-RETURN-1 resources effects sharing and nonzero bytes retain the journal" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted(false, false);
    defer manifest.deinit();
    for ([_][]const u8{ "managed", "resource", "called", "named", "nonzero", "result", "allocated", "scoped", "main" }) |name|
        try t.expect(!contains(try named(manifest.value, name), "@rcinertreturn"));
}

// spec-case: RC-INERT-RETURN-1
test "RC-INERT-RETURN-1 frame accounting remains and step accounting declines" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var framed = try emitted(false, true);
    defer framed.deinit();
    const make = try named(framed.value, "make");
    try t.expect(contains(make, "@rcinertreturn") and contains(make, "call $myl_qbe_fail_frame"));
    var stepped = try emitted(true, true);
    defer stepped.deinit();
    try t.expect(!contains(try named(stepped.value, "make"), "@rcinertreturn"));
    runtime.set(.gc);
    var gc = try emitted(false, false);
    defer gc.deinit();
    try t.expect(!contains(try named(gc.value, "make"), "@rcinertreturn"));
}
