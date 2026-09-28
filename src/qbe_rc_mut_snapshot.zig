//! RC-MUT-PAYLOAD-SNAPSHOT-1: which elided `value_copy`s RC still makes real.
const runtime_mode = @import("runtime_mode.zig");

/// Whether the `value_copy` at `pc` copies a whole `mut` list, dictionary, set
/// or byte buffer parameter under RC. An elided copy still stores an owner
/// into the named local, and a later write through the parameter then found
/// two owners and cloned the payload into the callee's own slot, detaching it
/// from the caller's value. A real copy publishes the snapshot instead, so the
/// parameter stays the caller's unique payload.
pub fn at(comptime E: type, self: *const E, pc: usize) bool {
    if (!runtime_mode.enabled() or pc == 0) return false;
    const code = self.function.scope.instructions;
    if (pc >= code.len or code[pc].op != .value_copy or self.branch_targets[pc]) return false;
    const read = code[pc - 1].op;
    if (read != .load_local) return false;
    const local = @backingInt(read.load_local);
    const cow_state = self.cow orelse return false;
    const state = cow_state.rc orelse return false;
    if (local >= state.contract.parameters.len) return false;
    return state.contract.parameters[local] == .mutable_payload;
}
