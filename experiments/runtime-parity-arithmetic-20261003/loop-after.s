.file 1 "myl_f_edca249d8d1f9a5b7d1a0f3ef54e3969bf3acb65499aaea1316cc43a98315502"
.text
.balign 16
.globl myl_f_edca249d8d1f9a5b7d1a0f3ef54e3969bf3acb65499aaea1316cc43a98315502
myl_f_edca249d8d1f9a5b7d1a0f3ef54e3969bf3acb65499aaea1316cc43a98315502:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $8, %rsp
	pushq %rbx
	movq %rdx, %rax
	cmpq $0, %rsi
	setg %cl
	movzbq %cl, %rcx
	cmpq $16, %rsi
	setae %r8b
	movzbq %r8b, %r8
	testq %rcx, %r8
	jnz .Lbb2
	movl $0, %r9d
	jmp .Lbb6
.Lbb2:
	movq $576460752303423488, %rcx
	movq %rsi, %r8
	addq %rcx, %r8
	movq $1152921504606846976, %rcx
	cmpq %rcx, %r8
	jbe .Lbb4
	movl $0, %r9d
	jmp .Lbb6
.Lbb4:
	movq $576460752303423488, %rcx
	movq %rax, %r8
	addq %rcx, %r8
	movq $1152921504606846976, %rcx
	cmpq %rcx, %r8
	jbe .Lbb16
	movl $0, %r9d
.p2align 4
.Lbb6:
	cmpq %rsi, %r9
	jge .Lbb19
	imulq $7, %r9, %rcx
	movl $4294967295, %r8d
	movq %r9, %rbx
	andq %r8, %rbx
	movq %r9, %r11
	shrq $32, %r11
	imulq $7, %rbx, %r8
	shrq $32, %r8
	imulq $7, %r11, %r10
	addq %r8, %r10
	movl $4294967295, %r8d
	andq %r10, %r8
	shrq $32, %r10
	imulq $0, %rbx, %rbx
	addq %rbx, %r8
	shrq $32, %r8
	imulq $0, %r11, %r11
	addq %r11, %r10
	addq %r10, %r8
	cmpq $0, %r9
	setl %r10b
	movzbq %r10b, %r10
	negq %r10
	movq %r10, %r11
	andq $7, %r11
	movq %r9, %r10
	andq $0, %r10
	subq %r11, %r8
	subq %r10, %r8
	movq %rcx, %r10
	sarq $63, %r10
	cmpq %r8, %r10
	jnz .Lbb14
	movq %rcx, %r8
	addq %rax, %r8
	movq %r8, %r10
	xorq %rax, %r10
	movq %rcx, %r11
	xorq %r8, %r11
	andq %r11, %r10
	cmpq $0, %r10
	jl .Lbb13
	movq $9223372036854775806, %rax
	cmpq %rax, %r9
	jg .Lbb11
	movq %r8, %rcx
	sarq $63, %rcx
	movq %rcx, %rax
	xorq %r8, %rax
	movq %rax, %r10
	subq %rcx, %r10
	movq $896011011859258473, %r11
	movq %r10, %rax
	mulq %r11
	movq %rdx, %rax
	subq %rax, %r10
	shrq $1, %r10
	addq %r10, %rax
	shrq $19, %rax
	xorq %rcx, %rax
	subq %rcx, %rax
	imulq $1000003, %rax, %rax
	negq %rax
	addq %r8, %rax
	cmpq $0, %rax
	setnz %r8b
	movzbq %r8b, %r8
	andq %r8, %rcx
	negq %rcx
	andq $1000003, %rcx
	addq %rcx, %rax
	addq $1, %r9
	jmp .Lbb6
.Lbb11:
	movq %r9, %rdx
	.loc 1 21
	movl $64, %r8d
	movl $1, %ecx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb13:
	.loc 1 15
	movl $64, %r8d
	movq %rax, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb14:
	movq %r9, %rdx
	.loc 1 14
	movl $64, %r8d
	movl $7, %ecx
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb16:
	movl $0, %ecx
.p2align 4
.Lbb17:
	cmpq %rsi, %rcx
	jge .Lbb19
	imulq $7, %rcx, %rdi
	movq %rdi, %r8
	addq %rax, %r8
	movq %r8, %rdi
	sarq $63, %rdi
	movq %r8, %rax
	xorq %rdi, %rax
	movq %rax, %r9
	subq %rdi, %r9
	movq $896011011859258473, %r10
	movq %r9, %rax
	mulq %r10
	movq %rdx, %rax
	subq %rax, %r9
	shrq $1, %r9
	addq %r9, %rax
	shrq $19, %rax
	xorq %rdi, %rax
	subq %rdi, %rax
	imulq $1000003, %rax, %rax
	negq %rax
	addq %r8, %rax
	cmpq $0, %rax
	setnz %r8b
	movzbq %r8b, %r8
	andq %r8, %rdi
	negq %rdi
	andq $1000003, %rdi
	addq %rdi, %rax
	addq $1, %rcx
	jmp .Lbb17
.Lbb19:
	popq %rbx
	leave
	ret
.type myl_f_edca249d8d1f9a5b7d1a0f3ef54e3969bf3acb65499aaea1316cc43a98315502, @function
.size myl_f_edca249d8d1f9a5b7d1a0f3ef54e3969bf3acb65499aaea1316cc43a98315502, .-myl_f_edca249d8d1f9a5b7d1a0f3ef54e3969bf3acb65499aaea1316cc43a98315502
/* end function myl_f_edca249d8d1f9a5b7d1a0f3ef54e3969bf3acb65499aaea1316cc43a98315502 */

.section .note.GNU-stack,"",@progbits
