.text
.balign 16
take_56:
	endbr64
	movzbl 8(%rsp), %eax
	movzbl 63(%rsp), %ecx
	movl %eax, %eax
	movl %ecx, %ecx
	addq %rcx, %rax
	addq %rdi, %rax
	ret
.type take_56, @function
.size take_56, .-take_56
/* end function take_56 */

.text
.balign 16
.globl qbe_agg56
qbe_agg56:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $64, %rsp
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
	callq take_56
	subq $-64, %rsp
	leave
	ret
.type qbe_agg56, @function
.size qbe_agg56, .-qbe_agg56
/* end function qbe_agg56 */

.text
.balign 16
give_56:
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
	ret
.type give_56, @function
.size give_56, .-give_56
/* end function give_56 */

.text
.balign 16
.globl qbe_ret56
qbe_ret56:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $72, %rsp
	pushq %rbx
	movq %rdi, %rax
	subq $64, %rsp
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
	movq %rax, %rbx
	movq 64(%rbp), %rax
	movq %rax, 48(%rcx)
	leaq -56(%rbp), %rdi
	callq give_56
	movq %rax, %rcx
	movq %rbx, %rax
	subq $-64, %rsp
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
	movq 48(%rcx), %rcx
	movq %rcx, 48(%rax)
	popq %rbx
	leave
	ret
.type qbe_ret56, @function
.size qbe_ret56, .-qbe_ret56
/* end function qbe_ret56 */

.text
.balign 16
.globl qbe_retcall_56
qbe_retcall_56:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $64, %rsp
	movq %rdi, %rsi
	subq $64, %rsp
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
	leaq -56(%rbp), %rdi
	callq give_56
	movq %rax, %rcx
	subq $-64, %rsp
	movzbl (%rcx), %eax
	movzbl 55(%rcx), %ecx
	movl %eax, %eax
	movl %ecx, %ecx
	addq %rcx, %rax
	leave
	ret
.type qbe_retcall_56, @function
.size qbe_retcall_56, .-qbe_retcall_56
/* end function qbe_retcall_56 */

.section .note.GNU-stack,"",@progbits
