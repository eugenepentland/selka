target triple = "x86_64-unknown-linux-gnu"

define dllexport i64 @slot_2_legacy(i64 %p_count, i64 %p_seed) {
bb_start:
  %slot1 = alloca i64, align 8
  %slot2 = alloca i64, align 8
  %slot3 = alloca i64, align 8
  %slot4 = alloca i64, align 8
  store i64 %p_count, ptr %slot1, align 8
  store i64 %p_seed, ptr %slot2, align 8
  %mem5 = alloca i8, i64 8, align 8
  %ptr6 = ptrtoint ptr %mem5 to i64
  store i64 %ptr6, ptr %slot3, align 8
  %v7 = load i64, ptr %slot2, align 8
  %v8 = load i64, ptr %slot3, align 8
  %p9 = inttoptr i64 %v8 to ptr
  store i64 %v7, ptr %p9, align 8, !alias.scope !3, !noalias !4
  %v10 = load i64, ptr %slot3, align 8
  %v11 = load i64, ptr %slot2, align 8
  call void @poke(i64 %v10, i64 %v11)
  %v12 = load i64, ptr %slot3, align 8
  %p13 = inttoptr i64 %v12 to ptr
  %ld14 = load i64, ptr %p13, align 8, !alias.scope !3, !noalias !4
  store i64 %ld14, ptr %slot4, align 8
  %v15 = load i64, ptr %slot4, align 8
  ret i64 %v15
}

declare void @poke(i64, i64)

!0 = distinct !{!0, !"mylang memory classes"}
!1 = distinct !{!1, !0, !"frame"}
!2 = distinct !{!2, !0, !"foreign"}
!3 = !{!1}
!4 = !{!2}
!5 = distinct !{!5, !0, !"object"}
!6 = !{!5}
!7 = !{!1}
