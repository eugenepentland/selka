.text
.balign 16
.globl review_scope_pin
review_scope_pin:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $8, %rsp
	pushq %rbx
	movq %rsi, (%rdx)
	movq 5640(%rsi), %rax
	movq 248(%rax), %r8
	movq %r8, 8(%rdx)
	movq $0, 16(%rdx)
	movl 112(%rsi), %r8d
	movl $1, 24(%rdx)
	movl %r8d, 28(%rdx)
	movq %rdx, 248(%rax)
	cmpq $0, %rcx
	jz .Lbb18
	movq %rcx, %rax
	subq $16, %rax
	movq (%rax), %r8
	movq %r8, %rax
	andq $2, %rax
	cmpq $0, %rax
	jnz .Lbb18
	movq $4611686018427387907, %rax
	andq %r8, %rax
	cmpq $0, %rax
	jnz .Lbb12
	movq %rcx, %rax
	subq $8, %rax
	movq (%rax), %r9
	movq myl_native_list_header_type(%rip), %rax
	cmpq %rax, %r9
	jnz .Lbb12
	movq 5640(%rsi), %r9
	movq 256(%r9), %rax
	cmpq $0, %rax
	jz .Lbb12
	movq 24(%rsi), %r10
	movq %r10, %rbx
	addq $40, %rbx
	cmpq %r10, %rbx
	jb .Lbb12
	movq 88(%rsi), %r11
	cmpq $0, %r11
	setz %r10b
	movzbl %r10b, %r10d
	cmpq %r11, %rbx
	setbe %r11b
	movzbl %r11b, %r11d
	orl %r11d, %r10d
	jz .Lbb12
	movq %rcx, %r10
	subq $24, %r10
	movq (%r10), %r10
	cmpq $-1, %r10
	jz .Lbb12
	movq 32(%rcx), %r10
	cmpq $0, %r10
	setnz %r11b
	movzbl %r11b, %r11d
	cmpl $0, %r11d
	jnz .Lbb10
	movq %rcx, %rdi
	movq %r10, %rcx
	jmp .Lbb15
.Lbb10:
	movq %r10, %r11
	subq $16, %r11
	movq (%r11), %r11
	movq $4611686018427387907, %rbx
	andq %rbx, %r11
	cmpq $0, %r11
	jnz .Lbb12
	movq %r10, %r11
	subq $24, %r11
	movq (%r11), %r11
	cmpq $-1, %r11
	jnz .Lbb14
.Lbb12:
	movq %rdx, %rax
	movq %rcx, %rdx
	movq %rax, %rsi
	callq myl_qbe_rc_scope_pin
	cmpl $0, %eax
	jnz .Lbb18
	movl $0, %eax
	jmp .Lbb19
.Lbb14:
	movq %rcx, %rdi
	movq %r10, %rcx
.Lbb15:
	movq (%rax), %r10
	movq %r10, 256(%r9)
	movq 264(%r9), %r10
	addq $-1, %r10
	movq %r10, 264(%r9)
	movq 24(%rsi), %r10
	addq $40, %r10
	movq %r10, 24(%rsi)
	movq 48(%r9), %rsi
	addq $40, %rsi
	movq %rsi, 48(%r9)
	movq %rdi, %rsi
	subq $24, %rsi
	movq (%rsi), %rsi
	addq $1, %rsi
	movq %rdi, %r9
	subq $24, %r9
	movq %rsi, (%r9)
	cmpq $0, %rcx
	jz .Lbb17
	movq %rcx, %rsi
	subq $24, %rsi
	movq (%rsi), %rsi
	addq $1, %rsi
	movq %rcx, %r9
	subq $24, %r9
	movq %rsi, (%r9)
.Lbb17:
	movq $1152921504606846976, %rsi
	andq %r8, %rsi
	movq $1152921504606846976, %r9
	orq %r9, %r8
	movq %rdi, %r9
	subq $16, %r9
	movq %r8, (%r9)
	movq 16(%rdx), %r8
	movq %r8, (%rax)
	movq %rdi, 8(%rax)
	movq %rsi, 16(%rax)
	movl $1, 24(%rax)
	movq %rcx, 32(%rax)
	movq %rax, 16(%rdx)
.Lbb18:
	movl $1, %eax
.Lbb19:
	popq %rbx
	leave
	ret
.type review_scope_pin, @function
.size review_scope_pin, .-review_scope_pin
/* end function review_scope_pin */

.text
.balign 16
.globl review_scope_end
review_scope_end:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	pushq %rbx
	pushq %r12
	movq %rsi, %rax
	movl 24(%rdx), %ecx
	cmpl $0, %ecx
	jz .Lbb45
	movq 5640(%rax), %rcx
	movq 248(%rcx), %rsi
	cmpq %rsi, %rdx
	jnz .Lbb37
	movq 200(%rcx), %rsi
	cmpq $0, %rsi
	jnz .Lbb37
	movq %rdx, %r9
	addq $16, %r9
	movq 16(%rdx), %r8
	cmpq $0, %r8
	jz .Lbb44
	movq (%r8), %rsi
	cmpq $0, %rsi
	jnz .Lbb37
	movq 264(%rcx), %rsi
	cmpq $32, %rsi
	jae .Lbb37
	movq 8(%r8), %rsi
	cmpq $0, %rsi
	jz .Lbb37
	movq %rsi, %r10
	subq $16, %r10
	movq (%r10), %r11
	movq $4611686018427387907, %r10
	andq %r11, %r10
	cmpq $0, %r10
	jnz .Lbb37
	movq %rsi, %r10
	subq $24, %r10
	movq (%r10), %r10
	cmpq $0, %r10
	jz .Lbb37
	movq %rsi, %rbx
	subq $32, %rbx
	movq (%rbx), %rbx
	cmpq $1, %r10
	seta %r10b
	movzbl %r10b, %r10d
	cmpq $0, %rbx
	setnz %bl
	movzbl %bl, %ebx
	orl %ebx, %r10d
	jz .Lbb37
	movq %rdi, %r10
	movq 32(%r8), %rdi
	cmpq $0, %rdi
	setnz %bl
	movzbl %bl, %ebx
	cmpl $0, %ebx
	jz .Lbb38
	movq %rdi, %rbx
	subq $16, %rbx
	movq (%rbx), %rbx
	movq $4611686018427387907, %r12
	andq %r12, %rbx
	cmpq $0, %rbx
	jz .Lbb33
	movq %r10, %rdi
	jmp .Lbb37
.Lbb33:
	movq %rdi, %rbx
	subq $24, %rbx
	movq (%rbx), %rbx
	cmpq $0, %rbx
	jnz .Lbb35
	movq %r10, %rdi
	jmp .Lbb37
.Lbb35:
	movq %rdi, %r12
	subq $32, %r12
	movq (%r12), %r12
	cmpq $1, %rbx
	seta %bl
	movzbl %bl, %ebx
	cmpq $0, %r12
	setnz %r12b
	movzbl %r12b, %r12d
	orl %r12d, %ebx
	jnz .Lbb38
	movq %r10, %rdi
.Lbb37:
	movq %rdx, %rsi
	callq myl_qbe_rc_scope_end
	jmp .Lbb45
.Lbb38:
	movl 24(%r8), %r10d
	cmpl $0, %r10d
	jnz .Lbb40
	movl $3735936685, %r9d
	jmp .Lbb41
.Lbb40:
	movq 16(%r8), %r10
	movq $-1152921504606846977, %rbx
	andq %rbx, %r11
	orq %r11, %r10
	movq %rsi, %r11
	subq $16, %r11
	movq %r10, (%r11)
.Lbb41:
	movq $0, (%r9)
	movq 256(%rcx), %r9
	movq %r9, (%r8)
	movq %r8, 256(%rcx)
	movq 264(%rcx), %r8
	addq $1, %r8
	movq %r8, 264(%rcx)
	movq 24(%rax), %r8
	addq $-40, %r8
	movq %r8, 24(%rax)
	movq 48(%rcx), %rax
	addq $-40, %rax
	movq %rax, 48(%rcx)
	cmpq $0, %rdi
	jz .Lbb43
	movq %rdi, %rax
	subq $24, %rax
	movq (%rax), %rax
	addq $-1, %rax
	subq $24, %rdi
	movq %rax, (%rdi)
.Lbb43:
	movq %rsi, %rax
	subq $24, %rax
	movq (%rax), %rax
	addq $-1, %rax
	subq $24, %rsi
	movq %rax, (%rsi)
.Lbb44:
	movq 8(%rdx), %rax
	movq %rax, 248(%rcx)
	movl $0, 24(%rdx)
	movq $0, 8(%rdx)
.Lbb45:
	popq %r12
	popq %rbx
	leave
	ret
.type review_scope_end, @function
.size review_scope_end, .-review_scope_end
/* end function review_scope_end */

.section .note.GNU-stack,"",@progbits
