target triple = "x86_64-unknown-linux-gnu"
declare preserve_mostcc void @myl_core_retain_slow(ptr) nounwind cold
declare preserve_mostcc void @myl_core_release_slow(ptr) nounwind cold
declare void @myl_core_free(ptr) nounwind
declare void @use(ptr) nounwind

; retain, retain, release, release of the same block
define void @rr(ptr %b) nounwind {
entry:
  %c0 = load atomic i32, ptr %b unordered, align 8, !tbaa !3, !range !8
  %p0 = icmp ult i32 %c0, 2147483646
  br i1 %p0, label %inc0, label %slow0, !prof !23
inc0:
  %n0 = add nuw i32 %c0, 1
  store i32 %n0, ptr %b, align 8, !tbaa !3
  br label %d0
slow0:
  call preserve_mostcc void @myl_core_retain_slow(ptr %b)
  br label %d0
d0:
  call void @use(ptr %b)
  %c1 = load atomic i32, ptr %b unordered, align 8, !tbaa !3, !range !8
  %p1 = icmp ult i32 %c1, 2147483648
  br i1 %p1, label %dec1, label %slow1, !prof !23
dec1:
  %n1 = sub nuw i32 %c1, 1
  %z1 = icmp eq i32 %n1, 0
  br i1 %z1, label %free1, label %keep1
keep1:
  store i32 %n1, ptr %b, align 8, !tbaa !3
  br label %d1
free1:
  call void @myl_core_free(ptr %b)
  br label %d1
slow1:
  call preserve_mostcc void @myl_core_release_slow(ptr %b)
  br label %d1
d1:
  ret void
}

; retain then immediately release (no call between)
define void @pair(ptr %b) nounwind {
entry:
  %c0 = load atomic i32, ptr %b unordered, align 8, !tbaa !3, !range !8
  %p0 = icmp ult i32 %c0, 2147483646
  br i1 %p0, label %inc0, label %slow0, !prof !23
inc0:
  %n0 = add nuw i32 %c0, 1
  store i32 %n0, ptr %b, align 8, !tbaa !3
  br label %d0
slow0:
  call preserve_mostcc void @myl_core_retain_slow(ptr %b)
  br label %d0
d0:
  %c1 = load atomic i32, ptr %b unordered, align 8, !tbaa !3, !range !8
  %p1 = icmp ult i32 %c1, 2147483648
  br i1 %p1, label %dec1, label %slow1, !prof !23
dec1:
  %n1 = sub nuw i32 %c1, 1
  %z1 = icmp eq i32 %n1, 0
  br i1 %z1, label %free1, label %keep1
keep1:
  store i32 %n1, ptr %b, align 8, !tbaa !3
  br label %d1
free1:
  call void @myl_core_free(ptr %b)
  br label %d1
slow1:
  call preserve_mostcc void @myl_core_release_slow(ptr %b)
  br label %d1
d1:
  ret void
}

; loop: retain each iteration, element stored elsewhere (n retains)
define void @loopretain(ptr %b, ptr %out, i64 %n) nounwind {
entry:
  br label %head
head:
  %i = phi i64 [0, %entry], [%i1, %d0]
  %done = icmp eq i64 %i, %n
  br i1 %done, label %exit, label %body
body:
  %c0 = load atomic i32, ptr %b unordered, align 8, !tbaa !3, !range !8
  %p0 = icmp ult i32 %c0, 2147483646
  br i1 %p0, label %inc0, label %slow0, !prof !23
inc0:
  %n0 = add nuw i32 %c0, 1
  store i32 %n0, ptr %b, align 8, !tbaa !3
  br label %d0
slow0:
  call preserve_mostcc void @myl_core_retain_slow(ptr %b)
  br label %d0
d0:
  %slot = getelementptr inbounds ptr, ptr %out, i64 %i
  store ptr %b, ptr %slot, align 8, !tbaa !22
  %i1 = add i64 %i, 1
  br label %head
exit:
  ret void
}
!0 = !{!"myl"}
!1 = !{!"myl.any", !0, i64 0}
!2 = !{!"myl.count", !1, i64 0}
!3 = !{!2, !2, i64 0}
!8 = !{i32 1, i32 0}
!21 = !{!"myl.data.ptr", !1, i64 0}
!22 = !{!21, !21, i64 0}
!23 = !{!"branch_weights", i32 32, i32 1}
