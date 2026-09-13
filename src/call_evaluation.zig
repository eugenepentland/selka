//! Preserve keyword argument evaluation order using existing local statements.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const Span = @import("source.zig").Span;
const arguments = @import("call_arguments.zig");
const Target = union(enum) { none, value: usize, literal: usize };
const Output = @FieldType(@FieldType(typed.Node, "data"), "call");

/// Checked storage and call metadata needed for source-order temporary bindings.
pub const Context = struct {
    storage: struct { nodes: *std.ArrayList(typed.Node), locals: *std.ArrayList(typed.Local), statements: *std.ArrayList(typed.Statement) },
    span: Span,
    call: arguments.Call,
    parameters: []const ast.Parameter,
    arena_depth: usize,

    /// Save supplied operands in source order and release those roots after calling.
    pub fn apply(self: Context, allocator: std.mem.Allocator, out: *Output) std.mem.Allocator.Error!void {
        var reordered = false;
        for (self.call.evaluation_order, 0..) |position, index| reordered = reordered or position != index;
        if (!reordered) return;
        const targets = try allocator.alloc(Target, self.parameters.len);
        defer allocator.free(targets);
        const values = try allocator.dupe(typed.NodeId, out.arguments);
        const literals = try allocator.dupe(typed.LiteralArgument, out.literals);
        var value_index: usize = 0;
        var reference_index: usize = 0;
        for (self.parameters, targets) |parameter, *target| {
            target.* = .none;
            if (parameter.reference != null) {
                const reference = out.references[reference_index];
                reference_index += 1;
                for (literals, 0..) |literal, index| if (literal.reference == reference) {
                    target.* = .{ .literal = index };
                    break;
                };
            } else {
                target.* = .{ .value = value_index };
                value_index += 1;
            }
        }
        var body: std.ArrayList(typed.StatementId) = .empty;
        var cleanup: std.ArrayList(typed.LocalId) = .empty;
        for (self.call.evaluation_order) |parameter_index| {
            const target = targets[parameter_index];
            const input = switch (target) {
                .none => continue,
                .value => |index| values[index],
                .literal => |index| literals[index].value,
            };
            const original = self.storage.nodes.items[@backingInt(input)];
            const slot: typed.LocalId = @fromBackingInt(self.storage.locals.items.len);
            try self.storage.locals.append(allocator, .{
                .name = "<argument>",
                .declaration = original.span,
                .ty = original.ty,
                .mutable = false,
                .ownership = .{ .arena_depth = self.arena_depth },
                .usage = .{ .temporary = true, .reads = 1 },
            });
            const statement: typed.StatementId = @fromBackingInt(self.storage.statements.items.len);
            try self.storage.statements.append(allocator, .{ .span = original.span, .terminates = false, .data = .{ .initialize = .{ .slot = slot, .value = input } } });
            try body.append(allocator, statement);
            try cleanup.append(allocator, slot);
            const read: typed.NodeId = @fromBackingInt(self.storage.nodes.items.len);
            try self.storage.nodes.append(allocator, .{ .span = original.span, .ty = original.ty, .data = .{ .local = slot } });
            switch (target) {
                .none => unreachable,
                .value => |index| values[index] = read,
                .literal => |index| literals[index].value = read,
            }
        }
        const block: typed.StatementId = @fromBackingInt(self.storage.statements.items.len);
        try self.storage.statements.append(allocator, .{ .span = self.span, .terminates = false, .data = .{ .block = try body.toOwnedSlice(allocator) } });
        out.arguments = values;
        out.literals = literals;
        out.evaluation = .{ .body = block, .cleanup = try cleanup.toOwnedSlice(allocator) };
    }
};
