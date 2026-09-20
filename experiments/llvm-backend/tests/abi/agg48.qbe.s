.text
.balign 16
take_48:
	endbr64
	movzbl 8(%rsp), %eax
	movzbl 55(%rsp), %ecx
	movl %eax, %eax
	movl %ecx, %ecx
	addq %rcx, %rax
	addq %rdi, %rax
	ret
.type take_48, @function
.size take_48, .-take_48
/* end function take_48 */

.text
.balign 16
.globl qbe_agg48
qbe_agg48:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $48, %rsp
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
	callq take_48
	subq $-48, %rsp
	leave
	ret
.type qbe_agg48, @function
.size qbe_agg48, .-qbe_agg48
/* end function qbe_agg48 */

.text
.balign 16
give_48:
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
	ret
.type give_48, @function
.size give_48, .-give_48
/* end function give_48 */

.text
.balign 16
.globl qbe_ret48
qbe_ret48:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $56, %rsp
	pushq %rbx
	movq %rdi, %rax
	subq $48, %rsp
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
	movq %rax, %rbx
	movq 56(%rbp), %rax
	movq %rax, 40(%rcx)
	leaq -48(%rbp), %rdi
	callq give_48
	movq %rax, %rcx
	movq %rbx, %rax
	subq $-48, %rsp
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
	movq 40(%rcx), %rcx
	movq %rcx, 40(%rax)
	popq %rbx
	leave
	ret
.type qbe_ret48, @function
.size qbe_ret48, .-qbe_ret48
/* end function qbe_ret48 */

.text
.balign 16
.globl qbe_retcall_48
qbe_retcall_48:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $48, %rsp
	movq %rdi, %rsi
	subq $48, %rsp
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
	leaq -48(%rbp), %rdi
	callq give_48
	movq %rax, %rcx
	subq $-48, %rsp
	movzbl (%rcx), %eax
	movzbl 47(%rcx), %ecx
	movl %eax, %eax
	movl %ecx, %ecx
	addq %rcx, %rax
	leave
	ret
.type qbe_retcall_48, @function
.size qbe_retcall_48, .-qbe_retcall_48
/* end function qbe_retcall_48 */

.section .note.GNU-stack,"",@progbits
