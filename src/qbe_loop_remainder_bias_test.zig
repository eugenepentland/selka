//! Old-plan equivalence, actual specialization, privacy and native outcomes.
const std = @import("std");
const t = std.testing;
const compiler = @import("compiler.zig");
const facts = @import("qbe_loop_facts.zig");
const remainder = @import("qbe_loop_remainder_bias.zig");
const bytecode = @import("bytecode.zig");
const native = @import("native_execute.zig");
const runtime = @import("runtime_mode.zig");
const ScalarPolicy = @import("runtime_contract").scalars.Policy;
const test_log = std.debug.print;
const fixture = "bounded_remainder.my";
const function_name = "calculate";
const bias_literal_line = ", 8646911284551353149\n";
const signed_shift = " =l sar ";
const unsigned_remainder = " =l urem ";
const signed_remainder = " =l rem ";
const outcome_format = "BOUNDED-REMAINDER-OUTCOME {s}\n";
const overflow_code = "R_OVERFLOW";
const source =
    \\def calculate(n: int, seed: int, offset: int) -> int:
    \\    values: list[int] = []
    \\    for i in range(n):
    \\        values.append((seed + offset + i * 13) % 1009)
    \\    if n <= 0:
    \\        return len(values)
    \\    return len(values) + values[0] + values[-1]
    \\def main() -> int:
    \\    return calculate(32, 17, 0)
;
const main_marker = "def main()";
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };

fn emitted(input: []const u8, policy: ScalarPolicy) ![]u8 {
    var compilation = try compiler.Compilation.init(t.allocator, fixture, input);
    defer compilation.deinit();
    const text = try compilation.emitQbeWithOptions(t.allocator, .{ .step_checks = false, .frame_checks = false, .scalar_policy = policy });
    defer t.allocator.free(text);
    var parsed = try std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer parsed.deinit();
    for (parsed.value.functions) |unit| if (std.mem.eql(u8, unit.name, function_name)) return t.allocator.dupe(u8, unit.il);
    return error.TestUnexpectedResult;
}

const Parts = struct { guard: []const u8, fast: []const u8, original: []const u8 };
fn parts(body: []const u8) !Parts {
    const start = std.mem.indexOf(u8, body, "\n@fi") orelse return error.TestUnexpectedResult;
    const original = std.mem.indexOf(u8, body, "\n@oi") orelse return error.TestUnexpectedResult;
    const guard = std.mem.lastIndexOf(u8, body[0..start], "# mylang-rc-append-range ") orelse 0;
    return .{ .guard = body[guard..start], .fast = body[start..original], .original = body[original..] };
}

fn policies() !void {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var old_guard: ?[]u8 = null;
    defer if (old_guard) |guard| t.allocator.free(guard);
    for ([_]ScalarPolicy{ .qbe, .llvm }) |policy| {
        const body = try emitted(source, policy);
        defer t.allocator.free(body);
        const loop = try parts(body);
        if (old_guard) |guard| try t.expectEqualStrings(guard, loop.guard) else old_guard = try t.allocator.dupe(u8, loop.guard);
        try t.expectEqual(@as(usize, 1), std.mem.count(u8, loop.fast, "call $myl_rc_list_append("));
        try t.expectEqual(@as(usize, 1), std.mem.count(u8, loop.original, "call $myl_rc_list_append("));
        try t.expect(std.mem.indexOf(u8, loop.original, "myl_qbe_fail_overflow_op") != null);
        try policyForm(policy, loop);
    }
}

fn policyForm(policy: ScalarPolicy, loop: Parts) !void {
    switch (policy) {
        .qbe => {
            try t.expect(std.mem.indexOf(u8, loop.fast, bias_literal_line) == null);
            try t.expect(std.mem.indexOf(u8, loop.fast, signed_shift) != null);
            try t.expect(std.mem.indexOf(u8, loop.fast, " =l umulh ") != null);
            try t.expect(std.mem.indexOf(u8, loop.original, signed_shift) != null);
        },
        .llvm => {
            try t.expect(std.mem.indexOf(u8, loop.fast, bias_literal_line) != null);
            try t.expect(std.mem.indexOf(u8, loop.fast, signed_shift) == null);
            try t.expect(std.mem.indexOf(u8, loop.fast, unsigned_remainder) != null);
            try t.expect(std.mem.indexOf(u8, loop.original, signed_remainder) != null);
        },
    }
}

fn translatedLlvm(allocator: std.mem.Allocator, body: []const u8) ![]const u8 {
    const llvm = @import("qbe_build_llvm.zig");
    var headers: std.ArrayList(llvm.RuntimeSource) = .empty;
    for (@import("qbe_build_assets").files) |file| {
        if (!std.mem.endsWith(u8, file.path, ".h") or std.mem.indexOfScalar(u8, file.path, '/') != null) continue;
        try headers.append(allocator, .{ .name = file.path, .bytes = file.bytes });
    }
    const table = try llvm.RuntimeTable.read(allocator, headers.items);
    var diagnostic: llvm.Diagnostic = .{ .unit = fixture };
    const header = try llvm.header(allocator, body, &diagnostic);
    var signatures: llvm.Signatures = .empty;
    try signatures.put(allocator, header.symbol, header.signature);
    return llvm.translate(allocator, body, .{ .signatures = &signatures, .runtime = &table }, &diagnostic);
}

fn llvmTranslation() !void {
    const body = try emitted(source, .llvm);
    defer t.allocator.free(body);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const ir = try translatedLlvm(arena.allocator(), body);
    try t.expect(std.mem.indexOf(u8, ir, " = urem i64 ") != null);
    try t.expect(std.mem.indexOf(u8, ir, " = srem i64 ") != null);
    const constant = std.mem.indexOf(u8, ir, bias_literal_line) orelse return error.TestUnexpectedResult;
    const start = std.mem.lastIndexOfScalar(u8, ir[0..constant], '\n') orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.indexOf(u8, ir[start..constant], " = add i64 ") != null);
    try t.expect(std.mem.indexOf(u8, ir[start..constant], "nsw") == null);
    const evidence = try std.json.Stringify.valueAlloc(arena.allocator(), .{ .kind = "translated_LLVM_IR_not_ELF", .ir = ir }, .{});
    test_log("BOUNDED-REMAINDER-LLVM-IR {s}\n", .{evidence});
}

// spec-case: QBE-LOOP-REMAINDER-BIAS-1
test "bounded remainder bias LLVM specializes and QBE keeps signed fast copy without changing negative admission" {
    try policies();
}

const Lowering = struct {
    scalar_policy: ScalarPolicy = .qbe,
    serial: usize = 40,
    output: std.ArrayList(u8) = .empty,
    pc: usize = 1,
    states: []const ?[]const u8 = &.{ "", "x" },
    function: struct { scope: struct { instructions: []const bytecode.Instruction } } = .{
        .scope = .{ .instructions = &.{.{ .span = .{ .start = 0, .end = 0 }, .op = .{ .push_i64 = 1009 } }} },
    },
    /// Supply a valid optional recipe; the default backend must ignore it.
    pub fn loopAction(_: *Lowering) ?facts.Action {
        return .{ .floor_remainder_bias = .{
            .recipe = @import("qbe_remainder_bias.zig").plan(8646911284551352320, 1009).?,
            .leaves = &.{},
        } };
    }
    /// This direct lowering fixture has no control-flow entry at its literal.
    pub fn isBranchTarget(_: *Lowering, _: usize) bool {
        return false;
    }
    /// Count every allocated temporary to detect a refused recipe's residue.
    pub fn temp(self: *Lowering) usize {
        const result = self.serial;
        self.serial += 1;
        return result;
    }
    /// Retain every emitted byte for comparison against the old recipe.
    pub fn print(self: *Lowering, comptime format: []const u8, arguments: anytype) @import("qbe_constant_divisor.zig").Error!void {
        const text = std.fmt.allocPrint(t.allocator, format, arguments) catch return error.OutOfMemory;
        defer t.allocator.free(text);
        self.output.appendSlice(t.allocator, text) catch return error.OutOfMemory;
    }
};

// spec-case: QBE-LOOP-REMAINDER-BIAS-1
test "bounded remainder bias QBE refusal preserves every old recipe byte and temporary" {
    const division = @import("qbe_constant_divisor.zig");
    var baseline: Lowering = .{};
    defer baseline.output.deinit(t.allocator);
    var candidate: Lowering = .{};
    defer candidate.output.deinit(t.allocator);
    const values: division.Values = .{ .left = 7, .right = 8, .result = 9 };
    const integer: @import("typed.zig").Type.Integer = .{ .bits = 64, .signed = true };
    try t.expect(!try remainder.lower(Lowering, &candidate, .floor_rem, integer, values));
    try t.expectEqual(@as(usize, 40), candidate.serial);
    try t.expectEqual(@as(usize, 0), candidate.output.items.len);
    try t.expect(try division.lower(Lowering, &baseline, .floor_rem, integer, values));
    try t.expect(try division.lower(Lowering, &candidate, .floor_rem, integer, values));
    try t.expectEqualStrings(baseline.output.items, candidate.output.items);
    try t.expectEqual(baseline.serial, candidate.serial);
    try t.expect(std.mem.indexOf(u8, candidate.output.items, signed_shift) != null);
}

// spec-case: QBE-LOOP-REMAINDER-BIAS-1
test "bounded remainder bias translated LLVM keeps unflagged add unsigned fast remainder and signed fallback" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    try llvmTranslation();
}

const Planner = struct {
    allocator: std.mem.Allocator,
    function: bytecode.Function,
    loop_plan: facts.Plan = .{},
    reference: bool = false,
    caller: bool = false,
    /// Model an ABI reference; validated scalar source parameters are words.
    pub fn byReference(self: *Planner, _: usize) bool {
        return self.reference;
    }
    /// Model caller-owned storage which cannot support a private leaf proof.
    pub fn callerStorage(self: *Planner, _: usize) bool {
        return self.caller;
    }
};

fn samePlan(a: facts.Plan, b: facts.Plan, allocator: std.mem.Allocator) !void {
    const left = try std.json.Stringify.valueAlloc(allocator, a, .{});
    const right = try std.json.Stringify.valueAlloc(allocator, b, .{});
    try t.expectEqualStrings(left, right);
    try t.expect(a.loops.len != 0);
}

fn oldStructure(allocator: std.mem.Allocator, plan: facts.Plan) !facts.Plan {
    const loops = try allocator.dupe(facts.Loop, plan.loops);
    for (loops) |*loop| {
        const actions = try allocator.dupe(facts.Action, loop.actions);
        for (actions) |*action| action.floor_remainder_bias = null;
        loop.actions = actions;
    }
    return .{ .nodes = plan.nodes, .loops = loops };
}

fn expressionPlan(expression: []const u8, expected_count: usize) !void {
    const input = try std.fmt.allocPrint(t.allocator,
        \\def calculate(n: int, seed: int, offset: int) -> int:
        \\    values: list[int] = []
        \\    for i in range(n):
        \\        values.append({s})
        \\    return len(values)
        \\def main() -> int:
        \\    return calculate(32, 17, 0)
        \\
    , .{expression});
    defer t.allocator.free(input);
    var compilation = try compiler.Compilation.init(t.allocator, fixture, input);
    defer compilation.deinit();
    try compilation.emit();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const program = compilation.code.?;
    for (program.functions) |function| {
        if (!std.mem.eql(u8, function.name, function_name)) continue;
        const ir = try @import("native_ir.zig").analyze(allocator, program, function);
        var options: facts.Input = .{ .program = program, .function = function, .states = ir.states };
        const plan = try facts.plan(allocator, options);
        var count: usize = 0;
        for (plan.loops) |loop| for (loop.actions) |action| {
            count += @intFromBool(action.floor_remainder_bias != null);
        };
        try t.expectEqual(expected_count, count);
        options.floor_remainder_bias = false;
        try samePlan(try facts.plan(allocator, options), try oldStructure(allocator, plan), allocator);
        return;
    }
    return error.TestUnexpectedResult;
}

// spec-case: QBE-LOOP-REMAINDER-BIAS-1
test "bounded remainder bias adds only metadata and missing old leaf powers and truncating operations preserve old plans" {
    try expressionPlan("(seed + offset + i * 13) % 1009", 1);
    try expressionPlan("seed % 1009", 0);
    try expressionPlan("remtrunc(seed + i * 13, 1009)", 0);
    try expressionPlan("(seed + i * 13) % 8", 0);
    try expressionPlan("(seed + i * 13) % -7", 0);
    try expressionPlan("((seed + i * 13) // 7) % 1009", 0);
    try expressionPlan("(seed * seed + i * 13) % 7", 1);
    try expressionPlan("(seed + i * 13) % 0", 0);
}

fn wideBiasEmission() !void {
    const wide = try std.mem.replaceOwned(u8, t.allocator, source, "% 1009", "% 4700000000000000000");
    defer t.allocator.free(wide);
    const body = try emitted(wide, .llvm);
    defer t.allocator.free(body);
    const loop = try parts(body);
    try t.expect(std.mem.indexOf(u8, loop.fast, ", -9046744073709551616\n") != null);
    try t.expect(std.mem.indexOf(u8, loop.fast, unsigned_remainder) != null);
    try t.expect(std.mem.indexOf(u8, loop.original, signed_remainder) != null);
}

// spec-case: QBE-LOOP-REMAINDER-BIAS-1
test "bounded remainder bias emits addends beyond signed range as exact wrapping bit patterns" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    try wideBiasEmission();
}

fn refusedPlan(reference: bool, caller: bool, large: bool) !void {
    var compilation = try compiler.Compilation.init(t.allocator, fixture, source);
    defer compilation.deinit();
    try compilation.emit();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const program = compilation.code.?;
    for (program.functions) |original| {
        if (!std.mem.eql(u8, original.name, function_name)) continue;
        var function = original;
        if (large) {
            const code = try allocator.alloc(bytecode.Instruction, 4097);
            @memcpy(code[0..original.scope.instructions.len], original.scope.instructions);
            @memset(code[original.scope.instructions.len..], .{ .span = .{ .start = 0, .end = 0 }, .op = .push_unit });
            function.scope.instructions = code;
        }
        const ir = try @import("native_ir.zig").analyze(allocator, program, function);
        var input: facts.Input = .{ .program = program, .function = function, .states = ir.states };
        var planner: Planner = .{ .allocator = allocator, .function = function, .reference = reference, .caller = caller };
        try remainder.plan(Planner, &planner, input);
        input.floor_remainder_bias = false;
        try samePlan(try facts.plan(allocator, input), planner.loop_plan, allocator);
        return;
    }
    return error.TestUnexpectedResult;
}

// spec-case: QBE-LOOP-REMAINDER-BIAS-1
test "bounded remainder bias cap and private reference refusal regenerate the exact old signed plan" {
    try refusedPlan(true, false, false);
    try refusedPlan(false, true, false);
    try refusedPlan(false, false, true);
}

fn same(a: native.Run, b: native.Run) !void {
    const left = try std.json.Stringify.valueAlloc(t.allocator, a, .{});
    defer t.allocator.free(left);
    const right = try std.json.Stringify.valueAlloc(t.allocator, b, .{});
    defer t.allocator.free(right);
    try t.expectEqualStrings(left, right);
}

fn outcome(seed: i64, offset: i64, count: i64, options: native.Options) !native.Run {
    const body = source[0..std.mem.indexOf(u8, source, main_marker).?];
    const input = try std.fmt.allocPrint(t.allocator, "{s}def main(out: Stream) -> int:\n    out.print(17)\n    return calculate({d}, {d}, {d})\n", .{ body, count, seed, offset });
    defer t.allocator.free(input);
    var compilation = try compiler.Compilation.init(t.allocator, fixture, input);
    defer compilation.deinit();
    const ordinary = try native.runWithOptions(&compilation, options);
    const fast = try native.runUnaccounted(&compilation, options);
    try same(ordinary, fast);
    const evidence = try std.json.Stringify.valueAlloc(t.allocator, .{ .seed = seed, .offset = offset, .count = count, .ordinary = ordinary, .fast = fast }, .{});
    defer t.allocator.free(evidence);
    test_log(outcome_format, .{evidence});
    return fast;
}

fn llvmPolicyCase(seed: i64, count: i64) !void {
    const body = source[0..std.mem.indexOf(u8, source, main_marker).?];
    const input = try std.fmt.allocPrint(t.allocator, "{s}def main(out: Stream) -> int:\n    out.print(17)\n    return calculate({d}, {d}, 0)\n", .{ body, count, seed });
    defer t.allocator.free(input);
    var compilation = try compiler.Compilation.init(t.allocator, fixture, input);
    defer compilation.deinit();
    const ordinary = try native.runWithPolicy(&compilation, .{ .scalar_policy = .llvm }, .{});
    const fast = try native.runWithPolicy(&compilation, .{ .scalar_policy = .llvm, .step_checks = false, .frame_checks = false }, .{});
    try same(ordinary, fast);
    const expected: i64 = if (count <= 0) 0 else count + @as(i64, @intCast(@mod(@as(i128, seed), 1009))) +
        @as(i64, @intCast(@mod(@as(i128, seed) + (count - 1) * 13, 1009)));
    try t.expect(!fast.failed);
    try t.expectEqual(expected, fast.value);
    try t.expectEqualStrings("17\n", fast.stdout);
    const evidence = try std.json.Stringify.valueAlloc(t.allocator, .{ .kind = "LLVM_policy_executed_by_QBE", .seed = seed, .count = count, .ordinary = ordinary, .fast = fast }, .{});
    defer t.allocator.free(evidence);
    test_log(outcome_format, .{evidence});
}

// spec-case: QBE-LOOP-REMAINDER-BIAS-1
test "bounded remainder bias LLVM scalar policy executed by QBE keeps negative positive and empty outcomes" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    try llvmPolicyCase(-1048576, 32);
    try llvmPolicyCase(17, 32);
    try llvmPolicyCase(std.math.minInt(i64), 32);
    try llvmPolicyCase(std.math.maxInt(i64), 0);
}

fn wideNativeCase(seed: i64) !void {
    const wide = try std.mem.replaceOwned(u8, t.allocator, source, "% 1009", "% 4700000000000000000");
    defer t.allocator.free(wide);
    const first = try std.mem.replaceOwned(u8, t.allocator, wide, "return len(values) + values[0] + values[-1]", "return values[0]");
    defer t.allocator.free(first);
    const body = first[0..std.mem.indexOf(u8, first, main_marker).?];
    const input = try std.fmt.allocPrint(t.allocator, "{s}def main(out: Stream) -> int:\n    out.print(17)\n    return calculate(32, {d}, 0)\n", .{ body, seed });
    defer t.allocator.free(input);
    var compilation = try compiler.Compilation.init(t.allocator, fixture, input);
    defer compilation.deinit();
    const ordinary = try native.runWithPolicy(&compilation, .{ .scalar_policy = .llvm }, .{});
    const fast = try native.runWithPolicy(&compilation, .{ .scalar_policy = .llvm, .step_checks = false, .frame_checks = false }, .{});
    try same(ordinary, fast);
    const expected: i64 = @intCast(@mod(@as(i128, seed), 4700000000000000000));
    try t.expect(!fast.failed);
    try t.expectEqual(expected, fast.value);
    try t.expectEqual(@as(u8, @truncate(@as(u64, @bitCast(expected)))), fast.status);
    try t.expectEqualStrings("17\n", fast.stdout);
    const evidence = try std.json.Stringify.valueAlloc(t.allocator, .{ .kind = "wide_bias_LLVM_policy_executed_by_QBE", .seed = seed, .ordinary = ordinary, .fast = fast }, .{});
    defer t.allocator.free(evidence);
    test_log(outcome_format, .{evidence});
}

// spec-case: QBE-LOOP-REMAINDER-BIAS-1
test "bounded remainder bias wide addend LLVM policy executed by QBE preserves full unsigned bits" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    try wideNativeCase(-1);
    try wideNativeCase(17);
    try wideNativeCase(-(1 << 59));
    try wideNativeCase(1 << 59);
}

fn endpointCase(seed: i64) !void {
    const scaled = try std.mem.replaceOwned(u8, t.allocator, source, "seed + offset + i * 13", "seed * 15 + i * 0");
    defer t.allocator.free(scaled);
    const body = scaled[0..std.mem.indexOf(u8, scaled, main_marker).?];
    const input = try std.fmt.allocPrint(t.allocator, "{s}def main(out: Stream) -> int:\n    out.print(17)\n    return calculate(32, {d}, 0)\n", .{ body, seed });
    defer t.allocator.free(input);
    const il = try emitted(input, .llvm);
    defer t.allocator.free(il);
    const loop = try parts(il);
    try t.expect(std.mem.indexOf(u8, loop.fast, bias_literal_line) != null);
    var compilation = try compiler.Compilation.init(t.allocator, fixture, input);
    defer compilation.deinit();
    const ordinary = try native.runWithPolicy(&compilation, .{ .scalar_policy = .llvm }, .{});
    const fast = try native.runWithPolicy(&compilation, .{ .scalar_policy = .llvm, .step_checks = false, .frame_checks = false }, .{});
    try same(ordinary, fast);
    const expected: i64 = @intCast(32 + 2 * @mod(@as(i128, seed) * 15, 1009));
    try t.expect(!fast.failed);
    try t.expectEqual(expected, fast.value);
    try t.expectEqualStrings("17\n", fast.stdout);
    const evidence = try std.json.Stringify.valueAlloc(t.allocator, .{ .kind = "exact_endpoint_LLVM_policy_executed_by_QBE", .seed = seed, .ordinary = ordinary, .fast = fast }, .{});
    defer t.allocator.free(evidence);
    test_log(outcome_format, .{evidence});
}

// spec-case: QBE-LOOP-REMAINDER-BIAS-1
test "bounded remainder bias LLVM policy executed by QBE reaches both exact magnitude endpoints" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    try endpointCase(-(1 << 59));
    try endpointCase(1 << 59);
}

const referenced =
    \\record Box:
    \\    value: int
    \\def touch(box: mut Box, n: int) -> None:
    \\    if n > 0:
    \\        touch(mut box, n - 1)
    \\    else:
    \\        box.value += 1
    \\def calculate(box: mut Box, n: int) -> int:
    \\    seed = box.value
    \\    touch(mut box, 0)
    \\    total = 0
    \\    for i in range(n):
    \\        total += (seed + i * 13) % 1009
    \\    return total + box.value
    \\def main() -> int:
    \\    box = Box(17)
    \\    return calculate(mut box, 32)
;

fn referenceCount(program: bytecode.Program) usize {
    var count: usize = 0;
    for (program.functions) |function| {
        if (!std.mem.eql(u8, function.name, function_name)) continue;
        for (function.scope.instructions) |instruction| count += @intFromBool(instruction.op == .ref_local);
    }
    return count;
}

// spec-case: QBE-LOOP-REMAINDER-BIAS-1
test "bounded remainder bias referenced aggregate leaves its detached private scalar eligible" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.gc);
    const il = try emitted(referenced, .llvm);
    defer t.allocator.free(il);
    try t.expect(std.mem.indexOf(u8, (try parts(il)).fast, signed_shift) == null);
    var compilation = try compiler.Compilation.init(t.allocator, fixture, referenced);
    defer compilation.deinit();
    try compilation.emit();
    try t.expect(referenceCount(compilation.code.?) > 0);
    const ordinary = try native.runWithPolicy(&compilation, .{ .scalar_policy = .llvm }, .{});
    const fast = try native.runWithPolicy(&compilation, .{ .scalar_policy = .llvm, .step_checks = false, .frame_checks = false }, .{});
    try same(ordinary, fast);
    try t.expect(!fast.failed);
    try t.expectEqual(@as(i64, 7010), fast.value);
    try t.expectEqual(@as(u8, 98), fast.status);
    try t.expectEqualStrings("", fast.stdout);
    const evidence = try std.json.Stringify.valueAlloc(t.allocator, .{ .kind = "detached_private_scalar_LLVM_policy_executed_by_QBE_GC", .ordinary = ordinary, .fast = fast }, .{});
    defer t.allocator.free(evidence);
    test_log(outcome_format, .{evidence});
}

fn movedScalar(compilation: *compiler.Compilation) !void {
    try compilation.emit();
    const allocator = compilation.arena.allocator();
    var program = compilation.code.?;
    const functions = try allocator.dupe(bytecode.Function, program.functions);
    program.functions = functions;
    for (functions) |*function| {
        if (!std.mem.eql(u8, function.name, function_name)) continue;
        const old = function.scope.instructions;
        const code = try allocator.alloc(bytecode.Instruction, old.len + 2);
        code[0] = .{ .span = old[0].span, .op = .{ .move_local = @fromBackingInt(@intCast(1)) } };
        code[1] = .{ .span = old[0].span, .op = .pop };
        @memcpy(code[2..], old);
        for (code[2..]) |*instruction| {
            switch (instruction.op) {
                .jump, .jump_if_false => |*target| target.* += 2,
                else => {},
            }
            if (instruction.inline_origin) |*origin| origin.call_position += 2;
        }
        function.scope.instructions = code;
    }
    try bytecode.validate(allocator, program);
    compilation.code = program;
}

fn movedEmission(allocator: std.mem.Allocator) ![]u8 {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.gc);
    var compilation = try compiler.Compilation.init(allocator, fixture, source);
    defer compilation.deinit();
    try movedScalar(&compilation);
    return compilation.emitQbeWithOptions(allocator, .{ .step_checks = false, .frame_checks = false });
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    const text = try movedEmission(allocator);
    defer allocator.free(text);
}

fn retainedSignedCopy() !void {
    const text = try movedEmission(t.allocator);
    defer t.allocator.free(text);
    var parsed = try std.json.parseFromSlice(Manifest, t.allocator, text, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    for (parsed.value.functions) |function| {
        if (!std.mem.eql(u8, function.name, function_name)) continue;
        const loop = try parts(function.il);
        try t.expect(std.mem.indexOf(u8, loop.fast, signed_shift) != null);
        try t.expect(std.mem.indexOf(u8, loop.fast, bias_literal_line) == null);
        return;
    }
    return error.TestUnexpectedResult;
}

// spec-case: QBE-LOOP-REMAINDER-BIAS-1
test "bounded remainder bias valid moved scalar keeps collector signed copy and cleans every abandoned allocation" {
    try retainedSignedCopy();
    try t.checkAllAllocationFailures(t.allocator, allocationScenario, .{});
}

fn success(seed: i64, count: i64) !void {
    const result = try outcome(seed, 0, count, .{});
    const value: i64 = if (count <= 0) 0 else count + @as(i64, @intCast(@mod(@as(i128, seed), 1009))) +
        @as(i64, @intCast(@mod(@as(i128, seed) + (count - 1) * 13, 1009)));
    try t.expect(!result.failed);
    try t.expectEqual(value, result.value);
    try t.expectEqual(@as(u8, @truncate(@as(u64, @bitCast(value)))), result.status);
    try t.expectEqualStrings("17\n", result.stdout);
}

fn nativeCases() !void {
    for ([_]i64{ -1048576, -1, 0, 17, (1 << 59), -(1 << 59) }) |seed| {
        try success(seed, 32);
        try success(seed, 3);
        try success(seed, 0);
    }
    try success(std.math.minInt(i64), 32);
    const empty = try outcome(std.math.maxInt(i64), 1, 0, .{});
    try t.expect(!empty.failed and empty.value == 0);
    const overflow = try outcome(std.math.maxInt(i64), 1, 32, .{});
    try t.expect(overflow.failed);
    try t.expectEqualStrings(overflow_code, overflow.trap.code);
    const negative = try outcome(std.math.minInt(i64), -1, 32, .{});
    try t.expect(negative.failed);
    try t.expectEqualStrings(overflow_code, negative.trap.code);
    const later = try outcome(std.math.maxInt(i64), 0, 32, .{});
    try t.expect(later.failed);
    try t.expectEqualStrings(overflow_code, later.trap.code);
    const memory = try outcome(17, 0, 400000, .{ .max_memory = 1 << 20 });
    try t.expect(memory.failed);
    try t.expectEqualStrings("R_MEMORY_BUDGET", memory.trap.code);
}

// spec-case: QBE-LOOP-REMAINDER-BIAS-1
test "bounded remainder bias native success negative old range fallback and first refusal retain complete outcomes" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    try nativeCases();
}

// spec-case: QBE-LOOP-REMAINDER-BIAS-1
test "bounded remainder bias collector mode preserves negative admitted and overflowing fallback outcomes" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.gc);
    try success(-1048576, 32);
    try success(17, 32);
    const overflow = try outcome(std.math.minInt(i64), -1, 32, .{});
    try t.expect(overflow.failed);
    try t.expectEqualStrings(overflow_code, overflow.trap.code);
}
