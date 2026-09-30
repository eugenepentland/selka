	.file	"count-hold.ll"
	.text
	.globl	hold                            # -- Begin function hold
	.p2align	4
	.type	hold,@function
hold:                                   # @hold
	.cfi_startproc
# %bb.0:                                # %bb_start
	movq	-24(%rsi), %rax
	incq	%rax
	jne	.LBB0_3
# %bb.1:                                # %bb_rcglimit363
	pushq	%rax
	.cfi_def_cfa_offset 16
	movl	$2, %esi
	callq	myl_qbe_rc_status@PLT
	xorl	%eax, %eax
	addq	$8, %rsp
	.cfi_def_cfa_offset 8
	retq
.LBB0_3:                                # %bb_rcgcapacity363
	movq	%rax, -24(%rsi)
	movq	%rsi, (%rdx)
	movl	$1, %eax
	retq
.Lfunc_end0:
	.size	hold, .Lfunc_end0-hold
	.cfi_endproc
                                        # -- End function
	.section	".note.GNU-stack","",@progbits
	.addrsig
