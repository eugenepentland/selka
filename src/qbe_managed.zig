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
const allocation_failure = @import("qbe_format.zig").allocation_failure;
const list_value_failure = "myl_qbe_fail_list_value";
const missing_key_failure = "myl_qbe_fail_missing_key";
const numeric_surface = @import("numeric_surface.zig");
const load_word = @import("qbe_format.zig").load_word;
const iteration_failure = "myl_qbe_fail_iteration";
const bytes_lower = @import("qbe_bytes.zig");
const text_lower = @import("qbe_text.zig");
const arena_lower = @import("qbe_arena.zig");
const io_lower = @import("qbe_io.zig");
const render = @import("native_render.zig");
const dictionary_write = " %v{d} =w call $myl_native_dictionary_write(l %heap, l %v{d}, l %v{d}, l %v{d})\n";
const dictionary_length = " %v{d} =l call $myl_native_dictionary_length(l %v{d})\n";
/// Detail-carrying bounds helper shared by indexable receivers.
const index_failure = "myl_qbe_fail_index_bounds";
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
        pub fn construct(self: *E, op: @FieldType(@FieldType(bytecode.Instruction, "op"), "make_record"), stack: []const typed.Type) Error!void {
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
            try self.print(" %v{d} =w call $myl_native_list_get(l %v{d}, l %v{d}, l %agg{d})\n", .{ output, list, index_value, self.pc });
            try requireIndexBounds(E, self, output, index_value, length, normalized_index_failure);
            try self.store(base, try self.readValue(try self.aggregatePointer(), op.output));
        },
        .append, .write => {
            const element = schema.shape.buffer.?;
            const position = h - 1;
            const value_pointer = self.temp();
            if (self.isScalar(element)) try self.print(copy_scratch, .{ value_pointer, position }) else try self.print(load_scratch, .{ value_pointer, position });
            try arena_lower.Lower(E).barrier(self, list, element, value_pointer);
            if (op.kind == .append) {
                try self.print(" %v{d} =w call $myl_native_list_append(l %heap, l %v{d}, l %v{d})\n", .{ output, list, value_pointer });
                try self.require(output, allocation_failure);
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
    const first = try self.load("s", base);
    const last = try self.load("s", base + 1);
    const step = try self.load("s", base + 2);
    const nonzero = self.temp();
    try self.print(" %v{d} =l cnel %v{d}, 0\n", .{ nonzero, step });
    try self.require(nonzero, "myl_qbe_fail_slice_step");
    const result = self.temp();
    try self.print(" %v{d} =l call $myl_native_list_slice_step(l %heap, l %v{d}, l %v{d}, l %v{d}, l %v{d})\n", .{ result, input, first, last, step });
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
fn requireIndexBounds(comptime E: type, self: *E, result: usize, index: usize, length: usize, failure: []const u8) Error!void {
    const label = self.temp();
    try self.print(" jnz %v{d}, @success{d}, @failed{d}\n@failed{d}\n call ${s}(l %ctx, l %v{d}, l %v{d})\n jmp @failure\n@success{d}\n", .{ result, label, label, label, failure, index, length, label });
}
/// Require a pop that has no caller index; report the receiver length only.
fn requirePopBounds(comptime E: type, self: *E, result: usize, length: usize) Error!void {
    const label = self.temp();
    try self.print(" jnz %v{d}, @success{d}, @failed{d}\n@failed{d}\n call $myl_qbe_fail_pop_bounds(l %ctx, l %v{d})\n jmp @failure\n@success{d}\n", .{ result, label, label, label, length, label });
}
/// Load one native list-like header word (length for lists, text and bytes).
fn receiverLength(comptime E: type, self: *E, receiver: usize) Error!usize {
    const length = self.temp();
    try self.print(load_word, .{ length, receiver });
    return length;
}
/// Construct immutable text, an ordinary managed list, or an ordered dictionary.
fn emitConstruct(comptime E: type, self: *E, record: @FieldType(@FieldType(bytecode.Instruction, "op"), "make_record"), stack: []const typed.Type) Error!void {
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
        const element: typed.Type = if (schema.collection.kind == .string) .u32 else schema.shape.buffer.?;
        try self.print(" %v{d} =l call $myl_native_list_new(l %heap, l ${s}, l {d})\n", .{ result, try self.descriptor(element), record.fields });
        try self.require(result, allocation_failure);
        for (0..record.fields) |i| {
            const ok = self.temp();
            const value_pointer = try operandPointer(E, self, element, base + i);
            try self.print(" %v{d} =w call $myl_native_list_append(l %heap, l %v{d}, l %v{d})\n", .{ ok, result, value_pointer });
            try self.require(ok, allocation_failure);
        }
    }
    try self.store(base, result);
}
/// Read Unicode scalar count, list length, or dictionary entry count.
fn emitLength(comptime E: type, self: *E, ty: typed.Type, stack: []const typed.Type) Error!void {
    const base = stack.len - 1;
    const input = try self.load("s", base);
    const result = self.temp();
    if (self.program.records[ty.recordIndex()].collection.kind == .dictionary) {
        try self.print(dictionary_length, .{ result, input });
    } else {
        try self.print(load_word, .{ result, input });
    }
    try self.store(base, result);
}
fn normalizedIndex(comptime E: type, self: *E, owner: usize, index_value: usize, ty: typed.Type) Error!usize {
    if (!ty.integer().?.signed) return index_value;
    const size = self.temp();
    const negative = self.temp();
    const offset = self.temp();
    const chosen = self.temp();
    const label = self.temp();
    try self.print(
        " %v{d} =l loadl %v{d}\n %v{d} =l csltl %v{d}, 0\n jnz %v{d}, @negative{d}, @positive{d}\n@negative{d}\n %v{d} =l add %v{d}, %v{d}\n" ++
            " jmp @index{d}\n@positive{d}\n jmp @index{d}\n@index{d}\n %v{d} =l phi @negative{d} %v{d}, @positive{d} %v{d}\n",
        .{ size, owner, negative, index_value, negative, label, label, label, offset, size, index_value, label, label, label, label, chosen, label, offset, label, index_value },
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
        const at = try normalizedIndex(E, self, input, raw_index, stack[base + 1]);
        const length = try receiverLength(E, self, input);
        if (replacing) {
            const value = try operandPointer(E, self, schema.shape.buffer.?, base + 2);
            try arena_lower.Lower(E).barrier(self, input, schema.shape.buffer.?, value);
            try self.print(" %v{d} =w call $myl_native_list_set(l %v{d}, l %v{d}, l %v{d})\n", .{ result, input, at, value });
            try requireIndexBounds(E, self, result, raw_index, length, index_failure);
            try self.store(base, input);
        } else {
            try self.print(" %v{d} =w call $myl_native_list_get(l %v{d}, l %v{d}, l %agg{d})\n", .{ result, input, at, self.pc });
            try requireIndexBounds(E, self, result, raw_index, length, index_failure);
            try self.store(base, try self.readValue(try self.aggregatePointer(), schema.shape.buffer.?));
        }
    }
}
/// Lower string concatenation and exact Unicode equality.
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
        .slice_step => try steppedSlice(E, self, base, input),
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
        .key_at => {
            const at = try self.load("s", base);
            const length = self.temp();
            try self.print(dictionary_length, .{ length, input });
            try self.print(" %v{d} =w call $myl_native_dictionary_key_at(l %v{d}, l %v{d}, l %agg{d})\n", .{ result, input, at, self.pc });
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
    const normalized = try normalizedIndex(E, self, input, at, ty);
    const size = self.temp();
    const valid = self.temp();
    try self.print(" %v{d} =l loadl %v{d}\n %v{d} =l cultl %v{d}, %v{d}\n", .{ size, input, valid, normalized, size });
    try requireIndexBounds(E, self, valid, at, size, "myl_qbe_fail_text_bounds_detail");
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
    if (collection == .bytes) return bytes_lower.Lower(E).fromList(self, stack);
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
