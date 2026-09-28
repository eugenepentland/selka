//! Isolated evaluation words preserve physical tokens and original fallbacks.
const std = @import("std");
const text = @import("qbe_loop_operand_text.zig");
const proof = @import("qbe_loop_operands.zig");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const facts = @import("qbe_loop_facts.zig");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const storage =
    " %s0 =l alloc8 8\n %s1 =l alloc8 8\n %s5 =l alloc8 8\n %s6 =l alloc8 8\n" ++
    " storel 111, %s5\n storel 112, %s6\n call $use(l %s0)\n";
const body =
    " # RC-LOOP-OPERANDS-BEGIN 4 9\n@fi4\n" ++
    " storel 1, %s0\n %v1 =l loadl %s0\n storel %v1, %s1\n %v2 =l loadl %s1\n" ++
    " jmp @fi4\n # RC-LOOP-OPERANDS-END 4 9\n@oi4\n";

fn unchanged(input: []const u8) !void {
    const output = try text.rewrite(t.allocator, input);
    defer t.allocator.free(output);
    try t.expectEqualStrings(input, output);
}

// spec-case: QBE-LOOP-VERSION-1
test "RC isolated operands reuse only whole-function write-only slots" {
    const input = storage ++ body ++ " %v20 =l loadl %s0\n ret %v20\n";
    const output = try text.rewrite(t.allocator, input);
    defer t.allocator.free(output);
    try t.expect(std.mem.startsWith(u8, output, storage));
    try t.expect(std.mem.indexOf(u8, output, "storel 1, %s5\n %v1 =l loadl %s5\n storel %v1, %s6") != null);
    try t.expect(std.mem.endsWith(u8, output, "@oi4\n %v20 =l loadl %s0\n ret %v20\n"));
    try t.expectEqual(std.mem.count(u8, input, "alloc8"), std.mem.count(u8, output, "alloc8"));
    try t.expectError(error.OutOfMemory, text.rewrite(t.failing_allocator, input));
}

// spec-case: QBE-LOOP-VERSION-1
test "RC isolated operands refuse global reads escapes self-address and missing banks" {
    try unchanged(storage ++ body ++ " %v9 =l loadl %s5\n");
    try unchanged(storage ++ body ++ " %v9 =l copy %s5\n");
    try unchanged(storage ++ body ++ " call $f(l %s5)\n");
    try unchanged(storage ++ body ++ " storel %s5, %s5\n");
    try unchanged(storage ++ body ++ " %s5 =l alloc8 8\n");
    try unchanged(" %s0 =l alloc8 8\n %s1 =l alloc8 8\n" ++ body);
    try unchanged(storage ++ body ++ "# later metadata alias %s5\n");
}

// spec-case: QBE-LOOP-VERSION-1
test "RC isolated operands refuse direct metadata narrow access and malformed regions atomically" {
    const begin = storage ++ " # RC-LOOP-OPERANDS-BEGIN 4 9\n@fi4\n";
    const end = " # RC-LOOP-OPERANDS-END 4 9\n@oi4\n";
    try unchanged(begin ++ " %v0 =l add %rcguards, 8\n storew 1, %v0\n" ++ end);
    try unchanged(begin ++ " storew 1, %v123\n" ++ end);
    try unchanged(begin ++ " storel 1, %v123\n" ++ end);
    try unchanged(begin ++ " %v0 =l copy %s0\n" ++ end);
    try unchanged(begin ++ " %v0 =w loaduw %s0\n" ++ end);
    try unchanged(begin ++ " storew 1, %s0\n" ++ end);
    try unchanged(begin ++ " # address annotation %s0\n" ++ end);
    try unchanged(begin ++ " storel 1, %s0\n # RC-LOOP-OPERANDS-END 4 8\n@oi4\n");
    try unchanged(begin ++ " # RC-LOOP-OPERANDS-BEGIN 4 9\n@fi4\n" ++ end);
    try unchanged(begin ++ " storel 1, %s00\n" ++ end);
    try unchanged(begin ++ " storel 1, %s0.extra\n" ++ end);
    try unchanged(begin ++ " storel %s0, %s1\n" ++ end);
    try unchanged(storage ++ body ++ " jmp @fi5\n");
    try unchanged(storage ++ body ++ " # RC-LOOP-OPERANDS-BEGIN 20 25\n@fi20\n %v0 =l copy %s0\n # RC-LOOP-OPERANDS-END 20 25\n@oi20\n");
}

// spec-case: QBE-LOOP-VERSION-1
test "RC isolated operands preserve quotes full identifiers and share a disjoint bank" {
    const suffix = " data $quoted = { b \"%s5 @fi5\" }\n %v100 =l loadl %s50\n";
    const second = " # RC-LOOP-OPERANDS-BEGIN 20 25\n@fi20\n storel 3, %s0\n %v30 =l loadl %s0\n jmp @fi20\n # RC-LOOP-OPERANDS-END 20 25\n@oi20\n";
    const output = try text.rewrite(t.allocator, storage ++ body ++ second ++ suffix);
    defer t.allocator.free(output);
    try t.expect(std.mem.endsWith(u8, output, suffix));
    try t.expectEqual(@as(usize, 2), std.mem.count(u8, output, "RC-LOOP-OPERANDS-ISOLATED"));
    try t.expect(std.mem.indexOf(u8, output, "storel 3, %s5\n %v30 =l loadl %s5") != null);
}

fn instruction(op: @FieldType(bytecode.Instruction, "op")) bytecode.Instruction {
    return .{ .span = .{ .start = 0, .end = 0 }, .op = op };
}

// spec-case: QBE-LOOP-VERSION-1
test "RC isolated operands require empty normal boundaries and reject interior entries" {
    var code = [_]bytecode.Instruction{
        instruction(.{ .jump = 2 }),      instruction(.{ .jump = 8 }),
        instruction(.{ .push_i64 = 1 }),  instruction(.{ .push_i64 = 2 }),
        instruction(.{ .cmp_i64 = .lt }), instruction(.{ .jump_if_false = 8 }),
        instruction(.{ .jump = 7 }),      instruction(.{ .jump = 2 }),
        instruction(.{ .push_i64 = 0 }),
    };
    var states = [_]?[]const typed.Type{ &.{}, &.{}, &.{}, &.{.i64}, &.{ .i64, .i64 }, &.{.bool}, &.{}, &.{}, &.{} };
    const actions: [6]facts.Action = @splat(.{});
    const loop: facts.Loop = .{ .head = 2, .back = 7, .bits = 8, .guard = &.{}, .actions = &actions };
    try t.expect(proof.closed(&code, &states, &loop, .{}));
    states[2] = &.{.i64};
    try t.expect(!proof.closed(&code, &states, &loop, .{}));
    states[2] = &.{};
    states[7] = &.{.i64};
    try t.expect(!proof.closed(&code, &states, &loop, .{}));
    states[7] = &.{};
    states[8] = &.{.i64};
    try t.expect(!proof.closed(&code, &states, &loop, .{}));
    states[8] = &.{};
    code[0] = instruction(.{ .jump = 3 });
    try t.expect(!proof.closed(&code, &states, &loop, .{}));
}

const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const source =
    \\def scan(out: Stream, count: int) -> int:
    \\    data = b"0123456789abcdefghijklmnop"
    \\    total = 0
    \\    for i in range(count):
    \\        total += int(data[i])
    \\    out.print(total)
    \\    return total
    \\def main(out: Stream) -> int:
    \\    return scan(out, 20)
    \\def heap(values: [4096]int, count: int) -> int:
    \\    padding = replace(values, 0, 7)
    \\    data = b"0123456789abcdefghijklmnop"
    \\    total = 0
    \\    for i in range(count):
    \\        total += int(data[i])
    \\    return total + padding[0]
;
fn emitted(steps: bool) !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "isolated.my", source);
    defer compilation.deinit();
    const output = try compilation.emitQbeWithOptions(t.allocator, .{ .step_checks = steps, .frame_checks = false });
    defer t.allocator.free(output);
    return std.json.parseFromSlice(Manifest, t.allocator, output, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn functionOf(output: Manifest, name: []const u8) ![]const u8 {
    for (output.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}

// spec-case: QBE-LOOP-VERSION-1
test "RC isolated operands preserve byte metadata guards checked fallback and steps" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var output = try emitted(false);
    defer output.deinit();
    // A constant literal is one instruction now, so it leaves no write-only push
    // slots behind: the emitted function has no spare bank and stays unisolated.
    // Give that same emitted text eight unused slots, as a wider frame would.
    const emitted_il = try functionOf(output.value, "scan");
    try t.expect(std.mem.indexOf(u8, emitted_il, "RC-LOOP-OPERANDS-ISOLATED") == null);
    const bank = "\n@entry\n %s20 =l alloc8 8\n %s21 =l alloc8 8\n %s22 =l alloc8 8\n %s23 =l alloc8 8\n %s24 =l alloc8 8\n %s25 =l alloc8 8\n %s26 =l alloc8 8\n %s27 =l alloc8 8\n";
    const banked = try std.mem.replaceOwned(u8, t.allocator, emitted_il, "\n@entry\n", bank);
    defer t.allocator.free(banked);
    const il = try text.rewrite(t.allocator, banked);
    defer t.allocator.free(il);
    try t.expect(std.mem.indexOf(u8, il, "RC-LOOP-OPERANDS-ISOLATED") != null);
    try t.expect(std.mem.indexOf(u8, il, "RC-READ-BYTES-VERSION-1") != null);
    const original = std.mem.indexOf(u8, il, "\n@oi") orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.indexOf(u8, il[original..], "myl_qbe_fail_index_bounds") != null);
    try t.expect(std.mem.indexOf(u8, il[original..], "@rcslotdrop") != null);
    const heap = try functionOf(output.value, "heap");
    try t.expect(std.mem.indexOf(u8, heap, "myl_qbe_frame_allocate") != null);
    try t.expect(std.mem.indexOf(u8, heap, "RC-LOOP-OPERANDS-ISOLATED") == null);
    var accounted = try emitted(true);
    defer accounted.deinit();
    try t.expect(std.mem.indexOf(u8, try functionOf(accounted.value, "scan"), "RC-LOOP-OPERANDS-ISOLATED") == null);
}
