const fixture_path = "results.my";
const std = @import("std");
const testing = std.testing;
const language = @import("compiler.zig");
const LimitedLiveAllocator = @import("test_support.zig").LimitedLiveAllocator;
const declaration = @import("fixture_declarations_test.zig").scalar_result;
fn result(source: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(testing.allocator, fixture_path, source);
    defer compilation.deinit();
    try testing.expectEqual(expected, (try compilation.execute(testing.allocator)).value);
}
fn reject(body: []const u8, code: []const u8) !void {
    const source = try std.mem.concat(testing.allocator, u8, &.{ declaration, body });
    defer testing.allocator.free(source);
    var compilation = try language.Compilation.init(testing.allocator, fixture_path, source);
    defer compilation.deinit();
    try testing.expectError(error.SourceError, compilation.check());
    try testing.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

test "nominal typed results handle success and failure through exhaustive matches" {
    try result("enum E { missing } result R { err: E, ok: i64 } fn make(ok: bool) -> R { if ok { " ++
        "return new R.ok(7); } return new R.err(new E.missing); } fn handle(r: R) -> i64 { " ++
        "match r { R.ok(n) => { return n; }, R.err(e) => { match e { E.missing => { return 3; " ++
        "} } } } } fn main() -> i64 { return handle(make(true)) + handle(make(false)); }", 10);
    try result("result R { ok: i64, err: bool } fn forward(r: R) -> R { return r; } fn main() -> i64 { let result = forward(new R.err(true)); match result { R.ok(n) => { return n; }, R.err(e) => { if e { return 9; } return 0; } } }", 9);
    try reject("result Bad { ok: i64 } fn main() -> i64 { return 0; }", "E_RESULT_SCHEMA");
    try reject("result Bad { ok: i64, err } fn main() -> i64 { return 0; }", "E_RESULT_SCHEMA");
    try reject("result Other { ok: i64, err: i64 } fn f(r: R) -> Other { return r; } fn main() -> i64 { return 0; }", "E_TYPE");
}

const owned_source = "struct Item { n: i64 } result R { ok: Item, err: i64 } fn fallible(flag: bool) -> R " ++
    "{ let mut x = new Item { n: 3 }; borrow mut x as r { if flag { write_ref(r, new Item " ++
    "{ n: 9 }); return new R.ok(read_ref(r)); } return new R.err(7); } } fn main() -> i64 " ++
    "{ let r = fallible(false); match r { R.ok(item) => { return item.n; }, R.err(code) " ++
    "=> { acknowledge fallible(true); return code; } } }";
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, fixture_path, owned_source);
    defer compilation.deinit();
    try testing.expectEqual(@as(i64, 7), (try compilation.execute(allocator)).value);
    const dump = try compilation.dump(allocator);
    defer allocator.free(dump);
    var discovery = try language.duplicates.discover(allocator, compilation.program.?, .{});
    defer discovery.deinit();
}

test "result checking runtime ownership and rendering survive allocation failure" {
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
}
