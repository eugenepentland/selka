//! Mutable-byte IR executes on the shared 32-byte counted-leaf layout.
const std = @import("std");
const ir = @import("ir.zig");
const flags = @import("flags.zig");
const buffers = @import("buffers.zig");
const byte_index = @import("byte_index.zig");

/// Byte emission has the LLVM emitter's allocation/unsupported failures.
pub const Error = error{ OutOfMemory, UnsupportedEntry, UnsupportedInstruction };

/// Recover the source index for an authorized adapter's located failure report.
pub fn sourceIndex(comptime Context: type, context: Context, offset: ir.Ref) ?ir.Ref {
    const inst = context.function.inst(context.function.resolve(offset));
    if (!byte_index.adapter(context.state.module, inst)) return null;
    return context.function.operands(inst.data)[1];
}

/// Emit the authorized byte-index adapter without a foreign call.
pub fn runtimeCall(comptime Context: type, comptime Output: type, context: Context, out: Output, name: []const u8, inst: ir.Inst) Error!bool {
    if (!byte_index.adapter(context.state.module, inst)) return false;
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
        .buffer_push => {
            const symbol = switch (inst.data) {
                flags.buffer_append_int => flags.buffer_int_symbol,
                flags.buffer_append_float => flags.buffer_float_symbol,
                else => "myl_core_buffer_push",
            };
            const scalar = switch (inst.data) {
                flags.buffer_append_int => "i64",
                flags.buffer_append_float => "double",
                else => "i8 zeroext",
            };
            if (inst.data == flags.buffer_append_int or inst.data == flags.buffer_append_float) try formatter(context, symbol, scalar);
            try out.print(a, "  {s} = call ptr @{s}(ptr {s}, {s} {s})\n", .{ name, symbol, try context.value(inst.a), scalar, try context.value(inst.b) });
        },
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
        .buffer_append => try append(@TypeOf(context), context, out, .{ .name = name, .inst = inst }),
        else => try context.unsupported(out, name, inst),
    }
}

/// `buffer_append` (NEW-CORE-CE-LISTS-6): the buffer is unique here (ownership tested or
/// copied it), so a non-empty range inside the source that fits the buffer's room is
/// copied in place and the length raised; anything else (growth, an empty or invalid
/// range) goes to the runtime's checked append, which grows the buffer or appends nothing.
fn append(comptime Context: type, context: Context, out: *std.ArrayList(u8), site: Append) Error!void {
    const a = context.a();
    const name = site.name;
    const inst = site.inst;
    const range = context.function.operands(inst.data);
    const buffer = try context.value(inst.a);
    const source = try context.value(inst.b);
    const start = try context.value(range[0]);
    const end = try context.value(range[1]);
    try declare(Context, context, buffers.append_symbol, "ptr, ptr, i64, i64");
    const len = try header(Context, context, out, .{ .block = buffer, .offset = 8 });
    const cap = try header(Context, context, out, .{ .block = buffer, .offset = 16 });
    const source_len = try header(Context, context, out, .{ .block = source, .offset = 8 });
    const count = try context.fresh("%apn");
    const room = try context.fresh("%apr");
    try out.print(a, "  {s} = sub i64 {s}, {s}\n  {s} = sub i64 {s}, {s}\n", .{ count, end, start, room, cap.value, len.value });
    // Non-empty, starting inside the source, ending inside it, and fitting the room.
    const tests = [_][4][]const u8{
        .{ "sgt", count, "0", "" },
        .{ "sge", start, "0", "" },
        .{ "sle", end, source_len.value, "" },
        .{ "sle", count, room, "" },
    };
    var fast_test: []const u8 = "true";
    for (tests) |t| {
        const holds = try context.fresh("%apk");
        const both = try context.fresh("%apk");
        try out.print(a, "  {s} = icmp {s} i64 {s}, {s}\n  {s} = and i1 {s}, {s}\n", .{ holds, t[0], t[1], t[2], both, fast_test, holds });
        fast_test = both;
    }
    const fast = try context.fresh("append.fast");
    const slow = try context.fresh("append.slow");
    const join = try context.fresh(context.label);
    try out.print(a, "  br i1 {s}, label %{s}, label %{s}, !prof !10\n{s}:\n", .{ fast_test, fast, slow, fast });
    const to = try context.fresh("%apd");
    const from = try context.fresh("%apf");
    const grown = try context.fresh("%apg");
    try out.print(a, "  {s} = getelementptr inbounds i8, ptr {s}, i64 32\n  {s}.at = getelementptr inbounds i8, ptr {s}, i64 {s}\n", .{ to, buffer, to, to, len.value });
    try out.print(a, "  {s} = getelementptr inbounds i8, ptr {s}, i64 32\n  {s}.at = getelementptr inbounds i8, ptr {s}, i64 {s}\n", .{ from, source, from, from, start });
    try out.print(a, "  call void @llvm.memmove.p0.p0.i64(ptr {s}.at, ptr {s}.at, i64 {s}, i1 false)\n", .{ to, from, count });
    try out.print(a, "  {s} = add i64 {s}, {s}\n  store i64 {s}, ptr {s}, align 8, !tbaa !5\n  br label %{s}\n", .{ grown, len.value, count, grown, len.at, join });
    const called = try context.fresh("%apcall");
    // The call keeps the append's source position, so a trap while growing names it.
    try out.print(a, "{s}:\n  {s} = call ptr @{s}(ptr {s}, ptr {s}, i64 {s}, i64 {s}){s}\n  br label %{s}\n", .{ slow, called, buffers.append_symbol, buffer, source, start, end, try context.callLocation(inst.span), join });
    try out.print(a, "{s}:\n  {s} = phi ptr [ {s}, %{s} ], [ {s}, %{s} ]\n", .{ join, name, buffer, fast, called, slow });
    context.label = join;
}

/// The `buffer_append` being emitted: the name it defines and the instruction.
const Append = struct { name: []const u8, inst: ir.Inst };

/// One `i64` header field of a block (length at 8, capacity at 16) and its address.
const Field = struct { at: []const u8, value: []const u8 };

/// A header field to load: the block and the field's offset.
const HeaderField = struct { block: []const u8, offset: u32 };

fn header(comptime Context: type, context: Context, out: *std.ArrayList(u8), field: HeaderField) Error!Field {
    const at = try context.fresh("%aph");
    const value = try context.fresh("%aph");
    try out.print(context.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 {d}\n  {s} = load i64, ptr {s}, align 8, !tbaa !5\n", .{ at, field.block, field.offset, value, at });
    return .{ .at = at, .value = value };
}

/// Declare runtime helper `symbol` once per unit (a Core call to it declares it the same way).
fn declare(comptime Context: type, context: Context, symbol: []const u8, params: []const u8) Error!void {
    for (context.state.declared.items) |known| if (std.mem.eql(u8, known, symbol)) return;
    try context.state.declared.append(context.a(), symbol);
    try context.state.externs.print(context.a(), "declare ptr @{s}({s}) nounwind\n", .{ symbol, params });
}

fn formatter(context: anytype, symbol: []const u8, scalar: []const u8) !void {
    // Numeric buffer operations name runtime helpers without a Core call. Declare
    // that dependency in this unit, including imported bodies, only when reached.
    try declare(@TypeOf(context), context, symbol, try std.fmt.allocPrint(context.a(), "ptr, {s}", .{scalar}));
}
