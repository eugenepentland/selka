//! QBE lowering of immutable managed byte strings over the native byte runtime.
//! Byte strings reuse the managed list representation with a one-byte stride, so
//! length, indexing, iteration and equality stay on the shared list path and only
//! the byte-specific methods are emitted here.
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
/// Failures reported while emitting native byte-string instructions.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
const BufferOperation = @FieldType(@FieldType(bytecode.Instruction, "op"), "buffer_operation");
const format = @import("qbe_format.zig");
const std = @import("std");
const allocation_failure = format.allocation_failure;
const load_word = format.load_word;
const list_storage_offset = format.list_storage_offset;
const load_scratch = "  %v{d} =l loadl %scratch\n";
/// The builtin mutable octet buffer's spelling, which is the only receiver the
/// checker admits the in-place append methods on.
const byte_buffer_name = @import("nominal_templates.zig").byte_buffer_name;
/// Byte offsets of the capacity and backing words of that buffer's header
/// (`native_collections.h`): two size words, the generation, the element
/// descriptor, then the storage pointer.
const buffer_capacity_offset = 8;
const buffer_storage_offset = list_storage_offset;
/// One buffered method's boolean answer, written into the operand slot it came
/// from on the paths that never call the runtime.
const store_true = " storel 1, %s{d}\n";
const store_false = " storel 0, %s{d}\n";

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
        /// Lower `bytes(buffer)` into an immutable snapshot of a byte-kind
        /// buffer's current octets. The snapshot reads the buffer's own block and
        /// retains it, and the buffer is left with no spare capacity, so its next
        /// write detaches the octets into a private block first: a published
        /// snapshot can never be written through, and the conversion copies no
        /// octet to publish one.
        pub fn copyImmutable(self: *E, stack: []const typed.Type) Error!void {
            const base = stack.len - 1;
            const input = try self.load("s", base);
            const result = self.temp();
            try self.print(" %v{d} =l call $myl_qbe_bytes_snapshot(l %ctx, l %v{d})\n", .{ result, input });
            try self.checkFailure("failure");
            try self.store(base, result);
        }
    };
}

/// Store a checked byte conversion, whose payload the runtime left in scratch.
fn emitPayloadResult(comptime E: type, self: *E, ty: typed.Type, status: usize, base: usize) Error!void {
    const value = self.temp();
    try self.print(load_scratch, .{value});
    return @import("qbe_results.zig").Lower(E).payload(self, .{ .ty = ty, .status = status, .value = value, .slot = base });
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
    if (op.kind == .starts_with or op.kind == .ends_with) {
        const name = if (op.kind == .starts_with) "myl_native_bytes_starts_with" else "myl_native_bytes_ends_with";
        try self.print(" %v{d} =w call ${s}(l %v{d}, l %v{d})\n", .{ result, name, input, needle });
        return emitBoolean(E, self, result, base);
    }
    try self.print(" %v{d} =l call $myl_native_bytes_find(l %v{d}, l %v{d})\n", .{ result, input, needle });
    if (op.kind == .find) return self.store(base, result);
    const found = self.temp();
    try self.print(" %v{d} =l csgel %v{d}, 0\n", .{ found, result });
    try self.store(base, found);
}

/// Lower one byte-string method using the native immutable byte runtime.
fn emitOperation(comptime E: type, self: *E, op: BufferOperation, stack: []const typed.Type) Error!void {
    const base = stack.len - op.kind.arity();
    const input = try self.load("l", @backingInt(op.owner));
    const result = self.temp();
    switch (op.kind) {
        .contains, .starts_with, .ends_with, .find => return emitSearch(E, self, op, stack, input),
        // `find_any` is one runtime call: the native entry point builds the byte
        // set's membership table and scans the rest of the receiver itself.
        .find_any => {
            const values = try self.load("s", base);
            const start = try self.load("s", base + 1);
            try self.print(" %v{d} =l call $myl_native_bytes_find_any(l %v{d}, l %v{d}, l %v{d})\n", .{ result, input, values, start });
            return self.store(base, result);
        },
        .slice => {
            const start = try self.load("s", base);
            const end = try self.load("s", base + 1);
            // `src[a:b].decode()` needs neither the intermediate byte string nor
            // the copy into it: record the range for the decode two instructions
            // later and leave a null byte string in the slot it would have
            // filled, so the store that follows and any root push over it see a
            // value the collector can trace.
            if (self.fusibleSlice(self.pc)) |_| {
                try self.print(" storel 0, %s{d}\n", .{base});
                self.fuseDecode(self.pc + 2, input, start, end);
                return;
            }
            try self.print(" %v{d} =l call $myl_native_bytes_slice(l %heap, l %v{d}, l %v{d}, l %v{d})\n", .{ result, input, start, end });
            try self.require(result, allocation_failure);
            try self.store(base, result);
        },
        .split_whitespace => {
            try self.print(" %v{d} =l call $myl_native_bytes_split_whitespace(l %heap, l %v{d})\n", .{ result, input });
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
        // Both numeric parses read the receiver's octets in place through the one
        // pinned grammar, so a numeric leaf needs no decoded `str` and no
        // allocation at all; the runtime publishes the value bits in scratch.
        .parse_int, .parse_float, .parse_int_range, .parse_float_range => {
            const ranged = op.kind == .parse_int_range or op.kind == .parse_float_range;
            const floating = op.kind == .parse_float or op.kind == .parse_float_range;
            const status = self.temp();
            if (ranged) {
                const start = try self.load("s", base);
                const end = try self.load("s", base + 1);
                const storage = self.temp();
                const length = self.temp();
                try self.print(" %v{d} =l call $myl_native_bytes_range(l %v{d}, l %v{d}, l %v{d}, l %scratch)\n", .{ storage, input, start, end });
                try self.print(load_scratch, .{length});
                try self.print(" %v{d} =w call $myl_native_bytes_number_parse(l %v{d}, l %v{d}, w {d}, l %scratch)\n", .{ status, storage, length, @intFromBool(floating) });
            } else {
                const storage = self.temp();
                const length = self.temp();
                const header = self.temp();
                try self.print(" %v{d} =l add %v{d}, {d}\n %v{d} =l loadl %v{d}\n", .{ header, input, list_storage_offset, storage, header });
                try self.print(load_word, .{ length, input });
                try self.print(" %v{d} =w call $myl_native_bytes_number_parse(l %v{d}, l %v{d}, w {d}, l %scratch)\n", .{ status, storage, length, @intFromBool(floating) });
            }
            const value = self.temp();
            try self.print(load_scratch, .{value});
            return @import("qbe_results.zig").Lower(E).option(self, .{ .ty = op.output, .status = status, .value = value, .slot = base });
        },
        // A view keeps the source's octets and retains its backing block, so the
        // one allocation here is the view's own header, not a copy of the range.
        .view => {
            const start = try self.load("s", base);
            const end = try self.load("s", base + 1);
            try self.print(" %v{d} =l call $myl_native_bytes_view(l %heap, l %v{d}, l %v{d}, l %v{d})\n", .{ result, input, start, end });
            try self.require(result, allocation_failure);
            try self.store(base, result);
        },
        // The explicit owned copy: the octets a view shares become a byte string
        // that shares no storage with the receiver.
        .copy => {
            try self.print(" %v{d} =l call $myl_native_bytes_copy(l %heap, l %v{d})\n", .{ result, input });
            try self.require(result, allocation_failure);
            try self.store(base, result);
        },
        .scalar_count, .scalar_count_range => {
            if (op.kind == .scalar_count_range) {
                const start = try self.load("s", base);
                const end = try self.load("s", base + 1);
                try self.print(" %v{d} =w call $myl_qbe_bytes_scalar_count_range(l %ctx, l %v{d}, l %v{d}, l %v{d}, l %scratch)\n", .{ result, input, start, end });
            } else try self.print(" %v{d} =w call $myl_qbe_bytes_scalar_count(l %ctx, l %v{d}, l %scratch)\n", .{ result, input });
            try self.checkFailure("failure");
            return emitPayloadResult(E, self, op.output, result, base);
        },
        .decode => {
            if (self.fusedDecode(self.pc)) |fused| {
                try self.print(" %v{d} =w call $myl_qbe_bytes_decode_range(l %ctx, l %v{d}, l %v{d}, l %v{d}, l %scratch)\n", .{ result, fused.input, fused.start, fused.end });
            } else try self.print(" %v{d} =w call $myl_qbe_bytes_decode(l %ctx, l %v{d}, l %scratch)\n", .{ result, input });
            try self.checkFailure("failure");
            return emitPayloadResult(E, self, op.output, result, base);
        },
        .buffer_reserve, .buffer_append_byte, .buffer_append_range, .buffer_append_utf8, .buffer_append_int => return emitBuffer(E, self, op, stack, input),
        .buffer_append_float => return emitBuffer(E, self, op, stack, input),
        else => return self.reject(self.pc),
    }
}

/// Lower one in-place octet-buffer method. The runtime appends straight into the
/// receiver's spare capacity and answers one status: `MYL_BYTES_FAILED` (zero)
/// reports that the allocation budget refused the growth, so the caller traps
/// the way every other refused allocation does, while `MYL_BYTES_REFUSED` (two)
/// is an argument or frozen-receiver refusal that becomes `False` without having
/// written anything.
fn emitBuffer(comptime E: type, self: *E, op: BufferOperation, stack: []const typed.Type, input: usize) Error!void {
    if (try inlineBufferAppend(E, self, op, stack, input)) return;
    const base = stack.len - op.kind.arity();
    const status = self.temp();
    switch (op.kind) {
        .buffer_reserve, .buffer_append_byte, .buffer_append_int => {
            const argument = try self.load("s", base);
            const name = switch (op.kind) {
                .buffer_reserve => "myl_native_bytes_buffer_reserve",
                .buffer_append_byte => "myl_native_bytes_buffer_append_byte",
                else => "myl_native_bytes_buffer_append_int",
            };
            try self.print(" %v{d} =w call ${s}(l %heap, l %v{d}, l %v{d})\n", .{ status, name, input, argument });
        },
        .buffer_append_range => {
            const data = try self.load("s", base);
            const start = try self.load("s", base + 1);
            const end = try self.load("s", base + 2);
            try self.print(" %v{d} =w call $myl_native_bytes_buffer_append_range(l %heap, l %v{d}, l %v{d}, l %v{d}, l %v{d})\n", .{ status, input, data, start, end });
        },
        .buffer_append_utf8 => {
            const text = try self.load("s", base);
            try self.print(" %v{d} =w call $myl_native_bytes_buffer_append_utf8(l %heap, l %v{d}, l %v{d})\n", .{ status, input, text });
        },
        // The canonical float spelling is Zig's, shared with `str(value)`; the
        // formatter builds it on its own stack and appends it through the C
        // runtime's raw append, so no managed temporary exists for the text.
        .buffer_append_float => {
            const bits = try self.load("s", base);
            try self.print(" %v{d} =w call $myl_native_bytes_buffer_append_float(l %heap, l %v{d}, l %v{d})\n", .{ status, input, bits });
        },
        else => return self.reject(self.pc),
    }
    try emitBufferStatus(E, self, status, base);
}

/// One inlined octet-buffer append: the receiver the octets are written through,
/// its one-octet element descriptor, and the operand slot the method's boolean
/// result is stored into.
const BufferAppend = struct { input: usize, element: typed.Type, base: usize };

/// Answer one buffer status word as the boolean the method returns: a zero
/// status refused the allocation budget, which traps the way every other refused
/// allocation does, and any other status wrote exactly when it is
/// `MYL_BYTES_WROTE`.
fn emitBufferStatus(comptime E: type, self: *E, status: usize, base: usize) Error!void {
    const allocated = self.temp();
    const nonzero = self.temp();
    try self.print(" %v{d} =l extuw %v{d}\n %v{d} =l cnel %v{d}, 0\n", .{ allocated, status, nonzero, allocated });
    try self.require(nonzero, allocation_failure);
    const wrote = self.temp();
    try self.print(" %v{d} =w ceqw %v{d}, 1\n", .{ wrote, status });
    try emitBoolean(E, self, wrote, base);
}

/// Lower one octet-buffer method with its capacity-sufficient case inline, or
/// answer false when this method has no inlined case.
fn inlineBufferAppend(comptime E: type, self: *E, op: BufferOperation, stack: []const typed.Type, input: usize) Error!bool {
    const element = (try mutableOctetBuffer(E, self, op)) orelse return false;
    try self.markObject(input);
    const append: BufferAppend = .{ .input = input, .element = element, .base = stack.len - op.kind.arity() };
    switch (op.kind) {
        .buffer_append_range => try inlineAppendRange(E, self, stack, append),
        .buffer_append_byte => try inlineAppendByte(E, self, stack, append),
        else => return false,
    }
    return true;
}

/// The element descriptor of the mutable octet buffer this operation appends
/// through, or null when the receiver is anything else.
///
/// The checker admits the in-place append methods only on `byte_buffer`, whose
/// one constructor is `byte_buffer(...)`'s `acquire_buffer` — a fresh, mortal,
/// heap-allocated list. An immutable `bytes` literal can therefore never be a
/// receiver, so no image-frozen object reaches the inline paths below and the
/// runtime's frozen-receiver refusal stays with the helper on the path that can
/// still reach it. The stride is one octet, the same one `myl_native_bytes_*`
/// copies, so the inline store is the byte `storage + length` names.
fn mutableOctetBuffer(comptime E: type, self: *E, op: BufferOperation) Error!?typed.Type {
    const ty = self.function.scope.locals[@backingInt(op.owner)].ty;
    if (!ty.isAggregate()) return null;
    const schema = self.program.records[ty.recordIndex()];
    if (!schema.managed or schema.collection.kind != .bytes) return null;
    if (!std.mem.eql(u8, schema.name, byte_buffer_name)) return null;
    const element = schema.shape.buffer orelse return null;
    return if ((try self.layout(element)).size == 1) element else null;
}

/// Lower `buffer.append_range(data, start, end)` with the capacity-sufficient
/// case inline: the four argument checks the runtime performs, one compare of
/// `length + count` against `capacity`, one bulk copy of the octets and one
/// length bump. Only a request that does not fit reaches
/// `myl_native_bytes_buffer_append_range`, and the frame's live roots are linked
/// around that call alone, so the common path neither allocates nor publishes a
/// root.
///
/// The refusals come before the copy because they are what make the copy's
/// operands trustworthy: `start` negative, `end` before `start`, or `end` past
/// `len(data)` would otherwise turn `end - start` into a count no capacity can
/// bound and `data->storage + start` into a source outside `data`. With those
/// three answered, `count` fits in the receiver's own length, `length + count`
/// cannot wrap, and `length <= capacity` — the invariant every constructor,
/// grow and reserve maintains — makes `capacity - length` the room that is
/// really there.
fn inlineAppendRange(comptime E: type, self: *E, stack: []const typed.Type, append: BufferAppend) Error!void {
    const data = try self.load("s", append.base);
    const start = try self.load("s", append.base + 1);
    const end = try self.load("s", append.base + 2);
    const label = self.temp();
    const nonnegative = self.temp();
    const ordered = self.temp();
    const available = self.temp();
    const bounded = self.temp();
    const length = self.temp();
    const capacity = self.temp();
    const count = self.temp();
    const room = self.temp();
    const fits = self.temp();
    const capacity_pointer = try self.address(append.input, buffer_capacity_offset);
    try self.print(
        " %v{d} =l csgel %v{d}, 0\n jnz %v{d}, @buf_start{d}, @buf_refused{d}\n@buf_start{d}\n",
        .{ nonnegative, start, nonnegative, label, label, label },
    );
    try self.print(
        " %v{d} =l cslel %v{d}, %v{d}\n jnz %v{d}, @buf_order{d}, @buf_refused{d}\n@buf_order{d}\n",
        .{ ordered, start, end, ordered, label, label, label },
    );
    // The end bound is the *source's* octet count, not the receiver's: it is
    // what makes `data->storage + start` a range this call owns the length of.
    try self.print(
        " %v{d} =l loadl %v{d}\n %v{d} =l culel %v{d}, %v{d}\n jnz %v{d}, @buf_bound{d}, @buf_refused{d}\n@buf_bound{d}\n",
        .{ available, data, bounded, end, available, bounded, label, label, label },
    );
    try self.print(
        " %v{d} =l loadl %v{d}\n %v{d} =l loadl %v{d}\n %v{d} =l sub %v{d}, %v{d}\n %v{d} =l sub %v{d}, %v{d}\n %v{d} =l cultl %v{d}, %v{d}\n jnz %v{d}, @buf_fast{d}, @buf_slow{d}\n@buf_slow{d}\n",
        .{ length, append.input, capacity, capacity_pointer, count, end, start, room, capacity, length, fits, count, room, fits, label, label, label },
    );
    const pushed = try self.roots(stack);
    const status = self.temp();
    try self.print(" %v{d} =w call $myl_native_bytes_buffer_append_range(l %heap, l %v{d}, l %v{d}, l %v{d}, l %v{d})\n", .{ status, append.input, data, start, end });
    if (pushed) try self.restoreRoots();
    try emitBufferStatus(E, self, status, append.base);
    try self.print(" jmp @buf_done{d}\n@buf_fast{d}\n", .{ label, label });
    try self.markObject(data);
    const storage_pointer = try self.address(append.input, buffer_storage_offset);
    const data_storage_pointer = try self.address(data, buffer_storage_offset);
    const storage = self.temp();
    const destination = self.temp();
    const source_storage = self.temp();
    const source = self.temp();
    const next_length = self.temp();
    try self.print(
        " %v{d} =l loadl %v{d}\n %v{d} =l add %v{d}, %v{d}\n %v{d} =l loadl %v{d}\n %v{d} =l add %v{d}, %v{d}\n",
        .{ storage, storage_pointer, destination, storage, length, source_storage, data_storage_pointer, source, source_storage, start },
    );
    try self.markElements(storage, append.element);
    try self.markElements(source_storage, append.element);
    try self.print(" call $myl_native_bytes_copy_octets(l %v{d}, l %v{d}, l %v{d})\n", .{ destination, source, count });
    try self.print(
        " %v{d} =l add %v{d}, %v{d}\n storel %v{d}, %v{d}\n" ++ store_true ++ " jmp @buf_done{d}\n@buf_refused{d}\n" ++ store_false ++ " jmp @buf_done{d}\n@buf_done{d}\n",
        .{ next_length, length, count, next_length, append.input, append.base, label, label, append.base, label, label },
    );
    self.inline_roots = true;
}

/// Lower `buffer.append_byte(value)` with the capacity-sufficient case inline:
/// the range check the runtime performs, one compare of `length` against
/// `capacity`, one octet store and one length bump. Only an out-of-range value
/// or a full receiver reaches `myl_native_bytes_buffer_append_byte`, and the
/// frame's live roots are linked around that call alone.
fn inlineAppendByte(comptime E: type, self: *E, stack: []const typed.Type, append: BufferAppend) Error!void {
    const value = try self.load("s", append.base);
    const label = self.temp();
    const nonnegative = self.temp();
    const inrange = self.temp();
    const length = self.temp();
    const capacity = self.temp();
    const room = self.temp();
    const capacity_pointer = try self.address(append.input, buffer_capacity_offset);
    try self.print(
        " %v{d} =l csgel %v{d}, 0\n jnz %v{d}, @byte_low{d}, @byte_refused{d}\n@byte_low{d}\n",
        .{ nonnegative, value, nonnegative, label, label, label },
    );
    try self.print(
        " %v{d} =l cslel %v{d}, 255\n jnz %v{d}, @byte_high{d}, @byte_refused{d}\n@byte_high{d}\n",
        .{ inrange, value, inrange, label, label, label },
    );
    try self.print(
        " %v{d} =l loadl %v{d}\n %v{d} =l loadl %v{d}\n %v{d} =l cultl %v{d}, %v{d}\n jnz %v{d}, @byte_fast{d}, @byte_slow{d}\n@byte_slow{d}\n",
        .{ length, append.input, capacity, capacity_pointer, room, length, capacity, room, label, label, label },
    );
    const pushed = try self.roots(stack);
    const status = self.temp();
    try self.print(" %v{d} =w call $myl_native_bytes_buffer_append_byte(l %heap, l %v{d}, l %v{d})\n", .{ status, append.input, value });
    if (pushed) try self.restoreRoots();
    try emitBufferStatus(E, self, status, append.base);
    try self.print(" jmp @byte_done{d}\n@byte_fast{d}\n", .{ label, label });
    const storage_pointer = try self.address(append.input, buffer_storage_offset);
    const storage = self.temp();
    const destination = self.temp();
    const next_length = self.temp();
    try self.print(" %v{d} =l loadl %v{d}\n %v{d} =l add %v{d}, %v{d}\n", .{ storage, storage_pointer, destination, storage, length });
    try self.markElements(storage, append.element);
    try self.writeValue(destination, value, append.element);
    try self.print(
        " %v{d} =l add %v{d}, 1\n storel %v{d}, %v{d}\n" ++ store_true ++ " jmp @byte_done{d}\n@byte_refused{d}\n" ++ store_false ++ " jmp @byte_done{d}\n@byte_done{d}\n",
        .{ next_length, length, next_length, append.input, append.base, label, label, append.base, label, label },
    );
    self.inline_roots = true;
}
