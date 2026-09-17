//! QBE lowering of the `print` builtin and of the text conversion an f-string
//! hole over an aggregate lowers to. Operands render through the generated
//! per-type renderers into one buffered line, so the native backend emits the
//! same bytes as `src/io_render.zig`, then either publishes them in one write
//! or keeps them as fresh managed text.
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
            const stderr = output.sink == .stderr;
            const sink = try begin(E, self, if (stderr) "myl_qbe_eprint_begin" else "myl_qbe_print_begin");
            for (output.types, 0..) |ty, index| {
                if (index != 0) try gap(E, self, sink, output.separator, separator);
                try operand(E, self, sink, ty, base + index);
            }
            if (output.terminator) {
                try self.print(raw_call, .{ sink, try self.load("s", terminator) });
            } else try self.print(" call $myl_qbe_print_byte(l %v{d}, w 10)\n", .{sink});
            try self.print(" call ${s}(l %ctx, l %v{d})\n", .{ if (stderr) "myl_qbe_eprint_finish" else "myl_qbe_print_finish", sink });
            try self.checkFailure("failure");
            try self.print(" storel 0, %s{d}\n", .{base});
        }
        /// Lower an aggregate's conversion to text: render the operand in `slot`
        /// the way `print` writes it, then replace it with fresh text holding
        /// those bytes, so a hole spells a value exactly as `print` does.
        pub fn text(self: *E, ty: typed.Type, slot: usize) Error!void {
            const sink = try begin(E, self, "myl_qbe_print_begin");
            try operand(E, self, sink, ty, slot);
            const result = self.temp();
            try self.print(" %v{d} =l call $myl_qbe_text_render(l %ctx, l %v{d})\n", .{ result, sink });
            try self.checkFailure("failure");
            try self.store(slot, result);
        }
    };
}

/// Open one render buffer, trapping once the allocation budget is exhausted.
fn begin(comptime E: type, self: *E, entry: []const u8) Error!usize {
    const sink = self.temp();
    try self.print(" %v{d} =l call ${s}(l %ctx)\n", .{ sink, entry });
    try self.checkFailure("failure");
    return sink;
}

/// Render the value in `slot` through the generated renderer for its type. A
/// managed record (`class`) is one word holding the body pointer; its renderer
/// reads fields at that pointer, so it needs the loaded pointer, not the
/// operand-slot address that scalar and collection renderers take.
fn operand(comptime E: type, self: *E, sink: usize, ty: typed.Type, slot: usize) Error!void {
    const value = self.temp();
    const managed_record = ty.isAggregate() and self.program.records[ty.recordIndex()].isManagedRecord();
    if (self.isScalar(ty) and !managed_record) try self.print(" %v{d} =l copy %s{d}\n", .{ value, slot }) else try self.print(" %v{d} =l loadl %s{d}\n", .{ value, slot });
    const symbol = render.symbol(self.allocator, self.layouts, ty) catch return error.InternalError;
    try self.print(" call ${s}(l %v{d}, l %v{d}, w 0)\n", .{ symbol, sink, value });
}

/// Separate two operands with the explicit `sep=` text or one space.
fn gap(comptime E: type, self: *E, sink: usize, explicit: bool, slot: usize) Error!void {
    if (!explicit) return self.print(" call $myl_qbe_print_byte(l %v{d}, w 32)\n", .{sink});
    try self.print(raw_call, .{ sink, try self.load("s", slot) });
}
