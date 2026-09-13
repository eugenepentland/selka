//! Immutable scalar constants are checked and folded before executable publication.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
fn scenario(allocator: std.mem.Allocator) !void {
    const text = "const ANSWER:i64=BASE*2;const BASE:i64=21;const MIN:i64=-9223372036854775808;" ++
        "const SAFE:bool=false&&(1/0==1);const WIDTH:u8=cast<u8>(BASE);" ++
        "fn work<T:copy>()->i64{if SAFE{return MIN;}return ANSWER+cast<i64>(WIDTH);}" ++
        "fn main()->i64{return work::<bool>();}";
    var compilation = try language.Compilation.init(allocator, "constants.my", text);
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 63), (try compilation.execute(allocator)).value);
    const formatted = try compilation.format(allocator);
    defer allocator.free(formatted);
    var again = try language.Compilation.init(allocator, "formatted.my", formatted);
    defer again.deinit();
    try t.expectEqual(@as(i64, 63), (try again.execute(allocator)).value);
}
// spec: CONSTANT-1
test "scalar constants support forward dependencies checked widths short circuit and generic uses under allocation failure" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
fn provider(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
    const text = if (std.mem.eql(u8, path, "main.my"))
        "module main;import constants;fn main()->i64{return constants::VALUE;}"
    else if (std.mem.eql(u8, path, "constants.my"))
        "module constants;export VALUE;const VALUE:i64=FACTOR*6;const FACTOR:i64=7;"
    else
        return error.NotFound;
    return allocator.dupe(u8, text);
}
test "exported constants retain module identity and private initializer dependencies" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = provider });
    defer program.deinit();
    try t.expectEqual(@as(i64, 42), (try language.vm.run(t.allocator, program.compilation.code.?)).value);
}
