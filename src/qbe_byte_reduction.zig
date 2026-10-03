//! Exact bulk reduction of a certified immutable byte iteration.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const facts = @import("qbe_loop_facts.zig");
const reads = @import("qbe_rc_read_version.zig");
const Op = @FieldType(bytecode.Instruction, "op");

/// The unchanged loop-carried locals and the sole read to replace.
pub const Certificate = struct {
    counter: usize,
    bound: usize,
    owner: usize,
    total: usize,
    element: usize,
    mask: union(enum) { zero, local: usize, literal: i64 },
    read: usize,
};

/// Recognize a complete canonical byte sum, independently of source names.
pub fn shape(code: []const bytecode.Instruction, head: usize, back: usize) ?Certificate {
    if (back >= code.len or back < head or (back - head != 22 and back - head != 24)) return null;
    const body = code[head .. back + 1];
    const counter = local(body[0].op, .load_local) orelse return null;
    const bound = local(body[1].op, .load_local) orelse return null;
    if (body[2].op != .cmp_i64 or body[2].op.cmp_i64 != .lt) return null;
    if (body[3].op != .jump_if_false or body[3].op.jump_if_false != back + 1) return null;
    const read = body[8].op;
    if (read != .buffer_operation or read.buffer_operation.kind != .read or read.buffer_operation.output != .u8) return null;
    const owner = @backingInt(read.buffer_operation.owner);
    if (!load(body[4].op, bound) or !iteration(body[5].op, owner)) return null;
    if (body[6].op != .pop) return null;
    if (!load(body[7].op, counter) or body[9].op != .cast_integer) return null;
    if (body[9].op.cast_integer != .i64) return null;
    const element = local(body[10].op, .store_local) orelse return null;
    const total = local(body[11].op, .load_local) orelse return null;
    if (!load(body[12].op, element)) return null;
    var mask: @FieldType(Certificate, "mask") = .zero;
    const add: usize = if (body.len == 25) 15 else 13;
    if (body.len == 25) {
        mask = switch (body[13].op) {
            .load_local => |slot| .{ .local = @backingInt(slot) },
            .push_i64 => |value| .{ .literal = value },
            else => return null,
        };
        if (body[14].op != .binary_integer or body[14].op.binary_integer.ty != .i64 or body[14].op.binary_integer.op != .bit_xor) return null;
    }
    if (body[add].op != .add_i64_checked or !store(body[add + 1].op, total)) return null;
    if (!load(body[add + 2].op, bound) or !iteration(body[add + 3].op, owner)) return null;
    if (body[add + 4].op != .pop) return null;
    if (!load(body[add + 5].op, counter) or body[add + 6].op != .push_i64) return null;
    if (body[add + 6].op.push_i64 != 1) return null;
    if (body[add + 7].op != .add_i64_checked or !store(body[add + 8].op, counter)) return null;
    if (body[add + 9].op != .jump or body[add + 9].op.jump != head) return null;
    const slots = [_]usize{ counter, bound, owner, total, element };
    for (slots, 0..) |slot, index| {
        for (slots[0..index]) |previous| if (slot == previous) return null;
        if (mask == .local and mask.local == slot) return null;
    }
    return .{ .counter = counter, .bound = bound, .owner = owner, .total = total, .element = element, .mask = mask, .read = head + 8 };
}

fn local(op: Op, comptime tag: std.meta.Tag(Op)) ?usize {
    return if (op == tag) @backingInt(@field(op, @tagName(tag))) else null;
}
fn load(op: Op, slot: usize) bool {
    return local(op, .load_local) == slot;
}
fn store(op: Op, slot: usize) bool {
    return local(op, .store_local) == slot;
}
fn iteration(op: Op, owner: usize) bool {
    return op == .buffer_operation and op.buffer_operation.kind == .iteration_check and
        @backingInt(op.buffer_operation.owner) == owner and op.buffer_operation.output == .unit;
}

/// Add physical, lifetime and range evidence to a recognized byte reduction.
pub fn certify(comptime E: type, self: *E, loop: *const facts.Loop, proof: ?reads.Certificate) ?Certificate {
    if (proof == null or self.step_checks or self.frame_checks) return null;
    const result = shape(self.function.scope.instructions, loop.head, loop.back) orelse return null;
    const locals = self.function.scope.locals;
    const ty = locals[result.owner].ty;
    if (!ty.isAggregate() or !typed.isByteString(self.program.records[ty.recordIndex()])) return null;
    const read = loop.actions[result.read - loop.head];
    if (!read.unchecked or read.receiver == null or read.value != null) return null;
    for ([_]usize{ result.counter, result.bound, result.total, result.element }) |slot| {
        if (locals[slot].ty != .i64 or self.byReference(slot) or self.callerStorage(slot) or self.moves.aliased(slot)) return null;
    }
    if (result.mask == .local) {
        const slot = result.mask.local;
        if (locals[slot].ty != .i64 or self.byReference(slot) or self.callerStorage(slot) or self.moves.aliased(slot)) return null;
    }
    const exit = self.states[loop.back + 1] orelse return null;
    if (exit.len != 0) return null;
    for (loop.head + 1..loop.back + 1) |pc| if (self.isBranchTarget(pc) or self.range_keys.role(pc) != .none) return null;
    return result;
}

/// Replace only a proven complete reduction; failed numeric guards use the original.
pub fn emit(comptime E: type, self: *E, loop: *const facts.Loop, proof: Certificate, storage: usize) reads.Error!void {
    const counter = try self.load("l", proof.counter);
    const bound = try self.load("l", proof.bound);
    const seed = try self.load("l", proof.total);
    const mask = switch (proof.mask) {
        .local => |slot| try self.load("l", slot),
        .zero, .literal => blk: {
            const value = self.temp();
            try self.print(" %v{d} =l copy {d}\n", .{ value, if (proof.mask == .literal) proof.mask.literal else @as(i64, 0) });
            break :blk value;
        },
    };
    const count = self.temp();
    const flag = self.temp();
    try self.print(" # QBE-BYTE-REDUCTION-1\n %v{d} =l sub %v{d}, %v{d}\n %v{d} =l culel %v{d}, 255\n", .{ count, bound, counter, flag, mask });
    try guard(E, self, flag, loop.head);
    const room = self.temp();
    const positive = self.temp();
    try self.print(" %v{d} =l culel %v{d}, {d}\n", .{ room, count, @divFloor(std.math.maxInt(i64), 255) });
    try self.print(" %v{d} =l csgtl %v{d}, 0\n %v{d} =l and %v{d}, %v{d}\n", .{ positive, count, room, room, positive });
    try guard(E, self, room, loop.head);
    const maximum = self.temp();
    const limit = self.temp();
    const safe = self.temp();
    try self.print(" %v{d} =l mul %v{d}, 255\n %v{d} =l sub {d}, %v{d}\n %v{d} =l cslel %v{d}, %v{d}\n", .{ maximum, count, limit, std.math.maxInt(i64), maximum, safe, seed, limit });
    try guard(E, self, safe, loop.head);
    const start = self.temp();
    const sum = self.temp();
    const total = self.temp();
    const last = self.temp();
    const address = self.temp();
    const element = self.temp();
    try self.print(" %v{d} =l add %v{d}, %v{d}\n %v{d} =l call $myl_native_bytes_sum_xor(l %v{d}, l %v{d}, l %v{d})\n", .{ start, storage, counter, sum, start, count, mask });
    try self.print(" %v{d} =l add %v{d}, %v{d}\n %v{d} =l sub %v{d}, 1\n %v{d} =l add %v{d}, %v{d}\n %v{d} =l loadub %v{d}\n", .{ total, seed, sum, last, bound, address, storage, last, element, address });
    try self.print(" storel %v{d}, %l{d}\n storel %v{d}, %l{d}\n storel %v{d}, %l{d}\n jmp @i{d}\n", .{ total, proof.total, bound, proof.counter, element, proof.element, loop.back + 1 });
}
fn guard(comptime E: type, self: *E, flag: usize, head: usize) reads.Error!void {
    try self.print(" jnz %v{d}, @byteguard{d}, @oi{d}\n@byteguard{d}\n", .{ flag, flag, head, flag });
}
