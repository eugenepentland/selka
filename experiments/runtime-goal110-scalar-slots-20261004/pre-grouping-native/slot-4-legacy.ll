target triple = "x86_64-unknown-linux-gnu"

define dllexport i64 @slot_4_legacy(i64 %p_count, i64 %p_seed) {
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
  %ptr11 = ptrtoint ptr %mem10 to i64
  store i64 %ptr11, ptr %slot3, align 8
  %mem12 = alloca i8, i64 8, align 16
  %ptr13 = ptrtoint ptr %mem12 to i64
  store i64 %ptr13, ptr %slot4, align 8
  %v14 = load i64, ptr %slot2, align 8
  %v15 = load i64, ptr %slot3, align 8
  %p16 = inttoptr i64 %v15 to ptr
  store i64 %v14, ptr %p16, align 8, !alias.scope !3, !noalias !4
  %v17 = load i64, ptr %slot1, align 8
  %v18 = load i64, ptr %slot4, align 8
  %p19 = inttoptr i64 %v18 to ptr
  store i64 %v17, ptr %p19, align 8, !alias.scope !3, !noalias !4
  %v20 = load i64, ptr %slot3, align 8
  %p21 = inttoptr i64 %v20 to ptr
  %ld22 = load i64, ptr %p21, align 8, !alias.scope !3, !noalias !4
  store i64 %ld22, ptr %slot5, align 8
  %v23 = load i64, ptr %slot5, align 8
  %op24 = add i64 %v23, 1
  store i64 %op24, ptr %slot6, align 8
  %v25 = load i64, ptr %slot6, align 8
  %v26 = load i64, ptr %slot3, align 8
  %p27 = inttoptr i64 %v26 to ptr
  store i64 %v25, ptr %p27, align 8, !alias.scope !3, !noalias !4
  %v28 = load i64, ptr %slot3, align 8
  %p29 = inttoptr i64 %v28 to ptr
  %ld30 = load i64, ptr %p29, align 8, !alias.scope !3, !noalias !4
  store i64 %ld30, ptr %slot7, align 8
  %v31 = load i64, ptr %slot4, align 8
  %p32 = inttoptr i64 %v31 to ptr
  %ld33 = load i64, ptr %p32, align 8, !alias.scope !3, !noalias !4
  store i64 %ld33, ptr %slot8, align 8
  %v34 = load i64, ptr %slot7, align 8
  %v35 = load i64, ptr %slot8, align 8
  %op36 = add i64 %v34, %v35
  store i64 %op36, ptr %slot9, align 8
  %v37 = load i64, ptr %slot9, align 8
  ret i64 %v37
}

!0 = distinct !{!0, !"mylang memory classes"}
!1 = distinct !{!1, !0, !"frame"}
!2 = distinct !{!2, !0, !"foreign"}
!3 = !{!1}
!4 = !{!2}
!5 = distinct !{!5, !0, !"object"}
!6 = !{!5}
!7 = !{!1}
