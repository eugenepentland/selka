.text
.balign 16
.globl trailing_address
trailing_address:
	endbr64
	movq %rdi, %rcx
	addq %rsi, %rcx
	movq review_global@gotpcrel(%rip), %rax
	addq $8, %rax
	movq (%rax), %rax
	cmpq $0, %rcx
	jnz .Lbb2
	movq $23, (%rdx)
	jmp .Lbb3
.Lbb2:
	movq $17, (%rdx)
.Lbb3:
	ret
.type trailing_address, @function
.size trailing_address, .-trailing_address
/* end function trailing_address */

.section .note.GNU-stack,"",@progbits
