//! RC-LOAN-RELOCATE-1: a loan already held by an operand moves into a private
//! temporary instead of being acquired a second time and dropped.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };

fn relocationsIn(source: []const u8, name: []const u8) !usize {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "rc_loan_relocate.my", source);
    defer compilation.deinit();
    const emitted = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(emitted);
    var manifest = try std.json.parseFromSlice(Manifest, t.allocator, emitted, .{ .ignore_unknown_fields = true });
    defer manifest.deinit();
    for (manifest.value.functions) |function| {
        if (std.mem.eql(u8, function.name, name)) return std.mem.count(u8, function.il, "# RC-LOAN-RELOCATE-1");
    }
    return error.TestUnexpectedResult;
}

const program =
    \\union Value:
    \\    nil,
    \\    number: float
    \\record Runtime:
    \\    stack: list[Value]
    \\    top: int
    \\def pop(rt: mut Runtime) -> Value:
    \\    rt.top = rt.top - 1
    \\    return rt.stack[rt.top]
    \\def total(values: list[float]) -> float:
    \\    sum = 0.0
    \\    for value in values:
    \\        sum += value
    \\    return sum
    \\def main() -> int:
    \\    rt = Runtime([Value.nil, Value.number(2.0)], 2)
    \\    match pop(mut rt):
    \\        case Value.number(x):
    \\            return int(x + total([1.0]))
    \\        case _:
    \\            return 0
;

// spec: RC-LOAN-RELOCATE-1
test "RC loaned field read stored into its index temporary relocates the loan" {
    try t.expect(try relocationsIn(program, "pop") > 0);
}

// spec-case: RC-LOAN-RELOCATE-1
test "RC plain loop reads keep ordinary lowering without relocation" {
    try t.expectEqual(@as(usize, 0), try relocationsIn(program, "total"));
}
