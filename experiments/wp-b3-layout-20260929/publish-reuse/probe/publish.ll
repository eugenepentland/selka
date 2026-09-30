target triple = "x86_64-unknown-linux-gnu"

define dllexport i32 @review_publish(i64 %p_ctx, i64 %p_heap, i64 %p_dst, i64 %p_src, i32 %p_region, i32 %p_mode) {
bb_start:
  %slot1 = alloca i64, align 8
  %slot2 = alloca i64, align 8
  %slot3 = alloca i64, align 8
  %slot4 = alloca i64, align 8
  %slot5 = alloca i32, align 8
  %slot6 = alloca i32, align 8
  %slot7 = alloca i32, align 8
  %slot8 = alloca i64, align 8
  %slot9 = alloca i32, align 8
  %slot10 = alloca i64, align 8
  %slot11 = alloca i64, align 8
  %slot12 = alloca i64, align 8
  %slot13 = alloca i32, align 8
  %slot14 = alloca i32, align 8
  %slot15 = alloca i64, align 8
  %slot16 = alloca i32, align 8
  %slot17 = alloca i64, align 8
  %slot18 = alloca i64, align 8
  %slot19 = alloca i64, align 8
  %slot20 = alloca i32, align 8
  %slot21 = alloca i64, align 8
  %slot22 = alloca i32, align 8
  %slot23 = alloca i64, align 8
  %slot24 = alloca i32, align 8
  %slot25 = alloca i32, align 8
  %slot26 = alloca i32, align 8
  %slot27 = alloca i32, align 8
  store i64 %p_ctx, ptr %slot1, align 8
  store i64 %p_heap, ptr %slot2, align 8
  store i64 %p_dst, ptr %slot3, align 8
  store i64 %p_src, ptr %slot4, align 8
  store i32 %p_region, ptr %slot5, align 8
  store i32 %p_mode, ptr %slot6, align 8
  %v28 = load i32, ptr %slot6, align 8
  %op29 = and i32 %v28, 3
  store i32 %op29, ptr %slot7, align 8
  %v30 = load i32, ptr %slot7, align 8
  %cv31 = zext i32 %v30 to i64
  %cond32 = icmp ne i64 %cv31, 0
  br i1 %cond32, label %bb_rcgpublishslow53, label %bb_rcgpublishmode53
bb_rcgpublishmode53:
  %v33 = load i64, ptr %slot4, align 8
  %p34 = inttoptr i64 %v33 to ptr
  %ld35 = load i64, ptr %p34, align 8, !alias.scope !4, !noalias !3
  store i64 %ld35, ptr %slot8, align 8
  %v36 = load i64, ptr %slot8, align 8
  %cmp37 = icmp ne i64 %v36, 0
  %cv38 = zext i1 %cmp37 to i32
  store i32 %cv38, ptr %slot9, align 8
  %v39 = load i32, ptr %slot9, align 8
  %cv40 = zext i32 %v39 to i64
  %cond41 = icmp ne i64 %cv40, 0
  br i1 %cond41, label %bb_rcgpublishnn53, label %bb_rcgpublishstore53
bb_rcgpublishnn53:
  %v42 = load i64, ptr %slot8, align 8
  %op43 = sub i64 %v42, 16
  store i64 %op43, ptr %slot10, align 8
  %v44 = load i64, ptr %slot8, align 8
  %p45 = inttoptr i64 %v44 to ptr
  %rgep46 = getelementptr i8, ptr %p45, i64 -16
  %ld47 = load i64, ptr %rgep46, align 8, !alias.scope !9, !noalias !10
  store i64 %ld47, ptr %slot11, align 8
  %v48 = load i64, ptr %slot11, align 8
  %op49 = and i64 %v48, 5764607523034234880
  store i64 %op49, ptr %slot12, align 8
  %v50 = load i64, ptr %slot12, align 8
  %cmp51 = icmp ne i64 %v50, 0
  %cv52 = zext i1 %cmp51 to i32
  store i32 %cv52, ptr %slot13, align 8
  %v53 = load i32, ptr %slot13, align 8
  %cv54 = zext i32 %v53 to i64
  %cond55 = icmp ne i64 %cv54, 0
  br i1 %cond55, label %bb_rcgpublishslow53, label %bb_rcgpublishshare53
bb_rcgpublishshare53:
  %v56 = load i32, ptr %slot6, align 8
  %op57 = and i32 %v56, 4
  store i32 %op57, ptr %slot14, align 8
  %v58 = load i64, ptr %slot11, align 8
  %op59 = and i64 %v58, 2
  store i64 %op59, ptr %slot15, align 8
  %v60 = load i32, ptr %slot14, align 8
  %cv61 = zext i32 %v60 to i64
  %cond62 = icmp ne i64 %cv61, 0
  br i1 %cond62, label %bb_rcgpublishmarkcheck53, label %bb_rcgpublishordinary53
bb_rcgpublishordinary53:
  %v63 = load i64, ptr %slot15, align 8
  %cmp64 = icmp ne i64 %v63, 0
  %cv65 = zext i1 %cmp64 to i32
  store i32 %cv65, ptr %slot16, align 8
  %v66 = load i32, ptr %slot16, align 8
  %cv67 = zext i32 %v66 to i64
  %cond68 = icmp ne i64 %cv67, 0
  br i1 %cond68, label %bb_rcgpublishmarkcheck53, label %bb_rcgpublishcapacity53
bb_rcgpublishcapacity53:
  %v69 = load i64, ptr %slot8, align 8
  %op70 = sub i64 %v69, 32
  store i64 %op70, ptr %slot17, align 8
  %v71 = load i64, ptr %slot8, align 8
  %p72 = inttoptr i64 %v71 to ptr
  %rgep73 = getelementptr i8, ptr %p72, i64 -32
  %ld74 = load i64, ptr %rgep73, align 8, !alias.scope !9, !noalias !10
  store i64 %ld74, ptr %slot18, align 8
  %v75 = load i64, ptr %slot18, align 8
  %op76 = add i64 %v75, 1
  store i64 %op76, ptr %slot19, align 8
  %v77 = load i64, ptr %slot19, align 8
  %cmp78 = icmp eq i64 %v77, 0
  %cv79 = zext i1 %cmp78 to i32
  store i32 %cv79, ptr %slot20, align 8
  %v80 = load i32, ptr %slot20, align 8
  %cv81 = zext i32 %v80 to i64
  %cond82 = icmp ne i64 %cv81, 0
  br i1 %cond82, label %bb_rcgpublishslow53, label %bb_rcgpublishacquire53
bb_rcgpublishacquire53:
  %v83 = load i64, ptr %slot19, align 8
  %v84 = load i64, ptr %slot8, align 8
  %p85 = inttoptr i64 %v84 to ptr
  %rgep86 = getelementptr i8, ptr %p85, i64 -32
  store i64 %v83, ptr %rgep86, align 8, !alias.scope !9, !noalias !10
  br label %bb_rcgpublishmarkcheck53
bb_rcgpublishmarkcheck53:
  %v87 = load i64, ptr %slot11, align 8
  %op88 = and i64 %v87, 2305843009213693954
  store i64 %op88, ptr %slot21, align 8
  %v89 = load i64, ptr %slot21, align 8
  %cmp90 = icmp ne i64 %v89, 0
  %cv91 = zext i1 %cmp90 to i32
  store i32 %cv91, ptr %slot22, align 8
  %v92 = load i32, ptr %slot22, align 8
  %cv93 = zext i32 %v92 to i64
  %cond94 = icmp ne i64 %cv93, 0
  br i1 %cond94, label %bb_rcgpublishstore53, label %bb_rcgpublishmark53
bb_rcgpublishmark53:
  %v95 = load i64, ptr %slot11, align 8
  %op96 = or i64 %v95, 2305843009213693952
  store i64 %op96, ptr %slot23, align 8
  %v97 = load i64, ptr %slot23, align 8
  %v98 = load i64, ptr %slot8, align 8
  %p99 = inttoptr i64 %v98 to ptr
  %rgep100 = getelementptr i8, ptr %p99, i64 -16
  store i64 %v97, ptr %rgep100, align 8, !alias.scope !9, !noalias !10
  br label %bb_rcgpublishstore53
bb_rcgpublishstore53:
  %v101 = load i64, ptr %slot8, align 8
  %v102 = load i64, ptr %slot3, align 8
  %p103 = inttoptr i64 %v102 to ptr
  store i64 %v101, ptr %p103, align 8, !alias.scope !4, !noalias !3
  %v104 = load i32, ptr %slot6, align 8
  %op105 = and i32 %v104, 4
  store i32 %op105, ptr %slot24, align 8
  %v106 = load i32, ptr %slot24, align 8
  %cv107 = zext i32 %v106 to i64
  %cond108 = icmp ne i64 %cv107, 0
  br i1 %cond108, label %bb_rcgpublishtake53, label %bb_rcgpublished53
bb_rcgpublishtake53:
  %v109 = load i64, ptr %slot4, align 8
  %p110 = inttoptr i64 %v109 to ptr
  store i64 0, ptr %p110, align 8, !alias.scope !4, !noalias !3
  br label %bb_rcgpublished53
bb_rcgpublishslow53:
  %v111 = load i64, ptr %slot2, align 8
  %v112 = load i64, ptr %slot3, align 8
  %v113 = load i64, ptr %slot4, align 8
  %v114 = load i32, ptr %slot5, align 8
  %v115 = load i32, ptr %slot6, align 8
  %call116 = call i32 @myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_publish(i64 %v111, i64 %v112, i64 %v113, i32 %v114, i32 %v115)
  store i32 %call116, ptr %slot25, align 8
  %v117 = load i32, ptr %slot25, align 8
  %cv118 = zext i32 %v117 to i64
  %cond119 = icmp ne i64 %cv118, 0
  br i1 %cond119, label %bb_rcsuccess73, label %bb_rcfailure73
bb_rcfailure73:
  %v120 = load i64, ptr %slot2, align 8
  %p121 = inttoptr i64 %v120 to ptr
  %call122 = call i32 @myl_rc_take_failure(ptr %p121)
  store i32 %call122, ptr %slot26, align 8
  %v123 = load i64, ptr %slot1, align 8
  %p124 = inttoptr i64 %v123 to ptr
  %v125 = load i32, ptr %slot26, align 8
  %call126 = call i32 @myl_qbe_rc_status(ptr %p124, i32 %v125)
  store i32 %call126, ptr %slot27, align 8
  br label %bb_failure
bb_rcsuccess73:
  br label %bb_rcgpublished53
bb_rcgpublished53:
  ret i32 1
bb_failure:
  ret i32 0
}

declare i32 @myl_qbe_rc_status(ptr, i32)
declare i32 @myl_rc_take_failure(ptr)
declare i32 @myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_publish(i64, i64, i64, i32, i32)

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
