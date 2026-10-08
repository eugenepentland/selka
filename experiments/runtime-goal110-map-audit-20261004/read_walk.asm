
/home/epentland/ai/canopy/mylang-worktrees/goal110-g4-rf-20261004/.mylang-cache/goal110-g4-rf/runner/bin/collections-my-llvm:     file format elf64-x86-64


Disassembly of section .text:

000000000105d710 <read_walk>:
 105d710:	push   %rbp
 105d711:	mov    %rsp,%rbp
 105d714:	push   %r15
 105d716:	push   %r14
 105d718:	push   %r12
 105d71a:	push   %rbx
 105d71b:	sub    $0x10,%rsp
 105d71f:	mov    %rdx,%r14
 105d722:	mov    %rdi,%rbx
 105d725:	mov    0x24(%rdi),%r12d
 105d729:	cmp    $0x2,%r12d
 105d72d:	je     105d73f <read_walk+0x2f>
 105d72f:	cmp    $0x1,%r12d
 105d733:	je     105d73a <read_walk+0x2a>
 105d735:	test   %r12d,%r12d
 105d738:	jne    105d770 <read_walk+0x60>
 105d73a:	mov    (%rsi),%r15
 105d73d:	jmp    105d7ae <read_walk+0x9e>
 105d73f:	mov    0x8(%rbx),%rax
 105d743:	mov    (%rax),%rax
 105d746:	movq   $0x0,-0x28(%rbp)
 105d74e:	popcnt %rax,%rcx
 105d753:	cmp    $0x1,%ecx
 105d756:	jne    105d78e <read_walk+0x7e>
 105d758:	tzcnt  %rax,%rcx
 105d75d:	cmp    $0x3,%rcx
 105d761:	ja     105d78e <read_walk+0x7e>
 105d763:	jmp    *0x100b438(,%rcx,8)
 105d76a:	movzbl (%rsi),%r15d
 105d76e:	jmp    105d7ae <read_walk+0x9e>
 105d770:	mov    %rbx,%rdi
 105d773:	call   105cae0 <probe_any>
 105d778:	movl   $0x0,0xf8(%rbx)
 105d782:	cmp    $0xffffffffffffffff,%rax
 105d786:	jne    105d88c <read_walk+0x17c>
 105d78c:	jmp    105d7c0 <read_walk+0xb0>
 105d78e:	cmp    $0x8,%rax
 105d792:	mov    $0x8,%edx
 105d797:	cmovb  %rax,%rdx
 105d79b:	lea    -0x28(%rbp),%rdi
 105d79f:	mov    %rsi,%r15
 105d7a2:	call   10713b0 <memcpy@plt>
 105d7a7:	mov    %r15,%rsi
 105d7aa:	mov    -0x28(%rbp),%r15
 105d7ae:	cmpl   $0x2,0xf8(%rbx)
 105d7b5:	jne    105d7c7 <read_walk+0xb7>
 105d7b7:	cmp    0xe0(%rbx),%r15
 105d7be:	jne    105d7c7 <read_walk+0xb7>
 105d7c0:	xor    %eax,%eax
 105d7c2:	jmp    105d8c1 <read_walk+0x1b1>
 105d7c7:	mov    0xd8(%rbx),%rdi
 105d7ce:	test   %rdi,%rdi
 105d7d1:	je     105d847 <read_walk+0x137>
 105d7d3:	cmp    $0x1,%r12d
 105d7d7:	je     105d8ce <read_walk+0x1be>
 105d7dd:	test   %r12d,%r12d
 105d7e0:	jne    105d94f <read_walk+0x23f>
 105d7e6:	mov    (%rsi),%rsi
 105d7e9:	mov    %rbx,%rdi
 105d7ec:	call   105cc00 <probe_text>
 105d7f1:	cmp    $0xffffffffffffffff,%rax
 105d7f5:	jne    105d855 <read_walk+0x145>
 105d7f7:	cmpl   $0x0,0x24(%rbx)
 105d7fb:	je     105d969 <read_walk+0x259>
 105d801:	mov    %edx,%eax
 105d803:	cmp    $0xffffffff,%eax
 105d806:	je     105d969 <read_walk+0x259>
 105d80c:	mov    %r15,0xe0(%rbx)
 105d813:	movq   $0x0,0xe8(%rbx)
 105d81e:	mov    %rdx,0xf0(%rbx)
 105d825:	movl   $0x2,0xf8(%rbx)
 105d82f:	vxorps %xmm0,%xmm0,%xmm0
 105d833:	vmovups %xmm0,0xfc(%rbx)
 105d83b:	vmovups %xmm0,0x108(%rbx)
 105d843:	xor    %eax,%eax
 105d845:	jmp    105d8c1 <read_walk+0x1b1>
 105d847:	mov    %rbx,%rdi
 105d84a:	call   105cae0 <probe_any>
 105d84f:	cmp    $0xffffffffffffffff,%rax
 105d853:	je     105d7f7 <read_walk+0xe7>
 105d855:	mov    %r15,0xe0(%rbx)
 105d85c:	mov    %rax,0xe8(%rbx)
 105d863:	movq   $0x0,0xf0(%rbx)
 105d86e:	movl   $0x1,0xf8(%rbx)
 105d878:	vxorps %xmm0,%xmm0,%xmm0
 105d87c:	vmovups %xmm0,0xfc(%rbx)
 105d884:	vmovups %xmm0,0x108(%rbx)
 105d88c:	imul   0x30(%rbx),%rax
 105d891:	mov    (%rbx),%rcx
 105d894:	add    0x20(%rcx),%rax
 105d898:	mov    0x10(%rbx),%rcx
 105d89c:	add    0x18(%rbx),%rax
 105d8a0:	mov    (%rcx),%rdx
 105d8a3:	cmp    $0x8,%rdx
 105d8a7:	jne    105d8b1 <read_walk+0x1a1>
 105d8a9:	mov    (%rax),%rax
 105d8ac:	mov    %rax,(%r14)
 105d8af:	jmp    105d8bc <read_walk+0x1ac>
 105d8b1:	mov    %r14,%rdi
 105d8b4:	mov    %rax,%rsi
 105d8b7:	call   10713e0 <memmove@plt>
 105d8bc:	mov    $0x1,%eax
 105d8c1:	add    $0x10,%rsp
 105d8c5:	pop    %rbx
 105d8c6:	pop    %r12
 105d8c8:	pop    %r14
 105d8ca:	pop    %r15
 105d8cc:	pop    %rbp
 105d8cd:	ret
 105d8ce:	movabs $0x9e3779b97f4a7c15,%rdx
 105d8d8:	xor    %r15,%rdx
 105d8db:	movabs $0xbf58476d1ce4e5b9,%rax
 105d8e5:	mulx   %rax,%rax,%rcx
 105d8ea:	xor    %rax,%rcx
 105d8ed:	mov    %rcx,%rdx
 105d8f0:	shr    $0x20,%rdx
 105d8f4:	xor    %rcx,%rdx
 105d8f7:	mov    0xd0(%rbx),%rsi
 105d8fe:	dec    %rdi
 105d901:	mov    %edi,%ecx
 105d903:	and    %edx,%ecx
 105d905:	mov    (%rsi,%rcx,8),%rax
 105d909:	test   %rax,%rax
 105d90c:	je     105d999 <read_walk+0x289>
 105d912:	mov    (%rbx),%r9
 105d915:	mov    0x30(%rbx),%r8
 105d919:	mov    0x20(%r9),%r9
 105d91d:	jmp    105d92f <read_walk+0x21f>
 105d91f:	nop
 105d920:	inc    %rcx
 105d923:	and    %rdi,%rcx
 105d926:	mov    (%rsi,%rcx,8),%rax
 105d92a:	test   %rax,%rax
 105d92d:	je     105d97a <read_walk+0x26a>
 105d92f:	mov    %rax,%r10
 105d932:	shr    $0x20,%r10
 105d936:	cmp    %r10d,%edx
 105d939:	jne    105d920 <read_walk+0x210>
 105d93b:	mov    %eax,%eax
 105d93d:	dec    %rax
 105d940:	mov    %rax,%r10
 105d943:	imul   %r8,%r10
 105d947:	cmp    %r15,(%r9,%r10,1)
 105d94b:	jne    105d920 <read_walk+0x210>
 105d94d:	jmp    105d981 <read_walk+0x271>
 105d94f:	mov    %rbx,%rdi
 105d952:	mov    %r15,%rsi
 105d955:	call   105cda0 <probe_scalar>
 105d95a:	cmp    $0xffffffffffffffff,%rax
 105d95e:	jne    105d855 <read_walk+0x145>
 105d964:	jmp    105d7f7 <read_walk+0xe7>
 105d969:	movl   $0x0,0xf8(%rbx)
 105d973:	xor    %eax,%eax
 105d975:	jmp    105d8c1 <read_walk+0x1b1>
 105d97a:	mov    $0xffffffffffffffff,%rax
 105d981:	mov    %ecx,%ecx
 105d983:	shl    $0x20,%rdx
 105d987:	or     %rcx,%rdx
 105d98a:	cmp    $0xffffffffffffffff,%rax
 105d98e:	jne    105d855 <read_walk+0x145>
 105d994:	jmp    105d7f7 <read_walk+0xe7>
 105d999:	mov    $0xffffffffffffffff,%rax
 105d9a0:	shl    $0x20,%rdx
 105d9a4:	or     %rcx,%rdx
 105d9a7:	cmp    $0xffffffffffffffff,%rax
 105d9ab:	jne    105d855 <read_walk+0x145>
 105d9b1:	jmp    105d7f7 <read_walk+0xe7>
 105d9b6:	mov    (%rsi),%r15d
 105d9b9:	jmp    105d7ae <read_walk+0x9e>
 105d9be:	movzwl (%rsi),%r15d
 105d9c2:	jmp    105d7ae <read_walk+0x9e>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
