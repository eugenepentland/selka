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
        .message = "payload fields must be supplied by name",
        .provenance = .{ .fix = .{ .edit = edits.items[0], .more = edits.items[1..] } },
    });
    return error.SourceError;
}
