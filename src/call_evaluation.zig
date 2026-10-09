//! Preserve keyword argument evaluation order using existing local statements.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const Span = @import("source.zig").Span;
const arguments = @import("call_arguments.zig");

/// Checked storage and call metadata needed for source-order temporary bindings.
pub const Context = struct {
    storage: struct { nodes: *std.ArrayList(typed.Node), locals: *std.ArrayList(typed.Local), statements: *std.ArrayList(typed.Statement) },
    span: Span,
    call: arguments.Call,
    parameters: []const ast.Parameter,

    /// Preserve written operand order without replacing mut places with value temporaries.
    pub fn apply(self: Context, allocator: std.mem.Allocator, out: anytype) std.mem.Allocator.Error!void {
        out.evaluation_order = try allocator.dupe(usize, self.call.evaluation_order);
    }
};
