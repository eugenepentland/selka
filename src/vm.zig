//! Typed local/operand storage and explicitly checked guest arithmetic in every host mode.
const std = @import("std");
const bc = @import("bytecode.zig");
const typed = @import("typed.zig");
const Diagnostic = @import("diagnostic.zig").Diagnostic;
pub const Options = struct { max_steps: u64 = 10_000_000 };
pub const Result = union(enum) { value: i64, trap: Diagnostic };
fn integer(value: typed.Value) error{InternalError}!i64 {
    if (value != .i64) return error.InternalError;
    return value.i64;
}
fn boolean(value: typed.Value) error{InternalError}!bool {
    if (value != .bool) return error.InternalError;
    return value.bool;
}
fn overflow(instruction: bc.Instruction) Result {
    return .{ .trap = .{ .code = "R_OVERFLOW", .span = instruction.span, .message = "integer arithmetic overflowed i64" } };
}
pub fn run(allocator: std.mem.Allocator, program: bc.Program) !Result {
    return runWithOptions(allocator, program, .{});
}
pub fn runWithOptions(allocator: std.mem.Allocator, program: bc.Program, options: Options) !Result {
    if (options.max_steps == 0) return error.InvalidBudget;
    try bc.validate(allocator, program);
    var stack: std.ArrayList(typed.Value) = .empty;
    defer stack.deinit(allocator);
    const function = program.functions[0];
    const locals = try allocator.alloc(?typed.Value, function.locals.len);
    defer allocator.free(locals);
    @memset(locals, null);
    var pc: usize = 0;
    var steps: u64 = 0;
    while (pc < function.instructions.len) {
        const instruction = function.instructions[pc];
        if (steps == options.max_steps) return .{ .trap = .{ .code = "R_STEP_LIMIT", .span = instruction.span, .message = "instruction budget exhausted" } };
        steps += 1;
        pc += 1;
        switch (instruction.op) {
            .pop => {
                _ = stack.pop() orelse return error.InternalError;
            },
            .jump => |target| pc = target,
            .jump_if_false => |target| if (!(try boolean(stack.pop() orelse return error.InternalError))) {
                pc = target;
            },
            .div_i64_checked, .rem_i64_checked => {
                const right = try integer(stack.pop() orelse return error.InternalError);
                const left = try integer(stack.pop() orelse return error.InternalError);
                if (right == 0) return .{ .trap = .{ .code = "R_DIVISION_BY_ZERO", .span = instruction.span, .message = "division or remainder by zero" } };
                const minimum_case = left == std.math.minInt(i64) and right == -1;
                if (instruction.op == .div_i64_checked and minimum_case) return overflow(instruction);
                const value = if (instruction.op == .div_i64_checked) @divTrunc(left, right) else if (minimum_case) @as(i64, 0) else @rem(left, right);
                try stack.append(allocator, .{ .i64 = value });
            },
            .push_i64 => |value| try stack.append(allocator, .{ .i64 = value }),
            .push_bool => |value| try stack.append(allocator, .{ .bool = value }),
            .load_local => |slot| try stack.append(allocator, locals[@backingInt(slot)] orelse return error.InternalError),
            .store_local => |slot| {
                const value = stack.pop() orelse return error.InternalError;
                if (std.meta.activeTag(value) != function.locals[@backingInt(slot)].ty) return error.InternalError;
                locals[@backingInt(slot)] = value;
            },
            .ret => {
                const value = try integer(stack.pop() orelse return error.InternalError);
                if (stack.items.len != 0) return error.InternalError;
                return .{ .value = value };
            },
            .not_bool => try stack.append(allocator, .{ .bool = !(try boolean(stack.pop() orelse return error.InternalError)) }),
            .neg_i64_checked => {
                const value = try integer(stack.pop() orelse return error.InternalError);
                const result = @subWithOverflow(@as(i64, 0), value);
                if (result[1] != 0) return overflow(instruction);
                try stack.append(allocator, .{ .i64 = result[0] });
            },
            .add_i64_checked, .sub_i64_checked, .mul_i64_checked => {
                const right = try integer(stack.pop() orelse return error.InternalError);
                const left = try integer(stack.pop() orelse return error.InternalError);
                const result = switch (instruction.op) {
                    .add_i64_checked => @addWithOverflow(left, right),
                    .sub_i64_checked => @subWithOverflow(left, right),
                    .mul_i64_checked => @mulWithOverflow(left, right),
                    else => return error.InternalError,
                };
                if (result[1] != 0) return overflow(instruction);
                try stack.append(allocator, .{ .i64 = result[0] });
            },
            .cmp_i64 => |predicate| {
                const right = try integer(stack.pop() orelse return error.InternalError);
                const left = try integer(stack.pop() orelse return error.InternalError);
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
                const right = try boolean(stack.pop() orelse return error.InternalError);
                const left = try boolean(stack.pop() orelse return error.InternalError);
                try stack.append(allocator, .{ .bool = if (predicate == .eq) left == right else left != right });
            },
        }
    }
    return error.InternalError;
}
