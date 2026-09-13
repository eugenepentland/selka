//! `fmt` validates syntax and returns the accepted program unchanged, because
//! indentation already is the canonical layout of a program the parser accepts.
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
    try t.expectEqualStrings(text, formatted);
    var after = try language.Compilation.init(allocator, "after.my", formatted);
    defer after.deinit();
    const twice = try after.format(allocator);
    defer allocator.free(twice);
    try t.expectEqualStrings(formatted, twice);
}

// spec: TOOL-5
test "formatting accepts incomplete semantic work but rejects invalid syntax" {
    var c = try language.Compilation.init(t.allocator, "fmt.my",
        \\def unfinished() -> Unknown:
        \\    return missing
    );
    defer c.deinit();
    const formatted = try c.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expect(c.program == null and c.code == null);
    try t.expectError(error.SourceError, c.check());
    var invalid = try language.Compilation.init(t.allocator, "invalid.my",
        \\def main() -> i64:
        \\    return +
    );
    defer invalid.deinit();
    try t.expectError(error.SourceError, invalid.format(t.allocator));
}

// spec-case: TOOL-5
test "an accepted program is its own canonical text, comments and blank lines included" {
    const text =
        \\# heading
        \\def main() -> i64: # body
        \\    x = 1 # value
        \\    # return note
        \\    return x + 2 # end
    ;
    try roundTrip(t.allocator, text);
    var c = try language.Compilation.init(t.allocator, "fmt.my", text);
    defer c.deinit();
    try t.expectEqual(@as(i64, 3), (try c.execute(t.allocator)).value);
}

test "formatter handles empty and comment-only input canonically" {
    try roundTrip(t.allocator, "\n \t");
    try roundTrip(t.allocator, " # one\n\n# two");
}

fn failureScenario(allocator: std.mem.Allocator) !void {
    try roundTrip(allocator,
        \\class A:
        \\    x: i64
        \\    y: i64
        \\
        \\
        \\def main() -> i64:
        \\    a = A(x=1, y=2) # kept
        \\    return a.x + a.y
    );
}

test "formatter parser output and idempotence release every failed allocation" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), failureScenario, .{});
}

fn moduleRoundTrip(allocator: std.mem.Allocator) !void {
    const text =
        \\# header
        \\module app.main
        \\import missing.units as u
        \\export Example
        \\export unfinished
        \\
        \\
        \\class Example:
        \\    value: u.Value
        \\
        \\
        \\def unfinished(x: u.Value) -> [2]u.Value: # draft
        \\    return missing(x)
    ;
    var before = try language.Compilation.init(allocator, "draft.my", text);
    defer before.deinit();
    const formatted = try before.formatModule(allocator);
    defer allocator.free(formatted);
    try t.expectEqualStrings(text, formatted);
    var after = try language.Compilation.init(allocator, "draft.my", formatted);
    defer after.deinit();
    const twice = try after.formatModule(allocator);
    defer allocator.free(twice);
    try t.expectEqualStrings(formatted, twice);
    var sink: diagnostic.Sink = .{ .allocator = before.arena.allocator() };
    const tokens = try lexer.lex(sink.allocator, text, &sink);
    try t.expect(tokens.len != 0);
    // Module formatting must not populate the single-file parser cache and bypass imports.
    before.check() catch |err| {
        if (err == error.OutOfMemory) return err;
        return t.expectEqual(error.SourceError, err);
    };
    return error.ExpectedSingleFileRejection;
}

test "module formatting preserves the module header and draft declarations under allocation failure" {
    try moduleRoundTrip(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), moduleRoundTrip, .{});
}

test "module formatter rejects malformed headers and bodies but permits unresolved draft declarations" {
    for ([_][]const u8{
        "module\n",
        "module main\nimport a..b\n",
        "module main\nexport a\nimport b\n",
        "module main\n\n\ndef broken(\n",
    }) |text| {
        var c = try language.Compilation.init(t.allocator, "bad.my", text);
        defer c.deinit();
        try t.expectError(error.SourceError, c.formatModule(t.allocator));
    }
    var c = try language.Compilation.init(t.allocator, "draft.my",
        \\module differently_named
        \\import absent as x
        \\import other as x
        \\export Missing
        \\
        \\
        \\def draft() -> Unknown:
        \\    return absent()
    );
    defer c.deinit();
    const text = try c.formatModule(t.allocator);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "export Missing") != null);
}
