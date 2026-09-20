.text
.balign 16
take_64:
	endbr64
	movzbl 8(%rsp), %eax
	movzbl 71(%rsp), %ecx
	movl %eax, %eax
	movl %ecx, %ecx
	addq %rcx, %rax
	addq %rdi, %rax
	ret
.type take_64, @function
.size take_64, .-take_64
/* end function take_64 */

.text
.balign 16
.globl qbe_agg64
qbe_agg64:
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
	movq 72(%rbp), %rax
	movq %rax, 56(%rcx)
	callq take_64
	subq $-64, %rsp
	leave
	ret
.type qbe_agg64, @function
.size qbe_agg64, .-qbe_agg64
/* end function qbe_agg64 */

.text
.balign 16
give_64:
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
	ret
.type give_64, @function
.size give_64, .-give_64
/* end function give_64 */

.text
.balign 16
.globl qbe_ret64
qbe_ret64:
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
	movq 64(%rbp), %rdx
	movq %rdx, 48(%rcx)
	movq %rax, %rbx
	movq 72(%rbp), %rax
	movq %rax, 56(%rcx)
	leaq -64(%rbp), %rdi
	callq give_64
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
	movq 48(%rcx), %rdx
	movq %rdx, 48(%rax)
	movq 56(%rcx), %rcx
	movq %rcx, 56(%rax)
	popq %rbx
	leave
	ret
.type qbe_ret64, @function
.size qbe_ret64, .-qbe_ret64
/* end function qbe_ret64 */

.text
.balign 16
.globl qbe_retcall_64
qbe_retcall_64:
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
	movq 72(%rbp), %rax
	movq %rax, 56(%rcx)
	leaq -64(%rbp), %rdi
	callq give_64
	movq %rax, %rcx
	subq $-64, %rsp
	movzbl (%rcx), %eax
	movzbl 63(%rcx), %ecx
	movl %eax, %eax
	movl %ecx, %ecx
	addq %rcx, %rax
	leave
	ret
.type qbe_retcall_64, @function
.size qbe_retcall_64, .-qbe_retcall_64
/* end function qbe_retcall_64 */

.section .note.GNU-stack,"",@progbits
