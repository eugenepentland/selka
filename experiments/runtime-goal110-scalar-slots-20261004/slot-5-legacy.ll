target triple = "x86_64-unknown-linux-gnu"

define dllexport i64 @slot_5_legacy(i64 %p_count, i64 %p_seed) {
bb_start:
  %slot1 = alloca i64, align 8
  %slot2 = alloca i64, align 8
  %slot3 = alloca i64, align 8
  %slot4 = alloca i64, align 8
  %slot5 = alloca i64, align 8
  %slot6 = alloca i64, align 8
  %slot7 = alloca i64, align 8
  store i64 %p_count, ptr %slot1, align 8
  store i64 %p_seed, ptr %slot2, align 8
  %v8 = load i64, ptr %slot1, align 8
  %cmp9 = icmp sgt i64 %v8, 0
  %cv10 = zext i1 %cmp9 to i64
  store i64 %cv10, ptr %slot3, align 8
  %v11 = load i64, ptr %slot3, align 8
  %cond12 = icmp ne i64 %v11, 0
  br i1 %cond12, label %bb_left, label %bb_right
bb_left:
  %mem13 = alloca i8, i64 8, align 8
  %ptr14 = ptrtoint ptr %mem13 to i64
  store i64 %ptr14, ptr %slot4, align 8
  %v15 = load i64, ptr %slot2, align 8
  %op16 = add i64 %v15, 3
  store i64 %op16, ptr %slot5, align 8
  %v17 = load i64, ptr %slot5, align 8
  %v18 = load i64, ptr %slot4, align 8
  %p19 = inttoptr i64 %v18 to ptr
  store i64 %v17, ptr %p19, align 8
  br label %bb_join
bb_right:
  %mem20 = alloca i8, i64 8, align 8
  %ptr21 = ptrtoint ptr %mem20 to i64
  store i64 %ptr21, ptr %slot4, align 8
  %v22 = load i64, ptr %slot2, align 8
  %op23 = add i64 %v22, 7
  store i64 %op23, ptr %slot6, align 8
  %v24 = load i64, ptr %slot6, align 8
  %v25 = load i64, ptr %slot4, align 8
  %p26 = inttoptr i64 %v25 to ptr
  store i64 %v24, ptr %p26, align 8
  br label %bb_join
bb_join:
  %v27 = load i64, ptr %slot4, align 8
  %p28 = inttoptr i64 %v27 to ptr
  %ld29 = load i64, ptr %p28, align 8
  store i64 %ld29, ptr %slot7, align 8
  %v30 = load i64, ptr %slot7, align 8
  ret i64 %v30
}
