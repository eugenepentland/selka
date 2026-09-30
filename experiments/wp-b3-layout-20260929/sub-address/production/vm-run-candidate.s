.file 1 "myl_f_a0e96f299197f34d601c1a9da1cbd514090305d2a21036d06ba179b733ea6e29"
.text
.balign 16
.globl myl_f_a0e96f299197f34d601c1a9da1cbd514090305d2a21036d06ba179b733ea6e29
myl_f_a0e96f299197f34d601c1a9da1cbd514090305d2a21036d06ba179b733ea6e29:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $7336, %rsp
	pushq %rbx
	pushq %r12
	pushq %r13
	pushq %r14
	pushq %r15
	movq %rdx, -3648(%rbp)
	movq %rsi, %r13
	movq %rdi, %rbx
	movq $0, -6160(%rbp)
	movq 64(%rbx), %rax
	movl $0, %r8d
	movl %r8d, -3716(%rbp)
	movl $0, %r12d
	movl %r12d, -3720(%rbp)
	leaq -3832(%rbp), %rcx
	cmpq %rax, %rcx
	jb .Lbb2708
	subq $208, %rsp
	movq %rsp, %rcx
	subq $16, %rsp
	movq %rsp, %rdx
	movq %rdx, -3752(%rbp)
	subq $208, %rsp
	movq %rsp, %r8
	movq %r8, -3744(%rbp)
	subq $208, %rsp
	movq %rsp, %rax
	movq %rax, -3808(%rbp)
	subq $208, %rsp
	movq %rsp, %r11
	movq %r11, -3800(%rbp)
	subq $16, %rsp
	movq %rsp, %rdx
	movq %rdx, -3736(%rbp)
	subq $208, %rsp
	movq %rsp, %r11
	movq %r11, -3792(%rbp)
	movq %rcx, %r14
	subq $208, %rsp
	movq %rsp, %rcx
	movq %rcx, -3784(%rbp)
	.loc 1 1
	.loc 1 1
	.loc 1 1
	.loc 1 1
	.loc 1 1
	.loc 1 1
	.loc 1 1
	.loc 1 1
	.loc 1 1
	.loc 1 1
	.loc 1 1
	.loc 1 1
	.loc 1 1
	.loc 1 1
	.loc 1 1
	.loc 1 1
	.loc 1 1
	.loc 1 1
	.loc 1 1
	.loc 1 1
	.loc 1 1
	.loc 1 1
	.loc 1 1
	.loc 1 1
	movq %rbx, %rdi
	callq myl_qbe_heap
	movq %rax, %rdi
	.loc 1 1
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_qbe_region_mark
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, %r14
	movq %r14, -3816(%rbp)
	movq %rsi, %rdx
	addq $136, %rdx
	movq %rdx, -3704(%rbp)
	movq 136(%rsi), %rax
	movq 144(%rsi), %rdx
	movq $-9223372036854775807, %r8
	cmpq %r8, %rdx
	jl .Lbb2706
	movq %rcx, %r12
	movq %rdx, %rcx
	subq $1, %rcx
	cmpq $0, %rcx
	jl .Lbb4
	movq %rcx, %r9
	movq %r12, %rcx
	jmp .Lbb7
.Lbb4:
	movq (%rax), %r10
	movq $9223372036854775807, %rdx
	cmpq %rdx, %r10
	ja .Lbb2704
	movq %r10, %r9
	addq %rcx, %r9
	movq %r10, %rdx
	xorq %r9, %rdx
	movq %rcx, %r8
	xorq %r9, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jl .Lbb2702
	movq %r12, %rcx
.Lbb7:
	movq (%rax), %rdx
	cmpq %rdx, %r9
	jb .Lbb10
	movq %rbx, %rdi
	.loc 1 20
	movq %r9, %rsi
	movq %rdi, %rbx
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb10:
	movq 32(%rax), %rax
	imulq $24, %r9, %rdx
	movq 0(%rax, %rdx, 1), %r8
	movq %r8, 0(%rcx)
	movq 8(%rax, %rdx, 1), %r8
	movq %r8, 8(%rcx)
	movq 16(%rax, %rdx, 1), %rax
	movq %rax, 16(%rcx)
	.loc 1 21
	movq %rsi, %rdx
	movq %rsi, %r13
	movq %rbx, %rsi
	movq %rdi, %r12
	leaq -7320(%rbp), %rdi
	callq myl_f_bf0431d3d9e553eacefcb10ebb00251bb8b43354cc87fd12c99ceb5644f705d6
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movq 0(%rax), %rdx
	movq %rdx, -6392(%rbp)
	movq 8(%rax), %rdx
	movq %rdx, -6384(%rbp)
	movq 16(%rax), %rdx
	movq %rdx, -6376(%rbp)
	movq 24(%rax), %rdx
	movq %rdx, -6368(%rbp)
	movq 32(%rax), %rax
	movq %rax, -6360(%rbp)
	movq -6392(%rbp), %rax
	movq %rax, -7016(%rbp)
	movq -6384(%rbp), %rax
	movq %rax, -7008(%rbp)
	movq -6376(%rbp), %rax
	movq %rax, -7000(%rbp)
	movq -6368(%rbp), %rax
	movq %rax, -6992(%rbp)
	movq -6360(%rbp), %rax
	movq %rax, -6984(%rbp)
	movq -7016(%rbp), %rax
	cmpq $0, %rax
	setnz %dl
	movzbl %dl, %edx
	cmpl $0, %edx
	jz .Lbb12
	movq -16(%rax), %rax
	movq $5764607523034234881, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb17
.Lbb12:
	movq -7008(%rbp), %rax
	cmpq $0, %rax
	jz .Lbb14
	movq -16(%rax), %rax
	movq $5764607523034234881, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb17
.Lbb14:
	movq -7000(%rbp), %rax
	cmpq $0, %rax
	jz .Lbb16
	movq -16(%rax), %rax
	movq $5764607523034234881, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb17
.Lbb16:
	movq -7016(%rbp), %rax
	movq %rax, -6392(%rbp)
	movq -7008(%rbp), %rax
	movq %rax, -6384(%rbp)
	movq -7000(%rbp), %rax
	movq %rax, -6376(%rbp)
	movq -6992(%rbp), %rax
	movq %rax, -6368(%rbp)
	movq -6984(%rbp), %rax
	movq %rax, -6360(%rbp)
	movq $0, -7016(%rbp)
	movq $0, -7008(%rbp)
	movq $0, -7000(%rbp)
	movq $0, -6992(%rbp)
	movq $0, -6984(%rbp)
	jmp .Lbb19
.Lbb17:
	.loc 1 22
	leaq -7016(%rbp), %rdx
	movq %rsi, %r13
	leaq -6392(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_take
	movq %r13, %rsi
	movq %r12, %rdi
	cmpl $0, %eax
	jnz .Lbb19
	.loc 1 22
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 22
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2692
.Lbb19:
	movq -6392(%rbp), %rax
	movq %rax, -6144(%rbp)
	movq -6384(%rbp), %rax
	movq %rax, -6136(%rbp)
	movq -6376(%rbp), %rax
	movq %rax, -6128(%rbp)
	movq -6368(%rbp), %rax
	movq %rax, -6120(%rbp)
	movq -6360(%rbp), %rax
	movq %rax, -6112(%rbp)
	leaq -6184(%rbp), %rax
	movq %rax, %r8
	addq $16, %r8
	movq %r8, -3712(%rbp)
	leaq -4312(%rbp), %rax
	movq %rax, %r8
	addq $8, %r8
	movq %r8, -3728(%rbp)
	leaq -4104(%rbp), %rax
	addq $8, %rax
	movq %rax, -3760(%rbp)
	movq %rsi, %rdx
	addq $120, %rdx
	movq %rdx, -3824(%rbp)
	leaq -6144(%rbp), %rax
	addq $8, %rax
	movq %rax, -3776(%rbp)
	leaq -6144(%rbp), %rax
	movq %rax, %r10
	addq $16, %r10
	movq %r10, -3768(%rbp)
	xchgq %rdi, %rbx
	movl $1, %r13d
	movl $2, %r9d
	movl $0, -100(%rbp)
	movl $2, %r15d
	movl $0, %r8d
	movl $0, %r12d
	movl $0, %ecx
	movl $0, %r14d
	movl $3735936685, %eax
.p2align 4
.Lbb21:
	movl %r13d, -3664(%rbp)
	movl %r9d, -3668(%rbp)
	movl %r8d, -3680(%rbp)
	movl %r12d, -3588(%rbp)
	movl %ecx, -3672(%rbp)
	movl %r14d, -3676(%rbp)
	movq %rax, -3656(%rbp)
	movq -6136(%rbp), %r11
	movq %r11, -16(%rbp)
	movq -6120(%rbp), %rdx
	movq %rdx, -64(%rbp)
	cmpq $0, %rdx
	jge .Lbb24
	movq (%r11), %r10
	movq $9223372036854775807, %r11
	cmpq %r11, %r10
	ja .Lbb2700
	movq %rdx, %r11
	addq %r10, %r11
	movq %r11, -40(%rbp)
	movq %r10, %r11
	xorq -40(%rbp), %r11
	movq %r11, -32(%rbp)
	xorq -40(%rbp), %rdx
	movq %rdx, -24(%rbp)
	movq -16(%rbp), %r11
	movq -32(%rbp), %rdx
	andq -24(%rbp), %rdx
	movq %rdx, -48(%rbp)
	movq -40(%rbp), %rdx
	cmpq $0, -48(%rbp)
	jl .Lbb2698
.Lbb24:
	movq (%r11), %r10
	movq %r10, -56(%rbp)
	movl %r14d, %r10d
	movl -100(%rbp), %r14d
	cmpq -56(%rbp), %rdx
	jae .Lbb2696
	movq 32(%r11), %r11
	movq (%r11, %rdx, 8), %r11
	movq %r11, -1680(%rbp)
	cmpl $0, %r14d
	jz .Lbb31
	testl $28, %r15d
	jnz .Lbb29
	.loc 1 42
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movl %r15d, %r9d
	movq %r14, %rsi
	movq %r13, %rdi
	movl -3664(%rbp), %r13d
	movl %r9d, %r15d
	movl -3668(%rbp), %r9d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl -3676(%rbp), %r10d
	movq -3656(%rbp), %rax
	movq -1680(%rbp), %r11
	movl $0, %r14d
	jmp .Lbb31
.Lbb29:
	.loc 1 42
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movl %r15d, %r9d
	movq %r14, %rsi
	movq %r13, %rdi
	movl -3664(%rbp), %r13d
	movl %r9d, %r15d
	movl -3668(%rbp), %r9d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl -3676(%rbp), %r10d
	movq -3656(%rbp), %rax
	movq -1680(%rbp), %r11
	movl $0, %r14d
.Lbb31:
	movq $9223372036854775806, %rdx
	movq %rdx, -72(%rbp)
	movq -64(%rbp), %rdx
	cmpq -72(%rbp), %rdx
	jg .Lbb2694
	addq $1, %rdx
	movq %rdx, -2400(%rbp)
	movq %rdx, -6120(%rbp)
	movq -3648(%rbp), %rdx
	cmpq $0, %r11
	jz .Lbb2617
	cmpq $1, %r11
	jz .Lbb2557
	cmpq $2, %r11
	jz .Lbb2496
	cmpq $3, %r11
	jz .Lbb2435
	cmpq $4, %r11
	jz .Lbb2422
	cmpq $5, %r11
	setz %dl
	movzbq %dl, %rdx
	cmpl $0, %edx
	jnz .Lbb2325
	cmpq $6, %r11
	jz .Lbb2203
	cmpq $7, %r11
	setz %dl
	movzbq %dl, %rdx
	movq %rdx, -80(%rbp)
	movq -3704(%rbp), %rdx
	cmpl $0, -80(%rbp)
	jnz .Lbb2117
	cmpq $8, %r11
	jz .Lbb2082
	cmpq $9, %r11
	jz .Lbb1995
	cmpq $10, %r11
	jz .Lbb1978
	cmpq $11, %r11
	jz .Lbb1961
	cmpq $12, %r11
	jz .Lbb1874
	cmpq $13, %r11
	jz .Lbb1787
	cmpq $14, %r11
	jz .Lbb1676
	movq -3824(%rbp), %rdx
	cmpq $15, %r11
	jz .Lbb1519
	cmpq $16, %r11
	setz %al
	movzbq %al, %rax
	cmpq $17, %r11
	setz %dl
	movzbq %dl, %rdx
	cmpl $0, %eax
	movl $1, %eax
	cmovz %rdx, %rax
	cmpq $19, %r11
	setz %dl
	movzbq %dl, %rdx
	cmpl $0, %eax
	movl $1, %eax
	cmovz %rdx, %rax
	cmpq $20, %r11
	setz %dl
	movzbq %dl, %rdx
	cmpl $0, %eax
	movl $1, %eax
	cmovz %rdx, %rax
	cmpq $21, %r11
	setz %dl
	movzbq %dl, %rdx
	cmpl $0, %eax
	movl $1, %eax
	cmovz %rdx, %rax
	movq %rax, -88(%rbp)
	movl -3664(%rbp), %r13d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	cmpl $0, -88(%rbp)
	jnz .Lbb1438
	cmpq $18, %r11
	jz .Lbb1357
	cmpq $22, %r11
	jz .Lbb1271
	cmpq $23, %r11
	jz .Lbb1190
	cmpq $24, %r11
	jz .Lbb1140
	cmpq $25, %r11
	jz .Lbb1119
	cmpq $26, %r11
	jz .Lbb1082
	cmpq $27, %r11
	jz .Lbb1060
	cmpq $28, %r11
	setz %dl
	movzbq %dl, %rdx
	movq %rdx, -96(%rbp)
	movq -3648(%rbp), %rdx
	cmpl $0, -96(%rbp)
	jnz .Lbb890
	cmpq $29, %r11
	jz .Lbb717
	cmpq $30, %r11
	jz .Lbb516
	cmpq $31, %r11
	jz .Lbb499
	cmpq $32, %r11
	jz .Lbb468
	cmpq $33, %r11
	jz .Lbb248
	cmpq $34, %r11
	jz .Lbb163
	cmpq $35, %r11
	jz .Lbb85
	cmpq $36, %r11
	jz .Lbb71
	xchgl %r9d, %r12d
	xchgl %r15d, %r9d
	xchgl %r14d, %r10d
	movl $1, %r11d
	jmp .Lbb2674
.Lbb71:
	.loc 1 1694
	leaq -6144(%rbp), %rdx
	movq %rsi, %r13
	movq %rdi, %r12
	callq myl_f_8a26e9a4615ca34682c5764acec261356b4869f23d43f0849ec12dd016904162
	movl %r14d, %r10d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl %r12d, %r9d
	movl -3588(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r10d, %r14d
	movl -3676(%rbp), %r10d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	cmpl $0, %r14d
	jnz .Lbb73
	xchgl %r10d, %r14d
	jmp .Lbb78
.Lbb73:
	testl $28, %r15d
	jnz .Lbb76
	.loc 1 1694
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r15d, %r9d
	movq %r14, %rsi
	movq %r13, %rdi
	movl -3664(%rbp), %r13d
	movl %r9d, %r15d
	movl -3668(%rbp), %r9d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl -3676(%rbp), %r14d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb78
.Lbb76:
	.loc 1 1694
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r15d, %r9d
	movq %r14, %rsi
	movq %r13, %rdi
	movl -3664(%rbp), %r13d
	movl %r9d, %r15d
	movl -3668(%rbp), %r9d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl -3676(%rbp), %r14d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb78:
	movl %r10d, -104(%rbp)
	cmpl $0, %r8d
	jz .Lbb84
	testl $28, %r12d
	jnz .Lbb82
	.loc 1 1694
	movq %rsi, %r14
	leaq -6808(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movl %r15d, %r9d
	movq %r14, %rsi
	movq %r13, %rdi
	movl -104(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl %r9d, %r15d
	movl -3668(%rbp), %r9d
	movl -3672(%rbp), %ecx
	movl -3676(%rbp), %r14d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r8d
	jmp .Lbb84
.Lbb82:
	.loc 1 1694
	movq %rsi, %r14
	leaq -6808(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movl %r15d, %r9d
	movq %r14, %rsi
	movq %r13, %rdi
	movl -104(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl %r9d, %r15d
	movl -3668(%rbp), %r9d
	movl -3672(%rbp), %ecx
	movl -3676(%rbp), %r14d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r8d
.Lbb84:
	xchgl %r9d, %r12d
	xchgl %r15d, %r9d
	movl $1, %r11d
	jmp .Lbb2674
.Lbb85:
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	cmpl $0, %r14d
	jz .Lbb92
	testl $28, %r15d
	jnz .Lbb90
	.loc 1 1648
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movq %r14, %rsi
	movq %r13, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r14d
	jmp .Lbb92
.Lbb90:
	.loc 1 1648
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r14, %rsi
	movq %r13, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r14d
.Lbb92:
	movl %r14d, %r10d
	cmpl $0, %r10d
	jnz .Lbb94
	movl %r15d, %r9d
	jmp .Lbb99
.Lbb94:
	testl $28, %r15d
	jnz .Lbb97
	.loc 1 1651
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r14, %rsi
	movq %r13, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl %r15d, %r9d
	movl $0, %r10d
	jmp .Lbb99
.Lbb97:
	.loc 1 1651
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r15d, %r9d
	movq %r14, %rsi
	movq %r13, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb99:
	cmpl $0, %r10d
	jz .Lbb119
	testl $28, %r9d
	jnz .Lbb110
	movq -7016(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb109
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r10
	andq %r10, %rax
	cmpq $0, %rax
	jnz .Lbb108
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb107
	movl %r9d, %r15d
	movq -24(%rcx), %r9
	cmpq $0, %r9
	jnz .Lbb106
	.loc 1 1652
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0_rcg_drop
	movl %r15d, %r9d
	movq %r14, %rsi
	movq %r13, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	jmp .Lbb109
.Lbb106:
	movl %r15d, %r9d
.Lbb107:
	movq %rax, -32(%rcx)
.Lbb108:
	movq $0, -7016(%rbp)
.Lbb109:
	movl $0, %r10d
	jmp .Lbb119
.Lbb110:
	movq -7016(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb118
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r10
	andq %r10, %rax
	cmpq $0, %rax
	jnz .Lbb117
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb116
	movl %r9d, %r15d
	movq -32(%rcx), %r9
	cmpq $0, %r9
	jnz .Lbb115
	.loc 1 1652
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0_rcg_unloan
	movl %r15d, %r9d
	movq %r14, %rsi
	movq %r13, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	jmp .Lbb118
.Lbb115:
	movl %r15d, %r9d
.Lbb116:
	movq %rax, -24(%rcx)
.Lbb117:
	movq $0, -7016(%rbp)
.Lbb118:
	movl $0, %r10d
.Lbb119:
	movl %r10d, -124(%rbp)
	movq 136(%rsi), %rax
	cmpq $0, %rax
	jz .Lbb124
	movq -16(%rax), %rcx
	movl %r9d, %r15d
	movq $6917529027641081858, %r9
	andq %r9, %rcx
	cmpq $0, %rcx
	jnz .Lbb123
	movq -32(%rax), %rax
	cmpq $2, %rax
	jae .Lbb123
	movl %r15d, %r9d
	jmp .Lbb124
.Lbb123:
	.loc 1 1652
	movl $0, %ecx
	movq %r11, %rdx
	movq %rsi, %r14
	movq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0@gotpcrel(%rip), %rsi
	movq %rdi, %r13
	callq myl_qbe_rc_unique_field
	movl %r15d, %r9d
	movq %r14, %rsi
	movq %r13, %rdi
	movl -124(%rbp), %r10d
	movq -2400(%rbp), %r8
	movq -3648(%rbp), %rdx
	cmpl $0, %eax
	jz .Lbb2692
.Lbb124:
	movq 136(%rsi), %rax
	movq %rax, -120(%rbp)
	movl %r9d, %r15d
	movq 144(%rsi), %r9
	movq %r9, -112(%rbp)
	cmpl $0, %r10d
	jnz .Lbb126
	movl %r10d, -128(%rbp)
	jmp .Lbb131
.Lbb126:
	testl $28, %r15d
	jnz .Lbb129
	.loc 1 1654
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r15d, %r9d
	movq %r14, %rsi
	movq %r13, %rdi
	movq -2400(%rbp), %r8
	movl %r9d, %r15d
	movq -112(%rbp), %r9
	movq -120(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, -128(%rbp)
	jmp .Lbb131
.Lbb129:
	.loc 1 1654
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r15d, %r9d
	movq %r14, %rsi
	movq %r13, %rdi
	movq -2400(%rbp), %r8
	movl %r9d, %r15d
	movq -112(%rbp), %r9
	movq -120(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, -128(%rbp)
.Lbb131:
	movq $-9223372036854775807, %rcx
	cmpq %rcx, %r9
	jl .Lbb161
	subq $1, %r9
	cmpq $0, %r9
	jge .Lbb135
	movq (%rax), %r10
	movq $9223372036854775807, %rcx
	cmpq %rcx, %r10
	ja .Lbb159
	movq %r9, %rcx
	addq %r10, %r9
	movq %r10, %r11
	xorq %r9, %r11
	movq %rcx, %r13
	xorq %r9, %r13
	andq %r13, %r11
	cmpq $0, %r11
	jl .Lbb157
.Lbb135:
	movq (%rax), %rcx
	cmpq %rcx, %r9
	jae .Lbb155
	movq 32(%rax), %r10
	imulq $24, %r9, %rcx
	movq 0(%r10, %rcx, 1), %r11
	movq %r11, -5728(%rbp)
	movq 8(%r10, %rcx, 1), %r11
	movq %r11, -5720(%rbp)
	movq 16(%r10, %rcx, 1), %r10
	movq %r10, -5712(%rbp)
	movq (%rax), %r10
	cmpq %r10, %r9
	jae .Lbb153
	movq 32(%rax), %r10
	movq 0(%rcx, %r10, 1), %r11
	movq %r11, -5728(%rbp)
	movq 8(%rcx, %r10, 1), %r11
	movq %r11, -5720(%rbp)
	movq 16(%rcx, %r10, 1), %r10
	movq %r10, -5712(%rbp)
	movq -5728(%rbp), %r10
	movq %r10, -3864(%rbp)
	movq -5720(%rbp), %r10
	movq %r10, -3856(%rbp)
	movq -5712(%rbp), %r10
	movq %r10, -3848(%rbp)
	movq %r8, -3856(%rbp)
	movq (%rax), %r8
	cmpq %r8, %r9
	jae .Lbb151
	movq 32(%rax), %r8
	movq -3864(%rbp), %rax
	movq %rax, 0(%rcx, %r8, 1)
	movq -3856(%rbp), %rax
	movq %rax, 8(%rcx, %r8, 1)
	movq -3848(%rbp), %rax
	movq %rax, 16(%rcx, %r8, 1)
	.loc 1 1685
	movq %rsi, %r14
	movq %rdi, %r13
	callq myl_f_4d66cd4231d4d1dca45177a9eaa74f584b15e1afd3ce4666fe2966f861de9665
	movl %r15d, %r9d
	movq %r14, %rsi
	movq %r13, %rdi
	movq %rax, %r11
	movl -128(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl %r9d, %r15d
	movl -3668(%rbp), %r9d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl -3676(%rbp), %r14d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movq %r11, -136(%rbp)
	cmpl $0, %r10d
	jz .Lbb144
	testl $28, %r15d
	jnz .Lbb142
	.loc 1 1685
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r15d, %r9d
	movq %r14, %rsi
	movq %r13, %rdi
	movl -3664(%rbp), %r13d
	movl %r9d, %r15d
	movl -3668(%rbp), %r9d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl -3676(%rbp), %r14d
	movq -3656(%rbp), %rax
	movq -136(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb144
.Lbb142:
	.loc 1 1685
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r15d, %r9d
	movq %r14, %rsi
	movq %r13, %rdi
	movl -3664(%rbp), %r13d
	movl %r9d, %r15d
	movl -3668(%rbp), %r9d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl -3676(%rbp), %r14d
	movq -3656(%rbp), %rax
	movq -136(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb144:
	movl %r10d, -148(%rbp)
	cmpl $0, %r8d
	jz .Lbb150
	testl $28, %r12d
	jnz .Lbb148
	.loc 1 1685
	movq %rsi, %r14
	leaq -6808(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_3ece1c6f770ecd2a506fa806688c97e383087567b3626d4a9ce4529758a6df1f_rcg_drop
	movl %r15d, %r9d
	movq %r14, %rsi
	movq %r13, %rdi
	movl -148(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl %r9d, %r15d
	movl -3668(%rbp), %r9d
	movl -3672(%rbp), %ecx
	movl -3676(%rbp), %r14d
	movq -3656(%rbp), %rax
	movq -136(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r8d
	jmp .Lbb150
.Lbb148:
	.loc 1 1685
	movq %rsi, %r14
	leaq -6808(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_3ece1c6f770ecd2a506fa806688c97e383087567b3626d4a9ce4529758a6df1f_rcg_unloan
	movl %r15d, %r9d
	movq %r14, %rsi
	movq %r13, %rdi
	movl -148(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl %r9d, %r15d
	movl -3668(%rbp), %r9d
	movl -3672(%rbp), %ecx
	movl -3676(%rbp), %r14d
	movq -3656(%rbp), %rax
	movq -136(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r8d
.Lbb150:
	xchgl %r9d, %r12d
	xchgl %r15d, %r9d
	jmp .Lbb2674
.Lbb151:
	movq %r8, %rdx
	.loc 1 1679
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb153:
	movq %r10, %rdx
	.loc 1 1673
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb155:
	movq %rcx, %rdx
	.loc 1 1670
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb157:
	movq %r10, %rsi
	.loc 1 1665
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb159:
	movq %r10, %rsi
	.loc 1 1663
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb161:
	movq %r9, %rdx
	.loc 1 1656
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb163:
	.loc 1 1596
	movq %rsi, %r13
	leaq -6144(%rbp), %rsi
	movq %rdi, %r12
	callq myl_f_94484f74f9fdfe749fe3bbd5703ff3b6b2a0ee43d3569a1125fbe02c5095250d
	movl %r14d, %r10d
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, -144(%rbp)
	movl -3668(%rbp), %r12d
	cmpl $0, %r10d
	jnz .Lbb165
	movq %rsi, %r14
	movl %r10d, -152(%rbp)
	jmp .Lbb170
.Lbb165:
	testl $28, %r15d
	jnz .Lbb168
	.loc 1 1596
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movq %r14, %rsi
	movq %r13, %rdi
	movq %rsi, %r14
	movl $0, -152(%rbp)
	jmp .Lbb170
.Lbb168:
	.loc 1 1596
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r13, %rdi
	movl $0, -152(%rbp)
.Lbb170:
	.loc 1 1600
	movq %rdi, %r13
	callq myl_f_a1ee89ef02f5de3a0549ceef8b403f960b5d820e5be22eacf42a3abf03f1c216
	movl %r15d, %r9d
	movq %r14, %rsi
	movq %r13, %rdi
	movq %rax, %r11
	movq %rdx, %r10
	movq -3816(%rbp), %rcx
	movq -3760(%rbp), %rax
	movq -3728(%rbp), %r8
	movq -144(%rbp), %rdx
	movq %r11, -7040(%rbp)
	movq %r10, -7032(%rbp)
	movq -7040(%rbp), %r10
	movq %r10, -6392(%rbp)
	movq -7032(%rbp), %r10
	movq %r10, -6384(%rbp)
	movq -6392(%rbp), %r10
	movq %r10, -6600(%rbp)
	movq -6384(%rbp), %r10
	movq %r10, -6592(%rbp)
	movq $0, -4312(%rbp)
	movq $0, -4304(%rbp)
	movq $0, -4296(%rbp)
	movq %rdx, -4312(%rbp)
	movq -6600(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb172
	movl %r9d, %r15d
	jmp .Lbb173
.Lbb172:
	movq -16(%rdx), %rdx
	movl %r9d, %r15d
	movq $5764607523034234881, %r9
	andq %r9, %rdx
	cmpq $0, %rdx
	jnz .Lbb174
.Lbb173:
	movq -6600(%rbp), %rdx
	movq %rdx, -6392(%rbp)
	movq -6592(%rbp), %rdx
	movq %rdx, -6384(%rbp)
	movq $0, -6600(%rbp)
	movq $0, -6592(%rbp)
	jmp .Lbb175
.Lbb174:
	.loc 1 1601
	leaq -6600(%rbp), %rdx
	movq %rsi, %r14
	leaq -6392(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_81d71c98b196ce876b8748e8f5e1c439a764a7854aeb5e4ef7865d0716f2ecef_rcg_take
	movq %r14, %rsi
	movq %r13, %rdi
	movl %eax, %edx
	movq -3816(%rbp), %rcx
	movq -3760(%rbp), %rax
	movq -3728(%rbp), %r8
	cmpl $0, %edx
	jz .Lbb246
.Lbb175:
	movq -6392(%rbp), %rdx
	movq %rdx, 0(%r8)
	movq -6384(%rbp), %rdx
	movq %rdx, 8(%r8)
	movq -4312(%rbp), %rdx
	movq %rdx, -6808(%rbp)
	movq -4304(%rbp), %rdx
	movq %rdx, -6800(%rbp)
	movq -4296(%rbp), %rdx
	movq %rdx, -6792(%rbp)
	movq $0, -4104(%rbp)
	movq $0, -4096(%rbp)
	movq $0, -4088(%rbp)
	movq $0, -4080(%rbp)
	movq $0, -4072(%rbp)
	movq $0, -4064(%rbp)
	movq $0, -4056(%rbp)
	movl $6, -4104(%rbp)
	movq -6800(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb177
	movq -16(%rdx), %rdx
	movq $5764607523034234881, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jnz .Lbb178
.Lbb177:
	movq %rax, %rcx
	movq -6808(%rbp), %rax
	movq %rax, -6392(%rbp)
	movq -6800(%rbp), %rax
	movq %rax, -6384(%rbp)
	movq -6792(%rbp), %rax
	movq %rax, -6376(%rbp)
	movq $0, -6808(%rbp)
	movq $0, -6800(%rbp)
	movq $0, -6792(%rbp)
	jmp .Lbb179
.Lbb178:
	.loc 1 1602
	movq %rcx, %r11
	leaq -6808(%rbp), %rdx
	movq %rsi, %r14
	leaq -6392(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_1ca39ac918178cb6d21e4d894cf1bad7f4b058d5b48f5646eb1c4f427db8f3b6_rcg_take
	movq %r14, %rsi
	movq %r13, %rdi
	movq -3760(%rbp), %rcx
	cmpl $0, %eax
	jz .Lbb244
.Lbb179:
	movq -6392(%rbp), %rax
	movq %rax, 0(%rcx)
	movq -6384(%rbp), %rax
	movq %rax, 8(%rcx)
	movq -6376(%rbp), %rax
	movq %rax, 16(%rcx)
	movq -4104(%rbp), %rax
	movq %rax, -6808(%rbp)
	movq -4096(%rbp), %rax
	movq %rax, -6800(%rbp)
	movq -4088(%rbp), %rax
	movq %rax, -6792(%rbp)
	movq -4080(%rbp), %rax
	movq %rax, -6784(%rbp)
	movq -4072(%rbp), %rax
	movq %rax, -6776(%rbp)
	movq -4064(%rbp), %rax
	movq %rax, -6768(%rbp)
	movq -4056(%rbp), %rax
	movq %rax, -6760(%rbp)
	.loc 1 1603
	leaq -6808(%rbp), %rdx
	movq %rsi, %r14
	movq %rdi, %r13
	callq myl_f_6993cfd5bc46d9d696adcc139c626f2b677f81bea8031cc740fa79e8da2d676e
	movq %r14, %rsi
	movq %r13, %rdi
	movq %rax, -160(%rbp)
	movl -152(%rbp), %r10d
	cmpl $0, %r10d
	jnz .Lbb181
	movl %r10d, -164(%rbp)
	jmp .Lbb186
.Lbb181:
	testl $28, %r15d
	jnz .Lbb184
	.loc 1 1603
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r14, %rsi
	movq %r13, %rdi
	movl $0, -164(%rbp)
	jmp .Lbb186
.Lbb184:
	.loc 1 1603
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r14, %rsi
	movq %r13, %rdi
	movl $0, -164(%rbp)
.Lbb186:
	.loc 1 1603
	movq %rsi, %r14
	leaq -6808(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_a83873657e77deb1bf51281383ae925ccb1b4b6510284b93a36500031c0efc14_rcg_drop
	movq %r14, %rsi
	movq %r13, %rdi
	movl -3716(%rbp), %r8d
	movl -164(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movq -160(%rbp), %rcx
	movq %rdx, %r9
	movq -3648(%rbp), %rdx
	movq $0, -3896(%rbp)
	movq $0, -3888(%rbp)
	movl $3, -3896(%rbp)
	movq %rcx, -3888(%rbp)
	movq -3896(%rbp), %rcx
	movq %rcx, -6072(%rbp)
	movq -3888(%rbp), %rcx
	movq %rcx, -6064(%rbp)
	cmpl $0, %r10d
	jz .Lbb192
	testl $28, %r15d
	jnz .Lbb190
	.loc 1 1609
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r14, %rsi
	movq %r13, %rdi
	movl -3716(%rbp), %r8d
	movl -3664(%rbp), %r13d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movq %rdx, %r9
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb192
.Lbb190:
	.loc 1 1609
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r14, %rsi
	movq %r13, %rdi
	movl -3716(%rbp), %r8d
	movl -3664(%rbp), %r13d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movq %rdx, %r9
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb192:
	cmpl $0, %r10d
	jz .Lbb210
	testl $28, %r15d
	jnz .Lbb202
	movq -7016(%rbp), %r10
	cmpq $0, %r10
	jz .Lbb201
	movq -16(%r10), %rcx
	movq $4611686018427387906, %r11
	andq %r11, %rcx
	cmpq $0, %rcx
	jnz .Lbb200
	movq -32(%r10), %rcx
	subq $1, %rcx
	jnz .Lbb199
	movq -24(%r10), %r11
	cmpq $0, %r11
	jnz .Lbb199
	.loc 1 1610
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a_rcg_drop
	movq %r14, %rsi
	movq %r13, %rdi
	movl -3716(%rbp), %r8d
	movl -3664(%rbp), %r13d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movq %rdx, %r9
	movq -3648(%rbp), %rdx
	jmp .Lbb201
.Lbb199:
	movq %rcx, -32(%r10)
.Lbb200:
	movq $0, -7016(%rbp)
.Lbb201:
	movl $0, %r10d
	jmp .Lbb210
.Lbb202:
	movq -7016(%rbp), %r10
	cmpq $0, %r10
	jz .Lbb209
	movq -16(%r10), %rcx
	movq $4611686018427387906, %r11
	andq %r11, %rcx
	cmpq $0, %rcx
	jnz .Lbb208
	movq -24(%r10), %rcx
	subq $1, %rcx
	jnz .Lbb207
	movq -32(%r10), %r11
	cmpq $0, %r11
	jnz .Lbb207
	.loc 1 1610
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a_rcg_unloan
	movq %r14, %rsi
	movq %r13, %rdi
	movl -3716(%rbp), %r8d
	movl -3664(%rbp), %r13d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movq %rdx, %r9
	movq -3648(%rbp), %rdx
	jmp .Lbb209
.Lbb207:
	movq %rcx, -24(%r10)
.Lbb208:
	movq $0, -7016(%rbp)
.Lbb209:
	movl $0, %r10d
.Lbb210:
	movl %r10d, -168(%rbp)
	movq 120(%rsi), %rcx
	cmpq $0, %rcx
	jz .Lbb214
	movq -16(%rcx), %r11
	movq $6917529027641081858, %r14
	andq %r14, %r11
	cmpq $0, %r11
	jnz .Lbb213
	movq -32(%rcx), %rcx
	cmpq $2, %rcx
	jb .Lbb214
.Lbb213:
	movq %r9, %rdx
	.loc 1 1610
	movl $0, %ecx
	movq %rsi, %r14
	movq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a@gotpcrel(%rip), %rsi
	movq %rdi, %r13
	callq myl_qbe_rc_unique_field
	movq %r14, %rsi
	movq %r13, %rdi
	movl %eax, %ecx
	movl -168(%rbp), %r10d
	movl -3716(%rbp), %r8d
	movl -3664(%rbp), %r13d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	cmpl $0, %ecx
	jz .Lbb2692
.Lbb214:
	movq 120(%rsi), %r11
	movq %r11, -176(%rbp)
	movq 128(%rsi), %rcx
	movq %rcx, -184(%rbp)
	cmpl $0, %r10d
	jnz .Lbb216
	movl %r15d, %r9d
	jmp .Lbb221
.Lbb216:
	testl $28, %r15d
	jnz .Lbb219
	.loc 1 1612
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r14, %rsi
	movq %r13, %rdi
	movl -3716(%rbp), %r8d
	movl -3664(%rbp), %r13d
	movq -3656(%rbp), %rax
	movq -184(%rbp), %rcx
	movq -176(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl %r15d, %r9d
	movl $0, %r10d
	jmp .Lbb221
.Lbb219:
	.loc 1 1612
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r15d, %r9d
	movq %r14, %rsi
	movq %r13, %rdi
	movl -3716(%rbp), %r8d
	movl -3664(%rbp), %r13d
	movq -3656(%rbp), %rax
	movq -184(%rbp), %rcx
	movq -176(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb221:
	cmpq $0, %rcx
	jl .Lbb223
	xchgl %r8d, %r13d
	jmp .Lbb225
.Lbb223:
	movq (%r11), %r15
	movq $9223372036854775807, %r8
	cmpq %r8, %r15
	ja .Lbb242
	movq %rcx, %r14
	addq %r15, %rcx
	movq %r15, %r8
	xorq %rcx, %r8
	movq %r8, -192(%rbp)
	movq %r14, %r8
	xorq %rcx, %r8
	movq %r8, -200(%rbp)
	movq -192(%rbp), %r8
	andq -200(%rbp), %r8
	cmpq $0, %r8
	movl %r13d, %r8d
	movl -3716(%rbp), %r13d
	jl .Lbb240
.Lbb225:
	movq -6072(%rbp), %r14
	movq %r14, -3880(%rbp)
	movq -6064(%rbp), %r14
	movq %r14, -3872(%rbp)
	movq (%r11), %r14
	cmpq %r14, %rcx
	jae .Lbb238
	movq 32(%r11), %r11
	imulq $16, %rcx, %r14
	movq -3880(%rbp), %rcx
	movq %rcx, 0(%r11, %r14, 1)
	movq -3872(%rbp), %rcx
	movq %rcx, 8(%r11, %r14, 1)
	movl %r9d, %r15d
	movq 128(%rsi), %r9
	movq %r9, -208(%rbp)
	cmpl $0, %r10d
	jnz .Lbb228
	movl %r15d, %r14d
	jmp .Lbb233
.Lbb228:
	testl $28, %r15d
	jnz .Lbb231
	.loc 1 1628
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r15d, %r9d
	movq %r14, %rsi
	movq %r13, %rdi
	movl -3716(%rbp), %r8d
	movl %r8d, %r13d
	movl -3664(%rbp), %r8d
	movq -3656(%rbp), %rax
	movl %r9d, %r15d
	movq -208(%rbp), %r9
	movq -3648(%rbp), %rdx
	movl %r15d, %r14d
	movl $0, %r10d
	jmp .Lbb233
.Lbb231:
	.loc 1 1628
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r15d, %r9d
	movq %r14, %rsi
	movq %r13, %rdi
	movl -3716(%rbp), %r8d
	movl %r8d, %r13d
	movl -3664(%rbp), %r8d
	movq -3656(%rbp), %rax
	movl %r9d, %r14d
	movq -208(%rbp), %r9
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb233:
	movq $9223372036854775806, %rcx
	cmpq %rcx, %r9
	jg .Lbb236
	movq %r9, %rcx
	addq $1, %rcx
	movq %rcx, 128(%rsi)
	movl %r14d, %r9d
	xchgl %r8d, %r13d
	movl $2, %r15d
	movl $0, %ecx
	movl $2, %r14d
	movl $1, %r11d
	jmp .Lbb2674
.Lbb236:
	movq %r9, %rdx
	.loc 1 1630
	movl $64, %r8d
	movl $1, %ecx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb238:
	movq %r14, %rdx
	.loc 1 1625
	movq %rcx, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb240:
	movq %r15, %rsi
	movq %r14, %rcx
	.loc 1 1621
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb242:
	movq %r15, %rsi
	.loc 1 1619
	movl $320, %edx
	movq %rdi, %rbx
	callq myl_qbe_fail_cast
	ud2
.Lbb244:
	xchgq %rbx, %rdi
	.loc 1 1602
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 1602
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2692
.Lbb246:
	xchgq %rbx, %rdi
	.loc 1 1601
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 1601
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2692
.Lbb248:
	xchgl %r14d, %r15d
	movq 128(%rsi), %rax
	movq %rax, -216(%rbp)
	cmpl $0, %r15d
	jnz .Lbb251
	movl %r15d, %r10d
	movl %r12d, %r15d
	jmp .Lbb257
.Lbb251:
	movl %r12d, %r15d
	testl $28, %r14d
	jnz .Lbb255
	.loc 1 1445
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3680(%rbp), %r8d
	movq -216(%rbp), %rax
	movl $0, %r10d
	jmp .Lbb257
.Lbb255:
	.loc 1 1445
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3680(%rbp), %r8d
	movq -216(%rbp), %rax
	movl $0, %r10d
.Lbb257:
	movq $-9223372036854775807, %rcx
	cmpq %rcx, %rax
	jl .Lbb466
	subq $1, %rax
	movq %rax, 128(%rsi)
	movq 120(%rsi), %rax
	movq %rax, -224(%rbp)
	cmpl $0, %r10d
	jz .Lbb264
	testl $28, %r14d
	jnz .Lbb262
	.loc 1 1460
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3680(%rbp), %r8d
	movq -224(%rbp), %rax
	movl $0, %r10d
	jmp .Lbb264
.Lbb262:
	.loc 1 1460
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3680(%rbp), %r8d
	movq -224(%rbp), %rax
	movl $0, %r10d
.Lbb264:
	movq 128(%rsi), %rcx
	movq %rcx, -232(%rbp)
	cmpl $0, %r10d
	jnz .Lbb266
	movl %r10d, -268(%rbp)
	jmp .Lbb271
.Lbb266:
	testl $28, %r14d
	jnz .Lbb269
	.loc 1 1463
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3680(%rbp), %r8d
	movq -232(%rbp), %rcx
	movq -224(%rbp), %rax
	movl $0, -268(%rbp)
	jmp .Lbb271
.Lbb269:
	.loc 1 1463
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3680(%rbp), %r8d
	movq -232(%rbp), %rcx
	movq -224(%rbp), %rax
	movl $0, -268(%rbp)
.Lbb271:
	cmpq $0, %rcx
	jge .Lbb274
	movq (%rax), %r10
	movq $9223372036854775807, %rdx
	cmpq %rdx, %r10
	ja .Lbb464
	movq %rcx, %r9
	addq %r10, %rcx
	movq %r10, %rdx
	xorq %rcx, %rdx
	movq %r9, %r11
	xorq %rcx, %r11
	andq %r11, %rdx
	cmpq $0, %rdx
	jl .Lbb462
.Lbb274:
	movq (%rax), %rdx
	cmpq %rdx, %rcx
	jae .Lbb461
	movq 32(%rax), %rax
	imulq $16, %rcx, %rcx
	movq 0(%rax, %rcx, 1), %rdx
	movq %rdx, -5744(%rbp)
	movq 8(%rax, %rcx, 1), %rax
	movq %rax, -5736(%rbp)
	movq -6112(%rbp), %rdx
	movq %rdx, -240(%rbp)
	cmpl $0, %r8d
	jnz .Lbb277
	movl %r8d, -316(%rbp)
	jmp .Lbb282
.Lbb277:
	testl $28, %r15d
	jnz .Lbb280
	.loc 1 1479
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -240(%rbp), %rdx
	movl $0, -316(%rbp)
	jmp .Lbb282
.Lbb280:
	.loc 1 1479
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -240(%rbp), %rdx
	movl $0, -316(%rbp)
.Lbb282:
	.loc 1 1480
	movq %rsi, %r13
	movq %rdi, %r12
	callq myl_f_d68035f037267c89f90770d7a0cb039e1c6cb185811c1f08f091959f77a86644
	movq %r13, %rsi
	movq %r12, %rdi
	movl -316(%rbp), %r8d
	movl -268(%rbp), %r10d
	movq -3784(%rbp), %rcx
	movq -3824(%rbp), %rdx
	cmpl $0, %r10d
	jz .Lbb288
	testl $28, %r14d
	jnz .Lbb286
	.loc 1 1480
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movl -316(%rbp), %r8d
	movq -3784(%rbp), %rcx
	movq -3824(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb288
.Lbb286:
	.loc 1 1480
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movl -316(%rbp), %r8d
	movq -3784(%rbp), %rcx
	movq -3824(%rbp), %rdx
	movl $0, %r10d
.Lbb288:
	movq 144(%rsi), %rax
	movq %rax, -248(%rbp)
	cmpl $0, %r10d
	jnz .Lbb290
	movl %r14d, %r9d
	jmp .Lbb295
.Lbb290:
	testl $28, %r14d
	jnz .Lbb293
	.loc 1 1483
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movl -316(%rbp), %r8d
	movq -3784(%rbp), %rcx
	movq -3824(%rbp), %rdx
	movq -248(%rbp), %rax
	movl %r14d, %r9d
	movl $0, %r10d
	jmp .Lbb295
.Lbb293:
	.loc 1 1483
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -316(%rbp), %r8d
	movq -3784(%rbp), %rcx
	movq -3824(%rbp), %rdx
	movq -248(%rbp), %rax
	movl $0, %r10d
.Lbb295:
	movl %r9d, %r14d
	movq $-9223372036854775807, %r9
	cmpq %r9, %rax
	jl .Lbb459
	subq $1, %rax
	movq %rax, -256(%rbp)
	movq %rax, 144(%rsi)
	cmpl $0, %r10d
	jz .Lbb302
	testl $28, %r14d
	jnz .Lbb300
	.loc 1 1498
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -256(%rbp), %rax
	movl -316(%rbp), %r8d
	movq -3784(%rbp), %rcx
	movq -3824(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb302
.Lbb300:
	.loc 1 1498
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -256(%rbp), %rax
	movl -316(%rbp), %r8d
	movq -3784(%rbp), %rcx
	movq -3824(%rbp), %rdx
	movl $0, %r10d
.Lbb302:
	cmpq $0, %rax
	jz .Lbb444
	movq -6112(%rbp), %rax
	movq %rax, -264(%rbp)
	cmpl $0, %r10d
	jz .Lbb309
	testl $28, %r14d
	jnz .Lbb307
	.loc 1 1520
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movl -316(%rbp), %r8d
	movq -3784(%rbp), %rcx
	movq -3824(%rbp), %rdx
	movq -264(%rbp), %rax
	movl $0, %r10d
	jmp .Lbb309
.Lbb307:
	.loc 1 1520
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movl -316(%rbp), %r8d
	movq -3784(%rbp), %rcx
	movq -3824(%rbp), %rdx
	movq -264(%rbp), %rax
	movl $0, %r10d
.Lbb309:
	movq %rax, 128(%rsi)
	movq -5744(%rbp), %rax
	movq %rax, -6072(%rbp)
	movq -5736(%rbp), %rax
	movq %rax, -6064(%rbp)
	cmpl $0, %r10d
	jnz .Lbb311
	movl %r14d, %r9d
	jmp .Lbb316
.Lbb311:
	testl $28, %r14d
	jnz .Lbb314
	.loc 1 1535
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movl -316(%rbp), %r8d
	movq -3784(%rbp), %rcx
	movq -3824(%rbp), %rdx
	movl %r14d, %r9d
	movl $0, %r10d
	jmp .Lbb316
.Lbb314:
	.loc 1 1535
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -316(%rbp), %r8d
	movq -3784(%rbp), %rcx
	movq -3824(%rbp), %rdx
	movl $0, %r10d
.Lbb316:
	cmpl $0, %r10d
	jz .Lbb336
	testl $28, %r9d
	jnz .Lbb327
	movq -7016(%rbp), %r10
	cmpq $0, %r10
	jz .Lbb326
	movq -16(%r10), %rax
	movq $4611686018427387906, %r11
	andq %r11, %rax
	cmpq $0, %rax
	jnz .Lbb325
	movq -32(%r10), %rax
	subq $1, %rax
	jnz .Lbb324
	movl %r9d, %r14d
	movq -24(%r10), %r9
	cmpq $0, %r9
	jnz .Lbb323
	.loc 1 1536
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -316(%rbp), %r8d
	movq -3784(%rbp), %rcx
	movq -3824(%rbp), %rdx
	jmp .Lbb326
.Lbb323:
	movl %r14d, %r9d
.Lbb324:
	movq %rax, -32(%r10)
.Lbb325:
	movq $0, -7016(%rbp)
.Lbb326:
	movl $0, %r10d
	jmp .Lbb336
.Lbb327:
	movq -7016(%rbp), %r10
	cmpq $0, %r10
	jz .Lbb335
	movq -16(%r10), %rax
	movq $4611686018427387906, %r11
	andq %r11, %rax
	cmpq $0, %rax
	jnz .Lbb334
	movq -24(%r10), %rax
	subq $1, %rax
	jnz .Lbb333
	movl %r9d, %r14d
	movq -32(%r10), %r9
	cmpq $0, %r9
	jnz .Lbb332
	.loc 1 1536
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -316(%rbp), %r8d
	movq -3784(%rbp), %rcx
	movq -3824(%rbp), %rdx
	jmp .Lbb335
.Lbb332:
	movl %r14d, %r9d
.Lbb333:
	movq %rax, -24(%r10)
.Lbb334:
	movq $0, -7016(%rbp)
.Lbb335:
	movl $0, %r10d
.Lbb336:
	movl %r10d, -272(%rbp)
	movq 120(%rsi), %rax
	cmpq $0, %rax
	jnz .Lbb338
	movl %r9d, %r14d
	jmp .Lbb341
.Lbb338:
	movl %r9d, %r14d
	movq -16(%rax), %r9
	movq $6917529027641081858, %r11
	andq %r11, %r9
	cmpq $0, %r9
	jnz .Lbb340
	movq -32(%rax), %rax
	cmpq $2, %rax
	jb .Lbb341
.Lbb340:
	.loc 1 1536
	movl $0, %ecx
	movq %rsi, %r13
	movq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	callq myl_qbe_rc_unique_field
	movq %r13, %rsi
	movq %r12, %rdi
	movl -272(%rbp), %r10d
	movl -316(%rbp), %r8d
	movq -3784(%rbp), %rcx
	cmpl $0, %eax
	jz .Lbb2692
.Lbb341:
	movq 120(%rsi), %rdx
	movq %rdx, -280(%rbp)
	movq 128(%rsi), %rax
	movq %rax, -288(%rbp)
	cmpl $0, %r10d
	jnz .Lbb343
	movl %r14d, %r9d
	jmp .Lbb348
.Lbb343:
	testl $28, %r14d
	jnz .Lbb346
	.loc 1 1538
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movl -316(%rbp), %r8d
	movq -3784(%rbp), %rcx
	movq -288(%rbp), %rax
	movq -280(%rbp), %rdx
	movl %r14d, %r9d
	movl $0, %r10d
	jmp .Lbb348
.Lbb346:
	.loc 1 1538
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -316(%rbp), %r8d
	movq -3784(%rbp), %rcx
	movq -288(%rbp), %rax
	movq -280(%rbp), %rdx
	movl $0, %r10d
.Lbb348:
	cmpq $0, %rax
	jge .Lbb351
	movq (%rdx), %r12
	movq $9223372036854775807, %r11
	cmpq %r11, %r12
	ja .Lbb442
	movq %rax, %r11
	addq %r12, %rax
	movq %r12, %r13
	xorq %rax, %r13
	movq %r11, %r14
	xorq %rax, %r14
	andq %r14, %r13
	cmpq $0, %r13
	jl .Lbb440
.Lbb351:
	movq -6072(%rbp), %r11
	movq %r11, -4328(%rbp)
	movq -6064(%rbp), %r11
	movq %r11, -4320(%rbp)
	movq (%rdx), %r11
	cmpq %r11, %rax
	jae .Lbb438
	movq 32(%rdx), %rdx
	movl %r9d, %r13d
	imulq $16, %rax, %r9
	movq -4328(%rbp), %rax
	movq %rax, 0(%rdx, %r9, 1)
	movq -4320(%rbp), %rax
	movq %rax, 8(%rdx, %r9, 1)
	movq 128(%rsi), %rax
	movq %rax, -296(%rbp)
	cmpl $0, %r10d
	jnz .Lbb354
	movl %r10d, -320(%rbp)
	jmp .Lbb359
.Lbb354:
	testl $28, %r13d
	jnz .Lbb357
	.loc 1 1554
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r14, %rsi
	movq %r12, %rdi
	movl -316(%rbp), %r8d
	movq -3784(%rbp), %rcx
	movq -296(%rbp), %rax
	movl $0, -320(%rbp)
	jmp .Lbb359
.Lbb357:
	.loc 1 1554
	movq %rsi, %r14
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r14, %rsi
	movq %r12, %rdi
	movl -316(%rbp), %r8d
	movq -3784(%rbp), %rcx
	movq -296(%rbp), %rax
	movl $0, -320(%rbp)
.Lbb359:
	movq $9223372036854775806, %rdx
	cmpq %rdx, %rax
	jg .Lbb436
	addq $1, %rax
	movq %rax, 128(%rsi)
	movq 136(%rsi), %rax
	movq %rax, -312(%rbp)
	cmpl $0, %r8d
	jz .Lbb366
	testl $28, %r15d
	jnz .Lbb364
	.loc 1 1570
	movq %rsi, %r14
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r14, %rsi
	movq %r12, %rdi
	movq -3784(%rbp), %rcx
	movq -312(%rbp), %rax
	movl $0, %r8d
	jmp .Lbb366
.Lbb364:
	.loc 1 1570
	movq %rsi, %r14
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r14, %rsi
	movq %r12, %rdi
	movq -3784(%rbp), %rcx
	movq -312(%rbp), %rax
	movl $0, %r8d
.Lbb366:
	movq 144(%rsi), %rdx
	movq %rdx, -304(%rbp)
	cmpl $0, %r8d
	jnz .Lbb368
	movl %r8d, -404(%rbp)
	jmp .Lbb373
.Lbb368:
	testl $28, %r15d
	jnz .Lbb371
	.loc 1 1573
	movq %rsi, %r14
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r14, %rsi
	movq %r12, %rdi
	movq -3784(%rbp), %rcx
	movq -304(%rbp), %rdx
	movq -312(%rbp), %rax
	movl $0, -404(%rbp)
	jmp .Lbb373
.Lbb371:
	.loc 1 1573
	movq %rsi, %r14
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r14, %rsi
	movq %r12, %rdi
	movq -3784(%rbp), %rcx
	movq -304(%rbp), %rdx
	movq -312(%rbp), %rax
	movl $0, -404(%rbp)
.Lbb373:
	movq $-9223372036854775807, %r8
	cmpq %r8, %rdx
	jl .Lbb435
	movq %rsi, %r14
	movq %rdx, %rsi
	subq $1, %rsi
	cmpq $0, %rsi
	jge .Lbb377
	movq (%rax), %r10
	movq $9223372036854775807, %rdx
	cmpq %rdx, %r10
	ja .Lbb433
	movq %rsi, %r9
	addq %r10, %rsi
	movq %r10, %rdx
	xorq %rsi, %rdx
	movq %r9, %r8
	xorq %rsi, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jl .Lbb431
.Lbb377:
	movq (%rax), %rdx
	cmpq %rdx, %rsi
	jae .Lbb430
	movq 32(%rax), %rax
	imulq $24, %rsi, %rdx
	movq 0(%rax, %rdx, 1), %rsi
	movq %rsi, 0(%rcx)
	movq 8(%rax, %rdx, 1), %rsi
	movq %rsi, 8(%rcx)
	movq 16(%rax, %rdx, 1), %rax
	movq %rax, 16(%rcx)
	.loc 1 1588
	movq %r14, %rdx
	movq %rdi, %rsi
	movq %rdi, %r12
	leaq -7080(%rbp), %rdi
	callq myl_f_bf0431d3d9e553eacefcb10ebb00251bb8b43354cc87fd12c99ceb5644f705d6
	movl %r13d, %r9d
	movq %r12, %rdi
	movq %rax, %r10
	movl -3664(%rbp), %r8d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r12d, %r13d
	movl -3676(%rbp), %r12d
	movq -3656(%rbp), %rax
	movq -3816(%rbp), %r11
	movq -3648(%rbp), %rdx
	movq 0(%r10), %rsi
	movq %rsi, -6392(%rbp)
	movq 8(%r10), %rsi
	movq %rsi, -6384(%rbp)
	movq 16(%r10), %rsi
	movq %rsi, -6376(%rbp)
	movq 24(%r10), %rsi
	movq %rsi, -6368(%rbp)
	movq -3776(%rbp), %rsi
	movq 32(%r10), %r10
	movq %r10, -6360(%rbp)
	movq -3768(%rbp), %r10
	cmpl $0, -320(%rbp)
	jnz .Lbb380
	movl %r8d, %r9d
	jmp .Lbb384
.Lbb380:
	testl $28, %r9d
	jnz .Lbb383
	.loc 1 1588
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rdi
	movq -3768(%rbp), %rsi
	movq %rsi, %r9
	movq -3776(%rbp), %rsi
	movl -3664(%rbp), %r13d
	movl %r13d, %r8d
	movl -3668(%rbp), %r13d
	movl -3672(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -3816(%rbp), %r11
	movq -3648(%rbp), %rdx
	movq %r9, %r10
	movl %r8d, %r9d
	jmp .Lbb384
.Lbb383:
	.loc 1 1588
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r13, %rdi
	movq -3768(%rbp), %rsi
	movq %rsi, %r10
	movq -3776(%rbp), %rsi
	movl -3664(%rbp), %r13d
	movl %r13d, %r9d
	movl -3668(%rbp), %r13d
	movl -3672(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -3816(%rbp), %r11
	movq -3648(%rbp), %rdx
.Lbb384:
	movq -6392(%rbp), %r8
	movq %r8, -7016(%rbp)
	movq -6384(%rbp), %r8
	movq %r8, -7008(%rbp)
	movq -6376(%rbp), %r8
	movq %r8, -7000(%rbp)
	movq -6368(%rbp), %r8
	movq %r8, -6992(%rbp)
	movq -6360(%rbp), %r8
	movq %r8, -6984(%rbp)
	movq -7016(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb386
	movq -16(%r8), %r8
	movq %r8, -328(%rbp)
	movq -3768(%rbp), %r10
	movq $5764607523034234881, %r8
	movq %r8, -336(%rbp)
	movq -328(%rbp), %r8
	andq -336(%rbp), %r8
	cmpq $0, %r8
	jnz .Lbb393
.Lbb386:
	movq -7008(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb388
	movq -16(%r8), %r8
	movq %r8, -344(%rbp)
	movq -3768(%rbp), %r10
	movq $5764607523034234881, %r8
	movq %r8, -352(%rbp)
	movq -344(%rbp), %r8
	andq -352(%rbp), %r8
	cmpq $0, %r8
	jnz .Lbb393
.Lbb388:
	movq -7000(%rbp), %r8
	movq %r8, -360(%rbp)
	movl -404(%rbp), %r8d
	cmpq $0, -360(%rbp)
	jz .Lbb391
	movq -360(%rbp), %r8
	movq -16(%r8), %r8
	movq %r8, -376(%rbp)
	movq -3768(%rbp), %r10
	movq $5764607523034234881, %r8
	movq %r8, -368(%rbp)
	movq -376(%rbp), %r8
	andq -368(%rbp), %r8
	movq %r8, -384(%rbp)
	movl -404(%rbp), %r8d
	cmpq $0, -384(%rbp)
	jnz .Lbb393
.Lbb391:
	movq -7016(%rbp), %r11
	movq %r11, -6392(%rbp)
	movq -7008(%rbp), %r11
	movq %r11, -6384(%rbp)
	movq -7000(%rbp), %r11
	movq %r11, -6376(%rbp)
	movq -6992(%rbp), %r11
	movq %r11, -6368(%rbp)
	movq -6984(%rbp), %r11
	movq %r11, -6360(%rbp)
	movq $0, -7016(%rbp)
	movq $0, -7008(%rbp)
	movq $0, -7000(%rbp)
	movq $0, -6992(%rbp)
	movq $0, -6984(%rbp)
	movq %r10, %r11
	jmp .Lbb394
.Lbb393:
	movq %r11, %rcx
	.loc 1 1589
	movq %rcx, %r11
	leaq -7016(%rbp), %rdx
	leaq -6392(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_take
	movq %r13, %rdi
	movl %eax, %r10d
	movq -3768(%rbp), %rsi
	movq %rsi, %r11
	movq -3776(%rbp), %rsi
	movl -404(%rbp), %r8d
	movl -3664(%rbp), %r13d
	movl %r13d, %r9d
	movl -3668(%rbp), %r13d
	movl -3672(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	cmpl $0, %r10d
	jz .Lbb428
.Lbb394:
	cmpl $0, %r9d
	jnz .Lbb396
	movl %r15d, %r9d
	movq %r14, %rsi
	jmp .Lbb426
.Lbb396:
	testl $28, %r13d
	jnz .Lbb424
	movq -6144(%rbp), %r10
	cmpq $0, %r10
	jz .Lbb404
	movq -16(%r10), %r9
	movq $4611686018427387906, %r13
	andq %r13, %r9
	cmpq $0, %r9
	jnz .Lbb403
	movq -32(%r10), %r9
	subq $1, %r9
	jnz .Lbb402
	movq -24(%r10), %r13
	cmpq $0, %r13
	jnz .Lbb402
	.loc 1 1589
	leaq -6144(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a_rcg_drop
	movq %r13, %rdi
	movq -3768(%rbp), %rsi
	movq %rsi, %r11
	movq -3776(%rbp), %rsi
	movl -404(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	jmp .Lbb404
.Lbb402:
	movq %r9, -32(%r10)
.Lbb403:
	movq $0, -6144(%rbp)
.Lbb404:
	movq -6136(%rbp), %r10
	cmpq $0, %r10
	jnz .Lbb406
	movq %r11, %rsi
	jmp .Lbb413
.Lbb406:
	movq -16(%r10), %r9
	movq $4611686018427387906, %r13
	andq %r13, %r9
	cmpq $0, %r9
	jnz .Lbb411
	movq -32(%r10), %r9
	subq $1, %r9
	jnz .Lbb410
	movq -24(%r10), %r13
	cmpq $0, %r13
	jnz .Lbb410
	.loc 1 1589
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %r14, %rsi
	movq %r13, %rdi
	movq %rsi, %r14
	movq -3768(%rbp), %rsi
	movl -404(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	jmp .Lbb413
.Lbb410:
	movq %r11, %rsi
	movq %r9, -32(%r10)
	jmp .Lbb412
.Lbb411:
	movq %r11, %rsi
.Lbb412:
	movq $0, -6136(%rbp)
.Lbb413:
	movq -6128(%rbp), %r10
	cmpq $0, %r10
	jnz .Lbb415
	movq %r14, %rsi
	jmp .Lbb422
.Lbb415:
	movq -16(%r10), %r9
	movq $4611686018427387906, %r11
	andq %r11, %r9
	cmpq $0, %r9
	jnz .Lbb420
	movq -32(%r10), %r9
	subq $1, %r9
	jnz .Lbb419
	movq -24(%r10), %r11
	cmpq $0, %r11
	jnz .Lbb419
	.loc 1 1589
	movq %rsi, %r10
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %r14, %rsi
	movq %r13, %rdi
	movl -404(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	jmp .Lbb422
.Lbb419:
	movq %r14, %rsi
	movq %r9, -32(%r10)
	jmp .Lbb421
.Lbb420:
	movq %r14, %rsi
.Lbb421:
	movq $0, -6128(%rbp)
.Lbb422:
	movq $0, -6144(%rbp)
	movq $0, -6136(%rbp)
	movq $0, -6128(%rbp)
	movq $0, -6120(%rbp)
	movq $0, -6112(%rbp)
	movl %r15d, %r9d
	jmp .Lbb426
.Lbb424:
	movq %r14, %rsi
	.loc 1 1589
	movq %rsi, %r14
	leaq -6144(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movl %r15d, %r9d
	movq %r14, %rsi
	movq %r13, %rdi
	movl -404(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
.Lbb426:
	movq -6392(%rbp), %r10
	movq %r10, -6144(%rbp)
	movq -6384(%rbp), %r10
	movq %r10, -6136(%rbp)
	movq -6376(%rbp), %r10
	movq %r10, -6128(%rbp)
	movq -6368(%rbp), %r10
	movq %r10, -6120(%rbp)
	movq -6360(%rbp), %r10
	movq %r10, -6112(%rbp)
	movl $1, %r13d
	movl $0, %r10d
	movl %r9d, %r15d
	movl $2, %r9d
	movl %r12d, %r14d
	movl $2, %r12d
	movl $1, %r11d
	jmp .Lbb2674
.Lbb428:
	xchgq %rbx, %rdi
	.loc 1 1589
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 1589
	callq myl_qbe_rc_status
	jmp .Lbb2692
.Lbb430:
	.loc 1 1587
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb431:
	movq %r9, %rcx
	movq %r10, %rsi
	.loc 1 1584
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb433:
	movq %r10, %rsi
	.loc 1 1582
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb435:
	.loc 1 1575
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb436:
	movq %rax, %rdx
	.loc 1 1556
	movl $64, %r8d
	movl $1, %ecx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb438:
	movq %r11, %rdx
	.loc 1 1551
	movq %rax, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb440:
	movq %r12, %rsi
	movq %r11, %rcx
	.loc 1 1547
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb442:
	movq %r12, %rsi
	.loc 1 1545
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb444:
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl %r14d, %r15d
	movq 128(%rsi), %rdx
	movq %rdx, -392(%rbp)
	cmpl $0, %r10d
	jz .Lbb449
	testl $28, %r15d
	jnz .Lbb448
	.loc 1 1503
	movq %rsi, %r15
	leaq -7016(%rbp), %rsi
	movq %rdi, %r14
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r15, %rsi
	movq %r14, %rdi
	movq -392(%rbp), %rdx
	jmp .Lbb449
.Lbb448:
	.loc 1 1503
	movq %rsi, %r15
	leaq -7016(%rbp), %rsi
	movq %rdi, %r14
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r15, %rsi
	movq %r14, %rdi
	movq -392(%rbp), %rdx
.Lbb449:
	movq $-9223372036854775807, %rax
	cmpq %rax, %rdx
	jl .Lbb458
	movq %rdx, %rax
	subq $1, %rax
	movq %rax, 128(%rsi)
	movl $0, -4336(%rbp)
	movl $0, -4336(%rbp)
	movl -6160(%rbp), %eax
	cmpl $0, %eax
	jnz .Lbb452
	movl %r12d, %r9d
	movq %rbx, %rdi
	jmp .Lbb453
.Lbb452:
	leaq -6184(%rbp), %rax
	movq %rax, -6152(%rbp)
	.loc 1 1518
	movl $1, %edx
	leaq -6152(%rbp), %rsi
	callq myl_qbe_rc_scopes_close
	movl %r12d, %r9d
	movq %rbx, %rdi
.Lbb453:
	cmpl $0, %r13d
	jz .Lbb457
	testl $28, %r9d
	jnz .Lbb456
	.loc 1 1518
	leaq -6144(%rbp), %rsi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	jmp .Lbb457
.Lbb456:
	.loc 1 1518
	leaq -6144(%rbp), %rsi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
.Lbb457:
	movq -4336(%rbp), %rax
	jmp .Lbb2693
.Lbb458:
	.loc 1 1505
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb459:
	movq %rax, %rdx
	.loc 1 1485
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb461:
	.loc 1 1475
	movq %rcx, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb462:
	movq %r10, %rsi
	movq %r9, %rcx
	.loc 1 1472
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb464:
	movq %r10, %rsi
	.loc 1 1470
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb466:
	movq %rax, %rdx
	.loc 1 1447
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb468:
	xchgl %r14d, %r15d
	movl %r12d, %r9d
	movq 0(%rsi), %rax
	movq %rax, -4544(%rbp)
	movq 8(%rsi), %rax
	movq %rax, -4536(%rbp)
	movq 16(%rsi), %rax
	movq %rax, -4528(%rbp)
	movq 24(%rsi), %rax
	movq %rax, -4520(%rbp)
	movq 32(%rsi), %rax
	movq %rax, -4512(%rbp)
	movq 40(%rsi), %rax
	movq %rax, -4504(%rbp)
	movq 48(%rsi), %rax
	movq %rax, -4496(%rbp)
	movq 56(%rsi), %rax
	movq %rax, -4488(%rbp)
	movq 64(%rsi), %rax
	movq %rax, -4480(%rbp)
	movq 72(%rsi), %rax
	movq %rax, -4472(%rbp)
	movq 80(%rsi), %rax
	movq %rax, -4464(%rbp)
	movq 88(%rsi), %rax
	movq %rax, -4456(%rbp)
	movq 96(%rsi), %rax
	movq %rax, -4448(%rbp)
	movq 104(%rsi), %rax
	movq %rax, -4440(%rbp)
	movq 112(%rsi), %rax
	movq %rax, -4432(%rbp)
	movq 120(%rsi), %rax
	movq %rax, -4424(%rbp)
	movq 128(%rsi), %rax
	movq %rax, -4416(%rbp)
	movq 136(%rsi), %rax
	movq %rax, -4408(%rbp)
	movq 144(%rsi), %rax
	movq %rax, -4400(%rbp)
	movq 152(%rsi), %rax
	movq %rax, -4392(%rbp)
	movq 160(%rsi), %rax
	movq %rax, -4384(%rbp)
	movq 168(%rsi), %rax
	movq %rax, -4376(%rbp)
	movq 176(%rsi), %rax
	movq %rax, -4368(%rbp)
	movq 184(%rsi), %rax
	movq %rax, -4360(%rbp)
	movq 192(%rsi), %rax
	movq %rax, -4352(%rbp)
	movq 200(%rsi), %rax
	movq %rax, -4344(%rbp)
	movq -4416(%rbp), %rax
	movq %rax, -400(%rbp)
	cmpl $0, %r8d
	jnz .Lbb471
	movl %r8d, -408(%rbp)
	jmp .Lbb476
.Lbb471:
	testl $28, %r9d
	jnz .Lbb474
	.loc 1 1419
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -400(%rbp), %rax
	movl $0, -408(%rbp)
	jmp .Lbb476
.Lbb474:
	.loc 1 1419
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -400(%rbp), %rax
	movl $0, -408(%rbp)
.Lbb476:
	movq $-9223372036854775807, %rcx
	cmpq %rcx, %rax
	jl .Lbb497
	.loc 1 1422
	movq %rax, %rdx
	subq $1, %rdx
	movq %rsi, %r13
	movq %rdi, %r12
	callq myl_f_d68035f037267c89f90770d7a0cb039e1c6cb185811c1f08f091959f77a86644
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -408(%rbp), %r8d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl %r9d, %r14d
	movl -3588(%rbp), %r9d
	movl -3672(%rbp), %ecx
	movl %r12d, %r10d
	movl -3676(%rbp), %r12d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	cmpl $0, %r15d
	jnz .Lbb479
	xchgl %r9d, %r15d
	xchgl %r10d, %r9d
	jmp .Lbb485
.Lbb479:
	movl %r9d, %r15d
	testl $28, %r14d
	jnz .Lbb483
	.loc 1 1422
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movl -408(%rbp), %r8d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r12d, %r9d
	movl -3676(%rbp), %r12d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb485
.Lbb483:
	.loc 1 1422
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movl -408(%rbp), %r8d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r12d, %r9d
	movl -3676(%rbp), %r12d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb485:
	movq 128(%rsi), %r11
	movq %r11, -416(%rbp)
	cmpl $0, %r10d
	jnz .Lbb487
	xchgl %r9d, %r15d
	jmp .Lbb492
.Lbb487:
	testl $28, %r14d
	jnz .Lbb490
	.loc 1 1425
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movl -408(%rbp), %r8d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r12d, %r9d
	movl -3676(%rbp), %r12d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	xchgl %r9d, %r15d
	movl $0, %r10d
	jmp .Lbb492
.Lbb490:
	.loc 1 1425
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r15d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -408(%rbp), %r8d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r12d, %r15d
	movl -3676(%rbp), %r12d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb492:
	movq $-9223372036854775807, %r11
	movq %r11, -424(%rbp)
	movq -416(%rbp), %r11
	cmpq -424(%rbp), %r11
	jl .Lbb495
	subq $1, %r11
	movq %r11, 128(%rsi)
	xchgl %r15d, %r12d
	xchgl %r9d, %r15d
	xchgl %r14d, %r9d
	movl $1, %r11d
	jmp .Lbb2674
.Lbb495:
	movq %r11, %rdx
	.loc 1 1427
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb497:
	movq %rax, %rdx
	.loc 1 1421
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	movq %rdi, %rbx
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb499:
	xchgl %r14d, %r15d
	.loc 1 1410
	leaq -6144(%rbp), %rdx
	movq %rsi, %r13
	movq %rdi, %r12
	callq myl_f_db6d20b17ece57e87a81f21cd245da938857f9dcc8445bc9043b7bd2bf9bdbe8
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl %r9d, %r14d
	movl -3588(%rbp), %r9d
	movl -3672(%rbp), %ecx
	movl %r12d, %r10d
	movl -3676(%rbp), %r12d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	cmpl $0, %r15d
	jnz .Lbb502
	xchgl %r9d, %r15d
	xchgl %r10d, %r9d
	jmp .Lbb508
.Lbb502:
	movl %r9d, %r15d
	testl $28, %r14d
	jnz .Lbb506
	.loc 1 1410
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r12d, %r9d
	movl -3676(%rbp), %r12d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb508
.Lbb506:
	.loc 1 1410
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r12d, %r9d
	movl -3676(%rbp), %r12d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb508:
	movl %r10d, -428(%rbp)
	cmpl $0, %r8d
	jnz .Lbb510
	xchgl %r15d, %r12d
	jmp .Lbb515
.Lbb510:
	testl $28, %r15d
	jnz .Lbb513
	.loc 1 1410
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movl -428(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r12d, %r9d
	movl -3676(%rbp), %r12d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	xchgl %r15d, %r12d
	movl $0, %r8d
	jmp .Lbb515
.Lbb513:
	.loc 1 1410
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -428(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl %r9d, %r14d
	movl -3668(%rbp), %r9d
	movl -3672(%rbp), %ecx
	movl %r15d, %r12d
	movl -3676(%rbp), %r15d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r8d
.Lbb515:
	xchgl %r12d, %r15d
	xchgl %r9d, %r12d
	xchgl %r14d, %r9d
	movl $1, %r11d
	jmp .Lbb2674
.Lbb516:
	xchgl %r14d, %r15d
	.loc 1 1297
	movq %rsi, %r13
	leaq -6144(%rbp), %rsi
	movq %rdi, %r12
	callq myl_f_94484f74f9fdfe749fe3bbd5703ff3b6b2a0ee43d3569a1125fbe02c5095250d
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, -496(%rbp)
	movl -3588(%rbp), %r12d
	cmpl $0, %r15d
	jnz .Lbb519
	movl %r15d, -432(%rbp)
	movl %r12d, %r15d
	jmp .Lbb525
.Lbb519:
	movl %r12d, %r15d
	testl $28, %r14d
	jnz .Lbb523
	.loc 1 1297
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movl $0, -432(%rbp)
	jmp .Lbb525
.Lbb523:
	.loc 1 1297
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movl $0, -432(%rbp)
.Lbb525:
	.loc 1 1300
	movq %rsi, %r13
	leaq -6144(%rbp), %rsi
	movq %rdi, %r12
	callq myl_f_fa0a495025828a635f8203a4c546663c235c2574b972f1294569bb6fadb2fcc2
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, -488(%rbp)
	movl -432(%rbp), %r10d
	movq -3736(%rbp), %rdx
	movq -3704(%rbp), %r11
	cmpl $0, %r10d
	jz .Lbb531
	testl $28, %r14d
	jnz .Lbb529
	.loc 1 1300
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3736(%rbp), %rdx
	movq -3704(%rbp), %r11
	movl $0, %r10d
	jmp .Lbb531
.Lbb529:
	.loc 1 1300
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3736(%rbp), %rdx
	movq -3704(%rbp), %r11
	movl $0, %r10d
.Lbb531:
	movq -6120(%rbp), %r8
	movq %r8, -440(%rbp)
	cmpl $0, %r10d
	jz .Lbb537
	testl $28, %r14d
	jnz .Lbb535
	.loc 1 1303
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3736(%rbp), %rdx
	movq -440(%rbp), %r8
	movq -3704(%rbp), %r11
	movl $0, %r10d
	jmp .Lbb537
.Lbb535:
	.loc 1 1303
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3736(%rbp), %rdx
	movq -440(%rbp), %r8
	movq -3704(%rbp), %r11
	movl $0, %r10d
.Lbb537:
	cmpl $0, %r10d
	jnz .Lbb539
	movl %r14d, %r9d
	jmp .Lbb544
.Lbb539:
	testl $28, %r14d
	jnz .Lbb542
	.loc 1 1306
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3736(%rbp), %rdx
	movq -440(%rbp), %r8
	movq -3704(%rbp), %r11
	movl %r14d, %r9d
	movl $0, %r10d
	jmp .Lbb544
.Lbb542:
	.loc 1 1306
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3736(%rbp), %rdx
	movq -440(%rbp), %r8
	movq -3704(%rbp), %r11
	movl $0, %r10d
.Lbb544:
	cmpl $0, %r10d
	jz .Lbb564
	testl $28, %r9d
	jnz .Lbb555
	movq -7016(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb554
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r10
	andq %r10, %rax
	cmpq $0, %rax
	jnz .Lbb553
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb552
	movl %r9d, %r14d
	movq -24(%rcx), %r9
	cmpq $0, %r9
	jnz .Lbb551
	.loc 1 1307
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3736(%rbp), %rdx
	movq -440(%rbp), %r8
	movq -3704(%rbp), %r11
	jmp .Lbb554
.Lbb551:
	movl %r14d, %r9d
.Lbb552:
	movq %rax, -32(%rcx)
.Lbb553:
	movq $0, -7016(%rbp)
.Lbb554:
	movl $0, %r10d
	jmp .Lbb564
.Lbb555:
	movq -7016(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb563
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r10
	andq %r10, %rax
	cmpq $0, %rax
	jnz .Lbb562
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb561
	movl %r9d, %r14d
	movq -32(%rcx), %r9
	cmpq $0, %r9
	jnz .Lbb560
	.loc 1 1307
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3736(%rbp), %rdx
	movq -440(%rbp), %r8
	movq -3704(%rbp), %r11
	jmp .Lbb563
.Lbb560:
	movl %r14d, %r9d
.Lbb561:
	movq %rax, -24(%rcx)
.Lbb562:
	movq $0, -7016(%rbp)
.Lbb563:
	movl $0, %r10d
.Lbb564:
	movl %r10d, -500(%rbp)
	movq 136(%rsi), %rax
	cmpq $0, %rax
	jz .Lbb569
	movq -16(%rax), %rcx
	movl %r9d, %r14d
	movq $6917529027641081858, %r9
	andq %r9, %rcx
	cmpq $0, %rcx
	jnz .Lbb568
	movq -32(%rax), %rax
	cmpq $2, %rax
	jae .Lbb568
	movl %r14d, %r9d
	jmp .Lbb569
.Lbb568:
	.loc 1 1307
	movl $0, %ecx
	movq %r11, %rdx
	movq %rsi, %r13
	movq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	callq myl_qbe_rc_unique_field
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -500(%rbp), %r10d
	movq -3736(%rbp), %rdx
	movq -440(%rbp), %r8
	cmpl $0, %eax
	jz .Lbb2692
.Lbb569:
	movq 136(%rsi), %rax
	movq %rax, -456(%rbp)
	movl %r9d, %r14d
	movq 144(%rsi), %r9
	movq %r9, -448(%rbp)
	cmpl $0, %r10d
	jz .Lbb575
	testl $28, %r14d
	jnz .Lbb573
	.loc 1 1309
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3736(%rbp), %rdx
	movl %r9d, %r14d
	movq -448(%rbp), %r9
	movq -456(%rbp), %rax
	movq -440(%rbp), %r8
	movl $0, %r10d
	jmp .Lbb575
.Lbb573:
	.loc 1 1309
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3736(%rbp), %rdx
	movl %r9d, %r14d
	movq -448(%rbp), %r9
	movq -456(%rbp), %rax
	movq -440(%rbp), %r8
	movl $0, %r10d
.Lbb575:
	movq $-9223372036854775807, %rcx
	cmpq %rcx, %r9
	jl .Lbb715
	subq $1, %r9
	cmpq $0, %r9
	jge .Lbb579
	movq (%rax), %r11
	movq $9223372036854775807, %rcx
	cmpq %rcx, %r11
	ja .Lbb713
	movq %r9, %rcx
	addq %r11, %r9
	movq %r11, %r12
	xorq %r9, %r12
	movq %rcx, %r13
	xorq %r9, %r13
	andq %r13, %r12
	cmpq $0, %r12
	jl .Lbb711
.Lbb579:
	movq (%rax), %rcx
	cmpq %rcx, %r9
	jae .Lbb709
	movq 32(%rax), %r11
	imulq $24, %r9, %rcx
	movq 0(%r11, %rcx, 1), %r12
	movq %r12, -5768(%rbp)
	movq 8(%r11, %rcx, 1), %r12
	movq %r12, -5760(%rbp)
	movq 16(%r11, %rcx, 1), %r11
	movq %r11, -5752(%rbp)
	movq (%rax), %r11
	cmpq %r11, %r9
	jae .Lbb707
	movq 32(%rax), %r11
	movq 0(%rcx, %r11, 1), %r12
	movq %r12, -5768(%rbp)
	movq 8(%rcx, %r11, 1), %r12
	movq %r12, -5760(%rbp)
	movq 16(%rcx, %r11, 1), %r11
	movq %r11, -5752(%rbp)
	movq -5768(%rbp), %r11
	movq %r11, -4568(%rbp)
	movq -5760(%rbp), %r11
	movq %r11, -4560(%rbp)
	movq -5752(%rbp), %r11
	movq %r11, -4552(%rbp)
	movq %r8, -4560(%rbp)
	movq (%rax), %r8
	cmpq %r8, %r9
	jae .Lbb705
	movq 32(%rax), %r8
	movq -4568(%rbp), %rax
	movq %rax, 0(%rcx, %r8, 1)
	movq -4560(%rbp), %rax
	movq %rax, 8(%rcx, %r8, 1)
	movq -4552(%rbp), %rax
	movq %rax, 16(%rcx, %r8, 1)
	movq 128(%rsi), %rax
	movq %rax, -464(%rbp)
	cmpl $0, %r10d
	jz .Lbb588
	testl $28, %r14d
	jnz .Lbb586
	.loc 1 1339
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3736(%rbp), %rdx
	movq -464(%rbp), %rax
	movl $0, %r10d
	jmp .Lbb588
.Lbb586:
	.loc 1 1339
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3736(%rbp), %rdx
	movq -464(%rbp), %rax
	movl $0, %r10d
.Lbb588:
	movq $-9223372036854775807, %rcx
	cmpq %rcx, %rax
	jl .Lbb703
	subq $1, %rax
	movq %rax, 128(%rsi)
	movq 120(%rsi), %rax
	movq %rax, -472(%rbp)
	cmpl $0, %r10d
	jz .Lbb595
	testl $28, %r14d
	jnz .Lbb593
	.loc 1 1354
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3736(%rbp), %rdx
	movq -472(%rbp), %rax
	movl $0, %r10d
	jmp .Lbb595
.Lbb593:
	.loc 1 1354
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3736(%rbp), %rdx
	movq -472(%rbp), %rax
	movl $0, %r10d
.Lbb595:
	movq 128(%rsi), %rcx
	movq %rcx, -480(%rbp)
	cmpl $0, %r10d
	jnz .Lbb597
	movq %rsi, %r13
	movq %rdx, %rsi
	movl %r10d, -504(%rbp)
	jmp .Lbb602
.Lbb597:
	testl $28, %r14d
	jnz .Lbb600
	.loc 1 1357
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3736(%rbp), %rdx
	movq -480(%rbp), %rcx
	movq -472(%rbp), %rax
	movq %rsi, %r13
	movq %rdx, %rsi
	movl $0, -504(%rbp)
	jmp .Lbb602
.Lbb600:
	.loc 1 1357
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rsi, %r13
	movq -3736(%rbp), %rsi
	movq -480(%rbp), %rcx
	movq -472(%rbp), %rax
	movl $0, -504(%rbp)
.Lbb602:
	cmpq $0, %rcx
	jge .Lbb605
	movq (%rax), %r10
	movq $9223372036854775807, %rdx
	cmpq %rdx, %r10
	ja .Lbb701
	movq %rcx, %r9
	addq %r10, %rcx
	movq %r10, %rdx
	xorq %rcx, %rdx
	movq %r9, %r8
	xorq %rcx, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jl .Lbb699
.Lbb605:
	movq (%rax), %rdx
	cmpq %rdx, %rcx
	jae .Lbb698
	movq 32(%rax), %rax
	imulq $16, %rcx, %rcx
	movq 0(%rax, %rcx, 1), %rdx
	movq %rdx, 0(%rsi)
	movq 8(%rax, %rcx, 1), %rax
	movq %rax, 8(%rsi)
	.loc 1 1370
	movq %rdi, %r12
	callq myl_f_a9f74430ee4e948451728b3abe4d648b4eecdee44abb338e15267f988b669b40
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, %rcx
	movl %r9d, %r14d
	movq -488(%rbp), %r9
	movq -496(%rbp), %r8
	movq -3648(%rbp), %rdx
	.loc 1 1377
	movq %rsi, %r13
	movq %rdi, %r12
	callq myl_f_f618d2a038c2e9d22503f0ab6a437ba21fd23a0574688674fa284a5ef69311cf
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, -664(%rbp)
	movl -504(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r12d, %r9d
	movl -3676(%rbp), %r12d
	movq -3656(%rbp), %rax
	movq -3792(%rbp), %r11
	movq -3648(%rbp), %rdx
	cmpl $0, %r10d
	jz .Lbb612
	testl $28, %r14d
	jnz .Lbb610
	.loc 1 1377
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r12d, %r9d
	movl -3676(%rbp), %r12d
	movq -3656(%rbp), %rax
	movq -3792(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb612
.Lbb610:
	.loc 1 1377
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r12d, %r9d
	movl -3676(%rbp), %r12d
	movq -3656(%rbp), %rax
	movq -3792(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb612:
	movl %r10d, -588(%rbp)
	cmpl $0, %r8d
	jnz .Lbb614
	xchgl %r15d, %r12d
	xchgl %r9d, %r8d
	jmp .Lbb619
.Lbb614:
	testl $28, %r15d
	jnz .Lbb617
	.loc 1 1377
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_3ece1c6f770ecd2a506fa806688c97e383087567b3626d4a9ce4529758a6df1f_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movl -588(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r12d, %r8d
	movl -3676(%rbp), %r12d
	movq -3656(%rbp), %rax
	movq -3792(%rbp), %r11
	movq -3648(%rbp), %rdx
	xchgl %r15d, %r12d
	movl $0, %r9d
	jmp .Lbb619
.Lbb617:
	.loc 1 1377
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_3ece1c6f770ecd2a506fa806688c97e383087567b3626d4a9ce4529758a6df1f_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movl -588(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r15d, %r12d
	movl -3676(%rbp), %r15d
	movq -3656(%rbp), %rax
	movq -3792(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r9d
.Lbb619:
	cmpl $0, -664(%rbp)
	jnz .Lbb621
	movq -664(%rbp), %r11
	xchgl %r14d, %r9d
	xchgl %r15d, %r14d
	xchgl %r8d, %r15d
	jmp .Lbb689
.Lbb621:
	movl %r9d, %r8d
	movq %r11, %rcx
	movq 136(%rsi), %rax
	movq %rax, -520(%rbp)
	cmpl $0, %r8d
	jz .Lbb628
	testl $28, %r12d
	jnz .Lbb626
	.loc 1 1383
	movq %rsi, %r15
	leaq -6808(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r15, %rsi
	movq %r13, %rdi
	movq -3792(%rbp), %rcx
	movq -520(%rbp), %rax
	movl $0, %r8d
	jmp .Lbb628
.Lbb626:
	.loc 1 1383
	movq %rsi, %r15
	leaq -6808(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r15, %rsi
	movq %r13, %rdi
	movq -3792(%rbp), %rcx
	movq -520(%rbp), %rax
	movl $0, %r8d
.Lbb628:
	movq 144(%rsi), %rdx
	movq %rdx, -512(%rbp)
	cmpl $0, %r8d
	jnz .Lbb630
	movl %r8d, -668(%rbp)
	jmp .Lbb635
.Lbb630:
	testl $28, %r12d
	jnz .Lbb633
	.loc 1 1386
	movq %rsi, %r15
	leaq -6808(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r15, %rsi
	movq %r13, %rdi
	movq -3792(%rbp), %rcx
	movq -512(%rbp), %rdx
	movq -520(%rbp), %rax
	movl $0, -668(%rbp)
	jmp .Lbb635
.Lbb633:
	.loc 1 1386
	movq %rsi, %r15
	leaq -6808(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r15, %rsi
	movq %r13, %rdi
	movq -3792(%rbp), %rcx
	movq -512(%rbp), %rdx
	movq -520(%rbp), %rax
	movl $0, -668(%rbp)
.Lbb635:
	movq $-9223372036854775807, %r8
	cmpq %r8, %rdx
	jl .Lbb697
	movq %rsi, %r15
	movq %rdx, %rsi
	subq $1, %rsi
	cmpq $0, %rsi
	jge .Lbb639
	movq (%rax), %r10
	movq $9223372036854775807, %rdx
	cmpq %rdx, %r10
	ja .Lbb695
	movq %rsi, %r9
	addq %r10, %rsi
	movq %r10, %rdx
	xorq %rsi, %rdx
	movq %r9, %r8
	xorq %rsi, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jl .Lbb693
.Lbb639:
	movq (%rax), %rdx
	cmpq %rdx, %rsi
	jae .Lbb692
	movq 32(%rax), %rax
	imulq $24, %rsi, %rdx
	movq 0(%rax, %rdx, 1), %rsi
	movq %rsi, 0(%rcx)
	movq 8(%rax, %rdx, 1), %rsi
	movq %rsi, 8(%rcx)
	movq 16(%rax, %rdx, 1), %rax
	movq %rax, 16(%rcx)
	.loc 1 1401
	movq %r15, %rdx
	movq %rdi, %rsi
	movq %rdi, %r13
	leaq -7120(%rbp), %rdi
	callq myl_f_bf0431d3d9e553eacefcb10ebb00251bb8b43354cc87fd12c99ceb5644f705d6
	movl %r14d, %r9d
	movq %r13, %rdi
	movq %rax, %rsi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl -3676(%rbp), %r14d
	movq -3656(%rbp), %rax
	movq -3816(%rbp), %r11
	movq -3648(%rbp), %rdx
	movq 0(%rsi), %r10
	movq %r10, -6392(%rbp)
	movq 8(%rsi), %r10
	movq %r10, -6384(%rbp)
	movq 16(%rsi), %r10
	movq %r10, -6376(%rbp)
	movq 24(%rsi), %r10
	movq %r10, -6368(%rbp)
	movl -588(%rbp), %r10d
	movq 32(%rsi), %rsi
	movq %rsi, -6360(%rbp)
	movq -3776(%rbp), %rsi
	cmpl $0, %r10d
	movq -3768(%rbp), %r10
	jnz .Lbb642
	movl %r8d, %r9d
	jmp .Lbb646
.Lbb642:
	testl $28, %r9d
	jnz .Lbb645
	.loc 1 1401
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rdi
	movq -3768(%rbp), %rsi
	movq %rsi, %r8
	movq -3776(%rbp), %rsi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r9d
	movl -3672(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -3816(%rbp), %r11
	movq -3648(%rbp), %rdx
	movq %r8, %r10
	jmp .Lbb646
.Lbb645:
	.loc 1 1401
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r13, %rdi
	movq -3768(%rbp), %rsi
	movq %rsi, %r10
	movq -3776(%rbp), %rsi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r9d
	movl -3672(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -3816(%rbp), %r11
	movq -3648(%rbp), %rdx
.Lbb646:
	movq -6392(%rbp), %r8
	movq %r8, -7016(%rbp)
	movq -6384(%rbp), %r8
	movq %r8, -7008(%rbp)
	movq -6376(%rbp), %r8
	movq %r8, -7000(%rbp)
	movq -6368(%rbp), %r8
	movq %r8, -6992(%rbp)
	movq -6360(%rbp), %r8
	movq %r8, -6984(%rbp)
	movq -7016(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb648
	movq -16(%r8), %r8
	movq %r8, -528(%rbp)
	movq -3768(%rbp), %r10
	movq $5764607523034234881, %r8
	movq %r8, -536(%rbp)
	movq -528(%rbp), %r8
	andq -536(%rbp), %r8
	cmpq $0, %r8
	jnz .Lbb655
.Lbb648:
	movq -7008(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb650
	movq -16(%r8), %r8
	movq %r8, -544(%rbp)
	movq -3768(%rbp), %r10
	movq $5764607523034234881, %r8
	movq %r8, -552(%rbp)
	movq -544(%rbp), %r8
	andq -552(%rbp), %r8
	cmpq $0, %r8
	jnz .Lbb655
.Lbb650:
	movq -7000(%rbp), %r8
	movq %r8, -560(%rbp)
	movl -668(%rbp), %r8d
	cmpq $0, -560(%rbp)
	jnz .Lbb652
	xchgq %r10, %r13
	jmp .Lbb654
.Lbb652:
	movq -560(%rbp), %r8
	movq -16(%r8), %r8
	movq %r8, -576(%rbp)
	movl %r13d, %r10d
	movq -3768(%rbp), %r13
	movq $5764607523034234881, %r8
	movq %r8, -568(%rbp)
	movq -576(%rbp), %r8
	andq -568(%rbp), %r8
	movq %r8, -584(%rbp)
	movl -668(%rbp), %r8d
	cmpq $0, -584(%rbp)
	jnz .Lbb655
.Lbb654:
	movq -7016(%rbp), %r11
	movq %r11, -6392(%rbp)
	movq -7008(%rbp), %r11
	movq %r11, -6384(%rbp)
	movq -7000(%rbp), %r11
	movq %r11, -6376(%rbp)
	movq -6992(%rbp), %r11
	movq %r11, -6368(%rbp)
	movq -6984(%rbp), %r11
	movq %r11, -6360(%rbp)
	movq -664(%rbp), %r11
	movq $0, -7016(%rbp)
	movq $0, -7008(%rbp)
	movq $0, -7000(%rbp)
	movq $0, -6992(%rbp)
	movq $0, -6984(%rbp)
	jmp .Lbb656
.Lbb655:
	movq %r11, %rcx
	.loc 1 1402
	movq %rcx, %r11
	leaq -7016(%rbp), %rdx
	leaq -6392(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_take
	movq %r13, %rdi
	movl %eax, -592(%rbp)
	movq -3768(%rbp), %rsi
	movq %rsi, %r13
	movq -3776(%rbp), %rsi
	movl -668(%rbp), %r8d
	movl -3664(%rbp), %r10d
	movl -3668(%rbp), %r9d
	movl -3672(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -664(%rbp), %r11
	movq -3648(%rbp), %rdx
	cmpl $0, -592(%rbp)
	jz .Lbb690
.Lbb656:
	cmpl $0, %r10d
	jnz .Lbb658
	movq %r15, %rsi
	jmp .Lbb687
.Lbb658:
	testl $28, %r9d
	jnz .Lbb685
	movq -6144(%rbp), %r10
	cmpq $0, %r10
	jz .Lbb666
	movq -16(%r10), %r9
	movq %r9, -600(%rbp)
	movq $4611686018427387906, %r9
	movq %r9, -608(%rbp)
	movq -600(%rbp), %r9
	andq -608(%rbp), %r9
	cmpq $0, %r9
	jnz .Lbb665
	movq -32(%r10), %r9
	subq $1, %r9
	movq %r9, -616(%rbp)
	jnz .Lbb664
	movq -24(%r10), %r9
	movq %r9, -624(%rbp)
	movq -616(%rbp), %r9
	cmpq $0, -624(%rbp)
	jnz .Lbb664
	.loc 1 1402
	leaq -6144(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a_rcg_drop
	movq %r13, %rdi
	movq -3768(%rbp), %rsi
	movq %rsi, %r13
	movq -3776(%rbp), %rsi
	movl -668(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -664(%rbp), %r11
	movq -3648(%rbp), %rdx
	jmp .Lbb666
.Lbb664:
	movq %r9, -32(%r10)
.Lbb665:
	movq $0, -6144(%rbp)
.Lbb666:
	movq -6136(%rbp), %r10
	cmpq $0, %r10
	jnz .Lbb668
	movq %r13, %rsi
	jmp .Lbb675
.Lbb668:
	movq -16(%r10), %r9
	movq %r9, -632(%rbp)
	movq $4611686018427387906, %r9
	movq %r9, -640(%rbp)
	movq -632(%rbp), %r9
	andq -640(%rbp), %r9
	cmpq $0, %r9
	jnz .Lbb673
	movq -32(%r10), %r9
	subq $1, %r9
	movq %r9, -648(%rbp)
	jnz .Lbb672
	movq -24(%r10), %r9
	movq %r9, -656(%rbp)
	movq -648(%rbp), %r9
	cmpq $0, -656(%rbp)
	jnz .Lbb672
	.loc 1 1402
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %r15, %rsi
	movq %r13, %rdi
	movq %rsi, %r15
	movq -3768(%rbp), %rsi
	movl -668(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -664(%rbp), %r11
	movq -3648(%rbp), %rdx
	jmp .Lbb675
.Lbb672:
	movq %r13, %rsi
	movq %r9, -32(%r10)
	jmp .Lbb674
.Lbb673:
	movq %r13, %rsi
.Lbb674:
	movq $0, -6136(%rbp)
.Lbb675:
	movq -6128(%rbp), %r10
	cmpq $0, %r10
	jnz .Lbb677
	movq %r15, %rsi
	jmp .Lbb684
.Lbb677:
	movq -16(%r10), %r9
	movq $4611686018427387906, %r13
	andq %r13, %r9
	cmpq $0, %r9
	jnz .Lbb682
	movq -32(%r10), %r9
	subq $1, %r9
	jnz .Lbb681
	movq -24(%r10), %r13
	cmpq $0, %r13
	jnz .Lbb681
	.loc 1 1402
	movq %rsi, %r10
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %r15, %rsi
	movq %r13, %rdi
	movl -668(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -664(%rbp), %r11
	movq -3648(%rbp), %rdx
	jmp .Lbb684
.Lbb681:
	movq %r15, %rsi
	movq %r9, -32(%r10)
	jmp .Lbb683
.Lbb682:
	movq %r15, %rsi
.Lbb683:
	movq $0, -6128(%rbp)
.Lbb684:
	movq $0, -6144(%rbp)
	movq $0, -6136(%rbp)
	movq $0, -6128(%rbp)
	movq $0, -6120(%rbp)
	movq $0, -6112(%rbp)
	jmp .Lbb687
.Lbb685:
	movq %r15, %rsi
	.loc 1 1402
	movq %rsi, %r15
	leaq -6144(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r15, %rsi
	movq %r13, %rdi
	movl -668(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -664(%rbp), %r11
	movq -3648(%rbp), %rdx
.Lbb687:
	movq -6392(%rbp), %r9
	movq %r9, -6144(%rbp)
	movq -6384(%rbp), %r9
	movq %r9, -6136(%rbp)
	movq -6376(%rbp), %r9
	movq %r9, -6128(%rbp)
	movq -6368(%rbp), %r9
	movq %r9, -6120(%rbp)
	movq -6360(%rbp), %r9
	movq %r9, -6112(%rbp)
	movl $1, %r13d
	movl $2, %r15d
	movl $0, %r10d
	movl $2, %r9d
.Lbb689:
	xchgl %r15d, %r12d
	jmp .Lbb2674
.Lbb690:
	xchgq %rbx, %rdi
	.loc 1 1402
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 1402
	callq myl_qbe_rc_status
	jmp .Lbb2692
.Lbb692:
	.loc 1 1400
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb693:
	movq %r9, %rcx
	movq %r10, %rsi
	.loc 1 1397
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb695:
	movq %r10, %rsi
	.loc 1 1395
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb697:
	.loc 1 1388
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb698:
	.loc 1 1369
	movq %rcx, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb699:
	movq %r10, %rsi
	movq %r9, %rcx
	.loc 1 1366
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb701:
	movq %r10, %rsi
	.loc 1 1364
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb703:
	movq %rax, %rdx
	.loc 1 1341
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb705:
	movq %r8, %rdx
	.loc 1 1334
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb707:
	movq %r11, %rdx
	.loc 1 1328
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb709:
	movq %rcx, %rdx
	.loc 1 1325
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb711:
	movq %r11, %rsi
	.loc 1 1320
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb713:
	movq %r11, %rsi
	.loc 1 1318
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb715:
	movq %r9, %rdx
	.loc 1 1311
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	movq %rdi, %rbx
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb717:
	xchgl %r14d, %r15d
	.loc 1 1220
	movq %rsi, %r13
	leaq -6144(%rbp), %rsi
	movq %rdi, %r12
	callq myl_f_94484f74f9fdfe749fe3bbd5703ff3b6b2a0ee43d3569a1125fbe02c5095250d
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, -696(%rbp)
	movl -3588(%rbp), %r12d
	cmpl $0, %r15d
	jnz .Lbb720
	movl %r15d, -672(%rbp)
	movl %r12d, %r15d
	jmp .Lbb726
.Lbb720:
	movl %r12d, %r15d
	testl $28, %r14d
	jnz .Lbb724
	.loc 1 1220
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movl $0, -672(%rbp)
	jmp .Lbb726
.Lbb724:
	.loc 1 1220
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movl $0, -672(%rbp)
.Lbb726:
	.loc 1 1223
	movq %rsi, %r13
	leaq -6144(%rbp), %rsi
	movq %rdi, %r12
	callq myl_f_fa0a495025828a635f8203a4c546663c235c2574b972f1294569bb6fadb2fcc2
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, %r8
	movl -672(%rbp), %r10d
	movq -696(%rbp), %rcx
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movq %r8, -688(%rbp)
	cmpl $0, %r10d
	jz .Lbb732
	testl $28, %r14d
	jnz .Lbb730
	.loc 1 1223
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -688(%rbp), %r8
	movq -696(%rbp), %rcx
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb732
.Lbb730:
	.loc 1 1223
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -688(%rbp), %r8
	movq -696(%rbp), %rcx
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb732:
	movq -6120(%rbp), %rax
	movq %rax, -680(%rbp)
	cmpl $0, %r10d
	jz .Lbb738
	testl $28, %r14d
	jnz .Lbb736
	.loc 1 1226
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -680(%rbp), %r11
	movq -688(%rbp), %r8
	movq -696(%rbp), %rcx
	movq %r11, %rax
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb738
.Lbb736:
	.loc 1 1226
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -680(%rbp), %r11
	movq -688(%rbp), %r8
	movq -696(%rbp), %rcx
	movq %r11, %rax
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb738:
	cmpl $0, %r10d
	jnz .Lbb740
	movl %r14d, %r9d
	jmp .Lbb745
.Lbb740:
	testl $28, %r14d
	jnz .Lbb743
	.loc 1 1229
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -680(%rbp), %r11
	movq -688(%rbp), %r8
	movq -696(%rbp), %rcx
	movq %r11, %rax
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl %r14d, %r9d
	movl $0, %r10d
	jmp .Lbb745
.Lbb743:
	.loc 1 1229
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -680(%rbp), %r11
	movq -688(%rbp), %r8
	movq -696(%rbp), %rcx
	movq %r11, %rax
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb745:
	cmpl $0, %r10d
	jz .Lbb765
	testl $28, %r9d
	jnz .Lbb756
	movq -7016(%rbp), %r12
	cmpq $0, %r12
	jz .Lbb755
	movq -16(%r12), %r10
	movq $4611686018427387906, %r13
	andq %r13, %r10
	cmpq $0, %r10
	jnz .Lbb754
	movq -32(%r12), %r10
	subq $1, %r10
	jnz .Lbb753
	movl %r9d, %r14d
	movq -24(%r12), %r9
	cmpq $0, %r9
	jnz .Lbb752
	.loc 1 1230
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -680(%rbp), %r11
	movq -688(%rbp), %r8
	movq -696(%rbp), %rcx
	movq %r11, %rax
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	jmp .Lbb755
.Lbb752:
	movl %r14d, %r9d
.Lbb753:
	movq %r10, -32(%r12)
.Lbb754:
	movq $0, -7016(%rbp)
.Lbb755:
	movl $0, %r10d
	jmp .Lbb765
.Lbb756:
	movq -7016(%rbp), %r12
	cmpq $0, %r12
	jz .Lbb764
	movq -16(%r12), %r10
	movq $4611686018427387906, %r13
	andq %r13, %r10
	cmpq $0, %r10
	jnz .Lbb763
	movq -24(%r12), %r10
	subq $1, %r10
	jnz .Lbb762
	movl %r9d, %r14d
	movq -32(%r12), %r9
	cmpq $0, %r9
	jnz .Lbb761
	.loc 1 1230
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -680(%rbp), %r11
	movq -688(%rbp), %r8
	movq -696(%rbp), %rcx
	movq %r11, %rax
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	jmp .Lbb764
.Lbb761:
	movl %r14d, %r9d
.Lbb762:
	movq %r10, -24(%r12)
.Lbb763:
	movq $0, -7016(%rbp)
.Lbb764:
	movl $0, %r10d
.Lbb765:
	movl %r10d, -732(%rbp)
	movl %r9d, %r14d
	movq 136(%rsi), %r9
	cmpq $0, %r9
	jnz .Lbb767
	movq %rax, %r11
	jmp .Lbb771
.Lbb767:
	movq -16(%r9), %r12
	movq $6917529027641081858, %r13
	andq %r13, %r12
	cmpq $0, %r12
	jnz .Lbb770
	movq -32(%r9), %r9
	cmpq $2, %r9
	jae .Lbb770
	movq %rax, %r11
	jmp .Lbb771
.Lbb770:
	.loc 1 1230
	movl $0, %ecx
	movq %r11, %rdx
	movq %rsi, %r13
	movq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	callq myl_qbe_rc_unique_field
	movq %r13, %rsi
	movq %r12, %rdi
	movl -732(%rbp), %r10d
	movq -680(%rbp), %r11
	movq -688(%rbp), %r8
	movq -696(%rbp), %rcx
	movq -3648(%rbp), %rdx
	cmpl $0, %eax
	jz .Lbb2692
.Lbb771:
	movq 136(%rsi), %rax
	movq %rax, -712(%rbp)
	movl %r10d, %r12d
	movq 144(%rsi), %r10
	movq %r10, -704(%rbp)
	cmpl $0, %r12d
	jnz .Lbb773
	movl %r14d, %r9d
	movl %r12d, -736(%rbp)
	jmp .Lbb778
.Lbb773:
	testl $28, %r14d
	jnz .Lbb776
	.loc 1 1232
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -704(%rbp), %r10
	movq -712(%rbp), %rax
	movq -680(%rbp), %r11
	movq -688(%rbp), %r8
	movq -696(%rbp), %rcx
	movq -3648(%rbp), %rdx
	movl %r14d, %r9d
	movl $0, -736(%rbp)
	jmp .Lbb778
.Lbb776:
	.loc 1 1232
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -704(%rbp), %r10
	movq -712(%rbp), %rax
	movq -680(%rbp), %r11
	movq -688(%rbp), %r8
	movq -696(%rbp), %rcx
	movq -3648(%rbp), %rdx
	movl $0, -736(%rbp)
.Lbb778:
	movq $-9223372036854775807, %r12
	cmpq %r12, %r10
	jl .Lbb888
	subq $1, %r10
	cmpq $0, %r10
	jge .Lbb782
	movq (%rax), %r13
	movq $9223372036854775807, %r12
	cmpq %r12, %r13
	ja .Lbb886
	movq %r10, %r12
	addq %r13, %r10
	movq %r13, %r14
	xorq %r10, %r14
	movq %r14, -720(%rbp)
	movq %r12, %r14
	xorq %r10, %r14
	movq %r14, -728(%rbp)
	movq -720(%rbp), %r14
	andq -728(%rbp), %r14
	cmpq $0, %r14
	jl .Lbb884
.Lbb782:
	movq (%rax), %r12
	cmpq %r12, %r10
	jae .Lbb882
	movq 32(%rax), %r12
	movl %r9d, %r14d
	imulq $24, %r10, %r9
	movq 0(%r12, %r9, 1), %r13
	movq %r13, -5792(%rbp)
	movq 8(%r12, %r9, 1), %r13
	movq %r13, -5784(%rbp)
	movq 16(%r12, %r9, 1), %r12
	movq %r12, -5776(%rbp)
	movq (%rax), %r12
	cmpq %r12, %r10
	jae .Lbb880
	movq 32(%rax), %r12
	movq 0(%r9, %r12, 1), %r13
	movq %r13, -5792(%rbp)
	movq 8(%r9, %r12, 1), %r13
	movq %r13, -5784(%rbp)
	movq 16(%r9, %r12, 1), %r12
	movq %r12, -5776(%rbp)
	movq -5792(%rbp), %r12
	movq %r12, -4592(%rbp)
	movq -5784(%rbp), %r12
	movq %r12, -4584(%rbp)
	movq -5776(%rbp), %r12
	movq %r12, -4576(%rbp)
	movq %r11, -4584(%rbp)
	movq (%rax), %r11
	cmpq %r11, %r10
	jae .Lbb878
	movq 32(%rax), %r10
	movq -4592(%rbp), %rax
	movq %rax, 0(%r9, %r10, 1)
	movq -4584(%rbp), %rax
	movq %rax, 8(%r9, %r10, 1)
	movq -4576(%rbp), %rax
	movq %rax, 16(%r9, %r10, 1)
	.loc 1 1265
	movq %rsi, %r13
	movq %rdi, %r12
	callq myl_f_8bc987cd8d73e85833672ca9fc6ae7f39c86d782cf8553d5c88364ca472ade1f
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, -896(%rbp)
	movl -736(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r12d, %r9d
	movl -3676(%rbp), %r12d
	movq -3656(%rbp), %rax
	movq -3800(%rbp), %r11
	movq -3648(%rbp), %rdx
	cmpl $0, %r10d
	jz .Lbb791
	testl $28, %r14d
	jnz .Lbb789
	.loc 1 1265
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r12d, %r9d
	movl -3676(%rbp), %r12d
	movq -3656(%rbp), %rax
	movq -3800(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb791
.Lbb789:
	.loc 1 1265
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r12d, %r9d
	movl -3676(%rbp), %r12d
	movq -3656(%rbp), %rax
	movq -3800(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb791:
	movl %r10d, -820(%rbp)
	cmpl $0, %r8d
	jnz .Lbb793
	xchgl %r15d, %r12d
	xchgl %r9d, %r8d
	jmp .Lbb798
.Lbb793:
	testl $28, %r15d
	jnz .Lbb796
	.loc 1 1265
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_3ece1c6f770ecd2a506fa806688c97e383087567b3626d4a9ce4529758a6df1f_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movl -820(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r12d, %r8d
	movl -3676(%rbp), %r12d
	movq -3656(%rbp), %rax
	movq -3800(%rbp), %r11
	movq -3648(%rbp), %rdx
	xchgl %r15d, %r12d
	movl $0, %r9d
	jmp .Lbb798
.Lbb796:
	.loc 1 1265
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_3ece1c6f770ecd2a506fa806688c97e383087567b3626d4a9ce4529758a6df1f_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movl -820(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r15d, %r12d
	movl -3676(%rbp), %r15d
	movq -3656(%rbp), %rax
	movq -3800(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r9d
.Lbb798:
	cmpl $0, -896(%rbp)
	jnz .Lbb800
	movq -896(%rbp), %r11
	xchgl %r15d, %r13d
	xchgl %r14d, %r9d
	xchgl %r8d, %r14d
	jmp .Lbb869
.Lbb800:
	movl %r9d, %r8d
	movq %r11, %rcx
	movq 136(%rsi), %rax
	movq %rax, -752(%rbp)
	cmpl $0, %r8d
	jz .Lbb807
	testl $28, %r12d
	jnz .Lbb805
	.loc 1 1271
	movq %rsi, %r15
	leaq -6808(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r15, %rsi
	movq %r13, %rdi
	movq -3800(%rbp), %rcx
	movq -752(%rbp), %rax
	movl $0, %r8d
	jmp .Lbb807
.Lbb805:
	.loc 1 1271
	movq %rsi, %r15
	leaq -6808(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r15, %rsi
	movq %r13, %rdi
	movq -3800(%rbp), %rcx
	movq -752(%rbp), %rax
	movl $0, %r8d
.Lbb807:
	movq 144(%rsi), %rdx
	movq %rdx, -744(%rbp)
	cmpl $0, %r8d
	jnz .Lbb809
	movl %r8d, -900(%rbp)
	jmp .Lbb814
.Lbb809:
	testl $28, %r12d
	jnz .Lbb812
	.loc 1 1274
	movq %rsi, %r15
	leaq -6808(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r15, %rsi
	movq %r13, %rdi
	movq -3800(%rbp), %rcx
	movq -744(%rbp), %rdx
	movq -752(%rbp), %rax
	movl $0, -900(%rbp)
	jmp .Lbb814
.Lbb812:
	.loc 1 1274
	movq %rsi, %r15
	leaq -6808(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r15, %rsi
	movq %r13, %rdi
	movq -3800(%rbp), %rcx
	movq -744(%rbp), %rdx
	movq -752(%rbp), %rax
	movl $0, -900(%rbp)
.Lbb814:
	movq $-9223372036854775807, %r8
	cmpq %r8, %rdx
	jl .Lbb877
	movq %rsi, %r15
	movq %rdx, %rsi
	subq $1, %rsi
	cmpq $0, %rsi
	jge .Lbb818
	movq (%rax), %r10
	movq $9223372036854775807, %rdx
	cmpq %rdx, %r10
	ja .Lbb875
	movq %rsi, %r9
	addq %r10, %rsi
	movq %r10, %rdx
	xorq %rsi, %rdx
	movq %r9, %r8
	xorq %rsi, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jl .Lbb873
.Lbb818:
	movq (%rax), %rdx
	cmpq %rdx, %rsi
	jae .Lbb872
	movq 32(%rax), %rax
	imulq $24, %rsi, %rdx
	movq 0(%rax, %rdx, 1), %rsi
	movq %rsi, 0(%rcx)
	movq 8(%rax, %rdx, 1), %rsi
	movq %rsi, 8(%rcx)
	movq 16(%rax, %rdx, 1), %rax
	movq %rax, 16(%rcx)
	.loc 1 1289
	movq %r15, %rdx
	movq %rdi, %rsi
	movq %rdi, %r13
	leaq -7160(%rbp), %rdi
	callq myl_f_bf0431d3d9e553eacefcb10ebb00251bb8b43354cc87fd12c99ceb5644f705d6
	movl %r14d, %r9d
	movq %r13, %rdi
	movq %rax, %rsi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl -3676(%rbp), %r14d
	movq -3656(%rbp), %rax
	movq -3816(%rbp), %r11
	movq -3648(%rbp), %rdx
	movq 0(%rsi), %r10
	movq %r10, -6392(%rbp)
	movq 8(%rsi), %r10
	movq %r10, -6384(%rbp)
	movq 16(%rsi), %r10
	movq %r10, -6376(%rbp)
	movq 24(%rsi), %r10
	movq %r10, -6368(%rbp)
	movl -820(%rbp), %r10d
	movq 32(%rsi), %rsi
	movq %rsi, -6360(%rbp)
	movq -3776(%rbp), %rsi
	cmpl $0, %r10d
	movq -3768(%rbp), %r10
	jnz .Lbb821
	movl %r8d, %r9d
	jmp .Lbb825
.Lbb821:
	testl $28, %r9d
	jnz .Lbb824
	.loc 1 1289
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rdi
	movq -3768(%rbp), %rsi
	movq %rsi, %r8
	movq -3776(%rbp), %rsi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r9d
	movl -3672(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -3816(%rbp), %r11
	movq -3648(%rbp), %rdx
	movq %r8, %r10
	jmp .Lbb825
.Lbb824:
	.loc 1 1289
	leaq -7016(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r13, %rdi
	movq -3768(%rbp), %rsi
	movq %rsi, %r10
	movq -3776(%rbp), %rsi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r9d
	movl -3672(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -3816(%rbp), %r11
	movq -3648(%rbp), %rdx
.Lbb825:
	movq -6392(%rbp), %r8
	movq %r8, -7016(%rbp)
	movq -6384(%rbp), %r8
	movq %r8, -7008(%rbp)
	movq -6376(%rbp), %r8
	movq %r8, -7000(%rbp)
	movq -6368(%rbp), %r8
	movq %r8, -6992(%rbp)
	movq -6360(%rbp), %r8
	movq %r8, -6984(%rbp)
	movq -7016(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb827
	movq -16(%r8), %r8
	movq %r8, -760(%rbp)
	movq -3768(%rbp), %r10
	movq $5764607523034234881, %r8
	movq %r8, -768(%rbp)
	movq -760(%rbp), %r8
	andq -768(%rbp), %r8
	cmpq $0, %r8
	jnz .Lbb834
.Lbb827:
	movq -7008(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb829
	movq -16(%r8), %r8
	movq %r8, -776(%rbp)
	movq -3768(%rbp), %r10
	movq $5764607523034234881, %r8
	movq %r8, -784(%rbp)
	movq -776(%rbp), %r8
	andq -784(%rbp), %r8
	cmpq $0, %r8
	jnz .Lbb834
.Lbb829:
	movq -7000(%rbp), %r8
	movq %r8, -792(%rbp)
	movl -900(%rbp), %r8d
	cmpq $0, -792(%rbp)
	jnz .Lbb831
	xchgq %r10, %r13
	jmp .Lbb833
.Lbb831:
	movq -792(%rbp), %r8
	movq -16(%r8), %r8
	movq %r8, -808(%rbp)
	movl %r13d, %r10d
	movq -3768(%rbp), %r13
	movq $5764607523034234881, %r8
	movq %r8, -800(%rbp)
	movq -808(%rbp), %r8
	andq -800(%rbp), %r8
	movq %r8, -816(%rbp)
	movl -900(%rbp), %r8d
	cmpq $0, -816(%rbp)
	jnz .Lbb834
.Lbb833:
	movq -7016(%rbp), %r11
	movq %r11, -6392(%rbp)
	movq -7008(%rbp), %r11
	movq %r11, -6384(%rbp)
	movq -7000(%rbp), %r11
	movq %r11, -6376(%rbp)
	movq -6992(%rbp), %r11
	movq %r11, -6368(%rbp)
	movq -6984(%rbp), %r11
	movq %r11, -6360(%rbp)
	movq -896(%rbp), %r11
	movq $0, -7016(%rbp)
	movq $0, -7008(%rbp)
	movq $0, -7000(%rbp)
	movq $0, -6992(%rbp)
	movq $0, -6984(%rbp)
	jmp .Lbb835
.Lbb834:
	movq %r11, %rcx
	.loc 1 1290
	leaq -7016(%rbp), %rdx
	leaq -6392(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_take
	movq %r13, %rdi
	movl %eax, -824(%rbp)
	movq -3768(%rbp), %rsi
	movq %rsi, %r13
	movq -3776(%rbp), %rsi
	movl -900(%rbp), %r8d
	movl -3664(%rbp), %r10d
	movl -3668(%rbp), %r9d
	movl -3672(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -896(%rbp), %r11
	movq -3648(%rbp), %rdx
	cmpl $0, -824(%rbp)
	jz .Lbb870
.Lbb835:
	cmpl $0, %r10d
	jnz .Lbb837
	movl %r14d, %r13d
	movq %r15, %rsi
	jmp .Lbb867
.Lbb837:
	testl $28, %r9d
	jnz .Lbb865
	movq -6144(%rbp), %r10
	cmpq $0, %r10
	jz .Lbb845
	movq -16(%r10), %r9
	movq %r9, -832(%rbp)
	movq $4611686018427387906, %r9
	movq %r9, -840(%rbp)
	movq -832(%rbp), %r9
	andq -840(%rbp), %r9
	cmpq $0, %r9
	jnz .Lbb844
	movq -32(%r10), %r9
	subq $1, %r9
	movq %r9, -848(%rbp)
	jnz .Lbb843
	movq -24(%r10), %r9
	movq %r9, -856(%rbp)
	movq -848(%rbp), %r9
	cmpq $0, -856(%rbp)
	jnz .Lbb843
	.loc 1 1290
	leaq -6144(%rbp), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a_rcg_drop
	movq %r13, %rdi
	movq -3768(%rbp), %rsi
	movq %rsi, %r13
	movq -3776(%rbp), %rsi
	movl -900(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -896(%rbp), %r11
	movq -3648(%rbp), %rdx
	jmp .Lbb845
.Lbb843:
	movq %r9, -32(%r10)
.Lbb844:
	movq $0, -6144(%rbp)
.Lbb845:
	movq -6136(%rbp), %r10
	cmpq $0, %r10
	jnz .Lbb847
	movq %r13, %rsi
	jmp .Lbb854
.Lbb847:
	movq -16(%r10), %r9
	movq %r9, -864(%rbp)
	movq $4611686018427387906, %r9
	movq %r9, -872(%rbp)
	movq -864(%rbp), %r9
	andq -872(%rbp), %r9
	cmpq $0, %r9
	jnz .Lbb852
	movq -32(%r10), %r9
	subq $1, %r9
	movq %r9, -880(%rbp)
	jnz .Lbb851
	movq -24(%r10), %r9
	movq %r9, -888(%rbp)
	movq -880(%rbp), %r9
	cmpq $0, -888(%rbp)
	jnz .Lbb851
	.loc 1 1290
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %r15, %rsi
	movq %r13, %rdi
	movq %rsi, %r15
	movq -3768(%rbp), %rsi
	movl -900(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -896(%rbp), %r11
	movq -3648(%rbp), %rdx
	jmp .Lbb854
.Lbb851:
	movq %r13, %rsi
	movq %r9, -32(%r10)
	jmp .Lbb853
.Lbb852:
	movq %r13, %rsi
.Lbb853:
	movq $0, -6136(%rbp)
.Lbb854:
	movq -6128(%rbp), %r10
	cmpq $0, %r10
	jnz .Lbb856
	movl %r14d, %r13d
	movq %r15, %rsi
	jmp .Lbb864
.Lbb856:
	movq -16(%r10), %r9
	movq $4611686018427387906, %r13
	andq %r13, %r9
	cmpq $0, %r9
	jnz .Lbb862
	movq -32(%r10), %r9
	subq $1, %r9
	jz .Lbb859
	movl %r14d, %r13d
	jmp .Lbb861
.Lbb859:
	movl %r14d, %r13d
	movq -24(%r10), %r14
	cmpq $0, %r14
	jnz .Lbb861
	.loc 1 1290
	movq %rsi, %r8
	movq %rdi, %r14
	movq %rbx, %rdi
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %r15, %rsi
	movq %r14, %rdi
	movl -900(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -896(%rbp), %r11
	movq -3648(%rbp), %rdx
	jmp .Lbb864
.Lbb861:
	movq %r15, %rsi
	movq %r9, -32(%r10)
	jmp .Lbb863
.Lbb862:
	movl %r14d, %r13d
	movq %r15, %rsi
.Lbb863:
	movq $0, -6128(%rbp)
.Lbb864:
	movq $0, -6144(%rbp)
	movq $0, -6136(%rbp)
	movq $0, -6128(%rbp)
	movq $0, -6120(%rbp)
	movq $0, -6112(%rbp)
	jmp .Lbb867
.Lbb865:
	movl %r14d, %r13d
	movq %r15, %rsi
	.loc 1 1290
	movq %rsi, %r15
	leaq -6144(%rbp), %rsi
	movq %rdi, %r14
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r15, %rsi
	movq %r14, %rdi
	movl -900(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -896(%rbp), %r11
	movq -3648(%rbp), %rdx
.Lbb867:
	movq -6392(%rbp), %r9
	movq %r9, -6144(%rbp)
	movq -6384(%rbp), %r9
	movq %r9, -6136(%rbp)
	movq -6376(%rbp), %r9
	movq %r9, -6128(%rbp)
	movq -6368(%rbp), %r9
	movq %r9, -6120(%rbp)
	movq -6360(%rbp), %r9
	movq %r9, -6112(%rbp)
	movl $1, %r15d
	movl $2, %r14d
	movl $0, %r10d
	movl $2, %r9d
.Lbb869:
	xchgl %r15d, %r13d
	xchgl %r12d, %r15d
	xchgl %r14d, %r12d
	jmp .Lbb2674
.Lbb870:
	xchgq %rbx, %rdi
	.loc 1 1290
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 1290
	callq myl_qbe_rc_status
	jmp .Lbb2692
.Lbb872:
	.loc 1 1288
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb873:
	movq %r9, %rcx
	movq %r10, %rsi
	.loc 1 1285
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb875:
	movq %r10, %rsi
	.loc 1 1283
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb877:
	.loc 1 1276
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb878:
	movq %r11, %rdx
	.loc 1 1257
	movq %r10, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb880:
	movq %r12, %rdx
	.loc 1 1251
	movq %r10, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb882:
	movq %r12, %rdx
	.loc 1 1248
	movq %r10, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb884:
	movq %r12, %rcx
	movq %r13, %rsi
	.loc 1 1243
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb886:
	movq %r13, %rsi
	.loc 1 1241
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb888:
	movq %r10, %rdx
	.loc 1 1234
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	movq %rdi, %rbx
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb890:
	xchgl %r14d, %r15d
	.loc 1 1144
	movq %rsi, %r13
	leaq -6144(%rbp), %rsi
	movq %rdi, %r12
	callq myl_f_fa0a495025828a635f8203a4c546663c235c2574b972f1294569bb6fadb2fcc2
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, %r8
	movl -3588(%rbp), %r12d
	movq -3704(%rbp), %r11
	movq %r8, -936(%rbp)
	cmpl $0, %r15d
	jnz .Lbb893
	movl %r15d, %r10d
	movl %r12d, %r15d
	jmp .Lbb899
.Lbb893:
	movl %r12d, %r15d
	testl $28, %r14d
	jnz .Lbb897
	.loc 1 1144
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -936(%rbp), %r8
	movq -3704(%rbp), %r11
	movl $0, %r10d
	jmp .Lbb899
.Lbb897:
	.loc 1 1144
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -936(%rbp), %r8
	movq -3704(%rbp), %r11
	movl $0, %r10d
.Lbb899:
	movq -6120(%rbp), %rdx
	movq %rdx, -912(%rbp)
	cmpl $0, %r10d
	jz .Lbb905
	testl $28, %r14d
	jnz .Lbb903
	.loc 1 1147
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -912(%rbp), %rdx
	movq -936(%rbp), %r8
	movq -3704(%rbp), %r11
	movl $0, %r10d
	jmp .Lbb905
.Lbb903:
	.loc 1 1147
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -912(%rbp), %rdx
	movq -936(%rbp), %r8
	movq -3704(%rbp), %r11
	movl $0, %r10d
.Lbb905:
	cmpl $0, %r10d
	jnz .Lbb907
	movl %r14d, %r9d
	jmp .Lbb912
.Lbb907:
	testl $28, %r14d
	jnz .Lbb910
	.loc 1 1150
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -912(%rbp), %rdx
	movq -936(%rbp), %r8
	movq -3704(%rbp), %r11
	movl %r14d, %r9d
	movl $0, %r10d
	jmp .Lbb912
.Lbb910:
	.loc 1 1150
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -912(%rbp), %rdx
	movq -936(%rbp), %r8
	movq -3704(%rbp), %r11
	movl $0, %r10d
.Lbb912:
	cmpl $0, %r10d
	jz .Lbb932
	testl $28, %r9d
	jnz .Lbb923
	movq -7016(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb922
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r10
	andq %r10, %rax
	cmpq $0, %rax
	jnz .Lbb921
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb920
	movl %r9d, %r14d
	movq -24(%rcx), %r9
	cmpq $0, %r9
	jnz .Lbb919
	.loc 1 1151
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -912(%rbp), %rdx
	movq -936(%rbp), %r8
	movq -3704(%rbp), %r11
	jmp .Lbb922
.Lbb919:
	movl %r14d, %r9d
.Lbb920:
	movq %rax, -32(%rcx)
.Lbb921:
	movq $0, -7016(%rbp)
.Lbb922:
	movl $0, %r10d
	jmp .Lbb932
.Lbb923:
	movq -7016(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb931
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r10
	andq %r10, %rax
	cmpq $0, %rax
	jnz .Lbb930
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb929
	movl %r9d, %r14d
	movq -32(%rcx), %r9
	cmpq $0, %r9
	jnz .Lbb928
	.loc 1 1151
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -912(%rbp), %rdx
	movq -936(%rbp), %r8
	movq -3704(%rbp), %r11
	jmp .Lbb931
.Lbb928:
	movl %r14d, %r9d
.Lbb929:
	movq %rax, -24(%rcx)
.Lbb930:
	movq $0, -7016(%rbp)
.Lbb931:
	movl $0, %r10d
.Lbb932:
	movl %r10d, -904(%rbp)
	movq 136(%rsi), %rax
	cmpq $0, %rax
	jz .Lbb937
	movq -16(%rax), %rcx
	movl %r9d, %r14d
	movq $6917529027641081858, %r9
	andq %r9, %rcx
	cmpq $0, %rcx
	jnz .Lbb936
	movq -32(%rax), %rax
	cmpq $2, %rax
	jae .Lbb936
	movl %r14d, %r9d
	jmp .Lbb937
.Lbb936:
	.loc 1 1151
	movl $0, %ecx
	movq %r11, %rdx
	movq %rsi, %r13
	movq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	callq myl_qbe_rc_unique_field
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -904(%rbp), %r10d
	movq -912(%rbp), %rdx
	movq -936(%rbp), %r8
	cmpl $0, %eax
	jz .Lbb2692
.Lbb937:
	movq 136(%rsi), %rax
	movq %rax, -928(%rbp)
	movl %r9d, %r14d
	movq 144(%rsi), %r9
	movq %r9, -920(%rbp)
	cmpl $0, %r10d
	jnz .Lbb939
	movl %r10d, -956(%rbp)
	jmp .Lbb944
.Lbb939:
	testl $28, %r14d
	jnz .Lbb942
	.loc 1 1153
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl %r9d, %r14d
	movq -920(%rbp), %r9
	movq -928(%rbp), %rax
	movq -912(%rbp), %rdx
	movq -936(%rbp), %r8
	movl $0, -956(%rbp)
	jmp .Lbb944
.Lbb942:
	.loc 1 1153
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl %r9d, %r14d
	movq -920(%rbp), %r9
	movq -928(%rbp), %rax
	movq -912(%rbp), %rdx
	movq -936(%rbp), %r8
	movl $0, -956(%rbp)
.Lbb944:
	movq $-9223372036854775807, %rcx
	cmpq %rcx, %r9
	jl .Lbb1058
	subq $1, %r9
	cmpq $0, %r9
	jge .Lbb948
	movq (%rax), %r10
	movq $9223372036854775807, %rcx
	cmpq %rcx, %r10
	ja .Lbb1056
	movq %r9, %rcx
	addq %r10, %r9
	movq %r10, %r11
	xorq %r9, %r11
	movq %rcx, %r12
	xorq %r9, %r12
	andq %r12, %r11
	cmpq $0, %r11
	jl .Lbb1054
.Lbb948:
	movq (%rax), %rcx
	cmpq %rcx, %r9
	jae .Lbb1052
	movq 32(%rax), %r10
	imulq $24, %r9, %rcx
	movq 0(%r10, %rcx, 1), %r11
	movq %r11, -5816(%rbp)
	movq 8(%r10, %rcx, 1), %r11
	movq %r11, -5808(%rbp)
	movq 16(%r10, %rcx, 1), %r10
	movq %r10, -5800(%rbp)
	movq (%rax), %r10
	cmpq %r10, %r9
	jae .Lbb1050
	movq 32(%rax), %r10
	movq 0(%rcx, %r10, 1), %r11
	movq %r11, -5816(%rbp)
	movq 8(%rcx, %r10, 1), %r11
	movq %r11, -5808(%rbp)
	movq 16(%rcx, %r10, 1), %r10
	movq %r10, -5800(%rbp)
	movq -5816(%rbp), %r10
	movq %r10, -4824(%rbp)
	movq -5808(%rbp), %r10
	movq %r10, -4816(%rbp)
	movq -5800(%rbp), %r10
	movq %r10, -4808(%rbp)
	movq %rdx, -4816(%rbp)
	movq (%rax), %rdx
	cmpq %rdx, %r9
	jae .Lbb1049
	movq 32(%rax), %rdx
	movq -4824(%rbp), %rax
	movq %rax, 0(%rcx, %rdx, 1)
	movq -4816(%rbp), %rax
	movq %rax, 8(%rcx, %rdx, 1)
	movq -4808(%rbp), %rax
	movq %rax, 16(%rcx, %rdx, 1)
	movq 0(%rsi), %rax
	movq %rax, -4800(%rbp)
	movq 8(%rsi), %rax
	movq %rax, -4792(%rbp)
	movq 16(%rsi), %rax
	movq %rax, -4784(%rbp)
	movq 24(%rsi), %rax
	movq %rax, -4776(%rbp)
	movq 32(%rsi), %rax
	movq %rax, -4768(%rbp)
	movq 40(%rsi), %rax
	movq %rax, -4760(%rbp)
	movq 48(%rsi), %rax
	movq %rax, -4752(%rbp)
	movq 56(%rsi), %rax
	movq %rax, -4744(%rbp)
	movq 64(%rsi), %rax
	movq %rax, -4736(%rbp)
	movq 72(%rsi), %rax
	movq %rax, -4728(%rbp)
	movq 80(%rsi), %rax
	movq %rax, -4720(%rbp)
	movq 88(%rsi), %rax
	movq %rax, -4712(%rbp)
	movq 96(%rsi), %rax
	movq %rax, -4704(%rbp)
	movq 104(%rsi), %rax
	movq %rax, -4696(%rbp)
	movq 112(%rsi), %rax
	movq %rax, -4688(%rbp)
	movq 120(%rsi), %rax
	movq %rax, -4680(%rbp)
	movq 128(%rsi), %rax
	movq %rax, -4672(%rbp)
	movq 136(%rsi), %rax
	movq %rax, -4664(%rbp)
	movq 144(%rsi), %rax
	movq %rax, -4656(%rbp)
	movq 152(%rsi), %rax
	movq %rax, -4648(%rbp)
	movq 160(%rsi), %rax
	movq %rax, -4640(%rbp)
	movq 168(%rsi), %rax
	movq %rax, -4632(%rbp)
	movq 176(%rsi), %rax
	movq %rax, -4624(%rbp)
	movq 184(%rsi), %rax
	movq %rax, -4616(%rbp)
	movq 192(%rsi), %rax
	movq %rax, -4608(%rbp)
	movq 200(%rsi), %rax
	movq %rax, -4600(%rbp)
	.loc 1 1186
	movq %r8, %rdx
	movq %rsi, %r13
	leaq -4800(%rbp), %rsi
	movq %rdi, %r12
	callq myl_f_851eb64c403b25f3166dffdb17dfc9e3c924451c20caa5851a74e0f4081ba50f
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, %r9
	movq %rdx, %rax
	movl -3672(%rbp), %ecx
	movl -3676(%rbp), %r13d
	movq -936(%rbp), %r8
	movq -3648(%rbp), %rdx
	movq %r9, -7216(%rbp)
	movq %rax, -7208(%rbp)
	cmpl $0, %ecx
	jnz .Lbb953
	movl %ecx, -1132(%rbp)
	jmp .Lbb958
.Lbb953:
	testl $28, %r13d
	jnz .Lbb956
	.loc 1 1186
	movq %rsi, %r13
	leaq -6600(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -936(%rbp), %r8
	movq -3648(%rbp), %rdx
	movl $0, -1132(%rbp)
	jmp .Lbb958
.Lbb956:
	.loc 1 1186
	movq %rsi, %r13
	leaq -6600(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -936(%rbp), %r8
	movq -3648(%rbp), %rdx
	movl $0, -1132(%rbp)
.Lbb958:
	.loc 1 1188
	leaq -7216(%rbp), %rcx
	movq %rsi, %r13
	movq %rdi, %r12
	callq myl_f_38b1eb8969d1be311bbb44d1b412311bcad6afc3cbe33e5e0c18ebf16300ae5f
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, -1096(%rbp)
	movl -1132(%rbp), %ecx
	movl -956(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl %r13d, %r9d
	movl -3676(%rbp), %r13d
	movq -3656(%rbp), %rax
	movl %ecx, %r11d
	movq -3808(%rbp), %rcx
	movq -3648(%rbp), %rdx
	cmpl $0, %r10d
	jnz .Lbb960
	xchgl %r9d, %r10d
	jmp .Lbb965
.Lbb960:
	testl $28, %r14d
	jnz .Lbb963
	.loc 1 1188
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movl -1132(%rbp), %ecx
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl %r13d, %r9d
	movl -3676(%rbp), %r13d
	movq -3656(%rbp), %rax
	movl %ecx, %r10d
	movq -3808(%rbp), %rcx
	movq -3648(%rbp), %rdx
	movl %r10d, %r11d
	movl %r9d, %r10d
	movl $0, %r9d
	jmp .Lbb965
.Lbb963:
	.loc 1 1188
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movl -1132(%rbp), %ecx
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl %r13d, %r10d
	movl -3676(%rbp), %r13d
	movq -3656(%rbp), %rax
	movl %ecx, %r11d
	movq -3808(%rbp), %rcx
	movq -3648(%rbp), %rdx
	movl $0, %r9d
.Lbb965:
	movl %r9d, -960(%rbp)
	cmpl $0, %r8d
	jz .Lbb971
	testl $28, %r15d
	jnz .Lbb969
	.loc 1 1188
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_3ece1c6f770ecd2a506fa806688c97e383087567b3626d4a9ce4529758a6df1f_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl %r9d, %r14d
	movl -960(%rbp), %r9d
	movl -1132(%rbp), %ecx
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl %r13d, %r8d
	movl -3676(%rbp), %r13d
	movq -3656(%rbp), %rax
	movl %ecx, %r10d
	movq -3808(%rbp), %rcx
	movq -3648(%rbp), %rdx
	movl %r10d, %r11d
	movl %r8d, %r10d
	movl $0, %r8d
	jmp .Lbb971
.Lbb969:
	.loc 1 1188
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_3ece1c6f770ecd2a506fa806688c97e383087567b3626d4a9ce4529758a6df1f_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl %r9d, %r14d
	movl -960(%rbp), %r9d
	movl -1132(%rbp), %ecx
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl %r13d, %r10d
	movl -3676(%rbp), %r13d
	movq -3656(%rbp), %rax
	movl %ecx, %r11d
	movq -3808(%rbp), %rcx
	movq -3648(%rbp), %rdx
	movl $0, %r8d
.Lbb971:
	cmpl $0, -1096(%rbp)
	jnz .Lbb973
	movl %r11d, %ecx
	movq -1096(%rbp), %r11
	xchgl %r13d, %r9d
	xchgl %r10d, %r13d
	xchgl %r15d, %r10d
	jmp .Lbb1040
.Lbb973:
	movq 136(%rsi), %rax
	movq %rax, -952(%rbp)
	cmpl $0, %r8d
	jz .Lbb979
	testl $28, %r15d
	jnz .Lbb977
	.loc 1 1194
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3808(%rbp), %rcx
	movq -952(%rbp), %rax
	movl $0, %r8d
	jmp .Lbb979
.Lbb977:
	.loc 1 1194
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3808(%rbp), %rcx
	movq -952(%rbp), %rax
	movl $0, %r8d
.Lbb979:
	movq 144(%rsi), %rdx
	movq %rdx, -944(%rbp)
	cmpl $0, %r8d
	jnz .Lbb981
	movl %r8d, -1104(%rbp)
	jmp .Lbb986
.Lbb981:
	testl $28, %r15d
	jnz .Lbb984
	.loc 1 1197
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3808(%rbp), %rcx
	movq -944(%rbp), %rdx
	movq -952(%rbp), %rax
	movl $0, -1104(%rbp)
	jmp .Lbb986
.Lbb984:
	.loc 1 1197
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3808(%rbp), %rcx
	movq -944(%rbp), %rdx
	movq -952(%rbp), %rax
	movl $0, -1104(%rbp)
.Lbb986:
	movq $-9223372036854775807, %r8
	cmpq %r8, %rdx
	jl .Lbb1048
	movq %rsi, %r13
	movq %rdx, %rsi
	subq $1, %rsi
	cmpq $0, %rsi
	jge .Lbb990
	movq (%rax), %r10
	movq $9223372036854775807, %rdx
	cmpq %rdx, %r10
	ja .Lbb1046
	movq %rsi, %r9
	addq %r10, %rsi
	movq %r10, %rdx
	xorq %rsi, %rdx
	movq %r9, %r8
	xorq %rsi, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jl .Lbb1044
.Lbb990:
	movq (%rax), %rdx
	cmpq %rdx, %rsi
	jae .Lbb1043
	movq 32(%rax), %rax
	imulq $24, %rsi, %rdx
	movq 0(%rax, %rdx, 1), %rsi
	movq %rsi, 0(%rcx)
	movq 8(%rax, %rdx, 1), %rsi
	movq %rsi, 8(%rcx)
	movq 16(%rax, %rdx, 1), %rax
	movq %rax, 16(%rcx)
	.loc 1 1212
	movq %r13, %rdx
	movq %rdi, %rsi
	movq %rdi, %r12
	leaq -7200(%rbp), %rdi
	callq myl_f_bf0431d3d9e553eacefcb10ebb00251bb8b43354cc87fd12c99ceb5644f705d6
	movl %r14d, %r9d
	movq %r12, %rdi
	movq %rax, %r8
	movl -960(%rbp), %r10d
	movl %r10d, %r11d
	movl -3664(%rbp), %r10d
	movl -3668(%rbp), %r12d
	movl -3676(%rbp), %r14d
	movq -3656(%rbp), %rax
	movq -3816(%rbp), %rcx
	movq -3648(%rbp), %rdx
	movq 0(%r8), %rsi
	movq %rsi, -6392(%rbp)
	movq 8(%r8), %rsi
	movq %rsi, -6384(%rbp)
	movq 16(%r8), %rsi
	movq %rsi, -6376(%rbp)
	movq 24(%r8), %rsi
	movq %rsi, -6368(%rbp)
	movq -3776(%rbp), %rsi
	movq 32(%r8), %r8
	movq %r8, -6360(%rbp)
	movq -3768(%rbp), %r8
	cmpl $0, %r11d
	movl -1132(%rbp), %r11d
	jnz .Lbb993
	movl %r12d, %r9d
	movq %r8, %r12
	jmp .Lbb997
.Lbb993:
	testl $28, %r9d
	jnz .Lbb996
	.loc 1 1212
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r12, %rdi
	movq -3768(%rbp), %rsi
	movq %rsi, %r8
	movq -3776(%rbp), %rsi
	movl -1132(%rbp), %ecx
	movl -3664(%rbp), %r10d
	movl -3668(%rbp), %r9d
	movq -3656(%rbp), %rax
	movl %ecx, %r11d
	movq -3816(%rbp), %rcx
	movq -3648(%rbp), %rdx
	movq %r8, %r12
	jmp .Lbb997
.Lbb996:
	.loc 1 1212
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r12, %rdi
	movq -3768(%rbp), %rsi
	movq %rsi, %r12
	movq -3776(%rbp), %rsi
	movl -1132(%rbp), %ecx
	movl -3664(%rbp), %r10d
	movl -3668(%rbp), %r9d
	movq -3656(%rbp), %rax
	movl %ecx, %r11d
	movq -3816(%rbp), %rcx
	movq -3648(%rbp), %rdx
.Lbb997:
	movq -6392(%rbp), %r8
	movq %r8, -7016(%rbp)
	movq -6384(%rbp), %r8
	movq %r8, -7008(%rbp)
	movq -6376(%rbp), %r8
	movq %r8, -7000(%rbp)
	movq -6368(%rbp), %r8
	movq %r8, -6992(%rbp)
	movq -6360(%rbp), %r8
	movq %r8, -6984(%rbp)
	movq -7016(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb999
	movq -16(%r8), %r8
	movq %r8, -968(%rbp)
	movl -1132(%rbp), %r11d
	movq $5764607523034234881, %r8
	movq %r8, -976(%rbp)
	movq -968(%rbp), %r8
	andq -976(%rbp), %r8
	cmpq $0, %r8
	jnz .Lbb1005
.Lbb999:
	movq -7008(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb1001
	movq -16(%r8), %r8
	movq %r8, -984(%rbp)
	movl -1132(%rbp), %r11d
	movq $5764607523034234881, %r8
	movq %r8, -992(%rbp)
	movq -984(%rbp), %r8
	andq -992(%rbp), %r8
	cmpq $0, %r8
	jnz .Lbb1005
.Lbb1001:
	movq -7000(%rbp), %r8
	movq %r8, -1000(%rbp)
	movl -1104(%rbp), %r8d
	cmpq $0, -1000(%rbp)
	jz .Lbb1004
	movq -1000(%rbp), %r8
	movq -16(%r8), %r8
	movq %r8, -1016(%rbp)
	movl -1132(%rbp), %r11d
	movq $5764607523034234881, %r8
	movq %r8, -1008(%rbp)
	movq -1016(%rbp), %r8
	andq -1008(%rbp), %r8
	movq %r8, -1024(%rbp)
	movl -1104(%rbp), %r8d
	cmpq $0, -1024(%rbp)
	jnz .Lbb1005
.Lbb1004:
	movl %r11d, %ecx
	movq -7016(%rbp), %r11
	movq %r11, -6392(%rbp)
	movq -7008(%rbp), %r11
	movq %r11, -6384(%rbp)
	movq -7000(%rbp), %r11
	movq %r11, -6376(%rbp)
	movq -6992(%rbp), %r11
	movq %r11, -6368(%rbp)
	movq -6984(%rbp), %r11
	movq %r11, -6360(%rbp)
	movq -1096(%rbp), %r11
	movq $0, -7016(%rbp)
	movq $0, -7008(%rbp)
	movq $0, -7000(%rbp)
	movq $0, -6992(%rbp)
	movq $0, -6984(%rbp)
	jmp .Lbb1006
.Lbb1005:
	.loc 1 1213
	leaq -7016(%rbp), %rdx
	leaq -6392(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_take
	movq %r12, %rdi
	movl %eax, -1100(%rbp)
	movq -3768(%rbp), %rsi
	movq %rsi, %r12
	movq -3776(%rbp), %rsi
	movl -1104(%rbp), %r8d
	movl -1132(%rbp), %ecx
	movl -3664(%rbp), %r10d
	movl -3668(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -1096(%rbp), %r11
	movq -3648(%rbp), %rdx
	cmpl $0, -1100(%rbp)
	jz .Lbb1041
.Lbb1006:
	cmpl $0, %r10d
	jnz .Lbb1008
	movl %r15d, %r10d
	movl %r14d, %r9d
	movq %r13, %rsi
	jmp .Lbb1038
.Lbb1008:
	testl $28, %r9d
	jnz .Lbb1036
	movq -6144(%rbp), %r10
	cmpq $0, %r10
	jz .Lbb1016
	movq -16(%r10), %r9
	movq %r9, -1032(%rbp)
	movq $4611686018427387906, %r9
	movq %r9, -1040(%rbp)
	movq -1032(%rbp), %r9
	andq -1040(%rbp), %r9
	cmpq $0, %r9
	jnz .Lbb1015
	movq -32(%r10), %r9
	subq $1, %r9
	movq %r9, -1048(%rbp)
	jnz .Lbb1014
	movq -24(%r10), %r9
	movq %r9, -1056(%rbp)
	movq -1048(%rbp), %r9
	cmpq $0, -1056(%rbp)
	jnz .Lbb1014
	.loc 1 1213
	leaq -6144(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a_rcg_drop
	movq %r12, %rdi
	movq -3768(%rbp), %rsi
	movq %rsi, %r12
	movq -3776(%rbp), %rsi
	movl -1104(%rbp), %r8d
	movl -1132(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -1096(%rbp), %r11
	movq -3648(%rbp), %rdx
	jmp .Lbb1016
.Lbb1014:
	movq %r9, -32(%r10)
.Lbb1015:
	movq $0, -6144(%rbp)
.Lbb1016:
	movq -6136(%rbp), %r10
	cmpq $0, %r10
	jnz .Lbb1018
	movq %r12, %rsi
	jmp .Lbb1025
.Lbb1018:
	movq -16(%r10), %r9
	movq %r9, -1064(%rbp)
	movq $4611686018427387906, %r9
	movq %r9, -1072(%rbp)
	movq -1064(%rbp), %r9
	andq -1072(%rbp), %r9
	cmpq $0, %r9
	jnz .Lbb1023
	movq -32(%r10), %r9
	subq $1, %r9
	movq %r9, -1080(%rbp)
	jnz .Lbb1022
	movq -24(%r10), %r9
	movq %r9, -1088(%rbp)
	movq -1080(%rbp), %r9
	cmpq $0, -1088(%rbp)
	jnz .Lbb1022
	.loc 1 1213
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rsi, %r13
	movq -3768(%rbp), %rsi
	movl -1104(%rbp), %r8d
	movl -1132(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -1096(%rbp), %r11
	movq -3648(%rbp), %rdx
	jmp .Lbb1025
.Lbb1022:
	movq %r12, %rsi
	movq %r9, -32(%r10)
	jmp .Lbb1024
.Lbb1023:
	movq %r12, %rsi
.Lbb1024:
	movq $0, -6136(%rbp)
.Lbb1025:
	movq -6128(%rbp), %r10
	cmpq $0, %r10
	jnz .Lbb1027
	movq %r13, %rsi
	jmp .Lbb1034
.Lbb1027:
	movq -16(%r10), %r9
	movq $4611686018427387906, %r12
	andq %r12, %r9
	cmpq $0, %r9
	jnz .Lbb1032
	movq -32(%r10), %r9
	subq $1, %r9
	jnz .Lbb1031
	movq -24(%r10), %r12
	cmpq $0, %r12
	jnz .Lbb1031
	.loc 1 1213
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movl -1104(%rbp), %r8d
	movl -1132(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -1096(%rbp), %r11
	movq -3648(%rbp), %rdx
	jmp .Lbb1034
.Lbb1031:
	movq %r13, %rsi
	movq %r9, -32(%r10)
	jmp .Lbb1033
.Lbb1032:
	movq %r13, %rsi
.Lbb1033:
	movq $0, -6128(%rbp)
.Lbb1034:
	movq $0, -6144(%rbp)
	movq $0, -6136(%rbp)
	movq $0, -6128(%rbp)
	movq $0, -6120(%rbp)
	movq $0, -6112(%rbp)
	movl %r15d, %r10d
	movl %r14d, %r9d
	jmp .Lbb1038
.Lbb1036:
	movq %r13, %rsi
	.loc 1 1213
	movq %rsi, %r13
	leaq -6144(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movl %r15d, %r10d
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -1104(%rbp), %r8d
	movl -1132(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -1096(%rbp), %r11
	movq -3648(%rbp), %rdx
.Lbb1038:
	movq -6392(%rbp), %r12
	movq %r12, -6144(%rbp)
	movq -6384(%rbp), %r12
	movq %r12, -6136(%rbp)
	movq -6376(%rbp), %r12
	movq %r12, -6128(%rbp)
	movq -6368(%rbp), %r12
	movq %r12, -6120(%rbp)
	movq -6360(%rbp), %r12
	movq %r12, -6112(%rbp)
	movl $1, %r13d
	movl $2, %r12d
	movl $0, %r15d
	movl $2, %r14d
.Lbb1040:
	xchgl %r15d, %r10d
	xchgl %r14d, %r9d
	jmp .Lbb2674
.Lbb1041:
	xchgq %rbx, %rdi
	.loc 1 1213
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 1213
	callq myl_qbe_rc_status
	jmp .Lbb2692
.Lbb1043:
	.loc 1 1211
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1044:
	movq %r9, %rcx
	movq %r10, %rsi
	.loc 1 1208
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1046:
	movq %r10, %rsi
	.loc 1 1206
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb1048:
	.loc 1 1199
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1049:
	.loc 1 1178
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1050:
	movq %r10, %rdx
	.loc 1 1172
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1052:
	movq %rcx, %rdx
	.loc 1 1169
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1054:
	movq %r10, %rsi
	.loc 1 1164
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1056:
	movq %r10, %rsi
	.loc 1 1162
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb1058:
	movq %r9, %rdx
	.loc 1 1155
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1060:
	xchgl %r14d, %r15d
	.loc 1 1121
	movq %rsi, %r13
	leaq -6144(%rbp), %rsi
	movq %rdi, %r12
	callq myl_f_22849c51a4fd631aa66144da38552fb710206c5e57b8268459a8dc3a6dbcd390
	movl %r15d, %r10d
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, -1160(%rbp)
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl %r10d, %r15d
	movl -3588(%rbp), %r10d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	cmpl $0, %r15d
	jnz .Lbb1063
	xchgl %r10d, %r15d
	jmp .Lbb1069
.Lbb1063:
	movl %r10d, %r15d
	testl $28, %r14d
	jnz .Lbb1067
	.loc 1 1121
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb1069
.Lbb1067:
	.loc 1 1121
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb1069:
	movq -6120(%rbp), %r11
	movq %r11, -1112(%rbp)
	cmpl $0, %r10d
	jnz .Lbb1071
	xchgl %r12d, %r15d
	movl %r10d, -1136(%rbp)
	jmp .Lbb1076
.Lbb1071:
	testl $28, %r14d
	jnz .Lbb1074
	.loc 1 1124
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -1112(%rbp), %r11
	movq -3648(%rbp), %rdx
	xchgl %r12d, %r15d
	movl $0, -1136(%rbp)
	jmp .Lbb1076
.Lbb1074:
	.loc 1 1124
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl %r15d, %r12d
	movl -3668(%rbp), %r15d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -1112(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, -1136(%rbp)
.Lbb1076:
	movq %r11, %r10
	subq -1160(%rbp), %r10
	movq %r10, -1152(%rbp)
	movq -1160(%rbp), %r10
	xorq %r11, %r10
	movq %r10, -1128(%rbp)
	movq %r11, %r10
	xorq -1152(%rbp), %r10
	movq %r10, -1120(%rbp)
	movq -1128(%rbp), %r10
	andq -1120(%rbp), %r10
	movq %r10, -1144(%rbp)
	movl -1136(%rbp), %r10d
	cmpq $0, -1144(%rbp)
	jl .Lbb1080
	movq -1152(%rbp), %r11
	movq %r11, -6120(%rbp)
	xchgl %r15d, %r12d
	xchgl %r14d, %r9d
	movl $1, %r11d
	jmp .Lbb2674
.Lbb1080:
	movq %r11, %rdx
	movq -1160(%rbp), %rcx
	.loc 1 1126
	movl $64, %r8d
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1082:
	xchgl %r14d, %r15d
	.loc 1 1082
	movq %rsi, %r13
	leaq -6144(%rbp), %rsi
	movq %rdi, %r12
	callq myl_f_22849c51a4fd631aa66144da38552fb710206c5e57b8268459a8dc3a6dbcd390
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, -1216(%rbp)
	movl -3588(%rbp), %r12d
	cmpl $0, %r15d
	jnz .Lbb1085
	movl %r15d, -1292(%rbp)
	movl %r12d, %r15d
	jmp .Lbb1091
.Lbb1085:
	movl %r12d, %r15d
	testl $28, %r14d
	jnz .Lbb1089
	.loc 1 1082
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movl $0, -1292(%rbp)
	jmp .Lbb1091
.Lbb1089:
	.loc 1 1082
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movl $0, -1292(%rbp)
.Lbb1091:
	.loc 1 1086
	movl $0, %edx
	movq %rsi, %r13
	movq %rdi, %r12
	callq myl_f_851eb64c403b25f3166dffdb17dfc9e3c924451c20caa5851a74e0f4081ba50f
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, %r11
	movq %rdx, -1168(%rbp)
	movl -1292(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movq %r11, -7232(%rbp)
	movq -1168(%rbp), %r11
	movq %r11, -7224(%rbp)
	cmpl $0, %r10d
	jz .Lbb1097
	testl $28, %r14d
	jnz .Lbb1095
	.loc 1 1086
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb1097
.Lbb1095:
	.loc 1 1086
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb1097:
	movq -7232(%rbp), %r11
	movq %r11, -5656(%rbp)
	movq -7224(%rbp), %r11
	movq %r11, -5648(%rbp)
	movl -5656(%rbp), %r11d
	cmpq $0, %r11
	jz .Lbb1104
	cmpq $1, %r11
	jz .Lbb1103
	cmpq $2, %r11
	jz .Lbb1102
	cmpq $3, %r11
	jnz .Lbb2692
	movl $0, %r11d
	jmp .Lbb1105
.Lbb1102:
	movl $0, %r11d
	jmp .Lbb1105
.Lbb1103:
	movzbq -5648(%rbp), %r11
	movb %r11b, -6392(%rbp)
	xorq $1, %r11
	jmp .Lbb1105
.Lbb1104:
	movl $1, %r11d
.Lbb1105:
	cmpl $0, %r11d
	jnz .Lbb1107
	xchgl %r15d, %r10d
	jmp .Lbb1116
.Lbb1107:
	movq -6120(%rbp), %r11
	movq %r11, -1208(%rbp)
	cmpl $0, %r10d
	jnz .Lbb1109
	xchgl %r15d, %r10d
	jmp .Lbb1114
.Lbb1109:
	testl $28, %r14d
	jnz .Lbb1112
	.loc 1 1101
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl %r15d, %r10d
	movl $0, %r15d
	jmp .Lbb1114
.Lbb1112:
	.loc 1 1101
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movl %r15d, %r10d
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r15d
.Lbb1114:
	movq -1216(%rbp), %r11
	addq -1208(%rbp), %r11
	movq %r11, -1192(%rbp)
	movq -1208(%rbp), %r11
	xorq -1192(%rbp), %r11
	movq %r11, -1184(%rbp)
	movq -1216(%rbp), %r11
	xorq -1192(%rbp), %r11
	movq %r11, -1176(%rbp)
	movq -1184(%rbp), %r11
	andq -1176(%rbp), %r11
	movq %r11, -1200(%rbp)
	movq -1192(%rbp), %r11
	cmpq $0, -1200(%rbp)
	jl .Lbb1117
	movq %r11, -6120(%rbp)
.Lbb1116:
	xchgl %r15d, %r10d
	xchgl %r14d, %r9d
	movl $1, %r11d
	jmp .Lbb2674
.Lbb1117:
	movq -1208(%rbp), %rdx
	movq -1216(%rbp), %rcx
	.loc 1 1103
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1119:
	xchgl %r14d, %r15d
	.loc 1 1059
	movq %rsi, %r13
	leaq -6144(%rbp), %rsi
	movq %rdi, %r12
	callq myl_f_22849c51a4fd631aa66144da38552fb710206c5e57b8268459a8dc3a6dbcd390
	movl %r15d, %r10d
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, -1264(%rbp)
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl %r10d, %r15d
	movl -3588(%rbp), %r10d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	cmpl $0, %r15d
	jnz .Lbb1122
	xchgl %r10d, %r15d
	jmp .Lbb1128
.Lbb1122:
	movl %r10d, %r15d
	testl $28, %r14d
	jnz .Lbb1126
	.loc 1 1059
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb1128
.Lbb1126:
	.loc 1 1059
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb1128:
	movq -6120(%rbp), %r11
	movq %r11, -1256(%rbp)
	cmpl $0, %r10d
	jnz .Lbb1130
	xchgl %r12d, %r15d
	jmp .Lbb1135
.Lbb1130:
	testl $28, %r14d
	jnz .Lbb1133
	.loc 1 1062
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	xchgl %r12d, %r15d
	movl $0, %r10d
	jmp .Lbb1135
.Lbb1133:
	.loc 1 1062
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl %r15d, %r12d
	movl -3668(%rbp), %r15d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb1135:
	movq -1264(%rbp), %r11
	addq -1256(%rbp), %r11
	movq %r11, -1240(%rbp)
	movq -1256(%rbp), %r11
	xorq -1240(%rbp), %r11
	movq %r11, -1232(%rbp)
	movq -1264(%rbp), %r11
	xorq -1240(%rbp), %r11
	movq %r11, -1224(%rbp)
	movq -1232(%rbp), %r11
	andq -1224(%rbp), %r11
	movq %r11, -1248(%rbp)
	movq -1240(%rbp), %r11
	cmpq $0, -1248(%rbp)
	jl .Lbb1138
	movq %r11, -6120(%rbp)
	xchgl %r15d, %r12d
	xchgl %r14d, %r9d
	movl $1, %r11d
	jmp .Lbb2674
.Lbb1138:
	movq -1256(%rbp), %rdx
	movq -1264(%rbp), %rcx
	.loc 1 1064
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1140:
	xchgl %r14d, %r15d
	movl %r10d, %r9d
	movq -3744(%rbp), %r8
	movq 128(%rsi), %rax
	movq %rax, -1272(%rbp)
	cmpl $0, %r15d
	jnz .Lbb1143
	movl %r15d, -1296(%rbp)
	movl %r12d, %r15d
	jmp .Lbb1149
.Lbb1143:
	movl %r12d, %r15d
	testl $28, %r14d
	jnz .Lbb1147
	.loc 1 1018
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3744(%rbp), %r8
	movq -1272(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, -1296(%rbp)
	jmp .Lbb1149
.Lbb1147:
	.loc 1 1018
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3744(%rbp), %r8
	movq -1272(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, -1296(%rbp)
.Lbb1149:
	movq $-9223372036854775807, %r10
	cmpq %r10, %rax
	jl .Lbb1188
	subq $1, %rax
	movq %rax, 128(%rsi)
	movq 0(%rsi), %rax
	movq %rax, -5032(%rbp)
	movq 8(%rsi), %rax
	movq %rax, -5024(%rbp)
	movq 16(%rsi), %rax
	movq %rax, -5016(%rbp)
	movq 24(%rsi), %rax
	movq %rax, -5008(%rbp)
	movq 32(%rsi), %rax
	movq %rax, -5000(%rbp)
	movq 40(%rsi), %rax
	movq %rax, -4992(%rbp)
	movq 48(%rsi), %rax
	movq %rax, -4984(%rbp)
	movq 56(%rsi), %rax
	movq %rax, -4976(%rbp)
	movq 64(%rsi), %rax
	movq %rax, -4968(%rbp)
	movq 72(%rsi), %rax
	movq %rax, -4960(%rbp)
	movq 80(%rsi), %rax
	movq %rax, -4952(%rbp)
	movq 88(%rsi), %rax
	movq %rax, -4944(%rbp)
	movq 96(%rsi), %rax
	movq %rax, -4936(%rbp)
	movq 104(%rsi), %rax
	movq %rax, -4928(%rbp)
	movq 112(%rsi), %rax
	movq %rax, -4920(%rbp)
	movq 120(%rsi), %rax
	movq %rax, -4912(%rbp)
	movq 128(%rsi), %rax
	movq %rax, -4904(%rbp)
	movq 136(%rsi), %rax
	movq %rax, -4896(%rbp)
	movq 144(%rsi), %rax
	movq %rax, -4888(%rbp)
	movq 152(%rsi), %rax
	movq %rax, -4880(%rbp)
	movq 160(%rsi), %rax
	movq %rax, -4872(%rbp)
	movq 168(%rsi), %rax
	movq %rax, -4864(%rbp)
	movq 176(%rsi), %rax
	movq %rax, -4856(%rbp)
	movq 184(%rsi), %rax
	movq %rax, -4848(%rbp)
	movq 192(%rsi), %rax
	movq %rax, -4840(%rbp)
	movq 200(%rsi), %rax
	movq %rax, -4832(%rbp)
	movq 120(%rsi), %rax
	movq %rax, -1280(%rbp)
	cmpl $0, %ecx
	jnz .Lbb1152
	xchgq %r8, %rcx
	jmp .Lbb1157
.Lbb1152:
	testl $28, %r9d
	jnz .Lbb1155
	.loc 1 1035
	movq %rsi, %r13
	leaq -6600(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3744(%rbp), %rcx
	movq -1280(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r8d
	jmp .Lbb1157
.Lbb1155:
	.loc 1 1035
	movq %rsi, %r13
	leaq -6600(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3744(%rbp), %rcx
	movq -1280(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r8d
.Lbb1157:
	movq 128(%rsi), %r10
	movq %r10, -1288(%rbp)
	cmpl $0, %r8d
	jnz .Lbb1159
	movl %r14d, %r9d
	movl %r8d, -1304(%rbp)
	jmp .Lbb1164
.Lbb1159:
	testl $28, %r9d
	jnz .Lbb1162
	.loc 1 1038
	movq %rsi, %r13
	leaq -6600(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3744(%rbp), %rcx
	movq -1288(%rbp), %r10
	movq -1280(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl %r14d, %r9d
	movl $0, -1304(%rbp)
	jmp .Lbb1164
.Lbb1162:
	.loc 1 1038
	movq %rsi, %r13
	leaq -6600(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3744(%rbp), %rcx
	movq -1288(%rbp), %r10
	movq -1280(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, -1304(%rbp)
.Lbb1164:
	cmpq $0, %r10
	jge .Lbb1167
	movq (%rax), %r12
	movq $9223372036854775807, %r8
	cmpq %r8, %r12
	ja .Lbb1186
	movq %r10, %r11
	addq %r12, %r10
	movq %r12, %r8
	xorq %r10, %r8
	movq %r11, %r13
	xorq %r10, %r13
	andq %r13, %r8
	cmpq $0, %r8
	jl .Lbb1184
.Lbb1167:
	movq (%rax), %r8
	cmpq %r8, %r10
	jae .Lbb1182
	movq 32(%rax), %rax
	imulq $16, %r10, %r8
	movl %r9d, %r14d
	movq 0(%rax, %r8, 1), %r9
	movq %r9, 0(%rcx)
	movq 8(%rax, %r8, 1), %rax
	movq %rax, 8(%rcx)
	.loc 1 1051
	movq %rsi, %r13
	leaq -5032(%rbp), %rsi
	movq %rdi, %r12
	callq myl_f_a931877b11ea3aa7de37854bbbc13e6f0160c87ee24000d47530697609fa185a
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -1304(%rbp), %ecx
	movl -1296(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	cmpl $0, %r10d
	jz .Lbb1174
	testl $28, %r14d
	jnz .Lbb1172
	.loc 1 1051
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -1304(%rbp), %ecx
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb1174
.Lbb1172:
	.loc 1 1051
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -1304(%rbp), %ecx
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb1174:
	movl %r10d, -1300(%rbp)
	cmpl $0, %r8d
	jnz .Lbb1176
	xchgl %r12d, %r15d
	jmp .Lbb1181
.Lbb1176:
	testl $28, %r15d
	jnz .Lbb1179
	.loc 1 1051
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_3ece1c6f770ecd2a506fa806688c97e383087567b3626d4a9ce4529758a6df1f_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -1300(%rbp), %r10d
	movl -1304(%rbp), %ecx
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	xchgl %r12d, %r15d
	movl $0, %r8d
	jmp .Lbb1181
.Lbb1179:
	.loc 1 1051
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_3ece1c6f770ecd2a506fa806688c97e383087567b3626d4a9ce4529758a6df1f_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -1300(%rbp), %r10d
	movl -1304(%rbp), %ecx
	movl -3664(%rbp), %r13d
	movl %r15d, %r12d
	movl -3668(%rbp), %r15d
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r8d
.Lbb1181:
	xchgl %r15d, %r12d
	xchgl %r14d, %r9d
	movl $1, %r11d
	jmp .Lbb2674
.Lbb1182:
	movq %r8, %rdx
	.loc 1 1050
	movq %r10, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1184:
	movq %r12, %rsi
	movq %r11, %rcx
	.loc 1 1047
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1186:
	movq %r12, %rsi
	.loc 1 1045
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb1188:
	movq %rax, %rdx
	.loc 1 1020
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1190:
	movq -2400(%rbp), %r8
	xchgl %r14d, %r15d
	movq -3704(%rbp), %r11
	cmpl $0, %r15d
	jnz .Lbb1193
	movl %r15d, %r10d
	movl %r12d, %r15d
	jmp .Lbb1199
.Lbb1193:
	movl %r12d, %r15d
	testl $28, %r14d
	jnz .Lbb1197
	.loc 1 973
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb1199
.Lbb1197:
	.loc 1 973
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb1199:
	cmpl $0, %r10d
	jnz .Lbb1201
	movl %r14d, %r9d
	jmp .Lbb1206
.Lbb1201:
	testl $28, %r14d
	jnz .Lbb1204
	.loc 1 976
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl %r14d, %r9d
	movl $0, %r10d
	jmp .Lbb1206
.Lbb1204:
	.loc 1 976
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb1206:
	cmpl $0, %r10d
	jz .Lbb1226
	testl $28, %r9d
	jnz .Lbb1217
	movq -7016(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1216
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r10
	andq %r10, %rax
	cmpq $0, %rax
	jnz .Lbb1215
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1214
	movl %r9d, %r14d
	movq -24(%rcx), %r9
	cmpq $0, %r9
	jnz .Lbb1213
	.loc 1 977
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	jmp .Lbb1216
.Lbb1213:
	movl %r14d, %r9d
.Lbb1214:
	movq %rax, -32(%rcx)
.Lbb1215:
	movq $0, -7016(%rbp)
.Lbb1216:
	movl $0, %r10d
	jmp .Lbb1226
.Lbb1217:
	movq -7016(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1225
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r10
	andq %r10, %rax
	cmpq $0, %rax
	jnz .Lbb1224
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1223
	movl %r9d, %r14d
	movq -32(%rcx), %r9
	cmpq $0, %r9
	jnz .Lbb1222
	.loc 1 977
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	jmp .Lbb1225
.Lbb1222:
	movl %r14d, %r9d
.Lbb1223:
	movq %rax, -24(%rcx)
.Lbb1224:
	movq $0, -7016(%rbp)
.Lbb1225:
	movl $0, %r10d
.Lbb1226:
	movl %r10d, -1324(%rbp)
	movq 136(%rsi), %rax
	cmpq $0, %rax
	jz .Lbb1231
	movq -16(%rax), %rcx
	movl %r9d, %r14d
	movq $6917529027641081858, %r9
	andq %r9, %rcx
	cmpq $0, %rcx
	jnz .Lbb1230
	movq -32(%rax), %rax
	cmpq $2, %rax
	jae .Lbb1230
	movl %r14d, %r9d
	jmp .Lbb1231
.Lbb1230:
	.loc 1 977
	movl $0, %ecx
	movq %r11, %rdx
	movq %rsi, %r13
	movq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	callq myl_qbe_rc_unique_field
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -1324(%rbp), %r10d
	movq -2400(%rbp), %r8
	movq -3648(%rbp), %rdx
	cmpl $0, %eax
	jz .Lbb2692
.Lbb1231:
	movq 136(%rsi), %rax
	movq %rax, -1320(%rbp)
	movl %r9d, %r14d
	movq 144(%rsi), %r9
	movq %r9, -1312(%rbp)
	cmpl $0, %r10d
	jnz .Lbb1233
	movl %r10d, -1328(%rbp)
	jmp .Lbb1238
.Lbb1233:
	testl $28, %r14d
	jnz .Lbb1236
	.loc 1 979
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movl %r9d, %r14d
	movq -1312(%rbp), %r9
	movq -1320(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, -1328(%rbp)
	jmp .Lbb1238
.Lbb1236:
	.loc 1 979
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movl %r9d, %r14d
	movq -1312(%rbp), %r9
	movq -1320(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, -1328(%rbp)
.Lbb1238:
	movq $-9223372036854775807, %rcx
	cmpq %rcx, %r9
	jl .Lbb1269
	subq $1, %r9
	cmpq $0, %r9
	jge .Lbb1242
	movq (%rax), %r10
	movq $9223372036854775807, %rcx
	cmpq %rcx, %r10
	ja .Lbb1267
	movq %r9, %rcx
	addq %r10, %r9
	movq %r10, %r11
	xorq %r9, %r11
	movq %rcx, %r12
	xorq %r9, %r12
	andq %r12, %r11
	cmpq $0, %r11
	jl .Lbb1265
.Lbb1242:
	movq (%rax), %rcx
	cmpq %rcx, %r9
	jae .Lbb1263
	movq 32(%rax), %r10
	imulq $24, %r9, %rcx
	movq 0(%r10, %rcx, 1), %r11
	movq %r11, -5840(%rbp)
	movq 8(%r10, %rcx, 1), %r11
	movq %r11, -5832(%rbp)
	movq 16(%r10, %rcx, 1), %r10
	movq %r10, -5824(%rbp)
	movq (%rax), %r10
	cmpq %r10, %r9
	jae .Lbb1261
	movq 32(%rax), %r10
	movq 0(%rcx, %r10, 1), %r11
	movq %r11, -5840(%rbp)
	movq 8(%rcx, %r10, 1), %r11
	movq %r11, -5832(%rbp)
	movq 16(%rcx, %r10, 1), %r10
	movq %r10, -5824(%rbp)
	movq -5840(%rbp), %r10
	movq %r10, -5056(%rbp)
	movq -5832(%rbp), %r10
	movq %r10, -5048(%rbp)
	movq -5824(%rbp), %r10
	movq %r10, -5040(%rbp)
	movq %r8, -5048(%rbp)
	movq (%rax), %r8
	cmpq %r8, %r9
	jae .Lbb1259
	movq 32(%rax), %r8
	movq -5056(%rbp), %rax
	movq %rax, 0(%rcx, %r8, 1)
	movq -5048(%rbp), %rax
	movq %rax, 8(%rcx, %r8, 1)
	movq -5040(%rbp), %rax
	movq %rax, 16(%rcx, %r8, 1)
	.loc 1 1010
	movq %rsi, %r13
	movq %rdi, %r12
	callq myl_f_6b8d2a166bbd9c248350f439dfeb2952399d529c32ecd164fee3dd015aa55840
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, %r11
	movl -1328(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movq %r11, -1336(%rbp)
	cmpl $0, %r10d
	jz .Lbb1251
	testl $28, %r14d
	jnz .Lbb1249
	.loc 1 1010
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -1336(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb1251
.Lbb1249:
	.loc 1 1010
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -1336(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb1251:
	movl %r10d, -1436(%rbp)
	cmpl $0, %r8d
	jnz .Lbb1253
	xchgl %r10d, %r15d
	jmp .Lbb1258
.Lbb1253:
	testl $28, %r15d
	jnz .Lbb1256
	.loc 1 1010
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_3ece1c6f770ecd2a506fa806688c97e383087567b3626d4a9ce4529758a6df1f_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -1436(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -1336(%rbp), %r11
	movq -3648(%rbp), %rdx
	xchgl %r10d, %r15d
	movl $0, %r8d
	jmp .Lbb1258
.Lbb1256:
	.loc 1 1010
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_3ece1c6f770ecd2a506fa806688c97e383087567b3626d4a9ce4529758a6df1f_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl %r15d, %r10d
	movl -1436(%rbp), %r15d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -1336(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r8d
.Lbb1258:
	xchgl %r15d, %r10d
	xchgl %r14d, %r9d
	jmp .Lbb2674
.Lbb1259:
	movq %r8, %rdx
	.loc 1 1004
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1261:
	movq %r10, %rdx
	.loc 1 998
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1263:
	movq %rcx, %rdx
	.loc 1 995
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1265:
	movq %r10, %rsi
	.loc 1 990
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1267:
	movq %r10, %rsi
	.loc 1 988
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb1269:
	movq %r9, %rdx
	.loc 1 981
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1271:
	xchgl %r14d, %r15d
	xchgl %r12d, %r10d
	xchgl %r9d, %r12d
	movq -3824(%rbp), %rdx
	movq 128(%rsi), %r11
	movq %r11, -1352(%rbp)
	cmpl $0, %r15d
	jnz .Lbb1274
	xchgl %r10d, %r15d
	jmp .Lbb1280
.Lbb1274:
	movl %r10d, %r15d
	testl $28, %r14d
	jnz .Lbb1278
	.loc 1 915
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb1280
.Lbb1278:
	.loc 1 915
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movl $0, %r10d
.Lbb1280:
	movq $-9223372036854775807, %r11
	movq %r11, -1344(%rbp)
	movq -1352(%rbp), %r11
	cmpq -1344(%rbp), %r11
	jl .Lbb1355
	movl %r10d, %r11d
	movq 120(%rsi), %r10
	movq %r10, -1392(%rbp)
	cmpl $0, %r11d
	jnz .Lbb1283
	movl %r11d, -1440(%rbp)
	movq -1352(%rbp), %r11
	jmp .Lbb1288
.Lbb1283:
	testl $28, %r14d
	jnz .Lbb1286
	.loc 1 920
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movq -1392(%rbp), %r10
	movq -1352(%rbp), %r11
	movl $0, -1440(%rbp)
	jmp .Lbb1288
.Lbb1286:
	.loc 1 920
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movq -1392(%rbp), %r10
	movq -1352(%rbp), %r11
	movl $0, -1440(%rbp)
.Lbb1288:
	subq $1, %r11
	movq %r11, -1576(%rbp)
	cmpq $0, %r11
	jl .Lbb1290
	movq %r11, -1416(%rbp)
	jmp .Lbb1294
.Lbb1290:
	movq (%r10), %r10
	movq %r10, -1368(%rbp)
	movq -1576(%rbp), %r11
	movq $9223372036854775807, %r10
	movq %r10, -1360(%rbp)
	movq -1368(%rbp), %r10
	cmpq -1360(%rbp), %r10
	ja .Lbb1353
	movq -1368(%rbp), %r10
	addq %r11, %r10
	movq %r10, -1408(%rbp)
	movq -1368(%rbp), %r10
	xorq -1408(%rbp), %r10
	movq %r10, -1384(%rbp)
	movq %r11, %r10
	xorq -1408(%rbp), %r10
	movq %r10, -1376(%rbp)
	movq -1368(%rbp), %r11
	movq -1384(%rbp), %r10
	andq -1376(%rbp), %r10
	movq %r10, -1400(%rbp)
	movq -1392(%rbp), %r10
	cmpq $0, -1400(%rbp)
	jl .Lbb1351
	movq -1408(%rbp), %r11
	movq %r11, -1416(%rbp)
.Lbb1294:
	movq (%r10), %r11
	movq %r11, -1424(%rbp)
	movq -1416(%rbp), %r11
	cmpq -1424(%rbp), %r11
	jae .Lbb1349
	movq 32(%r10), %r10
	imulq $16, %r11, %r11
	movq %r11, -1432(%rbp)
	movq 0(%r10, %r11, 1), %r11
	movq %r11, -5672(%rbp)
	movq -1432(%rbp), %r11
	movq 8(%r10, %r11, 1), %r10
	movq -1576(%rbp), %r11
	movq %r10, -5664(%rbp)
	movl -5672(%rbp), %r10d
	cmpq $0, %r10
	jz .Lbb1302
	cmpq $1, %r10
	jz .Lbb1301
	cmpq $2, %r10
	jz .Lbb1300
	cmpq $3, %r10
	jnz .Lbb2692
	movl $0, %r10d
	jmp .Lbb1303
.Lbb1300:
	movl $0, %r10d
	jmp .Lbb1303
.Lbb1301:
	movzbq -5664(%rbp), %r10
	movb %r10b, -6392(%rbp)
	xorq $1, %r10
	jmp .Lbb1303
.Lbb1302:
	movl $1, %r10d
.Lbb1303:
	movq $0, -5088(%rbp)
	movq $0, -5080(%rbp)
	movl $1, -5088(%rbp)
	movzbq %r10b, %r10
	movb %r10b, -5080(%rbp)
	movq -5088(%rbp), %r10
	movq %r10, -6072(%rbp)
	movq -5080(%rbp), %r10
	movq %r10, -6064(%rbp)
	movl -1440(%rbp), %r10d
	cmpl $0, %r10d
	jz .Lbb1309
	testl $28, %r14d
	jnz .Lbb1307
	.loc 1 950
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -1576(%rbp), %r11
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb1309
.Lbb1307:
	.loc 1 950
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -1576(%rbp), %r11
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movl $0, %r10d
.Lbb1309:
	cmpl $0, %r10d
	jnz .Lbb1311
	movl %r10d, -1620(%rbp)
	jmp .Lbb1330
.Lbb1311:
	testl $28, %r14d
	jnz .Lbb1321
	movq -7016(%rbp), %r10
	movq %r10, -1464(%rbp)
	cmpq $0, %r10
	jz .Lbb1320
	movq -16(%r10), %r10
	movq %r10, -1456(%rbp)
	movq -1576(%rbp), %r11
	movq $4611686018427387906, %r10
	movq %r10, -1448(%rbp)
	movq -1456(%rbp), %r10
	andq -1448(%rbp), %r10
	movq %r10, -1472(%rbp)
	movq -1464(%rbp), %r10
	cmpq $0, -1472(%rbp)
	jnz .Lbb1319
	movq %r10, %r11
	movq -32(%r11), %r10
	subq $1, %r10
	movq %r10, -1480(%rbp)
	jnz .Lbb1318
	movq -24(%r11), %r10
	movq %r10, -1488(%rbp)
	movq -1480(%rbp), %r10
	cmpq $0, -1488(%rbp)
	jnz .Lbb1318
	.loc 1 951
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -1576(%rbp), %r11
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	jmp .Lbb1320
.Lbb1318:
	movq %r10, -32(%r11)
	movq -1576(%rbp), %r11
.Lbb1319:
	movq $0, -7016(%rbp)
.Lbb1320:
	movl $0, -1620(%rbp)
	jmp .Lbb1330
.Lbb1321:
	movq -7016(%rbp), %r10
	movq %r10, -1512(%rbp)
	cmpq $0, %r10
	jz .Lbb1329
	movq -16(%r10), %r10
	movq %r10, -1504(%rbp)
	movq -1576(%rbp), %r11
	movq $4611686018427387906, %r10
	movq %r10, -1496(%rbp)
	movq -1504(%rbp), %r10
	andq -1496(%rbp), %r10
	movq %r10, -1520(%rbp)
	movq -1512(%rbp), %r10
	cmpq $0, -1520(%rbp)
	jnz .Lbb1328
	movq %r10, %r11
	movq -24(%r11), %r10
	subq $1, %r10
	movq %r10, -1528(%rbp)
	jnz .Lbb1327
	movq -32(%r11), %r10
	movq %r10, -1536(%rbp)
	movq -1528(%rbp), %r10
	cmpq $0, -1536(%rbp)
	jnz .Lbb1327
	.loc 1 951
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -1576(%rbp), %r11
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	jmp .Lbb1329
.Lbb1327:
	movq %r10, -24(%r11)
	movq -1576(%rbp), %r11
.Lbb1328:
	movq $0, -7016(%rbp)
.Lbb1329:
	movl $0, -1620(%rbp)
.Lbb1330:
	movq 120(%rsi), %r10
	movq %r10, -1560(%rbp)
	cmpq $0, %r10
	jnz .Lbb1332
	xchgl %r12d, %r15d
	jmp .Lbb1336
.Lbb1332:
	movq -16(%r10), %r10
	movq %r10, -1552(%rbp)
	movq -1576(%rbp), %r11
	movq $6917529027641081858, %r10
	movq %r10, -1544(%rbp)
	movq -1552(%rbp), %r10
	andq -1544(%rbp), %r10
	movq %r10, -1568(%rbp)
	movq -1560(%rbp), %r10
	cmpq $0, -1568(%rbp)
	jnz .Lbb1335
	movq -32(%r10), %r10
	cmpq $2, %r10
	jae .Lbb1335
	xchgl %r12d, %r15d
	jmp .Lbb1336
.Lbb1335:
	.loc 1 951
	movl $0, %ecx
	movq %rsi, %r13
	movq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	callq myl_qbe_rc_unique_field
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %edx
	movq -1576(%rbp), %r11
	movl -3664(%rbp), %r13d
	movl %r15d, %r12d
	movl -3668(%rbp), %r15d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	cmpl $0, %edx
	jz .Lbb2692
.Lbb1336:
	movq 120(%rsi), %rdx
	movq %rdx, -1600(%rbp)
	cmpq $0, %r11
	jge .Lbb1340
	movq (%rdx), %r10
	movq $9223372036854775807, %rdx
	cmpq %rdx, %r10
	ja .Lbb1347
	movq %r10, %rdx
	addq %r11, %rdx
	movq %rdx, -1616(%rbp)
	movq %r10, %rdx
	xorq -1616(%rbp), %rdx
	movq %rdx, -1592(%rbp)
	movq %r11, %rdx
	xorq -1616(%rbp), %rdx
	movq %rdx, -1584(%rbp)
	movq -1592(%rbp), %rdx
	andq -1584(%rbp), %rdx
	movq %rdx, -1608(%rbp)
	movq -1600(%rbp), %rdx
	cmpq $0, -1608(%rbp)
	jl .Lbb1345
	movq -1616(%rbp), %r11
.Lbb1340:
	movq -6072(%rbp), %r10
	movq %r10, -5072(%rbp)
	movq -6064(%rbp), %r10
	movq %r10, -5064(%rbp)
	movq (%rdx), %r10
	cmpq %r10, %r11
	jae .Lbb1343
	movq 32(%rdx), %r10
	imulq $16, %r11, %r11
	movq -5072(%rbp), %rdx
	movq %rdx, 0(%r10, %r11, 1)
	movq -5064(%rbp), %rdx
	movq %rdx, 8(%r10, %r11, 1)
	movl -1620(%rbp), %r10d
	movq -3648(%rbp), %rdx
	xchgl %r15d, %r12d
	xchgl %r14d, %r9d
	movl $1, %r11d
	jmp .Lbb2674
.Lbb1343:
	movq %r10, %rdx
	.loc 1 965
	movq %r11, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1345:
	movq %r11, %rcx
	movq %r10, %rsi
	.loc 1 961
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1347:
	movq %r10, %rsi
	.loc 1 959
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb1349:
	movq -1424(%rbp), %rdx
	.loc 1 934
	movq %r11, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1351:
	movq -1576(%rbp), %rcx
	movq %r11, %rsi
	.loc 1 931
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1353:
	movq -1368(%rbp), %rsi
	.loc 1 929
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb1355:
	movq -1352(%rbp), %rdx
	.loc 1 917
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1357:
	movq -2400(%rbp), %r8
	xchgl %r14d, %r15d
	movq -3704(%rbp), %r11
	cmpl $0, %r15d
	jnz .Lbb1360
	movl %r15d, %r10d
	movl %r12d, %r15d
	jmp .Lbb1366
.Lbb1360:
	movl %r12d, %r15d
	testl $28, %r14d
	jnz .Lbb1364
	.loc 1 870
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb1366
.Lbb1364:
	.loc 1 870
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb1366:
	cmpl $0, %r10d
	jnz .Lbb1368
	movl %r14d, %r9d
	jmp .Lbb1373
.Lbb1368:
	testl $28, %r14d
	jnz .Lbb1371
	.loc 1 873
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl %r14d, %r9d
	movl $0, %r10d
	jmp .Lbb1373
.Lbb1371:
	.loc 1 873
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb1373:
	cmpl $0, %r10d
	jz .Lbb1393
	testl $28, %r9d
	jnz .Lbb1384
	movq -7016(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1383
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r10
	andq %r10, %rax
	cmpq $0, %rax
	jnz .Lbb1382
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1381
	movl %r9d, %r14d
	movq -24(%rcx), %r9
	cmpq $0, %r9
	jnz .Lbb1380
	.loc 1 874
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	jmp .Lbb1383
.Lbb1380:
	movl %r14d, %r9d
.Lbb1381:
	movq %rax, -32(%rcx)
.Lbb1382:
	movq $0, -7016(%rbp)
.Lbb1383:
	movl $0, %r10d
	jmp .Lbb1393
.Lbb1384:
	movq -7016(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1392
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r10
	andq %r10, %rax
	cmpq $0, %rax
	jnz .Lbb1391
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1390
	movl %r9d, %r14d
	movq -32(%rcx), %r9
	cmpq $0, %r9
	jnz .Lbb1389
	.loc 1 874
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	jmp .Lbb1392
.Lbb1389:
	movl %r14d, %r9d
.Lbb1390:
	movq %rax, -24(%rcx)
.Lbb1391:
	movq $0, -7016(%rbp)
.Lbb1392:
	movl $0, %r10d
.Lbb1393:
	movl %r10d, -1624(%rbp)
	movq 136(%rsi), %rax
	cmpq $0, %rax
	jz .Lbb1398
	movq -16(%rax), %rcx
	movl %r9d, %r14d
	movq $6917529027641081858, %r9
	andq %r9, %rcx
	cmpq $0, %rcx
	jnz .Lbb1397
	movq -32(%rax), %rax
	cmpq $2, %rax
	jae .Lbb1397
	movl %r14d, %r9d
	jmp .Lbb1398
.Lbb1397:
	.loc 1 874
	movl $0, %ecx
	movq %r11, %rdx
	movq %rsi, %r13
	movq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	callq myl_qbe_rc_unique_field
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -1624(%rbp), %r10d
	movq -2400(%rbp), %r8
	movq -3648(%rbp), %rdx
	cmpl $0, %eax
	jz .Lbb2692
.Lbb1398:
	movq 136(%rsi), %rax
	movq %rax, -1640(%rbp)
	movl %r9d, %r14d
	movq 144(%rsi), %r9
	movq %r9, -1632(%rbp)
	cmpl $0, %r10d
	jnz .Lbb1400
	movl %r10d, -1652(%rbp)
	jmp .Lbb1405
.Lbb1400:
	testl $28, %r14d
	jnz .Lbb1403
	.loc 1 876
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movl %r9d, %r14d
	movq -1632(%rbp), %r9
	movq -1640(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, -1652(%rbp)
	jmp .Lbb1405
.Lbb1403:
	.loc 1 876
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movl %r9d, %r14d
	movq -1632(%rbp), %r9
	movq -1640(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, -1652(%rbp)
.Lbb1405:
	movq $-9223372036854775807, %rcx
	cmpq %rcx, %r9
	jl .Lbb1436
	subq $1, %r9
	cmpq $0, %r9
	jge .Lbb1409
	movq (%rax), %r10
	movq $9223372036854775807, %rcx
	cmpq %rcx, %r10
	ja .Lbb1434
	movq %r9, %rcx
	addq %r10, %r9
	movq %r10, %r11
	xorq %r9, %r11
	movq %rcx, %r12
	xorq %r9, %r12
	andq %r12, %r11
	cmpq $0, %r11
	jl .Lbb1432
.Lbb1409:
	movq (%rax), %rcx
	cmpq %rcx, %r9
	jae .Lbb1430
	movq 32(%rax), %r10
	imulq $24, %r9, %rcx
	movq 0(%r10, %rcx, 1), %r11
	movq %r11, -5864(%rbp)
	movq 8(%r10, %rcx, 1), %r11
	movq %r11, -5856(%rbp)
	movq 16(%r10, %rcx, 1), %r10
	movq %r10, -5848(%rbp)
	movq (%rax), %r10
	cmpq %r10, %r9
	jae .Lbb1428
	movq 32(%rax), %r10
	movq 0(%rcx, %r10, 1), %r11
	movq %r11, -5864(%rbp)
	movq 8(%rcx, %r10, 1), %r11
	movq %r11, -5856(%rbp)
	movq 16(%rcx, %r10, 1), %r10
	movq %r10, -5848(%rbp)
	movq -5864(%rbp), %r10
	movq %r10, -5112(%rbp)
	movq -5856(%rbp), %r10
	movq %r10, -5104(%rbp)
	movq -5848(%rbp), %r10
	movq %r10, -5096(%rbp)
	movq %r8, -5104(%rbp)
	movq (%rax), %r8
	cmpq %r8, %r9
	jae .Lbb1426
	movq 32(%rax), %r8
	movq -5112(%rbp), %rax
	movq %rax, 0(%rcx, %r8, 1)
	movq -5104(%rbp), %rax
	movq %rax, 8(%rcx, %r8, 1)
	movq -5096(%rbp), %rax
	movq %rax, 16(%rcx, %r8, 1)
	.loc 1 907
	movq %rsi, %r13
	movq %rdi, %r12
	callq myl_f_2ebfe2cc969f1c1a5ba88011b86a1472451e4fef31738ad491da1fd5ef2c2cc0
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, %r11
	movl -1652(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movq %r11, -1648(%rbp)
	cmpl $0, %r10d
	jz .Lbb1418
	testl $28, %r14d
	jnz .Lbb1416
	.loc 1 907
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -1648(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb1418
.Lbb1416:
	.loc 1 907
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -1648(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb1418:
	movl %r10d, -1656(%rbp)
	cmpl $0, %r8d
	jnz .Lbb1420
	xchgl %r12d, %r15d
	jmp .Lbb1425
.Lbb1420:
	testl $28, %r15d
	jnz .Lbb1423
	.loc 1 907
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_3ece1c6f770ecd2a506fa806688c97e383087567b3626d4a9ce4529758a6df1f_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -1656(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -1648(%rbp), %r11
	movq -3648(%rbp), %rdx
	xchgl %r12d, %r15d
	movl $0, %r8d
	jmp .Lbb1425
.Lbb1423:
	.loc 1 907
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_3ece1c6f770ecd2a506fa806688c97e383087567b3626d4a9ce4529758a6df1f_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -1656(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl %r15d, %r12d
	movl -3668(%rbp), %r15d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -1648(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r8d
.Lbb1425:
	xchgl %r15d, %r12d
	xchgl %r14d, %r9d
	jmp .Lbb2674
.Lbb1426:
	movq %r8, %rdx
	.loc 1 901
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1428:
	movq %r10, %rdx
	.loc 1 895
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1430:
	movq %rcx, %rdx
	.loc 1 892
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1432:
	movq %r10, %rsi
	.loc 1 887
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1434:
	movq %r10, %rsi
	.loc 1 885
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb1436:
	movq %r9, %rdx
	.loc 1 878
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1438:
	movq -2400(%rbp), %r8
	xchgl %r14d, %r15d
	movq %r11, %rcx
	movq -3704(%rbp), %r11
	cmpl $0, %r15d
	jnz .Lbb1441
	movl %r15d, %r10d
	movl %r12d, %r15d
	jmp .Lbb1447
.Lbb1441:
	movl %r12d, %r15d
	testl $28, %r14d
	jnz .Lbb1445
	.loc 1 824
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -1680(%rbp), %rcx
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb1447
.Lbb1445:
	.loc 1 824
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -1680(%rbp), %rcx
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb1447:
	cmpl $0, %r10d
	jnz .Lbb1449
	movl %r14d, %r9d
	jmp .Lbb1454
.Lbb1449:
	testl $28, %r14d
	jnz .Lbb1452
	.loc 1 827
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -1680(%rbp), %rcx
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl %r14d, %r9d
	movl $0, %r10d
	jmp .Lbb1454
.Lbb1452:
	.loc 1 827
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -1680(%rbp), %rcx
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb1454:
	cmpl $0, %r10d
	jz .Lbb1474
	testl $28, %r9d
	jnz .Lbb1465
	movq -7016(%rbp), %r10
	cmpq $0, %r10
	jz .Lbb1464
	movq -16(%r10), %rax
	movq $4611686018427387906, %r12
	andq %r12, %rax
	cmpq $0, %rax
	jnz .Lbb1463
	movq -32(%r10), %rax
	subq $1, %rax
	jnz .Lbb1462
	movl %r9d, %r14d
	movq -24(%r10), %r9
	cmpq $0, %r9
	jnz .Lbb1461
	.loc 1 828
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -1680(%rbp), %rcx
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	jmp .Lbb1464
.Lbb1461:
	movl %r14d, %r9d
.Lbb1462:
	movq %rax, -32(%r10)
.Lbb1463:
	movq $0, -7016(%rbp)
.Lbb1464:
	movl $0, %r10d
	jmp .Lbb1474
.Lbb1465:
	movq -7016(%rbp), %r10
	cmpq $0, %r10
	jz .Lbb1473
	movq -16(%r10), %rax
	movq $4611686018427387906, %r12
	andq %r12, %rax
	cmpq $0, %rax
	jnz .Lbb1472
	movq -24(%r10), %rax
	subq $1, %rax
	jnz .Lbb1471
	movl %r9d, %r14d
	movq -32(%r10), %r9
	cmpq $0, %r9
	jnz .Lbb1470
	.loc 1 828
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -1680(%rbp), %rcx
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	jmp .Lbb1473
.Lbb1470:
	movl %r14d, %r9d
.Lbb1471:
	movq %rax, -24(%r10)
.Lbb1472:
	movq $0, -7016(%rbp)
.Lbb1473:
	movl $0, %r10d
.Lbb1474:
	movl %r10d, -1684(%rbp)
	movq 136(%rsi), %rax
	cmpq $0, %rax
	jnz .Lbb1476
	movl %r9d, %r14d
	jmp .Lbb1479
.Lbb1476:
	movl %r9d, %r14d
	movq -16(%rax), %r9
	movq $6917529027641081858, %r12
	andq %r12, %r9
	cmpq $0, %r9
	jnz .Lbb1478
	movq -32(%rax), %rax
	cmpq $2, %rax
	jb .Lbb1479
.Lbb1478:
	.loc 1 828
	movl $0, %ecx
	movq %r11, %rdx
	movq %rsi, %r13
	movq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	callq myl_qbe_rc_unique_field
	movq %r13, %rsi
	movq %r12, %rdi
	movl -1684(%rbp), %r10d
	movq -2400(%rbp), %r8
	movq -1680(%rbp), %rcx
	movq -3648(%rbp), %rdx
	cmpl $0, %eax
	jz .Lbb2692
.Lbb1479:
	movq 136(%rsi), %rax
	movq %rax, -1672(%rbp)
	movl %r10d, %r12d
	movq 144(%rsi), %r10
	movq %r10, -1664(%rbp)
	cmpl $0, %r12d
	jnz .Lbb1481
	movl %r14d, %r9d
	movl %r12d, -1688(%rbp)
	jmp .Lbb1486
.Lbb1481:
	testl $28, %r14d
	jnz .Lbb1484
	.loc 1 830
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -1664(%rbp), %r10
	movq -1672(%rbp), %rax
	movq -1680(%rbp), %rcx
	movq -3648(%rbp), %rdx
	movl %r14d, %r9d
	movl $0, -1688(%rbp)
	jmp .Lbb1486
.Lbb1484:
	.loc 1 830
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -1664(%rbp), %r10
	movq -1672(%rbp), %rax
	movq -1680(%rbp), %rcx
	movq -3648(%rbp), %rdx
	movl $0, -1688(%rbp)
.Lbb1486:
	movq $-9223372036854775807, %r11
	cmpq %r11, %r10
	jl .Lbb1517
	subq $1, %r10
	cmpq $0, %r10
	jge .Lbb1490
	movq (%rax), %r12
	movq $9223372036854775807, %r11
	cmpq %r11, %r12
	ja .Lbb1515
	movq %r10, %r11
	addq %r12, %r10
	movq %r12, %r13
	xorq %r10, %r13
	movq %r11, %r14
	xorq %r10, %r14
	andq %r14, %r13
	cmpq $0, %r13
	jl .Lbb1513
.Lbb1490:
	movq (%rax), %r11
	cmpq %r11, %r10
	jae .Lbb1511
	movq 32(%rax), %r12
	movq %r8, %r11
	imulq $24, %r10, %r8
	movq 0(%r12, %r8, 1), %r13
	movq %r13, -5888(%rbp)
	movq 8(%r12, %r8, 1), %r13
	movq %r13, -5880(%rbp)
	movq 16(%r12, %r8, 1), %r12
	movq %r12, -5872(%rbp)
	movq (%rax), %r12
	cmpq %r12, %r10
	jae .Lbb1509
	movq 32(%rax), %r12
	movq 0(%r8, %r12, 1), %r13
	movq %r13, -5888(%rbp)
	movq 8(%r8, %r12, 1), %r13
	movq %r13, -5880(%rbp)
	movq 16(%r8, %r12, 1), %r12
	movq %r12, -5872(%rbp)
	movq -5888(%rbp), %r12
	movq %r12, -5136(%rbp)
	movq -5880(%rbp), %r12
	movq %r12, -5128(%rbp)
	movq -5872(%rbp), %r12
	movq %r12, -5120(%rbp)
	movq %r11, -5128(%rbp)
	movq (%rax), %r11
	cmpq %r11, %r10
	jae .Lbb1507
	movl %r9d, %r14d
	movq 32(%rax), %r9
	movq -5136(%rbp), %rax
	movq %rax, 0(%r8, %r9, 1)
	movq -5128(%rbp), %rax
	movq %rax, 8(%r8, %r9, 1)
	movq -5120(%rbp), %rax
	movq %rax, 16(%r8, %r9, 1)
	.loc 1 862
	movq %rsi, %r13
	movq %rdi, %r12
	callq myl_f_aae7e3f63f242f091f741298468821884e7473697b1d7153432e9386d8e0579c
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, %r11
	movl -1688(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movq %r11, -1696(%rbp)
	cmpl $0, %r10d
	jz .Lbb1499
	testl $28, %r14d
	jnz .Lbb1497
	.loc 1 862
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -1696(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb1499
.Lbb1497:
	.loc 1 862
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -1696(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb1499:
	movl %r10d, -1804(%rbp)
	cmpl $0, %r8d
	jnz .Lbb1501
	xchgl %r10d, %r15d
	jmp .Lbb1506
.Lbb1501:
	testl $28, %r15d
	jnz .Lbb1504
	.loc 1 862
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_3ece1c6f770ecd2a506fa806688c97e383087567b3626d4a9ce4529758a6df1f_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -1804(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -1696(%rbp), %r11
	movq -3648(%rbp), %rdx
	xchgl %r10d, %r15d
	movl $0, %r8d
	jmp .Lbb1506
.Lbb1504:
	.loc 1 862
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_3ece1c6f770ecd2a506fa806688c97e383087567b3626d4a9ce4529758a6df1f_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl %r15d, %r10d
	movl -1804(%rbp), %r15d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -1696(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r8d
.Lbb1506:
	xchgl %r15d, %r10d
	xchgl %r14d, %r9d
	jmp .Lbb2674
.Lbb1507:
	movq %r11, %rdx
	.loc 1 855
	movq %r10, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1509:
	movq %r12, %rdx
	.loc 1 849
	movq %r10, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1511:
	movq %r11, %rdx
	.loc 1 846
	movq %r10, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1513:
	movq %r11, %rcx
	movq %r12, %rsi
	.loc 1 841
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1515:
	movq %r12, %rsi
	.loc 1 839
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb1517:
	movq %r10, %rdx
	.loc 1 832
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1519:
	xchgl %r14d, %r15d
	xchgl %r12d, %r10d
	xchgl %r9d, %r12d
	movq 120(%rsi), %r11
	movq %r11, -1776(%rbp)
	cmpl $0, %r15d
	jnz .Lbb1522
	xchgl %r10d, %r15d
	jmp .Lbb1528
.Lbb1522:
	movl %r10d, %r15d
	testl $28, %r14d
	jnz .Lbb1526
	.loc 1 659
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb1528
.Lbb1526:
	.loc 1 659
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movl $0, %r10d
.Lbb1528:
	movq 128(%rsi), %r11
	movq %r11, -1704(%rbp)
	movl %r10d, %r11d
	movq -1776(%rbp), %r10
	cmpl $0, %r11d
	jnz .Lbb1530
	movl %r11d, -1808(%rbp)
	jmp .Lbb1535
.Lbb1530:
	testl $28, %r14d
	jnz .Lbb1533
	.loc 1 662
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movq -1776(%rbp), %r10
	movl $0, -1808(%rbp)
	jmp .Lbb1535
.Lbb1533:
	.loc 1 662
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movq -1776(%rbp), %r10
	movl $0, -1808(%rbp)
.Lbb1535:
	movq $-9223372036854775807, %r11
	movq %r11, -1712(%rbp)
	movq -1704(%rbp), %r11
	cmpq -1712(%rbp), %r11
	jl .Lbb1674
	subq $1, %r11
	movq %r11, -1720(%rbp)
	cmpq $0, %r11
	jl .Lbb1538
	movq %r11, -1784(%rbp)
	jmp .Lbb1542
.Lbb1538:
	movq (%r10), %r10
	movq %r10, -1752(%rbp)
	movq -1720(%rbp), %r11
	movq $9223372036854775807, %r10
	movq %r10, -1728(%rbp)
	movq -1752(%rbp), %r10
	cmpq -1728(%rbp), %r10
	ja .Lbb1672
	movq -1752(%rbp), %r10
	addq %r11, %r10
	movq %r10, -1768(%rbp)
	movq -1752(%rbp), %r10
	xorq -1768(%rbp), %r10
	movq %r10, -1744(%rbp)
	movq %r11, %r10
	xorq -1768(%rbp), %r10
	movq %r10, -1736(%rbp)
	movq -1744(%rbp), %r10
	andq -1736(%rbp), %r10
	movq %r10, -1760(%rbp)
	movq -1752(%rbp), %r10
	cmpq $0, -1760(%rbp)
	jl .Lbb1670
	movq -1768(%rbp), %r11
	movq -1776(%rbp), %r10
	movq %r11, -1784(%rbp)
.Lbb1542:
	movq (%r10), %r11
	movq %r11, -1792(%rbp)
	movq -1784(%rbp), %r11
	cmpq -1792(%rbp), %r11
	jae .Lbb1668
	movq 32(%r10), %r10
	imulq $16, %r11, %r11
	movq %r11, -1800(%rbp)
	movq 0(%r10, %r11, 1), %r11
	movq %r11, -5920(%rbp)
	movq -1800(%rbp), %r11
	movq 8(%r10, %r11, 1), %r11
	movl -1808(%rbp), %r10d
	movq %r11, -5912(%rbp)
	movq 120(%rsi), %r11
	movq %r11, -1888(%rbp)
	cmpl $0, %r10d
	jz .Lbb1549
	testl $28, %r14d
	jnz .Lbb1547
	.loc 1 679
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb1549
.Lbb1547:
	.loc 1 679
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movl $0, %r10d
.Lbb1549:
	movq 128(%rsi), %r11
	movq %r11, -1816(%rbp)
	movl %r10d, %r11d
	movq -1888(%rbp), %r10
	cmpl $0, %r11d
	jnz .Lbb1551
	movl %r11d, -1964(%rbp)
	jmp .Lbb1556
.Lbb1551:
	testl $28, %r14d
	jnz .Lbb1554
	.loc 1 682
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movq -1888(%rbp), %r10
	movl $0, -1964(%rbp)
	jmp .Lbb1556
.Lbb1554:
	.loc 1 682
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movq -1888(%rbp), %r10
	movl $0, -1964(%rbp)
.Lbb1556:
	movq $-9223372036854775806, %r11
	movq %r11, -1824(%rbp)
	movq -1816(%rbp), %r11
	cmpq -1824(%rbp), %r11
	jl .Lbb1666
	subq $2, %r11
	movq %r11, -1832(%rbp)
	cmpq $0, %r11
	jl .Lbb1559
	movq %r11, -1896(%rbp)
	jmp .Lbb1563
.Lbb1559:
	movq (%r10), %r10
	movq %r10, -1864(%rbp)
	movq -1832(%rbp), %r11
	movq $9223372036854775807, %r10
	movq %r10, -1840(%rbp)
	movq -1864(%rbp), %r10
	cmpq -1840(%rbp), %r10
	ja .Lbb1664
	movq -1864(%rbp), %r10
	addq %r11, %r10
	movq %r10, -1880(%rbp)
	movq -1864(%rbp), %r10
	xorq -1880(%rbp), %r10
	movq %r10, -1856(%rbp)
	movq %r11, %r10
	xorq -1880(%rbp), %r10
	movq %r10, -1848(%rbp)
	movq -1856(%rbp), %r10
	andq -1848(%rbp), %r10
	movq %r10, -1872(%rbp)
	movq -1864(%rbp), %r10
	cmpq $0, -1872(%rbp)
	jl .Lbb1662
	movq -1880(%rbp), %r11
	movq -1888(%rbp), %r10
	movq %r11, -1896(%rbp)
.Lbb1563:
	movq (%r10), %r11
	movq %r11, -1904(%rbp)
	movq -1896(%rbp), %r11
	cmpq -1904(%rbp), %r11
	jae .Lbb1660
	movq 32(%r10), %r10
	imulq $16, %r11, %r11
	movq %r11, -1912(%rbp)
	movq 0(%r10, %r11, 1), %r11
	movq %r11, -5904(%rbp)
	movq -1912(%rbp), %r11
	movq 8(%r10, %r11, 1), %r11
	movl -1964(%rbp), %r10d
	movq %r11, -5896(%rbp)
	movq 128(%rsi), %r11
	movq %r11, -1920(%rbp)
	cmpl $0, %r10d
	jz .Lbb1570
	testl $28, %r14d
	jnz .Lbb1568
	.loc 1 699
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb1570
.Lbb1568:
	.loc 1 699
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movl $0, %r10d
.Lbb1570:
	movq $-9223372036854775807, %r11
	movq %r11, -1928(%rbp)
	movq -1920(%rbp), %r11
	cmpq -1928(%rbp), %r11
	jl .Lbb1658
	subq $1, %r11
	movq %r11, 128(%rsi)
	movq -5920(%rbp), %r11
	movq %r11, -5688(%rbp)
	movq -5912(%rbp), %r11
	movq %r11, -5680(%rbp)
	movq -5904(%rbp), %r11
	movq %r11, -5704(%rbp)
	movq -5896(%rbp), %r11
	movq %r11, -5696(%rbp)
	movl -5704(%rbp), %r11d
	cmpq $0, %r11
	jz .Lbb1599
	cmpq $1, %r11
	jz .Lbb1591
	cmpq $2, %r11
	jz .Lbb1583
	cmpq $3, %r11
	jnz .Lbb2692
	movq -5696(%rbp), %r11
	movq %r11, -1936(%rbp)
	movq %r11, -6392(%rbp)
	movl -5688(%rbp), %r11d
	cmpq $0, %r11
	jz .Lbb1582
	cmpq $1, %r11
	jz .Lbb1581
	cmpq $2, %r11
	jz .Lbb1580
	cmpq $3, %r11
	jnz .Lbb2692
	movq -5680(%rbp), %r11
	movq %r11, -1944(%rbp)
	movq %r11, -6392(%rbp)
	movq -1936(%rbp), %r11
	cmpq -1944(%rbp), %r11
	setz %r11b
	movzbq %r11b, %r11
	jmp .Lbb1607
.Lbb1580:
	movl $0, %r11d
	jmp .Lbb1607
.Lbb1581:
	movl $0, %r11d
	jmp .Lbb1607
.Lbb1582:
	movl $0, %r11d
	jmp .Lbb1607
.Lbb1583:
	movq -5696(%rbp), %r11
	movq %r11, -1952(%rbp)
	movq %r11, -6392(%rbp)
	movl -5688(%rbp), %r11d
	cmpq $0, %r11
	jz .Lbb1590
	cmpq $1, %r11
	jz .Lbb1589
	cmpq $2, %r11
	jz .Lbb1588
	cmpq $3, %r11
	jnz .Lbb2692
	movl $0, %r11d
	jmp .Lbb1607
.Lbb1588:
	movq -5680(%rbp), %r11
	movq %r11, -1960(%rbp)
	movq %r11, -6392(%rbp)
	movq -1952(%rbp), %r11
	movq %r11, %xmm1
	movq -1960(%rbp), %r11
	movq %r11, %xmm0
	ucomisd %xmm0, %xmm1
	setz %r11b
	movzbq %r11b, %r11
	movl %r11d, -1968(%rbp)
	setnp %r11b
	movzbq %r11b, %r11
	movl %r11d, -2084(%rbp)
	movl -1968(%rbp), %r11d
	andl -2084(%rbp), %r11d
	jmp .Lbb1607
.Lbb1589:
	movl $0, %r11d
	jmp .Lbb1607
.Lbb1590:
	movl $0, %r11d
	jmp .Lbb1607
.Lbb1591:
	movzbq -5696(%rbp), %r11
	movq %r11, -1976(%rbp)
	movb %r11b, -6392(%rbp)
	movl -5688(%rbp), %r11d
	cmpq $0, %r11
	jz .Lbb1598
	cmpq $1, %r11
	jz .Lbb1597
	cmpq $2, %r11
	jz .Lbb1596
	cmpq $3, %r11
	jnz .Lbb2692
	movl $0, %r11d
	jmp .Lbb1607
.Lbb1596:
	movl $0, %r11d
	jmp .Lbb1607
.Lbb1597:
	movzbq -5680(%rbp), %r11
	movq %r11, -1984(%rbp)
	movb %r11b, -6392(%rbp)
	movq -1976(%rbp), %r11
	cmpq -1984(%rbp), %r11
	setz %r11b
	movzbq %r11b, %r11
	jmp .Lbb1607
.Lbb1598:
	movl $0, %r11d
	jmp .Lbb1607
.Lbb1599:
	movl -5688(%rbp), %r11d
	cmpq $0, %r11
	jz .Lbb1606
	cmpq $1, %r11
	jz .Lbb1605
	cmpq $2, %r11
	jz .Lbb1604
	cmpq $3, %r11
	jnz .Lbb2692
	movl $0, %r11d
	jmp .Lbb1607
.Lbb1604:
	movl $0, %r11d
	jmp .Lbb1607
.Lbb1605:
	movl $0, %r11d
	jmp .Lbb1607
.Lbb1606:
	movl $1, %r11d
.Lbb1607:
	movq $0, -5168(%rbp)
	movq $0, -5160(%rbp)
	movl $1, -5168(%rbp)
	movzbq %r11b, %r11
	movb %r11b, -5160(%rbp)
	movq -5168(%rbp), %r11
	movq %r11, -6072(%rbp)
	movq -5160(%rbp), %r11
	movq %r11, -6064(%rbp)
	cmpl $0, %r10d
	jz .Lbb1613
	testl $28, %r14d
	jnz .Lbb1611
	.loc 1 774
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb1613
.Lbb1611:
	.loc 1 774
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movl $0, %r10d
.Lbb1613:
	cmpl $0, %r10d
	jz .Lbb1631
	testl $28, %r14d
	jnz .Lbb1623
	movq -7016(%rbp), %r11
	cmpq $0, %r11
	jz .Lbb1622
	movq -16(%r11), %r10
	movq %r10, -1992(%rbp)
	movq $4611686018427387906, %r10
	movq %r10, -2000(%rbp)
	movq -1992(%rbp), %r10
	andq -2000(%rbp), %r10
	cmpq $0, %r10
	jnz .Lbb1621
	movq -32(%r11), %r10
	subq $1, %r10
	movq %r10, -2008(%rbp)
	jnz .Lbb1620
	movq -24(%r11), %r10
	movq %r10, -2016(%rbp)
	movq -2008(%rbp), %r10
	cmpq $0, -2016(%rbp)
	jnz .Lbb1620
	.loc 1 775
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	jmp .Lbb1622
.Lbb1620:
	movq %r10, -32(%r11)
.Lbb1621:
	movq $0, -7016(%rbp)
.Lbb1622:
	movl $0, %r10d
	jmp .Lbb1631
.Lbb1623:
	movq -7016(%rbp), %r11
	cmpq $0, %r11
	jz .Lbb1630
	movq -16(%r11), %r10
	movq %r10, -2024(%rbp)
	movq $4611686018427387906, %r10
	movq %r10, -2032(%rbp)
	movq -2024(%rbp), %r10
	andq -2032(%rbp), %r10
	cmpq $0, %r10
	jnz .Lbb1629
	movq -24(%r11), %r10
	subq $1, %r10
	movq %r10, -2040(%rbp)
	jnz .Lbb1628
	movq -32(%r11), %r10
	movq %r10, -2048(%rbp)
	movq -2040(%rbp), %r10
	cmpq $0, -2048(%rbp)
	jnz .Lbb1628
	.loc 1 775
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	jmp .Lbb1630
.Lbb1628:
	movq %r10, -24(%r11)
.Lbb1629:
	movq $0, -7016(%rbp)
.Lbb1630:
	movl $0, %r10d
.Lbb1631:
	movl %r10d, -2088(%rbp)
	movq 120(%rsi), %r11
	movq %r11, -2072(%rbp)
	cmpq $0, %r11
	jz .Lbb1635
	movq -16(%r11), %r10
	movq %r10, -2064(%rbp)
	movl -2088(%rbp), %r10d
	movq $6917529027641081858, %r11
	movq %r11, -2056(%rbp)
	movq -2064(%rbp), %r11
	andq -2056(%rbp), %r11
	movq %r11, -2080(%rbp)
	movq -2072(%rbp), %r11
	cmpq $0, -2080(%rbp)
	jnz .Lbb1634
	movq -32(%r11), %r11
	cmpq $2, %r11
	jb .Lbb1635
.Lbb1634:
	.loc 1 775
	movl $0, %ecx
	movq %rsi, %r13
	movq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	callq myl_qbe_rc_unique_field
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %edx
	movl -2088(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	cmpl $0, %edx
	jz .Lbb2692
.Lbb1635:
	movq 120(%rsi), %rdx
	movq %rdx, -2120(%rbp)
	movl %r10d, %r11d
	movq 128(%rsi), %r10
	movq %r10, -2096(%rbp)
	cmpl $0, %r11d
	jnz .Lbb1637
	xchgl %r12d, %r15d
	movl %r11d, -2140(%rbp)
	jmp .Lbb1642
.Lbb1637:
	testl $28, %r14d
	jnz .Lbb1640
	.loc 1 777
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2096(%rbp), %r10
	movq -2120(%rbp), %rdx
	xchgl %r12d, %r15d
	movl $0, -2140(%rbp)
	jmp .Lbb1642
.Lbb1640:
	.loc 1 777
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl %r15d, %r12d
	movl -3668(%rbp), %r15d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2096(%rbp), %r10
	movq -2120(%rbp), %rdx
	movl $0, -2140(%rbp)
.Lbb1642:
	movq $-9223372036854775807, %r11
	cmpq %r11, %r10
	jl .Lbb1656
	movq %r10, %r11
	subq $1, %r11
	cmpq $0, %r11
	jge .Lbb1647
	movq (%rdx), %r10
	movq $9223372036854775807, %rdx
	cmpq %rdx, %r10
	ja .Lbb1654
	movq %r10, %rdx
	addq %r11, %rdx
	movq %rdx, -2136(%rbp)
	movq %r10, %rdx
	xorq -2136(%rbp), %rdx
	movq %rdx, -2112(%rbp)
	movq %r11, %rdx
	xorq -2136(%rbp), %rdx
	movq %rdx, -2104(%rbp)
	movq -2112(%rbp), %rdx
	andq -2104(%rbp), %rdx
	movq %rdx, -2128(%rbp)
	movq -2120(%rbp), %rdx
	cmpq $0, -2128(%rbp)
	jl .Lbb1652
	movq -2136(%rbp), %r11
.Lbb1647:
	movq -6072(%rbp), %r10
	movq %r10, -5152(%rbp)
	movq -6064(%rbp), %r10
	movq %r10, -5144(%rbp)
	movq (%rdx), %r10
	cmpq %r10, %r11
	jae .Lbb1650
	movq 32(%rdx), %r10
	imulq $16, %r11, %r11
	movq -5152(%rbp), %rdx
	movq %rdx, 0(%r10, %r11, 1)
	movq -5144(%rbp), %rdx
	movq %rdx, 8(%r10, %r11, 1)
	movl -2140(%rbp), %r10d
	movq -3648(%rbp), %rdx
	xchgl %r15d, %r12d
	xchgl %r14d, %r9d
	movl $1, %r11d
	jmp .Lbb2674
.Lbb1650:
	movq %r10, %rdx
	.loc 1 792
	movq %r11, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1652:
	movq %r11, %rcx
	movq %r10, %rsi
	.loc 1 788
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1654:
	movq %r10, %rsi
	.loc 1 786
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb1656:
	movq %r10, %rdx
	.loc 1 779
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1658:
	movq %r11, %rdx
	.loc 1 701
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1660:
	movq -1904(%rbp), %rdx
	.loc 1 696
	movq %r11, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1662:
	movq %r11, %rcx
	movq %r10, %rsi
	.loc 1 693
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1664:
	movq -1864(%rbp), %rsi
	.loc 1 691
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb1666:
	movq %r11, %rdx
	.loc 1 684
	movl $64, %r8d
	movl $2, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1668:
	movq -1792(%rbp), %rdx
	.loc 1 676
	movq %r11, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1670:
	movq %r11, %rcx
	movq %r10, %rsi
	.loc 1 673
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1672:
	movq -1752(%rbp), %rsi
	.loc 1 671
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb1674:
	movq %r11, %rdx
	.loc 1 664
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1676:
	movq -2400(%rbp), %r8
	xchgl %r14d, %r15d
	movq %rdx, %r11
	cmpl $0, %r15d
	jnz .Lbb1679
	movl %r15d, %r10d
	movl %r12d, %r15d
	jmp .Lbb1685
.Lbb1679:
	movl %r12d, %r15d
	testl $28, %r14d
	jnz .Lbb1683
	.loc 1 575
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movl $0, %r10d
	jmp .Lbb1685
.Lbb1683:
	.loc 1 575
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movl $0, %r10d
.Lbb1685:
	cmpl $0, %r10d
	jz .Lbb1691
	testl $28, %r14d
	jnz .Lbb1689
	.loc 1 578
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movl $0, %r10d
	jmp .Lbb1691
.Lbb1689:
	.loc 1 578
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movl $0, %r10d
.Lbb1691:
	cmpl $0, %r10d
	jz .Lbb1709
	testl $28, %r14d
	jnz .Lbb1701
	movq -7016(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1700
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb1699
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1698
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1698
	.loc 1 579
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	jmp .Lbb1700
.Lbb1698:
	movq %rax, -32(%rcx)
.Lbb1699:
	movq $0, -7016(%rbp)
.Lbb1700:
	movl $0, %r10d
	jmp .Lbb1709
.Lbb1701:
	movq -7016(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1708
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb1707
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1706
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1706
	.loc 1 579
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	jmp .Lbb1708
.Lbb1706:
	movq %rax, -24(%rcx)
.Lbb1707:
	movq $0, -7016(%rbp)
.Lbb1708:
	movl $0, %r10d
.Lbb1709:
	movl %r10d, -2144(%rbp)
	movq 136(%rsi), %rax
	cmpq $0, %rax
	jz .Lbb1713
	movq -16(%rax), %rcx
	movq $6917529027641081858, %rdx
	andq %rdx, %rcx
	cmpq $0, %rcx
	jnz .Lbb1712
	movq -32(%rax), %rax
	cmpq $2, %rax
	jb .Lbb1713
.Lbb1712:
	.loc 1 579
	movl $0, %ecx
	movq %r11, %rdx
	movq %rsi, %r13
	movq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	callq myl_qbe_rc_unique_field
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2144(%rbp), %r10d
	movq -2400(%rbp), %r8
	cmpl $0, %eax
	jz .Lbb2692
.Lbb1713:
	movq 136(%rsi), %rax
	movq %rax, -2160(%rbp)
	movq 144(%rsi), %rdx
	movq %rdx, -2152(%rbp)
	cmpl $0, %r10d
	jnz .Lbb1715
	movl %r14d, %r9d
	movl %r10d, -2196(%rbp)
	jmp .Lbb1720
.Lbb1715:
	testl $28, %r14d
	jnz .Lbb1718
	.loc 1 581
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -2152(%rbp), %rdx
	movq -2160(%rbp), %rax
	movl %r14d, %r9d
	movl $0, -2196(%rbp)
	jmp .Lbb1720
.Lbb1718:
	.loc 1 581
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -2152(%rbp), %rdx
	movq -2160(%rbp), %rax
	movl $0, -2196(%rbp)
.Lbb1720:
	movq $-9223372036854775807, %rcx
	cmpq %rcx, %rdx
	jl .Lbb1786
	movl %r9d, %r14d
	movq %rdx, %r9
	subq $1, %r9
	cmpq $0, %r9
	jge .Lbb1724
	movq (%rax), %r10
	movq $9223372036854775807, %rcx
	cmpq %rcx, %r10
	ja .Lbb1784
	movq %r9, %rcx
	addq %r10, %r9
	movq %r10, %rdx
	xorq %r9, %rdx
	movq %rcx, %r11
	xorq %r9, %r11
	andq %r11, %rdx
	cmpq $0, %rdx
	jl .Lbb1782
.Lbb1724:
	movq (%rax), %rcx
	cmpq %rcx, %r9
	jae .Lbb1780
	movq 32(%rax), %rdx
	imulq $24, %r9, %rcx
	movq 0(%rdx, %rcx, 1), %r10
	movq %r10, -5944(%rbp)
	movq 8(%rdx, %rcx, 1), %r10
	movq %r10, -5936(%rbp)
	movq 16(%rdx, %rcx, 1), %rdx
	movq %rdx, -5928(%rbp)
	movq (%rax), %rdx
	cmpq %rdx, %r9
	jae .Lbb1779
	movq 32(%rax), %rdx
	movq 0(%rcx, %rdx, 1), %r10
	movq %r10, -5944(%rbp)
	movq 8(%rcx, %rdx, 1), %r10
	movq %r10, -5936(%rbp)
	movq 16(%rcx, %rdx, 1), %rdx
	movq %rdx, -5928(%rbp)
	movq -5944(%rbp), %rdx
	movq %rdx, -5192(%rbp)
	movq -5936(%rbp), %rdx
	movq %rdx, -5184(%rbp)
	movq -5928(%rbp), %rdx
	movq %rdx, -5176(%rbp)
	movq %r8, -5184(%rbp)
	movq (%rax), %rdx
	cmpq %rdx, %r9
	jae .Lbb1778
	movq 32(%rax), %rdx
	movq -5192(%rbp), %rax
	movq %rax, 0(%rcx, %rdx, 1)
	movq -5184(%rbp), %rax
	movq %rax, 8(%rcx, %rdx, 1)
	movq -5176(%rbp), %rax
	movq %rax, 16(%rcx, %rdx, 1)
	.loc 1 611
	movq %rsi, %r13
	leaq -6144(%rbp), %rsi
	movq %rdi, %r12
	callq myl_f_94484f74f9fdfe749fe3bbd5703ff3b6b2a0ee43d3569a1125fbe02c5095250d
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, -2192(%rbp)
	movl -2196(%rbp), %r10d
	movq -3752(%rbp), %rdx
	cmpl $0, %r10d
	jz .Lbb1733
	testl $28, %r14d
	jnz .Lbb1731
	.loc 1 611
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3752(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb1733
.Lbb1731:
	.loc 1 611
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3752(%rbp), %rdx
	movl $0, %r10d
.Lbb1733:
	movq 128(%rsi), %rax
	movq %rax, -2168(%rbp)
	cmpl $0, %r10d
	jz .Lbb1739
	testl $28, %r14d
	jnz .Lbb1737
	.loc 1 614
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3752(%rbp), %rdx
	movq -2168(%rbp), %rax
	movl $0, %r10d
	jmp .Lbb1739
.Lbb1737:
	.loc 1 614
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3752(%rbp), %rdx
	movq -2168(%rbp), %rax
	movl $0, %r10d
.Lbb1739:
	movq $-9223372036854775807, %rcx
	cmpq %rcx, %rax
	jl .Lbb1776
	subq $1, %rax
	movq %rax, 128(%rsi)
	movq 120(%rsi), %rax
	movq %rax, -2176(%rbp)
	cmpl $0, %r10d
	jz .Lbb1746
	testl $28, %r14d
	jnz .Lbb1744
	.loc 1 629
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3752(%rbp), %rdx
	movq -2176(%rbp), %rax
	movl $0, %r10d
	jmp .Lbb1746
.Lbb1744:
	.loc 1 629
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3752(%rbp), %rdx
	movq -2176(%rbp), %rax
	movl $0, %r10d
.Lbb1746:
	movq 128(%rsi), %rcx
	movq %rcx, -2184(%rbp)
	cmpl $0, %r10d
	jnz .Lbb1748
	movq %rsi, %r13
	movq %rdx, %rsi
	movl %r10d, -2200(%rbp)
	jmp .Lbb1753
.Lbb1748:
	testl $28, %r14d
	jnz .Lbb1751
	.loc 1 632
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -3752(%rbp), %rdx
	movq -2184(%rbp), %rcx
	movq -2176(%rbp), %rax
	movq %rsi, %r13
	movq %rdx, %rsi
	movl $0, -2200(%rbp)
	jmp .Lbb1753
.Lbb1751:
	.loc 1 632
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rsi, %r13
	movq -3752(%rbp), %rsi
	movq -2184(%rbp), %rcx
	movq -2176(%rbp), %rax
	movl $0, -2200(%rbp)
.Lbb1753:
	cmpq $0, %rcx
	jge .Lbb1756
	movq (%rax), %r10
	movq $9223372036854775807, %rdx
	cmpq %rdx, %r10
	ja .Lbb1774
	movq %rcx, %r9
	addq %r10, %rcx
	movq %r10, %rdx
	xorq %rcx, %rdx
	movq %r9, %r8
	xorq %rcx, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jl .Lbb1772
.Lbb1756:
	movq (%rax), %rdx
	cmpq %rdx, %rcx
	jae .Lbb1771
	movq 32(%rax), %rax
	imulq $16, %rcx, %rcx
	movq 0(%rax, %rcx, 1), %rdx
	movq %rdx, 0(%rsi)
	movq 8(%rax, %rcx, 1), %rax
	movq %rax, 8(%rsi)
	.loc 1 645
	movq %rdi, %r12
	callq myl_f_a9f74430ee4e948451728b3abe4d648b4eecdee44abb338e15267f988b669b40
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, %rcx
	movq -2192(%rbp), %r8
	movq -3648(%rbp), %rdx
	.loc 1 651
	movq %rsi, %r13
	movq %rdi, %r12
	callq myl_f_e9094c6211933ede19810aeaba462c8d30aa91458caea819bb98a6ba7765e7d1
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, %r11
	movl -2200(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movq %r11, -2208(%rbp)
	cmpl $0, %r10d
	jz .Lbb1763
	testl $28, %r14d
	jnz .Lbb1761
	.loc 1 651
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2208(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb1763
.Lbb1761:
	.loc 1 651
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2208(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb1763:
	movl %r10d, -2212(%rbp)
	cmpl $0, %r8d
	jnz .Lbb1765
	xchgl %r12d, %r15d
	jmp .Lbb1770
.Lbb1765:
	testl $28, %r15d
	jnz .Lbb1768
	.loc 1 651
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_3ece1c6f770ecd2a506fa806688c97e383087567b3626d4a9ce4529758a6df1f_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2212(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2208(%rbp), %r11
	movq -3648(%rbp), %rdx
	xchgl %r12d, %r15d
	movl $0, %r8d
	jmp .Lbb1770
.Lbb1768:
	.loc 1 651
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_3ece1c6f770ecd2a506fa806688c97e383087567b3626d4a9ce4529758a6df1f_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2212(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl %r15d, %r12d
	movl -3668(%rbp), %r15d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2208(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r8d
.Lbb1770:
	xchgl %r15d, %r12d
	xchgl %r14d, %r9d
	jmp .Lbb2674
.Lbb1771:
	.loc 1 644
	movq %rcx, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1772:
	movq %r10, %rsi
	movq %r9, %rcx
	.loc 1 641
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1774:
	movq %r10, %rsi
	.loc 1 639
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb1776:
	movq %rax, %rdx
	.loc 1 616
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1778:
	.loc 1 606
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1779:
	.loc 1 600
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1780:
	movq %rcx, %rdx
	.loc 1 597
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1782:
	movq %r10, %rsi
	.loc 1 592
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1784:
	movq %r10, %rsi
	.loc 1 590
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb1786:
	.loc 1 583
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1787:
	movq -2400(%rbp), %r8
	xchgl %r14d, %r15d
	movq %rdx, %r11
	movq -3648(%rbp), %rdx
	cmpl $0, %r15d
	jnz .Lbb1790
	movl %r15d, %r10d
	movl %r12d, %r15d
	jmp .Lbb1796
.Lbb1790:
	movl %r12d, %r15d
	testl $28, %r14d
	jnz .Lbb1794
	.loc 1 529
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb1796
.Lbb1794:
	.loc 1 529
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb1796:
	cmpl $0, %r10d
	jnz .Lbb1798
	movl %r14d, %r9d
	jmp .Lbb1803
.Lbb1798:
	testl $28, %r14d
	jnz .Lbb1801
	.loc 1 532
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl %r14d, %r9d
	movl $0, %r10d
	jmp .Lbb1803
.Lbb1801:
	.loc 1 532
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb1803:
	cmpl $0, %r10d
	jz .Lbb1823
	testl $28, %r9d
	jnz .Lbb1814
	movq -7016(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1813
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r10
	andq %r10, %rax
	cmpq $0, %rax
	jnz .Lbb1812
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1811
	movl %r9d, %r14d
	movq -24(%rcx), %r9
	cmpq $0, %r9
	jnz .Lbb1810
	.loc 1 533
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	jmp .Lbb1813
.Lbb1810:
	movl %r14d, %r9d
.Lbb1811:
	movq %rax, -32(%rcx)
.Lbb1812:
	movq $0, -7016(%rbp)
.Lbb1813:
	movl $0, %r10d
	jmp .Lbb1823
.Lbb1814:
	movq -7016(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1822
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r10
	andq %r10, %rax
	cmpq $0, %rax
	jnz .Lbb1821
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1820
	movl %r9d, %r14d
	movq -32(%rcx), %r9
	cmpq $0, %r9
	jnz .Lbb1819
	.loc 1 533
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	jmp .Lbb1822
.Lbb1819:
	movl %r14d, %r9d
.Lbb1820:
	movq %rax, -24(%rcx)
.Lbb1821:
	movq $0, -7016(%rbp)
.Lbb1822:
	movl $0, %r10d
.Lbb1823:
	movl %r10d, -2216(%rbp)
	movq 136(%rsi), %rax
	cmpq $0, %rax
	jz .Lbb1828
	movq -16(%rax), %rcx
	movl %r9d, %r14d
	movq $6917529027641081858, %r9
	andq %r9, %rcx
	cmpq $0, %rcx
	jnz .Lbb1827
	movq -32(%rax), %rax
	cmpq $2, %rax
	jae .Lbb1827
	movl %r14d, %r9d
	jmp .Lbb1828
.Lbb1827:
	.loc 1 533
	movl $0, %ecx
	movq %r11, %rdx
	movq %rsi, %r13
	movq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	callq myl_qbe_rc_unique_field
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2216(%rbp), %r10d
	movq -2400(%rbp), %r8
	movq -3648(%rbp), %rdx
	cmpl $0, %eax
	jz .Lbb2692
.Lbb1828:
	movq 136(%rsi), %rax
	movq %rax, -2232(%rbp)
	movl %r9d, %r14d
	movq 144(%rsi), %r9
	movq %r9, -2224(%rbp)
	cmpl $0, %r10d
	jnz .Lbb1830
	movl %r10d, -2244(%rbp)
	jmp .Lbb1835
.Lbb1830:
	testl $28, %r14d
	jnz .Lbb1833
	.loc 1 535
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movl %r9d, %r14d
	movq -2224(%rbp), %r9
	movq -2232(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, -2244(%rbp)
	jmp .Lbb1835
.Lbb1833:
	.loc 1 535
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movl %r9d, %r14d
	movq -2224(%rbp), %r9
	movq -2232(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, -2244(%rbp)
.Lbb1835:
	movq $-9223372036854775807, %rcx
	cmpq %rcx, %r9
	jl .Lbb1872
	subq $1, %r9
	cmpq $0, %r9
	jge .Lbb1839
	movq (%rax), %r10
	movq $9223372036854775807, %rcx
	cmpq %rcx, %r10
	ja .Lbb1870
	movq %r9, %rcx
	addq %r10, %r9
	movq %r10, %r11
	xorq %r9, %r11
	movq %rcx, %r12
	xorq %r9, %r12
	andq %r12, %r11
	cmpq $0, %r11
	jl .Lbb1868
.Lbb1839:
	movq (%rax), %rcx
	cmpq %rcx, %r9
	jae .Lbb1866
	movq 32(%rax), %r10
	imulq $24, %r9, %rcx
	movq 0(%r10, %rcx, 1), %r11
	movq %r11, -5968(%rbp)
	movq 8(%r10, %rcx, 1), %r11
	movq %r11, -5960(%rbp)
	movq 16(%r10, %rcx, 1), %r10
	movq %r10, -5952(%rbp)
	movq (%rax), %r10
	cmpq %r10, %r9
	jae .Lbb1864
	movq 32(%rax), %r10
	movq 0(%rcx, %r10, 1), %r11
	movq %r11, -5968(%rbp)
	movq 8(%rcx, %r10, 1), %r11
	movq %r11, -5960(%rbp)
	movq 16(%rcx, %r10, 1), %r10
	movq %r10, -5952(%rbp)
	movq -5968(%rbp), %r10
	movq %r10, -5216(%rbp)
	movq -5960(%rbp), %r10
	movq %r10, -5208(%rbp)
	movq -5952(%rbp), %r10
	movq %r10, -5200(%rbp)
	movq %r8, -5208(%rbp)
	movq (%rax), %r8
	cmpq %r8, %r9
	jae .Lbb1862
	movq 32(%rax), %r8
	movq -5216(%rbp), %rax
	movq %rax, 0(%rcx, %r8, 1)
	movq -5208(%rbp), %rax
	movq %rax, 8(%rcx, %r8, 1)
	movq -5200(%rbp), %rax
	movq %rax, 16(%rcx, %r8, 1)
	.loc 1 567
	leaq -6144(%rbp), %rcx
	movq %rsi, %r13
	movq %rdi, %r12
	callq myl_f_9a0199d95ad9eff3ff1c9349ca8998b70fffda59996a1ab49599b93a90d66e10
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, %r11
	movl -2244(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movq %r11, -2240(%rbp)
	cmpl $0, %r10d
	jz .Lbb1848
	testl $28, %r14d
	jnz .Lbb1846
	.loc 1 567
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2240(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb1848
.Lbb1846:
	.loc 1 567
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2240(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb1848:
	movl %r10d, -2252(%rbp)
	cmpl $0, %r8d
	jz .Lbb1854
	testl $28, %r15d
	jnz .Lbb1852
	.loc 1 567
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_3ece1c6f770ecd2a506fa806688c97e383087567b3626d4a9ce4529758a6df1f_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2252(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2240(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r8d
	jmp .Lbb1854
.Lbb1852:
	.loc 1 567
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_3ece1c6f770ecd2a506fa806688c97e383087567b3626d4a9ce4529758a6df1f_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2252(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2240(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r8d
.Lbb1854:
	movl %r8d, -2248(%rbp)
	cmpl $0, %ecx
	jnz .Lbb1856
	xchgl %r12d, %r15d
	jmp .Lbb1861
.Lbb1856:
	testl $28, %r9d
	jnz .Lbb1859
	.loc 1 567
	movq %rsi, %r13
	leaq -6600(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2248(%rbp), %r8d
	movl -2252(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2240(%rbp), %r11
	movq -3648(%rbp), %rdx
	xchgl %r12d, %r15d
	movl $0, %ecx
	jmp .Lbb1861
.Lbb1859:
	.loc 1 567
	movq %rsi, %r13
	leaq -6600(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2248(%rbp), %r8d
	movl -2252(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl %r15d, %r12d
	movl -3668(%rbp), %r15d
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2240(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %ecx
.Lbb1861:
	xchgl %r15d, %r12d
	xchgl %r14d, %r9d
	jmp .Lbb2674
.Lbb1862:
	movq %r8, %rdx
	.loc 1 560
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1864:
	movq %r10, %rdx
	.loc 1 554
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1866:
	movq %rcx, %rdx
	.loc 1 551
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1868:
	movq %r10, %rsi
	.loc 1 546
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1870:
	movq %r10, %rsi
	.loc 1 544
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb1872:
	movq %r9, %rdx
	.loc 1 537
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1874:
	movq -2400(%rbp), %r8
	xchgl %r14d, %r15d
	movq %rdx, %r11
	movq -3648(%rbp), %rdx
	cmpl $0, %r15d
	jnz .Lbb1877
	movl %r15d, %r10d
	movl %r12d, %r15d
	jmp .Lbb1883
.Lbb1877:
	movl %r12d, %r15d
	testl $28, %r14d
	jnz .Lbb1881
	.loc 1 483
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb1883
.Lbb1881:
	.loc 1 483
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb1883:
	cmpl $0, %r10d
	jnz .Lbb1885
	movl %r14d, %r9d
	jmp .Lbb1890
.Lbb1885:
	testl $28, %r14d
	jnz .Lbb1888
	.loc 1 486
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl %r14d, %r9d
	movl $0, %r10d
	jmp .Lbb1890
.Lbb1888:
	.loc 1 486
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb1890:
	cmpl $0, %r10d
	jz .Lbb1910
	testl $28, %r9d
	jnz .Lbb1901
	movq -7016(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1900
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r10
	andq %r10, %rax
	cmpq $0, %rax
	jnz .Lbb1899
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1898
	movl %r9d, %r14d
	movq -24(%rcx), %r9
	cmpq $0, %r9
	jnz .Lbb1897
	.loc 1 487
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	jmp .Lbb1900
.Lbb1897:
	movl %r14d, %r9d
.Lbb1898:
	movq %rax, -32(%rcx)
.Lbb1899:
	movq $0, -7016(%rbp)
.Lbb1900:
	movl $0, %r10d
	jmp .Lbb1910
.Lbb1901:
	movq -7016(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1909
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r10
	andq %r10, %rax
	cmpq $0, %rax
	jnz .Lbb1908
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1907
	movl %r9d, %r14d
	movq -32(%rcx), %r9
	cmpq $0, %r9
	jnz .Lbb1906
	.loc 1 487
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	jmp .Lbb1909
.Lbb1906:
	movl %r14d, %r9d
.Lbb1907:
	movq %rax, -24(%rcx)
.Lbb1908:
	movq $0, -7016(%rbp)
.Lbb1909:
	movl $0, %r10d
.Lbb1910:
	movl %r10d, -2256(%rbp)
	movq 136(%rsi), %rax
	cmpq $0, %rax
	jz .Lbb1915
	movq -16(%rax), %rcx
	movl %r9d, %r14d
	movq $6917529027641081858, %r9
	andq %r9, %rcx
	cmpq $0, %rcx
	jnz .Lbb1914
	movq -32(%rax), %rax
	cmpq $2, %rax
	jae .Lbb1914
	movl %r14d, %r9d
	jmp .Lbb1915
.Lbb1914:
	.loc 1 487
	movl $0, %ecx
	movq %r11, %rdx
	movq %rsi, %r13
	movq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	callq myl_qbe_rc_unique_field
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2256(%rbp), %r10d
	movq -2400(%rbp), %r8
	movq -3648(%rbp), %rdx
	cmpl $0, %eax
	jz .Lbb2692
.Lbb1915:
	movq 136(%rsi), %rax
	movq %rax, -2272(%rbp)
	movl %r9d, %r14d
	movq 144(%rsi), %r9
	movq %r9, -2264(%rbp)
	cmpl $0, %r10d
	jnz .Lbb1917
	movl %r10d, -2284(%rbp)
	jmp .Lbb1922
.Lbb1917:
	testl $28, %r14d
	jnz .Lbb1920
	.loc 1 489
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movl %r9d, %r14d
	movq -2264(%rbp), %r9
	movq -2272(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, -2284(%rbp)
	jmp .Lbb1922
.Lbb1920:
	.loc 1 489
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movl %r9d, %r14d
	movq -2264(%rbp), %r9
	movq -2272(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, -2284(%rbp)
.Lbb1922:
	movq $-9223372036854775807, %rcx
	cmpq %rcx, %r9
	jl .Lbb1959
	subq $1, %r9
	cmpq $0, %r9
	jge .Lbb1926
	movq (%rax), %r10
	movq $9223372036854775807, %rcx
	cmpq %rcx, %r10
	ja .Lbb1957
	movq %r9, %rcx
	addq %r10, %r9
	movq %r10, %r11
	xorq %r9, %r11
	movq %rcx, %r12
	xorq %r9, %r12
	andq %r12, %r11
	cmpq $0, %r11
	jl .Lbb1955
.Lbb1926:
	movq (%rax), %rcx
	cmpq %rcx, %r9
	jae .Lbb1953
	movq 32(%rax), %r10
	imulq $24, %r9, %rcx
	movq 0(%r10, %rcx, 1), %r11
	movq %r11, -5992(%rbp)
	movq 8(%r10, %rcx, 1), %r11
	movq %r11, -5984(%rbp)
	movq 16(%r10, %rcx, 1), %r10
	movq %r10, -5976(%rbp)
	movq (%rax), %r10
	cmpq %r10, %r9
	jae .Lbb1951
	movq 32(%rax), %r10
	movq 0(%rcx, %r10, 1), %r11
	movq %r11, -5992(%rbp)
	movq 8(%rcx, %r10, 1), %r11
	movq %r11, -5984(%rbp)
	movq 16(%rcx, %r10, 1), %r10
	movq %r10, -5976(%rbp)
	movq -5992(%rbp), %r10
	movq %r10, -5240(%rbp)
	movq -5984(%rbp), %r10
	movq %r10, -5232(%rbp)
	movq -5976(%rbp), %r10
	movq %r10, -5224(%rbp)
	movq %r8, -5232(%rbp)
	movq (%rax), %r8
	cmpq %r8, %r9
	jae .Lbb1949
	movq 32(%rax), %r8
	movq -5240(%rbp), %rax
	movq %rax, 0(%rcx, %r8, 1)
	movq -5232(%rbp), %rax
	movq %rax, 8(%rcx, %r8, 1)
	movq -5224(%rbp), %rax
	movq %rax, 16(%rcx, %r8, 1)
	.loc 1 521
	leaq -6144(%rbp), %rcx
	movq %rsi, %r13
	movq %rdi, %r12
	callq myl_f_9997f25fb78e8fa6d0d7377b866a60fc0115d73452e18cfb6fc361c19bf67784
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, %r11
	movl -2284(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movq %r11, -2280(%rbp)
	cmpl $0, %r10d
	jz .Lbb1935
	testl $28, %r14d
	jnz .Lbb1933
	.loc 1 521
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2280(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb1935
.Lbb1933:
	.loc 1 521
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2280(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb1935:
	movl %r10d, -2292(%rbp)
	cmpl $0, %r8d
	jz .Lbb1941
	testl $28, %r15d
	jnz .Lbb1939
	.loc 1 521
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_3ece1c6f770ecd2a506fa806688c97e383087567b3626d4a9ce4529758a6df1f_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2292(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2280(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r8d
	jmp .Lbb1941
.Lbb1939:
	.loc 1 521
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_3ece1c6f770ecd2a506fa806688c97e383087567b3626d4a9ce4529758a6df1f_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2292(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2280(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r8d
.Lbb1941:
	movl %r8d, -2288(%rbp)
	cmpl $0, %ecx
	jnz .Lbb1943
	xchgl %r10d, %r15d
	jmp .Lbb1948
.Lbb1943:
	testl $28, %r9d
	jnz .Lbb1946
	.loc 1 521
	movq %rsi, %r13
	leaq -6600(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2288(%rbp), %r8d
	movl -2292(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2280(%rbp), %r11
	movq -3648(%rbp), %rdx
	xchgl %r10d, %r15d
	movl $0, %ecx
	jmp .Lbb1948
.Lbb1946:
	.loc 1 521
	movq %rsi, %r13
	leaq -6600(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2288(%rbp), %r8d
	movl %r15d, %r10d
	movl -2292(%rbp), %r15d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2280(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %ecx
.Lbb1948:
	xchgl %r15d, %r10d
	xchgl %r14d, %r9d
	jmp .Lbb2674
.Lbb1949:
	movq %r8, %rdx
	.loc 1 514
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1951:
	movq %r10, %rdx
	.loc 1 508
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1953:
	movq %rcx, %rdx
	.loc 1 505
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1955:
	movq %r10, %rsi
	.loc 1 500
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1957:
	movq %r10, %rsi
	.loc 1 498
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb1959:
	movq %r9, %rdx
	.loc 1 491
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1961:
	xchgl %r14d, %r15d
	.loc 1 475
	leaq -6144(%rbp), %rdx
	movq %rsi, %r13
	movq %rdi, %r12
	callq myl_f_fc59ee3dd541d9a698e7595d5041ff0b2452432249e595746bfcbac6ec0dbc1c
	movl %r15d, %r10d
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl %r10d, %r15d
	movl -3588(%rbp), %r10d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	cmpl $0, %r15d
	jnz .Lbb1964
	xchgl %r10d, %r15d
	jmp .Lbb1970
.Lbb1964:
	movl %r10d, %r15d
	testl $28, %r14d
	jnz .Lbb1968
	.loc 1 475
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb1970
.Lbb1968:
	.loc 1 475
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb1970:
	movl %r10d, -2296(%rbp)
	cmpl $0, %r8d
	jnz .Lbb1972
	xchgl %r10d, %r15d
	jmp .Lbb1977
.Lbb1972:
	testl $28, %r15d
	jnz .Lbb1975
	.loc 1 475
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2296(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	xchgl %r10d, %r15d
	movl $0, %r8d
	jmp .Lbb1977
.Lbb1975:
	.loc 1 475
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl %r15d, %r10d
	movl -2296(%rbp), %r15d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r8d
.Lbb1977:
	xchgl %r15d, %r10d
	xchgl %r14d, %r9d
	movl $1, %r11d
	jmp .Lbb2674
.Lbb1978:
	xchgl %r14d, %r15d
	.loc 1 466
	leaq -6144(%rbp), %rdx
	movq %rsi, %r13
	movq %rdi, %r12
	callq myl_f_767328694dc18a8173640ba3de7757d4b038442746deca689bfc0eb0a23918b2
	movl %r15d, %r10d
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl %r10d, %r15d
	movl -3588(%rbp), %r10d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	cmpl $0, %r15d
	jnz .Lbb1981
	xchgl %r10d, %r15d
	jmp .Lbb1987
.Lbb1981:
	movl %r10d, %r15d
	testl $28, %r14d
	jnz .Lbb1985
	.loc 1 466
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb1987
.Lbb1985:
	.loc 1 466
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb1987:
	movl %r10d, -2300(%rbp)
	cmpl $0, %r8d
	jnz .Lbb1989
	xchgl %r12d, %r15d
	jmp .Lbb1994
.Lbb1989:
	testl $28, %r15d
	jnz .Lbb1992
	.loc 1 466
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2300(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	xchgl %r12d, %r15d
	movl $0, %r8d
	jmp .Lbb1994
.Lbb1992:
	.loc 1 466
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2300(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl %r15d, %r12d
	movl -3668(%rbp), %r15d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r8d
.Lbb1994:
	xchgl %r15d, %r12d
	xchgl %r14d, %r9d
	movl $1, %r11d
	jmp .Lbb2674
.Lbb1995:
	movq -2400(%rbp), %r8
	xchgl %r14d, %r15d
	movq %rdx, %r11
	movq -3648(%rbp), %rdx
	cmpl $0, %r15d
	jnz .Lbb1998
	movl %r15d, %r10d
	movl %r12d, %r15d
	jmp .Lbb2004
.Lbb1998:
	movl %r12d, %r15d
	testl $28, %r14d
	jnz .Lbb2002
	.loc 1 419
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb2004
.Lbb2002:
	.loc 1 419
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb2004:
	cmpl $0, %r10d
	jnz .Lbb2006
	movl %r14d, %r9d
	jmp .Lbb2011
.Lbb2006:
	testl $28, %r14d
	jnz .Lbb2009
	.loc 1 422
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl %r14d, %r9d
	movl $0, %r10d
	jmp .Lbb2011
.Lbb2009:
	.loc 1 422
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb2011:
	cmpl $0, %r10d
	jz .Lbb2031
	testl $28, %r9d
	jnz .Lbb2022
	movq -7016(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2021
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r10
	andq %r10, %rax
	cmpq $0, %rax
	jnz .Lbb2020
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2019
	movl %r9d, %r14d
	movq -24(%rcx), %r9
	cmpq $0, %r9
	jnz .Lbb2018
	.loc 1 423
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	jmp .Lbb2021
.Lbb2018:
	movl %r14d, %r9d
.Lbb2019:
	movq %rax, -32(%rcx)
.Lbb2020:
	movq $0, -7016(%rbp)
.Lbb2021:
	movl $0, %r10d
	jmp .Lbb2031
.Lbb2022:
	movq -7016(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2030
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r10
	andq %r10, %rax
	cmpq $0, %rax
	jnz .Lbb2029
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2028
	movl %r9d, %r14d
	movq -32(%rcx), %r9
	cmpq $0, %r9
	jnz .Lbb2027
	.loc 1 423
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	jmp .Lbb2030
.Lbb2027:
	movl %r14d, %r9d
.Lbb2028:
	movq %rax, -24(%rcx)
.Lbb2029:
	movq $0, -7016(%rbp)
.Lbb2030:
	movl $0, %r10d
.Lbb2031:
	movl %r10d, -2304(%rbp)
	movq 136(%rsi), %rax
	cmpq $0, %rax
	jz .Lbb2036
	movq -16(%rax), %rcx
	movl %r9d, %r14d
	movq $6917529027641081858, %r9
	andq %r9, %rcx
	cmpq $0, %rcx
	jnz .Lbb2035
	movq -32(%rax), %rax
	cmpq $2, %rax
	jae .Lbb2035
	movl %r14d, %r9d
	jmp .Lbb2036
.Lbb2035:
	.loc 1 423
	movl $0, %ecx
	movq %r11, %rdx
	movq %rsi, %r13
	movq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	callq myl_qbe_rc_unique_field
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2304(%rbp), %r10d
	movq -2400(%rbp), %r8
	movq -3648(%rbp), %rdx
	cmpl $0, %eax
	jz .Lbb2692
.Lbb2036:
	movq 136(%rsi), %rax
	movq %rax, -2320(%rbp)
	movl %r9d, %r14d
	movq 144(%rsi), %r9
	movq %r9, -2312(%rbp)
	cmpl $0, %r10d
	jnz .Lbb2038
	movl %r10d, -2332(%rbp)
	jmp .Lbb2043
.Lbb2038:
	testl $28, %r14d
	jnz .Lbb2041
	.loc 1 425
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movl %r9d, %r14d
	movq -2312(%rbp), %r9
	movq -2320(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, -2332(%rbp)
	jmp .Lbb2043
.Lbb2041:
	.loc 1 425
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movl %r9d, %r14d
	movq -2312(%rbp), %r9
	movq -2320(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, -2332(%rbp)
.Lbb2043:
	movq $-9223372036854775807, %rcx
	cmpq %rcx, %r9
	jl .Lbb2080
	subq $1, %r9
	cmpq $0, %r9
	jge .Lbb2047
	movq (%rax), %r10
	movq $9223372036854775807, %rcx
	cmpq %rcx, %r10
	ja .Lbb2078
	movq %r9, %rcx
	addq %r10, %r9
	movq %r10, %r11
	xorq %r9, %r11
	movq %rcx, %r12
	xorq %r9, %r12
	andq %r12, %r11
	cmpq $0, %r11
	jl .Lbb2076
.Lbb2047:
	movq (%rax), %rcx
	cmpq %rcx, %r9
	jae .Lbb2074
	movq 32(%rax), %r10
	imulq $24, %r9, %rcx
	movq 0(%r10, %rcx, 1), %r11
	movq %r11, -6016(%rbp)
	movq 8(%r10, %rcx, 1), %r11
	movq %r11, -6008(%rbp)
	movq 16(%r10, %rcx, 1), %r10
	movq %r10, -6000(%rbp)
	movq (%rax), %r10
	cmpq %r10, %r9
	jae .Lbb2072
	movq 32(%rax), %r10
	movq 0(%rcx, %r10, 1), %r11
	movq %r11, -6016(%rbp)
	movq 8(%rcx, %r10, 1), %r11
	movq %r11, -6008(%rbp)
	movq 16(%rcx, %r10, 1), %r10
	movq %r10, -6000(%rbp)
	movq -6016(%rbp), %r10
	movq %r10, -5264(%rbp)
	movq -6008(%rbp), %r10
	movq %r10, -5256(%rbp)
	movq -6000(%rbp), %r10
	movq %r10, -5248(%rbp)
	movq %r8, -5256(%rbp)
	movq (%rax), %r8
	cmpq %r8, %r9
	jae .Lbb2070
	movq 32(%rax), %r8
	movq -5264(%rbp), %rax
	movq %rax, 0(%rcx, %r8, 1)
	movq -5256(%rbp), %rax
	movq %rax, 8(%rcx, %r8, 1)
	movq -5248(%rbp), %rax
	movq %rax, 16(%rcx, %r8, 1)
	.loc 1 457
	leaq -6144(%rbp), %rcx
	movq %rsi, %r13
	movq %rdi, %r12
	callq myl_f_b361da155a914033687da8756fbfd8cb51ce70a35219f28a8040081445b592d7
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, %r11
	movl -2332(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movq %r11, -2328(%rbp)
	cmpl $0, %r10d
	jz .Lbb2056
	testl $28, %r14d
	jnz .Lbb2054
	.loc 1 457
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2328(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb2056
.Lbb2054:
	.loc 1 457
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2328(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb2056:
	movl %r10d, -2348(%rbp)
	cmpl $0, %r8d
	jz .Lbb2062
	testl $28, %r15d
	jnz .Lbb2060
	.loc 1 457
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_3ece1c6f770ecd2a506fa806688c97e383087567b3626d4a9ce4529758a6df1f_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2348(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2328(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r8d
	jmp .Lbb2062
.Lbb2060:
	.loc 1 457
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_3ece1c6f770ecd2a506fa806688c97e383087567b3626d4a9ce4529758a6df1f_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2348(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2328(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r8d
.Lbb2062:
	movl %r8d, -2336(%rbp)
	cmpl $0, %ecx
	jnz .Lbb2064
	xchgl %r10d, %r15d
	jmp .Lbb2069
.Lbb2064:
	testl $28, %r9d
	jnz .Lbb2067
	.loc 1 457
	movq %rsi, %r13
	leaq -6600(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2336(%rbp), %r8d
	movl -2348(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2328(%rbp), %r11
	movq -3648(%rbp), %rdx
	xchgl %r10d, %r15d
	movl $0, %ecx
	jmp .Lbb2069
.Lbb2067:
	.loc 1 457
	movq %rsi, %r13
	leaq -6600(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2336(%rbp), %r8d
	movl %r15d, %r10d
	movl -2348(%rbp), %r15d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2328(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %ecx
.Lbb2069:
	xchgl %r15d, %r10d
	xchgl %r14d, %r9d
	jmp .Lbb2674
.Lbb2070:
	movq %r8, %rdx
	.loc 1 450
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb2072:
	movq %r10, %rdx
	.loc 1 444
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb2074:
	movq %rcx, %rdx
	.loc 1 441
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb2076:
	movq %r10, %rsi
	.loc 1 436
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2078:
	movq %r10, %rsi
	.loc 1 434
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb2080:
	movq %r9, %rdx
	.loc 1 427
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2082:
	xchgl %r14d, %r15d
	.loc 1 392
	movq %rsi, %r13
	leaq -6144(%rbp), %rsi
	movq %rdi, %r12
	callq myl_f_94484f74f9fdfe749fe3bbd5703ff3b6b2a0ee43d3569a1125fbe02c5095250d
	movl %r15d, %r10d
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, -2344(%rbp)
	movl -3680(%rbp), %r8d
	movl %r10d, %r15d
	movl -3588(%rbp), %r10d
	cmpl $0, %r8d
	jnz .Lbb2085
	movl %r8d, -2372(%rbp)
	jmp .Lbb2090
.Lbb2085:
	testl $28, %r10d
	jnz .Lbb2088
	.loc 1 392
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movl $0, -2372(%rbp)
	jmp .Lbb2090
.Lbb2088:
	.loc 1 392
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movl $0, -2372(%rbp)
.Lbb2090:
	movq 0(%rsi), %rax
	movq %rax, -5472(%rbp)
	movq 8(%rsi), %rax
	movq %rax, -5464(%rbp)
	movq 16(%rsi), %rax
	movq %rax, -5456(%rbp)
	movq 24(%rsi), %rax
	movq %rax, -5448(%rbp)
	movq 32(%rsi), %rax
	movq %rax, -5440(%rbp)
	movq 40(%rsi), %rax
	movq %rax, -5432(%rbp)
	movq 48(%rsi), %rax
	movq %rax, -5424(%rbp)
	movq 56(%rsi), %rax
	movq %rax, -5416(%rbp)
	movq 64(%rsi), %rax
	movq %rax, -5408(%rbp)
	movq 72(%rsi), %rax
	movq %rax, -5400(%rbp)
	movq 80(%rsi), %rax
	movq %rax, -5392(%rbp)
	movq 88(%rsi), %rax
	movq %rax, -5384(%rbp)
	movq 96(%rsi), %rax
	movq %rax, -5376(%rbp)
	movq 104(%rsi), %rax
	movq %rax, -5368(%rbp)
	movq 112(%rsi), %rax
	movq %rax, -5360(%rbp)
	movq 120(%rsi), %rax
	movq %rax, -5352(%rbp)
	movq 128(%rsi), %rax
	movq %rax, -5344(%rbp)
	movq 136(%rsi), %rax
	movq %rax, -5336(%rbp)
	movq 144(%rsi), %rax
	movq %rax, -5328(%rbp)
	movq 152(%rsi), %rax
	movq %rax, -5320(%rbp)
	movq 160(%rsi), %rax
	movq %rax, -5312(%rbp)
	movq 168(%rsi), %rax
	movq %rax, -5304(%rbp)
	movq 176(%rsi), %rax
	movq %rax, -5296(%rbp)
	movq 184(%rsi), %rax
	movq %rax, -5288(%rbp)
	movq 192(%rsi), %rax
	movq %rax, -5280(%rbp)
	movq 200(%rsi), %rax
	movq %rax, -5272(%rbp)
	.loc 1 395
	movl $0, %edx
	movq %rsi, %r13
	leaq -5472(%rbp), %rsi
	movq %rdi, %r12
	callq myl_f_851eb64c403b25f3166dffdb17dfc9e3c924451c20caa5851a74e0f4081ba50f
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, %r8
	movq %rdx, %rax
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -2344(%rbp), %rdx
	movq %r8, -7248(%rbp)
	movq %rax, -7240(%rbp)
	cmpl $0, %ecx
	jnz .Lbb2092
	movl %ecx, -2352(%rbp)
	jmp .Lbb2097
.Lbb2092:
	testl $28, %r9d
	jnz .Lbb2095
	.loc 1 395
	movq %rsi, %r13
	leaq -6600(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2344(%rbp), %rdx
	movl $0, -2352(%rbp)
	jmp .Lbb2097
.Lbb2095:
	.loc 1 395
	movq %rsi, %r13
	leaq -6600(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2344(%rbp), %rdx
	movl $0, -2352(%rbp)
.Lbb2097:
	.loc 1 396
	leaq -7248(%rbp), %rcx
	movq %rsi, %r13
	movq %rdi, %r12
	callq myl_f_df854e8ed9ee42930d3ed44ab0cd662c7c2c4c4b0b98e3a3a182e1a6f7dcca63
	movl %r15d, %r10d
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2352(%rbp), %ecx
	movl -2372(%rbp), %r8d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl %r10d, %r15d
	movl -3588(%rbp), %r10d
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	cmpl $0, %r15d
	jnz .Lbb2099
	xchgl %r10d, %r15d
	jmp .Lbb2105
.Lbb2099:
	movl %r10d, %r15d
	testl $28, %r14d
	jnz .Lbb2103
	.loc 1 396
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2352(%rbp), %ecx
	movl -2372(%rbp), %r8d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb2105
.Lbb2103:
	.loc 1 396
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2352(%rbp), %ecx
	movl -2372(%rbp), %r8d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb2105:
	movq 128(%rsi), %r11
	movq %r11, -2360(%rbp)
	cmpl $0, %r10d
	jnz .Lbb2107
	xchgl %r12d, %r15d
	jmp .Lbb2112
.Lbb2107:
	testl $28, %r14d
	jnz .Lbb2110
	.loc 1 399
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2352(%rbp), %ecx
	movl -2372(%rbp), %r8d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	xchgl %r12d, %r15d
	movl $0, %r10d
	jmp .Lbb2112
.Lbb2110:
	.loc 1 399
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2352(%rbp), %ecx
	movl -2372(%rbp), %r8d
	movl -3664(%rbp), %r13d
	movl %r15d, %r12d
	movl -3668(%rbp), %r15d
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb2112:
	movq $-9223372036854775807, %r11
	movq %r11, -2368(%rbp)
	movq -2360(%rbp), %r11
	cmpq -2368(%rbp), %r11
	jl .Lbb2115
	subq $1, %r11
	movq %r11, 128(%rsi)
	xchgl %r15d, %r12d
	xchgl %r14d, %r9d
	movl $1, %r11d
	jmp .Lbb2674
.Lbb2115:
	movq %r11, %rdx
	.loc 1 401
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2117:
	movq -2400(%rbp), %r8
	xchgl %r14d, %r15d
	movq %rdx, %r11
	movq -3648(%rbp), %rdx
	cmpl $0, %r15d
	jnz .Lbb2120
	movl %r15d, %r10d
	movl %r12d, %r15d
	jmp .Lbb2126
.Lbb2120:
	movl %r12d, %r15d
	testl $28, %r14d
	jnz .Lbb2124
	.loc 1 345
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb2126
.Lbb2124:
	.loc 1 345
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb2126:
	cmpl $0, %r10d
	jnz .Lbb2128
	movl %r14d, %r9d
	jmp .Lbb2133
.Lbb2128:
	testl $28, %r14d
	jnz .Lbb2131
	.loc 1 348
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl %r14d, %r9d
	movl $0, %r10d
	jmp .Lbb2133
.Lbb2131:
	.loc 1 348
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb2133:
	cmpl $0, %r10d
	jz .Lbb2153
	testl $28, %r9d
	jnz .Lbb2144
	movq -7016(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2143
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r10
	andq %r10, %rax
	cmpq $0, %rax
	jnz .Lbb2142
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2141
	movl %r9d, %r14d
	movq -24(%rcx), %r9
	cmpq $0, %r9
	jnz .Lbb2140
	.loc 1 349
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	jmp .Lbb2143
.Lbb2140:
	movl %r14d, %r9d
.Lbb2141:
	movq %rax, -32(%rcx)
.Lbb2142:
	movq $0, -7016(%rbp)
.Lbb2143:
	movl $0, %r10d
	jmp .Lbb2153
.Lbb2144:
	movq -7016(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2152
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r10
	andq %r10, %rax
	cmpq $0, %rax
	jnz .Lbb2151
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2150
	movl %r9d, %r14d
	movq -32(%rcx), %r9
	cmpq $0, %r9
	jnz .Lbb2149
	.loc 1 349
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movq -3704(%rbp), %r11
	movq -3648(%rbp), %rdx
	jmp .Lbb2152
.Lbb2149:
	movl %r14d, %r9d
.Lbb2150:
	movq %rax, -24(%rcx)
.Lbb2151:
	movq $0, -7016(%rbp)
.Lbb2152:
	movl $0, %r10d
.Lbb2153:
	movl %r10d, -2376(%rbp)
	movq 136(%rsi), %rax
	cmpq $0, %rax
	jz .Lbb2158
	movq -16(%rax), %rcx
	movl %r9d, %r14d
	movq $6917529027641081858, %r9
	andq %r9, %rcx
	cmpq $0, %rcx
	jnz .Lbb2157
	movq -32(%rax), %rax
	cmpq $2, %rax
	jae .Lbb2157
	movl %r14d, %r9d
	jmp .Lbb2158
.Lbb2157:
	.loc 1 349
	movl $0, %ecx
	movq %r11, %rdx
	movq %rsi, %r13
	movq myl_t_a76886878581aa149dcc111e15b8fc4762d047b1328eba92f48178c36cc2bfb0@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	callq myl_qbe_rc_unique_field
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2376(%rbp), %r10d
	movq -2400(%rbp), %r8
	movq -3648(%rbp), %rdx
	cmpl $0, %eax
	jz .Lbb2692
.Lbb2158:
	movq 136(%rsi), %rax
	movq %rax, -2392(%rbp)
	movl %r9d, %r14d
	movq 144(%rsi), %r9
	movq %r9, -2384(%rbp)
	cmpl $0, %r10d
	jnz .Lbb2160
	movl %r10d, -2412(%rbp)
	jmp .Lbb2165
.Lbb2160:
	testl $28, %r14d
	jnz .Lbb2163
	.loc 1 351
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movl %r9d, %r14d
	movq -2384(%rbp), %r9
	movq -2392(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, -2412(%rbp)
	jmp .Lbb2165
.Lbb2163:
	.loc 1 351
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2400(%rbp), %r8
	movl %r9d, %r14d
	movq -2384(%rbp), %r9
	movq -2392(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, -2412(%rbp)
.Lbb2165:
	movq $-9223372036854775807, %rcx
	cmpq %rcx, %r9
	jl .Lbb2201
	subq $1, %r9
	cmpq $0, %r9
	jge .Lbb2169
	movq (%rax), %r10
	movq $9223372036854775807, %rcx
	cmpq %rcx, %r10
	ja .Lbb2199
	movq %r9, %rcx
	addq %r10, %r9
	movq %r10, %r11
	xorq %r9, %r11
	movq %rcx, %r12
	xorq %r9, %r12
	andq %r12, %r11
	cmpq $0, %r11
	jl .Lbb2197
.Lbb2169:
	movq (%rax), %rcx
	cmpq %rcx, %r9
	jae .Lbb2195
	movq 32(%rax), %r10
	imulq $24, %r9, %rcx
	movq 0(%r10, %rcx, 1), %r11
	movq %r11, -6040(%rbp)
	movq 8(%r10, %rcx, 1), %r11
	movq %r11, -6032(%rbp)
	movq 16(%r10, %rcx, 1), %r10
	movq %r10, -6024(%rbp)
	movq (%rax), %r10
	cmpq %r10, %r9
	jae .Lbb2193
	movq 32(%rax), %r10
	movq 0(%rcx, %r10, 1), %r11
	movq %r11, -6040(%rbp)
	movq 8(%rcx, %r10, 1), %r11
	movq %r11, -6032(%rbp)
	movq 16(%rcx, %r10, 1), %r10
	movq %r10, -6024(%rbp)
	movq -6040(%rbp), %r10
	movq %r10, -5496(%rbp)
	movq -6032(%rbp), %r10
	movq %r10, -5488(%rbp)
	movq -6024(%rbp), %r10
	movq %r10, -5480(%rbp)
	movq %r8, -5488(%rbp)
	movq (%rax), %r8
	cmpq %r8, %r9
	jae .Lbb2191
	movq 32(%rax), %r8
	movq -5496(%rbp), %rax
	movq %rax, 0(%rcx, %r8, 1)
	movq -5488(%rbp), %rax
	movq %rax, 8(%rcx, %r8, 1)
	movq -5480(%rbp), %rax
	movq %rax, 16(%rcx, %r8, 1)
	.loc 1 383
	leaq -6144(%rbp), %rcx
	movq %rsi, %r13
	movq %rdi, %r12
	callq myl_f_a166af0fddcce6486b1b5dce83e3088987f61aa80d20403973fcc035ba69fb14
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, %r11
	movl -2412(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movq %r11, -2408(%rbp)
	cmpl $0, %r10d
	jz .Lbb2178
	testl $28, %r14d
	jnz .Lbb2176
	.loc 1 383
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2408(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb2178
.Lbb2176:
	.loc 1 383
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2408(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb2178:
	movl %r10d, -2420(%rbp)
	cmpl $0, %r8d
	jz .Lbb2184
	testl $28, %r15d
	jnz .Lbb2182
	.loc 1 383
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_3ece1c6f770ecd2a506fa806688c97e383087567b3626d4a9ce4529758a6df1f_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2420(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2408(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r8d
	jmp .Lbb2184
.Lbb2182:
	.loc 1 383
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_3ece1c6f770ecd2a506fa806688c97e383087567b3626d4a9ce4529758a6df1f_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2420(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2408(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %r8d
.Lbb2184:
	movl %r8d, -2416(%rbp)
	cmpl $0, %ecx
	jz .Lbb2190
	testl $28, %r9d
	jnz .Lbb2188
	.loc 1 383
	movq %rsi, %r13
	leaq -6600(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2416(%rbp), %r8d
	movl -2420(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2408(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %ecx
	jmp .Lbb2190
.Lbb2188:
	.loc 1 383
	movq %rsi, %r13
	leaq -6600(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2416(%rbp), %r8d
	movl -2420(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2408(%rbp), %r11
	movq -3648(%rbp), %rdx
	movl $0, %ecx
.Lbb2190:
	xchgl %r14d, %r9d
	jmp .Lbb2674
.Lbb2191:
	movq %r8, %rdx
	.loc 1 376
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb2193:
	movq %r10, %rdx
	.loc 1 370
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb2195:
	movq %rcx, %rdx
	.loc 1 367
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb2197:
	movq %r10, %rsi
	.loc 1 362
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2199:
	movq %r10, %rsi
	.loc 1 360
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb2201:
	movq %r9, %rdx
	.loc 1 353
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2203:
	xchgl %r14d, %r15d
	.loc 1 315
	movl $0, %edx
	movq %rsi, %r13
	movq %rdi, %r12
	callq myl_f_851eb64c403b25f3166dffdb17dfc9e3c924451c20caa5851a74e0f4081ba50f
	movl %r15d, %r10d
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, %rcx
	movq %rdx, %rax
	movl -3720(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3588(%rbp), %r15d
	movq -3824(%rbp), %rdx
	movq %rcx, -7264(%rbp)
	movq %rax, -7256(%rbp)
	cmpl $0, %r10d
	jnz .Lbb2206
	movl %r14d, %r9d
	xchgl %r12d, %r10d
	jmp .Lbb2211
.Lbb2206:
	testl $28, %r14d
	jnz .Lbb2209
	.loc 1 315
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3720(%rbp), %r10d
	movl -3680(%rbp), %r8d
	movq -3824(%rbp), %rdx
	movl %r14d, %r9d
	movl $0, %r12d
	jmp .Lbb2211
.Lbb2209:
	.loc 1 315
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3720(%rbp), %r10d
	movl -3680(%rbp), %r8d
	movq -3824(%rbp), %rdx
	movl $0, %r12d
.Lbb2211:
	movq -7264(%rbp), %rax
	movq %rax, -6072(%rbp)
	movq -7256(%rbp), %rax
	movq %rax, -6064(%rbp)
	movq 120(%rsi), %rax
	cmpq $0, %rax
	jnz .Lbb2213
	movl %r8d, %r14d
	jmp .Lbb2217
.Lbb2213:
	movq -16(%rax), %rcx
	movl %r8d, %r14d
	movq $4611686018427387906, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jnz .Lbb2217
	movq -24(%rax), %rcx
	addq $1, %rcx
	jz .Lbb2216
	movq %rcx, -24(%rax)
	jmp .Lbb2217
.Lbb2216:
	.loc 1 318
	movl $2, %esi
	callq myl_qbe_rc_status
	jmp .Lbb2692
.Lbb2217:
	movq %rax, -6392(%rbp)
	cmpl $0, %r12d
	jnz .Lbb2219
	movl %r14d, %r8d
	jmp .Lbb2223
.Lbb2219:
	testl $28, %r9d
	jnz .Lbb2222
	.loc 1 318
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3720(%rbp), %r10d
	movq -3824(%rbp), %rdx
	movl %r14d, %r8d
	jmp .Lbb2223
.Lbb2222:
	.loc 1 318
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r8d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3720(%rbp), %r10d
	movq -3824(%rbp), %rdx
.Lbb2223:
	movq -6392(%rbp), %rax
	movq %rax, -7016(%rbp)
	movq -7016(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2231
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r9
	andq %r9, %rax
	cmpq $0, %rax
	jnz .Lbb2230
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2229
	movl %r8d, %r14d
	movq -32(%rcx), %r8
	cmpq $0, %r8
	jnz .Lbb2228
	.loc 1 319
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a_rcg_unloan
	movl %r14d, %r8d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3720(%rbp), %r10d
	movq -3824(%rbp), %rdx
	jmp .Lbb2231
.Lbb2228:
	movl %r14d, %r8d
.Lbb2229:
	movq %rax, -24(%rcx)
.Lbb2230:
	movq $0, -7016(%rbp)
.Lbb2231:
	movq 120(%rsi), %rax
	cmpq $0, %rax
	jnz .Lbb2233
	movl %r8d, %r14d
	jmp .Lbb2236
.Lbb2233:
	movq -16(%rax), %rcx
	movl %r8d, %r14d
	movq $6917529027641081858, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jnz .Lbb2235
	movq -32(%rax), %rax
	cmpq $2, %rax
	jb .Lbb2236
.Lbb2235:
	.loc 1 319
	movl $0, %ecx
	movq %rsi, %r13
	movq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	callq myl_qbe_rc_unique_field
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3720(%rbp), %r10d
	cmpl $0, %eax
	jz .Lbb2692
.Lbb2236:
	movq 120(%rsi), %r9
	movq %r9, -2432(%rbp)
	cmpl $0, %r10d
	jnz .Lbb2238
	movl %r14d, %r8d
	jmp .Lbb2248
.Lbb2238:
	movq -7016(%rbp), %rcx
	cmpq $0, %rcx
	jnz .Lbb2240
	movl %r14d, %r8d
	jmp .Lbb2247
.Lbb2240:
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2245
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2244
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2244
	.loc 1 319
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a_rcg_unloan
	movl %r14d, %r8d
	movq %r13, %rsi
	movq %r12, %rdi
	movq -2432(%rbp), %r9
	jmp .Lbb2247
.Lbb2244:
	movl %r14d, %r8d
	movq %rax, -24(%rcx)
	jmp .Lbb2246
.Lbb2245:
	movl %r14d, %r8d
.Lbb2246:
	movq $0, -7016(%rbp)
.Lbb2247:
	movl $0, %r10d
.Lbb2248:
	movl %r10d, -2424(%rbp)
	movq %rbx, -6184(%rbp)
	movq 5640(%rbx), %rcx
	movq 248(%rcx), %rax
	movq %rax, -6176(%rbp)
	movq $0, -6168(%rbp)
	movl 112(%rbx), %eax
	movl $1, -6160(%rbp)
	movl %eax, -6156(%rbp)
	leaq -6184(%rbp), %rax
	movq %rax, 248(%rcx)
	cmpq $0, %r9
	setnz %al
	movzbl %al, %eax
	cmpl $0, %eax
	jnz .Lbb2250
	movl %r8d, %r14d
	jmp .Lbb2273
.Lbb2250:
	movq -16(%r9), %r11
	movq %r11, %rax
	andq $2, %rax
	cmpq $0, %rax
	jnz .Lbb2272
	movq $4611686018427387907, %rax
	andq %r11, %rax
	cmpq $0, %rax
	jz .Lbb2253
	movl %r8d, %r14d
	jmp .Lbb2266
.Lbb2253:
	movq -8(%r9), %rcx
	movq myl_native_list_header_type(%rip), %rax
	cmpq %rax, %rcx
	jz .Lbb2255
	movl %r8d, %r14d
	jmp .Lbb2266
.Lbb2255:
	movq 5640(%rbx), %r12
	movq 256(%r12), %rax
	cmpq $0, %rax
	jnz .Lbb2257
	movl %r8d, %r14d
	jmp .Lbb2266
.Lbb2257:
	movq 24(%rbx), %rcx
	movq %rcx, %r13
	addq $40, %r13
	cmpq %rcx, %r13
	jae .Lbb2259
	movl %r8d, %r14d
	jmp .Lbb2266
.Lbb2259:
	movq 88(%rbx), %rdx
	cmpq $0, %rdx
	setz %cl
	movzbl %cl, %ecx
	cmpq %rdx, %r13
	setbe %dl
	movzbl %dl, %edx
	orl %edx, %ecx
	jnz .Lbb2261
	movl %r8d, %r14d
	jmp .Lbb2266
.Lbb2261:
	movq -24(%r9), %rcx
	cmpq $-1, %rcx
	jnz .Lbb2263
	movl %r8d, %r14d
	jmp .Lbb2266
.Lbb2263:
	movq 32(%r9), %rcx
	cmpq $0, %rcx
	setnz %dl
	movzbl %dl, %edx
	cmpl $0, %edx
	jz .Lbb2269
	movq -16(%rcx), %rdx
	movl %r8d, %r14d
	movq $4611686018427387907, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jnz .Lbb2266
	movq -24(%rcx), %rdx
	cmpq $-1, %rdx
	jnz .Lbb2268
.Lbb2266:
	.loc 1 319
	movq %r9, %rdx
	movq %rsi, %r13
	leaq -6184(%rbp), %rsi
	movq %rdi, %r12
	callq myl_qbe_rc_scope_pin
	movl %r14d, %r8d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2424(%rbp), %r10d
	cmpl $0, %eax
	jz .Lbb2692
	movl %r8d, %r14d
	jmp .Lbb2273
.Lbb2268:
	movl %r14d, %r8d
.Lbb2269:
	movq (%rax), %rdx
	movq %rdx, 256(%r12)
	movq 264(%r12), %rdx
	addq $-1, %rdx
	movq %rdx, 264(%r12)
	movq 24(%rbx), %rdx
	addq $40, %rdx
	movq %rdx, 24(%rbx)
	movq 48(%r12), %rdx
	addq $40, %rdx
	movq %rdx, 48(%r12)
	movq -24(%r9), %rdx
	addq $1, %rdx
	movq %rdx, -24(%r9)
	cmpq $0, %rcx
	jz .Lbb2271
	movq -24(%rcx), %rdx
	addq $1, %rdx
	movq %rdx, -24(%rcx)
.Lbb2271:
	movq $1152921504606846976, %rdx
	andq %r11, %rdx
	movq $1152921504606846976, %r12
	orq %r12, %r11
	movq %r11, -16(%r9)
	movl %r8d, %r14d
	movq -6168(%rbp), %r8
	movq %r8, (%rax)
	movq %r9, 8(%rax)
	movq %rdx, 16(%rax)
	movl $1, 24(%rax)
	movq %rcx, 32(%rax)
	movq %rax, -6168(%rbp)
	jmp .Lbb2273
.Lbb2272:
	movl %r8d, %r14d
.Lbb2273:
	movq -6112(%rbp), %r11
	movq %r11, -2456(%rbp)
	cmpl $0, %r10d
	jnz .Lbb2275
	movl %r10d, -2656(%rbp)
	jmp .Lbb2277
.Lbb2275:
	.loc 1 321
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movl $0, -2656(%rbp)
.Lbb2277:
	.loc 1 323
	movq %rsi, %r13
	leaq -6144(%rbp), %rsi
	movq %rdi, %r12
	callq myl_f_fa0a495025828a635f8203a4c546663c235c2574b972f1294569bb6fadb2fcc2
	movl %r14d, %r8d
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, %r10
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl -3676(%rbp), %r14d
	movq -3656(%rbp), %rax
	movq -2456(%rbp), %r11
	movq -2432(%rbp), %r9
	movq -3648(%rbp), %rdx
	movq %r10, -2472(%rbp)
	cmpl $0, %r8d
	jz .Lbb2283
	testl $28, %r15d
	jnz .Lbb2281
	.loc 1 323
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -2472(%rbp), %r10
	movq -2456(%rbp), %r11
	movq -2432(%rbp), %r9
	movq -3648(%rbp), %rdx
	movl $0, %r8d
	jmp .Lbb2283
.Lbb2281:
	.loc 1 323
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -2472(%rbp), %r10
	movq -2456(%rbp), %r11
	movq -2432(%rbp), %r9
	movq -3648(%rbp), %rdx
	movl $0, %r8d
.Lbb2283:
	movl %r8d, -2652(%rbp)
	addq %r11, %r10
	movq -2456(%rbp), %r11
	xorq %r10, %r11
	movq %r11, -2448(%rbp)
	movq -2472(%rbp), %r11
	xorq %r10, %r11
	movq %r11, -2440(%rbp)
	movq -2448(%rbp), %r11
	andq -2440(%rbp), %r11
	movq %r11, -2464(%rbp)
	movq -2456(%rbp), %r11
	cmpq $0, -2464(%rbp)
	jl .Lbb2323
	cmpq $0, %r10
	jge .Lbb2288
	movq (%r9), %r11
	movq $9223372036854775807, %r8
	cmpq %r8, %r11
	ja .Lbb2321
	movq %r11, %r8
	addq %r10, %r8
	movq %r8, -2504(%rbp)
	movq %r11, %r8
	xorq -2504(%rbp), %r8
	movq %r8, -2488(%rbp)
	movq %r10, %r8
	xorq -2504(%rbp), %r8
	movq %r8, -2480(%rbp)
	movq -2488(%rbp), %r8
	andq -2480(%rbp), %r8
	movq %r8, -2496(%rbp)
	movl -2652(%rbp), %r8d
	cmpq $0, -2496(%rbp)
	jl .Lbb2319
	movq -2504(%rbp), %r10
.Lbb2288:
	movq -6072(%rbp), %r11
	movq %r11, -5512(%rbp)
	movq -6064(%rbp), %r11
	movq %r11, -5504(%rbp)
	movq (%r9), %r11
	cmpq %r11, %r10
	jae .Lbb2317
	movq 32(%r9), %r11
	movl %r12d, %r9d
	imulq $16, %r10, %r12
	movq -5512(%rbp), %r10
	movq %r10, 0(%r11, %r12, 1)
	movq -5504(%rbp), %r10
	movq %r10, 8(%r11, %r12, 1)
	movl -2656(%rbp), %r10d
	movl -6160(%rbp), %r11d
	cmpl $0, %r11d
	jnz .Lbb2291
	movl %r15d, %r12d
	xchgl %r9d, %r14d
	jmp .Lbb2316
.Lbb2291:
	movl %r15d, %r12d
	movq 5640(%rbx), %r15
	movq 248(%r15), %r11
	movq %r11, -2512(%rbp)
	leaq -6184(%rbp), %r11
	cmpq -2512(%rbp), %r11
	jnz .Lbb2306
	movq 200(%r15), %r11
	cmpq $0, %r11
	jnz .Lbb2306
	movl %r8d, %r11d
	movq -6168(%rbp), %r8
	cmpq $0, %r8
	jnz .Lbb2295
	movl %r11d, %r8d
	xchgl %r9d, %r14d
	jmp .Lbb2315
.Lbb2295:
	movq (%r8), %r10
	cmpq $0, %r10
	jnz .Lbb2306
	movq 264(%r15), %r10
	cmpq $32, %r10
	jae .Lbb2306
	movq 8(%r8), %r11
	movq %r11, -2576(%rbp)
	cmpq $0, %r11
	jz .Lbb2306
	movq -16(%r11), %r10
	movq %r10, -2632(%rbp)
	movq $4611686018427387907, %r10
	movq %r10, -2520(%rbp)
	movq -2632(%rbp), %r10
	andq -2520(%rbp), %r10
	cmpq $0, %r10
	jnz .Lbb2306
	movq -24(%r11), %r10
	movq %r10, -2528(%rbp)
	cmpq $0, %r10
	jz .Lbb2306
	movq -32(%r11), %r10
	movq %r10, -2536(%rbp)
	movq -2528(%rbp), %r10
	cmpq $1, %r10
	seta %r10b
	movzbl %r10b, %r10d
	movl %r10d, -2540(%rbp)
	movq -2536(%rbp), %r10
	cmpq $0, %r10
	setnz %r10b
	movzbl %r10b, %r10d
	movl %r10d, -2544(%rbp)
	movl -2540(%rbp), %r10d
	orl -2544(%rbp), %r10d
	jz .Lbb2306
	movq 32(%r8), %r10
	movq %r10, -2600(%rbp)
	cmpq $0, %r10
	setnz %r10b
	movzbl %r10b, %r10d
	movl %r10d, -2588(%rbp)
	movq -2600(%rbp), %r10
	cmpl $0, -2588(%rbp)
	jnz .Lbb2303
	xchgl %r9d, %r14d
	jmp .Lbb2308
.Lbb2303:
	movq -16(%r10), %r11
	movq %r11, -2552(%rbp)
	movq $4611686018427387907, %r11
	movq %r11, -2560(%rbp)
	movq -2552(%rbp), %r11
	andq -2560(%rbp), %r11
	cmpq $0, %r11
	jnz .Lbb2306
	movq -24(%r10), %r11
	movq %r11, -2568(%rbp)
	cmpq $0, %r11
	jz .Lbb2306
	movq -32(%r10), %r10
	movq %r10, -2584(%rbp)
	movq -2568(%rbp), %r10
	movq -2576(%rbp), %r11
	cmpq $1, %r10
	seta %r10b
	movzbl %r10b, %r10d
	movl %r10d, -2592(%rbp)
	movq -2584(%rbp), %r10
	cmpq $0, %r10
	setnz %r10b
	movzbl %r10b, %r10d
	movl %r10d, -2604(%rbp)
	movl -2592(%rbp), %r10d
	orl -2604(%rbp), %r10d
	jnz .Lbb2307
.Lbb2306:
	.loc 1 337
	movq %rsi, %r15
	leaq -6184(%rbp), %rsi
	movq %rdi, %r13
	callq myl_qbe_rc_scope_end
	movq %r15, %rsi
	movq %r13, %rdi
	movl -2652(%rbp), %r8d
	movl -2656(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl %r14d, %r9d
	movl -3668(%rbp), %r14d
	movl -3672(%rbp), %ecx
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	jmp .Lbb2316
.Lbb2307:
	xchgl %r9d, %r14d
.Lbb2308:
	movl 24(%r8), %r10d
	movl %r10d, -2608(%rbp)
	movq -2600(%rbp), %r10
	cmpl $0, -2608(%rbp)
	jnz .Lbb2310
	xchgq %r8, %rax
	jmp .Lbb2312
.Lbb2310:
	movq %r8, %rax
	movq 16(%rax), %r8
	movq %r8, -2624(%rbp)
	movq $-1152921504606846977, %r8
	movq %r8, -2616(%rbp)
	movq -2632(%rbp), %r8
	andq -2616(%rbp), %r8
	movq %r8, -2640(%rbp)
	movq -2624(%rbp), %r8
	orq -2640(%rbp), %r8
	movq %r8, -16(%r11)
	movq -3712(%rbp), %r8
.Lbb2312:
	movq %r8, -2648(%rbp)
	movq $0, (%r8)
	movq 256(%r15), %r8
	movq %r8, (%rax)
	movl -2652(%rbp), %r8d
	movq %rax, 256(%r15)
	movq 264(%r15), %rax
	addq $1, %rax
	movq %rax, 264(%r15)
	movq 24(%rbx), %rax
	addq $-40, %rax
	movq %rax, 24(%rbx)
	movq 48(%r15), %rax
	addq $-40, %rax
	movq %rax, 48(%r15)
	movq -2648(%rbp), %rax
	cmpq $0, %r10
	jz .Lbb2314
	movq -24(%r10), %rax
	addq $-1, %rax
	movq %rax, -24(%r10)
	movq -2648(%rbp), %rax
.Lbb2314:
	movq -24(%r11), %r10
	addq $-1, %r10
	movq %r10, -24(%r11)
	movl -2656(%rbp), %r10d
.Lbb2315:
	movq -6176(%rbp), %r11
	movq %r11, 248(%r15)
	movl $0, -6160(%rbp)
	movq $0, -6176(%rbp)
.Lbb2316:
	movl %r12d, %r15d
	movl %r14d, %r12d
	movl %r9d, %r14d
	movl $16, %r9d
	movl $1, %r11d
	jmp .Lbb2674
.Lbb2317:
	movq %r11, %rdx
	.loc 1 337
	movq %r10, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb2319:
	movq %r10, %rcx
	movq %r11, %rsi
	.loc 1 333
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2321:
	movq %r11, %rsi
	.loc 1 331
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb2323:
	movq -2472(%rbp), %rcx
	movq %r11, %rdx
	.loc 1 324
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2325:
	movl %r14d, %r10d
	movl %r15d, %r14d
	movl %r10d, %r15d
	movq 120(%rsi), %r10
	movq %r10, -2760(%rbp)
	cmpl $0, %r15d
	jnz .Lbb2328
	movl %r15d, %r10d
	movl %r12d, %r15d
	jmp .Lbb2334
.Lbb2328:
	movl %r12d, %r15d
	testl $28, %r14d
	jnz .Lbb2332
	.loc 1 252
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movl $0, %r10d
	jmp .Lbb2334
.Lbb2332:
	.loc 1 252
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movl $0, %r10d
.Lbb2334:
	movq -6112(%rbp), %rax
	movq %rax, -2696(%rbp)
	cmpl $0, %r10d
	jnz .Lbb2336
	movl %r10d, -2884(%rbp)
	jmp .Lbb2341
.Lbb2336:
	testl $28, %r14d
	jnz .Lbb2339
	.loc 1 255
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movq %r13, %rsi
	movq %r12, %rdi
	movl $0, -2884(%rbp)
	jmp .Lbb2341
.Lbb2339:
	.loc 1 255
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movq %r13, %rsi
	movq %r12, %rdi
	movl $0, -2884(%rbp)
.Lbb2341:
	.loc 1 257
	movq %rsi, %r13
	leaq -6144(%rbp), %rsi
	movq %rdi, %r12
	callq myl_f_fa0a495025828a635f8203a4c546663c235c2574b972f1294569bb6fadb2fcc2
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, -2688(%rbp)
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movq -2696(%rbp), %r10
	movq %rdx, %r11
	movq -3648(%rbp), %rdx
	cmpl $0, %r8d
	jnz .Lbb2343
	movl %r8d, -2944(%rbp)
	movq %r11, %r8
	movq -2688(%rbp), %r11
	jmp .Lbb2348
.Lbb2343:
	testl $28, %r15d
	jnz .Lbb2346
	.loc 1 257
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movq -2688(%rbp), %r11
	movq -2696(%rbp), %r10
	movq %rdx, %r8
	movq -3648(%rbp), %rdx
	movl $0, -2944(%rbp)
	jmp .Lbb2348
.Lbb2346:
	.loc 1 257
	movq %rsi, %r13
	leaq -6808(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movq -2688(%rbp), %r11
	movq -2696(%rbp), %r10
	movq %rdx, %r8
	movq -3648(%rbp), %rdx
	movl $0, -2944(%rbp)
.Lbb2348:
	addq %r10, %r11
	movq %r11, -2704(%rbp)
	movq -2696(%rbp), %r10
	xorq %r11, %r10
	movq %r10, -2672(%rbp)
	movq -2688(%rbp), %r10
	xorq %r11, %r10
	movq %r10, -2664(%rbp)
	movq -2672(%rbp), %r10
	andq -2664(%rbp), %r10
	movq %r10, -2680(%rbp)
	movq -2760(%rbp), %r10
	cmpq $0, -2680(%rbp)
	jl .Lbb2420
	cmpq $0, %r11
	jl .Lbb2351
	movq %r11, -2768(%rbp)
	jmp .Lbb2355
.Lbb2351:
	movq (%r10), %r10
	movq %r10, -2736(%rbp)
	movq -2704(%rbp), %r11
	movq $9223372036854775807, %r10
	movq %r10, -2712(%rbp)
	movq -2736(%rbp), %r10
	cmpq -2712(%rbp), %r10
	ja .Lbb2418
	movq -2736(%rbp), %r10
	addq %r11, %r10
	movq %r10, -2752(%rbp)
	movq -2736(%rbp), %r10
	xorq -2752(%rbp), %r10
	movq %r10, -2728(%rbp)
	movq %r11, %r10
	xorq -2752(%rbp), %r10
	movq %r10, -2720(%rbp)
	movq -2728(%rbp), %r10
	andq -2720(%rbp), %r10
	movq %r10, -2744(%rbp)
	movq -2736(%rbp), %r10
	cmpq $0, -2744(%rbp)
	jl .Lbb2416
	movq -2752(%rbp), %r11
	movq -2760(%rbp), %r10
	movq %r11, -2768(%rbp)
.Lbb2355:
	movq (%r10), %r11
	movq %r11, -2776(%rbp)
	movq -2768(%rbp), %r11
	cmpq -2776(%rbp), %r11
	jae .Lbb2414
	movq 32(%r10), %r10
	imulq $16, %r11, %r11
	movq %r11, -2784(%rbp)
	movq 0(%r10, %r11, 1), %r11
	movq %r11, -6056(%rbp)
	movq -2784(%rbp), %r11
	movq 8(%r10, %r11, 1), %r11
	movl -2884(%rbp), %r10d
	movq %r11, -6048(%rbp)
	movq -6056(%rbp), %r11
	movq %r11, -6072(%rbp)
	movq -6048(%rbp), %r11
	movq %r11, -6064(%rbp)
	cmpl $0, %r10d
	jz .Lbb2362
	testl $28, %r14d
	jnz .Lbb2360
	.loc 1 275
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movq %rdx, %r8
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb2362
.Lbb2360:
	.loc 1 275
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movq %rdx, %r8
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb2362:
	cmpl $0, %r10d
	jz .Lbb2380
	testl $28, %r14d
	jnz .Lbb2372
	movq -7016(%rbp), %r11
	cmpq $0, %r11
	jz .Lbb2371
	movq -16(%r11), %r10
	movq %r10, -2792(%rbp)
	movq $4611686018427387906, %r10
	movq %r10, -2800(%rbp)
	movq -2792(%rbp), %r10
	andq -2800(%rbp), %r10
	cmpq $0, %r10
	jnz .Lbb2370
	movq -32(%r11), %r10
	subq $1, %r10
	movq %r10, -2808(%rbp)
	jnz .Lbb2369
	movq -24(%r11), %r10
	movq %r10, -2816(%rbp)
	movq -2808(%rbp), %r10
	cmpq $0, -2816(%rbp)
	jnz .Lbb2369
	.loc 1 276
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movq %rdx, %r8
	movq -3648(%rbp), %rdx
	jmp .Lbb2371
.Lbb2369:
	movq %r10, -32(%r11)
.Lbb2370:
	movq $0, -7016(%rbp)
.Lbb2371:
	movl $0, %r10d
	jmp .Lbb2380
.Lbb2372:
	movq -7016(%rbp), %r11
	cmpq $0, %r11
	jz .Lbb2379
	movq -16(%r11), %r10
	movq %r10, -2824(%rbp)
	movq $4611686018427387906, %r10
	movq %r10, -2832(%rbp)
	movq -2824(%rbp), %r10
	andq -2832(%rbp), %r10
	cmpq $0, %r10
	jnz .Lbb2378
	movq -24(%r11), %r10
	subq $1, %r10
	movq %r10, -2840(%rbp)
	jnz .Lbb2377
	movq -32(%r11), %r10
	movq %r10, -2848(%rbp)
	movq -2840(%rbp), %r10
	cmpq $0, -2848(%rbp)
	jnz .Lbb2377
	.loc 1 276
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movq %rdx, %r8
	movq -3648(%rbp), %rdx
	jmp .Lbb2379
.Lbb2377:
	movq %r10, -24(%r11)
.Lbb2378:
	movq $0, -7016(%rbp)
.Lbb2379:
	movl $0, %r10d
.Lbb2380:
	movl %r10d, -2888(%rbp)
	movq 120(%rsi), %r11
	movq %r11, -2872(%rbp)
	cmpq $0, %r11
	jz .Lbb2384
	movq -16(%r11), %r10
	movq %r10, -2864(%rbp)
	movl -2888(%rbp), %r10d
	movq $6917529027641081858, %r11
	movq %r11, -2856(%rbp)
	movq -2864(%rbp), %r11
	andq -2856(%rbp), %r11
	movq %r11, -2880(%rbp)
	movq -2872(%rbp), %r11
	cmpq $0, -2880(%rbp)
	jnz .Lbb2383
	movq -32(%r11), %r11
	cmpq $2, %r11
	jb .Lbb2384
.Lbb2383:
	movq %r8, %rdx
	.loc 1 276
	movl $0, %ecx
	movq %rsi, %r13
	movq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	callq myl_qbe_rc_unique_field
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %r8d
	movl -2888(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	cmpl $0, %r8d
	jz .Lbb2692
.Lbb2384:
	movq 120(%rsi), %r8
	movq %r8, -2920(%rbp)
	movq 128(%rsi), %r11
	movq %r11, -2896(%rbp)
	cmpl $0, %r10d
	jnz .Lbb2386
	movl %r10d, -2940(%rbp)
	jmp .Lbb2391
.Lbb2386:
	testl $28, %r14d
	jnz .Lbb2389
	.loc 1 278
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2896(%rbp), %r11
	movq -2920(%rbp), %r8
	movq -3648(%rbp), %rdx
	movl $0, -2940(%rbp)
	jmp .Lbb2391
.Lbb2389:
	.loc 1 278
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -2896(%rbp), %r11
	movq -2920(%rbp), %r8
	movq -3648(%rbp), %rdx
	movl $0, -2940(%rbp)
.Lbb2391:
	cmpq $0, %r11
	jge .Lbb2395
	movq (%r8), %r10
	movq $9223372036854775807, %r8
	cmpq %r8, %r10
	ja .Lbb2412
	movq %r11, %r8
	addq %r10, %r8
	movq %r8, -2936(%rbp)
	movq %r10, %r8
	xorq -2936(%rbp), %r8
	movq %r8, -2912(%rbp)
	movq %r11, %r8
	xorq -2936(%rbp), %r8
	movq %r8, -2904(%rbp)
	movq -2912(%rbp), %r8
	andq -2904(%rbp), %r8
	movq %r8, -2928(%rbp)
	movq -2920(%rbp), %r8
	cmpq $0, -2928(%rbp)
	jl .Lbb2410
	movq -2936(%rbp), %r11
.Lbb2395:
	movq -6072(%rbp), %r10
	movq %r10, -5528(%rbp)
	movq -6064(%rbp), %r10
	movq %r10, -5520(%rbp)
	movq (%r8), %r10
	cmpq %r10, %r11
	jae .Lbb2408
	movq 32(%r8), %r10
	imulq $16, %r11, %r11
	movq -5528(%rbp), %r8
	movq %r8, 0(%r10, %r11, 1)
	movq -5520(%rbp), %r8
	movq %r8, 8(%r10, %r11, 1)
	movl -2940(%rbp), %r10d
	movl -2944(%rbp), %r8d
	movq 128(%rsi), %r11
	movq %r11, -2952(%rbp)
	cmpl $0, %r10d
	jnz .Lbb2398
	xchgl %r15d, %r10d
	jmp .Lbb2403
.Lbb2398:
	testl $28, %r14d
	jnz .Lbb2401
	.loc 1 294
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2944(%rbp), %r8d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl %r15d, %r10d
	movl $0, %r15d
	jmp .Lbb2403
.Lbb2401:
	.loc 1 294
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r15d, %r10d
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -2944(%rbp), %r8d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r15d
.Lbb2403:
	movq $9223372036854775806, %r11
	movq %r11, -2960(%rbp)
	movq -2952(%rbp), %r11
	cmpq -2960(%rbp), %r11
	jg .Lbb2406
	addq $1, %r11
	movq %r11, 128(%rsi)
	xchgl %r15d, %r10d
	xchgl %r14d, %r9d
	movl $1, %r11d
	jmp .Lbb2674
.Lbb2406:
	movq %r11, %rdx
	.loc 1 296
	movl $64, %r8d
	movl $1, %ecx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2408:
	movq %r10, %rdx
	.loc 1 291
	movq %r11, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb2410:
	movq %r10, %rsi
	movq %r11, %rcx
	.loc 1 287
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2412:
	movq %r10, %rsi
	.loc 1 285
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb2414:
	movq -2776(%rbp), %rdx
	.loc 1 270
	movq %r11, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb2416:
	movq %r11, %rcx
	movq %r10, %rsi
	.loc 1 267
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2418:
	movq -2736(%rbp), %rsi
	.loc 1 265
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb2420:
	movq -2688(%rbp), %rcx
	movq -2696(%rbp), %rdx
	.loc 1 258
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2422:
	xchgl %r14d, %r15d
	xchgl %r12d, %r10d
	xchgl %r9d, %r12d
	movq 128(%rsi), %r11
	movq %r11, -2968(%rbp)
	cmpl $0, %r15d
	jz .Lbb2430
	movl %r10d, %r15d
	testl $28, %r14d
	jnz .Lbb2428
	.loc 1 232
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl %r15d, %r10d
	movl $0, %r15d
	jmp .Lbb2430
.Lbb2428:
	.loc 1 232
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r15d, %r10d
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r15d
.Lbb2430:
	movq $-9223372036854775807, %r11
	movq %r11, -2976(%rbp)
	movq -2968(%rbp), %r11
	cmpq -2976(%rbp), %r11
	jl .Lbb2433
	subq $1, %r11
	movq %r11, 128(%rsi)
	xchgl %r15d, %r10d
	xchgl %r14d, %r9d
	movl $1, %r11d
	jmp .Lbb2674
.Lbb2433:
	movq %r11, %rdx
	.loc 1 234
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2435:
	xchgl %r14d, %r15d
	xchgl %r12d, %r10d
	xchgl %r9d, %r12d
	movq -3824(%rbp), %rdx
	movq $0, -5560(%rbp)
	movq $0, -5552(%rbp)
	movl $1, -5560(%rbp)
	movb $0, -5552(%rbp)
	movq -5560(%rbp), %r11
	movq %r11, -6072(%rbp)
	movq -5552(%rbp), %r11
	movq %r11, -6064(%rbp)
	cmpl $0, %r15d
	jnz .Lbb2438
	xchgl %r10d, %r15d
	jmp .Lbb2444
.Lbb2438:
	movl %r10d, %r15d
	testl $28, %r14d
	jnz .Lbb2442
	.loc 1 193
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb2444
.Lbb2442:
	.loc 1 193
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movl $0, %r10d
.Lbb2444:
	cmpl $0, %r10d
	jz .Lbb2462
	testl $28, %r14d
	jnz .Lbb2454
	movq -7016(%rbp), %r11
	cmpq $0, %r11
	jz .Lbb2453
	movq -16(%r11), %r10
	movq %r10, -2984(%rbp)
	movq $4611686018427387906, %r10
	movq %r10, -2992(%rbp)
	movq -2984(%rbp), %r10
	andq -2992(%rbp), %r10
	cmpq $0, %r10
	jnz .Lbb2452
	movq -32(%r11), %r10
	subq $1, %r10
	movq %r10, -3000(%rbp)
	jnz .Lbb2451
	movq -24(%r11), %r10
	movq %r10, -3008(%rbp)
	movq -3000(%rbp), %r10
	cmpq $0, -3008(%rbp)
	jnz .Lbb2451
	.loc 1 194
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	jmp .Lbb2453
.Lbb2451:
	movq %r10, -32(%r11)
.Lbb2452:
	movq $0, -7016(%rbp)
.Lbb2453:
	movl $0, %r10d
	jmp .Lbb2462
.Lbb2454:
	movq -7016(%rbp), %r11
	cmpq $0, %r11
	jz .Lbb2461
	movq -16(%r11), %r10
	movq %r10, -3016(%rbp)
	movq $4611686018427387906, %r10
	movq %r10, -3024(%rbp)
	movq -3016(%rbp), %r10
	andq -3024(%rbp), %r10
	cmpq $0, %r10
	jnz .Lbb2460
	movq -24(%r11), %r10
	subq $1, %r10
	movq %r10, -3032(%rbp)
	jnz .Lbb2459
	movq -32(%r11), %r10
	movq %r10, -3040(%rbp)
	movq -3032(%rbp), %r10
	cmpq $0, -3040(%rbp)
	jnz .Lbb2459
	.loc 1 194
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	jmp .Lbb2461
.Lbb2459:
	movq %r10, -24(%r11)
.Lbb2460:
	movq $0, -7016(%rbp)
.Lbb2461:
	movl $0, %r10d
.Lbb2462:
	movl %r10d, -3124(%rbp)
	movq 120(%rsi), %r11
	movq %r11, -3064(%rbp)
	cmpq $0, %r11
	jz .Lbb2466
	movq -16(%r11), %r10
	movq %r10, -3056(%rbp)
	movl -3124(%rbp), %r10d
	movq $6917529027641081858, %r11
	movq %r11, -3048(%rbp)
	movq -3056(%rbp), %r11
	andq -3048(%rbp), %r11
	movq %r11, -3072(%rbp)
	movq -3064(%rbp), %r11
	cmpq $0, -3072(%rbp)
	jnz .Lbb2465
	movq -32(%r11), %r11
	cmpq $2, %r11
	jb .Lbb2466
.Lbb2465:
	.loc 1 194
	movl $0, %ecx
	movq %rsi, %r13
	movq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	callq myl_qbe_rc_unique_field
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %edx
	movl -3124(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	cmpl $0, %edx
	jz .Lbb2692
.Lbb2466:
	movq 120(%rsi), %rdx
	movq %rdx, -3104(%rbp)
	movq 128(%rsi), %r11
	movq %r11, -3080(%rbp)
	cmpl $0, %r10d
	jnz .Lbb2468
	movl %r10d, -3128(%rbp)
	jmp .Lbb2473
.Lbb2468:
	testl $28, %r14d
	jnz .Lbb2471
	.loc 1 196
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3080(%rbp), %r11
	movq -3104(%rbp), %rdx
	movl $0, -3128(%rbp)
	jmp .Lbb2473
.Lbb2471:
	.loc 1 196
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3080(%rbp), %r11
	movq -3104(%rbp), %rdx
	movl $0, -3128(%rbp)
.Lbb2473:
	cmpq $0, %r11
	jge .Lbb2477
	movq (%rdx), %r10
	movq $9223372036854775807, %rdx
	cmpq %rdx, %r10
	ja .Lbb2494
	movq %r11, %rdx
	addq %r10, %rdx
	movq %rdx, -3120(%rbp)
	movq %r10, %rdx
	xorq -3120(%rbp), %rdx
	movq %rdx, -3096(%rbp)
	movq %r11, %rdx
	xorq -3120(%rbp), %rdx
	movq %rdx, -3088(%rbp)
	movq -3096(%rbp), %rdx
	andq -3088(%rbp), %rdx
	movq %rdx, -3112(%rbp)
	movq -3104(%rbp), %rdx
	cmpq $0, -3112(%rbp)
	jl .Lbb2492
	movq -3120(%rbp), %r11
.Lbb2477:
	movq -6072(%rbp), %r10
	movq %r10, -5544(%rbp)
	movq -6064(%rbp), %r10
	movq %r10, -5536(%rbp)
	movq (%rdx), %r10
	cmpq %r10, %r11
	jae .Lbb2490
	movq 32(%rdx), %r10
	imulq $16, %r11, %r11
	movq -5544(%rbp), %rdx
	movq %rdx, 0(%r10, %r11, 1)
	movq -5536(%rbp), %rdx
	movq %rdx, 8(%r10, %r11, 1)
	movl -3128(%rbp), %r10d
	movq -3648(%rbp), %rdx
	movq 128(%rsi), %r11
	movq %r11, -3136(%rbp)
	cmpl $0, %r10d
	jnz .Lbb2480
	xchgl %r15d, %r10d
	jmp .Lbb2485
.Lbb2480:
	testl $28, %r14d
	jnz .Lbb2483
	.loc 1 212
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl %r15d, %r10d
	movl $0, %r15d
	jmp .Lbb2485
.Lbb2483:
	.loc 1 212
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r15d, %r10d
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r15d
.Lbb2485:
	movq $9223372036854775806, %r11
	movq %r11, -3144(%rbp)
	movq -3136(%rbp), %r11
	cmpq -3144(%rbp), %r11
	jg .Lbb2488
	addq $1, %r11
	movq %r11, 128(%rsi)
	xchgl %r15d, %r10d
	xchgl %r14d, %r9d
	movl $1, %r11d
	jmp .Lbb2674
.Lbb2488:
	movq %r11, %rdx
	.loc 1 214
	movl $64, %r8d
	movl $1, %ecx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2490:
	movq %r10, %rdx
	.loc 1 209
	movq %r11, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb2492:
	movq %r10, %rsi
	movq %r11, %rcx
	.loc 1 205
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2494:
	movq %r10, %rsi
	.loc 1 203
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb2496:
	xchgl %r14d, %r15d
	xchgl %r12d, %r10d
	xchgl %r9d, %r12d
	movq -3824(%rbp), %rdx
	movq $0, -5592(%rbp)
	movq $0, -5584(%rbp)
	movl $1, -5592(%rbp)
	movb $1, -5584(%rbp)
	movq -5592(%rbp), %r11
	movq %r11, -6072(%rbp)
	movq -5584(%rbp), %r11
	movq %r11, -6064(%rbp)
	cmpl $0, %r15d
	jnz .Lbb2499
	xchgl %r10d, %r15d
	jmp .Lbb2505
.Lbb2499:
	movl %r10d, %r15d
	testl $28, %r14d
	jnz .Lbb2503
	.loc 1 151
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb2505
.Lbb2503:
	.loc 1 151
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movl $0, %r10d
.Lbb2505:
	cmpl $0, %r10d
	jz .Lbb2523
	testl $28, %r14d
	jnz .Lbb2515
	movq -7016(%rbp), %r11
	cmpq $0, %r11
	jz .Lbb2514
	movq -16(%r11), %r10
	movq %r10, -3152(%rbp)
	movq $4611686018427387906, %r10
	movq %r10, -3160(%rbp)
	movq -3152(%rbp), %r10
	andq -3160(%rbp), %r10
	cmpq $0, %r10
	jnz .Lbb2513
	movq -32(%r11), %r10
	subq $1, %r10
	movq %r10, -3168(%rbp)
	jnz .Lbb2512
	movq -24(%r11), %r10
	movq %r10, -3176(%rbp)
	movq -3168(%rbp), %r10
	cmpq $0, -3176(%rbp)
	jnz .Lbb2512
	.loc 1 152
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	jmp .Lbb2514
.Lbb2512:
	movq %r10, -32(%r11)
.Lbb2513:
	movq $0, -7016(%rbp)
.Lbb2514:
	movl $0, %r10d
	jmp .Lbb2523
.Lbb2515:
	movq -7016(%rbp), %r11
	cmpq $0, %r11
	jz .Lbb2522
	movq -16(%r11), %r10
	movq %r10, -3184(%rbp)
	movq $4611686018427387906, %r10
	movq %r10, -3192(%rbp)
	movq -3184(%rbp), %r10
	andq -3192(%rbp), %r10
	cmpq $0, %r10
	jnz .Lbb2521
	movq -24(%r11), %r10
	subq $1, %r10
	movq %r10, -3200(%rbp)
	jnz .Lbb2520
	movq -32(%r11), %r10
	movq %r10, -3208(%rbp)
	movq -3200(%rbp), %r10
	cmpq $0, -3208(%rbp)
	jnz .Lbb2520
	.loc 1 152
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	jmp .Lbb2522
.Lbb2520:
	movq %r10, -24(%r11)
.Lbb2521:
	movq $0, -7016(%rbp)
.Lbb2522:
	movl $0, %r10d
.Lbb2523:
	movl %r10d, -3292(%rbp)
	movq 120(%rsi), %r11
	movq %r11, -3232(%rbp)
	cmpq $0, %r11
	jz .Lbb2527
	movq -16(%r11), %r10
	movq %r10, -3224(%rbp)
	movl -3292(%rbp), %r10d
	movq $6917529027641081858, %r11
	movq %r11, -3216(%rbp)
	movq -3224(%rbp), %r11
	andq -3216(%rbp), %r11
	movq %r11, -3240(%rbp)
	movq -3232(%rbp), %r11
	cmpq $0, -3240(%rbp)
	jnz .Lbb2526
	movq -32(%r11), %r11
	cmpq $2, %r11
	jb .Lbb2527
.Lbb2526:
	.loc 1 152
	movl $0, %ecx
	movq %rsi, %r13
	movq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	callq myl_qbe_rc_unique_field
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %edx
	movl -3292(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	cmpl $0, %edx
	jz .Lbb2692
.Lbb2527:
	movq 120(%rsi), %rdx
	movq %rdx, -3272(%rbp)
	movq 128(%rsi), %r11
	movq %r11, -3248(%rbp)
	cmpl $0, %r10d
	jnz .Lbb2529
	movl %r10d, -3296(%rbp)
	jmp .Lbb2534
.Lbb2529:
	testl $28, %r14d
	jnz .Lbb2532
	.loc 1 154
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3248(%rbp), %r11
	movq -3272(%rbp), %rdx
	movl $0, -3296(%rbp)
	jmp .Lbb2534
.Lbb2532:
	.loc 1 154
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3248(%rbp), %r11
	movq -3272(%rbp), %rdx
	movl $0, -3296(%rbp)
.Lbb2534:
	cmpq $0, %r11
	jge .Lbb2538
	movq (%rdx), %r10
	movq $9223372036854775807, %rdx
	cmpq %rdx, %r10
	ja .Lbb2555
	movq %r11, %rdx
	addq %r10, %rdx
	movq %rdx, -3288(%rbp)
	movq %r10, %rdx
	xorq -3288(%rbp), %rdx
	movq %rdx, -3264(%rbp)
	movq %r11, %rdx
	xorq -3288(%rbp), %rdx
	movq %rdx, -3256(%rbp)
	movq -3264(%rbp), %rdx
	andq -3256(%rbp), %rdx
	movq %rdx, -3280(%rbp)
	movq -3272(%rbp), %rdx
	cmpq $0, -3280(%rbp)
	jl .Lbb2553
	movq -3288(%rbp), %r11
.Lbb2538:
	movq -6072(%rbp), %r10
	movq %r10, -5576(%rbp)
	movq -6064(%rbp), %r10
	movq %r10, -5568(%rbp)
	movq (%rdx), %r10
	cmpq %r10, %r11
	jae .Lbb2551
	movq 32(%rdx), %r10
	imulq $16, %r11, %r11
	movq -5576(%rbp), %rdx
	movq %rdx, 0(%r10, %r11, 1)
	movq -5568(%rbp), %rdx
	movq %rdx, 8(%r10, %r11, 1)
	movl -3296(%rbp), %r10d
	movq -3648(%rbp), %rdx
	movq 128(%rsi), %r11
	movq %r11, -3304(%rbp)
	cmpl $0, %r10d
	jnz .Lbb2541
	xchgl %r15d, %r10d
	jmp .Lbb2546
.Lbb2541:
	testl $28, %r14d
	jnz .Lbb2544
	.loc 1 170
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl %r15d, %r10d
	movl $0, %r15d
	jmp .Lbb2546
.Lbb2544:
	.loc 1 170
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r15d, %r10d
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r15d
.Lbb2546:
	movq $9223372036854775806, %r11
	movq %r11, -3312(%rbp)
	movq -3304(%rbp), %r11
	cmpq -3312(%rbp), %r11
	jg .Lbb2549
	addq $1, %r11
	movq %r11, 128(%rsi)
	xchgl %r15d, %r10d
	xchgl %r14d, %r9d
	movl $1, %r11d
	jmp .Lbb2674
.Lbb2549:
	movq %r11, %rdx
	.loc 1 172
	movl $64, %r8d
	movl $1, %ecx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2551:
	movq %r10, %rdx
	.loc 1 167
	movq %r11, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb2553:
	movq %r10, %rsi
	movq %r11, %rcx
	.loc 1 163
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2555:
	movq %r10, %rsi
	.loc 1 161
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb2557:
	xchgl %r14d, %r15d
	xchgl %r12d, %r10d
	xchgl %r9d, %r12d
	movq -3824(%rbp), %rdx
	movq $0, -5624(%rbp)
	movq $0, -5616(%rbp)
	movl $0, -5624(%rbp)
	movq -5624(%rbp), %r11
	movq %r11, -6072(%rbp)
	movq -5616(%rbp), %r11
	movq %r11, -6064(%rbp)
	cmpl $0, %r15d
	jnz .Lbb2560
	xchgl %r10d, %r15d
	jmp .Lbb2566
.Lbb2560:
	movl %r10d, %r15d
	testl $28, %r14d
	jnz .Lbb2564
	.loc 1 109
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb2566
.Lbb2564:
	.loc 1 109
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movl $0, %r10d
.Lbb2566:
	cmpl $0, %r10d
	jz .Lbb2584
	testl $28, %r14d
	jnz .Lbb2576
	movq -7016(%rbp), %r11
	cmpq $0, %r11
	jz .Lbb2575
	movq -16(%r11), %r10
	movq %r10, -3320(%rbp)
	movq $4611686018427387906, %r10
	movq %r10, -3328(%rbp)
	movq -3320(%rbp), %r10
	andq -3328(%rbp), %r10
	cmpq $0, %r10
	jnz .Lbb2574
	movq -32(%r11), %r10
	subq $1, %r10
	movq %r10, -3336(%rbp)
	jnz .Lbb2573
	movq -24(%r11), %r10
	movq %r10, -3344(%rbp)
	movq -3336(%rbp), %r10
	cmpq $0, -3344(%rbp)
	jnz .Lbb2573
	.loc 1 110
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	jmp .Lbb2575
.Lbb2573:
	movq %r10, -32(%r11)
.Lbb2574:
	movq $0, -7016(%rbp)
.Lbb2575:
	movl $0, %r10d
	jmp .Lbb2584
.Lbb2576:
	movq -7016(%rbp), %r11
	cmpq $0, %r11
	jz .Lbb2583
	movq -16(%r11), %r10
	movq %r10, -3352(%rbp)
	movq $4611686018427387906, %r10
	movq %r10, -3360(%rbp)
	movq -3352(%rbp), %r10
	andq -3360(%rbp), %r10
	cmpq $0, %r10
	jnz .Lbb2582
	movq -24(%r11), %r10
	subq $1, %r10
	movq %r10, -3368(%rbp)
	jnz .Lbb2581
	movq -32(%r11), %r10
	movq %r10, -3376(%rbp)
	movq -3368(%rbp), %r10
	cmpq $0, -3376(%rbp)
	jnz .Lbb2581
	.loc 1 110
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	jmp .Lbb2583
.Lbb2581:
	movq %r10, -24(%r11)
.Lbb2582:
	movq $0, -7016(%rbp)
.Lbb2583:
	movl $0, %r10d
.Lbb2584:
	movl %r10d, -3460(%rbp)
	movq 120(%rsi), %r11
	movq %r11, -3400(%rbp)
	cmpq $0, %r11
	jz .Lbb2588
	movq -16(%r11), %r10
	movq %r10, -3392(%rbp)
	movl -3460(%rbp), %r10d
	movq $6917529027641081858, %r11
	movq %r11, -3384(%rbp)
	movq -3392(%rbp), %r11
	andq -3384(%rbp), %r11
	movq %r11, -3408(%rbp)
	movq -3400(%rbp), %r11
	cmpq $0, -3408(%rbp)
	jnz .Lbb2587
	movq -32(%r11), %r11
	cmpq $2, %r11
	jb .Lbb2588
.Lbb2587:
	.loc 1 110
	movl $0, %ecx
	movq %rsi, %r13
	movq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	callq myl_qbe_rc_unique_field
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %edx
	movl -3460(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	cmpl $0, %edx
	jz .Lbb2692
.Lbb2588:
	movq 120(%rsi), %rdx
	movq %rdx, -3440(%rbp)
	movq 128(%rsi), %r11
	movq %r11, -3416(%rbp)
	cmpl $0, %r10d
	jnz .Lbb2590
	movl %r10d, -3464(%rbp)
	jmp .Lbb2595
.Lbb2590:
	testl $28, %r14d
	jnz .Lbb2593
	.loc 1 112
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3416(%rbp), %r11
	movq -3440(%rbp), %rdx
	movl $0, -3464(%rbp)
	jmp .Lbb2595
.Lbb2593:
	.loc 1 112
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3416(%rbp), %r11
	movq -3440(%rbp), %rdx
	movl $0, -3464(%rbp)
.Lbb2595:
	cmpq $0, %r11
	jge .Lbb2599
	movq (%rdx), %r10
	movq $9223372036854775807, %rdx
	cmpq %rdx, %r10
	ja .Lbb2615
	movq %r11, %rdx
	addq %r10, %rdx
	movq %rdx, -3456(%rbp)
	movq %r10, %rdx
	xorq -3456(%rbp), %rdx
	movq %rdx, -3432(%rbp)
	movq %r11, %rdx
	xorq -3456(%rbp), %rdx
	movq %rdx, -3424(%rbp)
	movq -3432(%rbp), %rdx
	andq -3424(%rbp), %rdx
	movq %rdx, -3448(%rbp)
	movq -3440(%rbp), %rdx
	cmpq $0, -3448(%rbp)
	jl .Lbb2613
	movq -3456(%rbp), %r11
.Lbb2599:
	movq -6072(%rbp), %r10
	movq %r10, -5608(%rbp)
	movq -6064(%rbp), %r10
	movq %r10, -5600(%rbp)
	movq (%rdx), %r10
	cmpq %r10, %r11
	jae .Lbb2611
	movq 32(%rdx), %r10
	imulq $16, %r11, %r11
	movq -5608(%rbp), %rdx
	movq %rdx, 0(%r10, %r11, 1)
	movq -5600(%rbp), %rdx
	movq %rdx, 8(%r10, %r11, 1)
	movl -3464(%rbp), %r10d
	movq -3648(%rbp), %rdx
	movq 128(%rsi), %r11
	movq %r11, -3472(%rbp)
	cmpl $0, %r10d
	jz .Lbb2606
	testl $28, %r14d
	jnz .Lbb2604
	.loc 1 128
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb2606
.Lbb2604:
	.loc 1 128
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb2606:
	movq $9223372036854775806, %r11
	movq %r11, -3480(%rbp)
	movq -3472(%rbp), %r11
	cmpq -3480(%rbp), %r11
	jg .Lbb2609
	addq $1, %r11
	movq %r11, 128(%rsi)
	xchgl %r14d, %r9d
	movl $1, %r11d
	jmp .Lbb2674
.Lbb2609:
	movq %r11, %rdx
	.loc 1 130
	movl $64, %r8d
	movl $1, %ecx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2611:
	movq %r10, %rdx
	.loc 1 125
	movq %r11, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb2613:
	movq %r10, %rsi
	movq %r11, %rcx
	.loc 1 121
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2615:
	movq %r10, %rsi
	.loc 1 119
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb2617:
	xchgl %r14d, %r15d
	.loc 1 63
	movq %rsi, %r13
	leaq -6144(%rbp), %rsi
	movq %rdi, %r12
	callq myl_f_cb51e0dd7840af78b8d3f65cd883ca525c8c73ff445227a508c4c557b220dad4
	movl %r15d, %r10d
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, %r11
	movq %rdx, -3488(%rbp)
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3588(%rbp), %r15d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movq %r11, -7280(%rbp)
	movq -3488(%rbp), %r11
	movq %r11, -7272(%rbp)
	cmpl $0, %r10d
	jz .Lbb2624
	testl $28, %r14d
	jnz .Lbb2622
	.loc 1 63
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb2624
.Lbb2622:
	.loc 1 63
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movl $0, %r10d
.Lbb2624:
	movq -7280(%rbp), %r11
	movq %r11, -6104(%rbp)
	movq -7272(%rbp), %r11
	movq %r11, -6096(%rbp)
	movq -6104(%rbp), %r11
	movq %r11, -6088(%rbp)
	movq -6096(%rbp), %r11
	movq %r11, -6080(%rbp)
	cmpl $0, %r10d
	jz .Lbb2630
	testl $28, %r14d
	jnz .Lbb2628
	.loc 1 68
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movl $0, %r10d
	jmp .Lbb2630
.Lbb2628:
	.loc 1 68
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	movl $0, %r10d
.Lbb2630:
	cmpl $0, %r10d
	jz .Lbb2648
	testl $28, %r14d
	jnz .Lbb2640
	movq -7016(%rbp), %r11
	cmpq $0, %r11
	jz .Lbb2639
	movq -16(%r11), %r10
	movq %r10, -3496(%rbp)
	movq $4611686018427387906, %r10
	movq %r10, -3504(%rbp)
	movq -3496(%rbp), %r10
	andq -3504(%rbp), %r10
	cmpq $0, %r10
	jnz .Lbb2638
	movq -32(%r11), %r10
	subq $1, %r10
	movq %r10, -3512(%rbp)
	jnz .Lbb2637
	movq -24(%r11), %r10
	movq %r10, -3520(%rbp)
	movq -3512(%rbp), %r10
	cmpq $0, -3520(%rbp)
	jnz .Lbb2637
	.loc 1 69
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	jmp .Lbb2639
.Lbb2637:
	movq %r10, -32(%r11)
.Lbb2638:
	movq $0, -7016(%rbp)
.Lbb2639:
	movl $0, %r10d
	jmp .Lbb2648
.Lbb2640:
	movq -7016(%rbp), %r11
	cmpq $0, %r11
	jz .Lbb2647
	movq -16(%r11), %r10
	movq %r10, -3528(%rbp)
	movq $4611686018427387906, %r10
	movq %r10, -3536(%rbp)
	movq -3528(%rbp), %r10
	andq -3536(%rbp), %r10
	cmpq $0, %r10
	jnz .Lbb2646
	movq -24(%r11), %r10
	subq $1, %r10
	movq %r10, -3544(%rbp)
	jnz .Lbb2645
	movq -32(%r11), %r10
	movq %r10, -3552(%rbp)
	movq -3544(%rbp), %r10
	cmpq $0, -3552(%rbp)
	jnz .Lbb2645
	.loc 1 69
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3824(%rbp), %rdx
	jmp .Lbb2647
.Lbb2645:
	movq %r10, -24(%r11)
.Lbb2646:
	movq $0, -7016(%rbp)
.Lbb2647:
	movl $0, %r10d
.Lbb2648:
	movl %r10d, -3592(%rbp)
	movq 120(%rsi), %r11
	movq %r11, -3576(%rbp)
	cmpq $0, %r11
	jz .Lbb2652
	movq -16(%r11), %r10
	movq %r10, -3568(%rbp)
	movl -3592(%rbp), %r10d
	movq $6917529027641081858, %r11
	movq %r11, -3560(%rbp)
	movq -3568(%rbp), %r11
	andq -3560(%rbp), %r11
	movq %r11, -3584(%rbp)
	movq -3576(%rbp), %r11
	cmpq $0, -3584(%rbp)
	jnz .Lbb2651
	movq -32(%r11), %r11
	cmpq $2, %r11
	jb .Lbb2652
.Lbb2651:
	.loc 1 69
	movl $0, %ecx
	movq %rsi, %r13
	movq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	callq myl_qbe_rc_unique_field
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %edx
	movl -3592(%rbp), %r10d
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	cmpl $0, %edx
	jz .Lbb2692
.Lbb2652:
	movq 120(%rsi), %rdx
	movq %rdx, -3624(%rbp)
	movq 128(%rsi), %r11
	movq %r11, -3600(%rbp)
	cmpl $0, %r10d
	jnz .Lbb2654
	movl %r10d, -3660(%rbp)
	jmp .Lbb2659
.Lbb2654:
	testl $28, %r14d
	jnz .Lbb2657
	.loc 1 71
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3600(%rbp), %r11
	movq -3624(%rbp), %rdx
	movl $0, -3660(%rbp)
	jmp .Lbb2659
.Lbb2657:
	.loc 1 71
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3600(%rbp), %r11
	movq -3624(%rbp), %rdx
	movl $0, -3660(%rbp)
.Lbb2659:
	cmpq $0, %r11
	jge .Lbb2663
	movq (%rdx), %r10
	movq $9223372036854775807, %rdx
	cmpq %rdx, %r10
	ja .Lbb2690
	movq %r11, %rdx
	addq %r10, %rdx
	movq %rdx, -3640(%rbp)
	movq %r10, %rdx
	xorq -3640(%rbp), %rdx
	movq %rdx, -3616(%rbp)
	movq %r11, %rdx
	xorq -3640(%rbp), %rdx
	movq %rdx, -3608(%rbp)
	movq -3616(%rbp), %rdx
	andq -3608(%rbp), %rdx
	movq %rdx, -3632(%rbp)
	movq -3624(%rbp), %rdx
	cmpq $0, -3632(%rbp)
	jl .Lbb2688
	movq -3640(%rbp), %r11
.Lbb2663:
	movq -6088(%rbp), %r10
	movq %r10, -5640(%rbp)
	movq -6080(%rbp), %r10
	movq %r10, -5632(%rbp)
	movq (%rdx), %r10
	cmpq %r10, %r11
	jae .Lbb2686
	movq 32(%rdx), %r10
	imulq $16, %r11, %r11
	movq -5640(%rbp), %rdx
	movq %rdx, 0(%r10, %r11, 1)
	movq -5632(%rbp), %rdx
	movq %rdx, 8(%r10, %r11, 1)
	movl -3660(%rbp), %r10d
	movq -3648(%rbp), %rdx
	movq 128(%rsi), %r11
	movq %r11, -3688(%rbp)
	cmpl $0, %r10d
	jnz .Lbb2666
	xchgl %r14d, %r9d
	jmp .Lbb2671
.Lbb2666:
	testl $28, %r14d
	jnz .Lbb2669
	.loc 1 87
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_drop
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl %r9d, %r14d
	movl -3676(%rbp), %r9d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	xchgl %r14d, %r9d
	movl $0, %r10d
	jmp .Lbb2671
.Lbb2669:
	.loc 1 87
	movq %rsi, %r13
	leaq -7016(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_4e6c1584b61f68a69271c693e65be720323e6bcb8d28e2f694592eed5c4c3f28_rcg_unloan
	movl %r14d, %r9d
	movq %r13, %rsi
	movq %r12, %rdi
	movl -3664(%rbp), %r13d
	movl -3668(%rbp), %r12d
	movl -3680(%rbp), %r8d
	movl -3672(%rbp), %ecx
	movl -3676(%rbp), %r14d
	movq -3656(%rbp), %rax
	movq -3648(%rbp), %rdx
	movl $0, %r10d
.Lbb2671:
	movq $9223372036854775806, %r11
	movq %r11, -3696(%rbp)
	movq -3688(%rbp), %r11
	cmpq -3696(%rbp), %r11
	jg .Lbb2684
	addq $1, %r11
	movq %r11, 128(%rsi)
	movl $1, %r11d
.Lbb2674:
	xorq $1, %r11
	movq -3704(%rbp), %r11
	jnz .Lbb2676
	movl %r10d, -100(%rbp)
	xchgl %r9d, %r15d
	xchgl %r12d, %r9d
	jmp .Lbb21
.Lbb2676:
	movl $0, -3840(%rbp)
	movl $2, -3840(%rbp)
	movl -6160(%rbp), %eax
	cmpl $0, %eax
	jnz .Lbb2678
	movq %rbx, %rdi
	jmp .Lbb2679
.Lbb2678:
	leaq -6184(%rbp), %rax
	movq %rax, -6152(%rbp)
	.loc 1 1700
	movl $1, %edx
	leaq -6152(%rbp), %rsi
	callq myl_qbe_rc_scopes_close
	movq %rbx, %rdi
.Lbb2679:
	cmpl $0, %r13d
	jz .Lbb2683
	testl $28, %r12d
	jnz .Lbb2682
	.loc 1 1700
	leaq -6144(%rbp), %rsi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_drop
	jmp .Lbb2683
.Lbb2682:
	.loc 1 1700
	leaq -6144(%rbp), %rsi
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_unloan
.Lbb2683:
	movq -3840(%rbp), %rax
	jmp .Lbb2693
.Lbb2684:
	movq %r11, %rdx
	.loc 1 89
	movl $64, %r8d
	movl $1, %ecx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2686:
	movq %r10, %rdx
	.loc 1 84
	movq %r11, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb2688:
	movq %r10, %rsi
	movq %r11, %rcx
	.loc 1 80
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2690:
	movq %r10, %rsi
	.loc 1 78
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb2692:
	.loc 1 1701
	movl $8, %edx
	movl $0, %esi
	leaq -7024(%rbp), %rdi
	callq memset
	movq -7024(%rbp), %rax
.Lbb2693:
	movq %rbp, %rsp
	subq $7376, %rsp
	popq %r15
	popq %r14
	popq %r13
	popq %r12
	popq %rbx
	leave
	ret
.Lbb2694:
	movq %rdx, %rcx
	.loc 1 44
	movl $64, %r8d
	movq %rcx, %rax
	movl $1, %ecx
	movq %rax, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2696:
	movq %rdx, %rcx
	movq -56(%rbp), %rdx
	.loc 1 39
	movq %rcx, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb2698:
	movq %r10, %rsi
	movq -64(%rbp), %rcx
	.loc 1 36
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2700:
	movq %r10, %rsi
	.loc 1 34
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb2702:
	movq %r10, %rsi
	movq %rbx, %rdi
	.loc 1 17
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2704:
	movq %r10, %rsi
	movq %rbx, %rdi
	.loc 1 15
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb2706:
	movq %rbx, %rdi
	.loc 1 8
	movl $64, %r8d
	movl $1, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2708:
	movq %rbx, %rdi
	.loc 1 1 1
	callq myl_qbe_fail_frame
	ud2
.type myl_f_a0e96f299197f34d601c1a9da1cbd514090305d2a21036d06ba179b733ea6e29, @function
.size myl_f_a0e96f299197f34d601c1a9da1cbd514090305d2a21036d06ba179b733ea6e29, .-myl_f_a0e96f299197f34d601c1a9da1cbd514090305d2a21036d06ba179b733ea6e29
/* end function myl_f_a0e96f299197f34d601c1a9da1cbd514090305d2a21036d06ba179b733ea6e29 */

.section .note.GNU-stack,"",@progbits
