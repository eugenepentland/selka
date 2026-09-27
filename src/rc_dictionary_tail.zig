//! Emission-independent dictionary capture lifetime and certificate data.
const bytecode = @import("bytecode.zig");
/// Shared late-proof scan allowance; metadata/stack rows consume one unit each.
pub const Budget = struct {
    left: usize = 262144,

    /// Refuse before visiting work beyond the remaining candidate allowance.
    pub fn take(self: *Budget, amount: usize) bool {
        if (amount > self.left) return false;
        self.left -= amount;
        return true;
    }
};
/// A closed five-op tail; only start + 1 stores its borrowed receiver.
pub const Certificate = struct {
    start: usize,
    root: usize,
    receiver: usize,
    key: usize,
    value: usize,
    key_authority: union(enum) { canonical, anchored: Key } = .canonical,
    empty_drops: ?EmptyDrops = null,
};
/// A canonical store resets operand zero before a closed, nonpublishing loop.
pub const EmptyDrops = struct { reset: usize, back: usize, get: usize };
/// Whole-local zero-token key and capture, anchored by one real list owner.
pub const Key = struct {
    anchor: @import("rc_model.zig").Anchor,
    receiver: usize,
    capture: usize,
    projection: usize,
};

/// The two raw stores are authorized together; all other stores keep ownership.
pub fn borrowedStore(proofs: []const Certificate, pc: usize, local: usize) bool {
    for (proofs) |proof| if (proof.key_authority == .anchored) {
        const key = proof.key_authority.anchored;
        if ((pc == key.capture and local == key.receiver) or
            (pc == key.projection + 1 and local == proof.key)) return true;
    };
    return false;
}
/// Only the exact read's pointer result bypasses ordinary LOAN publication.
pub fn borrowedRead(proofs: []const Certificate, pc: usize) bool {
    for (proofs) |proof| if (proof.key_authority == .anchored and
        proof.key_authority.anchored.projection == pc) return true;
    return false;
}
/// Bypass type-wide H handling only for the proven raw list input and store.
pub fn rawCapture(proofs: []const Certificate, pc: usize) bool {
    for (proofs) |proof| if (proof.key_authority == .anchored) {
        const at = proof.key_authority.anchored.capture;
        if (pc == at - 1 or pc == at) return true;
    };
    return false;
}

/// Exact physical consumers only; setup and later owning uses keep their guards.
pub fn emptyDrop(proofs: []const Certificate, pc: usize, journal: usize, locals: usize) bool {
    for (proofs) |proof| if (proof.empty_drops) |empty| {
        const key = proof.key_authority.anchored;
        if (journal == locals and (pc == empty.get or pc == proof.start + 1 or pc == proof.start + 4)) return true;
        if (journal == key.receiver and pc == key.projection + 1) return true;
        if (journal == proof.receiver and pc == proof.start + 1) return true;
    };
    return false;
}

/// No admitted operation can pass this operand guard to a runtime publisher.
pub fn closedOperand(proofs: []const Certificate, pc: usize, journal: usize, locals: usize) bool {
    if (journal != locals) return false;
    for (proofs) |proof| if (proof.empty_drops) |empty| {
        if (pc > empty.reset and pc <= empty.back) return true;
    };
    return false;
}

/// Raw locals never publish; the shared operand may own before and after the loop.
pub fn forbidsPublication(proofs: []const Certificate, pc: usize, journal: usize, locals: usize) bool {
    if (closedOperand(proofs, pc, journal, locals)) return true;
    for (proofs) |proof| if (proof.empty_drops != null) {
        if (journal == proof.receiver or journal == proof.key or journal == proof.key_authority.anchored.receiver) return true;
    };
    return false;
}

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
