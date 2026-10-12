define internal fastcc i64 @"my.walk"(ptr %p0) nounwind uwtable !dbg !1000032 {
entry:
  %slot = alloca i64, align 8
  br label %b0
b0:
  %h.1 = getelementptr inbounds i8, ptr %p0, i64 8
  %v22 = load i64, ptr %h.1, align 8, !tbaa !5
  %view.3 = getelementptr inbounds i8, ptr %p0, i64 32
  %view.2 = getelementptr inbounds i8, ptr %view.3, i64 0
  %view.4 = insertvalue { ptr, i64 } poison, ptr %view.2, 0
  %v1 = insertvalue { ptr, i64 } %view.4, i64 %v22, 1
  br label %b1
b1:
  %v5 = phi i64 [ 0, %b0 ], [ %v17, %b3 ]
  %v11 = phi i64 [ 0, %b0 ], [ %v15, %b3 ]
  %v7 = extractvalue { ptr, i64 } %v1, 1
  %v8 = add i64 %v7, 0
  %v9 = icmp ult i64 %v5, %v8
  br i1 %v9, label %b2, label %b4
b2:
  %bytelen.5 = extractvalue { ptr, i64 } %v1, 1
  %byteoob.8 = icmp uge i64 %v5, %bytelen.5
  br i1 %byteoob.8, label %trap.9, label %b2.10, !prof !0
trap.9:
  call void @myl_core_trap(ptr @myl.site.13, i64 %v5, i64 %bytelen.5) #2, !dbg !1000038
  unreachable
b2.10:
  %bytedata.6 = extractvalue { ptr, i64 } %v1, 0
  %byteslot.7 = getelementptr inbounds i8, ptr %bytedata.6, i64 %v5
  %v13 = load i8, ptr %byteslot.7, align 1
  %v14 = zext i8 %v13 to i64
  %v15 = add nuw nsw i64 %v11, %v14
  %v17 = add nuw nsw i64 %v5, 1
  br label %b3
b3:
  br label %b1
b4:
  ret i64 %v11
}
define internal fastcc i64 @"my.at_zero"(ptr %p0) nounwind uwtable !dbg !1000039 {
entry:
  %slot = alloca i64, align 8
  br label %b0
b0:
  %h.1 = getelementptr inbounds i8, ptr %p0, i64 8
  %v8 = load i64, ptr %h.1, align 8, !tbaa !5
  %view.3 = getelementptr inbounds i8, ptr %p0, i64 32
  %view.2 = getelementptr inbounds i8, ptr %view.3, i64 0
  %view.4 = insertvalue { ptr, i64 } poison, ptr %view.2, 0
  %v1 = insertvalue { ptr, i64 } %view.4, i64 %v8, 1
  %bytelen.5 = extractvalue { ptr, i64 } %v1, 1
  %byteoob.8 = icmp uge i64 0, %bytelen.5
  br i1 %byteoob.8, label %trap.9, label %b0.10, !prof !0
trap.9:
  call void @myl_core_trap(ptr @myl.site.14, i64 0, i64 %bytelen.5) #2, !dbg !1000041
  unreachable
b0.10:
  %bytedata.6 = extractvalue { ptr, i64 } %v1, 0
  %byteslot.7 = getelementptr inbounds i8, ptr %bytedata.6, i64 0
  %v4 = load i8, ptr %byteslot.7, align 1
  %v5 = zext i8 %v4 to i64
  ret i64 %v5
}
define internal fastcc i64 @"my.at"(ptr %p0, i64 %p1) nounwind uwtable !dbg !1000042 {
entry:
  %slot = alloca i64, align 8
  br label %b0
b0:
  %h.1 = getelementptr inbounds i8, ptr %p0, i64 8
  %v8 = load i64, ptr %h.1, align 8, !tbaa !5
  %view.3 = getelementptr inbounds i8, ptr %p0, i64 32
  %view.2 = getelementptr inbounds i8, ptr %view.3, i64 0
  %view.4 = insertvalue { ptr, i64 } poison, ptr %view.2, 0
  %v2 = insertvalue { ptr, i64 } %view.4, i64 %v8, 1
  %span.5 = extractvalue { ptr, i64 } %v2, 0
  %span.6 = extractvalue { ptr, i64 } %v2, 1
  %v3 = call i64 @myl_core_span_bytes_index_offset(ptr %span.5, i64 %span.6, i64 %p1), !dbg !1000044
  %bytelen.7 = extractvalue { ptr, i64 } %v2, 1
  %byteoob.10 = icmp uge i64 %v3, %bytelen.7
  br i1 %byteoob.10, label %trap.11, label %b0.12, !prof !0
trap.11:
  call void @myl_core_trap(ptr @myl.site.15, i64 %p1, i64 %bytelen.7) #2, !dbg !1000046
  unreachable
b0.12:
  %bytedata.8 = extractvalue { ptr, i64 } %v2, 0
  %byteslot.9 = getelementptr inbounds i8, ptr %bytedata.8, i64 %v3
  %v4 = load i8, ptr %byteslot.9, align 1
  %v5 = zext i8 %v4 to i64
  ret i64 %v5
}
define i32 @main(i32 %argc, ptr %argv) uwtable !dbg !1000048 {
entry:
  call void @myl_core_start()
  %args = call ptr @myl_core_args(i32 %argc, ptr %argv)
