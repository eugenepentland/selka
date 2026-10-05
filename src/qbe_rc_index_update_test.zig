//! Checked update indices preserve first errors and scalar snapshot semantics.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const native = @import("native_execute.zig");
const interface = @import("native_interface.zig");
const model = @import("qbe_rc_index_update.zig");
const bytecode = @import("bytecode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const marker = "# RC-INDEX-UPDATE-1";
const functions =
    \\def update(index: int, delta: int, shared: bool) -> int:
    \\    values = [7, 11]
    \\    snapshot = values if shared else [0, 0]
    \\    values[index] = values[index] + delta
    \\    return values[index] + snapshot[index] * 100
    \\def modulo(index: int, divisor: int, shared: bool) -> int:
    \\    values = [7, 11]
    \\    snapshot = values if shared else [0, 0]
    \\    values[index] = (values[index] + 1) % divisor
    \\    return values[index] + snapshot[index] * 100
    \\def quotient(index: int, divisor: int) -> int:
    \\    values = [-9223372036854775807 - 1, 11]
    \\    values[index] = values[index] // divisor
    \\    return values[index]
    \\def checksum_update(index: int, delta: int, shared: bool) -> int:
    \\    values = [7, 11]
    \\    snapshot = values if shared else [0, 0]
    \\    values[index] = (values[index] + delta) % 1000003
    \\    checksum = 29
    \\    checksum = (checksum + values[index]) % 1000000007
    \\    return checksum + values[0] + values[1] + snapshot[index] * 100
    \\def combine(values: list[int], value: int) -> int:
    \\    return values[0] + value
    \\def managed_prefix(index: int, delta: int) -> int:
    \\    values = [7, 11]
    \\    values[index] = values[index] + delta
    \\    return combine(values, values[index])
    \\def shared_read(index: int, delta: int) -> int:
    \\    values = [7, 11]
    \\    snapshot = values
    \\    values[index] = values[index] + delta
    \\    return snapshot[index] + values[index] + values[0] + values[1]
    \\def provenance(index: int, delta: int) -> int:
    \\    values = [7, 11]
    \\    next_value = values[index] + delta
    \\    values[index] = next_value
    \\    return values[index]
    \\def empty(index: int) -> int:
    \\    values: list[int] = []
    \\    values[index] = values[index] + 1
    \\    return values[index]
    \\def descriptor(index: int) -> int:
    \\    values = [7, 11]
    \\    flags = [True, False]
    \\    values[index] = values[index] + 3
    \\    return values[index] + (1 if flags[0] else 0)
    \\def alias(index: int, delta: int) -> int:
    \\    values = [7, 11]
    \\    next_value = values[index] + delta
    \\    snapshot = values
    \\    values[index] = next_value
    \\    return snapshot[index] * 100 + values[index]
    \\def rebound(index: int, delta: int) -> int:
    \\    values = [7, 11]
    \\    next_value = values[index] + delta
    \\    values = [19, 23]
    \\    values[index] = next_value
    \\    return values[index]
    \\def resized(index: int, delta: int) -> int:
    \\    values = [7, 11]
    \\    next_value = values[index] + delta
    \\    values.clear()
    \\    values.append(17)
    \\    values[index] = next_value
    \\    return values[index]
    \\def change(values: mut list[int]) -> int:
    \\    values.clear()
    \\    values.append(17)
    \\    return 0
    \\def callback(index: int) -> int:
    \\    values = [7, 11]
    \\    mutation_result_84 = change(mut values)
    \\    values[index] = values[index] + mutation_result_84
    \\    return values[index]
    \\def distinct(index: int) -> int:
    \\    left = [7, 11]
    \\    right = [19, 23]
    \\    right[index] = left[index] + 3
    \\    return right[index]
    \\def changed_index(index: int) -> int:
    \\    values = [7, 11]
    \\    next_value = values[index] + 3
    \\    index = (index + 1) % 2
    \\    values[index] = next_value
    \\    return values[index]
    \\def narrow(index: int) -> i32:
    \\    values: list[i32] = [7, 11]
    \\    values[index] = values[index] + 3
    \\    return values[index]
    \\def managed(index: int) -> int:
    \\    values = [[7], [11]]
    \\    values[index] = values[index]
    \\    return values[index][0]
    \\def repeat(times: int, index: int) -> int:
    \\    values = [7, 11]
    \\    total = 0
    \\    for at in range(times):
    \\        values[index] = values[index] + at + 1
    \\        total += values[index]
    \\    return total + values[0] + values[1]
    \\
;
const source = functions ++
    \\def main() -> int:
    \\    return update(-1, 3, True)
;

fn emitted(policy: interface.Policy) !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "index_update.my", source);
    defer compilation.deinit();
    return fromCompilation(&compilation, policy);
}

fn fromCompilation(compilation: *compiler.Compilation, policy: interface.Policy) !std.json.Parsed(Manifest) {
    const text = try compilation.emitQbeWithOptions(t.allocator, policy);
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}

fn body(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}

const unaccounted: interface.Policy = .{ .step_checks = false, .frame_checks = false };

// spec: RC-INDEX-UPDATE-1
test "RC index update reuses checked indices and forwards exact stored i64 values" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var result = try emitted(unaccounted);
    defer result.deinit();
    const il = try body(result.value, "update");
    try t.expectEqual(@as(usize, 3), std.mem.count(u8, il, marker));
    try t.expect(std.mem.indexOf(u8, il, "# QBE-POSITIVE-INDEX-1") != null);
    try t.expect(std.mem.indexOf(u8, il, "myl_qbe_fail_normalized_index_bounds") != null);
    try t.expect(std.mem.indexOf(u8, il, "myl_qbe_rc_unique_local") != null);
    try t.expect(std.mem.indexOf(u8, il, "myl_qbe_fail_overflow_op") != null);
    const provenance = try body(result.value, "provenance");
    try t.expectEqual(@as(usize, 3), std.mem.count(u8, provenance, marker));
    try t.expectEqual(@as(usize, 3), std.mem.count(u8, try body(result.value, "modulo"), marker));
    try t.expectEqual(@as(usize, 3), std.mem.count(u8, try body(result.value, "quotient"), marker));
    try t.expectEqual(@as(usize, 3), std.mem.count(u8, try body(result.value, "checksum_update"), marker));
    // Once the mut call finishes, the current receiver admits the same update.
    try t.expectEqual(@as(usize, 3), std.mem.count(u8, try body(result.value, "callback"), marker));
    // The complete first negative correction remains, including its checked
    // cast/add cold path; a valid native i64-list length cannot overflow it.
    try t.expect(std.mem.indexOf(u8, provenance, "myl_qbe_fail_overflow_op") != null);
    for ([_][]const u8{ "alias", "rebound", "resized", "distinct", "changed_index", "narrow", "managed" }) |name|
        try t.expect(std.mem.indexOf(u8, try body(result.value, name), marker) == null);
}

// spec-case: RC-INDEX-UPDATE-1
test "RC index update preserves accounted collector counted and site fallbacks" {
    const saved = runtime.get();
    defer runtime.set(saved);
    for ([_]runtime.Selection{ .rc_counting, .rc_sites, .gc }) |selection| {
        runtime.set(selection);
        var result = try emitted(unaccounted);
        defer result.deinit();
        try t.expect(std.mem.indexOf(u8, try body(result.value, "update"), marker) == null);
    }
    runtime.set(.rc);
    try accountedFallbacks();
}

fn accountedFallbacks() !void {
    for ([_]interface.Policy{
        .{ .step_checks = true, .frame_checks = false },
        .{ .step_checks = false, .frame_checks = true },
    }) |policy| {
        var result = try emitted(policy);
        defer result.deinit();
        try t.expect(std.mem.indexOf(u8, try body(result.value, "update"), marker) == null);
    }
}

// spec-case: RC-INDEX-UPDATE-1
test "RC index update audits alternate entries Result edges and switch arms" {
    const span: @import("source.zig").Span = .{ .start = 0, .end = 0 };
    var code: [70]bytecode.Instruction = @splat(.{ .span = span, .op = .push_unit });
    const read: model.Access = .{ .start = 8, .index = 0, .owner = 1, .at = 18, .write = false };
    const write: model.Access = .{ .start = 32, .index = 2, .owner = 3, .at = 43, .write = true };
    const proof: model.Proof = .{ .read = read, .write = write, .root = 4, .source = 5, .value = 6 };
    code[11].op = .{ .jump_if_false = 17 };
    code[35].op = .{ .jump_if_false = 41 };
    try t.expect(model.entries(&code, 4, 43, proof, null));
    const targets = [_]usize{ 5, 8, 17, 18, 28, 32, 41, 43 };
    for (targets) |target| {
        code[69].op = .{ .try_result = .{ .input = .i64, .output = .i64, .error_target = target } };
        try t.expect(!model.entries(&code, 4, 43, proof, null));
        code[69].op = .{ .jump = target };
        try t.expect(!model.entries(&code, 4, 43, proof, null));
    }
    code[69].op = .{ .switch_variant = .{ .ty = .i64, .arms = &.{.{ .target = 41, .slot = null }} } };
    try t.expect(!model.entries(&code, 4, 43, proof, null));
    code[69].op = .{ .jump = 4 };
    try t.expect(model.entries(&code, 4, 43, proof, null));
}

fn checkedFunction(compilation: *compiler.Compilation, name: []const u8) !*bytecode.Function {
    for (@constCast(compilation.code.?.functions)) |*function|
        if (std.mem.eql(u8, function.name, name)) return function;
    return error.TestUnexpectedResult;
}

fn firstWrite(function: *bytecode.Function) !model.Access {
    for (0..function.scope.instructions.len) |pc| {
        const access = model.normalizer(function.scope.instructions, pc) orelse continue;
        if (access.write) return access;
    }
    return error.TestUnexpectedResult;
}

// spec-case: RC-INDEX-UPDATE-1
test "RC index update emitter refuses extra join entries references and descriptor mismatch" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    for (0..4) |case| {
        var compilation = try compiler.Compilation.init(t.allocator, "forged_index_update.my", source);
        defer compilation.deinit();
        try compilation.emit();
        const function = try checkedFunction(&compilation, "descriptor");
        const write = try firstWrite(function);
        const original = function.scope.instructions;
        const code = try t.allocator.alloc(bytecode.Instruction, original.len + 2);
        defer t.allocator.free(code);
        @memcpy(code[0..original.len], original);
        code[original.len] = .{ .span = original[write.at].span, .op = .push_unit };
        code[original.len + 1] = .{ .span = original[write.at].span, .op = .pop };
        if (case == 0) {
            // An unreachable predecessor still forbids assuming that the
            // normalized index or exact RHS was initialized on every entry.
            code[original.len].op = .{ .jump = write.start + 9 };
        } else if (case == 1 or case == 2) {
            const id = if (case == 1) original[write.start - 2].op.load_local else original[write.at - 1].op.load_local;
            code[original.len].op = .{ .ref_local = id };
        } else {
            var other: ?@import("typed.zig").Type = null;
            for (function.scope.locals) |local_| if (std.mem.eql(u8, local_.name, "flags")) {
                other = local_.ty;
                break;
            };
            @constCast(function.scope.locals)[write.owner].ty = other orelse return error.TestUnexpectedResult;
        }
        function.scope.instructions = code;
        var result = try fromCompilation(&compilation, unaccounted);
        defer result.deinit();
        try t.expect(std.mem.indexOf(u8, try body(result.value, "descriptor"), marker) == null);
    }
}

// spec-case: RC-INDEX-UPDATE-1
test "RC index update following prefixes refuse extra entries and receiver references" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    const name = "checksum_update";
    for (0..2) |case| {
        var compilation = try compiler.Compilation.init(t.allocator, "forged_prefix.my", source);
        defer compilation.deinit();
        try compilation.emit();
        const function = try checkedFunction(&compilation, name);
        const read = try followingRead(function, try firstWrite(function));
        const original = function.scope.instructions;
        const code = try t.allocator.alloc(bytecode.Instruction, original.len + 2);
        defer t.allocator.free(code);
        @memcpy(code[0..original.len], original);
        code[original.len] = .{ .span = original[read.at].span, .op = .push_unit };
        code[original.len + 1] = .{ .span = original[read.at].span, .op = .pop };
        prefixCounterexample(code, original.len, read, case);
        function.scope.instructions = code;
        var result = try fromCompilation(&compilation, unaccounted);
        defer result.deinit();
        try t.expect(std.mem.indexOf(u8, try body(result.value, name), "# RC-INDEX-UPDATE-1 value") == null);
    }
}

fn followingRead(function: *bytecode.Function, write: model.Access) !model.Access {
    for (write.at + 1..function.scope.instructions.len) |pc| {
        const access = model.normalizer(function.scope.instructions, pc) orelse continue;
        if (!access.write) return access;
    }
    return error.TestUnexpectedResult;
}

fn prefixCounterexample(code: []bytecode.Instruction, pc: usize, read: model.Access, case: usize) void {
    if (case == 0) {
        code[pc].op = .{ .jump = read.start + 9 };
    } else {
        code[pc].op = .{ .ref_local = @fromBackingInt(read.owner) };
    }
}

const native_source = functions ++
    \\def number(text: str) -> int:
    \\    match int(text):
    \\        case Some(value):
    \\            return value
    \\        case None:
    \\            return 0
    \\def main(args: list[str], out: Stream) -> int:
    \\    out.print(41)
    \\    index = number(args[1])
    \\    delta = number(args[2])
    \\    if args[0] == "modulo" or args[0] == "modulo_shared":
    \\        return modulo(index, delta, args[0] == "modulo_shared")
    \\    if args[0] == "quotient":
    \\        return quotient(index, delta)
    \\    if args[0] == "checksum" or args[0] == "checksum_shared":
    \\        return checksum_update(index, delta, args[0] == "checksum_shared")
    \\    if args[0] == "managed_prefix":
    \\        return managed_prefix(index, delta)
    \\    if args[0] == "shared_read":
    \\        return shared_read(index, delta)
    \\    if args[0] == "alias":
    \\        return alias(index, delta)
    \\    if args[0] == "rebound":
    \\        return rebound(index, delta)
    \\    if args[0] == "resized":
    \\        return resized(index, delta)
    \\    if args[0] == "callback":
    \\        return callback(index)
    \\    if args[0] == "distinct":
    \\        return distinct(index)
    \\    if args[0] == "changed":
    \\        return changed_index(index)
    \\    if args[0] == "provenance":
    \\        return provenance(index, delta)
    \\    if args[0] == "empty":
    \\        return empty(index)
    \\    if args[0] == "repeat":
    \\        return repeat(delta, index)
    \\    return update(index, delta, args[0] == "shared")
;

fn outcome(compilation: *compiler.Compilation, name: []const u8, index: i64, delta: i64) !native.Run {
    const index_text = try std.fmt.allocPrint(t.allocator, "{d}", .{index});
    defer t.allocator.free(index_text);
    const delta_text = try std.fmt.allocPrint(t.allocator, "{d}", .{delta});
    defer t.allocator.free(delta_text);
    const options: native.Options = .{ .arguments = &.{ "--", name, index_text, delta_text } };
    const ordinary = try native.runWithOptions(compilation, options);
    const fast = try native.runUnaccounted(compilation, options);
    try t.expectEqualDeep(ordinary, fast);
    try t.expectEqualStrings("41\n", fast.stdout);
    return fast;
}

// spec-case: RC-INDEX-UPDATE-1
test "RC index update executes positive negative shared boundaries and overflow exactly" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "native_index_update.my", native_source);
    defer compilation.deinit();
    for ([_]i64{ -2, -1, 0, 1 }) |index| {
        const initial: i64 = if (index == -2 or index == 0) 7 else 11;
        for ([_]bool{ false, true }) |shared| {
            const result = try outcome(&compilation, if (shared) "shared" else "unique", index, 3);
            try t.expect(!result.failed);
            try t.expectEqual(initial + 3 + (if (shared) initial * 100 else @as(i64, 0)), result.value);
            try t.expectEqual(@as(u8, @intCast(@as(u64, @bitCast(result.value)) & 255)), result.status);
        }
    }
    try invalidIndices(&compilation);
    const overflow = try outcome(&compilation, "shared", 0, std.math.maxInt(i64));
    try t.expect(overflow.failed);
    try t.expectEqualStrings("R_OVERFLOW", overflow.trap.code);
    try forwardedBits(&compilation);
}

fn invalidIndices(compilation: *compiler.Compilation) !void {
    for ([_]i64{ -3, 2, std.math.minInt(i64), std.math.maxInt(i64) }) |index| {
        const result = try outcome(compilation, "shared", index, 3);
        try t.expect(result.failed);
        try t.expectEqualStrings("R_LIST_BOUNDS", result.trap.code);
    }
}

fn forwardedBits(compilation: *compiler.Compilation) !void {
    for ([_]i64{ std.math.minInt(i64), -10, std.math.maxInt(i64) - 11 }) |delta| {
        const bits = try outcome(compilation, "provenance", 1, delta);
        try t.expect(!bits.failed);
        try t.expectEqual(@as(i64, 11) + delta, bits.value);
        try t.expectEqual(@as(u8, @intCast(@as(u64, @bitCast(bits.value)) & 255)), bits.status);
    }
}

// spec-case: RC-INDEX-UPDATE-1
test "RC index update keeps floor remainder signs and division failure before COW" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "modulo_index_update.my", native_source);
    defer compilation.deinit();
    for ([_]i64{ -5, -3, 3, 5 }, [_]i64{ -3, 0, 0, 2 }) |divisor, expected| {
        for ([_]bool{ false, true }) |shared| {
            const name = if (shared) "modulo_shared" else "modulo";
            const result = try outcome(&compilation, name, -1, divisor);
            try t.expect(!result.failed);
            try t.expectEqual(expected + (if (shared) @as(i64, 1100) else 0), result.value);
        }
    }
    const failure = try outcome(&compilation, "modulo_shared", -1, 0);
    try t.expect(failure.failed);
    try t.expectEqualStrings("R_DIVISION_BY_ZERO", failure.trap.code);
    try t.expectEqual(sourceLine("    values[index] = (values[index] + 1) % divisor"), failure.trap.line);
    try t.expectEqual(@as(i64, 12), failure.trap.detail.values.left);
    try t.expectEqual(@as(i64, 0), failure.trap.detail.values.right);
    try quotientOutcomes(&compilation);
}

fn quotientOutcomes(compilation: *compiler.Compilation) !void {
    const name = "quotient";
    for ([_]i64{ -3, 3 }, [_]i64{ -4, 3 }) |divisor, expected| {
        const result = try outcome(compilation, name, -1, divisor);
        try t.expect(!result.failed);
        try t.expectEqual(expected, result.value);
    }
    const bits = try outcome(compilation, name, 0, 1);
    try t.expect(!bits.failed);
    try t.expectEqual(std.math.minInt(i64), bits.value);
    const overflow = try outcome(compilation, name, 0, -1);
    try t.expect(overflow.failed);
    try t.expectEqualStrings("R_OVERFLOW", overflow.trap.code);
    try t.expectEqual(sourceLine("    values[index] = values[index] // divisor"), overflow.trap.line);
    try t.expectEqual(std.math.minInt(i64), overflow.trap.detail.values.left);
    try t.expectEqual(@as(i64, -1), overflow.trap.detail.values.right);
}

// spec-case: RC-INDEX-UPDATE-1
test "RC index update forwards checksum prefixes but keeps managed and snapshot read fallbacks" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var result = try emitted(unaccounted);
    defer result.deinit();
    for ([_][]const u8{ "managed_prefix", "shared_read" }) |name| {
        const il = try body(result.value, name);
        try t.expect(std.mem.indexOf(u8, il, "# RC-INDEX-UPDATE-1 value") == null);
        try t.expect(std.mem.indexOf(u8, il, "myl_qbe_fail_normalized_index_bounds") != null);
    }
    var compilation = try compiler.Compilation.init(t.allocator, "checksum_index_update.my", native_source);
    defer compilation.deinit();
    try checksumOutcomes(&compilation);
    try prefixFallbackOutcomes(&compilation);
    const first = try outcome(&compilation, "checksum_shared", std.math.minInt(i64), 3);
    try bounds(first, std.math.minInt(i64), 2, sourceLine("    values[index] = (values[index] + delta) % 1000003"));
}

fn prefixFallbackOutcomes(compilation: *compiler.Compilation) !void {
    for ([_][]const u8{ "managed_prefix", "shared_read" }, [_]i64{ 21, 46 }) |name, expected| {
        const outcome_ = try outcome(compilation, name, -1, 3);
        try t.expect(!outcome_.failed);
        try t.expectEqual(expected, outcome_.value);
    }
}

fn checksumOutcomes(compilation: *compiler.Compilation) !void {
    for ([_]i64{ -2, -1, 0, 1 }) |index| {
        const initial: i64 = if (index == -2 or index == 0) 7 else 11;
        for ([_]i64{ -10, 3 }) |delta| {
            const next = @mod(initial + delta, 1000003);
            for ([_]bool{ false, true }) |shared| {
                const name = if (shared) "checksum_shared" else "checksum";
                const result = try outcome(compilation, name, index, delta);
                try t.expect(!result.failed);
                try t.expectEqual(47 - initial + next * 2 + (if (shared) initial * 100 else 0), result.value);
            }
        }
    }
}

fn sourceLine(text: []const u8) u64 {
    const at = std.mem.indexOf(u8, source, text).?;
    return @intCast(std.mem.count(u8, source[0..at], "\n") + 1);
}

fn bounds(result: native.Run, index: i64, length: u64, line: u64) !void {
    const detail = @import("native_trap_detail.zig");
    try t.expect(result.failed);
    try t.expectEqualStrings("R_LIST_BOUNDS", result.trap.code);
    try t.expectEqual(line, result.trap.line);
    try t.expect(result.trap.detail.has(detail.present_index));
    try t.expect(result.trap.detail.has(detail.present_length));
    try t.expectEqual(index, result.trap.detail.values.index);
    try t.expectEqual(length, result.trap.detail.values.length);
}

// spec-case: RC-INDEX-UPDATE-1
test "RC index update preserves first read versus later write failure provenance" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "index_provenance.my", native_source);
    defer compilation.deinit();
    for ([_]i64{ -3, 2, std.math.minInt(i64), std.math.maxInt(i64) }) |index|
        try bounds(try outcome(&compilation, "provenance", index, 3), index, 2, sourceLine("    next_value = values[index] + delta"));
    try emptyIndices(&compilation);
    try bounds(try outcome(&compilation, "resized", 1, 3), 1, 1, sourceLine("    values[index] = next_value\n    return values[index]\ndef change"));
    const overflow = try outcome(&compilation, "provenance", 0, std.math.maxInt(i64));
    try t.expect(overflow.failed);
    try t.expectEqualStrings("R_OVERFLOW", overflow.trap.code);
    try t.expectEqual(sourceLine("    next_value = values[index] + delta"), overflow.trap.line);
    try t.expectEqual(@as(i64, 7), overflow.trap.detail.values.left);
    try t.expectEqual(std.math.maxInt(i64), overflow.trap.detail.values.right);
}

fn emptyIndices(compilation: *compiler.Compilation) !void {
    for ([_]i64{ -1, 0 }) |index|
        try bounds(try outcome(compilation, "empty", index, 3), index, 0, sourceLine("    values[index] = values[index] + 1"));
}

// spec-case: RC-INDEX-UPDATE-1
test "RC index update preserves zero trips arena collector and counting outcomes" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "index_fallbacks.my", native_source);
    defer compilation.deinit();
    const zero = try outcome(&compilation, "repeat", std.math.minInt(i64), 0);
    try t.expect(!zero.failed);
    try t.expectEqual(@as(i64, 18), zero.value);
    const repeated = try outcome(&compilation, "repeat", -1, 3);
    try t.expect(!repeated.failed);
    try t.expectEqual(@as(i64, 67), repeated.value);
    runtime.set(.gc);
    const collected = try outcome(&compilation, "shared", -1, 3);
    try t.expect(!collected.failed);
    try t.expectEqual(@as(i64, 1114), collected.value);
    runtime.set(.rc);
    const stressed = try native.runUnaccounted(&compilation, .{ .arguments = &.{ "--", "shared", "-1", "3" }, .gc_stress = true });
    try t.expect(!stressed.failed);
    try t.expectEqual(@as(i64, 1114), stressed.value);
    const limited = try native.runWithOptions(&compilation, .{ .arguments = &.{ "--", "shared", "-1", "3" }, .max_steps = 1 });
    try t.expect(limited.failed);
    try t.expectEqualStrings("R_STEP_LIMIT", limited.trap.code);
    var arena_compilation = try compiler.Compilation.init(t.allocator, "arena_index_update.my",
        \\def main(out: Stream) -> int:
        \\    with arena():
        \\        values = [7, 11]
        \\        index = -1
        \\        values[index] = values[index] + 3
        \\        result = values[index]
        \\    out.print(41)
        \\    return result
    );
    defer arena_compilation.deinit();
    var arena_il = try fromCompilation(&arena_compilation, unaccounted);
    defer arena_il.deinit();
    try t.expect(std.mem.indexOf(u8, try body(arena_il.value, "main"), marker) == null);
    const ordinary_arena = try native.run(&arena_compilation);
    const fast_arena = try native.runUnaccounted(&arena_compilation, .{});
    try t.expectEqualDeep(ordinary_arena, fast_arena);
    try t.expect(!fast_arena.failed);
    try t.expectEqual(@as(i64, 14), fast_arena.value);
    try t.expectEqualStrings("41\n", fast_arena.stdout);
}

fn countedProcess(compilation: *compiler.Compilation, policy: interface.Policy) !std.process.RunResult {
    const session = try @import("wiring/native_session.zig").acquire();
    const allocator = session.allocator();
    const text = try compilation.emitQbeWithOptions(t.allocator, policy);
    defer t.allocator.free(text);
    const executable = try native.program(session, text);
    var environment = try session.environ.clone(allocator);
    defer environment.deinit();
    try environment.put(@import("memory_budget").variable, "536870912");
    try @import("qbe_build.zig").runtime_options.apply(allocator, &environment, &.{"--print-result"});
    return std.process.run(allocator, session.io, .{
        .argv = &.{ executable, "shared", "-1", "3" },
        .environ_map = &environment,
        .stdout_limit = .limited(1 << 20),
        .stderr_limit = .limited(1 << 20),
    });
}

// spec-case: RC-INDEX-UPDATE-1
test "RC index update preserves actual counting and site reports with positive native oracles" {
    const saved = runtime.get();
    defer runtime.set(saved);
    var compilation = try compiler.Compilation.init(t.allocator, "counted_index_update.my", native_source);
    defer compilation.deinit();
    for ([_]runtime.Selection{ .rc_counting, .rc_sites }) |selection| {
        runtime.set(selection);
        const ordinary = try countedProcess(&compilation, .{});
        const fast = try countedProcess(&compilation, unaccounted);
        try t.expectEqual(ordinary.term, fast.term);
        try t.expectEqualStrings(ordinary.stdout, fast.stdout);
        try t.expectEqual(std.process.Child.Term{ .exited = 90 }, fast.term);
        try t.expectEqualStrings("41\n1114\n", fast.stdout);
        try t.expect(std.mem.startsWith(u8, fast.stderr, "MYLANG_RC_COUNTS {"));
        // Physical event totals agree. The existing positive-read lowering
        // adds two zero-event sites under unaccounted policy, so inventories
        // from distinct accounting policies are intentionally not identical.
        const ordinary_end = std.mem.indexOfScalar(u8, ordinary.stderr, '\n').?;
        const fast_end = std.mem.indexOfScalar(u8, fast.stderr, '\n').?;
        try t.expectEqualStrings(ordinary.stderr[0..ordinary_end], fast.stderr[0..fast_end]);
    }
}

// spec-case: RC-INDEX-UPDATE-1
test "RC index update executes aliases rebinds resizes and calls before updates" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "refused_index_update.my", native_source);
    defer compilation.deinit();
    for ([_][]const u8{ "alias", "rebound", "resized", "callback", "distinct", "changed" }, [_]i64{ 710, 10, 10, 17, 10, 10 }) |name, expected| {
        const result = try outcome(&compilation, name, 0, 3);
        try t.expect(!result.failed);
        try t.expectEqual(expected, result.value);
    }
    const resized = try outcome(&compilation, "resized", 1, 3);
    try t.expect(resized.failed);
    try t.expectEqualStrings("R_LIST_BOUNDS", resized.trap.code);
}

// spec-case: RC-INDEX-UPDATE-1
test "RC index update leaves COW allocation refusal and prior output at the original operation" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "refused_detach.my",
        \\def main(out: Stream) -> int:
        \\    values = [j for j in range(40000)]
        \\    retained: list[list[int]] = []
        \\    index = 0
        \\    out.print(41)
        \\    for at in range(20):
        \\        snapshot = values
        \\        next_value = values[index] + 1
        \\        values[index] = next_value
        \\        retained.append(snapshot)
        \\    return values[index]
    );
    defer compilation.deinit();
    const options: native.Options = .{ .max_memory = 1 << 20 };
    const ordinary = try native.runWithOptions(&compilation, options);
    const fast = try native.runUnaccounted(&compilation, options);
    try t.expectEqualDeep(ordinary, fast);
    try t.expect(fast.failed);
    try t.expectEqualStrings("41\n", fast.stdout);
    try t.expectEqualStrings("R_MEMORY_BUDGET", fast.trap.code);
    try t.expectEqual(@as(u64, 9), fast.trap.line);
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(allocator, "index_allocations.my",
        \\def update(index: int) -> int:
        \\    values = [7, 11]
        \\    values[index] = values[index] + 3
        \\    return values[index]
        \\def main() -> int:
        \\    return update(-1)
    );
    defer compilation.deinit();
    const text = try compilation.emitQbeWithOptions(allocator, unaccounted);
    defer allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, marker) != null);
}

// spec-case: RC-INDEX-UPDATE-1
test "RC index update emission releases partial allocations on every allocator refusal" {
    try t.checkAllAllocationFailures(t.allocator, allocationScenario, .{});
}
