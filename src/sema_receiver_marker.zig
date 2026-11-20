//! The marker rules of a writing prelude call's receiver, shared by `append`, `sort`, `take` and `exchange`: the call
//! writes its first operand, so that operand is borrowed `mut` and nothing else in the call is.

const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const Error = @import("diagnostic.zig").Error;
const mutation_marker_code = @import("origins.zig").mutation_marker_code;
const own_marker_code = @import("own_parameters.zig").marker_code;

/// Check the markers of the call `spelling(...)`, whose first operand is the place it writes, and answer that operand's
/// `mut` syntax node. M3: the receiver takes `mut` and no other operand does. W2: `own` on the receiver is `mut`, since
/// the call writes it and never gives it away. Each refusal carries the exact edit.
pub fn require(comptime Checker: type, self: *Checker, spelling: []const u8, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!ast.Node {
    const first = self.syntax.nodes.items[@backingInt(call.arguments[0])];
    if (first.data == .own_argument) {
        const receiver = self.syntax.nodes.items[@backingInt(first.data.own_argument)];
        const message = try std.fmt.allocPrint(self.allocator, "`{s}` writes `{s}`, so it borrows it `mut` instead of taking it `own`", .{ spelling, self.src.text(receiver.span) });
        const marker: source.Span = .{ .start = first.span.start, .end = receiver.span.start };
        return self.sink.failOwnershipFix(.{ .code = own_marker_code, .rule = .W2 }, first.span, message, .{ .span = marker, .text = "mut " });
    }
    if (first.data != .mut_argument) {
        const message = try std.fmt.allocPrint(self.allocator, "`{s}` writes `{s}`; write `mut {s}`", .{ spelling, self.src.text(first.span), self.src.text(first.span) });
        const insert: source.Span = .{ .start = first.span.start, .end = first.span.start };
        return self.sink.failOwnershipFix(.{ .code = mutation_marker_code, .rule = .M3 }, first.span, message, .{ .span = insert, .text = "mut " });
    }
    for (call.arguments[1..]) |argument| {
        const marked = self.syntax.nodes.items[@backingInt(argument)];
        // Owning operands keep their source marker for Core. Only the receiver has a mutation marker.
        if (marked.data != .mut_argument) continue;
        const target = self.syntax.nodes.items[@backingInt(marked.data.mut_argument)];
        const message = try std.fmt.allocPrint(self.allocator, "`{s}` writes only its receiver; remove `mut` from `{s}`", .{ spelling, self.src.text(target.span) });
        const marker: source.Span = .{ .start = marked.span.start, .end = target.span.start };
        return self.sink.failOwnershipFix(.{ .code = mutation_marker_code, .rule = .M3 }, marked.span, message, .{ .span = marker, .text = "" });
    }
    return first;
}
