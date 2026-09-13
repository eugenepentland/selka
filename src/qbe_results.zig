//! Store native provider status/value pairs using the semantic checked-result layout.
const typed = @import("typed.zig");
/// Errors reported while emitting native operations.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
/// Bind result lowering to the concrete backend emitter.
pub fn Lower(comptime E: type) type {
    return struct {
        /// Typed result payload and destination slot.
        pub const Result = struct { ty: typed.Type, status: usize, value: usize, slot: usize };
        /// Store native success/error payloads using the semantic result layout.
        pub fn result(self: *E, args: Result) Error!void {
            const shape = typed.resultShape(args.ty, self.program.records) orelse return error.InternalError;
            const pointer = try self.aggregatePointer();
            const payload = try self.address(pointer, (try self.layout(args.ty)).payload_offset);
            const label = self.temp();
            try self.print(" jnz %v{d}, @providererror{d}, @providerok{d}\n@providererror{d}\n storew {d}, %v{d}\n", .{ args.status, label, label, label, shape.error_tag, pointer });
            const status = self.temp();
            try self.print(" %v{d} =l extsw %v{d}\n", .{ status, args.status });
            try self.writeValue(payload, status, shape.error_type);
            try self.print(" jmp @providerresult{d}\n@providerok{d}\n storew {d}, %v{d}\n", .{ label, label, shape.ok_tag, pointer });
            try self.writeValue(payload, args.value, shape.ok_type);
            try self.print(" jmp @providerresult{d}\n@providerresult{d}\n", .{ label, label });
            try self.store(args.slot, pointer);
        }
    };
}
