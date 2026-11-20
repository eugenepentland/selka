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
/// The shapes a default may take beyond a scalar literal: an empty collection, and a constructor (an enum case or a record
/// constructor). A record field allows both; a parameter and a variant field allow neither.
const DefaultForms = struct { collections: bool = false, constructors: bool = false };
const eRequirement = diagnostic.generic_requirement;
const eGenericLimit = diagnostic.generic_limit;
const removed_spelling_code = "E_REMOVED_SPELLING";
const std = @import("std");
const removed_names = @import("removed_names.zig");
const eIteration = "E_ITERATION";
const ast = @import("ast.zig");
const ast_subtree = @import("ast_subtree.zig");
const local_qualifiers = @import("local_qualifiers.zig");
const bind_or_else = @import("bind_or_else.zig");
const on_fail = @import("on_fail.zig");
const loop_detach = @import("loop_detach_syntax.zig");
const lex = @import("lexer.zig");
const Span = @import("source.zig").Span;
const diagnostic = @import("diagnostic.zig");
const quote_in_word = @import("quote_in_word.zig");
const byte_literal = @import("byte_literal.zig");
const number_literal = @import("number_literal.zig");
const requirements = @import("generic_requirements.zig");
const format_strings = @import("format_strings.zig");
/// Tokens that may stand inside an explicit type-argument list: a name, a constant
/// length, nested brackets, and every type the lexer spells as a keyword.
fn typeArgumentToken(tag: lex.Tag) bool {
    return switch (tag) {
        .ident,
        .integer,
        .question,
        .kw_def,
        .lparen,
        .rparen,
        .arrow,
        .colon,
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
    walrus,
};
/// One hinted declaration form: the idiom the friction classifier files the
/// shape under, the primary message, the accepted spelling the note names, and
/// the programs that spell it. `example` holds one program, or several
/// separated by a line of `---`: `src/advice_tables_test.zig` requires each to
/// check, and every backquoted fragment of `accepted` to occur in one of them,
/// so the advice is code the compiler accepts.
pub const DeclarationHint = struct {
    /// The form a call site names.
    form: HintForm,
    /// The idiom the friction classifier files the shape under.
    idiom: []const u8,
    /// The primary message.
    message: []const u8,
    /// The accepted spelling the note names.
    accepted: []const u8,
    /// The program, or the `---`-separated programs, that spell the accepted form.
    example: []const u8,
};
const module_constant_example =
    \\const MAX: int = 42
    \\
    \\func main() -> int:
    \\    return MAX
    \\
;
const method_example =
    \\record Point:
    \\    x: int
    \\    y: int
    \\
    \\func norm1(p: Point) -> int:
    \\    return p.x + p.y
    \\
    \\func main() -> int:
    \\    return norm1(Point(x=1, y=2))
    \\
;
const from_import_example =
    \\import binary
    \\
    \\type Failure = binary.Error
    \\
    \\func describe(code: Failure) -> int:
    \\    match code:
    \\        case Truncated:
    \\            return 1
    \\        case _:
    \\            return 0
    \\
    \\func main() -> int:
    \\    return describe(binary.Error.Overlong)
    \\---
    \\import binary as b
    \\
    \\func main() -> int:
    \\    const code = b.Error.Text
    \\    return len(b.message(code))
    \\
;
const chained_assignment_example =
    \\func main() -> int:
    \\    const x = 21
    \\    const y = 21
    \\    return x + y
    \\
;
const exceptions_example =
    \\func parse(text: str) -> int fails str:
    \\    if len(text) == 0:
    \\        fail "empty"
    \\    return len(text)
    \\
    \\func main() -> int:
    \\    match parse("x"):
    \\        case Ok(value):
    \\            return value
    \\        case Err(reason):
    \\            return len(reason)
    \\
;
const match_literal_example =
    \\func pick(n: int) -> int:
    \\    match n:
    \\        case 1:
    \\            return 10
    \\        case _:
    \\            return 0
    \\
    \\func main() -> int:
    \\    return pick(1)
    \\
;
const del_example =
    \\import lists
    \\import dicts
    \\
    \\func main() -> int:
    \\    mut xs = [1, 2]
    \\    const index = 0
    \\    _ = lists.pop_at(mut xs, index)
    \\    mut d: dict[str, int] = {"a": 1}
    \\    const key = "a"
    \\    _ = dicts.pop(mut d, key)
    \\    return len(xs) + len(d)
    \\
;
const string_prefix_example =
    \\func main() -> int:
    \\    const text = "a\nb"
    \\    return len(text)
    \\
;
const main_guard_example =
    \\func main() -> int:
    \\    return 0
    \\
;
const option_unwrap_example =
    \\func half(x: int) -> int fails str:
    \\    if x % 2 != 0:
    \\        fail "odd"
    \\    return x // 2
    \\
    \\func quarter(x: int) -> int fails str:
    \\    const h = try half(x)
    \\    return try half(h)
    \\
    \\func first(xs: int[]) -> int?:
    \\    if len(xs) == 0:
    \\        return None
    \\    return xs[0]
    \\
    \\func present(xs: int[]) -> int:
    \\    match first(xs):
    \\        case Some(value):
    \\            return value
    \\        case None:
    \\            return 0
    \\
    \\func main() -> int:
    \\    match quarter(8):
    \\        case Ok(value):
    \\            return present([value])
    \\        case Err(_):
    \\            return 1
    \\
;
const walrus_example =
    \\func main() -> int:
    \\    const n = len("abc")
    \\    if n > 2:
    \\        return n
    \\    return 0
    \\
;
/// The hinted forms in `HintForm` order. `tools/friction/classifier.json`
/// files the same idioms in its `hints` array, so the suite's classification and
/// the parser's messaging are one table; `src/declaration_hints_test.zig` and
/// `tests/parser_hints.py` fail when one side names a form the other lacks.
pub const declaration_hints = [_]DeclarationHint{
    .{
        .form = .module_constant,
        .idiom = "module-constant",
        .message = "a bare assignment declares no module-level binding",
        .accepted = "declare it as a constant: `const MAX: int = 42`",
        .example = module_constant_example,
    },
    .{
        .form = .method,
        .idiom = "method",
        .message = "a record or class body declares fields, not methods",
        .accepted = "declare a top-level function taking the record: `func norm1(p: Point) -> int`",
        .example = method_example,
    },
    .{
        .form = .from_import,
        .idiom = "from-import",
        .message = "a from-import is not a declaration",
        .accepted = "import the module and use its names, as in `binary.Error`; `type Failure = binary.Error` or `import binary as b` shortens it",
        .example = from_import_example,
    },
    .{
        .form = .chained_assignment,
        .idiom = "chained-assign",
        .message = "a chained assignment declares no binding",
        .accepted = "declare one name per statement: `const x = 21` first, then `const y = 21`",
        .example = chained_assignment_example,
    },
    .{
        .form = .exceptions,
        .idiom = "exceptions",
        .message = "a try statement is not part of the language",
        .accepted = "declare the function `-> int fails str` and match its call: `case Ok(value)` and `case Err(reason)`",
        .example = exceptions_example,
    },
    .{
        .form = .match_literal,
        .idiom = "match-literal",
        .message = "a literal is a whole match arm, not a case payload",
        .accepted = "match the literal as its own arm of a match on an int, str, bytes or bool: `case 1:`",
        .example = match_literal_example,
    },
    .{
        .form = .del_statement,
        .idiom = "del",
        .message = "a del statement is not part of the language",
        .accepted = "remove with `lists.pop_at(mut xs, index)` for a list or `dicts.pop(mut d, key)` for a dictionary",
        .example = del_example,
    },
    .{
        .form = .string_prefix,
        .idiom = "string-prefix",
        .message = "a string prefix is not part of a literal",
        .accepted = "drop the prefix and write the escape in an ordinary quoted string",
        .example = string_prefix_example,
    },
    .{
        .form = .main_guard,
        .idiom = "main-guard",
        .message = "a module has no `__name__` guard",
        .accepted = "delete the guard: running the module calls `func main()` directly",
        .example = main_guard_example,
    },
    .{
        .form = .option_unwrap,
        .idiom = "option-unwrap",
        .message = "`unwrap` is not a method",
        .accepted = "extract with `match`: `case Ok(value)` or `case Some(value)`; prefix `try` propagates a result",
        .example = option_unwrap_example,
    },
    .{
        .form = .walrus,
        .idiom = "walrus",
        .message = "the walrus operator is not part of the language",
        .accepted = "assign the name on its own line first, then test it",
        .example = walrus_example,
    },
};
/// The message of `E_TRY_POSITION`, at a `try` whose operand is an operator expression.
const try_position_message = "`try` takes a call (or a name, field or element), not an operator expression: write the operator outside it (`try f() + 1`, `-try f()`), or extract the fallible operation into a declaration";
/// The message of `E_TRY_POSITION` at a `try` in a module constant's value.
const try_in_constant = "a module constant is computed when the program is compiled, so its value cannot `try`: call the function where the value " ++
    "is needed (`const value = try f()` in a function that fails), or declare a function that returns the result";
/// The message of `E_TRY_POSITION` at a `try` in a default of a parameter or field.
const try_in_default = "a default is computed when the program is compiled, so it cannot `try`: give the parameter or field no default, " ++
    "and pass `try f()` as the argument where it is called";
/// Accepted spellings for Python forms whose rejection is not `E_SYNTAX`, so
/// they have no row in the shared classifier table. Each one names a construct
/// the language accepts today for the same intent; nothing here guesses.
const loop_else_accepted = "use a flag: assign it before the loop, set it before `break`, and test it after";
const nested_def_accepted = "declare the function at the top level and call it from the body";
const power_accepted = "multiply in a loop: `mut total = 1` then `for i in range(exponent): total = total * base`";
/// The accepted `range` arities, shared by the parser and the prelude's `list(range(...))`.
const range_arity = "range requires end; start, end; or start, end, step";
const shift_accepted = "use `shift_left(value, count)` or `shift_right(value, count)`";
const for_else_message = "a loop has no `else` clause";
const set_augment_message = "`&=`, `|=` and `^=` are not operators";
const set_augment_accepted = "rebind a set with the operator, `s = s | t`, or call `s.update(t)`; combine integers with `x = bit_or(x, y)`, `bit_and` or `bit_xor`";
const nested_def_message = "a function body declares statements, not another function";
const power_message = "`**` is not an operator";
const shift_message = "`<<` and `>>` are not operators";
const step_message = "`++` and `--` are not operators";
const step_accepted = "add or subtract one with `x += 1` or `x -= 1`";
const conditional_mark_message = "`a ? b : c` is not a conditional, and `?` after a value only passes its failure on (`f()?`)";
const conditional_mark_accepted = "declare the result first, assign it in an `if`/`else` statement or a `match`, or return in each arm";
/// PY-GENERATOR-2: a generator expression has no length, as in Python.
const generator_code = @import("gather_use.zig").generator_code;
const generator_length_message = "generator arguments were removed; count with an explicit loop";
const generator_length_accepted = "declare `mut count = 0`, then increment count in an explicit for/if loop";
/// PY-GENERATOR-1: an unparenthesized generator argument beside another one. Generator arguments are removed, so the
/// accepted form is the loop that collects the values (F-50's rule: a message names only a spelling that is accepted).
const generator_sole_message = "generator arguments were removed";
const generator_sole_accepted = "collect the values in a typed list with an explicit for/if loop and pass the list";
/// `E_CONDITIONAL`: a value chosen by a condition in a spelling the parser does not read as one (F-50). Conditional
/// values are removed, so the message names the statement form, as `E_CONDITIONAL_EXPRESSION_REMOVED` does.
const conditional_message = "a condition cannot choose a value inside an expression: declare the result first " ++
    "(`mut word: str`), assign it in an `if`/`else` statement (`if on:` then `word = \"a\"`, `else:` then `word = \"b\"`), " ++
    "or return in each arm";
/// `E_SYNTAX` at a second comma after an assert's message (F-72): the message is one `str` expression, so a comma ends
/// it and a third operand is not read. The repair joins the texts, as a call's arguments do not.
const assert_second_comma_message = "an assert takes a condition and one message, and the message is one text; a second comma " ++
    "does not add a third operand: join the texts with `+` or write a format string (`f'text {value}'`)";
/// `E_COMPREHENSION`: a source-first comprehension without `yield`. Comprehensions are removed, so the message names
/// the loop, as `E_COMPREHENSION_REMOVED` does, instead of the `yield` that would only reach that refusal.
const comprehension_message = "comprehensions were removed; use a typed accumulator and explicit for/if statements";
/// Token cursor and allocator-backed syntax builder with bounded recursive nesting.
pub const Parser = struct {
    src: @import("source.zig").Source,
    /// Where the syntax this parser builds lives: the owning project's or compilation's arena.
    storage: std.mem.Allocator,
    tokens: []const lex.Token,
    sink: *diagnostic.Sink,
    cursor: struct {
        dialect: enum { migration, target } = .target,
        pos: usize = 0,
        depth: usize = 0,
        delimiters: usize = 0,
        /// Bit 0/1 records a top-level `func len`/`func replace`, indexed once at
        /// parse start so each prelude call does not rescan the token stream.
        shadowing: u3 = 0,
        recovered: bool = false,
        /// What the statements after the one just read still complete: a bind-or-else, and the `on fail:` clauses.
        pending: Pending = .{},
        /// While a value computed when the program is compiled is read (a module constant, a default), the message of
        /// `E_TRY_POSITION` at a `try` in it.
        compile_time: ?[]const u8 = null,
    } = .{},
    module_syntax: bool = false,
    syntax: struct {
        nodes: std.ArrayList(ast.Node) = .empty,
        statements: std.ArrayList(ast.Statement) = .empty,
        types: struct {
            suffixes: std.ArrayList(ast.TypeSuffix) = .empty,
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
        if (tag == .semicolon and token.tag != .semicolon and (self.previousTag() == .dedent or lex.implicitTerminator(self.src.bytes, self.tokens, self.cursor.pos))) {
            const end = self.tokens[self.cursor.pos - 1].span.end;
            return .{ .tag = .semicolon, .span = .{ .start = end, .end = end } };
        }
        if (!self.take(tag)) {
            if (tag == .ident and lex.isReservedWord(token.tag)) return self.reservedNameFailure(token);
            const unexpected = "unexpected token; expected " ++ comptime lex.spelling(tag);
            if (self.quoteEndedText(token)) |ended| {
                const message = try quote_in_word.reason(self.storage, unexpected, self.src.bytes, ended);
                return self.sink.failRelated(syntax_code, token.span, message, quote_in_word.note(self.src.bytes, ended));
            }
            return self.sink.fail(syntax_code, token.span, unexpected);
        }
        return token;
    }
    /// The quote that ended the text just before `token`, when that text ended inside a word and `token` is the rest of
    /// the word (`'the cat's toy'` reads `'the cat'`, then `s`): F-61.
    fn quoteEndedText(self: *const Parser, token: lex.Token) ?usize {
        if (token.tag != .ident or self.cursor.pos == 0) return null;
        const previous = self.tokens[self.cursor.pos - 1];
        if (previous.tag != .bytes and previous.tag != .format) return null;
        return quote_in_word.closingInsideWord(self.src.bytes, previous.span, token.span);
    }
    /// A reserved word where a name belongs: say which word it is, so the
    /// reader renames the declaration instead of hunting for a syntax slip.
    fn reservedNameFailure(self: *Parser, token: lex.Token) diagnostic.Error {
        const message = try std.fmt.allocPrint(self.storage, "unexpected token; expected a name: `{s}` is a reserved word and cannot be used as one", .{self.src.text(token.span)});
        return self.sink.fail(syntax_code, token.span, message);
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
        return self.alternativeAt(self.current().span, code, message, accepted);
    }
    /// `alternative` at a span the caller names: where the form is written, when the parser failed after it.
    fn alternativeAt(self: *Parser, span: Span, code: []const u8, message: []const u8, accepted: []const u8) diagnostic.Error {
        return self.sink.failRelated(code, span, message, .{ .span = span, .message = accepted, .role = .alternative });
    }
    /// One expression-position Python form with the accepted spelling it has
    /// instead of the grammar production that is missing.
    const ExpressionForm = struct { message: []const u8, accepted: []const u8, at: ?Span = null };
    /// The Python form standing where an expression belongs: a nested `func`, a
    /// `match` expression, or the second `*`/`<` of `**`/`<<`. Every other token
    /// keeps the ordinary "expected an expression" failure.
    fn pythonExpressionFailure(self: *Parser, token: lex.Token) diagnostic.Error {
        const form: ?ExpressionForm = switch (token.tag) {
            .kw_def => .{ .message = nested_def_message, .accepted = nested_def_accepted },
            .star, .star_equal => if (self.previousTag() == .star) .{ .message = power_message, .accepted = power_accepted } else null,
            .lt, .gt => if (self.previousTag() == token.tag) .{ .message = shift_message, .accepted = shift_accepted } else null,
            .le => if (self.previousTag() == .lt) .{ .message = shift_message, .accepted = shift_accepted } else null,
            .ge => if (self.previousTag() == .gt) .{ .message = shift_message, .accepted = shift_accepted } else null,
            .plus => if (self.pairedPlus(token)) .{ .message = step_message, .accepted = step_accepted } else null,
            .equal => switch (self.previousTag()) {
                .pipe, .ampersand, .caret => .{ .message = set_augment_message, .accepted = set_augment_accepted },
                else => null,
            },
            else => if (self.afterMinuses()) .{ .message = step_message, .accepted = step_accepted, .at = .join(self.tokens[self.cursor.pos - 2].span, self.tokens[self.cursor.pos - 1].span) } else null,
        };
        if (form) |shape| return self.alternativeAt(shape.at orelse token.span, expression_code, shape.message, shape.accepted);
        return self.sink.fail(expression_code, token.span, expected_expression);
    }
    /// Whether `token`, where an expression fails, is one `+` of a `++` written together: `x++` fails at the second `+`
    /// and `++x` at the first, since there is no unary `+`.
    fn pairedPlus(self: *Parser, token: lex.Token) bool {
        const at = self.cursor.pos;
        if (at >= 1 and self.tokens[at - 1].tag == .plus and self.tokens[at - 1].span.end == token.span.start) return true;
        return self.tokens[at + 1].tag == .plus and token.span.end == self.tokens[at + 1].span.start;
    }
    /// Whether the two tokens before the cursor are a `--` written together: `x--` then a line that is no operand
    /// (`return 0`, the end of the block), where the second `-` found no operand to negate.
    fn afterMinuses(self: *Parser) bool {
        const at = self.cursor.pos;
        return at >= 2 and self.tokens[at - 1].tag == .minus and self.tokens[at - 2].tag == .minus and self.tokens[at - 2].span.end == self.tokens[at - 1].span.start;
    }
    /// Whether the statement's terminator is already there: an explicit `;`, or
    /// the line break, closing dedent or end of file accepted in its place.
    fn terminatorAhead(self: *Parser) bool {
        return self.current().tag == .semicolon or lex.implicitTerminator(self.src.bytes, self.tokens, self.cursor.pos);
    }
    /// Whether the statement's terminator stands at token `position`, as `terminatorAhead` asks of the current one.
    fn terminatorAt(self: *Parser, position: usize) bool {
        return self.tokens[position].tag == .semicolon or lex.implicitTerminator(self.src.bytes, self.tokens, position);
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
            if (self.previousTag() == .question) return self.alternative(syntax_code, conditional_mark_message, conditional_mark_accepted);
        }
        return self.expect(.semicolon);
    }
    /// The `indent` that opens a suite. A missing indent is already a failure;
    /// the `is`-is-not-an-operator hint that once lived here is gone because
    /// `is None` is an expression now (OPTION-FLOW-1).
    fn blockOpen(self: *Parser) diagnostic.Error!lex.Token {
        return self.expect(.indent);
    }
    /// The `)` that closes a call's arguments.
    fn callClose(self: *Parser) diagnostic.Error!lex.Token {
        return self.closeValues(.rparen);
    }
    /// The bracket that closes a list of values (a call's arguments, a parenthesis, a list, a dictionary or a set literal, an index). A
    /// value that ended in `?` and is followed by anything but the bracket or a comma is the `a ? b : c` of C, as in the statement `statementEnd`
    /// refuses: the failure says what `?` does and what to write, at the same token.
    fn closeValues(self: *Parser, comptime tag: lex.Tag) diagnostic.Error!lex.Token {
        const next = self.current().tag;
        if (self.previousTag() == .question and next != tag and next != .comma) return self.alternative(syntax_code, conditional_mark_message, conditional_mark_accepted);
        return self.expect(tag);
    }
    /// Whether the cursor sits on an identifier in `previous`'s column: the next
    /// case of a union, enum or result written without the separating comma.
    fn nextVariantCase(self: *Parser, previous: Span) bool {
        if (self.take(.comma)) return self.current().tag != .dedent;
        return self.caseAtSameColumn(previous);
    }
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
    /// The plain type of the one literal that makes up a value starting at token `first`, when the statement ends right
    /// after it: `int` for an integer written without a width suffix and inside the `int` range, `float` for a decimal
    /// float, `str` for a text, `bool` for `True` and `False`, each with an optional minus sign on a number. Null for any
    /// other value, where the type is not certain from the literal alone. `last` is the literal's token.
    fn plainLiteral(self: *Parser, first: usize) ?struct { ty: []const u8, last: usize } {
        const negative = self.tokens[first].tag == .minus;
        const last = if (negative) first + 1 else first;
        const token = self.tokens[last];
        const text = self.src.text(token.span);
        const ty: []const u8 = switch (token.tag) {
            .integer => number: {
                if (number_literal.isFloat(text)) {
                    const parsed = number_literal.float(self.storage, text) catch return null;
                    break :number if (parsed == .ok) "float" else return null;
                }
                const parts = switch (number_literal.integer(text)) {
                    .ok => |parts| parts,
                    .bad => return null,
                };
                const magnitude = number_literal.magnitude(parts) orelse return null;
                break :number if (parts.suffix.len == 0 and magnitude <= std.math.maxInt(i64)) "int" else return null;
            },
            .bytes => if (!negative and text[0] != 'b') "str" else return null,
            .kw_true, .kw_false => if (!negative) "bool" else return null,
            else => return null,
        };
        // The literal is no end of file, so a token follows it.
        if (!self.terminatorAt(last + 1)) return null;
        return .{ .ty = ty, .last = last };
    }
    /// `const NAME = value` at the top level (SP1-F-3, W3-F-4): inside a function the type is inferred, which is why the
    /// line is written, but a module constant is declared with its type. The message says so and writes the line as it
    /// should be, with the type inserted after the name as the repair when the value is one literal of a plain type; any
    /// other value gets the form to fill in and no edit. The caret stays on the `=` where the type belongs before.
    fn untypedModuleConstant(self: *Parser, name: Span) diagnostic.Error {
        const written = self.src.text(name);
        const first = self.cursor.pos + 1;
        const plain = self.plainLiteral(first) orelse {
            const form = try std.fmt.allocPrint(self.storage, "a module constant needs its type: write `const {s}: TYPE = ...`", .{written});
            return self.sink.fail(syntax_code, self.current().span, form);
        };
        const value = self.src.bytes[self.tokens[first].span.start..self.tokens[plain.last].span.end];
        const shown = if (value.len <= 40 and std.mem.indexOfScalar(u8, value, '\n') == null) value else "...";
        const message = try std.fmt.allocPrint(self.storage, "a module constant needs its type: write `const {s}: {s} = {s}`", .{ written, plain.ty, shown });
        const insert = try std.fmt.allocPrint(self.storage, ": {s}", .{plain.ty});
        return self.sink.failFix(syntax_code, self.current().span, message, .{ .span = .{ .start = name.end, .end = name.end }, .text = insert });
    }
    fn enter(self: *Parser) diagnostic.Error!void {
        if (self.cursor.depth >= 256) return self.sink.fail("E_NESTING_LIMIT", self.current().span, "parser nesting exceeds 256 levels");
        self.cursor.depth += 1;
    }
    /// Accept a declared name that collides with an intrinsic keyword. `len` and `replace`
    /// are intrinsics in call position only, so both remain ordinary names elsewhere.
    /// The name after a member `.`: any declared name, which includes the contextual
    /// `union` (SET-1).
    fn memberName(self: *Parser) diagnostic.Error!Span {
        return self.declaredName();
    }
    fn declaredName(self: *Parser) diagnostic.Error!Span {
        const token = self.current();
        if (token.tag == .ident) try self.rejectInternalTestName(token);
        if (token.tag != .kw_len and token.tag != .kw_replace) return (try self.expect(.ident)).span;
        self.cursor.pos += 1;
        return token.span;
    }
    /// Only the compiler-embedded standard modules may spell the private
    /// `__float_sqrt` intrinsic. A matching `@stdlib/` path is not enough: the
    /// source bytes must be the exact embedded module.
    fn trustedStdlib(self: Parser) bool {
        return @import("standard_library.zig").trusted(self.src.path, self.src.bytes, self.src.trusted_intrinsics);
    }
    /// Only the compiler-embedded `testing` module may spell its two counter
    /// readers; a matching `@stdlib/` path is not enough, the bytes must be the
    /// embedded module, and the module must be `testing.selka`.
    fn trustedTestingModule(self: Parser) bool {
        return self.trustedStdlib() and std.mem.endsWith(u8, self.src.path, "testing.selka");
    }
    /// `__test_blocks` and `__test_allocations` are the one route to a trial's
    /// counters (`B5`): the `testing` module uses them, ordinary source gets
    /// `E_INTERNAL_NAME`.
    fn rejectInternalTestName(self: *Parser, token: lex.Token) diagnostic.Error!void {
        const text = self.src.text(token.span);
        // Every internal spelling starts with `__`, so an ordinary name costs one
        // length and two byte tests before the comparisons.
        if (text.len < 2 or text[0] != '_' or text[1] != '_') return;
        for ([_][]const u8{ "__test_blocks", "__test_allocations" }) |name| {
            if (!std.mem.eql(u8, text, name)) continue;
            if (self.trustedTestingModule()) return;
            return self.sink.fail(
                eInternalName,
                token.span,
                "`__test_blocks` and `__test_allocations` are reserved for the compiler's `testing` module; " ++
                    "use `testing.steps`, `testing.allocations`, `testing.growth`, `testing.linear` or `testing.constant`",
            );
        }
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
    /// declared name or the type itself, so `func f(mut: int)` and `func f(a: mut)`
    /// are unchanged.
    fn atMutParameter(self: *Parser) bool {
        if (!self.identIsMut()) return false;
        return switch (self.tokens[self.cursor.pos + 1].tag) {
            .comma, .rparen, .equal, .colon, .semicolon, .eof, .dedent, .indent => false,
            else => true,
        };
    }
    /// Whether the `mut` at the cursor opens a binding: a name follows it, or a reserved word that is then
    /// declared (`mut domain = 1`), so the refusal names the word instead of a missing newline.
    fn atMutBinding(self: *Parser) bool {
        const named = self.tokens[self.cursor.pos + 1].tag;
        if (named == .ident) return true;
        if (!lex.isReservedWord(named)) return false;
        return switch (self.tokens[self.cursor.pos + 2].tag) {
            .equal, .colon => true,
            else => false,
        };
    }
    /// Whether the cursor names the contextual `own` marker by text. `own` has no
    /// lexer tag, so a binding, field or parameter named `own` keeps working and
    /// only a marker position reads it as the keyword.
    fn identIsOwn(self: *Parser) bool {
        const token = self.current();
        return token.tag == .ident and std.mem.eql(u8, self.src.text(token.span), "own");
    }
    /// Whether the `own` before the parameter is the doubled `own mut` spelling
    /// the refusal names, rather than a parameter named `own`.
    fn atOwnParameter(self: *Parser) bool {
        if (!self.identIsOwn()) return false;
        const marker = self.current();
        if (marker.span.end >= self.src.bytes.len) return false;
        if (self.src.bytes[marker.span.end] != ' ' and self.src.bytes[marker.span.end] != '\t') return false;
        if (self.tokens[self.cursor.pos + 1].tag != .ident) return false;
        if (self.tokens[self.cursor.pos + 2].tag == .colon) return true;
        const doubled = self.tokens[self.cursor.pos + 2].tag == .ident and
            (self.tokenWord(self.cursor.pos + 1, "mut") or self.tokenWord(self.cursor.pos + 1, "own"));
        return doubled and self.tokens[self.cursor.pos + 3].tag == .colon;
    }
    /// Whether the token at `position` is the contextual word `text`.
    fn tokenWord(self: *Parser, position: usize, text: []const u8) bool {
        const token = self.tokens[position];
        return token.tag == .ident and std.mem.eql(u8, self.src.text(token.span), text);
    }
    /// An `own` expression marker requires whitespace and an identifier-led
    /// operand on the same logical line. Before punctuation, literals or operators it remains a name,
    /// including spaced calls/indexes and subtraction such as `own - 1`.
    fn atOwnArgument(self: *Parser) bool {
        if (!self.identIsOwn()) return false;
        const marker = self.current();
        if (marker.span.end >= self.src.bytes.len) return false;
        const separated = self.src.bytes[marker.span.end] == ' ' or self.src.bytes[marker.span.end] == '\t';
        if (!separated) return false;
        const next = self.cursor.pos + 1;
        if (self.tokens[next].tag != .ident) return false;
        return self.cursor.delimiters != 0 or !lex.implicitTerminator(self.src.bytes, self.tokens, next);
    }
    /// Whether the cursor starts an `own` marker in a callback type, where the
    /// parameter may be a bare type (`func(own Node) -> int`) or a named one.
    /// A colon, comma or `)` after `own` keeps it the type or binder name.
    fn atOwnParameterType(self: *Parser) bool {
        if (!self.identIsOwn()) return false;
        const marker = self.current();
        if (marker.span.end >= self.src.bytes.len) return false;
        if (self.src.bytes[marker.span.end] != ' ' and self.src.bytes[marker.span.end] != '\t') return false;
        return switch (self.tokens[self.cursor.pos + 1].tag) {
            .colon, .comma, .rparen => false,
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
    /// One call argument's value. `mut` is a call marker; `own` also wraps values
    /// in bindings, stores and constructors, so expression parsing handles it.
    fn argumentValue(self: *Parser) diagnostic.Error!ast.NodeId {
        if (!self.atMutArgument()) return self.expression(0);
        const marker = self.current();
        self.cursor.pos += 1;
        if (self.atOwnArgument() or self.atMutArgument()) return self.sink.fail("E_PARAMETER_MODIFIER", marker.span, "a call argument is given away `own` or written `mut`, not both");
        const value = try self.expression(0);
        if (self.syntax.nodes.items[@backingInt(value)].data == .own_argument) return self.sink.fail("E_PARAMETER_MODIFIER", marker.span, "a call argument is given away `own` or written `mut`, not both");
        const span = Span.join(marker.span, self.syntax.nodes.items[@backingInt(value)].span);
        return self.append(.{ .span = span, .data = .{ .mut_argument = value } });
    }
    /// Record a top-level `func len`/`func replace`/`func unwrap` once so shadowing
    /// checks are constant-time instead of a fresh full token scan for every call.
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
            if (std.mem.eql(u8, name, "unwrap")) self.cursor.shadowing |= 4;
        }
    }
    fn declaresFunction(self: Parser, name: Span) bool {
        const text = self.src.text(name);
        const bit: u3 = if (std.mem.eql(u8, text, "len")) 1 else if (std.mem.eql(u8, text, "unwrap")) 4 else 2;
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
    /// Refuse `strings.Builder` in a type's place when the file does not import `strings`: the qualifier is a standard
    /// module, and the repair is its `import` line (W13-S5). Without it the type's `.` is an unexpected token.
    fn refuseUnimportedQualifier(self: *Parser, name: Span) diagnostic.Error!void {
        if (self.current().tag != .dot or !self.sameExpressionLine()) return;
        const import_fix = @import("import_fix.zig");
        const text = self.src.text(name);
        if (self.syntax.import_aliases.contains(text) or !import_fix.standardModule(text)) return;
        const message = try import_fix.unimportedMessage(self.storage, text);
        const edit = try import_fix.edit(self.storage, import_fix.placement(self.src.bytes, text), text);
        return self.sink.failFix(import_fix.code, name, message, edit);
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
    /// Whether the cursor is on `@name` (an `@` then the identifier `name`), without consuming it.
    fn atAttribute(self: *Parser, name: []const u8) bool {
        if (self.current().tag != .at or self.cursor.pos + 1 >= self.tokens.len) return false;
        const next = self.tokens[self.cursor.pos + 1];
        return next.tag == .ident and std.mem.eql(u8, self.src.text(next.span), name);
    }
    /// `@vectorize` above a `for` loop: the loop asks LLVM's loop vectorizer for its widest form.
    fn vectorized(self: *Parser, loop: ast.StatementId, at_span: Span) diagnostic.Error!ast.StatementId {
        const data = &self.syntax.statements.items[@backingInt(loop)].data;
        switch (data.*) {
            .for_range => |*range| range.vectorize = true,
            .for_each => |*each| each.vectorize = true,
            else => return self.sink.fail("E_ATTRIBUTE_TARGET", at_span, "@vectorize attaches to a for loop"),
        }
        return loop;
    }
    /// Take the `named` modifier of a parameter (function declaration or callback type) when it is one. A modifier
    /// is followed by the parameter's name, or by `own` or `mut`, so a `named` followed by `:`, `=`, `,` or `)` is the
    /// parameter's own name (`func count(named: int[])`; `named = 3` is a parameter called `named` that lacks its type,
    /// which `functionParameters` says) or, in a callback type, a bare type called `named`, as `own` and `mut` are:
    /// nothing accepted before changes, since each of those spellings was refused.
    fn takeNamedModifier(self: *Parser) bool {
        const token = self.current();
        if (token.tag != .ident or !std.mem.eql(u8, self.src.text(token.span), "named")) return false;
        switch (self.tokens[self.cursor.pos + 1].tag) {
            .colon, .equal, .comma, .rparen => return false,
            else => {},
        }
        self.cursor.pos += 1;
        return true;
    }
    fn word(self: *Parser, text: []const u8) bool {
        if (self.current().tag != .ident or !std.mem.eql(u8, self.src.text(self.current().span), text)) return false;
        self.cursor.pos += 1;
        return true;
    }
    fn typeName(self: *Parser) diagnostic.Error!Span {
        var base = try self.typeAtom();
        while (true) {
            const kind: @FieldType(ast.TypeSuffix, "kind") = if (self.take(.question)) .optional else if (self.current().tag == .lbracket and self.tokens[self.cursor.pos + 1].tag == .rbracket) array: {
                self.cursor.pos += 2;
                break :array .growable;
            } else break;
            const span: Span = .join(base, self.tokens[self.cursor.pos - 1].span);
            try self.syntax.types.suffixes.append(self.storage, .{ .span = span, .base = base, .kind = kind });
            base = span;
        }
        return base;
    }
    fn typeAtom(self: *Parser) diagnostic.Error!Span {
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
        var own_parameters: std.ArrayList(bool) = .empty;
        var named_parameters: std.ArrayList(bool) = .empty;
        if (self.current().tag != .rparen) while (true) {
            if (parameters.items.len == 16) return self.sink.fail(eGenericLimit, first, "callbacks support at most 16 value parameters");
            // A callback type is positional, so it has no keyword-only group.
            if (self.current().tag == .star) return self.sink.fail(syntax_code, self.current().span, "`*` is not permitted in a callback type; declare the keyword-only parameters on a function");
            const named = self.takeNamedModifier();
            try named_parameters.append(allocator, named);
            // A callback type spells the mode the same way: `func(own Node) -> int`
            // takes its argument, `func(mut Node) -> int` writes it.
            var own = false;
            var prefix_mut = false;
            while (true) {
                if (!own and self.atOwnParameterType()) {
                    own = true;
                    self.cursor.pos += 1;
                    continue;
                }
                const mut_marker = self.identIsMut() and self.tokens[self.cursor.pos + 1].tag == .ident and self.tokens[self.cursor.pos + 2].tag == .colon;
                if (!prefix_mut and mut_marker) {
                    prefix_mut = true;
                    self.cursor.pos += 1;
                    continue;
                }
                break;
            }
            if (own and prefix_mut) return self.sink.fail("E_PARAMETER_MODIFIER", self.current().span, "a parameter takes its value `own` or writes it `mut`, not both");
            var name: ?Span = null;
            if (self.current().tag == .ident and self.tokens[self.cursor.pos + 1].tag == .colon) {
                name = (try self.expect(.ident)).span;
                _ = try self.expect(.colon);
            }
            if (named and name == null) return self.sink.fail("E_PARAMETER_NAME", self.current().span, "a named callable parameter requires a name and type, such as `named limit: int`");
            const mutable = self.atMutParameter();
            if (mutable and (prefix_mut or own)) return self.sink.fail(
                "E_PARAMETER_MODIFIER",
                self.current().span,
                if (own) "a parameter takes its value `own` or writes it `mut`, not both" else "write `mut` once before the parameter name",
            );
            if (mutable) self.cursor.pos += 1;
            try mut_parameters.append(allocator, mutable or prefix_mut);
            try own_parameters.append(allocator, own);
            try parameters.append(allocator, try self.typeName());
            try names.append(allocator, name);
            if (!self.take(.comma) or self.current().tag == .rparen) break;
        };
        _ = try self.expect(.rparen);
        _ = try self.expect(.arrow);
        const result = try self.typeName();
        try self.rejectCallbackBorrow();
        const failure_type = if (self.word("fails")) try self.typeName() else null;
        try self.rejectCallbackBorrow();
        try self.rejectEffectClause(null);
        try self.rejectMutatesClause();
        const span: Span = .join(first, self.tokens[self.cursor.pos - 1].span);
        try self.syntax.types.callbacks.append(allocator, .{
            .span = span,
            .parameters = try parameters.toOwnedSlice(allocator),
            .parameter_names = try names.toOwnedSlice(allocator),
            .return_type = result,
            .failure_type = failure_type,
            .parameter_modes = .{
                .mut = try mut_parameters.toOwnedSlice(allocator),
                .own = try own_parameters.toOwnedSlice(allocator),
                .named = try named_parameters.toOwnedSlice(allocator),
            },
        });
        return span;
    }
    /// Callable types have owning results; only function declarations name lenders.
    fn rejectCallbackBorrow(self: *Parser) diagnostic.Error!void {
        const head = self.current().span;
        if (self.word("from")) return self.sink.fail(syntax_code, head, "function types cannot declare borrowed results; write `from` on a function declaration");
    }
    fn nominalTypeName(self: *Parser) diagnostic.Error!Span {
        const token = try self.expect(.ident);
        const name = try self.qualifiedTail(token.span);
        try self.refuseUnimportedQualifier(name);
        if (self.current().tag == .lbracket and self.tokens[self.cursor.pos + 1].tag == .rbracket) return name;
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
    /// Parse path-named modules and their leading import directives.
    /// Redundant legacy headers are accepted only by migration parsers.
    pub fn parseModule(self: *Parser) diagnostic.Error!ast.Program {
        self.module_syntax = true;
        const first = self.current();
        if (first.tag == .ident and std.mem.eql(u8, self.src.text(first.span), "module")) {
            self.cursor.pos += 1;
            try self.moduleName();
            const end = try self.expect(.semicolon);
            if (self.cursor.dialect == .target) {
                const span: Span = .join(first.span, end.span);
                try self.sink.appendFix(.{ .code = "E_MODULE_HEADER", .span = span, .message = "module names come from file paths; remove the redundant module header" }, .{ .span = span, .text = "" });
                return error.SourceError;
            }
        }
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
            .ident => if (std.mem.eql(u8, text, "extern") or std.mem.eql(u8, text, "host")) .host_function else if (std.mem.eql(u8, text, "builtin")) .function else if (std.mem.eql(u8, text, "record")) .record else .other,
            else => .other,
        };
    }
    /// Reject an attribute placed above a declaration that cannot carry it:
    /// `@requires`/`@ensures` need a `func` with a body, `@invariant` a
    /// `record` or `domain`, and the other attributes a function. A domain
    /// member (`member` set) takes only contract clauses.
    fn checkAttributeTarget(self: *Parser, pending: []const ast.Attribute, member: bool) diagnostic.Error!void {
        if (pending.len == 0) return;
        const head = self.attributeHead();
        for (pending) |attribute| switch (attribute.kind) {
            .invariant => if (head != .record and head != .domain)
                return self.sink.fail(contract_target_code, attribute.span, "`@invariant` attaches to a `record` declaration; a union, enum, alias, constraint or function carries none"),
            .noalloc => if (head != .function)
                return self.sink.fail("E_ATTRIBUTE_TARGET", attribute.span, "@noalloc attaches to a function with a body"),
            .freestanding => if (head != .function)
                return self.sink.fail("E_ATTRIBUTE_TARGET", attribute.span, "@freestanding attaches to a function with a body"),
            .linear => if (head != .record)
                return self.sink.fail("E_ATTRIBUTE_TARGET", attribute.span, "`@linear` attaches to a `record` declaration; a union, enum, alias or function carries none"),
            .sealed => if (head != .record)
                return self.sink.fail("E_ATTRIBUTE_TARGET", attribute.span, "`@sealed` attaches to a `record` declaration; a union, enum, alias, constraint or function carries none"),
            .address => if (member or head != .host_function)
                return self.sink.fail("E_ATTRIBUTE_TARGET", attribute.span, "`@address` attaches to an `extern func` declaration, whose target it makes a value"),
            .requires, .ensures => if (head != .function)
                return self.sink.fail(contract_target_code, attribute.span, if (head == .host_function)
                    "an `extern` or `host` declaration has no body to check a contract in"
                else
                    "`@requires` and `@ensures` attach to a `func` declaration"),
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
        for (pending) |attribute| if (attribute.kind == .linear)
            return self.sink.fail("E_ATTRIBUTE_TARGET", attribute.span, "`@linear` attaches to a non-generic `record`: generic bodies are checked once, without the obligation");
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
                return self.sink.fail("E_UNKNOWN_ATTRIBUTE", clause, "unknown attribute; expected @noalloc, @freestanding, @deprecated, @test, @allow, @requires, @ensures, @invariant, @linear, @sealed or @address");
            // Contract clauses repeat: each one is checked in source order.
            if (!kind.contract()) for (list.items) |existing| if (existing.kind == kind)
                return self.sink.fail("E_DUPLICATE_ATTRIBUTE", clause, "attribute is repeated on one declaration");
            var attribute: ast.Attribute = .{ .kind = kind, .span = clause };
            switch (kind) {
                .noalloc, .@"test", .linear, .sealed, .address => {},
                .freestanding => try self.freestandingPlacement(&attribute, at_token.span),
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
    /// The optional placement of `@freestanding(ram)` (MCU-NOC2B): one word in parentheses, and `ram` is the only one. The
    /// argument is the word's span and the clause runs to the `)`; a bare `@freestanding` keeps no argument.
    fn freestandingPlacement(self: *Parser, attribute: *ast.Attribute, at: Span) diagnostic.Error!void {
        if (!self.take(.lparen)) return;
        const placement = try self.expect(.ident);
        if (!std.mem.eql(u8, self.src.text(placement.span), "ram"))
            return self.sink.fail("E_FREESTANDING", placement.span, "unknown placement of a @freestanding function; the only placement is `ram` (`@freestanding(ram)`: its code runs from RAM)");
        attribute.argument = placement.span;
        attribute.span = .join(at, (try self.expect(.rparen)).span);
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
    const Declarations = struct {
        functions: std.ArrayList(ast.Function) = .empty,
        records: std.ArrayList(ast.Record) = .empty,
        domains: std.ArrayList(ast.Domain) = .empty,
        resources: std.ArrayList(ast.Domain) = .empty,
        variants: std.ArrayList(ast.Variants) = .empty,
        constraints: std.ArrayList(ast.Constraint) = .empty,
        attribute_table: std.ArrayList(ast.DeclarationAttributes) = .empty,
        public_names: std.ArrayList(Span) = .empty,
    };

    /// `extern type Name` declares an opaque C handle type. It is kept with the resource declarations, a named type with
    /// no fields, and its `backing` is the `extern` word, which the type catalog reads (`nominal_catalog.zig`).
    fn externType(self: *Parser, lists: *Declarations, declare_public: bool) diagnostic.Error!bool {
        if (self.current().tag != .ident or !std.mem.eql(u8, self.src.text(self.current().span), "extern")) return false;
        if (self.tokens[self.cursor.pos + 1].tag != .kw_type) return false;
        const head = self.current().span;
        self.cursor.pos += 2;
        const name = try self.expect(.ident);
        _ = try self.expect(.semicolon);
        try self.markPublic(&lists.public_names, declare_public, name.span);
        try lists.resources.append(self.storage, .{ .name = name.span, .backing = head });
        return true;
    }

    fn parseDeclaration(self: *Parser, lists: *Declarations) diagnostic.Error!void {
        const pending = try self.attributes();
        try self.checkAttributeTarget(pending, false);
        // A leading `public` publishes the declaration that follows, so a
        // module marks visibility on the declaration itself. It is not a way
        // to spell the separate `export NAME` directive.
        const declare_public = try self.takePublic();
        if (try self.reexportDirective()) return;
        if (self.current().tag == .ident and std.mem.eql(u8, self.src.text(self.current().span), "constraint")) {
            const head = self.current().span;
            self.cursor.pos += 1;
            const constraint = try self.constraintDeclaration(head);
            try self.markPublic(&lists.public_names, declare_public, constraint.name);
            try lists.constraints.append(self.storage, constraint);
            return;
        }
        if (try self.externType(lists, declare_public)) return;
        if (self.take(.kw_type)) {
            const name = (try self.expect(.ident)).span;
            _ = try self.expect(.equal);
            const target = try self.typeName();
            _ = try self.expect(.semicolon);
            try self.markPublic(&lists.public_names, declare_public, name);
            try self.syntax.types.aliases.append(self.storage, .{ .name = name, .target = target });
            return;
        }
        if (self.take(.kw_const)) {
            const name = (try self.expect(.ident)).span;
            if (self.current().tag == .equal) return self.untypedModuleConstant(name);
            _ = try self.expect(.colon);
            const ty = try self.typeName();
            _ = try self.expect(.equal);
            const value = try self.compileTimeExpression(try_in_constant);
            const end = (try self.expect(.semicolon)).span;
            const ret = try self.addStatement(.{ .span = .join(name, end), .data = .{ .ret = value } });
            const statements = try self.storage.alloc(ast.StatementId, 1);
            statements[0] = ret;
            const body = try self.addStatement(.{ .span = .join(name, end), .data = .{ .block = statements } });
            try self.markPublic(&lists.public_names, declare_public, name);
            try lists.functions.append(self.storage, .{ .policy = .{ .constant = true }, .signature = .{ .parameters = &.{}, .return_type = ty }, .name = name, .body = body });
            return;
        }
        if (self.current().tag == .ident and std.mem.eql(u8, self.src.text(self.current().span), "resource")) {
            self.cursor.pos += 1;
            const name = try self.expect(.ident);
            _ = try self.expect(.colon);
            const kind = try self.expect(.ident);
            _ = try self.expect(.semicolon);
            try self.markPublic(&lists.public_names, declare_public, name.span);
            try lists.resources.append(self.storage, .{ .name = name.span, .backing = kind.span });
            return;
        }
        const fallible = self.current().tag == .ident and std.mem.eql(u8, self.src.text(self.current().span), "result");
        // `union` is a contextual word: the lexer leaves it an identifier and the
        // retired declaration form is recognized by its spelling (batch 0).
        const union_head = self.current().tag == .ident and std.mem.eql(u8, self.src.text(self.current().span), "union");
        if (self.current().tag == .kw_enum or union_head or fallible) {
            var is_union = self.current().tag != .kw_enum;
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
                if (self.take(.lparen)) {
                    fields = try self.caseFields();
                    is_union = true;
                } else if (is_union and self.take(.colon)) {
                    payload = try self.typeName();
                }
                try cases.append(self.storage, .{ .name = tag.span, .payload = payload, .fields = fields });
                if (!self.nextVariantCase(tag.span)) break;
            };
            _ = try self.expect(.dedent);
            try self.markPublic(&lists.public_names, declare_public, name.span);
            try lists.variants.append(self.storage, .{ .type_parameters = type_parameters, .name = name.span, .fallible = fallible, .is_union = is_union, .cases = try cases.toOwnedSlice(self.storage) });
            return;
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
                } else try lists.functions.append(self.storage, try self.domainMember(name.span, &lists.attribute_table));
            }
            _ = try self.expect(.dedent);
            try self.attach(&lists.attribute_table, name.span, pending);
            try self.markPublic(&lists.public_names, declare_public, name.span);
            try lists.domains.append(self.storage, .{ .name = name.span, .backing = backing, .codec = codec });
            return;
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
            try self.attach(&lists.attribute_table, name.span, pending);
            try self.markPublic(&lists.public_names, declare_public, name.span);
            try lists.records.append(self.storage, .{ .managed = managed_record, .type_parameters = type_parameters, .name = name.span, .fields = fields });
            return;
        }
        if (self.pythonDeclarationHead()) |form| return self.hintHere(form);
        const declared_function = try self.function(null);
        try self.markPublic(&lists.public_names, declare_public, declared_function.name);
        try lists.functions.append(self.storage, declared_function);
        try self.attach(&lists.attribute_table, declared_function.name, pending);
    }

    /// Parse a complete source program, retaining syntax and diagnostics in the supplied allocator.
    pub fn parse(self: *Parser) diagnostic.Error!ast.Program {
        self.indexShadowingDeclarations();
        // A leading string statement documents the module itself. The module has
        // no declaration name, so it is keyed on the empty sentinel span.
        try self.recordDocstring(ast.module_docstring_span);
        var lists: Declarations = .{};
        while (self.current().tag != .eof) {
            const start = self.cursor.pos;
            self.parseDeclaration(&lists) catch |err| switch (err) {
                error.SourceError => {
                    self.recover(start);
                    if (self.cursor.pos == start and self.current().tag != .eof) self.cursor.pos += 1;
                },
                else => return err,
            };
        }
        if (self.cursor.recovered) return error.SourceError;
        // A local named like the root of an imported path reads as itself: see `local_qualifiers.zig`.
        if (self.module_syntax and self.syntax.import_aliases.count() != 0) try local_qualifiers.resolve(self.storage, .{
            .src = self.src,
            .tables = .{ .nodes = &self.syntax.nodes, .statements = &self.syntax.statements, .growth = self.syntax.growth orelse self.storage },
            .aliases = &self.syntax.import_aliases,
        }, lists.functions.items);
        const program: ast.Program = .{
            .types = .{
                .resources = try lists.resources.toOwnedSlice(self.storage),
                .variants = try lists.variants.toOwnedSlice(self.storage),
                .domains = try lists.domains.toOwnedSlice(self.storage),
                .expressions = .{
                    .callbacks = try self.syntax.types.callbacks.toOwnedSlice(self.storage),
                    .suffixes = try self.syntax.types.suffixes.toOwnedSlice(self.storage),
                    .arrays = try self.syntax.types.arrays.toOwnedSlice(self.storage),
                    .applications = try self.syntax.types.applications.toOwnedSlice(self.storage),
                    .aliases = try self.syntax.types.aliases.toOwnedSlice(self.storage),
                    .tuples = try self.syntax.types.tuples.toOwnedSlice(self.storage),
                },
                .records = try lists.records.toOwnedSlice(self.storage),
                .constraints = try lists.constraints.toOwnedSlice(self.storage),
                .public_declarations = try lists.public_names.toOwnedSlice(self.storage),
            },

            .nodes = try self.settle(ast.Node, &self.syntax.nodes),
            .statements = try self.settle(ast.Statement, &self.syntax.statements),
            .functions = try lists.functions.toOwnedSlice(self.storage),
            .lambdas = try self.syntax.lambdas.toOwnedSlice(self.storage),
            .attributes = try lists.attribute_table.toOwnedSlice(self.storage),
            .docstrings = try self.syntax.docstrings.toOwnedSlice(self.storage),
        };
        if (self.cursor.dialect == .target and try @import("frontend_migration.zig").publish(self.src, program, self.tokens, self.sink)) return error.SourceError;
        return program;
    }
    /// The code a `builtin func` outside the compiler's own standard-library sources is refused with (W10).
    pub const builtin_declaration_code = "E_BUILTIN_DECLARATION";
    /// Why only the standard library may declare a `builtin func`.
    const builtin_declaration_message = "only the standard library declares a `builtin func`: its calls are supplied by the compiler, " ++
        "which has no operation for a function declared here; give the function a body";
    /// Whether the cursor is at the contextual word `builtin` that opens `builtin func`.
    fn builtinHead(self: *Parser) bool {
        const token = self.current();
        if (token.tag != .ident or !std.mem.eql(u8, self.src.text(token.span), "builtin")) return false;
        return self.cursor.pos + 1 < self.tokens.len and self.tokens[self.cursor.pos + 1].tag == .kw_def;
    }
    /// What the body of a `builtin func` is made from: its name, parameters, and the shape of its result.
    const SuppliedHead = struct { name: Span, parameters: []const ast.Parameter, generic: bool, result: bool, fails: bool };
    /// The body of a `builtin func`, which the page does not write (W10). A generic one gets an empty block: every call
    /// is the operation and a generic function is never a value, so nothing runs it. A non-generic one gets one
    /// statement, a call of itself with each parameter in its own mode (`return upper(text)`), whose call name is the
    /// declaration's own name span; the checker answers that call with the operation (`builtin_functions.zig`), so a
    /// function value of a supplied function runs exactly what a direct call runs.
    fn suppliedBody(self: *Parser, head: SuppliedHead) diagnostic.Error!ast.StatementId {
        const end = (try self.expect(.semicolon)).span;
        if (head.generic) return self.addStatement(.{ .span = end, .data = .{ .block = &.{} } });
        const arguments = try self.storage.alloc(ast.NodeId, head.parameters.len);
        for (head.parameters, arguments) |parameter, *argument| {
            const named = try self.append(.{ .span = parameter.name, .data = .{ .name = parameter.name } });
            argument.* = if (parameter.mut)
                try self.append(.{ .span = parameter.name, .data = .{ .mut_argument = named } })
            else if (parameter.own)
                try self.append(.{ .span = parameter.name, .data = .{ .own_argument = named } })
            else
                named;
        }
        const call = try self.append(.{ .span = head.name, .data = .{ .call = .{ .name = head.name, .arguments = arguments } } });
        const only_statement: ast.Statement = if (head.fails)
            .{ .span = head.name, .data = .{ .ret = try self.append(.{ .span = head.name, .data = .{ .propagate = call } }) } }
        else if (head.result)
            .{ .span = head.name, .data = .{ .ret = call } }
        else
            .{ .span = head.name, .implicit_discard = true, .data = .{ .discard = call } };
        const only = try self.storage.dupe(ast.StatementId, &.{try self.addStatement(only_statement)});
        return self.addStatement(.{ .span = end, .data = .{ .block = only } });
    }
    /// The code a retired `host func` declaration is refused with (NEW-CORE-S5-HOST-1).
    pub const host_retired_code = "E_HOST_RETIRED";
    /// Why `host func` is refused and what replaces it.
    const host_retired = "`host func` is retired (S5-D5): host functions and their registered adapters were removed with the old back end; declare the function `extern func` and link its C implementation with `--link FILE.c`";
    fn function(self: *Parser, owner: ?Span) diagnostic.Error!ast.Function {
        const c_abi = self.current().tag == .ident and std.mem.eql(u8, self.src.text(self.current().span), "extern");
        const host: ?Span = if (c_abi or (self.current().tag == .ident and std.mem.eql(u8, self.src.text(self.current().span), "host"))) self.current().span else null;
        // NEW-CORE-S5-HOST-1: host functions were retired with their registered
        // adapters (S5-D5); C interop is `extern func` with `--link FILE.c`.
        if (host != null and !c_abi) return self.sink.fail(host_retired_code, host.?, host_retired);
        if (host != null) self.cursor.pos += 1;
        // `builtin func`: a declaration whose calls the compiler supplies (W10). It has no body, and only the
        // compiler's own standard-library sources may write one.
        const builtin = host == null and self.builtinHead();
        if (builtin) {
            if (!self.trustedStdlib()) return self.sink.fail(builtin_declaration_code, self.current().span, builtin_declaration_message);
            self.cursor.pos += 1;
        }
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
        const borrowing = try self.borrowingSources(return_type);
        if (host) |span| {
            if (owner != null or restricted or conversion) return self.sink.fail("E_HOST_DECLARATION", span, "host declarations must be ordinary top-level functions");
            if (type_parameters.len != 0) return self.sink.fail("E_HOST_DECLARATION", span, "generic host declarations are not supported");
        }
        const failure_type = if (self.word("fails")) try self.typeName() else null;
        const misplaced_from = self.current().span;
        if (self.word("from")) return self.sink.fail(syntax_code, misplaced_from, "write the `from` clause before `fails`, after the return type");
        try self.rejectEffectClause(if (host == null) name.span else null);
        try self.rejectMutatesClauseOf(parameters.parameters.items);
        if (c_abi and !annotated_return) return self.sink.fail("E_EXTERN_SIGNATURE", name.span, "extern functions require an explicit return type (unit for C void)");
        // A foreign call is the one ambient authority left, so every `extern func`
        // and `host func` takes the `Host` capability as a visible first parameter.
        if (host != null) {
            if (parameters.parameters.items.len == 0 or !std.mem.eql(u8, self.src.text(parameters.parameters.items[0].ty), "Host")) return self.sink.fail(
                "E_HOST_CAPABILITY",
                if (parameters.parameters.items.len == 0) name.span else parameters.parameters.items[0].ty,
                "an extern or host declaration must take `host: Host` as its first parameter",
            );
        }
        // A body's `on fail:` clauses are its own; `fails` decides whether it may hold one.
        self.cursor.pending.cleanup.clauses.clearRetainingCapacity();
        self.cursor.pending.cleanup.tries.clearRetainingCapacity();
        self.cursor.pending.cleanup.fails = failure_type != null;
        if (builtin and (owner != null or restricted or conversion)) return self.sink.fail(builtin_declaration_code, name.span, "a `builtin func` is an ordinary top-level function");
        const body = if (builtin)
            try self.suppliedBody(.{ .name = name.span, .parameters = parameters.parameters.items, .generic = type_parameters.len != 0, .result = annotated_return, .fails = failure_type != null })
        else if (host != null) try self.addStatement(.{ .span = (try self.expect(.semicolon)).span, .data = .{ .block = &.{} } }) else try self.block(name.span);
        // The `mut` positions are read from the parameter list before it is
        // handed over, because `toOwnedSlice` empties the list it returns.
        const mut_positions = try ast.mutPositions(self.storage, try self.declaredMutFlags(parameters.parameters.items));
        return .{
            .policy = .{
                .host = host,
                .c_abi = c_abi,
                .owner = owner,
                .restricted = restricted,
                .conversion = conversion,
                .builtin = builtin,
            },
            .signature = .{
                .type_parameters = type_parameters,
                .parameters = try parameters.parameters.toOwnedSlice(self.storage),
                .return_type = return_type,
                .borrowing = borrowing,
                .failure_type = failure_type,
                .mut_positions = mut_positions,
                .keyword_only_from = parameters.keyword_only_from,
            },
            .name = name.span,
            .body = body,
        };
    }
    /// Parse a contextual `from a, b` between an explicit result and `fails`.
    /// Source eligibility belongs to checking; parsing retains every name.
    fn borrowingSources(self: *Parser, result: Span) diagnostic.Error![]const Span {
        const head = self.current().span;
        if (!self.word("from")) return &.{};
        if (result.start == result.end) return self.sink.fail(syntax_code, head, "a `from` clause requires an explicit return type before it");
        var names: std.ArrayList(Span) = .empty;
        while (true) {
            try names.append(self.storage, try self.declaredName());
            if (!self.take(.comma)) break;
        }
        return names.toOwnedSlice(self.storage);
    }
    /// One declared parameter list together with the keyword-only boundary its
    /// bare `*` records: the zero-based index of the first parameter after the
    /// `*`, or null when the list has none.
    const ParameterList = struct {
        parameters: std.ArrayList(ast.Parameter) = .empty,
        keyword_only_from: ?usize = null,
    };
    /// Whether a parameter's name is followed by a default, a comma or the closing parenthesis where its `:` and type belong.
    fn parameterLacksType(self: *Parser) bool {
        return switch (self.current().tag) {
            .equal, .comma, .rparen => true,
            else => false,
        };
    }
    /// A parameter written without its type (`count = 3`, `named = 3`, `count`): say that it needs one, and how it is written.
    fn missingParameterType(self: *Parser, parameter: Span) diagnostic.Error {
        const name = self.src.text(parameter);
        const default = if (self.current().tag == .equal) " = 3" else "";
        const message = try std.fmt.allocPrint(self.storage, "parameter `{s}` has no type; a parameter needs its type after a colon, as in `{s}: int{s}`", .{ name, name, default });
        return self.sink.fail(syntax_code, self.current().span, message);
    }
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
            const named = self.takeNamedModifier();
            if (named and list.keyword_only_from == null) list.keyword_only_from = list.parameters.items.len;
            // The three modes: `own name`, `mut name`, or plain. `own` and `mut`
            // do not combine, whichever order they are written in.
            var own = false;
            var prefix_mut = false;
            while (true) {
                if (!own and self.atOwnParameter()) {
                    own = true;
                    self.cursor.pos += 1;
                    continue;
                }
                if (!prefix_mut and self.identIsMut() and self.tokens[self.cursor.pos + 1].tag == .ident) {
                    prefix_mut = true;
                    self.cursor.pos += 1;
                    continue;
                }
                break;
            }
            if (own and prefix_mut) return self.sink.fail("E_PARAMETER_MODIFIER", self.current().span, "a parameter takes its value `own` or writes it `mut`, not both");
            const parameter = try self.declaredName();
            if (self.parameterLacksType()) return self.missingParameterType(parameter);
            _ = try self.expect(.colon);
            const mutable = self.atMutParameter();
            if (mutable and (prefix_mut or own)) return self.sink.fail(
                "E_PARAMETER_MODIFIER",
                self.current().span,
                if (own) "a parameter takes its value `own` or writes it `mut`, not both" else "write `mut` once before the parameter name",
            );
            if (mutable) self.cursor.pos += 1;
            const ty = try self.typeName();
            const default_value = if (self.take(.equal)) try self.defaultArgument(.{}) else null;
            // Python's ordering rule holds inside the positional group; the
            // keyword-only group may mix required and defaulted parameters.
            if (list.keyword_only_from == null) {
                if (default_seen and default_value == null) return self.sink.fail(eDefaultArgument, parameter, "required parameters must precede parameters with defaults");
                default_seen = default_seen or default_value != null;
            }
            try list.parameters.append(self.storage, .{ .name = parameter, .ty = ty, .default_value = default_value, .mut = mutable or prefix_mut, .own = own, .named = named });
            if (!self.take(.comma) or self.current().tag == .rparen) break;
        };
        return list;
    }
    /// The default after `=`. Every default is an immutable scalar literal. A record field may also default to an empty
    /// collection (`[]`, `{}`, `b""`, `set()`), a non-empty bytes literal (`b"GND"`), a module constant (`LIMIT`, `limits.MAX`,
    /// or a negated one), an enum case (`Kind.ground`, `Kind.atom(value=1)`) or a record constructor (`Turn()`,
    /// `Turn(angle=0)`) whose arguments are such defaults in turn: each construction that omits the field makes its own
    /// value, so no two records share one. Parameters and variant fields take scalars only. The parser judges the shape;
    /// the checker confirms what a name or a call names (`Checker.requireConstantDefault`).
    fn defaultArgument(self: *Parser, forms: DefaultForms) diagnostic.Error!ast.NodeId {
        const value = try self.compileTimeExpression(try_in_default);
        const node = self.syntax.nodes.items[@backingInt(value)];
        if (!self.defaultShape(value, forms)) {
            const message = if (forms.constructors)
                "defaults must be immutable literals, an empty collection (`[]`, `{}` or `set()`), a module constant, an enum case or a record constructor of such defaults"
            else if (forms.collections)
                "defaults must be immutable scalar literals or an empty collection: `[]`, `{}`, `b\"\"` or `set()`"
            else
                "defaults must be immutable scalar literals";
            return self.sink.fail(eDefaultArgument, node.span, message);
        }
        return value;
    }
    /// Whether `id` has the shape of a default that `forms` allows: a scalar literal, an empty collection, a bytes literal, or
    /// a constructor (a name or member path such as `LIMIT` or `Kind.ground`, or a call) whose arguments have such a shape
    /// themselves. A name that is no constant of the declaring module is refused by the checker, where it resolves.
    fn defaultShape(self: *Parser, id: ast.NodeId, forms: DefaultForms) bool {
        const node = self.syntax.nodes.items[@backingInt(id)];
        const literal = switch (node.data) {
            .integer, .boolean, .unit, .text => true,
            .unary => |unary| unary.op == .neg and self.negatable(unary.operand, forms),
            .list_literal, .dictionary_literal => |items| forms.collections and items.len == 0,
            .bytes => forms.collections,
            .call => |call| forms.collections and self.isEmptySetCall(call),
            else => false,
        };
        if (literal or !forms.constructors) return literal;
        return switch (node.data) {
            .name => true,
            .field => |field| self.namePath(field.base),
            .call => |call| for (call.arguments) |argument| {
                if (!self.defaultShape(argument, forms)) break false;
            } else true,
            else => false,
        };
    }
    /// Whether `-operand` is a default: a number literal, or (where constants are allowed) a name or member path.
    fn negatable(self: *Parser, operand: ast.NodeId, forms: DefaultForms) bool {
        return switch (self.syntax.nodes.items[@backingInt(operand)].data) {
            .integer => true,
            .name => forms.constructors,
            .field => |field| forms.constructors and self.namePath(field.base),
            else => false,
        };
    }
    /// Whether `id` is a name or a chain of member names (`Kind`, `shapes.Kind`).
    fn namePath(self: *Parser, id: ast.NodeId) bool {
        return switch (self.syntax.nodes.items[@backingInt(id)].data) {
            .name => true,
            .field => |field| self.namePath(field.base),
            else => false,
        };
    }
    /// `set()`: the empty set constructor, with no owner, type argument or operand.
    fn isEmptySetCall(self: *Parser, call: anytype) bool {
        return call.owner == null and call.arguments.len == 0 and call.type_arguments.len == 0 and std.mem.eql(u8, self.src.text(call.name), "set");
    }
    /// One record body's ordered field declarations, each with the optional
    /// default it declares after `=`. `pass` spells an empty body. A required field
    /// may follow a defaulted one, since a record is built by field name.
    fn recordFields(self: *Parser) diagnostic.Error![]const ast.Parameter {
        var fields: std.ArrayList(ast.Parameter) = .empty;
        const empty_record = self.take(.kw_pass);
        if (empty_record) _ = try self.expect(.semicolon);
        if (!empty_record and self.current().tag != .dedent) while (true) {
            // A method belongs to the record's functions, not to its field list.
            if (self.current().tag == .kw_def) return self.hintHere(.method);
            const field = try self.declaredName();
            _ = try self.expect(.colon);
            const ty = try self.typeName();
            const default_value = if (self.take(.equal)) try self.defaultArgument(.{ .collections = true, .constructors = true }) else null;
            try fields.append(self.storage, .{ .default_value = default_value, .name = field, .ty = ty });
            const next_field = self.current().tag != .dedent and lex.implicitTerminator(self.src.bytes, self.tokens, self.cursor.pos);
            if (!self.take(.comma) and !next_field) break;
        };
        return fields.toOwnedSlice(self.storage);
    }
    /// One parenthesized case's ordered named fields, with the parameter default
    /// rule: at least one field, a required field may not follow a defaulted one,
    /// and a default is an immutable scalar literal.
    fn caseFields(self: *Parser) diagnostic.Error![]const ast.Parameter {
        var fields: std.ArrayList(ast.Parameter) = .empty;
        var default_field = false;
        if (self.current().tag == .rparen) return self.sink.fail("E_CASE_FIELDS", self.current().span, "a parenthesized case declares at least one named field");
        while (true) {
            const field = try self.declaredName();
            _ = try self.expect(.colon);
            const ty = try self.typeName();
            const default_value = if (self.take(.equal)) try self.defaultArgument(.{}) else null;
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
        try self.rejectEffectClause(null);
        _ = try self.expect(.rparen);
        return .{ .name = name, .parameters = try parameters.toOwnedSlice(self.storage), .return_type = result };
    }
    /// Reject the retired `mutates(name, ...)` clause where a signature could
    /// still spell it. The clause was how a write was declared before
    /// `mut name: T`, so the rejection names that replacement at the clause's own
    /// span and never reads the positional names inside it.
    fn rejectMutatesClause(self: *Parser) diagnostic.Error!void {
        return self.rejectMutatesClauseOf(&.{});
    }
    /// Reject a function declaration's retired `mutates(...)` clause. When every
    /// name in it is one of `parameters`, the diagnostic carries the migration as
    /// a fix: `mut ` in front of each named parameter's type that lacks it, and
    /// the clause deleted together with the blank in front of it.
    fn rejectMutatesClauseOf(self: *Parser, parameters: []const ast.Parameter) diagnostic.Error!void {
        const token = self.current();
        if (token.tag != .ident or !std.mem.eql(u8, self.src.text(token.span), "mutates")) return;
        const message = "`mutates(...)` was removed; write `mut` before the name of each written parameter, as in `mut name: T`";
        const fix = (try self.mutatesMigration(parameters)) orelse return self.sink.fail(removed_spelling_code, token.span, message);
        self.sink.items.append(self.sink.allocator, .{ .code = removed_spelling_code, .span = token.span, .message = message, .provenance = .{ .fix = fix } }) catch return error.OutOfMemory;
        return error.SourceError;
    }
    /// The edits that replace the `mutates(...)` clause at the cursor with `mut`
    /// parameters, or null when the clause is malformed or names something that
    /// is not one of `parameters`.
    fn mutatesMigration(self: *Parser, parameters: []const ast.Parameter) std.mem.Allocator.Error!?diagnostic.Fix {
        const at = self.cursor.pos;
        if (parameters.len == 0 or at == 0 or self.tokens[at + 1].tag != .lparen) return null;
        var marked: [64]bool = @splat(false);
        if (parameters.len > marked.len) return null;
        var cursor = at + 2;
        while (self.tokens[cursor].tag == .ident) {
            const wanted = self.src.text(self.tokens[cursor].span);
            const index = for (parameters, 0..) |parameter, index| {
                if (std.mem.eql(u8, self.src.text(parameter.name), wanted)) break index;
            } else return null;
            marked[index] = true;
            cursor += 1;
            if (self.tokens[cursor].tag != .comma) break;
            cursor += 1;
        }
        if (self.tokens[cursor].tag != .rparen) return null;
        const allocator = self.storage;
        var edits: std.ArrayList(diagnostic.Edit) = .empty;
        for (parameters, marked[0..parameters.len]) |parameter, named| {
            if (!named or parameter.mut) continue;
            try edits.append(allocator, .{ .span = .{ .start = parameter.ty.start, .end = parameter.ty.start }, .text = "mut " });
        }
        const clause: Span = .{ .start = self.tokens[at - 1].span.end, .end = self.tokens[cursor].span.end };
        try edits.append(allocator, .{ .span = clause, .text = "" });
        return .{ .edit = edits.items[0], .more = edits.items[1..] };
    }
    /// The `mut` flag list one declared parameter list records, in source order.
    /// Positions come from `ast.mutPositions` so the declaration side and the
    /// callback-type side cannot drift apart.
    fn declaredMutFlags(self: *Parser, parameters: []const ast.Parameter) std.mem.Allocator.Error![]const bool {
        const flags = try self.storage.alloc(bool, parameters.len);
        for (parameters, flags) |parameter, *flag| flag.* = parameter.mut;
        return flags;
    }
    /// Recognize retired source clauses only to offer a certain migration.
    fn rejectEffectClause(self: *Parser, declaration_name: ?Span) diagnostic.Error!void {
        const token = self.current();
        if (token.tag != .ident) return;
        const spelling = self.src.text(token.span);
        const noalloc = std.mem.eql(u8, spelling, "noalloc");
        const retired = noalloc or std.mem.eql(u8, spelling, "noio") or std.mem.eql(u8, spelling, "effects");
        if (!retired) return;
        self.cursor.pos += 1;
        var span = token.span;
        if (std.mem.eql(u8, spelling, "effects")) {
            _ = try self.expect(.lparen);
            while (self.current().tag != .rparen) {
                _ = try self.expect(.ident);
                if (!self.take(.comma)) break;
            }
            span = .join(span, (try self.expect(.rparen)).span);
        }
        var erase = span;
        while (erase.start > 0 and self.src.bytes[erase.start - 1] == ' ') erase.start -= 1;
        const message = if (noalloc)
            "source effect clauses were removed; write @noalloc above the function declaration"
        else
            "source effect clauses were removed; capability parameters declare authority";
        const item: diagnostic.Diagnostic = .{ .code = "E_EFFECTS_REMOVED", .span = span, .message = message };
        if (noalloc and declaration_name != null) {
            var declaration = declaration_name.?.start;
            while (declaration > 0 and self.src.bytes[declaration - 1] != '\n') declaration -= 1;
            var head = declaration;
            while (head < declaration_name.?.start and (self.src.bytes[head] == ' ' or self.src.bytes[head] == '\t')) head += 1;
            const prefix = self.src.bytes[head..declaration_name.?.start];
            if (std.mem.startsWith(u8, prefix, "func ") or std.mem.startsWith(u8, prefix, "public func ") or std.mem.startsWith(u8, prefix, "private func ")) {
                const attribute = try std.fmt.allocPrint(self.storage, "@noalloc\n{s}", .{self.src.bytes[declaration..head]});
                const edits = try self.storage.dupe(diagnostic.Edit, &.{
                    .{ .span = .{ .start = head, .end = head }, .text = attribute },
                    .{ .span = erase, .text = "" },
                });
                var fixed = item;
                fixed.provenance = .{ .fix = .{ .edit = edits[0], .more = edits[1..] } };
                try self.sink.items.append(self.sink.allocator, fixed);
            } else try self.sink.items.append(self.sink.allocator, item);
        } else try self.sink.appendFix(item, .{ .span = erase, .text = "" });
        // Invalid syntax must not enter the syntax cache without its diagnostic.
        return error.SourceError;
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
    // PARSE-RECOVERY-1: rescan from the failed construct's start so consumed
    // indents still count. A newline at its own depth or its suite's dedent is
    // safe; an enclosing dedent belongs to the caller and must stay unconsumed.
    fn recover(self: *Parser, start: usize) void {
        self.cursor.recovered = true;
        self.cursor.delimiters = 0;
        var nesting: usize = 0;
        var delimiters: usize = 0;
        var at = start;
        while (self.tokens[at].tag != .eof) {
            const tag = self.tokens[at].tag;
            if (tag == .dedent and nesting == 0) break;
            const newline_boundary = at > start and nesting == 0 and delimiters == 0 and tag != .indent;
            if (newline_boundary and !self.recoveryContinuation(at) and lex.implicitTerminator(self.src.bytes, self.tokens, at)) break;
            at += 1;
            switch (tag) {
                .lparen, .lbracket, .lbrace => delimiters += 1,
                .rparen, .rbracket, .rbrace => delimiters -|= 1,
                .indent => nesting += 1,
                .dedent => {
                    nesting -= 1;
                    if (nesting == 0 and at >= self.cursor.pos and !self.recoveryContinuation(at)) break;
                },
                .semicolon => if (nesting == 0 and at >= self.cursor.pos) break,
                else => {},
            }
        }
        self.cursor.pos = at;
    }

    /// A continuation belongs to the damaged compound statement, so neither a
    /// newline nor the preceding suite's dedent can restart parsing there.
    fn recoveryContinuation(self: *const Parser, at: usize) bool {
        const token = self.tokens[at];
        switch (token.tag) {
            .kw_elif, .kw_else, .kw_case => return true,
            .ident => {},
            else => return false,
        }
        // Exception clauses are unsupported syntax, not reserved names. Only
        // skip their header form; a local named `except` or `finally` is valid.
        const text = self.src.text(token.span);
        if (!std.mem.eql(u8, text, "except") and !std.mem.eql(u8, text, "finally")) return false;
        var next = at + 1;
        while (self.tokens[next].tag != .eof and self.tokens[next].tag != .dedent) : (next += 1) {
            if (self.tokens[next].tag == .indent) return true;
            if (lex.implicitTerminator(self.src.bytes, self.tokens, next)) return false;
        }
        return false;
    }

    fn block(self: *Parser, owner: ?Span) diagnostic.Error!ast.StatementId {
        try self.enter();
        defer self.cursor.depth -= 1;
        const open = try self.blockOpen();
        // A function body's first string statement documents the function; any
        // other block keeps the ordinary discarded-expression reading.
        if (owner) |declaration| try self.recordDocstring(declaration);
        var statements: std.ArrayList(ast.StatementId) = .empty;
        const scope = try self.openCleanupScope();
        try self.blockStatements(&statements);
        try self.closeCleanupScope(scope, statements.items);
        _ = try self.expect(.dedent);
        // A dedent stands at the next declaration, so the blank lines and comments
        // between two suites belong to neither; a suite ends where its last token did.
        var written = self.cursor.pos;
        while (written > 1 and self.tokens[written - 1].span.start == self.tokens[written - 1].span.end) written -= 1;
        const close = self.tokens[written - 1].span;
        return self.addStatement(.{ .span = .join(open.span, close), .data = .{ .block = try statements.toOwnedSlice(self.storage) } });
    }
    /// The statements of a block, up to its closing dedent. A bind-or-else takes every statement after it as its success arm,
    /// so the statements that follow one are read here as the body of that arm, and the block ends with it.
    fn blockStatements(self: *Parser, statements: *std.ArrayList(ast.StatementId)) diagnostic.Error!void {
        while (self.current().tag != .dedent) {
            if (self.current().tag == .eof) return self.sink.fail(syntax_code, self.current().span, "block is not closed before the end of the file");
            const start = self.cursor.pos;
            const statement_id = self.statement() catch |err| switch (err) {
                error.SourceError => {
                    self.cursor.pending.bind_else = null;
                    self.recover(start);
                    continue;
                },
                else => return err,
            };
            try statements.append(self.storage, statement_id);
            if (self.cursor.pending.bind_else) |pending| {
                self.cursor.pending.bind_else = null;
                try self.enter();
                defer self.cursor.depth -= 1;
                var rest: std.ArrayList(ast.StatementId) = .empty;
                try self.blockStatements(&rest);
                return self.finishBindOrElse(pending, rest.items);
            }
        }
    }
    /// What a declaration with an `else` tail leaves for its block loop to finish.
    const PendingElse = struct { statement: ast.StatementId, adopt: ?ast.StatementId };
    /// The `match` of a bind-or-else just read, which the statements after it are still to complete, and the `on fail:`
    /// clauses of the function being read (`on_fail.zig`).
    const Pending = struct { bind_else: ?PendingElse = null, cleanup: on_fail.State = .{} };
    /// The parts of `const NAME = EXPR` (or `mut NAME`, or `_ =`) before its `else`.
    const BindHead = struct { first: lex.Token, name: ?Span, annotation: ?Span, mutable: bool, value: ast.NodeId };
    /// Parse `else FAILURE:` and its block after `const NAME = EXPR`, and build the `match` the declaration stands for: the
    /// failure arm holds the block, the success arm binds the payload (its body is filled in by `finishBindOrElse`, once the
    /// statements after the declaration are read). A `mut` or annotated NAME takes the payload through a second binding,
    /// `adopt`, so that it owns it: the arm's own binding of a payload is read-only.
    fn bindOrElse(self: *Parser, head: BindHead) diagnostic.Error!ast.StatementId {
        const else_token = try self.expect(.kw_else);
        const failure = try self.elseFailure(else_token);
        const leave = try self.block(null);
        return self.bindOrElseMatch(head, .{ .failure = failure, .leave = leave, .at = else_token.span });
    }
    /// The failure arm of a bind-or-else: its pattern, its block, and where the `else` (or the `try` it stands for) is.
    const FailureArm = struct { failure: Pattern, leave: ast.StatementId, at: Span };
    /// Build the `match` a bind-or-else stands for, from its head and its failure arm, and leave it pending for the
    /// statements after it.
    fn bindOrElseMatch(self: *Parser, head: BindHead, arm: FailureArm) diagnostic.Error!ast.StatementId {
        const failure = arm.failure;
        const leave = arm.leave;
        const empty = try self.addStatement(.{ .span = arm.at, .data = .{ .block = &.{} } });
        const anchor = head.name orelse head.first.span;
        const bound = [_]?Span{head.name};
        const labels = [_]?Span{null};
        const fields = [_]ast.PatternField{.{ .pattern = .{ .span = anchor, .data = .{ .binding = head.name } } }};
        const arms = try self.storage.dupe(ast.MatchArm, &.{
            .{
                .ty = failure.ty,
                .name = failure.name,
                .bindings = failure.bindings,
                .binding_names = failure.binding_names,
                .payload_patterns = failure.payload_patterns,
                .body = leave,
                .alternatives = .{ .role = .failure },
            },
            .{
                .ty = .{ .start = anchor.start, .end = anchor.start },
                .name = anchor,
                .bindings = try self.storage.dupe(?Span, &bound),
                .binding_names = try self.storage.dupe(?Span, &labels),
                .payload_patterns = try self.storage.dupe(ast.PatternField, &fields),
                .body = empty,
                .alternatives = .{ .role = .success },
            },
        });
        var adopt: ?ast.StatementId = null;
        if (head.name) |name| if (head.mutable or head.annotation != null) {
            const read = try self.append(.{ .span = name, .data = .{ .name = name } });
            adopt = try self.addStatement(.{ .span = Span.join(head.first.span, name), .data = .{ .binding = .{ .name = name, .annotation = head.annotation, .mutable = head.mutable, .value = read, .adopt = true } } });
        };
        const span = Span.join(head.first.span, self.syntax.statements.items[@backingInt(leave)].span);
        const id = try self.addStatement(.{ .span = span, .data = .{ .match = .{ .value = head.value, .arms = arms } } });
        self.cursor.pending.bind_else = .{ .statement = id, .adopt = adopt };
        return id;
    }
    /// The failure a bind-or-else names: `Err(e)`, `Err(_)`, `None`, or nothing (`else:`, the `None` of an Option).
    fn elseFailure(self: *Parser, else_token: lex.Token) diagnostic.Error!Pattern {
        if (self.current().tag == .indent) return .{ .ty = .{ .start = else_token.span.end, .end = else_token.span.end }, .name = else_token.span };
        const pattern = try self.matchPattern();
        const spelling = self.src.text(pattern.name);
        const plain = pattern.ty.start == pattern.ty.end and !pattern.rest;
        const none = plain and std.mem.eql(u8, spelling, "None") and pattern.bindings.len == 0 and pattern.payload_patterns.len == 0;
        const err = plain and std.mem.eql(u8, spelling, "Err") and pattern.bindings.len == 1 and pattern.payload_patterns.len == 1 and pattern.payload_patterns[0].pattern.data == .binding;
        if (!none and !err) return self.sink.fail(bind_or_else.pattern_code, pattern.name, bind_or_else.pattern_message);
        return pattern;
    }
    /// Give the success arm of a bind-or-else the statements after its declaration, and the statement the span that covers them.
    fn finishBindOrElse(self: *Parser, pending: PendingElse, rest: []const ast.StatementId) diagnostic.Error!void {
        const index = @backingInt(pending.statement);
        const declared = self.syntax.statements.items[index];
        const arms = try self.storage.dupe(ast.MatchArm, declared.data.match.arms);
        var body = std.ArrayList(ast.StatementId).empty;
        if (pending.adopt) |adopt| try body.append(self.storage, adopt);
        try body.appendSlice(self.storage, rest);
        var end = declared.span;
        if (rest.len != 0) end = self.syntax.statements.items[@backingInt(rest[rest.len - 1])].span;
        const block_span = if (rest.len != 0) Span.join(self.syntax.statements.items[@backingInt(rest[0])].span, end) else declared.span;
        arms[1].body = try self.addStatement(.{ .span = block_span, .data = .{ .block = try body.toOwnedSlice(self.storage) } });
        self.syntax.statements.items[index] = .{ .span = Span.join(declared.span, end), .data = .{ .match = .{ .value = declared.data.match.value, .arms = arms } } };
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
        } else try self.expression(0);
        const name: ?Span = if (self.take(.kw_as)) (try self.expect(.ident)).span else null;
        const body = try self.block(null);
        return self.addStatement(.{
            .span = .join(first, self.syntax.statements.items[@backingInt(body)].span),
            .data = .{ .with_scope = .{ .resource = resource, .name = name, .body = body } },
        });
    }
    /// A value computed when the program is compiled: a `try` in it is `E_TRY_POSITION` with `message`.
    fn compileTimeExpression(self: *Parser, message: []const u8) diagnostic.Error!ast.NodeId {
        const outer = self.cursor.compile_time;
        self.cursor.compile_time = message;
        defer self.cursor.compile_time = outer;
        return self.expression(0);
    }
    /// Refuse the `try` at token `at` whose operand is an operator expression (`try (a + b)`, `try -f()`). No repair: the
    /// operator belongs outside the `try`, and only the writer knows which operand is the fallible one.
    fn refuseTryPosition(self: *Parser, at: usize) diagnostic.Error {
        return self.sink.fail("E_TRY_POSITION", self.tokens[at].span, try_position_message);
    }
    fn conditionExpression(self: *Parser) diagnostic.Error!ast.NodeId {
        return self.expression(0);
    }
    fn redesignedStatement(self: *Parser, first: lex.Token) diagnostic.Error!?ast.StatementId {
        if (self.current().tag == .kw_const or (self.identIsMut() and self.atMutBinding())) {
            self.cursor.pos += 1;
            const name = try self.declaredName();
            if (self.current().tag == .comma) {
                const declaration = try self.destructuringDeclaration(first, name);
                return declaration;
            }
            const annotation = if (self.take(.colon)) try self.typeName() else null;
            const initialized = self.take(.equal);
            if (!initialized and annotation == null)
                return self.sink.fail("E_BINDING_INITIALIZER", name, "an omitted initializer requires an explicit type, as in `const name: Type` or `mut name: Type`");
            const value = if (initialized) try self.expression(0) else try self.append(.{ .span = .{ .start = name.end, .end = name.end }, .data = .unit });
            if (initialized and self.current().tag == .kw_else) {
                const bound = try self.bindOrElse(.{ .first = first, .name = name, .annotation = annotation, .mutable = first.tag != .kw_const, .value = value });
                return bound;
            }
            const end = try self.statementEnd(first);
            const result = try self.addStatement(.{ .span = .join(first.span, end.span), .data = .{ .binding = .{ .name = name, .annotation = annotation, .mutable = first.tag != .kw_const, .value = value, .initialized = initialized } } });
            return result;
        }
        if (self.word("fail") or self.word("yield")) {
            const failure = std.mem.eql(u8, self.src.text(first.span), "fail");
            const value = try self.expression(0);
            const end = try self.statementEnd(first);
            const result = try self.addStatement(.{ .span = .join(first.span, end.span), .data = if (failure) .{ .fail = value } else .{ .yield_value = value } });
            return result;
        }
        if (self.word("try")) {
            if (self.current().tag == .indent) return self.hintHere(.exceptions);
            self.cursor.pos -= 1;
            const value = try self.expression(0);
            const end = try self.statementEnd(first);
            const result = try self.addStatement(.{ .span = .join(first.span, end.span), .data = .{ .discard = value } });
            return result;
        }
        return null;
    }
    /// A loop's body. Inside an `on fail:` clause it is counted, so a `break` or `continue` that ends a loop of the
    /// clause's own is not taken for one that leaves the clause.
    fn loopBody(self: *Parser) diagnostic.Error!ast.StatementId {
        const inside = &self.cursor.pending.cleanup.inside;
        if (inside.clause) inside.loops += 1;
        defer if (inside.clause) {
            inside.loops -= 1;
        };
        return self.block(null);
    }
    /// The clauses of the enclosing blocks as a block opens: how many there are, whether each is armed, and whether an
    /// earlier block of the same statement consumed its owner (a sibling branch must not see that).
    const CleanupScope = struct { mark: usize, armed: []const bool, consumed: []const bool };
    fn openCleanupScope(self: *Parser) diagnostic.Error!CleanupScope {
        const cleanup = &self.cursor.pending.cleanup;
        const clauses = cleanup.clauses.items;
        if (clauses.len == 0) return .{ .mark = 0, .armed = &.{}, .consumed = &.{} };
        // The head of the statement this block belongs to has been read: what it consumes is consumed in its blocks.
        if (cleanup.head) |start| if (!cleanup.inside.clause) {
            for (clauses) |*clause| if (on_fail.consumes(self.src, self.tokens, start, self.cursor.pos, clause.owners)) {
                clause.flags.armed = false;
            };
        };
        cleanup.head = null;
        const armed = try self.storage.alloc(bool, clauses.len);
        const consumed = try self.storage.alloc(bool, clauses.len);
        for (clauses, armed, consumed) |*clause, *flag, *inside| {
            flag.* = clause.flags.armed;
            inside.* = clause.flags.consumed_inside;
            clause.flags.consumed_inside = false;
        }
        return .{ .mark = clauses.len, .armed = armed, .consumed = consumed };
    }
    /// End the clauses a block registered (each must have been reached by a failure exit) and give the enclosing ones
    /// back the arming they had when the block opened: a branch that consumed an owner disarms its clause only there.
    fn closeCleanupScope(self: *Parser, scope: CleanupScope, statements: []const ast.StatementId) diagnostic.Error!void {
        const clauses = &self.cursor.pending.cleanup.clauses;
        if (clauses.items.len < scope.mark) return;
        for (clauses.items[scope.mark..]) |clause| if (!clause.flags.reached and !clause.flags.branch_disarmed) return self.sink.fail(on_fail.code, clause.span, on_fail.unreached);
        clauses.shrinkRetainingCapacity(scope.mark);
        // A block that consumed an owner and falls through leaves it consumed after the statement that holds the block;
        // one that leaves (`return`, `fail`, `break`, `continue`) does not.
        const falls_through = statements.len == 0 or !on_fail.leavesBlock(self.syntax.statements.items, statements[statements.len - 1]);
        for (clauses.items, scope.armed, scope.consumed) |*clause, armed, earlier| {
            clause.flags.consumed_inside = earlier or (falls_through and armed and !clause.flags.armed);
            clause.flags.armed = armed;
        }
    }
    /// Whether the cursor is on `on fail:` (or `on fail` and an indented block): `on` is a word only there.
    fn atOnFail(self: *Parser) bool {
        if (self.current().tag != .ident or !std.mem.eql(u8, self.src.text(self.current().span), "on")) return false;
        const next = self.tokens[self.cursor.pos + 1];
        if (next.tag != .ident or !std.mem.eql(u8, self.src.text(next.span), "fail")) return false;
        const after = self.tokens[self.cursor.pos + 2].tag;
        return after == .colon or after == .indent;
    }
    /// Read `on fail: STATEMENT` or `on fail:` and a block, and register the clause for the failure exits after it. The
    /// statement it leaves in place is empty: the clause runs only where a failure exit's rewrite places it.
    fn onFailStatement(self: *Parser, first: lex.Token) diagnostic.Error!ast.StatementId {
        const cleanup = &self.cursor.pending.cleanup;
        if (cleanup.inside.clause) return self.sink.fail(on_fail.code, first.span, on_fail.leaves);
        if (!cleanup.fails) return self.sink.fail(on_fail.code, first.span, on_fail.not_failing);
        self.cursor.pos += 2;
        const start = self.cursor.pos;
        cleanup.inside = .{ .clause = true };
        const body = body: {
            defer cleanup.inside = .{};
            if (self.current().tag == .indent) break :body try self.block(null);
            const colon = try self.expect(.colon);
            const only = try self.statement();
            const span = Span.join(colon.span, self.syntax.statements.items[@backingInt(only)].span);
            break :body try self.addStatement(.{ .span = span, .data = .{ .block = try self.storage.dupe(ast.StatementId, &.{only}) } });
        };
        const span = Span.join(first.span, self.syntax.statements.items[@backingInt(body)].span);
        const owners = try on_fail.owners(self.storage, self.src, self.tokens, start, self.cursor.pos);
        try cleanup.clauses.append(self.storage, .{ .body = body, .span = span, .owners = owners });
        return self.addStatement(.{ .span = span, .data = .{ .block = &.{} } });
    }
    /// After a statement is read: inside a clause, refuse what leaves it; in the reach of armed clauses, rewrite a failure
    /// exit so that they run on it, refuse a `try` the rewrite does not cover, and disarm each clause whose owner the
    /// statement consumed.
    fn cleanupExit(self: *Parser, id: ast.StatementId, start: usize) diagnostic.Error!ast.StatementId {
        const cleanup = &self.cursor.pending.cleanup;
        const statement_data = self.syntax.statements.items[@backingInt(id)];
        const nodes = self.syntax.nodes.items;
        if (cleanup.inside.clause) {
            if (on_fail.leavesClause(statement_data, nodes, cleanup.inside.loops)) return self.sink.fail(on_fail.code, statement_data.span, on_fail.leaves);
            return id;
        }
        if (cleanup.clauses.items.len == 0) return id;
        const end = self.cursor.pos;
        try self.declaredAfterClause(statement_data);
        const user = on_fail.userArmed(cleanup.clauses.items);
        if (on_fail.uncovered(statement_data, nodes)) |value| {
            // The `try` is a failure exit the armed clauses would run on: refuse its position, not the clauses as unreached.
            for (cleanup.clauses.items) |*clause| if (clause.flags.armed) {
                clause.flags.reached = true;
            };
            if (!user) return self.sink.fail(loop_detach.try_code, nodes[@backingInt(value)].span, if (cleanup.fails) loop_detach.try_position else loop_detach.optional_try);
            return self.sink.fail(on_fail.code, nodes[@backingInt(value)].span, on_fail.position);
        }
        // A `try` in a call's argument or an operand where a clause would run on it (TRYARG, TRY-2): refused, see
        // `on_fail.argument_position`. A format string's hole is in the statement's bytes, so it is found too.
        const head_end = on_fail.headEnd(self.tokens, start, end);
        const head: Span = .{ .start = self.tokens[start].span.start, .end = self.tokens[head_end - 1].span.end };
        if (cleanup.operandTry(head, on_fail.wholeTry(statement_data, nodes))) |at| for (cleanup.clauses.items) |*clause| {
            if (!clause.flags.armed) continue;
            clause.flags.reached = true;
            if (!user) return self.sink.fail(loop_detach.try_code, at, if (cleanup.fails) loop_detach.try_position else loop_detach.optional_try);
            return self.sink.fail(on_fail.code, at, on_fail.argument_position);
        };
        // A user's own bind-or-else: its `else` block's exits were read as statements already.
        if (self.cursor.pending.bind_else == null) switch (statement_data.data) {
            .binding => |binding| if (binding.initialized and on_fail.isPropagate(nodes, binding.value)) {
                return self.exitDeclaration(.{ .first = self.tokens[start], .name = binding.name, .annotation = binding.annotation, .mutable = binding.mutable, .value = binding.value }, .{ .id = id, .start = start, .end = end });
            },
            .discard => |value| if (on_fail.isPropagate(nodes, value)) {
                return self.exitDeclaration(.{ .first = self.tokens[start], .name = null, .annotation = null, .mutable = false, .value = value }, .{ .id = id, .start = start, .end = end });
            },
            .fail => return self.exitFail(id, start, end),
            else => {},
        };
        self.disarm(start, end);
        return id;
    }
    /// A statement read in a clause's reach, by its id and its tokens.
    const Read = struct { id: ast.StatementId, start: usize, end: usize };
    /// Refuse a declaration of a name an active clause consumes: the clause would name a binding that did not exist
    /// where it was written.
    fn declaredAfterClause(self: *Parser, statement_data: ast.Statement) diagnostic.Error!void {
        const name = switch (statement_data.data) {
            .binding => |binding| binding.name,
            else => return,
        };
        const text = self.src.text(name);
        for (self.cursor.pending.cleanup.clauses.items) |clause| for (clause.owners) |owner| if (std.mem.eql(u8, owner, text)) {
            return self.sink.failRelated(on_fail.code, name, on_fail.declared_after, .{ .span = clause.span, .message = "the clause" });
        };
    }
    /// Disarm every clause whose owner the statement read at `[start, end)` consumes: in its own tokens (a compound
    /// statement's head), or in a block of it that falls through.
    fn disarm(self: *Parser, start: usize, end: usize) void {
        const own_end = on_fail.headEnd(self.tokens, start, end);
        for (self.cursor.pending.cleanup.clauses.items) |*clause| {
            if (clause.flags.consumed_inside) clause.flags.branch_disarmed = true;
            if (clause.flags.consumed_inside or on_fail.consumes(self.src, self.tokens, start, own_end, clause.owners)) clause.flags.armed = false;
            clause.flags.consumed_inside = false;
        }
    }
    /// The armed clauses' statements for a failure exit read at `[start, end)`, latest first, each a fresh copy of its
    /// block (the first use takes the parsed one). The exit's own consumption disarms first, so `try close(own conn)`
    /// does not close again. Empty when no clause is armed.
    fn armedClauses(self: *Parser, start: usize, end: usize) diagnostic.Error![]const ast.StatementId {
        self.disarm(start, end);
        var bodies: std.ArrayList(ast.StatementId) = .empty;
        const clauses = self.cursor.pending.cleanup.clauses.items;
        var index = clauses.len;
        while (index > 0) {
            index -= 1;
            const clause = &clauses[index];
            if (!clause.flags.armed) continue;
            clause.flags.reached = true;
            // A `detach` loop's clause adds no statement: the checker puts the collection back at the `fail` (`loop_detach.zig`).
            if (clause.flags.detach) continue;
            const tables: ast_subtree.Tables = .{ .nodes = &self.syntax.nodes, .statements = &self.syntax.statements, .growth = self.syntax.growth orelse self.storage };
            const body = if (clause.flags.original_used) try ast_subtree.cloneStatement(self.storage, tables, clause.body) else clause.body;
            clause.flags.original_used = true;
            try bodies.append(self.storage, body);
        }
        return bodies.items;
    }
    /// Rewrite `const x = try f()` (or `mut`, `try f()`, `_ = try f()`) in the reach of armed clauses into the bind-or-else
    /// it stands for, whose failure arm runs the clauses and then `fail`s the error. The error's binding is named by the
    /// `try` keyword itself, a name no source can spell.
    fn exitDeclaration(self: *Parser, head: BindHead, read: Read) diagnostic.Error!ast.StatementId {
        const clauses = try self.armedClauses(read.start, read.end);
        if (clauses.len == 0 and !on_fail.detachArmed(self.cursor.pending.cleanup.clauses.items)) return read.id;
        const propagate = self.syntax.nodes.items[@backingInt(head.value)];
        // Only a function that fails holds an `on fail:` clause, so the armed clause is a `detach` loop's, and this
        // `try` passes on a `None`, which the rewrite to `fail` cannot carry.
        if (!self.cursor.pending.cleanup.fails) return self.sink.fail(loop_detach.try_code, propagate.span, loop_detach.optional_try);
        const keyword: Span = .{ .start = propagate.span.start, .end = propagate.span.start + "try".len };
        const error_name = try self.append(.{ .span = keyword, .data = .{ .name = keyword } });
        const failed = try self.addStatement(.{ .span = keyword, .data = .{ .fail = error_name } });
        const leave = try self.addStatement(.{ .span = keyword, .data = .{ .block = try std.mem.concat(self.storage, ast.StatementId, &.{ clauses, &.{failed} }) } });
        const field = [_]ast.PatternField{.{ .pattern = .{ .span = keyword, .data = .{ .binding = keyword } } }};
        const failure: Pattern = .{
            .ty = .{ .start = keyword.start, .end = keyword.start },
            .name = keyword,
            .bindings = try self.storage.dupe(?Span, &.{keyword}),
            .binding_names = try self.storage.dupe(?Span, &.{null}),
            .payload_patterns = try self.storage.dupe(ast.PatternField, &field),
        };
        var unwrapped = head;
        unwrapped.value = propagate.data.propagate;
        return self.bindOrElseMatch(unwrapped, .{ .failure = failure, .leave = leave, .at = keyword });
    }
    /// Rewrite `fail value` in the reach of armed clauses into a block that runs the clauses and then fails.
    fn exitFail(self: *Parser, id: ast.StatementId, start: usize, end: usize) diagnostic.Error!ast.StatementId {
        const clauses = try self.armedClauses(start, end);
        if (clauses.len == 0) return id;
        const span = self.syntax.statements.items[@backingInt(id)].span;
        return self.addStatement(.{ .span = span, .data = .{ .block = try std.mem.concat(self.storage, ast.StatementId, &.{ clauses, &.{id} }) } });
    }
    fn statement(self: *Parser) diagnostic.Error!ast.StatementId {
        try self.enter();
        defer self.cursor.depth -= 1;
        const first = self.current();
        if (self.atOnFail()) return self.onFailStatement(first);
        const start = self.cursor.pos;
        self.cursor.pending.cleanup.head = start;
        const id = try self.statementForm(first);
        self.cursor.pending.cleanup.head = null;
        return self.cleanupExit(id, start);
    }
    fn statementForm(self: *Parser, first: lex.Token) diagnostic.Error!ast.StatementId {
        if (try self.redesignedStatement(first)) |result| return result;
        if (self.take(.kw_with)) return self.withStatement(first.span);
        if (self.take(.kw_match)) {
            // `match mut <place>:` (C1): `mut` is a contextual word, so `match mut:` still names a value called `mut`.
            const exclusive = self.identIsMut() and self.tokens[self.cursor.pos + 1].tag != .colon;
            if (exclusive) self.cursor.pos += 1;
            const value = try self.conditionExpression();
            _ = try self.expect(.indent);
            var arms: std.ArrayList(ast.MatchArm) = .empty;
            if (self.current().tag != .dedent) while (true) {
                try self.caseArms(&arms);
                if (self.current().tag != .kw_case) break;
            };
            const close = try self.expect(.dedent);
            return self.addStatement(.{ .span = .join(first.span, close.span), .data = .{ .match = .{ .value = value, .arms = try arms.toOwnedSlice(self.storage), .exclusive = exclusive } } });
        }
        if (self.take(.kw_if) or self.take(.kw_elif)) {
            const condition = try self.conditionExpression();
            if (self.word("then")) return self.conditionalDiscard(first, condition);
            const then_body = try self.block(null);
            const else_body = if (self.current().tag == .kw_elif)
                try self.statement()
            else if (self.take(.kw_else)) try self.block(null) else null;
            const last = else_body orelse then_body;
            if (self.bindingTest(condition)) |variant| {
                const span = Span.join(first.span, self.syntax.statements.items[@backingInt(last)].span);
                return self.bindingMatch(variant, then_body, else_body orelse try self.addStatement(.{ .span = span, .data = .{ .block = &.{} } }), span);
            }
            return self.addStatement(.{ .span = .join(first.span, self.syntax.statements.items[@backingInt(last)].span), .data = .{ .branch = .{
                .condition = condition,
                .then_body = then_body,
                .else_body = else_body,
            } } });
        }
        if (self.atAttribute("vectorize")) {
            self.cursor.pos += 2;
            return self.vectorized(try self.statement(), first.span);
        }
        if (self.take(.kw_for)) return self.forStatement(first);
        if (self.take(.kw_while)) {
            const condition = try self.conditionExpression();
            const body = try self.loopBody();
            if (self.current().tag == .kw_else) return self.alternative(expression_code, for_else_message, loop_else_accepted);
            const span = Span.join(first.span, self.syntax.statements.items[@backingInt(body)].span);
            if (self.bindingTest(condition)) |variant| {
                // `while value is PATTERN:` is `while True:` over `match value:`, whose other cases `break`.
                const stop = try self.addStatement(.{ .span = first.span, .data = .{ .loop_exit = false } });
                const matched = try self.bindingMatch(variant, body, stop, span);
                const forever = try self.append(.{ .span = first.span, .data = .{ .boolean = true } });
                return self.addStatement(.{ .span = span, .data = .{ .loop = .{ .condition = forever, .body = matched } } });
            }
            return self.addStatement(.{ .span = span, .data = .{ .loop = .{ .condition = condition, .body = body } } });
        }
        var implicit_discard = false;
        const statement_start = self.cursor.pos;
        const data: @FieldType(ast.Statement, "data") = switch (first.tag) {
            .kw_pass => no_op: {
                self.cursor.pos += 1;
                break :no_op .{ .block = &.{} };
            },
            .kw_assert => check: {
                self.cursor.pos += 1;
                break :check .{ .assertion = try self.assertion() };
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
                    const discarded = try self.expression(0);
                    if (self.current().tag == .kw_else) {
                        const bound = try self.bindOrElse(.{ .first = first, .name = null, .annotation = null, .mutable = false, .value = discarded });
                        return bound;
                    }
                    break :assignment .{ .discard = discarded };
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
        if (self.current().tag == .kw_else) try self.refuseStatementElse(first, statement_start, data, implicit_discard);
        const end = try self.statementEnd(first);
        return self.addStatement(.{ .span = .join(first.span, end.span), .implicit_discard = implicit_discard, .data = data });
    }
    /// Whether `id` is an expression a statement may be made of, not an assignment the parser also lowers to a discard.
    fn isPlainExpression(self: *Parser, id: ast.NodeId) bool {
        return switch (self.syntax.nodes.items[@backingInt(id)].data) {
            .field_assignment, .index_assignment, .list_operation => false,
            else => true,
        };
    }
    /// The `else` after a statement that is not a declaration, which has no value to unwrap: the cursor stands on it. A plain
    /// expression is `elseWithoutValue`'s, an assignment to a local `elseOnAssignment`'s, one to a field or an element
    /// `refuseElseOnPlace`'s. Returns normally for the shapes that keep the old `expected a newline`, and for an `else` that
    /// starts the next line.
    fn refuseStatementElse(self: *Parser, first: lex.Token, start: usize, data: @FieldType(ast.Statement, "data"), implicit_discard: bool) diagnostic.Error!void {
        if (implicit_discard and self.isPlainExpression(data.discard)) return self.elseWithoutValue(first);
        if (self.terminatorAhead()) return;
        if (implicit_discard) return self.refuseElseOnPlace(start, data.discard);
        if (data == .assignment) return self.elseOnAssignment(first, data.assignment);
    }
    /// F-76: `CALL else Err(e):` as a statement. `else` unwraps the value of a declaration or of `_ =`, and a statement
    /// that is only an expression has none to bind, so the refusal says what to write: `if CALL is Err(e):` tests a
    /// call that gives nothing back, the pattern after `else` carried over. The repair (`if ` in front, `is` for
    /// `else`) is attached when the pattern is `Err(name)`, `Err(_)` or `None`, which `is` accepts as written; a bare
    /// `else:` names no case, so its message gives both and no repair.
    fn elseWithoutValue(self: *Parser, first: lex.Token) diagnostic.Error {
        const else_token = self.current();
        const operand = self.src.bytes[first.span.start..self.previousEnd()];
        const short = operand.len <= 40 and std.mem.indexOfScalar(u8, operand, '\n') == null;
        const pattern = self.statementElsePattern();
        const message = try bind_or_else.statementElseMessage(self.storage, if (short) operand else "CALL", pattern);
        const fix: ?diagnostic.Fix = if (pattern == null) null else blk: {
            const edits = try self.storage.dupe(diagnostic.Edit, &.{
                .{ .span = .{ .start = first.span.start, .end = first.span.start }, .text = "if " },
                .{ .span = else_token.span, .text = "is" },
            });
            break :blk .{ .edit = edits[0], .more = edits[1..] };
        };
        return self.sink.failRepaired(syntax_code, else_token.span, message, fix);
    }
    /// SP1-F-5: `x = f() else Err(m):`. The `else` that unwraps a value binds it to a new name, so it belongs to a
    /// declaration (`const x = f() else Err(m):`); an assignment to a name that already exists takes no block. The refusal
    /// says so and writes the two forms that do the job, a new `const` assigned afterwards and a `match`; it carries no
    /// repair, since either needs the reader's choice of a name or of the arms. `assignment` is the statement just parsed,
    /// whose `else` the cursor stands on; the position stays the `else`, where the old `expected a newline` pointed.
    fn elseOnAssignment(self: *Parser, first: lex.Token, assignment: @FieldType(@FieldType(ast.Statement, "data"), "assignment")) diagnostic.Error {
        const else_token = self.current();
        const raw = std.mem.trim(u8, self.src.bytes[assignment.op_span.end..self.previousEnd()], " \t");
        const short = raw.len <= 40 and std.mem.indexOfScalar(u8, raw, '\n') == null;
        const pattern = self.statementElsePattern();
        const clause = if (pattern) |written|
            try std.fmt.allocPrint(self.storage, "else {s}:", .{written})
        else if (self.tokens[self.cursor.pos + 1].tag == .indent) "else:" else "else Err(e):";
        const message = try bind_or_else.assignmentElseMessage(self.storage, .{
            .target = self.src.text(first.span),
            .operator = self.src.text(assignment.op_span),
            .operand = if (short) raw else "VALUE",
            .clause = clause,
        });
        return self.sink.fail(syntax_code, else_token.span, message);
    }
    /// SP1B-F-3: `pax.size = f() else:` and `xs[i] = f() else:`. The `else` that unwraps a value belongs to a declaration, as
    /// in `elseOnAssignment`, but the three forms that do the job for a place are another list: the declaration and the
    /// assignment after it, `PLACE = try CALL` in a function that can fail (TRYFIELD), and `if CALL is Some(value):` with the
    /// assignment inside. Returns normally when `discarded` is no assignment to a field or an element, or its value is a
    /// `try` (whose old `expected a newline` stays); otherwise the refusal, at the `else` where the old one stood, with no
    /// repair since each form needs the reader's choice of a name.
    fn refuseElseOnPlace(self: *Parser, start: usize, discarded: ast.NodeId) diagnostic.Error!void {
        const value = switch (self.syntax.nodes.items[@backingInt(discarded)].data) {
            .field_assignment => |assigned| assigned.value,
            .index_assignment => |assigned| assigned.value,
            .list_operation => |write| if (write.kind == .write) write.arguments[1] else return,
            else => return,
        };
        if (self.syntax.nodes.items[@backingInt(value)].data == .propagate) return;
        // The operator is the first assignment operator outside brackets: a place holds none there.
        var depth: usize = 0;
        var at = start;
        while (at < self.cursor.pos) : (at += 1) switch (self.tokens[at].tag) {
            .lparen, .lbracket, .lbrace => depth += 1,
            .rparen, .rbracket, .rbrace => depth -|= 1,
            else => if (depth == 0 and assignmentOperation(self.tokens[at].tag) != null) break,
        };
        if (at + 1 >= self.cursor.pos) return;
        const else_token = self.current();
        const place = std.mem.trim(u8, self.src.bytes[self.tokens[start].span.start..self.tokens[at].span.start], " \t");
        const raw = std.mem.trim(u8, self.src.bytes[self.tokens[at].span.end..self.previousEnd()], " \t");
        const clause = if (self.statementElsePattern()) |written|
            try std.fmt.allocPrint(self.storage, "else {s}:", .{written})
        else if (self.tokens[self.cursor.pos + 1].tag == .indent) "else:" else "else Err(e):";
        const message = try bind_or_else.placeElseMessage(self.storage, .{
            .place = if (place.len <= 40 and std.mem.indexOfScalar(u8, place, '\n') == null) place else "PLACE",
            .element = self.syntax.nodes.items[@backingInt(discarded)].data != .field_assignment,
            .operator = self.src.text(self.tokens[at].span),
            .operand = if (raw.len <= 40 and std.mem.indexOfScalar(u8, raw, '\n') == null) raw else "VALUE",
            .clause = clause,
        });
        return self.sink.fail(syntax_code, else_token.span, message);
    }
    /// The failure pattern after the `else` at the cursor, as source text, when it is one a bind-or-else takes and an
    /// `is` test takes as well: `None`, `Err(name)` or `Err(_)` followed by the colon that opens the block. Null for a
    /// bare `else:` and for anything else.
    fn statementElsePattern(self: *Parser) ?[]const u8 {
        const at = self.cursor.pos + 1;
        const head = self.tokens[at];
        if (head.tag == .kw_none) return if (self.tokens[at + 1].tag == .indent) self.src.text(head.span) else null;
        if (head.tag != .ident or !std.mem.eql(u8, self.src.text(head.span), "Err")) return null;
        const bound = self.tokens[at + 2];
        if (self.tokens[at + 1].tag != .lparen or bound.tag != .ident or self.tokens[at + 3].tag != .rparen or self.tokens[at + 4].tag != .indent) return null;
        return self.src.bytes[head.span.start..self.tokens[at + 3].span.end];
    }
    /// Recognize `range(end)`, `range(start, end)` or `range(start, end, step)` as an
    /// iteration source and return its bounds, using a unit sentinel for the implicit zero
    /// start. A `for` loop and a list comprehension share this so both accept exactly the
    /// same range spellings.
    fn rangeBounds(self: *Parser, input: ast.NodeId) diagnostic.Error!?ast.RangeBounds {
        const node = self.syntax.nodes.items[@backingInt(input)];
        if (node.data != .call or node.data.call.owner != null) return null;
        const call = node.data.call;
        if (!std.mem.eql(u8, self.src.text(call.name), "range")) return null;
        if (call.arguments.len < 1 or call.arguments.len > 3) return self.sink.fail("E_ARITY", node.span, range_arity);
        // Unit is an internal zero sentinel, avoiding fabricated source text.
        return .{
            .start = if (call.arguments.len >= 2) call.arguments[0] else try self.append(.{ .span = call.name, .data = .unit }),
            .end = if (call.arguments.len >= 2) call.arguments[1] else call.arguments[0],
            .step = if (call.arguments.len == 3) call.arguments[2] else null,
        };
    }
    /// The names and source of one `for` loop or comprehension clause, and the
    /// iteration its source spells: a `range(...)`, an `enumerate(...)` whose
    /// iterable is its one argument, or any other expression.
    const LoopHeader = struct {
        first: Span,
        second: ?Span,
        input: ast.NodeId,
        range: ?ast.RangeBounds = null,
        iterable: ast.NodeId,
        enumerated: bool = false,
        /// The `detach` word of `for x in detach place:` (`loop_detach.zig`).
        detached: ?Span = null,
    };
    /// Parse `names in source` after a `for` and classify the source. A
    /// comprehension parses its source above the conditional expression, so the
    /// `if` after it starts a filter; a statement parses a whole expression.
    fn loopHeader(self: *Parser, comprehension: bool) diagnostic.Error!LoopHeader {
        const first_name = (try self.expect(.ident)).span;
        const second_name = if (self.take(.comma)) (try self.expect(.ident)).span else null;
        _ = try self.expect(.kw_in);
        const detached = if (comprehension) null else self.detachWord();
        const input = if (comprehension) try self.expression(1) else try self.conditionExpression();
        var header: LoopHeader = .{ .first = first_name, .second = second_name, .input = input, .iterable = input, .detached = detached };
        // The checker refuses a detached source that is not a place, `range(...)` and `enumerate(...)` among them.
        if (detached != null) return header;
        if (try self.rangeBounds(input)) |bounds| {
            header.range = bounds;
            return header;
        }
        const node = self.syntax.nodes.items[@backingInt(input)];
        if (node.data == .call and node.data.call.owner == null and std.mem.eql(u8, self.src.text(node.data.call.name), "enumerate")) {
            const call = node.data.call;
            if (call.arguments.len != 1 or second_name == null) return self.sink.fail("E_ARITY", node.span, "enumerate requires one iterable and two iteration names");
            header.iterable = call.arguments[0];
            header.enumerated = true;
        } else if (node.data == .call and node.data.call.owner == null and std.mem.eql(u8, self.src.text(node.data.call.name), "zip")) {
            const call = node.data.call;
            if (call.arguments.len != 2 or second_name == null) return self.sink.fail("E_ARITY", node.span, "zip requires two iterables and two iteration names");
        }
        return header;
    }
    /// The `for` statement one header runs `body` under: a counted range loop or
    /// a walk over a collection, `enumerate`, `zip` or a dictionary view.
    fn loopStatement(self: *Parser, header: LoopHeader, body: ast.StatementId, span: Span) diagnostic.Error!ast.StatementId {
        if (header.range) |bounds| {
            if (header.second != null) return self.sink.fail(eIteration, span, "range requires one iteration name");
            return self.addStatement(.{ .span = span, .data = .{ .for_range = .{ .name = header.first, .start = bounds.start, .end = bounds.end, .body = body, .step = bounds.step } } });
        }
        return self.addStatement(.{
            .span = span,
            .data = .{ .for_each = .{
                .name = header.second orelse header.first,
                .index_name = if (header.second != null) header.first else null,
                .iterable = header.iterable,
                .body = body,
                .enumerated = header.enumerated,
                .detached = header.detached,
            } },
        });
    }
    fn forStatement(self: *Parser, first: lex.Token) diagnostic.Error!ast.StatementId {
        const header = try self.loopHeader(false);
        const body = if (header.detached) |at| try self.detachedBody(at) else try self.loopBody();
        if (self.current().tag == .kw_else) return self.alternative(expression_code, for_else_message, loop_else_accepted);
        const span: Span = .join(first.span, self.syntax.statements.items[@backingInt(body)].span);
        return self.loopStatement(header, body, span);
    }
    /// The `detach` word after a statement loop's `in`, when a place follows it (`for x in detach ev.items:`); a value
    /// named `detach` (`for x in detach:`, `detach.items`, `detach(xs)`) is not one.
    fn detachWord(self: *Parser) ?Span {
        const at = self.current();
        if (at.tag != .ident or self.tokens[self.cursor.pos + 1].tag != .ident) return null;
        if (!std.mem.eql(u8, self.src.text(at.span), loop_detach.word)) return null;
        self.cursor.pos += 1;
        return at.span;
    }
    /// The body of a `detach` loop. A clause of the `on fail:` kind is armed over it, so each `try` in it is rewritten into
    /// the `match` whose failure arm runs the armed `on fail:` clauses and then `fail`s; the checker puts the collection
    /// back at that `fail` as at any other (`loop_detach.zig`). The clause's own block is empty and never placed.
    fn detachedBody(self: *Parser, at: Span) diagnostic.Error!ast.StatementId {
        const cleanup = &self.cursor.pending.cleanup;
        // An `on fail:` clause neither fails nor returns, so a loop inside one has no exit to cover.
        if (cleanup.inside.clause) return self.loopBody();
        const mark = cleanup.clauses.items.len;
        const marker = try self.addStatement(.{ .span = at, .data = .{ .block = &.{} } });
        try cleanup.clauses.append(self.storage, .{ .body = marker, .span = at, .owners = &.{}, .flags = .{ .reached = true, .detach = true } });
        defer cleanup.clauses.shrinkRetainingCapacity(mark);
        return self.loopBody();
    }
    /// Explicit local declarations destructure one tuple into named bindings.
    fn destructuringDeclaration(self: *Parser, first: lex.Token, name: Span) diagnostic.Error!ast.StatementId {
        const head = try self.append(.{ .span = name, .data = .{ .name = name } });
        const targets = try self.destructuringTargets(head);
        for (self.syntax.nodes.items[@backingInt(targets)].data.tuple) |target| {
            const node = self.syntax.nodes.items[@backingInt(target)];
            if (node.data != .name) return self.sink.fail("E_BINDING_TARGET", node.span, "a destructuring declaration binds names; use a separate assignment for fields or elements");
        }
        _ = try self.expect(.equal);
        const value = try self.bareTuple(try self.expression(0));
        const end = try self.statementEnd(first);
        const span: Span = .join(first.span, end.span);
        const assignment = try self.append(.{ .span = span, .data = .{ .field_assignment = .{
            .target = targets,
            .value = value,
            .declaration = first.tag != .kw_const,
        } } });
        return self.addStatement(.{ .span = span, .data = .{ .discard = assignment } });
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
        if (!self.take(.equal)) return self.sink.fail(syntax_code, target_span, "a bare comma list is not an expression; tuples were removed, so write one statement per value or use a record with named fields");
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
        // The value of an assignment to a field or an element is a statement's value, so it may be `try CALL` (TRYFIELD,
        // `docs/results-and-options.md#postfix-error-propagation`): lowered in place, a failure leaves before the write.
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
    fn expressionHead(self: *Parser, token: lex.Token) diagnostic.Error!?ast.NodeId {
        if (token.tag != .ident) return null;
        if (self.atOwnArgument()) {
            self.cursor.pos += 1;
            if (self.atOwnArgument() or self.atMutArgument()) return self.sink.fail("E_PARAMETER_MODIFIER", token.span, "a value has one `own` marker; `own` and `mut` do not combine");
            const value = try self.expression(0);
            if (self.syntax.nodes.items[@backingInt(value)].data == .own_argument) return self.sink.fail("E_PARAMETER_MODIFIER", token.span, "a value has one `own` marker; `own` and `mut` do not combine");
            const marked = try self.append(.{ .span = .join(token.span, self.syntax.nodes.items[@backingInt(value)].span), .data = .{ .own_argument = value } });
            return marked;
        }
        if (std.mem.eql(u8, self.src.text(token.span), "lambda")) {
            const value = try self.lambdaExpression(token);
            return value;
        }
        return null;
    }
    fn expression(self: *Parser, min_precedence: u8) diagnostic.Error!ast.NodeId {
        try self.enter();
        defer self.cursor.depth -= 1;
        const token = self.current();
        if (token.tag == .ident and std.mem.eql(u8, self.src.text(token.span), "try")) return self.tryOperand(min_precedence);
        if (try self.expressionHead(token)) |value| return value;
        // `len` is a prelude builtin name, not a reserved word (batch 0): as a call
        // it builds the length node unless this file declares its own `len`, and as
        // a bare name it is an ordinary reference. It is a primary, not a whole
        // expression, so the operator loop still runs after it.
        const length_call = token.tag == .ident and std.mem.eql(u8, self.src.text(token.span), "len") and
            self.cursor.pos + 1 < self.tokens.len and self.tokens[self.cursor.pos + 1].tag == .lparen and
            !self.declaresFunction(token.span);
        // `unwrap(value)` is the retired scalar-domain form, recognized by its
        // spelling now that the word is not reserved: the domain migration still
        // rewrites it, and a file that declares its own `unwrap` keeps it.
        const unwrap_call = token.tag == .ident and std.mem.eql(u8, self.src.text(token.span), "unwrap") and
            self.cursor.pos + 1 < self.tokens.len and self.tokens[self.cursor.pos + 1].tag == .lparen and
            !self.declaresFunction(token.span);
        // `replace(...)` is the positional list intrinsic or, with a named field
        // (`replace(record, field=value)`), the functional record update. Both are
        // recognized by the spelling now that the word is not reserved; a file that
        // declares its own `replace` keeps it.
        const replace_call = token.tag == .ident and std.mem.eql(u8, self.src.text(token.span), "replace") and
            self.cursor.pos + 1 < self.tokens.len and self.tokens[self.cursor.pos + 1].tag == .lparen and
            !self.declaresFunction(token.span) and !self.recordUpdateAhead();
        const left: ast.NodeId = if (length_call or unwrap_call or replace_call) try self.parseBuiltin(token) else switch (token.tag) {
            .kw_if => try self.forwardConditional(token),
            .kw_match => try self.matchExpression(token),
            .kw_restrict_resource => try self.parseRestrict(token),
            .kw_read_resource, .kw_write_resource => try self.parseResourceIo(token),
            .kw_environment_get => try self.parseEnvironmentGated(token),
            .kw_acquire_resource, .kw_accept_resource, .kw_complete_resource => try self.parseResource(token),
            .kw_clock_now, .kw_random_u64 => try self.parseExternalGated(token),
            .kw_stand_in, .kw_clock_advance, .kw_clock_monotonic, .kw_clock_sleep, .kw_stand_fail, .kw_stream_memory, .kw_stream_text => try self.parseStandIn(token),
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
            .kw_bit_not => try self.parseBitNot(token),
            .kw_f64_sqrt => if (self.trustedStdlib())
                try self.parseFloatUnary(token)
            else
                return self.sink.fail(eInternalName, token.span, "`__float_sqrt` is reserved for compiler-internal standard-library sources; use the public `sqrt` operation"),
            .kw_f64_sin, .kw_f64_cos => if (self.trustedStdlib())
                try self.parseFloatUnary(token)
            else
                return self.sink.fail(eInternalName, token.span, "this binary64 intrinsic is reserved for compiler-internal standard-library sources; use `math.sin` or `math.cos`"),
            .kw_f64_bits, .kw_f64_from_bits, .kw_f32_bits, .kw_f32_from_bits => if (self.trustedStdlib())
                try self.parseFloatUnary(token)
            else
                return self.sink.fail(eInternalName, token.span, "this bit-pattern intrinsic is reserved for compiler-internal standard-library sources; use `math.bits` or `math.from_bits`"),
            .kw_f64_floor, .kw_f64_ceil, .kw_f64_trunc, .kw_f64_abs, .kw_f64_neg, .kw_f64_from_u64, .kw_f64_to_u64 => try self.parseFloatUnary(token),
            .kw_wrap => try self.parseWrap(token),
            .kw_i8, .kw_i16, .kw_i32, .kw_i64, .kw_u8, .kw_u16, .kw_u32, .kw_u64 => try self.parseWidthConversion(token),
            .lbracket => try self.listLiteral(token),
            .kw_todo => try self.parseHole(token),
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
                _ = try removed_names.rejectMarker(self.sink, self.src.bytes, token.span);
                return self.pythonExpressionFailure(token);
            },
            // A `func` or `match` in expression position, and the second `*` or
            // `<` of a `**` or `<<`, name their accepted spelling; every other
            // token keeps the plain rejection.
            else => return self.pythonExpressionFailure(token),
        };
        return self.operatorTail(left, min_precedence);
    }
    /// `try` and the operand it binds to: the call (or name, field or element) after it with its `.`, `[]` and call
    /// suffixes, the operand a statement's `try` has always taken (TRY-2, `docs/results-and-options.md#try-in-an-operand`).
    /// The operators after it apply to the unwrapped value, so `try f() + 1` is `(try f()) + 1`. Lowering evaluates
    /// operands left to right and `and`/`or` only on the side that runs, so the call runs where it is written and a
    /// failure leaves before anything to its right. Before `a if p else b` at the loosest level the `try` covers the
    /// conditional, as a statement's `try` did before operands took one.
    fn tryOperand(self: *Parser, min_precedence: u8) diagnostic.Error!ast.NodeId {
        const at = self.cursor.pos;
        const keyword = self.current().span;
        if (self.cursor.compile_time) |message| return self.sink.fail("E_TRY_POSITION", keyword, message);
        self.cursor.pos += 1;
        // Above every binary operator: only a primary and its suffixes.
        const operand = try self.expression(10);
        switch (self.syntax.nodes.items[@backingInt(operand)].data) {
            .binary, .unary, .membership => return self.refuseTryPosition(at),
            else => {},
        }
        const conditional = min_precedence == 0 and self.current().tag == .kw_if and !self.implicitBoundary();
        const covered = if (conditional) try self.conditionalExpression(operand) else operand;
        const left = try self.append(.{ .span = .join(keyword, self.syntax.nodes.items[@backingInt(covered)].span), .data = .{ .propagate = covered } });
        try self.cursor.pending.cleanup.noteTry(self.storage, keyword);
        if (conditional) return left;
        return self.operatorTail(left, min_precedence);
    }
    /// The suffixes and binary operators after an expression's first operand `first`, binding at `min_precedence` or
    /// tighter, and at the loosest level a trailing `a if p else b`.
    fn operatorTail(self: *Parser, first: ast.NodeId, min_precedence: u8) diagnostic.Error!ast.NodeId {
        var left = first;
        // PY-CHAIN-1: whether `left` is a comparison this loop built, so a
        // following comparison continues a Python chain instead of comparing a bool.
        var chain = false;
        while (true) {
            if (self.implicitBoundary()) break;
            if (!self.continuesChain(chain)) chain = false;
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
                    const close = try self.closeValues(.rbracket);
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
            const comparison = comparisonOperator(op.tag);
            left = try self.append(.{ .span = .join(self.syntax.nodes.items[@backingInt(left)].span, self.syntax.nodes.items[@backingInt(right)].span), .data = .{ .binary = .{
                .op = binaryOperator(op.tag),
                .left = left,
                .right = right,
                .op_span = op.span,
                .chained = chain and comparison,
            } } });
            chain = comparison;
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
    fn listLiteral(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        _ = self.take(.lbracket);
        if (self.current().tag == .kw_for) return self.sourceComprehension(token);
        var values: std.ArrayList(ast.NodeId) = .empty;
        if (self.current().tag != .rbracket) while (true) {
            try values.append(self.storage, try self.expression(0));
            if (values.items.len == 1 and self.current().tag == .kw_for) return self.parseComprehension(token, values.items[0]);
            if (!self.take(.comma) or self.current().tag == .rbracket) break;
        };
        const close = try self.closeValues(.rbracket);
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .list_literal = try values.toOwnedSlice(self.storage) } });
    }
    /// The condition and optional message of an `assert`, after the keyword. A quoted message that stands alone keeps its
    /// decoded literal, which the native trap carries directly; any other expression, a quoted text with an operator
    /// after it included, is rendered to standard error on the failure path only (F-72). A comma after the message is
    /// refused with what an `assert` takes.
    fn assertion(self: *Parser) diagnostic.Error!ast.Assertion {
        const condition = try self.expression(0);
        const condition_text = self.src.text(self.syntax.nodes.items[@backingInt(condition)].span);
        if (!self.take(.comma)) return .{ .condition = condition, .message = condition_text };
        if (self.current().tag == .bytes and self.terminatorAt(self.cursor.pos + 1)) {
            const literal = self.current().span;
            self.cursor.pos += 1;
            return .{ .condition = condition, .message = try byte_literal.decode(self.storage, self.src, literal, self.sink), .literal = literal };
        }
        const value = try self.expression(0);
        if (self.current().tag == .comma) return self.sink.fail(syntax_code, self.current().span, assert_second_comma_message);
        return .{ .condition = condition, .message = "", .value = value };
    }
    fn forwardConditional(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        const condition = try self.expression(0);
        // `if c: a else: b` on one line (F-50) is read as the conditional value it means, so the refusal that follows names
        // the statement form and carries its repair; any other spelling names the statement form here.
        if (self.current().tag == .colon) {
            const colon = self.cursor.pos;
            self.cursor.pos += 1;
            const then_value = try self.expression(0);
            if (self.current().tag == .kw_else and self.tokens[self.cursor.pos + 1].tag == .colon) {
                self.cursor.pos += 2;
                const else_value = try self.expression(0);
                return self.append(.{ .span = .join(token.span, self.syntax.nodes.items[@backingInt(else_value)].span), .data = .{ .conditional = .{ .condition = condition, .then_value = then_value, .else_value = else_value } } });
            }
            self.cursor.pos = colon;
        }
        if (!self.word("then")) return self.sink.fail("E_CONDITIONAL", self.current().span, conditional_message);
        return self.conditionalValues(token.span, condition);
    }
    fn conditionalValues(self: *Parser, first: Span, condition: ast.NodeId) diagnostic.Error!ast.NodeId {
        const then_value = try self.expression(0);
        _ = try self.expect(.kw_else);
        const else_value = try self.expression(0);
        return self.append(.{ .span = .join(first, self.syntax.nodes.items[@backingInt(else_value)].span), .data = .{ .conditional = .{ .condition = condition, .then_value = then_value, .else_value = else_value } } });
    }
    /// A conditional value used as a statement follows ordinary discard rules.
    fn conditionalDiscard(self: *Parser, first: lex.Token, condition: ast.NodeId) diagnostic.Error!ast.StatementId {
        const value = try self.conditionalValues(first.span, condition);
        const end = try self.statementEnd(first);
        return self.addStatement(.{ .span = .join(first.span, end.span), .implicit_discard = true, .data = .{ .discard = value } });
    }
    fn sourceComprehension(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        _ = try self.expect(.kw_for);
        const name = try self.expect(.ident);
        _ = try self.expect(.kw_in);
        const input = try self.expression(1);
        const filter = if (self.take(.kw_if)) try self.expression(1) else null;
        if (!self.word("yield")) return self.sink.fail("E_COMPREHENSION", self.current().span, comprehension_message);
        const output = try self.expression(0);
        const close = try self.expect(.rbracket);
        const header: LoopHeader = .{ .first = name.span, .second = null, .input = input, .iterable = input, .range = try self.rangeBounds(input) };
        const filters: []const ast.NodeId = if (filter) |value| &.{value} else &.{};
        const clause: Clause = .{
            .header = header,
            .filters = filters,
            .span = .join(name.span, self.syntax.nodes.items[@backingInt(input)].span),
        };
        return self.gather(.{ .shape = .list, .open = token.span, .span = .join(token.span, close.span) }, &.{clause}, .{ .value = output });
    }
    fn matchExpression(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        const value = try self.expression(0);
        _ = try self.expect(.indent);
        var arms: std.ArrayList(ast.MatchArm) = .empty;
        while (self.current().tag != .dedent) {
            _ = try self.expect(.kw_case);
            const pattern = try self.matchPattern();
            const body = try self.block(null);
            try arms.append(self.storage, .{ .ty = pattern.ty, .name = pattern.name, .bindings = pattern.bindings, .binding_names = pattern.binding_names, .payload_patterns = pattern.payload_patterns, .body = body });
        }
        const close = try self.expect(.dedent);
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .match_expression = .{ .value = value, .arms = try arms.toOwnedSlice(self.storage) } } });
    }
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
        if (self.current().tag == .kw_for) {
            const generator = try self.generatorExpression(inner);
            const end = try self.expect(.rparen);
            self.syntax.nodes.items[@backingInt(generator)].span = .join(token.span, end.span);
            return generator;
        }
        const close = try self.closeValues(.rparen);
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
        if (elements.items.len < 2) return self.sink.fail(syntax_code, comma_span orelse self.syntax.nodes.items[@backingInt(first)].span, "a one-element tuple is not a value; write the element alone");
        const close = try self.closeValues(.rparen);
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
        if (elements.items.len < 2) return self.sink.fail(syntax_code, comma_span orelse self.syntax.nodes.items[@backingInt(first)].span, "a one-element tuple is not a value; write the element alone");
        const last = self.syntax.nodes.items[@backingInt(elements.items[elements.items.len - 1])].span;
        return self.append(.{ .span = .join(self.syntax.nodes.items[@backingInt(first)].span, last), .data = .{ .tuple = try elements.toOwnedSlice(allocator) } });
    }
    fn lambdaExpression(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        var parameters: std.ArrayList(Span) = .empty;
        if (self.current().tag != .colon) while (true) {
            const parameter = try self.expect(.ident);
            if (std.mem.eql(u8, self.src.text(parameter.span), "_"))
                return self.sink.fail("E_LAMBDA_PARAMETER", parameter.span, "lambdas were removed; declare a named top-level function with explicit parameter and result types");
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
        if (self.current().tag == .ident and std.mem.eql(u8, self.src.text(self.current().span), "unwrap")) return self.hintHere(.option_unwrap);
        const name: lex.Token = .{ .tag = .ident, .span = try self.declaredName() };
        if (self.take(.lparen)) {
            const arguments = try self.callArguments();
            const close = try self.callClose();
            return self.append(.{
                .span = .join(self.syntax.nodes.items[@backingInt(left)].span, close.span),
                .data = .{ .method_call = .{ .base = left, .name = name.span, .arguments = arguments.values, .argument_names = arguments.names } },
            });
        } else return self.append(.{ .span = .join(self.syntax.nodes.items[@backingInt(left)].span, name.span), .data = .{ .field = .{ .base = left, .name = name.span } } });
    }
    /// A comparison chain continues only while the next token is another
    /// comparison; any postfix form or other operator in between ends it.
    fn continuesChain(self: *Parser, chain: bool) bool {
        return chain and comparisonOperator(self.current().tag);
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
            const next = self.tokens[self.cursor.pos + 1].tag;
            const none_ahead = next == .kw_none or (next == .bang and self.tokens[self.cursor.pos + 2].tag == .kw_none);
            return if (none_ahead) try self.parseNoneTest(left) else try self.parseVariantTest(left);
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
    /// Parse `value is PATTERN | PATTERN ...`, the test of which case a value holds. A bare case name stands for the case
    /// with any payload. The parser builds the `match` that checks it (`ast.Node.variant_test`): one arm per listed case with
    /// an empty body, then a synthetic wildcard arm. A pattern that binds names is only meaningful as the whole condition of
    /// an `if`, `elif` or `while`, where `bindingBranch` and `bindingLoop` replace the empty bodies with the real ones.
    fn parseVariantTest(self: *Parser, left: ast.NodeId) diagnostic.Error!ast.NodeId {
        const operator = try self.expect(.kw_is);
        var patterns: std.ArrayList(Pattern) = .empty;
        var binds = false;
        while (true) {
            const pattern = try self.matchPattern();
            for (pattern.payload_patterns) |field| switch (field.pattern.data) {
                .variant => return self.sink.fail(syntax_code, field.pattern.span, "an `is` test names a case and its own fields: match a nested pattern with `match`"),
                .binding => |binding| binds = binds or binding != null,
            };
            try patterns.append(self.storage, pattern);
            if (!self.take(.pipe)) break;
        }
        const last = self.tokens[self.cursor.pos - 1].span;
        const span = Span.join(self.syntax.nodes.items[@backingInt(left)].span, last);
        const empty = try self.addStatement(.{ .span = last, .data = .{ .block = &.{} } });
        var arms: std.ArrayList(ast.MatchArm) = .empty;
        for (patterns.items) |pattern| {
            const bare = pattern.payload_patterns.len == 0 and pattern.bindings.len == 0 and !pattern.rest;
            try arms.append(self.storage, .{
                .ty = pattern.ty,
                .name = pattern.name,
                .bindings = pattern.bindings,
                .binding_names = pattern.binding_names,
                .payload_patterns = pattern.payload_patterns,
                .body = empty,
                .alternatives = .{ .rest = pattern.rest or bare, .bare = bare, .group = if (patterns.items.len > 1) empty else null },
            });
        }
        try arms.append(self.storage, .{ .ty = .{ .start = operator.span.start, .end = operator.span.start }, .name = operator.span, .body = empty, .internal = .{ .wildcard = true } });
        const check = try self.addStatement(.{ .span = span, .data = .{ .match = .{ .value = left, .arms = try arms.toOwnedSlice(self.storage) } } });
        return self.append(.{ .span = span, .data = .{ .variant_test = .{ .value = left, .check = check, .explicit = @intCast(patterns.items.len), .binds = binds } } });
    }
    /// The test an `if`, `elif` or `while` condition is, when the whole condition is `value is PATTERN` and the pattern binds names.
    fn bindingTest(self: *Parser, condition: ast.NodeId) ?@FieldType(@FieldType(ast.Node, "data"), "variant_test") {
        const node = self.syntax.nodes.items[@backingInt(condition)];
        if (node.data != .variant_test or !node.data.variant_test.binds) return null;
        return node.data.variant_test;
    }
    /// The `match` a binding test stands for: each listed case runs `body` (a copy for every case after the first, since
    /// the checker memoizes a body's expressions) and any other case runs `otherwise`.
    fn bindingMatch(self: *Parser, variant: @FieldType(@FieldType(ast.Node, "data"), "variant_test"), body: ast.StatementId, otherwise: ast.StatementId, span: Span) diagnostic.Error!ast.StatementId {
        const check = self.syntax.statements.items[@backingInt(variant.check)].data.match;
        const arms = try self.storage.dupe(ast.MatchArm, check.arms);
        for (arms, 0..) |*arm, position| {
            if (position >= variant.explicit) {
                arm.body = otherwise;
                continue;
            }
            arm.body = if (position == 0) body else try ast_subtree.cloneStatement(self.storage, .{ .nodes = &self.syntax.nodes, .statements = &self.syntax.statements, .growth = self.syntax.growth orelse self.storage }, body);
            if (arm.alternatives.group != null) arm.alternatives.group = body;
        }
        return self.addStatement(.{ .span = span, .data = .{ .match = .{ .value = variant.value, .arms = arms } } });
    }
    /// One `for` clause of a comprehension or generator expression and the `if`
    /// filters that follow it, in source order.
    const Clause = struct { header: LoopHeader, filters: []const ast.NodeId, span: Span };
    /// Parse every `for names in source if condition ...` clause at the cursor.
    /// Each source and filter is parsed above the conditional expression, as
    /// Python's grammar parses them: the `if` after a source starts a filter, so
    /// `[x for x in xs if p]` never reads as a conditional.
    fn comprehensionClauses(self: *Parser) diagnostic.Error![]const Clause {
        var clauses: std.ArrayList(Clause) = .empty;
        while (self.current().tag == .kw_for) {
            const start = self.current().span;
            self.cursor.pos += 1;
            const header = try self.loopHeader(true);
            var filters: std.ArrayList(ast.NodeId) = .empty;
            while (self.take(.kw_if)) try filters.append(self.storage, try self.expression(1));
            const end = self.tokens[self.cursor.pos - 1].span;
            try clauses.append(self.storage, .{ .header = header, .filters = try filters.toOwnedSlice(self.storage), .span = .join(start, end) });
        }
        return clauses.toOwnedSlice(self.storage);
    }
    /// Parse the clauses of `[value for ...]` after its value. One unfiltered
    /// clause with one name keeps the dedicated form that reserves the source's
    /// length; a filter, two names or a second clause lower through ordinary
    /// loops instead (`PY-GATHER-1`), so a filter narrows the value it guards.
    fn parseComprehension(self: *Parser, token: lex.Token, output: ast.NodeId) diagnostic.Error!ast.NodeId {
        const clauses = try self.comprehensionClauses();
        const close = try self.expect(.rbracket);
        const span: Span = .join(token.span, close.span);
        return self.gather(.{ .shape = .list, .open = token.span, .span = span }, clauses, .{ .value = output });
    }
    /// The result a gather builds and the source it covers.
    const GatherSite = struct { shape: ast.GatherShape, open: Span, span: Span };
    /// PY-GATHER-1: build a comprehension or generator expression as its loops.
    /// The innermost statement hands `step` to the result; each clause's filters
    /// wrap it as branches, last filter innermost, and each clause's `for`
    /// statement wraps those, so the clauses nest exactly as Python reads them.
    fn gather(self: *Parser, site: GatherSite, clauses: []const Clause, step: ast.GatherStep) diagnostic.Error!ast.NodeId {
        const value_span = self.syntax.nodes.items[@backingInt(step.value)].span;
        const step_span = if (step.key) |key| Span.join(self.syntax.nodes.items[@backingInt(key)].span, value_span) else value_span;
        var body = try self.addStatement(.{ .span = step_span, .data = .{ .gather_step = step } });
        var index = clauses.len;
        while (index > 0) {
            index -= 1;
            const clause = clauses[index];
            var filter = clause.filters.len;
            while (filter > 0) {
                filter -= 1;
                const condition = clause.filters[filter];
                const branch_span = self.syntax.nodes.items[@backingInt(condition)].span;
                body = try self.addStatement(.{ .span = branch_span, .data = .{ .branch = .{ .condition = condition, .then_body = body, .else_body = null } } });
            }
            body = try self.loopStatement(clause.header, body, clause.span);
        }
        return self.append(.{ .span = site.span, .data = .{ .gather = .{ .shape = site.shape, .loop = body, .open = site.open } } });
    }
    /// PY-GENERATOR-1: `value for ...` after a first call argument or inside
    /// parentheses is a generator expression. Its node spans the value and the
    /// clauses; the consuming call decides what it builds.
    fn generatorExpression(self: *Parser, value: ast.NodeId) diagnostic.Error!ast.NodeId {
        const clauses = try self.comprehensionClauses();
        const value_span = self.syntax.nodes.items[@backingInt(value)].span;
        const span: Span = .join(value_span, clauses[clauses.len - 1].span);
        return self.gather(.{ .shape = .generator, .open = value_span, .span = span }, clauses, .{ .value = value });
    }

    /// Build `f"a{x}b"` as its alternating literal and interpolated pieces.
    /// Each hole is tokenized from the original bytes, so its spans stay absolute.
    fn parseFormat(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        const allocator = self.storage;
        const pieces = try format_strings.split(allocator, self.src, token.span, self.sink);
        var parts: std.ArrayList(ast.NodeId) = .empty;
        for (pieces, 0..) |piece, index| switch (piece) {
            .literal => |span| try parts.append(allocator, try self.formatLiteral(span)),
            .brace => |span| try parts.append(allocator, try self.append(.{ .span = span, .data = .{ .text = self.src.bytes[span.start .. span.start + 1] } })),
            .hole => |span| {
                const value = try self.formatHole(span);
                const spec: ?Span = if (index + 1 < pieces.len and pieces[index + 1] == .spec) pieces[index + 1].spec else null;
                // An empty specification is `format(value, "")`, the value's own text.
                if (spec == null or spec.?.end == spec.?.start) {
                    try parts.append(allocator, value);
                    continue;
                }
                const field_span: Span = .{ .start = span.start, .end = spec.?.end };
                try parts.append(allocator, try self.append(.{ .span = field_span, .data = .{ .format_field = .{ .value = value, .spec = spec.? } } }));
            },
            .spec => {},
        };
        return self.append(.{ .span = token.span, .data = .{ .format = try parts.toOwnedSlice(allocator) } });
    }

    /// Decode one literal chunk with the ordinary escapes by lending it surrounding quotes.
    fn formatLiteral(self: *Parser, span: Span) diagnostic.Error!ast.NodeId {
        const quoted: Span = .{ .start = span.start - 1, .end = span.end + 1 };
        const decoded = try byte_literal.decodePiece(self.storage, self.src, quoted, self.sink);
        return self.append(.{ .span = span, .data = .{ .text = decoded } });
    }

    /// Parse one interpolation as an ordinary expression over its own token range. A hole whose text is not an expression
    /// may be text that was meant to hold a literal brace (CSS, JSON), so its refusal says how that is written (FR21).
    fn formatHole(self: *Parser, span: Span) diagnostic.Error!ast.NodeId {
        const before = self.sink.items.items.len;
        return self.formatHoleExpression(span) catch |err| {
            if (err != error.SourceError or self.sink.items.items.len != before + 1) return err;
            const failure = &self.sink.items.items[before];
            // A `!` is the conversion of another language's format strings (`{text!r}`), which this one writes as a call.
            if (std.mem.eql(u8, failure.code, "E_TOKEN") and self.src.bytes[failure.span.start] == '!') {
                failure.message = try format_strings.conversionAdvice(self.sink.allocator, self.src.bytes[span.start..failure.span.start]);
                const fix = try self.conversionFix(span, before);
                self.sink.items.items[before].provenance.fix = fix;
                return err;
            }
            // A `\"` is the escaped quote of text, which a hole does not hold: its quotes are the other kind, or the value is a local.
            if (std.mem.eql(u8, failure.code, "E_TOKEN")) if (format_strings.escapedQuote(self.src.bytes, failure.span.start, span.end)) |quote| {
                failure.message = try format_strings.escapedQuoteAdvice(self.sink.allocator, quote);
                return err;
            };
            // A hole's own grammar errors only: a removed form or a lexical error in it is about that form, not about braces.
            const grammar = std.mem.eql(u8, failure.code, syntax_code) or std.mem.eql(u8, failure.code, "E_EXPRESSION");
            if (!grammar and !std.mem.eql(u8, failure.code, format_strings.code)) return err;
            const advice = try format_strings.literalBraceAdvice(self.sink.allocator, self.src.bytes, span.start - 1, span.end);
            failure.message = try std.fmt.allocPrint(self.sink.allocator, "{s}. {s}", .{ failure.message, advice });
            return err;
        };
    }

    /// The repair of a `!r` or `!s` conversion in the hole at `span`, whose failure is the diagnostic at `index`: the call that
    /// stands for it, when the text before the `!` is one expression of its own (it is parsed alone, and what that parse reports
    /// is dropped). Null where the repair is not certain.
    fn conversionFix(self: *Parser, span: Span, index: usize) diagnostic.Error!?diagnostic.Fix {
        const bang = self.sink.items.items[index].span.start;
        const edits = format_strings.conversionEdits(self.src.bytes, span, bang) orelse return null;
        const parsed: bool = if (self.formatHoleExpression(.{ .start = span.start, .end = bang })) |_| true else |err| switch (err) {
            error.SourceError => false,
            else => return err,
        };
        self.sink.items.shrinkRetainingCapacity(index + 1);
        if (!parsed) return null;
        const owned = try self.storage.dupe(diagnostic.Edit, &edits);
        return .{ .edit = owned[0], .more = owned[1..] };
    }

    fn formatHoleExpression(self: *Parser, span: Span) diagnostic.Error!ast.NodeId {
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

    /// `{}` and `{k: v, ...}` build a dictionary; `{a, b}` a set (SET-1);
    /// `{k: v for ...}` a dict comprehension and `{x for ...}` a set
    /// comprehension (`PY-GATHER-1`). The first entry decides which.
    fn parseDictionary(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.delimiters += 1;
        defer self.cursor.delimiters -= 1;

        self.cursor.pos += 1;
        var entries: std.ArrayList(ast.NodeId) = .empty;
        while (self.current().tag != .rbrace) {
            const key = try self.expression(0);
            if (entries.items.len == 0) {
                if (self.current().tag == .kw_for) return self.braceComprehension(token, .set, .{ .value = key });
                if (self.current().tag == .comma or self.current().tag == .rbrace) return self.setLiteral(token, key);
            }
            try entries.append(self.storage, key);
            _ = try self.expect(.colon);
            const value = try self.expression(0);
            if (entries.items.len == 1 and self.current().tag == .kw_for) return self.braceComprehension(token, .dict, .{ .key = key, .value = value });
            try entries.append(self.storage, value);
            if (!self.take(.comma)) break;
        }
        const close = try self.closeValues(.rbrace);
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .dictionary_literal = try entries.toOwnedSlice(self.storage) } });
    }
    /// The clauses and closing brace of a set or dict comprehension. A set
    /// comprehension with one unfiltered clause over one name keeps the
    /// dedicated comprehension form (SET-1), as a list comprehension does; every
    /// other shape lowers through ordinary loops (`PY-GATHER-1`).
    fn braceComprehension(self: *Parser, token: lex.Token, shape: ast.GatherShape, step: ast.GatherStep) diagnostic.Error!ast.NodeId {
        const clauses = try self.comprehensionClauses();
        const close = try self.expect(.rbrace);
        const span: Span = .join(token.span, close.span);
        return self.gather(.{ .shape = shape, .open = token.span, .span = span }, clauses, step);
    }
    /// SET-1: the elements of `{a, b, ...}` after its first, with an optional
    /// trailing comma.
    fn setLiteral(self: *Parser, token: lex.Token, first: ast.NodeId) diagnostic.Error!ast.NodeId {
        var elements: std.ArrayList(ast.NodeId) = .empty;
        try elements.append(self.storage, first);
        while (self.take(.comma)) {
            if (self.current().tag == .rbrace) break;
            try elements.append(self.storage, try self.expression(0));
        }
        const close = try self.closeValues(.rbrace);
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .set_literal = try elements.toOwnedSlice(self.storage) } });
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

    /// Parse `__stand_in[T](operand)`, `__clock_advance(clock, count)`, `__clock_monotonic(clock)`, `__clock_sleep(clock, count)` or
    /// `__stand_fail(capability, count)`, which only compiler-owned standard-library bytes may spell.
    fn parseStandIn(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        if (!self.trustedStdlib()) return self.sink.fail(
            eInternalName,
            token.span,
            "`__stand_in[...]`, `__clock_advance(...)`, `__clock_monotonic(...)`, `__clock_sleep(...)`, `__stand_fail(...)`, `__stream_memory(...)` and `__stream_text(...)` are reserved for compiler-internal standard-library sources; " ++
                "use `time.simulated_clock`, `random.seeded_entropy`, `filesystem.memory`, `environment.fixed`, `process.scripted` or `network.denied`",
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
        if (token.tag == .kw_clock_advance or token.tag == .kw_clock_sleep or token.tag == .kw_stand_fail) {
            _ = try self.expect(.comma);
            second = try self.expression(0);
        }
        const close = try self.expect(.rparen);
        const op: @FieldType(@FieldType(@FieldType(ast.Node, "data"), "stand_in"), "op") = switch (token.tag) {
            .kw_clock_advance => .advance,
            .kw_clock_monotonic => .monotonic,
            .kw_clock_sleep => .sleep,
            .kw_stand_fail => .fail,
            .kw_stream_memory => .stream_memory,
            .kw_stream_text => .stream_text,
            else => .build,
        };
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .stand_in = .{ .ty = ty, .first = first, .second = second, .op = op } } });
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
        if (token.tag == .kw_accept_resource) {
            _ = try self.expect(.lbracket);
            const ty = try self.typeName();
            _ = try self.expect(.rbracket);
            _ = try self.expect(.lparen);
            const value = try self.expression(0);
            const close = try self.expect(.rparen);
            return self.append(.{ .span = .join(token.span, close.span), .data = .{ .accept_resource = .{ .ty = ty, .value = value } } });
        }
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
        if (self.current().tag != .lbracket) return self.sink.fail(syntax_code, token.span, "`wrap` is a reserved word and cannot be used as a function or variable name");
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
    /// `bit_not(value)`: the complement in the operand's own width. A function
    /// rather than an operator because every bit operation has one spelling
    /// (`bit_and`, `bit_or`, `bit_xor`, `shift_left`, `shift_right`).
    fn parseBitNot(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        _ = try self.expect(.lparen);
        const operand = try self.expression(0);
        const close = try self.expect(.rparen);
        return self.append(.{ .span = .join(token.span, close.span), .data = .{ .unary = .{
            .op = .bit_not,
            .operand = operand,
            .op_span = token.span,
        } } });
    }
    fn parseBuiltin(self: *Parser, token: lex.Token) diagnostic.Error!ast.NodeId {
        self.cursor.pos += 1;
        _ = try self.expect(.lparen);
        const base = try self.expression(0);
        const spelling = self.src.text(token.span);
        const length = std.mem.eql(u8, spelling, "len");
        if (length and self.current().tag == .kw_for) {
            const at = self.current().span;
            return self.sink.failRelated(generator_code, at, generator_length_message, .{ .span = at, .message = generator_length_accepted, .role = .alternative });
        }
        if (!std.mem.eql(u8, spelling, "replace")) {
            const close = try self.expect(.rparen);
            return self.append(.{ .span = .join(token.span, close.span), .data = if (length) .{ .length = base } else .{ .unwrap = base } });
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
    const Pattern = struct { payload_patterns: []const ast.PatternField = &.{}, binding_names: []const ?Span = &.{}, ty: Span, name: Span, bindings: []const ?Span = &.{}, rest: bool = false };
    /// One `case` of a match statement: one arm, or one arm per alternative of a `|` list. Literal alternatives
    /// (`case 0 | 1:`, `case "x":`, `case True:`, `case -3:`, `case ord("+"):`) make one literal arm; a list of bare
    /// names is also read as one, and sema takes it for case names when the matched value is an enum or a union. Any
    /// other list is case patterns, `case text(value) | code(value):`, each parsed by `matchPattern`; every
    /// alternative becomes an arm of its own, all sharing the body, so exhaustiveness and duplicate arms are judged
    /// on them as on arms written apart.
    fn caseArms(self: *Parser, out: *std.ArrayList(ast.MatchArm)) diagnostic.Error!void {
        _ = try self.expect(.kw_case);
        if (!self.patternAlternativesAhead()) if (try self.literalAlternatives()) |literals| {
            const first = self.syntax.nodes.items[@backingInt(literals[0])].span;
            const body = try self.block(null);
            return out.append(self.storage, .{ .ty = first, .name = first, .literals = literals, .body = body, .alternatives = .{ .name_bodies = try self.nameBodies(literals, body) } });
        };
        var patterns: std.ArrayList(Pattern) = .empty;
        while (true) {
            try patterns.append(self.storage, try self.matchPattern());
            if (!self.take(.pipe)) break;
        }
        const body = try self.block(null);
        for (patterns.items, 0..) |pattern, position| {
            // Each alternative checks a body of its own (see `ast_subtree`); the first keeps the parsed one.
            const own = if (position == 0) body else try ast_subtree.cloneStatement(self.storage, .{ .nodes = &self.syntax.nodes, .statements = &self.syntax.statements, .growth = self.syntax.growth orelse self.storage }, body);
            try out.append(self.storage, .{
                .ty = pattern.ty,
                .name = pattern.name,
                .bindings = pattern.bindings,
                .binding_names = pattern.binding_names,
                .payload_patterns = pattern.payload_patterns,
                .body = own,
                .alternatives = .{ .rest = pattern.rest, .group = if (patterns.items.len > 1) body else null },
            });
        }
    }
    /// A copy of `body` for each bare name after the first of a literal arm that lists only names, empty for any other
    /// literal arm: the names are cases when the matched value turns out to be an enum or a union.
    fn nameBodies(self: *Parser, literals: []const ast.NodeId, body: ast.StatementId) diagnostic.Error![]const ast.StatementId {
        if (literals.len < 2) return &.{};
        for (literals) |literal| if (self.syntax.nodes.items[@backingInt(literal)].data != .name) return &.{};
        const copies = try self.storage.alloc(ast.StatementId, literals.len - 1);
        for (copies) |*copy| copy.* = try ast_subtree.cloneStatement(self.storage, .{ .nodes = &self.syntax.nodes, .statements = &self.syntax.statements, .growth = self.syntax.growth orelse self.storage }, body);
        return copies;
    }
    /// Whether the `..` of a rest marker is next: two adjacent dots.
    fn restAhead(self: *Parser) bool {
        const first = self.current();
        const second = self.tokens[self.cursor.pos + 1];
        return first.tag == .dot and second.tag == .dot and first.span.end == second.span.start;
    }
    /// Whether the `case` ahead lists case patterns rather than literals: some alternative of its `|` list is a
    /// case with a payload (`text(value)`), a qualified case, or `None`. A list of bare names stays a literal arm.
    fn patternAlternativesAhead(self: *Parser) bool {
        var position = self.cursor.pos;
        var depth: usize = 0;
        var starts = true;
        while (position + 1 < self.tokens.len) : (position += 1) {
            const token = self.tokens[position];
            if (starts and depth == 0) {
                starts = false;
                if (token.tag == .kw_none) return true;
                if (token.tag == .ident and !self.byteFormAt(position)) {
                    const next = self.tokens[position + 1].tag;
                    if (next == .lparen or next == .dot) return true;
                }
            }
            switch (token.tag) {
                .lparen, .lbracket => depth += 1,
                .rparen, .rbracket => depth -|= 1,
                .pipe => starts = depth == 0,
                .colon => if (depth == 0) return false,
                .eof, .indent, .dedent => return false,
                else => {},
            }
        }
        return false;
    }
    /// Whether the arm alternative ahead is a byte constant: `ord("=")`, or a string or bytes literal indexed as
    /// `b"="[0]`. A pattern never has a literal payload, so `ord(` followed by a literal is unambiguous.
    fn byteForm(self: *Parser) bool {
        return self.byteFormAt(self.cursor.pos);
    }
    fn byteFormAt(self: *Parser, position: usize) bool {
        if (position + 3 >= self.tokens.len) return false;
        const head = self.tokens[position];
        const next = self.tokens[position + 1];
        if (head.tag == .bytes) return next.tag == .lbracket;
        if (head.tag != .ident or next.tag != .lparen or !std.mem.eql(u8, self.src.text(head.span), "ord")) return false;
        return self.tokens[position + 2].tag == .bytes and self.tokens[position + 3].tag == .rparen;
    }
    /// The alternatives of a literal arm, or null when the arm is a case pattern. An arm
    /// starts a literal form with an integer, a minus sign before one, a string or bytes
    /// literal, `True` or `False`, or a name followed by `|`.
    fn literalAlternatives(self: *Parser) diagnostic.Error!?[]const ast.NodeId {
        const head = self.current();
        const literal_head = switch (head.tag) {
            .integer, .bytes, .kw_true, .kw_false => true,
            .minus => self.tokens[self.cursor.pos + 1].tag == .integer,
            .ident => self.tokens[self.cursor.pos + 1].tag == .pipe or self.byteForm(),
            else => false,
        };
        if (!literal_head) return null;
        var alternatives: std.ArrayList(ast.NodeId) = .empty;
        while (true) {
            try alternatives.append(self.storage, try self.literalAlternative());
            if (!self.take(.pipe)) break;
        }
        const listed = try alternatives.toOwnedSlice(self.storage);
        return listed;
    }
    /// One alternative of a literal arm: an integer (negative with a leading minus), a
    /// string or bytes literal, `True` or `False`, or a name naming a constant.
    fn literalAlternative(self: *Parser) diagnostic.Error!ast.NodeId {
        const token = self.current();
        if (self.byteForm()) return self.expression(10);
        if (token.tag == .minus) {
            self.cursor.pos += 1;
            const digits = try self.expect(.integer);
            const operand = try self.append(.{ .span = digits.span, .data = .{ .integer = digits.span } });
            return self.append(.{ .span = .join(token.span, digits.span), .data = .{ .unary = .{ .op = .neg, .operand = operand, .op_span = token.span } } });
        }
        self.cursor.pos += 1;
        return self.append(.{ .span = token.span, .data = switch (token.tag) {
            .integer => .{ .integer = token.span },
            .bytes => literal: {
                const decoded = try byte_literal.decode(self.storage, self.src, token.span, self.sink);
                break :literal if (self.src.text(token.span)[0] != 'b') .{ .text = decoded } else .{ .bytes = decoded };
            },
            .ident => .{ .name = token.span },
            else => .{ .boolean = token.tag == .kw_true },
        } });
    }
    fn matchPattern(self: *Parser) diagnostic.Error!Pattern {
        const head = self.current();
        // A case names a union, enum or result case — or `_`, or `None`. A
        // literal here is a payload field's value: a literal is a whole arm of
        // a match on an int, str, bytes or bool (`caseArm`), never a payload.
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
            var binding_names: std.ArrayList(?Span) = .empty;
            var payload_patterns: std.ArrayList(ast.PatternField) = .empty;
            if (self.current().tag != .rparen) while (true) {
                if (self.restAhead()) {
                    self.cursor.pos += 2;
                    pattern.rest = true;
                    if (self.current().tag != .rparen) return self.sink.fail(syntax_code, self.current().span, "the rest marker `..` ends a pattern: nothing follows it");
                    break;
                }
                const labelled = self.current().tag == .ident and self.tokens[self.cursor.pos + 1].tag == .equal;
                const label = if (labelled) (try self.expect(.ident)).span else null;
                if (labelled) _ = try self.expect(.equal);
                const field = try self.payloadPattern();
                try payload_patterns.append(self.storage, .{ .name = label, .pattern = field });
                try binding_names.append(self.storage, label);
                try bindings.append(self.storage, if (field.data == .binding) field.data.binding else null);
                if (!self.take(.comma) or self.current().tag == .rparen) break;
            };
            _ = try self.expect(.rparen);
            pattern.bindings = try bindings.toOwnedSlice(self.storage);
            pattern.binding_names = try binding_names.toOwnedSlice(self.storage);
            pattern.payload_patterns = try payload_patterns.toOwnedSlice(self.storage);
        }
        return pattern;
    }
    fn payloadPattern(self: *Parser) diagnostic.Error!ast.Pattern {
        try self.enter();
        defer self.cursor.depth -= 1;
        const head = self.current();
        if (head.tag == .ident and self.tokens[self.cursor.pos + 1].tag != .dot and self.tokens[self.cursor.pos + 1].tag != .lparen and self.tokens[self.cursor.pos + 1].tag != .lbracket) {
            self.cursor.pos += 1;
            return .{ .span = head.span, .data = .{ .binding = if (std.mem.eql(u8, self.src.text(head.span), "_")) null else head.span } };
        }
        const nested = try self.matchPattern();
        return .{ .span = .join(head.span, self.tokens[self.cursor.pos - 1].span), .data = .{ .variant = .{ .ty = nested.ty, .name = nested.name, .fields = nested.payload_patterns, .rest = nested.rest } } };
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
                .comma, .colon, .rparen => if (brackets == 0) return false,
                .lparen => if (brackets == 0) return applied,
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
            // PY-GENERATOR-1: `f(x for x in xs)` passes one generator expression,
            // which must be the only argument unless it is parenthesized.
            if (self.current().tag == .kw_for and values.items.len == 1 and !keyword) {
                values.items[0] = try self.generatorExpression(values.items[0]);
                if (self.current().tag == .comma) return self.sink.failRelated(syntax_code, self.current().span, generator_sole_message, .{ .span = self.current().span, .message = generator_sole_accepted, .role = .alternative });
                break;
            }
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
        if (token.tag == .ident) try self.rejectInternalTestName(token);
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
            name = try self.memberName();
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

/// PY-CHAIN-1: the six comparison operators share one precedence level, as in
/// Python, so `a < b == c` is one chain rather than a comparison of a bool.
/// Whether a binary operator token is one of the six chainable comparisons.
fn comparisonOperator(tag: lex.Tag) bool {
    return switch (tag) {
        .eq_eq, .bang_eq, .lt, .le, .gt, .ge => true,
        else => false,
    };
}
fn binaryPrecedence(tag: lex.Tag) ?u8 {
    return switch (tag) {
        .or_or => 1,
        .and_and => 2,
        // PY-CHAIN-1: the six comparisons share one level, so they chain.
        .eq_eq, .bang_eq, .lt, .le, .gt, .ge => 3,
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
