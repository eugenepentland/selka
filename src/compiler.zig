//! One request owns source, syntax, semantic nodes, and lowered instructions.
/// Failures returned by format; callers must handle these boundary errors.
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
/// Failures returned by emitC; callers must handle these boundary errors.
pub const EmitCError = EmitError || error{
    WriteFailed,
};

/// Failures returned by execute; callers must handle these boundary errors.
pub const ExecuteError = EmitError || error{
    BorrowConflict,
    BorrowSuspended,
    Bounds,
    CapabilityUnavailable,
    CapacityLimit,
    ChildrenActive,
    Closed,
    Denied,
    ExpiredBorrow,
    Failed,
    ForeignMemory,
    IdentityExhausted,
    InvalidAggregateType,
    InvalidAllocation,
    InvalidBudget,
    InvalidCapability,
    InvalidDataType,
    InvalidDataValue,
    InvalidOwner,
    InvalidProvider,
    InvalidValueLimits,
    MemoryClosed,
    NoCapacity,
    NotDataType,
    ReadOnly,
    RegionInUse,
    ResourceLimit,
    TypeMismatch,
    Unavailable,
    ValueCountLimit,
    ValueDepthLimit,
    ValueTypeMismatch,
};

const std = @import("std");
pub const codec_json = @import("codec_json.zig");
pub const typed_json = @import("typed_json.zig");
pub const schema_report = @import("schema_report.zig");
pub const schema = @import("schema.zig");
pub const input_manifest = @import("input_manifest.zig");
pub const evaluation_report = @import("evaluation_report.zig");
pub const evaluation = @import("evaluation.zig");
pub const import_policy = @import("import_policy.zig");
pub const embedded_project = @import("embedded_project.zig");
pub const dependency_report = @import("dependency_report.zig");
pub const project_files = @import("project_files.zig");
pub const project_compile = @import("project_compile.zig");
const project_syntax = @import("project_syntax.zig");
pub const interfaces = @import("interfaces.zig");
pub const check_cache = @import("check_cache.zig");
pub const syntax_cache = @import("syntax_cache.zig");
pub const project = @import("project.zig");
pub const source = @import("source.zig");
pub const diagnostic = @import("diagnostic.zig");
/// Versioned diagnostic rendering for CLI and tool consumers.
pub const diagnostic_output = @import("diagnostic_output.zig");
/// Trusted typed host registration and copied-value callback boundary.
pub const host_functions = @import("host_functions.zig");
/// Program-bound registration adapter for explicitly declared VM host functions.
pub const vm_host = @import("vm_host.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const sema = @import("sema.zig");
const lower = @import("lower.zig");
pub const bytecode = @import("bytecode.zig");
pub const navigation_partial = @import("navigation_partial.zig");
pub const navigation = @import("navigation.zig");
pub const quality = @import("quality.zig");
pub const duplicates = @import("duplicates.zig");
pub const vm = @import("vm.zig");
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

    pub fn deinit(self: *Compilation) void {
        self.arena.deinit();
    }

    /// Lazily tokenize and parse the source, retaining syntax and source diagnostics.
    pub fn parse(self: *Compilation) diagnostic.Error!void {
        if (self.syntax != null) return;
        var sink: diagnostic.Sink = .{ .allocator = self.arena.allocator(), .items = self.diagnostics };
        defer self.diagnostics = sink.items;
        self.tokens = try lexer.lex(sink.allocator, self.src.bytes, &sink);
        var p: parser.Parser = .{ .src = self.src, .arena = &self.arena, .tokens = self.tokens.?, .sink = &sink };
        self.syntax = try p.parse();
    }

    pub fn format(self: *Compilation, allocator: std.mem.Allocator) FormatError![]u8 {
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

    /// Lazily type-check parsed syntax and retain the checked program.
    pub fn check(self: *Compilation) diagnostic.Error!void {
        if (self.program != null) return;
        for (self.diagnostics.items) |item| if (item.severity == .err) return error.SourceError;
        try self.parse();
        var sink: diagnostic.Sink = .{ .allocator = self.arena.allocator(), .items = self.diagnostics };
        defer self.diagnostics = sink.items;
        self.program = try sema.check(sink.allocator, self.src, self.syntax.?, &sink);
    }

    /// Lazily lower the checked program into bytecode owned by the compilation.
    pub fn emit(self: *Compilation) EmitError!void {
        try self.check();
        if (self.code == null) self.code = try lower.lower(self.arena.allocator(), self.program.?);
    }

    /// Execute the lowered entry point using the default VM limits and providers.
    pub fn execute(self: *Compilation, allocator: std.mem.Allocator) ExecuteError!vm.Result {
        return self.executeWithOptions(allocator, .{});
    }

    /// Execute the lowered entry point with explicit VM limits and host providers.
    pub fn executeWithOptions(self: *Compilation, allocator: std.mem.Allocator, options: vm.Options) ExecuteError!vm.Result {
        try self.emit();
        return vm.runWithOptions(allocator, self.code.?, options);
    }

    /// Validate native support and allocate C source with the caller allocator.
    pub fn emitC(self: *Compilation, allocator: std.mem.Allocator) EmitCError![]u8 {
        try self.emit();
        var sink: diagnostic.Sink = .{ .allocator = self.arena.allocator(), .items = self.diagnostics };
        defer self.diagnostics = sink.items;
        return @import("native.zig").generate(allocator, self.code.?, self.src, &sink);
    }

    /// Allocate a source-annotated disassembly of the lowered program.
    pub fn dump(self: *Compilation, allocator: std.mem.Allocator) EmitError![]u8 {
        try self.emit();
        return disassemble.dump(allocator, self.code.?, self.src);
    }
};

/// Trusted directory and endpoint scoped resource adapters for application hosts.
pub const scoped_providers = @import("scoped_providers.zig");
