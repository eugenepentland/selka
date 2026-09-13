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
// spec: GENERIC-RUNTIME-1
test "generic acquireValue validates acquisitionShape authority capacity and uncalled effect bounds" {
    try reject("fn f<T:copy>(heap:allocator)->R{return acquire_buffer<R>(heap,1);}", "E_BUFFER_RESULT");
    try reject("fn f<T:copy>(heap:allocator)->A{return acquire_pool<A>(heap,1);}", "E_POOL_RESULT");
    try reject("result Bad{ok:B,err:bool}fn f<T:copy>(heap:allocator)->Bad{return acquire_buffer<Bad>(heap,1);}", "E_BUFFER_RESULT");
    try reject("fn f<T:copy>()->A{return acquire_buffer<A>(true,1);}", "E_GENERIC_TYPE");
    try reject("fn f<T:copy>(heap:allocator)->A{return acquire_buffer<A>(heap,true);}", "E_GENERIC_OPERATION");
    try reject("fn f<T:copy>(heap:allocator,n:T)->A{return acquire_buffer<A>(heap,n);}", "E_GENERIC_OPERATION");
    try reject("fn f<T:copy>(heap:allocator)->A noalloc{return acquire_buffer<A>(heap,1);}", "E_EFFECT_BOUND");
    try reject("fn make(heap:allocator)->PA{return acquire_pool<PA>(heap,1);}fn f<T:copy>(heap:allocator)->i64 effects(){acknowledge make(heap);return 0;}", "E_EFFECT_BOUND");
}
test "generic runtime owners are checked after argument transfers and require mutable bindings" {
    try reject("fn f<T:copy>(b:B)->S{return append_buffer<S>(b,1);}", "E_IMMUTABLE");
    try reject("fn f<T:copy>(b:B)->i64{discard b;return read_buffer(b,0);}", "E_OWNED_CONSUMED");
    try reject("fn consume(b:B)->i64{discard b;return 1;}fn f<T:copy>(input:B)->S{let mut b=input;return append_buffer<S>(b,consume(b));}", "E_OWNED_CONSUMED");
    try reject("fn consume(p:P)->i64{discard p;return 1;}fn f<T:copy>(input:P)->H{let mut p=input;return insert_pool<H>(p,consume(p));}", "E_OWNED_CONSUMED");
    try reject("fn f<T:copy>(p:P)->u64{discard p;return len_pool(p);}", "E_OWNED_CONSUMED");
    try reject("fn f<T:copy>(p:P)->bool{return clear_pool(p);}", "E_IMMUTABLE");
}
test "generic operationResult and element handle contracts reject malformed uncalled operations" {
    try reject("fn f<T:copy>(input:B)->R{let mut b=input;return append_buffer<R>(b,1);}", "E_BUFFER_RESULT");
    try reject("fn f<T:copy>(input:B)->S{let mut b=input;return append_buffer<S>(b,true);}", "E_GENERIC_TYPE");
    try reject("fn f<T:copy>(input:B)->S{let mut b=input;return reserve_buffer<S>(b,true,2);}", "E_GENERIC_TYPE");
    try reject("fn f<T:copy>(input:B,heap:allocator)->S noalloc{let mut b=input;return reserve_buffer<S>(b,heap,2);}", "E_EFFECT_BOUND");
    try reject("fn f<T:copy>(input:P)->S{let mut p=input;return insert_pool<S>(p,1);}", "E_POOL_RESULT");
    try reject("pool Other(OtherId):i64;fn f<T:copy>(p:P,id:OtherId)->R{return read_pool<R>(p,id);}", "E_GENERIC_TYPE");
    try reject("fn f<T:copy>(p:P,id:Id)->S{return read_pool<S>(p,id);}", "E_POOL_RESULT");
}
const program = schema ++
    "fn fill<T:integer>(input:B,n:T)->A noalloc{let mut b=input;discard try append_buffer<S>(b,cast<i64>(n));return new A.ok(b);}" ++
    "fn work<T:integer>(heap:allocator,n:T)->R{let mut b=try fill::<T>(try acquire_buffer<A>(heap,1),n);" ++
    "discard try reserve_buffer<S>(b,heap,4);discard try resize_buffer<S>(b,2,9);discard try write_buffer<S>(b,0,5);" ++
    "let mut p=try acquire_pool<PA>(heap,2);let id=try insert_pool<H>(p,7);discard try replace_pool<S>(p,id,11);" ++
    "let sum=read_buffer(b,0)+read_buffer(b,1)+(try read_pool<R>(p,id));discard try remove_pool<S>(p,id);discard clear_pool(" ++
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
test "generic failed acquisition propagates while releasing an earlier owned buffer" {
    const bytes = schema ++ "fn f<T:integer>(heap:allocator,n:T)->A{let first=try acquire_buffer<A>(heap,1);let second=try acquire_buffer<A>(heap,n);" ++
        "discard first;return new A.ok(second);}fn main(heap:allocator)->i64{match f::<i64>(heap,-1){A.ok(discard)=>{return 0;}," ++
        "A.err(discard)=>{return 7;}}}";
    var c = try language.Compilation.init(t.allocator, "generic-acquire-failure.my", bytes);
    defer c.deinit();
    try t.expectEqual(@as(i64, 7), (try c.execute(t.allocator)).value);
}
