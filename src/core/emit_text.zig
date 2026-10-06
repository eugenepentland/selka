//! Text operation dispatch; S2-T extends the minimal hand-built IR support.
const ir = @import("ir.zig");
const flags = @import("flags.zig");
const length_name = "%textlen";

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
            try out.print(a, "  {s} = getelementptr inbounds i8, ptr {s}, i64 32\n  {s} = getelementptr inbounds i8, ptr {s}, i64 {s}\n", .{ data, try context.value(inst.a), pointer, data, try context.value(inst.b) });
            try out.print(a, "  {s} = insertvalue {{ ptr, i64 }} poison, ptr {s}, 0\n  {s} = insertvalue {{ ptr, i64 }} {s}, i64 {s}, 1\n", .{ partial, pointer, name, partial, try context.value(context.function.operands(inst.data)[0]) });
        },
        .str_from_view => {
            const pointer = try context.fresh("%view");
            const len = try context.fresh("%view");
            const view = try context.value(inst.a);
            try out.print(a, "  {s} = extractvalue {{ ptr, i64 }} {s}, 0\n  {s} = extractvalue {{ ptr, i64 }} {s}, 1\n", .{ pointer, view, len, view });
            try out.print(a, "  {s} = call ptr @myl_core_ir_str_from_view(ptr {s}, i64 {s})\n", .{ name, pointer, len });
        },
        else => try context.unsupported(out, name, inst),
    }
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
