//! Structured loop exits retain ownership obligations and release exited scopes.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
fn execute(text: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(t.allocator, "loops.my", text);
    defer compilation.deinit();
    const result = compilation.execute(t.allocator) catch |err| {
        @import("diagnostics_test.zig").report(compilation.diagnostics.items);
        return err;
    };
    try t.expectEqual(expected, result.value);
    const formatted = try compilation.format(t.allocator);
    defer t.allocator.free(formatted);
    var again = try language.Compilation.init(t.allocator, "formatted.my", formatted);
    defer again.deinit();
    try t.expectEqual(expected, (try again.execute(t.allocator)).value);
}
// spec: LOOP-EXIT-1
test "break and continue target nearest loops and preserve generic flow and formatting" {
    for ([_]bool{ false, true }) |generic| {
        const source = try std.mem.concat(t.allocator, u8, &.{
            if (generic) "fn work<T:copy>()->i64{" else "fn work()->i64{",
            "let mut sum=0;let mut i=0;while i<5{i+=1;if i==2{continue;}" ++
                "let mut j=0;while j<10{j+=1;if j==3{break;}sum+=i;}if i==4{break;}}return sum;}",
            if (generic) "fn main()->i64{return work::<bool>();}" else "fn main()->i64{return work();}",
        });
        defer t.allocator.free(source);
        try execute(source, 16);
    }
}
fn cleanupScenario(allocator: std.mem.Allocator) !void {
    const text = "buffer B:i64;result Open{ok:B,err:i64}result Change{ok:bool,err:i64}result R{ok:i64,err:i64}" ++
        "fn work(heap:allocator)->R{let mut sum=0;let mut i=0;while i<10{i+=1;arena heap as a{arena a as b{" ++
        "let mut values=try acquire_buffer<Open>(b,1);discard try append_buffer<Change>(values,i);" ++
        "borrow values[0..1] as view{sum+=read_slice(view,0);if i<3{continue;}break;}}}}return new R.ok(sum);}" ++
        "fn main(heap:allocator)->i64{match work(heap){R.ok(value)=>{return value;},R.err(code)=>{return code;}}}";
    for ([_]bool{ false, true }) |generic| {
        const declaration = try std.mem.replaceOwned(u8, allocator, text, "fn work(", if (generic) "fn work<T:copy>(" else "fn work(");
        defer allocator.free(declaration);
        const source = try std.mem.replaceOwned(u8, allocator, declaration, "match work(", if (generic) "match work::<bool>(" else "match work(");
        defer allocator.free(source);
        var compilation = try language.Compilation.init(allocator, "cleanup.my", source);
        defer compilation.deinit();
        const result = try compilation.executeWithOptions(allocator, .{});
        try t.expectEqual(@as(i64, 6), result.value);
    }
}
test "loop exits release nested borrows buffers and arenas under every allocation failure" {
    try cleanupScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), cleanupScenario, .{});
}
