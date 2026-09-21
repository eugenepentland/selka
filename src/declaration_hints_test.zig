//! The parser names the accepted spelling at the declaration forms an agent
//! writes first. One table holds those forms so the friction classifier can file
//! the same shapes; the agreement test here reads the classifier itself.
const std = @import("std");
const t = std.testing;
const diagnostic = @import("diagnostic.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const source = @import("source.zig");

/// The classifier the hint table is kept in step with, relative to the repository
/// root every `zig build` step runs from.
const classifier_path = "velocity/friction/classifier.json";
/// Candidate roots for the classifier, for a build started in a subdirectory.
const classifier_candidates = [_][]const u8{ classifier_path, "../" ++ classifier_path, "../../" ++ classifier_path };
/// The classifier is a small hand-written table; this bounds a runaway read.
const classifier_limit = 256 * 1024;

/// Parse one single-unit source and answer its first diagnostic from `arena`.
const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    sink: diagnostic.Sink,
    src: source.Source = undefined,

    fn init(allocator: std.mem.Allocator) Fixture {
        return .{ .arena = .init(allocator), .sink = .{ .allocator = allocator } };
    }

    fn deinit(self: *Fixture) void {
        self.arena.deinit();
    }

    /// Parse one single-unit source and answer its first diagnostic, which stays
    /// valid until `deinit` at the earliest.
    fn failure(self: *Fixture, bytes: []const u8) !*const diagnostic.Diagnostic {
        const allocator = self.arena.allocator();
        self.src = try source.Source.init(allocator, "hint.my", bytes);
        var sink: diagnostic.Sink = .{ .allocator = allocator };
        const tokens = try lexer.lex(allocator, bytes, &sink);
        var p: parser.Parser = .{ .src = self.src, .arena = &self.arena, .tokens = tokens, .sink = &sink };
        try t.expectError(error.SourceError, p.parse());
        self.sink = sink;
        return &self.sink.items.items[0];
    }
};

/// Assert one hint: its code, its message, the accepted spelling under the
/// counted `alternative` role, and the location the rejected token keeps.
fn expectHint(fixture: *const Fixture, failure: *const diagnostic.Diagnostic, message: []const u8, accepted: []const u8, line: usize, column: usize) !void {
    const at = fixture.src.locate(failure.span.start);
    try t.expectEqualStrings("E_SYNTAX", failure.code);
    try t.expectEqualStrings(message, failure.message);
    try t.expect(failure.related != null);
    try t.expectEqual(diagnostic.Role.alternative, failure.related.?.role);
    try t.expectEqualStrings(accepted, failure.related.?.message);
    try t.expectEqual(line, at.line);
    try t.expectEqual(column, at.column);
}

/// Assert one replacement note on a diagnostic whose code is not `E_SYNTAX`, so
/// it has no row in the declaration table: the code, the message and the counted
/// `alternative` note the failure carries.
fn expectAlternative(fixture: *const Fixture, failure: *const diagnostic.Diagnostic, code: []const u8, message: []const u8, accepted: []const u8) !void {
    const at = fixture.src.locate(failure.span.start);
    try t.expectEqualStrings(code, failure.code);
    try t.expectEqualStrings(message, failure.message);
    try t.expect(failure.related != null);
    try t.expectEqual(diagnostic.Role.alternative, failure.related.?.role);
    try t.expectEqualStrings(accepted, failure.related.?.message);
    try t.expect(at.line != 0);
}

/// Read the first candidate that exists. `error.ClassifierUnreadable` means the
/// table could not be checked at all: a failure, never a silent skip.
fn readFirst(allocator: std.mem.Allocator, candidates: []const []const u8) ![]u8 {
    for (candidates) |candidate| {
        const bytes = std.Io.Dir.cwd().readFileAlloc(t.io, candidate, allocator, .limited(classifier_limit)) catch continue;
        return bytes;
    }
    return error.ClassifierUnreadable;
}

/// The classifier document the agreement test reads.
fn readClassifier(allocator: std.mem.Allocator) ![]u8 {
    return readFirst(allocator, &classifier_candidates);
}

/// Whether some `E_SYNTAX` rule in the classifier files `idiom`.
fn classifierRulesHint(object: std.json.ObjectMap, idiom: []const u8) bool {
    const rules = object.get("rules") orelse return false;
    for (rules.array.items) |rule| {
        if (!std.mem.eql(u8, rule.object.get("code").?.string, "E_SYNTAX")) continue;
        if (std.mem.eql(u8, rule.object.get("idiom").?.string, idiom)) return true;
    }
    return false;
}

/// Assert that the classifier's `hints` array is exactly the parser's table, in
/// order, and that every hinted form has an `E_SYNTAX` rule behind it. A
/// classifier without the array fails on the assertion, never silently passes.
fn checkAgreement(root: std.json.Value) !void {
    const object = root.object;
    const listed = object.get("hints");
    try t.expect(listed != null);
    try t.expectEqual(parser.declaration_hints.len, listed.?.array.items.len);
    for (parser.declaration_hints, listed.?.array.items) |hint, entry| try t.expectEqualStrings(hint.idiom, entry.string);
    for (parser.declaration_hints) |hint| try t.expect(classifierRulesHint(object, hint.idiom));
}

/// Assert the table's own invariants: one row per form, in form order, each with
/// a distinct nonempty idiom.
fn checkTable() !void {
    for (parser.declaration_hints, 0..) |hint, index| {
        try t.expectEqual(@as(parser.HintForm, @fromBackingInt(@intCast(index))), hint.form);
        try t.expect(hint.idiom.len != 0);
        try t.expect(hint.message.len != 0);
        try t.expect(hint.accepted.len != 0);
    }
}

// spec: PARSER-HINT-1
test "a union or enum case without its comma names the rule and the fix" {
    var fixture = Fixture.init(t.allocator);
    defer fixture.deinit();
    const union_case = try fixture.failure(
        \\union Event:
        \\    heartbeat
        \\    count: int
        \\
    );
    try expectHint(&fixture, union_case, "union cases are separated by commas", "insert a comma after the previous case", 3, 5);
    const enum_case = try fixture.failure(
        \\enum Level:
        \\    debug
        \\    warning
        \\
    );
    try expectHint(&fixture, enum_case, "enum cases are separated by commas", "insert a comma after the previous case", 3, 5);
    const result_case = try fixture.failure(
        \\result Parse:
        \\    ok: int
        \\    err: str
        \\
    );
    try expectHint(&fixture, result_case, "result cases are separated by commas", "insert a comma after the previous case", 3, 5);
}

// spec: PARSER-HINT-2
test "a bare module-level assignment names the const declaration it needs" {
    var fixture = Fixture.init(t.allocator);
    defer fixture.deinit();
    const bare = try fixture.failure("MAX = 42\n");
    try expectHint(&fixture, bare, "a bare assignment declares no module-level binding", "declare it as a constant: const MAX: int = 42", 1, 1);
    const annotated = try fixture.failure("MAX: int = 42\n");
    try expectHint(&fixture, annotated, "a bare assignment declares no module-level binding", "declare it as a constant: const MAX: int = 42", 1, 1);
}

// spec: PARSER-HINT-3
test "a def inside a record or class body names the function that takes the record" {
    var fixture = Fixture.init(t.allocator);
    defer fixture.deinit();
    const after_field = try fixture.failure(
        \\record Point:
        \\    x: int
        \\    def norm1(self) -> int:
        \\        return self.x
        \\
    );
    try expectHint(&fixture, after_field, "a record or class body declares fields, not methods", "declare a top-level function taking the record: def norm1(p: Point) -> int", 3, 5);
    const first_member = try fixture.failure(
        \\class Point:
        \\    def __init__(self, x: int, y: int):
        \\        self.x = x
        \\
    );
    try expectHint(&fixture, first_member, "a record or class body declares fields, not methods", "declare a top-level function taking the record: def norm1(p: Point) -> int", 2, 5);
}

// spec: PARSER-HINT-4
test "a from-import names the accepted module import and record declaration" {
    var fixture = Fixture.init(t.allocator);
    defer fixture.deinit();
    const failure = try fixture.failure(
        \\from dataclasses import dataclass
        \\
        \\@dataclass
        \\class Point:
        \\    x: int
        \\
    );
    try expectHint(&fixture, failure, "a from-import is not a declaration", "import the module and declare a record: import dataclasses", 1, 1);
}

// spec: PARSER-HINT-6
test "a Python statement shape names its accepted spelling where the terminator belongs" {
    var fixture = Fixture.init(t.allocator);
    defer fixture.deinit();
    const target_list = "bind one name per statement and use a temporary variable; declare a record to return several values";
    const ternary = try fixture.failure("def main() -> int:\n    y = 42 if x > 0 else 0\n");
    try expectHint(&fixture, ternary, "a conditional expression is not part of the language", "write an if/else statement that assigns the same name", 2, 12);
    const inside_call = try fixture.failure("def main() -> int:\n    return int(1.5 if x else 0.0)\n");
    try expectHint(&fixture, inside_call, "a conditional expression is not part of the language", "write an if/else statement that assigns the same name", 2, 20);
    const swap = try fixture.failure("def main() -> int:\n    a = 1\n    b = 41\n    a, b = b, a\n");
    try expectHint(&fixture, swap, "a comma-separated target list declares no binding", target_list, 4, 6);
    const returning = try fixture.failure("def divmod2(a: int, b: int) -> int:\n    return a // b, a % b\n");
    try expectHint(&fixture, returning, "a comma-separated return list is not one value", target_list, 2, 18);
    const chained = try fixture.failure("def main() -> int:\n    x = y = 21\n    return x + y\n");
    try expectHint(&fixture, chained, "a chained assignment declares no binding", "assign one name per statement: `x = 21` first, then `y = 21`", 2, 11);
    const deletion = try fixture.failure("def main() -> int:\n    xs = [1]\n    del xs[0]\n    return 0\n");
    try expectHint(&fixture, deletion, "a del statement is not part of the language", "remove with `_ = xs.pop(index)` for a list or `_ = d.pop(key)` for a dictionary", 3, 9);
    const attempt = try fixture.failure("def main() -> int:\n    try:\n        x = 1\n    return 0\n");
    try expectHint(&fixture, attempt, "a try statement is not part of the language", "return `Result` and match it: `case Ok(value)` and `case Err(reason)`", 2, 8);
    const prefix = try fixture.failure("def main() -> int:\n    r = r\"a\\nb\"\n    return 0\n");
    try expectHint(&fixture, prefix, "a string prefix is not part of a literal", "drop the prefix and write the escape in an ordinary quoted string", 2, 10);
}

// spec: PARSER-HINT-8
test "a collection form Python spells differently names the loop it accepts" {
    var fixture = Fixture.init(t.allocator);
    defer fixture.deinit();
    const literal = try fixture.failure("def main() -> int:\n    seen = {1, 2, 2}\n    return 0\n");
    try expectHint(&fixture, literal, "a set literal is not a collection this language has", "use a dict literal keyed by the value: `{1: True, 2: True}`", 2, 14);
    const dict_comp = try fixture.failure("def main() -> int:\n    d = {x: x * x for x in range(4)}\n    return d[3]\n");
    try expectHint(&fixture, dict_comp, "a dict comprehension is not provided", "build the dictionary with a loop: `for x in range(4): d[x] = x * x`", 2, 19);
    const nested = try fixture.failure("def main() -> int:\n    grid = [[1]]\n    flat = [x for row in grid for x in row]\n    return 0\n");
    try expectHint(&fixture, nested, "a comprehension takes exactly one generator", "write the loops out and append: `for row in grid:` then `for x in row: flat.append(x)`", 3, 31);
    const generator = try fixture.failure("def main() -> int:\n    xs = [1, 2, 3]\n    if any(x > 2 for x in xs):\n        return 1\n    return 0\n");
    try expectHint(&fixture, generator, "a generator expression is not provided", "materialize a list instead: `any([x > 2 for x in xs])`", 3, 18);
}

// spec: PARSER-HINT-9
test "a case literal, an unwrap member, a walrus and a main guard name their accepted forms" {
    var fixture = Fixture.init(t.allocator);
    defer fixture.deinit();
    const literal = try fixture.failure("def main() -> int:\n    x = 3\n    match x:\n        case 1:\n            return 0\n        case _:\n            return 1\n");
    try expectHint(&fixture, literal, "a case names a union, enum or result case, not a literal", "compare literals with `if`/`elif`: `if x == 1:` then `elif x == 3:`", 4, 14);
    const unwrap = try fixture.failure("def main() -> int:\n    v = parse(\"42\").unwrap()\n    return v\n");
    try expectHint(&fixture, unwrap, "`unwrap` is a keyword here, not a method", "extract with `match`: `case Ok(value)` or `case Some(value)`; `?` propagates a `Result`", 2, 21);
    const walrus = try fixture.failure("def main() -> int:\n    xs = [1, 2, 3]\n    if (n := len(xs)) > 2:\n        return n\n    return 0\n");
    try expectHint(&fixture, walrus, "the walrus operator is not part of the language", "assign the name on its own line first, then test it", 3, 11);
    const guard = try fixture.failure("def main() -> int:\n    return 42\n\nif __name__ == \"__main__\":\n    main()\n");
    try expectHint(&fixture, guard, "a module has no `__name__` guard", "delete the guard: `mylang run` calls `def main()` directly", 4, 1);
}

// spec: PARSER-HINT-10
test "a Python form outside the declaration table still names its accepted spelling" {
    var fixture = Fixture.init(t.allocator);
    defer fixture.deinit();
    const loop_else = try fixture.failure("def main() -> int:\n    for x in [1, 2, 3]:\n        if x == 5:\n            break\n    else:\n        return 42\n    return 0\n");
    try expectAlternative(&fixture, loop_else, "E_EXPRESSION", "a loop has no `else` clause", "use a flag: assign it before the loop, set it before `break`, and test it after");
    const while_else = try fixture.failure("def main() -> int:\n    while False:\n        break\n    else:\n        return 1\n    return 0\n");
    try expectAlternative(&fixture, while_else, "E_EXPRESSION", "a loop has no `else` clause", "use a flag: assign it before the loop, set it before `break`, and test it after");
    const nested = try fixture.failure("def main() -> int:\n    def helper(x: int) -> int:\n        return x * 2\n    return helper(21)\n");
    try expectAlternative(&fixture, nested, "E_EXPRESSION", "a function body declares statements, not another function", "declare the function at the top level and call it from the body");
    const expression = try fixture.failure("def main() -> int:\n    v = match 1:\n        case 0: 1\n    return v\n");
    try expectAlternative(&fixture, expression, "E_EXPRESSION", "`match` is a statement, not an expression", "assign the value in each branch of an if/elif statement");
    const power = try fixture.failure("def main() -> int:\n    return 2 ** 5 + 10\n");
    try expectAlternative(&fixture, power, "E_EXPRESSION", "`**` is not an operator", "multiply in a loop: `total = 1` then `for i in range(exponent): total = total * base`");
    const shift = try fixture.failure("def main() -> int:\n    a = 1 << 4\n    return a\n");
    try expectAlternative(&fixture, shift, "E_EXPRESSION", "`<<` and `>>` are not operators", "use `shift_left(value, count)` or `shift_right(value, count)`");
}

// spec: PARSER-HINT-5
test "the hinted forms and the friction classifier name one table" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const text = try readClassifier(arena.allocator());
    const parsed = try std.json.parseFromSlice(std.json.Value, arena.allocator(), text, .{});
    try checkTable();
    try checkAgreement(parsed.value);
}

// The agreement check above must fail loudly when the classifier cannot be read
// at all: an unreadable table is a failure, never a silent pass.
test "an unreadable classifier fails the agreement check instead of skipping it" {
    try t.expectError(error.ClassifierUnreadable, readFirst(t.allocator, &.{"no/such/classifier.json"}));
}
