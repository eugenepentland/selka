define internal fastcc ptr @my.frequencies(ptr %p0, i64 range(i64 0, -9223372036854775808) %p1) unnamed_addr #5 !dbg !4 {
entry:
  %stack.64 = alloca [8 x i8], align 8
  %stack.65 = alloca [8 x i8], align 8
  %v3 = tail call ptr @myl_core_dict_new(i64 0, ptr nonnull @myl.dict.0)
  %v5 = tail call i64 @myl_core_str_chars(ptr %p0)
  %hi.1 = icmp slt i64 %v5, 0
  br i1 %hi.1, label %trap.2, label %b0.3, !prof !9

trap.2:                                           ; preds = %entry
  tail call void @myl_core_trap(ptr nonnull @myl.site.7, i64 %v5, i64 0) #11
  unreachable

b0.3:                                             ; preds = %entry
  %v7 = sub nsw i64 %v5, %p1
  %p.4 = tail call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %v7, i64 1)
  %v9 = extractvalue { i64, i1 } %p.4, 0
  %o.5 = extractvalue { i64, i1 } %p.4, 1
  br i1 %o.5, label %trap.6, label %b1.preheader, !prof !9

b1.preheader:                                     ; preds = %b0.3
  %v1326 = icmp sgt i64 %v9, 0
  br i1 %v1326, label %b2.lr.ph, label %b4

b2.lr.ph:                                         ; preds = %b1.preheader
  %slicekind.12 = getelementptr inbounds nuw i8, ptr %p0, i64 4
  %slicelen.19 = getelementptr inbounds nuw i8, ptr %p0, i64 8
  %slicedata.43 = getelementptr inbounds nuw i8, ptr %p0, i64 32
  br label %b2

trap.6:                                           ; preds = %b0.3
  tail call void @myl_core_trap(ptr nonnull @myl.site.8, i64 %v7, i64 1) #11
  unreachable

b2:                                               ; preds = %b2.lr.ph, %b10
  %v1928 = phi ptr [ %v3, %b2.lr.ph ], [ %v41, %b10 ]
  %v1127 = phi i64 [ 0, %b2.lr.ph ], [ %v46, %b10 ]
  %p.8 = call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %v1127, i64 %p1)
  %v17 = extractvalue { i64, i1 } %p.8, 0
  %o.9 = extractvalue { i64, i1 } %p.8, 1
  br i1 %o.9, label %trap.10, label %b2.11, !prof !9

trap.10:                                          ; preds = %b2
  call void @myl_core_trap(ptr nonnull @myl.site.9, i64 %v1127, i64 %p1) #11
  unreachable

b2.11:                                            ; preds = %b2
  %slicekind.13 = load i32, ptr %slicekind.12, align 4
  %sliceascii.14 = and i32 %slicekind.13, 256
  %sliceascii.15.not = icmp eq i32 %sliceascii.14, 0
  br i1 %sliceascii.15.not, label %sliceslow.17, label %slicefast.16

slicefast.16:                                     ; preds = %b2.11
  %slicelen.20 = load i64, ptr %slicelen.19, align 8
  %clamped.27 = call i64 @llvm.smin.i64(i64 %v1127, i64 %slicelen.20)
  %clampneg.28 = icmp slt i64 %v17, 0
  %clampwrap.29 = select i1 %clampneg.28, i64 %slicelen.20, i64 0
  %clampend.30 = add i64 %clampwrap.29, %v17
  %clamplow.32 = call i64 @llvm.smax.i64(i64 %clampend.30, i64 0)
  %clamped.34 = call i64 @llvm.smin.i64(i64 %clamplow.32, i64 %slicelen.20)
  %slicewidth.35 = sub i64 %clamped.34, %clamped.27
  %slicewidth.37 = call i64 @llvm.smax.i64(i64 %slicewidth.35, i64 0)
  br label %slicejoin.18

sliceslow.17:                                     ; preds = %b2.11
  %slicespan.38 = call { i64, i64 } @myl_core_ir_str_slice_span(ptr nonnull %p0, i64 %v1127, i64 %v17)
  %sliceat.39 = extractvalue { i64, i64 } %slicespan.38, 0
  %slicewidth.40 = extractvalue { i64, i64 } %slicespan.38, 1
  br label %slicejoin.18

slicejoin.18:                                     ; preds = %sliceslow.17, %slicefast.16
  %sliceat.41 = phi i64 [ %clamped.27, %slicefast.16 ], [ %sliceat.39, %sliceslow.17 ]
  %slicewidth.42 = phi i64 [ %slicewidth.37, %slicefast.16 ], [ %slicewidth.40, %sliceslow.17 ]
  %slicedata.44 = getelementptr inbounds i8, ptr %slicedata.43, i64 %sliceat.41
  %raw.i = call i32 @myl_core_span_hash(ptr nonnull %slicedata.44, i64 %slicewidth.42)
  %bits.i = zext i32 %raw.i to i64
  %mixed.i = mul i64 %bits.i, -7046029254386353131
  %high.i = lshr i64 %mixed.i, 32
  %hash.i = xor i64 %high.i, %mixed.i
  %meta_at.i = getelementptr inbounds nuw i8, ptr %v1928, i64 24
  %meta.i = load ptr, ptr %meta_at.i, align 8
  %index_at.i = getelementptr inbounds nuw i8, ptr %meta.i, i64 8
  %index.i = load ptr, ptr %index_at.i, align 8
  %small.i = icmp eq ptr %index.i, null
  br i1 %small.i, label %small_table.i, label %group.i

group.i:                                          ; preds = %slicejoin.18
  %slots.i = load i32, ptr %index.i, align 4
  %log.i = call range(i32 0, 33) i32 @llvm.cttz.i32(i32 %slots.i, i1 false)
  %shift32.i = sub nuw nsw i32 64, %log.i
  %shift.i = zext nneg i32 %shift32.i to i64
  %home64.i = lshr i64 %hash.i, %shift.i
  %home.i = trunc nuw i64 %home64.i to i32
  %mask.i = add i32 %slots.i, -1
  %control.i = getelementptr inbounds nuw i8, ptr %index.i, i64 16
  %group_at.i = getelementptr inbounds nuw i8, ptr %control.i, i64 %home64.i
  %controls.i = load <16 x i8>, ptr %group_at.i, align 1
  %tag.i = trunc i64 %hash.i to i8
  %tag7.i = and i8 %tag.i, 127
  %tag0.i = insertelement <16 x i8> poison, i8 %tag7.i, i64 0
  %tags.i = shufflevector <16 x i8> %tag0.i, <16 x i8> poison, <16 x i32> zeroinitializer
  %tagmatch.i = icmp eq <16 x i8> %controls.i, %tags.i
  %match16.i = bitcast <16 x i1> %tagmatch.i to i16
  %room.i = add i32 %slots.i, 30
  %number_offset.i = and i32 %room.i, -16
  %number_offset64.i = zext i32 %number_offset.i to i64
  %numbers.i = getelementptr inbounds nuw i8, ptr %control.i, i64 %number_offset64.i
  %none.i22 = icmp eq i16 %match16.i, 0
  br i1 %none.i22, label %empty.i, label %candidate.i.lr.ph

candidate.i.lr.ph:                                ; preds = %group.i
  %matches.i = zext i16 %match16.i to i32
  %short.i7.i = icmp ult i64 %slicewidth.42, 17
  %words.i12.i = icmp samesign ugt i64 %slicewidth.42, 7
  %halves.i14.i = icmp samesign ugt i64 %slicewidth.42, 3
  %nothing.i16.i = icmp eq i64 %slicewidth.42, 0
  %middle.i18.i = lshr i64 %slicewidth.42, 1
  %last.i19.i = add nsw i64 %slicewidth.42, -1
  %right_at.i55.i = getelementptr inbounds nuw i8, ptr %slicedata.44, i64 %middle.i18.i
  %right_at.i.i = getelementptr inbounds nuw i8, ptr %slicedata.44, i64 %last.i19.i
  %tail4.i26.i = add nsw i64 %slicewidth.42, -4
  %right_tail_at.i42.i = getelementptr inbounds nuw i8, ptr %slicedata.44, i64 %tail4.i26.i
  %tail8.i29.i = add nsw i64 %slicewidth.42, -8
  %right_tail_at.i.i = getelementptr inbounds nuw i8, ptr %slicedata.44, i64 %tail8.i29.i
  br label %candidate.i

candidate.i:                                      ; preds = %candidate.i.lr.ph, %next.i
  %candidate_bits.i23 = phi i32 [ %matches.i, %candidate.i.lr.ph ], [ %remaining.i, %next.i ]
  %bit.i = call range(i32 0, 33) i32 @llvm.cttz.i32(i32 %candidate_bits.i23, i1 true)
  %raw_slot.i = add i32 %bit.i, %home.i
  %slot.i = and i32 %raw_slot.i, %mask.i
  %slot64.i = zext i32 %slot.i to i64
  %number_at.i = getelementptr inbounds nuw i32, ptr %numbers.i, i64 %slot64.i
  %number32.i = load i32, ptr %number_at.i, align 4
  %entry_number.i = zext i32 %number32.i to i64
  %offset.i = shl nuw nsw i64 %entry_number.i, 4
  %0 = getelementptr inbounds nuw i8, ptr %v1928, i64 %offset.i
  %stored_at.i = getelementptr inbounds nuw i8, ptr %0, i64 32
  %stored.i = load ptr, ptr %stored_at.i, align 8
  %length_at.i1.i = getelementptr inbounds nuw i8, ptr %stored.i, i64 8
  %stored_length.i2.i = load i64, ptr %length_at.i1.i, align 8
  %length_match.i3.i = icmp eq i64 %stored_length.i2.i, %slicewidth.42
  br i1 %length_match.i3.i, label %octets.i5.i, label %next.i

octets.i5.i:                                      ; preds = %candidate.i
  %bytes.i6.i = getelementptr inbounds nuw i8, ptr %stored.i, i64 32
  br i1 %short.i7.i, label %short_span.i11.i, label %myl.dict.0.span_same.exit31.i

short_span.i11.i:                                 ; preds = %octets.i5.i
  br i1 %words.i12.i, label %word8.i28.i, label %below8.i13.i

word8.i28.i:                                      ; preds = %short_span.i11.i
  %left_first.i.i = load i64, ptr %bytes.i6.i, align 1
  %right_first.i.i = load i64, ptr %slicedata.44, align 1
  %left_tail_at.i.i = getelementptr inbounds nuw i8, ptr %bytes.i6.i, i64 %tail8.i29.i
  %left_tail.i.i = load i64, ptr %left_tail_at.i.i, align 1
  %right_tail.i.i = load i64, ptr %right_tail_at.i.i, align 1
  %1 = icmp eq i64 %left_first.i.i, %right_first.i.i
  %2 = icmp eq i64 %left_tail.i.i, %right_tail.i.i
  %equal.i.i = and i1 %1, %2
  br i1 %equal.i.i, label %b7.thread, label %next.i

below8.i13.i:                                     ; preds = %short_span.i11.i
  br i1 %halves.i14.i, label %word4.i25.i, label %below4.i15.i

word4.i25.i:                                      ; preds = %below8.i13.i
  %left_first.i39.i = load i32, ptr %bytes.i6.i, align 1
  %right_first.i40.i = load i32, ptr %slicedata.44, align 1
  %left_tail_at.i41.i = getelementptr inbounds nuw i8, ptr %bytes.i6.i, i64 %tail4.i26.i
  %left_tail.i43.i = load i32, ptr %left_tail_at.i41.i, align 1
  %right_tail.i44.i = load i32, ptr %right_tail_at.i42.i, align 1
  %3 = icmp eq i32 %left_first.i39.i, %right_first.i40.i
  %4 = icmp eq i32 %left_tail.i43.i, %right_tail.i44.i
  %equal.i45.i = and i1 %3, %4
  br i1 %equal.i45.i, label %b7.thread, label %next.i

below4.i15.i:                                     ; preds = %below8.i13.i
  br i1 %nothing.i16.i, label %b7.thread, label %octet.i17.i

octet.i17.i:                                      ; preds = %below4.i15.i
  %left_octet.i61.i = load i8, ptr %bytes.i6.i, align 1
  %right_octet.i62.i = load i8, ptr %slicedata.44, align 1
  %equal.i63.i = icmp eq i8 %left_octet.i61.i, %right_octet.i62.i
  %left_at.i54.i = getelementptr inbounds nuw i8, ptr %bytes.i6.i, i64 %middle.i18.i
  %left_octet.i56.i = load i8, ptr %left_at.i54.i, align 1
  %right_octet.i57.i = load i8, ptr %right_at.i55.i, align 1
  %equal.i58.i = icmp eq i8 %left_octet.i56.i, %right_octet.i57.i
  %left_at.i.i = getelementptr inbounds nuw i8, ptr %bytes.i6.i, i64 %last.i19.i
  %left_octet.i.i = load i8, ptr %left_at.i.i, align 1
  %right_octet.i.i = load i8, ptr %right_at.i.i, align 1
  %equal.i53.i = icmp eq i8 %left_octet.i.i, %right_octet.i.i
  %two.i23.i = and i1 %equal.i63.i, %equal.i58.i
  %three.i24.i = and i1 %two.i23.i, %equal.i53.i
  br i1 %three.i24.i, label %b7.thread, label %next.i

myl.dict.0.span_same.exit31.i:                    ; preds = %octets.i5.i
  %bcmp.i9.i = call i32 @bcmp(ptr nonnull %bytes.i6.i, ptr nonnull %slicedata.44, i64 %slicewidth.42)
  %long_equal.i10.i = icmp eq i32 %bcmp.i9.i, 0
  br i1 %long_equal.i10.i, label %b7.thread, label %next.i

next.i:                                           ; preds = %candidate.i, %word8.i28.i, %word4.i25.i, %octet.i17.i, %myl.dict.0.span_same.exit31.i
  %one_less.i = add nsw i32 %candidate_bits.i23, -1
  %remaining.i = and i32 %one_less.i, %candidate_bits.i23
  %none.i = icmp eq i32 %remaining.i, 0
  br i1 %none.i, label %empty.i, label %candidate.i

empty.i:                                          ; preds = %next.i, %group.i
  %empty_match.i = icmp eq <16 x i8> %controls.i, splat (i8 -128)
  %empty16.i = bitcast <16 x i1> %empty_match.i to i16
  %full.i = icmp eq i16 %empty16.i, 0
  br i1 %full.i, label %slow.i, label %missing.i

missing.i:                                        ; preds = %empty.i
  %5 = call range(i16 0, 17) i16 @llvm.cttz.i16(i16 %empty16.i, i1 true)
  %empty_bit.i = zext nneg i16 %5 to i32
  %empty_raw_slot.i = add i32 %home.i, %empty_bit.i
  %empty_slot.i = and i32 %empty_raw_slot.i, %mask.i
  %empty_slot64.i = zext i32 %empty_slot.i to i64
  %probe.i = xor i64 %empty_slot64.i, -1
  br label %b9

small_table.i:                                    ; preds = %slicejoin.18
  %hashes_at.i = getelementptr inbounds nuw i8, ptr %meta.i, i64 16
  %hashes.i = load ptr, ptr %hashes_at.i, align 8
  %dead_at.i = getelementptr inbounds nuw i8, ptr %meta.i, i64 24
  %dead.i = load ptr, ptr %dead_at.i, align 8
  %clean.i = icmp eq ptr %dead.i, null
  %elen_at.i = getelementptr inbounds nuw i8, ptr %meta.i, i64 32
  %elen.i = load i64, ptr %elen_at.i, align 8
  %more.i24.not = icmp eq i64 %elen.i, 0
  br i1 %more.i24.not, label %b9, label %scan_hash.i.lr.ph

scan_hash.i.lr.ph:                                ; preds = %small_table.i
  %short.i.i = icmp ult i64 %slicewidth.42, 17
  %words.i.i = icmp samesign ugt i64 %slicewidth.42, 7
  %halves.i.i = icmp samesign ugt i64 %slicewidth.42, 3
  %nothing.i.i = icmp eq i64 %slicewidth.42, 0
  %middle.i.i = lshr i64 %slicewidth.42, 1
  %last.i.i = add nsw i64 %slicewidth.42, -1
  %right_at.i70.i = getelementptr inbounds nuw i8, ptr %slicedata.44, i64 %middle.i.i
  %right_at.i65.i = getelementptr inbounds nuw i8, ptr %slicedata.44, i64 %last.i.i
  %tail4.i.i = add nsw i64 %slicewidth.42, -4
  %right_tail_at.i49.i = getelementptr inbounds nuw i8, ptr %slicedata.44, i64 %tail4.i.i
  %tail8.i.i = add nsw i64 %slicewidth.42, -8
  %right_tail_at.i35.i = getelementptr inbounds nuw i8, ptr %slicedata.44, i64 %tail8.i.i
  br label %scan_hash.i

scan_hash.i:                                      ; preds = %scan_hash.i.lr.ph, %scan_next.i
  %number.i25 = phi i64 [ 0, %scan_hash.i.lr.ph ], [ %scan_following.i, %scan_next.i ]
  %hash_at.i = getelementptr inbounds i64, ptr %hashes.i, i64 %number.i25
  %stored_hash.i = load i64, ptr %hash_at.i, align 8
  %hash_match.i = icmp eq i64 %stored_hash.i, %hash.i
  br i1 %hash_match.i, label %scan_live.i, label %scan_next.i

scan_live.i:                                      ; preds = %scan_hash.i
  br i1 %clean.i, label %scan_key.i, label %scan_dead.i

scan_dead.i:                                      ; preds = %scan_live.i
  %dead_byte_number.i = lshr i64 %number.i25, 3
  %dead_byte_at.i = getelementptr inbounds nuw i8, ptr %dead.i, i64 %dead_byte_number.i
  %dead_byte.i = load i8, ptr %dead_byte_at.i, align 1
  %6 = trunc i64 %number.i25 to i8
  %dead_shift.i = and i8 %6, 7
  %7 = shl nuw i8 1, %dead_shift.i
  %8 = and i8 %dead_byte.i, %7
  %gone.not.i = icmp eq i8 %8, 0
  br i1 %gone.not.i, label %scan_key.i, label %scan_next.i

scan_key.i:                                       ; preds = %scan_dead.i, %scan_live.i
  %scan_offset.i = shl i64 %number.i25, 4
  %9 = getelementptr i8, ptr %v1928, i64 %scan_offset.i
  %scan_stored_at.i = getelementptr i8, ptr %9, i64 32
  %scan_stored.i = load ptr, ptr %scan_stored_at.i, align 8
  %length_at.i.i = getelementptr inbounds nuw i8, ptr %scan_stored.i, i64 8
  %stored_length.i.i = load i64, ptr %length_at.i.i, align 8
  %length_match.i.i = icmp eq i64 %stored_length.i.i, %slicewidth.42
  br i1 %length_match.i.i, label %octets.i.i, label %scan_next.i

octets.i.i:                                       ; preds = %scan_key.i
  %bytes.i.i = getelementptr inbounds nuw i8, ptr %scan_stored.i, i64 32
  br i1 %short.i.i, label %short_span.i.i, label %myl.dict.0.span_same.exit.i

short_span.i.i:                                   ; preds = %octets.i.i
  br i1 %words.i.i, label %word8.i.i, label %below8.i.i

word8.i.i:                                        ; preds = %short_span.i.i
  %left_first.i32.i = load i64, ptr %bytes.i.i, align 1
  %right_first.i33.i = load i64, ptr %slicedata.44, align 1
  %left_tail_at.i34.i = getelementptr inbounds nuw i8, ptr %bytes.i.i, i64 %tail8.i.i
  %left_tail.i36.i = load i64, ptr %left_tail_at.i34.i, align 1
  %right_tail.i37.i = load i64, ptr %right_tail_at.i35.i, align 1
  %10 = icmp eq i64 %left_first.i32.i, %right_first.i33.i
  %11 = icmp eq i64 %left_tail.i36.i, %right_tail.i37.i
  %equal.i38.i = and i1 %10, %11
  br i1 %equal.i38.i, label %myl.dict.0.find_span.exit, label %scan_next.i

below8.i.i:                                       ; preds = %short_span.i.i
  br i1 %halves.i.i, label %word4.i.i, label %below4.i.i

word4.i.i:                                        ; preds = %below8.i.i
  %left_first.i46.i = load i32, ptr %bytes.i.i, align 1
  %right_first.i47.i = load i32, ptr %slicedata.44, align 1
  %left_tail_at.i48.i = getelementptr inbounds nuw i8, ptr %bytes.i.i, i64 %tail4.i.i
  %left_tail.i50.i = load i32, ptr %left_tail_at.i48.i, align 1
  %right_tail.i51.i = load i32, ptr %right_tail_at.i49.i, align 1
  %12 = icmp eq i32 %left_first.i46.i, %right_first.i47.i
  %13 = icmp eq i32 %left_tail.i50.i, %right_tail.i51.i
  %equal.i52.i = and i1 %12, %13
  br i1 %equal.i52.i, label %myl.dict.0.find_span.exit, label %scan_next.i

below4.i.i:                                       ; preds = %below8.i.i
  br i1 %nothing.i.i, label %myl.dict.0.find_span.exit, label %octet.i.i

octet.i.i:                                        ; preds = %below4.i.i
  %left_octet.i76.i = load i8, ptr %bytes.i.i, align 1
  %right_octet.i77.i = load i8, ptr %slicedata.44, align 1
  %equal.i78.i = icmp eq i8 %left_octet.i76.i, %right_octet.i77.i
  %left_at.i69.i = getelementptr inbounds nuw i8, ptr %bytes.i.i, i64 %middle.i.i
  %left_octet.i71.i = load i8, ptr %left_at.i69.i, align 1
  %right_octet.i72.i = load i8, ptr %right_at.i70.i, align 1
  %equal.i73.i = icmp eq i8 %left_octet.i71.i, %right_octet.i72.i
  %left_at.i64.i = getelementptr inbounds nuw i8, ptr %bytes.i.i, i64 %last.i.i
  %left_octet.i66.i = load i8, ptr %left_at.i64.i, align 1
  %right_octet.i67.i = load i8, ptr %right_at.i65.i, align 1
  %equal.i68.i = icmp eq i8 %left_octet.i66.i, %right_octet.i67.i
  %two.i.i = and i1 %equal.i78.i, %equal.i73.i
  %three.i.i = and i1 %two.i.i, %equal.i68.i
  br i1 %three.i.i, label %myl.dict.0.find_span.exit, label %scan_next.i

myl.dict.0.span_same.exit.i:                      ; preds = %octets.i.i
  %bcmp.i.i = call i32 @bcmp(ptr nonnull %bytes.i.i, ptr nonnull %slicedata.44, i64 %slicewidth.42)
  %long_equal.i.i = icmp eq i32 %bcmp.i.i, 0
  br i1 %long_equal.i.i, label %myl.dict.0.find_span.exit, label %scan_next.i

scan_next.i:                                      ; preds = %scan_key.i, %word8.i.i, %word4.i.i, %octet.i.i, %myl.dict.0.span_same.exit.i, %scan_dead.i, %scan_hash.i
  %scan_following.i = add nuw i64 %number.i25, 1
  %exitcond.not = icmp eq i64 %scan_following.i, %elen.i
  br i1 %exitcond.not, label %b9, label %scan_hash.i

slow.i:                                           ; preds = %empty.i
  %result.i = call i64 @myl_core_dict_find_span(ptr nonnull %v1928, ptr nonnull %slicedata.44, i64 %slicewidth.42)
  br label %myl.dict.0.find_span.exit

myl.dict.0.find_span.exit:                        ; preds = %below4.i.i, %word8.i.i, %word4.i.i, %octet.i.i, %myl.dict.0.span_same.exit.i, %slow.i
  %common.ret.op.i = phi i64 [ %result.i, %slow.i ], [ %number.i25, %myl.dict.0.span_same.exit.i ], [ %number.i25, %octet.i.i ], [ %number.i25, %word4.i.i ], [ %number.i25, %word8.i.i ], [ %number.i25, %below4.i.i ]
  %v23 = icmp sgt i64 %common.ret.op.i, -1
  br i1 %v23, label %myl.dict.0.find_span.exit.b5_crit_edge, label %b9

myl.dict.0.find_span.exit.b5_crit_edge:           ; preds = %myl.dict.0.find_span.exit
  %.pre = shl i64 %common.ret.op.i, 4
  br label %b7.thread

b4:                                               ; preds = %b10, %b1.preheader
  %v19.lcssa = phi ptr [ %v3, %b1.preheader ], [ %v41, %b10 ]
  ret ptr %v19.lcssa

b7.thread:                                        ; preds = %myl.dict.0.span_same.exit31.i, %octet.i17.i, %word4.i25.i, %word8.i28.i, %below4.i15.i, %myl.dict.0.find_span.exit.b5_crit_edge
  %dictoffset.48.pre-phi = phi i64 [ %.pre, %myl.dict.0.find_span.exit.b5_crit_edge ], [ %offset.i, %below4.i15.i ], [ %offset.i, %word8.i28.i ], [ %offset.i, %word4.i25.i ], [ %offset.i, %octet.i17.i ], [ %offset.i, %myl.dict.0.span_same.exit31.i ]
  %common.ret.op.i10 = phi i64 [ %common.ret.op.i, %myl.dict.0.find_span.exit.b5_crit_edge ], [ %entry_number.i, %below4.i15.i ], [ %entry_number.i, %word8.i28.i ], [ %entry_number.i, %word4.i25.i ], [ %entry_number.i, %octet.i17.i ], [ %entry_number.i, %myl.dict.0.span_same.exit31.i ]
  %14 = getelementptr i8, ptr %v1928, i64 %dictoffset.48.pre-phi
  %dictentry.50 = getelementptr i8, ptr %14, i64 40
  %v25 = load i64, ptr %dictentry.50, align 8
  %p.5141 = call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %v25, i64 1)
  %o.5243 = extractvalue { i64, i1 } %p.5141, 1
  br i1 %o.5243, label %trap.53, label %b8, !prof !9

trap.53:                                          ; preds = %b7.thread
  call void @myl_core_trap(ptr nonnull @myl.site.10, i64 %v25, i64 1) #11
  unreachable

b8:                                               ; preds = %b7.thread
  %v3042 = extractvalue { i64, i1 } %p.5141, 0
  %dictstore.55 = shl i64 %common.ret.op.i10, 4
  %15 = getelementptr i8, ptr %v1928, i64 %dictstore.55
  %dictstore.57 = getelementptr i8, ptr %15, i64 40
  store i64 %v3042, ptr %dictstore.57, align 8
  br label %b10

b9:                                               ; preds = %scan_next.i, %myl.dict.0.find_span.exit, %missing.i, %small_table.i
  %common.ret.op.i945 = phi i64 [ -1, %small_table.i ], [ %common.ret.op.i, %myl.dict.0.find_span.exit ], [ %probe.i, %missing.i ], [ -1, %scan_next.i ]
  %viewkind.61 = load i32, ptr %slicekind.12, align 4
  %viewascii.62 = and i32 %viewkind.61, 256
  %viewascii.63 = icmp ne i32 %viewascii.62, 0
  %v55 = call ptr @myl_core_ir_str_from_span(ptr nonnull %slicedata.44, i64 %slicewidth.42, i1 zeroext %viewascii.63)
  store ptr %v55, ptr %stack.64, align 8
  store i64 1, ptr %stack.65, align 8
  %v39 = call ptr @myl_core_dict_insert(ptr %v1928, i64 %common.ret.op.i945, ptr nonnull %stack.64, ptr nonnull %stack.65, i1 false)
  br label %b10

b10:                                              ; preds = %b9, %b8
  %v41 = phi ptr [ %v1928, %b8 ], [ %v39, %b9 ]
  %v46 = add nuw nsw i64 %v1127, 1
  %exitcond37.not = icmp eq i64 %v46, %v9
  br i1 %exitcond37.not, label %b4, label %b2
}
