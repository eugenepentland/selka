; ModuleID = 'hoist-plain.ll'
source_filename = "hoist-plain.ll"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux7.0.0-gnu2.43.0"

; Function Attrs: nofree norecurse nosync nounwind memory(argmem: readwrite)
define void @f(ptr noalias readonly captures(none) %block, ptr noalias writeonly captures(none) %out, i64 %n) local_unnamed_addr #0 {
iter.check:
  %c = load i32, ptr %block, align 8, !tbaa !0
  %u = icmp eq i32 %c, 1
  %z = zext i1 %u to i32
  %min.iters.check = icmp ult i64 %n, 4
  br i1 %min.iters.check, label %loop.preheader, label %vector.main.loop.iter.check

vector.main.loop.iter.check:                      ; preds = %iter.check
  %min.iters.check1 = icmp ult i64 %n, 32
  br i1 %min.iters.check1, label %vec.epilog.ph, label %vector.ph

vector.ph:                                        ; preds = %vector.main.loop.iter.check
  %n.mod.vf = and i64 %n, 28
  %n.vec = and i64 %n, -32
  %broadcast.splatinsert = insertelement <8 x i32> poison, i32 %z, i64 0
  %broadcast.splat = shufflevector <8 x i32> %broadcast.splatinsert, <8 x i32> poison, <8 x i32> zeroinitializer
  br label %vector.body

vector.body:                                      ; preds = %vector.body, %vector.ph
  %index = phi i64 [ 0, %vector.ph ], [ %index.next, %vector.body ]
  %0 = getelementptr i32, ptr %out, i64 %index
  %1 = getelementptr i8, ptr %0, i64 32
  %2 = getelementptr i8, ptr %0, i64 64
  %3 = getelementptr i8, ptr %0, i64 96
  store <8 x i32> %broadcast.splat, ptr %0, align 4, !tbaa !3
  store <8 x i32> %broadcast.splat, ptr %1, align 4, !tbaa !3
  store <8 x i32> %broadcast.splat, ptr %2, align 4, !tbaa !3
  store <8 x i32> %broadcast.splat, ptr %3, align 4, !tbaa !3
  %index.next = add nuw i64 %index, 32
  %4 = icmp eq i64 %index.next, %n.vec
  br i1 %4, label %middle.block, label %vector.body, !llvm.loop !5

middle.block:                                     ; preds = %vector.body
  %cmp.n = icmp eq i64 %n, %n.vec
  br i1 %cmp.n, label %exit, label %vec.epilog.iter.check

vec.epilog.iter.check:                            ; preds = %middle.block
  %min.epilog.iters.check = icmp eq i64 %n.mod.vf, 0
  br i1 %min.epilog.iters.check, label %loop.preheader, label %vec.epilog.ph, !prof !8

vec.epilog.ph:                                    ; preds = %vector.main.loop.iter.check, %vec.epilog.iter.check
  %vec.epilog.resume.val = phi i64 [ %n.vec, %vec.epilog.iter.check ], [ 0, %vector.main.loop.iter.check ]
  %n.vec3 = and i64 %n, -4
  %broadcast.splatinsert4 = insertelement <4 x i32> poison, i32 %z, i64 0
  %broadcast.splat5 = shufflevector <4 x i32> %broadcast.splatinsert4, <4 x i32> poison, <4 x i32> zeroinitializer
  br label %vec.epilog.vector.body

vec.epilog.vector.body:                           ; preds = %vec.epilog.vector.body, %vec.epilog.ph
  %index6 = phi i64 [ %vec.epilog.resume.val, %vec.epilog.ph ], [ %index.next7, %vec.epilog.vector.body ]
  %5 = getelementptr i32, ptr %out, i64 %index6
  store <4 x i32> %broadcast.splat5, ptr %5, align 4, !tbaa !3
  %index.next7 = add nuw i64 %index6, 4
  %6 = icmp eq i64 %index.next7, %n.vec3
  br i1 %6, label %vec.epilog.middle.block, label %vec.epilog.vector.body, !llvm.loop !9

vec.epilog.middle.block:                          ; preds = %vec.epilog.vector.body
  %cmp.n8 = icmp eq i64 %n, %n.vec3
  br i1 %cmp.n8, label %exit, label %loop.preheader

loop.preheader:                                   ; preds = %iter.check, %vec.epilog.iter.check, %vec.epilog.middle.block
  %i.ph = phi i64 [ 0, %iter.check ], [ %n.vec, %vec.epilog.iter.check ], [ %n.vec3, %vec.epilog.middle.block ]
  br label %loop

loop:                                             ; preds = %loop.preheader, %loop
  %i = phi i64 [ %i1, %loop ], [ %i.ph, %loop.preheader ]
  %p = getelementptr i32, ptr %out, i64 %i
  store i32 %z, ptr %p, align 4, !tbaa !3
  %i1 = add i64 %i, 1
  %d = icmp eq i64 %i1, %n
  br i1 %d, label %exit, label %loop, !llvm.loop !10

exit:                                             ; preds = %loop, %vec.epilog.middle.block, %middle.block
  ret void
}

attributes #0 = { nofree norecurse nosync nounwind memory(argmem: readwrite) }

!0 = !{!1, !1, i64 0}
!1 = !{!"myl.count", !2, i64 0}
!2 = !{!"myl.tbaa"}
!3 = !{!4, !4, i64 0}
!4 = !{!"myl.other", !2, i64 0}
!5 = distinct !{!5, !6, !7}
!6 = !{!"llvm.loop.isvectorized", i32 1}
!7 = !{!"llvm.loop.unroll.runtime.disable"}
!8 = !{!"branch_weights", i32 4, i32 28}
!9 = distinct !{!9, !6, !7}
!10 = distinct !{!10, !7, !6}
