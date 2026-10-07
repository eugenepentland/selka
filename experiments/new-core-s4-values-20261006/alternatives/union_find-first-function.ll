define internal i64 @"my.row_union_find::batch_result"(i64 %p0, i64 %p1, i64 %p2) nounwind uwtable !dbg !1000021 {
entry:
  %slot = alloca i64, align 8
  br label %b0
b0:
  %v5 = icmp slt i64 0, %p0
  br i1 %v5, label %b1, label %b2
b1:
  br i1 false, label %b3, label %b5
b2:
  %v30 = phi i64 [ 0, %b0 ], [ %v31, %b4 ]
  %v33 = call ptr @myl_core_list_new(i64 %v30, i64 8)
  br label %b9
b3:
  %v11 = icmp slt i64 %p0, 0
  br i1 %v11, label %b6, label %b8
b4:
  %v31 = phi i64 [ %v32, %b7 ], [ %v27, %b5 ]
  br label %b2
b5:
  %v26 = sub nsw i64 %p0, 0
  %v27 = add i64 %v26, 0
  br label %b4
b6:
  %p.1 = call { i64, i1 } @llvm.ssub.with.overflow.i64(i64 %p0, i64 0)
  %v13 = extractvalue { i64, i1 } %p.1, 0
  %o.2 = extractvalue { i64, i1 } %p.1, 1
  br i1 %o.2, label %trap.3, label %b6.4, !prof !0
trap.3:
  call void @myl_core_trap(i32 13, i64 %p0, i64 0), !dbg !1000022
  unreachable
b6.4:
  %lo.5 = icmp slt i64 %v13, 0
  br i1 %lo.5, label %trap.6, label %b6.4.7, !prof !0
trap.6:
  call void @myl_core_trap(i32 14, i64 %v13, i64 0), !dbg !1000023
  unreachable
b6.4.7:
  %v14 = add i64 %v13, 0
  br label %b7
b7:
  %v32 = phi i64 [ %v14, %b6.4.7 ], [ %v23, %b8.10.14.18.21.25.29 ]
  br label %b4
b8:
  %lo.8 = icmp slt i64 %p0, 0
  br i1 %lo.8, label %trap.9, label %b8.10, !prof !0
trap.9:
  call void @myl_core_trap(i32 15, i64 %p0, i64 0), !dbg !1000024
  unreachable
b8.10:
  %v16 = add i64 %p0, 0
  %p.11 = call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 0, i64 1)
  %v18 = extractvalue { i64, i1 } %p.11, 0
  %o.12 = extractvalue { i64, i1 } %p.11, 1
  br i1 %o.12, label %trap.13, label %b8.10.14, !prof !0
trap.13:
  call void @myl_core_trap(i32 16, i64 0, i64 1), !dbg !1000025
  unreachable
b8.10.14:
  %n.15 = call { i64, i1 } @llvm.ssub.with.overflow.i64(i64 0, i64 %v18)
  %v19 = extractvalue { i64, i1 } %n.15, 0
  %o.16 = extractvalue { i64, i1 } %n.15, 1
  br i1 %o.16, label %trap.17, label %b8.10.14.18, !prof !0
trap.17:
  call void @myl_core_trap(i32 17, i64 %v18, i64 0), !dbg !1000026
  unreachable
b8.10.14.18:
  %lo.19 = icmp slt i64 %v19, 0
  br i1 %lo.19, label %trap.20, label %b8.10.14.18.21, !prof !0
trap.20:
  call void @myl_core_trap(i32 18, i64 %v19, i64 0), !dbg !1000027
  unreachable
b8.10.14.18.21:
  %v20 = add i64 %v19, 0
  %p.22 = call { i64, i1 } @llvm.uadd.with.overflow.i64(i64 %v16, i64 %v20)
  %v21 = extractvalue { i64, i1 } %p.22, 0
  %o.23 = extractvalue { i64, i1 } %p.22, 1
  br i1 %o.23, label %trap.24, label %b8.10.14.18.21.25, !prof !0
trap.24:
  call void @myl_core_trap(i32 19, i64 %v16, i64 %v20), !dbg !1000028
  unreachable
b8.10.14.18.21.25:
  %p.26 = call { i64, i1 } @llvm.uadd.with.overflow.i64(i64 %v21, i64 1)
  %v23 = extractvalue { i64, i1 } %p.26, 0
  %o.27 = extractvalue { i64, i1 } %p.26, 1
  br i1 %o.27, label %trap.28, label %b8.10.14.18.21.25.29, !prof !0
trap.28:
  call void @myl_core_trap(i32 20, i64 %v21, i64 1), !dbg !1000029
  unreachable
b8.10.14.18.21.25.29:
  br label %b7
b9:
  %v35 = phi i64 [ 0, %b2 ], [ %v42, %b11 ]
  %v39 = phi ptr [ %v33, %b2 ], [ %v40, %b11 ]
  %v37 = icmp slt i64 %v35, %p0
  br i1 %v37, label %b10, label %b12
b10:
  %v40 = call ptr @myl_core_list_reserve(ptr %v39, i64 8)
  %pl.30 = getelementptr inbounds i8, ptr %v40, i64 8
  %plen.31 = load i64, ptr %pl.30, align 8, !tbaa !5
  %data.33 = getelementptr inbounds i8, ptr %v40, i64 32
  %elt.34 = getelementptr inbounds i64, ptr %data.33, i64 %plen.31
  store i64 %v35, ptr %elt.34, align 8, !tbaa !7
  %pn.32 = add nuw nsw i64 %plen.31, 1
  store i64 %pn.32, ptr %pl.30, align 8, !tbaa !5
  %v42 = add nuw nsw i64 %v35, 1
  br label %b11
b11:
  br label %b9
b12:
  br label %b13
b13:
  %v57 = phi i64 [ 0, %b12 ], [ %v104, %b15 ]
  %v78 = phi ptr [ %v39, %b12 ], [ %v122, %b15 ]
  %v59 = icmp slt i64 %v57, %p0
  br i1 %v59, label %b14, label %b16
b14:
  %p.35 = call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %p2, i64 %p1)
  %v63 = extractvalue { i64, i1 } %p.35, 0
  %o.36 = extractvalue { i64, i1 } %p.35, 1
  br i1 %o.36, label %trap.37, label %b14.38, !prof !0
trap.37:
  call void @myl_core_trap(i32 21, i64 %p2, i64 %p1), !dbg !1000030
  unreachable
b14.38:
  %v65 = mul nuw nsw i64 13, %v57
  %p.39 = call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %v63, i64 %v65)
  %v66 = extractvalue { i64, i1 } %p.39, 0
  %o.40 = extractvalue { i64, i1 } %p.39, 1
  br i1 %o.40, label %trap.41, label %b14.38.42, !prof !0
trap.41:
  call void @myl_core_trap(i32 22, i64 %v63, i64 %v65), !dbg !1000031
  unreachable
b14.38.42:
  %z.43 = icmp eq i64 %p0, 0
  br i1 %z.43, label %trap.44, label %b14.38.42.45, !prof !0
trap.44:
  call void @myl_core_trap(i32 23, i64 %v66, i64 %p0), !dbg !1000032
  unreachable
b14.38.42.45:
  %m.46 = icmp eq i64 %p0, -1
  %d.47 = select i1 %m.46, i64 1, i64 %p0
  %q.48 = sdiv i64 %v66, %d.47
  %r.49 = srem i64 %v66, %d.47
  %rnz.50 = icmp ne i64 %r.49, 0
  %x.51 = xor i64 %r.49, %p0
  %neg.52 = icmp slt i64 %x.51, 0
  %fix.53 = and i1 %rnz.50, %neg.52
  %ra.54 = select i1 %fix.53, i64 %p0, i64 0
  %v68 = add i64 %r.49, %ra.54
  %p.55 = call { i64, i1 } @llvm.smul.with.overflow.i64(i64 7, i64 %p1)
  %v70 = extractvalue { i64, i1 } %p.55, 0
  %o.56 = extractvalue { i64, i1 } %p.55, 1
  br i1 %o.56, label %trap.57, label %b14.38.42.45.58, !prof !0
trap.57:
  call void @myl_core_trap(i32 24, i64 7, i64 %p1), !dbg !1000033
  unreachable
b14.38.42.45.58:
  %p.59 = call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %p2, i64 %v70)
  %v71 = extractvalue { i64, i1 } %p.59, 0
  %o.60 = extractvalue { i64, i1 } %p.59, 1
  br i1 %o.60, label %trap.61, label %b14.38.42.45.58.62, !prof !0
trap.61:
  call void @myl_core_trap(i32 25, i64 %p2, i64 %v70), !dbg !1000034
  unreachable
b14.38.42.45.58.62:
  %v73 = mul nuw nsw i64 17, %v57
  %p.63 = call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %v71, i64 %v73)
  %v74 = extractvalue { i64, i1 } %p.63, 0
  %o.64 = extractvalue { i64, i1 } %p.63, 1
  br i1 %o.64, label %trap.65, label %b14.38.42.45.58.62.66, !prof !0
trap.65:
  call void @myl_core_trap(i32 26, i64 %v71, i64 %v73), !dbg !1000035
  unreachable
b14.38.42.45.58.62.66:
  %p.67 = call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %v74, i64 1)
  %v76 = extractvalue { i64, i1 } %p.67, 0
  %o.68 = extractvalue { i64, i1 } %p.67, 1
  br i1 %o.68, label %trap.69, label %b14.38.42.45.58.62.66.70, !prof !0
trap.69:
  call void @myl_core_trap(i32 27, i64 %v74, i64 1), !dbg !1000036
  unreachable
b14.38.42.45.58.62.66.70:
  %z.71 = icmp eq i64 %p0, 0
  br i1 %z.71, label %trap.72, label %b14.38.42.45.58.62.66.70.73, !prof !0
trap.72:
  call void @myl_core_trap(i32 28, i64 %v76, i64 %p0), !dbg !1000037
  unreachable
b14.38.42.45.58.62.66.70.73:
  %m.74 = icmp eq i64 %p0, -1
  %d.75 = select i1 %m.74, i64 1, i64 %p0
  %q.76 = sdiv i64 %v76, %d.75
  %r.77 = srem i64 %v76, %d.75
  %rnz.78 = icmp ne i64 %r.77, 0
  %x.79 = xor i64 %r.77, %p0
  %neg.80 = icmp slt i64 %x.79, 0
  %fix.81 = and i1 %rnz.78, %neg.80
  %ra.82 = select i1 %fix.81, i64 %p0, i64 0
  %v77 = add i64 %r.77, %ra.82
  %v79 = call { i64, ptr } @"my.row_union_find::find"(ptr %v78, i64 %v68), !dbg !1000038
  %v80 = extractvalue { i64, ptr } %v79, 0
  %v81 = extractvalue { i64, ptr } %v79, 1
  %v82 = call { i64, ptr } @"my.row_union_find::find"(ptr %v81, i64 %v77), !dbg !1000039
  %v83 = extractvalue { i64, ptr } %v82, 0
  %v84 = extractvalue { i64, ptr } %v82, 1
  %v85 = icmp ne i64 %v80, %v83
  br i1 %v85, label %b17, label %b18
b15:
  %v104 = add nuw nsw i64 %v57, 1
  br label %b13
b16:
  br label %b21
b17:
  %v88 = icmp slt i64 %v80, 0
  br i1 %v88, label %b19, label %b20
b18:
  %v122 = phi ptr [ %v84, %b14.38.42.45.58.62.66.70.73 ], [ %v97, %b31.120 ]
  br label %b15
b19:
  %h.83 = getelementptr inbounds i8, ptr %v84, i64 8
  %v90 = load i64, ptr %h.83, align 8, !tbaa !5
  %v91 = add i64 %v90, 0
  %v92 = add nsw i64 %v91, %v80
  br label %b20
b20:
  %v94 = phi i64 [ %v80, %b17 ], [ %v92, %b19 ]
  %rc.84 = load i32, ptr %v84, align 8, !tbaa !3, !range !8
  %v174 = icmp eq i32 %rc.84, 1
  br i1 %v174, label %b31, label %b32
b21:
  %v126 = phi i64 [ 0, %b16 ], [ %v143, %b23 ]
  %v130 = phi ptr [ %v78, %b16 ], [ %v133, %b23 ]
  %v136 = phi i64 [ 0, %b16 ], [ %v147, %b23 ]
  %v128 = icmp slt i64 %v126, %p0
  br i1 %v128, label %b22, label %b24
b22:
  %v131 = call { i64, ptr } @"my.row_union_find::find"(ptr %v130, i64 %v126), !dbg !1000040
  %v132 = extractvalue { i64, ptr } %v131, 0
  %v133 = extractvalue { i64, ptr } %v131, 1
  %v134 = icmp eq i64 %v132, %v126
  br i1 %v134, label %b25, label %b26
b23:
  %v143 = add nuw nsw i64 %v126, 1
  br label %b21
b24:
  br label %b27
b25:
  %p.85 = call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %v136, i64 1)
  %v138 = extractvalue { i64, i1 } %p.85, 0
  %o.86 = extractvalue { i64, i1 } %p.85, 1
  br i1 %o.86, label %trap.87, label %b25.88, !prof !0
trap.87:
  call void @myl_core_trap(i32 29, i64 %v136, i64 1), !dbg !1000041
  unreachable
b25.88:
  br label %b26
b26:
  %v147 = phi i64 [ %v136, %b22 ], [ %v138, %b25.88 ]
  br label %b23
b27:
  %v153 = phi i64 [ 0, %b24 ], [ %v165, %b29 ]
  %v157 = phi i64 [ 0, %b24 ], [ %v162, %b29 ]
  %v158 = phi ptr [ %v130, %b24 ], [ %v161, %b29 ]
  %v155 = icmp slt i64 %v153, %p0
  br i1 %v155, label %b28, label %b30
b28:
  %v159 = call { i64, ptr } @"my.row_union_find::find"(ptr %v158, i64 %v153), !dbg !1000042
  %v160 = extractvalue { i64, ptr } %v159, 0
  %v161 = extractvalue { i64, ptr } %v159, 1
  %p.89 = call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %v157, i64 %v160)
  %v162 = extractvalue { i64, i1 } %p.89, 0
  %o.90 = extractvalue { i64, i1 } %p.89, 1
  br i1 %o.90, label %trap.91, label %b28.92, !prof !0
trap.91:
  call void @myl_core_trap(i32 30, i64 %v157, i64 %v160), !dbg !1000043
  unreachable
b28.92:
  br label %b29
b29:
  %v165 = add nuw nsw i64 %v153, 1
  br label %b27
b30:
  %rc.93 = load i32, ptr %v158, align 8, !tbaa !3, !range !8
  %rs.94 = icmp eq i32 %rc.93, -1
  br i1 %rs.94, label %b30.96, label %rc.dec.95
rc.dec.95:
  %rn.97 = sub nuw i32 %rc.93, 1
  %rz.98 = icmp eq i32 %rn.97, 0
  br i1 %rz.98, label %rc.free.100, label %rc.keep.99
rc.keep.99:
  store i32 %rn.97, ptr %v158, align 8, !tbaa !3
  br label %b30.96
rc.free.100:
  call void @myl_core_free(ptr %v158)
  br label %b30.96
b30.96:
  %p.101 = call { i64, i1 } @llvm.smul.with.overflow.i64(i64 %v136, i64 1000003)
  %v169 = extractvalue { i64, i1 } %p.101, 0
  %o.102 = extractvalue { i64, i1 } %p.101, 1
  br i1 %o.102, label %trap.103, label %b30.96.104, !prof !0
trap.103:
  call void @myl_core_trap(i32 31, i64 %v136, i64 1000003), !dbg !1000044
  unreachable
b30.96.104:
  %p.105 = call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %v169, i64 %v157)
  %v170 = extractvalue { i64, i1 } %p.105, 0
  %o.106 = extractvalue { i64, i1 } %p.105, 1
  br i1 %o.106, label %trap.107, label %b30.96.104.108, !prof !0
trap.107:
  call void @myl_core_trap(i32 32, i64 %v169, i64 %v157), !dbg !1000045
  unreachable
b30.96.104.108:
  %q.109 = sdiv i64 %v170, 1000000007
  %r.110 = srem i64 %v170, 1000000007
  %rnz.111 = icmp ne i64 %r.110, 0
  %x.112 = xor i64 %r.110, 1000000007
  %neg.113 = icmp slt i64 %x.112, 0
  %fix.114 = and i1 %rnz.111, %neg.113
  %ra.115 = select i1 %fix.114, i64 1000000007, i64 0
  %v172 = add i64 %r.110, %ra.115
  ret i64 %v172
b31:
  %v180 = phi ptr [ %v84, %b20 ], [ %v177, %b32.126 ]
  %lh.116 = getelementptr inbounds i8, ptr %v180, i64 8
  %len.117 = load i64, ptr %lh.116, align 8, !tbaa !5
  %oob.118 = icmp uge i64 %v94, %len.117
  br i1 %oob.118, label %trap.119, label %b31.120, !prof !0
trap.119:
  call void @myl_core_trap(i32 33, i64 %v94, i64 %len.117), !dbg !1000046
  unreachable
b31.120:
  %data.121 = getelementptr inbounds i8, ptr %v180, i64 32
  %elt.122 = getelementptr inbounds i64, ptr %data.121, i64 %v94
  store i64 %v83, ptr %elt.122, align 8, !tbaa !7
  %v97 = getelementptr inbounds i8, ptr %v180, i64 0
  br label %b18
b32:
  %v177 = call ptr @myl_core_list_copy(ptr %v84, i64 8)
  %rc.123 = load i32, ptr %v84, align 8, !tbaa !3, !range !8
  %rs.124 = icmp eq i32 %rc.123, -1
  br i1 %rs.124, label %b32.126, label %rc.dec.125
rc.dec.125:
  %rn.127 = sub nuw i32 %rc.123, 1
  %rz.128 = icmp eq i32 %rn.127, 0
  br i1 %rz.128, label %rc.free.130, label %rc.keep.129
rc.keep.129:
  store i32 %rn.127, ptr %v84, align 8, !tbaa !3
  br label %b32.126
rc.free.130:
  call void @myl_core_free(ptr %v84)
  br label %b32.126
b32.126:
  br label %b31
}