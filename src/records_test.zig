const fixture_path = "records.my";
const std = @import("std");
const testing = std.testing;
const language = @import("compiler.zig");

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

// spec: CORE-5
test "record construction nesting named order field access and immutable copies" {
    try result("struct Pair { x: i64, y: i64 } fn main() -> i64 { let a: Pair = new Pair { y: 2, x: 3 }; let b = update(a) { x: 8 }; return a.x + b.x + b.y; }", 13);
    try result("struct Outer { inner: Inner, flag: bool } struct Inner { value: i64 } fn id(x: " ++
        "Outer) -> Outer { return x; } fn main() -> i64 { let x = id(new Outer { flag: true, " ++
        "inner: new Inner { value: 7 } }); if x.flag { return x.inner.value; } return 0; }", 7);
    try result("struct Empty {} fn main() -> i64 { let x = new Empty {}; discard update(x) {}; return 4; }", 4);
    try result("struct Count { n: i64, keep: i64 } fn main() -> i64 { let mut state = new Count { n: 0, keep: 7 }; while state.n < 10000 { state = update(state) { n: state.n + 1 }; } return state.n + state.keep; }", 10007);
    try result("struct Pair { x: i64, y: i64 } fn main() -> i64 { return -new Pair { x: 4, y: 2 }.x + 10; }", 6);
}

test "record declarations and construction reject missing duplicate wrong and recursive fields" {
    const cases = [_]struct { text: []const u8, code: []const u8 }{
        .{ .text = "struct A { x: i64, x: bool } fn main() -> i64 { return 0; }", .code = "E_DUPLICATE_FIELD" },
        .{ .text = "struct A {} struct A {} fn main() -> i64 { return 0; }", .code = "E_DUPLICATE_TYPE" },
        .{ .text = "struct A {} fn A() -> i64 { return 0; } fn main() -> i64 { return 0; }", .code = "E_DUPLICATE_NAME" },
        .{ .text = "struct A { x: Missing } fn main() -> i64 { return 0; }", .code = "E_UNKNOWN_TYPE" },
        .{ .text = "struct A { x: A } fn main() -> i64 { return 0; }", .code = "E_RECURSIVE_RECORD" },
        .{ .text = "struct A { x: B } struct B { x: A } fn main() -> i64 { return 0; }", .code = "E_RECURSIVE_RECORD" },
        .{ .text = "struct A { x: i64, y: i64 } fn main() -> i64 { discard new A { x: 1 }; return 0; }", .code = "E_INCOMPLETE_CONSTRUCTION" },
        .{ .text = "struct A { x: i64 } fn main() -> i64 { discard new A { x: 1, x: 2 }; return 0; }", .code = "E_DUPLICATE_FIELD" },
        .{ .text = "struct A { x: i64 } fn main() -> i64 { discard new A { x: true }; return 0; }", .code = "E_TYPE" },
        .{ .text = "struct A { x: i64 } fn main() -> i64 { discard new A { y: 1 }; return 0; }", .code = "E_UNKNOWN_FIELD" },
        .{ .text = "fn main() -> i64 { return 1.x; }", .code = "E_TYPE" },
        .{ .text = "struct A { x: i64 } fn main() -> i64 { return new A { x: 1 }.y; }", .code = "E_UNKNOWN_FIELD" },
        .{ .text = "struct A { x: i64 } struct B { x: i64 } fn f(a: A) -> i64 { return a.x; } fn main() -> i64 { return f(new B { x: 1 }); }", .code = "E_TYPE" },
        .{ .text = "struct A {} fn main() -> i64 { discard new A {} == new A {}; return 0; }", .code = "E_TYPE" },
        .{ .text = "fn main() -> i64 { discard update(1) {}; return 0; }", .code = "E_TYPE" },
        .{ .text = "struct A { x: i64 } fn main() -> i64 { let a = new A { x: 1 }; discard update(a) { x: 2, x: 3 }; return 0; }", .code = "E_DUPLICATE_FIELD" },
    };
    for (cases) |case| try reject(case.text, case.code);
}

test "adding fields breaks incomplete construction but preserving updates retain new values" {
    try result("struct State { n: i64, added: i64 } fn main() -> i64 { let x = new State { n: 0, added: 123 }; let y = update(x) { n: 1 }; return y.added; }", 123);
    try reject("struct State { n: i64, added: i64 } fn main() -> i64 { discard new State { n: 0 }; return 0; }", "E_INCOMPLETE_CONSTRUCTION");
}

test "source field evaluation order precedes storage order and update base is first" {
    const cases = [_][]const u8{
        "struct Pair { x: i64, y: i64 } fn main() -> i64 { discard new Pair { y: 1 / 0, x: 9223372036854775807 + 1 }; return 0; }",
        "struct Pair { x: i64, y: i64 } fn main() -> i64 { discard update(new Pair { x: 1 / 0, y: 2 }) { y: 9223372036854775807 + 1 }; return 0; }",
    };
    for (cases) |source| {
        var compilation = try language.Compilation.init(testing.allocator, "order.my", source);
        defer compilation.deinit();
        const outcome = try compilation.execute(testing.allocator);
        try testing.expectEqualStrings("R_DIVISION_BY_ZERO", outcome.trap.code);
        try testing.expectEqualStrings("/", compilation.src.text(outcome.trap.span));
    }
}

test "complete conversion accounts named source fields and requires complete destination" {
    try result("struct Source { x: i64, ignored: bool } struct Target { y: i64 } conversion fn " ++
        "convert(src: Source) -> Target { discard src.ignored; return new Target { y: src.x * " ++
        "2 }; } fn main() -> i64 { return convert(new Source { x: 4, ignored: true }).y; }", 8);
    try reject("struct Source { x: i64, added: bool } struct Target { y: i64 } conversion fn convert(src: Source) -> Target { return new Target { y: src.x }; } fn main() -> i64 { return 0; }", "E_INCOMPLETE_CONVERSION");
    try reject("struct Source { x: i64 } struct Target { y: i64, added: bool } conversion fn convert(src: Source) -> Target { return new Target { y: src.x }; } fn main() -> i64 { return 0; }", "E_INCOMPLETE_CONSTRUCTION");
    try result("struct Source { x: i64, added: bool } fn geometry(src: Source) -> i64 { return src.x; } fn main() -> i64 { return geometry(new Source { x: 5, added: true }); }", 5);
    try reject("struct Source { x: i64 } struct Target { y: i64 } fn helper(src: Source) -> i64 { " ++
        "return src.x; } conversion fn convert(src: Source) -> Target { return new Target { " ++
        "y: helper(src) }; } fn main() -> i64 { return 0; }", "E_INCOMPLETE_CONVERSION");
    try reject("struct Source { x: i64 } struct Target { y: i64 } conversion fn convert(src: Source) -> Target { let unused = src.x; return new Target { y: 0 }; } fn main() -> i64 { return 0; }", "E_CONVERSION_BODY");
    try reject("struct Source { x: i64 } conversion fn convert(src: Source) -> Source { return src; } fn main() -> i64 { return 0; }", "E_CONVERSION_BODY");
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, fixture_path, "struct Inner { x: i64 } struct Source { inner: Inner, ignored: bool } struct Target " ++
        "{ value: i64 } conversion fn convert(src: Source) -> Target { discard src.ignored; " ++
        "return new Target { value: src.inner.x }; } fn main() -> i64 { let source = new " ++
        "Source { ignored: true, inner: new Inner { x: 7 } }; let next = update(source) { " ++
        "inner: new Inner { x: 9 } }; return convert(next).value; }");
    defer compilation.deinit();
    try testing.expectEqual(@as(i64, 9), (try compilation.execute(allocator)).value);
    const dump = try compilation.dump(allocator);
    defer allocator.free(dump);
    var discovery = try language.duplicates.discover(allocator, compilation.program.?, .{});
    defer discovery.deinit();
}

test "record schemas conversion checking construction update projection and dump clean up on allocation failure" {
    // Successful backing-heap resizes vary with address/heap state. Force the
    // allocation fallback so fail_index identifies the same operation each run.
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
}

test "duplicate discovery retains nominal record and resolved field identities" {
    var compilation = try language.Compilation.init(testing.allocator, "identity.my", "struct A { x: i64, y: i64 } struct B { x: i64, y: i64 } fn a(v: A) -> i64 { return " ++
        "v.x; } fn b(v: B) -> i64 { return v.x; } fn c(v: A) -> i64 { return v.y; } fn " ++
        "d(renamed: A) -> i64 { return renamed.x; } fn main() -> i64 { return 0; }");
    defer compilation.deinit();
    try compilation.check();
    var analysis = try language.duplicates.discover(testing.allocator, compilation.program.?, .{ .min_nodes = 1 });
    defer analysis.deinit();
    try testing.expectEqual(@as(usize, 1), analysis.groups.len);
    const members = analysis.groups[0].members;
    try testing.expectEqual(@as(usize, 2), members.len);
    try testing.expectEqualStrings("a", compilation.program.?.functions[@backingInt(members[0])].name);
    try testing.expectEqualStrings("d", compilation.program.?.functions[@backingInt(members[1])].name);
}
