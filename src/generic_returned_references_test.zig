//! Generic reference results retain their declared input and concrete callee types.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const declarations = "fn same<T:copy>(x:&T)->&T from x{return x;}" ++
    "fn tail<T:copy>(s:&mut []T)->&mut []T from s{borrow mut s[1..len_slice(s)] as rest{return rest;}}" ++
    "fn forward<U:copy>(s:&mut []U)->&mut []U from s{borrow mut tail::<U>(s) as rest{return rest;}}" ++
    "fn second<A:copy,B:copy>(a:&A,b:&B)->&B from b{discard read_ref(a);return b;}" ++
    "fn choose<U:copy,V:copy>(x:&V,y:&U)->&U from y{borrow second::<V,U>(x,y) as selected{return selected;}}" ++
    "fn read<T:copy>(x:&T)->T{borrow same::<T>(x) as y{return read_ref(y);}}";
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "returned.my", declarations ++
        "fn main()->i64{let mut a=new [3]i8 [1i8,2i8,3i8];let old=a;borrow mut a[0..3] as s{borrow mut forward::<i8>(s) as rest{write_slice(rest,0,9i8);}write_slice(s,0,4i8);}" ++
        "let b=7;let flag=true;borrow flag as f{borrow b as r{borrow choose::<i64,bool>(f,r) as selected{return read::<i64>(selected)+cast<i64>(a[0])+cast<i64>(a[1])+cast<i64>(old[1]);}}}}");
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 22), (try compilation.execute(allocator)).value);
    const generated = try compilation.emitC(allocator);
    defer allocator.free(generated);
    try t.expect(generated.len > 0);
}
// spec: GENERIC-RETURN-1
test "generic returned references execute forwarded specialized views and restore parent access" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
test "generic returned references reject invalid provenance permissions and value escape" {
    const cases = [_]struct { text: []const u8, code: []const u8 }{
        .{ .text = "fn f<T:copy>(x:&T,y:&T)->&T from x{return y;}", .code = "E_RETURN_LIFETIME" },
        .{ .text = "fn f<T:copy>(x:&T)->&T from x{let y=read_ref(x);borrow y as r{return r;}}", .code = "E_RETURN_LIFETIME" },
        .{ .text = "fn f<T:copy>(x:T)->&T from x{borrow x as r{return r;}}", .code = "E_RETURN_LIFETIME" },
        .{ .text = "fn f<T:copy>(x:&T)->&T from missing{return x;}", .code = "E_RETURN_LIFETIME" },
        .{ .text = "fn f<T:copy>(x:&T)->&mut T from x{return x;}", .code = "E_REFERENCE_READ_ONLY" },
        .{ .text = "fn f<T:copy,U:copy>(x:&T)->&U from x{return x;}", .code = "E_GENERIC_TYPE" },
        .{ .text = "fn f<T:copy>(x:&T)->&T from x{return read_ref(x);}", .code = "E_REFERENCE_RESULT" },
        .{ .text = "fn f<T:copy>(x:&T)->T{return same::<T>(x);}", .code = "E_REFERENCE_RESULT" },
        .{ .text = "fn f<T:copy>(x:&T)->T{borrow mut same::<T>(x) as r{return read_ref(r);}}", .code = "E_REFERENCE_READ_ONLY" },
        .{ .text = "fn f<T:copy>(x:&mut []T)->u64{borrow mut tail::<T>(x) as r{return len_slice(x);}}", .code = "E_BORROW_SUSPENDED" },
        .{ .text = "fn f<T:copy>(x:&[]T)->&T from x{return x;}", .code = "E_REFERENCE_KIND" },
        .{ .text = "fn f<T:copy>(x:&T)->&[]T from x{return x;}", .code = "E_GENERIC_BODY_UNSUPPORTED" },
    };
    for (cases) |case| {
        const text = try std.mem.concat(t.allocator, u8, &.{ declarations, case.text });
        defer t.allocator.free(text);
        var compilation = try language.Compilation.init(t.allocator, "invalid-return.my", text);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}
