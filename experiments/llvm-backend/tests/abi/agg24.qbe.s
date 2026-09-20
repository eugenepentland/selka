.text
.balign 16
take_24:
	endbr64
	movzbl 8(%rsp), %eax
	movzbl 31(%rsp), %ecx
	movl %eax, %eax
	movl %ecx, %ecx
	addq %rcx, %rax
	addq %rdi, %rax
	ret
.type take_24, @function
.size take_24, .-take_24
/* end function take_24 */

.text
.balign 16
.globl qbe_agg24
qbe_agg24:
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
	callq take_24
	subq $-32, %rsp
	leave
	ret
.type qbe_agg24, @function
.size qbe_agg24, .-qbe_agg24
/* end function qbe_agg24 */

.text
.balign 16
give_24:
	endbr64
	movq %rdi, %rax
	movq 8(%rsp), %rcx
	movq %rcx, 0(%rax)
	movq 16(%rsp), %rcx
	movq %rcx, 8(%rax)
	movq 24(%rsp), %rcx
	movq %rcx, 16(%rax)
	ret
.type give_24, @function
.size give_24, .-give_24
/* end function give_24 */

.text
.balign 16
.globl qbe_ret24
qbe_ret24:
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
	movq %rax, %rbx
	movq 32(%rbp), %rax
	movq %rax, 16(%rcx)
	leaq -24(%rbp), %rdi
	callq give_24
	movq %rax, %rcx
	movq %rbx, %rax
	subq $-32, %rsp
	movq 0(%rcx), %rdx
	movq %rdx, 0(%rax)
	movq 8(%rcx), %rdx
	movq %rdx, 8(%rax)
	movq 16(%rcx), %rcx
	movq %rcx, 16(%rax)
	popq %rbx
	leave
	ret
.type qbe_ret24, @function
.size qbe_ret24, .-qbe_ret24
/* end function qbe_ret24 */

.text
.balign 16
.globl qbe_retcall_24
qbe_retcall_24:
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
	leaq -24(%rbp), %rdi
	callq give_24
	movq %rax, %rcx
	subq $-32, %rsp
	movzbl (%rcx), %eax
	movzbl 23(%rcx), %ecx
	movl %eax, %eax
	movl %ecx, %ecx
	addq %rcx, %rax
	leave
	ret
.type qbe_retcall_24, @function
.size qbe_retcall_24, .-qbe_retcall_24
/* end function qbe_retcall_24 */

.section .note.GNU-stack,"",@progbits
