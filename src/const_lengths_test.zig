//! Constant generic lengths preserve shape identity and runtime integer values.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
test "const length function parameters specialize array shapes and forward values" {
    const text = "fn first<T:copy,const N:u64>(items:[N]T)->T{return items[0];}" ++
        "fn size<const N:u64>()->u64{return N;}" ++
        "fn forward<T:copy,const N:u64>(items:[N]T)->T{return first::<T,N>(items);}" ++
        "fn main()->i64{return forward::<i64,2>(new [2]i64[40,0])+cast<i64>(size::<2>());}";
    var c = try language.Compilation.init(t.allocator, "lengths.my", text);
    defer c.deinit();
    try t.expectEqual(@as(i64, 42), (try c.execute(t.allocator)).value);
}
fn nominalScenario(allocator: std.mem.Allocator) !void {
    const text = "struct Chunk<T:copy,const N:u64>{items:[N]T}" ++
        "fn make<T:copy,const N:u64>(items:[N]T)->Chunk<T,N>{return new Chunk<T,N>{items:items};}" ++
        "fn first<T:copy,const N:u64>(chunk:Chunk<T,N>)->T{return chunk.items[0];}" ++
        "fn main()->i64{let a=make::<i64,2>(new [2]i64[40,0]);let b=make::<i64,3>(new [3]i64[2,0,0]);return first::<i64,2>(a)+first::<i64,3>(b);}";
    var c = try language.Compilation.init(allocator, "lengths.my", text);
    defer c.deinit();
    try t.expectEqual(@as(i64, 42), (try c.execute(allocator)).value);
    const formatted = try c.format(allocator);
    defer allocator.free(formatted);
    var again = try language.Compilation.init(allocator, "formatted.my", formatted);
    defer again.deinit();
    try t.expectEqual(@as(i64, 42), (try again.execute(allocator)).value);
}
// spec: CONST-LENGTH-1
test "const length nominal parameters compose arrays and clean allocation failures" {
    try nominalScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), nominalScenario, .{});
}
test "uncalled const length templates reject kind confusion unprovable construction and missing requirements" {
    const cases = [_]struct { source: []const u8, code: []const u8 }{
        .{ .source = "fn bad<const N:u64>(x:N)->i64{return 0;}", .code = "E_GENERIC_LENGTH" },
        .{ .source = "struct Bad<const N:u64>{x:N}", .code = "E_GENERIC_LENGTH" },
        .{ .source = "fn bad<const N:u64>()->[N]i64{return new [N]i64[];}", .code = "E_GENERIC_LENGTH" },
        .{ .source = "fn bad<T:copy,const N:u64>(items:[N]T)->i64{return items[0]+1;}", .code = "E_GENERIC_TYPE" },
        .{ .source = "fn bad<const N:u64>()->u64{let N=1u64;return N;}", .code = "E_SHADOWING" },
        .{ .source = "struct Bad<T:copy>{x:[T]i64}", .code = "E_GENERIC_ARRAY_KEY" },
        .{ .source = "struct Chunk<const N:u64>{x:[N]i64}struct Bad{x:Chunk<1048577>}", .code = "E_GENERIC_LENGTH" },
    };
    for (cases) |case| {
        const text = try std.fmt.allocPrint(t.allocator, "{s}fn main()->i64{{return 0;}}", .{case.source});
        defer t.allocator.free(text);
        var c = try language.Compilation.init(t.allocator, "invalid.my", text);
        defer c.deinit();
        try t.expectError(error.SourceError, c.check());
        try t.expectEqualStrings(case.code, c.diagnostics.items[0].code);
    }
}

test "one helper serves distinct nominal element types and empty lengths" {
    const text = "struct A{value:i64}struct B{value:i64}" ++
        "fn first<T:copy,const N:u64>(items:[N]T)->T{return items[0];}" ++
        "fn count<T:copy,const N:u64>(items:[N]T)->u64{return N;}" ++
        "fn main()->i64{let a=first::<A,2>(new [2]A[new A{value:40},new A{value:0}]);" ++
        "let b=first::<B,1>(new [1]B[new B{value:2}]);return a.value+b.value+cast<i64>(count::<A,0>(new [0]A[]));}";
    var c = try language.Compilation.init(t.allocator, "nominals.my", text);
    defer c.deinit();
    try t.expectEqual(@as(i64, 42), (try c.execute(t.allocator)).value);
}
test "constant specialization identity owns lengths and distinguishes equal scalar representations" {
    const instances = @import("generic_instances.zig");
    var registry: instances.Registry = .{};
    defer registry.deinit(t.allocator);
    var lengths = [_]?usize{2};
    const first = try registry.intern(t.allocator, .{ .declaration = @fromBackingInt(0), .arguments = &.{.u64}, .lengths = &lengths });
    lengths[0] = 3;
    const second = try registry.intern(t.allocator, .{ .declaration = @fromBackingInt(0), .arguments = &.{.u64}, .lengths = &lengths });
    const repeated = try registry.intern(t.allocator, .{ .declaration = @fromBackingInt(0), .arguments = &.{.u64}, .lengths = &.{2} });
    try t.expect(first != second);
    try t.expectEqual(first, repeated);
    try t.expectEqual(@as(?usize, 2), (try registry.get(first)).length(0));
}
fn provider(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
    if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8, "module main;import shapes as s;fn main()->i64{let chunk=s::make::<i64,2>(new [2]i64[42,0]);return chunk.items[0];}");
    if (std.mem.eql(u8, path, "shapes.my")) return allocator.dupe(u8, "module shapes;export Chunk;export make;struct Chunk<T:copy,const N:u64>{items:[N]T}" ++
        "fn make<T:copy,const N:u64>(items:[N]T)->Chunk<T,N>{return new Chunk<T,N>{items:items};}");
    return error.NotFound;
}
test "exported constant length constructors retain kind through source relocation" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = provider });
    defer program.deinit();
    try t.expectEqual(@as(i64, 42), (try language.vm.run(t.allocator, program.compilation.code.?)).value);
}
