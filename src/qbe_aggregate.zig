//! Concrete native record, array, and variant value lowering.
const managed_lower = @import("qbe_managed.zig");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const rc_aggregate = @import("qbe_rc_aggregate.zig");
const runtime_mode = @import("runtime_mode.zig");
/// Errors reported while emitting native operations.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
/// Emit aggregate operations using native layouts and independent value snapshots.
pub fn emit(self: anytype, op: @FieldType(bytecode.Instruction, "op"), stack: []const typed.Type) Error!void {
    if (try rc_aggregate.emit(@TypeOf(self.*), self, op, stack)) return;
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
            if (try fieldWriteAt(@TypeOf(self), self, self.pc)) |write| return fieldWriteRead(@TypeOf(self), self, write, h);
            const source = try self.load("s", h - 1);
            const member = try self.field(stack[h - 1], index);
            if (try boxRead(@TypeOf(self), self, stack, source)) return;
            var value = try self.readValue(try self.address(source, member.offset), member.ty);
            const shared = self.program.records[stack[h - 1].recordIndex()].isManagedRecord() and !self.isScalar(member.ty);
            if (shared and !try elementRead(@TypeOf(self), self, self.pc, h, member.ty)) {
                const snapshot = try self.aggregatePointer();
                try self.writeValue(snapshot, value, member.ty);
                value = snapshot;
            }
            try self.store(h - 1, value);
        },
        .update_record => |record| {
            const base = h - record.indices.len - 1;
            if (try fieldWriteUpdating(@TypeOf(self), self, self.pc)) |write| return self.store(base, try fieldWriteRecord(@TypeOf(self), self, write, base));
            const source = try self.load("s", base);
            const cell = self.program.records[record.ty.recordIndex()].isManagedRecord();
            // QBE-MOVE-ELIDE-1: a base whose value moves here, out of a local
            // no one reads again, is updated where it lives instead of in a
            // scratch copy.
            const in_place = self.moves.update(self.pc) != .copy;
            const pointer = if (cell or in_place) source else try self.aggregatePointer();
            if (!cell and !in_place) try self.print(" blit %v{d}, %v{d}, {d}\n", .{ source, pointer, (try self.layout(record.ty)).size });
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
        .get_index, .replace_index => try arrayAccess(self, op, stack),
        .make_variant => |variant| {
            const pointer = try self.aggregatePointer();
            const layout_value = try self.layout(variant.ty);
            try self.writeTag(variant.ty, variant.tag, pointer);
            const case = self.program.records[variant.ty.recordIndex()].shape.variants.?.cases[variant.tag];
            if (case.payload) |ty| {
                try self.writeValue(try self.address(pointer, layout_value.payload_offset), try self.load("s", h - 1), ty);
                try self.store(h - 1, pointer);
            } else try self.store(h, pointer);
            // ERROR-TRACE-1: a new `Err` value starts a fresh error return trace here.
            try @import("qbe_error_trace.zig").Lower(@TypeOf(self.*)).construction(self, variant.ty, variant.tag);
        },
        .switch_variant => |dispatch| {
            const pointer = try self.load("s", h - 1);
            const tag = try self.readTag(dispatch.ty, pointer);
            for (dispatch.arms, 0..) |arm, i| {
                const matches = self.temp();
                try self.print(" %v{d} =l ceql %v{d}, {d}\n jnz %v{d}, @arm{d}, @armnext{d}\n@arm{d}\n", .{ matches, tag, i, matches, matches, matches, matches });
                try armPayload(@TypeOf(self), self, dispatch.ty, arm.slot, i, pointer);
                try self.print(" jmp @{s}{d}\n@armnext{d}\n", .{ self.labelPrefix(arm.target), arm.target, matches });
            }
            try self.print(" jmp @failure\n", .{});
        },
        else => return error.InternalError,
    }
}

fn arrayAccess(self: anytype, op: @FieldType(bytecode.Instruction, "op"), stack: []const typed.Type) Error!void {
    const access = if (op == .replace_index) op.replace_index else op.get_index;
    const h = stack.len;
    const ty = access.ty;
    if (self.program.records[ty.recordIndex()].managed) return managed_lower.Lower(@TypeOf(self.*)).index(self, ty, stack);
    const layout_value = try self.layout(ty);
    const replacing = op == .replace_index;
    const base = h - @as(usize, if (replacing) 3 else 2);
    // QBE-ARRAYWRITE-1: a replace whose array is a local's own storage
    // and whose result the next instruction stores back into that local
    // writes the element where it already lives.
    const destination = if (replacing) try replaceDestination(@TypeOf(self), self, self.pc) else null;
    const rc_replace = replacing and @import("qbe_rc_frame.zig").get(@TypeOf(self.*), self) != null;
    var source = if (rc_replace) try rc_aggregate.prepareBase(@TypeOf(self.*), self, ty, base) else if (destination) |target| try localPointer(@TypeOf(self), self, target) else try self.load("s", base);
    // QBE-ARRAYWRITE-2: through a record field the operand already
    // names the field inside the record's own storage.
    const in_field = replacing and try fieldWriteReplacing(@TypeOf(self), self, self.pc) != null;
    const legacy_copy = replacing and !rc_replace;
    if (legacy_copy and destination == null and !in_field) {
        const copy = try self.aggregatePointer();
        try self.print(" blit %v{d}, %v{d}, {d}\n", .{ source, copy, layout_value.size });
        source = copy;
    }
    const element: Element = .{ .source = source, .result = base, .stride = layout_value.stride, .ty = layout_value.fields[0].ty, .value = if (replacing) h - 1 else null, .container = if (rc_replace) ty else null };
    try indexedElement(@TypeOf(self), self, access, stack[base + 1], .{ .slot = base + 1, .count = layout_value.count }, element);
}

/// A box reaching mutable collections needs a private shallow COW snapshot;
/// pure boxes use ordinary field lowering and its private-copy lifetime rules.
fn boxRead(comptime E: type, self: E, stack: []const typed.Type, source: usize) Error!bool {
    if (runtime_mode.enabled()) return false;
    if (self.cow == null or !@import("value_semantics.zig").enabled()) return false;
    if (!self.program.records[stack[stack.len - 1].recordIndex()].collection.box) return false;
    if (!@import("value_semantics.zig").needsCopy(self.program.records, stack[stack.len - 1])) return false;
    if (@import("qbe_cow.zig").Lower(@TypeOf(self.*)).scopedProjection(self, self.pc)) return false;
    const snapshot = try self.aggregatePointer();
    const done = self.temp();
    try self.print(" %v{d} =w call $myl_qbe_cow_unbox(l %ctx, l extern ${s}, l %v{d}, l %v{d})\n", .{ done, try self.descriptor(stack[stack.len - 1]), source, snapshot });
    try self.checkFailure("failure");
    try self.store(stack.len - 1, snapshot);
    return true;
}

/// The index operand of a fixed-array access and the array's element count.
const IndexOperand = struct { slot: usize, count: usize };

/// One fixed-array element access: the array's storage, the operand slot the
/// result lands in, the element stride and type, and for a `replace` the slot
/// holding the value written.
const Element = struct { source: usize, result: usize, stride: usize, ty: typed.Type, value: ?usize, container: ?typed.Type = null };

/// Load a fixed-array index, check it and read or write the element it names.
///
/// An enum table's key is a tag loaded from its variant. The checker leaves
/// `from_end` off where it proved the index non-negative, so those accesses
/// carry no extra instruction. The trap reports the index the program wrote,
/// before counting from the end, as a list's does.
fn indexedElement(comptime E: type, self: E, access: bytecode.Access, ty: typed.Type, operand: IndexOperand, element: Element) Error!void {
    const raw_index = try self.load("s", operand.slot);
    if (!self.isScalar(ty)) {
        const tag = self.temp();
        try self.print(" %v{d} =l loaduw %v{d}\n", .{ tag, raw_index });
        try boundsCheck(E, self, .{ .index = tag, .reported = tag, .limit = operand.count, .length = operand.count });
        return useElement(E, self, element, try elementAddress(E, self, element, tag));
    }
    const signed = if (ty.integer()) |info| info.signed else false;
    // QBE-LOOP-VERSION-1: an index the loop's guard proved non-negative
    // never counts from the end.
    const proven = if (self.loopAction()) |action| action.nonnegative else false;
    const counts_from_end = access.from_end and signed;
    if (!counts_from_end or proven) {
        try boundsCheck(E, self, .{ .index = raw_index, .reported = raw_index, .limit = operand.count, .length = operand.count });
        return useElement(E, self, element, try elementAddress(E, self, element, raw_index));
    }
    return fromEnd(E, self, raw_index, operand.count, element);
}

/// PY-ARRAY-NEGATIVE-1: an access whose index may count from the end, without
/// a branch. One unsigned test of `i + N` against `2N` accepts exactly
/// `-N <= i < N` (an overflowing sum is out of range either way), and the
/// address is the ordinary `base + i * stride` plus a correction of
/// `N * stride` selected by the sign mask (`i >> 63`, all ones exactly when `i`
/// is negative). Keeping the ordinary address as a term, rather than
/// rewriting the index first, leaves it the affine expression a loop's
/// induction variable produces, which is what lets an optimizer strength-reduce
/// it and share it between a read and a write of the same element.
fn fromEnd(comptime E: type, self: E, raw_index: usize, count: usize, element: Element) Error!void {
    const shifted = self.temp();
    try self.print(" %v{d} =l add %v{d}, {d}\n", .{ shifted, raw_index, count });
    try boundsCheck(E, self, .{ .index = shifted, .reported = raw_index, .limit = 2 * count, .length = count });
    const ordinary = try elementAddress(E, self, element, raw_index);
    const mask = self.temp();
    const correction = self.temp();
    const address_value = self.temp();
    try self.print(" %v{d} =l sar %v{d}, 63\n %v{d} =l and %v{d}, {d}\n", .{ mask, raw_index, correction, mask, count * element.stride });
    try self.print(" %v{d} =l add %v{d}, %v{d}\n", .{ address_value, ordinary, correction });
    return useElement(E, self, element, address_value);
}

/// The address of the element at position `index` of the array.
fn elementAddress(comptime E: type, self: E, element: Element, index: usize) Error!usize {
    const offset = self.temp();
    const address_value = self.temp();
    try self.print(" %v{d} =l mul %v{d}, {d}\n %v{d} =l add %v{d}, %v{d}\n", .{ offset, index, element.stride, address_value, element.source, offset });
    return address_value;
}

/// Read or write the element at a checked address.
fn useElement(comptime E: type, self: E, element: Element, address_value: usize) Error!void {
    if (element.value) |slot| {
        if (element.container) |array| return rc_aggregate.arrayElement(@TypeOf(self.*), self, .{ .array = array, .element = element.ty, .address = address_value, .source = element.source, .base = element.result, .input = slot });
        try self.writeValue(address_value, try self.load("s", slot), element.ty);
        try self.store(element.result, element.source);
    } else try self.store(element.result, try self.readValue(address_value, element.ty));
}

/// The unsigned range test of a fixed-array position against its count, and
/// its cold trap reporting `reported`. A loop copy's guard that proved the
/// position in bounds drops both (QBE-LOOP-VERSION-1).
fn boundsCheck(comptime E: type, self: E, check: RangeTest) Error!void {
    if (!self.checks) return;
    const invalid = self.temp();
    try self.print(" %v{d} =l cugel %v{d}, {d}\n jnz %v{d}, @bounds{d}, @index{d}\n", .{ invalid, check.index, check.limit, invalid, invalid, invalid });
    try self.print("@bounds{d}\n call $myl_qbe_fail_array_bounds(l %ctx, l %v{d}, l {d})\n jmp @failure\n@index{d}\n", .{ invalid, check.reported, check.length, invalid });
}

/// One unsigned range test: the value tested against `limit`, and the index
/// and array length a failure reports.
const RangeTest = struct { index: usize, reported: usize, limit: usize, length: usize };

/// Whether the instruction immediately before `pc` already wrote local `slot`
/// in place, so the store at `pc` has nothing left to copy: a record
/// constructor that built the record there, or a `replace` that wrote one
/// element of the array that already lives there.
pub fn storeForwarded(comptime E: type, self: E, pc: usize, slot: usize) Error!bool {
    if (pc == 0) return false;
    if (try constructorDestination(E, self, pc - 1)) |destination| return destination == slot;
    if (try replaceDestination(E, self, pc - 1)) |destination| return destination == slot;
    if (try fieldWriteUpdating(E, self, pc - 1)) |write| return write.slot == slot;
    return false;
}

/// QBE-ARRAYWRITE-2: one element write through a record field, `r.cells[i] = v`
/// on a value record local or `c.cells[i] = v` on a `class` reference, found
/// by the `get_field` that reads the field, the `replace_index` that rebuilds
/// it and the local both start from.
const FieldWrite = struct { read: usize, replace: usize, slot: usize, managed: bool };

/// The field-element write whose field read is the `get_field` at `pc`.
///
/// The statement the checker builds for `r.cells[i] = v` is `load r; load r;
/// get_field k; <index>; <value>; replace_index; update_record {k}; store r`:
/// the array is rebuilt with `replace`, put back into the record with an
/// update and the record stored back into its binding. When nothing between the
/// field read and the store can observe or change the record, all three write
/// the same bytes the element store alone writes, so the field read names the
/// field inside the record's own storage (a value record's frame slot, or a
/// `class` cell), the `replace` writes the element there after the same bounds
/// check, and the update and the store copy nothing. It is claimed only when:
///
///  - the statement starts with an empty operand stack and both loads read the
///    same local, reached by falling through; no branch enters the statement;
///  - a value record is this frame's own nonzero-sized value owning nothing,
///    not a parameter slot holding a caller's address; a `class` local holds
///    its cell pointer, and writing the cell is what the update means;
///  - the field is a fixed array of scalar elements, so the store needs no
///    collector or arena barrier;
///  - every instruction between the field read and the `replace` only pushes,
///    reads or computes scalars, so none can call, allocate, trap into a
///    handler or write the local — a trap still aborts before the element
///    store — and the value was computed before the element is written;
///  - the `replace` is followed by an update of exactly that field of exactly
///    that record type and a store into the same local.
fn fieldWriteAt(comptime E: type, self: E, pc: usize) Error!?FieldWrite {
    if (runtime_mode.enabled()) return null;
    const code = self.function.scope.instructions;
    if (pc < 2 or pc + 1 >= code.len) return null;
    const field_index = switch (code[pc].op) {
        .get_field => |index| index,
        else => return null,
    };
    const slot = switch (code[pc - 2].op) {
        .load_local => |target| @backingInt(target),
        else => return null,
    };
    switch (code[pc - 1].op) {
        .load_local => |target| if (@backingInt(target) != slot) return null,
        else => return null,
    }
    const start = self.states[pc - 2] orelse return null;
    if (start.len != 0 or branchTarget(E, self, pc - 1) or branchTarget(E, self, pc)) return null;
    if (slot >= self.function.scope.locals.len) return null;
    const record = self.function.scope.locals[slot].ty;
    if (!record.isAggregate()) return null;
    const schema = self.program.records[record.recordIndex()];
    if (!schema.isRecord() or schema.isCollection()) return null;
    if (schema.collection.box) return null;
    const managed = schema.isManagedRecord();
    if (!managed and !try ownRecord(E, self, slot, record)) return null;
    const array = (try self.field(record, field_index)).ty;
    if (!try scalarArray(E, self, array)) return null;
    const replace = try fieldWindow(E, self, pc + 1, slot) orelse return null;
    switch (code[replace].op) {
        .replace_index => |access| if (access.ty != array) return null,
        else => return null,
    }
    if (replace + 2 >= code.len or branchTarget(E, self, replace + 1) or branchTarget(E, self, replace + 2)) return null;
    if (self.states[replace + 1] == null or self.states[replace + 2] == null) return null;
    switch (code[replace + 1].op) {
        .update_record => |update| if (update.ty != record or update.indices.len != 1 or update.indices[0] != field_index) return null,
        else => return null,
    }
    switch (code[replace + 2].op) {
        .store_local => |target| if (@backingInt(target) != slot) return null,
        else => return null,
    }
    return .{ .read = pc, .replace = replace, .slot = slot, .managed = managed };
}

/// Whether value-record local `slot` holds its own nonzero-sized value owning nothing.
fn ownRecord(comptime E: type, self: E, slot: usize, record: typed.Type) Error!bool {
    if (self.byReference(slot)) return false;
    const value = try self.layout(record);
    return !value.drop and value.size != 0;
}

/// Whether `ty` is a fixed array (not a table) of scalar elements.
fn scalarArray(comptime E: type, self: E, ty: typed.Type) Error!bool {
    if (!ty.isAggregate()) return false;
    const schema = self.program.records[ty.recordIndex()];
    const shape = schema.shape.array orelse return false;
    if (schema.managed or shape.key != null or !self.isScalar(shape.element)) return false;
    const value = try self.layout(ty);
    return !value.drop and value.size != 0;
}

/// The `replace_index` that ends a field write's window starting at `from`,
/// when every instruction before it is a scalar push or computation that
/// neither writes local `slot` nor is entered by a branch.
fn fieldWindow(comptime E: type, self: E, from: usize, slot: usize) Error!?usize {
    const code = self.function.scope.instructions;
    var pc = from;
    while (pc < code.len) : (pc += 1) {
        const state = self.states[pc] orelse return null;
        if (branchTarget(E, self, pc) or state.len < 2) return null;
        if (state.len == 4 and code[pc].op == .replace_index) return pc;
        if (!try windowStep(E, self, code[pc].op, slot)) return null;
    }
    return null;
}

/// Whether one instruction inside a field write's window only pushes, reads or
/// computes a scalar without calling, allocating or writing local `slot`.
fn windowStep(comptime E: type, self: E, op: @FieldType(bytecode.Instruction, "op"), slot: usize) Error!bool {
    return switch (op) {
        .load_local, .push_i64, .push_integer, .push_bool, .add_i64_checked, .sub_i64_checked, .mul_i64_checked, .div_i64_checked, .rem_i64_checked, .neg_i64_checked, .cmp_i64, .cmp_bool, .not_bool, .unary_float, .array_length => true,
        .move_local => |target| @backingInt(target) != slot,
        .binary_integer => |binary| !binary.ty.isAggregate() or self.isScalar(binary.ty),
        .neg_integer, .cast_integer => |target| self.isScalar(target),
        .get_field => true,
        .get_index => |access| access.ty.isAggregate() and !self.program.records[access.ty.recordIndex()].managed,
        else => false,
    };
}

/// QBE-FIELDARRAY-READ-1: whether the fixed array a `class` field read at `pc`
/// pushes (to operand height `h`) is consumed only by one element read, with
/// nothing but scalar pushes and computations between them.
///
/// A field of a heap cell is otherwise snapshotted, because the cell can change
/// while the value is live. An element read that follows at once reads the same
/// bytes from the cell itself: no instruction in between can call, allocate or
/// write memory, so the field still holds what the snapshot would have copied,
/// and `c.cells[i]` costs a bounds check and a load instead of a whole-array
/// copy.
fn elementRead(comptime E: type, self: E, pc: usize, h: usize, array: typed.Type) Error!bool {
    if (!try scalarArray(E, self, array)) return false;
    const code = self.function.scope.instructions;
    var at = pc + 1;
    while (at < code.len) : (at += 1) {
        const state = self.states[at] orelse return false;
        if (branchTarget(E, self, at)) return false;
        if (at > pc + 1 and state.len <= h) return false;
        if (state.len == h + 1) switch (code[at].op) {
            .get_index => |access| return access.ty == array,
            else => {},
        };
        if (!try windowStep(E, self, code[at].op, self.function.scope.locals.len)) return false;
    }
    return false;
}

/// The field-element write whose `replace_index` is at `pc`.
fn fieldWriteReplacing(comptime E: type, self: E, pc: usize) Error!?FieldWrite {
    const code = self.function.scope.instructions;
    // The field read runs at height two, the loads under it; every instruction
    // of the window after it runs at height two or more but is not a field
    // read at height two, which needs an operand of its own above the array.
    var read = pc;
    while (read > 0) {
        read -= 1;
        const state = self.states[read] orelse return null;
        if (state.len < 2) return null;
        if (state.len == 2 and code[read].op == .get_field) break;
    } else return null;
    const write = try fieldWriteAt(E, self, read) orelse return null;
    return if (write.replace == pc) write else null;
}

/// The field-element write whose `update_record` is at `pc`.
fn fieldWriteUpdating(comptime E: type, self: E, pc: usize) Error!?FieldWrite {
    if (pc == 0) return null;
    switch (self.function.scope.instructions[pc].op) {
        .update_record => {},
        else => return null,
    }
    return fieldWriteReplacing(E, self, pc - 1);
}

/// The record a field write's update answers: the `class` cell pointer on the
/// operand stack, or the value record's own frame storage.
fn fieldWriteRecord(comptime E: type, self: E, write: FieldWrite, base: usize) Error!usize {
    return if (write.managed) self.load("s", base) else localPointer(E, self, write.slot);
}

/// Push the address of the written field inside the record's own storage.
fn fieldWriteRead(comptime E: type, self: E, write: FieldWrite, h: usize) Error!void {
    const index = switch (self.function.scope.instructions[write.read].op) {
        .get_field => |field_index| field_index,
        else => return error.InternalError,
    };
    const record = try fieldWriteRecord(E, self, write, h - 1);
    const member = try self.field(self.function.scope.locals[write.slot].ty, index);
    try self.store(h - 1, try self.address(record, member.offset));
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
    if (runtime_mode.enabled()) return null;
    const code = self.function.scope.instructions;
    const ty = switch (code[pc].op) {
        .replace_index => |access| access.ty,
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
    if (runtime_mode.enabled()) return null;
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
    // QBE-MOVE-ELIDE-1: a read of an alias reads this local's slot.
    for (code, 0..) |instruction, pc| if (reached[pc]) switch (instruction.op) {
        .load_local => |target| if (self.moves.resolve(@backingInt(target)) == slot) return true,
        else => {},
    };
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
