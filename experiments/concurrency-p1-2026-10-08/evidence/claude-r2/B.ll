target triple = "x86_64-unknown-linux-gnu"
declare preserve_mostcc void @myl_core_retain_slow(ptr) nounwind cold
define i64 @work(ptr %blocks, i64 %v0, i64 %v1, i64 %v2, i64 %v3, i64 %v4) {
entry:
  br label %s0
s0:
  %p0 = getelementptr ptr, ptr %blocks, i64 0
  %blk0 = load ptr, ptr %p0
  %cnt0 = load atomic i32, ptr %blk0 unordered, align 8
  %plain0 = icmp ult i32 %cnt0, 2147483646
  br i1 %plain0, label %inc0, label %slow0, !prof !0
inc0:
  %n0 = add nuw i32 %cnt0, 1
  store i32 %n0, ptr %blk0, align 8
  br label %done0
slow0:
  call preserve_mostcc void @myl_core_retain_slow(ptr %blk0)
  br label %done0
done0:
  %x0_0 = mul i64 %v0, %v1
  %x0_1 = mul i64 %v1, %v2
  %x0_2 = mul i64 %v2, %v3
  %x0_3 = mul i64 %v3, %v4
  %x0_4 = mul i64 %v4, %v0
  br label %s1
s1:
  %p1 = getelementptr ptr, ptr %blocks, i64 1
  %blk1 = load ptr, ptr %p1
  %cnt1 = load atomic i32, ptr %blk1 unordered, align 8
  %plain1 = icmp ult i32 %cnt1, 2147483646
  br i1 %plain1, label %inc1, label %slow1, !prof !0
inc1:
  %n1 = add nuw i32 %cnt1, 1
  store i32 %n1, ptr %blk1, align 8
  br label %done1
slow1:
  call preserve_mostcc void @myl_core_retain_slow(ptr %blk1)
  br label %done1
done1:
  %x1_0 = mul i64 %x0_0, %x0_1
  %x1_1 = mul i64 %x0_1, %x0_2
  %x1_2 = mul i64 %x0_2, %x0_3
  %x1_3 = mul i64 %x0_3, %x0_4
  %x1_4 = mul i64 %x0_4, %x0_0
  br label %s2
s2:
  %p2 = getelementptr ptr, ptr %blocks, i64 2
  %blk2 = load ptr, ptr %p2
  %cnt2 = load atomic i32, ptr %blk2 unordered, align 8
  %plain2 = icmp ult i32 %cnt2, 2147483646
  br i1 %plain2, label %inc2, label %slow2, !prof !0
inc2:
  %n2 = add nuw i32 %cnt2, 1
  store i32 %n2, ptr %blk2, align 8
  br label %done2
slow2:
  call preserve_mostcc void @myl_core_retain_slow(ptr %blk2)
  br label %done2
done2:
  %x2_0 = mul i64 %x1_0, %x1_1
  %x2_1 = mul i64 %x1_1, %x1_2
  %x2_2 = mul i64 %x1_2, %x1_3
  %x2_3 = mul i64 %x1_3, %x1_4
  %x2_4 = mul i64 %x1_4, %x1_0
  br label %s3
s3:
  %p3 = getelementptr ptr, ptr %blocks, i64 3
  %blk3 = load ptr, ptr %p3
  %cnt3 = load atomic i32, ptr %blk3 unordered, align 8
  %plain3 = icmp ult i32 %cnt3, 2147483646
  br i1 %plain3, label %inc3, label %slow3, !prof !0
inc3:
  %n3 = add nuw i32 %cnt3, 1
  store i32 %n3, ptr %blk3, align 8
  br label %done3
slow3:
  call preserve_mostcc void @myl_core_retain_slow(ptr %blk3)
  br label %done3
done3:
  %x3_0 = mul i64 %x2_0, %x2_1
  %x3_1 = mul i64 %x2_1, %x2_2
  %x3_2 = mul i64 %x2_2, %x2_3
  %x3_3 = mul i64 %x2_3, %x2_4
  %x3_4 = mul i64 %x2_4, %x2_0
  br label %s4
s4:
  %p4 = getelementptr ptr, ptr %blocks, i64 4
  %blk4 = load ptr, ptr %p4
  %cnt4 = load atomic i32, ptr %blk4 unordered, align 8
  %plain4 = icmp ult i32 %cnt4, 2147483646
  br i1 %plain4, label %inc4, label %slow4, !prof !0
inc4:
  %n4 = add nuw i32 %cnt4, 1
  store i32 %n4, ptr %blk4, align 8
  br label %done4
slow4:
  call preserve_mostcc void @myl_core_retain_slow(ptr %blk4)
  br label %done4
done4:
  %x4_0 = mul i64 %x3_0, %x3_1
  %x4_1 = mul i64 %x3_1, %x3_2
  %x4_2 = mul i64 %x3_2, %x3_3
  %x4_3 = mul i64 %x3_3, %x3_4
  %x4_4 = mul i64 %x3_4, %x3_0
  br label %s5
s5:
  %p5 = getelementptr ptr, ptr %blocks, i64 5
  %blk5 = load ptr, ptr %p5
  %cnt5 = load atomic i32, ptr %blk5 unordered, align 8
  %plain5 = icmp ult i32 %cnt5, 2147483646
  br i1 %plain5, label %inc5, label %slow5, !prof !0
inc5:
  %n5 = add nuw i32 %cnt5, 1
  store i32 %n5, ptr %blk5, align 8
  br label %done5
slow5:
  call preserve_mostcc void @myl_core_retain_slow(ptr %blk5)
  br label %done5
done5:
  %x5_0 = mul i64 %x4_0, %x4_1
  %x5_1 = mul i64 %x4_1, %x4_2
  %x5_2 = mul i64 %x4_2, %x4_3
  %x5_3 = mul i64 %x4_3, %x4_4
  %x5_4 = mul i64 %x4_4, %x4_0
  br label %s6
s6:
  %p6 = getelementptr ptr, ptr %blocks, i64 6
  %blk6 = load ptr, ptr %p6
  %cnt6 = load atomic i32, ptr %blk6 unordered, align 8
  %plain6 = icmp ult i32 %cnt6, 2147483646
  br i1 %plain6, label %inc6, label %slow6, !prof !0
inc6:
  %n6 = add nuw i32 %cnt6, 1
  store i32 %n6, ptr %blk6, align 8
  br label %done6
slow6:
  call preserve_mostcc void @myl_core_retain_slow(ptr %blk6)
  br label %done6
done6:
  %x6_0 = mul i64 %x5_0, %x5_1
  %x6_1 = mul i64 %x5_1, %x5_2
  %x6_2 = mul i64 %x5_2, %x5_3
  %x6_3 = mul i64 %x5_3, %x5_4
  %x6_4 = mul i64 %x5_4, %x5_0
  br label %s7
s7:
  %p7 = getelementptr ptr, ptr %blocks, i64 7
  %blk7 = load ptr, ptr %p7
  %cnt7 = load atomic i32, ptr %blk7 unordered, align 8
  %plain7 = icmp ult i32 %cnt7, 2147483646
  br i1 %plain7, label %inc7, label %slow7, !prof !0
inc7:
  %n7 = add nuw i32 %cnt7, 1
  store i32 %n7, ptr %blk7, align 8
  br label %done7
slow7:
  call preserve_mostcc void @myl_core_retain_slow(ptr %blk7)
  br label %done7
done7:
  %x7_0 = mul i64 %x6_0, %x6_1
  %x7_1 = mul i64 %x6_1, %x6_2
  %x7_2 = mul i64 %x6_2, %x6_3
  %x7_3 = mul i64 %x6_3, %x6_4
  %x7_4 = mul i64 %x6_4, %x6_0
  br label %s8
s8:
  %p8 = getelementptr ptr, ptr %blocks, i64 8
  %blk8 = load ptr, ptr %p8
  %cnt8 = load atomic i32, ptr %blk8 unordered, align 8
  %plain8 = icmp ult i32 %cnt8, 2147483646
  br i1 %plain8, label %inc8, label %slow8, !prof !0
inc8:
  %n8 = add nuw i32 %cnt8, 1
  store i32 %n8, ptr %blk8, align 8
  br label %done8
slow8:
  call preserve_mostcc void @myl_core_retain_slow(ptr %blk8)
  br label %done8
done8:
  %x8_0 = mul i64 %x7_0, %x7_1
  %x8_1 = mul i64 %x7_1, %x7_2
  %x8_2 = mul i64 %x7_2, %x7_3
  %x8_3 = mul i64 %x7_3, %x7_4
  %x8_4 = mul i64 %x7_4, %x7_0
  br label %s9
s9:
  %p9 = getelementptr ptr, ptr %blocks, i64 9
  %blk9 = load ptr, ptr %p9
  %cnt9 = load atomic i32, ptr %blk9 unordered, align 8
  %plain9 = icmp ult i32 %cnt9, 2147483646
  br i1 %plain9, label %inc9, label %slow9, !prof !0
inc9:
  %n9 = add nuw i32 %cnt9, 1
  store i32 %n9, ptr %blk9, align 8
  br label %done9
slow9:
  call preserve_mostcc void @myl_core_retain_slow(ptr %blk9)
  br label %done9
done9:
  %x9_0 = mul i64 %x8_0, %x8_1
  %x9_1 = mul i64 %x8_1, %x8_2
  %x9_2 = mul i64 %x8_2, %x8_3
  %x9_3 = mul i64 %x8_3, %x8_4
  %x9_4 = mul i64 %x8_4, %x8_0
  br label %s10
s10:
  %p10 = getelementptr ptr, ptr %blocks, i64 10
  %blk10 = load ptr, ptr %p10
  %cnt10 = load atomic i32, ptr %blk10 unordered, align 8
  %plain10 = icmp ult i32 %cnt10, 2147483646
  br i1 %plain10, label %inc10, label %slow10, !prof !0
inc10:
  %n10 = add nuw i32 %cnt10, 1
  store i32 %n10, ptr %blk10, align 8
  br label %done10
slow10:
  call preserve_mostcc void @myl_core_retain_slow(ptr %blk10)
  br label %done10
done10:
  %x10_0 = mul i64 %x9_0, %x9_1
  %x10_1 = mul i64 %x9_1, %x9_2
  %x10_2 = mul i64 %x9_2, %x9_3
  %x10_3 = mul i64 %x9_3, %x9_4
  %x10_4 = mul i64 %x9_4, %x9_0
  br label %s11
s11:
  %p11 = getelementptr ptr, ptr %blocks, i64 11
  %blk11 = load ptr, ptr %p11
  %cnt11 = load atomic i32, ptr %blk11 unordered, align 8
  %plain11 = icmp ult i32 %cnt11, 2147483646
  br i1 %plain11, label %inc11, label %slow11, !prof !0
inc11:
  %n11 = add nuw i32 %cnt11, 1
  store i32 %n11, ptr %blk11, align 8
  br label %done11
slow11:
  call preserve_mostcc void @myl_core_retain_slow(ptr %blk11)
  br label %done11
done11:
  %x11_0 = mul i64 %x10_0, %x10_1
  %x11_1 = mul i64 %x10_1, %x10_2
  %x11_2 = mul i64 %x10_2, %x10_3
  %x11_3 = mul i64 %x10_3, %x10_4
  %x11_4 = mul i64 %x10_4, %x10_0
  br label %s12
s12:
  %r1 = add i64 %x11_0, %x11_1
  %r2 = add i64 %r1, %x11_2
  %r3 = add i64 %r2, %x11_3
  %r4 = add i64 %r3, %x11_4
  ret i64 %r4
}
!0 = !{!"branch_weights", i32 2000, i32 1}
