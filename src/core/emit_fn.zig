//! Function, array and sort operation dispatch; S2-F fills the source lowering and sort.
const ir = @import("ir.zig");

/// Allocation or an unsupported IR representation can stop operation emission.
pub const Error = error{ OutOfMemory, UnsupportedEntry, UnsupportedInstruction };

/// Emit indirect calls and fixed-array accesses; unfinished sort traps precisely.
pub fn instruction(context: anytype, out: anytype, name: []const u8, inst: ir.Inst) Error!void {
    switch (inst.op) {
        .call_indirect => try context.call(out, name, inst),
        .array_get, .array_set => try arrayAccess(context, out, name, inst),
        else => try context.unsupported(out, name, inst),
    }
}

fn arrayAccess(context: anytype, out: anytype, name: []const u8, inst: ir.Inst) Error!void {
    const a = context.a();
    const m = context.state.module;
    const ty = context.typeOf(inst.a);
    const array = m.compound(ty).array;
    const index = try context.widened(out, inst.b);
    if (inst.check != .proven or context.state.options.verify) {
        const bad = try context.fresh("%array");
        try out.print(a, "  {s} = icmp uge i64 {s}, {d}\n", .{ bad, index, array.n });
        try context.trapIf(out, bad, try context.site(.list_bounds, inst, "index"), index, try @import("std").fmt.allocPrint(a, "{d}", .{array.n}));
    }
    const slot = try context.stackSlot(m.size(ty));
    try context.storeValue(out, ty, try context.value(inst.a), slot);
    const at = try context.fresh("%array");
    const memory_type = try @import("std").fmt.allocPrint(a, "[{d} x [{d} x i8]]", .{ array.n, m.size(array.elem) });
    try out.print(a, "  {s} = getelementptr inbounds {s}, ptr {s}, i64 0, i64 {s}\n", .{ at, memory_type, slot, index });
    if (inst.op == .array_get) return context.loadValue(out, array.elem, at, name);
    try context.storeValue(out, array.elem, try context.value(context.function.operands(inst.data)[0]), at);
    try context.loadValue(out, ty, slot, name);
}
