.text
.balign 16
.globl guard
guard:
	endbr64
	movl 8(%rdi), %eax
	movl 56(%rsi), %edx
	cmpl $2, %edx
	setz %cl
	movzbl %cl, %ecx
	cmpl $8, %edx
	setz %dl
	movzbl %dl, %edx
	orl %edx, %ecx
	testl %eax, %ecx
	jnz .Lbb2
	movl $0, %eax
	jmp .Lbb3
.Lbb2:
	movl $1, %eax
.Lbb3:
	ret
.type guard, @function
.size guard, .-guard
/* end function guard */

.section .note.GNU-stack,"",@progbits
