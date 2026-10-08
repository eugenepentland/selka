//! The `W_ARENA_RETIRED` warning of a retired `with arena():` block (S5-D3)
//! and the `mylang fix` repair it carries: delete the `with` line, dedent the
//! block's body by one level and rewrite each `name.escape(value)` of that
//! arena to `value`. The repair is offered only where the edit is certain: a
//! header alone on its line, space indentation, and no multi-line string
//! literal in the body. Both are derived from the syntax after the bodies are
//! checked, so a body the semantic cache reuses still reports them.
const std = @import("std");
const ast = @import("ast.zig");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");

/// The warning a `with arena():` block carries (NEW-CORE-S5-ARENA-1).
pub const retired_code = "W_ARENA_RETIRED";
/// The `W_ARENA_RETIRED` message: what an arena block now does and how to drop it.
const retired_message = "`with arena():` is retired (S5-D3): the block runs as an ordinary block and frees nothing early; remove the `with arena():` line and dedent its body";

/// Report `W_ARENA_RETIRED` at every `with arena()` block of `syntax`, with the
/// repair `mylang fix` applies when its edits are certain (NEW-CORE-S5-ARENA-3).
pub fn warn(allocator: std.mem.Allocator, src: source.Source, syntax: ast.Program, sink: *diagnostic.Sink) std.mem.Allocator.Error!void {
    for (syntax.statements.items) |statement| {
        if (statement.data != .with_scope or statement.data.with_scope.resource != null) continue;
        const scope = statement.data.with_scope;
        const body = syntax.statements.items[@backingInt(scope.body)];
        var fix: ?diagnostic.Fix = null;
        if (body.data == .block and body.data.block.len != 0) {
            var escapes: std.ArrayList(diagnostic.Edit) = .empty;
            if (scope.name) |name| try findEscapes(allocator, src, syntax, .{ .name = src.text(name), .region = body.span }, &escapes);
            const first = syntax.statements.items[@backingInt(body.data.block[0])].span.start;
            fix = try retirementFix(allocator, src.bytes, .{ .with_start = statement.span.start, .body_start = first, .body_end = body.span.end }, escapes.items);
        }
        try sink.items.append(allocator, .{ .severity = .warning, .code = retired_code, .span = statement.span, .message = retired_message, .provenance = .{ .fix = fix } });
    }
}

/// One arena binding's name and the body it is visible in.
const Binding = struct { name: []const u8, region: source.Span };

/// Append the rewrite of every `name.escape(value)` call inside the arena's
/// body. Arena names cannot shadow one another, so the spelling decides.
fn findEscapes(allocator: std.mem.Allocator, src: source.Source, syntax: ast.Program, binding: Binding, escapes: *std.ArrayList(diagnostic.Edit)) std.mem.Allocator.Error!void {
    for (syntax.nodes.items) |node| {
        if (node.data != .call or node.span.start < binding.region.start or node.span.end > binding.region.end) continue;
        const call = node.data.call;
        const owner = call.owner orelse continue;
        const escape = std.mem.eql(u8, src.text(owner), binding.name) and std.mem.eql(u8, src.text(call.name), "escape");
        if (!escape or call.arguments.len != 1) continue;
        const argument = syntax.nodes.items[@backingInt(call.arguments[0])];
        const simple = switch (argument.data) {
            .name, .call, .method_call, .field, .index, .integer, .text, .bytes, .boolean => true,
            else => false,
        };
        try appendEscape(allocator, escapes, node.span, call.name.end, argument.span, simple);
    }
}

/// Where one arena block sits in its module's bytes.
pub const Block = struct {
    /// The `with` keyword's offset.
    with_start: usize,
    /// The offset of the body's first statement.
    body_start: usize,
    /// The end of the body's last token.
    body_end: usize,
};

/// The repair for the arena block at `block` in `bytes`, with the escape
/// rewrites `escapes` (already found by the checker) folded in; null when the
/// block's layout leaves any edit uncertain. Edits are allocated with
/// `allocator`, an arena: a refused block may leave partial edits in it.
pub fn retirementFix(allocator: std.mem.Allocator, bytes: []const u8, block: Block, escapes: []const diagnostic.Edit) std.mem.Allocator.Error!?diagnostic.Fix {
    const header_line = lineStart(bytes, block.with_start);
    const outer = indentation(bytes, header_line) orelse return null;
    if (header_line + outer != block.with_start) return null;
    const header_end = std.mem.indexOfScalarPos(u8, bytes, block.with_start, '\n') orelse return null;
    // The header must end its line, so the body starts on a later one.
    if (block.body_start <= header_end) return null;
    const comment = headerComment(bytes[block.with_start..header_end]) orelse return null;
    const body_line = lineStart(bytes, block.body_start);
    const inner = indentation(bytes, body_line) orelse return null;
    if (body_line + inner != block.body_start or inner <= outer) return null;
    const depth = inner - outer;
    if (std.mem.indexOf(u8, bytes[block.body_start..block.body_end], "\"\"\"") != null) return null;
    if (std.mem.indexOf(u8, bytes[block.body_start..block.body_end], "'''") != null) return null;

    var edits: std.ArrayList(diagnostic.Edit) = .empty;
    // The header line goes; a trailing comment on it stays, at the block's own
    // indentation, so no text but the header is lost.
    const header: source.Span = .{ .start = header_line, .end = header_end + 1 };
    const kept = if (comment.len == 0) "" else try std.fmt.allocPrint(allocator, "{s}{s}\n", .{ bytes[header_line..block.with_start], comment });
    try edits.append(allocator, .{ .span = header, .text = kept });
    var line = header_end + 1;
    var last_body_line = lineStart(bytes, if (block.body_end > 0) block.body_end - 1 else 0);
    while (line < bytes.len) {
        const end = std.mem.indexOfScalarPos(u8, bytes, line, '\n') orelse bytes.len;
        const text = bytes[line..end];
        const blank = std.mem.trim(u8, text, " \t\r").len == 0;
        if (line > last_body_line) {
            // Comment lines indented as the body, just after its last token,
            // belong with it.
            if (blank) {
                line = end + 1;
                continue;
            }
            const spaces = indentation(bytes, line) orelse break;
            if (spaces < inner or text[spaces] != '#') break;
            last_body_line = line;
        }
        if (!blank) {
            const spaces = indentation(bytes, line) orelse return null;
            if (spaces >= depth) try edits.append(allocator, .{ .span = .{ .start = line, .end = line + depth }, .text = "" });
        }
        line = end + 1;
    }
    // A call the parser built twice (on a backtrack) is rewritten once.
    for (escapes, 0..) |escape, index| {
        const repeated = for (escapes[0..index]) |earlier| {
            if (earlier.span.start == escape.span.start and earlier.span.end == escape.span.end) break true;
        } else false;
        if (!repeated) try edits.append(allocator, escape);
    }
    const owned = try edits.toOwnedSlice(allocator);
    return .{ .edit = owned[0], .more = owned[1..] };
}

/// Append the edits that turn `name.escape(value)`, spanning `call`, into
/// `value`, where `value` spans `argument` and `name_end` ends the `escape`
/// name. A `simple` argument (a name, literal, call, field or index) loses the
/// wrapper; any other keeps its parentheses, so the rewrite never changes how
/// the surrounding expression groups.
pub fn appendEscape(allocator: std.mem.Allocator, edits: *std.ArrayList(diagnostic.Edit), call: source.Span, name_end: usize, argument: source.Span, simple: bool) std.mem.Allocator.Error!void {
    if (!simple) return edits.append(allocator, .{ .span = .{ .start = call.start, .end = name_end }, .text = "" });
    try edits.append(allocator, .{ .span = .{ .start = call.start, .end = argument.start }, .text = "" });
    try edits.append(allocator, .{ .span = .{ .start = argument.end, .end = call.end }, .text = "" });
}

/// The offset of the first byte of the line holding `offset`.
fn lineStart(bytes: []const u8, offset: usize) usize {
    return if (std.mem.lastIndexOfScalar(u8, bytes[0..offset], '\n')) |newline| newline + 1 else 0;
}

/// The number of spaces that open the line at `start`; null when a tab is
/// part of its indentation, which leaves the dedent uncertain.
fn indentation(bytes: []const u8, start: usize) ?usize {
    var index = start;
    while (index < bytes.len and bytes[index] == ' ') index += 1;
    if (index < bytes.len and bytes[index] == '\t') return null;
    return index - start;
}

/// The trailing `# comment` of a `with arena() [as name]:` header line (empty
/// when there is none); null when the header does not end at its colon.
fn headerComment(header: []const u8) ?[]const u8 {
    const hash = std.mem.indexOfScalar(u8, header, '#') orelse header.len;
    const code = std.mem.trimEnd(u8, header[0..hash], " \t\r");
    if (code.len == 0 or code[code.len - 1] != ':') return null;
    if (std.mem.indexOfScalar(u8, code, ':').? != code.len - 1) return null;
    return std.mem.trimEnd(u8, header[hash..], " \t\r");
}
