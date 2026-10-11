//! Emit the compiler's private whitespace cursors as bounded byte loops.
const std = @import("std");
const ir = @import("ir.zig");
const space_name = "%splitspace";
const length_name = "%splitlen";

/// Allocation or an unsupported IR representation can stop cursor emission.
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
    if (try prefixCall(Context, Output, context, out, name, inst)) return true;
    if (try explicitCall(Context, Output, context, out, name, inst)) return true;
    const skip_space = adapter(context.state.module, inst) orelse return false;
    const args = context.function.operands(inst.data);
    if (args.len != 2) return false;
    if (context.typeOf(args[0]) != .str or context.typeOf(args[1]) != .i64) return false;
    const receiver = try context.value(args[0]);
    const initial = try context.value(args[1]);
    const previous = context.label;
    const length_at = try context.fresh(length_name);
    const length = try context.fresh(length_name);
    const data = try context.fresh("%splitdata");
    const scan = try context.fresh("splitscan");
    const read = try context.fresh("splitread");
    const advance = try context.fresh("splitadvance");
    const join = try context.fresh("splitjoin");
    const cursor = try context.fresh("%splitcursor");
    const next = try context.fresh("%splitnext");
    const nonnegative = try context.fresh("%splitnonnegative");
    const below = try context.fresh("%splitbelow");
    const within = try context.fresh("%splitwithin");
    const setup = "  {s} = getelementptr inbounds i8, ptr {s}, i64 8\n" ++
        "  {s} = load i64, ptr {s}, align 8\n" ++
        "  {s} = getelementptr inbounds i8, ptr {s}, i64 32\n  br label %{s}\n{s}:\n" ++
        "  {s} = phi i64 [ {s}, %{s} ], [ {s}, %{s} ]\n" ++
        "  {s} = icmp sge i64 {s}, 0\n  {s} = icmp slt i64 {s}, {s}\n" ++
        "  {s} = and i1 {s}, {s}\n  br i1 {s}, label %{s}, label %{s}\n{s}:\n";
    try out.print(context.a(), setup, .{
        length_at, receiver, length,   length_at,   data,    receiver,    scan,   scan,
        cursor,    initial,  previous, next,        advance, nonnegative, cursor, below,
        cursor,    length,   within,   nonnegative, below,   within,      read,   join,
        read,
    });
    const pointer = try context.fresh("%splitbyte");
    const byte = try context.fresh("%splitbyte");
    const blank = try context.fresh("%splitblank");
    const shifted = try context.fresh(space_name);
    const control = try context.fresh(space_name);
    const space = try context.fresh(space_name);
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

/// Inline the validated next cursor and single-octet separator search.
pub fn explicitCall(comptime Context: type, comptime Output: type, context: Context, out: Output, name: []const u8, inst: ir.Inst) Error!bool {
    if (inst.op != .call or inst.ty != .i64) return false;
    const module = context.state.module;
    const callee = module.functions.items[inst.a.index()];
    const signature = callee.signature;
    if (signature.linkage != .runtime_c or signature.owned != 0 or signature.views != 0) return false;
    if (!std.mem.eql(ir.Type, signature.params, &.{ .str, .str, .i64 })) return false;
    const next = std.mem.eql(u8, callee.name, "myl_core_split_next");
    const args = context.function.operands(inst.data);
    if (!next and !std.mem.eql(u8, callee.name, "myl_core_split_end")) return false;
    const separator = context.function.inst(context.function.resolve(args[1]));
    const single = separator.op == .str_const and module.strings.items[@intCast(separator.data)].len == 1;
    if (!next and !single) return false;
    const receiver = try context.value(args[0]);
    const index = try context.value(args[2]);
    const at = try context.fresh(length_name);
    const len = try context.fresh(length_name);
    try out.print(context.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 8\n  {s} = load i64, ptr {s}, align 8\n", .{ at, receiver, len, at });
    if (next) {
        const sep_at = try context.fresh("%seplen");
        const sep_len = try context.fresh("%seplen");
        const done = try context.fresh("%splitdone");
        const advanced = try context.fresh("%splitadvance");
        try out.print(context.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 8\n  {s} = load i64, ptr {s}, align 8\n", .{ sep_at, try context.value(args[1]), sep_len, sep_at });
        try out.print(context.a(), "  {s} = icmp eq i64 {s}, {s}\n  {s} = add i64 {s}, {s}\n  {s} = select i1 {s}, i64 -1, i64 {s}\n", .{ done, index, len, advanced, index, sep_len, name, done, advanced });
    } else try singleEnd(Context, Output, context, out, name, .{ .receiver = receiver, .index = index, .len = len, .byte = module.strings.items[@intCast(separator.data)][0] });
    return true;
}

const End = struct { receiver: []const u8, index: []const u8, len: []const u8, byte: u8 };
fn singleEnd(comptime Context: type, comptime Output: type, context: Context, out: Output, name: []const u8, args: End) Error!void {
    const data = try context.fresh("%splitdata");
    const start = try context.fresh("%splitstart");
    const remaining = try context.fresh("%splitremaining");
    const found = try context.fresh("%splitfound");
    const missing = try context.fresh("%splitmissing");
    const address = try context.fresh("%splitaddress");
    const base = try context.fresh("%splitbase");
    const offset = try context.fresh("%splitoffset");
    try out.print(context.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 32\n  {s} = getelementptr inbounds i8, ptr {s}, i64 {s}\n", .{ data, args.receiver, start, data, args.index });
    try out.print(context.a(), "  {s} = sub i64 {s}, {s}\n  {s} = call ptr @memchr(ptr {s}, i32 {d}, i64 {s})\n", .{ remaining, args.len, args.index, found, start, args.byte, remaining });
    try out.print(context.a(), "  {s} = icmp eq ptr {s}, null\n  {s} = ptrtoint ptr {s} to i64\n  {s} = ptrtoint ptr {s} to i64\n", .{ missing, found, address, found, base, data });
    try out.print(context.a(), "  {s} = sub i64 {s}, {s}\n  {s} = select i1 {s}, i64 {s}, i64 {s}\n", .{ offset, address, base, name, missing, args.len, offset });
}

// A private fixed-index split's bounded offset prefix lives in an entry-frame slot.
// Its saturated header is never published and ownership never puts it on a heap free list.
fn prefixCall(comptime Context: type, comptime Output: type, context: Context, out: Output, name: []const u8, inst: ir.Inst) Error!bool {
    if (inst.op != .call) return false;
    const module = context.state.module;
    const callee = module.functions.items[inst.a.index()];
    if (callee.signature.linkage != .runtime_c or callee.signature.owned != 0) return false;
    const str = std.mem.startsWith(u8, callee.name, "myl_core_str_split_prefix_");
    const span = std.mem.startsWith(u8, callee.name, "myl_core_span_split_prefix_");
    if (!str and !span) return false;
    if (!std.mem.eql(ir.Type, callee.signature.params, &.{ .str, .str })) return false;
    if (callee.signature.views != @as(u64, if (span) 3 else 0)) return false;
    if (module.kind(inst.ty) != .list) return false;
    const element = module.compound(inst.ty).list;
    if (module.kind(element) != .record) return false;
    if (!std.mem.eql(ir.Type, module.compound(element).record, &.{ .u64, .u64 })) return false;
    const digit = callee.name[callee.name.len - 1];
    if (digit < '1' or digit > '8') return false;
    const capacity: u32 = digit - '0';
    const slot = try context.stackSlot(32 + capacity * 16);
    if (!module.zero_rc) try out.print(context.a(), "  store i32 -1, ptr {s}, align 8\n", .{slot});
    const kind = try context.fresh("%splitkind");
    const cap = try context.fresh("%splitcap");
    const reserved = try context.fresh("%splitreserved");
    try out.print(context.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 {d}\n  store i32 {d}, ptr {s}, align 4\n", .{ kind, slot, module.kindOffset(), @as(u32, if (module.zero_rc) 1 << 23 else 0), kind });
    try out.print(context.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 16\n  store i64 {d}, ptr {s}, align 8\n", .{ cap, slot, capacity, cap });
    try out.print(context.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 24\n  store i64 0, ptr {s}, align 8\n", .{ reserved, slot, reserved });
    const args = context.function.operands(inst.data);
    const input = try context.spanArgument(out, args[0]);
    const separator = try context.spanArgument(out, args[1]);
    try out.print(context.a(), "  call void @myl_core_span_split_fill({s}, {s}, ptr {s}, i64 {d})\n  {s} = getelementptr inbounds i8, ptr {s}, i64 0\n", .{ input, separator, slot, capacity, name, slot });
    return true;
}
