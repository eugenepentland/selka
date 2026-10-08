target triple = "x86_64-unknown-linux-gnu"

define dllexport i64 @slot_4_default(i64 %p_count, i64 %p_seed) {
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
  store i64 %p_count, ptr %slot1, align 8
  store i64 %p_seed, ptr %slot2, align 8
  %mem10 = alloca i8, i64 8, align 8
  %mem12 = alloca i8, i64 8, align 16
  %v14 = load i64, ptr %slot2, align 8
  store i64 %v14, ptr %mem10, align 8, !alias.scope !3, !noalias !4
  %v15 = load i64, ptr %slot1, align 8
  store i64 %v15, ptr %mem12, align 8, !alias.scope !3, !noalias !4
  %ld16 = load i64, ptr %mem10, align 8, !alias.scope !3, !noalias !4
  store i64 %ld16, ptr %slot5, align 8
  %v17 = load i64, ptr %slot5, align 8
  %op18 = add i64 %v17, 1
  store i64 %op18, ptr %slot6, align 8
  %v19 = load i64, ptr %slot6, align 8
  store i64 %v19, ptr %mem10, align 8, !alias.scope !3, !noalias !4
  %ld20 = load i64, ptr %mem10, align 8, !alias.scope !3, !noalias !4
  store i64 %ld20, ptr %slot7, align 8
  %ld21 = load i64, ptr %mem12, align 8, !alias.scope !3, !noalias !4
  store i64 %ld21, ptr %slot8, align 8
  %v22 = load i64, ptr %slot7, align 8
  %v23 = load i64, ptr %slot8, align 8
  %op24 = add i64 %v22, %v23
  store i64 %op24, ptr %slot9, align 8
  %v25 = load i64, ptr %slot9, align 8
  ret i64 %v25
}

!0 = distinct !{!0, !"mylang memory classes"}
!1 = distinct !{!1, !0, !"frame"}
!2 = distinct !{!2, !0, !"foreign"}
!3 = !{!1}
!4 = !{!2}
!5 = distinct !{!5, !0, !"object"}
!6 = !{!5}
!7 = !{!1}
