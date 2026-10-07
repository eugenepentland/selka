
experiments/new-core-s4-emission-20261006/entry-attributes-01/result_propagate/baseline/program:     file format elf64-x86-64


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
 1032966:	0f 85 5e 09 00 00    	jne    10332ca <main+0x98a>
 103296c:	49 89 c6             	mov    %rax,%r14
 103296f:	48 8b 7b 20          	mov    0x20(%rbx),%rdi
 1032973:	48 8b 4f 08          	mov    0x8(%rdi),%rcx
 1032977:	48 85 c9             	test   %rcx,%rcx
 103297a:	74 6a                	je     10329e6 <main+0xa6>
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
 10329a6:	75 2c                	jne    10329d4 <main+0x94>
 10329a8:	45 8d 48 d0          	lea    -0x30(%r8),%r9d
 10329ac:	41 80 f9 0a          	cmp    $0xa,%r9b
 10329b0:	73 22                	jae    10329d4 <main+0x94>
 10329b2:	40 88 f2             	mov    %sil,%dl
 10329b5:	48 29 d1             	sub    %rdx,%rcx
 10329b8:	48 83 f9 08          	cmp    $0x8,%rcx
 10329bc:	0f 87 99 01 00 00    	ja     1032b5b <main+0x21b>
 10329c2:	48 8d 77 20          	lea    0x20(%rdi),%rsi
 10329c6:	48 01 d6             	add    %rdx,%rsi
 10329c9:	48 83 f9 08          	cmp    $0x8,%rcx
 10329cd:	75 24                	jne    10329f3 <main+0xb3>
 10329cf:	48 8b 16             	mov    (%rsi),%rdx
 10329d2:	eb 3f                	jmp    1032a13 <main+0xd3>
 10329d4:	3c 21                	cmp    $0x21,%al
 10329d6:	0f 82 7f 01 00 00    	jb     1032b5b <main+0x21b>
 10329dc:	41 80 f8 21          	cmp    $0x21,%r8b
 10329e0:	0f 82 75 01 00 00    	jb     1032b5b <main+0x21b>
 10329e6:	45 31 e4             	xor    %r12d,%r12d
 10329e9:	ba 03 00 00 00       	mov    $0x3,%edx
 10329ee:	e9 8e 01 00 00       	jmp    1032b81 <main+0x241>
 10329f3:	48 83 f9 04          	cmp    $0x4,%rcx
 10329f7:	0f 86 cd 00 00 00    	jbe    1032aca <main+0x18a>
 10329fd:	44 8b 06             	mov    (%rsi),%r8d
 1032a00:	48 8d 51 fc          	lea    -0x4(%rcx),%rdx
 1032a04:	8b 74 0e fc          	mov    -0x4(%rsi,%rcx,1),%esi
 1032a08:	c1 e2 03             	shl    $0x3,%edx
 1032a0b:	c4 e2 e9 f7 d6       	shlx   %rdx,%rsi,%rdx
 1032a10:	4c 09 c2             	or     %r8,%rdx
 1032a13:	c1 e1 03             	shl    $0x3,%ecx
 1032a16:	89 ce                	mov    %ecx,%esi
 1032a18:	40 f6 de             	neg    %sil
 1032a1b:	c4 e2 c9 f7 d2       	shlx   %rsi,%rdx,%rdx
 1032a20:	40 b6 40             	mov    $0x40,%sil
 1032a23:	40 28 ce             	sub    %cl,%sil
 1032a26:	48 b9 30 30 30 30 30 	movabs $0x30303030303030,%rcx
 1032a2d:	30 30 00 
 1032a30:	c4 e2 c8 f5 c9       	bzhi   %rsi,%rcx,%rcx
 1032a35:	48 09 d1             	or     %rdx,%rcx
 1032a38:	48 ba d0 cf cf cf cf 	movabs $0xcfcfcfcfcfcfcfd0,%rdx
 1032a3f:	cf cf cf 
 1032a42:	48 01 ca             	add    %rcx,%rdx
 1032a45:	48 be 46 46 46 46 46 	movabs $0x4646464646464646,%rsi
 1032a4c:	46 46 46 
 1032a4f:	48 01 ce             	add    %rcx,%rsi
 1032a52:	48 09 d6             	or     %rdx,%rsi
 1032a55:	48 b9 80 80 80 80 80 	movabs $0x8080808080808080,%rcx
 1032a5c:	80 80 80 
 1032a5f:	48 85 ce             	test   %rcx,%rsi
 1032a62:	0f 94 c1             	sete   %cl
 1032a65:	48 8d 34 92          	lea    (%rdx,%rdx,4),%rsi
 1032a69:	48 c1 ea 08          	shr    $0x8,%rdx
 1032a6d:	48 8d 14 72          	lea    (%rdx,%rsi,2),%rdx
 1032a71:	48 89 d6             	mov    %rdx,%rsi
 1032a74:	48 c1 ee 10          	shr    $0x10,%rsi
 1032a78:	49 b8 ff 00 00 00 ff 	movabs $0xff000000ff,%r8
 1032a7f:	00 00 00 
 1032a82:	4c 21 c2             	and    %r8,%rdx
 1032a85:	4c 21 c6             	and    %r8,%rsi
 1032a88:	49 b8 64 00 00 00 40 	movabs $0xf424000000064,%r8
 1032a8f:	42 0f 00 
 1032a92:	4c 0f af c2          	imul   %rdx,%r8
 1032a96:	48 ba 01 00 00 00 10 	movabs $0x271000000001,%rdx
 1032a9d:	27 00 00 
 1032aa0:	48 0f af d6          	imul   %rsi,%rdx
 1032aa4:	4c 01 c2             	add    %r8,%rdx
 1032aa7:	48 c1 ea 20          	shr    $0x20,%rdx
 1032aab:	f6 c1 01             	test   $0x1,%cl
 1032aae:	0f 84 a7 00 00 00    	je     1032b5b <main+0x21b>
 1032ab4:	49 89 d4             	mov    %rdx,%r12
 1032ab7:	49 f7 dc             	neg    %r12
 1032aba:	3c 2d                	cmp    $0x2d,%al
 1032abc:	4c 0f 45 e2          	cmovne %rdx,%r12
 1032ac0:	ba 03 00 00 00       	mov    $0x3,%edx
 1032ac5:	e9 b7 00 00 00       	jmp    1032b81 <main+0x241>
 1032aca:	48 8d 51 ff          	lea    -0x1(%rcx),%rdx
 1032ace:	48 83 fa 03          	cmp    $0x3,%rdx
 1032ad2:	0f 87 2a 02 00 00    	ja     1032d02 <main+0x3c2>
 1032ad8:	4c 8d 05 e1 1a fd ff 	lea    -0x2e51f(%rip),%r8        # 10045c0 <core_number_pairs+0xd0>
 1032adf:	49 63 14 90          	movslq (%r8,%rdx,4),%rdx
 1032ae3:	4c 01 c2             	add    %r8,%rdx
 1032ae6:	ff e2                	jmp    *%rdx
 1032ae8:	0f b6 16             	movzbl (%rsi),%edx
 1032aeb:	eb 17                	jmp    1032b04 <main+0x1c4>
 1032aed:	44 0f b7 06          	movzwl (%rsi),%r8d
 1032af1:	0f b6 56 02          	movzbl 0x2(%rsi),%edx
 1032af5:	c1 e2 10             	shl    $0x10,%edx
 1032af8:	44 09 c2             	or     %r8d,%edx
 1032afb:	eb 07                	jmp    1032b04 <main+0x1c4>
 1032afd:	8b 16                	mov    (%rsi),%edx
 1032aff:	eb 03                	jmp    1032b04 <main+0x1c4>
 1032b01:	0f b7 16             	movzwl (%rsi),%edx
 1032b04:	c1 e1 03             	shl    $0x3,%ecx
 1032b07:	89 ce                	mov    %ecx,%esi
 1032b09:	40 f6 de             	neg    %sil
 1032b0c:	c4 e2 49 f7 d2       	shlx   %esi,%edx,%edx
 1032b11:	40 b6 20             	mov    $0x20,%sil
 1032b14:	40 28 ce             	sub    %cl,%sil
 1032b17:	b9 30 30 30 00       	mov    $0x303030,%ecx
 1032b1c:	c4 e2 48 f5 c9       	bzhi   %esi,%ecx,%ecx
 1032b21:	09 d1                	or     %edx,%ecx
 1032b23:	8d 91 d0 cf cf cf    	lea    -0x30303030(%rcx),%edx
 1032b29:	81 c1 46 46 46 46    	add    $0x46464646,%ecx
 1032b2f:	09 d1                	or     %edx,%ecx
 1032b31:	f7 c1 80 80 80 80    	test   $0x80808080,%ecx
 1032b37:	0f 94 c1             	sete   %cl
 1032b3a:	69 d2 01 0a 00 00    	imul   $0xa01,%edx,%edx
 1032b40:	c1 ea 08             	shr    $0x8,%edx
 1032b43:	81 e2 ff 00 ff 00    	and    $0xff00ff,%edx
 1032b49:	69 d2 01 00 64 00    	imul   $0x640001,%edx,%edx
 1032b4f:	c1 ea 10             	shr    $0x10,%edx
 1032b52:	f6 c1 01             	test   $0x1,%cl
 1032b55:	0f 85 59 ff ff ff    	jne    1032ab4 <main+0x174>
 1032b5b:	48 8d 74 24 08       	lea    0x8(%rsp),%rsi
 1032b60:	e8 6b c1 fe ff       	call   101ecd0 <myl_core_str_parse_int>
 1032b65:	a8 01                	test   $0x1,%al
 1032b67:	74 07                	je     1032b70 <main+0x230>
 1032b69:	4c 8b 64 24 08       	mov    0x8(%rsp),%r12
 1032b6e:	eb 03                	jmp    1032b73 <main+0x233>
 1032b70:	45 31 e4             	xor    %r12d,%r12d
 1032b73:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 1032b77:	48 83 fa 01          	cmp    $0x1,%rdx
 1032b7b:	0f 86 f4 07 00 00    	jbe    1033375 <main+0xa35>
 1032b81:	48 8b 7b 28          	mov    0x28(%rbx),%rdi
 1032b85:	48 8b 4f 08          	mov    0x8(%rdi),%rcx
 1032b89:	48 85 c9             	test   %rcx,%rcx
 1032b8c:	74 6b                	je     1032bf9 <main+0x2b9>
 1032b8e:	0f b6 47 20          	movzbl 0x20(%rdi),%eax
 1032b92:	44 8d 40 d5          	lea    -0x2b(%rax),%r8d
 1032b96:	31 f6                	xor    %esi,%esi
 1032b98:	41 f6 c0 fd          	test   $0xfd,%r8b
 1032b9c:	41 0f 94 c0          	sete   %r8b
 1032ba0:	41 0f 95 c2          	setne  %r10b
 1032ba4:	44 8d 48 d0          	lea    -0x30(%rax),%r9d
 1032ba8:	41 80 f9 0a          	cmp    $0xa,%r9b
 1032bac:	41 0f 93 c3          	setae  %r11b
 1032bb0:	44 0f b6 4c 0f 1f    	movzbl 0x1f(%rdi,%rcx,1),%r9d
 1032bb6:	45 84 d3             	test   %r10b,%r11b
 1032bb9:	75 2c                	jne    1032be7 <main+0x2a7>
 1032bbb:	45 8d 51 d0          	lea    -0x30(%r9),%r10d
 1032bbf:	41 80 fa 0a          	cmp    $0xa,%r10b
 1032bc3:	73 22                	jae    1032be7 <main+0x2a7>
 1032bc5:	44 88 c6             	mov    %r8b,%sil
 1032bc8:	48 29 f1             	sub    %rsi,%rcx
 1032bcb:	48 83 f9 08          	cmp    $0x8,%rcx
 1032bcf:	0f 87 b1 01 00 00    	ja     1032d86 <main+0x446>
 1032bd5:	4c 8d 47 20          	lea    0x20(%rdi),%r8
 1032bd9:	49 01 f0             	add    %rsi,%r8
 1032bdc:	48 83 f9 08          	cmp    $0x8,%rcx
 1032be0:	75 24                	jne    1032c06 <main+0x2c6>
 1032be2:	49 8b 30             	mov    (%r8),%rsi
 1032be5:	eb 40                	jmp    1032c27 <main+0x2e7>
 1032be7:	3c 21                	cmp    $0x21,%al
 1032be9:	0f 82 97 01 00 00    	jb     1032d86 <main+0x446>
 1032bef:	41 80 f9 21          	cmp    $0x21,%r9b
 1032bf3:	0f 82 8d 01 00 00    	jb     1032d86 <main+0x446>
 1032bf9:	48 c7 04 24 00 00 00 	movq   $0x0,(%rsp)
 1032c00:	00 
 1032c01:	e9 a5 01 00 00       	jmp    1032dab <main+0x46b>
 1032c06:	48 83 f9 04          	cmp    $0x4,%rcx
 1032c0a:	0f 86 ce 00 00 00    	jbe    1032cde <main+0x39e>
 1032c10:	45 8b 08             	mov    (%r8),%r9d
 1032c13:	48 8d 71 fc          	lea    -0x4(%rcx),%rsi
 1032c17:	45 8b 44 08 fc       	mov    -0x4(%r8,%rcx,1),%r8d
 1032c1c:	c1 e6 03             	shl    $0x3,%esi
 1032c1f:	c4 c2 c9 f7 f0       	shlx   %rsi,%r8,%rsi
 1032c24:	4c 09 ce             	or     %r9,%rsi
 1032c27:	c1 e1 03             	shl    $0x3,%ecx
 1032c2a:	41 89 c8             	mov    %ecx,%r8d
 1032c2d:	41 f6 d8             	neg    %r8b
 1032c30:	c4 e2 b9 f7 f6       	shlx   %r8,%rsi,%rsi
 1032c35:	41 b0 40             	mov    $0x40,%r8b
 1032c38:	41 28 c8             	sub    %cl,%r8b
 1032c3b:	48 b9 30 30 30 30 30 	movabs $0x30303030303030,%rcx
 1032c42:	30 30 00 
 1032c45:	c4 e2 b8 f5 c9       	bzhi   %r8,%rcx,%rcx
 1032c4a:	48 09 f1             	or     %rsi,%rcx
 1032c4d:	48 be d0 cf cf cf cf 	movabs $0xcfcfcfcfcfcfcfd0,%rsi
 1032c54:	cf cf cf 
 1032c57:	48 01 ce             	add    %rcx,%rsi
 1032c5a:	49 b8 46 46 46 46 46 	movabs $0x4646464646464646,%r8
 1032c61:	46 46 46 
 1032c64:	49 01 c8             	add    %rcx,%r8
 1032c67:	49 09 f0             	or     %rsi,%r8
 1032c6a:	48 b9 80 80 80 80 80 	movabs $0x8080808080808080,%rcx
 1032c71:	80 80 80 
 1032c74:	49 85 c8             	test   %rcx,%r8
 1032c77:	0f 94 c1             	sete   %cl
 1032c7a:	4c 8d 04 b6          	lea    (%rsi,%rsi,4),%r8
 1032c7e:	48 c1 ee 08          	shr    $0x8,%rsi
 1032c82:	4a 8d 34 46          	lea    (%rsi,%r8,2),%rsi
 1032c86:	49 89 f0             	mov    %rsi,%r8
 1032c89:	49 c1 e8 10          	shr    $0x10,%r8
 1032c8d:	49 b9 ff 00 00 00 ff 	movabs $0xff000000ff,%r9
 1032c94:	00 00 00 
 1032c97:	4c 21 ce             	and    %r9,%rsi
 1032c9a:	4d 21 c8             	and    %r9,%r8
 1032c9d:	49 b9 64 00 00 00 40 	movabs $0xf424000000064,%r9
 1032ca4:	42 0f 00 
 1032ca7:	4c 0f af ce          	imul   %rsi,%r9
 1032cab:	48 be 01 00 00 00 10 	movabs $0x271000000001,%rsi
 1032cb2:	27 00 00 
 1032cb5:	49 0f af f0          	imul   %r8,%rsi
 1032cb9:	4c 01 ce             	add    %r9,%rsi
 1032cbc:	48 c1 ee 20          	shr    $0x20,%rsi
 1032cc0:	f6 c1 01             	test   $0x1,%cl
 1032cc3:	0f 84 bd 00 00 00    	je     1032d86 <main+0x446>
 1032cc9:	48 89 f1             	mov    %rsi,%rcx
 1032ccc:	48 f7 d9             	neg    %rcx
 1032ccf:	3c 2d                	cmp    $0x2d,%al
 1032cd1:	48 0f 45 ce          	cmovne %rsi,%rcx
 1032cd5:	48 89 0c 24          	mov    %rcx,(%rsp)
 1032cd9:	e9 cd 00 00 00       	jmp    1032dab <main+0x46b>
 1032cde:	48 8d 71 ff          	lea    -0x1(%rcx),%rsi
 1032ce2:	48 83 fe 03          	cmp    $0x3,%rsi
 1032ce6:	0f 87 3e 02 00 00    	ja     1032f2a <main+0x5ea>
 1032cec:	4c 8d 0d dd 18 fd ff 	lea    -0x2e723(%rip),%r9        # 10045d0 <core_number_pairs+0xe0>
 1032cf3:	49 63 34 b1          	movslq (%r9,%rsi,4),%rsi
 1032cf7:	4c 01 ce             	add    %r9,%rsi
 1032cfa:	ff e6                	jmp    *%rsi
 1032cfc:	41 0f b6 30          	movzbl (%r8),%esi
 1032d00:	eb 2c                	jmp    1032d2e <main+0x3ee>
 1032d02:	31 c9                	xor    %ecx,%ecx
 1032d04:	31 d2                	xor    %edx,%edx
 1032d06:	f6 c1 01             	test   $0x1,%cl
 1032d09:	0f 85 a5 fd ff ff    	jne    1032ab4 <main+0x174>
 1032d0f:	e9 47 fe ff ff       	jmp    1032b5b <main+0x21b>
 1032d14:	45 0f b7 08          	movzwl (%r8),%r9d
 1032d18:	41 0f b6 70 02       	movzbl 0x2(%r8),%esi
 1032d1d:	c1 e6 10             	shl    $0x10,%esi
 1032d20:	44 09 ce             	or     %r9d,%esi
 1032d23:	eb 09                	jmp    1032d2e <main+0x3ee>
 1032d25:	41 8b 30             	mov    (%r8),%esi
 1032d28:	eb 04                	jmp    1032d2e <main+0x3ee>
 1032d2a:	41 0f b7 30          	movzwl (%r8),%esi
 1032d2e:	c1 e1 03             	shl    $0x3,%ecx
 1032d31:	41 89 c8             	mov    %ecx,%r8d
 1032d34:	41 f6 d8             	neg    %r8b
 1032d37:	c4 e2 39 f7 f6       	shlx   %r8d,%esi,%esi
 1032d3c:	41 b0 20             	mov    $0x20,%r8b
 1032d3f:	41 28 c8             	sub    %cl,%r8b
 1032d42:	b9 30 30 30 00       	mov    $0x303030,%ecx
 1032d47:	c4 e2 38 f5 c9       	bzhi   %r8d,%ecx,%ecx
 1032d4c:	09 f1                	or     %esi,%ecx
 1032d4e:	8d b1 d0 cf cf cf    	lea    -0x30303030(%rcx),%esi
 1032d54:	81 c1 46 46 46 46    	add    $0x46464646,%ecx
 1032d5a:	09 f1                	or     %esi,%ecx
 1032d5c:	f7 c1 80 80 80 80    	test   $0x80808080,%ecx
 1032d62:	0f 94 c1             	sete   %cl
 1032d65:	69 f6 01 0a 00 00    	imul   $0xa01,%esi,%esi
 1032d6b:	c1 ee 08             	shr    $0x8,%esi
 1032d6e:	81 e6 ff 00 ff 00    	and    $0xff00ff,%esi
 1032d74:	69 f6 01 00 64 00    	imul   $0x640001,%esi,%esi
 1032d7a:	c1 ee 10             	shr    $0x10,%esi
 1032d7d:	f6 c1 01             	test   $0x1,%cl
 1032d80:	0f 85 43 ff ff ff    	jne    1032cc9 <main+0x389>
 1032d86:	48 8d 74 24 08       	lea    0x8(%rsp),%rsi
 1032d8b:	e8 40 bf fe ff       	call   101ecd0 <myl_core_str_parse_int>
 1032d90:	a8 01                	test   $0x1,%al
 1032d92:	74 0b                	je     1032d9f <main+0x45f>
 1032d94:	48 8b 44 24 08       	mov    0x8(%rsp),%rax
 1032d99:	48 89 04 24          	mov    %rax,(%rsp)
 1032d9d:	eb 08                	jmp    1032da7 <main+0x467>
 1032d9f:	48 c7 04 24 00 00 00 	movq   $0x0,(%rsp)
 1032da6:	00 
 1032da7:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 1032dab:	48 83 fa 02          	cmp    $0x2,%rdx
 1032daf:	0f 86 af 05 00 00    	jbe    1033364 <main+0xa24>
 1032db5:	48 8b 7b 30          	mov    0x30(%rbx),%rdi
 1032db9:	48 8b 4f 08          	mov    0x8(%rdi),%rcx
 1032dbd:	48 85 c9             	test   %rcx,%rcx
 1032dc0:	0f 84 04 05 00 00    	je     10332ca <main+0x98a>
 1032dc6:	0f b6 47 20          	movzbl 0x20(%rdi),%eax
 1032dca:	8d 70 d5             	lea    -0x2b(%rax),%esi
 1032dcd:	31 d2                	xor    %edx,%edx
 1032dcf:	40 f6 c6 fd          	test   $0xfd,%sil
 1032dd3:	40 0f 94 c6          	sete   %sil
 1032dd7:	41 0f 95 c1          	setne  %r9b
 1032ddb:	44 8d 40 d0          	lea    -0x30(%rax),%r8d
 1032ddf:	41 80 f8 0a          	cmp    $0xa,%r8b
 1032de3:	41 0f 93 c2          	setae  %r10b
 1032de7:	44 0f b6 44 0f 1f    	movzbl 0x1f(%rdi,%rcx,1),%r8d
 1032ded:	45 84 ca             	test   %r9b,%r10b
 1032df0:	75 2c                	jne    1032e1e <main+0x4de>
 1032df2:	45 8d 48 d0          	lea    -0x30(%r8),%r9d
 1032df6:	41 80 f9 0a          	cmp    $0xa,%r9b
 1032dfa:	73 22                	jae    1032e1e <main+0x4de>
 1032dfc:	40 88 f2             	mov    %sil,%dl
 1032dff:	48 29 d1             	sub    %rdx,%rcx
 1032e02:	48 83 f9 08          	cmp    $0x8,%rcx
 1032e06:	0f 87 9e 01 00 00    	ja     1032faa <main+0x66a>
 1032e0c:	48 8d 77 20          	lea    0x20(%rdi),%rsi
 1032e10:	48 01 d6             	add    %rdx,%rsi
 1032e13:	48 83 f9 08          	cmp    $0x8,%rcx
 1032e17:	75 1c                	jne    1032e35 <main+0x4f5>
 1032e19:	48 8b 16             	mov    (%rsi),%rdx
 1032e1c:	eb 37                	jmp    1032e55 <main+0x515>
 1032e1e:	3c 21                	cmp    $0x21,%al
 1032e20:	0f 82 84 01 00 00    	jb     1032faa <main+0x66a>
 1032e26:	41 80 f8 21          	cmp    $0x21,%r8b
 1032e2a:	0f 83 9a 04 00 00    	jae    10332ca <main+0x98a>
 1032e30:	e9 75 01 00 00       	jmp    1032faa <main+0x66a>
 1032e35:	48 83 f9 04          	cmp    $0x4,%rcx
 1032e39:	0f 86 c8 00 00 00    	jbe    1032f07 <main+0x5c7>
 1032e3f:	44 8b 06             	mov    (%rsi),%r8d
 1032e42:	48 8d 51 fc          	lea    -0x4(%rcx),%rdx
 1032e46:	8b 74 0e fc          	mov    -0x4(%rsi,%rcx,1),%esi
 1032e4a:	c1 e2 03             	shl    $0x3,%edx
 1032e4d:	c4 e2 e9 f7 d6       	shlx   %rdx,%rsi,%rdx
 1032e52:	4c 09 c2             	or     %r8,%rdx
 1032e55:	c1 e1 03             	shl    $0x3,%ecx
 1032e58:	89 ce                	mov    %ecx,%esi
 1032e5a:	40 f6 de             	neg    %sil
 1032e5d:	c4 e2 c9 f7 d2       	shlx   %rsi,%rdx,%rdx
 1032e62:	40 b6 40             	mov    $0x40,%sil
 1032e65:	40 28 ce             	sub    %cl,%sil
 1032e68:	48 b9 30 30 30 30 30 	movabs $0x30303030303030,%rcx
 1032e6f:	30 30 00 
 1032e72:	c4 e2 c8 f5 c9       	bzhi   %rsi,%rcx,%rcx
 1032e77:	48 09 d1             	or     %rdx,%rcx
 1032e7a:	48 ba d0 cf cf cf cf 	movabs $0xcfcfcfcfcfcfcfd0,%rdx
 1032e81:	cf cf cf 
 1032e84:	48 01 ca             	add    %rcx,%rdx
 1032e87:	48 be 46 46 46 46 46 	movabs $0x4646464646464646,%rsi
 1032e8e:	46 46 46 
 1032e91:	48 01 ce             	add    %rcx,%rsi
 1032e94:	48 09 d6             	or     %rdx,%rsi
 1032e97:	48 b9 80 80 80 80 80 	movabs $0x8080808080808080,%rcx
 1032e9e:	80 80 80 
 1032ea1:	48 85 ce             	test   %rcx,%rsi
 1032ea4:	0f 94 c1             	sete   %cl
 1032ea7:	48 8d 34 92          	lea    (%rdx,%rdx,4),%rsi
 1032eab:	48 c1 ea 08          	shr    $0x8,%rdx
 1032eaf:	48 8d 14 72          	lea    (%rdx,%rsi,2),%rdx
 1032eb3:	48 89 d6             	mov    %rdx,%rsi
 1032eb6:	48 c1 ee 10          	shr    $0x10,%rsi
 1032eba:	49 b8 ff 00 00 00 ff 	movabs $0xff000000ff,%r8
 1032ec1:	00 00 00 
 1032ec4:	4c 21 c2             	and    %r8,%rdx
 1032ec7:	4c 21 c6             	and    %r8,%rsi
 1032eca:	49 b8 64 00 00 00 40 	movabs $0xf424000000064,%r8
 1032ed1:	42 0f 00 
 1032ed4:	4c 0f af c2          	imul   %rdx,%r8
 1032ed8:	48 ba 01 00 00 00 10 	movabs $0x271000000001,%rdx
 1032edf:	27 00 00 
 1032ee2:	48 0f af d6          	imul   %rsi,%rdx
 1032ee6:	4c 01 c2             	add    %r8,%rdx
 1032ee9:	48 c1 ea 20          	shr    $0x20,%rdx
 1032eed:	f6 c1 01             	test   $0x1,%cl
 1032ef0:	0f 84 b4 00 00 00    	je     1032faa <main+0x66a>
 1032ef6:	49 89 d0             	mov    %rdx,%r8
 1032ef9:	49 f7 d8             	neg    %r8
 1032efc:	3c 2d                	cmp    $0x2d,%al
 1032efe:	4c 0f 45 c2          	cmovne %rdx,%r8
 1032f02:	e9 ba 00 00 00       	jmp    1032fc1 <main+0x681>
 1032f07:	48 8d 51 ff          	lea    -0x1(%rcx),%rdx
 1032f0b:	48 83 fa 03          	cmp    $0x3,%rdx
 1032f0f:	0f 87 d4 03 00 00    	ja     10332e9 <main+0x9a9>
 1032f15:	4c 8d 05 c4 16 fd ff 	lea    -0x2e93c(%rip),%r8        # 10045e0 <core_number_pairs+0xf0>
 1032f1c:	49 63 14 90          	movslq (%r8,%rdx,4),%rdx
 1032f20:	4c 01 c2             	add    %r8,%rdx
 1032f23:	ff e2                	jmp    *%rdx
 1032f25:	0f b6 16             	movzbl (%rsi),%edx
 1032f28:	eb 29                	jmp    1032f53 <main+0x613>
 1032f2a:	31 c9                	xor    %ecx,%ecx
 1032f2c:	31 f6                	xor    %esi,%esi
 1032f2e:	f6 c1 01             	test   $0x1,%cl
 1032f31:	0f 85 92 fd ff ff    	jne    1032cc9 <main+0x389>
 1032f37:	e9 4a fe ff ff       	jmp    1032d86 <main+0x446>
 1032f3c:	44 0f b7 06          	movzwl (%rsi),%r8d
 1032f40:	0f b6 56 02          	movzbl 0x2(%rsi),%edx
 1032f44:	c1 e2 10             	shl    $0x10,%edx
 1032f47:	44 09 c2             	or     %r8d,%edx
 1032f4a:	eb 07                	jmp    1032f53 <main+0x613>
 1032f4c:	8b 16                	mov    (%rsi),%edx
 1032f4e:	eb 03                	jmp    1032f53 <main+0x613>
 1032f50:	0f b7 16             	movzwl (%rsi),%edx
 1032f53:	c1 e1 03             	shl    $0x3,%ecx
 1032f56:	89 ce                	mov    %ecx,%esi
 1032f58:	40 f6 de             	neg    %sil
 1032f5b:	c4 e2 49 f7 d2       	shlx   %esi,%edx,%edx
 1032f60:	40 b6 20             	mov    $0x20,%sil
 1032f63:	40 28 ce             	sub    %cl,%sil
 1032f66:	b9 30 30 30 00       	mov    $0x303030,%ecx
 1032f6b:	c4 e2 48 f5 c9       	bzhi   %esi,%ecx,%ecx
 1032f70:	09 d1                	or     %edx,%ecx
 1032f72:	8d 91 d0 cf cf cf    	lea    -0x30303030(%rcx),%edx
 1032f78:	81 c1 46 46 46 46    	add    $0x46464646,%ecx
 1032f7e:	09 d1                	or     %edx,%ecx
 1032f80:	f7 c1 80 80 80 80    	test   $0x80808080,%ecx
 1032f86:	0f 94 c1             	sete   %cl
 1032f89:	69 d2 01 0a 00 00    	imul   $0xa01,%edx,%edx
 1032f8f:	c1 ea 08             	shr    $0x8,%edx
 1032f92:	81 e2 ff 00 ff 00    	and    $0xff00ff,%edx
 1032f98:	69 d2 01 00 64 00    	imul   $0x640001,%edx,%edx
 1032f9e:	c1 ea 10             	shr    $0x10,%edx
 1032fa1:	f6 c1 01             	test   $0x1,%cl
 1032fa4:	0f 85 4c ff ff ff    	jne    1032ef6 <main+0x5b6>
 1032faa:	48 8d 74 24 08       	lea    0x8(%rsp),%rsi
 1032faf:	e8 1c bd fe ff       	call   101ecd0 <myl_core_str_parse_int>
 1032fb4:	84 c0                	test   %al,%al
 1032fb6:	0f 84 0e 03 00 00    	je     10332ca <main+0x98a>
 1032fbc:	4c 8b 44 24 08       	mov    0x8(%rsp),%r8
 1032fc1:	49 83 fc 02          	cmp    $0x2,%r12
 1032fc5:	0f 8c ff 02 00 00    	jl     10332ca <main+0x98a>
 1032fcb:	48 83 3c 24 00       	cmpq   $0x0,(%rsp)
 1032fd0:	0f 8e f4 02 00 00    	jle    10332ca <main+0x98a>
 1032fd6:	49 8d 80 bf bd f0 ff 	lea    -0xf4241(%r8),%rax
 1032fdd:	48 3d c0 bd f0 ff    	cmp    $0xfffffffffff0bdc0,%rax
 1032fe3:	0f 82 e1 02 00 00    	jb     10332ca <main+0x98a>
 1032fe9:	49 81 fc 00 04 00 00 	cmp    $0x400,%r12
 1032ff0:	4c 89 74 24 10       	mov    %r14,0x10(%rsp)
 1032ff5:	0f 87 00 03 00 00    	ja     10332fb <main+0x9bb>
 1032ffb:	4a 8d 04 e5 3f 00 00 	lea    0x3f(,%r12,8),%rax
 1033002:	00 
 1033003:	48 3d 1f 04 00 00    	cmp    $0x41f,%rax
 1033009:	0f 87 ec 02 00 00    	ja     10332fb <main+0x9bb>
 103300f:	48 89 c1             	mov    %rax,%rcx
 1033012:	48 c1 e9 05          	shr    $0x5,%rcx
 1033016:	48 8d 15 63 5a 02 00 	lea    0x25a63(%rip),%rdx        # 1058a80 <myl_core_free_lists>
 103301d:	4c 8b 3c ca          	mov    (%rdx,%rcx,8),%r15
 1033021:	4d 85 ff             	test   %r15,%r15
 1033024:	0f 84 d1 02 00 00    	je     10332fb <main+0x9bb>
 103302a:	49 8b 37             	mov    (%r15),%rsi
 103302d:	48 89 34 ca          	mov    %rsi,(%rdx,%rcx,8)
 1033031:	41 c7 07 01 00 00 00 	movl   $0x1,(%r15)
 1033038:	c1 e1 18             	shl    $0x18,%ecx
 103303b:	41 89 4f 04          	mov    %ecx,0x4(%r15)
 103303f:	49 c7 47 08 00 00 00 	movq   $0x0,0x8(%r15)
 1033046:	00 
 1033047:	25 e0 07 00 00       	and    $0x7e0,%eax
 103304c:	48 83 c0 e0          	add    $0xffffffffffffffe0,%rax
 1033050:	48 c1 e8 03          	shr    $0x3,%rax
 1033054:	49 89 47 10          	mov    %rax,0x10(%r15)
 1033058:	49 c7 47 18 00 00 00 	movq   $0x0,0x18(%r15)
 103305f:	00 
 1033060:	48 89 5c 24 20       	mov    %rbx,0x20(%rsp)
 1033065:	48 be f3 59 37 98 22 	movabs $0x3759f22983759f3,%rsi
 103306c:	9f 75 03 
 103306f:	45 31 f6             	xor    %r14d,%r14d
 1033072:	48 bf c3 00 cd 58 c2 	movabs $0x81e722c258cd00c3,%rdi
 1033079:	22 e7 81 
 103307c:	31 ed                	xor    %ebp,%ebp
 103307e:	66 90                	xchg   %ax,%ax
 1033080:	48 39 ee             	cmp    %rbp,%rsi
 1033083:	0f 84 a9 02 00 00    	je     1033332 <main+0x9f2>
 1033089:	4d 89 c5             	mov    %r8,%r13
 103308c:	4d 01 f5             	add    %r14,%r13
 103308f:	0f 80 ae 02 00 00    	jo     1033343 <main+0xa03>
 1033095:	4c 89 ea             	mov    %r13,%rdx
 1033098:	c4 e2 e3 f6 df       	mulx   %rdi,%rbx,%rbx
 103309d:	49 8b 47 08          	mov    0x8(%r15),%rax
 10330a1:	49 3b 47 10          	cmp    0x10(%r15),%rax
 10330a5:	73 28                	jae    10330cf <main+0x78f>
 10330a7:	48 c1 eb 09          	shr    $0x9,%rbx
 10330ab:	48 69 cb f1 03 00 00 	imul   $0x3f1,%rbx,%rcx
 10330b2:	49 29 cd             	sub    %rcx,%r13
 10330b5:	4d 89 6c c7 20       	mov    %r13,0x20(%r15,%rax,8)
 10330ba:	48 ff c0             	inc    %rax
 10330bd:	49 89 47 08          	mov    %rax,0x8(%r15)
 10330c1:	48 ff c5             	inc    %rbp
 10330c4:	49 83 c6 25          	add    $0x25,%r14
 10330c8:	49 39 ec             	cmp    %rbp,%r12
 10330cb:	75 b3                	jne    1033080 <main+0x740>
 10330cd:	eb 30                	jmp    10330ff <main+0x7bf>
 10330cf:	be 08 00 00 00       	mov    $0x8,%esi
 10330d4:	4c 89 ff             	mov    %r15,%rdi
 10330d7:	4d 89 c7             	mov    %r8,%r15
 10330da:	e8 91 5f fd ff       	call   1009070 <myl_core_list_grow>
 10330df:	48 bf c3 00 cd 58 c2 	movabs $0x81e722c258cd00c3,%rdi
 10330e6:	22 e7 81 
 10330e9:	48 be f3 59 37 98 22 	movabs $0x3759f22983759f3,%rsi
 10330f0:	9f 75 03 
 10330f3:	4d 89 f8             	mov    %r15,%r8
 10330f6:	49 89 c7             	mov    %rax,%r15
 10330f9:	48 8b 40 08          	mov    0x8(%rax),%rax
 10330fd:	eb a8                	jmp    10330a7 <main+0x767>
 10330ff:	48 8d 3d aa 18 00 00 	lea    0x18aa(%rip),%rdi        # 10349b0 <core_io_file_error.verbs+0x110>
 1033106:	e8 35 6f fd ff       	call   100a040 <myl_core_io_at>
 103310b:	48 8b 7c 24 10       	mov    0x10(%rsp),%rdi
 1033110:	e8 9b ee fe ff       	call   1021fb0 <myl_core_host_check>
 1033115:	31 ed                	xor    %ebp,%ebp
 1033117:	e8 84 02 00 00       	call   10333a0 <runtime_bench_now>
 103311c:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
 1033121:	49 ba f1 f0 f0 f0 f0 	movabs $0xf0f0f0f0f0f0f0f1,%r10
 1033128:	f0 f0 f0 
 103312b:	48 8d 0d 9e 19 00 00 	lea    0x199e(%rip),%rcx        # 1034ad0 <core_io_file_error.verbs+0x230>
 1033132:	4c 8d 0d 67 19 00 00 	lea    0x1967(%rip),%r9        # 1034aa0 <core_io_file_error.verbs+0x200>
 1033139:	48 bb e5 8f a2 12 31 	movabs $0x89705f3112a28fe5,%rbx
 1033140:	5f 70 89 
 1033143:	45 31 c0             	xor    %r8d,%r8d
 1033146:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 103314d:	00 00 00 
 1033150:	4c 89 c2             	mov    %r8,%rdx
 1033153:	c4 c2 fb f6 c2       	mulx   %r10,%rax,%rax
 1033158:	48 89 c2             	mov    %rax,%rdx
 103315b:	48 83 e2 f0          	and    $0xfffffffffffffff0,%rdx
 103315f:	48 c1 e8 04          	shr    $0x4,%rax
 1033163:	48 01 d0             	add    %rdx,%rax
 1033166:	4d 89 c6             	mov    %r8,%r14
 1033169:	49 29 c6             	sub    %rax,%r14
 103316c:	31 f6                	xor    %esi,%esi
 103316e:	45 31 ed             	xor    %r13d,%r13d
 1033171:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033178:	0f 1f 84 00 00 00 00 
 103317f:	00 
 1033180:	4b 8b 54 ef 20       	mov    0x20(%r15,%r13,8),%rdx
 1033185:	69 c2 cd cc ff ff    	imul   $0xffffcccd,%edx,%eax
 103318b:	0f b7 c0             	movzwl %ax,%eax
 103318e:	3d 33 33 00 00       	cmp    $0x3333,%eax
 1033193:	76 29                	jbe    10331be <main+0x87e>
 1033195:	4c 01 f2             	add    %r14,%rdx
 1033198:	31 c0                	xor    %eax,%eax
 103319a:	3c 01                	cmp    $0x1,%al
 103319c:	74 33                	je     10331d1 <main+0x891>
 103319e:	48 8d 04 52          	lea    (%rdx,%rdx,2),%rax
 10331a2:	48 ff c0             	inc    %rax
 10331a5:	48 89 f2             	mov    %rsi,%rdx
 10331a8:	48 01 c2             	add    %rax,%rdx
 10331ab:	0f 80 65 01 00 00    	jo     1033316 <main+0x9d6>
 10331b1:	49 ff c5             	inc    %r13
 10331b4:	48 89 d6             	mov    %rdx,%rsi
 10331b7:	4d 39 ec             	cmp    %r13,%r12
 10331ba:	75 c4                	jne    1033180 <main+0x840>
 10331bc:	eb 32                	jmp    10331f0 <main+0x8b0>
 10331be:	48 89 cf             	mov    %rcx,%rdi
 10331c1:	e8 2c f5 ff ff       	call   10326f2 <myl_core_err_trace_origin_preserve_most>
 10331c6:	ba 01 00 00 00       	mov    $0x1,%edx
 10331cb:	b0 01                	mov    $0x1,%al
 10331cd:	3c 01                	cmp    $0x1,%al
 10331cf:	75 cd                	jne    103319e <main+0x85e>
 10331d1:	4c 89 cf             	mov    %r9,%rdi
 10331d4:	e8 31 f5 ff ff       	call   103270a <myl_core_err_trace_append_preserve_most>
 10331d9:	48 8d 04 d5 00 00 00 	lea    0x0(,%rdx,8),%rax
 10331e0:	00 
 10331e1:	48 29 d0             	sub    %rdx,%rax
 10331e4:	eb bf                	jmp    10331a5 <main+0x865>
 10331e6:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 10331ed:	00 00 00 
 10331f0:	48 89 d6             	mov    %rdx,%rsi
 10331f3:	48 01 ee             	add    %rbp,%rsi
 10331f6:	0f 80 59 01 00 00    	jo     1033355 <main+0xa15>
 10331fc:	48 89 f0             	mov    %rsi,%rax
 10331ff:	48 f7 eb             	imul   %rbx
 1033202:	48 01 f2             	add    %rsi,%rdx
 1033205:	48 89 d0             	mov    %rdx,%rax
 1033208:	48 c1 e8 3f          	shr    $0x3f,%rax
 103320c:	48 c1 fa 1d          	sar    $0x1d,%rdx
 1033210:	48 01 c2             	add    %rax,%rdx
 1033213:	48 69 c2 07 ca 9a 3b 	imul   $0x3b9aca07,%rdx,%rax
 103321a:	48 29 c6             	sub    %rax,%rsi
 103321d:	48 89 f5             	mov    %rsi,%rbp
 1033220:	48 c1 fd 3f          	sar    $0x3f,%rbp
 1033224:	81 e5 07 ca 9a 3b    	and    $0x3b9aca07,%ebp
 103322a:	48 01 f5             	add    %rsi,%rbp
 103322d:	49 ff c0             	inc    %r8
 1033230:	4c 3b 04 24          	cmp    (%rsp),%r8
 1033234:	0f 85 16 ff ff ff    	jne    1033150 <main+0x810>
 103323a:	41 0f b6 47 07       	movzbl 0x7(%r15),%eax
 103323f:	48 85 c0             	test   %rax,%rax
 1033242:	0f 84 dd 00 00 00    	je     1033325 <main+0x9e5>
 1033248:	49 83 7f 18 00       	cmpq   $0x0,0x18(%r15)
 103324d:	0f 85 d2 00 00 00    	jne    1033325 <main+0x9e5>
 1033253:	48 8d 0d 26 58 02 00 	lea    0x25826(%rip),%rcx        # 1058a80 <myl_core_free_lists>
 103325a:	48 8b 14 c1          	mov    (%rcx,%rax,8),%rdx
 103325e:	49 89 17             	mov    %rdx,(%r15)
 1033261:	4c 89 3c c1          	mov    %r15,(%rcx,%rax,8)
 1033265:	48 8b 5c 24 10       	mov    0x10(%rsp),%rbx
 103326a:	4c 8b 74 24 18       	mov    0x18(%rsp),%r14
 103326f:	48 8d 3d 6a 17 00 00 	lea    0x176a(%rip),%rdi        # 10349e0 <core_io_file_error.verbs+0x140>
 1033276:	e8 c5 6d fd ff       	call   100a040 <myl_core_io_at>
 103327b:	48 89 df             	mov    %rbx,%rdi
 103327e:	e8 2d ed fe ff       	call   1021fb0 <myl_core_host_check>
 1033283:	e8 18 01 00 00       	call   10333a0 <runtime_bench_now>
 1033288:	48 89 c3             	mov    %rax,%rbx
 103328b:	4c 29 f3             	sub    %r14,%rbx
 103328e:	0f 80 f2 00 00 00    	jo     1033386 <main+0xa46>
 1033294:	bf 01 00 00 00       	mov    $0x1,%edi
 1033299:	48 89 ee             	mov    %rbp,%rsi
 103329c:	e8 9f 74 fd ff       	call   100a740 <myl_core_print_i64>
 10332a1:	bf 01 00 00 00       	mov    $0x1,%edi
 10332a6:	e8 d5 5a fd ff       	call   1008d80 <myl_core_print_sep>
 10332ab:	bf 01 00 00 00       	mov    $0x1,%edi
 10332b0:	48 89 de             	mov    %rbx,%rsi
 10332b3:	e8 88 74 fd ff       	call   100a740 <myl_core_print_i64>
 10332b8:	bf 01 00 00 00       	mov    $0x1,%edi
 10332bd:	e8 7e 5b fd ff       	call   1008e40 <myl_core_print_end>
 10332c2:	45 31 ff             	xor    %r15d,%r15d
 10332c5:	48 8b 5c 24 20       	mov    0x20(%rsp),%rbx
 10332ca:	48 89 df             	mov    %rbx,%rdi
 10332cd:	e8 6e 62 fd ff       	call   1009540 <myl_core_release>
 10332d2:	4c 89 ff             	mov    %r15,%rdi
 10332d5:	e8 76 6d fd ff       	call   100a050 <myl_core_exit>
 10332da:	48 83 c4 28          	add    $0x28,%rsp
 10332de:	5b                   	pop    %rbx
 10332df:	41 5c                	pop    %r12
 10332e1:	41 5d                	pop    %r13
 10332e3:	41 5e                	pop    %r14
 10332e5:	41 5f                	pop    %r15
 10332e7:	5d                   	pop    %rbp
 10332e8:	c3                   	ret
 10332e9:	31 c9                	xor    %ecx,%ecx
 10332eb:	31 d2                	xor    %edx,%edx
 10332ed:	f6 c1 01             	test   $0x1,%cl
 10332f0:	0f 85 00 fc ff ff    	jne    1032ef6 <main+0x5b6>
 10332f6:	e9 af fc ff ff       	jmp    1032faa <main+0x66a>
 10332fb:	be 08 00 00 00       	mov    $0x8,%esi
 1033300:	4c 89 e7             	mov    %r12,%rdi
 1033303:	4d 89 c6             	mov    %r8,%r14
 1033306:	e8 f5 5c fd ff       	call   1009000 <myl_core_list_new_slow>
 103330b:	4d 89 f0             	mov    %r14,%r8
 103330e:	49 89 c7             	mov    %rax,%r15
 1033311:	e9 4a fd ff ff       	jmp    1033060 <main+0x720>
 1033316:	48 8d 3d 53 17 00 00 	lea    0x1753(%rip),%rdi        # 1034a70 <core_io_file_error.verbs+0x1d0>
 103331d:	48 89 c2             	mov    %rax,%rdx
 1033320:	e8 db 63 fd ff       	call   1009700 <myl_core_trap>
 1033325:	4c 89 ff             	mov    %r15,%rdi
 1033328:	e8 e3 ef ff ff       	call   1032310 <myl_core_free_block>
 103332d:	e9 33 ff ff ff       	jmp    1033265 <main+0x925>
 1033332:	48 8d 3d 17 16 00 00 	lea    0x1617(%rip),%rdi        # 1034950 <core_io_file_error.verbs+0xb0>
 1033339:	ba 25 00 00 00       	mov    $0x25,%edx
 103333e:	e8 bd 63 fd ff       	call   1009700 <myl_core_trap>
 1033343:	48 8d 3d 36 16 00 00 	lea    0x1636(%rip),%rdi        # 1034980 <core_io_file_error.verbs+0xe0>
 103334a:	4c 89 c6             	mov    %r8,%rsi
 103334d:	4c 89 f2             	mov    %r14,%rdx
 1033350:	e8 ab 63 fd ff       	call   1009700 <myl_core_trap>
 1033355:	48 8d 3d e4 16 00 00 	lea    0x16e4(%rip),%rdi        # 1034a40 <core_io_file_error.verbs+0x1a0>
 103335c:	48 89 ee             	mov    %rbp,%rsi
 103335f:	e8 9c 63 fd ff       	call   1009700 <myl_core_trap>
 1033364:	48 8d 3d b5 15 00 00 	lea    0x15b5(%rip),%rdi        # 1034920 <core_io_file_error.verbs+0x80>
 103336b:	be 02 00 00 00       	mov    $0x2,%esi
 1033370:	e8 8b 63 fd ff       	call   1009700 <myl_core_trap>
 1033375:	48 8d 3d 74 15 00 00 	lea    0x1574(%rip),%rdi        # 10348f0 <core_io_file_error.verbs+0x50>
 103337c:	be 01 00 00 00       	mov    $0x1,%esi
 1033381:	e8 7a 63 fd ff       	call   1009700 <myl_core_trap>
 1033386:	48 8d 3d 83 16 00 00 	lea    0x1683(%rip),%rdi        # 1034a10 <core_io_file_error.verbs+0x170>
 103338d:	48 89 c6             	mov    %rax,%rsi
 1033390:	4c 89 f2             	mov    %r14,%rdx
 1033393:	e8 68 63 fd ff       	call   1009700 <myl_core_trap>

Disassembly of section .init:

Disassembly of section .fini:

Disassembly of section .plt:
