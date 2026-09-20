.text
.balign 16
take_72:
	endbr64
	movzbl 8(%rsp), %eax
	movzbl 79(%rsp), %ecx
	movl %eax, %eax
	movl %ecx, %ecx
	addq %rcx, %rax
	addq %rdi, %rax
	ret
.type take_72, @function
.size take_72, .-take_72
/* end function take_72 */

.text
.balign 16
.globl qbe_agg72
qbe_agg72:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $80, %rsp
	movq %rsp, %rcx
	movq 16(%rbp), %rax
	movq %rax, 0(%rcx)
	movq 24(%rbp), %rax
	movq %rax, 8(%rcx)
	movq 32(%rbp), %rax
	movq %rax, 16(%rcx)
	movq 40(%rbp), %rax
	movq %rax, 24(%rcx)
	movq 48(%rbp), %rax
	movq %rax, 32(%rcx)
	movq 56(%rbp), %rax
	movq %rax, 40(%rcx)
	movq 64(%rbp), %rax
	movq %rax, 48(%rcx)
	movq 72(%rbp), %rax
	movq %rax, 56(%rcx)
	movq 80(%rbp), %rax
	movq %rax, 64(%rcx)
	callq take_72
	subq $-80, %rsp
	leave
	ret
.type qbe_agg72, @function
.size qbe_agg72, .-qbe_agg72
/* end function qbe_agg72 */

.text
.balign 16
give_72:
	endbr64
	movq %rdi, %rax
	movq 8(%rsp), %rcx
	movq %rcx, 0(%rax)
	movq 16(%rsp), %rcx
	movq %rcx, 8(%rax)
	movq 24(%rsp), %rcx
	movq %rcx, 16(%rax)
	movq 32(%rsp), %rcx
	movq %rcx, 24(%rax)
	movq 40(%rsp), %rcx
	movq %rcx, 32(%rax)
	movq 48(%rsp), %rcx
	movq %rcx, 40(%rax)
	movq 56(%rsp), %rcx
	movq %rcx, 48(%rax)
	movq 64(%rsp), %rcx
	movq %rcx, 56(%rax)
	movq 72(%rsp), %rcx
	movq %rcx, 64(%rax)
	ret
.type give_72, @function
.size give_72, .-give_72
/* end function give_72 */

.text
.balign 16
.globl qbe_ret72
qbe_ret72:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $88, %rsp
	pushq %rbx
	movq %rdi, %rax
	subq $80, %rsp
	movq %rsp, %rcx
	movq 16(%rbp), %rdx
	movq %rdx, 0(%rcx)
	movq 24(%rbp), %rdx
	movq %rdx, 8(%rcx)
	movq 32(%rbp), %rdx
	movq %rdx, 16(%rcx)
	movq 40(%rbp), %rdx
	movq %rdx, 24(%rcx)
	movq 48(%rbp), %rdx
	movq %rdx, 32(%rcx)
	movq 56(%rbp), %rdx
	movq %rdx, 40(%rcx)
	movq 64(%rbp), %rdx
	movq %rdx, 48(%rcx)
	movq 72(%rbp), %rdx
	movq %rdx, 56(%rcx)
	movq %rax, %rbx
	movq 80(%rbp), %rax
	movq %rax, 64(%rcx)
	leaq -72(%rbp), %rdi
	callq give_72
	movq %rax, %rcx
	movq %rbx, %rax
	subq $-80, %rsp
	movq 0(%rcx), %rdx
	movq %rdx, 0(%rax)
	movq 8(%rcx), %rdx
	movq %rdx, 8(%rax)
	movq 16(%rcx), %rdx
	movq %rdx, 16(%rax)
	movq 24(%rcx), %rdx
	movq %rdx, 24(%rax)
	movq 32(%rcx), %rdx
	movq %rdx, 32(%rax)
	movq 40(%rcx), %rdx
	movq %rdx, 40(%rax)
	movq 48(%rcx), %rdx
	movq %rdx, 48(%rax)
	movq 56(%rcx), %rdx
	movq %rdx, 56(%rax)
	movq 64(%rcx), %rcx
	movq %rcx, 64(%rax)
	popq %rbx
	leave
	ret
.type qbe_ret72, @function
.size qbe_ret72, .-qbe_ret72
/* end function qbe_ret72 */

.text
.balign 16
.globl qbe_retcall_72
qbe_retcall_72:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $80, %rsp
	movq %rdi, %rsi
	subq $80, %rsp
	movq %rsp, %rcx
	movq 16(%rbp), %rax
	movq %rax, 0(%rcx)
	movq 24(%rbp), %rax
	movq %rax, 8(%rcx)
	movq 32(%rbp), %rax
	movq %rax, 16(%rcx)
	movq 40(%rbp), %rax
	movq %rax, 24(%rcx)
	movq 48(%rbp), %rax
	movq %rax, 32(%rcx)
	movq 56(%rbp), %rax
	movq %rax, 40(%rcx)
	movq 64(%rbp), %rax
	movq %rax, 48(%rcx)
	movq 72(%rbp), %rax
	movq %rax, 56(%rcx)
	movq 80(%rbp), %rax
	movq %rax, 64(%rcx)
	leaq -72(%rbp), %rdi
	callq give_72
	movq %rax, %rcx
	subq $-80, %rsp
	movzbl (%rcx), %eax
	movzbl 71(%rcx), %ecx
	movl %eax, %eax
	movl %ecx, %ecx
	addq %rcx, %rax
	leave
	ret
.type qbe_retcall_72, @function
.size qbe_retcall_72, .-qbe_retcall_72
/* end function qbe_retcall_72 */

.section .note.GNU-stack,"",@progbits
