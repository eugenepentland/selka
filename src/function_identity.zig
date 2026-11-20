//! Shared source spelling for free functions and nominal domain members.
const std = @import("std");
const source = @import("source.zig");
/// Borrow a free-function name, or allocate its domain-qualified member spelling.
pub fn localName(allocator: std.mem.Allocator, src: source.Source, owner: ?source.Span, name: source.Span) std.mem.Allocator.Error![]const u8 {
    if (owner) |domain| return std.fmt.allocPrint(allocator, "{s}.{s}", .{ src.text(domain), src.text(name) });
    return src.text(name);
}
