//! Exact typed constant pushes used by frozen bytes/text data emission.
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
/// Validate the same contiguous literal inputs before proof or static emission.
pub fn frozen(code: []const bytecode.Instruction, pc: usize, record: @FieldType(@FieldType(bytecode.Instruction, "op"), "make_record"), element: typed.Type, text: bool) bool {
    if (record.order.len != 0 or pc < record.fields or pc > code.len) return false;
    for (code[pc - record.fields .. pc]) |instruction| switch (instruction.op) {
        .push_integer => |number| {
            if (number.ty != element) return false;
            if (text) {
                if (number.value < 0 or number.value > 0x10ffff) return false;
                if (number.value >= 0xd800 and number.value <= 0xdfff) return false;
            }
        },
        else => return false,
    };
    return true;
}
