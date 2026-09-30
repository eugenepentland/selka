.text
.balign 16
.globl owner
owner:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	movq (%rsi), %rcx
	cmpq $0, %rcx
	jz .Lbb7
	movq %rcx, %rax
	subq $16, %rax
	movq (%rax), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb6
	movq %rcx, %rax
	subq $32, %rax
	movq (%rax), %rax
	cmpq $1, %rax
	jnz .Lbb5
	movq %rcx, %rdx
	subq $24, %rdx
	movq (%rdx), %rdx
	cmpq $0, %rdx
	jnz .Lbb5
	callq boundary_drop
	jmp .Lbb7
.Lbb5:
	subq $1, %rax
	subq $32, %rcx
	movq %rax, (%rcx)
.Lbb6:
	movq $0, (%rsi)
.Lbb7:
	movl $0, %eax
	leave
	ret
.type owner, @function
.size owner, .-owner
/* end function owner */

.text
.balign 16
.globl hold
hold:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	movq (%rsi), %rcx
	cmpq $0, %rcx
	jz .Lbb16
	movq %rcx, %rax
	subq $16, %rax
	movq (%rax), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb15
	movq %rcx, %rax
	subq $24, %rax
	movq (%rax), %rax
	cmpq $1, %rax
	jnz .Lbb14
	movq %rcx, %rdx
	subq $32, %rdx
	movq (%rdx), %rdx
	cmpq $0, %rdx
	jnz .Lbb14
	callq boundary_unloan
	jmp .Lbb16
.Lbb14:
	subq $1, %rax
	subq $24, %rcx
	movq %rax, (%rcx)
.Lbb15:
	movq $0, (%rsi)
.Lbb16:
	movl $0, %eax
	leave
	ret
.type hold, @function
.size hold, .-hold
/* end function hold */

.section .note.GNU-stack,"",@progbits
