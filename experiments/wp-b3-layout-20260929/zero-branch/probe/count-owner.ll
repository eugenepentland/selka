target triple = "x86_64-unknown-linux-gnu"

define dllexport i32 @owner(i64 %p_ctx, i64 %p_payload, i64 %p_output) {
bb_start:
  %slot1 = alloca i64, align 8
  %slot2 = alloca i64, align 8
  %slot3 = alloca i64, align 8
  %slot4 = alloca i64, align 8
  %slot5 = alloca i64, align 8
  %slot6 = alloca i64, align 8
  %slot7 = alloca i32, align 8
  %slot8 = alloca i32, align 8
  store i64 %p_ctx, ptr %slot1, align 8
  store i64 %p_payload, ptr %slot2, align 8
  store i64 %p_output, ptr %slot3, align 8
  %v9 = load i64, ptr %slot2, align 8
  %op10 = sub i64 %v9, 32
  store i64 %op10, ptr %slot4, align 8
  %v11 = load i64, ptr %slot2, align 8
  %p12 = inttoptr i64 %v11 to ptr
  %rgep13 = getelementptr i8, ptr %p12, i64 -32
  %ld14 = load i64, ptr %rgep13, align 8, !alias.scope !9, !noalias !10
  store i64 %ld14, ptr %slot5, align 8
  %v15 = load i64, ptr %slot5, align 8
  %op16 = add i64 %v15, 1
  store i64 %op16, ptr %slot6, align 8
  %v17 = load i64, ptr %slot6, align 8
  %cmp18 = icmp eq i64 %v17, 0
  %cv19 = zext i1 %cmp18 to i32
  store i32 %cv19, ptr %slot7, align 8
  %v20 = load i32, ptr %slot7, align 8
  %cv21 = zext i32 %v20 to i64
  %cond22 = icmp ne i64 %cv21, 0
  br i1 %cond22, label %bb_rcglimit480, label %bb_rcgcapacity480
bb_rcglimit480:
  %v23 = load i64, ptr %slot1, align 8
  %p24 = inttoptr i64 %v23 to ptr
  %call25 = call i32 @myl_qbe_rc_status(ptr %p24, i32 2)
  store i32 %call25, ptr %slot8, align 8
  br label %bb_failure
bb_rcgcapacity480:
  %v26 = load i64, ptr %slot6, align 8
  %v27 = load i64, ptr %slot2, align 8
  %p28 = inttoptr i64 %v27 to ptr
  %rgep29 = getelementptr i8, ptr %p28, i64 -32
  store i64 %v26, ptr %rgep29, align 8, !alias.scope !9, !noalias !10
  %v30 = load i64, ptr %slot2, align 8
  %v31 = load i64, ptr %slot3, align 8
  %p32 = inttoptr i64 %v31 to ptr
  store i64 %v30, ptr %p32, align 8, !alias.scope !4, !noalias !3
  ret i32 1
bb_failure:
  ret i32 0
}

declare i32 @myl_qbe_rc_status(ptr, i32)

!0 = distinct !{!0, !"mylang memory classes"}
!1 = distinct !{!1, !0, !"frame"}
!2 = distinct !{!2, !0, !"foreign"}
!3 = !{!1}
!4 = !{!2}
!5 = distinct !{!5, !0, !"object"}
!6 = !{!5}
!7 = !{!1}
!8 = distinct !{!8, !0, !"rc prefix"}
!9 = !{!8}
!10 = !{!1, !5}
