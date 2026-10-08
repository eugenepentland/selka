//! Inline borrowed text-key probes only for clean, index-less dictionaries.
const std = @import("std");
const ir = @import("ir.zig");

/// Allocation or an unsupported descriptor can stop emission.
pub const Error = error{ OutOfMemory, UnsupportedEntry, UnsupportedInstruction };

/// Whether this dictionary descriptor has a borrowed-span lookup in the module.
pub fn used(module: *const ir.Module, dict_type: ir.Type) bool {
    for (module.functions.items) |function| {
        for (function.insts.items) |inst| {
            if (inst.op != .dict_find or inst.b == .none) continue;
            if (function.inst(function.resolve(inst.a)).ty == dict_type and function.inst(function.resolve(inst.b)).ty == .str_view) return true;
        }
    }
    return false;
}

/// Emit the small-table span probe, retaining the runtime path for indexes or deletions.
pub fn definition(context: anytype, out: *std.ArrayList(u8), dict_type: ir.Type, symbol: []const u8) Error!void {
    const arena = context.a();
    try declare(context, "myl_core_span_hash", "declare i32 @myl_core_span_hash(ptr, i64) nounwind\n");
    try declare(context, "memcmp", "declare i32 @memcmp(ptr, ptr, i64) nounwind\n");
    const module = context.module();
    const shape = module.compound(dict_type).dict;
    const value_offset = std.mem.alignForward(u32, module.size(shape.key), module.alignment(shape.value));
    const stride = @max(1, std.mem.alignForward(u32, value_offset + module.size(shape.value), @max(module.alignment(shape.key), module.alignment(shape.value))));
    try out.print(arena, "define internal i64 {s}.find_span(ptr %dict, ptr %data, i64 %length) alwaysinline nounwind {{\nentry:\n", .{symbol});
    try out.appendSlice(arena,
        \\  %meta_at = getelementptr inbounds i8, ptr %dict, i64 24
        \\  %meta = load ptr, ptr %meta_at, align 8
        \\  %index_at = getelementptr inbounds i8, ptr %meta, i64 8
        \\  %index = load ptr, ptr %index_at, align 8
        \\  %dead_at = getelementptr inbounds i8, ptr %meta, i64 24
        \\  %dead = load ptr, ptr %dead_at, align 8
        \\  %small = icmp eq ptr %index, null
        \\  %clean = icmp eq ptr %dead, null
        \\  %inline = and i1 %small, %clean
        \\  br i1 %inline, label %small_table, label %slow
        \\small_table:
        \\  %raw = call i32 @myl_core_span_hash(ptr %data, i64 %length)
        \\  %bits = zext i32 %raw to i64
        \\  %mixed = mul i64 %bits, -7046029254386353131
        \\  %high = lshr i64 %mixed, 32
        \\  %hash = xor i64 %mixed, %high
        \\  %hashes_at = getelementptr inbounds i8, ptr %meta, i64 16
        \\  %hashes = load ptr, ptr %hashes_at, align 8
        \\  %elen_at = getelementptr inbounds i8, ptr %meta, i64 32
        \\  %elen = load i64, ptr %elen_at, align 8
        \\  br label %scan
        \\scan:
        \\  %number = phi i64 [ 0, %small_table ], [ %next, %scan_next ]
        \\  %more = icmp ult i64 %number, %elen
        \\  br i1 %more, label %scan_hash, label %missing
        \\scan_hash:
        \\  %hash_at = getelementptr inbounds i64, ptr %hashes, i64 %number
        \\  %stored_hash = load i64, ptr %hash_at, align 8
        \\  %hash_match = icmp eq i64 %stored_hash, %hash
        \\  br i1 %hash_match, label %scan_key, label %scan_next
        \\scan_key:
        \\
    );
    try out.print(arena, "  %offset = mul i64 %number, {d}\n  %entry_offset = add i64 %offset, 32\n", .{stride});
    try out.appendSlice(arena,
        \\  %stored_at = getelementptr inbounds i8, ptr %dict, i64 %entry_offset
        \\  %stored = load ptr, ptr %stored_at, align 8
        \\  %length_at = getelementptr inbounds i8, ptr %stored, i64 8
        \\  %stored_length = load i64, ptr %length_at, align 8
        \\  %length_match = icmp eq i64 %stored_length, %length
        \\  br i1 %length_match, label %compare, label %scan_next
        \\compare:
        \\  %stored_data = getelementptr inbounds i8, ptr %stored, i64 32
        \\  %comparison = call i32 @memcmp(ptr %stored_data, ptr %data, i64 %length)
        \\  %equal = icmp eq i32 %comparison, 0
        \\  br i1 %equal, label %found, label %scan_next
        \\found:
        \\  ret i64 %number
        \\scan_next:
        \\  %next = add nuw i64 %number, 1
        \\  br label %scan
        \\missing:
        \\  ret i64 -1
        \\slow:
        \\  %result = call i64 @myl_core_dict_find_span(ptr %dict, ptr %data, i64 %length)
        \\  ret i64 %result
        \\}
        \\
    );
}

fn declare(context: anytype, symbol: []const u8, text: []const u8) Error!void {
    for (context.state.declared.items) |name| if (std.mem.eql(u8, name, symbol)) return;
    try context.state.declared.append(context.a(), symbol);
    try context.state.externs.appendSlice(context.a(), text);
}
