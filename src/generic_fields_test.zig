//! Partial field availability is checked before generic instantiation.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const schema = "result R{ok:i64,err:i64}struct Pair{left:R,right:R,code:i64}";
fn reject(body: []const u8, code: []const u8) !void {
    const bytes = try std.mem.concat(t.allocator, u8, &.{ schema, body, "fn main()->i64{return 0;}" });
    defer t.allocator.free(bytes);
    var c = try language.Compilation.init(t.allocator, "generic-fields-invalid.my", bytes);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
const program = schema ++
    "fn drain<T:copy>(flag:bool,p:Pair)->i64{if flag{_ = p.left;_ = p.right;}else{_ = p.right;_ = p.left;}return p.code;}" ++
    "fn step<T:copy>(p:Pair)->R{_ = p.left;let n=p.right?;return new R.ok(n+p.code);}" ++
    "fn number(r:R)->i64{match r{R.ok(n)=>{return n;},R.err(n)=>{return 0-n;}}}" ++
    "fn refill<T:copy>()->i64{let mut n=0;let mut p=new Pair{left:new R.ok(1),right:new R.err(2),code:3};" ++
    "while n<2{_ = p.left;_ = p.right;p=new Pair{left:new R.ok(n),right:new R.ok(n)," ++
    "code:n};n+=1;}_ = p.left;_ = p.right;return p.code;}" ++
    "fn main()->i64{return drain::<bool>(true,new Pair{left:new R.ok(1),right:new R.ok(2),code:3})+drain::<bool>(false," ++
    "new Pair{left:new R.ok(1),right:new R.ok(2),code:4})+number(step::<bool>(new Pair{left:new R.ok(1),right:new R.ok(5)," ++
    "code:6}))+number(step::<bool>(new Pair{left:new R.ok(1),right:new R.err(2),code:6}))+refill::<bool>();}";
fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "generic-fields.my", program);
    defer c.deinit();
    try t.expectEqual(@as(i64, 17), (try c.execute(allocator)).value);
}
test "generic fieldValue snapshots scopes replenishment and propagation survive allocation failures" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
