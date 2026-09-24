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
/// Export snapshot and the safety/accounting policy one native emission runs under.
pub const native_interface = @import("native_interface.zig");
/// Per-function reuse of emitted QBE units across builds.
pub const qbe_fragments = @import("qbe_fragments.zig");
const project_syntax = @import("project_syntax.zig");
pub const interfaces = @import("interfaces.zig");
pub const check_cache = @import("check_cache.zig");
/// Changed-source semantic function queries with fresh global validation.
pub const semantic_cache = @import("semantic_cache.zig");
/// Per-function check summaries that stand in for unchanged bodies in `check`.
pub const semantic_summary = @import("semantic_summary.zig");
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
pub const lexer = @import("lexer.zig");
/// `tokens-v1` machine output used as the stage-0 lexer oracle.
pub const tokens_dump = @import("tokens_dump.zig");
const parser = @import("parser.zig");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const sema = @import("sema.zig");
const lower = @import("lower.zig");
pub const bytecode = @import("bytecode.zig");
pub const effect_set = @import("effect_set.zig");
pub const navigation = @import("navigation.zig");
pub const navigation_partial = @import("navigation_partial.zig");
/// `index-project`'s summary, selection and full documents.
pub const navigation_views = @import("navigation_views.zig");
/// Syntax-derived test reachability for a project whose bodies do not check.
pub const navigation_syntax = @import("navigation_syntax.zig");
pub const quality = @import("quality.zig");
pub const duplicates = @import("duplicates.zig");
/// `mylang lint` driver, rule registry and profiles.
pub const lint = @import("lint.zig");
/// Strict `lint` object inside `mylang.json`.
pub const lint_config = @import("lint_config.zig");
/// Shared declaration-span-to-diff mapping for the commit-time rules.
pub const declaration_diff = @import("declaration_diff.zig");
/// `mylang test --affected` selection over the resolved call graph.
pub const affected_tests = @import("affected_tests.zig");
/// `mylang api-diff` baseline comparison and classification.
pub const api_diff = @import("api_diff.zig");
/// `mylang context` bounded per-declaration answer for a coding agent.
pub const context = @import("context.zig");
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
        self.tokens = try lexer.lex(sink.allocator, self.src.bytes, &sink);
        var p: parser.Parser = .{ .src = self.src, .arena = &self.arena, .tokens = self.tokens.?, .sink = &sink };
        self.syntax = try p.parse();
        if (cache) |disk| try disk.rememberSyntax(self.src, 0, self.syntax.?);
    }

    /// Allocate the canonical formatting of this unit. A file that opens with a
    /// `module` header or an `import` directive is a module file, so it is
    /// formatted with the module grammar rather than rejected at its first word.
    pub fn format(self: *Compilation, allocator: std.mem.Allocator) FormatError![]u8 {
        if (opensAsModule(self.src.bytes)) return self.formatModule(allocator);
        try self.parse();
        return @import("formatter.zig").format(allocator, self.src.bytes, self.tokens.?, self.syntax.?.types);
    }

    /// Parse module syntax and allocate its canonical formatting with the caller allocator.
    pub fn formatModule(self: *Compilation, allocator: std.mem.Allocator) FormatError![]u8 {
        var sink: diagnostic.Sink = .{ .allocator = self.arena.allocator(), .items = self.diagnostics };
        defer self.diagnostics = sink.items;
        const tokens = try lexer.lex(sink.allocator, self.src.bytes, &sink);
        var p: parser.Parser = .{ .src = self.src, .arena = &self.arena, .tokens = tokens, .sink = &sink };
        const syntax = try p.parseModule();
        return @import("formatter.zig").format(allocator, self.src.bytes, tokens, syntax.types);
    }

    /// Parse one module or single-file program and allocate its declaration listing.
    pub fn listDeclarations(self: *Compilation, allocator: std.mem.Allocator) declarations.Error![]u8 {
        var sink: diagnostic.Sink = .{ .allocator = self.arena.allocator(), .items = self.diagnostics };
        defer self.diagnostics = sink.items;
        const tokens = try lexer.lex(sink.allocator, self.src.bytes, &sink);
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
        if (self.code == null) {
            const lowered = try lower.lowerWith(self.arena.allocator(), self.program.?, drop_debug);
            self.code = try @import("bytecode_inline.zig").inlineProgram(self.arena.allocator(), lowered);
        }
    }

    /// Allocate independently compilable scalar QBE units after full checking.
    pub fn emitQbe(self: *Compilation, allocator: std.mem.Allocator) EmitNativeError![]u8 {
        return self.emitQbeWithOptions(allocator, .{});
    }

    /// Emit QBE units under an explicit debug, accounting and safety policy.
    pub fn emitQbeWithOptions(self: *Compilation, allocator: std.mem.Allocator, policy: @import("native_interface.zig").Policy) EmitNativeError![]u8 {
        try self.emitWithOptions(policy.drop_debug);
        var sink: diagnostic.Sink = .{ .allocator = self.arena.allocator(), .items = self.diagnostics };
        defer self.diagnostics = sink.items;
        return @import("qbe.zig").generateWithInterface(allocator, self.code.?, self.src, &sink, .{ .policy = policy });
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

/// Builtin vocabulary tables the compiler-derived reference engine reads. The
/// engine is compiled into the root module beside the other subcommands, which
/// cannot import these files directly without becoming a second module member,
/// so it names them through this one namespace instead of a copied list.
pub const reference_tables = struct {
    /// Familiar constructor spellings and the reserved prelude type names.
    pub const prelude = @import("prelude.zig");
    /// Builtin call names, arities and result types.
    pub const prelude_builtins = @import("prelude_builtins.zig");
    /// Managed collection method vocabulary and per-operation arities.
    pub const buffer_operations = @import("buffer_operations.zig");
    /// Host I/O builtin names and arities.
    pub const io_builtins = @import("io_builtins.zig");
    /// Scalar intrinsic names the checker accepts in call position.
    pub const float_intrinsics = @import("float_intrinsics.zig");
    /// Managed collection families a method spelling is accepted on.
    pub const runtime_values = @import("runtime_values.zig");
};

/// Opt-in per-command friction record. It reads the compiler's own diagnostic
/// and identity types, so it lives in this module and the command-line root
/// reaches it through `language.friction_log` rather than a second import.
pub const friction_log = @import("friction_log.zig");

/// Whether a source's first line that is neither blank nor a comment is a
/// `module` header or an `import` directive: the openings of a module file.
pub fn opensAsModule(source_bytes: []const u8) bool {
    var lines = std.mem.splitScalar(u8, source_bytes, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        for ([_][]const u8{ "module", "import" }) |word| {
            if (std.mem.startsWith(u8, line, word) and line.len > word.len and (line[word.len] == ' ' or line[word.len] == '\t')) return true;
        }
        return false;
    }
    return false;
}
