//! Deterministic module-header discovery. This graph does not yet resolve exports
//! or type-check multi-file bodies. Provider paths are normalized relative names.
/// Failures returned by load; callers must handle these boundary errors.
pub const LoadError = error{
    InvalidModuleBudget,
    InvalidModuleName,
    OutOfMemory,
    ProjectAlreadyLoaded,
    SourceError,
    InternalError,
};
/// Failures returned by render; callers must handle these boundary errors.
pub const RenderError = error{
    IncompleteProject,
    OutOfMemory,
};
/// Failures returned by renderProblem; callers must handle these boundary errors.
pub const RenderProblemError = error{
    NoProblem,
    OutOfMemory,
};
/// Failures returned by modulePath; callers must handle these boundary errors.
pub const ModulePathError = error{
    InvalidModuleName,
    OutOfMemory,
};

const std = @import("std");
const ChunkedArena = @import("chunked_arena.zig").ChunkedArena;
const source = @import("source.zig");
const lex = @import("lexer.zig");
const diagnostic = @import("diagnostic.zig");
const standard_library = @import("standard_library.zig");
/// The one code every malformed or missing module header reports.
const eModuleHeader = "E_MODULE_HEADER";
/// Header discovery's scratch chunk: the tokens of a module of about 64 KiB.
const header_scratch_bytes = 1 << 20;
pub const ReadError = error{ OutOfMemory, NotFound, ReadFailed, TooLarge };
/// Source reader callback; returned bytes use the supplied allocator and respect the byte limit.
pub const Provider = struct { context: ?*anyopaque, read: *const fn (?*anyopaque, std.mem.Allocator, []const u8, usize) ReadError![]u8 };
/// Bounds on module count, import edges, individual files, and total source
/// bytes. A `mylang.json` `budgets` object may override each field. The
/// defaults (PROJ-SCALE-1) admit a project of well over a million lines with no
/// configuration: 64 MiB of source is about 1.9 million lines of 35-byte lines,
/// and 16,384 modules averages 64 lines a module over a million lines.
pub const Options = struct { max_modules: usize = 16384, max_imports: usize = 262144, max_file_bytes: usize = 4 * 1024 * 1024, max_total_bytes: usize = 64 * 1024 * 1024 };
/// A source span paired with the module whose bytes it indexes.
pub const Site = struct { module: usize, span: source.Span };
/// A dotted module path: its joined text, its trailing segment, and its span.
pub const ModuleName = struct { text: []const u8, last: []const u8, span: source.Span };
/// Project diagnostic and optional related declaration/import location.
pub const Problem = struct { code: []const u8, message: []const u8, site: Site, related: ?Site = null };
/// Declared public name and its source location. A re-export directive
/// (`export shared.units.Distance`) records `name` as the final member and
/// `alias` as the imported module qualifier; a plain `export Name` leaves
/// `alias` null.
pub const Export = struct { name: []const u8, span: source.Span, alias: ?[]const u8 = null };
/// Imported module name, local alias, source span, and resolved target index.
pub const Import = struct {
    name: []const u8,
    alias: []const u8,
    span: source.Span,
    target: usize = undefined,
    /// Whether some qualified reference after the header names this import
    /// (the first import a qualifier matches). Header discovery already holds
    /// the module's tokens, so the unused-import warning reads this instead of
    /// lexing every module a second time.
    seen: bool = false,

    /// Whether a source qualifier names this import, by its local alias or its
    /// full dotted module path. `import a.b` therefore answers both `a.b.fn`
    /// and `b.fn` while `import a.b as c` answers only `c.fn`.
    pub fn matches(self: Import, requested: []const u8) bool {
        return std.mem.eql(u8, requested, self.alias) or std.mem.eql(u8, requested, self.name);
    }
};
/// Owned source and parsed dependency metadata with traversal state and content digest.
pub const Module = struct {
    name: []const u8,
    src: source.Source,
    header: struct {
        declaration: source.Span = .{ .start = 0, .end = 0 },
        body_start: usize = 0,
        /// Whether header discovery recorded each import's `seen` flag.
        usage_scanned: bool = false,
    } = .{},
    imports: []Import = &.{},
    exports: []Export = &.{},
    digest: [32]u8 = undefined,
    state: enum {
        unseen,
        visiting,
        complete,
    } = .unseen,
};
/// Owns loaded modules, diagnostics, and dependency order in a project arena.
pub const Project = struct {
    /// Every module's source, syntax and checked program: an arena whose
    /// untouched reservation stays within one chunk (ARENA-BOUNDED-1).
    arena: ChunkedArena,
    modules: std.ArrayList(Module) = .empty,
    order: std.ArrayList(usize) = .empty,
    names: std.StringHashMapUnmanaged(usize) = .empty,
    problem: ?Problem = null,
    counts: struct { bytes: usize = 0, imports: usize = 0 } = .{},
    progress: struct { started: bool = false, complete: bool = false } = .{},
    /// Create an empty project arena; release all project storage with deinit.
    pub fn init(allocator: std.mem.Allocator) Project {
        return .{ .arena = .init(allocator) };
    }
    pub fn deinit(self: *Project) void {
        self.arena.deinit();
    }
    /// Record a project diagnostic and return SourceError for propagation.
    pub fn fail(self: *Project, code: []const u8, message: []const u8, site: Site, related: ?Site) error{SourceError} {
        self.problem = .{ .code = code, .message = message, .site = site, .related = related };
        return error.SourceError;
    }
    fn intern(self: *Project, provider: Provider, name: []const u8, origin: ?Site, options: Options, scratch: *std.heap.ArenaAllocator) diagnostic.Error!usize {
        if (self.names.get(name)) |id| return id;
        const allocator = self.arena.allocator();
        if (self.modules.items.len >= options.max_modules) return self.fail("E_MODULE_LIMIT", "module count exceeds the project budget", origin orelse .{ .module = 0, .span = .{ .start = 0, .end = 0 } }, null);
        const path = modulePath(allocator, name) catch |err| switch (err) {
            error.InvalidModuleName => unreachable,
            error.OutOfMemory => return error.OutOfMemory,
        };
        const id = self.modules.items.len;
        const owned_name = try allocator.dupe(u8, name);
        try self.modules.append(allocator, .{ .name = owned_name, .src = try source.Source.init(allocator, path, "") });
        try self.names.put(allocator, owned_name, id);
        const site = origin orelse Site{ .module = id, .span = .{ .start = 0, .end = 0 } };
        const limit = @min(options.max_file_bytes, options.max_total_bytes - self.counts.bytes);
        const bytes = if (standard_library.source(path)) |library| try allocator.dupe(u8, library) else provider.read(provider.context, allocator, path, limit) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            if (err == error.TooLarge) return self.fail("E_PROJECT_BYTES", try budgetMessage(allocator, path, options, self.counts.bytes), site, null);
            return self.fail("E_MODULE_READ", try std.fmt.allocPrint(allocator, "cannot load {s}: {s}", .{ path, @errorName(err) }), site, null);
        };
        defer allocator.free(bytes);
        if (bytes.len > limit) return self.fail("E_PROJECT_BYTES", try budgetMessage(allocator, path, options, self.counts.bytes), site, null);
        self.counts.bytes += bytes.len;
        const source_path = if (standard_library.source(path) != null) try std.fmt.allocPrint(allocator, "@stdlib/{s}", .{path}) else path;
        self.modules.items[id].src = try source.Source.init(allocator, source_path, bytes);
        std.crypto.hash.sha2.Sha256.hash(bytes, &self.modules.items[id].digest, .{});
        try self.header(id, options, origin == null, scratch);
        return id;
    }
    /// Load the reachable import graph iteratively while enforcing source and graph limits.
    pub fn load(self: *Project, provider: Provider, entry: []const u8, options: Options) LoadError!void {
        if (self.progress.started) return error.ProjectAlreadyLoaded;
        self.progress.started = true;
        if (!validName(entry)) return error.InvalidModuleName;
        // An empty budget is a host configuration error, so no nonexistent source
        // location needs to be manufactured for the diagnostic renderer.
        if (options.max_modules == 0) return error.InvalidModuleBudget;
        const allocator = self.arena.allocator();
        // Header discovery lexes each module into this scratch arena, which is
        // reset after every module, so the token arrays of a whole project are
        // never live (or faulted in) at once.
        var scratch = std.heap.ArenaAllocator.init(self.arena.child_allocator);
        defer scratch.deinit();
        // One chunk that holds a typical module's tokens, reused by every
        // module rather than grown (and faulted in) module by module.
        _ = try scratch.allocator().alloc(u8, header_scratch_bytes);
        const root = try self.intern(provider, entry, null, options, &scratch);
        const Visit = struct { id: usize, next: usize = 0 };
        var work: std.ArrayList(Visit) = .empty;
        defer work.deinit(allocator);
        self.modules.items[root].state = .visiting;
        try work.append(allocator, .{ .id = root });
        while (work.items.len != 0) {
            const index = work.items.len - 1;
            const visit = work.items[index];
            if (visit.next == self.modules.items[visit.id].imports.len) {
                self.modules.items[visit.id].state = .complete;
                try self.order.append(allocator, visit.id);
                _ = work.pop();
                continue;
            }
            work.items[index].next += 1;
            const imported = self.modules.items[visit.id].imports[visit.next];
            const site: Site = .{ .module = visit.id, .span = imported.span };
            const target = try self.intern(provider, imported.name, site, options, &scratch);
            self.modules.items[visit.id].imports[visit.next].target = target;
            switch (self.modules.items[target].state) {
                .complete => {},
                .unseen => {
                    self.modules.items[target].state = .visiting;
                    try work.append(allocator, .{ .id = target });
                },
                .visiting => {
                    var chain: std.Io.Writer.Allocating = .init(allocator);
                    var include = false;
                    for (work.items) |at| {
                        if (at.id == target) include = true;
                        if (include) chain.writer.print("{s} -> ", .{self.modules.items[at.id].name}) catch return error.OutOfMemory;
                    }
                    chain.writer.writeAll(self.modules.items[target].name) catch return error.OutOfMemory;
                    return self.fail("E_IMPORT_CYCLE", try chain.toOwnedSlice(), site, .{ .module = target, .span = self.modules.items[target].header.declaration });
                },
            }
        }
        self.progress.complete = true;
    }
    fn header(self: *Project, id: usize, options: Options, is_entry: bool, scratch: *std.heap.ArenaAllocator) diagnostic.Error!void {
        const allocator = self.arena.allocator();
        const src = self.modules.items[id].src;
        // Diagnostics outlive the header in the project arena; only the tokens
        // are scratch. Releasing the previous module's tokens can itself
        // allocate (to keep one retained chunk), and that failure is reported.
        var sink: diagnostic.Sink = .{ .allocator = allocator };
        if (!scratch.reset(.retain_capacity)) return error.OutOfMemory;
        const tokens = lex.lex(scratch.allocator(), src.bytes, &sink) catch |err| {
            if (err == error.OutOfMemory) return err;
            const problem = sink.items.items[0];
            return self.fail(problem.code, problem.message, .{ .module = id, .span = problem.span }, null);
        };
        var scanner: Scanner = .{ .project = self, .id = id, .tokens = tokens };
        if (try self.moduleDeclaration(&scanner, is_entry)) |declared| {
            self.modules.items[id].header.declaration = declared.span;
            if (!std.mem.eql(u8, declared.text, self.modules.items[id].name)) {
                // State the rule and the exact replacement: an agent that copied
                // `module main` from an example into `csvstats.my` needs both.
                const expected = self.modules.items[id].name;
                const message = try std.fmt.allocPrint(
                    allocator,
                    "declared `module {s}`, but this file is `{s}`, so its module name is `{s}`: " ++
                        "a module's name is its path from the project root without `.my`; write `module {s}`",
                    .{ declared.text, self.modules.items[id].src.path, expected, expected },
                );
                return self.fail("E_MODULE_NAME", message, .{ .module = id, .span = declared.span }, null);
            }
        }
        var imports: std.ArrayList(Import) = .empty;
        var aliases: std.StringHashMapUnmanaged(source.Span) = .empty;
        var imported_names: std.StringHashMapUnmanaged(source.Span) = .empty;
        while (scanner.isWord("import")) {
            scanner.pos += 1;
            const imported = try scanner.name();
            var alias = imported.last;
            if (scanner.take(.kw_as)) alias = src.text((try scanner.expect(.ident)).span);
            _ = try scanner.expect(.semicolon);
            if (aliases.get(alias)) |previous| return self.fail("E_IMPORT_ALIAS", "import alias is already bound", .{ .module = id, .span = imported.span }, .{ .module = id, .span = previous });
            if (imported_names.get(imported.text)) |previous| return self.fail("E_DUPLICATE_IMPORT", "module is already imported in this file", .{ .module = id, .span = imported.span }, .{ .module = id, .span = previous });
            if (self.counts.imports >= options.max_imports) return self.fail("E_IMPORT_LIMIT", "import count exceeds the project budget", .{ .module = id, .span = imported.span }, null);
            self.counts.imports += 1;
            try aliases.put(allocator, alias, imported.span);
            try imported_names.put(allocator, imported.text, imported.span);
            try imports.append(allocator, .{ .name = imported.text, .alias = alias, .span = imported.span });
        }
        self.modules.items[id].imports = try imports.toOwnedSlice(allocator);
        self.modules.items[id].header.body_start = tokens[scanner.pos].span.start;
        var exports: std.ArrayList(Export) = .empty;
        var exported_names: std.StringHashMapUnmanaged(source.Span) = .empty;
        while (scanner.tokens[scanner.pos].tag != .eof) {
            if (!scanner.isWord("export")) {
                scanner.skipDeclaration();
                continue;
            }
            scanner.pos += 1;
            const exported_name = try scanner.name();
            const alias = if (exported_name.text.len == exported_name.last.len) null else exported_name.text[0 .. exported_name.text.len - exported_name.last.len - 1];
            _ = try scanner.expect(.semicolon);
            // A bare `export NAME` is removed; a local declaration publishes
            // itself with `public`. Only the dotted re-export remains a directive.
            if (alias == null) return self.fail("E_EXPORT_REMOVED", "plain `export NAME` is removed; mark the declaration `public` instead", .{ .module = id, .span = exported_name.span }, null);
            if (alias) |qualifier| {
                var imported_qualifier = false;
                for (self.modules.items[id].imports) |imported| {
                    if (imported.matches(qualifier)) {
                        imported_qualifier = true;
                        break;
                    }
                }
                if (!imported_qualifier) return self.fail("E_UNKNOWN_EXPORT", "re-export names no imported module", .{ .module = id, .span = exported_name.span }, null);
            }
            if (exported_names.get(exported_name.last)) |previous| return self.fail("E_DUPLICATE_EXPORT", "declaration is already exported", .{ .module = id, .span = exported_name.span }, .{ .module = id, .span = previous });
            try exported_names.put(allocator, exported_name.last, exported_name.span);
            try exports.append(allocator, .{ .name = exported_name.last, .span = exported_name.span, .alias = alias });
        }
        self.modules.items[id].exports = try exports.toOwnedSlice(allocator);
        markQualifiedImports(src.bytes, tokens, self.modules.items[id].header.body_start, self.modules.items[id].imports);
        self.modules.items[id].header.usage_scanned = true;
    }
    /// Consume the `module NAME;` header, or the headerless opening of an entry
    /// script whose every import names an embedded standard module. Answers the
    /// declared name when there is one, null for the headerless form, and reports
    /// `E_MODULE_HEADER` for every other opening, including an imported file that
    /// declares nothing.
    fn moduleDeclaration(self: *Project, scanner: *Scanner, is_entry: bool) diagnostic.Error!?ModuleName {
        if (scanner.isWord("module")) {
            scanner.pos += 1;
            const declared = try scanner.name();
            _ = try scanner.expect(.semicolon);
            return declared;
        }
        if (!is_entry or !try standardImportOpening(self.arena.allocator(), self.modules.items[scanner.id].src, scanner.tokens, scanner.pos)) {
            const site: Site = .{ .module = scanner.id, .span = scanner.tokens[scanner.pos].span };
            if (is_entry) if (try self.projectImport(scanner)) |name| {
                // `import heapq` in a script is usually a Python import, not a
                // missing header: say which module is not standard and what is.
                const allocator = self.arena.allocator();
                const message = try std.fmt.allocPrint(
                    allocator,
                    "`{s}` is not a standard module ({s}); a file without a `module` header can import only those. " ++
                        "To import `{s}.my` from this project, start this file with `module {s}`",
                    .{ name, try standard_library.names(allocator), name, self.modules.items[scanner.id].name },
                );
                return self.fail(eModuleHeader, message, site, null);
            };
            return self.fail(eModuleHeader, "file must begin with a module declaration", site, null);
        }
        return null;
    }
    /// The first imported name in a headerless opening that is not an embedded
    /// standard module, or null when the opening is not an import list.
    fn projectImport(self: *Project, scanner: *Scanner) diagnostic.Error!?[]const u8 {
        const src = self.modules.items[scanner.id].src;
        const tokens = scanner.tokens;
        var cursor = scanner.pos;
        while (cursor + 1 < tokens.len and tokens[cursor].tag == .ident and std.mem.eql(u8, src.text(tokens[cursor].span), "import")) {
            if (tokens[cursor + 1].tag != .ident) return null;
            const name = src.text(tokens[cursor + 1].span);
            if (!try isStandardModule(self.arena.allocator(), name)) return name;
            cursor += 2;
            if (cursor < tokens.len and tokens[cursor].tag == .kw_as) cursor += 2;
            if (cursor < tokens.len and tokens[cursor].tag == .semicolon) cursor += 1;
        }
        return null;
    }
    /// Allocate the completed dependency graph report; reject incomplete loading state.
    pub fn render(self: *Project, allocator: std.mem.Allocator) RenderError![]u8 {
        if (!self.progress.complete) return error.IncompleteProject;
        var output: std.Io.Writer.Allocating = .init(allocator);
        errdefer output.deinit();
        output.writer.writeAll("module graph v1; header discovery only; bodies/exports/types not checked\n") catch return error.OutOfMemory;
        for (self.order.items) |id| {
            const module = self.modules.items[id];
            output.writer.print("module {s} path={s} sha256={s}\n", .{ module.name, module.src.path, std.fmt.bytesToHex(module.digest, .lower) }) catch return error.OutOfMemory;
            for (module.imports) |imported| output.writer.print("  import {s} as {s}\n", .{ self.modules.items[imported.target].name, imported.alias }) catch return error.OutOfMemory;
        }
        return output.toOwnedSlice();
    }
    /// Allocate the current project diagnostic with source locations.
    pub fn renderProblem(self: *Project, allocator: std.mem.Allocator) RenderProblemError![]u8 {
        const problem = self.problem orelse return error.NoProblem;
        const diag: diagnostic.Diagnostic = .{ .code = problem.code, .span = problem.site.span, .message = problem.message };
        const primary = try diag.render(allocator, self.modules.items[problem.site.module].src);
        if (problem.related) |related| {
            defer allocator.free(primary);
            const src = self.modules.items[related.module].src;
            const at = src.locate(related.span.start);
            return std.fmt.allocPrint(allocator, "{s}{s}:{d}:{d}: note: related module/import declaration\n", .{ primary, src.path, at.line, at.column });
        }
        return primary;
    }
};
/// Mark every import some dotted reference after the header qualifies: for each
/// `a.b.c` chain the qualifier `a.b` marks the first import it names. This is
/// the scan the unused-import warning needs, taken from the header's tokens.
fn markQualifiedImports(bytes: []const u8, tokens: []const lex.Token, body_start: usize, imports: []Import) void {
    if (imports.len == 0) return;
    var index: usize = 0;
    while (index < tokens.len) : (index += 1) {
        if (tokens[index].tag != .ident) continue;
        if (tokens[index].span.start < body_start) continue;
        var last = index;
        var cursor = index + 1;
        while (cursor + 1 < tokens.len and tokens[cursor].tag == .dot and tokens[cursor + 1].tag == .ident) {
            last = cursor + 1;
            cursor += 2;
        }
        if (last == index) continue;
        const qualifier = bytes[tokens[index].span.start..tokens[last - 2].span.end];
        for (imports) |*imported| {
            if (!imported.matches(qualifier)) continue;
            imported.seen = true;
            break;
        }
        index = last;
    }
}
const Scanner = struct {
    project: *Project,
    id: usize,
    tokens: []const lex.Token,
    pos: usize = 0,
    // Discovery skips bodies without parsing them. Only declaration boundaries
    // can introduce exports; identifiers named export inside declarations cannot.
    fn skipDeclaration(self: *Scanner) void {
        // A `public` modifier precedes the declaration head, so look through it
        // to decide whether the declaration has a braced body.
        var head = self.pos;
        if (head < self.tokens.len and self.tokens[head].tag == .ident and std.mem.eql(u8, self.project.modules.items[self.id].src.text(self.tokens[head].span), "public")) head += 1;
        const braced = switch (self.tokens[head].tag) {
            .kw_def, .kw_class, .kw_enum, .kw_union, .kw_domain, .kw_private, .kw_conversion => true,
            .ident => self.isWordAt(head, "result") or self.isWordAt(head, "record"),
            else => false,
        };
        self.pos = lex.declarationEnd(self.project.modules.items[self.id].src.bytes, self.tokens, self.pos, braced);
    }
    fn isWordAt(self: Scanner, at: usize, text: []const u8) bool {
        const token = self.tokens[at];
        return token.tag == .ident and std.mem.eql(u8, self.project.modules.items[self.id].src.text(token.span), text);
    }
    fn take(self: *Scanner, tag: lex.Tag) bool {
        if (self.tokens[self.pos].tag != tag) return false;
        self.pos += 1;
        return true;
    }
    fn expect(self: *Scanner, tag: lex.Tag) diagnostic.Error!lex.Token {
        const token = self.tokens[self.pos];
        const bytes = self.project.modules.items[self.id].src.bytes;
        if (tag == .semicolon and token.tag != .semicolon and lex.implicitTerminator(bytes, self.tokens, self.pos)) {
            const end = self.tokens[self.pos - 1].span.end;
            return .{ .tag = .semicolon, .span = .{ .start = end, .end = end } };
        }
        if (!self.take(tag)) return self.project.fail(eModuleHeader, "unexpected token in module/import header", .{ .module = self.id, .span = token.span }, null);
        return token;
    }
    fn isWord(self: Scanner, text: []const u8) bool {
        const token = self.tokens[self.pos];
        return token.tag == .ident and std.mem.eql(u8, self.project.modules.items[self.id].src.text(token.span), text);
    }
    fn word(self: *Scanner, text: []const u8) diagnostic.Error!void {
        if (!self.isWord(text)) return self.project.fail(eModuleHeader, "file must begin with a module declaration", .{ .module = self.id, .span = self.tokens[self.pos].span }, null);
        self.pos += 1;
    }
    fn name(self: *Scanner) diagnostic.Error!ModuleName {
        const src = self.project.modules.items[self.id].src;
        const first = try self.expect(.ident);
        var last = first;
        var output: std.Io.Writer.Allocating = .init(self.project.arena.allocator());
        output.writer.writeAll(src.text(first.span)) catch return error.OutOfMemory;
        while (self.take(.dot)) {
            last = try self.expect(.ident);
            output.writer.print(".{s}", .{src.text(last.span)}) catch return error.OutOfMemory;
        }
        return .{ .text = try output.toOwnedSlice(), .last = src.text(last.span), .span = .join(first.span, last.span) };
    }
};
/// The `E_PROJECT_BYTES` message for a module the byte budget refused: which
/// budget ran out — the project total or the single file — its size, and the
/// `mylang.json` field that raises it.
fn budgetMessage(allocator: std.mem.Allocator, path: []const u8, options: Options, loaded: usize) error{OutOfMemory}![]const u8 {
    if (options.max_total_bytes - loaded < options.max_file_bytes) {
        return std.fmt.allocPrint(allocator, "cannot load {s}: the project's sources exceed the {d}-byte max_total_bytes budget; raise budgets.max_total_bytes in mylang.json", .{ path, options.max_total_bytes });
    }
    return std.fmt.allocPrint(allocator, "cannot load {s}: the file exceeds the {d}-byte max_file_bytes budget; raise budgets.max_file_bytes in mylang.json", .{ path, options.max_file_bytes });
}
/// Check dotted module names while excluding filesystem traversal syntax.
pub fn validName(name: []const u8) bool {
    var parts = std.mem.splitScalar(u8, name, '.');
    while (parts.next()) |part| {
        if (part.len == 0 or !(std.ascii.isAlphabetic(part[0]) or part[0] == '_')) return false;
        for (part[1..]) |byte| if (!(std.ascii.isAlphanumeric(byte) or byte == '_')) return false;
    }
    return name.len != 0;
}
/// Allocate the relative source path corresponding to a valid dotted module name.
pub fn modulePath(allocator: std.mem.Allocator, name: []const u8) ModulePathError![]u8 {
    if (!validName(name)) return error.InvalidModuleName;
    const path = try std.fmt.allocPrint(allocator, "{s}.my", .{name});
    for (path[0..name.len]) |*byte| if (byte.* == '.') {
        byte.* = '/';
    };
    return path;
}
/// Whether `name` resolves to a compiler-embedded standard module. The embedded
/// set is fixed at compile time, so this is a table lookup, never a disk read.
pub fn isStandardModule(allocator: std.mem.Allocator, name: []const u8) diagnostic.Error!bool {
    const path = modulePath(allocator, name) catch |err| switch (err) {
        error.InvalidModuleName => return false,
        error.OutOfMemory => return error.OutOfMemory,
    };
    defer allocator.free(path);
    return standard_library.source(path) != null;
}
/// Whether the token run at `at` opens a headerless file whose imports all name
/// embedded standard modules: the script shape that needs no `module`
/// declaration. A dotted path, a project module, or any other opening answers
/// false, so the caller keeps the header requirement. Parser and project loader
/// share this one policy.
pub fn standardImportOpening(allocator: std.mem.Allocator, src: source.Source, tokens: []const lex.Token, at: usize) diagnostic.Error!bool {
    var cursor = at;
    while (cursor + 1 < tokens.len and tokens[cursor].tag == .ident and std.mem.eql(u8, src.text(tokens[cursor].span), "import")) {
        if (tokens[cursor + 1].tag != .ident) return false;
        if (!try isStandardModule(allocator, src.text(tokens[cursor + 1].span))) return false;
        cursor += 2;
        if (cursor < tokens.len and tokens[cursor].tag == .kw_as) {
            if (cursor + 1 >= tokens.len or tokens[cursor + 1].tag != .ident) return false;
            cursor += 2;
        }
        // A directive ends at its explicit semicolon or at the line break the
        // module-header grammar accepts in its place.
        if (cursor < tokens.len and tokens[cursor].tag == .semicolon) {
            cursor += 1;
        } else if (!lex.implicitTerminator(src.bytes, tokens, cursor)) return false;
    }
    return cursor != at;
}
