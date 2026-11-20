//! Python surface syntax retains typed semantics and original diagnostic offsets.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");
const ast = @import("ast.zig");
const graph = @import("project.zig");
const interfaces = @import("interfaces.zig");

const program =
    \\# Python records remain value records.
    \\record Point:
    \\    x: int
    \\    y: int
    \\
    \\
    \\func noop():
    \\    pass
    \\
    \\
    \\func main() -> int:
    \\    noop()
    \\    mut p = Point(x=40, y=2)
    \\    mut total: int = 0
    \\    while total < 2:
    \\        total += 1
    \\    if not total == 2:
    \\        return 0
    \\    elif True and not False:
    \\        return p.x + p.y
    \\    else:
    \\        return total
    \\
;

fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "python.selka", program);
    defer c.deinit();
    try t.expectEqual(@as(i64, 42), (try native.run(&c)).value);
    const formatted = try c.format(allocator);
    defer allocator.free(formatted);
    try t.expectEqualStrings(program, formatted);
}

// spec: PYTHON-1
test "Python indentation records assignment boolean precedence and omitted unit execute" {
    try scenario(t.allocator);
}

// spec-case: PYTHON-1
test "Python layout retains original spans and ignores blank comment and continuation lines" {
    const text = "func main() -> int:\n    # ignored\n\n    return (\n        40 +\n        2\n    )\n";
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var sink: diagnostic.Sink = .{ .allocator = arena.allocator() };
    const tokens = try lexer.lex(arena.allocator(), text, &sink);
    var last: usize = 0;
    var virtual_closes: usize = 0;
    for (tokens) |token| {
        try t.expect(token.span.start >= last);
        try t.expect(token.span.end <= text.len);
        last = token.span.end;
        if (token.tag == .dedent and token.span.start == token.span.end) virtual_closes += 1;
    }
    try t.expectEqual(@as(usize, 1), virtual_closes);
    var c = try language.Compilation.init(t.allocator, "continuation.selka", text);
    defer c.deinit();
    try t.expectEqual(@as(i64, 42), (try native.run(&c)).value);
}

// spec-case: PYTHON-1
test "Python layout lower rejects missing blocks inconsistent dedents tabs and excess indentation" {
    for ([_][]const u8{
        "def main() -> int:\nreturn 42\n",
        "def main() -> int:\n    if True:\n        return 42\n  return 0\n",
        "def main() -> int:\n\treturn 42\n",
        "def main() -> int:\n    x = 1\n        return x\n",
        "def main() -> int:\n    # empty\n",
    }) |text| {
        var c = try language.Compilation.init(t.allocator, "indent.selka", text);
        defer c.deinit();
        try t.expectError(error.SourceError, c.check());
        try t.expectEqualStrings("E_INDENTATION", c.diagnostics.items[0].code);
    }
}

// spec-case: PYTHON-2
test "immutable parameters support derived locals and mutable locals update across blocks" {
    const text = "func bump[T: integer](value: T) -> T:\n    const doubled = value + value\n    return doubled\n\nfunc main() -> int:\n    mut answer = 0\n    if True:\n        answer = bump(21)\n    return answer\n";
    var c = try language.Compilation.init(t.allocator, "scope.selka", text);
    defer c.deinit();
    try t.expectEqual(@as(i64, 42), (try native.run(&c)).value);
    // A name assigned only on one branch is not definitely bound afterwards.
    var bad = try language.Compilation.init(t.allocator, "scope.selka", "func main() -> int:\n    if True:\n        answer = 42\n    return answer\n");
    defer bad.deinit();
    try t.expectError(error.SourceError, bad.check());
    try t.expectEqualStrings("E_BINDING_SCOPE_MIGRATION", bad.diagnostics.items[0].code);
}

fn scopeValue(text: []const u8) !i64 {
    var c = try language.Compilation.init(t.allocator, "scope.selka", text);
    defer c.deinit();
    return (try native.run(&c)).value;
}

fn scopeReject(text: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "scope.selka", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

// An augmented field assignment keeps the rules plain field assignment and a
// binding's augmented form have: `/=` on an integer field is a type error and
// a field of a class parameter the signature does not mark `mut` needs it.
// spec-case: AUGMENTED-FIELD-1
test "augmented field assignment keeps the operator and mutation rules" {
    try scopeReject("record Box:\n    n: int\n\nfunc main() -> int:\n    mut b = Box(n=4)\n    b.n /= 2\n    return b.n\n", "E_TYPE");
    try scopeReject("record Box:\n    n: int\n\nfunc bump(b: Box):\n    b.n += 1\n\nfunc main() -> int:\n    mut b = Box(n=4)\n    bump(b)\n    return b.n\n", "E_IMMUTABLE");
    try t.expectEqual(@as(i64, 12), try scopeValue("record Box:\n    n: int\n    f: float\n\nfunc main() -> int:\n    mut b = Box(n=4, f=1.0)\n    b.n *= 3\n    b.f /= 4.0\n    return b.n\n"));
}

// spec-case: PY-SCOPE-2
test "PY-SCOPE-2 assignments only in a loop body are unbound after the loop" {
    try scopeReject(
        \\func main() -> int:
        \\    while False:
        \\        const answer = 42
        \\    return answer
    , "E_UNKNOWN_NAME");
    try scopeReject(
        \\func main() -> int:
        \\    for item in [1, 2]:
        \\        const answer = item
        \\    return answer
    , "E_UNKNOWN_NAME");
    try scopeReject(
        \\func main() -> int:
        \\    for item in range(2):
        \\        const answer = item
        \\    return answer
    , "E_UNKNOWN_NAME");
    try scopeReject(
        \\func main() -> int:
        \\    for item in reversed([1, 2]):
        \\        const answer = item
        \\    return answer
    , "E_UNKNOWN_NAME");
    try scopeReject(
        \\func main() -> int:
        \\    for a, b in zip([1, 2], [3, 4]):
        \\        const answer = a + b
        \\    return answer
    , "E_UNKNOWN_NAME");
}

// spec: PY-SCOPE-2
test "PY-SCOPE-2 reading a name unbound on some path is rejected" {
    try scopeReject(
        \\func main() -> int:
        \\    mut flag = True
        \\    if flag:
        \\        const chosen = 5
        \\    return chosen
    , "E_UNKNOWN_NAME");
    // A name never assigned before the read stays E_UNKNOWN_NAME.
    try scopeReject(
        \\func main() -> int:
        \\    return missing
    , "E_UNKNOWN_NAME");
    // A method call reads its receiver, so a maybe-unbound owner is rejected too.
    try scopeReject(
        \\func main() -> int:
        \\    mut flag = True
        \\    if flag:
        \\        mut data = [1, 2]
        \\    data.insert(0, 3)
        \\    return 0
    , "E_UNKNOWN_TYPE");
}

const match_choice =
    \\enum Choice:
    \\    first
    \\    second
    \\
    \\
;

// spec-case: PY-SCOPE-3
test "match rejects locals unassigned on a continuing arm" {
    try scopeReject(match_choice ++
        \\func main() -> int:
        \\    match Choice.first:
        \\        case first:
        \\            const answer = 42
        \\        case second:
        \\            pass
        \\    return answer
    , "E_UNKNOWN_NAME");
    // An assignment in a terminating arm does not bind the continuing path.
    try scopeReject(match_choice ++
        \\func main() -> int:
        \\    match Choice.first:
        \\        case first:
        \\            const answer = 42
        \\            return answer
        \\        case second:
        \\            pass
        \\    return answer
    , "E_UNKNOWN_NAME");
    // A wildcard continuation that does not assign cannot consume another
    // arm's assignment.
    try scopeReject(match_choice ++
        \\func main() -> int:
        \\    match Choice.first:
        \\        case first:
        \\            const answer = 42
        \\        case _:
        \\            pass
        \\    return answer
    , "E_UNKNOWN_NAME");
}

// spec-case: PY-SCOPE-3
test "match payload bindings remain scoped to their arm" {
    try scopeReject(
        \\enum Box:
        \\    only(value: int)
        \\
        \\
        \\func main() -> int:
        \\    match Box.only(value=42):
        \\        case only(value=value):
        \\            pass
        \\    return value
    , "E_UNKNOWN_NAME");
}

// spec-case: PYTHON-1
test "Python declaration listings and formatting retain comment and original name positions" {
    const text = "# documentation\nfunc first() -> int:\n    return 40\n\n\nfunc main() -> int:\n    return first() + 2\n";
    var c = try language.Compilation.init(t.allocator, "listing.selka", text);
    defer c.deinit();
    const listing = try c.listDeclarations(t.allocator);
    defer t.allocator.free(listing);
    try t.expect(std.mem.indexOf(u8, listing, "\"name\":\"first\"") != null);
    try t.expect(std.mem.indexOf(u8, listing, "\"comment_start\":0") != null);
    const formatted = try c.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expectEqualStrings(text, formatted);
}

fn lowerAllocations(allocator: std.mem.Allocator) !void {
    var sink: diagnostic.Sink = .{ .allocator = allocator };
    const tokens = try lexer.lex(allocator, program, &sink);
    defer allocator.free(tokens);
    try t.expectEqual(lexer.Tag.eof, tokens[tokens.len - 1].tag);
}

// spec: PYTHON-3
test "Python match cases retain contextual pattern names square types and discard payloads" {
    const text = "func extract(value: Result[int, int]) -> int:\n    match value:\n        case Ok(answer):\n            return answer\n        case Err(_):\n            return 0\n";
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const src = try source.Source.init(arena.allocator(), "patterns.selka", text);
    var sink: diagnostic.Sink = .{ .allocator = arena.allocator() };
    const tokens = try lexer.lex(arena.allocator(), text, &sink);
    var p: parser.Parser = .{ .src = src, .storage = arena.allocator(), .tokens = tokens, .sink = &sink };
    const syntax = try p.parse();
    try t.expectEqual(@as(usize, 1), syntax.types.expressions.applications.len);
    const body = syntax.statements.items[@backingInt(syntax.functions[0].body)].data.block;
    const arms = syntax.statements.items[@backingInt(body[0])].data.match.arms;
    try t.expectEqualStrings("Ok", src.text(arms[0].name));
    try t.expectEqual(arms[0].ty.start, arms[0].ty.end);
    try t.expect(arms[1].bindings.len == 1 and arms[1].bindings[0] == null);
}

/// A module of `count` small functions, each a loop over a list.
fn manyFunctions(allocator: std.mem.Allocator, count: usize) ![]u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    defer text.deinit();
    try text.writer.writeAll("\n\n");
    for (0..count) |index| try text.writer.print("func g{d}(n: int) -> int:\n    mut xs: int[] = []\n    for k in range(n):\n        xs.append(k * {d})\n    return len(xs)\n\n\n", .{ index, index });
    return text.toOwnedSlice();
}
/// Bytes the parse of `text` reserved in its storage, and whether its node and
/// statement lists came back at their exact length.
fn parseStorage(text: []const u8, growth: ?std.mem.Allocator) !struct { bytes: usize, exact: bool } {
    var counting = t.FailingAllocator.init(t.allocator, .{});
    var storage = std.heap.ArenaAllocator.init(counting.allocator());
    defer storage.deinit();
    var inputs = std.heap.ArenaAllocator.init(t.allocator);
    defer inputs.deinit();
    const src = try source.Source.init(inputs.allocator(), "many.selka", text);
    var sink: diagnostic.Sink = .{ .allocator = inputs.allocator() };
    const tokens = try lexer.lex(inputs.allocator(), text, &sink);
    var p: parser.Parser = .{ .src = src, .storage = storage.allocator(), .tokens = tokens, .sink = &sink, .syntax = .{ .growth = growth } };
    defer p.release();
    const syntax = try p.parseModule();
    const exact = syntax.nodes.capacity == syntax.nodes.items.len and syntax.statements.capacity == syntax.statements.items.len;
    return .{ .bytes = counting.allocated_bytes, .exact = exact };
}
// spec: PARSE-EXACT-1
test "a module's node and statement lists grow outside its storage and settle there at their exact length" {
    const text = try manyFunctions(t.allocator, 400);
    defer t.allocator.free(text);
    const grown = try parseStorage(text, null);
    const settled = try parseStorage(text, t.allocator);
    try t.expect(settled.exact);
    // The abandoned growth buffers were a third of what an arena storage held
    // here (2.7 MB against 4.0 MB); a whole project's parse was 2.4 times
    // smaller (1.08 GB to 0.44 GB at 500k lines).
    try t.expect(settled.bytes * 4 < grown.bytes * 3);
}

// spec-case: PYTHON-1
test "Python layout lower frees partial token allocations on every allocator failure" {
    try t.checkAllAllocationFailures(t.allocator, lowerAllocations, .{});
}

// spec-case: ATTR-1
test "the parser rejects unknown repeated and misplaced attributes" {
    try scopeReject("@unknown\ndef main() -> int:\n    return 0\n", "E_UNKNOWN_ATTRIBUTE");
    try scopeReject("@test\n@test\ndef main() -> bool:\n    return True\n", "E_DUPLICATE_ATTRIBUTE");
    try scopeReject("@test\nclass C:\n    x: int\n", "E_ATTRIBUTE_TARGET");
    var valid = try language.Compilation.init(t.allocator, "attrs.selka",
        \\@test
        \\func checks() -> bool:
        \\    return True
        \\
        \\
        \\@allow("dead-private", reason="kept")
        \\func helper() -> int:
        \\    return 1
        \\
        \\
        \\func main() -> int:
        \\    return 0
    );
    defer valid.deinit();
    try valid.parse();
    try t.expectEqual(@as(usize, 2), valid.syntax.?.attributes.len);
}

/// One in-memory module source for the project-level DOC-2 scenario.
const DocFile = struct { path: []const u8, bytes: []const u8 };
/// Read a fixed module table without touching the filesystem.
const DocFiles = struct {
    entries: []const DocFile,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) graph.ReadError![]u8 {
        const self: *DocFiles = @ptrCast(@alignCast(context.?));
        for (self.entries) |file| if (std.mem.eql(u8, file.path, path)) {
            if (file.bytes.len > limit) return error.TooLarge;
            return allocator.dupe(u8, file.bytes);
        };
        return error.NotFound;
    }
    fn provider(self: *DocFiles) graph.Provider {
        return .{ .context = self, .read = read };
    }
};

/// The registered lint rule with this name.
fn ruleNamed(name: []const u8) *const language.lint.Rule {
    for (&language.lint.rules) |*rule| if (std.mem.eql(u8, rule.name, name)) return rule;
    return &language.lint.rules[0];
}

// spec: DOC-1
test "leading string statements are inert module and function docstrings" {
    const documented =
        // migrate-embedded: skip intentional original effects docstring witness
        \\"""Module documentation for the program."""
        \\func area(width: int, height: int) -> int effects():
        \\    """The rectangle's area.
        \\
        \\    A # hash and a blank line stay in the literal.
        \\    """
        \\    return width * height
        \\
        \\
        \\func main() -> int effects():
        \\    return area(2, 7)
    ;
    var before = try language.Compilation.init(t.allocator, "docstrings-before.selka", documented);
    defer before.deinit();
    try t.expectError(error.SourceError, before.check());
    try t.expect(before.diagnostics.items.len > 0);
    for (before.diagnostics.items) |item| try t.expectEqualStrings("E_EFFECTS_REMOVED", item.code);
    const modern_documented = try std.mem.replaceOwned(u8, t.allocator, documented, " effects()", "");
    defer t.allocator.free(modern_documented);
    var c = try language.Compilation.init(t.allocator, "docstrings.selka", modern_documented);
    defer c.deinit();
    try t.expectEqual(@as(i64, 14), (try native.run(&c)).value);
    const module_doc = ast.docstringOf(c.syntax.?, ast.module_docstring_span) orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings("Module documentation for the program.", module_doc.text);
    const area_doc = ast.docstringOf(c.syntax.?, c.syntax.?.functions[0].name) orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings("The rectangle's area.\n\n    A # hash and a blank line stay in the literal.\n    ", area_doc.text);
    const listing = try c.listDeclarations(t.allocator);
    defer t.allocator.free(listing);
    try t.expect(std.mem.indexOf(u8, listing, "\"name\":\"area\"") != null);
    try t.expect(std.mem.indexOf(u8, listing, "\"name\":\"main\"") != null);

    // A string after the first statement is not a docstring: it stays the
    // ordinary standalone expression, which the checker rejects as non-unit.
    // migrate-embedded: skip intentional original effects non-docstring witness
    const later = "func main() -> int effects():\n    mut value = 1\n    \"not a docstring\"\n    return value\n";
    var later_before = try language.Compilation.init(t.allocator, "later-before.selka", later);
    defer later_before.deinit();
    try t.expectError(error.SourceError, later_before.check());
    try t.expectEqualStrings("E_EFFECTS_REMOVED", later_before.diagnostics.items[0].code);
    const modern_later = try std.mem.replaceOwned(u8, t.allocator, later, " effects()", "");
    defer t.allocator.free(modern_later);
    var d = try language.Compilation.init(t.allocator, "later.selka", modern_later);
    defer d.deinit();
    try d.parse();
    try t.expect(ast.docstringOf(d.syntax.?, d.syntax.?.functions[0].name) == null);
    try t.expectEqual(@as(usize, 0), d.syntax.?.docstrings.len);
    try t.expectError(error.SourceError, d.check());
    try t.expectEqualStrings("E_EXPLICIT_DISCARD_REQUIRED", d.diagnostics.items[0].code);
}

/// Parse one `min_chars` value out of a version 2 `selka.json` document.
fn parsedMinChars(allocator: std.mem.Allocator, text: []const u8) !?usize {
    var failure: language.lint_config.Failure = .{};
    var config = try language.lint_config.parseConfig(allocator, text, &failure);
    defer config.deinit(allocator);
    return config.min_chars;
}

// spec: DOC-2
test "undocumented-export reports missing short and name-restating docstrings" {
    const body =
        \\
        \\
        \\public func bare(x: int) -> int:
        \\    return x
        \\
        \\
        \\public func terse(x: int) -> int:
        \\    "short"
        \\    return x
        \\
        \\
        \\public func compute_value(x: int) -> int:
        \\    "compute value"
        \\    return x
        \\
        \\
        \\public func area(x: int) -> int:
        \\    "The rectangle's area in square units."
        \\    return x
        \\
        \\
        \\func main() -> int:
        \\    return 0
    ;
    var files: DocFiles = .{ .entries = &.{.{ .path = "main.selka", .bytes = body }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var scratch = std.heap.ArenaAllocator.init(t.allocator);
    defer scratch.deinit();
    var findings: std.ArrayList(language.lint.Finding) = .empty;
    try language.lint.appendUndocumentedExports(scratch.allocator(), &index, 12, &findings);
    try t.expectEqual(@as(usize, 3), findings.items.len);
    try t.expectEqualStrings("L_UNDOCUMENTED_EXPORT", findings.items[0].code);
    try t.expect(std.mem.indexOf(u8, findings.items[0].message, "bare has no docstring") != null);
    try t.expect(std.mem.indexOf(u8, findings.items[1].message, "terse docstring has 5 non-whitespace characters (min 12)") != null);
    try t.expect(std.mem.indexOf(u8, findings.items[2].message, "compute_value docstring merely restates the declaration name") != null);
    const rule = ruleNamed("undocumented-export");
    try t.expectEqual(language.lint_config.Mode.report, rule.modes.agent);
    try t.expectEqual(language.lint_config.Mode.block, rule.modes.strict);
    try t.expectEqual(language.lint_config.Mode.block, rule.modes.safety);
    // A shorter configured floor accepts the five-character docstring.
    try t.expectEqual(@as(?usize, 5), try parsedMinChars(t.allocator, "{\"version\":2,\"lint\":{\"min_chars\":5}}"));
}

/// The statement list of the first function's body, for a parse-only assertion.
fn bodyOf(syntax: ast.Program) []const ast.StatementId {
    return syntax.statements.items[@backingInt(syntax.functions[0].body)].data.block;
}

/// The source text a node's span covers, for a parse-only assertion.
fn nodeText(syntax: ast.Program, src: source.Source, id: ast.NodeId) []const u8 {
    return src.text(syntax.nodes.items[@backingInt(id)].span);
}

/// Parse one source that must fail, asserting the first diagnostic's code, its
/// message, and the source text its span covers.
fn parseFailure(text: []const u8, code: []const u8, message: []const u8, at: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "syntax.selka", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.parse());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
    try t.expectEqualStrings(message, c.diagnostics.items[0].message);
    try t.expectEqualStrings(at, c.src.text(c.diagnostics.items[0].span));
}

test "borrowing syntax retains from source order before the failure clause" {
    var c = try language.Compilation.init(t.allocator, "borrowing.selka",
        \\func select[T](first: T, mut fallback: T) -> T? from fallback, first fails Error:
        \\    return None
    );
    defer c.deinit();
    try c.parse();
    const signature = c.syntax.?.functions[0].signature;
    try t.expectEqualStrings("T?", c.src.text(signature.return_type));
    try t.expectEqualStrings("Error", c.src.text(signature.failure_type.?));
    try t.expectEqual(@as(usize, 2), signature.borrowing.len);
    try t.expectEqualStrings("fallback", c.src.text(signature.borrowing[0]));
    try t.expectEqualStrings("first", c.src.text(signature.borrowing[1]));
}

test "borrowing syntax leaves contextual from names and omitted clauses intact" {
    var c = try language.Compilation.init(t.allocator, "contextual-from.selka",
        \\func from(from: str) -> str from from:
        \\    return from
        \\func plain(from: int) -> int:
        \\    return from
        \\func attempt() fails Error:
        \\    return
    );
    defer c.deinit();
    try c.parse();
    const functions = c.syntax.?.functions;
    try t.expectEqualStrings("from", c.src.text(functions[0].name));
    try t.expectEqualStrings("from", c.src.text(functions[0].signature.borrowing[0]));
    try t.expectEqual(@as(usize, 0), functions[1].signature.borrowing.len);
    try t.expectEqual(@as(usize, 0), functions[2].signature.borrowing.len);
    try t.expect(functions[2].signature.failure_type != null);
}

test "borrowing syntax preserves source eligibility for later checking and foreign headers" {
    var c = try language.Compilation.init(t.allocator, "borrowing-draft.selka",
        \\func draft(own owned: str, count: int) -> str from missing, owned, count, count:
        \\    return owned
        \\extern func declared(host: Host, value: str) -> str from value
    );
    defer c.deinit();
    try c.parse();
    try t.expectEqual(@as(usize, 4), c.syntax.?.functions[0].signature.borrowing.len);
    try t.expectEqualStrings("missing", c.src.text(c.syntax.?.functions[0].signature.borrowing[0]));
    try t.expect(c.syntax.?.functions[1].policy.c_abi);
    try t.expectEqualStrings("value", c.src.text(c.syntax.?.functions[1].signature.borrowing[0]));
}

fn rejectBorrowingGrammar(text: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "borrowing-grammar.selka", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.parse());
    try t.expectEqualStrings("E_SYNTAX", c.diagnostics.items[0].code);
    try t.expect(c.diagnostics.items[0].provenance.rule == null);
}

test "O4 own syntax wraps bindings stores constructors literals and returns" {
    var c = try language.Compilation.init(t.allocator, "own-positions.selka",
        // migrate-embedded: skip intentional O4 parser marker positions and exact source spans
        \\func draft() -> Value:
        \\    const borrowed = source
        \\    const moved = own source
        \\    mut changed = own other
        \\    changed = own source
        \\    item.field = own source
        \\    items[0] = own source
        \\    const record = Row(items=own source)
        \\    const wrapped = Some(own source)
        \\    const list = [own left, own right]
        \\    const mapping = {own key: own value}
        \\    return own moved
    );
    defer c.deinit();
    try c.parse();
    var markers: usize = 0;
    for (c.syntax.?.nodes.items) |node| {
        if (node.data != .own_argument) continue;
        markers += 1;
        const inner = c.syntax.?.nodes.items[@backingInt(node.data.own_argument)];
        try t.expect(inner.data == .name);
        try t.expectEqual(node.span.start + "own ".len, inner.span.start);
        try t.expectEqual(node.span.end, inner.span.end);
    }
    try t.expectEqual(@as(usize, 12), markers);
}

test "O4 own syntax keeps contextual names and defers marker eligibility" {
    var c = try language.Compilation.init(t.allocator, "own-context.selka",
        // migrate-embedded: skip intentional O4 contextual names and misplaced marker syntax
        \\func own(own: int) -> int:
        \\    return own
        \\func draft() -> int:
        \\    const own = [1]
        \\    const call = own(1)
        \\    const index = own[0]
        \\    const field = box.own
        \\    const fresh = own make()
        \\    const scalar = own number
        \\    const expression = (own left) + right
        \\    return own + index
    );
    defer c.deinit();
    try c.parse();
    var markers: usize = 0;
    for (c.syntax.?.nodes.items) |node| {
        if (node.data != .own_argument) continue;
        markers += 1;
    }
    try t.expectEqual(@as(usize, 3), markers);
    try t.expectEqualStrings("own", c.src.text(c.syntax.?.functions[0].name));
    try t.expectEqualStrings("own", c.src.text(c.syntax.?.functions[0].signature.parameters[0].name));
}

test "O4 own syntax refuses duplicate and combined markers before typed flattening" {
    for ([_][]const u8{
        "const value = own own source",
        "const value = (own own source)",
        "take(own mut source)",
        "take(mut own source)",
        "take(mut (own source))",
    }) |statement| {
        // migrate-embedded: skip intentional O4 duplicate and combined marker parser template
        const text = try std.fmt.allocPrint(t.allocator, "func draft():\n    {s}\n", .{statement});
        defer t.allocator.free(text);
        var c = try language.Compilation.init(t.allocator, "own-duplicate.selka", text);
        defer c.deinit();
        try t.expectError(error.SourceError, c.parse());
        try t.expectEqualStrings("E_PARAMETER_MODIFIER", c.diagnostics.items[0].code);
    }
}

test "O4 own syntax reaches typed nodes with source spans views and contextual types" {
    const text =
        // migrate-embedded: skip intentional O4 typed marker provenance before Core eligibility
        \\record Row:
        \\    items: int[]
        \\func make() -> int[]:
        \\    return []
        \\func examine(mut rows: int[][]) -> int:
        \\    const source = [1]
        \\    const moved = own source
        \\    const held = Row(items=own moved)
        \\    const wrapped: int[]? = Some(own held.items)
        \\    append(mut rows, own make())
        \\    const invalid = own source[0:1]
        \\    return 0
        \\func main() -> int:
        \\    return 0
    ;
    var c = try language.Compilation.init(t.allocator, "own-typed.selka", text);
    defer c.deinit();
    try c.checkWithFrontend(null);
    const program_value = c.program.?;
    var markers: usize = 0;
    var views: usize = 0;
    var fields: usize = 0;
    var fresh_calls: usize = 0;
    for (program_value.nodes) |node| {
        if (!node.own) continue;
        markers += 1;
        try t.expect(std.mem.startsWith(u8, c.src.text(node.span), "own "));
        if (node.view) views += 1;
        if (node.data == .field) fields += 1;
        if (std.mem.eql(u8, c.src.text(node.span), "own make()")) {
            fresh_calls += 1;
            try t.expect(node.ty.isAggregate());
            try t.expectEqual(language.typed.Type.i64, program_value.records[node.ty.recordIndex()].shape.buffer.?);
        }
    }
    try t.expectEqual(@as(usize, 5), markers);
    try t.expectEqual(@as(usize, 1), views);
    try t.expectEqual(@as(usize, 1), fields);
    try t.expectEqual(@as(usize, 1), fresh_calls);
}

test "O4 own mode spelling matches mut and scalar taking parameters" {
    const cases = [_]struct { text: []const u8, marker: []const u8, replacement: []const u8 }{
        .{
            // migrate-embedded: skip intentional O4 own-to-mut spelling diagnostic and exact repair
            .text = "func use(mut values: int[]) -> int:\n    return len(values)\nfunc main() -> int:\n    mut values = [1]\n    return use(own values)\n",
            .marker = "own ",
            .replacement = "mut ",
        },
        .{
            // migrate-embedded: skip intentional O4 mut-to-own spelling diagnostic and exact repair
            .text = "func use(own values: int[]) -> int:\n    return len(values)\nfunc main() -> int:\n    mut values = [1]\n    return use(mut values)\n",
            .marker = "mut ",
            .replacement = "own ",
        },
        .{
            // migrate-embedded: skip intentional O4 scalar marker spelling diagnostic and exact repair
            .text = "func use(own value: int) -> int:\n    return value\nfunc main() -> int:\n    mut value = 1\n    return use(mut value)\n",
            .marker = "mut ",
            .replacement = "",
        },
    };
    for (cases) |case| {
        var c = try language.Compilation.init(t.allocator, "own-mode.selka", case.text);
        defer c.deinit();
        try t.expectError(error.SourceError, c.checkWithFrontend(null));
        const item = c.diagnostics.items[0];
        try t.expectEqualStrings("E_OWN_MARKER", item.code);
        try t.expectEqual(language.ownership_rules.Rule.W2, item.provenance.rule.?);
        const fix = item.provenance.fix.?;
        try t.expectEqualStrings(case.marker, c.src.text(fix.edit.span));
        try t.expectEqualStrings(case.replacement, fix.edit.text);
    }
}

test "O4 own provenance survives fresh field receiver staging" {
    var c = try language.Compilation.init(t.allocator, "own-fresh-field.selka",
        // migrate-embedded: skip intentional O4 misplaced fresh-field markers retained for Core
        \\record Row:
        \\    items: int[]
        \\func make() -> Row:
        \\    return Row(items=[1])
        \\func main() -> int:
        \\    const count = len(own make().items)
        \\    const copied = copy(own make().items)
        \\    return count + len(copied)
    );
    defer c.deinit();
    try c.checkWithFrontend(null);
    const program_value = c.program.?;
    const function = program_value.functions[@backingInt(program_value.main)];
    var walker = try language.typed_walk.Walker.init(t.allocator, program_value, function.scope.body);
    defer walker.deinit();
    var found: usize = 0;
    while (try walker.next()) |item| {
        if (item != .expression) continue;
        const node = program_value.nodes[@backingInt(item.expression)];
        if (!node.own) continue;
        try t.expectEqualStrings("own make().items", c.src.text(node.span));
        try t.expect(node.data == .field);
        try t.expect(program_value.nodes[@backingInt(node.data.field.base)].data == .call);
        found += 1;
    }
    try t.expectEqual(@as(usize, 2), found);
}

test "O4 own provenance stays reachable through folded helpers conversions and unused values" {
    for ([_][]const u8{
        "len(own values)",
        "len(own text)",
        "copy(own values)",
        "strings.char_count(own text)",
        "int(own count)",
        "float(own fraction)",
        "ord(own text)",
        "0 in own octets",
        "own count",
        "False and (own truth)",
        "(own count) + 3",
        "list(range(0, 3, own stride))",
        "list(range(0, 3, -(own stride)))",
    }) |expression| {
        const text = try std.fmt.allocPrint(
            t.allocator,
            // migrate-embedded: skip intentional O4 folded-helper marker provenance template
            "func main() -> int:\n    const values = [1]\n    const text = \"x\"\n    const octets = b\"x\"\n    const mapping = {{\"x\": 1}}\n" ++
                "    const count = 1\n    const fraction = 1.0\n    const truth = True\n    const stride = 1\n" ++
                "    const unused = {s}\n    return 0\n",
            .{expression},
        );
        defer t.allocator.free(text);
        var c = try language.Compilation.init(t.allocator, "own-helper.selka", text);
        defer c.deinit();
        try c.checkWithFrontend(null);
        const program_value = c.program.?;
        const function = program_value.functions[@backingInt(program_value.main)];
        var walker = try language.typed_walk.Walker.init(t.allocator, program_value, function.scope.body);
        defer walker.deinit();
        var found: usize = 0;
        while (try walker.next()) |item| {
            if (item != .expression) continue;
            const node = program_value.nodes[@backingInt(item.expression)];
            if (!node.own) continue;
            try t.expect(std.mem.startsWith(u8, std.mem.trimStart(u8, c.src.text(node.span), " (\t"), "own "));
            found += 1;
        }
        try t.expectEqual(@as(usize, 1), found);
    }
}

test "O4 own dictionary projection markers stay reachable through immediate consumers" {
    for ([_][]const u8{ "len", "list" }) |consumer| {
        const text = try std.fmt.allocPrint(
            t.allocator,
            // migrate-embedded: skip intentional O4 dictionary projection marker provenance template
            "import dicts\n\nfunc main() -> int:\n    const mapping = {{1: 2}}\n    const unused = {s}(own dicts.keys(mapping))\n    return 0\n",
            .{consumer},
        );
        defer t.allocator.free(text);
        var project: language.embedded_project.Program = undefined;
        try @import("stdlib_fixture.zig").load(&project, t.allocator, text);
        defer project.deinit();
        const checked = project.compilation.program.?;
        var walker = try language.typed_walk.Walker.init(t.allocator, checked, checked.functions[@backingInt(checked.main)].scope.body);
        defer walker.deinit();
        var found: usize = 0;
        while (try walker.next()) |item| {
            if (item != .expression) continue;
            const node = checked.nodes[@backingInt(item.expression)];
            if (!node.own) continue;
            try t.expectEqualStrings("own dicts.keys(mapping)", project.compilation.src.text(node.span));
            found += 1;
        }
        try t.expectEqual(@as(usize, 1), found);
    }
}

test "O4 own provenance survives scalar and text literal match lowering" {
    for ([_]struct { value: []const u8, pattern: []const u8 }{
        .{ .value = "1", .pattern = "1" },
        .{ .value = "\"x\"", .pattern = "\"x\"" },
    }) |case| {
        const text = try std.fmt.allocPrint(
            t.allocator,
            // migrate-embedded: skip intentional O4 scalar and text match marker provenance template
            "func main() -> int:\n    const value = {s}\n    match own value:\n        case {s}:\n            return 42\n        case _:\n            return 0\n",
            .{ case.value, case.pattern },
        );
        defer t.allocator.free(text);
        var c = try language.Compilation.init(t.allocator, "own-match.selka", text);
        defer c.deinit();
        try c.checkWithFrontend(null);
        const program_value = c.program.?;
        const function = program_value.functions[@backingInt(program_value.main)];
        var walker = try language.typed_walk.Walker.init(t.allocator, program_value, function.scope.body);
        defer walker.deinit();
        var found: usize = 0;
        while (try walker.next()) |item| {
            if (item != .expression) continue;
            const node = program_value.nodes[@backingInt(item.expression)];
            if (!node.own) continue;
            try t.expect(node.data == .local);
            try t.expectEqualStrings("own value", c.src.text(node.span));
            found += 1;
        }
        try t.expectEqual(@as(usize, 1), found);
    }
}

test "O4 own provenance survives fixed and refreshed loop sources" {
    for ([_]struct { source: []const u8, body: []const u8, iterable: []const u8 = "own values", marker: []const u8 = "own values", references: usize = 1 }{
        .{ .source = "FixedArray[int, 2]([1, 2])", .body = "_ = value" },
        .{ .source = "[1, 2]", .body = "append(mut values, 3)" },
        .{ .source = "[1, 2]", .body = "append(mut values, 3)", .iterable = "(own Row(items=values)).items", .marker = "(own Row(items=values))" },
        .{ .source = "Row(items=[1, 2])", .body = "append(mut values.items, 3)", .iterable = "(own values).items", .marker = "(own values)", .references = 3 },
    }) |case| {
        const text = try std.fmt.allocPrint(
            t.allocator,
            // migrate-embedded: skip intentional O4 iteration marker provenance and source-span template
            "record Row:\n    items: int[]\nfunc main() -> int:\n    mut values = {s}\n    for value in {s}:\n        {s}\n    return 0\n",
            .{ case.source, case.iterable, case.body },
        );
        defer t.allocator.free(text);
        var c = try language.Compilation.init(t.allocator, "own-loop.selka", text);
        defer c.deinit();
        try c.parse();
        var original: ?source.Span = null;
        for (c.syntax.?.nodes.items) |node| {
            if (node.data != .own_argument) continue;
            try t.expect(original == null);
            try t.expectEqualStrings(case.marker, c.src.text(node.span));
            original = node.span;
        }
        const marker = original orelse return error.TestUnexpectedResult;
        try c.checkWithFrontend(null);
        const program_value = c.program.?;
        const function = program_value.functions[@backingInt(program_value.main)];
        var walker = try language.typed_walk.Walker.init(t.allocator, program_value, function.scope.body);
        defer walker.deinit();
        var found: usize = 0;
        while (try walker.next()) |item| {
            if (item != .expression) continue;
            const node = program_value.nodes[@backingInt(item.expression)];
            if (!node.own) continue;
            try t.expectEqualDeep(marker, node.span);
            found += 1;
        }
        // Live-place guards revisit the same source marker in the body and
        // back edge; every reachable reference must retain its original span.
        try t.expectEqual(case.references, found);
    }
}

test "O4 own provenance survives SIMD list argument staging" {
    var c = try language.Compilation.init(t.allocator, "own-simd.selka",
        // migrate-embedded: skip intentional O4 misplaced SIMD read marker retained for Core
        \\func main() -> int:
        \\    const values = [1, 2]
        \\    const lanes: Simd[int, 2] = simd.load(own values, 0)
        \\    return lanes[0] + values[0]
    );
    defer c.deinit();
    try c.checkWithFrontend(null);
    const program_value = c.program.?;
    const function = program_value.functions[@backingInt(program_value.main)];
    var walker = try language.typed_walk.Walker.init(t.allocator, program_value, function.scope.body);
    defer walker.deinit();
    var found: usize = 0;
    while (try walker.next()) |item| {
        if (item != .expression) continue;
        const node = program_value.nodes[@backingInt(item.expression)];
        if (!node.own) continue;
        try t.expect(node.data == .local);
        try t.expectEqualStrings("own values", c.src.text(node.span));
        found += 1;
    }
    try t.expectEqual(@as(usize, 1), found);
}

test "O4 own store staging records transfers through field list dictionary and fixed array paths" {
    const cases = [_]struct { setup: []const u8, target: []const u8, rhs: []const u8 = "own source" }{
        .{ .setup = "mut box = Box(items=[1])", .target = "box.items" },
        .{ .setup = "mut box = Box(items=[1])", .target = "box.items", .rhs = "source" },
        .{ .setup = "mut boxes = [Box(items=[1])]", .target = "boxes[0].items" },
        .{ .setup = "mut values = [[1]]", .target = "values[0]" },
        .{ .setup = "mut values = [[1]]", .target = "values[0]", .rhs = "source" },
        .{ .setup = "mut values = {\"x\": [1]}", .target = "values[\"x\"]" },
        .{ .setup = "mut values = FixedArray[int[], 2]([[1], [2]])", .target = "values[0]" },
        .{ .setup = "mut shelf = Shelf(cells=FixedArray[int[], 2]([[1], [2]]))", .target = "shelf.cells[0]" },
        .{ .setup = "mut values = [FixedArray[int[], 2]([[1], [2]])]", .target = "values[0][0]" },
        .{ .setup = "mut values = FixedArray[Box, 2]([Box(items=[1]), Box(items=[2])])", .target = "values[0].items" },
    };
    for (cases) |case| {
        const text = try std.fmt.allocPrint(
            t.allocator,
            // migrate-embedded: skip intentional O4 marked and unmarked owning-store staging template
            "record Box:\n    items: int[]\nrecord Shelf:\n    cells: FixedArray[int[], 2]\nfunc main() -> int:\n    mut source = [3]\n    {s}\n    {s} = {s}\n    return 0\n",
            .{ case.setup, case.target, case.rhs },
        );
        defer t.allocator.free(text);
        var c = try language.Compilation.init(t.allocator, "own-store-staging.selka", text);
        defer c.deinit();
        try c.checkWithFrontend(null);
        const checked = c.program.?;
        var walker = try language.typed_walk.Walker.init(t.allocator, checked, checked.functions[@backingInt(checked.main)].scope.body);
        defer walker.deinit();
        var found: usize = 0;
        while (try walker.next()) |item| {
            if (item != .statement) continue;
            const statement = checked.statements[@backingInt(item.statement)];
            if (statement.data != .initialize) continue;
            const store = statement.data.initialize;
            const value = checked.nodes[@backingInt(store.value)];
            if (!std.mem.eql(u8, c.src.text(value.span), case.rhs)) continue;
            try t.expect(store.transfer);
            try t.expectEqual(std.mem.startsWith(u8, case.rhs, "own "), value.own);
            found += 1;
        }
        try t.expectEqual(@as(usize, 1), found);
    }
}

test "O4 own field transfer is staged before evaluating a fixed array destination index" {
    var c = try language.Compilation.init(t.allocator, "own-store-order.selka",
        // migrate-embedded: skip intentional O4 original carrier marker and exact store evaluation order
        \\record Carrier:
        \\    items: int[]
        \\    sibling: str
        \\func select_index() -> int:
        \\    return 0
        \\func main() -> int:
        \\    mut carrier = Carrier(items=[3], sibling="held")
        \\    mut values = FixedArray[int[], 2]([[1], [2]])
        \\    values[select_index()] = own carrier.items
        \\    return 0
    );
    defer c.deinit();
    try c.checkWithFrontend(null);
    const checked = c.program.?;
    var walker = try language.typed_walk.Walker.init(t.allocator, checked, checked.functions[@backingInt(checked.main)].scope.body);
    defer walker.deinit();
    var transferred = false;
    var indexed = false;
    while (try walker.next()) |item| {
        switch (item) {
            .statement => |id| {
                const statement = checked.statements[@backingInt(id)];
                if (statement.data != .initialize) continue;
                const store = statement.data.initialize;
                if (!std.mem.eql(u8, c.src.text(checked.nodes[@backingInt(store.value)].span), "own carrier.items")) continue;
                try t.expect(store.transfer);
                try t.expect(!indexed);
                transferred = true;
            },
            .expression => |id| {
                const value = checked.nodes[@backingInt(id)];
                if (value.data != .call or !std.mem.eql(u8, c.src.text(value.span), "select_index()")) continue;
                try t.expect(transferred);
                indexed = true;
            },
        }
    }
    try t.expect(transferred and indexed);
}

test "O4 own read-only receiver staging stays separate from an assignment transfer" {
    var c = try language.Compilation.init(t.allocator, "own-read-staging.selka",
        // migrate-embedded: skip intentional O4 read and transfer uses of the same original source marker
        \\record Box:
        \\    items: int[]
        \\func main() -> int:
        \\    mut source = [1, 2]
        \\    const count = len(own source)
        \\    mut box = Box(items=[0])
        \\    box.items = own source
        \\    return count
    );
    defer c.deinit();
    try c.checkWithFrontend(null);
    const checked = c.program.?;
    var walker = try language.typed_walk.Walker.init(t.allocator, checked, checked.functions[@backingInt(checked.main)].scope.body);
    defer walker.deinit();
    var reads: usize = 0;
    var transfers: usize = 0;
    while (try walker.next()) |item| {
        if (item != .statement) continue;
        const statement = checked.statements[@backingInt(item.statement)];
        if (statement.data != .initialize) continue;
        const store = statement.data.initialize;
        if (!std.mem.eql(u8, c.src.text(checked.nodes[@backingInt(store.value)].span), "own source")) continue;
        if (store.transfer) transfers += 1 else reads += 1;
    }
    try t.expectEqual(@as(usize, 1), transfers);
    try t.expectEqual(@as(usize, 1), reads);
}

test "O4 own assignment staging transfers fresh augmented results" {
    var c = try language.Compilation.init(t.allocator, "own-augmented-staging.selka",
        // migrate-embedded: skip intentional O4 frontend-only augmented store staging control
        \\record Box:
        \\    text: str
        \\func suffix() -> str:
        \\    return "!"
        \\func main() -> int:
        \\    mut box = Box(text="x")
        \\    box.text += suffix()
        \\    mut values = ["x"]
        \\    values[0] += suffix()
        \\    mut cells = FixedArray[str, 2](["x", "y"])
        \\    cells[0] += suffix()
        \\    return 0
    );
    defer c.deinit();
    try c.checkWithFrontend(null);
    const checked = c.program.?;
    var walker = try language.typed_walk.Walker.init(t.allocator, checked, checked.functions[@backingInt(checked.main)].scope.body);
    defer walker.deinit();
    var found: usize = 0;
    while (try walker.next()) |item| {
        if (item != .statement) continue;
        const statement = checked.statements[@backingInt(item.statement)];
        if (statement.data != .initialize) continue;
        const store = statement.data.initialize;
        const value = checked.nodes[@backingInt(store.value)];
        if (value.data != .binary) continue;
        try t.expect(store.transfer);
        found += 1;
    }
    try t.expectEqual(@as(usize, 3), found);
}

test "borrowing syntax requires a return type nonempty names and clause order" {
    try rejectBorrowingGrammar("func f(x: str) from x:\n    return x\n");
    try rejectBorrowingGrammar("func f(x: str) -> str from:\n    return x\n");
    try rejectBorrowingGrammar("func f(x: str) -> str from x,:\n    return x\n");
    try rejectBorrowingGrammar("func f(x: str) -> str fails Error from x:\n    return x\n");
    try rejectBorrowingGrammar("func f(x: str) -> str from x.part:\n    return x\n");
}

// spec: SYNTAX-MUT-1
test "foundation syntax: a mut parameter marker sets the flag and leaves the type span" {
    var c = try language.Compilation.init(t.allocator, "mut.selka",
        \\func fill(mut values: int[], count: int) -> Unit:
        \\    return
    );
    defer c.deinit();
    try c.parse();
    const parameters = c.syntax.?.functions[0].signature.parameters;
    try t.expectEqual(@as(usize, 2), parameters.len);
    try t.expect(parameters[0].mut);
    try t.expectEqualStrings("int[]", c.src.text(parameters[0].ty));
    try t.expect(!parameters[1].mut);
    try t.expectEqualStrings("int", c.src.text(parameters[1].ty));
    try t.expectEqualSlices(u16, &.{0}, c.syntax.?.functions[0].signature.mut_positions);
}

// spec-case: SYNTAX-MUT-1
test "foundation syntax: mut stays an ordinary name in every position outside a marker" {
    var c = try language.Compilation.init(t.allocator, "mut.selka",
        \\func tally(mut: int) -> int:
        \\    mut = mut + 1
        \\    return mut
    );
    defer c.deinit();
    try c.parse();
    const parameters = c.syntax.?.functions[0].signature.parameters;
    try t.expect(!parameters[0].mut);
    try t.expectEqualStrings("int", c.src.text(parameters[0].ty));
    var d = try language.Compilation.init(t.allocator, "mut.selka", "func mut(value: int) -> int:\n    return value\n");
    defer d.deinit();
    try d.parse();
    try t.expectEqualStrings("mut", d.src.text(d.syntax.?.functions[0].name));
}

// spec-case: SYNTAX-MUT-1
test "foundation syntax: a mut call-argument marker wraps its target and leaves other arguments plain" {
    var c = try language.Compilation.init(t.allocator, "mut.selka",
        \\func main() -> int:
        \\    push(mut values, 1)
        \\    return 0
    );
    defer c.deinit();
    try c.parse();
    const parsed_program = c.syntax.?;
    const call = parsed_program.statements.items[@backingInt(bodyOf(parsed_program)[0])].data.discard;
    const arguments = parsed_program.nodes.items[@backingInt(call)].data.call.arguments;
    try t.expectEqual(@as(usize, 2), arguments.len);
    const marker = parsed_program.nodes.items[@backingInt(arguments[0])];
    try t.expect(marker.data == .mut_argument);
    try t.expectEqualStrings("values", nodeText(parsed_program, c.src, marker.data.mut_argument));
    try t.expect(parsed_program.nodes.items[@backingInt(arguments[1])].data == .integer);
}

// spec-case: SYNTAX-MUT-1
test "foundation syntax: the retired ampersand marker is a removed spelling" {
    var c = try language.Compilation.init(t.allocator, "mut.selka",
        \\def main() -> int:
        \\    push(&values)
        \\    return 0
    );
    defer c.deinit();
    try t.expectError(error.SourceError, c.parse());
    const diag = c.diagnostics.items[0];
    try t.expectEqualStrings("E_REMOVED_SPELLING", diag.code);
    try t.expect(std.mem.indexOf(u8, diag.message, "as in `mut value`") != null);
}

// spec-case: SYNTAX-MUT-1
test "foundation syntax: a callback type records one mut flag per parameter" {
    var c = try language.Compilation.init(t.allocator, "mut.selka",
        \\func apply(cb: func(values: mut int[], count: int) -> Unit) -> Unit:
        \\    return
    );
    defer c.deinit();
    try c.parse();
    const callbacks = c.syntax.?.types.expressions.callbacks;
    try t.expectEqual(@as(usize, 1), callbacks.len);
    try t.expectEqual(@as(usize, 2), callbacks[0].parameter_modes.mut.len);
    try t.expect(callbacks[0].parameter_modes.mut[0]);
    try t.expect(!callbacks[0].parameter_modes.mut[1]);
    try t.expectEqualStrings("int[]", c.src.text(callbacks[0].parameters[0]));
}

// spec: SYNTAX-KEYWORD-ONLY-1
test "foundation syntax: a bare star records the keyword-only boundary and frees its ordering rule" {
    var c = try language.Compilation.init(t.allocator, "keywords.selka",
        \\func issue(host: int, named code: int = 13, named file: int) -> Unit:
        \\    return
    );
    defer c.deinit();
    try c.parse();
    const signature = c.syntax.?.functions[0].signature;
    try t.expectEqual(@as(usize, 3), signature.parameters.len);
    try t.expectEqual(@as(?usize, 1), signature.keyword_only_from);
    try t.expect(signature.parameters[1].default_value != null);
    try t.expect(signature.parameters[2].default_value == null);
    var d = try language.Compilation.init(t.allocator, "keywords.selka", "func plain(a: int, b: int) -> Unit:\n    return\n");
    defer d.deinit();
    try d.parse();
    try t.expectEqual(@as(?usize, null), d.syntax.?.functions[0].signature.keyword_only_from);
}

// spec-case: SYNTAX-KEYWORD-ONLY-1
test "foundation syntax: a star with no parameter a repeated star and a callback star are rejected" {
    try parseFailure("def f(a: int, *) -> None:\n    return\n", "E_SYNTAX", "`*` must be followed by at least one parameter", "*");
    try parseFailure("def f(a: int, *, b: int, *, c: int) -> None:\n    return\n", "E_SYNTAX", "`*` may appear once in a parameter list", "*");
    try parseFailure("def f(cb: def(x: int, *) -> None) -> None:\n    return\n", "E_SYNTAX", "`*` is not permitted in a callback type; declare the keyword-only parameters on a function", "*");
}

// spec: SYNTAX-TUPLE-1
test "foundation syntax: a parenthesized comma list builds a tuple and parentheses alone only group" {
    var c = try language.Compilation.init(t.allocator, "tuple.selka",
        // migrate-embedded: skip intentional tuple parser recognition needed for retirement fixes and exact AST assertions
        \\func main() -> int:
        \\    mut pair = (first, second)
        \\    mut trailing = (first, second,)
        \\    mut grouped = (first)
        \\    return 0
    );
    defer c.deinit();
    try c.parse();
    const parsed_program = c.syntax.?;
    const body = bodyOf(parsed_program);
    const pair = parsed_program.nodes.items[@backingInt(parsed_program.statements.items[@backingInt(body[0])].data.binding.value)];
    try t.expect(pair.data == .tuple);
    try t.expectEqual(@as(usize, 2), pair.data.tuple.len);
    try t.expectEqualStrings("first", nodeText(parsed_program, c.src, pair.data.tuple[0]));
    try t.expectEqualStrings("second", nodeText(parsed_program, c.src, pair.data.tuple[1]));
    const trailing = parsed_program.nodes.items[@backingInt(parsed_program.statements.items[@backingInt(body[1])].data.binding.value)];
    try t.expect(trailing.data == .tuple);
    try t.expectEqual(@as(usize, 2), trailing.data.tuple.len);
    const grouped = parsed_program.nodes.items[@backingInt(parsed_program.statements.items[@backingInt(body[2])].data.binding.value)];
    try t.expect(grouped.data == .name);
    try t.expectEqualStrings("first", c.src.text(grouped.data.name));
}

// spec-case: SYNTAX-TUPLE-1
test "foundation syntax: return and a multi-target assignment build a tuple on both sides" {
    var c = try language.Compilation.init(t.allocator, "tuple.selka",
        // migrate-embedded: skip intentional tuple parser recognition needed for retirement fixes and exact AST assertions
        \\func swap(a: int, b: int) -> int:
        \\    a, b = b, a
        \\    return a, b
    );
    defer c.deinit();
    try c.parse();
    const parsed_program = c.syntax.?;
    const body = bodyOf(parsed_program);
    const assignment = parsed_program.nodes.items[@backingInt(parsed_program.statements.items[@backingInt(body[0])].data.discard)];
    try t.expect(assignment.data == .field_assignment);
    const targets = parsed_program.nodes.items[@backingInt(assignment.data.field_assignment.target)];
    const values = parsed_program.nodes.items[@backingInt(assignment.data.field_assignment.value)];
    try t.expect(targets.data == .tuple);
    try t.expect(values.data == .tuple);
    try t.expectEqual(@as(usize, 2), targets.data.tuple.len);
    try t.expectEqual(@as(usize, 2), values.data.tuple.len);
    try t.expectEqualStrings("a", c.src.text(parsed_program.nodes.items[@backingInt(targets.data.tuple[0])].data.name));
    try t.expectEqualStrings("b", c.src.text(parsed_program.nodes.items[@backingInt(targets.data.tuple[1])].data.name));
    try t.expectEqualStrings("b", nodeText(parsed_program, c.src, values.data.tuple[0]));
    try t.expectEqualStrings("a", nodeText(parsed_program, c.src, values.data.tuple[1]));
    const returned = parsed_program.nodes.items[@backingInt(parsed_program.statements.items[@backingInt(body[1])].data.ret)];
    try t.expect(returned.data == .tuple);
    try t.expectEqual(@as(usize, 2), returned.data.tuple.len);
}

// spec-case: SYNTAX-TUPLE-1
test "foundation syntax: a one-element tuple is rejected as a value as a target list and bare" {
    try parseFailure("def main() -> int:\n    x = (1,)\n    return 0\n", "E_SYNTAX", "a one-element tuple is not a value; write the element alone", ",");
    try parseFailure("def main() -> int:\n    pair = (1, 2)\n    x, = pair\n    return 0\n", "E_SYNTAX", "a one-element target list is not a tuple; bind the name directly", ",");
    try parseFailure("def main() -> int:\n    x, y\n    return 0\n", "E_SYNTAX", "a bare comma list is not an expression; tuples were removed, so write one statement per value or use a record with named fields", "x, y");
}

// spec: SYNTAX-TUPLE-2
test "foundation syntax: a tuple type records every element span in the type catalog" {
    var c = try language.Compilation.init(t.allocator, "tuple.selka",
        // migrate-embedded: skip parse-only tuple type source-span catalog witness
        \\func split(text: str) -> tuple[str, str]:
        \\    return text, text
    );
    defer c.deinit();
    try c.parse();
    const tuples = c.syntax.?.types.expressions.tuples;
    try t.expectEqual(@as(usize, 1), tuples.len);
    try t.expectEqual(@as(usize, 2), tuples[0].elements.len);
    try t.expectEqualStrings("str", c.src.text(tuples[0].elements[0]));
    try t.expectEqualStrings("str", c.src.text(tuples[0].elements[1]));
    try t.expectEqualStrings("tuple[str, str]", c.src.text(tuples[0].span));
    try t.expectEqualStrings("tuple[str, str]", c.src.text(c.syntax.?.functions[0].signature.return_type));
}

// spec: SYNTAX-CONDITIONAL-1
test "foundation syntax: a conditional expression binds loosest and nests in its else arm" {
    var c = try language.Compilation.init(t.allocator, "conditional.selka",
        // migrate-embedded: skip original R2 diagnostic, syntax-recognition or exact-output fixture; see L01 r2-preservation classification
        \\func choose(x: int) -> int:
        \\    mut y = if (x > 0) then (42) else (0)
        \\    mut z = if (x > 0) then (1 or 2) else (3 + 4)
        \\    mut w = if (x > 0) then (1) else if ((x < 0)) then ((2)) else ((3))
        \\    return y
    );
    defer c.deinit();
    try c.parse();
    const parsed_program = c.syntax.?;
    const body = bodyOf(parsed_program);
    const y = parsed_program.nodes.items[@backingInt(parsed_program.statements.items[@backingInt(body[0])].data.binding.value)];
    try t.expect(y.data == .conditional);
    try t.expect(parsed_program.nodes.items[@backingInt(y.data.conditional.condition)].data == .binary);
    try t.expect(parsed_program.nodes.items[@backingInt(y.data.conditional.then_value)].data == .integer);
    try t.expect(parsed_program.nodes.items[@backingInt(y.data.conditional.else_value)].data == .integer);
    const z = parsed_program.nodes.items[@backingInt(parsed_program.statements.items[@backingInt(body[1])].data.binding.value)];
    try t.expect(z.data == .conditional);
    try t.expect(parsed_program.nodes.items[@backingInt(z.data.conditional.then_value)].data == .binary);
    try t.expect(parsed_program.nodes.items[@backingInt(z.data.conditional.else_value)].data == .binary);
    const w = parsed_program.nodes.items[@backingInt(parsed_program.statements.items[@backingInt(body[2])].data.binding.value)];
    try t.expect(w.data == .conditional);
    try t.expect(parsed_program.nodes.items[@backingInt(w.data.conditional.else_value)].data == .conditional);
}

// spec: SYNTAX-CONDITIONAL-2
test "foundation syntax: a conditional expression parses in arguments holes lists returns and fields" {
    var c = try language.Compilation.init(t.allocator, "conditional.selka",
        // migrate-embedded: skip original R2 diagnostic, syntax-recognition or exact-output fixture; see L01 r2-preservation classification
        \\func choose(p: bool) -> int:
        \\    f(if (p) then (1) else (2), value=if (p) then (3) else (4))
        \\    mut items = [if (p) then (5) else (6)]
        \\    mut label = f"{if (p) then (7) else (8)}"
        \\    return if (p) then (9) else (10)
    );
    defer c.deinit();
    // This fixture tests retained syntax recognition, not target acceptance.
    // Migration dialect keeps the exact old AST without publishing repairs.
    const allocator = c.arena.allocator();
    var sink: diagnostic.Sink = .{ .allocator = allocator };
    c.tokens = try lexer.lex(allocator, c.src.bytes, &sink);
    var recognition: parser.Parser = .{
        .src = c.src,
        .storage = allocator,
        .tokens = c.tokens.?,
        .sink = &sink,
        .cursor = .{ .dialect = .migration },
    };
    c.syntax = try recognition.parse();
    try t.expectEqual(@as(usize, 0), sink.items.items.len);
    const parsed_program = c.syntax.?;
    const body = bodyOf(parsed_program);
    const call_node = parsed_program.nodes.items[@backingInt(parsed_program.statements.items[@backingInt(body[0])].data.discard)];
    const call = call_node.data.call;
    try t.expectEqual(@as(usize, 2), call.arguments.len);
    try t.expect(parsed_program.nodes.items[@backingInt(call.arguments[0])].data == .conditional);
    try t.expect(parsed_program.nodes.items[@backingInt(call.arguments[1])].data == .conditional);
    try t.expectEqualStrings("value", c.src.text(call.argument_names[1].?));
    const items = parsed_program.nodes.items[@backingInt(parsed_program.statements.items[@backingInt(body[1])].data.binding.value)];
    try t.expect(items.data == .list_literal);
    try t.expect(parsed_program.nodes.items[@backingInt(items.data.list_literal[0])].data == .conditional);
    const label = parsed_program.nodes.items[@backingInt(parsed_program.statements.items[@backingInt(body[2])].data.binding.value)];
    try t.expect(label.data == .format);
    try t.expect(parsed_program.nodes.items[@backingInt(label.data.format[0])].data == .conditional);
    const returned = parsed_program.nodes.items[@backingInt(parsed_program.statements.items[@backingInt(body[3])].data.ret)];
    try t.expect(returned.data == .conditional);
}

// spec-case: PYTHON-1
test "redesign parser preserves declarations failure signatures and source-first expressions" {
    const text =
        // migrate-embedded: skip original R2 diagnostic, syntax-recognition or exact-output fixture; see L01 r2-preservation classification
        \\enum Error:
        \\    bad(message: str)
        \\
        \\type Handler = func(mut values: int[], named limit: int) -> Unit fails Error
        \\
        \\func transform(mut values: int[], named mut amount: int, named limit: int = 10) -> int? fails Error:
        \\    const copied: int[] = [for value in values if value > 0 yield value + amount]
        \\    mut fixed: FixedArray[int, 2] = make_fixed()
        \\    const selected = if limit > 0 then copied[0] else 0
        \\    const answer = try compute(selected)
        \\    with try open_file() as file:
        \\        inspect(file)
        \\    if answer == 0:
        \\        fail Error.bad(message="zero")
        \\    return answer
    ;
    var c = try language.Compilation.init(t.allocator, "redesign.selka", text);
    defer c.deinit();
    try c.parse();
    const syntax = c.syntax.?;
    const signature = syntax.functions[0].signature;
    try t.expect(signature.failure_type != null);
    try t.expect(signature.parameters[0].mut);
    try t.expect(signature.parameters[1].mut and signature.parameters[1].named);
    try t.expectEqual(@as(?usize, 1), signature.keyword_only_from);
    try t.expect(syntax.types.expressions.suffixes.len >= 4);
    try t.expect(syntax.types.expressions.callbacks[0].failure_type != null);
    try t.expect(syntax.types.expressions.callbacks[0].parameter_modes.named[1]);
    try t.expect(syntax.types.variants[0].cases[0].fields.len == 1);
    try assertPropagationSpans(&c);
}

// spec-case: PYTHON-1
test "redesign parser accepts match expression yields and named payload patterns" {
    const text =
        \\func choose(value: Choice) -> int:
        \\    const answer = match value:
        \\        case number(value=number):
        \\            yield number
        \\        case _:
        \\            yield 0
        \\    return answer
    ;
    var c = try language.Compilation.init(t.allocator, "redesign_match.selka", text);
    defer c.deinit();
    try c.parse();
    try assertExpressionPattern(&c);
}

fn expectReservedNameMessage(word: []const u8, text: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "reserved.selka", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.parse());
    const message = c.diagnostics.items[0].message;
    try t.expectEqualStrings("E_SYNTAX", c.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, message, word) != null);
    try t.expect(std.mem.indexOf(u8, message, "reserved word") != null);
}

// spec: RESERVED-NAME-1
test "a reserved word where a function name belongs is named in the diagnostic" {
    try expectReservedNameMessage("`wrap`", "func wrap(value: int) -> int:\n    return value\n");
    // `unwrap` is a contextual word since batch 0: a declaration may be named it,
    // while `x.unwrap` still earns the extraction hint and `unwrap(value)` stays the
    // retired scalar-domain form the migration rewrites.
    try expectReservedNameMessage("`domain`", "func domain(value: int) -> int:\n    return value\n");
    try expectReservedNameMessage("`todo`", "func todo(value: int) -> int:\n    return value\n");
    try expectReservedNameMessage("`wrap`", "func main() -> int:\n    return wrap(1)\n");
}

// spec: RESERVED-NAME-1
test "replace is a contextual word: a declaration keeps its own call" {
    // The word is an ordinary identifier, so a file may declare `replace` and call
    // it; the intrinsic forms (`replace(a, i, v)` and the record update) are what
    // remain when the file declares nothing.
    const text = "func replace(values: int[], index: int, value: int) -> int:\n    return values[index] + value\n\n\nfunc main() -> int:\n    return replace([1, 2], 0, 3)\n";
    var c = try language.Compilation.init(t.allocator, "replace_contextual.selka", text);
    defer c.deinit();
    try c.parse();
    try c.check();
    try t.expectEqual(@as(usize, 0), c.diagnostics.items.len);
}

// spec-case: PYTHON-1
test "redesign parser rejects propagation over an operator expression with the operator-outside guidance" {
    var c = try language.Compilation.init(t.allocator, "redesign_try.selka", "func main() -> int:\n    const value = consume(try (compute() + 1))\n    return value\n");
    defer c.deinit();
    try t.expectError(error.SourceError, c.parse());
    try t.expectEqualStrings("E_TRY_POSITION", c.diagnostics.items[0].code);
    // TRYARG: `try` and its operand as a whole argument parse.
    var argument = try language.Compilation.init(t.allocator, "redesign_try.selka", "func main() -> int:\n    const value = consume(try compute())\n    return value\n");
    defer argument.deinit();
    try argument.parse();
    try t.expectEqual(@as(usize, 0), argument.diagnostics.items.len);
    // TRY-2: `try` binds to the call after it, so an operator after the call takes its value.
    var operand = try language.Compilation.init(t.allocator, "redesign_try.selka", "func main() -> int:\n    const value = consume(try compute() + 1)\n    return value\n");
    defer operand.deinit();
    try operand.parse();
    try t.expectEqual(@as(usize, 0), operand.diagnostics.items.len);
}

// spec-case: PYTHON-1
test "redesign parser preserves nested variant payload pattern tree" {
    const text = "func choose(value: Outcome) -> int:\n    match value:\n        case Err(Error.bad(message=text)):\n            return 1\n        case Ok(number):\n            return number\n";
    var c = try language.Compilation.init(t.allocator, "nested_pattern.selka", text);
    defer c.deinit();
    try c.parse();
    try assertNestedPattern(&c);
}

// spec-case: PYTHON-1
test "redesign parser diagnoses duplicate mutation modifiers" {
    var c = try language.Compilation.init(t.allocator, "duplicate_mut.selka", "func helper(mut value: mut int):\n    pass\n");
    defer c.deinit();
    try t.expectError(error.SourceError, c.parse());
    try t.expectEqualStrings("E_PARAMETER_MODIFIER", c.diagnostics.items[0].code);
}

// spec-case: PYTHON-1
test "redesign parser requires names on labelled callable parameters" {
    var c = try language.Compilation.init(t.allocator, "named_callback.selka", "type Handler = func(named int) -> Unit\nfunc main():\n    pass\n");
    defer c.deinit();
    try t.expectError(error.SourceError, c.parse());
    try t.expectEqualStrings("E_PARAMETER_NAME", c.diagnostics.items[0].code);
}

// spec-case: PYTHON-1
test "a parameter called named is a name, not the modifier, in a function and in a callback type (F-78)" {
    const text = "func count(named: int[], named named: int) -> int:\n    return len(named)\n\n" ++
        "func use(f: func(named: int, named named: int) -> int) -> int:\n    return f(1, named=2)\n";
    var c = try language.Compilation.init(t.allocator, "named_name.selka", text);
    defer c.deinit();
    try c.parse();
    const syntax = c.syntax.?;
    const parameters = syntax.functions[0].signature.parameters;
    try t.expectEqualStrings("named", c.src.text(parameters[0].name));
    try t.expect(!parameters[0].named);
    try t.expectEqualStrings("named", c.src.text(parameters[1].name));
    try t.expect(parameters[1].named);
    try t.expectEqual(@as(?usize, 1), syntax.functions[0].signature.keyword_only_from);
    const modes = syntax.types.expressions.callbacks[0].parameter_modes.named;
    try t.expect(!modes[0] and modes[1]);
}

// spec-case: PYTHON-1
test "a named in a callback type before a comma or a closing parenthesis is a bare type, as own and mut would be (F-78)" {
    var c = try language.Compilation.init(t.allocator, "named_type.selka", "record named:\n    v: int\n\nfunc use(f: func(named) -> int, g: func(named, int) -> int) -> int:\n    return 0\n");
    defer c.deinit();
    try c.parse();
    const callbacks = c.syntax.?.types.expressions.callbacks;
    try t.expect(!callbacks[0].parameter_modes.named[0]);
    try t.expectEqualStrings("named", c.src.text(callbacks[0].parameters[0]));
    try t.expect(!callbacks[1].parameter_modes.named[0]);
    try t.expectEqual(@as(usize, 2), callbacks[1].parameters.len);
}

// spec-case: PYTHON-1
test "a modifier named with no name after it is still refused, in a function and in a callback type (F-78)" {
    var function = try language.Compilation.init(t.allocator, "named_none.selka", "func count(named = 3) -> int:\n    return 0\n");
    defer function.deinit();
    try t.expectError(error.SourceError, function.parse());
    try t.expectEqualStrings("E_SYNTAX", function.diagnostics.items[0].code);
    var callback = try language.Compilation.init(t.allocator, "named_callback_none.selka", "type Handler = func(named [int]) -> Unit\nfunc main():\n    pass\n");
    defer callback.deinit();
    try t.expectError(error.SourceError, callback.parse());
    try t.expectEqualStrings("E_PARAMETER_NAME", callback.diagnostics.items[0].code);
}

fn assertPropagationSpans(c: *language.Compilation) !void {
    var propagation_count: usize = 0;
    for (c.syntax.?.nodes.items) |node| if (node.data == .propagate) {
        propagation_count += 1;
        try t.expect(std.mem.startsWith(u8, c.src.text(node.span), "try "));
    };
    try t.expectEqual(@as(usize, 2), propagation_count);
}

fn assertExpressionPattern(c: *language.Compilation) !void {
    var found = false;
    for (c.syntax.?.nodes.items) |node| if (node.data == .match_expression) {
        found = true;
        try t.expectEqual(@as(usize, 2), node.data.match_expression.arms.len);
        try t.expectEqualStrings("value", c.src.text(node.data.match_expression.arms[0].binding_names[0].?));
    };
    try t.expect(found);
}

fn assertNestedPattern(c: *language.Compilation) !void {
    var found = false;
    for (c.syntax.?.statements.items) |statement| if (statement.data == .match) {
        const nested = statement.data.match.arms[0].payload_patterns[0].pattern;
        try t.expect(nested.data == .variant);
        try t.expectEqualStrings("bad", c.src.text(nested.data.variant.name));
        try t.expectEqualStrings("message", c.src.text(nested.data.variant.fields[0].name.?));
        try t.expectEqualStrings("text", c.src.text(nested.data.variant.fields[0].pattern.data.binding.?));
        found = true;
    };
    try t.expect(found);
}

// spec-case: SYNTAX-MUT-1
test "generic call arguments accept optional array and callable types" {
    var compilation = try language.Compilation.init(t.allocator, "generic-types.selka",
        \\func main() -> int:
        \\    const fixed = FixedArray[Pair?, 2]([None, None])
        \\    consume[int[]?](fixed)
        \\    Factory[func(named mut values: int[]) -> int? fails Error](callback)
        \\    owner.use[func(named amount: int) -> int](callback)
        \\    return 0
    );
    defer compilation.deinit();
    try compilation.parse();
    try t.expectEqual(@as(usize, 2), compilation.syntax.?.types.expressions.callbacks.len);
    try t.expect(compilation.syntax.?.types.expressions.suffixes.len >= 4);
}

// spec-case: SYNTAX-TUPLE-1
test "tuple declarations retain explicit mutability and boundary propagation" {
    var compilation = try language.Compilation.init(t.allocator, "tuple-bindings.selka",
        // migrate-embedded: skip intentional tuple parser recognition needed for retirement fixes and exact AST assertions
        \\func main() -> int:
        \\    const left, right = pair()
        \\    mut first, second = (1, 2)
        \\    first, second = (second, first)
        \\    return 0
    );
    defer compilation.deinit();
    try compilation.parse();
    const parsed_program = compilation.syntax.?;
    const body = bodyOf(parsed_program);
    const immutable = parsed_program.nodes.items[@backingInt(parsed_program.statements.items[@backingInt(body[0])].data.discard)].data.field_assignment;
    const mutable = parsed_program.nodes.items[@backingInt(parsed_program.statements.items[@backingInt(body[1])].data.discard)].data.field_assignment;
    const assigned = parsed_program.nodes.items[@backingInt(parsed_program.statements.items[@backingInt(body[2])].data.discard)].data.field_assignment;
    try t.expectEqual(@as(?bool, false), immutable.declaration);
    try t.expectEqual(@as(?bool, true), mutable.declaration);
    try t.expectEqual(@as(?bool, null), assigned.declaration);
}

// spec-case: SYNTAX-CONDITIONAL-2
test "conditional indexed conditions do not look like applied constructors" {
    var compilation = try language.Compilation.init(t.allocator, "condition.selka",
        // migrate-embedded: skip original R2 diagnostic, syntax-recognition or exact-output fixture; see L01 r2-preservation classification
        \\func choose(flags: bool[]) -> int:
        \\    return 2 + (if (flags[0]) then (1) else (0))
    );
    defer compilation.deinit();
    try compilation.parse();
}

// spec: TYPED-RANGE-1
test "source shaped typed ranges retain endpoint spans and walker call order" {
    const input =
        \\func first() -> int:
        \\    return 1
        \\
        \\func last() -> int:
        \\    return 4
        \\
        \\func stride() -> int:
        \\    return 1
        \\
        \\func main() -> int:
        \\    mut total = 0
        \\    for item in range(first(), last(), stride()):
        \\        total += item
        \\    return total
    ;
    var compilation = try language.Compilation.init(t.allocator, "typed-range.selka", input);
    defer compilation.deinit();
    try compilation.check();
    const checked = compilation.program.?;
    var calls = try assertRangeShape(compilation.src, checked);
    defer calls.deinit(t.allocator);
    try t.expectEqual(@as(usize, 3), calls.items.len);
    try t.expectEqualStrings("first", calls.items[0]);
    try t.expectEqualStrings("last", calls.items[1]);
    try t.expectEqualStrings("stride", calls.items[2]);
    try t.expectEqual(@as(i64, 6), (try native.run(&compilation)).value);
}

fn assertRangeShape(src: source.Source, checked: language.typed.Program) !std.ArrayList([]const u8) {
    var found = false;
    for (checked.statements) |statement| {
        if (statement.data != .range_loop) continue;
        const range = statement.data.range_loop;
        found = true;
        try t.expectEqualStrings("item", src.text(range.plan().binding));
        try t.expectEqualStrings("first()", src.text(checked.nodes[@backingInt(range.plan().start.value)].span));
        try t.expectEqualStrings("last()", src.text(checked.nodes[@backingInt(range.plan().end.value)].span));
    }
    try t.expect(found);
    var walker = try @import("typed_walk.zig").Walker.init(t.allocator, checked, checked.functions[@backingInt(checked.main)].scope.body);
    defer walker.deinit();
    var calls: std.ArrayList([]const u8) = .empty;
    errdefer calls.deinit(t.allocator);
    while (try walker.next()) |item| switch (item) {
        .expression => |id| {
            const node = checked.nodes[@backingInt(id)];
            if (node.data == .call) try calls.append(t.allocator, checked.functions[@backingInt(node.data.call.function)].name);
        },
        else => {},
    };
    return calls;
}

test "checked docs lint exempts constants tests and facade declarations and requires examples" {
    const library =
        "\"\"\"Arithmetic for the example fixture.\"\"\"\n" ++
        "public const ANSWER: int = 42\n" ++
        "public func ready() -> int:\n    \"\"\"The answer as a complete example.\n\n    >>> ready()\n    42\n    \"\"\"\n    return ANSWER\n" ++
        "public func missing() -> int:\n    \"\"\"The answer without an example.\"\"\"\n    return ANSWER\n" ++
        "# lint: allow missing-example reason=\"covered through an external socket fixture\"\n" ++
        "public func waived() -> int:\n    \"\"\"The external integration answer.\"\"\"\n    return ANSWER\n" ++
        "public func bench_answer() -> int:\n    \"\"\"A normal public benchmark function.\"\"\"\n    return ANSWER\n" ++
        "public func test_existing() -> bool:\n    return ready() == ANSWER\n";
    var files: DocFiles = .{ .entries = &.{ .{ .path = "main.selka", .bytes = "import library\nexport library.ready\nfunc main() -> int:\n    return 0\n" }, .{ .path = "library.selka", .bytes = library } } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var findings: std.ArrayList(language.lint.Finding) = .empty;
    try language.lint.appendProjectDocumentation(a, &index, project.order.items, 12, &findings);
    try t.expectEqual(@as(usize, 3), findings.items.len);
    try t.expectEqualStrings("L_MISSING_EXAMPLE", findings.items[0].code);
    try t.expectEqualStrings("library::missing", findings.items[0].subject.qualified);
    try t.expectEqualStrings("library::bench_answer", findings.items[1].subject.qualified);
    try t.expectEqualStrings("L_UNDOCUMENTED_MODULE", findings.items[2].code);
    try t.expectEqual(diagnostic.Severity.err, findings.items[0].state.severity);
    try t.expectEqual(language.lint_config.Mode.off, ruleNamed("missing-example").modes.agent);
    try t.expectEqual(language.lint_config.Mode.report, ruleNamed("missing-example").modes.strict);
    try t.expectEqual(language.lint_config.Mode.off, ruleNamed("undocumented-module").modes.agent);
    try t.expectEqual(language.lint_config.Mode.report, ruleNamed("undocumented-module").modes.safety);
}

test "checked docs waiverReason shares attribute comment and empty reason semantics" {
    const text =
        "# lint: allow missing-example reason=\"a comment reason\"\n" ++
        "public func comment() -> int:\n    return 1\n" ++
        "@allow(\"missing-example\", reason=\"an attribute reason\")\n" ++
        "public func attributed() -> int:\n    return 2\n" ++
        "# lint: allow missing-example reason=\" \"\n" ++
        "public func empty() -> int:\n    return 3\n" ++
        "func main() -> int:\n    return 0\n";
    var unit = try language.Compilation.init(t.allocator, "waivers.selka", text);
    defer unit.deinit();
    try unit.parse();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const syntax = unit.syntax.?;
    try t.expectEqualStrings("a comment reason", (try language.lint.waiverReason(arena.allocator(), unit.src, syntax, syntax.functions[0].name, "missing-example")).?);
    try t.expectEqualStrings("an attribute reason", (try language.lint.waiverReason(arena.allocator(), unit.src, syntax, syntax.functions[1].name, "missing-example")).?);
    try t.expectEqual(@as(?[]const u8, null), try language.lint.waiverReason(arena.allocator(), unit.src, syntax, syntax.functions[2].name, "missing-example"));
    try t.expectEqual(@as(?[]const u8, null), try language.lint.waiverReason(arena.allocator(), unit.src, syntax, syntax.functions[0].name, "undocumented-export"));
}

test "checked docs waiverReason preserves escaped quotes instead of truncating prose" {
    const text =
        \\# lint: allow missing-example reason="calls \"external\" adapter"
        \\public func value() -> int:
        \\    return 42
        \\@allow("missing-example", reason="calls \"external\" adapter")
        \\public func attributed() -> int:
        \\    return 42
        \\func main() -> int:
        \\    return 0
    ;
    var unit = try language.Compilation.init(t.allocator, "reason.selka", text);
    defer unit.deinit();
    try unit.parse();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try t.expectEqualStrings("calls \\\"external\\\" adapter", (try language.lint.waiverReason(arena.allocator(), unit.src, unit.syntax.?, unit.syntax.?.functions[0].name, "missing-example")).?);
    try t.expectEqualStrings("calls \\\"external\\\" adapter", (try language.lint.waiverReason(arena.allocator(), unit.src, unit.syntax.?, unit.syntax.?.functions[1].name, "missing-example")).?);
}

test "F2 own before minus remains a binary name expression" {
    var c = try language.Compilation.init(t.allocator, "own-minus.selka", "func main() -> int:\n    const own = 10\n    return own - 1\n");
    defer c.deinit();
    try c.parse();
    const p = c.syntax.?;
    const body = p.statements.items[@backingInt(p.functions[0].body)].data.block;
    const returned = p.statements.items[@backingInt(body[1])].data.ret;
    const node = p.nodes.items[@backingInt(returned)];
    try t.expect(node.data == .binary);
    try t.expectEqual(ast.BinaryOp.sub, node.data.binary.op);
    try t.expectEqualStrings("own", c.src.text(p.nodes.items[@backingInt(node.data.binary.left)].data.name));
}

// Q2: before punctuation/literals `own` is a name, not an expression marker.
test "F2 own before parentheses and brackets stays an ordinary contextual identifier" {
    var c = try language.Compilation.init(t.allocator, "own-name.selka",
        \\func draft():
        \\    const call = own (value)
        \\    const index = own [0]
    );
    defer c.deinit();
    try c.parse();
    const p = c.syntax.?;
    const body = p.statements.items[@backingInt(p.functions[0].body)].data.block;
    const call = p.nodes.items[@backingInt(p.statements.items[@backingInt(body[0])].data.binding.value)];
    const index = p.nodes.items[@backingInt(p.statements.items[@backingInt(body[1])].data.binding.value)];
    try t.expect(call.data == .call);
    try t.expectEqualStrings("own", c.src.text(call.data.call.name));
    try t.expect(index.data == .index);
    try t.expectEqualStrings("own", c.src.text(p.nodes.items[@backingInt(index.data.index.base)].data.name));
}

test "F2 own before a migration conditional stays an ordinary name" {
    var c = try language.Compilation.init(t.allocator, "own-conditional.selka",
        // migrate-embedded: skip intentional retired conditional parser recognition.
        \\func select(own: int, flag: bool, fallback: int) -> int:
        \\    return own if flag else fallback
    );
    defer c.deinit();
    // Target syntax refuses conditional expressions independently of Q2.
    const allocator = c.arena.allocator();
    var sink: diagnostic.Sink = .{ .allocator = allocator };
    c.tokens = try lexer.lex(allocator, c.src.bytes, &sink);
    var recognition: parser.Parser = .{
        .src = c.src,
        .storage = allocator,
        .tokens = c.tokens.?,
        .sink = &sink,
        .cursor = .{ .dialect = .migration },
    };
    c.syntax = try recognition.parse();
    try t.expectEqual(@as(usize, 0), sink.items.items.len);
    const p = c.syntax.?;
    const body = p.statements.items[@backingInt(p.functions[0].body)].data.block;
    const returned = p.nodes.items[@backingInt(p.statements.items[@backingInt(body[0])].data.ret)];
    try t.expect(returned.data == .conditional);
    const selected = p.nodes.items[@backingInt(returned.data.conditional.then_value)];
    try t.expect(selected.data == .name);
    try t.expectEqualStrings("own", c.src.text(selected.data.name));
}

test "F2 own before a comment cannot consume the next statement as a marker operand" {
    // migrate-embedded: skip intentional contextual-name parser boundary witness.
    var c = try language.Compilation.init(t.allocator, "own-newline.selka",
        \\func draft():
        \\    const own = 10
        \\    const selected = own # This comment ends the statement.
        \\    step()
        \\    return selected
    );
    defer c.deinit();
    try c.parse();
    const p = c.syntax.?;
    const body = p.statements.items[@backingInt(p.functions[0].body)].data.block;
    try t.expectEqual(@as(usize, 4), body.len);
    const selected = p.nodes.items[@backingInt(p.statements.items[@backingInt(body[1])].data.binding.value)];
    try t.expect(selected.data == .name);
    try t.expectEqualStrings("own", c.src.text(selected.data.name));
    const step = p.nodes.items[@backingInt(p.statements.items[@backingInt(body[2])].data.discard)];
    try t.expect(step.data == .call);
    try t.expectEqualStrings("step", c.src.text(step.data.call.name));
}

test "F2 own marker continues after a comment inside parentheses" {
    // migrate-embedded: skip intentional grouped marker parser continuation witness.
    var c = try language.Compilation.init(t.allocator, "own-continuation.selka",
        \\func draft():
        \\    const selected = (own # The open group continues the marker operand.
        \\        value)
    );
    defer c.deinit();
    try c.parse();
    const p = c.syntax.?;
    const body = p.statements.items[@backingInt(p.functions[0].body)].data.block;
    const selected = p.nodes.items[@backingInt(p.statements.items[@backingInt(body[0])].data.binding.value)];
    try t.expect(selected.data == .own_argument);
    const value = p.nodes.items[@backingInt(selected.data.own_argument)];
    try t.expect(value.data == .name);
    try t.expectEqualStrings("value", c.src.text(value.data.name));
}

/// The text with every edit of `fix` applied, edits in source order.
fn repaired(text: []const u8, fix: diagnostic.Fix) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(t.allocator);
    var at: usize = 0;
    for (0..fix.count()) |index| {
        const edit = fix.at(index);
        try out.appendSlice(t.allocator, text[at..edit.span.start]);
        try out.appendSlice(t.allocator, edit.text);
        at = edit.span.end;
    }
    try out.appendSlice(t.allocator, text[at..]);
    return out.toOwnedSlice(t.allocator);
}

/// Check `text`: the first diagnostic has `code` and `message`, and its repair makes `after`, or there is none when `after` is null.
fn expectContinuation(text: []const u8, code: []const u8, message: []const u8, after: ?[]const u8) !void {
    var c = try language.Compilation.init(t.allocator, "continue.selka", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    const item = c.diagnostics.items[0];
    try t.expectEqualStrings(code, item.code);
    try t.expectEqualStrings(message, item.message);
    const wanted = after orelse return t.expect(item.provenance.fix == null);
    const text_after = try repaired(text, item.provenance.fix.?);
    defer t.allocator.free(text_after);
    try t.expectEqualStrings(wanted, text_after);
}

// spec-case: PYTHON-1
test "R3-CONTINUE a binary operator that ends a line is not a continuation: parentheses are, and the repair writes them" {
    const advice = "an expression continues on the next line only inside parentheses, so a line ending in `+` ends there: " ++
        "write `(a +` ... `b)`";
    try expectContinuation(
        \\func main() -> int:
        \\    const total = 1 +
        \\        2
        \\    return total
        \\
    , "E_INDENTATION", advice,
        \\func main() -> int:
        \\    const total = (1 +
        \\        2)
        \\    return total
        \\
    );
    // Several continuation lines, one of them already in brackets, and a `return`.
    try expectContinuation(
        \\func f(a: int) -> int:
        \\    return a +
        \\        f(1 +
        \\          2) +
        \\        3
        \\
    , "E_INDENTATION", advice,
        \\func f(a: int) -> int:
        \\    return (a +
        \\        f(1 +
        \\          2) +
        \\        3)
        \\
    );
    // A condition: the colon stays outside the parentheses.
    const and_advice = "an expression continues on the next line only inside parentheses, so a line ending in `and` ends there: " ++
        "write `(a and` ... `b)`";
    try expectContinuation(
        \\func main() -> int:
        \\    if 1 == 1 and
        \\            2 == 2:
        \\        return 1
        \\    return 0
        \\
    , "E_INDENTATION", and_advice,
        \\func main() -> int:
        \\    if (1 == 1 and
        \\            2 == 2):
        \\        return 1
        \\    return 0
        \\
    );
}

// spec-case: PYTHON-1
test "R3-CONTINUE a line continued after an operator keeps the advice and offers no repair where the expression is not certain" {
    const advice = "an expression continues on the next line only inside parentheses, so a line ending in `+` ends there: " ++
        "write `(a +` ... `b)`";
    try expectContinuation("func main() -> int:\n    return 1 +\n        2, 3\n", "E_INDENTATION", advice, null);
    // An indented line after a line that does not end in an operator keeps the plain message.
    const plain = "unexpected indentation or dedent does not match an enclosing block";
    try expectContinuation("func main() -> int:\n    const x = 1\n        return x\n", "E_INDENTATION", plain, null);
}

// spec-case: PYTHON-1
test "R3-CONTINUE a backslash that ends a line is refused with the parentheses to write, and the repair writes them" {
    const advice = "a backslash does not continue a line: an expression continues on the next line only inside parentheses, " ++
        "so write `(a +` ... `b)` and no backslash";
    try expectContinuation(
        \\func main() -> int:
        \\    const x = 1 + \
        \\        2
        \\    return x
        \\
    , "E_TOKEN", advice,
        \\func main() -> int:
        \\    const x = (1 +
        \\        2)
        \\    return x
        \\
    );
    // Every backslash of the statement goes, and the parentheses are written once.
    try expectContinuation(
        \\func main() -> int:
        \\    const x = 1 + \
        \\        2 \
        \\        + 3
        \\    return x
        \\
    , "E_TOKEN", advice,
        \\func main() -> int:
        \\    const x = (1 +
        \\        2
        \\        + 3)
        \\    return x
        \\
    );
    try expectContinuation(
        \\func main() -> int:
        \\    if 1 == 1 and \
        \\            2 == 2:
        \\        return 1
        \\    return 0
        \\
    , "E_TOKEN", advice,
        \\func main() -> int:
        \\    if (1 == 1 and
        \\            2 == 2):
        \\        return 1
        \\    return 0
        \\
    );
    // Inside brackets the line goes on without a backslash: delete it.
    const bracketed = "a backslash does not continue a line, and inside brackets the line goes on without one: delete it";
    try expectContinuation(
        \\func main() -> int:
        \\    const x = max(1, \
        \\        2)
        \\    return x
        \\
    , "E_TOKEN", bracketed,
        \\func main() -> int:
        \\    const x = max(1,
        \\        2)
        \\    return x
        \\
    );
    // A statement of another shape has the advice and no repair.
    try expectContinuation("func main() -> int:\n    return 1 + \\\n        2, 3\n", "E_TOKEN", advice, null);
    // A backslash in the middle of a line is still only an unexpected character.
    try expectContinuation("func main() -> int:\n    return 1 \\ 2\n", "E_TOKEN", "unexpected character in source", null);
}
