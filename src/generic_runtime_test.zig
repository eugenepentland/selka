//! Generic buffer/pool operation contracts and explicit allocator authority.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const schema = "buffer B:i64;result A{ok:B,err:i64}result S{ok:bool,err:i64}result R{ok:i64,err:i64}pool P(Id):i64;result PA{ok:P,err:i64}result H{ok:Id,err:i64}";
fn reject(body: []const u8, code: []const u8) !void {
    const bytes = try std.mem.concat(t.allocator, u8, &.{ schema, body, "fn main()->i64{return 0;}" });
    defer t.allocator.free(bytes);
    var c = try language.Compilation.init(t.allocator, "generic-runtime-invalid.my", bytes);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
const program = schema ++
    "fn fill<T:integer>(input:B,n:T)->A noalloc{let mut b=input;_ = append_buffer<S>(b,cast<i64>(n))?;return new A.ok(b);}" ++
    "fn work<T:integer>(heap:allocator,n:T)->R{let mut b=fill::<T>(acquire_buffer<A>(heap,1)?,n)?;" ++
    "_ = reserve_buffer<S>(b,heap,4)?;_ = resize_buffer<S>(b,2,9)?;_ = write_buffer<S>(b,0,5)?;" ++
    "let mut p=acquire_pool<PA>(heap,2)?;let id=insert_pool<H>(p,7)?;_ = replace_pool<S>(p,id,11)?;" ++
    "let sum=read_buffer(b,0)+read_buffer(b,1)+(read_pool<R>(p,id)?);_ = remove_pool<S>(p,id)?;discard clear_pool(" ++
    "p);return new R.ok(sum+cast<i64>(len_buffer(b))+cast<i64>(capacity_buffer(b))+cast<i64>(len_pool(p))+cast<i64>(" ++
    "capacity_pool(p)));}" ++
    "fn main(heap:allocator)->i64{match work::<u8>(heap,7u8){R.ok(n)=>{return n;},R.err(e)=>{return e;}}}";
fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "generic-runtime.my", program);
    defer c.deinit();
    try t.expectEqual(@as(i64, 33), (try c.execute(allocator)).value);
}
test "generic bufferValue poolValue acquisition mutation and propagation survive allocation failures" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
