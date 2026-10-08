const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const quality = language.quality;
fn index(c: *language.Compilation, name: []const u8) !usize {
    for (c.program.?.functions, 0..) |function, i| if (std.mem.eql(u8, function.name, name)) return i;
    return error.TestUnexpectedResult;
}
const graph =
    \\domain D: i64:
    \\    private def hidden() -> i64:
    \\        return 1
    \\
    \\
    \\def leaf(x: i64) -> i64:
    \\    return x
    \\
    \\
    \\def a(n: i64) -> i64:
    \\    if n <= 0:
    \\        return 0
    \\    return b(n - 1)
    \\
    \\
    \\def b(n: i64) -> i64:
    \\    return a(n)
    \\
    \\
    \\def unused() -> i64:
    \\    return leaf(1)
    \\
    \\
    \\def main() -> i64:
    \\    if False:
    \\        _ = a(1)
    \\    return leaf(2) + leaf(3)
;

// spec: TOOL-6
test "resolved reachability includes untaken call paths cycles and incoming sites from unreachable functions" {
    var c = try language.Compilation.init(t.allocator, "quality.my", graph);
    defer c.deinit();
    try c.check();
    var result = try quality.analyze(t.allocator, c.program.?, c.src, .{});
    defer result.deinit();
    try t.expect(result.functions[try index(&c, "a")].reachable);
    try t.expect(result.functions[try index(&c, "b")].reachable);
    try t.expect(!result.functions[try index(&c, "unused")].reachable);
    try t.expectEqual(@as(usize, 3), result.functions[try index(&c, "leaf")].incoming_sites);
    const rendered = try quality.render(t.allocator, result, c.program.?, c.src);
    defer t.allocator.free(rendered);
    try t.expect(std.mem.indexOf(u8, rendered, "private=true; reachable-from-main=false") != null);
    try t.expect(std.mem.indexOf(u8, rendered, "Runtime coverage and assertions: not measured") != null);
    try t.expect(std.mem.indexOf(u8, rendered, "external entry policy") != null);
}

test "zero thresholds disable metric signals without hiding facts or changing source checking" {
    var c = try language.Compilation.init(t.allocator, "quality.my",
        \\def main() -> i64:
        \\    if True:
        \\        return 1
        \\    return 0
    );
    defer c.deinit();
    try c.check();
    var result = try quality.analyze(t.allocator, c.program.?, c.src, .{ .max_function_lines = 0, .max_parameters = 0, .max_nesting = 0, .max_decisions = 0, .max_line_bytes = 0 });
    defer result.deinit();
    const rendered = try quality.render(t.allocator, result, c.program.?, c.src);
    defer t.allocator.free(rendered);
    try t.expect(std.mem.indexOf(u8, rendered, "exceeds configured") == null);
    try t.expect(std.mem.indexOf(u8, rendered, "decision-points=1") != null);
}
fn allocationScenario(allocator: std.mem.Allocator, c: *language.Compilation) !void {
    var result = try quality.analyze(allocator, c.program.?, c.src, .{});
    defer result.deinit();
    const rendered = try quality.render(allocator, result, c.program.?, c.src);
    defer allocator.free(rendered);
    try t.expect(result.functions[try index(c, "leaf")].reachable);
}
test "quality traversal reachability and rendering release storage at every allocation failure" {
    var c = try language.Compilation.init(t.allocator, "quality.my", graph);
    defer c.deinit();
    try c.check();
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{&c});
}

test "static call reachability traverses a long chain without host recursion" {
    var output: std.Io.Writer.Allocating = .init(t.allocator);
    defer output.deinit();
    try writeCallChain(&output);
    const text = try output.toOwnedSlice();
    defer t.allocator.free(text);
    var c = try language.Compilation.init(t.allocator, "chain.my", text);
    defer c.deinit();
    try c.check();
    var result = try quality.analyze(t.allocator, c.program.?, c.src, .{});
    defer result.deinit();
    for (result.functions) |function| try t.expect(function.reachable);
    try t.expectEqual(@as(usize, 1), result.functions[try index(&c, "f2000")].incoming_sites);
}

test "explicit quality roots validate bounds and tolerate duplicate or empty roots" {
    var c = try language.Compilation.init(t.allocator, "roots.my",
        \\def main() -> i64:
        \\    return 0
        \\
        \\
        \\def api() -> i64:
        \\    return 1
    );
    defer c.deinit();
    try c.check();
    var empty = try language.quality.analyzeWithExports(t.allocator, c.program.?, c.src, .{}, &.{});
    defer empty.deinit();
    try t.expect(empty.module_roots);
    try t.expect(empty.functions[0].reachable);
    try t.expect(!empty.functions[0].reachable_from_exports);
    var duplicate = try language.quality.analyzeWithExports(t.allocator, c.program.?, c.src, .{}, &.{ @fromBackingInt(1), @fromBackingInt(1) });
    defer duplicate.deinit();
    try t.expect(duplicate.functions[1].exported);
    try t.expect(duplicate.functions[1].reachable_from_exports);
    try t.expect(!duplicate.functions[1].reachable);
    try t.expectError(error.InvalidQualityRoot, language.quality.analyzeWithExports(t.allocator, c.program.?, c.src, .{}, &.{@fromBackingInt(2)}));
}

fn writeCallChain(output: *std.Io.Writer.Allocating) !void {
    for (0..2000) |i| try output.writer.print("def f{d}() -> i64:\n    return f{d}()\n\n\n", .{ i, i + 1 });
    try output.writer.writeAll(
        \\def f2000() -> i64:
        \\    return 7
        \\
        \\
        \\def main() -> i64:
        \\    return f0()
    );
}

test "structural metrics count branches loops short circuits nesting and physical source lines" {
    const text =
        \\def work(x: i64, flag: bool) -> i64:
        \\    n = x
        \\    if flag and n > 0:
        \\        while n > 0:
        \\            n -= 1
        \\    if flag:
        \\        return n
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    return work(2, True)
    ;
    var c = try language.Compilation.init(t.allocator, "quality.my", text);
    defer c.deinit();
    try c.check();
    var result = try quality.analyze(t.allocator, c.program.?, c.src, .{ .max_nesting = 1, .max_decisions = 3, .max_parameters = 1, .max_function_lines = 7 });
    defer result.deinit();
    const metrics = result.functions[try index(&c, "work")];
    try t.expectEqual(@as(usize, 8), metrics.structure.lines);
    try t.expectEqual(@as(usize, 2), metrics.structure.parameters);
    try t.expectEqual(@as(usize, 2), metrics.structure.nesting);
    try t.expectEqual(@as(usize, 4), metrics.structure.decisions);
    try t.expectEqual(@as(usize, "def work(x: i64, flag: bool) -> i64:".len), metrics.structure.longest_line);
    const first = try quality.render(t.allocator, result, c.program.?, c.src);
    defer t.allocator.free(first);
    const second = try quality.render(t.allocator, result, c.program.?, c.src);
    defer t.allocator.free(second);
    try t.expectEqualStrings(first, second);
    for ([_][]const u8{ "function-lines 8 exceeds", "parameters 2 exceeds", "control-nesting 2 exceeds", "decision-points 4 exceeds" }) |part| try t.expect(std.mem.indexOf(u8, first, part) != null);
}
