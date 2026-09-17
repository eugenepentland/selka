//! QBE lowering of the `print` builtin. Operands render through the generated
//! per-type renderers into one buffered line, so the native backend emits the
//! same bytes as `src/io_render.zig` and publishes them in one write.
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
/// Failures reported while emitting native output instructions.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
const render = @import("native_render.zig");
const Print = @FieldType(@FieldType(bytecode.Instruction, "op"), "print");
const raw_call = " call $myl_qbe_print_raw(l %v{d}, l %v{d})\n";

/// Bind output lowering to the concrete emitter without an import cycle.
pub fn Lower(comptime E: type) type {
    return struct {
        /// Lower one `print` call, including its `sep=` and `end=` operands.
        pub fn emit(self: *E, output: Print, stack: []const typed.Type) Error!void {
            const terminator = stack.len - @intFromBool(output.terminator);
            const separator = terminator - @intFromBool(output.separator);
            const base = separator - output.types.len;
            const sink = self.temp();
            const begin = if (output.sink == .stderr) "myl_qbe_eprint_begin" else "myl_qbe_print_begin";
            const finish = if (output.sink == .stderr) "myl_qbe_eprint_finish" else "myl_qbe_print_finish";
            try self.print(" %v{d} =l call ${s}(l %ctx)\n", .{ sink, begin });
            try self.checkFailure("failure");
            for (output.types, 0..) |ty, index| {
                if (index != 0) try gap(E, self, sink, output.separator, separator);
                const value = self.temp();
                // A managed record (`class`) is one word holding the body pointer;
                // its renderer reads fields at that pointer, so it needs the loaded
                // pointer, not the operand-slot address used by scalar/collection
                // renderers.
                const managed_record = ty.isAggregate() and self.program.records[ty.recordIndex()].isManagedRecord();
                if (self.isScalar(ty) and !managed_record) try self.print(" %v{d} =l copy %s{d}\n", .{ value, base + index }) else try self.print(" %v{d} =l loadl %s{d}\n", .{ value, base + index });
                const symbol = render.symbol(self.allocator, self.layouts, ty) catch return error.InternalError;
                try self.print(" call ${s}(l %v{d}, l %v{d}, w 0)\n", .{ symbol, sink, value });
            }
            if (output.terminator) {
                try self.print(raw_call, .{ sink, try self.load("s", terminator) });
            } else try self.print(" call $myl_qbe_print_byte(l %v{d}, w 10)\n", .{sink});
            try self.print(" call ${s}(l %ctx, l %v{d})\n", .{ finish, sink });
            try self.checkFailure("failure");
            try self.print(" storel 0, %s{d}\n", .{base});
        }
    };
}

/// Separate two operands with the explicit `sep=` text or one space.
fn gap(comptime E: type, self: *E, sink: usize, explicit: bool, slot: usize) Error!void {
    if (!explicit) return self.print(" call $myl_qbe_print_byte(l %v{d}, w 32)\n", .{sink});
    try self.print(raw_call, .{ sink, try self.load("s", slot) });
}
