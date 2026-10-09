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
test "immutable parameters support derived locals and mutable locals update across blocks" {
    const text = "func bump[T: integer](value: T) -> T:\n    const doubled = value + value\n    return doubled\n\nfunc main() -> int:\n    mut answer = 0\n    if True:\n        answer = bump(21)\n    return answer\n";
    var c = try language.Compilation.init(t.allocator, "scope.my", text);
    defer c.deinit();
    try t.expectEqual(@as(i64, 42), (try native.run(&c)).value);
    // A name assigned only on one branch is not definitely bound afterwards.
    var bad = try language.Compilation.init(t.allocator, "scope.my", "func main() -> int:\n    if True:\n        answer = 42\n    return answer\n");
    defer bad.deinit();
    try t.expectError(error.SourceError, bad.check());
    try t.expectEqualStrings("E_BINDING_SCOPE_MIGRATION", bad.diagnostics.items[0].code);
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
        \\    data.append(3)
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
        \\        case Choice.first:
        \\            const answer = 42
        \\        case Choice.second:
        \\            pass
        \\    return answer
    , "E_UNKNOWN_NAME");
    // An assignment in a terminating arm does not bind the continuing path.
    try scopeReject(match_choice ++
        \\func main() -> int:
        \\    match Choice.first:
        \\        case Choice.first:
        \\            const answer = 42
        \\            return answer
        \\        case Choice.second:
        \\            pass
        \\    return answer
    , "E_UNKNOWN_NAME");
    // A wildcard continuation that does not assign cannot consume another
    // arm's assignment.
    try scopeReject(match_choice ++
        \\func main() -> int:
        \\    match Choice.first:
        \\        case Choice.first:
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
        \\        case Box.only(value=value):
        \\            pass
        \\    return value
    , "E_UNKNOWN_NAME");
}

// spec-case: PYTHON-1
test "Python declaration listings and formatting retain comment and original name positions" {
    const text = "# documentation\nfunc first() -> int:\n    return 40\n\n\nfunc main() -> int:\n    return first() + 2\n";
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
    const text = "func extract(value: Result[int, int]) -> int:\n    match value:\n        case Ok(answer):\n            return answer\n        case Err(_):\n            return 0\n";
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const src = try source.Source.init(arena.allocator(), "patterns.my", text);
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
    for (0..count) |index| try text.writer.print("func f{d}(n: int) -> int:\n    mut xs: int[] = []\n    for k in range(n):\n        xs.append(k * {d})\n    return len(xs)\n\n\n", .{ index, index });
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
    const src = try source.Source.init(inputs.allocator(), "many.my", text);
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
    var valid = try language.Compilation.init(t.allocator, "attrs.my",
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
    const later = "func main() -> int effects():\n    mut value = 1\n    \"not a docstring\"\n    return value\n";
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
    var c = try language.Compilation.init(t.allocator, "mut.my",
        \\func tally(mut: int) -> int:
        \\    mut = mut + 1
        \\    return mut
    );
    defer c.deinit();
    try c.parse();
    const parameters = c.syntax.?.functions[0].signature.parameters;
    try t.expect(!parameters[0].mut);
    try t.expectEqualStrings("int", c.src.text(parameters[0].ty));
    var d = try language.Compilation.init(t.allocator, "mut.my", "func mut(value: int) -> int:\n    return value\n");
    defer d.deinit();
    try d.parse();
    try t.expectEqualStrings("mut", d.src.text(d.syntax.?.functions[0].name));
}

// spec-case: SYNTAX-MUT-1
test "foundation syntax: a mut call-argument marker wraps its target and leaves other arguments plain" {
    var c = try language.Compilation.init(t.allocator, "mut.my",
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
    var c = try language.Compilation.init(t.allocator, "mut.my",
        \\def main() -> int:
        \\    push(&values)
        \\    return 0
    );
    defer c.deinit();
    try t.expectError(error.SourceError, c.parse());
    const diag = c.diagnostics.items[0];
    try t.expectEqualStrings("E_REMOVED_SPELLING", diag.code);
    try t.expect(std.mem.indexOf(u8, diag.message, "write `mut value`") != null);
}

// spec-case: SYNTAX-MUT-1
test "foundation syntax: a callback type records one mut flag per parameter" {
    var c = try language.Compilation.init(t.allocator, "mut.my",
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
    var c = try language.Compilation.init(t.allocator, "keywords.my",
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
    var d = try language.Compilation.init(t.allocator, "keywords.my", "func plain(a: int, b: int) -> Unit:\n    return\n");
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
    var c = try language.Compilation.init(t.allocator, "tuple.my",
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
    try parseFailure("def main() -> int:\n    x = (1,)\n    return 0\n", "E_SYNTAX", "a one-element tuple is not a value; write the element alone or a two-element tuple", ",");
    try parseFailure("def main() -> int:\n    pair = (1, 2)\n    x, = pair\n    return 0\n", "E_SYNTAX", "a one-element target list is not a tuple; bind the name directly", ",");
    try parseFailure("def main() -> int:\n    x, y\n    return 0\n", "E_SYNTAX", "a bare comma list is not an expression; write `x, y = value` or parenthesize it as a tuple", "x, y");
}

// spec: SYNTAX-TUPLE-2
test "foundation syntax: a tuple type records every element span in the type catalog" {
    var c = try language.Compilation.init(t.allocator, "tuple.my",
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
    var c = try language.Compilation.init(t.allocator, "conditional.my",
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
    var c = try language.Compilation.init(t.allocator, "conditional.my",
        \\func choose(p: bool) -> int:
        \\    f(if (p) then (1) else (2), value=if (p) then (3) else (4))
        \\    mut items = [if (p) then (5) else (6)]
        \\    mut label = f"{if (p) then (7) else (8)}"
        \\    return if (p) then (9) else (10)
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
    var c = try language.Compilation.init(t.allocator, "redesign.my", text);
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
        \\        case Choice.number(value=number):
        \\            yield number
        \\        case _:
        \\            yield 0
        \\    return answer
    ;
    var c = try language.Compilation.init(t.allocator, "redesign_match.my", text);
    defer c.deinit();
    try c.parse();
    try assertExpressionPattern(&c);
}

// spec-case: PYTHON-1
test "redesign parser rejects nested propagation with statement boundary guidance" {
    var c = try language.Compilation.init(t.allocator, "redesign_try.my", "func main() -> int:\n    const value = consume(try compute())\n    return value\n");
    defer c.deinit();
    try t.expectError(error.SourceError, c.parse());
    try t.expectEqualStrings("E_TRY_POSITION", c.diagnostics.items[0].code);
}

// spec-case: PYTHON-1
test "redesign parser preserves nested variant payload pattern tree" {
    const text = "func choose(value: Outcome) -> int:\n    match value:\n        case Err(Error.bad(message=text)):\n            return 1\n        case Ok(number):\n            return number\n";
    var c = try language.Compilation.init(t.allocator, "nested_pattern.my", text);
    defer c.deinit();
    try c.parse();
    try assertNestedPattern(&c);
}

// spec-case: PYTHON-1
test "redesign parser diagnoses duplicate mutation modifiers" {
    var c = try language.Compilation.init(t.allocator, "duplicate_mut.my", "func helper(mut value: mut int):\n    pass\n");
    defer c.deinit();
    try t.expectError(error.SourceError, c.parse());
    try t.expectEqualStrings("E_PARAMETER_MODIFIER", c.diagnostics.items[0].code);
}

// spec-case: PYTHON-1
test "redesign parser requires names on labelled callable parameters" {
    var c = try language.Compilation.init(t.allocator, "named_callback.my", "type Handler = func(named int) -> Unit\nfunc main():\n    pass\n");
    defer c.deinit();
    try t.expectError(error.SourceError, c.parse());
    try t.expectEqualStrings("E_PARAMETER_NAME", c.diagnostics.items[0].code);
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
    var compilation = try language.Compilation.init(t.allocator, "generic-types.my",
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
    var compilation = try language.Compilation.init(t.allocator, "tuple-bindings.my",
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
    var compilation = try language.Compilation.init(t.allocator, "condition.my",
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
    var compilation = try language.Compilation.init(t.allocator, "typed-range.my", input);
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
