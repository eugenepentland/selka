//! Native resource providers: owned handles, copied I/O, and retained failures.
const typed = @import("typed.zig");
const bytecode = @import("bytecode.zig");
/// Errors reported while emitting native operations.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
/// Bind operation lowering to the concrete backend emitter.
pub fn Lower(comptime E: type) type {
    return struct {
        const result = @import("qbe_results.zig").Lower(E).result;
        /// Lower resource authority and ownership transitions against provider helpers.
        pub fn emit(self: *E, op: @FieldType(bytecode.Instruction, "op"), stack: []const typed.Type) Error!void {
            const h = stack.len;
            switch (op) {
                .restrict_resource => |restrict| {
                    const input = try self.load("s", h - 1);
                    const value = self.temp();
                    try self.print(" %v{d} =l call $myl_qbe_restrict_resource(l %ctx, l %v{d}, w {d})\n", .{ value, input, restrict.permissions });
                    try self.store(h - 1, value);
                },
                .acquire_resource => |acquire| {
                    const shape = typed.resultShape(acquire.output, self.program.records).?;
                    const authority = try self.load("s", h - 2);
                    const request = try self.load("s", h - 1);
                    const bytes = try byteView(self, request, acquire.request);
                    const status = self.temp();
                    const kind = typed.resourceKind(shape.ok_type, self.program.records).?;
                    try self.print(" %v{d} =w call $myl_qbe_resource_new(l %ctx, l %v{d}, w {d}, l %v{d}, l %v{d}, l %aux{d})\n", .{ status, authority, @backingInt(kind), bytes.pointer, bytes.length, self.pc });
                    if ((try self.layout(acquire.request)).drop) try self.print(" call $myl_native_owned_drop(l %heap, l extern ${s}, l %s{d})\n", .{ try self.descriptor(acquire.request), h - 1 });
                    try self.checkFailure("failure");
                    const value = self.temp();
                    try self.print(" %v{d} =l loadl %aux{d}\n", .{ value, self.pc });
                    try result(self, .{ .ty = acquire.output, .status = status, .value = value, .slot = h - 2 });
                },
                .complete_resource => |ty| {
                    const shape = typed.completionShape(ty, self.program.records).?;
                    const resource = try self.load("s", h - 1);
                    const status = self.temp();
                    try self.print(" %v{d} =w call $myl_qbe_resource_complete(l %ctx, l %v{d})\n", .{ status, resource });
                    try self.checkFailure("failure");
                    const output = try self.aggregatePointer();
                    const payload = try self.address(output, (try self.layout(ty)).payload_offset);
                    const label = self.temp();
                    try self.print(" jnz %v{d}, @completeerr{d}, @completeok{d}\n@completeerr{d}\n storew {d}, %v{d}\n", .{ status, label, label, label, shape.result.error_tag, output });
                    const owner_field = try self.field(shape.result.error_type, shape.resource_field);
                    const code_field = try self.field(shape.result.error_type, shape.code_field);
                    try self.writeValue(try self.address(payload, owner_field.offset), resource, shape.resource_type);
                    const code = self.temp();
                    try self.print(" %v{d} =l extsw %v{d}\n", .{ code, status });
                    try self.writeValue(try self.address(payload, code_field.offset), code, .i64);
                    try self.print(" jmp @completed{d}\n@completeok{d}\n storew {d}, %v{d}\n storeb 1, %v{d}\n jmp @completed{d}\n@completed{d}\n", .{ label, label, shape.result.ok_tag, output, payload, label, label });
                    try self.store(h - 1, output);
                },
                .resource_io => |io| try ioOperation(self, io, stack),
                else => return error.InternalError,
            }
        }
        const Bytes = struct { pointer: usize, length: usize };
        fn byteView(self: *E, base: usize, ty: typed.Type) Error!Bytes {
            const length = self.temp();
            if ((try self.layout(ty)).kind == .owned_buffer) {
                const storage = try self.address(base, 32);
                const pointer = self.temp();
                try self.print(" %v{d} =l loadl %v{d}\n %v{d} =l loadl %v{d}\n", .{ length, base, pointer, storage });
                return .{ .pointer = pointer, .length = length };
            }
            try self.print(" %v{d} =l copy {d}\n", .{ length, (try self.layout(ty)).size });
            return .{ .pointer = base, .length = length };
        }
        fn ioOperation(self: *E, io: @FieldType(@FieldType(bytecode.Instruction, "op"), "resource_io"), stack: []const typed.Type) Error!void {
            const resource = try self.load("l", @backingInt(io.owner));
            const status = self.temp();
            const shape = typed.resultShape(io.output, self.program.records).?;
            const output = self.temp();
            try self.print(" %v{d} =l copy %aux{d}\n call $memset(l %v{d}, w 0, l {d})\n", .{ output, self.pc, output, @max(8, (try self.layout(shape.ok_type)).size) });
            var slot = stack.len;
            var bytes: Bytes = undefined;
            if (io.kind == .write) {
                slot -= 1;
                bytes = try byteView(self, try self.load("s", slot), io.input.?);
            } else {
                const read = typed.resourceReadShape(io.output, self.program.records).?;
                const field = try self.field(shape.ok_type, read.bytes_field);
                const length = self.temp();
                try self.print(" %v{d} =l copy {d}\n", .{ length, (try self.layout(read.bytes_type)).size });
                bytes = .{ .pointer = try self.address(output, field.offset), .length = length };
            }
            var value = output;
            if (io.kind == .write) {
                try self.print(" %v{d} =w call $myl_qbe_resource_write(l %ctx, l %v{d}, l %v{d}, l %v{d}, l %scratch)\n", .{ status, resource, bytes.pointer, bytes.length });
                value = self.temp();
                try self.print(" %v{d} =l loadl %scratch\n", .{value});
            } else {
                const length_field = typed.resourceReadShape(io.output, self.program.records).?.length_field;
                const flag_field = typed.resourceReadShape(io.output, self.program.records).?.flag_field;
                const length = try self.field(shape.ok_type, length_field);
                const flag = try self.field(shape.ok_type, flag_field);
                const length_ptr = try self.address(output, length.offset);
                try self.print(" %v{d} =w call $myl_qbe_resource_read(l %ctx, l %v{d}, l %v{d}, l %v{d}, l %v{d}, l %scratch)\n", .{ status, resource, bytes.pointer, bytes.length, length_ptr });
                const eof = self.temp();
                try self.print(" %v{d} =l loaduw %scratch\n", .{eof});
                try self.writeValue(try self.address(output, flag.offset), eof, .bool);
            }
            if (io.kind == .write) {
                const input_type = io.input.?;
                if ((try self.layout(input_type)).drop) {
                    try self.print(" call $myl_native_owned_drop(l %heap, l extern ${s}, l %s{d})\n", .{ try self.descriptor(input_type), slot });
                }
            }
            try self.checkFailure("failure");
            try result(self, .{ .ty = io.output, .status = status, .value = value, .slot = slot });
        }
    };
}
