const std = @import("std");
const testing = std.testing;
const language = @import("compiler.zig");
const LimitedLiveAllocator = @import("test_support.zig").LimitedLiveAllocator;

fn result(source: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(testing.allocator, "slices.my", source);
    defer compilation.deinit();
    try testing.expectEqual(expected, (try compilation.execute(testing.allocator)).value);
}
fn reject(source: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(testing.allocator, "slices.my", source);
    defer compilation.deinit();
    try testing.expectError(error.SourceError, compilation.check());
    try testing.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}
fn bounds(source: []const u8) !void {
    var compilation = try language.Compilation.init(testing.allocator, "bounds.my", source);
    defer compilation.deinit();
    const outcome = try compilation.execute(testing.allocator);
    try testing.expectEqualStrings("R_SLICE_BOUNDS", outcome.trap.code);
    try testing.expect(outcome.trap.span.end > outcome.trap.span.start);
}

test "slices read and replace bounded ranges while preserving owner snapshots" {
    try result("fn main() -> i64 { let mut a = new [4]i64 [1, 2, 3, 4]; let snapshot = a; borrow mut a[1..3] as s { write_slice(s, 1, 9); } return a[0] + a[1] + a[2] + a[3] + snapshot[2]; }", 19);
    try result("fn main() -> i64 { let a = new [3]u8 [1u8, 2u8, 3u8]; borrow a[1u8..3u64] as s { return cast<i64>(read_slice(s, 1i16)) + cast<i64>(len_slice(s)); } }", 5);
    try result("fn main() -> i64 { let a = new [0]i64 []; borrow a[0..0] as s { return cast<i64>(len_slice(s)); } }", 0);
    try result("fn main() -> i64 { let a = new [2]i64 [1, 2]; borrow a[2..2] as s { borrow s[0..0] as empty { return cast<i64>(len_slice(empty)); } } }", 0);
}

test "slice ranges and indices reject negatives reversed ranges and full unsigned overflow" {
    for ([_][]const u8{ "-1..1", "0..3", "2..1", "18446744073709551615u64..18446744073709551615u64", "0..18446744073709551615u64" }) |range| {
        const source = try std.fmt.allocPrint(testing.allocator, "fn main() -> i64 {{ let a = new [2]i64 [1, 2]; borrow a[{s}] as s {{ return cast<i64>(len_slice(s)); }} }}", .{range});
        defer testing.allocator.free(source);
        try bounds(source);
    }
    for ([_][]const u8{ "-1", "1", "18446744073709551615u64" }) |index| {
        const read = try std.fmt.allocPrint(testing.allocator, "fn main() -> i64 {{ let a = new [2]i64 [1, 2]; borrow a[1..2] as s {{ return read_slice(s, {s}); }} }}", .{index});
        defer testing.allocator.free(read);
        try bounds(read);
        const write = try std.fmt.allocPrint(testing.allocator, "fn main() -> i64 {{ let mut a = new [2]i64 [1, 2]; borrow mut a[1..2] as s {{ write_slice(s, {s}, 7); }} return a[1]; }}", .{index});
        defer testing.allocator.free(write);
        try bounds(write);
    }
    try bounds("fn main() -> i64 { let a = new [2]i64 [1, 2]; borrow a[2..2] as s { return read_slice(s, 0); } }");
    try bounds("fn main() -> i64 { let a = new [3]i64 [1, 2, 3]; borrow a[1..2] as s { borrow s[0..2] as child { return read_slice(child, 0); } } }");
}

test "slice reborrows compose offsets and restore exclusive access" {
    try result("fn main() -> i64 { let mut a = new [4]i64 [1, 2, 3, 4]; borrow mut a as whole { borrow mut whole[1..4] as s { borrow mut s[1..2] as child { write_slice(child, 0, 9); } borrow s as copy { discard read_slice(copy, 1); } write_slice(s, 0, 7); } return read_ref(whole)[1] + read_ref(whole)[2]; } }", 16);
    try reject("fn main() -> i64 { let mut a = new [2]i64 [1, 2]; borrow mut a[0..2] as s { borrow s[0..1] as child { return cast<i64>(len_slice(s)); } } }", "E_BORROW_SUSPENDED");
    try reject("fn main() -> i64 { let mut a = new [2]i64 [1, 2]; borrow mut a[0..1] as left { borrow mut a[1..2] as right { return read_slice(right, 0); } } }", "E_BORROW_CONFLICT");
    try reject("fn main() -> i64 { let a = new [2]i64 [1, 2]; borrow a[0..2] as s { borrow mut s[0..1] as child { return read_slice(child, 0); } } }", "E_REFERENCE_READ_ONLY");
    try result("fn main() -> i64 { let a = new [2]i64 [1, 2]; borrow a[0..2] as s { borrow s[0..1] as first { borrow s[1..2] as second { return read_slice(s, 0) + read_slice(first, 0) + read_slice(second, 0) + a[1]; } } } }", 6);
}

test "slice parameters accept different lengths and support recursively narrowed views" {
    const sum = "fn sum(s: &[]i64) -> i64 { if len_slice(s) == 0u64 { return 0; } let first = read_slice(s, 0); borrow s[1..len_slice(s)] as rest { return first + sum(rest); } }";
    const source = try std.fmt.allocPrint(testing.allocator, "{s} fn main() -> i64 {{ let a = new [2]i64 [1, 2]; let b = new [3]i64 [3, 4, 5]; borrow a[0..2] as x {{ borrow b[0..3] as y {{ return sum(x) + sum(y); }} }} }}", .{sum});
    defer testing.allocator.free(source);
    try result(source, 15);
    try result("fn clear(s: &mut []i64) -> i64 { if len_slice(s) == 0u64 { return 0; } write_slice(s, 0, 0); borrow mut s[1..len_slice(s)] as rest { return clear(rest); } } fn main() -> i64 { let mut a = new [3]i64 [1, 2, 3]; borrow mut a[0..3] as s { discard clear(s); } return a[0] + a[1] + a[2]; }", 0);
    try result("fn pair(a: &[]i64, b: &[]i64) -> i64 { return read_slice(a, 0) + read_slice(b, 0); } fn main() -> i64 { let a = new [1]i64 [7]; borrow a[0..1] as s { return pair(s, s); } }", 14);
    try reject("fn f(s: &[]u8) -> i64 { return cast<i64>(len_slice(s)); } fn main() -> i64 { let a = new [1]i64 [7]; borrow a[0..1] as s { return f(s); } }", "E_TYPE");
    try reject("fn f(s: &mut []i64) -> i64 { return cast<i64>(len_slice(s)); } fn main() -> i64 { let a = new [1]i64 [7]; borrow a[0..1] as s { return f(s); } }", "E_REFERENCE_READ_ONLY");
}

test "slice kinds cannot bypass nominal types owner conflicts or lexical lifetimes" {
    try reject("fn main() -> i64 { let x = 1; borrow x[0..1] as s { return read_slice(s, 0); } }", "E_SLICE_TYPE");
    try reject("enum E { a } fn main() -> i64 { let x = new [E]i64 { a: 1 }; borrow x[0..1] as s { return read_slice(s, 0); } }", "E_SLICE_TYPE");
    try reject("fn main() -> i64 { let a = new [1]i64 [1]; borrow a[false..1] as s { return read_slice(s, 0); } }", "E_TYPE");
    try reject("fn main() -> i64 { let a = new [1]i64 [1]; borrow a[0..1] as s { return read_slice(s, false); } }", "E_TYPE");
    try reject("fn main() -> i64 { let a = new [1]i64 [1]; borrow a[0..1] as s { return read_ref(s); } }", "E_REFERENCE_KIND");
    try reject("fn main() -> i64 { let a = new [1]i64 [1]; borrow a as r { return read_slice(r, 0); } }", "E_REFERENCE_KIND");
    try reject("fn f(r: &i64) -> i64 { return read_ref(r); } fn main() -> i64 { let a = new [1]i64 [1]; borrow a[0..1] as s { return f(s); } }", "E_REFERENCE_KIND");
    try reject("fn main() -> i64 { let a = new [1]i64 [1]; borrow a[0..1] as s {} return cast<i64>(len_slice(s)); }", "E_REFERENCE_SCOPE");
    try reject("fn main() -> i64 { let a = new [1]i64 [1]; borrow a[0..1] as s { return s; } }", "E_REFERENCE_VALUE");
    try reject("fn main() -> i64 { let mut a = new [1]i64 [1]; borrow mut a[0..1] as s { return a[0]; } }", "E_BORROW_CONFLICT");
    try reject("fn main() -> i64 { let mut a = new [1]i64 [1]; borrow a[0..1] as s { a = new [1]i64 [2]; } return a[0]; }", "E_BORROW_CONFLICT");
    try reject("fn main() -> i64 { let mut a = new [1]i64 [1]; borrow mut a[0..1] as s { write_slice(s, 0, true); } return a[0]; }", "E_TYPE");
    try reject("domain D: i64 {} fn expose(s: &[]D) -> i64 { return unwrap(read_slice(s, 0)); } fn main() -> i64 { return 0; }", "E_PRIVATE_DOMAIN");
}

test "slice bounds and write operands evaluate once in source order before access" {
    try result("fn next(r: &mut i64) -> i64 { let old = read_ref(r); write_ref(r, old + 1); return old; } fn main() -> i64 { let mut i = 0; let mut a = new [2]i64 [7, 9]; borrow mut i as n { borrow mut a[next(n)..next(n)] as s { write_ref(n, 0); write_slice(s, next(n), next(n)); } } return a[0] + a[1] + i; }", 12);
    var trapped = try language.Compilation.init(testing.allocator, "order.my", "fn main() -> i64 { let mut a = new [1]i64 [1]; borrow mut a[0..1] as s { write_slice(s, 99, 1 / 0); } return 0; }");
    defer trapped.deinit();
    try testing.expectEqualStrings("R_DIVISION_BY_ZERO", (try trapped.execute(testing.allocator)).trap.code);
}

const nested_source = "struct R { n: i64 } fn change(s: &mut []R) -> R { let old = read_slice(s, 0); write_slice(s, 0, new R { n: 9 }); borrow s[0..1] as child { discard read_slice(child, 0); return old; } } fn main() -> i64 { let mut a = new [2]R [new R { n: 1 }, new R { n: 2 }]; let original = a; borrow mut a[1..2] as s { let previous = change(s); return previous.n + original[1].n + read_slice(s, 0).n; } }";
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "slices.my", nested_source);
    defer compilation.deinit();
    try testing.expectEqual(@as(i64, 13), (try compilation.execute(allocator)).value);
    const dump = try compilation.dump(allocator);
    defer allocator.free(dump);
    var discovery = try language.duplicates.discover(allocator, compilation.program.?, .{});
    defer discovery.deinit();
}

test "slice aggregate snapshots call cleanup and lowering survive allocation failures" {
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
    try result("fn f(s: &mut [2]i64) -> i64 { borrow mut s[1..2] as part { write_slice(part, 0, 8); } return read_ref(s)[1]; } fn main() -> i64 { let mut a = new [2]i64 [1, 2]; borrow mut a as r { return f(r); } }", 8);
    try result("fn f(s: &mut [][1]i64) -> i64 { let old = read_slice(s, 0); write_slice(s, 0, new [1]i64 [7]); return old[0] + read_slice(s, 0)[0]; } fn main() -> i64 { let mut a = new [1][1]i64 [new [1]i64 [2]]; borrow mut a[0..1] as s { return f(s); } }", 9);
}

test "slice writes reuse bounded storage and release at each instruction trap boundary" {
    var compilation = try language.Compilation.init(testing.allocator, "slices.my", nested_source);
    defer compilation.deinit();
    try compilation.emit();
    var limiter = LimitedLiveAllocator{ .parent = testing.allocator, .limit = 16384 };
    var complete = false;
    for (1..150) |budget| {
        const outcome = try compilation.executeWithOptions(limiter.allocator(), .{ .max_steps = budget });
        try testing.expectEqual(@as(usize, 0), limiter.live);
        if (outcome == .value) {
            complete = true;
            break;
        }
        try testing.expectEqualStrings("R_STEP_LIMIT", outcome.trap.code);
    }
    try testing.expect(complete);
    var loop = try language.Compilation.init(testing.allocator, "loop.my", "fn bump(s: &mut []i64) -> i64 { write_slice(s, 0, read_slice(s, 0) + 1); return 0; } fn main() -> i64 { let mut a = new [1]i64 [0]; while a[0] < 10000 { borrow mut a[0..1] as s { discard bump(s); } } return a[0]; }");
    defer loop.deinit();
    try loop.emit();
    try testing.expectEqual(@as(i64, 10000), (try loop.execute(limiter.allocator())).value);
    try testing.expectEqual(@as(usize, 0), limiter.live);
}

test "slice duplicate identity retains bounds modes element types and indexing" {
    const source = "fn a(s: &[]i64) -> i64 { borrow s[0..1] as part { return read_slice(part, 0); } } fn b(x: &[]i64) -> i64 { borrow x[0..1] as renamed { return read_slice(renamed, 0); } } fn c(s: &[]i64) -> i64 { borrow s[1..2] as part { return read_slice(part, 0); } } fn d(s: &mut []i64) -> i64 { borrow s[0..1] as part { return read_slice(part, 0); } } fn main() -> i64 { return 0; }";
    var compilation = try language.Compilation.init(testing.allocator, "duplicates.my", source);
    defer compilation.deinit();
    try compilation.check();
    var discovery = try language.duplicates.discover(testing.allocator, compilation.program.?, .{ .min_nodes = 1 });
    defer discovery.deinit();
    try testing.expectEqual(@as(usize, 1), discovery.groups.len);
    try testing.expectEqual(@as(usize, 2), discovery.groups[0].members.len);
}

test "VM validates slice metadata and traps suspended slice access without retaining storage" {
    const typed = @import("typed.zig");
    var compilation = try language.Compilation.init(testing.allocator, "invalid-slice.my", "fn main() -> i64 { let mut a = new [2]i64 [1, 2]; borrow mut a[0..2] as root { borrow root[0..1] as child { return cast<i64>(len_slice(child)); } } }");
    defer compilation.deinit();
    try compilation.emit();
    const original = compilation.code.?;
    const functions = try testing.allocator.dupe(language.bytecode.Function, original.functions);
    defer testing.allocator.free(functions);
    const instructions = try testing.allocator.dupe(language.bytecode.Instruction, functions[0].instructions);
    defer testing.allocator.free(instructions);
    functions[0].instructions = instructions;
    var program = original;
    program.functions = functions;
    for (instructions) |*instruction| if (instruction.op == .len_slice) {
        instruction.op.len_slice = @fromBackingInt(0);
    };
    var limiter = LimitedLiveAllocator{ .parent = testing.allocator, .limit = 16384 };
    const outcome = try language.vm.run(limiter.allocator(), program);
    try testing.expectEqualStrings("R_BORROW_SUSPENDED", outcome.trap.code);
    try testing.expectEqual(@as(usize, 0), limiter.live);
    @memcpy(instructions, original.functions[0].instructions);
    for (instructions) |*instruction| if (instruction.op == .len_slice) {
        const reference = instruction.op.len_slice;
        instruction.op = .{ .read_ref = reference };
    };
    try testing.expectError(error.InternalError, language.bytecode.validate(testing.allocator, program));
    @memcpy(instructions, original.functions[0].instructions);
    const references = try testing.allocator.dupe(typed.Reference, functions[0].references);
    defer testing.allocator.free(references);
    functions[0].references = references;
    references[0].ty = .bool;
    try testing.expectError(error.InternalError, language.bytecode.validate(testing.allocator, program));
    @memcpy(references, original.functions[0].references);
    references[1].slice = false;
    try testing.expectError(error.InternalError, language.bytecode.validate(testing.allocator, program));
}
