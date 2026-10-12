define internal fastcc void @"my.json::read_literal"(ptr noalias sret([40 x i8]) align 8 %ret, { ptr, i64 } %p0, ptr %p1, { i8, [1 x i64] } %p2) nounwind uwtable !dbg !1000410 {
entry:
  %slot = alloca i64, align 8
  %stack.46 = alloca [8 x i8], align 8
  %stack.48 = alloca [8 x i8], align 8
  %stack.53 = alloca [8 x i8], align 8
  %stack.57 = alloca [8 x i8], align 8
  %stack.61 = alloca [8 x i8], align 8
  %stack.64 = alloca [8 x i8], align 8
  %stack.68 = alloca [8 x i8], align 8
  %stack.71 = alloca [8 x i8], align 8
  %stack.75 = alloca [8 x i8], align 8
  %stack.78 = alloca [8 x i8], align 8
  %stack.82 = alloca [8 x i8], align 8
  %stack.85 = alloca [8 x i8], align 8
  %stack.89 = alloca [8 x i8], align 8
  %myl.cnt.saved = load ptr, ptr @myl_count_current, align 8
  %myl.cnt.active = call ptr @myl_count_function_local(ptr @myl.cf.40)
  store ptr %myl.cnt.active, ptr @myl_count_current, align 8
  %myl.cnt.calls.at = getelementptr inbounds i8, ptr %myl.cnt.active, i64 8
  %myl.cnt.calls = load i64, ptr %myl.cnt.calls.at, align 8
  %myl.cnt.calls.1 = add i64 %myl.cnt.calls, 1
  store i64 %myl.cnt.calls.1, ptr %myl.cnt.calls.at, align 8
  br label %b0
b0:
  %v3 = extractvalue { ptr, i64 } %p0, 1
  %h.1 = getelementptr inbounds i8, ptr %p1, i64 8
  %v4 = load i64, ptr %h.1, align 8, !tbaa !5
  %v5 = add i64 %v4, 0
  %p.2 = call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %v3, i64 %v5)
  %v6 = extractvalue { i64, i1 } %p.2, 0
  %o.3 = extractvalue { i64, i1 } %p.2, 1
  %cnt.4.record = call ptr @myl_count_site_local(ptr @myl.cs.195)
  %cnt.4.at = getelementptr inbounds i8, ptr %cnt.4.record, i64 48
  %cnt.4 = load i64, ptr %cnt.4.at, align 8
  %cnt.5 = add i64 %cnt.4, 1
  store i64 %cnt.5, ptr %cnt.4.at, align 8
  br i1 %o.3, label %trap.6, label %b0.7, !prof !0
trap.6:
  call void @myl_core_trap(ptr @myl.site.32, i64 %v3, i64 %v5) #2, !dbg !1000412
  unreachable
b0.7:
  %v7 = extractvalue { ptr, i64 } %p0, 0
  %h.8 = getelementptr inbounds i8, ptr %v7, i64 8
  %v8 = load i64, ptr %h.8, align 8, !tbaa !5
  %v9 = add i64 %v8, 0
  %v10 = icmp sgt i64 %v6, %v9
  br i1 %v10, label %b1, label %b2
b1:
  %v13 = notail call fastcc ptr @"my.json::parse_error"({ ptr, i64 } %p0, ptr @myl.str.73), !dbg !1000414
  call preserve_mostcc void @myl_core_err_trace_origin_preserve_most(ptr @myl.site.33) #1
  store i64 1, ptr %ret, align 8, !tbaa !7
  %fp.9 = getelementptr inbounds i8, ptr %ret, i64 8
  store ptr %v13, ptr %fp.9, align 8, !tbaa !7
  %fp.10 = getelementptr inbounds i8, ptr %ret, i64 24
  %sf.11 = extractvalue { ptr, i64 } %p0, 0
  store ptr %sf.11, ptr %fp.10, align 8, !tbaa !7
  %sf.12 = extractvalue { ptr, i64 } %p0, 1
  %fp.13 = getelementptr inbounds i8, ptr %fp.10, i64 8
  store i64 %sf.12, ptr %fp.13, align 8, !tbaa !7
  store ptr %myl.cnt.saved, ptr @myl_count_current, align 8
  ret void
b2:
  %v18 = extractvalue { ptr, i64 } %p0, 0
  %h.14 = getelementptr inbounds i8, ptr %p1, i64 8
  %v19 = load i64, ptr %h.14, align 8, !tbaa !5
  %v20 = add i64 %v19, 0
  %p.15 = call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %v3, i64 %v20)
  %v21 = extractvalue { i64, i1 } %p.15, 0
  %o.16 = extractvalue { i64, i1 } %p.15, 1
  %cnt.17.record = call ptr @myl_count_site_local(ptr @myl.cs.196)
  %cnt.17.at = getelementptr inbounds i8, ptr %cnt.17.record, i64 48
  %cnt.17 = load i64, ptr %cnt.17.at, align 8
  %cnt.18 = add i64 %cnt.17, 1
  store i64 %cnt.18, ptr %cnt.17.at, align 8
  br i1 %o.16, label %trap.19, label %b2.20, !prof !0
trap.19:
  call void @myl_core_trap(ptr @myl.site.34, i64 %v3, i64 %v20) #2, !dbg !1000416
  unreachable
b2.20:
  %v22 = call ptr @myl_core_bytes_slice(ptr %v18, i64 %v3, i64 %v21), !dbg !1000418
  %v23 = call i1 @myl_core_str_eq(ptr %v22, ptr %p1), !dbg !1000420
  %cnt.21.record = call ptr @myl_count_site_local(ptr @myl.cs.197)
  %cnt.21.at = getelementptr inbounds i8, ptr %cnt.21.record, i64 48
  %cnt.21 = load i64, ptr %cnt.21.at, align 8
  %cnt.22 = add i64 %cnt.21, 1
  store i64 %cnt.22, ptr %cnt.21.at, align 8
  call void @myl_core_drop_owned(ptr %v22)
  %v24 = xor i1 %v23, true
  br i1 %v24, label %b3, label %b4
b3:
  %v27 = notail call fastcc ptr @"my.json::parse_error"({ ptr, i64 } %p0, ptr @myl.str.74), !dbg !1000422
  call preserve_mostcc void @myl_core_err_trace_origin_preserve_most(ptr @myl.site.35) #1
  store i64 1, ptr %ret, align 8, !tbaa !7
  %fp.23 = getelementptr inbounds i8, ptr %ret, i64 8
  store ptr %v27, ptr %fp.23, align 8, !tbaa !7
  %fp.24 = getelementptr inbounds i8, ptr %ret, i64 24
  %sf.25 = extractvalue { ptr, i64 } %p0, 0
  store ptr %sf.25, ptr %fp.24, align 8, !tbaa !7
  %sf.26 = extractvalue { ptr, i64 } %p0, 1
  %fp.27 = getelementptr inbounds i8, ptr %fp.24, i64 8
  store i64 %sf.26, ptr %fp.27, align 8, !tbaa !7
  store ptr %myl.cnt.saved, ptr @myl_count_current, align 8
  ret void
b4:
  %h.28 = getelementptr inbounds i8, ptr %p1, i64 8
  %v32 = load i64, ptr %h.28, align 8, !tbaa !5
  %v33 = add i64 %v32, 0
  %p.29 = call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %v3, i64 %v33)
  %v34 = extractvalue { i64, i1 } %p.29, 0
  %o.30 = extractvalue { i64, i1 } %p.29, 1
  %cnt.31.record = call ptr @myl_count_site_local(ptr @myl.cs.198)
  %cnt.31.at = getelementptr inbounds i8, ptr %cnt.31.record, i64 48
  %cnt.31 = load i64, ptr %cnt.31.at, align 8
  %cnt.32 = add i64 %cnt.31, 1
  store i64 %cnt.32, ptr %cnt.31.at, align 8
  br i1 %o.30, label %trap.33, label %b4.34, !prof !0
trap.33:
  call void @myl_core_trap(ptr @myl.site.36, i64 %v3, i64 %v33) #2, !dbg !1000424
  unreachable
b4.34:
  %v35 = insertvalue { ptr, i64 } %p0, i64 %v34, 1
  %t.35 = extractvalue { i8, [1 x i64] } %p2, 0
  %v36 = zext i8 %t.35 to i32
  %v38 = icmp eq i32 %v36, 0
  br i1 %v38, label %b6, label %b7
b5:
  %v85 = phi { i8, [1 x i64] } [ %v40, %b6 ], [ %v46, %b8 ], [ %v52, %b10 ], [ %v58, %b12 ], [ %v67, %b14 ], [ %v76, %b16 ], [ %v83, %b18 ]
  store i64 0, ptr %ret, align 8, !tbaa !7
  %fp.36 = getelementptr inbounds i8, ptr %ret, i64 8
  %st.37 = extractvalue { i8, [1 x i64] } %v85, 0
  %st.38 = zext i8 %st.37 to i64
  store i64 %st.38, ptr %fp.36, align 8, !tbaa !7
  %fp.39 = getelementptr inbounds i8, ptr %fp.36, i64 8
  %sw.40 = extractvalue { i8, [1 x i64] } %v85, 1, 0
  store i64 %sw.40, ptr %fp.39, align 8, !tbaa !7
  %fp.41 = getelementptr inbounds i8, ptr %ret, i64 24
  %sf.42 = extractvalue { ptr, i64 } %v35, 0
  store ptr %sf.42, ptr %fp.41, align 8, !tbaa !7
  %sf.43 = extractvalue { ptr, i64 } %v35, 1
  %fp.44 = getelementptr inbounds i8, ptr %fp.41, i64 8
  store i64 %sf.43, ptr %fp.44, align 8, !tbaa !7
  store ptr %myl.cnt.saved, ptr @myl_count_current, align 8
  ret void
b6:
  %u.45 = insertvalue { i8, [1 x i64] } poison, i8 0, 0
  store [1 x i64] zeroinitializer, ptr %stack.46, align 8, !tbaa !7
  %uw.47 = load i64, ptr %stack.46, align 8, !tbaa !7
  %v40 = insertvalue { i8, [1 x i64] } %u.45, i64 %uw.47, 1, 0
  br label %b5
b7:
  %v43 = icmp eq i32 %v36, 1
  br i1 %v43, label %b8, label %b9
b8:
  %pw.49 = extractvalue { i8, [1 x i64] } %p2, 1, 0
  store i64 %pw.49, ptr %stack.48, align 8, !tbaa !7
  %lb.51 = load i8, ptr %stack.48, align 1, !tbaa !7
  %lf.50 = trunc i8 %lb.51 to i1
  %v45 = insertvalue { i1 } poison, i1 %lf.50, 0
  %u.52 = insertvalue { i8, [1 x i64] } poison, i8 1, 0
  store [1 x i64] zeroinitializer, ptr %stack.53, align 8, !tbaa !7
  %sf.54 = extractvalue { i1 } %v45, 0
  %sb.55 = zext i1 %sf.54 to i8
  store i8 %sb.55, ptr %stack.53, align 1, !tbaa !7
  %uw.56 = load i64, ptr %stack.53, align 8, !tbaa !7
  %v46 = insertvalue { i8, [1 x i64] } %u.52, i64 %uw.56, 1, 0
  br label %b5
b9:
  %v49 = icmp eq i32 %v36, 2
  br i1 %v49, label %b10, label %b11
b10:
  %pw.58 = extractvalue { i8, [1 x i64] } %p2, 1, 0
  store i64 %pw.58, ptr %stack.57, align 8, !tbaa !7
  %lf.59 = load i64, ptr %stack.57, align 8, !tbaa !7
  %v51 = insertvalue { i64 } poison, i64 %lf.59, 0
  %u.60 = insertvalue { i8, [1 x i64] } poison, i8 2, 0
  store [1 x i64] zeroinitializer, ptr %stack.61, align 8, !tbaa !7
  %sf.62 = extractvalue { i64 } %v51, 0
  store i64 %sf.62, ptr %stack.61, align 8, !tbaa !7
  %uw.63 = load i64, ptr %stack.61, align 8, !tbaa !7
  %v52 = insertvalue { i8, [1 x i64] } %u.60, i64 %uw.63, 1, 0
  br label %b5
b11:
  %v55 = icmp eq i32 %v36, 3
  br i1 %v55, label %b12, label %b13
b12:
  %pw.65 = extractvalue { i8, [1 x i64] } %p2, 1, 0
  store i64 %pw.65, ptr %stack.64, align 8, !tbaa !7
  %lf.66 = load double, ptr %stack.64, align 8, !tbaa !7
  %v57 = insertvalue { double } poison, double %lf.66, 0
  %u.67 = insertvalue { i8, [1 x i64] } poison, i8 3, 0
  store [1 x i64] zeroinitializer, ptr %stack.68, align 8, !tbaa !7
  %sf.69 = extractvalue { double } %v57, 0
  store double %sf.69, ptr %stack.68, align 8, !tbaa !7
  %uw.70 = load i64, ptr %stack.68, align 8, !tbaa !7
  %v58 = insertvalue { i8, [1 x i64] } %u.67, i64 %uw.70, 1, 0
  br label %b5
b13:
  %v61 = icmp eq i32 %v36, 4
  br i1 %v61, label %b14, label %b15
b14:
  %pw.72 = extractvalue { i8, [1 x i64] } %p2, 1, 0
  store i64 %pw.72, ptr %stack.71, align 8, !tbaa !7
  %lf.73 = load ptr, ptr %stack.71, align 8, !tbaa !7
  %v63 = insertvalue { ptr } poison, ptr %lf.73, 0
  %v64 = extractvalue { ptr } %v63, 0
  %v65 = call ptr @myl_core_owned_octets_copy(ptr %v64), !dbg !1000426
  %v66 = insertvalue { ptr } poison, ptr %v65, 0
  %u.74 = insertvalue { i8, [1 x i64] } poison, i8 4, 0
  store [1 x i64] zeroinitializer, ptr %stack.75, align 8, !tbaa !7
  %sf.76 = extractvalue { ptr } %v66, 0
  store ptr %sf.76, ptr %stack.75, align 8, !tbaa !7
  %uw.77 = load i64, ptr %stack.75, align 8, !tbaa !7
  %v67 = insertvalue { i8, [1 x i64] } %u.74, i64 %uw.77, 1, 0
  br label %b5
b15:
  %v70 = icmp eq i32 %v36, 5
  br i1 %v70, label %b16, label %b17
b16:
  %pw.79 = extractvalue { i8, [1 x i64] } %p2, 1, 0
  store i64 %pw.79, ptr %stack.78, align 8, !tbaa !7
  %lf.80 = load ptr, ptr %stack.78, align 8, !tbaa !7
  %v72 = insertvalue { ptr } poison, ptr %lf.80, 0
  %v73 = extractvalue { ptr } %v72, 0
  %v74 = notail call fastcc ptr @myl_core_owned_copy_22(ptr %v73), !dbg !1000428
  %v75 = insertvalue { ptr } poison, ptr %v74, 0
  %u.81 = insertvalue { i8, [1 x i64] } poison, i8 5, 0
  store [1 x i64] zeroinitializer, ptr %stack.82, align 8, !tbaa !7
  %sf.83 = extractvalue { ptr } %v75, 0
  store ptr %sf.83, ptr %stack.82, align 8, !tbaa !7
  %uw.84 = load i64, ptr %stack.82, align 8, !tbaa !7
  %v76 = insertvalue { i8, [1 x i64] } %u.81, i64 %uw.84, 1, 0
  br label %b5
b17:
  br label %b18
b18:
  %pw.86 = extractvalue { i8, [1 x i64] } %p2, 1, 0
  store i64 %pw.86, ptr %stack.85, align 8, !tbaa !7
  %lf.87 = load ptr, ptr %stack.85, align 8, !tbaa !7
  %v79 = insertvalue { ptr } poison, ptr %lf.87, 0
  %v80 = extractvalue { ptr } %v79, 0
  %v81 = notail call fastcc ptr @myl_core_owned_copy_24(ptr %v80), !dbg !1000430
  %v82 = insertvalue { ptr } poison, ptr %v81, 0
  %u.88 = insertvalue { i8, [1 x i64] } poison, i8 6, 0
  store [1 x i64] zeroinitializer, ptr %stack.89, align 8, !tbaa !7
  %sf.90 = extractvalue { ptr } %v82, 0
  store ptr %sf.90, ptr %stack.89, align 8, !tbaa !7
  %uw.91 = load i64, ptr %stack.89, align 8, !tbaa !7
  %v83 = insertvalue { i8, [1 x i64] } %u.88, i64 %uw.91, 1, 0
  br label %b5
}
