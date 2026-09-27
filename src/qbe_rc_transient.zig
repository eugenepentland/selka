//! RC-TRANSIENT-FIELD-1: field reads consumed by the very next instruction.
//!
//! `load_local x; get_field a; get_field b` and `...; get_field b;
//! value_copy` read fields out of a local that nothing can write before the
//! next instruction consumes them. The next field read projects its own
//! field out of this one at once, and a real value copy acquires its own
//! owner from the bits at once. A loan on the intermediate value (for a
//! record, one hold per edge) only protected bits that no operation between
//! the two instructions could release, so the read publishes no token.
const bytecode = @import("bytecode.zig");
const semantics = @import("value_semantics.zig");
const Op = @FieldType(bytecode.Instruction, "op");

/// The longest `get_field` chain one read looks back through.
const chain_limit = 16;

/// Whether the `get_field` at the current pc publishes its result without a
/// token.
pub fn projection(comptime E: type, self: *E, op: Op) bool {
    if (op != .get_field) return false;
    const pc = self.pc;
    const code = self.function.scope.instructions;
    if (pc + 1 >= code.len or self.isBranchTarget(pc + 1)) return false;
    const next = self.states[pc + 1] orelse return false;
    if (next.len == 0) return false;
    const result = next[next.len - 1];
    if (!result.isAggregate() or semantics.isLiveView(self.program.records, result)) return false;
    if (!rawInput(E, self, pc, chain_limit)) return false;
    return switch (code[pc + 1].op) {
        .get_field => true,
        .value_copy => |copy| copy.ty == result and @import("qbe_value_copy.zig").Lower(E).copies(self, pc + 1),
        else => false,
    };
}

// The consumed record was pushed by a plain local read, or by a field read
// of one that itself published no token, with no entry in between.
fn rawInput(comptime E: type, self: *E, pc: usize, remaining: usize) bool {
    if (pc == 0 or remaining == 0 or self.isBranchTarget(pc)) return false;
    const code = self.function.scope.instructions;
    const stack = self.states[pc] orelse return false;
    if (stack.len == 0 or !plainRecord(E, self, stack[stack.len - 1])) return false;
    return switch (code[pc - 1].op) {
        .load_local => true,
        .get_field => rawInput(E, self, pc - 1, remaining - 1),
        else => false,
    };
}

// A value record read in place: not a class body, collection or box.
fn plainRecord(comptime E: type, self: *E, ty: @import("typed.zig").Type) bool {
    if (!ty.isAggregate()) return false;
    const record = self.program.records[ty.recordIndex()];
    return record.isRecord() and !record.managed and !record.isCollection();
}
