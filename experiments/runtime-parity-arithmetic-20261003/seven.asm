0000000001005fb0 <myl_f_3ba8d02b16fd2a01c1a8ba1a1f036d7ce386ed953696fa57331c2ac48a80b255>:
 1005fb0:	endbr64
 1005fb4:	mov    %rsi,%rcx
 1005fb7:	sar    $0x3f,%rcx
 1005fbb:	mov    %rsi,%rax
 1005fbe:	xor    %rcx,%rax
 1005fc1:	mov    %rax,%rdi
 1005fc4:	sub    %rcx,%rdi
 1005fc7:	movabs $0x2492492492492493,%r8
 1005fd1:	mov    %rdi,%rax
 1005fd4:	mul    %r8
 1005fd7:	mov    %rdx,%rax
 1005fda:	mov    %rdi,%rdx
 1005fdd:	sub    %rax,%rdx
 1005fe0:	shr    $1,%rdx
 1005fe3:	add    %rdx,%rax
 1005fe6:	shr    $0x2,%rax
 1005fea:	xor    %rcx,%rax
 1005fed:	sub    %rcx,%rax
 1005ff0:	imul   $0x7,%rax,%rdx
 1005ff4:	neg    %rdx
 1005ff7:	add    %rsi,%rdx
 1005ffa:	cmp    $0x0,%rdx
 1005ffe:	setne  %dl
 1006001:	movzbq %dl,%rdx
 1006005:	and    %rdx,%rcx
 1006008:	sub    %rcx,%rax
 100600b:	ret
 100600c:	int3
 100600d:	int3
 100600e:	int3
 100600f:	int3

