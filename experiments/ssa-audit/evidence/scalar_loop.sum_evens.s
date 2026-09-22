.text
.balign 16
.globl myl_f_c0ce3ee4f36ab8f06139a03bba784307a3213db796e13299f160ce3c3b663044
myl_f_c0ce3ee4f36ab8f06139a03bba784307a3213db796e13299f160ce3c3b663044:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $72, %rsp
	pushq %rbx
	pushq %r12
	pushq %r13
	pushq %r14
	pushq %r15
	movq 48(%rdi), %rax
	movq %rax, -56(%rbp)
	movq myl_f_c0ce3ee4f36ab8f06139a03bba784307a3213db796e13299f160ce3c3b663044_meta@gotpcrel(%rip), %rax
	movq %rax, -48(%rbp)
	movq $0, -40(%rbp)
	leaq -56(%rbp), %rax
	movq %rax, 48(%rdi)
	movl $0, %ebx
	movl $0, %r12d
.p2align 4
.Lbb2:
	movq (%rsi), %rax
	movq $9223372036854775807, %rcx
	cmpq %rcx, %rax
	ja .Lbb23
	cmpq %rax, %r12
	jge .Lbb21
	cmpq $0, %r12
	jl .Lbb6
	movq %r12, %r13
	jmp .Lbb7
.Lbb6:
	movq %rax, %r13
	addq %r12, %r13
	movq %rax, %rcx
	xorq %r13, %rcx
	movq %r12, %rdx
	xorq %r13, %rdx
	andq %rdx, %rcx
	cmpq $0, %rcx
	jl .Lbb19
.Lbb7:
	movq $25, -40(%rbp)
	movq (%rsi), %rax
	movq %rax, -16(%rbp)
	leaq -24(%rbp), %rdx
	movq %rsi, %r15
	movq %r13, %rsi
	movq %rdi, %r14
	movq %r15, %rdi
	callq myl_native_list_get
	movq %r15, %rsi
	movq %r14, %rdi
	movl %eax, %ecx
	movq -16(%rbp), %rax
	cmpl $0, %ecx
	jz .Lbb17
	movq -24(%rbp), %rcx
	movq 32(%rdi), %rax
	cmpl $0, %eax
	jnz .Lbb25
	movq $-9223372036854775808, %rax
	cmpq %rax, %rcx
	setz %al
	movzbq %al, %rax
	andq $0, %rax
	negq %rax
	andq $3, %rax
	movq %rax, %r8
	xorq $2, %r8
	movq %rcx, %rax
	cqto
	idivq %r8
	cmpq $0, %rdx
	setnz %al
	movzbq %al, %rax
	movq %r8, %r9
	xorq %rdx, %r9
	cmpq $0, %r9
	setl %r9b
	movzbq %r9b, %r9
	andq %r9, %rax
	negq %rax
	andq %r8, %rax
	addq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb11
	movq %rbx, %r13
	addq %rcx, %rbx
	movq %r13, %rax
	xorq %rbx, %rax
	movq %rcx, %rdx
	xorq %rbx, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jl .Lbb15
.Lbb11:
	movq $9223372036854775806, %rax
	cmpq %rax, %r12
	jg .Lbb13
	addq $1, %r12
	jmp .Lbb2
.Lbb13:
	movq %r12, %rcx
	movq $39, -40(%rbp)
	movl $64, %r8d
	movq %rcx, %rbx
	movl $1, %ecx
	movq %rbx, %rdx
	movl $0, %esi
	movq %rdi, %rbx
	callq myl_qbe_fail_overflow_op
	movq %rbx, %rdi
	jmp .Lbb25
.Lbb15:
	movq %r13, %rax
	movq $35, -40(%rbp)
	movl $64, %r8d
	movq %rax, %rdx
	movl $0, %esi
	movq %rdi, %rbx
	callq myl_qbe_fail_overflow_op
	movq %rbx, %rdi
	jmp .Lbb25
.Lbb17:
	movq %rax, %rdx
	movq %r13, %rsi
	movq %rdi, %rbx
	callq myl_qbe_fail_normalized_index_bounds
	movq %rbx, %rdi
	jmp .Lbb25
.Lbb19:
	movq %r12, %rcx
	movq %rax, %rsi
	movq $22, -40(%rbp)
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	movq %rdi, %rbx
	callq myl_qbe_fail_overflow_op
	movq %rbx, %rdi
	jmp .Lbb25
.Lbb21:
	movq %rbx, %rax
	movq -56(%rbp), %rcx
	movq %rcx, 48(%rdi)
	jmp .Lbb26
.Lbb23:
	movq %rax, %rsi
	movq $8, -40(%rbp)
	movl $64, %edx
	movq %rdi, %rbx
	callq myl_qbe_fail_cast
	movq %rbx, %rdi
.Lbb25:
	movq -56(%rbp), %rax
	movq %rax, 48(%rdi)
	movl $0, %eax
.Lbb26:
	popq %r15
	popq %r14
	popq %r13
	popq %r12
	popq %rbx
	leave
	ret
.type myl_f_c0ce3ee4f36ab8f06139a03bba784307a3213db796e13299f160ce3c3b663044, @function
.size myl_f_c0ce3ee4f36ab8f06139a03bba784307a3213db796e13299f160ce3c3b663044, .-myl_f_c0ce3ee4f36ab8f06139a03bba784307a3213db796e13299f160ce3c3b663044
/* end function myl_f_c0ce3ee4f36ab8f06139a03bba784307a3213db796e13299f160ce3c3b663044 */

.section .note.GNU-stack,"",@progbits
