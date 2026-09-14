//! Value records: construction by field name, copy semantics, updated copies and
//! the diagnostics that reject unknown, missing and mistyped fields.
const fixture_path = "records.my";
const std = @import("std");
const testing = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

fn result(source: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(testing.allocator, fixture_path, source);
    defer compilation.deinit();
    try testing.expectEqual(expected, (try native.run(&compilation)).value);
}
fn reject(source: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(testing.allocator, fixture_path, source);
    defer compilation.deinit();
    try testing.expectError(error.SourceError, compilation.check());
    try testing.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, fixture_path,
        \\class Inner:
        \\    x: i64
        \\
        \\
        \\class Source:
        \\    inner: Inner
        \\    ignored: bool
        \\
        \\
        \\class Target:
        \\    value: i64
        \\
        \\
        \\conversion def convert(src: Source) -> Target:
        \\    _ = src.ignored
        \\    return Target(value=src.inner.x)
        \\
        \\
        \\def main() -> i64:
        \\    source = Source(ignored=True, inner=Inner(x=7))
        \\    next = source
        \\    next.inner = Inner(x=9)
        \\    return convert(next).value
    );
    defer compilation.deinit();
    try compilation.check();
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
    var compilation = try language.Compilation.init(testing.allocator, "identity.my",
        \\class A:
        \\    x: i64
        \\    y: i64
        \\
        \\
        \\class B:
        \\    x: i64
        \\    y: i64
        \\
        \\
        \\def a(v: A) -> i64:
        \\    return v.x
        \\
        \\
        \\def b(v: B) -> i64:
        \\    return v.x
        \\
        \\
        \\def c(v: A) -> i64:
        \\    return v.y
        \\
        \\
        \\def d(renamed: A) -> i64:
        \\    return renamed.x
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    );
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
    try result(
        \\class Source:
        \\    x: i64
        \\    ignored: bool
        \\
        \\
        \\class Target:
        \\    y: i64
        \\
        \\
        \\conversion def convert(src: Source) -> Target:
        \\    _ = src.ignored
        \\    return Target(y=src.x * 2)
        \\
        \\
        \\def main() -> i64:
        \\    return convert(Source(x=4, ignored=True)).y
    , 8);
    try reject(
        \\class Source:
        \\    x: i64
        \\    added: bool
        \\
        \\
        \\class Target:
        \\    y: i64
        \\
        \\
        \\conversion def convert(src: Source) -> Target:
        \\    return Target(y=src.x)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_INCOMPLETE_CONVERSION");
    try reject(
        \\class Source:
        \\    x: i64
        \\
        \\
        \\class Target:
        \\    y: i64
        \\    added: bool
        \\
        \\
        \\conversion def convert(src: Source) -> Target:
        \\    return Target(y=src.x)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_INCOMPLETE_CONSTRUCTION");
    try result(
        \\class Source:
        \\    x: i64
        \\    added: bool
        \\
        \\
        \\def geometry(src: Source) -> i64:
        \\    return src.x
        \\
        \\
        \\def main() -> i64:
        \\    return geometry(Source(x=5, added=True))
    , 5);
    try reject(
        \\class Source:
        \\    x: i64
        \\
        \\
        \\class Target:
        \\    y: i64
        \\
        \\
        \\def helper(src: Source) -> i64:
        \\    return src.x
        \\
        \\
        \\conversion def convert(src: Source) -> Target:
        \\    return Target(y=helper(src))
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_INCOMPLETE_CONVERSION");
    try reject(
        \\class Source:
        \\    x: i64
        \\
        \\
        \\class Target:
        \\    y: i64
        \\
        \\
        \\conversion def convert(src: Source) -> Target:
        \\    unused = src.x
        \\    return Target(y=0)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_CONVERSION_BODY");
    try reject(
        \\class Source:
        \\    x: i64
        \\
        \\
        \\conversion def convert(src: Source) -> Source:
        \\    return src
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_CONVERSION_BODY");
}

test "record schemas conversion checking construction update projection and dump clean up on allocation failure" {
    // Successful backing-heap resizes vary with address/heap state. Force the
    // allocation fallback so fail_index identifies the same operation each run.
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
}

// spec: CORE-5
test "record construction nesting named order field access and immutable copies" {
    try result(
        \\class Pair:
        \\    x: i64
        \\    y: i64
        \\
        \\
        \\def main() -> i64:
        \\    a: Pair = Pair(y=2, x=3)
        \\    b = a
        \\    b.x = 8
        \\    return a.x + b.x + b.y
    , 13);
    try result(
        \\class Outer:
        \\    inner: Inner
        \\    flag: bool
        \\
        \\
        \\class Inner:
        \\    value: i64
        \\
        \\
        \\def id(x: Outer) -> Outer:
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    x = id(Outer(flag=True, inner=Inner(value=7)))
        \\    if x.flag:
        \\        return x.inner.value
        \\    return 0
    , 7);
    try result(
        \\class Count:
        \\    n: i64
        \\    keep: i64
        \\
        \\
        \\def main() -> i64:
        \\    state = Count(n=0, keep=7)
        \\    while state.n < 10000:
        \\        state.n = state.n + 1
        \\    return state.n + state.keep
    , 10007);
    try result(
        \\class Pair:
        \\    x: i64
        \\    y: i64
        \\
        \\
        \\def main() -> i64:
        \\    return -Pair(x=4, y=2).x + 10
    , 6);
}
