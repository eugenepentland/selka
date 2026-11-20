//! Test-only source overlays for docstring transcripts; ordinary compilation is inert.
const std = @import("std");
const grammar = @import("docstring_examples.zig");
const source = @import("source.zig");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const parser = @import("parser.zig");
const lexer = @import("lexer.zig");
const diagnostic = @import("diagnostic.zig");

/// Private generated symbols remain ordinary tests internally.
pub const prefix = "test__docstring_example_";
/// One function's examples and their unmodified defining source.
pub const Block = struct { module: []const u8, function: []const u8, generated: []const u8, src: source.Source, examples: []const grammar.Example };
/// How a checked expression is displayed; statements do not have a display value.
pub const Display = enum { statement, probe, unit, printed, repr };
/// One generated line's original docstring position. `text` is the overlay offset
/// where an example line copies its prompt-stripped text, which runs to the line's
/// newline; a line the extraction synthesized leaves it null.
pub const Position = struct { start: usize, end: usize, original: source.Span, text: ?usize = null };
/// An appended function and its source-position table.
pub const Overlay = struct { text: []const u8, positions: []const Position, expressions: []const source.Span, display: []const Display };
/// One expected output section, separated by compiler-owned transcript boundaries.
pub const Expected = struct { marker: []const u8, text: []const u8, line: usize };
/// What the trial grader needs, with no ownership of compiler syntax.
pub const Transcript = struct { path: []const u8, sections: []const Expected, ending: []const u8 };

const Parsed = struct { syntax: ast.Program, tokens: []const lexer.Token };

fn syntaxOf(a: std.mem.Allocator, src: source.Source) diagnostic.Error!Parsed {
    var sink: diagnostic.Sink = .{ .allocator = a };
    const tokens = try lexer.lex(a, src.bytes, &sink);
    var reading: parser.Parser = .{ .src = src, .storage = a, .tokens = tokens, .sink = &sink };
    const syntax = try reading.parseModule();
    for (sink.items.items) |finding| if (finding.severity == .err) return error.SourceError;
    return .{ .syntax = syntax, .tokens = tokens };
}

/// Extract function docstrings only, including private and generic definitions.
/// The prompt byte scan keeps ordinary modules off the parser path entirely.
pub fn extract(a: std.mem.Allocator, module: []const u8, src: source.Source) std.mem.Allocator.Error![]const Block {
    if (std.mem.indexOf(u8, src.bytes, ">>> ") == null) return &.{};
    const parsed = syntaxOf(a, src) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return &.{};
    };
    var blocks: std.ArrayList(Block) = .empty;
    for (parsed.syntax.functions) |function| {
        if (function.policy.constant) continue;
        const doc = ast.docstringOf(parsed.syntax, function.name) orelse continue;
        if (grammar.count(doc.text) == 0) continue;
        const function_name = src.text(function.name);
        var generated = try std.mem.concat(a, u8, &.{ prefix, function_name });
        while (declared(src, parsed.tokens, generated)) generated = try std.mem.concat(a, u8, &.{ generated, "_" });
        try blocks.append(a, .{ .module = module, .function = function_name, .generated = generated, .src = src, .examples = try grammar.parse(a, doc.text, src.locate(doc.span.start).line) });
    }
    return blocks.items;
}

fn declared(src: source.Source, tokens: []const lexer.Token, candidate: []const u8) bool {
    for (tokens) |token| if (token.tag == .ident and std.mem.eql(u8, src.text(token.span), candidate)) return true;
    return false;
}

/// Whether a source has a function docstring with a real prompt, for root discovery.
pub fn contains(a: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error!bool {
    if (std.mem.indexOf(u8, bytes, ">>> ") == null) return false;
    const src = try source.Source.init(a, "", bytes);
    const parsed = syntaxOf(a, src) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return malformedTranscript(a, src);
    };
    for (parsed.syntax.functions) |function| {
        if (function.policy.constant) continue;
        const doc = ast.docstringOf(parsed.syntax, function.name) orelse continue;
        if (grammar.count(doc.text) != 0) return true;
    }
    return false;
}

fn malformedTranscript(a: std.mem.Allocator, src: source.Source) std.mem.Allocator.Error!bool {
    var sink: diagnostic.Sink = .{ .allocator = a };
    const tokens = lexer.lexRange(a, src.bytes, .{ .start = 0, .end = src.bytes.len }, &sink) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        var limit = src.bytes.len;
        for (sink.items.items) |finding| {
            if (finding.severity != .err) continue;
            if (std.mem.eql(u8, finding.code, "E_BYTE_LITERAL") and transcriptLiteral(src, finding.span, false)) return true;
            limit = @min(limit, finding.span.start);
        }
        if (limit == 0 or limit == src.bytes.len) return false;
        var prior_sink: diagnostic.Sink = .{ .allocator = a };
        const prior = lexer.lexRange(a, src.bytes, .{ .start = 0, .end = limit }, &prior_sink) catch |prior_error| {
            if (prior_error == error.OutOfMemory) return error.OutOfMemory;
            return false;
        };
        return transcriptTokens(src, prior);
    };
    return transcriptTokens(src, tokens);
}

fn transcriptTokens(src: source.Source, tokens: []const lexer.Token) bool {
    for (tokens) |token| if (token.tag == .bytes and transcriptLiteral(src, token.span, true)) return true;
    return false;
}

fn transcriptLiteral(src: source.Source, span: source.Span, complete: bool) bool {
    if (src.physicalLocation(span.start).column <= 1) return false;
    const literal = src.text(span);
    const closing: usize = if (complete) 3 else 0;
    if (literal.len < 3 + closing or !@import("byte_literal.zig").tripleStart(literal, 0, literal.len)) return false;
    return grammar.count(literal[3 .. literal.len - closing]) != 0;
}

/// Stable public case identity, with the suffix after the final module separator.
pub fn name(a: std.mem.Allocator, block: Block) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(a, "{s}::{s}.example", .{ block.module, block.function });
}

fn expression(a: std.mem.Allocator, example: grammar.Example) std.mem.Allocator.Error!bool {
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(a, "func example() -> Unit:\n    const docstring_parse_anchor = 0\n");
    for (example.lines) |line| try text.print(a, "    {s}\n", .{line.text});
    const parsed = syntaxOf(a, try source.Source.init(a, "", text.items)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return false;
    };
    const syntax = parsed.syntax;
    if (syntax.functions.len != 1) return false;
    const body = syntax.statements.items[@backingInt(syntax.functions[0].body)].data;
    if (body != .block or body.block.len != 2) return false;
    const statement = syntax.statements.items[@backingInt(body.block[1])];
    if (!statement.implicit_discard or statement.data != .discard) return false;
    // `xs[0] = 1` and `p.field = 2` parse as a discarded expression, but an
    // assignment has no display value: the example is a statement, not a value
    // wrapped for display (FR-412).
    return !writesAPlace(syntax.nodes.items[@backingInt(statement.data.discard)]);
}

fn writesAPlace(node: ast.Node) bool {
    return switch (node.data) {
        .index_assignment, .field_assignment => true,
        .list_operation => |operation| operation.kind == .write,
        else => false,
    };
}

fn original(src: source.Source, line: usize) source.Span {
    const start = src.line_starts[@min(line - 1, src.line_starts.len - 1)];
    const end = std.mem.indexOfScalarPos(u8, src.bytes, start, '\n') orelse src.bytes.len;
    const body = std.mem.trimStart(u8, src.bytes[start..end], " \t");
    return .{ .start = start + (end - start - body.len), .end = end };
}

/// Build an overlay. A null display table produces printable probes whose checked
/// operand types choose the final display; no probe executable is ever run.
pub fn render(a: std.mem.Allocator, block: Block, displays: ?[]const Display, transcript: Transcript) std.mem.Allocator.Error!Overlay {
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(a, block.src.bytes);
    const declaration_start = text.items.len;
    try text.print(a, "\n\npublic func {s}(fs: Filesystem, net: Network, clock: Clock, entropy: Entropy, env: Environment, out: Stream) -> bool:\n", .{block.generated});
    var positions: std.ArrayList(Position) = .empty;
    try positions.append(a, .{ .start = declaration_start, .end = text.items.len, .original = original(block.src, block.examples[0].line) });
    const binding_start = text.items.len;
    try text.appendSlice(a, "    _ = fs\n    _ = net\n    _ = clock\n    _ = entropy\n    _ = env\n    _ = out\n");
    try positions.append(a, .{ .start = binding_start, .end = text.items.len, .original = original(block.src, block.examples[0].line) });
    const expressions = try a.alloc(source.Span, block.examples.len);
    const display = try a.alloc(Display, block.examples.len);
    for (block.examples, 0..) |example, index| {
        display[index] = if (displays) |known| known[index] else if (try expression(a, example)) .probe else .statement;
        const marker = try std.json.Stringify.valueAlloc(a, transcript.sections[index].marker, .{});
        const boundary_start = text.items.len;
        try text.print(a, "    print(out, {s}, end=\"\")\n", .{marker});
        try positions.append(a, .{ .start = boundary_start, .end = text.items.len, .original = original(block.src, example.line) });
        const start = text.items.len;
        const mode = display[index];
        const opening: []const u8 = switch (mode) {
            .probe, .printed => "print(out,",
            .repr => "print(out, repr(",
            else => "",
        };
        const closing: []const u8 = switch (mode) {
            .probe, .printed => ")",
            .repr => "))",
            else => "",
        };
        if (opening.len != 0) {
            const line_start = text.items.len;
            try text.print(a, "    {s}\n", .{opening});
            try positions.append(a, .{ .start = line_start, .end = text.items.len, .original = original(block.src, example.line) });
        }
        for (example.lines) |line| {
            const line_start = text.items.len;
            try text.print(a, "    {s}{s}\n", .{ if (opening.len != 0) "    " else "", line.text });
            try positions.append(a, .{ .start = line_start, .end = text.items.len, .original = original(block.src, line.line), .text = text.items.len - 1 - line.text.len });
        }
        if (closing.len != 0) {
            const line_start = text.items.len;
            try text.print(a, "    {s}\n", .{closing});
            try positions.append(a, .{ .start = line_start, .end = text.items.len, .original = original(block.src, example.lines[example.lines.len - 1].line) });
        }
        expressions[index] = .{ .start = start, .end = text.items.len };
    }
    const ending_start = text.items.len;
    try text.print(a, "    print(out, {s}, end=\"\")\n    return True\n", .{try std.json.Stringify.valueAlloc(a, transcript.ending, .{})});
    try positions.append(a, .{ .start = ending_start, .end = text.items.len, .original = original(block.src, block.examples[block.examples.len - 1].line) });
    return .{ .text = text.items, .positions = positions.items, .expressions = expressions, .display = display };
}

/// Transcript boundaries incorporate every expected byte, so a changed expectation
/// invalidates ordinary IR and executable receipts without a separate cache tier.
pub fn transcriptOf(a: std.mem.Allocator, block: Block) std.mem.Allocator.Error!Transcript {
    var digest: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(block.src.bytes, &digest, .{});
    const sections = try a.alloc(Expected, block.examples.len);
    for (sections, block.examples, 0..) |*section, example, index| section.* = .{
        .marker = try std.fmt.allocPrint(a, "\x1eDOC-{s}-{d}\x1f", .{ std.fmt.bytesToHex(digest[0..12], .lower), index }),
        .text = example.expected,
        .line = example.line,
    };
    return .{ .path = block.src.path, .sections = sections, .ending = try std.fmt.allocPrint(a, "\x1eDOC-{s}-END\x1f", .{std.fmt.bytesToHex(digest[0..12], .lower)}) };
}

fn moduleOffset(src: source.Source, path: []const u8) usize {
    for (src.origins) |origin| if (std.mem.eql(u8, origin.original.path, path)) return origin.start;
    return 0;
}

/// Read only the synthetic outer print's operand type; nested user prints retain
/// their ordinary behavior, and unit expressions lose the synthetic print.
pub fn displaysOf(a: std.mem.Allocator, program: typed.Program, src: source.Source, block: Block, overlay: Overlay) std.mem.Allocator.Error![]const Display {
    const result = try a.dupe(Display, overlay.display);
    const offset = moduleOffset(src, block.src.path);
    for (overlay.expressions, result) |span, *display| {
        if (display.* != .probe) continue;
        for (program.nodes) |node| {
            if (node.data != .print or node.data.print.arguments.len != 1) continue;
            if (node.span.start != offset + span.start + 4 or node.span.end > offset + span.end) continue;
            const ty = program.nodes[@backingInt(node.data.print.arguments[0])].ty;
            display.* = if (ty == .unit) .unit else if (ty.isAggregate() and (program.records[ty.recordIndex()].collection.kind == .string or typed.byteString(ty, program.records))) .repr else .printed;
            break;
        }
    }
    return result;
}

/// Map all generated expression and statement positions back to docstring lines.
/// The returned tables are private copies, so shared checked snapshots remain intact.
pub fn remap(a: std.mem.Allocator, program: typed.Program, src: source.Source, block: Block, overlay: Overlay) std.mem.Allocator.Error!typed.Program {
    var result = program;
    const offset = moduleOffset(src, block.src.path);
    const nodes = try a.dupe(typed.Node, program.nodes);
    for (nodes) |*node| {
        node.span = mapped(node.span, offset, overlay.positions);
        switch (node.data) {
            .unary => |*operation| operation.op_span = mapped(operation.op_span, offset, overlay.positions),
            .binary => |*operation| operation.op_span = mapped(operation.op_span, offset, overlay.positions),
            else => {},
        }
    }
    const statements = try a.dupe(typed.Statement, program.statements);
    for (statements) |*statement| {
        statement.span = mapped(statement.span, offset, overlay.positions);
        if (statement.data == .range_loop) {
            const parts = try a.dupe(typed.RangeParts, statement.data.range_loop.parts);
            for (parts) |*part| part.binding = mapped(part.binding, offset, overlay.positions);
            statement.data.range_loop.parts = parts;
        }
    }
    const functions = try a.dupe(typed.Function, program.functions);
    for (functions) |*function| {
        const locals = try a.dupe(typed.Local, function.scope.locals);
        for (locals) |*local| {
            local.declaration = mapped(local.declaration, offset, overlay.positions);
            if (local.ownership.transfer_span) |span| local.ownership.transfer_span = mapped(span, offset, overlay.positions);
            if (local.usage.dead_write_span) |span| local.usage.dead_write_span = mapped(span, offset, overlay.positions);
        }
        function.scope.locals = locals;
        const own = if (std.mem.lastIndexOf(u8, function.name, "::")) |at| function.name[at + 2 ..] else function.name;
        if (!std.mem.eql(u8, own, block.generated)) continue;
        function.name = try name(a, block);
        const span = original(block.src, block.examples[0].line);
        function.declaration = .{ .start = offset + span.start, .end = offset + span.end };
    }
    result.functions = functions;
    result.nodes = nodes;
    result.statements = statements;
    return result;
}

fn mapped(span: source.Span, offset: usize, positions: []const Position) source.Span {
    for (positions) |position| if (span.start >= offset + position.start and span.start < offset + position.end) return .{ .start = offset + position.original.start, .end = offset + position.original.end };
    return span;
}

/// The overlay offset where the appended generated function begins; everything
/// before it is the module's own, unchanged text.
pub fn appendedStart(overlay: Overlay) usize {
    return overlay.positions[0].start;
}

/// The original docstring line the generated line holding overlay `offset` was
/// made from (from its first non-blank byte to its end), or null before the
/// generated function.
pub fn originalLine(overlay: Overlay, offset: usize) ?source.Span {
    for (overlay.positions) |position| if (offset >= position.start and offset < position.end) return position.original;
    return null;
}

/// The original source bytes that overlay bytes `range` copy verbatim from a
/// docstring line, or null when the range touches any byte the extraction
/// synthesized (indentation, a probe wrapper or a line break), or spans two
/// lines, or the original no longer reads the same bytes there. An empty range
/// is an insertion point; one at either end of a copied line maps to the same
/// end of the original text. An edit for the overlay is applicable to the
/// original source only through this mapping, never by line alone.
pub fn originalRange(block: Block, overlay: Overlay, range: source.Span) ?source.Span {
    if (range.start > range.end) return null;
    for (overlay.positions) |position| {
        const copied = position.text orelse continue;
        const finish = position.end - 1;
        if (range.start < copied or range.end > finish) continue;
        const prompt = position.original.start;
        if (prompt + prompt_length > block.src.bytes.len) return null;
        const marker = block.src.bytes[prompt..][0..prompt_length];
        if (!std.mem.eql(u8, marker, ">>> ") and !std.mem.eql(u8, marker, "... ")) return null;
        const at = prompt + prompt_length;
        if (at + (finish - copied) > block.src.bytes.len) return null;
        if (!std.mem.eql(u8, block.src.bytes[at..][0 .. finish - copied], overlay.text[copied..finish])) return null;
        return .{ .start = at + range.start - copied, .end = at + range.end - copied };
    }
    return null;
}

/// Bytes in a `>>> ` or `... ` prompt.
const prompt_length = 4;

/// Remap rendered checker positions from appended source to the original prompt.
pub fn diagnosticText(a: std.mem.Allocator, text: []const u8, block: Block, overlay: Overlay) std.mem.Allocator.Error![]const u8 {
    var result = text;
    for (overlay.positions) |position| {
        const generated = 1 + std.mem.count(u8, overlay.text[0..position.start], "\n");
        const actual = block.src.locate(position.original.start).line;
        const before = try std.fmt.allocPrint(a, "{s}:{d}:", .{ block.src.path, generated });
        const after = try std.fmt.allocPrint(a, "{s}:{d}:", .{ block.src.path, actual });
        result = try std.mem.replaceOwned(u8, a, result, before, after);
    }
    return result;
}
