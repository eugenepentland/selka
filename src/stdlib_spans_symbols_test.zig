//! The `spans` and `symbols` modules through the embedded standard-library provider: a span outside its table and a symbol the table
//! did not make fail stop with `R_ASSERT` and a message that says why, and a program can read a span back through the table it was
//! numbered by. The behaviour of the accepted calls is tested in tests/lang/spans_and_sources.selka and tests/lang/symbol_tables.selka.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const fixture = @import("stdlib_fixture.zig");

/// Run `body` as the statements of a `main` that has a `Sources` named `sources` holding one file and a `Table` named `table`
/// holding one name, and require the `R_ASSERT` trap whose report holds `reason`.
fn faults(body: []const u8, reason: []const u8) !void {
    const source = try std.fmt.allocPrint(t.allocator,
        \\import spans
        \\import symbols
        \\func main() -> int:
        \\    mut sources = spans.create()
        \\    mut data = b"hello world"
        \\    const file = spans.add(mut sources, "greeting.txt", own data)
        \\    mut table = symbols.create()
        \\    const known = symbols.intern(mut table, b"hello")
        \\    {s}
        \\    return known.id + file
        \\
    , .{body});
    defer t.allocator.free(source);
    var program: language.embedded_project.Program = undefined;
    try fixture.load(&program, t.allocator, source);
    defer program.deinit();
    const outcome = try native.runWithOptions(&program.compilation, .{});
    try t.expect(outcome.trapped());
    try t.expectEqualStrings("R_ASSERT", outcome.trap.code);
    try t.expect(std.mem.indexOf(u8, outcome.stderr, reason) != null);
}

test "a span outside its table or its file traps R_ASSERT instead of reading the wrong text" {
    try faults("_ = spans.text(sources, spans.of(file, 6, 6))", "the span is outside its source");
    try faults("_ = spans.text(sources, spans.of(file + 1, 0, 1))", "the span is outside its source");
    try faults("_ = spans.hash(sources, spans.of(file, 0, 12))", "the span is outside its source");
    try faults("_ = spans.file_text(sources, 7)", "the file is not in the table");
    try faults("_ = spans.sub(spans.of(file, 0, 5), 3, 4)", "the sub-span is outside its span");
    try faults("_ = spans.join(spans.of(file, 0, 1), spans.of(file + 1, 0, 1))", "only spans of one file can be joined");
}

test "a symbol the table did not make traps R_ASSERT when its number is out of range" {
    try faults("_ = symbols.name(table, symbols.Symbol(id=5))", "the symbol does not belong to this table");
    try faults("_ = symbols.name(table, symbols.Symbol(id=-1))", "the symbol does not belong to this table");
}

test "a program reads a span through the table that numbered its file, and a symbol through its table" {
    try fixture.run(t.allocator,
        \\import spans
        \\import symbols
        \\func main() -> int:
        \\    mut sources = spans.create()
        \\    mut data = b"hello world"
        \\    const file = spans.add(mut sources, "greeting.txt", own data)
        \\    mut table = symbols.create()
        \\    const word = symbols.intern_span(mut table, sources, spans.of(file, 6, 5))
        \\    if spans.text(sources, spans.of(file, 6, 5)) != b"world" or symbols.name(table, word) != b"world":
        \\        return 1
        \\    return 42
    , 42);
}
