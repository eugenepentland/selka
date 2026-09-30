.text
.balign 16
.globl review_owner
review_owner:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	movq %rsi, %rdi
	movq (%rdx), %rcx
	cmpq $0, %rcx
	jz .Lbb7
	movq %rcx, %rax
	subq $16, %rax
	movq (%rax), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb6
	movq %rcx, %rax
	subq $32, %rax
	movq (%rax), %rax
	subq $1, %rax
	jnz .Lbb5
	movq %rcx, %rsi
	subq $24, %rsi
	movq (%rsi), %rsi
	cmpq $0, %rsi
	jnz .Lbb5
	movq %rdx, %rsi
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	jmp .Lbb7
.Lbb5:
	subq $32, %rcx
	movq %rax, (%rcx)
.Lbb6:
	movq $0, (%rdx)
.Lbb7:
	movl $1, %eax
	leave
	ret
.type review_owner, @function
.size review_owner, .-review_owner
/* end function review_owner */

.text
.balign 16
.globl review_hold
review_hold:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	movq %rsi, %rdi
	movq (%rdx), %rcx
	cmpq $0, %rcx
	jz .Lbb16
	movq %rcx, %rax
	subq $16, %rax
	movq (%rax), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb15
	movq %rcx, %rax
	subq $24, %rax
	movq (%rax), %rax
	subq $1, %rax
	jnz .Lbb14
	movq %rcx, %rsi
	subq $32, %rsi
	movq (%rsi), %rsi
	cmpq $0, %rsi
	jnz .Lbb14
	movq %rdx, %rsi
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	jmp .Lbb16
.Lbb14:
	subq $24, %rcx
	movq %rax, (%rcx)
.Lbb15:
	movq $0, (%rdx)
.Lbb16:
	movl $1, %eax
	leave
	ret
.type review_hold, @function
.size review_hold, .-review_hold
/* end function review_hold */

.text
.balign 16
.globl review_publish
review_publish:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	pushq %rbx
	pushq %r12
	movq %rdi, %rbx
	movq %rsi, %rdi
	movq %rdx, %rsi
	movq %rcx, %rdx
	movl %r8d, %ecx
	movl %r9d, %r8d
	testl $3, %r8d
	jnz .Lbb32
	movq (%rdx), %rax
	cmpq $0, %rax
	setnz %r9b
	movzbl %r9b, %r9d
	cmpl $0, %r9d
	jz .Lbb29
	movl %ecx, %r10d
	movq %rax, %rcx
	subq $16, %rcx
	movq (%rcx), %rcx
	movq $5764607523034234880, %r9
	andq %rcx, %r9
	cmpq $0, %r9
	jnz .Lbb31
	testl $4, %r8d
	jnz .Lbb27
	movq %rcx, %r9
	andq $2, %r9
	cmpq $0, %r9
	jnz .Lbb27
	movq %rax, %r9
	subq $32, %r9
	movq (%r9), %r9
	addq $1, %r9
	jz .Lbb26
	movq %r9, %rdi
	movq %rax, %r9
	subq $32, %r9
	movq %rdi, (%r9)
	jmp .Lbb27
.Lbb26:
	movl %r10d, %ecx
	jmp .Lbb32
.Lbb27:
	movq $2305843009213693954, %rdi
	andq %rcx, %rdi
	cmpq $0, %rdi
	jnz .Lbb29
	movq $2305843009213693952, %rdi
	orq %rdi, %rcx
	movq %rax, %rdi
	subq $16, %rdi
	movq %rcx, (%rdi)
.Lbb29:
	movq %rax, (%rsi)
	testl $4, %r8d
	jz .Lbb34
	movq $0, (%rdx)
	jmp .Lbb34
.Lbb31:
	movl %r10d, %ecx
.Lbb32:
	movq %rdi, %r12
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_publish
	movq %r12, %rdi
	cmpl $0, %eax
	jnz .Lbb34
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	callq myl_qbe_rc_status
	movl $0, %eax
	jmp .Lbb35
.Lbb34:
	movl $1, %eax
.Lbb35:
	popq %r12
	popq %rbx
	leave
	ret
.type review_publish, @function
.size review_publish, .-review_publish
/* end function review_publish */

.section .note.GNU-stack,"",@progbits
