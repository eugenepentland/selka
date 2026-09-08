const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const lexer = @import("lexer.zig");
const diagnostic = @import("diagnostic.zig");
fn roundTrip(allocator: std.mem.Allocator, text: []const u8) !void {
    var original = try language.Compilation.init(allocator, "before.my", text);
    defer original.deinit();
    const formatted = try original.format(allocator);
    defer allocator.free(formatted);
    var after = try language.Compilation.init(allocator, "after.my", formatted);
    defer after.deinit();
    const twice = try after.format(allocator);
    defer allocator.free(twice);
    try t.expectEqualStrings(formatted, twice);
    var first_sink: diagnostic.Sink = .{ .allocator = original.arena.allocator() };
    var second_sink: diagnostic.Sink = .{ .allocator = after.arena.allocator() };
    const before_tokens = try lexer.lex(first_sink.allocator, original.src.bytes, &first_sink);
    const after_tokens = try lexer.lex(second_sink.allocator, after.src.bytes, &second_sink);
    try t.expectEqual(before_tokens.len, after_tokens.len);
    for (before_tokens, after_tokens) |before, next| {
        try t.expectEqual(before.tag, next.tag);
        try t.expectEqualStrings(original.src.text(before.span), after.src.text(next.span));
    }
    // Every comment retains its text and sequence. Token-gap association is also
    // checked separately in the golden fixture below.
    var before_comments = std.mem.splitScalar(u8, text, '\n');
    var after_comments = std.mem.splitScalar(u8, formatted, '\n');
    while (before_comments.next()) |line| {
        const start = std.mem.indexOf(u8, line, "//") orelse continue;
        var found = false;
        while (after_comments.next()) |next| {
            const offset = std.mem.indexOf(u8, next, "//") orelse continue;
            try t.expectEqualStrings(std.mem.trimEnd(u8, line[start..], "\r"), next[offset..]);
            found = true;
            break;
        }
        try t.expect(found);
    }
    while (after_comments.next()) |line| try t.expect(std.mem.indexOf(u8, line, "//") == null);
}
// spec: TOOL-4
test "formatter canonical indentation preserves inline standalone and trailing comments" {
    const text = "// heading\r\nfn main( )->i64{ // body\r\nlet x=1; // value\n// return note\nreturn x+2;} // end";
    const expected = "// heading\nfn main() -> i64 { // body\n    let x = 1; // value\n    // return note\n    return x + 2;\n} // end\n";
    var c = try language.Compilation.init(t.allocator, "fmt.my", text);
    defer c.deinit();
    const formatted = try c.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expectEqualStrings(expected, formatted);
    try roundTrip(t.allocator, text);
    var after = try language.Compilation.init(t.allocator, "fmt.my", formatted);
    defer after.deinit();
    try t.expectEqual(@as(i64, 3), (try after.execute(t.allocator)).value);
}
test "formatter preserves ambiguous operators literal spellings and aggregate type tokens" {
    const text = "fn main()->i64{let mut a=new [3]i64[1,2,3];borrow mut a[0..3] as s{write_slice(s,0,-1);}if !(a[0]<0)&&false{return 0;}return cast<i64>(a[0])+ - -1;}";
    try roundTrip(t.allocator, text);
    try roundTrip(t.allocator, "fn main()->i64{return 9223372036854775807 + 1;}");
    try roundTrip(t.allocator, "domain D:i64{fn make(x:i64)->D{return wrap<D>(x);}} fn main()->i64{return 0;}");
    try roundTrip(t.allocator, "fn main()->i64{ // empty comments\n// before return\nreturn 0;// after return\n// before close\n}\n// final\n");
}
// spec: TOOL-5
test "formatting accepts incomplete semantic work but rejects invalid syntax" {
    var c = try language.Compilation.init(t.allocator, "fmt.my", "fn unfinished()->Unknown{return missing;} ");
    defer c.deinit();
    const formatted = try c.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expect(c.program == null and c.code == null);
    try t.expectError(error.SourceError, c.check());
    var invalid = try language.Compilation.init(t.allocator, "invalid.my", "fn main() -> i64 { return +; }");
    defer invalid.deinit();
    try t.expectError(error.SourceError, invalid.format(t.allocator));
}
test "formatter handles empty and comment-only input canonically" {
    try roundTrip(t.allocator, "\n \t");
    try roundTrip(t.allocator, " // one\n\n// two");
}
fn failureScenario(allocator: std.mem.Allocator) !void {
    try roundTrip(allocator, "struct A{x:i64,y:i64} fn main()->i64{let a=new A{x:1,y:2}; // kept\nreturn a.x+a.y;}");
}
test "formatter parser comments output and idempotence release every failed allocation" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), failureScenario, .{});
}

fn moduleRoundTrip(allocator: std.mem.Allocator) !void {
    const text = "// header\r\nmodule app . main ;import missing . units as u;export Example;struct Example{value:u :: Value}\n" ++
        "fn unfinished(x:u // qualifier comment\n: // between colons\n:Value)->[2]u::Value{return missing(x);} // next export\nexport unfinished; // final export\n";
    var before = try language.Compilation.init(allocator, "draft.my", text);
    defer before.deinit();
    const formatted = try before.formatModule(allocator);
    defer allocator.free(formatted);
    var after = try language.Compilation.init(allocator, "draft.my", formatted);
    defer after.deinit();
    const twice = try after.formatModule(allocator);
    defer allocator.free(twice);
    try t.expectEqualStrings(formatted, twice);
    try t.expect(std.mem.indexOf(u8, formatted, "module app.main;\nimport missing.units as u;\nexport Example;") != null);
    try t.expect(std.mem.indexOf(u8, formatted, "value: u::Value") != null);
    try t.expect(std.mem.indexOf(u8, formatted, "-> [2]u::Value") != null);
    try t.expect(std.mem.indexOf(u8, formatted, "} // next export\nexport unfinished; // final export") != null);
    var sink_a: diagnostic.Sink = .{ .allocator = before.arena.allocator() };
    var sink_b: diagnostic.Sink = .{ .allocator = after.arena.allocator() };
    const a = try lexer.lex(sink_a.allocator, text, &sink_a);
    const b = try lexer.lex(sink_b.allocator, formatted, &sink_b);
    try t.expectEqual(a.len, b.len);
    for (a, b, 0..) |first, second, i| {
        try t.expectEqual(first.tag, second.tag);
        try t.expectEqualStrings(before.src.text(first.span), after.src.text(second.span));
        const a_start = if (i == 0) 0 else a[i - 1].span.end;
        const b_start = if (i == 0) 0 else b[i - 1].span.end;
        var old_lines = std.mem.splitScalar(u8, text[a_start..first.span.start], '\n');
        var new_lines = std.mem.splitScalar(u8, formatted[b_start..second.span.start], '\n');
        while (old_lines.next()) |line| {
            const comment = std.mem.indexOf(u8, line, "//") orelse continue;
            var found = false;
            while (new_lines.next()) |next| {
                const next_comment = std.mem.indexOf(u8, next, "//") orelse continue;
                try t.expectEqualStrings(std.mem.trimEnd(u8, line[comment..], "\r"), next[next_comment..]);
                found = true;
                break;
            }
            try t.expect(found);
        }
        while (new_lines.next()) |line| try t.expect(std.mem.indexOf(u8, line, "//") == null);
    }
    // Module formatting must not populate the single-file parser cache and bypass imports.
    before.check() catch |err| {
        if (err == error.OutOfMemory) return err;
        return t.expectEqual(error.SourceError, err);
    };
    return error.ExpectedSingleFileRejection;
}
test "module formatting preserves qualified names header order and comment gaps under allocation failure" {
    try moduleRoundTrip(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), moduleRoundTrip, .{});
}
test "module formatter rejects malformed headers and bodies but permits unresolved draft declarations" {
    for ([_][]const u8{ "module ;", "module main; import a..b;", "module main; export a; import b;", "module main; fn broken( ;", "module main; fn f(x:a:Type)->i64{return 0;}" }) |text| {
        var c = try language.Compilation.init(t.allocator, "bad.my", text);
        defer c.deinit();
        try t.expectError(error.SourceError, c.formatModule(t.allocator));
    }
    var c = try language.Compilation.init(t.allocator, "draft.my", "module differently_named; import absent as x; import other as x; export Missing; fn draft()->Unknown{return absent();}");
    defer c.deinit();
    const text = try c.formatModule(t.allocator);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "export Missing;") != null);
}
