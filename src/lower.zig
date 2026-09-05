//! Iterative lowering preserves source evaluation order without recursive host expression walks.
const std = @import("std");
const typed = @import("typed.zig");
const bc = @import("bytecode.zig");
const Work = union(enum) {
    expression: struct { id: typed.NodeId, emit: bool = false },
    statement: typed.StatementId,
    instruction: bc.Instruction,
};
fn binaryInstruction(binary: anytype, nodes: []const typed.Node) bc.Instruction {
    return .{ .span = binary.op_span, .op = switch (binary.op) {
        .add => .add_i64_checked,
        .sub => .sub_i64_checked,
        .mul => .mul_i64_checked,
        .eq, .ne => if (nodes[@backingInt(binary.left)].ty == .bool)
            .{ .cmp_bool = if (binary.op == .eq) .eq else .ne }
        else
            .{ .cmp_i64 = if (binary.op == .eq) .eq else .ne },
        .lt, .le, .gt, .ge => .{ .cmp_i64 = std.meta.stringToEnum(bc.Predicate, @tagName(binary.op)).? },
    } };
}
pub fn lower(allocator: std.mem.Allocator, program: typed.Program) !bc.Program {
    const functions = try allocator.alloc(bc.Function, program.functions.len);
    for (program.functions, functions) |function, *out| {
        var code: std.ArrayList(bc.Instruction) = .empty;
        var work: std.ArrayList(Work) = .empty;
        defer work.deinit(allocator);
        try work.append(allocator, .{ .statement = function.body });
        while (work.pop()) |task| switch (task) {
            .instruction => |instruction| try code.append(allocator, instruction),
            .statement => |id| {
                const stmt = program.statements[@backingInt(id)];
                switch (stmt.data) {
                    .block => |children| {
                        var i = children.len;
                        while (i > 0) {
                            i -= 1;
                            try work.append(allocator, .{ .statement = children[i] });
                        }
                    },
                    .ret => |value| {
                        try work.append(allocator, .{ .instruction = .{ .span = stmt.span, .op = .ret } });
                        try work.append(allocator, .{ .expression = .{ .id = value } });
                    },
                    .initialize, .assign => |store| {
                        try work.append(allocator, .{ .instruction = .{ .span = stmt.span, .op = .{ .store_local = store.slot } } });
                        try work.append(allocator, .{ .expression = .{ .id = store.value } });
                    },
                }
            },
            .expression => |expr| {
                const index = @backingInt(expr.id);
                if (index >= program.nodes.len) return error.InternalError;
                const node = program.nodes[index];
                switch (node.data) {
                    .integer => |value| try code.append(allocator, .{ .span = node.span, .op = .{ .push_i64 = value } }),
                    .boolean => |value| try code.append(allocator, .{ .span = node.span, .op = .{ .push_bool = value } }),
                    .local => |slot| try code.append(allocator, .{ .span = node.span, .op = .{ .load_local = slot } }),
                    .unary => |u| {
                        try work.append(allocator, .{ .instruction = .{ .span = u.op_span, .op = if (u.op == .neg) .neg_i64_checked else .not_bool } });
                        try work.append(allocator, .{ .expression = .{ .id = u.operand } });
                    },
                    .binary => |b| {
                        if (expr.emit) {
                            try code.append(allocator, binaryInstruction(b, program.nodes));
                        } else {
                            try work.append(allocator, .{ .expression = .{ .id = expr.id, .emit = true } });
                            try work.append(allocator, .{ .expression = .{ .id = b.right } });
                            try work.append(allocator, .{ .expression = .{ .id = b.left } });
                        }
                    },
                }
            },
        };
        out.* = .{ .id = function.id, .name = function.name, .locals = function.locals, .instructions = try code.toOwnedSlice(allocator) };
    }
    const result: bc.Program = .{ .functions = functions };
    try bc.validate(result);
    return result;
}
