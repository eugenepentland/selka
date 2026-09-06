//! Arena dependency witnesses follow the same monotone ordering as lifetime checks.
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const Span = @import("source.zig").Span;
/// Deepest dependent arena and its source declaration, when available.
pub const Dependency = struct { depth: usize = 0, scope: ?Span = null };
/// Prefer a deeper arena; equal depths select the earliest declaration deterministically.
pub fn combine(left: Dependency, right: Dependency) Dependency {
    if (left.depth != right.depth) return if (left.depth > right.depth) left else right;
    const a = left.scope orelse return right;
    const b = right.scope orelse return left;
    return if (a.start <= b.start) left else right;
}
/// Propagate both lifetime depth and its witness until neither can improve.
pub fn grow(target: *Dependency, input: Dependency) bool {
    const next = combine(target.*, input);
    if (std.meta.eql(target.*, next)) return false;
    target.* = next;
    return true;
}
/// Reject escape and explain which arena supplies the shorter dependency.
pub fn requireLimit(dependency: Dependency, limit: usize, span: Span, sink: *diagnostic.Sink) diagnostic.Error!void {
    if (dependency.depth <= limit) return;
    const message = "value depends on a shorter-lived arena; keep its allocator and owned storage inside that scope";
    if (dependency.scope) |scope| return sink.failRelated("E_ARENA_ESCAPE", span, message, .{ .span = scope, .message = "shorter-lived arena declared here" });
    return sink.fail("E_ARENA_ESCAPE", span, message);
}
