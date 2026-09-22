//! QBE lowering of precisely rooted native managed collections.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
/// Failures producing native managed collection instructions.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
const BufferOperation = @FieldType(@FieldType(bytecode.Instruction, "op"), "buffer_operation");
const store_unit = " storel 0, %s{d}\n";
const copy_scratch = " %v{d} =l copy %s{d}\n";
const load_scratch = " %v{d} =l loadl %s{d}\n";
/// Load one native word through a computed pointer.
const load_pointer = " %v{d} =l loadl %v{d}\n";
/// Append one element through the runtime's grow-capable helper.
const list_append_call = " %v{d} =w call $myl_native_list_append(l %heap, l %v{d}, l %v{d})\n";
const format = @import("qbe_format.zig");
const allocation_failure = format.allocation_failure;
const list_value_failure = "myl_qbe_fail_list_value";
const missing_key_failure = "myl_qbe_fail_missing_key";
const numeric_surface = @import("numeric_surface.zig");
const load_word = format.load_word;
const iteration_failure = "myl_qbe_fail_iteration";
const bytes_lower = @import("qbe_bytes.zig");
const text_lower = @import("qbe_text.zig");
const arena_lower = @import("qbe_arena.zig");
const io_lower = @import("qbe_io.zig");
const render = @import("native_render.zig");
const dictionary_write = " %v{d} =w call $myl_native_dictionary_write(l %heap, l %v{d}, l %v{d}, l %v{d})\n";
const dictionary_length = " %v{d} =l call $myl_native_dictionary_length(l %v{d})\n";
/// Byte offset of `storage` in a native list header (`native_collections.h`):
/// two size words, the generation, the element descriptor, then the pointer.
const list_storage_offset = format.list_storage_offset;
/// Byte offsets of the capacity and generation words of that same header, which
/// the inline append fast path reads and bumps.
const list_capacity_offset = 8;
const list_generation_offset = 16;
/// Detail-carrying bounds helper shared by indexable receivers.
const index_failure = "myl_qbe_fail_index_bounds";
/// The `make_record` operation shape this unit lowers.
const MakeRecord = @FieldType(@FieldType(bytecode.Instruction, "op"), "make_record");
/// Marker line the metadata unit scans for the C definition of one frozen
/// literal. QBE ignores it as a comment; the payload follows as element bytes in
/// lowercase hex. Format: `# myl-lit <symbol> <element> <width> <count> [hex]`.
const literal_marker = "# myl-lit ";
/// A frozen `str`/`bytes` literal: the global data symbol the metadata unit
/// defines, the element descriptor its object header stores, its element width —
/// zero for a text, whose payload is UTF-8 octets rather than elements — its
/// payload unit count, and for a text its scalar count and ASCII flag, which are
/// also the count of the constant pushes it was built from. `digest` names it.
const Frozen = struct {
    name: [72]u8,
    element: []const u8,
    width: usize,
    count: usize,
    scalars: usize,
    ascii: bool,
    digest: [32]u8,
};
/// The element descriptor a frozen text literal's object header stores: a text's
/// payload is octets and holds no traced pointer, so the collector never walks it.
const text_leaf = "myl_native_text_leaf";
/// List element access normalizes a negative index in the checked frontend; the
/// runtime helper subtracts the length back to recover the original index.
const normalized_index_failure = "myl_qbe_fail_normalized_index_bounds";
/// Bind managed lowering to the concrete emitter without dependency cycles.
pub fn Lower(comptime E: type) type {
    return struct {
        /// Convert a value to canonical immutable Unicode text, or a list to bytes.
        pub fn cast(self: *E, ty: typed.Type, stack: []const typed.Type) Error!void {
            return emitCast(E, self, ty, stack);
        }
        /// Emit a managed collection method invocation.
        pub fn operation(self: *E, op: BufferOperation, stack: []const typed.Type) Error!void {
            return emitOperation(E, self, op, stack);
        }
        /// Construct a managed string, list, or dictionary.
        pub fn construct(self: *E, op: MakeRecord, stack: []const typed.Type) Error!void {
            return emitConstruct(E, self, op, stack);
        }
        /// Read the initialized collection element count.
        pub fn length(self: *E, ty: typed.Type, stack: []const typed.Type) Error!void {
            return emitLength(E, self, ty, stack);
        }
        /// Read or replace a managed collection element.
        pub fn index(self: *E, ty: typed.Type, stack: []const typed.Type) Error!void {
            return emitIndex(E, self, ty, stack);
        }
        /// Compare managed contents or concatenate strings.
        pub fn binary(self: *E, op: @FieldType(@FieldType(bytecode.Instruction, "op"), "binary_integer"), stack: []const typed.Type) Error!void {
            return emitBinary(E, self, op, stack);
        }
    };
}
/// Lower one managed collection operation using native typed storage.
fn emitOperation(comptime E: type, self: *E, op: BufferOperation, stack: []const typed.Type) Error!void {
    const ty = self.function.scope.locals[@backingInt(op.owner)].ty;
    const schema = self.program.records[ty.recordIndex()];
    if (!schema.managed) return self.reject(self.pc);
    if (schema.collection.kind == .string) return textOperation(E, self, op, stack);
    if (schema.collection.kind == .dictionary) return dictionaryOperation(E, self, op, stack);
    // Byte strings share the native list representation, so length, iteration and
    // element reads stay here while the byte-specific methods lower separately.
    if (schema.collection.kind == .bytes) switch (op.kind) {
        .length, .iteration_check, .read => {},
        else => return bytes_lower.Lower(E).operation(self, op, stack),
    };
    const h = stack.len;
    const base = h - op.kind.arity();
    const list = try self.load("l", @backingInt(op.owner));
    try self.markObject(list);
    const output = self.temp();
    switch (op.kind) {
        .length, .capacity => {
            const pointer = try self.address(list, if (op.kind == .length) 0 else 8);
            try self.print(load_word, .{ output, pointer });
            try self.store(base, output);
        },
        .iteration_check => {
            const expected = try self.load("s", base);
            const actual = self.temp();
            try self.print(" %v{d} =l loadl %v{d}\n %v{d} =l ceql %v{d}, %v{d}\n", .{ actual, list, output, actual, expected });
            try self.require(output, iteration_failure);
            try self.print(store_unit, .{base});
        },
        .contains => {
            const element = schema.shape.buffer.?;
            const needle = try operandPointer(E, self, element, base);
            try self.print(" %v{d} =w call $myl_native_list_contains(l %v{d}, l ${s}, l %v{d})\n", .{ output, list, try self.descriptor(element), needle });
            try equalResult(E, self, output);
            try boolean(E, self, output, base);
        },
        .read => {
            const index_value = try self.load("s", base);
            const length = try receiverLength(E, self, list);
            // Concrete layouts fix the element stride. Scalars load directly;
            // records keep their value snapshot unless only an immediate scalar
            // field projection can observe it. Zero-sized layouts retain their
            // existing runtime/scratch representation.
            if ((try self.layout(op.output)).size != 0) {
                try inlineIndexRead(E, self, .{ .input = list, .at = index_value, .raw_index = index_value, .length = length, .element = op.output, .slot = base }, normalized_index_failure);
            } else {
                try self.print(" %v{d} =w call $myl_native_list_get(l %v{d}, l %v{d}, l %agg{d})\n", .{ output, list, index_value, self.pc });
                try requireIndexBounds(E, self, output, index_value, length, normalized_index_failure);
                try self.store(base, try self.readValue(try self.aggregatePointer(), op.output));
            }
        },
        .append, .write => {
            const element = schema.shape.buffer.?;
            const position = h - 1;
            const value_pointer = self.temp();
            if (self.isScalar(element)) try self.print(copy_scratch, .{ value_pointer, position }) else try self.print(load_scratch, .{ value_pointer, position });
            try arena_lower.Lower(E).barrier(self, list, element, value_pointer);
            if (op.kind == .append) {
                if (self.needsRootProtocol()) {
                    try inlineAppend(E, self, list, element, value_pointer, output, stack);
                } else {
                    try self.print(list_append_call, .{ output, list, value_pointer });
                    try self.require(output, allocation_failure);
                }
            } else {
                const index_value = try self.load("s", base);
                const length = try receiverLength(E, self, list);
                try self.print(" %v{d} =w call $myl_native_list_set(l %v{d}, l %v{d}, l %v{d})\n", .{ output, list, index_value, value_pointer });
                try requireIndexBounds(E, self, output, index_value, length, normalized_index_failure);
            }
            try self.print(store_unit, .{base});
        },
        .extend => {
            const other = try self.load("s", base);
            try self.print(" %v{d} =w call $myl_native_list_extend(l %heap, l %v{d}, l %v{d})\n", .{ output, list, other });
            try self.require(output, allocation_failure);
            try self.print(store_unit, .{base});
        },
        .insert => {
            const element = schema.shape.buffer.?;
            const position = h - 1;
            const value_pointer = self.temp();
            if (self.isScalar(element)) try self.print(copy_scratch, .{ value_pointer, position }) else try self.print(load_scratch, .{ value_pointer, position });
            try arena_lower.Lower(E).barrier(self, list, element, value_pointer);
            const index_value = try self.load("s", base);
            try self.print(" %v{d} =w call $myl_native_list_insert(l %heap, l %v{d}, l %v{d}, l %v{d})\n", .{ output, list, index_value, value_pointer });
            try self.require(output, allocation_failure);
            try self.print(store_unit, .{base});
        },
        .pop, .pop_at => {
            const pointer = try self.aggregatePointer();
            const length = try receiverLength(E, self, list);
            if (op.kind == .pop_at) {
                const index_value = try self.load("s", base);
                try self.print(" %v{d} =w call $myl_native_list_pop_at(l %v{d}, l %v{d}, l %agg{d})\n", .{ output, list, index_value, self.pc });
                try requireIndexBounds(E, self, output, index_value, length, "myl_qbe_fail_pop_at_bounds");
            } else {
                try self.print(" %v{d} =w call $myl_native_list_pop(l %v{d}, l %agg{d})\n", .{ output, list, self.pc });
                try requirePopBounds(E, self, output, length);
            }
            try self.store(base, try self.readValue(pointer, op.output));
        },
        .remove => {
            const element = schema.shape.buffer.?;
            const needle = try operandPointer(E, self, element, base);
            try self.print(" %v{d} =w call $myl_native_list_remove(l %v{d}, l %v{d})\n", .{ output, list, needle });
            const found = self.temp();
            try self.print(" %v{d} =w ceqw %v{d}, 1\n", .{ found, output });
            try self.require(found, list_value_failure);
            try self.print(store_unit, .{base});
        },
        .index_of => {
            const element = schema.shape.buffer.?;
            const needle = try operandPointer(E, self, element, base);
            const pointer = try self.aggregatePointer();
            try self.print(" %v{d} =w call $myl_native_list_index(l %v{d}, l %v{d}, l %agg{d})\n", .{ output, list, needle, self.pc });
            const found = self.temp();
            try self.print(" %v{d} =w ceqw %v{d}, 1\n", .{ found, output });
            try self.require(found, list_value_failure);
            try self.store(base, try self.readValue(pointer, .i64));
        },
        .reverse => {
            try self.print(" call $myl_native_list_reverse(l %v{d})\n", .{list});
            try self.print(store_unit, .{base});
        },
        .sort => {
            const element = schema.shape.buffer.?;
            const order: u32 = if (numeric_surface.isFloat(element, self.program.records)) 2 else if (element.isInteger()) (if (element.integer().?.signed) 0 else 1) else 3;
            try self.print(" %v{d} =w call $myl_native_list_sort(l %v{d}, w {d})\n", .{ output, list, order });
            try self.require(output, allocation_failure);
            try self.print(store_unit, .{base});
        },
        .copy => {
            const result = self.temp();
            try self.print(" %v{d} =l call $myl_native_list_copy(l %heap, l %v{d})\n", .{ result, list });
            try checkedPointer(E, self, result, base);
        },
        .clear => {
            try self.print(" %v{d} =w call $myl_native_list_clear(l %v{d})\n", .{ output, list });
            try self.print(store_unit, .{base});
        },
        .slice_step => try steppedSlice(E, self, base, list),
        else => return self.reject(self.pc),
    }
}

/// Copy a stepped slice through the shared native list routine, which text shares.
fn steppedSlice(comptime E: type, self: *E, base: usize, input: usize) Error!void {
    return sliceStep(E, self, base, input, "myl_native_list_slice_step");
}

/// Lower a stepped slice of text, whose element storage is UTF-8 octets: the
/// gather cannot read a stride of the payload, so it runs on the text runtime.
fn textStep(comptime E: type, self: *E, base: usize, input: usize) Error!void {
    return sliceStep(E, self, base, input, "myl_native_text_slice_step");
}

/// Lower `receiver[start:stop:step]` onto `callee`, trapping a zero step before
/// either engine runs.
fn sliceStep(comptime E: type, self: *E, base: usize, input: usize, callee: []const u8) Error!void {
    const first = try self.load("s", base);
    const last = try self.load("s", base + 1);
    const step = try self.load("s", base + 2);
    const nonzero = self.temp();
    try self.print(" %v{d} =l cnel %v{d}, 0\n", .{ nonzero, step });
    try self.require(nonzero, "myl_qbe_fail_slice_step");
    const result = self.temp();
    try self.print(" %v{d} =l call ${s}(l %heap, l %v{d}, l %v{d}, l %v{d}, l %v{d})\n", .{ result, callee, input, first, last, step });
    try checkedPointer(E, self, result, base);
}

fn operandPointer(comptime E: type, self: *E, ty: typed.Type, slot: usize) Error!usize {
    const result = self.temp();
    if (self.isScalar(ty)) try self.print(copy_scratch, .{ result, slot }) else try self.print(load_scratch, .{ result, slot });
    return result;
}
fn boolean(comptime E: type, self: *E, result: usize, slot: usize) Error!void {
    const extended = self.temp();
    try self.print(" %v{d} =l extuw %v{d}\n", .{ extended, result });
    try self.store(slot, extended);
}
fn checkedPointer(comptime E: type, self: *E, result: usize, slot: usize) Error!void {
    try self.require(result, allocation_failure);
    try self.store(slot, result);
}
/// Require `result`, otherwise raise a bounds trap carrying the already-loaded
/// original index and receiver length. `failure` names the detail-carrying
/// runtime helper; both values are captured, never recomputed.
///
/// QBE-UNCHECKED-1: an unchecked build emits neither the test nor the cold
/// block. The runtime call or inline address that produced `result` still runs,
/// so the value the caller goes on to use is unchanged on a valid index.
fn requireIndexBounds(comptime E: type, self: *E, result: usize, index: usize, length: usize, failure: []const u8) Error!void {
    if (!self.checks) return;
    const label = self.temp();
    try self.print(" jnz %v{d}, @success{d}, @failed{d}\n@failed{d}\n call ${s}(l %ctx, l %v{d}, l %v{d})\n jmp @failure\n@success{d}\n", .{ result, label, label, label, failure, index, length, label });
}
/// Require a pop that has no caller index; report the receiver length only.
/// QBE-UNCHECKED-1 drops this test with the other container-range tests.
fn requirePopBounds(comptime E: type, self: *E, result: usize, length: usize) Error!void {
    if (!self.checks) return;
    const label = self.temp();
    try self.print(" jnz %v{d}, @success{d}, @failed{d}\n@failed{d}\n call $myl_qbe_fail_pop_bounds(l %ctx, l %v{d})\n jmp @failure\n@success{d}\n", .{ result, label, label, label, length, label });
}
/// Load one native list-like header word (length for lists, text and bytes).
fn receiverLength(comptime E: type, self: *E, receiver: usize) Error!usize {
    const length = self.temp();
    try self.markObject(receiver);
    try self.print(load_word, .{ length, receiver });
    return length;
}
/// Construct immutable text, an ordinary managed list, or an ordered dictionary.
fn emitConstruct(comptime E: type, self: *E, record: MakeRecord, stack: []const typed.Type) Error!void {
    const schema = self.program.records[record.ty.recordIndex()];
    const base = stack.len - record.fields;
    const result = self.temp();
    if (schema.collection.kind == .dictionary) {
        const key = schema.collection.key.?;
        const text_keys = key.isAggregate() and self.program.records[key.recordIndex()].collection.kind == .string;
        try self.print(" %v{d} =l call $myl_native_dictionary_new(l %heap, l ${s}, l ${s}, w {d})\n", .{ result, try self.descriptor(key), try self.descriptor(schema.shape.buffer.?), @intFromBool(text_keys) });
        try self.require(result, allocation_failure);
        var i: usize = 0;
        while (i < record.fields) : (i += 2) {
            const ok = self.temp();
            const key_pointer = try operandPointer(E, self, key, base + i);
            const value_pointer = try operandPointer(E, self, schema.shape.buffer.?, base + i + 1);
            try self.print(dictionary_write, .{ ok, result, key_pointer, value_pointer });
            try self.require(ok, allocation_failure);
        }
    } else {
        const text = schema.collection.kind == .string;
        const element: typed.Type = if (text) .u32 else schema.shape.buffer.?;
        // A `str`/`bytes` literal whose every element is a constant push is
        // immutable for the life of the image, so it lives as one shared data
        // object instead of one allocation per evaluation.
        if (text or schema.collection.kind == .bytes) {
            if (try frozenLiteral(E, self, record, element, text)) |frozen| return emitFrozen(E, self, frozen, base);
        }
        try self.print(" %v{d} =l call $myl_native_list_new(l %heap, l ${s}, l {d})\n", .{ result, try self.descriptor(element), record.fields });
        try self.require(result, allocation_failure);
        for (0..record.fields) |i| {
            const ok = self.temp();
            const value_pointer = try operandPointer(E, self, element, base + i);
            try self.print(list_append_call, .{ ok, result, value_pointer });
            try self.require(ok, allocation_failure);
        }
        // A text whose elements were not all constants is assembled scalar by
        // scalar into a temporary list, because a text's payload is UTF-8 and a
        // scalar's width is only known once it is written. The conversion roots
        // the temporary across its own allocation.
        if (text) {
            const converted = self.temp();
            try self.print(" %v{d} =l call $myl_native_text_from_points(l %heap, l %v{d})\n", .{ converted, result });
            try self.require(converted, allocation_failure);
            try self.store(base, converted);
            return;
        }
    }
    try self.store(base, result);
}
/// Describe a constant `str`/`bytes` literal as one frozen data object, or null
/// when any operand is not a constant push of the element type. The data symbol
/// hashes the element descriptor and the native payload, so equal literals share
/// one object across the whole image; a text hashes its UTF-8 octets, so equal
/// text shares one object whatever its scalar widths.
fn frozenLiteral(comptime E: type, self: *E, record: MakeRecord, element: typed.Type, text: bool) Error!?Frozen {
    const count = record.fields;
    if (record.order.len != 0 or self.pc < count) return null;
    const first = self.pc - count;
    for (0..count) |i| switch (self.function.scope.instructions[first + i].op) {
        .push_integer => |number| if (number.ty != element) return null,
        else => return null,
    };
    var frozen: Frozen = .{
        .name = undefined,
        .element = if (text) text_leaf else try self.descriptor(element),
        .width = if (text) 0 else (try self.layout(element)).size,
        .count = count,
        .scalars = count,
        .ascii = true,
        .digest = undefined,
    };
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(frozen.element);
    hasher.update(&[_]u8{0});
    var scratch: [8]u8 = undefined;
    var octets: usize = 0;
    for (0..count) |i| {
        const value = pushedValue(E, self, first + i);
        if (!text) {
            hasher.update(elementBytes(frozen.width, value, &scratch));
            continue;
        }
        var encoded: [4]u8 = undefined;
        const bytes = encodeScalar(value, &encoded) orelse return null;
        hasher.update(bytes);
        octets += bytes.len;
        if (value >= 0x80) frozen.ascii = false;
    }
    if (text) frozen.count = octets;
    hasher.final(&frozen.digest);
    _ = std.fmt.bufPrint(&frozen.name, "myl_lit_{s}", .{std.fmt.bytesToHex(frozen.digest, .lower)}) catch return error.InternalError;
    return frozen;
}
/// The UTF-8 encoding of one pushed scalar, or null when the value is not a
/// Unicode scalar value and so could not be part of a text.
fn encodeScalar(value: i128, buffer: *[4]u8) ?[]const u8 {
    if (value < 0 or value > 0x10ffff) return null;
    const scalar: u21 = @intCast(value);
    if (scalar >= 0xd800 and scalar <= 0xdfff) return null;
    const length = std.unicode.utf8Encode(scalar, buffer) catch return null;
    return buffer[0..length];
}
/// Lower one frozen literal as a load of its shared data pointer plus the
/// metadata marker that names its image bytes. A text marker carries its scalar
/// count and ASCII flag after the octet count, because its object header is not
/// an element list and the metadata unit emits a different block for it.
fn emitFrozen(comptime E: type, self: *E, frozen: Frozen, base: usize) Error!void {
    const result = self.temp();
    try self.print(" %v{d} =l loadl ${s}\n", .{ result, frozen.name[0..] });
    try self.print("{s}{s} {s} {d} {d} ", .{ literal_marker, frozen.name[0..], frozen.element, frozen.width, frozen.count });
    const pushes = if (frozen.width == 0) frozen.scalars else frozen.count;
    if (frozen.width == 0) try self.print("{d} {d} ", .{ frozen.scalars, @intFromBool(frozen.ascii) });
    const first = self.pc - pushes;
    var scratch: [8]u8 = undefined;
    for (0..pushes) |i| {
        const value = pushedValue(E, self, first + i);
        if (frozen.width != 0) {
            for (elementBytes(frozen.width, value, &scratch)) |byte| try self.print("{x:0>2}", .{byte});
            continue;
        }
        var encoded: [4]u8 = undefined;
        for (encodeScalar(value, &encoded) orelse return error.InternalError) |byte| try self.print("{x:0>2}", .{byte});
    }
    try self.print("\n", .{});
    try self.store(base, result);
}
/// The constant carried by one already-validated `push_integer`.
fn pushedValue(comptime E: type, self: *E, at: usize) i128 {
    return switch (self.function.scope.instructions[at].op) {
        .push_integer => |number| number.value,
        else => 0,
    };
}
/// The low `width` bytes of one scalar in native little-endian order.
fn elementBytes(width: usize, value: i128, scratch: *[8]u8) []const u8 {
    std.mem.writeInt(u64, scratch, @truncate(@as(u128, @bitCast(value))), .little);
    return scratch[0..width];
}
/// Lower `list.append(value)` with the capacity-sufficient case inline: a
/// length/capacity compare, one element store and two counter bumps. The grow
/// helper is reached only when the element does not fit, and the frame's roots
/// are linked only around that call, so the common path neither allocates nor
/// publishes a root and the value no longer has to live at an address a callee
/// can capture. The frozen receiver the helper refuses — `generation` at
/// `UINT64_MAX` — cannot occur for a list: the runtime only ever increments the
/// generation, and the image-frozen literals carry `generation = 0` plus an
/// immortal object header, so the receiver is always writable and the helper's
/// refusal test is left to the slow path it already guards.
fn inlineAppend(comptime E: type, self: *E, list: usize, element: typed.Type, value_pointer: usize, output: usize, stack: []const typed.Type) Error!void {
    const label = self.temp();
    const width = (try self.layout(element)).size;
    // A one-word scalar is read into a register once and carried through both
    // paths by value, so no callee ever receives the operand slot's address and
    // the push that filled it can be promoted away. Wider and aggregate elements
    // keep the pointer the runtime copies from.
    const scalar = self.isScalar(element) and width != 0 and width <= 8;
    const held = if (scalar) try self.readValue(value_pointer, element) else value_pointer;
    try self.markObject(list);
    const generation = try self.address(list, list_generation_offset);
    const current = self.temp();
    try self.print(load_pointer, .{ current, generation });
    const length = self.temp();
    const capacity_pointer = try self.address(list, list_capacity_offset);
    const capacity = self.temp();
    try self.print(" %v{d} =l loadl %v{d}\n %v{d} =l loadl %v{d}\n", .{ length, list, capacity, capacity_pointer });
    const fits = self.temp();
    try self.print(" %v{d} =l cultl %v{d}, %v{d}\n jnz %v{d}, @append_fast{d}, @append_slow{d}\n@append_slow{d}\n", .{ fits, length, capacity, fits, label, label, label });
    const pushed = try self.roots(stack);
    if (scalar) {
        try self.print(" %v{d} =w call $myl_native_list_append_scalar(l %heap, l %v{d}, l %v{d})\n", .{ output, list, held });
    } else {
        try self.print(list_append_call, .{ output, list, value_pointer });
    }
    try self.require(output, allocation_failure);
    if (pushed) try self.restoreRoots();
    try self.print(" jmp @append_done{d}\n@append_fast{d}\n", .{ label, label });
    const storage = try self.address(list, list_storage_offset);
    const backing = self.temp();
    try self.print(load_pointer, .{ backing, storage });
    try self.markObject(backing);
    const destination = self.temp();
    if (width == 1) {
        try self.print(" %v{d} =l add %v{d}, %v{d}\n", .{ destination, backing, length });
    } else {
        const offset = self.temp();
        try self.print(" %v{d} =l mul %v{d}, {d}\n %v{d} =l add %v{d}, %v{d}\n", .{ offset, length, width, destination, backing, offset });
    }
    if (width != 0) try self.writeValue(destination, held, element);
    const next_length = self.temp();
    try self.print(" %v{d} =l add %v{d}, 1\n storel %v{d}, %v{d}\n", .{ next_length, length, next_length, list });
    const next_generation = self.temp();
    try self.print(" %v{d} =l add %v{d}, 1\n storel %v{d}, %v{d}\n@append_done{d}\n", .{ next_generation, current, next_generation, generation, label });
    self.inline_roots = true;
}
/// Read Unicode scalar count, list length, or dictionary entry count.
fn emitLength(comptime E: type, self: *E, ty: typed.Type, stack: []const typed.Type) Error!void {
    const base = stack.len - 1;
    const input = try self.load("s", base);
    const result = self.temp();
    if (self.program.records[ty.recordIndex()].collection.kind == .dictionary) {
        try self.print(dictionary_length, .{ result, input });
    } else {
        try self.markObject(input);
        try self.print(load_word, .{ result, input });
    }
    try self.store(base, result);
}
/// Normalize one signed index the way Python does: a negative index counts back
/// from the end of the receiver. The adjustment is derived branchlessly from the
/// sign mask (`raw >> 63` is all ones exactly when `raw` is negative), so the
/// common non-negative read carries no branch, label or phi. An index still
/// below `-length` stays negative and the caller's unsigned bounds check rejects
/// it, exactly as the branching form did.
fn normalizedIndex(comptime E: type, self: *E, index_value: usize, length: usize, ty: typed.Type) Error!usize {
    if (!ty.integer().?.signed) return index_value;
    const mask = self.temp();
    const adjust = self.temp();
    const chosen = self.temp();
    try self.print(
        " %v{d} =l sar %v{d}, 63\n %v{d} =l and %v{d}, %v{d}\n %v{d} =l add %v{d}, %v{d}\n",
        .{ mask, index_value, adjust, mask, length, chosen, index_value, adjust },
    );
    return chosen;
}
/// Index or replace managed elements using native unboxed storage.
fn emitIndex(comptime E: type, self: *E, ty: typed.Type, stack: []const typed.Type) Error!void {
    const replacing = self.function.scope.instructions[self.pc].op == .replace_index;
    const base = stack.len - @as(usize, if (replacing) 3 else 2);
    const schema = self.program.records[ty.recordIndex()];
    const input = try self.load("s", base);
    const result = self.temp();
    if (schema.collection.kind == .string) {
        if (replacing) return self.reject(self.pc);
        const at = try self.load("s", base + 1);
        try textAt(E, self, input, at, stack[base + 1], result, base);
    } else if (schema.collection.kind == .dictionary) {
        const key = try operandPointer(E, self, schema.collection.key.?, base + 1);
        if (replacing) {
            const value = try operandPointer(E, self, schema.shape.buffer.?, base + 2);
            try arena_lower.Lower(E).barrier(self, input, schema.collection.key.?, key);
            try arena_lower.Lower(E).barrier(self, input, schema.shape.buffer.?, value);
            try self.print(dictionary_write, .{ result, input, key, value });
            try self.require(result, allocation_failure);
            try self.store(base, input);
        } else {
            try self.print(" %v{d} =w call $myl_native_dictionary_read(l %v{d}, l %v{d}, l %agg{d})\n", .{ result, input, key, self.pc });
            try self.require(result, missing_key_failure);
            try self.store(base, try self.readValue(try self.aggregatePointer(), schema.shape.buffer.?));
        }
    } else {
        const raw_index = try self.load("s", base + 1);
        const length = try receiverLength(E, self, input);
        const at = try normalizedIndex(E, self, raw_index, length, stack[base + 1]);
        if (replacing) {
            const value = try operandPointer(E, self, schema.shape.buffer.?, base + 2);
            try arena_lower.Lower(E).barrier(self, input, schema.shape.buffer.?, value);
            try self.print(" %v{d} =w call $myl_native_list_set(l %v{d}, l %v{d}, l %v{d})\n", .{ result, input, at, value });
            try requireIndexBounds(E, self, result, raw_index, length, index_failure);
            try self.store(base, input);
        } else {
            try inlineIndexRead(E, self, .{ .input = input, .at = at, .raw_index = raw_index, .length = length, .element = schema.shape.buffer.?, .slot = base }, index_failure);
        }
    }
}
/// One inline element read: the receiver, the normalized index, the caller's
/// original index and the receiver length for the trap, and where the value goes.
const IndexRead = struct { input: usize, at: usize, raw_index: usize, length: usize, element: typed.Type, slot: usize };
/// A list element's backing may be borrowed only through an uninterrupted chain
/// of field reads ending in a scalar value. No branch may enter that chain and
/// no call, allocation, mutation or stored aggregate may intervene. Each field
/// instruction still executes with its original position and step check; the
/// interior address never survives to an instruction that can collect or mutate.
fn immediateScalarProjection(comptime E: type, self: *E, element: typed.Type) Error!bool {
    if ((try self.layout(element)).drop) return false;
    var ty = element;
    var pc = self.pc + 1;
    const code = self.function.scope.instructions;
    while (pc < code.len) : (pc += 1) {
        if (self.states[pc] == null or self.branch_targets[pc]) return false;
        const index = switch (code[pc].op) {
            .get_field => |field| field,
            else => return false,
        };
        if (!ty.isAggregate() or self.program.records[ty.recordIndex()].isManagedRecord()) return false;
        ty = (try self.field(ty, index)).ty;
        if (self.isScalar(ty)) return true;
    }
    return false;
}
/// QBE-AGGREF-1's by-address rule for a list element whose only consumer is the
/// store that copies it into a local of its own.
///
/// The element lives in the receiver's backing storage. The instruction that
/// follows this read is a `store_local` reached by falling through, of the
/// element's own type, and the element owns nothing, so that store can blit
/// straight out of the element instead of out of a snapshot of it: passing the
/// checked address on removes the copy into per-pc aggregate scratch, and the
/// one copy the program asked for — into the destination local — remains. No
/// call, allocation, mutation or release runs in between, because the very next
/// instruction is the store, and the address is dead once it has copied. An
/// element the store would release (a type with a `drop`) keeps its snapshot,
/// so no release ever runs against storage the list still owns, and a zero-sized
/// element keeps the scratch the frame protocol places after the entry block.
fn elementFeedsStore(comptime E: type, self: *E, element: typed.Type) Error!bool {
    const code = self.function.scope.instructions;
    const next = self.pc + 1;
    if (next >= code.len or self.states[next] == null) return false;
    if (next < self.branch_targets.len and self.branch_targets[next]) return false;
    const slot = switch (code[next].op) {
        .store_local => |target| @backingInt(target),
        else => return false,
    };
    if (slot >= self.function.scope.locals.len) return false;
    if (self.function.scope.locals[slot].ty != element) return false;
    const value = try self.layout(element);
    return !value.drop and value.size != 0;
}
/// Read one element of a byte string or list straight from its backing storage
/// after an unsigned bounds check, in place of a `myl_native_list_get` call.
/// The cold path raises the same detail-carrying bounds trap, with the caller's
/// original index and the receiver length: `failure` names the helper that
/// reports an index this lowering already normalized, or one it has not.
fn inlineIndexRead(comptime E: type, self: *E, read: IndexRead, failure: []const u8) Error!void {
    // QBE-UNCHECKED-1: the comparison exists only to feed the test, so an
    // unchecked build emits neither and reads the element address directly.
    if (self.checks) {
        const valid = self.temp();
        try self.print(" %v{d} =l cultl %v{d}, %v{d}\n", .{ valid, read.at, read.length });
        try requireIndexBounds(E, self, valid, read.raw_index, read.length, failure);
    }
    const address = try elementAddress(E, self, read.input, read.at, read.element);
    if (self.isScalar(read.element)) {
        try self.store(read.slot, try self.readValue(address, read.element));
    } else if (try immediateScalarProjection(E, self, read.element)) {
        try self.store(read.slot, address);
    } else if (try elementFeedsStore(E, self, read.element)) {
        try self.store(read.slot, address);
    } else {
        const pointer = try self.aggregatePointer();
        try self.print(" blit %v{d}, %v{d}, {d}\n", .{ address, pointer, (try self.layout(read.element)).size });
        try self.store(read.slot, pointer);
    }
}
/// Address of element `index` in a native list-like receiver's backing storage.
/// `storage` is the word at `list_storage_offset` in the header; the stride is
/// the element layout's, so byte strings, lists and inline records share it.
fn elementAddress(comptime E: type, self: *E, list: usize, index: usize, element: typed.Type) Error!usize {
    const header = self.temp();
    const storage = self.temp();
    const offset = self.temp();
    const address = self.temp();
    try self.markObject(list);
    try self.print(" %v{d} =l add %v{d}, {d}\n %v{d} =l loadl %v{d}\n", .{ header, list, list_storage_offset, storage, header });
    try self.markObject(storage);
    const stride = (try self.layout(element)).size;
    if (stride == 1) {
        try self.print(" %v{d} =l add %v{d}, %v{d}\n", .{ address, storage, index });
    } else {
        try self.print(" %v{d} =l mul %v{d}, {d}\n %v{d} =l add %v{d}, %v{d}\n", .{ offset, index, stride, address, storage, offset });
    }
    return address;
}
/// Lower string concatenation, equality, and direct Unicode scalar ordering.
fn emitBinary(comptime E: type, self: *E, op: @FieldType(@FieldType(bytecode.Instruction, "op"), "binary_integer"), stack: []const typed.Type) Error!void {
    const base = stack.len - 2;
    const left = try self.load("s", base);
    const right = try self.load("s", base + 1);
    const result = self.temp();
    if (op.op == .add) {
        const kind = self.program.records[op.ty.recordIndex()].collection.kind;
        if (kind == .bytes) return bytes_lower.Lower(E).concat(self, base);
        if (kind != .string) return self.reject(self.pc);
        try self.print(" %v{d} =l call $myl_native_text_concat(l %heap, l %v{d}, l %v{d})\n", .{ result, left, right });
        try checkedPointer(E, self, result, base);
    } else if (op.op == .lt) {
        if (self.program.records[op.ty.recordIndex()].collection.kind != .string) return self.reject(self.pc);
        const comparison = self.temp();
        try self.print(" %v{d} =w call $myl_native_text_compare(l %v{d}, l %v{d})\n %v{d} =w csltw %v{d}, 0\n", .{ comparison, left, right, result, comparison });
        try boolean(E, self, result, base);
    } else if (op.op == .eq or op.op == .ne) {
        const left_pointer = try operandPointer(E, self, op.ty, base);
        const right_pointer = try operandPointer(E, self, op.ty, base + 1);
        try self.print(" %v{d} =w call $myl_native_equal(l ${s}, l %v{d}, l %v{d})\n", .{ result, try self.descriptor(op.ty), left_pointer, right_pointer });
        try equalResult(E, self, result);
        if (op.op == .ne) {
            const inverse = self.temp();
            try self.print(" %v{d} =w ceqw %v{d}, 0\n", .{ inverse, result });
            try boolean(E, self, inverse, base);
        } else try boolean(E, self, result, base);
    } else return self.reject(self.pc);
}

fn textOperation(comptime E: type, self: *E, op: BufferOperation, stack: []const typed.Type) Error!void {
    const base = stack.len - op.kind.arity();
    const input = try self.load("l", @backingInt(op.owner));
    const result = self.temp();
    switch (op.kind) {
        .length => {
            try self.print(load_word, .{ result, input });
            try self.store(base, result);
        },
        .read => {
            const at = try self.load("s", base);
            try textAt(E, self, input, at, stack[base], result, base);
        },
        // Text shares the list header, so iteration reads its scalar count too.
        .iteration_check => {
            const expected = try self.load("s", base);
            const actual = self.temp();
            try self.print(" %v{d} =l loadl %v{d}\n %v{d} =l ceql %v{d}, %v{d}\n", .{ actual, input, result, actual, expected });
            try self.require(result, iteration_failure);
            try self.print(store_unit, .{base});
        },
        .slice => {
            const start = try self.load("s", base);
            const end = try self.load("s", base + 1);
            try self.print(" %v{d} =l call $myl_native_text_slice(l %heap, l %v{d}, l %v{d}, l %v{d})\n", .{ result, input, start, end });
            try checkedPointer(E, self, result, base);
        },
        .slice_step => try textStep(E, self, base, input),
        .split, .join => {
            const argument = try self.load("s", base);
            if (op.kind == .split) {
                const separator_length = self.temp();
                try self.print(load_word, .{ separator_length, argument });
                try self.require(separator_length, "myl_qbe_fail_empty_separator");
            }
            try self.print(" %v{d} =l call ${s}(l %heap, l %v{d}, l %v{d})\n", .{ result, if (op.kind == .split) "myl_native_text_split" else "myl_native_text_join", input, argument });
            try checkedPointer(E, self, result, base);
        },
        .contains => {
            const needle = try self.load("s", base);
            try self.print(" %v{d} =w call $myl_native_text_contains(l %v{d}, l %v{d})\n", .{ result, input, needle });
            try boolean(E, self, result, base);
        },
        .encode, .from_hex => return bytes_lower.Lower(E).textual(self, op, stack),
        // The Python string methods and the number grammar lower on their own.
        else => return text_lower.Lower(E).operation(self, op, stack),
    }
}
fn dictionaryOperation(comptime E: type, self: *E, op: BufferOperation, stack: []const typed.Type) Error!void {
    const schema = self.program.records[self.function.scope.locals[@backingInt(op.owner)].ty.recordIndex()];
    const base = stack.len - op.kind.arity();
    const input = try self.load("l", @backingInt(op.owner));
    const result = self.temp();
    switch (op.kind) {
        .length => {
            try self.print(dictionary_length, .{ result, input });
            try self.store(base, result);
        },
        .iteration_check => {
            const actual = self.temp();
            const expected = try self.load("s", base);
            try self.print(dictionary_length ++ " %v{d} =l ceql %v{d}, %v{d}\n", .{ actual, input, result, actual, expected });
            try self.require(result, iteration_failure);
            try self.print(store_unit, .{base});
        },
        .keys, .values => {
            try self.print(" %v{d} =l call $myl_native_dictionary_snapshot(l %heap, l %v{d}, w {d})\n", .{ result, input, @intFromBool(op.kind == .keys) });
            try checkedPointer(E, self, result, base);
        },
        .key_at, .value_at => {
            const at = try self.load("s", base);
            const length = self.temp();
            try self.print(dictionary_length, .{ length, input });
            const operation = if (op.kind == .key_at) "key_at" else "value_at";
            try self.print(" %v{d} =w call $myl_native_dictionary_{s}(l %v{d}, l %v{d}, l %agg{d})\n", .{ result, operation, input, at, self.pc });
            try requireIndexBounds(E, self, result, at, length, index_failure);
            try self.store(base, try self.readValue(try self.aggregatePointer(), op.output));
        },
        .read, .get, .contains, .write => {
            const key = try operandPointer(E, self, schema.collection.key.?, base);
            if (op.kind == .contains) {
                try self.print(" %v{d} =w call $myl_native_dictionary_contains(l %v{d}, l %v{d})\n", .{ result, input, key });
                try boolean(E, self, result, base);
            } else if (op.kind == .write) {
                const value = try operandPointer(E, self, schema.shape.buffer.?, base + 1);
                try arena_lower.Lower(E).barrier(self, input, schema.collection.key.?, key);
                try arena_lower.Lower(E).barrier(self, input, schema.shape.buffer.?, value);
                try self.print(dictionary_write, .{ result, input, key, value });
                try self.require(result, allocation_failure);
                try self.print(store_unit, .{base});
            } else {
                try self.print(" %v{d} =w call $myl_native_dictionary_read(l %v{d}, l %v{d}, l %agg{d})\n", .{ result, input, key, self.pc });
                if (op.kind == .get) {
                    const label = self.temp();
                    try self.print(" jnz %v{d}, @found{d}, @missing{d}\n@found{d}\n", .{ result, label, label, label });
                    try self.store(base, try self.readValue(try self.aggregatePointer(), op.output));
                    try self.print(" jmp @got{d}\n@missing{d}\n", .{ label, label });
                    try self.store(base, try self.load("s", base + 1));
                    try self.print(" jmp @got{d}\n@got{d}\n", .{ label, label });
                } else {
                    try self.require(result, missing_key_failure);
                    try self.store(base, try self.readValue(try self.aggregatePointer(), op.output));
                }
            }
        },
        .items => {
            try self.print(" %v{d} =l call $myl_native_dictionary_snapshot(l %heap, l %v{d}, w 0)\n", .{ result, input });
            try checkedPointer(E, self, result, base);
        },
        .pop_key, .pop_default => {
            const key = try operandPointer(E, self, schema.collection.key.?, base);
            const pointer = try self.aggregatePointer();
            try self.print(" %v{d} =w call $myl_native_dictionary_pop(l %v{d}, l %v{d}, l %agg{d})\n", .{ result, input, key, self.pc });
            if (op.kind == .pop_key) {
                try self.require(result, missing_key_failure);
                try self.store(base, try self.readValue(pointer, op.output));
            } else {
                const label = self.temp();
                try self.print(" jnz %v{d}, @found{d}, @missing{d}\n@found{d}\n", .{ result, label, label, label });
                try self.store(base, try self.readValue(pointer, op.output));
                try self.print(" jmp @got{d}\n@missing{d}\n", .{ label, label });
                try self.store(base, try self.load("s", base + 1));
                try self.print(" jmp @got{d}\n@got{d}\n", .{ label, label });
            }
        },
        .update => {
            const other = try self.load("s", base);
            try self.print(" %v{d} =w call $myl_native_dictionary_update(l %heap, l %v{d}, l %v{d})\n", .{ result, input, other });
            try self.require(result, allocation_failure);
            try self.print(store_unit, .{base});
        },
        .setdefault => {
            const key = try operandPointer(E, self, schema.collection.key.?, base);
            const fallback = try operandPointer(E, self, schema.shape.buffer.?, base + 1);
            const pointer = try self.aggregatePointer();
            try self.print(" %v{d} =w call $myl_native_dictionary_setdefault(l %heap, l %v{d}, l %v{d}, l %v{d}, l %agg{d})\n", .{ result, input, key, fallback, self.pc });
            try self.require(result, allocation_failure);
            try self.store(base, try self.readValue(pointer, op.output));
        },
        .clear => {
            try self.print(" call $myl_native_dictionary_clear(l %v{d})\n", .{input});
            try self.print(store_unit, .{base});
        },
        .copy => {
            const copy = self.temp();
            try self.print(" %v{d} =l call $myl_native_dictionary_copy(l %heap, l %v{d})\n", .{ copy, input });
            try checkedPointer(E, self, copy, base);
        },
        else => return self.reject(self.pc),
    }
}

fn textAt(comptime E: type, self: *E, input: usize, at: usize, ty: typed.Type, result: usize, base: usize) Error!void {
    const size = self.temp();
    try self.print(load_pointer, .{ size, input });
    const normalized = try normalizedIndex(E, self, at, size, ty);
    // QBE-UNCHECKED-1: keep the negative-index normalization, which produces the
    // offset the read uses, and drop only its range test and cold block.
    if (self.checks) {
        const valid = self.temp();
        try self.print(" %v{d} =l cultl %v{d}, %v{d}\n", .{ valid, normalized, size });
        try requireIndexBounds(E, self, valid, at, size, "myl_qbe_fail_text_bounds_detail");
    }
    try self.print(" %v{d} =l call $myl_native_text_at(l %heap, l %v{d}, l %v{d})\n", .{ result, input, normalized });
    try checkedPointer(E, self, result, base);
}

fn equalResult(comptime E: type, self: *E, result: usize) Error!void {
    const valid = self.temp();
    const label = self.temp();
    try self.print(
        " %v{d} =w csgew %v{d}, 0\n jnz %v{d}, @equalok{d}, @equalerror{d}\n@equalerror{d}\n call $myl_qbe_fail_equality(l %ctx, w %v{d})\n" ++
            " jmp @failure\n@equalok{d}\n",
        .{ valid, result, valid, label, label, label, result, label },
    );
}

fn emitCast(comptime E: type, self: *E, ty: typed.Type, stack: []const typed.Type) Error!void {
    const collection = self.program.records[ty.recordIndex()].collection.kind;
    if (collection == .bytes) {
        const base = stack.len - 1;
        const input_type = stack[base];
        // A byte-kind input is already one-byte storage, so the conversion copies
        // its current octets instead of widening a `list[int]` element by element.
        if (input_type.isAggregate() and self.program.records[input_type.recordIndex()].collection.kind == .bytes)
            return bytes_lower.Lower(E).copyImmutable(self, stack);
        return bytes_lower.Lower(E).fromList(self, stack);
    }
    if (collection != .string) return self.reject(self.pc);
    const base = stack.len - 1;
    const input_type = stack[base];
    if (input_type == ty) return;
    // A list, dictionary, record, variant or byte string renders through the
    // renderer `print` uses, so one value has one spelling either way.
    if (render.rendersConversion(self.program.records, ty, input_type)) return io_lower.Lower(E).text(self, input_type, base);
    const kind: u32 = if (input_type.integer()) |info| (if (info.signed) @as(u32, 0) else 1) else switch (input_type) {
        .bool => 2,
        .unit => 3,
        else => if (@import("numeric_surface.zig").isFloat(input_type, self.program.records)) 4 else return self.reject(self.pc),
    };
    const input = try self.load("s", base);
    const result = self.temp();
    try self.print(" %v{d} =l call $myl_native_text_scalar(l %heap, l %v{d}, w {d})\n", .{ result, input, kind });
    try checkedPointer(E, self, result, base);
}
