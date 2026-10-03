.text
.balign 16
.globl from_signed
from_signed:
	endbr64
	cvtsi2sd %rdi, %xmm0
	movq %xmm0, %rax
	ret
.type from_signed, @function
.size from_signed, .-from_signed
/* end function from_signed */

.text
.balign 16
.globl from_unsigned
from_unsigned:
	endbr64
	movq %rdi, %rax
	andq $1, %rax
	movq %rdi, %rdx
	shrq $63, %rdx
	movl %edx, %ecx
	movq %rdi, %rsi
	shrq %cl, %rsi
	orq %rsi, %rax
	cvtsi2sd %rax, %xmm0
	movq %xmm0, %rax
	movq %rdx, %rcx
	shlq $52, %rcx
	addq %rcx, %rax
	movq %rax, %xmm0
	movq %xmm0, %rax
	ret
.type from_unsigned, @function
.size from_unsigned, .-from_unsigned
/* end function from_unsigned */

.section .note.GNU-stack,"",@progbits
