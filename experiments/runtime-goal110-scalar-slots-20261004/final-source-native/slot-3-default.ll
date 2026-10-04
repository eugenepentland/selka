target triple = "x86_64-unknown-linux-gnu"

define dllexport i64 @slot_3_default(i64 %p_count, i64 %p_seed) {
bb_start:
  %slot1 = alloca i64, align 8
  %slot2 = alloca i64, align 8
  %slot3 = alloca i64, align 8
  %slot4 = alloca i64, align 8
  %slot5 = alloca i64, align 8
  %slot6 = alloca i64, align 8
  store i64 %p_count, ptr %slot1, align 8
  store i64 %p_seed, ptr %slot2, align 8
  %mem7 = alloca i8, i64 8, align 8
  %ptr8 = ptrtoint ptr %mem7 to i64
  store i64 %ptr8, ptr %slot3, align 8
  %v9 = load i64, ptr %slot3, align 8
  %p11 = inttoptr i64 %v9 to ptr
  %gep12 = getelementptr i8, ptr %p11, i64 0
  %op10 = ptrtoint ptr %gep12 to i64
  store i64 %op10, ptr %slot4, align 8
  %v13 = load i64, ptr %slot2, align 8
  %op14 = add i64 %v13, 99
  store i64 %op14, ptr %slot5, align 8
  %v15 = load i64, ptr %slot5, align 8
  %v16 = load i64, ptr %slot4, align 8
  %p17 = inttoptr i64 %v16 to ptr
  store i64 %v15, ptr %p17, align 8, !alias.scope !3, !noalias !4
  %v18 = load i64, ptr %slot3, align 8
  %p19 = inttoptr i64 %v18 to ptr
  %ld20 = load i64, ptr %p19, align 8, !alias.scope !3, !noalias !4
  store i64 %ld20, ptr %slot6, align 8
  %v21 = load i64, ptr %slot6, align 8
  ret i64 %v21
}

!0 = distinct !{!0, !"mylang memory classes"}
!1 = distinct !{!1, !0, !"frame"}
!2 = distinct !{!2, !0, !"foreign"}
!3 = !{!1}
!4 = !{!2}
!5 = distinct !{!5, !0, !"object"}
!6 = !{!5}
!7 = !{!1}
