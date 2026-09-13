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
