//! A `case` arm that names a case carrying a payload and binds nothing (`case Ok:`, `case circle:`; FR14).
//!
//! The pattern must say what the arm does with the payload, and the general sentence ("payload variants require a binding
//! or (discard)") named neither the case, nor what it carries, nor the two spellings. Both checkers (`sema_statements.zig`
//! for concrete bodies, `generic_bodies.zig` for generic ones) refuse it here with the case as written, the payload's type
//! (or the fields of a case with named fields) and the two patterns. The repair writes the discard after the case name,
//! `(_)` for a single payload and `(..)` for named fields, when the payload may be dropped (it does not itself need
//! handling, the condition of F-60's `else Err(_):`): a discard pattern binds no name, so the arm's body reads what it read.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");

/// What the refusal says about the case: its payload's type for a single payload, or the fields of a case with named
/// fields (`Fields.of`). `droppable` is whether the payload may be discarded, which offers the repair; `declared` is the
/// case's declaration, for the note.
pub const Missing = struct {
    payload: []const u8 = "",
    fields: ?Fields = null,
    droppable: bool,
    declared: ?source.Span = null,
};

/// The fields of a case with named fields as the refusal words them: `described` (``the field `radius: float` `` or
/// ``the fields `left: int` and `right: int` ``) and `names`, the binding spelling (`left, right`).
pub const Fields = struct {
    described: []const u8,
    names: []const u8,
    plural: bool,

    /// The wording for fields `names` whose types are `types` (one name per type, in declaration order).
    pub fn of(allocator: std.mem.Allocator, names: []const []const u8, types: []const []const u8) error{OutOfMemory}!Fields {
        var described: std.ArrayList(u8) = .empty;
        var spelled: std.ArrayList(u8) = .empty;
        try described.appendSlice(allocator, if (names.len == 1) "the field " else "the fields ");
        for (names, types, 0..) |name, ty, index| {
            const separator: []const u8 = if (index == 0) "" else if (index + 1 == names.len) " and " else ", ";
            try described.print(allocator, "{s}`{s}: {s}`", .{ separator, name, ty });
            try spelled.print(allocator, "{s}{s}", .{ if (index == 0) "" else ", ", name });
        }
        return .{ .described = described.items, .names = spelled.items, .plural = names.len != 1 };
    }
};

/// Whether `arm` is a written `case NAME:` (or one name of a `case a | b:` list) with no parentheses after the name, the
/// shape this refusal is for. A bind-or-else arm, an `is` test's bare name and a pattern with a payload list are not.
pub fn bare(src: source.Source, arm: ast.MatchArm) bool {
    if (arm.alternatives.role != .named or arm.alternatives.bare or arm.bindings.len != 0 or arm.binding_names.len != 0) return false;
    var at: usize = arm.name.end;
    while (at < src.bytes.len and (src.bytes[at] == ' ' or src.bytes[at] == '\t')) at += 1;
    return at < src.bytes.len and (src.bytes[at] == ':' or src.bytes[at] == '|');
}

/// Refuse `arm` with `code`, naming the case, what it carries and the two patterns, with the discard as the repair when
/// the payload may be dropped.
pub fn refuse(src: source.Source, sink: *diagnostic.Sink, code: []const u8, arm: ast.MatchArm, missing: Missing) diagnostic.Error {
    const name = src.text(arm.name);
    const message = if (missing.fields) |fields|
        std.fmt.allocPrint(sink.allocator, "`case {s}` names a case with {s}, so the pattern must say what the arm does with {s}: " ++
            "`case {s}(..):` drops {s} and `case {s}({s}):` binds {s} to use", .{
            name, fields.described, if (fields.plural) "them" else "it", name, if (fields.plural) "them" else "it", name, fields.names, if (fields.plural) "them" else "it",
        }) catch return error.OutOfMemory
    else
        std.fmt.allocPrint(sink.allocator, "`case {s}` names a case that carries {s}, so the pattern must say what the arm does with it: " ++
            "`case {s}(_):` drops it and `case {s}(value):` binds it to use", .{ name, missing.payload, name, name }) catch return error.OutOfMemory;
    var item: diagnostic.Diagnostic = .{ .code = code, .span = arm.name, .message = message };
    if (missing.declared) |span| item.related = .{ .span = span, .message = "variant declared here" };
    if (!missing.droppable) {
        sink.items.append(sink.allocator, item) catch return error.OutOfMemory;
        return error.SourceError;
    }
    try sink.appendFix(item, .{ .span = .{ .start = arm.name.end, .end = arm.name.end }, .text = if (missing.fields != null) "(..)" else "(_)" });
    return error.SourceError;
}
