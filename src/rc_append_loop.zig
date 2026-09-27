//! Bounded CFG authority for lazy scalar-append readiness reuse.
const bytecode = @import("bytecode.zig");
/// A stable root in the closed loop whose external entries reset admission.
pub const Certificate = struct { head: usize, back: usize, root: usize };
/// Interior entry or a backwards escape could reuse another dynamic lifetime.
pub fn validEdge(op: @FieldType(bytecode.Instruction, "op"), pc: usize, proof: Certificate) bool {
    return @import("ownership_sources.zig").targetsSatisfy(op, pc, proof, edge);
}
fn edge(pc: usize, target: usize, proof: Certificate) bool {
    if (pc >= proof.head and pc <= proof.back) return target >= proof.head;
    return target <= proof.head or target > proof.back;
}

const t = @import("std").testing;
// spec-case: RC-PLAIN-APPEND-1
test "RC append loop admits reset entries and refuses interior entry and backwards escape" {
    const proof: Certificate = .{ .head = 10, .back = 20, .root = 3 };
    const arms = [_]bytecode.SwitchArm{ .{ .target = 10, .slot = null }, .{ .target = 12, .slot = null } };
    try t.expect(validEdge(.{ .jump = 10 }, 25, proof));
    try t.expect(validEdge(.{ .jump = 10 }, 20, proof));
    try t.expect(validEdge(.{ .jump_if_false = 30 }, 15, proof));
    try t.expect(!validEdge(.{ .jump = 12 }, 5, proof));
    try t.expect(!validEdge(.{ .jump_if_false = 9 }, 15, proof));
    try t.expect(!validEdge(.{ .try_result = .{ .input = .unit, .output = .unit, .error_target = 15 } }, 25, proof));
    try t.expect(validEdge(.{ .switch_variant = .{ .ty = .unit, .arms = arms[0..1] } }, 25, proof));
    try t.expect(!validEdge(.{ .switch_variant = .{ .ty = .unit, .arms = &arms } }, 25, proof));
}
