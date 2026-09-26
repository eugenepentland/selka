//! Machine diagnostics preserve byte coordinates, original modules and bounded evidence.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const output = language.diagnostic_output;
const Value = std.json.Value;
fn field(value: Value, name: []const u8) Value {
    return value.object.get(name).?;
}
// spec: DIAGNOSTIC-FIX-1
test "structured fix maps exact original-file byte ranges and drops crossing edits" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const first = try language.source.Source.init(arena.allocator(), "first.my", "alias = value\n");
    const second = try language.source.Source.init(arena.allocator(), "second.my", "main = 1\n");
    const src = try language.source.Source.initMapped(arena.allocator(), &.{ first, second });
    const mapped = try src.mappedSpan(0, .{ .start = 0, .end = 5 });
    const diag: language.diagnostic.Diagnostic = .{ .code = "W_TEST", .severity = .warning, .span = mapped, .message = "replace", .provenance = .{ .fix = .{ .edit = .{ .span = mapped, .text = "copy" } } } };
    const json = try output.render(t.allocator, diag, src, .json);
    defer t.allocator.free(json);
    var parsed = try std.json.parseFromSlice(Value, t.allocator, json, .{});
    defer parsed.deinit();
    const edit = field(field(field(parsed.value, "diagnostic"), "fix"), "edits").array.items[0];
    try t.expectEqualStrings("first.my", field(edit, "path").string);
    try t.expectEqual(@as(i64, 5), field(field(edit, "bytes"), "end").integer);
    try t.expectEqualStrings("copy", field(edit, "text").string);
    var crossing = diag;
    crossing.provenance.fix = .{ .edit = .{ .span = .{ .start = mapped.start, .end = src.bytes.len }, .text = "" } };
    const omitted = try output.render(t.allocator, crossing, src, .json);
    defer t.allocator.free(omitted);
    var other = try std.json.parseFromSlice(Value, t.allocator, omitted, .{});
    defer other.deinit();
    try t.expect(field(other.value, "diagnostic").object.get("fix") == null);
}
fn renderScenario(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const src = try language.source.Source.init(arena.allocator(), "dir/\"é.my", "é\tx\ny");
    var diag: language.diagnostic.Diagnostic = .{
        .code = "E_TEST",
        .severity = .warning,
        .message = "quoted \"value\"\nnext",
        .span = .{ .start = 3, .end = 4 },
        .related = .{ .span = .{ .start = 0, .end = 2 }, .message = "earlier" },
        .provenance = .{
            .origin = .{ .span = .{ .start = 5, .end = 6 }, .message = "owner" },
            .requirement = .{ .span = .{ .start = 6, .end = 6 }, .message = "contract" },
        },
    };
    diag.stack.len = 1;
    diag.stack.omitted = 3;
    diag.stack.frames[0] = .{ .function = "helper::call", .span = .{ .start = 5, .end = 6 } };
    const json = try output.render(allocator, diag, src, .json);
    defer allocator.free(json);
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, json, "\n"));
    var parsed = try std.json.parseFromSlice(Value, allocator, json, .{});
    defer parsed.deinit();
    try t.expectEqualStrings("diagnostic-v1", field(parsed.value, "version").string);
    const data = field(parsed.value, "diagnostic");
    try t.expectEqualStrings("warning", field(data, "severity").string);
    try t.expectEqualStrings(diag.message, field(data, "message").string);
    const loc = field(data, "location");
    try t.expectEqualStrings(src.path, field(loc, "path").string);
    try t.expectEqual(@as(i64, 4), field(field(loc, "start"), "column").integer);
    try t.expectEqual(@as(i64, 3), field(field(loc, "bytes"), "start").integer);
    const notes = field(data, "notes").array.items;
    try t.expectEqual(@as(usize, 3), notes.len);
    try t.expectEqualStrings("requirement", field(notes[2], "role").string);
    try t.expectEqual(@as(i64, 2), field(field(field(notes[2], "location"), "start"), "column").integer);
    const stack = field(data, "stack");
    try t.expectEqual(@as(i64, 3), field(stack, "omitted").integer);
    try t.expectEqualStrings("helper::call", field(field(stack, "frames").array.items[0], "function").string);
    const legacy = try output.render(allocator, diag, src, .text);
    defer allocator.free(legacy);
    const expected = try diag.render(allocator, src);
    defer allocator.free(expected);
    try t.expectEqualStrings(expected, legacy);
}
// spec: DIAGNOSTIC-JSON-1
test "JSON diagnostic rendering retains bytes Unicode notes and traces under allocation failure" {
    try renderScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), renderScenario, .{});
}
test "JSON diagnostics map module ranges including EOF and avoid invented cross-module ends" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const first = try language.source.Source.init(arena.allocator(), "first.my", "a");
    const second = try language.source.Source.init(arena.allocator(), "second.my", "b\n");
    const src = try language.source.Source.initMapped(arena.allocator(), &.{ first, second });
    for ([_]bool{ false, true }) |crossing| {
        const span = if (crossing) language.source.Span{ .start = 0, .end = 3 } else try src.mappedSpan(1, .{ .start = 2, .end = 2 });
        const text = try output.render(t.allocator, .{ .code = "E_TEST", .span = span, .message = "end" }, src, .json);
        defer t.allocator.free(text);
        var parsed = try std.json.parseFromSlice(Value, t.allocator, text, .{});
        defer parsed.deinit();
        const loc = field(field(parsed.value, "diagnostic"), "location");
        try t.expectEqualStrings(if (crossing) "first.my" else "second.my", field(loc, "path").string);
        if (crossing) {
            try t.expect(field(loc, "bytes") == .null);
            try t.expect(field(loc, "end") == .null);
        } else {
            try t.expectEqual(@as(i64, 2), field(field(loc, "bytes"), "start").integer);
            try t.expectEqual(@as(i64, 2), field(field(loc, "start"), "line").integer);
        }
    }
}
test "JSON auxiliary messages preserve non UTF8 bytes without producing invalid JSON" {
    const text = try output.message(t.allocator, "bad\xff", .json);
    defer t.allocator.free(text);
    var parsed = try std.json.parseFromSlice(Value, t.allocator, text, .{});
    defer parsed.deinit();
    try t.expectEqualStrings("message", field(parsed.value, "kind").string);
    const bytes = field(parsed.value, "message").array.items;
    try t.expectEqual(@as(usize, 4), bytes.len);
    try t.expectEqual(@as(i64, 255), bytes[3].integer);
}
test "JSON project diagnostics preserve cross-module related declarations and NoProblem" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try t.expectError(error.NoProblem, output.renderProject(t.allocator, &project, .json));
    const allocator = project.arena.allocator();
    try project.modules.append(allocator, .{ .name = "a", .src = try language.source.Source.init(allocator, "a.my", "abc") });
    try project.modules.append(allocator, .{ .name = "b", .src = try language.source.Source.init(allocator, "b.my", "\nx") });
    project.problem = .{ .code = "E_PROJECT", .message = "conflict", .site = .{ .module = 0, .span = .{ .start = 1, .end = 2 } }, .related = .{ .module = 1, .span = .{ .start = 1, .end = 2 } } };
    const text = try output.renderProject(t.allocator, &project, .json);
    defer t.allocator.free(text);
    var parsed = try std.json.parseFromSlice(Value, t.allocator, text, .{});
    defer parsed.deinit();
    const data = field(parsed.value, "diagnostic");
    try t.expectEqualStrings("a.my", field(field(data, "location"), "path").string);
    const related = field(field(data, "notes").array.items[0], "location");
    try t.expectEqualStrings("b.my", field(related, "path").string);
    try t.expectEqual(@as(i64, 2), field(field(related, "start"), "line").integer);
}
