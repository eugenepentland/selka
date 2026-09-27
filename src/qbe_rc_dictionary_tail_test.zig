//! Evaluated dictionary tails retain first uniqueness and ordinary journals.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const marker = "# RC-DICTIONARY-TAIL-1";
const source =
    \\def counted(times: int) -> int:
    \\    counts: dict[str, int] = {}
    \\    for i in range(times):
    \\        key = "key" + str(i % 3)
    \\        counts[key] = counts.get(key, 0) + 1
    \\    return counts.get("key0", 0)
    \\def snapshot() -> int:
    \\    counts = {1: 7}
    \\    saved = counts
    \\    key = 1
    \\    counts[key] = 13
    \\    return saved[key] + counts[key]
    \\def parameter(counts: mut dict[int, int]):
    \\    key = 1
    \\    counts[key] = 13
    \\def managed() -> list[int]:
    \\    counts = {1: [7]}
    \\    key = 1
    \\    counts[key] = [13]
    \\    return counts[key]
    \\def held() -> int:
    \\    counts = {1: 7}
    \\    view = counts.values()
    \\    key = 1
    \\    counts[key] = 13
    \\    return list(view)[0]
    \\def held_key() -> int:
    \\    counts: dict[str, int] = {}
    \\    key = "key"
    \\    letters = 0
    \\    for letter in key:
    \\        letters += len(letter)
    \\    counts[key] = letters
    \\    return counts[key]
    \\def rebound() -> int:
    \\    counts = {1: 7}
    \\    counts = {1: 9}
    \\    key = 1
    \\    counts[key] = 13
    \\    return counts[key]
    \\def nonlist_key() -> int:
    \\    names = {1: "key"}
    \\    key = names[1]
    \\    counts: dict[str, int] = {}
    \\    counts[key] = 7
    \\    return counts[key]
    \\def parameter_key(key: str) -> int:
    \\    counts: dict[str, int] = {}
    \\    counts[key] = 7
    \\    return counts[key]
    \\def pattern_key(candidate: Option[str]) -> int:
    \\    counts: dict[str, int] = {}
    \\    match candidate:
    \\        case Some(key):
    \\            counts[key] = 7
    \\            return counts[key]
    \\        case None:
    \\            return 0
    \\def main() -> int:
    \\    return counted(3)
;
fn emitted() !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "dictionary_tail.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn body(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}
// spec: RC-DICTIONARY-TAIL-1
test "RC dictionary tail retains first uniqueness and frame through repeated captures" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var result = try emitted();
    defer result.deinit();
    const il = try body(result.value, "counted");
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, il, marker));
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, il, "call $myl_qbe_rc_unique_local"));
    try t.expectEqual(@as(usize, 0), std.mem.count(u8, il, "call $myl_qbe_rc_scope_begin"));
    try t.expect(std.mem.indexOf(u8, il, "# rc-frame") != null);
    try t.expect(std.mem.indexOf(u8, il, "call $myl_native_dictionary_write") != null);
    try t.expect(std.mem.indexOf(u8, try body(result.value, "snapshot"), marker) != null);
}
// spec-case: RC-DICTIONARY-TAIL-1
test "RC dictionary tail refuses parameter managed and function-wide held receivers" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var result = try emitted();
    defer result.deinit();
    for ([_][]const u8{ "parameter", "managed", "held", "held_key", "rebound", "nonlist_key", "parameter_key", "pattern_key" }) |name| {
        const il = try body(result.value, name);
        try t.expect(std.mem.indexOf(u8, il, marker) == null);
        try t.expect(std.mem.indexOf(u8, il, "call $myl_qbe_rc_scope_begin") != null);
    }
}

// spec-case: RC-DICTIONARY-TAIL-1
test "RC dictionary tail refuses a middle entry into the capture lifetime" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "middle_tail.my", source);
    defer compilation.deinit();
    try compilation.emit();
    const code = @constCast(compilation.code.?.functions[0].scope.instructions);
    try enterMiddle(code);
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    var result = try std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer result.deinit();
    try t.expect(std.mem.indexOf(u8, try body(result.value, "counted"), marker) == null);
}

fn enterMiddle(code: []@import("bytecode.zig").Instruction) !void {
    var middle: ?usize = null;
    for (code, 0..) |instruction, pc| {
        if (instruction.op == .buffer_operation and instruction.op.buffer_operation.kind == .write) middle = pc - 2;
    }
    for (code) |*instruction| {
        if (instruction.op == .jump_if_false) {
            instruction.op.jump_if_false = @intCast(middle orelse return error.TestUnexpectedResult);
            break;
        }
    }
}

// spec-case: RC-DICTIONARY-TAIL-1
test "RC dictionary tail admits the unchanged benchmark key capture grammar" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    const exact = try std.Io.Dir.cwd().readFileAlloc(t.io, "bench/parity/micro/dict_count.my", t.allocator, .limited(65536));
    defer t.allocator.free(exact);
    var compilation = try compiler.Compilation.init(t.allocator, "dict_count.my", exact);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    var result = try std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer result.deinit();
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, try body(result.value, "main"), marker));
}
