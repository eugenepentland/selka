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
	movq %r13, %rsi
	movq %r12, %rdi
	xchgq %rax, %rbx
	.loc 1 1
	cmpq $0, %rsi
	setnz %r9b
	movzbl %r9b, %r9d
	movl $0, %ecx
	movl $0, %r8d
	cmpl $0, %r9d
	jz .Lbb5
	movq -16(%rsi), %r9
	movq $4611686018427387906, %r10
	andq %r10, %r9
	cmpq $0, %r9
	jnz .Lbb5
	movq -24(%rsi), %r9
	addq $1, %r9
	jz .Lbb4
	movq %r9, -24(%rsi)
	jmp .Lbb5
.Lbb4:
	.loc 1 4
	movl $2, %esi
	callq myl_qbe_rc_status
	movl $0, %eax
	jmp .Lbb57
.Lbb5:
	cmpl $0, %r8d
	jz .Lbb25
	testl $28, %ecx
	jnz .Lbb16
	movq -16(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb25
	movq -16(%r8), %rcx
	movq %rdx, %r15
	movq $4611686018427387906, %rdx
	andq %rdx, %rcx
	cmpq $0, %rcx
	jnz .Lbb14
	movq -32(%r8), %rcx
	subq $1, %rcx
	jnz .Lbb13
	movq %rax, %r12
	movq -24(%r8), %rax
	cmpq $0, %rax
	jnz .Lbb12
	.loc 1 4
	movq %rsi, %r14
	leaq -16(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_277089d91c0bdf4f2e6862ba7e4a07605119431f5d13f726dd352b06f1b206a9_rcg_drop
	movq %r15, %rdx
	movq %r14, %rsi
	movq %r13, %rdi
	movq %r12, %rax
	jmp .Lbb25
.Lbb12:
	movq %r12, %rax
.Lbb13:
	movq %r15, %rdx
	movq %rcx, -32(%r8)
	jmp .Lbb15
.Lbb14:
	movq %r15, %rdx
.Lbb15:
	movq $0, -16(%rbp)
	jmp .Lbb25
.Lbb16:
	movq -16(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb25
	movq -16(%r8), %rcx
	movq %rdx, %r15
	movq $4611686018427387906, %rdx
	andq %rdx, %rcx
	cmpq $0, %rcx
	jnz .Lbb23
	movq -24(%r8), %rcx
	subq $1, %rcx
	jnz .Lbb22
	movq %rax, %r12
	movq -32(%r8), %rax
	cmpq $0, %rax
	jnz .Lbb21
	.loc 1 4
	movq %rsi, %r14
	leaq -16(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_277089d91c0bdf4f2e6862ba7e4a07605119431f5d13f726dd352b06f1b206a9_rcg_unloan
	movq %r15, %rdx
	movq %r14, %rsi
	movq %r13, %rdi
	movq %r12, %rax
	jmp .Lbb25
.Lbb21:
	movq %r12, %rax
.Lbb22:
	movq %r15, %rdx
	movq %rcx, -24(%r8)
	jmp .Lbb24
.Lbb23:
	movq %r15, %rdx
.Lbb24:
	movq $0, -16(%rbp)
.Lbb25:
	movq %rsi, -16(%rbp)
	movq %rsi, -8(%rbp)
	movq %rax, %r12
	movq (%rsi), %rax
	cmpq $0, %rax
	setg %cl
	movzbq %cl, %rcx
	cmpq $16, %rax
	setae %r8b
	movzbq %r8b, %r8
	testq %rcx, %r8
	jnz .Lbb27
	movq %r12, %rcx
	movl $0, %r9d
	jmp .Lbb29
.Lbb27:
	movq $1152921504606846976, %rcx
	movq %rax, %r8
	addq %rcx, %r8
	movq $2305843009213693952, %rcx
	cmpq %rcx, %r8
	jbe .Lbb42
	movq %r12, %rcx
	movl $0, %r9d
.p2align 4
.Lbb29:
	cmpq %rax, %r9
	jge .Lbb49
	movq (%rsi), %r8
	cmpq %r8, %rax
	jnz .Lbb41
	cmpq %r8, %r9
	jae .Lbb39
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
	jl .Lbb37
	movq $9223372036854775806, %r8
	cmpq %r8, %r9
	jg .Lbb35
	addq $1, %r9
	jmp .Lbb29
.Lbb35:
	movq %r9, %rsi
	.loc 1 32
	movl $64, %r8d
	movl $1, %ecx
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb37:
	movq %r12, %rax
	movq %r10, %rcx
	.loc 1 25
	movl $64, %r8d
	movq %rax, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb39:
	movq %r9, %rsi
	movq %r8, %rdx
	.loc 1 18
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb41:
	.loc 1 15
	callq myl_qbe_fail_iteration
	ud2
.Lbb42:
	movq 32(%rsi), %r9
	movq %r12, %rcx
	movl $0, %r8d
.p2align 4
.Lbb44:
	cmpq %rax, %r8
	jge .Lbb49
	movzbq (%r9, %r8, 1), %r10
	xorq %rdx, %r10
	movq %rcx, %r12
	addq %r10, %rcx
	movq %r12, %r11
	xorq %rcx, %r11
	movq %r10, %r13
	xorq %rcx, %r13
	andq %r13, %r11
	cmpq $0, %r11
	jl .Lbb47
	addq $1, %r8
	jmp .Lbb44
.Lbb47:
	movq %r12, %rax
	movq %r10, %rcx
	.loc 1 25
	movl $64, %r8d
	movq %rax, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb49:
	movq %rbx, %rdi
	movq %rcx, %rax
	cmpq $0, %rsi
	jz .Lbb57
	movq -16(%rsi), %rcx
	movq $4611686018427387906, %rdx
	andq %rdx, %rcx
	cmpq $0, %rcx
	jnz .Lbb56
	movq -24(%rsi), %rcx
	subq $1, %rcx
	jnz .Lbb55
	movq %rax, %rbx
	movq -32(%rsi), %rax
	cmpq $0, %rax
	jnz .Lbb54
	.loc 1 36
	leaq -8(%rbp), %rsi
	callq myl_t_277089d91c0bdf4f2e6862ba7e4a07605119431f5d13f726dd352b06f1b206a9_rcg_unloan
	movq %rbx, %rax
	jmp .Lbb57
.Lbb54:
	movq %rbx, %rax
.Lbb55:
	movq %rcx, -24(%rsi)
.Lbb56:
	movq $0, -8(%rbp)
.Lbb57:
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
