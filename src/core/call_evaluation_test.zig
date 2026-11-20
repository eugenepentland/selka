//! One source-order argument path supplies direct and callback calls without hidden copies.
const std = @import("std");
const language = @import("selka");
const ir = @import("ir.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const ownership = @import("single_owner.zig");
const support = @import("test_support.zig");
const modes = @import("native_language_modes.zig");

const sequencing =
    \\func mark(mut seen: int[], value: int) -> int:
    \\    append(mut seen, value)
    \\    return value
    \\func pair(named left: int, named right: int) -> int:
    \\    return left * 10 + right
    \\func direct(mut seen: int[]) -> int:
    \\    return pair(right=mark(mut seen, 2), left=mark(mut seen, 1))
    \\func indirect(callback: func(named left: int, named right: int) -> int, mut seen: int[]) -> int:
    \\    return callback(right=mark(mut seen, 2), left=mark(mut seen, 1))
    \\func main() -> int:
    \\    mut seen: int[] = []
    \\    const first = direct(mut seen)
    \\    const second = indirect(pair, mut seen)
    \\    return first + second + len(seen)
;

fn named(module: *const ir.Module, name: []const u8) !*const ir.Function {
    for (module.functions.items) |*function| {
        if (std.mem.eql(u8, function.name, name)) return function;
    }
    return error.TestUnexpectedResult;
}

fn producer(function: *const ir.Function, value: ir.Ref) ir.Ref {
    var current = function.resolve(value);
    while (function.inst(current).op == .record_get) current = function.resolve(function.inst(current).a);
    return current;
}

fn ordered(module: *const ir.Module, name: []const u8, indirect: bool) !void {
    const function = try named(module, name);
    var marks: [2]ir.Ref = undefined;
    var count: usize = 0;
    var called: ?ir.Inst = null;
    for (function.insts.items, 0..) |inst, index| {
        try std.testing.expect(inst.op != .list_copy and inst.op != .dict_copy and inst.op != .str_from_view);
        if (inst.op == .call_indirect) {
            try std.testing.expect(indirect);
            try std.testing.expectEqual(@as(usize, 2), count);
            called = inst;
        }
        if (inst.op != .call) continue;
        const target = module.functions.items[inst.a.index()].name;
        if (std.mem.eql(u8, target, "mark")) {
            try std.testing.expect(count < marks.len);
            const value = function.inst(function.resolve(function.operands(inst.data)[1]));
            try std.testing.expectEqual(ir.Op.iconst, value.op);
            try std.testing.expectEqual(@as(u64, 2 - count), value.data);
            marks[count] = @fromBackingInt(@intCast(index));
            count += 1;
        } else if (std.mem.eql(u8, target, "pair")) {
            try std.testing.expect(!indirect);
            try std.testing.expectEqual(@as(usize, 2), count);
            called = inst;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), count);
    const values = function.operands((called orelse return error.TestUnexpectedResult).data);
    try std.testing.expectEqual(@as(usize, 2), values.len);
    try std.testing.expectEqual(marks[1], producer(function, values[0]));
    try std.testing.expectEqual(marks[0], producer(function, values[1]));
}

test "O5 call evaluation binds source order into parameter ordered SSA values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expect(!@hasField(@FieldType(@FieldType(language.typed.Node, "data"), "call"), "evaluation"));
    try std.testing.expect(!@hasField(@FieldType(@FieldType(language.typed.Node, "data"), "invoke"), "evaluation"));
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, sequencing, &refusal);
    try ordered(&module, "direct", false);
    try ordered(&module, "indirect", true);
    const result = try passes.run(a, &module, .verify);
    try support.verified(a, &module, result.plans);
}

const overlap_prefix =
    \\func change(mut values: int[]) -> int:
    \\    append(mut values, 9)
    \\    return 7
    \\func inspect(named values: int[], named number: int) -> int:
    \\    return len(values) + number
    \\func main() -> int:
    \\    mut values = [1]
    \\
;
const move_prefix =
    \\func my_take(named own left: int[], named own right: int[]) -> int:
    \\    return len(left) + len(right)
    \\func main() -> int:
    \\    const values = [1]
    \\
;

fn refuses(backing: std.mem.Allocator, source: []const u8, expected: language.ownership_rules.Refusal) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings(expected.code, failure.code);
    try std.testing.expectEqual(expected.rule, failure.rule.?);
}

test "O5 call evaluation retains earlier argument loans and rejects repeated transfers" {
    try refuses(std.testing.allocator, overlap_prefix ++
        // migrate-embedded: skip intentional M5 argument evaluation overlap
        \\    return inspect(values=values, number=change(mut values))
    , .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = .M5 });
    try refuses(std.testing.allocator, overlap_prefix ++
        // migrate-embedded: skip intentional M5 callback argument evaluation overlap
        \\    const callback = inspect
        \\    return callback(values=values, number=change(mut values))
    , .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = .M5 });
    try refuses(std.testing.allocator, move_prefix ++
        // migrate-embedded: skip intentional B3 repeated owning argument
        \\    return my_take(right=own values, left=own values)
    , .{ .code = "E_SINGLE_OWNER_MOVED", .rule = .B3 });
    try refuses(std.testing.allocator, move_prefix ++
        // migrate-embedded: skip intentional B3 repeated owning callback argument
        \\    const callback = my_take
        \\    return callback(right=own values, left=own values)
    , .{ .code = "E_SINGLE_OWNER_MOVED", .rule = .B3 });
}

fn allocationFailure(backing: std.mem.Allocator, program: language.typed.Program) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: ownership.Failure = .{};
    try ownership.check(a, program, &failure);
    var refusal: build.Refusal = .{};
    var module = try build.buildModule(a, program, &refusal);
    const result = try passes.debug(a, &module);
    try support.verified(a, &module, result.plans);
}

test "O5 call evaluation checking and lowering release partial allocation state" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try support.checkedProgram(arena.allocator(), sequencing);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationFailure, .{program});
}

test "O5 call evaluation direct and callback owners execute in native modes" {
    try std.testing.expectEqual(@as(usize, 3), try modes.run(std.testing.allocator, .{
        .path = "tests/lang/call_evaluation.selka",
        .passed = 11,
        .label = "call evaluation",
    }));
}

const trap_prefix =
    \\func fresh(out: Stream) -> str[]:
    \\    print(out, "first")
    \\    return ["value-" + str(1)]
    \\func broken(out: Stream, count: int) -> str[]:
    \\    print(out, "second")
    \\    assert count != 0, "argument failed"
    \\    return ["unreached"]
    \\func consume(left: str[], right: str[]) -> int:
    \\    return len(left) + len(right)
    \\func apply(callback: func(str[], str[]) -> int, out: Stream) -> int:
    \\    return callback(fresh(out), broken(out, 0))
    \\func main(out: Stream) -> int:
    \\
;

/// Builds `suffix` after the trap prefix and checks effect and trap order in the debug (`release` false) or verified release build.
fn orderedTrap(backing: std.mem.Allocator, suffix: []const u8, release: bool) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try std.mem.concat(a, u8, &.{ trap_prefix, suffix });
    const program = try support.checkedProgram(a, source);
    var refusal: build.Refusal = .{};
    var module = try build.buildExecutable(a, .{ .program = program }, &refusal);
    const result = if (release) try passes.run(a, &module, .verify) else try passes.debug(a, &module);
    try support.verified(a, &module, result.plans);
    // A fatal assertion exits immediately. This checks effects and trap order;
    // normal-return cleanup is covered by the fallible guest cases above.
    const ran = try support.runOwned(a, &module, .{ .own = false, .release = release, .verify = release, .leakcheck = false, .analysis = support.analysis(&result) });
    try std.testing.expectEqual(@as(u8, 1), ran.status);
    try std.testing.expectEqualStrings("first\nsecond\n", ran.stdout);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "R_ASSERT") != null);
}

test "O5 call evaluation preserves earlier effects before a later direct or callback argument traps" {
    try orderedTrap(std.testing.allocator, "    return consume(fresh(out), broken(out, 0))\n", false);
    try orderedTrap(std.testing.allocator, "    return apply(consume, out)\n", false);
}

// Skipped by default: release builds run only with `-Dtest-release`.
test "O5 call evaluation preserves earlier effects before a later direct or callback argument traps (release)" {
    try support.requireRelease();
    try orderedTrap(std.testing.allocator, "    return consume(fresh(out), broken(out, 0))\n", true);
    try orderedTrap(std.testing.allocator, "    return apply(consume, out)\n", true);
}
