//! Everyday list composition through existing value-functional updates.
const std = @import("std");
const ir = @import("ir.zig");
const flags = @import("flags.zig");
const checks = @import("text_checks.zig");
const typed = @import("mylang").typed;
const Operation = @FieldType(@FieldType(typed.Node, "data"), "buffer_operation");
const Range = struct { start: ir.Ref, stop: ir.Ref };
const Endpoint = struct { value: ir.Ref, stop: bool };
const Slice = struct { first: ir.Ref, step: ir.Ref, count: ir.Ref };

/// Allocation and precise feature refusals are the list builder's failures.
pub const Error = error{ OutOfMemory, Unsupported };

/// Read methods capture the receiver; mutators evaluate arguments before refreshing it.
pub fn operation(comptime Context: type, b: Context, node: Operation, result_ty: ir.Type, span: u32) Error!ir.Ref {
    switch (node.kind) {
        .index_of => {
            const receiver = try b.receiverOf(node.owner);
            const needle = try b.expression(node.arguments[0]);
            if (b.current == null) return .none;
            const index = try find(Context, b, receiver, needle, span);
            return b.emit(.{ .op = .convert, .ty = .i64, .a = index, .span = span });
        },
        .insert => return insert(Context, b, node, span),
        .pop_at, .remove => return remove(Context, b, node, result_ty, span),
        .slice_step => return slice(Context, b, node, span),
        .extend => {
            const other = try b.expression(node.arguments[0]);
            if (b.current == null) return .none;
            const receiver = try b.writableReceiverOf(node.owner, span);
            try b.writeOwner(node.owner, try extend(Context, b, receiver, other, span), span);
        },
        .reverse, .clear => {
            const receiver = try b.writableReceiverOf(node.owner, span);
            if (node.kind == .reverse and b.module().zero_rc) {
                const ty = b.typeOfRef(receiver);
                const size = try b.constant(.i64, b.module().size(b.module().compound(ty).list));
                const result = try b.effectCall("myl_core_owned_list_reverse", &.{ ty, .i64 }, ty, &.{ receiver, size }, span);
                try b.writeOwner(node.owner, result, span);
                return .none;
            }
            const capacity = if (node.kind == .clear) try b.constant(.u64, 0) else try length(Context, b, receiver, span);
            const empty = try fresh(Context, b, receiver, capacity, span);
            const result = if (node.kind == .clear) empty else try compose(Context, b, empty, receiver, true, span);
            try b.writeOwner(node.owner, result, span);
        },
        else => return b.mb.refuse(@tagName(node.kind), span),
    }
    return .none;
}

/// Append each source element once; a nested receiver can alias a distinct read.
pub fn extend(comptime Context: type, b: Context, target: ir.Ref, source: ir.Ref, span: u32) Error!ir.Ref {
    if (!b.module().zero_rc or b.function.resolve(target) == b.function.resolve(source))
        return compose(Context, b, target, source, false, span);
    const ty = b.typeOfRef(target);
    const identical = try b.runtimeCall("myl_core_owned_same_block", &.{ ty, ty }, .i64, &.{ target, source }, span);
    const result = try b.synthetic(ty);
    const same = try b.newBlock();
    const distinct = try b.newBlock();
    const end = try b.newBlock();
    try b.branch(try compare(Context, b, .ne, identical, try b.constant(.i64, 0), span), same, distinct, span);
    try b.seal(same);
    b.enter(same);
    const extended_self = try compose(Context, b, target, target, false, span);
    try b.write(result, b.current.?, extended_self);
    try b.jump(end);
    try b.seal(distinct);
    b.enter(distinct);
    const extended_other = try compose(Context, b, target, source, false, span);
    try b.write(result, b.current.?, extended_other);
    try b.jump(end);
    try b.seal(end);
    b.enter(end);
    return b.read(result, end);
}

fn length(comptime Context: type, b: Context, source: ir.Ref, span: u32) Error!ir.Ref {
    return b.emit(.{ .op = .list_len, .ty = .u64, .a = source, .span = span });
}

fn fresh(comptime Context: type, b: Context, source: ir.Ref, capacity: ir.Ref, span: u32) Error!ir.Ref {
    return b.emit(.{ .op = .list_new, .ty = b.typeOfRef(source), .a = capacity, .span = span });
}

fn compare(comptime Context: type, b: Context, predicate: ir.Predicate, left: ir.Ref, right: ir.Ref, span: u32) Error!ir.Ref {
    return b.emit(.{ .op = .cmp, .ty = .bool, .a = left, .b = right, .data = @backingInt(predicate), .span = span });
}

fn select(comptime Context: type, b: Context, condition: ir.Ref, yes: ir.Ref, no: ir.Ref, span: u32) Error!ir.Ref {
    const slot = try b.synthetic(b.typeOfRef(yes));
    const first = try b.newBlock();
    const second = try b.newBlock();
    const end = try b.newBlock();
    try b.branch(condition, first, second, span);
    try b.seal(first);
    b.enter(first);
    try b.write(slot, first, yes);
    try b.jump(end);
    try b.seal(second);
    b.enter(second);
    try b.write(slot, second, no);
    try b.jump(end);
    try b.seal(end);
    b.enter(end);
    return b.read(slot, end);
}

/// The first equal element, or the old R_LIST_VALUE trap when absent.
fn find(comptime Context: type, b: Context, source: ir.Ref, needle: ir.Ref, span: u32) Error!ir.Ref {
    const found = try @import("build_values.zig").firstIndex(Context, b, source, needle, span);
    const count = try length(Context, b, source, span);
    try checks.require(Context, b, try compare(Context, b, .lt, found, count, span), 18, span);
    return found;
}

/// Python's negative insertion positions clamp into [0, length].
fn insert(comptime Context: type, b: Context, node: Operation, span: u32) Error!ir.Ref {
    const input = try b.expression(node.arguments[0]);
    var value = try b.expression(node.arguments[1]);
    if (b.current == null) return .none;
    if (value == .none) value = try b.constant(.bool, 0);
    const source = try b.writableReceiverOf(node.owner, span);
    const count = try length(Context, b, source, span);
    const wide = try b.emit(.{ .op = .convert, .ty = .i64, .a = input, .span = span });
    const signed_count = try b.emit(.{ .op = .convert, .ty = .i64, .a = count, .span = span });
    const zero = try b.constant(.i64, 0);
    const adjusted = try select(Context, b, try compare(Context, b, .lt, wide, zero, span), try b.emit(.{ .op = .add, .ty = .i64, .a = wide, .b = signed_count, .span = span }), wide, span);
    const low = try select(Context, b, try compare(Context, b, .lt, adjusted, zero, span), zero, adjusted, span);
    const clamped = try select(Context, b, try compare(Context, b, .gt, low, signed_count, span), signed_count, low, span);
    const at = try b.emit(.{ .op = .convert, .ty = .u64, .a = clamped, .span = span });
    if (b.module().zero_rc) {
        const pushed = try b.emit(.{ .op = .list_push, .ty = b.typeOfRef(source), .a = source, .b = value, .span = span });
        try b.writeOwner(node.owner, try rotate(Context, b, pushed, at, true, span), span);
        return .none;
    }
    const empty = try fresh(Context, b, source, try b.emit(.{ .op = .add, .ty = .u64, .a = count, .b = try b.constant(.u64, 1), .check = .exact, .span = span }), span);
    const first = try range(Context, b, empty, source, .{ .start = try b.constant(.u64, 0), .stop = at }, span);
    const middle = try b.emit(.{ .op = .list_push, .ty = b.typeOfRef(source), .a = first, .b = value, .span = span });
    try b.writeOwner(node.owner, try range(Context, b, middle, source, .{ .start = at, .stop = count }, span), span);
    return .none;
}

/// Read a popped value before rebuilding the remaining list, preserving owned children.
fn remove(comptime Context: type, b: Context, node: Operation, result_ty: ir.Type, span: u32) Error!ir.Ref {
    const input = try b.expression(node.arguments[0]);
    if (b.current == null) return .none;
    const source = try b.writableReceiverOf(node.owner, span);
    const count = try length(Context, b, source, span);
    var index = input;
    var value: ir.Ref = .none;
    if (node.kind == .remove) {
        index = try find(Context, b, source, input, span);
    } else {
        const wide = try b.emit(.{ .op = .convert, .ty = .i64, .a = input, .span = span });
        const signed_count = try b.emit(.{ .op = .convert, .ty = .i64, .a = count, .span = span });
        index = try select(Context, b, try compare(Context, b, .lt, wide, try b.constant(.i64, 0), span), try b.emit(.{ .op = .add, .ty = .i64, .a = wide, .b = signed_count, .span = span }), wide, span);
        const element = b.module().compound(b.typeOfRef(source)).list;
        value = try b.emit(.{ .op = .list_get, .ty = element, .a = source, .b = index, .data = flags.pop_index_read, .check = .exact, .span = span });
        index = try b.emit(.{ .op = .convert, .ty = .u64, .a = index, .span = span });
    }
    if (b.module().zero_rc) {
        // The indexed read above retains the existing located pop bounds check.
        // Rotate whole slots, then use the ordinary last-slot transfer protocol.
        const rotated = try rotate(Context, b, source, index, false, span);
        const last = try b.emit(.{ .op = .sub, .ty = .u64, .a = count, .b = try b.constant(.u64, 1), .span = span });
        const element = b.module().compound(b.typeOfRef(source)).list;
        const taken = try b.emit(.{ .op = .list_get, .ty = element, .a = rotated, .b = last, .data = flags.pop_read, .check = .exact, .span = span });
        const rest = try b.emit(.{ .op = .list_pop, .ty = b.typeOfRef(source), .a = rotated, .check = .exact, .span = span });
        try b.writeOwner(node.owner, rest, span);
        return if (result_ty == .void) .none else taken;
    }
    const empty = try fresh(Context, b, source, try b.emit(.{ .op = .sub, .ty = .u64, .a = count, .b = try b.constant(.u64, 1), .span = span }), span);
    const first = try range(Context, b, empty, source, .{ .start = try b.constant(.u64, 0), .stop = index }, span);
    const next = try b.emit(.{ .op = .add, .ty = .u64, .a = index, .b = try b.constant(.u64, 1), .span = span });
    try b.writeOwner(node.owner, try range(Context, b, first, source, .{ .start = next, .stop = count }, span), span);
    return if (result_ty == .void) .none else value;
}

// A consuming permutation moves the existing child owners without copying them.
fn rotate(comptime Context: type, b: Context, source: ir.Ref, index: ir.Ref, last_to_index: bool, span: u32) Error!ir.Ref {
    const ty = b.typeOfRef(source);
    const size = try b.constant(.i64, b.module().size(b.module().compound(ty).list));
    const direction = try b.constant(.i64, @intFromBool(last_to_index));
    const at = if (b.typeOfRef(index) == .i64) index else try b.emit(.{ .op = .convert, .ty = .i64, .a = index, .span = span });
    return b.effectCall("myl_core_owned_list_rotate", &.{ ty, .i64, .i64, .i64 }, ty, &.{ source, at, size, direction }, span);
}

fn range(comptime Context: type, b: Context, target: ir.Ref, source: ir.Ref, limits: Range, span: u32) Error!ir.Ref {
    const ty = b.typeOfRef(source);
    const element = b.module().compound(ty).list;
    const list_slot = try b.synthetic(ty);
    const index_slot = try b.synthetic(.u64);
    try b.write(list_slot, b.current.?, target);
    try b.write(index_slot, b.current.?, limits.start);
    const header = try b.newBlock();
    const body = try b.newBlock();
    const end = try b.newBlock();
    try b.jump(header);
    b.enter(header);
    const index = try b.read(index_slot, header);
    try b.branch(try compare(Context, b, .lt, index, limits.stop, span), body, end, span);
    try b.seal(body);
    b.enter(body);
    const value = try b.emit(.{ .op = .list_get, .ty = element, .a = source, .b = index, .check = .exact, .span = span });
    const pushed = try b.emit(.{ .op = .list_push, .ty = ty, .a = try b.read(list_slot, body), .b = value, .span = span });
    try b.write(list_slot, body, pushed);
    try b.write(index_slot, body, try b.emit(.{ .op = .add, .ty = .u64, .a = index, .b = try b.constant(.u64, 1), .span = span }));
    try b.jump(header);
    try b.seal(header);
    try b.seal(end);
    b.enter(end);
    return b.read(list_slot, end);
}

/// The endpoint/sentinel rules of native_collections.c's stepped-list slice.
fn bound(comptime Context: type, b: Context, endpoint: Endpoint, count: ir.Ref, positive: ir.Ref, span: u32) Error!ir.Ref {
    const input = endpoint.value;
    const zero = try b.constant(.i64, 0);
    const minus_one = try b.constant(.i64, -1);
    const last = try b.emit(.{ .op = .sub, .ty = .i64, .a = count, .b = try b.constant(.i64, 1), .span = span });
    const low = try select(Context, b, positive, zero, minus_one, span);
    const high = try select(Context, b, positive, count, last, span);
    const adjusted = try select(Context, b, try compare(Context, b, .lt, input, zero, span), try b.emit(.{ .op = .add, .ty = .i64, .a = input, .b = count, .span = span }), input, span);
    const clamped_low = try select(Context, b, try compare(Context, b, .lt, adjusted, low, span), low, adjusted, span);
    const clamped = try select(Context, b, try compare(Context, b, .gt, clamped_low, high, span), high, clamped_low, span);
    const sentinel = try b.constant(.i64, if (endpoint.stop) std.math.maxInt(i64) else std.math.minInt(i64));
    const default = if (endpoint.stop) try select(Context, b, positive, count, minus_one, span) else try select(Context, b, positive, zero, last, span);
    return select(Context, b, try compare(Context, b, .eq, input, sentinel, span), default, clamped, span);
}

fn slice(comptime Context: type, b: Context, node: Operation, span: u32) Error!ir.Ref {
    const source = try b.receiverOf(node.owner);
    const start = try b.expression(node.arguments[0]);
    const stop = try b.expression(node.arguments[1]);
    const step = try b.expression(node.arguments[2]);
    if (b.current == null) return .none;
    const zero = try b.constant(.i64, 0);
    try checks.require(Context, b, try compare(Context, b, .ne, step, zero, span), 13, span);
    const positive = try compare(Context, b, .gt, step, zero, span);
    const count = try b.emit(.{ .op = .convert, .ty = .i64, .a = try length(Context, b, source, span), .span = span });
    const first = try bound(Context, b, .{ .value = start, .stop = false }, count, positive, span);
    const last = try bound(Context, b, .{ .value = stop, .stop = true }, count, positive, span);
    const nonempty = try select(Context, b, positive, try compare(Context, b, .lt, first, last, span), try compare(Context, b, .gt, first, last, span), span);
    const difference = try select(Context, b, positive, try b.emit(.{ .op = .sub, .ty = .i64, .a = last, .b = first, .span = span }), try b.emit(.{ .op = .sub, .ty = .i64, .a = first, .b = last, .span = span }), span);
    const distance = try b.emit(.{ .op = .convert, .ty = .u64, .a = try select(Context, b, nonempty, difference, zero, span), .span = span });
    const magnitude = try b.emit(.{ .op = .convert, .ty = .u64, .a = try select(Context, b, positive, step, try b.emit(.{ .op = .neg, .ty = .i64, .a = step, .span = span }), span), .span = span });
    const whole = try b.emit(.{ .op = .div, .ty = .u64, .a = distance, .b = magnitude, .span = span });
    const remainder = try b.emit(.{ .op = .rem, .ty = .u64, .a = distance, .b = magnitude, .span = span });
    const extra = try select(Context, b, try compare(Context, b, .ne, remainder, try b.constant(.u64, 0), span), try b.constant(.u64, 1), try b.constant(.u64, 0), span);
    const selected = try b.emit(.{ .op = .add, .ty = .u64, .a = whole, .b = extra, .span = span });
    return sliceCopy(Context, b, source, .{ .first = first, .step = step, .count = selected }, span);
}

fn sliceCopy(comptime Context: type, b: Context, source: ir.Ref, plan: Slice, span: u32) Error!ir.Ref {
    const ty = b.typeOfRef(source);
    const element = b.module().compound(ty).list;
    const list_slot = try b.synthetic(ty);
    const counter_slot = try b.synthetic(.u64);
    const index_slot = try b.synthetic(.i64);
    try b.write(list_slot, b.current.?, try fresh(Context, b, source, plan.count, span));
    try b.write(counter_slot, b.current.?, try b.constant(.u64, 0));
    try b.write(index_slot, b.current.?, plan.first);
    const header = try b.newBlock();
    const body = try b.newBlock();
    const end = try b.newBlock();
    try b.jump(header);
    b.enter(header);
    const counter = try b.read(counter_slot, header);
    const index = try b.read(index_slot, header);
    try b.branch(try compare(Context, b, .lt, counter, plan.count, span), body, end, span);
    try b.seal(body);
    b.enter(body);
    const borrowed = try b.emit(.{ .op = .list_get, .ty = element, .a = source, .b = index, .check = .exact, .span = span });
    const value = if (b.module().zero_rc) try @import("single_owner_copy.zig").copy(Context, b, borrowed, span) else borrowed;
    const current = b.current.?;
    const pushed = try b.emit(.{ .op = .list_push, .ty = ty, .a = try b.read(list_slot, current), .b = value, .span = span });
    try b.write(list_slot, current, pushed);
    try b.write(counter_slot, current, try b.emit(.{ .op = .add, .ty = .u64, .a = counter, .b = try b.constant(.u64, 1), .span = span }));
    try b.write(index_slot, current, try b.emit(.{ .op = .add, .ty = .i64, .a = index, .b = plan.step, .span = span }));
    try b.jump(header);
    try b.seal(header);
    try b.seal(end);
    b.enter(end);
    return b.read(list_slot, end);
}

fn compose(comptime Context: type, b: Context, target: ir.Ref, source: ir.Ref, reverse: bool, span: u32) Error!ir.Ref {
    const ty = b.typeOfRef(target);
    const element = b.module().compound(ty).list;
    const count = try b.emit(.{ .op = .list_len, .ty = .u64, .a = source, .span = span });
    const list_slot = try b.synthetic(ty);
    const index_slot = try b.synthetic(.u64);
    try b.write(list_slot, b.current.?, target);
    try b.write(index_slot, b.current.?, try b.constant(.u64, 0));
    const header = try b.newBlock();
    const body = try b.newBlock();
    const exit = try b.newBlock();
    try b.jump(header);
    b.enter(header);
    const index = try b.read(index_slot, header);
    const more = try b.emit(.{ .op = .cmp, .ty = .bool, .a = index, .b = count, .data = @backingInt(ir.Predicate.lt), .span = span });
    try b.branch(more, body, exit, span);
    try b.seal(body);
    b.enter(body);
    const selected = if (reverse) try b.emit(.{ .op = .sub, .ty = .u64, .a = try b.emit(.{ .op = .sub, .ty = .u64, .a = count, .b = try b.constant(.u64, 1), .span = span }), .b = index, .span = span }) else index;
    // Self-extension reads the original prefix through the current owner: a
    // previous push may have grown and freed the old outer block. Each child
    // is independently copied once before insertion, including self-extension.
    const input = if (b.module().zero_rc and b.function.resolve(source) == b.function.resolve(target)) try b.read(list_slot, body) else source;
    const borrowed = if (element == .void) try b.emit(.{ .op = .undef, .ty = .void }) else try b.emit(.{ .op = .list_get, .ty = element, .a = input, .b = selected, .check = .exact, .span = span });
    const value = if (b.module().zero_rc) try @import("single_owner_copy.zig").copy(Context, b, borrowed, span) else borrowed;
    const current = b.current.?;
    const pushed = try b.emit(.{ .op = .list_push, .ty = ty, .a = try b.read(list_slot, current), .b = value, .span = span });
    try b.write(list_slot, current, pushed);
    try b.write(index_slot, current, try b.emit(.{ .op = .add, .ty = .u64, .a = index, .b = try b.constant(.u64, 1), .span = span }));
    try b.jump(header);
    try b.seal(header);
    try b.seal(exit);
    b.enter(exit);
    return b.read(list_slot, exit);
}
