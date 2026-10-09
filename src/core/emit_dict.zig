//! Dictionary operations over insertion-ordered entries and a hybrid control index.
const ir = @import("ir.zig");

/// Allocation or an unsupported IR representation can stop operation emission.
pub const Error = error{ OutOfMemory, UnsupportedEntry, UnsupportedInstruction };

/// Emit layout-independent operations and typed entry loads/stores.
pub fn instruction(comptime Context: type, c: Context, out: *@import("std").ArrayList(u8), name: []const u8, inst: ir.Inst) Error!void {
    const arena = c.a();
    const module = c.module();
    const dict_type = if (inst.op == .dict_new) inst.ty else c.function.inst(c.function.resolve(inst.a)).ty;
    const shape = module.compound(dict_type).dict;
    const value_offset = @import("std").mem.alignForward(u32, module.size(shape.key), module.alignment(shape.value));
    const stride = @max(1, @import("std").mem.alignForward(u32, value_offset + module.size(shape.value), @max(module.alignment(shape.key), module.alignment(shape.value))));
    switch (inst.op) {
        .dict_new => try out.print(arena, "  {s} = call ptr @myl_core_dict_new(i64 {s}, ptr {s})\n", .{ name, try c.value(inst.a), try c.dictDescriptor(dict_type) }),
        .dict_len => {
            const pointer = try c.fresh("%dictlen");
            try out.print(arena, "  {s} = getelementptr inbounds i8, ptr {s}, i64 8\n  {s} = load i64, ptr {s}, align 8, !tbaa !5\n", .{ pointer, try c.value(inst.a), name, pointer });
        },
        .dict_find => {
            if (shape.key != .void and inst.b == .none) return error.UnsupportedInstruction;
            if (shape.key != .void and c.function.inst(c.function.resolve(inst.b)).ty == .str_view) {
                const data = try c.fresh("%dictspan");
                const length = try c.fresh("%dictspanlen");
                try out.print(arena, "  {s} = extractvalue {{ ptr, i64 }} {s}, 0\n  {s} = extractvalue {{ ptr, i64 }} {s}, 1\n" ++
                    "  {s} = call i64 {s}.find_span(ptr {s}, ptr {s}, i64 {s})\n", .{ data, try c.value(inst.b), length, try c.value(inst.b), name, try c.dictDescriptor(dict_type), try c.value(inst.a), data, length });
                return;
            }
            const key = try slot(Context, c, out, shape.key, inst.b, module.size(shape.key));
            const hash = try c.fresh("%dicthash");
            if (shape.key.integer() != null or shape.key == .bool) {
                const bits = if (shape.key == .bool) 1 else shape.key.integer().?.bits;
                const widened = if (bits == 64) try c.value(inst.b) else try c.fresh("%dictkey");
                if (bits != 64) try out.print(arena, "  {s} = zext i{d} {s} to i64\n", .{ widened, bits, try c.value(inst.b) });
                const mixed = try c.fresh("%dictmix");
                const high = try c.fresh("%dicthigh");
                try out.print(arena, "  {s} = mul i64 {s}, -7046029254386353131\n  {s} = lshr i64 {s}, 32\n  {s} = xor i64 {s}, {s}\n", .{ mixed, widened, high, mixed, hash, mixed, high });
            } else if (shape.key == .str or shape.key == .bytes) {
                try out.print(arena, "  {s} = call i64 {s}.hash(ptr {s})\n", .{ hash, try c.dictDescriptor(dict_type), try c.value(inst.b) });
            } else try out.print(arena, "  {s} = call i64 @myl_core_dict_hash(ptr {s}, ptr {s})\n", .{ hash, try c.value(inst.a), key });
            try out.print(arena, "  {s} = call i64 {s}.find(ptr {s}, ptr {s}, i64 {s})\n", .{ name, try c.dictDescriptor(dict_type), try c.value(inst.a), key, hash });
        },
        .dict_entry_key, .dict_entry_value => {
            if (inst.ty == .void) return;
            const offset = try c.fresh("%dictoffset");
            const total = try c.fresh("%dictoffset");
            const pointer = try c.fresh("%dictentry");
            try out.print(arena, "  {s} = mul i64 {s}, {d}\n  {s} = add i64 {s}, {d}\n  {s} = getelementptr inbounds i8, ptr {s}, i64 {s}\n", .{
                offset,
                try c.value(inst.b),
                stride,
                total,
                offset,
                32 + if (inst.op == .dict_entry_value) value_offset else @as(u32, 0),
                pointer,
                try c.value(inst.a),
                total,
            });
            try c.loadValue(out, inst.ty, pointer, name);
        },
        .dict_set_value => {
            const scalar = shape.value.integer() != null or shape.value == .bool or shape.value == .f64 or shape.value == .void;
            if (scalar or @import("flags.zig").transferredSlot(c.function, inst)) {
                try scalarSet(c, out, name, inst, .{ .stride = stride, .offset = value_offset, .value = shape.value });
                return;
            }
            const value = try slot(Context, c, out, shape.value, c.function.operands(inst.data)[0], stride - value_offset);
            try out.print(arena, "  {s} = call ptr @myl_core_dict_set(ptr {s}, i64 {s}, ptr {s})\n", .{ name, try c.value(inst.a), try c.value(inst.b), value });
        },
        .dict_insert => {
            const operands = c.function.operands(inst.data);
            const key = try slot(Context, c, out, shape.key, operands[0], module.size(shape.key));
            const value = if (shape.value == .void) "null" else try slot(Context, c, out, shape.value, operands[1], stride - value_offset);
            try out.print(arena, "  {s} = call ptr @myl_core_dict_insert(ptr {s}, i64 {s}, ptr {s}, ptr {s}, i1 {s})\n", .{ name, try c.value(inst.a), try c.value(inst.b), key, value, if (c.verifyMode()) "true" else "false" });
        },
        .dict_remove => try out.print(arena, "  {s} = call ptr @myl_core_dict_remove(ptr {s}, i64 {s})\n", .{ name, try c.value(inst.a), try c.value(inst.b) }),
        .dict_entries => try out.print(arena, "  {s} = call i64 @myl_core_dict_entries(ptr {s})\n", .{ name, try c.value(inst.a) }),
        .dict_entry_live => try out.print(arena, "  {s} = call zeroext i1 @myl_core_dict_live(ptr {s}, i64 {s})\n", .{ name, try c.value(inst.a), try c.value(inst.b) }),
        .dict_copy, .dict_clear => try out.print(arena, "  {s} = call ptr @{s}(ptr {s})\n", .{ name, if (inst.op == .dict_copy) "myl_core_dict_copy" else "myl_core_dict_clear", try c.value(inst.a) }),
        else => return error.UnsupportedInstruction,
    }
}

const ScalarStore = struct { stride: u32, offset: u32, value: ir.Type };

fn scalarSet(c: anytype, out: *@import("std").ArrayList(u8), name: []const u8, inst: ir.Inst, layout: ScalarStore) Error!void {
    // Ownership already supplied the unique dictionary, including COW and verify checks.
    // A scalar value has no reference to release; padding has no observable value.
    if (layout.value != .void) {
        const prefix = "%dictstore";
        const offset = try c.fresh(prefix);
        const total = try c.fresh(prefix);
        const pointer = try c.fresh(prefix);
        try out.print(c.a(), "  {s} = mul i64 {s}, {d}\n  {s} = add i64 {s}, {d}\n  {s} = getelementptr inbounds i8, ptr {s}, i64 {s}\n", .{
            offset, try c.value(inst.b), layout.stride, total, offset, 32 + layout.offset, pointer, try c.value(inst.a), total,
        });
        try c.storeOperand(out, layout.value, c.function.operands(inst.data)[0], pointer);
    }
    try out.print(c.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 0\n", .{ name, try c.value(inst.a) });
}

fn slot(comptime Context: type, c: Context, out: *@import("std").ArrayList(u8), ty: ir.Type, value: ir.Ref, size: u32) Error![]const u8 {
    if (ty == .void) return "null";
    const pointer = try c.stackSlot(@max(1, size));
    if (size > c.module().size(ty)) try out.print(c.a(), "  call void @llvm.memset.p0.i64(ptr {s}, i8 0, i64 {d}, i1 false)\n", .{ pointer, size });
    try c.storeOperand(out, ty, value, pointer);
    return pointer;
}

/// Emit the first SSE2 control group and scalar candidate comparisons inline.
pub fn probeDefinition(comptime Context: type, c: Context, out: *@import("std").ArrayList(u8), dict_type: ir.Type, symbol: []const u8) Error!void {
    const a = c.a();
    const m = c.module();
    const shape = m.compound(dict_type).dict;
    const value_offset = @import("std").mem.alignForward(u32, m.size(shape.key), m.alignment(shape.value));
    const stride = @max(1, @import("std").mem.alignForward(u32, value_offset + m.size(shape.value), @max(m.alignment(shape.key), m.alignment(shape.value))));
    if (shape.key == .str and @import("emit_dict_span.zig").used(m, dict_type)) try @import("emit_dict_span.zig").definition(c, out, dict_type, symbol);
    if (shape.key.integer() == null and shape.key != .bool and shape.key != .str and shape.key != .bytes) {
        try out.print(a, "define internal i64 {s}.find(ptr %dict, ptr %key, i64 %hash) alwaysinline nounwind {{\nentry:\n  %result = call i64 @myl_core_dict_find(ptr %dict, ptr %key, i64 %hash)\n  ret i64 %result\n}}\n", .{symbol});
        return;
    }
    if (shape.key == .str or shape.key == .bytes) try textHashDefinition(Context, c, out, symbol);
    const key_type = if (shape.key == .bool) "i8" else try c.ty(shape.key);
    try out.print(a, "define internal i64 {s}.find(ptr %dict, ptr %key, i64 %hash) alwaysinline nounwind {{\nentry:\n", .{symbol});
    try out.appendSlice(a,
        \\  %meta_at = getelementptr inbounds i8, ptr %dict, i64 24
        \\  %meta = load ptr, ptr %meta_at, align 8
        \\  %index_at = getelementptr inbounds i8, ptr %meta, i64 8
        \\  %index = load ptr, ptr %index_at, align 8
        \\  %small = icmp eq ptr %index, null
        \\  br i1 %small, label %small_table, label %group
        \\group:
        \\  %slots = load i32, ptr %index, align 4
        \\  %log = call i32 @llvm.cttz.i32(i32 %slots, i1 false)
        \\  %shift32 = sub i32 64, %log
        \\  %shift = zext i32 %shift32 to i64
        \\  %home64 = lshr i64 %hash, %shift
        \\  %home = trunc i64 %home64 to i32
        \\  %mask = sub i32 %slots, 1
        \\  %control = getelementptr inbounds i8, ptr %index, i64 16
        \\  %group_at = getelementptr inbounds i8, ptr %control, i64 %home64
        \\  %controls = load <16 x i8>, ptr %group_at, align 1
        \\  %tag = trunc i64 %hash to i8
        \\  %tag7 = and i8 %tag, 127
        \\  %tag0 = insertelement <16 x i8> poison, i8 %tag7, i32 0
        \\  %tags = shufflevector <16 x i8> %tag0, <16 x i8> poison, <16 x i32> zeroinitializer
        \\  %tagmatch = icmp eq <16 x i8> %controls, %tags
        \\  %match16 = bitcast <16 x i1> %tagmatch to i16
        \\  %matches = zext i16 %match16 to i32
        \\  %room = add i32 %slots, 30
        \\  %number_offset = and i32 %room, -16
        \\  %number_offset64 = zext i32 %number_offset to i64
        \\  %numbers = getelementptr inbounds i8, ptr %control, i64 %number_offset64
        \\  br label %candidates
        \\candidates:
        \\  %bits = phi i32 [ %matches, %group ], [ %remaining, %next ]
        \\  %none = icmp eq i32 %bits, 0
        \\  br i1 %none, label %empty, label %candidate
        \\candidate:
        \\  %bit = call i32 @llvm.cttz.i32(i32 %bits, i1 false)
        \\  %raw_slot = add i32 %home, %bit
        \\  %slot = and i32 %raw_slot, %mask
        \\  %slot64 = zext i32 %slot to i64
        \\  %number_at = getelementptr inbounds i32, ptr %numbers, i64 %slot64
        \\  %number = load i32, ptr %number_at, align 4
        \\  %entry_number = zext i32 %number to i64
        \\
    );
    try out.print(a, "  %offset = mul i64 %entry_number, {d}\n  %entry_offset = add i64 %offset, 32\n" ++
        "  %stored_at = getelementptr inbounds i8, ptr %dict, i64 %entry_offset\n  %stored = load {s}, ptr %stored_at, align {d}\n" ++
        "  %query = load {s}, ptr %key, align {d}\n", .{ stride, key_type, m.alignment(shape.key), key_type, m.alignment(shape.key) });
    if (shape.key == .str or shape.key == .bytes) {
        try out.appendSlice(a, "  %same = call zeroext i1 @myl_core_str_eq(ptr %stored, ptr %query)\n");
    } else try out.print(a, "  %same = icmp eq {s} %stored, %query\n", .{key_type});
    try out.appendSlice(a,
        \\  br i1 %same, label %found, label %next
        \\found:
        \\  ret i64 %entry_number
        \\next:
        \\  %one_less = sub i32 %bits, 1
        \\  %remaining = and i32 %bits, %one_less
        \\  br label %candidates
        \\empty:
        \\  %empty_match = icmp eq <16 x i8> %controls, <i8 -128, i8 -128, i8 -128, i8 -128, i8 -128, i8 -128, i8 -128, i8 -128, i8 -128, i8 -128, i8 -128, i8 -128, i8 -128, i8 -128, i8 -128, i8 -128>
        \\  %empty16 = bitcast <16 x i1> %empty_match to i16
        \\  %empties = zext i16 %empty16 to i32
        \\  %full = icmp eq i32 %empties, 0
        \\  br i1 %full, label %slow, label %missing
        \\missing:
        \\  %empty_bit = call i32 @llvm.cttz.i32(i32 %empties, i1 false)
        \\  %empty_raw_slot = add i32 %home, %empty_bit
        \\  %empty_slot = and i32 %empty_raw_slot, %mask
        \\  %empty_slot64 = zext i32 %empty_slot to i64
        \\  %probe = xor i64 %empty_slot64, -1
        \\  ret i64 %probe
        \\
    );
    try smallScan(Context, c, out, .{ .stride = stride, .key_type = key_type, .key_align = m.alignment(shape.key), .text = shape.key == .str or shape.key == .bytes });
    try out.appendSlice(a,
        \\slow:
        \\  %result = call i64 @myl_core_dict_find(ptr %dict, ptr %key, i64 %hash)
        \\  ret i64 %result
        \\}
        \\
    );
}

/// The entry layout and key comparison a small-table scan needs.
const SmallKey = struct { stride: u32, key_type: []const u8, key_align: u32, text: bool };

/// NEW-CORE-DICT-SMALL-1: a table of at most eight entries has no index, so the probe
/// walks its cached hashes in place and compares a key only on a hash match, with no
/// runtime call. A table that ever lost an entry (a deletion bitmap) still asks the
/// runtime. A miss is -1, as `myl_core_dict_find` answers for an index-less table.
fn smallScan(comptime Context: type, c: Context, out: *@import("std").ArrayList(u8), key: SmallKey) Error!void {
    const a = c.a();
    try out.appendSlice(a,
        \\small_table:
        \\  %hashes_at = getelementptr inbounds i8, ptr %meta, i64 16
        \\  %hashes = load ptr, ptr %hashes_at, align 8
        \\  %dead_at = getelementptr inbounds i8, ptr %meta, i64 24
        \\  %dead = load ptr, ptr %dead_at, align 8
        \\  %elen_at = getelementptr inbounds i8, ptr %meta, i64 32
        \\  %elen = load i64, ptr %elen_at, align 8
        \\  %clean = icmp eq ptr %dead, null
        \\  br i1 %clean, label %scan, label %slow
        \\scan:
        \\  %si = phi i64 [ 0, %small_table ], [ %si_next, %scan_next ]
        \\  %more = icmp ult i64 %si, %elen
        \\  br i1 %more, label %scan_hash, label %scan_missing
        \\scan_hash:
        \\  %sh_at = getelementptr inbounds i64, ptr %hashes, i64 %si
        \\  %sh = load i64, ptr %sh_at, align 8
        \\  %sh_hit = icmp eq i64 %sh, %hash
        \\  br i1 %sh_hit, label %scan_key, label %scan_next
        \\scan_key:
        \\
    );
    try out.print(a, "  %soffset = mul i64 %si, {d}\n  %sentry = add i64 %soffset, 32\n" ++
        "  %sstored_at = getelementptr inbounds i8, ptr %dict, i64 %sentry\n  %sstored = load {s}, ptr %sstored_at, align {d}\n" ++
        "  %squery = load {s}, ptr %key, align {d}\n", .{ key.stride, key.key_type, key.key_align, key.key_type, key.key_align });
    if (key.text) {
        try out.appendSlice(a, "  %ssame = call zeroext i1 @myl_core_str_eq(ptr %sstored, ptr %squery)\n");
    } else try out.print(a, "  %ssame = icmp eq {s} %sstored, %squery\n", .{key.key_type});
    try out.appendSlice(a,
        \\  br i1 %ssame, label %scan_found, label %scan_next
        \\scan_found:
        \\  ret i64 %si
        \\scan_next:
        \\  %si_next = add nuw i64 %si, 1
        \\  br label %scan
        \\scan_missing:
        \\  ret i64 -1
        \\
    );
}

/// Emit field-wise hashes and equality; padding and inactive union payloads never participate.
pub fn keyDefinitions(comptime Context: type, c: Context, out: *@import("std").ArrayList(u8), ty: ir.Type, symbol: []const u8) Error!void {
    const m = c.module();
    const a = c.a();
    if (@import("emit_values.zig").dynamic(m.*, ty)) return @import("emit_values.zig").key(Context, c, out, ty, symbol);
    switch (m.kind(ty) orelse .box) {
        .record => for (m.compound(ty).record, 0..) |field, i| try keyDefinitions(Context, c, out, field, try childSymbol(Context, c, symbol, i)),
        .@"union" => for (m.compound(ty).@"union", 0..) |field, i| try keyDefinitions(Context, c, out, field, try childSymbol(Context, c, symbol, i)),
        .array => try keyDefinitions(Context, c, out, m.compound(ty).array.elem, try childSymbol(Context, c, symbol, 0)),
        else => {},
    }
    try out.print(a, "define internal i64 {s}.hash(ptr %key) nounwind {{\nentry:\n", .{symbol});
    switch (m.kind(ty) orelse .box) {
        .record => {
            try out.appendSlice(a, "  %h0 = add i64 0, 0\n");
            for (m.compound(ty).record, 0..) |_, i| {
                try out.print(a, "  %p{d} = getelementptr inbounds i8, ptr %key, i64 {d}\n  %f{d} = call i64 {s}.hash(ptr %p{d})\n" ++
                    "  %m{d} = mul i64 %h{d}, -7046029254386353131\n  %h{d} = xor i64 %m{d}, %f{d}\n", .{ i, m.fieldOffset(ty, i), i, try childSymbol(Context, c, symbol, i), i, i, i, i + 1, i, i });
            }
            try out.print(a, "  ret i64 %h{d}\n", .{m.compound(ty).record.len});
        },
        .array => try arrayKeyHash(Context, c, out, ty, symbol),
        .@"union" => try unionKeyHash(Context, c, out, ty, symbol),
        else => try scalarKeyHash(Context, c, out, ty),
    }
    try out.print(a, "}}\ndefine internal zeroext i1 {s}.same(ptr %left, ptr %right) nounwind {{\nentry:\n", .{symbol});
    switch (m.kind(ty) orelse .box) {
        .record => {
            try out.appendSlice(a, "  %e0 = icmp eq i1 true, true\n");
            for (m.compound(ty).record, 0..) |_, i| {
                try out.print(a, "  %l{d} = getelementptr inbounds i8, ptr %left, i64 {d}\n  %r{d} = getelementptr inbounds i8, ptr %right, i64 {d}\n" ++
                    "  %f{d} = call zeroext i1 {s}.same(ptr %l{d}, ptr %r{d})\n  %e{d} = and i1 %e{d}, %f{d}\n", .{ i, m.fieldOffset(ty, i), i, m.fieldOffset(ty, i), i, try childSymbol(Context, c, symbol, i), i, i, i + 1, i, i });
            }
            try out.print(a, "  ret i1 %e{d}\n", .{m.compound(ty).record.len});
        },
        .array => try arrayKeySame(Context, c, out, ty, symbol),
        .@"union" => try unionKeySame(Context, c, out, ty, symbol),
        else => {
            if (ty == .void) {
                try out.appendSlice(a, "  ret i1 true\n");
            } else {
                const spelling = if (ty == .bool) "i8" else try c.ty(ty);
                try out.print(a, "  %l = load {s}, ptr %left, align {d}\n  %r = load {s}, ptr %right, align {d}\n", .{ spelling, m.alignment(ty), spelling, m.alignment(ty) });
                if (ty == .str or ty == .bytes) try out.appendSlice(a, "  %equal = call zeroext i1 @myl_core_str_eq(ptr %l, ptr %r)\n") else try out.print(a, "  %equal = icmp eq {s} %l, %r\n", .{spelling});
                try out.appendSlice(a, "  ret i1 %equal\n");
            }
        },
    }
    try out.appendSlice(a, "}\n");
}

fn childSymbol(comptime Context: type, c: Context, symbol: []const u8, child: usize) Error![]const u8 {
    return @import("std").fmt.allocPrint(c.a(), "{s}.{d}", .{ symbol, child });
}

fn scalarKeyHash(comptime Context: type, c: Context, out: *@import("std").ArrayList(u8), ty: ir.Type) Error!void {
    const a = c.a();
    if (ty == .void) return out.appendSlice(a, "  ret i64 0\n");
    if (ty == .str or ty == .bytes) {
        try out.appendSlice(a, "  %text = load ptr, ptr %key, align 8\n  %raw = call i32 @myl_core_str_hash(ptr %text)\n  %bits = zext i32 %raw to i64\n");
    } else {
        const bits = if (ty == .bool) 8 else ty.integer().?.bits;
        try out.print(a, "  %raw = load i{d}, ptr %key, align {d}\n", .{ bits, c.module().alignment(ty) });
        if (bits < 64) try out.print(a, "  %bits = zext i{d} %raw to i64\n", .{bits});
    }
    const value = if (ty.integer() != null and ty.integer().?.bits == 64) "%raw" else "%bits";
    try out.print(a, "  %mixed = mul i64 {s}, -7046029254386353131\n  %high = lshr i64 %mixed, 32\n  %hash = xor i64 %mixed, %high\n  ret i64 %hash\n", .{value});
}

fn arrayKeyHash(comptime Context: type, c: Context, out: *@import("std").ArrayList(u8), ty: ir.Type, symbol: []const u8) Error!void {
    const shape = c.module().compound(ty).array;
    try out.print(c.a(), "  br label %loop\nloop:\n  %i = phi i64 [0, %entry], [%next, %body]\n  %h = phi i64 [0, %entry], [%hash, %body]\n" ++
        "  %done = icmp eq i64 %i, {d}\n  br i1 %done, label %end, label %body\nbody:\n  %offset = mul i64 %i, {d}\n" ++
        "  %p = getelementptr inbounds i8, ptr %key, i64 %offset\n  %part = call i64 {s}.hash(ptr %p)\n" ++
        "  %mixed = mul i64 %h, -7046029254386353131\n  %hash = xor i64 %mixed, %part\n  %next = add i64 %i, 1\n  br label %loop\nend:\n" ++
        "  ret i64 %h\n", .{ shape.n, c.module().size(shape.elem), try childSymbol(Context, c, symbol, 0) });
}

fn arrayKeySame(comptime Context: type, c: Context, out: *@import("std").ArrayList(u8), ty: ir.Type, symbol: []const u8) Error!void {
    const shape = c.module().compound(ty).array;
    try out.print(c.a(), "  br label %loop\nloop:\n  %i = phi i64 [0, %entry], [%next, %body]\n  %e = phi i1 [true, %entry], [%same, %body]\n" ++
        "  %done = icmp eq i64 %i, {d}\n  br i1 %done, label %end, label %body\nbody:\n  %offset = mul i64 %i, {d}\n" ++
        "  %l = getelementptr inbounds i8, ptr %left, i64 %offset\n  %r = getelementptr inbounds i8, ptr %right, i64 %offset\n" ++
        "  %part = call zeroext i1 {s}.same(ptr %l, ptr %r)\n  %same = and i1 %e, %part\n  %next = add i64 %i, 1\n  br label %loop\nend:\n" ++
        "  ret i1 %e\n", .{ shape.n, c.module().size(shape.elem), try childSymbol(Context, c, symbol, 0) });
}

fn keyTag(comptime Context: type, c: Context, out: *@import("std").ArrayList(u8), ty: ir.Type, pointer: []const u8, name: []const u8) Error!void {
    const layout = c.module().unionLayout(ty);
    if (layout.form == .niche) {
        try out.print(c.a(), "  %{s}_ptr = load ptr, ptr %{s}, align 8\n  %{s}_null = icmp eq ptr %{s}_ptr, null\n  %{s} = select i1 %{s}_null, i64 {d}, i64 {d}\n", .{
            name,
            pointer,
            name,
            name,
            name,
            name,
            layout.empty_case,
            1 - layout.empty_case,
        });
    } else try out.print(c.a(), "  %{s} = load i64, ptr %{s}, align 8\n", .{ name, pointer });
}

fn keySwitch(comptime Context: type, c: Context, out: *@import("std").ArrayList(u8), ty: ir.Type) Error!void {
    try out.appendSlice(c.a(), "  switch i64 %tag, label %invalid [");
    for (c.module().compound(ty).@"union", 0..) |_, i| try out.print(c.a(), " i64 {d}, label %case{d}", .{ i, i });
    try out.appendSlice(c.a(), " ]\ninvalid:\n  unreachable\n");
}

fn unionKeyHash(comptime Context: type, c: Context, out: *@import("std").ArrayList(u8), ty: ir.Type, symbol: []const u8) Error!void {
    try keyTag(Context, c, out, ty, "key", "tag");
    try out.appendSlice(c.a(), "  %tag_hash = mul i64 %tag, -7046029254386353131\n");
    try keySwitch(Context, c, out, ty);
    for (c.module().compound(ty).@"union", 0..) |_, i| {
        try out.print(c.a(), "case{d}:\n  %p{d} = getelementptr inbounds i8, ptr %key, i64 {d}\n  %part{d} = call i64 {s}.hash(ptr %p{d})\n" ++
            "  %hash{d} = xor i64 %tag_hash, %part{d}\n  ret i64 %hash{d}\n", .{ i, i, @as(u32, if (c.module().unionLayout(ty).form == .niche) 0 else 8), i, try childSymbol(Context, c, symbol, i), i, i, i, i });
    }
}

fn unionKeySame(comptime Context: type, c: Context, out: *@import("std").ArrayList(u8), ty: ir.Type, symbol: []const u8) Error!void {
    try keyTag(Context, c, out, ty, "left", "tag");
    try keyTag(Context, c, out, ty, "right", "rtag");
    try out.appendSlice(c.a(), "  %same_tag = icmp eq i64 %tag, %rtag\n  br i1 %same_tag, label %dispatch, label %different\ndifferent:\n  ret i1 false\ndispatch:\n");
    try keySwitch(Context, c, out, ty);
    for (c.module().compound(ty).@"union", 0..) |_, i| {
        const offset: u32 = if (c.module().unionLayout(ty).form == .niche) 0 else 8;
        try out.print(c.a(), "case{d}:\n  %l{d} = getelementptr inbounds i8, ptr %left, i64 {d}\n  %r{d} = getelementptr inbounds i8, ptr %right, i64 {d}\n" ++
            "  %same{d} = call zeroext i1 {s}.same(ptr %l{d}, ptr %r{d})\n  ret i1 %same{d}\n", .{ i, i, offset, i, offset, i, try childSymbol(Context, c, symbol, i), i, i, i });
    }
}

fn textHashDefinition(comptime Context: type, c: Context, out: *@import("std").ArrayList(u8), symbol: []const u8) Error!void {
    try out.print(c.a(), "define internal i64 {s}.hash(ptr %text) alwaysinline nounwind {{\nentry:\n", .{symbol});
    try out.appendSlice(c.a(),
        \\  %kind_at = getelementptr inbounds i8, ptr %text, i64 4
        \\  %kind = load i32, ptr %kind_at, align 4
        \\  %hashed_bit = and i32 %kind, 512
        \\  %hashed = icmp ne i32 %hashed_bit, 0
        \\  br i1 %hashed, label %cached, label %slow
        \\cached:
        \\  %meta_at = getelementptr inbounds i8, ptr %text, i64 24
        \\  %cached_hash = load i32, ptr %meta_at, align 4
        \\  br label %mix
        \\slow:
        \\  %computed_hash = call i32 @myl_core_str_hash(ptr %text)
        \\  br label %mix
        \\mix:
        \\  %raw = phi i32 [%cached_hash, %cached], [%computed_hash, %slow]
        \\  %bits = zext i32 %raw to i64
        \\  %mixed = mul i64 %bits, -7046029254386353131
        \\  %high = lshr i64 %mixed, 32
        \\  %hash = xor i64 %mixed, %high
        \\  ret i64 %hash
        \\}
        \\
    );
}
