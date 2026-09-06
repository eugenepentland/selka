//! Lifetime diagnostics retain source witnesses through conservative dependency analysis.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const diagnostic = @import("diagnostic.zig");
const Graph = @import("generic_regions.zig").Graph;
fn at(text: []const u8, needle: []const u8, skip: usize) usize {
    return std.mem.indexOf(u8, text, needle).? + skip;
}
fn expectArena(c: *language.Compilation, primary: usize, arena: usize) !void {
    try t.expectError(error.SourceError, c.check());
    const problem = c.diagnostics.items[0];
    try t.expectEqualStrings("E_ARENA_ESCAPE", problem.code);
    try t.expectEqual(primary, problem.span.start);
    try t.expectEqual(arena, problem.related.?.span.start);
    try t.expectEqualStrings("shorter-lived arena declared here", problem.related.?.message);
}
// spec: DIAGNOSTIC-LIFETIME-1
test "arena return diagnostics point to the allocator scope and heap repair executes" {
    const schema = @import("fixture_declarations_test.zig").generic_buffer_results;
    for ([_]bool{ false, true }) |generic| {
        const prefix = if (generic) "fn work<T:copy>(heap:allocator)->A{" else "fn work(heap:allocator)->A{";
        const main = if (generic)
            "fn main(heap:allocator)->i64{match work::<bool>(heap){A.ok(b)=>{return cast<i64>(capacity_buffer(b));},A.err(e)=>{return e;}}}"
        else
            "fn main(heap:allocator)->i64{match work(heap){A.ok(b)=>{return cast<i64>(capacity_buffer(b));},A.err(e)=>{return e;}}}";
        const bad = try std.mem.concat(t.allocator, u8, &.{ schema, prefix, "arena heap as scratch{return acquire_buffer<A>(scratch,2);}}", main });
        defer t.allocator.free(bad);
        var c = try language.Compilation.init(t.allocator, "arena-repair.my", bad);
        defer c.deinit();
        try expectArena(&c, at(bad, "return acquire", 0), at(bad, "as scratch", 3));
        const fixed = try std.mem.replaceOwned(u8, t.allocator, bad, "acquire_buffer<A>(scratch,2)", "acquire_buffer<A>(heap,2)");
        defer t.allocator.free(fixed);
        var repaired = try language.Compilation.init(t.allocator, "arena-fixed.my", fixed);
        defer repaired.deinit();
        try t.expectEqual(@as(i64, 2), (try repaired.execute(t.allocator)).value);
    }
}
test "arena witnesses survive fixed point loops aggregate construction and helper calls" {
    for ([_]bool{ false, true }) |generic| {
        const prefix = if (generic) "fn work<T:copy>(heap:allocator)->Box{" else "fn work(heap:allocator)->Box{";
        const bad = try std.mem.concat(t.allocator, u8, &.{
            "struct Box{cap:allocator}fn pack(cap:allocator)->Box{return new Box{cap:cap};}",                                            prefix,
            "arena heap as scratch{let mut x=heap;let mut y=heap;while false{x=y;y=scratch;}return pack(x);}}fn main()->i64{return 0;}",
        });
        defer t.allocator.free(bad);
        var c = try language.Compilation.init(t.allocator, "loop-origin.my", bad);
        defer c.deinit();
        try expectArena(&c, at(bad, "return pack(x)", 0), at(bad, "as scratch", 3));
    }
}
fn graphScenario(allocator: std.mem.Allocator) !void {
    var sink: diagnostic.Sink = .{ .allocator = allocator };
    defer sink.deinit();
    var graph: Graph = .{ .allocator = allocator };
    defer graph.deinit();
    const first = try graph.add(.{ .depth = 1, .scope = .{ .start = 10, .end = 11 } });
    const later = try graph.add(.{ .depth = 1, .scope = .{ .start = 50, .end = 51 } });
    const value = try graph.add(.{});
    const cycle = try graph.add(.{});
    try graph.flow(first, value);
    try graph.flow(later, value);
    try graph.flow(value, cycle);
    try graph.flow(cycle, value);
    try graph.require(cycle, .{ .depth = 0 }, .{ .start = 90, .end = 91 });
    graph.check(&sink) catch |err| {
        if (err != error.SourceError) return err;
        try t.expectEqualStrings("E_ARENA_ESCAPE", sink.items.items[0].code);
        try t.expectEqual(@as(usize, 10), sink.items.items[0].related.?.span.start);
        return;
    };
    try t.expect(false);
}
test "equal depth arena witnesses propagate through cycles deterministically under allocation failure" {
    try graphScenario(t.allocator);
    try t.checkAllAllocationFailures(t.allocator, graphScenario, .{});
}
test "returned reference diagnostics explain the loan actual owner and required input before repair" {
    for ([_]bool{ false, true }) |generic| {
        const prefix = if (generic) "fn work<T:copy>(input:&i64)->&i64 from input{" else "fn work(input:&i64)->&i64 from input{";
        const main = if (generic)
            "fn main()->i64{let n=9;borrow n as r{borrow work::<bool>(r) as value{return read_ref(value);}}}"
        else
            "fn main()->i64{let n=9;borrow n as r{borrow work(r) as value{return read_ref(value);}}}";
        const bad = try std.mem.concat(t.allocator, u8, &.{ prefix, "let local=7;borrow local as loan{return loan;}}", main });
        defer t.allocator.free(bad);
        var c = try language.Compilation.init(t.allocator, "return-repair.my", bad);
        defer c.deinit();
        try t.expectError(error.SourceError, c.check());
        const problem = c.diagnostics.items[0];
        try t.expectEqualStrings("E_RETURN_LIFETIME", problem.code);
        try t.expectEqual(at(bad, "return loan", 7), problem.span.start);
        try t.expectEqual(at(bad, "as loan", 3), problem.related.?.span.start);
        try t.expectEqual(at(bad, "let local", 4), problem.provenance.origin.?.span.start);
        try t.expectEqual(at(bad, "input:&i64", 0), problem.provenance.requirement.?.span.start);
        const fixed = try std.mem.replaceOwned(u8, t.allocator, bad, "let local=7;borrow local as loan{return loan;}", "return input;");
        defer t.allocator.free(fixed);
        var repaired = try language.Compilation.init(t.allocator, "return-fixed.my", fixed);
        defer repaired.deinit();
        try t.expectEqual(@as(i64, 9), (try repaired.execute(t.allocator)).value);
    }
}
fn renderScenario(allocator: std.mem.Allocator) !void {
    var sink: diagnostic.Sink = .{ .allocator = allocator };
    defer sink.deinit();
    const failure = sink.failReturnLifetime(.{ .start = 6, .end = 7 }, .{ .start = 4, .end = 5 }, .{ .start = 2, .end = 3 }, .{ .start = 0, .end = 1 });
    if (failure != error.SourceError) return failure;
    const text = try sink.items.items[0].render(allocator, .{ .path = "return.my", .bytes = "i\nv\nb\nr", .line_starts = &.{ 0, 2, 4, 6 } });
    defer allocator.free(text);
    for ([_][]const u8{
        "return.my:4:1: error[E_RETURN_LIFETIME]", "return.my:3:1: returned borrow declared here",
        "return.my:2:1: value declared here",      "return.my:1:1: result lifetime is tied to this input",
    }) |part| try t.expect(std.mem.indexOf(u8, text, part) != null);
}
test "returned lifetime collection and rendering preserve allocation failures and all note locations" {
    try renderScenario(t.allocator);
    try t.checkAllAllocationFailures(t.allocator, renderScenario, .{});
}

test "nested arena evidence selects the deepest dependency through wrappers and mutable helper writes" {
    for ([_]bool{ false, true }) |generic| {
        const prefix = if (generic) "fn work<T:copy>(heap:allocator)->allocator{" else "fn work(heap:allocator)->allocator{";
        const bad = try std.mem.concat(t.allocator, u8, &.{
            "fn set(dest:&mut allocator,cap:allocator)->i64{write_ref(dest,cap);return 0;}",                                                                            prefix,
            "arena heap as outer{arena outer as inner{let mut value=outer;borrow mut value as dest{discard set(dest,inner);}return value;}}}fn main()->i64{return 0;}",
        });
        defer t.allocator.free(bad);
        var c = try language.Compilation.init(t.allocator, "deep-origin.my", bad);
        defer c.deinit();
        try expectArena(&c, at(bad, "return value", 0), at(bad, "as inner", 3));
    }
}
