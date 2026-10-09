//! Structured repairs for the readable frontend. Repairs use parsed type and
//! expression spans, so words in comments, strings and ordinary names survive.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const lex = @import("lexer.zig");
const Span = source.Span;

/// Publish certain surface repairs for a parsed legacy source. The caller
/// decides whether a finding rejects a normal check or previews a migration.
pub fn publish(src: source.Source, program: ast.Program, tokens: []const lex.Token, sink: *diagnostic.Sink) diagnostic.Error!bool {
    var pass: Pass = .{ .src = src, .program = program, .tokens = tokens, .sink = sink };
    defer pass.covered.deinit(sink.allocator);
    pass.changed = try @import("frontend_binding_migration.zig").publish(src, program, sink);
    if (tokens.len > 0 and std.mem.eql(u8, src.text(tokens[0].span), "module")) {
        const end = if (std.mem.indexOfScalarPos(u8, src.bytes, tokens[0].span.end, '\n')) |newline| newline + 1 else src.bytes.len;
        const span: Span = .{ .start = tokens[0].span.start, .end = @intCast(end) };
        try sink.appendFix(.{ .code = "E_MODULE_HEADER", .span = span, .message = "module identity comes from its file path; remove the module header" }, .{ .span = span, .text = "" });
        pass.changed = true;
    }
    if (try @import("frontend_migration_variants.zig").publish(src, program, tokens, sink)) pass.changed = true;
    if (try @import("frontend_migration_expressions.zig").publish(src, program, tokens, sink)) pass.changed = true;
    for (tokens) |token| {
        if (token.tag == .kw_def and std.mem.eql(u8, src.text(token.span), "def")) {
            try pass.repair(token.span, "declare a function or callable type with 'func'", .{ .span = token.span, .text = "func" });
        }
    }
    try pass.types();
    for (program.functions) |function| try pass.parameters(function.signature);
    for (program.statements.items) |statement| switch (statement.data) {
        .binding => |binding| {
            const head = std.mem.trimStart(u8, src.bytes[statement.span.start..binding.name.start], " \t");
            if (head.len == 0) try pass.repair(binding.name, "declare a writable local with 'mut'", .{ .span = .{ .start = binding.name.start, .end = binding.name.start }, .text = "mut " });
        },
        else => {},
    };
    for (program.nodes.items, 0..) |node, index| switch (node.data) {
        .propagate => |value| {
            const operand = program.nodes.items[@backingInt(value)].span;
            if (node.span.end > operand.end and src.bytes[node.span.end - 1] == '?') {
                if (!pass.boundary(@fromBackingInt(index))) {
                    try sink.items.append(sink.allocator, .{
                        .code = "E_TRY_POSITION",
                        .span = node.span,
                        .message = "extract this fallible operation into a declaration using 'try' before the enclosing expression",
                    });
                    pass.changed = true;
                    continue;
                }
                try pass.repair(node.span, "propagate failure with prefix 'try'", .{ .span = node.span, .text = try std.fmt.allocPrint(sink.allocator, "try {s}", .{src.text(operand)}) });
            }
        },
        .conditional => |conditional| {
            if (pass.canonicalConditional(node.span)) continue;
            const condition = src.text(program.nodes.items[@backingInt(conditional.condition)].span);
            const yes = src.text(program.nodes.items[@backingInt(conditional.then_value)].span);
            const no = src.text(program.nodes.items[@backingInt(conditional.else_value)].span);
            const replacement = try std.fmt.allocPrint(sink.allocator, "(if ({s}) then ({s}) else ({s}))", .{ condition, yes, no });
            try pass.repair(node.span, "write a conditional in reading order: 'if condition then value else value'", .{ .span = node.span, .text = replacement });
        },
        else => {},
    };
    // Unwrap retired arena blocks before deciding which legacy locals need a
    // lexical-scope rewrite. Their certain edits can accompany syntax repairs.
    if (pass.changed) try @import("arena_fix.zig").reject(sink.allocator, src, program, sink);
    return pass.changed;
}

const Pass = struct {
    src: source.Source,
    program: ast.Program,
    tokens: []const lex.Token,
    sink: *diagnostic.Sink,
    covered: std.ArrayList(Span) = .empty,
    changed: bool = false,

    fn canonicalConditional(self: *const Pass, span: Span) bool {
        // Interpolation expressions live inside a single outer string token.
        const text = std.mem.trimStart(u8, self.src.text(span), "( \t\r\n");
        if (!std.mem.startsWith(u8, text, "if")) return false;
        return text.len == 2 or !(std.ascii.isAlphanumeric(text[2]) or text[2] == '_');
    }

    fn boundary(self: *const Pass, id: ast.NodeId) bool {
        for (self.program.statements.items) |statement| {
            const value: ?ast.NodeId = switch (statement.data) {
                .binding => |binding| binding.value,
                .assignment => |assignment| assignment.value,
                .ret, .discard => |value| value,
                .with_scope => |scope| scope.resource,
                else => null,
            };
            if (value == id) return true;
        }
        return false;
    }

    fn repair(self: *Pass, at: Span, message: []const u8, edit: diagnostic.Edit) diagnostic.Error!void {
        try self.sink.appendFix(.{ .code = "E_FRONTEND_SYNTAX", .span = at, .message = message }, edit);
        self.changed = true;
    }

    fn types(self: *Pass) diagnostic.Error!void {
        var spans: std.ArrayList(Span) = .empty;
        defer spans.deinit(self.sink.allocator);
        const expressions = self.program.types.expressions;
        // Variant payload repairs already replace and canonicalize their whole type.
        // A nested repair would overlap that edit and invalidate its source offsets.
        for (self.program.types.variants) |variant| {
            if (variant.fallible) continue;
            for (variant.cases) |case| {
                if (case.payload) |payload| try self.covered.append(self.sink.allocator, payload);
            }
        }
        for (expressions.applications) |application| try spans.append(self.sink.allocator, application.span);
        for (expressions.arrays) |array| try spans.append(self.sink.allocator, array.span);
        for (expressions.suffixes) |suffix| try spans.append(self.sink.allocator, suffix.span);
        for (expressions.aliases) |alias| try spans.append(self.sink.allocator, alias.target);
        for (expressions.callbacks) |callback| {
            try spans.appendSlice(self.sink.allocator, callback.parameters);
            try spans.append(self.sink.allocator, callback.return_type);
        }
        for (self.program.functions) |function| {
            for (function.signature.parameters) |parameter| try spans.append(self.sink.allocator, parameter.ty);
            try spans.append(self.sink.allocator, function.signature.return_type);
        }
        for (self.program.types.records) |record| for (record.fields) |field| {
            try spans.append(self.sink.allocator, field.ty);
        };
        for (self.program.statements.items) |statement| switch (statement.data) {
            .binding => |binding| if (binding.annotation) |annotation| {
                try spans.append(self.sink.allocator, annotation);
            },
            else => {},
        };
        std.mem.sort(Span, spans.items, {}, largerFirst);
        for (spans.items) |span| {
            if (self.alreadyCovered(span)) continue;
            const text = try renderType(self.sink.allocator, self.src, expressions, span);
            if (std.mem.eql(u8, text, self.src.text(span))) continue;
            try self.repair(span, "use the canonical array, optional or Unit type spelling", .{ .span = span, .text = text });
            try self.covered.append(self.sink.allocator, span);
        }
    }

    fn alreadyCovered(self: *const Pass, span: Span) bool {
        for (self.covered.items) |outer| {
            if (outer.start <= span.start and outer.end >= span.end) return true;
        }
        return false;
    }

    fn parameters(self: *Pass, signature: ast.FunctionSignature) diagnostic.Error!void {
        for (signature.parameters, 0..) |parameter, index| {
            const old_mut = parameter.mut and std.mem.indexOf(u8, self.src.bytes[parameter.name.end..parameter.ty.start], "mut") != null;
            const named = signature.keyword_only_from != null and index >= signature.keyword_only_from.? and !parameter.named;
            if (!old_mut and !named) continue;
            const replacement = try std.fmt.allocPrint(self.sink.allocator, "{s}{s}{s}: ", .{
                if (named) "named " else "",
                if (old_mut) "mut " else "",
                self.src.text(parameter.name),
            });
            try self.repair(parameter.name, "put 'named' and 'mut' before each parameter name", .{
                .span = .{ .start = parameter.name.start, .end = parameter.ty.start },
                .text = replacement,
            });
        }
        if (signature.keyword_only_from) |first| {
            if (first >= signature.parameters.len or signature.parameters[first].named) return;
            const end = signature.parameters[first].name.start;
            const start = if (first == 0) end -| 8 else signature.parameters[first - 1].ty.end;
            for (self.tokens, 0..) |token, index| {
                if (token.tag != .star or token.span.start < start or token.span.end > end) continue;
                if (index + 1 >= self.tokens.len or self.tokens[index + 1].tag != .comma) continue;
                var close = self.tokens[index + 1].span.end;
                while (close < end and (self.src.bytes[close] == ' ' or self.src.bytes[close] == '\t')) close += 1;
                try self.repair(token.span, "replace the '*' separator with individual 'named' parameters", .{ .span = .{ .start = token.span.start, .end = close }, .text = "" });
            }
        }
    }
};

fn largerFirst(_: void, left: Span, right: Span) bool {
    return left.end - left.start > right.end - right.start;
}

/// Render one parsed type with canonical collection suffixes, preserving identity.
pub const renderType = @import("frontend_migration_types.zig").renderType;
