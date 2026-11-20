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
const product = @import("product.zig");
const ChunkedArena = @import("chunked_arena.zig").ChunkedArena;
const source = @import("source.zig");
const lex = @import("lexer.zig");
const diagnostic = @import("diagnostic.zig");
const standard_library = @import("standard_library.zig");
const embed = @import("embed.zig");
const source_digest = @import("source_digest.zig");
const module_records = @import("module_records.zig");
const format_strings = @import("format_strings.zig");
const import_cycle = @import("import_cycle.zig");
/// The one code every malformed or missing module header reports.
const eModuleHeader = "E_MODULE_HEADER";
const eProjectBytes = "E_PROJECT_BYTES";
/// Header discovery's scratch chunk: the tokens of a module of about 64 KiB.
const header_scratch_bytes = 1 << 20;
pub const ReadError = error{ OutOfMemory, NotFound, ReadFailed, TooLarge };
/// Source reader callback; returned bytes use the supplied allocator and respect the byte limit.
/// `embed` reads the file one `embed_bytes`/`embed_str` literal names, given the
/// embedding module's path, the literal's text and the byte allowance; a provider without it leaves
/// every embed unresolved (`EMBED-1`).
pub const Provider = struct {
    context: ?*anyopaque,
    read: *const fn (?*anyopaque, std.mem.Allocator, []const u8, usize) ReadError![]u8,
    embed: ?*const fn (?*anyopaque, std.mem.Allocator, []const u8, []const u8, usize) std.mem.Allocator.Error!embed.Read = null,
    /// Header records to read and keep between builds. Null keeps none.
    records: ?module_records.Records = null,
    /// A digest the provider can vouch for without hashing: given the project-relative path of a module it just read and the bytes it
    /// returned, the `source_digest.of` those bytes, or null to have the loader hash them (`core/file_digests.zig`: a stat tuple recorded
    /// by an earlier load, outside the engine's racy window, still describes the file). Called only for bytes read from the provider.
    vouch: ?*const fn (?*anyopaque, []const u8, []const u8) ?[32]u8 = null,
    /// Told the digest the loader took of the bytes `read` returned for a path, when `vouch` did not give it, so the provider can remember it.
    learned: ?*const fn (?*anyopaque, []const u8, [32]u8) void = null,
};
/// When a load takes each module's digest. `.eager` hashes a module as it is read. `.deferred` is for whole-project verdicts, which hash the
/// loaded bytes themselves: the caller may skip the per-module hashes until a verdict misses, and then must call `ensureSourceDigests` before
/// reading any module's `digest`. `.with_sha256` also takes each module's SHA-256 as it is read, for the commands that publish one in a receipt
/// (`sha256Of`): the receipt then names the bytes the project loaded even if the module's source is replaced in memory afterwards, where
/// otherwise `sha256Of` hashes the bytes it is given when it is asked.
pub const Digests = enum { eager, deferred, with_sha256 };
/// How a standard module's name is read: from the provider's file beside the entry first or from the compiler's own source, and
/// which local files the compiler's source hides.
pub const Standard = struct {
    /// MODULE-SCHEDULE-4: ask the provider for a standard module first (a per-module compile serves its precompiled interface), and
    /// read the compiler's own source only when the provider has none.
    from_provider: bool = false,
    /// The `.selka` files beside the entry that a standard module of the same name hides (`options.selka`): the loader reads the standard
    /// module, so these are ignored, and a message about a standard module that lacks a name says so.
    hidden: []const []const u8 = &.{},
};
/// Bounds on module count, import edges, individual files, and total source
/// and embedded bytes. A `selka.json` `budgets` object may override each field. The
/// defaults (PROJ-SCALE-1) admit a project of well over a million lines with no
/// configuration: 64 MiB of source is about 1.9 million lines of 35-byte lines,
/// and 16,384 modules averages 64 lines a module over a million lines.
pub const Options = struct {
    max_modules: usize = 16384,
    max_imports: usize = 262144,
    max_file_bytes: usize = 4 * 1024 * 1024,
    max_total_bytes: usize = 64 * 1024 * 1024,
    /// How a standard module's name is read (`Standard`).
    standard: Standard = .{},
    /// When the module digests are taken (`Digests`).
    digests: Digests = .eager,

    /// Accept redundant source headers when explicitly migrating legacy files.
    legacy_headers: bool = false,
};
/// A source span paired with the module whose bytes it indexes.
pub const Site = struct { module: usize, span: source.Span };
/// A dotted module path: its joined text, its trailing segment, and its span.
pub const ModuleName = struct { text: []const u8, last: []const u8, span: source.Span };
/// Project diagnostic, optional related declaration/import location, and the
/// exact edit that repairs it, indexing the problem module's own bytes.
pub const Problem = struct { code: []const u8, message: []const u8, site: Site, related: ?Site = null, fix: ?diagnostic.Edit = null, fix_more: []const diagnostic.Edit = &.{}, recovered: []const diagnostic.Diagnostic = &.{} };
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
    /// `source_digest.of` the module's bytes: every cache's name for them, and the header record's key. Valid unless
    /// `state.digest_pending`, which `ensureSourceDigests` settles.
    digest: [32]u8 = undefined,
    state: struct {
        traversal: enum { unseen, visiting, complete } = .unseen,
        digest_pending: bool = false,
        /// The SHA-256 of the bytes as loaded, when `Options.sha256` asked for it.
        sha256: ?[32]u8 = null,
    } = .{},
};
/// The module's SHA-256, for the receipts and reports that publish one (`source_receipt`, the module graph report, the API listing):
/// a verifier outside the compiler recomputes it, so it stays a SHA-256 while the caches use `Module.digest`. It is computed on
/// demand, with the portable compression, which runs at the same speed on every core of the build hosts.
pub fn sha256Of(module: Module) [32]u8 {
    if (module.state.sha256) |loaded| return loaded;
    var out: [32]u8 = undefined;
    @import("sha256_portable.zig").hash(module.src.bytes, &out);
    return out;
}
/// Owns loaded modules, diagnostics, and dependency order in a project arena.
pub const Project = struct {
    /// Every module's source, syntax and checked program: an arena whose
    /// untouched reservation stays within one chunk (ARENA-BOUNDED-1).
    arena: ChunkedArena,
    modules: std.ArrayList(Module) = .empty,
    order: std.ArrayList(usize) = .empty,
    names: std.StringHashMapUnmanaged(usize) = .empty,
    problem: ?Problem = null,
    counts: struct { bytes: usize = 0, embedded_bytes: usize = 0, imports: usize = 0 } = .{},
    /// The load's state, and `hidden_standard`, the `Options.standard.hidden` it was told of (borrowed from the caller).
    progress: struct { started: bool = false, complete: bool = false, source_digests_ready: bool = true, hidden_standard: []const []const u8 = &.{} } = .{},
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
        const standard = standard_library.source(path);
        // The embedded standard library is the compiler's own source, not the project's: `budgets.max_file_bytes` bounds the project's files,
        // so a small budget does not stop `import math`. The library still counts toward `max_total_bytes` (STANDARD-MODULES-2).
        const remaining = options.max_total_bytes - self.totalBytes();
        const limit = if (standard != null) remaining else @min(options.max_file_bytes, remaining);
        const served: ?[]u8 = if (standard != null and options.standard.from_provider) provider.read(provider.context, allocator, path, limit) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => null,
        } else null;
        const served_local = served != null;
        const bytes = if (served) |text| text else if (standard) |library| try allocator.dupe(u8, library) else provider.read(provider.context, allocator, path, limit) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            if (err == error.TooLarge) return self.fail(eProjectBytes, try budgetMessage(allocator, path, options, self.totalBytes(), standard != null), site, null);
            return self.fail("E_MODULE_READ", try std.fmt.allocPrint(allocator, "cannot load {s}: {s}", .{ path, @errorName(err) }), site, null);
        };
        if (bytes.len > limit) return self.fail(eProjectBytes, try budgetMessage(allocator, path, options, self.totalBytes(), standard != null), site, null);
        self.counts.bytes += bytes.len;
        const source_path = if (standard_library.source(path) != null and !served_local) try std.fmt.allocPrint(allocator, "@stdlib/{s}", .{path}) else path;
        // The header record's key and the module digest are the same digest of the same bytes: hash them once.
        const hashed = provider.records != null or options.digests != .deferred;
        if (hashed) self.modules.items[id].digest = digestOfRead(provider, path, bytes, standard != null and !served_local);
        if (options.digests == .with_sha256) {
            var taken: [32]u8 = undefined;
            @import("sha256_portable.zig").hash(bytes, &taken);
            self.modules.items[id].state.sha256 = taken;
        }
        // The module keeps the bytes it read: no second copy.
        self.modules.items[id].src = try source.Source.initOwned(allocator, source_path, bytes);
        // A provider-served standard source keeps the reserved internal names
        // only when its bytes are exactly the compiler's own source.
        if (served_local) if (standard) |library| {
            self.modules.items[id].src.trusted_intrinsics = std.mem.eql(u8, bytes, library);
        };
        if (!hashed) self.modules.items[id].state.digest_pending = true;
        try self.header(id, options, provider.records, scratch);
        try self.readEmbeds(provider, id, path, options);
        return id;
    }
    /// The digest of the bytes the provider returned for `path`: the one it vouches for, else the hash of the bytes (which it is told).
    /// The compiler's own embedded sources (`embedded`) are not the provider's to vouch for.
    fn digestOfRead(provider: Provider, path: []const u8, bytes: []const u8, embedded: bool) [32]u8 {
        if (embedded) return source_digest.of(bytes);
        if (provider.vouch) |vouch| if (vouch(provider.context, path, bytes)) |known| return known;
        const taken = source_digest.of(bytes);
        if (provider.learned) |learn| learn(provider.context, path, taken);
        return taken;
    }
    /// Read the file behind each embed call `header` found in module `id`, whose
    /// file is `path` beneath the import root. Without a provider hook they stay unresolved.
    fn readEmbeds(self: *Project, provider: Provider, id: usize, path: []const u8, options: Options) diagnostic.Error!void {
        const read_embed = provider.embed orelse return;
        const embeds: []source.Embed = @constCast(self.modules.items[id].src.embeds);
        const allocator = self.arena.allocator();
        for (embeds, 0..) |*entry, at| {
            if (priorEmbed(embeds[0..at], entry.path)) |previous| {
                entry.status = previous.status;
                entry.contents = previous.contents;
                entry.digest = previous.digest;
                continue;
            }
            const limit = @min(embed.size_cap, @min(options.max_file_bytes, options.max_total_bytes - self.totalBytes()));
            const outcome = try read_embed(provider.context, allocator, path, entry.path, limit);
            if ((outcome.status == .too_large and limit < embed.size_cap) or outcome.contents.len > limit) {
                return self.fail(eProjectBytes, try budgetMessage(allocator, entry.path, options, self.totalBytes(), false), .{ .module = id, .span = entry.literal }, null);
            }
            if (outcome.status == .ok) self.counts.embedded_bytes += outcome.contents.len;
            entry.status = outcome.status;
            entry.contents = outcome.contents;
            if (outcome.status == .ok) embed.digest(outcome.contents, &entry.digest);
        }
    }
    fn priorEmbed(entries: []const source.Embed, path: []const u8) ?source.Embed {
        for (entries) |entry| if (std.mem.eql(u8, entry.path, path)) return entry;
        return null;
    }
    fn totalBytes(self: *const Project) usize {
        return self.counts.bytes + self.counts.embedded_bytes;
    }
    /// Materialize deferred receipt hashes from the exact immutable source
    /// snapshots already loaded, without consulting the provider a second time.
    pub fn ensureSourceDigests(self: *Project) void {
        if (self.progress.source_digests_ready) return;
        for (self.modules.items) |*module| if (module.state.digest_pending) {
            module.digest = source_digest.of(module.src.bytes);
            module.state.digest_pending = false;
        };
        self.progress.source_digests_ready = true;
    }
    /// Load the reachable import graph iteratively while enforcing source, embedded-file and graph limits.
    pub fn load(self: *Project, provider: Provider, entry: []const u8, options: Options) LoadError!void {
        if (self.progress.started) return error.ProjectAlreadyLoaded;
        self.progress.started = true;
        self.progress.source_digests_ready = options.digests != .deferred;
        self.progress.hidden_standard = options.standard.hidden;
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
        var work: std.ArrayList(Visit) = .empty;
        defer work.deinit(allocator);
        self.modules.items[root].state.traversal = .visiting;
        try work.append(allocator, .{ .id = root });
        while (work.items.len != 0) {
            const index = work.items.len - 1;
            const visit = work.items[index];
            if (visit.next == self.modules.items[visit.id].imports.len) {
                self.modules.items[visit.id].state.traversal = .complete;
                try self.order.append(allocator, visit.id);
                _ = work.pop();
                continue;
            }
            work.items[index].next += 1;
            const imported = self.modules.items[visit.id].imports[visit.next];
            const site: Site = .{ .module = visit.id, .span = imported.span };
            if (try hiddenImportMessage(allocator, imported.name)) |message| return self.fail("E_INTERNAL_NAME", message, site, null);
            const target = try self.intern(provider, imported.name, site, options, &scratch);
            self.modules.items[visit.id].imports[visit.next].target = target;
            switch (self.modules.items[target].state.traversal) {
                .complete => {},
                .unseen => {
                    self.modules.items[target].state.traversal = .visiting;
                    try work.append(allocator, .{ .id = target });
                },
                .visiting => return self.fail("E_IMPORT_CYCLE", try self.cycleMessage(work.items, target), site, .{ .module = target, .span = self.modules.items[target].header.declaration }),
            }
        }
        self.progress.complete = true;
    }
    /// The `E_IMPORT_CYCLE` message: the chain of modules from `target` round to `target`, then what each module of it uses
    /// from the next and the way out (F-73). It runs only when a cycle is found, so a program without one pays nothing:
    /// the uses are read by lexing the modules of the cycle again.
    fn cycleMessage(self: *Project, stack: []const Visit, target: usize) error{OutOfMemory}![]const u8 {
        const allocator = self.arena.allocator();
        var first: usize = 0;
        while (stack[first].id != target) first += 1;
        const members = stack[first..];
        var chain: std.Io.Writer.Allocating = .init(allocator);
        for (members) |at| chain.writer.print("{s} -> ", .{self.modules.items[at.id].name}) catch return error.OutOfMemory;
        chain.writer.writeAll(self.modules.items[target].name) catch return error.OutOfMemory;
        const edges = try allocator.alloc(import_cycle.Edge, members.len);
        for (members, edges) |at, *edge| {
            const module = self.modules.items[at.id];
            // `next` was advanced past the import being followed before the walk went into it.
            const followed = at.next - 1;
            edge.* = .{
                .from = module.name,
                .to = self.modules.items[module.imports[followed].target].name,
                .uses = try importUses(allocator, module, followed),
            };
        }
        chain.writer.writeAll(": ") catch return error.OutOfMemory;
        chain.writer.writeAll(try import_cycle.explain(allocator, edges)) catch return error.OutOfMemory;
        return chain.toOwnedSlice();
    }
    fn header(self: *Project, id: usize, options: Options, records: ?module_records.Records, scratch: *std.heap.ArenaAllocator) diagnostic.Error!void {
        if (records) |store| if (try self.restoreHeader(id, options, store)) return;
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
            const failure = self.fail(problem.code, problem.message, .{ .module = id, .span = problem.span }, null);
            // A removed spelling's rename stays a structured fix in a project
            // module too, so `selka fix` migrates it (FIX-MIGRATION-CAPTURE-1).
            if (problem.provenance.fix) |fix| {
                self.problem.?.fix = fix.edit;
                self.problem.?.fix_more = fix.more;
            }
            return failure;
        };
        var scanner: Scanner = .{ .project = self, .id = id, .tokens = tokens };
        _ = try self.moduleDeclaration(&scanner, options.legacy_headers);
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
        try markQualifiedImports(scratch.allocator(), src, tokens, self.modules.items[id].header.body_start, self.modules.items[id].imports);
        self.modules.items[id].header.usage_scanned = true;
        // The tokens are in hand, so find the module's embed calls here rather than lexing again.
        if (embed.mayEmbed(src.bytes)) self.modules.items[id].src.embeds = try embed.sites(allocator, src, tokens);
        if (records) |store| self.storeHeader(id, options, store);
    }

    /// The record key of a module's header facts: its bytes' digest and whether legacy headers are read.
    fn headerKey(content: [32]u8, legacy: bool) [32]u8 {
        const flavour: []const u8 = if (legacy) "legacy" else "current";
        return module_records.recordKey(module_records.header_domain, &.{ &content, flavour });
    }

    /// Apply the stored header facts of module `id` when they exist under its bytes and the
    /// import budget still admits every import. Only a header that was valid when stored has a
    /// record, so a miss, a damaged record or a tighter budget falls through to lexing, which
    /// reports any error exactly as it did before records existed.
    fn restoreHeader(self: *Project, id: usize, options: Options, store: module_records.Records) error{OutOfMemory}!bool {
        const allocator = self.arena.allocator();
        const module = &self.modules.items[id];
        const payload = store.fetch(store.context, allocator, headerKey(module.digest, options.legacy_headers)) orelse return false;
        const facts = (try module_records.decodeHeader(allocator, payload)) orelse return false;
        const size = module.src.bytes.len;
        if (facts.body_start > size) return false;
        if (facts.declaration) |span| if (span.end > size or !options.legacy_headers) return false;
        if (self.counts.imports +| facts.imports.len > options.max_imports) return false;
        for (facts.imports) |item| if (item.span.end > size) return false;
        for (facts.exports) |item| if (item.span.end > size) return false;
        for (facts.embeds) |item| if (item.literal.end > size) return false;
        const imports = try allocator.alloc(Import, facts.imports.len);
        for (facts.imports, imports) |item, *slot| slot.* = .{ .name = item.name, .alias = item.alias, .span = .{ .start = item.span.start, .end = item.span.end }, .seen = item.seen };
        const exports = try allocator.alloc(Export, facts.exports.len);
        for (facts.exports, exports) |item, *slot| slot.* = .{ .name = item.name, .span = .{ .start = item.span.start, .end = item.span.end }, .alias = item.alias };
        if (facts.embeds.len != 0) {
            const embeds = try allocator.alloc(source.Embed, facts.embeds.len);
            for (facts.embeds, embeds) |item, *slot| slot.* = .{ .literal = .{ .start = item.literal.start, .end = item.literal.end }, .path = item.path, .text = item.text };
            module.src.embeds = embeds;
        }
        if (facts.declaration) |span| module.header.declaration = .{ .start = span.start, .end = span.end };
        module.header.body_start = facts.body_start;
        module.imports = imports;
        module.exports = exports;
        module.header.usage_scanned = true;
        self.counts.imports += imports.len;
        return true;
    }

    /// Keep the header facts header discovery just accepted for module `id`, under its bytes. A
    /// record that cannot be encoded or kept is only a later miss.
    fn storeHeader(self: *Project, id: usize, options: Options, store: module_records.Records) void {
        const allocator = self.arena.allocator();
        const module = self.modules.items[id];
        const imports = allocator.alloc(module_records.ImportFact, module.imports.len) catch return;
        for (module.imports, imports) |item, *slot| slot.* = .{ .name = item.name, .alias = item.alias, .span = .{ .start = item.span.start, .end = item.span.end }, .seen = item.seen };
        const exports = allocator.alloc(module_records.ExportFact, module.exports.len) catch return;
        for (module.exports, exports) |item, *slot| slot.* = .{ .name = item.name, .span = .{ .start = item.span.start, .end = item.span.end }, .alias = item.alias };
        const embeds = allocator.alloc(module_records.EmbedFact, module.src.embeds.len) catch return;
        for (module.src.embeds, embeds) |item, *slot| slot.* = .{ .literal = .{ .start = item.literal.start, .end = item.literal.end }, .path = item.path, .text = item.text };
        const declared = module.header.declaration;
        const declaration: ?module_records.Range = if (options.legacy_headers and declared.end > declared.start) .{ .start = declared.start, .end = declared.end } else null;
        const payload = module_records.encodeHeader(allocator, .{ .body_start = module.header.body_start, .declaration = declaration, .imports = imports, .exports = exports, .embeds = embeds }) catch return;
        store.store(store.context, headerKey(module.digest, options.legacy_headers), payload);
    }
    /// Paths determine module identity. Migration may consume a redundant header.
    fn moduleDeclaration(self: *Project, scanner: *Scanner, legacy_headers: bool) diagnostic.Error!?ModuleName {
        if (!scanner.isWord("module")) return null;
        const start = scanner.tokens[scanner.pos].span;
        scanner.pos += 1;
        const declared = try scanner.name();
        const end = try scanner.expect(.semicolon);
        if (!legacy_headers) {
            const span: source.Span = .join(start, end.span);
            const failure = self.fail(eModuleHeader, "module names come from file paths; remove the redundant module header", .{ .module = scanner.id, .span = span }, null);
            self.problem.?.fix = .{ .span = span, .text = "" };
            return failure;
        }
        self.modules.items[scanner.id].header.declaration = declared.span;
        return declared;
    }
    /// Allocate the completed dependency graph report; reject incomplete loading state.
    pub fn render(self: *Project, allocator: std.mem.Allocator) RenderError![]u8 {
        if (!self.progress.complete) return error.IncompleteProject;
        var output: std.Io.Writer.Allocating = .init(allocator);
        errdefer output.deinit();
        output.writer.writeAll("module graph v1; header discovery only; bodies/exports/types not checked\n") catch return error.OutOfMemory;
        for (self.order.items) |id| {
            const module = self.modules.items[id];
            output.writer.print("module {s} path={s} sha256={s}\n", .{ module.name, module.src.path, std.fmt.bytesToHex(sha256Of(module), .lower) }) catch return error.OutOfMemory;
            for (module.imports) |imported| output.writer.print("  import {s} as {s}\n", .{ self.modules.items[imported.target].name, imported.alias }) catch return error.OutOfMemory;
        }
        return output.toOwnedSlice();
    }
    /// Allocate the current project diagnostic with source locations.
    pub fn renderProblem(self: *Project, allocator: std.mem.Allocator) RenderProblemError![]u8 {
        const problem = self.problem orelse return error.NoProblem;
        if (problem.recovered.len != 0) {
            var output: std.ArrayList(u8) = .empty;
            errdefer output.deinit(allocator);
            for (problem.recovered) |item| {
                const text = try item.render(allocator, self.modules.items[problem.site.module].src);
                defer allocator.free(text);
                try output.appendSlice(allocator, text);
            }
            return output.toOwnedSlice(allocator);
        }
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
/// One module on the walk's stack: its index and how many of its imports the walk has taken up.
const Visit = struct { id: usize, next: usize = 0 };
/// Mark every import some dotted reference after the header qualifies: for each
/// `a.b.c` chain the longest matching qualifier marks the first import it names. This is
/// the scan the unused-import warning needs, taken from the header's tokens. A format
/// string is one token, so the holes of each `f"..."` literal are lexed and read the same
/// way while some import is still unmarked; a name used only there is a use.
pub fn markQualifiedImports(scratch: std.mem.Allocator, src: source.Source, tokens: []const lex.Token, body_start: usize, imports: []Import) error{OutOfMemory}!void {
    var marker: SeenMarker = .{ .imports = imports };
    return scanQualified(&marker, scratch, src, tokens, body_start, imports);
}
/// The visitor behind `markQualifiedImports`: a use sets the import's `seen`, and a format string's holes are read only
/// while some import is still unseen.
const SeenMarker = struct {
    imports: []Import,
    fn use(self: *SeenMarker, index: usize, qualifier: []const u8, member: []const u8) error{OutOfMemory}!void {
        _ = qualifier;
        _ = member;
        self.imports[index].seen = true;
    }
    fn holesMatter(self: *const SeenMarker) bool {
        for (self.imports) |imported| if (!imported.seen) return true;
        return false;
    }
};
/// The visitor behind an import cycle's message (F-73): the distinct qualified names, as written, that read one import.
const UseCollector = struct {
    allocator: std.mem.Allocator,
    import_index: usize,
    names: std.ArrayList([]const u8) = .empty,
    fn use(self: *UseCollector, index: usize, qualifier: []const u8, member: []const u8) error{OutOfMemory}!void {
        if (index != self.import_index) return;
        const written = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ qualifier, member });
        for (self.names.items) |known| if (std.mem.eql(u8, known, written)) return;
        try self.names.append(self.allocator, written);
    }
    fn holesMatter(self: *const UseCollector) bool {
        _ = self;
        return true;
    }
};
/// The qualified names `module` reads from its import number `import_index`, in the order they first appear, found by
/// lexing the module again.
fn importUses(allocator: std.mem.Allocator, module: Module, import_index: usize) error{OutOfMemory}![]const []const u8 {
    var sink: diagnostic.Sink = .{ .allocator = allocator };
    const tokens = lex.lex(allocator, module.src.bytes, &sink) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return &.{},
    };
    // The scan gives each qualifier to the first import that names it, so every import is offered and the collector keeps
    // the uses of this one.
    var collector: UseCollector = .{ .allocator = allocator, .import_index = import_index };
    try scanQualified(&collector, allocator, module.src, tokens, module.header.body_start, module.imports);
    return collector.names.items;
}
/// Walk the dotted references after the header and tell `visitor` which import each one qualifies: `use(import index,
/// qualifier, member)`, and `holesMatter()` before the holes of a format string are read. A comptime visitor, so the walk
/// that sets `seen` costs what it did.
fn scanQualified(visitor: anytype, scratch: std.mem.Allocator, src: source.Source, tokens: []const lex.Token, body_start: usize, imports: []const Import) error{OutOfMemory}!void {
    if (imports.len == 0) return;
    const bytes = src.bytes;
    var index: usize = 0;
    while (index < tokens.len) : (index += 1) {
        if (tokens[index].tag == .format) {
            try scanHoleImports(visitor, scratch, src, tokens[index].span, body_start, imports);
            continue;
        }
        if (tokens[index].tag != .ident) continue;
        if (tokens[index].span.start < body_start) continue;
        var last = index;
        var cursor = index + 1;
        while (cursor + 1 < tokens.len and tokens[cursor].tag == .dot and tokens[cursor + 1].tag == .ident) {
            last = cursor + 1;
            cursor += 2;
        }
        if (last == index) continue;
        // A chain can end in a type member, e.g. object.Obj.string.
        // Resolve the longest matching module qualifier, never a bare name.
        var member = last;
        found: while (member > index) : (member -= 2) {
            const qualifier = bytes[tokens[index].span.start..tokens[member - 2].span.end];
            for (imports, 0..) |imported, at| {
                if (!imported.matches(qualifier)) continue;
                try visitor.use(at, qualifier, bytes[tokens[member].span.start..tokens[member].span.end]);
                break :found;
            }
        }
        index = last;
    }
}
/// `scanQualified` over the interpolation holes of one `f"..."` literal, nested literals included.
fn scanHoleImports(visitor: anytype, scratch: std.mem.Allocator, src: source.Source, literal: source.Span, body_start: usize, imports: []const Import) error{OutOfMemory}!void {
    // A qualified name needs a dot, and a literal with no unmarked import to find has nothing to add.
    if (!visitor.holesMatter() or std.mem.indexOfScalar(u8, src.text(literal), '.') == null) return;
    var sink: diagnostic.Sink = .{ .allocator = scratch };
    const pieces = format_strings.split(scratch, src, literal, &sink) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return,
    };
    for (pieces) |piece| {
        const hole = switch (piece) {
            .hole => |inner| inner,
            else => continue,
        };
        const tokens = lex.lexRange(scratch, src.bytes, hole, &sink) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => continue,
        };
        try scanQualified(visitor, scratch, src, tokens, body_start, imports);
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
/// `selka.json` field that raises it. A standard module is never refused by the per-file budget, so its refusal is always the total one.
fn budgetMessage(allocator: std.mem.Allocator, path: []const u8, options: Options, loaded: usize, standard: bool) error{OutOfMemory}![]const u8 {
    if (standard or options.max_total_bytes - loaded < options.max_file_bytes) {
        return std.fmt.allocPrint(allocator, "cannot load {s}: the project's source and embedded inputs exceed the {d}-byte max_total_bytes budget; raise budgets.max_total_bytes in selka.json", .{ path, options.max_total_bytes });
    }
    return std.fmt.allocPrint(allocator, "cannot load {s}: the file exceeds the {d}-byte max_file_bytes budget; raise budgets.max_file_bytes in selka.json", .{ path, options.max_file_bytes });
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
/// The leading of a module-name segment that stands for a hidden folder or file: `__hidden_tmp` is `.tmp`. A file under a hidden
/// folder of its project (`.tmp/scratch.selka`) is an entry of that project, named `__hidden_tmp.scratch`; `modulePath` reads the
/// name back as the path it came from. A real segment that begins this way is reserved for it.
pub const hidden_segment_prefix = "__hidden_";

/// The `E_INTERNAL_NAME` message for an import that spells a hidden folder (`import __hidden_tmp.x`): the spelling is the compiler's
/// own name for an entry under a hidden folder, so source never imports it. Null for any other name.
fn hiddenImportMessage(allocator: std.mem.Allocator, name: []const u8) error{OutOfMemory}!?[]const u8 {
    var parts = std.mem.splitScalar(u8, name, '.');
    while (parts.next()) |part| {
        if (!std.mem.startsWith(u8, part, hidden_segment_prefix) or part.len == hidden_segment_prefix.len) continue;
        const path = modulePath(allocator, name) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidModuleName => name,
        };
        const spelling = "`{s}` spells `{s}`, a file under a hidden folder: hidden folders cannot be imported (a module-name segment that begins `{s}` is the " ++
            "compiler's name for running such a file as an entry); move the module out of the hidden folder to import it";
        const message = try std.fmt.allocPrint(allocator, spelling, .{ name, path, hidden_segment_prefix });
        return message;
    }
    return null;
}

/// Allocate the relative source path corresponding to a valid dotted module name.
pub fn modulePath(allocator: std.mem.Allocator, name: []const u8) ModulePathError![]u8 {
    if (!validName(name)) return error.InvalidModuleName;
    var path: std.ArrayList(u8) = .empty;
    errdefer path.deinit(allocator);
    var parts = std.mem.splitScalar(u8, name, '.');
    while (parts.next()) |part| {
        if (path.items.len != 0) try path.append(allocator, '/');
        if (std.mem.startsWith(u8, part, hidden_segment_prefix) and part.len > hidden_segment_prefix.len) {
            try path.append(allocator, '.');
            try path.appendSlice(allocator, part[hidden_segment_prefix.len..]);
        } else try path.appendSlice(allocator, part);
    }
    try path.appendSlice(allocator, product.source_suffix);
    return path.toOwnedSlice(allocator);
}
