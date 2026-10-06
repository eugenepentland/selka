//! Mutable-byte IR executes on the shared 32-byte counted-leaf layout.
const std = @import("std");
const ir = @import("ir.zig");

/// Byte emission has the LLVM emitter's allocation/unsupported failures.
pub const Error = error{ OutOfMemory, UnsupportedEntry, UnsupportedInstruction };

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
