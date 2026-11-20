//! A bare call of a prelude function's name is always the prelude function. Before this rule a module could declare
//! `func len(n: int) -> int`, and every bare `len(...)` in that module then called it, with no word from the compiler, so a
//! reader could not know what `len(xs)` did without reading the whole module. Such a declaration is now refused
//! (`E_BUILTIN_FUNCTION_NAME`, public or private) when its own module uses the name bare: a call `len(...)` or the function
//! passed as a value. A note points at the first such use. The refusal carries the rename that keeps the program meaning what
//! it meant: the declaration, every bare use in its own module and every qualified use (`shapes.len(...)`) from the modules
//! that import it, withheld when the module also writes the name in a way the rename cannot classify.
//!
//! A bare call whose arguments cannot be the declared function's is the prelude's, and the rename leaves it (FR78): its
//! argument count is outside what the declared parameters take, or an argument whose kind the source writes (a literal, a
//! list literal, or a parameter of the function the call is in) binds by position a parameter declared with another kind of
//! type (a number, text, a `bool`, a `Stream`, a collection). So `flush(out)` with `out: Stream` stays the builtin's beside a
//! declared `func flush(n: int)`. Every call the repair cannot judge this way is renamed, as before. The note then points at
//! the first renamed use. In a module that re-exports the name such a call cannot stay bare, so that repair is withheld.
//!
//! A function its module never uses bare is accepted: a public `write` that other modules call as `zipfile.write(...)`
//! misleads no reader, and nor does a function nothing calls. The prelude is `prelude_names.entries`. The embedded standard
//! library is exempt (`math.abs` is reached by its qualified name and is trusted code), by the same test that admits its
//! internal spellings (`standard_library.trusted`). A local, a parameter, an import, a constant, a field and a type keep their
//! names: they are outside this rule.
//!
//! A re-export is a declaration too: `export helpers.sum` makes a bare `sum(...)` in the re-exporting module call
//! `helpers.sum`, and `export math.abs` makes a bare `abs(...)` call the standard library's `math.abs`. The same test refuses
//! it at the `export` line (`E_BUILTIN_FUNCTION_NAME`), and its repair writes each bare use qualified (`helpers.sum(...)`),
//! which is what it called. A re-export of `len`, `copy`, `str` or `bytes` is left alone: a bare call of one of those is
//! the builtin whatever the module re-exports.
const std = @import("std");
const ast = @import("ast.zig");
const diagnostic = @import("diagnostic.zig");
const format_strings = @import("format_strings.zig");
const lexer = @import("lexer.zig");
const prelude_names = @import("prelude_names.zig");
const source = @import("source.zig");
const standard_library = @import("standard_library.zig");
const builtin_type_names = @import("builtin_type_names.zig");
const Names = @import("module_names.zig").Names;

/// The diagnostic code of a module function that has a prelude function's name and that its own module uses bare.
pub const code = "E_BUILTIN_FUNCTION_NAME";

/// What one refusal reads: the program, the module names when the check sees a project, and the sink it reports to.
const Context = struct {
    allocator: std.mem.Allocator,
    src: source.Source,
    program: ast.Program,
    names: ?*Names,
    sink: *diagnostic.Sink,
};

/// One declared function name and the prelude spelling it takes. An `extern func` takes its C symbol from its name, so it is
/// never renamed. `signature` is the declared function's, when it is known: a bare call whose arguments cannot be its own is the
/// prelude function's, and the repair leaves it.
const Renaming = struct { name: source.Span, old: []const u8, external: bool = false, signature: ?ast.FunctionSignature = null };

/// The place and source of the declaring module: its index in the project, or the single source itself.
const Module = struct { index: usize, src: source.Source };

/// What the declaring module writes under the declared name: its first bare use (a call or a function value), the first use
/// the rename cannot classify, an edit for every bare use that may be the function, and every bare call whose arguments cannot
/// be its own (`kept`, the prelude function's). Spans are in the merged source's coordinates.
const Scan = struct {
    bare: ?source.Span = null,
    unclassified: ?source.Span = null,
    uses: std.ArrayList(source.Span) = .empty,
    kept: std.ArrayList(source.Span) = .empty,
    /// False when the module could not be read or one of its spans could not be mapped.
    complete: bool = true,
};

/// Refuse every free function of `program` written in user code whose name is a prelude function's and that its own
/// module uses bare. Each refusal is appended with its repair, so one run names every such declaration, and the check then
/// stops: whatever follows would be noise about the same name.
pub fn check(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, names: ?*Names, sink: *diagnostic.Sink) diagnostic.Error!void {
    const context: Context = .{ .allocator = allocator, .src = src, .program = program, .names = names, .sink = sink };
    const before = sink.items.items.len;
    var seen: std.AutoHashMapUnmanaged(usize, void) = .empty;
    for (program.functions) |function| {
        if (function.policy.constant or function.policy.owner != null) continue;
        const old = src.text(function.name);
        if (!prelude_names.isPrelude(old)) continue;
        if (trusted(context, function.name)) continue;
        const entry = try seen.getOrPut(allocator, function.name.start);
        if (entry.found_existing) continue;
        try refuse(context, .{ .name = function.name, .old = old, .external = function.policy.c_abi, .signature = function.signature });
    }
    if (names) |known| try reexports(context, known);
    if (sink.items.items.len != before) return error.SourceError;
}

/// The prelude names a re-export does not capture: a bare call of one is the builtin even in a module that re-exports a
/// function of that name (`len` is decided by the parser from the file's own declarations; `copy`, `str` and `bytes` by
/// the checker before it consults the module's names).
const uncaptured = [_][]const u8{ "bytes", "copy", "len", "str" };

fn captured(name: []const u8) bool {
    for (uncaptured) |spelling| if (std.mem.eql(u8, spelling, name)) return false;
    return true;
}

/// Refuse every `export module.NAME` of a user module in this program whose NAME is a prelude function's, a bare call of
/// which the re-export captures, and that the module uses bare.
fn reexports(self: Context, known: *Names) diagnostic.Error!void {
    for (known.index.project.modules.items, 0..) |module, index| {
        if (standard_library.trusted(module.src.path, module.src.bytes, module.src.trusted_intrinsics)) continue;
        for (module.exports) |exported| {
            const qualifier = exported.alias orelse continue;
            if (!prelude_names.isPrelude(exported.name) or !captured(exported.name)) continue;
            // A module that is not part of this program has no place in its source; another check reports it.
            const place = known.src.mappedSpan(index, exported.span) catch continue;
            const signature = exportedSignature(self, module.imports, qualifier, exported.name);
            try refuseReexport(self, .{ .index = index, .src = module.src }, place, exported.name, qualifier, signature);
        }
    }
}

/// The signature of the function `qualifier.old` that a module re-exports, when this program declares it.
fn exportedSignature(self: Context, imports: []const @import("project.zig").Import, qualifier: []const u8, old: []const u8) ?ast.FunctionSignature {
    const target = for (imports) |imported| {
        if (std.mem.eql(u8, imported.alias, qualifier)) break imported.target;
    } else return null;
    for (self.program.functions) |function| {
        if (function.policy.constant or function.policy.owner != null or !std.mem.eql(u8, self.src.text(function.name), old)) continue;
        const at = declaringModule(self, function.name) orelse continue;
        if (at.index == target) return function.signature;
    }
    return null;
}

/// Append the refusal of the re-export at `place` when its module uses `old` bare, with the repair that qualifies each use.
/// A bare call whose arguments cannot be the re-exported function's is the prelude's, which a module that re-exports `old`
/// cannot call bare, so the repair is then withheld.
fn refuseReexport(self: Context, module: Module, place: source.Span, old: []const u8, qualifier: []const u8, signature: ?ast.FunctionSignature) diagnostic.Error!void {
    const tokens = try moduleTokens(self.allocator, module.src);
    const scan = try ownUses(self, .{ .name = place, .old = old, .signature = signature }, module, tokens);
    const first = scan.bare orelse return;
    const written = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ qualifier, old });
    const reason = if (scan.unclassified) |other| reason: {
        const at = self.src.locate(other.start);
        break :reason try std.fmt.allocPrint(
            self.allocator,
            "; writing the uses as `{s}` is not offered because `{s}` is also written at {s}:{d} as a name the repair cannot tell from the function (a parameter, a local or a field)",
            .{ written, old, at.path, at.line },
        );
    } else if (!scan.complete)
        try std.fmt.allocPrint(self.allocator, "; writing the uses as `{s}` is not offered because the module could not be read", .{written})
    else if (scan.kept.items.len != 0) reason: {
        const at = self.src.locate(scan.kept.items[0].start);
        break :reason try std.fmt.allocPrint(
            self.allocator,
            "; writing the uses as `{s}` is not offered because the bare call at {s}:{d}:{d} has arguments `{s}` cannot take, so it is the prelude's `{s}`, which this module cannot call bare while it re-exports `{s}`",
            .{ written, at.path, at.line, at.column, written, old, old },
        );
    } else try std.fmt.allocPrint(self.allocator, " (`selka fix` writes each bare use as `{s}`)", .{written});
    const message = try std.fmt.allocPrint(
        self.allocator,
        "`{s}` is a prelude function, and a bare `{s}` in this module reads as the builtin but would mean the re-exported `{s}`; write those uses as `{s}`{s}",
        .{ old, old, written, written, reason },
    );
    const note = try std.fmt.allocPrint(self.allocator, "this bare `{s}` reads as the prelude's `{s}`", .{ old, old });
    var item: diagnostic.Diagnostic = .{ .code = code, .span = place, .message = message, .related = .{ .span = first, .message = note } };
    if (scan.complete and scan.unclassified == null and scan.kept.items.len == 0) {
        var edits: std.ArrayList(diagnostic.Edit) = .empty;
        for (scan.uses.items) |use| try edits.append(self.allocator, .{ .span = use, .text = written });
        item.provenance.fix = .{ .edit = edits.items[0], .more = edits.items[1..] };
    }
    try self.sink.items.append(self.allocator, item);
}

/// Whether the module that declares `name` is the embedded standard library (or a source granted its trust).
fn trusted(self: Context, name: source.Span) bool {
    if (self.src.trusted_intrinsics or standard_library.trusted(self.src.path, self.src.bytes, false)) return true;
    if (self.src.origins.len == 0) return false;
    const original = self.src.originalSpan(name) catch return false;
    const unit = self.src.origins[original.input].original;
    return standard_library.trusted(unit.path, unit.bytes, unit.trusted_intrinsics);
}

/// Append the refusal of the function declared at `renaming.name` when its module uses the name bare, with the rename when
/// every reference to it can be named.
fn refuse(self: Context, renaming: Renaming) diagnostic.Error!void {
    const module = declaringModule(self, renaming.name) orelse return;
    const tokens = try moduleTokens(self.allocator, module.src);
    const scan = try ownUses(self, renaming, module, tokens);
    const first = scan.bare orelse return;
    const replacement = try suggestion(self, renaming, module, tokens);
    var edits: std.ArrayList(diagnostic.Edit) = .empty;
    try edits.append(self.allocator, .{ .span = renaming.name, .text = replacement });
    for (scan.uses.items) |use| try edits.append(self.allocator, .{ .span = use, .text = replacement });
    // A repair that left a reference behind would change what the program means, so one that cannot name them all is withheld.
    const unseen = unseenCallers(self, renaming.name, module);
    const qualified = scan.complete and scan.unclassified == null and !unseen and try qualifiedReferences(self, renaming, replacement, &edits);
    const reason = if (renaming.external)
        try std.fmt.allocPrint(
            self.allocator,
            "; an `extern func` takes its C symbol from its name, so no rename is offered: declare it in a module of its own and call it as `module.{s}(...)`",
            .{renaming.old},
        )
    else if (scan.unclassified) |other| reason: {
        const at = self.src.locate(other.start);
        break :reason try std.fmt.allocPrint(
            self.allocator,
            "; the rename to `{s}` is not offered because `{s}` is also written at {s}:{d} as a name the rename cannot tell from this function (a parameter, a local or a field)",
            .{ replacement, renaming.old, at.path, at.line },
        );
    } else if (unseen)
        try std.fmt.allocPrint(
            self.allocator,
            "; the rename to `{s}` is not offered here because this module is checked alone and the modules that call it as `module.{s}(...)` are not in view: run `selka fix` on the program that imports it",
            .{ replacement, renaming.old },
        )
    else if (!qualified)
        try std.fmt.allocPrint(self.allocator, "; the rename to `{s}` is not offered because a module that may call it could not be read", .{replacement})
    else
        try offered(self, renaming.old, replacement, scan.kept.items);
    const message = try std.fmt.allocPrint(
        self.allocator,
        "`{s}` is a prelude function, and a bare `{s}` in this module reads as the builtin but would mean this function; rename the function{s}",
        .{ renaming.old, renaming.old, reason },
    );
    // With a call left to the prelude, the note points at the first use the rename follows, or says that none is renamed.
    const kept = scan.kept.items.len != 0;
    const pointed = if (kept and scan.uses.items.len != 0) scan.uses.items[0] else first;
    const note = if (!kept)
        try std.fmt.allocPrint(self.allocator, "this bare `{s}` reads as the prelude's `{s}`", .{ renaming.old, renaming.old })
    else if (scan.uses.items.len != 0)
        try std.fmt.allocPrint(self.allocator, "this bare `{s}` reads as the prelude's `{s}`, and its arguments may be this function's, so the rename follows it", .{ renaming.old, renaming.old })
    else
        try std.fmt.allocPrint(self.allocator, "this bare `{s}` is the prelude's `{s}`: its arguments cannot be this function's, so the rename leaves it", .{ renaming.old, renaming.old });
    var item: diagnostic.Diagnostic = .{ .code = code, .span = renaming.name, .message = message, .related = .{ .span = pointed, .message = note } };
    if (qualified and !renaming.external) item.provenance.fix = .{ .edit = edits.items[0], .more = edits.items[1..] };
    try self.sink.items.append(self.allocator, item);
}

/// The offered rename, in the message: every use, or every use but the bare calls `kept`, whose arguments cannot be the
/// function's and which stay the prelude's.
fn offered(self: Context, old: []const u8, replacement: []const u8, kept: []const source.Span) diagnostic.Error![]const u8 {
    if (kept.len == 0) return std.fmt.allocPrint(self.allocator, " (`selka fix` renames it `{s}` with every use)", .{replacement});
    const at = self.src.locate(kept[0].start);
    if (kept.len == 1) return std.fmt.allocPrint(
        self.allocator,
        " (`selka fix` renames it `{s}` with every use but the bare call at {s}:{d}:{d}, whose arguments cannot be this function's: it stays the prelude's `{s}`)",
        .{ replacement, at.path, at.line, at.column, old },
    );
    return std.fmt.allocPrint(
        self.allocator,
        " (`selka fix` renames it `{s}` with every use but the {d} bare calls whose arguments cannot be this function's, the first at {s}:{d}:{d}: they stay the prelude's `{s}`)",
        .{ replacement, kept.len, at.path, at.line, at.column, old },
    );
}

/// Whether a public function's qualified callers may be out of view: its module is checked as a library on its own (no
/// module of this check imports it, and it declares no `main`), so another program may call it as `module.old(...)` and a
/// rename here would leave those calls behind.
fn unseenCallers(self: Context, name: source.Span, module: Module) bool {
    if (!ast.isPublicDeclaration(self.program, name)) return false;
    for (self.program.functions) |function| {
        if (!std.mem.eql(u8, self.src.text(function.name), "main")) continue;
        const at = declaringModule(self, function.name) orelse continue;
        if (at.index == module.index) return false;
    }
    const known = self.names orelse return true;
    for (known.index.project.modules.items) |other| {
        for (other.imports) |imported| if (imported.target == module.index) return false;
    }
    return true;
}

/// The last segment of the declaring module's name (the file's stem for a single file), then `_` and the prelude name:
/// `len` in `shapes/outline` becomes `outline_len`. A byte that cannot be in a name becomes `_`, and a stem that does not
/// start with a letter is written after `my_`. A spelling the declaring module already writes anywhere, as any name, gets a
/// digit after it (`outline_len2`), so the new name captures nothing and nothing captures it.
fn suggestion(self: Context, renaming: Renaming, module: Module, tokens: []const lexer.Token) diagnostic.Error![]const u8 {
    var base: std.ArrayList(u8) = .empty;
    const stem = moduleStem(self, renaming.name);
    if (stem.len == 0 or !std.ascii.isAlphabetic(stem[0])) try base.appendSlice(self.allocator, "my_");
    for (stem) |byte| try base.append(self.allocator, if (std.ascii.isAlphanumeric(byte) or byte == '_') byte else '_');
    try base.append(self.allocator, '_');
    try base.appendSlice(self.allocator, renaming.old);
    var attempt: usize = 1;
    while (true) : (attempt += 1) {
        const candidate = if (attempt == 1) try self.allocator.dupe(u8, base.items) else try std.fmt.allocPrint(self.allocator, "{s}{d}", .{ base.items, attempt });
        if (!taken(self, renaming.name, candidate, module, tokens)) return candidate;
    }
}

/// Whether `candidate` is a prelude name, a top-level name or an import of the declaring module, or any name its source writes.
fn taken(self: Context, name: source.Span, candidate: []const u8, module: Module, tokens: []const lexer.Token) bool {
    if (prelude_names.isPrelude(candidate)) return true;
    if (self.names) |known| if (known.topLevelSpelling(name, candidate) catch true) return true;
    for (tokens) |token| if (token.tag == .ident and std.mem.eql(u8, module.src.text(token.span), candidate)) return true;
    return false;
}

/// The last segment of the module that writes `name`: the module's name when the check sees a project, the file's stem otherwise.
fn moduleStem(self: Context, name: source.Span) []const u8 {
    if (self.names) |known| if (known.moduleOf(name) catch null) |module| {
        const base = if (std.mem.lastIndexOfScalar(u8, module, '.')) |dot| module[dot + 1 ..] else module;
        if (base.len != 0) return base;
    };
    const file = std.fs.path.basename(self.src.path);
    return if (std.mem.lastIndexOfScalar(u8, file, '.')) |dot| file[0..dot] else file;
}

fn declaringModule(self: Context, name: source.Span) ?Module {
    const known = self.names orelse return .{ .index = 0, .src = self.src };
    const original = known.src.originalSpan(name) catch return null;
    return .{ .index = original.input, .src = known.index.project.modules.items[original.input].src };
}

/// A token span of module `module`, in the coordinates the diagnostic's edits use.
fn mapped(self: Context, module: usize, span: source.Span) ?source.Span {
    const known = self.names orelse return span;
    return known.src.mappedSpan(module, span) catch null;
}

/// Every token of `src`, with the tokens of each `f"..."` interpolation after the literal's own token, so a call written
/// inside a hole is found like any other. Empty when the source does not lex.
fn moduleTokens(allocator: std.mem.Allocator, src: source.Source) diagnostic.Error![]const lexer.Token {
    var scratch: diagnostic.Sink = .{ .allocator = allocator };
    const tokens = lexer.lex(allocator, src.bytes, &scratch) catch |err| return if (err == error.OutOfMemory) err else &.{};
    var all: std.ArrayList(lexer.Token) = .empty;
    try appendExpanded(allocator, src, tokens, &all, &scratch);
    return all.toOwnedSlice(allocator);
}

fn appendExpanded(allocator: std.mem.Allocator, src: source.Source, tokens: []const lexer.Token, all: *std.ArrayList(lexer.Token), scratch: *diagnostic.Sink) diagnostic.Error!void {
    for (tokens) |token| {
        try all.append(allocator, token);
        if (token.tag != .format) continue;
        const pieces = format_strings.split(allocator, src, token.span, scratch) catch |err| if (err == error.OutOfMemory) return err else continue;
        for (pieces) |piece| if (piece == .hole) {
            const inner = lexer.lexRange(allocator, src.bytes, piece.hole, scratch) catch |err| if (err == error.OutOfMemory) return err else continue;
            // A hole's own token list ends at its end of input; a separator on each side keeps it apart from its neighbours.
            const body = if (inner.len != 0 and inner[inner.len - 1].tag == .eof) inner[0 .. inner.len - 1] else inner;
            try all.append(allocator, .{ .tag = .semicolon, .span = piece.hole });
            try appendExpanded(allocator, src, body, all, scratch);
            try all.append(allocator, .{ .tag = .semicolon, .span = piece.hole });
        };
    }
}

/// Whether token `at` is the identifier `old` written alone, not after a dot (`shape.len` is a field of something).
fn bare(src: source.Source, tokens: []const lexer.Token, at: usize, old: []const u8) bool {
    if (tokens[at].tag != .ident or !std.mem.eql(u8, src.text(tokens[at].span), old)) return false;
    return at == 0 or tokens[at - 1].tag != .dot;
}

/// Whether the bare name at `at` is called: `old(...)`, or a generic call `old[T](...)`.
fn called(tokens: []const lexer.Token, at: usize) bool {
    if (at + 1 >= tokens.len) return false;
    if (tokens[at + 1].tag == .lparen) return true;
    if (tokens[at + 1].tag != .lbracket) return false;
    var depth: usize = 0;
    for (tokens[at + 1 ..], at + 1..) |token, index| {
        if (token.tag == .lbracket) depth += 1;
        if (token.tag == .rbracket) {
            depth -= 1;
            if (depth == 0) return index + 1 < tokens.len and tokens[index + 1].tag == .lparen;
        }
    }
    return false;
}

/// Whether the bare name at `at` is written where a name is bound or a binding is named: a parameter or field (`old:`), a
/// local or a named argument (`old = `, `const old`, `mut old`), a loop or `as` binding, or an `own` marker on a local.
fn binding(src: source.Source, tokens: []const lexer.Token, at: usize) bool {
    if (at + 1 < tokens.len and (tokens[at + 1].tag == .colon or tokens[at + 1].tag == .equal)) return true;
    if (at == 0) return false;
    const previous = tokens[at - 1];
    if (previous.tag == .kw_const or previous.tag == .kw_for or previous.tag == .kw_as) return true;
    if (previous.tag != .ident) return false;
    const word = src.text(previous.span);
    return std.mem.eql(u8, word, "mut") or std.mem.eql(u8, word, "own");
}

/// The prelude functions whose names are also builtin type spellings (`-> bytes`, `xs: list[int]`). Only a call of one of
/// these is a bare use: any other bare spelling is read as the type, and the rename leaves it alone.
const type_spellings = [_][]const u8{ "bool", "bytes", "dict", "float", "int", "list", "set", "str" };

comptime {
    for (type_spellings) |name| if (!prelude_names.isPrelude(name)) @compileError("not a prelude name: " ++ name);
}

fn typeSpelling(name: []const u8) bool {
    for (type_spellings) |spelling| if (std.mem.eql(u8, spelling, name)) return true;
    return false;
}

/// The kinds of value the repair tells apart from the source alone: an argument of one kind cannot bind a parameter whose
/// declared type is of another.
const Kind = enum { number, text, boolean, stream, collection };

/// The kind a declared type spelling names, or null when it may name several (a generic, an option, a record, an alias).
fn spelledKind(spelling: []const u8) ?Kind {
    const text = std.mem.trim(u8, spelling, " \t");
    if (text.len != 0 and text[text.len - 1] == ']') return .collection;
    const numbers = [_][]const u8{ "int", "float", "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64" };
    for (numbers) |name| if (std.mem.eql(u8, text, name)) return .number;
    if (std.mem.eql(u8, text, "str") or std.mem.eql(u8, text, "bytes")) return .text;
    if (std.mem.eql(u8, text, "bool")) return .boolean;
    if (std.mem.eql(u8, text, "Stream")) return .stream;
    return null;
}

/// Whether the bare call at `at` may call the declared function. It cannot when its argument count is outside what the
/// declared parameters take, or when an argument whose kind the source writes (`argumentKind`) binds by position a
/// parameter declared with another kind. A call the repair cannot judge may.
fn mayCall(self: Context, signature: ast.FunctionSignature, module: Module, tokens: []const lexer.Token, at: usize, place: source.Span) bool {
    var open = at + 1;
    if (tokens[open].tag == .lbracket) open = closing(tokens, open) orelse return true;
    while (open < tokens.len and tokens[open].tag != .lparen) open += 1;
    const parameters = signature.parameters;
    const positional = signature.keyword_only_from orelse parameters.len;
    var required: usize = 0;
    for (parameters) |parameter| required += @intFromBool(parameter.default_value == null);
    var count: usize = 0;
    var start = open + 1;
    var depth: usize = 0;
    var index = open + 1;
    while (index < tokens.len) : (index += 1) {
        const tag = tokens[index].tag;
        if (tag == .lparen or tag == .lbracket or tag == .lbrace) depth += 1;
        const ends = depth == 0 and (tag == .comma or tag == .rparen or tag == .rbracket or tag == .rbrace);
        if (!ends) {
            if (tag == .rparen or tag == .rbracket or tag == .rbrace) depth -= 1;
            continue;
        }
        if (index > start) {
            const named = tokens[start].tag == .ident and start + 1 < index and tokens[start + 1].tag == .equal;
            if (!named and count < positional and count < parameters.len) {
                const wanted = spelledKind(self.src.text(parameters[count].ty));
                const found = argumentKind(self, module, tokens, .{ start, index }, place);
                if (wanted != null and found != null and wanted.? != found.?) return false;
            }
            count += 1;
        }
        if (tag != .comma) return count <= parameters.len and count >= required;
        start = index + 1;
    }
    return true;
}

/// The index of the bracket that closes the one at `open`.
fn closing(tokens: []const lexer.Token, open: usize) ?usize {
    var depth: usize = 0;
    for (tokens[open..], open..) |token, index| {
        if (token.tag == .lparen or token.tag == .lbracket or token.tag == .lbrace) depth += 1;
        if (token.tag == .rparen or token.tag == .rbracket or token.tag == .rbrace) {
            depth -= 1;
            if (depth == 0) return index;
        }
    }
    return null;
}

/// The kind of the argument `tokens[range[0]..range[1]]` when the source writes it: a literal, a negative number, a list
/// literal, or a parameter of the function the call is in (`parameterType`).
fn argumentKind(self: Context, module: Module, tokens: []const lexer.Token, range: [2]usize, place: source.Span) ?Kind {
    const first = tokens[range[0]];
    const length = range[1] - range[0];
    if (length == 2 and first.tag == .minus and tokens[range[0] + 1].tag == .integer) return .number;
    if (first.tag == .lbracket and closing(tokens, range[0]) == range[1] - 1) return .collection;
    if (length != 1) return null;
    return switch (first.tag) {
        .integer => .number,
        .bytes, .format => .text,
        .kw_true, .kw_false => .boolean,
        .ident => spelledKind(parameterType(self, module, tokens, module.src.text(first.span), place) orelse return null),
        else => null,
    };
}

/// The declared type of parameter `name` of the function whose body holds `place` (the last declaration before it), when
/// the module writes `name` nowhere else as a binding: no local, loop or `as` binding, and no field or parameter beyond the
/// declared functions' parameters of that name.
fn parameterType(self: Context, module: Module, tokens: []const lexer.Token, name: []const u8, place: source.Span) ?[]const u8 {
    var nearest: ?ast.Function = null;
    var declared: usize = 0;
    for (self.program.functions) |function| {
        const at = declaringModule(self, function.name) orelse return null;
        if (at.index != module.index) continue;
        for (function.signature.parameters) |parameter| declared += @intFromBool(std.mem.eql(u8, self.src.text(parameter.name), name));
        if (function.name.start > place.start) continue;
        if (nearest) |seen| if (seen.name.start >= function.name.start) continue;
        nearest = function;
    }
    const function = nearest orelse return null;
    if (function.policy.constant) return null;
    var written: usize = 0;
    for (tokens, 0..) |_, index| {
        if (!bare(module.src, tokens, index, name)) continue;
        if (index + 1 < tokens.len and tokens[index + 1].tag == .colon) {
            written += 1;
        } else if (binding(module.src, tokens, index)) return null;
    }
    if (written != declared) return null;
    for (function.signature.parameters) |parameter| {
        if (std.mem.eql(u8, self.src.text(parameter.name), name)) return self.src.text(parameter.ty);
    }
    return null;
}

/// Classify every bare `old` of the declaring module other than the declaration itself. A call is a bare use. A name in a
/// binding position is not a use of the function, but the rename cannot tell it from one, so it withholds the repair. Any
/// other bare reference is the function passed as a value when the module binds no name `old`, and is unclassified when it
/// does (it may read that binding). A name that is also a type spelling counts only its calls.
fn ownUses(self: Context, renaming: Renaming, module: Module, tokens: []const lexer.Token) diagnostic.Error!Scan {
    var scan: Scan = .{};
    if (tokens.len == 0) return .{ .complete = false };
    const types = typeSpelling(renaming.old);
    var binds = false;
    for (tokens, 0..) |_, at| {
        if (bare(module.src, tokens, at, renaming.old) and !called(tokens, at) and binding(module.src, tokens, at)) binds = true;
    }
    for (tokens, 0..) |token, at| {
        if (!bare(module.src, tokens, at, renaming.old)) continue;
        const place = mapped(self, module.index, token.span) orelse return .{ .complete = false };
        if (place.start == renaming.name.start) continue;
        if (types and !called(tokens, at)) continue;
        if (renaming.signature) |signature| if (called(tokens, at) and !mayCall(self, signature, module, tokens, at, place)) {
            if (scan.bare == null) scan.bare = place;
            try scan.kept.append(self.allocator, place);
            continue;
        };
        const use = called(tokens, at) or (!binding(module.src, tokens, at) and !binds);
        if (!use) {
            if (scan.unclassified == null) scan.unclassified = place;
            continue;
        }
        if (scan.bare == null) scan.bare = place;
        try scan.uses.append(self.allocator, place);
    }
    return scan;
}

/// Append an edit for every reference written `alias.old` in a module that imports the declaring one. False when a module
/// cannot be read or mapped.
// twin-drift-ok: unlike the type rename in `builtin_type_names`, a call can sit inside an f-string hole, so this one reads
// `moduleTokens` (holes expanded) and takes the replacement apart from the renaming.
fn qualifiedReferences(self: Context, renaming: Renaming, replacement: []const u8, edits: *std.ArrayList(diagnostic.Edit)) diagnostic.Error!bool {
    const known = self.names orelse return true;
    const declaring = (known.src.originalSpan(renaming.name) catch return false).input;
    for (known.index.project.modules.items, 0..) |module, index| {
        if (index == declaring) continue;
        var qualifiers: std.ArrayList([]const u8) = .empty;
        for (module.imports) |imported| if (imported.target == declaring) {
            try qualifiers.append(self.allocator, imported.alias);
            try qualifiers.append(self.allocator, imported.name);
        };
        if (qualifiers.items.len == 0) continue;
        const tokens = try moduleTokens(self.allocator, module.src);
        if (tokens.len == 0) return false;
        for (tokens, 0..) |token, at| {
            if (token.tag != .ident or !std.mem.eql(u8, module.src.text(token.span), renaming.old)) continue;
            if (at < 2 or tokens[at - 1].tag != .dot) continue;
            if (!builtin_type_names.qualifierMatches(module.src, tokens, at - 1, qualifiers.items)) continue;
            const place = mapped(self, index, token.span) orelse return false;
            try edits.append(self.allocator, .{ .span = place, .text = replacement });
        }
    }
    return true;
}
