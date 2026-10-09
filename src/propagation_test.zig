//! Error propagation with `try`: unwrapping success, forwarding compatible error
//! payloads by case name, and the cleanup each propagation path performs.
const fixture_path = "propagation.my";
const std = @import("std");
const testing = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const declaration = @import("fixture_declarations_test.zig").scalar_result;
fn result(source: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(testing.allocator, fixture_path, source);
    defer compilation.deinit();
    try testing.expectEqual(expected, (try native.run(&compilation)).value);
}
fn reject(body: []const u8, code: []const u8) !void {
    const source = try std.mem.concat(testing.allocator, u8, &.{ declaration, body });
    defer testing.allocator.free(source);
    var compilation = try language.Compilation.init(testing.allocator, fixture_path, source);
    defer compilation.deinit();
    try testing.expectError(error.SourceError, compilation.check());
    try testing.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

const owned_source =
    \\record Item:
    \\    n: i64
    \\
    \\
    \\record Error:
    \\    detail: FixedArray[Item, 2]
    \\
    \\
    \\result Inner:
    \\    ok: i64,
    \\    err: Error
    \\
    \\
    \\result Outer:
    \\    err: Error,
    \\    ok: FixedArray[Item, 2]
    \\
    \\
    \\func attempt(flag: bool) -> Inner:
    \\    if flag:
    \\        return Err(Error(detail=FixedArray[Item, 2]([Item(n=7), Item(n=8)])))
    \\    return Ok(9)
    \\
    \\
    \\func build(flag: bool) -> Outer:
    \\    mut counter = 0
    \\    counter = 1
    \\    _ = counter
    \\    const first = Item(n=3)
    \\    const value = try attempt(flag)
    \\    return Ok(FixedArray[Item, 2]([first, Item(n=value)]))
    \\
    \\
    \\func main() -> i64:
    \\    match build(True):
    \\        case Outer.ok(items):
    \\            return items[1].n
    \\        case Outer.err(error):
    \\            return error.detail[0].n
;
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, fixture_path, owned_source);
    defer compilation.deinit();
    try testing.expectEqual(@as(i64, 7), (try native.run(&compilation)).value);
    try compilation.check();
    var discovery = try language.duplicates.discover(allocator, compilation.program.?, .{});
    defer discovery.deinit();
}

test "propagation releases partial aggregate operands and survives every allocation failure" {
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
    const success = try std.mem.replaceOwned(u8, testing.allocator, owned_source, "match build(True)", "match build(False)");
    defer testing.allocator.free(success);
    try result(success, 9);
}

// spec-case: TRY-CONVERT-1
test "try rejects an error type that is not a case payload of the enclosing error union" {
    try reject(
        \\enum Other:
        \\    Text(value: str)
        \\
        \\
        \\result Wrapped:
        \\    ok: i64,
        \\    err: Other
        \\
        \\
        \\func f(r: R) -> Wrapped:
        \\    const value = try r
        \\    return Ok(value)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_TYPE");
}

test "propagation cannot abandon pending locals parameters or unfinished expression results" {
    try reject(
        \\func f(r: R, other: R) -> R:
        \\    const value = try r
        \\    return R.ok(value)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_RESULT_UNHANDLED");
    try reject(
        \\func f(r: R) -> R:
        \\    mut ignored = R.err(3)
        \\    mut value = try r
        \\    _ = ignored
        \\    return R.ok(value)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_RESULT_UNHANDLED");
    try reject(
        \\func consume(r: R, n: i64) -> i64:
        \\    _ = r
        \\    return n
        \\
        \\
        \\func f(r: R) -> R:
        \\    const pending = R.err(7)
        \\    const value = try r
        \\    return R.ok(consume(pending, value))
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_RESULT_UNHANDLED");
    try reject(
        \\record Wrapper:
        \\    r: R
        \\
        \\
        \\func consume(w: Wrapper, n: i64) -> i64:
        \\    _ = w
        \\    return n
        \\
        \\
        \\func f(r: R) -> R:
        \\    mut first = R.err(7)
        \\    const pending = Wrapper(r=first)
        \\    const value = try r
        \\    return R.ok(consume(pending, value))
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_RESULT_UNHANDLED");
    try reject(
        \\record Pair:
        \\    first: R
        \\    second: i64
        \\
        \\
        \\result Wrapped:
        \\    ok: Pair,
        \\    err: i64
        \\
        \\
        \\func f(r: R) -> Wrapped:
        \\    const first = R.err(7)
        \\    const value = try r
        \\    return Ok(Pair(first=first, second=value))
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_RESULT_UNHANDLED");
    try result(
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\func f(r: R, other: R) -> R:
        \\    _ = other
        \\    const value = try r
        \\    return Ok(value)
        \\
        \\
        \\func main() -> i64:
        \\    match f(Err(7), Ok(1)):
        \\        case R.ok(n):
        \\            return n
        \\        case R.err(e):
        \\            return e
    , 7);
}

test "duplicate discovery retains propagation operations and target result types" {
    var compilation = try language.Compilation.init(testing.allocator, "duplicates.my",
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\func a(r: R) -> R:
        \\    const value = try r
        \\    return Ok(value + 1)
        \\
        \\
        \\func b(other: R) -> R:
        \\    const value = try other
        \\    return Ok(value + 1)
        \\
        \\
        \\func c(r: R) -> R:
        \\    match r:
        \\        case R.ok(n):
        \\            return Ok(n + 1)
        \\        case R.err(e):
        \\            return Err(e)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    );
    defer compilation.deinit();
    try compilation.check();
    var discovery = try language.duplicates.discover(testing.allocator, compilation.program.?, .{ .min_nodes = 1 });
    defer discovery.deinit();
    try testing.expectEqual(@as(usize, 1), discovery.groups.len);
    try testing.expectEqual(@as(usize, 2), discovery.groups[0].members.len);
}
