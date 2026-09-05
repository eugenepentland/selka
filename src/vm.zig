//! Typed local/operand storage and explicitly checked guest arithmetic in every host mode.
const std = @import("std");
const bc = @import("bytecode.zig");
const integers = @import("integers.zig");
const typed = @import("typed.zig");
const Diagnostic = @import("diagnostic.zig").Diagnostic;
pub const Options = struct { max_steps: u64 = 10_000_000, max_frames: u64 = 1024 };
pub const Result = union(enum) { value: i64, trap: Diagnostic };
fn integer(value: typed.Value, allocator: std.mem.Allocator) error{InternalError}!i64 {
    defer value.release(allocator);
    if (value != .i64) return error.InternalError;
    return value.i64;
}
fn numeric(stack: *std.ArrayList(typed.Value), base: usize, expected: ?typed.Type, allocator: std.mem.Allocator) !i128 {
    const value = try pop(stack, base);
    defer value.release(allocator);
    if (!value.typeOf().isInteger()) return error.InternalError;
    if (expected) |ty| if (value.typeOf() != ty) {
        return error.InternalError;
    };
    return value.asInteger();
}
fn boolean(value: typed.Value, allocator: std.mem.Allocator) error{InternalError}!bool {
    defer value.release(allocator);
    if (value != .bool) return error.InternalError;
    return value.bool;
}
fn pushOwned(stack: *std.ArrayList(typed.Value), allocator: std.mem.Allocator, value: typed.Value) !void {
    errdefer value.release(allocator);
    try stack.append(allocator, value);
}
const Span = @import("source.zig").Span;
const Frame = struct { function: typed.FunctionId, pc: usize = 0, local_base: usize, operand_base: usize, call_span: Span };
fn trap(code: []const u8, message: []const u8, span: Span, frames: []const Frame, program: bc.Program) Result {
    var diagnostic: Diagnostic = .{ .code = code, .message = message, .span = span };
    var i = frames.len;
    var at = span;
    while (i > 0 and diagnostic.trace_len < diagnostic.trace.len) {
        i -= 1;
        const frame = frames[i];
        diagnostic.trace[diagnostic.trace_len] = .{ .function = program.functions[@backingInt(frame.function)].name, .span = at };
        diagnostic.trace_len += 1;
        at = frame.call_span;
    }
    diagnostic.trace_omitted = i;
    return .{ .trap = diagnostic };
}
fn overflow(instruction: bc.Instruction, frames: []const Frame, program: bc.Program) Result {
    return trap("R_OVERFLOW", "integer arithmetic overflowed i64", instruction.span, frames, program);
}
fn pop(stack: *std.ArrayList(typed.Value), base: usize) error{InternalError}!typed.Value {
    if (stack.items.len <= base) return error.InternalError;
    return stack.pop().?;
}
pub fn run(allocator: std.mem.Allocator, program: bc.Program) !Result {
    return runWithOptions(allocator, program, .{});
}
pub fn runWithOptions(allocator: std.mem.Allocator, program: bc.Program, options: Options) !Result {
    if (options.max_steps == 0 or options.max_frames == 0) return error.InvalidBudget;
    try bc.validate(allocator, program);
    var stack: std.ArrayList(typed.Value) = .empty;
    defer {
        for (stack.items) |value| value.release(allocator);
        stack.deinit(allocator);
    }
    var locals: std.ArrayList(?typed.Value) = .empty;
    defer {
        for (locals.items) |value| if (value) |owned| owned.release(allocator);
        locals.deinit(allocator);
    }
    var frames: std.ArrayList(Frame) = .empty;
    defer frames.deinit(allocator);
    try locals.resize(allocator, program.functions[@backingInt(program.main)].locals.len);
    @memset(locals.items, null);
    try frames.append(allocator, .{ .function = program.main, .local_base = 0, .operand_base = 0, .call_span = .{ .start = 0, .end = 0 } });
    var steps: u64 = 0;
    while (frames.items.len != 0) {
        // Copy frame metadata before any grow; no references survive reallocations.
        const frame_index = frames.items.len - 1;
        const frame = frames.items[frame_index];
        const function = program.functions[@backingInt(frame.function)];
        if (frame.pc >= function.instructions.len) return error.InternalError;
        const instruction = function.instructions[frame.pc];
        if (steps == options.max_steps) return trap("R_STEP_LIMIT", "instruction budget exhausted", instruction.span, frames.items, program);
        steps += 1;
        frames.items[frame_index].pc += 1;
        switch (instruction.op) {
            .pop => {
                (try pop(&stack, frame.operand_base)).release(allocator);
            },
            .jump => |target| frames.items[frame_index].pc = target,
            .jump_if_false => |target| if (!(try boolean(try pop(&stack, frame.operand_base), allocator))) {
                frames.items[frame_index].pc = target;
            },
            .div_i64_checked, .rem_i64_checked => {
                const right = try integer(try pop(&stack, frame.operand_base), allocator);
                const left = try integer(try pop(&stack, frame.operand_base), allocator);
                if (right == 0) return trap("R_DIVISION_BY_ZERO", "division or remainder by zero", instruction.span, frames.items, program);
                const minimum_case = left == std.math.minInt(i64) and right == -1;
                if (instruction.op == .div_i64_checked and minimum_case) return overflow(instruction, frames.items, program);
                const value = if (instruction.op == .div_i64_checked) @divTrunc(left, right) else if (minimum_case) @as(i64, 0) else @rem(left, right);
                try stack.append(allocator, .{ .i64 = value });
            },
            .make_record => |record| {
                if (stack.items.len - frame.operand_base < record.fields) return error.InternalError;
                const start = stack.items.len - record.fields;
                const schema = program.records[record.ty.recordIndex()];
                for (stack.items[start..], 0..) |field, i| {
                    const field_index = if (record.order.len == 0) i else record.order[i];
                    if (field.typeOf() != schema.fields[field_index].ty) return error.InternalError;
                }
                const value = try typed.Value.createOrdered(allocator, record.ty, stack.items[start..], record.order);
                for (stack.items[start..]) |field| field.release(allocator);
                stack.shrinkRetainingCapacity(start);
                try pushOwned(&stack, allocator, value);
            },
            .update_record => |update| {
                if (stack.items.len - frame.operand_base <= update.indices.len) return error.InternalError;
                const start = stack.items.len - update.indices.len - 1;
                const base = stack.items[start];
                if (base.typeOf() != update.ty) return error.InternalError;
                const schema = program.records[update.ty.recordIndex()];
                for (stack.items[start + 1 ..], update.indices) |field, index| {
                    if (field.typeOf() != schema.fields[index].ty) return error.InternalError;
                }
                const value = try base.updated(allocator, update.indices, stack.items[start + 1 ..]);
                for (stack.items[start..]) |old| old.release(allocator);
                stack.shrinkRetainingCapacity(start);
                try pushOwned(&stack, allocator, value);
            },
            .get_field => |index| {
                const record = try pop(&stack, frame.operand_base);
                defer record.release(allocator);
                try pushOwned(&stack, allocator, try record.getField(index));
            },
            .push_integer => |number| try stack.append(allocator, typed.Value.number(number.ty, number.value)),
            .cast_integer, .neg_integer => |ty| {
                const operand = try numeric(&stack, frame.operand_base, if (instruction.op == .neg_integer) ty else null, allocator);
                const value = integers.cast(ty, if (instruction.op == .neg_integer) -operand else operand) catch |err| switch (err) {
                    error.Overflow => return trap("R_OVERFLOW", "integer conversion or negation exceeds the destination width", instruction.span, frames.items, program),
                    else => return error.InternalError,
                };
                try stack.append(allocator, value);
            },
            .binary_integer => |binary| {
                const right = try numeric(&stack, frame.operand_base, binary.ty, allocator);
                const left = try numeric(&stack, frame.operand_base, binary.ty, allocator);
                const value = integers.binary(binary.ty, binary.op, left, right) catch |err| switch (err) {
                    error.Overflow => return trap("R_OVERFLOW", "integer arithmetic exceeds its declared width", instruction.span, frames.items, program),
                    error.DivisionByZero => return trap("R_DIVISION_BY_ZERO", "division or remainder by zero", instruction.span, frames.items, program),
                    else => return error.InternalError,
                };
                try stack.append(allocator, value);
            },
            .push_i64 => |value| try stack.append(allocator, .{ .i64 = value }),
            .push_bool => |value| try stack.append(allocator, .{ .bool = value }),
            .load_local => |slot| try pushOwned(&stack, allocator, (locals.items[frame.local_base + @backingInt(slot)] orelse return error.InternalError).retain()),
            .store_local => |slot| {
                const value = try pop(&stack, frame.operand_base);
                errdefer value.release(allocator);
                if (value.typeOf() != function.locals[@backingInt(slot)].ty) return error.InternalError;
                if (locals.items[frame.local_base + @backingInt(slot)]) |old| old.release(allocator);
                locals.items[frame.local_base + @backingInt(slot)] = value;
            },
            .call => |id| {
                const callee = program.functions[@backingInt(id)];
                if (stack.items.len < frame.operand_base or stack.items.len - frame.operand_base < callee.parameter_count) return error.InternalError;
                if (frames.items.len >= options.max_frames) return trap("R_FRAME_LIMIT", "active frame budget exhausted", instruction.span, frames.items, program);
                const argument_base = stack.items.len - callee.parameter_count;
                for (stack.items[argument_base..], 0..) |argument, i| {
                    if (argument.typeOf() != callee.locals[i].ty) return error.InternalError;
                }
                const local_base = locals.items.len;
                const local_end = std.math.add(usize, local_base, callee.locals.len) catch return error.OutOfMemory;
                try locals.resize(allocator, local_end);
                @memset(locals.items[local_base..], null);
                for (stack.items[argument_base..], 0..) |argument, i| {
                    locals.items[local_base + i] = argument;
                }
                stack.shrinkRetainingCapacity(argument_base);
                try frames.append(allocator, .{ .function = id, .local_base = local_base, .operand_base = argument_base, .call_span = instruction.span });
            },
            .ret => {
                const value = try pop(&stack, frame.operand_base);
                if (value.typeOf() != function.return_type or stack.items.len != frame.operand_base) {
                    value.release(allocator);
                    return error.InternalError;
                }
                for (locals.items[frame.local_base..]) |local| if (local) |owned| owned.release(allocator);
                locals.shrinkRetainingCapacity(frame.local_base);
                _ = frames.pop();
                if (frames.items.len == 0) return .{ .value = try integer(value, allocator) };
                try pushOwned(&stack, allocator, value);
            },
            .not_bool => try stack.append(allocator, .{ .bool = !(try boolean(try pop(&stack, frame.operand_base), allocator)) }),
            .neg_i64_checked => {
                const value = try integer(try pop(&stack, frame.operand_base), allocator);
                const result = @subWithOverflow(@as(i64, 0), value);
                if (result[1] != 0) return overflow(instruction, frames.items, program);
                try stack.append(allocator, .{ .i64 = result[0] });
            },
            .add_i64_checked, .sub_i64_checked, .mul_i64_checked => {
                const right = try integer(try pop(&stack, frame.operand_base), allocator);
                const left = try integer(try pop(&stack, frame.operand_base), allocator);
                const result = switch (instruction.op) {
                    .add_i64_checked => @addWithOverflow(left, right),
                    .sub_i64_checked => @subWithOverflow(left, right),
                    .mul_i64_checked => @mulWithOverflow(left, right),
                    else => return error.InternalError,
                };
                if (result[1] != 0) return overflow(instruction, frames.items, program);
                try stack.append(allocator, .{ .i64 = result[0] });
            },
            .cmp_i64 => |predicate| {
                const right = try integer(try pop(&stack, frame.operand_base), allocator);
                const left = try integer(try pop(&stack, frame.operand_base), allocator);
                const value = switch (predicate) {
                    .eq => left == right,
                    .ne => left != right,
                    .lt => left < right,
                    .le => left <= right,
                    .gt => left > right,
                    .ge => left >= right,
                };
                try stack.append(allocator, .{ .bool = value });
            },
            .cmp_bool => |predicate| {
                const right = try boolean(try pop(&stack, frame.operand_base), allocator);
                const left = try boolean(try pop(&stack, frame.operand_base), allocator);
                try stack.append(allocator, .{ .bool = if (predicate == .eq) left == right else left != right });
            },
        }
    }
    return error.InternalError;
}
