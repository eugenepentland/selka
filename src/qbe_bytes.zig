//! QBE lowering of immutable managed byte strings over the native byte runtime.
//! Byte strings reuse the managed list representation with a one-byte stride, so
//! length, indexing, iteration and equality stay on the shared list path and only
//! the byte-specific methods are emitted here.
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
/// Failures reported while emitting native byte-string instructions.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
const BufferOperation = @FieldType(@FieldType(bytecode.Instruction, "op"), "buffer_operation");
const allocation_failure = "myl_qbe_fail_allocation";
const load_word = @import("qbe_format.zig").load_word;

/// Bind byte-string lowering to the concrete emitter without an import cycle.
pub fn Lower(comptime E: type) type {
    return struct {
        /// Lower one byte-string method onto the native byte runtime.
        pub fn operation(self: *E, op: BufferOperation, stack: []const typed.Type) Error!void {
            return emitOperation(E, self, op, stack);
        }
        /// Lower `s.encode()` and `bytes.fromhex(s)` on a managed text receiver.
        pub fn textual(self: *E, op: BufferOperation, stack: []const typed.Type) Error!void {
            return emitTextual(E, self, op, stack);
        }
        /// Lower byte-string concatenation into a fresh immutable value.
        pub fn concat(self: *E, base: usize) Error!void {
            const left = try self.load("s", base);
            const right = try self.load("s", base + 1);
            const result = self.temp();
            try self.print(" %v{d} =l call $myl_native_bytes_concat(l %heap, l %v{d}, l %v{d})\n", .{ result, left, right });
            try self.require(result, allocation_failure);
            try self.store(base, result);
        }
        /// Lower `bytes(values)` from a managed integer list, trapping `R_BYTE_RANGE`.
        pub fn fromList(self: *E, stack: []const typed.Type) Error!void {
            const base = stack.len - 1;
            const input = try self.load("s", base);
            const result = self.temp();
            try self.print(" %v{d} =l call $myl_qbe_bytes_from_list(l %ctx, l %v{d})\n", .{ result, input });
            try self.checkFailure("failure");
            try self.store(base, result);
        }
    };
}

/// Store a checked byte conversion whose success and error payloads are both
/// managed references, so the status selects the tag rather than the payload.
fn emitPayloadResult(comptime E: type, self: *E, ty: typed.Type, status: usize, base: usize) Error!void {
    const shape = typed.resultShape(ty, self.program.records) orelse return error.InternalError;
    const value = self.temp();
    try self.print(" %v{d} =l loadl %scratch\n", .{value});
    const pointer = try self.aggregatePointer();
    const payload = try self.address(pointer, (try self.layout(ty)).payload_offset);
    const label = self.temp();
    try self.print(" jnz %v{d}, @byteserr{d}, @bytesok{d}\n@byteserr{d}\n storew {d}, %v{d}\n", .{ status, label, label, label, shape.error_tag, pointer });
    try self.writeValue(payload, value, shape.error_type);
    try self.print(" jmp @bytesdone{d}\n@bytesok{d}\n storew {d}, %v{d}\n", .{ label, label, shape.ok_tag, pointer });
    try self.writeValue(payload, value, shape.ok_type);
    try self.print(" jmp @bytesdone{d}\n@bytesdone{d}\n", .{ label, label });
    try self.store(base, pointer);
}

fn emitBoolean(comptime E: type, self: *E, result: usize, slot: usize) Error!void {
    const extended = self.temp();
    try self.print(" %v{d} =l extuw %v{d}\n", .{ extended, result });
    try self.store(slot, extended);
}

fn emitTextual(comptime E: type, self: *E, op: BufferOperation, stack: []const typed.Type) Error!void {
    const base = stack.len - op.kind.arity();
    const input = try self.load("l", @backingInt(op.owner));
    const result = self.temp();
    if (op.kind == .encode) {
        try self.print(" %v{d} =l call $myl_native_bytes_encode(l %heap, l %v{d})\n", .{ result, input });
        try self.require(result, allocation_failure);
        try self.store(base, result);
        return;
    }
    try self.print(" %v{d} =w call $myl_qbe_bytes_from_hex(l %ctx, l %v{d}, l %scratch)\n", .{ result, input });
    try self.checkFailure("failure");
    return emitPayloadResult(E, self, op.output, result, base);
}

fn emitSearch(comptime E: type, self: *E, op: BufferOperation, stack: []const typed.Type, input: usize) Error!void {
    const base = stack.len - 1;
    const needle = try self.load("s", base);
    const result = self.temp();
    if (op.kind == .contains and !stack[base].isAggregate()) {
        try self.print(" %v{d} =w call $myl_native_bytes_has_byte(l %v{d}, l %v{d})\n", .{ result, input, needle });
        return emitBoolean(E, self, result, base);
    }
    if (op.kind == .find) {
        try self.print(" %v{d} =l call $myl_native_bytes_find(l %v{d}, l %v{d})\n", .{ result, input, needle });
        return self.store(base, result);
    }
    const name: []const u8 = switch (op.kind) {
        .starts_with => "myl_native_bytes_starts_with",
        .ends_with => "myl_native_bytes_ends_with",
        else => "myl_native_bytes_find",
    };
    try self.print(" %v{d} =w call ${s}(l %v{d}, l %v{d})\n", .{ result, name, input, needle });
    if (op.kind != .contains) return emitBoolean(E, self, result, base);
    const found = self.temp();
    try self.print(" %v{d} =l extsw %v{d}\n %v{d} =w csgel %v{d}, 0\n", .{ found, result, result, found });
    return emitBoolean(E, self, result, base);
}

/// Lower one byte-string method using the native immutable byte runtime.
fn emitOperation(comptime E: type, self: *E, op: BufferOperation, stack: []const typed.Type) Error!void {
    const base = stack.len - op.kind.arity();
    const input = try self.load("l", @backingInt(op.owner));
    const result = self.temp();
    switch (op.kind) {
        .contains, .starts_with, .ends_with, .find => return emitSearch(E, self, op, stack, input),
        .slice => {
            const start = try self.load("s", base);
            const end = try self.load("s", base + 1);
            try self.print(" %v{d} =l call $myl_native_bytes_slice(l %heap, l %v{d}, l %v{d}, l %v{d})\n", .{ result, input, start, end });
            try self.require(result, allocation_failure);
            try self.store(base, result);
        },
        .split, .join => {
            const argument = try self.load("s", base);
            if (op.kind == .split) {
                const separator_length = self.temp();
                try self.print(load_word, .{ separator_length, argument });
                try self.require(separator_length, "myl_qbe_fail_empty_separator");
            }
            const name = if (op.kind == .split) "myl_native_bytes_split" else "myl_native_bytes_join";
            try self.print(" %v{d} =l call ${s}(l %heap, l %v{d}, l %v{d})\n", .{ result, name, input, argument });
            try self.require(result, allocation_failure);
            try self.store(base, result);
        },
        .to_list, .hex => {
            const name = if (op.kind == .to_list) "myl_native_bytes_to_list" else "myl_native_bytes_hex";
            try self.print(" %v{d} =l call ${s}(l %heap, l %v{d})\n", .{ result, name, input });
            try self.require(result, allocation_failure);
            try self.store(base, result);
        },
        .decode => {
            try self.print(" %v{d} =w call $myl_qbe_bytes_decode(l %ctx, l %v{d}, l %scratch)\n", .{ result, input });
            try self.checkFailure("failure");
            return emitPayloadResult(E, self, op.output, result, base);
        },
        else => return self.reject(self.pc),
    }
}
