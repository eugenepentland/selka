.file 1 "myl_f_bf0431d3d9e553eacefcb10ebb00251bb8b43354cc87fd12c99ceb5644f705d6"
.text
.balign 16
.globl myl_f_bf0431d3d9e553eacefcb10ebb00251bb8b43354cc87fd12c99ceb5644f705d6
myl_f_bf0431d3d9e553eacefcb10ebb00251bb8b43354cc87fd12c99ceb5644f705d6:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $712, %rsp
	pushq %rbx
	pushq %r12
	pushq %r13
	pushq %r14
	pushq %r15
	movq %rcx, %r15
	movq %rdx, %r13
	movq %rdi, %r12
	movq %rsi, %rdi
	movq %r15, -16(%rbp)
	.loc 1 1
	.loc 1 1
	movq $0, -88(%rbp)
	movq $0, -80(%rbp)
	movq $0, -72(%rbp)
	.loc 1 1
	movq %rdi, %rbx
	callq myl_qbe_heap
	movq %rbx, %rdi
	movq %rax, %rbx
	.loc 1 1
	movq %rdi, %r14
	callq myl_qbe_region_mark
	movq %r15, %rdx
	movq %r14, %rdi
	xchgq %rax, %r12
	movq (%r13), %rcx
	movq %rcx, %r8
	movq (%rdx), %rcx
	cmpq $0, %rcx
	jl .Lbb2
	movq %rcx, %rsi
	movq %r8, %rcx
	jmp .Lbb5
.Lbb2:
	movq (%r8), %rsi
	movq $9223372036854775807, %r9
	cmpq %r9, %rsi
	ja .Lbb145
	movq %rcx, %r9
	addq %rsi, %r9
	movq %rsi, %r10
	xorq %r9, %r10
	movq %rcx, %r11
	xorq %r9, %r11
	andq %r11, %r10
	cmpq $0, %r10
	jl .Lbb144
	movq %r9, %rsi
	movq %r8, %rcx
.Lbb5:
	movq (%rcx), %r8
	cmpq %r8, %rsi
	jb .Lbb8
	movq %r8, %rdx
	.loc 1 17
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb8:
	movq 32(%rcx), %rcx
	imulq $56, %rsi, %r8
	movq %rcx, %rsi
	addq %r8, %rsi
	movl (%rcx, %r8, 1), %ecx
	cmpq $0, %rcx
	jz .Lbb143
	cmpq $1, %rcx
	jz .Lbb142
	cmpq $2, %rcx
	jz .Lbb141
	cmpq $3, %rcx
	jz .Lbb140
	cmpq $4, %rcx
	jz .Lbb26
	cmpq $5, %rcx
	jz .Lbb25
	cmpq $6, %rcx
	jz .Lbb24
	cmpq $7, %rcx
	jz .Lbb23
	cmpq $8, %rcx
	jz .Lbb22
	cmpq $9, %rcx
	jz .Lbb21
	cmpq $10, %rcx
	jz .Lbb20
	movq %rax, %rbx
	jmp .Lbb132
.Lbb20:
	.loc 1 120
	callq myl_qbe_fail_assert
	ud2
.Lbb21:
	.loc 1 117
	callq myl_qbe_fail_assert
	ud2
.Lbb22:
	.loc 1 114
	callq myl_qbe_fail_assert
	ud2
.Lbb23:
	.loc 1 111
	callq myl_qbe_fail_assert
	ud2
.Lbb24:
	.loc 1 108
	callq myl_qbe_fail_assert
	ud2
.Lbb25:
	.loc 1 105
	callq myl_qbe_fail_assert
	ud2
.Lbb26:
	movq %rsi, %rcx
	movq 8(%rcx), %rsi
	movq %rsi, -152(%rbp)
	movq 16(%rcx), %rcx
	movq %rcx, -144(%rbp)
	movq (%r13), %rcx
	movq %rcx, %r8
	movq -152(%rbp), %rcx
	cmpq $0, %rcx
	jl .Lbb29
	movq %rcx, %rsi
	movq %r8, %rcx
	jmp .Lbb32
.Lbb29:
	movq (%r8), %rsi
	movq $9223372036854775807, %r9
	cmpq %r9, %rsi
	ja .Lbb139
	movq %rcx, %r9
	addq %rsi, %r9
	movq %rsi, %r10
	xorq %r9, %r10
	movq %rcx, %r11
	xorq %r9, %r11
	andq %r11, %r10
	cmpq $0, %r10
	jl .Lbb138
	movq %r9, %rsi
	movq %r8, %rcx
.Lbb32:
	movq (%rcx), %r8
	cmpq %r8, %rsi
	jb .Lbb35
	movq %r8, %rdx
	.loc 1 38
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb35:
	movq 32(%rcx), %rcx
	imulq $56, %rsi, %r8
	movq %rcx, %rsi
	addq %r8, %rsi
	movl (%rcx, %r8, 1), %ecx
	cmpq $0, %rcx
	jz .Lbb137
	cmpq $1, %rcx
	jz .Lbb136
	cmpq $2, %rcx
	jz .Lbb55
	cmpq $3, %rcx
	jz .Lbb54
	cmpq $4, %rcx
	jz .Lbb53
	cmpq $5, %rcx
	jz .Lbb52
	cmpq $6, %rcx
	jz .Lbb51
	cmpq $7, %rcx
	jz .Lbb50
	cmpq $8, %rcx
	jz .Lbb49
	cmpq $9, %rcx
	jz .Lbb48
	cmpq $10, %rcx
	jz .Lbb47
	movq %rax, %rbx
	jmp .Lbb132
.Lbb47:
	.loc 1 88
	callq myl_qbe_fail_assert
	ud2
.Lbb48:
	.loc 1 85
	callq myl_qbe_fail_assert
	ud2
.Lbb49:
	.loc 1 82
	callq myl_qbe_fail_assert
	ud2
.Lbb50:
	.loc 1 79
	callq myl_qbe_fail_assert
	ud2
.Lbb51:
	.loc 1 76
	callq myl_qbe_fail_assert
	ud2
.Lbb52:
	.loc 1 73
	callq myl_qbe_fail_assert
	ud2
.Lbb53:
	.loc 1 70
	callq myl_qbe_fail_assert
	ud2
.Lbb54:
	.loc 1 67
	movq %rdi, %r12
	callq myl_qbe_fail_assert
	ud2
.Lbb55:
	movq %r12, %rcx
	movq %rdi, %r12
	movq %rbx, %rdi
	movq 8(%rsi), %r8
	movq %r8, -136(%rbp)
	movq 16(%rsi), %r8
	movq %r8, -128(%rbp)
	movq 24(%rsi), %r8
	movq %r8, -120(%rbp)
	movq 32(%rsi), %r8
	movq %r8, -112(%rbp)
	movq 40(%rsi), %r8
	movq %r8, -104(%rbp)
	movq 48(%rsi), %rsi
	movq %rsi, -96(%rbp)
	movq %rax, %rbx
	movq -104(%rbp), %rax
	movq %rax, -384(%rbp)
	cmpq $0, %rax
	jz .Lbb63
	movq -16(%rax), %rsi
	movq $5764607523034234880, %r8
	andq %rsi, %r8
	cmpq $0, %r8
	jnz .Lbb65
	movq %rsi, %r8
	andq $2, %r8
	cmpq $0, %r8
	jnz .Lbb61
	movq -32(%rax), %r8
	addq $1, %r8
	jz .Lbb65
	movq %r8, -32(%rax)
.Lbb61:
	movq $2305843009213693954, %r8
	andq %rsi, %r8
	cmpq $0, %r8
	jnz .Lbb63
	movq $2305843009213693952, %r8
	orq %r8, %rsi
	movq %rsi, -16(%rax)
.Lbb63:
	movq %rax, -360(%rbp)
	movq %rbx, %rax
	jmp .Lbb69
.Lbb65:
	.loc 1 46
	movl $0, %r8d
	movq %rcx, %r15
	movq %rdx, %r14
	leaq -384(%rbp), %rdx
	leaq -360(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a_rcg_publish
	movq %r15, %rcx
	movq %r14, %rdx
	movq %r13, %rdi
	cmpl $0, %eax
	jnz .Lbb68
	.loc 1 46
	callq myl_rc_take_failure
	movq %r12, %rdi
	movl %eax, %esi
	.loc 1 46
	movq %rdi, %r12
	callq myl_qbe_rc_status
	movq %rbx, %rax
	movq %rax, %rbx
	jmp .Lbb132
.Lbb68:
	movq %rbx, %rax
.Lbb69:
	movq -360(%rbp), %rsi
	movq %rsi, -656(%rbp)
	movq -656(%rbp), %r14
	leaq -136(%rbp), %rsi
	movq %rsi, %r13
	addq $16, %r13
	movq %r13, -48(%rbp)
	movq %rax, %rbx
	movq -120(%rbp), %rax
	movq %rax, -376(%rbp)
	cmpq $0, %rax
	jz .Lbb76
	movq -16(%rax), %rsi
	movq $5764607523034234880, %r8
	andq %rsi, %r8
	cmpq $0, %r8
	jnz .Lbb78
	movq %rsi, %r8
	andq $2, %r8
	cmpq $0, %r8
	jnz .Lbb74
	movq -32(%rax), %r8
	addq $1, %r8
	jz .Lbb78
	movq %r8, -32(%rax)
.Lbb74:
	movq $2305843009213693954, %r8
	andq %rsi, %r8
	cmpq $0, %r8
	jnz .Lbb76
	movq $2305843009213693952, %r8
	orq %r8, %rsi
	movq %rsi, -16(%rax)
.Lbb76:
	movq %rax, -360(%rbp)
	movq %rbx, %rax
	jmp .Lbb82
.Lbb78:
	.loc 1 50
	movl $0, %r8d
	movq %rcx, %r15
	leaq -376(%rbp), %rdx
	leaq -360(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_publish
	movq %r15, %rcx
	movq %r13, %rdi
	movq -48(%rbp), %r13
	movq -16(%rbp), %rdx
	cmpl $0, %eax
	jnz .Lbb81
	.loc 1 50
	callq myl_rc_take_failure
	movq %r12, %rdi
	movl %eax, %esi
	.loc 1 50
	movq %rdi, %r12
	callq myl_qbe_rc_status
	movq %rbx, %rax
	movq %rax, %rbx
	jmp .Lbb132
.Lbb81:
	movq %rbx, %rax
.Lbb82:
	movq -360(%rbp), %rsi
	movq %rsi, -448(%rbp)
	movq -448(%rbp), %r15
	movq %r15, -24(%rbp)
	movq %rax, %rbx
	movq -144(%rbp), %rax
	movq %rax, -368(%rbp)
	cmpq $0, %rax
	jz .Lbb89
	movq -16(%rax), %rsi
	movq $5764607523034234880, %r8
	andq %rsi, %r8
	cmpq $0, %r8
	jnz .Lbb91
	movq %rsi, %r8
	andq $2, %r8
	cmpq $0, %r8
	jnz .Lbb87
	movq -32(%rax), %r8
	addq $1, %r8
	jz .Lbb91
	movq %r8, -32(%rax)
.Lbb87:
	movq $2305843009213693954, %r8
	andq %rsi, %r8
	cmpq $0, %r8
	jnz .Lbb89
	movq $2305843009213693952, %r8
	orq %r8, %rsi
	movq %rsi, -16(%rax)
.Lbb89:
	movq %rax, -360(%rbp)
	movq %rbx, %rax
	movq %r14, %rbx
	jmp .Lbb95
.Lbb91:
	.loc 1 53
	movl $0, %r8d
	movq %rcx, %r15
	leaq -368(%rbp), %rdx
	leaq -360(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_publish
	movq %r15, %rcx
	movq %r13, %rdi
	movq -24(%rbp), %r15
	movq -48(%rbp), %r13
	movq -16(%rbp), %rdx
	cmpl $0, %eax
	jnz .Lbb94
	.loc 1 53
	callq myl_rc_take_failure
	movq %r12, %rdi
	movl %eax, %esi
	.loc 1 53
	movq %rdi, %r12
	callq myl_qbe_rc_status
	movq %rbx, %rax
	movq %rax, %rbx
	jmp .Lbb132
.Lbb94:
	movq %rbx, %rax
	movq %r14, %rbx
.Lbb95:
	movq -360(%rbp), %rsi
	movq %rsi, -400(%rbp)
	movq -400(%rbp), %r14
	movq %r14, -32(%rbp)
	movq 8(%rdx), %rsi
	movq %rsi, -64(%rbp)
	movq 16(%rdx), %rdx
	movq %rdx, -56(%rbp)
	movq $0, -136(%rbp)
	leaq -136(%rbp), %r8
	movq %r8, %r9
	addq $8, %r9
	movq %r9, -40(%rbp)
	movq $0, -128(%rbp)
	movq $0, -120(%rbp)
	movq $0, -112(%rbp)
	movq $0, -104(%rbp)
	movq %rbx, -384(%rbp)
	movq %rbx, -384(%rbp)
	leaq -360(%rbp), %r10
	leaq -384(%rbp), %r8
	subq %r10, %r8
	leaq -384(%rbp), %r11
	leaq -360(%rbp), %r10
	subq %r11, %r10
	cmpq $8, %r8
	setb %r8b
	movzbl %r8b, %r8d
	cmpq $8, %r10
	setb %r10b
	movzbl %r10b, %r10d
	orl %r10d, %r8d
	jnz .Lbb100
	cmpq $0, %rbx
	jz .Lbb98
	movq -16(%rbx), %r8
	movq $5764607523034234881, %r10
	andq %r10, %r8
	cmpq $0, %r8
	jnz .Lbb100
.Lbb98:
	movq %rax, %rbx
	movq -384(%rbp), %rax
	movq %rax, -360(%rbp)
	movq $0, -384(%rbp)
	movq %rbx, %rax
	movq %r15, %rbx
	jmp .Lbb104
.Lbb100:
	movq %rax, %rbx
	.loc 1 58
	movq %rcx, %r14
	leaq -384(%rbp), %rdx
	leaq -360(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_a1fa53db408c85388cfd14badb361c2a89e74ce2a863fa83774cb6942b74317a_rcg_take
	movq %r14, %rcx
	movq %r13, %rdi
	movq -40(%rbp), %r9
	movq -56(%rbp), %rdx
	movq -64(%rbp), %rsi
	movq -32(%rbp), %r14
	movq -48(%rbp), %r13
	cmpl $0, %eax
	jnz .Lbb103
	.loc 1 58
	callq myl_rc_take_failure
	movq %r12, %rdi
	movl %eax, %esi
	.loc 1 58
	movq %rdi, %r12
	callq myl_qbe_rc_status
	movq %rbx, %rax
	movq %rax, %rbx
	jmp .Lbb132
.Lbb103:
	movq %rbx, %rax
	movq %r15, %rbx
.Lbb104:
	movq -360(%rbp), %r8
	movq %r8, -136(%rbp)
	movq %rbx, -376(%rbp)
	movq %rbx, -376(%rbp)
	leaq -360(%rbp), %r10
	leaq -376(%rbp), %r8
	subq %r10, %r8
	leaq -376(%rbp), %r11
	leaq -360(%rbp), %r10
	subq %r11, %r10
	cmpq $8, %r8
	setb %r8b
	movzbl %r8b, %r8d
	cmpq $8, %r10
	setb %r10b
	movzbl %r10b, %r10d
	orl %r10d, %r8d
	jnz .Lbb109
	cmpq $0, %rbx
	jz .Lbb107
	movq -16(%rbx), %r8
	movq $5764607523034234881, %r10
	andq %r10, %r8
	cmpq $0, %r8
	jnz .Lbb109
.Lbb107:
	movq %rax, %rbx
	movq -376(%rbp), %rax
	movq %rax, -360(%rbp)
	movq $0, -376(%rbp)
	movq %rbx, %rax
	movq %r14, %rbx
	jmp .Lbb113
.Lbb109:
	movq %rax, %rbx
	.loc 1 58
	movq %rcx, %r15
	leaq -376(%rbp), %rdx
	leaq -360(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_take
	movq %r15, %rcx
	movq %r13, %rdi
	movq -40(%rbp), %r9
	movq -56(%rbp), %rdx
	movq -64(%rbp), %rsi
	movq -48(%rbp), %r13
	cmpl $0, %eax
	jnz .Lbb112
	.loc 1 58
	callq myl_rc_take_failure
	movq %r12, %rdi
	movl %eax, %esi
	.loc 1 58
	movq %rdi, %r12
	callq myl_qbe_rc_status
	movq %rbx, %rax
	movq %rax, %rbx
	jmp .Lbb132
.Lbb112:
	movq %rbx, %rax
	movq %r14, %rbx
.Lbb113:
	movq -360(%rbp), %r8
	movq %r8, 0(%r9)
	movq %rbx, -368(%rbp)
	movq %rbx, -368(%rbp)
	leaq -360(%rbp), %r9
	leaq -368(%rbp), %r8
	subq %r9, %r8
	leaq -368(%rbp), %r10
	leaq -360(%rbp), %r9
	subq %r10, %r9
	cmpq $8, %r8
	setb %r8b
	movzbl %r8b, %r8d
	cmpq $8, %r9
	setb %r9b
	movzbl %r9b, %r9d
	orl %r9d, %r8d
	jnz .Lbb118
	cmpq $0, %rbx
	jz .Lbb116
	movq -16(%rbx), %r8
	movq $5764607523034234881, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb118
.Lbb116:
	movq %rax, %rbx
	movq -368(%rbp), %rax
	movq %rax, -360(%rbp)
	movq $0, -368(%rbp)
	movq %rbx, %rax
	movq %r13, %rbx
	jmp .Lbb122
.Lbb118:
	movq %rax, %rbx
	.loc 1 58
	movq %rcx, %r15
	leaq -368(%rbp), %rdx
	leaq -360(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_take
	movq %r15, %rcx
	movq %r14, %rdi
	movq -56(%rbp), %rdx
	movq -64(%rbp), %rsi
	cmpl $0, %eax
	jnz .Lbb121
	.loc 1 58
	callq myl_rc_take_failure
	movq %r12, %rdi
	movl %eax, %esi
	.loc 1 58
	movq %rdi, %r12
	callq myl_qbe_rc_status
	movq %rbx, %rax
	movq %rax, %rbx
	jmp .Lbb132
.Lbb121:
	movq %rbx, %rax
	movq %r13, %rbx
.Lbb122:
	movq -360(%rbp), %r8
	movq %r8, 0(%rbx)
	movq %rsi, -112(%rbp)
	movq %rdx, -104(%rbp)
	movq -136(%rbp), %rdx
	movq %rdx, -656(%rbp)
	movq -128(%rbp), %rdx
	movq %rdx, -648(%rbp)
	movq -120(%rbp), %rdx
	movq %rdx, -640(%rbp)
	movq -112(%rbp), %rdx
	movq %rdx, -632(%rbp)
	movq -104(%rbp), %rdx
	movq %rdx, -624(%rbp)
	movq -656(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb124
	movq -16(%rdx), %rdx
	movq $5764607523034234881, %rsi
	andq %rsi, %rdx
	cmpq $0, %rdx
	jnz .Lbb130
.Lbb124:
	movq -648(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb126
	movq -16(%rdx), %rdx
	movq $5764607523034234881, %rsi
	andq %rsi, %rdx
	cmpq $0, %rdx
	jnz .Lbb130
.Lbb126:
	movq -640(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb128
	movq -16(%rdx), %rdx
	movq $5764607523034234881, %rsi
	andq %rsi, %rdx
	cmpq $0, %rdx
	jnz .Lbb130
.Lbb128:
	movq -656(%rbp), %rcx
	movq %rcx, -360(%rbp)
	movq -648(%rbp), %rcx
	movq %rcx, -352(%rbp)
	movq -640(%rbp), %rcx
	movq %rcx, -344(%rbp)
	movq -632(%rbp), %rcx
	movq %rcx, -336(%rbp)
	movq %rax, %rbx
	movq -624(%rbp), %rax
	movq %rax, -328(%rbp)
	movq $0, -656(%rbp)
	movq $0, -648(%rbp)
	movq $0, -640(%rbp)
	movq $0, -632(%rbp)
	movq $0, -624(%rbp)
	movq %rbx, %rax
	jmp .Lbb134
.Lbb130:
	movq %rax, %rbx
	.loc 1 59
	leaq -656(%rbp), %rdx
	leaq -360(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_c000f22f7ee44dea31e81b0a933c1dec3a560f42212434ae24333c6a58c466f9_rcg_take
	movq %r13, %rdi
	cmpl $0, %eax
	jnz .Lbb133
	.loc 1 59
	callq myl_rc_take_failure
	movq %r12, %rdi
	movl %eax, %esi
	.loc 1 59
	callq myl_qbe_rc_status
.Lbb132:
	.loc 1 142
	movl $40, %edx
	movl $0, %esi
	leaq -696(%rbp), %rdi
	callq memset
	movq %rbx, %rax
	movq -696(%rbp), %rcx
	movq %rcx, 0(%rax)
	movq -688(%rbp), %rcx
	movq %rcx, 8(%rax)
	movq -680(%rbp), %rcx
	movq %rcx, 16(%rax)
	movq -672(%rbp), %rcx
	movq %rcx, 24(%rax)
	movq -664(%rbp), %rcx
	movq %rcx, 32(%rax)
	jmp .Lbb135
.Lbb133:
	movq %rbx, %rax
.Lbb134:
	movq -360(%rbp), %rcx
	movq %rcx, 0(%rax)
	movq -352(%rbp), %rcx
	movq %rcx, 8(%rax)
	movq -344(%rbp), %rcx
	movq %rcx, 16(%rax)
	movq -336(%rbp), %rcx
	movq %rcx, 24(%rax)
	movq -328(%rbp), %rcx
	movq %rcx, 32(%rax)
.Lbb135:
	popq %r15
	popq %r14
	popq %r13
	popq %r12
	popq %rbx
	leave
	ret
.Lbb136:
	.loc 1 64
	callq myl_qbe_fail_assert
	ud2
.Lbb137:
	.loc 1 61
	callq myl_qbe_fail_assert
	ud2
.Lbb138:
	.loc 1 35
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb139:
	.loc 1 33
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb140:
	.loc 1 102
	callq myl_qbe_fail_assert
	ud2
.Lbb141:
	.loc 1 99
	callq myl_qbe_fail_assert
	ud2
.Lbb142:
	.loc 1 96
	callq myl_qbe_fail_assert
	ud2
.Lbb143:
	.loc 1 93
	callq myl_qbe_fail_assert
	ud2
.Lbb144:
	.loc 1 14
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb145:
	.loc 1 12
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.type myl_f_bf0431d3d9e553eacefcb10ebb00251bb8b43354cc87fd12c99ceb5644f705d6, @function
.size myl_f_bf0431d3d9e553eacefcb10ebb00251bb8b43354cc87fd12c99ceb5644f705d6, .-myl_f_bf0431d3d9e553eacefcb10ebb00251bb8b43354cc87fd12c99ceb5644f705d6
/* end function myl_f_bf0431d3d9e553eacefcb10ebb00251bb8b43354cc87fd12c99ceb5644f705d6 */

.section .note.GNU-stack,"",@progbits
