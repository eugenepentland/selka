//! Half-open integer iteration reuses scoped loop exits and evaluates bounds once.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
fn scenario(allocator: std.mem.Allocator) !void {
    const text = "fn bound(counter:&mut i64,value:i64)->i64{write_ref(counter,read_ref(counter)+1);return value;}" ++
        "fn sum_range<T:integer>(start:T,end:T)->i64{let mut sum=0;for i in start..end{" ++
        "if i==cast<T>(2){continue;}for j in 0..3{if j==1{break;}sum+=cast<i64>(i);}}return sum;}" ++
        "fn main()->i64{let mut calls=0;let mut result=0;borrow mut calls as count{" ++
        "for i in bound(count,0)..bound(count,4){result+=i;}}" ++
        "return result+sum_range::<u8>(0u8,5u8)+calls;}";
    var compilation = try language.Compilation.init(allocator, "for.my", text);
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 16), (try compilation.execute(allocator)).value);
    const formatted = try compilation.format(allocator);
    defer allocator.free(formatted);
    var again = try language.Compilation.init(allocator, "formatted.my", formatted);
    defer again.deinit();
    try t.expectEqual(@as(i64, 16), (try again.execute(allocator)).value);
}
// spec: FOR-RANGE-1
test "half-open ranges evaluate bounds once and support generic nested exits with allocation failures" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
