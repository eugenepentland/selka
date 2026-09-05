//! Typed local/operand storage and explicitly checked guest arithmetic in every host mode.
const std = @import("std");
const bc = @import("bytecode.zig");
const typed = @import("typed.zig");
const Diagnostic = @import("diagnostic.zig").Diagnostic;
pub const Options = struct { max_steps: u64 = 10_000_000, max_frames: u64 = 1024 };
pub const Result = union(enum) { value: i64, trap: Diagnostic };
fn integer(value: typed.Value) error{InternalError}!i64 {
    if (value != .i64) return error.InternalError;
    return value.i64;
}
fn boolean(value: typed.Value) error{InternalError}!bool {
    if (value != .bool) return error.InternalError;
    return value.bool;
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
    defer stack.deinit(allocator);
    var locals: std.ArrayList(?typed.Value) = .empty;
    defer locals.deinit(allocator);
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
                _ = try pop(&stack, frame.operand_base);
            },
            .jump => |target| frames.items[frame_index].pc = target,
            .jump_if_false => |target| if (!(try boolean(try pop(&stack, frame.operand_base)))) {
                frames.items[frame_index].pc = target;
            },
            .div_i64_checked, .rem_i64_checked => {
                const right = try integer(try pop(&stack, frame.operand_base));
                const left = try integer(try pop(&stack, frame.operand_base));
                if (right == 0) return trap("R_DIVISION_BY_ZERO", "division or remainder by zero", instruction.span, frames.items, program);
                const minimum_case = left == std.math.minInt(i64) and right == -1;
                if (instruction.op == .div_i64_checked and minimum_case) return overflow(instruction, frames.items, program);
                const value = if (instruction.op == .div_i64_checked) @divTrunc(left, right) else if (minimum_case) @as(i64, 0) else @rem(left, right);
                try stack.append(allocator, .{ .i64 = value });
            },
            .push_i64 => |value| try stack.append(allocator, .{ .i64 = value }),
            .push_bool => |value| try stack.append(allocator, .{ .bool = value }),
            .load_local => |slot| try stack.append(allocator, locals.items[frame.local_base + @backingInt(slot)] orelse return error.InternalError),
            .store_local => |slot| {
                const value = try pop(&stack, frame.operand_base);
                if (std.meta.activeTag(value) != function.locals[@backingInt(slot)].ty) return error.InternalError;
                locals.items[frame.local_base + @backingInt(slot)] = value;
            },
            .call => |id| {
                const callee = program.functions[@backingInt(id)];
                if (stack.items.len < frame.operand_base or stack.items.len - frame.operand_base < callee.parameter_count) return error.InternalError;
                if (frames.items.len >= options.max_frames) return trap("R_FRAME_LIMIT", "active frame budget exhausted", instruction.span, frames.items, program);
                const argument_base = stack.items.len - callee.parameter_count;
                const local_base = locals.items.len;
                const local_end = std.math.add(usize, local_base, callee.locals.len) catch return error.OutOfMemory;
                try locals.resize(allocator, local_end);
                @memset(locals.items[local_base..], null);
                for (stack.items[argument_base..], 0..) |argument, i| {
                    if (std.meta.activeTag(argument) != callee.locals[i].ty) return error.InternalError;
                    locals.items[local_base + i] = argument;
                }
                stack.shrinkRetainingCapacity(argument_base);
                try frames.append(allocator, .{ .function = id, .local_base = local_base, .operand_base = argument_base, .call_span = instruction.span });
            },
            .ret => {
                const value = try pop(&stack, frame.operand_base);
                if (std.meta.activeTag(value) != function.return_type or stack.items.len != frame.operand_base) return error.InternalError;
                locals.shrinkRetainingCapacity(frame.local_base);
                _ = frames.pop();
                if (frames.items.len == 0) return .{ .value = try integer(value) };
                try stack.append(allocator, value);
            },
            .not_bool => try stack.append(allocator, .{ .bool = !(try boolean(try pop(&stack, frame.operand_base))) }),
            .neg_i64_checked => {
                const value = try integer(try pop(&stack, frame.operand_base));
                const result = @subWithOverflow(@as(i64, 0), value);
                if (result[1] != 0) return overflow(instruction, frames.items, program);
                try stack.append(allocator, .{ .i64 = result[0] });
            },
            .add_i64_checked, .sub_i64_checked, .mul_i64_checked => {
                const right = try integer(try pop(&stack, frame.operand_base));
                const left = try integer(try pop(&stack, frame.operand_base));
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
                const right = try integer(try pop(&stack, frame.operand_base));
                const left = try integer(try pop(&stack, frame.operand_base));
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
                const right = try boolean(try pop(&stack, frame.operand_base));
                const left = try boolean(try pop(&stack, frame.operand_base));
                try stack.append(allocator, .{ .bool = if (predicate == .eq) left == right else left != right });
            },
        }
    }
    return error.InternalError;
}
