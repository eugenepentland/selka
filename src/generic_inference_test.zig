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
    const generated = try compilation.emitC(allocator);
    defer allocator.free(generated);
    try t.expect(generated.len > 0);
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
test "generic inference rejects ambiguity conflicts weakened requirements and partial arguments" {
    const cases = [_]struct { text: []const u8, code: []const u8 }{
        .{ .text = "fn f<T:copy>()->i64{return 0;}fn main()->i64{return f();}", .code = "E_GENERIC_INFERENCE" },
        .{ .text = "fn f<T:copy>(a:T,b:T)->T{discard b;return a;}fn main()->i64{return f(1,true);}", .code = "E_GENERIC_INFERENCE" },
        .{ .text = "fn f<T:integer>(x:T)->T{return x;}fn main()->i64{discard f(true);return 0;}", .code = "E_GENERIC_ARGUMENT" },
        .{ .text = "fn f<T:integer>(x:T)->T{return x;}fn g<U:copy>(x:U)->U{return f(x);}", .code = "E_GENERIC_ARGUMENT" },
        .{ .text = "fn f<T:copy>(a:T,b:T)->T{discard b;return a;}fn g<A:copy,B:copy>(a:A,b:B)->A{return f(a,b);}", .code = "E_GENERIC_INFERENCE" },
        .{ .text = "fn f<T:copy>(x:&mut T)->T{return read_ref(x);}fn g<U:copy>(x:&U)->U{return f(x);}", .code = "E_REFERENCE_READ_ONLY" },
        .{ .text = "fn f<T:copy>(a:&mut T,b:&T)->T{discard read_ref(a);return read_ref(b);}fn g<U:copy>(x:&mut U)->U{return f(x,x);}", .code = "E_BORROW_CONFLICT" },
        .{ .text = "fn f<T:storable>(a:T,b:T)->T{discard b;return a;}buffer B:u8;fn g(x:B)->B{return f(x,x);}fn main()->i64{return 0;}", .code = "E_OWNED_CONSUMED" },
        .{ .text = "result Time{ok:i64,err:i64}fn f<T:copy>(x:T,c:clock_cap)->T{acknowledge clock_now<Time>(c);return x;}fn g<U:copy>(x:U,c:clock_cap)->U effects(){return f(x,c);}", .code = "E_EFFECT_BOUND" },
        .{ .text = "fn f<T:copy,U:copy>(a:T,b:U)->T{discard b;return a;}fn main()->i64{return f::<i64>(1,true);}", .code = "E_GENERIC_ARITY" },
        .{ .text = "fn f<T:copy,const N:u64>(a:[N]T,b:[N]T)->T{discard b;return a[0];}fn main()->i64{return f(new [1]i64[1],new [2]i64[1,2]);}", .code = "E_GENERIC_INFERENCE" },
    };
    for (cases) |case| {
        var compilation = try language.Compilation.init(t.allocator, "rejected.my", case.text);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}

test "generic inference keeps reference permissions effects and owned argument transfer" {
    try run("fn get<T:copy>(x:&T)->T{return read_ref(x);}" ++
        "fn set<T:copy>(x:&mut T,y:T)->T{write_ref(x,y);return get(x);}" ++
        "fn forward<U:copy>(x:&mut U,y:U)->U{return set(x,y);}" ++
        "fn main()->i64{let mut x=0;borrow mut x as r{discard forward(r,7);}return x;}", 7);
    try run("buffer B:u8;result A{ok:B,err:i64}" ++
        "fn move<T:storable>(x:T)->T{return x;}" ++
        "fn forward<U:storable>(x:U)->U{return move(x);}" ++
        "fn main(heap:allocator)->i64{match acquire_buffer<A>(heap,0){A.ok(b)=>{discard forward(b);return 9;},A.err(e)=>{return e;}}}", 9);
    try run("fn next(x:&mut i64)->i64{let y=read_ref(x)+1;write_ref(x,y);return y;}" ++
        "fn pair<T:integer>(a:T,b:T)->T{return a*cast<T>(10)+b;}" ++
        "fn main()->i64{let mut x=0;borrow mut x as r{return pair(next(r),next(r));}}", 12);
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
