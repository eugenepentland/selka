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
	subq $192, %rsp
	pushq %rbx
	pushq %r12
	pushq %r13
	pushq %r14
	pushq %r15
	movq %rsi, %rax
	movq %rdi, %r14
	movq (%rax), %r12
	movq 8(%rax), %r13
	movq 16(%rax), %rbx
	movq 24(%rax), %r11
	movq 32(%rax), %r10
	movq 40(%rax), %r9
	movq 48(%rax), %r8
	movq 56(%rax), %rdi
	movq 64(%rax), %rsi
	movq 72(%rax), %rdx
	movq 80(%rax), %rcx
	movq 88(%rax), %r15
	movq %r15, 216(%rsp)
	movq 96(%rax), %r15
	movq %r15, 200(%rsp)
	movq 104(%rax), %r15
	movq %r15, 208(%rsp)
	movq 112(%rax), %r15
	movq %r15, 184(%rsp)
	movq 120(%rax), %r15
	movq %r15, 168(%rsp)
	movq 128(%rax), %r15
	movq %r15, 152(%rsp)
	movq 136(%rax), %r15
	movq %r15, 136(%rsp)
	movq 144(%rax), %r15
	movq %r15, 120(%rsp)
	movq 152(%rax), %r15
	movq %r15, 104(%rsp)
	movq 160(%rax), %r15
	movq %r15, 88(%rsp)
	movq 168(%rax), %r15
	movq %r15, 72(%rsp)
	movq 176(%rax), %r15
	movq %r15, 48(%rsp)
	movq 216(%rsp), %r15
	movq 184(%rax), %rax
	addq $1, %r14
	cmpq $0, %r14
	setz %r14b
	movzbl %r14b, %r14d
	movl %r14d, 56(%rsp)
	addq %r13, %r12
	movq %r12, 192(%rsp)
	movq 208(%rsp), %r13
	movq 200(%rsp), %r14
	addq 192(%rsp), %rbx
	movq %rbx, 176(%rsp)
	movq 184(%rsp), %r12
	addq 176(%rsp), %r11
	movq %r11, 160(%rsp)
	movq 168(%rsp), %rbx
	addq 160(%rsp), %r10
	movq %r10, 144(%rsp)
	movq 152(%rsp), %r11
	addq 144(%rsp), %r9
	movq %r9, 128(%rsp)
	movq 136(%rsp), %r10
	addq 128(%rsp), %r8
	movq %r8, 112(%rsp)
	movq 120(%rsp), %r9
	addq 112(%rsp), %rdi
	movq %rdi, 96(%rsp)
	movq 104(%rsp), %r8
	addq 96(%rsp), %rsi
	movq %rsi, 80(%rsp)
	movq 88(%rsp), %rdi
	addq 80(%rsp), %rdx
	movq %rdx, 64(%rsp)
	movq 72(%rsp), %rdx
	addq 64(%rsp), %rcx
	movq %rcx, 40(%rsp)
	movl 56(%rsp), %esi
	movq 48(%rsp), %rcx
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
	addq %rdi, %rdx
	addq %rdx, %rcx
	movq %rax, %rdx
	addq %rcx, %rdx
	cmpl $0, %esi
	jnz .Lbb50
	addq %rcx, %rax
	jmp .Lbb52
.Lbb50:
	movq %rdx, %rax
	addq $1, %rax
.Lbb52:
	popq %r15
	popq %r14
	popq %r13
	popq %r12
	popq %rbx
	addq $192, %rsp
	ret
.type branch_spill, @function
.size branch_spill, .-branch_spill
/* end function branch_spill */

.section .note.GNU-stack,"",@progbits
