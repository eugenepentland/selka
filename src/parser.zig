//! Recursive descent for statements; precedence climbing for expressions.
const syntax_code = "E_SYNTAX";
const eDefaultArgument = "E_DEFAULT_ARGUMENT";
const eRequirement = diagnostic.generic_requirement;
const eGenericLimit = diagnostic.generic_limit;
const external_resources = @import("external_resources.zig");
const std = @import("std");
const eIteration = "E_ITERATION";
const effects = @import("effect_set.zig");
const ast = @import("ast.zig");
const lex = @import("lexer.zig");
const Span = @import("source.zig").Span;
const diagnostic = @import("diagnostic.zig");
const byte_literal = @import("byte_literal.zig");
const format_strings = @import("format_strings.zig");
/// Tokens that may stand inside an explicit type-argument list: a name, a constant
/// length, nested brackets, and every type the lexer spells as a keyword.
fn typeArgumentToken(tag: lex.Tag) bool {
    return switch (tag) {
        .ident,
        .integer,
        .lbracket,
        .rbracket,
        .kw_i8,
        .kw_i16,
        .kw_i32,
        .kw_i64,
        .kw_u8,
        .kw_u16,
        .kw_u32,
        .kw_u64,
        .kw_bool,
        .kw_none,
        .kw_filesystem_cap,
        .kw_network_cap,
        .kw_environment_cap,
        .kw_clock_cap,
        .kw_random_cap,
        => true,
        else => false,
    };
}

/// Token cursor and allocator-backed syntax builder with bounded recursive nesting.
pub const Parser = struct {
    src: @import("source.zig").Source,
    arena: *std.heap.ArenaAllocator,
    tokens: []const lex.Token,
    sink: *diagnostic.Sink,
    cursor: struct { pos: usize = 0, depth: usize = 0, delimiters: usize = 0 } = .{},
    module_syntax: bool = false,
    syntax: struct {
        nodes: std.ArrayList(ast.Node) = .empty,
        statements: std.ArrayList(ast.Statement) = .empty,
        array_types: std.ArrayList(ast.ArrayType) = .empty,
        callbacks: std.ArrayList(ast.CallbackType) = .empty,
        applications: std.ArrayList(ast.TypeApplication) = .empty,
        aliases: std.ArrayList(ast.TypeAlias) = .empty,
        import_aliases: std.StringHashMapUnmanaged(void) = .empty,
    } = .{},
    fn current(self: *Parser) lex.Token {
        return self.tokens[self.cursor.pos];
    }
    fn take(self: *Parser, tag: lex.Tag) bool {
        if (self.current().tag != tag) return false;
        self.cursor.pos += 1;
        switch (tag) {
            .lparen, .lbracket => self.cursor.delimiters += 1,
            .rparen, .rbracket => self.cursor.delimiters -|= 1,
            else => {},
        }
        return true;
    }
    fn expect(self: *Parser, comptime tag: lex.Tag) diagnostic.Error!lex.Token {
        if (tag == .rparen and self.current().tag == .comma) {
            if (self.tokens[self.cursor.pos + 1].tag == .rparen) _ = self.take(.comma);
        }
        const token = self.current();
        if (tag == .semicolon and token.tag != .semicolon and lex.implicitTerminator(self.src.bytes, self.tokens, self.cursor.pos)) {
            const end = self.tokens[self.cursor.pos - 1].span.end;
            return .{ .tag = .semicolon, .span = .{ .start = end, .end = end } };
        }
        if (!self.take(tag)) return self.sink.fail(syntax_code, token.span, "unexpected token; expected " ++ comptime lex.spelling(tag));
        return token;
    }
    fn enter(self: *Parser) diagnostic.Error!void {
        if (self.cursor.depth >= 256) return self.sink.fail("E_NESTING_LIMIT", self.current().span, "parser nesting exceeds 256 levels");
        self.cursor.depth += 1;
    }
    /// Accept a declared name that collides with an intrinsic keyword. `len` and `replace`
    /// are intrinsics in call position only, so both remain ordinary names elsewhere.
    fn declaredName(self: *Parser) diagnostic.Error!Span {
        const token = self.current();
        if (token.tag != .kw_len and token.tag != .kw_replace) return (try self.expect(.ident)).span;
        self.cursor.pos += 1;
        return token.span;
    }
    fn declaresFunction(self: Parser, name: Span) bool {
        var position: usize = 0;
        var depth: usize = 0;
        while (position + 1 < self.tokens.len) : (position += 1) {
            if (self.tokens[position].tag == .indent) depth += 1;
            if (self.tokens[position].tag == .dedent) depth -|= 1;
            if (depth != 0 or self.tokens[position].tag != .kw_def) continue;
            const candidate = self.tokens[position + 1];
            if (candidate.tag != .ident and candidate.tag != .kw_len and candidate.tag != .kw_replace) continue;
            if (std.mem.eql(u8, self.src.text(candidate.span), self.src.text(name))) return true;
        }
        return false;
    }
    fn qualifiedTail(self: *Parser, first: Span) diagnostic.Error!Span {
        if (!self.module_syntax) return first;
        if (self.current().tag != .dot or !self.syntax.import_aliases.contains(self.src.text(first))) return first;
        if (!self.sameExpressionLine()) return first;
        self.cursor.pos += 1;
        return .join(first, try self.declaredName());
    }
    fn typeName(self: *Parser) diagnostic.Error!Span {
        try self.enter();
        defer self.cursor.depth -= 1;
        const token = self.current();
        if (self.take(.kw_def)) return self.callbackType(token.span);
        if (self.take(.kw_none)) return token.span;
        if (self.take(.lparen)) return .join(token.span, (try self.expect(.rparen)).span);
        if (self.take(.lbracket)) {
            const index: ast.ArrayIndex = if (self.current().tag == .integer) .{ .length = (try self.expect(.integer)).span } else .{ .enum_type = try self.typeName() };
            _ = try self.expect(.rbracket);
            const element = try self.typeName();
            const span: Span = .join(token.span, element);
            try self.syntax.array_types.append(self.arena.allocator(), .{ .span = span, .index = index, .element = element });
            return span;
        }
        for ([_]lex.Tag{
            .kw_i64,
            .kw_bool,
            .kw_i8,
            .kw_i16,
            .kw_i32,
            .kw_u8,
            .kw_u16,
            .kw_u32,
            .kw_u64,
            .kw_filesystem_cap,
            .kw_network_cap,
            .kw_environment_cap,
            .kw_clock_cap,
            .kw_random_cap,
        }) |tag| {
            if (self.take(tag)) return token.span;
        }
        if (self.current().tag == .ident) return self.nominalTypeName();
        return self.sink.fail("E_TYPE", token.span, "expected a built-in, declared, fixed array, or enum-indexed table type");
    }
    fn genericArgument(self: *Parser) diagnostic.Error!Span {
        if (self.current().tag == .integer) return (try self.expect(.integer)).span;
        return self.typeName();
    }
    fn callbackType(self: *Parser, first: Span) diagnostic.Error!Span {
        _ = try self.expect(.lparen);
        var parameters: std.ArrayList(Span) = .empty;
        if (self.current().tag != .rparen) while (true) {
            if (parameters.items.len == 16) return self.sink.fail(eGenericLimit, first, "callbacks support at most 16 value parameters");
            try parameters.append(self.arena.allocator(), try self.typeName());
            if (!self.take(.comma) or self.current().tag == .rparen) break;
        };
        _ = try self.expect(.rparen);
        _ = try self.expect(.arrow);
        const result = try self.typeName();
        const bound = try self.effectBound() orelse return self.sink.fail("E_CALLBACK_EFFECTS", first, "callback types require an explicit effects ceiling");
        const span: Span = .join(first, self.tokens[self.cursor.pos - 1].span);
        try self.syntax.callbacks.append(self.arena.allocator(), .{ .span = span, .parameters = try parameters.toOwnedSlice(self.arena.allocator()), .return_type = result, .effect_bound = bound });
        return span;
    }
    fn nominalTypeName(self: *Parser) diagnostic.Error!Span {
        const token = try self.expect(.ident);
        const name = try self.qualifiedTail(token.span);
        if (!self.take(.lbracket)) return name;
        var arguments: std.ArrayList(Span) = .empty;
        while (true) {
            const argument = try self.genericArgument();
            if (arguments.items.len == 16) return self.sink.fail(eGenericLimit, argument, "at most 16 type arguments are permitted");
            try arguments.append(self.arena.allocator(), argument);
            if (!self.take(.comma)) break;
        }
        const close = try self.expect(.rbracket);
        const span: Span = .join(name, close.span);
        try self.syntax.applications.append(self.arena.allocator(), .{ .span = span, .name = name, .arguments = try arguments.toOwnedSlice(self.arena.allocator()) });
        return span;
    }
    /// Parse module headers and bodies without loading imports or checking names.
    pub fn parseModule(self: *Parser) diagnostic.Error!ast.Program {
        self.module_syntax = true;
        const first = try self.expect(.ident);
        if (!std.mem.eql(u8, self.src.text(first.span), "module")) return self.sink.fail("E_MODULE_HEADER", first.span, "file must begin with a module declaration");
        try self.moduleName();
        _ = try self.expect(.semicolon);
        while (self.current().tag == .ident and std.mem.eql(u8, self.src.text(self.current().span), "import")) {
            self.cursor.pos += 1;
            try self.moduleName();
            const alias = if (self.take(.kw_as)) (try self.expect(.ident)).span else self.tokens[self.cursor.pos - 1].span;
            try self.syntax.import_aliases.put(self.arena.allocator(), self.src.text(alias), {});
            _ = try self.expect(.semicolon);
        }
        return self.parse();
    }
    fn parseCodec(self: *Parser) diagnostic.Error!ast.Codec {
        const wire = try self.typeName();
        _ = try self.expect(.indent);
        var decode: ?Span = null;
        var encode: ?Span = null;
        while (self.current().tag != .dedent) {
            const key = (try self.expect(.ident)).span;
            const name = self.src.text(key);
            const target = if (std.mem.eql(u8, name, "decode")) &decode else if (std.mem.eql(u8, name, "encode")) &encode else return self.sink.fail("E_CODEC_KEY", key, "codec entries must be decode or encode");
            if (target.* != null) return self.sink.fail("E_DUPLICATE_CODEC_KEY", key, "codec entry is declared more than once");
            _ = try self.expect(.colon);
            target.* = (try self.expect(.ident)).span;
            if (!self.take(.comma)) break;
        }
        const end = (try self.expect(.dedent)).span;
        return .{
            .wire = wire,
            .decode = decode orelse return self.sink.fail("E_INCOMPLETE_CODEC", end, "codec requires decode and encode entries"),
            .encode = encode orelse return self.sink.fail("E_INCOMPLETE_CODEC", end, "codec requires decode and encode entries"),
        };
    }
    fn moduleName(self: *Parser) diagnostic.Error!void {
        _ = try self.expect(.ident);
        while (self.take(.dot)) _ = try self.expect(.ident);
    }
    /// Parse a complete source program, retaining syntax and diagnostics in the supplied allocator.
    pub fn parse(self: *Parser) diagnostic.Error!ast.Program {
        var functions: std.ArrayList(ast.Function) = .empty;
        var records: std.ArrayList(ast.Record) = .empty;
        var domains: std.ArrayList(ast.Domain) = .empty;
        var resources: std.ArrayList(ast.Domain) = .empty;
        var variants: std.ArrayList(ast.Variants) = .empty;
        while (self.current().tag != .eof) {
            if (self.module_syntax and self.current().tag == .ident and std.mem.eql(u8, self.src.text(self.current().span), "export")) {
                self.cursor.pos += 1;
                _ = try self.declaredName();
                _ = try self.expect(.semicolon);
                continue;
            }
            if (self.take(.kw_type)) {
                const name = (try self.expect(.ident)).span;
                _ = try self.expect(.equal);
                const target = try self.typeName();
                _ = try self.expect(.semicolon);
                try self.syntax.aliases.append(self.arena.allocator(), .{ .name = name, .target = target });
                continue;
            }
            if (self.take(.kw_const)) {
                const name = (try self.expect(.ident)).span;
                _ = try self.expect(.colon);
                const ty = try self.typeName();
                _ = try self.expect(.equal);
                const value = try self.expression(0);
                const end = (try self.expect(.semicolon)).span;
                const ret = try self.addStatement(.{ .span = .join(name, end), .data = .{ .ret = value } });
                const statements = try self.arena.allocator().alloc(ast.StatementId, 1);
                statements[0] = ret;
                const body = try self.addStatement(.{ .span = .join(name, end), .data = .{ .block = statements } });
                try functions.append(self.arena.allocator(), .{ .policy = .{ .constant = true, .effect_bound = .{ .allowed = 0, .span = name } }, .signature = .{ .parameters = &.{}, .return_type = ty }, .name = name, .body = body });
                continue;
            }
            if (self.current().tag == .ident and std.mem.eql(u8, self.src.text(self.current().span), "resource")) {
                self.cursor.pos += 1;
                const name = try self.expect(.ident);
                _ = try self.expect(.colon);
                const kind = try self.expect(.ident);
                _ = try self.expect(.semicolon);
                try resources.append(self.arena.allocator(), .{ .name = name.span, .backing = kind.span });
                continue;
            }
            const fallible = self.current().tag == .ident and std.mem.eql(u8, self.src.text(self.current().span), "result");
            if (self.current().tag == .kw_enum or self.current().tag == .kw_union or fallible) {
                const is_union = self.current().tag != .kw_enum;
                self.cursor.pos += 1;
                const name = try self.expect(.ident);
                const type_parameters = try self.typeParameters();
                _ = try self.expect(.indent);
                var cases: std.ArrayList(ast.Variant) = .empty;
                if (self.current().tag != .dedent) while (true) {
                    const tag = try self.expect(.ident);
                    const payload = if (is_union and self.take(.colon)) try self.typeName() else null;
                    try cases.append(self.arena.allocator(), .{ .name = tag.span, .payload = payload });
                    if (!self.take(.comma)) break;
                };
                _ = try self.expect(.dedent);
                try variants.append(self.arena.allocator(), .{ .type_parameters = type_parameters, .name = name.span, .fallible = fallible, .is_union = is_union, .cases = try cases.toOwnedSlice(self.arena.allocator()) });
                continue;
            }
            if (self.take(.kw_domain)) {
                const name = try self.expect(.ident);
                _ = try self.expect(.colon);
                const backing = try self.typeName();
                _ = try self.expect(.indent);
                var codec: ?ast.Codec = null;
                // `pass` spells an empty suite here as it does in a record.
                if (self.take(.kw_pass)) _ = try self.expect(.semicolon);
                while (self.current().tag != .dedent) {
                    if (self.current().tag == .ident and std.mem.eql(u8, self.src.text(self.current().span), "codec")) {
                        if (codec != null) return self.sink.fail("E_DUPLICATE_CODEC", self.current().span, "a domain declares at most one codec");
                        self.cursor.pos += 1;
                        codec = try self.parseCodec();
                    } else try functions.append(self.arena.allocator(), try self.function(name.span));
                }
                _ = try self.expect(.dedent);
                try domains.append(self.arena.allocator(), .{ .name = name.span, .backing = backing, .codec = codec });
                continue;
            }
            if (self.take(.kw_class)) {
                const name = try self.expect(.ident);
                const type_parameters = try self.typeParameters();
                _ = try self.expect(.indent);
                var fields: std.ArrayList(ast.Parameter) = .empty;
                const empty_record = self.take(.kw_pass);
                if (empty_record) _ = try self.expect(.semicolon);
                if (!empty_record and self.current().tag != .dedent) while (true) {
                    const field = try self.declaredName();
                    _ = try self.expect(.colon);
                    try fields.append(self.arena.allocator(), .{ .name = field, .ty = try self.typeName() });
                    const next_field = self.current().tag != .dedent and lex.implicitTerminator(self.src.bytes, self.tokens, self.cursor.pos);
                    if (!self.take(.comma) and !next_field) break;
                };
                _ = try self.expect(.dedent);
                try records.append(self.arena.allocator(), .{ .type_parameters = type_parameters, .name = name.span, .fields = try fields.toOwnedSlice(self.arena.allocator()) });
                continue;
            }
            try functions.append(self.arena.allocator(), try self.function(null));
        }
        return .{
            .types = .{
                .resources = try resources.toOwnedSlice(self.arena.allocator()),
                .variants = try variants.toOwnedSlice(self.arena.allocator()),
                .domains = try domains.toOwnedSlice(self.arena.allocator()),
                .expressions = .{
                    .callbacks = try self.syntax.callbacks.toOwnedSlice(self.arena.allocator()),
                    .arrays = try self.syntax.array_types.toOwnedSlice(self.arena.allocator()),
                    .applications = try self.syntax.applications.toOwnedSlice(self.arena.allocator()),
                    .aliases = try self.syntax.aliases.toOwnedSlice(self.arena.allocator()),
                },
                .records = try records.toOwnedSlice(self.arena.allocator()),
            },

            .nodes = self.syntax.nodes,
            .statements = self.syntax.statements,
            .functions = try functions.toOwnedSlice(self.arena.allocator()),
        };
    }
    fn function(self: *Parser, owner: ?Span) diagnostic.Error!ast.Function {
        const c_abi = self.current().tag == .ident and std.mem.eql(u8, self.src.text(self.current().span), "extern");
        const host: ?Span = if (c_abi or (self.current().tag == .ident and std.mem.eql(u8, self.src.text(self.current().span), "host"))) self.current().span else null;
        if (host != null) self.cursor.pos += 1;
        const restricted = self.take(.kw_private);
        if (restricted and owner == null) return self.sink.fail("E_PRIVATE_SCOPE", self.tokens[self.cursor.pos - 1].span, "private functions must be declared inside a domain");
        const conversion = self.take(.kw_conversion);
        _ = try self.expect(.kw_def);
        const name: lex.Token = .{ .tag = .ident, .span = try self.declaredName() };
        const type_parameters = try self.typeParameters();
        _ = try self.expect(.lparen);
        var parameters = try self.functionParameters();
        const close_parameters = try self.expect(.rparen);
        const annotated_return = self.take(.arrow);
        const return_type = if (annotated_return) try self.typeName() else Span{ .start = close_parameters.span.end, .end = close_parameters.span.end };
        if (host) |span| {
            if (owner != null or restricted or conversion) return self.sink.fail("E_HOST_DECLARATION", span, "host declarations must be ordinary top-level functions");
            if (type_parameters.len != 0) return self.sink.fail("E_HOST_DECLARATION", span, "generic host declarations are not supported");
            if (self.current().tag != .ident or !std.mem.eql(u8, self.src.text(self.current().span), "effects")) return self.sink.fail("E_HOST_EFFECTS", span, "host declarations require an explicit effects(host, ...) contract");
        }
        const effect_bound = try self.effectBound();
        if (host) |span| if (effect_bound.?.allowed & effects.bit(.host) == 0) return self.sink.fail("E_HOST_EFFECTS", span, "host declarations must include the host effect");
        if (c_abi and !annotated_return) return self.sink.fail("E_EXTERN_SIGNATURE", name.span, "extern functions require an explicit return type (unit for C void)");
        const body = if (host != null) try self.addStatement(.{ .span = (try self.expect(.semicolon)).span, .data = .{ .block = &.{} } }) else try self.block();
        return .{
            .policy = .{
                .host = host,
                .c_abi = c_abi,
                .effect_bound = effect_bound,
                .owner = owner,
                .restricted = restricted,
                .conversion = conversion,
            },
            .signature = .{
                .type_parameters = type_parameters,
                .parameters = try parameters.toOwnedSlice(self.arena.allocator()),
                .return_type = return_type,
            },
            .name = name.span,
            .body = body,
        };
    }
    fn functionParameters(self: *Parser) diagnostic.Error!std.ArrayList(ast.Parameter) {
        var parameters: std.ArrayList(ast.Parameter) = .empty;
        var default_seen = false;
        if (self.current().tag != .rparen) while (true) {
            const parameter = try self.declaredName();
            _ = try self.expect(.colon);
            const ty = try self.typeName();
            const default_value = if (self.take(.equal)) try self.defaultArgument() else null;
            if (default_seen and default_value == null) return self.sink.fail(eDefaultArgument, parameter, "required parameters must precede parameters with defaults");
            default_seen = default_seen or default_value != null;
            try parameters.append(self.arena.allocator(), .{ .name = parameter, .ty = ty, .default_value = default_value });
            if (!self.take(.comma) or self.current().tag == .rparen) break;
        };
        return parameters;
    }
    fn defaultArgument(self: *Parser) diagnostic.Error!ast.NodeId {
        const value = try self.expression(0);
        const node = self.syntax.nodes.items[@backingInt(value)];
        const literal = switch (node.data) {
            .integer, .boolean, .unit, .text => true,
            .unary => |unary| unary.op == .neg and self.syntax.nodes.items[@backingInt(unary.operand)].data == .integer,
            else => false,
        };
        if (!literal) return self.sink.fail(eDefaultArgument, node.span, "defaults must be immutable scalar literals");
        return value;
    }
    fn typeParameters(self: *Parser) diagnostic.Error![]const ast.TypeParameter {
        if (!self.take(.lbracket)) return &.{};
        var parameters: std.ArrayList(ast.TypeParameter) = .empty;
        while (true) {
            const constant_length = self.take(.kw_const);
            const name = (try self.expect(.ident)).span;
            if (parameters.items.len == 16) return self.sink.fail(eGenericLimit, name, "at most 16 type parameters are permitted");
            for (parameters.items) |previous| if (std.mem.eql(u8, self.src.text(previous.name), self.src.text(name))) return self.sink.fail("E_GENERIC_PARAMETER", name, "duplicate type parameter");
            if (!constant_length and self.current().tag != .colon) {
                try parameters.append(self.arena.allocator(), .{ .name = name, .requirements = &.{}, .default_copy = true });
                if (!self.take(.comma)) break;
                continue;
            }
            _ = try self.expect(.colon);
            if (constant_length) {
                _ = try self.expect(.kw_u64);
                try parameters.append(self.arena.allocator(), .{ .name = name, .requirements = &.{}, .constant_length = true });
                if (!self.take(.comma)) break;
                continue;
            }
            var requirements: std.ArrayList(Span) = .empty;
            var fields: std.ArrayList(ast.Parameter) = .empty;
            var operations: std.ArrayList(ast.Operation) = .empty;
            while (true) {
                const requirement = (try self.expect(.ident)).span;
                if (requirements.items.len + fields.items.len + operations.items.len == 16) return self.sink.fail(eGenericLimit, requirement, "at most 16 requirements are permitted");
                if (std.mem.eql(u8, self.src.text(requirement), "field")) {
                    _ = try self.expect(.lparen);
                    const field = try self.constraintParameter();
                    _ = try self.expect(.rparen);
                    try fields.append(self.arena.allocator(), field);
                } else if (std.mem.eql(u8, self.src.text(requirement), "op")) {
                    try operations.append(self.arena.allocator(), try self.operationConstraint());
                } else {
                    for (requirements.items) |previous| if (std.mem.eql(u8, self.src.text(previous), self.src.text(requirement))) return self.sink.fail(eRequirement, requirement, "duplicate type requirement");
                    try requirements.append(self.arena.allocator(), requirement);
                }
                if (!self.take(.plus)) break;
            }
            try parameters.append(self.arena.allocator(), .{
                .name = name,
                .requirements = try requirements.toOwnedSlice(self.arena.allocator()),
                .field_requirements = try fields.toOwnedSlice(self.arena.allocator()),
                .operation_requirements = try operations.toOwnedSlice(self.arena.allocator()),
            });
            if (!self.take(.comma)) break;
        }
        _ = try self.expect(.rbracket);
        return parameters.toOwnedSlice(self.arena.allocator());
    }
    fn constraintParameter(self: *Parser) diagnostic.Error!ast.Parameter {
        const name = (try self.expect(.ident)).span;
        _ = try self.expect(.colon);
        return .{ .name = name, .ty = try self.typeName() };
    }
    fn operationConstraint(self: *Parser) diagnostic.Error!ast.Operation {
        _ = try self.expect(.lparen);
        const name = (try self.expect(.ident)).span;
        _ = try self.expect(.lparen);
        var parameters: std.ArrayList(ast.Parameter) = .empty;
        if (self.current().tag != .rparen) while (true) {
            if (parameters.items.len == 16) return self.sink.fail(eGenericLimit, self.current().span, "at most 16 structural operation parameters are permitted");
            try parameters.append(self.arena.allocator(), try self.constraintParameter());
            if (!self.take(.comma) or self.current().tag == .rparen) break;
        };
        _ = try self.expect(.rparen);
        _ = try self.expect(.arrow);
        const result = try self.typeName();
        const bound = try self.effectBound() orelse return self.sink.fail(eRequirement, name, "structural operations require an explicit effects bound");
        _ = try self.expect(.rparen);
        return .{ .name = name, .parameters = try parameters.toOwnedSlice(self.arena.allocator()), .return_type = result, .effect_bound = bound };
    }
    fn effectBound(self: *Parser) diagnostic.Error!?effects.Bound {
        const sets = effects;
        const token = self.current();
        if (token.tag != .ident) return null;
        const spelling = self.src.text(token.span);
        if (std.mem.eql(u8, spelling, "noalloc") or std.mem.eql(u8, spelling, "noio")) {
            self.cursor.pos += 1;
            const excluded = if (std.mem.eql(u8, spelling, "noalloc")) sets.bit(.managed_allocation) else sets.io;
            return .{ .span = token.span, .allowed = sets.all & ~excluded };
        }
        if (!std.mem.eql(u8, spelling, "effects")) return null;
        self.cursor.pos += 1;
        _ = try self.expect(.lparen);
        var allowed: sets.Mask = 0;
        if (self.current().tag != .rparen) while (true) {
            const name = try self.expect(.ident);
            const effect = std.meta.stringToEnum(sets.Effect, self.src.text(name.span)) orelse return self.sink.fail(
                "E_UNKNOWN_EFFECT",
                name.span,
                "unknown effect; expected managed_allocation, filesystem, network, clock, random, environment, output, or host",
            );
            if (allowed & sets.bit(effect) != 0) return self.sink.fail("E_DUPLICATE_EFFECT", name.span, "effect appears more than once in this bound");
            allowed |= sets.bit(effect);
            if (!self.take(.comma) or self.current().tag == .rparen) break;
        };
        const close = try self.expect(.rparen);
        return .{ .span = .join(token.span, close.span), .allowed = allowed };
    }
    fn addStatement(self: *Parser, stmt: ast.Statement) diagnostic.Error!ast.StatementId {
        const id: ast.StatementId = @fromBackingInt(self.syntax.statements.items.len);
        try self.syntax.statements.append(self.arena.allocator(), stmt);
        return id;
    }
    fn block(self: *Parser) diagnostic.Error!ast.StatementId {
        try self.enter();
        defer self.cursor.depth -= 1;
        const open = try self.expect(.indent);
        var statements: std.ArrayList(ast.StatementId) = .empty;
        while (self.current().tag != .dedent) {
            if (self.current().tag == .eof) return self.sink.fail(syntax_code, self.current().span, "block is not closed before the end of the file");
            try statements.append(self.arena.allocator(), try self.statement());
        }
        _ = try self.expect(.dedent);
        // A dedent stands at the next declaration, so the blank lines and comments
        // between two suites belong to neither; a suite ends where its last token did.
        var written = self.cursor.pos;
        while (written > 1 and self.tokens[written - 1].span.start == self.tokens[written - 1].span.end) written -= 1;
        const close = self.tokens[written - 1].span;
        return self.addStatement(.{ .span = .join(open.span, close), .data = .{ .block = try statements.toOwnedSlice(self.arena.allocator()) } });
    }
    /// One `with` form covers both resource kinds: `with arena()` opens a managed
    /// region, and any other expression must produce an open file handle.
    fn withStatement(self: *Parser, first: Span) diagnostic.Error!ast.StatementId {
        const arena = self.current().tag == .kw_arena;
        const resource: ?ast.NodeId = if (arena) resource: {
            self.cursor.pos += 1;
            _ = try self.expect(.lparen);
            _ = try self.expect(.rparen);
            break :resource null;
        } else try self.conditionExpression();
        const name: ?Span = if (self.take(.kw_as)) (try self.expect(.ident)).span else null;
        const body = try self.block();
        return self.addStatement(.{
            .span = .join(first, self.syntax.statements.items[@backingInt(body)].span),
            .data = .{ .with_scope = .{ .resource = resource, .name = name, .body = body } },
        });
    }
    fn conditionExpression(self: *Parser) diagnostic.Error!ast.NodeId {
        return self.expression(0);
    }
    fn statement(self: *Parser) diagnostic.Error!ast.StatementId {
        try self.enter();
        defer self.cursor.depth -= 1;
        const first = self.current();
        if (self.take(.kw_with)) return self.withStatement(first.span);
        if (self.take(.kw_match)) {
            const value = try self.conditionExpression();
            _ = try self.expect(.indent);
            var arms: std.ArrayList(ast.MatchArm) = .empty;
            if (self.current().tag != .dedent) while (true) {
                _ = try self.expect(.kw_case);
                const pattern = try self.matchPattern();
                const body = try self.block();
                try arms.append(self.arena.allocator(), .{ .ty = pattern.ty, .name = pattern.name, .binding = pattern.binding, .discard_payload = pattern.discard_payload, .body = body });
                if (self.current().tag != .kw_case) break;
            };
            const close = try self.expect(.dedent);
            return self.addStatement(.{ .span = .join(first.span, close.span), .data = .{ .match = .{ .value = value, .arms = try arms.toOwnedSlice(self.arena.allocator()) } } });
        }
        if (self.take(.kw_if) or self.take(.kw_elif)) {
            const condition = try self.conditionExpression();
            const then_body = try self.block();
            const else_body = if (self.current().tag == .kw_elif)
                try self.statement()
            else if (self.take(.kw_else)) try self.block() else null;
            const last = else_body orelse then_body;
            return self.addStatement(.{ .span = .join(first.span, self.syntax.statements.items[@backingInt(last)].span), .data = .{ .branch = .{
                .condition = condition,
                .then_body = then_body,
                .else_body = else_body,
            } } });
        }
        if (self.take(.kw_for)) return self.forStatement(first);
        if (self.take(.kw_while)) {
            const condition = try self.conditionExpression();
            const body = try self.block();
            return self.addStatement(.{ .span = .join(first.span, self.syntax.statements.items[@backingInt(body)].span), .data = .{ .loop = .{ .condition = condition, .body = body } } });
        }
        var implicit_discard = false;
        const data: @FieldType(ast.Statement, "data") = switch (first.tag) {
            .kw_pass => no_op: {
                self.cursor.pos += 1;
                break :no_op .{ .block = &.{} };
            },
            .kw_assert => check: {
                self.cursor.pos += 1;
                const condition = try self.expression(0);
                var message = self.src.text(self.syntax.nodes.items[@backingInt(condition)].span);
                var literal: ?Span = null;
                if (self.take(.comma)) {
                    const quoted = try self.expect(.bytes);
                    literal = quoted.span;
                    message = try byte_literal.decode(self.arena.allocator(), self.src, quoted.span, self.sink);
                }
                break :check .{ .assertion = .{ .condition = condition, .message = message, .literal = literal } };
            },
            .kw_break, .kw_continue => exit: {
                self.cursor.pos += 1;
                break :exit .{ .loop_exit = first.tag == .kw_continue };
            },
            .kw_return => ret: {
                self.cursor.pos += 1;
                break :ret .{ .ret = if (self.current().tag == .semicolon or lex.implicitTerminator(self.src.bytes, self.tokens, self.cursor.pos)) try self.append(.{ .span = first.span, .data = .unit }) else try self.expression(0) };
            },
            .ident => assignment: {
                if (self.tokens[self.cursor.pos + 1].tag == .colon and self.tokens[self.cursor.pos + 2].tag != .colon) {
                    self.cursor.pos += 2;
                    const annotation = try self.typeName();
                    _ = try self.expect(.equal);
                    break :assignment .{ .binding = .{ .name = first.span, .mutable = true, .annotation = annotation, .value = try self.expression(0) } };
                }
                // `_ = value` is the only spelling that drops a value.
                if (std.mem.eql(u8, self.src.text(first.span), "_") and self.tokens[self.cursor.pos + 1].tag == .equal) {
                    self.cursor.pos += 2;
                    break :assignment .{ .discard = try self.expression(0) };
                }
                const operator = self.tokens[self.cursor.pos + 1];
                const op: ast.AssignmentOp = assignmentOperation(operator.tag) orelse {
                    implicit_discard = true;
                    break :assignment .{ .discard = try self.assignmentExpression() };
                };
                self.cursor.pos += 2;
                break :assignment .{ .assignment = .{ .name = first.span, .value = try self.expression(0), .op = op, .op_span = operator.span } };
            },
            else => expression: {
                implicit_discard = true;
                break :expression .{ .discard = try self.expression(0) };
            },
        };
        const end = try self.expect(.semicolon);
        return self.addStatement(.{ .span = .join(first.span, end.span), .implicit_discard = implicit_discard, .data = data });
    }
    /// Recognize `range(end)` or `range(start, end)` as an iteration source and return its
    /// half-open bounds, using a unit sentinel for the implicit zero start. A `for` loop and
    /// a list comprehension share this so both accept exactly the same range spellings.
    fn rangeBounds(self: *Parser, input: ast.NodeId) diagnostic.Error!?struct { start: ast.NodeId, end: ast.NodeId } {
        const node = self.syntax.nodes.items[@backingInt(input)];
        if (node.data != .call or node.data.call.owner != null) return null;
        const call = node.data.call;
        if (!std.mem.eql(u8, self.src.text(call.name), "range")) return null;
        if (call.arguments.len < 1 or call.arguments.len > 2) return self.sink.fail("E_ARITY", node.span, "range requires end or start, end");
        // Unit is an internal zero sentinel, avoiding fabricated source text.
        return .{
            .start = if (call.arguments.len == 2) call.arguments[0] else try self.append(.{ .span = call.name, .data = .unit }),
            .end = call.arguments[call.arguments.len - 1],
        };
    }
    fn forStatement(self: *Parser, first: lex.Token) diagnostic.Error!ast.StatementId {
        const first_name = (try self.expect(.ident)).span;
        const second_name = if (self.take(.comma)) (try self.expect(.ident)).span else null;
        _ = try self.expect(.kw_in);
        const input = try self.conditionExpression();
        var start: ?ast.NodeId = null;
        var end: ?ast.NodeId = null;
        var iterable = input;
        if (try self.rangeBounds(input)) |bounds| {
            start = bounds.start;
            end = bounds.end;
        } else {
            const node = self.syntax.nodes.items[@backingInt(input)];
            if (node.data == .call and node.data.call.owner == null and std.mem.eql(u8, self.src.text(node.data.call.name), "enumerate")) {
                const call = node.data.call;
                if (call.arguments.len != 1 or second_name == null) return self.sink.fail("E_ARITY", node.span, "enumerate requires one iterable and two iteration names");
                iterable = call.arguments[0];
            } else if (node.data == .call and node.data.call.owner == null and std.mem.eql(u8, self.src.text(node.data.call.name), "zip")) {
                const call = node.data.call;
                if (call.arguments.len != 2 or second_name == null) return self.sink.fail("E_ARITY", node.span, "zip requires two iterables and two iteration names");
            } else if (second_name != null and node.data == .call and node.data.call.owner != null and std.mem.eql(u8, self.src.text(node.data.call.name), "items")) {
                // `for position, value in d.items()` consumes the value snapshot
                // that `items` produces; the first name receives the position.
            } else if (second_name != null and node.data == .method_call and std.mem.eql(u8, self.src.text(node.data.method_call.name), "items")) {
                // The same form when the receiver is a postfix expression.
            } else if (second_name != null) return self.sink.fail(eIteration, node.span, "two iteration names require enumerate or zip");
        }
        const body = try self.block();
        const span: Span = .join(first.span, self.syntax.statements.items[@backingInt(body)].span);
        if (start) |range_start| {
            if (second_name != null) return self.sink.fail(eIteration, span, "range requires one iteration name");
            return self.addStatement(.{ .span = span, .data = .{ .for_range = .{ .name = first_name, .start = range_start, .end = end.?, .body = body } } });
        }
        return self.addStatement(.{ .span = span, .data = .{ .for_each = .{ .name = second_name orelse first_name, .index_name = if (second_name != null) first_name else null, .iterable = iterable, .body = body } } });
    }
    fn assignmentExpression(self: *Parser) diagnostic.Error!ast.NodeId {
        const value = try self.expression(0);
        const operator = self.current();
        const op = assignmentOperation(operator.tag) orelse return value;
        self.cursor.pos += 1;
        const target = self.syntax.nodes.items[@backingInt(value)];
        if (target.data == .field) {
            if (op != .set) return self.sink.fail("E_ASSIGNMENT_TARGET", operator.span, "augmented assignment to a record field is not supported; write the field out in full");
            const assigned = try self.expression(0);
            return self.append(.{ .span = .join(target.span, self.syntax.nodes.items[@backingInt(assigned)].span), .data = .{ .field_assignment = .{ .target = value, .value = assigned } } });
        }
        if (target.data != .index) return self.sink.fail("E_ASSIGNMENT_TARGET", target.span, "indexed assignment requires a list binding and index");
        if (op != .set) {
            const assigned = try self.expression(0);
            return self.append(.{ .span = .join(target.span, self.syntax.nodes.items[@backingInt(assigned)].span), .data = .{ .index_assignment = .{ .target = value, .op = op, .value = assigned } } });
        }
        const arguments = try self.arena.allocator().alloc(ast.NodeId, 2);
        arguments[0] = target.data.index.index;
        arguments[1] = try self.expression(0);
        return self.append(.{ .span = .join(target.span, self.syntax.nodes.items[@backingInt(arguments[1])].span), .data = .{ .list_operation = .{ .kind = .write, .base = target.data.index.base, .arguments = arguments } } });
    }

    /// Map an assignment operator token, or null when the statement is an expression.
    fn assignmentOperation(tag: lex.Tag) ?ast.AssignmentOp {
        return switch (tag) {
            .equal => .set,
            .plus_equal => .add,
            .minus_equal => .sub,
            .star_equal => .mul,
            .slash_equal => .div,
            .slash_slash_equal => .floor_div,
            .percent_equal => .rem,
            else => null,
        };
    }

    fn append(self: *Parser, node: ast.Node) diagnostic.Error!ast.NodeId {
        const id: ast.NodeId = @fromBackingInt(self.syntax.nodes.items.len);
        try self.syntax.nodes.append(self.arena.allocator(), node);
        return id;
    }
    fn expression(self: *Parser, min_precedence: u8) diagnostic.Error!ast.NodeId {
        try self.enter();
        defer self.cursor.depth -= 1;
        const token = self.current();
        var left: ast.NodeId = switch (token.tag) {
            .kw_restrict_resource => try self.parseRestrict(token),
            .kw_read_resource, .kw_write_resource => try self.parseResourceIo(token),
            .kw_environment_get => try self.parseEnvironment(token),
            .kw_acquire_resource, .kw_complete_resource => try self.parseResource(token),
            .kw_clock_now, .kw_random_u64 => external: {
                self.cursor.pos += 1;
                _ = try self.expect(.lbracket);
                const ty = try self.typeName();
                _ = try self.expect(.rbracket);
                _ = try self.expect(.lparen);
                const capability = try self.expression(0);
                const close = try self.expect(.rparen);
                break :external try self.append(.{ .span = .join(token.span, close.span), .data = .{ .external_read = .{ .kind = if (token.tag == .kw_clock_now) .clock else .random, .ty = ty, .capability = capability } } });
            },
            .kw_f64_add,
            .kw_f64_sub,
            .kw_f64_mul,
            .kw_f64_div,
            .kw_f64_eq,
            .kw_f64_lt,
            .kw_f64_le,
            .kw_bit_and,
            .kw_bit_or,
            .kw_bit_xor,
            .kw_shift_left,
            .kw_shift_right,
            .kw_wrapping_add,
            .kw_wrapping_sub,
            .kw_wrapping_mul,
            .kw_saturating_add,
            .kw_saturating_sub,
            .kw_saturating_mul,
            => try self.parseIntegerOperation(token),
            .kw_f64_sqrt, .kw_f64_floor, .kw_f64_ceil, .kw_f64_trunc, .kw_f64_abs, .kw_f64_neg, .kw_f64_from_u64, .kw_f64_to_u64 => try self.parseFloatUnary(token),
            .kw_wrap => try self.parseWrap(token),
            .kw_i8, .kw_i16, .kw_i32, .kw_i64, .kw_u8, .kw_u16, .kw_u32, .kw_u64 => try self.parseWidthConversion(token),
            .lbracket => list: {
                _ = self.take(.lbracket);
                var values: std.ArrayList(ast.NodeId) = .empty;
                if (self.current().tag != .rbracket) while (true) {
                    try values.append(self.arena.allocator(), try self.expression(0));
                    if (values.items.len == 1 and self.current().tag == .kw_for) break :list try self.parseComprehension(token, values.items[0]);
                    if (!self.take(.comma) or self.current().tag == .rbracket) break;
                };
                const close = try self.expect(.rbracket);
                break :list try self.append(.{ .span = .join(token.span, close.span), .data = .{ .list_literal = try values.toOwnedSlice(self.arena.allocator()) } });
            },
            .kw_len, .kw_replace => if (self.declaresFunction(token.span)) try self.parseLeaf(token) else try self.parseBuiltin(token),
            .kw_unwrap => try self.parseBuiltin(token),
            .kw_todo => try self.parseHole(token),
            .kw_codec_encode, .kw_codec_decode => try self.parseCodecOperation(token),
            .kw_none => none: {
                self.cursor.pos += 1;
                break :none try self.append(.{ .span = token.span, .data = .unit });
            },
            .format => try self.parseFormat(token),
            .lbrace => try self.parseDictionary(token),
            .integer, .bytes, .ident, .kw_true, .kw_false => try self.parseLeaf(token),
            .minus, .bang => unary: {
                self.cursor.pos += 1;
                const operand = try self.expression(if (std.mem.eql(u8, self.src.text(token.span), "not")) 3 else 7);
                break :unary try self.append(.{
                    .span = .join(token.span, self.syntax.nodes.items[@backingInt(operand)].span),
                    .data = .{ .unary = .{
                        .op = if (token.tag == .minus) .neg else .not,
                        .operand = operand,
                        .op_span = token.span,
                    } },
                });
            },
            .lparen => group: {
                _ = self.take(.lparen);
                if (self.take(.rparen)) break :group try self.append(.{ .span = .join(token.span, self.tokens[self.cursor.pos - 1].span), .data = .unit });
                const inner = try self.expression(0);
                const close = try self.expect(.rparen);
                self.syntax.nodes.items[@backingInt(inner)].span = .join(token.span, close.span);
                break :group inner;
            },
            else => return self.sink.fail("E_EXPRESSION", token.span, "expected an expression"),
        };
        while (true) {
            if (self.cursor.delimiters == 0 and self.current().tag != .dedent and self.current().tag != .eof) {
                if (lex.implicitTerminator(self.src.bytes, self.tokens, self.cursor.pos)) break;
            }
            if (self.take(.question)) {
                left = try self.append(.{ .span = .join(self.syntax.nodes.items[@backingInt(left)].span, self.tokens[self.cursor.pos - 1].span), .data = .{ .propagate = left } });
                continue;
            }
            if (self.take(.lbracket)) {
                const start = if (self.current().tag == .colon) null else try self.expression(0);
                if (self.take(.colon)) {
                    const end = if (self.current().tag == .rbracket or self.current().tag == .colon) null else try self.expression(0);
                    const step = if (self.take(.colon)) (if (self.current().tag == .rbracket) null else try self.expression(0)) else null;
                    const close = try self.expect(.rbracket);
                    left = try self.append(.{ .span = .join(self.syntax.nodes.items[@backingInt(left)].span, close.span), .data = .{ .slice = .{ .base = left, .start = start, .end = end, .step = step } } });
                } else {
                    const close = try self.expect(.rbracket);
                    left = try self.append(.{ .span = .join(self.syntax.nodes.items[@backingInt(left)].span, close.span), .data = .{ .index = .{ .base = left, .index = start.? } } });
                }
                continue;
            }
            if (self.take(.dot)) {
                left = try self.parseMemberSuffix(left);
                continue;
            }
            if (try self.parseMembership(left, min_precedence)) |membership| {
                left = membership;
                continue;
            }
            const op = self.current();
            const precedence = binaryPrecedence(op.tag) orelse break;
            if (precedence < min_precedence) break;
            self.cursor.pos += 1;
            const right = try self.expression(precedence + 1);
            left = try self.append(.{ .span = .join(self.syntax.nodes.items[@backingInt(left)].span, self.syntax.nodes.items[@backingInt(right)].span), .data = .{ .binary = .{
                .op = binaryOperator(op.tag),
                .left = left,
                .right = right,
                .op_span = op.span,
            } } });
        }
        return left;
    }
    fn parseMemberSuffix(self: *Parser, left: ast.NodeId) diagnostic.Error!ast.NodeId {
        const name: lex.Token = .{ .tag = .ident, .span = try self.declaredName() };
        if (self.take(.lparen)) {
            var arguments: std.ArrayList(ast.NodeId) = .empty;
            if (self.current().tag != .rparen) while (true) {
                try arguments.append(self.arena.allocator(), try self.expression(0));
                if (!self.take(.comma) or self.current().tag == .rparen) break;
            };
            const close = try self.expect(.rparen);
            return self.append(.{
                .span = .join(self.syntax.nodes.items[@backingInt(left)].span, close.span),
                .data = .{ .method_call = .{ .base = left, .name = name.span, .arguments = try arguments.toOwnedSlice(self.arena.allocator()) } },
            });
        } else return self.append(.{ .span = .join(self.syntax.nodes.items[@backingInt(left)].span, name.span), .data = .{ .field = .{ .base = left, .name = name.span } } });
    }
    fn binaryOperator(tag: lex.Tag) ast.BinaryOp {
        return switch (tag) {
            .plus => .add,
            .minus => .sub,
            .star => .mul,
            .slash => .python_div,
            .slash_slash => .floor_div,
            .percent => .floor_rem,
            .and_and => .logical_and,
            .or_or => .logical_or,
            .eq_eq => .eq,
            .bang_eq => .ne,
            .lt => .lt,
            .le => .le,
            .gt => .gt,
            .ge => .ge,
            else => unreachable,
        };
    }
    fn parseMembership(self: *Parser, left: ast.NodeId, precedence: u8) diagnostic.Error!?ast.NodeId {
        const not_in = self.current().tag == .bang and self.cursor.pos + 1 < self.tokens.len and self.tokens[self.cursor.pos + 1].tag == .kw_in;
        if (precedence > 3 or (self.current().tag != .kw_in and !not_in)) return null;
        self.cursor.pos += if (not_in) @as(usize, 2) else 1;
        const container = try self.expression(4);
        const span = Span.join(self.syntax.nodes.items[@backingInt(left)].span, self.syntax.nodes.items[@backingInt(container)].span);
        const result = try self.append(.{ .span = span, .data = .{ .membership = .{ .needle = left, .container = container, .negate = not_in } } });
        return result;
    }
    /// Parse the tail of `[value for name in iterable if condition]` after its value.
    fn parseComprehension(self: *Parser, token: lex.Token, output: ast.NodeId) diagnostic.Error!ast.NodeId {
        _ = try self.expect(.kw_for);
        const name = try self.expect(.ident);
        _ = try self.expect(.kw_in);
        const input = try self.expression(0);
        const filter = if (self.take(.kw_if)) try self.expression(0) else null;
        const close = try self.expect(.rbracket);
        const src: ast.Comprehension.Source = if (try self.rangeBounds(input)) |bounds|
            .{ .range = .{ .start = bounds.start, .end = bounds.end } }
        else
            .{ .iterable = input };
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .comprehension = .{
            .output = output,
            .name = name.span,
            .source = src,
            .filter = filter,
        } } });
    }

    /// Build `f"a{x}b"` as its alternating literal and interpolated pieces.
    /// Each hole is tokenized from the original bytes, so its spans stay absolute.
    fn parseFormat(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        const allocator = self.arena.allocator();
        const pieces = try format_strings.split(allocator, self.src, token.span, self.sink);
        var parts: std.ArrayList(ast.NodeId) = .empty;
        for (pieces) |piece| switch (piece) {
            .literal => |span| try parts.append(allocator, try self.formatLiteral(span)),
            .brace => |span| try parts.append(allocator, try self.append(.{ .span = span, .data = .{ .text = self.src.bytes[span.start .. span.start + 1] } })),
            .hole => |span| try parts.append(allocator, try self.formatHole(span)),
        };
        return self.append(.{ .span = token.span, .data = .{ .format = try parts.toOwnedSlice(allocator) } });
    }

    /// Decode one literal chunk with the ordinary escapes by lending it surrounding quotes.
    fn formatLiteral(self: *Parser, span: Span) diagnostic.Error!ast.NodeId {
        const quoted: Span = .{ .start = span.start - 1, .end = span.end + 1 };
        const decoded = try byte_literal.decode(self.arena.allocator(), self.src, quoted, self.sink);
        return self.append(.{ .span = span, .data = .{ .text = decoded } });
    }

    /// Parse one interpolation as an ordinary expression over its own token range.
    fn formatHole(self: *Parser, span: Span) diagnostic.Error!ast.NodeId {
        const tokens = try lex.lexRange(self.arena.allocator(), self.src.bytes, span, self.sink);
        const outer = self.tokens;
        const position = self.cursor.pos;
        const delimiters = self.cursor.delimiters;
        self.tokens = tokens;
        self.cursor.pos = 0;
        self.cursor.delimiters += 1;
        defer {
            self.tokens = outer;
            self.cursor.pos = position;
            self.cursor.delimiters = delimiters;
        }
        const value = try self.expression(0);
        if (self.current().tag != .eof) return self.sink.fail(
            format_strings.code,
            self.current().span,
            "a format string interpolation holds exactly one expression",
        );
        return value;
    }

    fn parseDictionary(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.delimiters += 1;
        defer self.cursor.delimiters -= 1;

        self.cursor.pos += 1;
        var entries: std.ArrayList(ast.NodeId) = .empty;
        while (self.current().tag != .rbrace) {
            try entries.append(self.arena.allocator(), try self.expression(0));
            _ = try self.expect(.colon);
            try entries.append(self.arena.allocator(), try self.expression(0));
            if (!self.take(.comma)) break;
        }
        const close = try self.expect(.rbrace);
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .dictionary_literal = try entries.toOwnedSlice(self.arena.allocator()) } });
    }
    fn parseRestrict(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        _ = try self.expect(.lbracket);
        var permissions: external_resources.Permissions = 0;
        if (self.current().tag != .rbracket) while (true) {
            const name = try self.expect(.ident);
            const permission = std.meta.stringToEnum(external_resources.Permission, self.src.text(name.span)) orelse return self.sink.fail("E_PERMISSION", name.span, "permission must be read, write, or complete");
            const bit = external_resources.permissionBit(permission);
            if (permissions & bit != 0) return self.sink.fail("E_PERMISSION", name.span, "permission is repeated");
            permissions |= bit;
            if (!self.take(.comma)) break;
        };
        _ = try self.expect(.rbracket);
        _ = try self.expect(.lparen);
        const value = try self.expression(0);
        const close = try self.expect(.rparen);
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .restrict_resource = .{ .permissions = permissions, .value = value } } });
    }

    fn parseResourceIo(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        _ = try self.expect(.lbracket);
        const ty = try self.typeName();
        _ = try self.expect(.rbracket);
        _ = try self.expect(.lparen);
        const owner = try self.expect(.ident);
        const value = if (token.tag == .kw_write_resource) value: {
            _ = try self.expect(.comma);
            break :value try self.expression(0);
        } else null;
        const close = try self.expect(.rparen);
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .resource_io = .{ .kind = if (token.tag == .kw_read_resource) .read else .write, .owner = owner.span, .ty = ty, .value = value } } });
    }

    fn parseEnvironment(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        _ = try self.expect(.lbracket);
        const ty = try self.typeName();
        _ = try self.expect(.rbracket);
        _ = try self.expect(.lparen);
        const capability = try self.expression(0);
        _ = try self.expect(.comma);
        const name = try self.expression(0);
        const close = try self.expect(.rparen);
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .environment_get = .{ .ty = ty, .capability = capability, .name = name } } });
    }

    fn parseResource(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        _ = try self.expect(.lbracket);
        const ty = try self.typeName();
        _ = try self.expect(.rbracket);
        _ = try self.expect(.lparen);
        const first = try self.expression(0);
        const request = if (token.tag == .kw_acquire_resource) request: {
            _ = try self.expect(.comma);
            break :request try self.expression(0);
        } else first;
        const close = try self.expect(.rparen);
        return self.append(.{
            .span = .join(token.span, close.span),
            .data = if (token.tag == .kw_acquire_resource) .{ .acquire_resource = .{
                .ty = ty,
                .capability = first,
                .request = request,
            } } else .{ .complete_resource = .{
                .ty = ty,
                .value = first,
            } },
        });
    }

    fn parseWrap(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        _ = try self.expect(.lbracket);
        const ty = try self.typeName();
        _ = try self.expect(.rbracket);
        _ = try self.expect(.lparen);
        const value = try self.expression(0);
        const close = try self.expect(.rparen);
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .wrap = .{ .ty = ty, .value = value } } });
    }

    /// `i64(x)` and its siblings convert between integer widths with a runtime range
    /// check, the way `int(x)` and `float(x)` convert between the numeric types.
    fn parseWidthConversion(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        _ = try self.expect(.lparen);
        const value = try self.expression(0);
        const close = try self.expect(.rparen);
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .cast = .{ .ty = token.span, .value = value } } });
    }

    fn parseFloatUnary(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        _ = try self.expect(.lparen);
        const operand = try self.expression(0);
        const close = try self.expect(.rparen);
        const op = std.meta.stringToEnum(ast.UnaryOp, @tagName(token.tag)[3..]).?;
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .unary = .{
            .op = op,
            .operand = operand,
            .op_span = token.span,
        } } });
    }
    fn parseIntegerOperation(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        _ = try self.expect(.lparen);
        const left = try self.expression(0);
        _ = try self.expect(.comma);
        const right = try self.expression(0);
        const close = try self.expect(.rparen);
        const op = std.meta.stringToEnum(ast.BinaryOp, @tagName(token.tag)[3..]).?;
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .binary = .{
            .op = op,
            .left = left,
            .right = right,
            .op_span = token.span,
        } } });
    }
    fn parseBuiltin(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        _ = try self.expect(.lparen);
        const base = try self.expression(0);
        if (token.tag != .kw_replace) {
            const close = try self.expect(.rparen);
            return self.append(.{ .span = .join(token.span, close.span), .data = if (token.tag == .kw_len) .{ .length = base } else .{ .unwrap = base } });
        }
        _ = try self.expect(.comma);
        const index = try self.expression(0);
        _ = try self.expect(.comma);
        const value = try self.expression(0);
        const close = try self.expect(.rparen);
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .replace = .{ .base = base, .index = index, .value = value } } });
    }

    fn methodSuffix(self: *Parser) bool {
        if (self.current().tag != .dot) return false;
        if (self.cursor.pos + 2 >= self.tokens.len) return false;
        const member = self.tokens[self.cursor.pos + 1].tag;
        if (member != .ident and member != .kw_len and member != .kw_replace) return false;
        return self.tokens[self.cursor.pos + 2].tag == .lparen;
    }

    fn parseHole(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        _ = try self.expect(.lbracket);
        const types = try self.arena.allocator().alloc(Span, 1);
        types[0] = try self.typeName();
        _ = try self.expect(.rbracket);
        _ = try self.expect(.lparen);
        const close = try self.expect(.rparen);
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .call = .{
            .name = token.span,
            .type_arguments = types,
            .arguments = &.{},
        } } });
    }
    fn parseCodecOperation(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        if (!self.take(.lbracket)) return self.sink.fail("E_CODEC_ARITY", token.span, "codec operation requires one explicit domain type");
        const types = try self.arena.allocator().alloc(Span, 1);
        types[0] = try self.typeName();
        _ = try self.expect(.rbracket);
        _ = try self.expect(.lparen);
        var arguments: std.ArrayList(ast.NodeId) = .empty;
        if (self.current().tag != .rparen) while (true) {
            try arguments.append(self.arena.allocator(), try self.expression(0));
            if (!self.take(.comma) or self.current().tag == .rparen) break;
        };
        const close = try self.expect(.rparen);
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .call = .{
            .name = token.span,
            .type_arguments = types,
            .arguments = try arguments.toOwnedSlice(self.arena.allocator()),
        } } });
    }
    const Pattern = struct { ty: Span, name: Span, binding: ?Span = null, discard_payload: bool = false };
    fn matchPattern(self: *Parser) diagnostic.Error!Pattern {
        const head = self.current();
        const first = if (self.take(.kw_none)) head.span else try self.nominalTypeName();
        const contextual = self.current().tag != .dot;
        var pattern: Pattern = .{
            .ty = if (contextual) .{ .start = first.start, .end = first.start } else first,
            .name = first,
        };
        if (!contextual) {
            _ = try self.expect(.dot);
            pattern.name = (try self.expect(.ident)).span;
        }
        if (self.take(.lparen)) {
            const binding = (try self.expect(.ident)).span;
            if (std.mem.eql(u8, self.src.text(binding), "_")) pattern.discard_payload = true else pattern.binding = binding;
            _ = try self.expect(.rparen);
        }
        return pattern;
    }
    fn sameExpressionLine(self: *Parser) bool {
        return self.cursor.delimiters != 0 or self.cursor.pos == 0 or std.mem.indexOfScalar(u8, self.src.bytes[self.tokens[self.cursor.pos - 1].span.end..self.current().span.start], '\n') == null;
    }
    /// Recognize `Ident[...](…)`, a square-bracket type application applied to arguments.
    /// A dot after the closing bracket makes the head an ordinary index and member access
    /// instead, because `items[at].append(v)` and `Box[T](v)` are otherwise indistinguishable.
    fn appliedConstructorAhead(self: *Parser) bool {
        var position = self.cursor.pos;
        var brackets: usize = 0;
        var applied = false;
        while (position + 2 < self.tokens.len) : (position += 1) {
            if (position > self.cursor.pos and brackets == 0 and std.mem.indexOfScalar(u8, self.src.bytes[self.tokens[position - 1].span.end..self.tokens[position].span.start], '\n') != null) return false;
            if (self.tokens[position].tag == .lbracket) {
                brackets += 1;
                applied = true;
            }
            if (self.tokens[position].tag == .rbracket) brackets -|= 1;
            switch (self.tokens[position].tag) {
                .dot => if (applied and brackets == 0) return false,
                .comma, .colon => if (brackets == 0) return false,
                .lparen => return applied and brackets == 0,
                else => if (!typeArgumentToken(self.tokens[position].tag)) return false,
            }
        }
        return false;
    }
    const Arguments = struct { values: []const ast.NodeId, names: []const ?Span };
    fn callArguments(self: *Parser) diagnostic.Error!Arguments {
        var values: std.ArrayList(ast.NodeId) = .empty;
        var names: std.ArrayList(?Span) = .empty;
        var keyword_seen = false;
        if (self.current().tag != .rparen) while (true) {
            const named = self.current().tag == .ident or self.current().tag == .kw_len or self.current().tag == .kw_replace;
            const keyword = named and self.tokens[self.cursor.pos + 1].tag == .equal;
            const name = if (keyword) self.current().span else null;
            if (keyword) self.cursor.pos += 2;
            if (keyword_seen and !keyword) return self.sink.fail("E_CALL_ARGUMENT", self.current().span, "positional arguments must precede keyword arguments");
            keyword_seen = keyword_seen or keyword;
            try names.append(self.arena.allocator(), name);
            try values.append(self.arena.allocator(), try self.expression(0));
            if (!self.take(.comma) or self.current().tag == .rparen) break;
        };
        return .{ .values = try values.toOwnedSlice(self.arena.allocator()), .names = if (keyword_seen) try names.toOwnedSlice(self.arena.allocator()) else &.{} };
    }
    /// Recognize `Owner.name[T](…)`, a member call carrying explicit type arguments.
    /// The applied-constructor lookahead cannot claim it, because `Owner.name` names a
    /// function rather than a type. One `alias.name` pair is excluded: an import alias
    /// joins into a single qualified name, so `m.f[T](x)` resolves as an ordinary call.
    fn memberApplicationAhead(self: *Parser) bool {
        var position = self.cursor.pos;
        if (self.tokens[position].tag != .ident) return false;
        var segments: usize = 1;
        while (position + 2 < self.tokens.len and self.tokens[position + 1].tag == .dot) {
            const member = self.tokens[position + 2].tag;
            if (member != .ident and member != .kw_len and member != .kw_replace) break;
            segments += 1;
            position += 2;
        }
        if (segments < 2) return false;
        if (segments == 2 and self.module_syntax and self.syntax.import_aliases.contains(self.src.text(self.current().span))) return false;
        position += 1;
        if (position >= self.tokens.len or self.tokens[position].tag != .lbracket) return false;
        var brackets: usize = 0;
        while (position < self.tokens.len) : (position += 1) {
            switch (self.tokens[position].tag) {
                .lbracket => brackets += 1,
                .rbracket => {
                    brackets -= 1;
                    if (brackets == 0) return position + 1 < self.tokens.len and self.tokens[position + 1].tag == .lparen;
                },
                .comma, .dot => {},
                else => if (!typeArgumentToken(self.tokens[position].tag)) return false,
            }
        }
        return false;
    }

    /// One `[A, B]` list of explicit call type arguments.
    fn squareTypeArguments(self: *Parser) diagnostic.Error![]const Span {
        _ = try self.expect(.lbracket);
        var arguments: std.ArrayList(Span) = .empty;
        while (true) {
            const argument = try self.genericArgument();
            if (arguments.items.len == 16) return self.sink.fail(eGenericLimit, argument, "at most 16 type arguments are permitted");
            try arguments.append(self.arena.allocator(), argument);
            if (!self.take(.comma)) break;
        }
        _ = try self.expect(.rbracket);
        return arguments.toOwnedSlice(self.arena.allocator());
    }

    fn parseLeaf(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        if (token.tag == .ident and self.memberApplicationAhead()) {
            var segments: std.ArrayList(Span) = .empty;
            try segments.append(self.arena.allocator(), (try self.expect(.ident)).span);
            while (self.take(.dot)) try segments.append(self.arena.allocator(), try self.declaredName());
            const member = segments.items[segments.items.len - 1];
            const owner = Span.join(segments.items[0], segments.items[segments.items.len - 2]);
            const type_arguments = try self.squareTypeArguments();
            _ = try self.expect(.lparen);
            const arguments = try self.callArguments();
            const close = try self.expect(.rparen);
            return self.append(.{ .span = .join(token.span, close.span), .data = .{ .call = .{
                .owner = owner,
                .type_arguments = type_arguments,
                .name = member,
                .arguments = arguments.values,
                .argument_names = arguments.names,
            } } });
        }
        if (token.tag == .ident and self.appliedConstructorAhead()) {
            const name = try self.typeName();
            _ = try self.expect(.lparen);
            const arguments = try self.callArguments();
            const close = try self.expect(.rparen);
            return self.append(.{ .span = .join(token.span, close.span), .data = .{ .call = .{ .name = name, .arguments = arguments.values, .argument_names = arguments.names } } });
        }
        self.cursor.pos += 1;
        var owner: ?Span = null;
        var name = if (token.tag == .ident) try self.qualifiedTail(token.span) else token.span;
        if (token.tag == .ident and self.sameExpressionLine() and self.methodSuffix()) {
            owner = name;
            self.cursor.pos += 1;
            name = try self.declaredName();
        }
        const callable_name = token.tag == .ident or token.tag == .kw_len or token.tag == .kw_replace;
        if (callable_name and self.sameExpressionLine() and self.take(.lparen)) {
            const arguments = try self.callArguments();
            const close = try self.expect(.rparen);
            return self.append(.{ .span = .join(token.span, close.span), .data = .{ .call = .{ .owner = owner, .name = name, .arguments = arguments.values, .argument_names = arguments.names } } });
        }
        return self.append(.{ .span = name, .data = switch (token.tag) {
            .integer => .{ .integer = token.span },
            .bytes => literal: {
                const decoded = try byte_literal.decode(self.arena.allocator(), self.src, token.span, self.sink);
                break :literal if (self.src.text(token.span)[0] != 'b') .{ .text = decoded } else .{ .bytes = decoded };
            },
            .ident, .kw_len, .kw_replace => .{ .name = name },
            else => .{ .boolean = token.tag == .kw_true },
        } });
    }
};

fn binaryPrecedence(tag: lex.Tag) ?u8 {
    return switch (tag) {
        .or_or => 1,
        .and_and => 2,
        .eq_eq, .bang_eq => 3,
        .lt, .le, .gt, .ge => 4,
        .plus, .minus => 5,
        .star, .slash, .slash_slash, .percent => 6,
        else => null,
    };
}
