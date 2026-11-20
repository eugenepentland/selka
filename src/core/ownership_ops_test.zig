//! The operation table of the ownership certificates (docs/design/ownership-certificates.md §3) agrees with the
//! ownership pass it describes.
const std = @import("std");
const ir = @import("ir.zig");
const own = @import("own.zig");
const ops = @import("ownership_ops.zig");
const flags = @import("flags.zig");

/// The operand positions worth comparing for `op`: the positions the operation actually has. A record, union or
/// box constructor, a take and a return have any number; an update has the container, then its stored operands.
fn comparedPositions(op: ir.Op) usize {
    return switch (ops.row(op).consumes) {
        .none, .all, .first_and_tail => 5,
        .first_two => 2,
        .first => if (op == .list_pop) 1 else 2,
    };
}

/// Whether the table consumes the same operand positions as the ownership pass's own table, for every
/// operation, with and without the lent-box marker.
fn tableAgreesWithOwnershipPass() bool {
    for (std.enums.values(ir.Op)) |op| {
        for ([_]u64{ 0, flags.lent_box }) |data| {
            const inst: ir.Inst = .{ .op = op, .ty = .void, .data = data };
            for (0..comparedPositions(op)) |position| {
                if (ops.consumesAt(inst, position) != own.consuming(inst, position)) return false;
            }
        }
    }
    return true;
}

test "the operation table consumes the operand positions the ownership pass consumes" {
    try std.testing.expect(tableAgreesWithOwnershipPass());
}

/// No terminator defines a value.
fn valueRulesMatchTerminators() bool {
    for (std.enums.values(ir.Op)) |op| {
        if (op.terminates() and ops.definesValue(op)) return false;
    }
    return true;
}

test "no terminator defines a value" {
    try std.testing.expect(valueRulesMatchTerminators());
}

test "the rows C1 corrected: array_get is a slot read, copy is a forward, str_char and text_frame are verified" {
    try std.testing.expectEqual(ops.Class.project, ops.classOf(.array_get));
    try std.testing.expectEqual(ops.Class.forward, ops.classOf(.copy));
    try std.testing.expectEqual(ops.Class.character, ops.classOf(.str_char));
    try std.testing.expectEqual(ops.ResultRule.fresh, ops.row(.str_char).result);
    try std.testing.expectEqual(ops.Class.text_frame, ops.classOf(.text_frame));
    try std.testing.expectEqual(ops.ResultRule.frame, ops.row(.text_frame).result);
    try std.testing.expectEqual(ops.ResultRule.immortal, ops.row(.undef).result);
    try std.testing.expectEqual(ops.Consumes.first_two, ops.row(.list_push).consumes);
    try std.testing.expectEqual(ops.Consumes.first, ops.row(.list_pop).consumes);
}

test "a lent box consumes nothing and a plain box consumes its operand" {
    const lent: ir.Inst = .{ .op = .box_make, .ty = .void, .data = flags.lent_box };
    const plain: ir.Inst = .{ .op = .box_make, .ty = .void };
    try std.testing.expect(!ops.consumesAt(lent, 0));
    try std.testing.expect(ops.consumesAt(plain, 0));
}
