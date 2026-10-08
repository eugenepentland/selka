0000000001005f10 <myl_f_3b325109deb02ebf8150c4cc76e908d55f977082fe74bfd455e298770351b77d>:
 1005f10:	endbr64
 1005f14:	push   %rbp
 1005f15:	mov    %rsp,%rbp
 1005f18:	mov    %rdx,%rcx
 1005f1b:	mov    %rsi,%rdx
 1005f1e:	cmp    $0x0,%rcx
 1005f22:	je     1005f9d <myl_f_3b325109deb02ebf8150c4cc76e908d55f977082fe74bfd455e298770351b77d+0x8d>
 1005f24:	movabs $0x8000000000000000,%rax
 1005f2e:	cmp    %rax,%rdx
 1005f31:	sete   %al
 1005f34:	movzbq %al,%rax
 1005f38:	cmp    $0xffffffffffffffff,%rcx
 1005f3c:	mov    %rcx,%rsi
 1005f3f:	sete   %cl
 1005f42:	movzbq %cl,%rcx
 1005f46:	test   %rax,%rcx
 1005f49:	jne    1005f88 <myl_f_3b325109deb02ebf8150c4cc76e908d55f977082fe74bfd455e298770351b77d+0x78>
 1005f4b:	mov    %rdx,%rax
 1005f4e:	mov    %rdx,%rdi
 1005f51:	cqto
 1005f53:	idiv   %rsi
 1005f56:	mov    %rdi,%rdx
 1005f59:	mov    %rax,%rcx
 1005f5c:	mov    %rdx,%rax
 1005f5f:	cqto
 1005f61:	idiv   %rsi
 1005f64:	cmp    $0x0,%rdx
 1005f68:	setne  %al
 1005f6b:	movzbq %al,%rax
 1005f6f:	xor    %rsi,%rdx
 1005f72:	cmp    $0x0,%rdx
 1005f76:	setl   %dl
 1005f79:	movzbq %dl,%rdx
 1005f7d:	and    %rdx,%rax
 1005f80:	neg    %rax
 1005f83:	add    %rcx,%rax
 1005f86:	leave
 1005f87:	ret
 1005f88:	mov    %rsi,%rcx
 1005f8b:	mov    $0x40,%r8d
 1005f91:	mov    $0x5,%esi
 1005f96:	call   1006660 <myl_qbe_fail_overflow_op>
 1005f9b:	ud2
 1005f9d:	mov    $0x0,%ecx
 1005fa2:	mov    $0x5,%esi
 1005fa7:	call   1006520 <myl_qbe_fail_division>
 1005fac:	ud2
 1005fae:	int3
 1005faf:	int3

