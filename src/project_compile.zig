//! Full semantic checking over relocated module syntax and explicit namespaces.
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
/// Failures returned by emitQbe; callers must handle these boundary errors.
pub const EmitNativeError = error{
    InternalError,
    OutOfMemory,
    SourceError,
    WriteFailed,
};
/// Failures returned by publicValueType; callers must handle these boundary errors.
pub const PublicValueTypeError = error{
    OutOfMemory,
    SourceError,
    UnknownPublicValueType,
    InternalError,
};
/// Failures returned by emit; callers must handle these boundary errors.
pub const EmitError = error{
    InternalError,
    OutOfMemory,
    SourceError,
};

const std = @import("std");
const interfaces = @import("interfaces.zig");
const syntax = @import("project_syntax.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");
const diagnostic = @import("diagnostic.zig");
const Names = @import("module_names.zig").Names;
/// Project-level checked and lowered state borrowing the interface index and its arena.
pub const Compilation = struct {
    index: *interfaces.Index,
    src: source.Source,
    syntax: @import("ast.zig").Program,
    diagnostics: diagnostic.Sink,
    program: ?typed.Program = null,
    code: ?@import("bytecode.zig").Program = null,
    /// Merge indexed modules into a compilation whose storage belongs to the project arena.
    pub fn init(index: *interfaces.Index) InitError!Compilation {
        const merged = try syntax.build(index);
        return .{ .index = index, .src = merged.src, .syntax = merged.syntax, .diagnostics = .{ .allocator = index.project.arena.allocator() } };
    }
    /// Type-check merged module bodies and enforce exported signature boundaries.
    pub fn check(self: *Compilation) CheckError!void {
        return self.checkWithCache(null);
    }
    /// Reuse supported function queries while checking fresh module/type/effect dependencies.
    pub fn checkWithCache(self: *Compilation, cache: ?*@import("semantic_cache.zig").Cache) CheckError!void {
        if (self.program != null) return;
        for (self.diagnostics.items.items) |item| if (item.severity == .err) return error.SourceError;
        var names: Names = .{ .index = self.index, .src = self.src };
        // Bind this project's lexical module/import identities so semantic
        // dependency resolution is per-module instead of global-by-spelling.
        if (cache) |semantic| semantic.resolution = self.index;
        self.program = try @import("sema.zig").checkCached(self.index.project.arena.allocator(), self.src, self.syntax, &self.diagnostics, &names, cache);
    }
    /// Allocate independently compilable scalar QBE units after full project checking.
    pub fn emitQbe(self: *Compilation, allocator: @import("std").mem.Allocator) EmitNativeError![]u8 {
        try self.emit();
        const roots = try self.exportRoots(allocator);
        defer allocator.free(roots);
        const schema = try self.renderSchema(allocator, roots);
        defer allocator.free(schema);
        return @import("qbe.zig").generateWithInterface(allocator, self.code.?, self.src, &self.diagnostics, .{ .roots = roots, .schema = schema });
    }

    /// Emit checked native-test dependency facts without lowering or QBE emission.
    ///
    /// The returned bytes are a `native-test-graph-v3` payload: schema plus each
    /// checked function's semantic fingerprint and dependency edges. It is the
    /// graph a warm `mylang test` loads before selecting result receipts.
    pub fn emitNativeTestFacts(self: *Compilation, allocator: @import("std").mem.Allocator) EmitNativeError![]u8 {
        try self.check();
        const roots = try self.exportRoots(allocator);
        defer allocator.free(roots);
        const schema = try self.renderSchema(allocator, roots);
        defer allocator.free(schema);
        return @import("native_test_facts.zig").render(allocator, self.src, self.program.?, roots, schema) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InternalError,
        };
    }

    /// Lower and emit only the selected functions (plus conservative runtime
    /// support). `names` are checked qualified function names borrowed by the
    /// caller. `stats` receives the closure width actually lowered and emitted.
    pub fn emitQbeSelected(self: *Compilation, allocator: @import("std").mem.Allocator, names: []const []const u8, stats: *SelectedStats) EmitNativeError![]u8 {
        try self.check();
        const roots = try self.exportRoots(allocator);
        defer allocator.free(roots);
        const schema = try self.renderSchema(allocator, roots);
        defer allocator.free(schema);
        const selected = try self.selectFunctions(allocator, names);
        defer allocator.free(selected);
        @import("native_test_facts.zig").expandSelection(allocator, self.program.?, selected) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InternalError,
        };
        var count: usize = 0;
        for (selected) |flag| count += @intFromBool(flag);
        const code = @import("lower.zig").lowerSelected(self.index.project.arena.allocator(), self.program.?, selected) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InternalError,
        };
        stats.* = .{ .lowered_functions = count, .emitted_fragments = count };
        return @import("qbe.zig").generateSelectedWithInterface(allocator, code, self.src, &self.diagnostics, .{ .roots = roots, .schema = schema }, selected) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.SourceError => return error.SourceError,
            error.WriteFailed => return error.WriteFailed,
            else => return error.InternalError,
        };
    }

    /// Lowering/emission counts for one selective native build.
    pub const SelectedStats = struct { lowered_functions: usize = 0, emitted_fragments: usize = 0 };

    fn selectFunctions(self: *Compilation, allocator: @import("std").mem.Allocator, names: []const []const u8) CheckError![]bool {
        const selected = try allocator.alloc(bool, self.program.?.functions.len);
        @memset(selected, false);
        for (names) |name| {
            if (name.len == 0) continue;
            var found = false;
            for (self.program.?.functions, 0..) |function, index| {
                if (std.mem.eql(u8, function.name, name)) {
                    selected[index] = true;
                    found = true;
                    break;
                }
            }
            if (!found) return error.InternalError;
        }
        return selected;
    }

    fn renderSchema(self: *Compilation, allocator: @import("std").mem.Allocator, roots: []const typed.FunctionId) EmitNativeError![]u8 {
        return @import("schema_graph.zig").render(allocator, self.index, self.program.?, roots) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.SourceError => return error.SourceError,
            else => return error.InternalError,
        };
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
    fn exported(self: *Compilation, function: typed.Function) error{InternalError}!bool {
        // Concrete instances are implementation details reachable through ordinary exports.
        if (function.type_arguments.len != 0) return false;
        // The synthesized entry wrapper of a unit or Result main has no declaration.
        if (@import("std").mem.eql(u8, function.name, @import("entry_adapter.zig").wrapper_name)) return false;
        // Expression lambdas are synthesized callable bodies, not module declarations.
        if (@import("std").mem.startsWith(u8, function.name, "lambda@")) return false;
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
    /// Lazily lower the checked project into its retained bytecode representation.
    pub fn emit(self: *Compilation) EmitError!void {
        try self.check();
        if (self.code == null) self.code = try @import("lower.zig").lower(self.index.project.arena.allocator(), self.program.?);
    }
};
