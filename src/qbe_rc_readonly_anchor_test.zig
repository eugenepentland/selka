//! RC-READONLY-ANCHOR-1: values read out of read-only parameters take no token.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const interval =
    \\union Value:
    \\    nil,
    \\    number: float
    \\record Frame:
    \\    code: list[int]
    \\    ip: int
    \\record Runtime:
    \\    stack: list[Value]
    \\    top: int
    \\def next(frame: mut Frame) -> int:
    \\    frame.ip = frame.ip + 1
    \\    return frame.code[frame.ip - 1]
    \\def fetch(rt: mut Runtime, frame: mut Frame) -> Value:
    \\    rt.top = rt.top + 1
    \\    return rt.stack[next(mut frame)]
    \\def shrink(rt: mut Runtime) -> int:
    \\    rt.stack = [Value.nil]
    \\    return 0
    \\def replaced(rt: mut Runtime) -> Value:
    \\    return rt.stack[shrink(mut rt)]
    \\def main() -> int:
    \\    rt = Runtime([Value.nil, Value.number(1.0)], 0)
    \\    frame = Frame([1, 0], 0)
    \\    first = fetch(mut rt, mut frame)
    \\    second = replaced(mut rt)
    \\    return rt.top + len(rt.stack)
;
const operand =
    \\record Table:
    \\    entries: list[int]
    \\record Runtime:
    \\    globals: Table
    \\    names: list[str]
    \\    top: int
    \\def lookup(t: Table, at: int) -> int:
    \\    return t.entries[at]
    \\def hash_of(rt: Runtime, at: int) -> int:
    \\    return len(rt.names[at])
    \\def global(rt: mut Runtime, at: int) -> int:
    \\    rt.top = rt.top + 1
    \\    return lookup(rt.globals, hash_of(rt, at))
    \\def reset(rt: mut Runtime) -> int:
    \\    rt.globals = Table([5])
    \\    return 0
    \\def reset_global(rt: mut Runtime) -> int:
    \\    return lookup(rt.globals, reset(mut rt))
    \\def main() -> int:
    \\    rt = Runtime(Table([1, 2]), ["a", "b"], 0)
    \\    return global(mut rt, 1) + reset_global(mut rt)
;
const source =
    \\record Chunk:
    \\    code: list[int]
    \\record Function:
    \\    arity: int
    \\    chunk: Chunk
    \\union Obj:
    \\    free,
    \\    function: Function
    \\record Runtime:
    \\    objects: list[Obj]
    \\    count: int
    \\def arity(rt: Runtime, at: int) -> int:
    \\    match rt.objects[at]:
    \\        case Obj.function(payload):
    \\            return payload.arity + len(payload.chunk.code)
    \\        case _:
    \\            return -1
    \\def code(rt: Runtime, at: int) -> list[int]:
    \\    match rt.objects[at]:
    \\        case Obj.function(payload):
    \\            return payload.chunk.code
    \\        case _:
    \\            return []
    \\def mutated(rt: mut Runtime, at: int) -> int:
    \\    rt.count = at
    \\    match rt.objects[at]:
    \\        case Obj.function(payload):
    \\            return payload.arity
    \\        case _:
    \\            return -1
    \\def main() -> int:
    \\    rt = Runtime([Obj.function(Function(2, Chunk([7])))], 1)
    \\    return arity(rt, 0) + len(code(rt, 0)) + mutated(mut rt, 0)
;

fn operations(name: []const u8) !usize {
    return operationsIn(source, name);
}

fn operationsIn(program: []const u8, name: []const u8) !usize {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "rc_readonly_anchor.my", program);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    var manifest = try std.json.parseFromSlice(Manifest, t.allocator, text, .{ .ignore_unknown_fields = true });
    defer manifest.deinit();
    for (manifest.value.functions) |function| {
        if (!std.mem.eql(u8, function.name, name)) continue;
        const il = function.il;
        return std.mem.count(u8, il, "# RC-GLUE-1 loan") + std.mem.count(u8, il, "# RC-GLUE-1 retain");
    }
    return error.TestUnexpectedResult;
}

// spec: RC-READONLY-ANCHOR-1
test "RC reads out of a read-only parameter take no loan or payload retain" {
    try t.expectEqual(@as(usize, 0), try operations("arity"));
}

// spec-case: RC-READONLY-ANCHOR-1
test "RC anchored reads still copy into returned owners and mut roots keep tokens" {
    try t.expect(try operations("code") > 0);
    try t.expect(try operations("mutated") > 0);
}

// spec: RC-INTERVAL-ANCHOR-1
test "RC list temporaries of a mut record root borrow across calls that do not receive it" {
    try t.expectEqual(@as(usize, 0), try operationsIn(interval, "fetch"));
}

// spec-case: RC-INTERVAL-ANCHOR-1
test "RC list temporaries keep their loan across a call that receives the root" {
    try t.expect(try operationsIn(interval, "replaced") > 0);
}

// spec-case: RC-INTERVAL-ANCHOR-1
test "RC interval anchors cover every list temporary of a long function" {
    var text: std.Io.Writer.Allocating = .init(t.allocator);
    defer text.deinit();
    const w = &text.writer;
    try w.writeAll("union Value:\n    nil,\n    number: float\nrecord Frame:\n    code: list[int]\n    ip: int\nrecord Runtime:\n    stack: list[Value]\n    top: int\n");
    try w.writeAll("def next(frame: mut Frame) -> int:\n    frame.ip = frame.ip + 1\n    return frame.code[0]\n");
    try w.writeAll("def long(rt: mut Runtime, frame: mut Frame) -> int:\n    rt.top = 0\n    total = 0\n");
    for (0..40) |_| try w.writeAll("    match rt.stack[next(mut frame)]:\n        case Value.nil:\n            total += 1\n        case _:\n            total += 2\n");
    try w.writeAll("    return total\n");
    try w.writeAll("def main() -> int:\n    rt = Runtime([Value.nil], 0)\n    frame = Frame([0], 0)\n    return long(mut rt, mut frame)\n");
    try t.expectEqual(@as(usize, 0), try operationsIn(text.written(), "long"));
}

// spec: RC-OPERAND-ANCHOR-1
test "RC field reads of a mut root passed straight to a call take no loan" {
    try t.expectEqual(@as(usize, 0), try operationsIn(operand, "global"));
}

// spec-case: RC-OPERAND-ANCHOR-1
test "RC field reads keep their loan when the root is passed mut before the call" {
    try t.expect(try operationsIn(operand, "reset_global") > 0);
}
