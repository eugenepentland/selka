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
const helpers = "fn leaf(x:i64)->i64{return numeric::<i64>(x);}" ++
    "fn middle(x:i64)->i64{return leaf(x)+leaf(x);}" ++
    "fn even(x:i64)->bool{if x==0{return true;}return odd(x-1);}" ++
    "fn odd(x:i64)->bool{if x==0{return false;}return even(x-1);}" ++
    "fn generic<T:copy>(x:T)->i64{discard x;if even(4){return middle(3);}return leaf(2);}" ++
    "fn unused(c:clock_cap)->i64{acknowledge clock_now<Time>(c);return 0;}";
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
