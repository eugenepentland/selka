//! Holes are explicit typed obligations, never executable placeholders.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const source = "fn first()->i64{return todo<i64>();}fn second<T:copy>(x:T)->T{_ = x;return todo<T>();}fn main()->i64{return 0;}";
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "holes.my", source);
    defer compilation.deinit();
    compilation.check() catch |err| switch (err) {
        error.SourceError => {},
        else => return err,
    };
    try t.expectEqual(@as(usize, 2), compilation.diagnostics.items.len);
    for (compilation.diagnostics.items) |item| {
        try t.expectEqualStrings("E_TYPED_HOLE", item.code);
        try t.expectEqualStrings("todo", compilation.src.text(item.span));
        try t.expect(item.related != null);
    }
    try t.expectError(error.SourceError, compilation.execute(allocator));
    try t.expect(compilation.program == null);
}
// spec: TYPED-HOLES-1
test "typed implementation obligations report independent generic and ordinary holes under allocation failure" {
    try scenario(t.allocator);
    try t.checkAllAllocationFailures(t.allocator, scenario, .{});
}
test "formatting retains typed holes and filling them restores executable checking" {
    var c = try language.Compilation.init(t.allocator, "holes.my", source);
    defer c.deinit();
    const formatted = try c.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expect(std.mem.indexOf(u8, formatted, "todo<i64>()") != null);
    var repaired = try language.Compilation.init(t.allocator, "fixed.my", "fn main()->i64{return 7;}");
    defer repaired.deinit();
    try t.expectEqual(@as(i64, 7), (try repaired.execute(t.allocator)).value);
}
