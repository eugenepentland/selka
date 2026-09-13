//! Value-producing matches reuse exhaustive pattern and ownership checks.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
fn scenario(allocator: std.mem.Allocator) !void {
    const text = "result Choice<T:copy>{ok:T,err:i64}enum Flag{yes,no}" ++
        "fn select<T:integer>(value:Choice<T>)->T{return match value{" ++
        "Choice<T>.ok(x)=>x,Choice<T>.err(code)=>cast<T>(code)};}" ++
        "fn main()->i64{let value=match new Flag.yes{Flag.yes=>new Choice<i64>.ok(42),Flag.no=>new Choice<i64>.err(1)};" ++
        "return 1+select::<i64>(value);}";
    var compilation = try language.Compilation.init(allocator, "matches.my", text);
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 43), (try compilation.execute(allocator)).value);
    const formatted = try compilation.format(allocator);
    defer allocator.free(formatted);
    var again = try language.Compilation.init(allocator, "formatted.my", formatted);
    defer again.deinit();
    try t.expectEqual(@as(i64, 43), (try again.execute(allocator)).value);
}
// spec: MATCH-VALUE-1
test "match expressions yield common typed values in generic calls and formatted nested contexts under allocation failure" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
