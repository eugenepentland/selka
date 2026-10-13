
.tmp/lox-eda-parity/P1/discard-local-001/candidate-lox:     file format elf64-x86-64


Disassembly of section .text:

000000000105ea80 <my.interpreter::execute>:
 105ea80:	55                   	push   %rbp
 105ea81:	41 57                	push   %r15
 105ea83:	41 56                	push   %r14
 105ea85:	41 55                	push   %r13
 105ea87:	41 54                	push   %r12
 105ea89:	53                   	push   %rbx
 105ea8a:	48 81 ec e8 0e 00 00 	sub    $0xee8,%rsp
 105ea91:	4d 89 ce             	mov    %r9,%r14
 105ea94:	4c 89 04 24          	mov    %r8,(%rsp)
 105ea98:	49 89 c9             	mov    %rcx,%r9
 105ea9b:	48 89 d3             	mov    %rdx,%rbx
 105ea9e:	48 89 fd             	mov    %rdi,%rbp
 105eaa1:	4c 8b a4 24 40 0f 00 	mov    0xf40(%rsp),%r12
 105eaa8:	00 
 105eaa9:	48 8b 52 08          	mov    0x8(%rdx),%rdx
 105eaad:	4c 89 e0             	mov    %r12,%rax
 105eab0:	49 39 d4             	cmp    %rdx,%r12
 105eab3:	0f 83 ac 12 00 00    	jae    105fd65 <my.interpreter::execute+0x12e5>
 105eab9:	4c 8b 9c 24 38 0f 00 	mov    0xf38(%rsp),%r11
 105eac0:	00 
 105eac1:	44 0f b6 84 24 30 0f 	movzbl 0xf30(%rsp),%r8d
 105eac8:	00 00 
 105eaca:	4c 8b ac 24 28 0f 00 	mov    0xf28(%rsp),%r13
 105ead1:	00 
 105ead2:	48 6b c8 58          	imul   $0x58,%rax,%rcx
 105ead6:	48 8d 04 0b          	lea    (%rbx,%rcx,1),%rax
 105eada:	48 83 c0 20          	add    $0x20,%rax
 105eade:	8b 4c 0b 20          	mov    0x20(%rbx,%rcx,1),%ecx
 105eae2:	48 83 f9 07          	cmp    $0x7,%rcx
 105eae6:	4c 89 4c 24 30       	mov    %r9,0x30(%rsp)
 105eaeb:	49 89 f7             	mov    %rsi,%r15
 105eaee:	0f 87 1c 07 00 00    	ja     105f210 <my.interpreter::execute+0x790>
 105eaf4:	48 8d 15 c9 89 fa ff 	lea    -0x57637(%rip),%rdx        # 10074c4 <core_number_pairs+0x264>
 105eafb:	48 63 0c 8a          	movslq (%rdx,%rcx,4),%rcx
 105eaff:	48 01 d1             	add    %rdx,%rcx
 105eb02:	ff e1                	jmp    *%rcx
 105eb04:	48 8b 48 10          	mov    0x10(%rax),%rcx
 105eb08:	49 8b 96 a8 00 00 00 	mov    0xa8(%r14),%rdx
 105eb0f:	48 8d bc 24 b0 0a 00 	lea    0xab0(%rsp),%rdi
 105eb16:	00 
 105eb17:	4c 89 f6             	mov    %r14,%rsi
 105eb1a:	e8 91 db 00 00       	call   106c6b0 <my.interpreter::new_env>
 105eb1f:	48 8b 94 24 b0 0a 00 	mov    0xab0(%rsp),%rdx
 105eb26:	00 
 105eb27:	49 8b b6 a8 00 00 00 	mov    0xa8(%r14),%rsi
 105eb2e:	49 8b 86 b0 00 00 00 	mov    0xb0(%r14),%rax
 105eb35:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105eb39:	48 3b 48 10          	cmp    0x10(%rax),%rcx
 105eb3d:	0f 83 8e 12 00 00    	jae    105fdd1 <my.interpreter::execute+0x1351>
 105eb43:	48 89 74 c8 20       	mov    %rsi,0x20(%rax,%rcx,8)
 105eb48:	48 ff c1             	inc    %rcx
 105eb4b:	48 89 48 08          	mov    %rcx,0x8(%rax)
 105eb4f:	49 89 86 b0 00 00 00 	mov    %rax,0xb0(%r14)
 105eb56:	49 89 96 a8 00 00 00 	mov    %rdx,0xa8(%r14)
 105eb5d:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 105eb61:	49 39 d4             	cmp    %rdx,%r12
 105eb64:	4c 8b 94 24 38 0f 00 	mov    0xf38(%rsp),%r10
 105eb6b:	00 
 105eb6c:	0f b6 b4 24 30 0f 00 	movzbl 0xf30(%rsp),%esi
 105eb73:	00 
 105eb74:	48 8b 4c 24 30       	mov    0x30(%rsp),%rcx
 105eb79:	0f 83 7c 12 00 00    	jae    105fdfb <my.interpreter::execute+0x137b>
 105eb7f:	4c 89 e0             	mov    %r12,%rax
 105eb82:	48 89 da             	mov    %rbx,%rdx
 105eb85:	48 83 c2 20          	add    $0x20,%rdx
 105eb89:	48 6b c0 58          	imul   $0x58,%rax,%rax
 105eb8d:	83 3c 02 00          	cmpl   $0x0,(%rdx,%rax,1)
 105eb91:	48 89 6c 24 20       	mov    %rbp,0x20(%rsp)
 105eb96:	0f 84 01 0b 00 00    	je     105f69d <my.interpreter::execute+0xc1d>
 105eb9c:	40 0f b6 f6          	movzbl %sil,%esi
 105eba0:	48 89 f3             	mov    %rsi,%rbx
 105eba3:	31 f6                	xor    %esi,%esi
 105eba5:	31 d2                	xor    %edx,%edx
 105eba7:	31 c0                	xor    %eax,%eax
 105eba9:	49 8b be b0 00 00 00 	mov    0xb0(%r14),%rdi
 105ebb0:	4c 8b 47 08          	mov    0x8(%rdi),%r8
 105ebb4:	4d 85 c0             	test   %r8,%r8
 105ebb7:	48 8b 6c 24 20       	mov    0x20(%rsp),%rbp
 105ebbc:	0f 84 6d 14 00 00    	je     106002f <my.interpreter::execute+0x15af>
 105ebc2:	4e 8b 4c c7 18       	mov    0x18(%rdi,%r8,8),%r9
 105ebc7:	49 ff c8             	dec    %r8
 105ebca:	4c 89 47 08          	mov    %r8,0x8(%rdi)
 105ebce:	4d 89 8e a8 00 00 00 	mov    %r9,0xa8(%r14)
 105ebd5:	40 84 f6             	test   %sil,%sil
 105ebd8:	0f 85 46 0f 00 00    	jne    105fb24 <my.interpreter::execute+0x10a4>
 105ebde:	48 89 55 00          	mov    %rdx,0x0(%rbp)
 105ebe2:	48 89 45 08          	mov    %rax,0x8(%rbp)
 105ebe6:	48 89 4d 10          	mov    %rcx,0x10(%rbp)
 105ebea:	4c 89 ad 00 01 00 00 	mov    %r13,0x100(%rbp)
 105ebf1:	48 89 9d 08 01 00 00 	mov    %rbx,0x108(%rbp)
 105ebf8:	4c 89 95 10 01 00 00 	mov    %r10,0x110(%rbp)
 105ebff:	e9 96 0e 00 00       	jmp    105fa9a <my.interpreter::execute+0x101a>
 105ec04:	48 8b 48 10          	mov    0x10(%rax),%rcx
 105ec08:	48 89 4c 24 10       	mov    %rcx,0x10(%rsp)
 105ec0d:	44 0f b6 60 18       	movzbl 0x18(%rax),%r12d
 105ec12:	48 8b 48 20          	mov    0x20(%rax),%rcx
 105ec16:	48 89 4c 24 18       	mov    %rcx,0x18(%rsp)
 105ec1b:	45 0f b6 d0          	movzbl %r8b,%r10d
 105ec1f:	48 8d bc 24 80 08 00 	lea    0x880(%rsp),%rdi
 105ec26:	00 
 105ec27:	48 89 da             	mov    %rbx,%rdx
 105ec2a:	4c 89 c9             	mov    %r9,%rcx
 105ec2d:	4c 8b 04 24          	mov    (%rsp),%r8
 105ec31:	4d 89 f1             	mov    %r14,%r9
 105ec34:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105ec3b:	ff 70 08             	push   0x8(%rax)
 105ec3e:	41 53                	push   %r11
 105ec40:	41 52                	push   %r10
 105ec42:	41 55                	push   %r13
 105ec44:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105ec4b:	e8 20 71 00 00       	call   1065d70 <my.interpreter::evaluate>
 105ec50:	48 83 c4 30          	add    $0x30,%rsp
 105ec54:	4c 8b ac 24 80 09 00 	mov    0x980(%rsp),%r13
 105ec5b:	00 
 105ec5c:	48 8b bc 24 88 09 00 	mov    0x988(%rsp),%rdi
 105ec63:	00 
 105ec64:	44 0f b6 d7          	movzbl %dil,%r10d
 105ec68:	4c 8b 9c 24 90 09 00 	mov    0x990(%rsp),%r11
 105ec6f:	00 
 105ec70:	80 bc 24 80 08 00 00 	cmpb   $0x1,0x880(%rsp)
 105ec77:	01 
 105ec78:	0f 84 42 0e 00 00    	je     105fac0 <my.interpreter::execute+0x1040>
 105ec7e:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105ec85:	48 89 c6             	mov    %rax,%rsi
 105ec88:	48 ff ce             	dec    %rsi
 105ec8b:	0f 80 f8 13 00 00    	jo     1060089 <my.interpreter::execute+0x1609>
 105ec91:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105ec98:	49 8b 46 78          	mov    0x78(%r14),%rax
 105ec9c:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105eca0:	48 39 d6             	cmp    %rdx,%rsi
 105eca3:	48 8b 4c 24 30       	mov    0x30(%rsp),%rcx
 105eca8:	0f 83 b9 11 00 00    	jae    105fe67 <my.interpreter::execute+0x13e7>
 105ecae:	49 89 f0             	mov    %rsi,%r8
 105ecb1:	49 c1 e0 04          	shl    $0x4,%r8
 105ecb5:	42 0f b6 54 00 20    	movzbl 0x20(%rax,%r8,1),%edx
 105ecbb:	85 d2                	test   %edx,%edx
 105ecbd:	0f 84 1c 09 00 00    	je     105f5df <my.interpreter::execute+0xb5f>
 105ecc3:	83 fa 01             	cmp    $0x1,%edx
 105ecc6:	75 11                	jne    105ecd9 <my.interpreter::execute+0x259>
 105ecc8:	4c 01 c0             	add    %r8,%rax
 105eccb:	48 83 c0 20          	add    $0x20,%rax
 105eccf:	f6 40 08 01          	testb  $0x1,0x8(%rax)
 105ecd3:	0f 84 06 09 00 00    	je     105f5df <my.interpreter::execute+0xb5f>
 105ecd9:	48 8d bc 24 68 07 00 	lea    0x768(%rsp),%rdi
 105ece0:	00 
 105ece1:	4c 89 fe             	mov    %r15,%rsi
 105ece4:	48 89 da             	mov    %rbx,%rdx
 105ece7:	4c 8b 04 24          	mov    (%rsp),%r8
 105eceb:	4d 89 f1             	mov    %r14,%r9
 105ecee:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105ecf5:	ff 74 24 18          	push   0x18(%rsp)
 105ecf9:	41 53                	push   %r11
 105ecfb:	41 52                	push   %r10
 105ecfd:	41 55                	push   %r13
 105ecff:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105ed06:	e8 75 fd ff ff       	call   105ea80 <my.interpreter::execute>
 105ed0b:	48 83 c4 30          	add    $0x30,%rsp
 105ed0f:	0f b6 84 24 68 07 00 	movzbl 0x768(%rsp),%eax
 105ed16:	00 
 105ed17:	c5 f8 10 84 24 70 07 	vmovups 0x770(%rsp),%xmm0
 105ed1e:	00 00 
 105ed20:	48 8b 8c 24 68 08 00 	mov    0x868(%rsp),%rcx
 105ed27:	00 
 105ed28:	0f b6 94 24 70 08 00 	movzbl 0x870(%rsp),%edx
 105ed2f:	00 
 105ed30:	48 8b b4 24 78 08 00 	mov    0x878(%rsp),%rsi
 105ed37:	00 
 105ed38:	48 83 f8 01          	cmp    $0x1,%rax
 105ed3c:	0f 85 10 09 00 00    	jne    105f652 <my.interpreter::execute+0xbd2>
 105ed42:	48 8d 3d 77 25 02 00 	lea    0x22577(%rip),%rdi        # 10812c0 <core_durable_error.verbs+0x1170>
 105ed49:	e9 df 0f 00 00       	jmp    105fd2d <my.interpreter::execute+0x12ad>
 105ed4e:	48 8b 40 08          	mov    0x8(%rax),%rax
 105ed52:	48 8b 56 08          	mov    0x8(%rsi),%rdx
 105ed56:	48 89 c1             	mov    %rax,%rcx
 105ed59:	48 39 d0             	cmp    %rdx,%rax
 105ed5c:	0f 83 28 10 00 00    	jae    105fd8a <my.interpreter::execute+0x130a>
 105ed62:	48 6b c9 70          	imul   $0x70,%rcx,%rcx
 105ed66:	83 7c 0e 20 0b       	cmpl   $0xb,0x20(%rsi,%rcx,1)
 105ed6b:	0f 85 3b 06 00 00    	jne    105f3ac <my.interpreter::execute+0x92c>
 105ed71:	48 01 f1             	add    %rsi,%rcx
 105ed74:	48 83 c1 20          	add    $0x20,%rcx
 105ed78:	4c 8b 79 38          	mov    0x38(%rcx),%r15
 105ed7c:	49 83 ff ff          	cmp    $0xffffffffffffffff,%r15
 105ed80:	0f 84 26 06 00 00    	je     105f3ac <my.interpreter::execute+0x92c>
 105ed86:	48 8b 59 40          	mov    0x40(%rcx),%rbx
 105ed8a:	49 8b 86 a8 00 00 00 	mov    0xa8(%r14),%rax
 105ed91:	4d 89 c4             	mov    %r8,%r12
 105ed94:	4d 85 ff             	test   %r15,%r15
 105ed97:	7e 37                	jle    105edd0 <my.interpreter::execute+0x350>
 105ed99:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105eda0:	0f 1f 84 00 00 00 00 
 105eda7:	00 
 105eda8:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105edaf:	0f 1f 84 00 00 00 00 
 105edb6:	00 
 105edb7:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 105edbe:	00 00 
 105edc0:	4c 89 f7             	mov    %r14,%rdi
 105edc3:	48 89 c6             	mov    %rax,%rsi
 105edc6:	e8 a5 dc 00 00       	call   106ca70 <my.heap::env_enclosing>
 105edcb:	49 ff cf             	dec    %r15
 105edce:	75 f0                	jne    105edc0 <my.interpreter::execute+0x340>
 105edd0:	4c 89 f7             	mov    %r14,%rdi
 105edd3:	48 89 c6             	mov    %rax,%rsi
 105edd6:	48 89 da             	mov    %rbx,%rdx
 105edd9:	e8 72 6e 00 00       	call   1065c50 <my.heap::env_slot>
 105edde:	49 8b 46 78          	mov    0x78(%r14),%rax
 105ede2:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105ede9:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105eded:	48 39 d6             	cmp    %rdx,%rsi
 105edf0:	0f 83 e6 11 00 00    	jae    105ffdc <my.interpreter::execute+0x155c>
 105edf6:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
 105edfa:	c5 f8 11 45 00       	vmovups %xmm0,0x0(%rbp)
 105edff:	4c 89 ad 00 01 00 00 	mov    %r13,0x100(%rbp)
 105ee06:	41 0f b6 c4          	movzbl %r12b,%eax
 105ee0a:	48 89 85 08 01 00 00 	mov    %rax,0x108(%rbp)
 105ee11:	48 8b 84 24 38 0f 00 	mov    0xf38(%rsp),%rax
 105ee18:	00 
 105ee19:	48 89 85 10 01 00 00 	mov    %rax,0x110(%rbp)
 105ee20:	e9 75 0c 00 00       	jmp    105fa9a <my.interpreter::execute+0x101a>
 105ee25:	4d 89 dc             	mov    %r11,%r12
 105ee28:	48 8b 70 08          	mov    0x8(%rax),%rsi
 105ee2c:	49 8b 51 08          	mov    0x8(%r9),%rdx
 105ee30:	48 89 f0             	mov    %rsi,%rax
 105ee33:	48 39 d6             	cmp    %rdx,%rsi
 105ee36:	0f 83 73 0f 00 00    	jae    105fdaf <my.interpreter::execute+0x132f>
 105ee3c:	48 8d 04 80          	lea    (%rax,%rax,4),%rax
 105ee40:	48 c1 e0 04          	shl    $0x4,%rax
 105ee44:	49 8b 5c 01 48       	mov    0x48(%r9,%rax,1),%rbx
 105ee49:	4d 8b 7c 01 60       	mov    0x60(%r9,%rax,1),%r15
 105ee4e:	49 8b 86 a8 00 00 00 	mov    0xa8(%r14),%rax
 105ee55:	48 c7 44 24 68 0a 00 	movq   $0xa,0x68(%rsp)
 105ee5c:	00 00 
 105ee5e:	48 89 74 24 70       	mov    %rsi,0x70(%rsp)
 105ee63:	48 89 5c 24 78       	mov    %rbx,0x78(%rsp)
 105ee68:	48 89 84 24 80 00 00 	mov    %rax,0x80(%rsp)
 105ee6f:	00 
 105ee70:	c6 84 24 88 00 00 00 	movb   $0x0,0x88(%rsp)
 105ee77:	00 
 105ee78:	48 8d bc 24 90 0c 00 	lea    0xc90(%rsp),%rdi
 105ee7f:	00 
 105ee80:	48 8d 54 24 68       	lea    0x68(%rsp),%rdx
 105ee85:	4c 89 f6             	mov    %r14,%rsi
 105ee88:	e8 d3 ba ff ff       	call   105a960 <my.heap::allocate>
 105ee8d:	48 8b 84 24 90 0c 00 	mov    0xc90(%rsp),%rax
 105ee94:	00 
 105ee95:	49 8b 4e 78          	mov    0x78(%r14),%rcx
 105ee99:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105eea0:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105eea4:	48 39 d6             	cmp    %rdx,%rsi
 105eea7:	0f 83 73 0f 00 00    	jae    105fe20 <my.interpreter::execute+0x13a0>
 105eead:	48 89 f7             	mov    %rsi,%rdi
 105eeb0:	48 c1 e7 04          	shl    $0x4,%rdi
 105eeb4:	48 c7 44 39 20 03 00 	movq   $0x3,0x20(%rcx,%rdi,1)
 105eebb:	00 00 
 105eebd:	48 89 44 39 28       	mov    %rax,0x28(%rcx,%rdi,1)
 105eec2:	49 89 4e 78          	mov    %rcx,0x78(%r14)
 105eec6:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105eecd:	48 89 f0             	mov    %rsi,%rax
 105eed0:	48 ff c0             	inc    %rax
 105eed3:	0f 80 66 11 00 00    	jo     106003f <my.interpreter::execute+0x15bf>
 105eed9:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 105eee0:	4c 89 f7             	mov    %r14,%rdi
 105eee3:	48 89 de             	mov    %rbx,%rsi
 105eee6:	4c 89 fa             	mov    %r15,%rdx
 105eee9:	e8 92 8d 00 00       	call   1067c80 <my.interpreter::define>
 105eeee:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105eef5:	48 89 c6             	mov    %rax,%rsi
 105eef8:	48 ff ce             	dec    %rsi
 105eefb:	0f 80 4f 11 00 00    	jo     1060050 <my.interpreter::execute+0x15d0>
 105ef01:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105ef08:	49 8b 46 78          	mov    0x78(%r14),%rax
 105ef0c:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105ef10:	48 39 d6             	cmp    %rdx,%rsi
 105ef13:	4d 89 e3             	mov    %r12,%r11
 105ef16:	0f b6 bc 24 30 0f 00 	movzbl 0xf30(%rsp),%edi
 105ef1d:	00 
 105ef1e:	0f 82 54 0b 00 00    	jb     105fa78 <my.interpreter::execute+0xff8>
 105ef24:	48 89 f0             	mov    %rsi,%rax
 105ef27:	48 c1 f8 3f          	sar    $0x3f,%rax
 105ef2b:	48 21 d0             	and    %rdx,%rax
 105ef2e:	48 01 f0             	add    %rsi,%rax
 105ef31:	48 39 d0             	cmp    %rdx,%rax
 105ef34:	0f 82 3e 0b 00 00    	jb     105fa78 <my.interpreter::execute+0xff8>
 105ef3a:	48 8d 3d 5f 28 02 00 	lea    0x2285f(%rip),%rdi        # 10817a0 <core_durable_error.verbs+0x1650>
 105ef41:	e8 3a 5d fc ff       	call   1024c80 <myl_core_trap>
 105ef46:	4c 8b 60 30          	mov    0x30(%rax),%r12
 105ef4a:	4c 8b 50 48          	mov    0x48(%rax),%r10
 105ef4e:	80 78 38 01          	cmpb   $0x1,0x38(%rax)
 105ef52:	0f 85 fe 04 00 00    	jne    105f456 <my.interpreter::execute+0x9d6>
 105ef58:	4c 89 54 24 30       	mov    %r10,0x30(%rsp)
 105ef5d:	45 0f b6 d0          	movzbl %r8b,%r10d
 105ef61:	48 8d bc 24 20 04 00 	lea    0x420(%rsp),%rdi
 105ef68:	00 
 105ef69:	48 89 da             	mov    %rbx,%rdx
 105ef6c:	4c 89 c9             	mov    %r9,%rcx
 105ef6f:	4c 8b 04 24          	mov    (%rsp),%r8
 105ef73:	4d 89 f1             	mov    %r14,%r9
 105ef76:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105ef7d:	ff 70 40             	push   0x40(%rax)
 105ef80:	41 53                	push   %r11
 105ef82:	41 52                	push   %r10
 105ef84:	41 55                	push   %r13
 105ef86:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105ef8d:	e8 de 6d 00 00       	call   1065d70 <my.interpreter::evaluate>
 105ef92:	48 83 c4 30          	add    $0x30,%rsp
 105ef96:	4c 8b ac 24 20 05 00 	mov    0x520(%rsp),%r13
 105ef9d:	00 
 105ef9e:	4c 8b bc 24 28 05 00 	mov    0x528(%rsp),%r15
 105efa5:	00 
 105efa6:	48 8b 9c 24 30 05 00 	mov    0x530(%rsp),%rbx
 105efad:	00 
 105efae:	80 bc 24 20 04 00 00 	cmpb   $0x1,0x420(%rsp)
 105efb5:	01 
 105efb6:	0f 84 72 0c 00 00    	je     105fc2e <my.interpreter::execute+0x11ae>
 105efbc:	4c 8b 54 24 30       	mov    0x30(%rsp),%r10
 105efc1:	e9 dc 04 00 00       	jmp    105f4a2 <my.interpreter::execute+0xa22>
 105efc6:	48 8b 48 30          	mov    0x30(%rax),%rcx
 105efca:	48 89 4c 24 18       	mov    %rcx,0x18(%rsp)
 105efcf:	48 8b 48 38          	mov    0x38(%rax),%rcx
 105efd3:	44 0f b6 60 40       	movzbl 0x40(%rax),%r12d
 105efd8:	48 8b 50 48          	mov    0x48(%rax),%rdx
 105efdc:	48 89 54 24 28       	mov    %rdx,0x28(%rsp)
 105efe1:	48 8b 40 50          	mov    0x50(%rax),%rax
 105efe5:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105efea:	48 89 4c 24 60       	mov    %rcx,0x60(%rsp)
 105efef:	48 83 f9 ff          	cmp    $0xffffffffffffffff,%rcx
 105eff3:	75 48                	jne    105f03d <my.interpreter::execute+0x5bd>
 105eff5:	4c 89 f7             	mov    %r14,%rdi
 105eff8:	48 8b 74 24 18       	mov    0x18(%rsp),%rsi
 105effd:	e8 de ad 00 00       	call   1069de0 <my.heap::string_hash>
 105f002:	49 8b 7e 30          	mov    0x30(%r14),%rdi
 105f006:	49 8b 76 38          	mov    0x38(%r14),%rsi
 105f00a:	48 8b 54 24 18       	mov    0x18(%rsp),%rdx
 105f00f:	89 c1                	mov    %eax,%ecx
 105f011:	45 31 c0             	xor    %r8d,%r8d
 105f014:	45 31 c9             	xor    %r9d,%r9d
 105f017:	e8 a4 ae 00 00       	call   1069ec0 <my.table::set>
 105f01c:	4c 89 fe             	mov    %r15,%rsi
 105f01f:	4c 8b 4c 24 30       	mov    0x30(%rsp),%r9
 105f024:	44 0f b6 84 24 30 0f 	movzbl 0xf30(%rsp),%r8d
 105f02b:	00 00 
 105f02d:	4c 8b 9c 24 38 0f 00 	mov    0xf38(%rsp),%r11
 105f034:	00 
 105f035:	49 89 56 30          	mov    %rdx,0x30(%r14)
 105f039:	49 89 4e 38          	mov    %rcx,0x38(%r14)
 105f03d:	49 c7 c7 ff ff ff ff 	mov    $0xffffffffffffffff,%r15
 105f044:	41 83 fc 01          	cmp    $0x1,%r12d
 105f048:	0f 85 b5 04 00 00    	jne    105f503 <my.interpreter::execute+0xa83>
 105f04e:	41 0f b6 c0          	movzbl %r8b,%eax
 105f052:	48 8d bc 24 d8 00 00 	lea    0xd8(%rsp),%rdi
 105f059:	00 
 105f05a:	49 89 f7             	mov    %rsi,%r15
 105f05d:	48 89 da             	mov    %rbx,%rdx
 105f060:	4c 89 c9             	mov    %r9,%rcx
 105f063:	4c 8b 04 24          	mov    (%rsp),%r8
 105f067:	4d 89 f1             	mov    %r14,%r9
 105f06a:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105f071:	48 8b 5c 24 30       	mov    0x30(%rsp),%rbx
 105f076:	53                   	push   %rbx
 105f077:	41 53                	push   %r11
 105f079:	50                   	push   %rax
 105f07a:	41 55                	push   %r13
 105f07c:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105f083:	e8 e8 6c 00 00       	call   1065d70 <my.interpreter::evaluate>
 105f088:	48 83 c4 30          	add    $0x30,%rsp
 105f08c:	4c 8b ac 24 d8 01 00 	mov    0x1d8(%rsp),%r13
 105f093:	00 
 105f094:	44 0f b6 84 24 e0 01 	movzbl 0x1e0(%rsp),%r8d
 105f09b:	00 00 
 105f09d:	48 8b bc 24 e8 01 00 	mov    0x1e8(%rsp),%rdi
 105f0a4:	00 
 105f0a5:	80 bc 24 d8 00 00 00 	cmpb   $0x1,0xd8(%rsp)
 105f0ac:	01 
 105f0ad:	0f 84 c5 0b 00 00    	je     105fc78 <my.interpreter::execute+0x11f8>
 105f0b3:	49 8b 57 08          	mov    0x8(%r15),%rdx
 105f0b7:	48 39 d3             	cmp    %rdx,%rbx
 105f0ba:	0f 83 ae 0e 00 00    	jae    105ff6e <my.interpreter::execute+0x14ee>
 105f0c0:	48 89 d8             	mov    %rbx,%rax
 105f0c3:	48 6b c0 70          	imul   $0x70,%rax,%rax
 105f0c7:	41 83 7c 07 20 0b    	cmpl   $0xb,0x20(%r15,%rax,1)
 105f0cd:	0f 85 71 06 00 00    	jne    105f744 <my.interpreter::execute+0xcc4>
 105f0d3:	4c 01 f8             	add    %r15,%rax
 105f0d6:	48 83 c0 20          	add    $0x20,%rax
 105f0da:	48 8b 58 20          	mov    0x20(%rax),%rbx
 105f0de:	e9 63 06 00 00       	jmp    105f746 <my.interpreter::execute+0xcc6>
 105f0e3:	45 0f b6 d0          	movzbl %r8b,%r10d
 105f0e7:	48 8d bc 24 38 05 00 	lea    0x538(%rsp),%rdi
 105f0ee:	00 
 105f0ef:	48 89 da             	mov    %rbx,%rdx
 105f0f2:	4c 89 c9             	mov    %r9,%rcx
 105f0f5:	4c 8b 04 24          	mov    (%rsp),%r8
 105f0f9:	4d 89 f1             	mov    %r14,%r9
 105f0fc:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105f103:	ff 70 08             	push   0x8(%rax)
 105f106:	41 53                	push   %r11
 105f108:	41 52                	push   %r10
 105f10a:	41 55                	push   %r13
 105f10c:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105f113:	e8 58 6c 00 00       	call   1065d70 <my.interpreter::evaluate>
 105f118:	48 83 c4 30          	add    $0x30,%rsp
 105f11c:	4c 8b ac 24 38 06 00 	mov    0x638(%rsp),%r13
 105f123:	00 
 105f124:	4c 8b bc 24 40 06 00 	mov    0x640(%rsp),%r15
 105f12b:	00 
 105f12c:	48 8b 9c 24 48 06 00 	mov    0x648(%rsp),%rbx
 105f133:	00 
 105f134:	80 bc 24 38 05 00 00 	cmpb   $0x1,0x538(%rsp)
 105f13b:	01 
 105f13c:	0f 84 c4 09 00 00    	je     105fb06 <my.interpreter::execute+0x1086>
 105f142:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105f149:	48 89 c6             	mov    %rax,%rsi
 105f14c:	48 ff ce             	dec    %rsi
 105f14f:	0f 80 48 0f 00 00    	jo     106009d <my.interpreter::execute+0x161d>
 105f155:	49 8b 46 78          	mov    0x78(%r14),%rax
 105f159:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105f15d:	48 39 d6             	cmp    %rdx,%rsi
 105f160:	0f 83 23 0d 00 00    	jae    105fe89 <my.interpreter::execute+0x1409>
 105f166:	48 89 f7             	mov    %rsi,%rdi
 105f169:	48 c1 e7 04          	shl    $0x4,%rdi
 105f16d:	48 8b 4c 38 28       	mov    0x28(%rax,%rdi,1),%rcx
 105f172:	8b 54 38 20          	mov    0x20(%rax,%rdi,1),%edx
 105f176:	4c 89 f7             	mov    %r14,%rdi
 105f179:	48 8b b4 24 20 0f 00 	mov    0xf20(%rsp),%rsi
 105f180:	00 
 105f181:	e8 ba 43 00 00       	call   1063540 <my.output::print_value>
 105f186:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105f18d:	48 89 f0             	mov    %rsi,%rax
 105f190:	48 ff c8             	dec    %rax
 105f193:	0f 80 18 0f 00 00    	jo     10600b1 <my.interpreter::execute+0x1631>
 105f199:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 105f1a0:	49 89 db             	mov    %rbx,%r11
 105f1a3:	4c 89 ff             	mov    %r15,%rdi
 105f1a6:	e9 cd 08 00 00       	jmp    105fa78 <my.interpreter::execute+0xff8>
 105f1ab:	83 78 30 01          	cmpl   $0x1,0x30(%rax)
 105f1af:	0f 85 5d 03 00 00    	jne    105f512 <my.interpreter::execute+0xa92>
 105f1b5:	45 0f b6 d0          	movzbl %r8b,%r10d
 105f1b9:	48 8d bc 24 78 0b 00 	lea    0xb78(%rsp),%rdi
 105f1c0:	00 
 105f1c1:	48 89 da             	mov    %rbx,%rdx
 105f1c4:	4c 89 c9             	mov    %r9,%rcx
 105f1c7:	4c 8b 04 24          	mov    (%rsp),%r8
 105f1cb:	4d 89 f1             	mov    %r14,%r9
 105f1ce:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105f1d5:	ff 70 38             	push   0x38(%rax)
 105f1d8:	41 53                	push   %r11
 105f1da:	41 52                	push   %r10
 105f1dc:	41 55                	push   %r13
 105f1de:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105f1e5:	e8 86 6b 00 00       	call   1065d70 <my.interpreter::evaluate>
 105f1ea:	48 83 c4 30          	add    $0x30,%rsp
 105f1ee:	4c 8b ac 24 78 0c 00 	mov    0xc78(%rsp),%r13
 105f1f5:	00 
 105f1f6:	80 bc 24 78 0b 00 00 	cmpb   $0x1,0xb78(%rsp)
 105f1fd:	01 
 105f1fe:	0f 84 d5 0a 00 00    	je     105fcd9 <my.interpreter::execute+0x1259>
 105f204:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105f20b:	e9 48 03 00 00       	jmp    105f558 <my.interpreter::execute+0xad8>
 105f210:	48 89 6c 24 20       	mov    %rbp,0x20(%rsp)
 105f215:	4c 8b 60 08          	mov    0x8(%rax),%r12
 105f219:	48 8b 40 10          	mov    0x10(%rax),%rax
 105f21d:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105f222:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105f229:	0f 1f 84 00 00 00 00 
 105f230:	00 
 105f231:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105f238:	0f 1f 84 00 00 00 00 
 105f23f:	00 
 105f240:	41 0f b6 c0          	movzbl %r8b,%eax
 105f244:	48 8d bc 24 08 03 00 	lea    0x308(%rsp),%rdi
 105f24b:	00 
 105f24c:	48 89 da             	mov    %rbx,%rdx
 105f24f:	4c 89 c9             	mov    %r9,%rcx
 105f252:	4c 8b 04 24          	mov    (%rsp),%r8
 105f256:	4d 89 f1             	mov    %r14,%r9
 105f259:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105f260:	41 54                	push   %r12
 105f262:	41 53                	push   %r11
 105f264:	50                   	push   %rax
 105f265:	41 55                	push   %r13
 105f267:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105f26e:	e8 fd 6a 00 00       	call   1065d70 <my.interpreter::evaluate>
 105f273:	48 83 c4 30          	add    $0x30,%rsp
 105f277:	4c 8b 94 24 08 04 00 	mov    0x408(%rsp),%r10
 105f27e:	00 
 105f27f:	48 8b 84 24 10 04 00 	mov    0x410(%rsp),%rax
 105f286:	00 
 105f287:	0f b6 e8             	movzbl %al,%ebp
 105f28a:	4c 8b ac 24 18 04 00 	mov    0x418(%rsp),%r13
 105f291:	00 
 105f292:	80 bc 24 08 03 00 00 	cmpb   $0x1,0x308(%rsp)
 105f299:	01 
 105f29a:	0f 84 13 09 00 00    	je     105fbb3 <my.interpreter::execute+0x1133>
 105f2a0:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105f2a7:	48 89 c6             	mov    %rax,%rsi
 105f2aa:	48 ff ce             	dec    %rsi
 105f2ad:	0f 80 4b 0d 00 00    	jo     105fffe <my.interpreter::execute+0x157e>
 105f2b3:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105f2ba:	49 8b 46 78          	mov    0x78(%r14),%rax
 105f2be:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105f2c2:	48 39 d6             	cmp    %rdx,%rsi
 105f2c5:	48 8b 4c 24 30       	mov    0x30(%rsp),%rcx
 105f2ca:	0f 83 ba 00 00 00    	jae    105f38a <my.interpreter::execute+0x90a>
 105f2d0:	48 89 f7             	mov    %rsi,%rdi
 105f2d3:	48 c1 e7 04          	shl    $0x4,%rdi
 105f2d7:	0f b6 54 38 20       	movzbl 0x20(%rax,%rdi,1),%edx
 105f2dc:	83 fa 01             	cmp    $0x1,%edx
 105f2df:	74 1f                	je     105f300 <my.interpreter::execute+0x880>
 105f2e1:	85 d2                	test   %edx,%edx
 105f2e3:	4c 89 fe             	mov    %r15,%rsi
 105f2e6:	75 2c                	jne    105f314 <my.interpreter::execute+0x894>
 105f2e8:	e9 c8 02 00 00       	jmp    105f5b5 <my.interpreter::execute+0xb35>
 105f2ed:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105f2f4:	0f 1f 84 00 00 00 00 
 105f2fb:	00 
 105f2fc:	0f 1f 40 00          	nopl   0x0(%rax)
 105f300:	48 01 f8             	add    %rdi,%rax
 105f303:	48 83 c0 20          	add    $0x20,%rax
 105f307:	f6 40 08 01          	testb  $0x1,0x8(%rax)
 105f30b:	4c 89 fe             	mov    %r15,%rsi
 105f30e:	0f 84 a1 02 00 00    	je     105f5b5 <my.interpreter::execute+0xb35>
 105f314:	48 8d bc 24 f0 01 00 	lea    0x1f0(%rsp),%rdi
 105f31b:	00 
 105f31c:	48 89 da             	mov    %rbx,%rdx
 105f31f:	4c 8b 04 24          	mov    (%rsp),%r8
 105f323:	4d 89 f1             	mov    %r14,%r9
 105f326:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105f32d:	ff 74 24 18          	push   0x18(%rsp)
 105f331:	41 55                	push   %r13
 105f333:	55                   	push   %rbp
 105f334:	41 52                	push   %r10
 105f336:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105f33d:	e8 3e f7 ff ff       	call   105ea80 <my.interpreter::execute>
 105f342:	48 83 c4 30          	add    $0x30,%rsp
 105f346:	48 8b 84 24 f8 01 00 	mov    0x1f8(%rsp),%rax
 105f34d:	00 
 105f34e:	4c 8b ac 24 f0 02 00 	mov    0x2f0(%rsp),%r13
 105f355:	00 
 105f356:	44 0f b6 84 24 f8 02 	movzbl 0x2f8(%rsp),%r8d
 105f35d:	00 00 
 105f35f:	4c 8b 9c 24 00 03 00 	mov    0x300(%rsp),%r11
 105f366:	00 
 105f367:	80 bc 24 f0 01 00 00 	cmpb   $0x1,0x1f0(%rsp)
 105f36e:	01 
 105f36f:	0f 84 73 08 00 00    	je     105fbe8 <my.interpreter::execute+0x1168>
 105f375:	3c 01                	cmp    $0x1,%al
 105f377:	4c 8b 4c 24 30       	mov    0x30(%rsp),%r9
 105f37c:	4c 89 fe             	mov    %r15,%rsi
 105f37f:	0f 85 bb fe ff ff    	jne    105f240 <my.interpreter::execute+0x7c0>
 105f385:	e9 eb 02 00 00       	jmp    105f675 <my.interpreter::execute+0xbf5>
 105f38a:	48 89 f7             	mov    %rsi,%rdi
 105f38d:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105f391:	48 21 d7             	and    %rdx,%rdi
 105f394:	48 01 f7             	add    %rsi,%rdi
 105f397:	48 39 d7             	cmp    %rdx,%rdi
 105f39a:	0f 82 33 ff ff ff    	jb     105f2d3 <my.interpreter::execute+0x853>
 105f3a0:	48 8d 3d 99 23 02 00 	lea    0x22399(%rip),%rdi        # 1081740 <core_durable_error.verbs+0x15f0>
 105f3a7:	e8 d4 58 fc ff       	call   1024c80 <myl_core_trap>
 105f3ac:	45 0f b6 d0          	movzbl %r8b,%r10d
 105f3b0:	48 8d bc 24 98 09 00 	lea    0x998(%rsp),%rdi
 105f3b7:	00 
 105f3b8:	48 89 da             	mov    %rbx,%rdx
 105f3bb:	4c 89 c9             	mov    %r9,%rcx
 105f3be:	4c 8b 04 24          	mov    (%rsp),%r8
 105f3c2:	4d 89 f1             	mov    %r14,%r9
 105f3c5:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105f3cc:	50                   	push   %rax
 105f3cd:	41 53                	push   %r11
 105f3cf:	41 52                	push   %r10
 105f3d1:	41 55                	push   %r13
 105f3d3:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105f3da:	e8 91 69 00 00       	call   1065d70 <my.interpreter::evaluate>
 105f3df:	48 83 c4 30          	add    $0x30,%rsp
 105f3e3:	4c 8b ac 24 98 0a 00 	mov    0xa98(%rsp),%r13
 105f3ea:	00 
 105f3eb:	48 8b bc 24 a0 0a 00 	mov    0xaa0(%rsp),%rdi
 105f3f2:	00 
 105f3f3:	4c 8b 9c 24 a8 0a 00 	mov    0xaa8(%rsp),%r11
 105f3fa:	00 
 105f3fb:	80 bc 24 98 09 00 00 	cmpb   $0x1,0x998(%rsp)
 105f402:	01 
 105f403:	0f 84 5d 07 00 00    	je     105fb66 <my.interpreter::execute+0x10e6>
 105f409:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105f410:	48 89 c6             	mov    %rax,%rsi
 105f413:	48 ff ce             	dec    %rsi
 105f416:	0f 80 e3 0c 00 00    	jo     10600ff <my.interpreter::execute+0x167f>
 105f41c:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105f423:	49 8b 46 78          	mov    0x78(%r14),%rax
 105f427:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105f42b:	48 39 d6             	cmp    %rdx,%rsi
 105f42e:	0f 82 44 06 00 00    	jb     105fa78 <my.interpreter::execute+0xff8>
 105f434:	48 89 f0             	mov    %rsi,%rax
 105f437:	48 c1 f8 3f          	sar    $0x3f,%rax
 105f43b:	48 21 d0             	and    %rdx,%rax
 105f43e:	48 01 f0             	add    %rsi,%rax
 105f441:	48 39 d0             	cmp    %rdx,%rax
 105f444:	0f 82 2e 06 00 00    	jb     105fa78 <my.interpreter::execute+0xff8>
 105f44a:	48 8d 3d ef 1f 02 00 	lea    0x21fef(%rip),%rdi        # 1081440 <core_durable_error.verbs+0x12f0>
 105f451:	e8 2a 58 fc ff       	call   1024c80 <myl_core_trap>
 105f456:	49 8b 46 78          	mov    0x78(%r14),%rax
 105f45a:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105f461:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105f465:	48 39 d6             	cmp    %rdx,%rsi
 105f468:	0f 83 bc 0a 00 00    	jae    105ff2a <my.interpreter::execute+0x14aa>
 105f46e:	48 89 f1             	mov    %rsi,%rcx
 105f471:	48 c1 e1 04          	shl    $0x4,%rcx
 105f475:	48 c7 44 08 20 00 00 	movq   $0x0,0x20(%rax,%rcx,1)
 105f47c:	00 00 
 105f47e:	49 89 46 78          	mov    %rax,0x78(%r14)
 105f482:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105f489:	48 89 f0             	mov    %rsi,%rax
 105f48c:	48 ff c0             	inc    %rax
 105f48f:	0f 80 9f 0c 00 00    	jo     1060134 <my.interpreter::execute+0x16b4>
 105f495:	4d 89 c7             	mov    %r8,%r15
 105f498:	4c 89 db             	mov    %r11,%rbx
 105f49b:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 105f4a2:	4c 89 f7             	mov    %r14,%rdi
 105f4a5:	4c 89 e6             	mov    %r12,%rsi
 105f4a8:	4c 89 d2             	mov    %r10,%rdx
 105f4ab:	e8 d0 87 00 00       	call   1067c80 <my.interpreter::define>
 105f4b0:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105f4b7:	48 89 c6             	mov    %rax,%rsi
 105f4ba:	48 ff ce             	dec    %rsi
 105f4bd:	0f 80 a1 0b 00 00    	jo     1060064 <my.interpreter::execute+0x15e4>
 105f4c3:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105f4ca:	49 8b 46 78          	mov    0x78(%r14),%rax
 105f4ce:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105f4d2:	48 39 d6             	cmp    %rdx,%rsi
 105f4d5:	49 89 db             	mov    %rbx,%r11
 105f4d8:	4c 89 ff             	mov    %r15,%rdi
 105f4db:	0f 82 97 05 00 00    	jb     105fa78 <my.interpreter::execute+0xff8>
 105f4e1:	48 89 f0             	mov    %rsi,%rax
 105f4e4:	48 c1 f8 3f          	sar    $0x3f,%rax
 105f4e8:	48 21 d0             	and    %rdx,%rax
 105f4eb:	48 01 f0             	add    %rsi,%rax
 105f4ee:	48 39 d0             	cmp    %rdx,%rax
 105f4f1:	0f 82 81 05 00 00    	jb     105fa78 <my.interpreter::execute+0xff8>
 105f4f7:	48 8d 3d 82 21 02 00 	lea    0x22182(%rip),%rdi        # 1081680 <core_durable_error.verbs+0x1530>
 105f4fe:	e8 7d 57 fc ff       	call   1024c80 <myl_core_trap>
 105f503:	4c 89 44 24 28       	mov    %r8,0x28(%rsp)
 105f508:	4c 89 5c 24 48       	mov    %r11,0x48(%rsp)
 105f50d:	e9 9b 02 00 00       	jmp    105f7ad <my.interpreter::execute+0xd2d>
 105f512:	49 8b 46 78          	mov    0x78(%r14),%rax
 105f516:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105f51d:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105f521:	48 39 d6             	cmp    %rdx,%rsi
 105f524:	0f 83 22 0a 00 00    	jae    105ff4c <my.interpreter::execute+0x14cc>
 105f52a:	48 89 f1             	mov    %rsi,%rcx
 105f52d:	48 c1 e1 04          	shl    $0x4,%rcx
 105f531:	48 c7 44 08 20 00 00 	movq   $0x0,0x20(%rax,%rcx,1)
 105f538:	00 00 
 105f53a:	49 89 46 78          	mov    %rax,0x78(%r14)
 105f53e:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105f545:	48 89 c6             	mov    %rax,%rsi
 105f548:	48 ff c6             	inc    %rsi
 105f54b:	0f 80 f4 0b 00 00    	jo     1060145 <my.interpreter::execute+0x16c5>
 105f551:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105f558:	48 89 f0             	mov    %rsi,%rax
 105f55b:	48 ff c8             	dec    %rax
 105f55e:	0f 80 14 0b 00 00    	jo     1060078 <my.interpreter::execute+0x15f8>
 105f564:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 105f56b:	49 8b 4e 78          	mov    0x78(%r14),%rcx
 105f56f:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105f573:	48 39 d0             	cmp    %rdx,%rax
 105f576:	0f 83 c6 08 00 00    	jae    105fe42 <my.interpreter::execute+0x13c2>
 105f57c:	48 89 c6             	mov    %rax,%rsi
 105f57f:	48 c1 e6 04          	shl    $0x4,%rsi
 105f583:	c5 f8 10 44 31 20    	vmovups 0x20(%rcx,%rsi,1),%xmm0
 105f589:	48 c7 45 00 00 00 00 	movq   $0x0,0x0(%rbp)
 105f590:	00 
 105f591:	48 c7 45 08 01 00 00 	movq   $0x1,0x8(%rbp)
 105f598:	00 
 105f599:	4c 89 ad 00 01 00 00 	mov    %r13,0x100(%rbp)
 105f5a0:	c5 f8 54 05 38 4e fa 	vandps -0x5b1c8(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105f5a7:	ff 
 105f5a8:	c5 f8 11 85 08 01 00 	vmovups %xmm0,0x108(%rbp)
 105f5af:	00 
 105f5b0:	e9 e5 04 00 00       	jmp    105fa9a <my.interpreter::execute+0x101a>
 105f5b5:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
 105f5b9:	48 8b 44 24 20       	mov    0x20(%rsp),%rax
 105f5be:	c5 f8 11 00          	vmovups %xmm0,(%rax)
 105f5c2:	4c 89 90 00 01 00 00 	mov    %r10,0x100(%rax)
 105f5c9:	48 89 a8 08 01 00 00 	mov    %rbp,0x108(%rax)
 105f5d0:	48 89 c5             	mov    %rax,%rbp
 105f5d3:	4c 89 a8 10 01 00 00 	mov    %r13,0x110(%rax)
 105f5da:	e9 bb 04 00 00       	jmp    105fa9a <my.interpreter::execute+0x101a>
 105f5df:	41 83 fc 01          	cmp    $0x1,%r12d
 105f5e3:	0f 85 8f 04 00 00    	jne    105fa78 <my.interpreter::execute+0xff8>
 105f5e9:	48 8d bc 24 50 06 00 	lea    0x650(%rsp),%rdi
 105f5f0:	00 
 105f5f1:	4c 89 fe             	mov    %r15,%rsi
 105f5f4:	48 89 da             	mov    %rbx,%rdx
 105f5f7:	4c 8b 04 24          	mov    (%rsp),%r8
 105f5fb:	4d 89 f1             	mov    %r14,%r9
 105f5fe:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105f605:	ff 74 24 20          	push   0x20(%rsp)
 105f609:	41 53                	push   %r11
 105f60b:	41 52                	push   %r10
 105f60d:	41 55                	push   %r13
 105f60f:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105f616:	e8 65 f4 ff ff       	call   105ea80 <my.interpreter::execute>
 105f61b:	48 83 c4 30          	add    $0x30,%rsp
 105f61f:	0f b6 84 24 50 06 00 	movzbl 0x650(%rsp),%eax
 105f626:	00 
 105f627:	c5 f8 10 84 24 58 06 	vmovups 0x658(%rsp),%xmm0
 105f62e:	00 00 
 105f630:	48 8b 8c 24 50 07 00 	mov    0x750(%rsp),%rcx
 105f637:	00 
 105f638:	0f b6 94 24 58 07 00 	movzbl 0x758(%rsp),%edx
 105f63f:	00 
 105f640:	48 8b b4 24 60 07 00 	mov    0x760(%rsp),%rsi
 105f647:	00 
 105f648:	48 83 f8 01          	cmp    $0x1,%rax
 105f64c:	0f 84 d4 06 00 00    	je     105fd26 <my.interpreter::execute+0x12a6>
 105f652:	48 89 45 00          	mov    %rax,0x0(%rbp)
 105f656:	c5 f8 11 45 08       	vmovups %xmm0,0x8(%rbp)
 105f65b:	48 89 8d 00 01 00 00 	mov    %rcx,0x100(%rbp)
 105f662:	48 89 95 08 01 00 00 	mov    %rdx,0x108(%rbp)
 105f669:	48 89 b5 10 01 00 00 	mov    %rsi,0x110(%rbp)
 105f670:	e9 25 04 00 00       	jmp    105fa9a <my.interpreter::execute+0x101a>
 105f675:	48 8b 6c 24 20       	mov    0x20(%rsp),%rbp
 105f67a:	48 c7 45 00 00 00 00 	movq   $0x0,0x0(%rbp)
 105f681:	00 
 105f682:	48 c7 45 08 01 00 00 	movq   $0x1,0x8(%rbp)
 105f689:	00 
 105f68a:	4c 89 ad 00 01 00 00 	mov    %r13,0x100(%rbp)
 105f691:	4c 89 85 08 01 00 00 	mov    %r8,0x108(%rbp)
 105f698:	e9 f6 03 00 00       	jmp    105fa93 <my.interpreter::execute+0x1013>
 105f69d:	48 01 c2             	add    %rax,%rdx
 105f6a0:	4c 8b 62 08          	mov    0x8(%rdx),%r12
 105f6a4:	49 8b 44 24 08       	mov    0x8(%r12),%rax
 105f6a9:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105f6ae:	48 85 c0             	test   %rax,%rax
 105f6b1:	0f 84 e5 f4 ff ff    	je     105eb9c <my.interpreter::execute+0x11c>
 105f6b7:	31 ed                	xor    %ebp,%ebp
 105f6b9:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
 105f6c0:	40 0f b6 c6          	movzbl %sil,%eax
 105f6c4:	48 8d bc 24 d8 00 00 	lea    0xd8(%rsp),%rdi
 105f6cb:	00 
 105f6cc:	4c 89 fe             	mov    %r15,%rsi
 105f6cf:	48 89 da             	mov    %rbx,%rdx
 105f6d2:	4c 8b 04 24          	mov    (%rsp),%r8
 105f6d6:	4d 89 f1             	mov    %r14,%r9
 105f6d9:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105f6e0:	41 ff 74 ec 20       	push   0x20(%r12,%rbp,8)
 105f6e5:	41 52                	push   %r10
 105f6e7:	50                   	push   %rax
 105f6e8:	41 55                	push   %r13
 105f6ea:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105f6f1:	e8 8a f3 ff ff       	call   105ea80 <my.interpreter::execute>
 105f6f6:	48 83 c4 30          	add    $0x30,%rsp
 105f6fa:	48 8b 84 24 e0 00 00 	mov    0xe0(%rsp),%rax
 105f701:	00 
 105f702:	4c 8b ac 24 d8 01 00 	mov    0x1d8(%rsp),%r13
 105f709:	00 
 105f70a:	0f b6 b4 24 e0 01 00 	movzbl 0x1e0(%rsp),%esi
 105f711:	00 
 105f712:	4c 8b 94 24 e8 01 00 	mov    0x1e8(%rsp),%r10
 105f719:	00 
 105f71a:	80 bc 24 d8 00 00 00 	cmpb   $0x1,0xd8(%rsp)
 105f721:	01 
 105f722:	0f 84 19 06 00 00    	je     105fd41 <my.interpreter::execute+0x12c1>
 105f728:	3c 01                	cmp    $0x1,%al
 105f72a:	0f 84 7f 03 00 00    	je     105faaf <my.interpreter::execute+0x102f>
 105f730:	48 ff c5             	inc    %rbp
 105f733:	48 39 6c 24 10       	cmp    %rbp,0x10(%rsp)
 105f738:	48 8b 4c 24 30       	mov    0x30(%rsp),%rcx
 105f73d:	75 81                	jne    105f6c0 <my.interpreter::execute+0xc40>
 105f73f:	e9 58 f4 ff ff       	jmp    105eb9c <my.interpreter::execute+0x11c>
 105f744:	31 db                	xor    %ebx,%ebx
 105f746:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105f74d:	48 89 c6             	mov    %rax,%rsi
 105f750:	48 ff ce             	dec    %rsi
 105f753:	0f 80 00 0a 00 00    	jo     1060159 <my.interpreter::execute+0x16d9>
 105f759:	49 8b 46 78          	mov    0x78(%r14),%rax
 105f75d:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105f761:	48 39 d6             	cmp    %rdx,%rsi
 105f764:	0f 83 2b 08 00 00    	jae    105ff95 <my.interpreter::execute+0x1515>
 105f76a:	48 89 f1             	mov    %rsi,%rcx
 105f76d:	4c 89 44 24 28       	mov    %r8,0x28(%rsp)
 105f772:	48 c1 e1 04          	shl    $0x4,%rcx
 105f776:	80 7c 08 20 03       	cmpb   $0x3,0x20(%rax,%rcx,1)
 105f77b:	0f 85 c0 03 00 00    	jne    105fb41 <my.interpreter::execute+0x10c1>
 105f781:	4c 8b 7c 08 28       	mov    0x28(%rax,%rcx,1),%r15
 105f786:	49 8b 06             	mov    (%r14),%rax
 105f789:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105f78d:	4c 89 f9             	mov    %r15,%rcx
 105f790:	49 39 d7             	cmp    %rdx,%r15
 105f793:	0f 83 1e 08 00 00    	jae    105ffb7 <my.interpreter::execute+0x1537>
 105f799:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 105f79d:	83 7c 08 20 06       	cmpl   $0x6,0x20(%rax,%rcx,1)
 105f7a2:	0f 85 99 03 00 00    	jne    105fb41 <my.interpreter::execute+0x10c1>
 105f7a8:	48 89 7c 24 48       	mov    %rdi,0x48(%rsp)
 105f7ad:	48 8d bc 24 b0 0a 00 	lea    0xab0(%rsp),%rdi
 105f7b4:	00 
 105f7b5:	4c 89 f6             	mov    %r14,%rsi
 105f7b8:	48 8b 54 24 18       	mov    0x18(%rsp),%rdx
 105f7bd:	e8 6e 4b 00 00       	call   1064330 <my.heap::allocate_class>
 105f7c2:	48 8b 8c 24 b0 0a 00 	mov    0xab0(%rsp),%rcx
 105f7c9:	00 
 105f7ca:	49 8b 46 78          	mov    0x78(%r14),%rax
 105f7ce:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105f7d5:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105f7d9:	48 39 d6             	cmp    %rdx,%rsi
 105f7dc:	0f 83 c9 06 00 00    	jae    105feab <my.interpreter::execute+0x142b>
 105f7e2:	48 89 f7             	mov    %rsi,%rdi
 105f7e5:	48 c1 e7 04          	shl    $0x4,%rdi
 105f7e9:	48 c7 44 38 20 03 00 	movq   $0x3,0x20(%rax,%rdi,1)
 105f7f0:	00 00 
 105f7f2:	48 89 4c 38 28       	mov    %rcx,0x28(%rax,%rdi,1)
 105f7f7:	49 89 46 78          	mov    %rax,0x78(%r14)
 105f7fb:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105f802:	48 89 f2             	mov    %rsi,%rdx
 105f805:	48 ff c2             	inc    %rdx
 105f808:	0f 80 b4 08 00 00    	jo     10600c2 <my.interpreter::execute+0x1642>
 105f80e:	48 8d 0c 38          	lea    (%rax,%rdi,1),%rcx
 105f812:	48 83 c1 20          	add    $0x20,%rcx
 105f816:	49 89 96 80 00 00 00 	mov    %rdx,0x80(%r14)
 105f81d:	0f b6 01             	movzbl (%rcx),%eax
 105f820:	83 f8 03             	cmp    $0x3,%eax
 105f823:	0f 85 e9 07 00 00    	jne    1060012 <my.interpreter::execute+0x1592>
 105f829:	48 8b 71 08          	mov    0x8(%rcx),%rsi
 105f82d:	49 83 ff ff          	cmp    $0xffffffffffffffff,%r15
 105f831:	48 89 6c 24 20       	mov    %rbp,0x20(%rsp)
 105f836:	4c 89 6c 24 58       	mov    %r13,0x58(%rsp)
 105f83b:	4c 89 7c 24 50       	mov    %r15,0x50(%rsp)
 105f840:	48 89 34 24          	mov    %rsi,(%rsp)
 105f844:	74 7c                	je     105f8c2 <my.interpreter::execute+0xe42>
 105f846:	4c 89 f7             	mov    %r14,%rdi
 105f849:	4c 89 fa             	mov    %r15,%rdx
 105f84c:	e8 5f b2 00 00       	call   106aab0 <my.heap::inherit_class_methods>
 105f851:	49 8b 96 a8 00 00 00 	mov    0xa8(%r14),%rdx
 105f858:	48 8d bc 24 20 0e 00 	lea    0xe20(%rsp),%rdi
 105f85f:	00 
 105f860:	b9 01 00 00 00       	mov    $0x1,%ecx
 105f865:	4c 89 f6             	mov    %r14,%rsi
 105f868:	e8 43 ce 00 00       	call   106c6b0 <my.interpreter::new_env>
 105f86d:	4c 8b a4 24 20 0e 00 	mov    0xe20(%rsp),%r12
 105f874:	00 
 105f875:	4c 89 f7             	mov    %r14,%rdi
 105f878:	4c 89 e6             	mov    %r12,%rsi
 105f87b:	31 d2                	xor    %edx,%edx
 105f87d:	b9 03 00 00 00       	mov    $0x3,%ecx
 105f882:	4d 89 f8             	mov    %r15,%r8
 105f885:	e8 b6 d0 00 00       	call   106c940 <my.heap::set_env_slot>
 105f88a:	4d 8b be a8 00 00 00 	mov    0xa8(%r14),%r15
 105f891:	49 8b 86 b0 00 00 00 	mov    0xb0(%r14),%rax
 105f898:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105f89c:	48 3b 48 10          	cmp    0x10(%rax),%rcx
 105f8a0:	0f 83 49 06 00 00    	jae    105feef <my.interpreter::execute+0x146f>
 105f8a6:	4c 89 7c c8 20       	mov    %r15,0x20(%rax,%rcx,8)
 105f8ab:	48 ff c1             	inc    %rcx
 105f8ae:	48 89 48 08          	mov    %rcx,0x8(%rax)
 105f8b2:	49 89 86 b0 00 00 00 	mov    %rax,0xb0(%r14)
 105f8b9:	4d 89 a6 a8 00 00 00 	mov    %r12,0xa8(%r14)
 105f8c0:	eb 07                	jmp    105f8c9 <my.interpreter::execute+0xe49>
 105f8c2:	4d 8b a6 a8 00 00 00 	mov    0xa8(%r14),%r12
 105f8c9:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105f8ce:	4c 8b 68 08          	mov    0x8(%rax),%r13
 105f8d2:	4d 85 ed             	test   %r13,%r13
 105f8d5:	48 8b 5c 24 30       	mov    0x30(%rsp),%rbx
 105f8da:	0f 84 f3 00 00 00    	je     105f9d3 <my.interpreter::execute+0xf53>
 105f8e0:	31 ed                	xor    %ebp,%ebp
 105f8e2:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105f8e9:	0f 1f 84 00 00 00 00 
 105f8f0:	00 
 105f8f1:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105f8f8:	0f 1f 84 00 00 00 00 
 105f8ff:	00 
 105f900:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105f905:	48 8b 74 e8 20       	mov    0x20(%rax,%rbp,8),%rsi
 105f90a:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 105f90e:	48 89 f0             	mov    %rsi,%rax
 105f911:	48 39 d6             	cmp    %rdx,%rsi
 105f914:	0f 83 97 00 00 00    	jae    105f9b1 <my.interpreter::execute+0xf31>
 105f91a:	48 8d 04 80          	lea    (%rax,%rax,4),%rax
 105f91e:	48 c1 e0 04          	shl    $0x4,%rax
 105f922:	4c 8b 7c 03 48       	mov    0x48(%rbx,%rax,1),%r15
 105f927:	4d 3b 7e 40          	cmp    0x40(%r14),%r15
 105f92b:	48 c7 84 24 a0 00 00 	movq   $0xa,0xa0(%rsp)
 105f932:	00 0a 00 00 00 
 105f937:	48 89 b4 24 a8 00 00 	mov    %rsi,0xa8(%rsp)
 105f93e:	00 
 105f93f:	4c 89 bc 24 b0 00 00 	mov    %r15,0xb0(%rsp)
 105f946:	00 
 105f947:	4c 89 a4 24 b8 00 00 	mov    %r12,0xb8(%rsp)
 105f94e:	00 
 105f94f:	0f 94 84 24 c0 00 00 	sete   0xc0(%rsp)
 105f956:	00 
 105f957:	48 8d bc 24 58 0d 00 	lea    0xd58(%rsp),%rdi
 105f95e:	00 
 105f95f:	4c 89 f6             	mov    %r14,%rsi
 105f962:	48 8d 94 24 a0 00 00 	lea    0xa0(%rsp),%rdx
 105f969:	00 
 105f96a:	e8 f1 af ff ff       	call   105a960 <my.heap::allocate>
 105f96f:	4c 8b a4 24 58 0d 00 	mov    0xd58(%rsp),%r12
 105f976:	00 
 105f977:	4c 89 f7             	mov    %r14,%rdi
 105f97a:	4c 89 fe             	mov    %r15,%rsi
 105f97d:	e8 5e a4 00 00       	call   1069de0 <my.heap::string_hash>
 105f982:	4c 89 f7             	mov    %r14,%rdi
 105f985:	48 8b 34 24          	mov    (%rsp),%rsi
 105f989:	4c 89 fa             	mov    %r15,%rdx
 105f98c:	89 c1                	mov    %eax,%ecx
 105f98e:	41 b8 03 00 00 00    	mov    $0x3,%r8d
 105f994:	4d 89 e1             	mov    %r12,%r9
 105f997:	e8 f4 b2 00 00       	call   106ac90 <my.heap::set_class_method>
 105f99c:	4d 8b a6 a8 00 00 00 	mov    0xa8(%r14),%r12
 105f9a3:	48 ff c5             	inc    %rbp
 105f9a6:	49 39 ed             	cmp    %rbp,%r13
 105f9a9:	0f 85 51 ff ff ff    	jne    105f900 <my.interpreter::execute+0xe80>
 105f9af:	eb 22                	jmp    105f9d3 <my.interpreter::execute+0xf53>
 105f9b1:	48 89 f0             	mov    %rsi,%rax
 105f9b4:	48 c1 f8 3f          	sar    $0x3f,%rax
 105f9b8:	48 21 d0             	and    %rdx,%rax
 105f9bb:	48 01 f0             	add    %rsi,%rax
 105f9be:	48 39 d0             	cmp    %rdx,%rax
 105f9c1:	0f 82 53 ff ff ff    	jb     105f91a <my.interpreter::execute+0xe9a>
 105f9c7:	48 8d 3d d2 35 02 00 	lea    0x235d2(%rip),%rdi        # 1082fa0 <core_durable_error.verbs+0x2e50>
 105f9ce:	e8 ad 52 fc ff       	call   1024c80 <myl_core_trap>
 105f9d3:	48 8b 5c 24 50       	mov    0x50(%rsp),%rbx
 105f9d8:	48 83 fb ff          	cmp    $0xffffffffffffffff,%rbx
 105f9dc:	48 8b 6c 24 20       	mov    0x20(%rsp),%rbp
 105f9e1:	4c 8b 6c 24 58       	mov    0x58(%rsp),%r13
 105f9e6:	74 27                	je     105fa0f <my.interpreter::execute+0xf8f>
 105f9e8:	49 8b 86 b0 00 00 00 	mov    0xb0(%r14),%rax
 105f9ef:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105f9f3:	48 85 c9             	test   %rcx,%rcx
 105f9f6:	0f 84 17 07 00 00    	je     1060113 <my.interpreter::execute+0x1693>
 105f9fc:	48 8b 54 c8 18       	mov    0x18(%rax,%rcx,8),%rdx
 105fa01:	48 ff c9             	dec    %rcx
 105fa04:	48 89 48 08          	mov    %rcx,0x8(%rax)
 105fa08:	49 89 96 a8 00 00 00 	mov    %rdx,0xa8(%r14)
 105fa0f:	4c 89 f7             	mov    %r14,%rdi
 105fa12:	48 8b 74 24 18       	mov    0x18(%rsp),%rsi
 105fa17:	48 8b 54 24 60       	mov    0x60(%rsp),%rdx
 105fa1c:	e8 5f 82 00 00       	call   1067c80 <my.interpreter::define>
 105fa21:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105fa28:	48 89 c6             	mov    %rax,%rsi
 105fa2b:	48 ff ce             	dec    %rsi
 105fa2e:	0f 80 b7 06 00 00    	jo     10600eb <my.interpreter::execute+0x166b>
 105fa34:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105fa3b:	49 8b 46 78          	mov    0x78(%r14),%rax
 105fa3f:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105fa43:	48 39 d6             	cmp    %rdx,%rsi
 105fa46:	4c 8b 5c 24 48       	mov    0x48(%rsp),%r11
 105fa4b:	48 8b 7c 24 28       	mov    0x28(%rsp),%rdi
 105fa50:	0f 83 77 04 00 00    	jae    105fecd <my.interpreter::execute+0x144d>
 105fa56:	48 83 fb ff          	cmp    $0xffffffffffffffff,%rbx
 105fa5a:	74 1c                	je     105fa78 <my.interpreter::execute+0xff8>
 105fa5c:	48 89 f0             	mov    %rsi,%rax
 105fa5f:	48 ff c8             	dec    %rax
 105fa62:	0f 80 bb 06 00 00    	jo     1060123 <my.interpreter::execute+0x16a3>
 105fa68:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 105fa6f:	48 39 d0             	cmp    %rdx,%rax
 105fa72:	0f 83 8d 04 00 00    	jae    105ff05 <my.interpreter::execute+0x1485>
 105fa78:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
 105fa7c:	c5 f8 11 45 00       	vmovups %xmm0,0x0(%rbp)
 105fa81:	4c 89 ad 00 01 00 00 	mov    %r13,0x100(%rbp)
 105fa88:	40 0f b6 c7          	movzbl %dil,%eax
 105fa8c:	48 89 85 08 01 00 00 	mov    %rax,0x108(%rbp)
 105fa93:	4c 89 9d 10 01 00 00 	mov    %r11,0x110(%rbp)
 105fa9a:	48 89 e8             	mov    %rbp,%rax
 105fa9d:	48 81 c4 e8 0e 00 00 	add    $0xee8,%rsp
 105faa4:	5b                   	pop    %rbx
 105faa5:	41 5c                	pop    %r12
 105faa7:	41 5d                	pop    %r13
 105faa9:	41 5e                	pop    %r14
 105faab:	41 5f                	pop    %r15
 105faad:	5d                   	pop    %rbp
 105faae:	c3                   	ret
 105faaf:	48 89 f3             	mov    %rsi,%rbx
 105fab2:	b8 01 00 00 00       	mov    $0x1,%eax
 105fab7:	31 f6                	xor    %esi,%esi
 105fab9:	31 d2                	xor    %edx,%edx
 105fabb:	e9 e9 f0 ff ff       	jmp    105eba9 <my.interpreter::execute+0x129>
 105fac0:	c5 f8 10 84 24 88 08 	vmovups 0x888(%rsp),%xmm0
 105fac7:	00 00 
 105fac9:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105face:	48 8d 3d bb 17 02 00 	lea    0x217bb(%rip),%rdi        # 1081290 <core_durable_error.verbs+0x1140>
 105fad5:	4c 89 d8             	mov    %r11,%rax
 105fad8:	e8 e3 75 ff ff       	call   10570c0 <myl_core_err_trace_append_preserve_most>
 105fadd:	48 c7 45 00 01 00 00 	movq   $0x1,0x0(%rbp)
 105fae4:	00 
 105fae5:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 105faea:	c5 f8 11 45 08       	vmovups %xmm0,0x8(%rbp)
 105faef:	4c 89 ad 00 01 00 00 	mov    %r13,0x100(%rbp)
 105faf6:	4c 89 95 08 01 00 00 	mov    %r10,0x108(%rbp)
 105fafd:	48 89 85 10 01 00 00 	mov    %rax,0x110(%rbp)
 105fb04:	eb 94                	jmp    105fa9a <my.interpreter::execute+0x101a>
 105fb06:	41 0f b6 c7          	movzbl %r15b,%eax
 105fb0a:	c5 f8 10 84 24 40 05 	vmovups 0x540(%rsp),%xmm0
 105fb11:	00 00 
 105fb13:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105fb18:	48 8d 3d 01 18 02 00 	lea    0x21801(%rip),%rdi        # 1081320 <core_durable_error.verbs+0x11d0>
 105fb1f:	e9 23 01 00 00       	jmp    105fc47 <my.interpreter::execute+0x11c7>
 105fb24:	48 8d 3d 15 34 02 00 	lea    0x23415(%rip),%rdi        # 1082f40 <core_durable_error.verbs+0x2df0>
 105fb2b:	e8 90 75 ff ff       	call   10570c0 <myl_core_err_trace_append_preserve_most>
 105fb30:	48 8d 3d 39 16 02 00 	lea    0x21639(%rip),%rdi        # 1081170 <core_durable_error.verbs+0x1020>
 105fb37:	e8 84 75 ff ff       	call   10570c0 <myl_core_err_trace_append_preserve_most>
 105fb3c:	e9 9d f0 ff ff       	jmp    105ebde <my.interpreter::execute+0x15e>
 105fb41:	49 89 fe             	mov    %rdi,%r14
 105fb44:	48 8d 3d 35 2d fb ff 	lea    -0x4d2cb(%rip),%rdi        # 1012880 <core_number_pairs+0xb620>
 105fb4b:	e8 30 4c fc ff       	call   1024780 <myl_core_owned_octets_copy>
 105fb50:	48 8d 3d 29 63 02 00 	lea    0x26329(%rip),%rdi        # 1085e80 <core_durable_error.verbs+0x5d30>
 105fb57:	e8 24 75 ff ff       	call   1057080 <myl_core_err_trace_origin_preserve_most>
 105fb5c:	4c 8b 44 24 28       	mov    0x28(%rsp),%r8
 105fb61:	e9 31 01 00 00       	jmp    105fc97 <my.interpreter::execute+0x1217>
 105fb66:	40 0f b6 c7          	movzbl %dil,%eax
 105fb6a:	c5 f8 10 84 24 a0 09 	vmovups 0x9a0(%rsp),%xmm0
 105fb71:	00 00 
 105fb73:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105fb78:	48 8d 3d b1 16 02 00 	lea    0x216b1(%rip),%rdi        # 1081230 <core_durable_error.verbs+0x10e0>
 105fb7f:	4c 89 d9             	mov    %r11,%rcx
 105fb82:	e8 39 75 ff ff       	call   10570c0 <myl_core_err_trace_append_preserve_most>
 105fb87:	48 c7 45 00 01 00 00 	movq   $0x1,0x0(%rbp)
 105fb8e:	00 
 105fb8f:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 105fb94:	c5 f8 11 45 08       	vmovups %xmm0,0x8(%rbp)
 105fb99:	4c 89 ad 00 01 00 00 	mov    %r13,0x100(%rbp)
 105fba0:	48 89 85 08 01 00 00 	mov    %rax,0x108(%rbp)
 105fba7:	48 89 8d 10 01 00 00 	mov    %rcx,0x110(%rbp)
 105fbae:	e9 e7 fe ff ff       	jmp    105fa9a <my.interpreter::execute+0x101a>
 105fbb3:	c5 f8 10 84 24 10 03 	vmovups 0x310(%rsp),%xmm0
 105fbba:	00 00 
 105fbbc:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105fbc1:	48 8d 3d e8 17 02 00 	lea    0x217e8(%rip),%rdi        # 10813b0 <core_durable_error.verbs+0x1260>
 105fbc8:	e8 f3 74 ff ff       	call   10570c0 <myl_core_err_trace_append_preserve_most>
 105fbcd:	48 8b 44 24 20       	mov    0x20(%rsp),%rax
 105fbd2:	48 c7 00 01 00 00 00 	movq   $0x1,(%rax)
 105fbd9:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 105fbde:	c5 f8 11 40 08       	vmovups %xmm0,0x8(%rax)
 105fbe3:	e9 da f9 ff ff       	jmp    105f5c2 <my.interpreter::execute+0xb42>
 105fbe8:	48 8b 8c 24 00 02 00 	mov    0x200(%rsp),%rcx
 105fbef:	00 
 105fbf0:	48 8d 3d e9 17 02 00 	lea    0x217e9(%rip),%rdi        # 10813e0 <core_durable_error.verbs+0x1290>
 105fbf7:	4c 89 da             	mov    %r11,%rdx
 105fbfa:	e8 c1 74 ff ff       	call   10570c0 <myl_core_err_trace_append_preserve_most>
 105fbff:	48 8b 6c 24 20       	mov    0x20(%rsp),%rbp
 105fc04:	48 c7 45 00 01 00 00 	movq   $0x1,0x0(%rbp)
 105fc0b:	00 
 105fc0c:	48 89 45 08          	mov    %rax,0x8(%rbp)
 105fc10:	48 89 4d 10          	mov    %rcx,0x10(%rbp)
 105fc14:	4c 89 ad 00 01 00 00 	mov    %r13,0x100(%rbp)
 105fc1b:	4c 89 85 08 01 00 00 	mov    %r8,0x108(%rbp)
 105fc22:	48 89 95 10 01 00 00 	mov    %rdx,0x110(%rbp)
 105fc29:	e9 6c fe ff ff       	jmp    105fa9a <my.interpreter::execute+0x101a>
 105fc2e:	41 0f b6 c7          	movzbl %r15b,%eax
 105fc32:	c5 f8 10 84 24 28 04 	vmovups 0x428(%rsp),%xmm0
 105fc39:	00 00 
 105fc3b:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105fc40:	48 8d 3d 39 17 02 00 	lea    0x21739(%rip),%rdi        # 1081380 <core_durable_error.verbs+0x1230>
 105fc47:	e8 74 74 ff ff       	call   10570c0 <myl_core_err_trace_append_preserve_most>
 105fc4c:	48 c7 45 00 01 00 00 	movq   $0x1,0x0(%rbp)
 105fc53:	00 
 105fc54:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 105fc59:	c5 f8 11 45 08       	vmovups %xmm0,0x8(%rbp)
 105fc5e:	4c 89 ad 00 01 00 00 	mov    %r13,0x100(%rbp)
 105fc65:	48 89 85 08 01 00 00 	mov    %rax,0x108(%rbp)
 105fc6c:	48 89 9d 10 01 00 00 	mov    %rbx,0x110(%rbp)
 105fc73:	e9 22 fe ff ff       	jmp    105fa9a <my.interpreter::execute+0x101a>
 105fc78:	49 89 fe             	mov    %rdi,%r14
 105fc7b:	48 8b 84 24 e0 00 00 	mov    0xe0(%rsp),%rax
 105fc82:	00 
 105fc83:	48 8b 9c 24 e8 00 00 	mov    0xe8(%rsp),%rbx
 105fc8a:	00 
 105fc8b:	48 8d 3d 8e 61 02 00 	lea    0x2618e(%rip),%rdi        # 1085e20 <core_durable_error.verbs+0x5cd0>
 105fc92:	e8 29 74 ff ff       	call   10570c0 <myl_core_err_trace_append_preserve_most>
 105fc97:	48 8d 3d d2 32 02 00 	lea    0x232d2(%rip),%rdi        # 1082f70 <core_durable_error.verbs+0x2e20>
 105fc9e:	e8 1d 74 ff ff       	call   10570c0 <myl_core_err_trace_append_preserve_most>
 105fca3:	48 8d 3d f6 14 02 00 	lea    0x214f6(%rip),%rdi        # 10811a0 <core_durable_error.verbs+0x1050>
 105fcaa:	e8 11 74 ff ff       	call   10570c0 <myl_core_err_trace_append_preserve_most>
 105fcaf:	48 c7 45 00 01 00 00 	movq   $0x1,0x0(%rbp)
 105fcb6:	00 
 105fcb7:	48 89 45 08          	mov    %rax,0x8(%rbp)
 105fcbb:	48 89 5d 10          	mov    %rbx,0x10(%rbp)
 105fcbf:	4c 89 ad 00 01 00 00 	mov    %r13,0x100(%rbp)
 105fcc6:	4c 89 85 08 01 00 00 	mov    %r8,0x108(%rbp)
 105fccd:	4c 89 b5 10 01 00 00 	mov    %r14,0x110(%rbp)
 105fcd4:	e9 c1 fd ff ff       	jmp    105fa9a <my.interpreter::execute+0x101a>
 105fcd9:	c5 f8 10 84 24 80 0b 	vmovups 0xb80(%rsp),%xmm0
 105fce0:	00 00 
 105fce2:	c5 f8 29 44 24 30    	vmovaps %xmm0,0x30(%rsp)
 105fce8:	c5 f8 10 84 24 80 0c 	vmovups 0xc80(%rsp),%xmm0
 105fcef:	00 00 
 105fcf1:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105fcf6:	48 8d 3d 53 16 02 00 	lea    0x21653(%rip),%rdi        # 1081350 <core_durable_error.verbs+0x1200>
 105fcfd:	e8 be 73 ff ff       	call   10570c0 <myl_core_err_trace_append_preserve_most>
 105fd02:	48 c7 45 00 01 00 00 	movq   $0x1,0x0(%rbp)
 105fd09:	00 
 105fd0a:	c5 f8 28 44 24 30    	vmovaps 0x30(%rsp),%xmm0
 105fd10:	c5 f8 11 45 08       	vmovups %xmm0,0x8(%rbp)
 105fd15:	4c 89 ad 00 01 00 00 	mov    %r13,0x100(%rbp)
 105fd1c:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 105fd21:	e9 7a f8 ff ff       	jmp    105f5a0 <my.interpreter::execute+0xb20>
 105fd26:	48 8d 3d c3 15 02 00 	lea    0x215c3(%rip),%rdi        # 10812f0 <core_durable_error.verbs+0x11a0>
 105fd2d:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105fd32:	e8 89 73 ff ff       	call   10570c0 <myl_core_err_trace_append_preserve_most>
 105fd37:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 105fd3c:	e9 11 f9 ff ff       	jmp    105f652 <my.interpreter::execute+0xbd2>
 105fd41:	48 89 f3             	mov    %rsi,%rbx
 105fd44:	48 8b 8c 24 e8 00 00 	mov    0xe8(%rsp),%rcx
 105fd4b:	00 
 105fd4c:	48 8d 3d 6d 60 02 00 	lea    0x2606d(%rip),%rdi        # 1085dc0 <core_durable_error.verbs+0x5c70>
 105fd53:	e8 68 73 ff ff       	call   10570c0 <myl_core_err_trace_append_preserve_most>
 105fd58:	ba 01 00 00 00       	mov    $0x1,%edx
 105fd5d:	40 b6 01             	mov    $0x1,%sil
 105fd60:	e9 44 ee ff ff       	jmp    105eba9 <my.interpreter::execute+0x129>
 105fd65:	4c 89 e0             	mov    %r12,%rax
 105fd68:	48 c1 f8 3f          	sar    $0x3f,%rax
 105fd6c:	48 21 d0             	and    %rdx,%rax
 105fd6f:	4c 01 e0             	add    %r12,%rax
 105fd72:	48 39 d0             	cmp    %rdx,%rax
 105fd75:	0f 82 3e ed ff ff    	jb     105eab9 <my.interpreter::execute+0x39>
 105fd7b:	48 8d 3d be 13 02 00 	lea    0x213be(%rip),%rdi        # 1081140 <core_durable_error.verbs+0xff0>
 105fd82:	4c 89 e6             	mov    %r12,%rsi
 105fd85:	e8 f6 4e fc ff       	call   1024c80 <myl_core_trap>
 105fd8a:	48 89 c1             	mov    %rax,%rcx
 105fd8d:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105fd91:	48 21 d1             	and    %rdx,%rcx
 105fd94:	48 01 c1             	add    %rax,%rcx
 105fd97:	48 39 d1             	cmp    %rdx,%rcx
 105fd9a:	0f 82 c2 ef ff ff    	jb     105ed62 <my.interpreter::execute+0x2e2>
 105fda0:	48 8d 3d 29 14 02 00 	lea    0x21429(%rip),%rdi        # 10811d0 <core_durable_error.verbs+0x1080>
 105fda7:	48 89 c6             	mov    %rax,%rsi
 105fdaa:	e8 d1 4e fc ff       	call   1024c80 <myl_core_trap>
 105fdaf:	48 89 f0             	mov    %rsi,%rax
 105fdb2:	48 c1 f8 3f          	sar    $0x3f,%rax
 105fdb6:	48 21 d0             	and    %rdx,%rax
 105fdb9:	48 01 f0             	add    %rsi,%rax
 105fdbc:	48 39 d0             	cmp    %rdx,%rax
 105fdbf:	0f 82 77 f0 ff ff    	jb     105ee3c <my.interpreter::execute+0x3bc>
 105fdc5:	48 8d 3d 94 14 02 00 	lea    0x21494(%rip),%rdi        # 1081260 <core_durable_error.verbs+0x1110>
 105fdcc:	e8 af 4e fc ff       	call   1024c80 <myl_core_trap>
 105fdd1:	48 89 74 24 18       	mov    %rsi,0x18(%rsp)
 105fdd6:	be 08 00 00 00       	mov    $0x8,%esi
 105fddb:	48 89 c7             	mov    %rax,%rdi
 105fdde:	48 89 54 24 10       	mov    %rdx,0x10(%rsp)
 105fde3:	e8 18 34 fc ff       	call   1023200 <myl_core_list_grow>
 105fde8:	48 8b 74 24 18       	mov    0x18(%rsp),%rsi
 105fded:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 105fdf2:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105fdf6:	e9 48 ed ff ff       	jmp    105eb43 <my.interpreter::execute+0xc3>
 105fdfb:	4c 89 e0             	mov    %r12,%rax
 105fdfe:	48 c1 f8 3f          	sar    $0x3f,%rax
 105fe02:	48 21 d0             	and    %rdx,%rax
 105fe05:	4c 01 e0             	add    %r12,%rax
 105fe08:	48 39 d0             	cmp    %rdx,%rax
 105fe0b:	0f 82 71 ed ff ff    	jb     105eb82 <my.interpreter::execute+0x102>
 105fe11:	48 8d 3d 78 5f 02 00 	lea    0x25f78(%rip),%rdi        # 1085d90 <core_durable_error.verbs+0x5c40>
 105fe18:	4c 89 e6             	mov    %r12,%rsi
 105fe1b:	e8 60 4e fc ff       	call   1024c80 <myl_core_trap>
 105fe20:	48 89 f7             	mov    %rsi,%rdi
 105fe23:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105fe27:	48 21 d7             	and    %rdx,%rdi
 105fe2a:	48 01 f7             	add    %rsi,%rdi
 105fe2d:	48 39 d7             	cmp    %rdx,%rdi
 105fe30:	0f 82 7a f0 ff ff    	jb     105eeb0 <my.interpreter::execute+0x430>
 105fe36:	48 8d 3d 33 16 02 00 	lea    0x21633(%rip),%rdi        # 1081470 <core_durable_error.verbs+0x1320>
 105fe3d:	e8 3e 4e fc ff       	call   1024c80 <myl_core_trap>
 105fe42:	48 89 c6             	mov    %rax,%rsi
 105fe45:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105fe49:	48 21 d6             	and    %rdx,%rsi
 105fe4c:	48 01 c6             	add    %rax,%rsi
 105fe4f:	48 39 d6             	cmp    %rdx,%rsi
 105fe52:	0f 82 27 f7 ff ff    	jb     105f57f <my.interpreter::execute+0xaff>
 105fe58:	48 8d 3d 61 17 02 00 	lea    0x21761(%rip),%rdi        # 10815c0 <core_durable_error.verbs+0x1470>
 105fe5f:	48 89 c6             	mov    %rax,%rsi
 105fe62:	e8 19 4e fc ff       	call   1024c80 <myl_core_trap>
 105fe67:	49 89 f0             	mov    %rsi,%r8
 105fe6a:	49 c1 f8 3f          	sar    $0x3f,%r8
 105fe6e:	49 21 d0             	and    %rdx,%r8
 105fe71:	49 01 f0             	add    %rsi,%r8
 105fe74:	49 39 d0             	cmp    %rdx,%r8
 105fe77:	0f 82 34 ee ff ff    	jb     105ecb1 <my.interpreter::execute+0x231>
 105fe7d:	48 8d 3d 7c 16 02 00 	lea    0x2167c(%rip),%rdi        # 1081500 <core_durable_error.verbs+0x13b0>
 105fe84:	e8 f7 4d fc ff       	call   1024c80 <myl_core_trap>
 105fe89:	48 89 f7             	mov    %rsi,%rdi
 105fe8c:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105fe90:	48 21 d7             	and    %rdx,%rdi
 105fe93:	48 01 f7             	add    %rsi,%rdi
 105fe96:	48 39 d7             	cmp    %rdx,%rdi
 105fe99:	0f 82 ca f2 ff ff    	jb     105f169 <my.interpreter::execute+0x6e9>
 105fe9f:	48 8d 3d ba 16 02 00 	lea    0x216ba(%rip),%rdi        # 1081560 <core_durable_error.verbs+0x1410>
 105fea6:	e8 d5 4d fc ff       	call   1024c80 <myl_core_trap>
 105feab:	48 89 f7             	mov    %rsi,%rdi
 105feae:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105feb2:	48 21 d7             	and    %rdx,%rdi
 105feb5:	48 01 f7             	add    %rsi,%rdi
 105feb8:	48 39 d7             	cmp    %rdx,%rdi
 105febb:	0f 82 24 f9 ff ff    	jb     105f7e5 <my.interpreter::execute+0xd65>
 105fec1:	48 8d 3d 08 31 02 00 	lea    0x23108(%rip),%rdi        # 1082fd0 <core_durable_error.verbs+0x2e80>
 105fec8:	e8 b3 4d fc ff       	call   1024c80 <myl_core_trap>
 105fecd:	48 89 f0             	mov    %rsi,%rax
 105fed0:	48 c1 f8 3f          	sar    $0x3f,%rax
 105fed4:	48 21 d0             	and    %rdx,%rax
 105fed7:	48 01 f0             	add    %rsi,%rax
 105feda:	48 39 d0             	cmp    %rdx,%rax
 105fedd:	0f 82 73 fb ff ff    	jb     105fa56 <my.interpreter::execute+0xfd6>
 105fee3:	48 8d 3d 76 31 02 00 	lea    0x23176(%rip),%rdi        # 1083060 <core_durable_error.verbs+0x2f10>
 105feea:	e8 91 4d fc ff       	call   1024c80 <myl_core_trap>
 105feef:	be 08 00 00 00       	mov    $0x8,%esi
 105fef4:	48 89 c7             	mov    %rax,%rdi
 105fef7:	e8 04 33 fc ff       	call   1023200 <myl_core_list_grow>
 105fefc:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105ff00:	e9 a1 f9 ff ff       	jmp    105f8a6 <my.interpreter::execute+0xe26>
 105ff05:	48 89 c1             	mov    %rax,%rcx
 105ff08:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105ff0c:	48 21 d1             	and    %rdx,%rcx
 105ff0f:	48 01 c1             	add    %rax,%rcx
 105ff12:	48 39 d1             	cmp    %rdx,%rcx
 105ff15:	0f 82 5d fb ff ff    	jb     105fa78 <my.interpreter::execute+0xff8>
 105ff1b:	48 8d 3d 9e 31 02 00 	lea    0x2319e(%rip),%rdi        # 10830c0 <core_durable_error.verbs+0x2f70>
 105ff22:	48 89 c6             	mov    %rax,%rsi
 105ff25:	e8 56 4d fc ff       	call   1024c80 <myl_core_trap>
 105ff2a:	48 89 f1             	mov    %rsi,%rcx
 105ff2d:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105ff31:	48 21 d1             	and    %rdx,%rcx
 105ff34:	48 01 f1             	add    %rsi,%rcx
 105ff37:	48 39 d1             	cmp    %rdx,%rcx
 105ff3a:	0f 82 31 f5 ff ff    	jb     105f471 <my.interpreter::execute+0x9f1>
 105ff40:	48 8d 3d 69 17 02 00 	lea    0x21769(%rip),%rdi        # 10816b0 <core_durable_error.verbs+0x1560>
 105ff47:	e8 34 4d fc ff       	call   1024c80 <myl_core_trap>
 105ff4c:	48 89 f1             	mov    %rsi,%rcx
 105ff4f:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105ff53:	48 21 d1             	and    %rdx,%rcx
 105ff56:	48 01 f1             	add    %rsi,%rcx
 105ff59:	48 39 d1             	cmp    %rdx,%rcx
 105ff5c:	0f 82 cb f5 ff ff    	jb     105f52d <my.interpreter::execute+0xaad>
 105ff62:	48 8d 3d 87 16 02 00 	lea    0x21687(%rip),%rdi        # 10815f0 <core_durable_error.verbs+0x14a0>
 105ff69:	e8 12 4d fc ff       	call   1024c80 <myl_core_trap>
 105ff6e:	48 89 d8             	mov    %rbx,%rax
 105ff71:	48 c1 f8 3f          	sar    $0x3f,%rax
 105ff75:	48 21 d0             	and    %rdx,%rax
 105ff78:	48 01 d8             	add    %rbx,%rax
 105ff7b:	48 39 d0             	cmp    %rdx,%rax
 105ff7e:	0f 82 3f f1 ff ff    	jb     105f0c3 <my.interpreter::execute+0x643>
 105ff84:	48 8d 3d c5 5e 02 00 	lea    0x25ec5(%rip),%rdi        # 1085e50 <core_durable_error.verbs+0x5d00>
 105ff8b:	48 8b 74 24 28       	mov    0x28(%rsp),%rsi
 105ff90:	e8 eb 4c fc ff       	call   1024c80 <myl_core_trap>
 105ff95:	48 89 f1             	mov    %rsi,%rcx
 105ff98:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105ff9c:	48 21 d1             	and    %rdx,%rcx
 105ff9f:	48 01 f1             	add    %rsi,%rcx
 105ffa2:	48 39 d1             	cmp    %rdx,%rcx
 105ffa5:	0f 82 c2 f7 ff ff    	jb     105f76d <my.interpreter::execute+0xced>
 105ffab:	48 8d 3d 2e 5f 02 00 	lea    0x25f2e(%rip),%rdi        # 1085ee0 <core_durable_error.verbs+0x5d90>
 105ffb2:	e8 c9 4c fc ff       	call   1024c80 <myl_core_trap>
 105ffb7:	4c 89 f9             	mov    %r15,%rcx
 105ffba:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105ffbe:	48 21 d1             	and    %rdx,%rcx
 105ffc1:	4c 01 f9             	add    %r15,%rcx
 105ffc4:	48 39 d1             	cmp    %rdx,%rcx
 105ffc7:	0f 82 cc f7 ff ff    	jb     105f799 <my.interpreter::execute+0xd19>
 105ffcd:	48 8d 3d cc 80 02 00 	lea    0x280cc(%rip),%rdi        # 10880a0 <core_durable_error.verbs+0x7f50>
 105ffd4:	4c 89 fe             	mov    %r15,%rsi
 105ffd7:	e8 a4 4c fc ff       	call   1024c80 <myl_core_trap>
 105ffdc:	48 89 f0             	mov    %rsi,%rax
 105ffdf:	48 c1 f8 3f          	sar    $0x3f,%rax
 105ffe3:	48 21 d0             	and    %rdx,%rax
 105ffe6:	48 01 f0             	add    %rsi,%rax
 105ffe9:	48 39 d0             	cmp    %rdx,%rax
 105ffec:	0f 82 04 ee ff ff    	jb     105edf6 <my.interpreter::execute+0x376>
 105fff2:	48 8d 3d 07 12 02 00 	lea    0x21207(%rip),%rdi        # 1081200 <core_durable_error.verbs+0x10b0>
 105fff9:	e8 82 4c fc ff       	call   1024c80 <myl_core_trap>
 105fffe:	48 8d 3d 0b 17 02 00 	lea    0x2170b(%rip),%rdi        # 1081710 <core_durable_error.verbs+0x15c0>
 1060005:	ba 01 00 00 00       	mov    $0x1,%edx
 106000a:	48 89 c6             	mov    %rax,%rsi
 106000d:	e8 6e 4c fc ff       	call   1024c80 <myl_core_trap>
 1060012:	83 f8 01             	cmp    $0x1,%eax
 1060015:	0f 84 b8 00 00 00    	je     10600d3 <my.interpreter::execute+0x1653>
 106001b:	85 c0                	test   %eax,%eax
 106001d:	0f 85 bc 00 00 00    	jne    10600df <my.interpreter::execute+0x165f>
 1060023:	48 8d 3d e6 5e 02 00 	lea    0x25ee6(%rip),%rdi        # 1085f10 <core_durable_error.verbs+0x5dc0>
 106002a:	e8 d1 9f fc ff       	call   102a000 <myl_core_assert_fail>
 106002f:	48 8d 3d ba 5d 02 00 	lea    0x25dba(%rip),%rdi        # 1085df0 <core_durable_error.verbs+0x5ca0>
 1060036:	31 f6                	xor    %esi,%esi
 1060038:	31 d2                	xor    %edx,%edx
 106003a:	e8 41 4c fc ff       	call   1024c80 <myl_core_trap>
 106003f:	48 8d 3d 5a 14 02 00 	lea    0x2145a(%rip),%rdi        # 10814a0 <core_durable_error.verbs+0x1350>
 1060046:	ba 01 00 00 00       	mov    $0x1,%edx
 106004b:	e8 30 4c fc ff       	call   1024c80 <myl_core_trap>
 1060050:	48 8d 3d 19 17 02 00 	lea    0x21719(%rip),%rdi        # 1081770 <core_durable_error.verbs+0x1620>
 1060057:	ba 01 00 00 00       	mov    $0x1,%edx
 106005c:	48 89 c6             	mov    %rax,%rsi
 106005f:	e8 1c 4c fc ff       	call   1024c80 <myl_core_trap>
 1060064:	48 8d 3d e5 15 02 00 	lea    0x215e5(%rip),%rdi        # 1081650 <core_durable_error.verbs+0x1500>
 106006b:	ba 01 00 00 00       	mov    $0x1,%edx
 1060070:	48 89 c6             	mov    %rax,%rsi
 1060073:	e8 08 4c fc ff       	call   1024c80 <myl_core_trap>
 1060078:	48 8d 3d 11 15 02 00 	lea    0x21511(%rip),%rdi        # 1081590 <core_durable_error.verbs+0x1440>
 106007f:	ba 01 00 00 00       	mov    $0x1,%edx
 1060084:	e8 f7 4b fc ff       	call   1024c80 <myl_core_trap>
 1060089:	48 8d 3d 40 14 02 00 	lea    0x21440(%rip),%rdi        # 10814d0 <core_durable_error.verbs+0x1380>
 1060090:	ba 01 00 00 00       	mov    $0x1,%edx
 1060095:	48 89 c6             	mov    %rax,%rsi
 1060098:	e8 e3 4b fc ff       	call   1024c80 <myl_core_trap>
 106009d:	48 8d 3d 8c 14 02 00 	lea    0x2148c(%rip),%rdi        # 1081530 <core_durable_error.verbs+0x13e0>
 10600a4:	ba 01 00 00 00       	mov    $0x1,%edx
 10600a9:	48 89 c6             	mov    %rax,%rsi
 10600ac:	e8 cf 4b fc ff       	call   1024c80 <myl_core_trap>
 10600b1:	48 8d 3d 18 17 02 00 	lea    0x21718(%rip),%rdi        # 10817d0 <core_durable_error.verbs+0x1680>
 10600b8:	ba 01 00 00 00       	mov    $0x1,%edx
 10600bd:	e8 be 4b fc ff       	call   1024c80 <myl_core_trap>
 10600c2:	48 8d 3d 37 2f 02 00 	lea    0x22f37(%rip),%rdi        # 1083000 <core_durable_error.verbs+0x2eb0>
 10600c9:	ba 01 00 00 00       	mov    $0x1,%edx
 10600ce:	e8 ad 4b fc ff       	call   1024c80 <myl_core_trap>
 10600d3:	48 8d 3d 66 5e 02 00 	lea    0x25e66(%rip),%rdi        # 1085f40 <core_durable_error.verbs+0x5df0>
 10600da:	e8 21 9f fc ff       	call   102a000 <myl_core_assert_fail>
 10600df:	48 8d 3d 8a 5e 02 00 	lea    0x25e8a(%rip),%rdi        # 1085f70 <core_durable_error.verbs+0x5e20>
 10600e6:	e8 15 9f fc ff       	call   102a000 <myl_core_assert_fail>
 10600eb:	48 8d 3d 3e 2f 02 00 	lea    0x22f3e(%rip),%rdi        # 1083030 <core_durable_error.verbs+0x2ee0>
 10600f2:	ba 01 00 00 00       	mov    $0x1,%edx
 10600f7:	48 89 c6             	mov    %rax,%rsi
 10600fa:	e8 81 4b fc ff       	call   1024c80 <myl_core_trap>
 10600ff:	48 8d 3d 0a 13 02 00 	lea    0x2130a(%rip),%rdi        # 1081410 <core_durable_error.verbs+0x12c0>
 1060106:	ba 01 00 00 00       	mov    $0x1,%edx
 106010b:	48 89 c6             	mov    %rax,%rsi
 106010e:	e8 6d 4b fc ff       	call   1024c80 <myl_core_trap>
 1060113:	48 8d 3d d6 5c 02 00 	lea    0x25cd6(%rip),%rdi        # 1085df0 <core_durable_error.verbs+0x5ca0>
 106011a:	31 f6                	xor    %esi,%esi
 106011c:	31 d2                	xor    %edx,%edx
 106011e:	e8 5d 4b fc ff       	call   1024c80 <myl_core_trap>
 1060123:	48 8d 3d 66 2f 02 00 	lea    0x22f66(%rip),%rdi        # 1083090 <core_durable_error.verbs+0x2f40>
 106012a:	ba 01 00 00 00       	mov    $0x1,%edx
 106012f:	e8 4c 4b fc ff       	call   1024c80 <myl_core_trap>
 1060134:	48 8d 3d a5 15 02 00 	lea    0x215a5(%rip),%rdi        # 10816e0 <core_durable_error.verbs+0x1590>
 106013b:	ba 01 00 00 00       	mov    $0x1,%edx
 1060140:	e8 3b 4b fc ff       	call   1024c80 <myl_core_trap>
 1060145:	48 8d 3d d4 14 02 00 	lea    0x214d4(%rip),%rdi        # 1081620 <core_durable_error.verbs+0x14d0>
 106014c:	ba 01 00 00 00       	mov    $0x1,%edx
 1060151:	48 89 c6             	mov    %rax,%rsi
 1060154:	e8 27 4b fc ff       	call   1024c80 <myl_core_trap>
 1060159:	48 8d 3d 50 5d 02 00 	lea    0x25d50(%rip),%rdi        # 1085eb0 <core_durable_error.verbs+0x5d60>
 1060160:	ba 01 00 00 00       	mov    $0x1,%edx
 1060165:	48 89 c6             	mov    %rax,%rsi
 1060168:	e8 13 4b fc ff       	call   1024c80 <myl_core_trap>

Disassembly of section .plt:
