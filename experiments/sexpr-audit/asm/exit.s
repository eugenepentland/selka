# Startup floor: a static syscall-only binary that exits immediately.
#   as -o exit.o exit.s && ld -s -o exit exit.o
	.section .text
	.globl _start
_start:
	xorl %edi, %edi
	movl $60, %eax
	syscall
