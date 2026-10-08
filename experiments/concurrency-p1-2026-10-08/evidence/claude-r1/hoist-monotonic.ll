target triple = "x86_64-unknown-linux-gnu"
define void @f(ptr noalias %block, ptr noalias %out, i64 %n) {
entry:
  br label %loop
loop:
  %i = phi i64 [0, %entry], [%i1, %loop]
  %c = load atomic i32, ptr %block monotonic, align 8, !tbaa !3
  %u = icmp eq i32 %c, 1
  %z = zext i1 %u to i32
  %p = getelementptr i32, ptr %out, i64 %i
  store i32 %z, ptr %p, align 4, !tbaa !5
  %i1 = add i64 %i, 1
  %d = icmp eq i64 %i1, %n
  br i1 %d, label %exit, label %loop
exit:
  ret void
}
!1 = !{!"myl.tbaa"}
!2 = !{!"myl.count", !1, i64 0}
!3 = !{!2, !2, i64 0}
!4 = !{!"myl.other", !1, i64 0}
!5 = !{!4, !4, i64 0}
