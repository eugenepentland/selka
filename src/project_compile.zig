//! Full semantic checking over relocated module syntax and explicit namespaces.
const invariant_callbacks = @import("invariant_callbacks.zig");
/// Failures returned by init; callers must handle these boundary errors.
pub const InitError = error{
    EmptySourceMap,
    IncompleteProject,
    InvalidNodeId,
    InvalidSourceIndex,
    InvalidSourceSpan,
    InvalidStatementId,
    NestedSourceMap,
    OutOfMemory,
    Overflow,
};
/// Failures returned by check; callers must handle these boundary errors.
pub const CheckError = error{
    OutOfMemory,
    SourceError,
    InternalError,
};
/// Failures returned by emitNativeTestFactsScoped; callers must handle these boundary errors.
pub const FactsError = CheckError || error{WriteFailed};
/// Which functions a test-facts schema is rooted at: `.all` every discovered
/// test and export, `.closure` the tests and exported `bench_` functions alone.
pub const FactsScope = enum { all, closure };
/// Failures returned by publicValueType; callers must handle these boundary errors.
pub const PublicValueTypeError = error{
    OutOfMemory,
    SourceError,
    UnknownPublicValueType,
    InternalError,
};

const std = @import("std");
const ast = @import("ast.zig");
const interfaces = @import("interfaces.zig");
const syntax = @import("project_syntax.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");
const diagnostic = @import("diagnostic.zig");
const Names = @import("module_names.zig").Names;
const semantic_cache = @import("semantic_cache.zig");
const sema = @import("sema.zig");
/// Project-level checked state borrowing the interface index and its arena.
pub const Compilation = struct {
    index: *interfaces.Index,
    src: source.Source,
    syntax: @import("ast.zig").Program,
    diagnostics: diagnostic.Sink,
    program: ?typed.Program = null,
    /// Merge indexed modules into a compilation whose storage belongs to the project arena.
    pub fn init(index: *interfaces.Index) InitError!Compilation {
        const merged = try syntax.build(index);
        return .{ .index = index, .src = merged.src, .syntax = merged.syntax, .diagnostics = .{ .allocator = index.project.arena.allocator() } };
    }
    /// Type-check merged module bodies and enforce exported signature boundaries.
    pub fn check(self: *Compilation) CheckError!void {
        return self.checkWithCache(null);
    }
    /// Validate library bodies, imports, effects and exports without requiring main.
    /// Success is deliberately not retained as an executable checked program.
    pub fn checkLibrary(self: *Compilation) CheckError!void {
        for (self.diagnostics.items.items) |item| if (item.severity == .err) return error.SourceError;
        var names: Names = .{ .index = self.index, .src = self.src };
        try sema.checkLibrary(self.index.project.arena.allocator(), self.src, self.syntax, &self.diagnostics, &names);
    }
    /// Whether the entry module (the first input) declares a free function named `main`.
    pub fn declaresMain(self: *const Compilation) bool {
        return sema.declaresMain(self.src, self.syntax);
    }
    /// Reuse supported function queries while checking fresh module/type/effect dependencies.
    pub fn checkWithCache(self: *Compilation, cache: ?*semantic_cache.Cache) CheckError!void {
        if (self.program != null) return;
        for (self.diagnostics.items.items) |item| if (item.severity == .err) return error.SourceError;
        var names: Names = .{ .index = self.index, .src = self.src };
        // Bind this project's lexical module/import identities so semantic
        // dependency resolution is per-module instead of global-by-spelling.
        if (cache) |semantic| semantic.resolution = self.index;
        const before = self.diagnostics.items.items.len;
        const counters = if (cache) |semantic| Counters.save(semantic) else null;
        self.program = sema.checkCached(self.index.project.arena.allocator(), self.src, self.syntax, &self.diagnostics, &names, cache) catch |err| retry: {
            // A check whose stood-in bodies met a changed cross-function fact
            // repeats in full, from the same diagnostics and work counters.
            const semantic = cache orelse return err;
            const request = semantic.context.summaries orelse return err;
            if (err != error.SourceError or !request.retry) return err;
            self.diagnostics.items.shrinkRetainingCapacity(before);
            counters.?.restore(semantic);
            request.* = .{ .facts_only = request.facts_only };
            break :retry try sema.checkCached(self.index.project.arena.allocator(), self.src, self.syntax, &self.diagnostics, &names, cache);
        };
    }

    /// Work counters a repeated check restores, so it reports one check's work.
    const Counters = struct {
        functions: semantic_cache.Statistics,
        symbolic: @import("generic_cache.zig").Statistics,
        specializations: @import("generic_specializations.zig").Statistics,

        fn save(cache: *const semantic_cache.Cache) Counters {
            return .{ .functions = cache.statistics, .symbolic = cache.reuse.symbolic.statistics, .specializations = cache.reuse.specializations.statistics };
        }
        fn restore(self: Counters, cache: *semantic_cache.Cache) void {
            cache.statistics = self.functions;
            cache.reuse.symbolic.statistics = self.symbolic;
            cache.reuse.specializations.statistics = self.specializations;
        }
    };
    /// The checked facts `mylang test` reads about a project's tests: a JSON
    /// object whose `schema` member is the public schema (`schema_graph.zig`,
    /// as a JSON string) of every function `scope` selects, including the
    /// parameters of private `@test` functions. It reads the checked program and
    /// the declaration index alone.
    pub fn emitNativeTestFactsScoped(self: *Compilation, allocator: std.mem.Allocator, scope: FactsScope) FactsError![]u8 {
        try self.check();
        const roots = if (scope == .all) try self.testRoots(allocator) else try self.testEntryRoots(allocator);
        defer allocator.free(roots);
        const schema = @import("schema_graph.zig").render(allocator, self.index, self.program.?, roots) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.SourceError => return error.SourceError,
            else => return error.InternalError,
        };
        defer allocator.free(schema);
        return std.json.Stringify.valueAlloc(allocator, .{ .version = "test-facts-v1", .schema = schema }, .{});
    }

    /// The functions `mylang test` can select: every discovered test and every
    /// exported `bench_` function.
    fn testEntryRoots(self: *Compilation, allocator: std.mem.Allocator) CheckError![]typed.FunctionId {
        try self.check();
        var roots: std.ArrayList(typed.FunctionId) = .empty;
        errdefer roots.deinit(allocator);
        for (self.program.?.functions) |function| {
            const at = std.mem.lastIndexOf(u8, function.name, "::");
            const short = if (at) |position| function.name[position + 2 ..] else function.name;
            const benchmark = std.mem.startsWith(u8, short, "bench_") and try self.exported(function);
            if (benchmark or try self.discoveredTest(function)) try roots.append(allocator, function.id);
        }
        return roots.toOwnedSlice(allocator);
    }

    /// Allocate the function identities exposed by the checked public interface.
    pub fn exportRoots(self: *Compilation, allocator: @import("std").mem.Allocator) CheckError![]typed.FunctionId {
        try self.check();
        var roots: @import("std").ArrayList(typed.FunctionId) = .empty;
        errdefer roots.deinit(allocator);
        for (self.program.?.functions) |function| {
            if (try self.exported(function)) try roots.append(allocator, function.id);
        }
        return roots.toOwnedSlice(allocator);
    }
    /// Allocate the public interface roots plus every discovered test (a
    /// `test_`-prefixed or `@test` declaration), so a test is found by name
    /// without an explicit `export`. `exportRoots` keeps the export-only set.
    pub fn testRoots(self: *Compilation, allocator: @import("std").mem.Allocator) CheckError![]typed.FunctionId {
        try self.check();
        var count: usize = 0;
        for (self.program.?.functions) |function| {
            if (try self.exported(function) or try self.discoveredTest(function)) count += 1;
        }
        const roots = try allocator.alloc(typed.FunctionId, count);
        var index: usize = 0;
        for (self.program.?.functions) |function| {
            if (try self.exported(function) or try self.discoveredTest(function)) {
                roots[index] = function.id;
                index += 1;
            }
        }
        return roots;
    }
    /// Whether a function is a discovered test: a `test_`-prefixed module
    /// declaration, or any declaration carrying `@test`, without `export`.
    fn discoveredTest(self: *Compilation, function: typed.Function) error{InternalError}!bool {
        if (function.type_arguments.len != 0) return false;
        if (@import("std").mem.eql(u8, function.name, @import("entry_adapter.zig").wrapper_name)) return false;
        if (@import("std").mem.startsWith(u8, function.name, "lambda@")) return false;
        if (invariant_callbacks.isName(function.name)) return false;
        const original = self.src.originalSpan(function.declaration) catch return error.InternalError;
        if (original.input >= self.index.units.len or original.input >= self.index.project.modules.items.len) return error.InternalError;
        if (ast.hasAttribute(self.index.units[original.input].syntax, original.span, .@"test")) return true;
        const prefix_len = self.index.project.modules.items[original.input].name.len + 2;
        if (prefix_len > function.name.len) return error.InternalError;
        return std.mem.startsWith(u8, function.name[prefix_len..], "test_");
    }
    fn exported(self: *Compilation, function: typed.Function) error{InternalError}!bool {
        // Concrete instances are implementation details reachable through ordinary exports.
        if (function.type_arguments.len != 0) return false;
        // The synthesized entry wrapper of a unit or Result main has no declaration.
        if (@import("std").mem.eql(u8, function.name, @import("entry_adapter.zig").wrapper_name)) return false;
        // Expression lambdas are synthesized callable bodies, not module declarations.
        if (@import("std").mem.startsWith(u8, function.name, "lambda@")) return false;
        if (invariant_callbacks.isName(function.name)) return false;
        const original = self.src.originalSpan(function.declaration) catch return error.InternalError;
        if (original.input >= self.index.units.len or original.input >= self.index.project.modules.items.len) return error.InternalError;
        const unit = self.index.units[original.input];
        const prefix_len = self.index.project.modules.items[original.input].name.len + 2;
        if (prefix_len > function.name.len) return error.InternalError;
        return unit.symbols.items[unit.names.get(function.name[prefix_len..]) orelse return error.InternalError].exported;
    }
    /// Select an explicitly exported nominal type, or a built-in type.
    pub fn publicValueType(self: *Compilation, name: []const u8) PublicValueTypeError!typed.Type {
        try self.check();
        if (typed.Type.fromName(name)) |ty| return ty;
        for (self.program.?.aliases) |alias| {
            if (!@import("std").mem.eql(u8, name, alias.name)) continue;
            if (try self.exportedType(alias.declaration)) return alias.target;
        }
        for (self.program.?.records) |record| {
            if (!@import("std").mem.eql(u8, name, record.name) or record.shape.array != null) continue;
            if (try self.exportedType(record.declaration) and record.contract.public_arguments) return record.id;
        }
        return error.UnknownPublicValueType;
    }
    fn exportedType(self: *Compilation, declaration: source.Span) error{InternalError}!bool {
        const original = self.src.originalSpan(declaration) catch return error.InternalError;
        if (original.input >= self.index.units.len or original.input >= self.index.project.modules.items.len) return error.InternalError;
        const unit = self.index.units[original.input];
        const symbol = unit.symbols.items[unit.names.get(self.src.text(declaration)) orelse return error.InternalError];
        return symbol.exported and symbol.kind == .type;
    }
};
