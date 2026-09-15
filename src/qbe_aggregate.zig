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
            const pointer = if (schema.isCell()) try allocateCell(@TypeOf(self), self, record.ty) else try self.aggregatePointer();
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
            if (self.program.records[stack[h - 1].recordIndex()].isCell() and !self.isScalar(member.ty)) {
                const snapshot = try self.aggregatePointer();
                try self.writeValue(snapshot, value, member.ty);
                value = snapshot;
            }
            try self.store(h - 1, value);
        },
        .update_record => |record| {
            const base = h - record.indices.len - 1;
            const source = try self.load("s", base);
            const cell = self.program.records[record.ty.recordIndex()].isCell();
            const pointer = if (cell) source else try self.aggregatePointer();
            if (!cell) try self.print(" blit %v{d}, %v{d}, {d}\n", .{ source, pointer, (try self.layout(record.ty)).size });
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
            var source = try self.load("s", base);
            var index = try self.load("s", base + 1);
            if (!self.isScalar(stack[base + 1])) {
                const tag = self.temp();
                try self.print(" %v{d} =l loaduw %v{d}\n", .{ tag, index });
                index = tag;
            }
            const invalid = self.temp();
            try self.print(" %v{d} =l cugel %v{d}, {d}\n jnz %v{d}, @bounds{d}, @index{d}\n", .{ invalid, index, layout_value.count, invalid, invalid, invalid });
            try self.print("@bounds{d}\n call $myl_qbe_fail_bounds(l %ctx)\n jmp @failure\n@index{d}\n", .{ invalid, invalid });
            if (replacing) {
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

fn allocateCell(comptime E: type, self: E, ty: typed.Type) Error!usize {
    const pointer = self.temp();
    try self.print(" %v{d} =l call $myl_native_heap_alloc(l %heap, l extern ${s}_body, l 1)\n", .{ pointer, try self.descriptor(ty) });
    try self.require(pointer, @import("qbe_format.zig").allocation_failure);
    return pointer;
}

fn armPayload(comptime E: type, self: E, ty_value: typed.Type, slot_value: ?typed.LocalId, i: usize, pointer: usize) Error!void {
    if (slot_value) |slot| {
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
