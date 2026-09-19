.text
.balign 16
.globl myl_f_f65050a6df54237c12e7c9b954b8f6375fc3ead4b8d97a893eee573994ea7c9f
myl_f_f65050a6df54237c12e7c9b954b8f6375fc3ead4b8d97a893eee573994ea7c9f:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $40, %rsp
	pushq %rbx
	movq 48(%rdi), %rax
	movq %rax, -32(%rbp)
	movq myl_f_f65050a6df54237c12e7c9b954b8f6375fc3ead4b8d97a893eee573994ea7c9f_meta@gotpcrel(%rip), %rax
	movq %rax, -24(%rbp)
	movq $0, -16(%rbp)
	leaq -32(%rbp), %rax
	movq %rax, 48(%rdi)
	movq 8(%rsi), %rcx
	movq (%rsi), %rax
	movq (%rax), %rax
	cmpq %rax, %rcx
	jge .Lbb13
	movq (%rsi), %rax
	movq 8(%rsi), %r8
	movq $11, -16(%rbp)
	movq (%rax), %rdx
	movq %r8, %rcx
	sarq $63, %rcx
	andq %rdx, %rcx
	addq %r8, %rcx
	cmpq %rdx, %rcx
	jb .Lbb4
	movq %r8, %rsi
	movq %rdi, %rbx
	callq myl_qbe_fail_index_bounds
	movq %rbx, %rdi
	jmp .Lbb16
.Lbb4:
	movq 32(%rax), %rax
	movzbq (%rax, %rcx, 1), %rax
	movq $12, -16(%rbp)
	movq 32(%rdi), %rcx
	cmpl $0, %ecx
	jnz .Lbb16
	cmpq $10, %rax
	setz %al
	movzbq %al, %rax
	cmpl $0, %eax
	jnz .Lbb9
	movq 24(%rsi), %rdx
	movq $36, -16(%rbp)
	movq $9223372036854775806, %rax
	cmpq %rax, %rdx
	jg .Lbb8
	movq %rdx, %rax
	addq $1, %rax
	movq %rax, 24(%rsi)
	jmp .Lbb11
.Lbb8:
	movl $64, %r8d
	movl $1, %ecx
	movl $0, %esi
	movq %rdi, %rbx
	callq myl_qbe_fail_overflow_op
	movq %rbx, %rdi
	jmp .Lbb16
.Lbb9:
	movq 16(%rsi), %rdx
	movq $20, -16(%rbp)
	movq $9223372036854775806, %rax
	cmpq %rax, %rdx
	jg .Lbb15
	movq %rdx, %rax
	addq $1, %rax
	movq %rax, 16(%rsi)
	movq $1, 24(%rsi)
.Lbb11:
	movq 8(%rsi), %rdx
	movq $45, -16(%rbp)
	movq $9223372036854775806, %rax
	cmpq %rax, %rdx
	jg .Lbb14
	movq %rdx, %rax
	addq $1, %rax
	movq %rax, 8(%rsi)
.Lbb13:
	movq -32(%rbp), %rax
	movq %rax, 48(%rdi)
	movl $0, %eax
	jmp .Lbb17
.Lbb14:
	movl $64, %r8d
	movl $1, %ecx
	movl $0, %esi
	movq %rdi, %rbx
	callq myl_qbe_fail_overflow_op
	movq %rbx, %rdi
	jmp .Lbb16
.Lbb15:
	movl $64, %r8d
	movl $1, %ecx
	movl $0, %esi
	movq %rdi, %rbx
	callq myl_qbe_fail_overflow_op
	movq %rbx, %rdi
.Lbb16:
	movq -32(%rbp), %rax
	movq %rax, 48(%rdi)
	movl $0, %eax
.Lbb17:
	popq %rbx
	leave
	ret
.type myl_f_f65050a6df54237c12e7c9b954b8f6375fc3ead4b8d97a893eee573994ea7c9f, @function
.size myl_f_f65050a6df54237c12e7c9b954b8f6375fc3ead4b8d97a893eee573994ea7c9f, .-myl_f_f65050a6df54237c12e7c9b954b8f6375fc3ead4b8d97a893eee573994ea7c9f
/* end function myl_f_f65050a6df54237c12e7c9b954b8f6375fc3ead4b8d97a893eee573994ea7c9f */

.section .note.GNU-stack,"",@progbits
