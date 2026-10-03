.file 1 "myl_f_0d6e4079e36703ebd37c00722f5891d28b0e2811dc114b129215123adcce3605"
.text
.balign 16
.globl myl_f_0d6e4079e36703ebd37c00722f5891d28b0e2811dc114b129215123adcce3605
myl_f_0d6e4079e36703ebd37c00722f5891d28b0e2811dc114b129215123adcce3605:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $4248, %rsp
	pushq %rbx
	pushq %r12
	pushq %r13
	pushq %r14
	pushq %r15
	movq %rcx, -3400(%rbp)
	movq %rdx, -3320(%rbp)
	movq %rdi, %rbx
	movq %rbx, -2760(%rbp)
	movq $0, -4048(%rbp)
	movq $0, -4016(%rbp)
	movq 64(%rbx), %rax
	leaq -3432(%rbp), %rcx
	cmpq %rax, %rcx
	setb %al
	movzbq %al, %rax
	movl $2, %r12d
	movl %r12d, -16(%rbp)
	movl $0, %r8d
	movq %r8, -136(%rbp)
	imulq $8, %r8, %r8
	movq %r8, -120(%rbp)
	movl $1, %r8d
	movq %r8, -168(%rbp)
	imulq $8, %r8, %rcx
	movq %rcx, -160(%rbp)
	movl $2, %ecx
	movq %rcx, -184(%rbp)
	imulq $8, %rcx, %rcx
	movq %rcx, -176(%rbp)
	movl $3, %r8d
	movq %r8, -208(%rbp)
	imulq $8, %r8, %rcx
	movq %rcx, -200(%rbp)
	movl $2, %ecx
	movl %ecx, %r13d
	movl %r13d, -220(%rbp)
	movl $2, %ecx
	movl %ecx, %r13d
	movl %r13d, -296(%rbp)
	movl $2, %ecx
	movl %ecx, -436(%rbp)
	movl $2, %r13d
	movl %r13d, -444(%rbp)
	movl $0, %edx
	movl %edx, -124(%rbp)
	movl $0, %ecx
	movl %ecx, -284(%rbp)
	movl $0, %ecx
	movl %ecx, -376(%rbp)
	movl $0, %edx
	movl %edx, -448(%rbp)
	movl $0, %r13d
	movl %r13d, -440(%rbp)
	movl $2, %r14d
	movl %r14d, -460(%rbp)
	movq %rsi, %r14
	movl $0, %esi
	movl %esi, -464(%rbp)
	movl $2, %r15d
	movl %r15d, -480(%rbp)
	movl $0, %r13d
	movl %r13d, -476(%rbp)
	movl $0, %ecx
	movl %ecx, -3424(%rbp)
	movl $0, %r13d
	movl %r13d, -508(%rbp)
	movl $0, %r9d
	movl %r9d, -152(%rbp)
	cmpl $0, %eax
	jnz .Lbb2384
	movq $0, -3992(%rbp)
	movq $0, -3984(%rbp)
	movq $0, -3976(%rbp)
	movq $0, -3968(%rbp)
	movq $0, -3960(%rbp)
	movq $0, -3952(%rbp)
	movq $0, -3944(%rbp)
	movq $0, -3936(%rbp)
	movq $0, -3928(%rbp)
	movq $0, -3920(%rbp)
	movq $0, -3912(%rbp)
	movq $0, -3904(%rbp)
	movq $0, -3896(%rbp)
	movq $0, -3888(%rbp)
	.loc 1 1
	movq %rbx, %rdi
	callq myl_qbe_heap
	movq %rax, %rdi
	movq %rdi, -2768(%rbp)
	.loc 1 1
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_qbe_region_mark
	movq %r13, %rdi
	movq %rax, %r15
	movq %r15, -504(%rbp)
	movl $0, -4200(%rbp)
	movl $0, -4192(%rbp)
	movl $0, -4184(%rbp)
	movl $0, -4176(%rbp)
	movl $0, -4168(%rbp)
	movl $0, -4160(%rbp)
	.loc 1 1
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_qbe_require_step_accounting
	movq %r13, %rdi
	.loc 1 1
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_qbe_require_frame_accounting
	movq %r15, %rcx
	movq %r14, %rsi
	movq %r13, %rdi
	movq (%rsi), %rax
	movq %rcx, %r15
	movq $9223372036854775807, %rcx
	cmpq %rcx, %rax
	ja .Lbb2382
	movq $4, -3712(%rbp)
	cmpq $4, %rax
	setnz %al
	movzbq %al, %rax
	cmpl $0, %eax
	jnz .Lbb2328
	.loc 1 11
	movl $12, %edx
	movq %rsi, %r14
	movq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a@gotpcrel(%rip), %rsi
	movq %rdi, %r13
	callq myl_native_list_new
	movq %r15, %rcx
	movq %r14, %rsi
	movq %r13, %rdi
	cmpl $0, %eax
	jnz .Lbb6
	movq %rbx, %rdi
	.loc 1 11
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	ud2
.Lbb6:
	movq %rax, -4120(%rbp)
	movq -4120(%rbp), %rdx
	movq %rdx, -4112(%rbp)
	movq -4112(%rbp), %rdx
	movq %rdx, -4152(%rbp)
	movq %rax, -4120(%rbp)
	leaq -4112(%rbp), %r8
	leaq -4120(%rbp), %rdx
	negq %r8
	addq %rdx, %r8
	leaq -4120(%rbp), %r9
	leaq -4112(%rbp), %rdx
	subq %r9, %rdx
	cmpq $8, %r8
	setb %r15b
	movzbl %r15b, %r15d
	movl %r15d, -516(%rbp)
	cmpq $8, %rdx
	setb %r11b
	movzbl %r11b, %r11d
	movl %r11d, -512(%rbp)
	movl %r15d, %edx
	orl %r11d, %edx
	jnz .Lbb10
	cmpq $0, %rax
	jz .Lbb9
	movq -16(%rax), %rax
	movq $5764607523034234881, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb10
.Lbb9:
	movq -4120(%rbp), %rax
	movq %rax, -4112(%rbp)
	movq $0, -4120(%rbp)
	jmp .Lbb12
.Lbb10:
	.loc 1 12
	movq %rcx, %r14
	leaq -4120(%rbp), %rdx
	movq %rsi, %r13
	leaq -4112(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_take
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movl -16(%rbp), %r12d
	cmpl $0, %eax
	jnz .Lbb12
	.loc 1 12
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 12
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb12:
	movl -4200(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb21
	movl $0, -4200(%rbp)
	movq -3992(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb21
	movq -16(%rdx), %rax
	movq $4611686018427387906, %r8
	andq %r8, %rax
	cmpq $0, %rax
	jnz .Lbb20
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb19
	movq %rcx, %r14
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb18
	.loc 1 12
	movq %rsi, %r13
	leaq -3992(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movl -16(%rbp), %r12d
	jmp .Lbb21
.Lbb18:
	movq %r14, %rcx
.Lbb19:
	movq %rax, -32(%rdx)
.Lbb20:
	movq $0, -3992(%rbp)
.Lbb21:
	movq -4112(%rbp), %rax
	movq %rax, -3992(%rbp)
	movl $1, -4200(%rbp)
	movq myl_lit_91d8e386c30c656a06165cf351f92965220d6691140b83eaf5169fd74bae9057(%rip), %rax
	movq %rax, -24(%rbp)
	movq %rax, -4120(%rbp)
	movq -4120(%rbp), %rdx
	movq %rdx, -4112(%rbp)
	movq -4112(%rbp), %rdx
	movq %rdx, -4152(%rbp)
	cmpl $16, %r12d
	jnz .Lbb51
	movq -3992(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb29
	movq -16(%rdx), %r8
	movq $4611686018427387906, %r9
	andq %r8, %r9
	cmpq $0, %r9
	jnz .Lbb28
	movq -32(%rdx), %r8
	addq $1, %r8
	jz .Lbb26
	movq %r8, -32(%rdx)
	jmp .Lbb29
.Lbb26:
	movq %rbx, %rdi
	.loc 1 14
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb28:
	movq $4611686018427387904, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb30
.Lbb29:
	movq %rdx, -4112(%rbp)
	jmp .Lbb32
.Lbb30:
	.loc 1 14
	movq %rcx, %r14
	leaq -3992(%rbp), %rdx
	movq %rsi, %r13
	leaq -4112(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_retain
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %edx
	movl -16(%rbp), %r12d
	movq -24(%rbp), %rax
	cmpl $0, %edx
	jnz .Lbb32
	.loc 1 14
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 14
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb32:
	movl -4200(%rbp), %edx
	cmpl $0, %edx
	jz .Lbb50
	movl $0, -4200(%rbp)
	testl $28, %r12d
	jnz .Lbb42
	movq -3992(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb50
	movq -16(%r8), %rdx
	movq $4611686018427387906, %r9
	andq %r9, %rdx
	cmpq $0, %rdx
	jnz .Lbb41
	movq -32(%r8), %rdx
	subq $1, %rdx
	jnz .Lbb40
	movq %rcx, %r14
	movq -24(%r8), %rcx
	cmpq $0, %rcx
	jnz .Lbb39
	.loc 1 14
	movq %rsi, %r13
	leaq -3992(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movq -24(%rbp), %rax
	jmp .Lbb50
.Lbb39:
	movq %r14, %rcx
.Lbb40:
	movq %rdx, -32(%r8)
.Lbb41:
	movq $0, -3992(%rbp)
	jmp .Lbb50
.Lbb42:
	movq -3992(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb50
	movq -16(%r8), %rdx
	movq $4611686018427387906, %r9
	andq %r9, %rdx
	cmpq $0, %rdx
	jnz .Lbb49
	movq -24(%r8), %rdx
	subq $1, %rdx
	jnz .Lbb48
	movq %rcx, %r14
	movq -32(%r8), %rcx
	cmpq $0, %rcx
	jnz .Lbb47
	.loc 1 14
	movq %rsi, %r13
	leaq -3992(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_unloan
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movq -24(%rbp), %rax
	jmp .Lbb50
.Lbb47:
	movq %r14, %rcx
.Lbb48:
	movq %rdx, -24(%r8)
.Lbb49:
	movq $0, -3992(%rbp)
.Lbb50:
	movq -4112(%rbp), %rdx
	movq %rdx, -3992(%rbp)
	movl $1, -4200(%rbp)
.Lbb51:
	movq -3992(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb53
	movq %rcx, %r14
	jmp .Lbb57
.Lbb53:
	movq -16(%rdx), %r8
	movq $6917529027641081858, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb56
	movq -32(%rdx), %rdx
	cmpq $2, %rdx
	jae .Lbb56
	movq %rcx, %r14
	jmp .Lbb57
.Lbb56:
	.loc 1 14
	movq %rcx, %r14
	leaq -4200(%rbp), %rcx
	leaq -3992(%rbp), %rdx
	movq %rsi, %r13
	movq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %ecx
	movq -24(%rbp), %rax
	cmpl $0, %ecx
	jz .Lbb2149
.Lbb57:
	movq %rsi, %r13
	movq -3992(%rbp), %rsi
	movq %rax, -4080(%rbp)
	.loc 1 14
	leaq -4080(%rbp), %rdx
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_list_append
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	cmpl $0, %eax
	jnz .Lbb60
	movq %rbx, %rdi
	.loc 1 14
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	ud2
.Lbb60:
	movq -4152(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb68
	movq -16(%rdx), %rax
	movq $4611686018427387906, %r8
	andq %r8, %rax
	cmpq $0, %rax
	jnz .Lbb67
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb66
	movq %rcx, %r14
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb65
	.loc 1 14
	movq %rsi, %r13
	leaq -4152(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	jmp .Lbb68
.Lbb65:
	movq %r14, %rcx
.Lbb66:
	movq %rax, -32(%rdx)
.Lbb67:
	movq $0, -4152(%rbp)
.Lbb68:
	movq myl_lit_48af4f085a39fdc824c1a25d3474aed7f74c916b0549dc50c9b7a25c3f2fdf98(%rip), %rax
	movq %rax, -32(%rbp)
	movq %rax, -4120(%rbp)
	movq -4120(%rbp), %rdx
	movq %rdx, -4112(%rbp)
	movq -4112(%rbp), %rdx
	movq %rdx, -4152(%rbp)
	movl -4200(%rbp), %edx
	testl $0, %edx
	jz .Lbb89
	movq -3992(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb76
	movq -16(%rdx), %r8
	movq $4611686018427387906, %r9
	andq %r8, %r9
	cmpq $0, %r9
	jnz .Lbb75
	movq -32(%rdx), %r8
	addq $1, %r8
	jz .Lbb73
	movq %r8, -32(%rdx)
	jmp .Lbb76
.Lbb73:
	movq %rbx, %rdi
	.loc 1 17
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb75:
	movq $4611686018427387904, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb77
.Lbb76:
	movq %rdx, -4112(%rbp)
	jmp .Lbb79
.Lbb77:
	.loc 1 17
	movq %rcx, %r14
	leaq -3992(%rbp), %rdx
	movq %rsi, %r13
	leaq -4112(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_retain
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %edx
	movq -32(%rbp), %rax
	cmpl $0, %edx
	jnz .Lbb79
	.loc 1 17
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 17
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb79:
	movl -4200(%rbp), %edx
	cmpl $0, %edx
	jz .Lbb88
	movl $0, -4200(%rbp)
	movq -3992(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb88
	movq -16(%r8), %rdx
	movq $4611686018427387906, %r9
	andq %r9, %rdx
	cmpq $0, %rdx
	jnz .Lbb87
	movq -32(%r8), %rdx
	subq $1, %rdx
	jnz .Lbb86
	movq %rcx, %r14
	movq -24(%r8), %rcx
	cmpq $0, %rcx
	jnz .Lbb85
	.loc 1 17
	movq %rsi, %r13
	leaq -3992(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movq -32(%rbp), %rax
	jmp .Lbb88
.Lbb85:
	movq %r14, %rcx
.Lbb86:
	movq %rdx, -32(%r8)
.Lbb87:
	movq $0, -3992(%rbp)
.Lbb88:
	movq -4112(%rbp), %rdx
	movq %rdx, -3992(%rbp)
	movl $1, -4200(%rbp)
.Lbb89:
	movq -3992(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb91
	movq %rcx, %r14
	jmp .Lbb95
.Lbb91:
	movq -16(%rdx), %r8
	movq $6917529027641081858, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb94
	movq -32(%rdx), %rdx
	cmpq $2, %rdx
	jae .Lbb94
	movq %rcx, %r14
	jmp .Lbb95
.Lbb94:
	.loc 1 17
	movq %rcx, %r14
	leaq -4200(%rbp), %rcx
	leaq -3992(%rbp), %rdx
	movq %rsi, %r13
	movq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %ecx
	movq -32(%rbp), %rax
	cmpl $0, %ecx
	jz .Lbb2149
.Lbb95:
	movq %rsi, %r13
	movq -3992(%rbp), %rsi
	movq %rax, -4080(%rbp)
	.loc 1 17
	leaq -4080(%rbp), %rdx
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_list_append
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	cmpl $0, %eax
	jnz .Lbb98
	movq %rbx, %rdi
	.loc 1 17
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	ud2
.Lbb98:
	movq -4152(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb106
	movq -16(%rdx), %rax
	movq $4611686018427387906, %r8
	andq %r8, %rax
	cmpq $0, %rax
	jnz .Lbb105
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb104
	movq %rcx, %r14
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb103
	.loc 1 17
	movq %rsi, %r13
	leaq -4152(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	jmp .Lbb106
.Lbb103:
	movq %r14, %rcx
.Lbb104:
	movq %rax, -32(%rdx)
.Lbb105:
	movq $0, -4152(%rbp)
.Lbb106:
	movq myl_lit_87e3dc7d60448f96b55621ea82cda5ab42e87191032c1d8a40da5b27ba5c5039(%rip), %rax
	movq %rax, -40(%rbp)
	movq %rax, -4120(%rbp)
	movq -4120(%rbp), %rdx
	movq %rdx, -4112(%rbp)
	movq -4112(%rbp), %rdx
	movq %rdx, -4152(%rbp)
	movl -4200(%rbp), %edx
	testl $0, %edx
	jz .Lbb127
	movq -3992(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb114
	movq -16(%rdx), %r8
	movq $4611686018427387906, %r9
	andq %r8, %r9
	cmpq $0, %r9
	jnz .Lbb113
	movq -32(%rdx), %r8
	addq $1, %r8
	jz .Lbb111
	movq %r8, -32(%rdx)
	jmp .Lbb114
.Lbb111:
	movq %rbx, %rdi
	.loc 1 20
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb113:
	movq $4611686018427387904, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb115
.Lbb114:
	movq %rdx, -4112(%rbp)
	jmp .Lbb117
.Lbb115:
	.loc 1 20
	movq %rcx, %r14
	leaq -3992(%rbp), %rdx
	movq %rsi, %r13
	leaq -4112(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_retain
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %edx
	movq -40(%rbp), %rax
	cmpl $0, %edx
	jnz .Lbb117
	.loc 1 20
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 20
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb117:
	movl -4200(%rbp), %edx
	cmpl $0, %edx
	jz .Lbb126
	movl $0, -4200(%rbp)
	movq -3992(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb126
	movq -16(%r8), %rdx
	movq $4611686018427387906, %r9
	andq %r9, %rdx
	cmpq $0, %rdx
	jnz .Lbb125
	movq -32(%r8), %rdx
	subq $1, %rdx
	jnz .Lbb124
	movq %rcx, %r14
	movq -24(%r8), %rcx
	cmpq $0, %rcx
	jnz .Lbb123
	.loc 1 20
	movq %rsi, %r13
	leaq -3992(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movq -40(%rbp), %rax
	jmp .Lbb126
.Lbb123:
	movq %r14, %rcx
.Lbb124:
	movq %rdx, -32(%r8)
.Lbb125:
	movq $0, -3992(%rbp)
.Lbb126:
	movq -4112(%rbp), %rdx
	movq %rdx, -3992(%rbp)
	movl $1, -4200(%rbp)
.Lbb127:
	movq -3992(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb129
	movq %rcx, %r14
	jmp .Lbb133
.Lbb129:
	movq -16(%rdx), %r8
	movq $6917529027641081858, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb132
	movq -32(%rdx), %rdx
	cmpq $2, %rdx
	jae .Lbb132
	movq %rcx, %r14
	jmp .Lbb133
.Lbb132:
	.loc 1 20
	movq %rcx, %r14
	leaq -4200(%rbp), %rcx
	leaq -3992(%rbp), %rdx
	movq %rsi, %r13
	movq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %ecx
	movq -40(%rbp), %rax
	cmpl $0, %ecx
	jz .Lbb2149
.Lbb133:
	movq %rsi, %r13
	movq -3992(%rbp), %rsi
	movq %rax, -4080(%rbp)
	.loc 1 20
	leaq -4080(%rbp), %rdx
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_list_append
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	cmpl $0, %eax
	jnz .Lbb136
	movq %rbx, %rdi
	.loc 1 20
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	ud2
.Lbb136:
	movq -4152(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb144
	movq -16(%rdx), %rax
	movq $4611686018427387906, %r8
	andq %r8, %rax
	cmpq $0, %rax
	jnz .Lbb143
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb142
	movq %rcx, %r14
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb141
	.loc 1 20
	movq %rsi, %r13
	leaq -4152(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	jmp .Lbb144
.Lbb141:
	movq %r14, %rcx
.Lbb142:
	movq %rax, -32(%rdx)
.Lbb143:
	movq $0, -4152(%rbp)
.Lbb144:
	movq myl_lit_893cdd504b2a309e97713e1ad13e95d9da6761cdcb493d1d2fb2d27b576568a0(%rip), %rax
	movq %rax, -48(%rbp)
	movq %rax, -4120(%rbp)
	movq -4120(%rbp), %rdx
	movq %rdx, -4112(%rbp)
	movq -4112(%rbp), %rdx
	movq %rdx, -4152(%rbp)
	movl -4200(%rbp), %edx
	testl $0, %edx
	jz .Lbb165
	movq -3992(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb152
	movq -16(%rdx), %r8
	movq $4611686018427387906, %r9
	andq %r8, %r9
	cmpq $0, %r9
	jnz .Lbb151
	movq -32(%rdx), %r8
	addq $1, %r8
	jz .Lbb149
	movq %r8, -32(%rdx)
	jmp .Lbb152
.Lbb149:
	movq %rbx, %rdi
	.loc 1 23
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb151:
	movq $4611686018427387904, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb153
.Lbb152:
	movq %rdx, -4112(%rbp)
	jmp .Lbb155
.Lbb153:
	.loc 1 23
	movq %rcx, %r14
	leaq -3992(%rbp), %rdx
	movq %rsi, %r13
	leaq -4112(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_retain
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %edx
	movq -48(%rbp), %rax
	cmpl $0, %edx
	jnz .Lbb155
	.loc 1 23
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 23
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb155:
	movl -4200(%rbp), %edx
	cmpl $0, %edx
	jz .Lbb164
	movl $0, -4200(%rbp)
	movq -3992(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb164
	movq -16(%r8), %rdx
	movq $4611686018427387906, %r9
	andq %r9, %rdx
	cmpq $0, %rdx
	jnz .Lbb163
	movq -32(%r8), %rdx
	subq $1, %rdx
	jnz .Lbb162
	movq %rcx, %r14
	movq -24(%r8), %rcx
	cmpq $0, %rcx
	jnz .Lbb161
	.loc 1 23
	movq %rsi, %r13
	leaq -3992(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movq -48(%rbp), %rax
	jmp .Lbb164
.Lbb161:
	movq %r14, %rcx
.Lbb162:
	movq %rdx, -32(%r8)
.Lbb163:
	movq $0, -3992(%rbp)
.Lbb164:
	movq -4112(%rbp), %rdx
	movq %rdx, -3992(%rbp)
	movl $1, -4200(%rbp)
.Lbb165:
	movq -3992(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb167
	movq %rcx, %r14
	jmp .Lbb171
.Lbb167:
	movq -16(%rdx), %r8
	movq $6917529027641081858, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb170
	movq -32(%rdx), %rdx
	cmpq $2, %rdx
	jae .Lbb170
	movq %rcx, %r14
	jmp .Lbb171
.Lbb170:
	.loc 1 23
	movq %rcx, %r14
	leaq -4200(%rbp), %rcx
	leaq -3992(%rbp), %rdx
	movq %rsi, %r13
	movq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %ecx
	movq -48(%rbp), %rax
	cmpl $0, %ecx
	jz .Lbb2149
.Lbb171:
	movq %rsi, %r13
	movq -3992(%rbp), %rsi
	movq %rax, -4080(%rbp)
	.loc 1 23
	leaq -4080(%rbp), %rdx
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_list_append
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	cmpl $0, %eax
	jnz .Lbb174
	movq %rbx, %rdi
	.loc 1 23
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	ud2
.Lbb174:
	movq -4152(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb182
	movq -16(%rdx), %rax
	movq $4611686018427387906, %r8
	andq %r8, %rax
	cmpq $0, %rax
	jnz .Lbb181
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb180
	movq %rcx, %r14
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb179
	.loc 1 23
	movq %rsi, %r13
	leaq -4152(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	jmp .Lbb182
.Lbb179:
	movq %r14, %rcx
.Lbb180:
	movq %rax, -32(%rdx)
.Lbb181:
	movq $0, -4152(%rbp)
.Lbb182:
	movq myl_lit_092d7c6801f882df3074b77feb8a8cfae05fd11077e077b473214d2840e62f89(%rip), %rax
	movq %rax, -56(%rbp)
	movq %rax, -4120(%rbp)
	movq -4120(%rbp), %rdx
	movq %rdx, -4112(%rbp)
	movq -4112(%rbp), %rdx
	movq %rdx, -4152(%rbp)
	movl -4200(%rbp), %edx
	testl $0, %edx
	jz .Lbb203
	movq -3992(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb190
	movq -16(%rdx), %r8
	movq $4611686018427387906, %r9
	andq %r8, %r9
	cmpq $0, %r9
	jnz .Lbb189
	movq -32(%rdx), %r8
	addq $1, %r8
	jz .Lbb187
	movq %r8, -32(%rdx)
	jmp .Lbb190
.Lbb187:
	movq %rbx, %rdi
	.loc 1 26
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb189:
	movq $4611686018427387904, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb191
.Lbb190:
	movq %rdx, -4112(%rbp)
	jmp .Lbb193
.Lbb191:
	.loc 1 26
	movq %rcx, %r14
	leaq -3992(%rbp), %rdx
	movq %rsi, %r13
	leaq -4112(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_retain
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %edx
	movq -56(%rbp), %rax
	cmpl $0, %edx
	jnz .Lbb193
	.loc 1 26
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 26
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb193:
	movl -4200(%rbp), %edx
	cmpl $0, %edx
	jz .Lbb202
	movl $0, -4200(%rbp)
	movq -3992(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb202
	movq -16(%r8), %rdx
	movq $4611686018427387906, %r9
	andq %r9, %rdx
	cmpq $0, %rdx
	jnz .Lbb201
	movq -32(%r8), %rdx
	subq $1, %rdx
	jnz .Lbb200
	movq %rcx, %r14
	movq -24(%r8), %rcx
	cmpq $0, %rcx
	jnz .Lbb199
	.loc 1 26
	movq %rsi, %r13
	leaq -3992(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movq -56(%rbp), %rax
	jmp .Lbb202
.Lbb199:
	movq %r14, %rcx
.Lbb200:
	movq %rdx, -32(%r8)
.Lbb201:
	movq $0, -3992(%rbp)
.Lbb202:
	movq -4112(%rbp), %rdx
	movq %rdx, -3992(%rbp)
	movl $1, -4200(%rbp)
.Lbb203:
	movq -3992(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb205
	movq %rcx, %r14
	jmp .Lbb209
.Lbb205:
	movq -16(%rdx), %r8
	movq $6917529027641081858, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb208
	movq -32(%rdx), %rdx
	cmpq $2, %rdx
	jae .Lbb208
	movq %rcx, %r14
	jmp .Lbb209
.Lbb208:
	.loc 1 26
	movq %rcx, %r14
	leaq -4200(%rbp), %rcx
	leaq -3992(%rbp), %rdx
	movq %rsi, %r13
	movq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %ecx
	movq -56(%rbp), %rax
	cmpl $0, %ecx
	jz .Lbb2149
.Lbb209:
	movq %rsi, %r13
	movq -3992(%rbp), %rsi
	movq %rax, -4080(%rbp)
	.loc 1 26
	leaq -4080(%rbp), %rdx
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_list_append
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	cmpl $0, %eax
	jnz .Lbb212
	movq %rbx, %rdi
	.loc 1 26
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	ud2
.Lbb212:
	movq -4152(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb220
	movq -16(%rdx), %rax
	movq $4611686018427387906, %r8
	andq %r8, %rax
	cmpq $0, %rax
	jnz .Lbb219
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb218
	movq %rcx, %r14
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb217
	.loc 1 26
	movq %rsi, %r13
	leaq -4152(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	jmp .Lbb220
.Lbb217:
	movq %r14, %rcx
.Lbb218:
	movq %rax, -32(%rdx)
.Lbb219:
	movq $0, -4152(%rbp)
.Lbb220:
	movq myl_lit_34de47119c2d38616e51ac3e34c9dbe870e177ae9782bc3e9e986f1120a4b1c8(%rip), %rax
	movq %rax, -64(%rbp)
	movq %rax, -4120(%rbp)
	movq -4120(%rbp), %rdx
	movq %rdx, -4112(%rbp)
	movq -4112(%rbp), %rdx
	movq %rdx, -4152(%rbp)
	movl -4200(%rbp), %edx
	testl $0, %edx
	jz .Lbb241
	movq -3992(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb228
	movq -16(%rdx), %r8
	movq $4611686018427387906, %r9
	andq %r8, %r9
	cmpq $0, %r9
	jnz .Lbb227
	movq -32(%rdx), %r8
	addq $1, %r8
	jz .Lbb225
	movq %r8, -32(%rdx)
	jmp .Lbb228
.Lbb225:
	movq %rbx, %rdi
	.loc 1 29
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb227:
	movq $4611686018427387904, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb229
.Lbb228:
	movq %rdx, -4112(%rbp)
	jmp .Lbb231
.Lbb229:
	.loc 1 29
	movq %rcx, %r14
	leaq -3992(%rbp), %rdx
	movq %rsi, %r13
	leaq -4112(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_retain
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %edx
	movq -64(%rbp), %rax
	cmpl $0, %edx
	jnz .Lbb231
	.loc 1 29
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 29
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb231:
	movl -4200(%rbp), %edx
	cmpl $0, %edx
	jz .Lbb240
	movl $0, -4200(%rbp)
	movq -3992(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb240
	movq -16(%r8), %rdx
	movq $4611686018427387906, %r9
	andq %r9, %rdx
	cmpq $0, %rdx
	jnz .Lbb239
	movq -32(%r8), %rdx
	subq $1, %rdx
	jnz .Lbb238
	movq %rcx, %r14
	movq -24(%r8), %rcx
	cmpq $0, %rcx
	jnz .Lbb237
	.loc 1 29
	movq %rsi, %r13
	leaq -3992(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movq -64(%rbp), %rax
	jmp .Lbb240
.Lbb237:
	movq %r14, %rcx
.Lbb238:
	movq %rdx, -32(%r8)
.Lbb239:
	movq $0, -3992(%rbp)
.Lbb240:
	movq -4112(%rbp), %rdx
	movq %rdx, -3992(%rbp)
	movl $1, -4200(%rbp)
.Lbb241:
	movq -3992(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb243
	movq %rcx, %r14
	jmp .Lbb247
.Lbb243:
	movq -16(%rdx), %r8
	movq $6917529027641081858, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb246
	movq -32(%rdx), %rdx
	cmpq $2, %rdx
	jae .Lbb246
	movq %rcx, %r14
	jmp .Lbb247
.Lbb246:
	.loc 1 29
	movq %rcx, %r14
	leaq -4200(%rbp), %rcx
	leaq -3992(%rbp), %rdx
	movq %rsi, %r13
	movq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %ecx
	movq -64(%rbp), %rax
	cmpl $0, %ecx
	jz .Lbb2149
.Lbb247:
	movq %rsi, %r13
	movq -3992(%rbp), %rsi
	movq %rax, -4080(%rbp)
	.loc 1 29
	leaq -4080(%rbp), %rdx
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_list_append
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	cmpl $0, %eax
	jnz .Lbb250
	movq %rbx, %rdi
	.loc 1 29
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	ud2
.Lbb250:
	movq -4152(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb258
	movq -16(%rdx), %rax
	movq $4611686018427387906, %r8
	andq %r8, %rax
	cmpq $0, %rax
	jnz .Lbb257
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb256
	movq %rcx, %r14
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb255
	.loc 1 29
	movq %rsi, %r13
	leaq -4152(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	jmp .Lbb258
.Lbb255:
	movq %r14, %rcx
.Lbb256:
	movq %rax, -32(%rdx)
.Lbb257:
	movq $0, -4152(%rbp)
.Lbb258:
	movq myl_lit_508b25981ffcb062ef47f525f87fd682c2be6416d9d7c4a0b4ca20c3e4f84a16(%rip), %rax
	movq %rax, -72(%rbp)
	movq %rax, -4120(%rbp)
	movq -4120(%rbp), %rdx
	movq %rdx, -4112(%rbp)
	movq -4112(%rbp), %rdx
	movq %rdx, -4152(%rbp)
	movl -4200(%rbp), %edx
	testl $0, %edx
	jz .Lbb279
	movq -3992(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb266
	movq -16(%rdx), %r8
	movq $4611686018427387906, %r9
	andq %r8, %r9
	cmpq $0, %r9
	jnz .Lbb265
	movq -32(%rdx), %r8
	addq $1, %r8
	jz .Lbb263
	movq %r8, -32(%rdx)
	jmp .Lbb266
.Lbb263:
	movq %rbx, %rdi
	.loc 1 32
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb265:
	movq $4611686018427387904, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb267
.Lbb266:
	movq %rdx, -4112(%rbp)
	jmp .Lbb269
.Lbb267:
	.loc 1 32
	movq %rcx, %r14
	leaq -3992(%rbp), %rdx
	movq %rsi, %r13
	leaq -4112(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_retain
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %edx
	movq -72(%rbp), %rax
	cmpl $0, %edx
	jnz .Lbb269
	.loc 1 32
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 32
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb269:
	movl -4200(%rbp), %edx
	cmpl $0, %edx
	jz .Lbb278
	movl $0, -4200(%rbp)
	movq -3992(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb278
	movq -16(%r8), %rdx
	movq $4611686018427387906, %r9
	andq %r9, %rdx
	cmpq $0, %rdx
	jnz .Lbb277
	movq -32(%r8), %rdx
	subq $1, %rdx
	jnz .Lbb276
	movq %rcx, %r14
	movq -24(%r8), %rcx
	cmpq $0, %rcx
	jnz .Lbb275
	.loc 1 32
	movq %rsi, %r13
	leaq -3992(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movq -72(%rbp), %rax
	jmp .Lbb278
.Lbb275:
	movq %r14, %rcx
.Lbb276:
	movq %rdx, -32(%r8)
.Lbb277:
	movq $0, -3992(%rbp)
.Lbb278:
	movq -4112(%rbp), %rdx
	movq %rdx, -3992(%rbp)
	movl $1, -4200(%rbp)
.Lbb279:
	movq -3992(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb281
	movq %rcx, %r14
	jmp .Lbb285
.Lbb281:
	movq -16(%rdx), %r8
	movq $6917529027641081858, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb284
	movq -32(%rdx), %rdx
	cmpq $2, %rdx
	jae .Lbb284
	movq %rcx, %r14
	jmp .Lbb285
.Lbb284:
	.loc 1 32
	movq %rcx, %r14
	leaq -4200(%rbp), %rcx
	leaq -3992(%rbp), %rdx
	movq %rsi, %r13
	movq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %ecx
	movq -72(%rbp), %rax
	cmpl $0, %ecx
	jz .Lbb2149
.Lbb285:
	movq %rsi, %r13
	movq -3992(%rbp), %rsi
	movq %rax, -4080(%rbp)
	.loc 1 32
	leaq -4080(%rbp), %rdx
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_list_append
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	cmpl $0, %eax
	jnz .Lbb288
	movq %rbx, %rdi
	.loc 1 32
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	ud2
.Lbb288:
	movq -4152(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb296
	movq -16(%rdx), %rax
	movq $4611686018427387906, %r8
	andq %r8, %rax
	cmpq $0, %rax
	jnz .Lbb295
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb294
	movq %rcx, %r14
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb293
	.loc 1 32
	movq %rsi, %r13
	leaq -4152(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	jmp .Lbb296
.Lbb293:
	movq %r14, %rcx
.Lbb294:
	movq %rax, -32(%rdx)
.Lbb295:
	movq $0, -4152(%rbp)
.Lbb296:
	movq myl_lit_5df1e3adc6cd2d309d46b415edafb480bb2aac56d37d79d6464456909f15ac46(%rip), %rax
	movq %rax, -80(%rbp)
	movq %rax, -4120(%rbp)
	movq -4120(%rbp), %rdx
	movq %rdx, -4112(%rbp)
	movq -4112(%rbp), %rdx
	movq %rdx, -4152(%rbp)
	movl -4200(%rbp), %edx
	testl $0, %edx
	jz .Lbb317
	movq -3992(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb304
	movq -16(%rdx), %r8
	movq $4611686018427387906, %r9
	andq %r8, %r9
	cmpq $0, %r9
	jnz .Lbb303
	movq -32(%rdx), %r8
	addq $1, %r8
	jz .Lbb301
	movq %r8, -32(%rdx)
	jmp .Lbb304
.Lbb301:
	movq %rbx, %rdi
	.loc 1 35
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb303:
	movq $4611686018427387904, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb305
.Lbb304:
	movq %rdx, -4112(%rbp)
	jmp .Lbb307
.Lbb305:
	.loc 1 35
	movq %rcx, %r14
	leaq -3992(%rbp), %rdx
	movq %rsi, %r13
	leaq -4112(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_retain
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %edx
	movq -80(%rbp), %rax
	cmpl $0, %edx
	jnz .Lbb307
	.loc 1 35
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 35
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb307:
	movl -4200(%rbp), %edx
	cmpl $0, %edx
	jz .Lbb316
	movl $0, -4200(%rbp)
	movq -3992(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb316
	movq -16(%r8), %rdx
	movq $4611686018427387906, %r9
	andq %r9, %rdx
	cmpq $0, %rdx
	jnz .Lbb315
	movq -32(%r8), %rdx
	subq $1, %rdx
	jnz .Lbb314
	movq %rcx, %r14
	movq -24(%r8), %rcx
	cmpq $0, %rcx
	jnz .Lbb313
	.loc 1 35
	movq %rsi, %r13
	leaq -3992(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movq -80(%rbp), %rax
	jmp .Lbb316
.Lbb313:
	movq %r14, %rcx
.Lbb314:
	movq %rdx, -32(%r8)
.Lbb315:
	movq $0, -3992(%rbp)
.Lbb316:
	movq -4112(%rbp), %rdx
	movq %rdx, -3992(%rbp)
	movl $1, -4200(%rbp)
.Lbb317:
	movq -3992(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb319
	movq %rcx, %r14
	jmp .Lbb323
.Lbb319:
	movq -16(%rdx), %r8
	movq $6917529027641081858, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb322
	movq -32(%rdx), %rdx
	cmpq $2, %rdx
	jae .Lbb322
	movq %rcx, %r14
	jmp .Lbb323
.Lbb322:
	.loc 1 35
	movq %rcx, %r14
	leaq -4200(%rbp), %rcx
	leaq -3992(%rbp), %rdx
	movq %rsi, %r13
	movq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %ecx
	movq -80(%rbp), %rax
	cmpl $0, %ecx
	jz .Lbb2149
.Lbb323:
	movq %rsi, %r13
	movq -3992(%rbp), %rsi
	movq %rax, -4080(%rbp)
	.loc 1 35
	leaq -4080(%rbp), %rdx
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_list_append
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	cmpl $0, %eax
	jnz .Lbb326
	movq %rbx, %rdi
	.loc 1 35
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	ud2
.Lbb326:
	movq -4152(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb334
	movq -16(%rdx), %rax
	movq $4611686018427387906, %r8
	andq %r8, %rax
	cmpq $0, %rax
	jnz .Lbb333
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb332
	movq %rcx, %r14
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb331
	.loc 1 35
	movq %rsi, %r13
	leaq -4152(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	jmp .Lbb334
.Lbb331:
	movq %r14, %rcx
.Lbb332:
	movq %rax, -32(%rdx)
.Lbb333:
	movq $0, -4152(%rbp)
.Lbb334:
	movq myl_lit_bf0fa3d2de4dff2fec439219b629ad17e9791bb9a451d7c298cc60f8dcce562a(%rip), %rax
	movq %rax, -88(%rbp)
	movq %rax, -4120(%rbp)
	movq -4120(%rbp), %rdx
	movq %rdx, -4112(%rbp)
	movq -4112(%rbp), %rdx
	movq %rdx, -4152(%rbp)
	movl -4200(%rbp), %edx
	testl $0, %edx
	jz .Lbb355
	movq -3992(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb342
	movq -16(%rdx), %r8
	movq $4611686018427387906, %r9
	andq %r8, %r9
	cmpq $0, %r9
	jnz .Lbb341
	movq -32(%rdx), %r8
	addq $1, %r8
	jz .Lbb339
	movq %r8, -32(%rdx)
	jmp .Lbb342
.Lbb339:
	movq %rbx, %rdi
	.loc 1 38
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb341:
	movq $4611686018427387904, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb343
.Lbb342:
	movq %rdx, -4112(%rbp)
	jmp .Lbb345
.Lbb343:
	.loc 1 38
	movq %rcx, %r14
	leaq -3992(%rbp), %rdx
	movq %rsi, %r13
	leaq -4112(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_retain
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %edx
	movq -88(%rbp), %rax
	cmpl $0, %edx
	jnz .Lbb345
	.loc 1 38
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 38
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb345:
	movl -4200(%rbp), %edx
	cmpl $0, %edx
	jz .Lbb354
	movl $0, -4200(%rbp)
	movq -3992(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb354
	movq -16(%r8), %rdx
	movq $4611686018427387906, %r9
	andq %r9, %rdx
	cmpq $0, %rdx
	jnz .Lbb353
	movq -32(%r8), %rdx
	subq $1, %rdx
	jnz .Lbb352
	movq %rcx, %r14
	movq -24(%r8), %rcx
	cmpq $0, %rcx
	jnz .Lbb351
	.loc 1 38
	movq %rsi, %r13
	leaq -3992(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movq -88(%rbp), %rax
	jmp .Lbb354
.Lbb351:
	movq %r14, %rcx
.Lbb352:
	movq %rdx, -32(%r8)
.Lbb353:
	movq $0, -3992(%rbp)
.Lbb354:
	movq -4112(%rbp), %rdx
	movq %rdx, -3992(%rbp)
	movl $1, -4200(%rbp)
.Lbb355:
	movq -3992(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb357
	movq %rcx, %r14
	jmp .Lbb361
.Lbb357:
	movq -16(%rdx), %r8
	movq $6917529027641081858, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb360
	movq -32(%rdx), %rdx
	cmpq $2, %rdx
	jae .Lbb360
	movq %rcx, %r14
	jmp .Lbb361
.Lbb360:
	.loc 1 38
	movq %rcx, %r14
	leaq -4200(%rbp), %rcx
	leaq -3992(%rbp), %rdx
	movq %rsi, %r13
	movq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %ecx
	movq -88(%rbp), %rax
	cmpl $0, %ecx
	jz .Lbb2149
.Lbb361:
	movq %rsi, %r13
	movq -3992(%rbp), %rsi
	movq %rax, -4080(%rbp)
	.loc 1 38
	leaq -4080(%rbp), %rdx
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_list_append
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	cmpl $0, %eax
	jnz .Lbb364
	movq %rbx, %rdi
	.loc 1 38
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	ud2
.Lbb364:
	movq -4152(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb372
	movq -16(%rdx), %rax
	movq $4611686018427387906, %r8
	andq %r8, %rax
	cmpq $0, %rax
	jnz .Lbb371
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb370
	movq %rcx, %r14
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb369
	.loc 1 38
	movq %rsi, %r13
	leaq -4152(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	jmp .Lbb372
.Lbb369:
	movq %r14, %rcx
.Lbb370:
	movq %rax, -32(%rdx)
.Lbb371:
	movq $0, -4152(%rbp)
.Lbb372:
	movq myl_lit_4a00641ab05bcbe6d1b38f5b152ad1f7a483fb86c6af5dc0ee9c09d98f25374a(%rip), %rax
	movq %rax, -96(%rbp)
	movq %rax, -4120(%rbp)
	movq -4120(%rbp), %rdx
	movq %rdx, -4112(%rbp)
	movq -4112(%rbp), %rdx
	movq %rdx, -4152(%rbp)
	movl -4200(%rbp), %edx
	testl $0, %edx
	jz .Lbb393
	movq -3992(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb380
	movq -16(%rdx), %r8
	movq $4611686018427387906, %r9
	andq %r8, %r9
	cmpq $0, %r9
	jnz .Lbb379
	movq -32(%rdx), %r8
	addq $1, %r8
	jz .Lbb377
	movq %r8, -32(%rdx)
	jmp .Lbb380
.Lbb377:
	movq %rbx, %rdi
	.loc 1 41
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb379:
	movq $4611686018427387904, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb381
.Lbb380:
	movq %rdx, -4112(%rbp)
	jmp .Lbb383
.Lbb381:
	.loc 1 41
	movq %rcx, %r14
	leaq -3992(%rbp), %rdx
	movq %rsi, %r13
	leaq -4112(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_retain
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %edx
	movq -96(%rbp), %rax
	cmpl $0, %edx
	jnz .Lbb383
	.loc 1 41
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 41
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb383:
	movl -4200(%rbp), %edx
	cmpl $0, %edx
	jz .Lbb392
	movl $0, -4200(%rbp)
	movq -3992(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb392
	movq -16(%r8), %rdx
	movq $4611686018427387906, %r9
	andq %r9, %rdx
	cmpq $0, %rdx
	jnz .Lbb391
	movq -32(%r8), %rdx
	subq $1, %rdx
	jnz .Lbb390
	movq %rcx, %r14
	movq -24(%r8), %rcx
	cmpq $0, %rcx
	jnz .Lbb389
	.loc 1 41
	movq %rsi, %r13
	leaq -3992(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movq -96(%rbp), %rax
	jmp .Lbb392
.Lbb389:
	movq %r14, %rcx
.Lbb390:
	movq %rdx, -32(%r8)
.Lbb391:
	movq $0, -3992(%rbp)
.Lbb392:
	movq -4112(%rbp), %rdx
	movq %rdx, -3992(%rbp)
	movl $1, -4200(%rbp)
.Lbb393:
	movq -3992(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb395
	movq %rcx, %r14
	jmp .Lbb399
.Lbb395:
	movq -16(%rdx), %r8
	movq $6917529027641081858, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb398
	movq -32(%rdx), %rdx
	cmpq $2, %rdx
	jae .Lbb398
	movq %rcx, %r14
	jmp .Lbb399
.Lbb398:
	.loc 1 41
	movq %rcx, %r14
	leaq -4200(%rbp), %rcx
	leaq -3992(%rbp), %rdx
	movq %rsi, %r13
	movq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %ecx
	movq -96(%rbp), %rax
	cmpl $0, %ecx
	jz .Lbb2149
.Lbb399:
	movq %rsi, %r13
	movq -3992(%rbp), %rsi
	movq %rax, -4080(%rbp)
	.loc 1 41
	leaq -4080(%rbp), %rdx
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_list_append
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	cmpl $0, %eax
	jnz .Lbb402
	movq %rbx, %rdi
	.loc 1 41
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	ud2
.Lbb402:
	movq -4152(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb410
	movq -16(%rdx), %rax
	movq $4611686018427387906, %r8
	andq %r8, %rax
	cmpq $0, %rax
	jnz .Lbb409
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb408
	movq %rcx, %r14
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb407
	.loc 1 41
	movq %rsi, %r13
	leaq -4152(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	jmp .Lbb410
.Lbb407:
	movq %r14, %rcx
.Lbb408:
	movq %rax, -32(%rdx)
.Lbb409:
	movq $0, -4152(%rbp)
.Lbb410:
	movq myl_lit_18c89eafb781b2d9c652089cbad879e67c59911bcd5c912b177a9a1671c17d8e(%rip), %rax
	movq %rax, -104(%rbp)
	movq %rax, -4120(%rbp)
	movq -4120(%rbp), %rdx
	movq %rdx, -4112(%rbp)
	movq -4112(%rbp), %rdx
	movq %rdx, -4152(%rbp)
	movl -4200(%rbp), %edx
	testl $0, %edx
	jz .Lbb431
	movq -3992(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb418
	movq -16(%rdx), %r8
	movq $4611686018427387906, %r9
	andq %r8, %r9
	cmpq $0, %r9
	jnz .Lbb417
	movq -32(%rdx), %r8
	addq $1, %r8
	jz .Lbb415
	movq %r8, -32(%rdx)
	jmp .Lbb418
.Lbb415:
	movq %rbx, %rdi
	.loc 1 44
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb417:
	movq $4611686018427387904, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb419
.Lbb418:
	movq %rdx, -4112(%rbp)
	jmp .Lbb421
.Lbb419:
	.loc 1 44
	movq %rcx, %r14
	leaq -3992(%rbp), %rdx
	movq %rsi, %r13
	leaq -4112(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_retain
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %edx
	movq -104(%rbp), %rax
	cmpl $0, %edx
	jnz .Lbb421
	.loc 1 44
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 44
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb421:
	movl -4200(%rbp), %edx
	cmpl $0, %edx
	jz .Lbb430
	movl $0, -4200(%rbp)
	movq -3992(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb430
	movq -16(%r8), %rdx
	movq $4611686018427387906, %r9
	andq %r9, %rdx
	cmpq $0, %rdx
	jnz .Lbb429
	movq -32(%r8), %rdx
	subq $1, %rdx
	jnz .Lbb428
	movq %rcx, %r14
	movq -24(%r8), %rcx
	cmpq $0, %rcx
	jnz .Lbb427
	.loc 1 44
	movq %rsi, %r13
	leaq -3992(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movq -104(%rbp), %rax
	jmp .Lbb430
.Lbb427:
	movq %r14, %rcx
.Lbb428:
	movq %rdx, -32(%r8)
.Lbb429:
	movq $0, -3992(%rbp)
.Lbb430:
	movq -4112(%rbp), %rdx
	movq %rdx, -3992(%rbp)
	movl $1, -4200(%rbp)
.Lbb431:
	movq -3992(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb433
	movq %rcx, %r14
	jmp .Lbb437
.Lbb433:
	movq -16(%rdx), %r8
	movq $6917529027641081858, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb436
	movq -32(%rdx), %rdx
	cmpq $2, %rdx
	jae .Lbb436
	movq %rcx, %r14
	jmp .Lbb437
.Lbb436:
	.loc 1 44
	movq %rcx, %r14
	leaq -4200(%rbp), %rcx
	leaq -3992(%rbp), %rdx
	movq %rsi, %r13
	movq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %ecx
	movq -104(%rbp), %rax
	cmpl $0, %ecx
	jz .Lbb2149
.Lbb437:
	movq %rsi, %r13
	movq -3992(%rbp), %rsi
	movq %rax, -4080(%rbp)
	.loc 1 44
	leaq -4080(%rbp), %rdx
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_list_append
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	cmpl $0, %eax
	jnz .Lbb440
	movq %rbx, %rdi
	.loc 1 44
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	ud2
.Lbb440:
	movq -4152(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb448
	movq -16(%rdx), %rax
	movq $4611686018427387906, %r8
	andq %r8, %rax
	cmpq $0, %rax
	jnz .Lbb447
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb446
	movq %rcx, %r14
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb445
	.loc 1 44
	movq %rsi, %r13
	leaq -4152(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	jmp .Lbb448
.Lbb445:
	movq %r14, %rcx
.Lbb446:
	movq %rax, -32(%rdx)
.Lbb447:
	movq $0, -4152(%rbp)
.Lbb448:
	movq myl_lit_8a59eb4ce18f56df83810e918f160a659444fbe4f14cc144a8b1ba8df97be02c(%rip), %rax
	movq %rax, -112(%rbp)
	movq %rax, -4120(%rbp)
	movq -4120(%rbp), %rdx
	movq %rdx, -4112(%rbp)
	movq -4112(%rbp), %rdx
	movq %rdx, -4152(%rbp)
	movl -4200(%rbp), %edx
	testl $0, %edx
	jz .Lbb469
	movq -3992(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb456
	movq -16(%rdx), %r8
	movq $4611686018427387906, %r9
	andq %r8, %r9
	cmpq $0, %r9
	jnz .Lbb455
	movq -32(%rdx), %r8
	addq $1, %r8
	jz .Lbb453
	movq %r8, -32(%rdx)
	jmp .Lbb456
.Lbb453:
	movq %rbx, %rdi
	.loc 1 47
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb455:
	movq $4611686018427387904, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb457
.Lbb456:
	movq %rdx, -4112(%rbp)
	jmp .Lbb459
.Lbb457:
	.loc 1 47
	movq %rcx, %r14
	leaq -3992(%rbp), %rdx
	movq %rsi, %r13
	leaq -4112(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_retain
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %edx
	movq -112(%rbp), %rax
	cmpl $0, %edx
	jnz .Lbb459
	.loc 1 47
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 47
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb459:
	movl -4200(%rbp), %edx
	cmpl $0, %edx
	jz .Lbb468
	movl $0, -4200(%rbp)
	movq -3992(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb468
	movq -16(%r8), %rdx
	movq $4611686018427387906, %r9
	andq %r9, %rdx
	cmpq $0, %rdx
	jnz .Lbb467
	movq -32(%r8), %rdx
	subq $1, %rdx
	jnz .Lbb466
	movq %rcx, %r14
	movq -24(%r8), %rcx
	cmpq $0, %rcx
	jnz .Lbb465
	.loc 1 47
	movq %rsi, %r13
	leaq -3992(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movq -112(%rbp), %rax
	jmp .Lbb468
.Lbb465:
	movq %r14, %rcx
.Lbb466:
	movq %rdx, -32(%r8)
.Lbb467:
	movq $0, -3992(%rbp)
.Lbb468:
	movq -4112(%rbp), %rdx
	movq %rdx, -3992(%rbp)
	movl $1, -4200(%rbp)
.Lbb469:
	movq -3992(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb471
	movq %rcx, %r14
	jmp .Lbb475
.Lbb471:
	movq -16(%rdx), %r8
	movq $6917529027641081858, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb474
	movq -32(%rdx), %rdx
	cmpq $2, %rdx
	jae .Lbb474
	movq %rcx, %r14
	jmp .Lbb475
.Lbb474:
	.loc 1 47
	movq %rcx, %r14
	leaq -4200(%rbp), %rcx
	leaq -3992(%rbp), %rdx
	movq %rsi, %r13
	movq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %r13, %rsi
	movq %r12, %rdi
	movl %eax, %ecx
	movq -112(%rbp), %rax
	cmpl $0, %ecx
	jz .Lbb2149
.Lbb475:
	movq %rsi, %r13
	movq -3992(%rbp), %rsi
	movq %rax, -4080(%rbp)
	.loc 1 47
	leaq -4080(%rbp), %rdx
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_list_append
	movl %r15d, %r10d
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movq -136(%rbp), %r8
	movl -124(%rbp), %edx
	movl -512(%rbp), %r11d
	cmpl $0, %eax
	jnz .Lbb478
	movq %rbx, %rdi
	.loc 1 47
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	ud2
.Lbb478:
	movq -4152(%rbp), %r9
	cmpq $0, %r9
	jnz .Lbb480
	movl %r10d, %r15d
	jmp .Lbb487
.Lbb480:
	movq -16(%r9), %rax
	movl %r10d, %r15d
	movq $4611686018427387906, %r10
	andq %r10, %rax
	cmpq $0, %rax
	jnz .Lbb486
	movq -32(%r9), %rax
	subq $1, %rax
	jnz .Lbb485
	movq %rcx, %r14
	movq -24(%r9), %rcx
	cmpq $0, %rcx
	jnz .Lbb484
	.loc 1 47
	movq %rsi, %r13
	leaq -4152(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movq -136(%rbp), %r8
	movl -124(%rbp), %edx
	movl -512(%rbp), %r11d
	jmp .Lbb487
.Lbb484:
	movq %r14, %rcx
.Lbb485:
	movq %rax, -32(%r9)
.Lbb486:
	movq $0, -4152(%rbp)
.Lbb487:
	movq -3992(%rbp), %rax
	movq %rax, -4120(%rbp)
	cmpl $0, %edx
	jnz .Lbb498
	cmpq $0, %rax
	jz .Lbb495
	movq -16(%rax), %rdx
	movq $4611686018427387906, %r9
	andq %rdx, %r9
	cmpq $0, %r9
	jnz .Lbb494
	movq -32(%rax), %rdx
	addq $1, %rdx
	jz .Lbb492
	movq %rdx, -32(%rax)
	jmp .Lbb495
.Lbb492:
	movq %rbx, %rdi
	.loc 1 51
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb494:
	movq $4611686018427387904, %r9
	andq %r9, %rdx
	cmpq $0, %rdx
	jnz .Lbb496
.Lbb495:
	movq %rax, -4112(%rbp)
	jmp .Lbb504
.Lbb496:
	.loc 1 51
	movq %rcx, %r14
	leaq -4120(%rbp), %rdx
	movq %rsi, %r13
	leaq -4112(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_retain
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movq -136(%rbp), %r8
	movl -512(%rbp), %r11d
	cmpl $0, %eax
	jnz .Lbb504
	.loc 1 51
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 51
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb498:
	movl %r15d, %edx
	orl %r11d, %edx
	jnz .Lbb502
	cmpq $0, %rax
	jz .Lbb501
	movq -16(%rax), %rax
	movq $5764607523034234881, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb502
.Lbb501:
	movq -4120(%rbp), %rax
	movq %rax, -4112(%rbp)
	movq $0, -4120(%rbp)
	jmp .Lbb504
.Lbb502:
	.loc 1 51
	movq %rcx, %r14
	leaq -4120(%rbp), %rdx
	movq %rsi, %r13
	leaq -4112(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_take
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movq -136(%rbp), %r8
	movl -512(%rbp), %r11d
	cmpl $0, %eax
	jnz .Lbb504
	.loc 1 51
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 51
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb504:
	movq -4112(%rbp), %rax
	movq %rax, -3984(%rbp)
	movl -4200(%rbp), %eax
	cmpl $0, %eax
	jnz .Lbb506
	movl %r15d, %r10d
	jmp .Lbb516
.Lbb506:
	movl $0, -4200(%rbp)
	movq -3992(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb508
	movl %r15d, %r10d
	jmp .Lbb516
.Lbb508:
	movq -16(%rdx), %rax
	movq $4611686018427387906, %r9
	andq %r9, %rax
	cmpq $0, %rax
	jnz .Lbb514
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb513
	movq %rcx, %r14
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb512
	.loc 1 51
	movq %rsi, %r13
	leaq -3992(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movl %r15d, %r10d
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movq -136(%rbp), %r8
	movl -512(%rbp), %r11d
	jmp .Lbb516
.Lbb512:
	movq %r14, %rcx
.Lbb513:
	movl %r15d, %r10d
	movq %rax, -32(%rdx)
	jmp .Lbb515
.Lbb514:
	movl %r15d, %r10d
.Lbb515:
	movq $0, -3992(%rbp)
.Lbb516:
	movq -3984(%rbp), %rax
	movq (%rax), %rax
	movq %rax, -144(%rbp)
	movq $9223372036854775807, %rdx
	cmpq %rdx, %rax
	ja .Lbb2326
	movq %rcx, %rbx
	movq %rdi, %r15
	movq %r8, %rdi
	movq %rax, %rcx
	movl $0, %edx
	movl $2, %r12d
	movl $0, %r9d
	movl $2, %eax
	movq $-1, %r14
	movl $0, %r13d
.p2align 4
.Lbb518:
	movl %edx, -3412(%rbp)
	movl %r12d, -3392(%rbp)
	movl %r9d, -188(%rbp)
	movl %eax, -212(%rbp)
	movq %r14, -2776(%rbp)
	movq %rcx, -3712(%rbp)
	cmpq %rcx, %r13
	setl %cl
	movzbq %cl, %rcx
	cmpl $0, %ecx
	jz .Lbb614
	movq -3984(%rbp), %rcx
	movq %rcx, -4120(%rbp)
	movl %eax, %r8d
	andl $24, %r8d
	cmpl $0, %r8d
	setz %r8b
	movzbl %r8b, %r8d
	andl %r9d, %r8d
	cmpl $0, %r8d
	movq -120(%rbp), %r8
	jnz .Lbb549
	cmpq $0, %rcx
	jz .Lbb526
	movq -16(%rcx), %r10
	movq $4611686018427387906, %r11
	andq %r11, %r10
	cmpq $0, %r10
	jnz .Lbb526
	movq -24(%rcx), %r10
	addq $1, %r10
	jz .Lbb524
	movq %r10, -24(%rcx)
	jmp .Lbb526
.Lbb524:
	movq -2760(%rbp), %rdi
	.loc 1 67
	movl $2, %esi
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb526:
	movq %rcx, -4112(%rbp)
	cmpl $0, %r9d
	jnz .Lbb528
	xchgq %rdx, %r13
	jmp .Lbb548
.Lbb528:
	testl $28, %eax
	jnz .Lbb537
	movq -4152(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb536
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r9
	andq %r9, %rax
	cmpq $0, %rax
	jnz .Lbb535
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb534
	movq -24(%rcx), %r9
	cmpq $0, %r9
	jnz .Lbb534
	.loc 1 67
	movq %rsi, %r12
	leaq -4152(%rbp), %rsi
	movq %r15, %rdi
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r13, %rdx
	movq %r12, %rsi
	movq -136(%rbp), %rdi
	movq %rdx, %r13
	movl -3412(%rbp), %edx
	movl -3392(%rbp), %r12d
	movq -120(%rbp), %r8
	jmp .Lbb536
.Lbb534:
	movq %rax, -32(%rcx)
.Lbb535:
	movq $0, -4152(%rbp)
.Lbb536:
	xchgq %rdx, %r13
	jmp .Lbb548
.Lbb537:
	movq -4152(%rbp), %rcx
	cmpq $0, %rcx
	jnz .Lbb539
	xchgq %rdx, %r13
	jmp .Lbb548
.Lbb539:
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r9
	andq %r9, %rax
	cmpq $0, %rax
	jnz .Lbb546
	movq -24(%rcx), %rax
	subq $1, %rax
	jz .Lbb542
	xchgq %rdx, %r13
	jmp .Lbb545
.Lbb542:
	movq -32(%rcx), %r9
	cmpq $0, %r9
	jnz .Lbb544
	.loc 1 67
	movq %rsi, %r12
	leaq -4152(%rbp), %rsi
	movq %r15, %rdi
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_unloan
	movq %r13, %rdx
	movq %r12, %rsi
	movq -136(%rbp), %rdi
	movl -3412(%rbp), %r13d
	movl -3392(%rbp), %r12d
	movq -120(%rbp), %r8
	jmp .Lbb548
.Lbb544:
	xchgq %rdx, %r13
.Lbb545:
	movq %rax, -24(%rcx)
	jmp .Lbb547
.Lbb546:
	xchgq %rdx, %r13
.Lbb547:
	movq $0, -4152(%rbp)
.Lbb548:
	movl $16, -148(%rbp)
	jmp .Lbb556
.Lbb549:
	xchgq %rdx, %r13
	movq %rcx, %rax
	movl %r11d, %ecx
	movl %r10d, %r9d
	orl %r9d, %ecx
	jnz .Lbb554
	cmpq $0, %rax
	jz .Lbb553
	movq -16(%rax), %rax
	movq $5764607523034234881, %rcx
	andq %rcx, %rax
	cmpq $0, %rax
	jnz .Lbb554
.Lbb553:
	movq -4120(%rbp), %rax
	movq %rax, -4112(%rbp)
	movq $0, -4120(%rbp)
	jmp .Lbb555
.Lbb554:
	.loc 1 67
	movl %ebx, %ecx
	movq %rdx, %r13
	leaq -4120(%rbp), %rdx
	movq %rsi, %r12
	leaq -4112(%rbp), %rsi
	movq %r15, %rdi
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_take
	movq %r13, %rdx
	movq %r12, %rsi
	movq -136(%rbp), %rdi
	movl -3412(%rbp), %r13d
	movl -3392(%rbp), %r12d
	movq -120(%rbp), %r8
	cmpl $0, %eax
	jz .Lbb612
.Lbb555:
	movl $2, -148(%rbp)
.Lbb556:
	cmpl $0, %r13d
	jz .Lbb574
	testl $28, %r12d
	jnz .Lbb566
	movq -3976(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb574
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r9
	andq %r9, %rax
	cmpq $0, %rax
	jnz .Lbb565
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb564
	movq %rdx, %r13
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb563
	.loc 1 67
	movq %rsi, %r12
	leaq -3976(%rbp), %rsi
	movq %r15, %rdi
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r13, %rdx
	movq %r12, %rsi
	movq -136(%rbp), %rdi
	movq -120(%rbp), %r8
	jmp .Lbb574
.Lbb563:
	movq %r13, %rdx
.Lbb564:
	movq %rax, -32(%rcx)
.Lbb565:
	movq $0, -3976(%rbp)
	jmp .Lbb574
.Lbb566:
	movq -3976(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb574
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r9
	andq %r9, %rax
	cmpq $0, %rax
	jnz .Lbb573
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb572
	movq %rdx, %r13
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb571
	.loc 1 67
	movq %rsi, %r12
	leaq -3976(%rbp), %rsi
	movq %r15, %rdi
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_unloan
	movq %r13, %rdx
	movq %r12, %rsi
	movq -136(%rbp), %rdi
	movq -120(%rbp), %r8
	jmp .Lbb574
.Lbb571:
	movq %r13, %rdx
.Lbb572:
	movq %rax, -24(%rcx)
.Lbb573:
	movq $0, -3976(%rbp)
.Lbb574:
	movq -4112(%rbp), %rax
	movq %rax, -3976(%rbp)
	movq $0, -3712(%rbp)
	cmpq $0, %rdx
	jl .Lbb576
	movq %rdx, %r12
	jmp .Lbb578
.Lbb576:
	movq -3976(%rbp), %rax
	movq (%rax), %rax
	movq $9223372036854775807, %rcx
	cmpq %rcx, %rax
	ja .Lbb610
	movq %rdx, -3712(%rbp)
	movq %rax, %r12
	addq %rdx, %r12
	movq %rax, %rcx
	xorq %r12, %rcx
	movq %rdx, %r9
	xorq %r12, %r9
	andq %r9, %rcx
	cmpq $0, %rcx
	jl .Lbb608
.Lbb578:
	movq -3976(%rbp), %rax
	movq (%rax), %rcx
	cmpq %rcx, %r12
	jae .Lbb606
	movq 32(%rax), %rax
	movq %rdi, %rcx
	movq (%rax, %r12, 8), %rdi
	movq %rdi, -4120(%rbp)
	cmpq $0, %rdi
	jnz .Lbb581
	movq %rdx, %r13
	jmp .Lbb586
.Lbb581:
	movq -16(%rdi), %rax
	movq %rdx, %r13
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb586
	movq -24(%rdi), %rax
	addq $1, %rax
	jz .Lbb584
	movq %rax, -24(%rdi)
	jmp .Lbb586
.Lbb584:
	movq -2760(%rbp), %rdi
	.loc 1 80
	movl $2, %esi
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb586:
	movq %rdi, -4112(%rbp)
	movq -4112(%rbp), %rax
	movq %rax, -4152(%rbp)
	movq %rsi, -3712(%rbp)
	movq $0, -3712(%rbp)
	movq $0, -3712(%rbp)
	movq $0, -3704(%rbp)
	movq $0, -3712(%rbp)
	movq %rcx, -3712(%rbp)
	movq (%rsi), %rax
	cmpq %rax, %rcx
	jae .Lbb604
	movq 32(%rsi), %rax
	movq %rsi, %r12
	movq (%rax, %r8, 1), %rsi
	movq %rsi, -3712(%rbp)
	.loc 1 96
	callq myl_native_text_equal
	movq %r13, %rdx
	movq %r12, %rsi
	movl %eax, %r10d
	movl -152(%rbp), %r9d
	movq -136(%rbp), %rdi
	movl -148(%rbp), %r12d
	movq -120(%rbp), %r8
	movq -144(%rbp), %rcx
	movl -512(%rbp), %eax
	movq %rdx, %r13
	movl -516(%rbp), %edx
	movl %r10d, -128(%rbp)
	movq -4152(%rbp), %r11
	cmpq $0, %r11
	jnz .Lbb589
	xchgq %r13, %rdx
	jmp .Lbb598
.Lbb589:
	movq -16(%r11), %r8
	movq $4611686018427387906, %r9
	andq %r8, %r9
	movq -120(%rbp), %r8
	cmpq $0, %r9
	movl -152(%rbp), %r9d
	jnz .Lbb596
	movq -24(%r11), %r9
	subq $1, %r9
	jz .Lbb592
	xchgq %r13, %rdx
	jmp .Lbb595
.Lbb592:
	movq -32(%r11), %r8
	cmpq $0, %r8
	movq -120(%rbp), %r8
	jnz .Lbb594
	.loc 1 96
	movq %rsi, %r12
	leaq -4152(%rbp), %rsi
	movq %r15, %rdi
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_unloan
	movq %r13, %rdx
	movq %r12, %rsi
	movl -152(%rbp), %r9d
	movq -136(%rbp), %rdi
	movl -148(%rbp), %r12d
	movl -128(%rbp), %r10d
	movq -120(%rbp), %r8
	movq -144(%rbp), %rcx
	movl -512(%rbp), %eax
	movl -516(%rbp), %r13d
	jmp .Lbb598
.Lbb594:
	xchgq %r13, %rdx
.Lbb595:
	movq %r9, -24(%r11)
	movl -152(%rbp), %r9d
	jmp .Lbb597
.Lbb596:
	xchgq %r13, %rdx
.Lbb597:
	movq $0, -4152(%rbp)
.Lbb598:
	movl %r10d, %r10d
	cmpl $0, %r10d
	cmovnz %rdx, %r14
	movq $1, -3712(%rbp)
	movq $9223372036854775806, %r10
	cmpq %r10, %rdx
	jg .Lbb602
	addq $1, %rdx
	movl %eax, %r11d
	movl %r13d, %r10d
	movl $16, %eax
	movq %rdx, %r13
	movl $1, %edx
	jmp .Lbb518
.Lbb602:
	movq %rdx, %rcx
	movq -2760(%rbp), %rdi
	.loc 1 102
	movl $64, %r8d
	movq %rcx, %rbx
	movl $1, %ecx
	movq %rbx, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb604:
	movq %rax, %rdx
	movq -136(%rbp), %rsi
	movq -2760(%rbp), %rdi
	.loc 1 95
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb606:
	movq %rcx, %rdx
	movq -2760(%rbp), %rdi
	.loc 1 80
	movq %r12, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb608:
	movq %rdx, %rcx
	movq %rax, %rsi
	movq -2760(%rbp), %rdi
	.loc 1 77
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb610:
	movq %rax, %rsi
	movq -2760(%rbp), %rdi
	.loc 1 75
	movl $320, %edx
	movq %rdi, %rbx
	callq myl_qbe_fail_cast
	ud2
.Lbb612:
	movq %r15, %rdi
	movq -2760(%rbp), %rbx
	.loc 1 67
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 67
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb614:
	movq -168(%rbp), %r8
	movq %r15, %rdi
	movq -160(%rbp), %rcx
	movq -2760(%rbp), %rbx
	movq $0, -3712(%rbp)
	cmpq $0, %r14
	jl .Lbb2244
	movq $0, -3712(%rbp)
	movq (%rsi), %rdx
	cmpq %rdx, %r8
	jb .Lbb619
	movq %r8, %rsi
	movq %rbx, %rdi
	.loc 1 125
	movq %rdi, %rbx
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb619:
	movl %eax, %r12d
	movq 32(%rsi), %rax
	movq %rsi, %r15
	movq (%rax, %rcx, 1), %rsi
	.loc 1 126
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_f_ea553995adf89bda71aacc499924ca857ef3837e6859fa5807b5db027815f66e
	movq %r15, %rsi
	movq %r13, %rdi
	movq %rax, %rdx
	movl %r12d, %eax
	movl %eax, %r12d
	movq -184(%rbp), %rax
	movl -188(%rbp), %r9d
	movq -176(%rbp), %rcx
	movq %rdx, -2752(%rbp)
	cmpl $0, %r9d
	jnz .Lbb621
	movl %r9d, -192(%rbp)
	jmp .Lbb640
.Lbb621:
	testl $28, %r12d
	jnz .Lbb631
	movq -4152(%rbp), %r9
	cmpq $0, %r9
	jz .Lbb630
	movq -16(%r9), %r8
	movq $4611686018427387906, %r10
	andq %r10, %r8
	cmpq $0, %r8
	jnz .Lbb629
	movq -32(%r9), %r8
	subq $1, %r8
	jnz .Lbb628
	movq %rdx, %r15
	movq -24(%r9), %rdx
	cmpq $0, %rdx
	jnz .Lbb627
	.loc 1 126
	movq %rsi, %r13
	leaq -4152(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %r15, %rdx
	movq %r13, %rsi
	movq %r12, %rdi
	movq -184(%rbp), %rax
	movq -176(%rbp), %rcx
	jmp .Lbb630
.Lbb627:
	movq %r15, %rdx
.Lbb628:
	movq %r8, -32(%r9)
.Lbb629:
	movq $0, -4152(%rbp)
.Lbb630:
	movl $0, -192(%rbp)
	jmp .Lbb640
.Lbb631:
	movq -4152(%rbp), %r9
	cmpq $0, %r9
	jz .Lbb639
	movq -16(%r9), %r8
	movq $4611686018427387906, %r10
	andq %r10, %r8
	cmpq $0, %r8
	jnz .Lbb638
	movq -24(%r9), %r8
	subq $1, %r8
	jnz .Lbb637
	movq %rdx, %r15
	movq -32(%r9), %rdx
	cmpq $0, %rdx
	jnz .Lbb636
	.loc 1 126
	movq %rsi, %r13
	leaq -4152(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_unloan
	movq %r15, %rdx
	movq %r13, %rsi
	movq %r12, %rdi
	movq -184(%rbp), %rax
	movq -176(%rbp), %rcx
	jmp .Lbb639
.Lbb636:
	movq %r15, %rdx
.Lbb637:
	movq %r8, -24(%r9)
.Lbb638:
	movq $0, -4152(%rbp)
.Lbb639:
	movl $0, -192(%rbp)
.Lbb640:
	movq $0, -3712(%rbp)
	movq %rdx, %r15
	movq (%rsi), %rdx
	cmpq %rdx, %rax
	jb .Lbb643
	movq %rax, %rsi
	movq %rbx, %rdi
	.loc 1 142
	movq %rdi, %rbx
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb643:
	movq 32(%rsi), %rax
	movq %rsi, %r13
	movq (%rax, %rcx, 1), %rsi
	.loc 1 143
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_f_ea553995adf89bda71aacc499924ca857ef3837e6859fa5807b5db027815f66e
	movq %r15, %rdx
	movq %r13, %rsi
	movq %r12, %rdi
	movq %rax, -3344(%rbp)
	movq -208(%rbp), %r8
	movl -192(%rbp), %r9d
	movl -212(%rbp), %eax
	movq -200(%rbp), %rcx
	cmpl $0, %r9d
	jnz .Lbb645
	movl %r9d, -216(%rbp)
	jmp .Lbb664
.Lbb645:
	testl $28, %eax
	jnz .Lbb655
	movq -4152(%rbp), %r10
	cmpq $0, %r10
	jz .Lbb654
	movq -16(%r10), %r9
	movq $4611686018427387906, %r11
	andq %r11, %r9
	cmpq $0, %r9
	jnz .Lbb653
	movq -32(%r10), %r9
	subq $1, %r9
	jnz .Lbb652
	movq %rdx, %r15
	movq -24(%r10), %rdx
	cmpq $0, %rdx
	jnz .Lbb651
	.loc 1 143
	movq %rsi, %r13
	leaq -4152(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %r15, %rdx
	movq %r13, %rsi
	movq %r12, %rdi
	movq -208(%rbp), %r8
	movl -212(%rbp), %eax
	movq -200(%rbp), %rcx
	jmp .Lbb654
.Lbb651:
	movq %r15, %rdx
.Lbb652:
	movq %r9, -32(%r10)
.Lbb653:
	movq $0, -4152(%rbp)
.Lbb654:
	movl $0, -216(%rbp)
	jmp .Lbb664
.Lbb655:
	movq -4152(%rbp), %r10
	cmpq $0, %r10
	jz .Lbb663
	movq -16(%r10), %r9
	movq $4611686018427387906, %r11
	andq %r11, %r9
	cmpq $0, %r9
	jnz .Lbb662
	movq -24(%r10), %r9
	subq $1, %r9
	jnz .Lbb661
	movq %rdx, %r15
	movq -32(%r10), %rdx
	cmpq $0, %rdx
	jnz .Lbb660
	.loc 1 143
	movq %rsi, %r13
	leaq -4152(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_unloan
	movq %r15, %rdx
	movq %r13, %rsi
	movq %r12, %rdi
	movq -208(%rbp), %r8
	movl -212(%rbp), %eax
	movq -200(%rbp), %rcx
	jmp .Lbb663
.Lbb660:
	movq %r15, %rdx
.Lbb661:
	movq %r9, -24(%r10)
.Lbb662:
	movq $0, -4152(%rbp)
.Lbb663:
	movl $0, -216(%rbp)
.Lbb664:
	movq $0, -3712(%rbp)
	movq %rdx, %r15
	movq (%rsi), %rdx
	cmpq %rdx, %r8
	jb .Lbb667
	movq %r8, %rsi
	movq %rbx, %rdi
	.loc 1 159
	movq %rdi, %rbx
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb667:
	movl %eax, %r12d
	movq 32(%rsi), %rax
	movq (%rax, %rcx, 1), %rsi
	.loc 1 160
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_f_ea553995adf89bda71aacc499924ca857ef3837e6859fa5807b5db027815f66e
	movq %r15, %rdx
	movq %r13, %rdi
	movq %rax, %r9
	movl %r12d, %eax
	movl -216(%rbp), %r8d
	movq %rdx, %r13
	movl -3412(%rbp), %edx
	movl -3392(%rbp), %esi
	movq -3344(%rbp), %rcx
	movq %r9, -3088(%rbp)
	cmpl $0, %r8d
	jnz .Lbb669
	movl %esi, %r15d
	movq %r13, %r12
	movl %edx, %r13d
	jmp .Lbb693
.Lbb669:
	testl $28, %eax
	jnz .Lbb681
	movq -4152(%rbp), %r8
	cmpq $0, %r8
	jnz .Lbb672
	movq %r9, %r15
	movq %r13, %r12
	jmp .Lbb680
.Lbb672:
	movq -16(%r8), %rax
	movq $4611686018427387906, %r10
	andq %r10, %rax
	cmpq $0, %rax
	jnz .Lbb678
	movq -32(%r8), %rax
	subq $1, %rax
	jz .Lbb675
	movq %r9, %r15
	jmp .Lbb677
.Lbb675:
	movq %r9, %r15
	movq -24(%r8), %r9
	cmpq $0, %r9
	jnz .Lbb677
	.loc 1 160
	leaq -4152(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %r13, %rdx
	movq %r12, %rdi
	movq %rdx, %r12
	movl -3412(%rbp), %edx
	movl -3392(%rbp), %esi
	movq -3344(%rbp), %rcx
	jmp .Lbb680
.Lbb677:
	movq %r13, %r12
	movq %rax, -32(%r8)
	jmp .Lbb679
.Lbb678:
	movq %r9, %r15
	movq %r13, %r12
.Lbb679:
	movq $0, -4152(%rbp)
.Lbb680:
	movl %edx, %r13d
	movq %r15, %r9
	movl %esi, %r15d
	jmp .Lbb693
.Lbb681:
	movq %r9, %r15
	movq %r13, %r12
	movl %edx, %r13d
	movq -4152(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb684
	movq %r15, %r9
	movl %esi, %r15d
	jmp .Lbb693
.Lbb684:
	movq -16(%rdx), %rax
	movq $4611686018427387906, %r8
	andq %r8, %rax
	cmpq $0, %rax
	jnz .Lbb691
	movq -24(%rdx), %rax
	subq $1, %rax
	jz .Lbb687
	movq %r15, %r9
	jmp .Lbb690
.Lbb687:
	movq -32(%rdx), %r8
	cmpq $0, %r8
	jnz .Lbb689
	.loc 1 160
	leaq -4152(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_unloan
	movq %r15, %r9
	movq %r13, %rdi
	movl -3412(%rbp), %r13d
	movl -3392(%rbp), %r15d
	movq -3344(%rbp), %rcx
	jmp .Lbb693
.Lbb689:
	movq %r15, %r9
.Lbb690:
	movl %esi, %r15d
	movq %rax, -24(%rdx)
	jmp .Lbb692
.Lbb691:
	movq %r15, %r9
	movl %esi, %r15d
.Lbb692:
	movq $0, -4152(%rbp)
.Lbb693:
	movq $2, -3712(%rbp)
	cmpq $2, %r12
	jl .Lbb695
	movq $1, -3712(%rbp)
	cmpq $1, %rcx
	setl %al
	movzbq %al, %rax
	jmp .Lbb696
.Lbb695:
	movl $1, %eax
.Lbb696:
	cmpl $0, %eax
	jnz .Lbb698
	movq $1, -3712(%rbp)
	cmpq $1, %r9
	setl %al
	movzbq %al, %rax
	jmp .Lbb699
.Lbb698:
	movl $1, %eax
.Lbb699:
	cmpl $0, %eax
	jnz .Lbb701
	movq $1000000, -3712(%rbp)
	cmpq $1000000, %r9
	setg %al
	movzbq %al, %rax
	jmp .Lbb702
.Lbb701:
	movl $1, %eax
.Lbb702:
	cmpl $0, %eax
	jnz .Lbb2162
	movq %r12, -3712(%rbp)
	cmpq $0, %r12
	setg %al
	movzbq %al, %rax
	movq %r12, %rcx
	xorq %r12, %rcx
	movq %r12, %r13
	andq %rcx, %r13
	movq %r13, -472(%rbp)
	cmpq $0, %r12
	setl %sil
	movzbq %sil, %rsi
	movq %rsi, -536(%rbp)
	cmpl $0, %eax
	jnz .Lbb705
	movl $0, %edx
	jmp .Lbb708
.Lbb705:
	movq $0, -3712(%rbp)
	movq $0, -3712(%rbp)
	cmpq $0, %r13
	jl .Lbb2160
	cmpq $0, %r12
	jl .Lbb2158
	movq %r12, %rdx
.Lbb708:
	.loc 1 228
	movq myl_t_1a91deb3742283487d66c3b500f6effd7ef1170e6d4b4368fe9ec3c3f0354fda@gotpcrel(%rip), %rsi
	movq %rdi, %r13
	callq myl_native_list_new
	movq %r13, %rdi
	movl -220(%rbp), %r13d
	movq -504(%rbp), %rcx
	movq -3088(%rbp), %r9
	movl -512(%rbp), %r11d
	movl -516(%rbp), %r10d
	cmpl $0, %eax
	jnz .Lbb711
	movq %rbx, %rdi
	.loc 1 228
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	ud2
.Lbb711:
	movq %rax, -4120(%rbp)
	movq -4120(%rbp), %rsi
	movq %rsi, -4112(%rbp)
	movq -4112(%rbp), %rsi
	movq %rsi, -4152(%rbp)
	movq %rax, -4120(%rbp)
	movl %r10d, %esi
	orl %r11d, %esi
	jnz .Lbb715
	cmpq $0, %rax
	jz .Lbb714
	movq -16(%rax), %rax
	movq $5764607523034234881, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb715
.Lbb714:
	movq -4120(%rbp), %rax
	movq %rax, -4112(%rbp)
	movq $0, -4120(%rbp)
	jmp .Lbb717
.Lbb715:
	movq %r12, %rdx
	.loc 1 229
	movq %rdx, %r12
	leaq -4120(%rbp), %rdx
	leaq -4112(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_take
	movq %r13, %rdi
	movl -220(%rbp), %r13d
	movq -504(%rbp), %rcx
	movq -3088(%rbp), %r9
	cmpl $0, %eax
	jnz .Lbb717
	.loc 1 229
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 229
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb717:
	movl -4192(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb725
	movl $0, -4192(%rbp)
	movq -3968(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb725
	movq -16(%rsi), %rax
	movq $4611686018427387906, %r8
	andq %r8, %rax
	cmpq $0, %rax
	jnz .Lbb724
	movq -32(%rsi), %rax
	subq $1, %rax
	jnz .Lbb723
	movq -24(%rsi), %r8
	cmpq $0, %r8
	jnz .Lbb723
	.loc 1 229
	leaq -3968(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %r13, %rdi
	movl -220(%rbp), %r13d
	movq -504(%rbp), %rcx
	movq -3088(%rbp), %r9
	jmp .Lbb725
.Lbb723:
	movq %rax, -32(%rsi)
.Lbb724:
	movq $0, -3968(%rbp)
.Lbb725:
	movq -4112(%rbp), %rax
	movq %rax, -3968(%rbp)
	movl $1, -4192(%rbp)
	cmpl $16, %r13d
	jnz .Lbb755
	movq -3968(%rbp), %rax
	cmpq $0, %rax
	jz .Lbb733
	movq -16(%rax), %rsi
	movq $4611686018427387906, %r8
	andq %rsi, %r8
	cmpq $0, %r8
	jnz .Lbb732
	movq -32(%rax), %rcx
	addq $1, %rcx
	jz .Lbb730
	movq %rcx, -32(%rax)
	jmp .Lbb733
.Lbb730:
	movq %rbx, %rdi
	.loc 1 230
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb732:
	movq $4611686018427387904, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb734
.Lbb733:
	movq %rax, -4112(%rbp)
	jmp .Lbb737
.Lbb734:
	movq %r12, %rdx
	.loc 1 230
	movq %rdx, %r12
	leaq -3968(%rbp), %rdx
	leaq -4112(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_retain
	movq %r13, %rdi
	movl -220(%rbp), %r13d
	movq -3088(%rbp), %r9
	cmpl $0, %eax
	jnz .Lbb737
	.loc 1 230
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 230
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb737:
	movl -4192(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb753
	movl $0, -4192(%rbp)
	testl $28, %r13d
	jnz .Lbb746
	movq -3968(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb753
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb745
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb744
	movq -24(%rcx), %rsi
	cmpq $0, %rsi
	jnz .Lbb744
	.loc 1 230
	leaq -3968(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %r13, %rdi
	movq -3088(%rbp), %r9
	jmp .Lbb753
.Lbb744:
	movq %rax, -32(%rcx)
.Lbb745:
	movq $0, -3968(%rbp)
	jmp .Lbb753
.Lbb746:
	movq -3968(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb753
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb752
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb751
	movq -32(%rcx), %rsi
	cmpq $0, %rsi
	jnz .Lbb751
	.loc 1 230
	leaq -3968(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movq %r13, %rdi
	movq -3088(%rbp), %r9
	jmp .Lbb753
.Lbb751:
	movq %rax, -24(%rcx)
.Lbb752:
	movq $0, -3968(%rbp)
.Lbb753:
	movq -4112(%rbp), %rax
	movq %rax, -3968(%rbp)
	movl $1, -4192(%rbp)
	movl $2, %r13d
.Lbb755:
	movl %r13d, -224(%rbp)
	cmpl $8, %r13d
	jz .Lbb761
	movq -3968(%rbp), %rax
	cmpq $0, %rax
	jz .Lbb760
	movq -16(%rax), %rcx
	movq $6917529027641081858, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb759
	movq -32(%rax), %rax
	cmpq $2, %rax
	jb .Lbb760
.Lbb759:
	movq %r12, %rdx
	.loc 1 230
	leaq -4192(%rbp), %rcx
	movq %rdx, %r12
	leaq -3968(%rbp), %rdx
	movq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527@gotpcrel(%rip), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %r13, %rdi
	movq -3088(%rbp), %r9
	cmpl $0, %eax
	jz .Lbb2149
.Lbb760:
	movl $2, -3416(%rbp)
	jmp .Lbb766
.Lbb761:
	movq -3968(%rbp), %rax
	cmpq $0, %rax
	jz .Lbb765
	movq -16(%rax), %rcx
	movq $6917529027641081858, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb764
	movq -32(%rax), %rax
	cmpq $2, %rax
	jb .Lbb765
.Lbb764:
	movq %r12, %rdx
	.loc 1 230
	movl $0, %ecx
	movq %rdx, %r12
	leaq -3968(%rbp), %rdx
	movq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527@gotpcrel(%rip), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_held
	movq %r13, %rdi
	movl -224(%rbp), %r13d
	movq -3088(%rbp), %r9
	cmpl $0, %eax
	jz .Lbb2149
.Lbb765:
	movl %r13d, -3416(%rbp)
.Lbb766:
	cmpq $0, %r12
	setg %sil
	movzbq %sil, %rsi
	movq %rsi, -312(%rbp)
	cmpq $16, %r12
	setae %r8b
	movzbq %r8b, %r8
	movq %r8, -304(%rbp)
	testq %rsi, %r8
	jnz .Lbb768
	movq %rdi, %r15
	movq %r12, %rax
	movl $0, %ecx
	movl $0, %ebx
	jmp .Lbb778
.Lbb768:
	movq $144115188075855872, %rax
	movq %r12, %rcx
	addq %rax, %rcx
	movq $288230376151711744, %rax
	cmpq %rax, %rcx
	jbe .Lbb770
	movq %rdi, %r15
	movq %r12, %rax
	movl $0, %ecx
	movl $0, %ebx
	jmp .Lbb778
.Lbb770:
	movq $144115188075855872, %rax
	movq %r9, %rcx
	addq %rax, %rcx
	movq $288230376151711744, %rax
	cmpq %rax, %rcx
	jbe .Lbb772
	movq %rdi, %r15
	movq %r12, %rax
	movl $0, %ecx
	movl $0, %ebx
	jmp .Lbb778
.Lbb772:
	movq -3968(%rbp), %rsi
	movq 8(%rsi), %rax
	movq (%rsi), %rcx
	movq %rcx, -240(%rbp)
	subq %rcx, %rax
	cmpq %r12, %rax
	jae .Lbb774
	movq %rdi, %r15
	movq %r12, %rax
	movl $0, %ecx
	movl $0, %ebx
	jmp .Lbb778
.Lbb774:
	movq 32(%rsi), %r10
	movq %r10, -248(%rbp)
	movq 16(%rsi), %rcx
	movq %rcx, -232(%rbp)
	.loc 1 230
	movq %rdi, %r13
	callq myl_rc_list_plain_ready
	movq %r13, %rdi
	movq -232(%rbp), %rsi
	movq -248(%rbp), %r10
	movq -240(%rbp), %rcx
	movq -3088(%rbp), %r9
	cmpl $0, %eax
	jnz .Lbb776
	movq %rdi, %r15
	movq %r12, %rax
	movl $0, %ecx
	movl $0, %ebx
	jmp .Lbb778
.Lbb776:
	movq $4611686018427387904, %rax
	cmpq %rax, %rsi
	jb .Lbb798
	movq %rdi, %r15
	movq %r12, %rax
	movl $0, %ecx
	movl $0, %ebx
.p2align 4
.Lbb778:
	movq %rax, -3712(%rbp)
	cmpq %rax, %rbx
	jge .Lbb797
	movq %rbx, -3712(%rbp)
	movq $37, -3704(%rbp)
	imulq $37, %rbx, %rdi
	movl $4294967295, %esi
	movq %rbx, %r11
	andq %rsi, %r11
	movq %rbx, %r10
	shrq $32, %r10
	imulq $37, %r11, %rsi
	shrq $32, %rsi
	imulq $37, %r10, %r8
	addq %rsi, %r8
	movl $4294967295, %esi
	andq %r8, %rsi
	shrq $32, %r8
	imulq $0, %r11, %r11
	addq %r11, %rsi
	shrq $32, %rsi
	imulq $0, %r10, %r10
	addq %r10, %r8
	addq %r8, %rsi
	cmpq $0, %rbx
	setl %r8b
	movzbq %r8b, %r8
	negq %r8
	movq %r8, %r10
	andq $37, %r10
	movq %rbx, %r8
	andq $0, %r8
	subq %r10, %rsi
	subq %r8, %rsi
	movq %rdi, %r8
	sarq $63, %r8
	cmpq %rsi, %r8
	jnz .Lbb795
	movq %rdi, -3712(%rbp)
	movq %r9, %rsi
	addq %rdi, %rsi
	movq %r9, %r8
	xorq %rsi, %r8
	movq %r9, %r13
	movq %rdi, %r9
	xorq %rsi, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jl .Lbb793
	movq $1009, -3712(%rbp)
	movq %rsi, %rdi
	sarq $63, %rdi
	movq %rax, %r12
	movq %rdi, %rax
	xorq %rsi, %rax
	subq %rdi, %rax
	movq $-9086255505087856445, %r8
	mulq %r8
	movq %r12, %rax
	movq %rdx, %r8
	shrq $9, %r8
	xorq %rdi, %r8
	subq %rdi, %r8
	imulq $1009, %r8, %r8
	subq %r8, %rsi
	cmpq $0, %rsi
	setnz %r8b
	movzbq %r8b, %r8
	andq %r8, %rdi
	negq %rdi
	andq $1009, %rdi
	movq %rsi, %r10
	addq %rdi, %r10
	movq %r10, -264(%rbp)
	movq -3968(%rbp), %rdi
	movq %rdi, -280(%rbp)
	movq (%rdi), %r8
	movq %r8, -272(%rbp)
	movq %rax, %r12
	movq 8(%rdi), %rax
	movq 16(%rdi), %rsi
	movq %rsi, -256(%rbp)
	cmpq %rax, %r8
	jae .Lbb784
	cmpl $0, %ecx
	jnz .Lbb788
	.loc 1 241
	movq %rdi, %rsi
	movq %r15, %rdi
	callq myl_rc_list_plain_ready
	movl %eax, %ecx
	movq -256(%rbp), %rsi
	movq -272(%rbp), %r8
	movq -280(%rbp), %rdi
	movq -264(%rbp), %r10
	cmpl $0, %ecx
	jnz .Lbb788
.Lbb784:
	movq %r10, -4080(%rbp)
	.loc 1 241
	leaq -4080(%rbp), %rdx
	movq %rdi, %rsi
	movq %r15, %rdi
	callq myl_rc_list_append
	movq %r13, %r9
	movl %eax, %ecx
	movq %r12, %rax
	cmpl $0, %ecx
	jz .Lbb786
	movl $0, %ecx
	jmp .Lbb789
.Lbb786:
	movq -2760(%rbp), %rdi
	.loc 1 241
	callq myl_qbe_fail_allocation
	ud2
.Lbb788:
	movq %r13, %r9
	movq %r12, %rax
	movq 32(%rdi), %r11
	movq %r10, (%r11, %r8, 8)
	addq $1, %r8
	movq %r8, (%rdi)
	addq $1, %rsi
	movq %rsi, 16(%rdi)
.Lbb789:
	movq $1, -3712(%rbp)
	movq $9223372036854775806, %rsi
	cmpq %rsi, %rbx
	jg .Lbb791
	addq $1, %rbx
	jmp .Lbb778
.Lbb791:
	movq %rbx, %rdx
	movq -2760(%rbp), %rdi
	.loc 1 245
	movl $64, %r8d
	movl $1, %ecx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb793:
	movq %rdi, %rcx
	movq %r13, %r9
	movq -2760(%rbp), %rdi
	.loc 1 238
	movl $64, %r8d
	movq %r9, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb795:
	movq %rbx, %rdx
	movq -2760(%rbp), %rdi
	.loc 1 237
	movl $64, %r8d
	movl $37, %ecx
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb797:
	movl -3416(%rbp), %r12d
	movl -284(%rbp), %esi
	movq -2776(%rbp), %r14
	movq -504(%rbp), %rcx
	movq -472(%rbp), %r13
	movl -512(%rbp), %r11d
	movl -516(%rbp), %r10d
	movq -2760(%rbp), %rbx
	jmp .Lbb802
.Lbb798:
	movq %rdi, %r15
	movq %r12, %rax
	movq %rbx, %rdi
	movl $0, %r8d
.p2align 4
.Lbb799:
	movq %rax, -3712(%rbp)
	cmpq %rax, %r8
	jge .Lbb801
	movq %r8, -3712(%rbp)
	movq $37, -3704(%rbp)
	imulq $37, %r8, %r11
	movq %r11, -3712(%rbp)
	addq %r9, %r11
	movq $1009, -3712(%rbp)
	movq %r11, %rbx
	sarq $63, %rbx
	movq %rax, %r12
	movq %r11, %rax
	xorq %rbx, %rax
	subq %rbx, %rax
	movq $-9086255505087856445, %r13
	mulq %r13
	movq %r12, %rax
	movq %rdx, %r12
	shrq $9, %r12
	xorq %rbx, %r12
	subq %rbx, %r12
	imulq $1009, %r12, %r12
	subq %r12, %r11
	cmpq $0, %r11
	setnz %r12b
	movzbq %r12b, %r12
	andq %r12, %rbx
	negq %rbx
	andq $1009, %rbx
	addq %r11, %rbx
	movq -3968(%rbp), %r11
	movq %rbx, (%r10, %rcx, 8)
	addq $1, %rcx
	movq %rcx, (%r11)
	addq $1, %rsi
	movq %rsi, 16(%r11)
	movq $1, -3712(%rbp)
	addq $1, %r8
	jmp .Lbb799
.Lbb801:
	movl -3416(%rbp), %r12d
	movl -284(%rbp), %esi
	movq -504(%rbp), %rcx
	movq -472(%rbp), %r13
	movl -512(%rbp), %r11d
	movl -516(%rbp), %r10d
	movq %rdi, %rbx
.Lbb802:
	movq %rax, %rdx
	movq %r15, %rdi
	movq -3968(%rbp), %rax
	cmpl $8, %r12d
	setz %r8b
	movzbl %r8b, %r8d
	movl -4192(%rbp), %r9d
	andl %r9d, %r8d
	cmpl $0, %r8d
	jnz .Lbb804
	movl %esi, %r8d
	movq %rax, %rsi
	movl $2, %eax
	jmp .Lbb814
.Lbb804:
	cmpq $0, %rax
	jnz .Lbb806
	movq %rax, %rsi
	jmp .Lbb812
.Lbb806:
	movq -16(%rax), %rsi
	movq $4611686018427387906, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb811
	movq %rax, %rsi
	movq -24(%rax), %rax
	addq $1, %rax
	jz .Lbb809
	movq %rax, -24(%rsi)
	jmp .Lbb812
.Lbb809:
	movq %rbx, %rdi
	.loc 1 248
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb811:
	movq %rax, %rsi
.Lbb812:
	movq %rsi, -4112(%rbp)
	movq %rsi, -4152(%rbp)
	movl $1, %r8d
	movl $8, %eax
.Lbb814:
	movl %r8d, -288(%rbp)
	movl %eax, -292(%rbp)
	movq %rsi, -4120(%rbp)
	movl %eax, %r9d
	andl $24, %r9d
	cmpl $0, %r9d
	setz %r9b
	movzbl %r9b, %r9d
	testl %r9d, %r8d
	jnz .Lbb844
	cmpq $0, %rsi
	jz .Lbb823
	movq -16(%rsi), %r9
	movq $4611686018427387906, %r10
	andq %r9, %r10
	cmpq $0, %r10
	jnz .Lbb822
	movl %r8d, %ecx
	movl %ecx, %r8d
	movq -32(%rsi), %rcx
	addq $1, %rcx
	jz .Lbb820
	movq %rcx, -32(%rsi)
	jmp .Lbb823
.Lbb820:
	movq %rbx, %rdi
	.loc 1 250
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb822:
	movq $4611686018427387904, %r10
	andq %r10, %r9
	cmpq $0, %r9
	jnz .Lbb824
.Lbb823:
	movl %r8d, %ecx
	movq %rsi, -4112(%rbp)
	jmp .Lbb826
.Lbb824:
	.loc 1 250
	movq %rdx, %r15
	leaq -4120(%rbp), %rdx
	leaq -4112(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_retain
	movq %r15, %rdx
	movq %r13, %rdi
	movl %eax, %esi
	movl -288(%rbp), %ecx
	movl -292(%rbp), %eax
	movq -472(%rbp), %r13
	cmpl $0, %esi
	jnz .Lbb826
	.loc 1 250
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 250
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb826:
	cmpl $0, %ecx
	jz .Lbb851
	testl $28, %eax
	jnz .Lbb836
	movq -4152(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb851
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb835
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb834
	movq %rdx, %r15
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb833
	.loc 1 250
	leaq -4152(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %r15, %rdx
	movq %r13, %rdi
	movq -472(%rbp), %r13
	jmp .Lbb851
.Lbb833:
	movq %r15, %rdx
.Lbb834:
	movq %rax, -32(%rcx)
.Lbb835:
	movq $0, -4152(%rbp)
	jmp .Lbb851
.Lbb836:
	movq -4152(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb851
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb843
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb842
	movq %rdx, %r15
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb841
	.loc 1 250
	leaq -4152(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movq %r15, %rdx
	movq %r13, %rdi
	movq -472(%rbp), %r13
	jmp .Lbb851
.Lbb841:
	movq %r15, %rdx
.Lbb842:
	movq %rax, -24(%rcx)
.Lbb843:
	movq $0, -4152(%rbp)
	jmp .Lbb851
.Lbb844:
	movq %rsi, %rax
	movl %r10d, %esi
	orl %r11d, %esi
	jnz .Lbb849
	cmpq $0, %rax
	jz .Lbb848
	movq -16(%rax), %rax
	movq $5764607523034234881, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb849
.Lbb848:
	movq -4120(%rbp), %rax
	movq %rax, -4112(%rbp)
	movq $0, -4120(%rbp)
	jmp .Lbb851
.Lbb849:
	.loc 1 250
	movq %rdx, %r15
	leaq -4120(%rbp), %rdx
	leaq -4112(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_take
	movq %r15, %rdx
	movq %r13, %rdi
	movq -472(%rbp), %r13
	cmpl $0, %eax
	jnz .Lbb851
	.loc 1 250
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 250
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb851:
	movq -4112(%rbp), %rax
	movq %rax, -3960(%rbp)
	movl -4192(%rbp), %eax
	cmpl $0, %eax
	jnz .Lbb853
	movq %rdx, %r12
	jmp .Lbb873
.Lbb853:
	movl $0, -4192(%rbp)
	testl $28, %r12d
	jnz .Lbb863
	movq -3968(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb862
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb861
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb860
	movq %rdx, %r15
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb859
	.loc 1 250
	leaq -3968(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %r15, %rdx
	movq %r12, %rdi
	jmp .Lbb862
.Lbb859:
	movq %r15, %rdx
.Lbb860:
	movq %rax, -32(%rcx)
.Lbb861:
	movq $0, -3968(%rbp)
.Lbb862:
	movq %rdx, %r12
	jmp .Lbb873
.Lbb863:
	movq -3968(%rbp), %rcx
	cmpq $0, %rcx
	jnz .Lbb865
	movq %rdx, %r12
	jmp .Lbb873
.Lbb865:
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb871
	movq -24(%rcx), %rax
	subq $1, %rax
	jz .Lbb868
	movq %rdx, %r12
	jmp .Lbb870
.Lbb868:
	movq %rdx, %r12
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb870
	.loc 1 250
	leaq -3968(%rbp), %rsi
	movq %rdi, %r15
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movq %r15, %rdi
	jmp .Lbb873
.Lbb870:
	movq %rax, -24(%rcx)
	jmp .Lbb872
.Lbb871:
	movq %rdx, %r12
.Lbb872:
	movq $0, -3968(%rbp)
.Lbb873:
	movq %r12, -3712(%rbp)
	cmpq $0, %r12
	jg .Lbb875
	movl $0, %edx
	jmp .Lbb878
.Lbb875:
	movq $0, -3712(%rbp)
	movq $0, -3712(%rbp)
	cmpq $0, %r13
	jl .Lbb2156
	cmpq $0, %r12
	jl .Lbb2154
	movq %r12, %rdx
.Lbb878:
	.loc 1 293
	movq myl_t_1a91deb3742283487d66c3b500f6effd7ef1170e6d4b4368fe9ec3c3f0354fda@gotpcrel(%rip), %rsi
	movq %rdi, %r13
	callq myl_native_list_new
	movq %r13, %rdi
	movl -296(%rbp), %r13d
	movq -504(%rbp), %rcx
	movq -304(%rbp), %r8
	movq -312(%rbp), %rsi
	movq -3088(%rbp), %r9
	movl -512(%rbp), %r11d
	movl -516(%rbp), %r10d
	cmpl $0, %eax
	jnz .Lbb881
	movq %rbx, %rdi
	.loc 1 293
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	ud2
.Lbb881:
	movq %rax, -4120(%rbp)
	movq -4120(%rbp), %r15
	movq %r15, -4112(%rbp)
	movq -4112(%rbp), %r15
	movq %r15, -4152(%rbp)
	movq %rax, -4120(%rbp)
	orl %r11d, %r10d
	jnz .Lbb885
	cmpq $0, %rax
	jz .Lbb884
	movq -16(%rax), %rax
	movq $5764607523034234881, %r10
	andq %r10, %rax
	cmpq $0, %rax
	jnz .Lbb885
.Lbb884:
	movq -4120(%rbp), %rax
	movq %rax, -4112(%rbp)
	movq $0, -4120(%rbp)
	jmp .Lbb887
.Lbb885:
	movq %r12, %rdx
	.loc 1 294
	movq %rdx, %r12
	leaq -4120(%rbp), %rdx
	leaq -4112(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_take
	movq %r13, %rdi
	movl -296(%rbp), %r13d
	movq -504(%rbp), %rcx
	movq -304(%rbp), %r8
	movq -312(%rbp), %rsi
	movq -3088(%rbp), %r9
	cmpl $0, %eax
	jnz .Lbb887
	.loc 1 294
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 294
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb887:
	movl -4184(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb895
	movl $0, -4184(%rbp)
	movq -3952(%rbp), %r10
	cmpq $0, %r10
	jz .Lbb895
	movq -16(%r10), %rax
	movq $4611686018427387906, %r11
	andq %r11, %rax
	cmpq $0, %rax
	jnz .Lbb894
	movq -32(%r10), %rax
	subq $1, %rax
	jnz .Lbb893
	movq -24(%r10), %r11
	cmpq $0, %r11
	jnz .Lbb893
	.loc 1 294
	leaq -3952(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %r13, %rdi
	movl -296(%rbp), %r13d
	movq -504(%rbp), %rcx
	movq -304(%rbp), %r8
	movq -312(%rbp), %rsi
	movq -3088(%rbp), %r9
	jmp .Lbb895
.Lbb893:
	movq %rax, -32(%r10)
.Lbb894:
	movq $0, -3952(%rbp)
.Lbb895:
	movq -4112(%rbp), %rax
	movq %rax, -3952(%rbp)
	movl $1, -4184(%rbp)
	cmpl $16, %r13d
	jnz .Lbb925
	movq -3952(%rbp), %rax
	cmpq $0, %rax
	jz .Lbb903
	movq -16(%rax), %r10
	movq $4611686018427387906, %r11
	andq %r10, %r11
	cmpq $0, %r11
	jnz .Lbb902
	movq -32(%rax), %rcx
	addq $1, %rcx
	jz .Lbb900
	movq %rcx, -32(%rax)
	jmp .Lbb903
.Lbb900:
	movq %rbx, %rdi
	.loc 1 295
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb902:
	movq $4611686018427387904, %r11
	andq %r11, %r10
	cmpq $0, %r10
	jnz .Lbb904
.Lbb903:
	movq %rax, -4112(%rbp)
	jmp .Lbb907
.Lbb904:
	movq %r12, %rdx
	.loc 1 295
	movq %rcx, %r13
	movq %rdx, %r12
	leaq -3952(%rbp), %rdx
	leaq -4112(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_retain
	movq %r13, %rdi
	movl -296(%rbp), %r13d
	movq -304(%rbp), %r8
	movq -312(%rbp), %rsi
	movq -3088(%rbp), %r9
	cmpl $0, %eax
	jnz .Lbb907
	.loc 1 295
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 295
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb907:
	movl -4184(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb923
	movl $0, -4184(%rbp)
	testl $28, %r13d
	jnz .Lbb916
	movq -3952(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb923
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r10
	andq %r10, %rax
	cmpq $0, %rax
	jnz .Lbb915
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb914
	movq -24(%rcx), %r10
	cmpq $0, %r10
	jnz .Lbb914
	.loc 1 295
	leaq -3952(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %r13, %rdi
	movq -304(%rbp), %r8
	movq -312(%rbp), %rsi
	movq -3088(%rbp), %r9
	jmp .Lbb923
.Lbb914:
	movq %rax, -32(%rcx)
.Lbb915:
	movq $0, -3952(%rbp)
	jmp .Lbb923
.Lbb916:
	movq -3952(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb923
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r10
	andq %r10, %rax
	cmpq $0, %rax
	jnz .Lbb922
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb921
	movq -32(%rcx), %r10
	cmpq $0, %r10
	jnz .Lbb921
	.loc 1 295
	leaq -3952(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movq %r13, %rdi
	movq -304(%rbp), %r8
	movq -312(%rbp), %rsi
	movq -3088(%rbp), %r9
	jmp .Lbb923
.Lbb921:
	movq %rax, -24(%rcx)
.Lbb922:
	movq $0, -3952(%rbp)
.Lbb923:
	movq -4112(%rbp), %rax
	movq %rax, -3952(%rbp)
	movl $1, -4184(%rbp)
	movl $2, %r13d
.Lbb925:
	movl %r13d, -372(%rbp)
	cmpl $8, %r13d
	jz .Lbb931
	movq -3952(%rbp), %rax
	cmpq $0, %rax
	jz .Lbb930
	movq -16(%rax), %rcx
	movq $6917529027641081858, %r10
	andq %r10, %rcx
	cmpq $0, %rcx
	jnz .Lbb929
	movq -32(%rax), %rax
	cmpq $2, %rax
	jb .Lbb930
.Lbb929:
	movq %r12, %rdx
	.loc 1 295
	leaq -4184(%rbp), %rcx
	movq %rdx, %r12
	leaq -3952(%rbp), %rdx
	movq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527@gotpcrel(%rip), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %r13, %rdi
	movq -304(%rbp), %r8
	movq -312(%rbp), %rsi
	movq -3088(%rbp), %r9
	cmpl $0, %eax
	jz .Lbb2149
.Lbb930:
	movl $2, -3420(%rbp)
	jmp .Lbb936
.Lbb931:
	movq -3952(%rbp), %rax
	cmpq $0, %rax
	jz .Lbb935
	movq -16(%rax), %rcx
	movq $6917529027641081858, %r10
	andq %r10, %rcx
	cmpq $0, %rcx
	jnz .Lbb934
	movq -32(%rax), %rax
	cmpq $2, %rax
	jb .Lbb935
.Lbb934:
	movq %r12, %rdx
	.loc 1 295
	movl $0, %ecx
	movq %rdx, %r12
	leaq -3952(%rbp), %rdx
	movq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527@gotpcrel(%rip), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_held
	movq %r13, %rdi
	movl -372(%rbp), %r13d
	movq -304(%rbp), %r8
	movq -312(%rbp), %rsi
	movq -3088(%rbp), %r9
	cmpl $0, %eax
	jz .Lbb2149
.Lbb935:
	movl %r13d, -3420(%rbp)
.Lbb936:
	movq %r9, %rcx
	sarq $63, %rcx
	movq %r9, %rax
	xorq %rcx, %rax
	subq %rcx, %rax
	movq $-5030930201920786804, %r10
	mulq %r10
	movq %rdx, %rax
	movq %r12, %rdx
	shrq $3, %rax
	xorq %rcx, %rax
	subq %rcx, %rax
	imulq $11, %rax, %rax
	negq %rax
	addq %r9, %rax
	cmpq $0, %rax
	setnz %r10b
	movzbq %r10b, %r10
	andq %r10, %rcx
	negq %rcx
	andq $11, %rcx
	addq %rax, %rcx
	movq %rcx, -2896(%rbp)
	testq %rsi, %r8
	jnz .Lbb938
	movq %rdi, %r15
	movq %rcx, %rsi
	movq %rdx, %rax
	movl $0, %ecx
	movl $0, %ebx
	jmp .Lbb946
.Lbb938:
	movq $288230376151711744, %rax
	movq %rdx, %r13
	addq %rax, %rdx
	movq $576460752303423488, %rax
	cmpq %rax, %rdx
	jbe .Lbb940
	movq %rdi, %r15
	movq %rcx, %rsi
	movq %r13, %rax
	movl $0, %ecx
	movl $0, %ebx
	jmp .Lbb946
.Lbb940:
	movq -3952(%rbp), %rsi
	movq %rcx, %r15
	movq 8(%rsi), %rcx
	movq (%rsi), %rax
	movq %rax, -328(%rbp)
	negq %rax
	addq %rcx, %rax
	cmpq %r13, %rax
	jae .Lbb942
	movq %r15, %rsi
	movq %rdi, %r15
	movq %r13, %rax
	movl $0, %ecx
	movl $0, %ebx
	jmp .Lbb946
.Lbb942:
	movq 32(%rsi), %r10
	movq %r10, -336(%rbp)
	movq 16(%rsi), %rax
	movq %rax, -320(%rbp)
	.loc 1 295
	movq %rdi, %r12
	callq myl_rc_list_plain_ready
	movq %r15, %rcx
	movq %r13, %rdx
	movq %r12, %rdi
	movl %eax, %r8d
	movq -320(%rbp), %rsi
	movq -336(%rbp), %r10
	movl -3392(%rbp), %r12d
	movq -504(%rbp), %r13
	movq -328(%rbp), %rax
	movq -3088(%rbp), %r9
	cmpl $0, %r8d
	jnz .Lbb944
	movq %rdi, %r15
	movq %rcx, %rsi
	movq %rdx, %rax
	movl $0, %ecx
	movl $0, %ebx
	jmp .Lbb946
.Lbb944:
	movq $4611686018427387904, %r8
	cmpq %r8, %rsi
	jb .Lbb966
	movq %rdi, %r15
	movq %rcx, %rsi
	movq %rdx, %rax
	movl $0, %ecx
	movl $0, %ebx
.p2align 4
.Lbb946:
	movq %rax, -3712(%rbp)
	cmpq %rax, %rbx
	jge .Lbb965
	movq $3, -3712(%rbp)
	imulq $3, %rbx, %rdx
	movl $4294967295, %edi
	movq %rbx, %r11
	andq %rdi, %r11
	movq %rbx, %r10
	shrq $32, %r10
	imulq $3, %r11, %rdi
	shrq $32, %rdi
	imulq $3, %r10, %r8
	addq %rdi, %r8
	movl $4294967295, %edi
	andq %r8, %rdi
	shrq $32, %r8
	imulq $0, %r11, %r11
	addq %r11, %rdi
	shrq $32, %rdi
	imulq $0, %r10, %r10
	addq %r10, %r8
	addq %r8, %rdi
	cmpq $0, %rbx
	setl %r8b
	movzbq %r8b, %r8
	negq %r8
	movq %r9, %r14
	movq %r8, %r9
	andq $3, %r9
	movq %rbx, %r8
	andq $0, %r8
	subq %r9, %rdi
	subq %r8, %rdi
	movq %rdx, %r8
	sarq $63, %r8
	cmpq %rdi, %r8
	jnz .Lbb963
	movq %r14, -3712(%rbp)
	movq $11, -3704(%rbp)
	movq %rsi, -3712(%rbp)
	movq %rsi, %r10
	addq %rdx, %r10
	movq %r10, -360(%rbp)
	movq %rdx, %rdi
	xorq %r10, %rdi
	movq %rsi, %r8
	xorq %r10, %r8
	andq %r8, %rdi
	cmpq $0, %rdi
	jl .Lbb961
	movq -3952(%rbp), %rdi
	movq %rdi, -368(%rbp)
	movq (%rdi), %r8
	movq %r8, -352(%rbp)
	movq %rax, %r12
	movq 8(%rdi), %rax
	movq 16(%rdi), %rdx
	movq %rdx, -344(%rbp)
	cmpq %rax, %r8
	jae .Lbb952
	cmpl $0, %ecx
	jnz .Lbb956
	.loc 1 306
	movq %rsi, %r13
	movq %rdi, %rsi
	movq %r15, %rdi
	callq myl_rc_list_plain_ready
	movq %r13, %rsi
	movl %eax, %ecx
	movq -344(%rbp), %rdx
	movq -352(%rbp), %r8
	movq -368(%rbp), %rdi
	movq -360(%rbp), %r10
	cmpl $0, %ecx
	jnz .Lbb956
.Lbb952:
	movq %r10, -4080(%rbp)
	.loc 1 306
	leaq -4080(%rbp), %rdx
	movq %rsi, %r13
	movq %rdi, %rsi
	movq %r15, %rdi
	callq myl_rc_list_append
	movq %r14, %r9
	movq %r13, %rsi
	movl %eax, %ecx
	movq %r12, %rax
	cmpl $0, %ecx
	jz .Lbb954
	movl $0, %ecx
	jmp .Lbb957
.Lbb954:
	movq -2760(%rbp), %rdi
	.loc 1 306
	callq myl_qbe_fail_allocation
	ud2
.Lbb956:
	movq %r14, %r9
	movq %r12, %rax
	movq 32(%rdi), %r11
	movq %r10, (%r11, %r8, 8)
	addq $1, %r8
	movq %r8, (%rdi)
	addq $1, %rdx
	movq %rdx, 16(%rdi)
.Lbb957:
	movq $1, -3712(%rbp)
	movq $9223372036854775806, %rdx
	cmpq %rdx, %rbx
	jg .Lbb959
	addq $1, %rbx
	jmp .Lbb946
.Lbb959:
	movq %rbx, %rdx
	movq -2760(%rbp), %rdi
	.loc 1 310
	movl $64, %r8d
	movl $1, %ecx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb961:
	movq %rsi, %rcx
	movq -2760(%rbp), %rdi
	.loc 1 305
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb963:
	movq %rbx, %rdx
	movq -2760(%rbp), %rdi
	.loc 1 301
	movl $64, %r8d
	movl $3, %ecx
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb965:
	movl -3420(%rbp), %r13d
	movl -376(%rbp), %esi
	movq -2776(%rbp), %r14
	movq -504(%rbp), %rcx
	movq -472(%rbp), %r12
	movl -512(%rbp), %r11d
	movl -516(%rbp), %r10d
	movq -2760(%rbp), %rbx
	jmp .Lbb970
.Lbb966:
	movq %rdi, %r15
	movq %rbx, %rdi
	movq %r13, %rbx
	movl $0, %r8d
	xchgq %rcx, %rsi
	xchgq %rax, %rcx
	xchgq %rdx, %rax
.p2align 4
.Lbb967:
	movq %rax, -3712(%rbp)
	cmpq %rax, %r8
	jge .Lbb969
	movq $3, -3712(%rbp)
	imulq $3, %r8, %r11
	movq %r9, -3712(%rbp)
	movq $11, -3704(%rbp)
	movq %rsi, -3712(%rbp)
	movq %r11, %r13
	addq %rsi, %r13
	movq -3952(%rbp), %r11
	movq %r13, (%r10, %rcx, 8)
	addq $1, %rcx
	movq %rcx, (%r11)
	addq $1, %rdx
	movq %rdx, 16(%r11)
	movq $1, -3712(%rbp)
	addq $1, %r8
	jmp .Lbb967
.Lbb969:
	movl -3420(%rbp), %r13d
	movl -376(%rbp), %esi
	movq %rbx, %rcx
	movq -472(%rbp), %r12
	movl -512(%rbp), %r11d
	movl -516(%rbp), %r10d
	movq %rdi, %rbx
.Lbb970:
	movq %rax, %rdx
	movq %r15, %rdi
	movq -3952(%rbp), %rax
	cmpl $8, %r13d
	setz %r8b
	movzbl %r8b, %r8d
	movl -4184(%rbp), %r9d
	andl %r9d, %r8d
	cmpl $0, %r8d
	jnz .Lbb972
	movl %esi, %r8d
	movq %rax, %rsi
	movl $2, %eax
	jmp .Lbb982
.Lbb972:
	cmpq $0, %rax
	jnz .Lbb974
	movq %rax, %rsi
	jmp .Lbb980
.Lbb974:
	movq -16(%rax), %rsi
	movq $4611686018427387906, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb979
	movq %rax, %rsi
	movq -24(%rax), %rax
	addq $1, %rax
	jz .Lbb977
	movq %rax, -24(%rsi)
	jmp .Lbb980
.Lbb977:
	movq %rbx, %rdi
	.loc 1 313
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb979:
	movq %rax, %rsi
.Lbb980:
	movq %rsi, -4112(%rbp)
	movq %rsi, -4152(%rbp)
	movl $1, %r8d
	movl $8, %eax
.Lbb982:
	movl %r8d, -380(%rbp)
	movl %eax, -384(%rbp)
	movq %rsi, -4120(%rbp)
	movl %eax, %r9d
	andl $24, %r9d
	cmpl $0, %r9d
	setz %r9b
	movzbl %r9b, %r9d
	testl %r9d, %r8d
	jnz .Lbb1013
	cmpq $0, %rsi
	jz .Lbb991
	movq -16(%rsi), %r9
	movq $4611686018427387906, %r10
	andq %r9, %r10
	cmpq $0, %r10
	jnz .Lbb990
	movl %r8d, %ecx
	movl %ecx, %r8d
	movq -32(%rsi), %rcx
	addq $1, %rcx
	jz .Lbb988
	movq %rcx, -32(%rsi)
	jmp .Lbb991
.Lbb988:
	movq %rbx, %rdi
	.loc 1 315
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb990:
	movq $4611686018427387904, %r10
	andq %r10, %r9
	cmpq $0, %r9
	jnz .Lbb992
.Lbb991:
	movl %r8d, %ecx
	movq %rsi, -4112(%rbp)
	jmp .Lbb994
.Lbb992:
	.loc 1 315
	movq %rdx, %r15
	leaq -4120(%rbp), %rdx
	leaq -4112(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_retain
	movq %r15, %rdx
	movq %r12, %rdi
	movl %eax, %esi
	movl -380(%rbp), %ecx
	movl -384(%rbp), %eax
	movq -472(%rbp), %r12
	cmpl $0, %esi
	jnz .Lbb994
	.loc 1 315
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 315
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb994:
	cmpl $0, %ecx
	jz .Lbb1012
	testl $28, %eax
	jnz .Lbb1004
	movq -4152(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1012
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1003
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1002
	movq %rdx, %r15
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1001
	.loc 1 315
	leaq -4152(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %r15, %rdx
	movq %r12, %rdi
	movq -472(%rbp), %r12
	jmp .Lbb1012
.Lbb1001:
	movq %r15, %rdx
.Lbb1002:
	movq %rax, -32(%rcx)
.Lbb1003:
	movq $0, -4152(%rbp)
	jmp .Lbb1012
.Lbb1004:
	movq -4152(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1012
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1011
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1010
	movq %rdx, %r15
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1009
	.loc 1 315
	leaq -4152(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movq %r15, %rdx
	movq %r12, %rdi
	movq -472(%rbp), %r12
	jmp .Lbb1012
.Lbb1009:
	movq %r15, %rdx
.Lbb1010:
	movq %rax, -24(%rcx)
.Lbb1011:
	movq $0, -4152(%rbp)
.Lbb1012:
	xchgq %r13, %r12
	jmp .Lbb1021
.Lbb1013:
	movq %rsi, %rax
	movl %r10d, %esi
	orl %r11d, %esi
	jnz .Lbb1019
	cmpq $0, %rax
	jz .Lbb1017
	movq -16(%rax), %rax
	movq $5764607523034234881, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1019
.Lbb1017:
	movq -4120(%rbp), %rax
	movq %rax, -4112(%rbp)
	movq $0, -4120(%rbp)
	xchgq %r13, %r12
	jmp .Lbb1021
.Lbb1019:
	.loc 1 315
	movq %rdx, %r15
	leaq -4120(%rbp), %rdx
	leaq -4112(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_take
	movq %r15, %rdx
	movq %r12, %rdi
	movl %r13d, %r12d
	movq -472(%rbp), %r13
	cmpl $0, %eax
	jnz .Lbb1021
	.loc 1 315
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 315
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb1021:
	movq -4112(%rbp), %rax
	movq %rax, -3944(%rbp)
	movl -4184(%rbp), %eax
	cmpl $0, %eax
	jnz .Lbb1023
	movq %rdx, %r12
	jmp .Lbb1043
.Lbb1023:
	movl $0, -4184(%rbp)
	testl $28, %r12d
	jnz .Lbb1033
	movq -3952(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1032
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1031
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1030
	movq %rdx, %r15
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1029
	.loc 1 315
	leaq -3952(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %r15, %rdx
	movq %r12, %rdi
	jmp .Lbb1032
.Lbb1029:
	movq %r15, %rdx
.Lbb1030:
	movq %rax, -32(%rcx)
.Lbb1031:
	movq $0, -3952(%rbp)
.Lbb1032:
	movq %rdx, %r12
	jmp .Lbb1043
.Lbb1033:
	movq -3952(%rbp), %rcx
	cmpq $0, %rcx
	jnz .Lbb1035
	movq %rdx, %r12
	jmp .Lbb1043
.Lbb1035:
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1041
	movq -24(%rcx), %rax
	subq $1, %rax
	jz .Lbb1038
	movq %rdx, %r12
	jmp .Lbb1040
.Lbb1038:
	movq %rdx, %r12
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1040
	.loc 1 315
	leaq -3952(%rbp), %rsi
	movq %rdi, %r15
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movq %r15, %rdi
	jmp .Lbb1043
.Lbb1040:
	movq %rax, -24(%rcx)
	jmp .Lbb1042
.Lbb1041:
	movq %rdx, %r12
.Lbb1042:
	movq $0, -3952(%rbp)
.Lbb1043:
	movq %r12, -3712(%rbp)
	cmpq $0, %r12
	jg .Lbb1045
	movl $0, %edx
	jmp .Lbb1048
.Lbb1045:
	movq $0, -3712(%rbp)
	movq $0, -3712(%rbp)
	cmpq $0, %r13
	jl .Lbb2152
	cmpq $0, %r12
	jl .Lbb2150
	movq %r12, %rdx
.Lbb1048:
	.loc 1 358
	movq myl_t_b760f44fa5965c2474a3b471467a22c43185152129295af588b022ae50b50903@gotpcrel(%rip), %rsi
	movq %rdi, %r13
	callq myl_native_list_new
	movq %r13, %rdi
	movq %rax, %rsi
	movl -436(%rbp), %eax
	movq -504(%rbp), %rcx
	movq -3088(%rbp), %r9
	movl -512(%rbp), %r11d
	movl -516(%rbp), %r10d
	cmpl $0, %esi
	jnz .Lbb1051
	movq %rbx, %rdi
	.loc 1 358
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	ud2
.Lbb1051:
	movq %rsi, -4120(%rbp)
	movq -4120(%rbp), %r8
	movq %r8, -4112(%rbp)
	movq -4112(%rbp), %r8
	movq %r8, -4152(%rbp)
	movq %rsi, -4120(%rbp)
	movl %r10d, %r8d
	orl %r11d, %r8d
	jnz .Lbb1055
	cmpq $0, %rsi
	jz .Lbb1054
	movq -16(%rsi), %rsi
	movq $5764607523034234881, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb1055
.Lbb1054:
	movq -4120(%rbp), %rsi
	movq %rsi, -4112(%rbp)
	movq $0, -4120(%rbp)
	jmp .Lbb1057
.Lbb1055:
	movq %r12, %rdx
	.loc 1 359
	movq %rdx, %r12
	leaq -4120(%rbp), %rdx
	leaq -4112(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_take
	movq %r13, %rdi
	movl %eax, %esi
	movl -436(%rbp), %eax
	movq -504(%rbp), %rcx
	movq -3088(%rbp), %r9
	cmpl $0, %esi
	jnz .Lbb1057
	.loc 1 359
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 359
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb1057:
	movl -4176(%rbp), %esi
	cmpl $0, %esi
	jz .Lbb1065
	movl $0, -4176(%rbp)
	movq -3936(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb1065
	movq -16(%r8), %rsi
	movq $4611686018427387906, %r10
	andq %r10, %rsi
	cmpq $0, %rsi
	jnz .Lbb1064
	movq -32(%r8), %rsi
	subq $1, %rsi
	jnz .Lbb1063
	movq -24(%r8), %r10
	cmpq $0, %r10
	jnz .Lbb1063
	.loc 1 359
	leaq -3936(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_drop
	movq %r13, %rdi
	movl -436(%rbp), %eax
	movq -504(%rbp), %rcx
	movq -3088(%rbp), %r9
	jmp .Lbb1065
.Lbb1063:
	movq %rsi, -32(%r8)
.Lbb1064:
	movq $0, -3936(%rbp)
.Lbb1065:
	movq -4112(%rbp), %rsi
	movq %rsi, -3936(%rbp)
	movl $1, -4176(%rbp)
	cmpl $16, %eax
	jz .Lbb1067
	movq %r9, %r13
	xchgq %r12, %rbx
	xchgq %rdi, %r12
	jmp .Lbb1100
.Lbb1067:
	movq -3936(%rbp), %rsi
	cmpq $0, %rsi
	jnz .Lbb1069
	movq %r9, %r13
	jmp .Lbb1077
.Lbb1069:
	movq -16(%rsi), %r8
	movq $4611686018427387906, %r10
	andq %r8, %r10
	cmpq $0, %r10
	jnz .Lbb1076
	movq %rsi, %rcx
	movq %rcx, %rsi
	movq -32(%rcx), %rcx
	addq $1, %rcx
	jz .Lbb1074
	movq %rcx, -32(%rsi)
	movq %r9, %r13
	jmp .Lbb1077
.Lbb1074:
	movq %rbx, %rdi
	.loc 1 360
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb1076:
	movq %r9, %r13
	movq $4611686018427387904, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb1079
.Lbb1077:
	movq %rsi, %rcx
	movq %rcx, -4112(%rbp)
	xchgq %r12, %rbx
	xchgq %rdi, %r12
	jmp .Lbb1083
.Lbb1079:
	movq %r12, %rdx
	.loc 1 360
	movq %rdx, %r12
	leaq -3936(%rbp), %rdx
	leaq -4112(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_retain
	movq %r13, %rdi
	movl %eax, %ecx
	movl -436(%rbp), %eax
	movq -3088(%rbp), %r13
	cmpl $0, %ecx
	jnz .Lbb1082
	.loc 1 360
	movq %rdi, %r12
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 360
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb1082:
	xchgq %r12, %rbx
	xchgq %rdi, %r12
.Lbb1083:
	movl -4176(%rbp), %ecx
	cmpl $0, %ecx
	jz .Lbb1099
	movl $0, -4176(%rbp)
	testl $28, %eax
	jnz .Lbb1092
	movq -3936(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1099
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1091
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1090
	movq -24(%rcx), %rsi
	cmpq $0, %rsi
	jnz .Lbb1090
	.loc 1 360
	leaq -3936(%rbp), %rsi
	movq %rdi, %r13
	movq %r12, %rdi
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_drop
	movq %r13, %rdi
	movq -3088(%rbp), %r13
	jmp .Lbb1099
.Lbb1090:
	movq %rax, -32(%rcx)
.Lbb1091:
	movq $0, -3936(%rbp)
	jmp .Lbb1099
.Lbb1092:
	movq -3936(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1099
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1098
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1097
	movq -32(%rcx), %rsi
	cmpq $0, %rsi
	jnz .Lbb1097
	.loc 1 360
	leaq -3936(%rbp), %rsi
	movq %rdi, %r13
	movq %r12, %rdi
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_unloan
	movq %r13, %rdi
	movq -3088(%rbp), %r13
	jmp .Lbb1099
.Lbb1097:
	movq %rax, -24(%rcx)
.Lbb1098:
	movq $0, -3936(%rbp)
.Lbb1099:
	movq -4112(%rbp), %rax
	movq %rax, -3936(%rbp)
	movl $1, -4176(%rbp)
.Lbb1100:
	movq -3936(%rbp), %rax
	cmpq $0, %rax
	jnz .Lbb1102
	movq %r12, %rdi
	movq %r13, %r9
	jmp .Lbb1106
.Lbb1102:
	movq -16(%rax), %rcx
	movq $6917529027641081858, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb1105
	movq -32(%rax), %rax
	cmpq $2, %rax
	jae .Lbb1105
	movq %r12, %rdi
	movq %r13, %r9
	jmp .Lbb1106
.Lbb1105:
	movq %rbx, %rdx
	.loc 1 360
	leaq -4176(%rbp), %rcx
	movq %rdx, %rbx
	leaq -3936(%rbp), %rdx
	movq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9@gotpcrel(%rip), %rsi
	callq myl_qbe_rc_unique_local
	movq %r13, %r9
	movq %r12, %rdi
	cmpl $0, %eax
	jz .Lbb2149
.Lbb1106:
	movq %rdi, %r15
	movq %rbx, %rax
	movl $0, %esi
.p2align 4
.Lbb1107:
	movq %rsi, -432(%rbp)
	movq %rax, -3712(%rbp)
	cmpq %rax, %rsi
	jge .Lbb1150
	movq $2, -3712(%rbp)
	cmpq $2, %r14
	jz .Lbb1136
	movq -3960(%rbp), %rcx
	movq (%rcx), %rdi
	cmpq %rdi, %rsi
	setb %dil
	movzbq %dil, %rdi
	cmpq $0, %rsi
	setl %r8b
	movzbq %r8b, %r8
	cmpl $0, %edi
	jnz .Lbb1122
	movq $0, -3712(%rbp)
	cmpq $0, %rsi
	jl .Lbb1112
	movq %rsi, %rdi
	jmp .Lbb1114
.Lbb1112:
	movq (%rcx), %r10
	movq $9223372036854775807, %rdi
	cmpq %rdi, %r10
	ja .Lbb1120
	movq %rsi, -3712(%rbp)
	movq %r10, %rdi
	addq %rsi, %rdi
	movq %r10, %r11
	xorq %rdi, %r11
	movq %rsi, %rbx
	xorq %rdi, %rbx
	andq %rbx, %r11
	cmpq $0, %r11
	jl .Lbb1118
.Lbb1114:
	movq (%rcx), %r10
	cmpq %r10, %rdi
	jae .Lbb1116
	movq 32(%rcx), %rcx
	movq (%rcx, %rdi, 8), %r10
	jmp .Lbb1123
.Lbb1116:
	movq %r10, %rdx
	movq %rdi, %rax
	movq -2760(%rbp), %rdi
	.loc 1 389
	movq %rax, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1118:
	movq %rsi, %rdx
	movq %r10, %rsi
	movq -2760(%rbp), %rdi
	.loc 1 386
	movl $64, %r8d
	movq %rdx, %rcx
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1120:
	movq %r10, %rsi
	movq -2760(%rbp), %rdi
	.loc 1 384
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb1122:
	movq 32(%rcx), %rcx
	movq (%rcx, %rsi, 8), %r10
.Lbb1123:
	movq $73, -3712(%rbp)
	imulq $73, %r10, %rdi
	movl $4294967295, %ecx
	movq %r10, %r12
	andq %rcx, %r12
	movq %r10, %rbx
	shrq $32, %rbx
	imulq $73, %r12, %rcx
	shrq $32, %rcx
	imulq $73, %rbx, %r11
	addq %rcx, %r11
	movl $4294967295, %ecx
	andq %r11, %rcx
	shrq $32, %r11
	imulq $0, %r12, %r12
	addq %r12, %rcx
	shrq $32, %rcx
	imulq $0, %rbx, %rbx
	addq %rbx, %r11
	addq %r11, %rcx
	cmpq $0, %r10
	setl %r11b
	movzbq %r11b, %r11
	negq %r11
	movq %r11, %rbx
	andq $73, %rbx
	movq %r10, %r11
	andq $0, %r11
	subq %rbx, %rcx
	subq %r11, %rcx
	movq %rdi, %r11
	sarq $63, %r11
	cmpq %rcx, %r11
	jnz .Lbb1134
	movq %rsi, -3712(%rbp)
	movq $19, -3704(%rbp)
	imulq $19, %rsi, %rcx
	movl $4294967295, %r10d
	movq %rsi, %r12
	andq %r10, %r12
	movq %rsi, %rbx
	shrq $32, %rbx
	imulq $19, %r12, %r10
	shrq $32, %r10
	imulq $19, %rbx, %r11
	addq %r11, %r10
	movq %rsi, %r11
	movl $4294967295, %esi
	andq %r10, %rsi
	shrq $32, %r10
	imulq $0, %r12, %r12
	addq %r12, %rsi
	shrq $32, %rsi
	imulq $0, %rbx, %rbx
	addq %rbx, %r10
	addq %r10, %rsi
	negq %r8
	movq %r8, %r10
	andq $19, %r10
	movq %r11, %r8
	andq $0, %r8
	subq %r10, %rsi
	subq %r8, %rsi
	movq %rcx, %r8
	sarq $63, %r8
	cmpq %rsi, %r8
	jnz .Lbb1132
	movq %rcx, -3712(%rbp)
	movq %rdi, %rsi
	addq %rcx, %rsi
	movq %rdi, %r8
	xorq %rsi, %r8
	movq %rcx, %r10
	xorq %rsi, %r10
	andq %r10, %r8
	cmpq $0, %r8
	jl .Lbb1130
	movq %r9, -3712(%rbp)
	movq %r9, %rcx
	addq %rsi, %rcx
	movq %rsi, %rdi
	xorq %rcx, %rdi
	movq %r9, %r8
	xorq %rcx, %r8
	andq %r8, %rdi
	cmpq $0, %rdi
	jl .Lbb1128
	movq $101, -3712(%rbp)
	movq %rcx, %rsi
	sarq $63, %rsi
	movq %rsi, %rdi
	xorq %rcx, %rdi
	movq %rdi, %r8
	subq %rsi, %r8
	movq $4931307821684731621, %rdi
	movq %rax, %rbx
	movq %r8, %rax
	mulq %rdi
	movq %rbx, %rax
	movq %rdx, %rdi
	subq %rdi, %r8
	shrq $1, %r8
	addq %r8, %rdi
	shrq $6, %rdi
	xorq %rsi, %rdi
	subq %rsi, %rdi
	imulq $101, %rdi, %rdi
	subq %rdi, %rcx
	cmpq $0, %rcx
	setnz %dil
	movzbq %dil, %rdi
	andq %rdi, %rsi
	negq %rsi
	andq $101, %rsi
	addq %rsi, %rcx
	movq $50, -3712(%rbp)
	cmpq $50, %rcx
	setl %cl
	movzbq %cl, %rcx
	jmp .Lbb1137
.Lbb1128:
	movq %rsi, %rdx
	movq %r9, %r14
	movq -2760(%rbp), %rdi
	.loc 1 397
	movl $64, %r8d
	movq %r14, %rcx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1130:
	movq %rdi, %rdx
	movq -2760(%rbp), %rdi
	.loc 1 395
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1132:
	movq -432(%rbp), %rdx
	movq -2760(%rbp), %rdi
	.loc 1 394
	movl $64, %r8d
	movl $19, %ecx
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1134:
	movq %r10, %rdx
	movq -2760(%rbp), %rdi
	.loc 1 391
	movl $64, %r8d
	movl $73, %ecx
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1136:
	movq $16, -3712(%rbp)
	movq %rsi, %rcx
	andq $15, %rcx
	movq $0, -3712(%rbp)
	cmpq $0, %rcx
	setnz %cl
	movzbq %cl, %rcx
.Lbb1137:
	movq %rcx, -416(%rbp)
	movq -3936(%rbp), %rdi
	movq %rdi, -424(%rbp)
	movq %r9, %r12
	movzbq %cl, %r9
	movq %r9, -400(%rbp)
	movq (%rdi), %r8
	movq %r8, -408(%rbp)
	movq 8(%rdi), %r10
	movq 16(%rdi), %rsi
	movq %rsi, -392(%rbp)
	cmpq %r10, %r8
	movq %rax, %rbx
	setb %al
	movzbl %al, %eax
	cmpq $-1, %rsi
	setnz %sil
	movzbl %sil, %esi
	testl %eax, %esi
	jnz .Lbb1139
	movq %r12, %r13
	movq %rbx, %rax
	jmp .Lbb1140
.Lbb1139:
	.loc 1 404
	movq %rdi, %rsi
	movq %r15, %rdi
	callq myl_rc_list_plain_ready
	movq %r12, %r9
	movl %eax, %r11d
	movq %rbx, %rax
	movq -392(%rbp), %rcx
	movq -408(%rbp), %r8
	movq %r9, %r13
	movq -400(%rbp), %r9
	movq -424(%rbp), %rdi
	movq %rcx, %r10
	movq -416(%rbp), %rcx
	movq -432(%rbp), %rsi
	cmpl $0, %r11d
	jnz .Lbb1143
.Lbb1140:
	movq %rax, %rbx
	movq %r9, %rax
	andq $255, %rax
	andq $-256, %rcx
	orq %rcx, %rax
	movq %rax, -4080(%rbp)
	.loc 1 404
	leaq -4080(%rbp), %rdx
	movq %rdi, %rsi
	movq %r15, %rdi
	callq myl_rc_list_append
	movl %eax, %ecx
	movq %rbx, %rax
	movq -432(%rbp), %rsi
	cmpl $0, %ecx
	jnz .Lbb1145
	movq -2760(%rbp), %rdi
	.loc 1 404
	callq myl_qbe_fail_allocation
	ud2
.Lbb1143:
	movq %r10, %rcx
	movq 32(%rdi), %r10
	movb %r9b, (%r10, %r8, 1)
	addq $1, %r8
	movq %r8, (%rdi)
	addq $1, %rcx
	movq %rcx, 16(%rdi)
.Lbb1145:
	movq $1, -3712(%rbp)
	movq $9223372036854775806, %rcx
	cmpq %rcx, %rsi
	jg .Lbb1148
	addq $1, %rsi
	movq %r13, %r9
	jmp .Lbb1107
.Lbb1148:
	movq %rsi, %rdx
	movq -2760(%rbp), %rdi
	.loc 1 408
	movl $64, %r8d
	movl $1, %ecx
	movl $0, %esi
	movq %rdi, %rbx
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1150:
	movl -440(%rbp), %r13d
	movl -444(%rbp), %r12d
	movl -448(%rbp), %edx
	movq -504(%rbp), %rcx
	movq %r15, %rdi
	movl -512(%rbp), %r11d
	movl -516(%rbp), %r10d
	movq -2760(%rbp), %rbx
	movq -3936(%rbp), %rax
	movq %rax, -4120(%rbp)
	cmpl $0, %edx
	jnz .Lbb1162
	cmpq $0, %rax
	jz .Lbb1159
	movq -16(%rax), %rdx
	movq $4611686018427387906, %rsi
	andq %rdx, %rsi
	cmpq $0, %rsi
	jnz .Lbb1158
	movq -32(%rax), %rdx
	addq $1, %rdx
	jz .Lbb1156
	movq %rdx, -32(%rax)
	jmp .Lbb1159
.Lbb1156:
	movq %rbx, %rdi
	.loc 1 413
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb1158:
	movq $4611686018427387904, %rsi
	andq %rsi, %rdx
	cmpq $0, %rdx
	jnz .Lbb1160
.Lbb1159:
	movq %rax, -4112(%rbp)
	jmp .Lbb1168
.Lbb1160:
	.loc 1 413
	movq %rcx, %r15
	leaq -4120(%rbp), %rdx
	leaq -4112(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_retain
	movq %r15, %rcx
	movq %r14, %rdi
	cmpl $0, %eax
	jnz .Lbb1168
	.loc 1 413
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 413
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb1162:
	movl %r10d, %edx
	orl %r11d, %edx
	jnz .Lbb1166
	cmpq $0, %rax
	jz .Lbb1165
	movq -16(%rax), %rax
	movq $5764607523034234881, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb1166
.Lbb1165:
	movq -4120(%rbp), %rax
	movq %rax, -4112(%rbp)
	movq $0, -4120(%rbp)
	jmp .Lbb1168
.Lbb1166:
	.loc 1 413
	movq %rcx, %r15
	leaq -4120(%rbp), %rdx
	leaq -4112(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_take
	movq %r15, %rcx
	movq %r14, %rdi
	cmpl $0, %eax
	jnz .Lbb1168
	.loc 1 413
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 413
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb1168:
	movq -4112(%rbp), %rax
	movq %rax, -3928(%rbp)
	movl -4176(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb1177
	movl $0, -4176(%rbp)
	movq -3936(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb1177
	movq -16(%rdx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1176
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb1175
	movq %rcx, %r15
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb1174
	.loc 1 413
	leaq -3936(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_drop
	movq %r15, %rcx
	movq %r14, %rdi
	jmp .Lbb1177
.Lbb1174:
	movq %r15, %rcx
.Lbb1175:
	movq %rax, -32(%rdx)
.Lbb1176:
	movq $0, -3936(%rbp)
.Lbb1177:
	movq -3960(%rbp), %rax
	cmpq $0, %rax
	jz .Lbb1183
	movq -16(%rax), %rdx
	movq $4611686018427387906, %rsi
	andq %rsi, %rdx
	cmpq $0, %rdx
	jnz .Lbb1183
	movq -24(%rax), %rdx
	addq $1, %rdx
	jz .Lbb1181
	movq %rdx, -24(%rax)
	jmp .Lbb1183
.Lbb1181:
	movq %rbx, %rdi
	.loc 1 415
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb1183:
	movq %rax, -4112(%rbp)
	cmpl $0, %r13d
	jnz .Lbb1185
	movq %rcx, %r14
	jmp .Lbb1202
.Lbb1185:
	testl $28, %r12d
	jnz .Lbb1195
	movq -4152(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb1194
	movq -16(%rdx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1193
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb1192
	movq %rcx, %r13
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb1191
	.loc 1 415
	leaq -4152(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %r13, %rcx
	movq %r12, %rdi
	jmp .Lbb1194
.Lbb1191:
	movq %r13, %rcx
.Lbb1192:
	movq %rax, -32(%rdx)
.Lbb1193:
	movq $0, -4152(%rbp)
.Lbb1194:
	movq %rcx, %r14
	jmp .Lbb1202
.Lbb1195:
	movq %rcx, %r14
	movq -4152(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1202
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb1201
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1200
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1200
	.loc 1 415
	leaq -4152(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movq %r12, %rdi
	jmp .Lbb1202
.Lbb1200:
	movq %rax, -24(%rcx)
.Lbb1201:
	movq $0, -4152(%rbp)
.Lbb1202:
	movq -4112(%rbp), %rax
	movq %rax, -4152(%rbp)
	movq %rax, -4112(%rbp)
	movq -4112(%rbp), %rax
	movq %rax, -3920(%rbp)
	movq (%rax), %rsi
	movq %rsi, -456(%rbp)
	movq $9223372036854775807, %rax
	cmpq %rax, %rsi
	ja .Lbb2147
	cmpq $0, %rsi
	jge .Lbb1206
	movq %rbx, %rdi
	.loc 1 422
	movq %rdi, %rbx
	callq myl_qbe_fail_list_capacity
	ud2
.Lbb1206:
	.loc 1 422
	movq %rsi, %rdx
	movq %rsi, %r13
	movq myl_t_a29cdb61df1464ef45ddedc7a042fd8f4fab0fd1c7c0c694df708d0b61e21222@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	callq myl_native_list_new
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movl -460(%rbp), %r12d
	movl -512(%rbp), %r11d
	movl -516(%rbp), %r10d
	cmpl $0, %eax
	jnz .Lbb1209
	movq %rbx, %rdi
	.loc 1 422
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	ud2
.Lbb1209:
	movq %rax, -4120(%rbp)
	movq -4120(%rbp), %r8
	movq %r8, -4112(%rbp)
	movq -4112(%rbp), %r8
	movq %r8, -4152(%rbp)
	movq %rax, -4120(%rbp)
	movl %r10d, %r8d
	orl %r11d, %r8d
	jnz .Lbb1213
	cmpq $0, %rax
	jz .Lbb1212
	movq -16(%rax), %rax
	movq $5764607523034234881, %r8
	andq %r8, %rax
	cmpq $0, %rax
	jnz .Lbb1213
.Lbb1212:
	movq -4120(%rbp), %rax
	movq %rax, -4112(%rbp)
	movq $0, -4120(%rbp)
	jmp .Lbb1215
.Lbb1213:
	.loc 1 423
	movq %rcx, %r14
	leaq -4120(%rbp), %rdx
	movq %rsi, %r13
	leaq -4112(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_take
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movl -460(%rbp), %r12d
	cmpl $0, %eax
	jnz .Lbb1215
	.loc 1 423
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 423
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb1215:
	movl -4168(%rbp), %eax
	cmpl $0, %eax
	jnz .Lbb1217
	movl %r12d, %r14d
	jmp .Lbb1227
.Lbb1217:
	movl $0, -4168(%rbp)
	movq -3912(%rbp), %r8
	cmpq $0, %r8
	jnz .Lbb1219
	movl %r12d, %r14d
	jmp .Lbb1227
.Lbb1219:
	movq -16(%r8), %rax
	movq $4611686018427387906, %r9
	andq %r9, %rax
	cmpq $0, %rax
	jnz .Lbb1225
	movq -32(%r8), %rax
	subq $1, %rax
	jnz .Lbb1224
	movq %rcx, %r14
	movq -24(%r8), %rcx
	cmpq $0, %rcx
	jnz .Lbb1223
	.loc 1 423
	movq %rsi, %r13
	leaq -3912(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_drop
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movl -460(%rbp), %r14d
	jmp .Lbb1227
.Lbb1223:
	movq %r14, %rcx
.Lbb1224:
	movl %r12d, %r14d
	movq %rax, -32(%r8)
	jmp .Lbb1226
.Lbb1225:
	movl %r12d, %r14d
.Lbb1226:
	movq $0, -3912(%rbp)
.Lbb1227:
	movq -4112(%rbp), %rax
	movq %rax, -3912(%rbp)
	movl $1, -4168(%rbp)
	movq %rdi, %r15
	movq %rsi, %r12
	movq %rbx, %rdi
	movq %rcx, %rbx
	movl $0, %r13d
.p2align 4
.Lbb1229:
	movl %r14d, -3388(%rbp)
	movq %r12, -3712(%rbp)
	cmpq %r12, %r13
	setl %al
	movzbq %al, %rax
	cmpl $0, %eax
	jz .Lbb1281
	movq -3920(%rbp), %rax
	movq (%rax), %rcx
	cmpq %rcx, %r12
	jnz .Lbb1280
	cmpq %rcx, %r13
	jae .Lbb1278
	movq 32(%rax), %rax
	movq (%rax, %r13, 8), %rsi
	movq %rsi, -3712(%rbp)
	movq $17, -3704(%rbp)
	movq %rsi, %rcx
	sarq $63, %rcx
	movq %rsi, %rax
	xorq %rcx, %rax
	subq %rcx, %rax
	movq $-1085102592571150095, %r8
	mulq %r8
	movq %rdx, %rax
	shrq $4, %rax
	xorq %rcx, %rax
	subq %rcx, %rax
	imulq $17, %rax, %rax
	negq %rax
	addq %rsi, %rax
	cmpq $0, %rax
	setnz %r8b
	movzbq %r8b, %r8
	andq %r8, %rcx
	negq %rcx
	andq $17, %rcx
	addq %rax, %rcx
	movq %rcx, -3712(%rbp)
	movq %rsi, -3704(%rbp)
	imulq $3, %rsi, %r9
	movl $4294967295, %eax
	movq %rsi, %r11
	andq %rax, %r11
	movq %rsi, %r10
	shrq $32, %r10
	imulq $3, %r11, %rax
	shrq $32, %rax
	imulq $3, %r10, %r8
	addq %rax, %r8
	movl $4294967295, %eax
	andq %r8, %rax
	shrq $32, %r8
	imulq $0, %r11, %r11
	addq %r11, %rax
	shrq $32, %rax
	imulq $0, %r10, %r10
	addq %r10, %r8
	addq %r8, %rax
	cmpq $0, %rsi
	setl %r8b
	movzbq %r8b, %r8
	negq %r8
	movq %r8, %r10
	andq $3, %r10
	movq %rsi, %r8
	andq $0, %r8
	subq %r10, %rax
	subq %r8, %rax
	movq %r9, %r8
	sarq $63, %r8
	cmpq %rax, %r8
	jnz .Lbb1276
	movq %r9, -3704(%rbp)
	movq %r8, %rax
	xorq %r9, %rax
	movq %rax, %r10
	subq %r8, %r10
	movq $4931307821684731621, %r11
	movq %r10, %rax
	mulq %r11
	movq %rdx, %rax
	subq %rax, %r10
	shrq $1, %r10
	addq %r10, %rax
	shrq $6, %rax
	xorq %r8, %rax
	subq %r8, %rax
	imulq $101, %rax, %rax
	negq %rax
	addq %r9, %rax
	cmpq $0, %rax
	setnz %r9b
	movzbq %r9b, %r9
	andq %r9, %r8
	negq %r8
	andq $101, %r8
	addq %r8, %rax
	movq %rax, -3704(%rbp)
	movq %rsi, -3696(%rbp)
	movq %rcx, -3688(%rbp)
	movq %rax, -3680(%rbp)
	cmpl $16, %r14d
	setz %al
	movzbl %al, %eax
	movl -4168(%rbp), %ecx
	testl %eax, %ecx
	jz .Lbb1259
	movq -3912(%rbp), %rax
	cmpq $0, %rax
	jz .Lbb1240
	movq -16(%rax), %rcx
	movq $4611686018427387906, %rsi
	andq %rcx, %rsi
	cmpq $0, %rsi
	jnz .Lbb1239
	movq -32(%rax), %rcx
	addq $1, %rcx
	jz .Lbb1238
	movq %rcx, -32(%rax)
	jmp .Lbb1240
.Lbb1238:
	.loc 1 444
	movl $2, %esi
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb1239:
	movq $4611686018427387904, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb1241
.Lbb1240:
	movq %rax, -4112(%rbp)
	jmp .Lbb1242
.Lbb1241:
	.loc 1 444
	movl %ebx, %ecx
	leaq -3912(%rbp), %rdx
	leaq -4112(%rbp), %rsi
	movq %rdi, %r12
	movq %r15, %rdi
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_retain
	movq %r12, %rdi
	movl -3388(%rbp), %r14d
	movq -456(%rbp), %r12
	cmpl $0, %eax
	jz .Lbb1274
.Lbb1242:
	movl -4168(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb1258
	movl $0, -4168(%rbp)
	testl $28, %r14d
	jnz .Lbb1251
	movq -3912(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1258
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1250
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1249
	movq -24(%rcx), %rsi
	cmpq $0, %rsi
	jnz .Lbb1249
	.loc 1 444
	leaq -3912(%rbp), %rsi
	movq %rdi, %r12
	movq %r15, %rdi
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_drop
	movq %r12, %rdi
	movq -456(%rbp), %r12
	jmp .Lbb1258
.Lbb1249:
	movq %rax, -32(%rcx)
.Lbb1250:
	movq $0, -3912(%rbp)
	jmp .Lbb1258
.Lbb1251:
	movq -3912(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1258
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1257
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1256
	movq -32(%rcx), %rsi
	cmpq $0, %rsi
	jnz .Lbb1256
	.loc 1 444
	leaq -3912(%rbp), %rsi
	movq %rdi, %r12
	movq %r15, %rdi
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_unloan
	movq %r12, %rdi
	movq -456(%rbp), %r12
	jmp .Lbb1258
.Lbb1256:
	movq %rax, -24(%rcx)
.Lbb1257:
	movq $0, -3912(%rbp)
.Lbb1258:
	movq -4112(%rbp), %rax
	movq %rax, -3912(%rbp)
	movl $1, -4168(%rbp)
.Lbb1259:
	movq -3912(%rbp), %rax
	cmpq $0, %rax
	jz .Lbb1263
	movq -16(%rax), %rcx
	movq $6917529027641081858, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb1262
	movq -32(%rax), %rax
	cmpq $2, %rax
	jb .Lbb1263
.Lbb1262:
	.loc 1 444
	leaq -4168(%rbp), %rcx
	leaq -3912(%rbp), %rdx
	movq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	callq myl_qbe_rc_unique_local
	movq %r12, %rdi
	movq -456(%rbp), %r12
	cmpl $0, %eax
	jz .Lbb2149
.Lbb1263:
	movq -3912(%rbp), %rcx
	movq (%rcx), %rsi
	movq 8(%rcx), %r11
	movq 16(%rcx), %rax
	movq 32(%rcx), %r9
	imulq $24, %rsi, %r10
	leaq -3696(%rbp), %r8
	subq %r9, %r8
	cmpq %r10, %r8
	setae %r8b
	movzbl %r8b, %r8d
	cmpq %r11, %rsi
	setb %r11b
	movzbl %r11b, %r11d
	cmpq $-1, %rax
	setnz %r14b
	movzbl %r14b, %r14d
	andl %r14d, %r11d
	testl %r8d, %r11d
	jnz .Lbb1266
	.loc 1 444
	leaq -3696(%rbp), %rdx
	movq %rcx, %rsi
	movq %rdi, %r12
	movq %r15, %rdi
	callq myl_t_a29cdb61df1464ef45ddedc7a042fd8f4fab0fd1c7c0c694df708d0b61e21222_rcg_list_append
	movq %r12, %rdi
	movq -456(%rbp), %r12
	cmpl $0, %eax
	jnz .Lbb1267
	.loc 1 444
	callq myl_qbe_fail_allocation
	ud2
.Lbb1266:
	movq -3696(%rbp), %r8
	movq %r8, 0(%r9, %r10, 1)
	movq -3688(%rbp), %r8
	movq %r8, 8(%r9, %r10, 1)
	movq -3680(%rbp), %r8
	movq %r8, 16(%r9, %r10, 1)
	addq $1, %rsi
	movq %rsi, (%rcx)
	addq $1, %rax
	movq %rax, 16(%rcx)
.Lbb1267:
	movq -3920(%rbp), %rax
	movq (%rax), %rax
	cmpq %rax, %r12
	jnz .Lbb1273
	movq $1, -3712(%rbp)
	movq $9223372036854775806, %rax
	cmpq %rax, %r13
	jg .Lbb1271
	addq $1, %r13
	movl $2, %r14d
	jmp .Lbb1229
.Lbb1271:
	movq %r13, %rsi
	.loc 1 451
	movl $64, %r8d
	movl $1, %ecx
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1273:
	.loc 1 447
	movq %rdi, %rbx
	callq myl_qbe_fail_iteration
	ud2
.Lbb1274:
	movq %rdi, %rbx
	movq %r15, %rdi
	.loc 1 444
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 444
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb1276:
	movq %rsi, %rdx
	.loc 1 440
	movl $64, %r8d
	movl $3, %ecx
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1278:
	movq %r13, %rsi
	movq %rcx, %rdx
	.loc 1 432
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1280:
	.loc 1 429
	movq %rdi, %rbx
	callq myl_qbe_fail_iteration
	ud2
.Lbb1281:
	movl %r14d, %r13d
	movl -464(%rbp), %esi
	movq %rbx, %rcx
	movq -472(%rbp), %r12
	movq -3088(%rbp), %r14
	movq -2752(%rbp), %rdx
	movl -512(%rbp), %r11d
	movl -516(%rbp), %r10d
	movq %rdi, %rbx
	movq %r15, %rdi
	movq -3912(%rbp), %rax
	movq %rax, -4120(%rbp)
	cmpl $0, %esi
	jnz .Lbb1293
	cmpq $0, %rax
	jz .Lbb1290
	movq -16(%rax), %rsi
	movq $4611686018427387906, %r8
	andq %rsi, %r8
	cmpq $0, %r8
	jnz .Lbb1289
	movq -32(%rax), %rcx
	addq $1, %rcx
	jz .Lbb1287
	movq %rcx, -32(%rax)
	jmp .Lbb1290
.Lbb1287:
	movq %rbx, %rdi
	.loc 1 456
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb1289:
	movq $4611686018427387904, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb1291
.Lbb1290:
	movq %rax, -4112(%rbp)
	jmp .Lbb1299
.Lbb1291:
	.loc 1 456
	movq %rdx, %r15
	leaq -4120(%rbp), %rdx
	leaq -4112(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_retain
	movq %r15, %rdx
	movq %r12, %rdi
	movq -472(%rbp), %r12
	cmpl $0, %eax
	jnz .Lbb1299
	.loc 1 456
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 456
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb1293:
	movl %r10d, %esi
	orl %r11d, %esi
	jnz .Lbb1297
	cmpq $0, %rax
	jz .Lbb1296
	movq -16(%rax), %rax
	movq $5764607523034234881, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1297
.Lbb1296:
	movq -4120(%rbp), %rax
	movq %rax, -4112(%rbp)
	movq $0, -4120(%rbp)
	jmp .Lbb1299
.Lbb1297:
	.loc 1 456
	movq %rdx, %r15
	leaq -4120(%rbp), %rdx
	leaq -4112(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_take
	movq %r15, %rdx
	movq %r12, %rdi
	movq -472(%rbp), %r12
	cmpl $0, %eax
	jnz .Lbb1299
	.loc 1 456
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 456
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb1299:
	movq -4112(%rbp), %rax
	movq %rax, -3904(%rbp)
	movl -4168(%rbp), %eax
	cmpl $0, %eax
	jnz .Lbb1301
	movq %rdx, %r13
	jmp .Lbb1321
.Lbb1301:
	movl $0, -4168(%rbp)
	testl $28, %r13d
	jnz .Lbb1311
	movq -3912(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1310
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1309
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1308
	movq %rdx, %r15
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1307
	.loc 1 456
	leaq -3912(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_drop
	movq %r15, %rdx
	movq %r13, %rdi
	jmp .Lbb1310
.Lbb1307:
	movq %r15, %rdx
.Lbb1308:
	movq %rax, -32(%rcx)
.Lbb1309:
	movq $0, -3912(%rbp)
.Lbb1310:
	movq %rdx, %r13
	jmp .Lbb1321
.Lbb1311:
	movq -3912(%rbp), %rcx
	cmpq $0, %rcx
	jnz .Lbb1313
	movq %rdx, %r13
	jmp .Lbb1321
.Lbb1313:
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1319
	movq -24(%rcx), %rax
	subq $1, %rax
	jz .Lbb1316
	movq %rdx, %r13
	jmp .Lbb1318
.Lbb1316:
	movq %rdx, %r13
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1318
	.loc 1 456
	leaq -3912(%rbp), %rsi
	movq %rdi, %r15
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_unloan
	movq %r15, %rdi
	jmp .Lbb1321
.Lbb1318:
	movq %rax, -24(%rcx)
	jmp .Lbb1320
.Lbb1319:
	movq %rdx, %r13
.Lbb1320:
	movq $0, -3912(%rbp)
.Lbb1321:
	movq %r13, -3712(%rbp)
	cmpq $0, %r13
	jg .Lbb1323
	movl $0, %edx
	jmp .Lbb1326
.Lbb1323:
	movq $0, -3712(%rbp)
	movq $0, -3712(%rbp)
	cmpq $0, %r12
	jl .Lbb2145
	cmpq $0, %r13
	jl .Lbb2143
	movq %r13, %rdx
.Lbb1326:
	.loc 1 499
	movq myl_t_277089d91c0bdf4f2e6862ba7e4a07605119431f5d13f726dd352b06f1b206a9@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	callq myl_native_list_new
	movq %r12, %rdi
	movl -476(%rbp), %r12d
	movl -480(%rbp), %r15d
	movq -504(%rbp), %rcx
	movl -512(%rbp), %r11d
	movl -516(%rbp), %r10d
	cmpl $0, %eax
	jnz .Lbb1329
	movq %rbx, %rdi
	.loc 1 499
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	ud2
.Lbb1329:
	movq %rax, -4120(%rbp)
	movq -4120(%rbp), %rsi
	movq %rsi, -4112(%rbp)
	movq -4112(%rbp), %rsi
	movq %rsi, -4152(%rbp)
	movq %rax, -4120(%rbp)
	movl %r10d, %esi
	orl %r11d, %esi
	jnz .Lbb1333
	cmpq $0, %rax
	jz .Lbb1332
	movq -16(%rax), %rax
	movq $5764607523034234881, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1333
.Lbb1332:
	movq -4120(%rbp), %rax
	movq %rax, -4112(%rbp)
	movq $0, -4120(%rbp)
	jmp .Lbb1335
.Lbb1333:
	movq %r13, %rdx
	.loc 1 500
	movq %rdx, %r13
	leaq -4120(%rbp), %rdx
	leaq -4112(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_take
	movq %r12, %rdi
	movl -476(%rbp), %r12d
	movl -480(%rbp), %r15d
	movq -504(%rbp), %rcx
	cmpl $0, %eax
	jnz .Lbb1335
	.loc 1 500
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 500
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb1335:
	movl -4160(%rbp), %eax
	cmpl $0, %eax
	jnz .Lbb1337
	movq %r14, %r9
	jmp .Lbb1346
.Lbb1337:
	movl $0, -4160(%rbp)
	movq -3896(%rbp), %rsi
	cmpq $0, %rsi
	jnz .Lbb1339
	movq %r14, %r9
	jmp .Lbb1346
.Lbb1339:
	movq -16(%rsi), %rax
	movq $4611686018427387906, %r8
	andq %r8, %rax
	cmpq $0, %rax
	jnz .Lbb1344
	movq -32(%rsi), %rax
	subq $1, %rax
	jnz .Lbb1343
	movq -24(%rsi), %r8
	cmpq $0, %r8
	jnz .Lbb1343
	.loc 1 500
	leaq -3896(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_drop
	movq %r14, %r9
	movq %r12, %rdi
	movl -476(%rbp), %r12d
	movl -480(%rbp), %r15d
	movq -504(%rbp), %rcx
	jmp .Lbb1346
.Lbb1343:
	movq %r14, %r9
	movq %rax, -32(%rsi)
	jmp .Lbb1345
.Lbb1344:
	movq %r14, %r9
.Lbb1345:
	movq $0, -3896(%rbp)
.Lbb1346:
	movq -4112(%rbp), %rax
	movq %rax, -3896(%rbp)
	movl $1, -4160(%rbp)
	movq %r13, %rax
	movl %r15d, -3312(%rbp)
	movq %rdi, %r15
	movq %rbx, %rdi
	movq %rcx, %rbx
	movl %r12d, -528(%rbp)
	movl $2, -544(%rbp)
	movl $0, %esi
.p2align 4
.Lbb1348:
	movq %r9, %r13
	movq %rsi, -496(%rbp)
	movq %rax, -3712(%rbp)
	cmpq %rax, %rsi
	movq %rax, %r12
	setl %al
	movzbq %al, %rax
	cmpl $0, %eax
	jz .Lbb1403
	movq %r13, -3712(%rbp)
	.loc 1 507
	movq %r13, %rdx
	movq %rdi, %r14
	callq myl_f_9b49081a6b2287f0b352a5145304597c577561f78778b00b14cf8abdb61281d6
	movq %r14, %rdi
	movq %rax, %rcx
	movq %r12, %rax
	movq %rbx, %r14
	movl -3312(%rbp), %ebx
	movq %rcx, -488(%rbp)
	movq %rcx, -4120(%rbp)
	movq -4120(%rbp), %rdx
	movq %rdx, -4112(%rbp)
	movq -4112(%rbp), %rdx
	movq %rdx, -4152(%rbp)
	cmpl $16, %ebx
	setz %dl
	movzbl %dl, %edx
	movl -4160(%rbp), %esi
	testl %edx, %esi
	jnz .Lbb1351
	movq %rcx, %r12
	jmp .Lbb1379
.Lbb1351:
	movq %rax, %r12
	movq -3896(%rbp), %rax
	cmpq $0, %rax
	jz .Lbb1357
	movq -16(%rax), %rdx
	movq $4611686018427387906, %rsi
	andq %rdx, %rsi
	cmpq $0, %rsi
	jnz .Lbb1356
	movq -32(%rax), %rdx
	addq $1, %rdx
	jz .Lbb1355
	movq %rdx, -32(%rax)
	jmp .Lbb1357
.Lbb1355:
	.loc 1 508
	movl $2, %esi
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb1356:
	movq $4611686018427387904, %rsi
	andq %rsi, %rdx
	cmpq $0, %rdx
	jnz .Lbb1359
.Lbb1357:
	movq %rcx, %r14
	movq %rax, -4112(%rbp)
	movq %r12, %rax
	movq %r14, %r12
	jmp .Lbb1360
.Lbb1359:
	.loc 1 508
	movl %r14d, %ecx
	leaq -3896(%rbp), %rdx
	leaq -4112(%rbp), %rsi
	movq %rdi, %r14
	movq %r15, %rdi
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_retain
	movq %r14, %rdi
	movl %eax, %ecx
	movq %r12, %rax
	movq -488(%rbp), %r12
	cmpl $0, %ecx
	jz .Lbb1401
.Lbb1360:
	movl -4160(%rbp), %ecx
	cmpl $0, %ecx
	jz .Lbb1378
	movl $0, -4160(%rbp)
	testl $28, %ebx
	jnz .Lbb1370
	movq -3896(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb1378
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb1369
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb1368
	movq %rax, %rbx
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb1367
	.loc 1 508
	leaq -3896(%rbp), %rsi
	movq %rdi, %r14
	movq %r15, %rdi
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_drop
	movq %r14, %rdi
	movq %rbx, %rax
	jmp .Lbb1378
.Lbb1367:
	movq %rbx, %rax
.Lbb1368:
	movq %rcx, -32(%rdx)
.Lbb1369:
	movq $0, -3896(%rbp)
	jmp .Lbb1378
.Lbb1370:
	movq -3896(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb1378
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb1377
	movq -24(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb1376
	movq %rax, %rbx
	movq -32(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb1375
	.loc 1 508
	leaq -3896(%rbp), %rsi
	movq %rdi, %r14
	movq %r15, %rdi
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_unloan
	movq %r14, %rdi
	movq %rbx, %rax
	jmp .Lbb1378
.Lbb1375:
	movq %rbx, %rax
.Lbb1376:
	movq %rcx, -24(%rdx)
.Lbb1377:
	movq $0, -3896(%rbp)
.Lbb1378:
	movq -4112(%rbp), %rcx
	movq %rcx, -3896(%rbp)
	movl $1, -4160(%rbp)
.Lbb1379:
	movq %rax, %rbx
	movq -3896(%rbp), %rax
	cmpq $0, %rax
	jz .Lbb1383
	movq -16(%rax), %rcx
	movq $6917529027641081858, %rdx
	andq %rdx, %rcx
	cmpq $0, %rcx
	jnz .Lbb1382
	movq -32(%rax), %rax
	cmpq $2, %rax
	jb .Lbb1383
.Lbb1382:
	.loc 1 508
	leaq -4160(%rbp), %rcx
	leaq -3896(%rbp), %rdx
	movq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a@gotpcrel(%rip), %rsi
	movq %rdi, %r14
	callq myl_qbe_rc_unique_local
	movq %r14, %rdi
	cmpl $0, %eax
	jz .Lbb2149
.Lbb1383:
	movq -3896(%rbp), %rsi
	movq %r12, -4080(%rbp)
	.loc 1 508
	leaq -4080(%rbp), %rdx
	movq %rdi, %r12
	movq %r15, %rdi
	callq myl_t_277089d91c0bdf4f2e6862ba7e4a07605119431f5d13f726dd352b06f1b206a9_rcg_list_append
	movq %r13, %r9
	movq %r12, %rdi
	movl %eax, %ecx
	movq %rbx, %rax
	movl -508(%rbp), %r14d
	movq -496(%rbp), %rsi
	movq -504(%rbp), %r12
	cmpl $0, %ecx
	jz .Lbb1400
	movq -4152(%rbp), %r8
	cmpq $0, %r8
	jnz .Lbb1386
	movl %r14d, %r13d
	movq %r12, %rbx
	jmp .Lbb1395
.Lbb1386:
	movq -16(%r8), %rcx
	movq %r9, %r13
	movq $4611686018427387906, %r9
	andq %r9, %rcx
	cmpq $0, %rcx
	jnz .Lbb1393
	movq -32(%r8), %rcx
	subq $1, %rcx
	jz .Lbb1389
	movq %r13, %r9
	jmp .Lbb1392
.Lbb1389:
	movq %rax, %rbx
	movq -24(%r8), %rax
	cmpq $0, %rax
	jnz .Lbb1391
	.loc 1 508
	leaq -4152(%rbp), %rsi
	movq %rdi, %r12
	movq %r15, %rdi
	callq myl_t_277089d91c0bdf4f2e6862ba7e4a07605119431f5d13f726dd352b06f1b206a9_rcg_drop
	movq %r13, %r9
	movq %r12, %rdi
	movq %rbx, %rax
	movl -508(%rbp), %r13d
	movq -496(%rbp), %rsi
	movq -504(%rbp), %rbx
	jmp .Lbb1395
.Lbb1391:
	movq %r13, %r9
	movq %rbx, %rax
.Lbb1392:
	movl %r14d, %r13d
	movq %r12, %rbx
	movq %rcx, -32(%r8)
	jmp .Lbb1394
.Lbb1393:
	movq %r12, %rbx
	movq %r13, %r9
	movl %r14d, %r13d
.Lbb1394:
	movq $0, -4152(%rbp)
.Lbb1395:
	movq $1, -3712(%rbp)
	movq $9223372036854775806, %rcx
	cmpq %rcx, %rsi
	jg .Lbb1398
	addq $1, %rsi
	movl $2, -3312(%rbp)
	movl %r13d, -528(%rbp)
	movl $2, -544(%rbp)
	jmp .Lbb1348
.Lbb1398:
	movq %rsi, %rdx
	.loc 1 512
	movl $64, %r8d
	movl $1, %ecx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1400:
	.loc 1 508
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	ud2
.Lbb1401:
	movq %rdi, %rbx
	movq %r15, %rdi
	.loc 1 508
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 508
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb1403:
	movl -528(%rbp), %eax
	movq -2776(%rbp), %r14
	movq %rbx, %rcx
	movq %r13, %r9
	movq %r12, %r13
	movl -544(%rbp), %r12d
	movl -512(%rbp), %r11d
	movl -516(%rbp), %r10d
	movq %rdi, %rbx
	movq %r15, %rdi
	movl -3312(%rbp), %r15d
	movq -3896(%rbp), %r8
	movq %r8, -4120(%rbp)
	movl %r12d, %esi
	andl $24, %esi
	cmpl $0, %esi
	setz %sil
	movzbl %sil, %esi
	movl %esi, -520(%rbp)
	movl -520(%rbp), %esi
	andl %eax, %esi
	movl %esi, -524(%rbp)
	movq -3320(%rbp), %rsi
	cmpl $0, -524(%rbp)
	jnz .Lbb1437
	cmpq $0, %r8
	jz .Lbb1412
	movq -16(%r8), %r10
	movq $4611686018427387906, %r11
	andq %r10, %r11
	cmpq $0, %r11
	jnz .Lbb1411
	movq -32(%r8), %rcx
	addq $1, %rcx
	jz .Lbb1409
	movq %rcx, -32(%r8)
	jmp .Lbb1412
.Lbb1409:
	movq %rbx, %rdi
	.loc 1 517
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb1411:
	movq $4611686018427387904, %r11
	andq %r11, %r10
	cmpq $0, %r10
	jnz .Lbb1414
.Lbb1412:
	movq %r8, %rcx
	movq %rcx, -4112(%rbp)
	xchgl %r15d, %r12d
	jmp .Lbb1417
.Lbb1414:
	movq %r13, %rdx
	.loc 1 517
	movq %rdx, %r13
	leaq -4120(%rbp), %rdx
	leaq -4112(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_retain
	movq %r12, %rdi
	movl %eax, %ecx
	movl -3312(%rbp), %r15d
	movl -528(%rbp), %eax
	movl %r15d, %r12d
	movl -544(%rbp), %r15d
	movq -3088(%rbp), %r9
	movq -3320(%rbp), %rsi
	cmpl $0, %ecx
	jnz .Lbb1417
	.loc 1 517
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 517
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb1417:
	cmpl $0, %eax
	jz .Lbb1435
	testl $28, %r15d
	jnz .Lbb1427
	movq -4152(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1426
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r8
	andq %r8, %rax
	cmpq $0, %rax
	jnz .Lbb1425
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1424
	movq -24(%rcx), %r8
	cmpq $0, %r8
	jnz .Lbb1424
	.loc 1 517
	leaq -4152(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_drop
	movq %r12, %rdi
	movl -3312(%rbp), %r12d
	movq -3088(%rbp), %r9
	movq -3320(%rbp), %rsi
	jmp .Lbb1426
.Lbb1424:
	movq %rax, -32(%rcx)
.Lbb1425:
	movq $0, -4152(%rbp)
.Lbb1426:
	movl $0, %eax
	jmp .Lbb1435
.Lbb1427:
	movq -4152(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1434
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r8
	andq %r8, %rax
	cmpq $0, %rax
	jnz .Lbb1433
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1432
	movq -32(%rcx), %r8
	cmpq $0, %r8
	jnz .Lbb1432
	.loc 1 517
	leaq -4152(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_unloan
	movq %r12, %rdi
	movl -3312(%rbp), %r12d
	movq -3088(%rbp), %r9
	movq -3320(%rbp), %rsi
	jmp .Lbb1434
.Lbb1432:
	movq %rax, -24(%rcx)
.Lbb1433:
	movq $0, -4152(%rbp)
.Lbb1434:
	movl $0, %eax
.Lbb1435:
	movl %eax, %r15d
	xchgq %rdi, %rbx
	movl %r15d, -540(%rbp)
	movq %r13, %r15
	jmp .Lbb1447
.Lbb1437:
	movl %r15d, %r12d
	movq %r8, %rax
	movl %r10d, %r8d
	orl %r11d, %r8d
	jnz .Lbb1443
	cmpq $0, %rax
	jz .Lbb1441
	movq -16(%rax), %rax
	movq $5764607523034234881, %r8
	andq %r8, %rax
	cmpq $0, %rax
	jnz .Lbb1443
.Lbb1441:
	movq -4120(%rbp), %rax
	movq %rax, -4112(%rbp)
	movq $0, -4120(%rbp)
	movq %r13, %r15
	xchgq %rdi, %rbx
	jmp .Lbb1446
.Lbb1443:
	movq %r13, %rdx
	.loc 1 517
	movq %rdx, %r15
	leaq -4120(%rbp), %rdx
	leaq -4112(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_take
	movq %r12, %rdi
	movl -3312(%rbp), %r12d
	movq -3088(%rbp), %r9
	movq -3320(%rbp), %rsi
	cmpl $0, %eax
	jnz .Lbb1445
	.loc 1 517
	callq myl_rc_take_failure
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 517
	callq myl_qbe_rc_status
	jmp .Lbb2149
.Lbb1445:
	xchgq %rdi, %rbx
.Lbb1446:
	movl $0, -540(%rbp)
.Lbb1447:
	movq -4112(%rbp), %rax
	movq %rax, -3888(%rbp)
	movl -4160(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb1463
	movl $0, -4160(%rbp)
	testl $28, %r12d
	jnz .Lbb1456
	movq -3896(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1463
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r8
	andq %r8, %rax
	cmpq $0, %rax
	jnz .Lbb1455
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1454
	movq -24(%rcx), %r8
	cmpq $0, %r8
	jnz .Lbb1454
	.loc 1 517
	leaq -3896(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_drop
	movq %r12, %rdi
	movq -3088(%rbp), %r9
	movq -3320(%rbp), %rsi
	jmp .Lbb1463
.Lbb1454:
	movq %rax, -32(%rcx)
.Lbb1455:
	movq $0, -3896(%rbp)
	jmp .Lbb1463
.Lbb1456:
	movq -3896(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1463
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r8
	andq %r8, %rax
	cmpq $0, %rax
	jnz .Lbb1462
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1461
	movq -32(%rcx), %r8
	cmpq $0, %r8
	jnz .Lbb1461
	.loc 1 517
	leaq -3896(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_unloan
	movq %r12, %rdi
	movq -3088(%rbp), %r9
	movq -3320(%rbp), %rsi
	jmp .Lbb1463
.Lbb1461:
	movq %rax, -24(%rcx)
.Lbb1462:
	movq $0, -3896(%rbp)
.Lbb1463:
	movq $2, -3712(%rbp)
	movq %r9, %rax
	andq $1, %rax
	movq $0, -3712(%rbp)
	cmpq $0, %rax
	movq myl_f_fbed9662b733fdfc404927bad78ff653690e8f62f873cdf248e33fd8d09121dc@gotpcrel(%rip), %rcx
	movq myl_f_9b69cc26102b21a7460fda3a7ab6db6c07257af409e687daefa36812e17816b3@gotpcrel(%rip), %rax
	cmovnz %rcx, %rax
	movq %rax, -3352(%rbp)
	.loc 1 534
	movq %rdi, %r12
	callq myl_f_8a5a050356fb7a5094326f2b8ccffa083f61d461495e1103718ebd5cfb6ac591
	movq %r12, %rdi
	movq %rax, -3376(%rbp)
	movl -540(%rbp), %r13d
	movl -544(%rbp), %r12d
	movq -536(%rbp), %rsi
	movq -3344(%rbp), %rcx
	cmpq $3, %r14
	setz %r8b
	movzbq %r8b, %r8
	movq %r8, -3112(%rbp)
	movl $4294967295, %eax
	movq %r15, %r10
	andq %rax, %r10
	movq %r15, %r9
	shrq $32, %r9
	imulq $3, %r10, %rax
	shrq $32, %rax
	imulq $3, %r9, %r8
	addq %rax, %r8
	movl $4294967295, %eax
	andq %r8, %rax
	shrq $32, %r8
	imulq $0, %r10, %r10
	addq %r10, %rax
	shrq $32, %rax
	imulq $0, %r9, %r9
	addq %r9, %r8
	addq %r8, %rax
	negq %rsi
	movq %rsi, %r9
	andq $3, %r9
	movq %r15, %r8
	andq $0, %r8
	imulq $3, %r15, %rsi
	movq %rsi, -3096(%rbp)
	movq %rsi, %r10
	sarq $63, %r10
	movq %r10, -3144(%rbp)
	subq %r9, %rax
	subq %r8, %rax
	movq %rax, -3368(%rbp)
	movq %rsi, %r8
	addq $3, %r8
	movq %r8, -3072(%rbp)
	cmpq $-1, %r8
	setz %r11b
	movzbq %r11b, %r11
	movq %r11, -3304(%rbp)
	movq %r8, %rax
	xorq $1, %rax
	movq %rax, -3360(%rbp)
	movq %r15, %rax
	movq %rbx, %r15
	movq $0, -3160(%rbp)
	movl $0, %r11d
.p2align 4
.Lbb1466:
	movq %r11, -3296(%rbp)
	movq %rcx, -3712(%rbp)
	cmpq %rcx, %r11
	jge .Lbb1962
	movq $17, -3712(%rbp)
	movq %r11, %rsi
	sarq $63, %rsi
	movq %rax, %rbx
	movq %rsi, %rax
	xorq %r11, %rax
	subq %rsi, %rax
	movq $-1085102592571150095, %rcx
	mulq %rcx
	movq %rbx, %rax
	movq %rdx, %rcx
	shrq $4, %rcx
	xorq %rsi, %rcx
	subq %rsi, %rcx
	imulq $17, %rcx, %rcx
	negq %rcx
	addq %r11, %rcx
	cmpq $0, %rcx
	setnz %r8b
	movzbq %r8b, %r8
	andq %r8, %rsi
	negq %rsi
	andq $17, %rsi
	movq %rcx, %rbx
	addq %rsi, %rbx
	cvtsi2sd %rbx, %xmm0
	movq %xmm0, %rcx
	movq %rcx, %xmm0
	divsd ".Lfp0"(%rip), %xmm0
	movq %xmm0, %rcx
	movq %rcx, -3120(%rbp)
	movq %rcx, %xmm0
	movsd %xmm0, -2744(%rbp)
	movq $0, -2928(%rbp)
	movl $0, %r11d
.p2align 4
.Lbb1469:
	movq %rax, -3712(%rbp)
	cmpq %rax, %r11
	jge .Lbb1953
	movq -3960(%rbp), %rcx
	movq (%rcx), %rsi
	cmpq %rsi, %r11
	setb %sil
	movzbq %sil, %rsi
	cmpl $0, %esi
	jnz .Lbb1483
	movq $0, -3712(%rbp)
	cmpq $0, %r11
	jl .Lbb1473
	movq %rcx, %rsi
	movq %r11, %rcx
	jmp .Lbb1475
.Lbb1473:
	movq (%rcx), %r9
	movq $9223372036854775807, %rsi
	cmpq %rsi, %r9
	ja .Lbb1481
	movq %r11, -3712(%rbp)
	movq %rcx, %rsi
	movq %r9, %rcx
	addq %r11, %rcx
	movq %r9, %r8
	xorq %rcx, %r8
	movq %r11, %r10
	xorq %rcx, %r10
	andq %r10, %r8
	cmpq $0, %r8
	jl .Lbb1479
.Lbb1475:
	movq (%rsi), %r8
	cmpq %r8, %rcx
	jae .Lbb1477
	movq 32(%rsi), %rsi
	movq (%rsi, %rcx, 8), %r9
	jmp .Lbb1484
.Lbb1477:
	movq %r8, %rdx
	.loc 1 572
	movq %rcx, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1479:
	movq %r11, %rdx
	movq %r9, %rsi
	.loc 1 569
	movl $64, %r8d
	movq %rdx, %rcx
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1481:
	movq %r9, %rsi
	.loc 1 567
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb1483:
	movq 32(%rcx), %rcx
	movq (%rcx, %r11, 8), %r9
.Lbb1484:
	movq $0, -3712(%rbp)
	movq %rbx, %r10
	addq %r9, %r10
	movl $4294967295, %ecx
	andq %r10, %rcx
	movq %rcx, -2584(%rbp)
	movq %r10, %rsi
	shrq $32, %rsi
	movq %rsi, -2608(%rbp)
	imulq $0, %rcx, %r8
	movq %r8, -2784(%rbp)
	imulq $0, %rsi, %r8
	movq %r8, -2800(%rbp)
	cmpq $0, %r10
	setl %r8b
	movzbq %r8b, %r8
	movq %r8, -552(%rbp)
	movq -552(%rbp), %r8
	negq %r8
	movq %r8, -2848(%rbp)
	movq %r10, %r8
	andq $0, %r8
	movq %r8, -2872(%rbp)
	movq %r10, %r8
	xorq %r9, %r8
	movq %r8, -560(%rbp)
	movq %rbx, %r8
	xorq %r10, %r8
	movq %r8, -568(%rbp)
	movq -560(%rbp), %r8
	andq -568(%rbp), %r8
	cmpq $0, %r14
	jz .Lbb1934
	movq -3120(%rbp), %rax
	movq $1, -3712(%rbp)
	cmpq $1, %r14
	jz .Lbb1932
	movq -3112(%rbp), %rax
	movq $2, -3712(%rbp)
	cmpq $2, %r14
	jz .Lbb1491
	movq $3, -3712(%rbp)
	movq %rax, -656(%rbp)
	jmp .Lbb1492
.Lbb1491:
	movq $1, -656(%rbp)
.Lbb1492:
	imulq $3, %rcx, %rax
	movq %rax, -576(%rbp)
	movq -2784(%rbp), %rcx
	movq -576(%rbp), %rax
	shrq $32, %rax
	movq %rax, -592(%rbp)
	imulq $3, %rsi, %rax
	movq %rax, -584(%rbp)
	movq -2800(%rbp), %rsi
	movq -592(%rbp), %rax
	addq -584(%rbp), %rax
	movq %rax, -608(%rbp)
	movl $4294967295, %eax
	movq %rax, -600(%rbp)
	movq -608(%rbp), %rax
	andq -600(%rbp), %rax
	movq %rax, -616(%rbp)
	movq -608(%rbp), %rax
	shrq $32, %rax
	movq %rax, -632(%rbp)
	movq -616(%rbp), %rax
	addq %rcx, %rax
	movq %rax, -624(%rbp)
	movq -2848(%rbp), %rcx
	movq -624(%rbp), %rax
	shrq $32, %rax
	movq %rax, -648(%rbp)
	movq -632(%rbp), %rax
	addq %rsi, %rax
	movq %rax, -640(%rbp)
	movq -2872(%rbp), %rsi
	movq -648(%rbp), %rax
	addq -640(%rbp), %rax
	movq %rax, -672(%rbp)
	movq %rcx, %rax
	andq $3, %rax
	movq %rax, -664(%rbp)
	imulq $3, %r10, %rax
	movq %rax, -2592(%rbp)
	sarq $63, %rax
	movq %rax, -2728(%rbp)
	movq -656(%rbp), %rcx
	movq -672(%rbp), %rax
	subq -664(%rbp), %rax
	movq %rax, -680(%rbp)
	movq -680(%rbp), %rax
	subq %rsi, %rax
	movq %rax, -2736(%rbp)
	cmpl $0, %ecx
	jnz .Lbb1897
	movq $4, -3712(%rbp)
	movq %r9, %rcx
	sarq $63, %rcx
	movq %rcx, %rax
	xorq %r9, %rax
	subq %rcx, %rax
	movq %rax, -1736(%rbp)
	movq $-1085102592571150095, %rsi
	mulq %rsi
	movq %rdx, %rax
	shrq $4, %rax
	xorq %rcx, %rax
	subq %rcx, %rax
	imulq $17, %rax, %rax
	negq %rax
	addq %r9, %rax
	cmpq $0, %rax
	setnz %sil
	movzbq %sil, %rsi
	andq %rcx, %rsi
	negq %rsi
	andq $17, %rsi
	addq %rsi, %rax
	movl $4294967295, %esi
	andq %r9, %rsi
	movq %r9, %rdi
	shrq $32, %rdi
	movq %rdi, -728(%rbp)
	imulq $3, %rsi, %rdi
	movq %rdi, -688(%rbp)
	movq -688(%rbp), %rdi
	shrq $32, %rdi
	movq %rdi, -704(%rbp)
	movl $3, %edi
	imulq -728(%rbp), %rdi
	movq %rdi, -696(%rbp)
	movq -704(%rbp), %rdi
	addq -696(%rbp), %rdi
	movq %rdi, -720(%rbp)
	movl $4294967295, %edi
	movq %rdi, -712(%rbp)
	movq -720(%rbp), %rdi
	andq -712(%rbp), %rdi
	movq %rdi, -744(%rbp)
	movq -720(%rbp), %rdi
	shrq $32, %rdi
	movq %rdi, -760(%rbp)
	imulq $0, %rsi, %rsi
	movq %rsi, -736(%rbp)
	movq -728(%rbp), %rsi
	movq -744(%rbp), %rdi
	addq -736(%rbp), %rdi
	movq %rdi, -752(%rbp)
	movq -752(%rbp), %rdi
	shrq $32, %rdi
	movq %rdi, -776(%rbp)
	imulq $0, %rsi, %rsi
	movq %rsi, -768(%rbp)
	movq -760(%rbp), %rsi
	addq -768(%rbp), %rsi
	movq %rsi, -784(%rbp)
	movq -776(%rbp), %rsi
	addq -784(%rbp), %rsi
	movq %rsi, -800(%rbp)
	cmpq $0, %r9
	setl %sil
	movzbq %sil, %rsi
	negq %rsi
	andq $3, %rsi
	movq %rsi, -792(%rbp)
	movq %r9, %rsi
	andq $0, %rsi
	movq %rsi, -816(%rbp)
	imulq $3, %r9, %rsi
	movq %rsi, -2480(%rbp)
	movq %rsi, %rdi
	sarq $63, %rdi
	movq %rdi, -2440(%rbp)
	movq -800(%rbp), %rdi
	subq -792(%rbp), %rdi
	movq %rdi, -808(%rbp)
	movq -808(%rbp), %rdi
	subq -816(%rbp), %rdi
	movq %rdi, -2448(%rbp)
	addq %rbx, %rsi
	movq %rsi, -1320(%rbp)
	movq -2480(%rbp), %rdi
	xorq %rsi, %rdi
	movq %rdi, -832(%rbp)
	movq %rbx, %rdi
	xorq %rsi, %rdi
	movq %rdi, -824(%rbp)
	movq -832(%rbp), %rdi
	andq -824(%rbp), %rdi
	movq %rdi, -2472(%rbp)
	movq %rsi, %rdi
	sarq $63, %rdi
	movq %rdi, -920(%rbp)
	movq -920(%rbp), %rdi
	xorq %rsi, %rdi
	movq %rdi, -840(%rbp)
	movq -840(%rbp), %rdi
	subq -920(%rbp), %rdi
	movq %rdi, -856(%rbp)
	movq $4931307821684731621, %rdi
	movq %rdi, -848(%rbp)
	movq %rax, %rdi
	movq -856(%rbp), %rax
	mulq -848(%rbp)
	movq %rdi, %rax
	movq %rdx, -880(%rbp)
	movq -856(%rbp), %rdi
	subq -880(%rbp), %rdi
	movq %rdi, -864(%rbp)
	movq -864(%rbp), %rdi
	shrq $1, %rdi
	movq %rdi, -872(%rbp)
	movq -880(%rbp), %rdi
	addq -872(%rbp), %rdi
	movq %rdi, -888(%rbp)
	movq -888(%rbp), %rdi
	shrq $6, %rdi
	movq %rdi, -896(%rbp)
	movq -920(%rbp), %rdi
	xorq -896(%rbp), %rdi
	movq %rdi, -904(%rbp)
	movq -904(%rbp), %rdi
	subq -920(%rbp), %rdi
	movq %rdi, -912(%rbp)
	movl $101, %edi
	imulq -912(%rbp), %rdi
	movq %rdi, -928(%rbp)
	movq -920(%rbp), %rdi
	subq -928(%rbp), %rsi
	movq %rsi, -936(%rbp)
	cmpq $0, %rsi
	setnz %sil
	movzbq %sil, %rsi
	movq %rsi, -944(%rbp)
	movq -936(%rbp), %rsi
	andq -944(%rbp), %rdi
	negq %rdi
	andq $101, %rdi
	addq %rdi, %rsi
	movl $4294967295, %edi
	movq %rdi, -952(%rbp)
	movq %rax, %rdi
	andq -952(%rbp), %rdi
	movq %rdi, -1000(%rbp)
	movq %rax, %rdi
	shrq $32, %rdi
	movq %rdi, -1032(%rbp)
	movl $3, %edi
	imulq -1000(%rbp), %rdi
	movq %rdi, -960(%rbp)
	movq -960(%rbp), %rdi
	shrq $32, %rdi
	movq %rdi, -976(%rbp)
	movl $3, %edi
	imulq -1032(%rbp), %rdi
	movq %rdi, -968(%rbp)
	movq -976(%rbp), %rdi
	addq -968(%rbp), %rdi
	movq %rdi, -992(%rbp)
	movl $4294967295, %edi
	movq %rdi, -984(%rbp)
	movq -992(%rbp), %rdi
	andq -984(%rbp), %rdi
	movq %rdi, -1016(%rbp)
	movq -992(%rbp), %rdi
	shrq $32, %rdi
	movq %rdi, -1048(%rbp)
	movl $0, %edi
	imulq -1000(%rbp), %rdi
	movq %rdi, -1008(%rbp)
	movq -1016(%rbp), %rdi
	addq -1008(%rbp), %rdi
	movq %rdi, -1024(%rbp)
	movq -1024(%rbp), %rdi
	shrq $32, %rdi
	movq %rdi, -1064(%rbp)
	movl $0, %edi
	imulq -1032(%rbp), %rdi
	movq %rdi, -1040(%rbp)
	movq -1048(%rbp), %rdi
	addq -1040(%rbp), %rdi
	movq %rdi, -1056(%rbp)
	movq -1064(%rbp), %rdi
	addq -1056(%rbp), %rdi
	movq %rdi, -1096(%rbp)
	cmpq $0, %rax
	setl %dil
	movzbq %dil, %rdi
	movq %rdi, -1072(%rbp)
	movq -1072(%rbp), %rdi
	negq %rdi
	movq %rdi, -1080(%rbp)
	movq -1080(%rbp), %rdi
	andq $3, %rdi
	movq %rdi, -1088(%rbp)
	movq %rax, %rdi
	andq $0, %rdi
	movq %rdi, -1112(%rbp)
	imulq $3, %rax, %rdi
	movq %rdi, -2456(%rbp)
	movq -2456(%rbp), %rdi
	sarq $63, %rdi
	movq %rdi, -2488(%rbp)
	movq -1096(%rbp), %rdi
	subq -1088(%rbp), %rdi
	movq %rdi, -1104(%rbp)
	movq -1104(%rbp), %rdi
	subq -1112(%rbp), %rdi
	movq %rdi, -2496(%rbp)
	movq %r10, %rdi
	addq -2456(%rbp), %rdi
	movq %rdi, -2504(%rbp)
	movq %r10, %rdi
	xorq -2504(%rbp), %rdi
	movq %rdi, -1128(%rbp)
	movq -2456(%rbp), %rdi
	xorq -2504(%rbp), %rdi
	movq %rdi, -1120(%rbp)
	movq -1128(%rbp), %rdi
	andq -1120(%rbp), %rdi
	movq %rdi, -2520(%rbp)
	movl $4294967295, %edi
	movq %rdi, -1136(%rbp)
	movq %rsi, %rdi
	andq -1136(%rbp), %rdi
	movq %rdi, -1184(%rbp)
	movq %rsi, %rdi
	shrq $32, %rdi
	movq %rdi, -1216(%rbp)
	movl $5, %edi
	imulq -1184(%rbp), %rdi
	movq %rdi, -1144(%rbp)
	movq -1144(%rbp), %rdi
	shrq $32, %rdi
	movq %rdi, -1160(%rbp)
	movl $5, %edi
	imulq -1216(%rbp), %rdi
	movq %rdi, -1152(%rbp)
	movq -1160(%rbp), %rdi
	addq -1152(%rbp), %rdi
	movq %rdi, -1176(%rbp)
	movl $4294967295, %edi
	movq %rdi, -1168(%rbp)
	movq -1176(%rbp), %rdi
	andq -1168(%rbp), %rdi
	movq %rdi, -1200(%rbp)
	movq -1176(%rbp), %rdi
	shrq $32, %rdi
	movq %rdi, -1232(%rbp)
	movl $0, %edi
	imulq -1184(%rbp), %rdi
	movq %rdi, -1192(%rbp)
	movq -1200(%rbp), %rdi
	addq -1192(%rbp), %rdi
	movq %rdi, -1208(%rbp)
	movq -1208(%rbp), %rdi
	shrq $32, %rdi
	movq %rdi, -1248(%rbp)
	movl $0, %edi
	imulq -1216(%rbp), %rdi
	movq %rdi, -1224(%rbp)
	movq -1232(%rbp), %rdi
	addq -1224(%rbp), %rdi
	movq %rdi, -1240(%rbp)
	movq -1248(%rbp), %rdi
	addq -1240(%rbp), %rdi
	movq %rdi, -1280(%rbp)
	cmpq $0, %rsi
	setl %dil
	movzbq %dil, %rdi
	movq %rdi, -1256(%rbp)
	movq -1256(%rbp), %rdi
	negq %rdi
	movq %rdi, -1264(%rbp)
	movq -1264(%rbp), %rdi
	andq $5, %rdi
	movq %rdi, -1272(%rbp)
	movq %rsi, %rdi
	andq $0, %rdi
	movq %rdi, -1296(%rbp)
	imulq $5, %rsi, %rdi
	movq %rdi, -2464(%rbp)
	movq -2464(%rbp), %rdi
	sarq $63, %rdi
	movq %rdi, -2528(%rbp)
	movq -1280(%rbp), %rdi
	subq -1272(%rbp), %rdi
	movq %rdi, -1288(%rbp)
	movq -1288(%rbp), %rdi
	subq -1296(%rbp), %rdi
	movq %rdi, -2536(%rbp)
	movq -2504(%rbp), %rdi
	addq -2464(%rbp), %rdi
	movq %rdi, -2512(%rbp)
	movq -2504(%rbp), %rdi
	xorq -2512(%rbp), %rdi
	movq %rdi, -1312(%rbp)
	movq -2464(%rbp), %rdi
	xorq -2512(%rbp), %rdi
	movq %rdi, -1304(%rbp)
	movq -1312(%rbp), %rdi
	andq -1304(%rbp), %rdi
	movq %rdi, -2544(%rbp)
	movq -2760(%rbp), %rdi
	cmpq $4, %r14
	jz .Lbb1871
	movq $5, -3712(%rbp)
	cmpq $5, %r14
	jz .Lbb1829
	movq -2896(%rbp), %rsi
	movq -2752(%rbp), %rax
	movq $6, -3712(%rbp)
	cmpq $6, %r14
	jz .Lbb1816
	movq $7, -3712(%rbp)
	cmpq $7, %r14
	jz .Lbb1810
	movq $8, -3712(%rbp)
	cmpq $8, %r14
	jz .Lbb1791
	movq $9, -3712(%rbp)
	cmpq $9, %r14
	jz .Lbb1767
	movq -3096(%rbp), %r15
	movq %r8, %rdx
	movq -3072(%rbp), %r8
	movq %rsi, %rcx
	movq -3088(%rbp), %rsi
	movq $10, -3712(%rbp)
	cmpq $10, %r14
	jz .Lbb1722
	movq $11, -3712(%rbp)
	cmpq $11, %r14
	jnz .Lbb1550
	movq -3888(%rbp), %rax
	movq $0, -3712(%rbp)
	cmpq $0, %r11
	jl .Lbb1505
	movq %r11, %r14
	jmp .Lbb1507
.Lbb1505:
	movq (%rax), %rsi
	movq $9223372036854775807, %rcx
	cmpq %rcx, %rsi
	ja .Lbb1549
	movq %r11, -3712(%rbp)
	movq %r11, %r14
	addq %rsi, %r11
	movq %rsi, %rcx
	xorq %r11, %rcx
	movq %r14, %rdx
	xorq %r11, %rdx
	andq %rdx, %rcx
	cmpq $0, %rcx
	jl .Lbb1547
.Lbb1507:
	movq (%rax), %rcx
	cmpq %rcx, %r11
	jae .Lbb1545
	movq 32(%rax), %rax
	movq (%rax, %r11, 8), %rdx
	.loc 1 1006
	movq %rdi, %rsi
	leaq -4232(%rbp), %rdi
	callq myl_f_713a1417c769dc7584c090ac7ff485481f486a11bb803fbf9ec54289769f2854
	movq %r14, %r11
	movq %rax, %r8
	movq -2928(%rbp), %rsi
	movq -2776(%rbp), %r14
	movq -2768(%rbp), %r15
	movsd -2744(%rbp), %xmm0
	movq -2896(%rbp), %rcx
	movq -2752(%rbp), %rax
	movq -2760(%rbp), %rdi
	movq %r8, -1328(%rbp)
	cmpl $0, %r13d
	jz .Lbb1528
	testl $28, %r12d
	jnz .Lbb1519
	movq -4152(%rbp), %r10
	cmpq $0, %r10
	jz .Lbb1518
	movq -16(%r10), %r9
	movq $4611686018427387906, %r13
	andq %r13, %r9
	cmpq $0, %r9
	jnz .Lbb1517
	movq -32(%r10), %r9
	subq $1, %r9
	jnz .Lbb1516
	movq %r11, %r13
	movq -24(%r10), %r11
	cmpq $0, %r11
	jnz .Lbb1515
	.loc 1 1006
	leaq -4152(%rbp), %rsi
	movq %r15, %rdi
	callq myl_t_277089d91c0bdf4f2e6862ba7e4a07605119431f5d13f726dd352b06f1b206a9_rcg_drop
	movq %r13, %r11
	movq -2928(%rbp), %rsi
	movq -2768(%rbp), %r15
	movq -1328(%rbp), %r8
	movsd -2744(%rbp), %xmm0
	movq -2896(%rbp), %rcx
	movq -2752(%rbp), %rax
	movq -2760(%rbp), %rdi
	jmp .Lbb1518
.Lbb1515:
	movq %r13, %r11
.Lbb1516:
	movq %r9, -32(%r10)
.Lbb1517:
	movq $0, -4152(%rbp)
.Lbb1518:
	movl $0, %r13d
	jmp .Lbb1528
.Lbb1519:
	movq -4152(%rbp), %r10
	cmpq $0, %r10
	jz .Lbb1527
	movq -16(%r10), %r9
	movq $4611686018427387906, %r13
	andq %r13, %r9
	cmpq $0, %r9
	jnz .Lbb1526
	movq -24(%r10), %r9
	subq $1, %r9
	jnz .Lbb1525
	movq %r11, %r13
	movq -32(%r10), %r11
	cmpq $0, %r11
	jnz .Lbb1524
	.loc 1 1006
	leaq -4152(%rbp), %rsi
	movq %r15, %rdi
	callq myl_t_277089d91c0bdf4f2e6862ba7e4a07605119431f5d13f726dd352b06f1b206a9_rcg_unloan
	movq %r13, %r11
	movq -2928(%rbp), %rsi
	movq -2768(%rbp), %r15
	movq -1328(%rbp), %r8
	movsd -2744(%rbp), %xmm0
	movq -2896(%rbp), %rcx
	movq -2752(%rbp), %rax
	movq -2760(%rbp), %rdi
	jmp .Lbb1527
.Lbb1524:
	movq %r13, %r11
.Lbb1525:
	movq %r9, -24(%r10)
.Lbb1526:
	movq $0, -4152(%rbp)
.Lbb1527:
	movl $0, %r13d
.Lbb1528:
	movl (%r8), %r9d
	cmpq $0, %r9
	setz %r10b
	movzbq %r10b, %r10
	movq %r10, -1336(%rbp)
	movq %rsi, %r10
	movq %r8, %rsi
	addq $8, %rsi
	cmpl $0, -1336(%rbp)
	jnz .Lbb1535
	movq %r10, %rsi
	cmpq $1, %r9
	jnz .Lbb2149
	movq 8(%r8), %r9
	movq %r9, -4112(%rbp)
	movq $101, -3712(%rbp)
	imulq $101, %r9, %r10
	movq %r10, -1416(%rbp)
	movl $4294967295, %r8d
	andq %r9, %r8
	movq %r9, %r10
	shrq $32, %r10
	movq %r10, -1384(%rbp)
	imulq $101, %r8, %r10
	movq %r10, -1344(%rbp)
	movq -1344(%rbp), %r10
	shrq $32, %r10
	movq %r10, -1360(%rbp)
	movl $101, %r10d
	imulq -1384(%rbp), %r10
	movq %r10, -1352(%rbp)
	movq -1360(%rbp), %r10
	addq -1352(%rbp), %r10
	movq %r10, -1376(%rbp)
	movl $4294967295, %r10d
	movq %r10, -1368(%rbp)
	movq -1376(%rbp), %r10
	andq -1368(%rbp), %r10
	movq %r10, -1400(%rbp)
	movq -1376(%rbp), %r10
	shrq $32, %r10
	movq %r10, -1432(%rbp)
	imulq $0, %r8, %r8
	movq %r8, -1392(%rbp)
	movq -1384(%rbp), %r8
	movq -1400(%rbp), %r10
	addq -1392(%rbp), %r10
	movq %r10, -1408(%rbp)
	movq -1408(%rbp), %r10
	shrq $32, %r10
	movq %r10, -1448(%rbp)
	imulq $0, %r8, %r8
	movq %r8, -1424(%rbp)
	movq -1416(%rbp), %r10
	movq -1432(%rbp), %r8
	addq -1424(%rbp), %r8
	movq %r8, -1440(%rbp)
	movq -1448(%rbp), %r8
	addq -1440(%rbp), %r8
	movq %r8, -1480(%rbp)
	cmpq $0, %r9
	setl %r8b
	movzbq %r8b, %r8
	movq %r8, -1456(%rbp)
	movq -1456(%rbp), %r8
	negq %r8
	movq %r8, -1464(%rbp)
	movq -1464(%rbp), %r8
	andq $101, %r8
	movq %r8, -1472(%rbp)
	movq %r9, %r8
	andq $0, %r8
	movq %r8, -1496(%rbp)
	movq -1480(%rbp), %r8
	subq -1472(%rbp), %r8
	movq %r8, -1488(%rbp)
	movq -1488(%rbp), %r8
	subq -1496(%rbp), %r8
	movq %r8, -1504(%rbp)
	movq %r10, %r8
	sarq $63, %r8
	cmpq -1504(%rbp), %r8
	jnz .Lbb1533
	movq %r14, %r8
	movq %r11, %r14
	jmp .Lbb1538
.Lbb1533:
	movq %r9, %rdx
	.loc 1 1022
	movl $64, %r8d
	movl $101, %ecx
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1535:
	movq 0(%rsi), %r8
	movq %r8, -4112(%rbp)
	movq 8(%rsi), %r8
	movq %r8, -4104(%rbp)
	movq 16(%rsi), %rsi
	movq %rsi, -4096(%rbp)
	movq -4112(%rbp), %rsi
	movq %rsi, -3784(%rbp)
	movq -4104(%rbp), %rsi
	movq %rsi, -3776(%rbp)
	movq -4096(%rbp), %rsi
	movq %rsi, -3768(%rbp)
	movq -3784(%rbp), %r10
	leaq -3784(%rbp), %rsi
	movq %rsi, -3712(%rbp)
	movq -3776(%rbp), %r9
	movq %r9, -3712(%rbp)
	movq $3, -3704(%rbp)
	imulq $3, %r9, %rsi
	movl $4294967295, %r8d
	movq %r8, -1512(%rbp)
	movq %r9, %r8
	andq -1512(%rbp), %r8
	movq %r8, -1560(%rbp)
	movq %r9, %r8
	shrq $32, %r8
	movq %r8, -1592(%rbp)
	movl $3, %r8d
	imulq -1560(%rbp), %r8
	movq %r8, -1520(%rbp)
	movq -1520(%rbp), %r8
	shrq $32, %r8
	movq %r8, -1536(%rbp)
	movl $3, %r8d
	imulq -1592(%rbp), %r8
	movq %r8, -1528(%rbp)
	movq -1536(%rbp), %r8
	addq -1528(%rbp), %r8
	movq %r8, -1552(%rbp)
	movl $4294967295, %r8d
	movq %r8, -1544(%rbp)
	movq -1552(%rbp), %r8
	andq -1544(%rbp), %r8
	movq %r8, -1576(%rbp)
	movq -1552(%rbp), %r8
	shrq $32, %r8
	movq %r8, -1608(%rbp)
	movl $0, %r8d
	imulq -1560(%rbp), %r8
	movq %r8, -1568(%rbp)
	movq -1576(%rbp), %r8
	addq -1568(%rbp), %r8
	movq %r8, -1584(%rbp)
	movq -1584(%rbp), %r8
	shrq $32, %r8
	movq %r8, -1624(%rbp)
	movl $0, %r8d
	imulq -1592(%rbp), %r8
	movq %r8, -1600(%rbp)
	movq -1608(%rbp), %r8
	addq -1600(%rbp), %r8
	movq %r8, -1616(%rbp)
	movq -1624(%rbp), %r8
	addq -1616(%rbp), %r8
	movq %r8, -1656(%rbp)
	cmpq $0, %r9
	setl %r8b
	movzbq %r8b, %r8
	movq %r8, -1632(%rbp)
	movq -1632(%rbp), %r8
	negq %r8
	movq %r8, -1640(%rbp)
	movq -1640(%rbp), %r8
	andq $3, %r8
	movq %r8, -1648(%rbp)
	movq %r9, %r8
	andq $0, %r8
	movq %r8, -1672(%rbp)
	movq -1656(%rbp), %r8
	subq -1648(%rbp), %r8
	movq %r8, -1664(%rbp)
	movq -1664(%rbp), %r8
	subq -1672(%rbp), %r8
	movq %r8, -1680(%rbp)
	movq %rsi, %r8
	sarq $63, %r8
	cmpq -1680(%rbp), %r8
	jnz .Lbb1543
	movq %rsi, -3712(%rbp)
	movq %r10, %r9
	addq %rsi, %r9
	movq %r10, %r8
	xorq %r9, %r8
	movq %r8, -1688(%rbp)
	movq %rsi, %r8
	xorq %r9, %r8
	movq %r8, -1696(%rbp)
	movq %r14, %r8
	movq -1688(%rbp), %r14
	andq -1696(%rbp), %r14
	cmpq $0, %r14
	jl .Lbb1541
	leaq -3784(%rbp), %rsi
	movq %rsi, -3712(%rbp)
	movq %r11, %r14
	movq -3768(%rbp), %r11
	movq %r11, -3712(%rbp)
	movq %r11, %r10
	addq %r9, %r10
	movq %r9, %rsi
	xorq %r10, %rsi
	movq %rsi, -1712(%rbp)
	movq %r11, %rsi
	xorq %r10, %rsi
	movq %rsi, -1704(%rbp)
	movq -1712(%rbp), %rsi
	andq -1704(%rbp), %rsi
	movq %rsi, -1720(%rbp)
	movq -2928(%rbp), %rsi
	cmpq $0, -1720(%rbp)
	jl .Lbb1539
.Lbb1538:
	movq %r14, %r11
	movq %r8, %r14
	jmp .Lbb1938
.Lbb1539:
	movq %r9, %rdx
	movq %r11, %rcx
	.loc 1 1017
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1541:
	movq %rsi, %rcx
	movq %r10, %rdx
	.loc 1 1014
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1543:
	movq %r9, %rdx
	.loc 1 1013
	movl $64, %r8d
	movl $3, %ecx
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1545:
	movq %rcx, %rdx
	.loc 1 1005
	movq %r11, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1547:
	movq %r14, %rdx
	.loc 1 1002
	movl $64, %r8d
	movq %rdx, %rcx
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1549:
	.loc 1 1000
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb1550:
	movl -3312(%rbp), %r15d
	movl -3388(%rbp), %r14d
	movl -3412(%rbp), %r13d
	movl -3392(%rbp), %r12d
	movq -2768(%rbp), %rbx
	movl -4048(%rbp), %eax
	movl -4016(%rbp), %ecx
	orl %ecx, %eax
	jz .Lbb1553
	leaq -4072(%rbp), %rax
	movq %rax, -4008(%rbp)
	leaq -4040(%rbp), %rax
	movq %rax, -4000(%rbp)
	.loc 1 1027
	movl $2, %edx
	leaq -4008(%rbp), %rsi
	movq %rdi, %r13
	callq myl_qbe_rc_scopes_close
	movq %r13, %rdi
	movl -3412(%rbp), %r13d
.Lbb1553:
	.loc 1 1027
	callq myl_qbe_exit_skip
	movl %r13d, %edx
	movq %rbx, %rdi
	movl %edx, %r13d
	movl -3420(%rbp), %edx
	movl -3416(%rbp), %ebx
	cmpl $0, %eax
	jnz .Lbb1721
	movq -3888(%rbp), %rcx
	cmpq $0, %rcx
	jnz .Lbb1556
	xchgl %edx, %r13d
	jmp .Lbb1565
.Lbb1556:
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1563
	movq -32(%rcx), %rax
	subq $1, %rax
	jz .Lbb1559
	xchgl %edx, %r13d
	jmp .Lbb1562
.Lbb1559:
	movq -24(%rcx), %rsi
	cmpq $0, %rsi
	jnz .Lbb1561
	.loc 1 1027
	leaq -3888(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_drop
	movl %r13d, %edx
	movq %rbx, %rdi
	movl -3420(%rbp), %r13d
	movl -3416(%rbp), %ebx
	jmp .Lbb1565
.Lbb1561:
	xchgl %edx, %r13d
.Lbb1562:
	movq %rax, -32(%rcx)
	jmp .Lbb1564
.Lbb1563:
	xchgl %edx, %r13d
.Lbb1564:
	movq $0, -3888(%rbp)
.Lbb1565:
	movl -4160(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb1583
	movl $0, -4160(%rbp)
	testl $28, %r15d
	jnz .Lbb1575
	movq -3896(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1583
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1574
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1573
	movl %edx, %r15d
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1572
	.loc 1 1027
	leaq -3896(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_drop
	movl %r15d, %edx
	movq %r13, %rdi
	movl -3420(%rbp), %r13d
	jmp .Lbb1583
.Lbb1572:
	movl %r15d, %edx
.Lbb1573:
	movq %rax, -32(%rcx)
.Lbb1574:
	movq $0, -3896(%rbp)
	jmp .Lbb1583
.Lbb1575:
	movq -3896(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1583
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1582
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1581
	movl %edx, %r15d
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1580
	.loc 1 1027
	leaq -3896(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_unloan
	movl %r15d, %edx
	movq %r13, %rdi
	movl -3420(%rbp), %r13d
	jmp .Lbb1583
.Lbb1580:
	movl %r15d, %edx
.Lbb1581:
	movq %rax, -24(%rcx)
.Lbb1582:
	movq $0, -3896(%rbp)
.Lbb1583:
	movq -3904(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1591
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1590
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1589
	movl %edx, %r15d
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1588
	.loc 1 1027
	leaq -3904(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_drop
	movl %r15d, %edx
	movq %r13, %rdi
	movl -3420(%rbp), %r13d
	jmp .Lbb1591
.Lbb1588:
	movl %r15d, %edx
.Lbb1589:
	movq %rax, -32(%rcx)
.Lbb1590:
	movq $0, -3904(%rbp)
.Lbb1591:
	movl -4168(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb1609
	movl $0, -4168(%rbp)
	testl $28, %r14d
	jnz .Lbb1601
	movq -3912(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1609
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1600
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1599
	movl %edx, %r15d
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1598
	.loc 1 1027
	leaq -3912(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_drop
	movl %r15d, %edx
	movq %r14, %rdi
	jmp .Lbb1609
.Lbb1598:
	movl %r15d, %edx
.Lbb1599:
	movq %rax, -32(%rcx)
.Lbb1600:
	movq $0, -3912(%rbp)
	jmp .Lbb1609
.Lbb1601:
	movq -3912(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1609
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1608
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1607
	movl %edx, %r15d
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1606
	.loc 1 1027
	leaq -3912(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_unloan
	movl %r15d, %edx
	movq %r14, %rdi
	jmp .Lbb1609
.Lbb1606:
	movl %r15d, %edx
.Lbb1607:
	movq %rax, -24(%rcx)
.Lbb1608:
	movq $0, -3912(%rbp)
.Lbb1609:
	movq -3920(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1617
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1616
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1615
	movl %edx, %r15d
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1614
	.loc 1 1027
	leaq -3920(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movl %r15d, %edx
	movq %r14, %rdi
	jmp .Lbb1617
.Lbb1614:
	movl %r15d, %edx
.Lbb1615:
	movq %rax, -24(%rcx)
.Lbb1616:
	movq $0, -3920(%rbp)
.Lbb1617:
	movq -3928(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1625
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1624
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1623
	movl %edx, %r15d
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1622
	.loc 1 1027
	leaq -3928(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_drop
	movl %r15d, %edx
	movq %r14, %rdi
	jmp .Lbb1625
.Lbb1622:
	movl %r15d, %edx
.Lbb1623:
	movq %rax, -32(%rcx)
.Lbb1624:
	movq $0, -3928(%rbp)
.Lbb1625:
	movl -4176(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb1634
	movl $0, -4176(%rbp)
	movq -3936(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1634
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1633
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1632
	movl %edx, %r15d
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1631
	.loc 1 1027
	leaq -3936(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_drop
	movl %r15d, %edx
	movq %r14, %rdi
	jmp .Lbb1634
.Lbb1631:
	movl %r15d, %edx
.Lbb1632:
	movq %rax, -32(%rcx)
.Lbb1633:
	movq $0, -3936(%rbp)
.Lbb1634:
	movq -3944(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1642
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1641
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1640
	movl %edx, %r15d
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1639
	.loc 1 1027
	leaq -3944(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movl %r15d, %edx
	movq %r14, %rdi
	jmp .Lbb1642
.Lbb1639:
	movl %r15d, %edx
.Lbb1640:
	movq %rax, -32(%rcx)
.Lbb1641:
	movq $0, -3944(%rbp)
.Lbb1642:
	movl -4184(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb1660
	movl $0, -4184(%rbp)
	testl $28, %r13d
	jnz .Lbb1652
	movq -3952(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1660
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1651
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1650
	movl %edx, %r14d
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1649
	.loc 1 1027
	leaq -3952(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movl %r14d, %edx
	movq %r13, %rdi
	jmp .Lbb1660
.Lbb1649:
	movl %r14d, %edx
.Lbb1650:
	movq %rax, -32(%rcx)
.Lbb1651:
	movq $0, -3952(%rbp)
	jmp .Lbb1660
.Lbb1652:
	movq -3952(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1660
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1659
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1658
	movl %edx, %r14d
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1657
	.loc 1 1027
	leaq -3952(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movl %r14d, %edx
	movq %r13, %rdi
	jmp .Lbb1660
.Lbb1657:
	movl %r14d, %edx
.Lbb1658:
	movq %rax, -24(%rcx)
.Lbb1659:
	movq $0, -3952(%rbp)
.Lbb1660:
	movq -3960(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1668
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1667
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1666
	movl %edx, %r14d
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1665
	.loc 1 1027
	leaq -3960(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movl %r14d, %edx
	movq %r13, %rdi
	jmp .Lbb1668
.Lbb1665:
	movl %r14d, %edx
.Lbb1666:
	movq %rax, -32(%rcx)
.Lbb1667:
	movq $0, -3960(%rbp)
.Lbb1668:
	movl -4192(%rbp), %eax
	cmpl $0, %eax
	jnz .Lbb1670
	movl %edx, %r13d
	jmp .Lbb1690
.Lbb1670:
	movl $0, -4192(%rbp)
	testl $28, %ebx
	jnz .Lbb1680
	movq -3968(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1679
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1678
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1677
	movl %edx, %r13d
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1676
	.loc 1 1027
	leaq -3968(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movl %r13d, %edx
	movq %rbx, %rdi
	jmp .Lbb1679
.Lbb1676:
	movl %r13d, %edx
.Lbb1677:
	movq %rax, -32(%rcx)
.Lbb1678:
	movq $0, -3968(%rbp)
.Lbb1679:
	movl %edx, %r13d
	jmp .Lbb1690
.Lbb1680:
	movq -3968(%rbp), %rcx
	cmpq $0, %rcx
	jnz .Lbb1682
	movl %edx, %r13d
	jmp .Lbb1690
.Lbb1682:
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1688
	movq -24(%rcx), %rax
	subq $1, %rax
	jz .Lbb1685
	movl %edx, %r13d
	jmp .Lbb1687
.Lbb1685:
	movl %edx, %r13d
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1687
	.loc 1 1027
	leaq -3968(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movq %rbx, %rdi
	jmp .Lbb1690
.Lbb1687:
	movq %rax, -24(%rcx)
	jmp .Lbb1689
.Lbb1688:
	movl %edx, %r13d
.Lbb1689:
	movq $0, -3968(%rbp)
.Lbb1690:
	cmpl $0, %r13d
	jz .Lbb1706
	testl $28, %r12d
	jnz .Lbb1699
	movq -3976(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1706
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb1698
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1697
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1697
	.loc 1 1027
	leaq -3976(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %rbx, %rdi
	jmp .Lbb1706
.Lbb1697:
	movq %rax, -32(%rcx)
.Lbb1698:
	movq $0, -3976(%rbp)
	jmp .Lbb1706
.Lbb1699:
	movq -3976(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1706
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb1705
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1704
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1704
	.loc 1 1027
	leaq -3976(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_unloan
	movq %rbx, %rdi
	jmp .Lbb1706
.Lbb1704:
	movq %rax, -24(%rcx)
.Lbb1705:
	movq $0, -3976(%rbp)
.Lbb1706:
	movq -3984(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1713
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb1712
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1711
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1711
	.loc 1 1027
	leaq -3984(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %rbx, %rdi
	jmp .Lbb1713
.Lbb1711:
	movq %rax, -32(%rcx)
.Lbb1712:
	movq $0, -3984(%rbp)
.Lbb1713:
	movl -4200(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb1721
	movl $0, -4200(%rbp)
	movq -3992(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1721
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb1720
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1719
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1719
	.loc 1 1027
	leaq -3992(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	jmp .Lbb1721
.Lbb1719:
	movq %rax, -32(%rcx)
.Lbb1720:
	movq $0, -3992(%rbp)
.Lbb1721:
	movl $2, %eax
	jmp .Lbb2381
.Lbb1722:
	movq %r11, %r14
	movq %rsi, %r11
	movq -3944(%rbp), %rsi
	movq %r9, -3712(%rbp)
	movq %rbx, -3704(%rbp)
	cmpq $0, %rdx
	movq -3144(%rbp), %rdx
	jl .Lbb1765
	movq %r11, %r9
	movq -3304(%rbp), %r11
	movq %r10, -3712(%rbp)
	movq %rax, -3704(%rbp)
	movq -3368(%rbp), %rax
	cmpq %rax, %rdx
	movq -3360(%rbp), %rdx
	jnz .Lbb1763
	movq %r15, -3704(%rbp)
	movq $9223372036854775804, %rax
	cmpq %rax, %r15
	jg .Lbb1761
	movq %r8, -3704(%rbp)
	cmpq $0, %r8
	jz .Lbb1759
	movq $-9223372036854775808, %rax
	cmpq %rax, %r10
	setz %al
	movzbq %al, %rax
	andq %r11, %rax
	negq %rax
	andq %rdx, %rax
	xorq %rax, %r8
	movq %r10, %rax
	cqto
	idivq %r8
	cmpq $0, %rdx
	setnz %al
	movzbq %al, %rax
	movq %r8, %r10
	xorq %rdx, %r10
	cmpq $0, %r10
	setl %r10b
	movzbq %r10b, %r10
	andq %r10, %rax
	negq %rax
	andq %r8, %rax
	addq %rdx, %rax
	movq %rax, -3712(%rbp)
	movq %r9, -3704(%rbp)
	movq %rcx, -3704(%rbp)
	movq %rcx, %rdx
	addq %rax, %rdx
	movq %rcx, %r15
	movq %rax, %rcx
	xorq %rdx, %rcx
	movq %r15, %r8
	xorq %rdx, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jl .Lbb1757
	movq %rdx, -3712(%rbp)
	.loc 1 984
	callq myl_f_2419329067823cab5b4e5ac5dd18a6abf1f57f45e753f5fc934292f3085a3717
	movq %r14, %r11
	movq %rax, %r10
	movq -2928(%rbp), %rsi
	movl %r12d, %r14d
	movq -2776(%rbp), %r12
	movq -2768(%rbp), %r15
	movsd -2744(%rbp), %xmm0
	movq -2896(%rbp), %rcx
	movq -2752(%rbp), %rax
	movq -2760(%rbp), %rdi
	movq %r10, -1728(%rbp)
	movl %r14d, -3308(%rbp)
	cmpl $0, %r13d
	jnz .Lbb1731
	movq %r12, %r8
	movl %r14d, %r12d
	movq %r11, %r14
	jmp .Lbb1756
.Lbb1731:
	testl $28, %r14d
	jnz .Lbb1743
	movq -4152(%rbp), %r9
	cmpq $0, %r9
	jnz .Lbb1734
	movl %r14d, %r13d
	jmp .Lbb1742
.Lbb1734:
	movq -16(%r9), %r8
	movq $4611686018427387906, %r13
	andq %r13, %r8
	cmpq $0, %r8
	jnz .Lbb1740
	movq -32(%r9), %r8
	subq $1, %r8
	jnz .Lbb1739
	movq %r11, %r13
	movq -24(%r9), %r11
	cmpq $0, %r11
	jnz .Lbb1738
	.loc 1 984
	leaq -4152(%rbp), %rsi
	movq %r15, %rdi
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %r13, %r11
	movl -3308(%rbp), %r13d
	movq -2928(%rbp), %rsi
	movq -1728(%rbp), %r10
	movsd -2744(%rbp), %xmm0
	movq -2896(%rbp), %rcx
	movq -2752(%rbp), %rax
	movq -2760(%rbp), %rdi
	jmp .Lbb1742
.Lbb1738:
	movq %r13, %r11
.Lbb1739:
	movl %r14d, %r13d
	movq %r8, -32(%r9)
	jmp .Lbb1741
.Lbb1740:
	movl %r14d, %r13d
.Lbb1741:
	movq $0, -4152(%rbp)
.Lbb1742:
	movq %r11, %r14
	movq %r12, %r8
	movl %r13d, %r12d
	movl $0, %r13d
	jmp .Lbb1756
.Lbb1743:
	movl %r14d, %r13d
	movq %r11, %r14
	movq -4152(%rbp), %r11
	cmpq $0, %r11
	jnz .Lbb1746
	movq %r12, %r8
	movl %r13d, %r12d
	jmp .Lbb1755
.Lbb1746:
	movq -16(%r11), %r8
	movq $4611686018427387906, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb1753
	movq -24(%r11), %r8
	movq %r8, %r9
	subq $1, %r9
	jz .Lbb1749
	movq %r12, %r8
	jmp .Lbb1752
.Lbb1749:
	movq -32(%r11), %r8
	cmpq $0, %r8
	jnz .Lbb1751
	.loc 1 984
	leaq -4152(%rbp), %rsi
	movq %r15, %rdi
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movq %r12, %r8
	movl -3308(%rbp), %r12d
	movq -2928(%rbp), %rsi
	movq -1728(%rbp), %r10
	movsd -2744(%rbp), %xmm0
	movq -2896(%rbp), %rcx
	movq -2752(%rbp), %rax
	movq -2760(%rbp), %rdi
	jmp .Lbb1755
.Lbb1751:
	movq %r12, %r8
.Lbb1752:
	movl %r13d, %r12d
	movq %r9, -24(%r11)
	jmp .Lbb1754
.Lbb1753:
	movq %r12, %r8
	movl %r13d, %r12d
.Lbb1754:
	movq $0, -4152(%rbp)
.Lbb1755:
	movl $0, %r13d
.Lbb1756:
	movq %r14, %r11
	movq %r8, %r14
	jmp .Lbb1938
.Lbb1757:
	movq %rax, %rdx
	movq -2896(%rbp), %rcx
	.loc 1 983
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1759:
	movq %r10, %rdx
	.loc 1 979
	movl $0, %ecx
	movl $6, %esi
	callq myl_qbe_fail_division
	ud2
.Lbb1761:
	movq -3096(%rbp), %rdx
	.loc 1 978
	movl $64, %r8d
	movl $3, %ecx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1763:
	movq -2752(%rbp), %rdx
	.loc 1 976
	movl $64, %r8d
	movl $3, %ecx
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1765:
	movq %r9, %rdx
	movq %rbx, %rcx
	.loc 1 973
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1767:
	xchgq %r14, %r8
	xchgq %r11, %r14
	movq %rbx, -3712(%rbp)
	movq %rbx, -3712(%rbp)
	movq $5, -3712(%rbp)
	movq $-3689348814741910323, %rsi
	movq %rsi, -1744(%rbp)
	movq %rax, %rsi
	movq -1736(%rbp), %rax
	mulq -1744(%rbp)
	movq %rsi, %rax
	movq %rdx, %rsi
	shrq $2, %rsi
	xorq %rcx, %rsi
	subq %rcx, %rsi
	imulq $5, %rsi, %rsi
	negq %rsi
	addq %r9, %rsi
	movq %rsi, -1784(%rbp)
	cmpq $0, %rsi
	setnz %sil
	movzbq %sil, %rsi
	movq %rsi, -1752(%rbp)
	andq -1752(%rbp), %rcx
	movq %rcx, -1760(%rbp)
	movq -2896(%rbp), %rcx
	movq -1760(%rbp), %rsi
	negq %rsi
	movq %rsi, -1768(%rbp)
	movq -1768(%rbp), %rsi
	andq $5, %rsi
	movq %rsi, -1776(%rbp)
	movq -1784(%rbp), %rsi
	addq -1776(%rbp), %rsi
	movq %rsi, -1792(%rbp)
	movq -2928(%rbp), %rsi
	movq $0, -3712(%rbp)
	cmpq $0, -1792(%rbp)
	jz .Lbb1774
	movq %rbx, -3712(%rbp)
	cmpq $0, %r11
	jl .Lbb1772
	movq %r8, %r9
	movq $0, -3480(%rbp)
	movq $0, -3472(%rbp)
	movl $0, -3480(%rbp)
	movq %r10, -3472(%rbp)
	leaq -3480(%rbp), %r8
	jmp .Lbb1775
.Lbb1772:
	movq %r9, %rdx
	movq %rbx, %rcx
	.loc 1 942
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1774:
	movq $0, -3496(%rbp)
	movq $0, -3488(%rbp)
	movl $1, -3496(%rbp)
	movq $1, -3488(%rbp)
	.loc 1 938
	movl $7, %esi
	movq myl_f_e61a3d78c65133c7260c43e719d97c46e16bd50c64ee7800536cf14c6407a617_meta@gotpcrel(%rip), %rdi
	callq myl_qbe_error_trace_origin
	movq -2928(%rbp), %rsi
	movq -2776(%rbp), %r9
	movq -2768(%rbp), %r15
	movsd -2744(%rbp), %xmm0
	movq -2896(%rbp), %rcx
	movq -2752(%rbp), %rax
	movq -2760(%rbp), %rdi
	leaq -3496(%rbp), %r8
.Lbb1775:
	movq %r8, -1800(%rbp)
	movl (%r8), %r10d
	cmpq $0, %r10
	setz %r10b
	movzbq %r10b, %r10
	cmpl $0, %r10d
	jnz .Lbb1777
	.loc 1 945
	movq $12884901907, %rsi
	movq myl_f_8e12cac141092888b455b1042ce0f135b93f62d14079f9ac5799b4808829b581_meta@gotpcrel(%rip), %rdi
	callq myl_qbe_error_trace_append
	movq %r14, %r11
	movq -1800(%rbp), %r8
	movq -2928(%rbp), %rsi
	movq -2776(%rbp), %r14
	movq -2768(%rbp), %r15
	movsd -2744(%rbp), %xmm0
	movq -2896(%rbp), %rcx
	movq -2752(%rbp), %rax
	movq -2760(%rbp), %rdi
	movq $0, -3464(%rbp)
	movq $0, -3456(%rbp)
	movl $1, -3464(%rbp)
	movq 8(%r8), %r8
	movq %r8, -3456(%rbp)
	leaq -3464(%rbp), %r8
	jmp .Lbb1781
.Lbb1777:
	movq %r14, %r11
	movq %r9, %r14
	movq $0, -3464(%rbp)
	movq 8(%r8), %r10
	movq %r10, -3464(%rbp)
	movq $3, -3712(%rbp)
	imulq $3, %r10, %r9
	movl $4294967295, %r8d
	movq %r8, -1808(%rbp)
	movq %r10, %r8
	andq -1808(%rbp), %r8
	movq %r8, -1856(%rbp)
	movq %r10, %r8
	shrq $32, %r8
	movq %r8, -1888(%rbp)
	movl $3, %r8d
	imulq -1856(%rbp), %r8
	movq %r8, -1816(%rbp)
	movq -1816(%rbp), %r8
	shrq $32, %r8
	movq %r8, -1832(%rbp)
	movl $3, %r8d
	imulq -1888(%rbp), %r8
	movq %r8, -1824(%rbp)
	movq -1832(%rbp), %r8
	addq -1824(%rbp), %r8
	movq %r8, -1848(%rbp)
	movl $4294967295, %r8d
	movq %r8, -1840(%rbp)
	movq -1848(%rbp), %r8
	andq -1840(%rbp), %r8
	movq %r8, -1872(%rbp)
	movq -1848(%rbp), %r8
	shrq $32, %r8
	movq %r8, -1904(%rbp)
	movl $0, %r8d
	imulq -1856(%rbp), %r8
	movq %r8, -1864(%rbp)
	movq -1872(%rbp), %r8
	addq -1864(%rbp), %r8
	movq %r8, -1880(%rbp)
	movq -1880(%rbp), %r8
	shrq $32, %r8
	movq %r8, -1920(%rbp)
	movl $0, %r8d
	imulq -1888(%rbp), %r8
	movq %r8, -1896(%rbp)
	movq -1904(%rbp), %r8
	addq -1896(%rbp), %r8
	movq %r8, -1912(%rbp)
	movq -1920(%rbp), %r8
	addq -1912(%rbp), %r8
	movq %r8, -1952(%rbp)
	cmpq $0, %r10
	setl %r8b
	movzbq %r8b, %r8
	movq %r8, -1928(%rbp)
	movq -1928(%rbp), %r8
	negq %r8
	movq %r8, -1936(%rbp)
	movq -1936(%rbp), %r8
	andq $3, %r8
	movq %r8, -1944(%rbp)
	movq %r10, %r8
	andq $0, %r8
	movq %r8, -1968(%rbp)
	movq -1952(%rbp), %r8
	subq -1944(%rbp), %r8
	movq %r8, -1960(%rbp)
	movq -1960(%rbp), %r8
	subq -1968(%rbp), %r8
	movq %r8, -1976(%rbp)
	movq %r9, %r8
	sarq $63, %r8
	cmpq -1976(%rbp), %r8
	jnz .Lbb1789
	movq $1, -3712(%rbp)
	movq $9223372036854775806, %r8
	cmpq %r8, %r9
	jg .Lbb1787
	movq $0, -3448(%rbp)
	movq $0, -3440(%rbp)
	movl $0, -3448(%rbp)
	movq %r9, %r8
	addq $1, %r8
	movq %r8, -3440(%rbp)
	leaq -3448(%rbp), %r8
.Lbb1781:
	movl (%r8), %r9d
	cmpq $0, %r9
	setz %r10b
	movzbq %r10b, %r10
	cmpl $0, %r10d
	jnz .Lbb1786
	cmpq $1, %r9
	jnz .Lbb2149
	movq 8(%r8), %r9
	movq %r9, -4112(%rbp)
	movq $7, -3712(%rbp)
	imulq $7, %r9, %r10
	movq %r10, -2056(%rbp)
	movl $4294967295, %r8d
	andq %r9, %r8
	movq %r9, %r10
	shrq $32, %r10
	movq %r10, -2024(%rbp)
	imulq $7, %r8, %r10
	movq %r10, -1984(%rbp)
	movq -1984(%rbp), %r10
	shrq $32, %r10
	movq %r10, -2000(%rbp)
	movl $7, %r10d
	imulq -2024(%rbp), %r10
	movq %r10, -1992(%rbp)
	movq -2000(%rbp), %r10
	addq -1992(%rbp), %r10
	movq %r10, -2016(%rbp)
	movl $4294967295, %r10d
	movq %r10, -2008(%rbp)
	movq -2016(%rbp), %r10
	andq -2008(%rbp), %r10
	movq %r10, -2040(%rbp)
	movq -2016(%rbp), %r10
	shrq $32, %r10
	movq %r10, -2072(%rbp)
	imulq $0, %r8, %r8
	movq %r8, -2032(%rbp)
	movq -2024(%rbp), %r8
	movq -2040(%rbp), %r10
	addq -2032(%rbp), %r10
	movq %r10, -2048(%rbp)
	movq -2048(%rbp), %r10
	shrq $32, %r10
	movq %r10, -2088(%rbp)
	imulq $0, %r8, %r8
	movq %r8, -2064(%rbp)
	movq -2056(%rbp), %r10
	movq -2072(%rbp), %r8
	addq -2064(%rbp), %r8
	movq %r8, -2080(%rbp)
	movq -2088(%rbp), %r8
	addq -2080(%rbp), %r8
	movq %r8, -2120(%rbp)
	cmpq $0, %r9
	setl %r8b
	movzbq %r8b, %r8
	movq %r8, -2096(%rbp)
	movq -2096(%rbp), %r8
	negq %r8
	movq %r8, -2104(%rbp)
	movq -2104(%rbp), %r8
	andq $7, %r8
	movq %r8, -2112(%rbp)
	movq %r9, %r8
	andq $0, %r8
	movq %r8, -2136(%rbp)
	movq -2120(%rbp), %r8
	subq -2112(%rbp), %r8
	movq %r8, -2128(%rbp)
	movq -2128(%rbp), %r8
	subq -2136(%rbp), %r8
	movq %r8, -2144(%rbp)
	movq %r10, %r8
	sarq $63, %r8
	cmpq -2144(%rbp), %r8
	jz .Lbb1938
	movq %r9, %rdx
	.loc 1 962
	movl $64, %r8d
	movl $7, %ecx
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1786:
	movq 8(%r8), %r10
	movq %r10, -4112(%rbp)
	jmp .Lbb1938
.Lbb1787:
	movq %r9, %rdx
	.loc 1 953
	movl $64, %r8d
	movl $1, %ecx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1789:
	movq %r10, %rdx
	.loc 1 951
	movl $64, %r8d
	movl $3, %ecx
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1791:
	movq %rsi, %rcx
	movq %rbx, -3712(%rbp)
	movq $4, -3712(%rbp)
	movq %r9, %rsi
	andq $3, %rsi
	movq %rsi, -2152(%rbp)
	movq -2928(%rbp), %rsi
	movq $0, -3712(%rbp)
	cmpq $0, -2152(%rbp)
	jz .Lbb1797
	movq %rbx, -3712(%rbp)
	cmpq $0, %r8
	jl .Lbb1795
	movq $0, -3512(%rbp)
	movq $0, -3504(%rbp)
	movl $1, -3512(%rbp)
	movq %r10, -3504(%rbp)
	leaq -3512(%rbp), %r8
	jmp .Lbb1798
.Lbb1795:
	movq %r9, %rdx
	movq %rbx, %rcx
	.loc 1 902
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1797:
	movq $0, -3528(%rbp)
	movq $0, -3520(%rbp)
	movl $0, -3528(%rbp)
	leaq -3528(%rbp), %r8
.Lbb1798:
	movl (%r8), %r9d
	cmpq $0, %r9
	jz .Lbb1807
	cmpq $1, %r9
	jnz .Lbb2149
	movq 8(%r8), %r10
	movq %r10, -4112(%rbp)
	movq $3, -3712(%rbp)
	imulq $3, %r10, %r9
	movl $4294967295, %r8d
	movq %r8, -2160(%rbp)
	movq %r10, %r8
	andq -2160(%rbp), %r8
	movq %r8, -2208(%rbp)
	movq %r10, %r8
	shrq $32, %r8
	movq %r8, -2240(%rbp)
	movl $3, %r8d
	imulq -2208(%rbp), %r8
	movq %r8, -2168(%rbp)
	movq -2168(%rbp), %r8
	shrq $32, %r8
	movq %r8, -2184(%rbp)
	movl $3, %r8d
	imulq -2240(%rbp), %r8
	movq %r8, -2176(%rbp)
	movq -2184(%rbp), %r8
	addq -2176(%rbp), %r8
	movq %r8, -2200(%rbp)
	movl $4294967295, %r8d
	movq %r8, -2192(%rbp)
	movq -2200(%rbp), %r8
	andq -2192(%rbp), %r8
	movq %r8, -2224(%rbp)
	movq -2200(%rbp), %r8
	shrq $32, %r8
	movq %r8, -2256(%rbp)
	movl $0, %r8d
	imulq -2208(%rbp), %r8
	movq %r8, -2216(%rbp)
	movq -2224(%rbp), %r8
	addq -2216(%rbp), %r8
	movq %r8, -2232(%rbp)
	movq -2232(%rbp), %r8
	shrq $32, %r8
	movq %r8, -2272(%rbp)
	movl $0, %r8d
	imulq -2240(%rbp), %r8
	movq %r8, -2248(%rbp)
	movq -2256(%rbp), %r8
	addq -2248(%rbp), %r8
	movq %r8, -2264(%rbp)
	movq -2272(%rbp), %r8
	addq -2264(%rbp), %r8
	movq %r8, -2304(%rbp)
	cmpq $0, %r10
	setl %r8b
	movzbq %r8b, %r8
	movq %r8, -2280(%rbp)
	movq -2280(%rbp), %r8
	negq %r8
	movq %r8, -2288(%rbp)
	movq -2288(%rbp), %r8
	andq $3, %r8
	movq %r8, -2296(%rbp)
	movq %r10, %r8
	andq $0, %r8
	movq %r8, -2320(%rbp)
	movq %rsi, %r8
	movq -2304(%rbp), %rsi
	subq -2296(%rbp), %rsi
	movq %rsi, -2312(%rbp)
	movq %r14, %rsi
	movq -2312(%rbp), %r14
	subq -2320(%rbp), %r14
	movq %r14, -2328(%rbp)
	movq %r11, %r14
	movq %r9, %r11
	sarq $63, %r11
	cmpq -2328(%rbp), %r11
	jnz .Lbb1805
	movq $1, -3712(%rbp)
	movq $9223372036854775806, %r10
	cmpq %r10, %r9
	jg .Lbb1803
	movq %r9, %r10
	addq $1, %r10
	jmp .Lbb1809
.Lbb1803:
	movq %r9, %rdx
	.loc 1 910
	movl $64, %r8d
	movl $1, %ecx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1805:
	movq %r10, %rdx
	.loc 1 908
	movl $64, %r8d
	movl $3, %ecx
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1807:
	movq %rsi, %r8
	movq %r14, %rsi
	movq %r11, %r14
	movl $19, %r10d
.Lbb1809:
	movq %r14, %r11
	movq %rsi, %r14
	movq %r8, %rsi
	jmp .Lbb1938
.Lbb1810:
	movq %r11, %r14
	movq -3352(%rbp), %rax
	movq %r9, -3712(%rbp)
	movq %rbx, -3704(%rbp)
	cmpq $0, %r8
	jl .Lbb1814
	movq %r10, -3712(%rbp)
	.loc 1 880
	movq %r10, %rsi
	callq *%rax
	movq %r14, %r11
	movq %rax, %r10
	movq -2928(%rbp), %r8
	movq -2776(%rbp), %r14
	movq -2768(%rbp), %r15
	movsd -2744(%rbp), %xmm0
	movq -2896(%rbp), %rcx
	movq -2752(%rbp), %rax
	movq -2760(%rbp), %rdi
	movq %r8, %rsi
	jmp .Lbb1938
.Lbb1814:
	movq %r9, %rdx
	movq %rbx, %rcx
	.loc 1 879
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1816:
	movq %rsi, %rcx
	movq -2592(%rbp), %rsi
	movq %rbx, -3712(%rbp)
	cmpq $0, %r8
	movq -2928(%rbp), %r8
	jl .Lbb1827
	movq %r8, %r9
	movq -2728(%rbp), %r8
	movq $3, -3712(%rbp)
	cmpq -2736(%rbp), %r8
	jnz .Lbb1825
	movq $7, -3712(%rbp)
	movq $9223372036854775800, %r8
	cmpq %r8, %rsi
	jg .Lbb1823
	movq %rsi, %r10
	addq $7, %r10
	movq %r9, %rsi
	jmp .Lbb1938
.Lbb1823:
	movq %rsi, %rdx
	.loc 1 868
	movl $64, %r8d
	movl $7, %ecx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1825:
	movq %r10, %rdx
	.loc 1 866
	movl $64, %r8d
	movl $3, %ecx
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1827:
	movq %r9, %rdx
	movq %rbx, %rcx
	.loc 1 861
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1829:
	movq -3904(%rbp), %rcx
	movq (%rcx), %rdi
	cmpq %rdi, %r11
	setb %dil
	movzbq %dil, %rdi
	cmpl $0, %edi
	jnz .Lbb1844
	movq $0, -3712(%rbp)
	cmpq $0, %r11
	jl .Lbb1832
	movq %r11, -2400(%rbp)
	jmp .Lbb1836
.Lbb1832:
	movq (%rcx), %rdi
	movq %rdi, -2360(%rbp)
	movq $9223372036854775807, %rdi
	movq %rdi, -2336(%rbp)
	movq -2360(%rbp), %rdi
	cmpq -2336(%rbp), %rdi
	ja .Lbb1842
	movq %r11, -3712(%rbp)
	movq -2360(%rbp), %rdi
	addq %r11, %rdi
	movq %rdi, -2376(%rbp)
	movq -2360(%rbp), %rdi
	xorq -2376(%rbp), %rdi
	movq %rdi, -2352(%rbp)
	movq %r11, %rdi
	xorq -2376(%rbp), %rdi
	movq %rdi, -2344(%rbp)
	movq -2352(%rbp), %rdi
	andq -2344(%rbp), %rdi
	movq %rdi, -2368(%rbp)
	movq -2360(%rbp), %rdi
	cmpq $0, -2368(%rbp)
	jl .Lbb1840
	movq -2376(%rbp), %rdi
	movq %rdi, -2400(%rbp)
.Lbb1836:
	movq (%rcx), %rdi
	movq %rdi, -2384(%rbp)
	movq -2400(%rbp), %rdi
	cmpq -2384(%rbp), %rdi
	movq -2384(%rbp), %rdi
	jae .Lbb1838
	movq 32(%rcx), %rcx
	movq %rcx, -2392(%rbp)
	movq -2760(%rbp), %rdi
	movl $24, %ecx
	imulq -2400(%rbp), %rcx
	movq %rcx, -2408(%rbp)
	movq -2392(%rbp), %rcx
	addq -2408(%rbp), %rcx
	jmp .Lbb1845
.Lbb1838:
	movq %rdi, %rdx
	movq -2400(%rbp), %rbx
	movq -2760(%rbp), %rdi
	.loc 1 789
	movq %rbx, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1840:
	movq %r11, %rdx
	movq %rdi, %rsi
	movq -2760(%rbp), %rdi
	.loc 1 786
	movl $64, %r8d
	movq %rdx, %rcx
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1842:
	movq -2360(%rbp), %rsi
	movq -2760(%rbp), %rdi
	.loc 1 784
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb1844:
	movq 32(%rcx), %rcx
	movq %rcx, -2416(%rbp)
	movq -2760(%rbp), %rdi
	imulq $24, %r11, %rcx
	movq %rcx, -2424(%rbp)
	movq -2416(%rbp), %rcx
	addq -2424(%rbp), %rcx
.Lbb1845:
	movq %rcx, -2432(%rbp)
	movq 0(%rcx), %rcx
	movq %rcx, -3880(%rbp)
	movq -2432(%rbp), %rcx
	movq 8(%rcx), %rcx
	movq %rcx, -3872(%rbp)
	movq -2432(%rbp), %rcx
	movq 16(%rcx), %rcx
	movq %rcx, -3864(%rbp)
	movq -2456(%rbp), %rcx
	movq %rbx, -3712(%rbp)
	cmpq $0, %r8
	jl .Lbb1869
	movq -3880(%rbp), %r8
	movq %r8, -3856(%rbp)
	movq -3872(%rbp), %r8
	movq %r8, -3848(%rbp)
	movq -3864(%rbp), %r8
	movq %r8, -3840(%rbp)
	movq -3880(%rbp), %r8
	movq %r8, -3856(%rbp)
	movq -3872(%rbp), %r8
	movq %r8, -3848(%rbp)
	movq -3864(%rbp), %r8
	movq %r8, -3840(%rbp)
	movq %r10, -3712(%rbp)
	movq -3856(%rbp), %r8
	movq %r8, -3624(%rbp)
	movq -3848(%rbp), %r8
	movq %r8, -3616(%rbp)
	movq -3840(%rbp), %r8
	movq %r8, -3608(%rbp)
	movq %r10, -3624(%rbp)
	movq -3624(%rbp), %r8
	movq %r8, -3880(%rbp)
	movq -3616(%rbp), %r8
	movq %r8, -3872(%rbp)
	movq -3608(%rbp), %r8
	movq %r8, -3864(%rbp)
	movq $17, -3712(%rbp)
	movq -3880(%rbp), %r8
	movq %r8, -3832(%rbp)
	movq -3872(%rbp), %r8
	movq %r8, -3824(%rbp)
	movq -3864(%rbp), %r8
	movq %r8, -3816(%rbp)
	movq -3880(%rbp), %r8
	movq %r8, -3832(%rbp)
	movq -3872(%rbp), %r8
	movq %r8, -3824(%rbp)
	movq -3864(%rbp), %r8
	movq %r8, -3816(%rbp)
	movq %rax, -3712(%rbp)
	movq -3832(%rbp), %r8
	movq %r8, -3600(%rbp)
	movq -3824(%rbp), %r8
	movq %r8, -3592(%rbp)
	movq -3816(%rbp), %r8
	movq %r8, -3584(%rbp)
	movq %rax, -3592(%rbp)
	movq -3600(%rbp), %r8
	movq %r8, -3880(%rbp)
	movq -3592(%rbp), %r8
	movq %r8, -3872(%rbp)
	movq -3584(%rbp), %r8
	movq %r8, -3864(%rbp)
	movq -2440(%rbp), %r8
	movq $3, -3712(%rbp)
	cmpq -2448(%rbp), %r8
	movq -2464(%rbp), %r8
	jnz .Lbb1867
	movq %r8, %r9
	movq -2472(%rbp), %r8
	movq %rbx, -3712(%rbp)
	cmpq $0, %r8
	jl .Lbb1865
	movq $101, -3712(%rbp)
	movq -3880(%rbp), %r8
	movq %r8, -3808(%rbp)
	movq -3872(%rbp), %r8
	movq %r8, -3800(%rbp)
	movq -3864(%rbp), %r8
	movq %r8, -3792(%rbp)
	movq -3880(%rbp), %r8
	movq %r8, -3808(%rbp)
	movq -3872(%rbp), %r8
	movq %r8, -3800(%rbp)
	movq -3864(%rbp), %r8
	movq %r8, -3792(%rbp)
	movq %rsi, -3712(%rbp)
	movq -3808(%rbp), %r8
	movq %r8, -3576(%rbp)
	movq -3800(%rbp), %r8
	movq %r8, -3568(%rbp)
	movq -3792(%rbp), %r8
	movq %r8, -3560(%rbp)
	movq %rsi, -3560(%rbp)
	movq -3576(%rbp), %r8
	movq %r8, -3880(%rbp)
	movq -3568(%rbp), %r8
	movq %r8, -3872(%rbp)
	movq -3560(%rbp), %r8
	movq %r8, -3864(%rbp)
	movq -3880(%rbp), %r8
	movq %r8, -3552(%rbp)
	movq -3872(%rbp), %r8
	movq %r8, -3544(%rbp)
	movq -3864(%rbp), %r8
	movq %r8, -3536(%rbp)
	movq -3552(%rbp), %r8
	movq %r8, -3736(%rbp)
	movq -3544(%rbp), %r8
	movq %r8, -3728(%rbp)
	movq -3536(%rbp), %r8
	movq %r8, -3720(%rbp)
	leaq -3736(%rbp), %r8
	movq %r8, -3712(%rbp)
	movq -2488(%rbp), %r8
	movq %rax, -3712(%rbp)
	movq $3, -3704(%rbp)
	cmpq -2496(%rbp), %r8
	movq -2512(%rbp), %r8
	jnz .Lbb1863
	movq -2752(%rbp), %rax
	movq %rcx, -3712(%rbp)
	movq -2896(%rbp), %rcx
	cmpq $0, -2520(%rbp)
	jl .Lbb1861
	movq %r8, %r10
	movq %rax, %r8
	leaq -3736(%rbp), %rax
	movq %rax, -3712(%rbp)
	movq %r10, %rax
	movq -2528(%rbp), %r10
	movq %rsi, -3712(%rbp)
	movq $5, -3704(%rbp)
	cmpq -2536(%rbp), %r10
	movq %r9, %r10
	movq -2928(%rbp), %r9
	jnz .Lbb1859
	movq %r9, %rsi
	movq -2544(%rbp), %r9
	movq %r10, -3712(%rbp)
	cmpq $0, %r9
	jl .Lbb1857
	movq %rax, %r10
	movq %r8, %rax
	jmp .Lbb1938
.Lbb1857:
	movq -2464(%rbp), %rcx
	movq -2504(%rbp), %rdx
	.loc 1 851
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1859:
	movq %rsi, %rdx
	.loc 1 850
	movl $64, %r8d
	movl $5, %ecx
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1861:
	movq -2456(%rbp), %rcx
	movq %r10, %rdx
	.loc 1 846
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1863:
	movq %rax, %rdx
	.loc 1 845
	movl $64, %r8d
	movl $3, %ecx
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1865:
	movq -2480(%rbp), %rdx
	movq %rbx, %rcx
	.loc 1 823
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1867:
	movq %r9, %rdx
	.loc 1 821
	movl $64, %r8d
	movl $3, %ecx
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1869:
	movq %r9, %rdx
	movq %rbx, %rcx
	.loc 1 793
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1871:
	movq %r8, %rcx
	movq -1320(%rbp), %r8
	movq %rbx, -3712(%rbp)
	cmpq $0, %rcx
	movq -2440(%rbp), %rcx
	jl .Lbb1895
	movq %r9, -3712(%rbp)
	movq $17, -3704(%rbp)
	movq %rax, -3712(%rbp)
	movq %r9, -3704(%rbp)
	cmpq -2448(%rbp), %rcx
	movq -2456(%rbp), %rcx
	jnz .Lbb1893
	movq -2480(%rbp), %r9
	movq %r9, -3704(%rbp)
	movq -2464(%rbp), %r9
	cmpq $0, -2472(%rbp)
	jl .Lbb1891
	movq %r8, -3704(%rbp)
	movq %rsi, -3704(%rbp)
	movq %r10, -3672(%rbp)
	movq %rax, -3664(%rbp)
	movq %rsi, -3656(%rbp)
	movq -3672(%rbp), %r8
	movq %r8, -3880(%rbp)
	movq -3664(%rbp), %r8
	movq %r8, -3872(%rbp)
	movq -3656(%rbp), %r8
	movq %r8, -3864(%rbp)
	movq -3880(%rbp), %r8
	movq %r8, -3648(%rbp)
	movq -3872(%rbp), %r8
	movq %r8, -3640(%rbp)
	movq -3864(%rbp), %r8
	movq %r8, -3632(%rbp)
	movq -3648(%rbp), %r8
	movq %r8, -3760(%rbp)
	movq -3640(%rbp), %r8
	movq %r8, -3752(%rbp)
	movq -3632(%rbp), %r8
	movq %r8, -3744(%rbp)
	leaq -3760(%rbp), %r8
	movq %r8, -3712(%rbp)
	movq -2488(%rbp), %r8
	movq %rax, -3712(%rbp)
	movq $3, -3704(%rbp)
	cmpq -2496(%rbp), %r8
	movq -2504(%rbp), %r8
	jnz .Lbb1889
	movq -2512(%rbp), %rax
	movq %rcx, -3712(%rbp)
	cmpq $0, -2520(%rbp)
	jl .Lbb1887
	movq %rax, %r10
	movq -2752(%rbp), %rax
	leaq -3760(%rbp), %rcx
	movq %rcx, -3712(%rbp)
	movq -2528(%rbp), %rcx
	movq %rsi, -3712(%rbp)
	movq $5, -3704(%rbp)
	cmpq -2536(%rbp), %rcx
	movq -2896(%rbp), %rcx
	jnz .Lbb1885
	movq -2928(%rbp), %rsi
	movq %r9, -3712(%rbp)
	cmpq $0, -2544(%rbp)
	jge .Lbb1938
	movq %r9, %rcx
	movq %r8, %rdx
	.loc 1 767
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1885:
	movq %rsi, %rdx
	.loc 1 766
	movl $64, %r8d
	movl $5, %ecx
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1887:
	movq %r10, %rdx
	.loc 1 762
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1889:
	movq %rax, %rdx
	.loc 1 761
	movl $64, %r8d
	movl $3, %ecx
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1891:
	movq -2480(%rbp), %rdx
	movq %rbx, %rcx
	.loc 1 748
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1893:
	movq %r9, %rdx
	.loc 1 746
	movl $64, %r8d
	movl $3, %ecx
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1895:
	movq %r9, %rdx
	movq %rbx, %rcx
	.loc 1 740
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1897:
	movq -3928(%rbp), %rcx
	movq $0, -3712(%rbp)
	cmpq $0, %r11
	jl .Lbb1899
	movq %r11, %rax
	jmp .Lbb1901
.Lbb1899:
	movq (%rcx), %rsi
	movq $9223372036854775807, %rax
	cmpq %rax, %rsi
	ja .Lbb1931
	movq %r11, -3712(%rbp)
	movq %rsi, %rax
	addq %r11, %rax
	movq %rax, -2568(%rbp)
	movq %rsi, %rax
	xorq -2568(%rbp), %rax
	movq %rax, -2560(%rbp)
	movq %r11, %rax
	xorq -2568(%rbp), %rax
	movq %rax, -2552(%rbp)
	movq -2560(%rbp), %rax
	andq -2552(%rbp), %rax
	movq %rax, -2576(%rbp)
	movq -2568(%rbp), %rax
	cmpq $0, -2576(%rbp)
	jl .Lbb1929
.Lbb1901:
	movq (%rcx), %rsi
	cmpq %rsi, %rax
	jae .Lbb1927
	movq 32(%rcx), %rcx
	movzbq (%rcx, %rax, 1), %rax
	movq %rax, -2600(%rbp)
	movq -2592(%rbp), %rsi
	movq -2584(%rbp), %rcx
	movq -2752(%rbp), %rax
	cmpl $0, -2600(%rbp)
	jnz .Lbb1914
	movq -2608(%rbp), %rsi
	movq %rbx, -3712(%rbp)
	cmpq $0, %r8
	jl .Lbb1912
	movq $5, -3712(%rbp)
	imulq $5, %r10, %r9
	imulq $5, %rcx, %rcx
	movq %rcx, -2616(%rbp)
	movq -2784(%rbp), %rcx
	movq -2616(%rbp), %r8
	shrq $32, %r8
	movq %r8, -2632(%rbp)
	imulq $5, %rsi, %rsi
	movq %rsi, -2624(%rbp)
	movq -2800(%rbp), %rsi
	movq -2632(%rbp), %r8
	addq -2624(%rbp), %r8
	movq %r8, -2648(%rbp)
	movl $4294967295, %r8d
	movq %r8, -2640(%rbp)
	movq -2648(%rbp), %r8
	andq -2640(%rbp), %r8
	movq %r8, -2656(%rbp)
	movq -2648(%rbp), %r8
	shrq $32, %r8
	movq %r8, -2672(%rbp)
	addq -2656(%rbp), %rcx
	movq %rcx, -2664(%rbp)
	movq -2848(%rbp), %rcx
	movq -2664(%rbp), %r8
	shrq $32, %r8
	movq %r8, -2688(%rbp)
	addq -2672(%rbp), %rsi
	movq %rsi, -2680(%rbp)
	movq -2872(%rbp), %rsi
	movq -2688(%rbp), %r8
	addq -2680(%rbp), %r8
	movq %r8, -2704(%rbp)
	andq $5, %rcx
	movq %rcx, -2696(%rbp)
	movq -2896(%rbp), %rcx
	movq %r14, %r8
	movq -2704(%rbp), %r14
	subq -2696(%rbp), %r14
	movq %r14, -2712(%rbp)
	negq %rsi
	addq -2712(%rbp), %rsi
	movq %rsi, -2720(%rbp)
	movq -2928(%rbp), %rsi
	movq %r11, %r14
	movq %r9, %r11
	sarq $63, %r11
	cmpq -2720(%rbp), %r11
	jnz .Lbb1910
	movq $7, -3712(%rbp)
	movq $9223372036854775800, %r10
	cmpq %r10, %r9
	jg .Lbb1908
	movq %r9, %r10
	addq $7, %r10
	jmp .Lbb1920
.Lbb1908:
	movq %r9, %rdx
	.loc 1 731
	movl $64, %r8d
	movl $7, %ecx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1910:
	movq %r10, %rdx
	.loc 1 729
	movl $64, %r8d
	movl $5, %ecx
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1912:
	movq %r9, %rdx
	movq %rbx, %rcx
	.loc 1 727
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1914:
	xchgq %r14, %r8
	xchgq %r11, %r14
	xchgq %rsi, %r11
	movq -2896(%rbp), %rcx
	movq %rbx, -3712(%rbp)
	cmpq $0, %rsi
	movq -2928(%rbp), %rsi
	jl .Lbb1925
	movq %r11, %r9
	movq -2728(%rbp), %r11
	movq $3, -3712(%rbp)
	cmpq -2736(%rbp), %r11
	jnz .Lbb1923
	movq $1, -3712(%rbp)
	movq $9223372036854775806, %r10
	cmpq %r10, %r9
	jg .Lbb1921
	movq %r9, %r10
	addq $1, %r10
.Lbb1920:
	movq %r14, %r11
	movq %r8, %r14
	jmp .Lbb1938
.Lbb1921:
	movq %r9, %rdx
	.loc 1 722
	movl $64, %r8d
	movl $1, %ecx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1923:
	movq %r10, %rdx
	.loc 1 720
	movl $64, %r8d
	movl $3, %ecx
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1925:
	movq %r9, %rdx
	movq %rbx, %rcx
	.loc 1 718
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1927:
	movq %rsi, %rdx
	.loc 1 714
	movq %rax, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	ud2
.Lbb1929:
	movq %r11, %rdx
	.loc 1 711
	movl $64, %r8d
	movq %rdx, %rcx
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1931:
	.loc 1 709
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb1932:
	movq %r11, %r14
	movq %rax, %rcx
	cvtsi2sd %r9, %xmm1
	movq %xmm1, %rax
	movq $4620693217682128896, %rdx
	movq %rdx, -3712(%rbp)
	movsd %xmm0, %xmm1
	movq %rax, %xmm0
	movsd %xmm0, %xmm2
	divsd ".Lfp5"(%rip), %xmm2
	movq %xmm2, %rax
	movq $4616189618054758400, %rdx
	movq %rdx, -3712(%rbp)
	movq %rcx, -3712(%rbp)
	movq %rax, %xmm2
	addsd %xmm2, %xmm1
	movq %xmm1, %rcx
	movq $4625196817309499392, %rax
	movq %rax, -3712(%rbp)
	divsd ".Lfp4"(%rip), %xmm0
	movq %xmm0, %rax
	movq $4607182418800017408, %rdx
	movq %rdx, -3712(%rbp)
	movq %rax, %xmm0
	addsd ".Lfp3"(%rip), %xmm0
	movq %xmm0, %rax
	movq %rax, -3712(%rbp)
	movq %rcx, %xmm0
	movq %rax, %xmm1
	mulsd %xmm1, %xmm0
	movq %xmm0, %rax
	movq $4602678819172646912, %rcx
	movq %rcx, -3712(%rbp)
	movq %rax, %xmm0
	addsd ".Lfp2"(%rip), %xmm0
	movq %xmm0, %rax
	movq $4638707616191610880, %rcx
	movq %rcx, -3712(%rbp)
	movq %rax, %xmm0
	mulsd ".Lfp1"(%rip), %xmm0
	movq %xmm0, %rdx
	.loc 1 687
	movl $11, %esi
	callq myl_qbe_float_unary
	movq %r14, %r11
	movq %rax, %r10
	movq -2928(%rbp), %rsi
	movq -2776(%rbp), %r14
	movq -2768(%rbp), %r15
	movsd -2744(%rbp), %xmm0
	movq -2896(%rbp), %rcx
	movq -2752(%rbp), %rax
	movq -2760(%rbp), %rdi
	jmp .Lbb1938
.Lbb1934:
	movq %rbx, -3712(%rbp)
	cmpq $0, %r8
	jl .Lbb1951
	movq $17, -3712(%rbp)
	imulq $17, %r10, %r9
	imulq $17, %rcx, %rcx
	movq %rcx, -2792(%rbp)
	movq -2784(%rbp), %rcx
	movq -2792(%rbp), %r8
	shrq $32, %r8
	movq %r8, -2816(%rbp)
	imulq $17, %rsi, %rsi
	movq %rsi, -2808(%rbp)
	movq -2800(%rbp), %rsi
	movq -2816(%rbp), %r8
	addq -2808(%rbp), %r8
	movq %r8, -2832(%rbp)
	movl $4294967295, %r8d
	movq %r8, -2824(%rbp)
	movq -2832(%rbp), %r8
	andq -2824(%rbp), %r8
	movq %r8, -2840(%rbp)
	movq -2832(%rbp), %r8
	shrq $32, %r8
	movq %r8, -2864(%rbp)
	addq -2840(%rbp), %rcx
	movq %rcx, -2856(%rbp)
	movq -2848(%rbp), %rcx
	movq -2856(%rbp), %r8
	shrq $32, %r8
	movq %r8, -2888(%rbp)
	addq -2864(%rbp), %rsi
	movq %rsi, -2880(%rbp)
	movq -2872(%rbp), %rsi
	movq -2888(%rbp), %r8
	addq -2880(%rbp), %r8
	movq %r8, -2912(%rbp)
	andq $17, %rcx
	movq %rcx, -2904(%rbp)
	movq -2896(%rbp), %rcx
	movq -2912(%rbp), %r8
	subq -2904(%rbp), %r8
	movq %r8, -2920(%rbp)
	negq %rsi
	addq -2920(%rbp), %rsi
	movq %rsi, -2936(%rbp)
	movq -2928(%rbp), %rsi
	movq %r9, %r8
	sarq $63, %r8
	cmpq -2936(%rbp), %r8
	jnz .Lbb1949
	movq $23, -3712(%rbp)
	movq $9223372036854775784, %r8
	cmpq %r8, %r9
	jg .Lbb1947
	movq $7, -3712(%rbp)
	movq %r9, %r10
	addq $23, %r10
	movq %r10, %r9
	sarq $63, %r9
	movq %r9, %r8
	xorq %r10, %r8
	movq %r8, -2944(%rbp)
	movq -2944(%rbp), %r8
	subq %r9, %r8
	movq %r8, -2960(%rbp)
	movq $2635249153387078803, %r8
	movq %r8, -2952(%rbp)
	movq %rax, %r8
	movq -2960(%rbp), %rax
	mulq -2952(%rbp)
	movq %r8, %rax
	movq %rdx, -2984(%rbp)
	movq -2960(%rbp), %r8
	subq -2984(%rbp), %r8
	movq %r8, -2968(%rbp)
	movq -2968(%rbp), %r8
	shrq $1, %r8
	movq %r8, -2976(%rbp)
	movq -2984(%rbp), %r8
	addq -2976(%rbp), %r8
	movq %r8, -2992(%rbp)
	movq -2992(%rbp), %r8
	shrq $2, %r8
	movq %r8, -3000(%rbp)
	movq %r9, %r8
	xorq -3000(%rbp), %r8
	movq %r8, -3008(%rbp)
	movq -3008(%rbp), %r8
	subq %r9, %r8
	movq %r8, -3016(%rbp)
	movl $7, %r8d
	imulq -3016(%rbp), %r8
	movq %r8, -3024(%rbp)
	movq -3016(%rbp), %r8
	subq -3024(%rbp), %r10
	cmpq $0, %r10
	setnz %r10b
	movzbq %r10b, %r10
	andq %r10, %r9
	subq %r9, %r8
	movq $1009, -3712(%rbp)
	movq %r8, %r9
	sarq $63, %r9
	movq %r8, %r10
	xorq %r9, %r10
	movq %r10, -3032(%rbp)
	movq -3032(%rbp), %r10
	subq %r9, %r10
	movq %r10, -3040(%rbp)
	movq $-9086255505087856445, %r10
	movq %r10, -3048(%rbp)
	movq %rax, %r10
	movq -3040(%rbp), %rax
	mulq -3048(%rbp)
	movq %r10, %rax
	movq %rdx, %r10
	shrq $9, %r10
	xorq %r9, %r10
	subq %r9, %r10
	imulq $1009, %r10, %r10
	subq %r10, %r8
	cmpq $0, %r8
	setnz %r10b
	movzbq %r10b, %r10
	andq %r10, %r9
	negq %r9
	andq $1009, %r9
	movq %r8, %r10
	addq %r9, %r10
.Lbb1938:
	movq %r10, -3712(%rbp)
	movq %rsi, %r9
	addq %r10, %rsi
	movq %r9, %r8
	xorq %rsi, %r8
	movq %r8, -3064(%rbp)
	movq %r10, %r8
	xorq %rsi, %r8
	movq %r8, -3056(%rbp)
	movq -3064(%rbp), %r8
	andq -3056(%rbp), %r8
	movq %r8, -3080(%rbp)
	movq -3072(%rbp), %r8
	cmpq $0, -3080(%rbp)
	jl .Lbb1945
	movq -3088(%rbp), %r9
	movq $1, -3712(%rbp)
	movq $9223372036854775806, %r10
	movq %r10, -3104(%rbp)
	movq -3096(%rbp), %r10
	cmpq -3104(%rbp), %r11
	jg .Lbb1943
	addq $1, %r11
	movq %rsi, -2928(%rbp)
	jmp .Lbb1469
.Lbb1943:
	movq %r11, %rdx
	.loc 1 1034
	movl $64, %r8d
	movl $1, %ecx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1945:
	movq %r10, %rcx
	movq %r9, %rsi
	.loc 1 1030
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1947:
	movq %r9, %rdx
	.loc 1 586
	movl $64, %r8d
	movl $23, %ecx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1949:
	movq %r10, %rdx
	.loc 1 584
	movl $64, %r8d
	movl $17, %ecx
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1951:
	movq %r9, %rdx
	movq %rbx, %rcx
	.loc 1 582
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1953:
	movq -3072(%rbp), %r8
	movq -3096(%rbp), %r10
	movq -2928(%rbp), %r11
	movq -3112(%rbp), %rcx
	movq -2896(%rbp), %rsi
	movq -3088(%rbp), %r9
	movq %r11, -3712(%rbp)
	movq -3160(%rbp), %rbx
	addq %r11, %rbx
	movq %rbx, -3232(%rbp)
	movq -3160(%rbp), %rbx
	xorq -3232(%rbp), %rbx
	movq %rbx, -3136(%rbp)
	movq %r11, %rbx
	xorq -3232(%rbp), %rbx
	movq %rbx, -3128(%rbp)
	movq -3136(%rbp), %rbx
	andq -3128(%rbp), %rbx
	movq %rbx, -3152(%rbp)
	movq -3144(%rbp), %rbx
	cmpq $0, -3152(%rbp)
	jl .Lbb1960
	movq $1000000007, -3712(%rbp)
	movq $1, -3712(%rbp)
	movq $9223372036854775806, %r11
	movq %r11, -3168(%rbp)
	movq -3296(%rbp), %r11
	cmpq -3168(%rbp), %r11
	jg .Lbb1958
	movq -3232(%rbp), %r11
	sarq $63, %r11
	movq %r11, -3256(%rbp)
	movq -3256(%rbp), %r11
	xorq -3232(%rbp), %r11
	movq %r11, -3176(%rbp)
	movq -3176(%rbp), %r11
	subq -3256(%rbp), %r11
	movq %r11, -3184(%rbp)
	movq $-8543223828751151131, %r11
	movq %r11, -3192(%rbp)
	movq %rax, %r11
	movq -3184(%rbp), %rax
	mulq -3192(%rbp)
	movq %r11, %rax
	movq %rdx, -3200(%rbp)
	movq -3200(%rbp), %r11
	shrq $29, %r11
	movq %r11, -3208(%rbp)
	movq -3256(%rbp), %r11
	xorq -3208(%rbp), %r11
	movq %r11, -3216(%rbp)
	movq -3216(%rbp), %r11
	subq -3256(%rbp), %r11
	movq %r11, -3224(%rbp)
	movl $1000000007, %r11d
	imulq -3224(%rbp), %r11
	movq %r11, -3240(%rbp)
	movq -3232(%rbp), %r11
	subq -3240(%rbp), %r11
	movq %r11, -3288(%rbp)
	cmpq $0, %r11
	setnz %r11b
	movzbq %r11b, %r11
	movq %r11, -3248(%rbp)
	movq -3256(%rbp), %r11
	andq -3248(%rbp), %r11
	movq %r11, -3264(%rbp)
	movq -3264(%rbp), %r11
	negq %r11
	movq %r11, -3272(%rbp)
	movq -3272(%rbp), %r11
	andq $1000000007, %r11
	movq %r11, -3280(%rbp)
	movq -3288(%rbp), %r11
	addq -3280(%rbp), %r11
	movq %r11, -3336(%rbp)
	movq -3296(%rbp), %r11
	addq $1, %r11
	movq %r11, -3328(%rbp)
	movq -3304(%rbp), %r11
	movq -3344(%rbp), %rcx
	movsd -3336(%rbp), %xmm15
	movsd %xmm15, -3160(%rbp)
	movq -3328(%rbp), %r11
	jmp .Lbb1466
.Lbb1958:
	movq -3296(%rbp), %rdx
	.loc 1 1045
	movl $64, %r8d
	movl $1, %ecx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1960:
	movq %r11, %rcx
	movq -3160(%rbp), %r13
	.loc 1 1039
	movl $64, %r8d
	movq %r13, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb1962:
	movq -3160(%rbp), %r13
	movl -3388(%rbp), %r14d
	movq %r15, %rbx
	movl -3312(%rbp), %r15d
	movq -3320(%rbp), %rsi
	.loc 1 1049
	movq %rdi, %r12
	callq myl_f_8a5a050356fb7a5094326f2b8ccffa083f61d461495e1103718ebd5cfb6ac591
	movq %r12, %rdi
	movq %rax, %rdx
	movl -3392(%rbp), %r12d
	movq -3376(%rbp), %rcx
	movq -3400(%rbp), %rsi
	movq %rcx, -3712(%rbp)
	movq %rdx, %rax
	subq %rcx, %rax
	movq %rax, -3384(%rbp)
	movq %rcx, %r8
	xorq %rdx, %r8
	movq %rdx, %r9
	xorq %rax, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jl .Lbb2142
	movq %rsi, %rdx
	movq -3944(%rbp), %rsi
	cmpq $0, %rsi
	jnz .Lbb1967
	movq %r13, %r11
	jmp .Lbb1974
.Lbb1967:
	movq -16(%rsi), %rcx
	movq $4611686018427387906, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jnz .Lbb1972
	movq -32(%rsi), %rcx
	subq $1, %rcx
	jnz .Lbb1971
	movq -24(%rsi), %r8
	cmpq $0, %r8
	jnz .Lbb1971
	.loc 1 1052
	leaq -3944(%rbp), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %r13, %r11
	movq %r12, %rdi
	movq -3384(%rbp), %rax
	movl -3392(%rbp), %r12d
	movq -3400(%rbp), %rdx
	jmp .Lbb1974
.Lbb1971:
	movq %r13, %r11
	movq %rcx, -32(%rsi)
	jmp .Lbb1973
.Lbb1972:
	movq %r13, %r11
.Lbb1973:
	movq $0, -3944(%rbp)
.Lbb1974:
	movq %r11, -3712(%rbp)
	movq %rax, -3704(%rbp)
	.loc 1 1056
	movq %rdx, %rsi
	movq %rdi, %r13
	callq myl_qbe_stream_begin
	movq %r13, %rdi
	movq %rax, %rsi
	movq %rsi, -3408(%rbp)
	.loc 1 1056
	movl $0, %edx
	movq %rsi, %rax
	leaq -3712(%rbp), %rsi
	movq %rdi, %r13
	movq %rax, %rdi
	callq myl_r_1a91deb3742283487d66c3b500f6effd7ef1170e6d4b4368fe9ec3c3f0354fda
	movq %r13, %rdi
	movq -3408(%rbp), %rsi
	.loc 1 1056
	movq %rsi, %rax
	movl $32, %esi
	movq %rdi, %r13
	movq %rax, %rdi
	callq myl_qbe_print_byte
	movq %r13, %rdi
	movq -3408(%rbp), %rsi
	.loc 1 1056
	movl $0, %edx
	movq %rsi, %rax
	leaq -3704(%rbp), %rsi
	movq %rdi, %r13
	movq %rax, %rdi
	callq myl_r_1a91deb3742283487d66c3b500f6effd7ef1170e6d4b4368fe9ec3c3f0354fda
	movq %r13, %rdi
	movq -3408(%rbp), %rsi
	.loc 1 1056
	movq %rsi, %rax
	movl $10, %esi
	movq %rdi, %r13
	movq %rax, %rdi
	callq myl_qbe_print_byte
	movq %r13, %rdi
	movq -3408(%rbp), %rsi
	movq -3400(%rbp), %rdx
	.loc 1 1056
	movq %rdi, %r13
	callq myl_qbe_stream_finish
	movq %r13, %rdi
	movl -3412(%rbp), %r13d
	movl -4048(%rbp), %eax
	movl -4016(%rbp), %ecx
	orl %ecx, %eax
	jz .Lbb1976
	leaq -4072(%rbp), %rax
	movq %rax, -4008(%rbp)
	leaq -4040(%rbp), %rax
	movq %rax, -4000(%rbp)
	.loc 1 1059
	movl $2, %edx
	leaq -4008(%rbp), %rsi
	movq %rdi, %r13
	callq myl_qbe_rc_scopes_close
	movq %r13, %rdi
	movl -3412(%rbp), %r13d
.Lbb1976:
	.loc 1 1059
	callq myl_qbe_exit_skip
	movl %r13d, %edx
	movq %rbx, %rdi
	movl %eax, %ecx
	movl -3424(%rbp), %eax
	movl %edx, %r13d
	movl -3420(%rbp), %edx
	movl -3416(%rbp), %ebx
	cmpl $0, %ecx
	jnz .Lbb2141
	movq -3888(%rbp), %rsi
	cmpq $0, %rsi
	jnz .Lbb1979
	xchgl %edx, %r13d
	jmp .Lbb1988
.Lbb1979:
	movq -16(%rsi), %rcx
	movq $4611686018427387906, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jnz .Lbb1986
	movq -32(%rsi), %rcx
	subq $1, %rcx
	jz .Lbb1982
	xchgl %edx, %r13d
	jmp .Lbb1985
.Lbb1982:
	movq -24(%rsi), %r8
	cmpq $0, %r8
	jnz .Lbb1984
	.loc 1 1059
	leaq -3888(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_drop
	movl %r13d, %edx
	movq %rbx, %rdi
	movl -3424(%rbp), %eax
	movl -3420(%rbp), %r13d
	movl -3416(%rbp), %ebx
	jmp .Lbb1988
.Lbb1984:
	xchgl %edx, %r13d
.Lbb1985:
	movq %rcx, -32(%rsi)
	jmp .Lbb1987
.Lbb1986:
	xchgl %edx, %r13d
.Lbb1987:
	movq $0, -3888(%rbp)
.Lbb1988:
	movl -4160(%rbp), %ecx
	cmpl $0, %ecx
	jz .Lbb2006
	movl $0, -4160(%rbp)
	testl $28, %r15d
	jnz .Lbb1998
	movq -3896(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb2006
	movq -16(%rsi), %rcx
	movq $4611686018427387906, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jnz .Lbb1997
	movq -32(%rsi), %rcx
	subq $1, %rcx
	jnz .Lbb1996
	movl %edx, %r15d
	movq -24(%rsi), %rdx
	cmpq $0, %rdx
	jnz .Lbb1995
	.loc 1 1059
	leaq -3896(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_drop
	movl %r15d, %edx
	movq %r13, %rdi
	movl -3424(%rbp), %eax
	movl -3420(%rbp), %r13d
	jmp .Lbb2006
.Lbb1995:
	movl %r15d, %edx
.Lbb1996:
	movq %rcx, -32(%rsi)
.Lbb1997:
	movq $0, -3896(%rbp)
	jmp .Lbb2006
.Lbb1998:
	movq -3896(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb2006
	movq -16(%rsi), %rcx
	movq $4611686018427387906, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jnz .Lbb2005
	movq -24(%rsi), %rcx
	subq $1, %rcx
	jnz .Lbb2004
	movl %edx, %r15d
	movq -32(%rsi), %rdx
	cmpq $0, %rdx
	jnz .Lbb2003
	.loc 1 1059
	leaq -3896(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_unloan
	movl %r15d, %edx
	movq %r13, %rdi
	movl -3424(%rbp), %eax
	movl -3420(%rbp), %r13d
	jmp .Lbb2006
.Lbb2003:
	movl %r15d, %edx
.Lbb2004:
	movq %rcx, -24(%rsi)
.Lbb2005:
	movq $0, -3896(%rbp)
.Lbb2006:
	movq -3904(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb2014
	movq -16(%rsi), %rcx
	movq $4611686018427387906, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jnz .Lbb2013
	movq -32(%rsi), %rcx
	subq $1, %rcx
	jnz .Lbb2012
	movl %edx, %r15d
	movq -24(%rsi), %rdx
	cmpq $0, %rdx
	jnz .Lbb2011
	.loc 1 1059
	leaq -3904(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_drop
	movl %r15d, %edx
	movq %r13, %rdi
	movl -3424(%rbp), %eax
	movl -3420(%rbp), %r13d
	jmp .Lbb2014
.Lbb2011:
	movl %r15d, %edx
.Lbb2012:
	movq %rcx, -32(%rsi)
.Lbb2013:
	movq $0, -3904(%rbp)
.Lbb2014:
	movl -4168(%rbp), %ecx
	cmpl $0, %ecx
	jz .Lbb2032
	movl $0, -4168(%rbp)
	testl $28, %r14d
	jnz .Lbb2024
	movq -3912(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb2032
	movq -16(%rsi), %rcx
	movq $4611686018427387906, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jnz .Lbb2023
	movq -32(%rsi), %rcx
	subq $1, %rcx
	jnz .Lbb2022
	movl %edx, %r15d
	movq -24(%rsi), %rdx
	cmpq $0, %rdx
	jnz .Lbb2021
	.loc 1 1059
	leaq -3912(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_drop
	movl %r15d, %edx
	movq %r14, %rdi
	movl -3424(%rbp), %eax
	jmp .Lbb2032
.Lbb2021:
	movl %r15d, %edx
.Lbb2022:
	movq %rcx, -32(%rsi)
.Lbb2023:
	movq $0, -3912(%rbp)
	jmp .Lbb2032
.Lbb2024:
	movq -3912(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb2032
	movq -16(%rsi), %rcx
	movq $4611686018427387906, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jnz .Lbb2031
	movq -24(%rsi), %rcx
	subq $1, %rcx
	jnz .Lbb2030
	movl %edx, %r15d
	movq -32(%rsi), %rdx
	cmpq $0, %rdx
	jnz .Lbb2029
	.loc 1 1059
	leaq -3912(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_unloan
	movl %r15d, %edx
	movq %r14, %rdi
	movl -3424(%rbp), %eax
	jmp .Lbb2032
.Lbb2029:
	movl %r15d, %edx
.Lbb2030:
	movq %rcx, -24(%rsi)
.Lbb2031:
	movq $0, -3912(%rbp)
.Lbb2032:
	movq -3920(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb2040
	movq -16(%rsi), %rcx
	movq $4611686018427387906, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jnz .Lbb2039
	movq -24(%rsi), %rcx
	subq $1, %rcx
	jnz .Lbb2038
	movl %edx, %r15d
	movq -32(%rsi), %rdx
	cmpq $0, %rdx
	jnz .Lbb2037
	.loc 1 1059
	leaq -3920(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movl %r15d, %edx
	movq %r14, %rdi
	movl -3424(%rbp), %eax
	jmp .Lbb2040
.Lbb2037:
	movl %r15d, %edx
.Lbb2038:
	movq %rcx, -24(%rsi)
.Lbb2039:
	movq $0, -3920(%rbp)
.Lbb2040:
	movq -3928(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb2048
	movq -16(%rsi), %rcx
	movq $4611686018427387906, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jnz .Lbb2047
	movq -32(%rsi), %rcx
	subq $1, %rcx
	jnz .Lbb2046
	movl %edx, %r15d
	movq -24(%rsi), %rdx
	cmpq $0, %rdx
	jnz .Lbb2045
	.loc 1 1059
	leaq -3928(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_drop
	movl %r15d, %edx
	movq %r14, %rdi
	movl -3424(%rbp), %eax
	jmp .Lbb2048
.Lbb2045:
	movl %r15d, %edx
.Lbb2046:
	movq %rcx, -32(%rsi)
.Lbb2047:
	movq $0, -3928(%rbp)
.Lbb2048:
	movl -4176(%rbp), %ecx
	cmpl $0, %ecx
	jz .Lbb2057
	movl $0, -4176(%rbp)
	movq -3936(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb2057
	movq -16(%rsi), %rcx
	movq $4611686018427387906, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jnz .Lbb2056
	movq -32(%rsi), %rcx
	subq $1, %rcx
	jnz .Lbb2055
	movl %edx, %r15d
	movq -24(%rsi), %rdx
	cmpq $0, %rdx
	jnz .Lbb2054
	.loc 1 1059
	leaq -3936(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_drop
	movl %r15d, %edx
	movq %r14, %rdi
	movl -3424(%rbp), %eax
	jmp .Lbb2057
.Lbb2054:
	movl %r15d, %edx
.Lbb2055:
	movq %rcx, -32(%rsi)
.Lbb2056:
	movq $0, -3936(%rbp)
.Lbb2057:
	cmpl $0, %eax
	jz .Lbb2066
	movq -3944(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2066
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb2065
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2064
	movl %edx, %r15d
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2063
	.loc 1 1059
	leaq -3944(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movl %r15d, %edx
	movq %r14, %rdi
	jmp .Lbb2066
.Lbb2063:
	movl %r15d, %edx
.Lbb2064:
	movq %rax, -32(%rcx)
.Lbb2065:
	movq $0, -3944(%rbp)
.Lbb2066:
	movl -4184(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2084
	movl $0, -4184(%rbp)
	testl $28, %r13d
	jnz .Lbb2076
	movq -3952(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2084
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb2075
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2074
	movl %edx, %r14d
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2073
	.loc 1 1059
	leaq -3952(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movl %r14d, %edx
	movq %r13, %rdi
	jmp .Lbb2084
.Lbb2073:
	movl %r14d, %edx
.Lbb2074:
	movq %rax, -32(%rcx)
.Lbb2075:
	movq $0, -3952(%rbp)
	jmp .Lbb2084
.Lbb2076:
	movq -3952(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2084
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb2083
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2082
	movl %edx, %r14d
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2081
	.loc 1 1059
	leaq -3952(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movl %r14d, %edx
	movq %r13, %rdi
	jmp .Lbb2084
.Lbb2081:
	movl %r14d, %edx
.Lbb2082:
	movq %rax, -24(%rcx)
.Lbb2083:
	movq $0, -3952(%rbp)
.Lbb2084:
	movq -3960(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2092
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb2091
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2090
	movl %edx, %r14d
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2089
	.loc 1 1059
	leaq -3960(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movl %r14d, %edx
	movq %r13, %rdi
	jmp .Lbb2092
.Lbb2089:
	movl %r14d, %edx
.Lbb2090:
	movq %rax, -32(%rcx)
.Lbb2091:
	movq $0, -3960(%rbp)
.Lbb2092:
	movl -4192(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2110
	movl $0, -4192(%rbp)
	testl $28, %ebx
	jnz .Lbb2102
	movq -3968(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2110
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb2101
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2100
	movl %edx, %r13d
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2099
	.loc 1 1059
	leaq -3968(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movl %r13d, %edx
	movq %rbx, %rdi
	jmp .Lbb2110
.Lbb2099:
	movl %r13d, %edx
.Lbb2100:
	movq %rax, -32(%rcx)
.Lbb2101:
	movq $0, -3968(%rbp)
	jmp .Lbb2110
.Lbb2102:
	movq -3968(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2110
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb2109
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2108
	movl %edx, %r13d
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2107
	.loc 1 1059
	leaq -3968(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movl %r13d, %edx
	movq %rbx, %rdi
	jmp .Lbb2110
.Lbb2107:
	movl %r13d, %edx
.Lbb2108:
	movq %rax, -24(%rcx)
.Lbb2109:
	movq $0, -3968(%rbp)
.Lbb2110:
	cmpl $0, %edx
	jz .Lbb2126
	testl $28, %r12d
	jnz .Lbb2119
	movq -3976(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2126
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2118
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2117
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2117
	.loc 1 1059
	leaq -3976(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %rbx, %rdi
	jmp .Lbb2126
.Lbb2117:
	movq %rax, -32(%rcx)
.Lbb2118:
	movq $0, -3976(%rbp)
	jmp .Lbb2126
.Lbb2119:
	movq -3976(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2126
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2125
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2124
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2124
	.loc 1 1059
	leaq -3976(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_unloan
	movq %rbx, %rdi
	jmp .Lbb2126
.Lbb2124:
	movq %rax, -24(%rcx)
.Lbb2125:
	movq $0, -3976(%rbp)
.Lbb2126:
	movq -3984(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2133
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2132
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2131
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2131
	.loc 1 1059
	leaq -3984(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %rbx, %rdi
	jmp .Lbb2133
.Lbb2131:
	movq %rax, -32(%rcx)
.Lbb2132:
	movq $0, -3984(%rbp)
.Lbb2133:
	movl -4200(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2141
	movl $0, -4200(%rbp)
	movq -3992(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2141
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2140
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2139
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2139
	.loc 1 1059
	leaq -3992(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	jmp .Lbb2141
.Lbb2139:
	movq %rax, -32(%rcx)
.Lbb2140:
	movq $0, -3992(%rbp)
.Lbb2141:
	movl $0, %eax
	jmp .Lbb2381
.Lbb2142:
	.loc 1 1051
	movl $64, %r8d
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2143:
	movq %r13, %rdx
	movq %rbx, %rdi
	.loc 1 496
	movq %rdx, %rbx
	movl $64, %edx
	movq %rbx, %rsi
	callq myl_qbe_fail_cast
	ud2
.Lbb2145:
	movq %r13, %rdx
	movq %rbx, %rdi
	.loc 1 495
	movl $64, %r8d
	movl $0, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2147:
	movq %rbx, %rdi
	.loc 1 419
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb2149:
	movl $0, %eax
	jmp .Lbb2381
.Lbb2150:
	movq %r12, %rdx
	movq %rbx, %rdi
	.loc 1 355
	movq %rdx, %rbx
	movl $64, %edx
	movq %rbx, %rsi
	callq myl_qbe_fail_cast
	ud2
.Lbb2152:
	movq %r12, %rdx
	movq %rbx, %rdi
	.loc 1 354
	movl $64, %r8d
	movl $0, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2154:
	movq %r12, %rdx
	movq %rbx, %rdi
	.loc 1 290
	movq %rdx, %rbx
	movl $64, %edx
	movq %rbx, %rsi
	callq myl_qbe_fail_cast
	ud2
.Lbb2156:
	movq %r12, %rdx
	movq %rbx, %rdi
	.loc 1 289
	movl $64, %r8d
	movl $0, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2158:
	movq %r12, %rdx
	movq %rbx, %rdi
	.loc 1 225
	movq %rdx, %rbx
	movl $64, %edx
	movq %rbx, %rsi
	callq myl_qbe_fail_cast
	ud2
.Lbb2160:
	movq %r12, %rdx
	movq %rbx, %rdi
	.loc 1 224
	movl $64, %r8d
	movl $0, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	ud2
.Lbb2162:
	movl %r13d, %edx
	movl %r15d, %r12d
	xchgq %rdi, %rbx
	movl -4048(%rbp), %eax
	movl -4016(%rbp), %ecx
	orl %ecx, %eax
	jnz .Lbb2165
	movl %edx, %r13d
	jmp .Lbb2166
.Lbb2165:
	leaq -4072(%rbp), %rax
	movq %rax, -4008(%rbp)
	leaq -4040(%rbp), %rax
	movq %rax, -4000(%rbp)
	.loc 1 185
	movl %edx, %r13d
	movl $2, %edx
	leaq -4008(%rbp), %rsi
	movq %rdi, %r14
	callq myl_qbe_rc_scopes_close
	movq %r14, %rdi
.Lbb2166:
	.loc 1 185
	callq myl_qbe_exit_skip
	movl %r13d, %edx
	movq %rbx, %rdi
	cmpl $0, %eax
	jnz .Lbb2243
	movl -4160(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2176
	movl $0, -4160(%rbp)
	movq -3896(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2176
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb2175
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2174
	movl %edx, %r13d
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2173
	.loc 1 185
	leaq -3896(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_drop
	movl %r13d, %edx
	movq %rbx, %rdi
	jmp .Lbb2176
.Lbb2173:
	movl %r13d, %edx
.Lbb2174:
	movq %rax, -32(%rcx)
.Lbb2175:
	movq $0, -3896(%rbp)
.Lbb2176:
	movl -4168(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2185
	movl $0, -4168(%rbp)
	movq -3912(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2185
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb2184
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2183
	movl %edx, %r13d
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2182
	.loc 1 185
	leaq -3912(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_drop
	movl %r13d, %edx
	movq %rbx, %rdi
	jmp .Lbb2185
.Lbb2182:
	movl %r13d, %edx
.Lbb2183:
	movq %rax, -32(%rcx)
.Lbb2184:
	movq $0, -3912(%rbp)
.Lbb2185:
	movl -4176(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2194
	movl $0, -4176(%rbp)
	movq -3936(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2194
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb2193
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2192
	movl %edx, %r13d
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2191
	.loc 1 185
	leaq -3936(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_drop
	movl %r13d, %edx
	movq %rbx, %rdi
	jmp .Lbb2194
.Lbb2191:
	movl %r13d, %edx
.Lbb2192:
	movq %rax, -32(%rcx)
.Lbb2193:
	movq $0, -3936(%rbp)
.Lbb2194:
	movl -4184(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2203
	movl $0, -4184(%rbp)
	movq -3952(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2203
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb2202
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2201
	movl %edx, %r13d
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2200
	.loc 1 185
	leaq -3952(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movl %r13d, %edx
	movq %rbx, %rdi
	jmp .Lbb2203
.Lbb2200:
	movl %r13d, %edx
.Lbb2201:
	movq %rax, -32(%rcx)
.Lbb2202:
	movq $0, -3952(%rbp)
.Lbb2203:
	movl -4192(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2212
	movl $0, -4192(%rbp)
	movq -3968(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2212
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb2211
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2210
	movl %edx, %r13d
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2209
	.loc 1 185
	leaq -3968(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movl %r13d, %edx
	movq %rbx, %rdi
	jmp .Lbb2212
.Lbb2209:
	movl %r13d, %edx
.Lbb2210:
	movq %rax, -32(%rcx)
.Lbb2211:
	movq $0, -3968(%rbp)
.Lbb2212:
	cmpl $0, %edx
	jz .Lbb2228
	testl $28, %r12d
	jnz .Lbb2221
	movq -3976(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2228
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2220
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2219
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2219
	.loc 1 185
	leaq -3976(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %rbx, %rdi
	jmp .Lbb2228
.Lbb2219:
	movq %rax, -32(%rcx)
.Lbb2220:
	movq $0, -3976(%rbp)
	jmp .Lbb2228
.Lbb2221:
	movq -3976(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2228
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2227
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2226
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2226
	.loc 1 185
	leaq -3976(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_unloan
	movq %rbx, %rdi
	jmp .Lbb2228
.Lbb2226:
	movq %rax, -24(%rcx)
.Lbb2227:
	movq $0, -3976(%rbp)
.Lbb2228:
	movq -3984(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2235
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2234
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2233
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2233
	.loc 1 185
	leaq -3984(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %rbx, %rdi
	jmp .Lbb2235
.Lbb2233:
	movq %rax, -32(%rcx)
.Lbb2234:
	movq $0, -3984(%rbp)
.Lbb2235:
	movl -4200(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2243
	movl $0, -4200(%rbp)
	movq -3992(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2243
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2242
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2241
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2241
	.loc 1 185
	leaq -3992(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	jmp .Lbb2243
.Lbb2241:
	movq %rax, -32(%rcx)
.Lbb2242:
	movq $0, -3992(%rbp)
.Lbb2243:
	movl $2, %eax
	jmp .Lbb2381
.Lbb2244:
	xchgq %rdi, %rbx
	movl -4048(%rbp), %eax
	movl -4016(%rbp), %ecx
	orl %ecx, %eax
	jnz .Lbb2247
	movl %edx, %r13d
	jmp .Lbb2248
.Lbb2247:
	leaq -4072(%rbp), %rax
	movq %rax, -4008(%rbp)
	leaq -4040(%rbp), %rax
	movq %rax, -4000(%rbp)
	.loc 1 110
	movl %edx, %r13d
	movl $2, %edx
	leaq -4008(%rbp), %rsi
	movq %rdi, %r14
	callq myl_qbe_rc_scopes_close
	movq %r14, %rdi
.Lbb2248:
	.loc 1 110
	callq myl_qbe_exit_skip
	movl %r13d, %edx
	movq %rbx, %rdi
	cmpl $0, %eax
	jnz .Lbb2325
	movl -4160(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2258
	movl $0, -4160(%rbp)
	movq -3896(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2258
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb2257
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2256
	movl %edx, %r13d
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2255
	.loc 1 110
	leaq -3896(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_drop
	movl %r13d, %edx
	movq %rbx, %rdi
	jmp .Lbb2258
.Lbb2255:
	movl %r13d, %edx
.Lbb2256:
	movq %rax, -32(%rcx)
.Lbb2257:
	movq $0, -3896(%rbp)
.Lbb2258:
	movl -4168(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2267
	movl $0, -4168(%rbp)
	movq -3912(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2267
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb2266
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2265
	movl %edx, %r13d
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2264
	.loc 1 110
	leaq -3912(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_drop
	movl %r13d, %edx
	movq %rbx, %rdi
	jmp .Lbb2267
.Lbb2264:
	movl %r13d, %edx
.Lbb2265:
	movq %rax, -32(%rcx)
.Lbb2266:
	movq $0, -3912(%rbp)
.Lbb2267:
	movl -4176(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2276
	movl $0, -4176(%rbp)
	movq -3936(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2276
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb2275
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2274
	movl %edx, %r13d
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2273
	.loc 1 110
	leaq -3936(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_drop
	movl %r13d, %edx
	movq %rbx, %rdi
	jmp .Lbb2276
.Lbb2273:
	movl %r13d, %edx
.Lbb2274:
	movq %rax, -32(%rcx)
.Lbb2275:
	movq $0, -3936(%rbp)
.Lbb2276:
	movl -4184(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2285
	movl $0, -4184(%rbp)
	movq -3952(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2285
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb2284
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2283
	movl %edx, %r13d
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2282
	.loc 1 110
	leaq -3952(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movl %r13d, %edx
	movq %rbx, %rdi
	jmp .Lbb2285
.Lbb2282:
	movl %r13d, %edx
.Lbb2283:
	movq %rax, -32(%rcx)
.Lbb2284:
	movq $0, -3952(%rbp)
.Lbb2285:
	movl -4192(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2294
	movl $0, -4192(%rbp)
	movq -3968(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2294
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb2293
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2292
	movl %edx, %r13d
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2291
	.loc 1 110
	leaq -3968(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movl %r13d, %edx
	movq %rbx, %rdi
	jmp .Lbb2294
.Lbb2291:
	movl %r13d, %edx
.Lbb2292:
	movq %rax, -32(%rcx)
.Lbb2293:
	movq $0, -3968(%rbp)
.Lbb2294:
	cmpl $0, %edx
	jz .Lbb2310
	testl $28, %r12d
	jnz .Lbb2303
	movq -3976(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2310
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2302
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2301
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2301
	.loc 1 110
	leaq -3976(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %rbx, %rdi
	jmp .Lbb2310
.Lbb2301:
	movq %rax, -32(%rcx)
.Lbb2302:
	movq $0, -3976(%rbp)
	jmp .Lbb2310
.Lbb2303:
	movq -3976(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2310
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2309
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2308
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2308
	.loc 1 110
	leaq -3976(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_unloan
	movq %rbx, %rdi
	jmp .Lbb2310
.Lbb2308:
	movq %rax, -24(%rcx)
.Lbb2309:
	movq $0, -3976(%rbp)
.Lbb2310:
	movq -3984(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2317
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2316
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2315
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2315
	.loc 1 110
	leaq -3984(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %rbx, %rdi
	jmp .Lbb2317
.Lbb2315:
	movq %rax, -32(%rcx)
.Lbb2316:
	movq $0, -3984(%rbp)
.Lbb2317:
	movl -4200(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2325
	movl $0, -4200(%rbp)
	movq -3992(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2325
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2324
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2323
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2323
	.loc 1 110
	leaq -3992(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	jmp .Lbb2325
.Lbb2323:
	movq %rax, -32(%rcx)
.Lbb2324:
	movq $0, -3992(%rbp)
.Lbb2325:
	movl $2, %eax
	jmp .Lbb2381
.Lbb2326:
	movq %rax, %rsi
	movq %rbx, %rdi
	.loc 1 60
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb2328:
	xchgq %rdi, %rbx
	movl -4048(%rbp), %eax
	movl -4016(%rbp), %ecx
	orl %ecx, %eax
	jz .Lbb2331
	leaq -4072(%rbp), %rax
	movq %rax, -4008(%rbp)
	leaq -4040(%rbp), %rax
	movq %rax, -4000(%rbp)
	.loc 1 9
	movl $2, %edx
	leaq -4008(%rbp), %rsi
	movq %rdi, %r12
	callq myl_qbe_rc_scopes_close
	movq %r12, %rdi
.Lbb2331:
	.loc 1 9
	callq myl_qbe_exit_skip
	movq %rbx, %rdi
	cmpl $0, %eax
	jnz .Lbb2380
	movl -4160(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2340
	movl $0, -4160(%rbp)
	movq -3896(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2340
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2339
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2338
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2338
	.loc 1 9
	leaq -3896(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_drop
	movq %rbx, %rdi
	jmp .Lbb2340
.Lbb2338:
	movq %rax, -32(%rcx)
.Lbb2339:
	movq $0, -3896(%rbp)
.Lbb2340:
	movl -4168(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2348
	movl $0, -4168(%rbp)
	movq -3912(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2348
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2347
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2346
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2346
	.loc 1 9
	leaq -3912(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_drop
	movq %rbx, %rdi
	jmp .Lbb2348
.Lbb2346:
	movq %rax, -32(%rcx)
.Lbb2347:
	movq $0, -3912(%rbp)
.Lbb2348:
	movl -4176(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2356
	movl $0, -4176(%rbp)
	movq -3936(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2356
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2355
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2354
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2354
	.loc 1 9
	leaq -3936(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_drop
	movq %rbx, %rdi
	jmp .Lbb2356
.Lbb2354:
	movq %rax, -32(%rcx)
.Lbb2355:
	movq $0, -3936(%rbp)
.Lbb2356:
	movl -4184(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2364
	movl $0, -4184(%rbp)
	movq -3952(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2364
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2363
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2362
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2362
	.loc 1 9
	leaq -3952(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %rbx, %rdi
	jmp .Lbb2364
.Lbb2362:
	movq %rax, -32(%rcx)
.Lbb2363:
	movq $0, -3952(%rbp)
.Lbb2364:
	movl -4192(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2372
	movl $0, -4192(%rbp)
	movq -3968(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2372
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2371
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2370
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2370
	.loc 1 9
	leaq -3968(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %rbx, %rdi
	jmp .Lbb2372
.Lbb2370:
	movq %rax, -32(%rcx)
.Lbb2371:
	movq $0, -3968(%rbp)
.Lbb2372:
	movl -4200(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2380
	movl $0, -4200(%rbp)
	movq -3992(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2380
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2379
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2378
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2378
	.loc 1 9
	leaq -3992(%rbp), %rsi
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	jmp .Lbb2380
.Lbb2378:
	movq %rax, -32(%rcx)
.Lbb2379:
	movq $0, -3992(%rbp)
.Lbb2380:
	movl $2, %eax
.Lbb2381:
	popq %r15
	popq %r14
	popq %r13
	popq %r12
	popq %rbx
	leave
	ret
.Lbb2382:
	movq %rax, %rsi
	movq %rbx, %rdi
	.loc 1 4
	movl $320, %edx
	callq myl_qbe_fail_cast
	ud2
.Lbb2384:
	movq %rbx, %rdi
	.loc 1 1 1
	callq myl_qbe_fail_frame
	ud2
.type myl_f_0d6e4079e36703ebd37c00722f5891d28b0e2811dc114b129215123adcce3605, @function
.size myl_f_0d6e4079e36703ebd37c00722f5891d28b0e2811dc114b129215123adcce3605, .-myl_f_0d6e4079e36703ebd37c00722f5891d28b0e2811dc114b129215123adcce3605
/* end function myl_f_0d6e4079e36703ebd37c00722f5891d28b0e2811dc114b129215123adcce3605 */

/* floating point constants */
.section .rodata
.p2align 3
.Lfp0:
	.quad 4616189618054758400 /* 4.000000 */

.section .rodata
.p2align 3
.Lfp1:
	.quad 4638707616191610880 /* 128.000000 */

.section .rodata
.p2align 3
.Lfp2:
	.quad 4602678819172646912 /* 0.500000 */

.section .rodata
.p2align 3
.Lfp3:
	.quad 4607182418800017408 /* 1.000000 */

.section .rodata
.p2align 3
.Lfp4:
	.quad 4625196817309499392 /* 16.000000 */

.section .rodata
.p2align 3
.Lfp5:
	.quad 4620693217682128896 /* 8.000000 */

.section .note.GNU-stack,"",@progbits
