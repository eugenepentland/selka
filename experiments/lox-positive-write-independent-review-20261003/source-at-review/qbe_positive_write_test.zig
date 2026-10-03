//! A sign guard preserves the entire original indexed-write protocol.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const native = @import("native_execute.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const source =
    \\record State:
    \\    values: list[int]
    \\def field(state: mut State, index: int, item: int):
    \\    state.values[index] = item
    \\def scoped(values: mut list[int], index: int, item: int):
    \\    values[index] = item
    \\record Managed:
    \\    values: list[list[int]]
    \\def managed(state: mut Managed, index: int, item: list[int]):
    \\    state.values[index] = item
    \\record Bytes:
    \\    values: list[u8]
    \\def byte(state: mut Bytes, index: int, item: u8):
    \\    state.values[index] = item
    \\def replace(state: mut State) -> int:
    \\    state.values = [17,19]
    \\    return 0
    \\def callback(state: mut State, item: int):
    \\    state.values[replace(mut state)] = item
    \\def main() -> int:
    \\    state = State([7,11])
    \\    field(mut state, 0, 13)
    \\    return state.values[0]
;

fn emitted(steps: bool) !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "positive-write.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbeWithOptions(t.allocator, .{ .step_checks = steps });
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}

fn body(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}

// spec: QBE-POSITIVE-WRITE-1
test "positive write skips only quiet normalization and preserves the checked write" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var result = try emitted(false);
    defer result.deinit();
    const il = try body(result.value, "field");
    try t.expect(std.mem.indexOf(u8, il, "# QBE-POSITIVE-WRITE-1") != null);
    try t.expect(std.mem.indexOf(u8, il, "myl_qbe_fail_cast") != null);
    try t.expect(std.mem.indexOf(u8, il, "myl_qbe_fail_overflow_op") != null);
    try t.expect(std.mem.indexOf(u8, il, "myl_qbe_fail_normalized_index_bounds") != null);
    for ([_][]const u8{ "scoped", "managed", "byte", "callback" }) |name| {
        try t.expect(std.mem.indexOf(u8, try body(result.value, name), "# QBE-POSITIVE-WRITE-1") == null);
    }
}

// spec-case: QBE-POSITIVE-WRITE-1
test "positive write counted execution keeps every original instruction" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var result = try emitted(true);
    defer result.deinit();
    try t.expect(std.mem.indexOf(u8, try body(result.value, "field"), "# QBE-POSITIVE-WRITE-1") == null);
}

// spec-case: QBE-POSITIVE-WRITE-1
test "positive write GC emission keeps the original receiver protocol" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.gc);
    var result = try emitted(false);
    defer result.deinit();
    try t.expect(std.mem.indexOf(u8, try body(result.value, "field"), "# QBE-POSITIVE-WRITE-1") == null);
}

// spec-case: QBE-POSITIVE-WRITE-1
test "positive write unaccounted fallback keeps exact bounds details and traces" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    const cases = [_]struct { values: []const u8, index: i64 }{
        .{ .values = "[7,11]", .index = 0 },
        .{ .values = "[7,11]", .index = 1 },
        .{ .values = "[7,11]", .index = -1 },
        .{ .values = "[7,11]", .index = -2 },
        .{ .values = "[7,11]", .index = -3 },
        .{ .values = "[7,11]", .index = std.math.minInt(i64) },
        .{ .values = "[7,11]", .index = std.math.maxInt(i64) },
        .{ .values = "[]", .index = 0 },
        .{ .values = "[]", .index = -1 },
    };
    for (cases) |case| {
        const template = "record State:\n    values: list[int]\n" ++
            "def field(state: mut State, index: int):\n    state.values[index] = 13\n" ++
            "def main() -> int:\n    values: list[int] = {s}\n    state = State(values)\n" ++
            "    field(mut state, {d})\n    return state.values[0]\n";
        const input = try std.fmt.allocPrint(t.allocator, template, .{ case.values, case.index });
        defer t.allocator.free(input);
        var compilation = try compiler.Compilation.init(t.allocator, "positive-write-fallback.my", input);
        defer compilation.deinit();
        const reference = try native.run(&compilation);
        const actual = try native.runUnaccounted(&compilation, .{});
        try t.expectEqual(reference.failed, actual.failed);
        try t.expectEqual(reference.value, actual.value);
        try t.expectEqualStrings(reference.stderr, actual.stderr);
        try t.expect(std.meta.eql(reference.trap.detail, actual.trap.detail));
    }
}

// spec-case: QBE-POSITIVE-WRITE-1
test "positive write native COW snapshots aliases and callback replacement survive GC stress" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    const input =
        \\record State:
        \\    values: list[int]
        \\def field(state: mut State, index: int, item: int):
        \\    state.values[index] = item
        \\def replace(state: mut State) -> int:
        \\    state.values = [17,19]
        \\    return 0
        \\def callback(state: mut State):
        \\    state.values[replace(mut state)] = 23
        \\def main() -> int:
        \\    state = State([7,11])
        \\    before = state
        \\    detached = state.values
        \\    field(mut state, 0, 13)
        \\    field(mut state, -1, 29)
        \\    state.values[0] = state.values[1]
        \\    assert state.values == [29,29]
        \\    assert before.values == [7,11] and detached == [7,11]
        \\    callback(mut state)
        \\    assert state.values == [17,19]
        \\    assert before.values == [7,11] and detached == [7,11]
        \\    return 0
    ;
    var compilation = try compiler.Compilation.init(t.allocator, "positive-write-snapshots.my", input);
    defer compilation.deinit();
    for ([_]bool{ false, true }) |stress| {
        const result = try native.runUnaccounted(&compilation, .{ .gc_stress = stress });
        try t.expect(!result.failed);
        try t.expectEqual(@as(i64, 0), result.value);
    }
}
