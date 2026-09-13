//! Mechanical translation of legacy brace sources into the canonical Python surface.
//! Declarations are printed from the parser's own tables; comments and blank lines
//! are replayed from the original token gaps, and every construct without a Python
//! spelling is reported instead of being approximated.
const std = @import("std");
const ast = @import("ast.zig");
const lex = @import("lexer.zig");
const parser = @import("parser.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Span = source.Span;
const Tag = lex.Tag;

/// Stable diagnostic code for a construct with no canonical Python spelling.
pub const unsupported_code = "E_MIGRATE_UNSUPPORTED";

/// Translation policy; partial output reports every gap instead of stopping at the first.
pub const Options = struct {
    /// Emit the remaining source with markers instead of failing on the first gap.
    allow_partial: bool = false,
    /// Print Python-surface input from its syntax tree instead of returning it byte for byte,
    /// which verifies the printer's spelling of Python-only forms such as `with arena()`.
    reprint: bool = false,
};

/// Failures returned by render; callers must handle these boundary errors.
pub const Error = diagnostic.Error;

/// Canonical whitespace sink with queued blank lines and four-space indentation.
const Output = struct {
    writer: *std.Io.Writer,
    indent: usize = 0,
    pending: usize = 0,
    line_start: bool = true,
    written: usize = 0,

    fn newline(self: *Output) Error!void {
        if (!self.line_start) self.writer.writeByte('\n') catch return error.OutOfMemory;
        self.line_start = true;
    }
    fn blank(self: *Output, count: usize) void {
        if (self.written == 0) return;
        if (self.pending < count) self.pending = count;
    }
    fn text(self: *Output, bytes: []const u8) Error!void {
        if (bytes.len == 0) return;
        if (self.line_start) {
            while (self.pending != 0) : (self.pending -= 1) self.writer.writeByte('\n') catch return error.OutOfMemory;
            for (0..self.indent) |_| self.writer.writeAll("    ") catch return error.OutOfMemory;
            self.line_start = false;
        }
        self.writer.writeAll(bytes) catch return error.OutOfMemory;
        self.written += bytes.len;
    }
    fn space(self: *Output) Error!void {
        if (!self.line_start) try self.text(" ");
    }
};

/// Allocator, policy, file dialect, queued partial-output markers, and the unsigned
/// bindings in scope, which decide whether legacy `/` and `%` already floor.
const Context = struct {
    allocator: std.mem.Allocator,
    options: Options,
    module: bool,
    notes: std.ArrayList([]const u8) = .empty,
    unsigned: std.StringHashMapUnmanaged(void) = .empty,
    declared: std.StringHashMapUnmanaged(usize) = .empty,
};

/// Report whether a source type spelling names an unsigned integer width.
fn unsignedType(text: []const u8) bool {
    inline for (.{ "u8", "u16", "u32", "u64" }) |width| {
        if (std.mem.eql(u8, text, width)) return true;
    }
    return false;
}

/// Report whether an integer literal carries an unsigned width suffix.
fn unsignedLiteral(text: []const u8) bool {
    const at = std.mem.indexOfScalar(u8, text, 'u') orelse return false;
    return unsignedType(text[at..]);
}

/// Kind and source extent of one top-level construct, in original file order.
const Item = struct { kind: Kind, name: Span, start: usize, end: usize };

/// Every top-level form the parser accepts, including module directives.
const Kind = enum {
    module_line,
    import_line,
    export_line,
    alias,
    constant,
    record,
    variants,
    domain,
    resource,
    function,
};

fn directiveKind(kind: Kind) bool {
    return kind == .module_line or kind == .import_line or kind == .export_line;
}

/// Ordinary, host, and C-ABI function prefixes retained from the legacy head.
const Linkage = enum { ordinary, host, c_abi };

const Precedence = struct {
    const call: u8 = 16;
    const unary: u8 = 14;
    const product: u8 = 12;
    const sum: u8 = 10;
    const compare: u8 = 8;
    const equality: u8 = 6;
    const inversion: u8 = 5;
    const conjunction: u8 = 4;
    const disjunction: u8 = 2;
};

/// Report whether the first meaningful line declares a module, selecting module syntax.
pub fn isModuleSource(bytes: []const u8) bool {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        const text = std.mem.trim(u8, line, " \t\r");
        if (text.len == 0 or std.mem.startsWith(u8, text, "#") or std.mem.startsWith(u8, text, "//")) continue;
        return std.mem.startsWith(u8, text, "module ") or std.mem.eql(u8, text, "module");
    }
    return false;
}

/// Translate one already-parsed file and allocate its Python-surface spelling.
/// Python-surface input is reproduced byte for byte, so migration is idempotent.
pub fn render(allocator: std.mem.Allocator, src: source.Source, options: Options, sink: *diagnostic.Sink) Error![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const tokens = try lex.lex(arena.allocator(), src.bytes, sink);
    const module = tokens[0].tag == .ident and std.mem.eql(u8, src.text(tokens[0].span), "module");
    var syntax_parser: parser.Parser = .{ .src = src, .arena = &arena, .tokens = tokens, .sink = sink };
    const syntax = if (module) try syntax_parser.parseModule() else try syntax_parser.parse();
    if (lex.isPythonSource(src.bytes) and !options.reprint) return allocator.dupe(u8, src.bytes);
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    var out: Output = .{ .writer = &output.writer };
    var walk: Walk = .{
        .src = src,
        .tokens = tokens,
        .syntax = syntax,
        .sink = sink,
        .out = &out,
        .ctx = .{ .allocator = arena.allocator(), .options = options, .module = module },
    };
    try walk.program();
    try walk.line();
    const bytes = output.toOwnedSlice() catch return error.OutOfMemory;
    errdefer allocator.free(bytes);
    if (!lex.isPythonSource(bytes)) return sink.fail(
        unsupported_code,
        .{ .start = 0, .end = 0 },
        "file declares no function or record, so it cannot select the Python dialect",
    );
    return bytes;
}

/// Cursor over one parsed file that prints declarations, statements, and expressions.
const Walk = struct {
    src: source.Source,
    tokens: []const lex.Token,
    syntax: ast.Program,
    sink: *diagnostic.Sink,
    out: *Output,
    cursor: usize = 0,
    ctx: Context,

    fn node(self: *Walk, id: ast.NodeId) ast.Node {
        return self.syntax.nodes.items[@backingInt(id)];
    }
    fn stmt(self: *Walk, id: ast.StatementId) ast.Statement {
        return self.syntax.statements.items[@backingInt(id)];
    }
    fn word(self: *Walk, at: usize, text: []const u8) bool {
        return self.tokens[at].tag == .ident and std.mem.eql(u8, self.src.text(self.tokens[at].span), text);
    }
    /// Name a construct by the keyword that introduces it in the original source.
    fn leadingWord(self: *Walk, span: Span) []const u8 {
        const at = self.tokenAt(span.start);
        if (at < self.tokens.len and self.tokens[at].span.start == span.start) return self.src.text(self.tokens[at].span);
        return "an explicit storage operation";
    }

    /// Reject a construct, or mark it in place when partial output is requested.
    fn reject(self: *Walk, span: Span, construct: []const u8) Error!void {
        if (!self.ctx.options.allow_partial) {
            const message = try std.fmt.allocPrint(self.sink.allocator, "no Python spelling for {s}", .{construct});
            return self.sink.fail(unsupported_code, span, message);
        }
        const message = try std.fmt.allocPrint(self.sink.allocator, "no Python spelling for {s}", .{construct});
        self.sink.items.append(self.sink.allocator, .{
            .code = unsupported_code,
            .severity = .warning,
            .span = span,
            .message = message,
        }) catch return error.OutOfMemory;
        try self.ctx.notes.append(self.ctx.allocator, construct);
    }

    /// End the current output line, appending any queued partial-output markers.
    fn line(self: *Walk) Error!void {
        if (self.ctx.notes.items.len != 0) {
            try self.out.text("  # MIGRATE: unsupported ");
            for (self.ctx.notes.items, 0..) |note, index| {
                if (index != 0) try self.out.text(", ");
                try self.out.text(note);
            }
            self.ctx.notes.clearRetainingCapacity();
        }
        try self.out.newline();
    }

    /// Report an unconvertible expression and keep partial output syntactically whole.
    fn rejectValue(self: *Walk, span: Span, construct: []const u8) Error!void {
        try self.reject(span, construct);
        try self.out.text("todo<i64>()");
    }

    /// Report an unconvertible statement, leaving a marked empty suite behind.
    fn rejectStatement(self: *Walk, span: Span, construct: []const u8) Error!void {
        try self.reject(span, construct);
        try self.out.text("pass");
    }

    // -- comments and blank lines ------------------------------------------

    fn commentAt(bytes: []const u8, from: usize, limit: usize) ?usize {
        var at = from;
        while (at < limit) : (at += 1) {
            if (bytes[at] == '#') return at;
            if (bytes[at] == '/' and at + 1 < limit and bytes[at + 1] == '/') return at;
        }
        return null;
    }

    /// Replay comments and blank lines from the gap before the given offset.
    fn flush(self: *Walk, upto: usize) Error!void {
        if (upto <= self.cursor) return;
        const bytes = self.src.bytes;
        var at = self.cursor;
        while (commentAt(bytes, at, upto)) |start| {
            const breaks = std.mem.count(u8, bytes[at..start], "\n");
            if (breaks == 0 and !self.out.line_start) try self.out.space() else {
                try self.line();
                if (breaks > 1) self.out.blank(1);
            }
            const ending = std.mem.indexOfScalarPos(u8, bytes, start, '\n') orelse bytes.len;
            const body = std.mem.trimEnd(u8, bytes[start..@min(ending, upto)], " \t\r");
            try self.out.text("#");
            try self.out.text(if (std.mem.startsWith(u8, body, "//")) body[2..] else body[1..]);
            try self.line();
            at = @min(ending + 1, upto);
        }
        if (std.mem.count(u8, bytes[at..upto], "\n") > 1) {
            try self.line();
            self.out.blank(1);
        }
        self.cursor = upto;
    }

    fn advance(self: *Walk, to: usize) void {
        if (to > self.cursor) self.cursor = to;
    }

    // -- top level ---------------------------------------------------------

    /// Print every module directive and declaration in original source order.
    fn program(self: *Walk) Error!void {
        var items: std.ArrayList(Item) = .empty;
        try self.scan(&items);
        var previous: ?Kind = null;
        for (items.items) |item| {
            const adjacent = directiveKind(item.kind) and directiveKind(previous orelse item.kind);
            if (previous != null and !adjacent) self.out.blank(2);
            try self.flush(item.start);
            try self.line();
            try self.declaration(item);
            self.advance(item.end);
            previous = item.kind;
        }
        try self.flush(self.src.bytes.len);
    }

    /// Collect top-level directives and declarations with their byte extents.
    fn scan(self: *Walk, into: *std.ArrayList(Item)) Error!void {
        var pos: usize = 0;
        if (self.ctx.module) {
            pos = try self.directive(into, pos, .module_line);
            while (self.word(pos, "import")) pos = try self.directive(into, pos, .import_line);
        }
        while (self.tokens[pos].tag != .eof) {
            if (self.ctx.module and self.word(pos, "export")) {
                pos = try self.directive(into, pos, .export_line);
                continue;
            }
            const start = self.tokens[pos].span.start;
            const entry = try self.head(&pos);
            const end = lex.declarationEnd(self.src.bytes, self.tokens, pos, entry.braced);
            if (end == pos) return error.InternalError;
            pos = end;
            try into.append(self.ctx.allocator, .{
                .kind = entry.kind,
                .name = entry.name,
                .start = start,
                .end = self.tokens[end - 1].span.end,
            });
        }
    }

    fn directive(self: *Walk, into: *std.ArrayList(Item), from: usize, kind: Kind) Error!usize {
        const start = self.tokens[from].span.start;
        var pos = from + 1;
        while (self.tokens[pos].tag != .eof) : (pos += 1) {
            const tag = self.tokens[pos].tag;
            if (tag == .semicolon) {
                pos += 1;
                break;
            }
            if (lex.implicitTerminator(self.src.bytes, self.tokens, pos)) break;
        }
        try into.append(self.ctx.allocator, .{
            .kind = kind,
            .name = self.tokens[from].span,
            .start = start,
            .end = self.tokens[pos - 1].span.end,
        });
        return pos;
    }

    const Head = struct { kind: Kind, name: Span, braced: bool };

    fn head(self: *Walk, pos: *usize) Error!Head {
        if (self.simple(pos.*)) |form| {
            pos.* += 1;
            const name = self.tokens[pos.*].span;
            if (self.tokens[pos.*].tag != .ident) return error.InternalError;
            pos.* += 1;
            return .{ .kind = form.kind, .name = name, .braced = form.braced };
        }
        const abi = self.linkage(pos.*);
        if (abi != .ordinary) pos.* += 1;
        if (self.tokens[pos.*].tag == .kw_private) pos.* += 1;
        if (self.tokens[pos.*].tag == .kw_conversion) pos.* += 1;
        if (self.tokens[pos.*].tag != .kw_fn) return error.InternalError;
        pos.* += 1;
        if (self.tokens[pos.*].tag != .ident) return error.InternalError;
        const name = self.tokens[pos.*].span;
        pos.* += 1;
        return .{ .kind = .function, .name = name, .braced = abi == .ordinary };
    }

    fn linkage(self: *Walk, at: usize) Linkage {
        if (self.word(at, "extern")) return .c_abi;
        if (self.word(at, "host")) return .host;
        return .ordinary;
    }

    const Simple = struct { kind: Kind, braced: bool };

    fn simple(self: *Walk, at: usize) ?Simple {
        return switch (self.tokens[at].tag) {
            .kw_type => .{ .kind = .alias, .braced = false },
            .kw_const => .{ .kind = .constant, .braced = false },
            .kw_enum, .kw_union => .{ .kind = .variants, .braced = true },
            .kw_domain => .{ .kind = .domain, .braced = true },
            .kw_struct => .{ .kind = .record, .braced = true },
            .ident => if (self.word(at, "resource"))
                .{ .kind = .resource, .braced = false }
            else if (self.word(at, "result"))
                .{ .kind = .variants, .braced = true }
            else
                null,
            else => null,
        };
    }

    // -- declarations ------------------------------------------------------

    fn declaration(self: *Walk, item: Item) Error!void {
        switch (item.kind) {
            .module_line, .import_line, .export_line => try self.directiveText(item),
            .alias => try self.alias(item.name),
            .constant => try self.constant(item.name),
            .record => try self.record(item.name),
            .variants => try self.variants(item.name),
            .domain => try self.domain(item.name),
            .resource => try self.resource(item.name),
            .function => try self.function(self.findFunction(item.name) orelse return error.InternalError),
        }
    }

    /// Reprint a module directive without its legacy statement terminator.
    fn directiveText(self: *Walk, item: Item) Error!void {
        var at = self.tokenAt(item.start);
        var first = true;
        while (self.tokens[at].span.start < item.end) : (at += 1) {
            const token = self.tokens[at];
            if (token.tag == .semicolon or token.tag == .eof) break;
            if (!first and token.tag != .dot and self.tokens[at - 1].tag != .dot) try self.out.space();
            try self.out.text(self.src.text(token.span));
            first = false;
        }
    }

    fn findFunction(self: *Walk, name: Span) ?ast.Function {
        for (self.syntax.functions) |item| {
            if (item.name.start == name.start) return item;
        }
        return null;
    }

    fn alias(self: *Walk, name: Span) Error!void {
        for (self.syntax.types.expressions.aliases) |item| {
            if (item.name.start != name.start) continue;
            try self.out.text("type ");
            try self.out.text(self.src.text(name));
            try self.out.text(" = ");
            return self.typeName(item.target);
        }
        return error.InternalError;
    }

    fn constant(self: *Walk, name: Span) Error!void {
        const declared = self.findFunction(name) orelse return error.InternalError;
        try self.out.text("const ");
        try self.out.text(self.src.text(name));
        try self.out.text(": ");
        try self.typeName(declared.signature.return_type);
        try self.out.text(" = ");
        const body = self.stmt(declared.body);
        const statements = body.data.block;
        if (statements.len != 1) return error.InternalError;
        try self.expression(self.stmt(statements[0]).data.ret, 0);
    }

    fn record(self: *Walk, name: Span) Error!void {
        for (self.syntax.types.records) |item| {
            if (item.name.start != name.start) continue;
            try self.out.text("class ");
            try self.out.text(self.src.text(name));
            try self.typeParameters(item.type_parameters);
            try self.out.text(":");
            self.out.indent += 1;
            defer self.out.indent -= 1;
            if (item.fields.len == 0) {
                try self.line();
                try self.out.text("pass");
                return;
            }
            for (item.fields) |field| {
                try self.flush(field.name.start);
                try self.line();
                try self.out.text(self.src.text(field.name));
                try self.out.text(": ");
                try self.typeName(field.ty);
                self.advance(field.ty.end);
            }
            return;
        }
        return error.InternalError;
    }

    fn variants(self: *Walk, name: Span) Error!void {
        for (self.syntax.types.variants) |item| {
            if (item.name.start != name.start) continue;
            try self.out.text(if (item.fallible) "result " else if (item.is_union) "union " else "enum ");
            try self.out.text(self.src.text(name));
            try self.typeParameters(item.type_parameters);
            try self.out.text(":");
            self.out.indent += 1;
            defer self.out.indent -= 1;
            for (item.cases, 0..) |case, index| {
                try self.flush(case.name.start);
                try self.line();
                try self.out.text(self.src.text(case.name));
                if (case.payload) |payload| {
                    try self.out.text(": ");
                    try self.typeName(payload);
                    self.advance(payload.end);
                } else self.advance(case.name.end);
                if (index + 1 != item.cases.len) try self.out.text(",");
            }
            return;
        }
        return error.InternalError;
    }

    fn domain(self: *Walk, name: Span) Error!void {
        for (self.syntax.types.domains) |item| {
            if (item.name.start != name.start) continue;
            try self.out.text("domain ");
            try self.out.text(self.src.text(name));
            try self.out.text(": ");
            try self.typeName(item.backing);
            try self.out.text(":");
            self.advance(item.backing.end);
            self.out.indent += 1;
            defer self.out.indent -= 1;
            if (item.codec) |entry| try self.codec(entry);
            var first = item.codec == null;
            for (self.syntax.functions) |member| {
                const owner = member.policy.owner orelse continue;
                if (owner.start != name.start) continue;
                if (!first) self.out.blank(1);
                first = false;
                try self.flush(member.name.start);
                try self.line();
                try self.function(member);
            }
            if (first and item.codec == null) {
                try self.line();
                try self.out.text("pass");
            }
            return;
        }
        return error.InternalError;
    }

    fn codec(self: *Walk, entry: ast.Codec) Error!void {
        try self.line();
        try self.out.text("codec ");
        try self.typeName(entry.wire);
        try self.out.text(":");
        self.out.indent += 1;
        defer self.out.indent -= 1;
        try self.line();
        try self.out.text("decode: ");
        try self.out.text(self.src.text(entry.decode));
        try self.out.text(",");
        try self.line();
        try self.out.text("encode: ");
        try self.out.text(self.src.text(entry.encode));
        self.advance(@max(entry.decode.end, entry.encode.end));
    }

    fn resource(self: *Walk, name: Span) Error!void {
        for (self.syntax.types.resources) |item| {
            if (item.name.start != name.start) continue;
            try self.out.text("resource ");
            try self.out.text(self.src.text(name));
            try self.out.text(": ");
            try self.out.text(self.src.text(item.backing));
            return;
        }
        return error.InternalError;
    }

    fn function(self: *Walk, item: ast.Function) Error!void {
        self.ctx.unsigned.clearRetainingCapacity();
        self.ctx.declared.clearRetainingCapacity();
        try self.countDeclarations(item.body);
        for (item.signature.parameters) |parameter| {
            try self.declare(parameter.name);
        }
        for (item.signature.parameters) |parameter| {
            if (unsignedType(self.src.text(parameter.ty))) try self.ctx.unsigned.put(self.ctx.allocator, self.src.text(parameter.name), {});
        }
        if (item.policy.c_abi) try self.out.text("extern ") else if (item.policy.host != null) try self.out.text("host ");
        if (item.policy.restricted) try self.out.text("private ");
        if (item.policy.conversion) try self.out.text("conversion ");
        try self.out.text("def ");
        try self.out.text(self.src.text(item.name));
        try self.typeParameters(item.signature.type_parameters);
        try self.out.text("(");
        for (item.signature.parameters, 0..) |parameter, index| {
            if (index != 0) try self.out.text(", ");
            try self.out.text(self.src.text(parameter.name));
            try self.out.text(": ");
            try self.typeName(parameter.ty);
            if (parameter.default_value) |default| {
                try self.out.text(" = ");
                try self.expression(default, 0);
            }
        }
        try self.out.text(")");
        if (!self.omittedReturn(item.signature.return_type)) {
            try self.out.text(" -> ");
            try self.typeName(item.signature.return_type);
        }
        if (item.policy.effect_bound) |bound| {
            if (bound.span.end > bound.span.start) {
                try self.out.text(" ");
                try self.out.text(self.src.text(bound.span));
                self.advance(bound.span.end);
            }
        }
        if (item.policy.host != null) return;
        try self.out.text(":");
        self.out.indent += 1;
        defer self.out.indent -= 1;
        try self.suite(item.body);
    }

    /// Unit results carry no Python annotation; every other result keeps its type.
    fn omittedReturn(self: *Walk, ty: Span) bool {
        if (ty.end <= ty.start) return true;
        const text = std.mem.trim(u8, self.src.text(ty), " \t\r\n");
        return std.mem.eql(u8, text, "unit") or std.mem.eql(u8, text, "()");
    }

    // -- types -------------------------------------------------------------

    fn tokenAt(self: *Walk, offset: usize) usize {
        var low: usize = 0;
        var high: usize = self.tokens.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (self.tokens[middle].span.start < offset) low = middle + 1 else high = middle;
        }
        return low;
    }

    /// Print a source type span using square-bracket generics and dotted qualification.
    fn typeName(self: *Walk, span: Span) Error!void {
        if (span.end <= span.start) return self.out.text("None");
        var at = self.tokenAt(span.start);
        var first = true;
        var previous: Tag = .eof;
        var ceiling = false;
        while (at < self.tokens.len and self.tokens[at].span.start < span.end) : (at += 1) {
            const token = self.tokens[at];
            if (token.tag == .ampersand) try self.reject(token.span, "a borrowed type");
            if (token.tag == .colon and self.tokens[at + 1].tag == .colon) {
                try self.out.text(".");
                previous = .dot;
                ceiling = false;
                at += 1;
                continue;
            }
            // An empty `effects()` ceiling keeps its parentheses; a bare `()` is the unit type.
            if (token.tag == .lparen and self.tokens[at + 1].tag == .rparen and !ceiling) {
                try self.out.text("None");
                previous = .ident;
                at += 1;
                first = false;
                continue;
            }
            const rendered: []const u8 = switch (token.tag) {
                .lt => "[",
                .gt, .ge => "]",
                .ident => if (std.mem.eql(u8, self.src.text(token.span), "unit")) "None" else self.src.text(token.span),
                else => self.src.text(token.span),
            };
            if (!first and typeSpace(previous, token.tag)) try self.out.space();
            try self.out.text(rendered);
            previous = token.tag;
            ceiling = token.tag == .ident and std.mem.eql(u8, self.src.text(token.span), "effects");
            first = false;
        }
        self.advance(span.end);
    }

    fn typeParameters(self: *Walk, parameters: []const ast.TypeParameter) Error!void {
        if (parameters.len == 0) return;
        try self.out.text("[");
        for (parameters, 0..) |parameter, index| {
            if (index != 0) try self.out.text(", ");
            if (parameter.constant_length) try self.out.text("const ");
            try self.out.text(self.src.text(parameter.name));
            if (parameter.constant_length) {
                try self.out.text(": u64");
                continue;
            }
            if (self.copyOnly(parameter)) continue;
            try self.out.text(": ");
            try self.requirements(parameter);
        }
        try self.out.text("]");
    }

    /// A lone `copy` requirement is the Python default for a bare type parameter.
    fn copyOnly(self: *Walk, parameter: ast.TypeParameter) bool {
        if (parameter.default_copy) return true;
        if (parameter.field_requirements.len != 0 or parameter.operation_requirements.len != 0) return false;
        if (parameter.requirements.len != 1) return false;
        return std.mem.eql(u8, self.src.text(parameter.requirements[0]), "copy");
    }

    fn requirements(self: *Walk, parameter: ast.TypeParameter) Error!void {
        var written: usize = 0;
        for (parameter.requirements) |requirement| {
            if (written != 0) try self.out.text(" + ");
            try self.out.text(self.src.text(requirement));
            written += 1;
        }
        for (parameter.field_requirements) |field| {
            if (written != 0) try self.out.text(" + ");
            try self.out.text("field(");
            try self.out.text(self.src.text(field.name));
            try self.out.text(": ");
            try self.typeName(field.ty);
            try self.out.text(")");
            written += 1;
        }
        for (parameter.operation_requirements) |contract| {
            if (written != 0) try self.out.text(" + ");
            try self.operation(contract);
            written += 1;
        }
    }

    fn operation(self: *Walk, item: ast.Operation) Error!void {
        try self.out.text("op(");
        try self.out.text(self.src.text(item.name));
        try self.out.text("(");
        for (item.parameters, 0..) |parameter, index| {
            if (index != 0) try self.out.text(", ");
            try self.out.text(self.src.text(parameter.name));
            try self.out.text(": ");
            try self.typeName(parameter.ty);
        }
        try self.out.text(") -> ");
        try self.typeName(item.return_type);
        try self.out.text(" ");
        try self.out.text(self.src.text(item.effect_bound.span));
        try self.out.text(")");
    }

    // -- statements --------------------------------------------------------

    /// Print a block as an indented suite, or `pass` when it holds no statements.
    fn suite(self: *Walk, id: ast.StatementId) Error!void {
        const block = self.stmt(id);
        const statements = block.data.block;
        if (statements.len == 0) {
            try self.flush(if (block.span.end > block.span.start) block.span.end - 1 else block.span.end);
            try self.line();
            try self.out.text("pass");
            self.advance(block.span.end);
            return;
        }
        for (statements) |child| {
            const span = self.stmt(child).span;
            try self.flush(span.start);
            try self.line();
            try self.statement(child);
            self.advance(span.end);
        }
        try self.flush(if (block.span.end > block.span.start) block.span.end - 1 else block.span.end);
        self.advance(block.span.end);
    }

    fn indented(self: *Walk, id: ast.StatementId) Error!void {
        self.out.indent += 1;
        defer self.out.indent -= 1;
        if (self.stmt(id).data != .block) {
            try self.line();
            return self.statement(id);
        }
        try self.suite(id);
    }

    fn statement(self: *Walk, id: ast.StatementId) Error!void {
        const item = self.stmt(id);
        switch (item.data) {
            .block => |children| try self.scopeBlock(item, children),
            .assertion => |check| try self.assertStatement(check),
            .ret => |result| try self.returnStatement(item, result),
            .loop_exit => |is_continue| try self.out.text(if (is_continue) "continue" else "break"),
            .for_each => |loop| try self.forEach(loop),
            .for_range => |loop| try self.forRange(loop),
            .loop => |loop| {
                try self.out.text("while ");
                try self.expression(loop.condition, 0);
                try self.out.text(":");
                try self.indented(loop.body);
            },
            .branch => |choice| try self.branch(choice),
            .match => |cases| try self.match(cases),
            .discard => |dropped| {
                if (!item.implicit_discard) try self.out.text("_ = ");
                try self.expression(dropped, 0);
            },
            .binding => |declared| try self.binding(declared),
            .assignment => |assignment| {
                try self.out.text(self.src.text(assignment.name));
                try self.out.text(switch (assignment.op) {
                    .set => " = ",
                    .add => " += ",
                    .sub => " -= ",
                });
                try self.expression(assignment.value, 0);
            },
            .managed_arena => |scope| {
                try self.out.text("with arena()");
                if (scope.name) |name| {
                    try self.out.text(" as ");
                    try self.out.text(self.src.text(name));
                }
                try self.out.text(":");
                try self.indented(scope.body);
            },
        }
    }

    /// Python has no bare scope block, so inline one whose bindings are unique in the
    /// enclosing function. A name declared twice would change meaning once the braces go.
    fn scopeBlock(self: *Walk, item: ast.Statement, children: []const ast.StatementId) Error!void {
        for (children) |child| {
            if (try self.reusedName(child)) return self.rejectStatement(item.span, "a bare nested scope block");
        }
        if (children.len == 0) return self.out.text("pass");
        for (children, 0..) |child, index| {
            const span = self.stmt(child).span;
            try self.flush(span.start);
            if (index != 0) try self.line();
            try self.statement(child);
            self.advance(span.end);
        }
        try self.flush(if (item.span.end > item.span.start) item.span.end - 1 else item.span.end);
        self.advance(item.span.end);
    }

    /// Report whether a statement declares a name that another declaration in this function
    /// also introduces, which inlining would collapse into one binding.
    fn reusedName(self: *Walk, id: ast.StatementId) Error!bool {
        const item = self.stmt(id);
        return switch (item.data) {
            .binding => |declared| self.repeated(declared.name),
            .for_each => |loop| self.repeated(loop.name) or (loop.index_name != null and self.repeated(loop.index_name.?)),
            .for_range => |loop| self.repeated(loop.name),
            .managed_arena => |scope| scope.name != null and self.repeated(scope.name.?),
            else => false,
        };
    }

    fn repeated(self: *Walk, name: Span) bool {
        return (self.ctx.declared.get(self.src.text(name)) orelse 0) > 1;
    }

    /// Count every declaration of each name in one function body, including its parameters.
    fn countDeclarations(self: *Walk, id: ast.StatementId) Error!void {
        const item = self.stmt(id);
        switch (item.data) {
            .block => |children| for (children) |child| try self.countDeclarations(child),
            .binding => |declared| try self.declare(declared.name),
            .for_each => |loop| {
                try self.declare(loop.name);
                if (loop.index_name) |index| try self.declare(index);
                try self.countDeclarations(loop.body);
            },
            .for_range => |loop| {
                try self.declare(loop.name);
                try self.countDeclarations(loop.body);
            },
            .branch => |choice| {
                try self.countDeclarations(choice.then_body);
                if (choice.else_body) |otherwise| try self.countDeclarations(otherwise);
            },
            .loop => |loop| try self.countDeclarations(loop.body),
            .match => |cases| for (cases.arms) |arm| {
                if (arm.binding) |bound| try self.declare(bound);
                try self.countDeclarations(arm.body);
            },
            .managed_arena => |scope| {
                if (scope.name) |name| try self.declare(name);
                try self.countDeclarations(scope.body);
            },
            else => {},
        }
    }

    fn declare(self: *Walk, name: Span) Error!void {
        const key = self.src.text(name);
        const entry = self.ctx.declared.getOrPut(self.ctx.allocator, key) catch return error.OutOfMemory;
        entry.value_ptr.* = if (entry.found_existing) entry.value_ptr.* + 1 else 1;
    }

    /// `assert` has no legacy spelling, so only Python reprinting reaches this.
    fn assertStatement(self: *Walk, check: ast.Assertion) Error!void {
        try self.out.text("assert ");
        try self.expression(check.condition, 0);
        const literal = check.literal orelse return;
        try self.out.text(", ");
        try self.out.text(self.src.text(literal));
    }
    fn returnStatement(self: *Walk, item: ast.Statement, result: ast.NodeId) Error!void {
        try self.out.text("return");
        const returned = self.node(result);
        if (returned.data == .unit and returned.span.start == item.span.start) return;
        try self.out.text(" ");
        try self.expression(result, 0);
    }

    fn forEach(self: *Walk, loop: @FieldType(@FieldType(ast.Statement, "data"), "for_each")) Error!void {
        try self.out.text("for ");
        if (loop.index_name) |index| {
            try self.out.text(self.src.text(index));
            try self.out.text(", ");
        }
        try self.out.text(self.src.text(loop.name));
        try self.out.text(" in ");
        if (loop.index_name != null) try self.out.text("enumerate(");
        try self.expression(loop.iterable, 0);
        if (loop.index_name != null) try self.out.text(")");
        try self.out.text(":");
        try self.indented(loop.body);
    }

    fn forRange(self: *Walk, loop: @FieldType(@FieldType(ast.Statement, "data"), "for_range")) Error!void {
        try self.out.text("for ");
        try self.out.text(self.src.text(loop.name));
        try self.out.text(" in range(");
        if (self.node(loop.start).data != .unit) {
            try self.expression(loop.start, 0);
            try self.out.text(", ");
        }
        try self.expression(loop.end, 0);
        try self.out.text("):");
        try self.indented(loop.body);
    }

    fn branch(self: *Walk, item: @FieldType(@FieldType(ast.Statement, "data"), "branch")) Error!void {
        try self.out.text("if ");
        try self.expression(item.condition, 0);
        try self.out.text(":");
        try self.indented(item.then_body);
        const otherwise = item.else_body orelse return;
        const nested = self.stmt(otherwise);
        try self.flush(nested.span.start);
        try self.line();
        if (nested.data == .branch) {
            try self.out.text("el");
            return self.statement(otherwise);
        }
        try self.out.text("else:");
        try self.indented(otherwise);
    }

    fn match(self: *Walk, item: @FieldType(@FieldType(ast.Statement, "data"), "match")) Error!void {
        try self.out.text("match ");
        try self.expression(item.value, 0);
        try self.out.text(":");
        self.out.indent += 1;
        defer self.out.indent -= 1;
        for (item.arms) |arm| {
            try self.flush(if (arm.ty.end > arm.ty.start) arm.ty.start else arm.name.start);
            try self.line();
            try self.out.text("case ");
            if (arm.ty.end > arm.ty.start) {
                try self.variantTypeName(arm.ty);
                try self.out.text(".");
            }
            try self.out.text(self.src.text(arm.name));
            if (arm.binding) |bound| {
                try self.out.text("(");
                try self.out.text(self.src.text(bound));
                try self.out.text(")");
            } else if (arm.discard_payload) try self.out.text("(_)");
            try self.out.text(":");
            try self.indented(arm.body);
        }
    }

    fn binding(self: *Walk, item: @FieldType(@FieldType(ast.Statement, "data"), "binding")) Error!void {
        try self.out.text(self.src.text(item.name));
        if (item.annotation) |annotation| {
            try self.out.text(": ");
            try self.typeName(annotation);
        } else if (self.inferredResult(item.value)) |ty| {
            try self.out.text(": ");
            try self.typeName(ty);
        }
        try self.out.text(" = ");
        try self.expression(item.value, 0);
        const declared = if (item.annotation) |annotation| unsignedType(self.src.text(annotation)) else false;
        if (declared or self.unsignedValue(item.value)) try self.ctx.unsigned.put(self.ctx.allocator, self.src.text(item.name), {});
    }

    /// Report whether an expression is certainly an unsigned integer, so legacy truncating
    /// `/` and `%` already agree with Python's flooring `//` and `%` on it. Operand types
    /// match on both sides of an integer operator, so one unsigned side settles the pair.
    fn unsignedValue(self: *Walk, id: ast.NodeId) bool {
        const item = self.node(id);
        return switch (item.data) {
            .integer => |span| unsignedLiteral(self.src.text(span)),
            .length => true,
            .cast, .wrap => |typedValue| unsignedType(self.src.text(typedValue.ty)),
            .name => |span| self.ctx.unsigned.contains(self.src.text(span)),
            .binary => |binary| binary.op != .python_div and
                (self.unsignedValue(binary.left) or self.unsignedValue(binary.right)),
            .call => |call| self.returnsUnsigned(call.name),
            else => false,
        };
    }

    /// Report whether a declared function in this file returns an unsigned integer.
    fn returnsUnsigned(self: *Walk, name: Span) bool {
        const called = self.src.text(name);
        for (self.syntax.functions) |declared| {
            if (!std.mem.eql(u8, self.src.text(declared.name), called)) continue;
            return unsignedType(self.src.text(declared.signature.return_type));
        }
        return false;
    }

    /// Contextual literals need an expected type, so an unannotated binding gains one.
    /// Contextual `Ok`/`Err`, fixed arrays and enum-indexed tables all lose their type
    /// spelling in the Python surface and recover it from the binding annotation.
    fn inferredResult(self: *Walk, initializer: ast.NodeId) ?Span {
        const item = self.node(initializer);
        if (item.data == .array) return item.data.array.ty;
        if (item.data == .record) {
            const name = item.data.record.name;
            const spelled = self.src.text(name);
            return if (spelled.len != 0 and spelled[0] == '[') name else null;
        }
        if (item.data != .variant) return null;
        // A generic variant loses its arguments in the Python spelling and recovers them here.
        const named = self.src.text(item.data.variant.ty);
        if (std.mem.indexOfAny(u8, named, "<[") != null) return item.data.variant.ty;
        if (self.resultCase(item.data.variant) == null) return null;
        return item.data.variant.ty;
    }

    // -- expressions -------------------------------------------------------

    fn expression(self: *Walk, id: ast.NodeId, min: u8) Error!void {
        const item = self.node(id);
        const level = precedenceOf(item);
        const wrap = level < min;
        if (wrap) try self.out.text("(");
        try self.value(item);
        if (wrap) try self.out.text(")");
    }

    fn precedenceOf(item: ast.Node) u8 {
        return switch (item.data) {
            .binary => |binary| switch (binary.op) {
                .logical_or => Precedence.disjunction,
                .logical_and => Precedence.conjunction,
                .eq, .ne => Precedence.equality,
                .lt, .le, .gt, .ge => Precedence.compare,
                .add, .sub => Precedence.sum,
                .mul, .div, .rem, .floor_div, .floor_rem, .python_div => Precedence.product,
                else => Precedence.call,
            },
            .membership => Precedence.equality,
            .unary => |unary| switch (unary.op) {
                .not => Precedence.inversion,
                .neg => Precedence.unary,
                else => Precedence.call,
            },
            else => Precedence.call,
        };
    }

    fn value(self: *Walk, item: ast.Node) Error!void {
        switch (item.data) {
            .integer => |span| try self.out.text(self.src.text(span)),
            .boolean => |flag| try self.out.text(if (flag) "True" else "False"),
            .unit => try self.out.text("None"),
            .name => |span| try self.qualified(self.src.text(span)),
            .text, .format, .comprehension => try self.out.text(self.src.text(item.span)),
            .bytes => try self.byteLiteral(item.span),
            .list_literal => |values| try self.sequence(values, "[", "]"),
            .dictionary_literal => |entries| try self.dictionary(entries),
            .record => |literal| try self.recordLiteral(literal),
            .variant => |literal| try self.variantValue(item, literal),
            .call => |call| try self.callValue(call),
            .method_call => |call| try self.methodCall(call),
            .arena_escape => |escape| {
                try self.out.text(self.src.text(escape.arena));
                try self.out.text(".escape(");
                try self.expression(escape.value, 0);
                try self.out.text(")");
            },
            .field => |access| {
                try self.expression(access.base, Precedence.call);
                try self.out.text(".");
                try self.out.text(self.src.text(access.name));
            },
            .index => |access| {
                try self.expression(access.base, Precedence.call);
                try self.out.text("[");
                try self.expression(access.index, 0);
                try self.out.text("]");
            },
            .slice => |access| try self.sliceValue(access),
            .length => |base| {
                try self.out.text("len(");
                try self.expression(base, 0);
                try self.out.text(")");
            },
            .unwrap => |base| {
                try self.out.text("unwrap(");
                try self.expression(base, 0);
                try self.out.text(")");
            },
            .replace => |item_replace| {
                try self.out.text("replace(");
                try self.expression(item_replace.base, 0);
                try self.out.text(", ");
                try self.expression(item_replace.index, 0);
                try self.out.text(", ");
                try self.expression(item_replace.value, 0);
                try self.out.text(")");
            },
            .cast => |typedValue| try self.generic("cast", typedValue.ty, typedValue.value),
            .wrap => |typedValue| try self.generic("wrap", typedValue.ty, typedValue.value),
            .propagate => |inner| {
                try self.expression(inner, Precedence.call);
                try self.out.text("?");
            },
            .membership => |test_value| {
                try self.expression(test_value.needle, Precedence.equality);
                try self.out.text(if (test_value.negate) " not in " else " in ");
                try self.expression(test_value.container, Precedence.compare);
            },
            .binary => |binary| try self.binaryValue(item, binary),
            .unary => |unary| try self.unaryValue(unary),
            .field_assignment => |assignment| {
                try self.expression(assignment.target, Precedence.call);
                try self.out.text(" = ");
                try self.expression(assignment.value, 0);
            },
            .list_operation => |write| try self.listOperation(item, write),
            .external_read => |read| try self.generic(if (read.kind == .clock) "clock_now" else "random_u64", read.ty, read.capability),
            .environment_get => |read| try self.environment(read),
            .match_expression => try self.rejectValue(item.span, "a match expression"),
            .array => |literal| try self.sequence(literal.values, "[", "]"),
            .restrict_resource => try self.rejectValue(item.span, "restrict_resource"),
            .acquire_resource => try self.rejectValue(item.span, "acquire_resource"),
            .complete_resource => try self.rejectValue(item.span, "complete_resource"),
            .resource_io => try self.rejectValue(item.span, "resource input or output"),
            .buffer_operation => try self.rejectValue(item.span, self.leadingWord(item.span)),
        }
    }

    fn sequence(self: *Walk, values: []const ast.NodeId, open: []const u8, close: []const u8) Error!void {
        try self.out.text(open);
        for (values, 0..) |entry, index| {
            if (index != 0) try self.out.text(", ");
            try self.expression(entry, 0);
        }
        try self.out.text(close);
    }

    fn dictionary(self: *Walk, entries: []const ast.NodeId) Error!void {
        try self.out.text("{");
        var index: usize = 0;
        while (index + 1 < entries.len) : (index += 2) {
            if (index != 0) try self.out.text(", ");
            try self.expression(entries[index], 0);
            try self.out.text(": ");
            try self.expression(entries[index + 1], 0);
        }
        try self.out.text("}");
    }

    fn byteLiteral(self: *Walk, span: Span) Error!void {
        const text = self.src.text(span);
        if (text.len != 0 and text[0] != 'b') try self.out.text("b");
        try self.out.text(text);
    }

    fn recordLiteral(self: *Walk, literal: @FieldType(@FieldType(ast.Node, "data"), "record")) Error!void {
        const spelled = self.src.text(literal.name);
        if (spelled.len != 0 and spelled[0] == '[') return self.tableLiteral(literal);
        try self.typeName(literal.name);
        try self.out.text("(");
        for (literal.fields, 0..) |field, index| {
            if (index != 0) try self.out.text(", ");
            try self.out.text(self.src.text(field.name));
            try self.out.text("=");
            try self.expression(field.value, 0);
        }
        try self.out.text(")");
    }

    /// `new [Kind]T { case: v }` becomes the dict literal `{Kind.case: v}` the checker accepts.
    fn tableLiteral(self: *Walk, literal: @FieldType(@FieldType(ast.Node, "data"), "record")) Error!void {
        const key = self.tableKey(literal.name) orelse return self.rejectValue(literal.name, "an enum-indexed table literal");
        try self.out.text("{");
        for (literal.fields, 0..) |field, index| {
            if (index != 0) try self.out.text(", ");
            try self.typeName(key);
            try self.out.text(".");
            try self.out.text(self.src.text(field.name));
            try self.out.text(": ");
            try self.expression(field.value, 0);
        }
        try self.out.text("}");
    }

    /// Key enum of an enum-indexed table type spelling, or null for a numeric array.
    fn tableKey(self: *Walk, name: Span) ?Span {
        for (self.syntax.types.expressions.arrays) |array| {
            if (array.span.start != name.start or array.span.end != name.end) continue;
            return if (array.index == .enum_type) array.index.enum_type else null;
        }
        return null;
    }

    /// Payload-free cases keep their qualified spelling; result payloads use Ok/Err.
    fn variantValue(self: *Walk, item: ast.Node, literal: @FieldType(@FieldType(ast.Node, "data"), "variant")) Error!void {
        const payload = literal.value orelse {
            try self.variantTypeName(literal.ty);
            try self.out.text(".");
            try self.out.text(self.src.text(literal.name));
            return;
        };
        if (self.resultCase(literal)) |case| {
            try self.out.text(if (case) "Ok(" else "Err(");
            try self.expression(payload, 0);
            try self.out.text(")");
            return;
        }
        _ = item;
        try self.variantTypeName(literal.ty);
        try self.out.text(".");
        try self.out.text(self.src.text(literal.name));
        try self.out.text("(");
        try self.expression(payload, 0);
        try self.out.text(")");
    }

    /// A generic variant infers its arguments from context, so only its template is named.
    /// `new Slot<Box<i64>>.some(v)` becomes `Slot.some(v)`, which no index expression mimics.
    fn variantTypeName(self: *Walk, span: Span) Error!void {
        const text = self.src.text(span);
        const applied = std.mem.indexOfAny(u8, text, "<[") orelse return self.typeName(span);
        try self.qualified(std.mem.trimEnd(u8, text[0..applied], " \t"));
    }

    /// Report whether a variant construction names the ok or err case of a result type.
    fn resultCase(self: *Walk, literal: @FieldType(@FieldType(ast.Node, "data"), "variant")) ?bool {
        const case = self.src.text(literal.name);
        const ok = std.mem.eql(u8, case, "ok");
        if (!ok and !std.mem.eql(u8, case, "err")) return null;
        if (!self.namesResult(self.src.text(literal.ty))) return null;
        return ok;
    }

    fn namesResult(self: *Walk, named: []const u8) bool {
        if (std.mem.startsWith(u8, named, "Result<") or std.mem.startsWith(u8, named, "Result[")) return true;
        for (self.syntax.types.variants) |item| {
            if (!std.mem.eql(u8, self.src.text(item.name), named)) continue;
            if (!item.fallible or item.cases.len != 2) return false;
            for (item.cases) |case| if (case.payload == null) return false;
            return true;
        }
        for (self.syntax.types.expressions.aliases) |item| {
            if (!std.mem.eql(u8, self.src.text(item.name), named)) continue;
            return self.namesResult(self.src.text(item.target));
        }
        // An imported type is opaque here. Only result shapes declare payload cases
        // named ok and err, and a wrong guess fails the migrated check loudly.
        return std.mem.indexOf(u8, named, "::") != null or std.mem.indexOfScalar(u8, named, '.') != null;
    }

    fn callValue(self: *Walk, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!void {
        const name = self.src.text(call.name);
        const keyword_generic = std.mem.eql(u8, name, "todo") or std.mem.startsWith(u8, name, "codec_");
        if (call.owner) |owner| {
            try self.qualified(self.src.text(owner));
            try self.out.text(".");
        }
        try self.qualified(self.src.text(call.name));
        if (call.type_arguments.len != 0) {
            // `f[T](x)` is the Python spelling; a keyword intrinsic and an owner-qualified
            // call both keep the angle-bracket form, which the Python parser also accepts.
            const square = !keyword_generic and call.owner == null;
            try self.out.text(if (square) "[" else if (keyword_generic) "<" else "::<");
            for (call.type_arguments, 0..) |argument, index| {
                if (index != 0) try self.out.text(", ");
                try self.typeName(argument);
            }
            try self.out.text(if (square) "]" else ">");
        }
        try self.arguments(call.arguments, call.argument_names);
    }

    fn arguments(self: *Walk, values: []const ast.NodeId, names: []const ?Span) Error!void {
        try self.out.text("(");
        for (values, 0..) |entry, index| {
            if (index != 0) try self.out.text(", ");
            if (index < names.len) if (names[index]) |name| {
                try self.out.text(self.src.text(name));
                try self.out.text("=");
            };
            try self.expression(entry, 0);
        }
        try self.out.text(")");
    }

    fn methodCall(self: *Walk, call: @FieldType(@FieldType(ast.Node, "data"), "method_call")) Error!void {
        try self.expression(call.base, Precedence.call);
        try self.out.text(".");
        try self.out.text(self.src.text(call.name));
        try self.arguments(call.arguments, &.{});
    }

    fn sliceValue(self: *Walk, access: @FieldType(@FieldType(ast.Node, "data"), "slice")) Error!void {
        try self.expression(access.base, Precedence.call);
        try self.out.text("[");
        if (access.start) |start| try self.expression(start, 0);
        try self.out.text(":");
        if (access.end) |end| try self.expression(end, 0);
        try self.out.text("]");
    }

    fn generic(self: *Walk, name: []const u8, ty: Span, operand: ast.NodeId) Error!void {
        try self.out.text(name);
        try self.out.text("<");
        try self.typeName(ty);
        try self.out.text(">(");
        try self.expression(operand, 0);
        try self.out.text(")");
    }

    fn environment(self: *Walk, read: @FieldType(@FieldType(ast.Node, "data"), "environment_get")) Error!void {
        try self.out.text("environment_get<");
        try self.typeName(read.ty);
        try self.out.text(">(");
        try self.expression(read.capability, 0);
        try self.out.text(", ");
        try self.expression(read.name, 0);
        try self.out.text(")");
    }

    fn listOperation(self: *Walk, item: ast.Node, write: @FieldType(@FieldType(ast.Node, "data"), "list_operation")) Error!void {
        if (write.kind != .write or write.arguments.len != 2) return self.rejectValue(item.span, "an explicit list operation");
        try self.expression(write.base, Precedence.call);
        try self.out.text("[");
        try self.expression(write.arguments[0], 0);
        try self.out.text("] = ");
        try self.expression(write.arguments[1], 0);
    }

    fn binaryValue(self: *Walk, item: ast.Node, binary: @FieldType(@FieldType(ast.Node, "data"), "binary")) Error!void {
        if (namedOperation(binary.op)) |name| {
            try self.out.text(name);
            try self.out.text("(");
            try self.expression(binary.left, 0);
            try self.out.text(", ");
            try self.expression(binary.right, 0);
            try self.out.text(")");
            return;
        }
        // Legacy `/` and `%` truncate toward zero; Python `//` and `%` floor. They agree on
        // unsigned operands, and the prelude helpers preserve the original rounding otherwise.
        const truncating = binary.op == .div or binary.op == .rem;
        const unsigned = self.unsignedValue(binary.left) or self.unsignedValue(binary.right);
        if (truncating and !unsigned) {
            try self.out.text(if (binary.op == .div) "divtrunc(" else "remtrunc(");
            try self.expression(binary.left, 0);
            try self.out.text(", ");
            try self.expression(binary.right, 0);
            try self.out.text(")");
            return;
        }
        const level = precedenceOf(item);
        try self.expression(binary.left, level);
        try self.out.text(" ");
        try self.out.text(spelling(binary.op));
        try self.out.text(" ");
        try self.expression(binary.right, level + 1);
    }

    fn unaryValue(self: *Walk, unary: @FieldType(@FieldType(ast.Node, "data"), "unary")) Error!void {
        switch (unary.op) {
            .neg => {
                try self.out.text("-");
                try self.expression(unary.operand, Precedence.unary);
            },
            .not => {
                // Python `not` binds looser than every comparison, so a compound
                // operand keeps explicit parentheses rather than relying on that.
                try self.out.text("not ");
                try self.expression(unary.operand, Precedence.call);
            },
            else => {
                try self.out.text(@tagName(unary.op));
                try self.out.text("(");
                try self.expression(unary.operand, 0);
                try self.out.text(")");
            },
        }
    }

    /// Rewrite one qualified name, replacing legacy `::` with Python dots.
    fn qualified(self: *Walk, text: []const u8) Error!void {
        var parts = std.mem.splitSequence(u8, text, "::");
        var first = true;
        while (parts.next()) |part| {
            if (!first) try self.out.text(".");
            try self.out.text(std.mem.trim(u8, part, " \t\r\n"));
            first = false;
        }
    }
};

fn namedOperation(op: ast.BinaryOp) ?[]const u8 {
    return switch (op) {
        .add, .sub, .mul, .div, .rem, .floor_div, .floor_rem, .python_div => null,
        .logical_and, .logical_or, .eq, .ne, .lt, .le, .gt, .ge => null,
        else => @tagName(op),
    };
}

// twin-drift-ok: source spellings for the whole parsed operator set, including
// arithmetic and the Python `and`/`or` words; the C backend maps only comparisons.
fn spelling(op: ast.BinaryOp) []const u8 {
    return switch (op) {
        .add => "+",
        .sub => "-",
        .mul => "*",
        .div, .floor_div => "//",
        .rem, .floor_rem => "%",
        .python_div => "/",
        .logical_and => "and",
        .logical_or => "or",
        .eq => "==",
        .ne => "!=",
        .lt => "<",
        .le => "<=",
        .gt => ">",
        .ge => ">=",
        else => "",
    };
}

fn typeSpace(previous: Tag, current: Tag) bool {
    switch (current) {
        .rbracket, .rparen, .comma, .dot, .lbracket, .lparen, .colon, .gt, .ge, .lt => return false,
        else => {},
    }
    switch (previous) {
        .lbracket, .lparen, .dot, .ampersand, .rbracket, .lt => return false,
        else => {},
    }
    return true;
}
