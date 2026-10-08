//! Function, fixed-array and stable-sort operation emission.
const ir = @import("ir.zig");

/// Allocation or an unsupported IR representation can stop operation emission.
pub const Error = error{ OutOfMemory, UnsupportedEntry, UnsupportedInstruction };

/// Emit indirect calls, checked fixed-array accesses and consuming stable sorts.
pub fn instruction(context: anytype, out: anytype, name: []const u8, inst: ir.Inst) Error!void {
    switch (inst.op) {
        .call_indirect => try context.call(out, name, inst),
        .array_get, .array_set => try arrayAccess(context, out, name, inst),
        .list_sort => {
            const module = context.state.module;
            const kind = @import("build_fn.zig").sortKind(module.*, module.compound(inst.ty).list) orelse return error.UnsupportedInstruction;
            try out.print(context.a(), "  {s} = call ptr @{s}(ptr {s}, i64 {d}, i1 {s})\n", .{ name, @import("flags.zig").list_sort_symbol, try context.value(inst.a), kind, try context.value(inst.b) });
        },
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
        const length = try @import("std").fmt.allocPrint(a, "{d}", .{array.n});
        // A negative index the program wrote is reported as written, recovered on the cold path.
        try context.trapBounds(out, bad, try context.site(.list_bounds, inst, "index"), .{ .index = index, .len = length, .from_end = context.countsFromEnd(inst.b) });
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
