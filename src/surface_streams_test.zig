//! The stream method spellings are retired for the stream-first functions (F-s):
//! `out.print(...)` and `out.write(...)` on a named `Stream` are refused with
//! E_METHOD_REMOVED, and the certain repair checks and prints what the spelling
//! printed. A stream held in a field, or a write whose count is used, has no
//! certain repair and is refused without one.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const fixture = @import("stdlib_fixture.zig");
const native = @import("native_execute.zig");

/// `text` with every edit of `fix` applied, in span order.
fn spliced(a: std.mem.Allocator, text: []const u8, fix: language.diagnostic.Fix) ![]const u8 {
    const edits = try a.alloc(language.diagnostic.Edit, fix.count());
    for (edits, 0..) |*slot, index| slot.* = fix.at(index);
    std.mem.sort(language.diagnostic.Edit, edits, {}, struct {
        fn earlier(_: void, left: language.diagnostic.Edit, right: language.diagnostic.Edit) bool {
            return left.span.start < right.span.start;
        }
    }.earlier);
    var out: std.ArrayList(u8) = .empty;
    var cursor: usize = 0;
    for (edits) |edit| {
        try out.appendSlice(a, text[cursor..edit.span.start]);
        try out.appendSlice(a, edit.text);
        cursor = edit.span.end;
    }
    try out.appendSlice(a, text[cursor..]);
    return out.toOwnedSlice(a);
}

/// The embedded project whose `main.selka` is `text`, run once with the default
/// grants: its standard output must be exactly `stdout`.
fn expectProjectOutput(text: []const u8, stdout: []const u8) !void {
    const Entry = struct {
        text: []const u8,
        pub fn read(context: ?*anyopaque, a: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
            if (!std.mem.eql(u8, path, "main.selka")) return error.NotFound;
            return a.dupe(u8, (@as(*const @This(), @ptrCast(@alignCast(context.?)))).text);
        }
    };
    var entry: Entry = .{ .text = text };
    var project: language.embedded_project.Program = undefined;
    try project.init(t.allocator, .{ .context = &entry, .read = Entry.read });
    defer project.deinit();
    const result = try native.run(&project.compilation);
    try t.expect(!result.trapped());
    try t.expectEqualStrings(stdout, result.stdout);
}

/// One retired stream spelling with its certain repair: the refusal answers
/// E_METHOD_REMOVED with the stream-first call as the repair, and the repaired
/// program returns normally having printed exactly `stdout`.
fn refusedStreamSpelling(text: []const u8, repair: []const u8, stdout: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const report = try fixture.check(a, text);
    try t.expect(!report.passed);
    const first = report.firstError().?;
    try t.expectEqualStrings("E_METHOD_REMOVED", first.code);
    try t.expect(std.mem.indexOf(u8, first.message, "is a function now") != null);
    const fix = first.provenance.fix.?;
    try t.expectEqualStrings(repair, fix.edit.text);
    try t.expectEqual(@as(usize, 1), fix.count());
    const repaired = try spliced(a, report.src.bytes, fix);
    try expectProjectOutput(repaired, stdout);
}

// spec-case: METHOD-REMOVED-1
test "each stream method spelling on a named stream is refused with its function repair" {
    const cases = [_]struct { text: []const u8, repair: []const u8, stdout: []const u8 }{
        .{ .text = "func main(out: Stream) -> int:\n    out.print(1, 2, sep=\"-\")\n    return 0\n", .repair = "print(out, 1, 2, sep=\"-\")", .stdout = "1-2\n" },
        .{ .text = "func main(out: Stream) -> int:\n    out.print()\n    return 0\n", .repair = "print(out)", .stdout = "\n" },
        .{ .text = "func main(out: Stream) -> int:\n    out.print(\"a\", end=\"!\\n\")\n    return 0\n", .repair = "print(out, \"a\", end=\"!\\n\")", .stdout = "a!\n" },
        .{ .text = "func main(out: Stream) -> int:\n    _ = out.print(3)\n    return 0\n", .repair = "print(out, 3)", .stdout = "3\n" },
        // Each write ends in a newline: the harness reads the result from the last stdout line.
        .{ .text = "func main(out: Stream) -> int:\n    out.write(\"z\\n\")\n    return 0\n", .repair = "write(out, \"z\\n\")", .stdout = "z\n" },
        .{ .text = "func main(out: Stream) -> int:\n    _ = out.write(\"xy\\n\")\n    return 0\n", .repair = "write(out, \"xy\\n\")", .stdout = "xy\n" },
        .{ .text = "func main(out: Stream) -> int:\n    _ = out.write(b\"\\x41\\n\")\n    return 0\n", .repair = "write(out, b\"\\x41\\n\")", .stdout = "A\n" },
    };
    for (cases) |case| try refusedStreamSpelling(case.text, case.repair, case.stdout);
}

// spec-case: METHOD-REMOVED-1
test "a stream spelling with no statement form, or a field stream, is refused without a repair" {
    const cases = [_]struct { text: []const u8, code: []const u8 }{
        // A count used as a value has no statement form to rewrite to.
        .{ .text = "func main(out: Stream) -> int:\n    mut written = out.write(\"x\")\n    return written\n", .code = "E_METHOD_REMOVED" },
        // A field-held stream takes its first argument from an expression, which the stream-first form does not accept.
        .{ .text = "record Sink:\n    stream: Stream\n\n\nfunc main(out: Stream) -> int:\n    mut sink = Sink(stream=out)\n    sink.stream.print(1)\n    return 0\n", .code = "E_METHOD_REMOVED" },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const report = try fixture.check(arena.allocator(), case.text);
        try t.expect(!report.passed);
        const first = report.firstError().?;
        try t.expectEqualStrings(case.code, first.code);
        try t.expect(first.provenance.fix == null);
    }
}
