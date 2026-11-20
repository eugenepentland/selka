//! Conservative source edits shared by language migrations.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");
const diagnostic = @import("diagnostic.zig");

/// Choose a name absent as an identifier anywhere in the source, including comments.
/// The caller reserves generated names by passing them in `reserved` on later calls.
pub fn freshName(allocator: std.mem.Allocator, src: source.Source, stem: []const u8) std.mem.Allocator.Error![]const u8 {
    return freshNameReserved(allocator, src, stem, &.{});
}
/// Choose a source-wide fresh name whose offset distinguishes independent diagnostics.
/// Use a consistent stem and distinct source offsets; same-offset names need reservations.
pub fn freshNameAt(allocator: std.mem.Allocator, src: source.Source, stem: []const u8, offset: usize) std.mem.Allocator.Error![]const u8 {
    const located = try std.fmt.allocPrint(allocator, "{s}_{d}", .{ stem, offset });
    defer allocator.free(located);
    return freshName(allocator, src, located);
}
/// Choose a name from the original module's bytes and module-local offset.
/// Combined-source prefixes and other modules never affect this diagnostic's name.
/// Offsets outside an original module span return InvalidSourceSpan.
pub fn freshOriginNameAt(allocator: std.mem.Allocator, src: source.Source, stem: []const u8, offset: usize) error{ OutOfMemory, InvalidSourceSpan }![]const u8 {
    if (offset > src.bytes.len) return error.InvalidSourceSpan;
    if (src.origins.len == 0) return freshNameAt(allocator, src, stem, offset);
    const original = src.originalSpan(.{ .start = offset, .end = offset }) catch return error.InvalidSourceSpan;
    return freshNameAt(allocator, src.origins[original.input].original, stem, original.span.start);
}
/// Choose a source-wide fresh identifier, also avoiding earlier generated names.
pub fn freshNameReserved(allocator: std.mem.Allocator, src: source.Source, stem: []const u8, reserved: []const []const u8) std.mem.Allocator.Error![]const u8 {
    var suffix: usize = 0;
    while (true) : (suffix += 1) {
        const candidate = if (suffix == 0) try allocator.dupe(u8, stem) else try std.fmt.allocPrint(allocator, "{s}_{d}", .{ stem, suffix });
        if (!identifierPresent(src.bytes, candidate) and !reservedName(reserved, candidate)) return candidate;
        allocator.free(candidate);
    }
}
fn reservedName(reserved: []const []const u8, candidate: []const u8) bool {
    for (reserved) |name| if (std.mem.eql(u8, name, candidate)) return true;
    return false;
}
fn identifierByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}
fn identifierPresent(bytes: []const u8, name: []const u8) bool {
    var position: usize = 0;
    while (std.mem.indexOfPos(u8, bytes, position, name)) |start| {
        const end = start + name.len;
        const starts_identifier = start == 0 or !identifierByte(bytes[start - 1]);
        const ends_identifier = end == bytes.len or !identifierByte(bytes[end]);
        if (starts_identifier and ends_identifier) return true;
        position = start + 1;
    }
    return false;
}
fn lineStart(bytes: []const u8, offset: usize) usize {
    const end = @min(offset, bytes.len);
    return if (std.mem.lastIndexOfScalar(u8, bytes[0..end], '\n')) |previous| previous + 1 else 0;
}
/// Borrow the enclosing line's leading spaces or tabs, preserving its spelling.
pub fn indentation(src: source.Source, offset: usize) []const u8 {
    const start = lineStart(src.bytes, offset);
    var end = start;
    while (end < src.bytes.len and (src.bytes[end] == ' ' or src.bytes[end] == '\t')) : (end += 1) {}
    return src.bytes[start..end];
}
fn oneOrigin(src: source.Source, span: source.Span) bool {
    for (src.origins) |origin| if (origin.start > span.start and origin.start < span.end) return false;
    return true;
}
/// Locate the smallest non-block statement containing an expression's range.
/// Callers must separately reject repeated loop conditions and conditional operands.
pub fn enclosingStatement(syntax: ast.Program, expression: source.Span) ?source.Span {
    var result: ?source.Span = null;
    for (syntax.statements.items) |statement| {
        if (statement.data == .block or statement.span.start > expression.start or statement.span.end < expression.end) continue;
        if (result == null or statement.span.end - statement.span.start < result.?.end - result.?.start) result = statement.span;
    }
    return result;
}
/// Indent a relative multiline statement before a standalone enclosing statement.
/// Preserve existing leading comments and refuse a merged-source boundary or inline start.
/// The returned edit's text belongs to the allocator; null means no certain insertion.
pub fn insertBeforeStatement(allocator: std.mem.Allocator, src: source.Source, statement: source.Span, text: []const u8) std.mem.Allocator.Error!?diagnostic.Edit {
    if (statement.start > statement.end or statement.end > src.bytes.len) return null;
    const start = lineStart(src.bytes, statement.start);
    const indent = indentation(src, statement.start);
    if (start + indent.len != statement.start or !oneOrigin(src, .{ .start = start, .end = statement.end })) return null;
    const newline = std.mem.indexOfScalarPos(u8, src.bytes, start, '\n');
    const crlf = if (newline) |end| end > start and src.bytes[end - 1] == '\r' else false;
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    var lines = std.mem.splitScalar(u8, text, '\n');
    var remaining = text.len;
    while (lines.next()) |line| {
        if (remaining == 0) break;
        try output.appendSlice(allocator, indent);
        try output.appendSlice(allocator, line);
        try output.appendSlice(allocator, if (crlf) "\r\n" else "\n");
        remaining -= line.len;
        if (remaining > 0) remaining -= 1;
    }
    return .{ .span = .{ .start = start, .end = start }, .text = try output.toOwnedSlice(allocator) };
}
/// Hoist relative statement text before the smallest enclosing source statement.
/// Evaluation-order certainty remains the caller's explicit responsibility.
pub fn hoistBeforeStatement(allocator: std.mem.Allocator, src: source.Source, syntax: ast.Program, expression: source.Span, text: []const u8) std.mem.Allocator.Error!?diagnostic.Edit {
    return insertBeforeStatement(allocator, src, enclosingStatement(syntax, expression) orelse return null, text);
}
/// Recognize syntactically simple operands under a checked local-name assumption.
/// Callers must establish that names resolve to active locals, not constant getters.
/// Prefer isPureTypedOperand when checked operands are available.
pub fn isPureOperand(syntax: ast.Program, id: ast.NodeId) bool {
    return pureOperand(syntax, id, 0);
}
fn pureOperand(syntax: ast.Program, id: ast.NodeId, depth: usize) bool {
    if (depth >= 128 or @backingInt(id) >= syntax.nodes.items.len) return false;
    return switch (syntax.nodes.items[@backingInt(id)].data) {
        .integer, .boolean, .name, .synthetic_name, .unit => true,
        .field => |field| pureOperand(syntax, field.base, depth + 1),
        .unary => |unary| unary.op == .not and pureOperand(syntax, unary.operand, depth + 1),
        else => false,
    };
}
/// A hoist may cross only stable literal operands without dependency analysis.
/// Pure name/field reads can change when the moved expression mutates their locals.
/// This does not authorize hoisting out of a loop or a short-circuit branch.
pub fn evaluationOrderCertain(syntax: ast.Program, preceding: []const ast.NodeId) bool {
    for (preceding) |operand| {
        if (@backingInt(operand) >= syntax.nodes.items.len) return false;
        switch (syntax.nodes.items[@backingInt(operand)].data) {
            .integer, .boolean, .unit => {},
            else => return false,
        }
    }
    return true;
}
/// Recognize checked operands safe to duplicate without evaluating calls or traps.
/// Resolved local reads differ from allocating getters, which are typed calls.
/// This does not authorize delaying local reads across another expression's writes.
pub fn isPureTypedOperand(nodes: []const typed.Node, id: typed.NodeId) bool {
    return pureTypedOperand(nodes, id, 0);
}
fn pureTypedOperand(nodes: []const typed.Node, id: typed.NodeId, depth: usize) bool {
    if (depth >= 128 or @backingInt(id) >= nodes.len) return false;
    return switch (nodes[@backingInt(id)].data) {
        .integer, .boolean, .unit, .local, .function_value, .blob => true,
        .field => |field| pureTypedOperand(nodes, field.base, depth + 1),
        .unary => |unary| unary.op == .not and pureTypedOperand(nodes, unary.operand, depth + 1),
        else => false,
    };
}

/// Spell original-module type names without changing external qualified tokens.
/// Prefix discovery belongs to the caller; an empty prefix borrows rendered text.
pub fn localTypeText(allocator: std.mem.Allocator, rendered: []const u8, prefix: []const u8) std.mem.Allocator.Error![]const u8 {
    if (prefix.len == 0) return rendered;
    var output: std.ArrayList(u8) = .empty;
    var position: usize = 0;
    while (position < rendered.len) {
        const boundary = position == 0 or (!identifierByte(rendered[position - 1]) and rendered[position - 1] != '.');
        if (boundary and std.mem.startsWith(u8, rendered[position..], prefix)) {
            position += prefix.len;
        } else {
            try output.append(allocator, rendered[position]);
            position += 1;
        }
    }
    return output.toOwnedSlice(allocator);
}
