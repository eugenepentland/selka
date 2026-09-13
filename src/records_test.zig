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
