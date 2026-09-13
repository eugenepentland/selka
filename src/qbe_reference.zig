//! Direct native references to statically validated owner storage.
const slice_failure = "myl_qbe_fail_slice";
const copy_value = " blit %v{d}, %v{d}, {d}\n";
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
/// Errors reported while emitting native operations.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
/// Bind operation lowering to the concrete backend emitter.
pub fn Lower(comptime E: type) type {
    return struct {
        /// Emit lexical borrowing, native loan transfers, and value snapshots.
        pub fn emit(self: *E, op: @FieldType(bytecode.Instruction, "op"), stack: []const typed.Type) Error!void {
            const h = stack.len;
            switch (op) {
                .begin_borrow, .begin_slice => |reference_id| try begin(self, reference_id, op == .begin_slice, h),
                .split_borrow => |split| {
                    const reference = self.function.scope.references[@backingInt(split.left)];
                    const source = try sourceSlice(self, reference);
                    const middle = try self.load("s", h - 1);
                    const valid = self.temp();
                    try self.print(" %v{d} =l culel %v{d}, %v{d}\n", .{ valid, middle, source.length });
                    try self.require(valid, slice_failure);
                    try saveSlice(self, split.left, source.pointer, middle);
                    const offset = self.temp();
                    const right = self.temp();
                    const count = self.temp();
                    try self.print(
                        " %v{d} =l mul %v{d}, {d}\n %v{d} =l add %v{d}, %v{d}\n %v{d} =l sub %v{d}, %v{d}\n",
                        .{ offset, middle, (try self.layout(reference.ty)).size, right, source.pointer, offset, count, source.length, middle },
                    );
                    try saveSlice(self, split.right, right, count);
                },
                .len_slice => |reference| try self.store(h, try sliceLength(self, reference)),
                .read_slice, .write_slice => |reference| {
                    const writing = op == .write_slice;
                    const base = h - @as(usize, if (writing) 2 else 1);
                    const index = try self.load("s", base);
                    const length = try sliceLength(self, reference);
                    const valid = self.temp();
                    try self.print(" %v{d} =l cultl %v{d}, %v{d}\n", .{ valid, index, length });
                    try self.require(valid, slice_failure);
                    const ty = self.function.scope.references[@backingInt(reference)].ty;
                    const source = try self.load("r", @backingInt(reference));
                    const offset = self.temp();
                    const pointer = self.temp();
                    try self.print(" %v{d} =l mul %v{d}, {d}\n %v{d} =l add %v{d}, %v{d}\n", .{ offset, index, (try self.layout(ty)).size, pointer, source, offset });
                    if (writing) try self.writeValue(pointer, try self.load("s", h - 1), ty) else if (self.isScalar(ty)) try self.store(base, try self.readValue(pointer, ty)) else {
                        const snapshot = try self.aggregatePointer();
                        try self.print(copy_value, .{ pointer, snapshot, (try self.layout(ty)).size });
                        try self.store(base, snapshot);
                    }
                },
                .end_borrow => |reference| try self.print(" storel 0, %r{d}\n", .{@backingInt(reference)}),
                .capture_ref => |reference| {
                    if (self.function.signature.return_reference.?.slice) try self.print(" blit %r{d}, %captured, 16\n", .{@backingInt(reference)}) else {
                        const pointer = try self.load("r", @backingInt(reference));
                        try self.print(" storel %v{d}, %captured\n", .{pointer});
                    }
                },
                .ret_ref => {
                    const pointer = self.temp();
                    try self.print(" %v{d} =l {s} %captured\n", .{ pointer, if (self.function.signature.return_reference.?.slice) "copy" else "loadl" });
                    try self.returnValue(pointer);
                },
                .read_ref => |reference| {
                    const pointer = try self.load("r", @backingInt(reference));
                    const ty = self.function.scope.references[@backingInt(reference)].ty;
                    if (self.isScalar(ty)) try self.store(h, try self.readValue(pointer, ty)) else {
                        const snapshot = try self.aggregatePointer();
                        try self.print(copy_value, .{ pointer, snapshot, (try self.layout(ty)).size });
                        try self.store(h, snapshot);
                    }
                },
                .write_ref => |reference| {
                    const pointer = try self.load("r", @backingInt(reference));
                    const value = try self.load("s", h - 1);
                    const ty = self.function.scope.references[@backingInt(reference)].ty;
                    if (self.isScalar(ty)) try self.print(" storel %v{d}, %v{d}\n", .{ value, pointer }) else try self.writeValue(pointer, value, ty);
                },
                .read_field, .take_field => |access| {
                    const owner_ty = self.function.scope.locals[@backingInt(access.owner)].ty;
                    const member = try self.field(owner_ty, access.field);
                    const pointer = if (access.reference) |reference| try self.load("r", @backingInt(reference)) else local: {
                        const value = self.temp();
                        try self.print(" %v{d} =l copy %l{d}\n", .{ value, @backingInt(access.owner) });
                        break :local value;
                    };
                    const address = try self.address(pointer, member.offset);
                    if (self.isScalar(access.output)) try self.store(h, try self.readValue(address, access.output)) else {
                        const snapshot = try self.aggregatePointer();
                        try self.print(copy_value, .{ address, snapshot, (try self.layout(access.output)).size });
                        try self.store(h, snapshot);
                    }
                    if (op == .take_field and (try self.layout(access.output)).drop) try self.print(" call $memset(l %v{d}, w 0, l {d})\n", .{ address, (try self.layout(access.output)).size });
                },
                else => return error.InternalError,
            }
        }

        fn begin(self: *E, reference_id: typed.ReferenceId, slicing: bool, h: usize) Error!void {
            const reference = self.function.scope.references[@backingInt(reference_id)];
            if (reference.mode.slice) {
                const source = try sourceSlice(self, reference);
                var pointer = source.pointer;
                var length = source.length;
                if (slicing) {
                    const start = try self.load("s", h - 2);
                    const end = try self.load("s", h - 1);
                    const ordered = self.temp();
                    const within = self.temp();
                    const valid = self.temp();
                    try self.print(" %v{d} =l culel %v{d}, %v{d}\n %v{d} =l culel %v{d}, %v{d}\n", .{ ordered, start, end, within, end, length });
                    try self.print(" %v{d} =l and %v{d}, %v{d}\n", .{ valid, ordered, within });
                    try self.require(valid, slice_failure);
                    const offset = self.temp();
                    const next = self.temp();
                    const size = (try self.layout(reference.ty)).size;
                    try self.print(" %v{d} =l mul %v{d}, {d}\n %v{d} =l add %v{d}, %v{d}\n", .{ offset, start, size, next, pointer, offset });
                    pointer = next;
                    length = self.temp();
                    try self.print(" %v{d} =l sub %v{d}, %v{d}\n", .{ length, end, start });
                }
                try saveSlice(self, reference_id, pointer, length);
            } else if (reference.parent) |parent| {
                const pointer = try self.load("r", @backingInt(parent));
                try self.print(" storel %v{d}, %r{d}\n", .{ pointer, @backingInt(reference_id) });
            } else try self.print(" storel %l{d}, %r{d}\n", .{ @backingInt(reference.owner), @backingInt(reference_id) });
        }
        fn sliceLength(self: *E, reference: typed.ReferenceId) Error!usize {
            const address = self.temp();
            const result = self.temp();
            try self.print(" %v{d} =l add %r{d}, 8\n %v{d} =l loadl %v{d}\n", .{ address, @backingInt(reference), result, address });
            return result;
        }
        fn saveSlice(self: *E, reference: typed.ReferenceId, pointer: usize, length: usize) Error!void {
            const address = self.temp();
            try self.print(" storel %v{d}, %r{d}\n %v{d} =l add %r{d}, 8\n storel %v{d}, %v{d}\n", .{ pointer, @backingInt(reference), address, @backingInt(reference), length, address });
        }
        fn sourceSlice(self: *E, reference: typed.Reference) Error!struct { pointer: usize, length: usize } {
            if (reference.parent) |parent| if (self.function.scope.references[@backingInt(parent)].mode.slice) {
                return .{ .pointer = try self.load("r", @backingInt(parent)), .length = try sliceLength(self, parent) };
            };
            const owner_ty = self.function.scope.locals[@backingInt(reference.owner)].ty;
            const layout = try self.layout(owner_ty);
            if (layout.kind == .owned_buffer) {
                const owner = if (reference.parent) |parent| blk: {
                    const reference_pointer = try self.load("r", @backingInt(parent));
                    const value = self.temp();
                    try self.print(" %v{d} =l loadl %v{d}\n", .{ value, reference_pointer });
                    break :blk value;
                } else try self.load("l", @backingInt(reference.owner));
                const length = self.temp();
                const storage = try self.address(owner, 32);
                const pointer = self.temp();
                try self.print(" %v{d} =l loadl %v{d}\n %v{d} =l loadl %v{d}\n", .{ length, owner, pointer, storage });
                return .{ .pointer = pointer, .length = length };
            }
            if (layout.kind != .array) return self.reject(self.pc);
            const pointer = self.temp();
            const length = self.temp();
            if (reference.parent) |parent| {
                const source = try self.load("r", @backingInt(parent));
                try self.print(" %v{d} =l copy %v{d}\n", .{ pointer, source });
            } else try self.print(" %v{d} =l copy %l{d}\n", .{ pointer, @backingInt(reference.owner) });
            try self.print(" %v{d} =l copy {d}\n", .{ length, layout.count });
            return .{ .pointer = pointer, .length = length };
        }
    };
}
