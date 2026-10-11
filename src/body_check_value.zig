//! Scalar body-check batch transport, independent of semantic orchestration.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const declaration = @import("declaration_value.zig");
const diagnostic = @import("diagnostic.zig");
const logical = @import("parser_value.zig");
/// Source diagnostics retain all B1 notes and fixes without runtime-only state.
pub const Diagnostic = logical.SyntaxDiagnostic;
const source = @import("source.zig");
/// Raw source and entry policy; no body decisions have been precomputed.
pub const Context = struct { path: []const u8, source: []const u8, trusted_intrinsics: bool, entry_required: bool };
/// Explicit module namespace and initial import usage in merged coordinates.
pub const Module = struct { context: declaration.Context, offset: usize, imports: []const declaration.Import, symbols: []const declaration.Symbol, import_used: []const bool };
/// Complete raw syntax and namespace inputs for one scalar body batch.
pub const Input = struct { context: Context, program: ast.Program, modules: []const Module, catalog: Catalog = .{} };
/// Native retained prelude identities; absent entries are unavailable, never inferred.
pub const Catalog = struct {
    string: ?Sequence = null,
    bytes: ?Sequence = null,
    base_count: usize = 0,
    lists: []const Sequence = &.{},
    list_available: bool = false,
    records: []const typed.Record = &.{},
    templates: Templates = .{},
};
/// Opaque retained builtin template authority, never per-use body answers.
pub const Templates = struct { result: ?TemplateBasis = null, option: ?TemplateBasis = null, byte_buffer: BufferBasis = .{}, collections: CollectionTemplates = .{} };
/// Exact injected collection declaration authorities; user declarations never grant these identities.
pub const CollectionTemplates = struct { dict: ?TemplateBasis = null, set: ?TemplateBasis = null, DictItem: ?TemplateBasis = null, DictKeys: ?TemplateBasis = null, DictValues: ?TemplateBasis = null, DictItems: ?TemplateBasis = null };
/// Authenticated optional octet-buffer identity and exact builtin addability.
pub const BufferBasis = struct { available: bool = false, identity: ?Sequence = null };
/// Exact common declaration authority; an empty span denotes the synthesized prelude.
pub const TemplateBasis = struct { id: usize, declaration: source.Span };
/// The exact managed identity and its internal scalar element representation.
pub const Sequence = struct { id: typed.Type, element: typed.Type };
/// Complete typed tables before entry adaptation and native postpasses.
pub const Batch = struct { nodes: []const typed.Node, statements: []const typed.Statement, functions: []const typed.Function, ranges: []const @import("semantic_copy.zig").Range };
/// Typed bodies and all ordered checker observations.
pub const Output = struct { batch: Batch, import_used: []const []const bool, diagnostics: []const Diagnostic, recipes: []const CatalogRecipe = &.{} };
/// One producer-selected canonical list identity, in native append order.
/// First-demand canonical octet-buffer schema, without type arguments.
pub const BufferRecipe = struct { id: typed.Type, span: source.Span };
/// Producer-selected list schema with its original demand span.
pub const ListRecipe = struct { id: typed.Type, element: typed.Type, span: source.Span };
/// One producer-selected canonical checked-result identity.
pub const ResultRecipe = struct { id: typed.Type, success: typed.Type, failure: typed.Type, span: source.Span };
/// One producer-selected canonical optional identity.
pub const OptionRecipe = struct { id: typed.Type, element: typed.Type, span: source.Span };
/// Dictionary and projection schemas retain both canonical type arguments.
pub const DictionaryRecipe = struct { id: typed.Type, key: typed.Type, value: typed.Type, span: source.Span };
/// All append decisions share one native first-demand order.
pub const CatalogRecipe = union(enum) {
    list: ListRecipe,
    result: ResultRecipe,
    option: OptionRecipe,
    byte_buffer: BufferRecipe,
    collection: CollectionRecipe,
};
/// Grouped collection append roles preserve the qualified seven-field profile.
pub const CollectionRecipe = union(enum) {
    dict: DictionaryRecipe,
    set: ListRecipe,
    dict_item: DictionaryRecipe,
    dict_keys: DictionaryRecipe,
    dict_values: DictionaryRecipe,
    dict_items: DictionaryRecipe,
};
/// Exact next runtime identity selected by any append recipe.
pub fn recipeId(recipe: CatalogRecipe) typed.Type {
    return switch (recipe) {
        .collection => |item| switch (item) {
            inline else => |entry| entry.id,
        },
        inline else => |item| item.id,
    };
}
/// First source demand retained independently of recipe family.
pub fn recipeSpan(recipe: CatalogRecipe) source.Span {
    return switch (recipe) {
        .collection => |item| switch (item) {
            inline else => |entry| entry.span,
        },
        inline else => |item| item.span,
    };
}
/// Located unsupported profile refusal; it never requests native fallback.
pub const Profile = struct { code: []const u8, span: source.Span, message: []const u8 };
/// Checked scalar bodies, source diagnostics, or explicit admission refusal.
pub const Outcome = union(enum) { success: Output, failure: []const Diagnostic, profile: Profile };
/// Reply values own storage independently of the process capture buffer.
pub const Decoded = struct {
    arena: std.heap.ArenaAllocator,
    outcome: Outcome,
    /// Release all decoded tables and observations.
    pub fn deinit(self: *Decoded) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

/// Restore a decoded source diagnostic for the native sink without dropping notes.
pub fn nativeDiagnostic(item: Diagnostic) diagnostic.Diagnostic {
    return .{
        .code = item.code,
        .severity = item.severity,
        .span = item.span,
        .message = item.message,
        .related = item.related,
        .provenance = .{ .origin = item.provenance.origin, .requirement = item.provenance.requirement, .fix = item.provenance.fix },
    };
}

/// Project native B1 diagnostics, rejecting runtime state instead of discarding it.
pub fn diagnostics(a: std.mem.Allocator, items: []const diagnostic.Diagnostic) logical.Error![]const Diagnostic {
    const output = try a.alloc(Diagnostic, items.len);
    errdefer a.free(output);
    for (items, output) |item, *result| {
        if (item.provenance.obligation != null or item.stack.len != 0 or item.stack.omitted != 0) return error.ComponentProtocol;
        result.* = .{
            .code = item.code,
            .severity = item.severity,
            .span = item.span,
            .message = item.message,
            .related = item.related,
            .provenance = .{ .origin = item.provenance.origin, .requirement = item.provenance.requirement, .fix = item.provenance.fix },
        };
    }
    return output;
}
/// Adopt independent body tables into caller-owned arena storage.
pub fn cloneBatch(a: std.mem.Allocator, batch: Batch) logical.Error!Batch {
    return @import("body_owned_copy.zig").clone(a, Batch, batch);
}
/// Publish complete decoded source diagnostics into a sink-owned arena.
pub fn publish(sink: *diagnostic.Sink, items: []const Diagnostic) logical.Error!void {
    const bytes = try logical.encodeTreeProfile(sink.allocator, []const Diagnostic, items, "SLKBTD01", .body);
    defer sink.allocator.free(bytes);
    const owned = try logical.decodeIntoProfile([]const Diagnostic, sink.allocator, bytes, "SLKBTD01", .body);
    for (owned) |item| try sink.items.append(sink.allocator, nativeDiagnostic(item));
}
/// Compare complete canonical outcomes independently of value-table ordering.
pub fn equal(a: std.mem.Allocator, left: Outcome, right: Outcome) logical.Error!bool {
    const lhs = try logical.encodeTreeProfile(a, Outcome, left, "SLKBKR01", .body);
    defer a.free(lhs);
    const rhs = try logical.encodeTreeProfile(a, Outcome, right, "SLKBKR01", .body);
    defer a.free(rhs);
    return std.mem.eql(u8, lhs, rhs);
}
