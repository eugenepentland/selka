//! Opt-in, placement-preserving conversion of eligible comments to docstrings.
const std = @import("std");
const ast = @import("ast.zig");
const interfaces = @import("interfaces.zig");
const source = @import("source.zig");
const baseline = @import("api_diff_baseline.zig");
/// Parse/allocation failures or prose with no lossless supported quote delimiter.
pub const Error = @import("diagnostic.zig").Error || error{CommentDelimiterCollision};
/// One comment block moved into a docstring, named for the declaration it now documents.
pub const Adoption = struct { path: []const u8, target: []const u8, line: usize };

/// Rewritten source plus every adoption the rewrite made, in source order.
pub const Report = struct { source: []const u8, adoptions: []const Adoption };

/// Return rewritten source, using each comment line at most once.
/// Directives, constants, existing docstrings and body comments remain untouched.
pub fn rewrite(a: std.mem.Allocator, module: @import("project.zig").Module, unit: interfaces.Unit) Error![]const u8 {
    return (try rewriteReport(a, module, unit)).source;
}

/// Rewrite one module and report every comment block the rewrite adopted.
pub fn rewriteReport(a: std.mem.Allocator, module: @import("project.zig").Module, unit: interfaces.Unit) Error!Report {
    var edits: std.ArrayList(Edit) = .empty;
    var adoptions: std.ArrayList(Adoption) = .empty;
    const bytes = module.src.bytes;
    var sink: @import("diagnostic.zig").Sink = .{ .allocator = a };
    const tokens = try @import("lexer.zig").lexRange(a, bytes, .{ .start = 0, .end = bytes.len }, &sink);
    if (module.imports.len != 0 and ast.docstringOf(unit.syntax, ast.module_docstring_span) == null) {
        const first = lineStart(bytes, module.imports[0].span.start);
        const block = commentsBefore(bytes, first);
        if (std.mem.trim(u8, bytes[0..block.start], " \t\r\n").len == 0) {
            const insertion = afterLine(bytes, module.imports[module.imports.len - 1].span.end);
            if (try adopt(a, bytes, block, .{ .offset = insertion, .indent = "" }, &edits)) {
                try adoptions.append(a, .{ .path = try a.dupe(u8, module.src.path), .target = try a.dupe(u8, module.name), .line = module.src.physicalLocation(block.start).line });
            }
        }
    }
    for (unit.symbols.items) |symbol| {
        if (!symbol.exported or ast.docstringOf(unit.syntax, symbol.span) != null) continue;
        if (!eligible(unit.syntax, symbol)) continue;
        const start = lineStart(bytes, ast.declarationStart(unit.syntax, symbol.span));
        const block = commentsBefore(bytes, start);
        const insertion = bodyStart(tokens, bytes, symbol.span.end) orelse continue;
        if (try adopt(a, bytes, block, .{ .offset = insertion, .indent = "    " }, &edits)) {
            try adoptions.append(a, .{
                .path = try a.dupe(u8, module.src.path),
                .target = try std.fmt.allocPrint(a, "{s}::{s}", .{ module.name, symbol.name }),
                .line = module.src.physicalLocation(block.start).line,
            });
        }
    }
    std.mem.sort(Adoption, adoptions.items, {}, adoptionLess);
    std.mem.sort(Edit, edits.items, {}, less);
    var out: std.ArrayList(u8) = .empty;
    var offset: usize = 0;
    for (edits.items) |edit| {
        if (edit.start < offset) continue;
        try out.appendSlice(a, bytes[offset..edit.start]);
        try out.appendSlice(a, edit.text);
        offset = edit.end;
    }
    try out.appendSlice(a, bytes[offset..]);
    return .{ .source = out.items, .adoptions = adoptions.items };
}
const Edit = struct { start: usize, end: usize, text: []const u8 };
const Block = struct { start: usize, end: usize };
const Insertion = struct { offset: usize, indent: []const u8 };
fn less(_: void, left: Edit, right: Edit) bool {
    return left.start < right.start or (left.start == right.start and left.end < right.end);
}

fn adoptionLess(_: void, left: Adoption, right: Adoption) bool {
    if (left.line != right.line) return left.line < right.line;
    return std.mem.lessThan(u8, left.target, right.target);
}
fn lineStart(bytes: []const u8, at: usize) usize {
    return if (std.mem.lastIndexOfScalar(u8, bytes[0..at], '\n')) |index| index + 1 else 0;
}
fn afterLine(bytes: []const u8, at: usize) usize {
    return if (std.mem.indexOfScalarPos(u8, bytes, at, '\n')) |index| index + 1 else bytes.len;
}
fn commentsBefore(bytes: []const u8, end: usize) Block {
    var start = end;
    while (start > 0) {
        const previous = lineStart(bytes, start - 1);
        const line = bytes[previous .. start - 1];
        if (line.len == 0 or line[0] != '#') break;
        // A banner or section divider groups what follows; it is not prose
        // about the declaration, so a block containing one is never adopted.
        if (decorative(line)) return .{ .start = end, .end = end };
        start = previous;
    }
    return .{ .start = start, .end = end };
}

/// Whether a comment line is a banner or section divider: three or more of the
/// same punctuation mark in a row, as in `# ======`, `# --- Title ---` or
/// `# #### Heading`. Such a line groups what follows; it is never prose about
/// the declaration.
fn decorative(line: []const u8) bool {
    const text = std.mem.trim(u8, line[1..], " \t\r");
    var previous: u8 = 0;
    var run: usize = 0;
    for (text) |byte| {
        if (!bannerMark(byte)) {
            previous = 0;
            run = 0;
            continue;
        }
        if (byte == previous) run += 1 else {
            previous = byte;
            run = 1;
        }
        if (run >= 3) return true;
    }
    return false;
}

/// The punctuation a decorative rule is drawn with. Quotes, dots and other
/// punctuation in prose are not banner marks.
fn bannerMark(byte: u8) bool {
    return byte == '-' or byte == '=' or byte == '*' or byte == '_' or byte == '~' or byte == '#' or byte == '+';
}
fn bodyStart(tokens: []const @import("lexer.zig").Token, bytes: []const u8, at: usize) ?usize {
    var depth: usize = 0;
    for (tokens) |token| {
        if (token.span.start < at) continue;
        switch (token.tag) {
            .lparen, .lbracket, .lbrace => depth += 1,
            .rparen, .rbracket, .rbrace => depth -|= 1,
            .colon => if (depth == 0) {
                return afterLine(bytes, token.span.end);
            },
            .semicolon, .indent, .dedent, .eof => if (depth == 0) {
                return null;
            },
            else => {},
        }
    }
    return null;
}
fn eligible(syntax: ast.Program, symbol: interfaces.Symbol) bool {
    if (symbol.kind == .function) {
        for (syntax.functions) |function| if (function.name.start == symbol.span.start) return !function.policy.constant and !function.policy.c_abi;
        return false;
    }
    for (syntax.types.records) |record| if (record.name.start == symbol.span.start) return true;
    for (syntax.types.variants) |variant| if (variant.name.start == symbol.span.start) return true;
    return false;
}
fn adopt(a: std.mem.Allocator, bytes: []const u8, block: Block, insertion: Insertion, edits: *std.ArrayList(Edit)) !bool {
    if (block.start == block.end) return false;
    var content: std.ArrayList(u8) = .empty;
    var removals: std.ArrayList(Edit) = .empty;
    var offset = block.start;
    while (offset < block.end) {
        const next = afterLine(bytes, offset);
        const raw = std.mem.trimEnd(u8, bytes[offset + 1 .. next], "\r\n");
        const line = if (std.mem.startsWith(u8, raw, " ")) raw[1..] else raw;
        const trimmed = std.mem.trimStart(u8, line, " \t");
        const directive = std.mem.startsWith(u8, trimmed, "lint:") or std.mem.startsWith(u8, trimmed, "doc:") or std.mem.startsWith(u8, trimmed, "!");
        if (!directive) {
            if (content.items.len != 0) try content.append(a, '\n');
            try content.appendSlice(a, line);
            try removals.append(a, .{ .start = offset, .end = next, .text = "" });
        }
        offset = next;
    }
    if (std.mem.trim(u8, content.items, " \t\r\n").len == 0) return false;
    const delimiter: []const u8 = if (std.mem.indexOf(u8, content.items, "\"\"\"") == null) "\"\"\"" else if (std.mem.indexOf(u8, content.items, "'''") == null) "'''" else return error.CommentDelimiterCollision;
    var literal: std.ArrayList(u8) = .empty;
    try literal.appendSlice(a, delimiter);
    for (content.items) |byte| {
        try literal.append(a, byte);
        if (byte == '\n') try literal.appendSlice(a, insertion.indent);
    }
    try literal.appendSlice(a, delimiter);
    try edits.appendSlice(a, removals.items);
    try edits.append(a, .{ .start = insertion.offset, .end = insertion.offset, .text = try std.fmt.allocPrint(a, "{s}{s}\n", .{ insertion.indent, literal.items }) });
    return true;
}

/// Refuse an adoption that changes any public declaration's identity or interface.
pub fn confirmInterface(a: std.mem.Allocator, previous: []const baseline.Entry, current: []const baseline.Entry) (baseline.Error || error{AdoptionChangedInterface})!void {
    const changes = try baseline.compareEntries(a, previous, current);
    defer baseline.freeChanges(a, changes);
    if (changes.additive.len != 0 or changes.breaking.len != 0) return error.AdoptionChangedInterface;
}
