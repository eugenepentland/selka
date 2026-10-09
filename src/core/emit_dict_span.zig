//! Inline borrowed text-key probes: the span is hashed once and compared in place.
//!
//! NEW-CORE-S1-VIEW-2: the probe of a borrowed span (`dict_find` with a `str_view` key)
//! is inline for every table shape. A table without an index scans its cached hashes and
//! skips entries a deletion left dead; an indexed table probes the first 16-slot control
//! group inline. Only a full first group asks the runtime. Candidate keys compare their
//! length and then their octets (NEW-CORE-S1-VIEW-3): up to 16 octets with overlapping
//! word loads that stay inside both spans, longer ones with `memcmp`.
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

/// Emit `SYMBOL.find_span` and the span comparison it inlines.
pub fn definition(context: anytype, out: *std.ArrayList(u8), dict_type: ir.Type, symbol: []const u8) Error!void {
    const arena = context.a();
    try declare(context, "myl_core_span_hash", "declare i32 @myl_core_span_hash(ptr, i64) nounwind\n");
    try declare(context, "memcmp", "declare i32 @memcmp(ptr, ptr, i64) nounwind\n");
    const module = context.module();
    const shape = module.compound(dict_type).dict;
    const value_offset = std.mem.alignForward(u32, module.size(shape.key), module.alignment(shape.value));
    const stride = @max(1, std.mem.alignForward(u32, value_offset + module.size(shape.value), @max(module.alignment(shape.key), module.alignment(shape.value))));
    try sameDefinition(arena, out, symbol);
    try out.print(arena, "define internal i64 {s}.find_span(ptr %dict, ptr %data, i64 %length) alwaysinline nounwind {{\nentry:\n", .{symbol});
    try out.appendSlice(arena,
        \\  %raw = call i32 @myl_core_span_hash(ptr %data, i64 %length)
        \\  %bits = zext i32 %raw to i64
        \\  %mixed = mul i64 %bits, -7046029254386353131
        \\  %high = lshr i64 %mixed, 32
        \\  %hash = xor i64 %mixed, %high
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
        \\  %candidate_bits = phi i32 [ %matches, %group ], [ %remaining, %next ]
        \\  %none = icmp eq i32 %candidate_bits, 0
        \\  br i1 %none, label %empty, label %candidate
        \\candidate:
        \\  %bit = call i32 @llvm.cttz.i32(i32 %candidate_bits, i1 false)
        \\  %raw_slot = add i32 %home, %bit
        \\  %slot = and i32 %raw_slot, %mask
        \\  %slot64 = zext i32 %slot to i64
        \\  %number_at = getelementptr inbounds i32, ptr %numbers, i64 %slot64
        \\  %number32 = load i32, ptr %number_at, align 4
        \\  %entry_number = zext i32 %number32 to i64
        \\
    );
    try out.print(arena, "  %offset = mul i64 %entry_number, {d}\n  %entry_offset = add i64 %offset, 32\n", .{stride});
    try out.print(arena,
        \\  %stored_at = getelementptr inbounds i8, ptr %dict, i64 %entry_offset
        \\  %stored = load ptr, ptr %stored_at, align 8
        \\  %same = call i1 {s}.span_same(ptr %stored, ptr %data, i64 %length)
        \\  br i1 %same, label %found, label %next
        \\found:
        \\  ret i64 %entry_number
        \\next:
        \\  %one_less = sub i32 %candidate_bits, 1
        \\  %remaining = and i32 %candidate_bits, %one_less
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
        \\small_table:
        \\  %hashes_at = getelementptr inbounds i8, ptr %meta, i64 16
        \\  %hashes = load ptr, ptr %hashes_at, align 8
        \\  %dead_at = getelementptr inbounds i8, ptr %meta, i64 24
        \\  %dead = load ptr, ptr %dead_at, align 8
        \\  %clean = icmp eq ptr %dead, null
        \\  %elen_at = getelementptr inbounds i8, ptr %meta, i64 32
        \\  %elen = load i64, ptr %elen_at, align 8
        \\  br label %scan
        \\scan:
        \\  %number = phi i64 [ 0, %small_table ], [ %scan_following, %scan_next ]
        \\  %more = icmp ult i64 %number, %elen
        \\  br i1 %more, label %scan_hash, label %scan_missing
        \\scan_hash:
        \\  %hash_at = getelementptr inbounds i64, ptr %hashes, i64 %number
        \\  %stored_hash = load i64, ptr %hash_at, align 8
        \\  %hash_match = icmp eq i64 %stored_hash, %hash
        \\  br i1 %hash_match, label %scan_live, label %scan_next
        \\scan_live:
        \\  br i1 %clean, label %scan_key, label %scan_dead
        \\scan_dead:
        \\  %dead_byte_number = lshr i64 %number, 3
        \\  %dead_byte_at = getelementptr inbounds i8, ptr %dead, i64 %dead_byte_number
        \\  %dead_byte = load i8, ptr %dead_byte_at, align 1
        \\  %dead_shift64 = and i64 %number, 7
        \\  %dead_shift = trunc i64 %dead_shift64 to i8
        \\  %dead_bits = lshr i8 %dead_byte, %dead_shift
        \\  %dead_bit = and i8 %dead_bits, 1
        \\  %gone = icmp ne i8 %dead_bit, 0
        \\  br i1 %gone, label %scan_next, label %scan_key
        \\scan_key:
        \\
    , .{symbol});
    try out.print(arena, "  %scan_offset = mul i64 %number, {d}\n  %scan_entry = add i64 %scan_offset, 32\n", .{stride});
    try out.print(arena,
        \\  %scan_stored_at = getelementptr inbounds i8, ptr %dict, i64 %scan_entry
        \\  %scan_stored = load ptr, ptr %scan_stored_at, align 8
        \\  %scan_same = call i1 {s}.span_same(ptr %scan_stored, ptr %data, i64 %length)
        \\  br i1 %scan_same, label %scan_found, label %scan_next
        \\scan_found:
        \\  ret i64 %number
        \\scan_next:
        \\  %scan_following = add nuw i64 %number, 1
        \\  br label %scan
        \\scan_missing:
        \\  ret i64 -1
        \\slow:
        \\  %result = call i64 @myl_core_dict_find_span(ptr %dict, ptr %data, i64 %length)
        \\  ret i64 %result
        \\}}
        \\
    , .{symbol});
}

/// `SYMBOL.span_same(stored, data, length)`: whether text block `stored` holds exactly the
/// `length` octets at `data`. Short spans compare their first and last word (or half
/// word, or the first, middle and last octet), which together cover every octet.
fn sameDefinition(arena: std.mem.Allocator, out: *std.ArrayList(u8), symbol: []const u8) Error!void {
    try out.print(arena, "define internal i1 {s}.span_same(ptr %stored, ptr %data, i64 %length) alwaysinline nounwind {{\nentry:\n", .{symbol});
    try out.print(arena,
        \\  %length_at = getelementptr inbounds i8, ptr %stored, i64 8
        \\  %stored_length = load i64, ptr %length_at, align 8
        \\  %length_match = icmp eq i64 %stored_length, %length
        \\  br i1 %length_match, label %octets, label %different
        \\different:
        \\  ret i1 false
        \\octets:
        \\  %bytes = getelementptr inbounds i8, ptr %stored, i64 32
        \\  %short = icmp ule i64 %length, 16
        \\  br i1 %short, label %short_span, label %long_span
        \\long_span:
        \\  %comparison = call i32 @memcmp(ptr %bytes, ptr %data, i64 %length)
        \\  %long_equal = icmp eq i32 %comparison, 0
        \\  ret i1 %long_equal
        \\short_span:
        \\  %words = icmp uge i64 %length, 8
        \\  br i1 %words, label %word8, label %below8
        \\word8:
        \\  %tail8 = sub i64 %length, 8
        \\  %equal8 = call i1 {[symbol]s}.span_pair.i64(ptr %bytes, ptr %data, i64 %tail8)
        \\  ret i1 %equal8
        \\below8:
        \\  %halves = icmp uge i64 %length, 4
        \\  br i1 %halves, label %word4, label %below4
        \\word4:
        \\  %tail4 = sub i64 %length, 4
        \\  %equal4 = call i1 {[symbol]s}.span_pair.i32(ptr %bytes, ptr %data, i64 %tail4)
        \\  ret i1 %equal4
        \\below4:
        \\  %nothing = icmp eq i64 %length, 0
        \\  br i1 %nothing, label %same_empty, label %octet
        \\same_empty:
        \\  ret i1 true
        \\octet:
        \\  %middle = lshr i64 %length, 1
        \\  %last = sub i64 %length, 1
        \\  %first_equal = call i1 {[symbol]s}.span_octet(ptr %bytes, ptr %data, i64 0)
        \\  %middle_equal = call i1 {[symbol]s}.span_octet(ptr %bytes, ptr %data, i64 %middle)
        \\  %last_equal = call i1 {[symbol]s}.span_octet(ptr %bytes, ptr %data, i64 %last)
        \\  %two = and i1 %first_equal, %middle_equal
        \\  %three = and i1 %two, %last_equal
        \\  ret i1 %three
        \\}}
        \\
    , .{ .symbol = symbol });
    try helpers(arena, out, symbol);
}

/// The word-pair and octet comparisons `SYMBOL.span_same` inlines.
fn helpers(arena: std.mem.Allocator, out: *std.ArrayList(u8), symbol: []const u8) Error!void {
    for ([_][]const u8{ "i64", "i32" }) |word| {
        try out.print(arena,
            \\define internal i1 {s}.span_pair.{s}(ptr %left, ptr %right, i64 %tail) alwaysinline nounwind {{
            \\entry:
            \\  %left_first = load {s}, ptr %left, align 1
            \\  %right_first = load {s}, ptr %right, align 1
            \\  %left_tail_at = getelementptr inbounds i8, ptr %left, i64 %tail
            \\  %right_tail_at = getelementptr inbounds i8, ptr %right, i64 %tail
            \\  %left_tail = load {s}, ptr %left_tail_at, align 1
            \\  %right_tail = load {s}, ptr %right_tail_at, align 1
            \\  %first_bits = xor {s} %left_first, %right_first
            \\  %tail_bits = xor {s} %left_tail, %right_tail
            \\  %bits = or {s} %first_bits, %tail_bits
            \\  %equal = icmp eq {s} %bits, 0
            \\  ret i1 %equal
            \\}}
            \\
        , .{ symbol, word, word, word, word, word, word, word, word, word });
    }
    try out.print(arena,
        \\define internal i1 {s}.span_octet(ptr %left, ptr %right, i64 %at) alwaysinline nounwind {{
        \\entry:
        \\  %left_at = getelementptr inbounds i8, ptr %left, i64 %at
        \\  %right_at = getelementptr inbounds i8, ptr %right, i64 %at
        \\  %left_octet = load i8, ptr %left_at, align 1
        \\  %right_octet = load i8, ptr %right_at, align 1
        \\  %equal = icmp eq i8 %left_octet, %right_octet
        \\  ret i1 %equal
        \\}}
        \\
    , .{symbol});
}

fn declare(context: anytype, symbol: []const u8, text: []const u8) Error!void {
    for (context.state.declared.items) |name| if (std.mem.eql(u8, name, symbol)) return;
    try context.state.declared.append(context.a(), symbol);
    try context.state.externs.appendSlice(context.a(), text);
}
