//! Text operation dispatch; S2-T extends the minimal hand-built IR support.
const std = @import("std");
const ir = @import("ir.zig");
const flags = @import("flags.zig");
const length_name = "%textlen";
const width_name = "%slicewidth";

/// Allocation or an unsupported IR representation can stop operation emission.
pub const Error = error{ OutOfMemory, UnsupportedEntry, UnsupportedInstruction };

/// Emit characters and SSA spans; unfinished text operations trap precisely.
pub fn instruction(context: anytype, out: anytype, name: []const u8, inst: ir.Inst) Error!void {
    const a = context.a();
    switch (inst.op) {
        .str_char => {
            try bounds(@TypeOf(context), @TypeOf(out), context, out, inst, .{ .receiver = inst.a, .offset = inst.b });
            try out.print(a, "  {s} = call ptr @myl_core_ir_str_char(ptr {s}, i64 {s})\n", .{ name, try context.value(inst.a), try context.value(inst.b) });
        },
        .str_width, .str_code => {
            if (inst.op == .str_code and inst.check == .exact) try bounds(@TypeOf(context), @TypeOf(out), context, out, inst, .{ .receiver = inst.a, .offset = inst.b });
            try scalar(@TypeOf(context), @TypeOf(out), context, out, name, inst);
        },
        .str_append => try out.print(a, "  {s} = call ptr @myl_core_ir_str_append(ptr {s}, ptr {s})\n", .{ name, try context.value(inst.a), try context.value(inst.b) }),
        .str_append_char => {
            const offset = context.function.operands(inst.data)[0];
            if (inst.check == .exact) try bounds(@TypeOf(context), @TypeOf(out), context, out, inst, .{ .receiver = inst.b, .offset = offset });
            if (isView(@TypeOf(context), context, inst.b)) {
                const pair = try context.value(inst.b);
                const data = try context.fresh("%textdata");
                const length = try context.fresh("%textlen");
                try out.print(a, "  {s} = extractvalue {{ ptr, i64 }} {s}, 0\n  {s} = extractvalue {{ ptr, i64 }} {s}, 1\n" ++
                    "  {s} = call ptr @myl_core_span_str_append_char(ptr {s}, ptr {s}, i64 {s}, i64 {s})\n", .{ data, pair, length, pair, name, try context.value(inst.a), data, length, try context.value(offset) });
                return;
            }
            try out.print(a, "  {s} = call ptr @myl_core_ir_str_append_char(ptr {s}, ptr {s}, i64 {s})\n", .{ name, try context.value(inst.a), try context.value(inst.b), try context.value(offset) });
        },
        .str_slice => try out.print(a, "  {s} = call ptr @myl_core_ir_str_slice(ptr {s}, i64 {s}, i64 {s})\n", .{ name, try context.value(inst.a), try context.value(inst.b), try context.value(context.function.operands(inst.data)[0]) }),
        .str_view_of => {
            const pointer = try context.fresh("%view");
            const data = try context.fresh("%view");
            const partial = try context.fresh("%view");
            if (context.function.inst(context.function.resolve(inst.a)).ty.isSpan()) {
                try out.print(a, "  {s} = extractvalue {{ ptr, i64 }} {s}, 0\n", .{ data, try context.value(inst.a) });
            } else try out.print(a, "  {s} = getelementptr inbounds i8, ptr {s}, i64 32\n", .{ data, try context.value(inst.a) });
            try out.print(a, "  {s} = getelementptr inbounds i8, ptr {s}, i64 {s}\n", .{ pointer, data, try context.value(inst.b) });
            try out.print(a, "  {s} = insertvalue {{ ptr, i64 }} poison, ptr {s}, 0\n  {s} = insertvalue {{ ptr, i64 }} {s}, i64 {s}, 1\n", .{ partial, pointer, name, partial, try context.value(context.function.operands(inst.data)[0]) });
        },
        .str_slice_view => try sliceView(@TypeOf(context), @TypeOf(out), context, out, name, inst),
        .str_slice_bytes_view => try sliceBytesView(@TypeOf(context), @TypeOf(out), context, out, name, inst),
        .str_from_view => {
            const pointer = try context.fresh("%view");
            const len = try context.fresh("%view");
            const view = try context.value(inst.a);
            try out.print(a, "  {s} = extractvalue {{ ptr, i64 }} {s}, 0\n  {s} = extractvalue {{ ptr, i64 }} {s}, 1\n", .{ pointer, view, len, view });
            const ascii = try sourceAscii(@TypeOf(context), @TypeOf(out), context, out, inst.a) orelse
                return out.print(a, "  {s} = call ptr @myl_core_ir_str_from_view(ptr {s}, i64 {s})\n", .{ name, pointer, len });
            try out.print(a, "  {s} = call ptr @myl_core_ir_str_from_span(ptr {s}, i64 {s}, i1 zeroext {s})\n", .{ name, pointer, len, ascii });
        },
        .text_frame => {
            // The cache owner of a plain `str` parameter (C9 S1): a sentinel owner is a frame header in this call's
            // entry-block stack slot, holding the span's length and no facts (kind STR, cap = len, reserved 0). The
            // header is a block that nothing else sees, so `core_text_can_cache` accepts it for anchor writes only.
            const header = try context.stackSlot(32);
            const view = try context.value(inst.b);
            const len = try context.fresh("%frame");
            const cap = try context.fresh("%frame");
            const reserved = try context.fresh("%frame");
            const at = try context.fresh("%frame");
            const sentinel = try context.fresh("%frame");
            try out.print(a, "  {s} = extractvalue {{ ptr, i64 }} {s}, 1\n  store i32 1, ptr {s}, align 8\n", .{ len, view, header });
            try out.print(a, "  {s} = getelementptr inbounds i8, ptr {s}, i64 8\n  store i64 {s}, ptr {s}, align 8\n", .{ at, header, len, at });
            try out.print(a, "  {s} = getelementptr inbounds i8, ptr {s}, i64 16\n  store i64 {s}, ptr {s}, align 8\n", .{ cap, header, len, cap });
            try out.print(a, "  {s} = getelementptr inbounds i8, ptr {s}, i64 24\n  store i64 0, ptr {s}, align 8\n", .{ reserved, header, reserved });
            try out.print(a, "  {s} = icmp eq ptr {s}, @myl_core_text_no_cache\n  {s} = select i1 {s}, ptr {s}, ptr {s}\n", .{ sentinel, try context.value(inst.a), name, sentinel, header, try context.value(inst.a) });
        },
        else => try context.unsupported(out, name, inst),
    }
}

/// NEW-CORE-S1-ASCII-1: whether the text a view borrows from is ASCII (an `i1`), when the
/// view's source is known; every span of an ASCII text is ASCII, so its copy skips the scan.
fn sourceAscii(comptime Context: type, comptime Output: type, context: Context, out: Output, view: ir.Ref) Error!?[]const u8 {
    const f = context.function;
    const borrow = f.inst(f.resolve(view));
    // An owner-explicit char slice borrows its owner's text, so the owner's ASCII fact holds for the span.
    const source: ir.Ref = if (borrow.op == .call) (sliceOwner(Context, context, borrow) orelse return null) else blk: {
        if (borrow.op != .str_view_of and borrow.op != .str_slice_view and borrow.op != .str_slice_bytes_view) return null;
        if (f.inst(f.resolve(borrow.a)).ty == .str_view) return sourceAscii(Context, Output, context, out, borrow.a);
        break :blk borrow.a;
    };
    const kind_at = try context.fresh("%viewkind");
    const kind = try context.fresh("%viewkind");
    const bit = try context.fresh("%viewascii");
    const ascii = try context.fresh("%viewascii");
    try out.print(context.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 {d}\n  {s} = load i32, ptr {s}, align 4\n  {s} = and i32 {s}, 256\n  {s} = icmp ne i32 {s}, 0\n", .{
        kind_at, try context.value(source), context.module().kindOffset(), kind, kind_at, bit, kind, ascii, bit,
    });
    return ascii;
}

/// The owner of an owner-explicit char slice (`myl_core_xc_slice(owner, text, start, end)`), or null for any other call.
fn sliceOwner(comptime Context: type, context: Context, inst: ir.Inst) ?ir.Ref {
    const module = context.state.module;
    if (inst.a.index() >= module.functions.items.len) return null;
    if (!std.mem.eql(u8, module.functions.items[inst.a.index()].name, "myl_core_xc_slice")) return null;
    const args = context.function.operands(inst.data);
    return if (args.len == 4) args[0] else null;
}

/// NEW-CORE-S1-VIEW-1: the span `str_slice` would copy, borrowed. An ASCII source's scalar
/// positions are its octet offsets, so its clamps are inline; any other source asks the
/// runtime for the same octet span `myl_core_ir_str_slice` copies.
fn sliceView(comptime Context: type, comptime Output: type, context: Context, out: Output, name: []const u8, inst: ir.Inst) Error!void {
    const a = context.a();
    const text = try context.value(inst.a);
    const start = try context.value(inst.b);
    const end = try context.value(context.function.operands(inst.data)[0]);
    const kind_at = try context.fresh("%slicekind");
    const kind = try context.fresh("%slicekind");
    const ascii_bit = try context.fresh("%sliceascii");
    const ascii = try context.fresh("%sliceascii");
    const fast = try context.fresh("slicefast");
    const slow = try context.fresh("sliceslow");
    const join = try context.fresh("slicejoin");
    const byte_source = context.function.inst(context.function.resolve(inst.a)).ty == .bytes or context.function.inst(context.function.resolve(inst.a)).ty == .byte_buffer;
    try out.print(a, "  {s} = getelementptr inbounds i8, ptr {s}, i64 {d}\n  {s} = load i32, ptr {s}, align 4\n" ++
        "  {s} = and i32 {s}, 256\n  {s} = icmp ne i32 {s}, 0\n  br i1 {s}, label %{s}, label %{s}\n{s}:\n", .{
        kind_at,   text, context.module().kindOffset(), kind,      kind_at,
        ascii_bit, kind, ascii,                         ascii_bit, if (byte_source) "true" else ascii,
        fast,      slow, fast,
    });
    const len_at = try context.fresh("%slicelen");
    const len = try context.fresh("%slicelen");
    try out.print(a, "  {s} = getelementptr inbounds i8, ptr {s}, i64 8\n  {s} = load i64, ptr {s}, align 8\n", .{ len_at, text, len, len_at });
    const low = try clamp(Context, Output, context, out, start, len);
    const high = try clamp(Context, Output, context, out, end, len);
    const width = try context.fresh(width_name);
    const empty = try context.fresh("%sliceempty");
    const fast_len = try context.fresh(width_name);
    try out.print(a, "  {s} = sub i64 {s}, {s}\n  {s} = icmp slt i64 {s}, 0\n  {s} = select i1 {s}, i64 0, i64 {s}\n  br label %{s}\n{s}:\n", .{ width, high, low, empty, width, fast_len, empty, width, join, slow });
    const span = try context.fresh("%slicespan");
    const slow_at = try context.fresh("%sliceat");
    const slow_len = try context.fresh(width_name);
    try context.cStructCall(out, .{ .name = span, .ty = "{ i64, i64 }", .bytes = 16 }, "@myl_core_ir_str_slice_span", try std.fmt.allocPrint(a, "ptr {s}, i64 {s}, i64 {s}", .{ text, start, end }));
    try out.print(a, "  {s} = extractvalue {{ i64, i64 }} {s}, 0\n  {s} = extractvalue {{ i64, i64 }} {s}, 1\n  br label %{s}\n{s}:\n", .{ slow_at, span, slow_len, span, join, join });
    const at = try context.fresh("%sliceat");
    const width_joined = try context.fresh(width_name);
    try out.print(a, "  {s} = phi i64 [ {s}, %{s} ], [ {s}, %{s} ]\n  {s} = phi i64 [ {s}, %{s} ], [ {s}, %{s} ]\n", .{ at, low, fast, slow_at, slow, width_joined, fast_len, fast, slow_len, slow });
    const data = try context.fresh("%slicedata");
    const pointer = try context.fresh("%slicedata");
    const partial = try context.fresh("%sliceview");
    try out.print(a, "  {s} = getelementptr inbounds i8, ptr {s}, i64 32\n  {s} = getelementptr inbounds i8, ptr {s}, i64 {s}\n", .{ data, text, pointer, data, at });
    try out.print(a, "  {s} = insertvalue {{ ptr, i64 }} poison, ptr {s}, 0\n  {s} = insertvalue {{ ptr, i64 }} {s}, i64 {s}, 1\n", .{ partial, pointer, name, partial, width_joined });
    context.label = join;
}

/// NEW-CORE-S1-VIEW-4: the octet range `myl_core_ir_str_slice_bytes` would copy,
/// borrowed. The runtime applies the same clamps and the same boundary trap, so a
/// view of valid text stays valid text and an endpoint inside a scalar still traps.
fn sliceBytesView(comptime Context: type, comptime Output: type, context: Context, out: Output, name: []const u8, inst: ir.Inst) Error!void {
    const a = context.a();
    const span = try context.fresh("%slicespans");
    const at = try context.fresh("%sliceats");
    const len = try context.fresh("%slicelens");
    const data = try context.fresh("%slicedatas");
    const pointer = try context.fresh("%slicedatas");
    const partial = try context.fresh("%sliceviews");
    const end = context.function.operands(inst.data)[0];
    // The trap site this view's boundary check reports: its own source line (B3).
    const site_index = try context.site(.text_boundary, inst, "slice");
    const arguments = try std.fmt.allocPrint(a, "ptr @myl.site.{d}, ptr {s}, i64 {s}, i64 {s}", .{ site_index, try context.value(inst.a), try context.value(inst.b), try context.value(end) });
    try context.cStructCall(out, .{ .name = span, .ty = "{ i64, i64 }", .bytes = 16 }, "@myl_core_ir_str_slice_bytes_span", arguments);
    try out.print(a, "  {s} = extractvalue {{ i64, i64 }} {s}, 0\n  {s} = extractvalue {{ i64, i64 }} {s}, 1\n", .{ at, span, len, span });
    try out.print(a, "  {s} = getelementptr inbounds i8, ptr {s}, i64 32\n  {s} = getelementptr inbounds i8, ptr {s}, i64 {s}\n", .{ data, try context.value(inst.a), pointer, data, at });
    try out.print(a, "  {s} = insertvalue {{ ptr, i64 }} poison, ptr {s}, 0\n  {s} = insertvalue {{ ptr, i64 }} {s}, i64 {s}, 1\n", .{ partial, pointer, name, partial, len });
}

/// Clamp a checked nonnegative slice endpoint only at the upper bound.
fn clamp(comptime Context: type, comptime Output: type, context: Context, out: Output, index: []const u8, len: []const u8) Error![]const u8 {
    const above = try context.fresh("%clamphigh");
    const result = try context.fresh("%clamped");
    try out.print(context.a(), "  {s} = icmp sgt i64 {s}, {s}\n  {s} = select i1 {s}, i64 {s}, i64 {s}\n", .{ above, index, len, result, above, len, index });
    return result;
}

// The runtime still handles Unicode and invalid offsets. Read the first byte
// only after this explicit guard, including unproven/manual width operations.
/// A text view operand: its value is an `{ ptr, i64 }` pair, not a block.
fn isView(comptime Context: type, context: Context, ref: ir.Ref) bool {
    const f = context.function;
    return f.inst(f.resolve(ref)).ty == .str_view;
}

fn scalar(comptime Context: type, comptime Output: type, context: Context, out: Output, name: []const u8, inst: ir.Inst) Error!void {
    const a = context.a();
    const view = isView(Context, context, inst.a);
    // Only a code read decodes a view in place; a width is never fused over a view.
    if (view and inst.op != .str_code and inst.op != .str_width) return context.unsupported(out, name, inst);
    const offset = try context.value(inst.b);
    const length = try context.fresh(length_name);
    const valid = try context.fresh("%textvalid");
    const read = try context.fresh("textread");
    const ascii = try context.fresh("textascii");
    const slow = try context.fresh("textscalar");
    const join = try context.fresh("textjoin");
    const data = try context.fresh("%textdata");
    if (view) {
        const pair = try context.value(inst.a);
        try out.print(a, "  {s} = extractvalue {{ ptr, i64 }} {s}, 0\n  {s} = extractvalue {{ ptr, i64 }} {s}, 1\n" ++
            "  {s} = icmp ult i64 {s}, {s}\n  br i1 {s}, label %{s}, label %{s}\n{s}:\n", .{ data, pair, length, pair, valid, offset, length, valid, read, slow, read });
    } else {
        const receiver = try context.value(inst.a);
        const length_ptr = try context.fresh(length_name);
        const guard = "  {s} = getelementptr inbounds i8, ptr {s}, i64 8\n" ++
            "  {s} = load i64, ptr {s}, align 8\n  {s} = icmp ult i64 {s}, {s}\n" ++
            "  br i1 {s}, label %{s}, label %{s}\n{s}:\n";
        try out.print(a, guard, .{ length_ptr, receiver, length, length_ptr, valid, offset, length, valid, read, slow, read });
        try out.print(a, "  {s} = getelementptr inbounds i8, ptr {s}, i64 32\n", .{ data, receiver });
    }
    const pointer = try context.fresh("%textbyte");
    const byte = try context.fresh("%textbyte");
    const single = try context.fresh("%textsingle");
    try out.print(a, "  {s} = getelementptr inbounds i8, ptr {s}, i64 {s}\n  {s} = load i8, ptr {s}, align 1\n" ++
        "  {s} = icmp ult i8 {s}, 128\n  br i1 {s}, label %{s}, label %{s}\n{s}:\n", .{ pointer, data, offset, byte, pointer, single, byte, single, ascii, slow, ascii });
    const result = if (inst.op == .str_width) "i64" else "i32";
    const symbol = if (inst.op == .str_width) "myl_core_ir_str_width" else "myl_core_ir_str_code";
    var fast_value: []const u8 = "1";
    if (inst.op == .str_code) {
        fast_value = try context.fresh("%textcode");
        try out.print(a, "  {s} = zext i8 {s} to i32\n", .{ fast_value, byte });
    }
    const slow_value = try context.fresh("%textscalar");
    try out.print(a, "  br label %{s}\n{s}:\n", .{ join, slow });
    if (view and inst.op == .str_width) {
        try out.print(a, "  {s} = call i64 @myl_core_span_str_width(ptr {s}, i64 {s}, i64 {s})\n", .{ slow_value, data, length, offset });
    } else if (view) {
        try out.print(a, "  {s} = call i32 @myl_core_span_str_code(ptr {s}, i64 {s}, i64 {s})\n", .{ slow_value, data, length, offset });
    } else {
        try out.print(a, "  {s} = call {s} @{s}(ptr {s}, i64 {s})\n", .{ slow_value, result, symbol, try context.value(inst.a), offset });
    }
    try out.print(a, "  br label %{s}\n{s}:\n  {s} = phi {s} [ {s}, %{s} ], [ {s}, %{s} ]\n", .{ join, join, name, result, fast_value, ascii, slow_value, slow });
    context.label = join;
}

const Access = struct { receiver: ir.Ref, offset: ir.Ref };

fn bounds(comptime Context: type, comptime Output: type, context: Context, out: Output, inst: ir.Inst, access: Access) Error!void {
    const length = try context.fresh(length_name);
    const outside = try context.fresh("%textoob");
    if (isView(@TypeOf(context), context, access.receiver)) {
        try out.print(context.a(), "  {s} = extractvalue {{ ptr, i64 }} {s}, 1\n  {s} = icmp uge i64 {s}, {s}\n", .{ length, try context.value(access.receiver), outside, try context.value(access.offset), length });
    } else {
        const pointer = try context.fresh(length_name);
        const check = "  {s} = getelementptr inbounds i8, ptr {s}, i64 8\n" ++
            "  {s} = load i64, ptr {s}, align 8\n" ++
            "  {s} = icmp uge i64 {s}, {s}\n";
        try out.print(context.a(), check, .{ pointer, try context.value(access.receiver), length, pointer, outside, try context.value(access.offset), length });
    }
    const site = try context.site(.text_bounds, inst, "index");
    const index = scalarIndex(context, access) orelse return context.trapIf(out, outside, site, try context.value(access.offset), length);
    const branch = try context.trapBegin(out, outside, site);
    const scalars = try context.textScalars(out, access.receiver);
    const reported = try context.value(index);
    try context.trapEnd(out, branch, .{ .left = reported, .right = scalars });
}

fn scalarIndex(context: anytype, access: Access) ?ir.Ref {
    const f = context.function;
    const offset = f.inst(f.resolve(access.offset));
    const module = context.state.module;
    if (offset.op != .call or offset.a.index() >= module.functions.items.len) return null;
    const callee = module.functions.items[offset.a.index()];
    const signature = callee.signature;
    _ = flags.textOffset(signature, callee.name) orelse return null;
    const args = f.operands(offset.data);
    if (args.len != 2 or f.resolve(args[0]) != f.resolve(access.receiver)) return null;
    return args[1];
}

/// An ASCII source proves a borrowed piece's scalar length equals its byte length.
pub fn runtimeCall(comptime Context: type, comptime Output: type, context: Context, out: Output, name: []const u8, inst: ir.Inst) Error!bool {
    if (inst.op != .call) return false;
    const callee = context.state.module.functions.items[inst.a.index()];
    if (std.mem.eql(u8, callee.name, "myl_core_xc_slice")) return xcSlice(Context, Output, context, out, name, inst);
    if (std.mem.eql(u8, callee.name, "myl_core_ir_str_byte")) return strByte(Context, Output, context, out, name, inst);
    const sig = callee.signature;
    if (sig.linkage != .runtime_c or !sig.passing.eql(.{ .views = 1 })) return false;
    if (!@import("std").mem.eql(u8, callee.name, "myl_core_span_chars")) return false;
    const arg = context.function.operands(inst.data)[0];
    if (context.function.inst(context.function.resolve(arg)).ty != .str_view) return false;
    const ascii = try sourceAscii(Context, Output, context, out, arg) orelse return false;
    const view = try context.value(arg);
    const data = try context.fresh("%charsdata");
    const len = try context.fresh("%charslen");
    const slow = try context.fresh("charsslow");
    const join = try context.fresh("charsjoin");
    const scalars = try context.fresh("%charsscalars");
    const previous = context.label;
    try out.print(context.a(), "  {s} = extractvalue {{ ptr, i64 }} {s}, 0\n  {s} = extractvalue {{ ptr, i64 }} {s}, 1\n", .{ data, view, len, view });
    try out.print(context.a(), "  br i1 {s}, label %{s}, label %{s}\n{s}:\n  {s} = call i64 @myl_core_span_chars(ptr {s}, i64 {s})\n", .{ ascii, join, slow, slow, scalars, data, len });
    try out.print(context.a(), "  br label %{s}\n{s}:\n  {s} = phi i64 [ {s}, %{s} ], [ {s}, %{s} ]\n", .{ join, join, name, len, previous, scalars, slow });
    context.label = join;
    return true;
}

/// The octet an owned `str` read selects, as a load from the text's octets. The builder guards the read with the located
/// unsigned bounds check before this call (`build_text.zig`), so the runtime function's own range check can never fail
/// and the call is only a barrier to LLVM: inline, the index and the length meet the guard, and the load can be hoisted.
fn strByte(comptime Context: type, comptime Output: type, context: Context, out: Output, name: []const u8, inst: ir.Inst) Error!bool {
    const sig = context.state.module.functions.items[inst.a.index()].signature;
    // The builder declares this helper `extern_c`; the `myl_` prefix is reserved, so no source extern can carry the name.
    if (sig.linkage != .extern_c or sig.ret != .i64 or !sig.passing.eql(.{ .views = 1 })) return false;
    if (!std.mem.eql(ir.Type, sig.params, &.{ .str, .i64 })) return false;
    const operands = context.function.operands(inst.data);
    if (operands.len != 2) return false;
    const span = try context.spanParts(out, operands[0]);
    const index = try context.value(operands[1]);
    const slot = try context.fresh("%strbyteslot");
    const octet = try context.fresh("%strbyte");
    try out.print(context.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 {s}\n  {s} = load i8, ptr {s}, align 1\n  {s} = zext i8 {s} to i64\n", .{ slot, span.data, index, octet, slot, name, octet });
    return true;
}

/// A char slice of a plain `str` parameter's view through its owner (`myl_core_xc_slice(owner, text, start, end)`).
/// An ASCII owner's scalar positions are its octet offsets, so non-negative endpoints clamp inline (the same
/// clamps as the runtime); any other slice calls the runtime, which also traps a negative endpoint.
fn xcSlice(comptime Context: type, comptime Output: type, context: Context, out: Output, name: []const u8, inst: ir.Inst) Error!bool {
    const args = context.function.operands(inst.data);
    if (args.len != 4) return false;
    const a = context.a();
    const owner = try context.value(args[0]);
    const view = try context.value(args[1]);
    const start = try context.value(args[2]);
    const end = try context.value(args[3]);
    const kind_at = try context.fresh("%xckind");
    const kind = try context.fresh("%xckind");
    const bit = try context.fresh("%xcascii");
    const ascii = try context.fresh("%xcascii");
    const from_nonneg = try context.fresh("%xcnonneg");
    const to_nonneg = try context.fresh("%xcnonneg");
    const from_ok = try context.fresh("%xcok");
    const inline_ok = try context.fresh("%xcok");
    const data = try context.fresh("%xcdata");
    const len = try context.fresh("%xclen");
    const fast = try context.fresh("xcfast");
    const slow = try context.fresh("xcslow");
    const join = try context.fresh("xcjoin");
    const clamp_from = try context.fresh("%xcfrom");
    const past_from = try context.fresh("%xcpastfrom");
    const clamp_to = try context.fresh("%xcto");
    const past_to = try context.fresh("%xcpastto");
    const to = try context.fresh("%xcend");
    const reversed = try context.fresh("%xcrev");
    const from = try context.fresh("%xcbegin");
    const pointer = try context.fresh("%xcptr");
    const octets = try context.fresh("%xcoctets");
    const fast_a = try context.fresh("%xcpair");
    const fast_v = try context.fresh("%xcpair");
    const slow_v = try context.fresh("%xcruntime");
    try out.print(a, "  {s} = getelementptr inbounds i8, ptr {s}, i64 {d}\n  {s} = load i32, ptr {s}, align 4\n" ++
        "  {s} = and i32 {s}, 256\n  {s} = icmp ne i32 {s}, 0\n", .{ kind_at, owner, context.module().kindOffset(), kind, kind_at, bit, kind, ascii, bit });
    try out.print(a, "  {s} = icmp sge i64 {s}, 0\n  {s} = icmp sge i64 {s}, 0\n", .{ from_nonneg, start, to_nonneg, end });
    try out.print(a, "  {s} = and i1 {s}, {s}\n  {s} = and i1 {s}, {s}\n", .{ from_ok, ascii, from_nonneg, inline_ok, from_ok, to_nonneg });
    try out.print(a, "  {s} = extractvalue {{ ptr, i64 }} {s}, 0\n  {s} = extractvalue {{ ptr, i64 }} {s}, 1\n", .{ data, view, len, view });
    try out.print(a, "  br i1 {s}, label %{s}, label %{s}\n{s}:\n", .{ inline_ok, fast, slow, fast });
    try out.print(a, "  {s} = icmp sgt i64 {s}, {s}\n  {s} = select i1 {s}, i64 {s}, i64 {s}\n", .{ past_from, start, len, clamp_from, past_from, len, start });
    try out.print(a, "  {s} = icmp sgt i64 {s}, {s}\n  {s} = select i1 {s}, i64 {s}, i64 {s}\n", .{ past_to, end, len, clamp_to, past_to, len, end });
    try out.print(a, "  {s} = icmp slt i64 {s}, {s}\n  {s} = select i1 {s}, i64 {s}, i64 {s}\n", .{ reversed, clamp_to, clamp_from, to, reversed, clamp_from, clamp_to });
    try out.print(a, "  {s} = getelementptr inbounds i8, ptr {s}, i64 {s}\n  {s} = sub i64 {s}, {s}\n", .{ pointer, data, clamp_from, from, to, clamp_from });
    try out.print(a, "  {s} = insertvalue {{ ptr, i64 }} poison, ptr {s}, 0\n  {s} = insertvalue {{ ptr, i64 }} {s}, i64 {s}, 1\n", .{ fast_a, pointer, fast_v, fast_a, from });
    try out.print(a, "  br label %{s}\n{s}:\n", .{ join, slow });
    const arguments = try std.fmt.allocPrint(a, "ptr {s}, ptr {s}, i64 {s}, i64 {s}, i64 {s}", .{ owner, data, len, start, end });
    try context.cStructCall(out, .{ .name = slow_v, .ty = "{ ptr, i64 }", .bytes = 16 }, "@myl_core_xc_slice", arguments);
    try out.print(a, "  br label %{s}\n{s}:\n  {s} = phi {{ ptr, i64 }} [ {s}, %{s} ], [ {s}, %{s} ]\n", .{ join, join, name, fast_v, fast, slow_v, slow });
    context.label = join;
    _ = octets;
    return true;
}

/// Read an octet from an SSA span, retaining the original located list bounds trap.
pub fn byteRead(comptime Context: type, comptime Output: type, context: Context, out: Output, name: []const u8, inst: ir.Inst) Error!void {
    const view = try context.value(inst.a);
    const length = try context.fresh("%bytelen");
    const data = try context.fresh("%bytedata");
    const slot = try context.fresh("%byteslot");
    const index = try context.widened(out, inst.b);
    try out.print(context.a(), "  {s} = extractvalue {{ ptr, i64 }} {s}, 1\n", .{ length, view });
    if (context.checkOf(inst) == .exact) {
        const outside = try context.fresh("%byteoob");
        try out.print(context.a(), "  {s} = icmp uge i64 {s}, {s}\n", .{ outside, index, length });
        const site = try context.site(.list_bounds, inst, "index");
        var reported = index;
        const offset = context.function.inst(context.function.resolve(inst.b));
        if (offset.op == .call and offset.a.index() < context.state.module.functions.items.len) {
            const callee = context.state.module.functions.items[offset.a.index()];
            const signature = callee.signature;
            const audited = signature.linkage == .runtime_c and signature.passing.eql(.{ .views = 1 });
            const layout = signature.ret == .u64 and @import("std").mem.eql(ir.Type, signature.params, &.{ .str, .i64 });
            if (audited and layout and @import("std").mem.eql(u8, callee.name, "myl_core_span_bytes_index_offset")) {
                reported = try context.value(context.function.operands(offset.data)[1]);
            }
        }
        try context.trapIf(out, outside, site, reported, length);
    }
    try out.print(context.a(), "  {s} = extractvalue {{ ptr, i64 }} {s}, 0\n  {s} = getelementptr inbounds i8, ptr {s}, i64 {s}\n  {s} = load i8, ptr {s}, align 1\n", .{ data, view, slot, data, index, name, slot });
}
