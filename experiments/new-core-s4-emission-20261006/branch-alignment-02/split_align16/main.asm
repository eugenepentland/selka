
/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s4-emission/experiments/new-core-s4-emission-20261006/branch-alignment-02/split_align16/program:     file format elf64-x86-64


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
 1032966:	0f 85 21 0a 00 00    	jne    103338d <main+0xa4d>
 103296c:	49 89 c6             	mov    %rax,%r14
 103296f:	48 8b 7b 20          	mov    0x20(%rbx),%rdi
 1032973:	48 8b 4f 08          	mov    0x8(%rdi),%rcx
 1032977:	48 85 c9             	test   %rcx,%rcx
 103297a:	74 7e                	je     10329fa <main+0xba>
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
 10329ac:	0f 1f 40 00          	nopl   0x0(%rax)
 10329b0:	41 80 f9 0a          	cmp    $0xa,%r9b
 10329b4:	73 26                	jae    10329dc <main+0x9c>
 10329b6:	40 88 f2             	mov    %sil,%dl
 10329b9:	48 29 d1             	sub    %rdx,%rcx
 10329bc:	0f 1f 40 00          	nopl   0x0(%rax)
 10329c0:	48 83 f9 08          	cmp    $0x8,%rcx
 10329c4:	0f 87 bf 01 00 00    	ja     1032b89 <main+0x249>
 10329ca:	48 8d 77 20          	lea    0x20(%rdi),%rsi
 10329ce:	48 01 d6             	add    %rdx,%rsi
 10329d1:	48 83 f9 08          	cmp    $0x8,%rcx
 10329d5:	75 30                	jne    1032a07 <main+0xc7>
 10329d7:	48 8b 16             	mov    (%rsi),%rdx
 10329da:	eb 54                	jmp    1032a30 <main+0xf0>
 10329dc:	0f 1f 40 00          	nopl   0x0(%rax)
 10329e0:	3c 21                	cmp    $0x21,%al
 10329e2:	0f 82 a1 01 00 00    	jb     1032b89 <main+0x249>
 10329e8:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
 10329ef:	00 
 10329f0:	41 80 f8 21          	cmp    $0x21,%r8b
 10329f4:	0f 82 8f 01 00 00    	jb     1032b89 <main+0x249>
 10329fa:	45 31 e4             	xor    %r12d,%r12d
 10329fd:	ba 03 00 00 00       	mov    $0x3,%edx
 1032a02:	e9 a8 01 00 00       	jmp    1032baf <main+0x26f>
 1032a07:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 1032a0e:	00 00 
 1032a10:	48 83 f9 04          	cmp    $0x4,%rcx
 1032a14:	0f 86 d5 00 00 00    	jbe    1032aef <main+0x1af>
 1032a1a:	44 8b 06             	mov    (%rsi),%r8d
 1032a1d:	48 8d 51 fc          	lea    -0x4(%rcx),%rdx
 1032a21:	8b 74 0e fc          	mov    -0x4(%rsi,%rcx,1),%esi
 1032a25:	c1 e2 03             	shl    $0x3,%edx
 1032a28:	c4 e2 e9 f7 d6       	shlx   %rdx,%rsi,%rdx
 1032a2d:	4c 09 c2             	or     %r8,%rdx
 1032a30:	c1 e1 03             	shl    $0x3,%ecx
 1032a33:	89 ce                	mov    %ecx,%esi
 1032a35:	40 f6 de             	neg    %sil
 1032a38:	c4 e2 c9 f7 d2       	shlx   %rsi,%rdx,%rdx
 1032a3d:	40 b6 40             	mov    $0x40,%sil
 1032a40:	40 28 ce             	sub    %cl,%sil
 1032a43:	48 b9 30 30 30 30 30 	movabs $0x30303030303030,%rcx
 1032a4a:	30 30 00 
 1032a4d:	c4 e2 c8 f5 c9       	bzhi   %rsi,%rcx,%rcx
 1032a52:	48 09 d1             	or     %rdx,%rcx
 1032a55:	48 ba d0 cf cf cf cf 	movabs $0xcfcfcfcfcfcfcfd0,%rdx
 1032a5c:	cf cf cf 
 1032a5f:	48 01 ca             	add    %rcx,%rdx
 1032a62:	48 be 46 46 46 46 46 	movabs $0x4646464646464646,%rsi
 1032a69:	46 46 46 
 1032a6c:	48 01 ce             	add    %rcx,%rsi
 1032a6f:	48 09 d6             	or     %rdx,%rsi
 1032a72:	48 b9 80 80 80 80 80 	movabs $0x8080808080808080,%rcx
 1032a79:	80 80 80 
 1032a7c:	48 85 ce             	test   %rcx,%rsi
 1032a7f:	0f 94 c1             	sete   %cl
 1032a82:	48 8d 34 92          	lea    (%rdx,%rdx,4),%rsi
 1032a86:	48 c1 ea 08          	shr    $0x8,%rdx
 1032a8a:	48 8d 14 72          	lea    (%rdx,%rsi,2),%rdx
 1032a8e:	48 89 d6             	mov    %rdx,%rsi
 1032a91:	48 c1 ee 10          	shr    $0x10,%rsi
 1032a95:	49 b8 ff 00 00 00 ff 	movabs $0xff000000ff,%r8
 1032a9c:	00 00 00 
 1032a9f:	4c 21 c2             	and    %r8,%rdx
 1032aa2:	4c 21 c6             	and    %r8,%rsi
 1032aa5:	49 b8 64 00 00 00 40 	movabs $0xf424000000064,%r8
 1032aac:	42 0f 00 
 1032aaf:	4c 0f af c2          	imul   %rdx,%r8
 1032ab3:	48 ba 01 00 00 00 10 	movabs $0x271000000001,%rdx
 1032aba:	27 00 00 
 1032abd:	48 0f af d6          	imul   %rsi,%rdx
 1032ac1:	4c 01 c2             	add    %r8,%rdx
 1032ac4:	48 c1 ea 20          	shr    $0x20,%rdx
 1032ac8:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
 1032acf:	00 
 1032ad0:	f6 c1 01             	test   $0x1,%cl
 1032ad3:	0f 84 b0 00 00 00    	je     1032b89 <main+0x249>
 1032ad9:	49 89 d4             	mov    %rdx,%r12
 1032adc:	49 f7 dc             	neg    %r12
 1032adf:	3c 2d                	cmp    $0x2d,%al
 1032ae1:	4c 0f 45 e2          	cmovne %rdx,%r12
 1032ae5:	ba 03 00 00 00       	mov    $0x3,%edx
 1032aea:	e9 c0 00 00 00       	jmp    1032baf <main+0x26f>
 1032aef:	48 8d 51 ff          	lea    -0x1(%rcx),%rdx
 1032af3:	48 83 fa 03          	cmp    $0x3,%rdx
 1032af7:	0f 87 65 02 00 00    	ja     1032d62 <main+0x422>
 1032afd:	4c 8d 05 bc 1a fd ff 	lea    -0x2e544(%rip),%r8        # 10045c0 <core_number_pairs+0xd0>
 1032b04:	49 63 14 90          	movslq (%r8,%rdx,4),%rdx
 1032b08:	4c 01 c2             	add    %r8,%rdx
 1032b0b:	ff e2                	jmp    *%rdx
 1032b0d:	0f b6 16             	movzbl (%rsi),%edx
 1032b10:	eb 17                	jmp    1032b29 <main+0x1e9>
 1032b12:	44 0f b7 06          	movzwl (%rsi),%r8d
 1032b16:	0f b6 56 02          	movzbl 0x2(%rsi),%edx
 1032b1a:	c1 e2 10             	shl    $0x10,%edx
 1032b1d:	44 09 c2             	or     %r8d,%edx
 1032b20:	eb 07                	jmp    1032b29 <main+0x1e9>
 1032b22:	8b 16                	mov    (%rsi),%edx
 1032b24:	eb 03                	jmp    1032b29 <main+0x1e9>
 1032b26:	0f b7 16             	movzwl (%rsi),%edx
 1032b29:	c1 e1 03             	shl    $0x3,%ecx
 1032b2c:	89 ce                	mov    %ecx,%esi
 1032b2e:	40 f6 de             	neg    %sil
 1032b31:	c4 e2 49 f7 d2       	shlx   %esi,%edx,%edx
 1032b36:	40 b6 20             	mov    $0x20,%sil
 1032b39:	40 28 ce             	sub    %cl,%sil
 1032b3c:	b9 30 30 30 00       	mov    $0x303030,%ecx
 1032b41:	c4 e2 48 f5 c9       	bzhi   %esi,%ecx,%ecx
 1032b46:	09 d1                	or     %edx,%ecx
 1032b48:	8d 91 d0 cf cf cf    	lea    -0x30303030(%rcx),%edx
 1032b4e:	81 c1 46 46 46 46    	add    $0x46464646,%ecx
 1032b54:	09 d1                	or     %edx,%ecx
 1032b56:	f7 c1 80 80 80 80    	test   $0x80808080,%ecx
 1032b5c:	0f 94 c1             	sete   %cl
 1032b5f:	69 d2 01 0a 00 00    	imul   $0xa01,%edx,%edx
 1032b65:	c1 ea 08             	shr    $0x8,%edx
 1032b68:	81 e2 ff 00 ff 00    	and    $0xff00ff,%edx
 1032b6e:	69 d2 01 00 64 00    	imul   $0x640001,%edx,%edx
 1032b74:	c1 ea 10             	shr    $0x10,%edx
 1032b77:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 1032b7e:	00 00 
 1032b80:	f6 c1 01             	test   $0x1,%cl
 1032b83:	0f 85 50 ff ff ff    	jne    1032ad9 <main+0x199>
 1032b89:	48 8d 74 24 08       	lea    0x8(%rsp),%rsi
 1032b8e:	e8 3d c1 fe ff       	call   101ecd0 <myl_core_str_parse_int>
 1032b93:	a8 01                	test   $0x1,%al
 1032b95:	74 07                	je     1032b9e <main+0x25e>
 1032b97:	4c 8b 64 24 08       	mov    0x8(%rsp),%r12
 1032b9c:	eb 03                	jmp    1032ba1 <main+0x261>
 1032b9e:	45 31 e4             	xor    %r12d,%r12d
 1032ba1:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 1032ba5:	48 83 fa 01          	cmp    $0x1,%rdx
 1032ba9:	0f 86 89 08 00 00    	jbe    1033438 <main+0xaf8>
 1032baf:	48 8b 7b 28          	mov    0x28(%rbx),%rdi
 1032bb3:	48 8b 4f 08          	mov    0x8(%rdi),%rcx
 1032bb7:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 1032bbe:	00 00 
 1032bc0:	48 85 c9             	test   %rcx,%rcx
 1032bc3:	0f 84 81 00 00 00    	je     1032c4a <main+0x30a>
 1032bc9:	0f b6 47 20          	movzbl 0x20(%rdi),%eax
 1032bcd:	44 8d 40 d5          	lea    -0x2b(%rax),%r8d
 1032bd1:	31 f6                	xor    %esi,%esi
 1032bd3:	41 f6 c0 fd          	test   $0xfd,%r8b
 1032bd7:	41 0f 94 c0          	sete   %r8b
 1032bdb:	41 0f 95 c2          	setne  %r10b
 1032bdf:	44 8d 48 d0          	lea    -0x30(%rax),%r9d
 1032be3:	41 80 f9 0a          	cmp    $0xa,%r9b
 1032be7:	41 0f 93 c3          	setae  %r11b
 1032beb:	44 0f b6 4c 0f 1f    	movzbl 0x1f(%rdi,%rcx,1),%r9d
 1032bf1:	45 84 d3             	test   %r10b,%r11b
 1032bf4:	75 36                	jne    1032c2c <main+0x2ec>
 1032bf6:	45 8d 51 d0          	lea    -0x30(%r9),%r10d
 1032bfa:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
 1032c00:	41 80 fa 0a          	cmp    $0xa,%r10b
 1032c04:	73 26                	jae    1032c2c <main+0x2ec>
 1032c06:	44 88 c6             	mov    %r8b,%sil
 1032c09:	48 29 f1             	sub    %rsi,%rcx
 1032c0c:	0f 1f 40 00          	nopl   0x0(%rax)
 1032c10:	48 83 f9 08          	cmp    $0x8,%rcx
 1032c14:	0f 87 cf 01 00 00    	ja     1032de9 <main+0x4a9>
 1032c1a:	4c 8d 47 20          	lea    0x20(%rdi),%r8
 1032c1e:	49 01 f0             	add    %rsi,%r8
 1032c21:	48 83 f9 08          	cmp    $0x8,%rcx
 1032c25:	75 30                	jne    1032c57 <main+0x317>
 1032c27:	49 8b 30             	mov    (%r8),%rsi
 1032c2a:	eb 55                	jmp    1032c81 <main+0x341>
 1032c2c:	0f 1f 40 00          	nopl   0x0(%rax)
 1032c30:	3c 21                	cmp    $0x21,%al
 1032c32:	0f 82 b1 01 00 00    	jb     1032de9 <main+0x4a9>
 1032c38:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
 1032c3f:	00 
 1032c40:	41 80 f9 21          	cmp    $0x21,%r9b
 1032c44:	0f 82 9f 01 00 00    	jb     1032de9 <main+0x4a9>
 1032c4a:	48 c7 04 24 00 00 00 	movq   $0x0,(%rsp)
 1032c51:	00 
 1032c52:	e9 b7 01 00 00       	jmp    1032e0e <main+0x4ce>
 1032c57:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 1032c5e:	00 00 
 1032c60:	48 83 f9 04          	cmp    $0x4,%rcx
 1032c64:	0f 86 d4 00 00 00    	jbe    1032d3e <main+0x3fe>
 1032c6a:	45 8b 08             	mov    (%r8),%r9d
 1032c6d:	48 8d 71 fc          	lea    -0x4(%rcx),%rsi
 1032c71:	45 8b 44 08 fc       	mov    -0x4(%r8,%rcx,1),%r8d
 1032c76:	c1 e6 03             	shl    $0x3,%esi
 1032c79:	c4 c2 c9 f7 f0       	shlx   %rsi,%r8,%rsi
 1032c7e:	4c 09 ce             	or     %r9,%rsi
 1032c81:	c1 e1 03             	shl    $0x3,%ecx
 1032c84:	41 89 c8             	mov    %ecx,%r8d
 1032c87:	41 f6 d8             	neg    %r8b
 1032c8a:	c4 e2 b9 f7 f6       	shlx   %r8,%rsi,%rsi
 1032c8f:	41 b0 40             	mov    $0x40,%r8b
 1032c92:	41 28 c8             	sub    %cl,%r8b
 1032c95:	48 b9 30 30 30 30 30 	movabs $0x30303030303030,%rcx
 1032c9c:	30 30 00 
 1032c9f:	c4 e2 b8 f5 c9       	bzhi   %r8,%rcx,%rcx
 1032ca4:	48 09 f1             	or     %rsi,%rcx
 1032ca7:	48 be d0 cf cf cf cf 	movabs $0xcfcfcfcfcfcfcfd0,%rsi
 1032cae:	cf cf cf 
 1032cb1:	48 01 ce             	add    %rcx,%rsi
 1032cb4:	49 b8 46 46 46 46 46 	movabs $0x4646464646464646,%r8
 1032cbb:	46 46 46 
 1032cbe:	49 01 c8             	add    %rcx,%r8
 1032cc1:	49 09 f0             	or     %rsi,%r8
 1032cc4:	48 b9 80 80 80 80 80 	movabs $0x8080808080808080,%rcx
 1032ccb:	80 80 80 
 1032cce:	49 85 c8             	test   %rcx,%r8
 1032cd1:	0f 94 c1             	sete   %cl
 1032cd4:	4c 8d 04 b6          	lea    (%rsi,%rsi,4),%r8
 1032cd8:	48 c1 ee 08          	shr    $0x8,%rsi
 1032cdc:	4a 8d 34 46          	lea    (%rsi,%r8,2),%rsi
 1032ce0:	49 89 f0             	mov    %rsi,%r8
 1032ce3:	49 c1 e8 10          	shr    $0x10,%r8
 1032ce7:	49 b9 ff 00 00 00 ff 	movabs $0xff000000ff,%r9
 1032cee:	00 00 00 
 1032cf1:	4c 21 ce             	and    %r9,%rsi
 1032cf4:	4d 21 c8             	and    %r9,%r8
 1032cf7:	49 b9 64 00 00 00 40 	movabs $0xf424000000064,%r9
 1032cfe:	42 0f 00 
 1032d01:	4c 0f af ce          	imul   %rsi,%r9
 1032d05:	48 be 01 00 00 00 10 	movabs $0x271000000001,%rsi
 1032d0c:	27 00 00 
 1032d0f:	49 0f af f0          	imul   %r8,%rsi
 1032d13:	4c 01 ce             	add    %r9,%rsi
 1032d16:	48 c1 ee 20          	shr    $0x20,%rsi
 1032d1a:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
 1032d20:	f6 c1 01             	test   $0x1,%cl
 1032d23:	0f 84 c0 00 00 00    	je     1032de9 <main+0x4a9>
 1032d29:	48 89 f1             	mov    %rsi,%rcx
 1032d2c:	48 f7 d9             	neg    %rcx
 1032d2f:	3c 2d                	cmp    $0x2d,%al
 1032d31:	48 0f 45 ce          	cmovne %rsi,%rcx
 1032d35:	48 89 0c 24          	mov    %rcx,(%rsp)
 1032d39:	e9 d0 00 00 00       	jmp    1032e0e <main+0x4ce>
 1032d3e:	48 8d 71 ff          	lea    -0x1(%rcx),%rsi
 1032d42:	48 83 fe 03          	cmp    $0x3,%rsi
 1032d46:	0f 87 63 02 00 00    	ja     1032faf <main+0x66f>
 1032d4c:	4c 8d 0d 7d 18 fd ff 	lea    -0x2e783(%rip),%r9        # 10045d0 <core_number_pairs+0xe0>
 1032d53:	49 63 34 b1          	movslq (%r9,%rsi,4),%rsi
 1032d57:	4c 01 ce             	add    %r9,%rsi
 1032d5a:	ff e6                	jmp    *%rsi
 1032d5c:	41 0f b6 30          	movzbl (%r8),%esi
 1032d60:	eb 2d                	jmp    1032d8f <main+0x44f>
 1032d62:	31 c9                	xor    %ecx,%ecx
 1032d64:	31 d2                	xor    %edx,%edx
 1032d66:	f6 c1 01             	test   $0x1,%cl
 1032d69:	0f 85 6a fd ff ff    	jne    1032ad9 <main+0x199>
 1032d6f:	90                   	nop
 1032d70:	e9 14 fe ff ff       	jmp    1032b89 <main+0x249>
 1032d75:	45 0f b7 08          	movzwl (%r8),%r9d
 1032d79:	41 0f b6 70 02       	movzbl 0x2(%r8),%esi
 1032d7e:	c1 e6 10             	shl    $0x10,%esi
 1032d81:	44 09 ce             	or     %r9d,%esi
 1032d84:	eb 09                	jmp    1032d8f <main+0x44f>
 1032d86:	41 8b 30             	mov    (%r8),%esi
 1032d89:	eb 04                	jmp    1032d8f <main+0x44f>
 1032d8b:	41 0f b7 30          	movzwl (%r8),%esi
 1032d8f:	c1 e1 03             	shl    $0x3,%ecx
 1032d92:	41 89 c8             	mov    %ecx,%r8d
 1032d95:	41 f6 d8             	neg    %r8b
 1032d98:	c4 e2 39 f7 f6       	shlx   %r8d,%esi,%esi
 1032d9d:	41 b0 20             	mov    $0x20,%r8b
 1032da0:	41 28 c8             	sub    %cl,%r8b
 1032da3:	b9 30 30 30 00       	mov    $0x303030,%ecx
 1032da8:	c4 e2 38 f5 c9       	bzhi   %r8d,%ecx,%ecx
 1032dad:	09 f1                	or     %esi,%ecx
 1032daf:	8d b1 d0 cf cf cf    	lea    -0x30303030(%rcx),%esi
 1032db5:	81 c1 46 46 46 46    	add    $0x46464646,%ecx
 1032dbb:	09 f1                	or     %esi,%ecx
 1032dbd:	f7 c1 80 80 80 80    	test   $0x80808080,%ecx
 1032dc3:	0f 94 c1             	sete   %cl
 1032dc6:	69 f6 01 0a 00 00    	imul   $0xa01,%esi,%esi
 1032dcc:	c1 ee 08             	shr    $0x8,%esi
 1032dcf:	81 e6 ff 00 ff 00    	and    $0xff00ff,%esi
 1032dd5:	69 f6 01 00 64 00    	imul   $0x640001,%esi,%esi
 1032ddb:	c1 ee 10             	shr    $0x10,%esi
 1032dde:	66 90                	xchg   %ax,%ax
 1032de0:	f6 c1 01             	test   $0x1,%cl
 1032de3:	0f 85 40 ff ff ff    	jne    1032d29 <main+0x3e9>
 1032de9:	48 8d 74 24 08       	lea    0x8(%rsp),%rsi
 1032dee:	e8 dd be fe ff       	call   101ecd0 <myl_core_str_parse_int>
 1032df3:	a8 01                	test   $0x1,%al
 1032df5:	74 0b                	je     1032e02 <main+0x4c2>
 1032df7:	48 8b 44 24 08       	mov    0x8(%rsp),%rax
 1032dfc:	48 89 04 24          	mov    %rax,(%rsp)
 1032e00:	eb 08                	jmp    1032e0a <main+0x4ca>
 1032e02:	48 c7 04 24 00 00 00 	movq   $0x0,(%rsp)
 1032e09:	00 
 1032e0a:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 1032e0e:	66 90                	xchg   %ax,%ax
 1032e10:	48 83 fa 02          	cmp    $0x2,%rdx
 1032e14:	0f 86 0d 06 00 00    	jbe    1033427 <main+0xae7>
 1032e1a:	48 8b 7b 30          	mov    0x30(%rbx),%rdi
 1032e1e:	48 8b 4f 08          	mov    0x8(%rdi),%rcx
 1032e22:	48 85 c9             	test   %rcx,%rcx
 1032e25:	0f 84 62 05 00 00    	je     103338d <main+0xa4d>
 1032e2b:	0f b6 47 20          	movzbl 0x20(%rdi),%eax
 1032e2f:	8d 70 d5             	lea    -0x2b(%rax),%esi
 1032e32:	31 d2                	xor    %edx,%edx
 1032e34:	40 f6 c6 fd          	test   $0xfd,%sil
 1032e38:	40 0f 94 c6          	sete   %sil
 1032e3c:	41 0f 95 c1          	setne  %r9b
 1032e40:	44 8d 40 d0          	lea    -0x30(%rax),%r8d
 1032e44:	41 80 f8 0a          	cmp    $0xa,%r8b
 1032e48:	41 0f 93 c2          	setae  %r10b
 1032e4c:	44 0f b6 44 0f 1f    	movzbl 0x1f(%rdi,%rcx,1),%r8d
 1032e52:	45 84 ca             	test   %r9b,%r10b
 1032e55:	75 35                	jne    1032e8c <main+0x54c>
 1032e57:	45 8d 48 d0          	lea    -0x30(%r8),%r9d
 1032e5b:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
 1032e60:	41 80 f9 0a          	cmp    $0xa,%r9b
 1032e64:	73 26                	jae    1032e8c <main+0x54c>
 1032e66:	40 88 f2             	mov    %sil,%dl
 1032e69:	48 29 d1             	sub    %rdx,%rcx
 1032e6c:	0f 1f 40 00          	nopl   0x0(%rax)
 1032e70:	48 83 f9 08          	cmp    $0x8,%rcx
 1032e74:	0f 87 bf 01 00 00    	ja     1033039 <main+0x6f9>
 1032e7a:	48 8d 77 20          	lea    0x20(%rdi),%rsi
 1032e7e:	48 01 d6             	add    %rdx,%rsi
 1032e81:	48 83 f9 08          	cmp    $0x8,%rcx
 1032e85:	75 28                	jne    1032eaf <main+0x56f>
 1032e87:	48 8b 16             	mov    (%rsi),%rdx
 1032e8a:	eb 44                	jmp    1032ed0 <main+0x590>
 1032e8c:	0f 1f 40 00          	nopl   0x0(%rax)
 1032e90:	3c 21                	cmp    $0x21,%al
 1032e92:	0f 82 a1 01 00 00    	jb     1033039 <main+0x6f9>
 1032e98:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
 1032e9f:	00 
 1032ea0:	41 80 f8 21          	cmp    $0x21,%r8b
 1032ea4:	0f 83 e3 04 00 00    	jae    103338d <main+0xa4d>
 1032eaa:	e9 8a 01 00 00       	jmp    1033039 <main+0x6f9>
 1032eaf:	90                   	nop
 1032eb0:	48 83 f9 04          	cmp    $0x4,%rcx
 1032eb4:	0f 86 d0 00 00 00    	jbe    1032f8a <main+0x64a>
 1032eba:	44 8b 06             	mov    (%rsi),%r8d
 1032ebd:	48 8d 51 fc          	lea    -0x4(%rcx),%rdx
 1032ec1:	8b 74 0e fc          	mov    -0x4(%rsi,%rcx,1),%esi
 1032ec5:	c1 e2 03             	shl    $0x3,%edx
 1032ec8:	c4 e2 e9 f7 d6       	shlx   %rdx,%rsi,%rdx
 1032ecd:	4c 09 c2             	or     %r8,%rdx
 1032ed0:	c1 e1 03             	shl    $0x3,%ecx
 1032ed3:	89 ce                	mov    %ecx,%esi
 1032ed5:	40 f6 de             	neg    %sil
 1032ed8:	c4 e2 c9 f7 d2       	shlx   %rsi,%rdx,%rdx
 1032edd:	40 b6 40             	mov    $0x40,%sil
 1032ee0:	40 28 ce             	sub    %cl,%sil
 1032ee3:	48 b9 30 30 30 30 30 	movabs $0x30303030303030,%rcx
 1032eea:	30 30 00 
 1032eed:	c4 e2 c8 f5 c9       	bzhi   %rsi,%rcx,%rcx
 1032ef2:	48 09 d1             	or     %rdx,%rcx
 1032ef5:	48 ba d0 cf cf cf cf 	movabs $0xcfcfcfcfcfcfcfd0,%rdx
 1032efc:	cf cf cf 
 1032eff:	48 01 ca             	add    %rcx,%rdx
 1032f02:	48 be 46 46 46 46 46 	movabs $0x4646464646464646,%rsi
 1032f09:	46 46 46 
 1032f0c:	48 01 ce             	add    %rcx,%rsi
 1032f0f:	48 09 d6             	or     %rdx,%rsi
 1032f12:	48 b9 80 80 80 80 80 	movabs $0x8080808080808080,%rcx
 1032f19:	80 80 80 
 1032f1c:	48 85 ce             	test   %rcx,%rsi
 1032f1f:	0f 94 c1             	sete   %cl
 1032f22:	48 8d 34 92          	lea    (%rdx,%rdx,4),%rsi
 1032f26:	48 c1 ea 08          	shr    $0x8,%rdx
 1032f2a:	48 8d 14 72          	lea    (%rdx,%rsi,2),%rdx
 1032f2e:	48 89 d6             	mov    %rdx,%rsi
 1032f31:	48 c1 ee 10          	shr    $0x10,%rsi
 1032f35:	49 b8 ff 00 00 00 ff 	movabs $0xff000000ff,%r8
 1032f3c:	00 00 00 
 1032f3f:	4c 21 c2             	and    %r8,%rdx
 1032f42:	4c 21 c6             	and    %r8,%rsi
 1032f45:	49 b8 64 00 00 00 40 	movabs $0xf424000000064,%r8
 1032f4c:	42 0f 00 
 1032f4f:	4c 0f af c2          	imul   %rdx,%r8
 1032f53:	48 ba 01 00 00 00 10 	movabs $0x271000000001,%rdx
 1032f5a:	27 00 00 
 1032f5d:	48 0f af d6          	imul   %rsi,%rdx
 1032f61:	4c 01 c2             	add    %r8,%rdx
 1032f64:	48 c1 ea 20          	shr    $0x20,%rdx
 1032f68:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
 1032f6f:	00 
 1032f70:	f6 c1 01             	test   $0x1,%cl
 1032f73:	0f 84 c0 00 00 00    	je     1033039 <main+0x6f9>
 1032f79:	49 89 d0             	mov    %rdx,%r8
 1032f7c:	49 f7 d8             	neg    %r8
 1032f7f:	3c 2d                	cmp    $0x2d,%al
 1032f81:	4c 0f 45 c2          	cmovne %rdx,%r8
 1032f85:	e9 c6 00 00 00       	jmp    1033050 <main+0x710>
 1032f8a:	48 8d 51 ff          	lea    -0x1(%rcx),%rdx
 1032f8e:	66 90                	xchg   %ax,%ax
 1032f90:	48 83 fa 03          	cmp    $0x3,%rdx
 1032f94:	0f 87 12 04 00 00    	ja     10333ac <main+0xa6c>
 1032f9a:	4c 8d 05 3f 16 fd ff 	lea    -0x2e9c1(%rip),%r8        # 10045e0 <core_number_pairs+0xf0>
 1032fa1:	49 63 14 90          	movslq (%r8,%rdx,4),%rdx
 1032fa5:	4c 01 c2             	add    %r8,%rdx
 1032fa8:	ff e2                	jmp    *%rdx
 1032faa:	0f b6 16             	movzbl (%rsi),%edx
 1032fad:	eb 2d                	jmp    1032fdc <main+0x69c>
 1032faf:	31 c9                	xor    %ecx,%ecx
 1032fb1:	31 f6                	xor    %esi,%esi
 1032fb3:	f6 c1 01             	test   $0x1,%cl
 1032fb6:	0f 85 6d fd ff ff    	jne    1032d29 <main+0x3e9>
 1032fbc:	0f 1f 40 00          	nopl   0x0(%rax)
 1032fc0:	e9 24 fe ff ff       	jmp    1032de9 <main+0x4a9>
 1032fc5:	44 0f b7 06          	movzwl (%rsi),%r8d
 1032fc9:	0f b6 56 02          	movzbl 0x2(%rsi),%edx
 1032fcd:	c1 e2 10             	shl    $0x10,%edx
 1032fd0:	44 09 c2             	or     %r8d,%edx
 1032fd3:	eb 07                	jmp    1032fdc <main+0x69c>
 1032fd5:	8b 16                	mov    (%rsi),%edx
 1032fd7:	eb 03                	jmp    1032fdc <main+0x69c>
 1032fd9:	0f b7 16             	movzwl (%rsi),%edx
 1032fdc:	c1 e1 03             	shl    $0x3,%ecx
 1032fdf:	89 ce                	mov    %ecx,%esi
 1032fe1:	40 f6 de             	neg    %sil
 1032fe4:	c4 e2 49 f7 d2       	shlx   %esi,%edx,%edx
 1032fe9:	40 b6 20             	mov    $0x20,%sil
 1032fec:	40 28 ce             	sub    %cl,%sil
 1032fef:	b9 30 30 30 00       	mov    $0x303030,%ecx
 1032ff4:	c4 e2 48 f5 c9       	bzhi   %esi,%ecx,%ecx
 1032ff9:	09 d1                	or     %edx,%ecx
 1032ffb:	8d 91 d0 cf cf cf    	lea    -0x30303030(%rcx),%edx
 1033001:	81 c1 46 46 46 46    	add    $0x46464646,%ecx
 1033007:	09 d1                	or     %edx,%ecx
 1033009:	f7 c1 80 80 80 80    	test   $0x80808080,%ecx
 103300f:	0f 94 c1             	sete   %cl
 1033012:	69 d2 01 0a 00 00    	imul   $0xa01,%edx,%edx
 1033018:	c1 ea 08             	shr    $0x8,%edx
 103301b:	81 e2 ff 00 ff 00    	and    $0xff00ff,%edx
 1033021:	69 d2 01 00 64 00    	imul   $0x640001,%edx,%edx
 1033027:	c1 ea 10             	shr    $0x10,%edx
 103302a:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
 1033030:	f6 c1 01             	test   $0x1,%cl
 1033033:	0f 85 40 ff ff ff    	jne    1032f79 <main+0x639>
 1033039:	48 8d 74 24 08       	lea    0x8(%rsp),%rsi
 103303e:	e8 8d bc fe ff       	call   101ecd0 <myl_core_str_parse_int>
 1033043:	84 c0                	test   %al,%al
 1033045:	0f 84 42 03 00 00    	je     103338d <main+0xa4d>
 103304b:	4c 8b 44 24 08       	mov    0x8(%rsp),%r8
 1033050:	49 83 fc 02          	cmp    $0x2,%r12
 1033054:	0f 8c 33 03 00 00    	jl     103338d <main+0xa4d>
 103305a:	48 83 3c 24 00       	cmpq   $0x0,(%rsp)
 103305f:	90                   	nop
 1033060:	0f 8e 27 03 00 00    	jle    103338d <main+0xa4d>
 1033066:	49 8d 80 bf bd f0 ff 	lea    -0xf4241(%r8),%rax
 103306d:	0f 1f 00             	nopl   (%rax)
 1033070:	48 3d c0 bd f0 ff    	cmp    $0xfffffffffff0bdc0,%rax
 1033076:	0f 82 11 03 00 00    	jb     103338d <main+0xa4d>
 103307c:	49 81 fc 00 04 00 00 	cmp    $0x400,%r12
 1033083:	4c 89 74 24 10       	mov    %r14,0x10(%rsp)
 1033088:	0f 87 30 03 00 00    	ja     10333be <main+0xa7e>
 103308e:	4a 8d 04 e5 3f 00 00 	lea    0x3f(,%r12,8),%rax
 1033095:	00 
 1033096:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 103309d:	00 00 00 
 10330a0:	48 3d 1f 04 00 00    	cmp    $0x41f,%rax
 10330a6:	0f 87 12 03 00 00    	ja     10333be <main+0xa7e>
 10330ac:	48 89 c1             	mov    %rax,%rcx
 10330af:	48 c1 e9 05          	shr    $0x5,%rcx
 10330b3:	48 8d 15 86 5a 02 00 	lea    0x25a86(%rip),%rdx        # 1058b40 <myl_core_free_lists>
 10330ba:	4c 8b 3c ca          	mov    (%rdx,%rcx,8),%r15
 10330be:	66 90                	xchg   %ax,%ax
 10330c0:	4d 85 ff             	test   %r15,%r15
 10330c3:	0f 84 f5 02 00 00    	je     10333be <main+0xa7e>
 10330c9:	49 8b 37             	mov    (%r15),%rsi
 10330cc:	48 89 34 ca          	mov    %rsi,(%rdx,%rcx,8)
 10330d0:	41 c7 07 01 00 00 00 	movl   $0x1,(%r15)
 10330d7:	c1 e1 18             	shl    $0x18,%ecx
 10330da:	41 89 4f 04          	mov    %ecx,0x4(%r15)
 10330de:	49 c7 47 08 00 00 00 	movq   $0x0,0x8(%r15)
 10330e5:	00 
 10330e6:	25 e0 07 00 00       	and    $0x7e0,%eax
 10330eb:	48 83 c0 e0          	add    $0xffffffffffffffe0,%rax
 10330ef:	48 c1 e8 03          	shr    $0x3,%rax
 10330f3:	49 89 47 10          	mov    %rax,0x10(%r15)
 10330f7:	49 c7 47 18 00 00 00 	movq   $0x0,0x18(%r15)
 10330fe:	00 
 10330ff:	48 89 5c 24 20       	mov    %rbx,0x20(%rsp)
 1033104:	48 be f3 59 37 98 22 	movabs $0x3759f22983759f3,%rsi
 103310b:	9f 75 03 
 103310e:	45 31 f6             	xor    %r14d,%r14d
 1033111:	48 bf c3 00 cd 58 c2 	movabs $0x81e722c258cd00c3,%rdi
 1033118:	22 e7 81 
 103311b:	31 ed                	xor    %ebp,%ebp
 103311d:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033124:	0f 1f 84 00 00 00 00 
 103312b:	00 
 103312c:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033133:	0f 1f 84 00 00 00 00 
 103313a:	00 
 103313b:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
 1033140:	48 39 ee             	cmp    %rbp,%rsi
 1033143:	0f 84 ac 02 00 00    	je     10333f5 <main+0xab5>
 1033149:	4d 89 c5             	mov    %r8,%r13
 103314c:	4d 01 f5             	add    %r14,%r13
 103314f:	90                   	nop
 1033150:	0f 80 b0 02 00 00    	jo     1033406 <main+0xac6>
 1033156:	4c 89 ea             	mov    %r13,%rdx
 1033159:	c4 e2 e3 f6 df       	mulx   %rdi,%rbx,%rbx
 103315e:	49 8b 47 08          	mov    0x8(%r15),%rax
 1033162:	49 3b 47 10          	cmp    0x10(%r15),%rax
 1033166:	73 2a                	jae    1033192 <main+0x852>
 1033168:	48 c1 eb 09          	shr    $0x9,%rbx
 103316c:	48 69 cb f1 03 00 00 	imul   $0x3f1,%rbx,%rcx
 1033173:	49 29 cd             	sub    %rcx,%r13
 1033176:	4d 89 6c c7 20       	mov    %r13,0x20(%r15,%rax,8)
 103317b:	48 ff c0             	inc    %rax
 103317e:	49 89 47 08          	mov    %rax,0x8(%r15)
 1033182:	48 ff c5             	inc    %rbp
 1033185:	49 83 c6 25          	add    $0x25,%r14
 1033189:	49 39 ec             	cmp    %rbp,%r12
 103318c:	75 b2                	jne    1033140 <main+0x800>
 103318e:	66 90                	xchg   %ax,%ax
 1033190:	eb 30                	jmp    10331c2 <main+0x882>
 1033192:	be 08 00 00 00       	mov    $0x8,%esi
 1033197:	4c 89 ff             	mov    %r15,%rdi
 103319a:	4d 89 c7             	mov    %r8,%r15
 103319d:	e8 ce 5e fd ff       	call   1009070 <myl_core_list_grow>
 10331a2:	48 bf c3 00 cd 58 c2 	movabs $0x81e722c258cd00c3,%rdi
 10331a9:	22 e7 81 
 10331ac:	48 be f3 59 37 98 22 	movabs $0x3759f22983759f3,%rsi
 10331b3:	9f 75 03 
 10331b6:	4d 89 f8             	mov    %r15,%r8
 10331b9:	49 89 c7             	mov    %rax,%r15
 10331bc:	48 8b 40 08          	mov    0x8(%rax),%rax
 10331c0:	eb a6                	jmp    1033168 <main+0x828>
 10331c2:	48 8d 3d a7 18 00 00 	lea    0x18a7(%rip),%rdi        # 1034a70 <core_io_file_error.verbs+0x110>
 10331c9:	e8 72 6e fd ff       	call   100a040 <myl_core_io_at>
 10331ce:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 10331d3:	e8 d8 ed fe ff       	call   1021fb0 <myl_core_host_check>
 10331d8:	31 ed                	xor    %ebp,%ebp
 10331da:	e8 81 02 00 00       	call   1033460 <runtime_bench_now>
 10331df:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
 10331e4:	49 ba f1 f0 f0 f0 f0 	movabs $0xf0f0f0f0f0f0f0f1,%r10
 10331eb:	f0 f0 f0 
 10331ee:	48 8d 0d 9b 19 00 00 	lea    0x199b(%rip),%rcx        # 1034b90 <core_io_file_error.verbs+0x230>
 10331f5:	4c 8d 0d 64 19 00 00 	lea    0x1964(%rip),%r9        # 1034b60 <core_io_file_error.verbs+0x200>
 10331fc:	48 bb e5 8f a2 12 31 	movabs $0x89705f3112a28fe5,%rbx
 1033203:	5f 70 89 
 1033206:	45 31 c0             	xor    %r8d,%r8d
 1033209:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
 1033210:	4c 89 c2             	mov    %r8,%rdx
 1033213:	c4 c2 fb f6 c2       	mulx   %r10,%rax,%rax
 1033218:	48 89 c2             	mov    %rax,%rdx
 103321b:	48 83 e2 f0          	and    $0xfffffffffffffff0,%rdx
 103321f:	48 c1 e8 04          	shr    $0x4,%rax
 1033223:	48 01 d0             	add    %rdx,%rax
 1033226:	4d 89 c6             	mov    %r8,%r14
 1033229:	49 29 c6             	sub    %rax,%r14
 103322c:	31 f6                	xor    %esi,%esi
 103322e:	45 31 ed             	xor    %r13d,%r13d
 1033231:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033238:	0f 1f 84 00 00 00 00 
 103323f:	00 
 1033240:	4b 8b 54 ef 20       	mov    0x20(%r15,%r13,8),%rdx
 1033245:	69 c2 cd cc ff ff    	imul   $0xffffcccd,%edx,%eax
 103324b:	0f b7 c0             	movzwl %ax,%eax
 103324e:	66 90                	xchg   %ax,%ax
 1033250:	3d 33 33 00 00       	cmp    $0x3333,%eax
 1033255:	76 30                	jbe    1033287 <main+0x947>
 1033257:	4c 01 f2             	add    %r14,%rdx
 103325a:	31 c0                	xor    %eax,%eax
 103325c:	0f 1f 40 00          	nopl   0x0(%rax)
 1033260:	3c 01                	cmp    $0x1,%al
 1033262:	74 36                	je     103329a <main+0x95a>
 1033264:	48 8d 04 52          	lea    (%rdx,%rdx,2),%rax
 1033268:	48 ff c0             	inc    %rax
 103326b:	48 89 f2             	mov    %rsi,%rdx
 103326e:	48 01 c2             	add    %rax,%rdx
 1033271:	0f 80 62 01 00 00    	jo     10333d9 <main+0xa99>
 1033277:	49 ff c5             	inc    %r13
 103327a:	48 89 d6             	mov    %rdx,%rsi
 103327d:	0f 1f 00             	nopl   (%rax)
 1033280:	4d 39 ec             	cmp    %r13,%r12
 1033283:	75 bb                	jne    1033240 <main+0x900>
 1033285:	eb 29                	jmp    10332b0 <main+0x970>
 1033287:	48 89 cf             	mov    %rcx,%rdi
 103328a:	e8 63 f4 ff ff       	call   10326f2 <myl_core_err_trace_origin_preserve_most>
 103328f:	ba 01 00 00 00       	mov    $0x1,%edx
 1033294:	b0 01                	mov    $0x1,%al
 1033296:	3c 01                	cmp    $0x1,%al
 1033298:	75 ca                	jne    1033264 <main+0x924>
 103329a:	4c 89 cf             	mov    %r9,%rdi
 103329d:	e8 68 f4 ff ff       	call   103270a <myl_core_err_trace_append_preserve_most>
 10332a2:	48 8d 04 d5 00 00 00 	lea    0x0(,%rdx,8),%rax
 10332a9:	00 
 10332aa:	48 29 d0             	sub    %rdx,%rax
 10332ad:	eb bc                	jmp    103326b <main+0x92b>
 10332af:	90                   	nop
 10332b0:	48 89 d6             	mov    %rdx,%rsi
 10332b3:	48 01 ee             	add    %rbp,%rsi
 10332b6:	0f 80 5c 01 00 00    	jo     1033418 <main+0xad8>
 10332bc:	48 89 f0             	mov    %rsi,%rax
 10332bf:	48 f7 eb             	imul   %rbx
 10332c2:	48 01 f2             	add    %rsi,%rdx
 10332c5:	48 89 d0             	mov    %rdx,%rax
 10332c8:	48 c1 e8 3f          	shr    $0x3f,%rax
 10332cc:	48 c1 fa 1d          	sar    $0x1d,%rdx
 10332d0:	48 01 c2             	add    %rax,%rdx
 10332d3:	48 69 c2 07 ca 9a 3b 	imul   $0x3b9aca07,%rdx,%rax
 10332da:	48 29 c6             	sub    %rax,%rsi
 10332dd:	48 89 f5             	mov    %rsi,%rbp
 10332e0:	48 c1 fd 3f          	sar    $0x3f,%rbp
 10332e4:	81 e5 07 ca 9a 3b    	and    $0x3b9aca07,%ebp
 10332ea:	48 01 f5             	add    %rsi,%rbp
 10332ed:	49 ff c0             	inc    %r8
 10332f0:	4c 3b 04 24          	cmp    (%rsp),%r8
 10332f4:	0f 85 16 ff ff ff    	jne    1033210 <main+0x8d0>
 10332fa:	41 0f b6 47 07       	movzbl 0x7(%r15),%eax
 10332ff:	90                   	nop
 1033300:	48 85 c0             	test   %rax,%rax
 1033303:	0f 84 df 00 00 00    	je     10333e8 <main+0xaa8>
 1033309:	49 83 7f 18 00       	cmpq   $0x0,0x18(%r15)
 103330e:	66 90                	xchg   %ax,%ax
 1033310:	0f 85 d2 00 00 00    	jne    10333e8 <main+0xaa8>
 1033316:	48 8d 0d 23 58 02 00 	lea    0x25823(%rip),%rcx        # 1058b40 <myl_core_free_lists>
 103331d:	48 8b 14 c1          	mov    (%rcx,%rax,8),%rdx
 1033321:	49 89 17             	mov    %rdx,(%r15)
 1033324:	4c 89 3c c1          	mov    %r15,(%rcx,%rax,8)
 1033328:	48 8b 5c 24 10       	mov    0x10(%rsp),%rbx
 103332d:	4c 8b 74 24 18       	mov    0x18(%rsp),%r14
 1033332:	48 8d 3d 67 17 00 00 	lea    0x1767(%rip),%rdi        # 1034aa0 <core_io_file_error.verbs+0x140>
 1033339:	e8 02 6d fd ff       	call   100a040 <myl_core_io_at>
 103333e:	48 89 df             	mov    %rbx,%rdi
 1033341:	e8 6a ec fe ff       	call   1021fb0 <myl_core_host_check>
 1033346:	e8 15 01 00 00       	call   1033460 <runtime_bench_now>
 103334b:	48 89 c3             	mov    %rax,%rbx
 103334e:	4c 29 f3             	sub    %r14,%rbx
 1033351:	0f 80 f2 00 00 00    	jo     1033449 <main+0xb09>
 1033357:	bf 01 00 00 00       	mov    $0x1,%edi
 103335c:	48 89 ee             	mov    %rbp,%rsi
 103335f:	e8 dc 73 fd ff       	call   100a740 <myl_core_print_i64>
 1033364:	bf 01 00 00 00       	mov    $0x1,%edi
 1033369:	e8 12 5a fd ff       	call   1008d80 <myl_core_print_sep>
 103336e:	bf 01 00 00 00       	mov    $0x1,%edi
 1033373:	48 89 de             	mov    %rbx,%rsi
 1033376:	e8 c5 73 fd ff       	call   100a740 <myl_core_print_i64>
 103337b:	bf 01 00 00 00       	mov    $0x1,%edi
 1033380:	e8 bb 5a fd ff       	call   1008e40 <myl_core_print_end>
 1033385:	45 31 ff             	xor    %r15d,%r15d
 1033388:	48 8b 5c 24 20       	mov    0x20(%rsp),%rbx
 103338d:	48 89 df             	mov    %rbx,%rdi
 1033390:	e8 ab 61 fd ff       	call   1009540 <myl_core_release>
 1033395:	4c 89 ff             	mov    %r15,%rdi
 1033398:	e8 b3 6c fd ff       	call   100a050 <myl_core_exit>
 103339d:	48 83 c4 28          	add    $0x28,%rsp
 10333a1:	5b                   	pop    %rbx
 10333a2:	41 5c                	pop    %r12
 10333a4:	41 5d                	pop    %r13
 10333a6:	41 5e                	pop    %r14
 10333a8:	41 5f                	pop    %r15
 10333aa:	5d                   	pop    %rbp
 10333ab:	c3                   	ret
 10333ac:	31 c9                	xor    %ecx,%ecx
 10333ae:	31 d2                	xor    %edx,%edx
 10333b0:	f6 c1 01             	test   $0x1,%cl
 10333b3:	0f 85 c0 fb ff ff    	jne    1032f79 <main+0x639>
 10333b9:	e9 7b fc ff ff       	jmp    1033039 <main+0x6f9>
 10333be:	be 08 00 00 00       	mov    $0x8,%esi
 10333c3:	4c 89 e7             	mov    %r12,%rdi
 10333c6:	4d 89 c6             	mov    %r8,%r14
 10333c9:	e8 32 5c fd ff       	call   1009000 <myl_core_list_new_slow>
 10333ce:	4d 89 f0             	mov    %r14,%r8
 10333d1:	49 89 c7             	mov    %rax,%r15
 10333d4:	e9 26 fd ff ff       	jmp    10330ff <main+0x7bf>
 10333d9:	48 8d 3d 50 17 00 00 	lea    0x1750(%rip),%rdi        # 1034b30 <core_io_file_error.verbs+0x1d0>
 10333e0:	48 89 c2             	mov    %rax,%rdx
 10333e3:	e8 18 63 fd ff       	call   1009700 <myl_core_trap>
 10333e8:	4c 89 ff             	mov    %r15,%rdi
 10333eb:	e8 20 ef ff ff       	call   1032310 <myl_core_free_block>
 10333f0:	e9 33 ff ff ff       	jmp    1033328 <main+0x9e8>
 10333f5:	48 8d 3d 14 16 00 00 	lea    0x1614(%rip),%rdi        # 1034a10 <core_io_file_error.verbs+0xb0>
 10333fc:	ba 25 00 00 00       	mov    $0x25,%edx
 1033401:	e8 fa 62 fd ff       	call   1009700 <myl_core_trap>
 1033406:	48 8d 3d 33 16 00 00 	lea    0x1633(%rip),%rdi        # 1034a40 <core_io_file_error.verbs+0xe0>
 103340d:	4c 89 c6             	mov    %r8,%rsi
 1033410:	4c 89 f2             	mov    %r14,%rdx
 1033413:	e8 e8 62 fd ff       	call   1009700 <myl_core_trap>
 1033418:	48 8d 3d e1 16 00 00 	lea    0x16e1(%rip),%rdi        # 1034b00 <core_io_file_error.verbs+0x1a0>
 103341f:	48 89 ee             	mov    %rbp,%rsi
 1033422:	e8 d9 62 fd ff       	call   1009700 <myl_core_trap>
 1033427:	48 8d 3d b2 15 00 00 	lea    0x15b2(%rip),%rdi        # 10349e0 <core_io_file_error.verbs+0x80>
 103342e:	be 02 00 00 00       	mov    $0x2,%esi
 1033433:	e8 c8 62 fd ff       	call   1009700 <myl_core_trap>
 1033438:	48 8d 3d 71 15 00 00 	lea    0x1571(%rip),%rdi        # 10349b0 <core_io_file_error.verbs+0x50>
 103343f:	be 01 00 00 00       	mov    $0x1,%esi
 1033444:	e8 b7 62 fd ff       	call   1009700 <myl_core_trap>
 1033449:	48 8d 3d 80 16 00 00 	lea    0x1680(%rip),%rdi        # 1034ad0 <core_io_file_error.verbs+0x170>
 1033450:	48 89 c6             	mov    %rax,%rsi
 1033453:	4c 89 f2             	mov    %r14,%rdx
 1033456:	e8 a5 62 fd ff       	call   1009700 <myl_core_trap>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
