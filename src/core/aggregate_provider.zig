//! The provider pin markers (`myl_core_provider_pin_`) and the root of a scoped provider. Since 5C a capability is a scalar
//! handle and no build emits a pin or a keepalive; the marker validation stays so that a cached body or a stored snapshot
//! that names one is still checked exactly.
const std = @import("std");
const typed = @import("selka").typed;
const ir = @import("ir.zig");
pub const Error = error{UnsupportedInstruction};

/// Compiler-only borrowed marker; its physical type is part of the exact identity.
pub const prefix = "myl_core_provider_pin_";

/// Scoped field providers must be projections of a named local, not temporaries.
pub fn root(program: typed.Program, source: typed.NodeId) ?typed.LocalId {
    var cursor = source;
    while (true) switch (program.nodes[@backingInt(cursor)].data) {
        .local => |slot| return slot,
        .field => |field| cursor = field.base,
        else => return null,
    };
}

/// Whether `symbol` is the canonical name of a provider pin marker: the prefix and the key of one type. The type is the
/// marker's parameter, never read from the name.
pub fn isMarker(symbol: []const u8) bool {
    return std.mem.startsWith(u8, symbol, prefix) and @import("stable_names.zig").isKeyList(symbol[prefix.len..], 1);
}

/// Validate the complete borrowed compiler marker before omitting its machine code.
pub fn marker(module: *const ir.Module, function: *const ir.Function) error{UnsupportedInstruction}!bool {
    if (!std.mem.startsWith(u8, function.name, prefix)) return false;
    if (!isMarker(function.name) or function.signature.params.len != 1) return error.UnsupportedInstruction;
    const ty = function.signature.params[0];
    if (!ty.isCompound() or @backingInt(ty) - ir.Type.first_compound >= module.compounds.items.len) return error.UnsupportedInstruction;
    const signature = function.signature;
    const optional_provider = module.kind(ty) == .@"union" and std.mem.eql(ir.Type, module.compound(ty).@"union", &.{ .void, .capability });
    if (module.kind(ty) != .record and !optional_provider) return error.UnsupportedInstruction;
    if (signature.linkage != .runtime_c or signature.ret != .void) return error.UnsupportedInstruction;
    if (!signature.passing.eql(.{})) return error.UnsupportedInstruction;
    if (function.blocks.items.len != 0 or function.insts.items.len != 0) return error.UnsupportedInstruction;
    return true;
}

fn operands(function: *const ir.Function, data: u64) Error![]const ir.Ref {
    const range = ir.ExtraSlice.unpack(data);
    if (range.start > function.extra.items.len or range.len > function.extra.items.len - range.start) return error.UnsupportedInstruction;
    return function.extra.items[range.start..][0..range.len];
}

/// Core observes this borrow until lexical cleanup; emitted code needs no operation.
pub fn call(module: *const ir.Module, function: *const ir.Function, inst: ir.Inst) Error!bool {
    if (inst.op != .call) return false;
    if (inst.a == .none or inst.a.index() >= module.functions.items.len) return error.UnsupportedInstruction;
    const callee = &module.functions.items[inst.a.index()];
    if (!try marker(module, callee)) return false;
    if (inst.ty != .void) return error.UnsupportedInstruction;
    const args = try operands(function, inst.data);
    if (args.len != 1) return error.UnsupportedInstruction;
    const argument = try @import("borrow_selection.zig").resolve(function, args[0]);
    if (function.inst(argument).ty != callee.signature.params[0]) return error.UnsupportedInstruction;
    return true;
}

/// Check exact call tables before the shared CFG/type/dominance verifier runs.
pub fn validate(module: *const ir.Module, function: *const ir.Function) Error!void {
    for (function.blocks.items) |block| for (block.insts.items) |ref| {
        if (ref == .none or ref.index() >= function.insts.items.len) return error.UnsupportedInstruction;
    };
    for (function.insts.items) |inst| {
        if (!module.valid(inst.ty)) return error.UnsupportedInstruction;
        if (inst.op.hasExtra()) _ = try operands(function, inst.data);
        const values = function.valueOperands(inst);
        for (0..values.len()) |index| _ = try @import("borrow_selection.zig").resolve(function, values.get(index));
        _ = try call(module, function, inst);
    }
}
