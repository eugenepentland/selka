	.file	"count-owner.ll"
	.text
	.globl	owner                           # -- Begin function owner
	.p2align	4
	.type	owner,@function
owner:                                  # @owner
	.cfi_startproc
# %bb.0:                                # %bb_start
	movq	-32(%rsi), %rax
	incq	%rax
	jne	.LBB0_3
# %bb.1:                                # %bb_rcglimit480
	pushq	%rax
	.cfi_def_cfa_offset 16
	movl	$2, %esi
	callq	myl_qbe_rc_status@PLT
	xorl	%eax, %eax
	addq	$8, %rsp
	.cfi_def_cfa_offset 8
	retq
.LBB0_3:                                # %bb_rcgcapacity480
	movq	%rax, -32(%rsi)
	movq	%rsi, (%rdx)
	movl	$1, %eax
	retq
.Lfunc_end0:
	.size	owner, .Lfunc_end0-owner
	.cfi_endproc
                                        # -- End function
	.section	".note.GNU-stack","",@progbits
	.addrsig
