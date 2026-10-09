target triple = "x86_64-unknown-linux-gnu"
define zeroext i1 @p1_is_unique(ptr %block) noinline sanitize_thread {
  %rc = load atomic i32, ptr %block unordered, align 8, !tbaa !3, !range !8
  %unique = icmp eq i32 %rc, 1
  ret i1 %unique
}
!1 = !{!"myl.tbaa"}
!2 = !{!"myl.count", !1, i64 0}
!3 = !{!2, !2, i64 0}
!8 = !{i32 1, i32 0}
