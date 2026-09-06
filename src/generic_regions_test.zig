//! Generic arena authority and fixed-point escape checks precede specialization.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const memory = @import("memory.zig");
const schema = @import("fixture_declarations_test.zig").generic_buffer_results;
const program = schema ++
    "fn reset<T:copy>(region:allocator)->S noalloc{return reset_arena<S>(region);}" ++
    "fn work<T:integer>(heap:allocator,n:T)->R{arena heap as scratch{let copy=scratch;" ++
    "let mut b=try acquire_buffer<A>(scratch,8);discard try append_buffer<S>(b,cast<i64>(n));" ++
    "borrow b[0..1] as view{match reset::<T>(copy){S.ok(discard)=>{return new R.err(90);},S.err(code)=>{if code!=1{return new R.err(91);}}}" ++
    "if read_slice(view,0)!=7{return new R.err(92);}}discard b;" ++
    "arena scratch as child{discard try reset::<T>(child);match reset::<T>(scratch){S.ok(discard)=>{return new R.err(93);},S.err(code)=>{if code!=2{return new R.err(94);}}}}" ++
    "discard try reset::<T>(copy);let replacement=try acquire_buffer<A>(scratch,3);let value=cast<i64>(capacity_buffer(replacement));" ++
    "discard replacement;discard try reset::<T>(scratch);return new R.ok(value);}}" ++
    "fn main(heap:allocator)->i64{match work::<u8>(heap,7u8){R.ok(value)=>{return value;},R.err(code)=>{return code;}}}";
fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "generic-regions.my", program);
    defer c.deinit();
    var statistics: memory.Statistics = .{};
    const outcome = try c.executeWithOptions(allocator, .{ .memory = .{ .statistics = &statistics, .limits = .{ .max_regions = 2, .max_allocations = 1 } } });
    try t.expectEqual(@as(i64, 3), outcome.value);
    try t.expectEqual(@as(u64, 2), statistics.created);
    try t.expectEqual(statistics.created, statistics.released);
}
// spec: GENERIC-REGION-1
test "generic arena scopes and reset preserve authority live storage child checks and allocation cleanup" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
fn reject(body: []const u8, code: []const u8) !void {
    const text = try std.mem.concat(t.allocator, u8, &.{ schema, body, "fn main()->i64{return 0;}" });
    defer t.allocator.free(text);
    var c = try language.Compilation.init(t.allocator, "generic-region-invalid.my", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
test "generic arenas reject malformed authority shadowing effects and reset result contracts uncalled" {
    try reject("fn f<T:copy>()->i64{arena true as scratch{return 0;}}", "E_GENERIC_TYPE");
    try reject("fn f<T:copy>(heap:allocator)->i64{arena heap as heap{return 0;}}", "E_SHADOWING");
    try reject("fn f<T:copy>(heap:allocator)->i64 noalloc{arena heap as scratch{return 0;}}", "E_EFFECT_BOUND");
    try reject("fn helper(heap:allocator)->i64{arena heap as scratch{return 0;}}fn f<T:copy>(heap:allocator)->i64 noalloc{return helper(heap);}", "E_EFFECT_BOUND");
    try reject("fn f<T:copy>(heap:allocator)->R{return reset_arena<R>(heap);}", "E_ARENA_RESULT");
    try reject("fn f<T:copy>()->S{return reset_arena<S>(true);}", "E_GENERIC_TYPE");
    try reject("fn f<T:copy>(heap:allocator)->i64{discard reset_arena<S>(heap);return 0;}", "E_RESULT_DISCARD");
    try reject("fn f<T:copy>(heap:allocator)->i64{arena heap as scratch{}discard scratch;return 0;}", "E_UNKNOWN_NAME");
}
test "generic arena values cannot escape in returns assignments records match payloads or propagated errors" {
    try reject("fn f<T:copy>(heap:allocator)->allocator{arena heap as scratch{return scratch;}}", "E_ARENA_ESCAPE");
    try reject("fn f<T:copy>(heap:allocator)->allocator{let mut out=heap;arena heap as scratch{out=scratch;}return out;}", "E_ARENA_ESCAPE");
    try reject("fn f<T:copy>(heap:allocator)->A{arena heap as scratch{return acquire_buffer<A>(scratch,1);}}", "E_ARENA_ESCAPE");
    try reject("struct Box{cap:allocator}fn f<T:copy>(heap:allocator)->Box{arena heap as scratch{return new Box{cap:scratch};}}", "E_ARENA_ESCAPE");
    try reject("result Cap{ok:allocator,err:i64}fn f<T:copy>(heap:allocator)->allocator{arena heap as scratch{match new Cap.ok(scratch){Cap.ok(cap)=>{return cap;},Cap.err(discard)=>{return heap;}}}}", "E_ARENA_ESCAPE");
    try reject("result Error{ok:i64,err:allocator}fn f<T:copy>(heap:allocator)->Error{arena heap as scratch{discard try new Error.err(scratch);}return new Error.ok(0);}", "E_ARENA_ESCAPE");
    try reject("fn id<U:copy>(cap:U)->U{return cap;}fn f<T:copy>(heap:allocator)->allocator{arena heap as scratch{return id::<allocator>(scratch);}}", "E_ARENA_ESCAPE");
}
test "generic region dependencies remain monotone through loops helper writes and copied fields" {
    try reject("fn f<T:copy>(heap:allocator)->allocator{arena heap as scratch{let mut x=heap;let mut y=heap;while false{x=y;y=scratch;}return x;}}", "E_ARENA_ESCAPE");
    try reject("fn set(dest:&mut allocator,cap:allocator)->i64{write_ref(dest,cap);return 0;}fn f<T:copy>(heap:allocator)->allocator{arena heap as scratch{let mut x=heap;" ++
        "borrow mut x as r{discard set(r,scratch);}return x;}}", "E_ARENA_ESCAPE");
    try reject("fn set<U:copy>(dest:&mut U,source:&U)->i64{write_ref(dest,read_ref(source));return 0;}fn f<T:copy>(heap:allocator)->i64{let mut outside=heap;" ++
        "borrow mut outside as dest{arena heap as scratch{borrow scratch as input{discard set::<allocator>(dest,input);}}}return 0;}", "E_ARENA_ESCAPE");
    try reject("struct Box{cap:allocator,n:i64}fn f<T:copy>(heap:allocator)->allocator{arena heap as scratch{let box=new Box{cap:scratch,n:0};return box.cap;}}", "E_ARENA_ESCAPE");
    try reject("fn f<T:copy>(heap:allocator)->allocator{arena heap as scratch{let mut a=new [1]allocator[heap];borrow mut a[0..1] as s{write_slice(s,0,scratch);}return a[0];}}", "E_ARENA_ESCAPE");
}
test "generic arena dependencies cannot be stored in longer lived buffers or pools" {
    try reject("buffer Caps:allocator;result Open{ok:Caps,err:i64}fn f<T:copy>(heap:allocator)->S{let mut caps=try acquire_buffer<Open>(heap,1);arena heap as scratch{return append_buffer<S>(caps,scratch);}}", "E_ARENA_ESCAPE");
    try reject("pool Caps(Id):allocator;" ++
        "result Open{ok:Caps,err:i64}result Insert{ok:Id,err:i64}fn f<T:copy>(heap:allocator)->Insert{let mut caps=try acquire_pool<Open>(heap,1);arena heap as scratch{return insert_pool<Insert>(caps,scratch);}}", "E_ARENA_ESCAPE");
    try reject("buffer Caps:allocator;result Open{ok:Caps,err:i64}fn f<T:copy>(heap:allocator)->S{let mut caps=try acquire_buffer<Open>(heap,1);" ++
        "discard try append_buffer<S>(caps,heap);borrow mut caps[0..1] as s{arena heap as scratch{write_slice(s,0,scratch);}}return new S.ok(true);}", "E_ARENA_ESCAPE");
}
test "generic arena cleanup survives every VM step limit in both execution backings" {
    var c = try language.Compilation.init(t.allocator, "generic-region-traps.my", program);
    defer c.deinit();
    for ([_]language.vm.MemoryBacking{ .general, .arena }) |backing| {
        var finished = false;
        for (1..500) |budget| {
            var statistics: memory.Statistics = .{};
            const result = try c.executeWithOptions(t.allocator, .{ .max_steps = budget, .memory = .{ .backing = backing, .statistics = &statistics } });
            try t.expectEqual(statistics.created, statistics.released);
            if (result == .value) {
                try t.expectEqual(@as(i64, 3), result.value);
                finished = true;
                break;
            }
            try t.expectEqualStrings("R_STEP_LIMIT", result.trap.code);
        }
        try t.expect(finished);
    }
}

test "generic arena scopes allow independent heap owners plain snapshots and inert pool handles to leave" {
    const text = schema ++ "pool P(Id):i64;result Open{ok:P,err:i64}result Insert{ok:Id,err:i64}" ++
        "fn keep<T:copy>(heap:allocator)->A{arena heap as scratch{return acquire_buffer<A>(heap,2);}}" ++
        "fn stale<T:copy>(heap:allocator)->Insert{arena heap as scratch{let mut p=try acquire_pool<Open>(scratch,1);return insert_pool<Insert>(p,7);}}" ++
        "fn work<T:copy>(heap:allocator)->R{let b=try keep::<T>(heap);let id=try stale::<T>(heap);let p=try acquire_pool<Open>(heap,1);" ++
        "let mut plain=new [1]i64[0];arena heap as scratch{let mut local=try acquire_buffer<A>(scratch,1);discard try append_buffer<S>(local,9);" ++
        "borrow local[0..1] as s{plain=new [1]i64[read_slice(s,0)];}}match read_pool<R>(p,id){R.ok(discard)=>{return new R.err(90);},R.err(code)=>{return new R.ok(plain[0]+cast<i64>(capacity_buffer(b))+code);}}}" ++
        "fn main(heap:allocator)->i64{match work::<bool>(heap){R.ok(n)=>{return n;},R.err(e)=>{return e;}}}";
    var c = try language.Compilation.init(t.allocator, "generic-region-snapshots.my", text);
    defer c.deinit();
    try t.expectEqual(@as(i64, 13), (try c.execute(t.allocator)).value);
}

test "generic equality requirements prove reference elements cannot retain arena dependencies" {
    const text = "fn inspect<U:equality>(value:&mut U,cap:allocator)->i64{discard cap;write_ref(value,read_ref(value));return 0;}" ++
        "fn identity<T:equality>(heap:allocator,input:T)->T{let mut out=input;borrow mut out as r{arena heap as scratch{discard inspect::<T>(r,scratch);}}return out;}" ++
        "fn main(heap:allocator)->i64{if identity::<bool>(heap,true){return 1;}return 0;}";
    var c = try language.Compilation.init(t.allocator, "generic-region-equality.my", text);
    defer c.deinit();
    try t.expectEqual(@as(i64, 1), (try c.execute(t.allocator)).value);
}
