//! Exact compiler markers for a dictionary lookup borrowing either evaluated input.
const std = @import("std");
const ir = @import("ir.zig");
const flags = @import("flags.zig");

pub const prefix = "myl_core_borrow_select_v1_";
pub const choice_prefix = "myl_core_borrow_choice_v1_";
/// Exact generated choice operations sharing a two-owner borrowed result.
pub const Kind = enum { min_text, max_text, optional_default };

/// Recognize reserved compiler marker names before their complete validation.
pub fn reserved(symbol: []const u8) bool {
    return std.mem.startsWith(u8, symbol, prefix) or std.mem.startsWith(u8, symbol, choice_prefix);
}
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

const Identity = struct { kind: ?Kind = null, first: ir.Type, value: ir.Type };

fn identity(symbol: []const u8) Error!?Identity {
    if (!reserved(symbol)) return null;
    var suffix: []const u8 = undefined;
    var kind: ?Kind = null;
    if (std.mem.startsWith(u8, symbol, choice_prefix)) {
        suffix = symbol[choice_prefix.len..];
        // Kind names contain underscores, so match an exact delimited name.
        inline for (.{ Kind.min_text, Kind.max_text, Kind.optional_default }) |choice| {
            const tag = @tagName(choice);
            if (std.mem.startsWith(u8, suffix, tag ++ "_")) {
                kind = choice;
                suffix = suffix[tag.len + 1 ..];
                break;
            }
        }
        if (kind == null) return error.UnsupportedInstruction;
    } else suffix = symbol[prefix.len..];
    const split = std.mem.indexOfScalar(u8, suffix, '_') orelse return error.UnsupportedInstruction;
    return .{
        .kind = kind,
        .first = number(suffix[0..split]) orelse return error.UnsupportedInstruction,
        .value = number(suffix[split + 1 ..]) orelse return error.UnsupportedInstruction,
    };
}

const Optional = struct { tag: usize, payload: ir.Type };

/// Only a two-case optional containing one managed value and one empty case.
fn optional(module: *const ir.Module, first: ir.Type, value: ir.Type) ?Optional {
    if (module.kind(first) != .@"union") return null;
    const cases = module.compound(first).@"union";
    if (cases.len != 2) return null;
    const tag: usize = if (cases[0] == .void) 1 else if (cases[1] == .void) 0 else return null;
    const payload = cases[tag];
    if (payload == value) return .{ .tag = tag, .payload = payload };
    if (!module.valid(payload) or module.kind(payload) != .box) return null;
    if (module.compound(payload).box != value) return null;
    return .{ .tag = tag, .payload = payload };
}

fn validIdentity(module: *const ir.Module, id: Identity) bool {
    if (!module.valid(id.first) or !module.valid(id.value)) return false;
    if (!module.managed(id.value)) return false;
    if (id.kind) |kind| return switch (kind) {
        .min_text, .max_text => id.first == .str and id.value == .str,
        .optional_default => optional(module, id.first, id.value) != null,
    };
    return module.kind(id.first) == .dict and module.compound(id.first).dict.value == id.value;
}

/// A reserved prefix never grants authority to a malformed or source C declaration.
pub fn declaration(module: *const ir.Module, function: *const ir.Function) Error!bool {
    const id = (try identity(function.name)) orelse return false;
    if (!module.zero_rc or !validIdentity(module, id)) return error.UnsupportedInstruction;
    const signature = function.signature;
    if (signature.linkage != .runtime_c or signature.params.len != 3) return error.UnsupportedInstruction;
    if (signature.ret != id.value or !std.mem.eql(ir.Type, signature.params, &.{ id.value, id.first, id.value })) return error.UnsupportedInstruction;
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

fn firstValue(module: *const ir.Module, function: *const ir.Function, raw: ir.Ref, first: ir.Ref, id: Identity) Error!bool {
    if (id.kind) |kind| switch (kind) {
        .min_text, .max_text => {
            const value = try resolve(function, raw);
            return value == first;
        },
        .optional_default => {
            const shape = optional(module, id.first, id.value) orelse return error.UnsupportedInstruction;
            var value = try resolve(function, raw);
            if (shape.payload != id.value) {
                const box = function.inst(value);
                if (box.op != .box_get or box.ty != id.value) return false;
                value = try resolve(function, box.a);
            }
            const payload = function.inst(value);
            return payload.op == .union_payload and payload.ty == shape.payload and payload.data == shape.tag and try resolve(function, payload.a) == first;
        },
    };
    return entry(function, raw, first);
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
    const callee = &module.functions.items[inst.a.index()];
    const signature = callee.signature;
    const id = (try identity(callee.name)).?;
    if (inst.ty != signature.ret) return error.UnsupportedInstruction;
    for (args, signature.params) |argument, ty| {
        if (function.inst(try resolve(function, argument)).ty != ty) return error.UnsupportedInstruction;
    }
    const result: Selection = .{ .value = value, .dictionary = dictionary, .fallback = fallback, .phi = null };
    if (value == fallback or try firstValue(module, function, value, dictionary, id)) return result;
    const selected = function.inst(value);
    if (selected.op != .phi) return error.UnsupportedInstruction;
    const values = try operands(function, selected.data);
    if (values.len != 2 or selected.ty != inst.ty) return error.UnsupportedInstruction;
    for (values) |operand| {
        if (function.inst(try resolve(function, operand)).ty != inst.ty) return error.UnsupportedInstruction;
    }
    const first = try resolve(function, values[0]);
    const second = try resolve(function, values[1]);
    const hit_first = try firstValue(module, function, first, dictionary, id);
    const hit_second = try firstValue(module, function, second, dictionary, id);
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
        if (reserved(module.functions.items[inst.a.index()].name)) any_marker = true;
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

/// Whether this operand transfers ownership or stores a borrowed value.
pub fn takes(module: *const ir.Module, function: *const ir.Function, inst: ir.Inst, index: usize) bool {
    if (index == 0 and inst.op.consumesOperand0()) return true;
    if (inst.op == .call) {
        if (inst.a == .none or inst.a.index() >= module.functions.items.len or index >= 64) return true;
        const signature = module.functions.items[inst.a.index()].signature;
        return (signature.owned | signature.consumes) & (@as(u64, 1) << @intCast(index)) != 0;
    }
    if (inst.op == .call_indirect) {
        if (index == 0) return false;
        const callee = resolve(function, inst.a) catch return true;
        const ty = function.inst(callee).ty;
        if (!module.valid(ty)) return true;
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
    return declareNamed(a, module, symbol, dictionary, value);
}

/// Min/max and optional defaults share the same nonconsuming two-root contract.
pub fn declareChoice(a: std.mem.Allocator, module: *ir.Module, kind: Kind, first: ir.Type, value: ir.Type) (Error || std.mem.Allocator.Error)!u32 {
    const symbol = try std.fmt.allocPrint(a, "{s}{s}_{d}_{d}", .{ choice_prefix, @tagName(kind), @backingInt(first), @backingInt(value) });
    return declareNamed(a, module, symbol, first, value);
}

fn declareNamed(a: std.mem.Allocator, module: *ir.Module, symbol: []const u8, dictionary: ir.Type, value: ir.Type) (Error || std.mem.Allocator.Error)!u32 {
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
