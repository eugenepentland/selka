
.tmp-lox-table-read-20261003/bin/direct-entries-qbe:     file format elf64-x86-64


Disassembly of section .text:

000000000111b9a0 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f>:
 111b9a0:	f3 0f 1e fa          	endbr64
 111b9a4:	55                   	push   %rbp
 111b9a5:	48 89 e5             	mov    %rsp,%rbp
 111b9a8:	48 83 ec 48          	sub    $0x48,%rsp
 111b9ac:	53                   	push   %rbx
 111b9ad:	48 89 f8             	mov    %rdi,%rax
 111b9b0:	48 89 f7             	mov    %rsi,%rdi
 111b9b3:	48 83 f9 00          	cmp    $0x0,%rcx
 111b9b7:	0f 84 89 02 00 00    	je     111bc46 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x2a6>
 111b9bd:	48 8b 32             	mov    (%rdx),%rsi
 111b9c0:	48 b9 ff ff ff ff ff 	movabs $0x7fffffffffffffff,%rcx
 111b9c7:	ff ff 7f 
 111b9ca:	48 39 ce             	cmp    %rcx,%rsi
 111b9cd:	0f 87 67 02 00 00    	ja     111bc3a <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x29a>
 111b9d3:	48 b9 01 00 00 00 00 	movabs $0x8000000000000001,%rcx
 111b9da:	00 00 80 
 111b9dd:	48 39 ce             	cmp    %rcx,%rsi
 111b9e0:	0f 8c 3a 02 00 00    	jl     111bc20 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x280>
 111b9e6:	48 89 f1             	mov    %rsi,%rcx
 111b9e9:	48 83 e9 01          	sub    $0x1,%rcx
 111b9ed:	48 83 f9 00          	cmp    $0x0,%rcx
 111b9f1:	41 0f 9c c2          	setl   %r10b
 111b9f5:	4d 0f b6 d2          	movzbq %r10b,%r10
 111b9f9:	41 bb ff ff ff ff    	mov    $0xffffffff,%r11d
 111b9ff:	4c 39 d9             	cmp    %r11,%rcx
 111ba02:	41 0f 9f c3          	setg   %r11b
 111ba06:	4d 0f b6 db          	movzbq %r11b,%r11
 111ba0a:	4d 09 da             	or     %r11,%r10
 111ba0d:	0f 85 fe 01 00 00    	jne    111bc11 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x271>
 111ba13:	49 21 c9             	and    %rcx,%r9
 111ba16:	49 c1 e1 20          	shl    $0x20,%r9
 111ba1a:	49 c1 e9 20          	shr    $0x20,%r9
 111ba1e:	48 87 f7             	xchg   %rsi,%rdi
 111ba21:	48 97                	xchg   %rax,%rdi
 111ba23:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 111ba2a:	00 00 00 
 111ba2d:	0f 1f 00             	nopl   (%rax)
 111ba30:	49 39 c1             	cmp    %rax,%r9
 111ba33:	0f 82 93 00 00 00    	jb     111bacc <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x12c>
 111ba39:	49 83 f9 00          	cmp    $0x0,%r9
 111ba3d:	7c 05                	jl     111ba44 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0xa4>
 111ba3f:	4d 89 cb             	mov    %r9,%r11
 111ba42:	eb 2d                	jmp    111ba71 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0xd1>
 111ba44:	49 ba ff ff ff ff ff 	movabs $0x7fffffffffffffff,%r10
 111ba4b:	ff ff 7f 
 111ba4e:	4c 39 d0             	cmp    %r10,%rax
 111ba51:	77 64                	ja     111bab7 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x117>
 111ba53:	4d 89 ca             	mov    %r9,%r10
 111ba56:	49 01 c2             	add    %rax,%r10
 111ba59:	4d 89 d3             	mov    %r10,%r11
 111ba5c:	49 31 c3             	xor    %rax,%r11
 111ba5f:	4c 89 d3             	mov    %r10,%rbx
 111ba62:	4c 31 cb             	xor    %r9,%rbx
 111ba65:	49 21 db             	and    %rbx,%r11
 111ba68:	49 83 fb 00          	cmp    $0x0,%r11
 111ba6c:	7c 28                	jl     111ba96 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0xf6>
 111ba6e:	4d 89 d3             	mov    %r10,%r11
 111ba71:	4c 8b 12             	mov    (%rdx),%r10
 111ba74:	4d 39 d3             	cmp    %r10,%r11
 111ba77:	73 0d                	jae    111ba86 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0xe6>
 111ba79:	4c 8b 52 20          	mov    0x20(%rdx),%r10
 111ba7d:	4d 6b db 20          	imul   $0x20,%r11,%r11
 111ba81:	4d 01 da             	add    %r11,%r10
 111ba84:	eb 51                	jmp    111bad7 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x137>
 111ba86:	4c 89 d2             	mov    %r10,%rdx
 111ba89:	48 89 f7             	mov    %rsi,%rdi
 111ba8c:	4c 89 de             	mov    %r11,%rsi
 111ba8f:	e8 2c f6 03 00       	call   115b0c0 <myl_qbe_fail_normalized_index_bounds>
 111ba94:	0f 0b                	ud2
 111ba96:	4c 89 ca             	mov    %r9,%rdx
 111ba99:	48 89 f7             	mov    %rsi,%rdi
 111ba9c:	48 89 c6             	mov    %rax,%rsi
 111ba9f:	41 b8 40 00 00 00    	mov    $0x40,%r8d
 111baa5:	48 89 d1             	mov    %rdx,%rcx
 111baa8:	48 89 f2             	mov    %rsi,%rdx
 111baab:	be 00 00 00 00       	mov    $0x0,%esi
 111bab0:	e8 1b f8 03 00       	call   115b2d0 <myl_qbe_fail_overflow_op>
 111bab5:	0f 0b                	ud2
 111bab7:	48 89 f7             	mov    %rsi,%rdi
 111baba:	48 89 c6             	mov    %rax,%rsi
 111babd:	ba 40 01 00 00       	mov    $0x140,%edx
 111bac2:	48 89 f0             	mov    %rsi,%rax
 111bac5:	e8 46 f9 03 00       	call   115b410 <myl_qbe_fail_cast>
 111baca:	0f 0b                	ud2
 111bacc:	4c 8b 52 20          	mov    0x20(%rdx),%r10
 111bad0:	4d 6b d9 20          	imul   $0x20,%r9,%r11
 111bad4:	4d 01 da             	add    %r11,%r10
 111bad7:	4d 8b 1a             	mov    (%r10),%r11
 111bada:	49 83 fb ff          	cmp    $0xffffffffffffffff,%r11
 111bade:	74 42                	je     111bb22 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x182>
 111bae0:	4d 39 d8             	cmp    %r11,%r8
 111bae3:	0f 85 cd 00 00 00    	jne    111bbb6 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x216>
 111bae9:	48 89 f8             	mov    %rdi,%rax
 111baec:	c7 45 e0 01 00 00 00 	movl   $0x1,-0x20(%rbp)
 111baf3:	49 8b 4a 10          	mov    0x10(%r10),%rcx
 111baf7:	48 89 4d e8          	mov    %rcx,-0x18(%rbp)
 111bafb:	49 8b 4a 18          	mov    0x18(%r10),%rcx
 111baff:	48 89 4d f0          	mov    %rcx,-0x10(%rbp)
 111bb03:	48 8b 4d e0          	mov    -0x20(%rbp),%rcx
 111bb07:	48 89 08             	mov    %rcx,(%rax)
 111bb0a:	48 8b 4d e8          	mov    -0x18(%rbp),%rcx
 111bb0e:	48 89 48 08          	mov    %rcx,0x8(%rax)
 111bb12:	48 8b 4d f0          	mov    -0x10(%rbp),%rcx
 111bb16:	48 89 48 10          	mov    %rcx,0x10(%rax)
 111bb1a:	48 89 c3             	mov    %rax,%rbx
 111bb1d:	e9 42 01 00 00       	jmp    111bc64 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x2c4>
 111bb22:	4d 8b 1a             	mov    (%r10),%r11
 111bb25:	4c 89 5d e0          	mov    %r11,-0x20(%rbp)
 111bb29:	4d 8b 5a 08          	mov    0x8(%r10),%r11
 111bb2d:	4c 89 5d e8          	mov    %r11,-0x18(%rbp)
 111bb31:	4d 8b 5a 10          	mov    0x10(%r10),%r11
 111bb35:	4c 89 5d f0          	mov    %r11,-0x10(%rbp)
 111bb39:	4d 8b 52 18          	mov    0x18(%r10),%r10
 111bb3d:	4c 89 55 f8          	mov    %r10,-0x8(%rbp)
 111bb41:	44 8b 55 f0          	mov    -0x10(%rbp),%r10d
 111bb45:	49 83 fa 00          	cmp    $0x0,%r10
 111bb49:	74 5f                	je     111bbaa <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x20a>
 111bb4b:	49 83 fa 01          	cmp    $0x1,%r10
 111bb4f:	74 51                	je     111bba2 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x202>
 111bb51:	49 83 fa 02          	cmp    $0x2,%r10
 111bb55:	74 43                	je     111bb9a <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x1fa>
 111bb57:	49 83 fa 03          	cmp    $0x3,%r10
 111bb5b:	75 08                	jne    111bb65 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x1c5>
 111bb5d:	41 ba 01 00 00 00    	mov    $0x1,%r10d
 111bb63:	eb 4b                	jmp    111bbb0 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x210>
 111bb65:	48 89 fb             	mov    %rdi,%rbx
 111bb68:	ba 18 00 00 00       	mov    $0x18,%edx
 111bb6d:	be 00 00 00 00       	mov    $0x0,%esi
 111bb72:	48 8d 7d c8          	lea    -0x38(%rbp),%rdi
 111bb76:	e8 f5 bc 05 00       	call   1177870 <compiler_rt.fastMemset>
 111bb7b:	48 89 d8             	mov    %rbx,%rax
 111bb7e:	48 8b 4d c8          	mov    -0x38(%rbp),%rcx
 111bb82:	48 89 08             	mov    %rcx,(%rax)
 111bb85:	48 8b 4d d0          	mov    -0x30(%rbp),%rcx
 111bb89:	48 89 48 08          	mov    %rcx,0x8(%rax)
 111bb8d:	48 8b 4d d8          	mov    -0x28(%rbp),%rcx
 111bb91:	48 89 48 10          	mov    %rcx,0x10(%rax)
 111bb95:	e9 ca 00 00 00       	jmp    111bc64 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x2c4>
 111bb9a:	41 ba 01 00 00 00    	mov    $0x1,%r10d
 111bba0:	eb 0e                	jmp    111bbb0 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x210>
 111bba2:	41 ba 01 00 00 00    	mov    $0x1,%r10d
 111bba8:	eb 06                	jmp    111bbb0 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x210>
 111bbaa:	41 ba 00 00 00 00    	mov    $0x0,%r10d
 111bbb0:	49 83 f2 01          	xor    $0x1,%r10
 111bbb4:	75 38                	jne    111bbee <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x24e>
 111bbb6:	49 ba fe ff ff ff ff 	movabs $0x7ffffffffffffffe,%r10
 111bbbd:	ff ff 7f 
 111bbc0:	4d 39 d1             	cmp    %r10,%r9
 111bbc3:	7f 0c                	jg     111bbd1 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x231>
 111bbc5:	49 83 c1 01          	add    $0x1,%r9
 111bbc9:	49 21 c9             	and    %rcx,%r9
 111bbcc:	e9 5f fe ff ff       	jmp    111ba30 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x90>
 111bbd1:	4c 89 ca             	mov    %r9,%rdx
 111bbd4:	48 89 f7             	mov    %rsi,%rdi
 111bbd7:	41 b8 40 00 00 00    	mov    $0x40,%r8d
 111bbdd:	b9 01 00 00 00       	mov    $0x1,%ecx
 111bbe2:	be 00 00 00 00       	mov    $0x0,%esi
 111bbe7:	e8 e4 f6 03 00       	call   115b2d0 <myl_qbe_fail_overflow_op>
 111bbec:	0f 0b                	ud2
 111bbee:	48 89 f8             	mov    %rdi,%rax
 111bbf1:	c7 45 e0 00 00 00 00 	movl   $0x0,-0x20(%rbp)
 111bbf8:	48 8b 4d e0          	mov    -0x20(%rbp),%rcx
 111bbfc:	48 89 08             	mov    %rcx,(%rax)
 111bbff:	48 8b 4d e8          	mov    -0x18(%rbp),%rcx
 111bc03:	48 89 48 08          	mov    %rcx,0x8(%rax)
 111bc07:	48 8b 4d f0          	mov    -0x10(%rbp),%rcx
 111bc0b:	48 89 48 10          	mov    %rcx,0x10(%rax)
 111bc0f:	eb 53                	jmp    111bc64 <myl_f_4192a2bf8c79d6c1482077147b62da5992111b1e9c0842eb498b5ef650f2e38f+0x2c4>
 111bc11:	48 89 ce             	mov    %rcx,%rsi
 111bc14:	ba 20 00 00 00       	mov    $0x20,%edx
 111bc19:	e8 f2 f7 03 00       	call   115b410 <myl_qbe_fail_cast>
 111bc1e:	0f 0b                	ud2
 111bc20:	41 b8 40 00 00 00    	mov    $0x40,%r8d
 111bc26:	b9 01 00 00 00       	mov    $0x1,%ecx
 111bc2b:	48 89 f2             	mov    %rsi,%rdx
 111bc2e:	be 01 00 00 00       	mov    $0x1,%esi
 111bc33:	e8 98 f6 03 00       	call   115b2d0 <myl_qbe_fail_overflow_op>
 111bc38:	0f 0b                	ud2
 111bc3a:	ba 40 01 00 00       	mov    $0x140,%edx
 111bc3f:	e8 cc f7 03 00       	call   115b410 <myl_qbe_fail_cast>
 111bc44:	0f 0b                	ud2
 111bc46:	c7 45 e0 00 00 00 00 	movl   $0x0,-0x20(%rbp)
 111bc4d:	48 8b 4d e0          	mov    -0x20(%rbp),%rcx
 111bc51:	48 89 08             	mov    %rcx,(%rax)
 111bc54:	48 8b 4d e8          	mov    -0x18(%rbp),%rcx
 111bc58:	48 89 48 08          	mov    %rcx,0x8(%rax)
 111bc5c:	48 8b 4d f0          	mov    -0x10(%rbp),%rcx
 111bc60:	48 89 48 10          	mov    %rcx,0x10(%rax)
 111bc64:	5b                   	pop    %rbx
 111bc65:	c9                   	leave
 111bc66:	c3                   	ret

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
