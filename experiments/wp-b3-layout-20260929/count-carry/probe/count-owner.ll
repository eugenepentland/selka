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
  %v18 = load i64, ptr %slot5, align 8
  %cmp19 = icmp ult i64 %v17, %v18
  %cv20 = zext i1 %cmp19 to i32
  store i32 %cv20, ptr %slot7, align 8
  %v21 = load i32, ptr %slot7, align 8
  %cv22 = zext i32 %v21 to i64
  %cond23 = icmp ne i64 %cv22, 0
  br i1 %cond23, label %bb_rcglimit480, label %bb_rcgcapacity480
bb_rcglimit480:
  %v24 = load i64, ptr %slot1, align 8
  %p25 = inttoptr i64 %v24 to ptr
  %call26 = call i32 @myl_qbe_rc_status(ptr %p25, i32 2)
  store i32 %call26, ptr %slot8, align 8
  br label %bb_failure
bb_rcgcapacity480:
  %v27 = load i64, ptr %slot6, align 8
  %v28 = load i64, ptr %slot2, align 8
  %p29 = inttoptr i64 %v28 to ptr
  %rgep30 = getelementptr i8, ptr %p29, i64 -32
  store i64 %v27, ptr %rgep30, align 8, !alias.scope !9, !noalias !10
  %v31 = load i64, ptr %slot2, align 8
  %v32 = load i64, ptr %slot3, align 8
  %p33 = inttoptr i64 %v32 to ptr
  store i64 %v31, ptr %p33, align 8, !alias.scope !4, !noalias !3
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
