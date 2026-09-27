//! Emission-independent dictionary capture lifetime and certificate data.
const bytecode = @import("bytecode.zig");
/// A closed five-op tail; only start + 1 stores its borrowed receiver.
pub const Certificate = struct { start: usize, root: usize, receiver: usize, key: usize, value: usize };

/// Reject every explicit capture publisher/use outside its one raw store/write.
pub fn writers(code: []const bytecode.Instruction, proof: Certificate) bool {
    var roots: usize = 0;
    var keys: usize = 0;
    for (code, 0..) |instruction, pc| switch (instruction.op) {
        .store_local => |id| {
            const at = @backingInt(id);
            if (at == proof.receiver and pc != proof.start + 1) return false;
            if (at == proof.root) {
                roots += 1;
                if (pc >= proof.start) return false;
            }
            if (at == proof.key) keys += 1;
        },
        .load_local => |id| if (@backingInt(id) == proof.receiver) return false,
        .move_local, .ref_local, .drop_local => |id| {
            const at = @backingInt(id);
            if (at == proof.root or at == proof.receiver or at == proof.key) return false;
        },
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (arm.slot) |id| {
                const at = @backingInt(id);
                if (at == proof.root or at == proof.receiver or at == proof.key) return false;
            }
        },
        .buffer_operation => |operation| if (@backingInt(operation.owner) == proof.receiver and pc != proof.start + 4) return false,
        else => {},
    };
    return roots == 1 and keys != 0;
}

const t = @import("std").testing;
const span: @import("source.zig").Span = .{ .start = 0, .end = 0 };
fn fixtureOp(op: @FieldType(bytecode.Instruction, "op")) bytecode.Instruction {
    return .{ .span = span, .op = op };
}
// spec-case: RC-DICTIONARY-TAIL-1
test "RC dictionary tail writer proof preserves zero tokens across repeated tails" {
    const proof: Certificate = .{ .start = 3, .root = 0, .receiver = 1, .key = 2, .value = 3 };
    var code = [_]bytecode.Instruction{
        fixtureOp(.{ .store_local = @fromBackingInt(0) }),
        fixtureOp(.{ .store_local = @fromBackingInt(2) }),
        fixtureOp(.{ .store_local = @fromBackingInt(2) }),
        fixtureOp(.{ .load_local = @fromBackingInt(0) }),
        fixtureOp(.{ .store_local = @fromBackingInt(1) }),
        fixtureOp(.{ .load_local = @fromBackingInt(2) }),
        fixtureOp(.{ .load_local = @fromBackingInt(3) }),
        fixtureOp(.{ .buffer_operation = .{ .owner = @fromBackingInt(1), .kind = .write, .output = .unit } }),
        fixtureOp(.{ .jump = 3 }),
    };
    try t.expect(writers(&code, proof));
    code[8] = fixtureOp(.{ .store_local = @fromBackingInt(1) });
    try t.expect(!writers(&code, proof));
    code[8] = fixtureOp(.{ .load_local = @fromBackingInt(1) });
    try t.expect(!writers(&code, proof));
    code[8] = fixtureOp(.{ .ref_local = @fromBackingInt(0) });
    try t.expect(!writers(&code, proof));
    code[8] = fixtureOp(.{ .move_local = @fromBackingInt(2) });
    try t.expect(!writers(&code, proof));
    code[8] = fixtureOp(.{ .switch_variant = .{ .ty = .unit, .arms = &.{.{ .target = 3, .slot = @fromBackingInt(1) }} } });
    try t.expect(!writers(&code, proof));
}
