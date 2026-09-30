.text
.balign 16
.globl branch_add
branch_add:
	endbr64
	movq %rdi, %rax
	addq $1, %rax
	jz .Lbb2
	movl $0, %eax
	jmp .Lbb3
.Lbb2:
	movl $1, %eax
.Lbb3:
	ret
.type branch_add, @function
.size branch_add, .-branch_add
/* end function branch_add */

.text
.balign 16
.globl branch_sub
branch_sub:
	endbr64
	movq %rdi, %rax
	subq $1, %rax
	jz .Lbb6
	movl $0, %eax
	jmp .Lbb7
.Lbb6:
	movl $1, %eax
.Lbb7:
	ret
.type branch_sub, @function
.size branch_sub, .-branch_sub
/* end function branch_sub */

.text
.balign 16
.globl branch_ne
branch_ne:
	endbr64
	movq %rdi, %rax
	addq $1, %rax
	jnz .Lbb10
	movl $0, %eax
	jmp .Lbb11
.Lbb10:
	movl $1, %eax
.Lbb11:
	ret
.type branch_ne, @function
.size branch_ne, .-branch_ne
/* end function branch_ne */

.text
.balign 16
.globl branch_reverse
branch_reverse:
	endbr64
	movq %rdi, %rax
	addq $1, %rax
	jz .Lbb14
	movl $0, %eax
	jmp .Lbb15
.Lbb14:
	movl $1, %eax
.Lbb15:
	ret
.type branch_reverse, @function
.size branch_reverse, .-branch_reverse
/* end function branch_reverse */

.text
.balign 16
.globl branch_word
branch_word:
	endbr64
	movl %edi, %eax
	addl $1, %eax
	jz .Lbb18
	movl $0, %eax
	jmp .Lbb19
.Lbb18:
	movl $1, %eax
.Lbb19:
	ret
.type branch_word, @function
.size branch_word, .-branch_word
/* end function branch_word */

.text
.balign 16
.globl branch_width
branch_width:
	endbr64
	movq %rdi, %rax
	addq $1, %rax
	cmpl $0, %eax
	jz .Lbb22
	movl $0, %eax
	jmp .Lbb23
.Lbb22:
	movl $1, %eax
.Lbb23:
	ret
.type branch_width, @function
.size branch_width, .-branch_width
/* end function branch_width */

.text
.balign 16
.globl branch_nonzero
branch_nonzero:
	endbr64
	movq %rdi, %rax
	addq $1, %rax
	cmpq $7, %rax
	jz .Lbb26
	movl $0, %eax
	jmp .Lbb27
.Lbb26:
	movl $1, %eax
.Lbb27:
	ret
.type branch_nonzero, @function
.size branch_nonzero, .-branch_nonzero
/* end function branch_nonzero */

.text
.balign 16
.globl branch_clobber
branch_clobber:
	endbr64
	movq %rdi, %rax
	addq $1, %rax
	movq %rdi, %rcx
	xorq $-1, %rcx
	movq %rcx, (%rsi)
	cmpq $0, %rax
	jz .Lbb30
	movl $0, %eax
	jmp .Lbb31
.Lbb30:
	movl $1, %eax
.Lbb31:
	ret
.type branch_clobber, @function
.size branch_clobber, .-branch_clobber
/* end function branch_clobber */

.text
.balign 16
.globl branch_other
branch_other:
	endbr64
	movq %rdi, %rax
	addq $1, %rax
	movq %rdi, %rcx
	subq $2, %rcx
	movq %rcx, (%rsi)
	cmpq $0, %rax
	jz .Lbb34
	movl $0, %eax
	jmp .Lbb35
.Lbb34:
	movl $1, %eax
.Lbb35:
	ret
.type branch_other, @function
.size branch_other, .-branch_other
/* end function branch_other */

.text
.balign 16
.globl branch_call
branch_call:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $8, %rsp
	pushq %rbx
	movq %rdi, %rbx
	addq $1, %rbx
	callq touch
	cmpq $0, %rbx
	jz .Lbb38
	movl $0, %eax
	jmp .Lbb39
.Lbb38:
	movl $1, %eax
.Lbb39:
	popq %rbx
	leave
	ret
.type branch_call, @function
.size branch_call, .-branch_call
/* end function branch_call */

.text
.balign 16
.globl branch_multi
branch_multi:
	endbr64
	movq %rdi, %rax
	addq $1, %rax
	cmpq $0, %rax
	setz %al
	movzbl %al, %eax
	movl %eax, %eax
	movq %rax, (%rsi)
	jz .Lbb42
	movl $0, %eax
	jmp .Lbb43
.Lbb42:
	movl $1, %eax
.Lbb43:
	ret
.type branch_multi, @function
.size branch_multi, .-branch_multi
/* end function branch_multi */

.text
.balign 16
.globl branch_wrongresult
branch_wrongresult:
	endbr64
	movq %rdi, %rax
	subq $1, %rax
	cmpq $0, %rdi
	jz .Lbb46
	movq %rax, (%rsi)
	movl $0, %eax
	jmp .Lbb47
.Lbb46:
	movq %rax, (%rsi)
	movl $1, %eax
.Lbb47:
	ret
.type branch_wrongresult, @function
.size branch_wrongresult, .-branch_wrongresult
/* end function branch_wrongresult */

.text
.balign 16
.globl branch_spill
branch_spill:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $232, %rsp
	pushq %rbx
	pushq %r12
	pushq %r13
	pushq %r14
	pushq %r15
	movq %rdi, %rax
	movq %rsi, %rdi
	movq (%rdi), %rbx
	movq 8(%rdi), %r12
	movq 16(%rdi), %r10
	movq 24(%rdi), %r9
	movq 32(%rdi), %r8
	movq 40(%rdi), %rcx
	movq %rcx, -64(%rbp)
	movq 48(%rdi), %rsi
	movq %rsi, -56(%rbp)
	movq 56(%rdi), %rdx
	movq %rdx, -48(%rbp)
	movq 64(%rdi), %rcx
	movq %rcx, -40(%rbp)
	movq 72(%rdi), %rcx
	movq %rcx, -32(%rbp)
	movq 80(%rdi), %r15
	movq %r15, -24(%rbp)
	movq 88(%rdi), %r14
	movq %r14, -16(%rbp)
	movq 96(%rdi), %r13
	movq %r13, -8(%rbp)
	movq 104(%rdi), %rcx
	movq %rcx, -80(%rbp)
	movq 112(%rdi), %rcx
	movq %rcx, -72(%rbp)
	movq 120(%rdi), %r11
	movq %r11, -96(%rbp)
	movq %r10, %r15
	movq 128(%rdi), %r10
	movq %r10, -112(%rbp)
	movq %r9, %r14
	movq 136(%rdi), %r9
	movq %r9, -128(%rbp)
	movq %r8, %r13
	movq 144(%rdi), %r8
	movq %r8, -144(%rbp)
	movq 152(%rdi), %rcx
	movq %rcx, -160(%rbp)
	movq 160(%rdi), %rsi
	movq %rsi, -176(%rbp)
	movq 168(%rdi), %rdx
	movq %rdx, -192(%rbp)
	movq 176(%rdi), %rcx
	movq %rcx, -216(%rbp)
	movq 184(%rdi), %rcx
	movq %rcx, -208(%rbp)
	addq $1, %rax
	jz .Lbb51
	callq record_no
	movq %r15, %r10
	movq %r14, %r9
	movq %r13, %r8
	movq %r10, %r15
	movq -8(%rbp), %r10
	movq %r9, %r14
	movq -16(%rbp), %r9
	movq %r8, %r13
	movq -24(%rbp), %r8
	movq -32(%rbp), %rax
	movq -40(%rbp), %rcx
	movq -48(%rbp), %rdx
	movq -56(%rbp), %rsi
	movq -64(%rbp), %rdi
	xchgq %r9, %r14
	xchgq %r8, %r15
	xchgq %r13, %r8
	xchgq %r10, %r13
	jmp .Lbb52
.Lbb51:
	callq record_yes
	movq %r15, %r10
	movq %r14, %r9
	movq %r13, %r8
	movq -8(%rbp), %r13
	movq -16(%rbp), %r14
	movq -24(%rbp), %r15
	movq -32(%rbp), %rax
	movq -40(%rbp), %rcx
	movq -48(%rbp), %rdx
	movq -56(%rbp), %rsi
	movq -64(%rbp), %rdi
.Lbb52:
	movq %rbx, %r11
	addq %r12, %r11
	movq %r11, -88(%rbp)
	movq -72(%rbp), %rbx
	movq -80(%rbp), %r12
	addq -88(%rbp), %r10
	movq %r10, -104(%rbp)
	movq -96(%rbp), %r11
	addq -104(%rbp), %r9
	movq %r9, -120(%rbp)
	movq -112(%rbp), %r10
	addq -120(%rbp), %r8
	movq %r8, -136(%rbp)
	movq -128(%rbp), %r9
	addq -136(%rbp), %rdi
	movq %rdi, -152(%rbp)
	movq -144(%rbp), %r8
	addq -152(%rbp), %rsi
	movq %rsi, -168(%rbp)
	movq -160(%rbp), %rdi
	addq -168(%rbp), %rdx
	movq %rdx, -184(%rbp)
	movq -176(%rbp), %rsi
	addq -184(%rbp), %rcx
	movq %rcx, -200(%rbp)
	movq -192(%rbp), %rdx
	addq -200(%rbp), %rax
	movq %rax, -224(%rbp)
	movq -208(%rbp), %rax
	movq -216(%rbp), %rcx
	addq -224(%rbp), %r15
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
	leave
	ret
.type branch_spill, @function
.size branch_spill, .-branch_spill
/* end function branch_spill */

.section .note.GNU-stack,"",@progbits
