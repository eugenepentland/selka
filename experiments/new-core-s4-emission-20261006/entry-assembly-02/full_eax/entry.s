	.file	"row_result_propagate.my"
	.text
	.globl	main                            # -- Begin function main
	.p2align	4
	.type	main,@function
main:                                   # @main
.Lfunc_begin0:
	.file	1 "row_result_propagate.my"
	.loc	1 1 0                           # row_result_propagate.my:1:0
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	pushq	%r15
	.cfi_def_cfa_offset 24
	pushq	%r14
	.cfi_def_cfa_offset 32
	pushq	%r13
	.cfi_def_cfa_offset 40
	pushq	%r12
	.cfi_def_cfa_offset 48
	pushq	%rbx
	.cfi_def_cfa_offset 56
	subq	$40, %rsp
	.cfi_def_cfa_offset 96
	.cfi_offset %rbx, -56
	.cfi_offset %r12, -48
	.cfi_offset %r13, -40
	.cfi_offset %r14, -32
	.cfi_offset %r15, -24
	.cfi_offset %rbp, -16
	.loc	1 1 0 prologue_end              # row_result_propagate.my:1:0
	callq	myl_core_args@PLT
	movq	%rax, %rbx
	callq	myl_core_host_grant@PLT
	movl	$2, %r15d
	cmpq	$3, 8(%rbx)
	jne	.LBB0_105
# %bb.1:                                # %b4.14.i
	movq	%rax, %r14
	movq	32(%rbx), %rdi
	movq	8(%rdi), %rcx
	testq	%rcx, %rcx
	je	.LBB0_7
# %bb.2:                                # %head.i.i130
	movzbl	32(%rdi), %eax
	leal	-43(%rax), %esi
	xorl	%edx, %edx
	testb	$-3, %sil
	sete	%sil
	setne	%r9b
	leal	-48(%rax), %r8d
	cmpb	$10, %r8b
	setae	%r10b
	movzbl	31(%rdi,%rcx), %r8d
	testb	%r9b, %r10b
	jne	.LBB0_8
# %bb.3:                                # %head.i.i130
	leal	-48(%r8), %r9d
	cmpb	$10, %r9b
	jae	.LBB0_8
# %bb.4:                                # %plain_head.i.i153
	movb	%sil, %dl
	subq	%rdx, %rcx
	cmpq	$8, %rcx
	ja	.LBB0_23
# %bb.5:                                # %first_word.i.i157
	leaq	32(%rdi), %rsi
	addq	%rdx, %rsi
	cmpq	$8, %rcx
	jne	.LBB0_11
# %bb.6:                                # %load8.i.i241
	movq	(%rsi), %rdx
	jmp	.LBB0_13
.LBB0_8:                                # %boundary.i.i144
	cmpb	$33, %al
	jb	.LBB0_23
# %bb.9:                                # %boundary.i.i144
	cmpb	$33, %r8b
	jb	.LBB0_23
.LBB0_7:
	xorl	%r12d, %r12d
	movl	$3, %edx
	jmp	.LBB0_27
.LBB0_11:                               # %short.i.i160
	cmpq	$4, %rcx
	jbe	.LBB0_14
# %bb.12:                               # %loadwide.i.i231
	movl	(%rsi), %r8d
	leaq	-4(%rcx), %rdx
	movl	-4(%rsi,%rcx), %esi
	shll	$3, %edx
	shlxq	%rdx, %rsi, %rdx
	orq	%r8, %rdx
.LBB0_13:                               # %large_word.i.i169
	shll	$3, %ecx
	movl	%ecx, %esi
	negb	%sil
	shlxq	%rsi, %rdx, %rdx
	movb	$64, %sil
	subb	%cl, %sil
	movabsq	$13563782407139376, %rcx        # imm = 0x30303030303030
	bzhiq	%rsi, %rcx, %rcx
	orq	%rdx, %rcx
	movabsq	$-3472328296227680304, %rdx     # imm = 0xCFCFCFCFCFCFCFD0
	addq	%rcx, %rdx
	movabsq	$5063812098665367110, %rsi      # imm = 0x4646464646464646
	addq	%rcx, %rsi
	orq	%rdx, %rsi
	movabsq	$-9187201950435737472, %rcx     # imm = 0x8080808080808080
	testq	%rcx, %rsi
	sete	%cl
	leaq	(%rdx,%rdx,4), %rsi
	shrq	$8, %rdx
	leaq	(%rdx,%rsi,2), %rdx
	movq	%rdx, %rsi
	shrq	$16, %rsi
	movabsq	$1095216660735, %r8             # imm = 0xFF000000FF
	andq	%r8, %rdx
	andq	%r8, %rsi
	movabsq	$4294967296000100, %r8          # imm = 0xF424000000064
	imulq	%rdx, %r8
	movabsq	$42949672960001, %rdx           # imm = 0x271000000001
	imulq	%rsi, %rdx
	addq	%r8, %rdx
	shrq	$32, %rdx
	testb	$1, %cl
	je	.LBB0_23
.LBB0_21:                               # %"my.row_result_propagate::parse_number.exit243.thread256"
	movq	%rdx, %r12
	negq	%r12
	cmpb	$45, %al
	cmovneq	%rdx, %r12
	movl	$3, %edx
	jmp	.LBB0_27
.LBB0_14:                               # %tiny.i.i162
	leaq	-1(%rcx), %rdx
	cmpq	$3, %rdx
	ja	.LBB0_22
# %bb.15:                               # %tiny.i.i162
	leaq	.LJTI0_0(%rip), %r8
	movslq	(%r8,%rdx,4), %rdx
	addq	%r8, %rdx
	jmpq	*%rdx
.LBB0_16:                               # %load1.i.i228
	movzbl	(%rsi), %edx
	jmp	.LBB0_20
.LBB0_17:                               # %load3.i.i222
	movzwl	(%rsi), %r8d
	movzbl	2(%rsi), %edx
	shll	$16, %edx
	orl	%r8d, %edx
	jmp	.LBB0_20
.LBB0_18:                               # %load4.i.i163
	movl	(%rsi), %edx
	jmp	.LBB0_20
.LBB0_19:                               # %load2.i.i225
	movzwl	(%rsi), %edx
.LBB0_20:                               # %small_word.i.i200
	shll	$3, %ecx
	movl	%ecx, %esi
	negb	%sil
	shlxl	%esi, %edx, %edx
	movb	$32, %sil
	subb	%cl, %sil
	movl	$3158064, %ecx                  # imm = 0x303030
	bzhil	%esi, %ecx, %ecx
	orl	%edx, %ecx
	leal	-808464432(%rcx), %edx
	addl	$1179010630, %ecx               # imm = 0x46464646
	orl	%edx, %ecx
	testl	$-2139062144, %ecx              # imm = 0x80808080
	sete	%cl
	imull	$2561, %edx, %edx               # imm = 0xA01
	shrl	$8, %edx
	andl	$16711935, %edx                 # imm = 0xFF00FF
	imull	$6553601, %edx, %edx            # imm = 0x640001
	shrl	$16, %edx
	testb	$1, %cl
	jne	.LBB0_21
.LBB0_23:                               # %"my.row_result_propagate::parse_number.exit243.thread"
	leaq	8(%rsp), %rsi
	callq	myl_core_str_parse_int@PLT
	testb	$1, %al
	je	.LBB0_25
# %bb.24:                               # %"my.row_result_propagate::parse_number.exit243.thread"
	movq	8(%rsp), %r12
	jmp	.LBB0_26
.LBB0_25:
	xorl	%r12d, %r12d
.LBB0_26:                               # %"my.row_result_propagate::parse_number.exit243.thread"
	movq	8(%rbx), %rdx
	cmpq	$1, %rdx
	jbe	.LBB0_113
.LBB0_27:                               # %b6.29.i
	movq	40(%rbx), %rdi
	movq	8(%rdi), %rcx
	testq	%rcx, %rcx
	je	.LBB0_33
# %bb.28:                               # %head.i.i12
	movzbl	32(%rdi), %eax
	leal	-43(%rax), %r8d
	xorl	%esi, %esi
	testb	$-3, %r8b
	sete	%r8b
	setne	%r10b
	leal	-48(%rax), %r9d
	cmpb	$10, %r9b
	setae	%r11b
	movzbl	31(%rdi,%rcx), %r9d
	testb	%r10b, %r11b
	jne	.LBB0_34
# %bb.29:                               # %head.i.i12
	leal	-48(%r9), %r10d
	cmpb	$10, %r10b
	jae	.LBB0_34
# %bb.30:                               # %plain_head.i.i35
	movb	%r8b, %sil
	subq	%rsi, %rcx
	cmpq	$8, %rcx
	ja	.LBB0_49
# %bb.31:                               # %first_word.i.i39
	leaq	32(%rdi), %r8
	addq	%rsi, %r8
	cmpq	$8, %rcx
	jne	.LBB0_37
# %bb.32:                               # %load8.i.i123
	movq	(%r8), %rsi
	jmp	.LBB0_39
.LBB0_34:                               # %boundary.i.i26
	cmpb	$33, %al
	jb	.LBB0_49
# %bb.35:                               # %boundary.i.i26
	cmpb	$33, %r9b
	jb	.LBB0_49
.LBB0_33:
	movq	$0, (%rsp)                      # 8-byte Folded Spill
	jmp	.LBB0_53
.LBB0_37:                               # %short.i.i42
	cmpq	$4, %rcx
	jbe	.LBB0_40
# %bb.38:                               # %loadwide.i.i113
	movl	(%r8), %r9d
	leaq	-4(%rcx), %rsi
	movl	-4(%r8,%rcx), %r8d
	shll	$3, %esi
	shlxq	%rsi, %r8, %rsi
	orq	%r9, %rsi
.LBB0_39:                               # %large_word.i.i51
	shll	$3, %ecx
	movl	%ecx, %r8d
	negb	%r8b
	shlxq	%r8, %rsi, %rsi
	movb	$64, %r8b
	subb	%cl, %r8b
	movabsq	$13563782407139376, %rcx        # imm = 0x30303030303030
	bzhiq	%r8, %rcx, %rcx
	orq	%rsi, %rcx
	movabsq	$-3472328296227680304, %rsi     # imm = 0xCFCFCFCFCFCFCFD0
	addq	%rcx, %rsi
	movabsq	$5063812098665367110, %r8       # imm = 0x4646464646464646
	addq	%rcx, %r8
	orq	%rsi, %r8
	movabsq	$-9187201950435737472, %rcx     # imm = 0x8080808080808080
	testq	%rcx, %r8
	sete	%cl
	leaq	(%rsi,%rsi,4), %r8
	shrq	$8, %rsi
	leaq	(%rsi,%r8,2), %rsi
	movq	%rsi, %r8
	shrq	$16, %r8
	movabsq	$1095216660735, %r9             # imm = 0xFF000000FF
	andq	%r9, %rsi
	andq	%r9, %r8
	movabsq	$4294967296000100, %r9          # imm = 0xF424000000064
	imulq	%rsi, %r9
	movabsq	$42949672960001, %rsi           # imm = 0x271000000001
	imulq	%r8, %rsi
	addq	%r9, %rsi
	shrq	$32, %rsi
	testb	$1, %cl
	je	.LBB0_49
.LBB0_47:                               # %"my.row_result_propagate::parse_number.exit125.thread268"
	movq	%rsi, %rcx
	negq	%rcx
	cmpb	$45, %al
	cmovneq	%rsi, %rcx
	movq	%rcx, (%rsp)                    # 8-byte Spill
	jmp	.LBB0_53
.LBB0_40:                               # %tiny.i.i44
	leaq	-1(%rcx), %rsi
	cmpq	$3, %rsi
	ja	.LBB0_48
# %bb.41:                               # %tiny.i.i44
	leaq	.LJTI0_1(%rip), %r9
	movslq	(%r9,%rsi,4), %rsi
	addq	%r9, %rsi
	jmpq	*%rsi
.LBB0_42:                               # %load1.i.i110
	movzbl	(%r8), %esi
	jmp	.LBB0_46
.LBB0_22:
	xorl	%ecx, %ecx
	xorl	%edx, %edx
	testb	$1, %cl
	jne	.LBB0_21
	jmp	.LBB0_23
.LBB0_43:                               # %load3.i.i104
	movzwl	(%r8), %r9d
	movzbl	2(%r8), %esi
	shll	$16, %esi
	orl	%r9d, %esi
	jmp	.LBB0_46
.LBB0_44:                               # %load4.i.i45
	movl	(%r8), %esi
	jmp	.LBB0_46
.LBB0_45:                               # %load2.i.i107
	movzwl	(%r8), %esi
.LBB0_46:                               # %small_word.i.i82
	shll	$3, %ecx
	movl	%ecx, %r8d
	negb	%r8b
	shlxl	%r8d, %esi, %esi
	movb	$32, %r8b
	subb	%cl, %r8b
	movl	$3158064, %ecx                  # imm = 0x303030
	bzhil	%r8d, %ecx, %ecx
	orl	%esi, %ecx
	leal	-808464432(%rcx), %esi
	addl	$1179010630, %ecx               # imm = 0x46464646
	orl	%esi, %ecx
	testl	$-2139062144, %ecx              # imm = 0x80808080
	sete	%cl
	imull	$2561, %esi, %esi               # imm = 0xA01
	shrl	$8, %esi
	andl	$16711935, %esi                 # imm = 0xFF00FF
	imull	$6553601, %esi, %esi            # imm = 0x640001
	shrl	$16, %esi
	testb	$1, %cl
	jne	.LBB0_47
.LBB0_49:                               # %"my.row_result_propagate::parse_number.exit125"
	leaq	8(%rsp), %rsi
	callq	myl_core_str_parse_int@PLT
	testb	$1, %al
	je	.LBB0_51
# %bb.50:                               # %"my.row_result_propagate::parse_number.exit125"
	movq	8(%rsp), %rax
	movq	%rax, (%rsp)                    # 8-byte Spill
	jmp	.LBB0_52
.LBB0_51:
	movq	$0, (%rsp)                      # 8-byte Folded Spill
.LBB0_52:                               # %"my.row_result_propagate::parse_number.exit125"
	movq	8(%rbx), %rdx
.LBB0_53:                               # %"my.row_result_propagate::parse_number.exit125.thread"
	cmpq	$2, %rdx
	jbe	.LBB0_112
# %bb.54:                               # %b8.44.i
	movq	48(%rbx), %rdi
	movq	8(%rdi), %rcx
	testq	%rcx, %rcx
	je	.LBB0_105
# %bb.55:                               # %head.i.i3
	movzbl	32(%rdi), %eax
	leal	-43(%rax), %esi
	xorl	%edx, %edx
	testb	$-3, %sil
	sete	%sil
	setne	%r9b
	leal	-48(%rax), %r8d
	cmpb	$10, %r8b
	setae	%r10b
	movzbl	31(%rdi,%rcx), %r8d
	testb	%r9b, %r10b
	jne	.LBB0_60
# %bb.56:                               # %head.i.i3
	leal	-48(%r8), %r9d
	cmpb	$10, %r9b
	jae	.LBB0_60
# %bb.57:                               # %plain_head.i.i
	movb	%sil, %dl
	subq	%rdx, %rcx
	cmpq	$8, %rcx
	ja	.LBB0_74
# %bb.58:                               # %first_word.i.i
	leaq	32(%rdi), %rsi
	addq	%rdx, %rsi
	cmpq	$8, %rcx
	jne	.LBB0_62
# %bb.59:                               # %load8.i.i
	movq	(%rsi), %rdx
	jmp	.LBB0_64
.LBB0_60:                               # %boundary.i.i
	cmpb	$33, %al
	jb	.LBB0_74
# %bb.61:                               # %boundary.i.i
	cmpb	$33, %r8b
	jae	.LBB0_105
	jmp	.LBB0_74
.LBB0_62:                               # %short.i.i
	cmpq	$4, %rcx
	jbe	.LBB0_65
# %bb.63:                               # %loadwide.i.i
	movl	(%rsi), %r8d
	leaq	-4(%rcx), %rdx
	movl	-4(%rsi,%rcx), %esi
	shll	$3, %edx
	shlxq	%rdx, %rsi, %rdx
	orq	%r8, %rdx
.LBB0_64:                               # %large_word.i.i
	shll	$3, %ecx
	movl	%ecx, %esi
	negb	%sil
	shlxq	%rsi, %rdx, %rdx
	movb	$64, %sil
	subb	%cl, %sil
	movabsq	$13563782407139376, %rcx        # imm = 0x30303030303030
	bzhiq	%rsi, %rcx, %rcx
	orq	%rdx, %rcx
	movabsq	$-3472328296227680304, %rdx     # imm = 0xCFCFCFCFCFCFCFD0
	addq	%rcx, %rdx
	movabsq	$5063812098665367110, %rsi      # imm = 0x4646464646464646
	addq	%rcx, %rsi
	orq	%rdx, %rsi
	movabsq	$-9187201950435737472, %rcx     # imm = 0x8080808080808080
	testq	%rcx, %rsi
	sete	%cl
	leaq	(%rdx,%rdx,4), %rsi
	shrq	$8, %rdx
	leaq	(%rdx,%rsi,2), %rdx
	movq	%rdx, %rsi
	shrq	$16, %rsi
	movabsq	$1095216660735, %r8             # imm = 0xFF000000FF
	andq	%r8, %rdx
	andq	%r8, %rsi
	movabsq	$4294967296000100, %r8          # imm = 0xF424000000064
	imulq	%rdx, %r8
	movabsq	$42949672960001, %rdx           # imm = 0x271000000001
	imulq	%rsi, %rdx
	addq	%r8, %rdx
	shrq	$32, %rdx
	testb	$1, %cl
	je	.LBB0_74
.LBB0_72:                               # %"my.row_result_propagate::parse_number.exit.thread280"
	movq	%rdx, %r8
	negq	%r8
	cmpb	$45, %al
	cmovneq	%rdx, %r8
	jmp	.LBB0_76
.LBB0_65:                               # %tiny.i.i
	leaq	-1(%rcx), %rdx
	cmpq	$3, %rdx
	ja	.LBB0_73
# %bb.66:                               # %tiny.i.i
	leaq	.LJTI0_2(%rip), %r8
	movslq	(%r8,%rdx,4), %rdx
	addq	%r8, %rdx
	jmpq	*%rdx
.LBB0_67:                               # %load1.i.i
	movzbl	(%rsi), %edx
	jmp	.LBB0_71
.LBB0_48:
	xorl	%ecx, %ecx
	xorl	%esi, %esi
	testb	$1, %cl
	jne	.LBB0_47
	jmp	.LBB0_49
.LBB0_68:                               # %load3.i.i
	movzwl	(%rsi), %r8d
	movzbl	2(%rsi), %edx
	shll	$16, %edx
	orl	%r8d, %edx
	jmp	.LBB0_71
.LBB0_69:                               # %load4.i.i
	movl	(%rsi), %edx
	jmp	.LBB0_71
.LBB0_70:                               # %load2.i.i
	movzwl	(%rsi), %edx
.LBB0_71:                               # %small_word.i.i
	shll	$3, %ecx
	movl	%ecx, %esi
	negb	%sil
	shlxl	%esi, %edx, %edx
	movb	$32, %sil
	subb	%cl, %sil
	movl	$3158064, %ecx                  # imm = 0x303030
	bzhil	%esi, %ecx, %ecx
	orl	%edx, %ecx
	leal	-808464432(%rcx), %edx
	addl	$1179010630, %ecx               # imm = 0x46464646
	orl	%edx, %ecx
	testl	$-2139062144, %ecx              # imm = 0x80808080
	sete	%cl
	imull	$2561, %edx, %edx               # imm = 0xA01
	shrl	$8, %edx
	andl	$16711935, %edx                 # imm = 0xFF00FF
	imull	$6553601, %edx, %edx            # imm = 0x640001
	shrl	$16, %edx
	testb	$1, %cl
	jne	.LBB0_72
.LBB0_74:                               # %"my.row_result_propagate::parse_number.exit"
	leaq	8(%rsp), %rsi
	callq	myl_core_str_parse_int@PLT
	testb	%al, %al
	je	.LBB0_105
# %bb.75:
	movq	8(%rsp), %r8
.LBB0_76:
	cmpq	$2, %r12
	jl	.LBB0_105
# %bb.77:
	cmpq	$0, (%rsp)                      # 8-byte Folded Reload
	jle	.LBB0_105
# %bb.78:
	leaq	-1000001(%r8), %rax
	cmpq	$-1000000, %rax                 # imm = 0xFFF0BDC0
	jb	.LBB0_105
# %bb.79:                               # %b18.i
	cmpq	$1024, %r12                     # imm = 0x400
	movq	%r14, 16(%rsp)                  # 8-byte Spill
	ja	.LBB0_106
# %bb.80:                               # %b18.i
	leaq	63(,%r12,8), %rax
	cmpq	$1055, %rax                     # imm = 0x41F
	ja	.LBB0_106
# %bb.81:                               # %small.i.i
	movq	%rax, %rcx
	shrq	$5, %rcx
	movq	myl_core_free_lists@GOTPCREL(%rip), %rdx
	movq	(%rdx,%rcx,8), %r15
	testq	%r15, %r15
	je	.LBB0_106
# %bb.82:                               # %pop.i.i
	movq	(%r15), %rsi
	movq	%rsi, (%rdx,%rcx,8)
	movl	$1, (%r15)
	shll	$24, %ecx
	movl	%ecx, 4(%r15)
	movq	$0, 8(%r15)
	andl	$2016, %eax                     # imm = 0x7E0
	addq	$-32, %rax
	shrq	$3, %rax
	movq	%rax, 16(%r15)
	movq	$0, 24(%r15)
.LBB0_83:                               # %b23.i.preheader
	movq	%rbx, 32(%rsp)                  # 8-byte Spill
	movabsq	$249280325320399347, %rsi       # imm = 0x3759F22983759F3
	xorl	%r14d, %r14d
	movabsq	$-9086255505087856445, %rdi     # imm = 0x81E722C258CD00C3
	xorl	%ebp, %ebp
	.loc	1 0 0 is_stmt 0                 # :0:0
.Ltmp0:
	.p2align	6
.LBB0_84:                               # %b23.i
                                        # =>This Inner Loop Header: Depth=1
	cmpq	%rbp, %rsi
	je	.LBB0_109
# %bb.85:                               # %b23.79.i
                                        #   in Loop: Header=BB0_84 Depth=1
	movq	%r8, %r13
	addq	%r14, %r13
	jo	.LBB0_110
# %bb.86:                               # %b23.79.83.i
                                        #   in Loop: Header=BB0_84 Depth=1
	movq	%r13, %rdx
	mulxq	%rdi, %rbx, %rbx
	movq	8(%r15), %rax
	cmpq	16(%r15), %rax
	jae	.LBB0_88
.LBB0_87:                               # %myl_core_list_reserve.exit.i
                                        #   in Loop: Header=BB0_84 Depth=1
	shrq	$9, %rbx
	imulq	$1009, %rbx, %rcx               # imm = 0x3F1
	subq	%rcx, %r13
	movq	%r13, 32(%r15,%rax,8)
	incq	%rax
	movq	%rax, 8(%r15)
	incq	%rbp
	addq	$37, %r14
	cmpq	%rbp, %r12
	jne	.LBB0_84
	jmp	.LBB0_89
.LBB0_88:                               # %grow.i.i
                                        #   in Loop: Header=BB0_84 Depth=1
	movl	$8, %esi
	movq	%r15, %rdi
	movq	%r8, %r15
	callq	myl_core_list_grow@PLT
	movabsq	$-9086255505087856445, %rdi     # imm = 0x81E722C258CD00C3
	movabsq	$249280325320399347, %rsi       # imm = 0x3759F22983759F3
	movq	%r15, %r8
	movq	%rax, %r15
	movq	8(%rax), %rax
	jmp	.LBB0_87
.LBB0_89:                               # %b27.i.lr.ph
	leaq	.Lmyl.site.19(%rip), %rdi
	callq	myl_core_io_at@PLT
	movq	16(%rsp), %rdi                  # 8-byte Reload
.Ltmp1:
	.loc	1 39 13 is_stmt 1               # row_result_propagate.my:39:13 @[ row_result_propagate.my:1:1 ]
	callq	myl_core_host_check@PLT
	xorl	%ebp, %ebp
	callq	runtime_bench_now@PLT
	movq	%rax, 24(%rsp)                  # 8-byte Spill
	movabsq	$-1085102592571150095, %r10     # imm = 0xF0F0F0F0F0F0F0F1
	leaq	.Lmyl.site.30(%rip), %rcx
	leaq	.Lmyl.site.27(%rip), %r9
	movabsq	$-8543223828751151131, %rbx     # imm = 0x89705F3112A28FE5
	xorl	%r8d, %r8d
	.loc	1 0 13 is_stmt 0                # :0:13
.Ltmp2:
	.p2align	4
.LBB0_90:                               # %b35.i.preheader
                                        # =>This Loop Header: Depth=1
                                        #     Child Loop BB0_91 Depth 2
	movq	%r8, %rdx
	mulxq	%r10, %rax, %rax
	movq	%rax, %rdx
	andq	$-16, %rdx
	shrq	$4, %rax
	addq	%rdx, %rax
	movq	%r8, %r14
	subq	%rax, %r14
	xorl	%esi, %esi
	xorl	%r13d, %r13d
	.p2align	6
.LBB0_91:                               # %b35.i
                                        #   Parent Loop BB0_90 Depth=1
                                        # =>  This Inner Loop Header: Depth=2
	movq	32(%r15,%r13,8), %rdx
	imull	$-13107, %edx, %eax             # imm = 0xCCCD
	movzwl	%ax, %eax
	cmpl	$13107, %eax                    # imm = 0x3333
	jbe	.LBB0_96
# %bb.92:                               # %b2.12.i
                                        #   in Loop: Header=BB0_91 Depth=2
	addq	%r14, %rdx
	xorl	%eax, %eax
	cmpb	$1, %al
	je	.LBB0_97
.LBB0_93:                               # %"my.row_result_propagate::forwarded.exit"
                                        #   in Loop: Header=BB0_91 Depth=2
	leaq	(%rdx,%rdx,2), %rax
	incq	%rax
.LBB0_94:                               # %b36.i
                                        #   in Loop: Header=BB0_91 Depth=2
	movq	%rsi, %rdx
	addq	%rax, %rdx
	jo	.LBB0_107
# %bb.95:                               # %b36.118.i
                                        #   in Loop: Header=BB0_91 Depth=2
	incq	%r13
	movq	%rdx, %rsi
	cmpq	%r13, %r12
	jne	.LBB0_91
	jmp	.LBB0_98
.LBB0_96:                               # %b1.i249
                                        #   in Loop: Header=BB0_91 Depth=2
	movq	%rcx, %rdi
	callq	myl_core_err_trace_origin_preserve_most@PLT
	movl	$1, %edx
	movl	$1, %eax
	cmpb	$1, %al
	jne	.LBB0_93
.LBB0_97:                               # %b39.i
                                        #   in Loop: Header=BB0_91 Depth=2
	movq	%r9, %rdi
	callq	myl_core_err_trace_append_preserve_most@PLT
	leaq	(,%rdx,8), %rax
	subq	%rdx, %rax
	jmp	.LBB0_94
	.p2align	4
.LBB0_98:                               # %b33.i
                                        #   in Loop: Header=BB0_90 Depth=1
	movq	%rdx, %rsi
	addq	%rbp, %rsi
	jo	.LBB0_111
# %bb.99:                               # %b33.96.i
                                        #   in Loop: Header=BB0_90 Depth=1
	movq	%rsi, %rax
	imulq	%rbx
	addq	%rsi, %rdx
	movq	%rdx, %rax
	shrq	$63, %rax
	sarq	$29, %rdx
	addq	%rax, %rdx
	imulq	$1000000007, %rdx, %rax         # imm = 0x3B9ACA07
	subq	%rax, %rsi
	movq	%rsi, %rbp
	sarq	$63, %rbp
	andl	$1000000007, %ebp               # imm = 0x3B9ACA07
	addq	%rsi, %rbp
	incq	%r8
	cmpq	(%rsp), %r8                     # 8-byte Folded Reload
	jne	.LBB0_90
# %bb.100:                              # %b29.i
	movzbl	7(%r15), %eax
	testq	%rax, %rax
	je	.LBB0_108
# %bb.101:                              # %b29.i
	cmpq	$0, 24(%r15)
	jne	.LBB0_108
# %bb.102:                              # %push.i.i
	movq	myl_core_free_lists@GOTPCREL(%rip), %rcx
	movq	(%rcx,%rax,8), %rdx
	movq	%rdx, (%r15)
	movq	%r15, (%rcx,%rax,8)
.LBB0_103:                              # %myl_core_free.exit.i
	movq	16(%rsp), %rbx                  # 8-byte Reload
	movq	24(%rsp), %r14                  # 8-byte Reload
	leaq	.Lmyl.site.20(%rip), %rdi
	callq	myl_core_io_at@PLT
	.loc	1 53 15 is_stmt 1               # row_result_propagate.my:53:15 @[ row_result_propagate.my:1:1 ]
	movq	%rbx, %rdi
	callq	myl_core_host_check@PLT
	callq	runtime_bench_now@PLT
	movq	%rax, %rbx
	subq	%r14, %rbx
	jo	.LBB0_114
# %bb.104:                              # %b29.92.i
	.loc	1 0 15 is_stmt 0                # row_result_propagate.my:0:15
	movl	$1, %edi
	movq	%rbp, %rsi
	callq	myl_core_print_i64@PLT
	movl	$1, %edi
	callq	myl_core_print_sep@PLT
	movl	$1, %edi
	movq	%rbx, %rsi
	callq	myl_core_print_i64@PLT
	movl	$1, %edi
	callq	myl_core_print_end@PLT
	xorl	%r15d, %r15d
	movq	32(%rsp), %rbx                  # 8-byte Reload
.LBB0_105:                              # %"my.row_result_propagate::main.exit"
	movq	%rbx, %rdi
	callq	myl_core_release@PLT
	movq	%r15, %rdi
	callq	myl_core_exit@PLT
	addq	$40, %rsp
	.cfi_def_cfa_offset 56
	popq	%rbx
	.cfi_def_cfa_offset 48
	popq	%r12
	.cfi_def_cfa_offset 40
	popq	%r13
	.cfi_def_cfa_offset 32
	popq	%r14
	.cfi_def_cfa_offset 24
	popq	%r15
	.cfi_def_cfa_offset 16
	popq	%rbp
	.cfi_def_cfa_offset 8
	retq
.LBB0_73:
	.cfi_def_cfa_offset 96
	xorl	%ecx, %ecx
	xorl	%edx, %edx
	testb	$1, %cl
	jne	.LBB0_72
	jmp	.LBB0_74
.LBB0_106:                              # %call.i.i
	movl	$8, %esi
	movq	%r12, %rdi
	movq	%r8, %r14
	callq	myl_core_list_new_slow@PLT
	movq	%r14, %r8
	movq	%rax, %r15
	jmp	.LBB0_83
.LBB0_107:                              # %trap.117.i
	.loc	1 51 24 is_stmt 1               # row_result_propagate.my:51:24 @[ row_result_propagate.my:1:1 ]
	leaq	.Lmyl.site.25(%rip), %rdi
	movq	%rax, %rdx
	callq	myl_core_trap@PLT
.LBB0_108:                              # %call.i12.i
	.loc	1 0 24 is_stmt 0                # row_result_propagate.my:0:24
	movq	%r15, %rdi
	callq	myl_core_free_block@PLT
	jmp	.LBB0_103
.LBB0_109:                              # %trap.78.i
	.loc	1 37 25 is_stmt 1               # row_result_propagate.my:37:25 @[ row_result_propagate.my:1:1 ]
	leaq	.Lmyl.site.17(%rip), %rdi
	movl	$37, %edx
	callq	myl_core_trap@PLT
.LBB0_110:                              # %trap.82.i
	.loc	1 37 21                         # row_result_propagate.my:37:21 @[ row_result_propagate.my:1:1 ]
	leaq	.Lmyl.site.18(%rip), %rdi
	movq	%r8, %rsi
	movq	%r14, %rdx
	callq	myl_core_trap@PLT
.LBB0_111:                              # %trap.95.i
	.loc	1 52 30                         # row_result_propagate.my:52:30 @[ row_result_propagate.my:1:1 ]
	leaq	.Lmyl.site.22(%rip), %rdi
	movq	%rbp, %rsi
	callq	myl_core_trap@PLT
.LBB0_112:                              # %trap.43.i
	.loc	1 34 25                         # row_result_propagate.my:34:25 @[ row_result_propagate.my:1:1 ]
	leaq	.Lmyl.site.8(%rip), %rdi
	movl	$2, %esi
	callq	myl_core_trap@PLT
.LBB0_113:                              # %trap.28.i
	.loc	1 33 31                         # row_result_propagate.my:33:31 @[ row_result_propagate.my:1:1 ]
	leaq	.Lmyl.site.5(%rip), %rdi
	movl	$1, %esi
	callq	myl_core_trap@PLT
.LBB0_114:                              # %trap.91.i
	.loc	1 53 39                         # row_result_propagate.my:53:39 @[ row_result_propagate.my:1:1 ]
	leaq	.Lmyl.site.21(%rip), %rdi
	movq	%rax, %rsi
	movq	%r14, %rdx
	callq	myl_core_trap@PLT
.Ltmp3:
.Lfunc_end0:
	.size	main, .Lfunc_end0-main
	.cfi_endproc
	.section	.rodata,"a",@progbits
	.p2align	2, 0x0
.LJTI0_0:
	.long	.LBB0_16-.LJTI0_0
	.long	.LBB0_19-.LJTI0_0
	.long	.LBB0_17-.LJTI0_0
	.long	.LBB0_18-.LJTI0_0
.LJTI0_1:
	.long	.LBB0_42-.LJTI0_1
	.long	.LBB0_45-.LJTI0_1
	.long	.LBB0_43-.LJTI0_1
	.long	.LBB0_44-.LJTI0_1
.LJTI0_2:
	.long	.LBB0_67-.LJTI0_2
	.long	.LBB0_70-.LJTI0_2
	.long	.LBB0_68-.LJTI0_2
	.long	.LBB0_69-.LJTI0_2
                                        # -- End function
	.type	.Lmyl.path.5,@object            # @myl.path.5
	.p2align	4, 0x0
.Lmyl.path.5:
	.asciz	"row_result_propagate.my"
	.size	.Lmyl.path.5, 24

	.type	.Lmyl.op.5,@object              # @myl.op.5
.Lmyl.op.5:
	.asciz	"index"
	.size	.Lmyl.op.5, 6

	.type	.Lmyl.fn.5,@object              # @myl.fn.5
	.p2align	4, 0x0
.Lmyl.fn.5:
	.asciz	"row_result_propagate::main"
	.size	.Lmyl.fn.5, 27

	.type	.Lmyl.site.5,@object            # @myl.site.5
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lmyl.site.5:
	.long	2                               # 0x2
	.long	33                              # 0x21
	.long	31                              # 0x1f
	.long	64                              # 0x40
	.quad	.Lmyl.op.5
	.quad	.Lmyl.fn.5
	.quad	.Lmyl.path.5
	.size	.Lmyl.site.5, 40

	.type	.Lmyl.path.8,@object            # @myl.path.8
	.section	.rodata,"a",@progbits
	.p2align	4, 0x0
.Lmyl.path.8:
	.asciz	"row_result_propagate.my"
	.size	.Lmyl.path.8, 24

	.type	.Lmyl.op.8,@object              # @myl.op.8
.Lmyl.op.8:
	.asciz	"index"
	.size	.Lmyl.op.8, 6

	.type	.Lmyl.fn.8,@object              # @myl.fn.8
	.p2align	4, 0x0
.Lmyl.fn.8:
	.asciz	"row_result_propagate::main"
	.size	.Lmyl.fn.8, 27

	.type	.Lmyl.site.8,@object            # @myl.site.8
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lmyl.site.8:
	.long	2                               # 0x2
	.long	34                              # 0x22
	.long	25                              # 0x19
	.long	64                              # 0x40
	.quad	.Lmyl.op.8
	.quad	.Lmyl.fn.8
	.quad	.Lmyl.path.8
	.size	.Lmyl.site.8, 40

	.type	.Lmyl.path.17,@object           # @myl.path.17
	.section	.rodata,"a",@progbits
	.p2align	4, 0x0
.Lmyl.path.17:
	.asciz	"row_result_propagate.my"
	.size	.Lmyl.path.17, 24

	.type	.Lmyl.op.17,@object             # @myl.op.17
.Lmyl.op.17:
	.asciz	"mul"
	.size	.Lmyl.op.17, 4

	.type	.Lmyl.fn.17,@object             # @myl.fn.17
	.p2align	4, 0x0
.Lmyl.fn.17:
	.asciz	"row_result_propagate::main"
	.size	.Lmyl.fn.17, 27

	.type	.Lmyl.site.17,@object           # @myl.site.17
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lmyl.site.17:
	.long	0                               # 0x0
	.long	37                              # 0x25
	.long	25                              # 0x19
	.long	64                              # 0x40
	.quad	.Lmyl.op.17
	.quad	.Lmyl.fn.17
	.quad	.Lmyl.path.17
	.size	.Lmyl.site.17, 40

	.type	.Lmyl.path.18,@object           # @myl.path.18
	.section	.rodata,"a",@progbits
	.p2align	4, 0x0
.Lmyl.path.18:
	.asciz	"row_result_propagate.my"
	.size	.Lmyl.path.18, 24

	.type	.Lmyl.op.18,@object             # @myl.op.18
.Lmyl.op.18:
	.asciz	"add"
	.size	.Lmyl.op.18, 4

	.type	.Lmyl.fn.18,@object             # @myl.fn.18
	.p2align	4, 0x0
.Lmyl.fn.18:
	.asciz	"row_result_propagate::main"
	.size	.Lmyl.fn.18, 27

	.type	.Lmyl.site.18,@object           # @myl.site.18
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lmyl.site.18:
	.long	0                               # 0x0
	.long	37                              # 0x25
	.long	21                              # 0x15
	.long	64                              # 0x40
	.quad	.Lmyl.op.18
	.quad	.Lmyl.fn.18
	.quad	.Lmyl.path.18
	.size	.Lmyl.site.18, 40

	.type	.Lmyl.path.19,@object           # @myl.path.19
	.section	.rodata,"a",@progbits
	.p2align	4, 0x0
.Lmyl.path.19:
	.asciz	"row_result_propagate.my"
	.size	.Lmyl.path.19, 24

	.type	.Lmyl.op.19,@object             # @myl.op.19
.Lmyl.op.19:
	.asciz	"effect"
	.size	.Lmyl.op.19, 7

	.type	.Lmyl.fn.19,@object             # @myl.fn.19
	.p2align	4, 0x0
.Lmyl.fn.19:
	.asciz	"row_result_propagate::main"
	.size	.Lmyl.fn.19, 27

	.type	.Lmyl.site.19,@object           # @myl.site.19
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lmyl.site.19:
	.long	7                               # 0x7
	.long	39                              # 0x27
	.long	13                              # 0xd
	.long	64                              # 0x40
	.quad	.Lmyl.op.19
	.quad	.Lmyl.fn.19
	.quad	.Lmyl.path.19
	.size	.Lmyl.site.19, 40

	.type	.Lmyl.path.20,@object           # @myl.path.20
	.section	.rodata,"a",@progbits
	.p2align	4, 0x0
.Lmyl.path.20:
	.asciz	"row_result_propagate.my"
	.size	.Lmyl.path.20, 24

	.type	.Lmyl.op.20,@object             # @myl.op.20
.Lmyl.op.20:
	.asciz	"effect"
	.size	.Lmyl.op.20, 7

	.type	.Lmyl.fn.20,@object             # @myl.fn.20
	.p2align	4, 0x0
.Lmyl.fn.20:
	.asciz	"row_result_propagate::main"
	.size	.Lmyl.fn.20, 27

	.type	.Lmyl.site.20,@object           # @myl.site.20
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lmyl.site.20:
	.long	7                               # 0x7
	.long	53                              # 0x35
	.long	15                              # 0xf
	.long	64                              # 0x40
	.quad	.Lmyl.op.20
	.quad	.Lmyl.fn.20
	.quad	.Lmyl.path.20
	.size	.Lmyl.site.20, 40

	.type	.Lmyl.path.21,@object           # @myl.path.21
	.section	.rodata,"a",@progbits
	.p2align	4, 0x0
.Lmyl.path.21:
	.asciz	"row_result_propagate.my"
	.size	.Lmyl.path.21, 24

	.type	.Lmyl.op.21,@object             # @myl.op.21
.Lmyl.op.21:
	.asciz	"sub"
	.size	.Lmyl.op.21, 4

	.type	.Lmyl.fn.21,@object             # @myl.fn.21
	.p2align	4, 0x0
.Lmyl.fn.21:
	.asciz	"row_result_propagate::main"
	.size	.Lmyl.fn.21, 27

	.type	.Lmyl.site.21,@object           # @myl.site.21
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lmyl.site.21:
	.long	0                               # 0x0
	.long	53                              # 0x35
	.long	39                              # 0x27
	.long	64                              # 0x40
	.quad	.Lmyl.op.21
	.quad	.Lmyl.fn.21
	.quad	.Lmyl.path.21
	.size	.Lmyl.site.21, 40

	.type	.Lmyl.path.22,@object           # @myl.path.22
	.section	.rodata,"a",@progbits
	.p2align	4, 0x0
.Lmyl.path.22:
	.asciz	"row_result_propagate.my"
	.size	.Lmyl.path.22, 24

	.type	.Lmyl.op.22,@object             # @myl.op.22
.Lmyl.op.22:
	.asciz	"add"
	.size	.Lmyl.op.22, 4

	.type	.Lmyl.fn.22,@object             # @myl.fn.22
	.p2align	4, 0x0
.Lmyl.fn.22:
	.asciz	"row_result_propagate::main"
	.size	.Lmyl.fn.22, 27

	.type	.Lmyl.site.22,@object           # @myl.site.22
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lmyl.site.22:
	.long	0                               # 0x0
	.long	52                              # 0x34
	.long	30                              # 0x1e
	.long	64                              # 0x40
	.quad	.Lmyl.op.22
	.quad	.Lmyl.fn.22
	.quad	.Lmyl.path.22
	.size	.Lmyl.site.22, 40

	.type	.Lmyl.path.25,@object           # @myl.path.25
	.section	.rodata,"a",@progbits
	.p2align	4, 0x0
.Lmyl.path.25:
	.asciz	"row_result_propagate.my"
	.size	.Lmyl.path.25, 24

	.type	.Lmyl.op.25,@object             # @myl.op.25
.Lmyl.op.25:
	.asciz	"add"
	.size	.Lmyl.op.25, 4

	.type	.Lmyl.fn.25,@object             # @myl.fn.25
	.p2align	4, 0x0
.Lmyl.fn.25:
	.asciz	"row_result_propagate::main"
	.size	.Lmyl.fn.25, 27

	.type	.Lmyl.site.25,@object           # @myl.site.25
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lmyl.site.25:
	.long	0                               # 0x0
	.long	51                              # 0x33
	.long	24                              # 0x18
	.long	64                              # 0x40
	.quad	.Lmyl.op.25
	.quad	.Lmyl.fn.25
	.quad	.Lmyl.path.25
	.size	.Lmyl.site.25, 40

	.type	.Lmyl.path.27,@object           # @myl.path.27
	.section	.rodata,"a",@progbits
	.p2align	4, 0x0
.Lmyl.path.27:
	.asciz	"row_result_propagate.my"
	.size	.Lmyl.path.27, 24

	.type	.Lmyl.op.27,@object             # @myl.op.27
.Lmyl.op.27:
	.asciz	"? propagated"
	.size	.Lmyl.op.27, 13

	.type	.Lmyl.fn.27,@object             # @myl.fn.27
	.p2align	4, 0x0
.Lmyl.fn.27:
	.asciz	"row_result_propagate::forwarded"
	.size	.Lmyl.fn.27, 32

	.type	.Lmyl.site.27,@object           # @myl.site.27
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lmyl.site.27:
	.long	7                               # 0x7
	.long	17                              # 0x11
	.long	13                              # 0xd
	.long	0                               # 0x0
	.quad	.Lmyl.op.27
	.quad	.Lmyl.fn.27
	.quad	.Lmyl.path.27
	.size	.Lmyl.site.27, 40

	.type	.Lmyl.path.30,@object           # @myl.path.30
	.section	.rodata,"a",@progbits
	.p2align	4, 0x0
.Lmyl.path.30:
	.asciz	"row_result_propagate.my"
	.size	.Lmyl.path.30, 24

	.type	.Lmyl.op.30,@object             # @myl.op.30
	.p2align	4, 0x0
.Lmyl.op.30:
	.asciz	"Err(...) created"
	.size	.Lmyl.op.30, 17

	.type	.Lmyl.fn.30,@object             # @myl.fn.30
	.p2align	4, 0x0
.Lmyl.fn.30:
	.asciz	"row_result_propagate::checked"
	.size	.Lmyl.fn.30, 30

	.type	.Lmyl.site.30,@object           # @myl.site.30
	.section	.data.rel.ro,"aw",@progbits
	.p2align	4, 0x0
.Lmyl.site.30:
	.long	7                               # 0x7
	.long	12                              # 0xc
	.long	16                              # 0x10
	.long	0                               # 0x0
	.quad	.Lmyl.op.30
	.quad	.Lmyl.fn.30
	.quad	.Lmyl.path.30
	.size	.Lmyl.site.30, 40

	.section	.debug_abbrev,"",@progbits
	.byte	1                               # Abbreviation Code
	.byte	17                              # DW_TAG_compile_unit
	.byte	1                               # DW_CHILDREN_yes
	.byte	37                              # DW_AT_producer
	.byte	14                              # DW_FORM_strp
	.byte	19                              # DW_AT_language
	.byte	5                               # DW_FORM_data2
	.byte	3                               # DW_AT_name
	.byte	14                              # DW_FORM_strp
	.byte	16                              # DW_AT_stmt_list
	.byte	23                              # DW_FORM_sec_offset
	.ascii	"\264B"                         # DW_AT_GNU_pubnames
	.byte	25                              # DW_FORM_flag_present
	.byte	17                              # DW_AT_low_pc
	.byte	1                               # DW_FORM_addr
	.byte	18                              # DW_AT_high_pc
	.byte	6                               # DW_FORM_data4
	.byte	0                               # EOM(1)
	.byte	0                               # EOM(2)
	.byte	2                               # Abbreviation Code
	.byte	46                              # DW_TAG_subprogram
	.byte	0                               # DW_CHILDREN_no
	.byte	3                               # DW_AT_name
	.byte	14                              # DW_FORM_strp
	.byte	58                              # DW_AT_decl_file
	.byte	11                              # DW_FORM_data1
	.byte	59                              # DW_AT_decl_line
	.byte	11                              # DW_FORM_data1
	.byte	63                              # DW_AT_external
	.byte	25                              # DW_FORM_flag_present
	.byte	32                              # DW_AT_inline
	.byte	11                              # DW_FORM_data1
	.byte	0                               # EOM(1)
	.byte	0                               # EOM(2)
	.byte	3                               # Abbreviation Code
	.byte	46                              # DW_TAG_subprogram
	.byte	1                               # DW_CHILDREN_yes
	.byte	17                              # DW_AT_low_pc
	.byte	1                               # DW_FORM_addr
	.byte	18                              # DW_AT_high_pc
	.byte	6                               # DW_FORM_data4
	.byte	64                              # DW_AT_frame_base
	.byte	24                              # DW_FORM_exprloc
	.byte	3                               # DW_AT_name
	.byte	14                              # DW_FORM_strp
	.byte	58                              # DW_AT_decl_file
	.byte	11                              # DW_FORM_data1
	.byte	59                              # DW_AT_decl_line
	.byte	11                              # DW_FORM_data1
	.byte	63                              # DW_AT_external
	.byte	25                              # DW_FORM_flag_present
	.byte	0                               # EOM(1)
	.byte	0                               # EOM(2)
	.byte	4                               # Abbreviation Code
	.byte	29                              # DW_TAG_inlined_subroutine
	.byte	0                               # DW_CHILDREN_no
	.byte	49                              # DW_AT_abstract_origin
	.byte	19                              # DW_FORM_ref4
	.byte	17                              # DW_AT_low_pc
	.byte	1                               # DW_FORM_addr
	.byte	18                              # DW_AT_high_pc
	.byte	6                               # DW_FORM_data4
	.byte	88                              # DW_AT_call_file
	.byte	11                              # DW_FORM_data1
	.byte	89                              # DW_AT_call_line
	.byte	11                              # DW_FORM_data1
	.byte	87                              # DW_AT_call_column
	.byte	11                              # DW_FORM_data1
	.byte	0                               # EOM(1)
	.byte	0                               # EOM(2)
	.byte	0                               # EOM(3)
	.section	.debug_info,"",@progbits
.Lcu_begin0:
	.long	.Ldebug_info_end0-.Ldebug_info_start0 # Length of Unit
.Ldebug_info_start0:
	.short	4                               # DWARF version number
	.long	.debug_abbrev                   # Offset Into Abbrev. Section
	.byte	8                               # Address Size (in bytes)
	.byte	1                               # Abbrev [1] 0xb:0x4e DW_TAG_compile_unit
	.long	.Linfo_string0                  # DW_AT_producer
	.short	12                              # DW_AT_language
	.long	.Linfo_string1                  # DW_AT_name
	.long	.Lline_table_start0             # DW_AT_stmt_list
                                        # DW_AT_GNU_pubnames
	.quad	.Lfunc_begin0                   # DW_AT_low_pc
	.long	.Lfunc_end0-.Lfunc_begin0       # DW_AT_high_pc
	.byte	2                               # Abbrev [2] 0x26:0x8 DW_TAG_subprogram
	.long	.Linfo_string2                  # DW_AT_name
	.byte	1                               # DW_AT_decl_file
	.byte	29                              # DW_AT_decl_line
                                        # DW_AT_external
	.byte	1                               # DW_AT_inline
	.byte	3                               # Abbrev [3] 0x2e:0x2a DW_TAG_subprogram
	.quad	.Lfunc_begin0                   # DW_AT_low_pc
	.long	.Lfunc_end0-.Lfunc_begin0       # DW_AT_high_pc
	.byte	1                               # DW_AT_frame_base
	.byte	87
	.long	.Linfo_string3                  # DW_AT_name
	.byte	1                               # DW_AT_decl_file
	.byte	1                               # DW_AT_decl_line
                                        # DW_AT_external
	.byte	4                               # Abbrev [4] 0x43:0x14 DW_TAG_inlined_subroutine
	.long	38                              # DW_AT_abstract_origin
	.quad	.Ltmp1                          # DW_AT_low_pc
	.long	.Ltmp3-.Ltmp1                   # DW_AT_high_pc
	.byte	1                               # DW_AT_call_file
	.byte	1                               # DW_AT_call_line
	.byte	1                               # DW_AT_call_column
	.byte	0                               # End Of Children Mark
	.byte	0                               # End Of Children Mark
.Ldebug_info_end0:
	.section	.debug_str,"MS",@progbits,1
.Linfo_string0:
	.asciz	"mylang-core"                   # string offset=0
.Linfo_string1:
	.asciz	"row_result_propagate.my"       # string offset=12
.Linfo_string2:
	.asciz	"row_result_propagate::main"    # string offset=36
.Linfo_string3:
	.asciz	"myl.entry"                     # string offset=63
	.section	.debug_pubnames,"",@progbits
	.long	.LpubNames_end0-.LpubNames_start0 # Length of Public Names Info
.LpubNames_start0:
	.short	2                               # DWARF Version
	.long	.Lcu_begin0                     # Offset of Compilation Unit Info
	.long	89                              # Compilation Unit Length
	.long	38                              # DIE offset
	.asciz	"row_result_propagate::main"    # External Name
	.long	46                              # DIE offset
	.asciz	"myl.entry"                     # External Name
	.long	0                               # End Mark
.LpubNames_end0:
	.section	.debug_pubtypes,"",@progbits
	.long	.LpubTypes_end0-.LpubTypes_start0 # Length of Public Types Info
.LpubTypes_start0:
	.short	2                               # DWARF Version
	.long	.Lcu_begin0                     # Offset of Compilation Unit Info
	.long	89                              # Compilation Unit Length
	.long	0                               # End Mark
.LpubTypes_end0:
	.section	".note.GNU-stack","",@progbits
	.addrsig
	.addrsig_sym .Lmyl.path.5
	.addrsig_sym .Lmyl.op.5
	.addrsig_sym .Lmyl.fn.5
	.addrsig_sym .Lmyl.site.5
	.addrsig_sym .Lmyl.path.8
	.addrsig_sym .Lmyl.op.8
	.addrsig_sym .Lmyl.fn.8
	.addrsig_sym .Lmyl.site.8
	.addrsig_sym .Lmyl.path.17
	.addrsig_sym .Lmyl.op.17
	.addrsig_sym .Lmyl.fn.17
	.addrsig_sym .Lmyl.site.17
	.addrsig_sym .Lmyl.path.18
	.addrsig_sym .Lmyl.op.18
	.addrsig_sym .Lmyl.fn.18
	.addrsig_sym .Lmyl.site.18
	.addrsig_sym .Lmyl.path.19
	.addrsig_sym .Lmyl.op.19
	.addrsig_sym .Lmyl.fn.19
	.addrsig_sym .Lmyl.site.19
	.addrsig_sym .Lmyl.path.20
	.addrsig_sym .Lmyl.op.20
	.addrsig_sym .Lmyl.fn.20
	.addrsig_sym .Lmyl.site.20
	.addrsig_sym .Lmyl.path.21
	.addrsig_sym .Lmyl.op.21
	.addrsig_sym .Lmyl.fn.21
	.addrsig_sym .Lmyl.site.21
	.addrsig_sym .Lmyl.path.22
	.addrsig_sym .Lmyl.op.22
	.addrsig_sym .Lmyl.fn.22
	.addrsig_sym .Lmyl.site.22
	.addrsig_sym .Lmyl.path.25
	.addrsig_sym .Lmyl.op.25
	.addrsig_sym .Lmyl.fn.25
	.addrsig_sym .Lmyl.site.25
	.addrsig_sym .Lmyl.path.27
	.addrsig_sym .Lmyl.op.27
	.addrsig_sym .Lmyl.fn.27
	.addrsig_sym .Lmyl.site.27
	.addrsig_sym .Lmyl.path.30
	.addrsig_sym .Lmyl.op.30
	.addrsig_sym .Lmyl.fn.30
	.addrsig_sym .Lmyl.site.30
	.section	.debug_line,"",@progbits
.Lline_table_start0:
