//! Typed local/operand storage and explicitly checked guest arithmetic in every host mode.
const std = @import("std");
const bc = @import("bytecode.zig");
const typed = @import("typed.zig");
const Diagnostic = @import("diagnostic.zig").Diagnostic;
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
    try bc.validate(program);
    var stack: std.ArrayList(typed.Value) = .empty;
    defer stack.deinit(allocator);
    const function = program.functions[0];
    const locals = try allocator.alloc(?typed.Value, function.locals.len);
    defer allocator.free(locals);
    @memset(locals, null);
    for (function.instructions) |instruction| switch (instruction.op) {
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
    };
    return error.InternalError;
}
