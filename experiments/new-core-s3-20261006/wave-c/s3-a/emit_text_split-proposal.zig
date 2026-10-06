//! Emit the compiler's private whitespace cursors as bounded byte loops.
const std = @import("std");
const ir = @import("ir.zig");

pub const Error = error{ OutOfMemory, UnsupportedEntry, UnsupportedInstruction };

/// Return the cursor's separator polarity only for its exact trusted declaration.
pub fn adapter(module: *const ir.Module, inst: ir.Inst) ?bool {
    if (inst.op != .call or inst.ty != .i64 or inst.a.index() >= module.functions.items.len) return null;
    const callee = module.functions.items[inst.a.index()];
    const signature = callee.signature;
    if (signature.linkage != .runtime_c or signature.ret != .i64) return null;
    if (signature.owned != 0 or signature.views != 0) return null;
    if (!std.mem.eql(ir.Type, signature.params, &.{ .str, .i64 })) return null;
    if (std.mem.eql(u8, callee.name, "myl_core_split_ws_start")) return true;
    if (std.mem.eql(u8, callee.name, "myl_core_split_ws_end")) return false;
    return null;
}

/// Bound every byte read by the immutable source length and preserve label joins.
pub fn runtimeCall(comptime Context: type, comptime Output: type, context: Context, out: Output, name: []const u8, inst: ir.Inst) Error!bool {
    const skip_space = adapter(context.state.module, inst) orelse return false;
    const args = context.function.operands(inst.data);
    if (args.len != 2) return false;
    const receiver = try context.value(args[0]);
    const initial = try context.value(args[1]);
    const previous = context.label;
    const length_at = try context.fresh("%splitlen");
    const length = try context.fresh("%splitlen");
    const data = try context.fresh("%splitdata");
    const scan = try context.fresh("splitscan");
    const read = try context.fresh("splitread");
    const advance = try context.fresh("splitadvance");
    const join = try context.fresh("splitjoin");
    const cursor = try context.fresh("%splitcursor");
    const next = try context.fresh("%splitnext");
    const within = try context.fresh("%splitwithin");
    const setup = "  {s} = getelementptr inbounds i8, ptr {s}, i64 8\n" ++
        "  {s} = load i64, ptr {s}, align 8\n" ++
        "  {s} = getelementptr inbounds i8, ptr {s}, i64 32\n  br label %{s}\n{s}:\n" ++
        "  {s} = phi i64 [ {s}, %{s} ], [ {s}, %{s} ]\n" ++
        "  {s} = icmp slt i64 {s}, {s}\n  br i1 {s}, label %{s}, label %{s}\n{s}:\n";
    try out.print(context.a(), setup, .{ length_at, receiver, length, length_at, data, receiver, scan, scan, cursor, initial, previous, next, advance, within, cursor, length, within, read, join, read });
    const pointer = try context.fresh("%splitbyte");
    const byte = try context.fresh("%splitbyte");
    const blank = try context.fresh("%splitblank");
    const shifted = try context.fresh("%splitspace");
    const control = try context.fresh("%splitspace");
    const space = try context.fresh("%splitspace");
    const classify = "  {s} = getelementptr inbounds i8, ptr {s}, i64 {s}\n" ++
        "  {s} = load i8, ptr {s}, align 1\n  {s} = icmp eq i8 {s}, 32\n" ++
        "  {s} = sub i8 {s}, 9\n  {s} = icmp ule i8 {s}, 4\n" ++
        "  {s} = or i1 {s}, {s}\n";
    try out.print(context.a(), classify, .{ pointer, data, cursor, byte, pointer, blank, byte, shifted, byte, control, shifted, space, blank, control });
    const then = if (skip_space) advance else join;
    const otherwise = if (skip_space) join else advance;
    const finish = "  br i1 {s}, label %{s}, label %{s}\n{s}:\n" ++
        "  {s} = add i64 {s}, 1\n  br label %{s}\n{s}:\n  {s} = add i64 {s}, 0\n";
    try out.print(context.a(), finish, .{ space, then, otherwise, advance, next, cursor, scan, join, name, cursor });
    context.label = join;
    return true;
}
