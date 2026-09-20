define dso_local [9 x i64] @myl_f_8eb428ca68410fb139af946d6aa6e23c28659cba29e0de3ff744192751629959(i64 %p_ctx, i64 %p_a0, i64 %p_a1) local_unnamed_addr {
bb_entry:
  %mem517498 = alloca [40 x i8], align 8
  %mem523501 = alloca [32 x i8], align 8
  %mem525502 = alloca [40 x i8], align 8
  %mem555517 = alloca [40 x i8], align 8
  %mem557518 = alloca [40 x i8], align 8
  %mem561520 = alloca [40 x i8], align 8
  %mem563521 = alloca [40 x i8], align 8
  %op354 = add i64 %p_ctx, 32
  %mem358525 = alloca [32 x i8], align 8
  %ptr359 = ptrtoint ptr %mem358525 to i64
  %mem366529 = alloca [40 x i8], align 8
  %ptr367 = ptrtoint ptr %mem366529 to i64
  %mem468580 = alloca [32 x i8], align 8
  %ptr469 = ptrtoint ptr %mem468580 to i64
  %mem470581 = alloca [32 x i8], align 8
  %ptr471 = ptrtoint ptr %mem470581 to i64
  %mem472582 = alloca [32 x i8], align 8
  %ptr473 = ptrtoint ptr %mem472582 to i64
  %mem474583 = alloca [32 x i8], align 8
  %ptr475 = ptrtoint ptr %mem474583 to i64
  %mem476584 = alloca [32 x i8], align 8
  %ptr477 = ptrtoint ptr %mem476584 to i64
  %mem478585 = alloca [32 x i8], align 8
  %ptr479 = ptrtoint ptr %mem478585 to i64
  %op481 = add i64 %p_ctx, 64
  %p483 = inttoptr i64 %op481 to ptr
  %ld484 = load i64, ptr %p483, align 8
  %cmp487 = icmp ugt i64 %ld484, %ptr479
  br i1 %cmp487, label %bb_floorfail3, label %bb_stackadmit1

bb_floorfail3:                                    ; preds = %bb_entry
  call void @myl_qbe_fail_frame(i64 %p_ctx)
  br label %common.ret

bb_stackadmit1:                                   ; preds = %bb_entry
  %op493 = add i64 %p_ctx, 48
  %p495 = inttoptr i64 %op493 to ptr
  %ld496 = load i64, ptr %p495, align 8
  store i64 %ld496, ptr %mem478585, align 8
  %op501.audit_gep = getelementptr inbounds nuw i8, ptr %mem478585, i64 8
  store i64 ptrtoint (ptr @myl_f_8eb428ca68410fb139af946d6aa6e23c28659cba29e0de3ff744192751629959_meta to i64), ptr %op501.audit_gep, align 8
  %op505.audit_gep = getelementptr inbounds nuw i8, ptr %mem478585, i64 16
  store i64 0, ptr %op505.audit_gep, align 8
  store i64 %ptr479, ptr %p495, align 8
  %ptr518 = ptrtoint ptr %mem517498 to i64
  %ptr524 = ptrtoint ptr %mem523501 to i64
  %ptr556 = ptrtoint ptr %mem555517 to i64
  %ptr558 = ptrtoint ptr %mem557518 to i64
  %ptr562 = ptrtoint ptr %mem561520 to i64
  %ptr564 = ptrtoint ptr %mem563521 to i64
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(40) %mem366529, i8 0, i64 40, i1 false)
  %p574 = inttoptr i64 %p_a0 to ptr
  call void @llvm.memmove.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(32) %mem358525, ptr noundef nonnull align 1 dereferenceable(32) %p574, i64 32, i1 false)
  %call580 = call i64 @myl_qbe_heap(i64 %p_ctx)
  %call582 = call i64 @myl_qbe_root_mark(i64 %p_ctx)
  %mem513496.sroa.1.0.mem358525.sroa_idx = getelementptr inbounds nuw i8, ptr %mem358525, i64 8
  %mem513496.sroa.1.0.copyload = load i64, ptr %mem513496.sroa.1.0.mem358525.sroa_idx, align 8
  %mem513496.sroa.2.0.mem358525.sroa_idx = getelementptr inbounds nuw i8, ptr %mem358525, i64 16
  %mem515497.sroa.1.0.copyload = load i64, ptr %mem513496.sroa.2.0.mem358525.sroa_idx, align 8
  %cmp647 = icmp slt i64 %mem515497.sroa.1.0.copyload, 0
  %p663 = inttoptr i64 %mem513496.sroa.1.0.copyload to ptr
  br i1 %cmp647, label %bb_next31, label %bb_i15

bb_next31:                                        ; preds = %bb_stackadmit1
  %ld664 = load i64, ptr %p663, align 8
  %cmp672 = icmp slt i64 %ld664, 0
  br i1 %cmp672, label %bb_cast_overflow36, label %bb_cast_ok36

bb_cast_overflow36:                               ; preds = %bb_next31
  store i64 11, ptr %op505.audit_gep, align 8
  call void @myl_qbe_fail_cast(i64 %p_ctx, i64 %ld664, i64 64)
  br label %bb_failure

bb_cast_ok36:                                     ; preds = %bb_next31
  %op697 = add nsw i64 %ld664, %mem515497.sroa.1.0.copyload
  %op700 = xor i64 %op697, %ld664
  %op703 = xor i64 %op697, %mem515497.sroa.1.0.copyload
  %op706 = and i64 %op700, %op703
  %cmp708 = icmp slt i64 %op706, 0
  br i1 %cmp708, label %bb_overflow40, label %bb_i15

bb_overflow40:                                    ; preds = %bb_cast_ok36
  store i64 13, ptr %op505.audit_gep, align 8
  call void @myl_qbe_fail_overflow_op(i64 %p_ctx, i64 0, i64 %ld664, i64 %mem515497.sroa.1.0.copyload, i64 64)
  br label %bb_failure

bb_i15:                                           ; preds = %bb_cast_ok36, %bb_stackadmit1
  %mem364528.sroa.0.0 = phi i64 [ %op697, %bb_cast_ok36 ], [ %mem515497.sroa.1.0.copyload, %bb_stackadmit1 ]
  store i64 16, ptr %op505.audit_gep, align 8
  %ld742 = load i64, ptr %p663, align 8
  %call746 = call i32 @myl_native_list_get(i64 %mem513496.sroa.1.0.copyload, i64 %mem364528.sroa.0.0, i64 %ptr518)
  %cond749.not = icmp eq i32 %call746, 0
  br i1 %cond749.not, label %bb_failed51, label %bb_success51

bb_failed51:                                      ; preds = %bb_i15
  call void @myl_qbe_fail_normalized_index_bounds(i64 %p_ctx, i64 %mem364528.sroa.0.0, i64 %ld742)
  br label %bb_failure

bb_success51:                                     ; preds = %bb_i15
  %p758 = inttoptr i64 %op354 to ptr
  %ld759 = load i64, ptr %p758, align 8
  %cond761.not = icmp eq i64 %ld759, 0
  br i1 %cond761.not, label %bb_ok53, label %bb_failure

bb_ok53:                                          ; preds = %bb_success51
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(40) %mem366529, ptr noundef nonnull align 8 dereferenceable(40) %mem517498, i64 40, i1 false)
  %mem519499.sroa.1.0.copyload = load i64, ptr %mem513496.sroa.2.0.mem358525.sroa_idx, align 8
  %cmp799 = icmp eq i64 %mem519499.sroa.1.0.copyload, 9223372036854775807
  br i1 %cmp799, label %bb_overflow60, label %bb_checked60

bb_overflow60:                                    ; preds = %bb_ok53
  store i64 21, ptr %op505.audit_gep, align 8
  call void @myl_qbe_fail_overflow_op(i64 %p_ctx, i64 0, i64 9223372036854775807, i64 1, i64 64)
  br label %bb_failure

bb_checked60:                                     ; preds = %bb_ok53
  %op797 = add nsw i64 %mem519499.sroa.1.0.copyload, 1
  %mem521500.sroa.0.0.copyload = load i32, ptr %mem366529, align 8
  switch i32 %mem521500.sroa.0.0.copyload, label %bb_failure [
    i32 0, label %bb_i26
    i32 1, label %bb_i33
    i32 2, label %bb_i84
    i32 3, label %bb_i94
    i32 4, label %bb_i104
    i32 5, label %bb_i108
    i32 6, label %bb_i112
    i32 7, label %bb_i118
    i32 8, label %bb_i122
  ]

bb_i26:                                           ; preds = %bb_checked60
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(32) %mem523501, ptr noundef nonnull align 8 dereferenceable(32) %mem358525, i64 32, i1 false)
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(40) %mem525502, ptr noundef nonnull align 8 dereferenceable(40) %mem517498, i64 40, i1 false)
  %op914.audit_gep = getelementptr inbounds nuw i8, ptr %mem525502, i64 16
  %op914 = ptrtoint ptr %op914.audit_gep to i64
  store i64 31, ptr %op505.audit_gep, align 8
  %op921 = add i64 %call580, 16
  %p923 = inttoptr i64 %op921 to ptr
  %ld924 = load i64, ptr %p923, align 8
  store i64 %ld924, ptr %mem468580, align 8
  %op929.audit_gep = getelementptr inbounds nuw i8, ptr %mem468580, i64 8
  store i64 %ptr359, ptr %op929.audit_gep, align 8
  %op934.audit_gep = getelementptr inbounds nuw i8, ptr %mem468580, i64 16
  store i64 ptrtoint (ptr @myl_t_306680ea529d6c1737c08d47b1547aaebd58d1a20c498e02eef2d4c0bf300a01 to i64), ptr %op934.audit_gep, align 8
  store i64 %ptr469, ptr %mem470581, align 8
  %op944.audit_gep = getelementptr inbounds nuw i8, ptr %mem470581, i64 8
  %op949.audit_gep = getelementptr inbounds nuw i8, ptr %mem470581, i64 24
  %op949 = ptrtoint ptr %op949.audit_gep to i64
  store i64 %mem513496.sroa.1.0.copyload, ptr %op949.audit_gep, align 8
  store i64 %op949, ptr %op944.audit_gep, align 8
  %op957.audit_gep = getelementptr inbounds nuw i8, ptr %mem470581, i64 16
  store i64 ptrtoint (ptr @myl_t_fb0d5bbdabead1b5cc59d8495e5b4a8111f2106f4f0a8a62c46bac565261293a to i64), ptr %op957.audit_gep, align 8
  store i64 %ptr471, ptr %mem472582, align 8
  %op967.audit_gep = getelementptr inbounds nuw i8, ptr %mem472582, i64 8
  store i64 %ptr367, ptr %op967.audit_gep, align 8
  %op972.audit_gep = getelementptr inbounds nuw i8, ptr %mem472582, i64 16
  store i64 ptrtoint (ptr @myl_t_de305505330c1abad390bf69bceeeab8acb7eff0a00387ae260ef9a7047bf31b to i64), ptr %op972.audit_gep, align 8
  store i64 %ptr473, ptr %mem474583, align 8
  %op985.audit_gep = getelementptr inbounds nuw i8, ptr %mem474583, i64 8
  store i64 %ptr524, ptr %op985.audit_gep, align 8
  %op990.audit_gep = getelementptr inbounds nuw i8, ptr %mem474583, i64 16
  store i64 ptrtoint (ptr @myl_t_306680ea529d6c1737c08d47b1547aaebd58d1a20c498e02eef2d4c0bf300a01 to i64), ptr %op990.audit_gep, align 8
  store i64 %ptr475, ptr %p923, align 8
  %call1013 = call [9 x i64] @myl_f_2e34b70956bd2f98094170b27161f4beca7b4dbc88ffeaecd468514ea7f8884c(i64 %p_ctx, i64 %ptr524, i64 %op797, i64 %p_a1, i64 %op914)
  store i64 %call582, ptr %p923, align 8
  %ld1026 = load i64, ptr %p758, align 8
  %cond1028.not = icmp eq i64 %ld1026, 0
  br i1 %cond1028.not, label %bb_ok99, label %bb_failure

common.ret:                                       ; preds = %bb_failure, %bb_ok278, %bb_ok266, %bb_ok243, %bb_ok212, %bb_ok189, %bb_i94, %bb_i84, %bb_ok111, %bb_ok99, %bb_floorfail3
  %ret1040.unpack.pn.in.sroa.speculated = phi i64 [ %call1013.elt, %bb_ok99 ], [ 1, %bb_ok111 ], [ 0, %bb_i84 ], [ 0, %bb_i94 ], [ %call1546.elt, %bb_ok189 ], [ %call1674.elt, %bb_ok212 ], [ %call1847.elt, %bb_ok243 ], [ %call1975.elt, %bb_ok266 ], [ 1, %bb_ok278 ], [ 0, %bb_failure ], [ 0, %bb_floorfail3 ]
  %ret1040.unpack815.pn = phi i64 [ %call1013.elt799, %bb_ok99 ], [ %ld1147, %bb_ok111 ], [ 1, %bb_i84 ], [ 2, %bb_i94 ], [ %call1546.elt709, %bb_ok189 ], [ %call1674.elt676, %bb_ok212 ], [ %call1847.elt643, %bb_ok243 ], [ %call1975.elt610, %bb_ok266 ], [ %ld2115, %bb_ok278 ], [ 0, %bb_failure ], [ 0, %bb_floorfail3 ]
  %ret1040.unpack817.pn = phi i64 [ %call1013.elt801, %bb_ok99 ], [ %mem527503.sroa.1.0.copyload, %bb_ok111 ], [ %mem531505.sroa.1.0.copyload, %bb_i84 ], [ %mem543511.sroa.1.0.copyload, %bb_i94 ], [ %call1546.elt711, %bb_ok189 ], [ %call1674.elt678, %bb_ok212 ], [ %call1847.elt645, %bb_ok243 ], [ %call1975.elt612, %bb_ok266 ], [ %mem565522.sroa.1.0.copyload, %bb_ok278 ], [ 0, %bb_failure ], [ 0, %bb_floorfail3 ]
  %ret1040.unpack819.pn = phi i64 [ %call1013.elt803, %bb_ok99 ], [ %mem527503.sroa.2.0.copyload, %bb_ok111 ], [ %mem533506.sroa.1.0.copyload, %bb_i84 ], [ %mem545512.sroa.1.0.copyload, %bb_i94 ], [ %call1546.elt713, %bb_ok189 ], [ %call1674.elt680, %bb_ok212 ], [ %call1847.elt647, %bb_ok243 ], [ %call1975.elt614, %bb_ok266 ], [ %mem565522.sroa.2.0.copyload, %bb_ok278 ], [ 0, %bb_failure ], [ 0, %bb_floorfail3 ]
  %ret1040.unpack821.pn = phi i64 [ %call1013.elt805, %bb_ok99 ], [ %mem527503.sroa.3.0.copyload, %bb_ok111 ], [ %mem533506.sroa.2.0.copyload, %bb_i84 ], [ %mem545512.sroa.2.0.copyload, %bb_i94 ], [ %call1546.elt715, %bb_ok189 ], [ %call1674.elt682, %bb_ok212 ], [ %call1847.elt649, %bb_ok243 ], [ %call1975.elt616, %bb_ok266 ], [ %mem565522.sroa.3.0.copyload, %bb_ok278 ], [ 0, %bb_failure ], [ 0, %bb_floorfail3 ]
  %ret1040.unpack823.pn = phi i64 [ %call1013.elt807, %bb_ok99 ], [ undef, %bb_ok111 ], [ %mem533506.sroa.3.0.copyload, %bb_i84 ], [ %mem545512.sroa.3.0.copyload, %bb_i94 ], [ %call1546.elt717, %bb_ok189 ], [ %call1674.elt684, %bb_ok212 ], [ %call1847.elt651, %bb_ok243 ], [ %call1975.elt618, %bb_ok266 ], [ undef, %bb_ok278 ], [ 0, %bb_failure ], [ 0, %bb_floorfail3 ]
  %ret1040.unpack825.pn = phi i64 [ %call1013.elt809, %bb_ok99 ], [ undef, %bb_ok111 ], [ undef, %bb_i84 ], [ undef, %bb_i94 ], [ %call1546.elt719, %bb_ok189 ], [ %call1674.elt686, %bb_ok212 ], [ %call1847.elt653, %bb_ok243 ], [ %call1975.elt620, %bb_ok266 ], [ undef, %bb_ok278 ], [ 0, %bb_failure ], [ 0, %bb_floorfail3 ]
  %ret1040.unpack827.pn = phi i64 [ %call1013.elt811, %bb_ok99 ], [ undef, %bb_ok111 ], [ undef, %bb_i84 ], [ undef, %bb_i94 ], [ %call1546.elt721, %bb_ok189 ], [ %call1674.elt688, %bb_ok212 ], [ %call1847.elt655, %bb_ok243 ], [ %call1975.elt622, %bb_ok266 ], [ undef, %bb_ok278 ], [ 0, %bb_failure ], [ 0, %bb_floorfail3 ]
  %ret1040.unpack829.pn = phi i64 [ %call1013.elt813, %bb_ok99 ], [ undef, %bb_ok111 ], [ %op797, %bb_i84 ], [ %op797, %bb_i94 ], [ %call1546.elt723, %bb_ok189 ], [ %call1674.elt690, %bb_ok212 ], [ %call1847.elt657, %bb_ok243 ], [ %call1975.elt624, %bb_ok266 ], [ undef, %bb_ok278 ], [ 0, %bb_failure ], [ 0, %bb_floorfail3 ]
  %.pn871 = insertvalue [9 x i64] poison, i64 %ret1040.unpack.pn.in.sroa.speculated, 0
  %.pn870 = insertvalue [9 x i64] %.pn871, i64 %ret1040.unpack815.pn, 1
  %.pn869 = insertvalue [9 x i64] %.pn870, i64 %ret1040.unpack817.pn, 2
  %.pn868 = insertvalue [9 x i64] %.pn869, i64 %ret1040.unpack819.pn, 3
  %.pn867 = insertvalue [9 x i64] %.pn868, i64 %ret1040.unpack821.pn, 4
  %.pn866 = insertvalue [9 x i64] %.pn867, i64 %ret1040.unpack823.pn, 5
  %.pn865 = insertvalue [9 x i64] %.pn866, i64 %ret1040.unpack825.pn, 6
  %.pn = insertvalue [9 x i64] %.pn865, i64 %ret1040.unpack827.pn, 7
  %common.ret.op = insertvalue [9 x i64] %.pn, i64 %ret1040.unpack829.pn, 8
  ret [9 x i64] %common.ret.op

bb_ok99:                                          ; preds = %bb_i26
  %call1013.elt813 = extractvalue [9 x i64] %call1013, 8
  %call1013.elt811 = extractvalue [9 x i64] %call1013, 7
  %call1013.elt809 = extractvalue [9 x i64] %call1013, 6
  %call1013.elt807 = extractvalue [9 x i64] %call1013, 5
  %call1013.elt805 = extractvalue [9 x i64] %call1013, 4
  %call1013.elt803 = extractvalue [9 x i64] %call1013, 3
  %call1013.elt801 = extractvalue [9 x i64] %call1013, 2
  %call1013.elt799 = extractvalue [9 x i64] %call1013, 1
  %call1013.elt = extractvalue [9 x i64] %call1013, 0
  %ld1034 = load i64, ptr %mem478585, align 8
  store i64 %ld1034, ptr %p495, align 8
  br label %common.ret

bb_i33:                                           ; preds = %bb_checked60
  %mem527503.sroa.1.0.mem517498.sroa_idx = getelementptr inbounds nuw i8, ptr %mem517498, i64 16
  %mem527503.sroa.1.0.copyload = load i64, ptr %mem527503.sroa.1.0.mem517498.sroa_idx, align 8
  %mem527503.sroa.2.0.mem517498.sroa_idx = getelementptr inbounds nuw i8, ptr %mem517498, i64 24
  %mem527503.sroa.2.0.copyload = load i64, ptr %mem527503.sroa.2.0.mem517498.sroa_idx, align 8
  %mem527503.sroa.3.0.mem517498.sroa_idx = getelementptr inbounds nuw i8, ptr %mem517498, i64 32
  %mem527503.sroa.3.0.copyload = load i64, ptr %mem527503.sroa.3.0.mem517498.sroa_idx, align 8
  %ld1147 = load i64, ptr @myl_lit_4f174ea5203edaee6e3b1694800e25e52473450d4f4824abf459a6ea9e3cab4f, align 8
  store i64 81, ptr %op505.audit_gep, align 8
  %ld1170 = load i64, ptr %p758, align 8
  %cond1172.not = icmp eq i64 %ld1170, 0
  br i1 %cond1172.not, label %bb_ok111, label %bb_failure

bb_ok111:                                         ; preds = %bb_i33
  %ld1193 = load i64, ptr %mem478585, align 8
  store i64 %ld1193, ptr %p495, align 8
  br label %common.ret

bb_i84:                                           ; preds = %bb_checked60
  %mem531505.sroa.1.0.mem517498.sroa_idx = getelementptr inbounds nuw i8, ptr %mem517498, i64 8
  %mem531505.sroa.1.0.copyload = load i64, ptr %mem531505.sroa.1.0.mem517498.sroa_idx, align 8
  %mem531505.sroa.2.0.mem517498.sroa_idx = getelementptr inbounds nuw i8, ptr %mem517498, i64 16
  %mem533506.sroa.1.0.copyload = load i64, ptr %mem531505.sroa.2.0.mem517498.sroa_idx, align 8
  %mem533506.sroa.2.0.mem517498.sroa_idx = getelementptr inbounds nuw i8, ptr %mem517498, i64 24
  %mem533506.sroa.2.0.copyload = load i64, ptr %mem533506.sroa.2.0.mem517498.sroa_idx, align 8
  %mem533506.sroa.3.0.mem517498.sroa_idx = getelementptr inbounds nuw i8, ptr %mem517498, i64 32
  %mem533506.sroa.3.0.copyload = load i64, ptr %mem533506.sroa.3.0.mem517498.sroa_idx, align 8
  %ld1316 = load i64, ptr %mem478585, align 8
  store i64 %ld1316, ptr %p495, align 8
  br label %common.ret

bb_i94:                                           ; preds = %bb_checked60
  %mem543511.sroa.1.0.mem517498.sroa_idx = getelementptr inbounds nuw i8, ptr %mem517498, i64 8
  %mem543511.sroa.1.0.copyload = load i64, ptr %mem543511.sroa.1.0.mem517498.sroa_idx, align 8
  %mem543511.sroa.2.0.mem517498.sroa_idx = getelementptr inbounds nuw i8, ptr %mem517498, i64 16
  %mem545512.sroa.1.0.copyload = load i64, ptr %mem543511.sroa.2.0.mem517498.sroa_idx, align 8
  %mem545512.sroa.2.0.mem517498.sroa_idx = getelementptr inbounds nuw i8, ptr %mem517498, i64 24
  %mem545512.sroa.2.0.copyload = load i64, ptr %mem545512.sroa.2.0.mem517498.sroa_idx, align 8
  %mem545512.sroa.3.0.mem517498.sroa_idx = getelementptr inbounds nuw i8, ptr %mem517498, i64 32
  %mem545512.sroa.3.0.copyload = load i64, ptr %mem545512.sroa.3.0.mem517498.sroa_idx, align 8
  %ld1439 = load i64, ptr %mem478585, align 8
  store i64 %ld1439, ptr %p495, align 8
  br label %common.ret

bb_i104:                                          ; preds = %bb_checked60
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(40) %mem555517, ptr noundef nonnull align 8 dereferenceable(40) %mem517498, i64 40, i1 false)
  store i64 106, ptr %op505.audit_gep, align 8
  %op1462 = add i64 %call580, 16
  %p1464 = inttoptr i64 %op1462 to ptr
  %ld1465 = load i64, ptr %p1464, align 8
  store i64 %ld1465, ptr %mem468580, align 8
  %op1470.audit_gep = getelementptr inbounds nuw i8, ptr %mem468580, i64 8
  store i64 %ptr359, ptr %op1470.audit_gep, align 8
  %op1475.audit_gep = getelementptr inbounds nuw i8, ptr %mem468580, i64 16
  store i64 ptrtoint (ptr @myl_t_306680ea529d6c1737c08d47b1547aaebd58d1a20c498e02eef2d4c0bf300a01 to i64), ptr %op1475.audit_gep, align 8
  store i64 %ptr469, ptr %mem470581, align 8
  %op1485.audit_gep = getelementptr inbounds nuw i8, ptr %mem470581, i64 8
  %op1490.audit_gep = getelementptr inbounds nuw i8, ptr %mem470581, i64 24
  %op1490 = ptrtoint ptr %op1490.audit_gep to i64
  store i64 %mem513496.sroa.1.0.copyload, ptr %op1490.audit_gep, align 8
  store i64 %op1490, ptr %op1485.audit_gep, align 8
  %op1498.audit_gep = getelementptr inbounds nuw i8, ptr %mem470581, i64 16
  store i64 ptrtoint (ptr @myl_t_fb0d5bbdabead1b5cc59d8495e5b4a8111f2106f4f0a8a62c46bac565261293a to i64), ptr %op1498.audit_gep, align 8
  store i64 %ptr471, ptr %mem472582, align 8
  %op1508.audit_gep = getelementptr inbounds nuw i8, ptr %mem472582, i64 8
  store i64 %ptr367, ptr %op1508.audit_gep, align 8
  %op1513.audit_gep = getelementptr inbounds nuw i8, ptr %mem472582, i64 16
  store i64 ptrtoint (ptr @myl_t_de305505330c1abad390bf69bceeeab8acb7eff0a00387ae260ef9a7047bf31b to i64), ptr %op1513.audit_gep, align 8
  store i64 %ptr473, ptr %mem474583, align 8
  %op1526.audit_gep = getelementptr inbounds nuw i8, ptr %mem474583, i64 8
  store i64 %ptr556, ptr %op1526.audit_gep, align 8
  %op1531.audit_gep = getelementptr inbounds nuw i8, ptr %mem474583, i64 16
  store i64 ptrtoint (ptr @myl_t_de305505330c1abad390bf69bceeeab8acb7eff0a00387ae260ef9a7047bf31b to i64), ptr %op1531.audit_gep, align 8
  store i64 %ptr475, ptr %p1464, align 8
  %call1546 = call [9 x i64] @myl_f_96b067c9e9a223f42df861e5f816c57d88027bc98ce7a2f9698fe752d5c07806(i64 %p_ctx, i64 %ptr556, i64 %op797)
  store i64 %call582, ptr %p1464, align 8
  %ld1559 = load i64, ptr %p758, align 8
  %cond1561.not = icmp eq i64 %ld1559, 0
  br i1 %cond1561.not, label %bb_ok189, label %bb_failure

bb_ok189:                                         ; preds = %bb_i104
  %call1546.elt723 = extractvalue [9 x i64] %call1546, 8
  %call1546.elt721 = extractvalue [9 x i64] %call1546, 7
  %call1546.elt719 = extractvalue [9 x i64] %call1546, 6
  %call1546.elt717 = extractvalue [9 x i64] %call1546, 5
  %call1546.elt715 = extractvalue [9 x i64] %call1546, 4
  %call1546.elt713 = extractvalue [9 x i64] %call1546, 3
  %call1546.elt711 = extractvalue [9 x i64] %call1546, 2
  %call1546.elt709 = extractvalue [9 x i64] %call1546, 1
  %call1546.elt = extractvalue [9 x i64] %call1546, 0
  %ld1567 = load i64, ptr %mem478585, align 8
  store i64 %ld1567, ptr %p495, align 8
  br label %common.ret

bb_i108:                                          ; preds = %bb_checked60
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(40) %mem557518, ptr noundef nonnull align 8 dereferenceable(40) %mem517498, i64 40, i1 false)
  store i64 110, ptr %op505.audit_gep, align 8
  %op1590 = add i64 %call580, 16
  %p1592 = inttoptr i64 %op1590 to ptr
  %ld1593 = load i64, ptr %p1592, align 8
  store i64 %ld1593, ptr %mem468580, align 8
  %op1598.audit_gep = getelementptr inbounds nuw i8, ptr %mem468580, i64 8
  store i64 %ptr359, ptr %op1598.audit_gep, align 8
  %op1603.audit_gep = getelementptr inbounds nuw i8, ptr %mem468580, i64 16
  store i64 ptrtoint (ptr @myl_t_306680ea529d6c1737c08d47b1547aaebd58d1a20c498e02eef2d4c0bf300a01 to i64), ptr %op1603.audit_gep, align 8
  store i64 %ptr469, ptr %mem470581, align 8
  %op1613.audit_gep = getelementptr inbounds nuw i8, ptr %mem470581, i64 8
  %op1618.audit_gep = getelementptr inbounds nuw i8, ptr %mem470581, i64 24
  %op1618 = ptrtoint ptr %op1618.audit_gep to i64
  store i64 %mem513496.sroa.1.0.copyload, ptr %op1618.audit_gep, align 8
  store i64 %op1618, ptr %op1613.audit_gep, align 8
  %op1626.audit_gep = getelementptr inbounds nuw i8, ptr %mem470581, i64 16
  store i64 ptrtoint (ptr @myl_t_fb0d5bbdabead1b5cc59d8495e5b4a8111f2106f4f0a8a62c46bac565261293a to i64), ptr %op1626.audit_gep, align 8
  store i64 %ptr471, ptr %mem472582, align 8
  %op1636.audit_gep = getelementptr inbounds nuw i8, ptr %mem472582, i64 8
  store i64 %ptr367, ptr %op1636.audit_gep, align 8
  %op1641.audit_gep = getelementptr inbounds nuw i8, ptr %mem472582, i64 16
  store i64 ptrtoint (ptr @myl_t_de305505330c1abad390bf69bceeeab8acb7eff0a00387ae260ef9a7047bf31b to i64), ptr %op1641.audit_gep, align 8
  store i64 %ptr473, ptr %mem474583, align 8
  %op1654.audit_gep = getelementptr inbounds nuw i8, ptr %mem474583, i64 8
  store i64 %ptr558, ptr %op1654.audit_gep, align 8
  %op1659.audit_gep = getelementptr inbounds nuw i8, ptr %mem474583, i64 16
  store i64 ptrtoint (ptr @myl_t_de305505330c1abad390bf69bceeeab8acb7eff0a00387ae260ef9a7047bf31b to i64), ptr %op1659.audit_gep, align 8
  store i64 %ptr475, ptr %p1592, align 8
  %call1674 = call [9 x i64] @myl_f_db346654ceb5a652b5f723024feb479638530adb6b7fd97ec7d886c140c1b503(i64 %p_ctx, i64 %ptr558, i64 %op797)
  store i64 %call582, ptr %p1592, align 8
  %ld1687 = load i64, ptr %p758, align 8
  %cond1689.not = icmp eq i64 %ld1687, 0
  br i1 %cond1689.not, label %bb_ok212, label %bb_failure

bb_ok212:                                         ; preds = %bb_i108
  %call1674.elt690 = extractvalue [9 x i64] %call1674, 8
  %call1674.elt688 = extractvalue [9 x i64] %call1674, 7
  %call1674.elt686 = extractvalue [9 x i64] %call1674, 6
  %call1674.elt684 = extractvalue [9 x i64] %call1674, 5
  %call1674.elt682 = extractvalue [9 x i64] %call1674, 4
  %call1674.elt680 = extractvalue [9 x i64] %call1674, 3
  %call1674.elt678 = extractvalue [9 x i64] %call1674, 2
  %call1674.elt676 = extractvalue [9 x i64] %call1674, 1
  %call1674.elt = extractvalue [9 x i64] %call1674, 0
  %ld1695 = load i64, ptr %mem478585, align 8
  store i64 %ld1695, ptr %p495, align 8
  br label %common.ret

bb_i112:                                          ; preds = %bb_checked60
  %mem559519.sroa.0.0.copyload = load i64, ptr %mem358525, align 8
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(40) %mem561520, ptr noundef nonnull align 8 dereferenceable(40) %mem517498, i64 40, i1 false)
  store i64 116, ptr %op505.audit_gep, align 8
  %op1736 = add i64 %call580, 16
  %p1738 = inttoptr i64 %op1736 to ptr
  %ld1739 = load i64, ptr %p1738, align 8
  store i64 %ld1739, ptr %mem468580, align 8
  %op1744.audit_gep = getelementptr inbounds nuw i8, ptr %mem468580, i64 8
  store i64 %ptr359, ptr %op1744.audit_gep, align 8
  %op1749.audit_gep = getelementptr inbounds nuw i8, ptr %mem468580, i64 16
  store i64 ptrtoint (ptr @myl_t_306680ea529d6c1737c08d47b1547aaebd58d1a20c498e02eef2d4c0bf300a01 to i64), ptr %op1749.audit_gep, align 8
  store i64 %ptr469, ptr %mem470581, align 8
  %op1759.audit_gep = getelementptr inbounds nuw i8, ptr %mem470581, i64 8
  %op1764.audit_gep = getelementptr inbounds nuw i8, ptr %mem470581, i64 24
  %op1764 = ptrtoint ptr %op1764.audit_gep to i64
  store i64 %mem513496.sroa.1.0.copyload, ptr %op1764.audit_gep, align 8
  store i64 %op1764, ptr %op1759.audit_gep, align 8
  %op1772.audit_gep = getelementptr inbounds nuw i8, ptr %mem470581, i64 16
  store i64 ptrtoint (ptr @myl_t_fb0d5bbdabead1b5cc59d8495e5b4a8111f2106f4f0a8a62c46bac565261293a to i64), ptr %op1772.audit_gep, align 8
  store i64 %ptr471, ptr %mem472582, align 8
  %op1782.audit_gep = getelementptr inbounds nuw i8, ptr %mem472582, i64 8
  store i64 %ptr367, ptr %op1782.audit_gep, align 8
  %op1787.audit_gep = getelementptr inbounds nuw i8, ptr %mem472582, i64 16
  store i64 ptrtoint (ptr @myl_t_de305505330c1abad390bf69bceeeab8acb7eff0a00387ae260ef9a7047bf31b to i64), ptr %op1787.audit_gep, align 8
  store i64 %ptr473, ptr %mem474583, align 8
  %op1797.audit_gep = getelementptr inbounds nuw i8, ptr %mem474583, i64 8
  %op1802.audit_gep = getelementptr inbounds nuw i8, ptr %mem474583, i64 24
  %op1802 = ptrtoint ptr %op1802.audit_gep to i64
  store i64 %mem559519.sroa.0.0.copyload, ptr %op1802.audit_gep, align 8
  store i64 %op1802, ptr %op1797.audit_gep, align 8
  %op1810.audit_gep = getelementptr inbounds nuw i8, ptr %mem474583, i64 16
  store i64 ptrtoint (ptr @myl_t_277089d91c0bdf4f2e6862ba7e4a07605119431f5d13f726dd352b06f1b206a9 to i64), ptr %op1810.audit_gep, align 8
  store i64 %ptr475, ptr %mem476584, align 8
  %op1823.audit_gep = getelementptr inbounds nuw i8, ptr %mem476584, i64 8
  store i64 %ptr562, ptr %op1823.audit_gep, align 8
  %op1828.audit_gep = getelementptr inbounds nuw i8, ptr %mem476584, i64 16
  store i64 ptrtoint (ptr @myl_t_de305505330c1abad390bf69bceeeab8acb7eff0a00387ae260ef9a7047bf31b to i64), ptr %op1828.audit_gep, align 8
  store i64 %ptr477, ptr %p1738, align 8
  %call1847 = call [9 x i64] @myl_f_48a09eee5c8fb894310b9440ff51d38042817f75ae5aef58822a4ca959117237(i64 %p_ctx, i64 %mem559519.sroa.0.0.copyload, i64 %ptr562, i64 %op797)
  store i64 %call582, ptr %p1738, align 8
  %ld1860 = load i64, ptr %p758, align 8
  %cond1862.not = icmp eq i64 %ld1860, 0
  br i1 %cond1862.not, label %bb_ok243, label %bb_failure

bb_ok243:                                         ; preds = %bb_i112
  %call1847.elt657 = extractvalue [9 x i64] %call1847, 8
  %call1847.elt655 = extractvalue [9 x i64] %call1847, 7
  %call1847.elt653 = extractvalue [9 x i64] %call1847, 6
  %call1847.elt651 = extractvalue [9 x i64] %call1847, 5
  %call1847.elt649 = extractvalue [9 x i64] %call1847, 4
  %call1847.elt647 = extractvalue [9 x i64] %call1847, 3
  %call1847.elt645 = extractvalue [9 x i64] %call1847, 2
  %call1847.elt643 = extractvalue [9 x i64] %call1847, 1
  %call1847.elt = extractvalue [9 x i64] %call1847, 0
  %ld1868 = load i64, ptr %mem478585, align 8
  store i64 %ld1868, ptr %p495, align 8
  br label %common.ret

bb_i118:                                          ; preds = %bb_checked60
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(40) %mem563521, ptr noundef nonnull align 8 dereferenceable(40) %mem517498, i64 40, i1 false)
  store i64 120, ptr %op505.audit_gep, align 8
  %op1891 = add i64 %call580, 16
  %p1893 = inttoptr i64 %op1891 to ptr
  %ld1894 = load i64, ptr %p1893, align 8
  store i64 %ld1894, ptr %mem468580, align 8
  %op1899.audit_gep = getelementptr inbounds nuw i8, ptr %mem468580, i64 8
  store i64 %ptr359, ptr %op1899.audit_gep, align 8
  %op1904.audit_gep = getelementptr inbounds nuw i8, ptr %mem468580, i64 16
  store i64 ptrtoint (ptr @myl_t_306680ea529d6c1737c08d47b1547aaebd58d1a20c498e02eef2d4c0bf300a01 to i64), ptr %op1904.audit_gep, align 8
  store i64 %ptr469, ptr %mem470581, align 8
  %op1914.audit_gep = getelementptr inbounds nuw i8, ptr %mem470581, i64 8
  %op1919.audit_gep = getelementptr inbounds nuw i8, ptr %mem470581, i64 24
  %op1919 = ptrtoint ptr %op1919.audit_gep to i64
  store i64 %mem513496.sroa.1.0.copyload, ptr %op1919.audit_gep, align 8
  store i64 %op1919, ptr %op1914.audit_gep, align 8
  %op1927.audit_gep = getelementptr inbounds nuw i8, ptr %mem470581, i64 16
  store i64 ptrtoint (ptr @myl_t_fb0d5bbdabead1b5cc59d8495e5b4a8111f2106f4f0a8a62c46bac565261293a to i64), ptr %op1927.audit_gep, align 8
  store i64 %ptr471, ptr %mem472582, align 8
  %op1937.audit_gep = getelementptr inbounds nuw i8, ptr %mem472582, i64 8
  store i64 %ptr367, ptr %op1937.audit_gep, align 8
  %op1942.audit_gep = getelementptr inbounds nuw i8, ptr %mem472582, i64 16
  store i64 ptrtoint (ptr @myl_t_de305505330c1abad390bf69bceeeab8acb7eff0a00387ae260ef9a7047bf31b to i64), ptr %op1942.audit_gep, align 8
  store i64 %ptr473, ptr %mem474583, align 8
  %op1955.audit_gep = getelementptr inbounds nuw i8, ptr %mem474583, i64 8
  store i64 %ptr564, ptr %op1955.audit_gep, align 8
  %op1960.audit_gep = getelementptr inbounds nuw i8, ptr %mem474583, i64 16
  store i64 ptrtoint (ptr @myl_t_de305505330c1abad390bf69bceeeab8acb7eff0a00387ae260ef9a7047bf31b to i64), ptr %op1960.audit_gep, align 8
  store i64 %ptr475, ptr %p1893, align 8
  %call1975 = call [9 x i64] @myl_f_c308f014c1c54b2b1a87e981d746d23f63c6d5d76d153608b5f096891060c5d2(i64 %p_ctx, i64 %ptr564, i64 %op797)
  store i64 %call582, ptr %p1893, align 8
  %ld1988 = load i64, ptr %p758, align 8
  %cond1990.not = icmp eq i64 %ld1988, 0
  br i1 %cond1990.not, label %bb_ok266, label %bb_failure

bb_ok266:                                         ; preds = %bb_i118
  %call1975.elt624 = extractvalue [9 x i64] %call1975, 8
  %call1975.elt622 = extractvalue [9 x i64] %call1975, 7
  %call1975.elt620 = extractvalue [9 x i64] %call1975, 6
  %call1975.elt618 = extractvalue [9 x i64] %call1975, 5
  %call1975.elt616 = extractvalue [9 x i64] %call1975, 4
  %call1975.elt614 = extractvalue [9 x i64] %call1975, 3
  %call1975.elt612 = extractvalue [9 x i64] %call1975, 2
  %call1975.elt610 = extractvalue [9 x i64] %call1975, 1
  %call1975.elt = extractvalue [9 x i64] %call1975, 0
  %ld1996 = load i64, ptr %mem478585, align 8
  store i64 %ld1996, ptr %p495, align 8
  br label %common.ret

bb_i122:                                          ; preds = %bb_checked60
  %mem565522.sroa.1.0.mem517498.sroa_idx = getelementptr inbounds nuw i8, ptr %mem517498, i64 16
  %mem565522.sroa.1.0.copyload = load i64, ptr %mem565522.sroa.1.0.mem517498.sroa_idx, align 8
  %mem565522.sroa.2.0.mem517498.sroa_idx = getelementptr inbounds nuw i8, ptr %mem517498, i64 24
  %mem565522.sroa.2.0.copyload = load i64, ptr %mem565522.sroa.2.0.mem517498.sroa_idx, align 8
  %mem565522.sroa.3.0.mem517498.sroa_idx = getelementptr inbounds nuw i8, ptr %mem517498, i64 32
  %mem565522.sroa.3.0.copyload = load i64, ptr %mem565522.sroa.3.0.mem517498.sroa_idx, align 8
  %ld2115 = load i64, ptr @myl_lit_cfcbeb19fd504ab63857162a7a3c8a2d1c502ba8016deba7737a47c9b2f86357, align 8
  store i64 173, ptr %op505.audit_gep, align 8
  %ld2138 = load i64, ptr %p758, align 8
  %cond2140.not = icmp eq i64 %ld2138, 0
  br i1 %cond2140.not, label %bb_ok278, label %bb_failure

bb_ok278:                                         ; preds = %bb_i122
  %ld2161 = load i64, ptr %mem478585, align 8
  store i64 %ld2161, ptr %p495, align 8
  br label %common.ret

bb_failure:                                       ; preds = %bb_i122, %bb_i118, %bb_i112, %bb_i108, %bb_i104, %bb_i33, %bb_i26, %bb_checked60, %bb_overflow60, %bb_success51, %bb_failed51, %bb_overflow40, %bb_cast_overflow36
  %op2169 = add i64 %call580, 16
  %p2172 = inttoptr i64 %op2169 to ptr
  store i64 %call582, ptr %p2172, align 8
  %ld2175 = load i64, ptr %mem478585, align 8
  store i64 %ld2175, ptr %p495, align 8
  br label %common.ret
}
