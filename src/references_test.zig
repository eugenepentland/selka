//! Reference typing and runtime lifetime tests. Corrupted bytecode fixtures verify checks independently of source validation.
const fixture_path = "references.my";
const std = @import("std");
const testing = std.testing;
const language = @import("compiler.zig");
const LimitedLiveAllocator = @import("test_support.zig").LimitedLiveAllocator;
fn result(source: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(testing.allocator, fixture_path, source);
    defer compilation.deinit();
    try testing.expectEqual(expected, (try compilation.execute(testing.allocator)).value);
}
fn reject(source: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(testing.allocator, fixture_path, source);
    defer compilation.deinit();
    try testing.expectError(error.SourceError, compilation.check());
    try testing.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

test "scoped shared and exclusive references read mutate and restore owner access" {
    try result("fn main() -> i64 { let mut x = 7; borrow mut x as r { write_ref(r, read_ref(r) + 2); } x += 1; return x; }", 10);
    try result("fn main() -> i64 { let x = 7; borrow x as a { borrow x as b { return read_ref(a) + read_ref(b) + x; } } }", 21);
    try result("fn main() -> i64 { let mut x = 7u8; borrow mut x as r { write_ref(r, 9u8); } return cast<i64>(x); }", 9);
    try result("fn main() -> i64 { let mut flag = false; borrow mut flag as r { write_ref(r, !read_ref(r)); } if flag { return 1; } return 0; }", 1);
}

// spec: OWN-2
test "scoped reborrows suspend exclusive parents and resume them after child scope" {
    try result("fn main() -> i64 { let mut x = 1; borrow mut x as root { borrow mut root as child { write_ref(child, 2); borrow child as view { discard read_ref(view); } } write_ref(root, read_ref(root) + 1); } return x; }", 3);
    try result("fn main() -> i64 { let x = 5; borrow x as root { borrow root as a { borrow root as b { return read_ref(root) + read_ref(a) + read_ref(b); } } } }", 15);
    try reject("fn main() -> i64 { let mut x = 1; borrow mut x as root { borrow root as child { return read_ref(root); } } }", "E_BORROW_SUSPENDED");
    try reject("fn main() -> i64 { let mut x = 1; borrow mut x as root { borrow root as child { write_ref(root, 2); } } return x; }", "E_BORROW_SUSPENDED");
    try reject("fn main() -> i64 { let x = 1; borrow x as root { borrow mut root as child { return read_ref(child); } } }", "E_REFERENCE_READ_ONLY");
}

// spec: OWN-1
test "borrow checking rejects conflicts mutation through shared aliases and wrong writes" {
    const cases = [_]struct { text: []const u8, code: []const u8 }{
        .{ .text = "fn main() -> i64 { let mut x = 1; borrow mut x as r { return x; } }", .code = "E_BORROW_CONFLICT" },
        .{ .text = "fn main() -> i64 { let mut x = 1; borrow x as r { x = 2; } return x; }", .code = "E_BORROW_CONFLICT" },
        .{ .text = "fn main() -> i64 { let mut x = 1; borrow x as r { x += 2; } return x; }", .code = "E_BORROW_CONFLICT" },
        .{ .text = "fn main() -> i64 { let mut x = 1; borrow x as a { borrow mut x as b { return read_ref(b); } } }", .code = "E_BORROW_CONFLICT" },
        .{ .text = "fn main() -> i64 { let mut x = 1; borrow mut x as a { borrow x as b { return read_ref(b); } } }", .code = "E_BORROW_CONFLICT" },
        .{ .text = "fn main() -> i64 { let x = 1; borrow mut x as r { return read_ref(r); } }", .code = "E_IMMUTABLE" },
        .{ .text = "fn main() -> i64 { let x = 1; borrow x as r { write_ref(r, 2); } return x; }", .code = "E_REFERENCE_READ_ONLY" },
        .{ .text = "fn main() -> i64 { let mut x = 1; borrow mut x as r { write_ref(r, true); } return x; }", .code = "E_TYPE" },
        .{ .text = "fn main() -> i64 { let mut x = 1; borrow mut x as r { write_ref(r, x + 1); } return x; }", .code = "E_BORROW_CONFLICT" },
    };
    for (cases) |case| try reject(case.text, case.code);
    var compilation = try language.Compilation.init(testing.allocator, "related.my", cases[0].text);
    defer compilation.deinit();
    try testing.expectError(error.SourceError, compilation.check());
    try testing.expectEqualStrings("r", compilation.src.text(compilation.diagnostics.items[0].related.?.span));
}

test "references cannot escape be copied or be shadowed and siblings may reuse names" {
    try reject("fn main() -> i64 { let x = 1; borrow x as r { discard read_ref(r); } return read_ref(r); }", "E_REFERENCE_SCOPE");
    try reject("fn main() -> i64 { let x = 1; borrow x as r { return r; } }", "E_REFERENCE_VALUE");
    try reject("fn main() -> i64 { let x = 1; borrow x as r { let copied = r; return copied; } }", "E_REFERENCE_VALUE");
    try reject("fn f(x: i64) -> i64 { return x; } fn main() -> i64 { let x = 1; borrow x as r { return f(r); } }", "E_REFERENCE_VALUE");
    try reject("fn main() -> i64 { let x = 1; borrow x as r { let r = 2; return r; } }", "E_SHADOWING");
    try reject("fn main() -> i64 { let x = 1; borrow x as x { return read_ref(x); } }", "E_SHADOWING");
    try result("fn main() -> i64 { let x = 1; borrow x as r { discard read_ref(r); } borrow x as r { return read_ref(r); } }", 1);
}

test "reference values preserve aggregate snapshots and nominal privacy" {
    try result("struct Box { n: i64 } fn main() -> i64 { let mut current = new Box { n: 1 }; let " ++
        "original = current; borrow mut current as edit { let snapshot = read_ref(edit); " ++
        "write_ref(edit, update(snapshot) { n: 9 }); return original.n + snapshot.n + " ++
        "read_ref(edit).n; } }", 11);
    try result("fn main() -> i64 { let mut a = new [2]i64 [3, 7]; borrow mut a as r { write_ref(r, replace(read_ref(r), 0, 9)); } return a[0] + a[1]; }", 16);
    try reject("domain D: i64 { fn from(n: i64) -> D { return wrap<D>(n); } } fn main() -> i64 { let d = D.from(1); borrow d as r { return unwrap(read_ref(r)); } }", "E_PRIVATE_DOMAIN");
    try reject("domain D: i64 { fn from(n: i64) -> D { return wrap<D>(n); } } fn main() -> i64 { let mut d = D.from(1); borrow mut d as r { write_ref(r, 2); } return 0; }", "E_TYPE");
}

test "borrow cleanup covers conditional early returns nested matches and function calls" {
    try result("fn f(n: i64) -> i64 { let mut x = n; borrow mut x as r { if read_ref(r) > 0 { borrow r as child { return read_ref(child); } } write_ref(r, 7); } return x; } fn main() -> i64 { return f(3) + f(0); }", 10);
    try result("enum E { a, b } fn f(e: E) -> i64 { let x = 7; borrow x as r { match e { E.a => { return read_ref(r); }, E.b => {} } } return 1; } fn main() -> i64 { return f(new E.a) + f(new E.b); }", 8);
    try result("fn inner(n: i64) -> i64 { let mut x = n; borrow mut x as r { write_ref(r, read_ref(r) + 1); return read_ref(r); } } fn main() -> i64 { let mut x = 7; borrow mut x as r { write_ref(r, inner(read_ref(r))); } return x; }", 8);
    try reject("fn main() -> i64 { let x = 1; borrow x as r { return read_ref(r); } return 0; }", "E_UNREACHABLE");
}

test "borrowed locals and match payloads are reinitialized on later loop iterations" {
    try result("fn main() -> i64 { let mut i = 0; let mut sum = 0; while i < 10 { let local = i; borrow local as r { sum += read_ref(r); } i += 1; } return sum; }", 45);
    try result("union U { value: i64 } fn main() -> i64 { let mut i = 0; let mut sum = 0; while i < 10 { match new U.value(i) { U.value(payload) => { borrow payload as r { sum += read_ref(r); } } } i += 1; } return sum; }", 45);
    var compilation = try language.Compilation.init(testing.allocator, "warnings.my", "fn main() -> i64 { let mut x = 1; borrow mut x as r { return read_ref(r); } }");
    defer compilation.deinit();
    try compilation.check();
    try testing.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
}

const owned_source = "struct Box { n: i64 } fn f(input: Box) -> Box { let mut x = input; borrow mut x as " ++
    "parent { write_ref(parent, update(read_ref(parent)) { n: 9 }); borrow parent as " ++
    "child { return read_ref(child); } } } fn main() -> i64 { let original = new Box { n: " ++
    "7 }; return original.n + f(original).n; }";
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, fixture_path, owned_source);
    defer compilation.deinit();
    try testing.expectEqual(@as(i64, 16), (try compilation.execute(allocator)).value);
    const dump = try compilation.dump(allocator);
    defer allocator.free(dump);
    var discovery = try language.duplicates.discover(allocator, compilation.program.?, .{});
    defer discovery.deinit();
}

test "reference compilation memory promotion cleanup dumps and discovery survive allocation failure" {
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
}

test "reference loops and traps release bounded VM memory and borrow registries" {
    const source = "fn main() -> i64 { let mut x = 0; while x < 10000 { borrow mut x as r { write_ref(r, read_ref(r) + 1); } } return x; }";
    var compilation = try language.Compilation.init(testing.allocator, "loop.my", source);
    defer compilation.deinit();
    try compilation.emit();
    var limiter = LimitedLiveAllocator{ .parent = testing.allocator, .limit = 8192 };
    defer limiter.deinit();
    try testing.expectEqual(@as(i64, 10000), (try compilation.execute(limiter.allocator())).value);
    try testing.expectEqual(@as(usize, 0), limiter.live);
    var nested = try language.Compilation.init(testing.allocator, "nested.my", owned_source);
    defer nested.deinit();
    try nested.emit();
    var completed = false;
    for (1..100) |budget| {
        const outcome = try nested.executeWithOptions(limiter.allocator(), .{ .max_steps = budget });
        try testing.expectEqual(@as(usize, 0), limiter.live);
        if (outcome == .value) {
            completed = true;
            break;
        }
        try testing.expectEqualStrings("R_STEP_LIMIT", outcome.trap.code);
    }
    try testing.expect(completed);
}

test "reference duplicate identity retains owner permissions reborrowing and scope" {
    const source = "fn a(n: i64) -> i64 { borrow n as r { return read_ref(r); } } fn b(x: i64) -> i64 { " ++
        "borrow x as renamed { return read_ref(renamed); } } fn c(n: i64) -> i64 { let mut x " ++
        "= n; borrow mut x as r { return read_ref(r); } } fn d(n: i64) -> i64 { borrow n as r " ++
        "{ borrow r as child { return read_ref(child); } } } fn main() -> i64 { return 0; }";
    var compilation = try language.Compilation.init(testing.allocator, "duplicates.my", source);
    defer compilation.deinit();
    try compilation.check();
    var discovery = try language.duplicates.discover(testing.allocator, compilation.program.?, .{ .min_nodes = 1 });
    defer discovery.deinit();
    try testing.expectEqual(@as(usize, 1), discovery.groups.len);
    const members = discovery.groups[0].members;
    try testing.expectEqual(@as(usize, 2), members.len);
    try testing.expectEqualStrings("a", compilation.program.?.functions[@backingInt(members[0])].name);
    try testing.expectEqualStrings("b", compilation.program.?.functions[@backingInt(members[1])].name);
}

test "VM rejects invalid borrow lifetime ordering and owner access with full cleanup" {
    const source = "fn main() -> i64 { let mut x = 7; borrow mut x as r { return read_ref(r); } }";
    var compilation = try language.Compilation.init(testing.allocator, "invalid-reference.my", source);
    defer compilation.deinit();
    try compilation.emit();
    const original = compilation.code.?;
    const functions = try testing.allocator.dupe(language.bytecode.Function, original.functions);
    defer testing.allocator.free(functions);
    const instructions = try testing.allocator.dupe(language.bytecode.Instruction, functions[0].scope.instructions);
    defer testing.allocator.free(instructions);
    functions[0].scope.instructions = instructions;
    var program = original;
    program.functions = functions;
    const Mutation = enum { missing_begin, missing_end, repeated_begin, owner_read };
    for (std.enums.values(Mutation)) |mutation| {
        @memcpy(instructions, original.functions[0].scope.instructions);
        for (instructions, 0..) |*instruction, index| {
            switch (instruction.op) {
                .begin_borrow => if (mutation == .missing_begin) {
                    instruction.op = .{ .jump = index + 1 };
                },
                .end_borrow => |reference| switch (mutation) {
                    .missing_end => instruction.op = .{ .jump = index + 1 },
                    .repeated_begin => instruction.op = .{ .begin_borrow = reference },
                    else => {},
                },
                .read_ref => if (mutation == .owner_read) {
                    instruction.op = .{ .load_local = @fromBackingInt(0) };
                },
                else => {},
            }
        }
        var limiter = LimitedLiveAllocator{ .parent = testing.allocator, .limit = 8192 };
        defer limiter.deinit();
        const outcome = try language.vm.run(limiter.allocator(), program);
        try testing.expectEqual(@as(usize, 0), limiter.live);
        try testing.expect(outcome == .trap);
        try testing.expectEqualStrings(if (mutation == .owner_read) "R_BORROW_CONFLICT" else "R_REFERENCE_LIFETIME", outcome.trap.code);
    }
}

test "reference parameters mutate caller storage with mixed value arguments and recursive forwarding" {
    try result("fn add(before: i64, r: &mut i64, after: i64) -> i64 { write_ref(r, read_ref(r) + " ++
        "before + after); return read_ref(r); } fn main() -> i64 { let mut x = 7; borrow mut " ++
        "x as r { discard add(2, r, 3); discard add(1, r, 1); } return x; }", 14);
    try result("fn recurse(r: &mut i64, n: i64) -> i64 { if n == 0 { return read_ref(r); } " ++
        "write_ref(r, read_ref(r) + 1); return recurse(r, n - 1); } fn main() -> i64 { let " ++
        "mut x = 0; borrow mut x as r { discard recurse(r, 100); } return x; }", 100);
    try result("fn inspect(r: &i64) -> i64 { borrow r as child { return read_ref(child); } } fn main() -> i64 { let mut x = 7; borrow mut x as r { let snapshot = inspect(r); write_ref(r, snapshot + 1); } return x; }", 8);
    try result("fn pair(a: &i64, b: &i64) -> i64 { return read_ref(a) + read_ref(b); } fn main() -> i64 { let x = 7; borrow x as r { return pair(r, r); } }", 14);
}

test "reference calls evaluate value arguments in order before acquiring callee borrows" {
    try result("fn bump(r: &mut i64) -> i64 { write_ref(r, read_ref(r) + 1); return read_ref(r); } " ++
        "fn combine(r: &mut i64, a: i64, b: i64) -> i64 { write_ref(r, a * 10 + b); return " ++
        "read_ref(r); } fn main() -> i64 { let mut x = 0; borrow mut x as r { discard " ++
        "combine(r, bump(r), bump(r)); } return x; }", 12);
    try result("fn mix(a: &mut i64, b: &mut i64) -> i64 { write_ref(a, read_ref(a) + read_ref(b)); " ++
        "write_ref(b, 2); return read_ref(a); } fn main() -> i64 { let mut x = 3; let mut y = " ++
        "7; borrow mut x as a { borrow mut y as b { discard mix(a, b); } } return x + y; }", 12);
}

test "reference parameters enforce type permission alias and lexical scope boundaries" {
    try reject("fn f(r: &mut i64) -> i64 { return read_ref(r); } fn main() -> i64 { let x = 1; borrow x as r { return f(r); } }", "E_REFERENCE_READ_ONLY");
    try reject("fn f(r: &i64) -> i64 { return read_ref(r); } fn main() -> i64 { return f(1); }", "E_REFERENCE_ARGUMENT");
    try reject("fn f(r: &i64) -> i64 { return read_ref(r); } fn main() -> i64 { let x = 1; return f(x); }", "E_REFERENCE_SCOPE");
    try reject("fn f(r: &i64) -> i64 { return read_ref(r); } fn main() -> i64 { let x = 1u8; borrow x as r { return f(r); } }", "E_TYPE");
    try reject("fn f(r: &i64) -> i64 { return r; } fn main() -> i64 { return 0; }", "E_REFERENCE_VALUE");
    try reject("fn f(r: &i64) -> i64 { write_ref(r, 2); return 0; } fn main() -> i64 { return 0; }", "E_REFERENCE_READ_ONLY");
    try reject("fn f(r: &i64) -> i64 { let r = 2; return r; } fn main() -> i64 { return 0; }", "E_SHADOWING");
    try reject("fn f(r: &i64, r: i64) -> i64 { return 0; } fn main() -> i64 { return 0; }", "E_DUPLICATE_PARAMETER");
    try reject("fn f(r: i64, r: &i64) -> i64 { return 0; } fn main() -> i64 { return 0; }", "E_DUPLICATE_PARAMETER");
    try reject("fn f(r: &mut i64) -> i64 { borrow r as child { return f(r); } } fn main() -> i64 { return 0; }", "E_BORROW_SUSPENDED");
    for ([_][]const u8{ "fn f(a: &mut i64, b: &mut i64) -> i64 { return read_ref(a) + read_ref(b); }", "fn f(a: &i64, b: &i64) -> i64 { return read_ref(a) + read_ref(b); }" }) |prefix| {
        const source = try std.fmt.allocPrint(testing.allocator, "{s} fn main() -> i64 {{ let mut x = 1; borrow mut x as r {{ return f(r, r); }} }}", .{prefix});
        defer testing.allocator.free(source);
        try reject(source, "E_BORROW_CONFLICT");
    }
}

test "reference parameters preserve aggregate snapshots and domain construction privacy" {
    try result("struct R { n: i64 } fn change(r: &mut R) -> R { let old = read_ref(r); write_ref(r, " ++
        "new R { n: 9 }); return old; } fn main() -> i64 { let mut r = new R { n: 3 }; let " ++
        "original = r; borrow mut r as edit { let previous = change(edit); return original.n " ++
        "+ previous.n + read_ref(edit).n; } }", 15);
    try result("fn change(r: &mut [2]u8) -> i64 { write_ref(r, replace(read_ref(r), 1, 9u8)); return " ++
        "cast<i64>(read_ref(r)[1]); } fn main() -> i64 { let mut a = new [2]u8 [1u8, 2u8]; " ++
        "borrow mut a as r { discard change(r); } return cast<i64>(a[1]); }", 9);
    try reject("domain D: i64 { fn from(n: i64) -> D { return wrap<D>(n); } } fn expose(r: &D) -> i64 { return unwrap(read_ref(r)); } fn main() -> i64 { return 0; }", "E_PRIVATE_DOMAIN");
    try reject("struct R { n: i64 } conversion fn copy(r: &R) -> R { return new R { n: read_ref(r).n }; } fn main() -> i64 { return 0; }", "E_CONVERSION_SIGNATURE");
}

const parameter_source = "struct R { n: i64 } fn update_both(a: &mut R, b: &mut R, n: i64) -> R { write_ref(a, " ++
    "new R { n: n }); borrow b as child { if read_ref(child).n > 0 { return read_ref(a); }" ++
    " } return read_ref(b); } fn main() -> i64 { let mut a = new R { n: 1 }; let mut b = " ++
    "new R { n: 2 }; borrow mut a as x { borrow mut b as y { discard update_both(x, y, 9);" ++
    " } } return a.n + b.n; }";
fn parameterAllocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "parameters.my", parameter_source);
    defer compilation.deinit();
    try testing.expectEqual(@as(i64, 11), (try compilation.execute(allocator)).value);
    const dump = try compilation.dump(allocator);
    defer allocator.free(dump);
    var discovery = try language.duplicates.discover(allocator, compilation.program.?, .{});
    defer discovery.deinit();
}

test "reference call loan creation and aggregate transfer clean up on every allocation failure" {
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), parameterAllocationScenario, .{});
}

test "reference parameters release bounded memory across loops early returns and trap boundaries" {
    var compilation = try language.Compilation.init(testing.allocator, "parameters.my", parameter_source);
    defer compilation.deinit();
    try compilation.emit();
    var limiter = LimitedLiveAllocator{ .parent = testing.allocator, .limit = 16384 };
    defer limiter.deinit();
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
    var loop = try language.Compilation.init(testing.allocator, "loop.my", "fn bump(r: &mut i64) -> i64 { write_ref(r, read_ref(r) + 1); return read_ref(r); } " ++
        "fn main() -> i64 { let mut x = 0; borrow mut x as r { while read_ref(r) < 10000 { " ++
        "discard bump(r); } } return x; }");
    defer loop.deinit();
    try loop.emit();
    try testing.expectEqual(@as(i64, 10000), (try loop.execute(limiter.allocator())).value);
    try testing.expectEqual(@as(usize, 0), limiter.live);
    var recurse = try language.Compilation.init(testing.allocator, "recursive.my", "fn f(r: &mut i64) -> i64 { return f(r); } fn main() -> i64 { let mut x = 0; borrow mut x as r { return f(r); } }");
    defer recurse.deinit();
    try recurse.emit();
    const trapped = try recurse.executeWithOptions(limiter.allocator(), .{ .max_frames = 8 });
    try testing.expectEqualStrings("R_FRAME_LIMIT", trapped.trap.code);
    try testing.expectEqual(@as(usize, 0), limiter.live);
}

test "reference parameter duplicate identity preserves permissions and argument order" {
    const source = "fn first(a: &i64, b: &i64) -> i64 { return read_ref(a) - read_ref(b); } fn second(x: " ++
        "&i64, y: &i64) -> i64 { return read_ref(x) - read_ref(y); } fn mutable(a: &mut i64, " ++
        "b: &i64) -> i64 { return read_ref(a) - read_ref(b); } fn direct(a: &i64, b: &i64) -> " ++
        "i64 { return first(a, b); } fn swapped(a: &i64, b: &i64) -> i64 { return first(b, a);" ++
        " } fn main() -> i64 { return 0; }";
    var compilation = try language.Compilation.init(testing.allocator, "duplicates.my", source);
    defer compilation.deinit();
    try compilation.check();
    var discovery = try language.duplicates.discover(testing.allocator, compilation.program.?, .{ .min_nodes = 1 });
    defer discovery.deinit();
    try testing.expectEqual(@as(usize, 1), discovery.groups.len);
    try testing.expectEqual(@as(usize, 2), discovery.groups[0].members.len);
}

test "unused reference parameters retain binding warnings and forwarding counts as use" {
    var unused = try language.Compilation.init(testing.allocator, "unused.my", "fn unused(r: &i64) -> i64 { return 1; } fn main() -> i64 { return 0; }");
    defer unused.deinit();
    try unused.check();
    try testing.expectEqual(@as(usize, 1), unused.diagnostics.items.len);
    try testing.expectEqualStrings("W_UNUSED_BINDING", unused.diagnostics.items[0].code);
    var used = try language.Compilation.init(testing.allocator, "used.my", "fn inner(r: &i64) -> i64 { return read_ref(r); } fn outer(r: &i64) -> i64 { return inner(r); } fn main() -> i64 { return 0; }");
    defer used.deinit();
    try used.check();
    try testing.expectEqual(@as(usize, 0), used.diagnostics.items.len);
}

test "invalid reference calls trap alias conflicts and reject malformed parameter metadata" {
    const typed = @import("typed.zig");
    var compilation = try language.Compilation.init(testing.allocator, "invalid-call.my", parameter_source);
    defer compilation.deinit();
    try compilation.emit();
    const original = compilation.code.?;
    const functions = try testing.allocator.dupe(language.bytecode.Function, original.functions);
    defer testing.allocator.free(functions);
    const main_index = @backingInt(original.main);
    const instructions = try testing.allocator.dupe(language.bytecode.Instruction, functions[main_index].scope.instructions);
    defer testing.allocator.free(instructions);
    functions[main_index].scope.instructions = instructions;
    var program = original;
    program.functions = functions;
    var aliases: [2]typed.ReferenceId = undefined;
    var call_index: usize = 0;
    for (instructions, 0..) |*instruction, index| {
        if (instruction.op == .call_refs) {
            aliases = .{ instruction.op.call_refs.references[0], instruction.op.call_refs.references[0] };
            instruction.op.call_refs.references = &aliases;
            call_index = index;
            break;
        }
    }
    var limiter = LimitedLiveAllocator{ .parent = testing.allocator, .limit = 16384 };
    defer limiter.deinit();
    const outcome = try language.vm.run(limiter.allocator(), program);
    try testing.expectEqualStrings("R_BORROW_SUSPENDED", outcome.trap.code);
    try testing.expectEqual(@as(usize, 0), limiter.live);
    instructions[call_index].op.call_refs.references = &.{};
    try testing.expectError(error.InternalError, language.bytecode.validate(testing.allocator, program));
    @memcpy(instructions, original.functions[main_index].scope.instructions);
    functions[0].scope.references = &.{};
    try testing.expectError(error.InternalError, language.bytecode.validate(testing.allocator, program));
    functions[0] = original.functions[0];
    const parameters = try testing.allocator.dupe(language.bytecode.Instruction, functions[0].scope.instructions);
    defer testing.allocator.free(parameters);
    functions[0].scope.instructions = parameters;
    const instruction = try @import("instruction_test.zig").find(parameters, .read_ref);
    instruction.op = .{ .load_local = @fromBackingInt(0) };
    try testing.expectError(error.InternalError, language.bytecode.validate(testing.allocator, program));
}
