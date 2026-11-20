//! A type may not be declared under the name of a builtin type. `Unit`, `int` and the other plain-name spellings
//! `typed.Type.fromName` resolves (the integer widths are reserved words, which the parser refuses) are read as the builtin
//! before any declaration is consulted, so a record or enum named `Unit` could be declared and then neither built nor read in its own module (`E_SYMBOL_KIND`, `E_TYPE`). The declaration is
//! refused instead, with the one repair that keeps every program that checked meaning what it meant: rename the type, the
//! qualified references to it from the modules that import it and, when the module itself plainly means the type, its own uses.
const std = @import("std");
const ast = @import("ast.zig");
const diagnostic = @import("diagnostic.zig");
const lexer = @import("lexer.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");
const Names = @import("module_names.zig").Names;

/// The diagnostic code of a type declared under a builtin type's name.
pub const code = "E_BUILTIN_TYPE_NAME";

/// What one refusal reads: the program, the module names when the check sees a project, and the sink it reports to.
const Context = struct {
    allocator: std.mem.Allocator,
    src: source.Source,
    program: ast.Program,
    names: ?*Names,
    sink: *diagnostic.Sink,
};

/// One declared type name and the builtin spelling it takes, with the name the repair gives it.
const Renaming = struct { name: source.Span, old: []const u8, replacement: []const u8 };

/// Refuse every record, enum, union, domain, resource and alias of `program` whose name is a builtin type's. Each refusal is
/// appended with its repair, so one run names every such declaration, and the check then stops: whatever follows would be noise
/// about the same name. The suggested name is never one the declaring module already holds.
pub fn check(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, names: ?*Names, sink: *diagnostic.Sink) diagnostic.Error!void {
    const context: Context = .{ .allocator = allocator, .src = src, .program = program, .names = names, .sink = sink };
    const before = sink.items.items.len;
    for (program.types.records) |declaration| try refuse(context, declaration.name);
    for (program.types.variants) |declaration| try refuse(context, declaration.name);
    for (program.types.domains) |declaration| try refuse(context, declaration.name);
    for (program.types.resources) |declaration| try refuse(context, declaration.name);
    for (program.types.expressions.aliases) |declaration| try refuse(context, declaration.name);
    if (sink.items.items.len != before) return error.SourceError;
}

/// Append the refusal of the type declared at `name` when its spelling is a builtin's.
fn refuse(self: Context, name: source.Span) diagnostic.Error!void {
    const old = self.src.text(name);
    if (old.len == 0 or typed.Type.fromName(old) == null) return;
    const message = try std.fmt.allocPrint(
        self.allocator,
        "`{s}` is the name of a builtin type, so a type declared with it can be neither built nor read in its own module; rename the type",
        .{old},
    );
    const renaming: Renaming = .{ .name = name, .old = old, .replacement = try suggestion(self, name, old) };
    var edits: std.ArrayList(diagnostic.Edit) = .empty;
    try edits.append(self.allocator, .{ .span = name, .text = renaming.replacement });
    // A repair that left a reference behind would change what the program means, so one that cannot name them all is withheld.
    const own = try ownReferences(self, renaming, &edits);
    const qualified = try qualifiedReferences(self, renaming, &edits);
    var item: diagnostic.Diagnostic = .{ .code = code, .span = name, .message = message };
    if (own and qualified) item.provenance.fix = .{ .edit = edits.items[0], .more = edits.items[1..] };
    try self.sink.items.append(self.allocator, item);
}

/// The module's own name and the builtin's, in `PascalCase`: `Unit` in `kicad_sym/shape` becomes `ShapeUnit`. A name a type or a
/// function of the declaring module already holds gets a digit after it.
fn suggestion(self: Context, name: source.Span, old: []const u8) std.mem.Allocator.Error![]const u8 {
    var base: std.ArrayList(u8) = .empty;
    try pascal(self.allocator, &base, moduleStem(self, name));
    try pascal(self.allocator, &base, old);
    var attempt: usize = 1;
    while (true) : (attempt += 1) {
        const candidate = if (attempt == 1) try self.allocator.dupe(u8, base.items) else try std.fmt.allocPrint(self.allocator, "{s}{d}", .{ base.items, attempt });
        if (!declares(self, name, candidate)) return candidate;
    }
}

/// The last segment of the module that writes `name`: the module's name when the check sees a project, the file's stem otherwise.
fn moduleStem(self: Context, name: source.Span) []const u8 {
    if (self.names) |known| if (known.moduleOf(name) catch null) |module| {
        const base = if (std.mem.lastIndexOfScalar(u8, module, '.')) |dot| module[dot + 1 ..] else module;
        if (base.len != 0) return base;
    };
    const file = std.fs.path.basename(self.src.path);
    const base = if (std.mem.lastIndexOfScalar(u8, file, '.')) |dot| file[0..dot] else file;
    return if (base.len == 0) "My" else base;
}

/// Append `text` in `PascalCase`: each `_`-separated word with its first letter raised.
fn pascal(allocator: std.mem.Allocator, out: *std.ArrayList(u8), text: []const u8) std.mem.Allocator.Error!void {
    var raise = true;
    for (text) |byte| {
        if (byte == '_') {
            raise = true;
            continue;
        }
        try out.append(allocator, if (raise) std.ascii.toUpper(byte) else byte);
        raise = false;
    }
}

/// Whether the module that declares `name` already has a top-level declaration called `candidate`.
fn declares(self: Context, name: source.Span, candidate: []const u8) bool {
    if (self.names) |known| if (known.topLevelSpelling(name, candidate) catch true) return true;
    const types = self.program.types;
    for (types.records) |declaration| if (std.mem.eql(u8, self.src.text(declaration.name), candidate)) return true;
    for (types.variants) |declaration| if (std.mem.eql(u8, self.src.text(declaration.name), candidate)) return true;
    for (types.domains) |declaration| if (std.mem.eql(u8, self.src.text(declaration.name), candidate)) return true;
    for (types.resources) |declaration| if (std.mem.eql(u8, self.src.text(declaration.name), candidate)) return true;
    for (types.expressions.aliases) |declaration| if (std.mem.eql(u8, self.src.text(declaration.name), candidate)) return true;
    for (self.program.functions) |function| if (std.mem.eql(u8, self.src.text(function.name), candidate)) return true;
    return false;
}

/// The place and source of the declaring module: its index in the project, or the single source itself.
const Module = struct { index: usize, src: source.Source };

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

/// Append an edit for every bare `old` in the declaring module when the module plainly means its own type by it: a use that the
/// builtin cannot be, `old(field=...)` or `old.case`. A bare `old` there otherwise still means the builtin (the module checked),
/// and renaming it would change the program. False when the module cannot be read or mapped.
fn ownReferences(self: Context, renaming: Renaming, edits: *std.ArrayList(diagnostic.Edit)) diagnostic.Error!bool {
    const module = declaringModule(self, renaming.name) orelse return false;
    var scratch: diagnostic.Sink = .{ .allocator = self.allocator };
    const tokens = lexer.lex(self.allocator, module.src.bytes, &scratch) catch return false;
    var meant = false;
    for (tokens, 0..) |_, at| {
        if (!bare(module.src, tokens, at, renaming.old)) continue;
        const next = tokens[at + 1];
        if (next.tag == .dot) meant = true;
        if (next.tag == .lparen and at + 3 < tokens.len and tokens[at + 2].tag == .ident and tokens[at + 3].tag == .equal) meant = true;
    }
    if (!meant) return true;
    for (tokens, 0..) |token, at| {
        if (!bare(module.src, tokens, at, renaming.old)) continue;
        const place = mapped(self, module.index, token.span) orelse return false;
        if (place.start == renaming.name.start) continue;
        try edits.append(self.allocator, .{ .span = place, .text = renaming.replacement });
    }
    return true;
}

/// Whether token `at` is the identifier `old` written alone, not after a dot (`config.Unit` is a field of something).
fn bare(src: source.Source, tokens: []const lexer.Token, at: usize, old: []const u8) bool {
    if (tokens[at].tag != .ident or !std.mem.eql(u8, src.text(tokens[at].span), old)) return false;
    return at == 0 or tokens[at - 1].tag != .dot;
}

/// Append an edit for every reference to the type written `alias.old` in a module that imports the declaring one. False when a
/// module cannot be read or mapped.
fn qualifiedReferences(self: Context, renaming: Renaming, edits: *std.ArrayList(diagnostic.Edit)) diagnostic.Error!bool {
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
        var scratch: diagnostic.Sink = .{ .allocator = self.allocator };
        const tokens = lexer.lex(self.allocator, module.src.bytes, &scratch) catch return false;
        for (tokens, 0..) |token, at| {
            if (token.tag != .ident or !std.mem.eql(u8, module.src.text(token.span), renaming.old)) continue;
            if (at < 2 or tokens[at - 1].tag != .dot) continue;
            if (!qualifierMatches(module.src, tokens, at - 1, qualifiers.items)) continue;
            const place = mapped(self, index, token.span) orelse return false;
            try edits.append(self.allocator, .{ .span = place, .text = renaming.replacement });
        }
    }
    return true;
}

/// Whether the dotted chain of names that ends just before the dot at `dot` is, whole, one of `qualifiers`. A chain that follows
/// another dot is a field of something (`config.m.Unit`) and is no module path. `builtin_function_names` reads it too.
pub fn qualifierMatches(src: source.Source, tokens: []const lexer.Token, dot: usize, qualifiers: []const []const u8) bool {
    if (dot == 0 or tokens[dot - 1].tag != .ident) return false;
    const end = dot - 1;
    var start = end;
    while (start >= 2 and tokens[start - 1].tag == .dot and tokens[start - 2].tag == .ident) start -= 2;
    if (start >= 1 and tokens[start - 1].tag == .dot) return false;
    const chain: source.Span = .{ .start = tokens[start].span.start, .end = tokens[end].span.end };
    for (qualifiers) |qualifier| if (std.mem.eql(u8, src.text(chain), qualifier)) return true;
    return false;
}
