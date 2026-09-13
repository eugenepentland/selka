//! Omitted generic arguments use the same checked substitutions as explicit calls.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const text = "fn id<T:copy>(value:T)->T{return value;}" ++
    "fn sum<T:integer>(x:T)->T{if x==cast<T>(0){return x;}return x+sum(x-cast<T>(1));}" ++
    "fn forward<U:integer>(x:U)->U{return id(sum(x));}" ++
    "fn main()->i64{let small=forward(4u8);let wide=forward(5);" ++
    "if id(true){return cast<i64>(small)+wide+sum::<i64>(2);}return 0;}";
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "inference.my", text);
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 28), (try compilation.execute(allocator)).value);
    try t.expectEqual(@as(usize, 8), compilation.program.?.functions.len);
}
// spec: GENERIC-INFERENCE-1
test "generic inferCall allocation failures preserve widths forwarding recursion and instance reuse" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
fn run(text_input: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(t.allocator, "shapes.my", text_input);
    defer compilation.deinit();
    const result = try compilation.execute(t.allocator);
    try t.expectEqual(expected, result.value);
}
test "generic inference follows arrays nominal applications const lengths and callbacks" {
    try run("fn first<T:copy,const N:u64>(x:[N]T)->T{return x[0];}" ++
        "fn forward<U:copy,const M:u64>(x:[M]U)->U{return first(x);}" ++
        "fn main()->i64{return forward(new [2]i64[7,9]);}", 7);
    try run("struct Box<T:copy>{value:T}" ++
        "fn unbox<T:copy>(x:Box<T>)->T{return x.value;}" ++
        "fn forward<U:copy>(x:Box<U>)->U{return unbox(x);}" ++
        "fn main()->i64{return forward(new Box<i64>{value:9});}", 9);
    try run("struct Chunk<T:copy,const N:u64>{items:[N]T}" ++
        "fn first<T:copy,const N:u64>(x:Chunk<T,N>)->T{return x.items[0];}" ++
        "fn forward<U:copy,const M:u64>(x:Chunk<U,M>)->U{return first(x);}" ++
        "fn main()->i64{return forward(new Chunk<i64,2>{items:new [2]i64[8,9]});}", 8);
    try run("fn inc(x:i64)->i64 effects(){return x+1;}" ++
        "fn apply<T:copy>(f:fn(T)->T effects(),x:T)->T{return f(x);}" ++
        "fn main()->i64{return apply(inc,4);}", 5);
}
const Modules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8, "module main;import helper as h;fn main()->i64{return h::first(new [2]i64[7,9]);}");
        if (std.mem.eql(u8, path, "helper.my")) return allocator.dupe(u8, "module helper;export first;fn first<T:copy,const N:u64>(x:[N]T)->T{return x[0];}");
        return error.NotFound;
    }
};
test "generic inference keeps module relocation and formatter source identity" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Modules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.emit();
    try t.expectEqual(@as(i64, 7), (try language.vm.run(t.allocator, compilation.code.?)).value);
    var source_compilation = try language.Compilation.init(t.allocator, "format.my", text);
    defer source_compilation.deinit();
    const formatted = try source_compilation.format(t.allocator);
    defer t.allocator.free(formatted);
    try run(formatted, 28);
}
