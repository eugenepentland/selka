target triple = "x86_64-unknown-linux-gnu"

define dllexport i64 @slot_1_legacy(i64 %p_count, i64 %p_seed) {
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
  %slot11 = alloca i64, align 8
  %slot12 = alloca i64, align 8
  store i64 %p_count, ptr %slot1, align 8
  store i64 %p_seed, ptr %slot2, align 8
  %mem13 = alloca i8, i64 8, align 8
  %ptr14 = ptrtoint ptr %mem13 to i64
  store i64 %ptr14, ptr %slot3, align 8
  %mem15 = alloca i8, i64 8, align 8
  %ptr16 = ptrtoint ptr %mem15 to i64
  store i64 %ptr16, ptr %slot4, align 8
  %v17 = load i64, ptr %slot2, align 8
  %v18 = load i64, ptr %slot3, align 8
  %p19 = inttoptr i64 %v18 to ptr
  store i64 %v17, ptr %p19, align 8, !alias.scope !3, !noalias !4
  %v20 = load i64, ptr %slot4, align 8
  %p21 = inttoptr i64 %v20 to ptr
  store i64 0, ptr %p21, align 8, !alias.scope !3, !noalias !4
  br label %bb_condition
bb_condition:
  %v22 = load i64, ptr %slot4, align 8
  %p23 = inttoptr i64 %v22 to ptr
  %ld24 = load i64, ptr %p23, align 8, !alias.scope !3, !noalias !4
  store i64 %ld24, ptr %slot5, align 8
  %v25 = load i64, ptr %slot5, align 8
  %v26 = load i64, ptr %slot1, align 8
  %cmp27 = icmp slt i64 %v25, %v26
  %cv28 = zext i1 %cmp27 to i64
  store i64 %cv28, ptr %slot6, align 8
  %v29 = load i64, ptr %slot6, align 8
  %cond30 = icmp ne i64 %v29, 0
  br i1 %cond30, label %bb_loop, label %bb_done
bb_loop:
  %mem31 = alloca i8, i64 8, align 8
  %ptr32 = ptrtoint ptr %mem31 to i64
  store i64 %ptr32, ptr %slot7, align 8
  %v33 = load i64, ptr %slot3, align 8
  %p34 = inttoptr i64 %v33 to ptr
  %ld35 = load i64, ptr %p34, align 8, !alias.scope !3, !noalias !4
  store i64 %ld35, ptr %slot8, align 8
  %v36 = load i64, ptr %slot8, align 8
  %v37 = load i64, ptr %slot5, align 8
  %op38 = add i64 %v36, %v37
  store i64 %op38, ptr %slot9, align 8
  %v39 = load i64, ptr %slot9, align 8
  %v40 = load i64, ptr %slot7, align 8
  %p41 = inttoptr i64 %v40 to ptr
  store i64 %v39, ptr %p41, align 8, !alias.scope !3, !noalias !4
  %v42 = load i64, ptr %slot7, align 8
  %p43 = inttoptr i64 %v42 to ptr
  %ld44 = load i64, ptr %p43, align 8, !alias.scope !3, !noalias !4
  store i64 %ld44, ptr %slot10, align 8
  %v45 = load i64, ptr %slot10, align 8
  %v46 = load i64, ptr %slot3, align 8
  %p47 = inttoptr i64 %v46 to ptr
  store i64 %v45, ptr %p47, align 8, !alias.scope !3, !noalias !4
  %v48 = load i64, ptr %slot5, align 8
  %op49 = add i64 %v48, 1
  store i64 %op49, ptr %slot11, align 8
  %v50 = load i64, ptr %slot11, align 8
  %v51 = load i64, ptr %slot4, align 8
  %p52 = inttoptr i64 %v51 to ptr
  store i64 %v50, ptr %p52, align 8, !alias.scope !3, !noalias !4
  br label %bb_condition
bb_done:
  %v53 = load i64, ptr %slot3, align 8
  %p54 = inttoptr i64 %v53 to ptr
  %ld55 = load i64, ptr %p54, align 8, !alias.scope !3, !noalias !4
  store i64 %ld55, ptr %slot12, align 8
  %v56 = load i64, ptr %slot12, align 8
  ret i64 %v56
}

!0 = distinct !{!0, !"mylang memory classes"}
!1 = distinct !{!1, !0, !"frame"}
!2 = distinct !{!2, !0, !"foreign"}
!3 = !{!1}
!4 = !{!2}
!5 = distinct !{!5, !0, !"object"}
!6 = !{!5}
!7 = !{!1}
