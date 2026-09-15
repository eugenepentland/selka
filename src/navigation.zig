//! Source-pinned compiler navigation facts, independent of VM execution.
const std = @import("std");
const typed = @import("typed.zig");
const source = @import("source.zig");
const pc = @import("project_compile.zig");
const receipt = @import("source_receipt.zig");
const walk = @import("typed_walk.zig");
const uses_type = "uses_type";
const effect_set = @import("effect_set.zig");
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
        effects: []const []const u8 = &.{},
        mutates: []const u16 = &.{},
        return_origin: []const u8 = "unknown",
        mutation_writes: bool = false,
    };
    const Context = struct { snippet: []const u8 = "", snippet_truncated: bool = false };

    /// Keep the navigation-v1 wire format flat while grouping internal facts.
    pub fn jsonStringify(self: Symbol, writer: anytype) !void {
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
        for (compilation.index.units, 0..) |unit, module_id| {
            const module = compilation.index.project.modules.items[module_id];
            for (unit.symbols.items) |symbol| {
                const span = compilation.src.mappedSpan(module_id, symbol.span) catch return error.InternalError;
                const qualified = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ module.name, symbol.name });
                try self.add(span, .{ .id = qualified, .name = symbol.name, .kind = @tagName(symbol.kind), .location = try self.location(span), .exported = symbol.exported });
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
                    .details = .{ .type_name = compilation.src.text(field.ty) },
                });
            }
        }
        for (compilation.syntax.types.variants) |variant| {
            const owner = self.id(variant.name) orelse continue;
            for (variant.cases) |item| {
                const name = compilation.src.text(item.name);
                try self.add(item.name, .{ .id = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ owner, name }), .name = name, .kind = "case", .location = try self.location(item.name) });
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
        if (function.type_arguments.len == 0) self.symbols.items[slot].details.type_name = typed.typeName(function.signature.return_type, program.records);
        var effects: std.ArrayList([]const u8) = .empty;
        // E2: navigation reports the declared public ceiling for exported
        // functions. Private helpers keep their inferred summary because they
        // have no published contract to fingerprint.
        const navigation_mask = if (self.symbols.items[slot].exported)
            (if (function.policy.effect_bound) |bound| bound.allowed else function.policy.effects)
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
                .details = .{ .type_name = typed.typeName(local.ty, program.records) },
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
/// Render source-indexed declarations and checked references; failed checking yields declarations only.
pub fn render(allocator: std.mem.Allocator, compilation: *pc.Compilation, identity: receipt.Identity, limits: Limits) Error![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
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
    const snapshot = .{ .implementation = try receipt.implementation(scratch, identity), .inputs = try receipt.inputs(scratch, &loaded) };
    return std.json.Stringify.valueAlloc(allocator, .{
        .version = "navigation-v1",
        .checked = compilation.program != null,
        .reference_scope = "resolved concrete bodies and specializations; generic declarations indexed; static edges are not runtime coverage",
        .snapshot_sha256 = try receipt.digest(scratch, snapshot),
        .snapshot = snapshot,
        .symbols = builder.symbols.items,
        .references = builder.references.items,
    }, .{});
}

fn excerptEnd(bytes: []const u8, start: usize, end: usize) usize {
    var stop = @min(end, start + 16384);
    while (stop < end and bytes[stop] & 0xc0 == 0x80) stop -= 1;
    return stop;
}
