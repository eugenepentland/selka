.file 1 "myl_f_79c6ce3bce682344e8fe030ab7695766dcd45431d0846c04f94423f31b0a332f"
.text
.balign 16
.globl myl_f_79c6ce3bce682344e8fe030ab7695766dcd45431d0846c04f94423f31b0a332f
myl_f_79c6ce3bce682344e8fe030ab7695766dcd45431d0846c04f94423f31b0a332f:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $24, %rsp
	pushq %rbx
	pushq %r12
	pushq %r13
	pushq %r14
	pushq %r15
	movq %rcx, %rbx
	movq %rdx, %r14
	movq %rsi, %r13
	movq $0, -8(%rbp)
	.loc 1 1
	movq %rdi, %r12
	callq myl_qbe_heap
	movq %r14, %rdx
	movq %r12, %rdi
	movq %rax, %r12
	movq %rbx, %rax
	.loc 1 1
	cmpq $0, %r13
	setnz %r8b
	movzbl %r8b, %r8d
	movl $0, %ecx
	movl $0, %esi
	cmpl $0, %r8d
	jz .Lbb5
	movq -16(%r13), %r8
	movq $4611686018427387906, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb5
	movq -24(%r13), %r8
	addq $1, %r8
	jz .Lbb4
	movq %r8, -24(%r13)
	jmp .Lbb5
.Lbb4:
	.loc 1 4
	movl $2, %esi
	callq myl_qbe_rc_status
	movl $0, %eax
	jmp .Lbb59
.Lbb5:
	cmpl $0, %esi
	jz .Lbb25
	testl $28, %ecx
	jnz .Lbb16
	movq -16(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb25
	movq -16(%rsi), %rcx
	movq %rdx, %r15
	movq $4611686018427387906, %rdx
	andq %rdx, %rcx
	cmpq $0, %rcx
	jnz .Lbb14
	movq -32(%rsi), %rcx
	subq $1, %rcx
	jnz .Lbb13
	movq %rax, %rbx
	movq -24(%rsi), %rax
	cmpq $0, %rax
	jnz .Lbb12
	.loc 1 4
	leaq -16(%rbp), %rsi
	movq %rdi, %r14
	movq %r12, %rdi
	callq myl_t_277089d91c0bdf4f2e6862ba7e4a07605119431f5d13f726dd352b06f1b206a9_rcg_drop
	movq %r15, %rdx
	movq %r14, %rdi
	movq %rbx, %rax
	jmp .Lbb25
.Lbb12:
	movq %rbx, %rax
.Lbb13:
	movq %r15, %rdx
	movq %rcx, -32(%rsi)
	jmp .Lbb15
.Lbb14:
	movq %r15, %rdx
.Lbb15:
	movq $0, -16(%rbp)
	jmp .Lbb25
.Lbb16:
	movq -16(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb25
	movq -16(%rsi), %rcx
	movq %rdx, %r15
	movq $4611686018427387906, %rdx
	andq %rdx, %rcx
	cmpq $0, %rcx
	jnz .Lbb23
	movq -24(%rsi), %rcx
	subq $1, %rcx
	jnz .Lbb22
	movq %rax, %rbx
	movq -32(%rsi), %rax
	cmpq $0, %rax
	jnz .Lbb21
	.loc 1 4
	leaq -16(%rbp), %rsi
	movq %rdi, %r14
	movq %r12, %rdi
	callq myl_t_277089d91c0bdf4f2e6862ba7e4a07605119431f5d13f726dd352b06f1b206a9_rcg_unloan
	movq %r15, %rdx
	movq %r14, %rdi
	movq %rbx, %rax
	jmp .Lbb25
.Lbb21:
	movq %rbx, %rax
.Lbb22:
	movq %r15, %rdx
	movq %rcx, -24(%rsi)
	jmp .Lbb24
.Lbb23:
	movq %r15, %rdx
.Lbb24:
	movq $0, -16(%rbp)
.Lbb25:
	movq %r13, -16(%rbp)
	movq %r13, -8(%rbp)
	movq (%r13), %rsi
	cmpq $0, %rsi
	setg %cl
	movzbq %cl, %rcx
	cmpq $16, %rsi
	setae %r8b
	movzbq %r8b, %r8
	testq %rcx, %r8
	jnz .Lbb27
	movq %r12, %rbx
	movq %rax, %rcx
	movq %rsi, %rax
	movl $0, %r9d
	movq %r13, %rsi
	jmp .Lbb35
.Lbb27:
	movq $1152921504606846976, %r8
	movq %rsi, %r9
	addq %r8, %r9
	movq $2305843009213693952, %r8
	cmpq %r8, %r9
	jbe .Lbb29
	movq %r12, %rbx
	movq %rax, %rcx
	movq %rsi, %rax
	movl $0, %r9d
	movq %r13, %rsi
	jmp .Lbb35
.Lbb29:
	movq %rax, %rbx
	movq 32(%r13), %rax
	cmpq $255, %rdx
	jbe .Lbb31
	movq %rsi, %rax
	movq %rbx, %rcx
	movq %r12, %rbx
	movl $0, %r9d
	movq %r13, %rsi
	jmp .Lbb35
.Lbb31:
	movq $36170086419038336, %r8
	cmpq %r8, %rsi
	setbe %r8b
	movzbq %r8b, %r8
	testq %rcx, %r8
	jnz .Lbb33
	movq %rsi, %rax
	movq %rbx, %rcx
	movq %r12, %rbx
	movl $0, %r9d
	movq %r13, %rsi
	jmp .Lbb35
.Lbb33:
	imulq $255, %rsi, %r8
	movq $9223372036854775807, %rcx
	subq %r8, %rcx
	cmpq %rcx, %rbx
	jle .Lbb49
	movq %rsi, %rax
	movq %rbx, %rcx
	movq %r12, %rbx
	movl $0, %r9d
	movq %r13, %rsi
.p2align 4
.Lbb35:
	cmpq %rax, %r9
	jge .Lbb48
	movq (%rsi), %r8
	cmpq %r8, %rax
	jnz .Lbb47
	cmpq %r8, %r9
	jae .Lbb45
	movq 32(%rsi), %r8
	movzbq (%r8, %r9, 1), %r8
	movq %rdx, %r10
	xorq %r8, %r10
	movq %rcx, %r12
	addq %r10, %rcx
	movq %r12, %r8
	xorq %rcx, %r8
	movq %r10, %r11
	xorq %rcx, %r11
	andq %r11, %r8
	cmpq $0, %r8
	jl .Lbb43
	movq $9223372036854775806, %r8
	cmpq %r8, %r9
	jg .Lbb41
	addq $1, %r9
	jmp .Lbb35
.Lbb41:
	movq %r9, %rsi
	.loc 1 32
	movl $64, %r8d
	movl $1, %ecx
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb43:
	movq %r12, %rax
	movq %r10, %rcx
	.loc 1 25
	movl $64, %r8d
	movq %rax, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb45:
	movq %r9, %rsi
	movq %r8, %rdx
	.loc 1 18
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb47:
	.loc 1 15
	callq myl_qbe_fail_iteration
	ud2
.Lbb48:
	movq %rbx, %rdi
	movq %rcx, %rax
	jmp .Lbb51
.Lbb49:
	movq %rax, %rdi
	.loc 1 10
	callq myl_native_bytes_sum_xor
	movq %r12, %rdi
	movq %rax, %rcx
	movq %rbx, %rax
	addq %rcx, %rax
.Lbb51:
	movq -8(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb59
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb58
	movq -24(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb57
	movq %rax, %rbx
	movq -32(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb56
	.loc 1 36
	leaq -8(%rbp), %rsi
	callq myl_t_277089d91c0bdf4f2e6862ba7e4a07605119431f5d13f726dd352b06f1b206a9_rcg_unloan
	movq %rbx, %rax
	jmp .Lbb59
.Lbb56:
	movq %rbx, %rax
.Lbb57:
	movq %rcx, -24(%rdx)
.Lbb58:
	movq $0, -8(%rbp)
.Lbb59:
	popq %r15
	popq %r14
	popq %r13
	popq %r12
	popq %rbx
	leave
	ret
.type myl_f_79c6ce3bce682344e8fe030ab7695766dcd45431d0846c04f94423f31b0a332f, @function
.size myl_f_79c6ce3bce682344e8fe030ab7695766dcd45431d0846c04f94423f31b0a332f, .-myl_f_79c6ce3bce682344e8fe030ab7695766dcd45431d0846c04f94423f31b0a332f
/* end function myl_f_79c6ce3bce682344e8fe030ab7695766dcd45431d0846c04f94423f31b0a332f */

.section .note.GNU-stack,"",@progbits
