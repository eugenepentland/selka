//! Lexical generic loans preserve parent suspension and restore access at scope exit.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const declarations = "fn sum<T:integer>(s:&[]T)->T{if len_slice(s)==0u64{return cast<T>(0);}let first=read_slice(s,0);" ++
    "borrow s[1..len_slice(s)] as tail{return first+sum::<T>(tail);}}" ++
    "fn fill<T:copy>(s:&mut []T,x:T)->u64{if len_slice(s)==0u64{return 0u64;}write_slice(s,0,x);let n=len_slice(s);" ++
    "borrow mut s[1..n] as tail{discard fill::<T>(tail,x);}return len_slice(s);}" ++
    "fn pair<T:integer>(a:&T,b:&T)->T{return read_ref(a)+read_ref(b);}" ++
    "fn siblings<T:integer>(x:T)->T{borrow x as r{borrow x as s{discard x;return pair::<T>(r,s);}}}" ++
    "fn local<T:copy>(x:T,y:T)->T{let mut z=x;borrow mut z as r{write_ref(r,y);}borrow z as r{discard read_ref(r);}z=y;borrow z as r{return read_ref(r);}}";
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "generic-borrow.my", declarations ++
        "fn main()->i64{let mut a=new [3]i8 [1i8,2i8,3i8];let original=a;borrow mut a[0..3] as s{discard fill::<i8>(s,4i8);}" ++
        "borrow a[0..3] as s{return cast<i64>(sum::<i8>(s))+cast<i64>(original[0])+local::<i64>(2,5)+siblings::<i64>(2);}}");
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 22), (try compilation.execute(allocator)).value);
    const generated = try compilation.emitC(allocator);
    defer allocator.free(generated);
    try t.expect(generated.len > 0);
}
// spec: GENERIC-BORROW-1
test "generic borrows recursively narrow slices and restore owners and parents" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
test "generic borrows reject permission suspension conflicts and scope escape without instantiation" {
    const cases = [_]struct { text: []const u8, code: []const u8 }{
        .{ .text = "fn f<T:copy>(x:T)->T{borrow mut x as r{return read_ref(r);}}", .code = "E_IMMUTABLE" },
        .{ .text = "fn f<T:copy>(x:&T)->T{borrow mut x as r{return read_ref(r);}}", .code = "E_REFERENCE_READ_ONLY" },
        .{ .text = "fn f<T:copy>(x:&mut T)->T{borrow x as r{return read_ref(x);}}", .code = "E_BORROW_SUSPENDED" },
        .{ .text = "fn f<T:copy>(x:T)->T{let mut z=x;borrow mut z as r{return z;}}", .code = "E_BORROW_CONFLICT" },
        .{ .text = "fn f<T:copy>(x:T)->T{let mut z=x;borrow z as r{z=x;}return z;}", .code = "E_BORROW_CONFLICT" },
        .{ .text = "fn f<T:copy>(x:T)->T{let mut z=x;borrow z as r{borrow mut z as w{return read_ref(w);}}}", .code = "E_BORROW_CONFLICT" },
        .{ .text = "fn f<T:copy>(x:&mut T)->T{borrow x as r{discard read_ref(r);}return read_ref(r);}", .code = "E_UNKNOWN_NAME" },
        .{ .text = "fn f<T:copy>(x:&[]T)->T{borrow x[false..1] as r{return read_slice(r,0);}}", .code = "E_GENERIC_OPERATION" },
        .{ .text = "fn f<T:copy>(x:T)->T{borrow x[0..1] as r{return read_slice(r,0);}}", .code = "E_GENERIC_BODY_UNSUPPORTED" },
        .{ .text = "fn f<T:copy>(x:&T)->T{borrow x as x{return read_ref(x);}}", .code = "E_SHADOWING" },
    };
    for (cases) |case| {
        var compilation = try language.Compilation.init(t.allocator, "invalid-borrow.my", case.text);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}

test "generic borrows preserve bounds traps while narrowing a concrete view" {
    var compilation = try language.Compilation.init(t.allocator, "narrow.my", "fn f<T:copy>(s:&[]T)->T{borrow s[0..2] as child{return read_slice(child,0);}}" ++
        "fn main()->i64{let a=new [1]i64 [7];borrow a[0..1] as s{return f::<i64>(s);}}");
    defer compilation.deinit();
    const result = try compilation.execute(t.allocator);
    try t.expectEqualStrings("R_SLICE_BOUNDS", result.trap.code);
    try t.expect(std.mem.startsWith(u8, compilation.src.text(result.trap.span), "borrow s"));
}
