//! The `E_ARENA_REMOVED` error for a removed `with arena():` block (S5-D3)
//! and the `mylang fix` repair it carries: delete the `with` line, dedent the
//! block's body by one level and rewrite each `name.escape(value)` of that
//! arena to `value`. The repair is offered only where the edit is certain: a
//! header alone on its line, space indentation, and no multi-line string
//! literal in the body, and bindings that stay unambiguous after dedent. Both
//! are derived from syntax even when a body fails semantic checking or its
//! checked summary is reused.
const std = @import("std");
const ast = @import("ast.zig");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");

/// The removal error a `with arena():` block carries (NEW-CORE-S5-ARENA-1).
pub const removed_code = "E_ARENA_REMOVED";
/// The `E_ARENA_REMOVED` message: what an arena block now does and how to drop it.
const removed_message = "`with arena():` was removed; use ordinary statements: remove the `with arena():` line and dedent its body";

/// Report `E_ARENA_REMOVED` at every `with arena()` block of `syntax`, with the
/// repair `mylang fix` applies when its edits are certain (NEW-CORE-S5-ARENA-3).
pub fn reject(allocator: std.mem.Allocator, src: source.Source, syntax: ast.Program, sink: *diagnostic.Sink) std.mem.Allocator.Error!void {
    for (syntax.statements.items) |statement| {
        if (statement.data != .with_scope or statement.data.with_scope.resource != null) continue;
        const scope = statement.data.with_scope;
        const body = syntax.statements.items[@backingInt(scope.body)];
        var fix: ?diagnostic.Fix = null;
        if (body.data == .block and body.data.block.len != 0 and bindingsCertain(src, syntax, statement, body)) {
            var escapes: std.ArrayList(diagnostic.Edit) = .empty;
            if (scope.name) |name| try findEscapes(allocator, src, syntax, .{ .name = src.text(name), .region = body.span }, &escapes);
            const first = syntax.statements.items[@backingInt(body.data.block[0])].span.start;
            fix = try retirementFix(allocator, src.bytes, .{ .with_start = statement.span.start, .body_start = first, .body_end = body.span.end }, escapes.items);
        }
        try sink.items.append(allocator, .{ .severity = .err, .code = removed_code, .span = statement.span, .message = removed_message, .provenance = .{ .fix = fix } });
    }
}

/// Withhold structural repairs that would erase an ambiguous arena binding or
/// merge declarations formerly isolated by the arena's lexical block.
fn bindingsCertain(src: source.Source, syntax: ast.Program, statement: ast.Statement, body: ast.Statement) bool {
    const region = functionRegion(syntax, statement.span.start) orelse return false;
    if (statement.data.with_scope.name) |name| {
        if (parameterNamed(src, syntax, region, name) or lambdaNamed(src, syntax, region, name)) return false;
        for (syntax.statements.items) |other| {
            if (other.span.start == statement.span.start or !inside(other.span, region)) continue;
            if (bindsName(src, other, name)) return false;
            if (other.data == .assignment and sameName(src, other.data.assignment.name, name)) return false;
        }
        for (syntax.nodes.items) |node| {
            if (inside(node.span, region) and nodeBindsName(src, node, name)) return false;
        }
    }
    for (body.data.block) |id| {
        const lifted = syntax.statements.items[@backingInt(id)];
        if (lifted.data == .discard) {
            const expression = syntax.nodes.items[@backingInt(lifted.data.discard)];
            if (expression.data == .field_assignment and expression.data.field_assignment.declaration != null) return false;
        }
        const name = switch (lifted.data) {
            .binding => |binding| binding.name,
            .assignment => |assignment| if (knownMutable(src, syntax, statement.span.start, assignment.name)) continue else assignment.name,
            else => continue,
        };
        if (parameterNamed(src, syntax, region, name) or lambdaNamed(src, syntax, region, name)) return false;
        for (syntax.statements.items) |other| {
            if (other.span.start == lifted.span.start or !inside(other.span, region)) continue;
            if (bindsName(src, other, name)) return false;
            if (!inside(other.span, body.span) and other.data == .assignment and sameName(src, other.data.assignment.name, name)) return false;
        }
        for (syntax.nodes.items) |node| {
            if (!inside(node.span, region)) continue;
            if (nodeBindsName(src, node, name)) return false;
            // An explicit block-local binding gains visibility after dedent.
            // Legacy implicit assignments intentionally migrate their old scope.
            if (lifted.data == .binding and node.span.start >= body.span.end and termNamed(src, node, name)) return false;
        }
    }
    return true;
}

fn functionRegion(syntax: ast.Program, point: usize) ?source.Span {
    for (syntax.functions) |function| {
        const span = syntax.statements.items[@backingInt(function.body)].span;
        if (point >= span.start and point < span.end) return span;
    }
    return null;
}

fn inside(span: source.Span, region: source.Span) bool {
    return span.start >= region.start and span.end <= region.end;
}

fn sameName(src: source.Source, left: source.Span, right: source.Span) bool {
    return std.mem.eql(u8, src.text(left), src.text(right));
}

fn parameterNamed(src: source.Source, syntax: ast.Program, region: source.Span, name: source.Span) bool {
    for (syntax.functions) |function| {
        const body = syntax.statements.items[@backingInt(function.body)].span;
        if (body.start != region.start or body.end != region.end) continue;
        for (function.signature.parameters) |parameter| {
            if (sameName(src, parameter.name, name)) return true;
        }
    }
    return false;
}

fn bindsName(src: source.Source, statement: ast.Statement, name: source.Span) bool {
    return switch (statement.data) {
        .binding => |binding| sameName(src, binding.name, name),
        .for_each => |loop| sameName(src, loop.name, name) or (if (loop.index_name) |index| sameName(src, index, name) else false),
        .for_range => |loop| sameName(src, loop.name, name),
        .with_scope => |scope| if (scope.name) |binding| sameName(src, binding, name) else false,
        .match => |match| arms: {
            for (match.arms) |arm| {
                if (armNamed(src, arm, name)) break :arms true;
            }
            break :arms false;
        },
        else => false,
    };
}

fn nodeBindsName(src: source.Source, node: ast.Node, name: source.Span) bool {
    return switch (node.data) {
        .comprehension => |value| sameName(src, value.name, name),
        // Gather clauses and destructuring declarations carry lowered or
        // speculative spans. Withhold rather than infer their lexical binding.
        .gather => true,
        .field_assignment => |value| value.declaration != null,
        .match_expression => |match| arms: {
            for (match.arms) |arm| {
                if (armNamed(src, arm, name)) break :arms true;
            }
            break :arms false;
        },
        else => false,
    };
}

fn termNamed(src: source.Source, node: ast.Node, name: source.Span) bool {
    return switch (node.data) {
        .name => |term| sameName(src, term, name),
        .call => |call| sameName(src, call.owner orelse call.name, name),
        .buffer_operation => |operation| sameName(src, operation.owner, name),
        .file_operation => |operation| sameName(src, operation.owner, name),
        .resource_io => |operation| sameName(src, operation.owner, name),
        .arena_escape => |escape| sameName(src, escape.arena, name),
        .record => |record| sameName(src, record.name, name),
        else => false,
    };
}

fn armNamed(src: source.Source, arm: ast.MatchArm, name: source.Span) bool {
    for (arm.bindings) |binding| {
        if (binding) |span| if (sameName(src, span, name)) return true;
    }
    return patternsNamed(src, arm.payload_patterns, name);
}

fn lambdaNamed(src: source.Source, syntax: ast.Program, region: source.Span, name: source.Span) bool {
    for (syntax.lambdas) |lambda| {
        if (!inside(lambda.span, region)) continue;
        for (lambda.parameters) |parameter| {
            if (sameName(src, parameter, name)) return true;
        }
    }
    return false;
}

fn knownMutable(src: source.Source, syntax: ast.Program, point: usize, name: source.Span) bool {
    for (syntax.functions) |function| {
        const body = syntax.statements.items[@backingInt(function.body)].span;
        if (point < body.start or point >= body.end) continue;
        for (function.signature.parameters) |parameter| {
            if (parameter.mut and sameName(src, parameter.name, name)) return true;
        }
    }
    for (syntax.statements.items) |scope| {
        if (scope.data != .block or point < scope.span.start or point >= scope.span.end) continue;
        for (scope.data.block) |id| {
            const earlier = syntax.statements.items[@backingInt(id)];
            if (earlier.span.start >= point or earlier.data != .binding) continue;
            if (earlier.data.binding.mutable and sameName(src, earlier.data.binding.name, name)) return true;
        }
    }
    return false;
}

fn patternsNamed(src: source.Source, fields: []const ast.PatternField, name: source.Span) bool {
    for (fields) |field| switch (field.pattern.data) {
        .binding => |binding| if (binding) |span| {
            if (sameName(src, span, name)) return true;
        },
        .variant => |variant| if (patternsNamed(src, variant.fields, name)) return true,
    };
    return false;
}

/// One arena binding's name and the body it is visible in.
const Binding = struct { name: []const u8, region: source.Span };

/// Append the rewrite of every `name.escape(value)` call inside the arena's
/// body after binding checks establish that no declaration shadows its name.
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
