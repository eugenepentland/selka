//! Generic reference inputs preserve symbolic types, access permissions and alias rules.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const source_text = "fn get<T:copy>(x:&T)->T{return read_ref(x);}" ++
    "fn set<T:copy>(x:&mut T,y:T)->T{write_ref(x,y);return get::<T>(x);}" ++
    "fn sum<T:integer>(a:&T,b:&T)->T{return read_ref(a)+read_ref(b);}" ++
    "fn double<T:integer>(x:&T)->T{return sum::<T>(x,x);}" ++
    "fn forward<U:integer>(x:&mut U,y:U)->U{discard set::<U>(x,y);return get::<U>(x);}" ++
    "fn main()->i64{let mut x=1i8;let mut y=2;let mut flag=false;borrow mut flag as f{discard set::<bool>(f,true);}" ++
    "borrow mut x as r{discard forward::<i8>(r,7i8);}borrow mut y as r{discard set::<i64>(r,9);}borrow x as r{discard double::<i8>(r);}if flag{return cast<i64>(x)+y;}return 0;}";
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "generic-reference.my", source_text);
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 16), (try compilation.execute(allocator)).value);
}
// spec: GENERIC-REFERENCE-1
test "generic references execute shared reads exclusive writes and forwarding across instances" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
test "generic references reject permission type and alias errors in uncalled templates" {
    const cases = [_]struct { source: []const u8, code: []const u8 }{
        .{ .source = "fn f<T:copy>(x:&T,y:T)->T{write_ref(x,y);return y;}", .code = "E_REFERENCE_READ_ONLY" },
        .{ .source = "fn f<T:copy>(x:T)->T{return read_ref(x);}", .code = "E_REFERENCE_SCOPE" },
        .{ .source = "fn f<T:copy>(x:&T)->T{return x;}", .code = "E_REFERENCE_VALUE" },
        .{ .source = "fn f<T:copy,U:copy>(x:&mut T,y:U)->T{write_ref(x,y);return read_ref(x);}", .code = "E_GENERIC_TYPE" },
        .{ .source = "fn helper<T:copy>(x:&mut T)->T{return read_ref(x);}fn f<T:copy>(x:&T)->T{return helper::<T>(x);}", .code = "E_REFERENCE_READ_ONLY" },
        .{ .source = "fn helper<T:copy>(x:&T)->T{return read_ref(x);}fn f<T:copy>(x:T)->T{return helper::<T>(x);}", .code = "E_REFERENCE_SCOPE" },
        .{ .source = "fn helper<T:integer>(x:&T)->T{return read_ref(x);}fn f<T:integer>(x:T)->T{return helper::<T>(x+x);}", .code = "E_REFERENCE_ARGUMENT" },
        .{ .source = "fn helper<T:copy>(x:T)->T{return x;}fn f<T:copy>(x:&T)->T{return helper::<T>(x);}", .code = "E_REFERENCE_VALUE" },
        .{ .source = "fn helper<T:copy>(x:&T,y:&mut T)->T{discard read_ref(x);return read_ref(y);}fn f<T:copy>(x:&mut T)->T{return helper::<T>(x,x);}", .code = "E_BORROW_CONFLICT" },
        .{ .source = "fn helper<T:copy>(x:&mut T,y:&T)->T{discard read_ref(x);return read_ref(y);}fn f<T:copy>(x:&mut T)->T{return helper::<T>(x,x);}", .code = "E_BORROW_CONFLICT" },
        .{ .source = "fn helper<T:copy>(x:&T,y:&T)->T{discard read_ref(x);return read_ref(y);}fn f<T:copy>(x:&mut T)->T{return helper::<T>(x,x);}", .code = "E_BORROW_CONFLICT" },
    };
    for (cases) |case| {
        var compilation = try language.Compilation.init(t.allocator, "invalid-reference.my", case.source);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}
