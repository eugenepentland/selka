//! QBE lowering of the Python string methods and the pinned number grammar.
//! Every method calls the immutable native text runtime, so the receiver and each
//! alias stay untouched, and `int(text)`/`float(text)` reach the same Zig grammar
//! the VM uses rather than a second parser that could drift from it.
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const prelude = @import("prelude.zig");
/// Failures reported while emitting native text-method instructions.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
const BufferOperation = @FieldType(@FieldType(bytecode.Instruction, "op"), "buffer_operation");
const Kind = @import("buffer_operations.zig").Kind;
const allocation_failure = @import("qbe_format.zig").allocation_failure;
const load_word = @import("qbe_format.zig").load_word;
const empty_separator = "myl_qbe_fail_empty_separator";

/// Bind text-method lowering to the concrete emitter without an import cycle.
pub fn Lower(comptime E: type) type {
    return struct {
        /// Lower one Python string method or number parse onto the native runtime.
        pub fn operation(self: *E, op: BufferOperation, stack: []const typed.Type) Error!void {
            return emitOperation(E, self, op, stack);
        }
    };
}

fn emitOperation(comptime E: type, self: *E, op: BufferOperation, stack: []const typed.Type) Error!void {
    const base = stack.len - op.kind.arity();
    const input = try self.load("l", @backingInt(op.owner));
    switch (op.kind) {
        .strip, .lstrip, .rstrip, .upper, .lower, .splitlines => return emitFresh(E, self, op, input, base),
        .is_digit, .is_alpha, .is_space => return emitClass(E, self, op, input, base),
        .starts_with, .ends_with => return emitEdge(E, self, op, input, base),
        .find, .count => return emitSearch(E, self, op, input, base),
        .replace => return emitReplace(E, self, input, base),
        .zfill => return emitPad(E, self, input, base),
        .parse_int, .parse_float => return emitParse(E, self, op, input, base),
        else => return self.reject(self.pc),
    }
}

/// Lower a method whose answer is a fresh value built from the whole receiver.
fn emitFresh(comptime E: type, self: *E, op: BufferOperation, input: usize, base: usize) Error!void {
    const result = self.temp();
    switch (op.kind) {
        .splitlines => try self.print(" %v{d} =l call $myl_native_text_lines(l %heap, l %v{d})\n", .{ result, input }),
        .upper, .lower => try self.print(" %v{d} =l call $myl_native_text_case(l %heap, l %v{d}, w {d})\n", .{ result, input, @intFromBool(op.kind == .upper) }),
        else => try self.print(" %v{d} =l call $myl_native_text_trim(l %heap, l %v{d}, w {d})\n", .{ result, input, ends(op.kind) }),
    }
    try self.require(result, allocation_failure);
    try self.store(base, result);
}

/// Lower `isdigit`, `isalpha` and `isspace` onto the shared classification pass.
fn emitClass(comptime E: type, self: *E, op: BufferOperation, input: usize, base: usize) Error!void {
    const result = self.temp();
    try self.print(" %v{d} =w call $myl_native_text_every(l %v{d}, w {d})\n", .{ result, input, property(op.kind) });
    return boolean(E, self, result, base);
}

/// Lower `startswith` and `endswith`; an empty affix matches either end.
fn emitEdge(comptime E: type, self: *E, op: BufferOperation, input: usize, base: usize) Error!void {
    const affix = try self.load("s", base);
    const result = self.temp();
    try self.print(" %v{d} =w call $myl_native_text_edge(l %v{d}, l %v{d}, w {d})\n", .{ result, input, affix, @intFromBool(op.kind == .starts_with) });
    return boolean(E, self, result, base);
}

/// Lower `find` and `count`, both of which trap on an empty needle.
fn emitSearch(comptime E: type, self: *E, op: BufferOperation, input: usize, base: usize) Error!void {
    const needle = try self.load("s", base);
    try requireNeedle(E, self, needle);
    const result = self.temp();
    const name = if (op.kind == .find) "myl_native_text_find" else "myl_native_text_count";
    try self.print(" %v{d} =l call ${s}(l %v{d}, l %v{d})\n", .{ result, name, input, needle });
    try self.store(base, result);
}

/// Lower `replace(old, new)` into one freshly allocated string.
fn emitReplace(comptime E: type, self: *E, input: usize, base: usize) Error!void {
    const needle = try self.load("s", base);
    const insert = try self.load("s", base + 1);
    try requireNeedle(E, self, needle);
    const result = self.temp();
    try self.print(" %v{d} =l call $myl_native_text_replace(l %heap, l %v{d}, l %v{d}, l %v{d})\n", .{ result, input, needle, insert });
    try self.require(result, allocation_failure);
    try self.store(base, result);
}

/// Lower `zfill(width)`, which keeps a leading sign in front of its padding.
fn emitPad(comptime E: type, self: *E, input: usize, base: usize) Error!void {
    const width = try self.load("s", base);
    const result = self.temp();
    try self.print(" %v{d} =l call $myl_native_text_zfill(l %heap, l %v{d}, l %v{d})\n", .{ result, input, width });
    try self.require(result, allocation_failure);
    try self.store(base, result);
}

/// Lower `int(text)` and `float(text)` into the shared grammar and an `Option`.
fn emitParse(comptime E: type, self: *E, op: BufferOperation, input: usize, base: usize) Error!void {
    const shape = prelude.optionShape(op.output, self.program.records) orelse return error.InternalError;
    const points = self.temp();
    const count = self.temp();
    const status = self.temp();
    try self.print(" %v{d} =l call $myl_native_text_points(l %v{d})\n", .{ points, input });
    try self.print(load_word, .{ count, input });
    try self.print(" %v{d} =w call $myl_native_number_parse(l %v{d}, l %v{d}, w {d}, l %scratch)\n", .{ status, points, count, @intFromBool(op.kind == .parse_float) });
    const pointer = try self.aggregatePointer();
    const slot = try self.address(pointer, (try self.layout(op.output)).payload_offset);
    const value = self.temp();
    const label = self.temp();
    try self.print(" %v{d} =l loadl %scratch\n", .{value});
    try self.print(" jnz %v{d}, @some{d}, @none{d}\n@some{d}\n storew {d}, %v{d}\n", .{ status, label, label, label, shape.some, pointer });
    try self.writeValue(slot, value, shape.element);
    try self.print(" jmp @parsed{d}\n@none{d}\n storew {d}, %v{d}\n jmp @parsed{d}\n@parsed{d}\n", .{ label, label, shape.none, pointer, label, label });
    try self.store(base, pointer);
}

/// An empty needle traps `R_EMPTY_SEPARATOR` before the runtime is called.
fn requireNeedle(comptime E: type, self: *E, needle: usize) Error!void {
    const length = self.temp();
    try self.print(load_word, .{ length, needle });
    try self.require(length, empty_separator);
}

fn boolean(comptime E: type, self: *E, result: usize, slot: usize) Error!void {
    const extended = self.temp();
    try self.print(" %v{d} =l extuw %v{d}\n", .{ extended, result });
    try self.store(slot, extended);
}

/// The end selector `strip`, `lstrip` and `rstrip` hand the runtime.
fn ends(kind: Kind) u32 {
    return switch (kind) {
        .lstrip => 1,
        .rstrip => 2,
        else => 0,
    };
}

/// The property selector `isdigit`, `isalpha` and `isspace` hand the runtime.
fn property(kind: Kind) u32 {
    return switch (kind) {
        .is_digit => 0,
        .is_alpha => 1,
        else => 2,
    };
}
