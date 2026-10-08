target triple = "x86_64-unknown-linux-gnu"

define dllexport i64 @slot_1_default(i64 %p_count, i64 %p_seed) {
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
  %mem15 = alloca i8, i64 8, align 8
  %v17 = load i64, ptr %slot2, align 8
  store i64 %v17, ptr %mem13, align 8, !alias.scope !3, !noalias !4
  store i64 0, ptr %mem15, align 8, !alias.scope !3, !noalias !4
  br label %bb_condition
bb_condition:
  %ld18 = load i64, ptr %mem15, align 8, !alias.scope !3, !noalias !4
  store i64 %ld18, ptr %slot5, align 8
  %v19 = load i64, ptr %slot5, align 8
  %v20 = load i64, ptr %slot1, align 8
  %cmp21 = icmp slt i64 %v19, %v20
  %cv22 = zext i1 %cmp21 to i64
  store i64 %cv22, ptr %slot6, align 8
  %v23 = load i64, ptr %slot6, align 8
  %cond24 = icmp ne i64 %v23, 0
  br i1 %cond24, label %bb_loop, label %bb_done
bb_loop:
  %mem25 = alloca i8, i64 8, align 8
  %ptr26 = ptrtoint ptr %mem25 to i64
  store i64 %ptr26, ptr %slot7, align 8
  %ld27 = load i64, ptr %mem13, align 8, !alias.scope !3, !noalias !4
  store i64 %ld27, ptr %slot8, align 8
  %v28 = load i64, ptr %slot8, align 8
  %v29 = load i64, ptr %slot5, align 8
  %op30 = add i64 %v28, %v29
  store i64 %op30, ptr %slot9, align 8
  %v31 = load i64, ptr %slot9, align 8
  %v32 = load i64, ptr %slot7, align 8
  %p33 = inttoptr i64 %v32 to ptr
  store i64 %v31, ptr %p33, align 8, !alias.scope !3, !noalias !4
  %v34 = load i64, ptr %slot7, align 8
  %p35 = inttoptr i64 %v34 to ptr
  %ld36 = load i64, ptr %p35, align 8, !alias.scope !3, !noalias !4
  store i64 %ld36, ptr %slot10, align 8
  %v37 = load i64, ptr %slot10, align 8
  store i64 %v37, ptr %mem13, align 8, !alias.scope !3, !noalias !4
  %v38 = load i64, ptr %slot5, align 8
  %op39 = add i64 %v38, 1
  store i64 %op39, ptr %slot11, align 8
  %v40 = load i64, ptr %slot11, align 8
  store i64 %v40, ptr %mem15, align 8, !alias.scope !3, !noalias !4
  br label %bb_condition
bb_done:
  %ld41 = load i64, ptr %mem13, align 8, !alias.scope !3, !noalias !4
  store i64 %ld41, ptr %slot12, align 8
  %v42 = load i64, ptr %slot12, align 8
  ret i64 %v42
}

!0 = distinct !{!0, !"mylang memory classes"}
!1 = distinct !{!1, !0, !"frame"}
!2 = distinct !{!2, !0, !"foreign"}
!3 = !{!1}
!4 = !{!2}
!5 = distinct !{!5, !0, !"object"}
!6 = !{!5}
!7 = !{!1}
