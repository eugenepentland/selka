//! The IR markers of a flat local context that borrowed immutable provider parameters for one invocation (P5).
//! Since 5C a capability is a scalar handle and no build emits these markers; their validation stays so that a cached
//! body or a stored snapshot that names one is still checked exactly.
const std = @import("std");
const typed = @import("selka").typed;
const ir = @import("ir.zig");

pub const prefix = "myl_core_borrowed_provider_v1_";
pub const optional_prefix = "myl_core_borrowed_optional_provider_v1_";
pub const Error = error{UnsupportedInstruction};
// The first contract uses bounded flat records and bounded parameter projections.
pub const max_fields = 64;
pub const max_projection_depth = 64;

fn physicalOptional(module: *const ir.Module, ty: ir.Type) bool {
    return module.valid(ty) and module.kind(ty) == .@"union" and
        std.mem.eql(ir.Type, module.compound(ty).@"union", &.{ .void, .capability });
}

fn physicalScalar(ty: ir.Type) bool {
    if (ty.integer() != null or ty == .bool or ty == .void) return true;
    return ty == .f64 or ty == .cap;
}

/// Validate every field and all ABI bits, including a declaration with no body.
pub fn declaration(module: *const ir.Module, function: *const ir.Function) Error!bool {
    const is_optional = std.mem.startsWith(u8, function.name, optional_prefix);
    if (!is_optional and !std.mem.startsWith(u8, function.name, prefix)) return false;
    // The name holds the key of the provider's type and no position; the type is the signature's result.
    const family: []const u8 = if (is_optional) optional_prefix else prefix;
    if (!@import("stable_names.zig").isKeyList(function.name[family.len..], 1)) return error.UnsupportedInstruction;
    const ty = function.signature.ret;
    if (!ty.isCompound() or !module.valid(ty)) return error.UnsupportedInstruction;
    if (is_optional and !physicalOptional(module, ty)) return error.UnsupportedInstruction;
    if (!is_optional and module.kind(ty) != .record) return error.UnsupportedInstruction;
    const fields: []const ir.Type = if (is_optional) &.{.capability} else module.compound(ty).record;
    if (fields.len == 0 or fields.len > max_fields) return error.UnsupportedInstruction;
    var has_provider = false;
    for (fields) |field| {
        if (field == .capability) has_provider = true else if (!physicalScalar(field)) return error.UnsupportedInstruction;
    }
    if (!has_provider) return error.UnsupportedInstruction;
    const sig = function.signature;
    if (sig.linkage != .runtime_c or sig.ret != ty or !std.mem.eql(ir.Type, fields, sig.params)) return error.UnsupportedInstruction;
    if (!sig.passing.eql(.{})) return error.UnsupportedInstruction;
    if (function.blocks.items.len != 0 or function.insts.items.len != 0) return error.UnsupportedInstruction;
    return true;
}

fn checkedInst(function: *const ir.Function, ref: ir.Ref) Error!ir.Inst {
    if (ref == .none or ref.index() >= function.insts.items.len) return error.UnsupportedInstruction;
    return function.inst(ref);
}

fn operands(function: *const ir.Function, data: u64) Error![]const ir.Ref {
    const range = ir.ExtraSlice.unpack(data);
    if (range.start > function.extra.items.len or range.len > function.extra.items.len - range.start) return error.UnsupportedInstruction;
    return function.extra.items[range.start..][0..range.len];
}

/// A bounded copy/projection path rooted in a readonly parameter of this function.
fn parameter(module: *const ir.Module, function: *const ir.Function, raw: ir.Ref) Error!void {
    var ref = raw;
    for (0..max_projection_depth) |_| {
        const inst = try checkedInst(function, ref);
        switch (inst.op) {
            .param => {
                if (inst.data >= function.signature.params.len) return error.UnsupportedInstruction;
                if (function.signature.params[@intCast(inst.data)] != inst.ty) return error.UnsupportedInstruction;
                if (function.signature.passing.takes(@intCast(inst.data))) return error.UnsupportedInstruction;
                return;
            },
            .record_get => {
                const base = try checkedInst(function, inst.a);
                if (!module.valid(base.ty) or module.kind(base.ty) != .record) return error.UnsupportedInstruction;
                const fields = module.compound(base.ty).record;
                if (inst.data >= fields.len or fields[@intCast(inst.data)] != inst.ty) return error.UnsupportedInstruction;
                ref = inst.a;
            },
            .copy => {
                if ((try checkedInst(function, inst.a)).ty != inst.ty) return error.UnsupportedInstruction;
                ref = inst.a;
            },
            else => return error.UnsupportedInstruction,
        }
    }
    return error.UnsupportedInstruction;
}

/// The existing native helper is exactly a no-op borrow, never source FFI authority.
pub fn keepalive(_: *const ir.Module, function: *const ir.Function) Error!bool {
    if (!std.mem.eql(u8, function.name, "myl_core_provider_keepalive")) return false;
    const sig = function.signature;
    if (function.span != 0 or sig.linkage != .runtime_c) return error.UnsupportedInstruction;
    if (sig.ret != .void or !std.mem.eql(ir.Type, sig.params, &.{.capability})) return error.UnsupportedInstruction;
    if (!sig.passing.eql(.{})) return error.UnsupportedInstruction;
    if (function.blocks.items.len != 0 or function.insts.items.len != 0) return error.UnsupportedInstruction;
    return true;
}

/// The call constructs its inline borrowed record directly, with no owned intermediate.
pub fn call(module: *const ir.Module, function: *const ir.Function, inst: ir.Inst) Error!?[]const ir.Ref {
    if (inst.op != .call) return null;
    if (inst.a == .none or inst.a.index() >= module.functions.items.len) return error.UnsupportedInstruction;
    const callee = &module.functions.items[inst.a.index()];
    if (!try declaration(module, callee)) return null;
    if (inst.ty != callee.signature.ret) return error.UnsupportedInstruction;
    const args = try operands(function, inst.data);
    if (args.len != callee.signature.params.len) return error.UnsupportedInstruction;
    for (args, callee.signature.params) |arg, ty| {
        if ((try checkedInst(function, arg)).ty != ty) return error.UnsupportedInstruction;
        if (ty == .capability) try parameter(module, function, arg);
    }
    return args;
}

/// Do not let a future inliner erase the parameter-root proof before ownership.
pub fn contains(module: *const ir.Module, function: *const ir.Function) bool {
    for (function.insts.items) |inst| {
        if (inst.op != .call or inst.a == .none or inst.a.index() >= module.functions.items.len) continue;
        const name = module.functions.items[inst.a.index()].name;
        if (std.mem.startsWith(u8, name, prefix) or std.mem.startsWith(u8, name, optional_prefix)) return true;
    }
    return false;
}

/// The family prefix of the marker for provider type `ty`: the optional form for an optional capability, else the record's.
pub fn prefixFor(module: *const ir.Module, ty: ir.Type) []const u8 {
    return if (physicalOptional(module, ty)) optional_prefix else prefix;
}

// twin-drift-ok: Provider contexts have variable field signatures; selections have three operands. Each marker must validate its own complete ABI.
/// A declaration is compiler-created; source extern declarations cannot select it. `symbol` is its name:
/// `prefixFor` and the key of `ty` (`stable_names.helperName`).
pub fn declare(a: std.mem.Allocator, module: *ir.Module, ty: ir.Type, symbol: []const u8) (Error || std.mem.Allocator.Error)!u32 {
    const is_optional = physicalOptional(module, ty);
    if (!is_optional) {
        if (!module.valid(ty) or module.kind(ty) != .record) return error.UnsupportedInstruction;
    }
    for (module.functions.items, 0..) |*function, index| {
        if (!std.mem.eql(u8, function.name, symbol)) continue;
        if (!try declaration(module, function)) return error.UnsupportedInstruction;
        return @intCast(index);
    }
    const index: u32 = @intCast(module.functions.items.len);
    const function: ir.Function = .{ .name = symbol, .signature = .{
        .params = try a.dupe(ir.Type, if (is_optional) &.{.capability} else module.compound(ty).record),
        .ret = ty,
        .linkage = .runtime_c,
    } };
    if (!try declaration(module, &function)) return error.UnsupportedInstruction;
    try module.functions.append(a, function);
    return index;
}

/// Verify before optimization and after cache restore. Propagate only copy/field
/// dependencies once via reverse edges; arbitrary ownership DAG inference is absent.
pub fn validate(a: std.mem.Allocator, module: *const ir.Module, function: *const ir.Function) (Error || std.mem.Allocator.Error)!void {
    if (!contains(module, function)) return;
    const count = function.insts.items.len;
    const none = std.math.maxInt(usize);
    const heads = try a.alloc(usize, count);
    defer a.free(heads);
    @memset(heads, none);
    const next = try a.alloc(usize, count);
    defer a.free(next);
    @memset(next, none);
    const borrowed = try a.alloc(bool, count);
    defer a.free(borrowed);
    @memset(borrowed, false);
    var queue: std.ArrayList(usize) = .empty;
    defer queue.deinit(a);
    for (function.insts.items, 0..) |inst, index| {
        if (inst.op == .copy or inst.op == .record_get or inst.op == .union_payload) {
            _ = try checkedInst(function, inst.a);
            next[index] = heads[inst.a.index()];
            heads[inst.a.index()] = index;
        }
        if ((try call(module, function, inst)) != null) {
            borrowed[index] = true;
            try queue.append(a, index);
        }
    }
    var at: usize = 0;
    while (at < queue.items.len) : (at += 1) {
        var child = heads[queue.items[at]];
        while (child != none) {
            // Scalar projections may freely escape; providers and contexts may not.
            const ty = function.insts.items[child].ty;
            if (!module.valid(ty)) return error.UnsupportedInstruction;
            if (module.managed(ty) and !borrowed[child]) {
                borrowed[child] = true;
                try queue.append(a, child);
            }
            child = next[child];
        }
    }
    for (function.insts.items) |inst| {
        if (inst.op.hasExtra()) _ = try operands(function, inst.data);
        const values = function.valueOperands(inst);
        for (0..values.len()) |index| {
            const value = values.get(index);
            _ = try checkedInst(function, value);
            if (borrowed[value.index()] and @import("borrow_selection.zig").takes(module, function, inst, index)) return error.UnsupportedInstruction;
        }
    }
}

/// Check all declarations, including unused malformed identities, before effects.
pub fn validateModule(a: std.mem.Allocator, module: *const ir.Module) (Error || std.mem.Allocator.Error)!void {
    for (module.functions.items) |*function| {
        _ = try declaration(module, function);
        try validate(a, module, function);
    }
}
