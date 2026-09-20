.text
.balign 16
take_16:
	endbr64
	subq $16, %rsp
	movq %rsi, 0(%rsp)
	movq %rdx, 8(%rsp)
	movzbl 0(%rsp), %eax
	movzbl 15(%rsp), %ecx
	movl %eax, %eax
	movl %ecx, %ecx
	addq %rcx, %rax
	addq %rdi, %rax
	addq $16, %rsp
	ret
.type take_16, @function
.size take_16, .-take_16
/* end function take_16 */

.text
.balign 16
.globl qbe_agg16
qbe_agg16:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $16, %rsp
	movq %rsi, -16(%rbp)
	movq %rdx, -8(%rbp)
	movq -16(%rbp), %rsi
	movq -8(%rbp), %rdx
	callq take_16
	leave
	ret
.type qbe_agg16, @function
.size qbe_agg16, .-qbe_agg16
/* end function qbe_agg16 */

.text
.balign 16
give_16:
	endbr64
	subq $16, %rsp
	movq %rsi, 0(%rsp)
	movq %rdx, 8(%rsp)
	movq 0(%rsp), %rax
	movq 8(%rsp), %rdx
	addq $16, %rsp
	ret
.type give_16, @function
.size give_16, .-give_16
/* end function give_16 */

.text
.balign 16
.globl qbe_ret16
qbe_ret16:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $32, %rsp
	movq %rsi, -16(%rbp)
	movq %rdx, -8(%rbp)
	movq -16(%rbp), %rsi
	movq -8(%rbp), %rdx
	callq give_16
	movq %rax, %rcx
	movq %rdx, %rax
	movq %rcx, -32(%rbp)
	movq %rax, -24(%rbp)
	movq -32(%rbp), %rax
	movq -24(%rbp), %rdx
	leave
	ret
.type qbe_ret16, @function
.size qbe_ret16, .-qbe_ret16
/* end function qbe_ret16 */

.text
.balign 16
.globl qbe_retcall_16
qbe_retcall_16:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $32, %rsp
	movq %rsi, -16(%rbp)
	movq %rdx, -8(%rbp)
	movq -16(%rbp), %rsi
	movq -8(%rbp), %rdx
	callq give_16
	movq %rax, %rcx
	movq %rdx, %rax
	movq %rcx, -32(%rbp)
	movq %rax, -24(%rbp)
	movzbl -32(%rbp), %eax
	movzbl -17(%rbp), %ecx
	movl %eax, %eax
	movl %ecx, %ecx
	addq %rcx, %rax
	leave
	ret
.type qbe_retcall_16, @function
.size qbe_retcall_16, .-qbe_retcall_16
/* end function qbe_retcall_16 */

.section .note.GNU-stack,"",@progbits
