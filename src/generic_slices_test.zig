//! Slice abstraction retains kind, element identity, mutation permissions and concrete bounds.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const declarations = "fn fill<T:copy>(s:&mut []T,x:T)->u64{let mut i=0u64;while i<len_slice(s){write_slice(s,i,x);i+=1u64;}return i;}" ++
    "fn first<T:copy>(s:&[]T)->T{return read_slice(s,0u64);}" ++
    "fn forward<T:copy>(s:&mut []T,x:T)->T{discard fill::<T>(s,x);return first::<T>(s);}" ++
    "fn sum<T:integer>(s:&[]T)->T{let mut total=cast<T>(0);let mut i=0u64;while i<len_slice(s){total+=read_slice(s,i);i+=1u64;}return total;}";
const example = declarations ++ "fn main()->i64{let mut a=new [3]i8 [2i8,3i8,5i8];let original=a;let mut flags=new [1]bool [false];" ++
    "borrow mut flags[0..1] as s{discard forward::<bool>(s,true);}borrow mut a[1..3] as s{discard forward::<i8>(s,4i8);}" ++
    "borrow mut a[3..3] as empty{discard fill::<i8>(empty,0i8);}if flags[0]{borrow a[0..3] as s{return cast<i64>(sum::<i8>(s))+cast<i64>(original[1]);}}return 0;}";
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "generic-slice.my", example);
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 13), (try compilation.execute(allocator)).value);
    const generated = try compilation.emitC(allocator);
    defer allocator.free(generated);
    try t.expect(generated.len > 0);
}
// spec: GENERIC-SLICE-1
test "generic slices execute mutation forwarding multiple element types and empty views" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
test "generic slices reject kind permission index and element errors in uncalled templates" {
    const cases = [_]struct { text: []const u8, code: []const u8 }{
        .{ .text = "fn f<T:copy>(s:&[]T)->T{return read_ref(s);}", .code = "E_REFERENCE_KIND" },
        .{ .text = "fn f<T:copy>(s:&T)->T{return read_slice(s,0);}", .code = "E_REFERENCE_KIND" },
        .{ .text = "fn f<T:copy>(s:&T)->u64{return len_slice(s);}", .code = "E_REFERENCE_KIND" },
        .{ .text = "fn f<T:copy>(s:&[]T,x:T)->u64{write_slice(s,0,x);return 0u64;}", .code = "E_REFERENCE_READ_ONLY" },
        .{ .text = "fn f<T:copy,U:copy>(s:&mut []T,x:U)->u64{write_slice(s,0,x);return 0u64;}", .code = "E_GENERIC_TYPE" },
        .{ .text = "fn f<T:copy>(s:&[]T)->T{return read_slice(s,true);}", .code = "E_GENERIC_OPERATION" },
        .{ .text = "fn f<T:copy,I:copy>(s:&[]T,i:I)->T{return read_slice(s,i);}", .code = "E_GENERIC_OPERATION" },
        .{ .text = "fn f<T:copy>(s:&T)->T{return first::<T>(s);}", .code = "E_REFERENCE_KIND" },
        .{ .text = "fn f<T:copy>(s:&[]T,x:T)->T{return forward::<T>(s,x);}", .code = "E_REFERENCE_READ_ONLY" },
        .{ .text = "fn pair<T:copy>(x:&[]T,y:&[]T)->T{discard first::<T>(x);return first::<T>(y);}fn f<T:copy>(s:&mut []T)->T{return pair::<T>(s,s);}", .code = "E_BORROW_CONFLICT" },
    };
    for (cases) |case| {
        const text = try std.mem.concat(t.allocator, u8, &.{ declarations, case.text });
        defer t.allocator.free(text);
        var compilation = try language.Compilation.init(t.allocator, "invalid-slice.my", text);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}
test "generic slices preserve located traps for signed and full-width indices" {
    const cases = [_]struct { ty: []const u8, index: []const u8 }{
        .{ .ty = "i8", .index = "-1i8" }, .{ .ty = "i64", .index = "1" }, .{ .ty = "u64", .index = "18446744073709551615u64" },
    };
    for (cases) |case| {
        const text = try std.fmt.allocPrint(t.allocator, "fn at<T:copy,I:integer>(s:&[]T,i:I)->T{{return read_slice(s,i);}}" ++
            "fn main()->i64{{let a=new [1]i64 [7];borrow a[0..1] as s{{return at::<i64,{s}>(s,{s});}}}}", .{ case.ty, case.index });
        defer t.allocator.free(text);
        var compilation = try language.Compilation.init(t.allocator, "bounds.my", text);
        defer compilation.deinit();
        const result = try compilation.execute(t.allocator);
        try t.expectEqualStrings("R_SLICE_BOUNDS", result.trap.code);
        try t.expectEqualStrings("read_slice(s,i)", compilation.src.text(result.trap.span));
    }
}
