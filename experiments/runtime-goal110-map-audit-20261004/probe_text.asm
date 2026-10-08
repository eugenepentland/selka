
/home/epentland/ai/canopy/mylang-worktrees/goal110-g4-rf-20261004/.mylang-cache/goal110-g4-rf/runner/bin/collections-my-llvm:     file format elf64-x86-64


Disassembly of section .text:

000000000105cc00 <probe_text>:
 105cc00:	push   %rbp
 105cc01:	mov    %rsp,%rbp
 105cc04:	push   %r15
 105cc06:	push   %r14
 105cc08:	push   %r13
 105cc0a:	push   %r12
 105cc0c:	push   %rbx
 105cc0d:	push   %rax
 105cc0e:	mov    %rsi,%rbx
 105cc11:	mov    %rdi,%r14
 105cc14:	mov    0x10(%rsi),%ecx
 105cc17:	test   $0x2,%cl
 105cc1a:	jne    105cc3d <probe_text+0x3d>
 105cc1c:	mov    %rbx,%rdi
 105cc1f:	call   10598b0 <myl_native_text_hash>
 105cc24:	mov    0x10(%rbx),%ecx
 105cc27:	test   $0x4,%cl
 105cc2a:	je     105cc45 <probe_text+0x45>
 105cc2c:	mov    0x18(%rbx),%rcx
 105cc30:	mov    0x14(%rbx),%edx
 105cc33:	lea    (%rcx,%rdx,1),%rdi
 105cc37:	add    $0x18,%rdi
 105cc3b:	jmp    105cc49 <probe_text+0x49>
 105cc3d:	mov    0x14(%rbx),%eax
 105cc40:	test   $0x4,%cl
 105cc43:	jne    105cc2c <probe_text+0x2c>
 105cc45:	lea    0x18(%rbx),%rdi
 105cc49:	mov    0xd0(%r14),%r8
 105cc50:	mov    0xd8(%r14),%r9
 105cc57:	dec    %r9
 105cc5a:	mov    %eax,%ecx
 105cc5c:	mov    %r9d,%edx
 105cc5f:	and    %eax,%edx
 105cc61:	mov    (%r8,%rdx,8),%r15
 105cc65:	mov    $0xffffffffffffffff,%rsi
 105cc6c:	test   %r15,%r15
 105cc6f:	je     105cd77 <probe_text+0x177>
 105cc75:	mov    %rcx,-0x30(%rbp)
 105cc79:	mov    (%r14),%rcx
 105cc7c:	mov    0x30(%r14),%r10
 105cc80:	mov    0x20(%rcx),%r11
 105cc84:	jmp    105ccb3 <probe_text+0xb3>
 105cc86:	mov    0x10(%r15,%r12,1),%rcx
 105cc8b:	cmp    -0x8(%rdi,%r12,1),%rcx
 105cc90:	je     105cd63 <probe_text+0x163>
 105cc96:	cs nopw 0x0(%rax,%rax,1)
 105cca0:	inc    %rdx
 105cca3:	and    %r9,%rdx
 105cca6:	mov    (%r8,%rdx,8),%r15
 105ccaa:	test   %r15,%r15
 105ccad:	je     105cd6c <probe_text+0x16c>
 105ccb3:	mov    %r15,%rcx
 105ccb6:	shr    $0x20,%rcx
 105ccba:	cmp    %ecx,%eax
 105ccbc:	jne    105cca0 <probe_text+0xa0>
 105ccbe:	mov    %r15d,%r14d
 105ccc1:	dec    %r14
 105ccc4:	mov    %r14,%rcx
 105ccc7:	imul   %r10,%rcx
 105cccb:	mov    (%r11,%rcx,1),%r15
 105cccf:	cmp    %rbx,%r15
 105ccd2:	je     105cd63 <probe_text+0x163>
 105ccd8:	mov    0x8(%r15),%r12
 105ccdc:	cmp    0x8(%rbx),%r12
 105cce0:	jne    105cca0 <probe_text+0xa0>
 105cce2:	cmp    $0x8,%r12
 105cce6:	jb     105cd09 <probe_text+0x109>
 105cce8:	xor    %r13d,%r13d
 105cceb:	nopl   0x0(%rax,%rax,1)
 105ccf0:	lea    0x8(%r13),%rcx
 105ccf4:	cmp    %r12,%rcx
 105ccf7:	jae    105cc86 <probe_text+0x86>
 105ccf9:	mov    0x18(%r15,%r13,1),%rsi
 105ccfe:	cmp    (%rdi,%r13,1),%rsi
 105cd02:	mov    %rcx,%r13
 105cd05:	je     105ccf0 <probe_text+0xf0>
 105cd07:	jmp    105cca0 <probe_text+0xa0>
 105cd09:	cmp    $0x3,%r12
 105cd0d:	jbe    105cd29 <probe_text+0x129>
 105cd0f:	mov    0x18(%r15),%ecx
 105cd13:	cmp    (%rdi),%ecx
 105cd15:	jne    105cca0 <probe_text+0xa0>
 105cd17:	mov    -0x4(%rdi,%r12,1),%ecx
 105cd1c:	cmp    %ecx,0x14(%r15,%r12,1)
 105cd21:	jne    105cca0 <probe_text+0xa0>
 105cd27:	jmp    105cd63 <probe_text+0x163>
 105cd29:	test   %r12,%r12
 105cd2c:	je     105cd63 <probe_text+0x163>
 105cd2e:	movzbl 0x18(%r15),%ecx
 105cd33:	cmp    (%rdi),%cl
 105cd35:	jne    105cca0 <probe_text+0xa0>
 105cd3b:	cmp    $0x1,%r12
 105cd3f:	je     105cd63 <probe_text+0x163>
 105cd41:	movzbl 0x19(%r15),%ecx
 105cd46:	cmp    0x1(%rdi),%cl
 105cd49:	jne    105cca0 <probe_text+0xa0>
 105cd4f:	cmp    $0x2,%r12
 105cd53:	je     105cd63 <probe_text+0x163>
 105cd55:	movzbl 0x1a(%r15),%ecx
 105cd5a:	cmp    0x2(%rdi),%cl
 105cd5d:	jne    105cca0 <probe_text+0xa0>
 105cd63:	mov    %r14,%rsi
 105cd66:	mov    -0x30(%rbp),%rcx
 105cd6a:	jmp    105cd77 <probe_text+0x177>
 105cd6c:	mov    -0x30(%rbp),%rcx
 105cd70:	mov    $0xffffffffffffffff,%rsi
 105cd77:	shl    $0x20,%rcx
 105cd7b:	mov    %edx,%edx
 105cd7d:	or     %rcx,%rdx
 105cd80:	mov    %rsi,%rax
 105cd83:	add    $0x8,%rsp
 105cd87:	pop    %rbx
 105cd88:	pop    %r12
 105cd8a:	pop    %r13
 105cd8c:	pop    %r14
 105cd8e:	pop    %r15
 105cd90:	pop    %rbp
 105cd91:	ret

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
