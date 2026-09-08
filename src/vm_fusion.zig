//! Execution-local superinstructions preserve the original bytecode and source PCs.
const std = @import("std");
const bc = @import("bytecode.zig");
const typed = @import("typed.zig");
/// Scalar input known from the checked instruction stream.
pub const Operand = union(enum(u8)) { local: typed.LocalId, constant: i64 };
/// Checked i64 operation or an unchanged index operand.
pub const Arithmetic = enum(u8) { identity, add, sub, mul, div, rem };
/// Original instructions represented by an execution-local plan entry.
pub const Kind = enum(u8) {
    none,
    copy,
    copy_pair,
    binary,
    binary_chain,
    binary_store,
    compare,
    compare_jump,
    compare_return,
    return_value,
    index,
    scalar_call,
    scalar_return,
    scalar_load,
    scalar_store,
    stack_binary,
    stack_binary_store,
    stack_binary_return,
    stack_compare,
    jump,
    branch,
    binary_compare,
    binary_compare_jump,
    arguments_call,
    binary_call,
};
/// A plan starts at an original PC and never removes interior entry points.
pub const Entry = struct {
    inputs: struct { left: Operand = .{ .constant = 0 }, right: Operand = .{ .constant = 0 }, third: Operand = .{ .constant = 0 } } = .{},
    destination: usize = 0,
    successor: usize = 0,
    ty: typed.Type = .i64,
    operation: struct {
        arithmetic: Arithmetic = .identity,
        next_arithmetic: Arithmetic = .identity,
        predicate: bc.Predicate = .eq,
        offset: u8 = 0,
        scalar_function: bool = false,
        tail_jump: bool = false,
        second_destination: usize = 0,
    } = .{},
    kind: Kind = .none,
    cost: u8 = 0,
};
/// Bounded execution-local metadata; collisions only cause re-matching.
/// The host stack holds 128 entries, independent of guest code or frame count.
pub const Plan = struct {
    const capacity = 128;
    keys: [capacity]?*const bc.Function = @splat(null),
    pcs: [capacity]usize = undefined,
    entries: [capacity]Entry = undefined,
    enabled: bool,
    /// Look up by original instruction identity, including interior entry points.
    pub inline fn get(self: *Plan, program: bc.Program, function: *const bc.Function, cache_offset: usize, pc: usize) *const Entry {
        const slot = (pc +% cache_offset) % capacity;
        if (self.keys[slot] != function or self.pcs[slot] != pc) self.fill(program, function, pc, slot);
        return &self.entries[slot];
    }
    noinline fn fill(self: *Plan, program: bc.Program, function: *const bc.Function, pc: usize, slot: usize) void {
        var entry = match(program, function.*, pc);
        const next = pc + entry.cost;
        if ((entry.kind == .copy or entry.kind == .copy_pair or entry.kind == .binary_store) and next < function.scope.instructions.len) {
            if (function.scope.instructions[next].op == .jump) {
                entry.operation.tail_jump = true;
                entry.successor = function.scope.instructions[next].op.jump;
                entry.cost += 1;
            }
        }
        self.entries[slot] = entry;
        self.keys[slot] = function;
        self.pcs[slot] = pc;
    }
};
fn operand(function: bc.Function, pc: usize, ty: typed.Type) ?Operand {
    const code = function.scope.instructions;
    if (pc >= code.len) return null;
    return switch (code[pc].op) {
        .load_local => |slot| if (function.scope.locals[@backingInt(slot)].ty == ty) .{ .local = slot } else null,
        .push_i64 => |value| if (ty == .i64) .{ .constant = value } else null,
        .push_bool => |value| if (ty == .bool) .{ .constant = @intFromBool(value) } else null,
        else => null,
    };
}
fn arithmetic(instruction: bc.Instruction) ?Arithmetic {
    return switch (instruction.op) {
        .add_i64_checked => .add,
        .sub_i64_checked => .sub,
        .mul_i64_checked => .mul,
        .div_i64_checked => .div,
        .rem_i64_checked => .rem,
        else => null,
    };
}
fn match(program: bc.Program, function: bc.Function, pc: usize) Entry {
    const code = function.scope.instructions;
    if (code[pc].op == .call) {
        const id = code[pc].op.call;
        if (scalarFunction(program.functions[@backingInt(id)])) return .{ .kind = .scalar_call, .cost = 1, .destination = @backingInt(id) };
    }
    if (code[pc].op == .ret and scalarFunction(function)) return .{ .kind = .scalar_return, .cost = 1, .ty = function.signature.return_type };
    if (index(program, function, pc)) |entry| return entry;
    if (argumentCall(program, function, pc)) |entry| return entry;
    if (pc + 1 >= code.len) return single(function, pc);
    inline for (.{ typed.Type.i64, typed.Type.bool }) |ty| {
        if (operand(function, pc, ty)) |left| {
            if (code[pc + 1].op == .store_local) {
                const slot = code[pc + 1].op.store_local;
                if (function.scope.locals[@backingInt(slot)].ty == ty) return copySequence(function, pc, left, ty, slot);
            }
            if (code[pc + 1].op == .ret and function.signature.return_type == ty) return .{ .kind = .return_value, .cost = 2, .inputs = .{ .left = left }, .ty = ty, .operation = .{ .scalar_function = scalarFunction(function) } };
        }
    }
    if (pc + 2 >= code.len) return single(function, pc);
    const left = operand(function, pc, .i64) orelse return single(function, pc);
    const right = operand(function, pc + 1, .i64) orelse return single(function, pc);
    if (arithmetic(code[pc + 2])) |op| {
        var entry: Entry = .{ .kind = .binary, .cost = 3, .inputs = .{ .left = left, .right = right }, .operation = .{ .arithmetic = op, .offset = 2 } };
        if (arithmeticChain(function, pc, entry)) |chained| return chained;
        if (pc + 3 < code.len and code[pc + 3].op == .store_local) {
            const slot = code[pc + 3].op.store_local;
            if (function.scope.locals[@backingInt(slot)].ty == .i64) {
                entry.kind = .binary_store;
                entry.cost = 4;
                entry.destination = @backingInt(slot);
            }
        }
        if (pc + 3 < code.len and code[pc + 3].op == .call) {
            const id = code[pc + 3].op.call;
            if (integerCall(program.functions[@backingInt(id)], 1)) {
                entry.kind = .binary_call;
                entry.cost = 4;
                entry.destination = @backingInt(id);
            }
        }
        if (pc + 4 < code.len and code[pc + 4].op == .cmp_i64) {
            if (operand(function, pc + 3, .i64)) |third| {
                entry.inputs.third = third;
                entry.kind = .binary_compare;
                entry.cost = 5;
                entry.operation.predicate = code[pc + 4].op.cmp_i64;
                if (pc + 5 < code.len and code[pc + 5].op == .jump_if_false) {
                    entry.kind = .binary_compare_jump;
                    entry.cost = 6;
                    entry.destination = code[pc + 5].op.jump_if_false;
                }
            }
        }
        return entry;
    }
    if (code[pc + 2].op == .cmp_i64) {
        var entry: Entry = .{ .kind = .compare, .cost = 3, .inputs = .{ .left = left, .right = right }, .operation = .{ .predicate = code[pc + 2].op.cmp_i64 } };
        if (pc + 3 < code.len and code[pc + 3].op == .jump_if_false) {
            entry.kind = .compare_jump;
            entry.cost = 4;
            entry.destination = code[pc + 3].op.jump_if_false;
            if (pc + 5 < code.len and code[pc + 5].op == .ret and scalarFunction(function)) {
                if (operand(function, pc + 4, function.signature.return_type)) |returned| {
                    entry.kind = .compare_return;
                    entry.cost = 6;
                    entry.ty = function.signature.return_type;
                    entry.inputs.third = returned;
                }
            }
        }
        return entry;
    }
    return single(function, pc);
}
fn arithmeticChain(function: bc.Function, pc: usize, first: Entry) ?Entry {
    const code = function.scope.instructions;
    if (pc + 4 >= code.len) return null;
    const next = arithmetic(code[pc + 4]) orelse return null;
    const third = operand(function, pc + 3, .i64) orelse return null;
    var entry = first;
    entry.kind = .binary_chain;
    entry.cost = 5;
    entry.inputs.third = third;
    entry.operation.next_arithmetic = next;
    return entry;
}
fn copySequence(function: bc.Function, pc: usize, left: Operand, ty: typed.Type, slot: typed.LocalId) Entry {
    var entry: Entry = .{ .kind = .copy, .cost = 2, .inputs = .{ .left = left }, .ty = ty, .destination = @backingInt(slot) };
    const code = function.scope.instructions;
    if (pc + 3 >= code.len or code[pc + 3].op != .store_local) return entry;
    const second = code[pc + 3].op.store_local;
    if (function.scope.locals[@backingInt(second)].ty != ty) return entry;
    const right = operand(function, pc + 2, ty) orelse return entry;
    entry.kind = .copy_pair;
    entry.cost = 4;
    entry.inputs.right = right;
    entry.operation.second_destination = @backingInt(second);
    return entry;
}
fn integerCall(function: bc.Function, count: usize) bool {
    if (function.signature.parameter_count != count or !scalarFunction(function)) return false;
    for (function.scope.locals[0..count]) |parameter| if (parameter.ty != .i64) return false;
    return true;
}
fn argumentCall(program: bc.Program, function: bc.Function, pc: usize) ?Entry {
    const code = function.scope.instructions;
    const left = operand(function, pc, .i64) orelse return null;
    inline for (.{ 1, 2 }) |count| {
        if (pc + count < code.len and code[pc + count].op == .call) {
            const id = code[pc + count].op.call;
            if (integerCall(program.functions[@backingInt(id)], count)) {
                const right: Operand = if (count == 2) operand(function, pc + 1, .i64) orelse return null else .{ .constant = 0 };
                return .{ .kind = .arguments_call, .cost = count + 1, .inputs = .{ .left = left, .right = right }, .destination = @backingInt(id) };
            }
        }
    }
    return null;
}
fn single(function: bc.Function, pc: usize) Entry {
    const instruction = function.scope.instructions[pc];
    inline for (.{ typed.Type.i64, typed.Type.bool }) |ty| {
        if (operand(function, pc, ty)) |input| return .{ .kind = .scalar_load, .cost = 1, .inputs = .{ .left = input }, .ty = ty };
        if (instruction.op == .store_local) {
            const slot = instruction.op.store_local;
            if (function.scope.locals[@backingInt(slot)].ty == ty) return .{ .kind = .scalar_store, .cost = 1, .destination = @backingInt(slot), .ty = ty };
        }
    }
    if (arithmetic(instruction)) |op| {
        var entry: Entry = .{ .kind = .stack_binary, .cost = 1, .operation = .{ .arithmetic = op } };
        const code = function.scope.instructions;
        if (pc + 1 < code.len) {
            if (code[pc + 1].op == .ret and function.signature.return_type == .i64 and scalarFunction(function)) {
                entry.kind = .stack_binary_return;
                entry.cost = 2;
            } else if (code[pc + 1].op == .store_local) {
                const slot = code[pc + 1].op.store_local;
                if (function.scope.locals[@backingInt(slot)].ty == .i64) {
                    entry.kind = .stack_binary_store;
                    entry.cost = 2;
                    entry.destination = @backingInt(slot);
                }
            }
        }
        return entry;
    }
    if (instruction.op == .cmp_i64) return .{ .kind = .stack_compare, .cost = 1, .operation = .{ .predicate = instruction.op.cmp_i64 } };
    if (instruction.op == .jump) return .{ .kind = .jump, .cost = 1, .destination = instruction.op.jump };
    if (instruction.op == .jump_if_false) return .{ .kind = .branch, .cost = 1, .destination = instruction.op.jump_if_false };
    return .{};
}
fn scalarFunction(function: bc.Function) bool {
    if (function.policy.host != null or function.scope.references.len != 0 or function.signature.return_reference != null) return false;
    if (function.signature.return_type != .i64 and function.signature.return_type != .bool) return false;
    for (function.scope.locals) |local| {
        if (local.ty != .i64 and local.ty != .bool) return false;
        if (local.parameter.reference_parameter != null) return false;
    }
    return true;
}
fn index(program: bc.Program, function: bc.Function, pc: usize) ?Entry {
    const code = function.scope.instructions;
    if (pc + 2 >= code.len or code[pc].op != .load_local) return null;
    const slot = code[pc].op.load_local;
    const ty = function.scope.locals[@backingInt(slot)].ty;
    if (!ty.isAggregate() or typed.moveOnly(ty, program.records)) return null;
    const schema = program.records[ty.recordIndex()].shape.array orelse return null;
    if (schema.element != .i64 or schema.key != null) return null;
    const left = operand(function, pc + 1, .i64) orelse return null;
    var entry: Entry = .{ .kind = .index, .cost = 3, .inputs = .{ .left = left }, .destination = @backingInt(slot), .ty = ty };
    if (code[pc + 2].op == .get_index and code[pc + 2].op.get_index == ty) return entry;
    if (pc + 4 >= code.len or code[pc + 4].op != .get_index or code[pc + 4].op.get_index != ty) return null;
    entry.inputs.right = operand(function, pc + 2, .i64) orelse return null;
    entry.operation.arithmetic = arithmetic(code[pc + 3]) orelse return null;
    entry.operation.offset = 3;
    entry.cost = 5;
    return entry;
}
/// Evaluate precisely the checked i64 semantics used by ordinary handlers.
pub inline fn evaluate(op: Arithmetic, left: i64, right: i64) error{ Overflow, DivisionByZero }!i64 {
    switch (op) {
        .identity => return left,
        .add, .sub, .mul => {
            const result = switch (op) {
                .add => @addWithOverflow(left, right),
                .sub => @subWithOverflow(left, right),
                .mul => @mulWithOverflow(left, right),
                else => unreachable,
            };
            if (result[1] != 0) return error.Overflow;
            return result[0];
        },
        .div, .rem => {
            if (right == 0) return error.DivisionByZero;
            if (left == std.math.minInt(i64) and right == -1) return if (op == .rem) 0 else error.Overflow;
            return if (op == .div) @divTrunc(left, right) else @rem(left, right);
        },
    }
}
/// Scalar predicate on already checked i64 inputs.
pub inline fn compare(predicate: bc.Predicate, left: i64, right: i64) bool {
    return switch (predicate) {
        .eq => left == right,
        .ne => left != right,
        .lt => left < right,
        .le => left <= right,
        .gt => left > right,
        .ge => left >= right,
    };
}
