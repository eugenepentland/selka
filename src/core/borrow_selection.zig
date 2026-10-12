//! Exact compiler markers for a dictionary lookup borrowing either evaluated input.
const std = @import("std");
const ir = @import("ir.zig");
const flags = @import("flags.zig");

pub const prefix = "myl_core_borrow_select_v1_";
pub const Error = error{UnsupportedInstruction};

/// Selected bytes borrow both roots until their last use; neither root transfers.
pub const Selection = struct {
    value: ir.Ref,
    dictionary: ir.Ref,
    fallback: ir.Ref,
    phi: ?ir.Ref,
};

/// Allocate the canonical identity from the exact physical signature.
pub fn name(a: std.mem.Allocator, dictionary: ir.Type, value: ir.Type) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(a, "{s}{d}_{d}", .{ prefix, @backingInt(dictionary), @backingInt(value) });
}

fn number(text: []const u8) ?ir.Type {
    if (text.len == 0) return null;
    if (text.len > 1 and text[0] == '0') return null;
    for (text) |byte| if (byte < '0' or byte > '9') return null;
    return @fromBackingInt(std.fmt.parseInt(u32, text, 10) catch return null);
}

/// A reserved prefix never grants authority to a malformed or source C declaration.
pub fn declaration(module: *const ir.Module, function: *const ir.Function) Error!bool {
    if (!std.mem.startsWith(u8, function.name, prefix)) return false;
    const suffix = function.name[prefix.len..];
    const split = std.mem.indexOfScalar(u8, suffix, '_') orelse return error.UnsupportedInstruction;
    const dictionary = number(suffix[0..split]) orelse return error.UnsupportedInstruction;
    const value = number(suffix[split + 1 ..]) orelse return error.UnsupportedInstruction;
    if (!module.zero_rc) return error.UnsupportedInstruction;
    if (!module.valid(dictionary) or !module.valid(value)) return error.UnsupportedInstruction;
    if (module.kind(dictionary) != .dict or !module.managed(value)) return error.UnsupportedInstruction;
    if (module.compound(dictionary).dict.value != value) return error.UnsupportedInstruction;
    const signature = function.signature;
    if (signature.linkage != .runtime_c or signature.params.len != 3) return error.UnsupportedInstruction;
    if (signature.ret != value or !std.mem.eql(ir.Type, signature.params, &.{ value, dictionary, value })) return error.UnsupportedInstruction;
    if ((signature.owned | signature.consumes | signature.views) != 0) return error.UnsupportedInstruction;
    if (function.blocks.items.len != 0 or function.insts.items.len != 0) return error.UnsupportedInstruction;
    return true;
}

/// Resolve copies with a finite bound, including malformed hand-built IR cycles.
pub fn resolve(function: *const ir.Function, raw: ir.Ref) Error!ir.Ref {
    var value = raw;
    var remaining = function.insts.items.len;
    while (remaining != 0) : (remaining -= 1) {
        if (value == .none or value.index() >= function.insts.items.len) return error.UnsupportedInstruction;
        const inst = function.inst(value);
        if (inst.op != .copy) return value;
        value = inst.a;
    }
    return error.UnsupportedInstruction;
}

fn operands(function: *const ir.Function, data: u64) Error![]const ir.Ref {
    const range = ir.ExtraSlice.unpack(data);
    if (range.start > function.extra.items.len) return error.UnsupportedInstruction;
    if (range.len > function.extra.items.len - range.start) return error.UnsupportedInstruction;
    return function.extra.items[range.start..][0..range.len];
}

fn entry(function: *const ir.Function, raw: ir.Ref, dictionary: ir.Ref) Error!bool {
    const value = try resolve(function, raw);
    const inst = function.inst(value);
    if (inst.op != .dict_entry_value or flags.transferredRead(inst)) return false;
    const owner = try resolve(function, inst.a);
    return owner == dictionary;
}

/// Recognize only a validated get selection or its trivial resolved hit/miss.
/// The ordinary verifier separately checks operand types and dominance.
pub fn call(module: *const ir.Module, function: *const ir.Function, inst: ir.Inst) Error!?Selection {
    if (inst.op != .call) return null;
    if (inst.a.index() >= module.functions.items.len) return error.UnsupportedInstruction;
    if (!try declaration(module, &module.functions.items[inst.a.index()])) return null;
    const args = try operands(function, inst.data);
    if (args.len != 3) return error.UnsupportedInstruction;
    const value = try resolve(function, args[0]);
    const dictionary = try resolve(function, args[1]);
    const fallback = try resolve(function, args[2]);
    const signature = module.functions.items[inst.a.index()].signature;
    if (inst.ty != signature.ret) return error.UnsupportedInstruction;
    for (args, signature.params) |argument, ty| {
        if (function.inst(try resolve(function, argument)).ty != ty) return error.UnsupportedInstruction;
    }
    const result: Selection = .{ .value = value, .dictionary = dictionary, .fallback = fallback, .phi = null };
    if (value == fallback or try entry(function, value, dictionary)) return result;
    const selected = function.inst(value);
    if (selected.op != .phi) return error.UnsupportedInstruction;
    const values = try operands(function, selected.data);
    if (values.len != 2 or selected.ty != inst.ty) return error.UnsupportedInstruction;
    for (values) |operand| {
        if (function.inst(try resolve(function, operand)).ty != inst.ty) return error.UnsupportedInstruction;
    }
    const first = try resolve(function, values[0]);
    const second = try resolve(function, values[1]);
    const hit_first = try entry(function, first, dictionary);
    const hit_second = try entry(function, second, dictionary);
    const hit_then_fallback = hit_first and second == fallback;
    const fallback_then_hit = hit_second and first == fallback;
    if (!hit_then_fallback and !fallback_then_hit) return error.UnsupportedInstruction;
    return .{ .value = value, .dictionary = dictionary, .fallback = fallback, .phi = value };
}

/// Validate before effects/optimizer scans can inspect marker operand tables.
pub fn validateModule(a: std.mem.Allocator, module: *const ir.Module) (Error || std.mem.Allocator.Error)!void {
    for (module.functions.items) |*function| {
        _ = try declaration(module, function);
        try validate(a, module, function);
    }
}

/// Always-on proof at the ownership boundary, including phi arity and uniqueness.
/// Ordinary IR dominance remains the general verifier's responsibility.
pub fn validate(a: std.mem.Allocator, module: *const ir.Module, function: *const ir.Function) (Error || std.mem.Allocator.Error)!void {
    var any_marker = false;
    for (function.insts.items) |inst| {
        if (inst.op != .call or inst.a.index() >= module.functions.items.len) continue;
        if (std.mem.startsWith(u8, module.functions.items[inst.a.index()].name, prefix)) any_marker = true;
    }
    if (!any_marker) return;
    var borrowed: std.AutoHashMapUnmanaged(ir.Ref, void) = .empty;
    defer borrowed.deinit(a);
    var phis: std.AutoHashMapUnmanaged(ir.Ref, Selection) = .empty;
    defer phis.deinit(a);
    var block_of = try a.alloc(?usize, function.insts.items.len);
    defer a.free(block_of);
    @memset(block_of, null);
    for (function.blocks.items, 0..) |block, index| {
        for (block.insts.items) |ref| {
            if (ref.index() >= block_of.len) return error.UnsupportedInstruction;
            block_of[ref.index()] = index;
        }
    }
    for (function.insts.items, 0..) |inst, index| {
        const selection = (try call(module, function, inst)) orelse continue;
        try borrowed.put(a, @fromBackingInt(@intCast(index)), {});
        const phi = selection.phi orelse continue;
        try borrowed.put(a, phi, {});
        const block = block_of[phi.index()] orelse return error.UnsupportedInstruction;
        if (function.blocks.items[block].preds.items.len != 2) return error.UnsupportedInstruction;
        const previous = try phis.getOrPut(a, phi);
        if (previous.found_existing) {
            const old = previous.value_ptr.*;
            if (old.dictionary != selection.dictionary or old.fallback != selection.fallback) return error.UnsupportedInstruction;
        } else previous.value_ptr.* = selection;
    }
    for (function.insts.items, 0..) |inst, index| {
        if (inst.op == .phi and phis.contains(@fromBackingInt(@intCast(index)))) continue;
        if (inst.op.hasExtra()) _ = try operands(function, inst.data);
        const values = function.valueOperands(inst);
        for (0..values.len()) |k| {
            const value = try resolve(function, values.get(k));
            if (borrowed.contains(value) and takes(module, function, inst, k)) return error.UnsupportedInstruction;
        }
    }
}

fn takes(module: *const ir.Module, function: *const ir.Function, inst: ir.Inst, index: usize) bool {
    if (index == 0 and inst.op.consumesOperand0()) return true;
    if (inst.op == .call) {
        if (inst.a.index() >= module.functions.items.len or index >= 64) return true;
        const signature = module.functions.items[inst.a.index()].signature;
        return (signature.owned | signature.consumes) & (@as(u64, 1) << @intCast(index)) != 0;
    }
    if (inst.op == .call_indirect) {
        if (index == 0) return false;
        const callee = resolve(function, inst.a) catch return true;
        const ty = function.inst(callee).ty;
        if (module.kind(ty) != .@"fn" or index > 64) return true;
        const signature = module.compound(ty).@"fn";
        return (signature.owned | signature.consumes) & (@as(u64, 1) << @intCast(index - 1)) != 0;
    }
    return switch (inst.op) {
        .list_push, .record_set => true,
        .list_set, .list_set_field, .array_set, .dict_set_value, .dict_insert => index >= 2,
        .list_pop, .union_make, .union_take, .box_make, .box_take, .ret, .release, .record_make, .phi => true,
        else => false,
    };
}

/// Declare a compiler-only marker; source extern declarations cannot select it.
pub fn declare(a: std.mem.Allocator, module: *ir.Module, dictionary: ir.Type, value: ir.Type) (Error || std.mem.Allocator.Error)!u32 {
    const symbol = try name(a, dictionary, value);
    for (module.functions.items, 0..) |*function, index| {
        if (!std.mem.eql(u8, function.name, symbol)) continue;
        if (!try declaration(module, function)) return error.UnsupportedInstruction;
        return @intCast(index);
    }
    const index: u32 = @intCast(module.functions.items.len);
    const function: ir.Function = .{ .name = symbol, .signature = .{
        .params = try a.dupe(ir.Type, &.{ value, dictionary, value }),
        .ret = value,
        .linkage = .runtime_c,
    } };
    if (!try declaration(module, &function)) return error.UnsupportedInstruction;
    try module.functions.append(a, function);
    return index;
}
