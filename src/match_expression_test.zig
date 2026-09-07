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
test "match expressions transfer owned payloads and clean unselected owned values" {
    var compilation = try language.Compilation.init(t.allocator, "owned.my", "buffer B:i64;result Open{ok:B,err:i64}result R{ok:i64,err:i64}" ++
        "fn work(heap:allocator)->R{let value=match acquire_buffer<Open>(heap,2){Open.ok(b)=>b,Open.err(discard)=>try acquire_buffer<Open>(heap,0)};" ++
        "return new R.ok(cast<i64>(len_buffer(value)));}" ++
        "fn main(heap:allocator)->i64{return match work(heap){R.ok(n)=>n,R.err(e)=>e};}");
    defer compilation.deinit();
    var statistics: @import("memory.zig").Statistics = .{};
    const result = try compilation.executeWithOptions(t.allocator, .{ .memory = .{ .statistics = &statistics } });
    try t.expectEqual(@as(i64, 0), result.value);
    try t.expectEqual(@as(u64, 1), statistics.created);
    try t.expectEqual(statistics.created, statistics.released);
}
test "match expressions reject coverage type pending payload and outer temporary loss" {
    const cases = [_][]const u8{
        "enum F{yes,no}fn main()->i64{return match new F.yes{F.yes=>1};}",
        "enum F{yes,no}fn main()->i64{return match new F.yes{F.yes=>1,F.no=>false};}",
        "enum F{yes,no}fn main()->i64{return match new F.yes{F.yes=>1,F.yes=>2,F.no=>3};}",
        "result R{ok:i64,err:i64}union U{value:R}fn main()->i64{return match new U.value(new R.ok(1)){U.value(x)=>0};}",
        "result R{ok:i64,err:i64}enum F{yes,no}fn consume(a:R,b:i64)->R{acknowledge a;return new R.ok(b);}" ++
            "fn work()->R{return consume(new R.ok(1),match new F.yes{F.yes=>try new R.err(7),F.no=>0});}" ++
            "fn main()->i64{return match work(){R.ok(x)=>x,R.err(e)=>e};}",
    };
    for (cases) |text| {
        var compilation = try language.Compilation.init(t.allocator, "invalid.my", text);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expect(compilation.program == null);
    }
}
test "match expression region dependencies forbid escaping scratch-owned payloads" {
    var compilation = try language.Compilation.init(t.allocator, "escape.my", "buffer B:i64;result Open{ok:B,err:i64}fn escape(heap:allocator)->Open{arena heap as scratch{" ++
        "let result=match acquire_buffer<Open>(scratch,0){Open.ok(b)=>new Open.ok(b),Open.err(e)=>new Open.err(e)};return result;}}" ++
        "fn main(heap:allocator)->i64{acknowledge escape(heap);return 0;}");
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_ARENA_ESCAPE", compilation.diagnostics.items[0].code);
}

test "try in ordinary and generic match arms cannot abandon an earlier argument temporary" {
    for ([_]bool{ false, true }) |generic| {
        const text = try std.mem.concat(t.allocator, u8, &.{
            "result R{ok:i64,err:i64}enum F{yes,no}fn consume(a:R,b:i64)->R{acknowledge a;return new R.ok(b);}",
            if (generic) "fn work<T:copy>()->R{" else "fn work()->R{",
            "return consume(new R.ok(1),match new F.yes{F.yes=>try new R.err(7),F.no=>0});}",
            "fn main()->i64{return 0;}",
        });
        defer t.allocator.free(text);
        var compilation = try language.Compilation.init(t.allocator, "temporary.my", text);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings("E_RESULT_PROPAGATION", compilation.diagnostics.items[0].code);
    }
}
