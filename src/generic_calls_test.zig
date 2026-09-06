//! Generic calls preserve requirements, nominal namespaces, and symbolic identities.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const diagnostic = @import("diagnostic.zig");
const bodies = @import("generic_bodies.zig");
const declarations = "fn identity<U:copy>(x:U)->U{return x;}fn numeric<N:integer>(x:N)->N{return x;}";
const valid = declarations ++
    "fn duo<A:integer,B:copy>(x:A,y:B)->B{discard x;return y;}fn permute<T:copy,U:integer>(x:T,y:U)->T{return duo::<U,T>(y,x);}" ++
    "fn forward<T:integer>(x:T)->T{return identity::<T>(numeric::<T>(x));}" ++
    "fn concrete<T:copy>(x:T)->i64{discard identity::<T>(x);return numeric::<i64>(3);}" ++
    "fn recurse<T:integer>(x:T)->T{if x==cast<T>(0){return x;}return recurse::<T>(x-cast<T>(1));}" ++
    "fn first<T:copy>(x:T)->T{return second::<T>(x);}fn second<U:copy>(x:U)->U{return first::<U>(x);}" ++
    "domain D:i64{private fn hidden<T:copy>(x:T)->T{return x;}fn public<U:copy>(x:U)->U{return D.hidden::<U>(x);}}" ++
    "fn main()->i64{return 0;}";
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "calls.my", valid);
    defer compilation.deinit();
    try compilation.parse();
    var sink: diagnostic.Sink = .{ .allocator = compilation.arena.allocator() };
    try bodies.check(allocator, compilation.src, compilation.syntax.?, &sink);
    try t.expectEqual(@as(usize, 0), sink.items.items.len);
}
// spec: GENERIC-CALL-1
test "generic calls forward contracts substitute types and check recursion without body expansion" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
test "generic calls reject invalid contracts identities arity and private access" {
    const cases = [_]struct { body: []const u8, code: []const u8 }{
        .{ .body = "fn f<T:copy>(x:T)->T{return numeric::<T>(x);}", .code = "E_GENERIC_ARGUMENT" },
        .{ .body = "fn f<T:copy>(x:T)->bool{discard x;return numeric::<bool>(true);}", .code = "E_GENERIC_ARGUMENT" },
        .{ .body = "fn f<T:copy,U:copy>(x:T,y:U)->U{discard y;return identity::<U>(x);}", .code = "E_GENERIC_TYPE" },
        .{ .body = "fn f<T:copy>(x:T)->T{return identity(x);}", .code = "E_GENERIC_ARITY" },
        .{ .body = "fn f<T:copy>(x:T)->T{return identity::<T,T>(x);}", .code = "E_GENERIC_ARITY" },
        .{ .body = "fn f<T:copy>(x:T)->T{return identity::<T>(x,x);}", .code = "E_ARITY" },
        .{ .body = "fn f<T:copy>(x:T)->T{return missing::<T>(x);}", .code = "E_UNKNOWN_FUNCTION" },
        .{ .body = "domain D:i64{private fn hidden<T:copy>(x:T)->T{return x;}}domain E:i64{fn f<T:copy>(x:T)->T{return D.hidden::<T>(x);}}", .code = "E_PRIVATE_FUNCTION" },
        .{ .body = "fn ordinary(x:i64)->i64{return x;}fn f<T:copy>(x:T)->i64{discard x;return ordinary(1);}", .code = "E_GENERIC_BODY_UNSUPPORTED" },
        .{ .body = "domain D:i64{private fn hidden<T:copy>(x:T)->T{return x;}}fn f<T:copy>(x:T)->T{return D.hidden::<T>(x);}", .code = "E_PRIVATE_FUNCTION" },
    };
    for (cases) |case| {
        const text = try std.mem.concat(t.allocator, u8, &.{ declarations, case.body, "fn main()->i64{return 0;}" });
        defer t.allocator.free(text);
        var compilation = try language.Compilation.init(t.allocator, "bad.my", text);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}
