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
	movq %r13, %rsi
	movq %r12, %rdi
	xchgq %rax, %rbx
	.loc 1 1
	cmpq $0, %rsi
	setnz %r8b
	movzbl %r8b, %r8d
	movl $0, %ecx
	movl $0, %edx
	cmpl $0, %r8d
	jz .Lbb5
	movq -16(%rsi), %r8
	movq $4611686018427387906, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb5
	movq -24(%rsi), %r8
	addq $1, %r8
	jz .Lbb4
	movq %r8, -24(%rsi)
	jmp .Lbb5
.Lbb4:
	.loc 1 4
	movl $2, %esi
	callq myl_qbe_rc_status
	movl $0, %eax
	jmp .Lbb55
.Lbb5:
	cmpl $0, %edx
	jz .Lbb23
	testl $28, %ecx
	jnz .Lbb15
	movq -16(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb23
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jnz .Lbb14
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb13
	movq %rax, %r12
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb12
	.loc 1 4
	movq %rsi, %r14
	leaq -16(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_277089d91c0bdf4f2e6862ba7e4a07605119431f5d13f726dd352b06f1b206a9_rcg_drop
	movq %r14, %rsi
	movq %r13, %rdi
	movq %r12, %rax
	jmp .Lbb23
.Lbb12:
	movq %r12, %rax
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
	movq $4611686018427387906, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jnz .Lbb22
	movq -24(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb21
	movq %rax, %r12
	movq -32(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb20
	.loc 1 4
	movq %rsi, %r14
	leaq -16(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_277089d91c0bdf4f2e6862ba7e4a07605119431f5d13f726dd352b06f1b206a9_rcg_unloan
	movq %r14, %rsi
	movq %r13, %rdi
	movq %r12, %rax
	jmp .Lbb23
.Lbb20:
	movq %r12, %rax
.Lbb21:
	movq %rcx, -24(%rdx)
.Lbb22:
	movq $0, -16(%rbp)
.Lbb23:
	movq %rsi, -16(%rbp)
	movq %rsi, -8(%rbp)
	movq %rax, %r12
	movq (%rsi), %rax
	cmpq $0, %rax
	setg %cl
	movzbq %cl, %rcx
	cmpq $16, %rax
	setae %dl
	movzbq %dl, %rdx
	testq %rcx, %rdx
	jnz .Lbb25
	movq %r12, %rdx
	movl $0, %r9d
	jmp .Lbb29
.Lbb25:
	movq $4503599627370496, %rcx
	movq %rax, %rdx
	addq %rcx, %rdx
	movq $9007199254740992, %rcx
	cmpq %rcx, %rdx
	jbe .Lbb27
	movq %r12, %rdx
	movl $0, %r9d
	jmp .Lbb29
.Lbb27:
	movq $4503599627370496, %rcx
	movq %r12, %rdx
	addq %rcx, %rdx
	movq $9007199254740992, %rcx
	cmpq %rcx, %rdx
	jbe .Lbb42
	movq %r12, %rdx
	movl $0, %r9d
.p2align 4
.Lbb29:
	cmpq %rax, %r9
	jge .Lbb47
	movq (%rsi), %rcx
	cmpq %rcx, %rax
	jnz .Lbb41
	cmpq %rcx, %r9
	jae .Lbb39
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
	jl .Lbb37
	movq $9223372036854775806, %rcx
	cmpq %rcx, %r9
	jg .Lbb35
	addq $1, %r9
	jmp .Lbb29
.Lbb35:
	movq %r9, %rsi
	.loc 1 30
	movl $64, %r8d
	movl $1, %ecx
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb37:
	movq %r12, %rdx
	.loc 1 23
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb39:
	movq %r9, %rsi
	movq %rcx, %rdx
	.loc 1 18
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb41:
	.loc 1 15
	callq myl_qbe_fail_iteration
	ud2
.Lbb42:
	movq %rbx, %rdi
	movq %rdi, %rbx
	movq 32(%rsi), %rdi
	movq %r12, %rdx
	movl $0, %ecx
.p2align 4
.Lbb45:
	cmpq %rax, %rcx
	jge .Lbb47
	movzbq (%rdi, %rcx, 1), %r8
	addq %r8, %rdx
	addq $1, %rcx
	jmp .Lbb45
.Lbb47:
	movq %rbx, %rdi
	movq %rdx, %rax
	cmpq $0, %rsi
	jz .Lbb55
	movq -16(%rsi), %rcx
	movq $4611686018427387906, %rdx
	andq %rdx, %rcx
	cmpq $0, %rcx
	jnz .Lbb54
	movq -24(%rsi), %rcx
	subq $1, %rcx
	jnz .Lbb53
	movq %rax, %rbx
	movq -32(%rsi), %rax
	cmpq $0, %rax
	jnz .Lbb52
	.loc 1 34
	leaq -8(%rbp), %rsi
	callq myl_t_277089d91c0bdf4f2e6862ba7e4a07605119431f5d13f726dd352b06f1b206a9_rcg_unloan
	movq %rbx, %rax
	jmp .Lbb55
.Lbb52:
	movq %rbx, %rax
.Lbb53:
	movq %rcx, -24(%rsi)
.Lbb54:
	movq $0, -8(%rbp)
.Lbb55:
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
