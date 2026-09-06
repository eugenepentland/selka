const std = @import("std");
const bytecode = @import("bytecode.zig");
const Op = @FieldType(bytecode.Instruction, "op");
/// Find a required opcode, failing explicitly when a corruption fixture is stale.
pub fn index(instructions: []const bytecode.Instruction, tag: std.meta.Tag(Op)) error{TestExpectedInstruction}!usize {
    for (instructions, 0..) |instruction, i| {
        if (std.meta.activeTag(instruction.op) == tag) return i;
    }
    return error.TestExpectedInstruction;
}
/// Return the mutable required instruction after checking its presence.
pub fn find(instructions: []bytecode.Instruction, tag: std.meta.Tag(Op)) error{TestExpectedInstruction}!*bytecode.Instruction {
    return &instructions[try index(instructions, tag)];
}
/// Count opcode occurrences without making assertions conditional on discovery.
pub fn count(instructions: []const bytecode.Instruction, tag: std.meta.Tag(Op)) usize {
    var total: usize = 0;
    for (instructions) |instruction| total += @intFromBool(std.meta.activeTag(instruction.op) == tag);
    return total;
}

test "missing corruption target returns TestExpectedInstruction" {
    try std.testing.expectError(error.TestExpectedInstruction, index(&.{}, .call));
}
