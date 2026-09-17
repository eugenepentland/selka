//! One request owns source, syntax, semantic nodes, and lowered instructions.
/// Failures returned by format; callers must handle these boundary errors.
pub const allocation_budget = @import("codec_memory.zig");
pub const FormatError = error{
    OutOfMemory,
    SourceError,
    InternalError,
};
/// Failures returned by emit; callers must handle these boundary errors.
pub const EmitError = error{
    InternalError,
    OutOfMemory,
    SourceError,
};
/// Failures returned by emitQbe; callers must handle these boundary errors.
pub const EmitNativeError = EmitError || error{
    WriteFailed,
};

const std = @import("std");
pub const schema_report = @import("schema_report.zig");
pub const schema = @import("schema.zig");
pub const input_manifest = @import("input_manifest.zig");
/// Deterministic source and compiler identities shared by every tool receipt.
pub const source_receipt = @import("source_receipt.zig");
pub const import_policy = @import("import_policy.zig");
pub const embedded_project = @import("embedded_project.zig");
pub const dependency_report = @import("dependency_report.zig");
pub const project_files = @import("project_files.zig");
pub const project_compile = @import("project_compile.zig");
const project_syntax = @import("project_syntax.zig");
pub const interfaces = @import("interfaces.zig");
pub const check_cache = @import("check_cache.zig");
/// Changed-source semantic function queries with fresh global validation.
pub const semantic_cache = @import("semantic_cache.zig");
pub const syntax_cache = @import("syntax_cache.zig");
/// Persistent content-addressed frontend reuse for ordinary one-shot commands.
pub const frontend_cache = @import("frontend_cache.zig");
pub const project = @import("project.zig");
pub const source = @import("source.zig");
pub const diagnostic = @import("diagnostic.zig");
/// Versioned diagnostic rendering for CLI and tool consumers.
pub const diagnostic_output = @import("diagnostic_output.zig");
/// Trusted typed host registration and copied-value callback boundary.
/// Program-bound registration adapter for explicitly declared VM host functions.
/// Parse-only top-level declaration listing for store and tooling consumers.
pub const declarations = @import("declarations.zig");
/// Checked mechanical translation from the legacy brace surface to Python syntax.
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const sema = @import("sema.zig");
const lower = @import("lower.zig");
pub const bytecode = @import("bytecode.zig");
pub const effect_set = @import("effect_set.zig");
pub const navigation = @import("navigation.zig");
pub const navigation_partial = @import("navigation_partial.zig");
pub const quality = @import("quality.zig");
pub const duplicates = @import("duplicates.zig");
const disassemble = @import("disassemble.zig");

/// Owns one source unit and all parsed, checked, and lowered data in its arena.
pub const Compilation = struct {
    arena: std.heap.ArenaAllocator,
    src: source.Source,
    diagnostics: std.ArrayList(diagnostic.Diagnostic) = .empty,
    tokens: ?[]const lexer.Token = null,
    syntax: ?ast.Program = null,
    program: ?typed.Program = null,
    code: ?bytecode.Program = null,

    /// Copy the source path and bytes into a new compilation arena; release with deinit.
    pub fn init(allocator: std.mem.Allocator, path: []const u8, bytes: []const u8) std.mem.Allocator.Error!Compilation {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const src = try source.Source.init(arena.allocator(), path, bytes);
        return .{ .arena = arena, .src = src };
    }

    /// Like `init`, but mark the source as compiler-owned so it may spell reserved
    /// internal intrinsics. Only the parser's own unit tests reach this hook.
    pub fn initTrusted(allocator: std.mem.Allocator, path: []const u8, bytes: []const u8) std.mem.Allocator.Error!Compilation {
        var result = try init(allocator, path, bytes);
        result.src.trusted_intrinsics = true;
        return result;
    }

    pub fn deinit(self: *Compilation) void {
        self.arena.deinit();
    }

    /// Lazily tokenize and parse the source, retaining syntax and source diagnostics.
    pub fn parse(self: *Compilation) diagnostic.Error!void {
        return self.parseCached(null);
    }
    /// Parse through an optional persistent cache. A disk hit still rebuilds all
    /// interface, resolution and semantic state; only the lexer and parser are skipped.
    pub fn parseCached(self: *Compilation, cache: ?*frontend_cache.Cache) diagnostic.Error!void {
        if (self.syntax != null) return;
        if (cache) |disk| {
            if (try disk.lookupSyntax(self.arena.allocator(), self.src, 0)) |syntax| {
                self.syntax = syntax;
                return;
            }
        }
        var sink: diagnostic.Sink = .{ .allocator = self.arena.allocator(), .items = self.diagnostics };
        defer self.diagnostics = sink.items;
        self.tokens = try lexer.lexWithMarkers(sink.allocator, self.src.bytes, self.src.mutation_markers, &sink);
        var p: parser.Parser = .{ .src = self.src, .arena = &self.arena, .tokens = self.tokens.?, .sink = &sink };
        self.syntax = try p.parse();
        if (cache) |disk| try disk.rememberSyntax(self.src, 0, self.syntax.?);
    }

    pub fn format(self: *Compilation, allocator: std.mem.Allocator) FormatError![]u8 {
        try self.parse();
        return @import("formatter.zig").format(allocator, self.src.bytes, self.tokens.?, self.syntax.?.types);
    }

    /// Parse module syntax and allocate its canonical formatting with the caller allocator.
    pub fn formatModule(self: *Compilation, allocator: std.mem.Allocator) FormatError![]u8 {
        var sink: diagnostic.Sink = .{ .allocator = self.arena.allocator(), .items = self.diagnostics };
        defer self.diagnostics = sink.items;
        const tokens = try lexer.lexWithMarkers(sink.allocator, self.src.bytes, self.src.mutation_markers, &sink);
        var p: parser.Parser = .{ .src = self.src, .arena = &self.arena, .tokens = tokens, .sink = &sink };
        const syntax = try p.parseModule();
        return @import("formatter.zig").format(allocator, self.src.bytes, tokens, syntax.types);
    }

    /// Parse one module or single-file program and allocate its declaration listing.
    pub fn listDeclarations(self: *Compilation, allocator: std.mem.Allocator) declarations.Error![]u8 {
        var sink: diagnostic.Sink = .{ .allocator = self.arena.allocator(), .items = self.diagnostics };
        defer self.diagnostics = sink.items;
        const tokens = try lexer.lexWithMarkers(sink.allocator, self.src.bytes, self.src.mutation_markers, &sink);
        return declarations.render(allocator, &self.arena, self.src, tokens, &sink);
    }

    /// Lazily type-check parsed syntax and retain the checked program.
    pub fn check(self: *Compilation) diagnostic.Error!void {
        return self.checkWithCache(null);
    }
    /// Check through an optional persistent syntax cache. Declaration, interface
    /// and whole-program validation always run; only source lexing and parsing
    /// may be skipped.
    pub fn checkWithFrontend(self: *Compilation, cache: ?*frontend_cache.Cache) diagnostic.Error!void {
        if (self.program != null) return;
        for (self.diagnostics.items) |item| if (item.severity == .err) return error.SourceError;
        try self.parseCached(cache);
        var sink: diagnostic.Sink = .{ .allocator = self.arena.allocator(), .items = self.diagnostics };
        defer self.diagnostics = sink.items;
        self.program = try sema.checkCached(sink.allocator, self.src, self.syntax.?, &sink, null, null);
    }
    /// Reuse independently owned checked bodies after supported source edits.
    pub fn checkWithCache(self: *Compilation, cache: ?*semantic_cache.Cache) diagnostic.Error!void {
        if (self.program != null) return;
        for (self.diagnostics.items) |item| if (item.severity == .err) return error.SourceError;
        try self.parse();
        var sink: diagnostic.Sink = .{ .allocator = self.arena.allocator(), .items = self.diagnostics };
        defer self.diagnostics = sink.items;
        self.program = try sema.checkCached(sink.allocator, self.src, self.syntax.?, &sink, null, cache);
    }

    /// Lazily lower the checked program into bytecode owned by the compilation.
    pub fn emit(self: *Compilation) EmitError!void {
        return self.emitWithOptions(false);
    }

    /// Lower with an explicit `debug` policy: a ReleaseFast build drops the nodes.
    pub fn emitWithOptions(self: *Compilation, drop_debug: bool) EmitError!void {
        try self.check();
        if (self.code == null) self.code = try lower.lowerWith(self.arena.allocator(), self.program.?, drop_debug);
    }

    /// Allocate independently compilable scalar QBE units after full checking.
    pub fn emitQbe(self: *Compilation, allocator: std.mem.Allocator) EmitNativeError![]u8 {
        return self.emitQbeWithOptions(allocator, false);
    }

    /// Emit QBE units under an explicit `debug` policy.
    pub fn emitQbeWithOptions(self: *Compilation, allocator: std.mem.Allocator, drop_debug: bool) EmitNativeError![]u8 {
        try self.emitWithOptions(drop_debug);
        var sink: diagnostic.Sink = .{ .allocator = self.arena.allocator(), .items = self.diagnostics };
        defer self.diagnostics = sink.items;
        return @import("qbe.zig").generate(allocator, self.code.?, self.src, &sink);
    }

    /// Allocate a source-annotated disassembly of the lowered program.
    pub fn dump(self: *Compilation, allocator: std.mem.Allocator) EmitError![]u8 {
        try self.emit();
        return disassemble.dump(allocator, self.code.?, self.src);
    }
};

/// Trusted directory and endpoint scoped resource adapters for application hosts.
pub const scoped_providers = @import("scoped_providers.zig");

/// Injected read-only environment provider contract for application hosts.
pub const environment = @import("environment.zig");

/// Shared runtime value and type identities named by host provider adapters.
pub const values = @import("value.zig");

/// Opt-in structured phase timing for command-line hosts.
pub const timings = @import("timings.zig");
