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
const ast = @import("ast.zig");
const interfaces = @import("interfaces.zig");
const syntax = @import("project_syntax.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");
const diagnostic = @import("diagnostic.zig");
const Names = @import("module_names.zig").Names;
/// Which functions a native-test facts payload describes.
pub const FactsScope = native_test_facts.Scope;
const native_test_facts = @import("native_test_facts.zig");
const semantic_cache = @import("semantic_cache.zig");
/// Project-level checked and lowered state borrowing the interface index and its arena.
pub const Compilation = struct {
    index: *interfaces.Index,
    src: source.Source,
    syntax: @import("ast.zig").Program,
    diagnostics: diagnostic.Sink,
    program: ?typed.Program = null,
    code: ?@import("bytecode.zig").Program = null,
    /// Persistent per-function unit reuse for native emission, when the
    /// command has a fragment store (`QBE-FRAGMENT-REUSE-1`).
    reuse: ?@import("qbe_fragments.zig").Reuse = null,
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
    pub fn checkWithCache(self: *Compilation, cache: ?*semantic_cache.Cache) CheckError!void {
        if (self.program != null) return;
        for (self.diagnostics.items.items) |item| if (item.severity == .err) return error.SourceError;
        var names: Names = .{ .index = self.index, .src = self.src };
        // Bind this project's lexical module/import identities so semantic
        // dependency resolution is per-module instead of global-by-spelling.
        if (cache) |semantic| semantic.resolution = self.index;
        const before = self.diagnostics.items.items.len;
        const counters = if (cache) |semantic| Counters.save(semantic) else null;
        self.program = @import("sema.zig").checkCached(self.index.project.arena.allocator(), self.src, self.syntax, &self.diagnostics, &names, cache) catch |err| {
            // A check whose stood-in bodies met a changed cross-function fact
            // repeats in full, from the same diagnostics and work counters.
            const semantic = cache orelse return err;
            const request = semantic.context.summaries orelse return err;
            if (err != error.SourceError or !request.retry) return err;
            self.diagnostics.items.shrinkRetainingCapacity(before);
            counters.?.restore(semantic);
            request.* = .{ .facts_only = request.facts_only };
            self.program = try @import("sema.zig").checkCached(self.index.project.arena.allocator(), self.src, self.syntax, &self.diagnostics, &names, cache);
            return;
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
    /// Allocate independently compilable scalar QBE units after full project checking.
    pub fn emitQbe(self: *Compilation, allocator: @import("std").mem.Allocator) EmitNativeError![]u8 {
        return self.emitQbeWithOptions(allocator, .{});
    }

    /// Emit QBE units under an explicit debug, accounting and safety policy.
    pub fn emitQbeWithOptions(self: *Compilation, allocator: @import("std").mem.Allocator, policy: @import("native_interface.zig").Policy) EmitNativeError![]u8 {
        try self.emitWithOptions(policy.drop_debug);
        const roots = try self.exportRoots(allocator);
        defer allocator.free(roots);
        const schema = try self.renderSchema(allocator, roots);
        defer allocator.free(schema);
        return @import("qbe.zig").generateWithInterface(allocator, self.code.?, self.src, &self.diagnostics, .{ .roots = roots, .schema = schema, .policy = policy, .reuse = self.reuse });
    }

    /// Emit checked native-test dependency facts without lowering or QBE emission.
    ///
    /// The returned bytes are a `native-test-graph-v3` payload: schema plus each
    /// checked function's semantic fingerprint and dependency edges. It is the
    /// graph a warm `mylang test` loads before selecting result receipts.
    pub fn emitNativeTestFacts(self: *Compilation, allocator: @import("std").mem.Allocator) EmitNativeError![]u8 {
        return self.emitNativeTestFactsScoped(allocator, .all);
    }

    /// The facts payload of `emitNativeTestFacts` over `scope`: `.all` keeps
    /// every checked function under the public-interface roots, `.closure`
    /// describes only what the selectable tests and benchmarks reach, with a
    /// schema of just their signatures — everything a `mylang test` plan reads.
    pub fn emitNativeTestFactsScoped(self: *Compilation, allocator: @import("std").mem.Allocator, scope: FactsScope) EmitNativeError![]u8 {
        try self.check();
        const roots = if (scope == .all) try self.testRoots(allocator) else try self.testEntryRoots(allocator);
        defer allocator.free(roots);
        const schema = try self.renderSchema(allocator, roots);
        defer allocator.free(schema);
        return native_test_facts.render(allocator, self.src, self.program.?, roots, schema, scope) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InternalError,
        };
    }

    /// The functions `mylang test` can select: every discovered test and every
    /// exported `bench_` function.
    fn testEntryRoots(self: *Compilation, allocator: @import("std").mem.Allocator) CheckError![]typed.FunctionId {
        try self.check();
        var roots: @import("std").ArrayList(typed.FunctionId) = .empty;
        // UNTESTED-ERROR: allocation-failure cleanup; generic allocator-failure coverage exercises it and no deterministic OOM hook reaches it here.
        errdefer roots.deinit(allocator);
        for (self.program.?.functions) |function| {
            const at = @import("std").mem.lastIndexOf(u8, function.name, "::");
            const short = if (at) |position| function.name[position + 2 ..] else function.name;
            const benchmark = @import("std").mem.startsWith(u8, short, "bench_") and try self.exported(function);
            if (benchmark or try self.discoveredTest(function)) try roots.append(allocator, function.id);
        }
        return roots.toOwnedSlice(allocator);
    }

    /// Lower and emit only the selected functions (plus conservative runtime
    /// support). `names` are checked qualified function names borrowed by the
    /// caller. `stats` receives the closure width actually lowered and emitted.
    pub fn emitQbeSelected(self: *Compilation, allocator: @import("std").mem.Allocator, names: []const []const u8, stats: *SelectedStats) EmitNativeError![]u8 {
        try self.check();
        const selected = try self.selectFunctions(allocator, names);
        defer allocator.free(selected);
        native_test_facts.expandSelection(allocator, self.program.?, selected) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InternalError,
        };
        // Only a selected root is emitted, so only it needs an export and a
        // schema entry; the unselected rest of a large public interface would
        // cost a whole-program schema on every selective build.
        const roots = try self.selectedRoots(allocator, selected);
        defer allocator.free(roots);
        const schema = try self.renderSchema(allocator, roots);
        defer allocator.free(schema);
        var count: usize = 0;
        for (selected) |flag| count += @intFromBool(flag);
        const code = @import("lower.zig").lowerSelected(self.index.project.arena.allocator(), self.program.?, selected) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InternalError,
        };
        const inlined = @import("bytecode_inline.zig").inlineProgram(self.index.project.arena.allocator(), code) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InternalError,
        };
        stats.* = .{ .lowered_functions = count, .emitted_fragments = count };
        return @import("qbe.zig").generateSelectedWithInterface(allocator, inlined, self.src, &self.diagnostics, .{ .roots = roots, .schema = schema, .reuse = self.reuse }, selected) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.SourceError => return error.SourceError,
            error.WriteFailed => return error.WriteFailed,
            else => return error.InternalError,
        };
    }

    /// Lowering/emission counts for one selective native build.
    pub const SelectedStats = struct { lowered_functions: usize = 0, emitted_fragments: usize = 0 };

    /// Mark each named function, by one table lookup per name rather than a
    /// scan of every function per name. The first function of a repeated name
    /// is the one marked, as a front-to-back scan would find it.
    fn selectFunctions(self: *Compilation, allocator: @import("std").mem.Allocator, names: []const []const u8) CheckError![]bool {
        const functions = self.program.?.functions;
        var positions: std.StringHashMapUnmanaged(usize) = .empty;
        defer positions.deinit(allocator);
        try positions.ensureTotalCapacity(allocator, @intCast(functions.len));
        for (functions, 0..) |function, index| {
            const entry = positions.getOrPutAssumeCapacity(function.name);
            if (!entry.found_existing) entry.value_ptr.* = index;
        }
        const selected = try allocator.alloc(bool, functions.len);
        // UNTESTED-ERROR: a name the checked program lacks is an internal error the native-test planner never produces; the slice is released on it.
        errdefer allocator.free(selected);
        @memset(selected, false);
        for (names) |name| {
            if (name.len == 0) continue;
            selected[positions.get(name) orelse return error.InternalError] = true;
        }
        return selected;
    }

    /// The test-graph roots (`testRoots`) a selection actually emits.
    fn selectedRoots(self: *Compilation, allocator: @import("std").mem.Allocator, selected: []const bool) CheckError![]typed.FunctionId {
        const all = try self.testRoots(allocator);
        defer allocator.free(all);
        var roots: std.ArrayList(typed.FunctionId) = .empty;
        // UNTESTED-ERROR: allocation-failure cleanup; generic allocator-failure coverage exercises it and no deterministic OOM hook reaches it here.
        errdefer roots.deinit(allocator);
        for (all) |root| if (selected[@backingInt(root)]) try roots.append(allocator, root);
        return roots.toOwnedSlice(allocator);
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
    /// Allocate the function identities a native-test graph exposes: the public
    /// interface roots plus every `test_`-prefixed declaration, so a test is
    /// discovered by name without an explicit `export`. Ordinary builds keep
    /// the export-only `exportRoots` and are unaffected.
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
        return self.emitWithOptions(false);
    }

    /// Lower with an explicit `debug` policy: a ReleaseFast build drops the nodes.
    pub fn emitWithOptions(self: *Compilation, drop_debug: bool) EmitError!void {
        try self.check();
        if (self.code == null) {
            const lowered = try @import("lower.zig").lowerWith(self.index.project.arena.allocator(), self.program.?, drop_debug);
            self.code = try @import("bytecode_inline.zig").inlineProgram(self.index.project.arena.allocator(), lowered);
        }
    }
};
