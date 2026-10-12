
/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/text-gaps/coordinator/common-001/text-runtime:     file format elf64-x86-64


Disassembly of section .text:

000000000104d9f4 <my.text::kernel+0x26a4>:
 104d9f4:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
 104d9f9:	49 8b 44 c5 20       	mov    0x20(%r13,%rax,8),%rax
 104d9fe:	48 8b 50 08          	mov    0x8(%rax),%rdx
 104da02:	48 83 fa 04          	cmp    $0x4,%rdx
 104da06:	0f 82 39 21 00 00    	jb     104fb45 <my.text::kernel+0x47f5>
 104da0c:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
 104da11:	48 8b 78 38          	mov    0x38(%rax),%rdi
 104da15:	48 8b 77 08          	mov    0x8(%rdi),%rsi
 104da19:	48 85 f6             	test   %rsi,%rsi
 104da1c:	74 c2                	je     104d9e0 <my.text::kernel+0x2690>
 104da1e:	48 83 c7 20          	add    $0x20,%rdi
 104da22:	0f b6 07             	movzbl (%rdi),%eax
 104da25:	8d 48 d5             	lea    -0x2b(%rax),%ecx
 104da28:	45 31 c0             	xor    %r8d,%r8d
 104da2b:	f6 c1 fd             	test   $0xfd,%cl
 104da2e:	0f 94 c1             	sete   %cl
 104da31:	41 0f 95 c2          	setne  %r10b
 104da35:	44 8d 48 d0          	lea    -0x30(%rax),%r9d
 104da39:	41 80 f9 0a          	cmp    $0xa,%r9b
 104da3d:	41 0f 93 c3          	setae  %r11b
 104da41:	44 0f b6 4c 37 ff    	movzbl -0x1(%rdi,%rsi,1),%r9d
 104da47:	45 84 d3             	test   %r10b,%r11b
 104da4a:	75 34                	jne    104da80 <my.text::kernel+0x2730>
 104da4c:	45 8d 51 d0          	lea    -0x30(%r9),%r10d
 104da50:	41 80 fa 0a          	cmp    $0xa,%r10b
 104da54:	73 2a                	jae    104da80 <my.text::kernel+0x2730>
 104da56:	41 88 c8             	mov    %cl,%r8b
 104da59:	48 89 f1             	mov    %rsi,%rcx
 104da5c:	4c 29 c1             	sub    %r8,%rcx
 104da5f:	48 83 f9 08          	cmp    $0x8,%rcx
 104da63:	0f 87 b7 01 00 00    	ja     104dc20 <my.text::kernel+0x28d0>
 104da69:	49 01 f8             	add    %rdi,%r8
 104da6c:	48 83 f9 08          	cmp    $0x8,%rcx
 104da70:	75 25                	jne    104da97 <my.text::kernel+0x2747>
 104da72:	4d 8b 00             	mov    (%r8),%r8
 104da75:	eb 42                	jmp    104dab9 <my.text::kernel+0x2769>
 104da77:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 104da7e:	00 00 
 104da80:	3c 21                	cmp    $0x21,%al
 104da82:	0f 82 98 01 00 00    	jb     104dc20 <my.text::kernel+0x28d0>
 104da88:	41 80 f9 21          	cmp    $0x21,%r9b
 104da8c:	0f 83 4e ff ff ff    	jae    104d9e0 <my.text::kernel+0x2690>
 104da92:	e9 89 01 00 00       	jmp    104dc20 <my.text::kernel+0x28d0>
 104da97:	48 83 f9 04          	cmp    $0x4,%rcx
 104da9b:	0f 86 d5 00 00 00    	jbe    104db76 <my.text::kernel+0x2826>
 104daa1:	45 8b 08             	mov    (%r8),%r9d
 104daa4:	4c 8d 51 fc          	lea    -0x4(%rcx),%r10
 104daa8:	45 8b 44 08 fc       	mov    -0x4(%r8,%rcx,1),%r8d
 104daad:	41 c1 e2 03          	shl    $0x3,%r10d
 104dab1:	c4 42 a9 f7 c0       	shlx   %r10,%r8,%r8
 104dab6:	4d 09 c8             	or     %r9,%r8
 104dab9:	c1 e1 03             	shl    $0x3,%ecx
 104dabc:	41 b1 40             	mov    $0x40,%r9b
 104dabf:	41 28 c9             	sub    %cl,%r9b
 104dac2:	f6 d9                	neg    %cl
 104dac4:	c4 c2 f1 f7 c8       	shlx   %rcx,%r8,%rcx
 104dac9:	49 b8 30 30 30 30 30 	movabs $0x30303030303030,%r8
 104dad0:	30 30 00 
 104dad3:	c4 42 b0 f5 c0       	bzhi   %r9,%r8,%r8
 104dad8:	49 09 c8             	or     %rcx,%r8
 104dadb:	48 b9 d0 cf cf cf cf 	movabs $0xcfcfcfcfcfcfcfd0,%rcx
 104dae2:	cf cf cf 
 104dae5:	4d 8d 0c 08          	lea    (%r8,%rcx,1),%r9
 104dae9:	48 b9 46 46 46 46 46 	movabs $0x4646464646464646,%rcx
 104daf0:	46 46 46 
 104daf3:	49 01 c8             	add    %rcx,%r8
 104daf6:	4d 09 c8             	or     %r9,%r8
 104daf9:	48 b9 80 80 80 80 80 	movabs $0x8080808080808080,%rcx
 104db00:	80 80 80 
 104db03:	49 85 c8             	test   %rcx,%r8
 104db06:	0f 94 c1             	sete   %cl
 104db09:	4f 8d 04 89          	lea    (%r9,%r9,4),%r8
 104db0d:	49 c1 e9 08          	shr    $0x8,%r9
 104db11:	4f 8d 0c 41          	lea    (%r9,%r8,2),%r9
 104db15:	4d 89 c8             	mov    %r9,%r8
 104db18:	49 c1 e8 10          	shr    $0x10,%r8
 104db1c:	49 bb ff 00 00 00 ff 	movabs $0xff000000ff,%r11
 104db23:	00 00 00 
 104db26:	4d 21 d9             	and    %r11,%r9
 104db29:	49 ba 64 00 00 00 40 	movabs $0xf424000000064,%r10
 104db30:	42 0f 00 
 104db33:	4d 0f af ca          	imul   %r10,%r9
 104db37:	4d 21 d8             	and    %r11,%r8
 104db3a:	49 ba 01 00 00 00 10 	movabs $0x271000000001,%r10
 104db41:	27 00 00 
 104db44:	4d 0f af c2          	imul   %r10,%r8
 104db48:	4d 01 c8             	add    %r9,%r8
 104db4b:	49 c1 e8 20          	shr    $0x20,%r8
 104db4f:	f6 c1 01             	test   $0x1,%cl
 104db52:	0f 84 c8 00 00 00    	je     104dc20 <my.text::kernel+0x28d0>
 104db58:	4c 89 c1             	mov    %r8,%rcx
 104db5b:	48 f7 d9             	neg    %rcx
 104db5e:	3c 2d                	cmp    $0x2d,%al
 104db60:	49 0f 45 c8          	cmovne %r8,%rcx
 104db64:	48 89 8c 24 58 01 00 	mov    %rcx,0x158(%rsp)
 104db6b:	00 
 104db6c:	48 8b 5c 24 30       	mov    0x30(%rsp),%rbx
 104db71:	e9 d3 00 00 00       	jmp    104dc49 <my.text::kernel+0x28f9>
 104db76:	4c 8d 49 ff          	lea    -0x1(%rcx),%r9
 104db7a:	49 83 f9 03          	cmp    $0x3,%r9
 104db7e:	0f 87 6a 05 00 00    	ja     104e0ee <my.text::kernel+0x2d9e>
 104db84:	4c 8d 15 35 98 fb ff 	lea    -0x467cb(%rip),%r10        # 10073c0 <core_number_pairs+0x120>
 104db8b:	4f 63 0c 8a          	movslq (%r10,%r9,4),%r9
 104db8f:	4d 01 d1             	add    %r10,%r9
 104db92:	41 ff e1             	jmp    *%r9
 104db95:	45 0f b6 00          	movzbl (%r8),%r8d
 104db99:	eb 1b                	jmp    104dbb6 <my.text::kernel+0x2866>
 104db9b:	45 0f b7 08          	movzwl (%r8),%r9d
 104db9f:	45 0f b6 40 02       	movzbl 0x2(%r8),%r8d
 104dba4:	41 c1 e0 10          	shl    $0x10,%r8d
 104dba8:	45 09 c8             	or     %r9d,%r8d
 104dbab:	eb 09                	jmp    104dbb6 <my.text::kernel+0x2866>
 104dbad:	45 8b 00             	mov    (%r8),%r8d
 104dbb0:	eb 04                	jmp    104dbb6 <my.text::kernel+0x2866>
 104dbb2:	45 0f b7 00          	movzwl (%r8),%r8d
 104dbb6:	c1 e1 03             	shl    $0x3,%ecx
 104dbb9:	41 b1 20             	mov    $0x20,%r9b
 104dbbc:	41 28 c9             	sub    %cl,%r9b
 104dbbf:	f6 d9                	neg    %cl
 104dbc1:	c4 c2 71 f7 c8       	shlx   %ecx,%r8d,%ecx
 104dbc6:	41 b8 30 30 30 00    	mov    $0x303030,%r8d
 104dbcc:	c4 42 30 f5 c0       	bzhi   %r9d,%r8d,%r8d
 104dbd1:	41 09 c8             	or     %ecx,%r8d
 104dbd4:	45 8d 88 d0 cf cf cf 	lea    -0x30303030(%r8),%r9d
 104dbdb:	41 81 c0 46 46 46 46 	add    $0x46464646,%r8d
 104dbe2:	45 09 c8             	or     %r9d,%r8d
 104dbe5:	41 f7 c0 80 80 80 80 	test   $0x80808080,%r8d
 104dbec:	0f 94 c1             	sete   %cl
 104dbef:	45 69 c1 01 0a 00 00 	imul   $0xa01,%r9d,%r8d
 104dbf6:	41 c1 e8 08          	shr    $0x8,%r8d
 104dbfa:	41 81 e0 ff 00 ff 00 	and    $0xff00ff,%r8d
 104dc01:	45 69 c0 01 00 64 00 	imul   $0x640001,%r8d,%r8d
 104dc08:	41 c1 e8 10          	shr    $0x10,%r8d
 104dc0c:	f6 c1 01             	test   $0x1,%cl
 104dc0f:	0f 85 43 ff ff ff    	jne    104db58 <my.text::kernel+0x2808>
 104dc15:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 104dc1c:	00 00 00 00 
 104dc20:	48 8d 94 24 58 01 00 	lea    0x158(%rsp),%rdx
 104dc27:	00 
 104dc28:	c5 f8 77             	vzeroupper
 104dc2b:	e8 d0 2c fe ff       	call   1030900 <myl_core_span_parse_int>
 104dc30:	84 c0                	test   %al,%al
 104dc32:	0f 84 a8 fd ff ff    	je     104d9e0 <my.text::kernel+0x2690>
 104dc38:	48 8b 8c 24 58 01 00 	mov    0x158(%rsp),%rcx
 104dc3f:	00 
 104dc40:	48 8b 5c 24 30       	mov    0x30(%rsp),%rbx
 104dc45:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 104dc49:	48 89 8c 24 80 00 00 	mov    %rcx,0x80(%rsp)
 104dc50:	00 
 104dc51:	48 83 fa 04          	cmp    $0x4,%rdx
 104dc55:	0f 86 d8 1f 00 00    	jbe    104fc33 <my.text::kernel+0x48e3>
 104dc5b:	48 8b 7b 40          	mov    0x40(%rbx),%rdi
 104dc5f:	48 8d 35 9a bf fb ff 	lea    -0x44066(%rip),%rsi        # 1009c00 <core_number_pairs+0x2960>
 104dc66:	c5 f8 77             	vzeroupper
 104dc69:	e8 92 1d fd ff       	call   101fa00 <myl_core_str_eq>
 104dc6e:	84 c0                	test   %al,%al
 104dc70:	0f 84 6d fd ff ff    	je     104d9e3 <my.text::kernel+0x2693>
 104dc76:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 104dc7a:	48 83 fa 02          	cmp    $0x2,%rdx
 104dc7e:	0f 86 53 20 00 00    	jbe    104fcd7 <my.text::kernel+0x4987>
 104dc84:	4c 89 7c 24 68       	mov    %r15,0x68(%rsp)
 104dc89:	48 8b 7b 30          	mov    0x30(%rbx),%rdi
 104dc8d:	48 8b 77 08          	mov    0x8(%rdi),%rsi
 104dc91:	48 83 c7 20          	add    $0x20,%rdi
 104dc95:	48 89 7c 24 50       	mov    %rdi,0x50(%rsp)
 104dc9a:	48 89 74 24 18       	mov    %rsi,0x18(%rsp)
 104dc9f:	e8 9c 1a fd ff       	call   101f740 <myl_core_span_hash>
 104dca4:	89 c0                	mov    %eax,%eax
 104dca6:	48 b9 15 7c 4a 7f b9 	movabs $0x9e3779b97f4a7c15,%rcx
 104dcad:	79 37 9e 
 104dcb0:	48 0f af c1          	imul   %rcx,%rax
 104dcb4:	48 89 c3             	mov    %rax,%rbx
 104dcb7:	48 c1 eb 20          	shr    $0x20,%rbx
 104dcbb:	48 31 c3             	xor    %rax,%rbx
 104dcbe:	48 8b 4d 18          	mov    0x18(%rbp),%rcx
 104dcc2:	48 8b 41 08          	mov    0x8(%rcx),%rax
 104dcc6:	48 85 c0             	test   %rax,%rax
 104dcc9:	0f 84 d4 01 00 00    	je     104dea3 <my.text::kernel+0x2b53>
 104dccf:	8b 08                	mov    (%rax),%ecx
 104dcd1:	f3 0f bc d1          	tzcnt  %ecx,%edx
 104dcd5:	f6 da                	neg    %dl
 104dcd7:	c4 62 eb f7 eb       	shrx   %rdx,%rbx,%r13
 104dcdc:	c4 a1 7a 6f 4c 28 10 	vmovdqu 0x10(%rax,%r13,1),%xmm1
 104dce3:	80 e3 7f             	and    $0x7f,%bl
 104dce6:	c5 f9 6e c3          	vmovd  %ebx,%xmm0
 104dcea:	c4 e2 79 78 c0       	vpbroadcastb %xmm0,%xmm0
 104dcef:	c5 f9 7f 8c 24 b0 00 	vmovdqa %xmm1,0xb0(%rsp)
 104dcf6:	00 00 
 104dcf8:	c5 f1 74 c0          	vpcmpeqb %xmm0,%xmm1,%xmm0
 104dcfc:	c5 f9 d7 f8          	vpmovmskb %xmm0,%edi
 104dd00:	85 ff                	test   %edi,%edi
 104dd02:	48 8b 54 24 18       	mov    0x18(%rsp),%rdx
 104dd07:	48 8b 74 24 50       	mov    0x50(%rsp),%rsi
 104dd0c:	0f 84 e3 00 00 00    	je     104ddf5 <my.text::kernel+0x2aa5>
 104dd12:	8d 59 ff             	lea    -0x1(%rcx),%ebx
 104dd15:	83 c1 1e             	add    $0x1e,%ecx
 104dd18:	83 e1 f0             	and    $0xfffffff0,%ecx
 104dd1b:	4c 8d 34 08          	lea    (%rax,%rcx,1),%r14
 104dd1f:	49 83 c6 10          	add    $0x10,%r14
 104dd23:	0f b7 ef             	movzwl %di,%ebp
 104dd26:	48 89 d0             	mov    %rdx,%rax
 104dd29:	48 d1 e8             	shr    $1,%rax
 104dd2c:	48 89 84 24 98 00 00 	mov    %rax,0x98(%rsp)
 104dd33:	00 
 104dd34:	eb 2c                	jmp    104dd62 <my.text::kernel+0x2a12>
 104dd36:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 104dd3d:	00 00 00 
 104dd40:	e8 1b f9 00 00       	call   105d660 <bcmp@plt>
 104dd45:	48 8b 74 24 50       	mov    0x50(%rsp),%rsi
 104dd4a:	48 8b 54 24 18       	mov    0x18(%rsp),%rdx
 104dd4f:	85 c0                	test   %eax,%eax
 104dd51:	0f 84 d4 00 00 00    	je     104de2b <my.text::kernel+0x2adb>
 104dd57:	c4 e2 50 f3 cd       	blsr   %ebp,%ebp
 104dd5c:	0f 84 93 00 00 00    	je     104ddf5 <my.text::kernel+0x2aa5>
 104dd62:	f3 0f bc c5          	tzcnt  %ebp,%eax
 104dd66:	44 01 e8             	add    %r13d,%eax
 104dd69:	21 d8                	and    %ebx,%eax
 104dd6b:	45 8b 3c 86          	mov    (%r14,%rax,4),%r15d
 104dd6f:	49 c1 e7 04          	shl    $0x4,%r15
 104dd73:	48 8b 04 24          	mov    (%rsp),%rax
 104dd77:	4a 8b 7c 38 20       	mov    0x20(%rax,%r15,1),%rdi
 104dd7c:	48 39 57 08          	cmp    %rdx,0x8(%rdi)
 104dd80:	75 d5                	jne    104dd57 <my.text::kernel+0x2a07>
 104dd82:	48 83 c7 20          	add    $0x20,%rdi
 104dd86:	48 83 fa 10          	cmp    $0x10,%rdx
 104dd8a:	77 b4                	ja     104dd40 <my.text::kernel+0x29f0>
 104dd8c:	48 83 fa 08          	cmp    $0x8,%rdx
 104dd90:	72 19                	jb     104ddab <my.text::kernel+0x2a5b>
 104dd92:	48 8b 07             	mov    (%rdi),%rax
 104dd95:	48 3b 06             	cmp    (%rsi),%rax
 104dd98:	75 bd                	jne    104dd57 <my.text::kernel+0x2a07>
 104dd9a:	48 8b 44 16 f8       	mov    -0x8(%rsi,%rdx,1),%rax
 104dd9f:	48 39 44 17 f8       	cmp    %rax,-0x8(%rdi,%rdx,1)
 104dda4:	75 b1                	jne    104dd57 <my.text::kernel+0x2a07>
 104dda6:	e9 80 00 00 00       	jmp    104de2b <my.text::kernel+0x2adb>
 104ddab:	48 83 fa 04          	cmp    $0x4,%rdx
 104ddaf:	72 12                	jb     104ddc3 <my.text::kernel+0x2a73>
 104ddb1:	8b 07                	mov    (%rdi),%eax
 104ddb3:	3b 06                	cmp    (%rsi),%eax
 104ddb5:	75 a0                	jne    104dd57 <my.text::kernel+0x2a07>
 104ddb7:	8b 44 16 fc          	mov    -0x4(%rsi,%rdx,1),%eax
 104ddbb:	39 44 17 fc          	cmp    %eax,-0x4(%rdi,%rdx,1)
 104ddbf:	75 96                	jne    104dd57 <my.text::kernel+0x2a07>
 104ddc1:	eb 68                	jmp    104de2b <my.text::kernel+0x2adb>
 104ddc3:	48 85 d2             	test   %rdx,%rdx
 104ddc6:	74 63                	je     104de2b <my.text::kernel+0x2adb>
 104ddc8:	0f b6 07             	movzbl (%rdi),%eax
 104ddcb:	3a 06                	cmp    (%rsi),%al
 104ddcd:	75 88                	jne    104dd57 <my.text::kernel+0x2a07>
 104ddcf:	48 8b 8c 24 98 00 00 	mov    0x98(%rsp),%rcx
 104ddd6:	00 
 104ddd7:	0f b6 04 0e          	movzbl (%rsi,%rcx,1),%eax
 104dddb:	38 04 0f             	cmp    %al,(%rdi,%rcx,1)
 104ddde:	0f 85 73 ff ff ff    	jne    104dd57 <my.text::kernel+0x2a07>
 104dde4:	0f b6 44 16 ff       	movzbl -0x1(%rsi,%rdx,1),%eax
 104dde9:	38 44 17 ff          	cmp    %al,-0x1(%rdi,%rdx,1)
 104dded:	0f 85 64 ff ff ff    	jne    104dd57 <my.text::kernel+0x2a07>
 104ddf3:	eb 36                	jmp    104de2b <my.text::kernel+0x2adb>
 104ddf5:	c5 f9 6f 84 24 b0 00 	vmovdqa 0xb0(%rsp),%xmm0
 104ddfc:	00 00 
 104ddfe:	c5 f9 74 05 da 65 fb 	vpcmpeqb -0x49a26(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0x50>
 104de05:	ff 
 104de06:	c5 f9 d7 c0          	vpmovmskb %xmm0,%eax
 104de0a:	85 c0                	test   %eax,%eax
 104de0c:	0f 85 39 1c 00 00    	jne    104fa4b <my.text::kernel+0x46fb>
 104de12:	48 8b 3c 24          	mov    (%rsp),%rdi
 104de16:	e8 65 15 fd ff       	call   101f380 <myl_core_dict_find_span>
 104de1b:	49 89 c7             	mov    %rax,%r15
 104de1e:	4d 85 ff             	test   %r15,%r15
 104de21:	0f 88 24 1c 00 00    	js     104fa4b <my.text::kernel+0x46fb>
 104de27:	49 c1 e7 04          	shl    $0x4,%r15
 104de2b:	48 8b 2c 24          	mov    (%rsp),%rbp
 104de2f:	4a 8b 74 3d 28       	mov    0x28(%rbp,%r15,1),%rsi
 104de34:	48 89 f0             	mov    %rsi,%rax
 104de37:	48 8b 94 24 80 00 00 	mov    0x80(%rsp),%rdx
 104de3e:	00 
 104de3f:	48 01 d0             	add    %rdx,%rax
 104de42:	0f 80 c0 1e 00 00    	jo     104fd08 <my.text::kernel+0x49b8>
 104de48:	4a 89 44 3d 28       	mov    %rax,0x28(%rbp,%r15,1)
 104de4d:	48 8b 44 24 30       	mov    0x30(%rsp),%rax
 104de52:	48 8b 50 08          	mov    0x8(%rax),%rdx
 104de56:	48 83 fa 01          	cmp    $0x1,%rdx
 104de5a:	4c 8b ac 24 00 01 00 	mov    0x100(%rsp),%r13
 104de61:	00 
 104de62:	0f 86 80 1e 00 00    	jbe    104fce8 <my.text::kernel+0x4998>
 104de68:	48 8b 40 28          	mov    0x28(%rax),%rax
 104de6c:	48 8b 48 08          	mov    0x8(%rax),%rcx
 104de70:	48 85 c9             	test   %rcx,%rcx
 104de73:	48 8b b4 24 a0 00 00 	mov    0xa0(%rsp),%rsi
 104de7a:	00 
 104de7b:	4c 8b b4 24 f8 00 00 	mov    0xf8(%rsp),%r14
 104de82:	00 
 104de83:	4c 8b 7c 24 68       	mov    0x68(%rsp),%r15
 104de88:	0f 84 73 01 00 00    	je     104e001 <my.text::kernel+0x2cb1>
 104de8e:	48 83 f9 04          	cmp    $0x4,%rcx
 104de92:	0f 83 70 01 00 00    	jae    104e008 <my.text::kernel+0x2cb8>
 104de98:	48 89 ca             	mov    %rcx,%rdx
 104de9b:	45 31 c0             	xor    %r8d,%r8d
 104de9e:	e9 6d 02 00 00       	jmp    104e110 <my.text::kernel+0x2dc0>
 104dea3:	48 8b 69 20          	mov    0x20(%rcx),%rbp
 104dea7:	48 85 ed             	test   %rbp,%rbp
 104deaa:	48 8b 54 24 18       	mov    0x18(%rsp),%rdx
 104deaf:	48 8b 74 24 50       	mov    0x50(%rsp),%rsi
 104deb4:	0f 84 91 1b 00 00    	je     104fa4b <my.text::kernel+0x46fb>
 104deba:	4c 8b 69 10          	mov    0x10(%rcx),%r13
 104debe:	4c 8b 41 18          	mov    0x18(%rcx),%r8
 104dec2:	48 89 d0             	mov    %rdx,%rax
 104dec5:	48 d1 e8             	shr    $1,%rax
 104dec8:	48 89 84 24 98 00 00 	mov    %rax,0x98(%rsp)
 104decf:	00 
 104ded0:	4c 8b b4 24 f0 00 00 	mov    0xf0(%rsp),%r14
 104ded7:	00 
 104ded8:	45 31 ff             	xor    %r15d,%r15d
 104dedb:	4c 89 84 24 b0 00 00 	mov    %r8,0xb0(%rsp)
 104dee2:	00 
 104dee3:	eb 6b                	jmp    104df50 <my.text::kernel+0x2c00>
 104dee5:	e8 76 f7 00 00       	call   105d660 <bcmp@plt>
 104deea:	4c 8b 84 24 b0 00 00 	mov    0xb0(%rsp),%r8
 104def1:	00 
 104def2:	48 8b 74 24 50       	mov    0x50(%rsp),%rsi
 104def7:	48 8b 54 24 18       	mov    0x18(%rsp),%rdx
 104defc:	85 c0                	test   %eax,%eax
 104defe:	0f 84 1a ff ff ff    	je     104de1e <my.text::kernel+0x2ace>
 104df04:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 104df0b:	0f 1f 84 00 00 00 00 
 104df12:	00 
 104df13:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 104df1a:	0f 1f 84 00 00 00 00 
 104df21:	00 
 104df22:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 104df29:	0f 1f 84 00 00 00 00 
 104df30:	00 
 104df31:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 104df38:	0f 1f 84 00 00 00 00 
 104df3f:	00 
 104df40:	49 ff c7             	inc    %r15
 104df43:	49 83 c6 10          	add    $0x10,%r14
 104df47:	4c 39 fd             	cmp    %r15,%rbp
 104df4a:	0f 84 fb 1a 00 00    	je     104fa4b <my.text::kernel+0x46fb>
 104df50:	4b 39 5c fd 00       	cmp    %rbx,0x0(%r13,%r15,8)
 104df55:	75 e9                	jne    104df40 <my.text::kernel+0x2bf0>
 104df57:	4d 85 c0             	test   %r8,%r8
 104df5a:	74 17                	je     104df73 <my.text::kernel+0x2c23>
 104df5c:	4c 89 f8             	mov    %r15,%rax
 104df5f:	48 c1 e8 03          	shr    $0x3,%rax
 104df63:	41 0f b6 04 00       	movzbl (%r8,%rax,1),%eax
 104df68:	44 89 f9             	mov    %r15d,%ecx
 104df6b:	83 e1 07             	and    $0x7,%ecx
 104df6e:	0f a3 c8             	bt     %ecx,%eax
 104df71:	72 cd                	jb     104df40 <my.text::kernel+0x2bf0>
 104df73:	49 8b 3e             	mov    (%r14),%rdi
 104df76:	48 39 57 08          	cmp    %rdx,0x8(%rdi)
 104df7a:	75 c4                	jne    104df40 <my.text::kernel+0x2bf0>
 104df7c:	48 83 c7 20          	add    $0x20,%rdi
 104df80:	48 83 fa 10          	cmp    $0x10,%rdx
 104df84:	0f 87 5b ff ff ff    	ja     104dee5 <my.text::kernel+0x2b95>
 104df8a:	48 83 fa 08          	cmp    $0x8,%rdx
 104df8e:	72 19                	jb     104dfa9 <my.text::kernel+0x2c59>
 104df90:	48 8b 07             	mov    (%rdi),%rax
 104df93:	48 3b 06             	cmp    (%rsi),%rax
 104df96:	75 a8                	jne    104df40 <my.text::kernel+0x2bf0>
 104df98:	48 8b 44 16 f8       	mov    -0x8(%rsi,%rdx,1),%rax
 104df9d:	48 39 44 17 f8       	cmp    %rax,-0x8(%rdi,%rdx,1)
 104dfa2:	75 9c                	jne    104df40 <my.text::kernel+0x2bf0>
 104dfa4:	e9 75 fe ff ff       	jmp    104de1e <my.text::kernel+0x2ace>
 104dfa9:	48 83 fa 04          	cmp    $0x4,%rdx
 104dfad:	72 15                	jb     104dfc4 <my.text::kernel+0x2c74>
 104dfaf:	8b 07                	mov    (%rdi),%eax
 104dfb1:	3b 06                	cmp    (%rsi),%eax
 104dfb3:	75 8b                	jne    104df40 <my.text::kernel+0x2bf0>
 104dfb5:	8b 44 16 fc          	mov    -0x4(%rsi,%rdx,1),%eax
 104dfb9:	39 44 17 fc          	cmp    %eax,-0x4(%rdi,%rdx,1)
 104dfbd:	75 81                	jne    104df40 <my.text::kernel+0x2bf0>
 104dfbf:	e9 5a fe ff ff       	jmp    104de1e <my.text::kernel+0x2ace>
 104dfc4:	48 85 d2             	test   %rdx,%rdx
 104dfc7:	0f 84 51 fe ff ff    	je     104de1e <my.text::kernel+0x2ace>
 104dfcd:	0f b6 07             	movzbl (%rdi),%eax
 104dfd0:	3a 06                	cmp    (%rsi),%al
 104dfd2:	0f 85 68 ff ff ff    	jne    104df40 <my.text::kernel+0x2bf0>
 104dfd8:	48 8b 8c 24 98 00 00 	mov    0x98(%rsp),%rcx
 104dfdf:	00 
 104dfe0:	0f b6 04 0e          	movzbl (%rsi,%rcx,1),%eax
 104dfe4:	38 04 0f             	cmp    %al,(%rdi,%rcx,1)
 104dfe7:	0f 85 53 ff ff ff    	jne    104df40 <my.text::kernel+0x2bf0>
 104dfed:	0f b6 44 16 ff       	movzbl -0x1(%rsi,%rdx,1),%eax
 104dff2:	38 44 17 ff          	cmp    %al,-0x1(%rdi,%rdx,1)
 104dff6:	0f 85 44 ff ff ff    	jne    104df40 <my.text::kernel+0x2bf0>
 104dffc:	e9 1d fe ff ff       	jmp    104de1e <my.text::kernel+0x2ace>
 104e001:	31 d2                	xor    %edx,%edx
 104e003:	e9 19 01 00 00       	jmp    104e121 <my.text::kernel+0x2dd1>
 104e008:	48 83 f9 10          	cmp    $0x10,%rcx
 104e00c:	73 0b                	jae    104e019 <my.text::kernel+0x2cc9>
 104e00e:	45 31 c0             	xor    %r8d,%r8d
 104e011:	48 89 ca             	mov    %rcx,%rdx
 104e014:	e9 8e 00 00 00       	jmp    104e0a7 <my.text::kernel+0x2d57>
 104e019:	49 89 c8             	mov    %rcx,%r8
 104e01c:	49 83 e0 f0          	and    $0xfffffffffffffff0,%r8
 104e020:	c4 e1 f9 6e c1       	vmovq  %rcx,%xmm0
 104e025:	c5 f1 ef c9          	vpxor  %xmm1,%xmm1,%xmm1
 104e029:	31 d2                	xor    %edx,%edx
 104e02b:	c5 e9 ef d2          	vpxor  %xmm2,%xmm2,%xmm2
 104e02f:	c5 e1 ef db          	vpxor  %xmm3,%xmm3,%xmm3
 104e033:	66 66 66 66 2e 0f 1f 	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 104e03a:	84 00 00 00 00 00 
 104e040:	c4 e2 7d 32 64 10 20 	vpmovzxbq 0x20(%rax,%rdx,1),%ymm4
 104e047:	c5 fd d4 c4          	vpaddq %ymm4,%ymm0,%ymm0
 104e04b:	c4 e2 7d 32 64 10 24 	vpmovzxbq 0x24(%rax,%rdx,1),%ymm4
 104e052:	c5 f5 d4 cc          	vpaddq %ymm4,%ymm1,%ymm1
 104e056:	c4 e2 7d 32 64 10 28 	vpmovzxbq 0x28(%rax,%rdx,1),%ymm4
 104e05d:	c5 ed d4 d4          	vpaddq %ymm4,%ymm2,%ymm2
 104e061:	c4 e2 7d 32 64 10 2c 	vpmovzxbq 0x2c(%rax,%rdx,1),%ymm4
 104e068:	c5 e5 d4 dc          	vpaddq %ymm4,%ymm3,%ymm3
 104e06c:	48 83 c2 10          	add    $0x10,%rdx
 104e070:	49 39 d0             	cmp    %rdx,%r8
 104e073:	75 cb                	jne    104e040 <my.text::kernel+0x2cf0>
 104e075:	c5 f5 d4 c0          	vpaddq %ymm0,%ymm1,%ymm0
 104e079:	c5 ed d4 c0          	vpaddq %ymm0,%ymm2,%ymm0
 104e07d:	c5 e5 d4 c0          	vpaddq %ymm0,%ymm3,%ymm0
 104e081:	c4 e3 7d 39 c1 01    	vextracti128 $0x1,%ymm0,%xmm1
 104e087:	c5 f9 d4 c1          	vpaddq %xmm1,%xmm0,%xmm0
 104e08b:	c5 f9 70 c8 ee       	vpshufd $0xee,%xmm0,%xmm1
 104e090:	c5 f9 d4 c1          	vpaddq %xmm1,%xmm0,%xmm0
 104e094:	c4 e1 f9 7e c2       	vmovq  %xmm0,%rdx
 104e099:	4c 39 c1             	cmp    %r8,%rcx
 104e09c:	0f 84 7f 00 00 00    	je     104e121 <my.text::kernel+0x2dd1>
 104e0a2:	f6 c1 0c             	test   $0xc,%cl
 104e0a5:	74 69                	je     104e110 <my.text::kernel+0x2dc0>
 104e0a7:	4c 89 c7             	mov    %r8,%rdi
 104e0aa:	49 89 c8             	mov    %rcx,%r8
 104e0ad:	49 83 e0 fc          	and    $0xfffffffffffffffc,%r8
 104e0b1:	c4 e1 f9 6e c2       	vmovq  %rdx,%xmm0
 104e0b6:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 104e0bd:	00 00 00 
 104e0c0:	c4 e2 7d 32 4c 38 20 	vpmovzxbq 0x20(%rax,%rdi,1),%ymm1
 104e0c7:	c5 fd d4 c1          	vpaddq %ymm1,%ymm0,%ymm0
 104e0cb:	48 83 c7 04          	add    $0x4,%rdi
 104e0cf:	49 39 f8             	cmp    %rdi,%r8
 104e0d2:	75 ec                	jne    104e0c0 <my.text::kernel+0x2d70>
 104e0d4:	c4 e3 7d 39 c1 01    	vextracti128 $0x1,%ymm0,%xmm1
 104e0da:	c5 f9 d4 c1          	vpaddq %xmm1,%xmm0,%xmm0
 104e0de:	c5 f9 70 c8 ee       	vpshufd $0xee,%xmm0,%xmm1
 104e0e3:	c5 f9 d4 c1          	vpaddq %xmm1,%xmm0,%xmm0
 104e0e7:	c4 e1 f9 7e c2       	vmovq  %xmm0,%rdx
 104e0ec:	eb 2e                	jmp    104e11c <my.text::kernel+0x2dcc>
 104e0ee:	31 c9                	xor    %ecx,%ecx
 104e0f0:	45 31 c0             	xor    %r8d,%r8d
 104e0f3:	f6 c1 01             	test   $0x1,%cl
 104e0f6:	0f 85 5c fa ff ff    	jne    104db58 <my.text::kernel+0x2808>
 104e0fc:	e9 1f fb ff ff       	jmp    104dc20 <my.text::kernel+0x28d0>
 104e101:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 104e108:	0f 1f 84 00 00 00 00 
 104e10f:	00 
 104e110:	42 0f b6 7c 00 20    	movzbl 0x20(%rax,%r8,1),%edi
 104e116:	48 01 fa             	add    %rdi,%rdx
 104e119:	49 ff c0             	inc    %r8
 104e11c:	4c 39 c1             	cmp    %r8,%rcx
 104e11f:	75 ef                	jne    104e110 <my.text::kernel+0x2dc0>
 104e121:	48 89 f0             	mov    %rsi,%rax
 104e124:	48 01 d0             	add    %rdx,%rax
 104e127:	0f 80 cc 1b 00 00    	jo     104fcf9 <my.text::kernel+0x49a9>
 104e12d:	48 ff 44 24 70       	incq   0x70(%rsp)
 104e132:	48 89 84 24 a0 00 00 	mov    %rax,0xa0(%rsp)
 104e139:	00 
 104e13a:	e9 a4 f8 ff ff       	jmp    104d9e3 <my.text::kernel+0x2693>
