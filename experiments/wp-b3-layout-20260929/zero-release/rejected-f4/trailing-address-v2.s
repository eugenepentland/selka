.text
.balign 16
.globl trailing_address
trailing_address:
	endbr64
	movq %rdi, %rax
	addq %rsi, %rax
	cmpq $0, %rax
	setnz %al
	movzbl %al, %eax
	movq review_global@gotpcrel(%rip), %rcx
	addq $8, %rcx
	movq (%rcx), %rcx
	movq %rcx, (%rdx)
	cmpl $0, %eax
	jnz .Lbb2
	movq $23, 8(%rdx)
	movl $0, %eax
	jmp .Lbb3
.Lbb2:
	movq $17, 8(%rdx)
	movl $1, %eax
.Lbb3:
	ret
.type trailing_address, @function
.size trailing_address, .-trailing_address
/* end function trailing_address */

.section .note.GNU-stack,"",@progbits
