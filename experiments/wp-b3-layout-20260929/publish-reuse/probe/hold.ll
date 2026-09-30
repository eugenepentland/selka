target triple = "x86_64-unknown-linux-gnu"

define dllexport i32 @review_hold(i64 %p_ctx, i64 %p_heap, i64 %p_slot) {
bb_start:
  %slot1 = alloca i64, align 8
  %slot2 = alloca i64, align 8
  %slot3 = alloca i64, align 8
  %slot4 = alloca i64, align 8
  %slot5 = alloca i64, align 8
  %slot6 = alloca i32, align 8
  %slot7 = alloca i64, align 8
  %slot8 = alloca i64, align 8
  %slot9 = alloca i64, align 8
  %slot10 = alloca i32, align 8
  %slot11 = alloca i64, align 8
  %slot12 = alloca i64, align 8
  %slot13 = alloca i64, align 8
  %slot14 = alloca i32, align 8
  %slot15 = alloca i64, align 8
  %slot16 = alloca i64, align 8
  %slot17 = alloca i32, align 8
  store i64 %p_ctx, ptr %slot1, align 8
  store i64 %p_heap, ptr %slot2, align 8
  store i64 %p_slot, ptr %slot3, align 8
  %v18 = load i64, ptr %slot2, align 8
  store i64 %v18, ptr %slot4, align 8
  %v19 = load i64, ptr %slot3, align 8
  %p20 = inttoptr i64 %v19 to ptr
  %ld21 = load i64, ptr %p20, align 8, !alias.scope !4, !noalias !3
  store i64 %ld21, ptr %slot5, align 8
  %v22 = load i64, ptr %slot5, align 8
  %cmp23 = icmp ne i64 %v22, 0
  %cv24 = zext i1 %cmp23 to i32
  store i32 %cv24, ptr %slot6, align 8
  %v25 = load i32, ptr %slot6, align 8
  %cv26 = zext i32 %v25 to i64
  %cond27 = icmp ne i64 %cv26, 0
  br i1 %cond27, label %bb_rcgnn95, label %bb_rcgdone95
bb_rcgnn95:
  %v28 = load i64, ptr %slot5, align 8
  %op29 = sub i64 %v28, 16
  store i64 %op29, ptr %slot7, align 8
  %v30 = load i64, ptr %slot5, align 8
  %p31 = inttoptr i64 %v30 to ptr
  %rgep32 = getelementptr i8, ptr %p31, i64 -16
  %ld33 = load i64, ptr %rgep32, align 8, !alias.scope !9, !noalias !10
  store i64 %ld33, ptr %slot8, align 8
  %v34 = load i64, ptr %slot8, align 8
  %op35 = and i64 %v34, 4611686018427387906
  store i64 %op35, ptr %slot9, align 8
  %v36 = load i64, ptr %slot9, align 8
  %cmp37 = icmp ne i64 %v36, 0
  %cv38 = zext i1 %cmp37 to i32
  store i32 %cv38, ptr %slot10, align 8
  %v39 = load i32, ptr %slot10, align 8
  %cv40 = zext i32 %v39 to i64
  %cond41 = icmp ne i64 %cv40, 0
  br i1 %cond41, label %bb_rcgclear95, label %bb_rcgcounted95
bb_rcgcounted95:
  %v42 = load i64, ptr %slot5, align 8
  %op43 = sub i64 %v42, 24
  store i64 %op43, ptr %slot11, align 8
  %v44 = load i64, ptr %slot5, align 8
  %p45 = inttoptr i64 %v44 to ptr
  %rgep46 = getelementptr i8, ptr %p45, i64 -24
  %ld47 = load i64, ptr %rgep46, align 8, !alias.scope !9, !noalias !10
  store i64 %ld47, ptr %slot12, align 8
  %v48 = load i64, ptr %slot12, align 8
  %op49 = sub i64 %v48, 1
  store i64 %op49, ptr %slot13, align 8
  %v50 = load i64, ptr %slot13, align 8
  %cmp51 = icmp eq i64 %v50, 0
  %cv52 = zext i1 %cmp51 to i32
  store i32 %cv52, ptr %slot14, align 8
  %v53 = load i32, ptr %slot14, align 8
  %cv54 = zext i32 %v53 to i64
  %cond55 = icmp ne i64 %cv54, 0
  br i1 %cond55, label %bb_rcglast95, label %bb_rcgdec95
bb_rcglast95:
  %v56 = load i64, ptr %slot5, align 8
  %op57 = sub i64 %v56, 32
  store i64 %op57, ptr %slot15, align 8
  %v58 = load i64, ptr %slot5, align 8
  %p59 = inttoptr i64 %v58 to ptr
  %rgep60 = getelementptr i8, ptr %p59, i64 -32
  %ld61 = load i64, ptr %rgep60, align 8, !alias.scope !9, !noalias !10
  store i64 %ld61, ptr %slot16, align 8
  %v62 = load i64, ptr %slot16, align 8
  %cmp63 = icmp ne i64 %v62, 0
  %cv64 = zext i1 %cmp63 to i32
  store i32 %cv64, ptr %slot17, align 8
  %v65 = load i32, ptr %slot17, align 8
  %cv66 = zext i32 %v65 to i64
  %cond67 = icmp ne i64 %cv66, 0
  br i1 %cond67, label %bb_rcgdec95, label %bb_rcgslow95
bb_rcgslow95:
  %v68 = load i64, ptr %slot4, align 8
  %v69 = load i64, ptr %slot3, align 8
  call void @myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan(i64 %v68, i64 %v69)
  br label %bb_rcgdone95
bb_rcgdec95:
  %v70 = load i64, ptr %slot13, align 8
  %v71 = load i64, ptr %slot5, align 8
  %p72 = inttoptr i64 %v71 to ptr
  %rgep73 = getelementptr i8, ptr %p72, i64 -24
  store i64 %v70, ptr %rgep73, align 8, !alias.scope !9, !noalias !10
  br label %bb_rcgclear95
bb_rcgclear95:
  %v74 = load i64, ptr %slot3, align 8
  %p75 = inttoptr i64 %v74 to ptr
  store i64 0, ptr %p75, align 8, !alias.scope !4, !noalias !3
  br label %bb_rcgdone95
bb_rcgdone95:
  ret i32 1
}

declare void @myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan(i64, i64)

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
