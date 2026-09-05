const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const eval = language.evaluation;
const pure = "struct Pair { a:i64,b:i64 } fn sum(p:Pair)->i64{return p.a+p.b;} fn main()->i64{return sum(new Pair{a:3,b:4});}";
fn evaluate(allocator: std.mem.Allocator, c: *language.Compilation, options: eval.Options) !language.vm.Result {
    var sink: language.diagnostic.Sink = .{ .allocator = c.arena.allocator(), .items = c.diagnostics };
    defer c.diagnostics = sink.items;
    return eval.evaluate(allocator, c.code.?, &sink, options);
}
test "restricted evaluator preserves aggregate values and every instruction/frame boundary" {
    var c = try language.Compilation.init(t.allocator, "eval.my", pure);
    defer c.deinit();
    try c.emit();
    try t.expectEqual(@as(i64, 7), (try evaluate(t.allocator, &c, .{})).value);
    for (1..40) |steps| {
        const reference = try language.vm.runWithOptions(t.allocator, c.code.?, .{ .max_steps = steps });
        const result = try evaluate(t.allocator, &c, .{ .max_steps = steps });
        try t.expectEqual(std.meta.activeTag(reference), std.meta.activeTag(result));
        switch (reference) {
            .value => |value| try t.expectEqual(value, result.value),
            .trap => |trap| {
                try t.expectEqualStrings(trap.code, result.trap.code);
                try t.expectEqualDeep(trap.span, result.trap.span);
                try t.expectEqual(trap.trace_len, result.trap.trace_len);
                try t.expectEqualDeep(trap.trace[0..trap.trace_len], result.trap.trace[0..result.trap.trace_len]);
                try t.expectEqual(trap.trace_omitted, result.trap.trace_omitted);
            },
        }
    }
    try t.expectEqualStrings("R_FRAME_LIMIT", (try evaluate(t.allocator, &c, .{ .max_frames = 1 })).trap.code);
    try t.expectEqualStrings("R_EVAL_MEMORY", (try evaluate(t.allocator, &c, .{ .max_bytes = 1 })).trap.code);
    var recursive = try language.Compilation.init(t.allocator, "recursive.my", "fn main()->i64{return main();}");
    defer recursive.deinit();
    try recursive.emit();
    try t.expectEqualStrings("R_EVAL_MEMORY", (try evaluate(t.allocator, &recursive, .{ .max_bytes = 65536, .max_frames = 100000 })).trap.code);
    for ([_]eval.Options{ .{ .max_bytes = 0 }, .{ .max_steps = 0 }, .{ .max_frames = 0 } }) |options| try t.expectError(error.InvalidBudget, evaluate(t.allocator, &c, options));
}
test "restricted evaluation rejects authority even in untaken transitive calls" {
    for ([_][]const u8{
        "fn main(heap:allocator)->i64{discard heap;return 1;}",
        "result T{ok:i64,err:i64} fn read(c:clock_cap)->T{return clock_now<T>(c);} fn main(c:clock_cap)->i64{if false{acknowledge read(c);}return 1;}",
    }, [_][]const u8{ "E_EVAL_INPUT", "E_EVAL_EFFECT" }) |source, code| {
        var c = try language.Compilation.init(t.allocator, "eval.my", source);
        defer c.deinit();
        try c.emit();
        try t.expectError(error.SourceError, evaluate(t.allocator, &c, .{}));
        try t.expectEqualStrings(code, c.diagnostics.items[c.diagnostics.items.len - 1].code);
    }
    var c = try language.Compilation.init(t.allocator, "eval.my", "result T{ok:i64,err:i64} fn unused(c:clock_cap)->T{return clock_now<T>(c);} fn main()->i64{return 7;}");
    defer c.deinit();
    try c.emit();
    try t.expectEqual(@as(i64, 7), (try evaluate(t.allocator, &c, .{})).value);
}
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "eval.my", pure);
    defer c.deinit();
    try c.emit();
    try t.expectEqual(@as(i64, 7), (try evaluate(allocator, &c, .{})).value);
    var sink: language.diagnostic.Sink = .{ .allocator = c.arena.allocator() };
    try t.expectEqual(null, try eval.preflight(allocator, c.code.?, &sink, .{}));
}
test "restricted evaluator releases host storage through allocation failures" {
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), allocationScenario, .{});
}

test "evaluation preflight validates eligibility without executing traps or nontermination" {
    for ([_][]const u8{ "fn main()->i64{return 1/0;}", "fn main()->i64{return main();}" }) |text| {
        var c = try language.Compilation.init(t.allocator, "preflight.my", text);
        defer c.deinit();
        try c.emit();
        var sink: language.diagnostic.Sink = .{ .allocator = c.arena.allocator() };
        try t.expectEqual(null, try eval.preflight(t.allocator, c.code.?, &sink, .{ .max_steps = 1, .max_frames = 1 }));
        const failure = (try eval.preflight(t.allocator, c.code.?, &sink, .{ .max_bytes = 1 })).?;
        try t.expectEqualStrings("R_EVAL_MEMORY", failure.code);
    }
}
