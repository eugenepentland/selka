//! RC-ELEMENT-TAKE-1: a match arm moves an element's payload into its binding
//! when the arm certainly replaces that same element before anything can
//! observe it.
//!
//! `match objects[i]: case K(p): f = p.field; change(mut f); objects[i] = K(..f..)`
//! on a `mut` list parameter is the same-slot return `COW-INDEX-RETURN-1`
//! proves: the read is the parameter's first use, the index is unchanged,
//! nothing between the arm's entry and the element write reads the list or the
//! binding (other than the binding's scalar fields and the one extraction),
//! every continuing path ends in that write, and neither temporary survives
//! it. Copying the payload into the binding left the element owning a second
//! token of everything the payload holds, so the extracted field could never be
//! unique and its first mutation cloned it. Moving the payload instead leaves
//! the element's payload bytes zero until the write replaces the element; zero
//! bytes are every RC value's empty cleanup form, so a trap in between tears
//! the heap down as usual (`RC-TRAP-TEARDOWN-1`) and the write's release of the
//! old element releases nothing. The move happens only when the scrutinee is
//! the element's own storage and the list is physically unique when the arm
//! runs; otherwise the arm copies as before.
const std = @import("std");
const typed = @import("typed.zig");
const shapes = @import("rc_shape.zig");
const semantics = @import("value_semantics.zig");

/// Allocation failure or an inconsistent analysis; refusal is ordinary lowering.
pub const Error = error{ InternalError, OutOfMemory };
/// One arm binding that moves its payload out of the element it matched.
pub const Take = struct {
    /// The `switch_variant` whose scrutinee is the checked element read before it.
    dispatch: usize,
    /// The arm's payload binding.
    slot: usize,
    /// The list local the element was read from.
    list: usize,
    /// The local holding the element's normalized index.
    index: usize,
};

/// Certify every same-slot return arm whose binding can own the payload.
pub fn build(comptime E: type, self: *E, catalog: *shapes.Catalog) Error![]const Take {
    const code = self.function.scope.instructions;
    if (code.len > 4096 or self.function.policy.c_abi or self.function.policy.host != null) return &.{};
    if (!candidate(code)) return &.{};
    const analysis = self.ownership orelse return &.{};
    const ownership = @import("ownership.zig");
    var context = ownership.context(self.allocator, .{ .program = self.program, .function = self.function, .states = self.states, .live = self.live.? }) catch |err| return translate(err);
    const returns = @import("ownership_index_return.zig").proven(&context, analysis.copies) catch |err| return translate(err);
    var found: std.ArrayList(Take) = .empty;
    for (returns) |proof| {
        const take = try admitted(E, self, proof.dispatch, proof.payload, catalog) orelse continue;
        try found.append(self.allocator, take);
    }
    return found.toOwnedSlice(self.allocator);
}

/// The certificate for the arm binding `slot` at `dispatch`, if any.
pub fn find(takes: []const Take, dispatch: usize, slot: usize) ?Take {
    for (takes) |take| if (take.dispatch == dispatch and take.slot == slot) return take;
    return null;
}

// A dispatch straight after a checked element read of a list local.
fn candidate(code: []const @import("bytecode.zig").Instruction) bool {
    for (code, 0..) |instruction, pc| {
        if (instruction.op != .switch_variant or pc < 2) continue;
        const read = code[pc - 1].op;
        if (read == .buffer_operation and read.buffer_operation.kind == .read and code[pc - 2].op == .load_local) return true;
    }
    return false;
}

// The binding keeps its payload in its own slot as an ordinary owner and the
// payload owns counted edges a move can relocate; the scrutinee is an element
// read of a list local at an index local.
fn admitted(comptime E: type, self: *E, dispatch: usize, payload: u32, catalog: *shapes.Catalog) Error!?Take {
    const code = self.function.scope.instructions;
    if (dispatch < 2 or code[dispatch].op != .switch_variant or code[dispatch].op.switch_variant.borrowed) return null;
    const read = code[dispatch - 1].op;
    if (read != .buffer_operation or read.buffer_operation.kind != .read or code[dispatch - 2].op != .load_local) return null;
    const list = @backingInt(read.buffer_operation.owner);
    const index = @backingInt(code[dispatch - 2].op.load_local);
    const slot: usize = payload;
    if (self.byReference(slot) or self.callerStorage(slot) or self.borrowsElement(slot)) return null;
    if (self.byReference(list) or self.callerStorage(list) or self.byReference(index)) return null;
    const ty = self.function.scope.locals[slot].ty;
    if (!ty.isAggregate() or semantics.containsLiveView(self.program.records, ty)) return null;
    const shape = catalog.get(ty) catch |err| return translate(err);
    if (!shape.counted or shape.unique_drop) return null;
    const layout = catalog.native.layout(ty) catch return error.InternalError;
    if (layout.drop or layout.copy == .prohibited or layout.size == 0) return null;
    if (!try @import("rc_field_authority.zig").movable(catalog, ty)) return null;
    const scrutinee: typed.Type = read.buffer_operation.output;
    if (scrutinee != code[dispatch].op.switch_variant.ty) return null;
    return .{ .dispatch = dispatch, .slot = slot, .list = list, .index = index };
}

fn translate(err: anyerror) Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
}
