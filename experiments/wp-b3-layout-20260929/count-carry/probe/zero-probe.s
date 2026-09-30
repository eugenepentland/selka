.text
.balign 16
.globl owner
owner:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	movq %rsi, %rax
	subq $32, %rax
	movq (%rax), %rax
	addq $1, %rax
	cmpq $0, %rax
	jz .Lbb2
	movq %rsi, %rcx
	subq $32, %rcx
	movq %rax, (%rcx)
	movq %rsi, (%rdx)
	movl $1, %eax
	jmp .Lbb3
.Lbb2:
	movl $2, %esi
	callq myl_qbe_rc_status
	movl $0, %eax
.Lbb3:
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
	movq %rsi, %rax
	subq $24, %rax
	movq (%rax), %rax
	addq $1, %rax
	cmpq $0, %rax
	jz .Lbb6
	movq %rsi, %rcx
	subq $24, %rcx
	movq %rax, (%rcx)
	movq %rsi, (%rdx)
	movl $1, %eax
	jmp .Lbb7
.Lbb6:
	movl $2, %esi
	callq myl_qbe_rc_status
	movl $0, %eax
.Lbb7:
	leave
	ret
.type hold, @function
.size hold, .-hold
/* end function hold */

.section .note.GNU-stack,"",@progbits
