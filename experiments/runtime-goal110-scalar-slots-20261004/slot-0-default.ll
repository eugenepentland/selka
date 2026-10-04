target triple = "x86_64-unknown-linux-gnu"

define dllexport i64 @slot_0_default(i64 %p_count, i64 %p_seed) {
bb_start:
  %slot1 = alloca i64, align 8
  %slot2 = alloca i64, align 8
  %slot3 = alloca i64, align 8
  %slot4 = alloca i64, align 8
  %slot5 = alloca i64, align 8
  %slot6 = alloca i64, align 8
  %slot7 = alloca i64, align 8
  %slot8 = alloca i64, align 8
  %slot9 = alloca i64, align 8
  %slot10 = alloca i64, align 8
  store i64 %p_count, ptr %slot1, align 8
  store i64 %p_seed, ptr %slot2, align 8
  %mem11 = alloca i8, i64 8, align 8
  %mem13 = alloca i8, i64 8, align 8
  %v15 = load i64, ptr %slot2, align 8
  store i64 %v15, ptr %mem11, align 8, !alias.scope !3, !noalias !4
  store i64 0, ptr %mem13, align 8, !alias.scope !3, !noalias !4
  br label %bb_condition
bb_condition:
  %ld16 = load i64, ptr %mem13, align 8, !alias.scope !3, !noalias !4
  store i64 %ld16, ptr %slot5, align 8
  %v17 = load i64, ptr %slot5, align 8
  %v18 = load i64, ptr %slot1, align 8
  %cmp19 = icmp slt i64 %v17, %v18
  %cv20 = zext i1 %cmp19 to i64
  store i64 %cv20, ptr %slot6, align 8
  %v21 = load i64, ptr %slot6, align 8
  %cond22 = icmp ne i64 %v21, 0
  br i1 %cond22, label %bb_loop, label %bb_done
bb_loop:
  %ld23 = load i64, ptr %mem11, align 8, !alias.scope !3, !noalias !4
  store i64 %ld23, ptr %slot7, align 8
  %v24 = load i64, ptr %slot7, align 8
  %v25 = load i64, ptr %slot5, align 8
  %op26 = add i64 %v24, %v25
  store i64 %op26, ptr %slot8, align 8
  %v27 = load i64, ptr %slot8, align 8
  store i64 %v27, ptr %mem11, align 8, !alias.scope !3, !noalias !4
  %v28 = load i64, ptr %slot5, align 8
  %op29 = add i64 %v28, 1
  store i64 %op29, ptr %slot9, align 8
  %v30 = load i64, ptr %slot9, align 8
  store i64 %v30, ptr %mem13, align 8, !alias.scope !3, !noalias !4
  br label %bb_condition
bb_done:
  %ld31 = load i64, ptr %mem11, align 8, !alias.scope !3, !noalias !4
  store i64 %ld31, ptr %slot10, align 8
  %v32 = load i64, ptr %slot10, align 8
  ret i64 %v32
}

!0 = distinct !{!0, !"mylang memory classes"}
!1 = distinct !{!1, !0, !"frame"}
!2 = distinct !{!2, !0, !"foreign"}
!3 = !{!1}
!4 = !{!2}
!5 = distinct !{!5, !0, !"object"}
!6 = !{!5}
!7 = !{!1}
