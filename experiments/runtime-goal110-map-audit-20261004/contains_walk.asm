
/home/epentland/ai/canopy/mylang-worktrees/goal110-g4-rf-20261004/.mylang-cache/goal110-g4-rf/runner/bin/collections-my-llvm:     file format elf64-x86-64


Disassembly of section .text:

000000000105c850 <contains_walk>:
 105c850:	push   %rbp
 105c851:	mov    %rsp,%rbp
 105c854:	push   %r15
 105c856:	push   %r14
 105c858:	push   %rbx
 105c859:	push   %rax
 105c85a:	mov    %rdi,%rbx
 105c85d:	mov    0x24(%rdi),%r15d
 105c861:	cmp    $0x2,%r15d
 105c865:	je     105c877 <contains_walk+0x27>
 105c867:	cmp    $0x1,%r15d
 105c86b:	je     105c872 <contains_walk+0x22>
 105c86d:	test   %r15d,%r15d
 105c870:	jne    105c8a8 <contains_walk+0x58>
 105c872:	mov    (%rsi),%r14
 105c875:	jmp    105c8eb <contains_walk+0x9b>
 105c877:	mov    0x8(%rbx),%rax
 105c87b:	mov    (%rax),%rax
 105c87e:	movq   $0x0,-0x20(%rbp)
 105c886:	popcnt %rax,%rcx
 105c88b:	cmp    $0x1,%ecx
 105c88e:	jne    105c8cb <contains_walk+0x7b>
 105c890:	tzcnt  %rax,%rcx
 105c895:	cmp    $0x3,%rcx
 105c899:	ja     105c8cb <contains_walk+0x7b>
 105c89b:	jmp    *0x100b398(,%rcx,8)
 105c8a2:	movzbl (%rsi),%r14d
 105c8a6:	jmp    105c8eb <contains_walk+0x9b>
 105c8a8:	mov    %rbx,%rdi
 105c8ab:	call   105cae0 <probe_any>
 105c8b0:	mov    %rax,%rcx
 105c8b3:	movl   $0x0,0xf8(%rbx)
 105c8bd:	xor    %eax,%eax
 105c8bf:	cmp    $0xffffffffffffffff,%rcx
 105c8c3:	setne  %al
 105c8c6:	jmp    105ca85 <contains_walk+0x235>
 105c8cb:	cmp    $0x8,%rax
 105c8cf:	mov    $0x8,%edx
 105c8d4:	cmovb  %rax,%rdx
 105c8d8:	lea    -0x20(%rbp),%rdi
 105c8dc:	mov    %rsi,%r14
 105c8df:	call   10713b0 <memcpy@plt>
 105c8e4:	mov    %r14,%rsi
 105c8e7:	mov    -0x20(%rbp),%r14
 105c8eb:	cmpl   $0x2,0xf8(%rbx)
 105c8f2:	jne    105c903 <contains_walk+0xb3>
 105c8f4:	xor    %eax,%eax
 105c8f6:	cmp    0xe0(%rbx),%r14
 105c8fd:	je     105ca85 <contains_walk+0x235>
 105c903:	mov    0xd8(%rbx),%rdi
 105c90a:	test   %rdi,%rdi
 105c90d:	je     105c984 <contains_walk+0x134>
 105c90f:	cmp    $0x1,%r15d
 105c913:	je     105c9d3 <contains_walk+0x183>
 105c919:	test   %r15d,%r15d
 105c91c:	jne    105ca5f <contains_walk+0x20f>
 105c922:	mov    (%rsi),%rsi
 105c925:	mov    %rbx,%rdi
 105c928:	call   105cc00 <probe_text>
 105c92d:	cmp    $0xffffffffffffffff,%rax
 105c931:	jne    105c992 <contains_walk+0x142>
 105c933:	cmpl   $0x0,0x24(%rbx)
 105c937:	je     105ca79 <contains_walk+0x229>
 105c93d:	mov    %edx,%eax
 105c93f:	cmp    $0xffffffff,%eax
 105c942:	je     105ca79 <contains_walk+0x229>
 105c948:	mov    %r14,0xe0(%rbx)
 105c94f:	movq   $0x0,0xe8(%rbx)
 105c95a:	mov    %rdx,0xf0(%rbx)
 105c961:	movl   $0x2,0xf8(%rbx)
 105c96b:	vxorps %xmm0,%xmm0,%xmm0
 105c96f:	vmovups %xmm0,0xfc(%rbx)
 105c977:	vmovups %xmm0,0x108(%rbx)
 105c97f:	jmp    105ca83 <contains_walk+0x233>
 105c984:	mov    %rbx,%rdi
 105c987:	call   105cae0 <probe_any>
 105c98c:	cmp    $0xffffffffffffffff,%rax
 105c990:	je     105c933 <contains_walk+0xe3>
 105c992:	mov    %r14,0xe0(%rbx)
 105c999:	mov    %rax,0xe8(%rbx)
 105c9a0:	movq   $0x0,0xf0(%rbx)
 105c9ab:	movl   $0x1,0xf8(%rbx)
 105c9b5:	vxorps %xmm0,%xmm0,%xmm0
 105c9b9:	vmovups %xmm0,0xfc(%rbx)
 105c9c1:	vmovups %xmm0,0x108(%rbx)
 105c9c9:	mov    $0x1,%eax
 105c9ce:	jmp    105ca85 <contains_walk+0x235>
 105c9d3:	movabs $0x9e3779b97f4a7c15,%rdx
 105c9dd:	xor    %r14,%rdx
 105c9e0:	movabs $0xbf58476d1ce4e5b9,%rax
 105c9ea:	mulx   %rax,%rax,%rcx
 105c9ef:	xor    %rax,%rcx
 105c9f2:	mov    %rcx,%rdx
 105c9f5:	shr    $0x20,%rdx
 105c9f9:	xor    %rcx,%rdx
 105c9fc:	mov    0xd0(%rbx),%rsi
 105ca03:	dec    %rdi
 105ca06:	mov    %edi,%ecx
 105ca08:	and    %edx,%ecx
 105ca0a:	mov    (%rsi,%rcx,8),%rax
 105ca0e:	test   %rax,%rax
 105ca11:	je     105caaf <contains_walk+0x25f>
 105ca17:	mov    (%rbx),%r9
 105ca1a:	mov    0x30(%rbx),%r8
 105ca1e:	mov    0x20(%r9),%r9
 105ca22:	jmp    105ca3f <contains_walk+0x1ef>
 105ca24:	data16 data16 cs nopw 0x0(%rax,%rax,1)
 105ca30:	inc    %rcx
 105ca33:	and    %rdi,%rcx
 105ca36:	mov    (%rsi,%rcx,8),%rax
 105ca3a:	test   %rax,%rax
 105ca3d:	je     105ca90 <contains_walk+0x240>
 105ca3f:	mov    %rax,%r10
 105ca42:	shr    $0x20,%r10
 105ca46:	cmp    %r10d,%edx
 105ca49:	jne    105ca30 <contains_walk+0x1e0>
 105ca4b:	mov    %eax,%eax
 105ca4d:	dec    %rax
 105ca50:	mov    %rax,%r10
 105ca53:	imul   %r8,%r10
 105ca57:	cmp    %r14,(%r9,%r10,1)
 105ca5b:	jne    105ca30 <contains_walk+0x1e0>
 105ca5d:	jmp    105ca97 <contains_walk+0x247>
 105ca5f:	mov    %rbx,%rdi
 105ca62:	mov    %r14,%rsi
 105ca65:	call   105cda0 <probe_scalar>
 105ca6a:	cmp    $0xffffffffffffffff,%rax
 105ca6e:	jne    105c992 <contains_walk+0x142>
 105ca74:	jmp    105c933 <contains_walk+0xe3>
 105ca79:	movl   $0x0,0xf8(%rbx)
 105ca83:	xor    %eax,%eax
 105ca85:	add    $0x8,%rsp
 105ca89:	pop    %rbx
 105ca8a:	pop    %r14
 105ca8c:	pop    %r15
 105ca8e:	pop    %rbp
 105ca8f:	ret
 105ca90:	mov    $0xffffffffffffffff,%rax
 105ca97:	mov    %ecx,%ecx
 105ca99:	shl    $0x20,%rdx
 105ca9d:	or     %rcx,%rdx
 105caa0:	cmp    $0xffffffffffffffff,%rax
 105caa4:	jne    105c992 <contains_walk+0x142>
 105caaa:	jmp    105c933 <contains_walk+0xe3>
 105caaf:	mov    $0xffffffffffffffff,%rax
 105cab6:	shl    $0x20,%rdx
 105caba:	or     %rcx,%rdx
 105cabd:	cmp    $0xffffffffffffffff,%rax
 105cac1:	jne    105c992 <contains_walk+0x142>
 105cac7:	jmp    105c933 <contains_walk+0xe3>
 105cacc:	mov    (%rsi),%r14d
 105cacf:	jmp    105c8eb <contains_walk+0x9b>
 105cad4:	movzwl (%rsi),%r14d
 105cad8:	jmp    105c8eb <contains_walk+0x9b>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
