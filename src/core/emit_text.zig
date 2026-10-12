//! Text operation dispatch; S2-T extends the minimal hand-built IR support.
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
            try out.print(a, "  {s} = call ptr @myl_core_ir_str_append_char(ptr {s}, ptr {s}, i64 {s})\n", .{ name, try context.value(inst.a), try context.value(inst.b), try context.value(offset) });
        },
        .str_slice => try out.print(a, "  {s} = call ptr @myl_core_ir_str_slice(ptr {s}, i64 {s}, i64 {s})\n", .{ name, try context.value(inst.a), try context.value(inst.b), try context.value(context.function.operands(inst.data)[0]) }),
        .str_view_of => {
            const pointer = try context.fresh("%view");
            const data = try context.fresh("%view");
            const partial = try context.fresh("%view");
            if (context.function.inst(context.function.resolve(inst.a)).ty == .str_view) {
                try out.print(a, "  {s} = extractvalue {{ ptr, i64 }} {s}, 0\n", .{ data, try context.value(inst.a) });
            } else try out.print(a, "  {s} = getelementptr inbounds i8, ptr {s}, i64 32\n", .{ data, try context.value(inst.a) });
            try out.print(a, "  {s} = getelementptr inbounds i8, ptr {s}, i64 {s}\n", .{ pointer, data, try context.value(inst.b) });
            try out.print(a, "  {s} = insertvalue {{ ptr, i64 }} poison, ptr {s}, 0\n  {s} = insertvalue {{ ptr, i64 }} {s}, i64 {s}, 1\n", .{ partial, pointer, name, partial, try context.value(context.function.operands(inst.data)[0]) });
        },
        .str_slice_view => try sliceView(@TypeOf(context), @TypeOf(out), context, out, name, inst),
        .str_from_view => {
            const pointer = try context.fresh("%view");
            const len = try context.fresh("%view");
            const view = try context.value(inst.a);
            try out.print(a, "  {s} = extractvalue {{ ptr, i64 }} {s}, 0\n  {s} = extractvalue {{ ptr, i64 }} {s}, 1\n", .{ pointer, view, len, view });
            const ascii = try sourceAscii(@TypeOf(context), @TypeOf(out), context, out, inst.a) orelse
                return out.print(a, "  {s} = call ptr @myl_core_ir_str_from_view(ptr {s}, i64 {s})\n", .{ name, pointer, len });
            try out.print(a, "  {s} = call ptr @myl_core_ir_str_from_span(ptr {s}, i64 {s}, i1 zeroext {s})\n", .{ name, pointer, len, ascii });
        },
        else => try context.unsupported(out, name, inst),
    }
}

/// NEW-CORE-S1-ASCII-1: whether the text a view borrows from is ASCII (an `i1`), when the
/// view's source is known; every span of an ASCII text is ASCII, so its copy skips the scan.
fn sourceAscii(comptime Context: type, comptime Output: type, context: Context, out: Output, view: ir.Ref) Error!?[]const u8 {
    const f = context.function;
    const borrow = f.inst(f.resolve(view));
    if (borrow.op != .str_view_of and borrow.op != .str_slice_view) return null;
    if (f.inst(f.resolve(borrow.a)).ty == .str_view) return sourceAscii(Context, Output, context, out, borrow.a);
    const kind_at = try context.fresh("%viewkind");
    const kind = try context.fresh("%viewkind");
    const bit = try context.fresh("%viewascii");
    const ascii = try context.fresh("%viewascii");
    try out.print(context.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 {d}\n  {s} = load i32, ptr {s}, align 4\n  {s} = and i32 {s}, 256\n  {s} = icmp ne i32 {s}, 0\n", .{
        kind_at, try context.value(borrow.a), context.module().kindOffset(), kind, kind_at, bit, kind, ascii, bit,
    });
    return ascii;
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
    const byte_source = context.function.inst(context.function.resolve(inst.a)).ty == .bytes;
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
    try out.print(a, "  {s} = call {{ i64, i64 }} @myl_core_ir_str_slice_span(ptr {s}, i64 {s}, i64 {s})\n" ++
        "  {s} = extractvalue {{ i64, i64 }} {s}, 0\n  {s} = extractvalue {{ i64, i64 }} {s}, 1\n  br label %{s}\n{s}:\n", .{ span, text, start, end, slow_at, span, slow_len, span, join, join });
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

/// Python's slice-bound clamp of `index` into `[0, len]`, a negative index counting from the end.
fn clamp(comptime Context: type, comptime Output: type, context: Context, out: Output, index: []const u8, len: []const u8) Error![]const u8 {
    const a = context.a();
    const negative = try context.fresh("%clampneg");
    const wrapped = try context.fresh("%clampwrap");
    const from_end = try context.fresh("%clampend");
    const below = try context.fresh("%clamplow");
    const floor = try context.fresh("%clamplow");
    const above = try context.fresh("%clamphigh");
    const result = try context.fresh("%clamped");
    try out.print(a, "  {s} = icmp slt i64 {s}, 0\n  {s} = add i64 {s}, {s}\n  {s} = select i1 {s}, i64 {s}, i64 {s}\n" ++
        "  {s} = icmp slt i64 {s}, 0\n  {s} = select i1 {s}, i64 0, i64 {s}\n  {s} = icmp sgt i64 {s}, {s}\n  {s} = select i1 {s}, i64 {s}, i64 {s}\n", .{
        negative, index,    wrapped, index, len,      from_end, negative, wrapped, index,
        below,    from_end, floor,   below, from_end, above,    floor,    len,     result,
        above,    len,      floor,
    });
    return result;
}

// The runtime still handles Unicode and invalid offsets. Read the first byte
// only after this explicit guard, including unproven/manual width operations.
fn scalar(comptime Context: type, comptime Output: type, context: Context, out: Output, name: []const u8, inst: ir.Inst) Error!void {
    const a = context.a();
    const receiver = try context.value(inst.a);
    const offset = try context.value(inst.b);
    const length_ptr = try context.fresh(length_name);
    const length = try context.fresh(length_name);
    const valid = try context.fresh("%textvalid");
    const read = try context.fresh("textread");
    const ascii = try context.fresh("textascii");
    const slow = try context.fresh("textscalar");
    const join = try context.fresh("textjoin");
    const guard = "  {s} = getelementptr inbounds i8, ptr {s}, i64 8\n" ++
        "  {s} = load i64, ptr {s}, align 8\n  {s} = icmp ult i64 {s}, {s}\n" ++
        "  br i1 {s}, label %{s}, label %{s}\n{s}:\n";
    try out.print(a, guard, .{ length_ptr, receiver, length, length_ptr, valid, offset, length, valid, read, slow, read });
    const data = try context.fresh("%textdata");
    const pointer = try context.fresh("%textbyte");
    const byte = try context.fresh("%textbyte");
    const single = try context.fresh("%textsingle");
    const first_byte = "  {s} = getelementptr inbounds i8, ptr {s}, i64 32\n" ++
        "  {s} = getelementptr inbounds i8, ptr {s}, i64 {s}\n  {s} = load i8, ptr {s}, align 1\n" ++
        "  {s} = icmp ult i8 {s}, 128\n  br i1 {s}, label %{s}, label %{s}\n{s}:\n";
    try out.print(a, first_byte, .{ data, receiver, pointer, data, offset, byte, pointer, single, byte, single, ascii, slow, ascii });
    const result = if (inst.op == .str_width) "i64" else "i32";
    const symbol = if (inst.op == .str_width) "myl_core_ir_str_width" else "myl_core_ir_str_code";
    var fast_value: []const u8 = "1";
    if (inst.op == .str_code) {
        fast_value = try context.fresh("%textcode");
        try out.print(a, "  {s} = zext i8 {s} to i32\n", .{ fast_value, byte });
    }
    const slow_value = try context.fresh("%textscalar");
    const finish = "  br label %{s}\n{s}:\n  {s} = call {s} @{s}(ptr {s}, i64 {s})\n" ++
        "  br label %{s}\n{s}:\n  {s} = phi {s} [ {s}, %{s} ], [ {s}, %{s} ]\n";
    try out.print(a, finish, .{ join, slow, slow_value, result, symbol, receiver, offset, join, join, name, result, fast_value, ascii, slow_value, slow });
    context.label = join;
}

const Access = struct { receiver: ir.Ref, offset: ir.Ref };

fn bounds(comptime Context: type, comptime Output: type, context: Context, out: Output, inst: ir.Inst, access: Access) Error!void {
    const length = try context.fresh(length_name);
    const pointer = try context.fresh(length_name);
    const outside = try context.fresh("%textoob");
    const check = "  {s} = getelementptr inbounds i8, ptr {s}, i64 8\n" ++
        "  {s} = load i64, ptr {s}, align 8\n" ++
        "  {s} = icmp uge i64 {s}, {s}\n";
    try out.print(context.a(), check, .{ pointer, try context.value(access.receiver), length, pointer, outside, try context.value(access.offset), length });
    const site = try context.site(.text_bounds, inst, "index");
    const index = scalarIndex(context, access) orelse return context.trapIf(out, outside, site, try context.value(access.offset), length);
    const branch = try context.trapBegin(out, outside, site);
    const scalars = try context.textScalars(out, access.receiver);
    var reported = try context.value(index.ref);
    if (index.normalized) {
        const negative = try context.fresh("%textnegative");
        const before = try context.fresh("%textbefore");
        const original = try context.fresh("%textindex");
        try out.print(context.a(), "  {s} = icmp slt i64 {s}, 0\n  {s} = sub i64 {s}, {s}\n  {s} = select i1 {s}, i64 {s}, i64 {s}\n", .{ negative, reported, before, reported, scalars, original, negative, before, reported });
        reported = original;
    }
    try context.trapEnd(out, branch, .{ .left = reported, .right = scalars });
}

fn scalarIndex(context: anytype, access: Access) ?struct { ref: ir.Ref, normalized: bool } {
    const f = context.function;
    const offset = f.inst(f.resolve(access.offset));
    const module = context.state.module;
    if (offset.op != .call or offset.a.index() >= module.functions.items.len) return null;
    const callee = module.functions.items[offset.a.index()];
    const signature = callee.signature;
    const kind = flags.textOffset(signature, callee.name) orelse return null;
    const args = f.operands(offset.data);
    if (args.len != 2 or f.resolve(args[0]) != f.resolve(access.receiver)) return null;
    return .{ .ref = args[1], .normalized = kind == .normalized and signature.params[1] == .i64 };
}

/// An ASCII source proves a borrowed piece's scalar length equals its byte length.
pub fn runtimeCall(comptime Context: type, comptime Output: type, context: Context, out: Output, name: []const u8, inst: ir.Inst) Error!bool {
    if (inst.op != .call) return false;
    const callee = context.state.module.functions.items[inst.a.index()];
    const sig = callee.signature;
    if (sig.linkage != .runtime_c or sig.views != 1 or sig.owned != 0) return false;
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
            const audited = signature.linkage == .runtime_c and signature.views == 1 and signature.owned == 0 and signature.consumes == 0;
            const layout = signature.ret == .u64 and @import("std").mem.eql(ir.Type, signature.params, &.{ .str, .i64 });
            if (audited and layout and @import("std").mem.eql(u8, callee.name, "myl_core_span_bytes_index_offset")) {
                reported = try context.value(context.function.operands(offset.data)[1]);
            }
        }
        try context.trapIf(out, outside, site, reported, length);
    }
    try out.print(context.a(), "  {s} = extractvalue {{ ptr, i64 }} {s}, 0\n  {s} = getelementptr inbounds i8, ptr {s}, i64 {s}\n  {s} = load i8, ptr {s}, align 1\n", .{ data, view, slot, data, index, name, slot });
}
