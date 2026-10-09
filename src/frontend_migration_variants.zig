//! Certain repairs for variant syntax, keyed by local nominal declarations.
//! No imported or unresolved declaration is guessed, and result identities survive.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const lex = @import("lexer.zig");
const diagnostic = @import("diagnostic.zig");
const Span = source.Span;

/// Publish certain enum declaration, constructor and pattern repairs.
pub fn publish(src: source.Source, program: ast.Program, tokens: []const lex.Token, sink: *diagnostic.Sink) diagnostic.Error!bool {
    var pass: Pass = .{ .src = src, .program = program, .tokens = tokens, .sink = sink };
    try pass.declarations();
    for (program.nodes.items) |node| try pass.constructor(node);
    for (program.statements.items) |statement| {
        if (statement.data == .match) try pass.arms(statement.data.match.value, statement.data.match.arms);
    }
    for (program.nodes.items) |node| {
        if (node.data == .match_expression) try pass.arms(node.data.match_expression.value, node.data.match_expression.arms);
    }
    return pass.changed;
}

const Pass = struct {
    src: source.Source,
    program: ast.Program,
    tokens: []const lex.Token,
    sink: *diagnostic.Sink,
    changed: bool = false,

    fn repair(self: *Pass, span: Span, text: []const u8, message: []const u8) diagnostic.Error!void {
        try self.sink.appendFix(.{ .code = "E_FRONTEND_VARIANT", .span = span, .message = message }, .{ .span = span, .text = text });
        self.changed = true;
    }

    fn nominal(self: *const Pass, span: Span) ?ast.Variants {
        const text = self.src.text(span);
        const end = std.mem.indexOfScalar(u8, text, '[') orelse text.len;
        const base = std.mem.trim(u8, text[0..end], " \t\r\n");
        for (self.program.types.variants) |variant| {
            if (std.mem.eql(u8, base, self.src.text(variant.name))) return variant;
        }
        return null;
    }

    fn caseOf(self: *const Pass, variant: ast.Variants, name: Span) ?ast.Variant {
        for (variant.cases) |case| {
            if (std.mem.eql(u8, self.src.text(case.name), self.src.text(name))) return case;
        }
        return null;
    }

    fn declarations(self: *Pass) diagnostic.Error!void {
        for (self.program.types.variants) |variant| {
            if (variant.fallible) continue;
            for (self.tokens, 0..) |token, index| {
                if (token.tag != .kw_union or index + 1 >= self.tokens.len) continue;
                if (self.tokens[index + 1].span.start == variant.name.start) try self.repair(token.span, "enum", "declare all non-result variants with `enum`");
            }
            for (variant.cases, 0..) |case, index| {
                if (case.payload) |payload| {
                    const rendered = try @import("frontend_migration_types.zig").renderType(self.sink.allocator, self.src, self.program.types.expressions, payload);
                    const replacement = try std.fmt.allocPrint(self.sink.allocator, "(value: {s})", .{rendered});
                    try self.repair(.{ .start = case.name.end, .end = payload.end }, replacement, "declare a variant payload as a named field");
                }
                const end = if (index + 1 < variant.cases.len) variant.cases[index + 1].name.start else self.declarationEnd(variant.name);
                try self.caseCommas(case.name.end, end, self.caseIndent(variant));
            }
        }
    }

    fn declarationEnd(self: *const Pass, name: Span) usize {
        for (self.tokens, 0..) |token, index| {
            if (token.span.start == name.start) return self.tokens[lex.declarationEnd(self.src.bytes, self.tokens, index, null)].span.start;
        }
        return self.src.bytes.len;
    }

    fn caseIndent(self: *const Pass, variant: ast.Variants) []const u8 {
        if (variant.cases.len == 0) return "    ";
        const start = variant.cases[0].name.start;
        const line = lineStart(self.src.bytes, start);
        return self.src.bytes[line..start];
    }

    fn caseCommas(self: *Pass, start: usize, end: usize, indent: []const u8) diagnostic.Error!void {
        var depth: usize = 0;
        for (self.tokens, 0..) |token, index| {
            if (token.span.start < start or token.span.start >= end) continue;
            switch (token.tag) {
                .lparen, .lbracket, .lbrace => depth += 1,
                .rparen, .rbracket, .rbrace => depth -|= 1,
                .comma => if (depth == 0) {
                    const next = self.tokens[index + 1];
                    const gap = self.src.bytes[token.span.end..next.span.start];
                    if (next.span.start == end and std.mem.indexOfScalar(u8, gap, '\n') == null and next.tag == .ident) {
                        const replacement = try std.fmt.allocPrint(self.sink.allocator, "\n{s}", .{indent});
                        try self.repair(.{ .start = token.span.start, .end = next.span.start }, replacement, "put each enum case on its own line");
                    } else try self.repair(token.span, "", "enum cases end at newlines");
                },
                else => {},
            }
        }
    }

    fn constructor(self: *Pass, node: ast.Node) diagnostic.Error!void {
        switch (node.data) {
            .call => |call| {
                const owner = call.owner orelse self.expectedType(node.span) orelse return;
                if (call.owner != null and self.shadowed(owner, node.span.start)) return;
                const variant = self.nominal(owner) orelse return;
                if (variant.fallible) return;
                const case = self.caseOf(variant, call.name) orelse return;
                try self.arguments(case, call.arguments, call.argument_names);
            },
            .method_call => |call| {
                const base = self.program.nodes.items[@backingInt(call.base)];
                if (base.data != .name or self.shadowed(base.data.name, node.span.start)) return;
                const variant = self.nominal(base.data.name) orelse return;
                if (variant.fallible) return;
                const case = self.caseOf(variant, call.name) orelse return;
                try self.arguments(case, call.arguments, call.argument_names);
            },
            .variant => |value| {
                const variant = self.nominal(value.ty) orelse return;
                if (variant.fallible) return;
                const case = self.caseOf(variant, value.name) orelse return;
                if (value.value) |payload| try self.arguments(case, &.{payload}, &.{});
                try self.arguments(case, value.values, value.value_names);
            },
            else => {},
        }
    }

    fn arguments(self: *Pass, case: ast.Variant, values: []const ast.NodeId, names: []const ?Span) diagnostic.Error!void {
        for (values, 0..) |value, index| {
            if (index < names.len and names[index] != null) continue;
            const label = self.fieldName(case, index) orelse continue;
            const span = self.program.nodes.items[@backingInt(value)].span;
            const text = try std.fmt.allocPrint(self.sink.allocator, "{s}=", .{label});
            try self.repair(.{ .start = span.start, .end = span.start }, text, "name the enum payload field at its construction");
        }
    }

    fn fieldName(self: *const Pass, case: ast.Variant, index: usize) ?[]const u8 {
        if (case.payload != null) return if (index == 0) "value" else null;
        if (index >= case.fields.len) return null;
        return self.src.text(case.fields[index].name);
    }

    fn arms(self: *Pass, value: ast.NodeId, cases: []const ast.MatchArm) diagnostic.Error!void {
        const expected = self.valueType(value, self.program.nodes.items[@backingInt(value)].span.start, 0);
        for (cases) |arm| {
            for (arm.payload_patterns) |field| try self.nestedPattern(field.pattern);
            const owner = if (arm.ty.start != arm.ty.end) arm.ty else expected orelse continue;
            const variant = self.nominal(owner) orelse continue;
            const case = self.caseOf(variant, arm.name) orelse continue;
            if (!variant.fallible) try self.patternFields(case, arm.payload_patterns);
        }
    }

    fn nestedPattern(self: *Pass, pattern: ast.Pattern) diagnostic.Error!void {
        if (pattern.data != .variant) return;
        const value = pattern.data.variant;
        const variant = self.nominal(value.ty) orelse return;
        const case = self.caseOf(variant, value.name) orelse return;
        if (!variant.fallible) try self.patternFields(case, value.fields);
        for (value.fields) |field| try self.nestedPattern(field.pattern);
    }

    fn patternFields(self: *Pass, case: ast.Variant, fields: []const ast.PatternField) diagnostic.Error!void {
        for (fields, 0..) |field, index| {
            if (field.name != null) continue;
            const label = self.fieldName(case, index) orelse continue;
            const text = try std.fmt.allocPrint(self.sink.allocator, "{s}=", .{label});
            try self.repair(.{ .start = field.pattern.span.start, .end = field.pattern.span.start }, text, "name the enum field bound by this pattern");
        }
    }

    fn expectedType(self: *const Pass, span: Span) ?Span {
        for (self.program.statements.items) |statement| switch (statement.data) {
            .binding => |binding| if (self.sameValue(binding.value, span)) return binding.annotation,
            .ret => |value| if (self.sameValue(value, span)) return (self.functionAt(span.start) orelse return null).signature.return_type,
            else => {},
        };
        return null;
    }

    fn sameValue(self: *const Pass, id: ast.NodeId, span: Span) bool {
        const other = self.program.nodes.items[@backingInt(id)].span;
        return other.start == span.start and other.end == span.end;
    }

    fn functionAt(self: *const Pass, point: usize) ?ast.Function {
        for (self.program.functions) |function| {
            const body = self.program.statements.items[@backingInt(function.body)].span;
            if (point >= body.start and point < body.end) return function;
        }
        return null;
    }

    fn shadowed(self: *const Pass, name: Span, point: usize) bool {
        return self.localType(name, point, true) != null;
    }

    fn localType(self: *const Pass, name: Span, point: usize, presence: bool) ?Span {
        const function = self.functionAt(point) orelse return null;
        for (function.signature.parameters) |parameter| {
            if (std.mem.eql(u8, self.src.text(parameter.name), self.src.text(name))) return parameter.ty;
        }
        for (self.program.statements.items) |statement| {
            if (statement.span.start >= point or statement.span.start < function.name.start) continue;
            if (statement.data == .assignment) {
                const assignment = statement.data.assignment;
                if (std.mem.eql(u8, self.src.text(assignment.name), self.src.text(name)) and self.visible(statement.span.start, point)) {
                    if (presence) return assignment.name;
                    return self.valueType(assignment.value, statement.span.start, 1);
                }
            }
            if (statement.data != .binding) continue;
            const binding = statement.data.binding;
            if (!std.mem.eql(u8, self.src.text(binding.name), self.src.text(name)) or !self.visible(statement.span.start, point)) continue;
            if (presence) return binding.name;
            if (binding.annotation) |annotation| return annotation;
            return self.valueType(binding.value, statement.span.start, 1);
        }
        return null;
    }

    fn visible(self: *const Pass, declaration: usize, use: usize) bool {
        var enclosing: ?Span = null;
        for (self.program.statements.items) |statement| {
            if (statement.data != .block or declaration < statement.span.start or declaration >= statement.span.end) continue;
            if (enclosing == null or statement.span.end - statement.span.start < enclosing.?.end - enclosing.?.start) enclosing = statement.span;
        }
        const block = enclosing orelse return false;
        return use >= block.start and use < block.end;
    }

    fn valueType(self: *const Pass, id: ast.NodeId, point: usize, depth: usize) ?Span {
        if (depth > 32) return null;
        const node = self.program.nodes.items[@backingInt(id)];
        return switch (node.data) {
            .name => |name| self.localType(name, point, false),
            .propagate => |value| self.valueType(value, point, depth + 1),
            .call => |call| self.callType(call),
            .variant => |variant| variant.ty,
            else => null,
        };
    }

    fn callType(self: *const Pass, call: @FieldType(@FieldType(ast.Node, "data"), "call")) ?Span {
        if (call.owner) |owner| if (self.nominal(owner) != null) return owner;
        for (self.program.functions) |function| {
            if (call.owner == null and std.mem.eql(u8, self.src.text(function.name), self.src.text(call.name))) return function.signature.return_type;
        }
        return null;
    }
};

fn lineStart(bytes: []const u8, point: usize) usize {
    return if (std.mem.lastIndexOfScalar(u8, bytes[0..point], '\n')) |at| at + 1 else 0;
}
