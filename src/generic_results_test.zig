//! Result obligations in uninstantiated templates and their executable specializations.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const schema = "result R{ok:i64,err:i64}";
fn reject(body: []const u8, code: []const u8) !void {
    const bytes = try std.mem.concat(t.allocator, u8, &.{ schema, body, "fn main()->i64{return 0;}" });
    defer t.allocator.free(bytes);
    var c = try language.Compilation.init(t.allocator, "generic-result-invalid.my", bytes);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
fn run(bytes: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "generic-result.my", bytes);
    defer c.deinit();
    try t.expectEqual(expected, (try c.execute(t.allocator)).value);
}
const scenario_source = schema ++
    "fn step<T:copy>(r:R)->R{return new R.ok((r?)+1);}" ++
    "fn consume(r:R)->bool{_ = r;return true;}" ++
    "fn flow<T:copy>(flag:bool,r:R)->i64{if flag{_ = r;return 1;}_ = r;let mut n=0;" ++
    "let mut item=new R.ok(0);while n<3{_ = item;item=new R.err(n);n+=1;}_ = item;" ++
    "_ = false&&consume(new R.err(1));return n;}" ++
    "fn main()->i64{let n=flow::<bool>(true,new R.ok(1))+flow::<bool>(false,new R.err(2));match step::<bool>(new R.ok(4)){R.ok(value)=>{return value+n;},R.err(_)=>{return 0;}}}";
const nested_source = schema ++ "union U{a:R,b}fn make<T:integer>(n:T)->R{return new R.ok(cast<i64>(n));" ++
    "}fn take<T:copy>(u:U)->i64{match u{U.a(r)=>{match r{R.ok(n)=>{return n;},R.err(n)=>{return 0-n;" ++
    "}}},U.b=>{return 0;}}}fn main()->i64{return take::<bool>(new U.a(make::<u8>(7u8)))+take::<bool>(new U.a(new R." ++
    "err(2)))+take::<bool>(new U.b);}";
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "generic-results.my", scenario_source);
    defer c.deinit();
    try t.expectEqual(@as(i64, 9), (try c.execute(allocator)).value);
}
test "generic result construction nested matching and native emission survive allocation failures" {
    try run(nested_source, 5);
    try allocationScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), allocationScenario, .{});
}

test "generic branches restore result state and merge only continuing paths" {
    try reject("fn f<T:copy>(flag:bool,r:R)->i64{if flag{_ = r;}return 0;}", "E_RESULT_PATH");
    try reject("fn f<T:copy>(flag:bool,r:R)->i64{if flag{return 0;}_ = r;return 1;}", "E_RESULT_UNHANDLED");
    try run(schema ++ "fn f<T:copy>(flag:bool,r:R)->i64{if flag{_ = r;return 1;}_ = r;return 2;}fn main()->i64{return f::<bool>(true,new R.err(3))+f::<bool>(false,new R.ok(4));}", 3);
    try run(schema ++ "fn f<T:copy>(flag:bool,r:R)->i64{if flag{_ = r;}else{_ = r;}return 7;}fn main()->i64{return f::<bool>(true,new R.err(3))+f::<bool>(false,new R.ok(4));}", 14);
}

test "generic matches transfer nested payloads and merge outer obligations" {
    try reject("enum E{a,b}fn f<T:copy>(e:E,r:R)->i64{match e{E.a=>{_ = r;},E.b=>{}}return 0;}", "E_RESULT_PATH");
    try reject("union U{a:R,b}fn f<T:copy>(u:U)->i64{match u{U.a(ignored)=>{},U.b=>{}}return 0;}", "E_RESULT_DISCARD");
    try reject("union U{a:R,b}fn f<T:copy>(u:U)->i64{match u{U.a(r)=>{},U.b=>{}}return 0;}", "E_RESULT_UNHANDLED");
    try run(schema ++ "enum E{a,b}fn f<T:copy>(e:E,r:R)->i64{match e{E.a=>{_ = r;return 1;},E.b=>{}}_ = r;return 2;}fn main()->i64{return f::<bool>(new E.a,new R.err(3))+f::<bool>(new E.b,new R.ok(4));}", 3);
}

test "generic acknowledgement retains operand traps" {
    var c = try language.Compilation.init(t.allocator, "generic-result-trap.my", schema ++ "fn f<T:integer>(n:T)->i64{_ = new R.err(7/cast<i64>(n));return 0;}fn main()->i64{return f::<u8>(0u8);}");
    defer c.deinit();
    try t.expectEqualStrings("R_DIVISION_BY_ZERO", (try c.execute(t.allocator)).trap.code);
}
