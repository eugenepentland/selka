; ModuleID = 'hoist-monotonic.ll'
source_filename = "hoist-monotonic.ll"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux7.0.0-gnu2.43.0"

; Function Attrs: nofree norecurse nounwind memory(argmem: readwrite)
define void @f(ptr noalias readonly captures(none) %block, ptr noalias writeonly captures(none) %out, i64 %n) local_unnamed_addr #0 {
entry:
  %0 = add i64 %n, -1
  %xtraiter = and i64 %n, 7
  %1 = icmp ult i64 %0, 7
  br i1 %1, label %loop.epil.preheader, label %entry.new

entry.new:                                        ; preds = %entry
  %unroll_iter = and i64 %n, -8
  br label %loop

loop:                                             ; preds = %loop, %entry.new
  %i = phi i64 [ 0, %entry.new ], [ %i1.7, %loop ]
  %niter = phi i64 [ 0, %entry.new ], [ %niter.next.7, %loop ]
  %c = load atomic i32, ptr %block monotonic, align 8, !tbaa !0
  %u = icmp eq i32 %c, 1
  %z = zext i1 %u to i32
  %p = getelementptr i32, ptr %out, i64 %i
  store i32 %z, ptr %p, align 4, !tbaa !3
  %c.1 = load atomic i32, ptr %block monotonic, align 8, !tbaa !0
  %u.1 = icmp eq i32 %c.1, 1
  %z.1 = zext i1 %u.1 to i32
  %2 = getelementptr i32, ptr %out, i64 %i
  %p.1 = getelementptr i8, ptr %2, i64 4
  store i32 %z.1, ptr %p.1, align 4, !tbaa !3
  %c.2 = load atomic i32, ptr %block monotonic, align 8, !tbaa !0
  %u.2 = icmp eq i32 %c.2, 1
  %z.2 = zext i1 %u.2 to i32
  %3 = getelementptr i32, ptr %out, i64 %i
  %p.2 = getelementptr i8, ptr %3, i64 8
  store i32 %z.2, ptr %p.2, align 4, !tbaa !3
  %c.3 = load atomic i32, ptr %block monotonic, align 8, !tbaa !0
  %u.3 = icmp eq i32 %c.3, 1
  %z.3 = zext i1 %u.3 to i32
  %4 = getelementptr i32, ptr %out, i64 %i
  %p.3 = getelementptr i8, ptr %4, i64 12
  store i32 %z.3, ptr %p.3, align 4, !tbaa !3
  %c.4 = load atomic i32, ptr %block monotonic, align 8, !tbaa !0
  %u.4 = icmp eq i32 %c.4, 1
  %z.4 = zext i1 %u.4 to i32
  %5 = getelementptr i32, ptr %out, i64 %i
  %p.4 = getelementptr i8, ptr %5, i64 16
  store i32 %z.4, ptr %p.4, align 4, !tbaa !3
  %c.5 = load atomic i32, ptr %block monotonic, align 8, !tbaa !0
  %u.5 = icmp eq i32 %c.5, 1
  %z.5 = zext i1 %u.5 to i32
  %6 = getelementptr i32, ptr %out, i64 %i
  %p.5 = getelementptr i8, ptr %6, i64 20
  store i32 %z.5, ptr %p.5, align 4, !tbaa !3
  %c.6 = load atomic i32, ptr %block monotonic, align 8, !tbaa !0
  %u.6 = icmp eq i32 %c.6, 1
  %z.6 = zext i1 %u.6 to i32
  %7 = getelementptr i32, ptr %out, i64 %i
  %p.6 = getelementptr i8, ptr %7, i64 24
  store i32 %z.6, ptr %p.6, align 4, !tbaa !3
  %c.7 = load atomic i32, ptr %block monotonic, align 8, !tbaa !0
  %u.7 = icmp eq i32 %c.7, 1
  %z.7 = zext i1 %u.7 to i32
  %8 = getelementptr i32, ptr %out, i64 %i
  %p.7 = getelementptr i8, ptr %8, i64 28
  store i32 %z.7, ptr %p.7, align 4, !tbaa !3
  %i1.7 = add i64 %i, 8
  %niter.next.7 = add i64 %niter, 8
  %niter.ncmp.7 = icmp eq i64 %niter.next.7, %unroll_iter
  br i1 %niter.ncmp.7, label %exit.unr-lcssa, label %loop

exit.unr-lcssa:                                   ; preds = %loop
  %lcmp.mod.not = icmp eq i64 %xtraiter, 0
  br i1 %lcmp.mod.not, label %exit, label %loop.epil.preheader

loop.epil.preheader:                              ; preds = %exit.unr-lcssa, %entry
  %i.epil.init = phi i64 [ 0, %entry ], [ %i1.7, %exit.unr-lcssa ]
  %lcmp.mod1 = icmp ne i64 %xtraiter, 0
  tail call void @llvm.assume(i1 %lcmp.mod1)
  br label %loop.epil

loop.epil:                                        ; preds = %loop.epil, %loop.epil.preheader
  %i.epil = phi i64 [ %i.epil.init, %loop.epil.preheader ], [ %i1.epil, %loop.epil ]
  %epil.iter = phi i64 [ 0, %loop.epil.preheader ], [ %epil.iter.next, %loop.epil ]
  %c.epil = load atomic i32, ptr %block monotonic, align 8, !tbaa !0
  %u.epil = icmp eq i32 %c.epil, 1
  %z.epil = zext i1 %u.epil to i32
  %p.epil = getelementptr i32, ptr %out, i64 %i.epil
  store i32 %z.epil, ptr %p.epil, align 4, !tbaa !3
  %i1.epil = add i64 %i.epil, 1
  %epil.iter.next = add i64 %epil.iter, 1
  %epil.iter.cmp.not = icmp eq i64 %epil.iter.next, %xtraiter
  br i1 %epil.iter.cmp.not, label %exit, label %loop.epil, !llvm.loop !5

exit:                                             ; preds = %loop.epil, %exit.unr-lcssa
  ret void
}

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(inaccessiblemem: write)
declare void @llvm.assume(i1 noundef) #1

attributes #0 = { nofree norecurse nounwind memory(argmem: readwrite) }
attributes #1 = { nocallback nofree nosync nounwind willreturn memory(inaccessiblemem: write) }

!0 = !{!1, !1, i64 0}
!1 = !{!"myl.count", !2, i64 0}
!2 = !{!"myl.tbaa"}
!3 = !{!4, !4, i64 0}
!4 = !{!"myl.other", !2, i64 0}
!5 = distinct !{!5, !6}
!6 = !{!"llvm.loop.unroll.disable"}
