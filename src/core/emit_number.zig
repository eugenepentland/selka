//! Safe inline SWAR parsing with exact grammar fallback and early invalid rejection.
const std = @import("std");

/// Emit the internal always-inline parser helpers used by str_parse_int.
pub fn prelude(allocator: std.mem.Allocator, out: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
    try out.appendSlice(allocator,
        \\define internal fastcc { i1, i64 } @myl_core_digits8(ptr %data, i64 %n) alwaysinline nounwind {
        \\entry:
        \\  %eight = icmp eq i64 %n, 8
        \\  br i1 %eight, label %load8, label %short
        \\short:
        \\  %five_or_more = icmp uge i64 %n, 5
        \\  br i1 %five_or_more, label %loadwide, label %tiny
        \\tiny:
        \\  switch i64 %n, label %bad [
        \\    i64 1, label %load1
        \\    i64 2, label %load2
        \\    i64 3, label %load3
        \\    i64 4, label %load4
        \\  ]
        \\load1:
        \\  %raw1 = load i8, ptr %data, align 1
        \\  %wide1 = zext i8 %raw1 to i64
        \\  br label %word
        \\load2:
        \\  %raw2 = load i16, ptr %data, align 1
        \\  %wide2 = zext i16 %raw2 to i64
        \\  br label %word
        \\load3:
        \\  %raw3 = load i24, ptr %data, align 1
        \\  %wide3 = zext i24 %raw3 to i64
        \\  br label %word
        \\load4:
        \\  %raw4 = load i32, ptr %data, align 1
        \\  %wide4 = zext i32 %raw4 to i64
        \\  br label %word
        \\loadwide:
        \\  %low32 = load i32, ptr %data, align 1
        \\  %tail_index = sub i64 %n, 4
        \\  %tail_at = getelementptr inbounds i8, ptr %data, i64 %tail_index
        \\  %tail32 = load i32, ptr %tail_at, align 1
        \\  %low64 = zext i32 %low32 to i64
        \\  %tail64 = zext i32 %tail32 to i64
        \\  %tail_shift = shl i64 %tail_index, 3
        \\  %tail_aligned = shl i64 %tail64, %tail_shift
        \\  %wide_word = or i64 %low64, %tail_aligned
        \\  br label %word
        \\load8:
        \\  %raw8 = load i64, ptr %data, align 1
        \\  br label %word
        \\word:
        \\  %raw = phi i64 [ %wide1, %load1 ], [ %wide2, %load2 ], [ %wide3, %load3 ], [ %wide4, %load4 ], [ %wide_word, %loadwide ], [ %raw8, %load8 ]
        \\  %four_digits = icmp ule i64 %n, 4
        \\  br i1 %four_digits, label %small_word, label %large_word
        \\small_word:
        \\  %raw_small = trunc i64 %raw to i32
        \\  %n_small = trunc i64 %n to i32
        \\  %missing_small = sub i32 4, %n_small
        \\  %shift_small = shl i32 %missing_small, 3
        \\  %aligned_small = shl i32 %raw_small, %shift_small
        \\  %missing_mask_small = shl i32 -1, %shift_small
        \\  %padding_mask_small = xor i32 %missing_mask_small, -1
        \\  %zeros_small = and i32 808464432, %padding_mask_small
        \\  %word_small = or i32 %aligned_small, %zeros_small
        \\  %below_small = sub i32 %word_small, 808464432
        \\  %above_small = add i32 %word_small, 1179010630
        \\  %either_small = or i32 %below_small, %above_small
        \\  %high_small = and i32 %either_small, -2139062144
        \\  %valid_small = icmp eq i32 %high_small, 0
        \\  %pair_product_small = mul i32 %below_small, 2561
        \\  %pairs_full_small = lshr i32 %pair_product_small, 8
        \\  %pairs_small = and i32 %pairs_full_small, 16711935
        \\  %number_product_small = mul i32 %pairs_small, 6553601
        \\  %number_small = lshr i32 %number_product_small, 16
        \\  %wide_small = zext i32 %number_small to i64
        \\  %partial_small = insertvalue { i1, i64 } poison, i1 %valid_small, 0
        \\  %result_small = insertvalue { i1, i64 } %partial_small, i64 %wide_small, 1
        \\  ret { i1, i64 } %result_small
        \\large_word:
        \\  %missing = sub i64 8, %n
        \\  %shift = shl i64 %missing, 3
        \\  %aligned = shl i64 %raw, %shift
        \\  %missing_mask = shl i64 -1, %shift
        \\  %padding_mask = xor i64 %missing_mask, -1
        \\  %zeros = and i64 3472328296227680304, %padding_mask
        \\  %word_value = or i64 %aligned, %zeros
        \\  %below = sub i64 %word_value, 3472328296227680304
        \\  %above = add i64 %word_value, 5063812098665367110
        \\  %either = or i64 %below, %above
        \\  %high = and i64 %either, -9187201950435737472
        \\  %valid = icmp eq i64 %high, 0
        \\  %times10 = mul i64 %below, 10
        \\  %next_byte = lshr i64 %below, 8
        \\  %pairs_full = add i64 %times10, %next_byte
        \\  %pairs_right_full = lshr i64 %pairs_full, 16
        \\  %pairs_left = and i64 %pairs_full, 1095216660735
        \\  %pairs_right = and i64 %pairs_right_full, 1095216660735
        \\  %left_weighted = mul i64 %pairs_left, 4294967296000100
        \\  %right_weighted = mul i64 %pairs_right, 42949672960001
        \\  %number_full = add i64 %left_weighted, %right_weighted
        \\  %number = lshr i64 %number_full, 32
        \\  %partial = insertvalue { i1, i64 } poison, i1 %valid, 0
        \\  %result = insertvalue { i1, i64 } %partial, i64 %number, 1
        \\  ret { i1, i64 } %result
        \\bad:
        \\  ret { i1, i64 } zeroinitializer
        \\}
        \\
        \\define internal fastcc i1 @myl_core_parse_int_inline(ptr %text, ptr %out) alwaysinline nounwind {
        \\entry:
        \\  %len_at = getelementptr inbounds i8, ptr %text, i64 8
        \\  %len = load i64, ptr %len_at, align 8
        \\  %has_bytes = icmp ugt i64 %len, 0
        \\  br i1 %has_bytes, label %head, label %invalid
        \\head:
        \\  %data = getelementptr inbounds i8, ptr %text, i64 32
        \\  %first = load i8, ptr %data, align 1
        \\  %minus = icmp eq i8 %first, 45
        \\  %plus = icmp eq i8 %first, 43
        \\  %signed = or i1 %minus, %plus
        \\  %first_digit = sub i8 %first, 48
        \\  %first_numeric = icmp ult i8 %first_digit, 10
        \\  %start_ok = or i1 %first_numeric, %signed
        \\  %last_index = sub i64 %len, 1
        \\  %last_at = getelementptr inbounds i8, ptr %data, i64 %last_index
        \\  %last = load i8, ptr %last_at, align 1
        \\  %last_digit = sub i8 %last, 48
        \\  %last_numeric = icmp ult i8 %last_digit, 10
        \\  %ends_ok = and i1 %start_ok, %last_numeric
        \\  br i1 %ends_ok, label %plain_head, label %boundary
        \\boundary:
        \\  %first_space = icmp ule i8 %first, 32
        \\  %last_space = icmp ule i8 %last, 32
        \\  %maybe_space = or i1 %first_space, %last_space
        \\  br i1 %maybe_space, label %slow, label %invalid
        \\plain_head:
        \\  %skip = zext i1 %signed to i64
        \\  %n = sub i64 %len, %skip
        \\  %plain = icmp ule i64 %n, 8
        \\  br i1 %plain, label %first_word, label %slow
        \\first_word:
        \\  %digits = getelementptr inbounds i8, ptr %data, i64 %skip
        \\  %left = call fastcc { i1, i64 } @myl_core_digits8(ptr %digits, i64 %n)
        \\  %left_ok = extractvalue { i1, i64 } %left, 0
        \\  %magnitude = extractvalue { i1, i64 } %left, 1
        \\  br i1 %left_ok, label %finish, label %slow
        \\finish:
        \\  %negated = sub i64 0, %magnitude
        \\  %value = select i1 %minus, i64 %negated, i64 %magnitude
        \\  store i64 %value, ptr %out, align 8
        \\  ret i1 true
        \\invalid:
        \\  ret i1 false
        \\slow:
        \\  %parsed = call zeroext i1 @myl_core_str_parse_int(ptr %text, ptr %out)
        \\  ret i1 %parsed
        \\}
        \\
    );
}
