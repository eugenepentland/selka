//! Syntax, parameter modes and types for `own`. Core owns transfer eligibility,
//! move requirements and borrow checks in core/own_arguments_test.zig.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const fixture = @import("stdlib_fixture.zig");
const own_parameters = @import("own_parameters.zig");

/// `text` with the entry point a whole-program check needs, so a fixture states
/// only the shape it judges.
fn withEntry(text: []const u8) ![]const u8 {
    return std.mem.concat(t.allocator, u8, &.{ text, "\n\nfunc main() -> int:\n    return 0\n" });
}

/// Check a program that must be accepted.
fn accepted(text: []const u8) !void {
    const source = try withEntry(text);
    defer t.allocator.free(source);
    var compilation = try language.Compilation.init(t.allocator, "own.selka", source);
    defer compilation.deinit();
    try compilation.check();
    try t.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
}

/// Check a program that must be rejected with `code` and exactly `message`.
fn expectRejected(text: []const u8, code: []const u8, message: []const u8) !void {
    const source = try withEntry(text);
    defer t.allocator.free(source);
    var compilation = try language.Compilation.init(t.allocator, "own.selka", source);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
    try t.expectEqualStrings(message, compilation.diagnostics.items[0].message);
}

test "own is a contextual word: a binding and a field named own still check" {
    try accepted(
        \\record Pair:
        \\    own: int
        \\
        \\
        \\func plain(value: int) -> int:
        \\    return value
        \\
        \\
        \\public func test_own_name() -> bool:
        \\    const own = 3
        \\    mut pair = Pair(own=own)
        \\    return plain(own) == 3 and pair.own == 3
    );
}

test "own and mut do not combine on a parameter" {
    try expectRejected(
        \\func bump(own mut value: int) -> int:
        \\    return value
    , "E_PARAMETER_MODIFIER", "a parameter takes its value `own` or writes it `mut`, not both");
    try expectRejected(
        \\func bump(mut own value: int) -> int:
        \\    return value
    , "E_PARAMETER_MODIFIER", "a parameter takes its value `own` or writes it `mut`, not both");
}

test "own and mut do not combine on a call argument" {
    try expectRejected(
        \\func my_take(own keys: int[]) -> int:
        \\    return len(keys)
        \\
        \\
        \\func use() -> int:
        \\    mut samples = [1, 2]
        \\    return my_take(own mut samples)
    , "E_PARAMETER_MODIFIER", "a value has one `own` marker; `own` and `mut` do not combine");
}

test "a function type spells the mode and a mismatch is refused" {
    try accepted(
        \\func first_of(own keys: int[]) -> int:
        \\    return keys[0]
        \\
        \\
        \\public func test_type() -> bool:
        \\    const apply: func(own int[]) -> int = first_of
        \\    mut samples = [5, 6]
        \\    return apply(own samples) == 5
    );
    try expectRejected(
        \\func first_of(own keys: int[]) -> int:
        \\    return keys[0]
        \\
        \\
        \\public func test_type() -> bool:
        \\    const apply: func(int[]) -> int = first_of
        \\    mut samples = [5, 6]
        \\    return apply(samples) == 5
    , "E_TYPE", "expected func(int[]) -> int, found func(own int[]) -> int");
}

test "the receiver of append is written, so own becomes mut" {
    const text =
        // migrate-embedded: skip original ownership-marker or move-only parameter diagnostic and repair witness
        \\public func test_append() -> bool:
        \\    mut rows: int[] = []
        \\    append(own rows, 1)
        \\    return len(rows) == 1
    ;
    const source = try withEntry(text);
    defer t.allocator.free(source);
    var compilation = try language.Compilation.init(t.allocator, "own.selka", source);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const item = compilation.diagnostics.items[0];
    try t.expectEqualStrings("E_OWN_MARKER", item.code);
    try t.expectEqualStrings("`append` writes `rows`, so it borrows it `mut` instead of taking it `own`", item.message);
    try t.expectEqual(language.ownership_rules.Rule.W2, item.provenance.rule.?);
    const fix = item.provenance.fix orelse return error.TestExpectedEqual;
    try t.expectEqual(@as(usize, 1), fix.count());
    const start = std.mem.indexOf(u8, source, "own rows").?;
    try t.expectEqual(start, fix.edit.span.start);
    try t.expectEqual(start + "own ".len, fix.edit.span.end);
    try t.expectEqualStrings("mut ", fix.edit.text);
    const repaired = try std.mem.concat(t.allocator, u8, &.{ source[0..fix.edit.span.start], fix.edit.text, source[fix.edit.span.end..] });
    defer t.allocator.free(repaired);
    const expected = try std.mem.replaceOwned(u8, t.allocator, source, "append(own rows, 1)", "append(mut rows, 1)");
    defer t.allocator.free(expected);
    try t.expectEqualStrings(expected, repaired);
    var accepted_fix = try language.Compilation.init(t.allocator, "own.selka", repaired);
    defer accepted_fix.deinit();
    try accepted_fix.check();
    try t.expectEqual(@as(usize, 0), accepted_fix.diagnostics.items.len);
}

/// The first diagnostic a project check reports for `text`, whose entry is
/// `main.selka` with a `main` appended, with its repair edit when it has one.
fn firstProjectDiagnostic(arena: std.mem.Allocator, text: []const u8) !fixture.Report {
    const report = try fixture.check(arena, text);
    try t.expect(!report.passed);
    return report;
}

test "a plain parameter of a move-only type is refused, and its repair writes own" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const text = "import network\n\n\nfunc keep(listener: network.Listener) -> int:\n    return 0\n\n\nfunc main() -> int:\n    return 0\n";
    const report = try firstProjectDiagnostic(arena.allocator(), text);
    try t.expectEqualStrings("E_OWN_PARAMETER", report.diagnostics[0].code);
    try t.expectEqualStrings("`listener` is a `network.Listener`: a plain parameter would take it without saying so; declare `own listener` to take it or `mut listener` to borrow it", report.diagnostics[0].message);
    const fix = report.diagnostics[0].provenance.fix orelse return error.TestExpectedEqual;
    try t.expectEqualStrings("own ", fix.edit.text);
    try t.expectEqual(std.mem.indexOf(u8, text, "listener:").?, fix.edit.span.start);
    try t.expectEqual(fix.edit.span.start, fix.edit.span.end);
}

test "a mut or own parameter of a move-only type is not a hidden transfer" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try fixture.accept(arena.allocator(),
        \\import network
        \\
        \\
        \\func borrow(mut listener: network.Listener) -> int:
        \\    return 0
        \\
        \\
        \\func keep(own listener: network.Listener) -> int:
        \\    return 0
        \\
        \\
        \\func main() -> int:
        \\    return 0
        \\
    );
}

test "a function type's plain move-only position is refused, and its repair writes own in the type" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const text = "import network\n\n\nfunc apply(f: func(network.Listener) -> int) -> int:\n    return 0\n\n\nfunc main() -> int:\n    return 0\n";
    const report = try firstProjectDiagnostic(arena.allocator(), text);
    try t.expectEqualStrings("E_OWN_PARAMETER", report.diagnostics[0].code);
    try t.expectEqualStrings("a plain parameter of this function type would take a `network.Listener` without saying so; write `own` before it to take it or `mut` to borrow it", report.diagnostics[0].message);
    const fix = report.diagnostics[0].provenance.fix orelse return error.TestExpectedEqual;
    try t.expectEqualStrings("own ", fix.edit.text);
    try t.expectEqual(std.mem.indexOf(u8, text, "network.Listener) ->").?, fix.edit.span.start);
}

test "a named function type position takes own before its name" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const text = "import network\n\n\nfunc apply(f: func(named l: network.Listener) -> int) -> int:\n    return 0\n\n\nfunc main() -> int:\n    return 0\n";
    const report = try firstProjectDiagnostic(arena.allocator(), text);
    try t.expectEqualStrings("E_OWN_PARAMETER", report.diagnostics[0].code);
    const fix = report.diagnostics[0].provenance.fix orelse return error.TestExpectedEqual;
    try t.expectEqualStrings("own ", fix.edit.text);
    try t.expectEqual(std.mem.indexOf(u8, text, "l: network.Listener").?, fix.edit.span.start);
}

/// The first diagnostic with `code` in a project report; the test fails when none.
fn projectDiagnostic(report: fixture.Report, code: []const u8) !language.diagnostic.Diagnostic {
    for (report.diagnostics) |item| if (std.mem.eql(u8, item.code, code)) return item;
    return error.TestExpectedEqual;
}

test "a concrete move-only parameter of a generic function is refused with its certain edit" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    // Only an instance is checked, so the generic function is called once.
    const text = "import network\n\n\n" ++
        "func keep[T](value: T, listener: network.Listener) -> int:\n    return 0\n\n\n" ++
        "func use(net: Network) -> int:\n    match network.listen(net):\n" ++
        "        case ok(listener):\n            return keep[int](1, listener)\n" ++
        "        case err(code):\n            return code\n\n\n" ++
        "func main() -> int:\n    return 0\n";
    const report = try firstProjectDiagnostic(arena.allocator(), text);
    const item = try projectDiagnostic(report, "E_OWN_PARAMETER");
    const fix = item.provenance.fix orelse return error.TestExpectedEqual;
    try t.expectEqualStrings("own ", fix.edit.text);
    try t.expectEqual(std.mem.indexOf(u8, text, "listener: network").?, fix.edit.span.start);
}

test "a record field or enum payload of function type refuses a move-only plain position" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const record_text = "import network\n\n\nrecord Hook:\n    run: func(network.Listener) -> int\n\n\nfunc main() -> int:\n    return 0\n";
    const record_report = try firstProjectDiagnostic(arena.allocator(), record_text);
    const record_item = try projectDiagnostic(record_report, "E_OWN_PARAMETER");
    const record_fix = record_item.provenance.fix orelse return error.TestExpectedEqual;
    try t.expectEqualStrings("own ", record_fix.edit.text);
    try t.expectEqual(std.mem.indexOf(u8, record_text, "network.Listener) ->").?, record_fix.edit.span.start);
    const enum_text = "import network\n\n\nenum Hook:\n    idle\n    run(callback: func(network.Listener) -> int)\n\n\nfunc main() -> int:\n    return 0\n";
    const enum_report = try firstProjectDiagnostic(arena.allocator(), enum_text);
    const enum_item = try projectDiagnostic(enum_report, "E_OWN_PARAMETER");
    try t.expect(enum_item.provenance.fix != null);
}

test "a generic function's concrete move-only parameter takes its edit beside a type parameter" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    // `value: T` is not refused: its type is a type parameter, not a resource.
    // The resource parameter beside it is refused with its own certain edit.
    const report = try firstProjectDiagnostic(arena.allocator(),
        // migrate-embedded: skip original ownership-marker or move-only parameter diagnostic and repair witness
        \\import network
        \\
        \\
        \\func keep[T](value: T, listener: network.Listener) -> int:
        \\    return 0
        \\
        \\
        \\func use(net: Network) -> int:
        \\    match network.listen(net):
        \\        case ok(listener):
        \\            return keep[int](1, listener)
        \\        case err(code):
        \\            return code
        \\
        \\
        \\func main() -> int:
        \\    return 0
        \\
    );
    const item = try projectDiagnostic(report, "E_OWN_PARAMETER");
    try t.expect(item.provenance.fix != null);
    try t.expectEqualStrings("`listener` is a `network.Listener`: a plain parameter would take it without saying so; declare `own listener` to take it or `mut listener` to borrow it", item.message);
}

test "a function type prints its own positions in a mismatch" {
    try expectRejected(
        \\func apply(f: func(own str[]) -> int, own xs: str[]) -> int:
        \\    return f(own xs)
        \\
        \\
        \\func peek(xs: str[]) -> int:
        \\    return len(xs)
        \\
        \\
        \\func use() -> int:
        \\    mut ys: str[] = ["a"]
        \\    return apply(peek, own ys)
    , "E_TYPE", "expected func(own str[]) -> int, found func(str[]) -> int");
}

test "a parameter type that names a type parameter is matched as a whole word" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const src = try @import("source.zig").Source.init(arena.allocator(), "names.selka", "Holder[T] Tree[T1] TT");
    const parameters = [_]@import("ast.zig").TypeParameter{.{ .name = .{ .start = 7, .end = 8 }, .requirements = &.{} }};
    try t.expect(own_parameters.mentionsTypeParameter(src, .{ .start = 0, .end = 9 }, &parameters));
    try t.expect(!own_parameters.mentionsTypeParameter(src, .{ .start = 10, .end = 18 }, &parameters));
    try t.expect(!own_parameters.mentionsTypeParameter(src, .{ .start = 19, .end = 21 }, &parameters));
}

test "a mut marker at an own position changes mode before Core judges the transfer" {
    try expectRejected(
        // migrate-embedded: skip original ownership-marker or move-only parameter diagnostic and repair witness
        \\func my_take(own s: str) -> int:
        \\    return len(s)
        \\func keep(s: str) -> int:
        \\    return my_take(mut s)
    , "E_OWN_MARKER", "`my_take` takes `s`; write `own s` instead of `mut`");
}
