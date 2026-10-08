.file 1 "myl_f_0d6e4079e36703ebd37c00722f5891d28b0e2811dc114b129215123adcce3605"
.text
.balign 16
.globl myl_f_0d6e4079e36703ebd37c00722f5891d28b0e2811dc114b129215123adcce3605
myl_f_0d6e4079e36703ebd37c00722f5891d28b0e2811dc114b129215123adcce3605:
	endbr64
	pushq %rbp
	movq %rsp, %rbp
	subq $2376, %rsp
	pushq %rbx
	pushq %r12
	pushq %r13
	pushq %r14
	pushq %r15
	movq %rcx, -1528(%rbp)
	movq %rdx, -1448(%rbp)
	movq %rdi, %rbx
	movq %rbx, -1224(%rbp)
	movq $0, -2184(%rbp)
	movq $0, -2152(%rbp)
	movq 64(%rbx), %rax
	leaq -1560(%rbp), %rcx
	cmpq %rax, %rcx
	setb %al
	movzbq %al, %rax
	movl $2, %r12d
	movl %r12d, -108(%rbp)
	movl $0, %ecx
	movq %rcx, -136(%rbp)
	imulq $8, %rcx, %rdx
	movq %rdx, -120(%rbp)
	movl $1, %ecx
	movq %rcx, -160(%rbp)
	imulq $8, %rcx, %rcx
	movq %rcx, -152(%rbp)
	movl $2, %ecx
	movq %rcx, -176(%rbp)
	imulq $8, %rcx, %rcx
	movq %rcx, -168(%rbp)
	movl $3, %ecx
	movq %rcx, -192(%rbp)
	imulq $8, %rcx, %rcx
	movq %rcx, -184(%rbp)
	movl $2, %ecx
	movl %ecx, %r13d
	movl %r13d, -204(%rbp)
	movl $2, %ecx
	movl %ecx, %r13d
	movl %r13d, -280(%rbp)
	movl $2, %ecx
	movl %ecx, -412(%rbp)
	movl $2, %r13d
	movl %r13d, -420(%rbp)
	movl $0, %ecx
	movq %rcx, -1432(%rbp)
	movl $0, %r8d
	movl %r8d, -112(%rbp)
	movl $0, %ecx
	movl %ecx, -268(%rbp)
	movl $0, %ecx
	movl %ecx, -360(%rbp)
	movl $0, %edx
	movl %edx, -424(%rbp)
	movl $0, %r13d
	movl %r13d, -416(%rbp)
	movl $2, %r14d
	movl %r14d, -436(%rbp)
	movl $0, %ecx
	movl %ecx, -440(%rbp)
	movl $2, %r13d
	movl %r13d, -464(%rbp)
	movl $0, %r14d
	movl %r14d, -460(%rbp)
	movl $0, %ecx
	movl %ecx, -1552(%rbp)
	movl $0, %r14d
	movl %r14d, -492(%rbp)
	movl $0, %r8d
	movl %r8d, -124(%rbp)
	cmpl $0, %eax
	jnz .Lbb2849
	movq $0, -2120(%rbp)
	movq $0, -2112(%rbp)
	movq $0, -2104(%rbp)
	movq $0, -2096(%rbp)
	movq $0, -2088(%rbp)
	movq $0, -2080(%rbp)
	movq $0, -2072(%rbp)
	movq $0, -2064(%rbp)
	movq $0, -2056(%rbp)
	movq $0, -2048(%rbp)
	movq $0, -2040(%rbp)
	movq $0, -2032(%rbp)
	movq $0, -2024(%rbp)
	movq $0, -2016(%rbp)
	movq %rsi, -2128(%rbp)
	.loc 1 1
	movq %rbx, %rdi
	callq myl_qbe_heap
	movq %rdx, -1240(%rbp)
	movq %rax, %rdi
	movq %rdi, -1232(%rbp)
	.loc 1 1
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_qbe_region_mark
	movq %rdx, -1240(%rbp)
	movq %r13, %rdi
	movq %rax, %r14
	movq %r14, -488(%rbp)
	movl $0, -2336(%rbp)
	movl $0, -2328(%rbp)
	movl $0, -2320(%rbp)
	movl $0, -2312(%rbp)
	movl $0, -2304(%rbp)
	movl $0, -2296(%rbp)
	.loc 1 1
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_qbe_require_step_accounting
	movq %rdx, -1240(%rbp)
	movq %r13, %rdi
	.loc 1 1
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_qbe_require_frame_accounting
	movq %rdx, -1240(%rbp)
	movq %r13, %rdi
	movq -2128(%rbp), %rax
	movq (%rax), %rsi
	movq $9223372036854775807, %rax
	cmpq %rax, %rsi
	ja .Lbb2847
	movq $4, -1840(%rbp)
	cmpq $4, %rsi
	setnz %al
	movzbq %al, %rax
	cmpl $0, %eax
	jnz .Lbb2793
	.loc 1 11
	movl $12, %edx
	movq %rdx, -1240(%rbp)
	movq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a@gotpcrel(%rip), %rsi
	movq %rdi, %r13
	callq myl_native_list_new
	movq %r14, %rcx
	movq %rdx, -1240(%rbp)
	movq %r13, %rdi
	cmpl $0, %eax
	jnz .Lbb6
	movq %rbx, %rdi
	.loc 1 11
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	movq %rdx, -1240(%rbp)
	ud2
.Lbb6:
	movq %rax, -2256(%rbp)
	movq -2256(%rbp), %rdx
	movq %rdx, -2248(%rbp)
	movq -2248(%rbp), %rdx
	movq %rdx, -2288(%rbp)
	movq %rax, -2256(%rbp)
	leaq -2248(%rbp), %rsi
	leaq -2256(%rbp), %rdx
	negq %rsi
	addq %rdx, %rsi
	leaq -2256(%rbp), %r8
	leaq -2248(%rbp), %rdx
	subq %r8, %rdx
	cmpq $8, %rsi
	setb %r14b
	movzbl %r14b, %r14d
	movl %r14d, -500(%rbp)
	cmpq $8, %rdx
	setb %r15b
	movzbl %r15b, %r15d
	movl %r15d, -496(%rbp)
	movl %r14d, %edx
	orl %r15d, %edx
	jnz .Lbb10
	cmpq $0, %rax
	jz .Lbb9
	movq -16(%rax), %rax
	movq $5764607523034234881, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb10
.Lbb9:
	movq -2256(%rbp), %rax
	movq %rax, -2248(%rbp)
	movq $0, -2256(%rbp)
	jmp .Lbb12
.Lbb10:
	.loc 1 12
	movq %rcx, %r13
	leaq -2256(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_take
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl -108(%rbp), %r12d
	cmpl $0, %eax
	jnz .Lbb12
	.loc 1 12
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 12
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb12:
	movl -2336(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb21
	movl $0, -2336(%rbp)
	movq -2120(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb21
	movq -16(%rdx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb20
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb19
	movq %rcx, %r13
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb18
	.loc 1 12
	leaq -2120(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl -108(%rbp), %r12d
	jmp .Lbb21
.Lbb18:
	movq %r13, %rcx
.Lbb19:
	movq %rax, -32(%rdx)
.Lbb20:
	movq $0, -2120(%rbp)
.Lbb21:
	movq -2248(%rbp), %rax
	movq %rax, -2120(%rbp)
	movl $1, -2336(%rbp)
	movq myl_lit_91d8e386c30c656a06165cf351f92965220d6691140b83eaf5169fd74bae9057(%rip), %rax
	movq %rax, -16(%rbp)
	movq %rax, -2256(%rbp)
	movq -2256(%rbp), %rdx
	movq %rdx, -2248(%rbp)
	movq -2248(%rbp), %rdx
	movq %rdx, -2288(%rbp)
	cmpl $16, %r12d
	jnz .Lbb51
	movq -2120(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb29
	movq -16(%rdx), %rsi
	movq $4611686018427387906, %r8
	andq %rsi, %r8
	cmpq $0, %r8
	jnz .Lbb28
	movq -32(%rdx), %rsi
	addq $1, %rsi
	jz .Lbb26
	movq %rsi, -32(%rdx)
	jmp .Lbb29
.Lbb26:
	movq %rbx, %rdi
	.loc 1 14
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb28:
	movq $4611686018427387904, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb30
.Lbb29:
	movq %rdx, -2248(%rbp)
	jmp .Lbb32
.Lbb30:
	.loc 1 14
	movq %rcx, %r13
	leaq -2120(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_retain
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %eax, %edx
	movl -108(%rbp), %r12d
	movq -16(%rbp), %rax
	cmpl $0, %edx
	jnz .Lbb32
	.loc 1 14
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 14
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb32:
	movl -2336(%rbp), %edx
	cmpl $0, %edx
	jz .Lbb50
	movl $0, -2336(%rbp)
	testl $28, %r12d
	jnz .Lbb42
	movq -2120(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb50
	movq -16(%rsi), %rdx
	movq $4611686018427387906, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jnz .Lbb41
	movq -32(%rsi), %rdx
	subq $1, %rdx
	jnz .Lbb40
	movq %rcx, %r13
	movq -24(%rsi), %rcx
	cmpq $0, %rcx
	jnz .Lbb39
	.loc 1 14
	leaq -2120(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movq -16(%rbp), %rax
	jmp .Lbb50
.Lbb39:
	movq %r13, %rcx
.Lbb40:
	movq %rdx, -32(%rsi)
.Lbb41:
	movq $0, -2120(%rbp)
	jmp .Lbb50
.Lbb42:
	movq -2120(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb50
	movq -16(%rsi), %rdx
	movq $4611686018427387906, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jnz .Lbb49
	movq -24(%rsi), %rdx
	subq $1, %rdx
	jnz .Lbb48
	movq %rcx, %r13
	movq -32(%rsi), %rcx
	cmpq $0, %rcx
	jnz .Lbb47
	.loc 1 14
	leaq -2120(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_unloan
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movq -16(%rbp), %rax
	jmp .Lbb50
.Lbb47:
	movq %r13, %rcx
.Lbb48:
	movq %rdx, -24(%rsi)
.Lbb49:
	movq $0, -2120(%rbp)
.Lbb50:
	movq -2248(%rbp), %rdx
	movq %rdx, -2120(%rbp)
	movl $1, -2336(%rbp)
.Lbb51:
	movq -2120(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb53
	movq %rcx, %r13
	jmp .Lbb57
.Lbb53:
	movq -16(%rdx), %rsi
	movq $6917529027641081858, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb56
	movq -32(%rdx), %rdx
	cmpq $2, %rdx
	jae .Lbb56
	movq %rcx, %r13
	jmp .Lbb57
.Lbb56:
	.loc 1 14
	movq %rcx, %r13
	leaq -2336(%rbp), %rcx
	leaq -2120(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %eax, %ecx
	movq -16(%rbp), %rax
	cmpl $0, %ecx
	jz .Lbb2614
.Lbb57:
	movq -2120(%rbp), %rsi
	movq %rax, -2216(%rbp)
	.loc 1 14
	leaq -2216(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_list_append
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	cmpl $0, %eax
	jnz .Lbb60
	movq %rbx, %rdi
	.loc 1 14
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	movq %rdx, -1240(%rbp)
	ud2
.Lbb60:
	movq -2288(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb68
	movq -16(%rdx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb67
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb66
	movq %rcx, %r13
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb65
	.loc 1 14
	leaq -2288(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	jmp .Lbb68
.Lbb65:
	movq %r13, %rcx
.Lbb66:
	movq %rax, -32(%rdx)
.Lbb67:
	movq $0, -2288(%rbp)
.Lbb68:
	movq myl_lit_48af4f085a39fdc824c1a25d3474aed7f74c916b0549dc50c9b7a25c3f2fdf98(%rip), %rax
	movq %rax, -24(%rbp)
	movq %rax, -2256(%rbp)
	movq -2256(%rbp), %rdx
	movq %rdx, -2248(%rbp)
	movq -2248(%rbp), %rdx
	movq %rdx, -2288(%rbp)
	movl -2336(%rbp), %edx
	testl $0, %edx
	jz .Lbb89
	movq -2120(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb76
	movq -16(%rdx), %rsi
	movq $4611686018427387906, %r8
	andq %rsi, %r8
	cmpq $0, %r8
	jnz .Lbb75
	movq -32(%rdx), %rsi
	addq $1, %rsi
	jz .Lbb73
	movq %rsi, -32(%rdx)
	jmp .Lbb76
.Lbb73:
	movq %rbx, %rdi
	.loc 1 17
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb75:
	movq $4611686018427387904, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb77
.Lbb76:
	movq %rdx, -2248(%rbp)
	jmp .Lbb79
.Lbb77:
	.loc 1 17
	movq %rcx, %r13
	leaq -2120(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_retain
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %eax, %edx
	movq -24(%rbp), %rax
	cmpl $0, %edx
	jnz .Lbb79
	.loc 1 17
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 17
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb79:
	movl -2336(%rbp), %edx
	cmpl $0, %edx
	jz .Lbb88
	movl $0, -2336(%rbp)
	movq -2120(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb88
	movq -16(%rsi), %rdx
	movq $4611686018427387906, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jnz .Lbb87
	movq -32(%rsi), %rdx
	subq $1, %rdx
	jnz .Lbb86
	movq %rcx, %r13
	movq -24(%rsi), %rcx
	cmpq $0, %rcx
	jnz .Lbb85
	.loc 1 17
	leaq -2120(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movq -24(%rbp), %rax
	jmp .Lbb88
.Lbb85:
	movq %r13, %rcx
.Lbb86:
	movq %rdx, -32(%rsi)
.Lbb87:
	movq $0, -2120(%rbp)
.Lbb88:
	movq -2248(%rbp), %rdx
	movq %rdx, -2120(%rbp)
	movl $1, -2336(%rbp)
.Lbb89:
	movq -2120(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb91
	movq %rcx, %r13
	jmp .Lbb95
.Lbb91:
	movq -16(%rdx), %rsi
	movq $6917529027641081858, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb94
	movq -32(%rdx), %rdx
	cmpq $2, %rdx
	jae .Lbb94
	movq %rcx, %r13
	jmp .Lbb95
.Lbb94:
	.loc 1 17
	movq %rcx, %r13
	leaq -2336(%rbp), %rcx
	leaq -2120(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %eax, %ecx
	movq -24(%rbp), %rax
	cmpl $0, %ecx
	jz .Lbb2614
.Lbb95:
	movq -2120(%rbp), %rsi
	movq %rax, -2216(%rbp)
	.loc 1 17
	leaq -2216(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_list_append
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	cmpl $0, %eax
	jnz .Lbb98
	movq %rbx, %rdi
	.loc 1 17
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	movq %rdx, -1240(%rbp)
	ud2
.Lbb98:
	movq -2288(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb106
	movq -16(%rdx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb105
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb104
	movq %rcx, %r13
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb103
	.loc 1 17
	leaq -2288(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	jmp .Lbb106
.Lbb103:
	movq %r13, %rcx
.Lbb104:
	movq %rax, -32(%rdx)
.Lbb105:
	movq $0, -2288(%rbp)
.Lbb106:
	movq myl_lit_87e3dc7d60448f96b55621ea82cda5ab42e87191032c1d8a40da5b27ba5c5039(%rip), %rax
	movq %rax, -32(%rbp)
	movq %rax, -2256(%rbp)
	movq -2256(%rbp), %rdx
	movq %rdx, -2248(%rbp)
	movq -2248(%rbp), %rdx
	movq %rdx, -2288(%rbp)
	movl -2336(%rbp), %edx
	testl $0, %edx
	jz .Lbb127
	movq -2120(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb114
	movq -16(%rdx), %rsi
	movq $4611686018427387906, %r8
	andq %rsi, %r8
	cmpq $0, %r8
	jnz .Lbb113
	movq -32(%rdx), %rsi
	addq $1, %rsi
	jz .Lbb111
	movq %rsi, -32(%rdx)
	jmp .Lbb114
.Lbb111:
	movq %rbx, %rdi
	.loc 1 20
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb113:
	movq $4611686018427387904, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb115
.Lbb114:
	movq %rdx, -2248(%rbp)
	jmp .Lbb117
.Lbb115:
	.loc 1 20
	movq %rcx, %r13
	leaq -2120(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_retain
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %eax, %edx
	movq -32(%rbp), %rax
	cmpl $0, %edx
	jnz .Lbb117
	.loc 1 20
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 20
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb117:
	movl -2336(%rbp), %edx
	cmpl $0, %edx
	jz .Lbb126
	movl $0, -2336(%rbp)
	movq -2120(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb126
	movq -16(%rsi), %rdx
	movq $4611686018427387906, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jnz .Lbb125
	movq -32(%rsi), %rdx
	subq $1, %rdx
	jnz .Lbb124
	movq %rcx, %r13
	movq -24(%rsi), %rcx
	cmpq $0, %rcx
	jnz .Lbb123
	.loc 1 20
	leaq -2120(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movq -32(%rbp), %rax
	jmp .Lbb126
.Lbb123:
	movq %r13, %rcx
.Lbb124:
	movq %rdx, -32(%rsi)
.Lbb125:
	movq $0, -2120(%rbp)
.Lbb126:
	movq -2248(%rbp), %rdx
	movq %rdx, -2120(%rbp)
	movl $1, -2336(%rbp)
.Lbb127:
	movq -2120(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb129
	movq %rcx, %r13
	jmp .Lbb133
.Lbb129:
	movq -16(%rdx), %rsi
	movq $6917529027641081858, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb132
	movq -32(%rdx), %rdx
	cmpq $2, %rdx
	jae .Lbb132
	movq %rcx, %r13
	jmp .Lbb133
.Lbb132:
	.loc 1 20
	movq %rcx, %r13
	leaq -2336(%rbp), %rcx
	leaq -2120(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %eax, %ecx
	movq -32(%rbp), %rax
	cmpl $0, %ecx
	jz .Lbb2614
.Lbb133:
	movq -2120(%rbp), %rsi
	movq %rax, -2216(%rbp)
	.loc 1 20
	leaq -2216(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_list_append
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	cmpl $0, %eax
	jnz .Lbb136
	movq %rbx, %rdi
	.loc 1 20
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	movq %rdx, -1240(%rbp)
	ud2
.Lbb136:
	movq -2288(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb144
	movq -16(%rdx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb143
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb142
	movq %rcx, %r13
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb141
	.loc 1 20
	leaq -2288(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	jmp .Lbb144
.Lbb141:
	movq %r13, %rcx
.Lbb142:
	movq %rax, -32(%rdx)
.Lbb143:
	movq $0, -2288(%rbp)
.Lbb144:
	movq myl_lit_893cdd504b2a309e97713e1ad13e95d9da6761cdcb493d1d2fb2d27b576568a0(%rip), %rax
	movq %rax, -40(%rbp)
	movq %rax, -2256(%rbp)
	movq -2256(%rbp), %rdx
	movq %rdx, -2248(%rbp)
	movq -2248(%rbp), %rdx
	movq %rdx, -2288(%rbp)
	movl -2336(%rbp), %edx
	testl $0, %edx
	jz .Lbb165
	movq -2120(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb152
	movq -16(%rdx), %rsi
	movq $4611686018427387906, %r8
	andq %rsi, %r8
	cmpq $0, %r8
	jnz .Lbb151
	movq -32(%rdx), %rsi
	addq $1, %rsi
	jz .Lbb149
	movq %rsi, -32(%rdx)
	jmp .Lbb152
.Lbb149:
	movq %rbx, %rdi
	.loc 1 23
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb151:
	movq $4611686018427387904, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb153
.Lbb152:
	movq %rdx, -2248(%rbp)
	jmp .Lbb155
.Lbb153:
	.loc 1 23
	movq %rcx, %r13
	leaq -2120(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_retain
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %eax, %edx
	movq -40(%rbp), %rax
	cmpl $0, %edx
	jnz .Lbb155
	.loc 1 23
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 23
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb155:
	movl -2336(%rbp), %edx
	cmpl $0, %edx
	jz .Lbb164
	movl $0, -2336(%rbp)
	movq -2120(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb164
	movq -16(%rsi), %rdx
	movq $4611686018427387906, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jnz .Lbb163
	movq -32(%rsi), %rdx
	subq $1, %rdx
	jnz .Lbb162
	movq %rcx, %r13
	movq -24(%rsi), %rcx
	cmpq $0, %rcx
	jnz .Lbb161
	.loc 1 23
	leaq -2120(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movq -40(%rbp), %rax
	jmp .Lbb164
.Lbb161:
	movq %r13, %rcx
.Lbb162:
	movq %rdx, -32(%rsi)
.Lbb163:
	movq $0, -2120(%rbp)
.Lbb164:
	movq -2248(%rbp), %rdx
	movq %rdx, -2120(%rbp)
	movl $1, -2336(%rbp)
.Lbb165:
	movq -2120(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb167
	movq %rcx, %r13
	jmp .Lbb171
.Lbb167:
	movq -16(%rdx), %rsi
	movq $6917529027641081858, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb170
	movq -32(%rdx), %rdx
	cmpq $2, %rdx
	jae .Lbb170
	movq %rcx, %r13
	jmp .Lbb171
.Lbb170:
	.loc 1 23
	movq %rcx, %r13
	leaq -2336(%rbp), %rcx
	leaq -2120(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %eax, %ecx
	movq -40(%rbp), %rax
	cmpl $0, %ecx
	jz .Lbb2614
.Lbb171:
	movq -2120(%rbp), %rsi
	movq %rax, -2216(%rbp)
	.loc 1 23
	leaq -2216(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_list_append
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	cmpl $0, %eax
	jnz .Lbb174
	movq %rbx, %rdi
	.loc 1 23
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	movq %rdx, -1240(%rbp)
	ud2
.Lbb174:
	movq -2288(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb182
	movq -16(%rdx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb181
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb180
	movq %rcx, %r13
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb179
	.loc 1 23
	leaq -2288(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	jmp .Lbb182
.Lbb179:
	movq %r13, %rcx
.Lbb180:
	movq %rax, -32(%rdx)
.Lbb181:
	movq $0, -2288(%rbp)
.Lbb182:
	movq myl_lit_092d7c6801f882df3074b77feb8a8cfae05fd11077e077b473214d2840e62f89(%rip), %rax
	movq %rax, -48(%rbp)
	movq %rax, -2256(%rbp)
	movq -2256(%rbp), %rdx
	movq %rdx, -2248(%rbp)
	movq -2248(%rbp), %rdx
	movq %rdx, -2288(%rbp)
	movl -2336(%rbp), %edx
	testl $0, %edx
	jz .Lbb203
	movq -2120(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb190
	movq -16(%rdx), %rsi
	movq $4611686018427387906, %r8
	andq %rsi, %r8
	cmpq $0, %r8
	jnz .Lbb189
	movq -32(%rdx), %rsi
	addq $1, %rsi
	jz .Lbb187
	movq %rsi, -32(%rdx)
	jmp .Lbb190
.Lbb187:
	movq %rbx, %rdi
	.loc 1 26
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb189:
	movq $4611686018427387904, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb191
.Lbb190:
	movq %rdx, -2248(%rbp)
	jmp .Lbb193
.Lbb191:
	.loc 1 26
	movq %rcx, %r13
	leaq -2120(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_retain
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %eax, %edx
	movq -48(%rbp), %rax
	cmpl $0, %edx
	jnz .Lbb193
	.loc 1 26
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 26
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb193:
	movl -2336(%rbp), %edx
	cmpl $0, %edx
	jz .Lbb202
	movl $0, -2336(%rbp)
	movq -2120(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb202
	movq -16(%rsi), %rdx
	movq $4611686018427387906, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jnz .Lbb201
	movq -32(%rsi), %rdx
	subq $1, %rdx
	jnz .Lbb200
	movq %rcx, %r13
	movq -24(%rsi), %rcx
	cmpq $0, %rcx
	jnz .Lbb199
	.loc 1 26
	leaq -2120(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movq -48(%rbp), %rax
	jmp .Lbb202
.Lbb199:
	movq %r13, %rcx
.Lbb200:
	movq %rdx, -32(%rsi)
.Lbb201:
	movq $0, -2120(%rbp)
.Lbb202:
	movq -2248(%rbp), %rdx
	movq %rdx, -2120(%rbp)
	movl $1, -2336(%rbp)
.Lbb203:
	movq -2120(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb205
	movq %rcx, %r13
	jmp .Lbb209
.Lbb205:
	movq -16(%rdx), %rsi
	movq $6917529027641081858, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb208
	movq -32(%rdx), %rdx
	cmpq $2, %rdx
	jae .Lbb208
	movq %rcx, %r13
	jmp .Lbb209
.Lbb208:
	.loc 1 26
	movq %rcx, %r13
	leaq -2336(%rbp), %rcx
	leaq -2120(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %eax, %ecx
	movq -48(%rbp), %rax
	cmpl $0, %ecx
	jz .Lbb2614
.Lbb209:
	movq -2120(%rbp), %rsi
	movq %rax, -2216(%rbp)
	.loc 1 26
	leaq -2216(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_list_append
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	cmpl $0, %eax
	jnz .Lbb212
	movq %rbx, %rdi
	.loc 1 26
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	movq %rdx, -1240(%rbp)
	ud2
.Lbb212:
	movq -2288(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb220
	movq -16(%rdx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb219
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb218
	movq %rcx, %r13
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb217
	.loc 1 26
	leaq -2288(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	jmp .Lbb220
.Lbb217:
	movq %r13, %rcx
.Lbb218:
	movq %rax, -32(%rdx)
.Lbb219:
	movq $0, -2288(%rbp)
.Lbb220:
	movq myl_lit_34de47119c2d38616e51ac3e34c9dbe870e177ae9782bc3e9e986f1120a4b1c8(%rip), %rax
	movq %rax, -56(%rbp)
	movq %rax, -2256(%rbp)
	movq -2256(%rbp), %rdx
	movq %rdx, -2248(%rbp)
	movq -2248(%rbp), %rdx
	movq %rdx, -2288(%rbp)
	movl -2336(%rbp), %edx
	testl $0, %edx
	jz .Lbb241
	movq -2120(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb228
	movq -16(%rdx), %rsi
	movq $4611686018427387906, %r8
	andq %rsi, %r8
	cmpq $0, %r8
	jnz .Lbb227
	movq -32(%rdx), %rsi
	addq $1, %rsi
	jz .Lbb225
	movq %rsi, -32(%rdx)
	jmp .Lbb228
.Lbb225:
	movq %rbx, %rdi
	.loc 1 29
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb227:
	movq $4611686018427387904, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb229
.Lbb228:
	movq %rdx, -2248(%rbp)
	jmp .Lbb231
.Lbb229:
	.loc 1 29
	movq %rcx, %r13
	leaq -2120(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_retain
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %eax, %edx
	movq -56(%rbp), %rax
	cmpl $0, %edx
	jnz .Lbb231
	.loc 1 29
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 29
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb231:
	movl -2336(%rbp), %edx
	cmpl $0, %edx
	jz .Lbb240
	movl $0, -2336(%rbp)
	movq -2120(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb240
	movq -16(%rsi), %rdx
	movq $4611686018427387906, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jnz .Lbb239
	movq -32(%rsi), %rdx
	subq $1, %rdx
	jnz .Lbb238
	movq %rcx, %r13
	movq -24(%rsi), %rcx
	cmpq $0, %rcx
	jnz .Lbb237
	.loc 1 29
	leaq -2120(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movq -56(%rbp), %rax
	jmp .Lbb240
.Lbb237:
	movq %r13, %rcx
.Lbb238:
	movq %rdx, -32(%rsi)
.Lbb239:
	movq $0, -2120(%rbp)
.Lbb240:
	movq -2248(%rbp), %rdx
	movq %rdx, -2120(%rbp)
	movl $1, -2336(%rbp)
.Lbb241:
	movq -2120(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb243
	movq %rcx, %r13
	jmp .Lbb247
.Lbb243:
	movq -16(%rdx), %rsi
	movq $6917529027641081858, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb246
	movq -32(%rdx), %rdx
	cmpq $2, %rdx
	jae .Lbb246
	movq %rcx, %r13
	jmp .Lbb247
.Lbb246:
	.loc 1 29
	movq %rcx, %r13
	leaq -2336(%rbp), %rcx
	leaq -2120(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %eax, %ecx
	movq -56(%rbp), %rax
	cmpl $0, %ecx
	jz .Lbb2614
.Lbb247:
	movq -2120(%rbp), %rsi
	movq %rax, -2216(%rbp)
	.loc 1 29
	leaq -2216(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_list_append
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	cmpl $0, %eax
	jnz .Lbb250
	movq %rbx, %rdi
	.loc 1 29
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	movq %rdx, -1240(%rbp)
	ud2
.Lbb250:
	movq -2288(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb258
	movq -16(%rdx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb257
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb256
	movq %rcx, %r13
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb255
	.loc 1 29
	leaq -2288(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	jmp .Lbb258
.Lbb255:
	movq %r13, %rcx
.Lbb256:
	movq %rax, -32(%rdx)
.Lbb257:
	movq $0, -2288(%rbp)
.Lbb258:
	movq myl_lit_508b25981ffcb062ef47f525f87fd682c2be6416d9d7c4a0b4ca20c3e4f84a16(%rip), %rax
	movq %rax, -64(%rbp)
	movq %rax, -2256(%rbp)
	movq -2256(%rbp), %rdx
	movq %rdx, -2248(%rbp)
	movq -2248(%rbp), %rdx
	movq %rdx, -2288(%rbp)
	movl -2336(%rbp), %edx
	testl $0, %edx
	jz .Lbb279
	movq -2120(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb266
	movq -16(%rdx), %rsi
	movq $4611686018427387906, %r8
	andq %rsi, %r8
	cmpq $0, %r8
	jnz .Lbb265
	movq -32(%rdx), %rsi
	addq $1, %rsi
	jz .Lbb263
	movq %rsi, -32(%rdx)
	jmp .Lbb266
.Lbb263:
	movq %rbx, %rdi
	.loc 1 32
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb265:
	movq $4611686018427387904, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb267
.Lbb266:
	movq %rdx, -2248(%rbp)
	jmp .Lbb269
.Lbb267:
	.loc 1 32
	movq %rcx, %r13
	leaq -2120(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_retain
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %eax, %edx
	movq -64(%rbp), %rax
	cmpl $0, %edx
	jnz .Lbb269
	.loc 1 32
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 32
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb269:
	movl -2336(%rbp), %edx
	cmpl $0, %edx
	jz .Lbb278
	movl $0, -2336(%rbp)
	movq -2120(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb278
	movq -16(%rsi), %rdx
	movq $4611686018427387906, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jnz .Lbb277
	movq -32(%rsi), %rdx
	subq $1, %rdx
	jnz .Lbb276
	movq %rcx, %r13
	movq -24(%rsi), %rcx
	cmpq $0, %rcx
	jnz .Lbb275
	.loc 1 32
	leaq -2120(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movq -64(%rbp), %rax
	jmp .Lbb278
.Lbb275:
	movq %r13, %rcx
.Lbb276:
	movq %rdx, -32(%rsi)
.Lbb277:
	movq $0, -2120(%rbp)
.Lbb278:
	movq -2248(%rbp), %rdx
	movq %rdx, -2120(%rbp)
	movl $1, -2336(%rbp)
.Lbb279:
	movq -2120(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb281
	movq %rcx, %r13
	jmp .Lbb285
.Lbb281:
	movq -16(%rdx), %rsi
	movq $6917529027641081858, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb284
	movq -32(%rdx), %rdx
	cmpq $2, %rdx
	jae .Lbb284
	movq %rcx, %r13
	jmp .Lbb285
.Lbb284:
	.loc 1 32
	movq %rcx, %r13
	leaq -2336(%rbp), %rcx
	leaq -2120(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %eax, %ecx
	movq -64(%rbp), %rax
	cmpl $0, %ecx
	jz .Lbb2614
.Lbb285:
	movq -2120(%rbp), %rsi
	movq %rax, -2216(%rbp)
	.loc 1 32
	leaq -2216(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_list_append
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	cmpl $0, %eax
	jnz .Lbb288
	movq %rbx, %rdi
	.loc 1 32
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	movq %rdx, -1240(%rbp)
	ud2
.Lbb288:
	movq -2288(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb296
	movq -16(%rdx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb295
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb294
	movq %rcx, %r13
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb293
	.loc 1 32
	leaq -2288(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	jmp .Lbb296
.Lbb293:
	movq %r13, %rcx
.Lbb294:
	movq %rax, -32(%rdx)
.Lbb295:
	movq $0, -2288(%rbp)
.Lbb296:
	movq myl_lit_5df1e3adc6cd2d309d46b415edafb480bb2aac56d37d79d6464456909f15ac46(%rip), %rax
	movq %rax, -72(%rbp)
	movq %rax, -2256(%rbp)
	movq -2256(%rbp), %rdx
	movq %rdx, -2248(%rbp)
	movq -2248(%rbp), %rdx
	movq %rdx, -2288(%rbp)
	movl -2336(%rbp), %edx
	testl $0, %edx
	jz .Lbb317
	movq -2120(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb304
	movq -16(%rdx), %rsi
	movq $4611686018427387906, %r8
	andq %rsi, %r8
	cmpq $0, %r8
	jnz .Lbb303
	movq -32(%rdx), %rsi
	addq $1, %rsi
	jz .Lbb301
	movq %rsi, -32(%rdx)
	jmp .Lbb304
.Lbb301:
	movq %rbx, %rdi
	.loc 1 35
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb303:
	movq $4611686018427387904, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb305
.Lbb304:
	movq %rdx, -2248(%rbp)
	jmp .Lbb307
.Lbb305:
	.loc 1 35
	movq %rcx, %r13
	leaq -2120(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_retain
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %eax, %edx
	movq -72(%rbp), %rax
	cmpl $0, %edx
	jnz .Lbb307
	.loc 1 35
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 35
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb307:
	movl -2336(%rbp), %edx
	cmpl $0, %edx
	jz .Lbb316
	movl $0, -2336(%rbp)
	movq -2120(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb316
	movq -16(%rsi), %rdx
	movq $4611686018427387906, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jnz .Lbb315
	movq -32(%rsi), %rdx
	subq $1, %rdx
	jnz .Lbb314
	movq %rcx, %r13
	movq -24(%rsi), %rcx
	cmpq $0, %rcx
	jnz .Lbb313
	.loc 1 35
	leaq -2120(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movq -72(%rbp), %rax
	jmp .Lbb316
.Lbb313:
	movq %r13, %rcx
.Lbb314:
	movq %rdx, -32(%rsi)
.Lbb315:
	movq $0, -2120(%rbp)
.Lbb316:
	movq -2248(%rbp), %rdx
	movq %rdx, -2120(%rbp)
	movl $1, -2336(%rbp)
.Lbb317:
	movq -2120(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb319
	movq %rcx, %r13
	jmp .Lbb323
.Lbb319:
	movq -16(%rdx), %rsi
	movq $6917529027641081858, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb322
	movq -32(%rdx), %rdx
	cmpq $2, %rdx
	jae .Lbb322
	movq %rcx, %r13
	jmp .Lbb323
.Lbb322:
	.loc 1 35
	movq %rcx, %r13
	leaq -2336(%rbp), %rcx
	leaq -2120(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %eax, %ecx
	movq -72(%rbp), %rax
	cmpl $0, %ecx
	jz .Lbb2614
.Lbb323:
	movq -2120(%rbp), %rsi
	movq %rax, -2216(%rbp)
	.loc 1 35
	leaq -2216(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_list_append
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	cmpl $0, %eax
	jnz .Lbb326
	movq %rbx, %rdi
	.loc 1 35
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	movq %rdx, -1240(%rbp)
	ud2
.Lbb326:
	movq -2288(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb334
	movq -16(%rdx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb333
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb332
	movq %rcx, %r13
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb331
	.loc 1 35
	leaq -2288(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	jmp .Lbb334
.Lbb331:
	movq %r13, %rcx
.Lbb332:
	movq %rax, -32(%rdx)
.Lbb333:
	movq $0, -2288(%rbp)
.Lbb334:
	movq myl_lit_bf0fa3d2de4dff2fec439219b629ad17e9791bb9a451d7c298cc60f8dcce562a(%rip), %rax
	movq %rax, -80(%rbp)
	movq %rax, -2256(%rbp)
	movq -2256(%rbp), %rdx
	movq %rdx, -2248(%rbp)
	movq -2248(%rbp), %rdx
	movq %rdx, -2288(%rbp)
	movl -2336(%rbp), %edx
	testl $0, %edx
	jz .Lbb355
	movq -2120(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb342
	movq -16(%rdx), %rsi
	movq $4611686018427387906, %r8
	andq %rsi, %r8
	cmpq $0, %r8
	jnz .Lbb341
	movq -32(%rdx), %rsi
	addq $1, %rsi
	jz .Lbb339
	movq %rsi, -32(%rdx)
	jmp .Lbb342
.Lbb339:
	movq %rbx, %rdi
	.loc 1 38
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb341:
	movq $4611686018427387904, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb343
.Lbb342:
	movq %rdx, -2248(%rbp)
	jmp .Lbb345
.Lbb343:
	.loc 1 38
	movq %rcx, %r13
	leaq -2120(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_retain
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %eax, %edx
	movq -80(%rbp), %rax
	cmpl $0, %edx
	jnz .Lbb345
	.loc 1 38
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 38
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb345:
	movl -2336(%rbp), %edx
	cmpl $0, %edx
	jz .Lbb354
	movl $0, -2336(%rbp)
	movq -2120(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb354
	movq -16(%rsi), %rdx
	movq $4611686018427387906, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jnz .Lbb353
	movq -32(%rsi), %rdx
	subq $1, %rdx
	jnz .Lbb352
	movq %rcx, %r13
	movq -24(%rsi), %rcx
	cmpq $0, %rcx
	jnz .Lbb351
	.loc 1 38
	leaq -2120(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movq -80(%rbp), %rax
	jmp .Lbb354
.Lbb351:
	movq %r13, %rcx
.Lbb352:
	movq %rdx, -32(%rsi)
.Lbb353:
	movq $0, -2120(%rbp)
.Lbb354:
	movq -2248(%rbp), %rdx
	movq %rdx, -2120(%rbp)
	movl $1, -2336(%rbp)
.Lbb355:
	movq -2120(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb357
	movq %rcx, %r13
	jmp .Lbb361
.Lbb357:
	movq -16(%rdx), %rsi
	movq $6917529027641081858, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb360
	movq -32(%rdx), %rdx
	cmpq $2, %rdx
	jae .Lbb360
	movq %rcx, %r13
	jmp .Lbb361
.Lbb360:
	.loc 1 38
	movq %rcx, %r13
	leaq -2336(%rbp), %rcx
	leaq -2120(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %eax, %ecx
	movq -80(%rbp), %rax
	cmpl $0, %ecx
	jz .Lbb2614
.Lbb361:
	movq -2120(%rbp), %rsi
	movq %rax, -2216(%rbp)
	.loc 1 38
	leaq -2216(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_list_append
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	cmpl $0, %eax
	jnz .Lbb364
	movq %rbx, %rdi
	.loc 1 38
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	movq %rdx, -1240(%rbp)
	ud2
.Lbb364:
	movq -2288(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb372
	movq -16(%rdx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb371
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb370
	movq %rcx, %r13
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb369
	.loc 1 38
	leaq -2288(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	jmp .Lbb372
.Lbb369:
	movq %r13, %rcx
.Lbb370:
	movq %rax, -32(%rdx)
.Lbb371:
	movq $0, -2288(%rbp)
.Lbb372:
	movq myl_lit_4a00641ab05bcbe6d1b38f5b152ad1f7a483fb86c6af5dc0ee9c09d98f25374a(%rip), %rax
	movq %rax, -88(%rbp)
	movq %rax, -2256(%rbp)
	movq -2256(%rbp), %rdx
	movq %rdx, -2248(%rbp)
	movq -2248(%rbp), %rdx
	movq %rdx, -2288(%rbp)
	movl -2336(%rbp), %edx
	testl $0, %edx
	jz .Lbb393
	movq -2120(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb380
	movq -16(%rdx), %rsi
	movq $4611686018427387906, %r8
	andq %rsi, %r8
	cmpq $0, %r8
	jnz .Lbb379
	movq -32(%rdx), %rsi
	addq $1, %rsi
	jz .Lbb377
	movq %rsi, -32(%rdx)
	jmp .Lbb380
.Lbb377:
	movq %rbx, %rdi
	.loc 1 41
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb379:
	movq $4611686018427387904, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb381
.Lbb380:
	movq %rdx, -2248(%rbp)
	jmp .Lbb383
.Lbb381:
	.loc 1 41
	movq %rcx, %r13
	leaq -2120(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_retain
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %eax, %edx
	movq -88(%rbp), %rax
	cmpl $0, %edx
	jnz .Lbb383
	.loc 1 41
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 41
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb383:
	movl -2336(%rbp), %edx
	cmpl $0, %edx
	jz .Lbb392
	movl $0, -2336(%rbp)
	movq -2120(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb392
	movq -16(%rsi), %rdx
	movq $4611686018427387906, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jnz .Lbb391
	movq -32(%rsi), %rdx
	subq $1, %rdx
	jnz .Lbb390
	movq %rcx, %r13
	movq -24(%rsi), %rcx
	cmpq $0, %rcx
	jnz .Lbb389
	.loc 1 41
	leaq -2120(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movq -88(%rbp), %rax
	jmp .Lbb392
.Lbb389:
	movq %r13, %rcx
.Lbb390:
	movq %rdx, -32(%rsi)
.Lbb391:
	movq $0, -2120(%rbp)
.Lbb392:
	movq -2248(%rbp), %rdx
	movq %rdx, -2120(%rbp)
	movl $1, -2336(%rbp)
.Lbb393:
	movq -2120(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb395
	movq %rcx, %r13
	jmp .Lbb399
.Lbb395:
	movq -16(%rdx), %rsi
	movq $6917529027641081858, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb398
	movq -32(%rdx), %rdx
	cmpq $2, %rdx
	jae .Lbb398
	movq %rcx, %r13
	jmp .Lbb399
.Lbb398:
	.loc 1 41
	movq %rcx, %r13
	leaq -2336(%rbp), %rcx
	leaq -2120(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %eax, %ecx
	movq -88(%rbp), %rax
	cmpl $0, %ecx
	jz .Lbb2614
.Lbb399:
	movq -2120(%rbp), %rsi
	movq %rax, -2216(%rbp)
	.loc 1 41
	leaq -2216(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_list_append
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	cmpl $0, %eax
	jnz .Lbb402
	movq %rbx, %rdi
	.loc 1 41
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	movq %rdx, -1240(%rbp)
	ud2
.Lbb402:
	movq -2288(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb410
	movq -16(%rdx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb409
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb408
	movq %rcx, %r13
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb407
	.loc 1 41
	leaq -2288(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	jmp .Lbb410
.Lbb407:
	movq %r13, %rcx
.Lbb408:
	movq %rax, -32(%rdx)
.Lbb409:
	movq $0, -2288(%rbp)
.Lbb410:
	movq myl_lit_18c89eafb781b2d9c652089cbad879e67c59911bcd5c912b177a9a1671c17d8e(%rip), %rax
	movq %rax, -96(%rbp)
	movq %rax, -2256(%rbp)
	movq -2256(%rbp), %rdx
	movq %rdx, -2248(%rbp)
	movq -2248(%rbp), %rdx
	movq %rdx, -2288(%rbp)
	movl -2336(%rbp), %edx
	testl $0, %edx
	jz .Lbb431
	movq -2120(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb418
	movq -16(%rdx), %rsi
	movq $4611686018427387906, %r8
	andq %rsi, %r8
	cmpq $0, %r8
	jnz .Lbb417
	movq -32(%rdx), %rsi
	addq $1, %rsi
	jz .Lbb415
	movq %rsi, -32(%rdx)
	jmp .Lbb418
.Lbb415:
	movq %rbx, %rdi
	.loc 1 44
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb417:
	movq $4611686018427387904, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb419
.Lbb418:
	movq %rdx, -2248(%rbp)
	jmp .Lbb421
.Lbb419:
	.loc 1 44
	movq %rcx, %r13
	leaq -2120(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_retain
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %eax, %edx
	movq -96(%rbp), %rax
	cmpl $0, %edx
	jnz .Lbb421
	.loc 1 44
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 44
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb421:
	movl -2336(%rbp), %edx
	cmpl $0, %edx
	jz .Lbb430
	movl $0, -2336(%rbp)
	movq -2120(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb430
	movq -16(%rsi), %rdx
	movq $4611686018427387906, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jnz .Lbb429
	movq -32(%rsi), %rdx
	subq $1, %rdx
	jnz .Lbb428
	movq %rcx, %r13
	movq -24(%rsi), %rcx
	cmpq $0, %rcx
	jnz .Lbb427
	.loc 1 44
	leaq -2120(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movq -96(%rbp), %rax
	jmp .Lbb430
.Lbb427:
	movq %r13, %rcx
.Lbb428:
	movq %rdx, -32(%rsi)
.Lbb429:
	movq $0, -2120(%rbp)
.Lbb430:
	movq -2248(%rbp), %rdx
	movq %rdx, -2120(%rbp)
	movl $1, -2336(%rbp)
.Lbb431:
	movq -2120(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb433
	movq %rcx, %r13
	jmp .Lbb437
.Lbb433:
	movq -16(%rdx), %rsi
	movq $6917529027641081858, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb436
	movq -32(%rdx), %rdx
	cmpq $2, %rdx
	jae .Lbb436
	movq %rcx, %r13
	jmp .Lbb437
.Lbb436:
	.loc 1 44
	movq %rcx, %r13
	leaq -2336(%rbp), %rcx
	leaq -2120(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %eax, %ecx
	movq -96(%rbp), %rax
	cmpl $0, %ecx
	jz .Lbb2614
.Lbb437:
	movq -2120(%rbp), %rsi
	movq %rax, -2216(%rbp)
	.loc 1 44
	leaq -2216(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_list_append
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	cmpl $0, %eax
	jnz .Lbb440
	movq %rbx, %rdi
	.loc 1 44
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	movq %rdx, -1240(%rbp)
	ud2
.Lbb440:
	movq -2288(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb448
	movq -16(%rdx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb447
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb446
	movq %rcx, %r13
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb445
	.loc 1 44
	leaq -2288(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	jmp .Lbb448
.Lbb445:
	movq %r13, %rcx
.Lbb446:
	movq %rax, -32(%rdx)
.Lbb447:
	movq $0, -2288(%rbp)
.Lbb448:
	movq myl_lit_8a59eb4ce18f56df83810e918f160a659444fbe4f14cc144a8b1ba8df97be02c(%rip), %rax
	movq %rax, -104(%rbp)
	movq %rax, -2256(%rbp)
	movq -2256(%rbp), %rdx
	movq %rdx, -2248(%rbp)
	movq -2248(%rbp), %rdx
	movq %rdx, -2288(%rbp)
	movl -2336(%rbp), %edx
	testl $0, %edx
	jz .Lbb469
	movq -2120(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb456
	movq -16(%rdx), %rsi
	movq $4611686018427387906, %r8
	andq %rsi, %r8
	cmpq $0, %r8
	jnz .Lbb455
	movq -32(%rdx), %rsi
	addq $1, %rsi
	jz .Lbb453
	movq %rsi, -32(%rdx)
	jmp .Lbb456
.Lbb453:
	movq %rbx, %rdi
	.loc 1 47
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb455:
	movq $4611686018427387904, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb457
.Lbb456:
	movq %rdx, -2248(%rbp)
	jmp .Lbb459
.Lbb457:
	.loc 1 47
	movq %rcx, %r13
	leaq -2120(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_retain
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %eax, %edx
	movq -104(%rbp), %rax
	cmpl $0, %edx
	jnz .Lbb459
	.loc 1 47
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 47
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb459:
	movl -2336(%rbp), %edx
	cmpl $0, %edx
	jz .Lbb468
	movl $0, -2336(%rbp)
	movq -2120(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb468
	movq -16(%rsi), %rdx
	movq $4611686018427387906, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jnz .Lbb467
	movq -32(%rsi), %rdx
	subq $1, %rdx
	jnz .Lbb466
	movq %rcx, %r13
	movq -24(%rsi), %rcx
	cmpq $0, %rcx
	jnz .Lbb465
	.loc 1 47
	leaq -2120(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movq -104(%rbp), %rax
	jmp .Lbb468
.Lbb465:
	movq %r13, %rcx
.Lbb466:
	movq %rdx, -32(%rsi)
.Lbb467:
	movq $0, -2120(%rbp)
.Lbb468:
	movq -2248(%rbp), %rdx
	movq %rdx, -2120(%rbp)
	movl $1, -2336(%rbp)
.Lbb469:
	movq -2120(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb471
	movq %rcx, %r13
	jmp .Lbb475
.Lbb471:
	movq -16(%rdx), %rsi
	movq $6917529027641081858, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb474
	movq -32(%rdx), %rdx
	cmpq $2, %rdx
	jae .Lbb474
	movq %rcx, %r13
	jmp .Lbb475
.Lbb474:
	.loc 1 47
	movq %rcx, %r13
	leaq -2336(%rbp), %rcx
	leaq -2120(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %eax, %ecx
	movq -104(%rbp), %rax
	cmpl $0, %ecx
	jz .Lbb2614
.Lbb475:
	movq -2120(%rbp), %rsi
	movq %rax, -2216(%rbp)
	.loc 1 47
	leaq -2216(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_list_append
	movl %r14d, %r9d
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movq -136(%rbp), %rsi
	movl -112(%rbp), %r8d
	movq -120(%rbp), %rdx
	cmpl $0, %eax
	jnz .Lbb478
	movq %rbx, %rdi
	.loc 1 47
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	movq %rdx, -1240(%rbp)
	ud2
.Lbb478:
	movq -2288(%rbp), %r11
	cmpq $0, %r11
	jnz .Lbb480
	movl %r15d, %r10d
	jmp .Lbb488
.Lbb480:
	movq -16(%r11), %rax
	movl %r9d, %r14d
	movq $4611686018427387906, %r9
	andq %r9, %rax
	cmpq $0, %rax
	jnz .Lbb486
	movq -32(%r11), %rax
	subq $1, %rax
	jnz .Lbb485
	movq %rcx, %r13
	movq -24(%r11), %rcx
	cmpq $0, %rcx
	jnz .Lbb484
	.loc 1 47
	leaq -2288(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movl %r15d, %r10d
	movl %r14d, %r9d
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movq -136(%rbp), %rsi
	movl -112(%rbp), %r8d
	movq -120(%rbp), %rdx
	jmp .Lbb488
.Lbb484:
	movq %r13, %rcx
.Lbb485:
	movl %r15d, %r10d
	movl %r14d, %r9d
	movq %rax, -32(%r11)
	jmp .Lbb487
.Lbb486:
	movl %r15d, %r10d
	movl %r14d, %r9d
.Lbb487:
	movq $0, -2288(%rbp)
.Lbb488:
	movq -2120(%rbp), %rax
	movq %rax, -2256(%rbp)
	cmpl $0, %r8d
	jnz .Lbb502
	cmpq $0, %rax
	jnz .Lbb491
	movl %r10d, %r15d
	movl %r9d, %r14d
	jmp .Lbb498
.Lbb491:
	movq -16(%rax), %r8
	movl %r10d, %r15d
	movq $4611686018427387906, %r10
	andq %r8, %r10
	cmpq $0, %r10
	jnz .Lbb497
	movq -32(%rax), %r8
	addq $1, %r8
	jz .Lbb495
	movq %r8, -32(%rax)
	movl %r9d, %r14d
	jmp .Lbb498
.Lbb495:
	movq %rbx, %rdi
	.loc 1 51
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb497:
	movl %r9d, %r14d
	movq $4611686018427387904, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb499
.Lbb498:
	movq %rax, -2248(%rbp)
	jmp .Lbb501
.Lbb499:
	.loc 1 51
	movq %rcx, %r13
	leaq -2256(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_retain
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movq -136(%rbp), %rsi
	movq -120(%rbp), %rdx
	cmpl $0, %eax
	jnz .Lbb501
	.loc 1 51
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 51
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb501:
	movl %r14d, %r9d
	jmp .Lbb510
.Lbb502:
	movl %r10d, %r15d
	movl %r9d, %r14d
	movl %r14d, %r8d
	orl %r15d, %r8d
	jnz .Lbb508
	cmpq $0, %rax
	jz .Lbb506
	movq -16(%rax), %rax
	movq $5764607523034234881, %r8
	andq %r8, %rax
	cmpq $0, %rax
	jnz .Lbb508
.Lbb506:
	movq -2256(%rbp), %rax
	movq %rax, -2248(%rbp)
	movq $0, -2256(%rbp)
	movl %r14d, %r9d
	jmp .Lbb510
.Lbb508:
	.loc 1 51
	movq %rcx, %r13
	leaq -2256(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_take
	movl %r14d, %r9d
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movq -136(%rbp), %rsi
	movq -120(%rbp), %rdx
	cmpl $0, %eax
	jnz .Lbb510
	.loc 1 51
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 51
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb510:
	movq -2248(%rbp), %rax
	movq %rax, -2112(%rbp)
	movl -2336(%rbp), %eax
	cmpl $0, %eax
	jnz .Lbb512
	movl %r15d, %r10d
	jmp .Lbb522
.Lbb512:
	movl $0, -2336(%rbp)
	movq -2120(%rbp), %r8
	cmpq $0, %r8
	jnz .Lbb514
	movl %r15d, %r10d
	jmp .Lbb522
.Lbb514:
	movq -16(%r8), %rax
	movl %r9d, %r14d
	movq $4611686018427387906, %r9
	andq %r9, %rax
	cmpq $0, %rax
	jnz .Lbb520
	movq -32(%r8), %rax
	subq $1, %rax
	jnz .Lbb519
	movq %rcx, %r13
	movq -24(%r8), %rcx
	cmpq $0, %rcx
	jnz .Lbb518
	.loc 1 51
	leaq -2120(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movl %r15d, %r10d
	movl %r14d, %r9d
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movq -136(%rbp), %rsi
	movq -120(%rbp), %rdx
	jmp .Lbb522
.Lbb518:
	movq %r13, %rcx
.Lbb519:
	movl %r15d, %r10d
	movl %r14d, %r9d
	movq %rax, -32(%r8)
	jmp .Lbb521
.Lbb520:
	movl %r15d, %r10d
	movl %r14d, %r9d
.Lbb521:
	movq $0, -2120(%rbp)
.Lbb522:
	movq %rsi, %rax
	movq -2112(%rbp), %rsi
	movq (%rsi), %rsi
	movq %rsi, -144(%rbp)
	movq $9223372036854775807, %r8
	cmpq %r8, %rsi
	ja .Lbb2791
	movq %rcx, %rbx
	movq %rdi, %r15
	movq %rdx, %rdi
	movq %rsi, %rcx
	movq %rax, %rsi
	movl $0, %eax
	movl $2, %r13d
	movl $0, %r8d
	movl $2, %r14d
	movq $-1, %r12
	movl $0, %edx
.p2align 4
.Lbb524:
	movl %eax, -1540(%rbp)
	movl %r13d, -1520(%rbp)
	movq %r12, -1184(%rbp)
	movq %rcx, -1840(%rbp)
	cmpq %rcx, %rdx
	setl %cl
	movzbq %cl, %rcx
	cmpl $0, %ecx
	jz .Lbb615
	movq -2112(%rbp), %rcx
	movq %rcx, -2256(%rbp)
	movl %r14d, %r11d
	andl $24, %r11d
	cmpl $0, %r11d
	setz %r11b
	movzbl %r11b, %r11d
	andl %r8d, %r11d
	cmpl $0, %r11d
	jnz .Lbb551
	cmpq $0, %rcx
	jz .Lbb532
	movq -16(%rcx), %r9
	movq $4611686018427387906, %r10
	andq %r10, %r9
	cmpq $0, %r9
	jnz .Lbb532
	movq -24(%rcx), %r9
	addq $1, %r9
	jz .Lbb530
	movq %r9, -24(%rcx)
	jmp .Lbb532
.Lbb530:
	movq -1224(%rbp), %rdi
	.loc 1 67
	movl $2, %esi
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb532:
	movq %rcx, -2248(%rbp)
	cmpl $0, %r8d
	jz .Lbb550
	testl $28, %r14d
	jnz .Lbb542
	movq -2288(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb550
	movq -16(%r8), %rcx
	movq $4611686018427387906, %r9
	andq %r9, %rcx
	cmpq $0, %rcx
	jnz .Lbb541
	movq -32(%r8), %rcx
	subq $1, %rcx
	jnz .Lbb540
	movq %rdx, %r14
	movq -24(%r8), %rdx
	cmpq $0, %rdx
	jnz .Lbb539
	.loc 1 67
	leaq -2288(%rbp), %rsi
	movq %r15, %rdi
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r14, %rdx
	movq -136(%rbp), %rsi
	movl -1540(%rbp), %eax
	movq -120(%rbp), %rdi
	jmp .Lbb550
.Lbb539:
	movq %r14, %rdx
.Lbb540:
	movq %rcx, -32(%r8)
.Lbb541:
	movq $0, -2288(%rbp)
	jmp .Lbb550
.Lbb542:
	movq -2288(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb550
	movq -16(%r8), %rcx
	movq $4611686018427387906, %r9
	andq %r9, %rcx
	cmpq $0, %rcx
	jnz .Lbb549
	movq -24(%r8), %rcx
	subq $1, %rcx
	jnz .Lbb548
	movq %rdx, %r14
	movq -32(%r8), %rdx
	cmpq $0, %rdx
	jnz .Lbb547
	.loc 1 67
	leaq -2288(%rbp), %rsi
	movq %r15, %rdi
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r14, %rdx
	movq -136(%rbp), %rsi
	movl -1540(%rbp), %eax
	movq -120(%rbp), %rdi
	jmp .Lbb550
.Lbb547:
	movq %r14, %rdx
.Lbb548:
	movq %rcx, -24(%r8)
.Lbb549:
	movq $0, -2288(%rbp)
.Lbb550:
	movl $16, %r14d
	jmp .Lbb558
.Lbb551:
	movl %r10d, %r14d
	movl %r9d, %r8d
	orl %r14d, %r8d
	jnz .Lbb556
	cmpq $0, %rcx
	jz .Lbb555
	movq -16(%rcx), %rcx
	movq $5764607523034234881, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jnz .Lbb556
.Lbb555:
	movq -2256(%rbp), %rcx
	movq %rcx, -2248(%rbp)
	movq $0, -2256(%rbp)
	jmp .Lbb557
.Lbb556:
	.loc 1 67
	movl %ebx, %ecx
	movq %rdx, %r14
	leaq -2256(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %r15, %rdi
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_take
	movq %rdx, -1240(%rbp)
	movq %r14, %rdx
	movl %eax, %ecx
	movq -136(%rbp), %rsi
	movl -1540(%rbp), %eax
	movq -120(%rbp), %rdi
	cmpl $0, %ecx
	jz .Lbb613
.Lbb557:
	movl $2, %r14d
.Lbb558:
	cmpl $0, %eax
	jz .Lbb576
	testl $28, %r13d
	jnz .Lbb568
	movq -2104(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb576
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r8
	andq %r8, %rax
	cmpq $0, %rax
	jnz .Lbb567
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb566
	movq %rdx, %r13
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb565
	.loc 1 67
	leaq -2104(%rbp), %rsi
	movq %r15, %rdi
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r13, %rdx
	movq -136(%rbp), %rsi
	movq -120(%rbp), %rdi
	jmp .Lbb576
.Lbb565:
	movq %r13, %rdx
.Lbb566:
	movq %rax, -32(%rcx)
.Lbb567:
	movq $0, -2104(%rbp)
	jmp .Lbb576
.Lbb568:
	movq -2104(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb576
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r8
	andq %r8, %rax
	cmpq $0, %rax
	jnz .Lbb575
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb574
	movq %rdx, %r13
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb573
	.loc 1 67
	leaq -2104(%rbp), %rsi
	movq %r15, %rdi
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r13, %rdx
	movq -136(%rbp), %rsi
	movq -120(%rbp), %rdi
	jmp .Lbb576
.Lbb573:
	movq %r13, %rdx
.Lbb574:
	movq %rax, -24(%rcx)
.Lbb575:
	movq $0, -2104(%rbp)
.Lbb576:
	movq -2248(%rbp), %rax
	movq %rax, -2104(%rbp)
	movq $0, -1840(%rbp)
	cmpq $0, %rdx
	jl .Lbb578
	movq %rdx, %r13
	jmp .Lbb580
.Lbb578:
	movq -2104(%rbp), %rax
	movq (%rax), %rax
	movq $9223372036854775807, %rcx
	cmpq %rcx, %rax
	ja .Lbb611
	movq %rdx, -1840(%rbp)
	movq %rax, %r13
	addq %rdx, %r13
	movq %rax, %rcx
	xorq %r13, %rcx
	movq %rdx, %r8
	xorq %r13, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jl .Lbb609
.Lbb580:
	movq -2104(%rbp), %rax
	movq (%rax), %rcx
	cmpq %rcx, %r13
	jae .Lbb607
	movq 32(%rax), %rcx
	movq %rdi, %rax
	movq (%rcx, %r13, 8), %rdi
	movq %rdi, -2256(%rbp)
	cmpq $0, %rdi
	jz .Lbb587
	movq -16(%rdi), %rcx
	movq $4611686018427387906, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jnz .Lbb587
	movq -24(%rdi), %rcx
	addq $1, %rcx
	jz .Lbb585
	movq %rcx, -24(%rdi)
	jmp .Lbb587
.Lbb585:
	movq -1224(%rbp), %rdi
	.loc 1 80
	movl $2, %esi
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb587:
	movq %rdi, -2248(%rbp)
	movq -2248(%rbp), %rcx
	movq %rcx, -2288(%rbp)
	movq -2128(%rbp), %rcx
	movq %rcx, -1840(%rbp)
	movq $0, -1840(%rbp)
	movq $0, -1840(%rbp)
	movq $0, -1832(%rbp)
	movq $0, -1840(%rbp)
	movq %rsi, -1840(%rbp)
	movq %rdx, %r13
	movq (%rcx), %rdx
	cmpq %rdx, %rsi
	jae .Lbb605
	movq 32(%rcx), %rcx
	movq (%rcx, %rax, 1), %rsi
	movq %rsi, -1840(%rbp)
	.loc 1 96
	callq myl_native_text_equal
	movq %rdx, -1240(%rbp)
	movq %r13, %rdx
	movl %eax, %r9d
	movl -124(%rbp), %r8d
	movq -136(%rbp), %rsi
	movq -120(%rbp), %rdi
	movq -144(%rbp), %rcx
	movl -496(%rbp), %eax
	movq %rdx, %r13
	movl -500(%rbp), %edx
	movl %r9d, -128(%rbp)
	movq -2288(%rbp), %r11
	cmpq $0, %r11
	jnz .Lbb590
	xchgq %r13, %rdx
	jmp .Lbb599
.Lbb590:
	movq -16(%r11), %r8
	movq $4611686018427387906, %r10
	andq %r8, %r10
	movl -124(%rbp), %r8d
	cmpq $0, %r10
	jnz .Lbb597
	movq -24(%r11), %r10
	subq $1, %r10
	jz .Lbb593
	xchgq %r13, %rdx
	jmp .Lbb596
.Lbb593:
	movq -32(%r11), %r8
	cmpq $0, %r8
	movl -124(%rbp), %r8d
	jnz .Lbb595
	.loc 1 96
	leaq -2288(%rbp), %rsi
	movq %r15, %rdi
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r13, %rdx
	movl -124(%rbp), %r8d
	movq -136(%rbp), %rsi
	movl -128(%rbp), %r9d
	movq -120(%rbp), %rdi
	movq -144(%rbp), %rcx
	movl -496(%rbp), %eax
	movl -500(%rbp), %r13d
	jmp .Lbb599
.Lbb595:
	xchgq %r13, %rdx
.Lbb596:
	movq %r10, -24(%r11)
	jmp .Lbb598
.Lbb597:
	xchgq %r13, %rdx
.Lbb598:
	movq $0, -2288(%rbp)
.Lbb599:
	movl %r9d, %r9d
	cmpl $0, %r9d
	cmovnz %rdx, %r12
	movq $1, -1840(%rbp)
	movq $9223372036854775806, %r9
	cmpq %r9, %rdx
	jg .Lbb603
	addq $1, %rdx
	movl %eax, %r10d
	movl %r13d, %r9d
	movl $1, %eax
	movl %r14d, %r13d
	movl $16, %r14d
	jmp .Lbb524
.Lbb603:
	movq %rdx, %rcx
	movq -1224(%rbp), %rdi
	.loc 1 102
	movl $64, %r8d
	movq %rcx, %rbx
	movl $1, %ecx
	movq %rbx, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb605:
	movq -136(%rbp), %rsi
	movq -1224(%rbp), %rdi
	.loc 1 95
	movq %rdx, -1240(%rbp)
	callq myl_qbe_fail_normalized_index_bounds
	movq %rdx, -1240(%rbp)
	ud2
.Lbb607:
	movq %rcx, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 80
	movq %rdx, -1240(%rbp)
	movq %r13, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	movq %rdx, -1240(%rbp)
	ud2
.Lbb609:
	movq %rdx, %rcx
	movq %rax, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 77
	movl $64, %r8d
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb611:
	movq %rax, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 75
	movl $320, %edx
	movq %rdx, -1240(%rbp)
	movq %rdi, %rbx
	callq myl_qbe_fail_cast
	movq %rdx, -1240(%rbp)
	ud2
.Lbb613:
	movq %r15, %rdi
	movq -1224(%rbp), %rbx
	.loc 1 67
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 67
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb615:
	movq -160(%rbp), %rsi
	movq %r15, %rdi
	movl %r8d, %r15d
	movq -152(%rbp), %rcx
	movq -1224(%rbp), %rbx
	movq $0, -1840(%rbp)
	cmpq $0, %r12
	jl .Lbb2709
	movq -2128(%rbp), %rax
	movq $0, -1840(%rbp)
	movq (%rax), %rdx
	cmpq %rdx, %rsi
	jb .Lbb620
	movq %rbx, %rdi
	.loc 1 125
	movq %rdx, -1240(%rbp)
	movq %rdi, %rbx
	callq myl_qbe_fail_normalized_index_bounds
	movq %rdx, -1240(%rbp)
	ud2
.Lbb620:
	movq 32(%rax), %rax
	movq (%rax, %rcx, 1), %rsi
	.loc 1 126
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_f_ea553995adf89bda71aacc499924ca857ef3837e6859fa5807b5db027815f66e
	movl %r15d, %r8d
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movq %rax, %rdx
	movq -176(%rbp), %rsi
	movq -168(%rbp), %rcx
	movq %rdx, -448(%rbp)
	cmpl $0, %r8d
	jnz .Lbb622
	movl %r8d, -196(%rbp)
	jmp .Lbb641
.Lbb622:
	testl $28, %r14d
	jnz .Lbb632
	movq -2288(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb631
	movq -16(%r8), %rax
	movq $4611686018427387906, %r9
	andq %r9, %rax
	cmpq $0, %rax
	jnz .Lbb630
	movq -32(%r8), %rax
	subq $1, %rax
	jnz .Lbb629
	movq %rdx, %r15
	movq -24(%r8), %rdx
	cmpq $0, %rdx
	jnz .Lbb628
	.loc 1 126
	leaq -2288(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r15, %rdx
	movq %r12, %rdi
	movq -176(%rbp), %rsi
	movq -168(%rbp), %rcx
	jmp .Lbb631
.Lbb628:
	movq %r15, %rdx
.Lbb629:
	movq %rax, -32(%r8)
.Lbb630:
	movq $0, -2288(%rbp)
.Lbb631:
	movl $0, -196(%rbp)
	jmp .Lbb641
.Lbb632:
	movq -2288(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb640
	movq -16(%r8), %rax
	movq $4611686018427387906, %r9
	andq %r9, %rax
	cmpq $0, %rax
	jnz .Lbb639
	movq -24(%r8), %rax
	subq $1, %rax
	jnz .Lbb638
	movq %rdx, %r15
	movq -32(%r8), %rdx
	cmpq $0, %rdx
	jnz .Lbb637
	.loc 1 126
	leaq -2288(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r15, %rdx
	movq %r12, %rdi
	movq -176(%rbp), %rsi
	movq -168(%rbp), %rcx
	jmp .Lbb640
.Lbb637:
	movq %r15, %rdx
.Lbb638:
	movq %rax, -24(%r8)
.Lbb639:
	movq $0, -2288(%rbp)
.Lbb640:
	movl $0, -196(%rbp)
.Lbb641:
	movq -2128(%rbp), %rax
	movq $0, -1840(%rbp)
	movq %rdx, %r15
	movq (%rax), %rdx
	cmpq %rdx, %rsi
	jb .Lbb644
	movq %rbx, %rdi
	.loc 1 142
	movq %rdx, -1240(%rbp)
	movq %rdi, %rbx
	callq myl_qbe_fail_normalized_index_bounds
	movq %rdx, -1240(%rbp)
	ud2
.Lbb644:
	movq 32(%rax), %rax
	movq (%rax, %rcx, 1), %rsi
	.loc 1 143
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_f_ea553995adf89bda71aacc499924ca857ef3837e6859fa5807b5db027815f66e
	movq %rdx, -1240(%rbp)
	movq %r15, %rdx
	movq %r12, %rdi
	movq %rax, -1472(%rbp)
	movq -192(%rbp), %rsi
	movl -196(%rbp), %r12d
	movq -184(%rbp), %rcx
	cmpl $0, %r12d
	jnz .Lbb646
	movl %r12d, -200(%rbp)
	jmp .Lbb665
.Lbb646:
	testl $28, %r14d
	jnz .Lbb656
	movq -2288(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb655
	movq -16(%r8), %rax
	movq $4611686018427387906, %r9
	andq %r9, %rax
	cmpq $0, %rax
	jnz .Lbb654
	movq -32(%r8), %rax
	subq $1, %rax
	jnz .Lbb653
	movq %rdx, %r15
	movq -24(%r8), %rdx
	cmpq $0, %rdx
	jnz .Lbb652
	.loc 1 143
	leaq -2288(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r15, %rdx
	movq %r12, %rdi
	movq -192(%rbp), %rsi
	movq -184(%rbp), %rcx
	jmp .Lbb655
.Lbb652:
	movq %r15, %rdx
.Lbb653:
	movq %rax, -32(%r8)
.Lbb654:
	movq $0, -2288(%rbp)
.Lbb655:
	movl $0, -200(%rbp)
	jmp .Lbb665
.Lbb656:
	movq -2288(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb664
	movq -16(%r8), %rax
	movq $4611686018427387906, %r9
	andq %r9, %rax
	cmpq $0, %rax
	jnz .Lbb663
	movq -24(%r8), %rax
	subq $1, %rax
	jnz .Lbb662
	movq %rdx, %r15
	movq -32(%r8), %rdx
	cmpq $0, %rdx
	jnz .Lbb661
	.loc 1 143
	leaq -2288(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r15, %rdx
	movq %r12, %rdi
	movq -192(%rbp), %rsi
	movq -184(%rbp), %rcx
	jmp .Lbb664
.Lbb661:
	movq %r15, %rdx
.Lbb662:
	movq %rax, -24(%r8)
.Lbb663:
	movq $0, -2288(%rbp)
.Lbb664:
	movl $0, -200(%rbp)
.Lbb665:
	movq -2128(%rbp), %rax
	movq $0, -1840(%rbp)
	movq %rdx, %r15
	movq (%rax), %rdx
	cmpq %rdx, %rsi
	jb .Lbb668
	movq %rbx, %rdi
	.loc 1 159
	movq %rdx, -1240(%rbp)
	movq %rdi, %rbx
	callq myl_qbe_fail_normalized_index_bounds
	movq %rdx, -1240(%rbp)
	ud2
.Lbb668:
	movq 32(%rax), %rax
	movq (%rax, %rcx, 1), %rsi
	.loc 1 160
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_f_ea553995adf89bda71aacc499924ca857ef3837e6859fa5807b5db027815f66e
	movq %rdx, -1240(%rbp)
	movq %r15, %rdx
	movq %r12, %rdi
	movq %rax, %r8
	movl -200(%rbp), %r12d
	movl -1540(%rbp), %eax
	movq -1472(%rbp), %rsi
	movq %r8, -1200(%rbp)
	cmpl $0, %r12d
	jnz .Lbb670
	movq %r8, %r14
	movq %rdx, %r12
	jmp .Lbb691
.Lbb670:
	testl $28, %r14d
	jnz .Lbb681
	movq -2288(%rbp), %r9
	cmpq $0, %r9
	jz .Lbb680
	movq -16(%r9), %rcx
	movq %r8, %r15
	movq $4611686018427387906, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jnz .Lbb678
	movq -32(%r9), %rcx
	subq $1, %rcx
	jnz .Lbb677
	movq %rdx, %r14
	movq -24(%r9), %rdx
	cmpq $0, %rdx
	jnz .Lbb676
	.loc 1 160
	leaq -2288(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_drop
	movq %r15, %r8
	movq %rdx, -1240(%rbp)
	movq %r14, %rdx
	movq %r12, %rdi
	movl -1540(%rbp), %eax
	movq -1472(%rbp), %rsi
	jmp .Lbb680
.Lbb676:
	movq %r14, %rdx
.Lbb677:
	movq %r15, %r8
	movq %rcx, -32(%r9)
	jmp .Lbb679
.Lbb678:
	movq %r15, %r8
.Lbb679:
	movq $0, -2288(%rbp)
.Lbb680:
	movq %r8, %r14
	movq %rdx, %r12
	jmp .Lbb691
.Lbb681:
	movq %rdx, %r12
	movq -2288(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb683
	movq %r8, %r14
	jmp .Lbb691
.Lbb683:
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %r9
	andq %r9, %rcx
	cmpq $0, %rcx
	jnz .Lbb689
	movq -24(%rdx), %rcx
	subq $1, %rcx
	jz .Lbb686
	movq %r8, %r14
	jmp .Lbb688
.Lbb686:
	movq %r8, %r14
	movq -32(%rdx), %r8
	cmpq $0, %r8
	jnz .Lbb688
	.loc 1 160
	leaq -2288(%rbp), %rsi
	movq %rdi, %r15
	callq myl_t_8c25cb3686462e9a86d2883c5688a22fe738b0bbc85f458d2d2b5f3f667c6d5a_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r15, %rdi
	movl -1540(%rbp), %eax
	movq -1472(%rbp), %rsi
	jmp .Lbb691
.Lbb688:
	movq %rcx, -24(%rdx)
	jmp .Lbb690
.Lbb689:
	movq %r8, %r14
.Lbb690:
	movq $0, -2288(%rbp)
.Lbb691:
	movq $2, -1840(%rbp)
	cmpq $2, %r12
	jl .Lbb693
	movq $1, -1840(%rbp)
	cmpq $1, %rsi
	setl %cl
	movzbq %cl, %rcx
	jmp .Lbb694
.Lbb693:
	movl $1, %ecx
.Lbb694:
	cmpl $0, %ecx
	jnz .Lbb696
	movq $1, -1840(%rbp)
	cmpq $1, %r14
	setl %cl
	movzbq %cl, %rcx
	jmp .Lbb697
.Lbb696:
	movl $1, %ecx
.Lbb697:
	cmpl $0, %ecx
	jnz .Lbb699
	movq $1000000, -1840(%rbp)
	cmpq $1000000, %r14
	setg %cl
	movzbq %cl, %rcx
	jmp .Lbb700
.Lbb699:
	movl $1, %ecx
.Lbb700:
	cmpl $0, %ecx
	jnz .Lbb2627
	movq %r12, -1840(%rbp)
	cmpq $0, %r12
	setg %al
	movzbq %al, %rax
	movq %r12, %rcx
	xorq %r12, %rcx
	movq %r12, %r13
	andq %rcx, %r13
	movq %r13, -456(%rbp)
	cmpq $0, %r12
	setl %r10b
	movzbq %r10b, %r10
	movq %r10, -520(%rbp)
	cmpl $0, %eax
	jnz .Lbb703
	movl $0, %edx
	jmp .Lbb706
.Lbb703:
	movq $0, -1840(%rbp)
	movq $0, -1840(%rbp)
	cmpq $0, %r13
	jl .Lbb2625
	cmpq $0, %r12
	jl .Lbb2623
	movq %r12, %rdx
.Lbb706:
	.loc 1 228
	movq %rdx, -1240(%rbp)
	movq myl_t_1a91deb3742283487d66c3b500f6effd7ef1170e6d4b4368fe9ec3c3f0354fda@gotpcrel(%rip), %rsi
	movq %rdi, %r13
	callq myl_native_list_new
	movq %r13, %rdi
	movl -204(%rbp), %r13d
	movq -488(%rbp), %rcx
	movl -496(%rbp), %r10d
	movl -500(%rbp), %r9d
	cmpl $0, %eax
	jnz .Lbb709
	movq %rbx, %rdi
	.loc 1 228
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	movq %rdx, -1240(%rbp)
	ud2
.Lbb709:
	movq %rax, -2256(%rbp)
	movq -2256(%rbp), %rsi
	movq %rsi, -2248(%rbp)
	movq -2248(%rbp), %rsi
	movq %rsi, -2288(%rbp)
	movq %rax, -2256(%rbp)
	movl %r9d, %esi
	orl %r10d, %esi
	jnz .Lbb714
	cmpq $0, %rax
	jz .Lbb712
	movq -16(%rax), %rax
	movq $5764607523034234881, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb714
.Lbb712:
	movq -2256(%rbp), %rax
	movq %rax, -2248(%rbp)
	movq $0, -2256(%rbp)
	movq %r14, %r8
	jmp .Lbb716
.Lbb714:
	movq %r12, %rdx
	.loc 1 229
	movq %rdx, %r12
	leaq -2256(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_take
	movq %r14, %r8
	movq %r13, %rdi
	movl -204(%rbp), %r13d
	movq -488(%rbp), %rcx
	cmpl $0, %eax
	jnz .Lbb716
	.loc 1 229
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 229
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb716:
	movl -2328(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb725
	movl $0, -2328(%rbp)
	movq -2096(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb725
	movq -16(%rsi), %rax
	movq $4611686018427387906, %r9
	andq %r9, %rax
	cmpq $0, %rax
	jnz .Lbb724
	movq -32(%rsi), %rax
	subq $1, %rax
	jnz .Lbb723
	movq %r8, %r14
	movq -24(%rsi), %r8
	cmpq $0, %r8
	jnz .Lbb722
	.loc 1 229
	leaq -2096(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %r14, %r8
	movq %r13, %rdi
	movl -204(%rbp), %r13d
	movq -488(%rbp), %rcx
	jmp .Lbb725
.Lbb722:
	movq %r14, %r8
.Lbb723:
	movq %rax, -32(%rsi)
.Lbb724:
	movq $0, -2096(%rbp)
.Lbb725:
	movq -2248(%rbp), %rax
	movq %rax, -2096(%rbp)
	movl $1, -2328(%rbp)
	cmpl $16, %r13d
	jz .Lbb727
	movq %r8, %r14
	jmp .Lbb758
.Lbb727:
	movq -2096(%rbp), %rax
	cmpq $0, %rax
	jnz .Lbb729
	movq %r8, %r14
	jmp .Lbb736
.Lbb729:
	movq -16(%rax), %rsi
	movq $4611686018427387906, %r9
	andq %rsi, %r9
	cmpq $0, %r9
	jnz .Lbb735
	movq -32(%rax), %rcx
	addq $1, %rcx
	jz .Lbb733
	movq %rcx, -32(%rax)
	movq %r8, %r14
	jmp .Lbb736
.Lbb733:
	movq %rbx, %rdi
	.loc 1 230
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb735:
	movq %r8, %r14
	movq $4611686018427387904, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb737
.Lbb736:
	movq %rax, -2248(%rbp)
	jmp .Lbb740
.Lbb737:
	movq %r12, %rdx
	.loc 1 230
	movq %rdx, %r12
	leaq -2096(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_retain
	movq %r13, %rdi
	movl -204(%rbp), %r13d
	cmpl $0, %eax
	jnz .Lbb740
	.loc 1 230
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 230
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb740:
	movl -2328(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb756
	movl $0, -2328(%rbp)
	testl $28, %r13d
	jnz .Lbb749
	movq -2096(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb756
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb748
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb747
	movq -24(%rcx), %rsi
	cmpq $0, %rsi
	jnz .Lbb747
	.loc 1 230
	leaq -2096(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %r13, %rdi
	jmp .Lbb756
.Lbb747:
	movq %rax, -32(%rcx)
.Lbb748:
	movq $0, -2096(%rbp)
	jmp .Lbb756
.Lbb749:
	movq -2096(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb756
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb755
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb754
	movq -32(%rcx), %rsi
	cmpq $0, %rsi
	jnz .Lbb754
	.loc 1 230
	leaq -2096(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movq %r13, %rdi
	jmp .Lbb756
.Lbb754:
	movq %rax, -24(%rcx)
.Lbb755:
	movq $0, -2096(%rbp)
.Lbb756:
	movq -2248(%rbp), %rax
	movq %rax, -2096(%rbp)
	movl $1, -2328(%rbp)
	movl $2, %r13d
.Lbb758:
	movl %r13d, -208(%rbp)
	cmpl $8, %r13d
	jz .Lbb766
	movq -2096(%rbp), %rax
	cmpq $0, %rax
	jnz .Lbb761
	movq %r12, %r13
	jmp .Lbb765
.Lbb761:
	movq -16(%rax), %rcx
	movq $6917529027641081858, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb764
	movq -32(%rax), %rax
	cmpq $2, %rax
	jae .Lbb764
	movq %r12, %r13
	jmp .Lbb765
.Lbb764:
	movq %r12, %rdx
	.loc 1 230
	leaq -2328(%rbp), %rcx
	movq %rdx, %r13
	leaq -2096(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %r12, %rdi
	cmpl $0, %eax
	jz .Lbb2614
.Lbb765:
	movq %r14, %r8
	movl $2, -1544(%rbp)
	jmp .Lbb774
.Lbb766:
	xchgq %r13, %r12
	movq -2096(%rbp), %rax
	cmpq $0, %rax
	jnz .Lbb769
	movq %r14, %r8
	jmp .Lbb773
.Lbb769:
	movq -16(%rax), %rcx
	movq $6917529027641081858, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb772
	movq -32(%rax), %rax
	cmpq $2, %rax
	jae .Lbb772
	movq %r14, %r8
	jmp .Lbb773
.Lbb772:
	movq %r13, %rdx
	.loc 1 230
	movl $0, %ecx
	movq %rdx, %r13
	leaq -2096(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_held
	movq %r14, %r8
	movq %r12, %rdi
	movl -208(%rbp), %r12d
	cmpl $0, %eax
	jz .Lbb2614
.Lbb773:
	movl %r12d, -1544(%rbp)
.Lbb774:
	cmpq $0, %r13
	setg %sil
	movzbq %sil, %rsi
	movq %rsi, -296(%rbp)
	cmpq $16, %r13
	movq %r8, %r14
	setae %r8b
	movzbq %r8b, %r8
	movq %r8, -288(%rbp)
	testq %rsi, %r8
	jnz .Lbb776
	movq %rdi, %r15
	movq %r14, %r8
	movq %r13, %r12
	movl $0, %ecx
	movl $0, %ebx
	jmp .Lbb786
.Lbb776:
	movq $144115188075855872, %rax
	movq %r13, %rcx
	addq %rax, %rcx
	movq $288230376151711744, %rax
	cmpq %rax, %rcx
	jbe .Lbb778
	movq %rdi, %r15
	movq %r14, %r8
	movq %r13, %r12
	movl $0, %ecx
	movl $0, %ebx
	jmp .Lbb786
.Lbb778:
	movq $144115188075855872, %rax
	movq %r14, %rcx
	addq %rax, %rcx
	movq $288230376151711744, %rax
	cmpq %rax, %rcx
	jbe .Lbb780
	movq %rdi, %r15
	movq %r14, %r8
	movq %r13, %r12
	movl $0, %ecx
	movl $0, %ebx
	jmp .Lbb786
.Lbb780:
	movq -2096(%rbp), %rsi
	movq 8(%rsi), %rax
	movq (%rsi), %rcx
	movq %rcx, -224(%rbp)
	subq %rcx, %rax
	cmpq %r13, %rax
	jae .Lbb782
	movq %rdi, %r15
	movq %r14, %r8
	movq %r13, %r12
	movl $0, %ecx
	movl $0, %ebx
	jmp .Lbb786
.Lbb782:
	movq 32(%rsi), %r10
	movq %r10, -232(%rbp)
	movq 16(%rsi), %rcx
	movq %rcx, -216(%rbp)
	.loc 1 230
	movq %rdi, %r12
	callq myl_rc_list_plain_ready
	movq %r14, %r8
	movq %r12, %rdi
	movq -216(%rbp), %rsi
	movq -232(%rbp), %r10
	movq -1184(%rbp), %r12
	movq -224(%rbp), %rcx
	cmpl $0, %eax
	jnz .Lbb784
	movq %rdi, %r15
	movq %r13, %r12
	movl $0, %ecx
	movl $0, %ebx
	jmp .Lbb786
.Lbb784:
	movq $4611686018427387904, %rax
	cmpq %rax, %rsi
	jb .Lbb806
	movq %rdi, %r15
	movq %r13, %r12
	movl $0, %ecx
	movl $0, %ebx
.p2align 4
.Lbb786:
	movq %r12, -1840(%rbp)
	cmpq %r12, %rbx
	jge .Lbb805
	movq %rbx, -1840(%rbp)
	movq $37, -1832(%rbp)
	imulq $37, %rbx, %rax
	movl $4294967295, %esi
	movq %rbx, %r10
	andq %rsi, %r10
	movq %rbx, %r9
	shrq $32, %r9
	imulq $37, %r10, %rsi
	shrq $32, %rsi
	imulq $37, %r9, %rdi
	addq %rsi, %rdi
	movl $4294967295, %esi
	andq %rdi, %rsi
	shrq $32, %rdi
	imulq $0, %r10, %r10
	addq %r10, %rsi
	shrq $32, %rsi
	imulq $0, %r9, %r9
	addq %r9, %rdi
	addq %rdi, %rsi
	cmpq $0, %rbx
	setl %dil
	movzbq %dil, %rdi
	negq %rdi
	movq %rdi, %r9
	andq $37, %r9
	movq %rbx, %rdi
	andq $0, %rdi
	subq %r9, %rsi
	subq %rdi, %rsi
	movq %rax, %rdi
	sarq $63, %rdi
	cmpq %rsi, %rdi
	jnz .Lbb803
	movq %rax, -1840(%rbp)
	movq %r8, %rdi
	addq %rax, %rdi
	movq %r8, %rsi
	xorq %rdi, %rsi
	movq %rax, %r9
	xorq %rdi, %r9
	andq %r9, %rsi
	cmpq $0, %rsi
	jl .Lbb801
	movq $1009, -1840(%rbp)
	movq %rdi, %rsi
	sarq $63, %rsi
	movq %rsi, %rax
	xorq %rdi, %rax
	subq %rsi, %rax
	movq $-9086255505087856445, %r9
	mulq %r9
	movq %rdx, %rax
	shrq $9, %rax
	xorq %rsi, %rax
	subq %rsi, %rax
	imulq $1009, %rax, %rax
	negq %rax
	addq %rdi, %rax
	cmpq $0, %rax
	setnz %dil
	movzbq %dil, %rdi
	andq %rdi, %rsi
	negq %rsi
	andq $1009, %rsi
	movq %rax, %r9
	addq %rsi, %r9
	movq %r9, -248(%rbp)
	movq -2096(%rbp), %rsi
	movq %rsi, -264(%rbp)
	movq (%rsi), %rdi
	movq %rdi, -256(%rbp)
	movq %r8, %r13
	movq 8(%rsi), %r8
	movq 16(%rsi), %rax
	movq %rax, -240(%rbp)
	cmpq %r8, %rdi
	jae .Lbb792
	cmpl $0, %ecx
	jnz .Lbb796
	.loc 1 241
	movq %r15, %rdi
	callq myl_rc_list_plain_ready
	movl %eax, %ecx
	movq -240(%rbp), %rax
	movq -256(%rbp), %rdi
	movq -264(%rbp), %rsi
	movq -248(%rbp), %r9
	cmpl $0, %ecx
	jnz .Lbb796
.Lbb792:
	movq %r9, -2216(%rbp)
	.loc 1 241
	leaq -2216(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq %r15, %rdi
	callq myl_rc_list_append
	movq %r13, %r8
	cmpl $0, %eax
	jz .Lbb794
	movl $0, %ecx
	jmp .Lbb797
.Lbb794:
	movq -1224(%rbp), %rdi
	.loc 1 241
	callq myl_qbe_fail_allocation
	movq %rdx, -1240(%rbp)
	ud2
.Lbb796:
	movq %r13, %r8
	movq 32(%rsi), %r10
	movq %r9, (%r10, %rdi, 8)
	addq $1, %rdi
	movq %rdi, (%rsi)
	addq $1, %rax
	movq %rax, 16(%rsi)
.Lbb797:
	movq $1, -1840(%rbp)
	movq $9223372036854775806, %rax
	cmpq %rax, %rbx
	jg .Lbb799
	addq $1, %rbx
	jmp .Lbb786
.Lbb799:
	movq %rbx, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 245
	movl $64, %r8d
	movl $1, %ecx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb801:
	movq %rax, %rcx
	movq -1224(%rbp), %rdi
	.loc 1 238
	movq %r8, %rbx
	movl $64, %r8d
	movq %rbx, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb803:
	movq %rbx, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 237
	movl $64, %r8d
	movl $37, %ecx
	movq %rdx, -1240(%rbp)
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb805:
	movl -268(%rbp), %esi
	movq -488(%rbp), %rcx
	movq %r15, %rdi
	movl -1544(%rbp), %r15d
	movq %r12, %rdx
	movq -456(%rbp), %r12
	movl -496(%rbp), %r10d
	movl -500(%rbp), %r9d
	movq -1224(%rbp), %rbx
	jmp .Lbb811
.Lbb806:
	movq %rdi, %r15
	movq %rbx, %rdi
	movq %r12, %rbx
	movq %r13, %r12
	movl $0, %r9d
.p2align 4
.Lbb807:
	movq %r12, -1840(%rbp)
	cmpq %r12, %r9
	jge .Lbb810
	movq %r9, -1840(%rbp)
	movq $37, -1832(%rbp)
	imulq $37, %r9, %rax
	movq %rax, -1840(%rbp)
	movq %r8, %r13
	addq %rax, %r13
	movq $1009, -1840(%rbp)
	movq %r13, %r11
	sarq $63, %r11
	movq %r13, %rax
	xorq %r11, %rax
	subq %r11, %rax
	movq $-9086255505087856445, %r14
	mulq %r14
	movq %rdx, %rax
	shrq $9, %rax
	xorq %r11, %rax
	subq %r11, %rax
	imulq $1009, %rax, %rax
	negq %rax
	addq %r13, %rax
	cmpq $0, %rax
	movq %rbx, %r13
	setnz %bl
	movzbq %bl, %rbx
	andq %rbx, %r11
	negq %r11
	andq $1009, %r11
	addq %rax, %r11
	movq -2096(%rbp), %rax
	movq %r11, (%r10, %rcx, 8)
	addq $1, %rcx
	movq %rcx, (%rax)
	addq $1, %rsi
	movq %rsi, 16(%rax)
	movq $1, -1840(%rbp)
	addq $1, %r9
	movq %r13, %rbx
	jmp .Lbb807
.Lbb810:
	movl -268(%rbp), %esi
	movq -488(%rbp), %rcx
	movq %r12, %rdx
	movq -456(%rbp), %r12
	movl -496(%rbp), %r10d
	movl -500(%rbp), %r9d
	movq %rdi, %rbx
	movq %r15, %rdi
	movl -1544(%rbp), %r15d
.Lbb811:
	movq -2096(%rbp), %rax
	cmpl $8, %r15d
	setz %r11b
	movzbl %r11b, %r11d
	movl -2328(%rbp), %r13d
	andl %r13d, %r11d
	cmpl $0, %r11d
	jnz .Lbb813
	movq %r8, %r14
	movl %esi, %r8d
	movq %rax, %rsi
	movl $2, %eax
	jmp .Lbb823
.Lbb813:
	cmpq $0, %rax
	jnz .Lbb815
	movq %rax, %rsi
	movq %r8, %r14
	jmp .Lbb821
.Lbb815:
	movq -16(%rax), %rsi
	movq %r8, %r14
	movq $4611686018427387906, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb820
	movq %rax, %rsi
	movq -24(%rax), %rax
	addq $1, %rax
	jz .Lbb818
	movq %rax, -24(%rsi)
	jmp .Lbb821
.Lbb818:
	movq %rbx, %rdi
	.loc 1 248
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb820:
	movq %rax, %rsi
.Lbb821:
	movq %rsi, -2248(%rbp)
	movq %rsi, -2288(%rbp)
	movl $1, %r8d
	movl $8, %eax
.Lbb823:
	movl %r8d, -272(%rbp)
	movl %eax, -276(%rbp)
	movq %rsi, -2256(%rbp)
	movl %eax, %r11d
	andl $24, %r11d
	cmpl $0, %r11d
	setz %r11b
	movzbl %r11b, %r11d
	testl %r11d, %r8d
	jnz .Lbb857
	cmpq $0, %rsi
	jz .Lbb832
	movq -16(%rsi), %r9
	movq $4611686018427387906, %r10
	andq %r9, %r10
	cmpq $0, %r10
	jnz .Lbb831
	movl %r8d, %ecx
	movl %ecx, %r8d
	movq -32(%rsi), %rcx
	addq $1, %rcx
	jz .Lbb829
	movq %rcx, -32(%rsi)
	jmp .Lbb832
.Lbb829:
	movq %rbx, %rdi
	.loc 1 250
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb831:
	movq $4611686018427387904, %r10
	andq %r10, %r9
	cmpq $0, %r9
	jnz .Lbb833
.Lbb832:
	movl %r8d, %ecx
	movq %rsi, -2248(%rbp)
	jmp .Lbb835
.Lbb833:
	.loc 1 250
	movq %rdx, %r13
	leaq -2256(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_retain
	movq %rdx, -1240(%rbp)
	movq %r13, %rdx
	movq %r12, %rdi
	movl %eax, %esi
	movl -272(%rbp), %ecx
	movl -276(%rbp), %eax
	movq -456(%rbp), %r12
	cmpl $0, %esi
	jnz .Lbb835
	.loc 1 250
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 250
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb835:
	cmpl $0, %ecx
	jnz .Lbb837
	movq %r12, %r13
	jmp .Lbb864
.Lbb837:
	testl $28, %eax
	jnz .Lbb847
	movq -2288(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb846
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb845
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb844
	movq %rdx, %r13
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb843
	.loc 1 250
	leaq -2288(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r13, %rdx
	movq %r12, %rdi
	movq -456(%rbp), %r12
	jmp .Lbb846
.Lbb843:
	movq %r13, %rdx
.Lbb844:
	movq %rax, -32(%rcx)
.Lbb845:
	movq $0, -2288(%rbp)
.Lbb846:
	movq %r12, %r13
	jmp .Lbb864
.Lbb847:
	movq -2288(%rbp), %rcx
	cmpq $0, %rcx
	jnz .Lbb849
	movq %r12, %r13
	jmp .Lbb864
.Lbb849:
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb855
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb854
	movq %rdx, %r13
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb853
	.loc 1 250
	leaq -2288(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r13, %rdx
	movq %r12, %rdi
	movq -456(%rbp), %r13
	jmp .Lbb864
.Lbb853:
	movq %r13, %rdx
.Lbb854:
	movq %r12, %r13
	movq %rax, -24(%rcx)
	jmp .Lbb856
.Lbb855:
	movq %r12, %r13
.Lbb856:
	movq $0, -2288(%rbp)
	jmp .Lbb864
.Lbb857:
	movq %rsi, %rax
	movq %r12, %r13
	movl %r9d, %esi
	orl %r10d, %esi
	jnz .Lbb862
	cmpq $0, %rax
	jz .Lbb861
	movq -16(%rax), %rax
	movq $5764607523034234881, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb862
.Lbb861:
	movq -2256(%rbp), %rax
	movq %rax, -2248(%rbp)
	movq $0, -2256(%rbp)
	jmp .Lbb864
.Lbb862:
	.loc 1 250
	movq %rdx, %r13
	leaq -2256(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_take
	movq %rdx, -1240(%rbp)
	movq %r13, %rdx
	movq %r12, %rdi
	movq -456(%rbp), %r13
	cmpl $0, %eax
	jnz .Lbb864
	.loc 1 250
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 250
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb864:
	movq -2248(%rbp), %rax
	movq %rax, -2088(%rbp)
	movl -2328(%rbp), %eax
	cmpl $0, %eax
	jnz .Lbb866
	movq %rdx, %r12
	jmp .Lbb886
.Lbb866:
	movl $0, -2328(%rbp)
	testl $28, %r15d
	jnz .Lbb876
	movq -2096(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb875
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb874
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb873
	movq %rdx, %r15
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb872
	.loc 1 250
	leaq -2096(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r15, %rdx
	movq %r12, %rdi
	jmp .Lbb875
.Lbb872:
	movq %r15, %rdx
.Lbb873:
	movq %rax, -32(%rcx)
.Lbb874:
	movq $0, -2096(%rbp)
.Lbb875:
	movq %rdx, %r12
	jmp .Lbb886
.Lbb876:
	movq -2096(%rbp), %rcx
	cmpq $0, %rcx
	jnz .Lbb878
	movq %rdx, %r12
	jmp .Lbb886
.Lbb878:
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb884
	movq -24(%rcx), %rax
	subq $1, %rax
	jz .Lbb881
	movq %rdx, %r12
	jmp .Lbb883
.Lbb881:
	movq %rdx, %r12
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb883
	.loc 1 250
	leaq -2096(%rbp), %rsi
	movq %rdi, %r15
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r15, %rdi
	jmp .Lbb886
.Lbb883:
	movq %rax, -24(%rcx)
	jmp .Lbb885
.Lbb884:
	movq %rdx, %r12
.Lbb885:
	movq $0, -2096(%rbp)
.Lbb886:
	movq %r12, -1840(%rbp)
	cmpq $0, %r12
	jg .Lbb888
	movl $0, %edx
	jmp .Lbb891
.Lbb888:
	movq $0, -1840(%rbp)
	movq $0, -1840(%rbp)
	cmpq $0, %r13
	jl .Lbb2621
	cmpq $0, %r12
	jl .Lbb2619
	movq %r12, %rdx
.Lbb891:
	.loc 1 293
	movq %rdx, -1240(%rbp)
	movq myl_t_1a91deb3742283487d66c3b500f6effd7ef1170e6d4b4368fe9ec3c3f0354fda@gotpcrel(%rip), %rsi
	movq %rdi, %r13
	callq myl_native_list_new
	movq %r14, %r8
	movq %r13, %rdi
	movl -280(%rbp), %r13d
	movq -488(%rbp), %rcx
	movq %r8, %r14
	movq -288(%rbp), %r8
	movq -296(%rbp), %rsi
	movl -496(%rbp), %r10d
	movl -500(%rbp), %r9d
	cmpl $0, %eax
	jnz .Lbb894
	movq %rbx, %rdi
	.loc 1 293
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	movq %rdx, -1240(%rbp)
	ud2
.Lbb894:
	movq %rax, -2256(%rbp)
	movq -2256(%rbp), %r11
	movq %r11, -2248(%rbp)
	movq -2248(%rbp), %r11
	movq %r11, -2288(%rbp)
	movq %rax, -2256(%rbp)
	orl %r10d, %r9d
	jnz .Lbb898
	cmpq $0, %rax
	jz .Lbb897
	movq -16(%rax), %rax
	movq $5764607523034234881, %r9
	andq %r9, %rax
	cmpq $0, %rax
	jnz .Lbb898
.Lbb897:
	movq -2256(%rbp), %rax
	movq %rax, -2248(%rbp)
	movq $0, -2256(%rbp)
	jmp .Lbb900
.Lbb898:
	movq %r12, %rdx
	.loc 1 294
	movq %rdx, %r12
	leaq -2256(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_take
	movq %r14, %r8
	movq %r13, %rdi
	movl -280(%rbp), %r13d
	movq -488(%rbp), %rcx
	movq %r8, %r14
	movq -288(%rbp), %r8
	movq -296(%rbp), %rsi
	cmpl $0, %eax
	jnz .Lbb900
	.loc 1 294
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 294
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb900:
	movl -2320(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb908
	movl $0, -2320(%rbp)
	movq -2080(%rbp), %r9
	cmpq $0, %r9
	jz .Lbb908
	movq -16(%r9), %rax
	movq $4611686018427387906, %r10
	andq %r10, %rax
	cmpq $0, %rax
	jnz .Lbb907
	movq -32(%r9), %rax
	subq $1, %rax
	jnz .Lbb906
	movq -24(%r9), %r10
	cmpq $0, %r10
	jnz .Lbb906
	.loc 1 294
	leaq -2080(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %r14, %r8
	movq %r13, %rdi
	movl -280(%rbp), %r13d
	movq -488(%rbp), %rcx
	movq %r8, %r14
	movq -288(%rbp), %r8
	movq -296(%rbp), %rsi
	jmp .Lbb908
.Lbb906:
	movq %rax, -32(%r9)
.Lbb907:
	movq $0, -2080(%rbp)
.Lbb908:
	movq -2248(%rbp), %rax
	movq %rax, -2080(%rbp)
	movl $1, -2320(%rbp)
	cmpl $16, %r13d
	jnz .Lbb938
	movq -2080(%rbp), %rax
	cmpq $0, %rax
	jz .Lbb916
	movq -16(%rax), %r9
	movq $4611686018427387906, %r10
	andq %r9, %r10
	cmpq $0, %r10
	jnz .Lbb915
	movq -32(%rax), %rcx
	addq $1, %rcx
	jz .Lbb913
	movq %rcx, -32(%rax)
	jmp .Lbb916
.Lbb913:
	movq %rbx, %rdi
	.loc 1 295
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb915:
	movq $4611686018427387904, %r10
	andq %r10, %r9
	cmpq $0, %r9
	jnz .Lbb917
.Lbb916:
	movq %rax, -2248(%rbp)
	jmp .Lbb920
.Lbb917:
	movq %r12, %rdx
	.loc 1 295
	movq %rdx, %r12
	leaq -2080(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_retain
	movq %r14, %r8
	movq %r13, %rdi
	movl -280(%rbp), %r13d
	movq %r8, %r14
	movq -288(%rbp), %r8
	movq -296(%rbp), %rsi
	cmpl $0, %eax
	jnz .Lbb920
	.loc 1 295
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 295
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb920:
	movl -2320(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb936
	movl $0, -2320(%rbp)
	testl $28, %r13d
	jnz .Lbb929
	movq -2080(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb936
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r9
	andq %r9, %rax
	cmpq $0, %rax
	jnz .Lbb928
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb927
	movq -24(%rcx), %r9
	cmpq $0, %r9
	jnz .Lbb927
	.loc 1 295
	leaq -2080(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %r14, %r8
	movq %r13, %rdi
	movq %r8, %r14
	movq -288(%rbp), %r8
	movq -296(%rbp), %rsi
	jmp .Lbb936
.Lbb927:
	movq %rax, -32(%rcx)
.Lbb928:
	movq $0, -2080(%rbp)
	jmp .Lbb936
.Lbb929:
	movq -2080(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb936
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r9
	andq %r9, %rax
	cmpq $0, %rax
	jnz .Lbb935
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb934
	movq -32(%rcx), %r9
	cmpq $0, %r9
	jnz .Lbb934
	.loc 1 295
	leaq -2080(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movq %r14, %r8
	movq %r13, %rdi
	movq %r8, %r14
	movq -288(%rbp), %r8
	movq -296(%rbp), %rsi
	jmp .Lbb936
.Lbb934:
	movq %rax, -24(%rcx)
.Lbb935:
	movq $0, -2080(%rbp)
.Lbb936:
	movq -2248(%rbp), %rax
	movq %rax, -2080(%rbp)
	movl $1, -2320(%rbp)
	movl $2, %r13d
.Lbb938:
	movl %r13d, -356(%rbp)
	cmpl $8, %r13d
	jz .Lbb944
	movq -2080(%rbp), %rax
	cmpq $0, %rax
	jz .Lbb943
	movq -16(%rax), %rcx
	movq $6917529027641081858, %r9
	andq %r9, %rcx
	cmpq $0, %rcx
	jnz .Lbb942
	movq -32(%rax), %rax
	cmpq $2, %rax
	jb .Lbb943
.Lbb942:
	movq %r12, %rdx
	.loc 1 295
	leaq -2320(%rbp), %rcx
	movq %rdx, %r12
	leaq -2080(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527@gotpcrel(%rip), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_local
	movq %r14, %r8
	movq %r13, %rdi
	movq %r8, %r14
	movq -288(%rbp), %r8
	movq -296(%rbp), %rsi
	cmpl $0, %eax
	jz .Lbb2614
.Lbb943:
	movq %r14, %r15
	movl $2, -1548(%rbp)
	jmp .Lbb951
.Lbb944:
	movq -2080(%rbp), %rax
	cmpq $0, %rax
	jnz .Lbb946
	movq %r14, %r15
	jmp .Lbb950
.Lbb946:
	movq -16(%rax), %rcx
	movq $6917529027641081858, %r9
	andq %r9, %rcx
	cmpq $0, %rcx
	jnz .Lbb949
	movq -32(%rax), %rax
	cmpq $2, %rax
	jae .Lbb949
	movq %r14, %r15
	jmp .Lbb950
.Lbb949:
	movq %r12, %rdx
	.loc 1 295
	movl $0, %ecx
	movq %rdx, %r12
	leaq -2080(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527@gotpcrel(%rip), %rsi
	movq %rdi, %r13
	movq %rbx, %rdi
	callq myl_qbe_rc_unique_held
	movq %r14, %r8
	movq %r13, %rdi
	movl -356(%rbp), %r13d
	movq %r8, %r15
	movq -288(%rbp), %r8
	movq -296(%rbp), %rsi
	cmpl $0, %eax
	jz .Lbb2614
.Lbb950:
	movl %r13d, -1548(%rbp)
.Lbb951:
	movq %r15, %rcx
	sarq $63, %rcx
	movq %r15, %rax
	xorq %rcx, %rax
	subq %rcx, %rax
	movq $-5030930201920786804, %r9
	mulq %r9
	movq %rdx, %rax
	movq %r12, %rdx
	shrq $3, %rax
	xorq %rcx, %rax
	subq %rcx, %rax
	imulq $11, %rax, %rax
	negq %rax
	addq %r15, %rax
	cmpq $0, %rax
	setnz %r9b
	movzbq %r9b, %r9
	andq %r9, %rcx
	negq %rcx
	andq $11, %rcx
	addq %rax, %rcx
	movq %rcx, -1216(%rbp)
	testq %rsi, %r8
	jnz .Lbb953
	movq %rcx, %rax
	movq %r15, %r8
	movq %rdi, %r15
	movq %rdx, %r12
	movl $0, %ecx
	movl $0, %ebx
	jmp .Lbb961
.Lbb953:
	movq $288230376151711744, %rax
	movq %rdx, %r13
	addq %rax, %rdx
	movq $576460752303423488, %rax
	cmpq %rax, %rdx
	jbe .Lbb955
	movq %rcx, %rax
	movq %r15, %r8
	movq %rdi, %r15
	movq %r13, %r12
	movl $0, %ecx
	movl $0, %ebx
	jmp .Lbb961
.Lbb955:
	movq -2080(%rbp), %rsi
	movq %rcx, %r14
	movq 8(%rsi), %rcx
	movq (%rsi), %rax
	movq %rax, -312(%rbp)
	negq %rax
	addq %rcx, %rax
	cmpq %r13, %rax
	jae .Lbb957
	movq %r14, %rax
	movq %r15, %r8
	movq %rdi, %r15
	movq %r13, %r12
	movl $0, %ecx
	movl $0, %ebx
	jmp .Lbb961
.Lbb957:
	movq 32(%rsi), %r9
	movq %r9, -320(%rbp)
	movq 16(%rsi), %rax
	movq %rax, -304(%rbp)
	.loc 1 295
	movq %rdi, %r12
	callq myl_rc_list_plain_ready
	movq %r15, %r8
	movq %r14, %rcx
	movq %rdx, -1240(%rbp)
	movq %r13, %rdx
	movq %r12, %rdi
	movl %eax, %r10d
	movq -304(%rbp), %rsi
	movq -320(%rbp), %r9
	movl -1520(%rbp), %r13d
	movq -1184(%rbp), %r12
	movq -488(%rbp), %r14
	movq -312(%rbp), %rax
	cmpl $0, %r10d
	jnz .Lbb959
	movq %rdi, %r15
	movq %rcx, %rax
	movq %rdx, %r12
	movl $0, %ecx
	movl $0, %ebx
	jmp .Lbb961
.Lbb959:
	movq $4611686018427387904, %r10
	cmpq %r10, %rsi
	jb .Lbb981
	movq %rdi, %r15
	movq %rcx, %rax
	movq %rdx, %r12
	movl $0, %ecx
	movl $0, %ebx
.p2align 4
.Lbb961:
	movq %r12, -1840(%rbp)
	cmpq %r12, %rbx
	jge .Lbb980
	movq $3, -1840(%rbp)
	imulq $3, %rbx, %rdx
	movl $4294967295, %esi
	movq %rbx, %r10
	andq %rsi, %r10
	movq %rbx, %r9
	shrq $32, %r9
	imulq $3, %r10, %rsi
	shrq $32, %rsi
	imulq $3, %r9, %rdi
	addq %rsi, %rdi
	movl $4294967295, %esi
	andq %rdi, %rsi
	shrq $32, %rdi
	imulq $0, %r10, %r10
	addq %r10, %rsi
	shrq $32, %rsi
	imulq $0, %r9, %r9
	addq %r9, %rdi
	addq %rdi, %rsi
	cmpq $0, %rbx
	setl %dil
	movzbq %dil, %rdi
	negq %rdi
	movq %r8, %r14
	movq %rdi, %r8
	andq $3, %r8
	movq %rbx, %rdi
	andq $0, %rdi
	subq %r8, %rsi
	subq %rdi, %rsi
	movq %rdx, %rdi
	sarq $63, %rdi
	cmpq %rsi, %rdi
	jnz .Lbb978
	movq %r14, -1840(%rbp)
	movq $11, -1832(%rbp)
	movq %rax, -1840(%rbp)
	movq %rax, %r9
	addq %rdx, %r9
	movq %r9, -344(%rbp)
	movq %rdx, %rsi
	xorq %r9, %rsi
	movq %rax, %rdi
	xorq %r9, %rdi
	andq %rdi, %rsi
	cmpq $0, %rsi
	jl .Lbb976
	movq -2080(%rbp), %rsi
	movq %rsi, -352(%rbp)
	movq (%rsi), %rdi
	movq %rdi, -336(%rbp)
	movq %rax, %r13
	movq 8(%rsi), %rax
	movq 16(%rsi), %rdx
	movq %rdx, -328(%rbp)
	cmpq %rax, %rdi
	jae .Lbb967
	cmpl $0, %ecx
	jnz .Lbb971
	.loc 1 306
	movq %r15, %rdi
	callq myl_rc_list_plain_ready
	movq %rdx, -1240(%rbp)
	movl %eax, %ecx
	movq -328(%rbp), %rdx
	movq -336(%rbp), %rdi
	movq -352(%rbp), %rsi
	movq -344(%rbp), %r9
	cmpl $0, %ecx
	jnz .Lbb971
.Lbb967:
	movq %r9, -2216(%rbp)
	.loc 1 306
	leaq -2216(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq %r15, %rdi
	callq myl_rc_list_append
	movq %r14, %r8
	movq %rdx, -1240(%rbp)
	movl %eax, %ecx
	movq %r13, %rax
	cmpl $0, %ecx
	jz .Lbb969
	movl $0, %ecx
	jmp .Lbb972
.Lbb969:
	movq -1224(%rbp), %rdi
	.loc 1 306
	callq myl_qbe_fail_allocation
	movq %rdx, -1240(%rbp)
	ud2
.Lbb971:
	movq %r14, %r8
	movq %r13, %rax
	movq 32(%rsi), %r10
	movq %r9, (%r10, %rdi, 8)
	addq $1, %rdi
	movq %rdi, (%rsi)
	addq $1, %rdx
	movq %rdx, 16(%rsi)
.Lbb972:
	movq $1, -1840(%rbp)
	movq $9223372036854775806, %rdx
	cmpq %rdx, %rbx
	jg .Lbb974
	addq $1, %rbx
	jmp .Lbb961
.Lbb974:
	movq %rbx, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 310
	movl $64, %r8d
	movl $1, %ecx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb976:
	movq %rax, %rcx
	movq -1224(%rbp), %rdi
	.loc 1 305
	movl $64, %r8d
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb978:
	movq %rbx, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 301
	movl $64, %r8d
	movl $3, %ecx
	movq %rdx, -1240(%rbp)
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb980:
	movl -360(%rbp), %esi
	movq -488(%rbp), %rcx
	movq -456(%rbp), %r13
	movq %r12, %rdx
	movl -1548(%rbp), %r12d
	movl -496(%rbp), %r10d
	movl -500(%rbp), %r9d
	movq -1224(%rbp), %rbx
	jmp .Lbb985
.Lbb981:
	movq %rdi, %r15
	movq %rbx, %rdi
	movq %r14, %rbx
	movl %r13d, %r14d
	movq %r12, %r13
	movq %rdx, %r12
	xchgq %rcx, %rax
	movq %rsi, %rdx
	movl $0, %esi
.p2align 4
.Lbb982:
	movq %r12, -1840(%rbp)
	cmpq %r12, %rsi
	jge .Lbb984
	movq $3, -1840(%rbp)
	imulq $3, %rsi, %r10
	movq %r8, -1840(%rbp)
	movq $11, -1832(%rbp)
	movq %rax, -1840(%rbp)
	movq %r10, %r11
	addq %rax, %r11
	movq -2080(%rbp), %r10
	movq %r11, (%r9, %rcx, 8)
	addq $1, %rcx
	movq %rcx, (%r10)
	addq $1, %rdx
	movq %rdx, 16(%r10)
	movq $1, -1840(%rbp)
	addq $1, %rsi
	jmp .Lbb982
.Lbb984:
	movl -360(%rbp), %esi
	movq %rbx, %rcx
	movq -456(%rbp), %r13
	movq %r12, %rdx
	movl -1548(%rbp), %r12d
	movl -496(%rbp), %r10d
	movl -500(%rbp), %r9d
	movq %rdi, %rbx
.Lbb985:
	movq %r15, %rdi
	movq -2080(%rbp), %rax
	cmpl $8, %r12d
	setz %r11b
	movzbl %r11b, %r11d
	movl -2320(%rbp), %r14d
	andl %r14d, %r11d
	cmpl $0, %r11d
	jnz .Lbb987
	movq %r8, %r14
	movl %esi, %r8d
	movq %rax, %rsi
	movl $2, %eax
	jmp .Lbb997
.Lbb987:
	cmpq $0, %rax
	jnz .Lbb989
	movq %rax, %rsi
	movq %r8, %r14
	jmp .Lbb995
.Lbb989:
	movq -16(%rax), %rsi
	movq %r8, %r14
	movq $4611686018427387906, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb994
	movq %rax, %rsi
	movq -24(%rax), %rax
	addq $1, %rax
	jz .Lbb992
	movq %rax, -24(%rsi)
	jmp .Lbb995
.Lbb992:
	movq %rbx, %rdi
	.loc 1 313
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb994:
	movq %rax, %rsi
.Lbb995:
	movq %rsi, -2248(%rbp)
	movq %rsi, -2288(%rbp)
	movl $1, %r8d
	movl $8, %eax
.Lbb997:
	movl %r8d, -364(%rbp)
	movl %eax, -368(%rbp)
	movq %rsi, -2256(%rbp)
	movl %eax, %r11d
	andl $24, %r11d
	cmpl $0, %r11d
	setz %r11b
	movzbl %r11b, %r11d
	testl %r11d, %r8d
	jnz .Lbb1028
	cmpq $0, %rsi
	jz .Lbb1006
	movq -16(%rsi), %r9
	movq $4611686018427387906, %r10
	andq %r9, %r10
	cmpq $0, %r10
	jnz .Lbb1005
	movl %r8d, %ecx
	movl %ecx, %r8d
	movq -32(%rsi), %rcx
	addq $1, %rcx
	jz .Lbb1003
	movq %rcx, -32(%rsi)
	jmp .Lbb1006
.Lbb1003:
	movq %rbx, %rdi
	.loc 1 315
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb1005:
	movq $4611686018427387904, %r10
	andq %r10, %r9
	cmpq $0, %r9
	jnz .Lbb1007
.Lbb1006:
	movl %r8d, %ecx
	movq %rsi, -2248(%rbp)
	jmp .Lbb1009
.Lbb1007:
	.loc 1 315
	movq %rdx, %r15
	leaq -2256(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_retain
	movq %rdx, -1240(%rbp)
	movq %r15, %rdx
	movq %r13, %rdi
	movl %eax, %esi
	movl -364(%rbp), %ecx
	movl -368(%rbp), %eax
	movq -456(%rbp), %r13
	cmpl $0, %esi
	jnz .Lbb1009
	.loc 1 315
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 315
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb1009:
	cmpl $0, %ecx
	jz .Lbb1027
	testl $28, %eax
	jnz .Lbb1019
	movq -2288(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1027
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1018
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1017
	movq %rdx, %r15
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1016
	.loc 1 315
	leaq -2288(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r15, %rdx
	movq %r13, %rdi
	movq -456(%rbp), %r13
	jmp .Lbb1027
.Lbb1016:
	movq %r15, %rdx
.Lbb1017:
	movq %rax, -32(%rcx)
.Lbb1018:
	movq $0, -2288(%rbp)
	jmp .Lbb1027
.Lbb1019:
	movq -2288(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1027
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1026
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1025
	movq %rdx, %r15
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1024
	.loc 1 315
	leaq -2288(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r15, %rdx
	movq %r13, %rdi
	movq -456(%rbp), %r13
	jmp .Lbb1027
.Lbb1024:
	movq %r15, %rdx
.Lbb1025:
	movq %rax, -24(%rcx)
.Lbb1026:
	movq $0, -2288(%rbp)
.Lbb1027:
	movl %r12d, %eax
	movq %r13, %r12
	movq %rbx, %r13
	jmp .Lbb1037
.Lbb1028:
	movq %rsi, %rax
	movl %r9d, %esi
	orl %r10d, %esi
	jnz .Lbb1034
	cmpq $0, %rax
	jz .Lbb1032
	movq -16(%rax), %rax
	movq $5764607523034234881, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1034
.Lbb1032:
	movq -2256(%rbp), %rax
	movq %rax, -2248(%rbp)
	movq $0, -2256(%rbp)
	movl %r12d, %eax
	movq %r13, %r12
	movq %rbx, %r13
	jmp .Lbb1037
.Lbb1034:
	.loc 1 315
	movq %rdx, %r15
	leaq -2256(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_take
	movq %rdx, -1240(%rbp)
	movq %r15, %rdx
	movq %r13, %rdi
	movl %eax, %ecx
	movl %r12d, %eax
	movq -456(%rbp), %r12
	cmpl $0, %ecx
	jnz .Lbb1036
	.loc 1 315
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 315
	movq %rdi, %r13
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb1036:
	movq %rbx, %r13
.Lbb1037:
	movq -2248(%rbp), %rcx
	movq %rcx, -2072(%rbp)
	movl -2320(%rbp), %ecx
	cmpl $0, %ecx
	jnz .Lbb1039
	movq %rdx, %rbx
	jmp .Lbb1059
.Lbb1039:
	movl $0, -2320(%rbp)
	testl $28, %eax
	jnz .Lbb1049
	movq -2080(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1048
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1047
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1046
	movq %rdx, %r15
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1045
	.loc 1 315
	leaq -2080(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r15, %rdx
	movq %rbx, %rdi
	jmp .Lbb1048
.Lbb1045:
	movq %r15, %rdx
.Lbb1046:
	movq %rax, -32(%rcx)
.Lbb1047:
	movq $0, -2080(%rbp)
.Lbb1048:
	movq %rdx, %rbx
	jmp .Lbb1059
.Lbb1049:
	movq -2080(%rbp), %rcx
	cmpq $0, %rcx
	jnz .Lbb1051
	movq %rdx, %rbx
	jmp .Lbb1059
.Lbb1051:
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1057
	movq -24(%rcx), %rax
	subq $1, %rax
	jz .Lbb1054
	movq %rdx, %rbx
	jmp .Lbb1056
.Lbb1054:
	movq %rdx, %rbx
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1056
	.loc 1 315
	leaq -2080(%rbp), %rsi
	movq %rdi, %r15
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r15, %rdi
	jmp .Lbb1059
.Lbb1056:
	movq %rax, -24(%rcx)
	jmp .Lbb1058
.Lbb1057:
	movq %rdx, %rbx
.Lbb1058:
	movq $0, -2080(%rbp)
.Lbb1059:
	movq %rbx, -1840(%rbp)
	cmpq $0, %rbx
	jg .Lbb1061
	movl $0, %edx
	jmp .Lbb1064
.Lbb1061:
	movq $0, -1840(%rbp)
	movq $0, -1840(%rbp)
	cmpq $0, %r12
	jl .Lbb2617
	cmpq $0, %rbx
	jl .Lbb2615
	movq %rbx, %rdx
.Lbb1064:
	.loc 1 358
	movq %rdx, -1240(%rbp)
	movq myl_t_b760f44fa5965c2474a3b471467a22c43185152129295af588b022ae50b50903@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	callq myl_native_list_new
	movq %r14, %r8
	movq %r12, %rdi
	movq %rax, %rsi
	movl -412(%rbp), %eax
	movq -1184(%rbp), %r12
	movq -488(%rbp), %rcx
	movl -496(%rbp), %r10d
	movl -500(%rbp), %r9d
	cmpl $0, %esi
	jnz .Lbb1067
	movq %r13, %rdi
	.loc 1 358
	movq %rdi, %r13
	callq myl_qbe_fail_allocation
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1067:
	movq %rsi, -2256(%rbp)
	movq -2256(%rbp), %r11
	movq %r11, -2248(%rbp)
	movq -2248(%rbp), %r11
	movq %r11, -2288(%rbp)
	movq %rsi, -2256(%rbp)
	orl %r10d, %r9d
	jnz .Lbb1073
	cmpq $0, %rsi
	jnz .Lbb1070
	movq %r8, %r14
	jmp .Lbb1071
.Lbb1070:
	movq -16(%rsi), %rsi
	movq %r8, %r14
	movq $5764607523034234881, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb1074
.Lbb1071:
	movq -2256(%rbp), %rsi
	movq %rsi, -2248(%rbp)
	movq $0, -2256(%rbp)
	movq %r14, %r8
	jmp .Lbb1077
.Lbb1073:
	movq %r8, %r14
.Lbb1074:
	movq %rbx, %rdx
	.loc 1 359
	movq %rdx, %rbx
	leaq -2256(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_take
	movq %r14, %r8
	movq %r12, %rdi
	movl %eax, %esi
	movl -412(%rbp), %eax
	movq -1184(%rbp), %r12
	movq -488(%rbp), %rcx
	cmpl $0, %esi
	jnz .Lbb1077
	movq %r13, %rbx
	.loc 1 359
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 359
	movq %rdi, %r13
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb1077:
	movl -2312(%rbp), %esi
	cmpl $0, %esi
	jz .Lbb1086
	movl $0, -2312(%rbp)
	movq -2064(%rbp), %r9
	cmpq $0, %r9
	jz .Lbb1086
	movq -16(%r9), %rsi
	movq $4611686018427387906, %r10
	andq %r10, %rsi
	cmpq $0, %rsi
	jnz .Lbb1085
	movq -32(%r9), %rsi
	subq $1, %rsi
	jnz .Lbb1084
	movq %r8, %r14
	movq -24(%r9), %r8
	cmpq $0, %r8
	jnz .Lbb1083
	.loc 1 359
	leaq -2064(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_drop
	movq %r14, %r8
	movq %r12, %rdi
	movl -412(%rbp), %eax
	movq -1184(%rbp), %r12
	movq -488(%rbp), %rcx
	jmp .Lbb1086
.Lbb1083:
	movq %r14, %r8
.Lbb1084:
	movq %rsi, -32(%r9)
.Lbb1085:
	movq $0, -2064(%rbp)
.Lbb1086:
	movq -2248(%rbp), %rsi
	movq %rsi, -2064(%rbp)
	movl $1, -2312(%rbp)
	cmpl $16, %eax
	jz .Lbb1088
	movq %r8, %r14
	xchgq %rdi, %r13
	jmp .Lbb1121
.Lbb1088:
	movq -2064(%rbp), %rsi
	cmpq $0, %rsi
	jnz .Lbb1090
	movq %r8, %r14
	jmp .Lbb1097
.Lbb1090:
	movq %r8, %r14
	movq -16(%rsi), %r8
	movq $4611686018427387906, %r9
	andq %r8, %r9
	cmpq $0, %r9
	jnz .Lbb1096
	movq %rsi, %rcx
	movq %rcx, %rsi
	movq -32(%rcx), %rcx
	addq $1, %rcx
	jz .Lbb1094
	movq %rcx, -32(%rsi)
	jmp .Lbb1097
.Lbb1094:
	movq %r13, %rdi
	.loc 1 360
	movl $2, %esi
	movq %rdi, %r13
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb1096:
	movq $4611686018427387904, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jnz .Lbb1099
.Lbb1097:
	movq %rsi, %rcx
	movq %rcx, -2248(%rbp)
	xchgq %rdi, %r13
	jmp .Lbb1104
.Lbb1099:
	movq %rbx, %rdx
	.loc 1 360
	movq %rdx, %rbx
	leaq -2064(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_retain
	movq %r12, %rdi
	movl %eax, %ecx
	movl -412(%rbp), %eax
	movq -1184(%rbp), %r12
	cmpl $0, %ecx
	jnz .Lbb1103
	movq %r13, %rbx
	.loc 1 360
	movq %rdi, %r13
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 360
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb1103:
	xchgq %rdi, %r13
.Lbb1104:
	movl -2312(%rbp), %ecx
	cmpl $0, %ecx
	jz .Lbb1120
	movl $0, -2312(%rbp)
	testl $28, %eax
	jnz .Lbb1113
	movq -2064(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1120
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1112
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1111
	movq -24(%rcx), %rsi
	cmpq $0, %rsi
	jnz .Lbb1111
	.loc 1 360
	leaq -2064(%rbp), %rsi
	movq %rdi, %r12
	movq %r13, %rdi
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_drop
	movq %r12, %rdi
	movq -1184(%rbp), %r12
	jmp .Lbb1120
.Lbb1111:
	movq %rax, -32(%rcx)
.Lbb1112:
	movq $0, -2064(%rbp)
	jmp .Lbb1120
.Lbb1113:
	movq -2064(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1120
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1119
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1118
	movq -32(%rcx), %rsi
	cmpq $0, %rsi
	jnz .Lbb1118
	.loc 1 360
	leaq -2064(%rbp), %rsi
	movq %rdi, %r12
	movq %r13, %rdi
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_unloan
	movq %r12, %rdi
	movq -1184(%rbp), %r12
	jmp .Lbb1120
.Lbb1118:
	movq %rax, -24(%rcx)
.Lbb1119:
	movq $0, -2064(%rbp)
.Lbb1120:
	movq -2248(%rbp), %rax
	movq %rax, -2064(%rbp)
	movl $1, -2312(%rbp)
.Lbb1121:
	movq -2064(%rbp), %rax
	cmpq $0, %rax
	jnz .Lbb1123
	movq %r13, %rdi
	movq %r14, %r8
	jmp .Lbb1127
.Lbb1123:
	movq -16(%rax), %rcx
	movq $6917529027641081858, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb1126
	movq -32(%rax), %rax
	cmpq $2, %rax
	jae .Lbb1126
	movq %r13, %rdi
	movq %r14, %r8
	jmp .Lbb1127
.Lbb1126:
	movq %rbx, %rdx
	.loc 1 360
	leaq -2312(%rbp), %rcx
	movq %rdx, %rbx
	leaq -2064(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9@gotpcrel(%rip), %rsi
	callq myl_qbe_rc_unique_local
	movq %r14, %r8
	movq %r13, %rdi
	cmpl $0, %eax
	jz .Lbb2614
.Lbb1127:
	movq %r12, %r13
	movq %rdi, %r15
	movq %rbx, %r12
	movl $0, %r14d
.p2align 4
.Lbb1128:
	movq %r12, -1840(%rbp)
	cmpq %r12, %r14
	jge .Lbb1171
	movq $2, -1840(%rbp)
	cmpq $2, %r13
	jz .Lbb1157
	movq -2088(%rbp), %rax
	movq (%rax), %rcx
	cmpq %rcx, %r14
	setb %cl
	movzbq %cl, %rcx
	cmpq $0, %r14
	setl %dil
	movzbq %dil, %rdi
	cmpl $0, %ecx
	jnz .Lbb1143
	movq $0, -1840(%rbp)
	cmpq $0, %r14
	jl .Lbb1133
	movq %r14, %rbx
	jmp .Lbb1135
.Lbb1133:
	movq (%rax), %rsi
	movq $9223372036854775807, %rcx
	cmpq %rcx, %rsi
	ja .Lbb1141
	movq %r14, -1840(%rbp)
	movq %rsi, %rbx
	addq %r14, %rbx
	movq %rsi, %rcx
	xorq %rbx, %rcx
	movq %r14, %r9
	xorq %rbx, %r9
	andq %r9, %rcx
	cmpq $0, %rcx
	jl .Lbb1139
.Lbb1135:
	movq (%rax), %rcx
	cmpq %rcx, %rbx
	jae .Lbb1137
	movq 32(%rax), %rax
	movq (%rax, %rbx, 8), %rax
	jmp .Lbb1144
.Lbb1137:
	movq %rcx, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 389
	movq %rdx, -1240(%rbp)
	movq %rbx, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1139:
	movq %r14, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 386
	movl $64, %r8d
	movq %rdx, %rcx
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1141:
	movq -1224(%rbp), %rdi
	.loc 1 384
	movl $320, %edx
	movq %rdx, -1240(%rbp)
	callq myl_qbe_fail_cast
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1143:
	movq 32(%rax), %rax
	movq (%rax, %r14, 8), %rax
.Lbb1144:
	movq $73, -1840(%rbp)
	imulq $73, %rax, %rsi
	movl $4294967295, %ecx
	movq %rax, %r11
	andq %rcx, %r11
	movq %rax, %r10
	shrq $32, %r10
	imulq $73, %r11, %rcx
	shrq $32, %rcx
	imulq $73, %r10, %r9
	addq %rcx, %r9
	movl $4294967295, %ecx
	andq %r9, %rcx
	shrq $32, %r9
	imulq $0, %r11, %r11
	addq %r11, %rcx
	shrq $32, %rcx
	imulq $0, %r10, %r10
	addq %r10, %r9
	addq %r9, %rcx
	cmpq $0, %rax
	setl %r9b
	movzbq %r9b, %r9
	negq %r9
	movq %r9, %r10
	andq $73, %r10
	movq %rax, %r9
	andq $0, %r9
	subq %r10, %rcx
	subq %r9, %rcx
	movq %rsi, %r9
	sarq $63, %r9
	cmpq %rcx, %r9
	jnz .Lbb1155
	movq %r14, -1840(%rbp)
	movq $19, -1832(%rbp)
	imulq $19, %r14, %rcx
	movl $4294967295, %eax
	movq %r14, %r11
	andq %rax, %r11
	movq %r14, %r10
	shrq $32, %r10
	imulq $19, %r11, %rax
	shrq $32, %rax
	imulq $19, %r10, %r9
	addq %rax, %r9
	movl $4294967295, %eax
	andq %r9, %rax
	shrq $32, %r9
	imulq $0, %r11, %r11
	addq %r11, %rax
	shrq $32, %rax
	imulq $0, %r10, %r10
	addq %r10, %r9
	addq %r9, %rax
	negq %rdi
	movq %rdi, %r9
	andq $19, %r9
	movq %r14, %rdi
	andq $0, %rdi
	subq %r9, %rax
	subq %rdi, %rax
	movq %rcx, %rdi
	sarq $63, %rdi
	cmpq %rax, %rdi
	jnz .Lbb1153
	movq %rcx, -1840(%rbp)
	movq %rsi, %rax
	addq %rcx, %rax
	movq %rsi, %rdi
	xorq %rax, %rdi
	movq %rcx, %r9
	xorq %rax, %r9
	andq %r9, %rdi
	cmpq $0, %rdi
	jl .Lbb1151
	movq %r8, -1840(%rbp)
	movq %r8, %rsi
	addq %rax, %rsi
	movq %rax, %rcx
	xorq %rsi, %rcx
	movq %r8, %rdi
	xorq %rsi, %rdi
	andq %rdi, %rcx
	cmpq $0, %rcx
	jl .Lbb1149
	movq $101, -1840(%rbp)
	movq %rsi, %rcx
	sarq $63, %rcx
	movq %rcx, %rax
	xorq %rsi, %rax
	movq %rax, %rdi
	subq %rcx, %rdi
	movq $4931307821684731621, %r9
	movq %rdi, %rax
	mulq %r9
	movq %rdx, %rax
	subq %rax, %rdi
	shrq $1, %rdi
	addq %rdi, %rax
	shrq $6, %rax
	xorq %rcx, %rax
	subq %rcx, %rax
	imulq $101, %rax, %rax
	negq %rax
	addq %rsi, %rax
	cmpq $0, %rax
	setnz %sil
	movzbq %sil, %rsi
	andq %rsi, %rcx
	negq %rcx
	andq $101, %rcx
	addq %rcx, %rax
	movq $50, -1840(%rbp)
	cmpq $50, %rax
	setl %sil
	movzbq %sil, %rsi
	jmp .Lbb1158
.Lbb1149:
	movq %rax, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 397
	movq %r8, %rbx
	movl $64, %r8d
	movq %rbx, %rcx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1151:
	movq %rsi, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 395
	movl $64, %r8d
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1153:
	movq %r14, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 394
	movl $64, %r8d
	movl $19, %ecx
	movq %rdx, -1240(%rbp)
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1155:
	movq %rax, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 391
	movl $64, %r8d
	movl $73, %ecx
	movq %rdx, -1240(%rbp)
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1157:
	movq $16, -1840(%rbp)
	movq %r14, %rax
	andq $15, %rax
	movq $0, -1840(%rbp)
	cmpq $0, %rax
	setnz %sil
	movzbq %sil, %rsi
.Lbb1158:
	movq %rsi, -400(%rbp)
	movq -2064(%rbp), %rcx
	movq %rcx, -408(%rbp)
	movzbq %sil, %rdi
	movq %rdi, -384(%rbp)
	movq (%rcx), %r9
	movq %r9, -392(%rbp)
	movq 8(%rcx), %r10
	movq 16(%rcx), %rax
	movq %rax, -376(%rbp)
	cmpq %r10, %r9
	movq %rax, %r9
	setb %al
	movzbl %al, %eax
	cmpq $-1, %r9
	movq %r8, %rbx
	setnz %r8b
	movzbl %r8b, %r8d
	testl %eax, %r8d
	jz .Lbb1160
	.loc 1 404
	movq %rcx, %rsi
	movq %r15, %rdi
	callq myl_rc_list_plain_ready
	movl %eax, %r9d
	movq -376(%rbp), %rax
	movq -392(%rbp), %rsi
	movq -384(%rbp), %rdi
	movq -408(%rbp), %rcx
	movq %rsi, %r8
	movq -400(%rbp), %rsi
	movq -1184(%rbp), %r13
	cmpl $0, %r9d
	jnz .Lbb1164
.Lbb1160:
	movq %rdi, %rax
	andq $255, %rax
	movq %rsi, %rdx
	andq $-256, %rdx
	orq %rdx, %rax
	movq %rax, -2216(%rbp)
	.loc 1 404
	leaq -2216(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq %rcx, %rsi
	movq %r15, %rdi
	callq myl_rc_list_append
	movq %rbx, %r8
	movq -1184(%rbp), %rbx
	cmpl $0, %eax
	jz .Lbb1162
	movq %r8, %r13
	jmp .Lbb1166
.Lbb1162:
	movq -1224(%rbp), %rdi
	.loc 1 404
	callq myl_qbe_fail_allocation
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1164:
	movq %r8, %rsi
	movq %rbx, %r8
	movq %r13, %rbx
	movq %r8, %r13
	movq 32(%rcx), %r8
	movb %dil, (%r8, %rsi, 1)
	addq $1, %rsi
	movq %rsi, (%rcx)
	addq $1, %rax
	movq %rax, 16(%rcx)
.Lbb1166:
	movq $1, -1840(%rbp)
	movq $9223372036854775806, %rax
	cmpq %rax, %r14
	jg .Lbb1169
	addq $1, %r14
	movq %r13, %r8
	movq %rbx, %r13
	jmp .Lbb1128
.Lbb1169:
	movq %r14, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 408
	movl $64, %r8d
	movl $1, %ecx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	movq %rdi, %rbx
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1171:
	movl -416(%rbp), %r13d
	movl -420(%rbp), %r12d
	movl -424(%rbp), %edx
	movq -488(%rbp), %rcx
	movq %r15, %rdi
	movl -496(%rbp), %r10d
	movl -500(%rbp), %r9d
	movq -1224(%rbp), %rbx
	movq -2064(%rbp), %rax
	movq %rax, -2256(%rbp)
	cmpl $0, %edx
	jnz .Lbb1183
	cmpq $0, %rax
	jz .Lbb1180
	movq -16(%rax), %rdx
	movq $4611686018427387906, %rsi
	andq %rdx, %rsi
	cmpq $0, %rsi
	jnz .Lbb1179
	movq -32(%rax), %rdx
	addq $1, %rdx
	jz .Lbb1177
	movq %rdx, -32(%rax)
	jmp .Lbb1180
.Lbb1177:
	movq %rbx, %rdi
	.loc 1 413
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb1179:
	movq $4611686018427387904, %rsi
	andq %rsi, %rdx
	cmpq $0, %rdx
	jnz .Lbb1181
.Lbb1180:
	movq %rax, -2248(%rbp)
	jmp .Lbb1189
.Lbb1181:
	.loc 1 413
	movq %rcx, %r15
	leaq -2256(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_retain
	movq %r15, %rcx
	movq %rdx, -1240(%rbp)
	movq %r14, %rdi
	cmpl $0, %eax
	jnz .Lbb1189
	.loc 1 413
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 413
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb1183:
	movl %r9d, %edx
	orl %r10d, %edx
	jnz .Lbb1187
	cmpq $0, %rax
	jz .Lbb1186
	movq -16(%rax), %rax
	movq $5764607523034234881, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb1187
.Lbb1186:
	movq -2256(%rbp), %rax
	movq %rax, -2248(%rbp)
	movq $0, -2256(%rbp)
	jmp .Lbb1189
.Lbb1187:
	.loc 1 413
	movq %rcx, %r15
	leaq -2256(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_take
	movq %r15, %rcx
	movq %rdx, -1240(%rbp)
	movq %r14, %rdi
	cmpl $0, %eax
	jnz .Lbb1189
	.loc 1 413
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 413
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb1189:
	movq -2248(%rbp), %rax
	movq %rax, -2056(%rbp)
	movl -2312(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb1198
	movl $0, -2312(%rbp)
	movq -2064(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb1198
	movq -16(%rdx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1197
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb1196
	movq %rcx, %r15
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb1195
	.loc 1 413
	leaq -2064(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_drop
	movq %r15, %rcx
	movq %rdx, -1240(%rbp)
	movq %r14, %rdi
	jmp .Lbb1198
.Lbb1195:
	movq %r15, %rcx
.Lbb1196:
	movq %rax, -32(%rdx)
.Lbb1197:
	movq $0, -2064(%rbp)
.Lbb1198:
	movq -2088(%rbp), %rax
	cmpq $0, %rax
	jz .Lbb1204
	movq -16(%rax), %rdx
	movq $4611686018427387906, %rsi
	andq %rsi, %rdx
	cmpq $0, %rdx
	jnz .Lbb1204
	movq -24(%rax), %rdx
	addq $1, %rdx
	jz .Lbb1202
	movq %rdx, -24(%rax)
	jmp .Lbb1204
.Lbb1202:
	movq %rbx, %rdi
	.loc 1 415
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb1204:
	movq %rax, -2248(%rbp)
	cmpl $0, %r13d
	jnz .Lbb1206
	movq %rcx, %r14
	jmp .Lbb1223
.Lbb1206:
	testl $28, %r12d
	jnz .Lbb1216
	movq -2288(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb1215
	movq -16(%rdx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1214
	movq -32(%rdx), %rax
	subq $1, %rax
	jnz .Lbb1213
	movq %rcx, %r13
	movq -24(%rdx), %rcx
	cmpq $0, %rcx
	jnz .Lbb1212
	.loc 1 415
	leaq -2288(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %r13, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	jmp .Lbb1215
.Lbb1212:
	movq %r13, %rcx
.Lbb1213:
	movq %rax, -32(%rdx)
.Lbb1214:
	movq $0, -2288(%rbp)
.Lbb1215:
	movq %rcx, %r14
	jmp .Lbb1223
.Lbb1216:
	movq %rcx, %r14
	movq -2288(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1223
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb1222
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1221
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1221
	.loc 1 415
	leaq -2288(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	jmp .Lbb1223
.Lbb1221:
	movq %rax, -24(%rcx)
.Lbb1222:
	movq $0, -2288(%rbp)
.Lbb1223:
	movq -2248(%rbp), %rax
	movq %rax, -2288(%rbp)
	movq %rax, -2248(%rbp)
	movq -2248(%rbp), %rax
	movq %rax, -2048(%rbp)
	movq (%rax), %rsi
	movq %rsi, -432(%rbp)
	movq $9223372036854775807, %rax
	cmpq %rax, %rsi
	ja .Lbb2612
	cmpq $0, %rsi
	jge .Lbb1227
	movq %rbx, %rdi
	.loc 1 422
	movq %rdi, %rbx
	callq myl_qbe_fail_list_capacity
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1227:
	.loc 1 422
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movq %rsi, %r13
	movq myl_t_a29cdb61df1464ef45ddedc7a042fd8f4fab0fd1c7c0c694df708d0b61e21222@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	callq myl_native_list_new
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movl -436(%rbp), %r12d
	movl -496(%rbp), %r10d
	movl -500(%rbp), %r9d
	cmpl $0, %eax
	jnz .Lbb1230
	movq %rbx, %rdi
	.loc 1 422
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1230:
	movq %rax, -2256(%rbp)
	movq -2256(%rbp), %r8
	movq %r8, -2248(%rbp)
	movq -2248(%rbp), %r8
	movq %r8, -2288(%rbp)
	movq %rax, -2256(%rbp)
	movl %r9d, %r8d
	orl %r10d, %r8d
	jnz .Lbb1234
	cmpq $0, %rax
	jz .Lbb1233
	movq -16(%rax), %rax
	movq $5764607523034234881, %r8
	andq %r8, %rax
	cmpq $0, %rax
	jnz .Lbb1234
.Lbb1233:
	movq -2256(%rbp), %rax
	movq %rax, -2248(%rbp)
	movq $0, -2256(%rbp)
	jmp .Lbb1236
.Lbb1234:
	.loc 1 423
	movq %rcx, %r14
	leaq -2256(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq %rsi, %r13
	leaq -2248(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_take
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movl -436(%rbp), %r12d
	cmpl $0, %eax
	jnz .Lbb1236
	.loc 1 423
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 423
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb1236:
	movl -2304(%rbp), %eax
	cmpl $0, %eax
	jnz .Lbb1238
	movl %r12d, %r14d
	jmp .Lbb1248
.Lbb1238:
	movl $0, -2304(%rbp)
	movq -2040(%rbp), %r8
	cmpq $0, %r8
	jnz .Lbb1240
	movl %r12d, %r14d
	jmp .Lbb1248
.Lbb1240:
	movq -16(%r8), %rax
	movq $4611686018427387906, %r9
	andq %r9, %rax
	cmpq $0, %rax
	jnz .Lbb1246
	movq -32(%r8), %rax
	subq $1, %rax
	jnz .Lbb1245
	movq %rcx, %r14
	movq -24(%r8), %rcx
	cmpq $0, %rcx
	jnz .Lbb1244
	.loc 1 423
	movq %rsi, %r13
	leaq -2040(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_drop
	movq %r14, %rcx
	movq %r13, %rsi
	movq %r12, %rdi
	movl -436(%rbp), %r14d
	jmp .Lbb1248
.Lbb1244:
	movq %r14, %rcx
.Lbb1245:
	movl %r12d, %r14d
	movq %rax, -32(%r8)
	jmp .Lbb1247
.Lbb1246:
	movl %r12d, %r14d
.Lbb1247:
	movq $0, -2040(%rbp)
.Lbb1248:
	movq -2248(%rbp), %rax
	movq %rax, -2040(%rbp)
	movl $1, -2304(%rbp)
	movq %rdi, %r15
	movq %rsi, %r12
	movq %rbx, %rdi
	movq %rcx, %rbx
	movl $0, %r13d
.p2align 4
.Lbb1250:
	movl %r14d, -1516(%rbp)
	movq %r12, -1840(%rbp)
	cmpq %r12, %r13
	setl %al
	movzbq %al, %rax
	cmpl $0, %eax
	jz .Lbb1302
	movq -2048(%rbp), %rax
	movq (%rax), %rcx
	cmpq %rcx, %r12
	jnz .Lbb1301
	cmpq %rcx, %r13
	jae .Lbb1299
	movq 32(%rax), %rax
	movq (%rax, %r13, 8), %rsi
	movq %rsi, -1840(%rbp)
	movq $17, -1832(%rbp)
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
	movq %rcx, -1840(%rbp)
	movq %rsi, -1832(%rbp)
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
	jnz .Lbb1297
	movq %r9, -1832(%rbp)
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
	movq %rax, -1832(%rbp)
	movq %rsi, -1824(%rbp)
	movq %rcx, -1816(%rbp)
	movq %rax, -1808(%rbp)
	cmpl $16, %r14d
	setz %al
	movzbl %al, %eax
	movl -2304(%rbp), %ecx
	testl %eax, %ecx
	jz .Lbb1280
	movq -2040(%rbp), %rax
	cmpq $0, %rax
	jz .Lbb1261
	movq -16(%rax), %rcx
	movq $4611686018427387906, %rsi
	andq %rcx, %rsi
	cmpq $0, %rsi
	jnz .Lbb1260
	movq -32(%rax), %rcx
	addq $1, %rcx
	jz .Lbb1259
	movq %rcx, -32(%rax)
	jmp .Lbb1261
.Lbb1259:
	.loc 1 444
	movl $2, %esi
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb1260:
	movq $4611686018427387904, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb1262
.Lbb1261:
	movq %rax, -2248(%rbp)
	jmp .Lbb1263
.Lbb1262:
	.loc 1 444
	movl %ebx, %ecx
	leaq -2040(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r12
	movq %r15, %rdi
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_retain
	movq %r12, %rdi
	movl -1516(%rbp), %r14d
	movq -432(%rbp), %r12
	cmpl $0, %eax
	jz .Lbb1295
.Lbb1263:
	movl -2304(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb1279
	movl $0, -2304(%rbp)
	testl $28, %r14d
	jnz .Lbb1272
	movq -2040(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1279
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1271
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1270
	movq -24(%rcx), %rsi
	cmpq $0, %rsi
	jnz .Lbb1270
	.loc 1 444
	leaq -2040(%rbp), %rsi
	movq %rdi, %r12
	movq %r15, %rdi
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_drop
	movq %r12, %rdi
	movq -432(%rbp), %r12
	jmp .Lbb1279
.Lbb1270:
	movq %rax, -32(%rcx)
.Lbb1271:
	movq $0, -2040(%rbp)
	jmp .Lbb1279
.Lbb1272:
	movq -2040(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1279
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1278
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1277
	movq -32(%rcx), %rsi
	cmpq $0, %rsi
	jnz .Lbb1277
	.loc 1 444
	leaq -2040(%rbp), %rsi
	movq %rdi, %r12
	movq %r15, %rdi
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_unloan
	movq %r12, %rdi
	movq -432(%rbp), %r12
	jmp .Lbb1279
.Lbb1277:
	movq %rax, -24(%rcx)
.Lbb1278:
	movq $0, -2040(%rbp)
.Lbb1279:
	movq -2248(%rbp), %rax
	movq %rax, -2040(%rbp)
	movl $1, -2304(%rbp)
.Lbb1280:
	movq -2040(%rbp), %rax
	cmpq $0, %rax
	jz .Lbb1284
	movq -16(%rax), %rcx
	movq $6917529027641081858, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb1283
	movq -32(%rax), %rax
	cmpq $2, %rax
	jb .Lbb1284
.Lbb1283:
	.loc 1 444
	leaq -2304(%rbp), %rcx
	leaq -2040(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	callq myl_qbe_rc_unique_local
	movq %r12, %rdi
	movq -432(%rbp), %r12
	cmpl $0, %eax
	jz .Lbb2614
.Lbb1284:
	movq -2040(%rbp), %rcx
	movq (%rcx), %rsi
	movq 8(%rcx), %r11
	movq 16(%rcx), %rax
	movq 32(%rcx), %r9
	imulq $24, %rsi, %r10
	leaq -1824(%rbp), %r8
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
	jnz .Lbb1287
	.loc 1 444
	leaq -1824(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq %rcx, %rsi
	movq %rdi, %r12
	movq %r15, %rdi
	callq myl_t_a29cdb61df1464ef45ddedc7a042fd8f4fab0fd1c7c0c694df708d0b61e21222_rcg_list_append
	movq %r12, %rdi
	movq -432(%rbp), %r12
	cmpl $0, %eax
	jnz .Lbb1288
	.loc 1 444
	callq myl_qbe_fail_allocation
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1287:
	movq -1824(%rbp), %r8
	movq %r8, 0(%r9, %r10, 1)
	movq -1816(%rbp), %r8
	movq %r8, 8(%r9, %r10, 1)
	movq -1808(%rbp), %r8
	movq %r8, 16(%r9, %r10, 1)
	addq $1, %rsi
	movq %rsi, (%rcx)
	addq $1, %rax
	movq %rax, 16(%rcx)
.Lbb1288:
	movq -2048(%rbp), %rax
	movq (%rax), %rax
	cmpq %rax, %r12
	jnz .Lbb1294
	movq $1, -1840(%rbp)
	movq $9223372036854775806, %rax
	cmpq %rax, %r13
	jg .Lbb1292
	addq $1, %r13
	movl $2, %r14d
	jmp .Lbb1250
.Lbb1292:
	movq %r13, %rsi
	.loc 1 451
	movl $64, %r8d
	movl $1, %ecx
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1294:
	.loc 1 447
	movq %rdi, %rbx
	callq myl_qbe_fail_iteration
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1295:
	movq %rdi, %rbx
	movq %r15, %rdi
	.loc 1 444
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 444
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb1297:
	movq %rsi, %rdx
	.loc 1 440
	movl $64, %r8d
	movl $3, %ecx
	movq %rdx, -1240(%rbp)
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1299:
	movq %r13, %rsi
	movq %rcx, %rdx
	.loc 1 432
	movq %rdx, -1240(%rbp)
	callq myl_qbe_fail_normalized_index_bounds
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1301:
	.loc 1 429
	movq %rdi, %rbx
	callq myl_qbe_fail_iteration
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1302:
	movl -440(%rbp), %esi
	movq %rbx, %rcx
	movq -456(%rbp), %r12
	movq -1200(%rbp), %r8
	movq -448(%rbp), %rdx
	movl -496(%rbp), %r10d
	movl -500(%rbp), %r9d
	movq %rdi, %rbx
	movq %r15, %rdi
	movq -2040(%rbp), %rax
	movq %rax, -2256(%rbp)
	cmpl $0, %esi
	jnz .Lbb1316
	cmpq $0, %rax
	jnz .Lbb1306
	movq %r8, %r15
	jmp .Lbb1313
.Lbb1306:
	movq -16(%rax), %rsi
	movq $4611686018427387906, %r9
	andq %rsi, %r9
	cmpq $0, %r9
	jnz .Lbb1312
	movq -32(%rax), %rsi
	addq $1, %rsi
	jz .Lbb1310
	movq %rsi, -32(%rax)
	movq %r8, %r15
	jmp .Lbb1313
.Lbb1310:
	movq %rbx, %rdi
	.loc 1 456
	movl $2, %esi
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb1312:
	movq %r8, %r15
	movq $4611686018427387904, %r8
	andq %r8, %rsi
	cmpq $0, %rsi
	jnz .Lbb1314
.Lbb1313:
	movq %rax, -2248(%rbp)
	jmp .Lbb1323
.Lbb1314:
	.loc 1 456
	movq %rcx, %r14
	movq %rdx, %r13
	leaq -2256(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_retain
	movq %r14, %rcx
	movq %rdx, -1240(%rbp)
	movq %r13, %rdx
	movq %r12, %rdi
	movl -1516(%rbp), %r14d
	movq -456(%rbp), %r12
	cmpl $0, %eax
	jnz .Lbb1323
	.loc 1 456
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 456
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb1316:
	movq %r8, %r15
	movl %r9d, %esi
	orl %r10d, %esi
	jnz .Lbb1321
	cmpq $0, %rax
	jz .Lbb1320
	movq -16(%rax), %rax
	movq $5764607523034234881, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1321
.Lbb1320:
	movq -2256(%rbp), %rax
	movq %rax, -2248(%rbp)
	movq $0, -2256(%rbp)
	jmp .Lbb1323
.Lbb1321:
	.loc 1 456
	movq %rcx, %r14
	movq %rdx, %r13
	leaq -2256(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_take
	movq %r14, %rcx
	movq %rdx, -1240(%rbp)
	movq %r13, %rdx
	movq %r12, %rdi
	movl -1516(%rbp), %r14d
	movq -456(%rbp), %r12
	cmpl $0, %eax
	jnz .Lbb1323
	.loc 1 456
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 456
	movq %rdi, %rbx
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb1323:
	movq -2248(%rbp), %rax
	movq %rax, -2032(%rbp)
	movl -2304(%rbp), %eax
	cmpl $0, %eax
	jnz .Lbb1325
	movq %rcx, %r14
	movq %rdx, %r13
	jmp .Lbb1346
.Lbb1325:
	movl $0, -2304(%rbp)
	testl $28, %r14d
	jnz .Lbb1336
	movq -2040(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb1335
	movq -16(%rsi), %rax
	movq %rdx, %r13
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb1333
	movq -32(%rsi), %rax
	subq $1, %rax
	jnz .Lbb1332
	movq %rcx, %r14
	movq -24(%rsi), %rcx
	cmpq $0, %rcx
	jnz .Lbb1331
	.loc 1 456
	leaq -2040(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_drop
	movq %r14, %rcx
	movq %rdx, -1240(%rbp)
	movq %r13, %rdx
	movq %r12, %rdi
	movq -456(%rbp), %r12
	jmp .Lbb1335
.Lbb1331:
	movq %r14, %rcx
.Lbb1332:
	movq %r13, %rdx
	movq %rax, -32(%rsi)
	jmp .Lbb1334
.Lbb1333:
	movq %r13, %rdx
.Lbb1334:
	movq $0, -2040(%rbp)
.Lbb1335:
	movq %rcx, %r14
	movq %rdx, %r13
	jmp .Lbb1346
.Lbb1336:
	movq %rcx, %r14
	movq -2040(%rbp), %rcx
	cmpq $0, %rcx
	jnz .Lbb1338
	movq %rdx, %r13
	jmp .Lbb1346
.Lbb1338:
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1344
	movq -24(%rcx), %rax
	subq $1, %rax
	jz .Lbb1341
	movq %rdx, %r13
	jmp .Lbb1343
.Lbb1341:
	movq %rdx, %r13
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1343
	.loc 1 456
	leaq -2040(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movq -456(%rbp), %r12
	jmp .Lbb1346
.Lbb1343:
	movq %rax, -24(%rcx)
	jmp .Lbb1345
.Lbb1344:
	movq %rdx, %r13
.Lbb1345:
	movq $0, -2040(%rbp)
.Lbb1346:
	movq %r13, -1840(%rbp)
	cmpq $0, %r13
	jg .Lbb1348
	movl $0, %edx
	jmp .Lbb1351
.Lbb1348:
	movq $0, -1840(%rbp)
	movq $0, -1840(%rbp)
	cmpq $0, %r12
	jl .Lbb2610
	cmpq $0, %r13
	jl .Lbb2608
	movq %r13, %rdx
.Lbb1351:
	.loc 1 499
	movq %rdx, -1240(%rbp)
	movq myl_t_277089d91c0bdf4f2e6862ba7e4a07605119431f5d13f726dd352b06f1b206a9@gotpcrel(%rip), %rsi
	movq %rdi, %r12
	callq myl_native_list_new
	movq %r14, %rcx
	movq %rdx, -1240(%rbp)
	movq %r13, %rdx
	movq %r12, %rdi
	movl -460(%rbp), %r14d
	movl -464(%rbp), %r12d
	movl -496(%rbp), %r10d
	movl -500(%rbp), %r9d
	cmpl $0, %eax
	jnz .Lbb1354
	movq %rbx, %rdi
	.loc 1 499
	movq %rdi, %r13
	callq myl_qbe_fail_allocation
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1354:
	movq %rbx, %r13
	movq %rax, -2256(%rbp)
	movq -2256(%rbp), %rsi
	movq %rsi, -2248(%rbp)
	movq -2248(%rbp), %rsi
	movq %rsi, -2288(%rbp)
	movq %rax, -2256(%rbp)
	movl %r9d, %esi
	orl %r10d, %esi
	jnz .Lbb1360
	cmpq $0, %rax
	jz .Lbb1358
	movq -16(%rax), %rax
	movq $5764607523034234881, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1360
.Lbb1358:
	movq -2256(%rbp), %rax
	movq %rax, -2248(%rbp)
	movq $0, -2256(%rbp)
	movq %rdx, %rbx
	movl %r14d, %edx
	jmp .Lbb1363
.Lbb1360:
	.loc 1 500
	movq %rcx, %r14
	movq %rdx, %r12
	leaq -2256(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_take
	movq %r14, %rcx
	movq %rdx, -1240(%rbp)
	movq %r12, %rdx
	movq %rbx, %rdi
	movq %rdx, %rbx
	movl -460(%rbp), %edx
	movl -464(%rbp), %r12d
	cmpl $0, %eax
	jnz .Lbb1363
	movq %r13, %rbx
	.loc 1 500
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 500
	movq %rdi, %r13
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb1363:
	movl -2296(%rbp), %eax
	cmpl $0, %eax
	jnz .Lbb1365
	movq %rcx, %r14
	movq %r15, %r8
	movl %edx, %r15d
	jmp .Lbb1376
.Lbb1365:
	movl $0, -2296(%rbp)
	movq %rcx, %r14
	movq -2024(%rbp), %rcx
	cmpq $0, %rcx
	jnz .Lbb1367
	movq %r15, %r8
	movl %edx, %r15d
	jmp .Lbb1376
.Lbb1367:
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rsi
	andq %rsi, %rax
	cmpq $0, %rax
	jnz .Lbb1374
	movq -32(%rcx), %rax
	subq $1, %rax
	jz .Lbb1370
	movq %r15, %r8
	jmp .Lbb1373
.Lbb1370:
	movq -24(%rcx), %rsi
	cmpq $0, %rsi
	jnz .Lbb1372
	.loc 1 500
	leaq -2024(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_drop
	movq %r15, %r8
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl -460(%rbp), %r15d
	movl -464(%rbp), %r12d
	jmp .Lbb1376
.Lbb1372:
	movq %r15, %r8
.Lbb1373:
	movl %edx, %r15d
	movq %rax, -32(%rcx)
	jmp .Lbb1375
.Lbb1374:
	movq %r15, %r8
	movl %edx, %r15d
.Lbb1375:
	movq $0, -2024(%rbp)
.Lbb1376:
	movq -2248(%rbp), %rax
	movq %rax, -2024(%rbp)
	movl $1, -2296(%rbp)
	movl %r12d, -1440(%rbp)
	movq %rbx, %r12
	movq %r14, %rbx
	movl %r15d, -512(%rbp)
	movq %rdi, %r15
	movq %r13, %rdi
	movl $2, -564(%rbp)
	movl $0, %eax
.p2align 4
.Lbb1378:
	movq %r8, %r13
	movq %rax, -480(%rbp)
	movq %r12, -1840(%rbp)
	cmpq %r12, %rax
	setl %cl
	movzbq %cl, %rcx
	cmpl $0, %ecx
	jz .Lbb1427
	movq %r13, -1840(%rbp)
	.loc 1 507
	movq %r13, %rdx
	movq %rdx, -1240(%rbp)
	movq %rax, %rsi
	movq %rdi, %r14
	callq myl_f_9b49081a6b2287f0b352a5145304597c577561f78778b00b14cf8abdb61281d6
	movq %rdx, -1240(%rbp)
	movq %r14, %rdi
	movq %rax, %rcx
	movl -1440(%rbp), %r14d
	movq %rcx, -472(%rbp)
	movq %rcx, -2256(%rbp)
	movq -2256(%rbp), %rax
	movq %rax, -2248(%rbp)
	movq -2248(%rbp), %rax
	movq %rax, -2288(%rbp)
	cmpl $16, %r14d
	setz %al
	movzbl %al, %eax
	movl -2296(%rbp), %edx
	testl %eax, %edx
	jnz .Lbb1381
	movq %rcx, %rbx
	jmp .Lbb1406
.Lbb1381:
	movq -2024(%rbp), %rax
	cmpq $0, %rax
	jz .Lbb1387
	movq -16(%rax), %rdx
	movq $4611686018427387906, %rsi
	andq %rdx, %rsi
	cmpq $0, %rsi
	jnz .Lbb1386
	movq -32(%rax), %rdx
	addq $1, %rdx
	jz .Lbb1385
	movq %rdx, -32(%rax)
	jmp .Lbb1387
.Lbb1385:
	.loc 1 508
	movl $2, %esi
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb1386:
	movq $4611686018427387904, %rsi
	andq %rsi, %rdx
	cmpq $0, %rdx
	jnz .Lbb1388
.Lbb1387:
	movq %rcx, %rbx
	movq %rax, -2248(%rbp)
	jmp .Lbb1389
.Lbb1388:
	.loc 1 508
	movl %ebx, %ecx
	leaq -2024(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %rbx
	movq %r15, %rdi
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_retain
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movq -472(%rbp), %rbx
	cmpl $0, %eax
	jz .Lbb1425
.Lbb1389:
	movl -2296(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb1405
	movl $0, -2296(%rbp)
	testl $28, %r14d
	jnz .Lbb1398
	movq -2024(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1405
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb1397
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1396
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1396
	.loc 1 508
	leaq -2024(%rbp), %rsi
	movq %rdi, %r14
	movq %r15, %rdi
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r14, %rdi
	jmp .Lbb1405
.Lbb1396:
	movq %rax, -32(%rcx)
.Lbb1397:
	movq $0, -2024(%rbp)
	jmp .Lbb1405
.Lbb1398:
	movq -2024(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1405
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb1404
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1403
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb1403
	.loc 1 508
	leaq -2024(%rbp), %rsi
	movq %rdi, %r14
	movq %r15, %rdi
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r14, %rdi
	jmp .Lbb1405
.Lbb1403:
	movq %rax, -24(%rcx)
.Lbb1404:
	movq $0, -2024(%rbp)
.Lbb1405:
	movq -2248(%rbp), %rax
	movq %rax, -2024(%rbp)
	movl $1, -2296(%rbp)
.Lbb1406:
	movq -2024(%rbp), %rax
	cmpq $0, %rax
	jz .Lbb1410
	movq -16(%rax), %rcx
	movq $6917529027641081858, %rdx
	andq %rdx, %rcx
	cmpq $0, %rcx
	jnz .Lbb1409
	movq -32(%rax), %rax
	cmpq $2, %rax
	jb .Lbb1410
.Lbb1409:
	.loc 1 508
	leaq -2296(%rbp), %rcx
	leaq -2024(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a@gotpcrel(%rip), %rsi
	movq %rdi, %r14
	callq myl_qbe_rc_unique_local
	movq %rdx, -1240(%rbp)
	movq %r14, %rdi
	cmpl $0, %eax
	jz .Lbb2614
.Lbb1410:
	movq -2024(%rbp), %rsi
	movq %rbx, -2216(%rbp)
	.loc 1 508
	leaq -2216(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	movq %rdi, %rbx
	movq %r15, %rdi
	callq myl_t_277089d91c0bdf4f2e6862ba7e4a07605119431f5d13f726dd352b06f1b206a9_rcg_list_append
	movq %r13, %r8
	movq %rbx, %rdi
	movl %eax, %ecx
	movl -492(%rbp), %r14d
	movq -480(%rbp), %rax
	movq -488(%rbp), %rbx
	cmpl $0, %ecx
	jz .Lbb1424
	movq -2288(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb1419
	movq -16(%rsi), %rcx
	movq $4611686018427387906, %r9
	andq %r9, %rcx
	cmpq $0, %rcx
	jnz .Lbb1418
	movq -32(%rsi), %rcx
	subq $1, %rcx
	jnz .Lbb1417
	movq %r8, %r13
	movq -24(%rsi), %r8
	cmpq $0, %r8
	jnz .Lbb1416
	.loc 1 508
	leaq -2288(%rbp), %rsi
	movq %rdi, %rbx
	movq %r15, %rdi
	callq myl_t_277089d91c0bdf4f2e6862ba7e4a07605119431f5d13f726dd352b06f1b206a9_rcg_drop
	movq %r13, %r8
	movq %rbx, %rdi
	movl -492(%rbp), %r14d
	movq -480(%rbp), %rax
	movq -488(%rbp), %rbx
	jmp .Lbb1419
.Lbb1416:
	movq %r13, %r8
.Lbb1417:
	movq %rcx, -32(%rsi)
.Lbb1418:
	movq $0, -2288(%rbp)
.Lbb1419:
	movq $1, -1840(%rbp)
	movq $9223372036854775806, %rcx
	cmpq %rcx, %rax
	jg .Lbb1422
	addq $1, %rax
	movl $2, -1440(%rbp)
	movl %r14d, -512(%rbp)
	movl $2, -564(%rbp)
	jmp .Lbb1378
.Lbb1422:
	movq %rax, %rdx
	.loc 1 512
	movl $64, %r8d
	movl $1, %ecx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1424:
	.loc 1 508
	movq %rdi, %rbx
	callq myl_qbe_fail_allocation
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1425:
	movq %rdi, %rbx
	movq %r15, %rdi
	.loc 1 508
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 508
	movq %rdi, %r13
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb1427:
	movl -512(%rbp), %eax
	movq %rbx, %r14
	movq -1216(%rbp), %rcx
	movq %r13, %r8
	movq %r12, %rbx
	movl -1440(%rbp), %r12d
	movl -496(%rbp), %r10d
	movl -500(%rbp), %r9d
	movq %rdi, %r13
	movq %r15, %rdi
	movl -564(%rbp), %r15d
	movq -2024(%rbp), %r11
	movq %r11, -2256(%rbp)
	movl %r15d, %esi
	andl $24, %esi
	cmpl $0, %esi
	setz %sil
	movzbl %sil, %esi
	movl %esi, -504(%rbp)
	movl -504(%rbp), %esi
	andl %eax, %esi
	movl %esi, -508(%rbp)
	movq -1448(%rbp), %rsi
	cmpl $0, -508(%rbp)
	jnz .Lbb1466
	movq %r11, %r9
	cmpq $0, %r9
	jnz .Lbb1432
	movq %rcx, %r14
	jmp .Lbb1439
.Lbb1432:
	movq -16(%r9), %r10
	movq $4611686018427387906, %r11
	andq %r10, %r11
	cmpq $0, %r11
	jnz .Lbb1437
	movq %rcx, %r14
	movq -32(%r9), %rcx
	addq $1, %rcx
	jz .Lbb1435
	movq %rcx, -32(%r9)
	jmp .Lbb1439
.Lbb1435:
	movq %r13, %rdi
	.loc 1 517
	movl $2, %esi
	movq %rdi, %r13
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb1437:
	xchgq %r14, %rcx
	movq $4611686018427387904, %r11
	andq %r11, %r10
	cmpq $0, %r10
	jnz .Lbb1441
.Lbb1439:
	movq %r9, %rcx
	movq %rcx, -2248(%rbp)
	movq %r14, %rcx
	movl %r15d, %r14d
	movl %eax, %r15d
	jmp .Lbb1445
.Lbb1441:
	movq %rbx, %rdx
	.loc 1 517
	movq %rdx, %rbx
	leaq -2256(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_retain
	movq %r14, %rcx
	movq %r12, %rdi
	movl -1440(%rbp), %r12d
	movl -512(%rbp), %r14d
	movl %r14d, %r15d
	movl -564(%rbp), %r14d
	movq -1200(%rbp), %r8
	movq -1448(%rbp), %rsi
	cmpl $0, %eax
	jnz .Lbb1445
	movq %r13, %rbx
	.loc 1 517
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 517
	movq %rdi, %r13
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb1445:
	cmpl $0, %r15d
	jnz .Lbb1447
	movq %rcx, %r14
	jmp .Lbb1465
.Lbb1447:
	testl $28, %r14d
	jnz .Lbb1457
	movq -2288(%rbp), %r9
	cmpq $0, %r9
	jz .Lbb1456
	movq -16(%r9), %rax
	movq $4611686018427387906, %r10
	andq %r10, %rax
	cmpq $0, %rax
	jnz .Lbb1455
	movq -32(%r9), %rax
	subq $1, %rax
	jnz .Lbb1454
	movq %rcx, %r14
	movq -24(%r9), %rcx
	cmpq $0, %rcx
	jnz .Lbb1453
	.loc 1 517
	leaq -2288(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_drop
	movq %r14, %rcx
	movq %r12, %rdi
	movl -1440(%rbp), %r12d
	movq -1200(%rbp), %r8
	movq -1448(%rbp), %rsi
	jmp .Lbb1456
.Lbb1453:
	movq %r14, %rcx
.Lbb1454:
	movq %rax, -32(%r9)
.Lbb1455:
	movq $0, -2288(%rbp)
.Lbb1456:
	movq %rcx, %r14
	movl $0, %r15d
	jmp .Lbb1465
.Lbb1457:
	movq %rcx, %r14
	movq -2288(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb1464
	movq -16(%rcx), %rax
	movq $4611686018427387906, %r9
	andq %r9, %rax
	cmpq $0, %rax
	jnz .Lbb1463
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb1462
	movq -32(%rcx), %r9
	cmpq $0, %r9
	jnz .Lbb1462
	.loc 1 517
	leaq -2288(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_unloan
	movq %r12, %rdi
	movl -1440(%rbp), %r12d
	movq -1200(%rbp), %r8
	movq -1448(%rbp), %rsi
	jmp .Lbb1464
.Lbb1462:
	movq %rax, -24(%rcx)
.Lbb1463:
	movq $0, -2288(%rbp)
.Lbb1464:
	movl $0, %r15d
.Lbb1465:
	movq %r14, %rcx
	movl %r15d, -568(%rbp)
	movq %rdi, %r15
	movq %r13, %rdi
	jmp .Lbb1477
.Lbb1466:
	movq %r11, %rax
	xchgq %r14, %rcx
	orl %r10d, %r9d
	jnz .Lbb1472
	cmpq $0, %rax
	jz .Lbb1470
	movq -16(%rax), %rax
	movq $5764607523034234881, %r9
	andq %r9, %rax
	cmpq $0, %rax
	jnz .Lbb1472
.Lbb1470:
	movq -2256(%rbp), %rax
	movq %rax, -2248(%rbp)
	movq $0, -2256(%rbp)
	movq %rdi, %r15
	movq %r14, %rcx
	movq %r13, %rdi
	jmp .Lbb1476
.Lbb1472:
	movq %rbx, %rdx
	.loc 1 517
	movq %rdx, %rbx
	leaq -2256(%rbp), %rdx
	movq %rdx, -1240(%rbp)
	leaq -2248(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_take
	movq %r14, %rcx
	movq %r12, %rdi
	movl -1440(%rbp), %r12d
	movq -1200(%rbp), %r8
	movq -1448(%rbp), %rsi
	cmpl $0, %eax
	jnz .Lbb1475
	movq %r13, %rbx
	.loc 1 517
	movq %rdi, %r15
	callq myl_rc_take_failure
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl %eax, %esi
	.loc 1 517
	callq myl_qbe_rc_status
	movq %rdx, -1240(%rbp)
	jmp .Lbb2614
.Lbb1475:
	movq %rdi, %r15
	movq %r13, %rdi
.Lbb1476:
	movl $0, -568(%rbp)
.Lbb1477:
	movq -2248(%rbp), %rax
	movq %rax, -2016(%rbp)
	movl -2296(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb1495
	movl $0, -2296(%rbp)
	testl $28, %r12d
	jnz .Lbb1487
	movq -2024(%rbp), %r9
	cmpq $0, %r9
	jz .Lbb1495
	movq -16(%r9), %rax
	movq $4611686018427387906, %r10
	andq %r10, %rax
	cmpq $0, %rax
	jnz .Lbb1486
	movq -32(%r9), %rax
	subq $1, %rax
	jnz .Lbb1485
	movq %rcx, %r13
	movq -24(%r9), %rcx
	cmpq $0, %rcx
	jnz .Lbb1484
	.loc 1 517
	leaq -2024(%rbp), %rsi
	movq %rdi, %r12
	movq %r15, %rdi
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_drop
	movq %r13, %rcx
	movq %r12, %rdi
	movq -1200(%rbp), %r8
	movq -1448(%rbp), %rsi
	jmp .Lbb1495
.Lbb1484:
	movq %r13, %rcx
.Lbb1485:
	movq %rax, -32(%r9)
.Lbb1486:
	movq $0, -2024(%rbp)
	jmp .Lbb1495
.Lbb1487:
	movq -2024(%rbp), %r9
	cmpq $0, %r9
	jz .Lbb1495
	movq -16(%r9), %rax
	movq $4611686018427387906, %r10
	andq %r10, %rax
	cmpq $0, %rax
	jnz .Lbb1494
	movq -24(%r9), %rax
	subq $1, %rax
	jnz .Lbb1493
	movq %rcx, %r13
	movq -32(%r9), %rcx
	cmpq $0, %rcx
	jnz .Lbb1492
	.loc 1 517
	leaq -2024(%rbp), %rsi
	movq %rdi, %r12
	movq %r15, %rdi
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_unloan
	movq %r13, %rcx
	movq %r12, %rdi
	movq -1200(%rbp), %r8
	movq -1448(%rbp), %rsi
	jmp .Lbb1495
.Lbb1492:
	movq %r13, %rcx
.Lbb1493:
	movq %rax, -24(%r9)
.Lbb1494:
	movq $0, -2024(%rbp)
.Lbb1495:
	movq $2, -1840(%rbp)
	movq %r8, %rax
	andq $1, %rax
	movq $0, -1840(%rbp)
	cmpq $0, %rax
	movq %rcx, %r13
	movq myl_f_fbed9662b733fdfc404927bad78ff653690e8f62f873cdf248e33fd8d09121dc@gotpcrel(%rip), %rcx
	movq myl_f_9b69cc26102b21a7460fda3a7ab6db6c07257af409e687daefa36812e17816b3@gotpcrel(%rip), %rax
	mov %rax, %r11
	cmovnz %rcx, %r11
	movq %r11, -1488(%rbp)
	.loc 1 534
	movq %rdi, %r12
	callq myl_f_8a5a050356fb7a5094326f2b8ccffa083f61d461495e1103718ebd5cfb6ac591
	movq %r13, %rcx
	movq %r12, %rdi
	movq %rax, -1504(%rbp)
	movl -564(%rbp), %r13d
	movq -1184(%rbp), %r12
	movq -520(%rbp), %r10
	movq -1200(%rbp), %r8
	movq -1472(%rbp), %rsi
	cmpq $3, %r12
	setz %al
	movzbq %al, %rax
	movq %rax, -536(%rbp)
	movl $4294967295, %eax
	movq %rbx, %r9
	andq %rax, %r9
	movq %rbx, %r14
	shrq $32, %r14
	imulq $3, %r9, %rax
	shrq $32, %rax
	imulq $3, %r14, %r11
	addq %r11, %rax
	movl $4294967295, %r11d
	movq %r11, -528(%rbp)
	movq %rax, %r11
	andq -528(%rbp), %r11
	movq %r11, -552(%rbp)
	movq %rax, %r11
	shrq $32, %r11
	movq %r11, -544(%rbp)
	movq -536(%rbp), %rax
	imulq $0, %r9, %r9
	movq %r9, -560(%rbp)
	movq -544(%rbp), %r11
	movq -552(%rbp), %r9
	addq -560(%rbp), %r9
	shrq $32, %r9
	imulq $0, %r14, %r14
	addq %r14, %r11
	addq %r11, %r9
	negq %r10
	movq %r10, %r11
	andq $3, %r11
	movq %rbx, %r10
	andq $0, %r10
	subq %r11, %r9
	movq %r9, %r11
	subq %r10, %r11
	movq %r11, -1176(%rbp)
	imulq $3, %rbx, %r10
	movq %r10, -1192(%rbp)
	movq %r10, %r9
	sarq $63, %r9
	movq %r9, -1264(%rbp)
	movq %r10, %r9
	addq $3, %r9
	movq %r9, -1208(%rbp)
	cmpq $-1, %r9
	setz %r14b
	movzbq %r14b, %r14
	movq %r14, -1424(%rbp)
	movq %r9, %r14
	xorq $1, %r14
	movq %r14, -1496(%rbp)
	movq %rax, -1480(%rbp)
	movl -568(%rbp), %r14d
	movq %rcx, %rax
	movq %r9, %rcx
	movq %r10, %r9
	xchgq %r12, %rbx
	movq $0, -1280(%rbp)
	movl $0, %r10d
.p2align 4
.Lbb1498:
	movl %r14d, -996(%rbp)
	movq %r10, -1416(%rbp)
	movq %rsi, -1840(%rbp)
	cmpq %rsi, %r10
	jge .Lbb2423
	movq $17, -1840(%rbp)
	movq %r10, %rsi
	sarq $63, %rsi
	movq %rsi, -632(%rbp)
	movq -632(%rbp), %rsi
	xorq %r10, %rsi
	movq %rsi, -576(%rbp)
	movq -576(%rbp), %rsi
	subq -632(%rbp), %rsi
	movq %rsi, -584(%rbp)
	movq $-1085102592571150095, %rsi
	movq %rsi, -592(%rbp)
	movq %rax, %rsi
	movq -584(%rbp), %rax
	mulq -592(%rbp)
	movq %rsi, %rax
	movq %rdx, -600(%rbp)
	movq -600(%rbp), %rsi
	shrq $4, %rsi
	movq %rsi, -608(%rbp)
	movq -632(%rbp), %rsi
	xorq -608(%rbp), %rsi
	movq %rsi, -616(%rbp)
	movq -616(%rbp), %rsi
	subq -632(%rbp), %rsi
	movq %rsi, -624(%rbp)
	movq %r10, %rsi
	movl $17, %r10d
	imulq -624(%rbp), %r10
	movq %r10, -640(%rbp)
	movq %rbx, %r10
	movq -632(%rbp), %rbx
	subq -640(%rbp), %rsi
	movq %rsi, -648(%rbp)
	cmpq $0, %rsi
	setnz %sil
	movzbq %sil, %rsi
	movq %rsi, -656(%rbp)
	movq -648(%rbp), %rsi
	andq -656(%rbp), %rbx
	negq %rbx
	andq $17, %rbx
	addq %rsi, %rbx
	cmpq $0, %r10
	jnz .Lbb1533
	movl $0, %esi
	movl $0, %edi
.p2align 4
.Lbb1501:
	movq %r12, -1840(%rbp)
	cmpq %r12, %rdi
	jge .Lbb1532
	movq -2088(%rbp), %rax
	movq (%rax), %rcx
	cmpq %rcx, %rdi
	setb %cl
	movzbq %cl, %rcx
	cmpl $0, %ecx
	jnz .Lbb1515
	movq $0, -1840(%rbp)
	cmpq $0, %rdi
	jl .Lbb1505
	movq %rdi, %r9
	jmp .Lbb1507
.Lbb1505:
	movq (%rax), %r10
	movq $9223372036854775807, %rcx
	cmpq %rcx, %r10
	ja .Lbb1513
	movq %rdi, -1840(%rbp)
	movq %r10, %r9
	addq %rdi, %r9
	movq %r10, %rcx
	xorq %r9, %rcx
	movq %rdi, %r8
	xorq %r9, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jl .Lbb1511
.Lbb1507:
	movq (%rax), %rcx
	cmpq %rcx, %r9
	jae .Lbb1509
	movq 32(%rax), %rax
	movq (%rax, %r9, 8), %rax
	jmp .Lbb1516
.Lbb1509:
	movq %rcx, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 572
	movq %rdx, -1240(%rbp)
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1511:
	movq %rdi, %rdx
	movq %r10, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 569
	movl $64, %r8d
	movq %rdx, %rcx
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1513:
	movq %r10, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 567
	movl $320, %edx
	movq %rdx, -1240(%rbp)
	callq myl_qbe_fail_cast
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1515:
	movq 32(%rax), %rax
	movq (%rax, %rdi, 8), %rax
.Lbb1516:
	movq $0, -1840(%rbp)
	movq %rbx, -1840(%rbp)
	movq %rbx, %r9
	addq %rax, %r9
	movq %r9, %rcx
	xorq %rax, %rcx
	movq %rbx, %r8
	xorq %r9, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jl .Lbb1530
	movq $17, -1840(%rbp)
	imulq $17, %r9, %rax
	movl $4294967295, %ecx
	movq %r9, %r11
	andq %rcx, %r11
	movq %r9, %r10
	shrq $32, %r10
	imulq $17, %r11, %rcx
	shrq $32, %rcx
	imulq $17, %r10, %r8
	addq %rcx, %r8
	movl $4294967295, %ecx
	andq %r8, %rcx
	shrq $32, %r8
	imulq $0, %r11, %r11
	addq %r11, %rcx
	shrq $32, %rcx
	imulq $0, %r10, %r10
	addq %r10, %r8
	addq %r8, %rcx
	cmpq $0, %r9
	setl %r8b
	movzbq %r8b, %r8
	negq %r8
	movq %r8, %r10
	andq $17, %r10
	movq %r9, %r8
	andq $0, %r8
	subq %r10, %rcx
	negq %r8
	addq %rcx, %r8
	movq %rax, %rcx
	sarq $63, %rcx
	cmpq %rcx, %r8
	jnz .Lbb1528
	movq $23, -1840(%rbp)
	movq $9223372036854775784, %rcx
	cmpq %rcx, %rax
	jg .Lbb1526
	movq $7, -1840(%rbp)
	movq %rax, %r8
	addq $23, %r8
	movq %r8, %rcx
	sarq $63, %rcx
	movq %rcx, %rax
	xorq %r8, %rax
	movq %rax, %r9
	subq %rcx, %r9
	movq $2635249153387078803, %r10
	movq %r9, %rax
	mulq %r10
	movq %rdx, %rax
	subq %rax, %r9
	shrq $1, %r9
	addq %r9, %rax
	shrq $2, %rax
	xorq %rcx, %rax
	subq %rcx, %rax
	imulq $7, %rax, %r9
	subq %r9, %r8
	cmpq $0, %r8
	setnz %r8b
	movzbq %r8b, %r8
	andq %r8, %rcx
	movq %rax, %r8
	subq %rcx, %r8
	movq $1009, -1840(%rbp)
	movq %r8, %rcx
	sarq $63, %rcx
	movq %r8, %rax
	xorq %rcx, %rax
	subq %rcx, %rax
	movq $-9086255505087856445, %r9
	mulq %r9
	movq %rdx, %rax
	shrq $9, %rax
	xorq %rcx, %rax
	subq %rcx, %rax
	imulq $1009, %rax, %rax
	negq %rax
	addq %r8, %rax
	cmpq $0, %rax
	setnz %r8b
	movzbq %r8b, %r8
	andq %r8, %rcx
	negq %rcx
	andq $1009, %rcx
	addq %rcx, %rax
	movq %rax, -1840(%rbp)
	movq %rsi, %r9
	addq %rax, %rsi
	movq %r9, %rcx
	xorq %rsi, %rcx
	movq %rax, %r8
	xorq %rsi, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jl .Lbb1524
	movq $1, -1840(%rbp)
	movq $9223372036854775806, %rax
	cmpq %rax, %rdi
	jg .Lbb1522
	addq $1, %rdi
	jmp .Lbb1501
.Lbb1522:
	movq %rdi, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 1034
	movl $64, %r8d
	movl $1, %ecx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1524:
	movq %r9, %rsi
	movq %rax, %rcx
	movq -1224(%rbp), %rdi
	.loc 1 1030
	movl $64, %r8d
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1526:
	movq %rax, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 586
	movl $64, %r8d
	movl $23, %ecx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1528:
	movq %r9, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 584
	movl $64, %r8d
	movl $17, %ecx
	movq %rdx, -1240(%rbp)
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1530:
	movq %rax, %rdx
	movq %rbx, %rcx
	movq -1224(%rbp), %rdi
	.loc 1 582
	movl $64, %r8d
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1532:
	movq -1208(%rbp), %rcx
	movq -1192(%rbp), %r9
	movq -1184(%rbp), %rbx
	movq -1176(%rbp), %r11
	movq -1216(%rbp), %rax
	movq -1200(%rbp), %r8
	movq -1224(%rbp), %rdi
	jmp .Lbb2243
.Lbb1533:
	cvtsi2sd %rbx, %xmm0
	movq %xmm0, %rsi
	movq %rsi, %xmm0
	divsd ".Lfp0"(%rip), %xmm0
	movq %xmm0, %rsi
	movq %rsi, -672(%rbp)
	movq %rsi, %xmm0
	movsd %xmm0, -664(%rbp)
	cmpq $1, %r10
	jnz .Lbb1557
	movq %rsi, %rax
	movq $0, -680(%rbp)
	movl $0, %ebx
.p2align 4
.Lbb1535:
	movq %r12, -1840(%rbp)
	cmpq %r12, %rbx
	jge .Lbb1556
	movq -2088(%rbp), %rcx
	movq (%rcx), %rdx
	cmpq %rdx, %rbx
	setb %dl
	movzbq %dl, %rdx
	cmpl $0, %edx
	jnz .Lbb1547
	movq $0, -1840(%rbp)
	cmpq $0, %rbx
	jl .Lbb1539
	movq %rbx, %r15
	jmp .Lbb1541
.Lbb1539:
	movq (%rcx), %rsi
	movq $9223372036854775807, %rdx
	cmpq %rdx, %rsi
	ja .Lbb1546
	movq %rbx, -1840(%rbp)
	movq %rsi, %r15
	addq %rbx, %r15
	movq %rsi, %rdx
	xorq %r15, %rdx
	movq %rbx, %r8
	xorq %r15, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jl .Lbb1544
.Lbb1541:
	movq (%rcx), %rdx
	cmpq %rdx, %r15
	jae .Lbb1543
	movq 32(%rcx), %rcx
	movq (%rcx, %r15, 8), %rcx
	jmp .Lbb1548
.Lbb1543:
	.loc 1 572
	movq %rdx, -1240(%rbp)
	movq %r15, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1544:
	movq %rbx, %rdx
	.loc 1 569
	movl $64, %r8d
	movq %rdx, %rcx
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1546:
	.loc 1 567
	movl $320, %edx
	movq %rdx, -1240(%rbp)
	callq myl_qbe_fail_cast
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1547:
	movq 32(%rcx), %rcx
	movq (%rcx, %rbx, 8), %rcx
.Lbb1548:
	movq $0, -1840(%rbp)
	movq $1, -1840(%rbp)
	cvtsi2sd %rcx, %xmm1
	movq %xmm1, %rcx
	movq $4620693217682128896, %rdx
	movq %rdx, -1840(%rbp)
	movsd %xmm0, %xmm1
	movq %rcx, %xmm0
	movsd %xmm0, %xmm2
	divsd ".Lfp5"(%rip), %xmm2
	movq %rax, %rcx
	movq %xmm2, %rax
	movq $4616189618054758400, %rdx
	movq %rdx, -1840(%rbp)
	movq %rcx, -1840(%rbp)
	movq %rax, %xmm2
	addsd %xmm2, %xmm1
	movq %xmm1, %rcx
	movq $4625196817309499392, %rax
	movq %rax, -1840(%rbp)
	divsd ".Lfp4"(%rip), %xmm0
	movq %xmm0, %rax
	movq $4607182418800017408, %rdx
	movq %rdx, -1840(%rbp)
	movq %rax, %xmm0
	addsd ".Lfp3"(%rip), %xmm0
	movq %xmm0, %rax
	movq %rax, -1840(%rbp)
	movq %rcx, %xmm0
	movq %rax, %xmm1
	mulsd %xmm1, %xmm0
	movq %xmm0, %rax
	movq $4602678819172646912, %rcx
	movq %rcx, -1840(%rbp)
	movq %rax, %xmm0
	addsd ".Lfp2"(%rip), %xmm0
	movq %xmm0, %rax
	movq $4638707616191610880, %rcx
	movq %rcx, -1840(%rbp)
	movq %rax, %xmm0
	mulsd ".Lfp1"(%rip), %xmm0
	movq %xmm0, %rdx
	.loc 1 687
	movq %rdx, -1240(%rbp)
	movl $11, %esi
	callq myl_qbe_float_unary
	movq %rax, %rcx
	movq -680(%rbp), %rsi
	movsd -664(%rbp), %xmm0
	movq -672(%rbp), %rax
	movq -1224(%rbp), %rdi
	movq %rcx, -1840(%rbp)
	movq %rsi, %r9
	addq %rcx, %rsi
	movq %r9, %r8
	xorq %rsi, %r8
	movq %rcx, %r10
	xorq %rsi, %r10
	andq %r10, %r8
	cmpq $0, %r8
	jl .Lbb1554
	movq $1, -1840(%rbp)
	movq $9223372036854775806, %rcx
	cmpq %rcx, %rbx
	jg .Lbb1552
	addq $1, %rbx
	movq %rsi, -680(%rbp)
	jmp .Lbb1535
.Lbb1552:
	movq %rbx, %rdx
	.loc 1 1034
	movl $64, %r8d
	movl $1, %ecx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1554:
	movq %r9, %rsi
	.loc 1 1030
	movl $64, %r8d
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1556:
	movq -1208(%rbp), %rcx
	movq -1192(%rbp), %r9
	movq -1184(%rbp), %rbx
	movq -1232(%rbp), %r15
	movq -1176(%rbp), %r11
	movq -1216(%rbp), %rax
	movq -1200(%rbp), %r8
	movq -680(%rbp), %rsi
	jmp .Lbb2243
.Lbb1557:
	movq -1488(%rbp), %rsi
	cmpq $2, %r10
	jz .Lbb2240
	movq %rsi, %r11
	movq -1480(%rbp), %rsi
	cmpq $3, %r10
	jnz .Lbb1617
	movl $0, %esi
	movl $0, %eax
.p2align 4
.Lbb1562:
	movq %r12, -1840(%rbp)
	cmpq %r12, %rax
	jge .Lbb1616
	movq -2088(%rbp), %rcx
	movq (%rcx), %rdx
	cmpq %rdx, %rax
	setb %dl
	movzbq %dl, %rdx
	cmpl $0, %edx
	jnz .Lbb1576
	movq $0, -1840(%rbp)
	cmpq $0, %rax
	jl .Lbb1566
	movq %rax, %rdi
	jmp .Lbb1568
.Lbb1566:
	movq (%rcx), %r9
	movq $9223372036854775807, %rdx
	cmpq %rdx, %r9
	ja .Lbb1574
	movq %rax, -1840(%rbp)
	movq %r9, %rdi
	addq %rax, %rdi
	movq %r9, %rdx
	xorq %rdi, %rdx
	movq %rax, %r8
	xorq %rdi, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jl .Lbb1572
.Lbb1568:
	movq (%rcx), %rdx
	cmpq %rdx, %rdi
	jae .Lbb1570
	movq 32(%rcx), %rcx
	movq (%rcx, %rdi, 8), %rdx
	jmp .Lbb1577
.Lbb1570:
	movq %rdi, %rcx
	movq -1224(%rbp), %rdi
	.loc 1 572
	movq %rdx, -1240(%rbp)
	movq %rcx, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1572:
	movq %rax, %rcx
	movq %r9, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 569
	movl $64, %r8d
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1574:
	movq %r9, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 567
	movl $320, %edx
	movq %rdx, -1240(%rbp)
	callq myl_qbe_fail_cast
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1576:
	movq 32(%rcx), %rcx
	movq (%rcx, %rax, 8), %rdx
.Lbb1577:
	movq $0, -1840(%rbp)
	movq $1, -1840(%rbp)
	movq $2, -1840(%rbp)
	movq $3, -1840(%rbp)
	movq -2056(%rbp), %rcx
	movq $0, -1840(%rbp)
	cmpq $0, %rax
	jl .Lbb1579
	movq %rax, %rdi
	jmp .Lbb1581
.Lbb1579:
	movq (%rcx), %r9
	movq $9223372036854775807, %rdi
	cmpq %rdi, %r9
	ja .Lbb1614
	movq %rax, -1840(%rbp)
	movq %r9, %rdi
	addq %rax, %rdi
	movq %r9, %r8
	xorq %rdi, %r8
	movq %rax, %r10
	xorq %rdi, %r10
	andq %r10, %r8
	cmpq $0, %r8
	jl .Lbb1612
.Lbb1581:
	movq (%rcx), %r8
	cmpq %r8, %rdi
	jae .Lbb1610
	movq 32(%rcx), %rcx
	movzbq (%rcx, %rdi, 1), %rcx
	movq %rcx, -704(%rbp)
	movq %rbx, %rdi
	addq %rdx, %rdi
	movq %rdi, %rcx
	xorq %rdx, %rcx
	movq %rbx, %r8
	xorq %rdi, %r8
	andq %rcx, %r8
	movl $4294967295, %ecx
	andq %rdi, %rcx
	movq %rdi, %r10
	shrq $32, %r10
	imulq $0, %rcx, %r15
	imulq $0, %r10, %r11
	cmpq $0, %rdi
	setl %r9b
	movzbq %r9b, %r9
	movq %r9, -688(%rbp)
	movq -688(%rbp), %r9
	negq %r9
	movq %r9, -696(%rbp)
	movq %rdi, %r9
	andq $0, %r9
	movq %r9, -712(%rbp)
	movq -696(%rbp), %r9
	cmpl $0, -704(%rbp)
	jnz .Lbb1593
	movq %rbx, -1840(%rbp)
	cmpq $0, %r8
	movq -712(%rbp), %r8
	jl .Lbb1591
	movq $5, -1840(%rbp)
	imulq $5, %rdi, %rdx
	imulq $5, %rcx, %rcx
	shrq $32, %rcx
	imulq $5, %r10, %r10
	addq %rcx, %r10
	movl $4294967295, %ecx
	andq %r10, %rcx
	shrq $32, %r10
	addq %r15, %rcx
	shrq $32, %rcx
	addq %r11, %r10
	addq %r10, %rcx
	andq $5, %r9
	subq %r9, %rcx
	negq %r8
	addq %rcx, %r8
	movq %rdx, %rcx
	sarq $63, %rcx
	cmpq %rcx, %r8
	jnz .Lbb1589
	movq $7, -1840(%rbp)
	movq $9223372036854775800, %rcx
	cmpq %rcx, %rdx
	jg .Lbb1587
	movq %rdx, %rcx
	addq $7, %rcx
	jmp .Lbb1597
.Lbb1587:
	movq -1224(%rbp), %rdi
	.loc 1 731
	movl $64, %r8d
	movl $7, %ecx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1589:
	movq %rdi, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 729
	movl $64, %r8d
	movl $5, %ecx
	movq %rdx, -1240(%rbp)
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1591:
	movq %rbx, %rcx
	movq -1224(%rbp), %rdi
	.loc 1 727
	movl $64, %r8d
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1593:
	movq %rbx, -1840(%rbp)
	cmpq $0, %r8
	movq -712(%rbp), %r8
	jl .Lbb1608
	movq $3, -1840(%rbp)
	imulq $3, %rdi, %rdx
	imulq $3, %rcx, %rcx
	shrq $32, %rcx
	imulq $3, %r10, %r10
	addq %rcx, %r10
	movl $4294967295, %ecx
	andq %r10, %rcx
	shrq $32, %r10
	addq %r15, %rcx
	shrq $32, %rcx
	addq %r11, %r10
	addq %r10, %rcx
	andq $3, %r9
	subq %r9, %rcx
	negq %r8
	addq %rcx, %r8
	movq %rdx, %rcx
	sarq $63, %rcx
	cmpq %rcx, %r8
	jnz .Lbb1606
	movq $1, -1840(%rbp)
	movq $9223372036854775806, %rcx
	cmpq %rcx, %rdx
	jg .Lbb1604
	movq %rdx, %rcx
	addq $1, %rcx
.Lbb1597:
	movq %rcx, -1840(%rbp)
	movq %rsi, %rdi
	addq %rcx, %rsi
	movq %rdi, %rdx
	xorq %rsi, %rdx
	movq %rcx, %r8
	xorq %rsi, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jl .Lbb1602
	movq $1, -1840(%rbp)
	movq $9223372036854775806, %rcx
	cmpq %rcx, %rax
	jg .Lbb1600
	addq $1, %rax
	jmp .Lbb1562
.Lbb1600:
	movq %rax, %rcx
	movq -1224(%rbp), %rdi
	.loc 1 1034
	movl $64, %r8d
	movq %rcx, %rax
	movl $1, %ecx
	movq %rax, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1602:
	movq %rdi, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 1030
	movl $64, %r8d
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1604:
	movq -1224(%rbp), %rdi
	.loc 1 722
	movl $64, %r8d
	movl $1, %ecx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1606:
	movq %rdi, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 720
	movl $64, %r8d
	movl $3, %ecx
	movq %rdx, -1240(%rbp)
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1608:
	movq %rbx, %rcx
	movq -1224(%rbp), %rdi
	.loc 1 718
	movl $64, %r8d
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1610:
	movq %r8, %rdx
	movq %rdi, %rcx
	movq -1224(%rbp), %rdi
	.loc 1 714
	movq %rdx, -1240(%rbp)
	movq %rcx, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1612:
	movq %rax, %rcx
	movq %r9, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 711
	movl $64, %r8d
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1614:
	movq %r9, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 709
	movl $320, %edx
	movq %rdx, -1240(%rbp)
	callq myl_qbe_fail_cast
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1616:
	movq -1208(%rbp), %rcx
	movq -1192(%rbp), %r9
	movq -1184(%rbp), %rbx
	movq -1232(%rbp), %r15
	movq -1176(%rbp), %r11
	movq -1216(%rbp), %rax
	movq -1200(%rbp), %r8
	movq -1224(%rbp), %rdi
	jmp .Lbb2243
.Lbb1617:
	cmpq $4, %r10
	jnz .Lbb1663
	movl $0, %esi
	movl $0, %edi
.p2align 4
.Lbb1619:
	movq %r12, -1840(%rbp)
	cmpq %r12, %rdi
	jge .Lbb1662
	movq -2088(%rbp), %rax
	movq (%rax), %rcx
	cmpq %rcx, %rdi
	setb %cl
	movzbq %cl, %rcx
	cmpl $0, %ecx
	jnz .Lbb1633
	movq $0, -1840(%rbp)
	cmpq $0, %rdi
	jl .Lbb1623
	movq %rdi, %r9
	jmp .Lbb1625
.Lbb1623:
	movq (%rax), %r10
	movq $9223372036854775807, %rcx
	cmpq %rcx, %r10
	ja .Lbb1631
	movq %rdi, -1840(%rbp)
	movq %r10, %r9
	addq %rdi, %r9
	movq %r10, %rcx
	xorq %r9, %rcx
	movq %rdi, %r8
	xorq %r9, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jl .Lbb1629
.Lbb1625:
	movq (%rax), %rcx
	cmpq %rcx, %r9
	jae .Lbb1627
	movq 32(%rax), %rax
	movq (%rax, %r9, 8), %r11
	jmp .Lbb1634
.Lbb1627:
	movq %rcx, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 572
	movq %rdx, -1240(%rbp)
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1629:
	movq %rdi, %rdx
	movq %r10, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 569
	movl $64, %r8d
	movq %rdx, %rcx
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1631:
	movq %r10, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 567
	movl $320, %edx
	movq %rdx, -1240(%rbp)
	callq myl_qbe_fail_cast
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1633:
	movq 32(%rax), %rax
	movq (%rax, %rdi, 8), %r11
.Lbb1634:
	movq $0, -1840(%rbp)
	movq $1, -1840(%rbp)
	movq $2, -1840(%rbp)
	movq $3, -1840(%rbp)
	movq $4, -1840(%rbp)
	movq %rbx, -1840(%rbp)
	movq %rbx, %r10
	addq %r11, %r10
	movq %r10, %rax
	xorq %r11, %rax
	movq %rbx, %rcx
	xorq %r10, %rcx
	andq %rcx, %rax
	cmpq $0, %rax
	jl .Lbb1660
	movq %r11, -1840(%rbp)
	movq $17, -1832(%rbp)
	movq %r11, %rcx
	sarq $63, %rcx
	movq %rcx, %rax
	xorq %r11, %rax
	subq %rcx, %rax
	movq $-1085102592571150095, %r8
	mulq %r8
	movq %rdx, %rax
	shrq $4, %rax
	xorq %rcx, %rax
	subq %rcx, %rax
	imulq $17, %rax, %rax
	negq %rax
	addq %r11, %rax
	cmpq $0, %rax
	setnz %r8b
	movzbq %r8b, %r8
	andq %r8, %rcx
	negq %rcx
	andq $17, %rcx
	movq %rax, %r9
	addq %rcx, %r9
	movq %r9, -1840(%rbp)
	movq %r11, -1832(%rbp)
	imulq $3, %r11, %rax
	movl $4294967295, %ecx
	andq %r11, %rcx
	movq %r11, %r15
	shrq $32, %r15
	imulq $3, %rcx, %r8
	movq %r8, -720(%rbp)
	movq -720(%rbp), %r8
	shrq $32, %r8
	movq %r8, -736(%rbp)
	imulq $3, %r15, %r8
	movq %r8, -728(%rbp)
	movq -736(%rbp), %r8
	addq -728(%rbp), %r8
	movq %r8, -752(%rbp)
	movl $4294967295, %r8d
	movq %r8, -744(%rbp)
	movq -752(%rbp), %r8
	andq -744(%rbp), %r8
	movq %r8, -768(%rbp)
	movq -752(%rbp), %r8
	shrq $32, %r8
	movq %r8, -760(%rbp)
	imulq $0, %rcx, %rcx
	movq %rcx, -776(%rbp)
	movq -760(%rbp), %r8
	movq -768(%rbp), %rcx
	addq -776(%rbp), %rcx
	shrq $32, %rcx
	imulq $0, %r15, %r15
	addq %r15, %r8
	addq %r8, %rcx
	cmpq $0, %r11
	setl %r8b
	movzbq %r8b, %r8
	negq %r8
	movq %r8, %r15
	andq $3, %r15
	movq %r11, %r8
	andq $0, %r8
	subq %r15, %rcx
	negq %r8
	addq %rcx, %r8
	movq %rax, %rcx
	sarq $63, %rcx
	cmpq %rcx, %r8
	jnz .Lbb1658
	movq %rax, -1832(%rbp)
	movq %rbx, %r8
	addq %rax, %r8
	movq %rax, %rcx
	xorq %r8, %rcx
	movq %rbx, %r11
	xorq %r8, %r11
	andq %r11, %rcx
	cmpq $0, %rcx
	jl .Lbb1656
	movq %r8, -1832(%rbp)
	movq %r8, %rcx
	sarq $63, %rcx
	movq %rcx, %rax
	xorq %r8, %rax
	movq %rax, %r11
	subq %rcx, %r11
	movq $4931307821684731621, %r15
	movq %r11, %rax
	mulq %r15
	movq %rdx, %rax
	subq %rax, %r11
	shrq $1, %r11
	addq %r11, %rax
	shrq $6, %rax
	xorq %rcx, %rax
	subq %rcx, %rax
	imulq $101, %rax, %rax
	negq %rax
	addq %r8, %rax
	cmpq $0, %rax
	setnz %r8b
	movzbq %r8b, %r8
	andq %r8, %rcx
	negq %rcx
	andq $101, %rcx
	addq %rcx, %rax
	movq %rax, -1832(%rbp)
	movq %r10, -1800(%rbp)
	movq %r9, -1792(%rbp)
	movq %rax, -1784(%rbp)
	movq -1800(%rbp), %rcx
	movq %rcx, -2008(%rbp)
	movq -1792(%rbp), %rcx
	movq %rcx, -2000(%rbp)
	movq -1784(%rbp), %rcx
	movq %rcx, -1992(%rbp)
	movq -2008(%rbp), %rcx
	movq %rcx, -1776(%rbp)
	movq -2000(%rbp), %rcx
	movq %rcx, -1768(%rbp)
	movq -1992(%rbp), %rcx
	movq %rcx, -1760(%rbp)
	movq -1776(%rbp), %rcx
	movq %rcx, -1888(%rbp)
	movq -1768(%rbp), %rcx
	movq %rcx, -1880(%rbp)
	movq -1760(%rbp), %rcx
	movq %rcx, -1872(%rbp)
	leaq -1888(%rbp), %rcx
	movq %rcx, -1840(%rbp)
	movq %r9, -1840(%rbp)
	movq $3, -1832(%rbp)
	imulq $3, %r9, %rcx
	movl $4294967295, %r8d
	andq %r9, %r8
	movq %r9, %r15
	shrq $32, %r15
	imulq $3, %r8, %r11
	movq %r11, -784(%rbp)
	movq -784(%rbp), %r11
	shrq $32, %r11
	movq %r11, -800(%rbp)
	imulq $3, %r15, %r11
	movq %r11, -792(%rbp)
	movq -800(%rbp), %r11
	addq -792(%rbp), %r11
	movq %r11, -816(%rbp)
	movl $4294967295, %r11d
	movq %r11, -808(%rbp)
	movq -816(%rbp), %r11
	andq -808(%rbp), %r11
	movq %r11, -832(%rbp)
	movq -816(%rbp), %r11
	shrq $32, %r11
	movq %r11, -824(%rbp)
	imulq $0, %r8, %r8
	movq %r8, -840(%rbp)
	movq -824(%rbp), %r11
	movq -832(%rbp), %r8
	addq -840(%rbp), %r8
	shrq $32, %r8
	imulq $0, %r15, %r15
	addq %r15, %r11
	addq %r11, %r8
	cmpq $0, %r9
	setl %r11b
	movzbq %r11b, %r11
	negq %r11
	movq %r11, %r15
	andq $3, %r15
	movq %r9, %r11
	andq $0, %r11
	subq %r15, %r8
	negq %r11
	addq %r8, %r11
	movq %rcx, %r8
	sarq $63, %r8
	cmpq %r8, %r11
	jnz .Lbb1654
	movq %rcx, -1840(%rbp)
	movq %r10, %r9
	addq %rcx, %r9
	movq %r10, %r8
	xorq %r9, %r8
	movq %rcx, %r11
	xorq %r9, %r11
	andq %r11, %r8
	cmpq $0, %r8
	jl .Lbb1652
	leaq -1888(%rbp), %rcx
	movq %rcx, -1840(%rbp)
	movq %rax, -1840(%rbp)
	movq $5, -1832(%rbp)
	imulq $5, %rax, %rcx
	movl $4294967295, %r8d
	movq %rax, %r15
	andq %r8, %r15
	movq %rax, %r11
	shrq $32, %r11
	imulq $5, %r15, %r8
	shrq $32, %r8
	imulq $5, %r11, %r10
	addq %r8, %r10
	movl $4294967295, %r8d
	andq %r10, %r8
	shrq $32, %r10
	imulq $0, %r15, %r15
	addq %r15, %r8
	shrq $32, %r8
	imulq $0, %r11, %r11
	addq %r11, %r10
	addq %r10, %r8
	cmpq $0, %rax
	setl %r10b
	movzbq %r10b, %r10
	negq %r10
	movq %r10, %r11
	andq $5, %r11
	movq %rax, %r10
	andq $0, %r10
	subq %r11, %r8
	negq %r10
	addq %r8, %r10
	movq %rcx, %r8
	sarq $63, %r8
	cmpq %r8, %r10
	jnz .Lbb1650
	movq %rcx, -1840(%rbp)
	movq %r9, %rax
	addq %rcx, %rax
	movq %r9, %r8
	xorq %rax, %r8
	movq %rcx, %r10
	xorq %rax, %r10
	andq %r10, %r8
	cmpq $0, %r8
	jl .Lbb1648
	movq %rax, -1840(%rbp)
	movq %rsi, %r9
	addq %rax, %rsi
	movq %r9, %rcx
	xorq %rsi, %rcx
	movq %rax, %r8
	xorq %rsi, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jl .Lbb1646
	movq $1, -1840(%rbp)
	movq $9223372036854775806, %rax
	cmpq %rax, %rdi
	jg .Lbb1644
	addq $1, %rdi
	jmp .Lbb1619
.Lbb1644:
	movq %rdi, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 1034
	movl $64, %r8d
	movl $1, %ecx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1646:
	movq %rax, %rcx
	movq %r9, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 1030
	movl $64, %r8d
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1648:
	movq %r9, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 767
	movl $64, %r8d
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1650:
	movq %rax, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 766
	movl $64, %r8d
	movl $5, %ecx
	movq %rdx, -1240(%rbp)
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1652:
	movq %r10, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 762
	movl $64, %r8d
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1654:
	movq %r9, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 761
	movl $64, %r8d
	movl $3, %ecx
	movq %rdx, -1240(%rbp)
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1656:
	movq %rax, %rdx
	movq %rbx, %rcx
	movq -1224(%rbp), %rdi
	.loc 1 748
	movl $64, %r8d
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1658:
	movq %r11, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 746
	movl $64, %r8d
	movl $3, %ecx
	movq %rdx, -1240(%rbp)
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1660:
	movq %r11, %rdx
	movq %rbx, %rcx
	movq -1224(%rbp), %rdi
	.loc 1 740
	movl $64, %r8d
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1662:
	movq -1208(%rbp), %rcx
	movq -1192(%rbp), %r9
	movq -1184(%rbp), %rbx
	movq -1232(%rbp), %r15
	movq -1176(%rbp), %r11
	movq -1216(%rbp), %rax
	movq -1200(%rbp), %r8
	movq -1224(%rbp), %rdi
	jmp .Lbb2243
.Lbb1663:
	cmpq $5, %r10
	jnz .Lbb1723
	movl $0, %esi
	movl $0, %edi
.p2align 4
.Lbb1665:
	movq %r12, -1840(%rbp)
	cmpq %r12, %rdi
	jge .Lbb1722
	movq -2088(%rbp), %rax
	movq (%rax), %rcx
	cmpq %rcx, %rdi
	setb %cl
	movzbq %cl, %rcx
	cmpl $0, %ecx
	jnz .Lbb1679
	movq $0, -1840(%rbp)
	cmpq $0, %rdi
	jl .Lbb1669
	movq %rdi, %r9
	jmp .Lbb1671
.Lbb1669:
	movq (%rax), %r10
	movq $9223372036854775807, %rcx
	cmpq %rcx, %r10
	ja .Lbb1677
	movq %rdi, -1840(%rbp)
	movq %r10, %r9
	addq %rdi, %r9
	movq %r10, %rcx
	xorq %r9, %rcx
	movq %rdi, %r8
	xorq %r9, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jl .Lbb1675
.Lbb1671:
	movq (%rax), %rcx
	cmpq %rcx, %r9
	jae .Lbb1673
	movq 32(%rax), %rax
	movq (%rax, %r9, 8), %r11
	jmp .Lbb1680
.Lbb1673:
	movq %rcx, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 572
	movq %rdx, -1240(%rbp)
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1675:
	movq %rdi, %rdx
	movq %r10, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 569
	movl $64, %r8d
	movq %rdx, %rcx
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1677:
	movq %r10, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 567
	movl $320, %edx
	movq %rdx, -1240(%rbp)
	callq myl_qbe_fail_cast
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1679:
	movq 32(%rax), %rax
	movq (%rax, %rdi, 8), %r11
.Lbb1680:
	movq $0, -1840(%rbp)
	movq $1, -1840(%rbp)
	movq $2, -1840(%rbp)
	movq $3, -1840(%rbp)
	movq $4, -1840(%rbp)
	movq $5, -1840(%rbp)
	movq -2032(%rbp), %rax
	movq (%rax), %rcx
	cmpq %rcx, %rdi
	setb %cl
	movzbq %cl, %rcx
	cmpl $0, %ecx
	jnz .Lbb1693
	movq $0, -1840(%rbp)
	cmpq $0, %rdi
	jl .Lbb1683
	movq %rdi, %r9
	jmp .Lbb1685
.Lbb1683:
	movq (%rax), %r10
	movq $9223372036854775807, %rcx
	cmpq %rcx, %r10
	ja .Lbb1691
	movq %rdi, -1840(%rbp)
	movq %r10, %r9
	addq %rdi, %r9
	movq %r10, %rcx
	xorq %r9, %rcx
	movq %rdi, %r8
	xorq %r9, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jl .Lbb1689
.Lbb1685:
	movq (%rax), %rcx
	cmpq %rcx, %r9
	jae .Lbb1687
	movq 32(%rax), %rax
	imulq $24, %r9, %rcx
	addq %rcx, %rax
	jmp .Lbb1694
.Lbb1687:
	movq %rcx, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 789
	movq %rdx, -1240(%rbp)
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1689:
	movq %rdi, %rdx
	movq %r10, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 786
	movl $64, %r8d
	movq %rdx, %rcx
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1691:
	movq %r10, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 784
	movl $320, %edx
	movq %rdx, -1240(%rbp)
	callq myl_qbe_fail_cast
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1693:
	movq 32(%rax), %rax
	imulq $24, %rdi, %rcx
	addq %rcx, %rax
.Lbb1694:
	movq 0(%rax), %rcx
	movq %rcx, -2008(%rbp)
	movq 8(%rax), %rcx
	movq %rcx, -2000(%rbp)
	movq 16(%rax), %rax
	movq %rax, -1992(%rbp)
	movq %rbx, -1840(%rbp)
	movq %rbx, %r10
	addq %r11, %r10
	movq %r10, %rax
	xorq %r11, %rax
	movq %rbx, %rcx
	xorq %r10, %rcx
	andq %rcx, %rax
	cmpq $0, %rax
	jl .Lbb1720
	movq -2008(%rbp), %rax
	movq %rax, -1984(%rbp)
	movq -2000(%rbp), %rax
	movq %rax, -1976(%rbp)
	movq -1992(%rbp), %rax
	movq %rax, -1968(%rbp)
	movq -2008(%rbp), %rax
	movq %rax, -1984(%rbp)
	movq -2000(%rbp), %rax
	movq %rax, -1976(%rbp)
	movq -1992(%rbp), %rax
	movq %rax, -1968(%rbp)
	movq %r10, -1840(%rbp)
	movq -1984(%rbp), %rax
	movq %rax, -1752(%rbp)
	movq -1976(%rbp), %rax
	movq %rax, -1744(%rbp)
	movq -1968(%rbp), %rax
	movq %rax, -1736(%rbp)
	movq %r10, -1752(%rbp)
	movq -1752(%rbp), %rax
	movq %rax, -2008(%rbp)
	movq -1744(%rbp), %rax
	movq %rax, -2000(%rbp)
	movq -1736(%rbp), %rax
	movq %rax, -1992(%rbp)
	movq $17, -1840(%rbp)
	movq %r11, %rcx
	sarq $63, %rcx
	movq %rcx, %rax
	xorq %r11, %rax
	subq %rcx, %rax
	movq $-1085102592571150095, %r8
	mulq %r8
	movq %rdx, %rax
	shrq $4, %rax
	xorq %rcx, %rax
	subq %rcx, %rax
	imulq $17, %rax, %rax
	negq %rax
	addq %r11, %rax
	cmpq $0, %rax
	setnz %r8b
	movzbq %r8b, %r8
	andq %r8, %rcx
	negq %rcx
	andq $17, %rcx
	movq %rax, %r9
	addq %rcx, %r9
	movq -2008(%rbp), %rax
	movq %rax, -1960(%rbp)
	movq -2000(%rbp), %rax
	movq %rax, -1952(%rbp)
	movq -1992(%rbp), %rax
	movq %rax, -1944(%rbp)
	movq -2008(%rbp), %rax
	movq %rax, -1960(%rbp)
	movq -2000(%rbp), %rax
	movq %rax, -1952(%rbp)
	movq -1992(%rbp), %rax
	movq %rax, -1944(%rbp)
	movq %r9, -1840(%rbp)
	movq -1960(%rbp), %rax
	movq %rax, -1728(%rbp)
	movq -1952(%rbp), %rax
	movq %rax, -1720(%rbp)
	movq -1944(%rbp), %rax
	movq %rax, -1712(%rbp)
	movq %r9, -1720(%rbp)
	movq -1728(%rbp), %rax
	movq %rax, -2008(%rbp)
	movq -1720(%rbp), %rax
	movq %rax, -2000(%rbp)
	movq -1712(%rbp), %rax
	movq %rax, -1992(%rbp)
	movq $3, -1840(%rbp)
	imulq $3, %r11, %rax
	movl $4294967295, %ecx
	andq %r11, %rcx
	movq %r11, %r15
	shrq $32, %r15
	imulq $3, %rcx, %r8
	movq %r8, -848(%rbp)
	movq -848(%rbp), %r8
	shrq $32, %r8
	movq %r8, -864(%rbp)
	imulq $3, %r15, %r8
	movq %r8, -856(%rbp)
	movq -864(%rbp), %r8
	addq -856(%rbp), %r8
	movq %r8, -880(%rbp)
	movl $4294967295, %r8d
	movq %r8, -872(%rbp)
	movq -880(%rbp), %r8
	andq -872(%rbp), %r8
	movq %r8, -896(%rbp)
	movq -880(%rbp), %r8
	shrq $32, %r8
	movq %r8, -888(%rbp)
	imulq $0, %rcx, %rcx
	movq %rcx, -904(%rbp)
	movq -888(%rbp), %r8
	movq -896(%rbp), %rcx
	addq -904(%rbp), %rcx
	shrq $32, %rcx
	imulq $0, %r15, %r15
	addq %r15, %r8
	addq %r8, %rcx
	cmpq $0, %r11
	setl %r8b
	movzbq %r8b, %r8
	negq %r8
	movq %r8, %r15
	andq $3, %r15
	movq %r11, %r8
	andq $0, %r8
	subq %r15, %rcx
	negq %r8
	addq %rcx, %r8
	movq %rax, %rcx
	sarq $63, %rcx
	cmpq %rcx, %r8
	jnz .Lbb1718
	movq %rbx, -1840(%rbp)
	movq %rbx, %r8
	addq %rax, %r8
	movq %rax, %rcx
	xorq %r8, %rcx
	movq %rbx, %r11
	xorq %r8, %r11
	andq %r11, %rcx
	cmpq $0, %rcx
	jl .Lbb1716
	movq $101, -1840(%rbp)
	movq %r8, %rcx
	sarq $63, %rcx
	movq %rcx, %rax
	xorq %r8, %rax
	movq %rax, %r11
	subq %rcx, %r11
	movq $4931307821684731621, %r15
	movq %r11, %rax
	mulq %r15
	movq %rdx, %rax
	subq %rax, %r11
	shrq $1, %r11
	addq %r11, %rax
	shrq $6, %rax
	xorq %rcx, %rax
	subq %rcx, %rax
	imulq $101, %rax, %rax
	negq %rax
	addq %r8, %rax
	cmpq $0, %rax
	setnz %r8b
	movzbq %r8b, %r8
	andq %r8, %rcx
	negq %rcx
	andq $101, %rcx
	addq %rcx, %rax
	movq -2008(%rbp), %rcx
	movq %rcx, -1936(%rbp)
	movq -2000(%rbp), %rcx
	movq %rcx, -1928(%rbp)
	movq -1992(%rbp), %rcx
	movq %rcx, -1920(%rbp)
	movq -2008(%rbp), %rcx
	movq %rcx, -1936(%rbp)
	movq -2000(%rbp), %rcx
	movq %rcx, -1928(%rbp)
	movq -1992(%rbp), %rcx
	movq %rcx, -1920(%rbp)
	movq %rax, -1840(%rbp)
	movq -1936(%rbp), %rcx
	movq %rcx, -1704(%rbp)
	movq -1928(%rbp), %rcx
	movq %rcx, -1696(%rbp)
	movq -1920(%rbp), %rcx
	movq %rcx, -1688(%rbp)
	movq %rax, -1688(%rbp)
	movq -1704(%rbp), %rcx
	movq %rcx, -2008(%rbp)
	movq -1696(%rbp), %rcx
	movq %rcx, -2000(%rbp)
	movq -1688(%rbp), %rcx
	movq %rcx, -1992(%rbp)
	movq -2008(%rbp), %rcx
	movq %rcx, -1680(%rbp)
	movq -2000(%rbp), %rcx
	movq %rcx, -1672(%rbp)
	movq -1992(%rbp), %rcx
	movq %rcx, -1664(%rbp)
	movq -1680(%rbp), %rcx
	movq %rcx, -1864(%rbp)
	movq -1672(%rbp), %rcx
	movq %rcx, -1856(%rbp)
	movq -1664(%rbp), %rcx
	movq %rcx, -1848(%rbp)
	leaq -1864(%rbp), %rcx
	movq %rcx, -1840(%rbp)
	movq %r9, -1840(%rbp)
	movq $3, -1832(%rbp)
	imulq $3, %r9, %rcx
	movl $4294967295, %r8d
	andq %r9, %r8
	movq %r9, %r15
	shrq $32, %r15
	imulq $3, %r8, %r11
	movq %r11, -912(%rbp)
	movq -912(%rbp), %r11
	shrq $32, %r11
	movq %r11, -928(%rbp)
	imulq $3, %r15, %r11
	movq %r11, -920(%rbp)
	movq -928(%rbp), %r11
	addq -920(%rbp), %r11
	movq %r11, -944(%rbp)
	movl $4294967295, %r11d
	movq %r11, -936(%rbp)
	movq -944(%rbp), %r11
	andq -936(%rbp), %r11
	movq %r11, -960(%rbp)
	movq -944(%rbp), %r11
	shrq $32, %r11
	movq %r11, -952(%rbp)
	imulq $0, %r8, %r8
	movq %r8, -968(%rbp)
	movq -952(%rbp), %r11
	movq -960(%rbp), %r8
	addq -968(%rbp), %r8
	shrq $32, %r8
	imulq $0, %r15, %r15
	addq %r15, %r11
	addq %r11, %r8
	cmpq $0, %r9
	setl %r11b
	movzbq %r11b, %r11
	negq %r11
	movq %r11, %r15
	andq $3, %r15
	movq %r9, %r11
	andq $0, %r11
	subq %r15, %r8
	negq %r11
	addq %r8, %r11
	movq %rcx, %r8
	sarq $63, %r8
	cmpq %r8, %r11
	jnz .Lbb1714
	movq %rcx, -1840(%rbp)
	movq %r10, %r9
	addq %rcx, %r9
	movq %r10, %r8
	xorq %r9, %r8
	movq %rcx, %r11
	xorq %r9, %r11
	andq %r11, %r8
	cmpq $0, %r8
	jl .Lbb1712
	leaq -1864(%rbp), %rcx
	movq %rcx, -1840(%rbp)
	movq %rax, -1840(%rbp)
	movq $5, -1832(%rbp)
	imulq $5, %rax, %rcx
	movl $4294967295, %r8d
	movq %rax, %r15
	andq %r8, %r15
	movq %rax, %r11
	shrq $32, %r11
	imulq $5, %r15, %r8
	shrq $32, %r8
	imulq $5, %r11, %r10
	addq %r8, %r10
	movl $4294967295, %r8d
	andq %r10, %r8
	shrq $32, %r10
	imulq $0, %r15, %r15
	addq %r15, %r8
	shrq $32, %r8
	imulq $0, %r11, %r11
	addq %r11, %r10
	addq %r10, %r8
	cmpq $0, %rax
	setl %r10b
	movzbq %r10b, %r10
	negq %r10
	movq %r10, %r11
	andq $5, %r11
	movq %rax, %r10
	andq $0, %r10
	subq %r11, %r8
	negq %r10
	addq %r8, %r10
	movq %rcx, %r8
	sarq $63, %r8
	cmpq %r8, %r10
	jnz .Lbb1710
	movq %rcx, -1840(%rbp)
	movq %r9, %rax
	addq %rcx, %rax
	movq %r9, %r8
	xorq %rax, %r8
	movq %rcx, %r10
	xorq %rax, %r10
	andq %r10, %r8
	cmpq $0, %r8
	jl .Lbb1708
	movq %rax, -1840(%rbp)
	movq %rsi, %r9
	addq %rax, %rsi
	movq %r9, %rcx
	xorq %rsi, %rcx
	movq %rax, %r8
	xorq %rsi, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jl .Lbb1706
	movq $1, -1840(%rbp)
	movq $9223372036854775806, %rax
	cmpq %rax, %rdi
	jg .Lbb1704
	addq $1, %rdi
	jmp .Lbb1665
.Lbb1704:
	movq %rdi, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 1034
	movl $64, %r8d
	movl $1, %ecx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1706:
	movq %rax, %rcx
	movq %r9, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 1030
	movl $64, %r8d
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1708:
	movq %r9, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 851
	movl $64, %r8d
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1710:
	movq %rax, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 850
	movl $64, %r8d
	movl $5, %ecx
	movq %rdx, -1240(%rbp)
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1712:
	movq %r10, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 846
	movl $64, %r8d
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1714:
	movq %r9, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 845
	movl $64, %r8d
	movl $3, %ecx
	movq %rdx, -1240(%rbp)
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1716:
	movq %rax, %rdx
	movq %rbx, %rcx
	movq -1224(%rbp), %rdi
	.loc 1 823
	movl $64, %r8d
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1718:
	movq %r11, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 821
	movl $64, %r8d
	movl $3, %ecx
	movq %rdx, -1240(%rbp)
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1720:
	movq %r11, %rdx
	movq %rbx, %rcx
	movq -1224(%rbp), %rdi
	.loc 1 793
	movl $64, %r8d
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1722:
	movq -1208(%rbp), %rcx
	movq -1192(%rbp), %r9
	movq -1184(%rbp), %rbx
	movq -1232(%rbp), %r15
	movq -1176(%rbp), %r11
	movq -1216(%rbp), %rax
	movq -1200(%rbp), %r8
	movq -1224(%rbp), %rdi
	jmp .Lbb2243
.Lbb1723:
	cmpq $6, %r10
	jnz .Lbb1757
	movl $0, %esi
	movl $0, %eax
.p2align 4
.Lbb1725:
	movq %r12, -1840(%rbp)
	cmpq %r12, %rax
	jge .Lbb1756
	movq -2088(%rbp), %rcx
	movq (%rcx), %rdi
	cmpq %rdi, %rax
	setb %dil
	movzbq %dil, %rdi
	cmpl $0, %edi
	jnz .Lbb1739
	movq $0, -1840(%rbp)
	cmpq $0, %rax
	jl .Lbb1729
	movq %rax, %rdi
	jmp .Lbb1731
.Lbb1729:
	movq (%rcx), %r9
	movq $9223372036854775807, %rdi
	cmpq %rdi, %r9
	ja .Lbb1737
	movq %rax, -1840(%rbp)
	movq %r9, %rdi
	addq %rax, %rdi
	movq %r9, %r8
	xorq %rdi, %r8
	movq %rax, %r10
	xorq %rdi, %r10
	andq %r10, %r8
	cmpq $0, %r8
	jl .Lbb1735
.Lbb1731:
	movq (%rcx), %r8
	cmpq %r8, %rdi
	jae .Lbb1733
	movq 32(%rcx), %rcx
	movq (%rcx, %rdi, 8), %rdi
	jmp .Lbb1740
.Lbb1733:
	movq %r8, %rdx
	movq %rdi, %rax
	movq -1224(%rbp), %rdi
	.loc 1 572
	movq %rdx, -1240(%rbp)
	movq %rax, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1735:
	movq %rax, %rdx
	movq %r9, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 569
	movl $64, %r8d
	movq %rdx, %rcx
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1737:
	movq %r9, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 567
	movl $320, %edx
	movq %rdx, -1240(%rbp)
	callq myl_qbe_fail_cast
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1739:
	movq 32(%rcx), %rcx
	movq (%rcx, %rax, 8), %rdi
.Lbb1740:
	movq $0, -1840(%rbp)
	movq $1, -1840(%rbp)
	movq $2, -1840(%rbp)
	movq $3, -1840(%rbp)
	movq $4, -1840(%rbp)
	movq $5, -1840(%rbp)
	movq $6, -1840(%rbp)
	movq %rbx, -1840(%rbp)
	movq %rbx, %r9
	addq %rdi, %r9
	movq %r9, %rcx
	xorq %rdi, %rcx
	movq %rbx, %r8
	xorq %r9, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jl .Lbb1754
	movq $3, -1840(%rbp)
	imulq $3, %r9, %rdi
	movl $4294967295, %ecx
	movq %r9, %r11
	andq %rcx, %r11
	movq %r9, %r10
	shrq $32, %r10
	imulq $3, %r11, %rcx
	shrq $32, %rcx
	imulq $3, %r10, %r8
	addq %rcx, %r8
	movl $4294967295, %ecx
	andq %r8, %rcx
	shrq $32, %r8
	imulq $0, %r11, %r11
	addq %r11, %rcx
	shrq $32, %rcx
	imulq $0, %r10, %r10
	addq %r10, %r8
	addq %r8, %rcx
	cmpq $0, %r9
	setl %r8b
	movzbq %r8b, %r8
	negq %r8
	movq %r8, %r10
	andq $3, %r10
	movq %r9, %r8
	andq $0, %r8
	subq %r10, %rcx
	negq %r8
	addq %rcx, %r8
	movq %rdi, %rcx
	sarq $63, %rcx
	cmpq %rcx, %r8
	jnz .Lbb1752
	movq $7, -1840(%rbp)
	movq $9223372036854775800, %rcx
	cmpq %rcx, %rdi
	jg .Lbb1750
	movq %rdi, %rcx
	addq $7, %rcx
	movq %rcx, -1840(%rbp)
	movq %rsi, %rdi
	addq %rcx, %rsi
	movq %rdi, %r8
	xorq %rsi, %r8
	movq %rcx, %r9
	xorq %rsi, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jl .Lbb1748
	movq $1, -1840(%rbp)
	movq $9223372036854775806, %rcx
	cmpq %rcx, %rax
	jg .Lbb1746
	addq $1, %rax
	jmp .Lbb1725
.Lbb1746:
	movq %rax, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 1034
	movl $64, %r8d
	movl $1, %ecx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1748:
	movq %rdi, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 1030
	movl $64, %r8d
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1750:
	movq %rdi, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 868
	movl $64, %r8d
	movl $7, %ecx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1752:
	movq %r9, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 866
	movl $64, %r8d
	movl $3, %ecx
	movq %rdx, -1240(%rbp)
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1754:
	movq %rdi, %rdx
	movq %rbx, %rcx
	movq -1224(%rbp), %rdi
	.loc 1 861
	movl $64, %r8d
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1756:
	movq -1208(%rbp), %rcx
	movq -1192(%rbp), %r9
	movq -1184(%rbp), %rbx
	movq -1176(%rbp), %r11
	movq -1216(%rbp), %rax
	movq -1200(%rbp), %r8
	movq -1224(%rbp), %rdi
	jmp .Lbb2243
.Lbb1757:
	cmpq $7, %r10
	jnz .Lbb1785
	movq %r11, %rax
	movq $0, -976(%rbp)
	movl $0, %r15d
.p2align 4
.Lbb1759:
	movq %r12, -1840(%rbp)
	cmpq %r12, %r15
	jge .Lbb1784
	movq -2088(%rbp), %rcx
	movq (%rcx), %rdx
	cmpq %rdx, %r15
	setb %dl
	movzbq %dl, %rdx
	cmpl $0, %edx
	jnz .Lbb1772
	movq $0, -1840(%rbp)
	cmpq $0, %r15
	jl .Lbb1763
	movq %rcx, %rdx
	movq %r15, %rcx
	jmp .Lbb1765
.Lbb1763:
	movq (%rcx), %rsi
	movq $9223372036854775807, %rdx
	cmpq %rdx, %rsi
	ja .Lbb1771
	movq %r15, -1840(%rbp)
	movq %rcx, %rdx
	movq %rsi, %rcx
	addq %r15, %rcx
	movq %rsi, %r8
	xorq %rcx, %r8
	movq %r15, %r9
	xorq %rcx, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jl .Lbb1769
.Lbb1765:
	movq (%rdx), %rsi
	cmpq %rsi, %rcx
	jae .Lbb1767
	movq 32(%rdx), %rdx
	movq (%rdx, %rcx, 8), %rdx
	jmp .Lbb1773
.Lbb1767:
	movq %rsi, %rdx
	.loc 1 572
	movq %rdx, -1240(%rbp)
	movq %rcx, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1769:
	movq %r15, %rdx
	.loc 1 569
	movl $64, %r8d
	movq %rdx, %rcx
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1771:
	.loc 1 567
	movl $320, %edx
	movq %rdx, -1240(%rbp)
	callq myl_qbe_fail_cast
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1772:
	movq 32(%rcx), %rcx
	movq (%rcx, %r15, 8), %rdx
.Lbb1773:
	movq $0, -1840(%rbp)
	movq $1, -1840(%rbp)
	movq $2, -1840(%rbp)
	movq $3, -1840(%rbp)
	movq $4, -1840(%rbp)
	movq $5, -1840(%rbp)
	movq $6, -1840(%rbp)
	movq $7, -1840(%rbp)
	movq %rdx, -1840(%rbp)
	movq %rbx, -1832(%rbp)
	movq %rbx, %rsi
	addq %rdx, %rsi
	movq %rsi, %rcx
	xorq %rdx, %rcx
	movq %rbx, %r8
	xorq %rsi, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jl .Lbb1782
	movq %rsi, -1840(%rbp)
	.loc 1 880
	callq *%rax
	movq %rdx, -1240(%rbp)
	movq %rax, %rcx
	movq -976(%rbp), %rsi
	movq -1488(%rbp), %rax
	movq -1224(%rbp), %rdi
	movq %rcx, -1840(%rbp)
	movq %rsi, %r9
	addq %rcx, %rsi
	movq %r9, %rdx
	xorq %rsi, %rdx
	movq %rcx, %r8
	xorq %rsi, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jl .Lbb1780
	movq $1, -1840(%rbp)
	movq $9223372036854775806, %rcx
	cmpq %rcx, %r15
	jg .Lbb1778
	addq $1, %r15
	movq %rsi, -976(%rbp)
	jmp .Lbb1759
.Lbb1778:
	movq %r15, %rdx
	.loc 1 1034
	movl $64, %r8d
	movl $1, %ecx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1780:
	movq %r9, %rsi
	.loc 1 1030
	movl $64, %r8d
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1782:
	movq %rbx, %rcx
	.loc 1 879
	movl $64, %r8d
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1784:
	movq -1208(%rbp), %rcx
	movq -1192(%rbp), %r9
	movq -1184(%rbp), %rbx
	movq -1232(%rbp), %r15
	movq -1176(%rbp), %r11
	movq -1216(%rbp), %rax
	movq -1200(%rbp), %r8
	movq -976(%rbp), %rsi
	jmp .Lbb2243
.Lbb1785:
	cmpq $8, %r10
	jnz .Lbb1826
	movl $0, %esi
	movl $0, %eax
.p2align 4
.Lbb1787:
	movq %r12, -1840(%rbp)
	cmpq %r12, %rax
	jge .Lbb1825
	movq -2088(%rbp), %rcx
	movq (%rcx), %rdi
	cmpq %rdi, %rax
	setb %dil
	movzbq %dil, %rdi
	cmpl $0, %edi
	jnz .Lbb1801
	movq $0, -1840(%rbp)
	cmpq $0, %rax
	jl .Lbb1791
	movq %rax, %rdi
	jmp .Lbb1793
.Lbb1791:
	movq (%rcx), %r9
	movq $9223372036854775807, %rdi
	cmpq %rdi, %r9
	ja .Lbb1799
	movq %rax, -1840(%rbp)
	movq %r9, %rdi
	addq %rax, %rdi
	movq %r9, %r8
	xorq %rdi, %r8
	movq %rax, %r10
	xorq %rdi, %r10
	andq %r10, %r8
	cmpq $0, %r8
	jl .Lbb1797
.Lbb1793:
	movq (%rcx), %r8
	cmpq %r8, %rdi
	jae .Lbb1795
	movq 32(%rcx), %rcx
	movq (%rcx, %rdi, 8), %rdi
	jmp .Lbb1802
.Lbb1795:
	movq %r8, %rdx
	movq %rdi, %rax
	movq -1224(%rbp), %rdi
	.loc 1 572
	movq %rdx, -1240(%rbp)
	movq %rax, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1797:
	movq %rax, %rdx
	movq %r9, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 569
	movl $64, %r8d
	movq %rdx, %rcx
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1799:
	movq %r9, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 567
	movl $320, %edx
	movq %rdx, -1240(%rbp)
	callq myl_qbe_fail_cast
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1801:
	movq 32(%rcx), %rcx
	movq (%rcx, %rax, 8), %rdi
.Lbb1802:
	movq $0, -1840(%rbp)
	movq $1, -1840(%rbp)
	movq $2, -1840(%rbp)
	movq $3, -1840(%rbp)
	movq $4, -1840(%rbp)
	movq $5, -1840(%rbp)
	movq $6, -1840(%rbp)
	movq $7, -1840(%rbp)
	movq $8, -1840(%rbp)
	movq %rbx, -1840(%rbp)
	movq $4, -1840(%rbp)
	movq %rdi, %rcx
	andq $3, %rcx
	movq $0, -1840(%rbp)
	cmpq $0, %rcx
	jz .Lbb1807
	movq %rbx, -1840(%rbp)
	movq %rbx, %rcx
	addq %rdi, %rcx
	movq %rcx, %r8
	xorq %rdi, %r8
	movq %rbx, %r9
	xorq %rcx, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jl .Lbb1805
	movq $0, -1640(%rbp)
	movq $0, -1632(%rbp)
	movl $1, -1640(%rbp)
	movq %rcx, -1632(%rbp)
	leaq -1640(%rbp), %rcx
	jmp .Lbb1808
.Lbb1805:
	movq %rdi, %rdx
	movq %rbx, %rcx
	movq -1224(%rbp), %rdi
	.loc 1 902
	movl $64, %r8d
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1807:
	movq $0, -1656(%rbp)
	movq $0, -1648(%rbp)
	movl $0, -1656(%rbp)
	leaq -1656(%rbp), %rcx
.Lbb1808:
	movl (%rcx), %edi
	cmpq $0, %rdi
	jz .Lbb1817
	cmpq $1, %rdi
	jnz .Lbb2614
	movq 8(%rcx), %r9
	movq %r9, -2248(%rbp)
	movq $3, -1840(%rbp)
	imulq $3, %r9, %rdi
	movl $4294967295, %ecx
	movq %r9, %r11
	andq %rcx, %r11
	movq %r9, %r10
	shrq $32, %r10
	imulq $3, %r11, %rcx
	shrq $32, %rcx
	imulq $3, %r10, %r8
	addq %rcx, %r8
	movl $4294967295, %ecx
	andq %r8, %rcx
	shrq $32, %r8
	imulq $0, %r11, %r11
	addq %r11, %rcx
	shrq $32, %rcx
	imulq $0, %r10, %r10
	addq %r10, %r8
	addq %r8, %rcx
	cmpq $0, %r9
	setl %r8b
	movzbq %r8b, %r8
	negq %r8
	movq %r8, %r10
	andq $3, %r10
	movq %r9, %r8
	andq $0, %r8
	subq %r10, %rcx
	negq %r8
	addq %rcx, %r8
	movq %rdi, %rcx
	sarq $63, %rcx
	cmpq %rcx, %r8
	jnz .Lbb1815
	movq $1, -1840(%rbp)
	movq $9223372036854775806, %rcx
	cmpq %rcx, %rdi
	jg .Lbb1813
	movq %rdi, %rcx
	addq $1, %rcx
	jmp .Lbb1818
.Lbb1813:
	movq %rdi, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 910
	movl $64, %r8d
	movl $1, %ecx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1815:
	movq %r9, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 908
	movl $64, %r8d
	movl $3, %ecx
	movq %rdx, -1240(%rbp)
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1817:
	movl $19, %ecx
.Lbb1818:
	movq %rcx, -1840(%rbp)
	movq %rsi, %rdi
	addq %rcx, %rsi
	movq %rdi, %r8
	xorq %rsi, %r8
	movq %rcx, %r9
	xorq %rsi, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jl .Lbb1823
	movq $1, -1840(%rbp)
	movq $9223372036854775806, %rcx
	cmpq %rcx, %rax
	jg .Lbb1821
	addq $1, %rax
	jmp .Lbb1787
.Lbb1821:
	movq %rax, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 1034
	movl $64, %r8d
	movl $1, %ecx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1823:
	movq %rdi, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 1030
	movl $64, %r8d
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1825:
	movq -1208(%rbp), %rcx
	movq -1192(%rbp), %r9
	movq -1184(%rbp), %rbx
	movq -1176(%rbp), %r11
	movq -1216(%rbp), %rax
	movq -1200(%rbp), %r8
	movq -1224(%rbp), %rdi
	jmp .Lbb2243
.Lbb1826:
	cmpq $9, %r10
	jnz .Lbb1872
	movl $0, %esi
	movl $0, %r15d
.p2align 4
.Lbb1828:
	movq %rsi, -984(%rbp)
	movq %r12, -1840(%rbp)
	cmpq %r12, %r15
	jge .Lbb1871
	movq -2088(%rbp), %rax
	movq (%rax), %rcx
	cmpq %rcx, %r15
	setb %cl
	movzbq %cl, %rcx
	cmpl $0, %ecx
	jnz .Lbb1842
	movq $0, -1840(%rbp)
	cmpq $0, %r15
	jl .Lbb1832
	movq %rax, %rcx
	movq %r15, %rax
	jmp .Lbb1834
.Lbb1832:
	movq (%rax), %rdi
	movq $9223372036854775807, %rcx
	cmpq %rcx, %rdi
	ja .Lbb1840
	movq %r15, -1840(%rbp)
	movq %rax, %rcx
	movq %rdi, %rax
	addq %r15, %rax
	movq %rdi, %r8
	xorq %rax, %r8
	movq %r15, %r9
	xorq %rax, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jl .Lbb1838
.Lbb1834:
	movq (%rcx), %rdi
	cmpq %rdi, %rax
	jae .Lbb1836
	movq 32(%rcx), %rcx
	movq (%rcx, %rax, 8), %rdi
	jmp .Lbb1843
.Lbb1836:
	movq %rdi, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 572
	movq %rdx, -1240(%rbp)
	movq %rax, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1838:
	movq %r15, %rdx
	movq %rdi, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 569
	movl $64, %r8d
	movq %rdx, %rcx
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1840:
	movq %rdi, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 567
	movl $320, %edx
	movq %rdx, -1240(%rbp)
	callq myl_qbe_fail_cast
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1842:
	movq 32(%rax), %rax
	movq (%rax, %r15, 8), %rdi
.Lbb1843:
	movq $0, -1840(%rbp)
	movq $1, -1840(%rbp)
	movq $2, -1840(%rbp)
	movq $3, -1840(%rbp)
	movq $4, -1840(%rbp)
	movq $5, -1840(%rbp)
	movq $6, -1840(%rbp)
	movq $7, -1840(%rbp)
	movq $8, -1840(%rbp)
	movq $9, -1840(%rbp)
	movq %rbx, -1840(%rbp)
	movq %rbx, -1840(%rbp)
	movq $5, -1840(%rbp)
	movq %rdi, %rcx
	sarq $63, %rcx
	movq %rcx, %rax
	xorq %rdi, %rax
	subq %rcx, %rax
	movq $-3689348814741910323, %r8
	mulq %r8
	movq %rdx, %rax
	shrq $2, %rax
	xorq %rcx, %rax
	subq %rcx, %rax
	imulq $5, %rax, %rax
	negq %rax
	addq %rdi, %rax
	cmpq $0, %rax
	setnz %r8b
	movzbq %r8b, %r8
	andq %r8, %rcx
	negq %rcx
	andq $5, %rcx
	addq %rcx, %rax
	movq $0, -1840(%rbp)
	cmpq $0, %rax
	jz .Lbb1848
	movq %rbx, -1840(%rbp)
	movq %rbx, %rax
	addq %rdi, %rax
	movq %rax, %rcx
	xorq %rdi, %rcx
	movq %rbx, %r8
	xorq %rax, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jl .Lbb1846
	movq $0, -1608(%rbp)
	movq $0, -1600(%rbp)
	movl $0, -1608(%rbp)
	movq %rax, -1600(%rbp)
	leaq -1608(%rbp), %rax
	jmp .Lbb1849
.Lbb1846:
	movq %rdi, %rdx
	movq %rbx, %rcx
	movq -1224(%rbp), %rdi
	.loc 1 942
	movl $64, %r8d
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1848:
	movq $0, -1624(%rbp)
	movq $0, -1616(%rbp)
	movl $1, -1624(%rbp)
	movq $1, -1616(%rbp)
	.loc 1 938
	movl $7, %esi
	movq myl_f_e61a3d78c65133c7260c43e719d97c46e16bd50c64ee7800536cf14c6407a617_meta@gotpcrel(%rip), %rdi
	callq myl_qbe_error_trace_origin
	movq -984(%rbp), %rsi
	movl -996(%rbp), %r14d
	leaq -1624(%rbp), %rax
.Lbb1849:
	movq %rax, -992(%rbp)
	movl (%rax), %ecx
	cmpq $0, %rcx
	setz %cl
	movzbq %cl, %rcx
	cmpl $0, %ecx
	jnz .Lbb1851
	.loc 1 945
	movq $12884901907, %rsi
	movq myl_f_8e12cac141092888b455b1042ce0f135b93f62d14079f9ac5799b4808829b581_meta@gotpcrel(%rip), %rdi
	callq myl_qbe_error_trace_append
	movq -992(%rbp), %rax
	movq -984(%rbp), %rsi
	movl -996(%rbp), %r14d
	movq $0, -1592(%rbp)
	movq $0, -1584(%rbp)
	movl $1, -1592(%rbp)
	movq 8(%rax), %rax
	movq %rax, -1584(%rbp)
	leaq -1592(%rbp), %rax
	jmp .Lbb1854
.Lbb1851:
	movq $0, -1592(%rbp)
	movq 8(%rax), %rdi
	movq %rdi, -1592(%rbp)
	movq $3, -1840(%rbp)
	imulq $3, %rdi, %rax
	movl $4294967295, %ecx
	movq %rdi, %r10
	andq %rcx, %r10
	movq %rdi, %r9
	shrq $32, %r9
	imulq $3, %r10, %rcx
	shrq $32, %rcx
	imulq $3, %r9, %r8
	addq %rcx, %r8
	movl $4294967295, %ecx
	andq %r8, %rcx
	shrq $32, %r8
	imulq $0, %r10, %r10
	addq %r10, %rcx
	shrq $32, %rcx
	imulq $0, %r9, %r9
	addq %r9, %r8
	addq %r8, %rcx
	cmpq $0, %rdi
	setl %r8b
	movzbq %r8b, %r8
	negq %r8
	movq %r8, %r9
	andq $3, %r9
	movq %rdi, %r8
	andq $0, %r8
	subq %r9, %rcx
	negq %r8
	addq %rcx, %r8
	movq %rax, %rcx
	sarq $63, %rcx
	cmpq %rcx, %r8
	jnz .Lbb1869
	movq $1, -1840(%rbp)
	movq $9223372036854775806, %rcx
	cmpq %rcx, %rax
	jg .Lbb1867
	movq $0, -1576(%rbp)
	movq $0, -1568(%rbp)
	movl $0, -1576(%rbp)
	addq $1, %rax
	movq %rax, -1568(%rbp)
	leaq -1576(%rbp), %rax
.Lbb1854:
	movl (%rax), %ecx
	cmpq $0, %rcx
	setz %dil
	movzbq %dil, %rdi
	cmpl $0, %edi
	jnz .Lbb1859
	cmpq $1, %rcx
	jnz .Lbb2614
	movq 8(%rax), %rdi
	movq %rdi, -2248(%rbp)
	movq $7, -1840(%rbp)
	imulq $7, %rdi, %rax
	movl $4294967295, %ecx
	movq %rdi, %r10
	andq %rcx, %r10
	movq %rdi, %r9
	shrq $32, %r9
	imulq $7, %r10, %rcx
	shrq $32, %rcx
	imulq $7, %r9, %r8
	addq %rcx, %r8
	movl $4294967295, %ecx
	andq %r8, %rcx
	shrq $32, %r8
	imulq $0, %r10, %r10
	addq %r10, %rcx
	shrq $32, %rcx
	imulq $0, %r9, %r9
	addq %r9, %r8
	addq %r8, %rcx
	cmpq $0, %rdi
	setl %r8b
	movzbq %r8b, %r8
	negq %r8
	movq %r8, %r9
	andq $7, %r9
	movq %rdi, %r8
	andq $0, %r8
	subq %r9, %rcx
	negq %r8
	addq %rcx, %r8
	movq %rax, %rcx
	sarq $63, %rcx
	cmpq %rcx, %r8
	jz .Lbb1860
	movq %rdi, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 962
	movl $64, %r8d
	movl $7, %ecx
	movq %rdx, -1240(%rbp)
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1859:
	movq 8(%rax), %rax
	movq %rax, -2248(%rbp)
.Lbb1860:
	movq %rax, -1840(%rbp)
	movq %rsi, %rdi
	addq %rax, %rsi
	movq %rdi, %rcx
	xorq %rsi, %rcx
	movq %rax, %r8
	xorq %rsi, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jl .Lbb1865
	movq $1, -1840(%rbp)
	movq $9223372036854775806, %rax
	cmpq %rax, %r15
	jg .Lbb1863
	addq $1, %r15
	jmp .Lbb1828
.Lbb1863:
	movq %r15, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 1034
	movl $64, %r8d
	movl $1, %ecx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1865:
	movq %rax, %rcx
	movq %rdi, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 1030
	movl $64, %r8d
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1867:
	movq %rax, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 953
	movl $64, %r8d
	movl $1, %ecx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1869:
	movq %rdi, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 951
	movl $64, %r8d
	movl $3, %ecx
	movq %rdx, -1240(%rbp)
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1871:
	movq -1208(%rbp), %rcx
	movq -1192(%rbp), %r9
	movq -1184(%rbp), %rbx
	movq -1232(%rbp), %r15
	movq -1176(%rbp), %r11
	movq -1216(%rbp), %rax
	movq -1200(%rbp), %r8
	movq -1224(%rbp), %rdi
	jmp .Lbb2243
.Lbb1872:
	movq %r10, %rdx
	cmpq $10, %rdx
	jnz .Lbb1938
	movl %r14d, -1000(%rbp)
	movl %r13d, -1004(%rbp)
	movq $0, -1024(%rbp)
	movl $0, %r10d
.p2align 4
.Lbb1875:
	movq %r12, -1840(%rbp)
	cmpq %r12, %r10
	jge .Lbb1937
	movq -2088(%rbp), %rdx
	movq (%rdx), %rsi
	cmpq %rsi, %r10
	setb %sil
	movzbq %sil, %rsi
	cmpl $0, %esi
	jnz .Lbb1889
	movq $0, -1840(%rbp)
	cmpq $0, %r10
	jl .Lbb1879
	movq %r10, %r13
	jmp .Lbb1881
.Lbb1879:
	movq (%rdx), %rsi
	movq $9223372036854775807, %r11
	cmpq %r11, %rsi
	ja .Lbb1888
	movq %r10, -1840(%rbp)
	movq %rsi, %r13
	addq %r10, %r13
	movq %rsi, %r11
	xorq %r13, %r11
	movq %r10, %r14
	xorq %r13, %r14
	andq %r14, %r11
	cmpq $0, %r11
	jl .Lbb1886
.Lbb1881:
	movq (%rdx), %rsi
	cmpq %rsi, %r13
	jae .Lbb1884
	movq 32(%rdx), %rdx
	movq (%rdx, %r13, 8), %rdx
	movq %r10, %r13
	movq %rdx, %r10
	jmp .Lbb1890
.Lbb1884:
	movq %rsi, %rdx
	.loc 1 572
	movq %rdx, -1240(%rbp)
	movq %r13, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1886:
	movq %r10, %rdx
	.loc 1 569
	movl $64, %r8d
	movq %rdx, %rcx
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1888:
	.loc 1 567
	movl $320, %edx
	movq %rdx, -1240(%rbp)
	callq myl_qbe_fail_cast
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1889:
	movq 32(%rdx), %rdx
	movq %r10, %r13
	movq (%rdx, %r10, 8), %r10
.Lbb1890:
	movq $0, -1840(%rbp)
	movq $1, -1840(%rbp)
	movq $2, -1840(%rbp)
	movq $3, -1840(%rbp)
	movq $4, -1840(%rbp)
	movq $5, -1840(%rbp)
	movq $6, -1840(%rbp)
	movq $7, -1840(%rbp)
	movq $8, -1840(%rbp)
	movq $9, -1840(%rbp)
	movq $10, -1840(%rbp)
	movq -2072(%rbp), %rsi
	movq %r10, -1840(%rbp)
	movq %rbx, -1832(%rbp)
	movq %rax, %r14
	movq %rbx, %rax
	addq %r10, %rax
	movq %rax, %rdx
	xorq %r10, %rdx
	movq %rbx, %r11
	xorq %rax, %r11
	andq %r11, %rdx
	movq -1176(%rbp), %r11
	cmpq $0, %rdx
	movq -1264(%rbp), %rdx
	jl .Lbb1935
	movq -1424(%rbp), %r10
	movq %rax, -1840(%rbp)
	movq %r12, -1832(%rbp)
	cmpq %rdx, %r11
	movq %r9, %r11
	movq -1496(%rbp), %r9
	jnz .Lbb1933
	movq %r11, -1832(%rbp)
	movq $9223372036854775804, %rdx
	cmpq %rdx, %r11
	jg .Lbb1931
	movq %rcx, -1832(%rbp)
	cmpq $0, %rcx
	jz .Lbb1929
	movq $-9223372036854775808, %rdx
	cmpq %rdx, %rax
	setz %dl
	movzbq %dl, %rdx
	andq %r10, %rdx
	negq %rdx
	andq %r9, %rdx
	xorq %rdx, %rcx
	cqto
	movq %rdx, -1240(%rbp)
	idivq %rcx
	movq %rdx, %rax
	cmpq $0, %rax
	setnz %dl
	movzbq %dl, %rdx
	movq %rcx, %r9
	xorq %rax, %r9
	cmpq $0, %r9
	setl %r9b
	movzbq %r9b, %r9
	andq %r9, %rdx
	negq %rdx
	andq %rdx, %rcx
	addq %rcx, %rax
	movq %rax, -1840(%rbp)
	movq %r8, -1832(%rbp)
	movq %r14, -1832(%rbp)
	movq %r14, %rdx
	addq %rax, %rdx
	movq %rax, %rcx
	xorq %rdx, %rcx
	movq %r14, %r8
	xorq %rdx, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jl .Lbb1927
	movq %rdx, -1840(%rbp)
	.loc 1 984
	movq %rdx, -1240(%rbp)
	callq myl_f_2419329067823cab5b4e5ac5dd18a6abf1f57f45e753f5fc934292f3085a3717
	movq %r13, %r10
	movq %rax, %r11
	movq -1208(%rbp), %rcx
	movl -1000(%rbp), %r14d
	movl -1004(%rbp), %r13d
	movq -1024(%rbp), %rsi
	movq -1216(%rbp), %rax
	movq -1224(%rbp), %rdi
	movq %r11, -1016(%rbp)
	movl %r13d, -1008(%rbp)
	cmpl $0, %r14d
	jz .Lbb1918
	testl $28, %r13d
	jnz .Lbb1908
	movq -2288(%rbp), %r9
	cmpq $0, %r9
	jz .Lbb1907
	movq -16(%r9), %r8
	movl %r13d, %r14d
	movq $4611686018427387906, %r13
	andq %r13, %r8
	cmpq $0, %r8
	jnz .Lbb1905
	movq -32(%r9), %r8
	subq $1, %r8
	jnz .Lbb1904
	movq %r10, %r13
	movq -24(%r9), %r10
	cmpq $0, %r10
	jnz .Lbb1903
	.loc 1 984
	leaq -2288(%rbp), %rsi
	movq %r15, %rdi
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %r13, %r10
	movq -1208(%rbp), %rcx
	movl -1008(%rbp), %r13d
	movq -1024(%rbp), %rsi
	movq -1016(%rbp), %r11
	movq -1216(%rbp), %rax
	movq -1224(%rbp), %rdi
	jmp .Lbb1907
.Lbb1903:
	movq %r13, %r10
.Lbb1904:
	movl %r14d, %r13d
	movq %r8, -32(%r9)
	jmp .Lbb1906
.Lbb1905:
	movl %r14d, %r13d
.Lbb1906:
	movq $0, -2288(%rbp)
.Lbb1907:
	movl $0, %r14d
	jmp .Lbb1918
.Lbb1908:
	movq -2288(%rbp), %r9
	cmpq $0, %r9
	jz .Lbb1917
	movq -16(%r9), %r8
	movl %r13d, %r14d
	movq $4611686018427387906, %r13
	andq %r13, %r8
	cmpq $0, %r8
	jnz .Lbb1915
	movq -24(%r9), %r8
	subq $1, %r8
	jnz .Lbb1914
	movq %r10, %r13
	movq -32(%r9), %r10
	cmpq $0, %r10
	jnz .Lbb1913
	.loc 1 984
	leaq -2288(%rbp), %rsi
	movq %r15, %rdi
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movq %r13, %r10
	movq -1208(%rbp), %rcx
	movl -1008(%rbp), %r13d
	movq -1024(%rbp), %rsi
	movq -1016(%rbp), %r11
	movq -1216(%rbp), %rax
	movq -1224(%rbp), %rdi
	jmp .Lbb1917
.Lbb1913:
	movq %r13, %r10
.Lbb1914:
	movl %r14d, %r13d
	movq %r8, -24(%r9)
	jmp .Lbb1916
.Lbb1915:
	movl %r14d, %r13d
.Lbb1916:
	movq $0, -2288(%rbp)
.Lbb1917:
	movl $0, %r14d
.Lbb1918:
	movq %r11, -1840(%rbp)
	movq %rsi, %r9
	addq %r11, %rsi
	movq %r9, %r8
	xorq %rsi, %r8
	movq %r8, -1040(%rbp)
	movq %r11, %r8
	xorq %rsi, %r8
	movq %r8, -1032(%rbp)
	movq -1040(%rbp), %r8
	andq -1032(%rbp), %r8
	movq %r8, -1048(%rbp)
	movq -1200(%rbp), %r8
	cmpq $0, -1048(%rbp)
	jl .Lbb1925
	movq -1192(%rbp), %r9
	movq $1, -1840(%rbp)
	movq $9223372036854775806, %r11
	cmpq %r11, %r10
	movq -1176(%rbp), %r11
	jg .Lbb1923
	addq $1, %r10
	movl %r14d, -1000(%rbp)
	movl %r13d, -1004(%rbp)
	movq %rsi, -1024(%rbp)
	jmp .Lbb1875
.Lbb1923:
	movq %r10, %rdx
	.loc 1 1034
	movl $64, %r8d
	movl $1, %ecx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1925:
	movq %r9, %rsi
	movq %r11, %rcx
	.loc 1 1030
	movl $64, %r8d
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1927:
	movq %rax, %rdx
	movq -1216(%rbp), %rcx
	.loc 1 983
	movl $64, %r8d
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1929:
	movq %rax, %rdx
	.loc 1 979
	movl $0, %ecx
	movq %rdx, -1240(%rbp)
	movl $6, %esi
	callq myl_qbe_fail_division
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1931:
	movq -1192(%rbp), %rdx
	.loc 1 978
	movl $64, %r8d
	movl $3, %ecx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1933:
	movq %r12, %rdx
	.loc 1 976
	movl $64, %r8d
	movl $3, %ecx
	movq %rdx, -1240(%rbp)
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1935:
	movq %r10, %rdx
	movq %rbx, %rcx
	.loc 1 973
	movl $64, %r8d
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1937:
	movq -1184(%rbp), %rbx
	movq -1176(%rbp), %r11
	movl -1000(%rbp), %r14d
	movl -1004(%rbp), %r13d
	movq -1024(%rbp), %rsi
	jmp .Lbb2243
.Lbb1938:
	movq %rsi, %rcx
	movq %rdx, %rax
	cmpq $11, %rax
	jz .Lbb2175
	movl $0, %esi
	movl $0, %eax
.p2align 4
.Lbb1941:
	movq %r12, -1840(%rbp)
	cmpq %r12, %rax
	jge .Lbb2174
	movq %rcx, %rdi
	movq -2088(%rbp), %rcx
	movq (%rcx), %rdx
	cmpq %rdx, %rax
	setb %dl
	movzbq %dl, %rdx
	cmpl $0, %edx
	jnz .Lbb1955
	movq $0, -1840(%rbp)
	cmpq $0, %rax
	jl .Lbb1945
	movq %rax, %r9
	jmp .Lbb1947
.Lbb1945:
	movq (%rcx), %r10
	movq $9223372036854775807, %rdx
	cmpq %rdx, %r10
	ja .Lbb1953
	movq %rax, -1840(%rbp)
	movq %r10, %r9
	addq %rax, %r9
	movq %r10, %rdx
	xorq %r9, %rdx
	movq %rax, %r8
	xorq %r9, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jl .Lbb1951
.Lbb1947:
	movq (%rcx), %rdx
	cmpq %rdx, %r9
	jae .Lbb1949
	movq 32(%rcx), %rcx
	movq (%rcx, %r9, 8), %rcx
	jmp .Lbb1956
.Lbb1949:
	movq -1224(%rbp), %rdi
	.loc 1 572
	movq %rdx, -1240(%rbp)
	movq %r9, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1951:
	movq %rax, %rcx
	movq %r10, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 569
	movl $64, %r8d
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1953:
	movq %r10, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 567
	movl $320, %edx
	movq %rdx, -1240(%rbp)
	callq myl_qbe_fail_cast
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1955:
	movq 32(%rcx), %rcx
	movq (%rcx, %rax, 8), %rcx
.Lbb1956:
	movq $0, -1840(%rbp)
	movq $1, -1840(%rbp)
	movq $2, -1840(%rbp)
	movq $3, -1840(%rbp)
	cmpl $0, %edi
	jz .Lbb1999
	movq -2056(%rbp), %rdx
	movq $0, -1840(%rbp)
	cmpq $0, %rax
	jl .Lbb1959
	movq %rax, %rdi
	jmp .Lbb1961
.Lbb1959:
	movq (%rdx), %r9
	movq $9223372036854775807, %rdi
	cmpq %rdi, %r9
	ja .Lbb1997
	movq %rax, -1840(%rbp)
	movq %r9, %rdi
	addq %rax, %rdi
	movq %r9, %r8
	xorq %rdi, %r8
	movq %rax, %r10
	xorq %rdi, %r10
	andq %r10, %r8
	cmpq $0, %r8
	jl .Lbb1995
.Lbb1961:
	movq (%rdx), %r8
	cmpq %r8, %rdi
	jae .Lbb1993
	movq 32(%rdx), %rdx
	movzbq (%rdx, %rdi, 1), %rdx
	movq %rdx, -1160(%rbp)
	movq %rbx, %rdi
	addq %rcx, %rdi
	movl $4294967295, %edx
	andq %rdi, %rdx
	movq %rdi, %r10
	shrq $32, %r10
	movq %r10, %r15
	imulq $0, %rdx, %r10
	imulq $0, %r15, %r11
	cmpq $0, %rdi
	setl %r8b
	movzbq %r8b, %r8
	movq %r8, %r9
	negq %r9
	movq %rdi, %r8
	andq $0, %r8
	movq %r8, -1152(%rbp)
	movq %rdi, %r8
	xorq %rcx, %r8
	movq %r8, -1144(%rbp)
	movq %rbx, %r8
	xorq %rdi, %r8
	movq %r8, -1136(%rbp)
	movq -1144(%rbp), %r8
	andq -1136(%rbp), %r8
	movq %r8, -1168(%rbp)
	movq -1152(%rbp), %r8
	cmpl $0, -1160(%rbp)
	jnz .Lbb1974
	movq %rbx, -1840(%rbp)
	cmpq $0, -1168(%rbp)
	jl .Lbb1972
	movq %r10, %rcx
	movq $5, -1840(%rbp)
	movq %rdx, %r10
	imulq $5, %rdi, %rdx
	imulq $5, %r10, %r10
	shrq $32, %r10
	imulq $5, %r15, %r15
	addq %r10, %r15
	movq %r9, %r10
	movl $4294967295, %r9d
	andq %r15, %r9
	shrq $32, %r15
	addq %rcx, %r9
	movq -1480(%rbp), %rcx
	shrq $32, %r9
	addq %r15, %r11
	addq %r11, %r9
	andq $5, %r10
	subq %r10, %r9
	subq %r8, %r9
	movq %rdx, %r8
	sarq $63, %r8
	cmpq %r8, %r9
	jnz .Lbb1970
	movq $7, -1840(%rbp)
	movq $9223372036854775800, %rdi
	cmpq %rdi, %rdx
	jg .Lbb1968
	addq $7, %rdx
	jmp .Lbb1980
.Lbb1968:
	movq -1224(%rbp), %rdi
	.loc 1 731
	movl $64, %r8d
	movl $7, %ecx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1970:
	movq %rdi, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 729
	movl $64, %r8d
	movl $5, %ecx
	movq %rdx, -1240(%rbp)
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1972:
	movq %rcx, %rdx
	movq %rbx, %rcx
	movq -1224(%rbp), %rdi
	.loc 1 727
	movl $64, %r8d
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1974:
	xchgq %r10, %r15
	movq %rbx, -1840(%rbp)
	cmpq $0, -1168(%rbp)
	jl .Lbb1991
	movq -1480(%rbp), %rcx
	movq $3, -1840(%rbp)
	imulq $3, %rdx, %rdx
	shrq $32, %rdx
	imulq $3, %r10, %r10
	addq %rdx, %r10
	movl $4294967295, %edx
	andq %r10, %rdx
	shrq $32, %r10
	addq %r15, %rdx
	shrq $32, %rdx
	addq %r11, %r10
	addq %r10, %rdx
	andq $3, %r9
	subq %r9, %rdx
	movq %rdx, %r9
	subq %r8, %r9
	imulq $3, %rdi, %rdx
	movq %rdx, %r8
	sarq $63, %r8
	cmpq %r8, %r9
	jnz .Lbb1989
	movq $1, -1840(%rbp)
	movq $9223372036854775806, %rdi
	cmpq %rdi, %rdx
	jg .Lbb1987
	addq $1, %rdx
.Lbb1980:
	movq %rdx, -1840(%rbp)
	movq %rsi, %rdi
	addq %rdx, %rsi
	movq %rdi, %r8
	xorq %rsi, %r8
	movq %rdx, %r9
	xorq %rsi, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jl .Lbb1985
	movq $1, -1840(%rbp)
	movq $9223372036854775806, %rdx
	cmpq %rdx, %rax
	jg .Lbb1983
	addq $1, %rax
	jmp .Lbb1941
.Lbb1983:
	movq %rax, %rcx
	movq -1224(%rbp), %rdi
	.loc 1 1034
	movl $64, %r8d
	movq %rcx, %rax
	movl $1, %ecx
	movq %rax, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1985:
	movq %rdx, %rcx
	movq %rdi, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 1030
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1987:
	movq -1224(%rbp), %rdi
	.loc 1 722
	movl $64, %r8d
	movl $1, %ecx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1989:
	movq %rdi, %rdx
	movq -1224(%rbp), %rdi
	.loc 1 720
	movl $64, %r8d
	movl $3, %ecx
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1991:
	movq %rcx, %rdx
	movq %rbx, %rcx
	movq -1224(%rbp), %rdi
	.loc 1 718
	movl $64, %r8d
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1993:
	movq %r8, %rdx
	movq %rdi, %rcx
	movq -1224(%rbp), %rdi
	.loc 1 714
	movq %rcx, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1995:
	movq %rax, %rcx
	movq %r9, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 711
	movl $64, %r8d
	movq %rsi, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1997:
	movq %r9, %rsi
	movq -1224(%rbp), %rdi
	.loc 1 709
	movl $320, %edx
	callq myl_qbe_fail_cast
	movq %rdx, -1240(%rbp)
	ud2
.Lbb1999:
	movl -1440(%rbp), %r12d
	movl -1516(%rbp), %r14d
	movl -1540(%rbp), %eax
	movl -1520(%rbp), %r13d
	movq -1232(%rbp), %r15
	movq -1224(%rbp), %rdi
	movq $4, -1840(%rbp)
	movq $5, -1840(%rbp)
	movq $6, -1840(%rbp)
	movq $7, -1840(%rbp)
	movq $8, -1840(%rbp)
	movq $9, -1840(%rbp)
	movq $10, -1840(%rbp)
	movq $11, -1840(%rbp)
	movl %eax, %ebx
	movl -2184(%rbp), %eax
	movl -2152(%rbp), %ecx
	orl %ecx, %eax
	jz .Lbb2002
	leaq -2208(%rbp), %rax
	movq %rax, -2144(%rbp)
	leaq -2176(%rbp), %rax
	movq %rax, -2136(%rbp)
	.loc 1 1027
	movl $2, %edx
	leaq -2144(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_qbe_rc_scopes_close
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl -1540(%rbp), %ebx
.Lbb2002:
	.loc 1 1027
	callq myl_qbe_exit_skip
	movq %rdx, -1240(%rbp)
	movq %r15, %rdi
	movl %eax, %ecx
	movl %ebx, %eax
	movl %eax, %ebx
	movl -1548(%rbp), %eax
	movl -1544(%rbp), %r15d
	cmpl $0, %ecx
	jnz .Lbb2173
	movq -2016(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb2005
	xchgl %r12d, %ebx
	xchgl %eax, %r12d
	jmp .Lbb2014
.Lbb2005:
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2012
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jz .Lbb2008
	xchgl %r12d, %ebx
	xchgl %eax, %r12d
	jmp .Lbb2011
.Lbb2008:
	movq -24(%rdx), %rsi
	cmpq $0, %rsi
	jnz .Lbb2010
	.loc 1 1027
	leaq -2016(%rbp), %rsi
	movq %rdi, %r15
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r15, %rdi
	movl %ebx, %eax
	movl %r12d, %ebx
	movl -1548(%rbp), %r12d
	movl -1544(%rbp), %r15d
	jmp .Lbb2014
.Lbb2010:
	xchgl %r12d, %ebx
	xchgl %eax, %r12d
.Lbb2011:
	movq %rcx, -32(%rdx)
	jmp .Lbb2013
.Lbb2012:
	xchgl %r12d, %ebx
	xchgl %eax, %r12d
.Lbb2013:
	movq $0, -2016(%rbp)
.Lbb2014:
	movl -2296(%rbp), %ecx
	cmpl $0, %ecx
	jnz .Lbb2016
	movl %r13d, %ebx
	movl %r12d, %r13d
	jmp .Lbb2037
.Lbb2016:
	movl $0, -2296(%rbp)
	testl $28, %ebx
	jnz .Lbb2026
	movq -2024(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2025
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2024
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2023
	movl %eax, %ebx
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2022
	.loc 1 1027
	leaq -2024(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %ebx, %eax
	movl -1548(%rbp), %r12d
	jmp .Lbb2025
.Lbb2022:
	movl %ebx, %eax
.Lbb2023:
	movq %rcx, -32(%rdx)
.Lbb2024:
	movq $0, -2024(%rbp)
.Lbb2025:
	movl %r13d, %ebx
	movl %r12d, %r13d
	jmp .Lbb2037
.Lbb2026:
	movq -2024(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb2028
	movl %r13d, %ebx
	movl %r12d, %r13d
	jmp .Lbb2037
.Lbb2028:
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2035
	movq -24(%rdx), %rcx
	subq $1, %rcx
	jz .Lbb2031
	movl %r13d, %ebx
	jmp .Lbb2034
.Lbb2031:
	movl %eax, %ebx
	movq -32(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2033
	.loc 1 1027
	leaq -2024(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %ebx, %eax
	movl %r13d, %ebx
	movl -1548(%rbp), %r13d
	jmp .Lbb2037
.Lbb2033:
	movl %ebx, %eax
	movl %r13d, %ebx
.Lbb2034:
	movl %r12d, %r13d
	movq %rcx, -24(%rdx)
	jmp .Lbb2036
.Lbb2035:
	movl %r13d, %ebx
	movl %r12d, %r13d
.Lbb2036:
	movq $0, -2024(%rbp)
.Lbb2037:
	movq -2032(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb2039
	movl %r13d, %r12d
	jmp .Lbb2047
.Lbb2039:
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2045
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2044
	movl %eax, %r12d
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2043
	.loc 1 1027
	leaq -2032(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r13, %rdi
	movl %r12d, %eax
	movl -1548(%rbp), %r12d
	jmp .Lbb2047
.Lbb2043:
	movl %r12d, %eax
.Lbb2044:
	movl %r13d, %r12d
	movq %rcx, -32(%rdx)
	jmp .Lbb2046
.Lbb2045:
	movl %r13d, %r12d
.Lbb2046:
	movq $0, -2032(%rbp)
.Lbb2047:
	movl -2304(%rbp), %ecx
	cmpl $0, %ecx
	jz .Lbb2065
	movl $0, -2304(%rbp)
	testl $28, %r14d
	jnz .Lbb2057
	movq -2040(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2065
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2056
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2055
	movl %eax, %r13d
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2054
	.loc 1 1027
	leaq -2040(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r14, %rdi
	movl %r13d, %eax
	jmp .Lbb2065
.Lbb2054:
	movl %r13d, %eax
.Lbb2055:
	movq %rcx, -32(%rdx)
.Lbb2056:
	movq $0, -2040(%rbp)
	jmp .Lbb2065
.Lbb2057:
	movq -2040(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2065
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2064
	movq -24(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2063
	movl %eax, %r13d
	movq -32(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2062
	.loc 1 1027
	leaq -2040(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r14, %rdi
	movl %r13d, %eax
	jmp .Lbb2065
.Lbb2062:
	movl %r13d, %eax
.Lbb2063:
	movq %rcx, -24(%rdx)
.Lbb2064:
	movq $0, -2040(%rbp)
.Lbb2065:
	movq -2048(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2073
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2072
	movq -24(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2071
	movl %eax, %r13d
	movq -32(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2070
	.loc 1 1027
	leaq -2048(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r14, %rdi
	movl %r13d, %eax
	jmp .Lbb2073
.Lbb2070:
	movl %r13d, %eax
.Lbb2071:
	movq %rcx, -24(%rdx)
.Lbb2072:
	movq $0, -2048(%rbp)
.Lbb2073:
	movq -2056(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2081
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2080
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2079
	movl %eax, %r13d
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2078
	.loc 1 1027
	leaq -2056(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r14, %rdi
	movl %r13d, %eax
	jmp .Lbb2081
.Lbb2078:
	movl %r13d, %eax
.Lbb2079:
	movq %rcx, -32(%rdx)
.Lbb2080:
	movq $0, -2056(%rbp)
.Lbb2081:
	movl -2312(%rbp), %ecx
	cmpl $0, %ecx
	jz .Lbb2090
	movl $0, -2312(%rbp)
	movq -2064(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2090
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2089
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2088
	movl %eax, %r13d
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2087
	.loc 1 1027
	leaq -2064(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r14, %rdi
	movl %r13d, %eax
	jmp .Lbb2090
.Lbb2087:
	movl %r13d, %eax
.Lbb2088:
	movq %rcx, -32(%rdx)
.Lbb2089:
	movq $0, -2064(%rbp)
.Lbb2090:
	movq -2072(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2098
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2097
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2096
	movl %eax, %r13d
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2095
	.loc 1 1027
	leaq -2072(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r14, %rdi
	movl %r13d, %eax
	jmp .Lbb2098
.Lbb2095:
	movl %r13d, %eax
.Lbb2096:
	movq %rcx, -32(%rdx)
.Lbb2097:
	movq $0, -2072(%rbp)
.Lbb2098:
	movl -2320(%rbp), %ecx
	cmpl $0, %ecx
	jz .Lbb2116
	movl $0, -2320(%rbp)
	testl $28, %r12d
	jnz .Lbb2108
	movq -2080(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2116
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2107
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2106
	movl %eax, %r12d
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2105
	.loc 1 1027
	leaq -2080(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r13, %rdi
	movl %r12d, %eax
	jmp .Lbb2116
.Lbb2105:
	movl %r12d, %eax
.Lbb2106:
	movq %rcx, -32(%rdx)
.Lbb2107:
	movq $0, -2080(%rbp)
	jmp .Lbb2116
.Lbb2108:
	movq -2080(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2116
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2115
	movq -24(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2114
	movl %eax, %r12d
	movq -32(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2113
	.loc 1 1027
	leaq -2080(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r13, %rdi
	movl %r12d, %eax
	jmp .Lbb2116
.Lbb2113:
	movl %r12d, %eax
.Lbb2114:
	movq %rcx, -24(%rdx)
.Lbb2115:
	movq $0, -2080(%rbp)
.Lbb2116:
	movq -2088(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2124
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2123
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2122
	movl %eax, %r12d
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2121
	.loc 1 1027
	leaq -2088(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r13, %rdi
	movl %r12d, %eax
	jmp .Lbb2124
.Lbb2121:
	movl %r12d, %eax
.Lbb2122:
	movq %rcx, -32(%rdx)
.Lbb2123:
	movq $0, -2088(%rbp)
.Lbb2124:
	movl -2328(%rbp), %ecx
	cmpl $0, %ecx
	jz .Lbb2142
	movl $0, -2328(%rbp)
	testl $28, %r15d
	jnz .Lbb2134
	movq -2096(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2142
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2133
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2132
	movl %eax, %r12d
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2131
	.loc 1 1027
	leaq -2096(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r13, %rdi
	movl %r12d, %eax
	jmp .Lbb2142
.Lbb2131:
	movl %r12d, %eax
.Lbb2132:
	movq %rcx, -32(%rdx)
.Lbb2133:
	movq $0, -2096(%rbp)
	jmp .Lbb2142
.Lbb2134:
	movq -2096(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2142
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2141
	movq -24(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2140
	movl %eax, %r12d
	movq -32(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2139
	.loc 1 1027
	leaq -2096(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r13, %rdi
	movl %r12d, %eax
	jmp .Lbb2142
.Lbb2139:
	movl %r12d, %eax
.Lbb2140:
	movq %rcx, -24(%rdx)
.Lbb2141:
	movq $0, -2096(%rbp)
.Lbb2142:
	cmpl $0, %eax
	jz .Lbb2158
	testl $28, %ebx
	jnz .Lbb2151
	movq -2104(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2158
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2150
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2149
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2149
	.loc 1 1027
	leaq -2104(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	jmp .Lbb2158
.Lbb2149:
	movq %rax, -32(%rcx)
.Lbb2150:
	movq $0, -2104(%rbp)
	jmp .Lbb2158
.Lbb2151:
	movq -2104(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2158
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2157
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2156
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2156
	.loc 1 1027
	leaq -2104(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	jmp .Lbb2158
.Lbb2156:
	movq %rax, -24(%rcx)
.Lbb2157:
	movq $0, -2104(%rbp)
.Lbb2158:
	movq -2112(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2165
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2164
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2163
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2163
	.loc 1 1027
	leaq -2112(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	jmp .Lbb2165
.Lbb2163:
	movq %rax, -32(%rcx)
.Lbb2164:
	movq $0, -2112(%rbp)
.Lbb2165:
	movl -2336(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2173
	movl $0, -2336(%rbp)
	movq -2120(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2173
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2172
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2171
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2171
	.loc 1 1027
	leaq -2120(%rbp), %rsi
	movq %rdi, %r15
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %rdx, -1240(%rbp)
	jmp .Lbb2173
.Lbb2171:
	movq %rax, -32(%rcx)
.Lbb2172:
	movq $0, -2120(%rbp)
.Lbb2173:
	movl $2, %eax
	jmp .Lbb2846
.Lbb2174:
	movq -1208(%rbp), %rcx
	movq -1192(%rbp), %r9
	movq -1184(%rbp), %rbx
	movq -1232(%rbp), %r15
	movq -1176(%rbp), %r11
	movq -1216(%rbp), %rax
	movq -1200(%rbp), %r8
	movq -1224(%rbp), %rdi
	jmp .Lbb2243
.Lbb2175:
	movq %r15, %rbx
	movl %r14d, -1436(%rbp)
	movq $0, -1064(%rbp)
	movl $0, %r15d
.p2align 4
.Lbb2176:
	movq %r12, -1840(%rbp)
	cmpq %r12, %r15
	jge .Lbb2239
	movq -2088(%rbp), %rax
	movq (%rax), %rcx
	cmpq %rcx, %r15
	setb %cl
	movzbq %cl, %rcx
	cmpl $0, %ecx
	jnz .Lbb2188
	movq $0, -1840(%rbp)
	cmpq $0, %r15
	jl .Lbb2180
	movq %r15, %r14
	jmp .Lbb2182
.Lbb2180:
	movq (%rax), %rsi
	movq $9223372036854775807, %rcx
	cmpq %rcx, %rsi
	ja .Lbb2187
	movq %r15, -1840(%rbp)
	movq %rsi, %r14
	addq %r15, %r14
	movq %rsi, %rcx
	xorq %r14, %rcx
	movq %r15, %rdx
	xorq %r14, %rdx
	andq %rdx, %rcx
	cmpq $0, %rcx
	jl .Lbb2185
.Lbb2182:
	movq (%rax), %rax
	cmpq %rax, %r14
	jb .Lbb2188
	movq %rax, %rdx
	.loc 1 572
	movq %rdx, -1240(%rbp)
	movq %r14, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	movq %rdx, -1240(%rbp)
	ud2
.Lbb2185:
	movq %r15, %rcx
	.loc 1 569
	movl $64, %r8d
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb2187:
	.loc 1 567
	movl $320, %edx
	movq %rdx, -1240(%rbp)
	callq myl_qbe_fail_cast
	movq %rdx, -1240(%rbp)
	ud2
.Lbb2188:
	movq $0, -1840(%rbp)
	movq $1, -1840(%rbp)
	movq $2, -1840(%rbp)
	movq $3, -1840(%rbp)
	movq $4, -1840(%rbp)
	movq $5, -1840(%rbp)
	movq $6, -1840(%rbp)
	movq $7, -1840(%rbp)
	movq $8, -1840(%rbp)
	movq $9, -1840(%rbp)
	movq $10, -1840(%rbp)
	movq $11, -1840(%rbp)
	movq -2016(%rbp), %rax
	movq $0, -1840(%rbp)
	cmpq $0, %r15
	jl .Lbb2190
	movq %r15, %r14
	jmp .Lbb2192
.Lbb2190:
	movq (%rax), %rsi
	movq $9223372036854775807, %rcx
	cmpq %rcx, %rsi
	ja .Lbb2238
	movq %r15, -1840(%rbp)
	movq %rsi, %r14
	addq %r15, %r14
	movq %rsi, %rcx
	xorq %r14, %rcx
	movq %r15, %rdx
	xorq %r14, %rdx
	andq %rdx, %rcx
	cmpq $0, %rcx
	jl .Lbb2236
.Lbb2192:
	movq (%rax), %rcx
	cmpq %rcx, %r14
	jae .Lbb2234
	movq 32(%rax), %rax
	movq (%rax, %r14, 8), %rdx
	.loc 1 1006
	movq %rdx, -1240(%rbp)
	movq %rdi, %rsi
	leaq -2368(%rbp), %rdi
	callq myl_f_713a1417c769dc7584c090ac7ff485481f486a11bb803fbf9ec54289769f2854
	movl -1436(%rbp), %r14d
	movq -1064(%rbp), %rsi
	movq -1224(%rbp), %rdi
	movq %rax, -1056(%rbp)
	cmpl $0, %r14d
	jz .Lbb2211
	testl $28, %r13d
	jnz .Lbb2203
	movq -2288(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb2202
	movq -16(%r8), %rcx
	movq $4611686018427387906, %r9
	andq %r9, %rcx
	cmpq $0, %rcx
	jnz .Lbb2201
	movq -32(%r8), %rcx
	subq $1, %rcx
	jnz .Lbb2200
	movq -24(%r8), %r9
	cmpq $0, %r9
	jnz .Lbb2200
	.loc 1 1006
	leaq -2288(%rbp), %rsi
	movq %rbx, %rdi
	callq myl_t_277089d91c0bdf4f2e6862ba7e4a07605119431f5d13f726dd352b06f1b206a9_rcg_drop
	movq -1064(%rbp), %rsi
	movq -1056(%rbp), %rax
	movq -1224(%rbp), %rdi
	jmp .Lbb2202
.Lbb2200:
	movq %rcx, -32(%r8)
.Lbb2201:
	movq $0, -2288(%rbp)
.Lbb2202:
	movl $0, %r14d
	jmp .Lbb2211
.Lbb2203:
	movq -2288(%rbp), %r8
	cmpq $0, %r8
	jz .Lbb2210
	movq -16(%r8), %rcx
	movq $4611686018427387906, %r9
	andq %r9, %rcx
	cmpq $0, %rcx
	jnz .Lbb2209
	movq -24(%r8), %rcx
	subq $1, %rcx
	jnz .Lbb2208
	movq -32(%r8), %r9
	cmpq $0, %r9
	jnz .Lbb2208
	.loc 1 1006
	leaq -2288(%rbp), %rsi
	movq %rbx, %rdi
	callq myl_t_277089d91c0bdf4f2e6862ba7e4a07605119431f5d13f726dd352b06f1b206a9_rcg_unloan
	movq -1064(%rbp), %rsi
	movq -1056(%rbp), %rax
	movq -1224(%rbp), %rdi
	jmp .Lbb2210
.Lbb2208:
	movq %rcx, -24(%r8)
.Lbb2209:
	movq $0, -2288(%rbp)
.Lbb2210:
	movl $0, %r14d
.Lbb2211:
	movl (%rax), %ecx
	cmpq $0, %rcx
	setz %r9b
	movzbq %r9b, %r9
	movq %rax, %r8
	addq $8, %r8
	cmpl $0, %r9d
	jnz .Lbb2216
	cmpq $1, %rcx
	jnz .Lbb2614
	movq 8(%rax), %r9
	movq %r9, -2248(%rbp)
	movq $101, -1840(%rbp)
	imulq $101, %r9, %rax
	movl $4294967295, %ecx
	movq %r9, %r11
	andq %rcx, %r11
	movq %r9, %r10
	shrq $32, %r10
	imulq $101, %r11, %rcx
	shrq $32, %rcx
	imulq $101, %r10, %r8
	addq %rcx, %r8
	movl $4294967295, %ecx
	andq %r8, %rcx
	shrq $32, %r8
	imulq $0, %r11, %r11
	addq %r11, %rcx
	shrq $32, %rcx
	imulq $0, %r10, %r10
	addq %r10, %r8
	addq %r8, %rcx
	cmpq $0, %r9
	setl %r8b
	movzbq %r8b, %r8
	negq %r8
	movq %r8, %r10
	andq $101, %r10
	movq %r9, %r8
	andq $0, %r8
	subq %r10, %rcx
	negq %r8
	addq %rcx, %r8
	movq %rax, %rcx
	sarq $63, %rcx
	cmpq %rcx, %r8
	jz .Lbb2220
	movq %r9, %rdx
	.loc 1 1022
	movl $64, %r8d
	movl $101, %ecx
	movq %rdx, -1240(%rbp)
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb2216:
	movq %r8, %rax
	movq 0(%rax), %rcx
	movq %rcx, -2248(%rbp)
	movq 8(%rax), %rcx
	movq %rcx, -2240(%rbp)
	movq 16(%rax), %rax
	movq %rax, -2232(%rbp)
	movq -2248(%rbp), %rax
	movq %rax, -1912(%rbp)
	movq -2240(%rbp), %rax
	movq %rax, -1904(%rbp)
	movq -2232(%rbp), %rax
	movq %rax, -1896(%rbp)
	movq -1912(%rbp), %r10
	leaq -1912(%rbp), %rax
	movq %rax, -1840(%rbp)
	movq -1904(%rbp), %r9
	movq %r9, -1840(%rbp)
	movq $3, -1832(%rbp)
	imulq $3, %r9, %rax
	movl $4294967295, %ecx
	andq %r9, %rcx
	movq %r9, %r11
	shrq $32, %r11
	imulq $3, %rcx, %r8
	movq %r8, -1072(%rbp)
	movq -1072(%rbp), %r8
	shrq $32, %r8
	movq %r8, -1088(%rbp)
	imulq $3, %r11, %r8
	movq %r8, -1080(%rbp)
	movq -1088(%rbp), %r8
	addq -1080(%rbp), %r8
	movq %r8, -1104(%rbp)
	movl $4294967295, %r8d
	movq %r8, -1096(%rbp)
	movq -1104(%rbp), %r8
	andq -1096(%rbp), %r8
	movq %r8, -1120(%rbp)
	movq -1104(%rbp), %r8
	shrq $32, %r8
	movq %r8, -1112(%rbp)
	imulq $0, %rcx, %rcx
	movq %rcx, -1128(%rbp)
	movq -1112(%rbp), %r8
	movq -1120(%rbp), %rcx
	addq -1128(%rbp), %rcx
	shrq $32, %rcx
	imulq $0, %r11, %r11
	addq %r11, %r8
	addq %r8, %rcx
	cmpq $0, %r9
	setl %r8b
	movzbq %r8b, %r8
	negq %r8
	movq %r8, %r11
	andq $3, %r11
	movq %r9, %r8
	andq $0, %r8
	subq %r11, %rcx
	negq %r8
	addq %rcx, %r8
	movq %rax, %rcx
	sarq $63, %rcx
	cmpq %rcx, %r8
	jnz .Lbb2232
	movq %rax, -1840(%rbp)
	movq %r10, %r9
	addq %rax, %r9
	movq %r10, %rcx
	xorq %r9, %rcx
	movq %rax, %r8
	xorq %r9, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jl .Lbb2230
	leaq -1912(%rbp), %rax
	movq %rax, -1840(%rbp)
	movq -1896(%rbp), %rcx
	movq %rcx, -1840(%rbp)
	movq %rcx, %rax
	addq %r9, %rax
	movq %r9, %r8
	xorq %rax, %r8
	movq %rcx, %r10
	xorq %rax, %r10
	andq %r10, %r8
	cmpq $0, %r8
	jl .Lbb2228
.Lbb2220:
	movq %rax, -1840(%rbp)
	movq %rsi, %r9
	addq %rax, %rsi
	movq %r9, %rcx
	xorq %rsi, %rcx
	movq %rax, %r8
	xorq %rsi, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jl .Lbb2226
	movq $1, -1840(%rbp)
	movq $9223372036854775806, %rax
	cmpq %rax, %r15
	jg .Lbb2224
	addq $1, %r15
	movl %r14d, -1436(%rbp)
	movq %rsi, -1064(%rbp)
	jmp .Lbb2176
.Lbb2224:
	movq %r15, %rcx
	.loc 1 1034
	movl $64, %r8d
	movq %rcx, %rbx
	movl $1, %ecx
	movq %rbx, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb2226:
	movq %rax, %rcx
	movq %r9, %rsi
	.loc 1 1030
	movl $64, %r8d
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb2228:
	movq %r9, %rdx
	.loc 1 1017
	movl $64, %r8d
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb2230:
	movq %rax, %rcx
	movq %r10, %rdx
	.loc 1 1014
	movl $64, %r8d
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb2232:
	movq %r9, %rdx
	.loc 1 1013
	movl $64, %r8d
	movl $3, %ecx
	movq %rdx, -1240(%rbp)
	movl $2, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb2234:
	movq %rcx, %rdx
	.loc 1 1005
	movq %rdx, -1240(%rbp)
	movq %r14, %rsi
	callq myl_qbe_fail_normalized_index_bounds
	movq %rdx, -1240(%rbp)
	ud2
.Lbb2236:
	movq %r15, %rcx
	.loc 1 1002
	movl $64, %r8d
	movq %rsi, %rdx
	movq %rdx, -1240(%rbp)
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb2238:
	.loc 1 1000
	movl $320, %edx
	movq %rdx, -1240(%rbp)
	callq myl_qbe_fail_cast
	movq %rdx, -1240(%rbp)
	ud2
.Lbb2239:
	movq -1208(%rbp), %rcx
	movq -1192(%rbp), %r9
	movq %rbx, %r15
	movq -1184(%rbp), %rbx
	movq -1176(%rbp), %r11
	movq -1216(%rbp), %rax
	movq -1200(%rbp), %r8
	movl -1436(%rbp), %r14d
	movq -1064(%rbp), %rsi
	jmp .Lbb2243
.Lbb2240:
	movq %r10, %rbx
	movq %r12, -1840(%rbp)
	cmpq $0, %r12
	jg .Lbb2251
	movl $0, %esi
.Lbb2243:
	movq %rsi, %r10
	movq %r10, -1840(%rbp)
	movq -1280(%rbp), %rsi
	addq %r10, %rsi
	movq %rsi, -1352(%rbp)
	movq -1280(%rbp), %rsi
	xorq -1352(%rbp), %rsi
	movq %rsi, -1256(%rbp)
	movq %r10, %rsi
	xorq -1352(%rbp), %rsi
	movq %rsi, -1248(%rbp)
	movq -1256(%rbp), %rsi
	andq -1248(%rbp), %rsi
	movq %rsi, -1272(%rbp)
	movq -1264(%rbp), %rsi
	cmpq $0, -1272(%rbp)
	jl .Lbb2249
	movq $1000000007, -1840(%rbp)
	movq $1, -1840(%rbp)
	movq $9223372036854775806, %r10
	movq %r10, -1288(%rbp)
	movq -1416(%rbp), %r10
	cmpq -1288(%rbp), %r10
	jg .Lbb2247
	movq -1352(%rbp), %r10
	sarq $63, %r10
	movq %r10, -1376(%rbp)
	movq -1376(%rbp), %r10
	xorq -1352(%rbp), %r10
	movq %r10, -1296(%rbp)
	movq -1296(%rbp), %r10
	subq -1376(%rbp), %r10
	movq %r10, -1304(%rbp)
	movq $-8543223828751151131, %r10
	movq %r10, -1312(%rbp)
	movq %rax, %r10
	movq -1304(%rbp), %rax
	mulq -1312(%rbp)
	movq %r10, %rax
	movq %rdx, -1320(%rbp)
	movq -1320(%rbp), %r10
	shrq $29, %r10
	movq %r10, -1328(%rbp)
	movq -1376(%rbp), %r10
	xorq -1328(%rbp), %r10
	movq %r10, -1336(%rbp)
	movq -1336(%rbp), %r10
	subq -1376(%rbp), %r10
	movq %r10, -1344(%rbp)
	movl $1000000007, %r10d
	imulq -1344(%rbp), %r10
	movq %r10, -1360(%rbp)
	movq -1352(%rbp), %r10
	subq -1360(%rbp), %r10
	movq %r10, -1408(%rbp)
	cmpq $0, %r10
	setnz %r10b
	movzbq %r10b, %r10
	movq %r10, -1368(%rbp)
	movq -1376(%rbp), %r10
	andq -1368(%rbp), %r10
	movq %r10, -1384(%rbp)
	movq -1384(%rbp), %r10
	negq %r10
	movq %r10, -1392(%rbp)
	movq -1392(%rbp), %r10
	andq $1000000007, %r10
	movq %r10, -1400(%rbp)
	movq -1408(%rbp), %r10
	addq -1400(%rbp), %r10
	movq %r10, -1464(%rbp)
	movq -1416(%rbp), %r10
	addq $1, %r10
	movq %r10, -1456(%rbp)
	movq -1424(%rbp), %r10
	movq -1472(%rbp), %rsi
	movsd -1464(%rbp), %xmm15
	movsd %xmm15, -1280(%rbp)
	movq -1456(%rbp), %r10
	jmp .Lbb1498
.Lbb2247:
	movq -1416(%rbp), %rdx
	.loc 1 1045
	movl $64, %r8d
	movl $1, %ecx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb2249:
	movq %r10, %rcx
	movq -1280(%rbp), %r13
	.loc 1 1039
	movl $64, %r8d
	movq %r13, %rdx
	movl $0, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb2251:
	movq -1432(%rbp), %rsi
	movl -1440(%rbp), %r12d
	movl -1516(%rbp), %r14d
	movl -1540(%rbp), %eax
	movl -1520(%rbp), %ebx
	movq -2088(%rbp), %rcx
	movq (%rcx), %rdx
	cmpq $0, %rdx
	seta %dl
	movzbq %dl, %rdx
	cmpl $0, %edx
	jnz .Lbb2255
	movq $0, -1840(%rbp)
	movq (%rcx), %rdx
	cmpq %rdx, %rsi
	jb .Lbb2255
	.loc 1 572
	callq myl_qbe_fail_normalized_index_bounds
	movq %rdx, -1240(%rbp)
	ud2
.Lbb2255:
	movq $0, -1840(%rbp)
	movq $1, -1840(%rbp)
	movq $2, -1840(%rbp)
	movq $4, -1840(%rbp)
	movq $5, -1840(%rbp)
	movq $6, -1840(%rbp)
	movq $7, -1840(%rbp)
	movq $8, -1840(%rbp)
	movq $9, -1840(%rbp)
	movq $10, -1840(%rbp)
	movq $11, -1840(%rbp)
	movl -2184(%rbp), %ecx
	movl -2152(%rbp), %edx
	orl %edx, %ecx
	jnz .Lbb2257
	movl %r12d, %r13d
	movl %eax, %r12d
	jmp .Lbb2258
.Lbb2257:
	leaq -2208(%rbp), %rax
	movq %rax, -2144(%rbp)
	leaq -2176(%rbp), %rax
	movq %rax, -2136(%rbp)
	.loc 1 1027
	movl $2, %edx
	leaq -2144(%rbp), %rsi
	movq %rdi, %r13
	callq myl_qbe_rc_scopes_close
	movq %rdx, -1240(%rbp)
	movq %r13, %rdi
	movl %r12d, %r13d
	movl -1540(%rbp), %r12d
.Lbb2258:
	.loc 1 1027
	callq myl_qbe_exit_skip
	movq %rdx, -1240(%rbp)
	movq %r15, %rdi
	movl %eax, %ecx
	movl %r12d, %eax
	movl %eax, %r12d
	movl -1548(%rbp), %eax
	movl -1544(%rbp), %r15d
	cmpl $0, %ecx
	jnz .Lbb2422
	movq -2016(%rbp), %rdx
	cmpq $0, %rdx
	jnz .Lbb2261
	xchgl %r15d, %r12d
	xchgl %eax, %r15d
	jmp .Lbb2270
.Lbb2261:
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2268
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jz .Lbb2264
	xchgl %r15d, %r12d
	xchgl %eax, %r15d
	jmp .Lbb2267
.Lbb2264:
	movq -24(%rdx), %rsi
	cmpq $0, %rsi
	jnz .Lbb2266
	.loc 1 1027
	leaq -2016(%rbp), %rsi
	movq %rdi, %r15
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r15, %rdi
	movl %r12d, %eax
	movl -1548(%rbp), %r12d
	movl %r12d, %r15d
	movl -1544(%rbp), %r12d
	jmp .Lbb2270
.Lbb2266:
	xchgl %r15d, %r12d
	xchgl %eax, %r15d
.Lbb2267:
	movq %rcx, -32(%rdx)
	jmp .Lbb2269
.Lbb2268:
	xchgl %r15d, %r12d
	xchgl %eax, %r15d
.Lbb2269:
	movq $0, -2016(%rbp)
.Lbb2270:
	movl -2296(%rbp), %ecx
	cmpl $0, %ecx
	jz .Lbb2288
	movl $0, -2296(%rbp)
	testl $28, %r13d
	jnz .Lbb2280
	movq -2024(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2288
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2279
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2278
	movl %eax, %r13d
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2277
	.loc 1 1027
	leaq -2024(%rbp), %rsi
	movq %rdi, %r15
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r15, %rdi
	movl %r13d, %eax
	movl -1548(%rbp), %r15d
	jmp .Lbb2288
.Lbb2277:
	movl %r13d, %eax
.Lbb2278:
	movq %rcx, -32(%rdx)
.Lbb2279:
	movq $0, -2024(%rbp)
	jmp .Lbb2288
.Lbb2280:
	movq -2024(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2288
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2287
	movq -24(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2286
	movl %eax, %r13d
	movq -32(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2285
	.loc 1 1027
	leaq -2024(%rbp), %rsi
	movq %rdi, %r15
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r15, %rdi
	movl %r13d, %eax
	movl -1548(%rbp), %r15d
	jmp .Lbb2288
.Lbb2285:
	movl %r13d, %eax
.Lbb2286:
	movq %rcx, -24(%rdx)
.Lbb2287:
	movq $0, -2024(%rbp)
.Lbb2288:
	movq -2032(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2296
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2295
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2294
	movl %eax, %r13d
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2293
	.loc 1 1027
	leaq -2032(%rbp), %rsi
	movq %rdi, %r15
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r15, %rdi
	movl %r13d, %eax
	movl -1548(%rbp), %r15d
	jmp .Lbb2296
.Lbb2293:
	movl %r13d, %eax
.Lbb2294:
	movq %rcx, -32(%rdx)
.Lbb2295:
	movq $0, -2032(%rbp)
.Lbb2296:
	movl -2304(%rbp), %ecx
	cmpl $0, %ecx
	jz .Lbb2314
	movl $0, -2304(%rbp)
	testl $28, %r14d
	jnz .Lbb2306
	movq -2040(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2314
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2305
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2304
	movl %eax, %r13d
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2303
	.loc 1 1027
	leaq -2040(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r14, %rdi
	movl %r13d, %eax
	jmp .Lbb2314
.Lbb2303:
	movl %r13d, %eax
.Lbb2304:
	movq %rcx, -32(%rdx)
.Lbb2305:
	movq $0, -2040(%rbp)
	jmp .Lbb2314
.Lbb2306:
	movq -2040(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2314
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2313
	movq -24(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2312
	movl %eax, %r13d
	movq -32(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2311
	.loc 1 1027
	leaq -2040(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r14, %rdi
	movl %r13d, %eax
	jmp .Lbb2314
.Lbb2311:
	movl %r13d, %eax
.Lbb2312:
	movq %rcx, -24(%rdx)
.Lbb2313:
	movq $0, -2040(%rbp)
.Lbb2314:
	movq -2048(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2322
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2321
	movq -24(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2320
	movl %eax, %r13d
	movq -32(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2319
	.loc 1 1027
	leaq -2048(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r14, %rdi
	movl %r13d, %eax
	jmp .Lbb2322
.Lbb2319:
	movl %r13d, %eax
.Lbb2320:
	movq %rcx, -24(%rdx)
.Lbb2321:
	movq $0, -2048(%rbp)
.Lbb2322:
	movq -2056(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2330
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2329
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2328
	movl %eax, %r13d
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2327
	.loc 1 1027
	leaq -2056(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r14, %rdi
	movl %r13d, %eax
	jmp .Lbb2330
.Lbb2327:
	movl %r13d, %eax
.Lbb2328:
	movq %rcx, -32(%rdx)
.Lbb2329:
	movq $0, -2056(%rbp)
.Lbb2330:
	movl -2312(%rbp), %ecx
	cmpl $0, %ecx
	jz .Lbb2339
	movl $0, -2312(%rbp)
	movq -2064(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2339
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2338
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2337
	movl %eax, %r13d
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2336
	.loc 1 1027
	leaq -2064(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r14, %rdi
	movl %r13d, %eax
	jmp .Lbb2339
.Lbb2336:
	movl %r13d, %eax
.Lbb2337:
	movq %rcx, -32(%rdx)
.Lbb2338:
	movq $0, -2064(%rbp)
.Lbb2339:
	movq -2072(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2347
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2346
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2345
	movl %eax, %r13d
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2344
	.loc 1 1027
	leaq -2072(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r14, %rdi
	movl %r13d, %eax
	jmp .Lbb2347
.Lbb2344:
	movl %r13d, %eax
.Lbb2345:
	movq %rcx, -32(%rdx)
.Lbb2346:
	movq $0, -2072(%rbp)
.Lbb2347:
	movl -2320(%rbp), %ecx
	cmpl $0, %ecx
	jz .Lbb2365
	movl $0, -2320(%rbp)
	testl $28, %r15d
	jnz .Lbb2357
	movq -2080(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2365
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2356
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2355
	movl %eax, %r13d
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2354
	.loc 1 1027
	leaq -2080(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r14, %rdi
	movl %r13d, %eax
	jmp .Lbb2365
.Lbb2354:
	movl %r13d, %eax
.Lbb2355:
	movq %rcx, -32(%rdx)
.Lbb2356:
	movq $0, -2080(%rbp)
	jmp .Lbb2365
.Lbb2357:
	movq -2080(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2365
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2364
	movq -24(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2363
	movl %eax, %r13d
	movq -32(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2362
	.loc 1 1027
	leaq -2080(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r14, %rdi
	movl %r13d, %eax
	jmp .Lbb2365
.Lbb2362:
	movl %r13d, %eax
.Lbb2363:
	movq %rcx, -24(%rdx)
.Lbb2364:
	movq $0, -2080(%rbp)
.Lbb2365:
	movq -2088(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2373
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2372
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2371
	movl %eax, %r13d
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2370
	.loc 1 1027
	leaq -2088(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r14, %rdi
	movl %r13d, %eax
	jmp .Lbb2373
.Lbb2370:
	movl %r13d, %eax
.Lbb2371:
	movq %rcx, -32(%rdx)
.Lbb2372:
	movq $0, -2088(%rbp)
.Lbb2373:
	movl -2328(%rbp), %ecx
	cmpl $0, %ecx
	jz .Lbb2391
	movl $0, -2328(%rbp)
	testl $28, %r12d
	jnz .Lbb2383
	movq -2096(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2391
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2382
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2381
	movl %eax, %r12d
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2380
	.loc 1 1027
	leaq -2096(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r13, %rdi
	movl %r12d, %eax
	jmp .Lbb2391
.Lbb2380:
	movl %r12d, %eax
.Lbb2381:
	movq %rcx, -32(%rdx)
.Lbb2382:
	movq $0, -2096(%rbp)
	jmp .Lbb2391
.Lbb2383:
	movq -2096(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2391
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2390
	movq -24(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2389
	movl %eax, %r12d
	movq -32(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2388
	.loc 1 1027
	leaq -2096(%rbp), %rsi
	movq %rdi, %r13
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r13, %rdi
	movl %r12d, %eax
	jmp .Lbb2391
.Lbb2388:
	movl %r12d, %eax
.Lbb2389:
	movq %rcx, -24(%rdx)
.Lbb2390:
	movq $0, -2096(%rbp)
.Lbb2391:
	cmpl $0, %eax
	jz .Lbb2407
	testl $28, %ebx
	jnz .Lbb2400
	movq -2104(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2407
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2399
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2398
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2398
	.loc 1 1027
	leaq -2104(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	jmp .Lbb2407
.Lbb2398:
	movq %rax, -32(%rcx)
.Lbb2399:
	movq $0, -2104(%rbp)
	jmp .Lbb2407
.Lbb2400:
	movq -2104(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2407
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2406
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2405
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2405
	.loc 1 1027
	leaq -2104(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	jmp .Lbb2407
.Lbb2405:
	movq %rax, -24(%rcx)
.Lbb2406:
	movq $0, -2104(%rbp)
.Lbb2407:
	movq -2112(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2414
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2413
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2412
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2412
	.loc 1 1027
	leaq -2112(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	jmp .Lbb2414
.Lbb2412:
	movq %rax, -32(%rcx)
.Lbb2413:
	movq $0, -2112(%rbp)
.Lbb2414:
	movl -2336(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2422
	movl $0, -2336(%rbp)
	movq -2120(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2422
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2421
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2420
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2420
	.loc 1 1027
	leaq -2120(%rbp), %rsi
	movq %rdi, %r15
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %rdx, -1240(%rbp)
	jmp .Lbb2422
.Lbb2420:
	movq %rax, -32(%rcx)
.Lbb2421:
	movq $0, -2120(%rbp)
.Lbb2422:
	movl $2, %eax
	jmp .Lbb2846
.Lbb2423:
	movq -1280(%rbp), %r13
	movl -1440(%rbp), %r12d
	movl -1516(%rbp), %r14d
	movq -1448(%rbp), %rsi
	.loc 1 1049
	movq %rdi, %rbx
	callq myl_f_8a5a050356fb7a5094326f2b8ccffa083f61d461495e1103718ebd5cfb6ac591
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movq %rax, %rdx
	movl -1520(%rbp), %ebx
	movq -1504(%rbp), %rcx
	movq -1528(%rbp), %rsi
	movq %rcx, -1840(%rbp)
	movq %rdx, %rax
	subq %rcx, %rax
	movq %rax, -1512(%rbp)
	movq %rcx, %r8
	xorq %rdx, %r8
	movq %rdx, %r9
	xorq %rax, %r9
	andq %r9, %r8
	cmpq $0, %r8
	jl .Lbb2607
	movq %rsi, %rdx
	movq -2072(%rbp), %rsi
	cmpq $0, %rsi
	jnz .Lbb2428
	movq %r13, %r10
	movl %ebx, %r13d
	jmp .Lbb2437
.Lbb2428:
	movq -16(%rsi), %rcx
	movq $4611686018427387906, %r8
	andq %r8, %rcx
	cmpq $0, %rcx
	jnz .Lbb2435
	movq -32(%rsi), %rcx
	subq $1, %rcx
	jz .Lbb2431
	movq %r13, %r10
	jmp .Lbb2434
.Lbb2431:
	movq -24(%rsi), %r8
	cmpq $0, %r8
	jnz .Lbb2433
	.loc 1 1052
	leaq -2072(%rbp), %rsi
	movq %rdi, %rbx
	movq %r15, %rdi
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %r13, %r10
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movq -1512(%rbp), %rax
	movl -1520(%rbp), %r13d
	movq -1528(%rbp), %rdx
	jmp .Lbb2437
.Lbb2433:
	movq %r13, %r10
.Lbb2434:
	movl %ebx, %r13d
	movq %rcx, -32(%rsi)
	jmp .Lbb2436
.Lbb2435:
	movq %r13, %r10
	movl %ebx, %r13d
.Lbb2436:
	movq $0, -2072(%rbp)
.Lbb2437:
	movq %r10, -1840(%rbp)
	movq %rax, -1832(%rbp)
	.loc 1 1056
	movq %rdx, %rsi
	movq %rdi, %rbx
	callq myl_qbe_stream_begin
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movq %rax, %rsi
	movq %rsi, -1536(%rbp)
	.loc 1 1056
	movl $0, %edx
	movq %rsi, %rax
	leaq -1840(%rbp), %rsi
	movq %rdi, %rbx
	movq %rax, %rdi
	callq myl_r_1a91deb3742283487d66c3b500f6effd7ef1170e6d4b4368fe9ec3c3f0354fda
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movq -1536(%rbp), %rsi
	.loc 1 1056
	movq %rsi, %rax
	movl $32, %esi
	movq %rdi, %rbx
	movq %rax, %rdi
	callq myl_qbe_print_byte
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movq -1536(%rbp), %rsi
	.loc 1 1056
	movl $0, %edx
	movq %rsi, %rax
	leaq -1832(%rbp), %rsi
	movq %rdi, %rbx
	movq %rax, %rdi
	callq myl_r_1a91deb3742283487d66c3b500f6effd7ef1170e6d4b4368fe9ec3c3f0354fda
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movq -1536(%rbp), %rsi
	.loc 1 1056
	movq %rsi, %rax
	movl $10, %esi
	movq %rdi, %rbx
	movq %rax, %rdi
	callq myl_qbe_print_byte
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movq -1536(%rbp), %rsi
	movq -1528(%rbp), %rdx
	.loc 1 1056
	movq %rdi, %rbx
	callq myl_qbe_stream_finish
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl -1540(%rbp), %eax
	movl %eax, %ebx
	movl -2184(%rbp), %eax
	movl -2152(%rbp), %ecx
	orl %ecx, %eax
	jz .Lbb2439
	leaq -2208(%rbp), %rax
	movq %rax, -2144(%rbp)
	leaq -2176(%rbp), %rax
	movq %rax, -2136(%rbp)
	.loc 1 1059
	movl $2, %edx
	leaq -2144(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_qbe_rc_scopes_close
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	movl -1540(%rbp), %ebx
.Lbb2439:
	.loc 1 1059
	callq myl_qbe_exit_skip
	movq %rdx, -1240(%rbp)
	movq %r15, %rdi
	movl %eax, %edx
	movl %ebx, %eax
	movl -1552(%rbp), %ecx
	movl -1548(%rbp), %r15d
	movl %eax, %ebx
	movl -1544(%rbp), %eax
	cmpl $0, %edx
	jnz .Lbb2606
	movq -2016(%rbp), %rsi
	cmpq $0, %rsi
	jnz .Lbb2442
	xchgl %eax, %ebx
	jmp .Lbb2451
.Lbb2442:
	movq -16(%rsi), %rdx
	movq $4611686018427387906, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jnz .Lbb2449
	movq -32(%rsi), %rdx
	subq $1, %rdx
	jz .Lbb2445
	xchgl %eax, %ebx
	jmp .Lbb2448
.Lbb2445:
	movq -24(%rsi), %r8
	cmpq $0, %r8
	jnz .Lbb2447
	.loc 1 1059
	leaq -2016(%rbp), %rsi
	movq %rdi, %r15
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r15, %rdi
	movl %ebx, %eax
	movl -1552(%rbp), %ecx
	movl -1548(%rbp), %r15d
	movl -1544(%rbp), %ebx
	jmp .Lbb2451
.Lbb2447:
	xchgl %eax, %ebx
.Lbb2448:
	movq %rdx, -32(%rsi)
	jmp .Lbb2450
.Lbb2449:
	xchgl %eax, %ebx
.Lbb2450:
	movq $0, -2016(%rbp)
.Lbb2451:
	movl -2296(%rbp), %edx
	cmpl $0, %edx
	jz .Lbb2469
	movl $0, -2296(%rbp)
	testl $28, %r12d
	jnz .Lbb2461
	movq -2024(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb2469
	movq -16(%rsi), %rdx
	movq $4611686018427387906, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jnz .Lbb2460
	movq -32(%rsi), %rdx
	subq $1, %rdx
	jnz .Lbb2459
	movl %eax, %r12d
	movq -24(%rsi), %rax
	cmpq $0, %rax
	jnz .Lbb2458
	.loc 1 1059
	leaq -2024(%rbp), %rsi
	movq %rdi, %r15
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r15, %rdi
	movl %r12d, %eax
	movl -1552(%rbp), %ecx
	movl -1548(%rbp), %r15d
	jmp .Lbb2469
.Lbb2458:
	movl %r12d, %eax
.Lbb2459:
	movq %rdx, -32(%rsi)
.Lbb2460:
	movq $0, -2024(%rbp)
	jmp .Lbb2469
.Lbb2461:
	movq -2024(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb2469
	movq -16(%rsi), %rdx
	movq $4611686018427387906, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jnz .Lbb2468
	movq -24(%rsi), %rdx
	subq $1, %rdx
	jnz .Lbb2467
	movl %eax, %r12d
	movq -32(%rsi), %rax
	cmpq $0, %rax
	jnz .Lbb2466
	.loc 1 1059
	leaq -2024(%rbp), %rsi
	movq %rdi, %r15
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r15, %rdi
	movl %r12d, %eax
	movl -1552(%rbp), %ecx
	movl -1548(%rbp), %r15d
	jmp .Lbb2469
.Lbb2466:
	movl %r12d, %eax
.Lbb2467:
	movq %rdx, -24(%rsi)
.Lbb2468:
	movq $0, -2024(%rbp)
.Lbb2469:
	movq -2032(%rbp), %rsi
	cmpq $0, %rsi
	jnz .Lbb2471
	movl %r15d, %r12d
	jmp .Lbb2479
.Lbb2471:
	movq -16(%rsi), %rdx
	movq $4611686018427387906, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jnz .Lbb2477
	movq -32(%rsi), %rdx
	subq $1, %rdx
	jnz .Lbb2476
	movl %eax, %r12d
	movq -24(%rsi), %rax
	cmpq $0, %rax
	jnz .Lbb2475
	.loc 1 1059
	leaq -2032(%rbp), %rsi
	movq %rdi, %r15
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r15, %rdi
	movl %r12d, %eax
	movl -1552(%rbp), %ecx
	movl -1548(%rbp), %r12d
	jmp .Lbb2479
.Lbb2475:
	movl %r12d, %eax
.Lbb2476:
	movl %r15d, %r12d
	movq %rdx, -32(%rsi)
	jmp .Lbb2478
.Lbb2477:
	movl %r15d, %r12d
.Lbb2478:
	movq $0, -2032(%rbp)
.Lbb2479:
	movl -2304(%rbp), %edx
	cmpl $0, %edx
	jz .Lbb2497
	movl $0, -2304(%rbp)
	testl $28, %r14d
	jnz .Lbb2489
	movq -2040(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb2497
	movq -16(%rsi), %rdx
	movq $4611686018427387906, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jnz .Lbb2488
	movq -32(%rsi), %rdx
	subq $1, %rdx
	jnz .Lbb2487
	movl %eax, %r14d
	movq -24(%rsi), %rax
	cmpq $0, %rax
	jnz .Lbb2486
	.loc 1 1059
	leaq -2040(%rbp), %rsi
	movq %rdi, %r15
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r15, %rdi
	movl %r14d, %eax
	movl -1552(%rbp), %ecx
	jmp .Lbb2497
.Lbb2486:
	movl %r14d, %eax
.Lbb2487:
	movq %rdx, -32(%rsi)
.Lbb2488:
	movq $0, -2040(%rbp)
	jmp .Lbb2497
.Lbb2489:
	movq -2040(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb2497
	movq -16(%rsi), %rdx
	movq $4611686018427387906, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jnz .Lbb2496
	movq -24(%rsi), %rdx
	subq $1, %rdx
	jnz .Lbb2495
	movl %eax, %r14d
	movq -32(%rsi), %rax
	cmpq $0, %rax
	jnz .Lbb2494
	.loc 1 1059
	leaq -2040(%rbp), %rsi
	movq %rdi, %r15
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r15, %rdi
	movl %r14d, %eax
	movl -1552(%rbp), %ecx
	jmp .Lbb2497
.Lbb2494:
	movl %r14d, %eax
.Lbb2495:
	movq %rdx, -24(%rsi)
.Lbb2496:
	movq $0, -2040(%rbp)
.Lbb2497:
	movq -2048(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb2505
	movq -16(%rsi), %rdx
	movq $4611686018427387906, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jnz .Lbb2504
	movq -24(%rsi), %rdx
	subq $1, %rdx
	jnz .Lbb2503
	movl %eax, %r14d
	movq -32(%rsi), %rax
	cmpq $0, %rax
	jnz .Lbb2502
	.loc 1 1059
	leaq -2048(%rbp), %rsi
	movq %rdi, %r15
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r15, %rdi
	movl %r14d, %eax
	movl -1552(%rbp), %ecx
	jmp .Lbb2505
.Lbb2502:
	movl %r14d, %eax
.Lbb2503:
	movq %rdx, -24(%rsi)
.Lbb2504:
	movq $0, -2048(%rbp)
.Lbb2505:
	movq -2056(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb2513
	movq -16(%rsi), %rdx
	movq $4611686018427387906, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jnz .Lbb2512
	movq -32(%rsi), %rdx
	subq $1, %rdx
	jnz .Lbb2511
	movl %eax, %r14d
	movq -24(%rsi), %rax
	cmpq $0, %rax
	jnz .Lbb2510
	.loc 1 1059
	leaq -2056(%rbp), %rsi
	movq %rdi, %r15
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r15, %rdi
	movl %r14d, %eax
	movl -1552(%rbp), %ecx
	jmp .Lbb2513
.Lbb2510:
	movl %r14d, %eax
.Lbb2511:
	movq %rdx, -32(%rsi)
.Lbb2512:
	movq $0, -2056(%rbp)
.Lbb2513:
	movl -2312(%rbp), %edx
	cmpl $0, %edx
	jz .Lbb2522
	movl $0, -2312(%rbp)
	movq -2064(%rbp), %rsi
	cmpq $0, %rsi
	jz .Lbb2522
	movq -16(%rsi), %rdx
	movq $4611686018427387906, %r8
	andq %r8, %rdx
	cmpq $0, %rdx
	jnz .Lbb2521
	movq -32(%rsi), %rdx
	subq $1, %rdx
	jnz .Lbb2520
	movl %eax, %r14d
	movq -24(%rsi), %rax
	cmpq $0, %rax
	jnz .Lbb2519
	.loc 1 1059
	leaq -2064(%rbp), %rsi
	movq %rdi, %r15
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r15, %rdi
	movl %r14d, %eax
	movl -1552(%rbp), %ecx
	jmp .Lbb2522
.Lbb2519:
	movl %r14d, %eax
.Lbb2520:
	movq %rdx, -32(%rsi)
.Lbb2521:
	movq $0, -2064(%rbp)
.Lbb2522:
	cmpl $0, %ecx
	jz .Lbb2531
	movq -2072(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2531
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2530
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2529
	movl %eax, %r14d
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2528
	.loc 1 1059
	leaq -2072(%rbp), %rsi
	movq %rdi, %r15
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r15, %rdi
	movl %r14d, %eax
	jmp .Lbb2531
.Lbb2528:
	movl %r14d, %eax
.Lbb2529:
	movq %rcx, -32(%rdx)
.Lbb2530:
	movq $0, -2072(%rbp)
.Lbb2531:
	movl -2320(%rbp), %ecx
	cmpl $0, %ecx
	jz .Lbb2549
	movl $0, -2320(%rbp)
	testl $28, %r12d
	jnz .Lbb2541
	movq -2080(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2549
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2540
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2539
	movl %eax, %r12d
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2538
	.loc 1 1059
	leaq -2080(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r14, %rdi
	movl %r12d, %eax
	jmp .Lbb2549
.Lbb2538:
	movl %r12d, %eax
.Lbb2539:
	movq %rcx, -32(%rdx)
.Lbb2540:
	movq $0, -2080(%rbp)
	jmp .Lbb2549
.Lbb2541:
	movq -2080(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2549
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2548
	movq -24(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2547
	movl %eax, %r12d
	movq -32(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2546
	.loc 1 1059
	leaq -2080(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r14, %rdi
	movl %r12d, %eax
	jmp .Lbb2549
.Lbb2546:
	movl %r12d, %eax
.Lbb2547:
	movq %rcx, -24(%rdx)
.Lbb2548:
	movq $0, -2080(%rbp)
.Lbb2549:
	movq -2088(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2557
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2556
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2555
	movl %eax, %r12d
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2554
	.loc 1 1059
	leaq -2088(%rbp), %rsi
	movq %rdi, %r14
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r14, %rdi
	movl %r12d, %eax
	jmp .Lbb2557
.Lbb2554:
	movl %r12d, %eax
.Lbb2555:
	movq %rcx, -32(%rdx)
.Lbb2556:
	movq $0, -2088(%rbp)
.Lbb2557:
	movl -2328(%rbp), %ecx
	cmpl $0, %ecx
	jz .Lbb2575
	movl $0, -2328(%rbp)
	testl $28, %ebx
	jnz .Lbb2567
	movq -2096(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2575
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2566
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2565
	movl %eax, %ebx
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2564
	.loc 1 1059
	leaq -2096(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %ebx, %eax
	jmp .Lbb2575
.Lbb2564:
	movl %ebx, %eax
.Lbb2565:
	movq %rcx, -32(%rdx)
.Lbb2566:
	movq $0, -2096(%rbp)
	jmp .Lbb2575
.Lbb2567:
	movq -2096(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2575
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2574
	movq -24(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2573
	movl %eax, %ebx
	movq -32(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2572
	.loc 1 1059
	leaq -2096(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %ebx, %eax
	jmp .Lbb2575
.Lbb2572:
	movl %ebx, %eax
.Lbb2573:
	movq %rcx, -24(%rdx)
.Lbb2574:
	movq $0, -2096(%rbp)
.Lbb2575:
	cmpl $0, %eax
	jz .Lbb2591
	testl $28, %r13d
	jnz .Lbb2584
	movq -2104(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2591
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2583
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2582
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2582
	.loc 1 1059
	leaq -2104(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	jmp .Lbb2591
.Lbb2582:
	movq %rax, -32(%rcx)
.Lbb2583:
	movq $0, -2104(%rbp)
	jmp .Lbb2591
.Lbb2584:
	movq -2104(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2591
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2590
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2589
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2589
	.loc 1 1059
	leaq -2104(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	jmp .Lbb2591
.Lbb2589:
	movq %rax, -24(%rcx)
.Lbb2590:
	movq $0, -2104(%rbp)
.Lbb2591:
	movq -2112(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2598
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2597
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2596
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2596
	.loc 1 1059
	leaq -2112(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	jmp .Lbb2598
.Lbb2596:
	movq %rax, -32(%rcx)
.Lbb2597:
	movq $0, -2112(%rbp)
.Lbb2598:
	movl -2336(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2606
	movl $0, -2336(%rbp)
	movq -2120(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2606
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2605
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2604
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2604
	.loc 1 1059
	leaq -2120(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %rdx, -1240(%rbp)
	jmp .Lbb2606
.Lbb2604:
	movq %rax, -32(%rcx)
.Lbb2605:
	movq $0, -2120(%rbp)
.Lbb2606:
	movl $0, %eax
	jmp .Lbb2846
.Lbb2607:
	.loc 1 1051
	movl $64, %r8d
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb2608:
	movq %r13, %rdx
	movq %rbx, %rdi
	.loc 1 496
	movq %rdx, %rbx
	movl $64, %edx
	movq %rbx, %rsi
	callq myl_qbe_fail_cast
	movq %rdx, -1240(%rbp)
	ud2
.Lbb2610:
	movq %r13, %rdx
	movq %rbx, %rdi
	.loc 1 495
	movl $64, %r8d
	movl $0, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb2612:
	movq %rbx, %rdi
	.loc 1 419
	movl $320, %edx
	callq myl_qbe_fail_cast
	movq %rdx, -1240(%rbp)
	ud2
.Lbb2614:
	movl $0, %eax
	jmp .Lbb2846
.Lbb2615:
	movq %rbx, %rdx
	movq %r13, %rdi
	.loc 1 355
	movq %rdx, %rbx
	movl $64, %edx
	movq %rbx, %rsi
	callq myl_qbe_fail_cast
	movq %rdx, -1240(%rbp)
	ud2
.Lbb2617:
	movq %rbx, %rdx
	movq %r13, %rdi
	.loc 1 354
	movl $64, %r8d
	movl $0, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb2619:
	movq %r12, %rdx
	movq %rbx, %rdi
	.loc 1 290
	movq %rdx, %rbx
	movl $64, %edx
	movq %rbx, %rsi
	callq myl_qbe_fail_cast
	movq %rdx, -1240(%rbp)
	ud2
.Lbb2621:
	movq %r12, %rdx
	movq %rbx, %rdi
	.loc 1 289
	movl $64, %r8d
	movl $0, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb2623:
	movq %r12, %rdx
	movq %rbx, %rdi
	.loc 1 225
	movq %rdx, %rbx
	movl $64, %edx
	movq %rbx, %rsi
	callq myl_qbe_fail_cast
	movq %rdx, -1240(%rbp)
	ud2
.Lbb2625:
	movq %r12, %rdx
	movq %rbx, %rdi
	.loc 1 224
	movl $64, %r8d
	movl $0, %ecx
	movl $1, %esi
	callq myl_qbe_fail_overflow_op
	movq %rdx, -1240(%rbp)
	ud2
.Lbb2627:
	movq %rdi, %r12
	movq %rbx, %rdi
	movl -2184(%rbp), %ecx
	movl -2152(%rbp), %edx
	orl %edx, %ecx
	jnz .Lbb2630
	movl %eax, %ebx
	jmp .Lbb2631
.Lbb2630:
	leaq -2208(%rbp), %rcx
	movq %rcx, -2144(%rbp)
	movl %eax, %ebx
	leaq -2176(%rbp), %rax
	movq %rax, -2136(%rbp)
	.loc 1 185
	movl $2, %edx
	leaq -2144(%rbp), %rsi
	movq %rdi, %r14
	callq myl_qbe_rc_scopes_close
	movq %rdx, -1240(%rbp)
	movq %r14, %rdi
.Lbb2631:
	.loc 1 185
	callq myl_qbe_exit_skip
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %eax, %ecx
	movl %ebx, %eax
	cmpl $0, %ecx
	jnz .Lbb2708
	movl -2296(%rbp), %ecx
	cmpl $0, %ecx
	jz .Lbb2641
	movl $0, -2296(%rbp)
	movq -2024(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2641
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2640
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2639
	movl %eax, %ebx
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2638
	.loc 1 185
	leaq -2024(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %ebx, %eax
	jmp .Lbb2641
.Lbb2638:
	movl %ebx, %eax
.Lbb2639:
	movq %rcx, -32(%rdx)
.Lbb2640:
	movq $0, -2024(%rbp)
.Lbb2641:
	movl -2304(%rbp), %ecx
	cmpl $0, %ecx
	jz .Lbb2650
	movl $0, -2304(%rbp)
	movq -2040(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2650
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2649
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2648
	movl %eax, %ebx
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2647
	.loc 1 185
	leaq -2040(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %ebx, %eax
	jmp .Lbb2650
.Lbb2647:
	movl %ebx, %eax
.Lbb2648:
	movq %rcx, -32(%rdx)
.Lbb2649:
	movq $0, -2040(%rbp)
.Lbb2650:
	movl -2312(%rbp), %ecx
	cmpl $0, %ecx
	jz .Lbb2659
	movl $0, -2312(%rbp)
	movq -2064(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2659
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2658
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2657
	movl %eax, %ebx
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2656
	.loc 1 185
	leaq -2064(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %ebx, %eax
	jmp .Lbb2659
.Lbb2656:
	movl %ebx, %eax
.Lbb2657:
	movq %rcx, -32(%rdx)
.Lbb2658:
	movq $0, -2064(%rbp)
.Lbb2659:
	movl -2320(%rbp), %ecx
	cmpl $0, %ecx
	jz .Lbb2668
	movl $0, -2320(%rbp)
	movq -2080(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2668
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2667
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2666
	movl %eax, %ebx
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2665
	.loc 1 185
	leaq -2080(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %ebx, %eax
	jmp .Lbb2668
.Lbb2665:
	movl %ebx, %eax
.Lbb2666:
	movq %rcx, -32(%rdx)
.Lbb2667:
	movq $0, -2080(%rbp)
.Lbb2668:
	movl -2328(%rbp), %ecx
	cmpl $0, %ecx
	jz .Lbb2677
	movl $0, -2328(%rbp)
	movq -2096(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2677
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2676
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2675
	movl %eax, %ebx
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2674
	.loc 1 185
	leaq -2096(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %ebx, %eax
	jmp .Lbb2677
.Lbb2674:
	movl %ebx, %eax
.Lbb2675:
	movq %rcx, -32(%rdx)
.Lbb2676:
	movq $0, -2096(%rbp)
.Lbb2677:
	cmpl $0, %eax
	jz .Lbb2693
	testl $28, %r13d
	jnz .Lbb2686
	movq -2104(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2693
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2685
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2684
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2684
	.loc 1 185
	leaq -2104(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	jmp .Lbb2693
.Lbb2684:
	movq %rax, -32(%rcx)
.Lbb2685:
	movq $0, -2104(%rbp)
	jmp .Lbb2693
.Lbb2686:
	movq -2104(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2693
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2692
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2691
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2691
	.loc 1 185
	leaq -2104(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	jmp .Lbb2693
.Lbb2691:
	movq %rax, -24(%rcx)
.Lbb2692:
	movq $0, -2104(%rbp)
.Lbb2693:
	movq -2112(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2700
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2699
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2698
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2698
	.loc 1 185
	leaq -2112(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	jmp .Lbb2700
.Lbb2698:
	movq %rax, -32(%rcx)
.Lbb2699:
	movq $0, -2112(%rbp)
.Lbb2700:
	movl -2336(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2708
	movl $0, -2336(%rbp)
	movq -2120(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2708
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2707
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2706
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2706
	.loc 1 185
	leaq -2120(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %rdx, -1240(%rbp)
	jmp .Lbb2708
.Lbb2706:
	movq %rax, -32(%rcx)
.Lbb2707:
	movq $0, -2120(%rbp)
.Lbb2708:
	movl $2, %eax
	jmp .Lbb2846
.Lbb2709:
	movq %rdi, %r12
	movq %rbx, %rdi
	movl -2184(%rbp), %ecx
	movl -2152(%rbp), %edx
	orl %edx, %ecx
	jnz .Lbb2712
	movl %eax, %ebx
	jmp .Lbb2713
.Lbb2712:
	leaq -2208(%rbp), %rcx
	movq %rcx, -2144(%rbp)
	movl %eax, %ebx
	leaq -2176(%rbp), %rax
	movq %rax, -2136(%rbp)
	.loc 1 110
	movl $2, %edx
	leaq -2144(%rbp), %rsi
	movq %rdi, %r14
	callq myl_qbe_rc_scopes_close
	movq %rdx, -1240(%rbp)
	movq %r14, %rdi
.Lbb2713:
	.loc 1 110
	callq myl_qbe_exit_skip
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %eax, %ecx
	movl %ebx, %eax
	cmpl $0, %ecx
	jnz .Lbb2790
	movl -2296(%rbp), %ecx
	cmpl $0, %ecx
	jz .Lbb2723
	movl $0, -2296(%rbp)
	movq -2024(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2723
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2722
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2721
	movl %eax, %ebx
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2720
	.loc 1 110
	leaq -2024(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %ebx, %eax
	jmp .Lbb2723
.Lbb2720:
	movl %ebx, %eax
.Lbb2721:
	movq %rcx, -32(%rdx)
.Lbb2722:
	movq $0, -2024(%rbp)
.Lbb2723:
	movl -2304(%rbp), %ecx
	cmpl $0, %ecx
	jz .Lbb2732
	movl $0, -2304(%rbp)
	movq -2040(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2732
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2731
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2730
	movl %eax, %ebx
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2729
	.loc 1 110
	leaq -2040(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %ebx, %eax
	jmp .Lbb2732
.Lbb2729:
	movl %ebx, %eax
.Lbb2730:
	movq %rcx, -32(%rdx)
.Lbb2731:
	movq $0, -2040(%rbp)
.Lbb2732:
	movl -2312(%rbp), %ecx
	cmpl $0, %ecx
	jz .Lbb2741
	movl $0, -2312(%rbp)
	movq -2064(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2741
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2740
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2739
	movl %eax, %ebx
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2738
	.loc 1 110
	leaq -2064(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %ebx, %eax
	jmp .Lbb2741
.Lbb2738:
	movl %ebx, %eax
.Lbb2739:
	movq %rcx, -32(%rdx)
.Lbb2740:
	movq $0, -2064(%rbp)
.Lbb2741:
	movl -2320(%rbp), %ecx
	cmpl $0, %ecx
	jz .Lbb2750
	movl $0, -2320(%rbp)
	movq -2080(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2750
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2749
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2748
	movl %eax, %ebx
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2747
	.loc 1 110
	leaq -2080(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %ebx, %eax
	jmp .Lbb2750
.Lbb2747:
	movl %ebx, %eax
.Lbb2748:
	movq %rcx, -32(%rdx)
.Lbb2749:
	movq $0, -2080(%rbp)
.Lbb2750:
	movl -2328(%rbp), %ecx
	cmpl $0, %ecx
	jz .Lbb2759
	movl $0, -2328(%rbp)
	movq -2096(%rbp), %rdx
	cmpq $0, %rdx
	jz .Lbb2759
	movq -16(%rdx), %rcx
	movq $4611686018427387906, %rsi
	andq %rsi, %rcx
	cmpq $0, %rcx
	jnz .Lbb2758
	movq -32(%rdx), %rcx
	subq $1, %rcx
	jnz .Lbb2757
	movl %eax, %ebx
	movq -24(%rdx), %rax
	cmpq $0, %rax
	jnz .Lbb2756
	.loc 1 110
	leaq -2096(%rbp), %rsi
	movq %rdi, %r12
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
	movl %ebx, %eax
	jmp .Lbb2759
.Lbb2756:
	movl %ebx, %eax
.Lbb2757:
	movq %rcx, -32(%rdx)
.Lbb2758:
	movq $0, -2096(%rbp)
.Lbb2759:
	cmpl $0, %eax
	jz .Lbb2775
	testl $28, %r13d
	jnz .Lbb2768
	movq -2104(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2775
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2767
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2766
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2766
	.loc 1 110
	leaq -2104(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	jmp .Lbb2775
.Lbb2766:
	movq %rax, -32(%rcx)
.Lbb2767:
	movq $0, -2104(%rbp)
	jmp .Lbb2775
.Lbb2768:
	movq -2104(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2775
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2774
	movq -24(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2773
	movq -32(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2773
	.loc 1 110
	leaq -2104(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_unloan
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	jmp .Lbb2775
.Lbb2773:
	movq %rax, -24(%rcx)
.Lbb2774:
	movq $0, -2104(%rbp)
.Lbb2775:
	movq -2112(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2782
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2781
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2780
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2780
	.loc 1 110
	leaq -2112(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	jmp .Lbb2782
.Lbb2780:
	movq %rax, -32(%rcx)
.Lbb2781:
	movq $0, -2112(%rbp)
.Lbb2782:
	movl -2336(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2790
	movl $0, -2336(%rbp)
	movq -2120(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2790
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2789
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2788
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2788
	.loc 1 110
	leaq -2120(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %rdx, -1240(%rbp)
	jmp .Lbb2790
.Lbb2788:
	movq %rax, -32(%rcx)
.Lbb2789:
	movq $0, -2120(%rbp)
.Lbb2790:
	movl $2, %eax
	jmp .Lbb2846
.Lbb2791:
	movq %rbx, %rdi
	.loc 1 60
	movl $320, %edx
	callq myl_qbe_fail_cast
	movq %rdx, -1240(%rbp)
	ud2
.Lbb2793:
	xchgq %rdi, %rbx
	movl -2184(%rbp), %eax
	movl -2152(%rbp), %ecx
	orl %ecx, %eax
	jz .Lbb2796
	leaq -2208(%rbp), %rax
	movq %rax, -2144(%rbp)
	leaq -2176(%rbp), %rax
	movq %rax, -2136(%rbp)
	.loc 1 9
	movl $2, %edx
	leaq -2144(%rbp), %rsi
	movq %rdi, %r12
	callq myl_qbe_rc_scopes_close
	movq %rdx, -1240(%rbp)
	movq %r12, %rdi
.Lbb2796:
	.loc 1 9
	callq myl_qbe_exit_skip
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	cmpl $0, %eax
	jnz .Lbb2845
	movl -2296(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2805
	movl $0, -2296(%rbp)
	movq -2024(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2805
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2804
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2803
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2803
	.loc 1 9
	leaq -2024(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_f020b39ff55316d6fc088b8f6fb23472a6c2a506141c6da48c67f451a7a6c56a_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	jmp .Lbb2805
.Lbb2803:
	movq %rax, -32(%rcx)
.Lbb2804:
	movq $0, -2024(%rbp)
.Lbb2805:
	movl -2304(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2813
	movl $0, -2304(%rbp)
	movq -2040(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2813
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2812
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2811
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2811
	.loc 1 9
	leaq -2040(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_8b7a491eab8031def57bec191111499572216f3521592d896389d1b509b65111_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	jmp .Lbb2813
.Lbb2811:
	movq %rax, -32(%rcx)
.Lbb2812:
	movq $0, -2040(%rbp)
.Lbb2813:
	movl -2312(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2821
	movl $0, -2312(%rbp)
	movq -2064(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2821
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2820
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2819
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2819
	.loc 1 9
	leaq -2064(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_9c418158b00420f461fdb922d52a07584437421adca396d7c839874586e1aea9_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	jmp .Lbb2821
.Lbb2819:
	movq %rax, -32(%rcx)
.Lbb2820:
	movq $0, -2064(%rbp)
.Lbb2821:
	movl -2320(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2829
	movl $0, -2320(%rbp)
	movq -2080(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2829
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2828
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2827
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2827
	.loc 1 9
	leaq -2080(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	jmp .Lbb2829
.Lbb2827:
	movq %rax, -32(%rcx)
.Lbb2828:
	movq $0, -2080(%rbp)
.Lbb2829:
	movl -2328(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2837
	movl $0, -2328(%rbp)
	movq -2096(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2837
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2836
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2835
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2835
	.loc 1 9
	leaq -2096(%rbp), %rsi
	movq %rdi, %rbx
	callq myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527_rcg_drop
	movq %rdx, -1240(%rbp)
	movq %rbx, %rdi
	jmp .Lbb2837
.Lbb2835:
	movq %rax, -32(%rcx)
.Lbb2836:
	movq $0, -2096(%rbp)
.Lbb2837:
	movl -2336(%rbp), %eax
	cmpl $0, %eax
	jz .Lbb2845
	movl $0, -2336(%rbp)
	movq -2120(%rbp), %rcx
	cmpq $0, %rcx
	jz .Lbb2845
	movq -16(%rcx), %rax
	movq $4611686018427387906, %rdx
	andq %rdx, %rax
	cmpq $0, %rax
	jnz .Lbb2844
	movq -32(%rcx), %rax
	subq $1, %rax
	jnz .Lbb2843
	movq -24(%rcx), %rdx
	cmpq $0, %rdx
	jnz .Lbb2843
	.loc 1 9
	leaq -2120(%rbp), %rsi
	callq myl_t_1fa64ff08badc7715febe33a527d577ee990f92c692f5fb9ca94bc8ae8b2241b_rcg_drop
	movq %rdx, -1240(%rbp)
	jmp .Lbb2845
.Lbb2843:
	movq %rax, -32(%rcx)
.Lbb2844:
	movq $0, -2120(%rbp)
.Lbb2845:
	movl $2, %eax
.Lbb2846:
	popq %r15
	popq %r14
	popq %r13
	popq %r12
	popq %rbx
	leave
	ret
.Lbb2847:
	movq %rbx, %rdi
	.loc 1 4
	movl $320, %edx
	callq myl_qbe_fail_cast
	movq %rdx, -1240(%rbp)
	ud2
.Lbb2849:
	movq %rbx, %rdi
	.loc 1 1 1
	callq myl_qbe_fail_frame
	movq %rdx, -1240(%rbp)
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
