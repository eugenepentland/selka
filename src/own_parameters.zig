//! The `own` parameter mode: which values a parameter can take, and the flags
//! the checker records for one declaration.
//!
//! A parameter has one of three modes, visible at the declaration and at every
//! call: plain reads its argument, `mut` writes the caller's value, and `own`
//! takes it, so the caller's binding is unusable after the line. The mode is a
//! spelling fact at the call and an ownership fact inside the callee (an `own`
//! parameter may be stored, returned or moved, and is destroyed at the
//! callee's scope end otherwise). Core decides marker eligibility and required
//! moves; this module supplies declared modes and managed-type facts.
const std = @import("std");
const ast = @import("ast.zig");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");

/// The diagnostic code one misplaced or missing `own` marker reports.
pub const marker_code = "E_OWN_MARKER";

/// The diagnostic code a plain parameter of a move-only type reports: it would
/// take its argument without saying so, which is the mode `own` names.
pub const parameter_code = "E_OWN_PARAMETER";

/// Whether a parameter's declared type names one of its function's type
/// parameters. Such a parameter is shared by every instance of a generic
/// template, so `own` on it would change instances that do not move.
pub fn mentionsTypeParameter(src: source.Source, ty: source.Span, parameters: []const ast.TypeParameter) bool {
    const text = src.text(ty);
    for (parameters) |parameter| {
        const name = src.text(parameter.name);
        if (name.len == 0) continue;
        var start: usize = 0;
        while (std.mem.indexOfPos(u8, text, start, name)) |at| : (start = at + 1) {
            const before_ok = at == 0 or !isIdentifierByte(text[at - 1]);
            const end = at + name.len;
            const after_ok = end == text.len or !isIdentifierByte(text[end]);
            if (before_ok and after_ok) return true;
        }
    }
    return false;
}

/// Whether `byte` can continue an identifier.
fn isIdentifierByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

/// Refuse a plain (neither `own` nor `mut`) parameter whose type is move-only,
/// the hidden transfer rule: the declaration must say it takes its argument.
/// `type_name` is the parameter's type as the checker names it. A parameter
/// whose type names a type parameter is refused at each instance with no edit,
/// because the template is shared and `own` would change every other instance
/// too; any other parameter carries the certain edit that writes `own` before
/// its name.
pub fn refusePlain(
    allocator: std.mem.Allocator,
    sink: *diagnostic.Sink,
    src: source.Source,
    parameter: ast.Parameter,
    type_name: []const u8,
    generic: bool,
) diagnostic.Error!void {
    const name = src.text(parameter.name);
    const message = try std.fmt.allocPrint(
        allocator,
        "`{s}` is a `{s}`: a plain parameter would take it without saying so; declare `own {s}` to take it or `mut {s}` to borrow it",
        .{ name, type_name, name, name },
    );
    try refuse(sink, .{ .code = parameter_code, .rule = .T2 }, parameter.name, message, if (generic) null else parameter.name.start);
}

/// Refuse a plain position of a function type whose parameter type is
/// move-only. `insert_at` is where the `own` goes: before the parameter's
/// name when it has one, otherwise before its type. A position of a generic
/// function type is refused with no edit, as a generic parameter is.
pub fn refuseFunctionPosition(
    allocator: std.mem.Allocator,
    sink: *diagnostic.Sink,
    span: source.Span,
    insert_at: usize,
    type_name: []const u8,
    generic: bool,
) diagnostic.Error!void {
    const message = try std.fmt.allocPrint(
        allocator,
        "a plain parameter of this function type would take a `{s}` without saying so; write `own` before it to take it or `mut` to borrow it",
        .{type_name},
    );
    try refuse(sink, .{ .code = parameter_code, .rule = .W3 }, span, message, if (generic) null else insert_at);
}

/// The function-type syntax whose source span is `span`, or null when the span
/// spells no function type (so a caller never resolves a non-function type).
pub fn syntaxAt(callbacks: []const ast.CallbackType, span: source.Span) ?ast.CallbackType {
    for (callbacks) |syntax| if (syntax.span.start == span.start and syntax.span.end == span.end) return syntax;
    return null;
}

/// Where a function type is written: its source, the checked records it resolves
/// against, and the type parameters of the declaration that names it.
pub const FunctionSite = struct {
    src: source.Source,
    records: []const typed.Record,
    type_parameters: []const ast.TypeParameter,
};

/// Refuse each plain position of the function type `syntax`, resolved to
/// `value_type`, whose parameter type is move-only. A repair is written in the
/// type's source, before the name of a named position and before the type of an
/// unnamed one. A position whose type names one of the site's type parameters is
/// refused with no edit. A value that is not a function type is left alone.
pub fn refuseFunctionType(
    allocator: std.mem.Allocator,
    sink: *diagnostic.Sink,
    site: FunctionSite,
    value_type: typed.Type,
    syntax: ast.CallbackType,
) diagnostic.Error!void {
    const records = site.records;
    if (!value_type.isAggregate() or value_type.recordIndex() >= records.len) return;
    const callback = records[value_type.recordIndex()].contract.callback orelse return;
    for (callback.parameters, 0..) |parameter, position| {
        if (isOwn(callback.own, position) or !typed.moveOnly(parameter, records)) continue;
        if (position >= syntax.parameters.len) continue;
        const type_span = syntax.parameters[position];
        const insert = if (position < syntax.parameter_names.len) syntax.parameter_names[position] orelse type_span else type_span;
        try refuseFunctionPosition(
            allocator,
            sink,
            type_span,
            insert.start,
            try typed.surfaceTypeName(allocator, parameter, records),
            mentionsTypeParameter(site.src, type_span, site.type_parameters),
        );
    }
}

/// Append one `E_OWN_PARAMETER` at `span`, carrying the `own` insertion at
/// `insert_at` when the repair is certain, and skip a repeat of a diagnostic
/// the sink already holds (a generic declaration is checked once per instance).
fn refuse(sink: *diagnostic.Sink, refusal: diagnostic.Refusal, span: source.Span, message: []const u8, insert_at: ?usize) diagnostic.Error!void {
    if (hasDiagnostic(sink, refusal.code, span)) return;
    const item = diagnostic.ownership(refusal, span, message);
    const at = insert_at orelse return sink.items.append(sink.allocator, item);
    try sink.appendFix(item, .{ .span = .{ .start = at, .end = at }, .text = "own " });
}

/// Whether `sink` already holds a diagnostic with this code at this span.
fn hasDiagnostic(sink: *const diagnostic.Sink, code: []const u8, span: source.Span) bool {
    for (sink.items.items) |item| {
        if (item.span.start == span.start and item.span.end == span.end and std.mem.eql(u8, item.code, code)) return true;
    }
    return false;
}

/// The flags of up to this many parameters, none of which spells `own`.
const plain: [16]bool = @splat(false);

/// One flag per declared parameter, true where the declaration spelled `own`.
/// The flag list is positional, so a call site reads the mode of the parameter
/// at the position it passes.
pub fn flags(allocator: std.mem.Allocator, parameters: []const @import("ast.zig").Parameter) std.mem.Allocator.Error![]const bool {
    // A function that takes nothing with `own` (nearly all of them) shares one list of plain flags instead of allocating its own.
    var owned = false;
    for (parameters) |parameter| owned = owned or parameter.own;
    if (!owned and parameters.len <= plain.len) return plain[0..parameters.len];
    const out = try allocator.alloc(bool, parameters.len);
    for (parameters, out) |parameter, *flag| flag.* = parameter.own;
    return out;
}

/// Whether a value of this type owns storage a callee could take: a list,
/// dictionary, set, byte buffer, text or bytes value, a resource or move-only
/// value, or a record, option, tuple, union or fixed array that holds one.
/// Scalars — integers, floats, booleans, unit — and capabilities are read by
/// value, so an `own` marker on one gives nothing away.
pub fn managed(records: []const typed.Record, ty: typed.Type) bool {
    return managedAt(records, ty, 0);
}

/// The mode flag of the parameter at `position`; a position past the declared
/// list (a defaulted argument the callee fills itself) is plain.
pub fn isOwn(flags_list: []const bool, position: usize) bool {
    return position < flags_list.len and flags_list[position];
}

/// Mirrors `core/single_owner.zig`'s owned-type closure: the same schema
/// metadata decides what a store owns, so the marker rule and the ownership
/// rule cannot disagree about which values a callee can take.
fn managedAt(records: []const typed.Record, ty: typed.Type, depth: usize) bool {
    // An open file owns a provider handle; a capability is borrowed authority.
    if (ty.isFile()) return true;
    if (ty.capabilityIndex() != null) return false;
    // A cycle always passes through a collection, box or resource, which answers
    // `true` before recursing; the depth bound is the backstop for a malformed
    // schema the checker would already have refused.
    if (depth > 32 or !ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    const record = records[ty.recordIndex()];
    if (record.isCollection()) return switch (record.collection.kind) {
        .list, .string, .dictionary, .bytes => true,
    };
    if (record.collection.box or record.shape.resource != null) return true;
    if (record.shape.array) |array| if (managedAt(records, array.element, depth + 1)) return true;
    if (record.shape.variants) |variants| for (variants.cases) |case| {
        if (case.boxed) return true;
        if (case.payload) |payload| if (managedAt(records, payload, depth + 1)) return true;
    };
    for (record.fields) |field| {
        if (field.boxed or managedAt(records, field.ty, depth + 1)) return true;
    }
    return false;
}

test "a scalar, a capability and a record of scalars are not taken by own" {
    const records: [0]typed.Record = .{};
    try std.testing.expect(!managed(&records, .i64));
    try std.testing.expect(!managed(&records, .bool));
    try std.testing.expect(!managed(&records, .unit));
    try std.testing.expect(!managed(&records, .filesystem_cap));
    try std.testing.expect(!managed(&records, .u8));
}

test "parameter and function-position refusals retain distinct rules with their fixes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var sink: diagnostic.Sink = .{ .allocator = allocator };
    defer sink.deinit();
    const src: source.Source = .{ .path = "test.selka", .bytes = "arg: File", .line_starts = &.{0} };
    const name: source.Span = .{ .start = 0, .end = 3 };
    const ty: source.Span = .{ .start = 5, .end = 9 };

    try refusePlain(allocator, &sink, src, .{ .name = name, .ty = ty }, "File", false);
    try refuseFunctionPosition(allocator, &sink, ty, ty.start, "File", false);

    try std.testing.expectEqual(@as(usize, 2), sink.items.items.len);
    try std.testing.expectEqual(diagnostic.Rule.T2, sink.items.items[0].provenance.rule.?);
    try std.testing.expectEqual(diagnostic.Rule.W3, sink.items.items[1].provenance.rule.?);
    try std.testing.expectEqual(@as(usize, 0), sink.items.items[0].provenance.fix.?.edit.span.start);
    try std.testing.expectEqual(@as(usize, 5), sink.items.items[1].provenance.fix.?.edit.span.start);
    try std.testing.expectEqualStrings("own ", sink.items.items[0].provenance.fix.?.edit.text);
    try std.testing.expectEqualStrings("own ", sink.items.items[1].provenance.fix.?.edit.text);
}

test "functions that need no list of their own share one, and a flag or a label keeps its own" {
    const plain_parameters = [_]@import("ast.zig").Parameter{ .{ .name = .{ .start = 0, .end = 1 }, .ty = .{ .start = 2, .end = 5 } }, .{ .name = .{ .start = 6, .end = 7 }, .ty = .{ .start = 8, .end = 11 } } };
    var taking = plain_parameters;
    taking[1].own = true;
    const first = try flags(std.testing.failing_allocator, &plain_parameters);
    try std.testing.expectEqualSlices(bool, &.{ false, false }, first);
    try std.testing.expectEqual(first.ptr, (try flags(std.testing.failing_allocator, plain_parameters[0..2])).ptr);
    const own = try flags(std.testing.allocator, &taking);
    defer std.testing.allocator.free(own);
    try std.testing.expectEqualSlices(bool, &.{ false, true }, own);
    const source_text = "a: int, b: int";
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const src = try @import("source.zig").Source.init(arena_state.allocator(), "f.selka", source_text);
    const shared = try @import("callables.zig").functionLabels(std.testing.failing_allocator, src, &plain_parameters);
    try std.testing.expectEqualStrings("", shared[0]);
    var labelled = plain_parameters;
    labelled[0].named = true;
    const labels = try @import("callables.zig").functionLabels(std.testing.allocator, src, &labelled);
    defer std.testing.allocator.free(labels);
    try std.testing.expectEqualStrings("a", labels[0]);
    try std.testing.expectEqualStrings("", labels[1]);
}
