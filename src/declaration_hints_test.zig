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
const classifier_path = "tools/friction/classifier.json";
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

    /// Parse one single-unit source that must be accepted.
    fn parses(self: *Fixture, bytes: []const u8) !void {
        const allocator = self.arena.allocator();
        self.src = try source.Source.init(allocator, "hint.selka", bytes);
        const tokens = try lexer.lex(allocator, bytes, &self.sink);
        var p: parser.Parser = .{ .src = self.src, .storage = allocator, .tokens = tokens, .sink = &self.sink };
        _ = try p.parse();
    }

    /// Parse one single-unit source and answer its first diagnostic, which stays
    /// valid until `deinit` at the earliest.
    fn failure(self: *Fixture, bytes: []const u8) !*const diagnostic.Diagnostic {
        const allocator = self.arena.allocator();
        self.src = try source.Source.init(allocator, "hint.selka", bytes);
        var sink: diagnostic.Sink = .{ .allocator = allocator };
        const tokens = try lexer.lex(allocator, bytes, &sink);
        var p: parser.Parser = .{ .src = self.src, .storage = self.arena.allocator(), .tokens = tokens, .sink = &sink };
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
        try t.expect(hint.example.len != 0);
    }
}

// spec: PARSER-HINT-1
test "enum and nominal result cases accept one case per line" {
    var fixture = Fixture.init(t.allocator);
    defer fixture.deinit();
    try fixture.parses("enum Event:\n    heartbeat\n    count(value: int)\n");
    try fixture.parses("result Parse:\n    ok: int\n    err: str\n");
}

// spec: PARSER-HINT-2
test "a bare module-level assignment names the const declaration it needs" {
    var fixture = Fixture.init(t.allocator);
    defer fixture.deinit();
    const bare = try fixture.failure("MAX = 42\n");
    try expectHint(&fixture, bare, "a bare assignment declares no module-level binding", "declare it as a constant: `const MAX: int = 42`", 1, 1);
    const annotated = try fixture.failure("MAX: int = 42\n");
    try expectHint(&fixture, annotated, "a bare assignment declares no module-level binding", "declare it as a constant: `const MAX: int = 42`", 1, 1);
}

// spec: PARSER-HINT-3
test "a func inside a record or class body names the function that takes the record" {
    var fixture = Fixture.init(t.allocator);
    defer fixture.deinit();
    const after_field = try fixture.failure(
        \\record Point:
        \\    x: int
        \\    func norm1(self) -> int:
        \\        return self.x
        \\
    );
    try expectHint(&fixture, after_field, "a record or class body declares fields, not methods", "declare a top-level function taking the record: `func norm1(p: Point) -> int`", 3, 5);
    const first_member = try fixture.failure(
        \\class Point:
        \\    func __init__(self, x: int, y: int):
        \\        self.x = x
        \\
    );
    try expectHint(&fixture, first_member, "a record or class body declares fields, not methods", "declare a top-level function taking the record: `func norm1(p: Point) -> int`", 2, 5);
}

// spec: PARSER-HINT-4
test "a from-import names the module import, the type alias and the module alias" {
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
    try expectHint(&fixture, failure, "a from-import is not a declaration", "import the module and use its names, as in `binary.Error`; `type Failure = binary.Error` or `import binary as b` shortens it", 1, 1);
}

// spec: PARSER-HINT-6
test "a Python statement shape names its accepted spelling where the terminator belongs" {
    var fixture = Fixture.init(t.allocator);
    defer fixture.deinit();
    const chained = try fixture.failure("func main() -> int:\n    x = y = 21\n    return x + y\n");
    try expectHint(&fixture, chained, "a chained assignment declares no binding", "declare one name per statement: `const x = 21` first, then `const y = 21`", 2, 11);
    const deletion = try fixture.failure("func main() -> int:\n    xs = [1]\n    del xs[0]\n    return 0\n");
    try expectHint(&fixture, deletion, "a del statement is not part of the language", "remove with `lists.pop_at(mut xs, index)` for a list or `dicts.pop(mut d, key)` for a dictionary", 3, 9);
    const attempt = try fixture.failure("func main() -> int:\n    try:\n        x = 1\n    return 0\n");
    try expectHint(&fixture, attempt, "a try statement is not part of the language", "declare the function `-> int fails str` and match its call: `case Ok(value)` and `case Err(reason)`", 2, 8);
    const prefix = try fixture.failure("func main() -> int:\n    r = r\"a\\nb\"\n    return 0\n");
    try expectHint(&fixture, prefix, "a string prefix is not part of a literal", "drop the prefix and write the escape in an ordinary quoted string", 2, 10);
}

// spec: PARSER-HINT-8
test "the collection forms the parser once hinted now parse into the program they mean" {
    var fixture = Fixture.init(t.allocator);
    defer fixture.deinit();
    const forms = [_][]const u8{
        "func main() -> int:\n    mut seen = {1, 2, 2}\n    return 0\n",
        // migrate-embedded: skip parser-only legacy collection-form recognition
        "func main() -> int:\n    mut d = {x: x * x for x in range(4)}\n    return d[3]\n",
        "func main() -> int:\n    mut grid = [[1]]\n    mut flat: int[] = []\n    for row in grid:\n        for x in row:\n            append(mut flat, x)\n    return 0\n",
        // migrate-embedded: skip parser-only legacy collection-form recognition
        "func main() -> int:\n    mut xs = [1, 2, 3]\n    if any(x > 2 for x in xs):\n        return 1\n    return 0\n",
    };
    for (forms) |bytes| try fixture.parses(bytes);
    try t.expectEqual(@as(usize, 0), fixture.sink.items.items.len);
}

// spec: PARSER-HINT-9
test "a case literal, an unwrap member, a walrus and a main guard name their accepted forms" {
    var fixture = Fixture.init(t.allocator);
    defer fixture.deinit();
    const literal = try fixture.failure("func main() -> int:\n    const found = Some(3)\n    match found:\n        case Some(3):\n            return 0\n        case None:\n            return 1\n");
    try expectHint(&fixture, literal, "a literal is a whole match arm, not a case payload", "match the literal as its own arm of a match on an int, str, bytes or bool: `case 1:`", 4, 19);
    const unwrap = try fixture.failure("func main() -> int:\n    v = parse(\"42\").unwrap()\n    return v\n");
    try expectHint(&fixture, unwrap, "`unwrap` is not a method", "extract with `match`: `case Ok(value)` or `case Some(value)`; prefix `try` propagates a result", 2, 21);
    const walrus = try fixture.failure("func main() -> int:\n    xs = [1, 2, 3]\n    if (n := len(xs)) > 2:\n        return n\n    return 0\n");
    try expectHint(&fixture, walrus, "the walrus operator is not part of the language", "assign the name on its own line first, then test it", 3, 11);
    const guard = try fixture.failure("func main() -> int:\n    return 42\n\nif __name__ == \"__main__\":\n    main()\n");
    try expectHint(&fixture, guard, "a module has no `__name__` guard", "delete the guard: running the module calls `func main()` directly", 4, 1);
}

// spec: PARSER-HINT-10
test "a Python form outside the declaration table still names its accepted spelling" {
    var fixture = Fixture.init(t.allocator);
    defer fixture.deinit();
    const loop_else = try fixture.failure("func main() -> int:\n    for x in [1, 2, 3]:\n        if x == 5:\n            break\n    else:\n        return 42\n    return 0\n");
    try expectAlternative(&fixture, loop_else, "E_EXPRESSION", "a loop has no `else` clause", "use a flag: assign it before the loop, set it before `break`, and test it after");
    const while_else = try fixture.failure("func main() -> int:\n    while False:\n        break\n    else:\n        return 1\n    return 0\n");
    try expectAlternative(&fixture, while_else, "E_EXPRESSION", "a loop has no `else` clause", "use a flag: assign it before the loop, set it before `break`, and test it after");
    const nested = try fixture.failure("func main() -> int:\n    func helper(x: int) -> int:\n        return x * 2\n    return helper(21)\n");
    try expectAlternative(&fixture, nested, "E_EXPRESSION", "a function body declares statements, not another function", "declare the function at the top level and call it from the body");
    const power = try fixture.failure("func main() -> int:\n    return 2 ** 5 + 10\n");
    try expectAlternative(&fixture, power, "E_EXPRESSION", "`**` is not an operator", "multiply in a loop: `mut total = 1` then `for i in range(exponent): total = total * base`");
    const shift = try fixture.failure("func main() -> int:\n    a = 1 << 4\n    return a\n");
    try expectAlternative(&fixture, shift, "E_EXPRESSION", "`<<` and `>>` are not operators", "use `shift_left(value, count)` or `shift_right(value, count)`");
}

// SP1B-F-4: `>>` and `<<` are answered alike, and so are the augmented spellings and the other operators an author coming from C
// writes: each says what the form is not and names the call or statement that does the job, at the token where the parse failed
// (the pair for `--`, which fails on the line after it).
test "the shifts and the C operators name what to write instead" {
    var fixture = Fixture.init(t.allocator);
    defer fixture.deinit();
    const shift = "use `shift_left(value, count)` or `shift_right(value, count)`";
    const augmented = "rebind a set with the operator, `s = s | t`, or call `s.update(t)`; combine integers with `x = bit_or(x, y)`, `bit_and` or `bit_xor`";
    const cases = [_]struct { body: []const u8, message: []const u8, accepted: []const u8, text: []const u8 }{
        .{ .body = "    return x >> 2\n", .message = "`<<` and `>>` are not operators", .accepted = shift, .text = ">" },
        .{ .body = "    return x << 2\n", .message = "`<<` and `>>` are not operators", .accepted = shift, .text = "<" },
        .{ .body = "    x >>= 1\n    return x\n", .message = "`<<` and `>>` are not operators", .accepted = shift, .text = ">=" },
        .{ .body = "    x <<= 1\n    return x\n", .message = "`<<` and `>>` are not operators", .accepted = shift, .text = "<=" },
        .{ .body = "    x **= 2\n    return x\n", .message = "`**` is not an operator", .accepted = "multiply in a loop: `mut total = 1` then `for i in range(exponent): total = total * base`", .text = "*=" },
        .{ .body = "    x++\n    return x\n", .message = "`++` and `--` are not operators", .accepted = "add or subtract one with `x += 1` or `x -= 1`", .text = "+" },
        .{ .body = "    ++x\n    return x\n", .message = "`++` and `--` are not operators", .accepted = "add or subtract one with `x += 1` or `x -= 1`", .text = "+" },
        .{ .body = "    x--\n    return x\n", .message = "`++` and `--` are not operators", .accepted = "add or subtract one with `x += 1` or `x -= 1`", .text = "--" },
        .{ .body = "    x |= 3\n    return x\n", .message = "`&=`, `|=` and `^=` are not operators", .accepted = augmented, .text = "=" },
    };
    for (cases) |case| {
        const bytes = try std.fmt.allocPrint(t.allocator, "func main() -> int:\n    mut x = 5\n{s}", .{case.body});
        defer t.allocator.free(bytes);
        const found = try fixture.failure(bytes);
        try expectAlternative(&fixture, found, "E_EXPRESSION", case.message, case.accepted);
        try t.expectEqualStrings(case.text, fixture.src.text(found.span));
    }
}

// SP1B-F-4: `a ? b : c` reads `a?` and then fails at `b`; the refusal says `?` only passes a failure on and names the statement
// forms, and a statement that is `f()?` alone is still accepted.
test "a question mark conditional says what the question mark does" {
    var fixture = Fixture.init(t.allocator);
    defer fixture.deinit();
    const found = try fixture.failure("func main() -> int:\n    const a = True\n    const z = a ? 1 : 2\n    return z\n");
    try expectHint(&fixture, found, "`a ? b : c` is not a conditional, and `?` after a value only passes its failure on (`f()?`)", //
        "declare the result first, assign it in an `if`/`else` statement or a `match`, or return in each arm", 3, 19);
    try fixture.parses("func main() -> int:\n    return 1\n");
}

// MSG-G: the same refusal where the conditional stands inside a bracket (the arguments of a call, a parenthesis, a list, an index, a dictionary
// value), where the parser used to stop with "unexpected token; expected )" at the same token. A declaration that ends in `?` and goes on
// (`x: int? y: int`) is no conditional and keeps its text.
test "a question mark conditional inside brackets says what the question mark does" {
    const cases = [_]struct { body: []const u8, at: []const u8 }{
        .{ .body = "const z = f(a ? 1 : 2)", .at = "1" },
        .{ .body = "const z = f(g(a ? 1 : 2))", .at = "1" },
        .{ .body = "const z = f(1, a ? 1 : 2)", .at = "1" },
        .{ .body = "const z = f(a ? \"y\" : \"n\")", .at = "\"y\"" },
        .{ .body = "const z = f(a ? b : c)", .at = "b" },
        .{ .body = "const z = text.strip(a ? 1 : 2)", .at = "1" },
        .{ .body = "const z = [a ? 1 : 2]", .at = "1" },
        .{ .body = "const z = (a ? 1 : 2)", .at = "1" },
        .{ .body = "const z = (1, a ? 1 : 2)", .at = "1" },
        .{ .body = "const z = {\"k\": a ? 1 : 2}", .at = "1" },
        .{ .body = "const z = [1, 2][a ? 1 : 0]", .at = "1" },
    };
    for (cases) |case| {
        var fixture = Fixture.init(t.allocator);
        defer fixture.deinit();
        const bytes = try std.fmt.allocPrint(t.allocator, "func main() -> int:\n    const a = True\n    {s}\n    return 0\n", .{case.body});
        defer t.allocator.free(bytes);
        const found = try fixture.failure(bytes);
        try expectAlternative(&fixture, found, "E_SYNTAX", "`a ? b : c` is not a conditional, and `?` after a value only passes its failure on (`f()?`)", //
            "declare the result first, assign it in an `if`/`else` statement or a `match`, or return in each arm");
        try t.expectEqualStrings(case.at, fixture.src.text(found.span));
        try t.expectEqual(@as(usize, 3), fixture.src.locate(found.span.start).line);
    }
    var kept = Fixture.init(t.allocator);
    defer kept.deinit();
    try kept.parses("func main() -> int:\n    const z = f(1, [2], (3, 4), {\"k\": 5})\n    return 0\n");
    const declared = try kept.failure("func f(x: int? y: int) -> int:\n    return 0\n");
    try t.expectEqualStrings("unexpected token; expected )", declared.message);
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

// SP1-F-3, W3-F-4: a top-level `const NAME = value` is the line an agent writes because a function takes it, and the
// message says the module constant needs its type; a plain literal gets the line as it should be and the edit that
// inserts the type after the name, any other value gets the form.
test "a module constant written without its type says it needs one and repairs a plain literal" {
    var fixture = Fixture.init(t.allocator);
    defer fixture.deinit();
    const cases = [_]struct { source: []const u8, ty: []const u8, line: []const u8 }{
        .{ .source = "const X = 1\n", .ty = "int", .line = "const X: int = 1" },
        .{ .source = "public const NONEXIST = -1\n", .ty = "int", .line = "const NONEXIST: int = -1" },
        .{ .source = "const RATIO = 0.5\n", .ty = "float", .line = "const RATIO: float = 0.5" },
        .{ .source = "const D = \"d\"\n", .ty = "str", .line = "const D: str = \"d\"" },
        .{ .source = "const ON = True\n", .ty = "bool", .line = "const ON: bool = True" },
    };
    for (cases) |case| {
        const failure = try fixture.failure(case.source);
        const message = try std.fmt.allocPrint(fixture.arena.allocator(), "a module constant needs its type: write `{s}`", .{case.line});
        try t.expectEqualStrings("E_SYNTAX", failure.code);
        try t.expectEqualStrings(message, failure.message);
        const name_end = std.mem.indexOfScalar(u8, case.source, '=').? - 1;
        try t.expectEqual(name_end + 1, failure.span.start);
        const edit = failure.provenance.fix.?.edit;
        try t.expectEqual(name_end, edit.span.start);
        try t.expectEqual(name_end, edit.span.end);
        try t.expectEqualStrings(try std.fmt.allocPrint(fixture.arena.allocator(), ": {s}", .{case.ty}), edit.text);
    }
}

test "a module constant of any other value gets the form to fill in and no edit" {
    var fixture = Fixture.init(t.allocator);
    defer fixture.deinit();
    const sources = [_][]const u8{
        "const LIMIT = 2 * 8\n",
        "const BIG = 1u8\n",
        "const TOO_BIG = 99999999999999999999\n",
        "const NAME = other\n",
        "const BYTES = b\"ab\"\n",
        "const MISSING =\n",
    };
    const names = [_][]const u8{ "LIMIT", "BIG", "TOO_BIG", "NAME", "BYTES", "MISSING" };
    for (sources, names) |bytes, name| {
        const failure = try fixture.failure(bytes);
        const message = try std.fmt.allocPrint(fixture.arena.allocator(), "a module constant needs its type: write `const {s}: TYPE = ...`", .{name});
        try t.expectEqualStrings("E_SYNTAX", failure.code);
        try t.expectEqualStrings(message, failure.message);
        try t.expect(failure.provenance.fix == null);
    }
}
