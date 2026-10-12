//! Flat local contexts borrowing immutable provider parameters for one invocation.
const std = @import("std");
const typed = @import("mylang").typed;
const ir = @import("ir.zig");

pub const prefix = "myl_core_borrowed_provider_v1_";
pub const Error = error{UnsupportedInstruction};
// The first contract uses bounded flat records and bounded parameter projections.
pub const max_fields = 64;
pub const max_projection_depth = 64;

fn provider(ty: typed.Type) bool {
    return ty.capabilityIndex() != null and !ty.isStream() and ty != .host_cap;
}

fn scalar(program: typed.Program, ty: typed.Type) bool {
    if (ty.isInteger() or ty == .bool or ty == .unit) return true;
    if (ty == .stream_cap or ty == .host_cap) return true;
    if (!ty.isAggregate() or ty.recordIndex() >= program.records.len) return false;
    const record = program.records[ty.recordIndex()];
    return record.shape.domain != null and std.mem.eql(u8, record.name, "float");
}

/// One exact immutable parameter root; no local aliases, calls or origin inference.
fn sourceParameter(program: typed.Program, function: typed.Function, raw: typed.NodeId) bool {
    var at = raw;
    for (0..max_projection_depth) |_| {
        if (@backingInt(at) >= program.nodes.len) return false;
        const node = program.nodes[@backingInt(at)];
        switch (node.data) {
            .local => |slot| {
                const index = @backingInt(slot);
                if (index >= 64 or index >= function.signature.parameter_count or index >= function.scope.locals.len) return false;
                const local = function.scope.locals[index];
                return !local.mutable and !typed.moveOnly(local.ty, program.records) and !local.ty.isFile();
            },
            .field => |field| {
                if (@backingInt(field.base) >= program.nodes.len) return false;
                const ty = program.nodes[@backingInt(field.base)].ty;
                if (!ty.isAggregate() or ty.recordIndex() >= program.records.len) return false;
                const record = program.records[ty.recordIndex()];
                if (field.index >= record.fields.len or record.fields[field.index].boxed) return false;
                if (record.fields[field.index].ty != node.ty) return false;
                at = field.base;
            },
            else => return false,
        }
    }
    return false;
}

/// Used only for a direct local initializer by both source checking and lowering.
/// Nested borrowed contexts and mixed owned-managed/provider storage do not qualify.
pub fn initializer(program: typed.Program, function: typed.Function, id: typed.NodeId) bool {
    if (@backingInt(id) >= program.nodes.len) return false;
    const node = program.nodes[@backingInt(id)];
    if (!node.ty.isAggregate() or node.ty.recordIndex() >= program.records.len) return false;
    const record = program.records[node.ty.recordIndex()];
    if (record.managed or record.isCollection() or record.collection.box) return false;
    if (record.shape.array != null or record.shape.variants != null or record.shape.resource != null) return false;
    if (record.shape.domain != null or record.contract.callback != null) return false;
    if (record.fields.len == 0 or record.fields.len > max_fields) return false;
    var has_provider = false;
    for (record.fields) |field| {
        if (field.boxed) return false;
        if (provider(field.ty)) has_provider = true else if (!scalar(program, field.ty)) return false;
    }
    if (!has_provider) return false;
    const fields = switch (node.data) {
        .record => |fields| fields,
        else => return false,
    };
    if (fields.len != record.fields.len) return false;
    var seen: u64 = 0;
    for (fields) |field| {
        if (field.index >= record.fields.len or @backingInt(field.value) >= program.nodes.len) return false;
        const bit = @as(u64, 1) << @intCast(field.index);
        if (seen & bit != 0) return false;
        seen |= bit;
        const ty = record.fields[field.index].ty;
        if (program.nodes[@backingInt(field.value)].ty != ty) return false;
        if (provider(ty) and !sourceParameter(program, function, field.value)) return false;
    }
    return true;
}

/// Canonical physical identity; parsing a name never admits its declaration alone.
pub fn markerType(symbol: []const u8) ?ir.Type {
    if (!std.mem.startsWith(u8, symbol, prefix)) return null;
    const digits = symbol[prefix.len..];
    if (digits.len == 0 or digits[0] == '0') return null;
    for (digits) |digit| if (digit < '0' or digit > '9') return null;
    const ty: ir.Type = @fromBackingInt(std.fmt.parseInt(u32, digits, 10) catch return null);
    return if (ty.isCompound()) ty else null;
}

fn physicalScalar(ty: ir.Type) bool {
    if (ty.integer() != null or ty == .bool or ty == .void) return true;
    return ty == .f64 or ty == .cap;
}

/// Validate every field and all ABI bits, including a declaration with no body.
pub fn declaration(module: *const ir.Module, function: *const ir.Function) Error!bool {
    if (!std.mem.startsWith(u8, function.name, prefix)) return false;
    const ty = markerType(function.name) orelse return error.UnsupportedInstruction;
    if (!module.zero_rc or !module.valid(ty)) return error.UnsupportedInstruction;
    if (module.kind(ty) != .record) return error.UnsupportedInstruction;
    const fields = module.compound(ty).record;
    if (fields.len == 0 or fields.len > max_fields) return error.UnsupportedInstruction;
    var has_provider = false;
    for (fields) |field| {
        if (field == .capability) has_provider = true else if (!physicalScalar(field)) return error.UnsupportedInstruction;
    }
    if (!has_provider) return error.UnsupportedInstruction;
    const sig = function.signature;
    if (sig.linkage != .runtime_c or sig.ret != ty or !std.mem.eql(ir.Type, fields, sig.params)) return error.UnsupportedInstruction;
    if (sig.owned != 0 or sig.consumes != 0 or sig.views != 0) return error.UnsupportedInstruction;
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
                if (inst.data >= function.signature.params.len or inst.data >= 64) return error.UnsupportedInstruction;
                if (function.signature.params[@intCast(inst.data)] != inst.ty) return error.UnsupportedInstruction;
                const bit = @as(u64, 1) << @intCast(inst.data);
                if ((function.signature.owned | function.signature.consumes) & bit != 0) return error.UnsupportedInstruction;
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
pub fn keepalive(module: *const ir.Module, function: *const ir.Function) Error!bool {
    if (!std.mem.eql(u8, function.name, "myl_core_provider_keepalive")) return false;
    const sig = function.signature;
    if (!module.zero_rc or function.span != 0 or sig.linkage != .runtime_c) return error.UnsupportedInstruction;
    if (sig.ret != .void or !std.mem.eql(ir.Type, sig.params, &.{.capability})) return error.UnsupportedInstruction;
    if (sig.owned != 0 or sig.consumes != 0 or sig.views != 0) return error.UnsupportedInstruction;
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
        if (std.mem.startsWith(u8, module.functions.items[inst.a.index()].name, prefix)) return true;
    }
    return false;
}

// twin-drift-ok: Provider contexts have variable field signatures; selections have three operands. Each marker must validate its own complete ABI.
/// A declaration is compiler-created; source extern declarations cannot select it.
pub fn declare(a: std.mem.Allocator, module: *ir.Module, ty: ir.Type) (Error || std.mem.Allocator.Error)!u32 {
    if (!module.valid(ty) or module.kind(ty) != .record) return error.UnsupportedInstruction;
    const symbol = try std.fmt.allocPrint(a, "{s}{d}", .{ prefix, @backingInt(ty) });
    for (module.functions.items, 0..) |*function, index| {
        if (!std.mem.eql(u8, function.name, symbol)) continue;
        if (!try declaration(module, function)) return error.UnsupportedInstruction;
        return @intCast(index);
    }
    const index: u32 = @intCast(module.functions.items.len);
    const function: ir.Function = .{ .name = symbol, .signature = .{
        .params = try a.dupe(ir.Type, module.compound(ty).record),
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
        if (inst.op == .copy or inst.op == .record_get) {
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
