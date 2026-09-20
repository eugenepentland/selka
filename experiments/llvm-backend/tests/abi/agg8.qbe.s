.text
.balign 16
take_8:
	endbr64
	subq $16, %rsp
	movq %rsi, 0(%rsp)
	movzbl 0(%rsp), %eax
	movzbl 7(%rsp), %ecx
	movl %eax, %eax
	movl %ecx, %ecx
	addq %rcx, %rax
	addq %rdi, %rax
	addq $16, %rsp
	ret
.type take_8, @function
.size take_8, .-take_8
/* end function take_8 */

.text
.balign 16
.globl qbe_agg8
qbe_agg8:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $16, %rsp
	movq %rsi, -8(%rbp)
	movq -8(%rbp), %rsi
	callq take_8
	leave
	ret
.type qbe_agg8, @function
.size qbe_agg8, .-qbe_agg8
/* end function qbe_agg8 */

.text
.balign 16
give_8:
	endbr64
	subq $16, %rsp
	movq %rsi, 0(%rsp)
	movq 0(%rsp), %rax
	addq $16, %rsp
	ret
.type give_8, @function
.size give_8, .-give_8
/* end function give_8 */

.text
.balign 16
.globl qbe_ret8
qbe_ret8:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $16, %rsp
	movq %rsi, -8(%rbp)
	movq -8(%rbp), %rsi
	callq give_8
	movq %rax, -16(%rbp)
	movq -16(%rbp), %rax
	leave
	ret
.type qbe_ret8, @function
.size qbe_ret8, .-qbe_ret8
/* end function qbe_ret8 */

.text
.balign 16
.globl qbe_retcall_8
qbe_retcall_8:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $16, %rsp
	movq %rsi, -8(%rbp)
	movq -8(%rbp), %rsi
	callq give_8
	movq %rax, -16(%rbp)
	movzbl -16(%rbp), %eax
	movzbl -9(%rbp), %ecx
	movl %eax, %eax
	movl %ecx, %ecx
	addq %rcx, %rax
	leave
	ret
.type qbe_retcall_8, @function
.size qbe_retcall_8, .-qbe_retcall_8
/* end function qbe_retcall_8 */

.section .note.GNU-stack,"",@progbits
