
.tmp/lox-eda-parity/P4/compact-sret-001/candidate/lox:     file format elf64-x86-64


Disassembly of section .text:

000000000105dab0 <my.interpreter::execute>:
 105dab0:	55                   	push   %rbp
 105dab1:	41 57                	push   %r15
 105dab3:	41 56                	push   %r14
 105dab5:	41 55                	push   %r13
 105dab7:	41 54                	push   %r12
 105dab9:	53                   	push   %rbx
 105daba:	48 81 ec d8 02 00 00 	sub    $0x2d8,%rsp
 105dac1:	4d 89 ce             	mov    %r9,%r14
 105dac4:	4c 89 04 24          	mov    %r8,(%rsp)
 105dac8:	49 89 c8             	mov    %rcx,%r8
 105dacb:	48 89 d3             	mov    %rdx,%rbx
 105dace:	48 89 fd             	mov    %rdi,%rbp
 105dad1:	4c 8b a4 24 30 03 00 	mov    0x330(%rsp),%r12
 105dad8:	00 
 105dad9:	48 8b 52 08          	mov    0x8(%rdx),%rdx
 105dadd:	4c 89 e0             	mov    %r12,%rax
 105dae0:	49 39 d4             	cmp    %rdx,%r12
 105dae3:	0f 83 9f 12 00 00    	jae    105ed88 <my.interpreter::execute+0x12d8>
 105dae9:	4c 8b ac 24 28 03 00 	mov    0x328(%rsp),%r13
 105daf0:	00 
 105daf1:	44 0f b6 94 24 20 03 	movzbl 0x320(%rsp),%r10d
 105daf8:	00 00 
 105dafa:	4c 8b 9c 24 18 03 00 	mov    0x318(%rsp),%r11
 105db01:	00 
 105db02:	48 6b c8 58          	imul   $0x58,%rax,%rcx
 105db06:	48 8d 04 0b          	lea    (%rbx,%rcx,1),%rax
 105db0a:	48 83 c0 20          	add    $0x20,%rax
 105db0e:	8b 4c 0b 20          	mov    0x20(%rbx,%rcx,1),%ecx
 105db12:	48 83 f9 07          	cmp    $0x7,%rcx
 105db16:	4c 89 44 24 30       	mov    %r8,0x30(%rsp)
 105db1b:	49 89 f7             	mov    %rsi,%r15
 105db1e:	0f 87 1f 07 00 00    	ja     105e243 <my.interpreter::execute+0x793>
 105db24:	48 8d 15 99 99 fa ff 	lea    -0x56667(%rip),%rdx        # 10074c4 <core_number_pairs+0x264>
 105db2b:	48 63 0c 8a          	movslq (%rdx,%rcx,4),%rcx
 105db2f:	48 01 d1             	add    %rdx,%rcx
 105db32:	ff e1                	jmp    *%rcx
 105db34:	48 8b 48 10          	mov    0x10(%rax),%rcx
 105db38:	49 8b 96 a8 00 00 00 	mov    0xa8(%r14),%rdx
 105db3f:	48 8d bc 24 c0 00 00 	lea    0xc0(%rsp),%rdi
 105db46:	00 
 105db47:	4c 89 f6             	mov    %r14,%rsi
 105db4a:	e8 a1 e8 00 00       	call   106c3f0 <my.interpreter::new_env>
 105db4f:	48 8b 94 24 c0 00 00 	mov    0xc0(%rsp),%rdx
 105db56:	00 
 105db57:	49 8b b6 a8 00 00 00 	mov    0xa8(%r14),%rsi
 105db5e:	49 8b 86 b0 00 00 00 	mov    0xb0(%r14),%rax
 105db65:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105db69:	48 3b 48 10          	cmp    0x10(%rax),%rcx
 105db6d:	0f 83 81 12 00 00    	jae    105edf4 <my.interpreter::execute+0x1344>
 105db73:	48 89 74 c8 20       	mov    %rsi,0x20(%rax,%rcx,8)
 105db78:	48 ff c1             	inc    %rcx
 105db7b:	48 89 48 08          	mov    %rcx,0x8(%rax)
 105db7f:	49 89 86 b0 00 00 00 	mov    %rax,0xb0(%r14)
 105db86:	49 89 96 a8 00 00 00 	mov    %rdx,0xa8(%r14)
 105db8d:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 105db91:	49 39 d4             	cmp    %rdx,%r12
 105db94:	4c 8b 94 24 18 03 00 	mov    0x318(%rsp),%r10
 105db9b:	00 
 105db9c:	0f b6 b4 24 20 03 00 	movzbl 0x320(%rsp),%esi
 105dba3:	00 
 105dba4:	48 8b 4c 24 30       	mov    0x30(%rsp),%rcx
 105dba9:	0f 83 6f 12 00 00    	jae    105ee1e <my.interpreter::execute+0x136e>
 105dbaf:	4c 89 e0             	mov    %r12,%rax
 105dbb2:	48 89 da             	mov    %rbx,%rdx
 105dbb5:	48 83 c2 20          	add    $0x20,%rdx
 105dbb9:	48 6b c0 58          	imul   $0x58,%rax,%rax
 105dbbd:	83 3c 02 00          	cmpl   $0x0,(%rdx,%rax,1)
 105dbc1:	48 89 6c 24 18       	mov    %rbp,0x18(%rsp)
 105dbc6:	0f 84 f3 0a 00 00    	je     105e6bf <my.interpreter::execute+0xc0f>
 105dbcc:	40 0f b6 f6          	movzbl %sil,%esi
 105dbd0:	48 89 f3             	mov    %rsi,%rbx
 105dbd3:	31 f6                	xor    %esi,%esi
 105dbd5:	31 d2                	xor    %edx,%edx
 105dbd7:	31 c0                	xor    %eax,%eax
 105dbd9:	49 8b be b0 00 00 00 	mov    0xb0(%r14),%rdi
 105dbe0:	4c 8b 47 08          	mov    0x8(%rdi),%r8
 105dbe4:	4d 85 c0             	test   %r8,%r8
 105dbe7:	48 8b 6c 24 18       	mov    0x18(%rsp),%rbp
 105dbec:	0f 84 b3 14 00 00    	je     105f0a5 <my.interpreter::execute+0x15f5>
 105dbf2:	4e 8b 4c c7 18       	mov    0x18(%rdi,%r8,8),%r9
 105dbf7:	49 ff c8             	dec    %r8
 105dbfa:	4c 89 47 08          	mov    %r8,0x8(%rdi)
 105dbfe:	4d 89 8e a8 00 00 00 	mov    %r9,0xa8(%r14)
 105dc05:	40 84 f6             	test   %sil,%sil
 105dc08:	0f 85 79 0f 00 00    	jne    105eb87 <my.interpreter::execute+0x10d7>
 105dc0e:	48 89 55 00          	mov    %rdx,0x0(%rbp)
 105dc12:	48 89 45 08          	mov    %rax,0x8(%rbp)
 105dc16:	48 89 4d 10          	mov    %rcx,0x10(%rbp)
 105dc1a:	4c 89 55 18          	mov    %r10,0x18(%rbp)
 105dc1e:	48 89 5d 20          	mov    %rbx,0x20(%rbp)
 105dc22:	e9 e0 0e 00 00       	jmp    105eb07 <my.interpreter::execute+0x1057>
 105dc27:	48 8b 48 10          	mov    0x10(%rax),%rcx
 105dc2b:	48 89 4c 24 10       	mov    %rcx,0x10(%rsp)
 105dc30:	44 0f b6 60 18       	movzbl 0x18(%rax),%r12d
 105dc35:	48 8b 48 20          	mov    0x20(%rax),%rcx
 105dc39:	48 89 4c 24 20       	mov    %rcx,0x20(%rsp)
 105dc3e:	45 0f b6 d2          	movzbl %r10b,%r10d
 105dc42:	48 8d bc 24 10 02 00 	lea    0x210(%rsp),%rdi
 105dc49:	00 
 105dc4a:	48 89 da             	mov    %rbx,%rdx
 105dc4d:	4c 89 c1             	mov    %r8,%rcx
 105dc50:	4c 8b 04 24          	mov    (%rsp),%r8
 105dc54:	4d 89 f1             	mov    %r14,%r9
 105dc57:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105dc5e:	ff 70 08             	push   0x8(%rax)
 105dc61:	41 55                	push   %r13
 105dc63:	41 52                	push   %r10
 105dc65:	41 53                	push   %r11
 105dc67:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105dc6e:	e8 dd 6f 00 00       	call   1064c50 <my.interpreter::evaluate>
 105dc73:	48 83 c4 30          	add    $0x30,%rsp
 105dc77:	4c 8b 9c 24 28 02 00 	mov    0x228(%rsp),%r11
 105dc7e:	00 
 105dc7f:	48 8b bc 24 30 02 00 	mov    0x230(%rsp),%rdi
 105dc86:	00 
 105dc87:	44 0f b6 d7          	movzbl %dil,%r10d
 105dc8b:	4c 8b ac 24 38 02 00 	mov    0x238(%rsp),%r13
 105dc92:	00 
 105dc93:	80 bc 24 10 02 00 00 	cmpb   $0x1,0x210(%rsp)
 105dc9a:	01 
 105dc9b:	0f 84 90 0e 00 00    	je     105eb31 <my.interpreter::execute+0x1081>
 105dca1:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105dca8:	48 89 c6             	mov    %rax,%rsi
 105dcab:	48 ff ce             	dec    %rsi
 105dcae:	0f 80 4b 14 00 00    	jo     105f0ff <my.interpreter::execute+0x164f>
 105dcb4:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105dcbb:	49 8b 46 78          	mov    0x78(%r14),%rax
 105dcbf:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105dcc3:	48 39 d6             	cmp    %rdx,%rsi
 105dcc6:	48 8b 4c 24 30       	mov    0x30(%rsp),%rcx
 105dccb:	0f 83 b9 11 00 00    	jae    105ee8a <my.interpreter::execute+0x13da>
 105dcd1:	49 89 f0             	mov    %rsi,%r8
 105dcd4:	49 c1 e0 04          	shl    $0x4,%r8
 105dcd8:	42 0f b6 54 00 20    	movzbl 0x20(%rax,%r8,1),%edx
 105dcde:	85 d2                	test   %edx,%edx
 105dce0:	0f 84 2a 09 00 00    	je     105e610 <my.interpreter::execute+0xb60>
 105dce6:	83 fa 01             	cmp    $0x1,%edx
 105dce9:	75 11                	jne    105dcfc <my.interpreter::execute+0x24c>
 105dceb:	4c 01 c0             	add    %r8,%rax
 105dcee:	48 83 c0 20          	add    $0x20,%rax
 105dcf2:	f6 40 08 01          	testb  $0x1,0x8(%rax)
 105dcf6:	0f 84 14 09 00 00    	je     105e610 <my.interpreter::execute+0xb60>
 105dcfc:	48 8d bc 24 e0 01 00 	lea    0x1e0(%rsp),%rdi
 105dd03:	00 
 105dd04:	4c 89 fe             	mov    %r15,%rsi
 105dd07:	48 89 da             	mov    %rbx,%rdx
 105dd0a:	4c 8b 04 24          	mov    (%rsp),%r8
 105dd0e:	4d 89 f1             	mov    %r14,%r9
 105dd11:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105dd18:	ff 74 24 18          	push   0x18(%rsp)
 105dd1c:	41 55                	push   %r13
 105dd1e:	41 52                	push   %r10
 105dd20:	41 53                	push   %r11
 105dd22:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105dd29:	e8 82 fd ff ff       	call   105dab0 <my.interpreter::execute>
 105dd2e:	48 83 c4 30          	add    $0x30,%rsp
 105dd32:	0f b6 84 24 e0 01 00 	movzbl 0x1e0(%rsp),%eax
 105dd39:	00 
 105dd3a:	c5 f8 10 84 24 e8 01 	vmovups 0x1e8(%rsp),%xmm0
 105dd41:	00 00 
 105dd43:	48 8b 8c 24 f8 01 00 	mov    0x1f8(%rsp),%rcx
 105dd4a:	00 
 105dd4b:	0f b6 94 24 00 02 00 	movzbl 0x200(%rsp),%edx
 105dd52:	00 
 105dd53:	48 8b b4 24 08 02 00 	mov    0x208(%rsp),%rsi
 105dd5a:	00 
 105dd5b:	48 83 f8 01          	cmp    $0x1,%rax
 105dd5f:	0f 85 1e 09 00 00    	jne    105e683 <my.interpreter::execute+0xbd3>
 105dd65:	48 8d 3d 54 23 02 00 	lea    0x22354(%rip),%rdi        # 10800c0 <core_durable_error.verbs+0x1170>
 105dd6c:	e9 df 0f 00 00       	jmp    105ed50 <my.interpreter::execute+0x12a0>
 105dd71:	48 8b 40 08          	mov    0x8(%rax),%rax
 105dd75:	48 8b 56 08          	mov    0x8(%rsi),%rdx
 105dd79:	48 89 c1             	mov    %rax,%rcx
 105dd7c:	48 39 d0             	cmp    %rdx,%rax
 105dd7f:	0f 83 28 10 00 00    	jae    105edad <my.interpreter::execute+0x12fd>
 105dd85:	48 6b c9 70          	imul   $0x70,%rcx,%rcx
 105dd89:	83 7c 0e 20 0b       	cmpl   $0xb,0x20(%rsi,%rcx,1)
 105dd8e:	0f 85 58 06 00 00    	jne    105e3ec <my.interpreter::execute+0x93c>
 105dd94:	48 01 f1             	add    %rsi,%rcx
 105dd97:	48 83 c1 20          	add    $0x20,%rcx
 105dd9b:	48 8b 79 38          	mov    0x38(%rcx),%rdi
 105dd9f:	48 83 ff ff          	cmp    $0xffffffffffffffff,%rdi
 105dda3:	0f 84 43 06 00 00    	je     105e3ec <my.interpreter::execute+0x93c>
 105dda9:	48 8b 71 40          	mov    0x40(%rcx),%rsi
 105ddad:	49 8b 0e             	mov    (%r14),%rcx
 105ddb0:	49 8b 86 a8 00 00 00 	mov    0xa8(%r14),%rax
 105ddb7:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105ddbb:	48 85 ff             	test   %rdi,%rdi
 105ddbe:	0f 8e c0 09 00 00    	jle    105e784 <my.interpreter::execute+0xcd4>
 105ddc4:	4c 8d 41 20          	lea    0x20(%rcx),%r8
 105ddc8:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105ddcf:	0f 1f 84 00 00 00 00 
 105ddd6:	00 
 105ddd7:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105ddde:	0f 1f 84 00 00 00 00 
 105dde5:	00 
 105dde6:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105dded:	0f 1f 84 00 00 00 00 
 105ddf4:	00 
 105ddf5:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 105ddfc:	00 00 00 00 
 105de00:	48 39 d0             	cmp    %rdx,%rax
 105de03:	73 23                	jae    105de28 <my.interpreter::execute+0x378>
 105de05:	49 89 c1             	mov    %rax,%r9
 105de08:	49 6b c1 38          	imul   $0x38,%r9,%rax
 105de0c:	41 83 3c 00 09       	cmpl   $0x9,(%r8,%rax,1)
 105de11:	0f 85 65 12 00 00    	jne    105f07c <my.interpreter::execute+0x15cc>
 105de17:	4c 01 c0             	add    %r8,%rax
 105de1a:	48 8b 40 08          	mov    0x8(%rax),%rax
 105de1e:	48 ff cf             	dec    %rdi
 105de21:	75 dd                	jne    105de00 <my.interpreter::execute+0x350>
 105de23:	e9 5c 09 00 00       	jmp    105e784 <my.interpreter::execute+0xcd4>
 105de28:	49 89 c1             	mov    %rax,%r9
 105de2b:	49 c1 f9 3f          	sar    $0x3f,%r9
 105de2f:	49 21 d1             	and    %rdx,%r9
 105de32:	49 01 c1             	add    %rax,%r9
 105de35:	49 39 d1             	cmp    %rdx,%r9
 105de38:	72 ce                	jb     105de08 <my.interpreter::execute+0x358>
 105de3a:	48 8d 3d df 6d 02 00 	lea    0x26ddf(%rip),%rdi        # 1084c20 <core_durable_error.verbs+0x5cd0>
 105de41:	48 89 c6             	mov    %rax,%rsi
 105de44:	e8 37 66 fc ff       	call   1024480 <myl_core_trap>
 105de49:	4d 89 dc             	mov    %r11,%r12
 105de4c:	48 8b 70 08          	mov    0x8(%rax),%rsi
 105de50:	49 8b 50 08          	mov    0x8(%r8),%rdx
 105de54:	48 89 f0             	mov    %rsi,%rax
 105de57:	48 39 d6             	cmp    %rdx,%rsi
 105de5a:	0f 83 72 0f 00 00    	jae    105edd2 <my.interpreter::execute+0x1322>
 105de60:	48 8d 04 80          	lea    (%rax,%rax,4),%rax
 105de64:	48 c1 e0 04          	shl    $0x4,%rax
 105de68:	49 8b 5c 00 48       	mov    0x48(%r8,%rax,1),%rbx
 105de6d:	4d 8b 7c 00 60       	mov    0x60(%r8,%rax,1),%r15
 105de72:	49 8b 86 a8 00 00 00 	mov    0xa8(%r14),%rax
 105de79:	48 c7 84 24 70 02 00 	movq   $0xa,0x270(%rsp)
 105de80:	00 0a 00 00 00 
 105de85:	48 89 b4 24 78 02 00 	mov    %rsi,0x278(%rsp)
 105de8c:	00 
 105de8d:	48 89 9c 24 80 02 00 	mov    %rbx,0x280(%rsp)
 105de94:	00 
 105de95:	48 89 84 24 88 02 00 	mov    %rax,0x288(%rsp)
 105de9c:	00 
 105de9d:	c6 84 24 90 02 00 00 	movb   $0x0,0x290(%rsp)
 105dea4:	00 
 105dea5:	48 8d 7c 24 68       	lea    0x68(%rsp),%rdi
 105deaa:	48 8d 94 24 70 02 00 	lea    0x270(%rsp),%rdx
 105deb1:	00 
 105deb2:	4c 89 f6             	mov    %r14,%rsi
 105deb5:	e8 96 c2 ff ff       	call   105a150 <my.heap::allocate>
 105deba:	48 8b 44 24 68       	mov    0x68(%rsp),%rax
 105debf:	49 8b 4e 78          	mov    0x78(%r14),%rcx
 105dec3:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105deca:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105dece:	48 39 d6             	cmp    %rdx,%rsi
 105ded1:	0f 83 6c 0f 00 00    	jae    105ee43 <my.interpreter::execute+0x1393>
 105ded7:	48 89 f7             	mov    %rsi,%rdi
 105deda:	48 c1 e7 04          	shl    $0x4,%rdi
 105dede:	48 c7 44 39 20 03 00 	movq   $0x3,0x20(%rcx,%rdi,1)
 105dee5:	00 00 
 105dee7:	48 89 44 39 28       	mov    %rax,0x28(%rcx,%rdi,1)
 105deec:	49 89 4e 78          	mov    %rcx,0x78(%r14)
 105def0:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105def7:	48 89 f0             	mov    %rsi,%rax
 105defa:	48 ff c0             	inc    %rax
 105defd:	0f 80 b2 11 00 00    	jo     105f0b5 <my.interpreter::execute+0x1605>
 105df03:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 105df0a:	4c 89 f7             	mov    %r14,%rdi
 105df0d:	48 89 de             	mov    %rbx,%rsi
 105df10:	4c 89 fa             	mov    %r15,%rdx
 105df13:	e8 b8 9a 00 00       	call   10679d0 <my.interpreter::define>
 105df18:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105df1f:	48 89 c6             	mov    %rax,%rsi
 105df22:	48 ff ce             	dec    %rsi
 105df25:	0f 80 9b 11 00 00    	jo     105f0c6 <my.interpreter::execute+0x1616>
 105df2b:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105df32:	49 8b 46 78          	mov    0x78(%r14),%rax
 105df36:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105df3a:	48 39 d6             	cmp    %rdx,%rsi
 105df3d:	4d 89 e3             	mov    %r12,%r11
 105df40:	0f b6 bc 24 20 03 00 	movzbl 0x320(%rsp),%edi
 105df47:	00 
 105df48:	0f 82 a4 0b 00 00    	jb     105eaf2 <my.interpreter::execute+0x1042>
 105df4e:	48 89 f0             	mov    %rsi,%rax
 105df51:	48 c1 f8 3f          	sar    $0x3f,%rax
 105df55:	48 21 d0             	and    %rdx,%rax
 105df58:	48 01 f0             	add    %rsi,%rax
 105df5b:	48 39 d0             	cmp    %rdx,%rax
 105df5e:	0f 82 8e 0b 00 00    	jb     105eaf2 <my.interpreter::execute+0x1042>
 105df64:	48 8d 3d 35 26 02 00 	lea    0x22635(%rip),%rdi        # 10805a0 <core_durable_error.verbs+0x1650>
 105df6b:	e8 10 65 fc ff       	call   1024480 <myl_core_trap>
 105df70:	4c 8b 60 30          	mov    0x30(%rax),%r12
 105df74:	4c 8b 48 48          	mov    0x48(%rax),%r9
 105df78:	80 78 38 01          	cmpb   $0x1,0x38(%rax)
 105df7c:	0f 85 14 05 00 00    	jne    105e496 <my.interpreter::execute+0x9e6>
 105df82:	4c 89 4c 24 30       	mov    %r9,0x30(%rsp)
 105df87:	45 0f b6 d2          	movzbl %r10b,%r10d
 105df8b:	48 8d bc 24 50 01 00 	lea    0x150(%rsp),%rdi
 105df92:	00 
 105df93:	48 89 da             	mov    %rbx,%rdx
 105df96:	4c 89 c1             	mov    %r8,%rcx
 105df99:	4c 8b 04 24          	mov    (%rsp),%r8
 105df9d:	4d 89 f1             	mov    %r14,%r9
 105dfa0:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105dfa7:	ff 70 40             	push   0x40(%rax)
 105dfaa:	41 55                	push   %r13
 105dfac:	41 52                	push   %r10
 105dfae:	41 53                	push   %r11
 105dfb0:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105dfb7:	e8 94 6c 00 00       	call   1064c50 <my.interpreter::evaluate>
 105dfbc:	48 83 c4 30          	add    $0x30,%rsp
 105dfc0:	48 8b 9c 24 68 01 00 	mov    0x168(%rsp),%rbx
 105dfc7:	00 
 105dfc8:	4c 8b bc 24 70 01 00 	mov    0x170(%rsp),%r15
 105dfcf:	00 
 105dfd0:	4c 8b ac 24 78 01 00 	mov    0x178(%rsp),%r13
 105dfd7:	00 
 105dfd8:	80 bc 24 50 01 00 00 	cmpb   $0x1,0x150(%rsp)
 105dfdf:	01 
 105dfe0:	0f 84 89 0c 00 00    	je     105ec6f <my.interpreter::execute+0x11bf>
 105dfe6:	4c 8b 4c 24 30       	mov    0x30(%rsp),%r9
 105dfeb:	e9 f2 04 00 00       	jmp    105e4e2 <my.interpreter::execute+0xa32>
 105dff0:	48 8b 48 30          	mov    0x30(%rax),%rcx
 105dff4:	48 89 4c 24 20       	mov    %rcx,0x20(%rsp)
 105dff9:	48 8b 48 38          	mov    0x38(%rax),%rcx
 105dffd:	44 0f b6 60 40       	movzbl 0x40(%rax),%r12d
 105e002:	48 8b 50 48          	mov    0x48(%rax),%rdx
 105e006:	48 89 54 24 28       	mov    %rdx,0x28(%rsp)
 105e00b:	48 8b 40 50          	mov    0x50(%rax),%rax
 105e00f:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105e014:	48 89 4c 24 60       	mov    %rcx,0x60(%rsp)
 105e019:	48 83 f9 ff          	cmp    $0xffffffffffffffff,%rcx
 105e01d:	75 51                	jne    105e070 <my.interpreter::execute+0x5c0>
 105e01f:	4c 89 f7             	mov    %r14,%rdi
 105e022:	4c 8b 6c 24 20       	mov    0x20(%rsp),%r13
 105e027:	4c 89 ee             	mov    %r13,%rsi
 105e02a:	e8 f1 ba 00 00       	call   1069b20 <my.heap::string_hash>
 105e02f:	49 8b 7e 30          	mov    0x30(%r14),%rdi
 105e033:	49 8b 76 38          	mov    0x38(%r14),%rsi
 105e037:	4c 89 ea             	mov    %r13,%rdx
 105e03a:	89 c1                	mov    %eax,%ecx
 105e03c:	45 31 c0             	xor    %r8d,%r8d
 105e03f:	45 31 c9             	xor    %r9d,%r9d
 105e042:	e8 b9 bb 00 00       	call   1069c00 <my.table::set>
 105e047:	4c 89 fe             	mov    %r15,%rsi
 105e04a:	4c 8b 44 24 30       	mov    0x30(%rsp),%r8
 105e04f:	44 0f b6 94 24 20 03 	movzbl 0x320(%rsp),%r10d
 105e056:	00 00 
 105e058:	4c 8b 9c 24 18 03 00 	mov    0x318(%rsp),%r11
 105e05f:	00 
 105e060:	4c 8b ac 24 28 03 00 	mov    0x328(%rsp),%r13
 105e067:	00 
 105e068:	49 89 56 30          	mov    %rdx,0x30(%r14)
 105e06c:	49 89 4e 38          	mov    %rcx,0x38(%r14)
 105e070:	49 c7 c7 ff ff ff ff 	mov    $0xffffffffffffffff,%r15
 105e077:	41 83 fc 01          	cmp    $0x1,%r12d
 105e07b:	0f 85 c2 04 00 00    	jne    105e543 <my.interpreter::execute+0xa93>
 105e081:	41 0f b6 c2          	movzbl %r10b,%eax
 105e085:	48 8d bc 24 c0 00 00 	lea    0xc0(%rsp),%rdi
 105e08c:	00 
 105e08d:	49 89 f7             	mov    %rsi,%r15
 105e090:	48 89 da             	mov    %rbx,%rdx
 105e093:	4c 89 c1             	mov    %r8,%rcx
 105e096:	4c 8b 04 24          	mov    (%rsp),%r8
 105e09a:	4d 89 f1             	mov    %r14,%r9
 105e09d:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e0a4:	48 8b 5c 24 30       	mov    0x30(%rsp),%rbx
 105e0a9:	53                   	push   %rbx
 105e0aa:	41 55                	push   %r13
 105e0ac:	50                   	push   %rax
 105e0ad:	41 53                	push   %r11
 105e0af:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e0b6:	e8 95 6b 00 00       	call   1064c50 <my.interpreter::evaluate>
 105e0bb:	48 83 c4 30          	add    $0x30,%rsp
 105e0bf:	48 8b bc 24 d8 00 00 	mov    0xd8(%rsp),%rdi
 105e0c6:	00 
 105e0c7:	44 0f b6 84 24 e0 00 	movzbl 0xe0(%rsp),%r8d
 105e0ce:	00 00 
 105e0d0:	4c 8b ac 24 e8 00 00 	mov    0xe8(%rsp),%r13
 105e0d7:	00 
 105e0d8:	80 bc 24 c0 00 00 00 	cmpb   $0x1,0xc0(%rsp)
 105e0df:	01 
 105e0e0:	0f 84 c2 0b 00 00    	je     105eca8 <my.interpreter::execute+0x11f8>
 105e0e6:	49 8b 57 08          	mov    0x8(%r15),%rdx
 105e0ea:	48 39 d3             	cmp    %rdx,%rbx
 105e0ed:	0f 83 9e 0e 00 00    	jae    105ef91 <my.interpreter::execute+0x14e1>
 105e0f3:	48 89 d8             	mov    %rbx,%rax
 105e0f6:	48 6b c0 70          	imul   $0x70,%rax,%rax
 105e0fa:	41 83 7c 07 20 0b    	cmpl   $0xb,0x20(%r15,%rax,1)
 105e100:	0f 85 df 06 00 00    	jne    105e7e5 <my.interpreter::execute+0xd35>
 105e106:	4c 01 f8             	add    %r15,%rax
 105e109:	48 83 c0 20          	add    $0x20,%rax
 105e10d:	48 8b 58 20          	mov    0x20(%rax),%rbx
 105e111:	e9 d1 06 00 00       	jmp    105e7e7 <my.interpreter::execute+0xd37>
 105e116:	45 0f b6 d2          	movzbl %r10b,%r10d
 105e11a:	48 8d bc 24 80 01 00 	lea    0x180(%rsp),%rdi
 105e121:	00 
 105e122:	48 89 da             	mov    %rbx,%rdx
 105e125:	4c 89 c1             	mov    %r8,%rcx
 105e128:	4c 8b 04 24          	mov    (%rsp),%r8
 105e12c:	4d 89 f1             	mov    %r14,%r9
 105e12f:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e136:	ff 70 08             	push   0x8(%rax)
 105e139:	41 55                	push   %r13
 105e13b:	41 52                	push   %r10
 105e13d:	41 53                	push   %r11
 105e13f:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e146:	e8 05 6b 00 00       	call   1064c50 <my.interpreter::evaluate>
 105e14b:	48 83 c4 30          	add    $0x30,%rsp
 105e14f:	48 8b 9c 24 98 01 00 	mov    0x198(%rsp),%rbx
 105e156:	00 
 105e157:	4c 8b bc 24 a0 01 00 	mov    0x1a0(%rsp),%r15
 105e15e:	00 
 105e15f:	4c 8b ac 24 a8 01 00 	mov    0x1a8(%rsp),%r13
 105e166:	00 
 105e167:	80 bc 24 80 01 00 00 	cmpb   $0x1,0x180(%rsp)
 105e16e:	01 
 105e16f:	0f 84 f4 09 00 00    	je     105eb69 <my.interpreter::execute+0x10b9>
 105e175:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105e17c:	48 89 c6             	mov    %rax,%rsi
 105e17f:	48 ff ce             	dec    %rsi
 105e182:	0f 80 8b 0f 00 00    	jo     105f113 <my.interpreter::execute+0x1663>
 105e188:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e18c:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e190:	48 39 d6             	cmp    %rdx,%rsi
 105e193:	0f 83 13 0d 00 00    	jae    105eeac <my.interpreter::execute+0x13fc>
 105e199:	48 89 f7             	mov    %rsi,%rdi
 105e19c:	48 c1 e7 04          	shl    $0x4,%rdi
 105e1a0:	48 8b 4c 38 28       	mov    0x28(%rax,%rdi,1),%rcx
 105e1a5:	8b 54 38 20          	mov    0x20(%rax,%rdi,1),%edx
 105e1a9:	4c 89 f7             	mov    %r14,%rdi
 105e1ac:	48 8b b4 24 10 03 00 	mov    0x310(%rsp),%rsi
 105e1b3:	00 
 105e1b4:	e8 f7 43 00 00       	call   10625b0 <my.output::print_value>
 105e1b9:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105e1c0:	48 89 f0             	mov    %rsi,%rax
 105e1c3:	48 ff c8             	dec    %rax
 105e1c6:	0f 80 5b 0f 00 00    	jo     105f127 <my.interpreter::execute+0x1677>
 105e1cc:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 105e1d3:	49 89 db             	mov    %rbx,%r11
 105e1d6:	4c 89 ff             	mov    %r15,%rdi
 105e1d9:	e9 14 09 00 00       	jmp    105eaf2 <my.interpreter::execute+0x1042>
 105e1de:	83 78 30 01          	cmpl   $0x1,0x30(%rax)
 105e1e2:	0f 85 6a 03 00 00    	jne    105e552 <my.interpreter::execute+0xaa2>
 105e1e8:	45 0f b6 d2          	movzbl %r10b,%r10d
 105e1ec:	48 8d bc 24 a8 02 00 	lea    0x2a8(%rsp),%rdi
 105e1f3:	00 
 105e1f4:	48 89 da             	mov    %rbx,%rdx
 105e1f7:	4c 89 c1             	mov    %r8,%rcx
 105e1fa:	4c 8b 04 24          	mov    (%rsp),%r8
 105e1fe:	4d 89 f1             	mov    %r14,%r9
 105e201:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e208:	ff 70 38             	push   0x38(%rax)
 105e20b:	41 55                	push   %r13
 105e20d:	41 52                	push   %r10
 105e20f:	41 53                	push   %r11
 105e211:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e218:	e8 33 6a 00 00       	call   1064c50 <my.interpreter::evaluate>
 105e21d:	48 83 c4 30          	add    $0x30,%rsp
 105e221:	4c 8b 9c 24 c0 02 00 	mov    0x2c0(%rsp),%r11
 105e228:	00 
 105e229:	80 bc 24 a8 02 00 00 	cmpb   $0x1,0x2a8(%rsp)
 105e230:	01 
 105e231:	0f 84 c5 0a 00 00    	je     105ecfc <my.interpreter::execute+0x124c>
 105e237:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105e23e:	e9 55 03 00 00       	jmp    105e598 <my.interpreter::execute+0xae8>
 105e243:	48 89 6c 24 18       	mov    %rbp,0x18(%rsp)
 105e248:	4c 8b 60 08          	mov    0x8(%rax),%r12
 105e24c:	48 8b 40 10          	mov    0x10(%rax),%rax
 105e250:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105e255:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105e25c:	0f 1f 84 00 00 00 00 
 105e263:	00 
 105e264:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105e26b:	0f 1f 84 00 00 00 00 
 105e272:	00 
 105e273:	66 66 66 66 2e 0f 1f 	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105e27a:	84 00 00 00 00 00 
 105e280:	41 0f b6 c2          	movzbl %r10b,%eax
 105e284:	48 8d bc 24 20 01 00 	lea    0x120(%rsp),%rdi
 105e28b:	00 
 105e28c:	48 89 da             	mov    %rbx,%rdx
 105e28f:	4c 89 c1             	mov    %r8,%rcx
 105e292:	4c 8b 04 24          	mov    (%rsp),%r8
 105e296:	4d 89 f1             	mov    %r14,%r9
 105e299:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e2a0:	41 54                	push   %r12
 105e2a2:	41 55                	push   %r13
 105e2a4:	50                   	push   %rax
 105e2a5:	41 53                	push   %r11
 105e2a7:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e2ae:	e8 9d 69 00 00       	call   1064c50 <my.interpreter::evaluate>
 105e2b3:	48 83 c4 30          	add    $0x30,%rsp
 105e2b7:	4c 8b 94 24 38 01 00 	mov    0x138(%rsp),%r10
 105e2be:	00 
 105e2bf:	48 8b 84 24 40 01 00 	mov    0x140(%rsp),%rax
 105e2c6:	00 
 105e2c7:	0f b6 e8             	movzbl %al,%ebp
 105e2ca:	4c 8b ac 24 48 01 00 	mov    0x148(%rsp),%r13
 105e2d1:	00 
 105e2d2:	80 bc 24 20 01 00 00 	cmpb   $0x1,0x120(%rsp)
 105e2d9:	01 
 105e2da:	0f 84 25 09 00 00    	je     105ec05 <my.interpreter::execute+0x1155>
 105e2e0:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105e2e7:	48 89 c6             	mov    %rax,%rsi
 105e2ea:	48 ff ce             	dec    %rsi
 105e2ed:	0f 80 75 0d 00 00    	jo     105f068 <my.interpreter::execute+0x15b8>
 105e2f3:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105e2fa:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e2fe:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e302:	48 39 d6             	cmp    %rdx,%rsi
 105e305:	48 8b 4c 24 30       	mov    0x30(%rsp),%rcx
 105e30a:	0f 83 ba 00 00 00    	jae    105e3ca <my.interpreter::execute+0x91a>
 105e310:	48 89 f7             	mov    %rsi,%rdi
 105e313:	48 c1 e7 04          	shl    $0x4,%rdi
 105e317:	0f b6 54 38 20       	movzbl 0x20(%rax,%rdi,1),%edx
 105e31c:	83 fa 01             	cmp    $0x1,%edx
 105e31f:	74 1f                	je     105e340 <my.interpreter::execute+0x890>
 105e321:	85 d2                	test   %edx,%edx
 105e323:	4c 89 fe             	mov    %r15,%rsi
 105e326:	75 2c                	jne    105e354 <my.interpreter::execute+0x8a4>
 105e328:	e9 c2 02 00 00       	jmp    105e5ef <my.interpreter::execute+0xb3f>
 105e32d:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105e334:	0f 1f 84 00 00 00 00 
 105e33b:	00 
 105e33c:	0f 1f 40 00          	nopl   0x0(%rax)
 105e340:	48 01 f8             	add    %rdi,%rax
 105e343:	48 83 c0 20          	add    $0x20,%rax
 105e347:	f6 40 08 01          	testb  $0x1,0x8(%rax)
 105e34b:	4c 89 fe             	mov    %r15,%rsi
 105e34e:	0f 84 9b 02 00 00    	je     105e5ef <my.interpreter::execute+0xb3f>
 105e354:	48 8d bc 24 f0 00 00 	lea    0xf0(%rsp),%rdi
 105e35b:	00 
 105e35c:	48 89 da             	mov    %rbx,%rdx
 105e35f:	4c 8b 04 24          	mov    (%rsp),%r8
 105e363:	4d 89 f1             	mov    %r14,%r9
 105e366:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e36d:	ff 74 24 18          	push   0x18(%rsp)
 105e371:	41 55                	push   %r13
 105e373:	55                   	push   %rbp
 105e374:	41 52                	push   %r10
 105e376:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e37d:	e8 2e f7 ff ff       	call   105dab0 <my.interpreter::execute>
 105e382:	48 83 c4 30          	add    $0x30,%rsp
 105e386:	48 8b 84 24 f8 00 00 	mov    0xf8(%rsp),%rax
 105e38d:	00 
 105e38e:	4c 8b 9c 24 08 01 00 	mov    0x108(%rsp),%r11
 105e395:	00 
 105e396:	44 0f b6 94 24 10 01 	movzbl 0x110(%rsp),%r10d
 105e39d:	00 00 
 105e39f:	4c 8b ac 24 18 01 00 	mov    0x118(%rsp),%r13
 105e3a6:	00 
 105e3a7:	80 bc 24 f0 00 00 00 	cmpb   $0x1,0xf0(%rsp)
 105e3ae:	01 
 105e3af:	0f 84 85 08 00 00    	je     105ec3a <my.interpreter::execute+0x118a>
 105e3b5:	3c 01                	cmp    $0x1,%al
 105e3b7:	4c 8b 44 24 30       	mov    0x30(%rsp),%r8
 105e3bc:	4c 89 fe             	mov    %r15,%rsi
 105e3bf:	0f 85 bb fe ff ff    	jne    105e280 <my.interpreter::execute+0x7d0>
 105e3c5:	e9 d3 02 00 00       	jmp    105e69d <my.interpreter::execute+0xbed>
 105e3ca:	48 89 f7             	mov    %rsi,%rdi
 105e3cd:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105e3d1:	48 21 d7             	and    %rdx,%rdi
 105e3d4:	48 01 f7             	add    %rsi,%rdi
 105e3d7:	48 39 d7             	cmp    %rdx,%rdi
 105e3da:	0f 82 33 ff ff ff    	jb     105e313 <my.interpreter::execute+0x863>
 105e3e0:	48 8d 3d 59 21 02 00 	lea    0x22159(%rip),%rdi        # 1080540 <core_durable_error.verbs+0x15f0>
 105e3e7:	e8 94 60 fc ff       	call   1024480 <myl_core_trap>
 105e3ec:	45 0f b6 d2          	movzbl %r10b,%r10d
 105e3f0:	48 8d bc 24 40 02 00 	lea    0x240(%rsp),%rdi
 105e3f7:	00 
 105e3f8:	48 89 da             	mov    %rbx,%rdx
 105e3fb:	4c 89 c1             	mov    %r8,%rcx
 105e3fe:	4c 8b 04 24          	mov    (%rsp),%r8
 105e402:	4d 89 f1             	mov    %r14,%r9
 105e405:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e40c:	50                   	push   %rax
 105e40d:	41 55                	push   %r13
 105e40f:	41 52                	push   %r10
 105e411:	41 53                	push   %r11
 105e413:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e41a:	e8 31 68 00 00       	call   1064c50 <my.interpreter::evaluate>
 105e41f:	48 83 c4 30          	add    $0x30,%rsp
 105e423:	4c 8b 9c 24 58 02 00 	mov    0x258(%rsp),%r11
 105e42a:	00 
 105e42b:	48 8b bc 24 60 02 00 	mov    0x260(%rsp),%rdi
 105e432:	00 
 105e433:	4c 8b ac 24 68 02 00 	mov    0x268(%rsp),%r13
 105e43a:	00 
 105e43b:	80 bc 24 40 02 00 00 	cmpb   $0x1,0x240(%rsp)
 105e442:	01 
 105e443:	0f 84 80 07 00 00    	je     105ebc9 <my.interpreter::execute+0x1119>
 105e449:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105e450:	48 89 c6             	mov    %rax,%rsi
 105e453:	48 ff ce             	dec    %rsi
 105e456:	0f 80 19 0d 00 00    	jo     105f175 <my.interpreter::execute+0x16c5>
 105e45c:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105e463:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e467:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e46b:	48 39 d6             	cmp    %rdx,%rsi
 105e46e:	0f 82 7e 06 00 00    	jb     105eaf2 <my.interpreter::execute+0x1042>
 105e474:	48 89 f0             	mov    %rsi,%rax
 105e477:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e47b:	48 21 d0             	and    %rdx,%rax
 105e47e:	48 01 f0             	add    %rsi,%rax
 105e481:	48 39 d0             	cmp    %rdx,%rax
 105e484:	0f 82 68 06 00 00    	jb     105eaf2 <my.interpreter::execute+0x1042>
 105e48a:	48 8d 3d af 1d 02 00 	lea    0x21daf(%rip),%rdi        # 1080240 <core_durable_error.verbs+0x12f0>
 105e491:	e8 ea 5f fc ff       	call   1024480 <myl_core_trap>
 105e496:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e49a:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105e4a1:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e4a5:	48 39 d6             	cmp    %rdx,%rsi
 105e4a8:	0f 83 9f 0a 00 00    	jae    105ef4d <my.interpreter::execute+0x149d>
 105e4ae:	48 89 f1             	mov    %rsi,%rcx
 105e4b1:	48 c1 e1 04          	shl    $0x4,%rcx
 105e4b5:	48 c7 44 08 20 00 00 	movq   $0x0,0x20(%rax,%rcx,1)
 105e4bc:	00 00 
 105e4be:	49 89 46 78          	mov    %rax,0x78(%r14)
 105e4c2:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105e4c9:	48 89 f0             	mov    %rsi,%rax
 105e4cc:	48 ff c0             	inc    %rax
 105e4cf:	0f 80 d5 0c 00 00    	jo     105f1aa <my.interpreter::execute+0x16fa>
 105e4d5:	4d 89 d7             	mov    %r10,%r15
 105e4d8:	4c 89 db             	mov    %r11,%rbx
 105e4db:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 105e4e2:	4c 89 f7             	mov    %r14,%rdi
 105e4e5:	4c 89 e6             	mov    %r12,%rsi
 105e4e8:	4c 89 ca             	mov    %r9,%rdx
 105e4eb:	e8 e0 94 00 00       	call   10679d0 <my.interpreter::define>
 105e4f0:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105e4f7:	48 89 c6             	mov    %rax,%rsi
 105e4fa:	48 ff ce             	dec    %rsi
 105e4fd:	0f 80 d7 0b 00 00    	jo     105f0da <my.interpreter::execute+0x162a>
 105e503:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105e50a:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e50e:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e512:	48 39 d6             	cmp    %rdx,%rsi
 105e515:	49 89 db             	mov    %rbx,%r11
 105e518:	4c 89 ff             	mov    %r15,%rdi
 105e51b:	0f 82 d1 05 00 00    	jb     105eaf2 <my.interpreter::execute+0x1042>
 105e521:	48 89 f0             	mov    %rsi,%rax
 105e524:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e528:	48 21 d0             	and    %rdx,%rax
 105e52b:	48 01 f0             	add    %rsi,%rax
 105e52e:	48 39 d0             	cmp    %rdx,%rax
 105e531:	0f 82 bb 05 00 00    	jb     105eaf2 <my.interpreter::execute+0x1042>
 105e537:	48 8d 3d 42 1f 02 00 	lea    0x21f42(%rip),%rdi        # 1080480 <core_durable_error.verbs+0x1530>
 105e53e:	e8 3d 5f fc ff       	call   1024480 <myl_core_trap>
 105e543:	4c 89 54 24 28       	mov    %r10,0x28(%rsp)
 105e548:	4c 89 5c 24 48       	mov    %r11,0x48(%rsp)
 105e54d:	e9 fc 02 00 00       	jmp    105e84e <my.interpreter::execute+0xd9e>
 105e552:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e556:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105e55d:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e561:	48 39 d6             	cmp    %rdx,%rsi
 105e564:	0f 83 05 0a 00 00    	jae    105ef6f <my.interpreter::execute+0x14bf>
 105e56a:	48 89 f1             	mov    %rsi,%rcx
 105e56d:	48 c1 e1 04          	shl    $0x4,%rcx
 105e571:	48 c7 44 08 20 00 00 	movq   $0x0,0x20(%rax,%rcx,1)
 105e578:	00 00 
 105e57a:	49 89 46 78          	mov    %rax,0x78(%r14)
 105e57e:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105e585:	48 89 c6             	mov    %rax,%rsi
 105e588:	48 ff c6             	inc    %rsi
 105e58b:	0f 80 2a 0c 00 00    	jo     105f1bb <my.interpreter::execute+0x170b>
 105e591:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105e598:	48 89 f0             	mov    %rsi,%rax
 105e59b:	48 ff c8             	dec    %rax
 105e59e:	0f 80 4a 0b 00 00    	jo     105f0ee <my.interpreter::execute+0x163e>
 105e5a4:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 105e5ab:	49 8b 4e 78          	mov    0x78(%r14),%rcx
 105e5af:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105e5b3:	48 39 d0             	cmp    %rdx,%rax
 105e5b6:	0f 83 a9 08 00 00    	jae    105ee65 <my.interpreter::execute+0x13b5>
 105e5bc:	48 89 c6             	mov    %rax,%rsi
 105e5bf:	48 c1 e6 04          	shl    $0x4,%rsi
 105e5c3:	c5 f8 10 44 31 20    	vmovups 0x20(%rcx,%rsi,1),%xmm0
 105e5c9:	48 c7 45 00 00 00 00 	movq   $0x0,0x0(%rbp)
 105e5d0:	00 
 105e5d1:	48 c7 45 08 01 00 00 	movq   $0x1,0x8(%rbp)
 105e5d8:	00 
 105e5d9:	4c 89 5d 18          	mov    %r11,0x18(%rbp)
 105e5dd:	c5 f8 54 05 fb 5d fa 	vandps -0x5a205(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105e5e4:	ff 
 105e5e5:	c5 f8 11 45 20       	vmovups %xmm0,0x20(%rbp)
 105e5ea:	e9 1c 05 00 00       	jmp    105eb0b <my.interpreter::execute+0x105b>
 105e5ef:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
 105e5f3:	48 8b 44 24 18       	mov    0x18(%rsp),%rax
 105e5f8:	c5 f8 11 00          	vmovups %xmm0,(%rax)
 105e5fc:	4c 89 50 18          	mov    %r10,0x18(%rax)
 105e600:	48 89 68 20          	mov    %rbp,0x20(%rax)
 105e604:	48 89 c5             	mov    %rax,%rbp
 105e607:	4c 89 68 28          	mov    %r13,0x28(%rax)
 105e60b:	e9 fb 04 00 00       	jmp    105eb0b <my.interpreter::execute+0x105b>
 105e610:	41 83 fc 01          	cmp    $0x1,%r12d
 105e614:	0f 85 d8 04 00 00    	jne    105eaf2 <my.interpreter::execute+0x1042>
 105e61a:	48 8d bc 24 b0 01 00 	lea    0x1b0(%rsp),%rdi
 105e621:	00 
 105e622:	4c 89 fe             	mov    %r15,%rsi
 105e625:	48 89 da             	mov    %rbx,%rdx
 105e628:	4c 8b 04 24          	mov    (%rsp),%r8
 105e62c:	4d 89 f1             	mov    %r14,%r9
 105e62f:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e636:	ff 74 24 28          	push   0x28(%rsp)
 105e63a:	41 55                	push   %r13
 105e63c:	41 52                	push   %r10
 105e63e:	41 53                	push   %r11
 105e640:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e647:	e8 64 f4 ff ff       	call   105dab0 <my.interpreter::execute>
 105e64c:	48 83 c4 30          	add    $0x30,%rsp
 105e650:	0f b6 84 24 b0 01 00 	movzbl 0x1b0(%rsp),%eax
 105e657:	00 
 105e658:	c5 f8 10 84 24 b8 01 	vmovups 0x1b8(%rsp),%xmm0
 105e65f:	00 00 
 105e661:	48 8b 8c 24 c8 01 00 	mov    0x1c8(%rsp),%rcx
 105e668:	00 
 105e669:	0f b6 94 24 d0 01 00 	movzbl 0x1d0(%rsp),%edx
 105e670:	00 
 105e671:	48 8b b4 24 d8 01 00 	mov    0x1d8(%rsp),%rsi
 105e678:	00 
 105e679:	48 83 f8 01          	cmp    $0x1,%rax
 105e67d:	0f 84 c6 06 00 00    	je     105ed49 <my.interpreter::execute+0x1299>
 105e683:	48 89 45 00          	mov    %rax,0x0(%rbp)
 105e687:	c5 f8 11 45 08       	vmovups %xmm0,0x8(%rbp)
 105e68c:	48 89 4d 18          	mov    %rcx,0x18(%rbp)
 105e690:	48 89 55 20          	mov    %rdx,0x20(%rbp)
 105e694:	48 89 75 28          	mov    %rsi,0x28(%rbp)
 105e698:	e9 6e 04 00 00       	jmp    105eb0b <my.interpreter::execute+0x105b>
 105e69d:	48 8b 6c 24 18       	mov    0x18(%rsp),%rbp
 105e6a2:	48 c7 45 00 00 00 00 	movq   $0x0,0x0(%rbp)
 105e6a9:	00 
 105e6aa:	48 c7 45 08 01 00 00 	movq   $0x1,0x8(%rbp)
 105e6b1:	00 
 105e6b2:	4c 89 5d 18          	mov    %r11,0x18(%rbp)
 105e6b6:	4c 89 55 20          	mov    %r10,0x20(%rbp)
 105e6ba:	e9 48 04 00 00       	jmp    105eb07 <my.interpreter::execute+0x1057>
 105e6bf:	48 01 c2             	add    %rax,%rdx
 105e6c2:	4c 8b 62 08          	mov    0x8(%rdx),%r12
 105e6c6:	49 8b 44 24 08       	mov    0x8(%r12),%rax
 105e6cb:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105e6d0:	48 85 c0             	test   %rax,%rax
 105e6d3:	0f 84 f3 f4 ff ff    	je     105dbcc <my.interpreter::execute+0x11c>
 105e6d9:	31 ed                	xor    %ebp,%ebp
 105e6db:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105e6e2:	0f 1f 84 00 00 00 00 
 105e6e9:	00 
 105e6ea:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105e6f1:	0f 1f 84 00 00 00 00 
 105e6f8:	00 
 105e6f9:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
 105e700:	40 0f b6 c6          	movzbl %sil,%eax
 105e704:	48 8d bc 24 88 00 00 	lea    0x88(%rsp),%rdi
 105e70b:	00 
 105e70c:	4c 89 fe             	mov    %r15,%rsi
 105e70f:	48 89 da             	mov    %rbx,%rdx
 105e712:	4c 8b 04 24          	mov    (%rsp),%r8
 105e716:	4d 89 f1             	mov    %r14,%r9
 105e719:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e720:	41 ff 74 ec 20       	push   0x20(%r12,%rbp,8)
 105e725:	41 55                	push   %r13
 105e727:	50                   	push   %rax
 105e728:	41 52                	push   %r10
 105e72a:	ff b4 24 38 03 00 00 	push   0x338(%rsp)
 105e731:	e8 7a f3 ff ff       	call   105dab0 <my.interpreter::execute>
 105e736:	48 83 c4 30          	add    $0x30,%rsp
 105e73a:	48 8b 84 24 90 00 00 	mov    0x90(%rsp),%rax
 105e741:	00 
 105e742:	4c 8b 94 24 a0 00 00 	mov    0xa0(%rsp),%r10
 105e749:	00 
 105e74a:	0f b6 b4 24 a8 00 00 	movzbl 0xa8(%rsp),%esi
 105e751:	00 
 105e752:	4c 8b ac 24 b0 00 00 	mov    0xb0(%rsp),%r13
 105e759:	00 
 105e75a:	80 bc 24 88 00 00 00 	cmpb   $0x1,0x88(%rsp)
 105e761:	01 
 105e762:	0f 84 fc 05 00 00    	je     105ed64 <my.interpreter::execute+0x12b4>
 105e768:	3c 01                	cmp    $0x1,%al
 105e76a:	0f 84 b0 03 00 00    	je     105eb20 <my.interpreter::execute+0x1070>
 105e770:	48 ff c5             	inc    %rbp
 105e773:	48 39 6c 24 10       	cmp    %rbp,0x10(%rsp)
 105e778:	48 8b 4c 24 30       	mov    0x30(%rsp),%rcx
 105e77d:	75 81                	jne    105e700 <my.interpreter::execute+0xc50>
 105e77f:	e9 48 f4 ff ff       	jmp    105dbcc <my.interpreter::execute+0x11c>
 105e784:	48 39 d0             	cmp    %rdx,%rax
 105e787:	0f 83 72 08 00 00    	jae    105efff <my.interpreter::execute+0x154f>
 105e78d:	48 89 c7             	mov    %rax,%rdi
 105e790:	48 6b c7 38          	imul   $0x38,%rdi,%rax
 105e794:	83 7c 01 20 09       	cmpl   $0x9,0x20(%rcx,%rax,1)
 105e799:	0f 85 44 0a 00 00    	jne    105f1e3 <my.interpreter::execute+0x1733>
 105e79f:	48 01 c8             	add    %rcx,%rax
 105e7a2:	48 83 c0 20          	add    $0x20,%rax
 105e7a6:	48 8b 40 10          	mov    0x10(%rax),%rax
 105e7aa:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e7ae:	48 39 d6             	cmp    %rdx,%rsi
 105e7b1:	0f 83 6d 08 00 00    	jae    105f024 <my.interpreter::execute+0x1574>
 105e7b7:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e7bb:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105e7c2:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e7c6:	48 39 d6             	cmp    %rdx,%rsi
 105e7c9:	0f 83 77 08 00 00    	jae    105f046 <my.interpreter::execute+0x1596>
 105e7cf:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
 105e7d3:	c5 f8 11 45 00       	vmovups %xmm0,0x0(%rbp)
 105e7d8:	4c 89 5d 18          	mov    %r11,0x18(%rbp)
 105e7dc:	41 0f b6 c2          	movzbl %r10b,%eax
 105e7e0:	e9 1e 03 00 00       	jmp    105eb03 <my.interpreter::execute+0x1053>
 105e7e5:	31 db                	xor    %ebx,%ebx
 105e7e7:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105e7ee:	48 89 c6             	mov    %rax,%rsi
 105e7f1:	48 ff ce             	dec    %rsi
 105e7f4:	0f 80 d5 09 00 00    	jo     105f1cf <my.interpreter::execute+0x171f>
 105e7fa:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e7fe:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e802:	48 39 d6             	cmp    %rdx,%rsi
 105e805:	0f 83 ad 07 00 00    	jae    105efb8 <my.interpreter::execute+0x1508>
 105e80b:	48 89 f1             	mov    %rsi,%rcx
 105e80e:	4c 89 44 24 28       	mov    %r8,0x28(%rsp)
 105e813:	48 c1 e1 04          	shl    $0x4,%rcx
 105e817:	80 7c 08 20 03       	cmpb   $0x3,0x20(%rax,%rcx,1)
 105e81c:	0f 85 82 03 00 00    	jne    105eba4 <my.interpreter::execute+0x10f4>
 105e822:	4c 8b 7c 08 28       	mov    0x28(%rax,%rcx,1),%r15
 105e827:	49 8b 06             	mov    (%r14),%rax
 105e82a:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e82e:	4c 89 f9             	mov    %r15,%rcx
 105e831:	49 39 d7             	cmp    %rdx,%r15
 105e834:	0f 83 a0 07 00 00    	jae    105efda <my.interpreter::execute+0x152a>
 105e83a:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 105e83e:	83 7c 08 20 06       	cmpl   $0x6,0x20(%rax,%rcx,1)
 105e843:	0f 85 5b 03 00 00    	jne    105eba4 <my.interpreter::execute+0x10f4>
 105e849:	48 89 7c 24 48       	mov    %rdi,0x48(%rsp)
 105e84e:	48 8d bc 24 80 00 00 	lea    0x80(%rsp),%rdi
 105e855:	00 
 105e856:	4c 89 f6             	mov    %r14,%rsi
 105e859:	48 8b 54 24 20       	mov    0x20(%rsp),%rdx
 105e85e:	e8 cd 4a 00 00       	call   1063330 <my.heap::allocate_class>
 105e863:	48 8b 8c 24 80 00 00 	mov    0x80(%rsp),%rcx
 105e86a:	00 
 105e86b:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e86f:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105e876:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e87a:	48 39 d6             	cmp    %rdx,%rsi
 105e87d:	0f 83 4b 06 00 00    	jae    105eece <my.interpreter::execute+0x141e>
 105e883:	48 89 f7             	mov    %rsi,%rdi
 105e886:	48 c1 e7 04          	shl    $0x4,%rdi
 105e88a:	48 c7 44 38 20 03 00 	movq   $0x3,0x20(%rax,%rdi,1)
 105e891:	00 00 
 105e893:	48 89 4c 38 28       	mov    %rcx,0x28(%rax,%rdi,1)
 105e898:	49 89 46 78          	mov    %rax,0x78(%r14)
 105e89c:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105e8a3:	48 89 f2             	mov    %rsi,%rdx
 105e8a6:	48 ff c2             	inc    %rdx
 105e8a9:	0f 80 89 08 00 00    	jo     105f138 <my.interpreter::execute+0x1688>
 105e8af:	48 8d 0c 38          	lea    (%rax,%rdi,1),%rcx
 105e8b3:	48 83 c1 20          	add    $0x20,%rcx
 105e8b7:	49 89 96 80 00 00 00 	mov    %rdx,0x80(%r14)
 105e8be:	0f b6 01             	movzbl (%rcx),%eax
 105e8c1:	83 f8 03             	cmp    $0x3,%eax
 105e8c4:	0f 85 be 07 00 00    	jne    105f088 <my.interpreter::execute+0x15d8>
 105e8ca:	48 8b 71 08          	mov    0x8(%rcx),%rsi
 105e8ce:	49 83 ff ff          	cmp    $0xffffffffffffffff,%r15
 105e8d2:	48 89 6c 24 18       	mov    %rbp,0x18(%rsp)
 105e8d7:	4c 89 6c 24 58       	mov    %r13,0x58(%rsp)
 105e8dc:	4c 89 7c 24 50       	mov    %r15,0x50(%rsp)
 105e8e1:	48 89 34 24          	mov    %rsi,(%rsp)
 105e8e5:	74 76                	je     105e95d <my.interpreter::execute+0xead>
 105e8e7:	4c 89 f7             	mov    %r14,%rdi
 105e8ea:	4c 89 fa             	mov    %r15,%rdx
 105e8ed:	e8 fe be 00 00       	call   106a7f0 <my.heap::inherit_class_methods>
 105e8f2:	49 8b 96 a8 00 00 00 	mov    0xa8(%r14),%rdx
 105e8f9:	48 8d 7c 24 78       	lea    0x78(%rsp),%rdi
 105e8fe:	b9 01 00 00 00       	mov    $0x1,%ecx
 105e903:	4c 89 f6             	mov    %r14,%rsi
 105e906:	e8 e5 da 00 00       	call   106c3f0 <my.interpreter::new_env>
 105e90b:	4c 8b 64 24 78       	mov    0x78(%rsp),%r12
 105e910:	4c 89 f7             	mov    %r14,%rdi
 105e913:	4c 89 e6             	mov    %r12,%rsi
 105e916:	31 d2                	xor    %edx,%edx
 105e918:	b9 03 00 00 00       	mov    $0x3,%ecx
 105e91d:	4d 89 f8             	mov    %r15,%r8
 105e920:	e8 5b dc 00 00       	call   106c580 <my.heap::set_env_slot>
 105e925:	4d 8b be a8 00 00 00 	mov    0xa8(%r14),%r15
 105e92c:	49 8b 86 b0 00 00 00 	mov    0xb0(%r14),%rax
 105e933:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105e937:	48 3b 48 10          	cmp    0x10(%rax),%rcx
 105e93b:	0f 83 d1 05 00 00    	jae    105ef12 <my.interpreter::execute+0x1462>
 105e941:	4c 89 7c c8 20       	mov    %r15,0x20(%rax,%rcx,8)
 105e946:	48 ff c1             	inc    %rcx
 105e949:	48 89 48 08          	mov    %rcx,0x8(%rax)
 105e94d:	49 89 86 b0 00 00 00 	mov    %rax,0xb0(%r14)
 105e954:	4d 89 a6 a8 00 00 00 	mov    %r12,0xa8(%r14)
 105e95b:	eb 07                	jmp    105e964 <my.interpreter::execute+0xeb4>
 105e95d:	4d 8b a6 a8 00 00 00 	mov    0xa8(%r14),%r12
 105e964:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105e969:	4c 8b 68 08          	mov    0x8(%rax),%r13
 105e96d:	4d 85 ed             	test   %r13,%r13
 105e970:	48 8b 5c 24 30       	mov    0x30(%rsp),%rbx
 105e975:	0f 84 d2 00 00 00    	je     105ea4d <my.interpreter::execute+0xf9d>
 105e97b:	31 ed                	xor    %ebp,%ebp
 105e97d:	0f 1f 00             	nopl   (%rax)
 105e980:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105e985:	48 8b 74 e8 20       	mov    0x20(%rax,%rbp,8),%rsi
 105e98a:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 105e98e:	48 89 f0             	mov    %rsi,%rax
 105e991:	48 39 d6             	cmp    %rdx,%rsi
 105e994:	0f 83 91 00 00 00    	jae    105ea2b <my.interpreter::execute+0xf7b>
 105e99a:	48 8d 04 80          	lea    (%rax,%rax,4),%rax
 105e99e:	48 c1 e0 04          	shl    $0x4,%rax
 105e9a2:	4c 8b 7c 03 48       	mov    0x48(%rbx,%rax,1),%r15
 105e9a7:	4d 3b 7e 40          	cmp    0x40(%r14),%r15
 105e9ab:	48 c7 84 24 88 00 00 	movq   $0xa,0x88(%rsp)
 105e9b2:	00 0a 00 00 00 
 105e9b7:	48 89 b4 24 90 00 00 	mov    %rsi,0x90(%rsp)
 105e9be:	00 
 105e9bf:	4c 89 bc 24 98 00 00 	mov    %r15,0x98(%rsp)
 105e9c6:	00 
 105e9c7:	4c 89 a4 24 a0 00 00 	mov    %r12,0xa0(%rsp)
 105e9ce:	00 
 105e9cf:	0f 94 84 24 a8 00 00 	sete   0xa8(%rsp)
 105e9d6:	00 
 105e9d7:	48 8d 7c 24 70       	lea    0x70(%rsp),%rdi
 105e9dc:	4c 89 f6             	mov    %r14,%rsi
 105e9df:	48 8d 94 24 88 00 00 	lea    0x88(%rsp),%rdx
 105e9e6:	00 
 105e9e7:	e8 64 b7 ff ff       	call   105a150 <my.heap::allocate>
 105e9ec:	4c 8b 64 24 70       	mov    0x70(%rsp),%r12
 105e9f1:	4c 89 f7             	mov    %r14,%rdi
 105e9f4:	4c 89 fe             	mov    %r15,%rsi
 105e9f7:	e8 24 b1 00 00       	call   1069b20 <my.heap::string_hash>
 105e9fc:	4c 89 f7             	mov    %r14,%rdi
 105e9ff:	48 8b 34 24          	mov    (%rsp),%rsi
 105ea03:	4c 89 fa             	mov    %r15,%rdx
 105ea06:	89 c1                	mov    %eax,%ecx
 105ea08:	41 b8 03 00 00 00    	mov    $0x3,%r8d
 105ea0e:	4d 89 e1             	mov    %r12,%r9
 105ea11:	e8 ba bf 00 00       	call   106a9d0 <my.heap::set_class_method>
 105ea16:	4d 8b a6 a8 00 00 00 	mov    0xa8(%r14),%r12
 105ea1d:	48 ff c5             	inc    %rbp
 105ea20:	49 39 ed             	cmp    %rbp,%r13
 105ea23:	0f 85 57 ff ff ff    	jne    105e980 <my.interpreter::execute+0xed0>
 105ea29:	eb 22                	jmp    105ea4d <my.interpreter::execute+0xf9d>
 105ea2b:	48 89 f0             	mov    %rsi,%rax
 105ea2e:	48 c1 f8 3f          	sar    $0x3f,%rax
 105ea32:	48 21 d0             	and    %rdx,%rax
 105ea35:	48 01 f0             	add    %rsi,%rax
 105ea38:	48 39 d0             	cmp    %rdx,%rax
 105ea3b:	0f 82 59 ff ff ff    	jb     105e99a <my.interpreter::execute+0xeea>
 105ea41:	48 8d 3d 58 33 02 00 	lea    0x23358(%rip),%rdi        # 1081da0 <core_durable_error.verbs+0x2e50>
 105ea48:	e8 33 5a fc ff       	call   1024480 <myl_core_trap>
 105ea4d:	48 8b 5c 24 50       	mov    0x50(%rsp),%rbx
 105ea52:	48 83 fb ff          	cmp    $0xffffffffffffffff,%rbx
 105ea56:	48 8b 6c 24 18       	mov    0x18(%rsp),%rbp
 105ea5b:	4c 8b 6c 24 58       	mov    0x58(%rsp),%r13
 105ea60:	74 27                	je     105ea89 <my.interpreter::execute+0xfd9>
 105ea62:	49 8b 86 b0 00 00 00 	mov    0xb0(%r14),%rax
 105ea69:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105ea6d:	48 85 c9             	test   %rcx,%rcx
 105ea70:	0f 84 13 07 00 00    	je     105f189 <my.interpreter::execute+0x16d9>
 105ea76:	48 8b 54 c8 18       	mov    0x18(%rax,%rcx,8),%rdx
 105ea7b:	48 ff c9             	dec    %rcx
 105ea7e:	48 89 48 08          	mov    %rcx,0x8(%rax)
 105ea82:	49 89 96 a8 00 00 00 	mov    %rdx,0xa8(%r14)
 105ea89:	4c 89 f7             	mov    %r14,%rdi
 105ea8c:	48 8b 74 24 20       	mov    0x20(%rsp),%rsi
 105ea91:	48 8b 54 24 60       	mov    0x60(%rsp),%rdx
 105ea96:	e8 35 8f 00 00       	call   10679d0 <my.interpreter::define>
 105ea9b:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105eaa2:	48 89 c6             	mov    %rax,%rsi
 105eaa5:	48 ff ce             	dec    %rsi
 105eaa8:	0f 80 b3 06 00 00    	jo     105f161 <my.interpreter::execute+0x16b1>
 105eaae:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105eab5:	49 8b 46 78          	mov    0x78(%r14),%rax
 105eab9:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105eabd:	48 39 d6             	cmp    %rdx,%rsi
 105eac0:	4c 8b 5c 24 48       	mov    0x48(%rsp),%r11
 105eac5:	48 8b 7c 24 28       	mov    0x28(%rsp),%rdi
 105eaca:	0f 83 20 04 00 00    	jae    105eef0 <my.interpreter::execute+0x1440>
 105ead0:	48 83 fb ff          	cmp    $0xffffffffffffffff,%rbx
 105ead4:	74 1c                	je     105eaf2 <my.interpreter::execute+0x1042>
 105ead6:	48 89 f0             	mov    %rsi,%rax
 105ead9:	48 ff c8             	dec    %rax
 105eadc:	0f 80 b7 06 00 00    	jo     105f199 <my.interpreter::execute+0x16e9>
 105eae2:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 105eae9:	48 39 d0             	cmp    %rdx,%rax
 105eaec:	0f 83 36 04 00 00    	jae    105ef28 <my.interpreter::execute+0x1478>
 105eaf2:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
 105eaf6:	c5 f8 11 45 00       	vmovups %xmm0,0x0(%rbp)
 105eafb:	4c 89 5d 18          	mov    %r11,0x18(%rbp)
 105eaff:	40 0f b6 c7          	movzbl %dil,%eax
 105eb03:	48 89 45 20          	mov    %rax,0x20(%rbp)
 105eb07:	4c 89 6d 28          	mov    %r13,0x28(%rbp)
 105eb0b:	48 89 e8             	mov    %rbp,%rax
 105eb0e:	48 81 c4 d8 02 00 00 	add    $0x2d8,%rsp
 105eb15:	5b                   	pop    %rbx
 105eb16:	41 5c                	pop    %r12
 105eb18:	41 5d                	pop    %r13
 105eb1a:	41 5e                	pop    %r14
 105eb1c:	41 5f                	pop    %r15
 105eb1e:	5d                   	pop    %rbp
 105eb1f:	c3                   	ret
 105eb20:	48 89 f3             	mov    %rsi,%rbx
 105eb23:	b8 01 00 00 00       	mov    $0x1,%eax
 105eb28:	31 f6                	xor    %esi,%esi
 105eb2a:	31 d2                	xor    %edx,%edx
 105eb2c:	e9 a8 f0 ff ff       	jmp    105dbd9 <my.interpreter::execute+0x129>
 105eb31:	c5 f8 10 84 24 18 02 	vmovups 0x218(%rsp),%xmm0
 105eb38:	00 00 
 105eb3a:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105eb3f:	48 8d 3d 4a 15 02 00 	lea    0x2154a(%rip),%rdi        # 1080090 <core_durable_error.verbs+0x1140>
 105eb46:	4c 89 d8             	mov    %r11,%rax
 105eb49:	e8 32 7d ff ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 105eb4e:	48 c7 45 00 01 00 00 	movq   $0x1,0x0(%rbp)
 105eb55:	00 
 105eb56:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 105eb5b:	c5 f8 11 45 08       	vmovups %xmm0,0x8(%rbp)
 105eb60:	48 89 45 18          	mov    %rax,0x18(%rbp)
 105eb64:	e9 4d fb ff ff       	jmp    105e6b6 <my.interpreter::execute+0xc06>
 105eb69:	41 0f b6 c7          	movzbl %r15b,%eax
 105eb6d:	c5 f8 10 84 24 88 01 	vmovups 0x188(%rsp),%xmm0
 105eb74:	00 00 
 105eb76:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105eb7b:	48 8d 3d 9e 15 02 00 	lea    0x2159e(%rip),%rdi        # 1080120 <core_durable_error.verbs+0x11d0>
 105eb82:	e9 01 01 00 00       	jmp    105ec88 <my.interpreter::execute+0x11d8>
 105eb87:	48 8d 3d b2 31 02 00 	lea    0x231b2(%rip),%rdi        # 1081d40 <core_durable_error.verbs+0x2df0>
 105eb8e:	e8 ed 7c ff ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 105eb93:	48 8d 3d d6 13 02 00 	lea    0x213d6(%rip),%rdi        # 107ff70 <core_durable_error.verbs+0x1020>
 105eb9a:	e8 e1 7c ff ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 105eb9f:	e9 6a f0 ff ff       	jmp    105dc0e <my.interpreter::execute+0x15e>
 105eba4:	49 89 fe             	mov    %rdi,%r14
 105eba7:	48 8d 3d f2 36 fb ff 	lea    -0x4c90e(%rip),%rdi        # 10122a0 <core_number_pairs+0xb040>
 105ebae:	e8 cd 53 fc ff       	call   1023f80 <myl_core_owned_octets_copy>
 105ebb3:	48 8d 3d 16 5f 02 00 	lea    0x25f16(%rip),%rdi        # 1084ad0 <core_durable_error.verbs+0x5b80>
 105ebba:	e8 81 7c ff ff       	call   1056840 <myl_core_err_trace_origin_preserve_most>
 105ebbf:	4c 8b 44 24 28       	mov    0x28(%rsp),%r8
 105ebc4:	e9 fe 00 00 00       	jmp    105ecc7 <my.interpreter::execute+0x1217>
 105ebc9:	40 0f b6 c7          	movzbl %dil,%eax
 105ebcd:	c5 f8 10 84 24 48 02 	vmovups 0x248(%rsp),%xmm0
 105ebd4:	00 00 
 105ebd6:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105ebdb:	48 8d 3d 4e 14 02 00 	lea    0x2144e(%rip),%rdi        # 1080030 <core_durable_error.verbs+0x10e0>
 105ebe2:	4c 89 d9             	mov    %r11,%rcx
 105ebe5:	e8 96 7c ff ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 105ebea:	48 c7 45 00 01 00 00 	movq   $0x1,0x0(%rbp)
 105ebf1:	00 
 105ebf2:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 105ebf7:	c5 f8 11 45 08       	vmovups %xmm0,0x8(%rbp)
 105ebfc:	48 89 4d 18          	mov    %rcx,0x18(%rbp)
 105ec00:	e9 fe fe ff ff       	jmp    105eb03 <my.interpreter::execute+0x1053>
 105ec05:	c5 f8 10 84 24 28 01 	vmovups 0x128(%rsp),%xmm0
 105ec0c:	00 00 
 105ec0e:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105ec13:	48 8d 3d 96 15 02 00 	lea    0x21596(%rip),%rdi        # 10801b0 <core_durable_error.verbs+0x1260>
 105ec1a:	e8 61 7c ff ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 105ec1f:	48 8b 44 24 18       	mov    0x18(%rsp),%rax
 105ec24:	48 c7 00 01 00 00 00 	movq   $0x1,(%rax)
 105ec2b:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 105ec30:	c5 f8 11 40 08       	vmovups %xmm0,0x8(%rax)
 105ec35:	e9 c2 f9 ff ff       	jmp    105e5fc <my.interpreter::execute+0xb4c>
 105ec3a:	48 8b 8c 24 00 01 00 	mov    0x100(%rsp),%rcx
 105ec41:	00 
 105ec42:	48 8d 3d 97 15 02 00 	lea    0x21597(%rip),%rdi        # 10801e0 <core_durable_error.verbs+0x1290>
 105ec49:	4c 89 da             	mov    %r11,%rdx
 105ec4c:	e8 2f 7c ff ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 105ec51:	48 8b 6c 24 18       	mov    0x18(%rsp),%rbp
 105ec56:	48 c7 45 00 01 00 00 	movq   $0x1,0x0(%rbp)
 105ec5d:	00 
 105ec5e:	48 89 45 08          	mov    %rax,0x8(%rbp)
 105ec62:	48 89 4d 10          	mov    %rcx,0x10(%rbp)
 105ec66:	48 89 55 18          	mov    %rdx,0x18(%rbp)
 105ec6a:	e9 47 fa ff ff       	jmp    105e6b6 <my.interpreter::execute+0xc06>
 105ec6f:	41 0f b6 c7          	movzbl %r15b,%eax
 105ec73:	c5 f8 10 84 24 58 01 	vmovups 0x158(%rsp),%xmm0
 105ec7a:	00 00 
 105ec7c:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105ec81:	48 8d 3d f8 14 02 00 	lea    0x214f8(%rip),%rdi        # 1080180 <core_durable_error.verbs+0x1230>
 105ec88:	e8 f3 7b ff ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 105ec8d:	48 c7 45 00 01 00 00 	movq   $0x1,0x0(%rbp)
 105ec94:	00 
 105ec95:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 105ec9a:	c5 f8 11 45 08       	vmovups %xmm0,0x8(%rbp)
 105ec9f:	48 89 5d 18          	mov    %rbx,0x18(%rbp)
 105eca3:	e9 5b fe ff ff       	jmp    105eb03 <my.interpreter::execute+0x1053>
 105eca8:	49 89 fe             	mov    %rdi,%r14
 105ecab:	48 8b 84 24 c8 00 00 	mov    0xc8(%rsp),%rax
 105ecb2:	00 
 105ecb3:	48 8b 9c 24 d0 00 00 	mov    0xd0(%rsp),%rbx
 105ecba:	00 
 105ecbb:	48 8d 3d ae 5d 02 00 	lea    0x25dae(%rip),%rdi        # 1084a70 <core_durable_error.verbs+0x5b20>
 105ecc2:	e8 b9 7b ff ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 105ecc7:	48 8d 3d a2 30 02 00 	lea    0x230a2(%rip),%rdi        # 1081d70 <core_durable_error.verbs+0x2e20>
 105ecce:	e8 ad 7b ff ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 105ecd3:	48 8d 3d c6 12 02 00 	lea    0x212c6(%rip),%rdi        # 107ffa0 <core_durable_error.verbs+0x1050>
 105ecda:	e8 a1 7b ff ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 105ecdf:	48 c7 45 00 01 00 00 	movq   $0x1,0x0(%rbp)
 105ece6:	00 
 105ece7:	48 89 45 08          	mov    %rax,0x8(%rbp)
 105eceb:	48 89 5d 10          	mov    %rbx,0x10(%rbp)
 105ecef:	4c 89 75 18          	mov    %r14,0x18(%rbp)
 105ecf3:	4c 89 45 20          	mov    %r8,0x20(%rbp)
 105ecf7:	e9 0b fe ff ff       	jmp    105eb07 <my.interpreter::execute+0x1057>
 105ecfc:	c5 f8 10 84 24 b0 02 	vmovups 0x2b0(%rsp),%xmm0
 105ed03:	00 00 
 105ed05:	c5 f8 29 44 24 30    	vmovaps %xmm0,0x30(%rsp)
 105ed0b:	c5 f8 10 84 24 c8 02 	vmovups 0x2c8(%rsp),%xmm0
 105ed12:	00 00 
 105ed14:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105ed19:	48 8d 3d 30 14 02 00 	lea    0x21430(%rip),%rdi        # 1080150 <core_durable_error.verbs+0x1200>
 105ed20:	4c 89 d8             	mov    %r11,%rax
 105ed23:	e8 58 7b ff ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 105ed28:	48 c7 45 00 01 00 00 	movq   $0x1,0x0(%rbp)
 105ed2f:	00 
 105ed30:	c5 f8 28 44 24 30    	vmovaps 0x30(%rsp),%xmm0
 105ed36:	c5 f8 11 45 08       	vmovups %xmm0,0x8(%rbp)
 105ed3b:	48 89 45 18          	mov    %rax,0x18(%rbp)
 105ed3f:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 105ed44:	e9 94 f8 ff ff       	jmp    105e5dd <my.interpreter::execute+0xb2d>
 105ed49:	48 8d 3d a0 13 02 00 	lea    0x213a0(%rip),%rdi        # 10800f0 <core_durable_error.verbs+0x11a0>
 105ed50:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105ed55:	e8 26 7b ff ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 105ed5a:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 105ed5f:	e9 1f f9 ff ff       	jmp    105e683 <my.interpreter::execute+0xbd3>
 105ed64:	48 89 f3             	mov    %rsi,%rbx
 105ed67:	48 8b 8c 24 98 00 00 	mov    0x98(%rsp),%rcx
 105ed6e:	00 
 105ed6f:	48 8d 3d 9a 5c 02 00 	lea    0x25c9a(%rip),%rdi        # 1084a10 <core_durable_error.verbs+0x5ac0>
 105ed76:	e8 05 7b ff ff       	call   1056880 <myl_core_err_trace_append_preserve_most>
 105ed7b:	ba 01 00 00 00       	mov    $0x1,%edx
 105ed80:	40 b6 01             	mov    $0x1,%sil
 105ed83:	e9 51 ee ff ff       	jmp    105dbd9 <my.interpreter::execute+0x129>
 105ed88:	4c 89 e0             	mov    %r12,%rax
 105ed8b:	48 c1 f8 3f          	sar    $0x3f,%rax
 105ed8f:	48 21 d0             	and    %rdx,%rax
 105ed92:	4c 01 e0             	add    %r12,%rax
 105ed95:	48 39 d0             	cmp    %rdx,%rax
 105ed98:	0f 82 4b ed ff ff    	jb     105dae9 <my.interpreter::execute+0x39>
 105ed9e:	48 8d 3d 9b 11 02 00 	lea    0x2119b(%rip),%rdi        # 107ff40 <core_durable_error.verbs+0xff0>
 105eda5:	4c 89 e6             	mov    %r12,%rsi
 105eda8:	e8 d3 56 fc ff       	call   1024480 <myl_core_trap>
 105edad:	48 89 c1             	mov    %rax,%rcx
 105edb0:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105edb4:	48 21 d1             	and    %rdx,%rcx
 105edb7:	48 01 c1             	add    %rax,%rcx
 105edba:	48 39 d1             	cmp    %rdx,%rcx
 105edbd:	0f 82 c2 ef ff ff    	jb     105dd85 <my.interpreter::execute+0x2d5>
 105edc3:	48 8d 3d 06 12 02 00 	lea    0x21206(%rip),%rdi        # 107ffd0 <core_durable_error.verbs+0x1080>
 105edca:	48 89 c6             	mov    %rax,%rsi
 105edcd:	e8 ae 56 fc ff       	call   1024480 <myl_core_trap>
 105edd2:	48 89 f0             	mov    %rsi,%rax
 105edd5:	48 c1 f8 3f          	sar    $0x3f,%rax
 105edd9:	48 21 d0             	and    %rdx,%rax
 105eddc:	48 01 f0             	add    %rsi,%rax
 105eddf:	48 39 d0             	cmp    %rdx,%rax
 105ede2:	0f 82 78 f0 ff ff    	jb     105de60 <my.interpreter::execute+0x3b0>
 105ede8:	48 8d 3d 71 12 02 00 	lea    0x21271(%rip),%rdi        # 1080060 <core_durable_error.verbs+0x1110>
 105edef:	e8 8c 56 fc ff       	call   1024480 <myl_core_trap>
 105edf4:	48 89 74 24 20       	mov    %rsi,0x20(%rsp)
 105edf9:	be 08 00 00 00       	mov    $0x8,%esi
 105edfe:	48 89 c7             	mov    %rax,%rdi
 105ee01:	48 89 54 24 10       	mov    %rdx,0x10(%rsp)
 105ee06:	e8 f5 3b fc ff       	call   1022a00 <myl_core_list_grow>
 105ee0b:	48 8b 74 24 20       	mov    0x20(%rsp),%rsi
 105ee10:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 105ee15:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105ee19:	e9 55 ed ff ff       	jmp    105db73 <my.interpreter::execute+0xc3>
 105ee1e:	4c 89 e0             	mov    %r12,%rax
 105ee21:	48 c1 f8 3f          	sar    $0x3f,%rax
 105ee25:	48 21 d0             	and    %rdx,%rax
 105ee28:	4c 01 e0             	add    %r12,%rax
 105ee2b:	48 39 d0             	cmp    %rdx,%rax
 105ee2e:	0f 82 7e ed ff ff    	jb     105dbb2 <my.interpreter::execute+0x102>
 105ee34:	48 8d 3d a5 5b 02 00 	lea    0x25ba5(%rip),%rdi        # 10849e0 <core_durable_error.verbs+0x5a90>
 105ee3b:	4c 89 e6             	mov    %r12,%rsi
 105ee3e:	e8 3d 56 fc ff       	call   1024480 <myl_core_trap>
 105ee43:	48 89 f7             	mov    %rsi,%rdi
 105ee46:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105ee4a:	48 21 d7             	and    %rdx,%rdi
 105ee4d:	48 01 f7             	add    %rsi,%rdi
 105ee50:	48 39 d7             	cmp    %rdx,%rdi
 105ee53:	0f 82 81 f0 ff ff    	jb     105deda <my.interpreter::execute+0x42a>
 105ee59:	48 8d 3d 10 14 02 00 	lea    0x21410(%rip),%rdi        # 1080270 <core_durable_error.verbs+0x1320>
 105ee60:	e8 1b 56 fc ff       	call   1024480 <myl_core_trap>
 105ee65:	48 89 c6             	mov    %rax,%rsi
 105ee68:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105ee6c:	48 21 d6             	and    %rdx,%rsi
 105ee6f:	48 01 c6             	add    %rax,%rsi
 105ee72:	48 39 d6             	cmp    %rdx,%rsi
 105ee75:	0f 82 44 f7 ff ff    	jb     105e5bf <my.interpreter::execute+0xb0f>
 105ee7b:	48 8d 3d 3e 15 02 00 	lea    0x2153e(%rip),%rdi        # 10803c0 <core_durable_error.verbs+0x1470>
 105ee82:	48 89 c6             	mov    %rax,%rsi
 105ee85:	e8 f6 55 fc ff       	call   1024480 <myl_core_trap>
 105ee8a:	49 89 f0             	mov    %rsi,%r8
 105ee8d:	49 c1 f8 3f          	sar    $0x3f,%r8
 105ee91:	49 21 d0             	and    %rdx,%r8
 105ee94:	49 01 f0             	add    %rsi,%r8
 105ee97:	49 39 d0             	cmp    %rdx,%r8
 105ee9a:	0f 82 34 ee ff ff    	jb     105dcd4 <my.interpreter::execute+0x224>
 105eea0:	48 8d 3d 59 14 02 00 	lea    0x21459(%rip),%rdi        # 1080300 <core_durable_error.verbs+0x13b0>
 105eea7:	e8 d4 55 fc ff       	call   1024480 <myl_core_trap>
 105eeac:	48 89 f7             	mov    %rsi,%rdi
 105eeaf:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105eeb3:	48 21 d7             	and    %rdx,%rdi
 105eeb6:	48 01 f7             	add    %rsi,%rdi
 105eeb9:	48 39 d7             	cmp    %rdx,%rdi
 105eebc:	0f 82 da f2 ff ff    	jb     105e19c <my.interpreter::execute+0x6ec>
 105eec2:	48 8d 3d 97 14 02 00 	lea    0x21497(%rip),%rdi        # 1080360 <core_durable_error.verbs+0x1410>
 105eec9:	e8 b2 55 fc ff       	call   1024480 <myl_core_trap>
 105eece:	48 89 f7             	mov    %rsi,%rdi
 105eed1:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105eed5:	48 21 d7             	and    %rdx,%rdi
 105eed8:	48 01 f7             	add    %rsi,%rdi
 105eedb:	48 39 d7             	cmp    %rdx,%rdi
 105eede:	0f 82 a2 f9 ff ff    	jb     105e886 <my.interpreter::execute+0xdd6>
 105eee4:	48 8d 3d e5 2e 02 00 	lea    0x22ee5(%rip),%rdi        # 1081dd0 <core_durable_error.verbs+0x2e80>
 105eeeb:	e8 90 55 fc ff       	call   1024480 <myl_core_trap>
 105eef0:	48 89 f0             	mov    %rsi,%rax
 105eef3:	48 c1 f8 3f          	sar    $0x3f,%rax
 105eef7:	48 21 d0             	and    %rdx,%rax
 105eefa:	48 01 f0             	add    %rsi,%rax
 105eefd:	48 39 d0             	cmp    %rdx,%rax
 105ef00:	0f 82 ca fb ff ff    	jb     105ead0 <my.interpreter::execute+0x1020>
 105ef06:	48 8d 3d 53 2f 02 00 	lea    0x22f53(%rip),%rdi        # 1081e60 <core_durable_error.verbs+0x2f10>
 105ef0d:	e8 6e 55 fc ff       	call   1024480 <myl_core_trap>
 105ef12:	be 08 00 00 00       	mov    $0x8,%esi
 105ef17:	48 89 c7             	mov    %rax,%rdi
 105ef1a:	e8 e1 3a fc ff       	call   1022a00 <myl_core_list_grow>
 105ef1f:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105ef23:	e9 19 fa ff ff       	jmp    105e941 <my.interpreter::execute+0xe91>
 105ef28:	48 89 c1             	mov    %rax,%rcx
 105ef2b:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105ef2f:	48 21 d1             	and    %rdx,%rcx
 105ef32:	48 01 c1             	add    %rax,%rcx
 105ef35:	48 39 d1             	cmp    %rdx,%rcx
 105ef38:	0f 82 b4 fb ff ff    	jb     105eaf2 <my.interpreter::execute+0x1042>
 105ef3e:	48 8d 3d 7b 2f 02 00 	lea    0x22f7b(%rip),%rdi        # 1081ec0 <core_durable_error.verbs+0x2f70>
 105ef45:	48 89 c6             	mov    %rax,%rsi
 105ef48:	e8 33 55 fc ff       	call   1024480 <myl_core_trap>
 105ef4d:	48 89 f1             	mov    %rsi,%rcx
 105ef50:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105ef54:	48 21 d1             	and    %rdx,%rcx
 105ef57:	48 01 f1             	add    %rsi,%rcx
 105ef5a:	48 39 d1             	cmp    %rdx,%rcx
 105ef5d:	0f 82 4e f5 ff ff    	jb     105e4b1 <my.interpreter::execute+0xa01>
 105ef63:	48 8d 3d 46 15 02 00 	lea    0x21546(%rip),%rdi        # 10804b0 <core_durable_error.verbs+0x1560>
 105ef6a:	e8 11 55 fc ff       	call   1024480 <myl_core_trap>
 105ef6f:	48 89 f1             	mov    %rsi,%rcx
 105ef72:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105ef76:	48 21 d1             	and    %rdx,%rcx
 105ef79:	48 01 f1             	add    %rsi,%rcx
 105ef7c:	48 39 d1             	cmp    %rdx,%rcx
 105ef7f:	0f 82 e8 f5 ff ff    	jb     105e56d <my.interpreter::execute+0xabd>
 105ef85:	48 8d 3d 64 14 02 00 	lea    0x21464(%rip),%rdi        # 10803f0 <core_durable_error.verbs+0x14a0>
 105ef8c:	e8 ef 54 fc ff       	call   1024480 <myl_core_trap>
 105ef91:	48 89 d8             	mov    %rbx,%rax
 105ef94:	48 c1 f8 3f          	sar    $0x3f,%rax
 105ef98:	48 21 d0             	and    %rdx,%rax
 105ef9b:	48 01 d8             	add    %rbx,%rax
 105ef9e:	48 39 d0             	cmp    %rdx,%rax
 105efa1:	0f 82 4f f1 ff ff    	jb     105e0f6 <my.interpreter::execute+0x646>
 105efa7:	48 8d 3d f2 5a 02 00 	lea    0x25af2(%rip),%rdi        # 1084aa0 <core_durable_error.verbs+0x5b50>
 105efae:	48 8b 74 24 28       	mov    0x28(%rsp),%rsi
 105efb3:	e8 c8 54 fc ff       	call   1024480 <myl_core_trap>
 105efb8:	48 89 f1             	mov    %rsi,%rcx
 105efbb:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105efbf:	48 21 d1             	and    %rdx,%rcx
 105efc2:	48 01 f1             	add    %rsi,%rcx
 105efc5:	48 39 d1             	cmp    %rdx,%rcx
 105efc8:	0f 82 40 f8 ff ff    	jb     105e80e <my.interpreter::execute+0xd5e>
 105efce:	48 8d 3d 5b 5b 02 00 	lea    0x25b5b(%rip),%rdi        # 1084b30 <core_durable_error.verbs+0x5be0>
 105efd5:	e8 a6 54 fc ff       	call   1024480 <myl_core_trap>
 105efda:	4c 89 f9             	mov    %r15,%rcx
 105efdd:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105efe1:	48 21 d1             	and    %rdx,%rcx
 105efe4:	4c 01 f9             	add    %r15,%rcx
 105efe7:	48 39 d1             	cmp    %rdx,%rcx
 105efea:	0f 82 4a f8 ff ff    	jb     105e83a <my.interpreter::execute+0xd8a>
 105eff0:	48 8d 3d 49 7b 02 00 	lea    0x27b49(%rip),%rdi        # 1086b40 <core_durable_error.verbs+0x7bf0>
 105eff7:	4c 89 fe             	mov    %r15,%rsi
 105effa:	e8 81 54 fc ff       	call   1024480 <myl_core_trap>
 105efff:	48 89 c7             	mov    %rax,%rdi
 105f002:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105f006:	48 21 d7             	and    %rdx,%rdi
 105f009:	48 01 c7             	add    %rax,%rdi
 105f00c:	48 39 d7             	cmp    %rdx,%rdi
 105f00f:	0f 82 7b f7 ff ff    	jb     105e790 <my.interpreter::execute+0xce0>
 105f015:	48 8d 3d d4 2e 02 00 	lea    0x22ed4(%rip),%rdi        # 1081ef0 <core_durable_error.verbs+0x2fa0>
 105f01c:	48 89 c6             	mov    %rax,%rsi
 105f01f:	e8 5c 54 fc ff       	call   1024480 <myl_core_trap>
 105f024:	48 89 f0             	mov    %rsi,%rax
 105f027:	48 c1 f8 3f          	sar    $0x3f,%rax
 105f02b:	48 21 d0             	and    %rdx,%rax
 105f02e:	48 01 f0             	add    %rsi,%rax
 105f031:	48 39 d0             	cmp    %rdx,%rax
 105f034:	0f 82 7d f7 ff ff    	jb     105e7b7 <my.interpreter::execute+0xd07>
 105f03a:	48 8d 3d 0f 2f 02 00 	lea    0x22f0f(%rip),%rdi        # 1081f50 <core_durable_error.verbs+0x3000>
 105f041:	e8 3a 54 fc ff       	call   1024480 <myl_core_trap>
 105f046:	48 89 f0             	mov    %rsi,%rax
 105f049:	48 c1 f8 3f          	sar    $0x3f,%rax
 105f04d:	48 21 d0             	and    %rdx,%rax
 105f050:	48 01 f0             	add    %rsi,%rax
 105f053:	48 39 d0             	cmp    %rdx,%rax
 105f056:	0f 82 73 f7 ff ff    	jb     105e7cf <my.interpreter::execute+0xd1f>
 105f05c:	48 8d 3d 9d 0f 02 00 	lea    0x20f9d(%rip),%rdi        # 1080000 <core_durable_error.verbs+0x10b0>
 105f063:	e8 18 54 fc ff       	call   1024480 <myl_core_trap>
 105f068:	48 8d 3d a1 14 02 00 	lea    0x214a1(%rip),%rdi        # 1080510 <core_durable_error.verbs+0x15c0>
 105f06f:	ba 01 00 00 00       	mov    $0x1,%edx
 105f074:	48 89 c6             	mov    %rax,%rsi
 105f077:	e8 04 54 fc ff       	call   1024480 <myl_core_trap>
 105f07c:	48 8d 3d cd 5b 02 00 	lea    0x25bcd(%rip),%rdi        # 1084c50 <core_durable_error.verbs+0x5d00>
 105f083:	e8 78 a7 fc ff       	call   1029800 <myl_core_assert_fail>
 105f088:	83 f8 01             	cmp    $0x1,%eax
 105f08b:	0f 84 b8 00 00 00    	je     105f149 <my.interpreter::execute+0x1699>
 105f091:	85 c0                	test   %eax,%eax
 105f093:	0f 85 bc 00 00 00    	jne    105f155 <my.interpreter::execute+0x16a5>
 105f099:	48 8d 3d c0 5a 02 00 	lea    0x25ac0(%rip),%rdi        # 1084b60 <core_durable_error.verbs+0x5c10>
 105f0a0:	e8 5b a7 fc ff       	call   1029800 <myl_core_assert_fail>
 105f0a5:	48 8d 3d 94 59 02 00 	lea    0x25994(%rip),%rdi        # 1084a40 <core_durable_error.verbs+0x5af0>
 105f0ac:	31 f6                	xor    %esi,%esi
 105f0ae:	31 d2                	xor    %edx,%edx
 105f0b0:	e8 cb 53 fc ff       	call   1024480 <myl_core_trap>
 105f0b5:	48 8d 3d e4 11 02 00 	lea    0x211e4(%rip),%rdi        # 10802a0 <core_durable_error.verbs+0x1350>
 105f0bc:	ba 01 00 00 00       	mov    $0x1,%edx
 105f0c1:	e8 ba 53 fc ff       	call   1024480 <myl_core_trap>
 105f0c6:	48 8d 3d a3 14 02 00 	lea    0x214a3(%rip),%rdi        # 1080570 <core_durable_error.verbs+0x1620>
 105f0cd:	ba 01 00 00 00       	mov    $0x1,%edx
 105f0d2:	48 89 c6             	mov    %rax,%rsi
 105f0d5:	e8 a6 53 fc ff       	call   1024480 <myl_core_trap>
 105f0da:	48 8d 3d 6f 13 02 00 	lea    0x2136f(%rip),%rdi        # 1080450 <core_durable_error.verbs+0x1500>
 105f0e1:	ba 01 00 00 00       	mov    $0x1,%edx
 105f0e6:	48 89 c6             	mov    %rax,%rsi
 105f0e9:	e8 92 53 fc ff       	call   1024480 <myl_core_trap>
 105f0ee:	48 8d 3d 9b 12 02 00 	lea    0x2129b(%rip),%rdi        # 1080390 <core_durable_error.verbs+0x1440>
 105f0f5:	ba 01 00 00 00       	mov    $0x1,%edx
 105f0fa:	e8 81 53 fc ff       	call   1024480 <myl_core_trap>
 105f0ff:	48 8d 3d ca 11 02 00 	lea    0x211ca(%rip),%rdi        # 10802d0 <core_durable_error.verbs+0x1380>
 105f106:	ba 01 00 00 00       	mov    $0x1,%edx
 105f10b:	48 89 c6             	mov    %rax,%rsi
 105f10e:	e8 6d 53 fc ff       	call   1024480 <myl_core_trap>
 105f113:	48 8d 3d 16 12 02 00 	lea    0x21216(%rip),%rdi        # 1080330 <core_durable_error.verbs+0x13e0>
 105f11a:	ba 01 00 00 00       	mov    $0x1,%edx
 105f11f:	48 89 c6             	mov    %rax,%rsi
 105f122:	e8 59 53 fc ff       	call   1024480 <myl_core_trap>
 105f127:	48 8d 3d a2 14 02 00 	lea    0x214a2(%rip),%rdi        # 10805d0 <core_durable_error.verbs+0x1680>
 105f12e:	ba 01 00 00 00       	mov    $0x1,%edx
 105f133:	e8 48 53 fc ff       	call   1024480 <myl_core_trap>
 105f138:	48 8d 3d c1 2c 02 00 	lea    0x22cc1(%rip),%rdi        # 1081e00 <core_durable_error.verbs+0x2eb0>
 105f13f:	ba 01 00 00 00       	mov    $0x1,%edx
 105f144:	e8 37 53 fc ff       	call   1024480 <myl_core_trap>
 105f149:	48 8d 3d 40 5a 02 00 	lea    0x25a40(%rip),%rdi        # 1084b90 <core_durable_error.verbs+0x5c40>
 105f150:	e8 ab a6 fc ff       	call   1029800 <myl_core_assert_fail>
 105f155:	48 8d 3d 64 5a 02 00 	lea    0x25a64(%rip),%rdi        # 1084bc0 <core_durable_error.verbs+0x5c70>
 105f15c:	e8 9f a6 fc ff       	call   1029800 <myl_core_assert_fail>
 105f161:	48 8d 3d c8 2c 02 00 	lea    0x22cc8(%rip),%rdi        # 1081e30 <core_durable_error.verbs+0x2ee0>
 105f168:	ba 01 00 00 00       	mov    $0x1,%edx
 105f16d:	48 89 c6             	mov    %rax,%rsi
 105f170:	e8 0b 53 fc ff       	call   1024480 <myl_core_trap>
 105f175:	48 8d 3d 94 10 02 00 	lea    0x21094(%rip),%rdi        # 1080210 <core_durable_error.verbs+0x12c0>
 105f17c:	ba 01 00 00 00       	mov    $0x1,%edx
 105f181:	48 89 c6             	mov    %rax,%rsi
 105f184:	e8 f7 52 fc ff       	call   1024480 <myl_core_trap>
 105f189:	48 8d 3d b0 58 02 00 	lea    0x258b0(%rip),%rdi        # 1084a40 <core_durable_error.verbs+0x5af0>
 105f190:	31 f6                	xor    %esi,%esi
 105f192:	31 d2                	xor    %edx,%edx
 105f194:	e8 e7 52 fc ff       	call   1024480 <myl_core_trap>
 105f199:	48 8d 3d f0 2c 02 00 	lea    0x22cf0(%rip),%rdi        # 1081e90 <core_durable_error.verbs+0x2f40>
 105f1a0:	ba 01 00 00 00       	mov    $0x1,%edx
 105f1a5:	e8 d6 52 fc ff       	call   1024480 <myl_core_trap>
 105f1aa:	48 8d 3d 2f 13 02 00 	lea    0x2132f(%rip),%rdi        # 10804e0 <core_durable_error.verbs+0x1590>
 105f1b1:	ba 01 00 00 00       	mov    $0x1,%edx
 105f1b6:	e8 c5 52 fc ff       	call   1024480 <myl_core_trap>
 105f1bb:	48 8d 3d 5e 12 02 00 	lea    0x2125e(%rip),%rdi        # 1080420 <core_durable_error.verbs+0x14d0>
 105f1c2:	ba 01 00 00 00       	mov    $0x1,%edx
 105f1c7:	48 89 c6             	mov    %rax,%rsi
 105f1ca:	e8 b1 52 fc ff       	call   1024480 <myl_core_trap>
 105f1cf:	48 8d 3d 2a 59 02 00 	lea    0x2592a(%rip),%rdi        # 1084b00 <core_durable_error.verbs+0x5bb0>
 105f1d6:	ba 01 00 00 00       	mov    $0x1,%edx
 105f1db:	48 89 c6             	mov    %rax,%rsi
 105f1de:	e8 9d 52 fc ff       	call   1024480 <myl_core_trap>
 105f1e3:	48 8d 3d 36 2d 02 00 	lea    0x22d36(%rip),%rdi        # 1081f20 <core_durable_error.verbs+0x2fd0>
 105f1ea:	e8 11 a6 fc ff       	call   1029800 <myl_core_assert_fail>

Disassembly of section .plt:
