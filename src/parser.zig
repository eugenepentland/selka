//! Recursive descent for statements; precedence climbing for expressions.
const std = @import("std");
const ast = @import("ast.zig");
const lex = @import("lexer.zig");
const Span = @import("source.zig").Span;
const diagnostic = @import("diagnostic.zig");
pub const Parser = struct {
    allocator: std.mem.Allocator,
    tokens: []const lex.Token,
    sink: *diagnostic.Sink,
    pos: usize = 0,
    nodes: std.ArrayList(ast.Node) = .empty,
    statements: std.ArrayList(ast.Statement) = .empty,
    depth: usize = 0,
    fn current(self: *Parser) lex.Token {
        return self.tokens[self.pos];
    }
    fn take(self: *Parser, tag: lex.Tag) bool {
        if (self.current().tag != tag) return false;
        self.pos += 1;
        return true;
    }
    fn expect(self: *Parser, comptime tag: lex.Tag) diagnostic.Error!lex.Token {
        const token = self.current();
        if (!self.take(tag)) return self.sink.fail("E_SYNTAX", token.span, "unexpected token; expected " ++ @tagName(tag));
        return token;
    }
    fn enter(self: *Parser) diagnostic.Error!void {
        if (self.depth >= 256) return self.sink.fail("E_NESTING_LIMIT", self.current().span, "parser nesting exceeds 256 levels");
        self.depth += 1;
    }
    fn typeName(self: *Parser) diagnostic.Error!Span {
        const token = self.current();
        if (self.take(.kw_i64) or self.take(.kw_bool)) return token.span;
        return self.sink.fail("E_TYPE", token.span, "expected i64 or bool");
    }
    pub fn parse(self: *Parser) diagnostic.Error!ast.Program {
        var functions: std.ArrayList(ast.Function) = .empty;
        while (self.current().tag != .eof) {
            _ = try self.expect(.kw_fn);
            const name = try self.expect(.ident);
            _ = try self.expect(.lparen);
            var parameters: std.ArrayList(ast.Parameter) = .empty;
            if (self.current().tag != .rparen) while (true) {
                const parameter = try self.expect(.ident);
                _ = try self.expect(.colon);
                try parameters.append(self.allocator, .{ .name = parameter.span, .ty = try self.typeName() });
                if (!self.take(.comma)) break;
            };
            _ = try self.expect(.rparen);
            _ = try self.expect(.arrow);
            const return_type = try self.typeName();
            const body = try self.block();
            try functions.append(self.allocator, .{ .name = name.span, .parameters = try parameters.toOwnedSlice(self.allocator), .return_type = return_type, .body = body });
        }
        return .{ .nodes = self.nodes, .statements = self.statements, .functions = try functions.toOwnedSlice(self.allocator) };
    }
    fn addStatement(self: *Parser, stmt: ast.Statement) diagnostic.Error!ast.StatementId {
        const id: ast.StatementId = @fromBackingInt(self.statements.items.len);
        try self.statements.append(self.allocator, stmt);
        return id;
    }
    fn block(self: *Parser) diagnostic.Error!ast.StatementId {
        try self.enter();
        defer self.depth -= 1;
        const open = try self.expect(.lbrace);
        var statements: std.ArrayList(ast.StatementId) = .empty;
        while (self.current().tag != .rbrace) {
            if (self.current().tag == .eof) return self.sink.fail("E_SYNTAX", self.current().span, "expected closing brace");
            try statements.append(self.allocator, try self.statement());
        }
        const close = try self.expect(.rbrace);
        return self.addStatement(.{ .span = .join(open.span, close.span), .data = .{ .block = try statements.toOwnedSlice(self.allocator) } });
    }
    fn statement(self: *Parser) diagnostic.Error!ast.StatementId {
        try self.enter();
        defer self.depth -= 1;
        const first = self.current();
        if (first.tag == .lbrace) return self.block();
        if (self.take(.kw_if)) {
            const condition = try self.expression(0);
            const then_body = try self.block();
            const else_body = if (self.take(.kw_else))
                if (self.current().tag == .kw_if) try self.statement() else try self.block()
            else
                null;
            const last = else_body orelse then_body;
            return self.addStatement(.{ .span = .join(first.span, self.statements.items[@backingInt(last)].span), .data = .{ .branch = .{
                .condition = condition,
                .then_body = then_body,
                .else_body = else_body,
            } } });
        }
        if (self.take(.kw_while)) {
            const condition = try self.expression(0);
            const body = try self.block();
            return self.addStatement(.{ .span = .join(first.span, self.statements.items[@backingInt(body)].span), .data = .{ .loop = .{ .condition = condition, .body = body } } });
        }
        const data: @FieldType(ast.Statement, "data") = switch (first.tag) {
            .kw_discard => discard: {
                self.pos += 1;
                break :discard .{ .discard = try self.expression(0) };
            },
            .kw_return => ret: {
                self.pos += 1;
                break :ret .{ .ret = try self.expression(0) };
            },
            .kw_let => binding: {
                self.pos += 1;
                const mutable = self.take(.kw_mut);
                const name = try self.expect(.ident);
                const annotation = if (self.take(.colon)) try self.typeName() else null;
                _ = try self.expect(.equal);
                break :binding .{ .binding = .{ .name = name.span, .mutable = mutable, .annotation = annotation, .value = try self.expression(0) } };
            },
            .ident => assignment: {
                const operator = self.tokens[self.pos + 1];
                const op: ast.AssignmentOp = switch (operator.tag) {
                    .equal => .set,
                    .plus_equal => .add,
                    .minus_equal => .sub,
                    else => return self.sink.fail("E_EXPLICIT_DISCARD_REQUIRED", first.span, "a standalone value requires explicit discard"),
                };
                self.pos += 2;
                break :assignment .{ .assignment = .{ .name = first.span, .value = try self.expression(0), .op = op, .op_span = operator.span } };
            },
            else => return self.sink.fail("E_EXPLICIT_DISCARD_REQUIRED", first.span, "expected a statement; a standalone value requires explicit discard"),
        };
        const end = try self.expect(.semicolon);
        return self.addStatement(.{ .span = .join(first.span, end.span), .data = data });
    }
    fn append(self: *Parser, node: ast.Node) diagnostic.Error!ast.NodeId {
        const id: ast.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, node);
        return id;
    }
    fn expression(self: *Parser, min_precedence: u8) diagnostic.Error!ast.NodeId {
        try self.enter();
        defer self.depth -= 1;
        const token = self.current();
        var left: ast.NodeId = switch (token.tag) {
            .integer, .ident, .kw_true, .kw_false => leaf: {
                self.pos += 1;
                if (token.tag == .ident and self.take(.lparen)) {
                    var arguments: std.ArrayList(ast.NodeId) = .empty;
                    if (self.current().tag != .rparen) while (true) {
                        try arguments.append(self.allocator, try self.expression(0));
                        if (!self.take(.comma)) break;
                    };
                    const close = try self.expect(.rparen);
                    break :leaf try self.append(.{ .span = .join(token.span, close.span), .data = .{ .call = .{ .name = token.span, .arguments = try arguments.toOwnedSlice(self.allocator) } } });
                }
                break :leaf try self.append(.{ .span = token.span, .data = switch (token.tag) {
                    .integer => .{ .integer = token.span },
                    .ident => .{ .name = token.span },
                    else => .{ .boolean = token.tag == .kw_true },
                } });
            },
            .minus, .bang => unary: {
                self.pos += 1;
                const operand = try self.expression(7);
                break :unary try self.append(.{ .span = .join(token.span, self.nodes.items[@backingInt(operand)].span), .data = .{ .unary = .{ .op = if (token.tag == .minus) .neg else .not, .operand = operand, .op_span = token.span } } });
            },
            .lparen => group: {
                self.pos += 1;
                const inner = try self.expression(0);
                const close = try self.expect(.rparen);
                self.nodes.items[@backingInt(inner)].span = .join(token.span, close.span);
                break :group inner;
            },
            else => return self.sink.fail("E_EXPRESSION", token.span, "expected an expression"),
        };
        while (true) {
            const op = self.current();
            const precedence: u8 = switch (op.tag) {
                .or_or => 1,
                .and_and => 2,
                .eq_eq, .bang_eq => 3,
                .lt, .le, .gt, .ge => 4,
                .plus, .minus => 5,
                .star, .slash, .percent => 6,
                else => break,
            };
            if (precedence < min_precedence) break;
            self.pos += 1;
            const right = try self.expression(precedence + 1);
            left = try self.append(.{ .span = .join(self.nodes.items[@backingInt(left)].span, self.nodes.items[@backingInt(right)].span), .data = .{ .binary = .{
                .op = switch (op.tag) {
                    .plus => .add,
                    .minus => .sub,
                    .star => .mul,
                    .slash => .div,
                    .percent => .rem,
                    .and_and => .logical_and,
                    .or_or => .logical_or,
                    .eq_eq => .eq,
                    .bang_eq => .ne,
                    .lt => .lt,
                    .le => .le,
                    .gt => .gt,
                    .ge => .ge,
                    else => unreachable,
                },
                .left = left,
                .right = right,
                .op_span = op.span,
            } } });
        }
        return left;
    }
};
