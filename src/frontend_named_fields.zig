//! Diagnostic repairs preserve each positional operand and its evaluation order.
const std = @import("std");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
/// Operand sites paired with declaration labels and existing source labels.
pub const Fields = struct {
    labels: []const []const u8,
    sites: []const source.Span,
    names: []const ?source.Span,
};
/// Add every missing label together, without rebuilding expressions or patterns.
pub fn require(sink: *diagnostic.Sink, span: source.Span, code: []const u8, fields: Fields) diagnostic.Error!void {
    return requireWith(sink, span, code, fields, "payload fields must be supplied by name");
}

/// `require` for a pattern: the message names the case's fields and shows what to write for each field the pattern left
/// unlabelled (`case array(items):` binds the field under its own name, `case array(items=elems):` under another, `items=_`
/// discards it).
pub fn requirePattern(sink: *diagnostic.Sink, src: source.Source, span: source.Span, code: []const u8, fields: Fields) diagnostic.Error!void {
    var unlabelled: std.ArrayList(Unlabelled) = .empty;
    for (fields.sites, 0..) |site, index| {
        if (index >= fields.labels.len) break;
        if (fields.names.len != 0 and fields.names[index] != null) continue;
        try unlabelled.append(sink.allocator, .{ .index = index, .bound = src.text(site) });
    }
    if (unlabelled.items.len == 0) return;
    const message = try patternMessage(sink.allocator, src.text(span), fields.labels, unlabelled.items);
    return requireWith(sink, span, code, fields, message);
}

/// A pattern field written without its label: its position in the case and the text the pattern bound there.
pub const Unlabelled = struct { index: usize, bound: []const u8 };

/// What to write for the pattern fields `unlabelled` of a case whose fields are `labels`, which a pattern bound without their
/// labels: the case's fields in declaration order (at most four are named), the own-name and the renaming or discarding form of
/// the first field alone when the case has one field, else the labelled form of every field in `unlabelled` (at most four, then
/// the count of the rest). A bare `_` is discarded, not renamed.
pub fn patternMessage(allocator: std.mem.Allocator, case: []const u8, labels: []const []const u8, unlabelled: []const Unlabelled) std.mem.Allocator.Error![]const u8 {
    const first = unlabelled[0];
    const label = labels[first.index];
    if (labels.len == 1) return std.fmt.allocPrint(
        allocator,
        "`{s}`'s field is `{s}`: `case {s}({s}):` binds it under its own name, `case {s}({s}={s}):` {s} it",
        .{ case, label, case, label, case, label, first.bound, if (discards(first.bound)) "discards" else "renames" },
    );
    var list: std.ArrayList(u8) = .empty;
    for (labels[0..@min(labels.len, 4)], 0..) |name, position| {
        try list.print(allocator, "{s}`{s}`", .{ if (position == 0) "" else ", ", name });
    }
    if (labels.len > 4) try list.print(allocator, " and {d} more", .{labels.len - 4});
    var forms: std.ArrayList(u8) = .empty;
    for (unlabelled[0..@min(unlabelled.len, 4)], 0..) |field, position| {
        const name = labels[field.index];
        if (position != 0) try forms.appendSlice(allocator, ", ");
        if (discards(field.bound)) try forms.print(allocator, "`{s}=_` discards `{s}`", .{ name, name }) else try forms.print(allocator, "`{s}={s}` binds `{s}` as `{s}`", .{ name, field.bound, name, field.bound });
    }
    if (unlabelled.len > 4) try forms.print(allocator, " and {d} more", .{unlabelled.len - 4});
    return std.fmt.allocPrint(
        allocator,
        "`{s}`'s fields are {s}: a bare name in the pattern is a field's own name, and {s}",
        .{ case, list.items, forms.items },
    );
}

/// Whether a pattern's bare text is the wildcard, which binds nothing.
fn discards(bound: []const u8) bool {
    return std.mem.eql(u8, bound, "_");
}

fn requireWith(sink: *diagnostic.Sink, span: source.Span, code: []const u8, fields: Fields, message: []const u8) diagnostic.Error!void {
    var edits: std.ArrayList(diagnostic.Edit) = .empty;
    for (fields.sites, 0..) |site, index| {
        if (fields.names.len != 0 and fields.names[index] != null) continue;
        if (index >= fields.labels.len) continue;
        try edits.append(sink.allocator, .{
            .span = .{ .start = site.start, .end = site.start },
            .text = try std.fmt.allocPrint(sink.allocator, "{s}=", .{fields.labels[index]}),
        });
    }
    if (edits.items.len == 0) return;
    try sink.items.append(sink.allocator, .{
        .code = code,
        .span = span,
        .message = message,
        .provenance = .{ .fix = .{ .edit = edits.items[0], .more = edits.items[1..] } },
    });
    return error.SourceError;
}
