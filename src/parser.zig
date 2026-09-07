//! Recursive descent for statements; precedence climbing for expressions.
const syntax_code = "E_SYNTAX";
const eRequirement = diagnostic.generic_requirement;
const eGenericLimit = diagnostic.generic_limit;
const external_resources = @import("external_resources.zig");
const std = @import("std");
const effects = @import("effect_set.zig");
const ast = @import("ast.zig");
const lex = @import("lexer.zig");
const Span = @import("source.zig").Span;
const diagnostic = @import("diagnostic.zig");
/// Token cursor and allocator-backed syntax builder with bounded recursive nesting.
pub const Parser = struct {
    src: @import("source.zig").Source,
    arena: *std.heap.ArenaAllocator,
    tokens: []const lex.Token,
    sink: *diagnostic.Sink,
    cursor: struct { pos: usize = 0, depth: usize = 0, equal_tail: ?usize = null } = .{},
    module_syntax: bool = false,
    syntax: struct {
        nodes: std.ArrayList(ast.Node) = .empty,
        statements: std.ArrayList(ast.Statement) = .empty,
        array_types: std.ArrayList(ast.ArrayType) = .empty,
        applications: std.ArrayList(ast.TypeApplication) = .empty,
        aliases: std.ArrayList(ast.TypeAlias) = .empty,
    } = .{},
    fn current(self: *Parser) lex.Token {
        const token = self.tokens[self.cursor.pos];
        if (self.cursor.equal_tail == self.cursor.pos) return .{ .tag = .equal, .span = .{ .start = token.span.start + 1, .end = token.span.end } };
        return token;
    }
    fn take(self: *Parser, tag: lex.Tag) bool {
        if (self.current().tag != tag) return false;
        self.cursor.pos += 1;
        return true;
    }
    fn expect(self: *Parser, comptime tag: lex.Tag) diagnostic.Error!lex.Token {
        const token = self.current();
        if (!self.take(tag)) return self.sink.fail(syntax_code, token.span, "unexpected token; expected " ++ @tagName(tag));
        return token;
    }
    fn enter(self: *Parser) diagnostic.Error!void {
        if (self.cursor.depth >= 256) return self.sink.fail("E_NESTING_LIMIT", self.current().span, "parser nesting exceeds 256 levels");
        self.cursor.depth += 1;
    }
    fn qualifiedTail(self: *Parser, first: Span) diagnostic.Error!Span {
        if (!self.module_syntax or self.current().tag != .colon or self.genericCallSuffix()) return first;
        self.cursor.pos += 1;
        _ = try self.expect(.colon);
        return .join(first, (try self.expect(.ident)).span);
    }
    fn typeName(self: *Parser) diagnostic.Error!Span {
        try self.enter();
        defer self.cursor.depth -= 1;
        const token = self.current();
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
            .kw_allocator,
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
    fn nominalTypeName(self: *Parser) diagnostic.Error!Span {
        const token = try self.expect(.ident);
        const name = try self.qualifiedTail(token.span);
        if (!self.take(.lt)) return name;
        var arguments: std.ArrayList(Span) = .empty;
        while (true) {
            const argument = try self.typeName();
            if (arguments.items.len == 16) return self.sink.fail(eGenericLimit, argument, "at most 16 type arguments are permitted");
            try arguments.append(self.arena.allocator(), argument);
            if (!self.take(.comma)) break;
        }
        const close = try self.closeNominalType();
        const span: Span = .join(name, close.span);
        try self.syntax.applications.append(self.arena.allocator(), .{ .span = span, .name = name, .arguments = try arguments.toOwnedSlice(self.arena.allocator()) });
        return span;
    }
    fn closeNominalType(self: *Parser) diagnostic.Error!lex.Token {
        const token = self.current();
        if (token.tag != .ge) return self.expect(.gt);
        self.cursor.equal_tail = self.cursor.pos;
        return .{ .tag = .gt, .span = .{ .start = token.span.start, .end = token.span.start + 1 } };
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
            if (self.take(.kw_as)) _ = try self.expect(.ident);
            _ = try self.expect(.semicolon);
        }
        while (self.current().tag == .ident and std.mem.eql(u8, self.src.text(self.current().span), "export")) {
            self.cursor.pos += 1;
            _ = try self.expect(.ident);
            _ = try self.expect(.semicolon);
        }
        return self.parse();
    }
    fn parseCodec(self: *Parser) diagnostic.Error!ast.Codec {
        const wire = try self.typeName();
        _ = try self.expect(.lbrace);
        var decode: ?Span = null;
        var encode: ?Span = null;
        while (self.current().tag != .rbrace) {
            const key = (try self.expect(.ident)).span;
            const name = self.src.text(key);
            const target = if (std.mem.eql(u8, name, "decode")) &decode else if (std.mem.eql(u8, name, "encode")) &encode else return self.sink.fail("E_CODEC_KEY", key, "codec entries must be decode or encode");
            if (target.* != null) return self.sink.fail("E_DUPLICATE_CODEC_KEY", key, "codec entry is declared more than once");
            _ = try self.expect(.colon);
            target.* = (try self.expect(.ident)).span;
            if (!self.take(.comma)) break;
        }
        const end = (try self.expect(.rbrace)).span;
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
        var pools: std.ArrayList(ast.Pool) = .empty;
        var buffers: std.ArrayList(ast.Domain) = .empty;
        var resources: std.ArrayList(ast.Domain) = .empty;
        var variants: std.ArrayList(ast.Variants) = .empty;
        while (self.current().tag != .eof) {
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
            if (self.current().tag == .ident and std.mem.eql(u8, self.src.text(self.current().span), "pool")) {
                self.cursor.pos += 1;
                const name = try self.expect(.ident);
                const type_parameters = try self.typeParameters();
                _ = try self.expect(.lparen);
                const handle = try self.expect(.ident);
                _ = try self.expect(.rparen);
                _ = try self.expect(.colon);
                const element = try self.typeName();
                _ = try self.expect(.semicolon);
                try pools.append(self.arena.allocator(), .{ .type_parameters = type_parameters, .name = name.span, .handle = handle.span, .element = element });
                continue;
            }
            if (self.current().tag == .ident and std.mem.eql(u8, self.src.text(self.current().span), "buffer")) {
                self.cursor.pos += 1;
                const name = try self.expect(.ident);
                const type_parameters = try self.typeParameters();
                _ = try self.expect(.colon);
                const element = try self.typeName();
                _ = try self.expect(.semicolon);
                try buffers.append(self.arena.allocator(), .{ .type_parameters = type_parameters, .name = name.span, .backing = element });
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
                _ = try self.expect(.lbrace);
                var cases: std.ArrayList(ast.Variant) = .empty;
                if (self.current().tag != .rbrace) while (true) {
                    const tag = try self.expect(.ident);
                    const payload = if (is_union and self.take(.colon)) try self.typeName() else null;
                    try cases.append(self.arena.allocator(), .{ .name = tag.span, .payload = payload });
                    if (!self.take(.comma)) break;
                };
                _ = try self.expect(.rbrace);
                try variants.append(self.arena.allocator(), .{ .type_parameters = type_parameters, .name = name.span, .fallible = fallible, .is_union = is_union, .cases = try cases.toOwnedSlice(self.arena.allocator()) });
                continue;
            }
            if (self.take(.kw_domain)) {
                const name = try self.expect(.ident);
                _ = try self.expect(.colon);
                const backing = try self.typeName();
                _ = try self.expect(.lbrace);
                var codec: ?ast.Codec = null;
                while (self.current().tag != .rbrace) {
                    if (self.current().tag == .ident and std.mem.eql(u8, self.src.text(self.current().span), "codec")) {
                        if (codec != null) return self.sink.fail("E_DUPLICATE_CODEC", self.current().span, "a domain declares at most one codec");
                        self.cursor.pos += 1;
                        codec = try self.parseCodec();
                    } else try functions.append(self.arena.allocator(), try self.function(name.span));
                }
                _ = try self.expect(.rbrace);
                try domains.append(self.arena.allocator(), .{ .name = name.span, .backing = backing, .codec = codec });
                continue;
            }
            if (self.take(.kw_struct)) {
                const name = try self.expect(.ident);
                const type_parameters = try self.typeParameters();
                _ = try self.expect(.lbrace);
                var fields: std.ArrayList(ast.Parameter) = .empty;
                if (self.current().tag != .rbrace) while (true) {
                    const field = try self.expect(.ident);
                    _ = try self.expect(.colon);
                    try fields.append(self.arena.allocator(), .{ .name = field.span, .ty = try self.typeName() });
                    if (!self.take(.comma)) break;
                };
                _ = try self.expect(.rbrace);
                try records.append(self.arena.allocator(), .{ .type_parameters = type_parameters, .name = name.span, .fields = try fields.toOwnedSlice(self.arena.allocator()) });
                continue;
            }
            try functions.append(self.arena.allocator(), try self.function(null));
        }
        return .{
            .types = .{
                .pools = try pools.toOwnedSlice(self.arena.allocator()),
                .resources = try resources.toOwnedSlice(self.arena.allocator()),
                .buffers = try buffers.toOwnedSlice(self.arena.allocator()),
                .variants = try variants.toOwnedSlice(self.arena.allocator()),
                .domains = try domains.toOwnedSlice(self.arena.allocator()),
                .expressions = .{
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
        const host: ?Span = if (self.current().tag == .ident and std.mem.eql(u8, self.src.text(self.current().span), "host")) self.current().span else null;
        if (host != null) self.cursor.pos += 1;
        const restricted = self.take(.kw_private);
        if (restricted and owner == null) return self.sink.fail("E_PRIVATE_SCOPE", self.tokens[self.cursor.pos - 1].span, "private functions must be declared inside a domain");
        const conversion = self.take(.kw_conversion);
        _ = try self.expect(.kw_fn);
        const name = try self.expect(.ident);
        const type_parameters = try self.typeParameters();
        _ = try self.expect(.lparen);
        var parameters: std.ArrayList(ast.Parameter) = .empty;
        if (self.current().tag != .rparen) while (true) {
            const parameter = try self.expect(.ident);
            _ = try self.expect(.colon);
            const reference: ?bool = if (self.take(.ampersand)) self.take(.kw_mut) else null;
            const slice = reference != null and self.current().tag == .lbracket and self.tokens[self.cursor.pos + 1].tag == .rbracket;
            if (slice) {
                self.cursor.pos += 2;
            }
            try parameters.append(self.arena.allocator(), .{ .name = parameter.span, .ty = try self.typeName(), .reference = reference, .slice = slice });
            if (!self.take(.comma)) break;
        };
        _ = try self.expect(.rparen);
        _ = try self.expect(.arrow);
        const reference: ?bool = if (self.take(.ampersand)) self.take(.kw_mut) else null;
        const slice = reference != null and self.current().tag == .lbracket and self.tokens[self.cursor.pos + 1].tag == .rbracket;
        if (slice) self.cursor.pos += 2;
        const return_type = try self.typeName();
        var return_reference: ?ast.ReturnReference = null;
        if (reference) |mutable| {
            const from = try self.expect(.ident);
            if (!std.mem.eql(u8, self.src.text(from.span), "from")) return self.sink.fail("E_RETURN_LIFETIME", from.span, "reference result requires `from` followed by a reference parameter name");
            return_reference = .{ .source = (try self.expect(.ident)).span, .mutable = mutable, .slice = slice };
        }
        if (host) |span| {
            if (owner != null or restricted or conversion) return self.sink.fail("E_HOST_DECLARATION", span, "host declarations must be ordinary top-level functions");
            if (type_parameters.len != 0) return self.sink.fail("E_HOST_DECLARATION", span, "generic host declarations are not supported");
            if (return_reference != null) return self.sink.fail("E_HOST_SIGNATURE", span, "host results must be copied ordinary values");
            for (parameters.items) |parameter| if (parameter.reference != null) return self.sink.fail("E_HOST_SIGNATURE", parameter.name, "host parameters must be copied ordinary values");
            if (self.current().tag != .ident or !std.mem.eql(u8, self.src.text(self.current().span), "effects")) return self.sink.fail("E_HOST_EFFECTS", span, "host declarations require an explicit effects(host, ...) contract");
        }
        const effect_bound = try self.effectBound();
        if (host) |span| if (effect_bound.?.allowed & effects.bit(.host) == 0) return self.sink.fail("E_HOST_EFFECTS", span, "host declarations must include the host effect");
        const body = if (host != null) try self.addStatement(.{ .span = (try self.expect(.semicolon)).span, .data = .{ .block = &.{} } }) else try self.block();
        return .{
            .policy = .{
                .host = host,
                .effect_bound = effect_bound,
                .owner = owner,
                .restricted = restricted,
                .conversion = conversion,
            },
            .signature = .{
                .type_parameters = type_parameters,
                .return_reference = return_reference,
                .parameters = try parameters.toOwnedSlice(self.arena.allocator()),
                .return_type = return_type,
            },
            .name = name.span,
            .body = body,
        };
    }
    fn typeParameters(self: *Parser) diagnostic.Error![]const ast.TypeParameter {
        if (!self.take(.lt)) return &.{};
        var parameters: std.ArrayList(ast.TypeParameter) = .empty;
        while (true) {
            const name = (try self.expect(.ident)).span;
            if (parameters.items.len == 16) return self.sink.fail(eGenericLimit, name, "at most 16 type parameters are permitted");
            for (parameters.items) |previous| if (std.mem.eql(u8, self.src.text(previous.name), self.src.text(name))) return self.sink.fail("E_GENERIC_PARAMETER", name, "duplicate type parameter");
            _ = try self.expect(.colon);
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
                    if (field.reference != null) return self.sink.fail(eRequirement, field.name, "structural fields are copied values, not references");
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
        _ = try self.expect(.gt);
        return parameters.toOwnedSlice(self.arena.allocator());
    }
    fn constraintParameter(self: *Parser) diagnostic.Error!ast.Parameter {
        const name = (try self.expect(.ident)).span;
        _ = try self.expect(.colon);
        const reference: ?bool = if (self.take(.ampersand)) self.take(.kw_mut) else null;
        if (self.current().tag == .lbracket) return self.sink.fail(eRequirement, self.current().span, "structural signatures currently require named types, not arrays or slices");
        return .{ .name = name, .ty = try self.typeName(), .reference = reference };
    }
    fn operationConstraint(self: *Parser) diagnostic.Error!ast.Operation {
        _ = try self.expect(.lparen);
        const name = (try self.expect(.ident)).span;
        _ = try self.expect(.lparen);
        var parameters: std.ArrayList(ast.Parameter) = .empty;
        if (self.current().tag != .rparen) while (true) {
            if (parameters.items.len == 16) return self.sink.fail(eGenericLimit, self.current().span, "at most 16 structural operation parameters are permitted");
            try parameters.append(self.arena.allocator(), try self.constraintParameter());
            if (!self.take(.comma)) break;
        };
        _ = try self.expect(.rparen);
        _ = try self.expect(.arrow);
        if (self.current().tag == .ampersand or self.current().tag == .lbracket) return self.sink.fail(eRequirement, self.current().span, "structural operation results currently require named value types");
        const result = try self.typeName();
        const bound = try self.effectBound() orelse return self.sink.fail(eRequirement, name, "structural operations require an explicit effects bound");
        _ = try self.expect(.rparen);
        return .{ .name = name, .parameters = try parameters.toOwnedSlice(self.arena.allocator()), .return_type = result, .effect_bound = bound };
    }
    fn borrowCallSuffix(self: *Parser) bool {
        return switch (self.current().tag) {
            .lparen, .dot => true,
            .colon => self.module_syntax or self.genericCallSuffix(),
            else => false,
        };
    }
    fn genericCallSuffix(self: *Parser) bool {
        if (self.cursor.pos + 2 >= self.tokens.len) return false;
        return self.current().tag == .colon and self.tokens[self.cursor.pos + 1].tag == .colon and self.tokens[self.cursor.pos + 2].tag == .lt;
    }
    fn typeArguments(self: *Parser) diagnostic.Error![]const Span {
        if (!self.genericCallSuffix()) return &.{};
        self.cursor.pos += 3;
        var arguments: std.ArrayList(Span) = .empty;
        while (true) {
            const argument = try self.typeName();
            if (arguments.items.len == 16) return self.sink.fail(eGenericLimit, argument, "at most 16 type arguments are permitted");
            try arguments.append(self.arena.allocator(), argument);
            if (!self.take(.comma)) break;
        }
        _ = try self.expect(.gt);
        if (self.current().tag != .lparen) return self.sink.fail("E_GENERIC_CALL", self.current().span, "explicit type arguments require a function call");
        return arguments.toOwnedSlice(self.arena.allocator());
    }
    fn effectBound(self: *Parser) diagnostic.Error!?effects.Bound {
        const sets = effects;
        const token = self.current();
        if (token.tag != .ident) return null;
        const spelling = self.src.text(token.span);
        if (std.mem.eql(u8, spelling, "noalloc") or std.mem.eql(u8, spelling, "noio")) {
            self.cursor.pos += 1;
            return .{ .span = token.span, .allowed = sets.all & ~(if (std.mem.eql(u8, spelling, "noalloc")) sets.bit(.allocation) else sets.io) };
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
                "unknown effect; expected allocation, filesystem, network, clock, random, environment, or host",
            );
            if (allowed & sets.bit(effect) != 0) return self.sink.fail("E_DUPLICATE_EFFECT", name.span, "effect appears more than once in this bound");
            allowed |= sets.bit(effect);
            if (!self.take(.comma)) break;
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
        const open = try self.expect(.lbrace);
        var statements: std.ArrayList(ast.StatementId) = .empty;
        while (self.current().tag != .rbrace) {
            if (self.current().tag == .eof) return self.sink.fail(syntax_code, self.current().span, "expected closing brace");
            try statements.append(self.arena.allocator(), try self.statement());
        }
        const close = try self.expect(.rbrace);
        return self.addStatement(.{ .span = .join(open.span, close.span), .data = .{ .block = try statements.toOwnedSlice(self.arena.allocator()) } });
    }
    fn splitBorrow(self: *Parser, first: Span) diagnostic.Error!ast.StatementId {
        const owner = (try self.expect(.ident)).span;
        const at = (try self.expect(.ident)).span;
        if (!std.mem.eql(u8, self.src.text(at), "at")) return self.sink.fail(syntax_code, at, "split requires `at` before its midpoint");
        const middle = try self.expression(0);
        _ = try self.expect(.kw_as);
        const left = (try self.expect(.ident)).span;
        _ = try self.expect(.comma);
        const right = (try self.expect(.ident)).span;
        const body = try self.block();
        return self.addStatement(.{
            .span = .join(first, self.syntax.statements.items[@backingInt(body)].span),
            .data = .{ .borrow = .{ .owner = owner, .name = left, .mutable = true, .body = body, .split = .{ .right = right, .middle = middle } } },
        });
    }
    fn statement(self: *Parser) diagnostic.Error!ast.StatementId {
        try self.enter();
        defer self.cursor.depth -= 1;
        const first = self.current();
        if (first.tag == .lbrace) return self.block();
        if (self.take(.kw_arena)) {
            const parent = try self.expression(0);
            _ = try self.expect(.kw_as);
            const name = try self.expect(.ident);
            const body = try self.block();
            return self.addStatement(.{ .span = .join(first.span, self.syntax.statements.items[@backingInt(body)].span), .data = .{ .arena_scope = .{ .parent = parent, .name = name.span, .body = body } } });
        }
        if (self.take(.kw_split)) return self.splitBorrow(first.span);
        if (self.take(.kw_borrow)) {
            const mutable = self.take(.kw_mut);
            const owner_position = self.cursor.pos;
            const owner = try self.expect(.ident);
            if (self.borrowCallSuffix()) {
                self.cursor.pos = owner_position;
                const call = try self.expression(0);
                _ = try self.expect(.kw_as);
                const name = try self.expect(.ident);
                const body = try self.block();
                return self.addStatement(.{ .span = .join(first.span, self.syntax.statements.items[@backingInt(body)].span), .data = .{ .borrow_call = .{ .call = call, .name = name.span, .mutable = mutable, .body = body } } });
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
            return self.addStatement(.{
                .span = .join(first.span, self.syntax.statements.items[@backingInt(body)].span),
                .data = .{ .borrow = .{
                    .owner = owner.span,
                    .name = name.span,
                    .mutable = mutable,
                    .body = body,
                    .range = range,
                } },
            });
        }
        if (self.take(.kw_match)) {
            const value = try self.expression(0);
            _ = try self.expect(.lbrace);
            var arms: std.ArrayList(ast.MatchArm) = .empty;
            if (self.current().tag != .rbrace) while (true) {
                const ty = try self.nominalTypeName();
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
                try arms.append(self.arena.allocator(), .{ .ty = ty, .name = name.span, .binding = binding, .discard_payload = discard_payload, .body = body });
                if (!self.take(.comma)) break;
            };
            const close = try self.expect(.rbrace);
            return self.addStatement(.{ .span = .join(first.span, close.span), .data = .{ .match = .{ .value = value, .arms = try arms.toOwnedSlice(self.arena.allocator()) } } });
        }
        if (self.take(.kw_if)) {
            const condition = try self.expression(0);
            const then_body = try self.block();
            const else_body = if (self.take(.kw_else))
                if (self.current().tag == .kw_if) try self.statement() else try self.block()
            else
                null;
            const last = else_body orelse then_body;
            return self.addStatement(.{ .span = .join(first.span, self.syntax.statements.items[@backingInt(last)].span), .data = .{ .branch = .{
                .condition = condition,
                .then_body = then_body,
                .else_body = else_body,
            } } });
        }
        if (self.take(.kw_for)) {
            const name = (try self.expect(.ident)).span;
            _ = try self.expect(.kw_in);
            const start = try self.expression(0);
            _ = try self.expect(.dot_dot);
            const end = try self.expression(0);
            const body = try self.block();
            return self.addStatement(.{ .span = .join(first.span, self.syntax.statements.items[@backingInt(body)].span), .data = .{ .for_range = .{ .name = name, .start = start, .end = end, .body = body } } });
        }
        if (self.take(.kw_while)) {
            const condition = try self.expression(0);
            const body = try self.block();
            return self.addStatement(.{ .span = .join(first.span, self.syntax.statements.items[@backingInt(body)].span), .data = .{ .loop = .{ .condition = condition, .body = body } } });
        }
        const data: @FieldType(ast.Statement, "data") = switch (first.tag) {
            .kw_write_slice => write: {
                self.cursor.pos += 1;
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
                self.cursor.pos += 1;
                _ = try self.expect(.lparen);
                const name = try self.expect(.ident);
                _ = try self.expect(.comma);
                const value = try self.expression(0);
                _ = try self.expect(.rparen);
                break :write .{ .write_ref = .{ .name = name.span, .value = value } };
            },
            .kw_acknowledge => acknowledged: {
                self.cursor.pos += 1;
                break :acknowledged .{ .acknowledge = try self.expression(0) };
            },
            .kw_discard => discard: {
                self.cursor.pos += 1;
                break :discard .{ .discard = try self.expression(0) };
            },
            .kw_break, .kw_continue => exit: {
                self.cursor.pos += 1;
                break :exit .{ .loop_exit = first.tag == .kw_continue };
            },
            .kw_return => ret: {
                self.cursor.pos += 1;
                break :ret .{ .ret = try self.expression(0) };
            },
            .kw_let => binding: {
                self.cursor.pos += 1;
                const mutable = self.take(.kw_mut);
                const name = try self.expect(.ident);
                const annotation = if (self.take(.colon)) try self.typeName() else null;
                _ = try self.expect(.equal);
                break :binding .{ .binding = .{ .name = name.span, .mutable = mutable, .annotation = annotation, .value = try self.expression(0) } };
            },
            .ident => assignment: {
                const operator = self.tokens[self.cursor.pos + 1];
                const op: ast.AssignmentOp = switch (operator.tag) {
                    .equal => .set,
                    .plus_equal => .add,
                    .minus_equal => .sub,
                    else => return self.sink.fail("E_EXPLICIT_DISCARD_REQUIRED", first.span, "a standalone value requires explicit discard"),
                };
                self.cursor.pos += 2;
                break :assignment .{ .assignment = .{ .name = first.span, .value = try self.expression(0), .op = op, .op_span = operator.span } };
            },
            else => return self.sink.fail("E_EXPLICIT_DISCARD_REQUIRED", first.span, "expected a statement; a standalone value requires explicit discard"),
        };
        const end = try self.expect(.semicolon);
        return self.addStatement(.{ .span = .join(first.span, end.span), .data = data });
    }
    fn append(self: *Parser, node: ast.Node) diagnostic.Error!ast.NodeId {
        const id: ast.NodeId = @fromBackingInt(self.syntax.nodes.items.len);
        try self.syntax.nodes.append(self.arena.allocator(), node);
        return id;
    }
    fn fieldInitializers(self: *Parser) diagnostic.Error![]const ast.FieldInit {
        _ = try self.expect(.lbrace);
        var fields: std.ArrayList(ast.FieldInit) = .empty;
        if (self.current().tag != .rbrace) while (true) {
            const name = try self.expect(.ident);
            _ = try self.expect(.colon);
            try fields.append(self.arena.allocator(), .{ .name = name.span, .value = try self.expression(0) });
            if (!self.take(.comma)) break;
        };
        _ = try self.expect(.rbrace);
        return fields.toOwnedSlice(self.arena.allocator());
    }
    fn expression(self: *Parser, min_precedence: u8) diagnostic.Error!ast.NodeId {
        try self.enter();
        defer self.cursor.depth -= 1;
        const token = self.current();
        var left: ast.NodeId = switch (token.tag) {
            .kw_len_pool, .kw_capacity_pool, .kw_read_pool, .kw_replace_pool, .kw_insert_pool, .kw_remove_pool, .kw_clear_pool => try self.parsePool(token),
            .kw_len_buffer, .kw_capacity_buffer, .kw_read_buffer, .kw_write_buffer, .kw_append_buffer, .kw_resize_buffer, .kw_reserve_buffer => try self.parseBuffer(token),
            .kw_restrict_resource => try self.parseRestrict(token),
            .kw_read_resource_slice, .kw_write_resource_slice => try self.parseSliceIo(token),
            .kw_read_resource, .kw_write_resource => try self.parseResourceIo(token),
            .kw_environment_get => try self.parseEnvironment(token),
            .kw_read_field, .kw_take_field => read: {
                self.cursor.pos += 1;
                _ = try self.expect(.lparen);
                const owner = try self.expect(.ident);
                _ = try self.expect(.comma);
                const field = try self.expect(.ident);
                const close = try self.expect(.rparen);
                break :read try self.append(.{
                    .span = .join(token.span, close.span),
                    .data = if (token.tag == .kw_take_field) .{ .take_field = .{
                        .owner = owner.span,
                        .field = field.span,
                    } } else .{ .read_field = .{
                        .owner = owner.span,
                        .field = field.span,
                    } },
                });
            },
            .kw_acquire_resource, .kw_complete_resource => try self.parseResource(token),
            .kw_clock_now, .kw_random_u64 => external: {
                self.cursor.pos += 1;
                _ = try self.expect(.lt);
                const ty = try self.typeName();
                _ = try self.expect(.gt);
                _ = try self.expect(.lparen);
                const capability = try self.expression(0);
                const close = try self.expect(.rparen);
                break :external try self.append(.{ .span = .join(token.span, close.span), .data = .{ .external_read = .{ .kind = if (token.tag == .kw_clock_now) .clock else .random, .ty = ty, .capability = capability } } });
            },
            .kw_read_slice => read: {
                self.cursor.pos += 1;
                _ = try self.expect(.lparen);
                const name = try self.expect(.ident);
                _ = try self.expect(.comma);
                const index = try self.expression(0);
                const close = try self.expect(.rparen);
                break :read try self.append(.{ .span = .join(token.span, close.span), .data = .{ .read_slice = .{ .name = name.span, .index = index } } });
            },
            .kw_len_slice => length: {
                self.cursor.pos += 1;
                _ = try self.expect(.lparen);
                const name = try self.expect(.ident);
                const close = try self.expect(.rparen);
                break :length try self.append(.{ .span = .join(token.span, close.span), .data = .{ .len_slice = name.span } });
            },
            .kw_read_ref => read: {
                self.cursor.pos += 1;
                _ = try self.expect(.lparen);
                const name = try self.expect(.ident);
                const close = try self.expect(.rparen);
                break :read try self.append(.{ .span = .join(token.span, close.span), .data = .{ .read_ref = name.span } });
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
            .kw_reset_arena, .kw_cast, .kw_wrap, .kw_acquire_buffer, .kw_acquire_pool => try self.parseCast(token),
            .kw_new => try self.parseRecord(token),
            .kw_match => try self.parseMatchExpression(token),
            .kw_len, .kw_replace, .kw_unwrap => try self.parseBuiltin(token),
            .kw_update => update: {
                self.cursor.pos += 1;
                _ = try self.expect(.lparen);
                const base = try self.expression(0);
                _ = try self.expect(.rparen);
                const fields = try self.fieldInitializers();
                break :update try self.append(.{ .span = .join(token.span, self.tokens[self.cursor.pos - 1].span), .data = .{ .update = .{ .base = base, .fields = fields } } });
            },
            .kw_todo => try self.parseHole(token),
            .kw_codec_encode, .kw_codec_decode => try self.parseCodecOperation(token),
            .integer, .bytes, .ident, .kw_true, .kw_false => try self.parseLeaf(token),
            .kw_try => propagated: {
                self.cursor.pos += 1;
                const value = try self.expression(7);
                break :propagated try self.append(.{ .span = .join(token.span, self.syntax.nodes.items[@backingInt(value)].span), .data = .{ .propagate = value } });
            },
            .minus, .bang => unary: {
                self.cursor.pos += 1;
                const operand = try self.expression(7);
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
                self.cursor.pos += 1;
                const inner = try self.expression(0);
                const close = try self.expect(.rparen);
                self.syntax.nodes.items[@backingInt(inner)].span = .join(token.span, close.span);
                break :group inner;
            },
            else => return self.sink.fail("E_EXPRESSION", token.span, "expected an expression"),
        };
        while (true) {
            if (self.take(.lbracket)) {
                const index = try self.expression(0);
                const close = try self.expect(.rbracket);
                left = try self.append(.{ .span = .join(self.syntax.nodes.items[@backingInt(left)].span, close.span), .data = .{ .index = .{ .base = left, .index = index } } });
                continue;
            }
            if (self.take(.dot)) {
                const name = try self.expect(.ident);
                left = try self.append(.{ .span = .join(self.syntax.nodes.items[@backingInt(left)].span, name.span), .data = .{ .field = .{ .base = left, .name = name.span } } });
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
            self.cursor.pos += 1;
            const right = try self.expression(precedence + 1);
            left = try self.append(.{ .span = .join(self.syntax.nodes.items[@backingInt(left)].span, self.syntax.nodes.items[@backingInt(right)].span), .data = .{ .binary = .{
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
    fn parsePool(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        const kind: @import("pool_operations.zig").Kind = switch (token.tag) {
            .kw_len_pool => .length,
            .kw_capacity_pool => .capacity,
            .kw_read_pool => .read,
            .kw_replace_pool => .replace,
            .kw_insert_pool => .insert,
            .kw_remove_pool => .remove,
            .kw_clear_pool => .clear,
            else => unreachable,
        };
        const result: ?Span = if (kind.fallible()) result: {
            _ = try self.expect(.lt);
            const ty = try self.typeName();
            _ = try self.expect(.gt);
            break :result ty;
        } else null;
        _ = try self.expect(.lparen);
        const owner = try self.expect(.ident);
        const arguments = try self.arena.allocator().alloc(ast.NodeId, kind.arity());
        for (arguments) |*argument| {
            _ = try self.expect(.comma);
            argument.* = try self.expression(0);
        }
        const close = try self.expect(.rparen);
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .pool_operation = .{ .kind = kind, .owner = owner.span, .result = result, .arguments = arguments } } });
    }

    fn parseBuffer(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        const kind: @import("buffer_operations.zig").Kind = switch (token.tag) {
            .kw_len_buffer => .length,
            .kw_capacity_buffer => .capacity,
            .kw_read_buffer => .read,
            .kw_write_buffer => .write,
            .kw_append_buffer => .append,
            .kw_resize_buffer => .resize,
            .kw_reserve_buffer => .reserve,
            else => unreachable,
        };
        const result: ?Span = if (kind.mutates()) result: {
            _ = try self.expect(.lt);
            const ty = try self.typeName();
            _ = try self.expect(.gt);
            break :result ty;
        } else null;
        _ = try self.expect(.lparen);
        const owner = try self.expect(.ident);
        const arguments = try self.arena.allocator().alloc(ast.NodeId, kind.arity());
        for (arguments) |*argument| {
            _ = try self.expect(.comma);
            argument.* = try self.expression(0);
        }
        const close = try self.expect(.rparen);
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .buffer_operation = .{ .kind = kind, .owner = owner.span, .result = result, .arguments = arguments } } });
    }

    fn parseRestrict(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        _ = try self.expect(.lt);
        var permissions: external_resources.Permissions = 0;
        if (self.current().tag != .gt) while (true) {
            const name = try self.expect(.ident);
            const permission = std.meta.stringToEnum(external_resources.Permission, self.src.text(name.span)) orelse return self.sink.fail("E_PERMISSION", name.span, "permission must be read, write, or complete");
            const bit = external_resources.permissionBit(permission);
            if (permissions & bit != 0) return self.sink.fail("E_PERMISSION", name.span, "permission is repeated");
            permissions |= bit;
            if (!self.take(.comma)) break;
        };
        _ = try self.expect(.gt);
        _ = try self.expect(.lparen);
        const value = try self.expression(0);
        const close = try self.expect(.rparen);
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .restrict_resource = .{ .permissions = permissions, .value = value } } });
    }

    fn parseSliceIo(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        _ = try self.expect(.lt);
        const ty = try self.typeName();
        _ = try self.expect(.gt);
        _ = try self.expect(.lparen);
        const owner = try self.expect(.ident);
        _ = try self.expect(.comma);
        const reference = try self.expect(.ident);
        const close = try self.expect(.rparen);
        return self.append(.{
            .span = .join(token.span, close.span),
            .data = .{ .resource_io = .{
                .kind = if (token.tag == .kw_read_resource_slice) .read else .write,
                .owner = owner.span,
                .ty = ty,
                .value = null,
                .reference = reference.span,
            } },
        });
    }

    fn parseResourceIo(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        _ = try self.expect(.lt);
        const ty = try self.typeName();
        _ = try self.expect(.gt);
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
        _ = try self.expect(.lt);
        const ty = try self.typeName();
        _ = try self.expect(.gt);
        _ = try self.expect(.lparen);
        const capability = try self.expression(0);
        _ = try self.expect(.comma);
        const name = try self.expression(0);
        const close = try self.expect(.rparen);
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .environment_get = .{ .ty = ty, .capability = capability, .name = name } } });
    }

    fn parseResource(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        _ = try self.expect(.lt);
        const ty = try self.typeName();
        _ = try self.expect(.gt);
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

    fn parseCast(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        _ = try self.expect(.lt);
        const ty = try self.typeName();
        _ = try self.expect(.gt);
        _ = try self.expect(.lparen);
        const first = try self.expression(0);
        const value = if (token.tag == .kw_acquire_buffer or token.tag == .kw_acquire_pool) value: {
            _ = try self.expect(.comma);
            break :value try self.expression(0);
        } else first;
        const close = try self.expect(.rparen);
        return self.append(.{
            .span = .join(token.span, close.span),
            .data = if (token.tag == .kw_reset_arena) .{ .reset_arena = .{
                .ty = ty,
                .value = value,
            } } else if (token.tag == .kw_acquire_pool) .{ .acquire_pool = .{
                .ty = ty,
                .allocator = first,
                .value = value,
            } } else if (token.tag == .kw_acquire_buffer) .{ .acquire_buffer = .{
                .ty = ty,
                .allocator = first,
                .value = value,
            } } else if (token.tag == .kw_cast) .{ .cast = .{
                .ty = ty,
                .value = value,
            } } else .{ .wrap = .{
                .ty = ty,
                .value = value,
            } },
        });
    }

    fn parseRecord(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        const name = try self.typeName();
        if (self.take(.dot)) {
            const tag = try self.expect(.ident);
            var value: ?ast.NodeId = null;
            if (self.take(.lparen)) {
                value = try self.expression(0);
                _ = try self.expect(.rparen);
            }
            return self.append(.{ .span = .join(token.span, self.tokens[self.cursor.pos - 1].span), .data = .{ .variant = .{ .ty = name, .name = tag.span, .value = value } } });
        }
        if (self.take(.lbracket)) {
            var values: std.ArrayList(ast.NodeId) = .empty;
            if (self.current().tag != .rbracket) while (true) {
                try values.append(self.arena.allocator(), try self.expression(0));
                if (!self.take(.comma)) break;
            };
            const close = try self.expect(.rbracket);
            return self.append(.{ .span = .join(token.span, close.span), .data = .{ .array = .{ .ty = name, .values = try values.toOwnedSlice(self.arena.allocator()) } } });
        }
        const fields = try self.fieldInitializers();
        return self.append(.{ .span = .join(token.span, self.tokens[self.cursor.pos - 1].span), .data = .{ .record = .{ .name = name, .fields = fields } } });
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
        return self.tokens[self.cursor.pos + 1].tag == .ident and (self.tokens[self.cursor.pos + 2].tag == .lparen or self.tokens[self.cursor.pos + 2].tag == .colon);
    }

    fn parseHole(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        _ = try self.expect(.lt);
        const types = try self.arena.allocator().alloc(Span, 1);
        types[0] = try self.typeName();
        _ = try self.expect(.gt);
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
        if (!self.take(.lt)) return self.sink.fail("E_CODEC_ARITY", token.span, "codec operation requires one explicit domain type");
        const types = try self.arena.allocator().alloc(Span, 1);
        types[0] = try self.typeName();
        _ = try self.expect(.gt);
        _ = try self.expect(.lparen);
        var arguments: std.ArrayList(ast.NodeId) = .empty;
        if (self.current().tag != .rparen) while (true) {
            try arguments.append(self.arena.allocator(), try self.expression(0));
            if (!self.take(.comma)) break;
        };
        const close = try self.expect(.rparen);
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .call = .{
            .name = token.span,
            .type_arguments = types,
            .arguments = try arguments.toOwnedSlice(self.arena.allocator()),
        } } });
    }
    fn parseMatchExpression(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        const value = try self.expression(0);
        _ = try self.expect(.lbrace);
        var arms: std.ArrayList(ast.MatchValueArm) = .empty;
        if (self.current().tag != .rbrace) while (true) {
            const ty = try self.nominalTypeName();
            _ = try self.expect(.dot);
            const name = (try self.expect(.ident)).span;
            var binding: ?Span = null;
            var discard_payload = false;
            if (self.take(.lparen)) {
                if (self.take(.kw_discard)) discard_payload = true else binding = (try self.expect(.ident)).span;
                _ = try self.expect(.rparen);
            }
            _ = try self.expect(.fat_arrow);
            const arm = try self.expression(0);
            try arms.append(self.arena.allocator(), .{ .ty = ty, .name = name, .binding = binding, .discard_payload = discard_payload, .value = arm });
            if (!self.take(.comma)) break;
            if (self.current().tag == .rbrace) break;
        };
        const close = (try self.expect(.rbrace)).span;
        return self.append(.{ .span = .join(token.span, close), .data = .{ .match_expression = .{ .value = value, .arms = try arms.toOwnedSlice(self.arena.allocator()) } } });
    }
    fn parseLeaf(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        var owner: ?Span = null;
        var name = if (token.tag == .ident) try self.qualifiedTail(token.span) else token.span;
        if (token.tag == .ident and self.methodSuffix()) {
            owner = name;
            self.cursor.pos += 1;
            name = (try self.expect(.ident)).span;
        }
        const type_arguments = if (token.tag == .ident) try self.typeArguments() else &.{};
        if (token.tag == .ident and self.take(.lparen)) {
            var arguments: std.ArrayList(ast.NodeId) = .empty;
            if (self.current().tag != .rparen) while (true) {
                try arguments.append(self.arena.allocator(), try self.expression(0));
                if (!self.take(.comma)) break;
            };
            const close = try self.expect(.rparen);
            return self.append(.{ .span = .join(token.span, close.span), .data = .{ .call = .{ .owner = owner, .type_arguments = type_arguments, .name = name, .arguments = try arguments.toOwnedSlice(self.arena.allocator()) } } });
        }
        return self.append(.{ .span = name, .data = switch (token.tag) {
            .integer => .{ .integer = token.span },
            .bytes => .{ .bytes = try @import("byte_literal.zig").decode(self.arena.allocator(), self.src, token.span, self.sink) },
            .ident => .{ .name = name },
            else => .{ .boolean = token.tag == .kw_true },
        } });
    }
};
