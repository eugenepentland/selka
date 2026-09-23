//! Source-pinned compiler navigation facts, independent of VM execution.
const std = @import("std");
const typed = @import("typed.zig");
const source = @import("source.zig");
const pc = @import("project_compile.zig");
const receipt = @import("source_receipt.zig");
const walk = @import("typed_walk.zig");
const uses_type = "uses_type";
const effect_set = @import("effect_set.zig");
const fact_status = @import("fact_status.zig");
const tests_index = @import("tests_index.zig");
/// Analysis limits prevent an inspection request from producing unbounded graphs.
pub const Limits = struct { symbols: usize = 50000, references: usize = 250000 };
/// Allocation, malformed internal locations, and bounded index exhaustion are distinct.
pub const Error = error{ OutOfMemory, NavigationLimit, InternalError, IncompleteProject };
/// Original half-open byte range with one-based diagnostic coordinates.
pub const Location = struct { path: []const u8, start: usize, end: usize, line: usize, column: usize };
/// Declaration identity is qualified by module and owner, never by its current line number.
pub const Symbol = struct {
    id: []const u8,
    name: []const u8,
    kind: []const u8,
    location: Location,
    exported: bool = false,
    details: Details = .{},
    context: Context = .{},

    const Details = struct {
        signature: []const u8 = "",
        type_name: []const u8 = "",
        /// How much of this declaration's contract the run analyzed. The default
        /// is lexical-only because the one constructor that leaves it unset is
        /// the partial renderer's lexical candidate list, which resolved nothing;
        /// every symbol `Builder` publishes states its own status.
        analysis: fact_status.Status = .lexical_only,
        effects: []const []const u8 = &.{},
        mutates: []const u16 = &.{},
        return_origin: []const u8 = "unknown",
        mutation_writes: bool = false,
    };
    const Context = struct { snippet: []const u8 = "", snippet_truncated: bool = false };

    /// Keep the navigation-v1 wire format flat while grouping internal facts.
    ///
    /// A symbol whose facts were checked publishes exactly the field set this
    /// command always published, so every previously checked answer stays
    /// byte-identical. A symbol whose inferred summary is unavailable publishes
    /// an explicit `analysis` status and `null` for every inferred field —
    /// effects, mutation positions, the return-origin bound and the managed-write
    /// flag — so a conservative or missing analysis can never be read as an
    /// empty fact.
    pub fn jsonStringify(self: Symbol, writer: anytype) !void {
        if (self.details.analysis != .checked) {
            const unavailable_effects: ?[]const []const u8 = null;
            const unavailable_mutates: ?[]const u16 = null;
            const unavailable_origin: ?[]const u8 = null;
            const unavailable_writes: ?bool = null;
            try writer.write(.{
                .id = self.id,
                .name = self.name,
                .kind = self.kind,
                .location = self.location,
                .exported = self.exported,
                .signature = self.details.signature,
                .type_name = self.details.type_name,
                .analysis = fact_status.name(self.details.analysis),
                .effects = unavailable_effects,
                .mutates = unavailable_mutates,
                .return_origin = unavailable_origin,
                .mutation_writes = unavailable_writes,
                .snippet = self.context.snippet,
                .snippet_truncated = self.context.snippet_truncated,
            });
            return;
        }
        try writer.write(.{
            .id = self.id,
            .name = self.name,
            .kind = self.kind,
            .location = self.location,
            .exported = self.exported,
            .signature = self.details.signature,
            .type_name = self.details.type_name,
            .effects = self.details.effects,
            .mutates = self.details.mutates,
            .return_origin = self.details.return_origin,
            .mutation_writes = self.details.mutation_writes,
            .snippet = self.context.snippet,
            .snippet_truncated = self.context.snippet_truncated,
        });
    }
};
/// A resolved syntactic relationship; it does not claim dynamic execution or test coverage.
pub const Reference = struct { from: []const u8, to: []const u8, kind: []const u8, location: Location };
fn originName(origin: typed.ReturnOrigin) []const u8 {
    return switch (origin) {
        .fresh => "fresh",
        .params => "params",
        .unknown => "unknown",
    };
}

/// The status of a declaration before any typed entry is attached. A declaration
/// in a checked program stays `checked`, so a checked answer keeps exactly the
/// field set this command always published; an unchecked one separates a
/// callable, whose inferred summary is missing, from a type declaration, whose
/// declared shape is complete without a body.
fn declarationAnalysis(checked: bool, is_function: bool) fact_status.Status {
    if (checked) return .checked;
    return if (is_function) .declaration_only else .declared;
}

/// The status of a function declaration once the merged syntax is known:
/// `template` when the declaration is generic and this program holds no
/// instantiation of it, and `declaration-only` when the program carries no entry
/// for the declaration at all. `functionFacts` promotes every symbol a typed
/// entry covers back to `checked`.
fn functionAnalysis(checked: bool, generic: bool) fact_status.Status {
    if (!checked) return .declaration_only;
    if (generic) return .template;
    return .declaration_only;
}

const Builder = struct {
    allocator: std.mem.Allocator,
    compilation: *pc.Compilation,
    limits: Limits,
    symbols: std.ArrayList(Symbol) = .empty,
    references: std.ArrayList(Reference) = .empty,
    declarations: std.AutoHashMapUnmanaged(usize, usize) = .empty,

    fn location(self: *Builder, span: source.Span) Error!Location {
        const src = self.compilation.src;
        const original = src.originalSpan(span) catch return error.InternalError;
        const at = src.locate(span.start);
        return .{ .path = at.path, .start = original.span.start, .end = original.span.end, .line = at.line, .column = at.column };
    }
    fn add(self: *Builder, span: source.Span, symbol: Symbol) Error!void {
        if (self.declarations.contains(span.start)) return;
        if (self.symbols.items.len >= self.limits.symbols) return error.NavigationLimit;
        try self.declarations.put(self.allocator, span.start, self.symbols.items.len);
        try self.symbols.append(self.allocator, symbol);
    }
    fn id(self: *Builder, declaration: source.Span) ?[]const u8 {
        const index = self.declarations.get(declaration.start) orelse return null;
        return self.symbols.items[index].id;
    }
    fn edge(self: *Builder, from: []const u8, to: ?[]const u8, kind: []const u8, span: source.Span) Error!void {
        const target = to orelse return;
        if (self.references.items.len >= self.limits.references) return error.NavigationLimit;
        try self.references.append(self.allocator, .{ .from = from, .to = target, .kind = kind, .location = try self.location(span) });
    }
    fn declarationsFromSyntax(self: *Builder) Error!void {
        const compilation = self.compilation;
        const checked = compilation.program != null;
        for (compilation.index.units, 0..) |unit, module_id| {
            const module = compilation.index.project.modules.items[module_id];
            for (unit.symbols.items) |symbol| {
                const span = compilation.src.mappedSpan(module_id, symbol.span) catch return error.InternalError;
                const qualified = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ module.name, symbol.name });
                try self.add(span, .{
                    .id = qualified,
                    .name = symbol.name,
                    .kind = @tagName(symbol.kind),
                    .location = try self.location(span),
                    .exported = symbol.exported,
                    .details = .{ .analysis = declarationAnalysis(checked, symbol.kind == .function) },
                });
            }
        }
        for (compilation.syntax.functions) |function| {
            const slot = self.declarations.get(function.name.start) orelse continue;
            const body = compilation.syntax.statements.items[@backingInt(function.body)].span;
            const name_at = compilation.src.originalSpan(function.name) catch return error.InternalError;
            const body_at = compilation.src.originalSpan(body) catch return error.InternalError;
            if (name_at.input != body_at.input) return error.InternalError;
            const original = compilation.index.project.modules.items[name_at.input].src;
            const start = name_at.span.start;
            const stop = excerptEnd(original.bytes, start, body_at.span.end);
            self.symbols.items[slot].details.type_name = compilation.src.text(function.signature.return_type);
            self.symbols.items[slot].details.signature = original.bytes[start..body_at.span.start];
            self.symbols.items[slot].details.analysis = functionAnalysis(checked, function.signature.type_parameters.len != 0);
            self.symbols.items[slot].context.snippet = original.bytes[start..stop];
            self.symbols.items[slot].context.snippet_truncated = stop != body_at.span.end;
        }
        for (compilation.syntax.types.records) |record| {
            const owner = self.id(record.name) orelse continue;
            for (record.fields) |field| {
                const name = compilation.src.text(field.name);
                try self.add(field.name, .{
                    .id = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ owner, name }),
                    .name = name,
                    .kind = "field",
                    .location = try self.location(field.name),
                    .details = .{ .analysis = declarationAnalysis(checked, false), .type_name = compilation.src.text(field.ty) },
                });
            }
        }
        for (compilation.syntax.types.variants) |variant| {
            const owner = self.id(variant.name) orelse continue;
            for (variant.cases) |item| {
                const name = compilation.src.text(item.name);
                try self.add(item.name, .{
                    .id = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ owner, name }),
                    .name = name,
                    .kind = "case",
                    .location = try self.location(item.name),
                    .details = .{ .analysis = declarationAnalysis(checked, false) },
                });
            }
        }
    }
    fn typeDeclarationId(self: *Builder, span: source.Span) ?[]const u8 {
        const index = self.declarations.get(span.start) orelse return null;
        const symbol = self.symbols.items[index];
        if (!std.mem.eql(u8, symbol.kind, "type")) return null;
        return symbol.id;
    }
    fn typeId(self: *Builder, program: typed.Program, ty: typed.Type) ?[]const u8 {
        if (!ty.isAggregate()) return null;
        return self.typeDeclarationId(program.records[ty.recordIndex()].declaration);
    }
    fn scopedId(self: *Builder, owner: []const u8, kind: []const u8, name: []const u8, span: source.Span) Error![]const u8 {
        const at = try self.location(span);
        return std.fmt.allocPrint(self.allocator, "{s}/{s}:{s}@{d}", .{ owner, kind, name, at.start });
    }
    fn fieldId(self: *Builder, program: typed.Program, ty: typed.Type, index: usize) ?[]const u8 {
        if (!ty.isAggregate()) return null;
        const fields = program.records[ty.recordIndex()].fields;
        if (index >= fields.len) return null;
        return self.id(fields[index].declaration);
    }
    fn functionFacts(self: *Builder, program: typed.Program, function: typed.Function) Error!void {
        const owner = self.id(function.declaration) orelse return;
        const slot = self.declarations.get(function.declaration.start).?;
        // This declaration has a typed entry, so its inferred facts are checked
        // facts whatever the declaration-level status started as.
        self.symbols.items[slot].details.analysis = .checked;
        if (function.type_arguments.len == 0) self.symbols.items[slot].details.type_name = typed.typeName(function.signature.return_type, program.records);
        var effects: std.ArrayList([]const u8) = .empty;
        // E2: navigation reports the published ceiling for exported functions.
        // That ceiling is the signature's own — the effects the parameter list
        // implies, narrowed by an explicit clause — so a body edit that stays
        // inside it cannot change what the index publishes. Private helpers keep
        // their inferred summary because they have no published contract.
        const navigation_mask = if (self.symbols.items[slot].exported)
            @import("effects.zig").effectiveCeiling(program.records, function)
        else
            function.policy.effects;
        var merged = navigation_mask;
        for (self.symbols.items[slot].details.effects) |name| {
            const prior = std.meta.stringToEnum(effect_set.Effect, name) orelse return error.InternalError;
            merged |= effect_set.bit(prior);
        }
        inline for (std.meta.tags(effect_set.Effect)) |effect| {
            if (merged & effect_set.bit(effect) != 0) try effects.append(self.allocator, @tagName(effect));
        }
        self.symbols.items[slot].details.effects = try effects.toOwnedSlice(self.allocator);
        self.symbols.items[slot].details.mutates = if (self.symbols.items[slot].exported and function.policy.effect_bound != null)
            function.signature.declared_mutates
        else
            function.signature.mutates;
        self.symbols.items[slot].details.return_origin = if (self.symbols.items[slot].exported and function.policy.effect_bound != null)
            "unknown"
        else
            originName(function.signature.return_origin);
        self.symbols.items[slot].details.mutation_writes = function.signature.mutation_facts.writes;
        try self.edge(owner, self.typeId(program, function.signature.return_type), "returns", function.declaration);
        for (function.scope.locals, 0..) |local, i| {
            if (local.usage.temporary) continue;
            try self.add(local.declaration, .{
                .id = try self.scopedId(owner, "local", local.name, local.declaration),
                .name = local.name,
                .kind = if (i < function.signature.parameter_count) "parameter" else "local",
                .location = try self.location(local.declaration),
                .details = .{ .analysis = .checked, .type_name = typed.typeName(local.ty, program.records) },
            });
            try self.edge(owner, self.typeId(program, local.ty), if (i < function.signature.parameter_count) "accepts" else uses_type, local.declaration);
        }
        var walker = try walk.Walker.init(self.allocator, program, function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| switch (item) {
            .expression => |node_id| try self.expression(program, function, owner, program.nodes[@backingInt(node_id)]),
            .statement => |statement_id| {
                const statement = program.statements[@backingInt(statement_id)];
                switch (statement.data) {
                    .assign, .initialize => |store| try self.edge(owner, self.id(function.scope.locals[@backingInt(store.slot)].declaration), "write", statement.span),
                    else => {},
                }
            },
        };
    }
    fn expression(self: *Builder, program: typed.Program, function: typed.Function, owner: []const u8, node: typed.Node) Error!void {
        try self.edge(owner, self.typeId(program, node.ty), uses_type, node.span);
        switch (node.data) {
            .function_value => |target| try self.edge(owner, self.id(program.functions[@backingInt(target)].declaration), "function_value", node.span),
            .call => |call| try self.edge(owner, self.id(program.functions[@backingInt(call.function)].declaration), "call", node.span),
            .local => |local| try self.edge(owner, self.id(function.scope.locals[@backingInt(local)].declaration), "read", node.span),
            .field => |field| try self.edge(owner, self.fieldId(program, program.nodes[@backingInt(field.base)].ty, field.index), "field_read", node.span),
            .record => |fields| for (fields) |field| {
                try self.edge(owner, self.fieldId(program, node.ty, field.index), "field_initialize", node.span);
            },
            .update => |update| for (update.fields) |field| {
                try self.edge(owner, self.fieldId(program, node.ty, field.index), "field_update", node.span);
            },
            else => {},
        }
    }
};
/// The identities an answer is pinned to: the compiler that produced it and the
/// loaded source it was produced from.
pub const Snapshot = struct { implementation: receipt.Implementation, inputs: []const receipt.Input };

/// Every declaration and resolved reference one frontend pass produced, owned by
/// their arena until `deinit`. `render` publishes these as `navigation-v1`;
/// `context.zig` reads the same tables instead of paying for a second pass.
pub const Facts = struct {
    arena: std.heap.ArenaAllocator,
    symbols: []const Symbol,
    references: []const Reference,
    snapshot: Snapshot,
    snapshot_sha256: []const u8,
    checked: bool,

    /// Release the arena every slice above points into.
    pub fn deinit(self: *Facts) void {
        self.arena.deinit();
    }

    /// The declaration with one exact identity, or null when this pass did not
    /// produce it. A source position never selects through this helper.
    pub fn symbol(self: *const Facts, id: []const u8) ?*const Symbol {
        for (self.symbols) |*item| {
            if (std.mem.eql(u8, item.id, id)) return item;
        }
        return null;
    }
};

/// Collect source-indexed declarations and checked references in one pass over
/// the merged compilation. Failed checking yields declarations only; every
/// symbol then carries the status of the analysis behind it.
pub fn collect(allocator: std.mem.Allocator, compilation: *pc.Compilation, identity: receipt.Identity, limits: Limits) Error!Facts {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const scratch = arena.allocator();
    var builder: Builder = .{ .allocator = scratch, .compilation = compilation, .limits = limits };
    try builder.declarationsFromSyntax();
    if (compilation.program) |program| {
        for (program.functions) |function| try builder.functionFacts(program, function);
        for (program.records) |record| {
            const owner = builder.typeDeclarationId(record.declaration) orelse continue;
            for (record.fields) |field| try builder.edge(owner, builder.typeId(program, field.ty), "contains_type", field.declaration);
        }
    }
    // Body resolution can attach a diagnostic after the complete load; keep the
    // exact loaded-source receipt without treating that diagnostic as a missing file.
    var loaded = compilation.index.project.*;
    loaded.problem = null;
    const snapshot: Snapshot = .{ .implementation = try receipt.implementation(scratch, identity), .inputs = try receipt.inputs(scratch, &loaded) };
    const digest = try receipt.digest(scratch, snapshot);
    return .{
        .arena = arena,
        .symbols = builder.symbols.items,
        .references = builder.references.items,
        .snapshot = snapshot,
        .snapshot_sha256 = digest,
        .checked = compilation.program != null,
    };
}

/// Render source-indexed declarations and checked references; failed checking
/// yields declarations only. Every symbol carries the status of the analysis
/// behind it: a checked symbol publishes its inferred facts exactly as before,
/// and a symbol whose facts were not checked publishes `null` for each inferred
/// field plus that status, so an empty array is never a stand-in for "unknown".
pub fn render(allocator: std.mem.Allocator, compilation: *pc.Compilation, identity: receipt.Identity, limits: Limits) Error![]u8 {
    var facts = try collect(allocator, compilation, identity, limits);
    defer facts.deinit();
    return std.json.Stringify.valueAlloc(allocator, .{
        .version = "navigation-v1",
        .checked = facts.checked,
        .reference_scope = "resolved concrete bodies and specializations; generic declarations indexed; static edges are not runtime coverage",
        .snapshot_sha256 = facts.snapshot_sha256,
        .snapshot = facts.snapshot,
        .symbols = facts.symbols,
        .references = facts.references,
    }, .{});
}

fn excerptEnd(bytes: []const u8, start: usize, end: usize) usize {
    var stop = @min(end, start + 16384);
    while (stop < end and bytes[stop] & 0xc0 == 0x80) stop -= 1;
    return stop;
}

/// Find the checked function with one exact qualified name.
fn findFunction(program: typed.Program, subject: []const u8) ?typed.FunctionId {
    for (program.functions, 0..) |function, index| {
        if (std.mem.eql(u8, function.name, subject)) return @fromBackingInt(@intCast(index));
    }
    return null;
}

/// Render the `tests-for` answer for one qualified declaration: the discovered
/// tests that call it directly and every test that reaches it transitively.
/// Returns null when no checked function carries that name.
pub fn renderTestsFor(allocator: std.mem.Allocator, compilation: *pc.Compilation, subject: []const u8) Error!?[]u8 {
    const program = compilation.program.?;
    const target = findFunction(program, subject) orelse return null;
    // The reachability walk lives in `tests_index.zig` so lint's related notes
    // and `list-interfaces`'s tests column answer identically.
    var scratch_arena = std.heap.ArenaAllocator.init(allocator);
    defer scratch_arena.deinit();
    const scratch = scratch_arena.allocator();
    const modules = try compilation.index.moduleSyntax(scratch);
    const graph = try tests_index.callGraph(scratch, program);
    const discovered = try tests_index.discoveredTests(scratch, program, modules);
    var index = try tests_index.build(allocator, program, graph, discovered);
    defer index.deinit();
    const answer = index.answer(target);

    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const writer = &out.writer;
    writer.print("tests-for {s}\n", .{subject}) catch return error.OutOfMemory;
    writer.print("  direct ({d}):", .{answer.direct.len}) catch return error.OutOfMemory;
    for (answer.direct) |name| writer.print(" {s}", .{name}) catch return error.OutOfMemory;
    writer.print("\n  reached-by ({d}):", .{answer.reached.len}) catch return error.OutOfMemory;
    for (answer.reached) |name| writer.print(" {s}", .{name}) catch return error.OutOfMemory;
    writer.writeAll("\n") catch return error.OutOfMemory;
    const owned = try out.toOwnedSlice();
    return owned;
}
