//! Parse-only top-level declaration listing with original byte ranges.
//! Kinds and names come from the parser's own declaration tables; this module
//! adds only the source extents the parser does not retain.
const std = @import("std");
const ast = @import("ast.zig");
const lex = @import("lexer.zig");
const parser = @import("parser.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");

/// Failures returned by render; callers must handle these boundary errors.
pub const Error = frontend_runtime.Error;
const frontend_runtime = @import("frontend_runtime.zig");

/// Stable lowercase kind names for every top-level construct the parser accepts.
pub const Kind = enum {
    alias,
    @"const",
    @"struct",
    @"enum",
    @"union",
    result,
    domain,
    resource,
    @"fn",
    host_fn,
    extern_fn,
    constraint,
};

/// Zero-based half-open byte range over the original file bytes.
const Bytes = struct { start: usize, end: usize };
/// Imported module name, explicit alias and the bytes of its import statement.
const Import = struct { name: []const u8, alias: ?[]const u8, bytes: Bytes };
/// Exported name with the bytes of its export statement and its name location.
/// A re-export (`export shared.units.Distance`) records `name` as the final
/// member and `alias` as the imported module qualifier; a plain directive
/// leaves `alias` null.
const Exported = struct {
    name: []const u8,
    bytes: Bytes,
    span: source.Span,
    alias: ?[]const u8 = null,

    /// Keep the declarations-v1 export record to its name and statement bytes;
    /// a re-export adds its module qualifier so the listing reports the facade.
    pub fn jsonStringify(self: Exported, writer: anytype) !void {
        if (self.alias) |alias| {
            try writer.write(.{ .name = self.name, .bytes = self.bytes, .alias = alias });
            return;
        }
        try writer.write(.{ .name = self.name, .bytes = self.bytes });
    }
};
/// One listed attribute with its optional string payloads.
const ListedAttribute = struct {
    name: []const u8,
    argument: ?[]const u8 = null,
    reason: ?[]const u8 = null,

    /// Emit only the payloads this attribute actually carries, so a listing
    /// without attributes keeps its existing field set.
    pub fn jsonStringify(self: ListedAttribute, writer: anytype) !void {
        if (self.argument) |argument| {
            if (self.reason) |reason| {
                try writer.write(.{ .name = self.name, .argument = argument, .reason = reason });
                return;
            }
            try writer.write(.{ .name = self.name, .argument = argument });
            return;
        }
        try writer.write(.{ .name = self.name });
    }
};
/// One listed declaration with its attached comment start and declaration bytes.
const Listed = struct {
    kind: []const u8,
    name: []const u8,
    exported: bool,
    bytes: Bytes,
    comment_start: usize,
    attributes: []const ListedAttribute = &.{},

    /// Report the attribute list only when the declaration carries one.
    pub fn jsonStringify(self: Listed, writer: anytype) !void {
        if (self.attributes.len != 0) {
            try writer.write(.{ .kind = self.kind, .name = self.name, .exported = self.exported, .bytes = self.bytes, .comment_start = self.comment_start, .attributes = self.attributes });
            return;
        }
        try writer.write(.{ .kind = self.kind, .name = self.name, .exported = self.exported, .bytes = self.bytes, .comment_start = self.comment_start });
    }
};

/// Strip the quote characters around one string-literal span for reporting.
fn literalText(bytes: []const u8, span: source.Span) []const u8 {
    const text = bytes[span.start..span.end];
    if (text.len >= 2 and (text[0] == '"' or text[0] == '\'')) return text[1 .. text.len - 1];
    return text;
}

/// Project one declaration's parser attributes into the listing shape.
fn listAttributes(work: std.mem.Allocator, src: source.Source, syntax: ast.Program, declaration: source.Span) std.mem.Allocator.Error![]const ListedAttribute {
    const attributes = ast.attributesOf(syntax, declaration);
    if (attributes.len == 0) return &.{};
    const listed = try work.alloc(ListedAttribute, attributes.len);
    for (attributes, listed) |attribute, *out| out.* = .{
        .name = @tagName(attribute.kind),
        .argument = if (attribute.argument) |argument| literalText(src.bytes, argument) else null,
        .reason = if (attribute.reason) |reason| literalText(src.bytes, reason) else null,
    };
    return listed;
}

fn hasExportDirective(bytes: []const u8) bool {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "export ")) return true;
    }
    return false;
}

/// Parse one file and allocate its declarations-v1 listing with the caller's allocator.
pub fn render(allocator: std.mem.Allocator, arena: *std.heap.ArenaAllocator, src: source.Source, tokens: []const lex.Token, sink: *diagnostic.Sink) Error![]u8 {
    return renderUsing(allocator, arena, src, tokens, sink, null);
}

/// Declaration rendering through an explicit verified syntax boundary.
pub fn renderUsing(allocator: std.mem.Allocator, arena: *std.heap.ArenaAllocator, src: source.Source, tokens: []const lex.Token, sink: *diagnostic.Sink, runtime: ?frontend_runtime.Runtime) Error![]u8 {
    _ = try frontend_runtime.verify(arena.allocator(), runtime);
    var scan: Scan = .{ .src = src, .tokens = tokens };
    const module_file = @import("module_syntax.zig").usesModuleSyntax(src.bytes) or hasExportDirective(src.bytes);
    var syntax_parser: parser.Parser = .{ .src = src, .storage = arena.allocator(), .tokens = tokens, .sink = sink };
    const syntax = try frontend_runtime.parse(&syntax_parser, module_file, runtime);
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    const work = scratch.allocator();
    var imports: std.ArrayList(Import) = .empty;
    var exports: std.ArrayList(Exported) = .empty;
    var listed: std.ArrayList(Listed) = .empty;
    var tally: Tally = .{ .syntax = syntax };
    const module_name: ?[]const u8 = if (module_file) std.fs.path.stem(src.path) else null;
    if (module_file) try scan.imports(work, &imports, src);
    // A leading string statement is the module's docstring, not a declaration.
    if (scan.tokens[scan.pos].tag == .bytes) scan.pos += 1;
    while (scan.tokens[scan.pos].tag != .eof) {
        if (module_file and scan.word(scan.pos, "export")) {
            try exports.append(work, try scan.exportStatement(src));
            continue;
        }
        const start = scan.tokens[scan.pos].span.start;
        // Attributes are part of the declaration's byte range; consume the whole
        // clause so the scan head is entered at the declaration token itself.
        while (scan.tokens[scan.pos].tag == .at) scan.pos = lex.declarationEnd(scan.src.bytes, scan.tokens, scan.pos, false);
        const head = try scan.head();
        try tally.check(head.kind, head.name);
        const end = try scan.body(head.braced);
        try listed.append(work, .{
            .kind = @tagName(head.kind),
            .name = src.text(head.name),
            .exported = ast.isPublicDeclaration(syntax, head.name),
            .bytes = .{ .start = start, .end = end.end },
            .comment_start = commentStart(src.bytes, start),
            .attributes = try listAttributes(work, src, syntax, head.name),
        });
    }
    try tally.finish();
    try resolveExports(work, listed.items, exports.items, sink);
    return std.json.Stringify.valueAlloc(allocator, .{
        .version = "declarations-v1",
        .module = module_name,
        .header = @as(?source.Span, null),
        .imports = imports.items,
        .exports = exports.items,
        .declarations = listed.items,
    }, .{});
}

/// Mark exported declarations, rejecting duplicate and unresolved export directives.
/// A re-export names an imported declaration instead of a local one, so it is
/// reported with its qualifier and marks no local listing flag.
fn resolveExports(work: std.mem.Allocator, listed: []Listed, exports: []const Exported, sink: *diagnostic.Sink) Error!void {
    var by_name: std.StringHashMapUnmanaged(usize) = .empty;
    for (listed, 0..) |item, index| {
        const entry = try by_name.getOrPut(work, item.name);
        if (!entry.found_existing) entry.value_ptr.* = index;
    }
    var seen: std.StringHashMapUnmanaged(source.Span) = .empty;
    for (exports) |exported| {
        if (seen.get(exported.name)) |previous| return sink.failRelated("E_DUPLICATE_EXPORT", exported.span, "declaration is already exported", .{ .span = previous, .message = "earlier export directive" });
        try seen.put(work, exported.name, exported.span);
        if (exported.alias != null) continue;
        const index = by_name.get(exported.name) orelse return sink.fail("E_UNKNOWN_EXPORT", exported.span, "export names no local declaration");
        if (listed[index].exported) return sink.fail("E_DUPLICATE_EXPORT", exported.span, "declaration is already public");
        listed[index].exported = true;
    }
}

/// Start of the contiguous leading line comments attached to a declaration.
fn commentStart(bytes: []const u8, start: usize) usize {
    var line = lineStart(bytes, start);
    if (std.mem.indexOfNone(u8, bytes[line..start], " \t\r") != null) return start;
    while (line > 0) {
        const previous = lineStart(bytes, line - 1);
        const comment = std.mem.trim(u8, bytes[previous .. line - 1], " \t\r");
        if (!std.mem.startsWith(u8, comment, "#")) break;
        line = previous;
    }
    return line;
}

fn lineStart(bytes: []const u8, at: usize) usize {
    const newline = std.mem.lastIndexOfScalar(u8, bytes[0..at], '\n') orelse return 0;
    return newline + 1;
}

/// Leading keywords and declared name of one top-level construct.
const Head = struct { kind: Kind, name: source.Span, braced: bool };
const Simple = struct { kind: Kind, braced: bool };

/// Token cursor over already parsed source; boundaries are read, never re-validated.
const Scan = struct {
    src: source.Source,
    tokens: []const lex.Token,
    pos: usize = 0,

    fn word(self: Scan, at: usize, text: []const u8) bool {
        return self.tokens[at].tag == .ident and std.mem.eql(u8, self.src.text(self.tokens[at].span), text);
    }
    /// The parser validated this grammar already, so a mismatch is an internal defect.
    fn expect(self: *Scan, want: lex.Tag) error{InternalError}!source.Span {
        if (want == .semicolon and self.tokens[self.pos].tag != .semicolon and lex.implicitTerminator(self.src.bytes, self.tokens, self.pos)) {
            const end = self.tokens[self.pos - 1].span.end;
            return .{ .start = end, .end = end };
        }
        if (self.tokens[self.pos].tag != want) return error.InternalError;
        defer self.pos += 1;
        return self.tokens[self.pos].span;
    }
    fn take(self: *Scan, want: lex.Tag) bool {
        if (self.tokens[self.pos].tag != want) return false;
        self.pos += 1;
        return true;
    }
    fn dotted(self: *Scan) error{InternalError}!source.Span {
        const first = try self.expect(.ident);
        var last = first;
        while (self.take(.dot)) last = try self.expect(.ident);
        return .join(first, last);
    }
    /// Collect every import statement with its alias and statement bytes.
    fn imports(self: *Scan, work: std.mem.Allocator, into: *std.ArrayList(Import), src: source.Source) Error!void {
        while (self.word(self.pos, "import")) {
            const start = self.tokens[self.pos].span.start;
            self.pos += 1;
            const name = try self.dotted();
            const alias = if (self.take(.kw_as)) try self.expect(.ident) else null;
            const end = try self.expect(.semicolon);
            try into.append(work, .{
                .name = src.text(name),
                .alias = if (alias) |span| src.text(span) else null,
                .bytes = .{ .start = start, .end = end.end },
            });
        }
    }
    /// Consume one `export NAME;` or `export module.NAME;` directive and return
    /// its record. The final member is the published local name; an earlier
    /// segment is the imported module qualifier of a re-export.
    fn exportStatement(self: *Scan, src: source.Source) error{InternalError}!Exported {
        const start = self.tokens[self.pos].span.start;
        self.pos += 1;
        const first = try self.declaredName();
        var last = first;
        var qualifier_end: ?usize = null;
        while (self.take(.dot)) {
            qualifier_end = last.end;
            last = try self.declaredName();
        }
        const end = try self.expect(.semicolon);
        const alias = if (qualifier_end) |at| src.text(.{ .start = first.start, .end = at }) else null;
        return .{ .name = src.text(last), .span = .join(first, last), .bytes = .{ .start = start, .end = end.end }, .alias = alias };
    }
    /// Accept a declared name that collides with an intrinsic keyword, as the parser does.
    fn declaredName(self: *Scan) error{InternalError}!source.Span {
        const token = self.tokens[self.pos];
        if (token.tag != .kw_len and token.tag != .kw_replace) return self.expect(.ident);
        self.pos += 1;
        return token.span;
    }
    /// Read the leading keywords and name of the next top-level declaration.
    fn head(self: *Scan) error{InternalError}!Head {
        if (self.word(self.pos, "public")) self.pos += 1;
        if (self.simple()) |form| {
            self.pos += 1;
            return .{ .kind = form.kind, .name = try self.declaredName(), .braced = form.braced };
        }
        const c_abi = self.word(self.pos, "extern");
        const host = self.word(self.pos, "host") or c_abi;
        if (host) self.pos += 1;
        _ = self.take(.kw_private);
        _ = self.take(.kw_conversion);
        _ = try self.expect(.kw_def);
        return .{ .kind = if (c_abi) .extern_fn else if (host) .host_fn else .@"fn", .name = try self.declaredName(), .braced = !host };
    }
    fn simple(self: Scan) ?Simple {
        return switch (self.tokens[self.pos].tag) {
            .kw_type => .{ .kind = .alias, .braced = false },
            .kw_const => .{ .kind = .@"const", .braced = false },
            .kw_enum => .{ .kind = .@"enum", .braced = true },
            .kw_union => .{ .kind = .@"union", .braced = true },
            .kw_domain => .{ .kind = .domain, .braced = true },
            .kw_class => .{ .kind = .@"struct", .braced = true },
            .ident => if (self.word(self.pos, "resource"))
                .{ .kind = .resource, .braced = false }
            else if (self.word(self.pos, "result"))
                .{ .kind = .result, .braced = true }
            else if (self.word(self.pos, "record"))
                .{ .kind = .@"struct", .braced = true }
            else if (self.word(self.pos, "constraint"))
                .{ .kind = .constraint, .braced = false }
            else
                null,
            else => null,
        };
    }
    /// Consume one declaration through its terminating brace or semicolon.
    /// Indentation closes a suite with zero-width braces standing at the next
    /// declaration, so the reported bytes end at the last token the body wrote;
    /// the comments between two declarations then belong to the second.
    fn body(self: *Scan, braced: bool) error{InternalError}!source.Span {
        const at = lex.declarationEnd(self.src.bytes, self.tokens, self.pos, braced);
        if (at == self.pos) return error.InternalError;
        const last = self.tokens[at - 1];
        if (braced and last.tag != .dedent) return error.InternalError;
        if (!braced and last.tag != .semicolon) {
            if (!lex.implicitTerminator(self.src.bytes, self.tokens, at)) return error.InternalError;
        }
        self.pos = at;
        var written = at;
        while (written > 1 and self.tokens[written - 1].span.start == self.tokens[written - 1].span.end) written -= 1;
        return self.tokens[written - 1].span;
    }
};

/// Compares scanned declarations against the parser's own tables in source order.
const Tally = struct {
    syntax: ast.Program,
    counts: [std.enums.values(Kind).len]usize = @splat(0),

    fn check(self: *Tally, kind: Kind, name: source.Span) error{InternalError}!void {
        const index = self.counts[@backingInt(kind)];
        self.counts[@backingInt(kind)] = index + 1;
        const parsed = declared(self.syntax, kind, index) orelse return error.InternalError;
        if (parsed.start != name.start or parsed.end != name.end) return error.InternalError;
    }
    /// Reject any parsed declaration the scan did not report.
    fn finish(self: Tally) error{InternalError}!void {
        for (std.enums.values(Kind)) |kind| {
            if (declared(self.syntax, kind, self.counts[@backingInt(kind)]) != null) return error.InternalError;
        }
    }
};

fn declared(syntax: ast.Program, kind: Kind, index: usize) ?source.Span {
    const types = syntax.types;
    return switch (kind) {
        .alias => if (index < types.expressions.aliases.len) types.expressions.aliases[index].name else null,
        .@"struct" => if (index < types.records.len) types.records[index].name else null,
        .domain => if (index < types.domains.len) types.domains[index].name else null,
        .resource => if (index < types.resources.len) types.resources[index].name else null,
        .@"enum", .@"union", .result => variantName(types.variants, kind, index),
        .@"const", .@"fn", .host_fn, .extern_fn => functionName(syntax.functions, kind, index),
        .constraint => if (index < types.constraints.len) types.constraints[index].name else null,
    };
}

fn variantName(variants: []const ast.Variants, kind: Kind, index: usize) ?source.Span {
    var seen: usize = 0;
    for (variants) |variant| {
        const actual: Kind = if (variant.fallible) .result else .@"enum";
        if (actual != kind) continue;
        if (seen == index) return variant.name;
        seen += 1;
    }
    return null;
}

fn functionName(functions: []const ast.Function, kind: Kind, index: usize) ?source.Span {
    var seen: usize = 0;
    for (functions) |function| {
        if (function.policy.owner != null) continue;
        const actual: Kind = if (function.policy.constant) .@"const" else if (function.policy.c_abi) .extern_fn else if (function.policy.host != null) .host_fn else .@"fn";
        if (actual != kind) continue;
        if (seen == index) return function.name;
        seen += 1;
    }
    return null;
}
