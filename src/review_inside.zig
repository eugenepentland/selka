//! The code a change edits, read inside its functions: every function whose text is added,
//! removed or edited, its code lines and decision points before and after, its edit
//! (bounded), and the three heuristic "possible patching" signals of plan section 3.4.
//!
//! A file that parses is read from its syntax tree: decision points, branch conditions,
//! branch and loop bodies and parameters. A file that does not parse falls back to a text
//! scan for function boundaries and a token count for decision points, and yields no signals.
//! Pure over the sides' source files: nothing is read, written or run here.
const std = @import("std");
const product = @import("product.zig");
const ast = @import("ast.zig");
const diagnostic = @import("diagnostic.zig");
const generated_marker = @import("generated_marker.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const review_side = @import("review_side.zig");
const review_tests = @import("review_tests.zig");
const source = @import("source.zig");

/// Allocation is the only failure: every function, signal and diff is built in memory.
pub const Error = std.mem.Allocator.Error;

/// Most diff lines one function shows, its `… N more lines` marker included.
const max_function_diff = 80;
/// Most diff lines a whole review shows, every marker included.
const max_review_diff = 600;
/// Fewest code lines a branch or loop body needs, its header included, to be a copy candidate.
const min_block_lines = 4;
/// Similarity, in percent, at which a new block counts as a copy of another.
const min_similarity_percent = 80;

/// How a function differs between the two sides.
pub const State = enum { added, changed, removed };

/// The kind of a possible-patching signal.
pub const Kind = enum {
    special_case,
    copy,
    flag,

    /// The spelling the reader and the JSON use: `special-case`, `copy` or `flag`.
    pub fn label(self: Kind) []const u8 {
        return switch (self) {
            .special_case => "special-case",
            .copy => "copy",
            .flag => "flag",
        };
    }
};

/// One possible-patching signal of a function: its kind and the sentence that names it.
pub const Signal = struct { kind: Kind, text: []const u8 };

/// A count before and after the change.
pub const Pair = struct { before: usize = 0, after: usize = 0 };

/// The file and 1-based line where a function's declaration starts.
pub const Location = struct { file: []const u8, line: usize };

/// The measures of a function before and after the change: code lines and decision points.
pub const Measure = struct { lines: Pair = .{}, decision_points: Pair = .{} };

/// One function the change adds, removes or edits. `name` is `module::name`, and `diff` is
/// empty unless the function changed, or when the review has no diff budget left.
pub const Function = struct {
    name: []const u8,
    public: bool,
    state: State,
    location: Location,
    measure: Measure,
    signals: []const Signal,
    diff: []const []const u8,
};

/// A source file as the parser left it: its source, its syntax program, its trimmed lines and
/// the masked text of each line (empty when the line holds no token).
const Parsed = struct {
    src: source.Source,
    program: ast.Program,
    lines: []const []const u8,
    masked: []const []const u8,
};

/// The syntax of one function: the parsed file it is in and its declaration.
const Tree = struct { parsed: *const Parsed, function: ast.Function };

/// One function as one side reads it: its qualified name, visibility, file, first line index,
/// its lines from the declaration to the end of its body, its text and its tree when the file parsed.
const Decl = struct {
    qualified: []const u8,
    public: bool,
    file: []const u8,
    first: usize,
    lines: []const []const u8,
    text: []const u8,
    tree: ?Tree,
};

/// A function's record, and the lines its diff compares, before the review's budget is applied.
const Pending = struct {
    function: Function,
    before: []const []const u8 = &.{},
    after: []const []const u8 = &.{},
};

/// A literal that one subject is compared with, and the subject's source text.
const Comparison = struct { subject: []const u8, literal: []const u8 };

/// A branch or loop body of at least `min_block_lines` code lines: its header and last line
/// (0-based), its masked code lines, and whether any of its lines is absent from the base.
const Block = struct { header: usize, last: usize, masked: []const []const u8, fresh: bool };

/// The literals a changed function newly compares one subject with, in first-seen order.
const Group = struct { subject: []const u8, literals: std.ArrayList([]const u8) = .empty };

/// A function header line: its name and whether it is public.
const Header = struct { name: []const u8, public: bool };

/// Compare the functions of the two sides' source files: each function that is added, removed
/// or whose text differs, with its measures, its edit and its signals, sorted by name. Files whose
/// bytes are the same on both sides are not read. Allocations belong to `a`.
pub fn compare(a: std.mem.Allocator, base: []const review_side.File, head: []const review_side.File) Error![]const Function {
    const before = try declarations(a, base, head);
    const after = try declarations(a, head, base);
    var known: std.StringHashMapUnmanaged(usize) = .empty;
    for (before, 0..) |decl, index| try known.put(a, decl.qualified, index);
    const seen = try a.alloc(bool, before.len);
    @memset(seen, false);
    var pending: std.ArrayList(Pending) = .empty;
    for (after) |decl| {
        const index = known.get(decl.qualified) orelse {
            try pending.append(a, try record(a, .added, null, decl));
            continue;
        };
        seen[index] = true;
        if (sameLines(before[index].lines, decl.lines)) continue;
        try pending.append(a, try record(a, .changed, before[index], decl));
    }
    for (before, seen) |decl, found| {
        if (!found) try pending.append(a, try record(a, .removed, decl, null));
    }
    std.mem.sort(Pending, pending.items, {}, pendingLess);
    return budgeted(a, pending.items);
}

/// Whether `path` names a test module, a file whose name ends in `_test.selka`.
pub fn isTestFile(path: []const u8) bool {
    return product.isTestSource(path);
}

/// Every function of the non-generated `.selka` files of `files` whose bytes differ from the
/// same path in `others`, in path order.
fn declarations(a: std.mem.Allocator, files: []const review_side.File, others: []const review_side.File) Error![]const Decl {
    var out: std.ArrayList(Decl) = .empty;
    for (files) |file| {
        if (!product.isSource(file.path) or generated_marker.isGenerated(file.bytes)) continue;
        if (sameFile(others, file)) continue;
        try fileDecls(a, file, &out);
    }
    return out.items;
}

/// Whether `files` holds a file with the same path and bytes as `file`.
fn sameFile(files: []const review_side.File, file: review_side.File) bool {
    for (files) |other| {
        if (std.mem.eql(u8, other.path, file.path) and std.mem.eql(u8, other.bytes, file.bytes)) return true;
    }
    return false;
}

/// Append the functions of one file. A file that parses yields its declarations with their
/// syntax; a file that does not parse yields the functions a text scan finds, without syntax.
/// Module constants are left out: the syntax tree holds them as functions, but they are not `func`s.
fn fileDecls(a: std.mem.Allocator, file: review_side.File, out: *std.ArrayList(Decl)) Error!void {
    const src = try source.Source.init(a, file.path, file.bytes);
    const lines = try trimmedLines(a, file.bytes);
    const module = try review_tests.moduleOf(a, file.path);
    if (try parseFile(a, src, lines)) |parsed| {
        for (parsed.program.functions) |function| {
            const name = src.text(function.name);
            if (function.policy.constant or isTestName(name)) continue;
            if (ast.hasAttribute(parsed.program, function.name, .@"test")) continue;
            const body = statementOf(&parsed.program, function.body);
            if (body.span.end == 0) continue;
            const first = lineOf(src, function.name.start);
            const last = lineOf(src, body.span.end - 1);
            if (last < first) continue;
            try out.append(a, .{
                .qualified = try qualify(a, module, name),
                .public = ast.isPublicDeclaration(parsed.program, function.name),
                .file = file.path,
                .first = first,
                .lines = lines[first .. last + 1],
                .text = file.bytes[src.line_starts[first]..lineEnd(src, last)],
                .tree = .{ .parsed = parsed, .function = function },
            });
        }
        return;
    }
    try scanDecls(a, file, src, lines, module, out);
}

/// Append the functions a text scan finds in an unparsed file: a column-zero `func` or
/// `public func` line, and the indented lines below it. Test functions are skipped.
fn scanDecls(a: std.mem.Allocator, file: review_side.File, src: source.Source, lines: []const []const u8, module: []const u8, out: *std.ArrayList(Decl)) Error!void {
    var index: usize = 0;
    while (index < lines.len) {
        const header = scanHeader(lines[index]) orelse {
            index += 1;
            continue;
        };
        var end = index + 1;
        while (end < lines.len and (blank(lines[end]) or indented(lines[end]))) end += 1;
        while (end > index + 1 and blank(lines[end - 1])) end -= 1;
        if (!isTestName(header.name)) try out.append(a, .{
            .qualified = try qualify(a, module, header.name),
            .public = header.public,
            .file = file.path,
            .first = index,
            .lines = lines[index..end],
            .text = file.bytes[src.line_starts[index]..lineEnd(src, end - 1)],
            .tree = null,
        });
        index = end;
    }
}

/// The name and visibility of a column-zero `func` or `public func` header line, or null.
fn scanHeader(line: []const u8) ?Header {
    var rest = line;
    const public = std.mem.startsWith(u8, rest, "public ");
    if (public) rest = rest["public ".len..];
    if (!std.mem.startsWith(u8, rest, "func ")) return null;
    rest = rest["func ".len..];
    var end: usize = 0;
    while (end < rest.len and (std.ascii.isAlphanumeric(rest[end]) or rest[end] == '_')) end += 1;
    if (end == 0) return null;
    return .{ .name = rest[0..end], .public = public };
}

/// Parse one file with the compiler's lexer and parser. Null when the file does not parse
/// cleanly: any error in the sink, or a failure of the lexer or parser.
fn parseFile(a: std.mem.Allocator, src: source.Source, lines: []const []const u8) Error!?*Parsed {
    var sink: diagnostic.Sink = .{ .allocator = a };
    const program = syntaxOf(a, src, &sink) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    for (sink.items.items) |finding| {
        if (finding.severity == .err) return null;
    }
    const parsed = try a.create(Parsed);
    parsed.* = .{ .src = src, .program = program, .lines = lines, .masked = try maskedLines(a, src) };
    return parsed;
}

/// Lex and parse one module, as the release loader does for each of its files.
fn syntaxOf(a: std.mem.Allocator, src: source.Source, sink: *diagnostic.Sink) diagnostic.Error!ast.Program {
    const tokens = try lexer.lex(a, src.bytes, sink);
    var parse: parser.Parser = .{ .src = src, .storage = a, .tokens = tokens, .sink = sink };
    return parse.parseModule();
}

/// The masked text of each line of a file: each identifier is `N`, each literal `L`, an `elif`
/// reads as `if`, and every other token keeps its tag. The tokens of one line are joined by spaces.
fn maskedLines(a: std.mem.Allocator, src: source.Source) Error![]const []const u8 {
    var sink: diagnostic.Sink = .{ .allocator = a };
    const tokens: []const lexer.Token = lexer.lexRange(a, src.bytes, .{ .start = 0, .end = src.bytes.len }, &sink) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => &.{},
    };
    const buffers = try a.alloc(std.ArrayList(u8), src.line_starts.len);
    for (buffers) |*buffer| buffer.* = .empty;
    for (tokens) |token| {
        if (token.tag == .eof) continue;
        const buffer = &buffers[lineOf(src, token.span.start)];
        if (buffer.items.len != 0) try buffer.append(a, ' ');
        try buffer.appendSlice(a, maskedWord(token.tag));
    }
    const out = try a.alloc([]const u8, buffers.len);
    for (buffers, out) |buffer, *line| line.* = buffer.items;
    return out;
}

/// The masked spelling of one token: `N` for an identifier, `L` for a literal, `kw_if` for
/// `elif`, and the tag name for anything else.
fn maskedWord(tag: lexer.Tag) []const u8 {
    return switch (tag) {
        .ident => "N",
        .integer, .bytes, .format => "L",
        .kw_elif => "kw_if",
        else => @tagName(tag),
    };
}

/// The lines of a text with their trailing spaces, tabs and carriage returns removed.
fn trimmedLines(a: std.mem.Allocator, bytes: []const u8) Error![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var split = std.mem.splitScalar(u8, bytes, '\n');
    while (split.next()) |raw| try out.append(a, std.mem.trimEnd(u8, raw, " \t\r"));
    return out.items;
}

/// The 0-based line that holds byte `offset`.
fn lineOf(src: source.Source, offset: usize) usize {
    const starts = src.line_starts;
    var low: usize = 0;
    var high: usize = starts.len;
    while (high - low > 1) {
        const middle = low + (high - low) / 2;
        if (starts[middle] <= offset) low = middle else high = middle;
    }
    return low;
}

/// The byte offset just past line `line`, its newline included.
fn lineEnd(src: source.Source, line: usize) usize {
    return if (line + 1 < src.line_starts.len) src.line_starts[line + 1] else src.bytes.len;
}

/// The statement with this id in a program.
fn statementOf(program: *const ast.Program, id: ast.StatementId) ast.Statement {
    return program.statements.items[@backingInt(id)];
}

/// The expression with this id in a program.
fn nodeOf(program: *const ast.Program, id: ast.NodeId) ast.Node {
    return program.nodes.items[@backingInt(id)];
}

/// The statements of a body: the body first, then every statement nested inside it.
fn bodyStatements(a: std.mem.Allocator, program: *const ast.Program, body: ast.StatementId) Error![]const ast.StatementId {
    var work: std.ArrayList(ast.StatementId) = .empty;
    try work.append(a, body);
    var index: usize = 0;
    while (index < work.items.len) : (index += 1) {
        try ast.appendNested(a, &work, statementOf(program, work.items[index]));
    }
    return work.items;
}

/// The decision points of a function: its branches (`if` and `elif`), loops, `for` loops, match
/// arms and `and`/`or` operators. A function that parsed is counted on its syntax tree; one that
/// did not is counted on its tokens.
fn decisionPoints(a: std.mem.Allocator, decl: Decl) Error!usize {
    if (decl.tree) |tree| return syntaxDecisions(a, tree);
    return tokenDecisions(a, decl.text);
}

/// The decision points of a parsed function, counted on its statements and on the logical
/// operators whose span starts inside the function.
fn syntaxDecisions(a: std.mem.Allocator, tree: Tree) Error!usize {
    const program = &tree.parsed.program;
    var count: usize = 0;
    for (try bodyStatements(a, program, tree.function.body)) |id| {
        switch (statementOf(program, id).data) {
            .branch, .loop, .for_each, .for_range => count += 1,
            .match => |match| count += match.arms.len,
            else => {},
        }
    }
    const start = tree.function.name.start;
    const end = statementOf(program, tree.function.body).span.end;
    for (program.nodes.items) |node| {
        if (node.span.start < start or node.span.start >= end) continue;
        switch (node.data) {
            .binary => |binary| {
                if (binary.op == .logical_and or binary.op == .logical_or) count += 1;
            },
            else => {},
        }
    }
    return count;
}

/// The decision points of a function that did not parse, counted on its lexer tokens. Text
/// that does not lex counts as none.
fn tokenDecisions(a: std.mem.Allocator, text: []const u8) Error!usize {
    var sink: diagnostic.Sink = .{ .allocator = a };
    const tokens = lexer.lexRange(a, text, .{ .start = 0, .end = text.len }, &sink) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return 0,
    };
    var count: usize = 0;
    for (tokens) |token| {
        switch (token.tag) {
            .kw_if, .kw_elif, .kw_while, .kw_for, .kw_case, .and_and, .or_or => count += 1,
            else => {},
        }
    }
    return count;
}

/// The code lines of a function: its lines that are neither blank nor a `#` comment.
fn codeLines(lines: []const []const u8) usize {
    var count: usize = 0;
    for (lines) |line| {
        const text = std.mem.trim(u8, line, " \t\r");
        if (text.len != 0 and text[0] != '#') count += 1;
    }
    return count;
}

/// Compare two line lists exactly.
fn sameLines(before: []const []const u8, after: []const []const u8) bool {
    if (before.len != after.len) return false;
    for (before, after) |left, right| {
        if (!std.mem.eql(u8, left, right)) return false;
    }
    return true;
}

/// The record of one function: its state, its measures, its signals, and the lines its diff compares.
fn record(a: std.mem.Allocator, state: State, base: ?Decl, head: ?Decl) Error!Pending {
    const decl = head orelse base.?;
    var measure: Measure = .{};
    var signals: []const Signal = &.{};
    var before: []const []const u8 = &.{};
    var after: []const []const u8 = &.{};
    if (base) |old| {
        before = old.lines;
        measure.lines.before = codeLines(old.lines);
        measure.decision_points.before = try decisionPoints(a, old);
    }
    if (head) |new| {
        after = new.lines;
        measure.lines.after = codeLines(new.lines);
        measure.decision_points.after = try decisionPoints(a, new);
    }
    if (base) |old| {
        if (head) |new| signals = try signalsOf(a, old, new);
    }
    return .{
        .function = .{
            .name = decl.qualified,
            .public = decl.public,
            .state = state,
            .location = .{ .file = decl.file, .line = decl.first + 1 },
            .measure = measure,
            .signals = signals,
            .diff = &.{},
        },
        .before = before,
        .after = after,
    };
}

/// The functions in order, each with its diff: a changed function shows its line diff, bounded
/// by the most lines one function shows and by what the review has left of `max_review_diff`.
fn budgeted(a: std.mem.Allocator, pending: []const Pending) Error![]const Function {
    const out = try a.alloc(Function, pending.len);
    var remaining: usize = max_review_diff;
    for (pending, out) |item, *function| {
        function.* = item.function;
        if (item.function.state == .changed) {
            function.diff = try boundedDiff(a, try review_tests.fullDiff(a, item.before, item.after), remaining);
            remaining -= function.diff.len;
        }
    }
    return out;
}

/// The first lines of a diff, at most `budget` and `max_function_diff` in all. A diff that is
/// cut ends with `… N more lines`, which counts as one of the lines. With no budget left the
/// diff is empty.
fn boundedDiff(a: std.mem.Allocator, lines: []const []const u8, budget: usize) Error![]const []const u8 {
    const limit = @min(max_function_diff, budget);
    if (lines.len <= limit) return lines;
    if (limit == 0) return &.{};
    const kept = limit - 1;
    const out = try a.alloc([]const u8, limit);
    @memcpy(out[0..kept], lines[0..kept]);
    out[kept] = try std.fmt.allocPrint(a, "… {d} more lines", .{lines.len - kept});
    return out;
}

/// The possible-patching signals of a changed function: special cases, copied blocks and flags.
fn signalsOf(a: std.mem.Allocator, before: Decl, after: Decl) Error![]const Signal {
    const old = before.tree orelse return &.{};
    const new = after.tree orelse return &.{};
    var out: std.ArrayList(Signal) = .empty;
    try specialCases(a, old, new, &out);
    try copies(a, before.lines, new, &out);
    try flags(a, old, new, &out);
    return out.items;
}

/// The special-case signals: one per subject that the function newly compares with two or more
/// literals, naming them in the order they first appear.
fn specialCases(a: std.mem.Allocator, old: Tree, new: Tree, out: *std.ArrayList(Signal)) Error!void {
    var known: std.StringHashMapUnmanaged(void) = .empty;
    for (try comparisonsOf(a, old)) |comparison| try known.put(a, try pairKey(a, comparison), {});
    var groups: std.ArrayList(Group) = .empty;
    for (try comparisonsOf(a, new)) |comparison| {
        if (known.contains(try pairKey(a, comparison))) continue;
        const group = try groupFor(a, &groups, comparison.subject);
        if (!containsText(group.literals.items, comparison.literal)) try group.literals.append(a, comparison.literal);
    }
    for (groups.items) |group| {
        if (group.literals.items.len < 2) continue;
        try out.append(a, .{ .kind = .special_case, .text = try specialCaseText(a, group.subject, group.literals.items) });
    }
}

/// The group of one subject, appended to `groups` when it is new.
fn groupFor(a: std.mem.Allocator, groups: *std.ArrayList(Group), subject: []const u8) Error!*Group {
    for (groups.items) |*group| {
        if (std.mem.eql(u8, group.subject, subject)) return group;
    }
    try groups.append(a, .{ .subject = subject });
    return &groups.items[groups.items.len - 1];
}

/// The sentence of a special case: `adds branches that compare `SUBJECT` against `"A"`, `"B"``.
fn specialCaseText(a: std.mem.Allocator, subject: []const u8, literals: []const []const u8) Error![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    try text.print(a, "adds branches that compare `{s}` against ", .{subject});
    for (literals, 0..) |literal, index| {
        if (index != 0) try text.appendSlice(a, ", ");
        try text.print(a, "`{s}`", .{literal});
    }
    return text.items;
}

/// The key that names one subject and literal pair in a set.
fn pairKey(a: std.mem.Allocator, comparison: Comparison) Error![]const u8 {
    return std.fmt.allocPrint(a, "{s}\x00{s}", .{ comparison.subject, comparison.literal });
}

/// Every comparison of a parsed function's `if`, `elif` and `while` conditions.
fn comparisonsOf(a: std.mem.Allocator, tree: Tree) Error![]const Comparison {
    const program = &tree.parsed.program;
    var out: std.ArrayList(Comparison) = .empty;
    for (try bodyStatements(a, program, tree.function.body)) |id| {
        const condition: ?ast.NodeId = switch (statementOf(program, id).data) {
            .branch => |branch| branch.condition,
            .loop => |loop| loop.condition,
            else => null,
        };
        if (condition) |node| try comparisons(a, tree.parsed, node, &out);
    }
    return out.items;
}

/// The subject-literal comparisons of one condition: `==` and `!=` with a literal on one side,
/// `startswith` with a literal first argument, and the `starts_with` function of `strings` or
/// `bytes` with a literal second argument. `and`, `or` and `not` are followed.
fn comparisons(a: std.mem.Allocator, parsed: *const Parsed, id: ast.NodeId, out: *std.ArrayList(Comparison)) Error!void {
    const node = nodeOf(&parsed.program, id);
    switch (node.data) {
        .binary => |binary| switch (binary.op) {
            .logical_and, .logical_or => {
                try comparisons(a, parsed, binary.left, out);
                try comparisons(a, parsed, binary.right, out);
            },
            .eq, .ne => try comparisonOf(a, parsed, binary.left, binary.right, out),
            else => {},
        },
        .unary => |unary| {
            if (unary.op == .not) try comparisons(a, parsed, unary.operand, out);
        },
        .method_call => |call| {
            if (call.arguments.len != 0 and std.mem.eql(u8, parsed.src.text(call.name), "startswith")) {
                try appendComparison(a, parsed, call.base, call.arguments[0], out);
            }
        },
        .call => |call| {
            if (call.arguments.len == 2 and isStartsWith(parsed, call.owner, call.name)) {
                try appendComparison(a, parsed, call.arguments[0], call.arguments[1], out);
            }
        },
        else => {},
    }
}

/// Whether a call names the library's prefix test, `strings.starts_with` or `bytes.starts_with`.
/// The parser keeps the qualifier as the call's owner, or as the start of its name when the file
/// imports the module, so both spellings are read.
fn isStartsWith(parsed: *const Parsed, owner: ?source.Span, name: source.Span) bool {
    const text = parsed.src.text(name);
    const dot = std.mem.lastIndexOfScalar(u8, text, '.');
    const member = if (dot) |at| text[at + 1 ..] else text;
    const module = if (owner) |span| parsed.src.text(span) else if (dot) |at| text[0..at] else "";
    if (!std.mem.eql(u8, member, "starts_with")) return false;
    return std.mem.eql(u8, module, "strings") or std.mem.eql(u8, module, "bytes");
}

/// A comparison of two operands, when exactly one of them is a literal.
fn comparisonOf(a: std.mem.Allocator, parsed: *const Parsed, left: ast.NodeId, right: ast.NodeId, out: *std.ArrayList(Comparison)) Error!void {
    const left_literal = isLiteral(nodeOf(&parsed.program, left));
    const right_literal = isLiteral(nodeOf(&parsed.program, right));
    if (left_literal and !right_literal) {
        try appendComparison(a, parsed, right, left, out);
    } else if (right_literal and !left_literal) {
        try appendComparison(a, parsed, left, right, out);
    }
}

/// Record one comparison of `subject` with `literal`, when `literal` is a literal.
fn appendComparison(a: std.mem.Allocator, parsed: *const Parsed, subject: ast.NodeId, literal: ast.NodeId, out: *std.ArrayList(Comparison)) Error!void {
    const literal_node = nodeOf(&parsed.program, literal);
    if (!isLiteral(literal_node)) return;
    try out.append(a, .{
        .subject = parsed.src.text(nodeOf(&parsed.program, subject).span),
        .literal = parsed.src.text(literal_node.span),
    });
}

/// Whether an expression is a string, byte or integer literal.
fn isLiteral(node: ast.Node) bool {
    return switch (node.data) {
        .text, .bytes, .integer => true,
        else => false,
    };
}

/// The copy signals: each new block of at least `min_block_lines` code lines that is at least
/// `min_similarity_percent` alike to another block that does not overlap it.
fn copies(a: std.mem.Allocator, base_lines: []const []const u8, tree: Tree, out: *std.ArrayList(Signal)) Error!void {
    var known: std.StringHashMapUnmanaged(void) = .empty;
    for (base_lines) |line| try known.put(a, std.mem.trim(u8, line, " \t"), {});
    var blocks: std.ArrayList(Block) = .empty;
    for (try bodyStatements(a, &tree.parsed.program, tree.function.body)) |id| {
        const program = &tree.parsed.program;
        switch (statementOf(program, id).data) {
            .branch => |branch| {
                try blockAt(a, tree.parsed, branch.then_body, &known, &blocks);
                if (branch.else_body) |other| {
                    if (std.meta.activeTag(statementOf(program, other).data) != .branch) try blockAt(a, tree.parsed, other, &known, &blocks);
                }
            },
            .loop => |loop| try blockAt(a, tree.parsed, loop.body, &known, &blocks),
            .for_each => |each| try blockAt(a, tree.parsed, each.body, &known, &blocks),
            .for_range => |range| try blockAt(a, tree.parsed, range.body, &known, &blocks),
            .match => |match| {
                for (match.arms) |arm| try blockAt(a, tree.parsed, arm.body, &known, &blocks);
            },
            else => {},
        }
    }
    std.mem.sort(Block, blocks.items, {}, blockLess);
    var reported: std.AutoHashMapUnmanaged(usize, void) = .empty;
    for (blocks.items, 0..) |first, index| {
        for (blocks.items[index + 1 ..]) |second| try copyPair(a, first, second, &reported, out);
    }
}

/// Append the block of body `id` when it has enough code lines. Its header is the line its
/// body opens on, its masked lines are those of its code lines, and it is fresh when a line of
/// it is not in the base function.
fn blockAt(a: std.mem.Allocator, parsed: *const Parsed, id: ast.StatementId, known: *const std.StringHashMapUnmanaged(void), out: *std.ArrayList(Block)) Error!void {
    const span = statementOf(&parsed.program, id).span;
    if (span.end == 0) return;
    const header = lineOf(parsed.src, span.start);
    const last = lineOf(parsed.src, span.end - 1);
    if (last < header) return;
    var masked: std.ArrayList([]const u8) = .empty;
    var fresh = false;
    for (parsed.lines[header .. last + 1], parsed.masked[header .. last + 1]) |line, code| {
        const text = std.mem.trim(u8, line, " \t");
        if (text.len == 0) continue;
        if (!known.contains(text)) fresh = true;
        if (code.len != 0) try masked.append(a, code);
    }
    if (masked.items.len < min_block_lines) return;
    try out.append(a, .{ .header = header, .last = last, .masked = masked.items, .fresh = fresh });
}

/// Append a copy signal for a pair of blocks, when they do not overlap, at least one is fresh,
/// and they are similar. The fresh block is the copy: of two fresh blocks, the later one. Each
/// copy is reported once, against the first block it repeats.
fn copyPair(a: std.mem.Allocator, first: Block, second: Block, reported: *std.AutoHashMapUnmanaged(usize, void), out: *std.ArrayList(Signal)) Error!void {
    if (overlaps(first, second)) return;
    if (!first.fresh and !second.fresh) return;
    if (!(try similar(a, first.masked, second.masked))) return;
    const copy = if (second.fresh) second else first;
    const original = if (second.fresh) first else second;
    if ((try reported.getOrPut(a, copy.header)).found_existing) return;
    try out.append(a, .{
        .kind = .copy,
        .text = try std.fmt.allocPrint(a, "the new block at line {d} repeats the block at line {d} with only names or literals changed", .{ copy.header + 1, original.header + 1 }),
    });
}

/// Whether two blocks share a line.
fn overlaps(left: Block, right: Block) bool {
    return !(left.last < right.header or right.last < left.header);
}

/// Whether two blocks' masked lines are at least `min_similarity_percent` alike: twice the
/// length of their longest common subsequence over the sum of their lengths.
pub fn similar(a: std.mem.Allocator, left: []const []const u8, right: []const []const u8) Error!bool {
    if (left.len == 0 or right.len == 0) return false;
    const shared = try lcsLength(a, left, right);
    return 2 * shared * 100 >= min_similarity_percent * (left.len + right.len);
}

/// The length of the longest common subsequence of two line lists, kept in one row of counts.
fn lcsLength(a: std.mem.Allocator, left: []const []const u8, right: []const []const u8) Error!usize {
    const row = try a.alloc(usize, right.len + 1);
    defer a.free(row);
    @memset(row, 0);
    for (left) |line| {
        var diagonal: usize = 0;
        for (right, 1..) |other, column| {
            const above = row[column];
            row[column] = if (std.mem.eql(u8, line, other)) diagonal + 1 else @max(row[column], row[column - 1]);
            diagonal = above;
        }
    }
    return row[right.len];
}

/// The flag signals: a parameter of type `bool` that the function does not have in the base,
/// and that one of its `if` or `elif` conditions names.
fn flags(a: std.mem.Allocator, old: Tree, new: Tree, out: *std.ArrayList(Signal)) Error!void {
    for (new.function.signature.parameters) |parameter| {
        const name = new.parsed.src.text(parameter.name);
        const kind = new.parsed.src.text(parameter.ty);
        if (!std.mem.eql(u8, kind, "bool") or declares(old, name, kind)) continue;
        if (!(try branchesOn(a, new, name))) continue;
        try out.append(a, .{ .kind = .flag, .text = try std.fmt.allocPrint(a, "takes a new bool parameter `{s}` and branches on it", .{name}) });
    }
}

/// Whether a function declares a parameter with this name and type spelling.
fn declares(tree: Tree, name: []const u8, kind: []const u8) bool {
    for (tree.function.signature.parameters) |parameter| {
        if (std.mem.eql(u8, tree.parsed.src.text(parameter.name), name) and std.mem.eql(u8, tree.parsed.src.text(parameter.ty), kind)) return true;
    }
    return false;
}

/// Whether one of a function's `if` or `elif` conditions names `name`.
fn branchesOn(a: std.mem.Allocator, tree: Tree, name: []const u8) Error!bool {
    const program = &tree.parsed.program;
    for (try bodyStatements(a, program, tree.function.body)) |id| {
        switch (statementOf(program, id).data) {
            .branch => |branch| {
                if (mentions(tree.parsed, branch.condition, name)) return true;
            },
            else => {},
        }
    }
    return false;
}

/// Whether an expression names `name` on its own, through `not`, `and`, `or` and comparisons.
fn mentions(parsed: *const Parsed, id: ast.NodeId, name: []const u8) bool {
    const node = nodeOf(&parsed.program, id);
    return switch (node.data) {
        .name => |span| std.mem.eql(u8, parsed.src.text(span), name),
        .binary => |binary| mentions(parsed, binary.left, name) or mentions(parsed, binary.right, name),
        .unary => |unary| mentions(parsed, unary.operand, name),
        else => false,
    };
}

/// Whether a text list holds `text`.
fn containsText(list: []const []const u8, text: []const u8) bool {
    for (list) |item| {
        if (std.mem.eql(u8, item, text)) return true;
    }
    return false;
}

/// The `module::name` of a function.
fn qualify(a: std.mem.Allocator, module: []const u8, name: []const u8) Error![]const u8 {
    return std.fmt.allocPrint(a, "{s}::{s}", .{ module, name });
}

/// Whether a function name is a test: `test_` followed by anything.
fn isTestName(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "test_");
}

/// Whether a line is blank.
fn blank(line: []const u8) bool {
    return std.mem.trim(u8, line, " \t\r").len == 0;
}

/// Whether a line starts with a space or a tab.
fn indented(line: []const u8) bool {
    return line.len != 0 and (line[0] == ' ' or line[0] == '\t');
}

/// Order pending records by qualified name.
fn pendingLess(_: void, left: Pending, right: Pending) bool {
    return std.mem.lessThan(u8, left.function.name, right.function.name);
}

/// Order blocks by the line they open on.
fn blockLess(_: void, left: Block, right: Block) bool {
    return left.header < right.header;
}

/// A parsed module of `text` for the tests, with no lines of its own.
fn parsedForTest(a: std.mem.Allocator, text: []const u8) !*const Parsed {
    const src = try source.Source.init(a, "cli.selka", text);
    return (try parseFile(a, src, &.{})) orelse error.SourceError;
}

/// The first function of a parsed test module, as a tree.
fn firstTree(parsed: *const Parsed) Tree {
    return .{ .parsed = parsed, .function = parsed.program.functions[0] };
}

/// `count` lines of the form `+line N`, for the diff budget tests.
fn numberedLines(a: std.mem.Allocator, count: usize) ![]const []const u8 {
    const lines = try a.alloc([]const u8, count);
    for (lines, 0..) |*line, index| line.* = try std.fmt.allocPrint(a, "+line {d}", .{index});
    return lines;
}

test "review inside masks names and literals and keeps keywords and operators" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try source.Source.init(a, "cli.selka", "if args[index] == \"--port\":\nelif count >= 10:\n    return 1\n");
    const masked = try maskedLines(a, src);
    try std.testing.expectEqualStrings("kw_if N lbracket N rbracket eq_eq L colon", masked[0]);
    try std.testing.expectEqualStrings("kw_if N ge L colon", masked[1]);
    try std.testing.expectEqualStrings("kw_return L", masked[2]);
}

test "review inside treats two blocks as a copy from eighty percent of their lines" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const one = [_][]const u8{ "a", "b", "c", "d", "e" };
    const one_changed = [_][]const u8{ "a", "b", "x", "d", "e" };
    const two_changed = [_][]const u8{ "a", "b", "x", "d", "y" };
    const empty: []const []const u8 = &.{};
    try std.testing.expect(try similar(a, &one, &one));
    try std.testing.expect(try similar(a, &one, &one_changed));
    try std.testing.expect(!(try similar(a, &one, &two_changed)));
    try std.testing.expect(!(try similar(a, &one, empty)));
}

test "review inside counts the longest common run of lines" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const one = [_][]const u8{ "a", "b", "c", "d", "e" };
    const two_changed = [_][]const u8{ "a", "b", "x", "d", "y" };
    try std.testing.expectEqual(@as(usize, 3), try lcsLength(a, &one, &two_changed));
    try std.testing.expectEqual(@as(usize, 0), try lcsLength(a, &one, &.{}));
}

test "review inside finds each literal that a condition compares a subject with" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parsed = try parsedForTest(a,
        // migrate-embedded: skip parse-only source spelling and literal-subject observation witness
        \\func parse(args: str[]) -> int:
        \\    mut index: int = 0
        \\    if args[index] == "--port" or args[index] == "-p":
        \\        return 1
        \\    elif "--idle-ms" == args[index]:
        \\        return 2
        \\    elif args[index].startswith("--blocking"):
        \\        return 3
        \\    return 0
        \\
    );
    const found = try comparisonsOf(a, firstTree(parsed));
    try std.testing.expectEqual(@as(usize, 4), found.len);
    try std.testing.expectEqualStrings("args[index]", found[0].subject);
    try std.testing.expectEqualStrings("\"--port\"", found[0].literal);
    try std.testing.expectEqualStrings("\"-p\"", found[1].literal);
    try std.testing.expectEqualStrings("\"--idle-ms\"", found[2].literal);
    try std.testing.expectEqualStrings("args[index]", found[2].subject);
    try std.testing.expectEqualStrings("\"--blocking\"", found[3].literal);
}

test "review inside finds the literal that the starts_with function compares its first argument with" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // With `import strings` the parser keeps `strings.starts_with` in the call's name.
    const imported = try parsedForTest(a,
        \\import strings
        \\
        \\func parse(args: str[]) -> int:
        \\    mut index: int = 0
        \\    if strings.starts_with(args[index], "--blocking"):
        \\        return 1
        \\    elif strings.starts_with(args[index], "--idle-ms=") or args[index] == "--port":
        \\        return 2
        \\    return 0
        \\
    );
    const found = try comparisonsOf(a, firstTree(imported));
    try std.testing.expectEqual(@as(usize, 3), found.len);
    try std.testing.expectEqualStrings("args[index]", found[0].subject);
    try std.testing.expectEqualStrings("\"--blocking\"", found[0].literal);
    try std.testing.expectEqualStrings("\"--idle-ms=\"", found[1].literal);
    try std.testing.expectEqualStrings("args[index]", found[1].subject);
    try std.testing.expectEqualStrings("\"--port\"", found[2].literal);
    // Without the import the parser keeps `strings` as the call's owner.
    const bare = try parsedForTest(a, "func parse(args: str[]) -> int:\n    if strings.starts_with(args[index], \"--idle-ms=\"):\n        return 1\n    return 0\n");
    const owned = try comparisonsOf(a, firstTree(bare));
    try std.testing.expectEqual(@as(usize, 1), owned.len);
    try std.testing.expectEqualStrings("args[index]", owned[0].subject);
    try std.testing.expectEqualStrings("\"--idle-ms=\"", owned[0].literal);
}

test "review inside counts branches, loops, match arms and logical operators on the syntax tree" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parsed = try parsedForTest(a,
        \\enum Shape:
        \\    Circle
        \\    Square
        \\
        \\func decide(shape: Shape, flag: bool, args: str[]) -> int:
        \\    if flag and len(args) > 0:
        \\        return 1
        \\    elif flag or len(args) == 0:
        \\        return 2
        \\    mut index: int = 0
        \\    while index < len(args):
        \\        index += 1
        \\    for item in args:
        \\        index += 1
        \\    match shape:
        \\        case Circle:
        \\            return 3
        \\        case Square:
        \\            return 4
        \\    return 0
        \\
    );
    // if, and, elif, or, while, for, and the two match arms.
    try std.testing.expectEqual(@as(usize, 8), try syntaxDecisions(a, firstTree(parsed)));
}

test "review inside reads the decision points of a file that does not parse from its tokens" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const head = [_]review_side.File{.{ .path = "main.selka", .bytes = "func broken(x: int) -> int:\n    if x > 0 and x < 9:\n        return 1\n    elif x == 3 or x == 4:\n        return 2\n    return x +\n" }};
    const functions = try compare(a, &.{}, &head);
    try std.testing.expectEqual(@as(usize, 1), functions.len);
    try std.testing.expectEqualStrings("main::broken", functions[0].name);
    try std.testing.expectEqual(@as(usize, 4), functions[0].measure.decision_points.after);
    try std.testing.expectEqual(@as(usize, 0), functions[0].signals.len);
}

test "review inside lists a changed function with its lines, decision points and diff" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = [_]review_side.File{.{ .path = "main.selka", .bytes = "func helper(x: int) -> int:\n    if x > 0:\n        return 1\n    return 0\n" }};
    const head = [_]review_side.File{.{ .path = "main.selka", .bytes = "func helper(x: int) -> int:\n    if x > 0:\n        return 1\n    elif x < 0:\n        return 2\n    return 0\n" }};
    const functions = try compare(a, &base, &head);
    try std.testing.expectEqual(@as(usize, 1), functions.len);
    const found = functions[0];
    try std.testing.expectEqualStrings("main::helper", found.name);
    try std.testing.expectEqual(State.changed, found.state);
    try std.testing.expect(!found.public);
    try std.testing.expectEqual(@as(usize, 1), found.location.line);
    try std.testing.expectEqual(@as(usize, 4), found.measure.lines.before);
    try std.testing.expectEqual(@as(usize, 6), found.measure.lines.after);
    try std.testing.expectEqual(@as(usize, 1), found.measure.decision_points.before);
    try std.testing.expectEqual(@as(usize, 2), found.measure.decision_points.after);
    try std.testing.expectEqual(@as(usize, 2), found.diff.len);
    try std.testing.expectEqualStrings("+    elif x < 0:", found.diff[0]);
}

test "review inside skips test functions, generated files and files identical on both sides" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = [_]review_side.File{
        .{ .path = "main.selka", .bytes = "func test_a() -> bool:\n    return true\n" },
        .{ .path = "gen.selka", .bytes = "# GENERATED by tool\nfunc gen() -> int:\n    return 1\n" },
        .{ .path = "same.selka", .bytes = "func same() -> int:\n    return 1\n" },
    };
    const head = [_]review_side.File{
        .{ .path = "main.selka", .bytes = "func test_a() -> bool:\n    return false\n" },
        .{ .path = "gen.selka", .bytes = "# GENERATED by tool\nfunc gen() -> int:\n    return 2\n" },
        .{ .path = "same.selka", .bytes = "func same() -> int:\n    return 1\n" },
    };
    try std.testing.expectEqual(@as(usize, 0), (try compare(a, &base, &head)).len);
}

test "review inside keeps a function's diff to eighty lines and counts the rest" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lines = try numberedLines(a, 100);
    const bounded = try boundedDiff(a, lines, 1000);
    try std.testing.expectEqual(@as(usize, max_function_diff), bounded.len);
    try std.testing.expectEqualStrings("+line 78", bounded[78]);
    try std.testing.expectEqualStrings("… 21 more lines", bounded[79]);
}

test "review inside gives a function only what the review's diff budget has left" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lines = try numberedLines(a, 10);
    const left = try boundedDiff(a, lines, 3);
    try std.testing.expectEqual(@as(usize, 3), left.len);
    try std.testing.expectEqualStrings("… 8 more lines", left[2]);
    try std.testing.expectEqual(@as(usize, 0), (try boundedDiff(a, lines, 0)).len);
    try std.testing.expectEqual(@as(usize, 10), (try boundedDiff(a, lines, 10)).len);
}

test "review inside names a block that repeats another, and the special cases it adds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = [_]review_side.File{.{ .path = "cli.selka", .bytes = parse_serve_base }};
    const head = [_]review_side.File{.{ .path = "cli.selka", .bytes = parse_serve_head }};
    const functions = try compare(a, &base, &head);
    try std.testing.expectEqual(@as(usize, 1), functions.len);
    const signals = functions[0].signals;
    try std.testing.expectEqual(@as(usize, 2), signals.len);
    try std.testing.expectEqual(Kind.special_case, signals[0].kind);
    try std.testing.expectEqualStrings("adds branches that compare `args[index]` against `\"--blocking\"`, `\"--idle-ms\"`", signals[0].text);
    try std.testing.expectEqual(Kind.copy, signals[1].kind);
    try std.testing.expectEqualStrings("the new block at line 13 repeats the block at line 5 with only names or literals changed", signals[1].text);
}

/// The `parse_serve` shape before the change: one `--port` branch that parses a number.
const parse_serve_base =
    \\func parse_serve(args: str[]) -> int:
    \\    mut index: int = 0
    \\    mut port: int = 0
    \\    while index < len(args):
    \\        if args[index] == "--port":
    \\            index += 1
    \\            if index >= len(args):
    \\                return 0 - 1
    \\            port = port * 10 + 1
    \\            port = port + 0
    \\        index += 1
    \\    return port
    \\
;

/// The same function after the change: `--blocking` and `--idle-ms` branches, the second a
/// copy of the `--port` branch with its literal changed.
const parse_serve_head =
    \\func parse_serve(args: str[]) -> int:
    \\    mut index: int = 0
    \\    mut port: int = 0
    \\    while index < len(args):
    \\        if args[index] == "--port":
    \\            index += 1
    \\            if index >= len(args):
    \\                return 0 - 1
    \\            port = port * 10 + 1
    \\            port = port + 0
    \\        elif args[index] == "--blocking":
    \\            return 2
    \\        elif args[index] == "--idle-ms":
    \\            index += 1
    \\            if index >= len(args):
    \\                return 0 - 1
    \\            port = port * 10 + 1
    \\            port = port + 0
    \\        index += 1
    \\    return port
    \\
;

test "review inside does not call two different blocks a copy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = [_]review_side.File{.{ .path = "main.selka", .bytes = "func f(a: int) -> int:\n    return a\n" }};
    const head_text =
        \\func f(a: int) -> int:
        \\    mut total: int = 0
        \\    if a > 0:
        \\        total += a
        \\        total += 2
        \\        total += 3
        \\        total += 4
        \\    if a < 0:
        \\        return 0
        \\        return 1
        \\        return 2
        \\        return 3
        \\    return total
    ;
    const head = [_]review_side.File{.{ .path = "main.selka", .bytes = head_text }};
    const functions = try compare(a, &base, &head);
    try std.testing.expectEqual(@as(usize, 1), functions.len);
    try std.testing.expectEqual(@as(usize, 0), functions[0].signals.len);
}

test "review inside takes a new bool parameter that a branch tests as a flag" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = [_]review_side.File{.{ .path = "main.selka", .bytes = "func flagged(name: str) -> str:\n    return name\n" }};
    const head = [_]review_side.File{.{ .path = "main.selka", .bytes = "func flagged(name: str, verbose: bool) -> str:\n    if verbose:\n        return \"loud\"\n    return name\n" }};
    const functions = try compare(a, &base, &head);
    try std.testing.expectEqual(@as(usize, 1), functions.len);
    try std.testing.expectEqual(@as(usize, 1), functions[0].signals.len);
    try std.testing.expectEqual(Kind.flag, functions[0].signals[0].kind);
    try std.testing.expectEqualStrings("takes a new bool parameter `verbose` and branches on it", functions[0].signals[0].text);
}

test "review inside gives no signal to a small edit of one constant" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = [_]review_side.File{.{ .path = "main.selka", .bytes = "func offset(x: int) -> int:\n    return x + 2\n" }};
    const head = [_]review_side.File{.{ .path = "main.selka", .bytes = "func offset(x: int) -> int:\n    return x + 3\n" }};
    const functions = try compare(a, &base, &head);
    try std.testing.expectEqual(@as(usize, 1), functions.len);
    try std.testing.expectEqual(@as(usize, 0), functions[0].signals.len);
    try std.testing.expectEqual(@as(usize, 2), functions[0].diff.len);
}

test "review inside recognises a test module by its file name" {
    try std.testing.expect(isTestFile("cli_test.selka"));
    try std.testing.expect(isTestFile("app/conn_test.selka"));
    try std.testing.expect(!isTestFile("cli.selka"));
    try std.testing.expect(!isTestFile("testing.selka"));
}

test "review inside lists functions but not module constants, public or private, added or removed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = [_]review_side.File{.{ .path = "main.selka", .bytes = "const OLD: int = 1\n\nfunc offset(x: int) -> int:\n    return x + 2\n" }};
    const head = [_]review_side.File{.{ .path = "main.selka", .bytes = "public const LIMIT: int = 3\nconst SLOTS: int = 1024\n\nfunc offset(x: int) -> int:\n    return x + 3\n" }};
    const functions = try compare(a, &base, &head);
    try std.testing.expectEqual(@as(usize, 1), functions.len);
    try std.testing.expectEqualStrings("main::offset", functions[0].name);
    try std.testing.expectEqual(State.changed, functions[0].state);
}
