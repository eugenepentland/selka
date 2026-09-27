//! RC construction registers partial ownership before a field transfer can fail.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };

fn pairText() !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "rc_aggregate.my",
        \\record Pair:
        \\    left: list[int]
        \\    right: list[int]
        \\
        \\def pair(items: list[int]) -> Pair:
        \\    return Pair(items, items)
        \\
        \\def main() -> int:
        \\    value = pair([1, 2])
        \\    return len(value.left)
    );
    defer compilation.deinit();
    const manifest = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(manifest);
    return std.json.parseFromSlice(Manifest, t.allocator, manifest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}

fn findFunction(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}

fn location(text: []const u8, needle: []const u8) !usize {
    return std.mem.indexOf(u8, text, needle) orelse error.TestUnexpectedResult;
}

// spec: RC-AGGREGATE-1
test "RC aggregate partial construction journals fields before guarded takes or copies" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try pairText();
    defer manifest.deinit();
    const text = try findFunction(manifest.value, "pair");
    // Pair has two pointer fields. Other token moves can clear an eight-byte
    // source before this constructor initializes its sixteen-byte body.
    const cleared = try location(text, "w 0, l 16)");
    const taken = cleared + try location(text[cleared..], "# RC-GLUE-1 take");
    const copied = cleared + try location(text[cleared..], "# RC-GLUE-1 retain");
    try t.expect(cleared < taken and taken < copied);
    try t.expect(std.mem.indexOf(u8, text[cleared..taken], "storew 1") != null);
    try t.expect(std.mem.indexOf(u8, text[taken..copied], "storew 0") != null);
    try t.expect(try location(text, "call $myl_qbe_rc_frame_enter") < cleared);
    try t.expect(try location(text, "call $myl_qbe_rc_frame_cleanup") > copied);
    // A semantic publication can retire a private loan before construction.
    // The constructor still adopts its completed inputs before frame cleanup.
    try t.expect(try location(text, "# RC-GLUE-1 publish") < cleared);
}

// spec: RC-PLAIN-PROJECTION-1
test "RC plain inline fields survive the release of their owning parent" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "rc_plain_projection.my",
        \\enum Kind:
        \\    list,
        \\    string
        \\record Scalar:
        \\    tag: Kind
        \\    count: int
        \\record Container:
        \\    keep: list[int]
        \\    plain: Scalar
        \\def produce() -> Container:
        \\    return Container([1], Scalar(Kind.string, 42))
        \\def selected() -> Scalar:
        \\    return produce().plain
        \\def main() -> int:
        \\    value = selected()
        \\    if value.tag != Kind.string:
        \\        return 1
        \\    return value.count
    );
    defer compilation.deinit();
    const emitted = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(emitted);
    var manifest = try std.json.parseFromSlice(Manifest, t.allocator, emitted, .{ .ignore_unknown_fields = true });
    defer manifest.deinit();
    const text = try findFunction(manifest.value, "selected");
    const release = try location(text, "call $myl_qbe_rc_slot_drop");
    try t.expect(hasPlainSnapshot(text[0..release]));
}

fn hasPlainSnapshot(text: []const u8) bool {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, " blit ") and std.mem.endsWith(u8, line, ", 16")) return true;
    }
    return false;
}

fn borrowsContractBeforeReturn(code: compiler.bytecode.Program) bool {
    for (code.functions) |function| {
        if (!std.mem.eql(u8, function.name, "checked")) continue;
        for (function.scope.instructions, 0..) |instruction, index| {
            if (instruction.op != .switch_variant or !instruction.op.switch_variant.borrowed or index == 0) continue;
            return function.scope.instructions[index - 1].op == .load_local;
        }
    }
    return false;
}

// spec: RC-CONTRACT-RESULT-1
test "RC contract inspection borrows the complete result before its final return" {
    var compilation = try compiler.Compilation.init(t.allocator, "rc_contract.my",
        \\@ensures(len(result) == 2)
        \\def checked() -> Result[list[int], str]:
        \\    return Ok([17, 23])
        \\def main() -> int:
        \\    match checked():
        \\        case Ok(values):
        \\            return values[0]
        \\        case Err(_):
        \\            return 1
    );
    defer compilation.deinit();
    try compilation.emit();
    try t.expect(borrowsContractBeforeReturn(compilation.code.?));
}

fn contractPayloadSlot(code: compiler.bytecode.Program) !usize {
    for (code.functions) |function| {
        if (!std.mem.eql(u8, function.name, "checked")) continue;
        for (function.scope.locals, 0..) |_, index| {
            if (@import("qbe_aggregate.zig").borrowedPayload(function, index)) return index;
        }
    }
    return error.TestUnexpectedResult;
}

// spec-case: RC-CONTRACT-RESULT-1
test "GC contract inspection does not close the returned unique payload" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.gc);
    var compilation = try compiler.Compilation.init(t.allocator, "gc_contract.my",
        \\@ensures(True)
        \\def checked(fs: Filesystem) -> Result[TextFile, str]:
        \\    return fs.open("data", "w")
        \\def main() -> int:
        \\    return 0
    );
    defer compilation.deinit();
    const emitted = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(emitted);
    var manifest = try std.json.parseFromSlice(Manifest, t.allocator, emitted, .{ .ignore_unknown_fields = true });
    defer manifest.deinit();
    const text = try findFunction(manifest.value, "checked");
    const drop_target = try std.fmt.allocPrint(t.allocator, ", l %l{d})", .{try contractPayloadSlot(compilation.code.?)});
    defer t.allocator.free(drop_target);
    try t.expect(std.mem.indexOf(u8, text, drop_target) == null);
}

// spec: RC-PLAIN-OPERAND-1
test "RC scalar arithmetic with a receiver loan emits no owned input drops" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "rc_plain_operands.my",
        \\def total(values: list[int], count: int) -> int:
        \\    index = 0
        \\    result = 0
        \\    while index < count:
        \\        result += index
        \\        index += 1
        \\    return result + len(values)
        \\def main() -> int:
        \\    return total([17, 23], 20)
    );
    defer compilation.deinit();
    const emitted = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(emitted);
    var manifest = try std.json.parseFromSlice(Manifest, t.allocator, emitted, .{ .ignore_unknown_fields = true });
    defer manifest.deinit();
    const text = try findFunction(manifest.value, "total");
    try t.expectEqual(@as(usize, 0), std.mem.count(u8, text, "call $myl_qbe_rc_slot_drop"));
}

// spec-case: RC-FRAME-1
test "RC empty slot releases branch around native cleanup" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try pairText();
    defer manifest.deinit();
    // main still releases its original list after the call owns Pair's fields;
    // pair itself directly publishes inputs already consumed by its fields.
    const text = try findFunction(manifest.value, "main");
    const release = try location(text, "call $myl_qbe_rc_slot_drop");
    try t.expect(std.mem.indexOf(u8, text[0..release], "@rcslotdrop") != null);
    try t.expect(std.mem.indexOf(u8, text[release..], "@rcslotdone") != null);
}
