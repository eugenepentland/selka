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
test "continue inside a child borrow preserves the outer borrowed loop condition" {
    try execute("fn main()->i64{let mut owner=0;borrow mut owner as outer{while read_ref(outer)<3{" ++
        "write_ref(outer,read_ref(outer)+1);borrow outer as inner{discard read_ref(inner);continue;}}}return owner;}", 3);
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
        var statistics: @import("memory.zig").Statistics = .{};
        const result = try compilation.executeWithOptions(allocator, .{ .memory = .{ .statistics = &statistics } });
        try t.expectEqual(@as(i64, 6), result.value);
        try t.expectEqual(@as(u64, 3), statistics.created);
        try t.expectEqual(statistics.created, statistics.released);
        try t.expectEqual(@as(usize, 0), statistics.live_allocations);
    }
}
test "loop exits release nested borrows buffers and arenas under every allocation failure" {
    try cleanupScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), cleanupScenario, .{});
}
test "loop exits reject out of scope exits unhandled results and changed outer ownership" {
    const cases = [_]struct { text: []const u8, code: []const u8 }{
        .{ .text = "fn main()->i64{break;}", .code = "E_LOOP_EXIT" },
        .{ .text = "fn main()->i64{continue;}", .code = "E_LOOP_EXIT" },
        .{ .text = "result R{ok:i64,err:i64}fn main()->i64{while true{let value=new R.ok(1);break;}return 0;}", .code = "E_RESULT_UNHANDLED" },
        .{ .text = "result R{ok:i64,err:i64}fn main()->i64{let value=new R.ok(1);while true{acknowledge value;continue;}acknowledge value;return 0;}", .code = "E_RESULT_LOOP" },
        .{ .text = "fn main()->i64{while true{break;return 0;}return 1;}", .code = "E_UNREACHABLE" },
    };
    for (cases) |case| {
        var compilation = try language.Compilation.init(t.allocator, "invalid.my", case.text);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}
