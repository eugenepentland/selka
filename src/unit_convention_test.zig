//! A reusable no-payload value composes with checked generic results.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
fn provider(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
    if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
    return allocator.dupe(u8, "module main;import std_unit;import std_result;" ++
        "fn done()->std_unit::Unit noalloc{return std_unit::unit();}" ++
        "fn identity<T:copy>(value:T)->T{return value;}" ++
        "fn operation()->std_result::Result<std_unit::Unit,std_result::Error>{" ++
        "return new std_result::Result<std_unit::Unit,std_result::Error>.ok(done());}" ++
        "fn main()->i64{discard identity::<std_unit::Unit>(done());" ++
        "match operation(){std_result::Result<std_unit::Unit,std_result::Error>.ok(discard)=>{return 0;}," ++
        "std_result::Result<std_unit::Unit,std_result::Error>.err(discard)=>{return 1;}}}");
}
// spec: UNIT-CONVENTION-1
test "standard Unit replaces dummy success integers and composes with generic fallible values" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = provider });
    defer program.deinit();
    const result = try language.vm.run(t.allocator, program.compilation.code.?);
    try t.expectEqual(@as(i64, 0), result.value);
}
