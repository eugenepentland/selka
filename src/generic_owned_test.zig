//! Abstract ownership and cleanup effects for concrete runtime values.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const schema = "buffer B:u8;result A{ok:B,err:i64}struct Box{b:B,n:i64}";
fn reject(bytes: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "owned-invalid.my", bytes);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
// spec: GENERIC-OWNED-1
test "generic owned templates reject repeated moves and inconsistent continuing paths" {
    try reject(schema ++ "fn f<T:copy>(b:B)->B{let other=b;discard other;return b;}fn main()->i64{return 0;}", "E_OWNED_CONSUMED");
    try reject(schema ++ "fn f<T:copy>(flag:bool,b:B)->i64{if flag{discard b;}return 0;}fn main()->i64{return 0;}", "E_OWNED_PATH");
    try reject(schema ++ "fn f<T:copy>(b:B)->i64{while false{discard b;}return 0;}fn main()->i64{return 0;}", "E_OWNED_LOOP");
    try reject(schema ++ "fn consume(b:B)->bool{discard b;return true;}fn f<T:copy>(b:B)->i64{discard false&&consume(b);return 0;}fn main()->i64{return 0;}", "E_OWNED_PATH");
    try reject(schema ++ "fn f<T:copy>(b:&B)->&B from b{return b;}fn main()->i64{return 0;}", "E_RESULT_BORROW");
    try reject(schema ++ "fn f<T:copy>(b:B)->i64{borrow b as r{}return 0;}fn main()->i64{return 0;}", "E_RESULT_BORROW");
    try reject(schema ++ "fn f<T:copy>(b:Box)->B{return read_field(b,b);}fn main()->i64{return 0;}", "E_FIELD_COPY");
    try reject(schema ++ "fn identity<T:copy>(x:T)->T{return x;}fn f(b:B)->B{return identity::<B>(b);}fn main()->i64{return 0;}", "E_GENERIC_ARGUMENT");
}
test "generic cleanup effect bounds include nested types and transitive recursive helpers" {
    try reject("resource F:filesystem;fn f<T:copy>(value:F)->i64 noio{return 0;}fn main()->i64{return 0;}", "E_EFFECT_BOUND");
    try reject("resource F:network;struct Box{f:F}fn f<T:copy>(x:Box)->Box effects(){return x;}fn main()->i64{return 0;}", "E_EFFECT_BOUND");
    try reject("resource F:filesystem;union U{empty,full:F}fn make()->U{return new U.empty;}fn f<T:copy>()->i64 noio{discard make();return 0;}fn main()->i64{return 0;}", "E_EFFECT_BOUND");
    try reject("resource F:network;union U{empty,full:F}fn first(n:i64)->U{if n==0{return new U.empty;}return second(n-1);}fn second(" ++
        "n:i64)->U{return first(n);}fn f<T:copy>()->i64 noio{discard first(2);return 0;}fn main()->i64{return 0;}", "E_EFFECT_BOUND");
    var c = try language.Compilation.init(t.allocator, "empty-owned.my", "resource F:filesystem;fn f<T:copy>(empty:[0]F)->i64 effects(){discard empty;return 7;}fn main()->i64{return f::<bool>(new [0]F[]);}");
    defer c.deinit();
    try t.expectEqual(@as(i64, 7), (try c.execute(t.allocator)).value);
}
const program = schema ++
    "fn forward<T:copy>(b:B)->B noalloc{return b;}" ++
    "fn drop<T:copy>(b:B)->i64 noalloc{return 1;}" ++
    "fn replenish<T:copy>(first:B,second:B)->B{let mut slot=first;slot=second;return slot;}" ++
    "fn fields<T:copy>(b:Box)->i64{discard take_field(b,b);return read_field(b,n);}" ++
    "fn select<T:copy>(flag:bool,first:B,second:B)->B{if flag{return first;}return second;}" ++
    "fn work(heap:allocator,flag:bool)->i64{match acquire_buffer<A>(heap,1){A.ok(first)=>{match acquire_buffer<A>(heap," ++
    "1){A.ok(second)=>{match acquire_buffer<A>(heap,1){A.ok(third)=>{return fields::<bool>(new Box{b:forward::<bool>(" ++
    "replenish::<bool>(select::<bool>(flag,first,second),third)),n:7});},A.err(e)=>{return e;}}},A.err(e)=>{return e;}}}," ++
    "A.err(e)=>{return e;}}}" ++ "fn main(heap:allocator)->i64{return work(heap,true)+work(heap,false);}";
fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "generic-owned.my", program);
    defer c.deinit();
    try t.expectEqual(@as(i64, 14), (try c.execute(allocator)).value);
    const native = try c.emitC(allocator);
    defer allocator.free(native);
}
test "generic owned transfers partial extraction replacement and cleanup survive allocation failure" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
test "generic owned signatures cannot grant operations or local region escape rules" {
    try reject(schema ++ "fn f<T:copy>(heap:allocator)->A{return acquire_buffer<A>(heap,1);}fn main()->i64{return 0;}", "E_GENERIC_BODY_UNSUPPORTED");
    try reject(schema ++ "fn f<T:copy>(heap:allocator)->i64{arena heap as scratch{return 0;}}fn main()->i64{return 0;}", "E_GENERIC_BODY_UNSUPPORTED");
}

test "generic pool owners transfer while handles retain ordinary copy identity" {
    const bytes = "pool P(Id):i64;result A{ok:P,err:i64}result H{ok:Id,err:i64}" ++
        "fn forward<T:copy>(pool:P)->P{return pool;}fn identity<T:copy>(value:T)->T{return value;}" ++
        "fn main(heap:allocator)->i64{match acquire_pool<A>(heap,1){A.ok(pool)=>{let mut moved=forward::<bool>(pool);" ++
        "match insert_pool<H>(moved,7){H.ok(id)=>{if id==identity::<Id>(id){return 7;}return 0;},H.err(e)=>{return e;}}},A.err(e)=>{return e;}}}";
    var c = try language.Compilation.init(t.allocator, "generic-pool.my", bytes);
    defer c.deinit();
    try t.expectEqual(@as(i64, 7), (try c.execute(t.allocator)).value);
    const native = try c.emitC(t.allocator);
    defer t.allocator.free(native);
    try reject("pool P(Id):i64;fn f<T:copy>(pool:P)->P{discard pool;return pool;}fn main()->i64{return 0;}", "E_OWNED_CONSUMED");
}
