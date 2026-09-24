//! Recursive descent for statements; precedence climbing for expressions.
const syntax_code = "E_SYNTAX";
const expression_code = "E_EXPRESSION";
const expected_expression = "expected an expression";
const eExportRemoved = "E_EXPORT_REMOVED";
/// Diagnostic code for a contract clause on a declaration that cannot carry it.
const contract_target_code = "E_CONTRACT_TARGET";
/// Diagnostic code for an `old(...)` outside `@ensures` or with a bad argument list.
const contract_old_code = "E_CONTRACT_OLD";
const eInternalName = "E_INTERNAL_NAME";
const eDefaultArgument = "E_DEFAULT_ARGUMENT";
const eRequirement = diagnostic.generic_requirement;
const eGenericLimit = diagnostic.generic_limit;
const removed_spelling_code = "E_REMOVED_SPELLING";
const std = @import("std");
const removed_names = @import("removed_names.zig");
const eIteration = "E_ITERATION";
const effects = @import("effect_set.zig");
const ast = @import("ast.zig");
const lex = @import("lexer.zig");
const Span = @import("source.zig").Span;
const diagnostic = @import("diagnostic.zig");
const byte_literal = @import("byte_literal.zig");
const requirements = @import("generic_requirements.zig");
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

/// One `+`-separated requirement list split by form before it is attached to a
/// type parameter or a constraint definition's subject.
const RequirementCollections = struct {
    builtins: std.ArrayList(Span) = .empty,
    fields: std.ArrayList(ast.Parameter) = .empty,
    operations: std.ArrayList(ast.Operation) = .empty,
    names: std.ArrayList(ast.BoundReference) = .empty,
};
/// A declaration or statement form whose Python spelling this language rejects
/// at a known point. The enum is what a call site names; `declaration_hints`
/// carries the table row it resolves to.
pub const HintForm = enum {
    union_cases,
    module_constant,
    method,
    from_import,
    chained_assignment,
    exceptions,
    match_literal,
    del_statement,
    string_prefix,
    main_guard,
    option_unwrap,
    nested_comprehension,
    dict_comprehension,
    generator_argument,
    walrus,
};
/// One hinted declaration form: the idiom the friction classifier files the
/// shape under, the primary message, and the accepted spelling the note names.
pub const DeclarationHint = struct { form: HintForm, idiom: []const u8, message: []const u8, accepted: []const u8 };
/// The hinted forms in `HintForm` order. `velocity/friction/classifier.json`
/// files the same idioms in its `hints` array, so the suite's classification and
/// the parser's messaging are one table; `src/declaration_hints_test.zig` and
/// `tests/parser_hints.py` fail when one side names a form the other lacks.
pub const declaration_hints = [_]DeclarationHint{
    .{ .form = .union_cases, .idiom = "union-cases", .message = "union cases are separated by commas", .accepted = "insert a comma after the previous case" },
    .{ .form = .module_constant, .idiom = "module-constant", .message = "a bare assignment declares no module-level binding", .accepted = "declare it as a constant: const MAX: int = 42" },
    .{ .form = .method, .idiom = "method", .message = "a record or class body declares fields, not methods", .accepted = "declare a top-level function taking the record: def norm1(p: Point) -> int" },
    .{ .form = .from_import, .idiom = "from-import", .message = "a from-import is not a declaration", .accepted = "import the module and declare a record: import dataclasses" },
    .{ .form = .chained_assignment, .idiom = "chained-assign", .message = "a chained assignment declares no binding", .accepted = "assign one name per statement: `x = 21` first, then `y = 21`" },
    .{ .form = .exceptions, .idiom = "exceptions", .message = "a try statement is not part of the language", .accepted = "return `Result` and match it: `case Ok(value)` and `case Err(reason)`" },
    .{ .form = .match_literal, .idiom = "match-literal", .message = "a case names a union, enum or result case, not a literal", .accepted = "compare literals with `if`/`elif`: `if x == 1:` then `elif x == 3:`" },
    .{ .form = .del_statement, .idiom = "del", .message = "a del statement is not part of the language", .accepted = "remove with `_ = xs.pop(index)` for a list or `_ = d.pop(key)` for a dictionary" },
    .{ .form = .string_prefix, .idiom = "string-prefix", .message = "a string prefix is not part of a literal", .accepted = "drop the prefix and write the escape in an ordinary quoted string" },
    .{ .form = .main_guard, .idiom = "main-guard", .message = "a module has no `__name__` guard", .accepted = "delete the guard: `mylang run` calls `def main()` directly" },
    .{ .form = .option_unwrap, .idiom = "option-unwrap", .message = "`unwrap` is a keyword here, not a method", .accepted = "extract with `match`: `case Ok(value)` or `case Some(value)`; `?` propagates a `Result`" },
    .{ .form = .nested_comprehension, .idiom = "nested-comprehension", .message = "a comprehension takes exactly one generator", .accepted = "write the loops out and append: `for row in grid:` then `for x in row: flat.append(x)`" },
    .{ .form = .dict_comprehension, .idiom = "dict-comprehension", .message = "a dict comprehension is not provided", .accepted = "build the dictionary with a loop: `for x in range(4): d[x] = x * x`" },
    .{ .form = .generator_argument, .idiom = "generator-argument", .message = "a generator expression is not provided", .accepted = "materialize a list instead: `any([x > 2 for x in xs])`" },
    .{ .form = .walrus, .idiom = "walrus", .message = "the walrus operator is not part of the language", .accepted = "assign the name on its own line first, then test it" },
};
/// The primary message for a case list whose next case lacks its separating
/// comma. `union` reads from the hint table so the two can never drift.
fn caseCommaMessage(head: []const u8) []const u8 {
    if (std.mem.eql(u8, head, "enum")) return "enum cases are separated by commas";
    if (std.mem.eql(u8, head, "result")) return "result cases are separated by commas";
    return declaration_hints[@backingInt(HintForm.union_cases)].message;
}
/// Accepted spellings for Python forms whose rejection is not `E_SYNTAX`, so
/// they have no row in the shared classifier table. Each one names a construct
/// the language accepts today for the same intent; nothing here guesses.
const loop_else_accepted = "use a flag: assign it before the loop, set it before `break`, and test it after";
const nested_def_accepted = "declare the function at the top level and call it from the body";
const match_expression_accepted = "assign the value in each branch of an if/elif statement";
const power_accepted = "multiply in a loop: `total = 1` then `for i in range(exponent): total = total * base`";
const shift_accepted = "use `shift_left(value, count)` or `shift_right(value, count)`";
const for_else_message = "a loop has no `else` clause";
const set_augment_message = "a set has no augmented assignment operator";
const set_augment_accepted = "rebind with the operator, `s = s | t`, or call `s.update(t)`";
const nested_def_message = "a function body declares statements, not another function";
const match_expression_message = "`match` is a statement, not an expression";
const power_message = "`**` is not an operator";
const shift_message = "`<<` and `>>` are not operators";
/// Token cursor and allocator-backed syntax builder with bounded recursive nesting.
pub const Parser = struct {
    src: @import("source.zig").Source,
    /// Where the syntax this parser builds lives: the owning project's or compilation's arena.
    storage: std.mem.Allocator,
    tokens: []const lex.Token,
    sink: *diagnostic.Sink,
    cursor: struct {
        pos: usize = 0,
        depth: usize = 0,
        delimiters: usize = 0,
        /// Bit 0/1 records a top-level `def len`/`def replace`, indexed once at
        /// parse start so each prelude call does not rescan the token stream.
        shadowing: u2 = 0,
    } = .{},
    module_syntax: bool = false,
    syntax: struct {
        nodes: std.ArrayList(ast.Node) = .empty,
        statements: std.ArrayList(ast.Statement) = .empty,
        types: struct {
            arrays: std.ArrayList(ast.ArrayType) = .empty,
            callbacks: std.ArrayList(ast.CallbackType) = .empty,
            applications: std.ArrayList(ast.TypeApplication) = .empty,
            aliases: std.ArrayList(ast.TypeAlias) = .empty,
            tuples: std.ArrayList(ast.TupleType) = .empty,
        } = .{},
        lambdas: std.ArrayList(ast.Lambda) = .empty,
        import_aliases: std.StringHashMapUnmanaged(void) = .empty,
        docstrings: std.ArrayList(ast.DeclarationDoc) = .empty,
        /// PARSE-EXACT-1: where the node and statement lists grow while a module
        /// is parsed, when not in `storage`. `parse` copies them into `storage`
        /// at their exact length and frees these, so an arena `storage` keeps no
        /// abandoned growth buffers (three times the final lists, before).
        growth: ?std.mem.Allocator = null,
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
    /// Report one known Python spelling at a declaration head: the primary
    /// message names the shape and the note names the accepted form under the
    /// counted `alternative` role, so the repair reads as an alternative rather
    /// than as more evidence.
    fn hint(self: *Parser, form: HintForm, span: Span, message: []const u8, note_span: Span) diagnostic.Error {
        return self.sink.failRelated(syntax_code, span, message, .{ .span = note_span, .message = declaration_hints[@backingInt(form)].accepted, .role = .alternative });
    }
    /// Hint the form at the cursor, attaching its note to the same token.
    fn hintHere(self: *Parser, form: HintForm) diagnostic.Error {
        return self.hint(form, self.current().span, declaration_hints[@backingInt(form)].message, self.current().span);
    }
    /// Report one Python form whose rejection is not `E_SYNTAX`, so it has no row
    /// in the shared declaration table: the code and span stay the ones the
    /// failure already produced and only the counted note is added.
    fn alternative(self: *Parser, code: []const u8, message: []const u8, accepted: []const u8) diagnostic.Error {
        const span = self.current().span;
        return self.sink.failRelated(code, span, message, .{ .span = span, .message = accepted, .role = .alternative });
    }
    /// One expression-position Python form with the accepted spelling it has
    /// instead of the grammar production that is missing.
    const ExpressionForm = struct { message: []const u8, accepted: []const u8 };
    /// The Python form standing where an expression belongs: a nested `def`, a
    /// `match` expression, or the second `*`/`<` of `**`/`<<`. Every other token
    /// keeps the ordinary "expected an expression" failure.
    fn pythonExpressionFailure(self: *Parser, token: lex.Token) diagnostic.Error {
        const form: ?ExpressionForm = switch (token.tag) {
            .kw_def => .{ .message = nested_def_message, .accepted = nested_def_accepted },
            .kw_match => .{ .message = match_expression_message, .accepted = match_expression_accepted },
            .star => if (self.previousTag() == .star) .{ .message = power_message, .accepted = power_accepted } else null,
            .lt => if (self.previousTag() == .lt) .{ .message = shift_message, .accepted = shift_accepted } else null,
            .equal => switch (self.previousTag()) {
                .pipe, .ampersand, .caret => .{ .message = set_augment_message, .accepted = set_augment_accepted },
                else => null,
            },
            else => null,
        };
        if (form) |shape| return self.alternative(expression_code, shape.message, shape.accepted);
        return self.sink.fail(expression_code, token.span, expected_expression);
    }
    /// Whether the statement's terminator is already there: an explicit `;`, or
    /// the line break, closing dedent or end of file accepted in its place.
    fn terminatorAhead(self: *Parser) bool {
        return self.current().tag == .semicolon or lex.implicitTerminator(self.src.bytes, self.tokens, self.cursor.pos);
    }
    /// Where the token before the cursor ends, or zero at the start of a file.
    fn previousEnd(self: *Parser) usize {
        return if (self.cursor.pos == 0) 0 else self.tokens[self.cursor.pos - 1].span.end;
    }
    /// The tag of the token before the cursor, or the end-of-file tag at the
    /// start of a file.
    fn previousTag(self: *Parser) lex.Tag {
        return if (self.cursor.pos == 0) .eof else self.tokens[self.cursor.pos - 1].tag;
    }
    /// The Python statement shape standing where the terminator belongs, or null
    /// when the statement simply has no terminator. Only a statement whose
    /// terminator is already missing is asked, so every form here is a program
    /// the parser rejects whatever message it prints.
    fn statementShapeHint(self: *Parser, first: lex.Token) ?HintForm {
        const token = self.current();
        if (first.tag == .ident) {
            const text = self.src.text(first.span);
            if (std.mem.eql(u8, text, "try") and token.tag == .indent) return .exceptions;
            if (std.mem.eql(u8, text, "del")) return .del_statement;
            // A prefix the lexer does not know (`r"..."`, `u"..."`) leaves the
            // prefix as a name and the literal right against it.
            if ((token.tag == .bytes or token.tag == .format) and self.previousEnd() == token.span.start) return .string_prefix;
        }
        return switch (token.tag) {
            .equal => .chained_assignment,
            else => null,
        };
    }
    /// One statement's terminator, or the hint that names the Python statement
    /// shape standing in its place: a chained assignment, `del`, `try:` or a
    /// string prefix.
    fn statementEnd(self: *Parser, first: lex.Token) diagnostic.Error!lex.Token {
        if (!self.terminatorAhead()) {
            if (self.statementShapeHint(first)) |form| return self.hintHere(form);
        }
        return self.expect(.semicolon);
    }
    /// The `indent` that opens a suite. A missing indent is already a failure;
    /// the `is`-is-not-an-operator hint that once lived here is gone because
    /// `is None` is an expression now (OPTION-FLOW-1).
    fn blockOpen(self: *Parser) diagnostic.Error!lex.Token {
        return self.expect(.indent);
    }
    /// The `)` that closes a call's arguments, or the hint that names a generator
    /// argument standing in its place. A missing `)` is already a failure, and a
    /// `for` after a call that already closed itself (`[f(x) for x in xs]`) never
    /// reaches this point.
    fn callClose(self: *Parser) diagnostic.Error!lex.Token {
        if (self.current().tag == .kw_for) return self.hintHere(.generator_argument);
        return self.expect(.rparen);
    }
    /// Whether the cursor sits on an identifier in `previous`'s column: the next
    /// case of a union, enum or result written without the separating comma.
    fn caseAtSameColumn(self: *Parser, previous: Span) bool {
        const token = self.current();
        if (token.tag != .ident) return false;
        return self.src.locate(token.span.start).column == self.src.locate(previous.start).column;
    }
    /// The Python declaration head at the cursor that this language spells
    /// differently, if any: a bare module-level assignment, a `from` import, or
    /// the `if __name__` guard a script wraps its entry point in.
    fn pythonDeclarationHead(self: *Parser) ?HintForm {
        const token = self.current();
        if (token.tag == .kw_if) return .main_guard;
        if (token.tag != .ident) return null;
        const next = self.tokens[self.cursor.pos + 1].tag;
        if (next == .equal or next == .colon) return .module_constant;
        if (std.mem.eql(u8, self.src.text(token.span), "from")) return .from_import;
        return null;
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
    /// Only the compiler-embedded standard modules may spell the private
    /// `__float_sqrt` intrinsic. A matching `@stdlib/` path is not enough: the
    /// source bytes must be the exact embedded module.
    fn trustedStdlib(self: Parser) bool {
        if (self.src.trusted_intrinsics) return true;
        const prefix = "@stdlib/";
        if (!std.mem.startsWith(u8, self.src.path, prefix)) return false;
        const embedded = @import("standard_library.zig").source(self.src.path[prefix.len..]) orelse return false;
        return std.mem.eql(u8, embedded, self.src.bytes);
    }
    /// `record` is the canonical declaration head but remains an ordinary name in
    /// expressions, so this is contextual at the top level rather than a keyword.
    fn takeRecordHead(self: *Parser) bool {
        if (self.current().tag != .ident or !std.mem.eql(u8, self.src.text(self.current().span), "record")) return false;
        self.cursor.pos += 1;
        return true;
    }
    /// Whether the cursor names the contextual `mut` marker by text. `mut` has no
    /// lexer tag, so it stays an ordinary identifier everywhere else, exactly as
    /// the `mutates` clause does.
    fn identIsMut(self: *Parser) bool {
        const token = self.current();
        return token.tag == .ident and std.mem.eql(u8, self.src.text(token.span), "mut");
    }
    /// Whether the cursor starts a `mut` parameter or callback-parameter marker:
    /// `mut` followed by the type it marks. A `mut` with nothing after it is the
    /// declared name or the type itself, so `def f(mut: int)` and `def f(a: mut)`
    /// are unchanged.
    fn atMutParameter(self: *Parser) bool {
        if (!self.identIsMut()) return false;
        return switch (self.tokens[self.cursor.pos + 1].tag) {
            .comma, .rparen, .equal, .colon, .semicolon, .eof, .dedent, .indent => false,
            else => true,
        };
    }
    /// Whether the cursor starts a `mut` call-argument marker: `mut` followed by
    /// the expression it marks. A call, index, member access or operator after
    /// `mut` keeps it an ordinary name, so `mut(x)`, `mut[0]`, `mut.x` and
    /// `mut + 1` all keep their meaning.
    fn atMutArgument(self: *Parser) bool {
        if (!self.identIsMut()) return false;
        return switch (self.tokens[self.cursor.pos + 1].tag) {
            .ident, .integer, .bytes, .format, .kw_true, .kw_false, .kw_none, .kw_len, .kw_replace, .kw_todo, .minus, .bang, .lbracket, .lparen, .lbrace => true,
            else => false,
        };
    }
    /// One call argument's value: an optional `mut` marker wrapping the
    /// expression it applies to. The parser does not validate the target; the
    /// checker decides whether the position admits a marker.
    fn argumentValue(self: *Parser) diagnostic.Error!ast.NodeId {
        if (!self.atMutArgument()) return self.expression(0);
        const marker = self.current();
        self.cursor.pos += 1;
        const value = try self.expression(0);
        return self.append(.{ .span = .join(marker.span, self.syntax.nodes.items[@backingInt(value)].span), .data = .{ .mut_argument = value } });
    }
    /// Record top-level `def len`/`def replace` once so shadowing checks are
    /// constant-time instead of a fresh full token scan for every prelude call.
    fn indexShadowingDeclarations(self: *Parser) void {
        var position: usize = 0;
        var depth: usize = 0;
        while (position + 1 < self.tokens.len) : (position += 1) {
            if (self.tokens[position].tag == .indent) depth += 1;
            if (self.tokens[position].tag == .dedent) depth -|= 1;
            if (depth != 0 or self.tokens[position].tag != .kw_def) continue;
            const candidate = self.tokens[position + 1];
            if (candidate.tag != .ident and candidate.tag != .kw_len and candidate.tag != .kw_replace) continue;
            const name = self.src.text(candidate.span);
            if (std.mem.eql(u8, name, "len")) self.cursor.shadowing |= 1;
            if (std.mem.eql(u8, name, "replace")) self.cursor.shadowing |= 2;
        }
    }
    fn declaresFunction(self: Parser, name: Span) bool {
        const bit: u2 = if (std.mem.eql(u8, self.src.text(name), "len")) 1 else 2;
        return self.cursor.shadowing & bit != 0;
    }
    /// Whether `replace(...)` is called with a keyword argument,
    /// `replace(record, field=value)`, the functional record update rather than
    /// the positional three-argument list intrinsic. Only the first argument
    /// separator decides: the update form always names its first changed field.
    fn recordUpdateAhead(self: Parser) bool {
        var at = self.cursor.pos + 1;
        if (at >= self.tokens.len or self.tokens[at].tag != .lparen) return false;
        at += 1;
        var depth: usize = 1;
        while (at < self.tokens.len) : (at += 1) {
            switch (self.tokens[at].tag) {
                .lparen, .lbracket => depth += 1,
                .rparen, .rbracket => {
                    depth -= 1;
                    if (depth == 0) return false;
                },
                .comma => if (depth == 1) {
                    if (at + 2 >= self.tokens.len) return false;
                    const name = self.tokens[at + 1].tag;
                    return (name == .ident or name == .kw_len or name == .kw_replace) and self.tokens[at + 2].tag == .equal;
                },
                else => {},
            }
        }
        return false;
    }
    /// Whether some registered import name extends `text` with a dot. It marks a
    /// segment that only begins a dotted module path rather than naming one.
    fn importPathPrefix(self: *Parser, text: []const u8) bool {
        var iterator = self.syntax.import_aliases.keyIterator();
        while (iterator.next()) |key| {
            const name = key.*;
            if (name.len > text.len and name[text.len] == '.' and std.mem.eql(u8, name[0..text.len], text)) return true;
        }
        return false;
    }
    /// Join a dotted module path and one member into a single qualified name.
    /// `shared.units.area` and `units.area` both qualify the module; a prefix
    /// that does not continue a registered path (`shared.field`) is left as a
    /// field access on the base name, so a local may reuse that name.
    fn qualifiedTail(self: *Parser, first: Span) diagnostic.Error!Span {
        if (!self.module_syntax) return first;
        if (self.current().tag != .dot) return first;
        const first_text = self.src.text(first);
        if (!self.syntax.import_aliases.contains(first_text) and !self.importPathPrefix(first_text)) return first;
        if (!self.sameExpressionLine()) return first;
        var joined = first;
        while (self.current().tag == .dot and self.sameExpressionLine()) {
            const saved = self.cursor.pos;
            self.cursor.pos += 1;
            const candidate = Span.join(joined, try self.declaredName());
            const candidate_text = self.src.text(candidate);
            if (self.syntax.import_aliases.contains(candidate_text)) {
                joined = candidate;
                // A complete module name ends the qualifier; the next segment is
                // its member, joined into the same qualified name.
                if (self.current().tag == .dot and self.sameExpressionLine()) {
                    self.cursor.pos += 1;
                    return Span.join(joined, try self.declaredName());
                }
                return joined;
            }
            if (self.importPathPrefix(candidate_text)) {
                joined = candidate;
                continue;
            }
            // `joined` names the module and `candidate` adds its member.
            if (self.syntax.import_aliases.contains(self.src.text(joined))) return candidate;
            // `joined` only begins a module path and this segment does not
            // continue it, so leave the dot for an ordinary field access.
            self.cursor.pos = saved;
            return joined;
        }
        return joined;
    }
    fn typeName(self: *Parser) diagnostic.Error!Span {
        try self.enter();
        defer self.cursor.depth -= 1;
        const token = self.current();
        if (self.take(.kw_def)) return self.callbackType(token.span);
        if (self.take(.kw_none)) return token.span;
        if (token.tag == .ident and std.mem.eql(u8, self.src.text(token.span), "tuple") and self.tokens[self.cursor.pos + 1].tag == .lbracket) return self.tupleType(token);
        if (self.take(.lparen)) return .join(token.span, (try self.expect(.rparen)).span);
        if (self.take(.lbracket)) {
            const index: ast.ArrayIndex = if (self.current().tag == .integer) .{ .length = (try self.expect(.integer)).span } else .{ .enum_type = try self.typeName() };
            _ = try self.expect(.rbracket);
            const element = try self.typeName();
            const span: Span = .join(token.span, element);
            try self.syntax.types.arrays.append(self.storage, .{ .span = span, .index = index, .element = element });
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
    /// `tuple[T1, T2, ...]`: one entry in `TypeExpressions.tuples` holding the
    /// element type spans in source order. The parser accepts any comma count,
    /// including one; `sema.zig` reports `E_TUPLE_ARITY` for arity outside the
    /// two-to-eight range, so a wrong arity is a check error rather than a parse
    /// error.
    fn tupleType(self: *Parser, token: lex.Token) diagnostic.Error!Span {
        self.cursor.pos += 1;
        _ = try self.expect(.lbracket);
        const allocator = self.storage;
        var elements: std.ArrayList(Span) = .empty;
        while (true) {
            try elements.append(allocator, try self.typeName());
            if (!self.take(.comma) or self.current().tag == .rbracket) break;
        }
        const close = try self.expect(.rbracket);
        const span: Span = .join(token.span, close.span);
        try self.syntax.types.tuples.append(allocator, .{ .span = span, .elements = try elements.toOwnedSlice(allocator) });
        return span;
    }
    fn callbackType(self: *Parser, first: Span) diagnostic.Error!Span {
        _ = try self.expect(.lparen);
        const allocator = self.storage;
        var parameters: std.ArrayList(Span) = .empty;
        var names: std.ArrayList(?Span) = .empty;
        var mut_parameters: std.ArrayList(bool) = .empty;
        if (self.current().tag != .rparen) while (true) {
            if (parameters.items.len == 16) return self.sink.fail(eGenericLimit, first, "callbacks support at most 16 value parameters");
            // A callback type is positional, so it has no keyword-only group.
            if (self.current().tag == .star) return self.sink.fail(syntax_code, self.current().span, "`*` is not permitted in a callback type; declare the keyword-only parameters on a function");
            var name: ?Span = null;
            if (self.current().tag == .ident and self.tokens[self.cursor.pos + 1].tag == .colon) {
                name = (try self.expect(.ident)).span;
                _ = try self.expect(.colon);
            }
            const mutable = self.atMutParameter();
            if (mutable) self.cursor.pos += 1;
            try mut_parameters.append(allocator, mutable);
            try parameters.append(allocator, try self.typeName());
            try names.append(allocator, name);
            if (!self.take(.comma) or self.current().tag == .rparen) break;
        };
        _ = try self.expect(.rparen);
        _ = try self.expect(.arrow);
        const result = try self.typeName();
        // An omitted callback ceiling is unbounded: the slot accepts any function
        // value, and an explicit ceiling remains an upper bound on the callee.
        const bound = try self.effectBound() orelse effects.Bound{ .span = first, .allowed = effects.all };
        try self.rejectMutatesClause();
        const span: Span = .join(first, self.tokens[self.cursor.pos - 1].span);
        try self.syntax.types.callbacks.append(allocator, .{
            .span = span,
            .parameters = try parameters.toOwnedSlice(allocator),
            .parameter_names = try names.toOwnedSlice(allocator),
            .return_type = result,
            .effect_bound = bound,
            .mut_parameters = try mut_parameters.toOwnedSlice(allocator),
        });
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
            try arguments.append(self.storage, argument);
            if (!self.take(.comma)) break;
        }
        const close = try self.expect(.rbracket);
        const span: Span = .join(name, close.span);
        try self.syntax.types.applications.append(self.storage, .{ .span = span, .name = name, .arguments = try arguments.toOwnedSlice(self.storage) });
        return span;
    }
    /// Parse module headers and bodies without loading imports or checking names.
    /// A file with no `module` header is a module program only when it opens with
    /// imports of compiler-embedded standard modules and nothing else; every
    /// other headerless file still reports `E_MODULE_HEADER`.
    pub fn parseModule(self: *Parser) diagnostic.Error!ast.Program {
        self.module_syntax = true;
        if (try self.standardImportScript()) {
            try self.importDirectives();
            return self.parse();
        }
        const first = try self.expect(.ident);
        if (!std.mem.eql(u8, self.src.text(first.span), "module")) return self.sink.fail("E_MODULE_HEADER", first.span, "file must begin with a module declaration");
        try self.moduleName();
        _ = try self.expect(.semicolon);
        try self.importDirectives();
        return self.parse();
    }
    /// Parse the leading `import` directives, recording each module qualifier.
    fn importDirectives(self: *Parser) diagnostic.Error!void {
        while (self.current().tag == .ident and std.mem.eql(u8, self.src.text(self.current().span), "import")) {
            self.cursor.pos += 1;
            const path_start = self.current().span;
            try self.moduleName();
            const path = Span.join(path_start, self.tokens[self.cursor.pos - 1].span);
            const explicit = self.take(.kw_as);
            const alias = if (explicit) (try self.expect(.ident)).span else self.tokens[self.cursor.pos - 1].span;
            const allocator = self.storage;
            // The local alias (explicit, or the trailing segment) and the full
            // dotted module path both qualify the module; no bare prefix of the
            // path is reserved, so a local may reuse `shared` in `shared.geometry`.
            try self.syntax.import_aliases.put(allocator, self.src.text(alias), {});
            try self.syntax.import_aliases.put(allocator, self.src.text(path), {});
            _ = try self.expect(.semicolon);
        }
    }
    /// Whether the file opens with a headerless run of standard-module imports:
    /// the script shape that needs no `module` declaration. The one policy lives
    /// in `project.zig` so the parser and the project loader cannot disagree.
    fn standardImportScript(self: *Parser) diagnostic.Error!bool {
        return @import("project.zig").standardImportOpening(self.storage, self.src, self.tokens, self.cursor.pos);
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
    /// The fixed attribute vocabulary: the three declaration markers and the
    /// three contract clauses.
    fn attributeKind(text: []const u8) ?ast.AttributeKind {
        inline for (@typeInfo(ast.AttributeKind).@"enum".field_names) |name| {
            if (std.mem.eql(u8, text, name)) return @field(ast.AttributeKind, name);
        }
        return null;
    }
    /// Parse one contract clause's `(condition[, "message"])` after its name.
    /// An `@ensures` condition records the `old(...)` calls it makes; any other
    /// clause that calls `old` is `E_CONTRACT_OLD`. The condition's nodes are
    /// exactly those appended while parsing it, so the scan needs no walker.
    fn contractClause(self: *Parser, attribute: *ast.Attribute, at: Span) diagnostic.Error!void {
        _ = try self.expect(.lparen);
        const first = self.syntax.nodes.items.len;
        const condition = try self.expression(0);
        attribute.condition = condition;
        if (self.take(.comma)) attribute.argument = (try self.expect(.bytes)).span;
        attribute.span = .join(at, (try self.expect(.rparen)).span);
        var olds: std.ArrayList(ast.NodeId) = .empty;
        for (self.syntax.nodes.items[first..], first..) |node, index| {
            if (node.data != .call or node.data.call.owner != null) continue;
            if (!std.mem.eql(u8, self.src.text(node.data.call.name), "old")) continue;
            if (attribute.kind != .ensures) return self.sink.fail(contract_old_code, node.span, "`old(...)` is only legal inside `@ensures`; a precondition and an invariant already see the current value");
            if (node.data.call.arguments.len != 1) return self.sink.fail(contract_old_code, node.span, "`old` takes exactly one expression");
            try olds.append(self.storage, @fromBackingInt(index));
        }
        attribute.olds = try olds.toOwnedSlice(self.storage);
    }
    /// The declaration kinds an attribute list can precede.
    const AttributeHead = enum { function, host_function, record, domain, other };
    /// Classify the declaration head after an attribute list, past `public`.
    fn attributeHead(self: *Parser) AttributeHead {
        var at = self.cursor.pos;
        if (self.tokens[at].tag == .ident and std.mem.eql(u8, self.src.text(self.tokens[at].span), "public")) at += 1;
        const text = self.src.text(self.tokens[at].span);
        return switch (self.tokens[at].tag) {
            .kw_def, .kw_private, .kw_conversion => .function,
            .kw_domain => .domain,
            .ident => if (std.mem.eql(u8, text, "extern") or std.mem.eql(u8, text, "host")) .host_function else if (std.mem.eql(u8, text, "record")) .record else .other,
            else => .other,
        };
    }
    /// Reject an attribute placed above a declaration that cannot carry it:
    /// `@requires`/`@ensures` need a `def` with a body, `@invariant` a
    /// `record` or `domain`, and the other attributes a function. A domain
    /// member (`member` set) takes only contract clauses.
    fn checkAttributeTarget(self: *Parser, pending: []const ast.Attribute, member: bool) diagnostic.Error!void {
        if (pending.len == 0) return;
        const head = self.attributeHead();
        for (pending) |attribute| switch (attribute.kind) {
            .invariant => if (head != .record and head != .domain)
                return self.sink.fail(contract_target_code, attribute.span, "`@invariant` attaches to a `record` or `domain` declaration; a class, union, enum, alias, constraint or function carries none"),
            .requires, .ensures => if (head != .function)
                return self.sink.fail(contract_target_code, attribute.span, if (head == .host_function) "an `extern` or `host` declaration has no body to check a contract in" else "`@requires` and `@ensures` attach to a `def` declaration"),
            .deprecated, .@"test", .allow => if (member or (head != .function and head != .host_function))
                return self.sink.fail("E_ATTRIBUTE_TARGET", attribute.span, if (member) "only contract clauses attach to a domain member" else "attributes attach to a function declaration"),
        };
    }
    /// Record one declaration's attribute list under its name span.
    fn attach(self: *Parser, table: *std.ArrayList(ast.DeclarationAttributes), declaration: Span, pending: []const ast.Attribute) std.mem.Allocator.Error!void {
        if (pending.len != 0) try table.append(self.storage, .{ .declaration = declaration, .attributes = pending });
    }
    /// Parse one function declared inside a domain body, with the contract
    /// clauses written above it.
    fn domainMember(self: *Parser, owner: Span, table: *std.ArrayList(ast.DeclarationAttributes)) diagnostic.Error!ast.Function {
        const pending = try self.attributes();
        try self.checkAttributeTarget(pending, true);
        const member = try self.function(owner);
        try self.attach(table, member.name, pending);
        return member;
    }
    /// Reject `@invariant` on a generic record: its condition would have to be
    /// checked once per instantiation, which this version does not do.
    fn rejectGenericInvariant(self: *Parser, pending: []const ast.Attribute, type_parameters: []const ast.TypeParameter) diagnostic.Error!void {
        if (type_parameters.len == 0) return;
        for (pending) |attribute| if (attribute.kind == .invariant)
            return self.sink.fail(contract_target_code, attribute.span, "`@invariant` attaches to a non-generic `record`; a generic record carries none");
    }
    /// Parse the `@name(...)` clauses that precede one declaration, rejecting an
    /// unknown name and a repeated kind.
    fn attributes(self: *Parser) diagnostic.Error![]const ast.Attribute {
        const allocator = self.storage;
        var list: std.ArrayList(ast.Attribute) = .empty;
        while (self.current().tag == .at) {
            const at_token = self.current();
            self.cursor.pos += 1;
            const name = try self.expect(.ident);
            const clause: Span = .join(at_token.span, name.span);
            const kind = attributeKind(self.src.text(name.span)) orelse
                return self.sink.fail("E_UNKNOWN_ATTRIBUTE", clause, "unknown attribute; expected @deprecated, @test, @allow, @requires, @ensures or @invariant");
            // Contract clauses repeat: each one is checked in source order.
            if (!kind.contract()) for (list.items) |existing| if (existing.kind == kind)
                return self.sink.fail("E_DUPLICATE_ATTRIBUTE", clause, "attribute is repeated on one declaration");
            var attribute: ast.Attribute = .{ .kind = kind, .span = clause };
            switch (kind) {
                .@"test" => {},
                .requires, .ensures, .invariant => try self.contractClause(&attribute, at_token.span),
                .deprecated => {
                    _ = try self.expect(.lparen);
                    attribute.argument = (try self.expect(.bytes)).span;
                    attribute.span = .join(at_token.span, (try self.expect(.rparen)).span);
                },
                .allow => {
                    _ = try self.expect(.lparen);
                    attribute.argument = (try self.expect(.bytes)).span;
                    if (self.take(.comma)) {
                        const key = try self.expect(.ident);
                        if (!std.mem.eql(u8, self.src.text(key.span), "reason")) return self.sink.fail(syntax_code, key.span, "the only @allow argument is reason=\"...\"");
                        _ = try self.expect(.equal);
                        attribute.reason = (try self.expect(.bytes)).span;
                    }
                    attribute.span = .join(at_token.span, (try self.expect(.rparen)).span);
                },
            }
            try list.append(allocator, attribute);
        }
        return list.toOwnedSlice(allocator);
    }
    /// Record the name of a declaration carrying the `public` modifier. Keeping
    /// the recording here holds the top-level dispatch below the complexity cap.
    fn markPublic(self: *Parser, names: *std.ArrayList(Span), declared: bool, name: Span) std.mem.Allocator.Error!void {
        if (declared) try names.append(self.storage, name);
    }
    /// Consume an optional leading `public` modifier and reject it directly
    /// before an `export` directive, the one spelling it cannot publish.
    fn takePublic(self: *Parser) diagnostic.Error!bool {
        const head_token = self.current();
        const declared = head_token.tag == .ident and std.mem.eql(u8, self.src.text(head_token.span), "public");
        if (declared) self.cursor.pos += 1;
        if (declared and self.current().tag == .ident and std.mem.eql(u8, self.src.text(self.current().span), "export"))
            return self.sink.fail(syntax_code, self.current().span, "`public` marks a declaration, not an export directive");
        return declared;
    }
    /// Consume a dotted re-export directive when the cursor names `export`, and
    /// reject the removed bare form. Answers whether a directive was consumed,
    /// so the top-level dispatch stays below the complexity cap.
    fn reexportDirective(self: *Parser) diagnostic.Error!bool {
        if (!self.module_syntax) return false;
        if (self.current().tag != .ident) return false;
        if (!std.mem.eql(u8, self.src.text(self.current().span), "export")) return false;
        self.cursor.pos += 1;
        const first_name = try self.declaredName();
        // The bare `export NAME` directive is removed: a local declaration
        // publishes itself with `public`. Only a re-export, which names an
        // imported declaration through its module qualifier
        // (`export shared.units.Distance`), is still a directive.
        if (!self.take(.dot)) return self.sink.fail(eExportRemoved, first_name, "plain `export NAME` is removed; mark the declaration `public` instead");
        _ = try self.declaredName();
        while (self.take(.dot)) _ = try self.declaredName();
        _ = try self.expect(.semicolon);
        return true;
    }
    /// Parse a complete source program, retaining syntax and diagnostics in the supplied allocator.
    pub fn parse(self: *Parser) diagnostic.Error!ast.Program {
        self.indexShadowingDeclarations();
        // A leading string statement documents the module itself. The module has
        // no declaration name, so it is keyed on the empty sentinel span.
        try self.recordDocstring(ast.module_docstring_span);
        var functions: std.ArrayList(ast.Function) = .empty;
        var records: std.ArrayList(ast.Record) = .empty;
        var domains: std.ArrayList(ast.Domain) = .empty;
        var resources: std.ArrayList(ast.Domain) = .empty;
        var variants: std.ArrayList(ast.Variants) = .empty;
        var constraints: std.ArrayList(ast.Constraint) = .empty;
        var attribute_table: std.ArrayList(ast.DeclarationAttributes) = .empty;
        var public_names: std.ArrayList(Span) = .empty;
        while (self.current().tag != .eof) {
            const pending = try self.attributes();
            try self.checkAttributeTarget(pending, false);
            // A leading `public` publishes the declaration that follows, so a
            // module marks visibility on the declaration itself. It is not a way
            // to spell the separate `export NAME` directive.
            const declare_public = try self.takePublic();
            if (try self.reexportDirective()) continue;
            if (self.current().tag == .ident and std.mem.eql(u8, self.src.text(self.current().span), "constraint")) {
                const head = self.current().span;
                self.cursor.pos += 1;
                const constraint = try self.constraintDeclaration(head);
                try self.markPublic(&public_names, declare_public, constraint.name);
                try constraints.append(self.storage, constraint);
                continue;
            }
            if (self.take(.kw_type)) {
                const name = (try self.expect(.ident)).span;
                _ = try self.expect(.equal);
                const target = try self.typeName();
                _ = try self.expect(.semicolon);
                try self.markPublic(&public_names, declare_public, name);
                try self.syntax.types.aliases.append(self.storage, .{ .name = name, .target = target });
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
                const statements = try self.storage.alloc(ast.StatementId, 1);
                statements[0] = ret;
                const body = try self.addStatement(.{ .span = .join(name, end), .data = .{ .block = statements } });
                const literal = self.syntax.nodes.items[@backingInt(value)].data;
                // Managed literal getters allocate on read; scalar getters remain pure.
                const allowed = if (literal == .text or literal == .bytes) effects.bit(.managed_allocation) else 0;
                try self.markPublic(&public_names, declare_public, name);
                try functions.append(self.storage, .{ .policy = .{ .constant = true, .effect_bound = .{ .allowed = allowed, .span = name } }, .signature = .{ .parameters = &.{}, .return_type = ty }, .name = name, .body = body });
                continue;
            }
            if (self.current().tag == .ident and std.mem.eql(u8, self.src.text(self.current().span), "resource")) {
                self.cursor.pos += 1;
                const name = try self.expect(.ident);
                _ = try self.expect(.colon);
                const kind = try self.expect(.ident);
                _ = try self.expect(.semicolon);
                try self.markPublic(&public_names, declare_public, name.span);
                try resources.append(self.storage, .{ .name = name.span, .backing = kind.span });
                continue;
            }
            const fallible = self.current().tag == .ident and std.mem.eql(u8, self.src.text(self.current().span), "result");
            if (self.current().tag == .kw_enum or self.current().tag == .kw_union or fallible) {
                const is_union = self.current().tag != .kw_enum;
                const case_head: []const u8 = if (fallible) "result" else if (self.current().tag == .kw_enum) "enum" else "union";
                self.cursor.pos += 1;
                const name = try self.expect(.ident);
                const type_parameters = try self.typeParameters();
                _ = try self.expect(.indent);
                try self.recordDocstring(name.span);
                var cases: std.ArrayList(ast.Variant) = .empty;
                if (self.current().tag != .dedent) while (true) {
                    const tag = try self.expect(.ident);
                    var fields: []const ast.Parameter = &.{};
                    var payload: ?Span = null;
                    if (is_union and self.take(.lparen)) {
                        fields = try self.caseFields();
                    } else if (is_union and self.take(.colon)) {
                        payload = try self.typeName();
                    }
                    try cases.append(self.storage, .{ .name = tag.span, .payload = payload, .fields = fields });
                    if (!self.take(.comma)) {
                        // A next case on its own line is the shape an agent writes
                        // first, so name the rule instead of "expected a dedent".
                        if (self.caseAtSameColumn(tag.span)) return self.hint(.union_cases, self.current().span, caseCommaMessage(case_head), tag.span);
                        break;
                    }
                };
                _ = try self.expect(.dedent);
                try self.markPublic(&public_names, declare_public, name.span);
                try variants.append(self.storage, .{ .type_parameters = type_parameters, .name = name.span, .fallible = fallible, .is_union = is_union, .cases = try cases.toOwnedSlice(self.storage) });
                continue;
            }
            if (self.take(.kw_domain)) {
                const name = try self.expect(.ident);
                _ = try self.expect(.colon);
                const backing = try self.typeName();
                _ = try self.expect(.indent);
                try self.recordDocstring(name.span);
                var codec: ?ast.Codec = null;
                // `pass` spells an empty suite here as it does in a record.
                if (self.take(.kw_pass)) _ = try self.expect(.semicolon);
                while (self.current().tag != .dedent) {
                    if (self.current().tag == .ident and std.mem.eql(u8, self.src.text(self.current().span), "codec")) {
                        if (codec != null) return self.sink.fail("E_DUPLICATE_CODEC", self.current().span, "a domain declares at most one codec");
                        self.cursor.pos += 1;
                        codec = try self.parseCodec();
                    } else try functions.append(self.storage, try self.domainMember(name.span, &attribute_table));
                }
                _ = try self.expect(.dedent);
                try self.attach(&attribute_table, name.span, pending);
                try self.markPublic(&public_names, declare_public, name.span);
                try domains.append(self.storage, .{ .name = name.span, .backing = backing, .codec = codec });
                continue;
            }
            const managed_record = self.take(.kw_class);
            if (managed_record or self.takeRecordHead()) {
                const name = try self.expect(.ident);
                const type_parameters = try self.typeParameters();
                try self.rejectGenericInvariant(pending, type_parameters);
                _ = try self.expect(.indent);
                try self.recordDocstring(name.span);
                const fields = try self.recordFields();
                _ = try self.expect(.dedent);
                try self.attach(&attribute_table, name.span, pending);
                try self.markPublic(&public_names, declare_public, name.span);
                try records.append(self.storage, .{ .managed = managed_record, .type_parameters = type_parameters, .name = name.span, .fields = fields });
                continue;
            }
            if (self.pythonDeclarationHead()) |form| return self.hintHere(form);
            const declared_function = try self.function(null);
            try self.markPublic(&public_names, declare_public, declared_function.name);
            try functions.append(self.storage, declared_function);
            try self.attach(&attribute_table, declared_function.name, pending);
        }
        return .{
            .types = .{
                .resources = try resources.toOwnedSlice(self.storage),
                .variants = try variants.toOwnedSlice(self.storage),
                .domains = try domains.toOwnedSlice(self.storage),
                .expressions = .{
                    .callbacks = try self.syntax.types.callbacks.toOwnedSlice(self.storage),
                    .arrays = try self.syntax.types.arrays.toOwnedSlice(self.storage),
                    .applications = try self.syntax.types.applications.toOwnedSlice(self.storage),
                    .aliases = try self.syntax.types.aliases.toOwnedSlice(self.storage),
                    .tuples = try self.syntax.types.tuples.toOwnedSlice(self.storage),
                },
                .records = try records.toOwnedSlice(self.storage),
                .constraints = try constraints.toOwnedSlice(self.storage),
                .public_declarations = try public_names.toOwnedSlice(self.storage),
            },

            .nodes = try self.settle(ast.Node, &self.syntax.nodes),
            .statements = try self.settle(ast.Statement, &self.syntax.statements),
            .functions = try functions.toOwnedSlice(self.storage),
            .lambdas = try self.syntax.lambdas.toOwnedSlice(self.storage),
            .attributes = try attribute_table.toOwnedSlice(self.storage),
            .docstrings = try self.syntax.docstrings.toOwnedSlice(self.storage),
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
        try self.rejectMutatesClause();
        if (c_abi and !annotated_return) return self.sink.fail("E_EXTERN_SIGNATURE", name.span, "extern functions require an explicit return type (unit for C void)");
        // A foreign call is the one ambient authority left, so every `extern def`
        // and `host def` takes the `Host` capability as a visible first parameter.
        if (host != null) {
            if (parameters.parameters.items.len == 0 or !std.mem.eql(u8, self.src.text(parameters.parameters.items[0].ty), "Host")) return self.sink.fail(
                "E_HOST_CAPABILITY",
                if (parameters.parameters.items.len == 0) name.span else parameters.parameters.items[0].ty,
                "an extern or host declaration must take `host: Host` as its first parameter",
            );
        }
        const body = if (host != null) try self.addStatement(.{ .span = (try self.expect(.semicolon)).span, .data = .{ .block = &.{} } }) else try self.block(name.span);
        // The `mut` positions are read from the parameter list before it is
        // handed over, because `toOwnedSlice` empties the list it returns.
        const mut_positions = try ast.mutPositions(self.storage, try self.declaredMutFlags(parameters.parameters.items));
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
                .parameters = try parameters.parameters.toOwnedSlice(self.storage),
                .return_type = return_type,
                .mut_positions = mut_positions,
                .keyword_only_from = parameters.keyword_only_from,
            },
            .name = name.span,
            .body = body,
        };
    }
    /// One declared parameter list together with the keyword-only boundary its
    /// bare `*` records: the zero-based index of the first parameter after the
    /// `*`, or null when the list has none.
    const ParameterList = struct {
        parameters: std.ArrayList(ast.Parameter) = .empty,
        keyword_only_from: ?usize = null,
    };
    fn functionParameters(self: *Parser) diagnostic.Error!ParameterList {
        var list: ParameterList = .{};
        var default_seen = false;
        if (self.current().tag != .rparen) while (true) {
            if (self.current().tag == .star) {
                if (list.keyword_only_from != null) return self.sink.fail(syntax_code, self.current().span, "`*` may appear once in a parameter list");
                const star = self.current();
                self.cursor.pos += 1;
                if (!self.take(.comma) or self.current().tag == .rparen) return self.sink.fail(syntax_code, star.span, "`*` must be followed by at least one parameter");
                list.keyword_only_from = list.parameters.items.len;
                continue;
            }
            const parameter = try self.declaredName();
            _ = try self.expect(.colon);
            const mutable = self.atMutParameter();
            if (mutable) self.cursor.pos += 1;
            const ty = try self.typeName();
            const default_value = if (self.take(.equal)) try self.defaultArgument() else null;
            // Python's ordering rule holds inside the positional group; the
            // keyword-only group may mix required and defaulted parameters.
            if (list.keyword_only_from == null) {
                if (default_seen and default_value == null) return self.sink.fail(eDefaultArgument, parameter, "required parameters must precede parameters with defaults");
                default_seen = default_seen or default_value != null;
            }
            try list.parameters.append(self.storage, .{ .name = parameter, .ty = ty, .default_value = default_value, .mut = mutable });
            if (!self.take(.comma) or self.current().tag == .rparen) break;
        };
        return list;
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
    /// One record body's ordered field declarations, each with the optional
    /// immutable scalar default it declares after `=`. `pass` spells an empty
    /// body; a required field after a defaulted one is rejected here exactly as
    /// it is in a function parameter list.
    fn recordFields(self: *Parser) diagnostic.Error![]const ast.Parameter {
        var fields: std.ArrayList(ast.Parameter) = .empty;
        var default_field = false;
        const empty_record = self.take(.kw_pass);
        if (empty_record) _ = try self.expect(.semicolon);
        if (!empty_record and self.current().tag != .dedent) while (true) {
            // A method belongs to the record's functions, not to its field list.
            if (self.current().tag == .kw_def) return self.hintHere(.method);
            const field = try self.declaredName();
            _ = try self.expect(.colon);
            const ty = try self.typeName();
            const default_value = if (self.take(.equal)) try self.defaultArgument() else null;
            if (default_field and default_value == null) return self.sink.fail(eDefaultArgument, field, "required fields must precede fields with defaults");
            default_field = default_field or default_value != null;
            try fields.append(self.storage, .{ .default_value = default_value, .name = field, .ty = ty });
            const next_field = self.current().tag != .dedent and lex.implicitTerminator(self.src.bytes, self.tokens, self.cursor.pos);
            if (!self.take(.comma) and !next_field) break;
        };
        return fields.toOwnedSlice(self.storage);
    }
    /// One parenthesized case's ordered named fields, with the same default rule
    /// as a record body: at least one field, a required field may not follow a
    /// defaulted one, and a default is an immutable scalar literal.
    fn caseFields(self: *Parser) diagnostic.Error![]const ast.Parameter {
        var fields: std.ArrayList(ast.Parameter) = .empty;
        var default_field = false;
        if (self.current().tag == .rparen) return self.sink.fail("E_CASE_FIELDS", self.current().span, "a parenthesized case declares at least one named field");
        while (true) {
            const field = try self.declaredName();
            _ = try self.expect(.colon);
            const ty = try self.typeName();
            const default_value = if (self.take(.equal)) try self.defaultArgument() else null;
            if (default_field and default_value == null) return self.sink.fail(eDefaultArgument, field, "required fields must precede fields with defaults");
            default_field = default_field or default_value != null;
            try fields.append(self.storage, .{ .default_value = default_value, .name = field, .ty = ty });
            if (!self.take(.comma) or self.current().tag == .rparen) break;
        }
        _ = try self.expect(.rparen);
        return fields.toOwnedSlice(self.storage);
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
                try parameters.append(self.storage, .{ .name = name, .requirements = &.{}, .default_copy = true });
                if (!self.take(.comma)) break;
                continue;
            }
            _ = try self.expect(.colon);
            if (constant_length) {
                if (self.current().tag != .kw_u64) return self.sink.fail(eRequirement, self.current().span, "named constraint bounds are not permitted on constant-length parameters");
                _ = self.take(.kw_u64);
                try parameters.append(self.storage, .{ .name = name, .requirements = &.{}, .constant_length = true });
                if (!self.take(.comma)) break;
                continue;
            }
            var collected = try self.requirementList(true, null);
            try parameters.append(self.storage, .{
                .name = name,
                .requirements = try collected.builtins.toOwnedSlice(self.storage),
                .field_requirements = try collected.fields.toOwnedSlice(self.storage),
                .operation_requirements = try collected.operations.toOwnedSlice(self.storage),
                .named_requirements = try collected.names.toOwnedSlice(self.storage),
            });
            if (!self.take(.comma)) break;
        }
        _ = try self.expect(.rbracket);
        return parameters.toOwnedSlice(self.storage);
    }
    /// Parse one `+`-separated requirement list, rejecting named references when
    /// `allow_named` is false and reporting them against `owner` when it is the
    /// declaration's own subject.
    fn requirementList(self: *Parser, allow_named: bool, owner: ?Span) diagnostic.Error!RequirementCollections {
        var result: RequirementCollections = .{};
        const allocator = self.storage;
        while (true) {
            const requirement = (try self.expect(.ident)).span;
            const text = self.src.text(requirement);
            const count = result.builtins.items.len + result.fields.items.len + result.operations.items.len + result.names.items.len;
            if (count == 16) return self.sink.fail(eGenericLimit, requirement, "at most 16 requirements are permitted");
            if (std.mem.eql(u8, text, "field")) {
                _ = try self.expect(.lparen);
                const field = try self.constraintParameter();
                _ = try self.expect(.rparen);
                try result.fields.append(allocator, field);
            } else if (std.mem.eql(u8, text, "op")) {
                try result.operations.append(allocator, try self.operationConstraint());
            } else if (std.meta.stringToEnum(requirements.Requirement, text) != null) {
                for (result.builtins.items) |previous| if (std.mem.eql(u8, self.src.text(previous), text)) return self.sink.fail(eRequirement, requirement, "duplicate type requirement");
                try result.builtins.append(allocator, requirement);
            } else {
                const reference = try self.boundReference(requirement);
                if (!allow_named) {
                    const self_reference = owner != null and reference.alias == null and std.mem.eql(u8, self.src.text(owner.?), self.src.text(reference.name));
                    return self.sink.fail(eRequirement, requirement, if (self_reference) "a constraint definition cannot refer to itself" else "a constraint definition cannot reference another named constraint");
                }
                for (result.names.items) |previous| {
                    const both_unqualified = previous.alias == null and reference.alias == null;
                    const same_alias = both_unqualified or (previous.alias != null and reference.alias != null and std.mem.eql(u8, self.src.text(previous.alias.?), self.src.text(reference.alias.?)));
                    const same_name = std.mem.eql(u8, self.src.text(previous.name), self.src.text(reference.name));
                    if (same_alias and same_name) return self.sink.fail(eRequirement, requirement, "duplicate type requirement");
                }
                try result.names.append(allocator, reference);
            }
            if (!self.take(.plus)) break;
        }
        return result;
    }
    /// Parse one bound reference after its first identifier was consumed; a
    /// qualified alias is only admitted in module syntax.
    fn boundReference(self: *Parser, first: Span) diagnostic.Error!ast.BoundReference {
        if (self.module_syntax and self.current().tag == .dot and self.syntax.import_aliases.contains(self.src.text(first)) and self.sameExpressionLine()) {
            self.cursor.pos += 1;
            const name = try self.declaredName();
            try self.rejectBoundArguments();
            return .{ .alias = first, .name = name };
        }
        try self.rejectBoundArguments();
        return .{ .alias = null, .name = first };
    }
    fn rejectBoundArguments(self: *Parser) diagnostic.Error!void {
        if (self.current().tag == .lbracket) return self.sink.fail(eRequirement, self.current().span, "a named constraint bound cannot take type arguments");
    }
    /// Parse `constraint NAME[SUBJECT] = REQUIREMENTS;` after its contextual head.
    fn constraintDeclaration(self: *Parser, head: Span) diagnostic.Error!ast.Constraint {
        const name = (try self.expect(.ident)).span;
        _ = try self.expect(.lbracket);
        if (self.current().tag != .ident) return self.sink.fail(syntax_code, self.current().span, "constraint subject must be one bare name");
        const subject_name = (try self.expect(.ident)).span;
        if (self.current().tag != .rbracket) return self.sink.fail(syntax_code, self.current().span, "constraint subject must be one bare name with no bound, default, or const parameter");
        _ = try self.expect(.rbracket);
        _ = try self.expect(.equal);
        var collected = try self.requirementList(false, name);
        const end = try self.expect(.semicolon);
        const allocator = self.storage;
        return .{
            .name = name,
            .span = .join(head, end.span),
            .subject = .{
                .name = subject_name,
                .requirements = try collected.builtins.toOwnedSlice(allocator),
                .field_requirements = try collected.fields.toOwnedSlice(allocator),
                .operation_requirements = try collected.operations.toOwnedSlice(allocator),
                .named_requirements = try collected.names.toOwnedSlice(allocator),
            },
        };
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
            try parameters.append(self.storage, try self.constraintParameter());
            if (!self.take(.comma) or self.current().tag == .rparen) break;
        };
        _ = try self.expect(.rparen);
        _ = try self.expect(.arrow);
        const result = try self.typeName();
        const bound = try self.effectBound() orelse return self.sink.fail(eRequirement, name, "structural operations require an explicit effects bound");
        _ = try self.expect(.rparen);
        return .{ .name = name, .parameters = try parameters.toOwnedSlice(self.storage), .return_type = result, .effect_bound = bound };
    }
    /// Reject the retired `mutates(name, ...)` clause where a signature could
    /// still spell it. The clause was how a write was declared before
    /// `name: mut T`, so the rejection names that replacement at the clause's own
    /// span and never reads the positional names inside it.
    fn rejectMutatesClause(self: *Parser) diagnostic.Error!void {
        const token = self.current();
        if (token.tag != .ident or !std.mem.eql(u8, self.src.text(token.span), "mutates")) return;
        return self.sink.fail(removed_spelling_code, token.span, "`mutates(...)` was removed; mark each written parameter `name: mut T`");
    }
    /// The `mut` flag list one declared parameter list records, in source order.
    /// Positions come from `ast.mutPositions` so the declaration side and the
    /// callback-type side cannot drift apart.
    fn declaredMutFlags(self: *Parser, parameters: []const ast.Parameter) std.mem.Allocator.Error![]const bool {
        const flags = try self.storage.alloc(bool, parameters.len);
        for (parameters, flags) |parameter, *flag| flag.* = parameter.mut;
        return flags;
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
                "unknown effect; expected managed_allocation, filesystem, network, clock, random, environment, output, mutation, or host",
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
        try self.syntax.statements.append(self.syntax.growth orelse self.storage, stmt);
        return id;
    }
    /// A finished node or statement list as `storage` keeps it: unchanged when
    /// it grew there, else copied at its exact length and its growth buffer freed.
    fn settle(self: *Parser, comptime T: type, list: *std.ArrayList(T)) diagnostic.Error!std.ArrayList(T) {
        const growth = self.syntax.growth orelse return list.*;
        const owned = try self.storage.dupe(T, list.items);
        list.deinit(growth);
        list.* = .empty;
        return .fromOwnedSlice(owned);
    }
    /// Free the growth buffers a parse that failed before `settle` still holds;
    /// a parser without a separate growth allocator holds none.
    pub fn release(self: *Parser) void {
        const growth = self.syntax.growth orelse return;
        self.syntax.nodes.deinit(growth);
        self.syntax.statements.deinit(growth);
        self.syntax.nodes = .empty;
        self.syntax.statements = .empty;
    }
    /// A string literal's source text with its single or triple quotes removed.
    fn docstringText(self: *Parser, span: Span) []const u8 {
        const raw = self.src.text(span);
        const delimiters = byte_literal.quoteDelimiters(raw);
        if (raw.len < delimiters * 2) return "";
        return raw[delimiters .. raw.len - delimiters];
    }
    /// Consume the current token as `declaration`'s leading docstring when it is
    /// a string literal. The statement never enters the body, so it is inert.
    fn recordDocstring(self: *Parser, declaration: Span) diagnostic.Error!void {
        const token = self.current();
        if (token.tag != .bytes) return;
        self.cursor.pos += 1;
        try self.syntax.docstrings.append(self.storage, .{
            .declaration = declaration,
            .text = self.docstringText(token.span),
            .span = token.span,
        });
    }
    fn block(self: *Parser, owner: ?Span) diagnostic.Error!ast.StatementId {
        try self.enter();
        defer self.cursor.depth -= 1;
        const open = try self.blockOpen();
        // A function body's first string statement documents the function; any
        // other block keeps the ordinary discarded-expression reading.
        if (owner) |declaration| try self.recordDocstring(declaration);
        var statements: std.ArrayList(ast.StatementId) = .empty;
        while (self.current().tag != .dedent) {
            if (self.current().tag == .eof) return self.sink.fail(syntax_code, self.current().span, "block is not closed before the end of the file");
            try statements.append(self.storage, try self.statement());
        }
        _ = try self.expect(.dedent);
        // A dedent stands at the next declaration, so the blank lines and comments
        // between two suites belong to neither; a suite ends where its last token did.
        var written = self.cursor.pos;
        while (written > 1 and self.tokens[written - 1].span.start == self.tokens[written - 1].span.end) written -= 1;
        const close = self.tokens[written - 1].span;
        return self.addStatement(.{ .span = .join(open.span, close), .data = .{ .block = try statements.toOwnedSlice(self.storage) } });
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
        const body = try self.block(null);
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
                const body = try self.block(null);
                try arms.append(self.storage, .{ .ty = pattern.ty, .name = pattern.name, .bindings = pattern.bindings, .body = body });
                if (self.current().tag != .kw_case) break;
            };
            const close = try self.expect(.dedent);
            return self.addStatement(.{ .span = .join(first.span, close.span), .data = .{ .match = .{ .value = value, .arms = try arms.toOwnedSlice(self.storage) } } });
        }
        if (self.take(.kw_if) or self.take(.kw_elif)) {
            const condition = try self.conditionExpression();
            const then_body = try self.block(null);
            const else_body = if (self.current().tag == .kw_elif)
                try self.statement()
            else if (self.take(.kw_else)) try self.block(null) else null;
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
            const body = try self.block(null);
            if (self.current().tag == .kw_else) return self.alternative(expression_code, for_else_message, loop_else_accepted);
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
                var value: ?ast.NodeId = null;
                if (self.take(.comma)) {
                    // A quoted message keeps its decoded literal, which the native
                    // trap carries directly; any other expression is rendered to
                    // standard error on the failure path only.
                    if (self.current().tag == .bytes) {
                        const quoted = try self.expect(.bytes);
                        literal = quoted.span;
                        message = try byte_literal.decode(self.storage, self.src, quoted.span, self.sink);
                    } else {
                        value = try self.expression(0);
                        message = "";
                    }
                }
                break :check .{ .assertion = .{ .condition = condition, .message = message, .literal = literal, .value = value } };
            },
            .kw_break, .kw_continue => exit: {
                self.cursor.pos += 1;
                break :exit .{ .loop_exit = first.tag == .kw_continue };
            },
            .kw_return => ret: {
                self.cursor.pos += 1;
                const empty = self.current().tag == .semicolon or lex.implicitTerminator(self.src.bytes, self.tokens, self.cursor.pos);
                break :ret .{ .ret = if (empty) try self.append(.{ .span = first.span, .data = .unit }) else try self.bareTuple(try self.expression(0)) };
            },
            .ident => assignment: {
                if (self.tokens[self.cursor.pos + 1].tag == .comma) {
                    implicit_discard = true;
                    break :assignment .{ .discard = try self.destructuringAssignment(first) };
                }
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
        const end = try self.statementEnd(first);
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
        var enumerated = false;
        if (try self.rangeBounds(input)) |bounds| {
            start = bounds.start;
            end = bounds.end;
        } else {
            const node = self.syntax.nodes.items[@backingInt(input)];
            if (node.data == .call and node.data.call.owner == null and std.mem.eql(u8, self.src.text(node.data.call.name), "enumerate")) {
                const call = node.data.call;
                if (call.arguments.len != 1 or second_name == null) return self.sink.fail("E_ARITY", node.span, "enumerate requires one iterable and two iteration names");
                iterable = call.arguments[0];
                enumerated = true;
            } else if (node.data == .call and node.data.call.owner == null and std.mem.eql(u8, self.src.text(node.data.call.name), "zip")) {
                const call = node.data.call;
                if (call.arguments.len != 2 or second_name == null) return self.sink.fail("E_ARITY", node.span, "zip requires two iterables and two iteration names");
            }
        }
        const body = try self.block(null);
        if (self.current().tag == .kw_else) return self.alternative(expression_code, for_else_message, loop_else_accepted);
        const span: Span = .join(first.span, self.syntax.statements.items[@backingInt(body)].span);
        if (start) |range_start| {
            if (second_name != null) return self.sink.fail(eIteration, span, "range requires one iteration name");
            return self.addStatement(.{ .span = span, .data = .{ .for_range = .{ .name = first_name, .start = range_start, .end = end.?, .body = body } } });
        }
        return self.addStatement(.{
            .span = span,
            .data = .{ .for_each = .{
                .name = second_name orelse first_name,
                .index_name = if (second_name != null) first_name else null,
                .iterable = iterable,
                .body = body,
                .enumerated = enumerated,
            } },
        });
    }
    /// `x, y = value`: a destructuring assignment. Both sides are `.tuple` nodes
    /// in source order and the whole statement keeps the shape a field
    /// assignment uses, an assignment node inside a discard, so the target list
    /// and the value stay reachable from one node. A bare `x, y` with no `=` is
    /// not a value and is rejected here.
    fn destructuringAssignment(self: *Parser, first: lex.Token) diagnostic.Error!ast.NodeId {
        const name = try self.append(.{ .span = first.span, .data = .{ .name = first.span } });
        self.cursor.pos += 1;
        return self.destructuringFrom(name);
    }
    /// The rest of a destructuring assignment whose first target is parsed.
    fn destructuringFrom(self: *Parser, first: ast.NodeId) diagnostic.Error!ast.NodeId {
        const targets = try self.destructuringTargets(first);
        const target_span = self.syntax.nodes.items[@backingInt(targets)].span;
        if (!self.take(.equal)) return self.sink.fail(syntax_code, target_span, "a bare comma list is not an expression; write `x, y = value` or parenthesize it as a tuple");
        const value = try self.bareTuple(try self.expression(0));
        return self.append(.{
            .span = .join(target_span, self.syntax.nodes.items[@backingInt(value)].span),
            .data = .{ .field_assignment = .{ .target = targets, .value = value } },
        });
    }
    /// The target list of a destructuring assignment: two or more targets
    /// separated by commas, with an optional trailing comma after the last one.
    /// A target is a name, an element `xs[i]` or a field `r.f`
    /// (`PY-DESTRUCTURE-PLACE-1`). One target is never a tuple, so `x, = pair`
    /// is rejected.
    fn destructuringTargets(self: *Parser, first: ast.NodeId) diagnostic.Error!ast.NodeId {
        const allocator = self.storage;
        var elements: std.ArrayList(ast.NodeId) = .empty;
        try elements.append(allocator, first);
        const first_span = self.syntax.nodes.items[@backingInt(first)].span;
        var last = first_span;
        var comma_span: ?Span = null;
        while (self.current().tag == .comma) {
            comma_span = self.current().span;
            _ = self.take(.comma);
            if (self.current().tag == .equal or self.terminatorAhead()) break;
            const target = try self.expression(0);
            const node = self.syntax.nodes.items[@backingInt(target)];
            switch (node.data) {
                .name, .index, .field => {},
                else => return self.sink.fail("E_ASSIGNMENT_TARGET", node.span, "a destructuring target is a name, an element `xs[i]` or a field `r.f`"),
            }
            last = node.span;
            try elements.append(allocator, target);
        }
        if (elements.items.len < 2) return self.sink.fail(syntax_code, comma_span orelse first_span, "a one-element target list is not a tuple; bind the name directly");
        return self.append(.{ .span = .join(first_span, last), .data = .{ .tuple = try elements.toOwnedSlice(allocator) } });
    }
    fn assignmentExpression(self: *Parser) diagnostic.Error!ast.NodeId {
        const value = try self.expression(0);
        // `a[i], a[j] = a[j], a[i]`: a target list that starts with a place.
        if (self.current().tag == .comma) switch (self.syntax.nodes.items[@backingInt(value)].data) {
            .index, .field => return self.destructuringFrom(value),
            else => {},
        };
        const operator = self.current();
        const op = assignmentOperation(operator.tag) orelse return value;
        self.cursor.pos += 1;
        const target = self.syntax.nodes.items[@backingInt(value)];
        if (target.data == .field) {
            const assigned = try self.expression(0);
            return self.append(.{ .span = .join(target.span, self.syntax.nodes.items[@backingInt(assigned)].span), .data = .{ .field_assignment = .{ .target = value, .value = assigned, .op = op } } });
        }
        if (target.data != .index) return self.sink.fail("E_ASSIGNMENT_TARGET", target.span, "indexed assignment requires a list binding and index");
        if (op != .set) {
            const assigned = try self.expression(0);
            return self.append(.{ .span = .join(target.span, self.syntax.nodes.items[@backingInt(assigned)].span), .data = .{ .index_assignment = .{ .target = value, .op = op, .value = assigned } } });
        }
        const arguments = try self.storage.alloc(ast.NodeId, 2);
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
        try self.syntax.nodes.append(self.syntax.growth orelse self.storage, node);
        return id;
    }
    /// Whether the cursor stands at the start of a new logical line: the boundary
    /// an expression stops at unless a delimiter holds the line open. A keyword
    /// that continues an expression on the next line of the same statement is
    /// never parsed across this boundary.
    fn implicitBoundary(self: *Parser) bool {
        if (self.cursor.delimiters != 0) return false;
        if (self.current().tag == .dedent or self.current().tag == .eof) return false;
        return lex.implicitTerminator(self.src.bytes, self.tokens, self.cursor.pos);
    }
    fn expression(self: *Parser, min_precedence: u8) diagnostic.Error!ast.NodeId {
        try self.enter();
        defer self.cursor.depth -= 1;
        const token = self.current();
        if (token.tag == .ident and std.mem.eql(u8, self.src.text(token.span), "lambda")) return self.lambdaExpression(token);
        var left: ast.NodeId = switch (token.tag) {
            .kw_restrict_resource => try self.parseRestrict(token),
            .kw_read_resource, .kw_write_resource => try self.parseResourceIo(token),
            .kw_environment_get => try self.parseEnvironmentGated(token),
            .kw_acquire_resource, .kw_complete_resource => try self.parseResource(token),
            .kw_clock_now, .kw_random_u64 => try self.parseExternalGated(token),
            .kw_stand_in, .kw_clock_advance => try self.parseStandIn(token),
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
            .kw_f64_sqrt => if (self.trustedStdlib())
                try self.parseFloatUnary(token)
            else
                return self.sink.fail(eInternalName, token.span, "`__float_sqrt` is reserved for compiler-internal standard-library sources; use the public `sqrt` operation"),
            .kw_f64_floor, .kw_f64_ceil, .kw_f64_trunc, .kw_f64_abs, .kw_f64_neg, .kw_f64_from_u64, .kw_f64_to_u64 => try self.parseFloatUnary(token),
            .kw_wrap => try self.parseWrap(token),
            .kw_i8, .kw_i16, .kw_i32, .kw_i64, .kw_u8, .kw_u16, .kw_u32, .kw_u64 => try self.parseWidthConversion(token),
            .lbracket => list: {
                _ = self.take(.lbracket);
                var values: std.ArrayList(ast.NodeId) = .empty;
                if (self.current().tag != .rbracket) while (true) {
                    try values.append(self.storage, try self.expression(0));
                    if (values.items.len == 1 and self.current().tag == .kw_for) break :list try self.parseComprehension(token, values.items[0], false);
                    if (!self.take(.comma) or self.current().tag == .rbracket) break;
                };
                const close = try self.expect(.rbracket);
                break :list try self.append(.{ .span = .join(token.span, close.span), .data = .{ .list_literal = try values.toOwnedSlice(self.storage) } });
            },
            .kw_len, .kw_replace => if (self.declaresFunction(token.span) or (token.tag == .kw_replace and self.recordUpdateAhead())) try self.parseLeaf(token) else try self.parseBuiltin(token),
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
                const operand = try self.expression(if (std.mem.eql(u8, self.src.text(token.span), "not")) 3 else 10);
                break :unary try self.append(.{
                    .span = .join(token.span, self.syntax.nodes.items[@backingInt(operand)].span),
                    .data = .{ .unary = .{
                        .op = if (token.tag == .minus) .neg else .not,
                        .operand = operand,
                        .op_span = token.span,
                    } },
                });
            },
            .lparen => try self.parenthesizedExpression(token),
            // `&` before an operand was the borrow marker `mut` replaced
            // (MUT-PARAM-5); only the binary set intersection spells it now.
            .ampersand => {
                _ = try removed_names.reject(self.sink, token.span, "&");
                return self.pythonExpressionFailure(token);
            },
            // A `def` or `match` in expression position, and the second `*` or
            // `<` of a `**` or `<<`, name their accepted spelling; every other
            // token keeps the plain rejection.
            else => return self.pythonExpressionFailure(token),
        };
        while (true) {
            if (self.implicitBoundary()) break;
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
        // `a if p else b` is the loosest expression form and nests to the right.
        if (min_precedence == 0 and self.current().tag == .kw_if and !self.implicitBoundary()) return self.conditionalExpression(left);
        return left;
    }
    /// The `if condition else value` tail of `a if p else b`, taken after the
    /// then-arm has been parsed. The condition is parsed above `or` and the else
    /// arm at the lowest precedence, so `a if p else b if q else c` nests in its
    /// else arm. A `kw_if` on a new logical line starts an `if` statement, not a
    /// conditional, so the caller checks the line boundary first.
    fn conditionalExpression(self: *Parser, then_value: ast.NodeId) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        const condition = try self.expression(1);
        _ = try self.expect(.kw_else);
        const else_value = try self.expression(0);
        return self.append(.{ .span = .join(self.syntax.nodes.items[@backingInt(then_value)].span, self.syntax.nodes.items[@backingInt(else_value)].span), .data = .{ .conditional = .{
            .condition = condition,
            .then_value = then_value,
            .else_value = else_value,
        } } });
    }
    /// One parenthesized expression: `()`, an ordinary grouped expression, or a
    /// tuple. A comma after the first element makes a tuple; without one the
    /// parentheses only group, so `(a)` stays the name `a`.
    fn parenthesizedExpression(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        _ = self.take(.lparen);
        if (self.take(.rparen)) return self.append(.{ .span = .join(token.span, self.tokens[self.cursor.pos - 1].span), .data = .unit });
        const inner = try self.expression(0);
        if (self.current().tag == .colon and self.tokens[self.cursor.pos + 1].tag == .equal) return self.hintHere(.walrus);
        if (self.current().tag == .comma) return self.parenthesizedTuple(token, inner);
        const close = try self.expect(.rparen);
        self.syntax.nodes.items[@backingInt(inner)].span = .join(token.span, close.span);
        return inner;
    }
    /// The trailing elements of a parenthesized tuple, after its first: `(a, b)`,
    /// `(a, b, c)` and `(a, b,)` all build one `.tuple` in source order. A
    /// trailing comma is accepted after two or more elements; `(a,)` is a
    /// one-element tuple, which this language has no value for.
    fn parenthesizedTuple(self: *Parser, open: lex.Token, first: ast.NodeId) diagnostic.Error!ast.NodeId {
        const allocator = self.storage;
        var elements: std.ArrayList(ast.NodeId) = .empty;
        try elements.append(allocator, first);
        var comma_span: ?Span = null;
        while (self.current().tag == .comma) {
            comma_span = self.current().span;
            _ = self.take(.comma);
            if (self.current().tag == .rparen) break;
            try elements.append(allocator, try self.expression(0));
        }
        if (elements.items.len < 2) return self.sink.fail(syntax_code, comma_span orelse self.syntax.nodes.items[@backingInt(first)].span, "a one-element tuple is not a value; write the element alone or a two-element tuple");
        const close = try self.expect(.rparen);
        return self.append(.{ .span = .join(open.span, close.span), .data = .{ .tuple = try elements.toOwnedSlice(allocator) } });
    }
    /// The trailing elements of a bare tuple after its first: the `a, b` of a
    /// `return` or of an assignment's right-hand side. A trailing comma is
    /// accepted after two or more elements; a bare `a,` is a one-element tuple
    /// and stays rejected.
    fn bareTuple(self: *Parser, first: ast.NodeId) diagnostic.Error!ast.NodeId {
        if (self.current().tag != .comma) return first;
        const allocator = self.storage;
        var elements: std.ArrayList(ast.NodeId) = .empty;
        try elements.append(allocator, first);
        var comma_span: ?Span = null;
        while (self.current().tag == .comma) {
            comma_span = self.current().span;
            _ = self.take(.comma);
            if (self.terminatorAhead()) break;
            try elements.append(allocator, try self.expression(0));
        }
        if (elements.items.len < 2) return self.sink.fail(syntax_code, comma_span orelse self.syntax.nodes.items[@backingInt(first)].span, "a one-element tuple is not a value; write the element alone or a two-element tuple");
        const last = self.syntax.nodes.items[@backingInt(elements.items[elements.items.len - 1])].span;
        return self.append(.{ .span = .join(self.syntax.nodes.items[@backingInt(first)].span, last), .data = .{ .tuple = try elements.toOwnedSlice(allocator) } });
    }
    fn lambdaExpression(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        var parameters: std.ArrayList(Span) = .empty;
        if (self.current().tag != .colon) while (true) {
            const parameter = try self.expect(.ident);
            if (std.mem.eql(u8, self.src.text(parameter.span), "_"))
                return self.sink.fail("E_LAMBDA_PARAMETER", parameter.span, "lambda parameters must have a usable name");
            try parameters.append(self.storage, parameter.span);
            if (!self.take(.comma)) break;
        };
        _ = try self.expect(.colon);
        const body = try self.expression(0);
        const span = Span.join(token.span, self.syntax.nodes.items[@backingInt(body)].span);
        try self.syntax.lambdas.append(self.storage, .{
            .span = span,
            .parameters = try parameters.toOwnedSlice(self.storage),
            .body = body,
        });
        return self.append(.{ .span = span, .data = .{ .name = token.span } });
    }
    fn parseMemberSuffix(self: *Parser, left: ast.NodeId) diagnostic.Error!ast.NodeId {
        // `unwrap` is the keyword that opens a domain, so it is never a member
        // name; the value it would extract comes from `match` or `?`.
        if (self.current().tag == .kw_unwrap) return self.hintHere(.option_unwrap);
        // `union` is a declaration keyword, but after a dot it is the set
        // method `s.union(t)` (SET-1).
        const keyword_member = self.current().tag == .kw_union;
        if (keyword_member) self.cursor.pos += 1;
        const name: lex.Token = .{ .tag = .ident, .span = if (keyword_member) self.tokens[self.cursor.pos - 1].span else try self.declaredName() };
        if (self.take(.lparen)) {
            const arguments = try self.callArguments();
            const close = try self.callClose();
            return self.append(.{
                .span = .join(self.syntax.nodes.items[@backingInt(left)].span, close.span),
                .data = .{ .method_call = .{ .base = left, .name = name.span, .arguments = arguments.values, .argument_names = arguments.names } },
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
            .pipe => .bit_or,
            .caret => .bit_xor,
            .ampersand => .bit_and,
            else => unreachable,
        };
    }
    /// Parse the postfix tests that bind below comparison: `in`, `not in`, and
    /// the optional-value identity test `is None` / `is not None`.
    fn parseMembership(self: *Parser, left: ast.NodeId, precedence: u8) diagnostic.Error!?ast.NodeId {
        if (precedence <= 3 and self.current().tag == .kw_is) {
            const none_test = try self.parseNoneTest(left);
            return none_test;
        }
        const not_in = self.current().tag == .bang and self.cursor.pos + 1 < self.tokens.len and self.tokens[self.cursor.pos + 1].tag == .kw_in;
        if (precedence > 3 or (self.current().tag != .kw_in and !not_in)) return null;
        self.cursor.pos += if (not_in) @as(usize, 2) else 1;
        const container = try self.expression(4);
        const span = Span.join(self.syntax.nodes.items[@backingInt(left)].span, self.syntax.nodes.items[@backingInt(container)].span);
        const result = try self.append(.{ .span = span, .data = .{ .membership = .{ .needle = left, .container = container, .negate = not_in } } });
        return result;
    }
    /// Parse only optional-value identity tests, without adding general object identity.
    fn parseNoneTest(self: *Parser, left: ast.NodeId) diagnostic.Error!ast.NodeId {
        const operator = try self.expect(.kw_is);
        const negate = self.take(.bang);
        const none = try self.expect(.kw_none);
        const span = Span.join(self.syntax.nodes.items[@backingInt(left)].span, none.span);
        const test_value = try self.append(.{ .span = span, .data = .{ .unary = .{ .op = .is_none, .operand = left, .op_span = operator.span } } });
        if (!negate) return test_value;
        return self.append(.{ .span = span, .data = .{ .unary = .{ .op = .not, .operand = test_value, .op_span = operator.span } } });
    }
    /// Parse the tail of `[value for name in iterable if condition]` after its
    /// value, or with `set` the tail of `{value for name in iterable if
    /// condition}`. The source and the filter are parsed above the conditional
    /// expression, as Python's grammar parses them: the `if` after the iterable
    /// starts the filter, so `[x for x in xs if p]` never reads as a conditional.
    fn parseComprehension(self: *Parser, token: lex.Token, output: ast.NodeId, set: bool) diagnostic.Error!ast.NodeId {
        _ = try self.expect(.kw_for);
        const name = try self.expect(.ident);
        _ = try self.expect(.kw_in);
        const input = try self.expression(1);
        if (self.current().tag == .kw_for) return self.hintHere(.nested_comprehension);
        const filter = if (self.take(.kw_if)) try self.expression(1) else null;
        const close = if (set) try self.expect(.rbrace) else try self.expect(.rbracket);
        const src: ast.Comprehension.Source = if (try self.rangeBounds(input)) |bounds|
            .{ .range = .{ .start = bounds.start, .end = bounds.end } }
        else
            .{ .iterable = input };
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .comprehension = .{
            .output = output,
            .name = name.span,
            .source = src,
            .filter = filter,
            .set = set,
        } } });
    }

    /// Build `f"a{x}b"` as its alternating literal and interpolated pieces.
    /// Each hole is tokenized from the original bytes, so its spans stay absolute.
    fn parseFormat(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        const allocator = self.storage;
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
        const decoded = try byte_literal.decode(self.storage, self.src, quoted, self.sink);
        return self.append(.{ .span = span, .data = .{ .text = decoded } });
    }

    /// Parse one interpolation as an ordinary expression over its own token range.
    fn formatHole(self: *Parser, span: Span) diagnostic.Error!ast.NodeId {
        const tokens = try lex.lexRange(self.storage, self.src.bytes, span, self.sink);
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
            try entries.append(self.storage, try self.expression(0));
            // A first element followed by a comma, the closing brace or `for`
            // is a set literal or a set comprehension (SET-1); `{}` stays the
            // empty dict, as in Python.
            if (entries.items.len == 1 and self.current().tag == .kw_for) return self.parseComprehension(token, entries.items[0], true);
            if (entries.items.len == 1 and (self.current().tag == .comma or self.current().tag == .rbrace)) return self.parseSetLiteral(token, entries.items[0]);
            _ = try self.expect(.colon);
            try entries.append(self.storage, try self.expression(0));
            if (self.current().tag == .kw_for) return self.hintHere(.dict_comprehension);
            if (!self.take(.comma)) break;
        }
        const close = try self.expect(.rbrace);
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .dictionary_literal = try entries.toOwnedSlice(self.storage) } });
    }
    /// Parse the rest of `{a, b, ...}` after its first element: a set literal.
    /// The elements stay in source order and a trailing comma is accepted.
    fn parseSetLiteral(self: *Parser, token: lex.Token, first: ast.NodeId) diagnostic.Error!ast.NodeId {
        var values: std.ArrayList(ast.NodeId) = .empty;
        try values.append(self.storage, first);
        while (self.take(.comma) and self.current().tag != .rbrace) try values.append(self.storage, try self.expression(0));
        const close = try self.expect(.rbrace);
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .set_literal = try values.toOwnedSlice(self.storage) } });
    }
    fn parseRestrict(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        return self.sink.fail("E_REMOVED_SPELLING", token.span, "`restrict_resource[...]` was removed; use `fs.read_only()`");
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

    /// Reject the raw `environment_get[...]` spelling in ordinary source; only
    /// compiler-owned standard-library bytes may reach its parser arm.
    fn parseEnvironmentGated(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        if (!self.trustedStdlib()) return self.sink.fail(eInternalName, token.span, "`environment_get[...]` is reserved for compiler-internal standard-library sources; use `env.get(\"NAME\")`");
        return self.parseEnvironment(token);
    }

    /// Reject the raw `clock_now[...]`/`random_u64[...]` spellings in ordinary
    /// source; only compiler-owned standard-library bytes may reach their arm.
    fn parseExternalGated(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        if (!self.trustedStdlib()) return self.sink.fail(eInternalName, token.span, "`clock_now[...]` and `random_u64[...]` are reserved for compiler-internal standard-library sources; use the `time` or `random` standard module");
        return self.parseExternalRead(token);
    }

    /// Parse `__stand_in[T](operand)` or `__clock_advance(clock, count)`, which
    /// only compiler-owned standard-library bytes may spell.
    fn parseStandIn(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        if (!self.trustedStdlib()) return self.sink.fail(
            eInternalName,
            token.span,
            "`__stand_in[...]` and `__clock_advance(...)` are reserved for compiler-internal standard-library sources; " ++
                "use `time.simulated_clock`, `random.seeded_entropy`, `filesystem.memory`, `environment.fixed` or `network.denied`",
        );
        self.cursor.pos += 1;
        var ty: ?Span = null;
        if (token.tag == .kw_stand_in) {
            _ = try self.expect(.lbracket);
            ty = try self.typeName();
            _ = try self.expect(.rbracket);
        }
        _ = try self.expect(.lparen);
        const first = try self.expression(0);
        var second: ?ast.NodeId = null;
        if (token.tag == .kw_clock_advance) {
            _ = try self.expect(.comma);
            second = try self.expression(0);
        }
        const close = try self.expect(.rparen);
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .stand_in = .{ .ty = ty, .first = first, .second = second } } });
    }

    fn parseExternalRead(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        _ = try self.expect(.lbracket);
        const ty = try self.typeName();
        _ = try self.expect(.rbracket);
        _ = try self.expect(.lparen);
        const capability = try self.expression(0);
        const close = try self.expect(.rparen);
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .external_read = .{ .kind = if (token.tag == .kw_clock_now) .clock else .random, .ty = ty, .capability = capability } } });
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
        const types = try self.storage.alloc(Span, 1);
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
        const types = try self.storage.alloc(Span, 1);
        types[0] = try self.typeName();
        _ = try self.expect(.rbracket);
        _ = try self.expect(.lparen);
        var arguments: std.ArrayList(ast.NodeId) = .empty;
        if (self.current().tag != .rparen) while (true) {
            try arguments.append(self.storage, try self.expression(0));
            if (!self.take(.comma) or self.current().tag == .rparen) break;
        };
        const close = try self.expect(.rparen);
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .call = .{
            .name = token.span,
            .type_arguments = types,
            .arguments = try arguments.toOwnedSlice(self.storage),
        } } });
    }
    const Pattern = struct { ty: Span, name: Span, bindings: []const ?Span = &.{} };
    fn matchPattern(self: *Parser) diagnostic.Error!Pattern {
        const head = self.current();
        // A case names a union, enum or result case — or `_`, or `None`. A
        // literal here is Python's literal-pattern spelling, which matches by
        // value instead: `if`/`elif` is what this language accepts.
        if (head.tag != .ident and head.tag != .kw_none) return self.hintHere(.match_literal);
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
            var bindings: std.ArrayList(?Span) = .empty;
            if (self.current().tag != .rparen) while (true) {
                const binding = (try self.expect(.ident)).span;
                try bindings.append(self.storage, if (std.mem.eql(u8, self.src.text(binding), "_")) null else binding);
                if (!self.take(.comma) or self.current().tag == .rparen) break;
            };
            _ = try self.expect(.rparen);
            pattern.bindings = try bindings.toOwnedSlice(self.storage);
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
            try names.append(self.storage, name);
            try values.append(self.storage, try self.argumentValue());
            if (!self.take(.comma) or self.current().tag == .rparen) break;
        };
        return .{
            .values = try values.toOwnedSlice(self.storage),
            .names = if (keyword_seen) try names.toOwnedSlice(self.storage) else &.{},
        };
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
        // `m.f[T](x)` where the owner `m` is an import alias (or the whole dotted
        // module path) is an ordinary call; `units.D.make[T](x)` keeps its member
        // application because `units.D` is not an import qualifier.
        const owner = Span.join(self.tokens[self.cursor.pos].span, self.tokens[position - 2].span);
        if (self.module_syntax and self.syntax.import_aliases.contains(self.src.text(owner))) return false;
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
            try arguments.append(self.storage, argument);
            if (!self.take(.comma)) break;
        }
        _ = try self.expect(.rbracket);
        return arguments.toOwnedSlice(self.storage);
    }

    fn parseLeaf(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        if (token.tag == .ident and self.memberApplicationAhead()) {
            var segments: std.ArrayList(Span) = .empty;
            try segments.append(self.storage, (try self.expect(.ident)).span);
            while (self.take(.dot)) try segments.append(self.storage, try self.declaredName());
            const member = segments.items[segments.items.len - 1];
            const owner = Span.join(segments.items[0], segments.items[segments.items.len - 2]);
            const type_arguments = try self.squareTypeArguments();
            _ = try self.expect(.lparen);
            const arguments = try self.callArguments();
            const close = try self.callClose();
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
            const close = try self.callClose();
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
            const close = try self.callClose();
            return self.append(.{ .span = .join(token.span, close.span), .data = .{ .call = .{ .owner = owner, .name = name, .arguments = arguments.values, .argument_names = arguments.names } } });
        }
        return self.append(.{ .span = name, .data = switch (token.tag) {
            .integer => .{ .integer = token.span },
            .bytes => literal: {
                const decoded = try byte_literal.decode(self.storage, self.src, token.span, self.sink);
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
        // Python's bitwise precedence, used by the set operators
        // (SET-OPERATORS-1): `|` below `^` below `&`, all above comparison
        // and below arithmetic.
        .pipe => 5,
        .caret => 6,
        .ampersand => 7,
        .plus, .minus => 8,
        .star, .slash, .slash_slash, .percent => 9,
        else => null,
    };
}
