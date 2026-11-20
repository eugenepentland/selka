//! Certain statement replacements for retired control-flow expressions.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const support = @import("migration_support.zig");

/// Select the stable diagnostic code for the recognized retired AST form.
pub fn code(node: ast.Node) []const u8 {
    return if (node.data == .conditional) "E_CONDITIONAL_EXPRESSION_REMOVED" else "E_MATCH_EXPRESSION_REMOVED";
}
/// Manual guidance shared by certain repairs and withheld edits.
pub const message = "control-flow expressions were removed; use an if or match statement assigning a named result, or return in each arm";

/// Nested selections supply type facts until their owning retired expression
/// reports a repair or removal. Its rejection keeps representatives out of Core.
/// Lambdas and gathers must publish first so a later round sees ordinary statements.
pub fn nestedSelection(program: ast.Program, node: ast.Node) bool {
    for (program.lambdas) |lambda| {
        if (contains(lambda.span, node.span)) return true;
    }
    for (program.nodes.items) |parent| {
        switch (parent.data) {
            .conditional, .match_expression, .comprehension, .gather => {},
            else => continue,
        }
        if (parent.span.start <= node.span.start and parent.span.end >= node.span.end and
            (parent.span.start != node.span.start or parent.span.end != node.span.end)) return true;
    }
    return false;
}

/// A typed spelling is optional: return and assignment sites do not need one.
pub fn publish(src: source.Source, program: ast.Program, sink: *diagnostic.Sink, node: ast.Node, result_type: ?[]const u8) diagnostic.Error!bool {
    const edit = try replacement(sink.allocator, src, program, node, result_type) orelse return false;
    try sink.appendFix(.{ .code = code(node), .span = node.span, .message = message }, edit);
    return true;
}
/// Report a certain edit when available, and always stop normal compilation.
pub fn reject(src: source.Source, program: ast.Program, sink: *diagnostic.Sink, node: ast.Node, result_type: ?[]const u8) diagnostic.Error {
    if (try publish(src, program, sink, node, result_type)) return error.SourceError;
    return sink.fail(code(node), node.span, message);
}
fn replacement(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, node: ast.Node, result_type: ?[]const u8) !?diagnostic.Edit {
    for (program.statements.items) |statement| {
        var prefix: []const u8 = "";
        var declaration: []const u8 = "";
        const value: ast.NodeId = switch (statement.data) {
            .ret => |value| blk: {
                prefix = "return ";
                break :blk value;
            },
            .yield_value => |value| blk: {
                prefix = "yield ";
                break :blk value;
            },
            .discard => |value| blk: {
                prefix = "_ = ";
                break :blk value;
            },
            .assignment => |assignment| blk: {
                if (assignment.op != .set) continue;
                prefix = try std.fmt.allocPrint(allocator, "{s} = ", .{src.text(assignment.name)});
                break :blk assignment.value;
            },
            .binding => |binding| blk: {
                if (!binding.initialized) continue;
                const ty = if (binding.annotation) |annotation| src.text(annotation) else result_type orelse continue;
                declaration = try std.fmt.allocPrint(allocator, "mut {s}: {s}\n", .{ src.text(binding.name), ty });
                prefix = try std.fmt.allocPrint(allocator, "{s} = ", .{src.text(binding.name)});
                break :blk binding.value;
            },
            else => continue,
        };
        const expression = program.nodes.items[@backingInt(value)];
        if (expression.span.start != node.span.start or expression.span.end != node.span.end) continue;
        const indent = support.indentation(src, statement.span.start);
        var rendered: std.ArrayList(u8) = .empty;
        try rendered.appendSlice(allocator, declaration);
        try (Renderer{ .allocator = allocator, .src = src, .program = program }).render(&rendered, node, prefix, "");
        // Relative indentation becomes the enclosing statement's indentation.
        var output: std.ArrayList(u8) = .empty;
        for (rendered.items, 0..) |byte, i| {
            try output.append(allocator, byte);
            if (byte == '\n' and i + 1 < rendered.items.len) try output.appendSlice(allocator, indent);
        }
        var end = statement.span.end;
        while (end > statement.span.start and std.ascii.isWhitespace(src.bytes[end - 1])) : (end -= 1) {}
        return .{ .span = .{ .start = statement.span.start, .end = @intCast(end) }, .text = try output.toOwnedSlice(allocator) };
    }
    const ty = result_type orelse return null;
    const enclosing = support.enclosingStatement(program, node.span) orelse return null;
    for (program.statements.items) |statement| {
        if (statement.span.start != enclosing.start or statement.span.end != enclosing.end) continue;
        switch (statement.data) {
            .ret, .binding, .discard, .match => {},
            .assignment => |assignment| if (assignment.op != .set) {
                return null;
            },
            .branch => if (!std.mem.startsWith(u8, src.text(statement.span), "if ")) {
                return null;
            },
            else => return null,
        }
    }
    if (!hoistCertain(program, node.span)) return null;
    const name = support.freshOriginNameAt(allocator, src, "selection", node.span.start) catch return null;
    var block: std.ArrayList(u8) = .empty;
    try block.appendSlice(allocator, try std.fmt.allocPrint(allocator, "mut {s}: {s}\n", .{ name, ty }));
    try (Renderer{ .allocator = allocator, .src = src, .program = program }).render(&block, node, try std.fmt.allocPrint(allocator, "{s} = ", .{name}), "");
    const insertion = try support.insertBeforeStatement(allocator, src, enclosing, block.items) orelse return null;
    // One replacement keeps the insertion and expression substitution atomic.
    const text = try std.fmt.allocPrint(allocator, "{s}{s}{s}{s}", .{ insertion.text, src.bytes[insertion.span.start..node.span.start], name, src.bytes[node.span.end..enclosing.end] });
    return .{ .span = .{ .start = insertion.span.start, .end = enclosing.end }, .text = text };
}
fn contains(outer: source.Span, inner: source.Span) bool {
    return outer.start <= inner.start and outer.end >= inner.end;
}
fn beforeCertain(program: ast.Program, values: []const ast.NodeId, span: source.Span) bool {
    for (values) |value| {
        if (contains(program.nodes.items[@backingInt(value)].span, span)) return true;
        switch (program.nodes.items[@backingInt(value)].data) {
            .integer, .boolean, .unit, .text, .bytes => {},
            else => return false,
        }
    }
    return false;
}
fn stableLiteral(program: ast.Program, id: ast.NodeId) bool {
    return switch (program.nodes.items[@backingInt(id)].data) {
        .integer, .boolean, .unit, .text, .bytes => true,
        else => false,
    };
}
fn fieldsBeforeCertain(program: ast.Program, fields: []const ast.FieldInit, span: source.Span) bool {
    for (fields) |field| {
        if (contains(program.nodes.items[@backingInt(field.value)].span, span)) return true;
        if (!support.evaluationOrderCertain(program, &.{field.value})) return false;
    }
    return false;
}
fn hoistCertain(program: ast.Program, span: source.Span) bool {
    for (program.nodes.items) |parent| {
        if (!contains(parent.span, span) or (parent.span.start == span.start and parent.span.end == span.end)) continue;
        switch (parent.data) {
            .binary => |binary| {
                if (binary.chained) return false;
                if (contains(program.nodes.items[@backingInt(binary.right)].span, span)) {
                    if (binary.op == .logical_and or binary.op == .logical_or) return false;
                    if (!stableLiteral(program, binary.left)) return false;
                }
            },
            .call => |call| {
                // An explicit evaluation order can differ from declaration order.
                if (call.evaluation_order.len != 0) return false;
                if (!beforeCertain(program, call.arguments, span)) return false;
            },
            .record => |record| if (!fieldsBeforeCertain(program, record.fields, span)) return false,
            .format, .list_literal, .set_literal, .dictionary_literal, .tuple => |values| if (!beforeCertain(program, values, span)) return false,
            .unary, .cast, .wrap, .format_field, .propagate, .length, .unwrap => {},
            // Receiver reads, repeated/conditional evaluation and unknown forms need manual extraction.
            else => return false,
        }
    }
    return true;
}
fn yieldAt(spans: []const source.Span, position: usize) bool {
    for (spans) |span| if (position == span.start) return true;
    return false;
}
const Renderer = struct {
    allocator: std.mem.Allocator,
    src: source.Source,
    program: ast.Program,
    fn render(self: Renderer, output: *std.ArrayList(u8), node: ast.Node, prefix: []const u8, indent: []const u8) std.mem.Allocator.Error!void {
        const allocator = self.allocator;
        const src = self.src;
        const program = self.program;
        switch (node.data) {
            .conditional => |conditional| {
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "if {s}:\n{s}    ", .{ src.text(program.nodes.items[@backingInt(conditional.condition)].span), indent }));
                try self.renderValue(output, conditional.then_value, prefix, try std.fmt.allocPrint(allocator, "{s}    ", .{indent}));
                try output.appendSlice(allocator, try std.fmt.allocPrint(allocator, "\n{s}else:\n{s}    ", .{ indent, indent }));
                try self.renderValue(output, conditional.else_value, prefix, try std.fmt.allocPrint(allocator, "{s}    ", .{indent}));
            },
            .match_expression => try self.renderMatch(output, node, prefix, indent),
            else => unreachable,
        }
    }
    fn renderMatch(self: Renderer, output: *std.ArrayList(u8), node: ast.Node, prefix: []const u8, indent: []const u8) std.mem.Allocator.Error!void {
        const allocator = self.allocator;
        const src = self.src;
        const program = self.program;
        const match = node.data.match_expression;
        const base = support.indentation(src, node.span.start);
        const text = std.mem.trimEnd(u8, src.text(node.span), " \t\r\n");
        var yields: std.ArrayList(source.Span) = .empty;
        for (match.arms) |arm| try collectYields(allocator, program, arm.body, &yields);
        var position: usize = node.span.start;
        const end = node.span.start + text.len;
        while (position < end) {
            if (yieldAt(yields.items, position)) {
                try output.appendSlice(allocator, prefix);
                position += "yield".len;
                while (position < end and src.bytes[position] == ' ') : (position += 1) {}
                continue;
            }
            const byte = src.bytes[position];
            try output.append(allocator, byte);
            position += 1;
            if (byte == '\n') {
                if (std.mem.startsWith(u8, src.bytes[position..end], base)) position += base.len;
                try output.appendSlice(allocator, indent);
            }
        }
    }
    fn renderValue(self: Renderer, output: *std.ArrayList(u8), id: ast.NodeId, prefix: []const u8, indent: []const u8) std.mem.Allocator.Error!void {
        const allocator = self.allocator;
        const src = self.src;
        const program = self.program;
        const node = program.nodes.items[@backingInt(id)];
        if (node.data == .conditional or node.data == .match_expression) return self.render(output, node, prefix, indent);
        try output.appendSlice(allocator, prefix);
        try output.appendSlice(allocator, src.text(node.span));
    }
};
fn collectYields(allocator: std.mem.Allocator, program: ast.Program, id: ast.StatementId, output: *std.ArrayList(source.Span)) std.mem.Allocator.Error!void {
    const statement = program.statements.items[@backingInt(id)];
    if (statement.data == .yield_value) try output.append(allocator, statement.span);
    var nested: std.ArrayList(ast.StatementId) = .empty;
    defer nested.deinit(allocator);
    try ast.appendNested(allocator, &nested, statement);
    for (nested.items) |child| try collectYields(allocator, program, child, output);
}
