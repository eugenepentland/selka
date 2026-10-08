.file 1 "myl_f_0e91d8ceeecff252be7bb71a2bd2d556518988052d3f7bf778b373334a5acad6"
.text
.balign 16
.globl myl_f_0e91d8ceeecff252be7bb71a2bd2d556518988052d3f7bf778b373334a5acad6
myl_f_0e91d8ceeecff252be7bb71a2bd2d556518988052d3f7bf778b373334a5acad6:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $16, %rsp
	pushq %rbx
	pushq %r12
	pushq %r13
	pushq %r14
	movq %rdx, %rbx
	movq %rsi, %r13
	movq $0, -8(%rbp)
	.loc 1 1
	movq %rdi, %r12
	callq myl_qbe_heap
	movq %r12, %rdi
	movq %rax, %r12
	movq %rbx, %rax
	.loc 1 1
	cmpq $0, %r13
	setnz %sil
	movzbl %sil, %esi
	movl $0, %ecx
	movl $0, %edx
	cmpl $0, %esi
	jz .Lbb5
	movq -16(%r13), %rsi
	movq $4611686018427387906, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb5
	movq -24(%r13), %rsi
	addq $1, %rsi
	jz .Lbb4
	movq %rsi, -24(%r13)
	jmp .Lbb5
.Lbb4:
	.loc 1 4
	movl $2, %esi
	callq myl_qbe_rc_status
	movl $0, %eax
	jmp .Lbb57
.Lbb5:
	cmpl $0, %edx
	jz .Lbb23
	testl $28, %ecx
	jnz .Lbb15
	movq -16(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb23
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb14
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb13
	movq %rax, %rbx
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb12
	.loc 1 4
	leaq -16(%rbp), %rsi
	movq %rdi, %r14
	movq %r12, %rdi
	callq myl_t_277089d91c0bdf4f2e6862ba7e4a07605119431f5d13f726dd352b06f1b206a9_rcg_drop
	movq %r14, %rdi
	movq %rbx, %rax
	jmp .Lbb23
.Lbb12:
	movq %rbx, %rax
.Lbb13:
	movq %rcx, -32(%rdx)
.Lbb14:
	movq $0, -16(%rbp)
	jmp .Lbb23
.Lbb15:
	movq -16(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb23
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb22
	movq -24(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb21
	movq %rax, %rbx
	movq -32(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb20
	.loc 1 4
	leaq -16(%rbp), %rsi
	movq %rdi, %r14
	movq %r12, %rdi
	callq myl_t_277089d91c0bdf4f2e6862ba7e4a07605119431f5d13f726dd352b06f1b206a9_rcg_unloan
	movq %r14, %rdi
	movq %rbx, %rax
	jmp .Lbb23
.Lbb20:
	movq %rbx, %rax
.Lbb21:
	movq %rcx, -24(%rdx)
.Lbb22:
	movq $0, -16(%rbp)
.Lbb23:
	movq %r13, -16(%rbp)
	movq %r13, -8(%rbp)
	movq (%r13), %rsi
	cmpq $0, %rsi
	setg %cl
	movzbq %cl, %rcx
	cmpq $16, %rsi
	setae %dl
	movzbq %dl, %rdx
	testq %rcx, %rdx
	jnz .Lbb25
	movq %r12, %rbx
	movq %rax, %rdx
	movq %rsi, %rax
	movl $0, %r9d
	movq %r13, %rsi
	jmp .Lbb33
.Lbb25:
	movq $4503599627370496, %rdx
	movq %rsi, %r8
	addq %rdx, %r8
	movq $9007199254740992, %rdx
	cmpq %rdx, %r8
	jbe .Lbb27
	movq %r12, %rbx
	movq %rax, %rdx
	movq %rsi, %rax
	movl $0, %r9d
	movq %r13, %rsi
	jmp .Lbb33
.Lbb27:
	movq $4503599627370496, %rdx
	movq %rax, %r8
	addq %rdx, %r8
	movq $9007199254740992, %rdx
	cmpq %rdx, %r8
	jbe .Lbb29
	movq %r12, %rbx
	movq %rax, %rdx
	movq %rsi, %rax
	movl $0, %r9d
	movq %r13, %rsi
	jmp .Lbb33
.Lbb29:
	movq %rax, %rbx
	movq 32(%r13), %rax
	movq $36170086419038336, %rdx
	cmpq %rdx, %rsi
	setbe %dl
	movzbq %dl, %rdx
	testq %rcx, %rdx
	jnz .Lbb31
	movq %rsi, %rax
	movq %rbx, %rdx
	movq %r12, %rbx
	movl $0, %r9d
	movq %r13, %rsi
	jmp .Lbb33
.Lbb31:
	imulq $255, %rsi, %rdx
	movq $9223372036854775807, %rcx
	subq %rdx, %rcx
	cmpq %rcx, %rbx
	jle .Lbb47
	movq %rsi, %rax
	movq %rbx, %rdx
	movq %r12, %rbx
	movl $0, %r9d
	movq %r13, %rsi
.p2align 4
.Lbb33:
	cmpq %rax, %r9
	jge .Lbb46
	movq (%rsi), %rcx
	cmpq %rcx, %rax
	jnz .Lbb45
	cmpq %rcx, %r9
	jae .Lbb43
	movq 32(%rsi), %rcx
	movzbq (%rcx, %r9, 1), %rcx
	movq %rdx, %r12
	addq %rcx, %rdx
	movq %r12, %r8
	xorq %rdx, %r8
	movq %rcx, %r10
	xorq %rdx, %r10
	andq %r10, %r8
	cmpq $0, %r8
	jl .Lbb41
	movq $9223372036854775806, %rcx
	cmpq %rcx, %r9
	jg .Lbb39
	addq $1, %r9
	jmp .Lbb33
.Lbb39:
	movq %r9, %rsi
	.loc 1 30
	movl $64, %r8d
	movl $1, %ecx
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb41:
	movq %r12, %rdx
	.loc 1 23
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb43:
	movq %r9, %rsi
	movq %rcx, %rdx
	.loc 1 18
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb45:
	.loc 1 15
	callq myl_qbe_fail_iteration
	ud2
.Lbb46:
	movq %rbx, %rdi
	movq %rdx, %rax
	jmp .Lbb49
.Lbb47:
	movq %rax, %rdi
	.loc 1 10
	movl $0, %edx
	callq myl_native_bytes_sum_xor
	movq %r12, %rdi
	movq %rax, %rcx
	movq %rbx, %rax
	addq %rcx, %rax
.Lbb49:
	movq -8(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb57
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb56
	movq -24(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb55
	movq %rax, %rbx
	movq -32(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb54
	.loc 1 34
	leaq -8(%rbp), %rsi
	callq myl_t_277089d91c0bdf4f2e6862ba7e4a07605119431f5d13f726dd352b06f1b206a9_rcg_unloan
	movq %rbx, %rax
	jmp .Lbb57
.Lbb54:
	movq %rbx, %rax
.Lbb55:
	movq %rcx, -24(%rdx)
.Lbb56:
	movq $0, -8(%rbp)
.Lbb57:
	popq %r14
	popq %r13
	popq %r12
	popq %rbx
	leave
	ret
.type myl_f_0e91d8ceeecff252be7bb71a2bd2d556518988052d3f7bf778b373334a5acad6, @function
.size myl_f_0e91d8ceeecff252be7bb71a2bd2d556518988052d3f7bf778b373334a5acad6, .-myl_f_0e91d8ceeecff252be7bb71a2bd2d556518988052d3f7bf778b373334a5acad6
/* end function myl_f_0e91d8ceeecff252be7bb71a2bd2d556518988052d3f7bf778b373334a5acad6 */

.section .note.GNU-stack,"",@progbits
