//! Byte-buffer appends inline (NEW-CORE-CE-LISTS-6).
//!
//! The builder lowers `buffer.append_range(source, start, end)` (and `append_utf8`) as two
//! runtime calls: `myl_core_buffer_range_valid(source, start, end)`, the method's result,
//! and `myl_core_buffer_append_checked(buffer, source, start, end)`, which takes the buffer
//! over, copies it when shared, and appends the octets when the range is valid. The first
//! becomes its comparisons, `0 <= start <= end <= len(source)`; the second a
//! `buffer_append`, an update like any other: ownership gives it its copy-on-write form,
//! and the emitter appends in place when the range is non-empty, valid and fits the
//! buffer's room, and calls the runtime only to grow it (or to append nothing).
//!
//! Runs in `own.function` before copy on write, so the facts never see the new operation.
const std = @import("std");
const ir = @import("ir.zig");

/// The pass only allocates.
pub const Error = std.mem.Allocator.Error;

/// The runtime append the builder calls, and the slow path of `buffer_append`.
pub const append_symbol = "myl_core_buffer_append_checked";
/// The runtime range test the builder calls.
const valid_symbol = "myl_core_buffer_range_valid";

/// Rewrite every buffer append and range test of `f`; returns how many appends.
pub fn appends(arena: std.mem.Allocator, module: *const ir.Module, f: *ir.Function) Error!u32 {
    var rewritten: u32 = 0;
    for (f.blocks.items) |*block| {
        var rebuilt: std.ArrayList(ir.Ref) = .empty;
        var changed = false;
        for (block.insts.items) |ref| {
            const inst = f.inst(ref);
            if (inst.op != .call or inst.a.index() >= module.functions.items.len) {
                try rebuilt.append(arena, ref);
                continue;
            }
            const callee = module.functions.items[inst.a.index()];
            const arguments = f.operands(inst.data);
            // A buffer appended to itself stays a call: the call retains the source it borrows
            // (the same block it takes over), so the runtime copies the buffer before growing it.
            const into_itself = arguments.len == 4 and f.resolve(arguments[0]) == f.resolve(arguments[1]);
            if (std.mem.eql(u8, callee.name, append_symbol) and arguments.len == 4 and !into_itself) {
                // Copied out first: appending may move `f.extra`, which `arguments` points into.
                const operands = [4]ir.Ref{ arguments[0], arguments[1], arguments[2], arguments[3] };
                const extra: u32 = @intCast(f.extra.items.len);
                try f.extra.appendSlice(arena, operands[2..4]);
                f.insts.items[ref.index()] = .{ .op = .buffer_append, .ty = .byte_buffer, .a = operands[0], .b = operands[1], .data = (ir.ExtraSlice{ .start = extra, .len = 2 }).pack(), .span = inst.span };
                rewritten += 1;
                changed = true;
            } else if (std.mem.eql(u8, callee.name, valid_symbol) and arguments.len == 3 and inst.ty == .bool) {
                try rangeTest(arena, f, .{ .ref = ref, .source = arguments[0], .start = arguments[1], .end = arguments[2], .span = inst.span }, &rebuilt);
                changed = true;
                continue;
            }
            try rebuilt.append(arena, ref);
        }
        if (changed) block.insts = rebuilt;
    }
    return rewritten;
}

/// One range test to expand in place of its call.
const Test = struct { ref: ir.Ref, source: ir.Ref, start: ir.Ref, end: ir.Ref, span: u32 };

/// `start >= 0 and end >= start and end <= len(source)`, the runtime test's own rule,
/// defined at the call's reference.
fn rangeTest(arena: std.mem.Allocator, f: *ir.Function, t: Test, into: *std.ArrayList(ir.Ref)) Error!void {
    const zero = try constant(arena, f, 0);
    const source_type = f.inst(f.resolve(t.source)).ty;
    const nonnegative = try emit(arena, f, into, .{ .op = .cmp, .ty = .bool, .a = t.start, .b = zero, .data = @backingInt(ir.Predicate.ge), .span = t.span });
    const ordered = try emit(arena, f, into, .{ .op = .cmp, .ty = .bool, .a = t.end, .b = t.start, .data = @backingInt(ir.Predicate.ge), .span = t.span });
    const length = try emit(arena, f, into, .{ .op = if (source_type == .str) .str_len else .list_len, .ty = .u64, .a = t.source, .span = t.span });
    const wide = try emit(arena, f, into, .{ .op = .convert, .ty = .i64, .a = length, .span = t.span });
    const inside = try emit(arena, f, into, .{ .op = .cmp, .ty = .bool, .a = t.end, .b = wide, .data = @backingInt(ir.Predicate.le), .span = t.span });
    const both = try emit(arena, f, into, .{ .op = .bit_and, .ty = .bool, .a = nonnegative, .b = ordered, .span = t.span });
    f.insts.items[t.ref.index()] = .{ .op = .bit_and, .ty = .bool, .a = both, .b = inside, .span = t.span };
    try into.append(arena, t.ref);
}

fn emit(arena: std.mem.Allocator, f: *ir.Function, into: *std.ArrayList(ir.Ref), inst: ir.Inst) Error!ir.Ref {
    const ref: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
    try f.insts.append(arena, inst);
    try into.append(arena, ref);
    return ref;
}

fn constant(arena: std.mem.Allocator, f: *ir.Function, value: i64) Error!ir.Ref {
    const ref: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
    try f.insts.append(arena, .{ .op = .iconst, .ty = .i64, .data = @bitCast(value) });
    return ref;
}
