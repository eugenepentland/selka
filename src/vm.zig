//! Typed local/operand storage and explicitly checked guest arithmetic in every host mode.
const std = @import("std");
const bc = @import("bytecode.zig");
const integers = @import("integers.zig");
const typed = @import("typed.zig");
const memory = @import("memory.zig");
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
const Slice = struct { start: usize, length: usize };
const Reference = struct { lease: memory.Borrow, slice: ?Slice = null };
const ReturnTarget = struct { destination: usize, parent: memory.Borrow, allocation: memory.Allocation, mutable: bool };
const CapturedReference = struct { slice: ?Slice };
const Frame = struct { return_target: ?ReturnTarget = null, captured: ?CapturedReference = null, reference_base: usize = 0, function: typed.FunctionId, pc: usize = 0, local_base: usize, operand_base: usize, call_span: Span };
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
    var storage = try memory.Store.init(allocator);
    defer storage.deinit();
    var owners: std.AutoHashMapUnmanaged(usize, memory.Allocation) = .empty;
    defer owners.deinit(allocator);
    var references: std.ArrayList(?Reference) = .empty;
    defer references.deinit(allocator);
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
    try references.resize(allocator, program.functions[@backingInt(program.main)].references.len);
    @memset(references.items, null);
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
            .acknowledge => |ty| {
                const value = try pop(&stack, frame.operand_base);
                defer value.release(allocator);
                if (value.typeOf() != ty) return error.InternalError;
            },
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
                    if (field.typeOf() != schema.elementType(field_index)) return error.InternalError;
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
            .get_index => |ty| {
                const key = try pop(&stack, frame.operand_base);
                defer key.release(allocator);
                const base = try pop(&stack, frame.operand_base);
                defer base.release(allocator);
                if (base.typeOf() != ty) return error.InternalError;
                const schema = program.records[ty.recordIndex()].array orelse return error.InternalError;
                const index = try arrayIndex(key, schema);
                if (index < 0 or index >= schema.length) return trap("R_INDEX_BOUNDS", "array index is outside its declared bounds", instruction.span, frames.items, program);
                try pushOwned(&stack, allocator, try base.getField(@intCast(index)));
            },
            .replace_index => |ty| {
                if (stack.items.len - frame.operand_base < 3) return error.InternalError;
                const start = stack.items.len - 3;
                const base = stack.items[start];
                const key = stack.items[start + 1];
                const replacement = stack.items[start + 2];
                if (base.typeOf() != ty) return error.InternalError;
                const schema = program.records[ty.recordIndex()].array orelse return error.InternalError;
                if (replacement.typeOf() != schema.element) return error.InternalError;
                const index = try arrayIndex(key, schema);
                if (index < 0 or index >= schema.length) return trap("R_INDEX_BOUNDS", "array replacement index is outside its declared bounds", instruction.span, frames.items, program);
                const result = try base.updated(allocator, &.{@intCast(index)}, &.{replacement});
                for (stack.items[start..]) |old| old.release(allocator);
                stack.shrinkRetainingCapacity(start);
                try pushOwned(&stack, allocator, result);
            },
            .array_length => |ty| {
                const base = try pop(&stack, frame.operand_base);
                defer base.release(allocator);
                if (base.typeOf() != ty) return error.InternalError;
                const schema = program.records[ty.recordIndex()].array orelse return error.InternalError;
                try stack.append(allocator, typed.Value.number(.u64, schema.length));
            },
            .make_variant => |variant| {
                const schema = program.records[variant.ty.recordIndex()].variants.?.cases[variant.tag];
                const payload: ?typed.Value = if (schema.payload != null) try pop(&stack, frame.operand_base) else null;
                defer if (payload) |value| value.release(allocator);
                if (payload) |value| if (value.typeOf() != schema.payload.?) return error.InternalError;
                try pushOwned(&stack, allocator, try typed.Value.createVariant(allocator, variant.ty, variant.tag, payload));
            },
            .switch_variant => |dispatch| {
                const input = try pop(&stack, frame.operand_base);
                defer input.release(allocator);
                if (input.typeOf() != dispatch.ty) return error.InternalError;
                const tag = try input.variantTag();
                if (tag >= dispatch.arms.len) return error.InternalError;
                const arm = dispatch.arms[tag];
                if (arm.slot) |slot| {
                    const payload = try input.getField(0);
                    if (payload.typeOf() != function.locals[@backingInt(slot)].ty) {
                        payload.release(allocator);
                        return error.InternalError;
                    }
                    const index = frame.local_base + @backingInt(slot);
                    if (owners.get(index)) |owner| {
                        defer payload.release(allocator);
                        storage.writeOwner(owner, 0, payload) catch |err| return memoryFailure(err, instruction, frames.items, program);
                    } else {
                        if (locals.items[index]) |old| old.release(allocator);
                        locals.items[index] = payload;
                    }
                }
                frames.items[frame_index].pc = arm.target;
            },
            .cmp_enum => |comparison| {
                const right = try pop(&stack, frame.operand_base);
                defer right.release(allocator);
                const left = try pop(&stack, frame.operand_base);
                defer left.release(allocator);
                if (left.typeOf() != comparison.ty or right.typeOf() != comparison.ty) return error.InternalError;
                const equal = try left.variantTag() == try right.variantTag();
                try stack.append(allocator, .{ .bool = if (comparison.predicate == .eq) equal else !equal });
            },
            .wrap_domain => |ty| {
                const input = try pop(&stack, frame.operand_base);
                defer input.release(allocator);
                const backing = program.records[ty.recordIndex()].domain orelse return error.InternalError;
                if (input.typeOf() != backing) return error.InternalError;
                try pushOwned(&stack, allocator, try typed.Value.create(allocator, ty, &.{input}));
            },
            .unwrap_domain => |ty| {
                const input = try pop(&stack, frame.operand_base);
                defer input.release(allocator);
                if (input.typeOf() != ty) return error.InternalError;
                try pushOwned(&stack, allocator, try input.getField(0));
            },
            .get_field => |index| {
                const record = try pop(&stack, frame.operand_base);
                defer record.release(allocator);
                if (record.typeOf().isAggregate() and (program.records[record.typeOf().recordIndex()].domain != null or program.records[record.typeOf().recordIndex()].variants != null)) return error.InternalError;
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
            .begin_borrow, .begin_slice => |id| {
                const index = frame.reference_base + @backingInt(id);
                if (references.items[index] != null) return trap("R_REFERENCE_LIFETIME", "reference is already active", instruction.span, frames.items, program);
                const metadata = function.references[@backingInt(id)];
                var slice: ?Slice = null;
                if (metadata.slice) {
                    if (metadata.parent) |parent| {
                        const previous = references.items[frame.reference_base + @backingInt(parent)] orelse return trap("R_REFERENCE_LIFETIME", "parent reference is not active", instruction.span, frames.items, program);
                        if (previous.slice) |view| slice = view else {
                            const array_type = function.references[@backingInt(parent)].ty;
                            slice = .{ .start = 0, .length = program.records[array_type.recordIndex()].array.?.length };
                        }
                    } else {
                        const array_type = function.locals[@backingInt(metadata.owner)].ty;
                        slice = .{ .start = 0, .length = program.records[array_type.recordIndex()].array.?.length };
                    }
                    if (instruction.op == .begin_slice) {
                        const end = try numeric(&stack, frame.operand_base, null, allocator);
                        const start = try numeric(&stack, frame.operand_base, null, allocator);
                        if (start < 0 or end < start or end > slice.?.length) return trap("R_SLICE_BOUNDS", "slice range is outside its source bounds", instruction.span, frames.items, program);
                        slice = .{ .start = slice.?.start + @as(usize, @intCast(start)), .length = @intCast(end - start) };
                    }
                }
                const kind: memory.Kind = if (metadata.mutable) .exclusive else .shared;
                const reference = if (metadata.parent) |parent| child: {
                    const parent_reference = references.items[frame.reference_base + @backingInt(parent)] orelse return trap("R_REFERENCE_LIFETIME", "parent reference is not active", instruction.span, frames.items, program);
                    break :child storage.reborrow(parent_reference.lease, 0, 1, kind) catch |err| return memoryFailure(err, instruction, frames.items, program);
                } else root: {
                    const local_index = frame.local_base + @backingInt(metadata.owner);
                    var allocation = owners.get(local_index);
                    if (allocation == null) {
                        const old = locals.items[local_index] orelse return error.InternalError;
                        const created = try storage.create(function.locals[@backingInt(metadata.owner)].ty, &.{old});
                        // The store owns created memory if inserting the owner map fails.
                        try owners.put(allocator, local_index, created);
                        locals.items[local_index] = null;
                        old.release(allocator);
                        allocation = created;
                    }
                    break :root storage.borrow(allocation.?, 0, 1, kind) catch |err| return memoryFailure(err, instruction, frames.items, program);
                };
                references.items[index] = .{ .lease = reference, .slice = slice };
            },
            .end_borrow => |id| {
                const index = frame.reference_base + @backingInt(id);
                const reference = references.items[index] orelse return trap("R_REFERENCE_LIFETIME", "reference is not active", instruction.span, frames.items, program);
                storage.end(reference.lease) catch |err| return memoryFailure(err, instruction, frames.items, program);
                references.items[index] = null;
            },
            .len_slice => |id| {
                const reference = references.items[frame.reference_base + @backingInt(id)] orelse return trap("R_REFERENCE_LIFETIME", "slice is not active", instruction.span, frames.items, program);
                _ = storage.describe(reference.lease) catch |err| return memoryFailure(err, instruction, frames.items, program);
                const view = reference.slice orelse return error.InternalError;
                try stack.append(allocator, typed.Value.number(.u64, view.length));
            },
            .read_slice => |id| {
                const index = try numeric(&stack, frame.operand_base, null, allocator);
                const reference = references.items[frame.reference_base + @backingInt(id)] orelse return trap("R_REFERENCE_LIFETIME", "slice is not active", instruction.span, frames.items, program);
                const view = reference.slice orelse return error.InternalError;
                if (index < 0 or index >= view.length) return trap("R_SLICE_BOUNDS", "slice index is outside its bounds", instruction.span, frames.items, program);
                const array = storage.read(reference.lease, 0) catch |err| return memoryFailure(err, instruction, frames.items, program);
                defer array.release(allocator);
                try pushOwned(&stack, allocator, try array.getField(view.start + @as(usize, @intCast(index))));
            },
            .write_slice => |id| {
                const value = try pop(&stack, frame.operand_base);
                defer value.release(allocator);
                const index = try numeric(&stack, frame.operand_base, null, allocator);
                const reference = references.items[frame.reference_base + @backingInt(id)] orelse return trap("R_REFERENCE_LIFETIME", "slice is not active", instruction.span, frames.items, program);
                const view = reference.slice orelse return error.InternalError;
                if (index < 0 or index >= view.length) return trap("R_SLICE_BOUNDS", "slice index is outside its bounds", instruction.span, frames.items, program);
                if (value.typeOf() != function.references[@backingInt(id)].ty) return trap("R_REFERENCE_TYPE", "slice write has the wrong element type", instruction.span, frames.items, program);
                const array = storage.read(reference.lease, 0) catch |err| return memoryFailure(err, instruction, frames.items, program);
                defer array.release(allocator);
                const updated = try array.updated(allocator, &.{view.start + @as(usize, @intCast(index))}, &.{value});
                defer updated.release(allocator);
                storage.write(reference.lease, 0, updated) catch |err| return memoryFailure(err, instruction, frames.items, program);
            },
            .read_ref => |id| {
                const reference = references.items[frame.reference_base + @backingInt(id)] orelse return trap("R_REFERENCE_LIFETIME", "reference is not active", instruction.span, frames.items, program);
                const value = storage.read(reference.lease, 0) catch |err| return memoryFailure(err, instruction, frames.items, program);
                try pushOwned(&stack, allocator, value);
            },
            .write_ref => |id| {
                const value = try pop(&stack, frame.operand_base);
                defer value.release(allocator);
                const reference = references.items[frame.reference_base + @backingInt(id)] orelse return trap("R_REFERENCE_LIFETIME", "reference is not active", instruction.span, frames.items, program);
                storage.write(reference.lease, 0, value) catch |err| return memoryFailure(err, instruction, frames.items, program);
            },
            .load_local => |slot| {
                const index = frame.local_base + @backingInt(slot);
                const value = if (owners.get(index)) |owner| storage.readOwner(owner, 0) catch |err| return memoryFailure(err, instruction, frames.items, program) else (locals.items[index] orelse return error.InternalError).retain();
                try pushOwned(&stack, allocator, value);
            },
            .store_local => |slot| {
                const value = try pop(&stack, frame.operand_base);
                var transferred = false;
                defer if (!transferred) value.release(allocator);
                if (value.typeOf() != function.locals[@backingInt(slot)].ty) return error.InternalError;
                const index = frame.local_base + @backingInt(slot);
                if (owners.get(index)) |owner| {
                    storage.writeOwner(owner, 0, value) catch |err| return memoryFailure(err, instruction, frames.items, program);
                } else {
                    if (locals.items[index]) |old| old.release(allocator);
                    locals.items[index] = value;
                    transferred = true;
                }
            },
            .capture_ref => |id| {
                const reference = references.items[frame.reference_base + @backingInt(id)] orelse return trap("R_REFERENCE_LIFETIME", "returned reference is not active", instruction.span, frames.items, program);
                const target = frame.return_target orelse return error.InternalError;
                const view = storage.describe(reference.lease) catch |err| return memoryFailure(err, instruction, frames.items, program);
                if (!std.meta.eql(view.allocation, target.allocation) or frame.captured != null) return trap("R_REFERENCE_LIFETIME", "returned reference does not belong to the declared input", instruction.span, frames.items, program);
                frames.items[frame_index].captured = .{ .slice = reference.slice };
            },
            .call, .call_refs, .call_borrow => {
                const id = switch (instruction.op) {
                    .call => |id| id,
                    .call_refs => |call| call.function,
                    .call_borrow => |call| call.function,
                    else => unreachable,
                };
                const loan_arguments: []const typed.ReferenceId = switch (instruction.op) {
                    .call => &.{},
                    .call_refs => |call| call.references,
                    .call_borrow => |call| call.references,
                    else => unreachable,
                };
                const callee = program.functions[@backingInt(id)];
                const value_count = bc.valueParameterCount(callee);
                if (stack.items.len < frame.operand_base or stack.items.len - frame.operand_base < value_count) return error.InternalError;
                if (frames.items.len >= options.max_frames) return trap("R_FRAME_LIMIT", "active frame budget exhausted", instruction.span, frames.items, program);
                const argument_base = stack.items.len - value_count;
                var argument_index = argument_base;
                for (callee.locals[0..callee.parameter_count]) |parameter| {
                    if (parameter.reference_parameter != null) continue;
                    if (stack.items[argument_index].typeOf() != parameter.ty) return error.InternalError;
                    argument_index += 1;
                }
                var return_target: ?ReturnTarget = null;
                if (instruction.op == .call_borrow) {
                    const destination = instruction.op.call_borrow.destination;
                    const target_index = frame.reference_base + @backingInt(destination);
                    if (references.items[target_index] != null) return trap("R_REFERENCE_LIFETIME", "result reference is already active", instruction.span, frames.items, program);
                    const metadata = function.references[@backingInt(destination)];
                    const parent = references.items[frame.reference_base + @backingInt(metadata.parent.?)] orelse return trap("R_REFERENCE_LIFETIME", "result input reference is not active", instruction.span, frames.items, program);
                    const view = storage.describe(parent.lease) catch |err| return memoryFailure(err, instruction, frames.items, program);
                    return_target = .{ .destination = target_index, .parent = parent.lease, .allocation = view.allocation, .mutable = metadata.mutable };
                }
                const reference_base = references.items.len;
                const reference_end = std.math.add(usize, reference_base, callee.references.len) catch return error.OutOfMemory;
                try references.resize(allocator, reference_end);
                @memset(references.items[reference_base..], null);
                var loan_index: usize = 0;
                for (callee.references, 0..) |parameter, index| {
                    if (!parameter.parameter) continue;
                    const parent = references.items[frame.reference_base + @backingInt(loan_arguments[loan_index])] orelse return trap("R_REFERENCE_LIFETIME", "reference argument is not active", instruction.span, frames.items, program);
                    loan_index += 1;
                    const child = storage.reborrow(parent.lease, 0, 1, if (parameter.mutable) .exclusive else .shared) catch |err| return memoryFailure(err, instruction, frames.items, program);
                    references.items[reference_base + index] = .{ .lease = child, .slice = parent.slice };
                }
                const local_base = locals.items.len;
                const local_end = std.math.add(usize, local_base, callee.locals.len) catch return error.OutOfMemory;
                try locals.resize(allocator, local_end);
                @memset(locals.items[local_base..], null);
                argument_index = argument_base;
                for (callee.locals[0..callee.parameter_count], 0..) |parameter, index| {
                    if (parameter.reference_parameter != null) continue;
                    locals.items[local_base + index] = stack.items[argument_index];
                    argument_index += 1;
                }
                stack.shrinkRetainingCapacity(argument_base);
                try frames.append(allocator, .{ .return_target = return_target, .reference_base = reference_base, .function = id, .local_base = local_base, .operand_base = argument_base, .call_span = instruction.span });
            },
            .ret, .ret_ref => {
                const value: ?typed.Value = if (instruction.op == .ret) try pop(&stack, frame.operand_base) else null;
                var transferred = false;
                defer if (!transferred) {
                    if (value) |owned| owned.release(allocator);
                };
                if (stack.items.len != frame.operand_base) return error.InternalError;
                if (value) |owned| {
                    if (owned.typeOf() != function.return_type) return error.InternalError;
                } else if (frame.captured == null or frame.return_target == null) return trap("R_REFERENCE_LIFETIME", "reference return has no captured result", instruction.span, frames.items, program);
                for (references.items[frame.reference_base..]) |reference| if (reference != null) return trap("R_REFERENCE_LIFETIME", "function returned with an active reference", instruction.span, frames.items, program);
                references.shrinkRetainingCapacity(frame.reference_base);
                for (locals.items[frame.local_base..], frame.local_base..) |*local, index| {
                    if (owners.get(index)) |owner| {
                        storage.destroy(owner) catch |err| return memoryFailure(err, instruction, frames.items, program);
                        _ = owners.remove(index);
                    }
                    if (local.*) |owned| owned.release(allocator);
                    local.* = null;
                }
                locals.shrinkRetainingCapacity(frame.local_base);
                _ = frames.pop();
                if (value) |owned| {
                    transferred = true;
                    if (frames.items.len == 0) return .{ .value = try integer(owned, allocator) };
                    try pushOwned(&stack, allocator, owned);
                } else {
                    const target = frame.return_target.?;
                    const lease = storage.reborrow(target.parent, 0, 1, if (target.mutable) .exclusive else .shared) catch |err| return memoryFailure(err, instruction, frames.items, program);
                    references.items[target.destination] = .{ .lease = lease, .slice = frame.captured.?.slice };
                }
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

fn arrayIndex(value: typed.Value, schema: typed.Array) error{InternalError}!i128 {
    if (schema.key) |key| {
        if (value.typeOf() != key) return error.InternalError;
        return try value.variantTag();
    }
    return value.asInteger();
}

fn memoryFailure(err: memory.Error, instruction: bc.Instruction, frames: []const Frame, program: bc.Program) error{ OutOfMemory, IdentityExhausted }!Result {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.IdentityExhausted => error.IdentityExhausted,
        error.BorrowConflict => trap("R_BORROW_CONFLICT", "access conflicts with an active borrow", instruction.span, frames, program),
        error.BorrowSuspended => trap("R_BORROW_SUSPENDED", "reference is suspended by an active child borrow", instruction.span, frames, program),
        error.ReadOnly => trap("R_REFERENCE_READ_ONLY", "reference does not permit writing", instruction.span, frames, program),
        error.Bounds => trap("R_REFERENCE_BOUNDS", "reference access is outside its bounds", instruction.span, frames, program),
        error.TypeMismatch => trap("R_REFERENCE_TYPE", "reference write has the wrong element type", instruction.span, frames, program),
        else => trap("R_REFERENCE_LIFETIME", "reference or owner lifetime is invalid", instruction.span, frames, program),
    };
}
