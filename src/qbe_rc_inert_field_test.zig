//! RC-INERT-FIELD-RECEIVER-1: list receivers filled from a named record's field.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const source =
    \\union Value:
    \\    nil,
    \\    number: float
    \\record Frame:
    \\    ip: int
    \\    base: int
    \\record Runtime:
    \\    stack: list[Value]
    \\    frames: list[Frame]
    \\    names: list[str]
    \\    top: int
    \\    count: int
    \\def push(rt: mut Runtime, item: Value):
    \\    rt.stack[rt.top] = item
    \\    rt.top = rt.top + 1
    \\def step(rt: mut Runtime, ip: int):
    \\    rt.frames[rt.count - 1].ip = ip
    \\def local_root(item: Value) -> int:
    \\    rt = Runtime([Value.nil], [], [], 0, 0)
    \\    rt.stack[rt.top] = item
    \\    return len(rt.stack)
    \\def bump(rt: mut Runtime) -> int:
    \\    rt.stack = [Value.nil, Value.nil]
    \\    return 1
    \\def callback(rt: mut Runtime, item: Value):
    \\    rt.stack[bump(mut rt)] = item
    \\def managed(rt: mut Runtime, name: str):
    \\    rt.names[0] = name
    \\def main() -> int:
    \\    rt = Runtime([Value.nil], [Frame(0, 0)], ["a"], 0, 1)
    \\    push(mut rt, Value.number(1.0))
    \\    step(mut rt, 3)
    \\    callback(mut rt, Value.nil)
    \\    managed(mut rt, "b")
    \\    return local_root(Value.nil) + rt.top
;

fn scopes(name: []const u8) !usize {
    return count(name, false);
}

fn operations(name: []const u8) !usize {
    return count(name, true);
}

fn count(name: []const u8, loans: bool) !usize {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "rc_inert_field.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    var manifest = try std.json.parseFromSlice(Manifest, t.allocator, text, .{ .ignore_unknown_fields = true });
    defer manifest.deinit();
    for (manifest.value.functions) |function| {
        if (!std.mem.eql(u8, function.name, name)) continue;
        const lent = if (loans) std.mem.count(u8, function.il, "# RC-GLUE-1 loan") else 0;
        return std.mem.count(u8, function.il, "call $myl_qbe_rc_scope_begin") + lent;
    }
    return error.TestUnexpectedResult;
}

// spec: RC-INERT-FIELD-RECEIVER-1
test "RC field receivers of a named record need no loan or receiver scope" {
    try t.expectEqual(@as(usize, 0), try operations("push"));
    try t.expectEqual(@as(usize, 0), try operations("step"));
    try t.expectEqual(@as(usize, 0), try scopes("local_root"));
}

// spec-case: RC-INERT-FIELD-RECEIVER-1
test "RC field receivers keep scopes across callbacks" {
    try t.expect(try scopes("callback") > 0);
}

// spec-case: RC-INERT-COUNTED-RECEIVER-1
test "RC field receivers storing a counted element loaded right before the write need no scope" {
    try t.expectEqual(@as(usize, 0), try scopes("managed"));
}
