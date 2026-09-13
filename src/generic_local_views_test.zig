//! Generic local array/buffer views retain owner access and returned-input provenance.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const schema = @import("fixture_declarations_test.zig").generic_buffer_results;
const functions =
    "fn tail<T:copy>(a:&mut [3]i64)->&mut []i64 from a{borrow mut a[1..3] as s{return s;}}" ++
    "fn arrays<T:integer>(n:T)->i64{let mut a=new [3]i64[1,2,3];let original=a;" ++
    "borrow mut a as whole{borrow mut tail::<T>(whole) as s{write_slice(s,0,cast<i64>(n));}}" ++
    "borrow a[3..3] as empty{_ = len_slice(empty);}borrow a[0..3] as s{borrow s[1..2] as child{return read_slice(child,0)+original[1];}}}" ++
    "fn buffers<T:integer>(heap:allocator,n:T)->R{let mut b=acquire_buffer<A>(heap,3)?;" ++
    "_ = append_buffer<S>(b,1)?;_ = append_buffer<S>(b,2)?;" ++
    "borrow mut b[0..len_buffer(b)] as s{write_slice(s,0,cast<i64>(n));borrow s[1..2] as child{_ = read_slice(child,0);}}" ++
    "borrow b[2..2] as empty{_ = len_slice(empty);}borrow b[0..2] as shared{_ = read_buffer(b,0);}" ++
    "return new R.ok(read_buffer(b,0)+read_buffer(b,1));}";
fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "local-views.my", schema ++ functions ++
        "fn main(heap:allocator)->i64{match buffers::<u8>(heap,9u8){R.ok(n)=>{return n+arrays::<i8>(9i8);},R.err(e)=>{return e;}}}");
    defer c.deinit();
    try t.expectEqual(@as(i64, 22), (try c.execute(allocator)).value);
}
fn reject(body: []const u8, code: []const u8) !void {
    const text = try std.mem.concat(t.allocator, u8, &.{ schema, body, "fn main()->i64{return 0;}" });
    defer t.allocator.free(text);
    var c = try language.Compilation.init(t.allocator, "invalid-local-view.my", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
