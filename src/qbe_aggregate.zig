//! Concrete native record, array, and variant value lowering.
const managed_lower = @import("qbe_managed.zig");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
/// Errors reported while emitting native operations.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
/// Emit aggregate operations using native layouts and independent value snapshots.
pub fn emit(self: anytype, op: @FieldType(bytecode.Instruction, "op"), stack: []const typed.Type) Error!void {
    const h = stack.len;
    switch (op) {
        .make_record => |record| {
            const schema = self.program.records[record.ty.recordIndex()];
            if (schema.isCollection()) return managed_lower.Lower(@TypeOf(self.*)).construct(self, record, stack);
            const destination = try constructorDestination(@TypeOf(self), self, self.pc);
            const pointer = if (destination) |slot|
                try localPointer(@TypeOf(self), self, slot)
            else if (schema.isManagedRecord())
                try @import("qbe_alloc.zig").cell(@TypeOf(self), self, record.ty, stack)
            else
                try self.aggregatePointer();
            for (0..record.fields) |i| {
                const field_index = if (record.order.len == 0) i else record.order[i];
                const member = try self.field(record.ty, field_index);
                try self.writeValue(try self.address(pointer, member.offset), try self.load("s", h - record.fields + i), member.ty);
            }
            try self.store(h - record.fields, pointer);
        },
        .get_field => |index| {
            const source = try self.load("s", h - 1);
            const member = try self.field(stack[h - 1], index);
            var value = try self.readValue(try self.address(source, member.offset), member.ty);
            if (self.program.records[stack[h - 1].recordIndex()].isManagedRecord() and !self.isScalar(member.ty)) {
                const snapshot = try self.aggregatePointer();
                try self.writeValue(snapshot, value, member.ty);
                value = snapshot;
            }
            try self.store(h - 1, value);
        },
        .update_record => |record| {
            const base = h - record.indices.len - 1;
            const source = try self.load("s", base);
            const cell = self.program.records[record.ty.recordIndex()].isManagedRecord();
            const pointer = if (cell) source else try self.aggregatePointer();
            if (!cell) try self.print(" blit %v{d}, %v{d}, {d}\n", .{ source, pointer, (try self.layout(record.ty)).size });
            if (cell and try storesReference(@TypeOf(self), self, record.ty, record.indices)) try @import("qbe_alloc.zig").barrier(@TypeOf(self), self, pointer);
            for (record.indices, 0..) |index, i| {
                const member = try self.field(record.ty, index);
                if (cell) {
                    const value_pointer = self.temp();
                    const operand = if (self.isScalar(member.ty)) "copy" else "loadl";
                    try self.print(" %v{d} =l {s} %s{d}\n", .{ value_pointer, operand, base + 1 + i });
                    try @import("qbe_arena.zig").Lower(@TypeOf(self.*)).barrier(self, pointer, member.ty, value_pointer);
                }
                try self.writeValue(try self.address(pointer, member.offset), try self.load("s", base + 1 + i), member.ty);
            }
            try self.store(base, pointer);
        },
        .array_length => |ty| {
            if (self.program.records[ty.recordIndex()].managed) return managed_lower.Lower(@TypeOf(self.*)).length(self, ty, stack);
            try self.print(" storel {d}, %s{d}\n", .{ (try self.layout(ty)).count, h - 1 });
        },
        .get_index, .replace_index => |ty| {
            if (self.program.records[ty.recordIndex()].managed) return managed_lower.Lower(@TypeOf(self.*)).index(self, ty, stack);
            const layout_value = try self.layout(ty);
            const replacing = op == .replace_index;
            const base = h - @as(usize, if (replacing) 3 else 2);
            // QBE-ARRAYWRITE-1: a replace whose array is a local's own storage
            // and whose result the next instruction stores back into that local
            // writes the element where it already lives.
            const destination = if (replacing) try replaceDestination(@TypeOf(self), self, self.pc) else null;
            var source = if (destination) |target| try localPointer(@TypeOf(self), self, target) else try self.load("s", base);
            var index = try self.load("s", base + 1);
            if (!self.isScalar(stack[base + 1])) {
                const tag = self.temp();
                try self.print(" %v{d} =l loaduw %v{d}\n", .{ tag, index });
                index = tag;
            }
            // QBE-UNCHECKED-1: the element address below is the operation; the
            // unsigned range test and its cold trap block are what go away.
            if (self.checks) {
                const invalid = self.temp();
                try self.print(" %v{d} =l cugel %v{d}, {d}\n jnz %v{d}, @bounds{d}, @index{d}\n", .{ invalid, index, layout_value.count, invalid, invalid, invalid });
                try self.print("@bounds{d}\n call $myl_qbe_fail_array_bounds(l %ctx, l %v{d}, l {d})\n jmp @failure\n@index{d}\n", .{ invalid, index, layout_value.count, invalid });
            }
            if (replacing and destination == null) {
                const copy = try self.aggregatePointer();
                try self.print(" blit %v{d}, %v{d}, {d}\n", .{ source, copy, layout_value.size });
                source = copy;
            }
            const offset = self.temp();
            const address_value = self.temp();
            try self.print(" %v{d} =l mul %v{d}, {d}\n %v{d} =l add %v{d}, %v{d}\n", .{ offset, index, layout_value.stride, address_value, source, offset });
            if (replacing) {
                try self.writeValue(address_value, try self.load("s", h - 1), layout_value.fields[0].ty);
                try self.store(base, source);
            } else try self.store(base, try self.readValue(address_value, layout_value.fields[0].ty));
        },
        .make_variant => |variant| {
            const pointer = try self.aggregatePointer();
            const layout_value = try self.layout(variant.ty);
            try self.print(" storew {d}, %v{d}\n", .{ variant.tag, pointer });
            const case = self.program.records[variant.ty.recordIndex()].shape.variants.?.cases[variant.tag];
            if (case.payload) |ty| {
                try self.writeValue(try self.address(pointer, layout_value.payload_offset), try self.load("s", h - 1), ty);
                try self.store(h - 1, pointer);
            } else try self.store(h, pointer);
        },
        .switch_variant => |dispatch| {
            const pointer = try self.load("s", h - 1);
            const tag = self.temp();
            try self.print(" %v{d} =l loaduw %v{d}\n", .{ tag, pointer });
            for (dispatch.arms, 0..) |arm, i| {
                const matches = self.temp();
                try self.print(" %v{d} =l ceql %v{d}, {d}\n jnz %v{d}, @arm{d}, @armnext{d}\n@arm{d}\n", .{ matches, tag, i, matches, matches, matches, matches });
                try armPayload(@TypeOf(self), self, dispatch.ty, arm.slot, i, pointer);
                try self.print(" jmp @i{d}\n@armnext{d}\n", .{ arm.target, matches });
            }
            try self.print(" jmp @failure\n", .{});
        },
        else => return error.InternalError,
    }
}

/// Whether the instruction immediately before `pc` already wrote local `slot`
/// in place, so the store at `pc` has nothing left to copy: a record
/// constructor that built the record there, or a `replace` that wrote one
/// element of the array that already lives there.
pub fn storeForwarded(comptime E: type, self: E, pc: usize, slot: usize) Error!bool {
    if (pc == 0) return false;
    if (try constructorDestination(E, self, pc - 1)) |destination| return destination == slot;
    if (try replaceDestination(E, self, pc - 1)) |destination| return destination == slot;
    return false;
}

/// QBE-ARRAYWRITE-1: the local a `replace` writes one element of in place, when
/// the very next instruction stores the replaced array back into it.
///
/// `replace(x, i, v)` is a whole-value expression: it copies the array, writes
/// one element of the copy and yields the copy. When that copy's only reader is
/// a store back into the very local the array was read from, both copies are
/// dead — the one into the per-pc aggregate scratch and the one back out of it —
/// so the element is written straight into the local's own storage, after the
/// same bounds check against the same length, raising the same trap at the same
/// source position. The destination is claimed only where nothing else can
/// observe the change:
///
///  - the array operand is the local's own storage rather than a snapshot of
///    it: the read that pushed it is a `load_local` or `move_local` of this
///    local, reached by falling through, which is exactly the window
///    `borrowableLocal` walks forward from, so `readLocal` named the slot;
///  - that read ran with an empty operand stack, so the replace is a whole
///    statement and no other live operand can still name the old value;
///  - the local owns nothing (`drop`), holds its own value — not a scalar, not
///    a zero-length aggregate, and not a parameter slot holding a caller's
///    address — and its type is the array's own type;
///  - no branch enters the store, and nothing between the read and the replace
///    is entered by a branch or writes the local.
///
/// The element operand may name storage inside the same array (`x =
/// replace(x, i, x[j])` over an array of aggregates); an element written from
/// an element is a region of the array's own stride copied onto an
/// element-aligned region of the same stride, so the two are the same region or
/// disjoint, exactly as they were when the write went to the scratch copy.
fn replaceDestination(comptime E: type, self: E, pc: usize) Error!?usize {
    const code = self.function.scope.instructions;
    const ty = switch (code[pc].op) {
        .replace_index => |array| array,
        else => return null,
    };
    if (self.program.records[ty.recordIndex()].managed) return null;
    if (pc + 1 >= code.len or self.states[pc + 1] == null) return null;
    if (branchTarget(E, self, pc + 1)) return null;
    const slot = switch (code[pc + 1].op) {
        .store_local => |target| @backingInt(target),
        else => return null,
    };
    if (slot >= self.function.scope.locals.len) return null;
    if (self.function.scope.locals[slot].ty != ty) return null;
    // A `mut` array parameter's slot holds the caller's address, and writing
    // the caller's array is what its element write means.
    if (self.isScalar(ty) or (self.byReference(slot) and !self.callerStorage(slot))) return null;
    const value = try self.layout(ty);
    if (value.drop or value.size == 0) return null;
    if (!borrowsLocal(E, self, pc, slot)) return null;
    return slot;
}

/// Whether the array operand of the `replace_index` at `pc` is local `slot`'s
/// own storage rather than a copy of it.
///
/// The operand was pushed by the last instruction that ran with an empty
/// operand stack, because the operand sits at the bottom of the stack for the
/// whole window; that instruction must read this local. Nothing in the window
/// is entered by a branch or writes the local, which is the same window
/// `borrowableLocal` walks forward from the read, so that read named the slot
/// instead of snapshotting it into scratch.
fn borrowsLocal(comptime E: type, self: E, pc: usize, slot: usize) bool {
    const code = self.function.scope.instructions;
    const state = self.states[pc] orelse return false;
    if (state.len != 3 or branchTarget(E, self, pc)) return false;
    var producer = pc;
    while (producer > 0) {
        producer -= 1;
        const before = self.states[producer] orelse return false;
        if (before.len == 0) break;
        if (branchTarget(E, self, producer) or writesLocal(code[producer].op, slot)) return false;
    } else return false;
    return switch (code[producer].op) {
        .load_local, .move_local => |target| @backingInt(target) == slot,
        else => false,
    };
}

/// Whether the instruction at `pc` is entered by a branch, so control can reach
/// it without having run the instruction before it.
fn branchTarget(comptime E: type, self: E, pc: usize) bool {
    return pc < self.branch_targets.len and self.branch_targets[pc];
}

/// Whether one instruction writes local `slot`: a whole-value store, a move
/// that clears it, an explicit drop, a match arm's payload binding, or a
/// `ref_local` handing its storage to a callee that writes through it.
fn writesLocal(op: @FieldType(bytecode.Instruction, "op"), slot: usize) bool {
    return switch (op) {
        .store_local, .move_local, .drop_local, .ref_local => |target| @backingInt(target) == slot,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (arm.slot) |target| if (@backingInt(target) == slot) break true;
        } else false,
        else => false,
    };
}

/// QBE-CTORFWD-1: the local a record constructor fills in place, when the very
/// next instruction stores the constructed record into it.
///
/// Forwarding writes the same field stores, in the same order, into the local's
/// own storage instead of the per-pc aggregate scratch, so the copy out of that
/// scratch — and the now-dead scratch declaration — disappear. Every operand was
/// already evaluated into its slot before the constructor runs and a plain
/// record construction calls nothing, so no allocation, trap or step check can
/// observe the destination part-way through. The destination is claimed only
/// where nothing else can observe the change:
///
///  - the local owns nothing (`drop`), so no release of its old value has to
///    happen before the new one lands, exactly like the store this replaces;
///  - the local holds its own value — not a scalar, not a zero-length aggregate,
///    and not a parameter slot holding a caller's address — and its type is the
///    constructor's type;
///  - the store is the constructor's only reader: no branch enters it directly,
///    so it runs only over the record the constructor just built in the local;
///  - no instruction that can reach the constructor reads the local, so no live
///    operand can name the destination's storage and be read back half
///    overwritten (`p = Pair(a=p.b, b=p.a)`).
fn constructorDestination(comptime E: type, self: E, pc: usize) Error!?usize {
    const code = self.function.scope.instructions;
    const record = switch (code[pc].op) {
        .make_record => |record| record,
        else => return null,
    };
    const schema = self.program.records[record.ty.recordIndex()];
    if (schema.isManagedRecord() or schema.isCollection()) return null;
    if (pc + 1 >= code.len or self.states[pc + 1] == null) return null;
    if (pc + 1 < self.branch_targets.len and self.branch_targets[pc + 1]) return null;
    const slot = switch (code[pc + 1].op) {
        .store_local => |target| @backingInt(target),
        else => return null,
    };
    if (slot >= self.function.scope.locals.len) return null;
    if (self.function.scope.locals[slot].ty != record.ty) return null;
    if (self.isScalar(record.ty) or self.byReference(slot)) return null;
    const value = try self.layout(record.ty);
    if (value.drop or value.size == 0) return null;
    if (try reachableRead(E, self, pc, slot)) return null;
    return slot;
}

/// The pointer a forwarded constructor or replace writes through: the address
/// of the destination local itself, or the caller's array a `mut` array
/// parameter's slot holds.
fn localPointer(comptime E: type, self: E, slot: usize) Error!usize {
    if (self.byReference(slot)) return self.load("l", slot);
    const pointer = self.temp();
    try self.print(" %v{d} =l copy %l{d}\n", .{ pointer, slot });
    return pointer;
}

/// Whether any instruction that can reach `at` reads local `slot`. Such a read
/// is the only way this frame can put the address of the local's own storage
/// into an operand slot, so it is exactly what makes building in place visible.
fn reachableRead(comptime E: type, self: E, at: usize, slot: usize) Error!bool {
    const code = self.function.scope.instructions;
    const reached = try self.allocator.alloc(bool, code.len);
    defer self.allocator.free(reached);
    @memset(reached, false);
    reached[at] = true;
    var changed = true;
    while (changed) {
        changed = false;
        var from = code.len;
        while (from > 0) {
            from -= 1;
            if (reached[from] or self.states[from] == null) continue;
            if (!flowsInto(code[from].op, from, reached)) continue;
            reached[from] = true;
            changed = true;
        }
    }
    for (code, 0..) |instruction, pc| if (reached[pc] and readsLocal(instruction.op, slot)) return true;
    return false;
}

/// Whether control leaving the instruction at `from` can enter an instruction
/// already known to reach the target. The relation is the one the bytecode
/// validator walks stack heights along: a `switch_variant` leaves only through
/// its arm targets, a `ret` leaves nowhere, and every other instruction but an
/// unconditional `jump` also falls through to the next pc.
fn flowsInto(op: @FieldType(bytecode.Instruction, "op"), from: usize, reached: []const bool) bool {
    const linear = from + 1 < reached.len and reached[from + 1];
    return switch (op) {
        .jump => |target| inRange(target, reached),
        .jump_if_false => |target| inRange(target, reached) or linear,
        .try_result => |propagate| inRange(propagate.error_target, reached) or linear,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (inRange(arm.target, reached)) break true;
        } else false,
        .ret => false,
        else => linear,
    };
}

fn inRange(target: usize, reached: []const bool) bool {
    return target < reached.len and reached[target];
}

/// Whether one instruction reads local `slot` into an operand. A whole-value
/// store is not a read: the address it consumes was read where it was produced.
fn readsLocal(op: @FieldType(bytecode.Instruction, "op"), slot: usize) bool {
    return switch (op) {
        .load_local, .move_local, .drop_local, .ref_local => |target| @backingInt(target) == slot,
        else => false,
    };
}

/// Whether a field update of a class body stores anything the collector
/// traces, which is when the generational barrier must see it. A store of
/// scalars alone cannot make an old body reference a young object.
fn storesReference(comptime E: type, self: E, ty: typed.Type, indices: []const usize) Error!bool {
    for (indices) |index| if ((try self.layout((try self.field(ty, index)).ty)).trace) return true;
    return false;
}

fn armPayload(comptime E: type, self: E, ty_value: typed.Type, slot_value: ?typed.LocalId, i: usize, pointer: usize) Error!void {
    if (slot_value) |slot| {
        // QBE-MATCHPROJ-1: a projected binding already names the payload where it
        // lives — `initializeStorage` stored that address once at entry — so the
        // arm reads the scrutinee's own storage instead of copying it out.
        if (self.byReference(@backingInt(slot))) return;
        const ty = self.function.scope.locals[@backingInt(slot)].ty;
        const payload = try self.readValue(try self.address(pointer, (try self.layout(ty_value)).payload_offset), ty);
        if (self.isScalar(ty)) try self.print(" storel %v{d}, %l{d}\n", .{ payload, @backingInt(slot) }) else try self.print(" blit %v{d}, %l{d}, {d}\n", .{ payload, @backingInt(slot), (try self.layout(ty)).size });
    } else if (self.program.records[ty_value.recordIndex()].shape.variants.?.cases[i].payload) |payload_ty| {
        if ((try self.layout(payload_ty)).drop) {
            const payload = try self.address(pointer, (try self.layout(ty_value)).payload_offset);
            try self.print(" call $myl_native_owned_drop(l %heap, l extern ${s}, l %v{d})\n", .{ try self.descriptor(payload_ty), payload });
        }
    }
}
