const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const Source = language.source.Source;

fn mappedCompilation(allocator: std.mem.Allocator, texts: []const []const u8) !language.Compilation {
    var compilation = try language.Compilation.init(allocator, "<project>", "");
    errdefer compilation.deinit();
    const scratch = compilation.arena.allocator();
    const sources = try scratch.alloc(Source, texts.len);
    for (texts, sources, 0..) |text, *src, i| {
        const path = try std.fmt.allocPrint(scratch, "part{d}.my", .{i});
        src.* = try Source.init(scratch, path, text);
    }
    compilation.src = try Source.initMapped(scratch, sources);
    return compilation;
}
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try mappedCompilation(allocator, &.{
        \\func main() -> i64:
        \\    return helper()
        ,
        // CRLF line ends and an inline tab still map back to this input's own offsets.
        "func helper() -> i64:\r\n    return divtrunc(1,\t0)",
    });
    defer compilation.deinit();
    const result = try @import("native_execute.zig").run(&compilation);
    try t.expect(result.trapped());
    const text = result.stderr;
    for ([_][]const u8{ "part1.my:2:", "R_DIVISION_BY_ZERO", "in main at part0.my:", "in helper at part1.my:" }) |part| try t.expect(std.mem.indexOf(u8, text, part) != null);
    try compilation.check();
}
// spec: PROJ-4
test "mapped related diagnostics identify each original declaration" {
    var compilation = try mappedCompilation(t.allocator, &.{
        \\func main() -> i64:
        \\    return 0
        ,
        \\func main() -> i64:
        \\    return 1
    });
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const text = try compilation.diagnostics.items[0].render(t.allocator, compilation.src);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "part1.my:1:") != null);
    try t.expect(std.mem.indexOf(u8, text, "note: part0.my:1:") != null);
}
test "mapped sources distinguish empty inputs EOF boundaries CRLF tabs and checked spans" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const originals = [_]Source{
        try Source.init(allocator, "empty.my", ""),
        try Source.init(allocator, "middle.my", "a\r\n\tb"),
        try Source.init(allocator, "last.my", ""),
    };
    const src = try Source.initMapped(allocator, &originals);
    for (originals, 0..) |original, i| {
        for (0..original.bytes.len + 1) |offset| {
            const mapped = try src.mappedSpan(i, .{ .start = offset, .end = offset });
            const restored = try src.originalSpan(mapped);
            try t.expectEqual(i, restored.input);
            try t.expectEqual(offset, restored.span.start);
            try t.expectEqual(offset, restored.span.end);
            const want = original.locate(offset);
            const got = src.locate(mapped.start);
            try t.expectEqualStrings(want.path, got.path);
            try t.expectEqual(want.line, got.line);
            try t.expectEqual(want.column, got.column);
            try t.expectEqualStrings(want.text, got.text);
        }
        const whole = try src.mappedSpan(i, .{ .start = 0, .end = original.bytes.len });
        try t.expectEqualStrings(original.bytes, src.text(whole));
    }
    try t.expectEqualStrings("last.my", src.locate(std.math.maxInt(usize)).path);
    try t.expectError(error.InvalidSourceIndex, src.mappedSpan(3, .{ .start = 0, .end = 0 }));
    try t.expectError(error.InvalidSourceSpan, src.mappedSpan(0, .{ .start = 0, .end = 1 }));
    try t.expectError(error.InvalidSourceSpan, src.mappedSpan(1, .{ .start = 2, .end = 1 }));
    try t.expectError(error.InvalidSourceSpan, src.originalSpan(.{ .start = 0, .end = 2 }));
    try t.expectError(error.InvalidSourceSpan, src.originalSpan(.{ .start = src.bytes.len, .end = src.bytes.len }));
    try t.expectError(error.NotMappedSource, originals[0].originalSpan(.{ .start = 0, .end = 0 }));
    try t.expectError(error.EmptySourceMap, Source.initMapped(allocator, &.{}));
    try t.expectError(error.NestedSourceMap, Source.initMapped(allocator, &.{src}));
}
test "quality metrics use combined line indices while reports use original paths" {
    var compilation = try mappedCompilation(t.allocator, &.{
        \\func main() -> i64:
        \\    return helper() # the entry source has a much longer line than any helper line
        ,
        \\func helper() -> i64:
        \\    return 1
        ,
    });
    defer compilation.deinit();
    try compilation.check();
    var analysis = try language.quality.analyze(t.allocator, compilation.program.?, compilation.src, .{});
    defer analysis.deinit();
    try t.expectEqual(@as(usize, 2), analysis.functions[1].structure.lines);
    try t.expect(analysis.functions[1].structure.longest_line < analysis.functions[0].structure.longest_line);
    const text = try language.quality.render(t.allocator, analysis, compilation.program.?, compilation.src);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "part1.my:1:") != null);
    try t.expect(std.mem.indexOf(u8, text, "calls helper at part0.my:2:") != null);
}
