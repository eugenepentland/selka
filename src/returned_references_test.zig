const std = @import("std");
const testing = std.testing;
const language = @import("compiler.zig");
const LimitedLiveAllocator = @import("test_support.zig").LimitedLiveAllocator;
fn result(source: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(testing.allocator, "returned.my", source);
    defer compilation.deinit();
    try testing.expectEqual(expected, (try compilation.execute(testing.allocator)).value);
}
fn reject(source: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(testing.allocator, "returned.my", source);
    defer compilation.deinit();
    try testing.expectError(error.SourceError, compilation.check());
    try testing.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

test "returned scalar references mutate caller storage and restore parents after the result scope" {
    try result("fn identity(r: &mut i64) -> &mut i64 from r { return r; } fn main() -> i64 { let mut x = 1; borrow mut x as r { borrow mut identity(r) as returned { write_ref(returned, 7); } write_ref(r, read_ref(r) + 1); } return x; }", 8);
    try result("fn identity(r: &i64) -> &i64 from r { return r; } fn main() -> i64 { let x = 7; borrow x as r { borrow identity(r) as returned { return read_ref(r) + read_ref(returned); } } }", 14);
    try result("fn identity(r: &mut i64) -> &mut i64 from r { return r; } fn main() -> i64 { let mut x = 7; borrow mut x as r { borrow identity(r) as shared { return read_ref(shared); } } }", 7);
}

test "returned slices retain narrowed bounds across forwarding and recursion" {
    try result("fn tail(s: &mut []i64, n: i64) -> &mut []i64 from s { if n == 0 { return s; } borrow mut s[1..len_slice(s)] as rest { borrow mut tail(rest, n - 1) as returned { return returned; } } } fn main() -> i64 { let mut a = new [3]i64 [1, 2, 3]; borrow mut a[0..3] as all { borrow mut tail(all, 2) as last { write_slice(last, 0, 9); } } return a[0] + a[1] + a[2]; }", 12);
    try result("fn empty(s: &[]i64) -> &[]i64 from s { borrow s[len_slice(s)..len_slice(s)] as end { return end; } } fn main() -> i64 { let a = new [2]i64 [1, 2]; borrow a[0..2] as all { borrow empty(all) as end { return cast<i64>(len_slice(end)); } } }", 0);
    try result("fn tail(a: &mut [3]i64) -> &mut []i64 from a { borrow mut a[1..3] as s { return s; } } fn main() -> i64 { let mut a = new [3]i64 [1, 2, 3]; borrow mut a as r { borrow mut tail(r) as s { write_slice(s, 0, 7); } return read_ref(r)[1]; } }", 7);
}

test "return contracts select explicit parameters across mixed arguments and conditional returns" {
    try result("fn select(flag: bool, a: &i64, count: i64, b: &i64) -> &i64 from b { discard read_ref(a); discard count; if flag { borrow b as child { return child; } } return b; } fn main() -> i64 { let x = 3; let y = 7; borrow x as a { borrow y as b { borrow select(true, a, 0, b) as yes { borrow select(false, a, 0, b) as no { return read_ref(yes) + read_ref(no); } } } } }", 14);
    try result("enum E { first, second } fn select(s: &[]i64, e: E) -> &[]i64 from s { match e { E.first => { borrow s[0..1] as r { return r; } }, E.second => { borrow s[1..2] as r { return r; } } } } fn main() -> i64 { let a = new [2]i64 [3, 7]; borrow a[0..2] as s { borrow select(s, new E.second) as r { return read_slice(r, 0); } } }", 7);
}

test "return lifetime checking rejects local storage copies unrelated inputs and inactive names" {
    try reject("fn bad(input: &i64) -> &i64 from input { let local = 7; borrow local as r { return r; } } fn main() -> i64 { return 0; }", "E_RETURN_LIFETIME");
    try reject("fn bad(input: &i64) -> &i64 from input { let copied = read_ref(input); borrow copied as r { return r; } } fn main() -> i64 { return 0; }", "E_RETURN_LIFETIME");
    try reject("fn bad(a: &i64, b: &i64) -> &i64 from a { return b; } fn main() -> i64 { return 0; }", "E_RETURN_LIFETIME");
    try reject("fn bad(a: &[]i64) -> &[]i64 from a { let local = new [1]i64 [7]; borrow local[0..1] as s { return s; } } fn main() -> i64 { return 0; }", "E_RETURN_LIFETIME");
    try reject("fn bad(a: &i64) -> &i64 from a { borrow a as r {} return r; } fn main() -> i64 { return 0; }", "E_REFERENCE_SCOPE");
    try reject("fn bad(a: i64) -> &i64 from a { return a; } fn main() -> i64 { return 0; }", "E_RETURN_LIFETIME");
    try reject("fn bad(a: &i64) -> &i64 from missing { return a; } fn main() -> i64 { return 0; }", "E_RETURN_LIFETIME");
    try reject("fn bad(a: &i64) -> &i64 using a { return a; } fn main() -> i64 { return 0; }", "E_RETURN_LIFETIME");
    try reject("fn bad(a: &i64) -> &i64 from a { return read_ref(a); } fn main() -> i64 { return 0; }", "E_REFERENCE_RESULT");
    try reject("fn bad(a: &i64) -> &i64 from a { if false { return a; } } fn main() -> i64 { return 0; }", "E_MISSING_RETURN");
}

test "returned references preserve permissions kinds and exclusive suspension" {
    try reject("fn bad(a: &i64) -> &mut i64 from a { return a; } fn main() -> i64 { return 0; }", "E_REFERENCE_READ_ONLY");
    try reject("fn bad(a: &mut i64) -> &mut i64 from a { borrow a as shared { return shared; } } fn main() -> i64 { return 0; }", "E_REFERENCE_READ_ONLY");
    try reject("fn bad(a: &[]i64) -> &i64 from a { return a; } fn main() -> i64 { return 0; }", "E_REFERENCE_KIND");
    try reject("fn bad(a: &i64) -> &bool from a { return a; } fn main() -> i64 { return 0; }", "E_TYPE");
    try reject("fn same(a: &mut i64) -> &mut i64 from a { return a; } fn main() -> i64 { let mut x = 1; borrow mut x as a { borrow mut same(a) as r { return read_ref(a); } } }", "E_BORROW_SUSPENDED");
    try reject("fn same(a: &i64) -> &i64 from a { return a; } fn main() -> i64 { let x = 1; borrow x as a { borrow mut same(a) as r { return read_ref(r); } } }", "E_REFERENCE_READ_ONLY");
    try reject("fn same(a: &i64) -> &i64 from a { return a; } fn main() -> i64 { let x = 1; borrow x as a { return same(a); } }", "E_REFERENCE_RESULT");
    try reject("fn value() -> i64 { return 1; } fn main() -> i64 { borrow value() as r { return read_ref(r); } }", "E_REFERENCE_RESULT");
}

const owned_source = "struct R { n: i64 } fn view(s: &mut []R) -> &mut []R from s { let temporary = new R { n: 3 }; discard temporary.n; borrow mut s[1..2] as r { return r; } } fn main() -> i64 { let mut a = new [2]R [new R { n: 1 }, new R { n: 2 }]; let original = a; borrow mut a[0..2] as all { borrow mut view(all) as r { write_slice(r, 0, new R { n: 9 }); } } return original[1].n + a[1].n; }";
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "returned.my", owned_source);
    defer compilation.deinit();
    try testing.expectEqual(@as(i64, 11), (try compilation.execute(allocator)).value);
    const dump = try compilation.dump(allocator);
    defer allocator.free(dump);
    var discovery = try language.duplicates.discover(allocator, compilation.program.?, .{});
    defer discovery.deinit();
}

test "returned reference capture cleanup and reacquisition survive allocation failures" {
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
    try reject("domain D: i64 {} fn expose(a: &D) -> &i64 from a { return a; } fn main() -> i64 { return 0; }", "E_TYPE");
    try result("struct R { n: i64 } fn identity(r: &mut R) -> &mut R from r { return r; } fn main() -> i64 { let mut r = new R { n: 1 }; let snapshot = r; borrow mut r as root { borrow mut identity(root) as view { write_ref(view, new R { n: 9 }); } } return snapshot.n + r.n; }", 10);
}

test "returned loans stay bounded over repeated calls and clean every capture and cleanup trap boundary" {
    var compilation = try language.Compilation.init(testing.allocator, "returned.my", owned_source);
    defer compilation.deinit();
    try compilation.emit();
    var limiter = LimitedLiveAllocator{ .parent = testing.allocator, .limit = 16384 };
    var completed = false;
    for (1..200) |budget| {
        const outcome = try compilation.executeWithOptions(limiter.allocator(), .{ .max_steps = budget });
        try testing.expectEqual(@as(usize, 0), limiter.live);
        if (outcome == .value) {
            completed = true;
            break;
        }
        try testing.expectEqualStrings("R_STEP_LIMIT", outcome.trap.code);
    }
    try testing.expect(completed);
    var loop = try language.Compilation.init(testing.allocator, "loop.my", "fn identity(r: &mut i64) -> &mut i64 from r { return r; } fn main() -> i64 { let mut x = 0; borrow mut x as r { while read_ref(r) < 10000 { borrow mut identity(r) as returned { write_ref(returned, read_ref(returned) + 1); } } } return x; }");
    defer loop.deinit();
    try loop.emit();
    try testing.expectEqual(@as(i64, 10000), (try loop.execute(limiter.allocator())).value);
    try testing.expectEqual(@as(usize, 0), limiter.live);
}

test "VM rejects missing reference capture and wrong declared provenance" {
    const typed = @import("typed.zig");
    var compilation = try language.Compilation.init(testing.allocator, "invalid-return.my", "fn identity(a: &i64, b: &i64) -> &i64 from a { discard read_ref(b); return a; } fn main() -> i64 { let x = 1; let y = 2; borrow x as a { borrow y as b { borrow identity(a, b) as r { return read_ref(r); } } } }");
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
    var capture_index: usize = 0;
    for (instructions, 0..) |*instruction, index| if (instruction.op == .capture_ref) {
        capture_index = index;
        instruction.op = .{ .jump = index + 1 };
        break;
    };
    var limiter = LimitedLiveAllocator{ .parent = testing.allocator, .limit = 16384 };
    const outcome = try language.vm.run(limiter.allocator(), program);
    try testing.expectEqualStrings("R_REFERENCE_LIFETIME", outcome.trap.code);
    try testing.expectEqual(@as(usize, 0), limiter.live);
    instructions[capture_index].op = .{ .capture_ref = @as(typed.ReferenceId, @fromBackingInt(1)) };
    try testing.expectError(error.InternalError, language.bytecode.validate(testing.allocator, program));
    instructions[capture_index] = original.functions[0].instructions[capture_index];
    functions[0].return_reference.?.parameter = @fromBackingInt(99);
    try testing.expectError(error.InternalError, language.bytecode.validate(testing.allocator, program));
}

test "duplicate identity retains returned reference contracts while normalizing parameter spelling" {
    const source = "fn a(x: &i64, y: &i64) -> &i64 from x { discard read_ref(y); return x; } fn b(first: &i64, second: &i64) -> &i64 from first { discard read_ref(second); return first; } fn c(x: &i64, y: &i64) -> &i64 from y { discard read_ref(x); return y; } fn main() -> i64 { return 0; }";
    var compilation = try language.Compilation.init(testing.allocator, "duplicates.my", source);
    defer compilation.deinit();
    try compilation.check();
    var discovery = try language.duplicates.discover(testing.allocator, compilation.program.?, .{ .min_nodes = 1 });
    defer discovery.deinit();
    try testing.expectEqual(@as(usize, 1), discovery.groups.len);
    try testing.expectEqual(@as(usize, 2), discovery.groups[0].members.len);
}
