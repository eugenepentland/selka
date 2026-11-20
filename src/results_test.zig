//! Checked results: construction, matching, propagation across nominal result types
//! and the rejections that keep an error from being abandoned silently.
const fixture_path = "results.selka";
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

test "nominal typed results handle success and failure through exhaustive matches" {
    try result(
        \\enum E:
        \\    missing
        \\
        \\
        \\result R:
        \\    err: E,
        \\    ok: i64
        \\
        \\
        \\func make(ok: bool) -> R:
        \\    if ok:
        \\        return Ok(7)
        \\    return Err(E.missing)
        \\
        \\
        \\func handle(r: R) -> i64:
        \\    match r:
        \\        case ok(n):
        \\            return n
        \\        case err(e):
        \\            match e:
        \\                case missing:
        \\                    return 3
        \\
        \\
        \\func main() -> i64:
        \\    return handle(make(True)) + handle(make(False))
    , 10);
    try result(
        \\result R:
        \\    ok: i64,
        \\    err: bool
        \\
        \\
        \\func forward(r: R) -> R:
        \\    return r
        \\
        \\
        \\func main() -> i64:
        \\    mut result = forward(Err(True))
        \\    match result:
        \\        case ok(n):
        \\            return n
        \\        case err(e):
        \\            if e:
        \\                return 9
        \\            return 0
    , 9);
    try reject(
        \\result Bad:
        \\    ok: i64
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_RESULT_SCHEMA");
    try reject(
        \\result Bad:
        \\    ok: i64,
        \\    err
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_RESULT_SCHEMA");
    try reject(
        \\result Other:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\func f(r: R) -> Other:
        \\    return r
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_TYPE");
}

const owned_source =
    \\record Item:
    \\    n: i64
    \\
    \\
    \\result R:
    \\    ok: Item,
    \\    err: i64
    \\
    \\
    \\func fallible(flag: bool) -> R:
    \\    mut x = Item(n=3)
    \\    if flag:
    \\        x = Item(n=9)
    \\        return Ok(x)
    \\    return Err(7)
    \\
    \\
    \\func main() -> i64:
    \\    mut r = fallible(False)
    \\    match r:
    \\        case ok(item):
    \\            return item.n
    \\        case err(code):
    \\            _ = fallible(True)
    \\            return code
;
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, fixture_path, owned_source);
    defer compilation.deinit();
    try compilation.check();
    var discovery = try language.duplicates.discover(allocator, compilation.program.?, .{});
    defer discovery.deinit();
}

test "result checking runtime ownership and rendering survive allocation failure" {
    try result(owned_source, 7);
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
}

/// Reject a complete Python-surface program, which needs no brace declarations.
fn pythonReject(source: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(testing.allocator, "results.selka", source);
    defer compilation.deinit();
    try testing.expectError(error.SourceError, compilation.check());
    try testing.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}
// spec: CORE-10
test "binding transfer and explicit release cannot silently drop results" {
    try result(
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\func main() -> i64:
        \\    mut first: R = Err(7)
        \\    mut second = first
        \\    _ = second
        \\    return 1
    , 1);
    try reject(
        \\func main() -> i64:
        \\    mut ignored = R.err(7)
        \\    return 0
    , "E_RESULT_UNHANDLED");
    try reject(
        \\func main() -> i64:
        \\    mut ignored = R.ok(7)
        \\    return 0
    , "E_RESULT_UNHANDLED");
    try result(
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\func main() -> i64:
        \\    _ = R.err(7)
        \\    return 0
    , 0);
    try reject(
        \\func main() -> i64:
        \\    mut r = R.ok(7)
        \\    mut copied = r
        \\    _ = r
        \\    _ = copied
        \\    return 0
    , "E_RESULT_CONSUMED");
    try reject(
        \\func main() -> i64:
        \\    R.err(7)
        \\    return 0
    , "E_EXPLICIT_DISCARD_REQUIRED");
    try reject(
        \\func swallow(r: R) -> i64:
        \\    return 0
        \\
        \\
        \\func main() -> i64:
        \\    return swallow(R.err(7))
    , "E_RESULT_UNHANDLED");
    try result(
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\func swallow(r: R) -> i64:
        \\    _ = r
        \\    return 3
        \\
        \\
        \\func main() -> i64:
        \\    return swallow(Err(7))
    , 3);
    // The Python surface releases and rejects the same way.
    try result("func attempt() -> int fails int:\n    fail 7\n\nfunc main() -> int:\n    _ = attempt()\n    return 0\n", 0);
    try result("func swallow(r: Result[int, int]) -> int:\n    _ = r\n    return 3\n\nfunc main() -> int:\n    return swallow(Err(7))\n", 3);
    try pythonReject("func attempt() -> int fails int:\n    fail 7\n\nfunc main() -> int:\n    attempt()\n    return 0\n", "E_EXPLICIT_DISCARD_REQUIRED");
    try pythonReject("func attempt() -> int fails int:\n    fail 7\n\nfunc main() -> int:\n    mut pending = attempt()\n    return 0\n", "E_RESULT_UNHANDLED");
}

/// Check L1 directly in the front end, before Core's managed-value rules run.
/// A Result carrying a resource is also move-only; that must not replace its
/// Result obligation with a retired move diagnostic or an ordinary B3 check.
fn rejectResourceResult(body: []const u8, code: []const u8) !void {
    const source = try std.mem.concat(testing.allocator, u8, &.{
        \\resource File: filesystem
        \\
        \\result Open:
        \\    ok: File,
        \\    err: i64
        \\
        \\
        ,
        body,
        "\n\n",
        \\func main() -> i64:
        \\    return 0
    });
    defer testing.allocator.free(source);
    var compilation = try language.Compilation.initTrusted(testing.allocator, fixture_path, source);
    defer compilation.deinit();
    try testing.expectError(error.SourceError, compilation.check());
    const refusal = compilation.diagnostics.items[0];
    try testing.expectEqualStrings(code, refusal.code);
    try testing.expectEqual(language.diagnostic.Rule.L1, refusal.provenance.rule.?);
}

test "frontend Result obligations survive retirement of move-only checks" {
    try rejectResourceResult(
        \\func duplicate(own pending: Open) -> i64:
        \\    _ = pending
        \\    _ = pending
        \\    return 0
    , "E_RESULT_CONSUMED");
    try rejectResourceResult(
        \\func abandon(own pending: Open) -> i64:
        \\    return 0
    , "E_RESULT_UNHANDLED");
    try rejectResourceResult(
        \\func replace(own pending: Open) -> i64:
        \\    pending = Err(2)
        \\    _ = pending
        \\    return 0
    , "E_RESULT_OVERWRITE");
    try rejectResourceResult(
        \\func conditional(flag: bool, own pending: Open) -> i64:
        \\    if flag:
        \\        _ = pending
        \\    return 0
    , "E_RESULT_PATH");
    try rejectResourceResult(
        \\func repeated(own pending: Open) -> i64:
        \\    while False:
        \\        _ = pending
        \\    return 0
    , "E_RESULT_LOOP");
}

test "result obligations must agree across all continuing branch and match paths" {
    try result(
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\func handle(flag: bool, r: R) -> i64:
        \\    if flag:
        \\        _ = r
        \\    else:
        \\        _ = r
        \\    return 7
        \\
        \\
        \\func main() -> i64:
        \\    return handle(False, Err(3))
    , 7);
    try result(
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\func handle(flag: bool, r: R) -> i64:
        \\    if flag:
        \\        _ = r
        \\        return 1
        \\    _ = r
        \\    return 2
        \\
        \\
        \\func main() -> i64:
        \\    return handle(False, Err(3))
    , 2);
    try reject(
        \\func f(flag: bool, r: R) -> i64:
        \\    if flag:
        \\        _ = r
        \\    return 0
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_RESULT_PATH");
    try reject(
        \\func f(flag: bool, r: R) -> i64:
        \\    if flag:
        \\        return 0
        \\    _ = r
        \\    return 1
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_RESULT_UNHANDLED");
    try reject(
        \\enum E:
        \\    a
        \\    b
        \\
        \\
        \\func f(e: E, r: R) -> i64:
        \\    match e:
        \\        case a:
        \\            _ = r
        \\        case b:
        \\            pass
        \\    return 0
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_RESULT_PATH");
    try result(
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\enum E:
        \\    a
        \\    b
        \\
        \\
        \\func f(e: E, r: R) -> i64:
        \\    match e:
        \\        case a:
        \\            _ = r
        \\            return 1
        \\        case b:
        \\            pass
        \\    _ = r
        \\    return 2
        \\
        \\
        \\func main() -> i64:
        \\    return f(E.b, Ok(3))
    , 2);
}

test "loops and short circuit evaluation cannot conditionally lose result obligations" {
    try reject(
        \\func main() -> i64:
        \\    mut r = R.err(1)
        \\    while False:
        \\        _ = r
        \\    return 0
    , "E_RESULT_LOOP");
    try reject(
        \\func consume(r: R) -> bool:
        \\    _ = r
        \\    return False
        \\
        \\
        \\func main() -> i64:
        \\    mut r = R.err(1)
        \\    while consume(r):
        \\        pass
        \\    return 0
    , "E_RESULT_LOOP");
    try reject(
        \\func consume(r: R) -> bool:
        \\    _ = r
        \\    return True
        \\
        \\
        \\func main() -> i64:
        \\    mut r = R.err(1)
        \\    _ = False and consume(r)
        \\    return 0
    , "E_RESULT_PATH");
    try reject(
        \\func consume(r: R) -> bool:
        \\    _ = r
        \\    return True
        \\
        \\
        \\func main() -> i64:
        \\    mut r = R.err(1)
        \\    _ = True or consume(r)
        \\    return 0
    , "E_RESULT_PATH");
    try result(
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\func consume(r: R) -> bool:
        \\    _ = r
        \\    return True
        \\
        \\
        \\func main() -> i64:
        \\    mut r: R = Err(1)
        \\    _ = consume(r) and False
        \\    _ = False and consume(Err(7))
        \\    return 1
    , 1);
    try result(
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\func main() -> i64:
        \\    mut n = 0
        \\    mut r: R = Ok(0)
        \\    while n < 3:
        \\        _ = r
        \\        r = Err(n)
        \\        n += 1
        \\    _ = r
        \\    return n
    , 3);
}

test "mutable result slots require handling before replacement and permit explicit transfer" {
    try reject(
        \\func main() -> i64:
        \\    mut r = R.err(1)
        \\    r = R.ok(2)
        \\    _ = r
        \\    return 0
    , "E_RESULT_OVERWRITE");
    try result(
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\func main() -> i64:
        \\    mut r: R = Err(1)
        \\    mut old = r
        \\    r = Ok(2)
        \\    _ = old
        \\    match r:
        \\        case ok(n):
        \\            return n
        \\        case err(_):
        \\            return 0
    , 2);
    try result(
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\func main() -> i64:
        \\    mut r: R = Err(1)
        \\    r = r
        \\    _ = r
        \\    return 7
    , 7);
}

test "recoverable error returns and explicit acknowledgement preserve evaluation and borrow cleanup" {
    try allocationScenario(testing.allocator);
    var compilation = try language.Compilation.init(testing.allocator, "trap.selka",
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\func main() -> i64:
        \\    _ = R.ok(divtrunc(1, 0))
        \\    return 0
    );
    defer compilation.deinit();
    try testing.expectEqualStrings("R_DIVISION_BY_ZERO", (try native.run(&compilation)).trap.code);
}

test "duplicate identity retains explicit acknowledgement and fallible result types" {
    var compilation = try language.Compilation.init(testing.allocator, "duplicates.selka",
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\func a(r: R) -> i64:
        \\    _ = r
        \\    return 1
        \\
        \\
        \\func b(other: R) -> i64:
        \\    _ = other
        \\    return 1
        \\
        \\
        \\func c(r: R) -> i64:
        \\    match r:
        \\        case ok(_):
        \\            pass
        \\        case err(_):
        \\            pass
        \\    return 1
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

fn nestedPropagationProbe(a: std.mem.Allocator) ![]const u8 {
    var compilation = try language.Compilation.init(a, "nested-propagation.selka",
        \\result R:
        \\    ok: int,
        \\    err: int
        \\func use(a: R, b: int) -> R:
        \\    _ = b
        \\    return a
        \\func part() -> R:
        \\    return Ok(2)
        \\func bad() -> R:
        \\    return use(R.ok(1), part())
        \\func main() -> int:
        \\    return 0
    );
    try compilation.parse();
    const nodes = &compilation.syntax.?.nodes;
    const index = for (nodes.items, 0..) |node, index| {
        if (node.data == .call and std.mem.eql(u8, compilation.src.text(node.span), "part()")) break index;
    } else return error.TestUnexpectedResult;
    const operand: @import("ast.zig").NodeId = @fromBackingInt(nodes.items.len);
    try nodes.append(compilation.arena.allocator(), nodes.items[index]);
    nodes.items[index].data = .{ .propagate = operand };
    try testing.expectError(error.SourceError, compilation.check());
    return compilation.diagnostics.items[0].code;
}

test "ownership coverage constructed nested propagation reaches pending temporary refusal" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqualStrings("E_RESULT_PROPAGATION", try nestedPropagationProbe(arena.allocator()));
}

/// Check `source`, which must be refused with `E_RESULT_UNHANDLED`: the refusal sits on the binding that holds the result
/// (`binding` is the text from its name on) and its note is the exit that leaves with the result pending (`exit` is that
/// statement's text).
fn expectUnhandledAt(source: []const u8, binding: []const u8, exit: []const u8, name: []const u8) !void {
    var compilation = try language.Compilation.init(testing.allocator, fixture_path, source);
    defer compilation.deinit();
    try testing.expectError(error.SourceError, compilation.check());
    const item = compilation.diagnostics.items[0];
    try testing.expectEqualStrings("E_RESULT_UNHANDLED", item.code);
    try testing.expectEqual(std.mem.indexOf(u8, source, binding).?, item.span.start);
    try testing.expectEqualStrings(name, compilation.src.text(item.span));
    try testing.expectEqual(std.mem.indexOf(u8, source, exit).?, item.related.?.span.start);
    const write = try std.fmt.allocPrint(testing.allocator, "_ = {s}", .{name});
    defer testing.allocator.free(write);
    try testing.expect(std.mem.indexOf(u8, item.message, write) != null);
    try testing.expect(std.mem.indexOf(u8, item.related.?.message, "this exit leaves while") != null);
}

test "a pending result held across an early return is reported at its binding with the exit as the note" {
    try expectUnhandledAt(
        "func step(n: int) -> int fails str:\n    if n > 1:\n        fail \"too big\"\n    return n\n\n\n" ++
            "func main() -> int:\n    const first = step(1)\n    const after = step(2)\n    const value = after else Err(_):\n" ++
            "        return 1\n    match first:\n        case Ok(n):\n            return n + value\n        case Err(_):\n            return 2\n",
        "first = step(1)",
        "return 1",
        "first",
    );
    try expectUnhandledAt(
        "func divide(a: int, b: int) -> int fails str:\n    if b == 0:\n        fail \"zero\"\n    return a // b\n\n\n" ++
            "func main() -> int:\n    mut ignored = divide(1, 0)\n    return 0\n",
        "ignored = divide",
        "return 0",
        "ignored",
    );
    // A template body is checked by its own checker and reports the same way.
    try expectUnhandledAt(
        "result R:\n    ok: i64,\n    err: i64\n\n\nfunc f[T](flag: bool, r: R) -> i64:\n    if flag:\n        return 0\n    _ = r\n    return 1\n\n\n" ++
            "func main() -> i64:\n    return 0\n",
        "r: R)",
        "return 0\n    _ = r",
        "r",
    );
}
