.text
.balign 16
.globl byte_guard
byte_guard:
	endbr64
	movl 40(%rdi), %eax
	cmpl $0, %eax
	jz .Lbb2
	movl $0, %eax
	jmp .Lbb3
.Lbb2:
	movl $1, %eax
.Lbb3:
	ret
.type byte_guard, @function
.size byte_guard, .-byte_guard
/* end function byte_guard */

.section .note.GNU-stack,"",@progbits
