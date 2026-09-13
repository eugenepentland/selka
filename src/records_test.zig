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

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, fixture_path, "struct Inner { x: i64 } struct Source { inner: Inner, ignored: bool } struct Target " ++
        "{ value: i64 } conversion fn convert(src: Source) -> Target { _ = src.ignored; " ++
        "return new Target { value: src.inner.x }; } fn main() -> i64 { let source = new " ++
        "Source { ignored: true, inner: new Inner { x: 7 } }; let mut next = source; " ++
        "next.inner = new Inner { x: 9 }; return convert(next).value; }");
    defer compilation.deinit();
    try testing.expectEqual(@as(i64, 9), (try compilation.execute(allocator)).value);
    const dump = try compilation.dump(allocator);
    defer allocator.free(dump);
    var discovery = try language.duplicates.discover(allocator, compilation.program.?, .{});
    defer discovery.deinit();
}

test "record schemas conversion checking construction assignment projection and dump clean up on allocation failure" {
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

test "complete conversion accounts named source fields and requires complete destination" {
    try result("struct Source { x: i64, ignored: bool } struct Target { y: i64 } conversion fn " ++
        "convert(src: Source) -> Target { _ = src.ignored; return new Target { y: src.x * " ++
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

test "record schemas conversion checking construction update projection and dump clean up on allocation failure" {
    // Successful backing-heap resizes vary with address/heap state. Force the
    // allocation fallback so fail_index identifies the same operation each run.
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
}

// spec: CORE-5
test "record construction nesting named order field access and immutable copies" {
    try result("struct Pair { x: i64, y: i64 } fn main() -> i64 { let a: Pair = new Pair { y: 2, x: 3 }; let mut b = a; b.x = 8; return a.x + b.x + b.y; }", 13);
    try result("struct Outer { inner: Inner, flag: bool } struct Inner { value: i64 } fn id(x: " ++
        "Outer) -> Outer { return x; } fn main() -> i64 { let x = id(new Outer { flag: true, " ++
        "inner: new Inner { value: 7 } }); if x.flag { return x.inner.value; } return 0; }", 7);
    try result("struct Count { n: i64, keep: i64 } fn main() -> i64 { let mut state = new Count { n: 0, keep: 7 }; while state.n < 10000 { state.n = state.n + 1; } return state.n + state.keep; }", 10007);
    try result("struct Pair { x: i64, y: i64 } fn main() -> i64 { return -new Pair { x: 4, y: 2 }.x + 10; }", 6);
}
