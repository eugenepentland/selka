; ModuleID = '.tmp/llvm-audit-20260919/sexpr_tokenizer_read_atom.ll'
source_filename = ".tmp/llvm-audit-20260919/sexpr_tokenizer_read_atom.ll"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux7.0.0-gnu2.43.0"

@myl_f_c7216ff81b82e9d60b2aefddc873a7cdb611d664b3deb9b17e22a05b9481cf8a_meta = external global i8, align 8
@myl_t_277089d91c0bdf4f2e6862ba7e4a07605119431f5d13f726dd352b06f1b206a9 = external global i8, align 8
@myl_t_950310f43c60c012ddd3d6e80b1dfa502a74b362475322e299c8523500d00f5b = external global i8, align 8

define dllexport [40 x i8] @myl_f_c7216ff81b82e9d60b2aefddc873a7cdb611d664b3deb9b17e22a05b9481cf8a(i64 %p_ctx, i64 %p_a0, i64 %p_a1, i64 %p_a2, i64 %p_a3) local_unnamed_addr {
bb_entry:
  %mem228261 = alloca [40 x i8], align 8
  %ptr229 = ptrtoint ptr %mem228261 to i64
  call void @memset(i64 %ptr229, i64 0, i64 40)
  %mem255274 = alloca [32 x i8], align 8
  %ptr256 = ptrtoint ptr %mem255274 to i64
  %mem257275 = alloca [32 x i8], align 8
  %ptr258 = ptrtoint ptr %mem257275 to i64
  %mem259276 = alloca [32 x i8], align 8
  %ptr260 = ptrtoint ptr %mem259276 to i64
  %mem261277 = alloca [32 x i8], align 8
  %ptr262 = ptrtoint ptr %mem261277 to i64
  %mem263278 = alloca [32 x i8], align 8
  %ptr264 = ptrtoint ptr %mem263278 to i64
  %op266 = add i64 %p_ctx, 64
  %p268 = inttoptr i64 %op266 to ptr
  %ld269 = load i64, ptr %p268, align 8
  %cmp272 = icmp ugt i64 %ld269, %ptr264
  br i1 %cmp272, label %bb_floorfail3, label %bb_stackadmit1

bb_floorfail3:                                    ; preds = %bb_entry
  call void @myl_qbe_fail_frame(i64 %p_ctx)
  br label %common.ret

bb_stackadmit1:                                   ; preds = %bb_entry
  %op227 = add i64 %p_ctx, 32
  %op278 = add i64 %p_ctx, 48
  %p280 = inttoptr i64 %op278 to ptr
  %ld281 = load i64, ptr %p280, align 8
  store i64 %ld281, ptr %mem263278, align 8
  %op286 = add i64 %ptr264, 8
  %p288 = inttoptr i64 %op286 to ptr
  store i64 ptrtoint (ptr @myl_f_c7216ff81b82e9d60b2aefddc873a7cdb611d664b3deb9b17e22a05b9481cf8a_meta to i64), ptr %p288, align 8
  %op290 = add i64 %ptr264, 16
  %p292 = inttoptr i64 %op290 to ptr
  store i64 0, ptr %p292, align 8
  store i64 %ptr264, ptr %p280, align 8
  %mem300280 = alloca [24 x i8], align 8
  %ptr301 = ptrtoint ptr %mem300280 to i64
  %mem302281 = alloca [40 x i8], align 8
  %ptr303 = ptrtoint ptr %mem302281 to i64
  %call321 = call i64 @myl_qbe_heap(i64 %p_ctx)
  %call323 = call i64 @myl_qbe_root_mark(i64 %p_ctx)
  %op334 = add i64 %p_a0, 8
  %p336 = inttoptr i64 %op334 to ptr
  %ld337 = load i64, ptr %p336, align 8
  %p388 = inttoptr i64 %p_a0 to ptr
  %p517 = inttoptr i64 %op227 to ptr
  %op819 = add i64 %p_a0, 24
  %p821 = inttoptr i64 %op819 to ptr
  %op718 = add i64 %p_a0, 16
  %p720 = inttoptr i64 %op718 to ptr
  %ld389.peel = load i64, ptr %p388, align 8
  %p397.peel = inttoptr i64 %ld389.peel to ptr
  %ld398.peel = load i64, ptr %p397.peel, align 8
  %cmp410.not.peel = icmp slt i64 %ld337, %ld398.peel
  br i1 %cmp410.not.peel, label %bb_i14.peel, label %bb_i21.peel

bb_i14.peel:                                      ; preds = %bb_stackadmit1
  %isneg.peel = icmp slt i64 %ld337, 0
  %op469.peel = select i1 %isneg.peel, i64 %ld398.peel, i64 0
  %op472.peel = add i64 %op469.peel, %ld337
  %cmp475.peel = icmp ult i64 %op472.peel, %ld398.peel
  br i1 %cmp475.peel, label %bb_success55.peel, label %bb_failed55

bb_success55.peel:                                ; preds = %bb_i14.peel
  %op485.peel = add i64 %ld389.peel, 32
  %p487.peel = inttoptr i64 %op485.peel to ptr
  %ld488.peel = load i64, ptr %p487.peel, align 8
  %op491.peel = add i64 %ld488.peel, %op472.peel
  %p493.peel = inttoptr i64 %op491.peel to ptr
  %ld494.peel = load i8, ptr %p493.peel, align 1
  %ext495.peel = zext i8 %ld494.peel to i64
  br label %bb_i21.peel

bb_i21.peel:                                      ; preds = %bb_success55.peel, %bb_stackadmit1
  %storemerge.peel = phi i64 [ %ext495.peel, %bb_success55.peel ], [ -1, %bb_stackadmit1 ]
  store i64 21, ptr %p292, align 8
  %call512.peel = call i64 @myl_f_cab2aecf2832c326d563b4e0eee7a0a2ec888bb39389f434d607141b8cd2b25f(i64 %p_ctx, i64 %storemerge.peel)
  %ld518.peel = load i64, ptr %p517, align 8
  %cond520.not.peel = icmp eq i64 %ld518.peel, 0
  br i1 %cond520.not.peel, label %bb_ok64.peel, label %bb_failure

bb_ok64.peel:                                     ; preds = %bb_i21.peel
  %cond525.not.peel = icmp eq i64 %call512.peel, 0
  br i1 %cond525.not.peel, label %bb_i79, label %bb_next66.peel

bb_next66.peel:                                   ; preds = %bb_ok64.peel
  %ld551.peel = load i64, ptr %p336, align 8
  %ld568.peel = load i64, ptr %p388, align 8
  %p576.peel = inttoptr i64 %ld568.peel to ptr
  %ld577.peel = load i64, ptr %p576.peel, align 8
  %cmp589.peel = icmp slt i64 %ld551.peel, %ld577.peel
  br i1 %cmp589.peel, label %bb_next82.peel, label %bb_i3.preheader

bb_next82.peel:                                   ; preds = %bb_next66.peel
  %isneg361.peel = icmp slt i64 %ld551.peel, 0
  %op646.peel = select i1 %isneg361.peel, i64 %ld577.peel, i64 0
  %op649.peel = add i64 %op646.peel, %ld551.peel
  %cmp652.peel = icmp ult i64 %op649.peel, %ld577.peel
  br i1 %cmp652.peel, label %bb_success98.peel, label %bb_failed98

bb_success98.peel:                                ; preds = %bb_next82.peel
  %op662.peel = add i64 %ld568.peel, 32
  %p664.peel = inttoptr i64 %op662.peel to ptr
  %ld665.peel = load i64, ptr %p664.peel, align 8
  %op668.peel = add i64 %ld665.peel, %op649.peel
  %p670.peel = inttoptr i64 %op668.peel to ptr
  %ld671.peel = load i8, ptr %p670.peel, align 1
  %cmp692.peel = icmp eq i8 %ld671.peel, 10
  br i1 %cmp692.peel, label %bb_next109.peel, label %bb_i57.peel

bb_i57.peel:                                      ; preds = %bb_success98.peel
  %ld822.peel = load i64, ptr %p821, align 8
  %cmp838.peel = icmp eq i64 %ld822.peel, 9223372036854775807
  br i1 %cmp838.peel, label %bb_overflow136, label %bb_checked136.peel

bb_checked136.peel:                               ; preds = %bb_i57.peel
  %op836.peel = add nsw i64 %ld822.peel, 1
  br label %bb_i66.peel

bb_next109.peel:                                  ; preds = %bb_success98.peel
  %ld721.peel = load i64, ptr %p720, align 8
  %cmp737.peel = icmp eq i64 %ld721.peel, 9223372036854775807
  br i1 %cmp737.peel, label %bb_overflow116, label %bb_checked116.peel

bb_checked116.peel:                               ; preds = %bb_next109.peel
  %op735.peel = add nsw i64 %ld721.peel, 1
  store i64 %op735.peel, ptr %p720, align 8
  br label %bb_i66.peel

bb_i66.peel:                                      ; preds = %bb_checked116.peel, %bb_checked136.peel
  %storemerge640 = phi i64 [ %op836.peel, %bb_checked136.peel ], [ 1, %bb_checked116.peel ]
  store i64 %storemerge640, ptr %p821, align 8
  %ld892.peel = load i64, ptr %p336, align 8
  %cmp908.peel = icmp eq i64 %ld892.peel, 9223372036854775807
  br i1 %cmp908.peel, label %bb_overflow150, label %bb_i3.sink.split

bb_i3.sink.split:                                 ; preds = %bb_i66.peel, %bb_i66
  %ld892.sink = phi i64 [ %ld892, %bb_i66 ], [ %ld892.peel, %bb_i66.peel ]
  %op906 = add nsw i64 %ld892.sink, 1
  store i64 %op906, ptr %p336, align 8
  br label %bb_i3.preheader

bb_i3.preheader:                                  ; preds = %bb_next66.peel, %bb_i3.sink.split
  %ld372.ph = phi i64 [ %op906, %bb_i3.sink.split ], [ %ld551.peel, %bb_next66.peel ]
  br label %bb_i3

bb_i3:                                            ; preds = %bb_i3.preheader, %bb_next66
  %ld372 = phi i64 [ %ld551, %bb_next66 ], [ %ld372.ph, %bb_i3.preheader ]
  %ld389 = load i64, ptr %p388, align 8
  %p397 = inttoptr i64 %ld389 to ptr
  %ld398 = load i64, ptr %p397, align 8
  %cmp410.not = icmp slt i64 %ld372, %ld398
  br i1 %cmp410.not, label %bb_i14, label %bb_i21

bb_i14:                                           ; preds = %bb_i3
  %isneg = icmp slt i64 %ld372, 0
  %op469 = select i1 %isneg, i64 %ld398, i64 0
  %op472 = add i64 %op469, %ld372
  %cmp475 = icmp ult i64 %op472, %ld398
  br i1 %cmp475, label %bb_success55, label %bb_failed55

bb_failed55:                                      ; preds = %bb_i14, %bb_i14.peel
  %ld372.lcssa = phi i64 [ %ld337, %bb_i14.peel ], [ %ld372, %bb_i14 ]
  %ld398.lcssa = phi i64 [ %ld398.peel, %bb_i14.peel ], [ %ld398, %bb_i14 ]
  store i64 18, ptr %p292, align 8
  call void @myl_qbe_fail_index_bounds(i64 %p_ctx, i64 %ld372.lcssa, i64 %ld398.lcssa)
  br label %bb_failure

bb_success55:                                     ; preds = %bb_i14
  %op485 = add i64 %ld389, 32
  %p487 = inttoptr i64 %op485 to ptr
  %ld488 = load i64, ptr %p487, align 8
  %op491 = add i64 %ld488, %op472
  %p493 = inttoptr i64 %op491 to ptr
  %ld494 = load i8, ptr %p493, align 1
  %ext495 = zext i8 %ld494 to i64
  br label %bb_i21

bb_i21:                                           ; preds = %bb_i3, %bb_success55
  %storemerge = phi i64 [ %ext495, %bb_success55 ], [ -1, %bb_i3 ]
  store i64 21, ptr %p292, align 8
  %call512 = call i64 @myl_f_cab2aecf2832c326d563b4e0eee7a0a2ec888bb39389f434d607141b8cd2b25f(i64 %p_ctx, i64 %storemerge)
  %ld518 = load i64, ptr %p517, align 8
  %cond520.not = icmp eq i64 %ld518, 0
  br i1 %cond520.not, label %bb_ok64, label %bb_failure

bb_ok64:                                          ; preds = %bb_i21
  %cond525.not = icmp eq i64 %call512, 0
  br i1 %cond525.not, label %bb_i79, label %bb_next66

bb_next66:                                        ; preds = %bb_ok64
  %ld551 = load i64, ptr %p336, align 8
  %ld568 = load i64, ptr %p388, align 8
  %p576 = inttoptr i64 %ld568 to ptr
  %ld577 = load i64, ptr %p576, align 8
  %cmp589 = icmp slt i64 %ld551, %ld577
  br i1 %cmp589, label %bb_next82, label %bb_i3, !llvm.loop !0

bb_next82:                                        ; preds = %bb_next66
  %isneg361 = icmp slt i64 %ld551, 0
  %op646 = select i1 %isneg361, i64 %ld577, i64 0
  %op649 = add i64 %op646, %ld551
  %cmp652 = icmp ult i64 %op649, %ld577
  br i1 %cmp652, label %bb_success98, label %bb_failed98

bb_failed98:                                      ; preds = %bb_next82, %bb_next82.peel
  %ld551.lcssa = phi i64 [ %ld551.peel, %bb_next82.peel ], [ %ld551, %bb_next82 ]
  %ld577.lcssa = phi i64 [ %ld577.peel, %bb_next82.peel ], [ %ld577, %bb_next82 ]
  store i64 36, ptr %p292, align 8
  call void @myl_qbe_fail_index_bounds(i64 %p_ctx, i64 %ld551.lcssa, i64 %ld577.lcssa)
  br label %bb_failure

bb_success98:                                     ; preds = %bb_next82
  %op662 = add i64 %ld568, 32
  %p664 = inttoptr i64 %op662 to ptr
  %ld665 = load i64, ptr %p664, align 8
  %op668 = add i64 %ld665, %op649
  %p670 = inttoptr i64 %op668 to ptr
  %ld671 = load i8, ptr %p670, align 1
  %cmp692 = icmp eq i8 %ld671, 10
  br i1 %cmp692, label %bb_next109, label %bb_i57

bb_next109:                                       ; preds = %bb_success98
  %ld721 = load i64, ptr %p720, align 8
  %cmp737 = icmp eq i64 %ld721, 9223372036854775807
  br i1 %cmp737, label %bb_overflow116, label %bb_checked116

bb_overflow116:                                   ; preds = %bb_next109, %bb_next109.peel
  store i64 45, ptr %p292, align 8
  call void @myl_qbe_fail_overflow_op(i64 %p_ctx, i64 0, i64 9223372036854775807, i64 1, i64 64)
  br label %bb_failure

bb_checked116:                                    ; preds = %bb_next109
  %op735 = add nsw i64 %ld721, 1
  store i64 %op735, ptr %p720, align 8
  br label %bb_i66

bb_i57:                                           ; preds = %bb_success98
  %ld822 = load i64, ptr %p821, align 8
  %cmp838 = icmp eq i64 %ld822, 9223372036854775807
  br i1 %cmp838, label %bb_overflow136, label %bb_checked136

bb_overflow136:                                   ; preds = %bb_i57, %bb_i57.peel
  store i64 61, ptr %p292, align 8
  call void @myl_qbe_fail_overflow_op(i64 %p_ctx, i64 0, i64 9223372036854775807, i64 1, i64 64)
  br label %bb_failure

bb_checked136:                                    ; preds = %bb_i57
  %op836 = add nsw i64 %ld822, 1
  br label %bb_i66

bb_i66:                                           ; preds = %bb_checked136, %bb_checked116
  %storemerge641 = phi i64 [ %op836, %bb_checked136 ], [ 1, %bb_checked116 ]
  store i64 %storemerge641, ptr %p821, align 8
  %ld892 = load i64, ptr %p336, align 8
  %cmp908 = icmp eq i64 %ld892, 9223372036854775807
  br i1 %cmp908, label %bb_overflow150, label %bb_i3.sink.split, !llvm.loop !0

bb_overflow150:                                   ; preds = %bb_i66, %bb_i66.peel
  store i64 70, ptr %p292, align 8
  call void @myl_qbe_fail_overflow_op(i64 %p_ctx, i64 0, i64 9223372036854775807, i64 1, i64 64)
  br label %bb_failure

bb_i79:                                           ; preds = %bb_ok64, %bb_ok64.peel
  %mem243268.sroa.0.0.lcssa625 = phi i64 [ 0, %bb_ok64.peel ], [ %p_a0, %bb_ok64 ]
  %ld964 = load i64, ptr %p388, align 8
  %ld987 = load i64, ptr %p336, align 8
  store i64 85, ptr %p292, align 8
  %op994 = add i64 %call321, 16
  %p996 = inttoptr i64 %op994 to ptr
  %ld997 = load i64, ptr %p996, align 8
  store i64 %ld997, ptr %mem255274, align 8
  %op1002 = add i64 %ptr256, 8
  %op1007 = add i64 %ptr256, 24
  %p1010 = inttoptr i64 %op1007 to ptr
  store i64 %p_a0, ptr %p1010, align 8
  %p1013 = inttoptr i64 %op1002 to ptr
  store i64 %op1007, ptr %p1013, align 8
  %op1015 = add i64 %ptr256, 16
  %p1017 = inttoptr i64 %op1015 to ptr
  store i64 ptrtoint (ptr @myl_t_950310f43c60c012ddd3d6e80b1dfa502a74b362475322e299c8523500d00f5b to i64), ptr %p1017, align 8
  store i64 %ptr256, ptr %mem257275, align 8
  %op1025 = add i64 %ptr258, 8
  %op1030 = add i64 %ptr258, 24
  %p1033 = inttoptr i64 %op1030 to ptr
  store i64 %p_a0, ptr %p1033, align 8
  %p1036 = inttoptr i64 %op1025 to ptr
  store i64 %op1030, ptr %p1036, align 8
  %op1038 = add i64 %ptr258, 16
  %p1040 = inttoptr i64 %op1038 to ptr
  store i64 ptrtoint (ptr @myl_t_950310f43c60c012ddd3d6e80b1dfa502a74b362475322e299c8523500d00f5b to i64), ptr %p1040, align 8
  store i64 %ptr258, ptr %mem259276, align 8
  %op1048 = add i64 %ptr260, 8
  %op1053 = add i64 %ptr260, 24
  %p1056 = inttoptr i64 %op1053 to ptr
  store i64 %mem243268.sroa.0.0.lcssa625, ptr %p1056, align 8
  %p1059 = inttoptr i64 %op1048 to ptr
  store i64 %op1053, ptr %p1059, align 8
  %op1061 = add i64 %ptr260, 16
  %p1063 = inttoptr i64 %op1061 to ptr
  store i64 ptrtoint (ptr @myl_t_950310f43c60c012ddd3d6e80b1dfa502a74b362475322e299c8523500d00f5b to i64), ptr %p1063, align 8
  store i64 %ptr260, ptr %mem261277, align 8
  %op1071 = add i64 %ptr262, 8
  %op1076 = add i64 %ptr262, 24
  %p1079 = inttoptr i64 %op1076 to ptr
  store i64 %ld964, ptr %p1079, align 8
  %p1082 = inttoptr i64 %op1071 to ptr
  store i64 %op1076, ptr %p1082, align 8
  %op1084 = add i64 %ptr262, 16
  %p1086 = inttoptr i64 %op1084 to ptr
  store i64 ptrtoint (ptr @myl_t_277089d91c0bdf4f2e6862ba7e4a07605119431f5d13f726dd352b06f1b206a9 to i64), ptr %p1086, align 8
  store i64 %ptr262, ptr %p996, align 8
  %call1103 = call i64 @myl_f_b69312568f5c6b484908a80aeaccdaa926bd0455ed6a922c9877a2da6e715f99(i64 %p_ctx, i64 %ld964, i64 %ld337, i64 %ld987)
  store i64 %call323, ptr %p996, align 8
  %ld1114 = load i64, ptr %p517, align 8
  %cond1116.not = icmp eq i64 %ld1114, 0
  br i1 %cond1116.not, label %bb_ok190, label %bb_failure

common.ret:                                       ; preds = %bb_floorfail3, %bb_failure, %bb_ok190
  %mem228261.sink701 = phi ptr [ %mem228261, %bb_floorfail3 ], [ %mem228261, %bb_failure ], [ %mem302281, %bb_ok190 ]
  %ret1221.elt443 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 1
  %ret1221.unpack444 = load i8, ptr %ret1221.elt443, align 1
  %ret1221.elt445 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 2
  %ret1221.unpack446 = load i8, ptr %ret1221.elt445, align 2
  %ret1221.elt447 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 3
  %ret1221.unpack448 = load i8, ptr %ret1221.elt447, align 1
  %ret1221.elt449 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 4
  %ret1221.unpack450 = load i8, ptr %ret1221.elt449, align 4
  %ret1221.elt451 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 5
  %ret1221.unpack452 = load i8, ptr %ret1221.elt451, align 1
  %ret1221.elt453 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 6
  %ret1221.unpack454 = load i8, ptr %ret1221.elt453, align 2
  %ret1221.elt455 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 7
  %ret1221.unpack456 = load i8, ptr %ret1221.elt455, align 1
  %ret1221.elt457 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 8
  %ret1221.unpack458 = load i8, ptr %ret1221.elt457, align 8
  %ret1221.elt459 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 9
  %ret1221.unpack460 = load i8, ptr %ret1221.elt459, align 1
  %ret1221.elt461 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 10
  %ret1221.unpack462 = load i8, ptr %ret1221.elt461, align 2
  %ret1221.elt463 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 11
  %ret1221.unpack464 = load i8, ptr %ret1221.elt463, align 1
  %ret1221.elt465 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 12
  %ret1221.unpack466 = load i8, ptr %ret1221.elt465, align 4
  %ret1221.elt467 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 13
  %ret1221.unpack468 = load i8, ptr %ret1221.elt467, align 1
  %ret1221.elt469 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 14
  %ret1221.unpack470 = load i8, ptr %ret1221.elt469, align 2
  %ret1221.elt471 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 15
  %ret1221.unpack472 = load i8, ptr %ret1221.elt471, align 1
  %ret1221.elt473 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 16
  %ret1221.unpack474 = load i8, ptr %ret1221.elt473, align 8
  %ret1221.elt475 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 17
  %ret1221.unpack476 = load i8, ptr %ret1221.elt475, align 1
  %ret1221.elt477 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 18
  %ret1221.unpack478 = load i8, ptr %ret1221.elt477, align 2
  %ret1221.elt479 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 19
  %ret1221.unpack480 = load i8, ptr %ret1221.elt479, align 1
  %ret1221.elt481 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 20
  %ret1221.unpack482 = load i8, ptr %ret1221.elt481, align 4
  %ret1221.elt483 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 21
  %ret1221.unpack484 = load i8, ptr %ret1221.elt483, align 1
  %ret1221.elt485 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 22
  %ret1221.unpack486 = load i8, ptr %ret1221.elt485, align 2
  %ret1221.elt487 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 23
  %ret1221.unpack488 = load i8, ptr %ret1221.elt487, align 1
  %ret1221.elt489 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 24
  %ret1221.unpack490 = load i8, ptr %ret1221.elt489, align 8
  %ret1221.elt491 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 25
  %ret1221.unpack492 = load i8, ptr %ret1221.elt491, align 1
  %ret1221.elt493 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 26
  %ret1221.unpack494 = load i8, ptr %ret1221.elt493, align 2
  %ret1221.elt495 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 27
  %ret1221.unpack496 = load i8, ptr %ret1221.elt495, align 1
  %ret1221.elt497 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 28
  %ret1221.unpack498 = load i8, ptr %ret1221.elt497, align 4
  %ret1221.elt499 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 29
  %ret1221.unpack500 = load i8, ptr %ret1221.elt499, align 1
  %ret1221.elt501 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 30
  %ret1221.unpack502 = load i8, ptr %ret1221.elt501, align 2
  %ret1221.elt503 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 31
  %ret1221.unpack504 = load i8, ptr %ret1221.elt503, align 1
  %ret1221.elt505 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 32
  %ret1221.unpack506 = load i8, ptr %ret1221.elt505, align 8
  %ret1221.elt507 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 33
  %ret1221.unpack508 = load i8, ptr %ret1221.elt507, align 1
  %ret1221.elt509 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 34
  %ret1221.unpack510 = load i8, ptr %ret1221.elt509, align 2
  %ret1221.elt511 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 35
  %ret1221.unpack512 = load i8, ptr %ret1221.elt511, align 1
  %ret1221.elt513 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 36
  %ret1221.unpack514 = load i8, ptr %ret1221.elt513, align 4
  %ret1221.elt515 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 37
  %ret1221.unpack516 = load i8, ptr %ret1221.elt515, align 1
  %ret1221.elt517 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 38
  %ret1221.unpack518 = load i8, ptr %ret1221.elt517, align 2
  %ret1221.elt519 = getelementptr inbounds nuw i8, ptr %mem228261.sink701, i64 39
  %ret1221.unpack520 = load i8, ptr %ret1221.elt519, align 1
  %ret1204.unpack.pn = load i8, ptr %mem228261.sink701, align 8
  %.pn559 = insertvalue [40 x i8] poison, i8 %ret1204.unpack.pn, 0
  %.pn558 = insertvalue [40 x i8] %.pn559, i8 %ret1221.unpack444, 1
  %.pn557 = insertvalue [40 x i8] %.pn558, i8 %ret1221.unpack446, 2
  %.pn556 = insertvalue [40 x i8] %.pn557, i8 %ret1221.unpack448, 3
  %.pn555 = insertvalue [40 x i8] %.pn556, i8 %ret1221.unpack450, 4
  %.pn554 = insertvalue [40 x i8] %.pn555, i8 %ret1221.unpack452, 5
  %.pn553 = insertvalue [40 x i8] %.pn554, i8 %ret1221.unpack454, 6
  %.pn552 = insertvalue [40 x i8] %.pn553, i8 %ret1221.unpack456, 7
  %.pn551 = insertvalue [40 x i8] %.pn552, i8 %ret1221.unpack458, 8
  %.pn550 = insertvalue [40 x i8] %.pn551, i8 %ret1221.unpack460, 9
  %.pn549 = insertvalue [40 x i8] %.pn550, i8 %ret1221.unpack462, 10
  %.pn548 = insertvalue [40 x i8] %.pn549, i8 %ret1221.unpack464, 11
  %.pn547 = insertvalue [40 x i8] %.pn548, i8 %ret1221.unpack466, 12
  %.pn546 = insertvalue [40 x i8] %.pn547, i8 %ret1221.unpack468, 13
  %.pn545 = insertvalue [40 x i8] %.pn546, i8 %ret1221.unpack470, 14
  %.pn544 = insertvalue [40 x i8] %.pn545, i8 %ret1221.unpack472, 15
  %.pn543 = insertvalue [40 x i8] %.pn544, i8 %ret1221.unpack474, 16
  %.pn542 = insertvalue [40 x i8] %.pn543, i8 %ret1221.unpack476, 17
  %.pn541 = insertvalue [40 x i8] %.pn542, i8 %ret1221.unpack478, 18
  %.pn540 = insertvalue [40 x i8] %.pn541, i8 %ret1221.unpack480, 19
  %.pn539 = insertvalue [40 x i8] %.pn540, i8 %ret1221.unpack482, 20
  %.pn538 = insertvalue [40 x i8] %.pn539, i8 %ret1221.unpack484, 21
  %.pn537 = insertvalue [40 x i8] %.pn538, i8 %ret1221.unpack486, 22
  %.pn536 = insertvalue [40 x i8] %.pn537, i8 %ret1221.unpack488, 23
  %.pn535 = insertvalue [40 x i8] %.pn536, i8 %ret1221.unpack490, 24
  %.pn534 = insertvalue [40 x i8] %.pn535, i8 %ret1221.unpack492, 25
  %.pn533 = insertvalue [40 x i8] %.pn534, i8 %ret1221.unpack494, 26
  %.pn532 = insertvalue [40 x i8] %.pn533, i8 %ret1221.unpack496, 27
  %.pn531 = insertvalue [40 x i8] %.pn532, i8 %ret1221.unpack498, 28
  %.pn530 = insertvalue [40 x i8] %.pn531, i8 %ret1221.unpack500, 29
  %.pn529 = insertvalue [40 x i8] %.pn530, i8 %ret1221.unpack502, 30
  %.pn528 = insertvalue [40 x i8] %.pn529, i8 %ret1221.unpack504, 31
  %.pn527 = insertvalue [40 x i8] %.pn528, i8 %ret1221.unpack506, 32
  %.pn526 = insertvalue [40 x i8] %.pn527, i8 %ret1221.unpack508, 33
  %.pn525 = insertvalue [40 x i8] %.pn526, i8 %ret1221.unpack510, 34
  %.pn524 = insertvalue [40 x i8] %.pn525, i8 %ret1221.unpack512, 35
  %.pn523 = insertvalue [40 x i8] %.pn524, i8 %ret1221.unpack514, 36
  %.pn522 = insertvalue [40 x i8] %.pn523, i8 %ret1221.unpack516, 37
  %.pn = insertvalue [40 x i8] %.pn522, i8 %ret1221.unpack518, 38
  %common.ret.op = insertvalue [40 x i8] %.pn, i8 %ret1221.unpack520, 39
  ret [40 x i8] %common.ret.op

bb_ok190:                                         ; preds = %bb_i79
  store i64 %p_a1, ptr %mem300280, align 8
  %op1145 = add i64 %ptr301, 8
  %p1151 = inttoptr i64 %op1145 to ptr
  store i64 %p_a2, ptr %p1151, align 8
  %op1153 = add i64 %ptr301, 16
  %p1159 = inttoptr i64 %op1153 to ptr
  store i64 %p_a3, ptr %p1159, align 8
  store i32 2, ptr %mem302281, align 8
  %op1174 = add i64 %ptr303, 8
  %p1180 = inttoptr i64 %op1174 to ptr
  store i64 %call1103, ptr %p1180, align 8
  %op1182 = add i64 %ptr303, 16
  %p1189 = inttoptr i64 %op1182 to ptr
  call void @llvm.memmove.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %p1189, ptr noundef nonnull align 8 dereferenceable(24) %mem300280, i64 24, i1 false)
  %ld1198 = load i64, ptr %mem263278, align 8
  store i64 %ld1198, ptr %p280, align 8
  br label %common.ret

bb_failure:                                       ; preds = %bb_i21, %bb_i21.peel, %bb_i79, %bb_overflow150, %bb_overflow136, %bb_overflow116, %bb_failed98, %bb_failed55
  %op1206 = add i64 %call321, 16
  %p1209 = inttoptr i64 %op1206 to ptr
  store i64 %call323, ptr %p1209, align 8
  %ld1212 = load i64, ptr %mem263278, align 8
  store i64 %ld1212, ptr %p280, align 8
  br label %common.ret
}

; Function Attrs: mustprogress nocallback nofree nounwind willreturn memory(argmem: readwrite)
declare void @llvm.memmove.p0.p0.i64(ptr writeonly captures(none), ptr readonly captures(none), i64, i1 immarg) #0

declare void @memset(i64, i64, i64) local_unnamed_addr

declare i64 @myl_f_b69312568f5c6b484908a80aeaccdaa926bd0455ed6a922c9877a2da6e715f99(i64, i64, i64, i64) local_unnamed_addr

declare i64 @myl_f_cab2aecf2832c326d563b4e0eee7a0a2ec888bb39389f434d607141b8cd2b25f(i64, i64) local_unnamed_addr

declare void @myl_qbe_fail_frame(i64) local_unnamed_addr

declare void @myl_qbe_fail_index_bounds(i64, i64, i64) local_unnamed_addr

declare void @myl_qbe_fail_overflow_op(i64, i64, i64, i64, i64) local_unnamed_addr

declare i64 @myl_qbe_heap(i64) local_unnamed_addr

declare i64 @myl_qbe_root_mark(i64) local_unnamed_addr

attributes #0 = { mustprogress nocallback nofree nounwind willreturn memory(argmem: readwrite) }

!0 = distinct !{!0, !1}
!1 = !{!"llvm.loop.peeled.count", i32 1}
