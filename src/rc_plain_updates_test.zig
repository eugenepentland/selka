//! RC-PLAIN-UPDATE-CALL-1: count-free field updates of a `mut` record root.
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
    \\    constants: list[Value]
    \\    code: list[int]
    \\    ip: int
    \\def read_byte(frame: mut Frame) -> int:
    \\    byte = frame.code[frame.ip]
    \\    frame.ip = frame.ip + 1
    \\    return byte
    \\def forward(frame: mut Frame) -> int:
    \\    frame.ip = frame.ip + 0
    \\    return read_byte(mut frame)
    \\def read_constant(frame: mut Frame) -> Value:
    \\    return frame.constants[read_byte(mut frame)]
    \\def read_forwarded(frame: mut Frame) -> Value:
    \\    return frame.constants[forward(mut frame)]
    \\def reload(frame: mut Frame) -> int:
    \\    frame.constants = [Value.nil]
    \\    return 0
    \\def grow(frame: mut Frame) -> int:
    \\    frame.code.append(0)
    \\    return 0
    \\def read_reloaded(frame: mut Frame) -> Value:
    \\    return frame.constants[reload(mut frame)]
    \\def read_grown(frame: mut Frame) -> Value:
    \\    return frame.constants[grow(mut frame)]
    \\def main() -> int:
    \\    frame = Frame([Value.number(1.0), Value.nil], [1, 0, 0, 0], 0)
    \\    first = read_constant(mut frame)
    \\    second = read_forwarded(mut frame)
    \\    third = read_reloaded(mut frame)
    \\    fourth = read_grown(mut frame)
    \\    return frame.ip
;

fn loans(name: []const u8) !usize {
    return loansIn(source, name);
}

fn loansIn(program: []const u8, name: []const u8) !usize {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "rc_plain_updates.my", program);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    var manifest = try std.json.parseFromSlice(Manifest, t.allocator, text, .{ .ignore_unknown_fields = true });
    defer manifest.deinit();
    for (manifest.value.functions) |function| {
        if (std.mem.eql(u8, function.name, name)) return std.mem.count(u8, function.il, "# RC-GLUE-1 loan");
    }
    return error.TestUnexpectedResult;
}

// spec: RC-PLAIN-UPDATE-CALL-1
test "RC borrows of a mut root survive calls that only update its count-free fields" {
    try t.expectEqual(@as(usize, 0), try loans("read_constant"));
    try t.expectEqual(@as(usize, 0), try loans("read_forwarded"));
}

// spec-case: RC-PLAIN-UPDATE-CALL-1
test "RC borrows keep their loan across calls that replace or mutate a counted field" {
    try t.expect(try loans("read_reloaded") > 0);
    try t.expect(try loans("read_grown") > 0);
}

const paths =
    \\record Frame:
    \\    rows: list[list[int]]
    \\    ip: int
    \\def push(values: mut list[int]):
    \\    values.append(7)
    \\def replace_first(rows: mut list[list[int]]):
    \\    rows[0] = [42]
    \\def nested(frame: mut Frame) -> int:
    \\    frame.rows[0].append(5)
    \\    return 0
    \\def field_argument(frame: mut Frame) -> int:
    \\    replace_first(mut frame.rows)
    \\    return 0
    \\def element_argument(frame: mut Frame) -> int:
    \\    push(mut frame.rows[0])
    \\    return 0
    \\def step(frame: mut Frame) -> int:
    \\    frame.ip = frame.ip + 1
    \\    return 0
    \\def read_step(frame: mut Frame) -> int:
    \\    return len(frame.rows[step(mut frame)])
    \\def read_nested(frame: mut Frame) -> int:
    \\    return len(frame.rows[nested(mut frame)])
    \\def read_field_argument(frame: mut Frame) -> int:
    \\    return len(frame.rows[field_argument(mut frame)])
    \\def read_element_argument(frame: mut Frame) -> int:
    \\    return len(frame.rows[element_argument(mut frame)])
    \\def main() -> int:
    \\    frame = Frame([[1, 2], [3]], 0)
    \\    return read_step(mut frame) + read_nested(mut frame) + read_field_argument(mut frame) + read_element_argument(mut frame)
;

// spec: RC-PLAIN-UPDATE-CALL-2
test "RC borrows keep their loan across calls that write through a field path or a mut field argument" {
    // The count-free step lends the receiver; each path writer keeps its loan.
    const lent = try loansIn(paths, "read_step");
    try t.expect(try loansIn(paths, "read_nested") > lent);
    try t.expect(try loansIn(paths, "read_field_argument") > lent);
    try t.expect(try loansIn(paths, "read_element_argument") > lent);
}
