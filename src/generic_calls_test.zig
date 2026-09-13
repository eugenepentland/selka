//! Generic calls preserve requirements, nominal namespaces, and symbolic identities.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const diagnostic = @import("diagnostic.zig");
const bodies = @import("generic_bodies.zig");
const declarations = "fn identity<U:copy>(x:U)->U{return x;}fn numeric<N:integer>(x:N)->N{return x;}";
const valid = declarations ++
    "fn duo<A:integer,B:copy>(x:A,y:B)->B{_ = x;return y;}fn permute<T:copy,U:integer>(x:T,y:U)->T{return duo::<U,T>(y,x);}" ++
    "fn forward<T:integer>(x:T)->T{return identity::<T>(numeric::<T>(x));}" ++
    "fn concrete<T:copy>(x:T)->i64{_ = identity::<T>(x);return numeric::<i64>(3);}" ++
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
const helpers = "fn leaf(x:i64)->i64{return numeric::<i64>(x);}" ++
    "fn middle(x:i64)->i64{return leaf(x)+leaf(x);}" ++
    "fn even(x:i64)->bool{if x==0{return true;}return odd(x-1);}" ++
    "fn odd(x:i64)->bool{if x==0{return false;}return even(x-1);}" ++
    "fn generic<T:copy>(x:T)->i64{_ = x;if even(4){return middle(3);}return leaf(2);}" ++
    "fn unused(c:clock_cap)->i64{_ = clock_now<Time>(c);return 0;}";
fn helperScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "helpers.my", declarations ++ helpers);
    defer compilation.deinit();
    try compilation.parse();
    var sink: diagnostic.Sink = .{ .allocator = compilation.arena.allocator() };
    try bodies.check(allocator, compilation.src, compilation.syntax.?, &sink);
    try t.expectEqual(@as(usize, 0), sink.items.items.len);
}
// spec: GENERIC-HELPER-1
test "generic calls check reachable concrete helpers transitively without expanding recursion" {
    try helperScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), helperScenario, .{});
}

test "generic calls reject invalid contracts identities arity and private access" {
    const cases = [_]struct { body: []const u8, code: []const u8 }{
        .{ .body = "fn f<T:copy>(x:T)->T{return numeric::<T>(x);}", .code = "E_GENERIC_ARGUMENT" },
        .{ .body = "fn f<T:copy>(x:T)->bool{_ = x;return numeric::<bool>(true);}", .code = "E_GENERIC_ARGUMENT" },
        .{ .body = "fn f<T:copy,U:copy>(x:T,y:U)->U{_ = y;return identity::<U>(x);}", .code = "E_GENERIC_TYPE" },
        .{ .body = "fn f<T:copy>(x:T)->T{return identity::<T,T>(x);}", .code = "E_GENERIC_ARITY" },
        .{ .body = "fn f<T:copy>(x:T)->T{return identity::<T>(x,x);}", .code = "E_ARITY" },
        .{ .body = "fn f<T:copy>(x:T)->T{return missing::<T>(x);}", .code = "E_UNKNOWN_FUNCTION" },
        .{ .body = "domain D:i64{private fn hidden<T:copy>(x:T)->T{return x;}}domain E:i64{fn f<T:copy>(x:T)->T{return D.hidden::<T>(x);}}", .code = "E_PRIVATE_FUNCTION" },

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

test "generic calls reject hidden effects and invalid concrete helper bodies" {
    const cases = [_]struct { body: []const u8, code: []const u8 }{
        .{ .body = "fn helper(x:i64)->i64{return true;}", .code = "E_GENERIC_TYPE" },
        .{ .body = "fn helper(x:i64)->i64{if x==0{return 0;}}", .code = "E_MISSING_RETURN" },
        .{ .body = "fn helper(x:bool)->i64{_ = x;return 0;}", .code = "E_GENERIC_TYPE" },
        .{ .body = "fn helper<T:copy,U:copy>(x:T)->T{return x;}", .code = "E_GENERIC_INFERENCE" },
    };
    for (cases) |case| {
        const text = try std.mem.concat(t.allocator, u8, &.{ case.body, "fn f<T:copy>(x:T)->i64{_ = x;return helper(1);}" });
        defer t.allocator.free(text);
        var compilation = try language.Compilation.init(t.allocator, "invalid-helper.my", text);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}

test "generic calls reject reachable clock effects even behind cycles and false branches" {
    const effectful = "result Time{ok:i64,err:i64}" ++
        "fn helper(c:clock_cap)->i64{return hidden(c);}" ++
        "fn hidden(c:clock_cap)->i64{if false{_ = clock_now<Time>(c);return helper(c);}return 0;}";
    var ordinary = try language.Compilation.init(t.allocator, "ordinary.my", effectful ++ "fn main(c:clock_cap)->i64{return helper(c);}");
    defer ordinary.deinit();
    try ordinary.check();
    var generic = try language.Compilation.init(t.allocator, "generic.my", effectful ++ "fn f<T:copy>(x:T,c:clock_cap)->i64 effects(){_ = x;return helper(c);}fn main()->i64{return 0;}");
    defer generic.deinit();
    try t.expectError(error.SourceError, generic.check());
    try t.expectEqualStrings("E_EFFECT_BOUND", generic.diagnostics.items[0].code);
    try t.expectEqualStrings("effects()", generic.src.text(generic.diagnostics.items[0].span));
}
