
/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s4-emission/experiments/new-core-s4-emission-20261006/entry-assembly-02/assembly_baseline/program:     file format elf64-x86-64


Disassembly of section .text:

0000000001008ac0 <main>:
 1008ac0:	55                   	push   %rbp
 1008ac1:	41 57                	push   %r15
 1008ac3:	41 56                	push   %r14
 1008ac5:	41 55                	push   %r13
 1008ac7:	41 54                	push   %r12
 1008ac9:	53                   	push   %rbx
 1008aca:	48 83 ec 28          	sub    $0x28,%rsp
 1008ace:	e8 1d 15 00 00       	call   1009ff0 <myl_core_args>
 1008ad3:	48 89 c3             	mov    %rax,%rbx
 1008ad6:	e8 25 9f 01 00       	call   1022a00 <myl_core_host_grant>
 1008adb:	41 bf 02 00 00 00    	mov    $0x2,%r15d
 1008ae1:	48 83 7b 08 03       	cmpq   $0x3,0x8(%rbx)
 1008ae6:	0f 85 5e 09 00 00    	jne    100944a <main+0x98a>
 1008aec:	49 89 c6             	mov    %rax,%r14
 1008aef:	48 8b 7b 20          	mov    0x20(%rbx),%rdi
 1008af3:	48 8b 4f 08          	mov    0x8(%rdi),%rcx
 1008af7:	48 85 c9             	test   %rcx,%rcx
 1008afa:	74 6a                	je     1008b66 <main+0xa6>
 1008afc:	0f b6 47 20          	movzbl 0x20(%rdi),%eax
 1008b00:	8d 70 d5             	lea    -0x2b(%rax),%esi
 1008b03:	31 d2                	xor    %edx,%edx
 1008b05:	40 f6 c6 fd          	test   $0xfd,%sil
 1008b09:	40 0f 94 c6          	sete   %sil
 1008b0d:	41 0f 95 c1          	setne  %r9b
 1008b11:	44 8d 40 d0          	lea    -0x30(%rax),%r8d
 1008b15:	41 80 f8 0a          	cmp    $0xa,%r8b
 1008b19:	41 0f 93 c2          	setae  %r10b
 1008b1d:	44 0f b6 44 0f 1f    	movzbl 0x1f(%rdi,%rcx,1),%r8d
 1008b23:	45 84 ca             	test   %r9b,%r10b
 1008b26:	75 2c                	jne    1008b54 <main+0x94>
 1008b28:	45 8d 48 d0          	lea    -0x30(%r8),%r9d
 1008b2c:	41 80 f9 0a          	cmp    $0xa,%r9b
 1008b30:	73 22                	jae    1008b54 <main+0x94>
 1008b32:	40 88 f2             	mov    %sil,%dl
 1008b35:	48 29 d1             	sub    %rdx,%rcx
 1008b38:	48 83 f9 08          	cmp    $0x8,%rcx
 1008b3c:	0f 87 99 01 00 00    	ja     1008cdb <main+0x21b>
 1008b42:	48 8d 77 20          	lea    0x20(%rdi),%rsi
 1008b46:	48 01 d6             	add    %rdx,%rsi
 1008b49:	48 83 f9 08          	cmp    $0x8,%rcx
 1008b4d:	75 24                	jne    1008b73 <main+0xb3>
 1008b4f:	48 8b 16             	mov    (%rsi),%rdx
 1008b52:	eb 3f                	jmp    1008b93 <main+0xd3>
 1008b54:	3c 21                	cmp    $0x21,%al
 1008b56:	0f 82 7f 01 00 00    	jb     1008cdb <main+0x21b>
 1008b5c:	41 80 f8 21          	cmp    $0x21,%r8b
 1008b60:	0f 82 75 01 00 00    	jb     1008cdb <main+0x21b>
 1008b66:	45 31 e4             	xor    %r12d,%r12d
 1008b69:	ba 03 00 00 00       	mov    $0x3,%edx
 1008b6e:	e9 8e 01 00 00       	jmp    1008d01 <main+0x241>
 1008b73:	48 83 f9 04          	cmp    $0x4,%rcx
 1008b77:	0f 86 cd 00 00 00    	jbe    1008c4a <main+0x18a>
 1008b7d:	44 8b 06             	mov    (%rsi),%r8d
 1008b80:	48 8d 51 fc          	lea    -0x4(%rcx),%rdx
 1008b84:	8b 74 0e fc          	mov    -0x4(%rsi,%rcx,1),%esi
 1008b88:	c1 e2 03             	shl    $0x3,%edx
 1008b8b:	c4 e2 e9 f7 d6       	shlx   %rdx,%rsi,%rdx
 1008b90:	4c 09 c2             	or     %r8,%rdx
 1008b93:	c1 e1 03             	shl    $0x3,%ecx
 1008b96:	89 ce                	mov    %ecx,%esi
 1008b98:	40 f6 de             	neg    %sil
 1008b9b:	c4 e2 c9 f7 d2       	shlx   %rsi,%rdx,%rdx
 1008ba0:	40 b6 40             	mov    $0x40,%sil
 1008ba3:	40 28 ce             	sub    %cl,%sil
 1008ba6:	48 b9 30 30 30 30 30 	movabs $0x30303030303030,%rcx
 1008bad:	30 30 00 
 1008bb0:	c4 e2 c8 f5 c9       	bzhi   %rsi,%rcx,%rcx
 1008bb5:	48 09 d1             	or     %rdx,%rcx
 1008bb8:	48 ba d0 cf cf cf cf 	movabs $0xcfcfcfcfcfcfcfd0,%rdx
 1008bbf:	cf cf cf 
 1008bc2:	48 01 ca             	add    %rcx,%rdx
 1008bc5:	48 be 46 46 46 46 46 	movabs $0x4646464646464646,%rsi
 1008bcc:	46 46 46 
 1008bcf:	48 01 ce             	add    %rcx,%rsi
 1008bd2:	48 09 d6             	or     %rdx,%rsi
 1008bd5:	48 b9 80 80 80 80 80 	movabs $0x8080808080808080,%rcx
 1008bdc:	80 80 80 
 1008bdf:	48 85 ce             	test   %rcx,%rsi
 1008be2:	0f 94 c1             	sete   %cl
 1008be5:	48 8d 34 92          	lea    (%rdx,%rdx,4),%rsi
 1008be9:	48 c1 ea 08          	shr    $0x8,%rdx
 1008bed:	48 8d 14 72          	lea    (%rdx,%rsi,2),%rdx
 1008bf1:	48 89 d6             	mov    %rdx,%rsi
 1008bf4:	48 c1 ee 10          	shr    $0x10,%rsi
 1008bf8:	49 b8 ff 00 00 00 ff 	movabs $0xff000000ff,%r8
 1008bff:	00 00 00 
 1008c02:	4c 21 c2             	and    %r8,%rdx
 1008c05:	4c 21 c6             	and    %r8,%rsi
 1008c08:	49 b8 64 00 00 00 40 	movabs $0xf424000000064,%r8
 1008c0f:	42 0f 00 
 1008c12:	4c 0f af c2          	imul   %rdx,%r8
 1008c16:	48 ba 01 00 00 00 10 	movabs $0x271000000001,%rdx
 1008c1d:	27 00 00 
 1008c20:	48 0f af d6          	imul   %rsi,%rdx
 1008c24:	4c 01 c2             	add    %r8,%rdx
 1008c27:	48 c1 ea 20          	shr    $0x20,%rdx
 1008c2b:	f6 c1 01             	test   $0x1,%cl
 1008c2e:	0f 84 a7 00 00 00    	je     1008cdb <main+0x21b>
 1008c34:	49 89 d4             	mov    %rdx,%r12
 1008c37:	49 f7 dc             	neg    %r12
 1008c3a:	3c 2d                	cmp    $0x2d,%al
 1008c3c:	4c 0f 45 e2          	cmovne %rdx,%r12
 1008c40:	ba 03 00 00 00       	mov    $0x3,%edx
 1008c45:	e9 b7 00 00 00       	jmp    1008d01 <main+0x241>
 1008c4a:	48 8d 51 ff          	lea    -0x1(%rcx),%rdx
 1008c4e:	48 83 fa 03          	cmp    $0x3,%rdx
 1008c52:	0f 87 2a 02 00 00    	ja     1008e82 <main+0x3c2>
 1008c58:	4c 8d 05 c1 8b ff ff 	lea    -0x743f(%rip),%r8        # 1001820 <__abi_tag+0x155c>
 1008c5f:	49 63 14 90          	movslq (%r8,%rdx,4),%rdx
 1008c63:	4c 01 c2             	add    %r8,%rdx
 1008c66:	ff e2                	jmp    *%rdx
 1008c68:	0f b6 16             	movzbl (%rsi),%edx
 1008c6b:	eb 17                	jmp    1008c84 <main+0x1c4>
 1008c6d:	44 0f b7 06          	movzwl (%rsi),%r8d
 1008c71:	0f b6 56 02          	movzbl 0x2(%rsi),%edx
 1008c75:	c1 e2 10             	shl    $0x10,%edx
 1008c78:	44 09 c2             	or     %r8d,%edx
 1008c7b:	eb 07                	jmp    1008c84 <main+0x1c4>
 1008c7d:	8b 16                	mov    (%rsi),%edx
 1008c7f:	eb 03                	jmp    1008c84 <main+0x1c4>
 1008c81:	0f b7 16             	movzwl (%rsi),%edx
 1008c84:	c1 e1 03             	shl    $0x3,%ecx
 1008c87:	89 ce                	mov    %ecx,%esi
 1008c89:	40 f6 de             	neg    %sil
 1008c8c:	c4 e2 49 f7 d2       	shlx   %esi,%edx,%edx
 1008c91:	40 b6 20             	mov    $0x20,%sil
 1008c94:	40 28 ce             	sub    %cl,%sil
 1008c97:	b9 30 30 30 00       	mov    $0x303030,%ecx
 1008c9c:	c4 e2 48 f5 c9       	bzhi   %esi,%ecx,%ecx
 1008ca1:	09 d1                	or     %edx,%ecx
 1008ca3:	8d 91 d0 cf cf cf    	lea    -0x30303030(%rcx),%edx
 1008ca9:	81 c1 46 46 46 46    	add    $0x46464646,%ecx
 1008caf:	09 d1                	or     %edx,%ecx
 1008cb1:	f7 c1 80 80 80 80    	test   $0x80808080,%ecx
 1008cb7:	0f 94 c1             	sete   %cl
 1008cba:	69 d2 01 0a 00 00    	imul   $0xa01,%edx,%edx
 1008cc0:	c1 ea 08             	shr    $0x8,%edx
 1008cc3:	81 e2 ff 00 ff 00    	and    $0xff00ff,%edx
 1008cc9:	69 d2 01 00 64 00    	imul   $0x640001,%edx,%edx
 1008ccf:	c1 ea 10             	shr    $0x10,%edx
 1008cd2:	f6 c1 01             	test   $0x1,%cl
 1008cd5:	0f 85 59 ff ff ff    	jne    1008c34 <main+0x174>
 1008cdb:	48 8d 74 24 08       	lea    0x8(%rsp),%rsi
 1008ce0:	e8 6b 6a 01 00       	call   101f750 <myl_core_str_parse_int>
 1008ce5:	a8 01                	test   $0x1,%al
 1008ce7:	74 07                	je     1008cf0 <main+0x230>
 1008ce9:	4c 8b 64 24 08       	mov    0x8(%rsp),%r12
 1008cee:	eb 03                	jmp    1008cf3 <main+0x233>
 1008cf0:	45 31 e4             	xor    %r12d,%r12d
 1008cf3:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 1008cf7:	48 83 fa 01          	cmp    $0x1,%rdx
 1008cfb:	0f 86 f4 07 00 00    	jbe    10094f5 <main+0xa35>
 1008d01:	48 8b 7b 28          	mov    0x28(%rbx),%rdi
 1008d05:	48 8b 4f 08          	mov    0x8(%rdi),%rcx
 1008d09:	48 85 c9             	test   %rcx,%rcx
 1008d0c:	74 6b                	je     1008d79 <main+0x2b9>
 1008d0e:	0f b6 47 20          	movzbl 0x20(%rdi),%eax
 1008d12:	44 8d 40 d5          	lea    -0x2b(%rax),%r8d
 1008d16:	31 f6                	xor    %esi,%esi
 1008d18:	41 f6 c0 fd          	test   $0xfd,%r8b
 1008d1c:	41 0f 94 c0          	sete   %r8b
 1008d20:	41 0f 95 c2          	setne  %r10b
 1008d24:	44 8d 48 d0          	lea    -0x30(%rax),%r9d
 1008d28:	41 80 f9 0a          	cmp    $0xa,%r9b
 1008d2c:	41 0f 93 c3          	setae  %r11b
 1008d30:	44 0f b6 4c 0f 1f    	movzbl 0x1f(%rdi,%rcx,1),%r9d
 1008d36:	45 84 d3             	test   %r10b,%r11b
 1008d39:	75 2c                	jne    1008d67 <main+0x2a7>
 1008d3b:	45 8d 51 d0          	lea    -0x30(%r9),%r10d
 1008d3f:	41 80 fa 0a          	cmp    $0xa,%r10b
 1008d43:	73 22                	jae    1008d67 <main+0x2a7>
 1008d45:	44 88 c6             	mov    %r8b,%sil
 1008d48:	48 29 f1             	sub    %rsi,%rcx
 1008d4b:	48 83 f9 08          	cmp    $0x8,%rcx
 1008d4f:	0f 87 b1 01 00 00    	ja     1008f06 <main+0x446>
 1008d55:	4c 8d 47 20          	lea    0x20(%rdi),%r8
 1008d59:	49 01 f0             	add    %rsi,%r8
 1008d5c:	48 83 f9 08          	cmp    $0x8,%rcx
 1008d60:	75 24                	jne    1008d86 <main+0x2c6>
 1008d62:	49 8b 30             	mov    (%r8),%rsi
 1008d65:	eb 40                	jmp    1008da7 <main+0x2e7>
 1008d67:	3c 21                	cmp    $0x21,%al
 1008d69:	0f 82 97 01 00 00    	jb     1008f06 <main+0x446>
 1008d6f:	41 80 f9 21          	cmp    $0x21,%r9b
 1008d73:	0f 82 8d 01 00 00    	jb     1008f06 <main+0x446>
 1008d79:	48 c7 04 24 00 00 00 	movq   $0x0,(%rsp)
 1008d80:	00 
 1008d81:	e9 a5 01 00 00       	jmp    1008f2b <main+0x46b>
 1008d86:	48 83 f9 04          	cmp    $0x4,%rcx
 1008d8a:	0f 86 ce 00 00 00    	jbe    1008e5e <main+0x39e>
 1008d90:	45 8b 08             	mov    (%r8),%r9d
 1008d93:	48 8d 71 fc          	lea    -0x4(%rcx),%rsi
 1008d97:	45 8b 44 08 fc       	mov    -0x4(%r8,%rcx,1),%r8d
 1008d9c:	c1 e6 03             	shl    $0x3,%esi
 1008d9f:	c4 c2 c9 f7 f0       	shlx   %rsi,%r8,%rsi
 1008da4:	4c 09 ce             	or     %r9,%rsi
 1008da7:	c1 e1 03             	shl    $0x3,%ecx
 1008daa:	41 89 c8             	mov    %ecx,%r8d
 1008dad:	41 f6 d8             	neg    %r8b
 1008db0:	c4 e2 b9 f7 f6       	shlx   %r8,%rsi,%rsi
 1008db5:	41 b0 40             	mov    $0x40,%r8b
 1008db8:	41 28 c8             	sub    %cl,%r8b
 1008dbb:	48 b9 30 30 30 30 30 	movabs $0x30303030303030,%rcx
 1008dc2:	30 30 00 
 1008dc5:	c4 e2 b8 f5 c9       	bzhi   %r8,%rcx,%rcx
 1008dca:	48 09 f1             	or     %rsi,%rcx
 1008dcd:	48 be d0 cf cf cf cf 	movabs $0xcfcfcfcfcfcfcfd0,%rsi
 1008dd4:	cf cf cf 
 1008dd7:	48 01 ce             	add    %rcx,%rsi
 1008dda:	49 b8 46 46 46 46 46 	movabs $0x4646464646464646,%r8
 1008de1:	46 46 46 
 1008de4:	49 01 c8             	add    %rcx,%r8
 1008de7:	49 09 f0             	or     %rsi,%r8
 1008dea:	48 b9 80 80 80 80 80 	movabs $0x8080808080808080,%rcx
 1008df1:	80 80 80 
 1008df4:	49 85 c8             	test   %rcx,%r8
 1008df7:	0f 94 c1             	sete   %cl
 1008dfa:	4c 8d 04 b6          	lea    (%rsi,%rsi,4),%r8
 1008dfe:	48 c1 ee 08          	shr    $0x8,%rsi
 1008e02:	4a 8d 34 46          	lea    (%rsi,%r8,2),%rsi
 1008e06:	49 89 f0             	mov    %rsi,%r8
 1008e09:	49 c1 e8 10          	shr    $0x10,%r8
 1008e0d:	49 b9 ff 00 00 00 ff 	movabs $0xff000000ff,%r9
 1008e14:	00 00 00 
 1008e17:	4c 21 ce             	and    %r9,%rsi
 1008e1a:	4d 21 c8             	and    %r9,%r8
 1008e1d:	49 b9 64 00 00 00 40 	movabs $0xf424000000064,%r9
 1008e24:	42 0f 00 
 1008e27:	4c 0f af ce          	imul   %rsi,%r9
 1008e2b:	48 be 01 00 00 00 10 	movabs $0x271000000001,%rsi
 1008e32:	27 00 00 
 1008e35:	49 0f af f0          	imul   %r8,%rsi
 1008e39:	4c 01 ce             	add    %r9,%rsi
 1008e3c:	48 c1 ee 20          	shr    $0x20,%rsi
 1008e40:	f6 c1 01             	test   $0x1,%cl
 1008e43:	0f 84 bd 00 00 00    	je     1008f06 <main+0x446>
 1008e49:	48 89 f1             	mov    %rsi,%rcx
 1008e4c:	48 f7 d9             	neg    %rcx
 1008e4f:	3c 2d                	cmp    $0x2d,%al
 1008e51:	48 0f 45 ce          	cmovne %rsi,%rcx
 1008e55:	48 89 0c 24          	mov    %rcx,(%rsp)
 1008e59:	e9 cd 00 00 00       	jmp    1008f2b <main+0x46b>
 1008e5e:	48 8d 71 ff          	lea    -0x1(%rcx),%rsi
 1008e62:	48 83 fe 03          	cmp    $0x3,%rsi
 1008e66:	0f 87 3e 02 00 00    	ja     10090aa <main+0x5ea>
 1008e6c:	4c 8d 0d bd 89 ff ff 	lea    -0x7643(%rip),%r9        # 1001830 <__abi_tag+0x156c>
 1008e73:	49 63 34 b1          	movslq (%r9,%rsi,4),%rsi
 1008e77:	4c 01 ce             	add    %r9,%rsi
 1008e7a:	ff e6                	jmp    *%rsi
 1008e7c:	41 0f b6 30          	movzbl (%r8),%esi
 1008e80:	eb 2c                	jmp    1008eae <main+0x3ee>
 1008e82:	31 c9                	xor    %ecx,%ecx
 1008e84:	31 d2                	xor    %edx,%edx
 1008e86:	f6 c1 01             	test   $0x1,%cl
 1008e89:	0f 85 a5 fd ff ff    	jne    1008c34 <main+0x174>
 1008e8f:	e9 47 fe ff ff       	jmp    1008cdb <main+0x21b>
 1008e94:	45 0f b7 08          	movzwl (%r8),%r9d
 1008e98:	41 0f b6 70 02       	movzbl 0x2(%r8),%esi
 1008e9d:	c1 e6 10             	shl    $0x10,%esi
 1008ea0:	44 09 ce             	or     %r9d,%esi
 1008ea3:	eb 09                	jmp    1008eae <main+0x3ee>
 1008ea5:	41 8b 30             	mov    (%r8),%esi
 1008ea8:	eb 04                	jmp    1008eae <main+0x3ee>
 1008eaa:	41 0f b7 30          	movzwl (%r8),%esi
 1008eae:	c1 e1 03             	shl    $0x3,%ecx
 1008eb1:	41 89 c8             	mov    %ecx,%r8d
 1008eb4:	41 f6 d8             	neg    %r8b
 1008eb7:	c4 e2 39 f7 f6       	shlx   %r8d,%esi,%esi
 1008ebc:	41 b0 20             	mov    $0x20,%r8b
 1008ebf:	41 28 c8             	sub    %cl,%r8b
 1008ec2:	b9 30 30 30 00       	mov    $0x303030,%ecx
 1008ec7:	c4 e2 38 f5 c9       	bzhi   %r8d,%ecx,%ecx
 1008ecc:	09 f1                	or     %esi,%ecx
 1008ece:	8d b1 d0 cf cf cf    	lea    -0x30303030(%rcx),%esi
 1008ed4:	81 c1 46 46 46 46    	add    $0x46464646,%ecx
 1008eda:	09 f1                	or     %esi,%ecx
 1008edc:	f7 c1 80 80 80 80    	test   $0x80808080,%ecx
 1008ee2:	0f 94 c1             	sete   %cl
 1008ee5:	69 f6 01 0a 00 00    	imul   $0xa01,%esi,%esi
 1008eeb:	c1 ee 08             	shr    $0x8,%esi
 1008eee:	81 e6 ff 00 ff 00    	and    $0xff00ff,%esi
 1008ef4:	69 f6 01 00 64 00    	imul   $0x640001,%esi,%esi
 1008efa:	c1 ee 10             	shr    $0x10,%esi
 1008efd:	f6 c1 01             	test   $0x1,%cl
 1008f00:	0f 85 43 ff ff ff    	jne    1008e49 <main+0x389>
 1008f06:	48 8d 74 24 08       	lea    0x8(%rsp),%rsi
 1008f0b:	e8 40 68 01 00       	call   101f750 <myl_core_str_parse_int>
 1008f10:	a8 01                	test   $0x1,%al
 1008f12:	74 0b                	je     1008f1f <main+0x45f>
 1008f14:	48 8b 44 24 08       	mov    0x8(%rsp),%rax
 1008f19:	48 89 04 24          	mov    %rax,(%rsp)
 1008f1d:	eb 08                	jmp    1008f27 <main+0x467>
 1008f1f:	48 c7 04 24 00 00 00 	movq   $0x0,(%rsp)
 1008f26:	00 
 1008f27:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 1008f2b:	48 83 fa 02          	cmp    $0x2,%rdx
 1008f2f:	0f 86 af 05 00 00    	jbe    10094e4 <main+0xa24>
 1008f35:	48 8b 7b 30          	mov    0x30(%rbx),%rdi
 1008f39:	48 8b 4f 08          	mov    0x8(%rdi),%rcx
 1008f3d:	48 85 c9             	test   %rcx,%rcx
 1008f40:	0f 84 04 05 00 00    	je     100944a <main+0x98a>
 1008f46:	0f b6 47 20          	movzbl 0x20(%rdi),%eax
 1008f4a:	8d 70 d5             	lea    -0x2b(%rax),%esi
 1008f4d:	31 d2                	xor    %edx,%edx
 1008f4f:	40 f6 c6 fd          	test   $0xfd,%sil
 1008f53:	40 0f 94 c6          	sete   %sil
 1008f57:	41 0f 95 c1          	setne  %r9b
 1008f5b:	44 8d 40 d0          	lea    -0x30(%rax),%r8d
 1008f5f:	41 80 f8 0a          	cmp    $0xa,%r8b
 1008f63:	41 0f 93 c2          	setae  %r10b
 1008f67:	44 0f b6 44 0f 1f    	movzbl 0x1f(%rdi,%rcx,1),%r8d
 1008f6d:	45 84 ca             	test   %r9b,%r10b
 1008f70:	75 2c                	jne    1008f9e <main+0x4de>
 1008f72:	45 8d 48 d0          	lea    -0x30(%r8),%r9d
 1008f76:	41 80 f9 0a          	cmp    $0xa,%r9b
 1008f7a:	73 22                	jae    1008f9e <main+0x4de>
 1008f7c:	40 88 f2             	mov    %sil,%dl
 1008f7f:	48 29 d1             	sub    %rdx,%rcx
 1008f82:	48 83 f9 08          	cmp    $0x8,%rcx
 1008f86:	0f 87 9e 01 00 00    	ja     100912a <main+0x66a>
 1008f8c:	48 8d 77 20          	lea    0x20(%rdi),%rsi
 1008f90:	48 01 d6             	add    %rdx,%rsi
 1008f93:	48 83 f9 08          	cmp    $0x8,%rcx
 1008f97:	75 1c                	jne    1008fb5 <main+0x4f5>
 1008f99:	48 8b 16             	mov    (%rsi),%rdx
 1008f9c:	eb 37                	jmp    1008fd5 <main+0x515>
 1008f9e:	3c 21                	cmp    $0x21,%al
 1008fa0:	0f 82 84 01 00 00    	jb     100912a <main+0x66a>
 1008fa6:	41 80 f8 21          	cmp    $0x21,%r8b
 1008faa:	0f 83 9a 04 00 00    	jae    100944a <main+0x98a>
 1008fb0:	e9 75 01 00 00       	jmp    100912a <main+0x66a>
 1008fb5:	48 83 f9 04          	cmp    $0x4,%rcx
 1008fb9:	0f 86 c8 00 00 00    	jbe    1009087 <main+0x5c7>
 1008fbf:	44 8b 06             	mov    (%rsi),%r8d
 1008fc2:	48 8d 51 fc          	lea    -0x4(%rcx),%rdx
 1008fc6:	8b 74 0e fc          	mov    -0x4(%rsi,%rcx,1),%esi
 1008fca:	c1 e2 03             	shl    $0x3,%edx
 1008fcd:	c4 e2 e9 f7 d6       	shlx   %rdx,%rsi,%rdx
 1008fd2:	4c 09 c2             	or     %r8,%rdx
 1008fd5:	c1 e1 03             	shl    $0x3,%ecx
 1008fd8:	89 ce                	mov    %ecx,%esi
 1008fda:	40 f6 de             	neg    %sil
 1008fdd:	c4 e2 c9 f7 d2       	shlx   %rsi,%rdx,%rdx
 1008fe2:	40 b6 40             	mov    $0x40,%sil
 1008fe5:	40 28 ce             	sub    %cl,%sil
 1008fe8:	48 b9 30 30 30 30 30 	movabs $0x30303030303030,%rcx
 1008fef:	30 30 00 
 1008ff2:	c4 e2 c8 f5 c9       	bzhi   %rsi,%rcx,%rcx
 1008ff7:	48 09 d1             	or     %rdx,%rcx
 1008ffa:	48 ba d0 cf cf cf cf 	movabs $0xcfcfcfcfcfcfcfd0,%rdx
 1009001:	cf cf cf 
 1009004:	48 01 ca             	add    %rcx,%rdx
 1009007:	48 be 46 46 46 46 46 	movabs $0x4646464646464646,%rsi
 100900e:	46 46 46 
 1009011:	48 01 ce             	add    %rcx,%rsi
 1009014:	48 09 d6             	or     %rdx,%rsi
 1009017:	48 b9 80 80 80 80 80 	movabs $0x8080808080808080,%rcx
 100901e:	80 80 80 
 1009021:	48 85 ce             	test   %rcx,%rsi
 1009024:	0f 94 c1             	sete   %cl
 1009027:	48 8d 34 92          	lea    (%rdx,%rdx,4),%rsi
 100902b:	48 c1 ea 08          	shr    $0x8,%rdx
 100902f:	48 8d 14 72          	lea    (%rdx,%rsi,2),%rdx
 1009033:	48 89 d6             	mov    %rdx,%rsi
 1009036:	48 c1 ee 10          	shr    $0x10,%rsi
 100903a:	49 b8 ff 00 00 00 ff 	movabs $0xff000000ff,%r8
 1009041:	00 00 00 
 1009044:	4c 21 c2             	and    %r8,%rdx
 1009047:	4c 21 c6             	and    %r8,%rsi
 100904a:	49 b8 64 00 00 00 40 	movabs $0xf424000000064,%r8
 1009051:	42 0f 00 
 1009054:	4c 0f af c2          	imul   %rdx,%r8
 1009058:	48 ba 01 00 00 00 10 	movabs $0x271000000001,%rdx
 100905f:	27 00 00 
 1009062:	48 0f af d6          	imul   %rsi,%rdx
 1009066:	4c 01 c2             	add    %r8,%rdx
 1009069:	48 c1 ea 20          	shr    $0x20,%rdx
 100906d:	f6 c1 01             	test   $0x1,%cl
 1009070:	0f 84 b4 00 00 00    	je     100912a <main+0x66a>
 1009076:	49 89 d0             	mov    %rdx,%r8
 1009079:	49 f7 d8             	neg    %r8
 100907c:	3c 2d                	cmp    $0x2d,%al
 100907e:	4c 0f 45 c2          	cmovne %rdx,%r8
 1009082:	e9 ba 00 00 00       	jmp    1009141 <main+0x681>
 1009087:	48 8d 51 ff          	lea    -0x1(%rcx),%rdx
 100908b:	48 83 fa 03          	cmp    $0x3,%rdx
 100908f:	0f 87 d4 03 00 00    	ja     1009469 <main+0x9a9>
 1009095:	4c 8d 05 a4 87 ff ff 	lea    -0x785c(%rip),%r8        # 1001840 <__abi_tag+0x157c>
 100909c:	49 63 14 90          	movslq (%r8,%rdx,4),%rdx
 10090a0:	4c 01 c2             	add    %r8,%rdx
 10090a3:	ff e2                	jmp    *%rdx
 10090a5:	0f b6 16             	movzbl (%rsi),%edx
 10090a8:	eb 29                	jmp    10090d3 <main+0x613>
 10090aa:	31 c9                	xor    %ecx,%ecx
 10090ac:	31 f6                	xor    %esi,%esi
 10090ae:	f6 c1 01             	test   $0x1,%cl
 10090b1:	0f 85 92 fd ff ff    	jne    1008e49 <main+0x389>
 10090b7:	e9 4a fe ff ff       	jmp    1008f06 <main+0x446>
 10090bc:	44 0f b7 06          	movzwl (%rsi),%r8d
 10090c0:	0f b6 56 02          	movzbl 0x2(%rsi),%edx
 10090c4:	c1 e2 10             	shl    $0x10,%edx
 10090c7:	44 09 c2             	or     %r8d,%edx
 10090ca:	eb 07                	jmp    10090d3 <main+0x613>
 10090cc:	8b 16                	mov    (%rsi),%edx
 10090ce:	eb 03                	jmp    10090d3 <main+0x613>
 10090d0:	0f b7 16             	movzwl (%rsi),%edx
 10090d3:	c1 e1 03             	shl    $0x3,%ecx
 10090d6:	89 ce                	mov    %ecx,%esi
 10090d8:	40 f6 de             	neg    %sil
 10090db:	c4 e2 49 f7 d2       	shlx   %esi,%edx,%edx
 10090e0:	40 b6 20             	mov    $0x20,%sil
 10090e3:	40 28 ce             	sub    %cl,%sil
 10090e6:	b9 30 30 30 00       	mov    $0x303030,%ecx
 10090eb:	c4 e2 48 f5 c9       	bzhi   %esi,%ecx,%ecx
 10090f0:	09 d1                	or     %edx,%ecx
 10090f2:	8d 91 d0 cf cf cf    	lea    -0x30303030(%rcx),%edx
 10090f8:	81 c1 46 46 46 46    	add    $0x46464646,%ecx
 10090fe:	09 d1                	or     %edx,%ecx
 1009100:	f7 c1 80 80 80 80    	test   $0x80808080,%ecx
 1009106:	0f 94 c1             	sete   %cl
 1009109:	69 d2 01 0a 00 00    	imul   $0xa01,%edx,%edx
 100910f:	c1 ea 08             	shr    $0x8,%edx
 1009112:	81 e2 ff 00 ff 00    	and    $0xff00ff,%edx
 1009118:	69 d2 01 00 64 00    	imul   $0x640001,%edx,%edx
 100911e:	c1 ea 10             	shr    $0x10,%edx
 1009121:	f6 c1 01             	test   $0x1,%cl
 1009124:	0f 85 4c ff ff ff    	jne    1009076 <main+0x5b6>
 100912a:	48 8d 74 24 08       	lea    0x8(%rsp),%rsi
 100912f:	e8 1c 66 01 00       	call   101f750 <myl_core_str_parse_int>
 1009134:	84 c0                	test   %al,%al
 1009136:	0f 84 0e 03 00 00    	je     100944a <main+0x98a>
 100913c:	4c 8b 44 24 08       	mov    0x8(%rsp),%r8
 1009141:	49 83 fc 02          	cmp    $0x2,%r12
 1009145:	0f 8c ff 02 00 00    	jl     100944a <main+0x98a>
 100914b:	48 83 3c 24 00       	cmpq   $0x0,(%rsp)
 1009150:	0f 8e f4 02 00 00    	jle    100944a <main+0x98a>
 1009156:	49 8d 80 bf bd f0 ff 	lea    -0xf4241(%r8),%rax
 100915d:	48 3d c0 bd f0 ff    	cmp    $0xfffffffffff0bdc0,%rax
 1009163:	0f 82 e1 02 00 00    	jb     100944a <main+0x98a>
 1009169:	49 81 fc 00 04 00 00 	cmp    $0x400,%r12
 1009170:	4c 89 74 24 10       	mov    %r14,0x10(%rsp)
 1009175:	0f 87 00 03 00 00    	ja     100947b <main+0x9bb>
 100917b:	4a 8d 04 e5 3f 00 00 	lea    0x3f(,%r12,8),%rax
 1009182:	00 
 1009183:	48 3d 1f 04 00 00    	cmp    $0x41f,%rax
 1009189:	0f 87 ec 02 00 00    	ja     100947b <main+0x9bb>
 100918f:	48 89 c1             	mov    %rax,%rcx
 1009192:	48 c1 e9 05          	shr    $0x5,%rcx
 1009196:	48 8d 15 e3 f8 04 00 	lea    0x4f8e3(%rip),%rdx        # 1058a80 <myl_core_free_lists>
 100919d:	4c 8b 3c ca          	mov    (%rdx,%rcx,8),%r15
 10091a1:	4d 85 ff             	test   %r15,%r15
 10091a4:	0f 84 d1 02 00 00    	je     100947b <main+0x9bb>
 10091aa:	49 8b 37             	mov    (%r15),%rsi
 10091ad:	48 89 34 ca          	mov    %rsi,(%rdx,%rcx,8)
 10091b1:	41 c7 07 01 00 00 00 	movl   $0x1,(%r15)
 10091b8:	c1 e1 18             	shl    $0x18,%ecx
 10091bb:	41 89 4f 04          	mov    %ecx,0x4(%r15)
 10091bf:	49 c7 47 08 00 00 00 	movq   $0x0,0x8(%r15)
 10091c6:	00 
 10091c7:	25 e0 07 00 00       	and    $0x7e0,%eax
 10091cc:	48 83 c0 e0          	add    $0xffffffffffffffe0,%rax
 10091d0:	48 c1 e8 03          	shr    $0x3,%rax
 10091d4:	49 89 47 10          	mov    %rax,0x10(%r15)
 10091d8:	49 c7 47 18 00 00 00 	movq   $0x0,0x18(%r15)
 10091df:	00 
 10091e0:	48 89 5c 24 20       	mov    %rbx,0x20(%rsp)
 10091e5:	48 be f3 59 37 98 22 	movabs $0x3759f22983759f3,%rsi
 10091ec:	9f 75 03 
 10091ef:	45 31 f6             	xor    %r14d,%r14d
 10091f2:	48 bf c3 00 cd 58 c2 	movabs $0x81e722c258cd00c3,%rdi
 10091f9:	22 e7 81 
 10091fc:	31 ed                	xor    %ebp,%ebp
 10091fe:	66 90                	xchg   %ax,%ax
 1009200:	48 39 ee             	cmp    %rbp,%rsi
 1009203:	0f 84 a9 02 00 00    	je     10094b2 <main+0x9f2>
 1009209:	4d 89 c5             	mov    %r8,%r13
 100920c:	4d 01 f5             	add    %r14,%r13
 100920f:	0f 80 ae 02 00 00    	jo     10094c3 <main+0xa03>
 1009215:	4c 89 ea             	mov    %r13,%rdx
 1009218:	c4 e2 e3 f6 df       	mulx   %rdi,%rbx,%rbx
 100921d:	49 8b 47 08          	mov    0x8(%r15),%rax
 1009221:	49 3b 47 10          	cmp    0x10(%r15),%rax
 1009225:	73 28                	jae    100924f <main+0x78f>
 1009227:	48 c1 eb 09          	shr    $0x9,%rbx
 100922b:	48 69 cb f1 03 00 00 	imul   $0x3f1,%rbx,%rcx
 1009232:	49 29 cd             	sub    %rcx,%r13
 1009235:	4d 89 6c c7 20       	mov    %r13,0x20(%r15,%rax,8)
 100923a:	48 ff c0             	inc    %rax
 100923d:	49 89 47 08          	mov    %rax,0x8(%r15)
 1009241:	48 ff c5             	inc    %rbp
 1009244:	49 83 c6 25          	add    $0x25,%r14
 1009248:	49 39 ec             	cmp    %rbp,%r12
 100924b:	75 b3                	jne    1009200 <main+0x740>
 100924d:	eb 30                	jmp    100927f <main+0x7bf>
 100924f:	be 08 00 00 00       	mov    $0x8,%esi
 1009254:	4c 89 ff             	mov    %r15,%rdi
 1009257:	4d 89 c7             	mov    %r8,%r15
 100925a:	e8 91 08 00 00       	call   1009af0 <myl_core_list_grow>
 100925f:	48 bf c3 00 cd 58 c2 	movabs $0x81e722c258cd00c3,%rdi
 1009266:	22 e7 81 
 1009269:	48 be f3 59 37 98 22 	movabs $0x3759f22983759f3,%rsi
 1009270:	9f 75 03 
 1009273:	4d 89 f8             	mov    %r15,%r8
 1009276:	49 89 c7             	mov    %rax,%r15
 1009279:	48 8b 40 08          	mov    0x8(%rax),%rax
 100927d:	eb a8                	jmp    1009227 <main+0x767>
 100927f:	48 8d 3d da b6 02 00 	lea    0x2b6da(%rip),%rdi        # 1034960 <fcntl@plt+0x10d0>
 1009286:	e8 35 18 00 00       	call   100aac0 <myl_core_io_at>
 100928b:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 1009290:	e8 9b 97 01 00       	call   1022a30 <myl_core_host_check>
 1009295:	31 ed                	xor    %ebp,%ebp
 1009297:	e8 04 a1 02 00       	call   10333a0 <runtime_bench_now>
 100929c:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
 10092a1:	49 ba f1 f0 f0 f0 f0 	movabs $0xf0f0f0f0f0f0f0f1,%r10
 10092a8:	f0 f0 f0 
 10092ab:	48 8d 0d ce b7 02 00 	lea    0x2b7ce(%rip),%rcx        # 1034a80 <fcntl@plt+0x11f0>
 10092b2:	4c 8d 0d 97 b7 02 00 	lea    0x2b797(%rip),%r9        # 1034a50 <fcntl@plt+0x11c0>
 10092b9:	48 bb e5 8f a2 12 31 	movabs $0x89705f3112a28fe5,%rbx
 10092c0:	5f 70 89 
 10092c3:	45 31 c0             	xor    %r8d,%r8d
 10092c6:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 10092cd:	00 00 00 
 10092d0:	4c 89 c2             	mov    %r8,%rdx
 10092d3:	c4 c2 fb f6 c2       	mulx   %r10,%rax,%rax
 10092d8:	48 89 c2             	mov    %rax,%rdx
 10092db:	48 83 e2 f0          	and    $0xfffffffffffffff0,%rdx
 10092df:	48 c1 e8 04          	shr    $0x4,%rax
 10092e3:	48 01 d0             	add    %rdx,%rax
 10092e6:	4d 89 c6             	mov    %r8,%r14
 10092e9:	49 29 c6             	sub    %rax,%r14
 10092ec:	31 f6                	xor    %esi,%esi
 10092ee:	45 31 ed             	xor    %r13d,%r13d
 10092f1:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10092f8:	0f 1f 84 00 00 00 00 
 10092ff:	00 
 1009300:	4b 8b 54 ef 20       	mov    0x20(%r15,%r13,8),%rdx
 1009305:	69 c2 cd cc ff ff    	imul   $0xffffcccd,%edx,%eax
 100930b:	0f b7 c0             	movzwl %ax,%eax
 100930e:	3d 33 33 00 00       	cmp    $0x3333,%eax
 1009313:	76 29                	jbe    100933e <main+0x87e>
 1009315:	4c 01 f2             	add    %r14,%rdx
 1009318:	31 c0                	xor    %eax,%eax
 100931a:	3c 01                	cmp    $0x1,%al
 100931c:	74 33                	je     1009351 <main+0x891>
 100931e:	48 8d 04 52          	lea    (%rdx,%rdx,2),%rax
 1009322:	48 ff c0             	inc    %rax
 1009325:	48 89 f2             	mov    %rsi,%rdx
 1009328:	48 01 c2             	add    %rax,%rdx
 100932b:	0f 80 65 01 00 00    	jo     1009496 <main+0x9d6>
 1009331:	49 ff c5             	inc    %r13
 1009334:	48 89 d6             	mov    %rdx,%rsi
 1009337:	4d 39 ec             	cmp    %r13,%r12
 100933a:	75 c4                	jne    1009300 <main+0x840>
 100933c:	eb 32                	jmp    1009370 <main+0x8b0>
 100933e:	48 89 cf             	mov    %rcx,%rdi
 1009341:	e8 2c 9e 02 00       	call   1033172 <myl_core_err_trace_origin_preserve_most>
 1009346:	ba 01 00 00 00       	mov    $0x1,%edx
 100934b:	b0 01                	mov    $0x1,%al
 100934d:	3c 01                	cmp    $0x1,%al
 100934f:	75 cd                	jne    100931e <main+0x85e>
 1009351:	4c 89 cf             	mov    %r9,%rdi
 1009354:	e8 31 9e 02 00       	call   103318a <myl_core_err_trace_append_preserve_most>
 1009359:	48 8d 04 d5 00 00 00 	lea    0x0(,%rdx,8),%rax
 1009360:	00 
 1009361:	48 29 d0             	sub    %rdx,%rax
 1009364:	eb bf                	jmp    1009325 <main+0x865>
 1009366:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 100936d:	00 00 00 
 1009370:	48 89 d6             	mov    %rdx,%rsi
 1009373:	48 01 ee             	add    %rbp,%rsi
 1009376:	0f 80 59 01 00 00    	jo     10094d5 <main+0xa15>
 100937c:	48 89 f0             	mov    %rsi,%rax
 100937f:	48 f7 eb             	imul   %rbx
 1009382:	48 01 f2             	add    %rsi,%rdx
 1009385:	48 89 d0             	mov    %rdx,%rax
 1009388:	48 c1 e8 3f          	shr    $0x3f,%rax
 100938c:	48 c1 fa 1d          	sar    $0x1d,%rdx
 1009390:	48 01 c2             	add    %rax,%rdx
 1009393:	48 69 c2 07 ca 9a 3b 	imul   $0x3b9aca07,%rdx,%rax
 100939a:	48 29 c6             	sub    %rax,%rsi
 100939d:	48 89 f5             	mov    %rsi,%rbp
 10093a0:	48 c1 fd 3f          	sar    $0x3f,%rbp
 10093a4:	81 e5 07 ca 9a 3b    	and    $0x3b9aca07,%ebp
 10093aa:	48 01 f5             	add    %rsi,%rbp
 10093ad:	49 ff c0             	inc    %r8
 10093b0:	4c 3b 04 24          	cmp    (%rsp),%r8
 10093b4:	0f 85 16 ff ff ff    	jne    10092d0 <main+0x810>
 10093ba:	41 0f b6 47 07       	movzbl 0x7(%r15),%eax
 10093bf:	48 85 c0             	test   %rax,%rax
 10093c2:	0f 84 dd 00 00 00    	je     10094a5 <main+0x9e5>
 10093c8:	49 83 7f 18 00       	cmpq   $0x0,0x18(%r15)
 10093cd:	0f 85 d2 00 00 00    	jne    10094a5 <main+0x9e5>
 10093d3:	48 8d 0d a6 f6 04 00 	lea    0x4f6a6(%rip),%rcx        # 1058a80 <myl_core_free_lists>
 10093da:	48 8b 14 c1          	mov    (%rcx,%rax,8),%rdx
 10093de:	49 89 17             	mov    %rdx,(%r15)
 10093e1:	4c 89 3c c1          	mov    %r15,(%rcx,%rax,8)
 10093e5:	48 8b 5c 24 10       	mov    0x10(%rsp),%rbx
 10093ea:	4c 8b 74 24 18       	mov    0x18(%rsp),%r14
 10093ef:	48 8d 3d 9a b5 02 00 	lea    0x2b59a(%rip),%rdi        # 1034990 <fcntl@plt+0x1100>
 10093f6:	e8 c5 16 00 00       	call   100aac0 <myl_core_io_at>
 10093fb:	48 89 df             	mov    %rbx,%rdi
 10093fe:	e8 2d 96 01 00       	call   1022a30 <myl_core_host_check>
 1009403:	e8 98 9f 02 00       	call   10333a0 <runtime_bench_now>
 1009408:	48 89 c3             	mov    %rax,%rbx
 100940b:	4c 29 f3             	sub    %r14,%rbx
 100940e:	0f 80 f2 00 00 00    	jo     1009506 <main+0xa46>
 1009414:	bf 01 00 00 00       	mov    $0x1,%edi
 1009419:	48 89 ee             	mov    %rbp,%rsi
 100941c:	e8 9f 1d 00 00       	call   100b1c0 <myl_core_print_i64>
 1009421:	bf 01 00 00 00       	mov    $0x1,%edi
 1009426:	e8 d5 03 00 00       	call   1009800 <myl_core_print_sep>
 100942b:	bf 01 00 00 00       	mov    $0x1,%edi
 1009430:	48 89 de             	mov    %rbx,%rsi
 1009433:	e8 88 1d 00 00       	call   100b1c0 <myl_core_print_i64>
 1009438:	bf 01 00 00 00       	mov    $0x1,%edi
 100943d:	e8 7e 04 00 00       	call   10098c0 <myl_core_print_end>
 1009442:	45 31 ff             	xor    %r15d,%r15d
 1009445:	48 8b 5c 24 20       	mov    0x20(%rsp),%rbx
 100944a:	48 89 df             	mov    %rbx,%rdi
 100944d:	e8 6e 0b 00 00       	call   1009fc0 <myl_core_release>
 1009452:	4c 89 ff             	mov    %r15,%rdi
 1009455:	e8 76 16 00 00       	call   100aad0 <myl_core_exit>
 100945a:	48 83 c4 28          	add    $0x28,%rsp
 100945e:	5b                   	pop    %rbx
 100945f:	41 5c                	pop    %r12
 1009461:	41 5d                	pop    %r13
 1009463:	41 5e                	pop    %r14
 1009465:	41 5f                	pop    %r15
 1009467:	5d                   	pop    %rbp
 1009468:	c3                   	ret
 1009469:	31 c9                	xor    %ecx,%ecx
 100946b:	31 d2                	xor    %edx,%edx
 100946d:	f6 c1 01             	test   $0x1,%cl
 1009470:	0f 85 00 fc ff ff    	jne    1009076 <main+0x5b6>
 1009476:	e9 af fc ff ff       	jmp    100912a <main+0x66a>
 100947b:	be 08 00 00 00       	mov    $0x8,%esi
 1009480:	4c 89 e7             	mov    %r12,%rdi
 1009483:	4d 89 c6             	mov    %r8,%r14
 1009486:	e8 f5 05 00 00       	call   1009a80 <myl_core_list_new_slow>
 100948b:	4d 89 f0             	mov    %r14,%r8
 100948e:	49 89 c7             	mov    %rax,%r15
 1009491:	e9 4a fd ff ff       	jmp    10091e0 <main+0x720>
 1009496:	48 8d 3d 83 b5 02 00 	lea    0x2b583(%rip),%rdi        # 1034a20 <fcntl@plt+0x1190>
 100949d:	48 89 c2             	mov    %rax,%rdx
 10094a0:	e8 db 0c 00 00       	call   100a180 <myl_core_trap>
 10094a5:	4c 89 ff             	mov    %r15,%rdi
 10094a8:	e8 e3 98 02 00       	call   1032d90 <myl_core_free_block>
 10094ad:	e9 33 ff ff ff       	jmp    10093e5 <main+0x925>
 10094b2:	48 8d 3d 47 b4 02 00 	lea    0x2b447(%rip),%rdi        # 1034900 <fcntl@plt+0x1070>
 10094b9:	ba 25 00 00 00       	mov    $0x25,%edx
 10094be:	e8 bd 0c 00 00       	call   100a180 <myl_core_trap>
 10094c3:	48 8d 3d 66 b4 02 00 	lea    0x2b466(%rip),%rdi        # 1034930 <fcntl@plt+0x10a0>
 10094ca:	4c 89 c6             	mov    %r8,%rsi
 10094cd:	4c 89 f2             	mov    %r14,%rdx
 10094d0:	e8 ab 0c 00 00       	call   100a180 <myl_core_trap>
 10094d5:	48 8d 3d 14 b5 02 00 	lea    0x2b514(%rip),%rdi        # 10349f0 <fcntl@plt+0x1160>
 10094dc:	48 89 ee             	mov    %rbp,%rsi
 10094df:	e8 9c 0c 00 00       	call   100a180 <myl_core_trap>
 10094e4:	48 8d 3d e5 b3 02 00 	lea    0x2b3e5(%rip),%rdi        # 10348d0 <fcntl@plt+0x1040>
 10094eb:	be 02 00 00 00       	mov    $0x2,%esi
 10094f0:	e8 8b 0c 00 00       	call   100a180 <myl_core_trap>
 10094f5:	48 8d 3d a4 b3 02 00 	lea    0x2b3a4(%rip),%rdi        # 10348a0 <fcntl@plt+0x1010>
 10094fc:	be 01 00 00 00       	mov    $0x1,%esi
 1009501:	e8 7a 0c 00 00       	call   100a180 <myl_core_trap>
 1009506:	48 8d 3d b3 b4 02 00 	lea    0x2b4b3(%rip),%rdi        # 10349c0 <fcntl@plt+0x1130>
 100950d:	48 89 c6             	mov    %rax,%rsi
 1009510:	4c 89 f2             	mov    %r14,%rdx
 1009513:	e8 68 0c 00 00       	call   100a180 <myl_core_trap>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
