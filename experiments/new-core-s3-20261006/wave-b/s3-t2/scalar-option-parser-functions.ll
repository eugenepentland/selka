define internal { i8, double } @"my.n_scalar_parse_abi::floating"(ptr %p0, i64 %p1, i64 %p2) nounwind uwtable !dbg !1000020 {
entry:
  %slot = alloca i64, align 8
  br label %b0
b0:
  %rl.1 = icmp slt i64 %p1, 0
  %rh.2 = icmp sgt i64 %p1, 0
  %rx.3 = or i1 %rl.1, %rh.2
  br i1 %rx.3, label %trap.4, label %b0.5, !prof !0
trap.4:
  call void @myl_core_trap(i32 0, i64 %p1, i64 0), !dbg !1000021
  unreachable
b0.5:
  %rl.6 = icmp slt i64 %p2, 3
  %rh.7 = icmp sgt i64 %p2, 6
  %rx.8 = or i1 %rl.6, %rh.7
  br i1 %rx.8, label %trap.9, label %b0.5.10, !prof !0
trap.9:
  call void @myl_core_trap(i32 1, i64 %p2, i64 0), !dbg !1000022
  unreachable
b0.5.10:
  %v3 = call { i8, double } @myl_core_parse_float_range(ptr %p0, i64 %p1, i64 %p2), !dbg !1000023
  ret { i8, double } %v3
}

define internal { i8, i64 } @"my.n_scalar_parse_abi::integer"(ptr %p0, i64 %p1, i64 %p2) nounwind uwtable !dbg !1000024 {
entry:
  %slot = alloca i64, align 8
  br label %b0
b0:
  %rl.1 = icmp slt i64 %p1, 0
  %rh.2 = icmp sgt i64 %p1, 0
  %rx.3 = or i1 %rl.1, %rh.2
  br i1 %rx.3, label %trap.4, label %b0.5, !prof !0
trap.4:
  call void @myl_core_trap(i32 2, i64 %p1, i64 0), !dbg !1000025
  unreachable
b0.5:
  %rl.6 = icmp slt i64 %p2, 7
  %rh.7 = icmp sgt i64 %p2, 20
  %rx.8 = or i1 %rl.6, %rh.7
  br i1 %rx.8, label %trap.9, label %b0.5.10, !prof !0
trap.9:
  call void @myl_core_trap(i32 3, i64 %p2, i64 0), !dbg !1000026
  unreachable
b0.5.10:
  %v3 = call { i8, i64 } @myl_core_parse_int_range(ptr %p0, i64 %p1, i64 %p2), !dbg !1000027
  ret { i8, i64 } %v3
}
