//! Recursive descent for statements; precedence climbing for expressions.
const std = @import("std");
const ast = @import("ast.zig");
const lex = @import("lexer.zig");
const Span = @import("source.zig").Span;
const diagnostic = @import("diagnostic.zig");
pub const Parser = struct {
    src: @import("source.zig").Source,
    allocator: std.mem.Allocator,
    tokens: []const lex.Token,
    sink: *diagnostic.Sink,
    pos: usize = 0,
    nodes: std.ArrayList(ast.Node) = .empty,
    statements: std.ArrayList(ast.Statement) = .empty,
    depth: usize = 0,
    array_types: std.ArrayList(ast.ArrayType) = .empty,
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
        try self.enter();
        defer self.depth -= 1;
        const token = self.current();
        if (self.take(.lbracket)) {
            const index: ast.ArrayIndex = if (self.current().tag == .integer) .{ .length = (try self.expect(.integer)).span } else .{ .enum_type = try self.typeName() };
            _ = try self.expect(.rbracket);
            const element = try self.typeName();
            const span: Span = .join(token.span, element);
            try self.array_types.append(self.allocator, .{ .span = span, .index = index, .element = element });
            return span;
        }
        if (self.take(.kw_i64) or self.take(.kw_bool) or self.take(.kw_i8) or self.take(.kw_i16) or self.take(.kw_i32) or self.take(.kw_u8) or self.take(.kw_u16) or self.take(.kw_u32) or self.take(.kw_u64) or self.take(.ident)) return token.span;
        return self.sink.fail("E_TYPE", token.span, "expected a built-in, declared, fixed array, or enum-indexed table type");
    }
    pub fn parse(self: *Parser) diagnostic.Error!ast.Program {
        var functions: std.ArrayList(ast.Function) = .empty;
        var records: std.ArrayList(ast.Record) = .empty;
        var domains: std.ArrayList(ast.Domain) = .empty;
        var variants: std.ArrayList(ast.Variants) = .empty;
        while (self.current().tag != .eof) {
            const fallible = self.current().tag == .ident and std.mem.eql(u8, self.src.text(self.current().span), "result");
            if (self.current().tag == .kw_enum or self.current().tag == .kw_union or fallible) {
                const is_union = self.current().tag != .kw_enum;
                self.pos += 1;
                const name = try self.expect(.ident);
                _ = try self.expect(.lbrace);
                var cases: std.ArrayList(ast.Variant) = .empty;
                if (self.current().tag != .rbrace) while (true) {
                    const tag = try self.expect(.ident);
                    const payload = if (is_union and self.take(.colon)) try self.typeName() else null;
                    try cases.append(self.allocator, .{ .name = tag.span, .payload = payload });
                    if (!self.take(.comma)) break;
                };
                _ = try self.expect(.rbrace);
                try variants.append(self.allocator, .{ .name = name.span, .fallible = fallible, .is_union = is_union, .cases = try cases.toOwnedSlice(self.allocator) });
                continue;
            }
            if (self.take(.kw_domain)) {
                const name = try self.expect(.ident);
                _ = try self.expect(.colon);
                const backing = try self.typeName();
                _ = try self.expect(.lbrace);
                while (self.current().tag != .rbrace) {
                    try functions.append(self.allocator, try self.function(name.span));
                }
                _ = try self.expect(.rbrace);
                try domains.append(self.allocator, .{ .name = name.span, .backing = backing });
                continue;
            }
            if (self.take(.kw_struct)) {
                const name = try self.expect(.ident);
                _ = try self.expect(.lbrace);
                var fields: std.ArrayList(ast.Parameter) = .empty;
                if (self.current().tag != .rbrace) while (true) {
                    const field = try self.expect(.ident);
                    _ = try self.expect(.colon);
                    try fields.append(self.allocator, .{ .name = field.span, .ty = try self.typeName() });
                    if (!self.take(.comma)) break;
                };
                _ = try self.expect(.rbrace);
                try records.append(self.allocator, .{ .name = name.span, .fields = try fields.toOwnedSlice(self.allocator) });
                continue;
            }
            try functions.append(self.allocator, try self.function(null));
        }
        return .{ .variants = try variants.toOwnedSlice(self.allocator), .domains = try domains.toOwnedSlice(self.allocator), .array_types = try self.array_types.toOwnedSlice(self.allocator), .nodes = self.nodes, .statements = self.statements, .functions = try functions.toOwnedSlice(self.allocator), .records = try records.toOwnedSlice(self.allocator) };
    }
    fn function(self: *Parser, owner: ?Span) diagnostic.Error!ast.Function {
        const restricted = self.take(.kw_private);
        if (restricted and owner == null) return self.sink.fail("E_PRIVATE_SCOPE", self.tokens[self.pos - 1].span, "private functions must be declared inside a domain");
        const conversion = self.take(.kw_conversion);
        _ = try self.expect(.kw_fn);
        const name = try self.expect(.ident);
        _ = try self.expect(.lparen);
        var parameters: std.ArrayList(ast.Parameter) = .empty;
        if (self.current().tag != .rparen) while (true) {
            const parameter = try self.expect(.ident);
            _ = try self.expect(.colon);
            const reference: ?bool = if (self.take(.ampersand)) self.take(.kw_mut) else null;
            const slice = reference != null and self.current().tag == .lbracket and self.tokens[self.pos + 1].tag == .rbracket;
            if (slice) {
                self.pos += 2;
            }
            try parameters.append(self.allocator, .{ .name = parameter.span, .ty = try self.typeName(), .reference = reference, .slice = slice });
            if (!self.take(.comma)) break;
        };
        _ = try self.expect(.rparen);
        _ = try self.expect(.arrow);
        const reference: ?bool = if (self.take(.ampersand)) self.take(.kw_mut) else null;
        const slice = reference != null and self.current().tag == .lbracket and self.tokens[self.pos + 1].tag == .rbracket;
        if (slice) self.pos += 2;
        const return_type = try self.typeName();
        var return_reference: ?ast.ReturnReference = null;
        if (reference) |mutable| {
            const from = try self.expect(.ident);
            if (!std.mem.eql(u8, self.src.text(from.span), "from")) return self.sink.fail("E_RETURN_LIFETIME", from.span, "reference result requires `from` followed by a reference parameter name");
            return_reference = .{ .source = (try self.expect(.ident)).span, .mutable = mutable, .slice = slice };
        }
        const body = try self.block();
        return .{ .return_reference = return_reference, .owner = owner, .restricted = restricted, .conversion = conversion, .name = name.span, .parameters = try parameters.toOwnedSlice(self.allocator), .return_type = return_type, .body = body };
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
        if (self.take(.kw_borrow)) {
            const mutable = self.take(.kw_mut);
            const owner_position = self.pos;
            const owner = try self.expect(.ident);
            if (self.current().tag == .lparen or self.current().tag == .dot) {
                self.pos = owner_position;
                const call = try self.expression(0);
                _ = try self.expect(.kw_as);
                const name = try self.expect(.ident);
                const body = try self.block();
                return self.addStatement(.{ .span = .join(first.span, self.statements.items[@backingInt(body)].span), .data = .{ .borrow_call = .{ .call = call, .name = name.span, .mutable = mutable, .body = body } } });
            }
            var range: ?ast.Range = null;
            if (self.take(.lbracket)) {
                const start = try self.expression(0);
                _ = try self.expect(.dot_dot);
                const end = try self.expression(0);
                _ = try self.expect(.rbracket);
                range = .{ .start = start, .end = end };
            }
            _ = try self.expect(.kw_as);
            const name = try self.expect(.ident);
            const body = try self.block();
            return self.addStatement(.{ .span = .join(first.span, self.statements.items[@backingInt(body)].span), .data = .{ .borrow = .{ .owner = owner.span, .name = name.span, .mutable = mutable, .body = body, .range = range } } });
        }
        if (self.take(.kw_match)) {
            const value = try self.expression(0);
            _ = try self.expect(.lbrace);
            var arms: std.ArrayList(ast.MatchArm) = .empty;
            if (self.current().tag != .rbrace) while (true) {
                const ty = try self.expect(.ident);
                _ = try self.expect(.dot);
                const name = try self.expect(.ident);
                var binding: ?Span = null;
                var discard_payload = false;
                if (self.take(.lparen)) {
                    if (self.take(.kw_discard)) discard_payload = true else binding = (try self.expect(.ident)).span;
                    _ = try self.expect(.rparen);
                }
                _ = try self.expect(.fat_arrow);
                const body = try self.block();
                try arms.append(self.allocator, .{ .ty = ty.span, .name = name.span, .binding = binding, .discard_payload = discard_payload, .body = body });
                if (!self.take(.comma)) break;
            };
            const close = try self.expect(.rbrace);
            return self.addStatement(.{ .span = .join(first.span, close.span), .data = .{ .match = .{ .value = value, .arms = try arms.toOwnedSlice(self.allocator) } } });
        }
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
            .kw_write_slice => write: {
                self.pos += 1;
                _ = try self.expect(.lparen);
                const name = try self.expect(.ident);
                _ = try self.expect(.comma);
                const index = try self.expression(0);
                _ = try self.expect(.comma);
                const value = try self.expression(0);
                _ = try self.expect(.rparen);
                break :write .{ .write_slice = .{ .name = name.span, .index = index, .value = value } };
            },
            .kw_write_ref => write: {
                self.pos += 1;
                _ = try self.expect(.lparen);
                const name = try self.expect(.ident);
                _ = try self.expect(.comma);
                const value = try self.expression(0);
                _ = try self.expect(.rparen);
                break :write .{ .write_ref = .{ .name = name.span, .value = value } };
            },
            .kw_acknowledge => acknowledged: {
                self.pos += 1;
                break :acknowledged .{ .acknowledge = try self.expression(0) };
            },
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
    fn fieldInitializers(self: *Parser) diagnostic.Error![]const ast.FieldInit {
        _ = try self.expect(.lbrace);
        var fields: std.ArrayList(ast.FieldInit) = .empty;
        if (self.current().tag != .rbrace) while (true) {
            const name = try self.expect(.ident);
            _ = try self.expect(.colon);
            try fields.append(self.allocator, .{ .name = name.span, .value = try self.expression(0) });
            if (!self.take(.comma)) break;
        };
        _ = try self.expect(.rbrace);
        return fields.toOwnedSlice(self.allocator);
    }
    fn expression(self: *Parser, min_precedence: u8) diagnostic.Error!ast.NodeId {
        try self.enter();
        defer self.depth -= 1;
        const token = self.current();
        var left: ast.NodeId = switch (token.tag) {
            .kw_read_slice => read: {
                self.pos += 1;
                _ = try self.expect(.lparen);
                const name = try self.expect(.ident);
                _ = try self.expect(.comma);
                const index = try self.expression(0);
                const close = try self.expect(.rparen);
                break :read try self.append(.{ .span = .join(token.span, close.span), .data = .{ .read_slice = .{ .name = name.span, .index = index } } });
            },
            .kw_len_slice => length: {
                self.pos += 1;
                _ = try self.expect(.lparen);
                const name = try self.expect(.ident);
                const close = try self.expect(.rparen);
                break :length try self.append(.{ .span = .join(token.span, close.span), .data = .{ .len_slice = name.span } });
            },
            .kw_read_ref => read: {
                self.pos += 1;
                _ = try self.expect(.lparen);
                const name = try self.expect(.ident);
                const close = try self.expect(.rparen);
                break :read try self.append(.{ .span = .join(token.span, close.span), .data = .{ .read_ref = name.span } });
            },
            .kw_cast, .kw_wrap => cast: {
                self.pos += 1;
                _ = try self.expect(.lt);
                const ty = try self.typeName();
                _ = try self.expect(.gt);
                _ = try self.expect(.lparen);
                const value = try self.expression(0);
                const close = try self.expect(.rparen);
                break :cast try self.append(.{ .span = .join(token.span, close.span), .data = if (token.tag == .kw_cast) .{ .cast = .{ .ty = ty, .value = value } } else .{ .wrap = .{ .ty = ty, .value = value } } });
            },
            .kw_new => record: {
                self.pos += 1;
                const name = try self.typeName();
                if (self.take(.dot)) {
                    const tag = try self.expect(.ident);
                    var value: ?ast.NodeId = null;
                    if (self.take(.lparen)) {
                        value = try self.expression(0);
                        _ = try self.expect(.rparen);
                    }
                    break :record try self.append(.{ .span = .join(token.span, self.tokens[self.pos - 1].span), .data = .{ .variant = .{ .ty = name, .name = tag.span, .value = value } } });
                }
                if (self.take(.lbracket)) {
                    var values: std.ArrayList(ast.NodeId) = .empty;
                    if (self.current().tag != .rbracket) while (true) {
                        try values.append(self.allocator, try self.expression(0));
                        if (!self.take(.comma)) break;
                    };
                    const close = try self.expect(.rbracket);
                    break :record try self.append(.{ .span = .join(token.span, close.span), .data = .{ .array = .{ .ty = name, .values = try values.toOwnedSlice(self.allocator) } } });
                }
                const fields = try self.fieldInitializers();
                break :record try self.append(.{ .span = .join(token.span, self.tokens[self.pos - 1].span), .data = .{ .record = .{ .name = name, .fields = fields } } });
            },
            .kw_len, .kw_replace, .kw_unwrap => builtin: {
                self.pos += 1;
                _ = try self.expect(.lparen);
                const base = try self.expression(0);
                if (token.tag != .kw_replace) {
                    const close = try self.expect(.rparen);
                    break :builtin try self.append(.{ .span = .join(token.span, close.span), .data = if (token.tag == .kw_len) .{ .length = base } else .{ .unwrap = base } });
                }
                _ = try self.expect(.comma);
                const index = try self.expression(0);
                _ = try self.expect(.comma);
                const value = try self.expression(0);
                const close = try self.expect(.rparen);
                break :builtin try self.append(.{ .span = .join(token.span, close.span), .data = .{ .replace = .{ .base = base, .index = index, .value = value } } });
            },
            .kw_update => update: {
                self.pos += 1;
                _ = try self.expect(.lparen);
                const base = try self.expression(0);
                _ = try self.expect(.rparen);
                const fields = try self.fieldInitializers();
                break :update try self.append(.{ .span = .join(token.span, self.tokens[self.pos - 1].span), .data = .{ .update = .{ .base = base, .fields = fields } } });
            },
            .integer, .ident, .kw_true, .kw_false => leaf: {
                self.pos += 1;
                var owner: ?Span = null;
                var name = token.span;
                if (token.tag == .ident and self.current().tag == .dot and self.pos + 2 < self.tokens.len and self.tokens[self.pos + 1].tag == .ident and self.tokens[self.pos + 2].tag == .lparen) {
                    owner = token.span;
                    self.pos += 1;
                    name = (try self.expect(.ident)).span;
                }
                if (token.tag == .ident and self.take(.lparen)) {
                    var arguments: std.ArrayList(ast.NodeId) = .empty;
                    if (self.current().tag != .rparen) while (true) {
                        try arguments.append(self.allocator, try self.expression(0));
                        if (!self.take(.comma)) break;
                    };
                    const close = try self.expect(.rparen);
                    break :leaf try self.append(.{ .span = .join(token.span, close.span), .data = .{ .call = .{ .owner = owner, .name = name, .arguments = try arguments.toOwnedSlice(self.allocator) } } });
                }
                break :leaf try self.append(.{ .span = token.span, .data = switch (token.tag) {
                    .integer => .{ .integer = token.span },
                    .ident => .{ .name = token.span },
                    else => .{ .boolean = token.tag == .kw_true },
                } });
            },
            .kw_try => propagated: {
                self.pos += 1;
                const value = try self.expression(7);
                break :propagated try self.append(.{ .span = .join(token.span, self.nodes.items[@backingInt(value)].span), .data = .{ .propagate = value } });
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
            if (self.take(.lbracket)) {
                const index = try self.expression(0);
                const close = try self.expect(.rbracket);
                left = try self.append(.{ .span = .join(self.nodes.items[@backingInt(left)].span, close.span), .data = .{ .index = .{ .base = left, .index = index } } });
                continue;
            }
            if (self.take(.dot)) {
                const name = try self.expect(.ident);
                left = try self.append(.{ .span = .join(self.nodes.items[@backingInt(left)].span, name.span), .data = .{ .field = .{ .base = left, .name = name.span } } });
                continue;
            }
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
