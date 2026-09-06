//! Generic local array/buffer views retain owner access and returned-input provenance.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const schema = "buffer B:i64;result A{ok:B,err:i64}result S{ok:bool,err:i64}result R{ok:i64,err:i64}";
const functions =
    "fn tail<T:copy>(a:&mut [3]i64)->&mut []i64 from a{borrow mut a[1..3] as s{return s;}}" ++
    "fn arrays<T:integer>(n:T)->i64{let mut a=new [3]i64[1,2,3];let original=a;" ++
    "borrow mut a as whole{borrow mut tail::<T>(whole) as s{write_slice(s,0,cast<i64>(n));}}" ++
    "borrow a[3..3] as empty{discard len_slice(empty);}borrow a[0..3] as s{borrow s[1..2] as child{return read_slice(child,0)+original[1];}}}" ++
    "fn buffers<T:integer>(heap:allocator,n:T)->R{let mut b=try acquire_buffer<A>(heap,3);" ++
    "discard try append_buffer<S>(b,1);discard try append_buffer<S>(b,2);" ++
    "borrow mut b[0..len_buffer(b)] as s{write_slice(s,0,cast<i64>(n));borrow s[1..2] as child{discard read_slice(child,0);}}" ++
    "borrow b[2..2] as empty{discard len_slice(empty);}borrow b[0..2] as shared{discard read_buffer(b,0);}" ++
    "return new R.ok(read_buffer(b,0)+read_buffer(b,1));}";
fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "local-views.my", schema ++ functions ++
        "fn main(heap:allocator)->i64{match buffers::<u8>(heap,9u8){R.ok(n)=>{return n+arrays::<i8>(9i8);},R.err(e)=>{return e;}}}");
    defer c.deinit();
    try t.expectEqual(@as(i64, 22), (try c.execute(allocator)).value);
}
// spec: GENERIC-LOCAL-VIEW-1
test "generic local views execute array snapshots buffer narrowing and returned array input slices" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
fn reject(body: []const u8, code: []const u8) !void {
    const text = try std.mem.concat(t.allocator, u8, &.{ schema, body, "fn main()->i64{return 0;}" });
    defer t.allocator.free(text);
    var c = try language.Compilation.init(t.allocator, "invalid-local-view.my", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
test "generic local views reject non-slice shapes permissions and borrowed owner access before instantiation" {
    try reject("fn f<T:copy>(x:i64)->i64{borrow x[0..1] as s{return read_slice(s,0);}}", "E_SLICE_TYPE");
    try reject("enum Key{a,b}fn f<T:copy>(x:[Key]i64)->i64{borrow x[0..1] as s{return read_slice(s,0);}}", "E_SLICE_TYPE");
    try reject("fn f<T:copy>(a:[1]R)->i64{borrow a[0..1] as s{return 0;}}", "E_RESULT_BORROW");
    try reject("fn f<T:copy>(a:[1]i64)->i64{borrow mut a[0..1] as s{return 0;}}", "E_IMMUTABLE");
    try reject("fn f<T:copy>()->i64{let mut a=new [1]i64[1];borrow mut a[0..1] as s{return a[0];}}", "E_BORROW_CONFLICT");
    try reject("fn f<T:copy>()->i64{let mut a=new [1]i64[1];borrow a[0..1] as s{a=new [1]i64[2];}return 0;}", "E_BORROW_CONFLICT");
    try reject("fn f<T:copy>()->i64{let a=new [1]i64[1];borrow a[0..1] as s{write_slice(s,0,2);}return 0;}", "E_REFERENCE_READ_ONLY");
    try reject("fn f<T:copy>()->i64{let mut a=new [1]i64[1];borrow mut a as whole{borrow whole[0..1] as s{discard read_ref(whole);}}return 0;}", "E_BORROW_SUSPENDED");
}
test "generic local buffer views check ownership after bounds and forbid transfer or growth while borrowed" {
    try reject("fn f<T:copy>(b:B)->i64{discard b;borrow b[0..0] as s{return 0;}}", "E_OWNED_CONSUMED");
    try reject("fn consume(b:B)->i64{discard b;return 0;}fn f<T:copy>(b:B)->i64{borrow b[consume(b)..0] as s{return 0;}}", "E_OWNED_CONSUMED");
    try reject("fn f<T:copy>(b:B)->i64{borrow b[0..0] as s{discard b;}return 0;}", "E_BORROW_CONFLICT");
    try reject("fn f<T:copy>(input:B,heap:allocator)->i64{let mut b=input;borrow b[0..0] as s{acknowledge reserve_buffer<S>(b,heap,2);}return 0;}", "E_BORROW_CONFLICT");
    try reject("fn f<T:copy>(b:B)->i64{borrow b as s{return 0;}}", "E_RESULT_BORROW");
    try reject("fn f<T:copy>(input:B)->i64{let mut b=input;borrow mut b[0..0] as s{return cast<i64>(len_buffer(b));}}", "E_BORROW_CONFLICT");
}
test "generic local slices cannot escape as borrowed input results or change nominal element type" {
    try reject("fn f<T:copy>(input:&[]i64)->&[]i64 from input{let a=new [1]i64[1];borrow a[0..1] as s{return s;}}", "E_RETURN_LIFETIME");
    try reject("fn f<T:copy>(input:&[]i64,b:B)->&[]i64 from input{borrow b[0..0] as s{return s;}}", "E_RETURN_LIFETIME");
    try reject("fn f<T:copy>(a:&[1]i64)->&[]bool from a{borrow a[0..1] as s{return s;}}", "E_GENERIC_TYPE");
    try reject("fn f<T:copy>(a:&[1]i64)->&mut []i64 from a{borrow a[0..1] as s{return s;}}", "E_REFERENCE_READ_ONLY");
    try reject("fn f<T:copy>(a:&mut [1]i64)->&mut []i64 from a{borrow a[0..1] as s{return s;}}", "E_REFERENCE_READ_ONLY");
}
test "generic local array view bounds trap at the borrow source" {
    var c = try language.Compilation.init(t.allocator, "view-trap.my", "fn f<T:integer>(n:T)->i64{let a=new [1]i64[7];borrow a[0..n] as s{return read_slice(s,0);}}fn main()->i64{return f::<i64>(2);}");
    defer c.deinit();
    const outcome = try c.execute(t.allocator);
    try t.expectEqualStrings("R_SLICE_BOUNDS", outcome.trap.code);
    try t.expect(std.mem.startsWith(u8, c.src.text(outcome.trap.span), "borrow a"));
}
