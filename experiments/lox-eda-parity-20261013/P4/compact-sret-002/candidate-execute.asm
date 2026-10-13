
.tmp/lox-eda-parity/P4/compact-sret-002/candidate/lox:     file format elf64-x86-64


Disassembly of section .text:

000000000105daf0 <my.interpreter::execute>:
 105daf0:	55                   	push   %rbp
 105daf1:	41 57                	push   %r15
 105daf3:	41 56                	push   %r14
 105daf5:	41 55                	push   %r13
 105daf7:	41 54                	push   %r12
 105daf9:	53                   	push   %rbx
 105dafa:	48 81 ec d8 02 00 00 	sub    $0x2d8,%rsp
 105db01:	4d 89 ce             	mov    %r9,%r14
 105db04:	4c 89 04 24          	mov    %r8,(%rsp)
 105db08:	49 89 c8             	mov    %rcx,%r8
 105db0b:	48 89 d3             	mov    %rdx,%rbx
 105db0e:	48 89 fd             	mov    %rdi,%rbp
 105db11:	4c 8b a4 24 30 03 00 	mov    0x330(%rsp),%r12
 105db18:	00 
 105db19:	48 8b 52 08          	mov    0x8(%rdx),%rdx
 105db1d:	4c 89 e0             	mov    %r12,%rax
 105db20:	49 39 d4             	cmp    %rdx,%r12
 105db23:	0f 83 a7 12 00 00    	jae    105edd0 <my.interpreter::execute+0x12e0>
 105db29:	4c 8b ac 24 28 03 00 	mov    0x328(%rsp),%r13
 105db30:	00 
 105db31:	44 0f b6 94 24 20 03 	movzbl 0x320(%rsp),%r10d
 105db38:	00 00 
 105db3a:	4c 8b 9c 24 18 03 00 	mov    0x318(%rsp),%r11
 105db41:	00 
 105db42:	48 6b c8 58          	imul   $0x58,%rax,%rcx
 105db46:	48 8d 04 0b          	lea    (%rbx,%rcx,1),%rax
 105db4a:	48 83 c0 20          	add    $0x20,%rax
 105db4e:	8b 4c 0b 20          	mov    0x20(%rbx,%rcx,1),%ecx
 105db52:	48 83 f9 07          	cmp    $0x7,%rcx
 105db56:	4c 89 44 24 30       	mov    %r8,0x30(%rsp)
 105db5b:	49 89 f7             	mov    %rsi,%r15
 105db5e:	0f 87 1f 07 00 00    	ja     105e283 <my.interpreter::execute+0x793>
 105db64:	48 8d 15 79 99 fa ff 	lea    -0x56687(%rip),%rdx        # 10074e4 <core_number_pairs+0x264>
 105db6b:	48 63 0c 8a          	movslq (%rdx,%rcx,4),%rcx
 105db6f:	48 01 d1             	add    %rdx,%rcx
 105db72:	ff e1                	jmp    *%rcx
 105db74:	48 8b 48 10          	mov    0x10(%rax),%rcx
 105db78:	49 8b 96 a8 00 00 00 	mov    0xa8(%r14),%rdx
 105db7f:	48 8d bc 24 c0 00 00 	lea    0xc0(%rsp),%rdi
 105db86:	00 
 105db87:	4c 89 f6             	mov    %r14,%rsi
 105db8a:	e8 a1 e8 00 00       	call   106c430 <my.interpreter::new_env>
 105db8f:	48 8b 94 24 c0 00 00 	mov    0xc0(%rsp),%rdx
 105db96:	00 
 105db97:	49 8b b6 a8 00 00 00 	mov    0xa8(%r14),%rsi
 105db9e:	49 8b 86 b0 00 00 00 	mov    0xb0(%r14),%rax
 105dba5:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105dba9:	48 3b 48 10          	cmp    0x10(%rax),%rcx
 105dbad:	0f 83 89 12 00 00    	jae    105ee3c <my.interpreter::execute+0x134c>
 105dbb3:	48 89 74 c8 20       	mov    %rsi,0x20(%rax,%rcx,8)
 105dbb8:	48 ff c1             	inc    %rcx
 105dbbb:	48 89 48 08          	mov    %rcx,0x8(%rax)
 105dbbf:	49 89 86 b0 00 00 00 	mov    %rax,0xb0(%r14)
 105dbc6:	49 89 96 a8 00 00 00 	mov    %rdx,0xa8(%r14)
 105dbcd:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 105dbd1:	49 39 d4             	cmp    %rdx,%r12
 105dbd4:	4c 8b 94 24 18 03 00 	mov    0x318(%rsp),%r10
 105dbdb:	00 
 105dbdc:	0f b6 b4 24 20 03 00 	movzbl 0x320(%rsp),%esi
 105dbe3:	00 
 105dbe4:	48 8b 4c 24 30       	mov    0x30(%rsp),%rcx
 105dbe9:	0f 83 77 12 00 00    	jae    105ee66 <my.interpreter::execute+0x1376>
 105dbef:	4c 89 e0             	mov    %r12,%rax
 105dbf2:	48 89 da             	mov    %rbx,%rdx
 105dbf5:	48 83 c2 20          	add    $0x20,%rdx
 105dbf9:	48 6b c0 58          	imul   $0x58,%rax,%rax
 105dbfd:	83 3c 02 00          	cmpl   $0x0,(%rdx,%rax,1)
 105dc01:	48 89 6c 24 18       	mov    %rbp,0x18(%rsp)
 105dc06:	0f 84 f3 0a 00 00    	je     105e6ff <my.interpreter::execute+0xc0f>
 105dc0c:	40 0f b6 f6          	movzbl %sil,%esi
 105dc10:	48 89 f3             	mov    %rsi,%rbx
 105dc13:	31 f6                	xor    %esi,%esi
 105dc15:	31 d2                	xor    %edx,%edx
 105dc17:	31 c0                	xor    %eax,%eax
 105dc19:	49 8b be b0 00 00 00 	mov    0xb0(%r14),%rdi
 105dc20:	4c 8b 47 08          	mov    0x8(%rdi),%r8
 105dc24:	4d 85 c0             	test   %r8,%r8
 105dc27:	48 8b 6c 24 18       	mov    0x18(%rsp),%rbp
 105dc2c:	0f 84 bb 14 00 00    	je     105f0ed <my.interpreter::execute+0x15fd>
 105dc32:	4e 8b 4c c7 18       	mov    0x18(%rdi,%r8,8),%r9
 105dc37:	49 ff c8             	dec    %r8
 105dc3a:	4c 89 47 08          	mov    %r8,0x8(%rdi)
 105dc3e:	4d 89 8e a8 00 00 00 	mov    %r9,0xa8(%r14)
 105dc45:	40 84 f6             	test   %sil,%sil
 105dc48:	0f 85 79 0f 00 00    	jne    105ebc7 <my.interpreter::execute+0x10d7>
 105dc4e:	48 89 55 00          	mov    %rdx,0x0(%rbp)
 105dc52:	48 89 45 08          	mov    %rax,0x8(%rbp)
 105dc56:	48 89 4d 10          	mov    %rcx,0x10(%rbp)
 105dc5a:	4c 89 55 18          	mov    %r10,0x18(%rbp)
 105dc5e:	48 89 5d 20          	mov    %rbx,0x20(%rbp)
 105dc62:	e9 e0 0e 00 00       	jmp    105eb47 <my.interpreter::execute+0x1057>
 105dc67:	48 8b 48 10          	mov    0x10(%rax),%rcx
 105dc6b:	48 89 4c 24 10       	mov    %rcx,0x10(%rsp)
 105dc70:	44 0f b6 60 18       	movzbl 0x18(%rax),%r12d
 105dc75:	48 8b 48 20          	mov    0x20(%rax),%rcx
 105dc79:	48 89 4c 24 20       	mov    %rcx,0x20(%rsp)
 105dc7e:	45 0f b6 d2          	movzbl %r10b,%r10d
 105dc82:	48 8d bc 24 10 02 00 	lea    0x210(%rsp),%rdi
 105dc89:	00 
 105dc8a:	48 89 da             	mov    %rbx,%rdx
 105dc8d:	4c 89 c1             	mov    %r8,%rcx
 105dc90:	4c 8b 04 24          	mov    (%rsp),%r8
 105dc94:	4d 89 f1             	mov    %r14,%r9
 105dc97:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105dc9e:	ff 70 08             	push   0x8(%rax)
 105dca1:	41 55                	push   %r13
 105dca3:	41 52                	push   %r10
 105dca5:	41 53                	push   %r11
 105dca7:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105dcae:	e8 dd 6f 00 00       	call   1064c90 <my.interpreter::evaluate>
 105dcb3:	48 83 c4 30          	add    $0x30,%rsp
 105dcb7:	4c 8b 9c 24 28 02 00 	mov    0x228(%rsp),%r11
 105dcbe:	00 
 105dcbf:	48 8b bc 24 30 02 00 	mov    0x230(%rsp),%rdi
 105dcc6:	00 
 105dcc7:	44 0f b6 d7          	movzbl %dil,%r10d
 105dccb:	4c 8b ac 24 38 02 00 	mov    0x238(%rsp),%r13
 105dcd2:	00 
 105dcd3:	80 bc 24 10 02 00 00 	cmpb   $0x1,0x210(%rsp)
 105dcda:	01 
 105dcdb:	0f 84 90 0e 00 00    	je     105eb71 <my.interpreter::execute+0x1081>
 105dce1:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105dce8:	48 89 c6             	mov    %rax,%rsi
 105dceb:	48 ff ce             	dec    %rsi
 105dcee:	0f 80 53 14 00 00    	jo     105f147 <my.interpreter::execute+0x1657>
 105dcf4:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105dcfb:	49 8b 46 78          	mov    0x78(%r14),%rax
 105dcff:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105dd03:	48 39 d6             	cmp    %rdx,%rsi
 105dd06:	48 8b 4c 24 30       	mov    0x30(%rsp),%rcx
 105dd0b:	0f 83 c1 11 00 00    	jae    105eed2 <my.interpreter::execute+0x13e2>
 105dd11:	49 89 f0             	mov    %rsi,%r8
 105dd14:	49 c1 e0 04          	shl    $0x4,%r8
 105dd18:	42 0f b6 54 00 20    	movzbl 0x20(%rax,%r8,1),%edx
 105dd1e:	85 d2                	test   %edx,%edx
 105dd20:	0f 84 2a 09 00 00    	je     105e650 <my.interpreter::execute+0xb60>
 105dd26:	83 fa 01             	cmp    $0x1,%edx
 105dd29:	75 11                	jne    105dd3c <my.interpreter::execute+0x24c>
 105dd2b:	4c 01 c0             	add    %r8,%rax
 105dd2e:	48 83 c0 20          	add    $0x20,%rax
 105dd32:	f6 40 08 01          	testb  $0x1,0x8(%rax)
 105dd36:	0f 84 14 09 00 00    	je     105e650 <my.interpreter::execute+0xb60>
 105dd3c:	48 8d bc 24 e0 01 00 	lea    0x1e0(%rsp),%rdi
 105dd43:	00 
 105dd44:	4c 89 fe             	mov    %r15,%rsi
 105dd47:	48 89 da             	mov    %rbx,%rdx
 105dd4a:	4c 8b 04 24          	mov    (%rsp),%r8
 105dd4e:	4d 89 f1             	mov    %r14,%r9
 105dd51:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105dd58:	ff 74 24 18          	push   0x18(%rsp)
 105dd5c:	41 55                	push   %r13
 105dd5e:	41 52                	push   %r10
 105dd60:	41 53                	push   %r11
 105dd62:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105dd69:	e8 82 fd ff ff       	call   105daf0 <my.interpreter::execute>
 105dd6e:	48 83 c4 30          	add    $0x30,%rsp
 105dd72:	0f b6 84 24 e0 01 00 	movzbl 0x1e0(%rsp),%eax
 105dd79:	00 
 105dd7a:	c5 f8 10 84 24 e8 01 	vmovups 0x1e8(%rsp),%xmm0
 105dd81:	00 00 
 105dd83:	48 8b 8c 24 f8 01 00 	mov    0x1f8(%rsp),%rcx
 105dd8a:	00 
 105dd8b:	0f b6 94 24 00 02 00 	movzbl 0x200(%rsp),%edx
 105dd92:	00 
 105dd93:	48 8b b4 24 08 02 00 	mov    0x208(%rsp),%rsi
 105dd9a:	00 
 105dd9b:	48 83 f8 01          	cmp    $0x1,%rax
 105dd9f:	0f 85 1e 09 00 00    	jne    105e6c3 <my.interpreter::execute+0xbd3>
 105dda5:	48 8d 3d c4 22 02 00 	lea    0x222c4(%rip),%rdi        # 1080070 <core_durable_error.verbs+0x1170>
 105ddac:	e9 e7 0f 00 00       	jmp    105ed98 <my.interpreter::execute+0x12a8>
 105ddb1:	48 8b 40 08          	mov    0x8(%rax),%rax
 105ddb5:	48 8b 56 08          	mov    0x8(%rsi),%rdx
 105ddb9:	48 89 c1             	mov    %rax,%rcx
 105ddbc:	48 39 d0             	cmp    %rdx,%rax
 105ddbf:	0f 83 30 10 00 00    	jae    105edf5 <my.interpreter::execute+0x1305>
 105ddc5:	48 6b c9 70          	imul   $0x70,%rcx,%rcx
 105ddc9:	83 7c 0e 20 0b       	cmpl   $0xb,0x20(%rsi,%rcx,1)
 105ddce:	0f 85 58 06 00 00    	jne    105e42c <my.interpreter::execute+0x93c>
 105ddd4:	48 01 f1             	add    %rsi,%rcx
 105ddd7:	48 83 c1 20          	add    $0x20,%rcx
 105dddb:	48 8b 79 38          	mov    0x38(%rcx),%rdi
 105dddf:	48 83 ff ff          	cmp    $0xffffffffffffffff,%rdi
 105dde3:	0f 84 43 06 00 00    	je     105e42c <my.interpreter::execute+0x93c>
 105dde9:	48 8b 71 40          	mov    0x40(%rcx),%rsi
 105dded:	49 8b 0e             	mov    (%r14),%rcx
 105ddf0:	49 8b 86 a8 00 00 00 	mov    0xa8(%r14),%rax
 105ddf7:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105ddfb:	48 85 ff             	test   %rdi,%rdi
 105ddfe:	0f 8e c0 09 00 00    	jle    105e7c4 <my.interpreter::execute+0xcd4>
 105de04:	4c 8d 41 20          	lea    0x20(%rcx),%r8
 105de08:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105de0f:	0f 1f 84 00 00 00 00 
 105de16:	00 
 105de17:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105de1e:	0f 1f 84 00 00 00 00 
 105de25:	00 
 105de26:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105de2d:	0f 1f 84 00 00 00 00 
 105de34:	00 
 105de35:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 105de3c:	00 00 00 00 
 105de40:	48 39 d0             	cmp    %rdx,%rax
 105de43:	73 23                	jae    105de68 <my.interpreter::execute+0x378>
 105de45:	49 89 c1             	mov    %rax,%r9
 105de48:	49 6b c1 38          	imul   $0x38,%r9,%rax
 105de4c:	41 83 3c 00 09       	cmpl   $0x9,(%r8,%rax,1)
 105de51:	0f 85 6d 12 00 00    	jne    105f0c4 <my.interpreter::execute+0x15d4>
 105de57:	4c 01 c0             	add    %r8,%rax
 105de5a:	48 8b 40 08          	mov    0x8(%rax),%rax
 105de5e:	48 ff cf             	dec    %rdi
 105de61:	75 dd                	jne    105de40 <my.interpreter::execute+0x350>
 105de63:	e9 5c 09 00 00       	jmp    105e7c4 <my.interpreter::execute+0xcd4>
 105de68:	49 89 c1             	mov    %rax,%r9
 105de6b:	49 c1 f9 3f          	sar    $0x3f,%r9
 105de6f:	49 21 d1             	and    %rdx,%r9
 105de72:	49 01 c1             	add    %rax,%r9
 105de75:	49 39 d1             	cmp    %rdx,%r9
 105de78:	72 ce                	jb     105de48 <my.interpreter::execute+0x358>
 105de7a:	48 8d 3d 4f 6d 02 00 	lea    0x26d4f(%rip),%rdi        # 1084bd0 <core_durable_error.verbs+0x5cd0>
 105de81:	48 89 c6             	mov    %rax,%rsi
 105de84:	e8 37 66 fc ff       	call   10244c0 <myl_core_trap>
 105de89:	4d 89 dc             	mov    %r11,%r12
 105de8c:	48 8b 70 08          	mov    0x8(%rax),%rsi
 105de90:	49 8b 50 08          	mov    0x8(%r8),%rdx
 105de94:	48 89 f0             	mov    %rsi,%rax
 105de97:	48 39 d6             	cmp    %rdx,%rsi
 105de9a:	0f 83 7a 0f 00 00    	jae    105ee1a <my.interpreter::execute+0x132a>
 105dea0:	48 8d 04 80          	lea    (%rax,%rax,4),%rax
 105dea4:	48 c1 e0 04          	shl    $0x4,%rax
 105dea8:	49 8b 5c 00 48       	mov    0x48(%r8,%rax,1),%rbx
 105dead:	4d 8b 7c 00 60       	mov    0x60(%r8,%rax,1),%r15
 105deb2:	49 8b 86 a8 00 00 00 	mov    0xa8(%r14),%rax
 105deb9:	48 c7 84 24 70 02 00 	movq   $0xa,0x270(%rsp)
 105dec0:	00 0a 00 00 00 
 105dec5:	48 89 b4 24 78 02 00 	mov    %rsi,0x278(%rsp)
 105decc:	00 
 105decd:	48 89 9c 24 80 02 00 	mov    %rbx,0x280(%rsp)
 105ded4:	00 
 105ded5:	48 89 84 24 88 02 00 	mov    %rax,0x288(%rsp)
 105dedc:	00 
 105dedd:	c6 84 24 90 02 00 00 	movb   $0x0,0x290(%rsp)
 105dee4:	00 
 105dee5:	48 8d 7c 24 68       	lea    0x68(%rsp),%rdi
 105deea:	48 8d 94 24 70 02 00 	lea    0x270(%rsp),%rdx
 105def1:	00 
 105def2:	4c 89 f6             	mov    %r14,%rsi
 105def5:	e8 96 c2 ff ff       	call   105a190 <my.heap::allocate>
 105defa:	48 8b 44 24 68       	mov    0x68(%rsp),%rax
 105deff:	49 8b 4e 78          	mov    0x78(%r14),%rcx
 105df03:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105df0a:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105df0e:	48 39 d6             	cmp    %rdx,%rsi
 105df11:	0f 83 74 0f 00 00    	jae    105ee8b <my.interpreter::execute+0x139b>
 105df17:	48 89 f7             	mov    %rsi,%rdi
 105df1a:	48 c1 e7 04          	shl    $0x4,%rdi
 105df1e:	48 c7 44 39 20 03 00 	movq   $0x3,0x20(%rcx,%rdi,1)
 105df25:	00 00 
 105df27:	48 89 44 39 28       	mov    %rax,0x28(%rcx,%rdi,1)
 105df2c:	49 89 4e 78          	mov    %rcx,0x78(%r14)
 105df30:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105df37:	48 89 f0             	mov    %rsi,%rax
 105df3a:	48 ff c0             	inc    %rax
 105df3d:	0f 80 ba 11 00 00    	jo     105f0fd <my.interpreter::execute+0x160d>
 105df43:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 105df4a:	4c 89 f7             	mov    %r14,%rdi
 105df4d:	48 89 de             	mov    %rbx,%rsi
 105df50:	4c 89 fa             	mov    %r15,%rdx
 105df53:	e8 98 9a 00 00       	call   10679f0 <my.interpreter::define>
 105df58:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105df5f:	48 89 c6             	mov    %rax,%rsi
 105df62:	48 ff ce             	dec    %rsi
 105df65:	0f 80 a3 11 00 00    	jo     105f10e <my.interpreter::execute+0x161e>
 105df6b:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105df72:	49 8b 46 78          	mov    0x78(%r14),%rax
 105df76:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105df7a:	48 39 d6             	cmp    %rdx,%rsi
 105df7d:	4d 89 e3             	mov    %r12,%r11
 105df80:	0f b6 bc 24 20 03 00 	movzbl 0x320(%rsp),%edi
 105df87:	00 
 105df88:	0f 82 a4 0b 00 00    	jb     105eb32 <my.interpreter::execute+0x1042>
 105df8e:	48 89 f0             	mov    %rsi,%rax
 105df91:	48 c1 f8 3f          	sar    $0x3f,%rax
 105df95:	48 21 d0             	and    %rdx,%rax
 105df98:	48 01 f0             	add    %rsi,%rax
 105df9b:	48 39 d0             	cmp    %rdx,%rax
 105df9e:	0f 82 8e 0b 00 00    	jb     105eb32 <my.interpreter::execute+0x1042>
 105dfa4:	48 8d 3d a5 25 02 00 	lea    0x225a5(%rip),%rdi        # 1080550 <core_durable_error.verbs+0x1650>
 105dfab:	e8 10 65 fc ff       	call   10244c0 <myl_core_trap>
 105dfb0:	4c 8b 60 30          	mov    0x30(%rax),%r12
 105dfb4:	4c 8b 48 48          	mov    0x48(%rax),%r9
 105dfb8:	80 78 38 01          	cmpb   $0x1,0x38(%rax)
 105dfbc:	0f 85 14 05 00 00    	jne    105e4d6 <my.interpreter::execute+0x9e6>
 105dfc2:	4c 89 4c 24 30       	mov    %r9,0x30(%rsp)
 105dfc7:	45 0f b6 d2          	movzbl %r10b,%r10d
 105dfcb:	48 8d bc 24 50 01 00 	lea    0x150(%rsp),%rdi
 105dfd2:	00 
 105dfd3:	48 89 da             	mov    %rbx,%rdx
 105dfd6:	4c 89 c1             	mov    %r8,%rcx
 105dfd9:	4c 8b 04 24          	mov    (%rsp),%r8
 105dfdd:	4d 89 f1             	mov    %r14,%r9
 105dfe0:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105dfe7:	ff 70 40             	push   0x40(%rax)
 105dfea:	41 55                	push   %r13
 105dfec:	41 52                	push   %r10
 105dfee:	41 53                	push   %r11
 105dff0:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105dff7:	e8 94 6c 00 00       	call   1064c90 <my.interpreter::evaluate>
 105dffc:	48 83 c4 30          	add    $0x30,%rsp
 105e000:	48 8b 9c 24 68 01 00 	mov    0x168(%rsp),%rbx
 105e007:	00 
 105e008:	4c 8b bc 24 70 01 00 	mov    0x170(%rsp),%r15
 105e00f:	00 
 105e010:	4c 8b ac 24 78 01 00 	mov    0x178(%rsp),%r13
 105e017:	00 
 105e018:	80 bc 24 50 01 00 00 	cmpb   $0x1,0x150(%rsp)
 105e01f:	01 
 105e020:	0f 84 89 0c 00 00    	je     105ecaf <my.interpreter::execute+0x11bf>
 105e026:	4c 8b 4c 24 30       	mov    0x30(%rsp),%r9
 105e02b:	e9 f2 04 00 00       	jmp    105e522 <my.interpreter::execute+0xa32>
 105e030:	48 8b 48 30          	mov    0x30(%rax),%rcx
 105e034:	48 89 4c 24 20       	mov    %rcx,0x20(%rsp)
 105e039:	48 8b 48 38          	mov    0x38(%rax),%rcx
 105e03d:	44 0f b6 60 40       	movzbl 0x40(%rax),%r12d
 105e042:	48 8b 50 48          	mov    0x48(%rax),%rdx
 105e046:	48 89 54 24 28       	mov    %rdx,0x28(%rsp)
 105e04b:	48 8b 40 50          	mov    0x50(%rax),%rax
 105e04f:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105e054:	48 89 4c 24 60       	mov    %rcx,0x60(%rsp)
 105e059:	48 83 f9 ff          	cmp    $0xffffffffffffffff,%rcx
 105e05d:	75 51                	jne    105e0b0 <my.interpreter::execute+0x5c0>
 105e05f:	4c 89 f7             	mov    %r14,%rdi
 105e062:	4c 8b 6c 24 20       	mov    0x20(%rsp),%r13
 105e067:	4c 89 ee             	mov    %r13,%rsi
 105e06a:	e8 f1 ba 00 00       	call   1069b60 <my.heap::string_hash>
 105e06f:	49 8b 7e 30          	mov    0x30(%r14),%rdi
 105e073:	49 8b 76 38          	mov    0x38(%r14),%rsi
 105e077:	4c 89 ea             	mov    %r13,%rdx
 105e07a:	89 c1                	mov    %eax,%ecx
 105e07c:	45 31 c0             	xor    %r8d,%r8d
 105e07f:	45 31 c9             	xor    %r9d,%r9d
 105e082:	e8 b9 bb 00 00       	call   1069c40 <my.table::set>
 105e087:	4c 89 fe             	mov    %r15,%rsi
 105e08a:	4c 8b 44 24 30       	mov    0x30(%rsp),%r8
 105e08f:	44 0f b6 94 24 20 03 	movzbl 0x320(%rsp),%r10d
 105e096:	00 00 
 105e098:	4c 8b 9c 24 18 03 00 	mov    0x318(%rsp),%r11
 105e09f:	00 
 105e0a0:	4c 8b ac 24 28 03 00 	mov    0x328(%rsp),%r13
 105e0a7:	00 
 105e0a8:	49 89 56 30          	mov    %rdx,0x30(%r14)
 105e0ac:	49 89 4e 38          	mov    %rcx,0x38(%r14)
 105e0b0:	49 c7 c7 ff ff ff ff 	mov    $0xffffffffffffffff,%r15
 105e0b7:	41 83 fc 01          	cmp    $0x1,%r12d
 105e0bb:	0f 85 c2 04 00 00    	jne    105e583 <my.interpreter::execute+0xa93>
 105e0c1:	41 0f b6 c2          	movzbl %r10b,%eax
 105e0c5:	48 8d bc 24 c0 00 00 	lea    0xc0(%rsp),%rdi
 105e0cc:	00 
 105e0cd:	49 89 f7             	mov    %rsi,%r15
 105e0d0:	48 89 da             	mov    %rbx,%rdx
 105e0d3:	4c 89 c1             	mov    %r8,%rcx
 105e0d6:	4c 8b 04 24          	mov    (%rsp),%r8
 105e0da:	4d 89 f1             	mov    %r14,%r9
 105e0dd:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e0e4:	48 8b 5c 24 30       	mov    0x30(%rsp),%rbx
 105e0e9:	53                   	push   %rbx
 105e0ea:	41 55                	push   %r13
 105e0ec:	50                   	push   %rax
 105e0ed:	41 53                	push   %r11
 105e0ef:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e0f6:	e8 95 6b 00 00       	call   1064c90 <my.interpreter::evaluate>
 105e0fb:	48 83 c4 30          	add    $0x30,%rsp
 105e0ff:	48 8b bc 24 d8 00 00 	mov    0xd8(%rsp),%rdi
 105e106:	00 
 105e107:	44 0f b6 84 24 e0 00 	movzbl 0xe0(%rsp),%r8d
 105e10e:	00 00 
 105e110:	4c 8b ac 24 e8 00 00 	mov    0xe8(%rsp),%r13
 105e117:	00 
 105e118:	80 bc 24 c0 00 00 00 	cmpb   $0x1,0xc0(%rsp)
 105e11f:	01 
 105e120:	0f 84 c2 0b 00 00    	je     105ece8 <my.interpreter::execute+0x11f8>
 105e126:	49 8b 57 08          	mov    0x8(%r15),%rdx
 105e12a:	48 39 d3             	cmp    %rdx,%rbx
 105e12d:	0f 83 a6 0e 00 00    	jae    105efd9 <my.interpreter::execute+0x14e9>
 105e133:	48 89 d8             	mov    %rbx,%rax
 105e136:	48 6b c0 70          	imul   $0x70,%rax,%rax
 105e13a:	41 83 7c 07 20 0b    	cmpl   $0xb,0x20(%r15,%rax,1)
 105e140:	0f 85 df 06 00 00    	jne    105e825 <my.interpreter::execute+0xd35>
 105e146:	4c 01 f8             	add    %r15,%rax
 105e149:	48 83 c0 20          	add    $0x20,%rax
 105e14d:	48 8b 58 20          	mov    0x20(%rax),%rbx
 105e151:	e9 d1 06 00 00       	jmp    105e827 <my.interpreter::execute+0xd37>
 105e156:	45 0f b6 d2          	movzbl %r10b,%r10d
 105e15a:	48 8d bc 24 80 01 00 	lea    0x180(%rsp),%rdi
 105e161:	00 
 105e162:	48 89 da             	mov    %rbx,%rdx
 105e165:	4c 89 c1             	mov    %r8,%rcx
 105e168:	4c 8b 04 24          	mov    (%rsp),%r8
 105e16c:	4d 89 f1             	mov    %r14,%r9
 105e16f:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e176:	ff 70 08             	push   0x8(%rax)
 105e179:	41 55                	push   %r13
 105e17b:	41 52                	push   %r10
 105e17d:	41 53                	push   %r11
 105e17f:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e186:	e8 05 6b 00 00       	call   1064c90 <my.interpreter::evaluate>
 105e18b:	48 83 c4 30          	add    $0x30,%rsp
 105e18f:	48 8b 9c 24 98 01 00 	mov    0x198(%rsp),%rbx
 105e196:	00 
 105e197:	4c 8b bc 24 a0 01 00 	mov    0x1a0(%rsp),%r15
 105e19e:	00 
 105e19f:	4c 8b ac 24 a8 01 00 	mov    0x1a8(%rsp),%r13
 105e1a6:	00 
 105e1a7:	80 bc 24 80 01 00 00 	cmpb   $0x1,0x180(%rsp)
 105e1ae:	01 
 105e1af:	0f 84 f4 09 00 00    	je     105eba9 <my.interpreter::execute+0x10b9>
 105e1b5:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105e1bc:	48 89 c6             	mov    %rax,%rsi
 105e1bf:	48 ff ce             	dec    %rsi
 105e1c2:	0f 80 93 0f 00 00    	jo     105f15b <my.interpreter::execute+0x166b>
 105e1c8:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e1cc:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e1d0:	48 39 d6             	cmp    %rdx,%rsi
 105e1d3:	0f 83 1b 0d 00 00    	jae    105eef4 <my.interpreter::execute+0x1404>
 105e1d9:	48 89 f7             	mov    %rsi,%rdi
 105e1dc:	48 c1 e7 04          	shl    $0x4,%rdi
 105e1e0:	48 8b 4c 38 28       	mov    0x28(%rax,%rdi,1),%rcx
 105e1e5:	8b 54 38 20          	mov    0x20(%rax,%rdi,1),%edx
 105e1e9:	4c 89 f7             	mov    %r14,%rdi
 105e1ec:	48 8b b4 24 10 03 00 	mov    0x310(%rsp),%rsi
 105e1f3:	00 
 105e1f4:	e8 37 44 00 00       	call   1062630 <my.output::print_value>
 105e1f9:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105e200:	48 89 f0             	mov    %rsi,%rax
 105e203:	48 ff c8             	dec    %rax
 105e206:	0f 80 63 0f 00 00    	jo     105f16f <my.interpreter::execute+0x167f>
 105e20c:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 105e213:	49 89 db             	mov    %rbx,%r11
 105e216:	4c 89 ff             	mov    %r15,%rdi
 105e219:	e9 14 09 00 00       	jmp    105eb32 <my.interpreter::execute+0x1042>
 105e21e:	83 78 30 01          	cmpl   $0x1,0x30(%rax)
 105e222:	0f 85 6a 03 00 00    	jne    105e592 <my.interpreter::execute+0xaa2>
 105e228:	45 0f b6 d2          	movzbl %r10b,%r10d
 105e22c:	48 8d bc 24 a8 02 00 	lea    0x2a8(%rsp),%rdi
 105e233:	00 
 105e234:	48 89 da             	mov    %rbx,%rdx
 105e237:	4c 89 c1             	mov    %r8,%rcx
 105e23a:	4c 8b 04 24          	mov    (%rsp),%r8
 105e23e:	4d 89 f1             	mov    %r14,%r9
 105e241:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e248:	ff 70 38             	push   0x38(%rax)
 105e24b:	41 55                	push   %r13
 105e24d:	41 52                	push   %r10
 105e24f:	41 53                	push   %r11
 105e251:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e258:	e8 33 6a 00 00       	call   1064c90 <my.interpreter::evaluate>
 105e25d:	48 83 c4 30          	add    $0x30,%rsp
 105e261:	4c 8b 9c 24 c0 02 00 	mov    0x2c0(%rsp),%r11
 105e268:	00 
 105e269:	80 bc 24 a8 02 00 00 	cmpb   $0x1,0x2a8(%rsp)
 105e270:	01 
 105e271:	0f 84 c5 0a 00 00    	je     105ed3c <my.interpreter::execute+0x124c>
 105e277:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105e27e:	e9 55 03 00 00       	jmp    105e5d8 <my.interpreter::execute+0xae8>
 105e283:	48 89 6c 24 18       	mov    %rbp,0x18(%rsp)
 105e288:	4c 8b 60 08          	mov    0x8(%rax),%r12
 105e28c:	48 8b 40 10          	mov    0x10(%rax),%rax
 105e290:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105e295:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105e29c:	0f 1f 84 00 00 00 00 
 105e2a3:	00 
 105e2a4:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105e2ab:	0f 1f 84 00 00 00 00 
 105e2b2:	00 
 105e2b3:	66 66 66 66 2e 0f 1f 	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105e2ba:	84 00 00 00 00 00 
 105e2c0:	41 0f b6 c2          	movzbl %r10b,%eax
 105e2c4:	48 8d bc 24 20 01 00 	lea    0x120(%rsp),%rdi
 105e2cb:	00 
 105e2cc:	48 89 da             	mov    %rbx,%rdx
 105e2cf:	4c 89 c1             	mov    %r8,%rcx
 105e2d2:	4c 8b 04 24          	mov    (%rsp),%r8
 105e2d6:	4d 89 f1             	mov    %r14,%r9
 105e2d9:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e2e0:	41 54                	push   %r12
 105e2e2:	41 55                	push   %r13
 105e2e4:	50                   	push   %rax
 105e2e5:	41 53                	push   %r11
 105e2e7:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e2ee:	e8 9d 69 00 00       	call   1064c90 <my.interpreter::evaluate>
 105e2f3:	48 83 c4 30          	add    $0x30,%rsp
 105e2f7:	4c 8b 94 24 38 01 00 	mov    0x138(%rsp),%r10
 105e2fe:	00 
 105e2ff:	48 8b 84 24 40 01 00 	mov    0x140(%rsp),%rax
 105e306:	00 
 105e307:	0f b6 e8             	movzbl %al,%ebp
 105e30a:	4c 8b ac 24 48 01 00 	mov    0x148(%rsp),%r13
 105e311:	00 
 105e312:	80 bc 24 20 01 00 00 	cmpb   $0x1,0x120(%rsp)
 105e319:	01 
 105e31a:	0f 84 25 09 00 00    	je     105ec45 <my.interpreter::execute+0x1155>
 105e320:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105e327:	48 89 c6             	mov    %rax,%rsi
 105e32a:	48 ff ce             	dec    %rsi
 105e32d:	0f 80 7d 0d 00 00    	jo     105f0b0 <my.interpreter::execute+0x15c0>
 105e333:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105e33a:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e33e:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e342:	48 39 d6             	cmp    %rdx,%rsi
 105e345:	48 8b 4c 24 30       	mov    0x30(%rsp),%rcx
 105e34a:	0f 83 ba 00 00 00    	jae    105e40a <my.interpreter::execute+0x91a>
 105e350:	48 89 f7             	mov    %rsi,%rdi
 105e353:	48 c1 e7 04          	shl    $0x4,%rdi
 105e357:	0f b6 54 38 20       	movzbl 0x20(%rax,%rdi,1),%edx
 105e35c:	83 fa 01             	cmp    $0x1,%edx
 105e35f:	74 1f                	je     105e380 <my.interpreter::execute+0x890>
 105e361:	85 d2                	test   %edx,%edx
 105e363:	4c 89 fe             	mov    %r15,%rsi
 105e366:	75 2c                	jne    105e394 <my.interpreter::execute+0x8a4>
 105e368:	e9 c2 02 00 00       	jmp    105e62f <my.interpreter::execute+0xb3f>
 105e36d:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105e374:	0f 1f 84 00 00 00 00 
 105e37b:	00 
 105e37c:	0f 1f 40 00          	nopl   0x0(%rax)
 105e380:	48 01 f8             	add    %rdi,%rax
 105e383:	48 83 c0 20          	add    $0x20,%rax
 105e387:	f6 40 08 01          	testb  $0x1,0x8(%rax)
 105e38b:	4c 89 fe             	mov    %r15,%rsi
 105e38e:	0f 84 9b 02 00 00    	je     105e62f <my.interpreter::execute+0xb3f>
 105e394:	48 8d bc 24 f0 00 00 	lea    0xf0(%rsp),%rdi
 105e39b:	00 
 105e39c:	48 89 da             	mov    %rbx,%rdx
 105e39f:	4c 8b 04 24          	mov    (%rsp),%r8
 105e3a3:	4d 89 f1             	mov    %r14,%r9
 105e3a6:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e3ad:	ff 74 24 18          	push   0x18(%rsp)
 105e3b1:	41 55                	push   %r13
 105e3b3:	55                   	push   %rbp
 105e3b4:	41 52                	push   %r10
 105e3b6:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e3bd:	e8 2e f7 ff ff       	call   105daf0 <my.interpreter::execute>
 105e3c2:	48 83 c4 30          	add    $0x30,%rsp
 105e3c6:	48 8b 84 24 f8 00 00 	mov    0xf8(%rsp),%rax
 105e3cd:	00 
 105e3ce:	4c 8b 9c 24 08 01 00 	mov    0x108(%rsp),%r11
 105e3d5:	00 
 105e3d6:	44 0f b6 94 24 10 01 	movzbl 0x110(%rsp),%r10d
 105e3dd:	00 00 
 105e3df:	4c 8b ac 24 18 01 00 	mov    0x118(%rsp),%r13
 105e3e6:	00 
 105e3e7:	80 bc 24 f0 00 00 00 	cmpb   $0x1,0xf0(%rsp)
 105e3ee:	01 
 105e3ef:	0f 84 85 08 00 00    	je     105ec7a <my.interpreter::execute+0x118a>
 105e3f5:	3c 01                	cmp    $0x1,%al
 105e3f7:	4c 8b 44 24 30       	mov    0x30(%rsp),%r8
 105e3fc:	4c 89 fe             	mov    %r15,%rsi
 105e3ff:	0f 85 bb fe ff ff    	jne    105e2c0 <my.interpreter::execute+0x7d0>
 105e405:	e9 d3 02 00 00       	jmp    105e6dd <my.interpreter::execute+0xbed>
 105e40a:	48 89 f7             	mov    %rsi,%rdi
 105e40d:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105e411:	48 21 d7             	and    %rdx,%rdi
 105e414:	48 01 f7             	add    %rsi,%rdi
 105e417:	48 39 d7             	cmp    %rdx,%rdi
 105e41a:	0f 82 33 ff ff ff    	jb     105e353 <my.interpreter::execute+0x863>
 105e420:	48 8d 3d c9 20 02 00 	lea    0x220c9(%rip),%rdi        # 10804f0 <core_durable_error.verbs+0x15f0>
 105e427:	e8 94 60 fc ff       	call   10244c0 <myl_core_trap>
 105e42c:	45 0f b6 d2          	movzbl %r10b,%r10d
 105e430:	48 8d bc 24 40 02 00 	lea    0x240(%rsp),%rdi
 105e437:	00 
 105e438:	48 89 da             	mov    %rbx,%rdx
 105e43b:	4c 89 c1             	mov    %r8,%rcx
 105e43e:	4c 8b 04 24          	mov    (%rsp),%r8
 105e442:	4d 89 f1             	mov    %r14,%r9
 105e445:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e44c:	50                   	push   %rax
 105e44d:	41 55                	push   %r13
 105e44f:	41 52                	push   %r10
 105e451:	41 53                	push   %r11
 105e453:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e45a:	e8 31 68 00 00       	call   1064c90 <my.interpreter::evaluate>
 105e45f:	48 83 c4 30          	add    $0x30,%rsp
 105e463:	4c 8b 9c 24 58 02 00 	mov    0x258(%rsp),%r11
 105e46a:	00 
 105e46b:	48 8b bc 24 60 02 00 	mov    0x260(%rsp),%rdi
 105e472:	00 
 105e473:	4c 8b ac 24 68 02 00 	mov    0x268(%rsp),%r13
 105e47a:	00 
 105e47b:	80 bc 24 40 02 00 00 	cmpb   $0x1,0x240(%rsp)
 105e482:	01 
 105e483:	0f 84 80 07 00 00    	je     105ec09 <my.interpreter::execute+0x1119>
 105e489:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105e490:	48 89 c6             	mov    %rax,%rsi
 105e493:	48 ff ce             	dec    %rsi
 105e496:	0f 80 21 0d 00 00    	jo     105f1bd <my.interpreter::execute+0x16cd>
 105e49c:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105e4a3:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e4a7:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e4ab:	48 39 d6             	cmp    %rdx,%rsi
 105e4ae:	0f 82 7e 06 00 00    	jb     105eb32 <my.interpreter::execute+0x1042>
 105e4b4:	48 89 f0             	mov    %rsi,%rax
 105e4b7:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e4bb:	48 21 d0             	and    %rdx,%rax
 105e4be:	48 01 f0             	add    %rsi,%rax
 105e4c1:	48 39 d0             	cmp    %rdx,%rax
 105e4c4:	0f 82 68 06 00 00    	jb     105eb32 <my.interpreter::execute+0x1042>
 105e4ca:	48 8d 3d 1f 1d 02 00 	lea    0x21d1f(%rip),%rdi        # 10801f0 <core_durable_error.verbs+0x12f0>
 105e4d1:	e8 ea 5f fc ff       	call   10244c0 <myl_core_trap>
 105e4d6:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e4da:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105e4e1:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e4e5:	48 39 d6             	cmp    %rdx,%rsi
 105e4e8:	0f 83 a7 0a 00 00    	jae    105ef95 <my.interpreter::execute+0x14a5>
 105e4ee:	48 89 f1             	mov    %rsi,%rcx
 105e4f1:	48 c1 e1 04          	shl    $0x4,%rcx
 105e4f5:	48 c7 44 08 20 00 00 	movq   $0x0,0x20(%rax,%rcx,1)
 105e4fc:	00 00 
 105e4fe:	49 89 46 78          	mov    %rax,0x78(%r14)
 105e502:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105e509:	48 89 f0             	mov    %rsi,%rax
 105e50c:	48 ff c0             	inc    %rax
 105e50f:	0f 80 dd 0c 00 00    	jo     105f1f2 <my.interpreter::execute+0x1702>
 105e515:	4d 89 d7             	mov    %r10,%r15
 105e518:	4c 89 db             	mov    %r11,%rbx
 105e51b:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 105e522:	4c 89 f7             	mov    %r14,%rdi
 105e525:	4c 89 e6             	mov    %r12,%rsi
 105e528:	4c 89 ca             	mov    %r9,%rdx
 105e52b:	e8 c0 94 00 00       	call   10679f0 <my.interpreter::define>
 105e530:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105e537:	48 89 c6             	mov    %rax,%rsi
 105e53a:	48 ff ce             	dec    %rsi
 105e53d:	0f 80 df 0b 00 00    	jo     105f122 <my.interpreter::execute+0x1632>
 105e543:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105e54a:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e54e:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e552:	48 39 d6             	cmp    %rdx,%rsi
 105e555:	49 89 db             	mov    %rbx,%r11
 105e558:	4c 89 ff             	mov    %r15,%rdi
 105e55b:	0f 82 d1 05 00 00    	jb     105eb32 <my.interpreter::execute+0x1042>
 105e561:	48 89 f0             	mov    %rsi,%rax
 105e564:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e568:	48 21 d0             	and    %rdx,%rax
 105e56b:	48 01 f0             	add    %rsi,%rax
 105e56e:	48 39 d0             	cmp    %rdx,%rax
 105e571:	0f 82 bb 05 00 00    	jb     105eb32 <my.interpreter::execute+0x1042>
 105e577:	48 8d 3d b2 1e 02 00 	lea    0x21eb2(%rip),%rdi        # 1080430 <core_durable_error.verbs+0x1530>
 105e57e:	e8 3d 5f fc ff       	call   10244c0 <myl_core_trap>
 105e583:	4c 89 54 24 28       	mov    %r10,0x28(%rsp)
 105e588:	4c 89 5c 24 48       	mov    %r11,0x48(%rsp)
 105e58d:	e9 fc 02 00 00       	jmp    105e88e <my.interpreter::execute+0xd9e>
 105e592:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e596:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105e59d:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e5a1:	48 39 d6             	cmp    %rdx,%rsi
 105e5a4:	0f 83 0d 0a 00 00    	jae    105efb7 <my.interpreter::execute+0x14c7>
 105e5aa:	48 89 f1             	mov    %rsi,%rcx
 105e5ad:	48 c1 e1 04          	shl    $0x4,%rcx
 105e5b1:	48 c7 44 08 20 00 00 	movq   $0x0,0x20(%rax,%rcx,1)
 105e5b8:	00 00 
 105e5ba:	49 89 46 78          	mov    %rax,0x78(%r14)
 105e5be:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105e5c5:	48 89 c6             	mov    %rax,%rsi
 105e5c8:	48 ff c6             	inc    %rsi
 105e5cb:	0f 80 32 0c 00 00    	jo     105f203 <my.interpreter::execute+0x1713>
 105e5d1:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105e5d8:	48 89 f0             	mov    %rsi,%rax
 105e5db:	48 ff c8             	dec    %rax
 105e5de:	0f 80 52 0b 00 00    	jo     105f136 <my.interpreter::execute+0x1646>
 105e5e4:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 105e5eb:	49 8b 4e 78          	mov    0x78(%r14),%rcx
 105e5ef:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105e5f3:	48 39 d0             	cmp    %rdx,%rax
 105e5f6:	0f 83 b1 08 00 00    	jae    105eead <my.interpreter::execute+0x13bd>
 105e5fc:	48 89 c6             	mov    %rax,%rsi
 105e5ff:	48 c1 e6 04          	shl    $0x4,%rsi
 105e603:	c5 f8 10 44 31 20    	vmovups 0x20(%rcx,%rsi,1),%xmm0
 105e609:	48 c7 45 00 00 00 00 	movq   $0x0,0x0(%rbp)
 105e610:	00 
 105e611:	48 c7 45 08 01 00 00 	movq   $0x1,0x8(%rbp)
 105e618:	00 
 105e619:	4c 89 5d 18          	mov    %r11,0x18(%rbp)
 105e61d:	c5 f8 54 05 bb 5d fa 	vandps -0x5a245(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105e624:	ff 
 105e625:	c5 f8 11 45 20       	vmovups %xmm0,0x20(%rbp)
 105e62a:	e9 1c 05 00 00       	jmp    105eb4b <my.interpreter::execute+0x105b>
 105e62f:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
 105e633:	48 8b 44 24 18       	mov    0x18(%rsp),%rax
 105e638:	c5 f8 11 00          	vmovups %xmm0,(%rax)
 105e63c:	4c 89 50 18          	mov    %r10,0x18(%rax)
 105e640:	48 89 68 20          	mov    %rbp,0x20(%rax)
 105e644:	48 89 c5             	mov    %rax,%rbp
 105e647:	4c 89 68 28          	mov    %r13,0x28(%rax)
 105e64b:	e9 fb 04 00 00       	jmp    105eb4b <my.interpreter::execute+0x105b>
 105e650:	41 83 fc 01          	cmp    $0x1,%r12d
 105e654:	0f 85 d8 04 00 00    	jne    105eb32 <my.interpreter::execute+0x1042>
 105e65a:	48 8d bc 24 b0 01 00 	lea    0x1b0(%rsp),%rdi
 105e661:	00 
 105e662:	4c 89 fe             	mov    %r15,%rsi
 105e665:	48 89 da             	mov    %rbx,%rdx
 105e668:	4c 8b 04 24          	mov    (%rsp),%r8
 105e66c:	4d 89 f1             	mov    %r14,%r9
 105e66f:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e676:	ff 74 24 28          	push   0x28(%rsp)
 105e67a:	41 55                	push   %r13
 105e67c:	41 52                	push   %r10
 105e67e:	41 53                	push   %r11
 105e680:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e687:	e8 64 f4 ff ff       	call   105daf0 <my.interpreter::execute>
 105e68c:	48 83 c4 30          	add    $0x30,%rsp
 105e690:	0f b6 84 24 b0 01 00 	movzbl 0x1b0(%rsp),%eax
 105e697:	00 
 105e698:	c5 f8 10 84 24 b8 01 	vmovups 0x1b8(%rsp),%xmm0
 105e69f:	00 00 
 105e6a1:	48 8b 8c 24 c8 01 00 	mov    0x1c8(%rsp),%rcx
 105e6a8:	00 
 105e6a9:	0f b6 94 24 d0 01 00 	movzbl 0x1d0(%rsp),%edx
 105e6b0:	00 
 105e6b1:	48 8b b4 24 d8 01 00 	mov    0x1d8(%rsp),%rsi
 105e6b8:	00 
 105e6b9:	48 83 f8 01          	cmp    $0x1,%rax
 105e6bd:	0f 84 ce 06 00 00    	je     105ed91 <my.interpreter::execute+0x12a1>
 105e6c3:	48 89 45 00          	mov    %rax,0x0(%rbp)
 105e6c7:	c5 f8 11 45 08       	vmovups %xmm0,0x8(%rbp)
 105e6cc:	48 89 4d 18          	mov    %rcx,0x18(%rbp)
 105e6d0:	48 89 55 20          	mov    %rdx,0x20(%rbp)
 105e6d4:	48 89 75 28          	mov    %rsi,0x28(%rbp)
 105e6d8:	e9 6e 04 00 00       	jmp    105eb4b <my.interpreter::execute+0x105b>
 105e6dd:	48 8b 6c 24 18       	mov    0x18(%rsp),%rbp
 105e6e2:	48 c7 45 00 00 00 00 	movq   $0x0,0x0(%rbp)
 105e6e9:	00 
 105e6ea:	48 c7 45 08 01 00 00 	movq   $0x1,0x8(%rbp)
 105e6f1:	00 
 105e6f2:	4c 89 5d 18          	mov    %r11,0x18(%rbp)
 105e6f6:	4c 89 55 20          	mov    %r10,0x20(%rbp)
 105e6fa:	e9 48 04 00 00       	jmp    105eb47 <my.interpreter::execute+0x1057>
 105e6ff:	48 01 c2             	add    %rax,%rdx
 105e702:	4c 8b 62 08          	mov    0x8(%rdx),%r12
 105e706:	49 8b 44 24 08       	mov    0x8(%r12),%rax
 105e70b:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105e710:	48 85 c0             	test   %rax,%rax
 105e713:	0f 84 f3 f4 ff ff    	je     105dc0c <my.interpreter::execute+0x11c>
 105e719:	31 ed                	xor    %ebp,%ebp
 105e71b:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105e722:	0f 1f 84 00 00 00 00 
 105e729:	00 
 105e72a:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105e731:	0f 1f 84 00 00 00 00 
 105e738:	00 
 105e739:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
 105e740:	40 0f b6 c6          	movzbl %sil,%eax
 105e744:	48 8d bc 24 88 00 00 	lea    0x88(%rsp),%rdi
 105e74b:	00 
 105e74c:	4c 89 fe             	mov    %r15,%rsi
 105e74f:	48 89 da             	mov    %rbx,%rdx
 105e752:	4c 8b 04 24          	mov    (%rsp),%r8
 105e756:	4d 89 f1             	mov    %r14,%r9
 105e759:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e760:	41 ff 74 ec 20       	push   0x20(%r12,%rbp,8)
 105e765:	41 55                	push   %r13
 105e767:	50                   	push   %rax
 105e768:	41 52                	push   %r10
 105e76a:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e771:	e8 7a f3 ff ff       	call   105daf0 <my.interpreter::execute>
 105e776:	48 83 c4 30          	add    $0x30,%rsp
 105e77a:	48 8b 84 24 90 00 00 	mov    0x90(%rsp),%rax
 105e781:	00 
 105e782:	4c 8b 94 24 a0 00 00 	mov    0xa0(%rsp),%r10
 105e789:	00 
 105e78a:	0f b6 b4 24 a8 00 00 	movzbl 0xa8(%rsp),%esi
 105e791:	00 
 105e792:	4c 8b ac 24 b0 00 00 	mov    0xb0(%rsp),%r13
 105e799:	00 
 105e79a:	80 bc 24 88 00 00 00 	cmpb   $0x1,0x88(%rsp)
 105e7a1:	01 
 105e7a2:	0f 84 04 06 00 00    	je     105edac <my.interpreter::execute+0x12bc>
 105e7a8:	3c 01                	cmp    $0x1,%al
 105e7aa:	0f 84 b0 03 00 00    	je     105eb60 <my.interpreter::execute+0x1070>
 105e7b0:	48 ff c5             	inc    %rbp
 105e7b3:	48 39 6c 24 10       	cmp    %rbp,0x10(%rsp)
 105e7b8:	48 8b 4c 24 30       	mov    0x30(%rsp),%rcx
 105e7bd:	75 81                	jne    105e740 <my.interpreter::execute+0xc50>
 105e7bf:	e9 48 f4 ff ff       	jmp    105dc0c <my.interpreter::execute+0x11c>
 105e7c4:	48 39 d0             	cmp    %rdx,%rax
 105e7c7:	0f 83 7a 08 00 00    	jae    105f047 <my.interpreter::execute+0x1557>
 105e7cd:	48 89 c7             	mov    %rax,%rdi
 105e7d0:	48 6b c7 38          	imul   $0x38,%rdi,%rax
 105e7d4:	83 7c 01 20 09       	cmpl   $0x9,0x20(%rcx,%rax,1)
 105e7d9:	0f 85 4c 0a 00 00    	jne    105f22b <my.interpreter::execute+0x173b>
 105e7df:	48 01 c8             	add    %rcx,%rax
 105e7e2:	48 83 c0 20          	add    $0x20,%rax
 105e7e6:	48 8b 40 10          	mov    0x10(%rax),%rax
 105e7ea:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e7ee:	48 39 d6             	cmp    %rdx,%rsi
 105e7f1:	0f 83 75 08 00 00    	jae    105f06c <my.interpreter::execute+0x157c>
 105e7f7:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e7fb:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105e802:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e806:	48 39 d6             	cmp    %rdx,%rsi
 105e809:	0f 83 7f 08 00 00    	jae    105f08e <my.interpreter::execute+0x159e>
 105e80f:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
 105e813:	c5 f8 11 45 00       	vmovups %xmm0,0x0(%rbp)
 105e818:	4c 89 5d 18          	mov    %r11,0x18(%rbp)
 105e81c:	41 0f b6 c2          	movzbl %r10b,%eax
 105e820:	e9 1e 03 00 00       	jmp    105eb43 <my.interpreter::execute+0x1053>
 105e825:	31 db                	xor    %ebx,%ebx
 105e827:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105e82e:	48 89 c6             	mov    %rax,%rsi
 105e831:	48 ff ce             	dec    %rsi
 105e834:	0f 80 dd 09 00 00    	jo     105f217 <my.interpreter::execute+0x1727>
 105e83a:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e83e:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e842:	48 39 d6             	cmp    %rdx,%rsi
 105e845:	0f 83 b5 07 00 00    	jae    105f000 <my.interpreter::execute+0x1510>
 105e84b:	48 89 f1             	mov    %rsi,%rcx
 105e84e:	4c 89 44 24 28       	mov    %r8,0x28(%rsp)
 105e853:	48 c1 e1 04          	shl    $0x4,%rcx
 105e857:	80 7c 08 20 03       	cmpb   $0x3,0x20(%rax,%rcx,1)
 105e85c:	0f 85 82 03 00 00    	jne    105ebe4 <my.interpreter::execute+0x10f4>
 105e862:	4c 8b 7c 08 28       	mov    0x28(%rax,%rcx,1),%r15
 105e867:	49 8b 06             	mov    (%r14),%rax
 105e86a:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e86e:	4c 89 f9             	mov    %r15,%rcx
 105e871:	49 39 d7             	cmp    %rdx,%r15
 105e874:	0f 83 a8 07 00 00    	jae    105f022 <my.interpreter::execute+0x1532>
 105e87a:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 105e87e:	83 7c 08 20 06       	cmpl   $0x6,0x20(%rax,%rcx,1)
 105e883:	0f 85 5b 03 00 00    	jne    105ebe4 <my.interpreter::execute+0x10f4>
 105e889:	48 89 7c 24 48       	mov    %rdi,0x48(%rsp)
 105e88e:	48 8d bc 24 80 00 00 	lea    0x80(%rsp),%rdi
 105e895:	00 
 105e896:	4c 89 f6             	mov    %r14,%rsi
 105e899:	48 8b 54 24 20       	mov    0x20(%rsp),%rdx
 105e89e:	e8 0d 4b 00 00       	call   10633b0 <my.heap::allocate_class>
 105e8a3:	48 8b 8c 24 80 00 00 	mov    0x80(%rsp),%rcx
 105e8aa:	00 
 105e8ab:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e8af:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105e8b6:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e8ba:	48 39 d6             	cmp    %rdx,%rsi
 105e8bd:	0f 83 53 06 00 00    	jae    105ef16 <my.interpreter::execute+0x1426>
 105e8c3:	48 89 f7             	mov    %rsi,%rdi
 105e8c6:	48 c1 e7 04          	shl    $0x4,%rdi
 105e8ca:	48 c7 44 38 20 03 00 	movq   $0x3,0x20(%rax,%rdi,1)
 105e8d1:	00 00 
 105e8d3:	48 89 4c 38 28       	mov    %rcx,0x28(%rax,%rdi,1)
 105e8d8:	49 89 46 78          	mov    %rax,0x78(%r14)
 105e8dc:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105e8e3:	48 89 f2             	mov    %rsi,%rdx
 105e8e6:	48 ff c2             	inc    %rdx
 105e8e9:	0f 80 91 08 00 00    	jo     105f180 <my.interpreter::execute+0x1690>
 105e8ef:	48 8d 0c 38          	lea    (%rax,%rdi,1),%rcx
 105e8f3:	48 83 c1 20          	add    $0x20,%rcx
 105e8f7:	49 89 96 80 00 00 00 	mov    %rdx,0x80(%r14)
 105e8fe:	0f b6 01             	movzbl (%rcx),%eax
 105e901:	83 f8 03             	cmp    $0x3,%eax
 105e904:	0f 85 c6 07 00 00    	jne    105f0d0 <my.interpreter::execute+0x15e0>
 105e90a:	48 8b 71 08          	mov    0x8(%rcx),%rsi
 105e90e:	49 83 ff ff          	cmp    $0xffffffffffffffff,%r15
 105e912:	48 89 6c 24 18       	mov    %rbp,0x18(%rsp)
 105e917:	4c 89 6c 24 58       	mov    %r13,0x58(%rsp)
 105e91c:	4c 89 7c 24 50       	mov    %r15,0x50(%rsp)
 105e921:	48 89 34 24          	mov    %rsi,(%rsp)
 105e925:	74 76                	je     105e99d <my.interpreter::execute+0xead>
 105e927:	4c 89 f7             	mov    %r14,%rdi
 105e92a:	4c 89 fa             	mov    %r15,%rdx
 105e92d:	e8 fe be 00 00       	call   106a830 <my.heap::inherit_class_methods>
 105e932:	49 8b 96 a8 00 00 00 	mov    0xa8(%r14),%rdx
 105e939:	48 8d 7c 24 78       	lea    0x78(%rsp),%rdi
 105e93e:	b9 01 00 00 00       	mov    $0x1,%ecx
 105e943:	4c 89 f6             	mov    %r14,%rsi
 105e946:	e8 e5 da 00 00       	call   106c430 <my.interpreter::new_env>
 105e94b:	4c 8b 64 24 78       	mov    0x78(%rsp),%r12
 105e950:	4c 89 f7             	mov    %r14,%rdi
 105e953:	4c 89 e6             	mov    %r12,%rsi
 105e956:	31 d2                	xor    %edx,%edx
 105e958:	b9 03 00 00 00       	mov    $0x3,%ecx
 105e95d:	4d 89 f8             	mov    %r15,%r8
 105e960:	e8 5b dc 00 00       	call   106c5c0 <my.heap::set_env_slot>
 105e965:	4d 8b be a8 00 00 00 	mov    0xa8(%r14),%r15
 105e96c:	49 8b 86 b0 00 00 00 	mov    0xb0(%r14),%rax
 105e973:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105e977:	48 3b 48 10          	cmp    0x10(%rax),%rcx
 105e97b:	0f 83 d9 05 00 00    	jae    105ef5a <my.interpreter::execute+0x146a>
 105e981:	4c 89 7c c8 20       	mov    %r15,0x20(%rax,%rcx,8)
 105e986:	48 ff c1             	inc    %rcx
 105e989:	48 89 48 08          	mov    %rcx,0x8(%rax)
 105e98d:	49 89 86 b0 00 00 00 	mov    %rax,0xb0(%r14)
 105e994:	4d 89 a6 a8 00 00 00 	mov    %r12,0xa8(%r14)
 105e99b:	eb 07                	jmp    105e9a4 <my.interpreter::execute+0xeb4>
 105e99d:	4d 8b a6 a8 00 00 00 	mov    0xa8(%r14),%r12
 105e9a4:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105e9a9:	4c 8b 68 08          	mov    0x8(%rax),%r13
 105e9ad:	4d 85 ed             	test   %r13,%r13
 105e9b0:	48 8b 5c 24 30       	mov    0x30(%rsp),%rbx
 105e9b5:	0f 84 d2 00 00 00    	je     105ea8d <my.interpreter::execute+0xf9d>
 105e9bb:	31 ed                	xor    %ebp,%ebp
 105e9bd:	0f 1f 00             	nopl   (%rax)
 105e9c0:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105e9c5:	48 8b 74 e8 20       	mov    0x20(%rax,%rbp,8),%rsi
 105e9ca:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 105e9ce:	48 89 f0             	mov    %rsi,%rax
 105e9d1:	48 39 d6             	cmp    %rdx,%rsi
 105e9d4:	0f 83 91 00 00 00    	jae    105ea6b <my.interpreter::execute+0xf7b>
 105e9da:	48 8d 04 80          	lea    (%rax,%rax,4),%rax
 105e9de:	48 c1 e0 04          	shl    $0x4,%rax
 105e9e2:	4c 8b 7c 03 48       	mov    0x48(%rbx,%rax,1),%r15
 105e9e7:	4d 3b 7e 40          	cmp    0x40(%r14),%r15
 105e9eb:	48 c7 84 24 88 00 00 	movq   $0xa,0x88(%rsp)
 105e9f2:	00 0a 00 00 00 
 105e9f7:	48 89 b4 24 90 00 00 	mov    %rsi,0x90(%rsp)
 105e9fe:	00 
 105e9ff:	4c 89 bc 24 98 00 00 	mov    %r15,0x98(%rsp)
 105ea06:	00 
 105ea07:	4c 89 a4 24 a0 00 00 	mov    %r12,0xa0(%rsp)
 105ea0e:	00 
 105ea0f:	0f 94 84 24 a8 00 00 	sete   0xa8(%rsp)
 105ea16:	00 
 105ea17:	48 8d 7c 24 70       	lea    0x70(%rsp),%rdi
 105ea1c:	4c 89 f6             	mov    %r14,%rsi
 105ea1f:	48 8d 94 24 88 00 00 	lea    0x88(%rsp),%rdx
 105ea26:	00 
 105ea27:	e8 64 b7 ff ff       	call   105a190 <my.heap::allocate>
 105ea2c:	4c 8b 64 24 70       	mov    0x70(%rsp),%r12
 105ea31:	4c 89 f7             	mov    %r14,%rdi
 105ea34:	4c 89 fe             	mov    %r15,%rsi
 105ea37:	e8 24 b1 00 00       	call   1069b60 <my.heap::string_hash>
 105ea3c:	4c 89 f7             	mov    %r14,%rdi
 105ea3f:	48 8b 34 24          	mov    (%rsp),%rsi
 105ea43:	4c 89 fa             	mov    %r15,%rdx
 105ea46:	89 c1                	mov    %eax,%ecx
 105ea48:	41 b8 03 00 00 00    	mov    $0x3,%r8d
 105ea4e:	4d 89 e1             	mov    %r12,%r9
 105ea51:	e8 ba bf 00 00       	call   106aa10 <my.heap::set_class_method>
 105ea56:	4d 8b a6 a8 00 00 00 	mov    0xa8(%r14),%r12
 105ea5d:	48 ff c5             	inc    %rbp
 105ea60:	49 39 ed             	cmp    %rbp,%r13
 105ea63:	0f 85 57 ff ff ff    	jne    105e9c0 <my.interpreter::execute+0xed0>
 105ea69:	eb 22                	jmp    105ea8d <my.interpreter::execute+0xf9d>
 105ea6b:	48 89 f0             	mov    %rsi,%rax
 105ea6e:	48 c1 f8 3f          	sar    $0x3f,%rax
 105ea72:	48 21 d0             	and    %rdx,%rax
 105ea75:	48 01 f0             	add    %rsi,%rax
 105ea78:	48 39 d0             	cmp    %rdx,%rax
 105ea7b:	0f 82 59 ff ff ff    	jb     105e9da <my.interpreter::execute+0xeea>
 105ea81:	48 8d 3d c8 32 02 00 	lea    0x232c8(%rip),%rdi        # 1081d50 <core_durable_error.verbs+0x2e50>
 105ea88:	e8 33 5a fc ff       	call   10244c0 <myl_core_trap>
 105ea8d:	48 8b 5c 24 50       	mov    0x50(%rsp),%rbx
 105ea92:	48 83 fb ff          	cmp    $0xffffffffffffffff,%rbx
 105ea96:	48 8b 6c 24 18       	mov    0x18(%rsp),%rbp
 105ea9b:	4c 8b 6c 24 58       	mov    0x58(%rsp),%r13
 105eaa0:	74 27                	je     105eac9 <my.interpreter::execute+0xfd9>
 105eaa2:	49 8b 86 b0 00 00 00 	mov    0xb0(%r14),%rax
 105eaa9:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105eaad:	48 85 c9             	test   %rcx,%rcx
 105eab0:	0f 84 1b 07 00 00    	je     105f1d1 <my.interpreter::execute+0x16e1>
 105eab6:	48 8b 54 c8 18       	mov    0x18(%rax,%rcx,8),%rdx
 105eabb:	48 ff c9             	dec    %rcx
 105eabe:	48 89 48 08          	mov    %rcx,0x8(%rax)
 105eac2:	49 89 96 a8 00 00 00 	mov    %rdx,0xa8(%r14)
 105eac9:	4c 89 f7             	mov    %r14,%rdi
 105eacc:	48 8b 74 24 20       	mov    0x20(%rsp),%rsi
 105ead1:	48 8b 54 24 60       	mov    0x60(%rsp),%rdx
 105ead6:	e8 15 8f 00 00       	call   10679f0 <my.interpreter::define>
 105eadb:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105eae2:	48 89 c6             	mov    %rax,%rsi
 105eae5:	48 ff ce             	dec    %rsi
 105eae8:	0f 80 bb 06 00 00    	jo     105f1a9 <my.interpreter::execute+0x16b9>
 105eaee:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105eaf5:	49 8b 46 78          	mov    0x78(%r14),%rax
 105eaf9:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105eafd:	48 39 d6             	cmp    %rdx,%rsi
 105eb00:	4c 8b 5c 24 48       	mov    0x48(%rsp),%r11
 105eb05:	48 8b 7c 24 28       	mov    0x28(%rsp),%rdi
 105eb0a:	0f 83 28 04 00 00    	jae    105ef38 <my.interpreter::execute+0x1448>
 105eb10:	48 83 fb ff          	cmp    $0xffffffffffffffff,%rbx
 105eb14:	74 1c                	je     105eb32 <my.interpreter::execute+0x1042>
 105eb16:	48 89 f0             	mov    %rsi,%rax
 105eb19:	48 ff c8             	dec    %rax
 105eb1c:	0f 80 bf 06 00 00    	jo     105f1e1 <my.interpreter::execute+0x16f1>
 105eb22:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 105eb29:	48 39 d0             	cmp    %rdx,%rax
 105eb2c:	0f 83 3e 04 00 00    	jae    105ef70 <my.interpreter::execute+0x1480>
 105eb32:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
 105eb36:	c5 f8 11 45 00       	vmovups %xmm0,0x0(%rbp)
 105eb3b:	4c 89 5d 18          	mov    %r11,0x18(%rbp)
 105eb3f:	40 0f b6 c7          	movzbl %dil,%eax
 105eb43:	48 89 45 20          	mov    %rax,0x20(%rbp)
 105eb47:	4c 89 6d 28          	mov    %r13,0x28(%rbp)
 105eb4b:	48 89 e8             	mov    %rbp,%rax
 105eb4e:	48 81 c4 d8 02 00 00 	add    $0x2d8,%rsp
 105eb55:	5b                   	pop    %rbx
 105eb56:	41 5c                	pop    %r12
 105eb58:	41 5d                	pop    %r13
 105eb5a:	41 5e                	pop    %r14
 105eb5c:	41 5f                	pop    %r15
 105eb5e:	5d                   	pop    %rbp
 105eb5f:	c3                   	ret
 105eb60:	48 89 f3             	mov    %rsi,%rbx
 105eb63:	b8 01 00 00 00       	mov    $0x1,%eax
 105eb68:	31 f6                	xor    %esi,%esi
 105eb6a:	31 d2                	xor    %edx,%edx
 105eb6c:	e9 a8 f0 ff ff       	jmp    105dc19 <my.interpreter::execute+0x129>
 105eb71:	c5 f8 10 84 24 18 02 	vmovups 0x218(%rsp),%xmm0
 105eb78:	00 00 
 105eb7a:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105eb7f:	48 8d 3d ba 14 02 00 	lea    0x214ba(%rip),%rdi        # 1080040 <core_durable_error.verbs+0x1140>
 105eb86:	4c 89 d8             	mov    %r11,%rax
 105eb89:	e8 32 7d ff ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 105eb8e:	48 c7 45 00 01 00 00 	movq   $0x1,0x0(%rbp)
 105eb95:	00 
 105eb96:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 105eb9b:	c5 f8 11 45 08       	vmovups %xmm0,0x8(%rbp)
 105eba0:	48 89 45 18          	mov    %rax,0x18(%rbp)
 105eba4:	e9 4d fb ff ff       	jmp    105e6f6 <my.interpreter::execute+0xc06>
 105eba9:	41 0f b6 c7          	movzbl %r15b,%eax
 105ebad:	c5 f8 10 84 24 88 01 	vmovups 0x188(%rsp),%xmm0
 105ebb4:	00 00 
 105ebb6:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105ebbb:	48 8d 3d 0e 15 02 00 	lea    0x2150e(%rip),%rdi        # 10800d0 <core_durable_error.verbs+0x11d0>
 105ebc2:	e9 01 01 00 00       	jmp    105ecc8 <my.interpreter::execute+0x11d8>
 105ebc7:	48 8d 3d 22 31 02 00 	lea    0x23122(%rip),%rdi        # 1081cf0 <core_durable_error.verbs+0x2df0>
 105ebce:	e8 ed 7c ff ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 105ebd3:	48 8d 3d 46 13 02 00 	lea    0x21346(%rip),%rdi        # 107ff20 <core_durable_error.verbs+0x1020>
 105ebda:	e8 e1 7c ff ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 105ebdf:	e9 6a f0 ff ff       	jmp    105dc4e <my.interpreter::execute+0x15e>
 105ebe4:	49 89 fe             	mov    %rdi,%r14
 105ebe7:	48 8d 3d d2 36 fb ff 	lea    -0x4c92e(%rip),%rdi        # 10122c0 <core_number_pairs+0xb040>
 105ebee:	e8 cd 53 fc ff       	call   1023fc0 <myl_core_owned_octets_copy>
 105ebf3:	48 8d 3d 86 5e 02 00 	lea    0x25e86(%rip),%rdi        # 1084a80 <core_durable_error.verbs+0x5b80>
 105ebfa:	e8 81 7c ff ff       	call   1056880 <myl_core_err_trace_origin_preserve_most>
 105ebff:	4c 8b 44 24 28       	mov    0x28(%rsp),%r8
 105ec04:	e9 fe 00 00 00       	jmp    105ed07 <my.interpreter::execute+0x1217>
 105ec09:	40 0f b6 c7          	movzbl %dil,%eax
 105ec0d:	c5 f8 10 84 24 48 02 	vmovups 0x248(%rsp),%xmm0
 105ec14:	00 00 
 105ec16:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105ec1b:	48 8d 3d be 13 02 00 	lea    0x213be(%rip),%rdi        # 107ffe0 <core_durable_error.verbs+0x10e0>
 105ec22:	4c 89 d9             	mov    %r11,%rcx
 105ec25:	e8 96 7c ff ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 105ec2a:	48 c7 45 00 01 00 00 	movq   $0x1,0x0(%rbp)
 105ec31:	00 
 105ec32:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 105ec37:	c5 f8 11 45 08       	vmovups %xmm0,0x8(%rbp)
 105ec3c:	48 89 4d 18          	mov    %rcx,0x18(%rbp)
 105ec40:	e9 fe fe ff ff       	jmp    105eb43 <my.interpreter::execute+0x1053>
 105ec45:	c5 f8 10 84 24 28 01 	vmovups 0x128(%rsp),%xmm0
 105ec4c:	00 00 
 105ec4e:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105ec53:	48 8d 3d 06 15 02 00 	lea    0x21506(%rip),%rdi        # 1080160 <core_durable_error.verbs+0x1260>
 105ec5a:	e8 61 7c ff ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 105ec5f:	48 8b 44 24 18       	mov    0x18(%rsp),%rax
 105ec64:	48 c7 00 01 00 00 00 	movq   $0x1,(%rax)
 105ec6b:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 105ec70:	c5 f8 11 40 08       	vmovups %xmm0,0x8(%rax)
 105ec75:	e9 c2 f9 ff ff       	jmp    105e63c <my.interpreter::execute+0xb4c>
 105ec7a:	48 8b 8c 24 00 01 00 	mov    0x100(%rsp),%rcx
 105ec81:	00 
 105ec82:	48 8d 3d 07 15 02 00 	lea    0x21507(%rip),%rdi        # 1080190 <core_durable_error.verbs+0x1290>
 105ec89:	4c 89 da             	mov    %r11,%rdx
 105ec8c:	e8 2f 7c ff ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 105ec91:	48 8b 6c 24 18       	mov    0x18(%rsp),%rbp
 105ec96:	48 c7 45 00 01 00 00 	movq   $0x1,0x0(%rbp)
 105ec9d:	00 
 105ec9e:	48 89 45 08          	mov    %rax,0x8(%rbp)
 105eca2:	48 89 4d 10          	mov    %rcx,0x10(%rbp)
 105eca6:	48 89 55 18          	mov    %rdx,0x18(%rbp)
 105ecaa:	e9 47 fa ff ff       	jmp    105e6f6 <my.interpreter::execute+0xc06>
 105ecaf:	41 0f b6 c7          	movzbl %r15b,%eax
 105ecb3:	c5 f8 10 84 24 58 01 	vmovups 0x158(%rsp),%xmm0
 105ecba:	00 00 
 105ecbc:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105ecc1:	48 8d 3d 68 14 02 00 	lea    0x21468(%rip),%rdi        # 1080130 <core_durable_error.verbs+0x1230>
 105ecc8:	e8 f3 7b ff ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 105eccd:	48 c7 45 00 01 00 00 	movq   $0x1,0x0(%rbp)
 105ecd4:	00 
 105ecd5:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 105ecda:	c5 f8 11 45 08       	vmovups %xmm0,0x8(%rbp)
 105ecdf:	48 89 5d 18          	mov    %rbx,0x18(%rbp)
 105ece3:	e9 5b fe ff ff       	jmp    105eb43 <my.interpreter::execute+0x1053>
 105ece8:	49 89 fe             	mov    %rdi,%r14
 105eceb:	48 8b 84 24 c8 00 00 	mov    0xc8(%rsp),%rax
 105ecf2:	00 
 105ecf3:	48 8b 9c 24 d0 00 00 	mov    0xd0(%rsp),%rbx
 105ecfa:	00 
 105ecfb:	48 8d 3d 1e 5d 02 00 	lea    0x25d1e(%rip),%rdi        # 1084a20 <core_durable_error.verbs+0x5b20>
 105ed02:	e8 b9 7b ff ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 105ed07:	48 8d 3d 12 30 02 00 	lea    0x23012(%rip),%rdi        # 1081d20 <core_durable_error.verbs+0x2e20>
 105ed0e:	e8 ad 7b ff ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 105ed13:	48 8d 3d 36 12 02 00 	lea    0x21236(%rip),%rdi        # 107ff50 <core_durable_error.verbs+0x1050>
 105ed1a:	e8 a1 7b ff ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 105ed1f:	48 c7 45 00 01 00 00 	movq   $0x1,0x0(%rbp)
 105ed26:	00 
 105ed27:	48 89 45 08          	mov    %rax,0x8(%rbp)
 105ed2b:	48 89 5d 10          	mov    %rbx,0x10(%rbp)
 105ed2f:	4c 89 75 18          	mov    %r14,0x18(%rbp)
 105ed33:	4c 89 45 20          	mov    %r8,0x20(%rbp)
 105ed37:	e9 0b fe ff ff       	jmp    105eb47 <my.interpreter::execute+0x1057>
 105ed3c:	c5 f8 10 84 24 b0 02 	vmovups 0x2b0(%rsp),%xmm0
 105ed43:	00 00 
 105ed45:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105ed4a:	c5 f8 10 84 24 c8 02 	vmovups 0x2c8(%rsp),%xmm0
 105ed51:	00 00 
 105ed53:	c5 f8 54 05 85 56 fa 	vandps -0x5a97b(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105ed5a:	ff 
 105ed5b:	c5 f8 29 44 24 30    	vmovaps %xmm0,0x30(%rsp)
 105ed61:	48 8d 3d 98 13 02 00 	lea    0x21398(%rip),%rdi        # 1080100 <core_durable_error.verbs+0x1200>
 105ed68:	4c 89 d8             	mov    %r11,%rax
 105ed6b:	e8 50 7b ff ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 105ed70:	48 c7 45 00 01 00 00 	movq   $0x1,0x0(%rbp)
 105ed77:	00 
 105ed78:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 105ed7d:	c5 f8 11 45 08       	vmovups %xmm0,0x8(%rbp)
 105ed82:	48 89 45 18          	mov    %rax,0x18(%rbp)
 105ed86:	c5 f8 28 44 24 30    	vmovaps 0x30(%rsp),%xmm0
 105ed8c:	e9 94 f8 ff ff       	jmp    105e625 <my.interpreter::execute+0xb35>
 105ed91:	48 8d 3d 08 13 02 00 	lea    0x21308(%rip),%rdi        # 10800a0 <core_durable_error.verbs+0x11a0>
 105ed98:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105ed9d:	e8 1e 7b ff ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 105eda2:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 105eda7:	e9 17 f9 ff ff       	jmp    105e6c3 <my.interpreter::execute+0xbd3>
 105edac:	48 89 f3             	mov    %rsi,%rbx
 105edaf:	48 8b 8c 24 98 00 00 	mov    0x98(%rsp),%rcx
 105edb6:	00 
 105edb7:	48 8d 3d 02 5c 02 00 	lea    0x25c02(%rip),%rdi        # 10849c0 <core_durable_error.verbs+0x5ac0>
 105edbe:	e8 fd 7a ff ff       	call   10568c0 <myl_core_err_trace_append_preserve_most>
 105edc3:	ba 01 00 00 00       	mov    $0x1,%edx
 105edc8:	40 b6 01             	mov    $0x1,%sil
 105edcb:	e9 49 ee ff ff       	jmp    105dc19 <my.interpreter::execute+0x129>
 105edd0:	4c 89 e0             	mov    %r12,%rax
 105edd3:	48 c1 f8 3f          	sar    $0x3f,%rax
 105edd7:	48 21 d0             	and    %rdx,%rax
 105edda:	4c 01 e0             	add    %r12,%rax
 105eddd:	48 39 d0             	cmp    %rdx,%rax
 105ede0:	0f 82 43 ed ff ff    	jb     105db29 <my.interpreter::execute+0x39>
 105ede6:	48 8d 3d 03 11 02 00 	lea    0x21103(%rip),%rdi        # 107fef0 <core_durable_error.verbs+0xff0>
 105eded:	4c 89 e6             	mov    %r12,%rsi
 105edf0:	e8 cb 56 fc ff       	call   10244c0 <myl_core_trap>
 105edf5:	48 89 c1             	mov    %rax,%rcx
 105edf8:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105edfc:	48 21 d1             	and    %rdx,%rcx
 105edff:	48 01 c1             	add    %rax,%rcx
 105ee02:	48 39 d1             	cmp    %rdx,%rcx
 105ee05:	0f 82 ba ef ff ff    	jb     105ddc5 <my.interpreter::execute+0x2d5>
 105ee0b:	48 8d 3d 6e 11 02 00 	lea    0x2116e(%rip),%rdi        # 107ff80 <core_durable_error.verbs+0x1080>
 105ee12:	48 89 c6             	mov    %rax,%rsi
 105ee15:	e8 a6 56 fc ff       	call   10244c0 <myl_core_trap>
 105ee1a:	48 89 f0             	mov    %rsi,%rax
 105ee1d:	48 c1 f8 3f          	sar    $0x3f,%rax
 105ee21:	48 21 d0             	and    %rdx,%rax
 105ee24:	48 01 f0             	add    %rsi,%rax
 105ee27:	48 39 d0             	cmp    %rdx,%rax
 105ee2a:	0f 82 70 f0 ff ff    	jb     105dea0 <my.interpreter::execute+0x3b0>
 105ee30:	48 8d 3d d9 11 02 00 	lea    0x211d9(%rip),%rdi        # 1080010 <core_durable_error.verbs+0x1110>
 105ee37:	e8 84 56 fc ff       	call   10244c0 <myl_core_trap>
 105ee3c:	48 89 74 24 20       	mov    %rsi,0x20(%rsp)
 105ee41:	be 08 00 00 00       	mov    $0x8,%esi
 105ee46:	48 89 c7             	mov    %rax,%rdi
 105ee49:	48 89 54 24 10       	mov    %rdx,0x10(%rsp)
 105ee4e:	e8 ed 3b fc ff       	call   1022a40 <myl_core_list_grow>
 105ee53:	48 8b 74 24 20       	mov    0x20(%rsp),%rsi
 105ee58:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 105ee5d:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105ee61:	e9 4d ed ff ff       	jmp    105dbb3 <my.interpreter::execute+0xc3>
 105ee66:	4c 89 e0             	mov    %r12,%rax
 105ee69:	48 c1 f8 3f          	sar    $0x3f,%rax
 105ee6d:	48 21 d0             	and    %rdx,%rax
 105ee70:	4c 01 e0             	add    %r12,%rax
 105ee73:	48 39 d0             	cmp    %rdx,%rax
 105ee76:	0f 82 76 ed ff ff    	jb     105dbf2 <my.interpreter::execute+0x102>
 105ee7c:	48 8d 3d 0d 5b 02 00 	lea    0x25b0d(%rip),%rdi        # 1084990 <core_durable_error.verbs+0x5a90>
 105ee83:	4c 89 e6             	mov    %r12,%rsi
 105ee86:	e8 35 56 fc ff       	call   10244c0 <myl_core_trap>
 105ee8b:	48 89 f7             	mov    %rsi,%rdi
 105ee8e:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105ee92:	48 21 d7             	and    %rdx,%rdi
 105ee95:	48 01 f7             	add    %rsi,%rdi
 105ee98:	48 39 d7             	cmp    %rdx,%rdi
 105ee9b:	0f 82 79 f0 ff ff    	jb     105df1a <my.interpreter::execute+0x42a>
 105eea1:	48 8d 3d 78 13 02 00 	lea    0x21378(%rip),%rdi        # 1080220 <core_durable_error.verbs+0x1320>
 105eea8:	e8 13 56 fc ff       	call   10244c0 <myl_core_trap>
 105eead:	48 89 c6             	mov    %rax,%rsi
 105eeb0:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105eeb4:	48 21 d6             	and    %rdx,%rsi
 105eeb7:	48 01 c6             	add    %rax,%rsi
 105eeba:	48 39 d6             	cmp    %rdx,%rsi
 105eebd:	0f 82 3c f7 ff ff    	jb     105e5ff <my.interpreter::execute+0xb0f>
 105eec3:	48 8d 3d a6 14 02 00 	lea    0x214a6(%rip),%rdi        # 1080370 <core_durable_error.verbs+0x1470>
 105eeca:	48 89 c6             	mov    %rax,%rsi
 105eecd:	e8 ee 55 fc ff       	call   10244c0 <myl_core_trap>
 105eed2:	49 89 f0             	mov    %rsi,%r8
 105eed5:	49 c1 f8 3f          	sar    $0x3f,%r8
 105eed9:	49 21 d0             	and    %rdx,%r8
 105eedc:	49 01 f0             	add    %rsi,%r8
 105eedf:	49 39 d0             	cmp    %rdx,%r8
 105eee2:	0f 82 2c ee ff ff    	jb     105dd14 <my.interpreter::execute+0x224>
 105eee8:	48 8d 3d c1 13 02 00 	lea    0x213c1(%rip),%rdi        # 10802b0 <core_durable_error.verbs+0x13b0>
 105eeef:	e8 cc 55 fc ff       	call   10244c0 <myl_core_trap>
 105eef4:	48 89 f7             	mov    %rsi,%rdi
 105eef7:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105eefb:	48 21 d7             	and    %rdx,%rdi
 105eefe:	48 01 f7             	add    %rsi,%rdi
 105ef01:	48 39 d7             	cmp    %rdx,%rdi
 105ef04:	0f 82 d2 f2 ff ff    	jb     105e1dc <my.interpreter::execute+0x6ec>
 105ef0a:	48 8d 3d ff 13 02 00 	lea    0x213ff(%rip),%rdi        # 1080310 <core_durable_error.verbs+0x1410>
 105ef11:	e8 aa 55 fc ff       	call   10244c0 <myl_core_trap>
 105ef16:	48 89 f7             	mov    %rsi,%rdi
 105ef19:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105ef1d:	48 21 d7             	and    %rdx,%rdi
 105ef20:	48 01 f7             	add    %rsi,%rdi
 105ef23:	48 39 d7             	cmp    %rdx,%rdi
 105ef26:	0f 82 9a f9 ff ff    	jb     105e8c6 <my.interpreter::execute+0xdd6>
 105ef2c:	48 8d 3d 4d 2e 02 00 	lea    0x22e4d(%rip),%rdi        # 1081d80 <core_durable_error.verbs+0x2e80>
 105ef33:	e8 88 55 fc ff       	call   10244c0 <myl_core_trap>
 105ef38:	48 89 f0             	mov    %rsi,%rax
 105ef3b:	48 c1 f8 3f          	sar    $0x3f,%rax
 105ef3f:	48 21 d0             	and    %rdx,%rax
 105ef42:	48 01 f0             	add    %rsi,%rax
 105ef45:	48 39 d0             	cmp    %rdx,%rax
 105ef48:	0f 82 c2 fb ff ff    	jb     105eb10 <my.interpreter::execute+0x1020>
 105ef4e:	48 8d 3d bb 2e 02 00 	lea    0x22ebb(%rip),%rdi        # 1081e10 <core_durable_error.verbs+0x2f10>
 105ef55:	e8 66 55 fc ff       	call   10244c0 <myl_core_trap>
 105ef5a:	be 08 00 00 00       	mov    $0x8,%esi
 105ef5f:	48 89 c7             	mov    %rax,%rdi
 105ef62:	e8 d9 3a fc ff       	call   1022a40 <myl_core_list_grow>
 105ef67:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105ef6b:	e9 11 fa ff ff       	jmp    105e981 <my.interpreter::execute+0xe91>
 105ef70:	48 89 c1             	mov    %rax,%rcx
 105ef73:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105ef77:	48 21 d1             	and    %rdx,%rcx
 105ef7a:	48 01 c1             	add    %rax,%rcx
 105ef7d:	48 39 d1             	cmp    %rdx,%rcx
 105ef80:	0f 82 ac fb ff ff    	jb     105eb32 <my.interpreter::execute+0x1042>
 105ef86:	48 8d 3d e3 2e 02 00 	lea    0x22ee3(%rip),%rdi        # 1081e70 <core_durable_error.verbs+0x2f70>
 105ef8d:	48 89 c6             	mov    %rax,%rsi
 105ef90:	e8 2b 55 fc ff       	call   10244c0 <myl_core_trap>
 105ef95:	48 89 f1             	mov    %rsi,%rcx
 105ef98:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105ef9c:	48 21 d1             	and    %rdx,%rcx
 105ef9f:	48 01 f1             	add    %rsi,%rcx
 105efa2:	48 39 d1             	cmp    %rdx,%rcx
 105efa5:	0f 82 46 f5 ff ff    	jb     105e4f1 <my.interpreter::execute+0xa01>
 105efab:	48 8d 3d ae 14 02 00 	lea    0x214ae(%rip),%rdi        # 1080460 <core_durable_error.verbs+0x1560>
 105efb2:	e8 09 55 fc ff       	call   10244c0 <myl_core_trap>
 105efb7:	48 89 f1             	mov    %rsi,%rcx
 105efba:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105efbe:	48 21 d1             	and    %rdx,%rcx
 105efc1:	48 01 f1             	add    %rsi,%rcx
 105efc4:	48 39 d1             	cmp    %rdx,%rcx
 105efc7:	0f 82 e0 f5 ff ff    	jb     105e5ad <my.interpreter::execute+0xabd>
 105efcd:	48 8d 3d cc 13 02 00 	lea    0x213cc(%rip),%rdi        # 10803a0 <core_durable_error.verbs+0x14a0>
 105efd4:	e8 e7 54 fc ff       	call   10244c0 <myl_core_trap>
 105efd9:	48 89 d8             	mov    %rbx,%rax
 105efdc:	48 c1 f8 3f          	sar    $0x3f,%rax
 105efe0:	48 21 d0             	and    %rdx,%rax
 105efe3:	48 01 d8             	add    %rbx,%rax
 105efe6:	48 39 d0             	cmp    %rdx,%rax
 105efe9:	0f 82 47 f1 ff ff    	jb     105e136 <my.interpreter::execute+0x646>
 105efef:	48 8d 3d 5a 5a 02 00 	lea    0x25a5a(%rip),%rdi        # 1084a50 <core_durable_error.verbs+0x5b50>
 105eff6:	48 8b 74 24 28       	mov    0x28(%rsp),%rsi
 105effb:	e8 c0 54 fc ff       	call   10244c0 <myl_core_trap>
 105f000:	48 89 f1             	mov    %rsi,%rcx
 105f003:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105f007:	48 21 d1             	and    %rdx,%rcx
 105f00a:	48 01 f1             	add    %rsi,%rcx
 105f00d:	48 39 d1             	cmp    %rdx,%rcx
 105f010:	0f 82 38 f8 ff ff    	jb     105e84e <my.interpreter::execute+0xd5e>
 105f016:	48 8d 3d c3 5a 02 00 	lea    0x25ac3(%rip),%rdi        # 1084ae0 <core_durable_error.verbs+0x5be0>
 105f01d:	e8 9e 54 fc ff       	call   10244c0 <myl_core_trap>
 105f022:	4c 89 f9             	mov    %r15,%rcx
 105f025:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105f029:	48 21 d1             	and    %rdx,%rcx
 105f02c:	4c 01 f9             	add    %r15,%rcx
 105f02f:	48 39 d1             	cmp    %rdx,%rcx
 105f032:	0f 82 42 f8 ff ff    	jb     105e87a <my.interpreter::execute+0xd8a>
 105f038:	48 8d 3d b1 7a 02 00 	lea    0x27ab1(%rip),%rdi        # 1086af0 <core_durable_error.verbs+0x7bf0>
 105f03f:	4c 89 fe             	mov    %r15,%rsi
 105f042:	e8 79 54 fc ff       	call   10244c0 <myl_core_trap>
 105f047:	48 89 c7             	mov    %rax,%rdi
 105f04a:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105f04e:	48 21 d7             	and    %rdx,%rdi
 105f051:	48 01 c7             	add    %rax,%rdi
 105f054:	48 39 d7             	cmp    %rdx,%rdi
 105f057:	0f 82 73 f7 ff ff    	jb     105e7d0 <my.interpreter::execute+0xce0>
 105f05d:	48 8d 3d 3c 2e 02 00 	lea    0x22e3c(%rip),%rdi        # 1081ea0 <core_durable_error.verbs+0x2fa0>
 105f064:	48 89 c6             	mov    %rax,%rsi
 105f067:	e8 54 54 fc ff       	call   10244c0 <myl_core_trap>
 105f06c:	48 89 f0             	mov    %rsi,%rax
 105f06f:	48 c1 f8 3f          	sar    $0x3f,%rax
 105f073:	48 21 d0             	and    %rdx,%rax
 105f076:	48 01 f0             	add    %rsi,%rax
 105f079:	48 39 d0             	cmp    %rdx,%rax
 105f07c:	0f 82 75 f7 ff ff    	jb     105e7f7 <my.interpreter::execute+0xd07>
 105f082:	48 8d 3d 77 2e 02 00 	lea    0x22e77(%rip),%rdi        # 1081f00 <core_durable_error.verbs+0x3000>
 105f089:	e8 32 54 fc ff       	call   10244c0 <myl_core_trap>
 105f08e:	48 89 f0             	mov    %rsi,%rax
 105f091:	48 c1 f8 3f          	sar    $0x3f,%rax
 105f095:	48 21 d0             	and    %rdx,%rax
 105f098:	48 01 f0             	add    %rsi,%rax
 105f09b:	48 39 d0             	cmp    %rdx,%rax
 105f09e:	0f 82 6b f7 ff ff    	jb     105e80f <my.interpreter::execute+0xd1f>
 105f0a4:	48 8d 3d 05 0f 02 00 	lea    0x20f05(%rip),%rdi        # 107ffb0 <core_durable_error.verbs+0x10b0>
 105f0ab:	e8 10 54 fc ff       	call   10244c0 <myl_core_trap>
 105f0b0:	48 8d 3d 09 14 02 00 	lea    0x21409(%rip),%rdi        # 10804c0 <core_durable_error.verbs+0x15c0>
 105f0b7:	ba 01 00 00 00       	mov    $0x1,%edx
 105f0bc:	48 89 c6             	mov    %rax,%rsi
 105f0bf:	e8 fc 53 fc ff       	call   10244c0 <myl_core_trap>
 105f0c4:	48 8d 3d 35 5b 02 00 	lea    0x25b35(%rip),%rdi        # 1084c00 <core_durable_error.verbs+0x5d00>
 105f0cb:	e8 70 a7 fc ff       	call   1029840 <myl_core_assert_fail>
 105f0d0:	83 f8 01             	cmp    $0x1,%eax
 105f0d3:	0f 84 b8 00 00 00    	je     105f191 <my.interpreter::execute+0x16a1>
 105f0d9:	85 c0                	test   %eax,%eax
 105f0db:	0f 85 bc 00 00 00    	jne    105f19d <my.interpreter::execute+0x16ad>
 105f0e1:	48 8d 3d 28 5a 02 00 	lea    0x25a28(%rip),%rdi        # 1084b10 <core_durable_error.verbs+0x5c10>
 105f0e8:	e8 53 a7 fc ff       	call   1029840 <myl_core_assert_fail>
 105f0ed:	48 8d 3d fc 58 02 00 	lea    0x258fc(%rip),%rdi        # 10849f0 <core_durable_error.verbs+0x5af0>
 105f0f4:	31 f6                	xor    %esi,%esi
 105f0f6:	31 d2                	xor    %edx,%edx
 105f0f8:	e8 c3 53 fc ff       	call   10244c0 <myl_core_trap>
 105f0fd:	48 8d 3d 4c 11 02 00 	lea    0x2114c(%rip),%rdi        # 1080250 <core_durable_error.verbs+0x1350>
 105f104:	ba 01 00 00 00       	mov    $0x1,%edx
 105f109:	e8 b2 53 fc ff       	call   10244c0 <myl_core_trap>
 105f10e:	48 8d 3d 0b 14 02 00 	lea    0x2140b(%rip),%rdi        # 1080520 <core_durable_error.verbs+0x1620>
 105f115:	ba 01 00 00 00       	mov    $0x1,%edx
 105f11a:	48 89 c6             	mov    %rax,%rsi
 105f11d:	e8 9e 53 fc ff       	call   10244c0 <myl_core_trap>
 105f122:	48 8d 3d d7 12 02 00 	lea    0x212d7(%rip),%rdi        # 1080400 <core_durable_error.verbs+0x1500>
 105f129:	ba 01 00 00 00       	mov    $0x1,%edx
 105f12e:	48 89 c6             	mov    %rax,%rsi
 105f131:	e8 8a 53 fc ff       	call   10244c0 <myl_core_trap>
 105f136:	48 8d 3d 03 12 02 00 	lea    0x21203(%rip),%rdi        # 1080340 <core_durable_error.verbs+0x1440>
 105f13d:	ba 01 00 00 00       	mov    $0x1,%edx
 105f142:	e8 79 53 fc ff       	call   10244c0 <myl_core_trap>
 105f147:	48 8d 3d 32 11 02 00 	lea    0x21132(%rip),%rdi        # 1080280 <core_durable_error.verbs+0x1380>
 105f14e:	ba 01 00 00 00       	mov    $0x1,%edx
 105f153:	48 89 c6             	mov    %rax,%rsi
 105f156:	e8 65 53 fc ff       	call   10244c0 <myl_core_trap>
 105f15b:	48 8d 3d 7e 11 02 00 	lea    0x2117e(%rip),%rdi        # 10802e0 <core_durable_error.verbs+0x13e0>
 105f162:	ba 01 00 00 00       	mov    $0x1,%edx
 105f167:	48 89 c6             	mov    %rax,%rsi
 105f16a:	e8 51 53 fc ff       	call   10244c0 <myl_core_trap>
 105f16f:	48 8d 3d 0a 14 02 00 	lea    0x2140a(%rip),%rdi        # 1080580 <core_durable_error.verbs+0x1680>
 105f176:	ba 01 00 00 00       	mov    $0x1,%edx
 105f17b:	e8 40 53 fc ff       	call   10244c0 <myl_core_trap>
 105f180:	48 8d 3d 29 2c 02 00 	lea    0x22c29(%rip),%rdi        # 1081db0 <core_durable_error.verbs+0x2eb0>
 105f187:	ba 01 00 00 00       	mov    $0x1,%edx
 105f18c:	e8 2f 53 fc ff       	call   10244c0 <myl_core_trap>
 105f191:	48 8d 3d a8 59 02 00 	lea    0x259a8(%rip),%rdi        # 1084b40 <core_durable_error.verbs+0x5c40>
 105f198:	e8 a3 a6 fc ff       	call   1029840 <myl_core_assert_fail>
 105f19d:	48 8d 3d cc 59 02 00 	lea    0x259cc(%rip),%rdi        # 1084b70 <core_durable_error.verbs+0x5c70>
 105f1a4:	e8 97 a6 fc ff       	call   1029840 <myl_core_assert_fail>
 105f1a9:	48 8d 3d 30 2c 02 00 	lea    0x22c30(%rip),%rdi        # 1081de0 <core_durable_error.verbs+0x2ee0>
 105f1b0:	ba 01 00 00 00       	mov    $0x1,%edx
 105f1b5:	48 89 c6             	mov    %rax,%rsi
 105f1b8:	e8 03 53 fc ff       	call   10244c0 <myl_core_trap>
 105f1bd:	48 8d 3d fc 0f 02 00 	lea    0x20ffc(%rip),%rdi        # 10801c0 <core_durable_error.verbs+0x12c0>
 105f1c4:	ba 01 00 00 00       	mov    $0x1,%edx
 105f1c9:	48 89 c6             	mov    %rax,%rsi
 105f1cc:	e8 ef 52 fc ff       	call   10244c0 <myl_core_trap>
 105f1d1:	48 8d 3d 18 58 02 00 	lea    0x25818(%rip),%rdi        # 10849f0 <core_durable_error.verbs+0x5af0>
 105f1d8:	31 f6                	xor    %esi,%esi
 105f1da:	31 d2                	xor    %edx,%edx
 105f1dc:	e8 df 52 fc ff       	call   10244c0 <myl_core_trap>
 105f1e1:	48 8d 3d 58 2c 02 00 	lea    0x22c58(%rip),%rdi        # 1081e40 <core_durable_error.verbs+0x2f40>
 105f1e8:	ba 01 00 00 00       	mov    $0x1,%edx
 105f1ed:	e8 ce 52 fc ff       	call   10244c0 <myl_core_trap>
 105f1f2:	48 8d 3d 97 12 02 00 	lea    0x21297(%rip),%rdi        # 1080490 <core_durable_error.verbs+0x1590>
 105f1f9:	ba 01 00 00 00       	mov    $0x1,%edx
 105f1fe:	e8 bd 52 fc ff       	call   10244c0 <myl_core_trap>
 105f203:	48 8d 3d c6 11 02 00 	lea    0x211c6(%rip),%rdi        # 10803d0 <core_durable_error.verbs+0x14d0>
 105f20a:	ba 01 00 00 00       	mov    $0x1,%edx
 105f20f:	48 89 c6             	mov    %rax,%rsi
 105f212:	e8 a9 52 fc ff       	call   10244c0 <myl_core_trap>
 105f217:	48 8d 3d 92 58 02 00 	lea    0x25892(%rip),%rdi        # 1084ab0 <core_durable_error.verbs+0x5bb0>
 105f21e:	ba 01 00 00 00       	mov    $0x1,%edx
 105f223:	48 89 c6             	mov    %rax,%rsi
 105f226:	e8 95 52 fc ff       	call   10244c0 <myl_core_trap>
 105f22b:	48 8d 3d 9e 2c 02 00 	lea    0x22c9e(%rip),%rdi        # 1081ed0 <core_durable_error.verbs+0x2fd0>
 105f232:	e8 09 a6 fc ff       	call   1029840 <myl_core_assert_fail>

Disassembly of section .plt:
