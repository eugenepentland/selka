//! Physical sole-owner provenance for newly admitted RC loop-entry checks.
const bytecode = @import("bytecode.zig");
const cow = @import("cow_plan.zig");
const frame = @import("qbe_rc_frame.zig");
const inert = @import("qbe_rc_inert_receiver.zig");
const edges = @import("qbe_rc_edges.zig");
const Op = @FieldType(bytecode.Instruction, "op");
const Family = struct {
    locals: [8]usize = undefined,
    stores: [8]usize = undefined,
    reads: [8]usize = undefined,
    len: usize = 0,
};

/// Trace a fresh list through exact temporary handoffs and real edge releases.
/// Every use of that allocation family is audited, including enclosing-loop
/// iterations, so no earlier alias can make a zero-iteration entry allocate.
pub fn proven(comptime E: type, self: *E, root: usize, head: usize) frame.Error!bool {
    const code = self.function.scope.instructions;
    const stack = self.states[head] orelse return false;
    if (code.len > 4096 or stack.len != 0) return false;
    var family: Family = .{};
    var local = root;
    var before = head;
    while (family.len < family.locals.len) {
        const at = definition(E, self, local) orelse return false;
        if (at >= before or at == 0 or self.isBranchTarget(at)) return false;
        family.locals[family.len] = local;
        family.stores[family.len] = at;
        family.reads[family.len] = cow.none;
        family.len += 1;
        const producer = code[at - 1].op;
        if (fresh(E, self, local, producer)) break;
        var read = at - 1;
        if (producer == .value_copy) {
            const analysis = self.ownership orelse return false;
            if (read >= analysis.copies.len or analysis.copies[read]) return false;
            if (read == 0 or self.isBranchTarget(read)) return false;
            read -= 1;
        }
        if (code[read].op != .load_local) return false;
        const source = @backingInt(code[read].op.load_local);
        if (contains(family, source) or self.function.scope.locals[source].ty != self.function.scope.locals[local].ty) return false;
        if (!try edges.releasesAt(E, self, at, source)) return false;
        family.reads[family.len - 1] = read;
        before = read;
        local = source;
    } else return false;
    const back = self.cow.?.plan.loops.back[head];
    if (back == cow.none) return false;
    return uses(E, self, family, back);
}

/// An extra restriction on an already certified fresh append root. Trace the
/// same bounded handoffs to an empty constructor, then refuse any earlier
/// receiver use: the list still has zero capacity when this loop is entered.
/// This does not admit a root or change the existing ownership certificate.
pub fn emptyBefore(comptime E: type, self: *E, root: usize, head: usize) bool {
    const code = self.function.scope.instructions;
    if (code.len > 4096 or head >= code.len) return false;
    var family: Family = .{};
    var local = root;
    var before = head;
    while (family.len < family.locals.len) {
        const at = definition(E, self, local) orelse return false;
        if (at >= before or at == 0 or self.isBranchTarget(at)) return false;
        family.locals[family.len] = local;
        family.stores[family.len] = at;
        family.reads[family.len] = cow.none;
        family.len += 1;
        const producer = code[at - 1].op;
        if (fresh(E, self, local, producer)) {
            const empty = switch (producer) {
                .make_record => |made| made.fields == 0 and made.payload.len == 0,
                .acquire_buffer => at >= 2 and !self.isBranchTarget(at - 1) and
                    code[at - 2].op == .push_i64 and code[at - 2].op.push_i64 == 0,
                else => false,
            };
            if (!empty) return false;
            return untouched(code, family, head);
        }
        var read = at - 1;
        if (producer == .value_copy) {
            if (read == 0 or self.isBranchTarget(read)) return false;
            read -= 1;
        }
        if (code[read].op != .load_local) return false;
        const source = @backingInt(code[read].op.load_local);
        if (contains(family, source)) return false;
        family.reads[family.len - 1] = read;
        before = read;
        local = source;
    }
    return false;
}

fn untouched(code: []const bytecode.Instruction, family: Family, head: usize) bool {
    const start = family.stores[family.len - 1] - 1;
    for (code[start..head], start..) |instruction, pc| switch (instruction.op) {
        .load_local => |slot| if (contains(family, @backingInt(slot))) {
            for (family.reads[0..family.len]) |read| {
                if (read == pc) break;
            } else return false;
        },
        .buffer_operation => |operation| if (contains(family, @backingInt(operation.owner))) return false,
        else => {},
    };
    return true;
}

fn contains(family: Family, local: usize) bool {
    for (family.locals[0..family.len]) |item| if (item == local) return true;
    return false;
}

fn definition(comptime E: type, self: *E, local: usize) ?usize {
    if (local < self.function.signature.parameter_count or self.byReference(local) or self.callerStorage(local)) return null;
    const plan = self.cow.?.plan;
    if (plan.place(local) != null or plan.aliases[local] != cow.none) return null;
    const role = self.cow.?.rc.?.plan.locals.entry[local].ownership;
    if (role != .empty) return null;
    var result: ?usize = null;
    for (self.function.scope.instructions, 0..) |instruction, pc| switch (instruction.op) {
        .store_local => |slot| if (@backingInt(slot) == local) {
            if (result != null) return null;
            result = pc;
        },
        .ref_local, .move_local, .drop_local => |slot| if (@backingInt(slot) == local) return null,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (arm.slot) |slot| if (@backingInt(slot) == local) return null;
        },
        else => {},
    };
    return result;
}

fn fresh(comptime E: type, self: *E, local: usize, op: Op) bool {
    const ty = self.function.scope.locals[local].ty;
    if (!ty.isAggregate()) return false;
    const record = self.program.records[ty.recordIndex()];
    if (!record.isCollection() or record.collection.box or record.collection.kind != .list) return false;
    const element = record.shape.buffer orelse return false;
    const shape = self.cow.?.rc.?.catalog.get(element) catch return false;
    if (shape.counted or shape.unique_drop) return false;
    return switch (op) {
        .acquire_buffer => |result| result == ty,
        .make_record => |result| result.ty == ty and result.payload.len == 0,
        else => false,
    };
}

fn uses(comptime E: type, self: *E, family: Family, back: usize) bool {
    const code = self.function.scope.instructions;
    const start = family.stores[family.len - 1] - 1;
    var remaining: usize = 262144;
    for (code, 0..) |instruction, pc| {
        // An outer backedge may re-create the allocation. It may never skip
        // that fresh producer and re-enter after a previous alias escaped.
        if (externalEntry(instruction.op, pc, start, back)) return false;
        if (pc < start or pc > back) continue;
        if (instruction.inline_origin != null) return false;
        switch (instruction.op) {
            // Explicit region transitions can make a handoff a migration.
            .begin_arena, .end_arena => return false,
            .load_local => |slot| if (contains(family, @backingInt(slot))) {
                var handoff = false;
                for (family.reads[0..family.len]) |read| if (pc == read) {
                    handoff = true;
                };
                if (!handoff) {
                    if (code.len > remaining) return false;
                    remaining -= code.len;
                    if (!receiver(E, self, pc)) return false;
                }
            },
            .buffer_operation => |operation| if (contains(family, @backingInt(operation.owner))) {
                const shape = self.cow.?.rc.?.catalog.get(operation.output) catch return false;
                if (shape.counted or shape.unique_drop) return false;
                switch (operation.kind) {
                    .length, .capacity, .read, .write, .append => {},
                    else => return false,
                }
            },
            else => {},
        }
    }
    return true;
}

// Only separately certified no-token receiver captures may duplicate a family
// pointer. The generic local store would acquire O or LOAN and is refused.
fn receiver(comptime E: type, self: *E, pc: usize) bool {
    const code = self.function.scope.instructions;
    if (pc + 1 >= code.len or code[pc + 1].op != .store_local or self.isBranchTarget(pc + 1)) return false;
    const local = @backingInt(code[pc + 1].op.store_local);
    const plan = self.cow.?.plan;
    for (pc..pc + 2) |at| {
        if (plan.at(at).shares.len != 0 or plan.at(at).read_captures.len != 0) return false;
    }
    const role = self.cow.?.rc.?.plan.locals.entry[local].ownership;
    if (role == .borrowed and role.borrowed == .storage) return true;
    return inert.emptyLocal(E, self, local);
}

fn externalEntry(op: Op, pc: usize, start: usize, back: usize) bool {
    if (pc >= start and pc <= back) return false;
    return switch (op) {
        .jump, .jump_if_false => |target| target > start and target <= back,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (arm.target > start and arm.target <= back) break true;
        } else false,
        .try_result => |propagate| propagate.error_target > start and propagate.error_target <= back,
        else => false,
    };
}
