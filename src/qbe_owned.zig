//! Owned native buffer operations with explicit transfer and result variants.
const load_word = @import("qbe_format.zig").load_word;
const std = @import("std");
const typed = @import("typed.zig");
const bytecode = @import("bytecode.zig");
/// Errors reported while emitting native operations.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
const capacity_limit = std.math.maxInt(usize) / @sizeOf(typed.Value);
/// Bind operation lowering to the concrete backend emitter.
pub fn Lower(comptime E: type) type {
    return struct {
        /// Acquire a buffer using the explicit native allocator capability.
        pub fn acquire(self: *E, ty: typed.Type, stack: []const typed.Type) Error!void {
            const shape = typed.resultShape(ty, self.program.records) orelse return error.InternalError;
            const element = self.program.records[shape.ok_type.recordIndex()].shape.buffer orelse return self.reject(self.pc);
            const capacity = try self.load("s", stack.len - 1);
            const authority = try self.load("s", stack.len - 2);
            const status = self.temp();
            try self.print(" %v{d} =w call $myl_qbe_owned_new(l %ctx, l extern ${s}, l %v{d}, l %v{d}, l {d}, l %agg{d})\n", .{ status, try self.descriptor(element), authority, capacity, capacity_limit, self.pc });
            try allocationStatus(self, status);
            const value = self.temp();
            try self.print(" %v{d} =l loadl %agg{d}\n", .{ value, self.pc });
            try result(self, .{ .ty = ty, .status = status, .value = value, .slot = stack.len - 2 });
        }
        fn allocationStatus(self: *E, status: usize) Error!void {
            const valid = self.temp();
            try self.print(" %v{d} =w csgew %v{d}, 0\n", .{ valid, status });
            try self.require(valid, "myl_qbe_fail_allocation");
        }
        /// Typed result payload and destination slot.
        pub const Result = struct { ty: typed.Type, status: usize, value: usize, slot: usize };
        /// Store native success/error payloads using the semantic result layout.
        pub fn result(self: *E, args: Result) Error!void {
            const shape = typed.resultShape(args.ty, self.program.records) orelse return error.InternalError;
            const pointer = try self.aggregatePointer();
            const payload = try self.address(pointer, (try self.layout(args.ty)).payload_offset);
            const label = self.temp();
            try self.print(" jnz %v{d}, @ownederror{d}, @ownedok{d}\n@ownederror{d}\n storew {d}, %v{d}\n", .{ args.status, label, label, label, shape.error_tag, pointer });
            const status = self.temp();
            try self.print(" %v{d} =l extsw %v{d}\n", .{ status, args.status });
            try self.writeValue(payload, status, shape.error_type);
            try self.print(" jmp @ownedresult{d}\n@ownedok{d}\n storew {d}, %v{d}\n", .{ label, label, shape.ok_tag, pointer });
            try self.writeValue(payload, args.value, shape.ok_type);
            try self.print(" jmp @ownedresult{d}\n@ownedresult{d}\n", .{ label, label });
            try self.store(args.slot, pointer);
        }
        /// Execute an owned buffer primitive and preserve its structured result status.
        pub fn operation(self: *E, op: @FieldType(@FieldType(bytecode.Instruction, "op"), "buffer_operation"), stack: []const typed.Type) Error!void {
            const owner_ty = self.function.scope.locals[@backingInt(op.owner)].ty;
            const element = self.program.records[owner_ty.recordIndex()].shape.buffer orelse return self.reject(self.pc);
            const owner = if (op.reference) |reference| blk: {
                const ptr = try self.load("r", @backingInt(reference));
                const value = self.temp();
                try self.print(load_word, .{ value, ptr });
                break :blk value;
            } else try self.load("l", @backingInt(op.owner));
            const base = stack.len - op.kind.arity();
            const status = self.temp();
            if (op.kind == .length or op.kind == .capacity) {
                const pointer = try self.address(owner, if (op.kind == .length) 0 else 8);
                try self.print(load_word, .{ status, pointer });
                return self.store(base, status);
            }
            if (op.kind == .read) {
                const index = try self.load("s", base);
                try self.print(" %v{d} =w call $myl_native_list_get(l %v{d}, l %v{d}, l %agg{d})\n", .{ status, owner, index, self.pc });
                try self.require(status, "myl_qbe_fail_buffer_bounds");
                return self.store(base, try self.readValue(try self.aggregatePointer(), element));
            }
            if (op.kind == .take) {
                const index = try self.load("s", base);
                try self.print(" %v{d} =w call $myl_native_owned_take(l %v{d}, l %v{d}, l %aux{d})\n", .{ status, owner, index, self.pc });
                const address = self.temp();
                try self.print(" %v{d} =l copy %aux{d}\n", .{ address, self.pc });
                const taken = try self.readValue(address, element);
                return result(self, .{ .ty = op.output, .status = status, .value = taken, .slot = base });
            }
            const value = self.temp();
            try self.print(" %v{d} =l copy 1\n", .{value});
            switch (op.kind) {
                .append, .write, .resize => {
                    const input = self.temp();
                    if (self.isScalar(element)) try self.print(" %v{d} =l copy %s{d}\n", .{ input, stack.len - 1 }) else try self.print(" %v{d} =l loadl %s{d}\n", .{ input, stack.len - 1 });
                    if (op.kind == .append) try self.print(" %v{d} =w call $myl_native_owned_append(l %heap, l %v{d}, l %v{d})\n", .{ status, owner, input }) else {
                        const index = try self.load("s", base);
                        try self.print(" %v{d} =w call ${s}(l %heap, l %v{d}, l %v{d}, l %v{d})\n", .{ status, if (op.kind == .write) "myl_native_owned_set" else "myl_native_owned_resize", owner, index, input });
                    }
                },
                .truncate => {
                    const length = try self.load("s", base);
                    try self.print(" %v{d} =w call $myl_native_owned_truncate(l %heap, l %v{d}, l %v{d})\n", .{ status, owner, length });
                },
                .reserve => {
                    const count = try self.load("s", base + 1);
                    const authority = try self.load("s", base);
                    try self.print(" %v{d} =w call $myl_qbe_owned_reserve(l %ctx, l %v{d}, l %v{d}, l %v{d}, l {d})\n", .{ status, owner, authority, count, capacity_limit });
                },
                else => return self.reject(self.pc),
            }
            try allocationStatus(self, status);
            try result(self, .{ .ty = op.output, .status = status, .value = value, .slot = base });
        }

        /// Acquire a native pool with generation-checked handles.
        pub fn acquirePool(self: *E, ty: typed.Type, stack: []const typed.Type) Error!void {
            const shape = typed.resultShape(ty, self.program.records).?;
            const element = self.program.records[shape.ok_type.recordIndex()].shape.pool.?.element;
            const authority = try self.load("s", stack.len - 2);
            const capacity = try self.load("s", stack.len - 1);
            const status = self.temp();
            try self.print(" %v{d} =w call $myl_qbe_pool_new(l %ctx, l extern ${s}, l %v{d}, l %v{d}, l %aux{d})\n", .{ status, try self.descriptor(element), authority, capacity, self.pc });
            try allocationStatus(self, status);
            const value = self.temp();
            try self.print(" %v{d} =l loadl %aux{d}\n", .{ value, self.pc });
            try result(self, .{ .ty = ty, .status = status, .value = value, .slot = stack.len - 2 });
        }
        /// Emit pool snapshots, mutations, and stale/foreign/full result codes.
        pub fn pool(self: *E, op: @FieldType(@FieldType(bytecode.Instruction, "op"), "pool_operation"), stack: []const typed.Type) Error!void {
            const owner_ty = self.function.scope.locals[@backingInt(op.owner)].ty;
            const schema = self.program.records[owner_ty.recordIndex()].shape.pool.?;
            const owner = if (op.reference) |reference| blk: {
                const ptr = try self.load("r", @backingInt(reference));
                const value = self.temp();
                try self.print(load_word, .{ value, ptr });
                break :blk value;
            } else try self.load("l", @backingInt(op.owner));
            const base = stack.len - op.kind.arity();
            const status = self.temp();
            if (op.kind == .length or op.kind == .capacity) {
                const pointer = try self.address(owner, if (op.kind == .length) 0 else 8);
                try self.print(load_word, .{ status, pointer });
                return self.store(base, status);
            }
            if (op.kind == .clear) {
                try self.print(" call $myl_native_pool_clear(l %heap, l %v{d})\n storel 1, %s{d}\n", .{ owner, base });
                return;
            }
            const value = self.temp();
            var output_type: typed.Type = .bool;
            switch (op.kind) {
                .insert => {
                    const input = try inputAddress(self, stack.len - 1, schema.element);
                    try self.print(" %v{d} =w call $myl_native_pool_insert(l %heap, l %v{d}, l %v{d}, l %aux{d})\n", .{ status, owner, input, self.pc });
                    output_type = schema.handle;
                },
                .read => {
                    const handle = try self.load("s", base);
                    try self.print(" %v{d} =w call $myl_native_pool_read(l %v{d}, l %v{d}, l %aux{d})\n", .{ status, owner, handle, self.pc });
                    output_type = schema.element;
                },
                .replace => {
                    const handle = try self.load("s", base);
                    const input = try inputAddress(self, stack.len - 1, schema.element);
                    try self.print(" %v{d} =w call $myl_native_pool_replace(l %heap, l %v{d}, l %v{d}, l %v{d})\n", .{ status, owner, handle, input });
                },
                .remove => {
                    const handle = try self.load("s", base);
                    try self.print(" %v{d} =w call $myl_native_pool_remove(l %heap, l %v{d}, l %v{d})\n", .{ status, owner, handle });
                },
                else => return self.reject(self.pc),
            }
            try allocationStatus(self, status);
            if (output_type == .bool) try self.print(" %v{d} =l copy 1\n", .{value}) else {
                const address = self.temp();
                try self.print(" %v{d} =l copy %aux{d}\n", .{ address, self.pc });
                const output = try self.readValue(address, output_type);
                try self.print(" %v{d} =l copy %v{d}\n", .{ value, output });
            }
            try result(self, .{ .ty = op.output, .status = status, .value = value, .slot = base });
        }
        fn inputAddress(self: *E, slot: usize, ty: typed.Type) Error!usize {
            const pointer = self.temp();
            try self.print(" %v{d} =l {s} %s{d}\n", .{ pointer, if (self.isScalar(ty)) "copy" else "loadl", slot });
            return pointer;
        }
    };
}
