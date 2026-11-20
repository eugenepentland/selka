//! Restating a docstring example's overlay diagnostics against the docstring.
const std = @import("std");
const t = std.testing;
const examples = @import("docstring_example_source.zig");
const restating = @import("docstring_example_diagnostics.zig");
const source = @import("source.zig");

const module =
    "public func value() -> int:\n" ++
    "    \"\"\"Moves a named value in a statement and in a continuation.\n\n" ++
    "    >>> mut merged = b\"\"\n" ++
    "    >>> match f():\n" ++
    "    ...     case Ok(text):\n" ++
    "    ...         merged = text\n" ++
    "    ...     case Err(_):\n" ++
    "    ...         merged = b\"failed\"\n" ++
    "    >>> g(refs=refs)\n" ++
    "    1\n" ++
    "    \"\"\"\n" ++
    "    return 0\n";

/// The module's first block with its overlay, rendered as `selka test` probes it.
fn overlaid(a: std.mem.Allocator) !restating.Overlaid {
    const src = try source.Source.init(a, "app.selka", module);
    const block = (try examples.extract(a, "app", src))[0];
    return .{ .block = block, .overlay = try examples.render(a, block, null, try examples.transcriptOf(a, block)) };
}

const fix_template = ",\"fix\":{{\"edits\":[{{\"path\":\"app.selka\",\"bytes\":{{\"start\":{d},\"end\":{d}}},\"text\":\"{s}\"}}]}}";
const line_template = "{{\"version\":\"diagnostic-v1\",\"kind\":\"diagnostic\",\"diagnostic\":{{\"code\":\"E_OWN_MARKER\"," ++
    "\"severity\":\"error\",\"message\":\"moving a named value requires own\",\"location\":{{\"path\":\"app.selka\"," ++
    "\"start\":{{\"line\":99,\"column\":9}},\"end\":{{\"line\":99,\"column\":13}},\"bytes\":{{\"start\":{d},\"end\":{d}}}}}," ++
    "\"notes\":[],\"stack\":{{\"frames\":[],\"omitted\":0}},\"rule\":\"W2\"{s}}}}}\n";

/// A `diagnostic-v1` error line located at overlay `bytes`, with one optional edit.
fn errorLine(a: std.mem.Allocator, bytes: source.Span, edit: ?struct { span: source.Span, text: []const u8 }) ![]const u8 {
    const fix = if (edit) |one| try std.fmt.allocPrint(a, fix_template, .{ one.span.start, one.span.end, one.text }) else "";
    return std.fmt.allocPrint(a, line_template, .{ bytes.start, bytes.end, fix });
}

/// Where `needle` first occurs in `haystack`, which the caller knows it does.
fn find(haystack: []const u8, needle: []const u8) usize {
    return std.mem.indexOf(u8, haystack, needle).?;
}

/// The overlay span of `needle` as its first occurrence in the generated text.
fn generatedSpan(overlaid_example: restating.Overlaid, needle: []const u8) source.Span {
    const start = find(overlaid_example.overlay.text[examples.appendedStart(overlaid_example.overlay)..], needle) + examples.appendedStart(overlaid_example.overlay);
    return .{ .start = start, .end = start + needle.len };
}

fn restated(a: std.mem.Allocator, example: restating.Overlaid, line: []const u8, format: @import("diagnostic_output.zig").Format) !struct { out: []const u8, tally: restating.Tally } {
    var out: std.ArrayList(u8) = .empty;
    const tally = try restating.restate(a, &out, example, line, format);
    return .{ .out = out.items, .tally = tally };
}

fn parsed(a: std.mem.Allocator, line: []const u8) !std.json.Value {
    return std.json.parseFromSliceLeaky(std.json.Value, a, line, .{});
}

fn applied(a: std.mem.Allocator, edit: std.json.Value) ![]const u8 {
    const bytes = edit.object.get("bytes").?.object;
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(a, module);
    try text.replaceRange(a, @intCast(bytes.get("start").?.integer), @intCast(bytes.get("end").?.integer - bytes.get("start").?.integer), edit.object.get("text").?.string);
    return text.items;
}

test "docstring example diagnostics: an own insertion on a continuation line maps to the docstring and applies exactly" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const example = try overlaid(a);
    const moved = generatedSpan(example, "merged = text");
    const name: source.Span = .{ .start = moved.start + "merged = ".len, .end = moved.end };
    const result = try restated(a, example, try errorLine(a, name, .{ .span = .{ .start = name.start, .end = name.start }, .text = "own " }), .json);
    try t.expectEqual(@as(usize, 1), result.tally.errors);
    try t.expectEqual(@as(usize, 0), result.tally.unmapped);
    const diag = (try parsed(a, result.out)).object.get("diagnostic").?;
    const location = diag.object.get("location").?.object;
    try t.expectEqual(@as(i64, 7), location.get("start").?.object.get("line").?.integer);
    try t.expectEqual(@as(i64, 26), location.get("start").?.object.get("column").?.integer);
    const edit = diag.object.get("fix").?.object.get("edits").?.array.items[0];
    const expected = try std.mem.replaceOwned(u8, a, module, "...         merged = text\n", "...         merged = own text\n");
    try t.expectEqualStrings(expected, try applied(a, edit));
}

test "docstring example diagnostics: an own insertion on a prompt line keeps the prompt and the docstring indentation" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const example = try overlaid(a);
    const call = generatedSpan(example, "g(refs=refs)");
    const name: source.Span = .{ .start = call.start + "g(refs=".len, .end = call.end - 1 };
    const result = try restated(a, example, try errorLine(a, name, .{ .span = .{ .start = name.start, .end = name.start }, .text = "own " }), .json);
    const edit = (try parsed(a, result.out)).object.get("diagnostic").?.object.get("fix").?.object.get("edits").?.array.items[0];
    const expected = try std.mem.replaceOwned(u8, a, module, "    >>> g(refs=refs)\n", "    >>> g(refs=own refs)\n");
    try t.expectEqualStrings(expected, try applied(a, edit));
}

test "docstring example diagnostics: an edit that touches text the extraction synthesized is dropped, reported and never guessed" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const example = try overlaid(a);
    const wrapper = generatedSpan(example, "print(out,\n");
    const prompt = generatedSpan(example, "g(refs=refs)");
    const result = try restated(a, example, try errorLine(a, prompt, .{ .span = wrapper, .text = "x" }), .json);
    try t.expectEqual(@as(usize, 1), result.tally.errors);
    try t.expectEqual(@as(usize, 1), result.tally.unmapped);
    const diag = (try parsed(a, result.out)).object.get("diagnostic").?;
    try t.expect(diag.object.get("fix") == null);
    const note = diag.object.get("notes").?.array.items[0].object;
    try t.expectEqualStrings(restating.unmapped_note, note.get("message").?.string);
    try t.expectEqual(@as(i64, 10), diag.object.get("location").?.object.get("start").?.object.get("line").?.integer);
}

test "docstring example diagnostics: an edit across two lines or with a line break in its text is not mapped" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const example = try overlaid(a);
    const first = generatedSpan(example, "merged = text");
    const two_lines = generatedSpan(example, "text):\n");
    const across = try restated(a, example, try errorLine(a, first, .{ .span = .{ .start = two_lines.start, .end = two_lines.end + 8 }, .text = "x" }), .json);
    try t.expectEqual(@as(usize, 1), across.tally.unmapped);
    const broken = try restated(a, example, try errorLine(a, first, .{ .span = .{ .start = first.start, .end = first.start }, .text = "a\\nb" }), .json);
    try t.expectEqual(@as(usize, 1), broken.tally.unmapped);
    const quoted = try restated(a, example, try errorLine(a, first, .{ .span = .{ .start = first.start, .end = first.start }, .text = "\\\"\\\"\\\"" }), .json);
    try t.expectEqual(@as(usize, 1), quoted.tally.unmapped);
}

test "docstring example diagnostics: an edit in the module's own text before the generated function maps to itself" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const example = try overlaid(a);
    const result = try restated(a, example, try errorLine(a, generatedSpan(example, "merged = text"), .{ .span = .{ .start = 7, .end = 11 }, .text = "func" }), .json);
    try t.expectEqual(@as(usize, 0), result.tally.unmapped);
    const edit = (try parsed(a, result.out)).object.get("diagnostic").?.object.get("fix").?.object.get("edits").?.array.items[0];
    try t.expectEqual(@as(i64, 7), edit.object.get("bytes").?.object.get("start").?.integer);
    try t.expectEqual(@as(i64, 11), edit.object.get("bytes").?.object.get("end").?.integer);
}

test "docstring example diagnostics: warnings are dropped and lines that are not example diagnostics pass through" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const example = try overlaid(a);
    const warning = try std.mem.replaceOwned(u8, a, try errorLine(a, generatedSpan(example, "merged = text"), null), "\"severity\":\"error\"", "\"severity\":\"warning\"");
    const outside = try errorLine(a, .{ .start = 7, .end = 11 }, null);
    const input = try std.mem.concat(a, u8, &.{ warning, "error: cannot load the program\n", outside });
    const result = try restated(a, example, input, .json);
    try t.expectEqual(@as(usize, 0), result.tally.errors);
    try t.expectEqualStrings("error: cannot load the program\n", result.out[0..31]);
    try t.expect(std.mem.endsWith(u8, result.out, outside));
}

test "docstring example diagnostics: terminal text names the docstring line, shows it and points at the moved name" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const example = try overlaid(a);
    const moved = generatedSpan(example, "merged = text");
    const name: source.Span = .{ .start = moved.start + "merged = ".len, .end = moved.end };
    const result = try restated(a, example, try errorLine(a, name, null), .text);
    try t.expectEqualStrings(
        "app.selka:7:26: error[E_OWN_MARKER]: moving a named value requires own\n" ++
            "      ...         merged = text\n" ++
            "  " ++ "                         " ++ "^\n" ++
            "  note: ownership rule W2\n",
        result.out,
    );
}

const rename_template = "{{\"version\":\"diagnostic-v1\",\"kind\":\"diagnostic\",\"diagnostic\":{{\"code\":\"E_BUILTIN_FUNCTION_NAME\"," ++
    "\"severity\":\"error\",\"message\":\"rename the function\",\"location\":{{\"path\":\"app.selka\"," ++
    "\"start\":{{\"line\":1,\"column\":13}},\"end\":{{\"line\":1,\"column\":18}},\"bytes\":{{\"start\":12,\"end\":17}}}}," ++
    "\"notes\":[{{\"role\":\"related\",\"message\":\"this bare use\",\"location\":{{\"path\":\"app.selka\",\"start\":{{\"line\":99,\"column\":1}}," ++
    "\"end\":{{\"line\":99,\"column\":2}},\"bytes\":{{\"start\":{d},\"end\":{d}}}}}}}],\"stack\":{{\"frames\":[],\"omitted\":0}}," ++
    "\"fix\":{{\"edits\":[{{\"path\":\"app.selka\",\"bytes\":{{\"start\":12,\"end\":17}},\"text\":\"app_value\"}}," ++
    "{{\"path\":\"app.selka\",\"bytes\":{{\"start\":{d},\"end\":{d}}},\"text\":\"app_g\"}}]}}}}}}\n";

test "docstring example diagnostics: a declaration's rename keeps its location and renames its use in the example" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const example = try overlaid(a);
    const call = generatedSpan(example, "g(refs=refs)");
    const use: source.Span = .{ .start = call.start, .end = call.start + 1 };
    const line = try std.fmt.allocPrint(a, rename_template, .{ use.start, use.end, use.start, use.end });
    const result = try restated(a, example, line, .json);
    try t.expectEqual(@as(usize, 0), result.tally.unmapped);
    const diag = (try parsed(a, result.out)).object.get("diagnostic").?;
    try t.expectEqual(@as(i64, 12), diag.object.get("location").?.object.get("bytes").?.object.get("start").?.integer);
    const note = diag.object.get("notes").?.array.items[0].object.get("location").?.object;
    try t.expectEqual(@as(i64, 10), note.get("start").?.object.get("line").?.integer);
    const edits = diag.object.get("fix").?.object.get("edits").?.array.items;
    try t.expectEqual(@as(i64, 12), edits[0].object.get("bytes").?.object.get("start").?.integer);
    const expected = try std.mem.replaceOwned(u8, a, module, "    >>> g(refs=refs)\n", "    >>> app_g(refs=refs)\n");
    try t.expectEqualStrings(expected, try applied(a, edits[1]));
    const shown = try restated(a, example, line, .text);
    try t.expect(std.mem.startsWith(u8, shown.out, "app.selka:1:13: error[E_BUILTIN_FUNCTION_NAME]: rename the function\n"));
    try t.expect(std.mem.indexOf(u8, shown.out, "note: app.selka:10:9: this bare use") != null);
}
