const std = @import("std");
const testing = std.testing;
const language = @import("compiler.zig");
const LimitedLiveAllocator = @import("test_support.zig").LimitedLiveAllocator;
const declaration = "result R { ok: i64, err: i64 } ";
fn result(source: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(testing.allocator, "results.my", source);
    defer compilation.deinit();
    try testing.expectEqual(expected, (try compilation.execute(testing.allocator)).value);
}
fn reject(body: []const u8, code: []const u8) !void {
    const source = try std.mem.concat(testing.allocator, u8, &.{ declaration, body });
    defer testing.allocator.free(source);
    var compilation = try language.Compilation.init(testing.allocator, "results.my", source);
    defer compilation.deinit();
    try testing.expectError(error.SourceError, compilation.check());
    try testing.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

test "nominal typed results handle success and failure through exhaustive matches" {
    try result("enum E { missing } result R { err: E, ok: i64 } fn make(ok: bool) -> R { if ok { return new R.ok(7); } return new R.err(new E.missing); } fn handle(r: R) -> i64 { match r { R.ok(n) => { return n; }, R.err(e) => { match e { E.missing => { return 3; } } } } } fn main() -> i64 { return handle(make(true)) + handle(make(false)); }", 10);
    try result("result R { ok: i64, err: bool } fn forward(r: R) -> R { return r; } fn main() -> i64 { let result = forward(new R.err(true)); match result { R.ok(n) => { return n; }, R.err(e) => { if e { return 9; } return 0; } } }", 9);
    try reject("result Bad { ok: i64 } fn main() -> i64 { return 0; }", "E_RESULT_SCHEMA");
    try reject("result Bad { ok: i64, err } fn main() -> i64 { return 0; }", "E_RESULT_SCHEMA");
    try reject("result Other { ok: i64, err: i64 } fn f(r: R) -> Other { return r; } fn main() -> i64 { return 0; }", "E_TYPE");
}

test "binding transfer and explicit acknowledgement cannot silently discard results" {
    try result("result R { ok: i64, err: i64 } fn main() -> i64 { let first = new R.err(7); let second = first; acknowledge second; return 1; }", 1);
    try reject("fn main() -> i64 { let ignored = new R.err(7); return 0; }", "E_RESULT_UNHANDLED");
    try reject("fn main() -> i64 { { let ignored = new R.ok(7); } return 0; }", "E_RESULT_UNHANDLED");
    try reject("fn main() -> i64 { discard new R.err(7); return 0; }", "E_RESULT_DISCARD");
    try reject("fn main() -> i64 { let r = new R.ok(7); let copied = r; acknowledge r; acknowledge copied; return 0; }", "E_RESULT_CONSUMED");
    try reject("fn main() -> i64 { acknowledge 7; return 0; }", "E_ACKNOWLEDGE_TYPE");
    try reject("fn swallow(r: R) -> i64 { return 0; } fn main() -> i64 { return swallow(new R.err(7)); }", "E_RESULT_UNHANDLED");
    try reject("fn swallow(r: R) -> i64 { discard r; return 0; } fn main() -> i64 { return 0; }", "E_RESULT_DISCARD");
}

test "result obligations must agree across all continuing branch and match paths" {
    try result("result R { ok: i64, err: i64 } fn handle(flag: bool, r: R) -> i64 { if flag { acknowledge r; } else { acknowledge r; } return 7; } fn main() -> i64 { return handle(false, new R.err(3)); }", 7);
    try result("result R { ok: i64, err: i64 } fn handle(flag: bool, r: R) -> i64 { if flag { acknowledge r; return 1; } acknowledge r; return 2; } fn main() -> i64 { return handle(false, new R.err(3)); }", 2);
    try reject("fn f(flag: bool, r: R) -> i64 { if flag { acknowledge r; } return 0; } fn main() -> i64 { return 0; }", "E_RESULT_PATH");
    try reject("fn f(flag: bool, r: R) -> i64 { if flag { return 0; } acknowledge r; return 1; } fn main() -> i64 { return 0; }", "E_RESULT_UNHANDLED");
    try reject("enum E { a, b } fn f(e: E, r: R) -> i64 { match e { E.a => { acknowledge r; }, E.b => {} } return 0; } fn main() -> i64 { return 0; }", "E_RESULT_PATH");
    try result("result R { ok: i64, err: i64 } enum E { a, b } fn f(e: E, r: R) -> i64 { match e { E.a => { acknowledge r; return 1; }, E.b => {} } acknowledge r; return 2; } fn main() -> i64 { return f(new E.b, new R.ok(3)); }", 2);
}

test "loops and short circuit evaluation cannot conditionally lose result obligations" {
    try reject("fn main() -> i64 { let r = new R.err(1); while false { acknowledge r; } return 0; }", "E_RESULT_LOOP");
    try reject("fn consume(r: R) -> bool { acknowledge r; return false; } fn main() -> i64 { let r = new R.err(1); while consume(r) {} return 0; }", "E_RESULT_LOOP");
    try reject("fn consume(r: R) -> bool { acknowledge r; return true; } fn main() -> i64 { let r = new R.err(1); discard false && consume(r); return 0; }", "E_RESULT_PATH");
    try reject("fn consume(r: R) -> bool { acknowledge r; return true; } fn main() -> i64 { let r = new R.err(1); discard true || consume(r); return 0; }", "E_RESULT_PATH");
    try result("result R { ok: i64, err: i64 } fn consume(r: R) -> bool { acknowledge r; return true; } fn main() -> i64 { let r = new R.err(1); discard consume(r) && false; discard false && consume(new R.err(7)); return 1; }", 1);
    try result("result R { ok: i64, err: i64 } fn main() -> i64 { let mut n = 0; let mut r = new R.ok(0); while n < 3 { acknowledge r; r = new R.err(n); n += 1; } acknowledge r; return n; }", 3);
}

test "mutable result slots require handling before replacement and permit explicit transfer" {
    try reject("fn main() -> i64 { let mut r = new R.err(1); r = new R.ok(2); acknowledge r; return 0; }", "E_RESULT_OVERWRITE");
    try result("result R { ok: i64, err: i64 } fn main() -> i64 { let mut r = new R.err(1); let old = r; r = new R.ok(2); acknowledge old; match r { R.ok(n) => { return n; }, R.err(discard) => { return 0; } } }", 2);
    try result("result R { ok: i64, err: i64 } fn main() -> i64 { let mut r = new R.err(1); r = r; acknowledge r; return 7; }", 7);
}

test "wrappers arrays and unions preserve nested result obligations" {
    try reject("struct Box { r: R } fn main() -> i64 { discard new Box { r: new R.err(1) }; return 0; }", "E_RESULT_DISCARD");
    try reject("struct Box { r: R, n: i64 } fn main() -> i64 { return new Box { r: new R.err(1), n: 7 }.n; }", "E_RESULT_OPERATION");
    try reject("fn main() -> i64 { discard len(new [1]R [new R.err(1)]); return 0; }", "E_RESULT_OPERATION");
    try reject("fn main() -> i64 { acknowledge new [2]R [new R.err(1), new R.ok(2)][0]; return 0; }", "E_RESULT_OPERATION");
    try reject("union Box { wrapped: R, empty } fn main() -> i64 { match new Box.wrapped(new R.err(1)) { Box.wrapped(discard) => { return 0; }, Box.empty => { return 1; } } }", "E_RESULT_DISCARD");
    try reject("union Box { wrapped: R, empty } fn main() -> i64 { match new Box.wrapped(new R.err(1)) { Box.wrapped(r) => {}, Box.empty => {} } return 0; }", "E_RESULT_UNHANDLED");
    try result("result R { ok: i64, err: i64 } struct Box { r: R, n: i64 } fn main() -> i64 { let box = new Box { r: new R.err(1), n: 7 }; let updated = update(box) { n: 9 }; acknowledge updated.r; acknowledge new [1]R [new R.err(3)][0]; discard new [0]R []; return 1; }", 1);
    try reject("struct Box { r: R } fn main() -> i64 { let box = new Box { r: new R.err(1) }; acknowledge update(box) { r: new R.ok(2) }; return 0; }", "E_RESULT_OPERATION");
    try result("result R { ok: i64, err: i64 } result Outer { ok: R, err: bool } fn main() -> i64 { match new Outer.ok(new R.err(7)) { Outer.ok(inner) => { acknowledge inner; return 1; }, Outer.err(discard) => { return 0; } } }", 1);
    try reject("fn f(r: &R) -> i64 { return 0; } fn main() -> i64 { return 0; }", "E_RESULT_BORROW");
}

const owned_source = "struct Item { n: i64 } result R { ok: Item, err: i64 } fn fallible(flag: bool) -> R { let mut x = new Item { n: 3 }; borrow mut x as r { if flag { write_ref(r, new Item { n: 9 }); return new R.ok(read_ref(r)); } return new R.err(7); } } fn main() -> i64 { let r = fallible(false); match r { R.ok(item) => { return item.n; }, R.err(code) => { acknowledge fallible(true); return code; } } }";
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "results.my", owned_source);
    defer compilation.deinit();
    try testing.expectEqual(@as(i64, 7), (try compilation.execute(allocator)).value);
    const dump = try compilation.dump(allocator);
    defer allocator.free(dump);
    var discovery = try language.duplicates.discover(allocator, compilation.program.?, .{});
    defer discovery.deinit();
}

test "recoverable error returns and explicit acknowledgement preserve evaluation and borrow cleanup" {
    try allocationScenario(testing.allocator);
    var compilation = try language.Compilation.init(testing.allocator, "trap.my", "result R { ok: i64, err: i64 } fn main() -> i64 { acknowledge new R.ok(1 / 0); return 0; }");
    defer compilation.deinit();
    try testing.expectEqualStrings("R_DIVISION_BY_ZERO", (try compilation.execute(testing.allocator)).trap.code);
}

test "result checking runtime ownership and rendering survive allocation failure" {
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
}

test "result loops and every trap boundary release bounded live runtime storage" {
    var compilation = try language.Compilation.init(testing.allocator, "results.my", owned_source);
    defer compilation.deinit();
    try compilation.emit();
    var limiter = LimitedLiveAllocator{ .parent = testing.allocator, .limit = 16384 };
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
    var loop = try language.Compilation.init(testing.allocator, "loop.my", "result R { ok: i64, err: i64 } fn main() -> i64 { let mut i = 0; while i < 10000 { let r = new R.err(i); acknowledge r; i += 1; } return i; }");
    defer loop.deinit();
    try loop.emit();
    try testing.expectEqual(@as(i64, 10000), (try loop.execute(limiter.allocator())).value);
    try testing.expectEqual(@as(usize, 0), limiter.live);
}

test "duplicate identity retains explicit acknowledgement and fallible result types" {
    var compilation = try language.Compilation.init(testing.allocator, "duplicates.my", "result R { ok: i64, err: i64 } fn a(r: R) -> i64 { acknowledge r; return 1; } fn b(other: R) -> i64 { acknowledge other; return 1; } fn c(r: R) -> i64 { match r { R.ok(discard) => {}, R.err(discard) => {} } return 1; } fn main() -> i64 { return 0; }");
    defer compilation.deinit();
    try compilation.check();
    var discovery = try language.duplicates.discover(testing.allocator, compilation.program.?, .{ .min_nodes = 1 });
    defer discovery.deinit();
    try testing.expectEqual(@as(usize, 1), discovery.groups.len);
    try testing.expectEqual(@as(usize, 2), discovery.groups[0].members.len);
}
