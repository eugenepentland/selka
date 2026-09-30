target triple = "x86_64-unknown-linux-gnu"

define dllexport i64 @owner(i64 %p_ctx, i64 %p_slot) {
bb_start:
  %slot1 = alloca i64, align 8
  %slot2 = alloca i64, align 8
  %slot3 = alloca i64, align 8
  %slot4 = alloca i64, align 8
  %slot5 = alloca i32, align 8
  %slot6 = alloca i64, align 8
  %slot7 = alloca i64, align 8
  %slot8 = alloca i64, align 8
  %slot9 = alloca i32, align 8
  %slot10 = alloca i64, align 8
  %slot11 = alloca i64, align 8
  %slot12 = alloca i64, align 8
  %slot13 = alloca i32, align 8
  %slot14 = alloca i64, align 8
  %slot15 = alloca i64, align 8
  %slot16 = alloca i32, align 8
  store i64 %p_ctx, ptr %slot1, align 8
  store i64 %p_slot, ptr %slot2, align 8
  %v17 = load i64, ptr %slot1, align 8
  store i64 %v17, ptr %slot3, align 8
  %v18 = load i64, ptr %slot2, align 8
  %p19 = inttoptr i64 %v18 to ptr
  %ld20 = load i64, ptr %p19, align 8, !alias.scope !4, !noalias !3
  store i64 %ld20, ptr %slot4, align 8
  %v21 = load i64, ptr %slot4, align 8
  %cmp22 = icmp ne i64 %v21, 0
  %cv23 = zext i1 %cmp22 to i32
  store i32 %cv23, ptr %slot5, align 8
  %v24 = load i32, ptr %slot5, align 8
  %cv25 = zext i32 %v24 to i64
  %cond26 = icmp ne i64 %cv25, 0
  br i1 %cond26, label %bb_rcgnn115, label %bb_rcgdone115
bb_rcgnn115:
  %v27 = load i64, ptr %slot4, align 8
  %op28 = sub i64 %v27, 16
  store i64 %op28, ptr %slot6, align 8
  %v29 = load i64, ptr %slot4, align 8
  %p30 = inttoptr i64 %v29 to ptr
  %rgep31 = getelementptr i8, ptr %p30, i64 -16
  %ld32 = load i64, ptr %rgep31, align 8, !alias.scope !9, !noalias !10
  store i64 %ld32, ptr %slot7, align 8
  %v33 = load i64, ptr %slot7, align 8
  %op34 = and i64 %v33, 4611686018427387906
  store i64 %op34, ptr %slot8, align 8
  %v35 = load i64, ptr %slot8, align 8
  %cmp36 = icmp ne i64 %v35, 0
  %cv37 = zext i1 %cmp36 to i32
  store i32 %cv37, ptr %slot9, align 8
  %v38 = load i32, ptr %slot9, align 8
  %cv39 = zext i32 %v38 to i64
  %cond40 = icmp ne i64 %cv39, 0
  br i1 %cond40, label %bb_rcgclear115, label %bb_rcgcounted115
bb_rcgcounted115:
  %v41 = load i64, ptr %slot4, align 8
  %op42 = sub i64 %v41, 32
  store i64 %op42, ptr %slot10, align 8
  %v43 = load i64, ptr %slot4, align 8
  %p44 = inttoptr i64 %v43 to ptr
  %rgep45 = getelementptr i8, ptr %p44, i64 -32
  %ld46 = load i64, ptr %rgep45, align 8, !alias.scope !9, !noalias !10
  store i64 %ld46, ptr %slot11, align 8
  %v47 = load i64, ptr %slot11, align 8
  %op48 = sub i64 %v47, 1
  store i64 %op48, ptr %slot12, align 8
  %v49 = load i64, ptr %slot12, align 8
  %cmp50 = icmp eq i64 %v49, 0
  %cv51 = zext i1 %cmp50 to i32
  store i32 %cv51, ptr %slot13, align 8
  %v52 = load i32, ptr %slot13, align 8
  %cv53 = zext i32 %v52 to i64
  %cond54 = icmp ne i64 %cv53, 0
  br i1 %cond54, label %bb_rcglast115, label %bb_rcgdec115
bb_rcglast115:
  %v55 = load i64, ptr %slot4, align 8
  %op56 = sub i64 %v55, 24
  store i64 %op56, ptr %slot14, align 8
  %v57 = load i64, ptr %slot4, align 8
  %p58 = inttoptr i64 %v57 to ptr
  %rgep59 = getelementptr i8, ptr %p58, i64 -24
  %ld60 = load i64, ptr %rgep59, align 8, !alias.scope !9, !noalias !10
  store i64 %ld60, ptr %slot15, align 8
  %v61 = load i64, ptr %slot15, align 8
  %cmp62 = icmp ne i64 %v61, 0
  %cv63 = zext i1 %cmp62 to i32
  store i32 %cv63, ptr %slot16, align 8
  %v64 = load i32, ptr %slot16, align 8
  %cv65 = zext i32 %v64 to i64
  %cond66 = icmp ne i64 %cv65, 0
  br i1 %cond66, label %bb_rcgdec115, label %bb_rcgslow115
bb_rcgslow115:
  %v67 = load i64, ptr %slot3, align 8
  %v68 = load i64, ptr %slot2, align 8
  call void @boundary_drop(i64 %v67, i64 %v68)
  br label %bb_rcgdone115
bb_rcgdec115:
  %v69 = load i64, ptr %slot12, align 8
  %v70 = load i64, ptr %slot4, align 8
  %p71 = inttoptr i64 %v70 to ptr
  %rgep72 = getelementptr i8, ptr %p71, i64 -32
  store i64 %v69, ptr %rgep72, align 8, !alias.scope !9, !noalias !10
  br label %bb_rcgclear115
bb_rcgclear115:
  %v73 = load i64, ptr %slot2, align 8
  %p74 = inttoptr i64 %v73 to ptr
  store i64 0, ptr %p74, align 8, !alias.scope !4, !noalias !3
  br label %bb_rcgdone115
bb_rcgdone115:
  ret i64 0
}

declare void @boundary_drop(i64, i64)

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
