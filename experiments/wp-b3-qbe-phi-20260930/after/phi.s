.text
.balign 16
.globl long_phi
long_phi:
	endbr64
	subq $32, %rsp
	pushq %rbx
	pushq %r12
	pushq %r13
	pushq %r14
	pushq %r15
	movq %rdx, %r15
	movq %rdi, %rcx
	movq (%rsi), %rax
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
	movq %rdx, 56(%rsp)
	movq 88(%rsi), %rdx
	movq %rdx, 64(%rsp)
	movq 96(%rsi), %rdx
	movq %rdx, 48(%rsp)
	movq 104(%rsi), %rdx
	movq %rdx, 40(%rsp)
	movq 64(%rsp), %rdx
	movq 56(%rsp), %rsi
	cmpq $0, %rcx
	movq 48(%rsp), %rcx
	jnz .Lbb3
	movl $23, (%r15)
	movl $0, %r15d
	jmp .Lbb5
.Lbb3:
	movl $17, (%r15)
	movl $1, %r15d
.Lbb5:
	addq %rax, %r15
	movq 40(%rsp), %rax
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
	addq $32, %rsp
	ret
.type long_phi, @function
.size long_phi, .-long_phi
/* end function long_phi */

.text
.balign 16
.globl word_phi
word_phi:
	endbr64
	subq $32, %rsp
	pushq %rbx
	pushq %r12
	pushq %r13
	pushq %r14
	pushq %r15
	movq %rdx, %rax
	movq %rdi, %rcx
	movl (%rsi), %r15d
	movl 8(%rsi), %r14d
	movl 16(%rsi), %r13d
	movl 24(%rsi), %r12d
	movl 32(%rsi), %ebx
	movl 40(%rsi), %r11d
	movl 48(%rsi), %r10d
	movl 56(%rsi), %r9d
	movl 64(%rsi), %r8d
	movl 72(%rsi), %edi
	movl 80(%rsi), %edx
	movl %edx, 52(%rsp)
	movl 88(%rsi), %edx
	movl %edx, 56(%rsp)
	movl 96(%rsi), %edx
	movl %edx, 48(%rsp)
	movl 104(%rsi), %edx
	movl %edx, 44(%rsp)
	movl 56(%rsp), %edx
	movl 52(%rsp), %esi
	cmpq $0, %rcx
	setnz %cl
	movzbl %cl, %ecx
	movl %ecx, 40(%rsp)
	movl 48(%rsp), %ecx
	jnz .Lbb9
	movl $23, (%rax)
	movl 44(%rsp), %eax
	jmp .Lbb10
.Lbb9:
	movl $17, (%rax)
	movl 44(%rsp), %eax
.Lbb10:
	addl 40(%rsp), %r15d
	addl %r15d, %r14d
	addl %r14d, %r13d
	addl %r13d, %r12d
	addl %r12d, %ebx
	addl %ebx, %r11d
	addl %r11d, %r10d
	addl %r10d, %r9d
	addl %r9d, %r8d
	addl %r8d, %edi
	addl %edi, %esi
	addl %esi, %edx
	addl %edx, %ecx
	addl %ecx, %eax
	popq %r15
	popq %r14
	popq %r13
	popq %r12
	popq %rbx
	addq $32, %rsp
	ret
.type word_phi, @function
.size word_phi, .-word_phi
/* end function word_phi */

.text
.balign 16
.globl cross_phi
cross_phi:
	endbr64
	cmpl $0, %edi
	jnz .Lbb15
	movl $23, (%rsi)
	movl $0, %eax
	movl $0, %ecx
	jmp .Lbb17
.Lbb15:
	movl $17, (%rsi)
	movq $-1, %rax
	movl $-1, %ecx
.Lbb17:
	movl %ecx, 8(%rsi)
	ret
.type cross_phi, @function
.size cross_phi, .-cross_phi
/* end function cross_phi */

.text
.balign 16
.globl same_long_phi
same_long_phi:
	endbr64
	cmpl $0, %edi
	jnz .Lbb22
	movl $23, (%rsi)
	movl $0, %eax
	jmp .Lbb24
.Lbb22:
	movl $17, (%rsi)
	movq $-1, %rax
.Lbb24:
	movq %rax, 8(%rsi)
	ret
.type same_long_phi, @function
.size same_long_phi, .-same_long_phi
/* end function same_long_phi */

.text
.balign 16
.globl same_word_phi
same_word_phi:
	endbr64
	cmpl $0, %edi
	jnz .Lbb29
	movl $23, (%rsi)
	movl $0, %eax
	jmp .Lbb31
.Lbb29:
	movl $17, (%rsi)
	movl $-1, %eax
.Lbb31:
	movl %eax, 8(%rsi)
	ret
.type same_word_phi, @function
.size same_word_phi, .-same_word_phi
/* end function same_word_phi */

.section .note.GNU-stack,"",@progbits
