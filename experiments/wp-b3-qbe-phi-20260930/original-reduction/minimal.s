.text
.balign 16
.globl review_phi_spill
review_phi_spill:
	endbr64
	subq $48, %rsp
	pushq %rbx
	pushq %r12
	pushq %r13
	pushq %r14
	pushq %r15
	movq %rdx, %rax
	movq %rdi, %rcx
	movq (%rsi), %r15
	movq 8(%rsi), %r14
	movq 16(%rsi), %r13
	movq 24(%rsi), %r12
	movq 32(%rsi), %rbx
	movq 40(%rsi), %r11
	movq 48(%rsi), %r10
	movq 56(%rsi), %r9
	movq 64(%rsi), %r8
	movq 72(%rsi), %rdi
	movq 80(%rsi), %rdx
	movq %rdx, 64(%rsp)
	movq 88(%rsi), %rdx
	movq %rdx, 72(%rsp)
	movq 96(%rsi), %rdx
	movq %rdx, 56(%rsp)
	movq 104(%rsi), %rdx
	movq %rdx, 48(%rsp)
	movq 72(%rsp), %rdx
	movq 64(%rsp), %rsi
	cmpq $0, %rcx
	setnz %cl
	movzbl %cl, %ecx
	movl %ecx, 40(%rsp)
	movq 56(%rsp), %rcx
	jnz .Lbb2
	movl $23, (%rax)
	movq 48(%rsp), %rax
	jmp .Lbb3
.Lbb2:
	movl $17, (%rax)
	movq 48(%rsp), %rax
.Lbb3:
	addq 40(%rsp), %r15
	addq %r15, %r14
	addq %r14, %r13
	addq %r13, %r12
	addq %r12, %rbx
	addq %rbx, %r11
	addq %r11, %r10
	addq %r10, %r9
	addq %r9, %r8
	addq %r8, %rdi
	addq %rdi, %rsi
	addq %rsi, %rdx
	addq %rdx, %rcx
	addq %rcx, %rax
	popq %r15
	popq %r14
	popq %r13
	popq %r12
	popq %rbx
	addq $48, %rsp
	ret
.type review_phi_spill, @function
.size review_phi_spill, .-review_phi_spill
/* end function review_phi_spill */

.section .note.GNU-stack,"",@progbits
