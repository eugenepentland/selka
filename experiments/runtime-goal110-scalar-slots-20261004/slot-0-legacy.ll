target triple = "x86_64-unknown-linux-gnu"

define dllexport i64 @slot_0_legacy(i64 %p_count, i64 %p_seed) {
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
  %ptr12 = ptrtoint ptr %mem11 to i64
  store i64 %ptr12, ptr %slot3, align 8
  %mem13 = alloca i8, i64 8, align 8
  %ptr14 = ptrtoint ptr %mem13 to i64
  store i64 %ptr14, ptr %slot4, align 8
  %v15 = load i64, ptr %slot2, align 8
  %v16 = load i64, ptr %slot3, align 8
  %p17 = inttoptr i64 %v16 to ptr
  store i64 %v15, ptr %p17, align 8, !alias.scope !3, !noalias !4
  %v18 = load i64, ptr %slot4, align 8
  %p19 = inttoptr i64 %v18 to ptr
  store i64 0, ptr %p19, align 8, !alias.scope !3, !noalias !4
  br label %bb_condition
bb_condition:
  %v20 = load i64, ptr %slot4, align 8
  %p21 = inttoptr i64 %v20 to ptr
  %ld22 = load i64, ptr %p21, align 8, !alias.scope !3, !noalias !4
  store i64 %ld22, ptr %slot5, align 8
  %v23 = load i64, ptr %slot5, align 8
  %v24 = load i64, ptr %slot1, align 8
  %cmp25 = icmp slt i64 %v23, %v24
  %cv26 = zext i1 %cmp25 to i64
  store i64 %cv26, ptr %slot6, align 8
  %v27 = load i64, ptr %slot6, align 8
  %cond28 = icmp ne i64 %v27, 0
  br i1 %cond28, label %bb_loop, label %bb_done
bb_loop:
  %v29 = load i64, ptr %slot3, align 8
  %p30 = inttoptr i64 %v29 to ptr
  %ld31 = load i64, ptr %p30, align 8, !alias.scope !3, !noalias !4
  store i64 %ld31, ptr %slot7, align 8
  %v32 = load i64, ptr %slot7, align 8
  %v33 = load i64, ptr %slot5, align 8
  %op34 = add i64 %v32, %v33
  store i64 %op34, ptr %slot8, align 8
  %v35 = load i64, ptr %slot8, align 8
  %v36 = load i64, ptr %slot3, align 8
  %p37 = inttoptr i64 %v36 to ptr
  store i64 %v35, ptr %p37, align 8, !alias.scope !3, !noalias !4
  %v38 = load i64, ptr %slot5, align 8
  %op39 = add i64 %v38, 1
  store i64 %op39, ptr %slot9, align 8
  %v40 = load i64, ptr %slot9, align 8
  %v41 = load i64, ptr %slot4, align 8
  %p42 = inttoptr i64 %v41 to ptr
  store i64 %v40, ptr %p42, align 8, !alias.scope !3, !noalias !4
  br label %bb_condition
bb_done:
  %v43 = load i64, ptr %slot3, align 8
  %p44 = inttoptr i64 %v43 to ptr
  %ld45 = load i64, ptr %p44, align 8, !alias.scope !3, !noalias !4
  store i64 %ld45, ptr %slot10, align 8
  %v46 = load i64, ptr %slot10, align 8
  ret i64 %v46
}

!0 = distinct !{!0, !"mylang memory classes"}
!1 = distinct !{!1, !0, !"frame"}
!2 = distinct !{!2, !0, !"foreign"}
!3 = !{!1}
!4 = !{!2}
!5 = distinct !{!5, !0, !"object"}
!6 = !{!5}
!7 = !{!1}
