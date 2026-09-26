//! Where every operand-stack value of one function comes from, for the
//! ownership analysis (`ownership.zig`, `OWNERSHIP-ANALYSIS-1`).
//!
//! The analysis asks one question of an operand: is it a local's value (or a
//! field or element read out of a local), a value no local holds yet (a call's
//! result, a constructor, an allocation), or something it cannot name. The
//! answer is found by simulating the operand stack in program order. A value
//! that reaches an instruction along two edges keeps its source only when both
//! edges agree; an instruction a backward edge enters starts from unknowns.
//! Nothing here depends on how the runtime represents a value.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");

/// The op union every step switches over.
pub const Op = @FieldType(bytecode.Instruction, "op");
/// The absent index or pc.
pub const none: u32 = std.math.maxInt(u32);
/// The one failure the simulation can meet.
pub const Error = error{ InternalError, OutOfMemory };

/// Which part of a local an operand is: the local's own value, an element of
/// the collection it holds, or a field of the record it holds.
pub const Part = enum(u8) { whole, element, field };
/// Whether an operand is a local's value, a value no local holds, or unknown.
pub const Origin = enum(u8) { fresh, local, unknown };

/// The source of one operand.
pub const Source = struct {
    origin: Origin = .unknown,
    /// The local read, when `origin` is `.local`.
    local: u32 = none,
    part: Part = .whole,
    /// The pc of the instruction that read `local`: its load or its element read.
    read: u32 = none,

    /// Whether two sources name the same value.
    pub fn eql(self: Source, other: Source) bool {
        return self.origin == other.origin and self.local == other.local and self.part == other.part and self.read == other.read;
    }
};

/// The simulated operand stack before every instruction, and how many
/// operands each instruction pops.
pub const Sources = struct {
    /// Per instruction, its operands' sources on entry; null where unreachable.
    at: []const ?[]const Source,
    pops: []const u32,
    /// Per instruction, whether a branch names it.
    targets: []const bool,
};

/// Simulate `function`'s operand stack. `states` is the validator's typed stack
/// per instruction; every allocation comes from `a`, an arena.
pub fn simulate(a: std.mem.Allocator, program: bytecode.Program, function: bytecode.Function, states: []const ?[]const typed.Type) Error!Sources {
    const code = function.scope.instructions;
    const at = try a.alloc(?[]const Source, code.len);
    @memset(at, null);
    const pops = try a.alloc(u32, code.len);
    const incoming = try a.alloc(?[]Source, code.len);
    @memset(incoming, null);
    const targets = try a.alloc(bool, code.len);
    const backward = try a.alloc(bool, code.len);
    @memset(targets, false);
    @memset(backward, false);
    for (code, 0..) |instruction, pc| {
        pops[pc] = if (pc < states.len and states[pc] != null) @intCast(popsOf(program, instruction.op)) else 0;
        var buffer: [2]usize = undefined;
        for (branchTargets(instruction.op, &buffer)) |target| if (target < code.len) {
            targets[target] = true;
            if (target <= pc) backward[target] = true;
        };
        if (instruction.op == .switch_variant) for (instruction.op.switch_variant.arms) |arm| if (arm.target < code.len) {
            targets[arm.target] = true;
            if (arm.target <= pc) backward[arm.target] = true;
        };
    }
    var stack: std.ArrayList(Source) = .empty;
    var falls = false;
    for (code, 0..) |instruction, pc| {
        const before = if (pc < states.len) states[pc] else null;
        const entry = before orelse {
            falls = false;
            continue;
        };
        try enter(a, .{ .stack = &stack, .height = entry.len, .falls = falls, .backward = backward[pc], .incoming = incoming[pc] });
        at[pc] = try a.dupe(Source, stack.items);
        const h = stack.items.len;
        if (pops[pc] > h) return error.InternalError;
        const pushed = if (pushes(instruction.op)) pushedSource(program, function, pc, stack.items) else null;
        stack.shrinkRetainingCapacity(h - pops[pc]);
        if (pushed) |value| try stack.append(a, value);
        try leave(a, .{ .states = states, .incoming = incoming, .pc = pc, .op = instruction.op }, stack.items);
        falls = fallsThrough(instruction.op) and pc + 1 < code.len;
    }
    return .{ .at = at, .pops = pops, .targets = targets };
}

/// How control arrives at one instruction.
const Entry = struct {
    stack: *std.ArrayList(Source),
    height: usize,
    falls: bool,
    backward: bool,
    incoming: ?[]Source,
};

/// Settle the simulated stack on entry to an instruction: the fall-through
/// stack merged with every forward branch's, or unknowns under a backward edge.
fn enter(a: std.mem.Allocator, entry: Entry) Error!void {
    const stack = entry.stack;
    if (entry.backward or (!entry.falls and entry.incoming == null)) {
        stack.clearRetainingCapacity();
        for (0..entry.height) |_| try stack.append(a, .{});
        return;
    }
    if (!entry.falls) {
        stack.clearRetainingCapacity();
        try stack.appendSlice(a, entry.incoming.?);
    } else if (stack.items.len != entry.height) {
        stack.clearRetainingCapacity();
        for (0..entry.height) |_| try stack.append(a, .{});
    }
    if (entry.incoming) |other| {
        if (other.len != stack.items.len) {
            for (stack.items) |*slot| slot.* = .{};
        } else for (stack.items, other) |*slot, value| if (!slot.eql(value)) {
            slot.* = .{};
        };
    }
}

/// One instruction's exit: the table of forward-branch stacks, the
/// instruction and its pc.
const Exit = struct {
    states: []const ?[]const typed.Type,
    incoming: []?[]Source,
    pc: usize,
    op: Op,
};

/// Carry the stack after an instruction to every forward branch target it
/// names, merged with what earlier branches carried there.
fn leave(a: std.mem.Allocator, exit: Exit, after: []const Source) Error!void {
    var buffer: [2]usize = undefined;
    for (branchTargets(exit.op, &buffer)) |target| try carry(a, exit, target, after);
    if (exit.op == .switch_variant) for (exit.op.switch_variant.arms) |arm| try carry(a, exit, arm.target, after);
}

fn carry(a: std.mem.Allocator, exit: Exit, target: usize, after: []const Source) Error!void {
    if (target <= exit.pc or target >= exit.incoming.len or target >= exit.states.len) return;
    const expected = exit.states[target] orelse return;
    // A `?` error edge enters its target with the error value alone, not with
    // the stack the success path continues with.
    const matches = after.len == expected.len and exit.op != .try_result;
    const contribution = if (matches) after else &.{};
    if (exit.incoming[target]) |merged| {
        if (!matches or merged.len != expected.len) {
            for (merged) |*slot| slot.* = .{};
            return;
        }
        for (merged, contribution) |*slot, value| if (!slot.eql(value)) {
            slot.* = .{};
        };
        return;
    }
    const fresh = try a.alloc(Source, expected.len);
    if (matches) @memcpy(fresh, contribution) else @memset(fresh, .{});
    exit.incoming[target] = fresh;
}

/// The targets a jump, conditional jump or `?` names, written into `buffer`.
/// A `switch_variant`'s arms are read by the callers directly.
pub fn branchTargets(op: Op, buffer: *[2]usize) []const usize {
    switch (op) {
        .jump, .jump_if_false => |target| {
            buffer[0] = target;
            return buffer[0..1];
        },
        .try_result => |propagate| {
            buffer[0] = propagate.error_target;
            return buffer[0..1];
        },
        else => return buffer[0..0],
    }
}

/// Whether control can fall from this instruction into the next one.
pub fn fallsThrough(op: Op) bool {
    return switch (op) {
        .jump, .ret, .switch_variant => false,
        else => true,
    };
}

/// Whether an instruction leaves a value of its own on the operand stack.
pub fn pushes(op: Op) bool {
    return switch (op) {
        .store_local, .pop, .acknowledge, .jump_if_false, .ret, .assert_true, .drop_local => false,
        .jump, .switch_variant, .begin_arena, .end_arena => false,
        else => true,
    };
}

/// The source of the value the instruction at `pc` pushes, given the sources
/// of the operands on entry to it.
pub fn pushedSource(program: bytecode.Program, function: bytecode.Function, pc: usize, stack: []const Source) Source {
    const h = stack.len;
    const here: u32 = @intCast(pc);
    return switch (function.scope.instructions[pc].op) {
        .load_local, .move_local, .ref_local => |slot| .{ .origin = .local, .local = @intCast(@backingInt(slot)), .read = here },
        // A value-semantics copy is the transfer of the value below it, which
        // `ownership_values.zig` classifies from that value's own source.
        .wrap_domain, .unwrap_domain, .value_copy => if (h > 0) stack[h - 1] else .{},
        .get_field, .try_result => if (h > 0) partOf(stack[h - 1], .field) else .{},
        .get_index => |access| if (h > 1 and !isString(program, access.ty)) partOf(stack[h - 2], .element) else .{ .origin = .fresh },
        .buffer_operation => |operation| bufferSource(program, function, operation, here),
        .call => |callee| callSource(program.functions[@backingInt(callee)].signature, stack),
        .invoke => .{},
        else => .{ .origin = .fresh },
    };
}

/// A part read out of an operand: a part of a local stays a part of that
/// local, and a part of a value no local holds is itself such a value.
fn partOf(operand: Source, part: Part) Source {
    return switch (operand.origin) {
        .local => .{ .origin = .local, .local = operand.local, .part = if (operand.part == .whole) part else operand.part, .read = operand.read },
        .fresh => .{ .origin = .fresh },
        .unknown => .{},
    };
}

fn isString(program: bytecode.Program, ty: typed.Type) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= program.records.len) return false;
    const record = program.records[ty.recordIndex()];
    return record.managed and record.collection.kind == .string;
}

/// A read hands back an element the receiver still holds; a `pop` takes it
/// out; every other result is new.
fn bufferSource(program: bytecode.Program, function: bytecode.Function, operation: @FieldType(Op, "buffer_operation"), pc: u32) Source {
    const owner: u32 = @intCast(@backingInt(operation.owner));
    const element: Source = .{ .origin = .local, .local = owner, .part = .element, .read = pc };
    return switch (operation.kind) {
        .read => if (owner < function.scope.locals.len and isString(program, function.scope.locals[owner].ty)) .{ .origin = .fresh } else element,
        .key_at, .value_at, .get => element,
        else => .{ .origin = .fresh },
    };
}

/// A call's result: new when the callee's return origin says so, part of the
/// one argument it may return, and unknown otherwise.
fn callSource(signature: typed.FunctionSignature, stack: []const Source) Source {
    // RETURN-BORROW-1: the checker bound is about logical independence. A
    // value copy may still retain backing from an argument, so the native
    // ownership plan uses the separate physical result bound.
    return switch (signature.inferred.borrow_origin) {
        .fresh => .{ .origin = .fresh },
        .unknown => .{},
        .params => |positions| {
            if (positions.len != 1 or positions[0] >= signature.parameter_count) return .{};
            const count = signature.parameter_count;
            if (stack.len < count) return .{};
            return partOf(stack[stack.len - count + positions[0]], .element);
        },
    };
}

/// Popped operand count of one instruction, mirroring `native_ir.analyze`.
pub fn popsOf(program: bytecode.Program, op: Op) usize {
    return switch (op) {
        .acquire_resource, .dir_resource, .host_resource, .environment_get, .environment_only, .stream_write => 2,
        .complete_resource, .restrict_resource, .external_read, .environment_names, .acquire_buffer, .try_result => 1,
        .resource_io => |io| @as(usize, if (io.kind == .write) 1 else 0),
        .stand_in => |kind| kind.operands(),
        .print => |output| output.types.len + @intFromBool(output.separator) + @intFromBool(output.terminator) + @intFromBool(output.stream),
        .file_access => |call| call.operands,
        .file_method => |call| @intFromBool(call.argument),
        .buffer_operation => |operation| operation.kind.arity(),
        .function_value, .push_i64, .push_integer, .push_bool, .push_unit, .load_local, .ref_local, .move_local => 0,
        .drop_local, .jump, .begin_arena, .end_arena => 0,
        .invoke => |callback_type| program.records[callback_type.recordIndex()].contract.callback.?.valueCount() + 1,
        .store_local, .pop, .acknowledge, .jump_if_false, .ret, .assert_true => 1,
        .cast_integer, .neg_integer, .neg_i64_checked, .not_bool, .wrap_domain, .unwrap_domain, .get_field, .value_copy => 1,
        .switch_variant, .unary_float, .arena_escape, .array_length => 1,
        .add_i64_checked, .sub_i64_checked, .mul_i64_checked, .div_i64_checked, .rem_i64_checked, .cmp_i64 => 2,
        .cmp_bool, .cmp_domain, .cmp_enum, .binary_integer, .get_index => 2,
        .make_record => |record| record.fields,
        .update_record => |update| update.indices.len + 1,
        .replace_index => 3,
        .make_variant => |variant| @intFromBool(program.records[variant.ty.recordIndex()].shape.variants.?.cases[variant.tag].payload != null),
        .call => |target| program.functions[@backingInt(target)].signature.parameter_count,
    };
}
