.file 1 "myl_f_7d4c7bb943c4902eb14b04cb668fbfa54b7391586b55d9371fc3f44d9121fd4b"
.text
.balign 16
.globl myl_f_7d4c7bb943c4902eb14b04cb668fbfa54b7391586b55d9371fc3f44d9121fd4b
myl_f_7d4c7bb943c4902eb14b04cb668fbfa54b7391586b55d9371fc3f44d9121fd4b:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	movq %r8, %rax
	.loc 1 1
	cmpq %rdx, %rcx
	setg %r8b
	movzbq %r8b, %r8
	movq %rcx, %r9
	subq %rdx, %r9
	cmpq $16, %r9
	setae %r9b
	movzbq %r9b, %r9
	andq %r9, %r8
	cmpl $0, %r8d
	jnz .Lbb2
	movq %rax, %r8
	jmp .Lbb12
.Lbb2:
	movq $4503599627370496, %r8
	movq %rdx, %r9
	addq %r8, %r9
	movq $9007199254740992, %r8
	cmpq %r8, %r9
	jbe .Lbb4
	movq %rax, %r8
	jmp .Lbb12
.Lbb4:
	movq $4503599627370496, %r8
	movq %rcx, %r9
	addq %r8, %r9
	movq $9007199254740992, %r8
	cmpq %r8, %r9
	jbe .Lbb6
	movq %rax, %r8
	jmp .Lbb12
.Lbb6:
	movq $4503599627370496, %r8
	movq %rax, %r9
	addq %r8, %r9
	movq $9007199254740992, %r8
	cmpq %r8, %r9
	jbe .Lbb8
	movq %rax, %r8
	jmp .Lbb12
.Lbb8:
	cmpq $0, %rdx
	jge .Lbb10
	movq %rax, %r8
	jmp .Lbb12
.Lbb10:
	movq (%rsi), %r8
	cmpq %r8, %rcx
	jle .Lbb22
	movq %rax, %r8
.p2align 4
.Lbb12:
	cmpq %rcx, %rdx
	jge .Lbb27
	movq (%rsi), %rax
	movq %rdx, %r9
	sarq $63, %r9
	andq %rax, %r9
	addq %rdx, %r9
	cmpq %rax, %r9
	jae .Lbb20
	movq 32(%rsi), %rax
	movzbq (%rax, %r9, 1), %r9
	movq %r8, %rax
	addq %r9, %r8
	movq %r8, %r10
	xorq %rax, %r10
	movq %r9, %r11
	xorq %r8, %r11
	andq %r11, %r10
	cmpq $0, %r10
	jl .Lbb18
	movq $9223372036854775806, %rax
	cmpq %rax, %rdx
	jg .Lbb17
	addq $1, %rdx
	jmp .Lbb12
.Lbb17:
	.loc 1 20
	movl $64, %r8d
	movl $1, %ecx
	movq %rdx, %rax
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb18:
	movq %r9, %rcx
	.loc 1 16
	movl $64, %r8d
	movq %rax, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb20:
	xchgq %rdx, %rax
	.loc 1 14
	movq %rax, %rsi
	callq myl_qbe_fail_index_bounds
	ud2
.Lbb22:
	movq %r8, %rdi
	movq 32(%rsi), %rsi
	movq %rax, %r8
	movq %rdi, %rax
.p2align 4
.Lbb25:
	cmpq %rcx, %rdx
	jge .Lbb27
	movzbq (%rsi, %rdx, 1), %rdi
	addq %rdi, %r8
	addq $1, %rdx
	jmp .Lbb25
.Lbb27:
	movq %r8, %rax
	leave
	ret
.type myl_f_7d4c7bb943c4902eb14b04cb668fbfa54b7391586b55d9371fc3f44d9121fd4b, @function
.size myl_f_7d4c7bb943c4902eb14b04cb668fbfa54b7391586b55d9371fc3f44d9121fd4b, .-myl_f_7d4c7bb943c4902eb14b04cb668fbfa54b7391586b55d9371fc3f44d9121fd4b
/* end function myl_f_7d4c7bb943c4902eb14b04cb668fbfa54b7391586b55d9371fc3f44d9121fd4b */

.section .note.GNU-stack,"",@progbits
