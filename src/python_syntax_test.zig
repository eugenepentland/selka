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
    \\class Point:
    \\    x: int
    \\    y: int
    \\
    \\
    \\def noop():
    \\    pass
    \\
    \\
    \\def main() -> int:
    \\    noop()
    \\    p = Point(x=40, y=2)
    \\    total: int = 0
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
    var c = try language.Compilation.init(allocator, "python.my", program);
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
    const text = "def main() -> int:\n    # ignored\n\n    return (\n        40 +\n        2\n    )\n";
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
    var c = try language.Compilation.init(t.allocator, "continuation.my", text);
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
        var c = try language.Compilation.init(t.allocator, "indent.my", text);
        defer c.deinit();
        try t.expectError(error.SourceError, c.check());
        try t.expectEqualStrings("E_INDENTATION", c.diagnostics.items[0].code);
    }
}

// spec-case: PYTHON-2
test "Python parameters rebind and existing locals update across blocks" {
    const text = "def bump[T: integer](value: T) -> T:\n    value = value + value\n    return value\n\ndef main() -> int:\n    answer = 0\n    if True:\n        answer = bump(21)\n    return answer\n";
    var c = try language.Compilation.init(t.allocator, "scope.my", text);
    defer c.deinit();
    try t.expectEqual(@as(i64, 42), (try native.run(&c)).value);
    // A name assigned only on one branch is not definitely bound afterwards.
    var bad = try language.Compilation.init(t.allocator, "scope.my", "def main() -> int:\n    if True:\n        answer = 42\n    return answer\n");
    defer bad.deinit();
    try t.expectError(error.SourceError, bad.check());
    try t.expectEqualStrings("E_UNBOUND", bad.diagnostics.items[0].code);
}

fn scopeValue(text: []const u8) !i64 {
    var c = try language.Compilation.init(t.allocator, "scope.my", text);
    defer c.deinit();
    return (try native.run(&c)).value;
}

fn scopeReject(text: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "scope.my", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

// An augmented field assignment keeps the rules plain field assignment and a
// binding's augmented form have: `/=` on an integer field is a type error.
// spec-case: AUGMENTED-FIELD-1
test "augmented field assignment keeps the operator and mutation rules" {
    try scopeReject("class Box:\n    n: int\n\ndef main() -> int:\n    b = Box(n=4)\n    b.n /= 2\n    return b.n\n", "E_TYPE");
    try t.expectEqual(@as(i64, 12), try scopeValue("class Box:\n    n: int\n    f: float\n\ndef main() -> int:\n    b = Box(n=4, f=1.0)\n    b.n *= 3\n    b.f /= 4.0\n    return b.n\n"));
}

// spec-case: PY-SCOPE-2
test "PY-SCOPE-2 assignments only in a loop body are unbound after the loop" {
    try scopeReject(
        \\def main() -> int:
        \\    while False:
        \\        answer = 42
        \\    return answer
    , "E_UNBOUND");
    try scopeReject(
        \\def main() -> int:
        \\    for item in [1, 2]:
        \\        answer = item
        \\    return answer
    , "E_UNBOUND");
    try scopeReject(
        \\def main() -> int:
        \\    for item in range(2):
        \\        answer = item
        \\    return answer
    , "E_UNBOUND");
    try scopeReject(
        \\def main() -> int:
        \\    for item in reversed([1, 2]):
        \\        answer = item
        \\    return answer
    , "E_UNBOUND");
    try scopeReject(
        \\def main() -> int:
        \\    for a, b in zip([1, 2], [3, 4]):
        \\        answer = a + b
        \\    return answer
    , "E_UNBOUND");
}

// spec: PY-SCOPE-2
test "PY-SCOPE-2 reading a name unbound on some path is rejected" {
    try scopeReject(
        \\def main() -> int:
        \\    flag = True
        \\    if flag:
        \\        chosen = 5
        \\    return chosen
    , "E_UNBOUND");
    // A name never assigned before the read stays E_UNKNOWN_NAME.
    try scopeReject(
        \\def main() -> int:
        \\    return missing
    , "E_UNKNOWN_NAME");
    // A method call reads its receiver, so a maybe-unbound owner is rejected too.
    try scopeReject(
        \\def main() -> int:
        \\    flag = True
        \\    if flag:
        \\        data = [1, 2]
        \\    data.append(3)
        \\    return 0
    , "E_UNBOUND");
}

const match_choice =
    \\enum Choice:
    \\    first,
    \\    second
    \\
    \\
;

// spec-case: PY-SCOPE-3
test "match rejects locals unassigned on a continuing arm" {
    try scopeReject(match_choice ++
        \\def main() -> int:
        \\    match Choice.first:
        \\        case Choice.first:
        \\            answer = 42
        \\        case Choice.second:
        \\            pass
        \\    return answer
    , "E_UNBOUND");
    // An assignment in a terminating arm does not bind the continuing path.
    try scopeReject(match_choice ++
        \\def main() -> int:
        \\    match Choice.first:
        \\        case Choice.first:
        \\            answer = 42
        \\            return answer
        \\        case Choice.second:
        \\            pass
        \\    return answer
    , "E_UNBOUND");
    // A wildcard continuation that does not assign cannot consume another
    // arm's assignment.
    try scopeReject(match_choice ++
        \\def main() -> int:
        \\    match Choice.first:
        \\        case Choice.first:
        \\            answer = 42
        \\        case _:
        \\            pass
        \\    return answer
    , "E_UNBOUND");
}

// spec-case: PY-SCOPE-3
test "match payload bindings remain scoped to their arm" {
    try scopeReject(
        \\union Box:
        \\    only: int
        \\
        \\
        \\def main() -> int:
        \\    match Box.only(42):
        \\        case Box.only(value):
        \\            pass
        \\    return value
    , "E_UNKNOWN_NAME");
}

// spec-case: PYTHON-1
test "Python declaration listings and formatting retain comment and original name positions" {
    const text = "# documentation\ndef first() -> int:\n    return 40\n\n\ndef main() -> int:\n    return first() + 2\n";
    var c = try language.Compilation.init(t.allocator, "listing.my", text);
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
    const text = "def extract(value: Result[int, int]) -> int:\n    match value:\n        case Ok(answer):\n            return answer\n        case Err(_):\n            return 0\n";
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const src = try source.Source.init(arena.allocator(), "patterns.my", text);
    var sink: diagnostic.Sink = .{ .allocator = arena.allocator() };
    const tokens = try lexer.lex(arena.allocator(), text, &sink);
    var p: parser.Parser = .{ .src = src, .arena = &arena, .tokens = tokens, .sink = &sink };
    const syntax = try p.parse();
    try t.expectEqual(@as(usize, 1), syntax.types.expressions.applications.len);
    const body = syntax.statements.items[@backingInt(syntax.functions[0].body)].data.block;
    const arms = syntax.statements.items[@backingInt(body[0])].data.match.arms;
    try t.expectEqualStrings("Ok", src.text(arms[0].name));
    try t.expectEqual(arms[0].ty.start, arms[0].ty.end);
    try t.expect(arms[1].bindings.len == 1 and arms[1].bindings[0] == null);
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
    var valid = try language.Compilation.init(t.allocator, "attrs.my",
        \\@test
        \\def checks() -> bool:
        \\    return True
        \\
        \\
        \\@allow("dead-private", reason="kept")
        \\def helper() -> int:
        \\    return 1
        \\
        \\
        \\def main() -> int:
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
        \\"""Module documentation for the program."""
        \\def area(width: int, height: int) -> int effects():
        \\    """The rectangle's area.
        \\
        \\    A # hash and a blank line stay in the literal.
        \\    """
        \\    return width * height
        \\
        \\
        \\def main() -> int effects():
        \\    return area(2, 7)
    ;
    var c = try language.Compilation.init(t.allocator, "docstrings.my", documented);
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
    const later = "def main() -> int effects():\n    value = 1\n    \"not a docstring\"\n    return value\n";
    var d = try language.Compilation.init(t.allocator, "later.my", later);
    defer d.deinit();
    try d.parse();
    try t.expect(ast.docstringOf(d.syntax.?, d.syntax.?.functions[0].name) == null);
    try t.expectEqual(@as(usize, 0), d.syntax.?.docstrings.len);
    try t.expectError(error.SourceError, d.check());
    try t.expectEqualStrings("E_EXPLICIT_DISCARD_REQUIRED", d.diagnostics.items[0].code);
}

/// Parse one `min_chars` value out of a version 2 `mylang.json` document.
fn parsedMinChars(allocator: std.mem.Allocator, text: []const u8) !?usize {
    var failure: language.lint_config.Failure = .{};
    var config = try language.lint_config.parseConfig(allocator, text, &failure);
    defer config.deinit(allocator);
    return config.min_chars;
}

// spec: DOC-2
test "undocumented-export reports missing short and name-restating docstrings" {
    const body =
        \\module main
        \\
        \\
        \\public def bare(x: int) -> int:
        \\    return x
        \\
        \\
        \\public def terse(x: int) -> int:
        \\    "short"
        \\    return x
        \\
        \\
        \\public def compute_value(x: int) -> int:
        \\    "compute value"
        \\    return x
        \\
        \\
        \\public def area(x: int) -> int:
        \\    "The rectangle's area in square units."
        \\    return x
        \\
        \\
        \\def main() -> int:
        \\    return 0
    ;
    var files: DocFiles = .{ .entries = &.{.{ .path = "main.my", .bytes = body }} };
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
    var c = try language.Compilation.init(t.allocator, "syntax.my", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.parse());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
    try t.expectEqualStrings(message, c.diagnostics.items[0].message);
    try t.expectEqualStrings(at, c.src.text(c.diagnostics.items[0].span));
}

// spec: SYNTAX-MUT-1
test "foundation syntax: a mut parameter marker sets the flag and leaves the type span" {
    var c = try language.Compilation.init(t.allocator, "mut.my",
        \\def fill(values: mut list[int], count: int) -> None:
        \\    return
    );
    defer c.deinit();
    try c.parse();
    const parameters = c.syntax.?.functions[0].signature.parameters;
    try t.expectEqual(@as(usize, 2), parameters.len);
    try t.expect(parameters[0].mut);
    try t.expectEqualStrings("list[int]", c.src.text(parameters[0].ty));
    try t.expect(!parameters[1].mut);
    try t.expectEqualStrings("int", c.src.text(parameters[1].ty));
}

// spec-case: SYNTAX-MUT-1
test "foundation syntax: mut stays an ordinary name in every position outside a marker" {
    var c = try language.Compilation.init(t.allocator, "mut.my",
        \\def tally(mut: int) -> int:
        \\    mut = mut + 1
        \\    return mut
    );
    defer c.deinit();
    try c.parse();
    const parameters = c.syntax.?.functions[0].signature.parameters;
    try t.expect(!parameters[0].mut);
    try t.expectEqualStrings("int", c.src.text(parameters[0].ty));
    var d = try language.Compilation.init(t.allocator, "mut.my", "def mut(value: int) -> int:\n    return value\n");
    defer d.deinit();
    try d.parse();
    try t.expectEqualStrings("mut", d.src.text(d.syntax.?.functions[0].name));
}

// spec-case: SYNTAX-MUT-1
test "foundation syntax: a mut call-argument marker wraps its target and leaves other arguments plain" {
    var c = try language.Compilation.init(t.allocator, "mut.my",
        \\def main() -> int:
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
test "foundation syntax: the existing ampersand argument marker keeps its plumbing" {
    var c = try language.Compilation.init(t.allocator, "mut.my",
        \\def main() -> int:
        \\    push(&values)
        \\    return 0
    );
    defer c.deinit();
    c.src.mutation_markers = true;
    try c.parse();
    const parsed_program = c.syntax.?;
    const call = parsed_program.statements.items[@backingInt(bodyOf(parsed_program)[0])].data.discard;
    const markers = parsed_program.nodes.items[@backingInt(call)].data.call.argument_markers;
    try t.expectEqual(@as(usize, 1), markers.len);
    try t.expect(markers[0]);
}

// spec-case: SYNTAX-MUT-1
test "foundation syntax: a callback type records one mut flag per parameter" {
    var c = try language.Compilation.init(t.allocator, "mut.my",
        \\def apply(cb: def(values: mut list[int], count: int) -> None) -> None:
        \\    return
    );
    defer c.deinit();
    try c.parse();
    const callbacks = c.syntax.?.types.expressions.callbacks;
    try t.expectEqual(@as(usize, 1), callbacks.len);
    try t.expectEqual(@as(usize, 2), callbacks[0].mut_parameters.len);
    try t.expect(callbacks[0].mut_parameters[0]);
    try t.expect(!callbacks[0].mut_parameters[1]);
    try t.expectEqualStrings("list[int]", c.src.text(callbacks[0].parameters[0]));
}

// spec: SYNTAX-KEYWORD-ONLY-1
test "foundation syntax: a bare star records the keyword-only boundary and frees its ordering rule" {
    var c = try language.Compilation.init(t.allocator, "keywords.my",
        \\def issue(host: int, *, code: int = 13, file: int) -> None:
        \\    return
    );
    defer c.deinit();
    try c.parse();
    const signature = c.syntax.?.functions[0].signature;
    try t.expectEqual(@as(usize, 3), signature.parameters.len);
    try t.expectEqual(@as(?usize, 1), signature.keyword_only_from);
    try t.expect(signature.parameters[1].default_value != null);
    try t.expect(signature.parameters[2].default_value == null);
    var d = try language.Compilation.init(t.allocator, "keywords.my", "def plain(a: int, b: int) -> None:\n    return\n");
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
    var c = try language.Compilation.init(t.allocator, "tuple.my",
        \\def main() -> int:
        \\    pair = (first, second)
        \\    trailing = (first, second,)
        \\    grouped = (first)
        \\    return 0
    );
    defer c.deinit();
    try c.parse();
    const parsed_program = c.syntax.?;
    const body = bodyOf(parsed_program);
    const pair = parsed_program.nodes.items[@backingInt(parsed_program.statements.items[@backingInt(body[0])].data.assignment.value)];
    try t.expect(pair.data == .tuple);
    try t.expectEqual(@as(usize, 2), pair.data.tuple.len);
    try t.expectEqualStrings("first", nodeText(parsed_program, c.src, pair.data.tuple[0]));
    try t.expectEqualStrings("second", nodeText(parsed_program, c.src, pair.data.tuple[1]));
    const trailing = parsed_program.nodes.items[@backingInt(parsed_program.statements.items[@backingInt(body[1])].data.assignment.value)];
    try t.expect(trailing.data == .tuple);
    try t.expectEqual(@as(usize, 2), trailing.data.tuple.len);
    const grouped = parsed_program.nodes.items[@backingInt(parsed_program.statements.items[@backingInt(body[2])].data.assignment.value)];
    try t.expect(grouped.data == .name);
    try t.expectEqualStrings("first", c.src.text(grouped.data.name));
}

// spec-case: SYNTAX-TUPLE-1
test "foundation syntax: return and a multi-target assignment build a tuple on both sides" {
    var c = try language.Compilation.init(t.allocator, "tuple.my",
        \\def swap(a: int, b: int) -> int:
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
    try parseFailure("def main() -> int:\n    x = (1,)\n    return 0\n", "E_SYNTAX", "a one-element tuple is not a value; write the element alone or a two-element tuple", ",");
    try parseFailure("def main() -> int:\n    pair = (1, 2)\n    x, = pair\n    return 0\n", "E_SYNTAX", "a one-element target list is not a tuple; bind the name directly", ",");
    try parseFailure("def main() -> int:\n    x, y\n    return 0\n", "E_SYNTAX", "a bare comma list is not an expression; write `x, y = value` or parenthesize it as a tuple", "x, y");
}

// spec: SYNTAX-TUPLE-2
test "foundation syntax: a tuple type records every element span in the type catalog" {
    var c = try language.Compilation.init(t.allocator, "tuple.my",
        \\def split(text: str) -> tuple[str, str]:
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
    var c = try language.Compilation.init(t.allocator, "conditional.my",
        \\def choose(x: int) -> int:
        \\    y = 42 if x > 0 else 0
        \\    z = 1 or 2 if x > 0 else 3 + 4
        \\    w = 1 if x > 0 else 2 if x < 0 else 3
        \\    return y
    );
    defer c.deinit();
    try c.parse();
    const parsed_program = c.syntax.?;
    const body = bodyOf(parsed_program);
    const y = parsed_program.nodes.items[@backingInt(parsed_program.statements.items[@backingInt(body[0])].data.assignment.value)];
    try t.expect(y.data == .conditional);
    try t.expect(parsed_program.nodes.items[@backingInt(y.data.conditional.condition)].data == .binary);
    try t.expect(parsed_program.nodes.items[@backingInt(y.data.conditional.then_value)].data == .integer);
    try t.expect(parsed_program.nodes.items[@backingInt(y.data.conditional.else_value)].data == .integer);
    const z = parsed_program.nodes.items[@backingInt(parsed_program.statements.items[@backingInt(body[1])].data.assignment.value)];
    try t.expect(z.data == .conditional);
    try t.expect(parsed_program.nodes.items[@backingInt(z.data.conditional.then_value)].data == .binary);
    try t.expect(parsed_program.nodes.items[@backingInt(z.data.conditional.else_value)].data == .binary);
    const w = parsed_program.nodes.items[@backingInt(parsed_program.statements.items[@backingInt(body[2])].data.assignment.value)];
    try t.expect(w.data == .conditional);
    try t.expect(parsed_program.nodes.items[@backingInt(w.data.conditional.else_value)].data == .conditional);
}

// spec: SYNTAX-CONDITIONAL-2
test "foundation syntax: a conditional expression parses in arguments holes lists returns and fields" {
    var c = try language.Compilation.init(t.allocator, "conditional.my",
        \\def choose(p: bool) -> int:
        \\    f(1 if p else 2, value=3 if p else 4)
        \\    items = [5 if p else 6]
        \\    label = f"{7 if p else 8}"
        \\    return 9 if p else 10
    );
    defer c.deinit();
    try c.parse();
    const parsed_program = c.syntax.?;
    const body = bodyOf(parsed_program);
    const call_node = parsed_program.nodes.items[@backingInt(parsed_program.statements.items[@backingInt(body[0])].data.discard)];
    const call = call_node.data.call;
    try t.expectEqual(@as(usize, 2), call.arguments.len);
    try t.expect(parsed_program.nodes.items[@backingInt(call.arguments[0])].data == .conditional);
    try t.expect(parsed_program.nodes.items[@backingInt(call.arguments[1])].data == .conditional);
    try t.expectEqualStrings("value", c.src.text(call.argument_names[1].?));
    const items = parsed_program.nodes.items[@backingInt(parsed_program.statements.items[@backingInt(body[1])].data.assignment.value)];
    try t.expect(items.data == .list_literal);
    try t.expect(parsed_program.nodes.items[@backingInt(items.data.list_literal[0])].data == .conditional);
    const label = parsed_program.nodes.items[@backingInt(parsed_program.statements.items[@backingInt(body[2])].data.assignment.value)];
    try t.expect(label.data == .format);
    try t.expect(parsed_program.nodes.items[@backingInt(label.data.format[0])].data == .conditional);
    const returned = parsed_program.nodes.items[@backingInt(parsed_program.statements.items[@backingInt(body[3])].data.ret)];
    try t.expect(returned.data == .conditional);
}
