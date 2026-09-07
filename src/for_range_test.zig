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
test "empty reversed and maximum integer ranges preserve half-open endpoints without overflow" {
    var compilation = try language.Compilation.init(t.allocator, "endpoints.my", "fn main()->i64{let mut sum=0;for i in 3..3{sum+=i;}for j in 5..2{sum+=j;}" ++
        "for k in 254u8..255u8{sum+=cast<i64>(k);continue;}" ++
        "for n in 9223372036854775806..9223372036854775807{discard n;sum+=1;}return sum;}");
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 255), (try compilation.execute(t.allocator)).value);
}
test "iteration bindings are immutable scoped and retain pending result obligations" {
    for ([_][]const u8{
        "fn main()->i64{for i in 0..3{i=8;}return 0;}",
        "fn main()->i64{for i in 0..3{discard i;}return i;}",
        "fn main()->i64{for i in 0u8..3{discard i;}return 0;}",
        "result R{ok:i64,err:i64}fn main()->i64{for i in 0..3{let value=new R.ok(i);continue;}return 0;}",
    }) |text| {
        var compilation = try language.Compilation.init(t.allocator, "invalid.my", text);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expect(compilation.program == null);
    }
}

test "range continue and break release per-iteration arenas and owned variant payloads" {
    var compilation = try language.Compilation.init(t.allocator, "cleanup.my", "buffer B:i64;result Open{ok:B,err:i64}fn main(heap:allocator)->i64{let mut total=0;" ++
        "for i in 0..5{arena heap as a{match acquire_buffer<Open>(a,0){Open.ok(b)=>{" ++
        "borrow b[0..0] as view{discard len_slice(view);total+=1;if i<2{continue;}break;}" ++
        "},Open.err(code)=>{return code;}}}}return total;}");
    defer compilation.deinit();
    var statistics: @import("memory.zig").Statistics = .{};
    const result = try compilation.executeWithOptions(t.allocator, .{ .memory = .{ .statistics = &statistics } });
    try t.expectEqual(@as(i64, 3), result.value);
    try t.expectEqual(@as(u64, 3), statistics.created);
    try t.expectEqual(statistics.created, statistics.released);
}
