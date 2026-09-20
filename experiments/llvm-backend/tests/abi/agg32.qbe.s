.text
.balign 16
take_32:
	endbr64
	movzbl 8(%rsp), %eax
	movzbl 39(%rsp), %ecx
	movl %eax, %eax
	movl %ecx, %ecx
	addq %rcx, %rax
	addq %rdi, %rax
	ret
.type take_32, @function
.size take_32, .-take_32
/* end function take_32 */

.text
.balign 16
.globl qbe_agg32
qbe_agg32:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $32, %rsp
	movq %rsp, %rcx
	movq 16(%rbp), %rax
	movq %rax, 0(%rcx)
	movq 24(%rbp), %rax
	movq %rax, 8(%rcx)
	movq 32(%rbp), %rax
	movq %rax, 16(%rcx)
	movq 40(%rbp), %rax
	movq %rax, 24(%rcx)
	callq take_32
	subq $-32, %rsp
	leave
	ret
.type qbe_agg32, @function
.size qbe_agg32, .-qbe_agg32
/* end function qbe_agg32 */

.text
.balign 16
give_32:
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
	ret
.type give_32, @function
.size give_32, .-give_32
/* end function give_32 */

.text
.balign 16
.globl qbe_ret32
qbe_ret32:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $40, %rsp
	pushq %rbx
	movq %rdi, %rax
	subq $32, %rsp
	movq %rsp, %rcx
	movq 16(%rbp), %rdx
	movq %rdx, 0(%rcx)
	movq 24(%rbp), %rdx
	movq %rdx, 8(%rcx)
	movq 32(%rbp), %rdx
	movq %rdx, 16(%rcx)
	movq %rax, %rbx
	movq 40(%rbp), %rax
	movq %rax, 24(%rcx)
	leaq -32(%rbp), %rdi
	callq give_32
	movq %rax, %rcx
	movq %rbx, %rax
	subq $-32, %rsp
	movq 0(%rcx), %rdx
	movq %rdx, 0(%rax)
	movq 8(%rcx), %rdx
	movq %rdx, 8(%rax)
	movq 16(%rcx), %rdx
	movq %rdx, 16(%rax)
	movq 24(%rcx), %rcx
	movq %rcx, 24(%rax)
	popq %rbx
	leave
	ret
.type qbe_ret32, @function
.size qbe_ret32, .-qbe_ret32
/* end function qbe_ret32 */

.text
.balign 16
.globl qbe_retcall_32
qbe_retcall_32:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $32, %rsp
	movq %rdi, %rsi
	subq $32, %rsp
	movq %rsp, %rcx
	movq 16(%rbp), %rax
	movq %rax, 0(%rcx)
	movq 24(%rbp), %rax
	movq %rax, 8(%rcx)
	movq 32(%rbp), %rax
	movq %rax, 16(%rcx)
	movq 40(%rbp), %rax
	movq %rax, 24(%rcx)
	leaq -32(%rbp), %rdi
	callq give_32
	movq %rax, %rcx
	subq $-32, %rsp
	movzbl (%rcx), %eax
	movzbl 31(%rcx), %ecx
	movl %eax, %eax
	movl %ecx, %ecx
	addq %rcx, %rax
	leave
	ret
.type qbe_retcall_32, @function
.size qbe_retcall_32, .-qbe_retcall_32
/* end function qbe_retcall_32 */

.section .note.GNU-stack,"",@progbits
