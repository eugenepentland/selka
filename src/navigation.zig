//! Source-pinned compiler navigation facts, independent of VM execution.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const pc = @import("project_compile.zig");
const receipt = @import("source_receipt.zig");
const walk = @import("typed_walk.zig");
const uses_type = "uses_type";
const effect_set = @import("effect_set.zig");
const fact_status = @import("fact_status.zig");
const tests_index = @import("tests_index.zig");
/// Optional caps on one navigation pass. Both default to null — no cap — so the
/// tables grow with the project and are bounded only by the compiler's own
/// memory ceiling (`MYLANG_HOST_MEMORY_LIMIT`), exactly like `check`. A caller
/// that sets one gets `NavigationLimit` once the pass would exceed it; no
/// command sets one, so a large project is never refused for its size.
pub const Limits = struct { symbols: ?usize = null, references: ?usize = null };
/// What one navigation pass collects: optional caps, and what the
/// relationship walk does with each row.
pub const Collect = struct { limits: Limits = .{}, edges: Edges = .all };
/// What the relationship walk does. The walk runs after every declaration is
/// known, so a caller can decide which rows it needs before any row exists.
pub const Edges = union(enum) {
    /// Skip the walk: declarations only. A summary needs nothing else.
    none,
    /// Keep every row in `Facts.references`.
    all,
    /// Show the visitor the finished declarations, then offer it each row.
    visit: Visitor,
};
/// A caller that acts between the declaration pass and the relationship walk,
/// so a document can be streamed, or a selection kept, without first holding
/// every row of a large project.
pub const Visitor = struct {
    context: *anyopaque,
    /// Sees the complete declaration table once, before any row.
    declarations: *const fn (context: *anyopaque, table: Table) VisitError!void,
    /// Whether a row between these two declarations is wanted at all, asked
    /// before its source location is computed.
    wants: *const fn (context: *anyopaque, from: []const u8, to: []const u8) bool,
    /// Sees each wanted row in walk order; true keeps it in `Facts.references`.
    row: *const fn (context: *anyopaque, reference: Reference) VisitError!bool,
};
/// The finished declaration table a visitor sees. The slice is valid only for
/// the duration of the call: the table may still move before `collect` returns.
pub const Table = struct { checked: bool, snapshot: Snapshot, snapshot_sha256: []const u8, symbols: []const Symbol };
/// Navigation failures, plus a visitor's refused write.
pub const VisitError = Error || error{WriteFailed};
/// Every declaration kind a navigation symbol can carry, in the order a
/// summary publishes their counts.
pub const kinds = [_][]const u8{ "function", "type", "constraint", "field", "case", "parameter", "local" };
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
    /// Owns the symbol table and the declaration map, each sized once from
    /// the project (`declarationBound`): grown inside the arena, a table of
    /// every local would leave each outgrown buffer behind until the arena
    /// dies. Relationship rows stay in the arena, because the command paths
    /// keep none or a few of them.
    gpa: std.mem.Allocator,
    compilation: *pc.Compilation,
    options: Collect,
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
        if (self.options.limits.symbols) |cap| if (self.symbols.items.len >= cap) return error.NavigationLimit;
        try self.declarations.put(self.gpa, span.start, self.symbols.items.len);
        try self.symbols.append(self.gpa, symbol);
    }
    fn id(self: *Builder, declaration: source.Span) ?[]const u8 {
        const index = self.declarations.get(declaration.start) orelse return null;
        return self.symbols.items[index].id;
    }
    fn edge(self: *Builder, from: []const u8, to: ?[]const u8, kind: []const u8, span: source.Span) VisitError!void {
        const target = to orelse return;
        switch (self.options.edges) {
            .none => return,
            .all => {},
            .visit => |visitor| if (!visitor.wants(visitor.context, from, target)) return,
        }
        const row: Reference = .{ .from = from, .to = target, .kind = kind, .location = try self.location(span) };
        switch (self.options.edges) {
            .none, .all => {},
            .visit => |visitor| if (!try visitor.row(visitor.context, row)) return,
        }
        if (self.options.limits.references) |cap| if (self.references.items.len >= cap) return error.NavigationLimit;
        try self.references.append(self.allocator, row);
    }
    /// CONTRACT-INTERFACE-1: a function's contract clauses lead its published
    /// signature, one per line, as they stand above its `def`.
    fn contractSignature(self: *Builder, function: ast.Function, signature: []const u8) Error![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        for (ast.attributesOf(self.compilation.syntax, function.name)) |attribute| {
            if (!attribute.kind.contract()) continue;
            try out.appendSlice(self.allocator, self.compilation.src.text(attribute.span));
            try out.append(self.allocator, '\n');
        }
        if (out.items.len == 0) return signature;
        try out.appendSlice(self.allocator, signature);
        return out.toOwnedSlice(self.allocator);
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
            self.symbols.items[slot].details.signature = try self.contractSignature(function, original.bytes[start..body_at.span.start]);
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
    /// The relationship walk over every checked function, then every record's
    /// field types.
    fn walkEdges(self: *Builder) VisitError!void {
        const program = self.compilation.program orelse return;
        for (program.functions) |function| try self.functionEdges(program, function);
        for (program.records) |record| {
            const owner = self.typeDeclarationId(record.declaration) orelse continue;
            for (record.fields) |field| try self.edge(owner, self.typeId(program, field.ty), "contains_type", field.declaration);
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
    /// The declaration pass over one typed function: its checked facts and its
    /// parameters and locals.
    fn functionSymbols(self: *Builder, program: typed.Program, function: typed.Function) Error!void {
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
        self.symbols.items[slot].details.mutation_writes = function.signature.inferred.writes;
        for (function.scope.locals, 0..) |local, i| {
            if (local.usage.temporary) continue;
            try self.add(local.declaration, .{
                .id = try self.scopedId(owner, "local", local.name, local.declaration),
                .name = local.name,
                .kind = if (i < function.signature.parameter_count) "parameter" else "local",
                .location = try self.location(local.declaration),
                .details = .{ .analysis = .checked, .type_name = typed.typeName(local.ty, program.records) },
            });
        }
    }
    /// The relationship walk over one typed function, in the order the rows
    /// have always been published: its result type, each parameter's and
    /// local's type, then its body.
    fn functionEdges(self: *Builder, program: typed.Program, function: typed.Function) VisitError!void {
        const owner = self.id(function.declaration) orelse return;
        try self.edge(owner, self.typeId(program, function.signature.return_type), "returns", function.declaration);
        for (function.scope.locals, 0..) |local, i| {
            if (local.usage.temporary) continue;
            try self.edge(owner, self.typeId(program, local.ty), if (i < function.signature.parameter_count) "accepts" else uses_type, local.declaration);
        }
        var walker = try walk.Walker.init(self.allocator, program, function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| switch (item) {
            .expression => |node_id| try self.expression(program, function, owner, program.nodes[@backingInt(node_id)]),
            .statement => |statement_id| {
                const statement = program.statements[@backingInt(statement_id)];
                switch (statement.data) {
                    .range_loop => |range| for ([_]typed.Store{ range.plan().start, range.plan().end }) |store| {
                        try self.edge(owner, self.id(function.scope.locals[@backingInt(store.slot)].declaration), "write", range.plan().binding);
                    },
                    .assign, .initialize => |store| try self.edge(owner, self.id(function.scope.locals[@backingInt(store.slot)].declaration), "write", statement.span),
                    else => {},
                }
            },
        };
    }
    fn expression(self: *Builder, program: typed.Program, function: typed.Function, owner: []const u8, node: typed.Node) VisitError!void {
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
pub const Snapshot = struct {
    implementation: receipt.Implementation,
    inputs: []const receipt.Input,
    embeds: []const receipt.Embedded = &.{},

    /// Keep the existing source-only wire identity when no embedded files exist.
    pub fn jsonStringify(self: Snapshot, writer: anytype) !void {
        try writer.beginObject();
        try writer.objectField("implementation");
        try writer.write(self.implementation);
        try writer.objectField("inputs");
        try writer.write(self.inputs);
        if (self.embeds.len != 0) {
            try writer.objectField("embeds");
            try writer.write(self.embeds);
        }
        try writer.endObject();
    }
};

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
    /// The whole allocation `symbols` is the front of.
    symbol_storage: []Symbol,

    /// Release the symbol table, which the caller's allocator owns, and the
    /// arena every other slice above points into.
    pub fn deinit(self: *Facts) void {
        self.arena.child_allocator.free(self.symbol_storage);
        self.arena.deinit();
    }

    /// The complete `navigation-v1` document these facts publish.
    pub fn document(self: *const Facts) Document {
        return .{
            .checked = self.checked,
            .reference_scope = checked_reference_scope,
            .snapshot_sha256 = self.snapshot_sha256,
            .snapshot = self.snapshot,
            .symbols = self.symbols,
            .references = self.references,
        };
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

/// At least as many declarations as one pass can publish: every interface
/// symbol, record field, case and typed local. Sizing the table once keeps a
/// large project's table from being copied as it grows.
fn declarationBound(compilation: *const pc.Compilation) usize {
    var total: usize = 0;
    for (compilation.index.units) |unit| total += unit.symbols.items.len;
    for (compilation.syntax.types.records) |record| total += record.fields.len;
    for (compilation.syntax.types.variants) |variant| total += variant.cases.len;
    const program = compilation.program orelse return total;
    for (program.functions) |function| total += function.scope.locals.len;
    return total;
}

/// Collect source-indexed declarations and checked references over the merged
/// compilation: every declaration first, then the relationship walk that
/// `options.edges` directs. Failed checking yields declarations only; every
/// symbol then carries the status of the analysis behind it.
pub fn collect(allocator: std.mem.Allocator, compilation: *pc.Compilation, identity: receipt.Identity, options: Collect) VisitError!Facts {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const scratch = arena.allocator();
    var builder: Builder = .{ .allocator = scratch, .gpa = allocator, .compilation = compilation, .options = options };
    defer builder.declarations.deinit(allocator);
    errdefer builder.symbols.deinit(allocator);
    const bound = declarationBound(compilation);
    try builder.symbols.ensureTotalCapacityPrecise(allocator, bound);
    try builder.declarations.ensureTotalCapacity(allocator, std.math.cast(u32, bound) orelse return error.OutOfMemory);
    // Body resolution can attach a diagnostic after the complete load; keep the
    // exact loaded-source receipt without treating that diagnostic as a missing file.
    var loaded = compilation.index.project.*;
    loaded.problem = null;
    const snapshot: Snapshot = .{ .implementation = try receipt.implementation(scratch, identity), .inputs = try receipt.inputs(scratch, &loaded), .embeds = try receipt.embeds(scratch, &loaded) };
    const digest = try receipt.digest(scratch, snapshot);
    try builder.declarationsFromSyntax();
    if (compilation.program) |program| {
        for (program.functions) |function| try builder.functionSymbols(program, function);
    }
    switch (options.edges) {
        .none => {},
        .all => try builder.walkEdges(),
        .visit => |visitor| {
            try visitor.declarations(visitor.context, .{ .checked = compilation.program != null, .snapshot = snapshot, .snapshot_sha256 = digest, .symbols = builder.symbols.items });
            try builder.walkEdges();
        },
    }
    return .{
        .arena = arena,
        .symbols = builder.symbols.items,
        .symbol_storage = builder.symbols.allocatedSlice(),
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
    var facts = collect(allocator, compilation, identity, .{ .limits = limits }) catch |err| switch (err) {
        // Only a visitor writes, and this pass has none.
        error.WriteFailed => return error.InternalError,
        else => |other| return other,
    };
    defer facts.deinit();
    return std.json.Stringify.valueAlloc(allocator, facts.document(), .{});
}

/// The `reference_scope` a checked pass publishes.
pub const checked_reference_scope = "resolved concrete bodies and specializations; generic declarations indexed; static edges are not runtime coverage";

/// The complete `navigation-v1` document one pass publishes: every field in the
/// order this command always wrote them.
pub const Document = struct {
    version: []const u8 = "navigation-v1",
    checked: bool,
    reference_scope: []const u8,
    snapshot_sha256: []const u8,
    snapshot: Snapshot,
    symbols: []const Symbol,
    references: []const Reference,
};

fn excerptEnd(bytes: []const u8, start: usize, end: usize) usize {
    var stop = @min(end, start + 16384);
    while (stop < end and bytes[stop] & 0xc0 == 0x80) stop -= 1;
    return stop;
}

/// How a caller's spelling of a declaration resolved against the identities
/// one pass published.
pub const Resolved = union(enum) {
    /// Exactly one identity matched; this is it.
    found: []const u8,
    /// A dotted spelling matched several identities; none is chosen.
    ambiguous: []const []const u8,
    /// Nothing matched.
    missing,
};

/// Resolve a declaration spelling against `ids`: the exact `module::name`
/// identity as written, or the spelling code writes at a call site,
/// `module.name`. A dotted spelling is tried at every split into a module path
/// and a member path, longest module path first, because both sides may hold
/// dots (`shared.units.Distance.make` is `shared.units::Distance.make`); one
/// match is the answer and several are reported, never silently chosen. A bare
/// name without a dot is left to the caller, which has its own rule for it.
pub fn resolveSpelling(arena: std.mem.Allocator, spelling: []const u8, ids: []const []const u8) error{OutOfMemory}!Resolved {
    for (ids) |id| {
        if (std.mem.eql(u8, id, spelling)) return .{ .found = id };
    }
    if (std.mem.indexOf(u8, spelling, "::") != null) return .missing;
    var matches: std.ArrayList([]const u8) = .empty;
    var cursor = spelling.len;
    while (std.mem.lastIndexOfScalar(u8, spelling[0..cursor], '.')) |dot| {
        cursor = dot;
        const module = spelling[0..dot];
        const member = spelling[dot + 1 ..];
        if (module.len == 0 or member.len == 0) continue;
        for (ids) |id| {
            if (!splitsAs(id, module, member)) continue;
            try matches.append(arena, id);
            break;
        }
    }
    return switch (matches.items.len) {
        0 => .missing,
        1 => .{ .found = matches.items[0] },
        else => .{ .ambiguous = matches.items },
    };
}

/// Whether `id` is exactly `module::member`.
fn splitsAs(id: []const u8, module: []const u8, member: []const u8) bool {
    if (id.len != module.len + 2 + member.len) return false;
    return std.mem.startsWith(u8, id, module) and std.mem.eql(u8, id[module.len .. module.len + 2], "::") and std.mem.endsWith(u8, id, member);
}

/// The qualified name of every checked function, the identities `tests-for`
/// resolves a spelling against.
pub fn functionNames(arena: std.mem.Allocator, program: typed.Program) error{OutOfMemory}![]const []const u8 {
    const names = try arena.alloc([]const u8, program.functions.len);
    for (names, program.functions) |*name, function| name.* = function.name;
    return names;
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
    const rendered = try formatTestsFor(allocator, subject, index.answer(target), null);
    return rendered;
}

/// The `tests-for` text: the subject, the direct tests, every test that reaches
/// it, and a closing `basis` line when the answer was not read from checked bodies.
pub fn formatTestsFor(allocator: std.mem.Allocator, subject: []const u8, answer: tests_index.Answer, basis: ?[]const u8) error{OutOfMemory}![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const writer = &out.writer;
    writer.print("tests-for {s}\n", .{subject}) catch return error.OutOfMemory;
    writer.print("  direct ({d}):", .{answer.direct.len}) catch return error.OutOfMemory;
    for (answer.direct) |name| writer.print(" {s}", .{name}) catch return error.OutOfMemory;
    writer.print("\n  reached-by ({d}):", .{answer.reached.len}) catch return error.OutOfMemory;
    for (answer.reached) |name| writer.print(" {s}", .{name}) catch return error.OutOfMemory;
    writer.writeAll("\n") catch return error.OutOfMemory;
    if (basis) |label| writer.print("  {s}\n", .{label}) catch return error.OutOfMemory;
    return out.toOwnedSlice();
}
