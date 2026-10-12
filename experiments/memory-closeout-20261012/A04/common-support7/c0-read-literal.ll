define internal fastcc void @"my.json::read_literal"(ptr noalias sret([40 x i8]) align 8 %ret, { ptr, i64 } %p0, ptr %p1, { i8, [1 x i64] } %p2) nounwind uwtable !dbg !1000410 {
entry:
  %slot = alloca i64, align 8
  %stack.83 = alloca [8 x i8], align 8
  %stack.85 = alloca [8 x i8], align 8
  %stack.90 = alloca [8 x i8], align 8
  %stack.94 = alloca [8 x i8], align 8
  %stack.98 = alloca [8 x i8], align 8
  %stack.101 = alloca [8 x i8], align 8
  %stack.105 = alloca [8 x i8], align 8
  %stack.108 = alloca [8 x i8], align 8
  %stack.112 = alloca [8 x i8], align 8
  %stack.115 = alloca [8 x i8], align 8
  %stack.119 = alloca [8 x i8], align 8
  %stack.122 = alloca [8 x i8], align 8
  %stack.126 = alloca [8 x i8], align 8
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
  %slicekind.21 = getelementptr inbounds i8, ptr %v18, i64 0
  %slicekind.22 = load i32, ptr %slicekind.21, align 4
  %sliceascii.23 = and i32 %slicekind.22, 256
  %sliceascii.24 = icmp ne i32 %sliceascii.23, 0
  br i1 true, label %slicefast.25, label %sliceslow.26
slicefast.25:
  %slicelen.28 = getelementptr inbounds i8, ptr %v18, i64 8
  %slicelen.29 = load i64, ptr %slicelen.28, align 8
  %clampneg.30 = icmp slt i64 %v3, 0
  %clampwrap.31 = add i64 %v3, %slicelen.29
  %clampend.32 = select i1 %clampneg.30, i64 %clampwrap.31, i64 %v3
  %clamplow.33 = icmp slt i64 %clampend.32, 0
  %clamplow.34 = select i1 %clamplow.33, i64 0, i64 %clampend.32
  %clamphigh.35 = icmp sgt i64 %clamplow.34, %slicelen.29
  %clamped.36 = select i1 %clamphigh.35, i64 %slicelen.29, i64 %clamplow.34
  %clampneg.37 = icmp slt i64 %v21, 0
  %clampwrap.38 = add i64 %v21, %slicelen.29
  %clampend.39 = select i1 %clampneg.37, i64 %clampwrap.38, i64 %v21
  %clamplow.40 = icmp slt i64 %clampend.39, 0
  %clamplow.41 = select i1 %clamplow.40, i64 0, i64 %clampend.39
  %clamphigh.42 = icmp sgt i64 %clamplow.41, %slicelen.29
  %clamped.43 = select i1 %clamphigh.42, i64 %slicelen.29, i64 %clamplow.41
  %slicewidth.44 = sub i64 %clamped.43, %clamped.36
  %sliceempty.45 = icmp slt i64 %slicewidth.44, 0
  %slicewidth.46 = select i1 %sliceempty.45, i64 0, i64 %slicewidth.44
  br label %slicejoin.27
sliceslow.26:
  %slicespan.47 = call { i64, i64 } @myl_core_ir_str_slice_span(ptr %v18, i64 %v3, i64 %v21)
  %sliceat.48 = extractvalue { i64, i64 } %slicespan.47, 0
  %slicewidth.49 = extractvalue { i64, i64 } %slicespan.47, 1
  br label %slicejoin.27
slicejoin.27:
  %sliceat.50 = phi i64 [ %clamped.36, %slicefast.25 ], [ %sliceat.48, %sliceslow.26 ]
  %slicewidth.51 = phi i64 [ %slicewidth.46, %slicefast.25 ], [ %slicewidth.49, %sliceslow.26 ]
  %slicedata.52 = getelementptr inbounds i8, ptr %v18, i64 32
  %slicedata.53 = getelementptr inbounds i8, ptr %slicedata.52, i64 %sliceat.50
  %sliceview.54 = insertvalue { ptr, i64 } poison, ptr %slicedata.53, 0
  %v22 = insertvalue { ptr, i64 } %sliceview.54, i64 %slicewidth.51, 1
  %span.55 = extractvalue { ptr, i64 } %v22, 0
  %span.56 = extractvalue { ptr, i64 } %v22, 1
  %span.57 = getelementptr inbounds i8, ptr %p1, i64 32
  %span.59 = getelementptr inbounds i8, ptr %p1, i64 8
  %span.58 = load i64, ptr %span.59, align 8
  %v23 = call i1 @myl_core_span_eq(ptr %span.55, i64 %span.56, ptr %span.57, i64 %span.58), !dbg !1000418
  %v24 = xor i1 %v23, true
  br i1 %v24, label %b3, label %b4
b3:
  %v27 = notail call fastcc ptr @"my.json::parse_error"({ ptr, i64 } %p0, ptr @myl.str.74), !dbg !1000420
  call preserve_mostcc void @myl_core_err_trace_origin_preserve_most(ptr @myl.site.35) #1
  store i64 1, ptr %ret, align 8, !tbaa !7
  %fp.60 = getelementptr inbounds i8, ptr %ret, i64 8
  store ptr %v27, ptr %fp.60, align 8, !tbaa !7
  %fp.61 = getelementptr inbounds i8, ptr %ret, i64 24
  %sf.62 = extractvalue { ptr, i64 } %p0, 0
  store ptr %sf.62, ptr %fp.61, align 8, !tbaa !7
  %sf.63 = extractvalue { ptr, i64 } %p0, 1
  %fp.64 = getelementptr inbounds i8, ptr %fp.61, i64 8
  store i64 %sf.63, ptr %fp.64, align 8, !tbaa !7
  store ptr %myl.cnt.saved, ptr @myl_count_current, align 8
  ret void
b4:
  %h.65 = getelementptr inbounds i8, ptr %p1, i64 8
  %v32 = load i64, ptr %h.65, align 8, !tbaa !5
  %v33 = add i64 %v32, 0
  %p.66 = call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %v3, i64 %v33)
  %v34 = extractvalue { i64, i1 } %p.66, 0
  %o.67 = extractvalue { i64, i1 } %p.66, 1
  %cnt.68.record = call ptr @myl_count_site_local(ptr @myl.cs.197)
  %cnt.68.at = getelementptr inbounds i8, ptr %cnt.68.record, i64 48
  %cnt.68 = load i64, ptr %cnt.68.at, align 8
  %cnt.69 = add i64 %cnt.68, 1
  store i64 %cnt.69, ptr %cnt.68.at, align 8
  br i1 %o.67, label %trap.70, label %b4.71, !prof !0
trap.70:
  call void @myl_core_trap(ptr @myl.site.36, i64 %v3, i64 %v33) #2, !dbg !1000422
  unreachable
b4.71:
  %v35 = insertvalue { ptr, i64 } %p0, i64 %v34, 1
  %t.72 = extractvalue { i8, [1 x i64] } %p2, 0
  %v36 = zext i8 %t.72 to i32
  %v38 = icmp eq i32 %v36, 0
  br i1 %v38, label %b6, label %b7
b5:
  %v85 = phi { i8, [1 x i64] } [ %v40, %b6 ], [ %v46, %b8 ], [ %v52, %b10 ], [ %v58, %b12 ], [ %v67, %b14 ], [ %v76, %b16 ], [ %v83, %b18 ]
  store i64 0, ptr %ret, align 8, !tbaa !7
  %fp.73 = getelementptr inbounds i8, ptr %ret, i64 8
  %st.74 = extractvalue { i8, [1 x i64] } %v85, 0
  %st.75 = zext i8 %st.74 to i64
  store i64 %st.75, ptr %fp.73, align 8, !tbaa !7
  %fp.76 = getelementptr inbounds i8, ptr %fp.73, i64 8
  %sw.77 = extractvalue { i8, [1 x i64] } %v85, 1, 0
  store i64 %sw.77, ptr %fp.76, align 8, !tbaa !7
  %fp.78 = getelementptr inbounds i8, ptr %ret, i64 24
  %sf.79 = extractvalue { ptr, i64 } %v35, 0
  store ptr %sf.79, ptr %fp.78, align 8, !tbaa !7
  %sf.80 = extractvalue { ptr, i64 } %v35, 1
  %fp.81 = getelementptr inbounds i8, ptr %fp.78, i64 8
  store i64 %sf.80, ptr %fp.81, align 8, !tbaa !7
  store ptr %myl.cnt.saved, ptr @myl_count_current, align 8
  ret void
b6:
  %u.82 = insertvalue { i8, [1 x i64] } poison, i8 0, 0
  store [1 x i64] zeroinitializer, ptr %stack.83, align 8, !tbaa !7
  %uw.84 = load i64, ptr %stack.83, align 8, !tbaa !7
  %v40 = insertvalue { i8, [1 x i64] } %u.82, i64 %uw.84, 1, 0
  br label %b5
b7:
  %v43 = icmp eq i32 %v36, 1
  br i1 %v43, label %b8, label %b9
b8:
  %pw.86 = extractvalue { i8, [1 x i64] } %p2, 1, 0
  store i64 %pw.86, ptr %stack.85, align 8, !tbaa !7
  %lb.88 = load i8, ptr %stack.85, align 1, !tbaa !7
  %lf.87 = trunc i8 %lb.88 to i1
  %v45 = insertvalue { i1 } poison, i1 %lf.87, 0
  %u.89 = insertvalue { i8, [1 x i64] } poison, i8 1, 0
  store [1 x i64] zeroinitializer, ptr %stack.90, align 8, !tbaa !7
  %sf.91 = extractvalue { i1 } %v45, 0
  %sb.92 = zext i1 %sf.91 to i8
  store i8 %sb.92, ptr %stack.90, align 1, !tbaa !7
  %uw.93 = load i64, ptr %stack.90, align 8, !tbaa !7
  %v46 = insertvalue { i8, [1 x i64] } %u.89, i64 %uw.93, 1, 0
  br label %b5
b9:
  %v49 = icmp eq i32 %v36, 2
  br i1 %v49, label %b10, label %b11
b10:
  %pw.95 = extractvalue { i8, [1 x i64] } %p2, 1, 0
  store i64 %pw.95, ptr %stack.94, align 8, !tbaa !7
  %lf.96 = load i64, ptr %stack.94, align 8, !tbaa !7
  %v51 = insertvalue { i64 } poison, i64 %lf.96, 0
  %u.97 = insertvalue { i8, [1 x i64] } poison, i8 2, 0
  store [1 x i64] zeroinitializer, ptr %stack.98, align 8, !tbaa !7
  %sf.99 = extractvalue { i64 } %v51, 0
  store i64 %sf.99, ptr %stack.98, align 8, !tbaa !7
  %uw.100 = load i64, ptr %stack.98, align 8, !tbaa !7
  %v52 = insertvalue { i8, [1 x i64] } %u.97, i64 %uw.100, 1, 0
  br label %b5
b11:
  %v55 = icmp eq i32 %v36, 3
  br i1 %v55, label %b12, label %b13
b12:
  %pw.102 = extractvalue { i8, [1 x i64] } %p2, 1, 0
  store i64 %pw.102, ptr %stack.101, align 8, !tbaa !7
  %lf.103 = load double, ptr %stack.101, align 8, !tbaa !7
  %v57 = insertvalue { double } poison, double %lf.103, 0
  %u.104 = insertvalue { i8, [1 x i64] } poison, i8 3, 0
  store [1 x i64] zeroinitializer, ptr %stack.105, align 8, !tbaa !7
  %sf.106 = extractvalue { double } %v57, 0
  store double %sf.106, ptr %stack.105, align 8, !tbaa !7
  %uw.107 = load i64, ptr %stack.105, align 8, !tbaa !7
  %v58 = insertvalue { i8, [1 x i64] } %u.104, i64 %uw.107, 1, 0
  br label %b5
b13:
  %v61 = icmp eq i32 %v36, 4
  br i1 %v61, label %b14, label %b15
b14:
  %pw.109 = extractvalue { i8, [1 x i64] } %p2, 1, 0
  store i64 %pw.109, ptr %stack.108, align 8, !tbaa !7
  %lf.110 = load ptr, ptr %stack.108, align 8, !tbaa !7
  %v63 = insertvalue { ptr } poison, ptr %lf.110, 0
  %v64 = extractvalue { ptr } %v63, 0
  %v65 = call ptr @myl_core_owned_octets_copy(ptr %v64), !dbg !1000424
  %v66 = insertvalue { ptr } poison, ptr %v65, 0
  %u.111 = insertvalue { i8, [1 x i64] } poison, i8 4, 0
  store [1 x i64] zeroinitializer, ptr %stack.112, align 8, !tbaa !7
  %sf.113 = extractvalue { ptr } %v66, 0
  store ptr %sf.113, ptr %stack.112, align 8, !tbaa !7
  %uw.114 = load i64, ptr %stack.112, align 8, !tbaa !7
  %v67 = insertvalue { i8, [1 x i64] } %u.111, i64 %uw.114, 1, 0
  br label %b5
b15:
  %v70 = icmp eq i32 %v36, 5
  br i1 %v70, label %b16, label %b17
b16:
  %pw.116 = extractvalue { i8, [1 x i64] } %p2, 1, 0
  store i64 %pw.116, ptr %stack.115, align 8, !tbaa !7
  %lf.117 = load ptr, ptr %stack.115, align 8, !tbaa !7
  %v72 = insertvalue { ptr } poison, ptr %lf.117, 0
  %v73 = extractvalue { ptr } %v72, 0
  %v74 = notail call fastcc ptr @myl_core_owned_copy_22(ptr %v73), !dbg !1000426
  %v75 = insertvalue { ptr } poison, ptr %v74, 0
  %u.118 = insertvalue { i8, [1 x i64] } poison, i8 5, 0
  store [1 x i64] zeroinitializer, ptr %stack.119, align 8, !tbaa !7
  %sf.120 = extractvalue { ptr } %v75, 0
  store ptr %sf.120, ptr %stack.119, align 8, !tbaa !7
  %uw.121 = load i64, ptr %stack.119, align 8, !tbaa !7
  %v76 = insertvalue { i8, [1 x i64] } %u.118, i64 %uw.121, 1, 0
  br label %b5
b17:
  br label %b18
b18:
  %pw.123 = extractvalue { i8, [1 x i64] } %p2, 1, 0
  store i64 %pw.123, ptr %stack.122, align 8, !tbaa !7
  %lf.124 = load ptr, ptr %stack.122, align 8, !tbaa !7
  %v79 = insertvalue { ptr } poison, ptr %lf.124, 0
  %v80 = extractvalue { ptr } %v79, 0
  %v81 = notail call fastcc ptr @myl_core_owned_copy_24(ptr %v80), !dbg !1000428
  %v82 = insertvalue { ptr } poison, ptr %v81, 0
  %u.125 = insertvalue { i8, [1 x i64] } poison, i8 6, 0
  store [1 x i64] zeroinitializer, ptr %stack.126, align 8, !tbaa !7
  %sf.127 = extractvalue { ptr } %v82, 0
  store ptr %sf.127, ptr %stack.126, align 8, !tbaa !7
  %uw.128 = load i64, ptr %stack.126, align 8, !tbaa !7
  %v83 = insertvalue { i8, [1 x i64] } %u.125, i64 %uw.128, 1, 0
  br label %b5
}
