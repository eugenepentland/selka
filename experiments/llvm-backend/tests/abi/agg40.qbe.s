.text
.balign 16
take_40:
	endbr64
	movzbl 8(%rsp), %eax
	movzbl 47(%rsp), %ecx
	movl %eax, %eax
	movl %ecx, %ecx
	addq %rcx, %rax
	addq %rdi, %rax
	ret
.type take_40, @function
.size take_40, .-take_40
/* end function take_40 */

.text
.balign 16
.globl qbe_agg40
qbe_agg40:
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
	callq take_40
	subq $-48, %rsp
	leave
	ret
.type qbe_agg40, @function
.size qbe_agg40, .-qbe_agg40
/* end function qbe_agg40 */

.text
.balign 16
give_40:
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
	ret
.type give_40, @function
.size give_40, .-give_40
/* end function give_40 */

.text
.balign 16
.globl qbe_ret40
qbe_ret40:
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
	movq %rax, %rbx
	movq 48(%rbp), %rax
	movq %rax, 32(%rcx)
	leaq -40(%rbp), %rdi
	callq give_40
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
	movq 32(%rcx), %rcx
	movq %rcx, 32(%rax)
	popq %rbx
	leave
	ret
.type qbe_ret40, @function
.size qbe_ret40, .-qbe_ret40
/* end function qbe_ret40 */

.text
.balign 16
.globl qbe_retcall_40
qbe_retcall_40:
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
	leaq -40(%rbp), %rdi
	callq give_40
	movq %rax, %rcx
	subq $-48, %rsp
	movzbl (%rcx), %eax
	movzbl 39(%rcx), %ecx
	movl %eax, %eax
	movl %ecx, %ecx
	addq %rcx, %rax
	leave
	ret
.type qbe_retcall_40, @function
.size qbe_retcall_40, .-qbe_retcall_40
/* end function qbe_retcall_40 */

.section .note.GNU-stack,"",@progbits
