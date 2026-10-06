//! Mutable-byte IR executes on the shared 32-byte counted-leaf layout.
const std = @import("std");
const ir = @import("ir.zig");

/// Byte emission has the LLVM emitter's allocation/unsupported failures.
pub const Error = error{ OutOfMemory, UnsupportedEntry, UnsupportedInstruction };

/// Inline the compiler's byte-index adapter so LLVM can see the offset and bounds.
/// A source extern with the same symbol has no runtime authority.
fn indexAdapter(module: *const ir.Module, inst: ir.Inst) bool {
    if (inst.op != .call) return false;
    const callee = module.functions.items[inst.a.index()];
    const signature = callee.signature;
    if (signature.linkage != .runtime_c or signature.ret != .u64) return false;
    if (signature.params.len != 2 or signature.params[1] != .i64) return false;
    if (signature.params[0] != .bytes and signature.params[0] != .byte_buffer) return false;
    if (signature.owned != 0 or signature.views != 0) return false;
    if (!std.mem.eql(u8, callee.name, "myl_core_bytes_index_offset")) return false;
    return true;
}

/// Recover the source index for an authorized adapter's located failure report.
pub fn sourceIndex(comptime Context: type, context: Context, offset: ir.Ref) ?ir.Ref {
    const inst = context.function.inst(context.function.resolve(offset));
    if (!indexAdapter(context.state.module, inst)) return null;
    return context.function.operands(inst.data)[1];
}

/// Emit the authorized byte-index adapter without a foreign call.
pub fn runtimeCall(comptime Context: type, comptime Output: type, context: Context, out: Output, name: []const u8, inst: ir.Inst) Error!bool {
    if (!indexAdapter(context.state.module, inst)) return false;
    const operands = context.function.operands(inst.data);
    const receiver = try context.value(operands[0]);
    const index = try context.value(operands[1]);
    const at = try context.fresh("%bylen");
    const len = try context.fresh("%bylen");
    const negative = try context.fresh("%bynegative");
    const adjusted = try context.fresh("%byadjusted");
    // Only negative indices select the sum. The unselected positive sum may wrap;
    // unflagged LLVM addition has defined modular semantics and creates no poison.
    try out.print(context.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 8\n" ++
        "  {s} = load i64, ptr {s}, align 8, !tbaa !5\n" ++
        "  {s} = icmp slt i64 {s}, 0\n" ++
        "  {s} = add i64 {s}, {s}\n" ++
        "  {s} = select i1 {s}, i64 {s}, i64 {s}\n", .{ at, receiver, len, at, negative, index, adjusted, index, len, name, negative, adjusted, index });
    return true;
}

/// Runtime declarations for the frozen buffer instruction shapes.
pub fn prelude(allocator: std.mem.Allocator, out: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
    try out.appendSlice(allocator,
        \\declare ptr @myl_core_buffer_new(i64) nounwind
        \\declare ptr @myl_core_buffer_copy(ptr) nounwind
        \\declare ptr @myl_core_buffer_push(ptr, i8 zeroext) nounwind
        \\declare ptr @myl_core_buffer_set(ptr, i64, i8 zeroext) nounwind
        \\declare ptr @myl_core_buffer_pop(ptr) nounwind
        \\
    );
}

/// Emit buffer updates; ownership supplies COW and verified uniqueness before mutation.
pub fn instruction(context: anytype, out: anytype, name: []const u8, inst: ir.Inst) Error!void {
    const a = context.a();
    switch (inst.op) {
        .buffer_new => try out.print(a, "  {s} = call ptr @myl_core_buffer_new(i64 {s})\n", .{ name, try context.value(inst.a) }),
        .buffer_copy => try out.print(a, "  {s} = call ptr @myl_core_buffer_copy(ptr {s})\n", .{ name, try context.value(inst.a) }),
        .buffer_push => try out.print(a, "  {s} = call ptr @myl_core_buffer_push(ptr {s}, i8 zeroext {s})\n", .{ name, try context.value(inst.a), try context.value(inst.b) }),
        .buffer_set => {
            const receiver = try context.value(inst.a);
            const index = try context.widened(out, inst.b);
            try context.boundsCheck(out, inst, receiver, index);
            try out.print(a, "  {s} = call ptr @myl_core_buffer_set(ptr {s}, i64 {s}, i8 zeroext {s})\n", .{ name, receiver, index, try context.value(context.function.operands(inst.data)[0]) });
        },
        .buffer_pop => {
            const at = try context.fresh("%buflen");
            const len = try context.fresh("%buflen");
            const empty = try context.fresh("%bufempty");
            try out.print(a, "  {s} = getelementptr inbounds i8, ptr {s}, i64 8\n  {s} = load i64, ptr {s}, align 8\n  {s} = icmp eq i64 {s}, 0\n", .{ at, try context.value(inst.a), len, at, empty, len });
            try context.trapIf(out, empty, try context.site(.list_empty, inst, "pop"), "0", len);
            try out.print(a, "  {s} = call ptr @myl_core_buffer_pop(ptr {s})\n", .{ name, try context.value(inst.a) });
        },
        else => try context.unsupported(out, name, inst),
    }
}
