//! Resolve Python variant construction `Type.case` and `Type.case(value)` through declared
//! identities. The legacy surface spells the same construction `new Type.case(value)`; the
//! Python surface reuses ordinary member and call syntax, so the checker rewrites it before
//! resolving a function. A generic variant names only its template: `Slot[Box[int]].some(v)`
//! cannot be told apart from an index followed by a method call, so `Slot.some(v)` infers its
//! type arguments from the expected type instead.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Catalog = @import("records.zig").Catalog;
const Call = @import("call_arguments.zig").Call;

/// Report whether a name declares a closed enum or tagged union, concrete or generic.
pub fn declaresVariant(src: source.Source, catalog: Catalog, span: source.Span, sink: *diagnostic.Sink) diagnostic.Error!bool {
    if (try catalog.variantType(src, span, sink) != null) return true;
    return templateKind(src, catalog, span) != null;
}

/// Resolve a bare generic variant template name against the expected type at its use site,
/// because such a name carries no arguments of its own. Returns null for every other
/// spelling, which the caller resolves through its own generic substitution scope.
pub fn contextual(
    src: source.Source,
    catalog: Catalog,
    span: source.Span,
    expected: ?typed.Type,
    sink: *diagnostic.Sink,
) diagnostic.Error!?typed.Type {
    if (templateKind(src, catalog, span) == null) return null;
    if (expected) |ty| if (specializes(catalog, ty, baseName(src.text(span)))) return ty;
    return sink.fail("E_GENERIC_INFERENCE", span, inference_message);
}

/// Lower `Type.case(value)` to the existing variant node when the owner names a declared
/// enum or tagged union and the member names one of its cases. Returns null for every other
/// call, leaving domain functions, collection methods and module functions untouched.
pub fn lower(src: source.Source, catalog: Catalog, call: Call, span: source.Span, sink: *diagnostic.Sink) diagnostic.Error!?ast.Node {
    const owner = call.owner orelse return null;
    if (call.type_arguments.len != 0) return null;
    if (!try namesCase(src, catalog, owner, call.name, sink)) return null;
    try @import("call_arguments.zig").positional(call, sink);
    if (call.arguments.len != 1) return sink.fail(
        "E_ARITY",
        call.name,
        "variant construction takes exactly one payload; an empty case is written without parentheses",
    );
    return .{ .span = span, .data = .{ .variant = .{ .ty = owner, .name = call.name, .value = call.arguments[0] } } };
}

/// Report whether `owner.name` selects a declared case of a concrete or generic variant type.
pub fn namesCase(
    src: source.Source,
    catalog: Catalog,
    owner: source.Span,
    name: source.Span,
    sink: *diagnostic.Sink,
) diagnostic.Error!bool {
    const case = src.text(name);
    if (try catalog.variantType(src, owner, sink)) |ty| {
        for (catalog.records[ty.recordIndex()].shape.variants.?.cases) |declared| {
            if (std.mem.eql(u8, declared.name, case)) return true;
        }
        return false;
    }
    const declaration = templateKind(src, catalog, owner) orelse return false;
    for (declaration.fields) |field| if (std.mem.eql(u8, src.text(field.name), case)) return true;
    return false;
}

const Declaration = @import("nominal_templates.zig").Declaration;

/// Index of the generic enum or tagged union template named by this span, or null.
/// Symbolic checking compares this index against a nominal shape's own declaration.
pub fn templateDeclaration(src: source.Source, catalog: Catalog, span: source.Span) ?usize {
    const store = catalog.templates.store orelse return null;
    const text = src.text(span);
    const id = store.index.names.get(text) orelse store.index.names.get(baseName(text)) orelse return null;
    const declaration = store.index.declarations.items[id];
    if (declaration.parameters.len == 0) return null;
    return switch (declaration.kind) {
        .variants, .enumeration, .result => id,
        else => null,
    };
}

/// Shared wording for a generic variant whose arguments no context supplies.
pub const inference_message = "a generic variant infers its type arguments from the expected type; annotate the binding, parameter or result";

fn templateKind(src: source.Source, catalog: Catalog, span: source.Span) ?Declaration {
    const store = catalog.templates.store orelse return null;
    const id = templateDeclaration(src, catalog, span) orelse return null;
    return store.index.declarations.items[id];
}

/// Report whether a concrete type is a specialization of the named template.
fn specializes(catalog: Catalog, ty: typed.Type, template: []const u8) bool {
    if (!ty.isAggregate()) return false;
    const record = catalog.records[ty.recordIndex()];
    if (record.shape.variants == null) return false;
    const head = record.name[0 .. std.mem.indexOfScalar(u8, record.name, '<') orelse record.name.len];
    return std.mem.eql(u8, baseName(head), template);
}

/// Last segment of a `module::Name` or `alias.Name` spelling.
fn baseName(text: []const u8) []const u8 {
    var name = text;
    if (std.mem.lastIndexOf(u8, name, "::")) |at| name = name[at + 2 ..];
    if (std.mem.lastIndexOfScalar(u8, name, '.')) |at| name = name[at + 1 ..];
    return name;
}
