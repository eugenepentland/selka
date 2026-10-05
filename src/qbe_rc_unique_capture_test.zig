//! Adjacent receiver captures preserve snapshots and uncertain held inputs.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const bytecode = @import("bytecode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const marker = "# RC-UNIQUE-CAPTURE-1";
const source =
    \\def plain(times: int, index: int) -> int:
    \\    values = [7, 11]
    \\    for at in range(times):
    \\        next_value = values[index] + at + 1
    \\        values[index] = next_value
    \\    return values[0] + values[1]
    \\def once(delta: int, index: int) -> int:
    \\    values = [7, 11]
    \\    flags = [True, False]
    \\    values[index] = delta
    \\    return values[0] + values[1] + (1 if flags[0] else 0)
    \\def snapshot(index: int) -> int:
    \\    values = [7, 11]
    \\    saved = values
    \\    values[index] = 13
    \\    return saved[index] * 100 + values[index]
    \\def repeat(times: int, index: int, shared: bool) -> int:
    \\    values = [7, 11]
    \\    total = 0
    \\    for at in range(times):
    \\        if shared:
    \\            saved = values
    \\            values[index] = (values[index] + at + 1) % 1000003
    \\            total += saved[index] + values[index]
    \\            saved = []
    \\        else:
    \\            values[index] = (values[index] + at + 1) % 1000003
    \\            total += values[index]
    \\    return total + values[0] + values[1]
    \\def change(values: mut list[int]) -> int:
    \\    values.clear()
    \\    values.append(17)
    \\    return 0
    \\def callback() -> int:
    \\    values = [7, 11]
    \\    mutation_result_45 = change(mut values)
    \\    values[mutation_result_45] = 13
    \\    return values[0]
    \\def rebound() -> int:
    \\    values = [7, 11]
    \\    values = [19, 23]
    \\    values[0] = 13
    \\    return values[0] + values[1]
    \\def held(groups: list[list[int]]) -> int:
    \\    total = 0
    \\    for element in groups:
    \\        values = element
    \\        values[0] = 13
    \\        total += values[0]
    \\    return total + groups[0][0]
    \\def managed() -> int:
    \\    values = [[7], [11]]
    \\    values[0] = [13]
    \\    return values[0][0]
    \\def main() -> int:
    \\    return plain(2, -1)
;

fn emitted(text: []const u8) !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "unique_capture.my", text);
    defer compilation.deinit();
    const il = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(il);
    return std.json.parseFromSlice(Manifest, t.allocator, il, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}

fn body(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}

// spec: RC-UNIQUE-CAPTURE-1
test "RC duplicate capture removes only the second checked named-root guard" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var result = try emitted(source);
    defer result.deinit();
    const cases = [_]struct { name: []const u8, copies: usize }{
        .{ .name = "once", .copies = 1 },     .{ .name = "snapshot", .copies = 1 },
        .{ .name = "repeat", .copies = 2 },   .{ .name = "plain", .copies = 0 },
        .{ .name = "callback", .copies = 1 }, .{ .name = "rebound", .copies = 0 },
        .{ .name = "held", .copies = 0 },     .{ .name = "managed", .copies = 0 },
    };
    for (cases) |case| try checkAdmission(try body(result.value, case.name), case.copies);
}

fn checkAdmission(il: []const u8, copies: usize) !void {
    try t.expectEqual(copies, std.mem.count(u8, il, marker));
    if (copies == 0) return;
    const at = std.mem.indexOf(u8, il, marker).?;
    try t.expect(std.mem.indexOf(u8, il[0..at], "$myl_qbe_rc_unique_local") != null);
    try t.expect(std.mem.indexOf(u8, il[at..], "myl_qbe_fail_normalized_index_bounds") != null);
}

// spec-case: RC-UNIQUE-CAPTURE-1
test "RC duplicate capture preserves counting site and collector emission" {
    const saved = runtime.get();
    defer runtime.set(saved);
    for ([_]runtime.Selection{ .rc_counting, .rc_sites, .gc }) |selection| {
        runtime.set(selection);
        var result = try emitted(source);
        defer result.deinit();
        try t.expect(std.mem.indexOf(u8, try body(result.value, "once"), marker) == null);
    }
}

// spec-case: RC-UNIQUE-CAPTURE-1
test "RC duplicate capture refuses an alternate entry into the adjacent store" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "middle_capture.my", source);
    defer compilation.deinit();
    try compilation.emit();
    const function = try checkedFunction(&compilation, "once");
    const original = function.scope.instructions;
    const code = try t.allocator.alloc(bytecode.Instruction, original.len + 2);
    defer t.allocator.free(code);
    @memcpy(code[0..original.len], original);
    var target: ?usize = null;
    var parent: ?@FieldType(bytecode.Instruction, "op") = null;
    const locals = function.scope.locals;
    for (original, 0..) |instruction, pc| {
        if (instruction.op != .store_local or pc == 0 or code[pc - 1].op != .load_local) continue;
        const local = @backingInt(instruction.op.store_local);
        if (!locals[local].usage.temporary or !locals[local].ty.isAggregate()) continue;
        target = pc;
        parent = code[pc - 1].op;
        break;
    }
    const at = target orelse return error.TestUnexpectedResult;
    // Even an unreachable extra predecessor conservatively refuses the proof.
    // Its one-value stack matches the store; the original path is untouched.
    code[original.len] = .{ .span = original[at].span, .op = parent.? };
    code[original.len + 1] = .{ .span = original[at].span, .op = .{ .jump = at } };
    function.scope.instructions = code;
    const il = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(il);
    var result = try std.json.parseFromSlice(Manifest, t.allocator, il, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer result.deinit();
    try t.expect(std.mem.indexOf(u8, try body(result.value, "once"), marker) == null);
}

fn checkedFunction(compilation: *compiler.Compilation, name: []const u8) !*bytecode.Function {
    for (@constCast(compilation.code.?.functions)) |*function|
        if (std.mem.eql(u8, function.name, name)) return function;
    return error.TestUnexpectedResult;
}

// spec-case: RC-UNIQUE-CAPTURE-1
test "RC duplicate capture refuses a mismatched physical descriptor" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "descriptor_capture.my", source);
    defer compilation.deinit();
    try compilation.emit();
    const function = try checkedFunction(&compilation, "once");
    try mismatchDescriptor(function);
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    var result = try std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer result.deinit();
    try t.expect(std.mem.indexOf(u8, try body(result.value, "once"), marker) == null);
}

fn mismatchDescriptor(function: *bytecode.Function) !void {
    const locals = @constCast(function.scope.locals);
    const other = try flagsType(function);
    for (function.scope.instructions, 0..) |instruction, pc| {
        if (instruction.op != .store_local or pc == 0 or function.scope.instructions[pc - 1].op != .load_local) continue;
        const local = @backingInt(instruction.op.store_local);
        if (!locals[local].usage.temporary or !locals[local].ty.isAggregate()) continue;
        // The two pointer-width collections deliberately disagree on their
        // element descriptor. This forged input must never earn a certificate.
        locals[local].ty = other;
        return;
    }
    return error.TestUnexpectedResult;
}

fn flagsType(function: *bytecode.Function) !@import("typed.zig").Type {
    for (function.scope.locals) |local| if (std.mem.eql(u8, local.name, "flags")) return local.ty;
    return error.TestUnexpectedResult;
}

// spec-case: RC-UNIQUE-CAPTURE-1
test "RC duplicate capture preserves native snapshots held inputs traps and budgets" {
    const native = @import("native_execute.zig");
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    const prefix = comptime source[0..std.mem.indexOf(u8, source, "def main(").?];
    const input = prefix ++
        \\def main(args: list[str], out: Stream) -> int:
        \\    out.print(41)
        \\    if args[0] == "bounds":
        \\        return once(13, 2)
        \\    if args[0] == "held":
        \\        return held([[7, 11], [19, 23]])
        \\    if args[0] == "snapshot":
        \\        return snapshot(-1)
        \\    return once(13, 0)
    ;
    var compilation = try compiler.Compilation.init(t.allocator, "native_capture.my", input);
    defer compilation.deinit();
    for ([_][]const u8{ "once", "snapshot", "held", "bounds" }, [_]i64{ 25, 1113, 33, 0 }) |name, value| {
        const options: native.Options = .{ .arguments = &.{ "--", name } };
        const ordinary = try native.runWithOptions(&compilation, options);
        const fast = try native.runUnaccounted(&compilation, options);
        try t.expectEqualDeep(ordinary, fast);
        try t.expectEqual(value, fast.value);
        try t.expectEqualStrings("41\n", fast.stdout);
        try t.expectEqual(std.mem.eql(u8, name, "bounds"), fast.failed);
    }
    const limited = try native.runWithOptions(&compilation, .{ .arguments = &.{ "--", "once" }, .max_steps = 1 });
    try t.expectEqualStrings("R_STEP_LIMIT", limited.trap.code);
    const stressed = try native.runWithOptions(&compilation, .{ .arguments = &.{ "--", "held" }, .gc_stress = true });
    try t.expectEqual(@as(i64, 33), stressed.value);
    try t.expect(!stressed.failed);
}
