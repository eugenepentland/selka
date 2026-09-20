//! Store native provider status/value pairs using the semantic checked-result layout.
const typed = @import("typed.zig");
const prelude = @import("prelude.zig");
/// Errors reported while emitting native operations.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
/// Bind result lowering to the concrete backend emitter.
pub fn Lower(comptime E: type) type {
    return struct {
        /// Typed result payload and destination slot.
        pub const Result = struct { ty: typed.Type, status: usize, value: usize, slot: usize };
        /// Typed optional payload, its runtime status word and destination slot.
        pub const Option = struct { ty: typed.Type, status: usize, value: usize, slot: usize };
        /// Store one `Option[T]` the runtime published: a zero status answers
        /// `Some` with the value word the caller already read, any other status
        /// `None` with no payload at all. Both the scalar grammar and the byte
        /// grammar publish through this shape, so they cannot drift.
        pub fn option(self: *E, args: Option) Error!void {
            const shape = prelude.optionShape(args.ty, self.program.records) orelse return error.InternalError;
            const pointer = try self.aggregatePointer();
            const slot = try self.address(pointer, (try self.layout(args.ty)).payload_offset);
            const label = self.temp();
            try self.print(" jnz %v{d}, @some{d}, @none{d}\n@some{d}\n storew {d}, %v{d}\n", .{ args.status, label, label, label, shape.some, pointer });
            try self.writeValue(slot, args.value, shape.element);
            try self.print(" jmp @parsed{d}\n@none{d}\n storew {d}, %v{d}\n jmp @parsed{d}\n@parsed{d}\n", .{ label, label, shape.none, pointer, label, label });
            try self.store(args.slot, pointer);
        }
        /// Store a checked result whose success and error payloads are both managed
        /// references, so the status selects the tag rather than the payload.
        pub fn payload(self: *E, args: Result) Error!void {
            const shape = typed.resultShape(args.ty, self.program.records) orelse return error.InternalError;
            const pointer = try self.aggregatePointer();
            const slot = try self.address(pointer, (try self.layout(args.ty)).payload_offset);
            const label = self.temp();
            try self.print(" jnz %v{d}, @payloaderr{d}, @payloadok{d}\n@payloaderr{d}\n storew {d}, %v{d}\n", .{ args.status, label, label, label, shape.error_tag, pointer });
            try self.writeValue(slot, args.value, shape.error_type);
            try self.print(" jmp @payloaddone{d}\n@payloadok{d}\n storew {d}, %v{d}\n", .{ label, label, shape.ok_tag, pointer });
            try self.writeValue(slot, args.value, shape.ok_type);
            try self.print(" jmp @payloaddone{d}\n@payloaddone{d}\n", .{ label, label });
            try self.store(args.slot, pointer);
        }
        /// Store native success/error payloads using the semantic result layout.
        pub fn result(self: *E, args: Result) Error!void {
            const shape = typed.resultShape(args.ty, self.program.records) orelse return error.InternalError;
            const pointer = try self.aggregatePointer();
            const slot = try self.address(pointer, (try self.layout(args.ty)).payload_offset);
            const label = self.temp();
            try self.print(" jnz %v{d}, @providererror{d}, @providerok{d}\n@providererror{d}\n storew {d}, %v{d}\n", .{ args.status, label, label, label, shape.error_tag, pointer });
            const status = self.temp();
            try self.print(" %v{d} =l extsw %v{d}\n", .{ status, args.status });
            try self.writeValue(slot, status, shape.error_type);
            try self.print(" jmp @providerresult{d}\n@providerok{d}\n storew {d}, %v{d}\n", .{ label, label, shape.ok_tag, pointer });
            try self.writeValue(slot, args.value, shape.ok_type);
            try self.print(" jmp @providerresult{d}\n@providerresult{d}\n", .{ label, label });
            try self.store(args.slot, pointer);
        }
    };
}
