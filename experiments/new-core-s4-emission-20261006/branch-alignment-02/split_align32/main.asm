
/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s4-emission/experiments/new-core-s4-emission-20261006/branch-alignment-02/split_align32/program:     file format elf64-x86-64


Disassembly of section .text:

0000000001032940 <main>:
 1032940:	55                   	push   %rbp
 1032941:	41 57                	push   %r15
 1032943:	41 56                	push   %r14
 1032945:	41 55                	push   %r13
 1032947:	41 54                	push   %r12
 1032949:	53                   	push   %rbx
 103294a:	48 83 ec 28          	sub    $0x28,%rsp
 103294e:	e8 1d 6c fd ff       	call   1009570 <myl_core_args>
 1032953:	48 89 c3             	mov    %rax,%rbx
 1032956:	e8 25 f6 fe ff       	call   1021f80 <myl_core_host_grant>
 103295b:	41 bf 02 00 00 00    	mov    $0x2,%r15d
 1032961:	48 83 7b 08 03       	cmpq   $0x3,0x8(%rbx)
 1032966:	0f 85 df 09 00 00    	jne    103334b <main+0xa0b>
 103296c:	49 89 c6             	mov    %rax,%r14
 103296f:	48 8b 7b 20          	mov    0x20(%rbx),%rdi
 1032973:	48 8b 4f 08          	mov    0x8(%rdi),%rcx
 1032977:	48 85 c9             	test   %rcx,%rcx
 103297a:	74 76                	je     10329f2 <main+0xb2>
 103297c:	0f b6 47 20          	movzbl 0x20(%rdi),%eax
 1032980:	8d 70 d5             	lea    -0x2b(%rax),%esi
 1032983:	31 d2                	xor    %edx,%edx
 1032985:	40 f6 c6 fd          	test   $0xfd,%sil
 1032989:	40 0f 94 c6          	sete   %sil
 103298d:	41 0f 95 c1          	setne  %r9b
 1032991:	44 8d 40 d0          	lea    -0x30(%rax),%r8d
 1032995:	41 80 f8 0a          	cmp    $0xa,%r8b
 1032999:	41 0f 93 c2          	setae  %r10b
 103299d:	44 0f b6 44 0f 1f    	movzbl 0x1f(%rdi,%rcx,1),%r8d
 10329a3:	45 84 ca             	test   %r9b,%r10b
 10329a6:	75 34                	jne    10329dc <main+0x9c>
 10329a8:	45 8d 48 d0          	lea    -0x30(%r8),%r9d
 10329ac:	41 80 f9 0a          	cmp    $0xa,%r9b
 10329b0:	73 2a                	jae    10329dc <main+0x9c>
 10329b2:	40 88 f2             	mov    %sil,%dl
 10329b5:	48 29 d1             	sub    %rdx,%rcx
 10329b8:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
 10329bf:	00 
 10329c0:	48 83 f9 08          	cmp    $0x8,%rcx
 10329c4:	0f 87 a6 01 00 00    	ja     1032b70 <main+0x230>
 10329ca:	48 8d 77 20          	lea    0x20(%rdi),%rsi
 10329ce:	48 01 d6             	add    %rdx,%rsi
 10329d1:	48 83 f9 08          	cmp    $0x8,%rcx
 10329d5:	75 28                	jne    10329ff <main+0xbf>
 10329d7:	48 8b 16             	mov    (%rsi),%rdx
 10329da:	eb 44                	jmp    1032a20 <main+0xe0>
 10329dc:	0f 1f 40 00          	nopl   0x0(%rax)
 10329e0:	3c 21                	cmp    $0x21,%al
 10329e2:	0f 82 88 01 00 00    	jb     1032b70 <main+0x230>
 10329e8:	41 80 f8 21          	cmp    $0x21,%r8b
 10329ec:	0f 82 7e 01 00 00    	jb     1032b70 <main+0x230>
 10329f2:	45 31 e4             	xor    %r12d,%r12d
 10329f5:	ba 03 00 00 00       	mov    $0x3,%edx
 10329fa:	e9 97 01 00 00       	jmp    1032b96 <main+0x256>
 10329ff:	90                   	nop
 1032a00:	48 83 f9 04          	cmp    $0x4,%rcx
 1032a04:	0f 86 d5 00 00 00    	jbe    1032adf <main+0x19f>
 1032a0a:	44 8b 06             	mov    (%rsi),%r8d
 1032a0d:	48 8d 51 fc          	lea    -0x4(%rcx),%rdx
 1032a11:	8b 74 0e fc          	mov    -0x4(%rsi,%rcx,1),%esi
 1032a15:	c1 e2 03             	shl    $0x3,%edx
 1032a18:	c4 e2 e9 f7 d6       	shlx   %rdx,%rsi,%rdx
 1032a1d:	4c 09 c2             	or     %r8,%rdx
 1032a20:	c1 e1 03             	shl    $0x3,%ecx
 1032a23:	89 ce                	mov    %ecx,%esi
 1032a25:	40 f6 de             	neg    %sil
 1032a28:	c4 e2 c9 f7 d2       	shlx   %rsi,%rdx,%rdx
 1032a2d:	40 b6 40             	mov    $0x40,%sil
 1032a30:	40 28 ce             	sub    %cl,%sil
 1032a33:	48 b9 30 30 30 30 30 	movabs $0x30303030303030,%rcx
 1032a3a:	30 30 00 
 1032a3d:	c4 e2 c8 f5 c9       	bzhi   %rsi,%rcx,%rcx
 1032a42:	48 09 d1             	or     %rdx,%rcx
 1032a45:	48 ba d0 cf cf cf cf 	movabs $0xcfcfcfcfcfcfcfd0,%rdx
 1032a4c:	cf cf cf 
 1032a4f:	48 01 ca             	add    %rcx,%rdx
 1032a52:	48 be 46 46 46 46 46 	movabs $0x4646464646464646,%rsi
 1032a59:	46 46 46 
 1032a5c:	48 01 ce             	add    %rcx,%rsi
 1032a5f:	48 09 d6             	or     %rdx,%rsi
 1032a62:	48 b9 80 80 80 80 80 	movabs $0x8080808080808080,%rcx
 1032a69:	80 80 80 
 1032a6c:	48 85 ce             	test   %rcx,%rsi
 1032a6f:	0f 94 c1             	sete   %cl
 1032a72:	48 8d 34 92          	lea    (%rdx,%rdx,4),%rsi
 1032a76:	48 c1 ea 08          	shr    $0x8,%rdx
 1032a7a:	48 8d 14 72          	lea    (%rdx,%rsi,2),%rdx
 1032a7e:	48 89 d6             	mov    %rdx,%rsi
 1032a81:	48 c1 ee 10          	shr    $0x10,%rsi
 1032a85:	49 b8 ff 00 00 00 ff 	movabs $0xff000000ff,%r8
 1032a8c:	00 00 00 
 1032a8f:	4c 21 c2             	and    %r8,%rdx
 1032a92:	4c 21 c6             	and    %r8,%rsi
 1032a95:	49 b8 64 00 00 00 40 	movabs $0xf424000000064,%r8
 1032a9c:	42 0f 00 
 1032a9f:	4c 0f af c2          	imul   %rdx,%r8
 1032aa3:	48 ba 01 00 00 00 10 	movabs $0x271000000001,%rdx
 1032aaa:	27 00 00 
 1032aad:	48 0f af d6          	imul   %rsi,%rdx
 1032ab1:	4c 01 c2             	add    %r8,%rdx
 1032ab4:	48 c1 ea 20          	shr    $0x20,%rdx
 1032ab8:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
 1032abf:	00 
 1032ac0:	f6 c1 01             	test   $0x1,%cl
 1032ac3:	0f 84 a7 00 00 00    	je     1032b70 <main+0x230>
 1032ac9:	49 89 d4             	mov    %rdx,%r12
 1032acc:	49 f7 dc             	neg    %r12
 1032acf:	3c 2d                	cmp    $0x2d,%al
 1032ad1:	4c 0f 45 e2          	cmovne %rdx,%r12
 1032ad5:	ba 03 00 00 00       	mov    $0x3,%edx
 1032ada:	e9 b7 00 00 00       	jmp    1032b96 <main+0x256>
 1032adf:	48 8d 51 ff          	lea    -0x1(%rcx),%rdx
 1032ae3:	48 83 fa 03          	cmp    $0x3,%rdx
 1032ae7:	0f 87 35 02 00 00    	ja     1032d22 <main+0x3e2>
 1032aed:	4c 8d 05 cc 1a fd ff 	lea    -0x2e534(%rip),%r8        # 10045c0 <core_number_pairs+0xd0>
 1032af4:	49 63 14 90          	movslq (%r8,%rdx,4),%rdx
 1032af8:	4c 01 c2             	add    %r8,%rdx
 1032afb:	ff e2                	jmp    *%rdx
 1032afd:	0f b6 16             	movzbl (%rsi),%edx
 1032b00:	eb 17                	jmp    1032b19 <main+0x1d9>
 1032b02:	44 0f b7 06          	movzwl (%rsi),%r8d
 1032b06:	0f b6 56 02          	movzbl 0x2(%rsi),%edx
 1032b0a:	c1 e2 10             	shl    $0x10,%edx
 1032b0d:	44 09 c2             	or     %r8d,%edx
 1032b10:	eb 07                	jmp    1032b19 <main+0x1d9>
 1032b12:	8b 16                	mov    (%rsi),%edx
 1032b14:	eb 03                	jmp    1032b19 <main+0x1d9>
 1032b16:	0f b7 16             	movzwl (%rsi),%edx
 1032b19:	c1 e1 03             	shl    $0x3,%ecx
 1032b1c:	89 ce                	mov    %ecx,%esi
 1032b1e:	40 f6 de             	neg    %sil
 1032b21:	c4 e2 49 f7 d2       	shlx   %esi,%edx,%edx
 1032b26:	40 b6 20             	mov    $0x20,%sil
 1032b29:	40 28 ce             	sub    %cl,%sil
 1032b2c:	b9 30 30 30 00       	mov    $0x303030,%ecx
 1032b31:	c4 e2 48 f5 c9       	bzhi   %esi,%ecx,%ecx
 1032b36:	09 d1                	or     %edx,%ecx
 1032b38:	8d 91 d0 cf cf cf    	lea    -0x30303030(%rcx),%edx
 1032b3e:	81 c1 46 46 46 46    	add    $0x46464646,%ecx
 1032b44:	09 d1                	or     %edx,%ecx
 1032b46:	f7 c1 80 80 80 80    	test   $0x80808080,%ecx
 1032b4c:	0f 94 c1             	sete   %cl
 1032b4f:	69 d2 01 0a 00 00    	imul   $0xa01,%edx,%edx
 1032b55:	c1 ea 08             	shr    $0x8,%edx
 1032b58:	81 e2 ff 00 ff 00    	and    $0xff00ff,%edx
 1032b5e:	69 d2 01 00 64 00    	imul   $0x640001,%edx,%edx
 1032b64:	c1 ea 10             	shr    $0x10,%edx
 1032b67:	f6 c1 01             	test   $0x1,%cl
 1032b6a:	0f 85 59 ff ff ff    	jne    1032ac9 <main+0x189>
 1032b70:	48 8d 74 24 08       	lea    0x8(%rsp),%rsi
 1032b75:	e8 56 c1 fe ff       	call   101ecd0 <myl_core_str_parse_int>
 1032b7a:	a8 01                	test   $0x1,%al
 1032b7c:	74 07                	je     1032b85 <main+0x245>
 1032b7e:	4c 8b 64 24 08       	mov    0x8(%rsp),%r12
 1032b83:	eb 03                	jmp    1032b88 <main+0x248>
 1032b85:	45 31 e4             	xor    %r12d,%r12d
 1032b88:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 1032b8c:	48 83 fa 01          	cmp    $0x1,%rdx
 1032b90:	0f 86 60 08 00 00    	jbe    10333f6 <main+0xab6>
 1032b96:	48 8b 7b 28          	mov    0x28(%rbx),%rdi
 1032b9a:	48 8b 4f 08          	mov    0x8(%rdi),%rcx
 1032b9e:	66 90                	xchg   %ax,%ax
 1032ba0:	48 85 c9             	test   %rcx,%rcx
 1032ba3:	74 6d                	je     1032c12 <main+0x2d2>
 1032ba5:	0f b6 47 20          	movzbl 0x20(%rdi),%eax
 1032ba9:	44 8d 40 d5          	lea    -0x2b(%rax),%r8d
 1032bad:	31 f6                	xor    %esi,%esi
 1032baf:	41 f6 c0 fd          	test   $0xfd,%r8b
 1032bb3:	41 0f 94 c0          	sete   %r8b
 1032bb7:	41 0f 95 c2          	setne  %r10b
 1032bbb:	44 8d 48 d0          	lea    -0x30(%rax),%r9d
 1032bbf:	41 80 f9 0a          	cmp    $0xa,%r9b
 1032bc3:	41 0f 93 c3          	setae  %r11b
 1032bc7:	44 0f b6 4c 0f 1f    	movzbl 0x1f(%rdi,%rcx,1),%r9d
 1032bcd:	45 84 d3             	test   %r10b,%r11b
 1032bd0:	75 2c                	jne    1032bfe <main+0x2be>
 1032bd2:	45 8d 51 d0          	lea    -0x30(%r9),%r10d
 1032bd6:	41 80 fa 0a          	cmp    $0xa,%r10b
 1032bda:	73 22                	jae    1032bfe <main+0x2be>
 1032bdc:	44 88 c6             	mov    %r8b,%sil
 1032bdf:	48 29 f1             	sub    %rsi,%rcx
 1032be2:	48 83 f9 08          	cmp    $0x8,%rcx
 1032be6:	0f 87 bd 01 00 00    	ja     1032da9 <main+0x469>
 1032bec:	4c 8d 47 20          	lea    0x20(%rdi),%r8
 1032bf0:	49 01 f0             	add    %rsi,%r8
 1032bf3:	48 83 f9 08          	cmp    $0x8,%rcx
 1032bf7:	75 26                	jne    1032c1f <main+0x2df>
 1032bf9:	49 8b 30             	mov    (%r8),%rsi
 1032bfc:	eb 43                	jmp    1032c41 <main+0x301>
 1032bfe:	66 90                	xchg   %ax,%ax
 1032c00:	3c 21                	cmp    $0x21,%al
 1032c02:	0f 82 a1 01 00 00    	jb     1032da9 <main+0x469>
 1032c08:	41 80 f9 21          	cmp    $0x21,%r9b
 1032c0c:	0f 82 97 01 00 00    	jb     1032da9 <main+0x469>
 1032c12:	48 c7 04 24 00 00 00 	movq   $0x0,(%rsp)
 1032c19:	00 
 1032c1a:	e9 af 01 00 00       	jmp    1032dce <main+0x48e>
 1032c1f:	90                   	nop
 1032c20:	48 83 f9 04          	cmp    $0x4,%rcx
 1032c24:	0f 86 d4 00 00 00    	jbe    1032cfe <main+0x3be>
 1032c2a:	45 8b 08             	mov    (%r8),%r9d
 1032c2d:	48 8d 71 fc          	lea    -0x4(%rcx),%rsi
 1032c31:	45 8b 44 08 fc       	mov    -0x4(%r8,%rcx,1),%r8d
 1032c36:	c1 e6 03             	shl    $0x3,%esi
 1032c39:	c4 c2 c9 f7 f0       	shlx   %rsi,%r8,%rsi
 1032c3e:	4c 09 ce             	or     %r9,%rsi
 1032c41:	c1 e1 03             	shl    $0x3,%ecx
 1032c44:	41 89 c8             	mov    %ecx,%r8d
 1032c47:	41 f6 d8             	neg    %r8b
 1032c4a:	c4 e2 b9 f7 f6       	shlx   %r8,%rsi,%rsi
 1032c4f:	41 b0 40             	mov    $0x40,%r8b
 1032c52:	41 28 c8             	sub    %cl,%r8b
 1032c55:	48 b9 30 30 30 30 30 	movabs $0x30303030303030,%rcx
 1032c5c:	30 30 00 
 1032c5f:	c4 e2 b8 f5 c9       	bzhi   %r8,%rcx,%rcx
 1032c64:	48 09 f1             	or     %rsi,%rcx
 1032c67:	48 be d0 cf cf cf cf 	movabs $0xcfcfcfcfcfcfcfd0,%rsi
 1032c6e:	cf cf cf 
 1032c71:	48 01 ce             	add    %rcx,%rsi
 1032c74:	49 b8 46 46 46 46 46 	movabs $0x4646464646464646,%r8
 1032c7b:	46 46 46 
 1032c7e:	49 01 c8             	add    %rcx,%r8
 1032c81:	49 09 f0             	or     %rsi,%r8
 1032c84:	48 b9 80 80 80 80 80 	movabs $0x8080808080808080,%rcx
 1032c8b:	80 80 80 
 1032c8e:	49 85 c8             	test   %rcx,%r8
 1032c91:	0f 94 c1             	sete   %cl
 1032c94:	4c 8d 04 b6          	lea    (%rsi,%rsi,4),%r8
 1032c98:	48 c1 ee 08          	shr    $0x8,%rsi
 1032c9c:	4a 8d 34 46          	lea    (%rsi,%r8,2),%rsi
 1032ca0:	49 89 f0             	mov    %rsi,%r8
 1032ca3:	49 c1 e8 10          	shr    $0x10,%r8
 1032ca7:	49 b9 ff 00 00 00 ff 	movabs $0xff000000ff,%r9
 1032cae:	00 00 00 
 1032cb1:	4c 21 ce             	and    %r9,%rsi
 1032cb4:	4d 21 c8             	and    %r9,%r8
 1032cb7:	49 b9 64 00 00 00 40 	movabs $0xf424000000064,%r9
 1032cbe:	42 0f 00 
 1032cc1:	4c 0f af ce          	imul   %rsi,%r9
 1032cc5:	48 be 01 00 00 00 10 	movabs $0x271000000001,%rsi
 1032ccc:	27 00 00 
 1032ccf:	49 0f af f0          	imul   %r8,%rsi
 1032cd3:	4c 01 ce             	add    %r9,%rsi
 1032cd6:	48 c1 ee 20          	shr    $0x20,%rsi
 1032cda:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
 1032ce0:	f6 c1 01             	test   $0x1,%cl
 1032ce3:	0f 84 c0 00 00 00    	je     1032da9 <main+0x469>
 1032ce9:	48 89 f1             	mov    %rsi,%rcx
 1032cec:	48 f7 d9             	neg    %rcx
 1032cef:	3c 2d                	cmp    $0x2d,%al
 1032cf1:	48 0f 45 ce          	cmovne %rsi,%rcx
 1032cf5:	48 89 0c 24          	mov    %rcx,(%rsp)
 1032cf9:	e9 d0 00 00 00       	jmp    1032dce <main+0x48e>
 1032cfe:	48 8d 71 ff          	lea    -0x1(%rcx),%rsi
 1032d02:	48 83 fe 03          	cmp    $0x3,%rsi
 1032d06:	0f 87 53 02 00 00    	ja     1032f5f <main+0x61f>
 1032d0c:	4c 8d 0d bd 18 fd ff 	lea    -0x2e743(%rip),%r9        # 10045d0 <core_number_pairs+0xe0>
 1032d13:	49 63 34 b1          	movslq (%r9,%rsi,4),%rsi
 1032d17:	4c 01 ce             	add    %r9,%rsi
 1032d1a:	ff e6                	jmp    *%rsi
 1032d1c:	41 0f b6 30          	movzbl (%r8),%esi
 1032d20:	eb 2c                	jmp    1032d4e <main+0x40e>
 1032d22:	31 c9                	xor    %ecx,%ecx
 1032d24:	31 d2                	xor    %edx,%edx
 1032d26:	f6 c1 01             	test   $0x1,%cl
 1032d29:	0f 85 9a fd ff ff    	jne    1032ac9 <main+0x189>
 1032d2f:	e9 3c fe ff ff       	jmp    1032b70 <main+0x230>
 1032d34:	45 0f b7 08          	movzwl (%r8),%r9d
 1032d38:	41 0f b6 70 02       	movzbl 0x2(%r8),%esi
 1032d3d:	c1 e6 10             	shl    $0x10,%esi
 1032d40:	44 09 ce             	or     %r9d,%esi
 1032d43:	eb 09                	jmp    1032d4e <main+0x40e>
 1032d45:	41 8b 30             	mov    (%r8),%esi
 1032d48:	eb 04                	jmp    1032d4e <main+0x40e>
 1032d4a:	41 0f b7 30          	movzwl (%r8),%esi
 1032d4e:	c1 e1 03             	shl    $0x3,%ecx
 1032d51:	41 89 c8             	mov    %ecx,%r8d
 1032d54:	41 f6 d8             	neg    %r8b
 1032d57:	c4 e2 39 f7 f6       	shlx   %r8d,%esi,%esi
 1032d5c:	41 b0 20             	mov    $0x20,%r8b
 1032d5f:	41 28 c8             	sub    %cl,%r8b
 1032d62:	b9 30 30 30 00       	mov    $0x303030,%ecx
 1032d67:	c4 e2 38 f5 c9       	bzhi   %r8d,%ecx,%ecx
 1032d6c:	09 f1                	or     %esi,%ecx
 1032d6e:	8d b1 d0 cf cf cf    	lea    -0x30303030(%rcx),%esi
 1032d74:	81 c1 46 46 46 46    	add    $0x46464646,%ecx
 1032d7a:	09 f1                	or     %esi,%ecx
 1032d7c:	f7 c1 80 80 80 80    	test   $0x80808080,%ecx
 1032d82:	0f 94 c1             	sete   %cl
 1032d85:	69 f6 01 0a 00 00    	imul   $0xa01,%esi,%esi
 1032d8b:	c1 ee 08             	shr    $0x8,%esi
 1032d8e:	81 e6 ff 00 ff 00    	and    $0xff00ff,%esi
 1032d94:	69 f6 01 00 64 00    	imul   $0x640001,%esi,%esi
 1032d9a:	c1 ee 10             	shr    $0x10,%esi
 1032d9d:	0f 1f 00             	nopl   (%rax)
 1032da0:	f6 c1 01             	test   $0x1,%cl
 1032da3:	0f 85 40 ff ff ff    	jne    1032ce9 <main+0x3a9>
 1032da9:	48 8d 74 24 08       	lea    0x8(%rsp),%rsi
 1032dae:	e8 1d bf fe ff       	call   101ecd0 <myl_core_str_parse_int>
 1032db3:	a8 01                	test   $0x1,%al
 1032db5:	74 0b                	je     1032dc2 <main+0x482>
 1032db7:	48 8b 44 24 08       	mov    0x8(%rsp),%rax
 1032dbc:	48 89 04 24          	mov    %rax,(%rsp)
 1032dc0:	eb 08                	jmp    1032dca <main+0x48a>
 1032dc2:	48 c7 04 24 00 00 00 	movq   $0x0,(%rsp)
 1032dc9:	00 
 1032dca:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 1032dce:	48 83 fa 02          	cmp    $0x2,%rdx
 1032dd2:	0f 86 0d 06 00 00    	jbe    10333e5 <main+0xaa5>
 1032dd8:	48 8b 7b 30          	mov    0x30(%rbx),%rdi
 1032ddc:	48 8b 4f 08          	mov    0x8(%rdi),%rcx
 1032de0:	48 85 c9             	test   %rcx,%rcx
 1032de3:	0f 84 62 05 00 00    	je     103334b <main+0xa0b>
 1032de9:	0f b6 47 20          	movzbl 0x20(%rdi),%eax
 1032ded:	8d 70 d5             	lea    -0x2b(%rax),%esi
 1032df0:	31 d2                	xor    %edx,%edx
 1032df2:	40 f6 c6 fd          	test   $0xfd,%sil
 1032df6:	40 0f 94 c6          	sete   %sil
 1032dfa:	41 0f 95 c1          	setne  %r9b
 1032dfe:	44 8d 40 d0          	lea    -0x30(%rax),%r8d
 1032e02:	41 80 f8 0a          	cmp    $0xa,%r8b
 1032e06:	41 0f 93 c2          	setae  %r10b
 1032e0a:	44 0f b6 44 0f 1f    	movzbl 0x1f(%rdi,%rcx,1),%r8d
 1032e10:	45 84 ca             	test   %r9b,%r10b
 1032e13:	75 2d                	jne    1032e42 <main+0x502>
 1032e15:	45 8d 48 d0          	lea    -0x30(%r8),%r9d
 1032e19:	41 80 f9 0a          	cmp    $0xa,%r9b
 1032e1d:	73 23                	jae    1032e42 <main+0x502>
 1032e1f:	40 88 f2             	mov    %sil,%dl
 1032e22:	48 29 d1             	sub    %rdx,%rcx
 1032e25:	48 83 f9 08          	cmp    $0x8,%rcx
 1032e29:	0f 87 ba 01 00 00    	ja     1032fe9 <main+0x6a9>
 1032e2f:	48 8d 77 20          	lea    0x20(%rdi),%rsi
 1032e33:	48 01 d6             	add    %rdx,%rsi
 1032e36:	48 83 f9 08          	cmp    $0x8,%rcx
 1032e3a:	75 1d                	jne    1032e59 <main+0x519>
 1032e3c:	48 8b 16             	mov    (%rsi),%rdx
 1032e3f:	90                   	nop
 1032e40:	eb 3e                	jmp    1032e80 <main+0x540>
 1032e42:	3c 21                	cmp    $0x21,%al
 1032e44:	0f 82 9f 01 00 00    	jb     1032fe9 <main+0x6a9>
 1032e4a:	41 80 f8 21          	cmp    $0x21,%r8b
 1032e4e:	0f 83 f7 04 00 00    	jae    103334b <main+0xa0b>
 1032e54:	e9 90 01 00 00       	jmp    1032fe9 <main+0x6a9>
 1032e59:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
 1032e60:	48 83 f9 04          	cmp    $0x4,%rcx
 1032e64:	0f 86 d0 00 00 00    	jbe    1032f3a <main+0x5fa>
 1032e6a:	44 8b 06             	mov    (%rsi),%r8d
 1032e6d:	48 8d 51 fc          	lea    -0x4(%rcx),%rdx
 1032e71:	8b 74 0e fc          	mov    -0x4(%rsi,%rcx,1),%esi
 1032e75:	c1 e2 03             	shl    $0x3,%edx
 1032e78:	c4 e2 e9 f7 d6       	shlx   %rdx,%rsi,%rdx
 1032e7d:	4c 09 c2             	or     %r8,%rdx
 1032e80:	c1 e1 03             	shl    $0x3,%ecx
 1032e83:	89 ce                	mov    %ecx,%esi
 1032e85:	40 f6 de             	neg    %sil
 1032e88:	c4 e2 c9 f7 d2       	shlx   %rsi,%rdx,%rdx
 1032e8d:	40 b6 40             	mov    $0x40,%sil
 1032e90:	40 28 ce             	sub    %cl,%sil
 1032e93:	48 b9 30 30 30 30 30 	movabs $0x30303030303030,%rcx
 1032e9a:	30 30 00 
 1032e9d:	c4 e2 c8 f5 c9       	bzhi   %rsi,%rcx,%rcx
 1032ea2:	48 09 d1             	or     %rdx,%rcx
 1032ea5:	48 ba d0 cf cf cf cf 	movabs $0xcfcfcfcfcfcfcfd0,%rdx
 1032eac:	cf cf cf 
 1032eaf:	48 01 ca             	add    %rcx,%rdx
 1032eb2:	48 be 46 46 46 46 46 	movabs $0x4646464646464646,%rsi
 1032eb9:	46 46 46 
 1032ebc:	48 01 ce             	add    %rcx,%rsi
 1032ebf:	48 09 d6             	or     %rdx,%rsi
 1032ec2:	48 b9 80 80 80 80 80 	movabs $0x8080808080808080,%rcx
 1032ec9:	80 80 80 
 1032ecc:	48 85 ce             	test   %rcx,%rsi
 1032ecf:	0f 94 c1             	sete   %cl
 1032ed2:	48 8d 34 92          	lea    (%rdx,%rdx,4),%rsi
 1032ed6:	48 c1 ea 08          	shr    $0x8,%rdx
 1032eda:	48 8d 14 72          	lea    (%rdx,%rsi,2),%rdx
 1032ede:	48 89 d6             	mov    %rdx,%rsi
 1032ee1:	48 c1 ee 10          	shr    $0x10,%rsi
 1032ee5:	49 b8 ff 00 00 00 ff 	movabs $0xff000000ff,%r8
 1032eec:	00 00 00 
 1032eef:	4c 21 c2             	and    %r8,%rdx
 1032ef2:	4c 21 c6             	and    %r8,%rsi
 1032ef5:	49 b8 64 00 00 00 40 	movabs $0xf424000000064,%r8
 1032efc:	42 0f 00 
 1032eff:	4c 0f af c2          	imul   %rdx,%r8
 1032f03:	48 ba 01 00 00 00 10 	movabs $0x271000000001,%rdx
 1032f0a:	27 00 00 
 1032f0d:	48 0f af d6          	imul   %rsi,%rdx
 1032f11:	4c 01 c2             	add    %r8,%rdx
 1032f14:	48 c1 ea 20          	shr    $0x20,%rdx
 1032f18:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
 1032f1f:	00 
 1032f20:	f6 c1 01             	test   $0x1,%cl
 1032f23:	0f 84 c0 00 00 00    	je     1032fe9 <main+0x6a9>
 1032f29:	49 89 d0             	mov    %rdx,%r8
 1032f2c:	49 f7 d8             	neg    %r8
 1032f2f:	3c 2d                	cmp    $0x2d,%al
 1032f31:	4c 0f 45 c2          	cmovne %rdx,%r8
 1032f35:	e9 c6 00 00 00       	jmp    1033000 <main+0x6c0>
 1032f3a:	48 8d 51 ff          	lea    -0x1(%rcx),%rdx
 1032f3e:	66 90                	xchg   %ax,%ax
 1032f40:	48 83 fa 03          	cmp    $0x3,%rdx
 1032f44:	0f 87 20 04 00 00    	ja     103336a <main+0xa2a>
 1032f4a:	4c 8d 05 8f 16 fd ff 	lea    -0x2e971(%rip),%r8        # 10045e0 <core_number_pairs+0xf0>
 1032f51:	49 63 14 90          	movslq (%r8,%rdx,4),%rdx
 1032f55:	4c 01 c2             	add    %r8,%rdx
 1032f58:	ff e2                	jmp    *%rdx
 1032f5a:	0f b6 16             	movzbl (%rsi),%edx
 1032f5d:	eb 2a                	jmp    1032f89 <main+0x649>
 1032f5f:	31 c9                	xor    %ecx,%ecx
 1032f61:	31 f6                	xor    %esi,%esi
 1032f63:	f6 c1 01             	test   $0x1,%cl
 1032f66:	0f 85 7d fd ff ff    	jne    1032ce9 <main+0x3a9>
 1032f6c:	e9 38 fe ff ff       	jmp    1032da9 <main+0x469>
 1032f71:	44 0f b7 06          	movzwl (%rsi),%r8d
 1032f75:	0f b6 56 02          	movzbl 0x2(%rsi),%edx
 1032f79:	c1 e2 10             	shl    $0x10,%edx
 1032f7c:	44 09 c2             	or     %r8d,%edx
 1032f7f:	90                   	nop
 1032f80:	eb 07                	jmp    1032f89 <main+0x649>
 1032f82:	8b 16                	mov    (%rsi),%edx
 1032f84:	eb 03                	jmp    1032f89 <main+0x649>
 1032f86:	0f b7 16             	movzwl (%rsi),%edx
 1032f89:	c1 e1 03             	shl    $0x3,%ecx
 1032f8c:	89 ce                	mov    %ecx,%esi
 1032f8e:	40 f6 de             	neg    %sil
 1032f91:	c4 e2 49 f7 d2       	shlx   %esi,%edx,%edx
 1032f96:	40 b6 20             	mov    $0x20,%sil
 1032f99:	40 28 ce             	sub    %cl,%sil
 1032f9c:	b9 30 30 30 00       	mov    $0x303030,%ecx
 1032fa1:	c4 e2 48 f5 c9       	bzhi   %esi,%ecx,%ecx
 1032fa6:	09 d1                	or     %edx,%ecx
 1032fa8:	8d 91 d0 cf cf cf    	lea    -0x30303030(%rcx),%edx
 1032fae:	81 c1 46 46 46 46    	add    $0x46464646,%ecx
 1032fb4:	09 d1                	or     %edx,%ecx
 1032fb6:	f7 c1 80 80 80 80    	test   $0x80808080,%ecx
 1032fbc:	0f 94 c1             	sete   %cl
 1032fbf:	69 d2 01 0a 00 00    	imul   $0xa01,%edx,%edx
 1032fc5:	c1 ea 08             	shr    $0x8,%edx
 1032fc8:	81 e2 ff 00 ff 00    	and    $0xff00ff,%edx
 1032fce:	69 d2 01 00 64 00    	imul   $0x640001,%edx,%edx
 1032fd4:	c1 ea 10             	shr    $0x10,%edx
 1032fd7:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 1032fde:	00 00 
 1032fe0:	f6 c1 01             	test   $0x1,%cl
 1032fe3:	0f 85 40 ff ff ff    	jne    1032f29 <main+0x5e9>
 1032fe9:	48 8d 74 24 08       	lea    0x8(%rsp),%rsi
 1032fee:	e8 dd bc fe ff       	call   101ecd0 <myl_core_str_parse_int>
 1032ff3:	84 c0                	test   %al,%al
 1032ff5:	0f 84 50 03 00 00    	je     103334b <main+0xa0b>
 1032ffb:	4c 8b 44 24 08       	mov    0x8(%rsp),%r8
 1033000:	49 83 fc 02          	cmp    $0x2,%r12
 1033004:	0f 8c 41 03 00 00    	jl     103334b <main+0xa0b>
 103300a:	48 83 3c 24 00       	cmpq   $0x0,(%rsp)
 103300f:	0f 8e 36 03 00 00    	jle    103334b <main+0xa0b>
 1033015:	49 8d 80 bf bd f0 ff 	lea    -0xf4241(%r8),%rax
 103301c:	0f 1f 40 00          	nopl   0x0(%rax)
 1033020:	48 3d c0 bd f0 ff    	cmp    $0xfffffffffff0bdc0,%rax
 1033026:	0f 82 1f 03 00 00    	jb     103334b <main+0xa0b>
 103302c:	49 81 fc 00 04 00 00 	cmp    $0x400,%r12
 1033033:	4c 89 74 24 10       	mov    %r14,0x10(%rsp)
 1033038:	0f 87 3e 03 00 00    	ja     103337c <main+0xa3c>
 103303e:	4a 8d 04 e5 3f 00 00 	lea    0x3f(,%r12,8),%rax
 1033045:	00 
 1033046:	48 3d 1f 04 00 00    	cmp    $0x41f,%rax
 103304c:	0f 87 2a 03 00 00    	ja     103337c <main+0xa3c>
 1033052:	48 89 c1             	mov    %rax,%rcx
 1033055:	48 c1 e9 05          	shr    $0x5,%rcx
 1033059:	48 8d 15 a0 5a 02 00 	lea    0x25aa0(%rip),%rdx        # 1058b00 <myl_core_free_lists>
 1033060:	4c 8b 3c ca          	mov    (%rdx,%rcx,8),%r15
 1033064:	4d 85 ff             	test   %r15,%r15
 1033067:	0f 84 0f 03 00 00    	je     103337c <main+0xa3c>
 103306d:	49 8b 37             	mov    (%r15),%rsi
 1033070:	48 89 34 ca          	mov    %rsi,(%rdx,%rcx,8)
 1033074:	41 c7 07 01 00 00 00 	movl   $0x1,(%r15)
 103307b:	c1 e1 18             	shl    $0x18,%ecx
 103307e:	41 89 4f 04          	mov    %ecx,0x4(%r15)
 1033082:	49 c7 47 08 00 00 00 	movq   $0x0,0x8(%r15)
 1033089:	00 
 103308a:	25 e0 07 00 00       	and    $0x7e0,%eax
 103308f:	48 83 c0 e0          	add    $0xffffffffffffffe0,%rax
 1033093:	48 c1 e8 03          	shr    $0x3,%rax
 1033097:	49 89 47 10          	mov    %rax,0x10(%r15)
 103309b:	49 c7 47 18 00 00 00 	movq   $0x0,0x18(%r15)
 10330a2:	00 
 10330a3:	48 89 5c 24 20       	mov    %rbx,0x20(%rsp)
 10330a8:	48 be f3 59 37 98 22 	movabs $0x3759f22983759f3,%rsi
 10330af:	9f 75 03 
 10330b2:	45 31 f6             	xor    %r14d,%r14d
 10330b5:	48 bf c3 00 cd 58 c2 	movabs $0x81e722c258cd00c3,%rdi
 10330bc:	22 e7 81 
 10330bf:	31 ed                	xor    %ebp,%ebp
 10330c1:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10330c8:	0f 1f 84 00 00 00 00 
 10330cf:	00 
 10330d0:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10330d7:	0f 1f 84 00 00 00 00 
 10330de:	00 
 10330df:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10330e6:	0f 1f 84 00 00 00 00 
 10330ed:	00 
 10330ee:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10330f5:	0f 1f 84 00 00 00 00 
 10330fc:	00 
 10330fd:	0f 1f 00             	nopl   (%rax)
 1033100:	48 39 ee             	cmp    %rbp,%rsi
 1033103:	0f 84 aa 02 00 00    	je     10333b3 <main+0xa73>
 1033109:	4d 89 c5             	mov    %r8,%r13
 103310c:	4d 01 f5             	add    %r14,%r13
 103310f:	0f 80 af 02 00 00    	jo     10333c4 <main+0xa84>
 1033115:	4c 89 ea             	mov    %r13,%rdx
 1033118:	c4 e2 e3 f6 df       	mulx   %rdi,%rbx,%rbx
 103311d:	49 8b 47 08          	mov    0x8(%r15),%rax
 1033121:	49 3b 47 10          	cmp    0x10(%r15),%rax
 1033125:	73 28                	jae    103314f <main+0x80f>
 1033127:	48 c1 eb 09          	shr    $0x9,%rbx
 103312b:	48 69 cb f1 03 00 00 	imul   $0x3f1,%rbx,%rcx
 1033132:	49 29 cd             	sub    %rcx,%r13
 1033135:	4d 89 6c c7 20       	mov    %r13,0x20(%r15,%rax,8)
 103313a:	48 ff c0             	inc    %rax
 103313d:	49 89 47 08          	mov    %rax,0x8(%r15)
 1033141:	48 ff c5             	inc    %rbp
 1033144:	49 83 c6 25          	add    $0x25,%r14
 1033148:	49 39 ec             	cmp    %rbp,%r12
 103314b:	75 b3                	jne    1033100 <main+0x7c0>
 103314d:	eb 30                	jmp    103317f <main+0x83f>
 103314f:	be 08 00 00 00       	mov    $0x8,%esi
 1033154:	4c 89 ff             	mov    %r15,%rdi
 1033157:	4d 89 c7             	mov    %r8,%r15
 103315a:	e8 11 5f fd ff       	call   1009070 <myl_core_list_grow>
 103315f:	48 bf c3 00 cd 58 c2 	movabs $0x81e722c258cd00c3,%rdi
 1033166:	22 e7 81 
 1033169:	48 be f3 59 37 98 22 	movabs $0x3759f22983759f3,%rsi
 1033170:	9f 75 03 
 1033173:	4d 89 f8             	mov    %r15,%r8
 1033176:	49 89 c7             	mov    %rax,%r15
 1033179:	48 8b 40 08          	mov    0x8(%rax),%rax
 103317d:	eb a8                	jmp    1033127 <main+0x7e7>
 103317f:	48 8d 3d aa 18 00 00 	lea    0x18aa(%rip),%rdi        # 1034a30 <core_io_file_error.verbs+0x110>
 1033186:	e8 b5 6e fd ff       	call   100a040 <myl_core_io_at>
 103318b:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 1033190:	e8 1b ee fe ff       	call   1021fb0 <myl_core_host_check>
 1033195:	31 ed                	xor    %ebp,%ebp
 1033197:	e8 84 02 00 00       	call   1033420 <runtime_bench_now>
 103319c:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
 10331a1:	49 ba f1 f0 f0 f0 f0 	movabs $0xf0f0f0f0f0f0f0f1,%r10
 10331a8:	f0 f0 f0 
 10331ab:	48 8d 0d 9e 19 00 00 	lea    0x199e(%rip),%rcx        # 1034b50 <core_io_file_error.verbs+0x230>
 10331b2:	4c 8d 0d 67 19 00 00 	lea    0x1967(%rip),%r9        # 1034b20 <core_io_file_error.verbs+0x200>
 10331b9:	48 bb e5 8f a2 12 31 	movabs $0x89705f3112a28fe5,%rbx
 10331c0:	5f 70 89 
 10331c3:	45 31 c0             	xor    %r8d,%r8d
 10331c6:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 10331cd:	00 00 00 
 10331d0:	4c 89 c2             	mov    %r8,%rdx
 10331d3:	c4 c2 fb f6 c2       	mulx   %r10,%rax,%rax
 10331d8:	48 89 c2             	mov    %rax,%rdx
 10331db:	48 83 e2 f0          	and    $0xfffffffffffffff0,%rdx
 10331df:	48 c1 e8 04          	shr    $0x4,%rax
 10331e3:	48 01 d0             	add    %rdx,%rax
 10331e6:	4d 89 c6             	mov    %r8,%r14
 10331e9:	49 29 c6             	sub    %rax,%r14
 10331ec:	31 f6                	xor    %esi,%esi
 10331ee:	45 31 ed             	xor    %r13d,%r13d
 10331f1:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10331f8:	0f 1f 84 00 00 00 00 
 10331ff:	00 
 1033200:	4b 8b 54 ef 20       	mov    0x20(%r15,%r13,8),%rdx
 1033205:	69 c2 cd cc ff ff    	imul   $0xffffcccd,%edx,%eax
 103320b:	0f b7 c0             	movzwl %ax,%eax
 103320e:	3d 33 33 00 00       	cmp    $0x3333,%eax
 1033213:	76 29                	jbe    103323e <main+0x8fe>
 1033215:	4c 01 f2             	add    %r14,%rdx
 1033218:	31 c0                	xor    %eax,%eax
 103321a:	3c 01                	cmp    $0x1,%al
 103321c:	74 33                	je     1033251 <main+0x911>
 103321e:	48 8d 04 52          	lea    (%rdx,%rdx,2),%rax
 1033222:	48 ff c0             	inc    %rax
 1033225:	48 89 f2             	mov    %rsi,%rdx
 1033228:	48 01 c2             	add    %rax,%rdx
 103322b:	0f 80 66 01 00 00    	jo     1033397 <main+0xa57>
 1033231:	49 ff c5             	inc    %r13
 1033234:	48 89 d6             	mov    %rdx,%rsi
 1033237:	4d 39 ec             	cmp    %r13,%r12
 103323a:	75 c4                	jne    1033200 <main+0x8c0>
 103323c:	eb 32                	jmp    1033270 <main+0x930>
 103323e:	48 89 cf             	mov    %rcx,%rdi
 1033241:	e8 ac f4 ff ff       	call   10326f2 <myl_core_err_trace_origin_preserve_most>
 1033246:	ba 01 00 00 00       	mov    $0x1,%edx
 103324b:	b0 01                	mov    $0x1,%al
 103324d:	3c 01                	cmp    $0x1,%al
 103324f:	75 cd                	jne    103321e <main+0x8de>
 1033251:	4c 89 cf             	mov    %r9,%rdi
 1033254:	e8 b1 f4 ff ff       	call   103270a <myl_core_err_trace_append_preserve_most>
 1033259:	48 8d 04 d5 00 00 00 	lea    0x0(,%rdx,8),%rax
 1033260:	00 
 1033261:	48 29 d0             	sub    %rdx,%rax
 1033264:	eb bf                	jmp    1033225 <main+0x8e5>
 1033266:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 103326d:	00 00 00 
 1033270:	48 89 d6             	mov    %rdx,%rsi
 1033273:	48 01 ee             	add    %rbp,%rsi
 1033276:	0f 80 5a 01 00 00    	jo     10333d6 <main+0xa96>
 103327c:	48 89 f0             	mov    %rsi,%rax
 103327f:	48 f7 eb             	imul   %rbx
 1033282:	48 01 f2             	add    %rsi,%rdx
 1033285:	48 89 d0             	mov    %rdx,%rax
 1033288:	48 c1 e8 3f          	shr    $0x3f,%rax
 103328c:	48 c1 fa 1d          	sar    $0x1d,%rdx
 1033290:	48 01 c2             	add    %rax,%rdx
 1033293:	48 69 c2 07 ca 9a 3b 	imul   $0x3b9aca07,%rdx,%rax
 103329a:	48 29 c6             	sub    %rax,%rsi
 103329d:	48 89 f5             	mov    %rsi,%rbp
 10332a0:	48 c1 fd 3f          	sar    $0x3f,%rbp
 10332a4:	81 e5 07 ca 9a 3b    	and    $0x3b9aca07,%ebp
 10332aa:	48 01 f5             	add    %rsi,%rbp
 10332ad:	49 ff c0             	inc    %r8
 10332b0:	4c 3b 04 24          	cmp    (%rsp),%r8
 10332b4:	0f 85 16 ff ff ff    	jne    10331d0 <main+0x890>
 10332ba:	41 0f b6 47 07       	movzbl 0x7(%r15),%eax
 10332bf:	90                   	nop
 10332c0:	48 85 c0             	test   %rax,%rax
 10332c3:	0f 84 dd 00 00 00    	je     10333a6 <main+0xa66>
 10332c9:	49 83 7f 18 00       	cmpq   $0x0,0x18(%r15)
 10332ce:	0f 85 d2 00 00 00    	jne    10333a6 <main+0xa66>
 10332d4:	48 8d 0d 25 58 02 00 	lea    0x25825(%rip),%rcx        # 1058b00 <myl_core_free_lists>
 10332db:	48 8b 14 c1          	mov    (%rcx,%rax,8),%rdx
 10332df:	49 89 17             	mov    %rdx,(%r15)
 10332e2:	4c 89 3c c1          	mov    %r15,(%rcx,%rax,8)
 10332e6:	48 8b 5c 24 10       	mov    0x10(%rsp),%rbx
 10332eb:	4c 8b 74 24 18       	mov    0x18(%rsp),%r14
 10332f0:	48 8d 3d 69 17 00 00 	lea    0x1769(%rip),%rdi        # 1034a60 <core_io_file_error.verbs+0x140>
 10332f7:	e8 44 6d fd ff       	call   100a040 <myl_core_io_at>
 10332fc:	48 89 df             	mov    %rbx,%rdi
 10332ff:	e8 ac ec fe ff       	call   1021fb0 <myl_core_host_check>
 1033304:	e8 17 01 00 00       	call   1033420 <runtime_bench_now>
 1033309:	48 89 c3             	mov    %rax,%rbx
 103330c:	4c 29 f3             	sub    %r14,%rbx
 103330f:	0f 80 f2 00 00 00    	jo     1033407 <main+0xac7>
 1033315:	bf 01 00 00 00       	mov    $0x1,%edi
 103331a:	48 89 ee             	mov    %rbp,%rsi
 103331d:	e8 1e 74 fd ff       	call   100a740 <myl_core_print_i64>
 1033322:	bf 01 00 00 00       	mov    $0x1,%edi
 1033327:	e8 54 5a fd ff       	call   1008d80 <myl_core_print_sep>
 103332c:	bf 01 00 00 00       	mov    $0x1,%edi
 1033331:	48 89 de             	mov    %rbx,%rsi
 1033334:	e8 07 74 fd ff       	call   100a740 <myl_core_print_i64>
 1033339:	bf 01 00 00 00       	mov    $0x1,%edi
 103333e:	e8 fd 5a fd ff       	call   1008e40 <myl_core_print_end>
 1033343:	45 31 ff             	xor    %r15d,%r15d
 1033346:	48 8b 5c 24 20       	mov    0x20(%rsp),%rbx
 103334b:	48 89 df             	mov    %rbx,%rdi
 103334e:	e8 ed 61 fd ff       	call   1009540 <myl_core_release>
 1033353:	4c 89 ff             	mov    %r15,%rdi
 1033356:	e8 f5 6c fd ff       	call   100a050 <myl_core_exit>
 103335b:	48 83 c4 28          	add    $0x28,%rsp
 103335f:	5b                   	pop    %rbx
 1033360:	41 5c                	pop    %r12
 1033362:	41 5d                	pop    %r13
 1033364:	41 5e                	pop    %r14
 1033366:	41 5f                	pop    %r15
 1033368:	5d                   	pop    %rbp
 1033369:	c3                   	ret
 103336a:	31 c9                	xor    %ecx,%ecx
 103336c:	31 d2                	xor    %edx,%edx
 103336e:	f6 c1 01             	test   $0x1,%cl
 1033371:	0f 85 b2 fb ff ff    	jne    1032f29 <main+0x5e9>
 1033377:	e9 6d fc ff ff       	jmp    1032fe9 <main+0x6a9>
 103337c:	be 08 00 00 00       	mov    $0x8,%esi
 1033381:	4c 89 e7             	mov    %r12,%rdi
 1033384:	4d 89 c6             	mov    %r8,%r14
 1033387:	e8 74 5c fd ff       	call   1009000 <myl_core_list_new_slow>
 103338c:	4d 89 f0             	mov    %r14,%r8
 103338f:	49 89 c7             	mov    %rax,%r15
 1033392:	e9 0c fd ff ff       	jmp    10330a3 <main+0x763>
 1033397:	48 8d 3d 52 17 00 00 	lea    0x1752(%rip),%rdi        # 1034af0 <core_io_file_error.verbs+0x1d0>
 103339e:	48 89 c2             	mov    %rax,%rdx
 10333a1:	e8 5a 63 fd ff       	call   1009700 <myl_core_trap>
 10333a6:	4c 89 ff             	mov    %r15,%rdi
 10333a9:	e8 62 ef ff ff       	call   1032310 <myl_core_free_block>
 10333ae:	e9 33 ff ff ff       	jmp    10332e6 <main+0x9a6>
 10333b3:	48 8d 3d 16 16 00 00 	lea    0x1616(%rip),%rdi        # 10349d0 <core_io_file_error.verbs+0xb0>
 10333ba:	ba 25 00 00 00       	mov    $0x25,%edx
 10333bf:	e8 3c 63 fd ff       	call   1009700 <myl_core_trap>
 10333c4:	48 8d 3d 35 16 00 00 	lea    0x1635(%rip),%rdi        # 1034a00 <core_io_file_error.verbs+0xe0>
 10333cb:	4c 89 c6             	mov    %r8,%rsi
 10333ce:	4c 89 f2             	mov    %r14,%rdx
 10333d1:	e8 2a 63 fd ff       	call   1009700 <myl_core_trap>
 10333d6:	48 8d 3d e3 16 00 00 	lea    0x16e3(%rip),%rdi        # 1034ac0 <core_io_file_error.verbs+0x1a0>
 10333dd:	48 89 ee             	mov    %rbp,%rsi
 10333e0:	e8 1b 63 fd ff       	call   1009700 <myl_core_trap>
 10333e5:	48 8d 3d b4 15 00 00 	lea    0x15b4(%rip),%rdi        # 10349a0 <core_io_file_error.verbs+0x80>
 10333ec:	be 02 00 00 00       	mov    $0x2,%esi
 10333f1:	e8 0a 63 fd ff       	call   1009700 <myl_core_trap>
 10333f6:	48 8d 3d 73 15 00 00 	lea    0x1573(%rip),%rdi        # 1034970 <core_io_file_error.verbs+0x50>
 10333fd:	be 01 00 00 00       	mov    $0x1,%esi
 1033402:	e8 f9 62 fd ff       	call   1009700 <myl_core_trap>
 1033407:	48 8d 3d 82 16 00 00 	lea    0x1682(%rip),%rdi        # 1034a90 <core_io_file_error.verbs+0x170>
 103340e:	48 89 c6             	mov    %rax,%rsi
 1033411:	4c 89 f2             	mov    %r14,%rdx
 1033414:	e8 e7 62 fd ff       	call   1009700 <myl_core_trap>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
