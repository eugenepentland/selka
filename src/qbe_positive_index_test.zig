//! Positive reads keep the original normalization and accounting fallbacks.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const native = @import("native_execute.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const source =
    \\record Frame:
    \\    code: list[int]
    \\    ip: int
    \\def read(frame: mut Frame) -> int:
    \\    value = frame.code[frame.ip]
    \\    frame.ip += 1
    \\    return value
    \\def byte(values: list[u8], index: int) -> u8:
    \\    return values[index]
    \\def managed(values: list[list[int]], index: int) -> int:
    \\    value = values[index]
    \\    return len(value)
    \\record Point:
    \\    x: int
    \\def mutate(values: mut list[Point], index: int):
    \\    values[index].x = 23
    \\def main() -> int:
    \\    frame = Frame([7, 11], 0)
    \\    return read(mut frame)
;
fn emitted(steps: bool) !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "positive_index.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbeWithOptions(t.allocator, .{ .step_checks = steps });
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

// spec-case: QBE-POSITIVE-INDEX-1
test "positive index refuses try result and every explicit extra join edge" {
    const bytecode = @import("bytecode.zig");
    const proof = @import("qbe_positive_index.zig");
    const span: @import("source.zig").Span = .{ .start = 0, .end = 0 };
    const start = 2;
    const join = start + 9;
    var code: [15]bytecode.Instruction = @splat(.{ .span = span, .op = .push_unit });
    code[start + 3].op = .{ .jump_if_false = join };
    try t.expect(!proof.extraEntry(&code, start));
    // Both forward propagation and a later/back edge could enter the join
    // without executing this normalizer. It is exempt from isBranchTarget.
    for ([_]usize{ 0, 14 }) |pc| {
        code[pc].op = .{ .try_result = .{ .input = .i64, .output = .i64, .error_target = join } };
        try t.expect(proof.extraEntry(&code, start));
        code[pc].op = .{ .try_result = .{ .input = .i64, .output = .i64, .error_target = start } };
        try t.expect(!proof.extraEntry(&code, start));
        code[pc].op = .push_unit;
    }
    code[14].op = .{ .jump = join };
    try t.expect(proof.extraEntry(&code, start));
    code[14].op = .{ .jump_if_false = join };
    try t.expect(proof.extraEntry(&code, start));
    code[14].op = .{ .switch_variant = .{ .ty = .i64, .arms = &.{ .{ .target = 14, .slot = null }, .{ .target = join, .slot = null } } } };
    try t.expect(proof.extraEntry(&code, start));
    code[14].op = .{ .switch_variant = .{ .ty = .i64, .arms = &.{ .{ .target = start, .slot = null }, .{ .target = start + 11, .slot = null } } } };
    try t.expect(!proof.extraEntry(&code, start));
}

// spec: QBE-POSITIVE-INDEX-1
test "positive index guards keep negative normalization exact traps and record mutation" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted(false);
    defer manifest.deinit();
    const il = try named(manifest.value, "read");
    try t.expect(contains(il, "# QBE-POSITIVE-INDEX-1"));
    try t.expect(contains(il, "@positive"));
    try t.expect(contains(il, "myl_qbe_fail_cast"));
    try t.expect(contains(il, "myl_qbe_fail_overflow_op"));
    try t.expect(contains(il, "myl_qbe_fail_normalized_index_bounds"));
    // An unsigned negative could pass a byte-list bound at extreme capacities;
    // managed leaves also need their ordinary ownership publication.
    try t.expect(!contains(try named(manifest.value, "byte"), "# QBE-POSITIVE-INDEX-1"));
    try t.expect(!contains(try named(manifest.value, "managed"), "# QBE-POSITIVE-INDEX-1"));
    try t.expect(!contains(try named(manifest.value, "mutate"), "# QBE-POSITIVE-INDEX-1"));
}

// spec-case: QBE-POSITIVE-INDEX-1
test "positive index leaves counted instruction and trap positions unchanged" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted(true);
    defer manifest.deinit();
    const il = try named(manifest.value, "read");
    try t.expect(!contains(il, "# QBE-POSITIVE-INDEX-1"));
    try t.expect(contains(il, ", @step_limit,"));
    try t.expect(contains(il, "myl_qbe_fail_normalized_index_bounds"));
}

// spec-case: QBE-POSITIVE-INDEX-1
test "positive index executes positive negative minimum and empty exact trap fallbacks" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    const cases = [_]struct { values: []const u8, index: i64 }{
        .{ .values = "[7,11]", .index = 0 },
        .{ .values = "[7,11]", .index = -1 },
        .{ .values = "[7,11]", .index = -3 },
        .{ .values = "[7,11]", .index = std.math.minInt(i64) },
        .{ .values = "[7,11]", .index = std.math.maxInt(i64) },
        .{ .values = "[]", .index = 0 },
        .{ .values = "[]", .index = -1 },
    };
    for (cases) |case| {
        const template = "def read(values: list[int], index: int) -> int:\n    return values[index]\n" ++
            "def main() -> int:\n    values: list[int] = {s}\n    return read(values, {d})\n";
        const input = try std.fmt.allocPrint(t.allocator, template, .{ case.values, case.index });
        defer t.allocator.free(input);
        var compilation = try compiler.Compilation.init(t.allocator, "positive-fallback.my", input);
        defer compilation.deinit();
        const reference = try native.run(&compilation);
        const fast = try native.runUnaccounted(&compilation, .{});
        try t.expectEqual(reference.failed, fast.failed);
        try t.expectEqual(reference.value, fast.value);
        try t.expectEqualStrings(reference.stderr, fast.stderr);
        try t.expect(std.meta.eql(reference.trap.detail, fast.trap.detail));
    }
}

const snapshots =
    \\record Frame:
    \\    code: list[int]
    \\    ip: int
    \\def read(frame: mut Frame) -> int:
    \\    value = frame.code[frame.ip]
    \\    frame.ip += 1
    \\    return value
    \\def replace(frame: mut Frame) -> int:
    \\    frame.code = [17,19]
    \\    return 0
    \\def select(frame: mut Frame) -> int:
    \\    return frame.code[replace(mut frame)]
    \\def main() -> int:
    \\    frame = Frame([7,11], 0)
    \\    before = frame
    \\    assert read(mut frame) == 7
    \\    frame.code[0] = 13
    \\    assert before.code == [7,11] and before.ip == 0
    \\    assert select(mut frame) == 13
    \\    assert frame.code == [17,19]
    \\    return 0
;

// spec-case: QBE-POSITIVE-INDEX-1
test "positive index unaccounted native COW snapshots and replacement survive collector stress" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "positive-snapshots.my", snapshots);
    defer compilation.deinit();
    for ([_]bool{ false, true }) |_| {
        const outcome = try native.runUnaccounted(&compilation, .{});
        try t.expect(!outcome.failed);
        try t.expectEqual(@as(i64, 0), outcome.value);
    }
}
