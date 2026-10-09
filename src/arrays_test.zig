//! Fixed-array construction, index bounds, copy behavior, and malformed bytecode metadata tests.
const fixture_path = "arrays.selka";
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

// spec: CORE-6
test "fixed arrays have structural types preserve copies and support every integer index width" {
    try result(
        \\func first(a: FixedArray[i64, 2]) -> i64:
        \\    return a[0]
        \\
        \\
        \\func main() -> i64:
        \\    mut a: FixedArray[i64, 0x2] = FixedArray[int, 2]([3, 4])
        \\    mut b = replace(a, 0, 8)
        \\    return first(a) + b[0] + b[1]
    , 15);
    for ([_][]const u8{ "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64" }) |width| {
        const source = try std.fmt.allocPrint(testing.allocator, "func main() -> i64:\n    const a = FixedArray[u8, 2]([7u8, 9u8])\n    return i64(a[1{s}])\n", .{width});
        defer testing.allocator.free(source);
        try result(source, 9);
    }
    try result(
        \\func empty(a: FixedArray[bool, 0]) -> FixedArray[bool, 0]:
        \\    return a
        \\
        \\
        \\func main() -> i64:
        \\    return i64(len(empty(FixedArray[bool, 0]([]))))
    , 0);
    try result(
        \\func main() -> i64:
        \\    return -[4][0] + 10
    , 6);
}

const allocation_source =
    \\record Box:
    \\    n: i64
    \\
    \\
    \\func id(a: FixedArray[Box, 2]) -> FixedArray[Box, 2]:
    \\    return a
    \\
    \\
    \\func main() -> i64:
    \\    mut a = id(FixedArray[Box, 2]([Box(n=7), Box(n=9)]))
    \\    mut b = replace(a, 1u8, Box(n=11))
    \\    return a[1].n + b[1].n + i64(len(b))
;
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, fixture_path, allocation_source);
    defer compilation.deinit();
    try compilation.check();
    var discovery = try language.duplicates.discover(allocator, compilation.program.?, .{});
    defer discovery.deinit();
}

test "array compiler dump and discovery clean up at every allocation failure" {
    try result(allocation_source, 22);
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
}

test "array duplicate identity preserves length element type index replacement and order" {
    const source =
        \\func a(x: FixedArray[i64, 2]) -> i64:
        \\    return x[0]
        \\
        \\
        \\func b(y: FixedArray[i64, 0x2]) -> i64:
        \\    return y[0]
        \\
        \\
        \\func c(x: FixedArray[i64, 3]) -> i64:
        \\    return x[0]
        \\
        \\
        \\func d(x: FixedArray[i64, 2]) -> i64:
        \\    return x[1]
        \\
        \\
        \\func e(x: FixedArray[u8, 2]) -> i64:
        \\    return i64(x[0])
        \\
        \\
        \\func f(x: FixedArray[i64, 2]) -> i64:
        \\    return replace(x, 0, 1)[0]
        \\
        \\
        \\func g() -> FixedArray[i64, 2]:
        \\    return FixedArray[int, 2]([1, 2])
        \\
        \\
        \\func h() -> FixedArray[i64, 2]:
        \\    return FixedArray[int, 2]([2, 1])
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ;
    var compilation = try language.Compilation.init(testing.allocator, "duplicates.selka", source);
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

test "deep array type syntax observes the shared parser budget" {
    var source: std.Io.Writer.Allocating = .init(testing.allocator);
    defer source.deinit();
    try source.writer.writeAll("record Deep:\n    value: ");
    for (0..300) |_| try source.writer.writeAll("[1]");
    try source.writer.writeAll("i64\n\n\nfunc main() -> i64:\n    return 0\n");
    try reject(source.written(), "E_NESTING_LIMIT");
}
