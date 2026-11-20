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
    const first = try language.source.Source.init(arena.allocator(), "first.selka", "alias = value\n");
    const second = try language.source.Source.init(arena.allocator(), "second.selka", "main = 1\n");
    const src = try language.source.Source.initMapped(arena.allocator(), &.{ first, second });
    const mapped = try src.mappedSpan(0, .{ .start = 0, .end = 5 });
    const diag: language.diagnostic.Diagnostic = .{ .code = "W_TEST", .severity = .warning, .span = mapped, .message = "replace", .provenance = .{ .fix = .{ .edit = .{ .span = mapped, .text = "copy" } } } };
    const json = try output.render(t.allocator, diag, src, .json);
    defer t.allocator.free(json);
    var parsed = try std.json.parseFromSlice(Value, t.allocator, json, .{});
    defer parsed.deinit();
    const edit = field(field(field(parsed.value, "diagnostic"), "fix"), "edits").array.items[0];
    try t.expectEqualStrings("first.selka", field(edit, "path").string);
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
test "a text diagnostic whose fix has a place in the source is noted for the closing `selka fix` line, and one without is not" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const src = try language.source.Source.init(arena.allocator(), "prog.selka", "alias = value\nother = 1\n");
    language.fix_tally.enable(true);
    defer language.fix_tally.enable(false);
    const first: language.source.Span = .{ .start = 0, .end = 5 };
    const fixed: language.diagnostic.Diagnostic = .{ .code = "W_TEST", .severity = .warning, .span = first, .message = "replace", .provenance = .{ .fix = .{ .edit = .{ .span = first, .text = "copy" } } } };
    const text = try output.render(t.allocator, fixed, src, .text);
    defer t.allocator.free(text);
    try t.expect(language.fix_tally.carries("prog.selka:1:1: warning[W_TEST]: replace"));
    var plain = fixed;
    plain.span = .{ .start = 14, .end = 19 };
    plain.provenance.fix = null;
    const unfixed = try output.render(t.allocator, plain, src, .text);
    defer t.allocator.free(unfixed);
    try t.expect(!language.fix_tally.carries("prog.selka:2:1: warning[W_TEST]: replace"));
    var beyond = fixed;
    beyond.span = .{ .start = 14, .end = 19 };
    beyond.provenance.fix = .{ .edit = .{ .span = .{ .start = 14, .end = 900 }, .text = "" } };
    const unplaced = try output.render(t.allocator, beyond, src, .text);
    defer t.allocator.free(unplaced);
    try t.expect(!language.fix_tally.carries("prog.selka:2:1: warning[W_TEST]: replace"));
}
test "a diagnostic carries a fix by the same test whether the fix tally is on or off" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const src = try language.source.Source.init(arena.allocator(), "prog.selka", "alias = value\nother = 1\n");
    const span: language.source.Span = .{ .start = 0, .end = 5 };
    const fixed: language.diagnostic.Diagnostic = .{ .code = "W_TEST", .severity = .warning, .span = span, .message = "replace", .provenance = .{ .fix = .{ .edit = .{ .span = span, .text = "copy" } } } };
    try t.expect(!language.fix_tally.carries("prog.selka:1:1: warning[W_TEST]: replace"));
    try t.expect(output.carriesFix(fixed, src));
    var plain = fixed;
    plain.provenance.fix = null;
    try t.expect(!output.carriesFix(plain, src));
    var beyond = fixed;
    beyond.provenance.fix = .{ .edit = .{ .span = .{ .start = 14, .end = 900 }, .text = "" } };
    try t.expect(!output.carriesFix(beyond, src));
}
fn renderScenario(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const src = try language.source.Source.init(arena.allocator(), "dir/\"é.selka", "é\tx\ny");
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
    const first = try language.source.Source.init(arena.allocator(), "first.selka", "a");
    const second = try language.source.Source.init(arena.allocator(), "second.selka", "b\n");
    const src = try language.source.Source.initMapped(arena.allocator(), &.{ first, second });
    for ([_]bool{ false, true }) |crossing| {
        const span = if (crossing) language.source.Span{ .start = 0, .end = 3 } else try src.mappedSpan(1, .{ .start = 2, .end = 2 });
        const text = try output.render(t.allocator, .{ .code = "E_TEST", .span = span, .message = "end" }, src, .json);
        defer t.allocator.free(text);
        var parsed = try std.json.parseFromSlice(Value, t.allocator, text, .{});
        defer parsed.deinit();
        const loc = field(field(parsed.value, "diagnostic"), "location");
        try t.expectEqualStrings(if (crossing) "first.selka" else "second.selka", field(loc, "path").string);
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
    try project.modules.append(allocator, .{ .name = "a", .src = try language.source.Source.init(allocator, "a.selka", "abc") });
    try project.modules.append(allocator, .{ .name = "b", .src = try language.source.Source.init(allocator, "b.selka", "\nx") });
    project.problem = .{ .code = "E_PROJECT", .message = "conflict", .site = .{ .module = 0, .span = .{ .start = 1, .end = 2 } }, .related = .{ .module = 1, .span = .{ .start = 1, .end = 2 } } };
    const text = try output.renderProject(t.allocator, &project, .json);
    defer t.allocator.free(text);
    var parsed = try std.json.parseFromSlice(Value, t.allocator, text, .{});
    defer parsed.deinit();
    const data = field(parsed.value, "diagnostic");
    try t.expectEqualStrings("a.selka", field(field(data, "location"), "path").string);
    const related = field(field(data, "notes").array.items[0], "location");
    try t.expectEqualStrings("b.selka", field(related, "path").string);
    try t.expectEqual(@as(i64, 2), field(field(related, "start"), "line").integer);
}

test "ownership diagnostic renders one rule beside fixes and preserves original module locations" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const first = try language.source.Source.init(arena.allocator(), "owner.selka", "item\n");
    const second = try language.source.Source.init(arena.allocator(), "main.selka", "main\n");
    const src = try language.source.Source.initMapped(arena.allocator(), &.{ first, second });
    const span = try src.mappedSpan(0, .{ .start = 0, .end = 4 });
    var sink: language.diagnostic.Sink = .{ .allocator = t.allocator };
    defer sink.deinit();
    try t.expect(sink.failOwnershipFix(.{ .code = "E_SINGLE_OWNER_BORROW", .rule = .B7 }, span, "copy the element", .{ .span = span, .text = "copy(item)" }) == error.SourceError);
    const json = try output.render(t.allocator, sink.items.items[0], src, .json);
    defer t.allocator.free(json);
    var parsed = try std.json.parseFromSlice(Value, t.allocator, json, .{});
    defer parsed.deinit();
    const data = field(parsed.value, "diagnostic");
    try t.expectEqualStrings("B7", field(data, "rule").string);
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, json, "\"rule\""));
    try t.expectEqualStrings("owner.selka", field(field(data, "location"), "path").string);
    try t.expectEqualStrings("owner.selka", field(field(field(data, "fix"), "edits").array.items[0], "path").string);
    const text = try output.render(t.allocator, sink.items.items[0], src, .text);
    defer t.allocator.free(text);
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, text, "note: ownership rule B7\n"));
}

test "nonownership diagnostic keeps exact diagnostic-v1 bytes including null location fields" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const src = try language.source.Source.init(arena.allocator(), "plain.selka", "x\n");
    const plain: language.diagnostic.Diagnostic = .{ .code = "E_TEST", .span = .{ .start = 0, .end = 9 }, .message = "plain" };
    const json = try output.render(t.allocator, plain, src, .json);
    defer t.allocator.free(json);
    try t.expectEqualStrings("{\"version\":\"diagnostic-v1\",\"kind\":\"diagnostic\",\"diagnostic\":{\"code\":\"E_TEST\",\"severity\":\"error\",\"message\":\"plain\"," ++
        "\"location\":{\"path\":\"plain.selka\",\"start\":{\"line\":1,\"column\":1},\"end\":null,\"bytes\":null}," ++
        "\"notes\":[],\"stack\":{\"frames\":[],\"omitted\":0}}}\n", json);
    const text = try output.render(t.allocator, plain, src, .text);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "ownership rule") == null);
}

test "nonownership fixed diagnostic keeps exact field order without a null rule" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const src = try language.source.Source.init(arena.allocator(), "plain.selka", "x\n");
    const fixed: language.diagnostic.Diagnostic = .{ .code = "E_TEST", .span = .{ .start = 0, .end = 1 }, .message = "plain", .provenance = .{ .fix = .{ .edit = .{ .span = .{ .start = 0, .end = 1 }, .text = "y" } } } };
    const json = try output.render(t.allocator, fixed, src, .json);
    defer t.allocator.free(json);
    try t.expectEqualStrings("{\"version\":\"diagnostic-v1\",\"kind\":\"diagnostic\",\"diagnostic\":{\"code\":\"E_TEST\",\"severity\":\"error\",\"message\":\"plain\"," ++
        "\"location\":{\"path\":\"plain.selka\",\"start\":{\"line\":1,\"column\":1},\"end\":{\"line\":1,\"column\":2},\"bytes\":{\"start\":0,\"end\":1}}," ++
        "\"notes\":[],\"stack\":{\"frames\":[],\"omitted\":0},\"fix\":{\"edits\":[{\"path\":\"plain.selka\",\"bytes\":{\"start\":0,\"end\":1},\"text\":\"y\"}]}}}\n", json);
}

test "typed-hole diagnostic omits absent ownership rule while retaining obligation record" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const src = try language.source.Source.init(arena.allocator(), "hole.selka", "int");
    var sink: language.diagnostic.Sink = .{ .allocator = t.allocator };
    defer sink.deinit();
    const span: language.source.Span = .{ .start = 0, .end = 3 };
    try t.expect(sink.recordHole(src, span, span, .{}) == error.SourceError);
    const json = try output.render(t.allocator, sink.items.items[0], src, .json);
    defer t.allocator.free(json);
    var parsed = try std.json.parseFromSlice(Value, t.allocator, json, .{});
    defer parsed.deinit();
    try t.expect(field(parsed.value, "diagnostic").object.get("rule") == null);
    try t.expect(parsed.value.object.get("obligation") != null);
}

// F-60: a builtin type's case has no declaration in the program (its span is the placeholder 0..0), so a note at it
// is left out instead of printed at line 1 of the first file; a note without a location (a signature) is kept.
test "a note at a declaration the program does not spell is left out" {
    var compilation = try language.Compilation.init(t.allocator, "builtin-case.selka",
        \\func half(n: int) -> int fails str:
        \\    return n // 2
        \\
        \\
        \\func main() -> int:
        \\    match half(4):
        \\        case Ok:
        \\            return 0
        \\        case Err(_):
        \\            return 1
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const refused = compilation.diagnostics.items[0];
    try t.expectEqualStrings("E_PATTERN_PAYLOAD", refused.code);
    try t.expect(refused.related != null);
    try t.expectEqual(@as(?language.diagnostic.Related, null), refused.notes()[0]);
    const rendered = try refused.render(t.allocator, compilation.src);
    defer t.allocator.free(rendered);
    try t.expect(std.mem.indexOf(u8, rendered, "builtin-case.selka:1:1") == null);
    const signature: language.diagnostic.Diagnostic = .{ .code = "E_X", .span = .{ .start = 1, .end = 2 }, .message = "m", .related = .{ .span = .{ .start = 0, .end = 0 }, .message = "f(x: int)", .role = .signature } };
    try t.expect(signature.notes()[0] != null);
}
