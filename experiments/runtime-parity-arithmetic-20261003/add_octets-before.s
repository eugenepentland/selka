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
	jmp .Lbb47
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
	movq %r12, %rdx
	movl $0, %r9d
.p2align 4
.Lbb25:
	cmpq %rax, %r9
	jge .Lbb38
	movq (%rsi), %rcx
	cmpq %rcx, %rax
	jnz .Lbb37
	cmpq %rcx, %r9
	jae .Lbb35
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
	jl .Lbb33
	movq $9223372036854775806, %rcx
	cmpq %rcx, %r9
	jg .Lbb31
	addq $1, %r9
	jmp .Lbb25
.Lbb31:
	movq %r9, %rsi
	.loc 1 30
	movl $64, %r8d
	movl $1, %ecx
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb33:
	movq %r12, %rax
	.loc 1 23
	movl $64, %r8d
	movq %rax, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb35:
	movq %r9, %rsi
	movq %rcx, %rdx
	.loc 1 18
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb37:
	.loc 1 15
	callq myl_qbe_fail_iteration
	ud2
.Lbb38:
	movq %rdx, %rax
	movq %rbx, %rdi
	cmpq $0, %rsi
	jz .Lbb47
	movq -16(%rsi), %rcx
	movq $4611686018427387906, %rdx
	andq %rdx, %rcx
	cmpq $0, %rcx
	jnz .Lbb46
	movq -24(%rsi), %rcx
	subq $1, %rcx
	jnz .Lbb45
	movq %rax, %rbx
	movq -32(%rsi), %rax
	cmpq $0, %rax
	jnz .Lbb44
	.loc 1 34
	leaq -8(%rbp), %rsi
	callq myl_t_277089d91c0bdf4f2e6862ba7e4a07605119431f5d13f726dd352b06f1b206a9_rcg_unloan
	movq %rbx, %rax
	jmp .Lbb47
.Lbb44:
	movq %rbx, %rax
.Lbb45:
	movq %rcx, -24(%rsi)
.Lbb46:
	movq $0, -8(%rbp)
.Lbb47:
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
