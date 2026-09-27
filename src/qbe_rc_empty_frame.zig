//! Closed physical admission for bodies whose private journals stay empty.
const typed = @import("typed.zig");
const bytecode = @import("bytecode.zig");
const cow = @import("cow_plan.zig");
const frame = @import("qbe_rc_frame.zig");
const unique = @import("qbe_rc_unique.zig");
const Op = @FieldType(bytecode.Instruction, "op");

/// Keep ordinary lowering/storage, omitting only a provably empty frame's link.
/// Unknown publications retain the complete runtime protocol; emitter guards
/// independently refuse publication after this certificate has been installed.
pub fn finalize(comptime E: type, self: *E) frame.Error!void {
    const state = frame.get(E, self) orelse return;
    state.plan.journal.unlinked = try certify(E, self);
}

fn certify(comptime E: type, self: *E) frame.Error!bool {
    if (self.entry or @import("qbe_rc_borrow.zig").active(E, self)) return false;
    const code = self.function.scope.instructions;
    if (code.len > 4096 or self.function.scope.locals.len > 4096) return false;
    if (!self.isScalar(self.function.signature.return_type) or
        !plain(E, self, self.function.signature.return_type)) return false;
    const root = parameter(E, self) orelse return false;
    for (self.function.scope.locals, 0..) |local, index| {
        if (self.byReference(index) or self.callerStorage(index)) return false;
        if (index != root and !frame.emptyLocal(E, self, index)) {
            if (!plain(E, self, local.ty)) return false;
        }
    }
    // These lists include implicit operations absent from the bytecode itself.
    // No scope, mark, field clone or loop-entry detachment can be hidden here.
    for (self.cow.?.plan.loops.entries) |entries| if (entries.len != 0) return false;
    var remaining: usize = 262144;
    for (code, 0..) |instruction, pc| {
        if (instruction.inline_origin != null) return false;
        const capture = self.cow.?.captures[pc];
        if (capture.begin != cow.none or capture.active != cow.none) return false;
        const site = self.cow.?.plan.at(pc);
        if (site.shares.len != 0 or site.read_captures.len != 0 or site.unique_field != null) return false;
        for (site.unique) |check| {
            if (check.local != root) return false;
            if (check.alias != cow.none and !frame.emptyLocal(E, self, check.alias)) return false;
        }
        if (self.states[pc]) |stack| {
            if (stack.len > remaining) return false;
            remaining -= stack.len;
            if (!try operation(E, self, instruction.op, pc, stack)) return false;
        }
    }
    return true;
}

// Initially one exact mut-list root; ordinary inputs are edge-free scalars.
// The caller's scope stays linked and owns every pin through return or trap.
fn parameter(comptime E: type, self: *E) ?usize {
    var root: ?usize = null;
    for (self.function.scope.locals[0..self.function.signature.parameter_count], 0..) |local, index| {
        if (plain(E, self, local.ty) and self.isScalar(local.ty)) continue;
        if (root != null or !unique.stableMutParameter(E, self, index)) return null;
        root = index;
    }
    return root;
}

fn plain(comptime E: type, self: *E, ty: typed.Type) bool {
    const shape = self.cow.?.rc.?.catalog.get(ty) catch return false;
    return !shape.counted and !shape.unique_drop;
}

fn operation(comptime E: type, self: *E, op: Op, pc: usize, stack: []const typed.Type) frame.Error!bool {
    // A managed load is an unguarded word used immediately by a separately
    // certified receiver store. No branch or semantic publication intervenes.
    if (op == .load_local and !plain(E, self, self.function.scope.locals[@backingInt(op.load_local)].ty)) {
        const code = self.function.scope.instructions;
        if (pc + 1 >= code.len or self.isBranchTarget(pc + 1) or code[pc + 1].op != .store_local) return false;
        return frame.emptyLocal(E, self, @backingInt(code[pc + 1].op.store_local));
    }
    if (op == .store_local and frame.emptyLocal(E, self, @backingInt(op.store_local))) return true;
    for (stack) |ty| if (!plain(E, self, ty)) return false;
    return switch (op) {
        .load_local, .store_local, .drop_local => |local| plain(E, self, self.function.scope.locals[@backingInt(local)].ty),
        .get_field => plainResult(E, self, pc),
        .update_record => |update| try updateRecord(E, self, update),
        .buffer_operation => |buffer| bufferOperation(E, self, buffer),
        .value_copy => |copy| plain(E, self, copy.ty),
        .cast_integer, .neg_integer, .wrap_domain, .unwrap_domain => |ty| plain(E, self, ty) and self.isScalar(ty),
        .binary_integer => |binary| plain(E, self, binary.ty) and self.isScalar(binary.ty),
        .cmp_domain => |comparison| plain(E, self, comparison.ty),
        .cmp_enum => |comparison| plain(E, self, comparison.ty),
        .push_integer => |value| plain(E, self, value.ty) and self.isScalar(value.ty),
        .push_i64,
        .push_bool,
        .push_unit,
        .jump,
        .jump_if_false,
        .add_i64_checked,
        .sub_i64_checked,
        .mul_i64_checked,
        .div_i64_checked,
        .rem_i64_checked,
        .neg_i64_checked,
        .cmp_i64,
        .cmp_bool,
        .not_bool,
        .unary_float,
        .assert_true,
        .pop,
        .acknowledge,
        .ret,
        => true,
        else => false,
    };
}

fn plainResult(comptime E: type, self: *E, pc: usize) bool {
    if (pc + 1 >= self.states.len) return false;
    const output = self.states[pc + 1] orelse return false;
    return output.len != 0 and plain(E, self, output[output.len - 1]);
}

fn updateRecord(comptime E: type, self: *E, update: @FieldType(Op, "update_record")) frame.Error!bool {
    const record = self.program.records[update.ty.recordIndex()];
    if (!plain(E, self, update.ty) or record.isManagedRecord() or (try self.layout(update.ty)).size == 0) return false;
    for (update.indices) |index| {
        const field = try self.field(update.ty, index);
        // Only the direct scalar replacement arm has no pending publication.
        if (!plain(E, self, field.ty)) return false;
        if (!self.isScalar(field.ty) or (try self.layout(field.ty)).size == 0) return false;
    }
    return true;
}

fn bufferOperation(comptime E: type, self: *E, buffer: @FieldType(Op, "buffer_operation")) bool {
    const index = @backingInt(buffer.owner);
    if (!frame.emptyLocal(E, self, index) or !plain(E, self, buffer.output)) return false;
    const ty = self.function.scope.locals[index].ty;
    const record = self.program.records[ty.recordIndex()];
    if (!record.isCollection() or record.collection.box or record.collection.kind != .list) return false;
    if (!plain(E, self, record.shape.buffer orelse return false)) return false;
    return switch (buffer.kind) {
        .length, .read => true,
        .write => @import("qbe_rc_inert_receiver.zig").proven(E, self, index),
        else => false,
    };
}
