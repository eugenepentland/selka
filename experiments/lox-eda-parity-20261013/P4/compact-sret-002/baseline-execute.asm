
.tmp/lox-eda-parity/P4/compact-sret-002/baseline/lox:     file format elf64-x86-64


Disassembly of section .text:

000000000105ddd0 <my.interpreter::execute>:
 105ddd0:	55                   	push   %rbp
 105ddd1:	41 57                	push   %r15
 105ddd3:	41 56                	push   %r14
 105ddd5:	41 55                	push   %r13
 105ddd7:	41 54                	push   %r12
 105ddd9:	53                   	push   %rbx
 105ddda:	48 81 ec e8 0e 00 00 	sub    $0xee8,%rsp
 105dde1:	4d 89 ce             	mov    %r9,%r14
 105dde4:	4c 89 04 24          	mov    %r8,(%rsp)
 105dde8:	49 89 c8             	mov    %rcx,%r8
 105ddeb:	48 89 d3             	mov    %rdx,%rbx
 105ddee:	48 89 fd             	mov    %rdi,%rbp
 105ddf1:	4c 8b a4 24 40 0f 00 	mov    0xf40(%rsp),%r12
 105ddf8:	00 
 105ddf9:	48 8b 52 08          	mov    0x8(%rdx),%rdx
 105ddfd:	4c 89 e0             	mov    %r12,%rax
 105de00:	49 39 d4             	cmp    %rdx,%r12
 105de03:	0f 83 e3 12 00 00    	jae    105f0ec <my.interpreter::execute+0x131c>
 105de09:	4c 8b ac 24 38 0f 00 	mov    0xf38(%rsp),%r13
 105de10:	00 
 105de11:	44 0f b6 94 24 30 0f 	movzbl 0xf30(%rsp),%r10d
 105de18:	00 00 
 105de1a:	4c 8b 9c 24 28 0f 00 	mov    0xf28(%rsp),%r11
 105de21:	00 
 105de22:	48 6b c8 58          	imul   $0x58,%rax,%rcx
 105de26:	48 8d 04 0b          	lea    (%rbx,%rcx,1),%rax
 105de2a:	48 83 c0 20          	add    $0x20,%rax
 105de2e:	8b 4c 0b 20          	mov    0x20(%rbx,%rcx,1),%ecx
 105de32:	48 83 f9 07          	cmp    $0x7,%rcx
 105de36:	4c 89 44 24 30       	mov    %r8,0x30(%rsp)
 105de3b:	49 89 f7             	mov    %rsi,%r15
 105de3e:	0f 87 f9 06 00 00    	ja     105e53d <my.interpreter::execute+0x76d>
 105de44:	48 8d 15 79 96 fa ff 	lea    -0x56987(%rip),%rdx        # 10074c4 <core_number_pairs+0x264>
 105de4b:	48 63 0c 8a          	movslq (%rdx,%rcx,4),%rcx
 105de4f:	48 01 d1             	add    %rdx,%rcx
 105de52:	ff e1                	jmp    *%rcx
 105de54:	48 8b 48 10          	mov    0x10(%rax),%rcx
 105de58:	49 8b 96 a8 00 00 00 	mov    0xa8(%r14),%rdx
 105de5f:	48 8d bc 24 b0 0a 00 	lea    0xab0(%rsp),%rdi
 105de66:	00 
 105de67:	4c 89 f6             	mov    %r14,%rsi
 105de6a:	e8 41 dd 00 00       	call   106bbb0 <my.interpreter::new_env>
 105de6f:	48 8b 94 24 b0 0a 00 	mov    0xab0(%rsp),%rdx
 105de76:	00 
 105de77:	49 8b b6 a8 00 00 00 	mov    0xa8(%r14),%rsi
 105de7e:	49 8b 86 b0 00 00 00 	mov    0xb0(%r14),%rax
 105de85:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105de89:	48 3b 48 10          	cmp    0x10(%rax),%rcx
 105de8d:	0f 83 c5 12 00 00    	jae    105f158 <my.interpreter::execute+0x1388>
 105de93:	48 89 74 c8 20       	mov    %rsi,0x20(%rax,%rcx,8)
 105de98:	48 ff c1             	inc    %rcx
 105de9b:	48 89 48 08          	mov    %rcx,0x8(%rax)
 105de9f:	49 89 86 b0 00 00 00 	mov    %rax,0xb0(%r14)
 105dea6:	49 89 96 a8 00 00 00 	mov    %rdx,0xa8(%r14)
 105dead:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 105deb1:	49 39 d4             	cmp    %rdx,%r12
 105deb4:	4c 8b 94 24 28 0f 00 	mov    0xf28(%rsp),%r10
 105debb:	00 
 105debc:	0f b6 b4 24 30 0f 00 	movzbl 0xf30(%rsp),%esi
 105dec3:	00 
 105dec4:	48 8b 4c 24 30       	mov    0x30(%rsp),%rcx
 105dec9:	0f 83 b3 12 00 00    	jae    105f182 <my.interpreter::execute+0x13b2>
 105decf:	4c 89 e0             	mov    %r12,%rax
 105ded2:	48 89 da             	mov    %rbx,%rdx
 105ded5:	48 83 c2 20          	add    $0x20,%rdx
 105ded9:	48 6b c0 58          	imul   $0x58,%rax,%rax
 105dedd:	83 3c 02 00          	cmpl   $0x0,(%rdx,%rax,1)
 105dee1:	48 89 6c 24 18       	mov    %rbp,0x18(%rsp)
 105dee6:	0f 84 f1 0a 00 00    	je     105e9dd <my.interpreter::execute+0xc0d>
 105deec:	40 0f b6 f6          	movzbl %sil,%esi
 105def0:	48 89 f3             	mov    %rsi,%rbx
 105def3:	31 f6                	xor    %esi,%esi
 105def5:	31 d2                	xor    %edx,%edx
 105def7:	31 c0                	xor    %eax,%eax
 105def9:	49 8b be b0 00 00 00 	mov    0xb0(%r14),%rdi
 105df00:	4c 8b 47 08          	mov    0x8(%rdi),%r8
 105df04:	4d 85 c0             	test   %r8,%r8
 105df07:	48 8b 6c 24 18       	mov    0x18(%rsp),%rbp
 105df0c:	0f 84 f7 14 00 00    	je     105f409 <my.interpreter::execute+0x1639>
 105df12:	4e 8b 4c c7 18       	mov    0x18(%rdi,%r8,8),%r9
 105df17:	49 ff c8             	dec    %r8
 105df1a:	4c 89 47 08          	mov    %r8,0x8(%rdi)
 105df1e:	4d 89 8e a8 00 00 00 	mov    %r9,0xa8(%r14)
 105df25:	40 84 f6             	test   %sil,%sil
 105df28:	0f 85 ab 0f 00 00    	jne    105eed9 <my.interpreter::execute+0x1109>
 105df2e:	48 89 55 00          	mov    %rdx,0x0(%rbp)
 105df32:	48 89 45 08          	mov    %rax,0x8(%rbp)
 105df36:	48 89 4d 10          	mov    %rcx,0x10(%rbp)
 105df3a:	4c 89 95 00 01 00 00 	mov    %r10,0x100(%rbp)
 105df41:	48 89 9d 08 01 00 00 	mov    %rbx,0x108(%rbp)
 105df48:	e9 06 0f 00 00       	jmp    105ee53 <my.interpreter::execute+0x1083>
 105df4d:	48 8b 48 10          	mov    0x10(%rax),%rcx
 105df51:	48 89 4c 24 10       	mov    %rcx,0x10(%rsp)
 105df56:	44 0f b6 60 18       	movzbl 0x18(%rax),%r12d
 105df5b:	48 8b 48 20          	mov    0x20(%rax),%rcx
 105df5f:	48 89 4c 24 20       	mov    %rcx,0x20(%rsp)
 105df64:	45 0f b6 d2          	movzbl %r10b,%r10d
 105df68:	48 8d bc 24 80 08 00 	lea    0x880(%rsp),%rdi
 105df6f:	00 
 105df70:	48 89 da             	mov    %rbx,%rdx
 105df73:	4c 89 c1             	mov    %r8,%rcx
 105df76:	4c 8b 04 24          	mov    (%rsp),%r8
 105df7a:	4d 89 f1             	mov    %r14,%r9
 105df7d:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105df84:	ff 70 08             	push   0x8(%rax)
 105df87:	41 55                	push   %r13
 105df89:	41 52                	push   %r10
 105df8b:	41 53                	push   %r11
 105df8d:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105df94:	e8 37 70 00 00       	call   1064fd0 <my.interpreter::evaluate>
 105df99:	48 83 c4 30          	add    $0x30,%rsp
 105df9d:	4c 8b 9c 24 80 09 00 	mov    0x980(%rsp),%r11
 105dfa4:	00 
 105dfa5:	48 8b bc 24 88 09 00 	mov    0x988(%rsp),%rdi
 105dfac:	00 
 105dfad:	44 0f b6 d7          	movzbl %dil,%r10d
 105dfb1:	4c 8b ac 24 90 09 00 	mov    0x990(%rsp),%r13
 105dfb8:	00 
 105dfb9:	80 bc 24 80 08 00 00 	cmpb   $0x1,0x880(%rsp)
 105dfc0:	01 
 105dfc1:	0f 84 b9 0e 00 00    	je     105ee80 <my.interpreter::execute+0x10b0>
 105dfc7:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105dfce:	48 89 c6             	mov    %rax,%rsi
 105dfd1:	48 ff ce             	dec    %rsi
 105dfd4:	0f 80 89 14 00 00    	jo     105f463 <my.interpreter::execute+0x1693>
 105dfda:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105dfe1:	49 8b 46 78          	mov    0x78(%r14),%rax
 105dfe5:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105dfe9:	48 39 d6             	cmp    %rdx,%rsi
 105dfec:	48 8b 4c 24 30       	mov    0x30(%rsp),%rcx
 105dff1:	0f 83 f7 11 00 00    	jae    105f1ee <my.interpreter::execute+0x141e>
 105dff7:	49 89 f0             	mov    %rsi,%r8
 105dffa:	49 c1 e0 04          	shl    $0x4,%r8
 105dffe:	42 0f b6 54 00 20    	movzbl 0x20(%rax,%r8,1),%edx
 105e004:	85 d2                	test   %edx,%edx
 105e006:	0f 84 13 09 00 00    	je     105e91f <my.interpreter::execute+0xb4f>
 105e00c:	83 fa 01             	cmp    $0x1,%edx
 105e00f:	75 11                	jne    105e022 <my.interpreter::execute+0x252>
 105e011:	4c 01 c0             	add    %r8,%rax
 105e014:	48 83 c0 20          	add    $0x20,%rax
 105e018:	f6 40 08 01          	testb  $0x1,0x8(%rax)
 105e01c:	0f 84 fd 08 00 00    	je     105e91f <my.interpreter::execute+0xb4f>
 105e022:	48 8d bc 24 68 07 00 	lea    0x768(%rsp),%rdi
 105e029:	00 
 105e02a:	4c 89 fe             	mov    %r15,%rsi
 105e02d:	48 89 da             	mov    %rbx,%rdx
 105e030:	4c 8b 04 24          	mov    (%rsp),%r8
 105e034:	4d 89 f1             	mov    %r14,%r9
 105e037:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105e03e:	ff 74 24 18          	push   0x18(%rsp)
 105e042:	41 55                	push   %r13
 105e044:	41 52                	push   %r10
 105e046:	41 53                	push   %r11
 105e048:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105e04f:	e8 7c fd ff ff       	call   105ddd0 <my.interpreter::execute>
 105e054:	48 83 c4 30          	add    $0x30,%rsp
 105e058:	0f b6 84 24 68 07 00 	movzbl 0x768(%rsp),%eax
 105e05f:	00 
 105e060:	c5 f8 10 84 24 70 07 	vmovups 0x770(%rsp),%xmm0
 105e067:	00 00 
 105e069:	48 8b 8c 24 68 08 00 	mov    0x868(%rsp),%rcx
 105e070:	00 
 105e071:	0f b6 94 24 70 08 00 	movzbl 0x870(%rsp),%edx
 105e078:	00 
 105e079:	48 8b b4 24 78 08 00 	mov    0x878(%rsp),%rsi
 105e080:	00 
 105e081:	48 83 f8 01          	cmp    $0x1,%rax
 105e085:	0f 85 07 09 00 00    	jne    105e992 <my.interpreter::execute+0xbc2>
 105e08b:	48 8d 3d ee 27 02 00 	lea    0x227ee(%rip),%rdi        # 1080880 <core_durable_error.verbs+0x1170>
 105e092:	e9 1d 10 00 00       	jmp    105f0b4 <my.interpreter::execute+0x12e4>
 105e097:	48 8b 40 08          	mov    0x8(%rax),%rax
 105e09b:	48 8b 56 08          	mov    0x8(%rsi),%rdx
 105e09f:	48 89 c1             	mov    %rax,%rcx
 105e0a2:	48 39 d0             	cmp    %rdx,%rax
 105e0a5:	0f 83 66 10 00 00    	jae    105f111 <my.interpreter::execute+0x1341>
 105e0ab:	48 6b c9 70          	imul   $0x70,%rcx,%rcx
 105e0af:	83 7c 0e 20 0b       	cmpl   $0xb,0x20(%rsi,%rcx,1)
 105e0b4:	0f 85 32 06 00 00    	jne    105e6ec <my.interpreter::execute+0x91c>
 105e0ba:	48 01 f1             	add    %rsi,%rcx
 105e0bd:	48 83 c1 20          	add    $0x20,%rcx
 105e0c1:	48 8b 79 38          	mov    0x38(%rcx),%rdi
 105e0c5:	48 83 ff ff          	cmp    $0xffffffffffffffff,%rdi
 105e0c9:	0f 84 1d 06 00 00    	je     105e6ec <my.interpreter::execute+0x91c>
 105e0cf:	48 8b 71 40          	mov    0x40(%rcx),%rsi
 105e0d3:	49 8b 0e             	mov    (%r14),%rcx
 105e0d6:	49 8b 86 a8 00 00 00 	mov    0xa8(%r14),%rax
 105e0dd:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105e0e1:	48 85 ff             	test   %rdi,%rdi
 105e0e4:	0f 8e 9a 09 00 00    	jle    105ea84 <my.interpreter::execute+0xcb4>
 105e0ea:	4c 8d 41 20          	lea    0x20(%rcx),%r8
 105e0ee:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105e0f5:	0f 1f 84 00 00 00 00 
 105e0fc:	00 
 105e0fd:	0f 1f 00             	nopl   (%rax)
 105e100:	48 39 d0             	cmp    %rdx,%rax
 105e103:	73 23                	jae    105e128 <my.interpreter::execute+0x358>
 105e105:	49 89 c1             	mov    %rax,%r9
 105e108:	49 6b c1 38          	imul   $0x38,%r9,%rax
 105e10c:	41 83 3c 00 09       	cmpl   $0x9,(%r8,%rax,1)
 105e111:	0f 85 c9 12 00 00    	jne    105f3e0 <my.interpreter::execute+0x1610>
 105e117:	4c 01 c0             	add    %r8,%rax
 105e11a:	48 8b 40 08          	mov    0x8(%rax),%rax
 105e11e:	48 ff cf             	dec    %rdi
 105e121:	75 dd                	jne    105e100 <my.interpreter::execute+0x330>
 105e123:	e9 5c 09 00 00       	jmp    105ea84 <my.interpreter::execute+0xcb4>
 105e128:	49 89 c1             	mov    %rax,%r9
 105e12b:	49 c1 f9 3f          	sar    $0x3f,%r9
 105e12f:	49 21 d1             	and    %rdx,%r9
 105e132:	49 01 c1             	add    %rax,%r9
 105e135:	49 39 d1             	cmp    %rdx,%r9
 105e138:	72 ce                	jb     105e108 <my.interpreter::execute+0x338>
 105e13a:	48 8d 3d 9f 72 02 00 	lea    0x2729f(%rip),%rdi        # 10853e0 <core_durable_error.verbs+0x5cd0>
 105e141:	48 89 c6             	mov    %rax,%rsi
 105e144:	e8 b7 65 fc ff       	call   1024700 <myl_core_trap>
 105e149:	4d 89 dc             	mov    %r11,%r12
 105e14c:	48 8b 70 08          	mov    0x8(%rax),%rsi
 105e150:	49 8b 50 08          	mov    0x8(%r8),%rdx
 105e154:	48 89 f0             	mov    %rsi,%rax
 105e157:	48 39 d6             	cmp    %rdx,%rsi
 105e15a:	0f 83 d6 0f 00 00    	jae    105f136 <my.interpreter::execute+0x1366>
 105e160:	48 8d 04 80          	lea    (%rax,%rax,4),%rax
 105e164:	48 c1 e0 04          	shl    $0x4,%rax
 105e168:	49 8b 5c 00 48       	mov    0x48(%r8,%rax,1),%rbx
 105e16d:	4d 8b 7c 00 60       	mov    0x60(%r8,%rax,1),%r15
 105e172:	49 8b 86 a8 00 00 00 	mov    0xa8(%r14),%rax
 105e179:	48 c7 44 24 68 0a 00 	movq   $0xa,0x68(%rsp)
 105e180:	00 00 
 105e182:	48 89 74 24 70       	mov    %rsi,0x70(%rsp)
 105e187:	48 89 5c 24 78       	mov    %rbx,0x78(%rsp)
 105e18c:	48 89 84 24 80 00 00 	mov    %rax,0x80(%rsp)
 105e193:	00 
 105e194:	c6 84 24 88 00 00 00 	movb   $0x0,0x88(%rsp)
 105e19b:	00 
 105e19c:	48 8d bc 24 90 0c 00 	lea    0xc90(%rsp),%rdi
 105e1a3:	00 
 105e1a4:	48 8d 54 24 68       	lea    0x68(%rsp),%rdx
 105e1a9:	4c 89 f6             	mov    %r14,%rsi
 105e1ac:	e8 ef c1 ff ff       	call   105a3a0 <my.heap::allocate>
 105e1b1:	48 8b 84 24 90 0c 00 	mov    0xc90(%rsp),%rax
 105e1b8:	00 
 105e1b9:	49 8b 4e 78          	mov    0x78(%r14),%rcx
 105e1bd:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105e1c4:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105e1c8:	48 39 d6             	cmp    %rdx,%rsi
 105e1cb:	0f 83 d6 0f 00 00    	jae    105f1a7 <my.interpreter::execute+0x13d7>
 105e1d1:	48 89 f7             	mov    %rsi,%rdi
 105e1d4:	48 c1 e7 04          	shl    $0x4,%rdi
 105e1d8:	48 c7 44 39 20 03 00 	movq   $0x3,0x20(%rcx,%rdi,1)
 105e1df:	00 00 
 105e1e1:	48 89 44 39 28       	mov    %rax,0x28(%rcx,%rdi,1)
 105e1e6:	49 89 4e 78          	mov    %rcx,0x78(%r14)
 105e1ea:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105e1f1:	48 89 f0             	mov    %rsi,%rax
 105e1f4:	48 ff c0             	inc    %rax
 105e1f7:	0f 80 1c 12 00 00    	jo     105f419 <my.interpreter::execute+0x1649>
 105e1fd:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 105e204:	4c 89 f7             	mov    %r14,%rdi
 105e207:	48 89 de             	mov    %rbx,%rsi
 105e20a:	4c 89 fa             	mov    %r15,%rdx
 105e20d:	e8 7e 8f 00 00       	call   1067190 <my.interpreter::define>
 105e212:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105e219:	48 89 c6             	mov    %rax,%rsi
 105e21c:	48 ff ce             	dec    %rsi
 105e21f:	0f 80 05 12 00 00    	jo     105f42a <my.interpreter::execute+0x165a>
 105e225:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105e22c:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e230:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e234:	48 39 d6             	cmp    %rdx,%rsi
 105e237:	4d 89 e3             	mov    %r12,%r11
 105e23a:	0f b6 bc 24 30 0f 00 	movzbl 0xf30(%rsp),%edi
 105e241:	00 
 105e242:	0f 82 f0 0b 00 00    	jb     105ee38 <my.interpreter::execute+0x1068>
 105e248:	48 89 f0             	mov    %rsi,%rax
 105e24b:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e24f:	48 21 d0             	and    %rdx,%rax
 105e252:	48 01 f0             	add    %rsi,%rax
 105e255:	48 39 d0             	cmp    %rdx,%rax
 105e258:	0f 82 da 0b 00 00    	jb     105ee38 <my.interpreter::execute+0x1068>
 105e25e:	48 8d 3d fb 2a 02 00 	lea    0x22afb(%rip),%rdi        # 1080d60 <core_durable_error.verbs+0x1650>
 105e265:	e8 96 64 fc ff       	call   1024700 <myl_core_trap>
 105e26a:	4c 8b 60 30          	mov    0x30(%rax),%r12
 105e26e:	4c 8b 48 48          	mov    0x48(%rax),%r9
 105e272:	80 78 38 01          	cmpb   $0x1,0x38(%rax)
 105e276:	0f 85 1a 05 00 00    	jne    105e796 <my.interpreter::execute+0x9c6>
 105e27c:	4c 89 4c 24 30       	mov    %r9,0x30(%rsp)
 105e281:	45 0f b6 d2          	movzbl %r10b,%r10d
 105e285:	48 8d bc 24 20 04 00 	lea    0x420(%rsp),%rdi
 105e28c:	00 
 105e28d:	48 89 da             	mov    %rbx,%rdx
 105e290:	4c 89 c1             	mov    %r8,%rcx
 105e293:	4c 8b 04 24          	mov    (%rsp),%r8
 105e297:	4d 89 f1             	mov    %r14,%r9
 105e29a:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105e2a1:	ff 70 40             	push   0x40(%rax)
 105e2a4:	41 55                	push   %r13
 105e2a6:	41 52                	push   %r10
 105e2a8:	41 53                	push   %r11
 105e2aa:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105e2b1:	e8 1a 6d 00 00       	call   1064fd0 <my.interpreter::evaluate>
 105e2b6:	48 83 c4 30          	add    $0x30,%rsp
 105e2ba:	48 8b 9c 24 20 05 00 	mov    0x520(%rsp),%rbx
 105e2c1:	00 
 105e2c2:	4c 8b bc 24 28 05 00 	mov    0x528(%rsp),%r15
 105e2c9:	00 
 105e2ca:	4c 8b ac 24 30 05 00 	mov    0x530(%rsp),%r13
 105e2d1:	00 
 105e2d2:	80 bc 24 20 04 00 00 	cmpb   $0x1,0x420(%rsp)
 105e2d9:	01 
 105e2da:	0f 84 e7 0c 00 00    	je     105efc7 <my.interpreter::execute+0x11f7>
 105e2e0:	4c 8b 4c 24 30       	mov    0x30(%rsp),%r9
 105e2e5:	e9 f8 04 00 00       	jmp    105e7e2 <my.interpreter::execute+0xa12>
 105e2ea:	48 8b 48 30          	mov    0x30(%rax),%rcx
 105e2ee:	48 89 4c 24 20       	mov    %rcx,0x20(%rsp)
 105e2f3:	48 8b 48 38          	mov    0x38(%rax),%rcx
 105e2f7:	44 0f b6 60 40       	movzbl 0x40(%rax),%r12d
 105e2fc:	48 8b 50 48          	mov    0x48(%rax),%rdx
 105e300:	48 89 54 24 28       	mov    %rdx,0x28(%rsp)
 105e305:	48 8b 40 50          	mov    0x50(%rax),%rax
 105e309:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105e30e:	48 89 4c 24 60       	mov    %rcx,0x60(%rsp)
 105e313:	48 83 f9 ff          	cmp    $0xffffffffffffffff,%rcx
 105e317:	75 51                	jne    105e36a <my.interpreter::execute+0x59a>
 105e319:	4c 89 f7             	mov    %r14,%rdi
 105e31c:	4c 8b 6c 24 20       	mov    0x20(%rsp),%r13
 105e321:	4c 89 ee             	mov    %r13,%rsi
 105e324:	e8 b7 af 00 00       	call   10692e0 <my.heap::string_hash>
 105e329:	49 8b 7e 30          	mov    0x30(%r14),%rdi
 105e32d:	49 8b 76 38          	mov    0x38(%r14),%rsi
 105e331:	4c 89 ea             	mov    %r13,%rdx
 105e334:	89 c1                	mov    %eax,%ecx
 105e336:	45 31 c0             	xor    %r8d,%r8d
 105e339:	45 31 c9             	xor    %r9d,%r9d
 105e33c:	e8 7f b0 00 00       	call   10693c0 <my.table::set>
 105e341:	4c 89 fe             	mov    %r15,%rsi
 105e344:	4c 8b 44 24 30       	mov    0x30(%rsp),%r8
 105e349:	44 0f b6 94 24 30 0f 	movzbl 0xf30(%rsp),%r10d
 105e350:	00 00 
 105e352:	4c 8b 9c 24 28 0f 00 	mov    0xf28(%rsp),%r11
 105e359:	00 
 105e35a:	4c 8b ac 24 38 0f 00 	mov    0xf38(%rsp),%r13
 105e361:	00 
 105e362:	49 89 56 30          	mov    %rdx,0x30(%r14)
 105e366:	49 89 4e 38          	mov    %rcx,0x38(%r14)
 105e36a:	49 c7 c7 ff ff ff ff 	mov    $0xffffffffffffffff,%r15
 105e371:	41 83 fc 01          	cmp    $0x1,%r12d
 105e375:	0f 85 c8 04 00 00    	jne    105e843 <my.interpreter::execute+0xa73>
 105e37b:	41 0f b6 c2          	movzbl %r10b,%eax
 105e37f:	48 8d bc 24 d8 00 00 	lea    0xd8(%rsp),%rdi
 105e386:	00 
 105e387:	49 89 f7             	mov    %rsi,%r15
 105e38a:	48 89 da             	mov    %rbx,%rdx
 105e38d:	4c 89 c1             	mov    %r8,%rcx
 105e390:	4c 8b 04 24          	mov    (%rsp),%r8
 105e394:	4d 89 f1             	mov    %r14,%r9
 105e397:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105e39e:	48 8b 5c 24 30       	mov    0x30(%rsp),%rbx
 105e3a3:	53                   	push   %rbx
 105e3a4:	41 55                	push   %r13
 105e3a6:	50                   	push   %rax
 105e3a7:	41 53                	push   %r11
 105e3a9:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105e3b0:	e8 1b 6c 00 00       	call   1064fd0 <my.interpreter::evaluate>
 105e3b5:	48 83 c4 30          	add    $0x30,%rsp
 105e3b9:	48 8b bc 24 d8 01 00 	mov    0x1d8(%rsp),%rdi
 105e3c0:	00 
 105e3c1:	44 0f b6 84 24 e0 01 	movzbl 0x1e0(%rsp),%r8d
 105e3c8:	00 00 
 105e3ca:	4c 8b ac 24 e8 01 00 	mov    0x1e8(%rsp),%r13
 105e3d1:	00 
 105e3d2:	80 bc 24 d8 00 00 00 	cmpb   $0x1,0xd8(%rsp)
 105e3d9:	01 
 105e3da:	0f 84 23 0c 00 00    	je     105f003 <my.interpreter::execute+0x1233>
 105e3e0:	49 8b 57 08          	mov    0x8(%r15),%rdx
 105e3e4:	48 39 d3             	cmp    %rdx,%rbx
 105e3e7:	0f 83 08 0f 00 00    	jae    105f2f5 <my.interpreter::execute+0x1525>
 105e3ed:	48 89 d8             	mov    %rbx,%rax
 105e3f0:	48 6b c0 70          	imul   $0x70,%rax,%rax
 105e3f4:	41 83 7c 07 20 0b    	cmpl   $0xb,0x20(%r15,%rax,1)
 105e3fa:	0f 85 e8 06 00 00    	jne    105eae8 <my.interpreter::execute+0xd18>
 105e400:	4c 01 f8             	add    %r15,%rax
 105e403:	48 83 c0 20          	add    $0x20,%rax
 105e407:	48 8b 58 20          	mov    0x20(%rax),%rbx
 105e40b:	e9 da 06 00 00       	jmp    105eaea <my.interpreter::execute+0xd1a>
 105e410:	45 0f b6 d2          	movzbl %r10b,%r10d
 105e414:	48 8d bc 24 38 05 00 	lea    0x538(%rsp),%rdi
 105e41b:	00 
 105e41c:	48 89 da             	mov    %rbx,%rdx
 105e41f:	4c 89 c1             	mov    %r8,%rcx
 105e422:	4c 8b 04 24          	mov    (%rsp),%r8
 105e426:	4d 89 f1             	mov    %r14,%r9
 105e429:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105e430:	ff 70 08             	push   0x8(%rax)
 105e433:	41 55                	push   %r13
 105e435:	41 52                	push   %r10
 105e437:	41 53                	push   %r11
 105e439:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105e440:	e8 8b 6b 00 00       	call   1064fd0 <my.interpreter::evaluate>
 105e445:	48 83 c4 30          	add    $0x30,%rsp
 105e449:	48 8b 9c 24 38 06 00 	mov    0x638(%rsp),%rbx
 105e450:	00 
 105e451:	4c 8b bc 24 40 06 00 	mov    0x640(%rsp),%r15
 105e458:	00 
 105e459:	4c 8b ac 24 48 06 00 	mov    0x648(%rsp),%r13
 105e460:	00 
 105e461:	80 bc 24 38 05 00 00 	cmpb   $0x1,0x538(%rsp)
 105e468:	01 
 105e469:	0f 84 4c 0a 00 00    	je     105eebb <my.interpreter::execute+0x10eb>
 105e46f:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105e476:	48 89 c6             	mov    %rax,%rsi
 105e479:	48 ff ce             	dec    %rsi
 105e47c:	0f 80 f5 0f 00 00    	jo     105f477 <my.interpreter::execute+0x16a7>
 105e482:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e486:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e48a:	48 39 d6             	cmp    %rdx,%rsi
 105e48d:	0f 83 7d 0d 00 00    	jae    105f210 <my.interpreter::execute+0x1440>
 105e493:	48 89 f7             	mov    %rsi,%rdi
 105e496:	48 c1 e7 04          	shl    $0x4,%rdi
 105e49a:	48 8b 4c 38 28       	mov    0x28(%rax,%rdi,1),%rcx
 105e49f:	8b 54 38 20          	mov    0x20(%rax,%rdi,1),%edx
 105e4a3:	4c 89 f7             	mov    %r14,%rdi
 105e4a6:	48 8b b4 24 20 0f 00 	mov    0xf20(%rsp),%rsi
 105e4ad:	00 
 105e4ae:	e8 4d 44 00 00       	call   1062900 <my.output::print_value>
 105e4b3:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105e4ba:	48 89 f0             	mov    %rsi,%rax
 105e4bd:	48 ff c8             	dec    %rax
 105e4c0:	0f 80 c5 0f 00 00    	jo     105f48b <my.interpreter::execute+0x16bb>
 105e4c6:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 105e4cd:	49 89 db             	mov    %rbx,%r11
 105e4d0:	4c 89 ff             	mov    %r15,%rdi
 105e4d3:	e9 60 09 00 00       	jmp    105ee38 <my.interpreter::execute+0x1068>
 105e4d8:	83 78 30 01          	cmpl   $0x1,0x30(%rax)
 105e4dc:	0f 85 70 03 00 00    	jne    105e852 <my.interpreter::execute+0xa82>
 105e4e2:	45 0f b6 d2          	movzbl %r10b,%r10d
 105e4e6:	48 8d bc 24 78 0b 00 	lea    0xb78(%rsp),%rdi
 105e4ed:	00 
 105e4ee:	48 89 da             	mov    %rbx,%rdx
 105e4f1:	4c 89 c1             	mov    %r8,%rcx
 105e4f4:	4c 8b 04 24          	mov    (%rsp),%r8
 105e4f8:	4d 89 f1             	mov    %r14,%r9
 105e4fb:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105e502:	ff 70 38             	push   0x38(%rax)
 105e505:	41 55                	push   %r13
 105e507:	41 52                	push   %r10
 105e509:	41 53                	push   %r11
 105e50b:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105e512:	e8 b9 6a 00 00       	call   1064fd0 <my.interpreter::evaluate>
 105e517:	48 83 c4 30          	add    $0x30,%rsp
 105e51b:	4c 8b 9c 24 78 0c 00 	mov    0xc78(%rsp),%r11
 105e522:	00 
 105e523:	80 bc 24 78 0b 00 00 	cmpb   $0x1,0xb78(%rsp)
 105e52a:	01 
 105e52b:	0f 84 2c 0b 00 00    	je     105f05d <my.interpreter::execute+0x128d>
 105e531:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105e538:	e9 5b 03 00 00       	jmp    105e898 <my.interpreter::execute+0xac8>
 105e53d:	48 89 6c 24 18       	mov    %rbp,0x18(%rsp)
 105e542:	4c 8b 60 08          	mov    0x8(%rax),%r12
 105e546:	48 8b 40 10          	mov    0x10(%rax),%rax
 105e54a:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105e54f:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105e556:	0f 1f 84 00 00 00 00 
 105e55d:	00 
 105e55e:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105e565:	0f 1f 84 00 00 00 00 
 105e56c:	00 
 105e56d:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105e574:	0f 1f 84 00 00 00 00 
 105e57b:	00 
 105e57c:	0f 1f 40 00          	nopl   0x0(%rax)
 105e580:	41 0f b6 c2          	movzbl %r10b,%eax
 105e584:	48 8d bc 24 08 03 00 	lea    0x308(%rsp),%rdi
 105e58b:	00 
 105e58c:	48 89 da             	mov    %rbx,%rdx
 105e58f:	4c 89 c1             	mov    %r8,%rcx
 105e592:	4c 8b 04 24          	mov    (%rsp),%r8
 105e596:	4d 89 f1             	mov    %r14,%r9
 105e599:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105e5a0:	41 54                	push   %r12
 105e5a2:	41 55                	push   %r13
 105e5a4:	50                   	push   %rax
 105e5a5:	41 53                	push   %r11
 105e5a7:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105e5ae:	e8 1d 6a 00 00       	call   1064fd0 <my.interpreter::evaluate>
 105e5b3:	48 83 c4 30          	add    $0x30,%rsp
 105e5b7:	4c 8b 94 24 08 04 00 	mov    0x408(%rsp),%r10
 105e5be:	00 
 105e5bf:	48 8b 84 24 10 04 00 	mov    0x410(%rsp),%rax
 105e5c6:	00 
 105e5c7:	0f b6 e8             	movzbl %al,%ebp
 105e5ca:	4c 8b ac 24 18 04 00 	mov    0x418(%rsp),%r13
 105e5d1:	00 
 105e5d2:	80 bc 24 08 03 00 00 	cmpb   $0x1,0x308(%rsp)
 105e5d9:	01 
 105e5da:	0f 84 7a 09 00 00    	je     105ef5a <my.interpreter::execute+0x118a>
 105e5e0:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105e5e7:	48 89 c6             	mov    %rax,%rsi
 105e5ea:	48 ff ce             	dec    %rsi
 105e5ed:	0f 80 d9 0d 00 00    	jo     105f3cc <my.interpreter::execute+0x15fc>
 105e5f3:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105e5fa:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e5fe:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e602:	48 39 d6             	cmp    %rdx,%rsi
 105e605:	48 8b 4c 24 30       	mov    0x30(%rsp),%rcx
 105e60a:	0f 83 ba 00 00 00    	jae    105e6ca <my.interpreter::execute+0x8fa>
 105e610:	48 89 f7             	mov    %rsi,%rdi
 105e613:	48 c1 e7 04          	shl    $0x4,%rdi
 105e617:	0f b6 54 38 20       	movzbl 0x20(%rax,%rdi,1),%edx
 105e61c:	83 fa 01             	cmp    $0x1,%edx
 105e61f:	74 1f                	je     105e640 <my.interpreter::execute+0x870>
 105e621:	85 d2                	test   %edx,%edx
 105e623:	4c 89 fe             	mov    %r15,%rsi
 105e626:	75 2c                	jne    105e654 <my.interpreter::execute+0x884>
 105e628:	e9 c8 02 00 00       	jmp    105e8f5 <my.interpreter::execute+0xb25>
 105e62d:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105e634:	0f 1f 84 00 00 00 00 
 105e63b:	00 
 105e63c:	0f 1f 40 00          	nopl   0x0(%rax)
 105e640:	48 01 f8             	add    %rdi,%rax
 105e643:	48 83 c0 20          	add    $0x20,%rax
 105e647:	f6 40 08 01          	testb  $0x1,0x8(%rax)
 105e64b:	4c 89 fe             	mov    %r15,%rsi
 105e64e:	0f 84 a1 02 00 00    	je     105e8f5 <my.interpreter::execute+0xb25>
 105e654:	48 8d bc 24 f0 01 00 	lea    0x1f0(%rsp),%rdi
 105e65b:	00 
 105e65c:	48 89 da             	mov    %rbx,%rdx
 105e65f:	4c 8b 04 24          	mov    (%rsp),%r8
 105e663:	4d 89 f1             	mov    %r14,%r9
 105e666:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105e66d:	ff 74 24 18          	push   0x18(%rsp)
 105e671:	41 55                	push   %r13
 105e673:	55                   	push   %rbp
 105e674:	41 52                	push   %r10
 105e676:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105e67d:	e8 4e f7 ff ff       	call   105ddd0 <my.interpreter::execute>
 105e682:	48 83 c4 30          	add    $0x30,%rsp
 105e686:	48 8b 84 24 f8 01 00 	mov    0x1f8(%rsp),%rax
 105e68d:	00 
 105e68e:	4c 8b 9c 24 f0 02 00 	mov    0x2f0(%rsp),%r11
 105e695:	00 
 105e696:	44 0f b6 94 24 f8 02 	movzbl 0x2f8(%rsp),%r10d
 105e69d:	00 00 
 105e69f:	4c 8b ac 24 00 03 00 	mov    0x300(%rsp),%r13
 105e6a6:	00 
 105e6a7:	80 bc 24 f0 01 00 00 	cmpb   $0x1,0x1f0(%rsp)
 105e6ae:	01 
 105e6af:	0f 84 da 08 00 00    	je     105ef8f <my.interpreter::execute+0x11bf>
 105e6b5:	3c 01                	cmp    $0x1,%al
 105e6b7:	4c 8b 44 24 30       	mov    0x30(%rsp),%r8
 105e6bc:	4c 89 fe             	mov    %r15,%rsi
 105e6bf:	0f 85 bb fe ff ff    	jne    105e580 <my.interpreter::execute+0x7b0>
 105e6c5:	e9 eb 02 00 00       	jmp    105e9b5 <my.interpreter::execute+0xbe5>
 105e6ca:	48 89 f7             	mov    %rsi,%rdi
 105e6cd:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105e6d1:	48 21 d7             	and    %rdx,%rdi
 105e6d4:	48 01 f7             	add    %rsi,%rdi
 105e6d7:	48 39 d7             	cmp    %rdx,%rdi
 105e6da:	0f 82 33 ff ff ff    	jb     105e613 <my.interpreter::execute+0x843>
 105e6e0:	48 8d 3d 19 26 02 00 	lea    0x22619(%rip),%rdi        # 1080d00 <core_durable_error.verbs+0x15f0>
 105e6e7:	e8 14 60 fc ff       	call   1024700 <myl_core_trap>
 105e6ec:	45 0f b6 d2          	movzbl %r10b,%r10d
 105e6f0:	48 8d bc 24 98 09 00 	lea    0x998(%rsp),%rdi
 105e6f7:	00 
 105e6f8:	48 89 da             	mov    %rbx,%rdx
 105e6fb:	4c 89 c1             	mov    %r8,%rcx
 105e6fe:	4c 8b 04 24          	mov    (%rsp),%r8
 105e702:	4d 89 f1             	mov    %r14,%r9
 105e705:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105e70c:	50                   	push   %rax
 105e70d:	41 55                	push   %r13
 105e70f:	41 52                	push   %r10
 105e711:	41 53                	push   %r11
 105e713:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105e71a:	e8 b1 68 00 00       	call   1064fd0 <my.interpreter::evaluate>
 105e71f:	48 83 c4 30          	add    $0x30,%rsp
 105e723:	4c 8b 9c 24 98 0a 00 	mov    0xa98(%rsp),%r11
 105e72a:	00 
 105e72b:	48 8b bc 24 a0 0a 00 	mov    0xaa0(%rsp),%rdi
 105e732:	00 
 105e733:	4c 8b ac 24 a8 0a 00 	mov    0xaa8(%rsp),%r13
 105e73a:	00 
 105e73b:	80 bc 24 98 09 00 00 	cmpb   $0x1,0x998(%rsp)
 105e742:	01 
 105e743:	0f 84 d2 07 00 00    	je     105ef1b <my.interpreter::execute+0x114b>
 105e749:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105e750:	48 89 c6             	mov    %rax,%rsi
 105e753:	48 ff ce             	dec    %rsi
 105e756:	0f 80 7d 0d 00 00    	jo     105f4d9 <my.interpreter::execute+0x1709>
 105e75c:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105e763:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e767:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e76b:	48 39 d6             	cmp    %rdx,%rsi
 105e76e:	0f 82 c4 06 00 00    	jb     105ee38 <my.interpreter::execute+0x1068>
 105e774:	48 89 f0             	mov    %rsi,%rax
 105e777:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e77b:	48 21 d0             	and    %rdx,%rax
 105e77e:	48 01 f0             	add    %rsi,%rax
 105e781:	48 39 d0             	cmp    %rdx,%rax
 105e784:	0f 82 ae 06 00 00    	jb     105ee38 <my.interpreter::execute+0x1068>
 105e78a:	48 8d 3d 6f 22 02 00 	lea    0x2226f(%rip),%rdi        # 1080a00 <core_durable_error.verbs+0x12f0>
 105e791:	e8 6a 5f fc ff       	call   1024700 <myl_core_trap>
 105e796:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e79a:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105e7a1:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e7a5:	48 39 d6             	cmp    %rdx,%rsi
 105e7a8:	0f 83 03 0b 00 00    	jae    105f2b1 <my.interpreter::execute+0x14e1>
 105e7ae:	48 89 f1             	mov    %rsi,%rcx
 105e7b1:	48 c1 e1 04          	shl    $0x4,%rcx
 105e7b5:	48 c7 44 08 20 00 00 	movq   $0x0,0x20(%rax,%rcx,1)
 105e7bc:	00 00 
 105e7be:	49 89 46 78          	mov    %rax,0x78(%r14)
 105e7c2:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105e7c9:	48 89 f0             	mov    %rsi,%rax
 105e7cc:	48 ff c0             	inc    %rax
 105e7cf:	0f 80 39 0d 00 00    	jo     105f50e <my.interpreter::execute+0x173e>
 105e7d5:	4d 89 d7             	mov    %r10,%r15
 105e7d8:	4c 89 db             	mov    %r11,%rbx
 105e7db:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 105e7e2:	4c 89 f7             	mov    %r14,%rdi
 105e7e5:	4c 89 e6             	mov    %r12,%rsi
 105e7e8:	4c 89 ca             	mov    %r9,%rdx
 105e7eb:	e8 a0 89 00 00       	call   1067190 <my.interpreter::define>
 105e7f0:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105e7f7:	48 89 c6             	mov    %rax,%rsi
 105e7fa:	48 ff ce             	dec    %rsi
 105e7fd:	0f 80 3b 0c 00 00    	jo     105f43e <my.interpreter::execute+0x166e>
 105e803:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105e80a:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e80e:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e812:	48 39 d6             	cmp    %rdx,%rsi
 105e815:	49 89 db             	mov    %rbx,%r11
 105e818:	4c 89 ff             	mov    %r15,%rdi
 105e81b:	0f 82 17 06 00 00    	jb     105ee38 <my.interpreter::execute+0x1068>
 105e821:	48 89 f0             	mov    %rsi,%rax
 105e824:	48 c1 f8 3f          	sar    $0x3f,%rax
 105e828:	48 21 d0             	and    %rdx,%rax
 105e82b:	48 01 f0             	add    %rsi,%rax
 105e82e:	48 39 d0             	cmp    %rdx,%rax
 105e831:	0f 82 01 06 00 00    	jb     105ee38 <my.interpreter::execute+0x1068>
 105e837:	48 8d 3d 02 24 02 00 	lea    0x22402(%rip),%rdi        # 1080c40 <core_durable_error.verbs+0x1530>
 105e83e:	e8 bd 5e fc ff       	call   1024700 <myl_core_trap>
 105e843:	4c 89 54 24 28       	mov    %r10,0x28(%rsp)
 105e848:	4c 89 5c 24 48       	mov    %r11,0x48(%rsp)
 105e84d:	e9 ff 02 00 00       	jmp    105eb51 <my.interpreter::execute+0xd81>
 105e852:	49 8b 46 78          	mov    0x78(%r14),%rax
 105e856:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105e85d:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105e861:	48 39 d6             	cmp    %rdx,%rsi
 105e864:	0f 83 69 0a 00 00    	jae    105f2d3 <my.interpreter::execute+0x1503>
 105e86a:	48 89 f1             	mov    %rsi,%rcx
 105e86d:	48 c1 e1 04          	shl    $0x4,%rcx
 105e871:	48 c7 44 08 20 00 00 	movq   $0x0,0x20(%rax,%rcx,1)
 105e878:	00 00 
 105e87a:	49 89 46 78          	mov    %rax,0x78(%r14)
 105e87e:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105e885:	48 89 c6             	mov    %rax,%rsi
 105e888:	48 ff c6             	inc    %rsi
 105e88b:	0f 80 8e 0c 00 00    	jo     105f51f <my.interpreter::execute+0x174f>
 105e891:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105e898:	48 89 f0             	mov    %rsi,%rax
 105e89b:	48 ff c8             	dec    %rax
 105e89e:	0f 80 ae 0b 00 00    	jo     105f452 <my.interpreter::execute+0x1682>
 105e8a4:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 105e8ab:	49 8b 4e 78          	mov    0x78(%r14),%rcx
 105e8af:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 105e8b3:	48 39 d0             	cmp    %rdx,%rax
 105e8b6:	0f 83 0d 09 00 00    	jae    105f1c9 <my.interpreter::execute+0x13f9>
 105e8bc:	48 89 c6             	mov    %rax,%rsi
 105e8bf:	48 c1 e6 04          	shl    $0x4,%rsi
 105e8c3:	c5 f8 10 44 31 20    	vmovups 0x20(%rcx,%rsi,1),%xmm0
 105e8c9:	48 c7 45 00 00 00 00 	movq   $0x0,0x0(%rbp)
 105e8d0:	00 
 105e8d1:	48 c7 45 08 01 00 00 	movq   $0x1,0x8(%rbp)
 105e8d8:	00 
 105e8d9:	4c 89 9d 00 01 00 00 	mov    %r11,0x100(%rbp)
 105e8e0:	c5 f8 54 05 f8 5a fa 	vandps -0x5a508(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 105e8e7:	ff 
 105e8e8:	c5 f8 11 85 08 01 00 	vmovups %xmm0,0x108(%rbp)
 105e8ef:	00 
 105e8f0:	e9 65 05 00 00       	jmp    105ee5a <my.interpreter::execute+0x108a>
 105e8f5:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
 105e8f9:	48 8b 44 24 18       	mov    0x18(%rsp),%rax
 105e8fe:	c5 f8 11 00          	vmovups %xmm0,(%rax)
 105e902:	4c 89 90 00 01 00 00 	mov    %r10,0x100(%rax)
 105e909:	48 89 a8 08 01 00 00 	mov    %rbp,0x108(%rax)
 105e910:	48 89 c5             	mov    %rax,%rbp
 105e913:	4c 89 a8 10 01 00 00 	mov    %r13,0x110(%rax)
 105e91a:	e9 3b 05 00 00       	jmp    105ee5a <my.interpreter::execute+0x108a>
 105e91f:	41 83 fc 01          	cmp    $0x1,%r12d
 105e923:	0f 85 0f 05 00 00    	jne    105ee38 <my.interpreter::execute+0x1068>
 105e929:	48 8d bc 24 50 06 00 	lea    0x650(%rsp),%rdi
 105e930:	00 
 105e931:	4c 89 fe             	mov    %r15,%rsi
 105e934:	48 89 da             	mov    %rbx,%rdx
 105e937:	4c 8b 04 24          	mov    (%rsp),%r8
 105e93b:	4d 89 f1             	mov    %r14,%r9
 105e93e:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105e945:	ff 74 24 28          	push   0x28(%rsp)
 105e949:	41 55                	push   %r13
 105e94b:	41 52                	push   %r10
 105e94d:	41 53                	push   %r11
 105e94f:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105e956:	e8 75 f4 ff ff       	call   105ddd0 <my.interpreter::execute>
 105e95b:	48 83 c4 30          	add    $0x30,%rsp
 105e95f:	0f b6 84 24 50 06 00 	movzbl 0x650(%rsp),%eax
 105e966:	00 
 105e967:	c5 f8 10 84 24 58 06 	vmovups 0x658(%rsp),%xmm0
 105e96e:	00 00 
 105e970:	48 8b 8c 24 50 07 00 	mov    0x750(%rsp),%rcx
 105e977:	00 
 105e978:	0f b6 94 24 58 07 00 	movzbl 0x758(%rsp),%edx
 105e97f:	00 
 105e980:	48 8b b4 24 60 07 00 	mov    0x760(%rsp),%rsi
 105e987:	00 
 105e988:	48 83 f8 01          	cmp    $0x1,%rax
 105e98c:	0f 84 1b 07 00 00    	je     105f0ad <my.interpreter::execute+0x12dd>
 105e992:	48 89 45 00          	mov    %rax,0x0(%rbp)
 105e996:	c5 f8 11 45 08       	vmovups %xmm0,0x8(%rbp)
 105e99b:	48 89 8d 00 01 00 00 	mov    %rcx,0x100(%rbp)
 105e9a2:	48 89 95 08 01 00 00 	mov    %rdx,0x108(%rbp)
 105e9a9:	48 89 b5 10 01 00 00 	mov    %rsi,0x110(%rbp)
 105e9b0:	e9 a5 04 00 00       	jmp    105ee5a <my.interpreter::execute+0x108a>
 105e9b5:	48 8b 6c 24 18       	mov    0x18(%rsp),%rbp
 105e9ba:	48 c7 45 00 00 00 00 	movq   $0x0,0x0(%rbp)
 105e9c1:	00 
 105e9c2:	48 c7 45 08 01 00 00 	movq   $0x1,0x8(%rbp)
 105e9c9:	00 
 105e9ca:	4c 89 9d 00 01 00 00 	mov    %r11,0x100(%rbp)
 105e9d1:	4c 89 95 08 01 00 00 	mov    %r10,0x108(%rbp)
 105e9d8:	e9 76 04 00 00       	jmp    105ee53 <my.interpreter::execute+0x1083>
 105e9dd:	48 01 c2             	add    %rax,%rdx
 105e9e0:	4c 8b 62 08          	mov    0x8(%rdx),%r12
 105e9e4:	49 8b 44 24 08       	mov    0x8(%r12),%rax
 105e9e9:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 105e9ee:	48 85 c0             	test   %rax,%rax
 105e9f1:	0f 84 f5 f4 ff ff    	je     105deec <my.interpreter::execute+0x11c>
 105e9f7:	31 ed                	xor    %ebp,%ebp
 105e9f9:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
 105ea00:	40 0f b6 c6          	movzbl %sil,%eax
 105ea04:	48 8d bc 24 d8 00 00 	lea    0xd8(%rsp),%rdi
 105ea0b:	00 
 105ea0c:	4c 89 fe             	mov    %r15,%rsi
 105ea0f:	48 89 da             	mov    %rbx,%rdx
 105ea12:	4c 8b 04 24          	mov    (%rsp),%r8
 105ea16:	4d 89 f1             	mov    %r14,%r9
 105ea19:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105ea20:	41 ff 74 ec 20       	push   0x20(%r12,%rbp,8)
 105ea25:	41 55                	push   %r13
 105ea27:	50                   	push   %rax
 105ea28:	41 52                	push   %r10
 105ea2a:	ff b4 24 48 0f 00 00 	push   0xf48(%rsp)
 105ea31:	e8 9a f3 ff ff       	call   105ddd0 <my.interpreter::execute>
 105ea36:	48 83 c4 30          	add    $0x30,%rsp
 105ea3a:	48 8b 84 24 e0 00 00 	mov    0xe0(%rsp),%rax
 105ea41:	00 
 105ea42:	4c 8b 94 24 d8 01 00 	mov    0x1d8(%rsp),%r10
 105ea49:	00 
 105ea4a:	0f b6 b4 24 e0 01 00 	movzbl 0x1e0(%rsp),%esi
 105ea51:	00 
 105ea52:	4c 8b ac 24 e8 01 00 	mov    0x1e8(%rsp),%r13
 105ea59:	00 
 105ea5a:	80 bc 24 d8 00 00 00 	cmpb   $0x1,0xd8(%rsp)
 105ea61:	01 
 105ea62:	0f 84 60 06 00 00    	je     105f0c8 <my.interpreter::execute+0x12f8>
 105ea68:	3c 01                	cmp    $0x1,%al
 105ea6a:	0f 84 ff 03 00 00    	je     105ee6f <my.interpreter::execute+0x109f>
 105ea70:	48 ff c5             	inc    %rbp
 105ea73:	48 39 6c 24 10       	cmp    %rbp,0x10(%rsp)
 105ea78:	48 8b 4c 24 30       	mov    0x30(%rsp),%rcx
 105ea7d:	75 81                	jne    105ea00 <my.interpreter::execute+0xc30>
 105ea7f:	e9 68 f4 ff ff       	jmp    105deec <my.interpreter::execute+0x11c>
 105ea84:	48 39 d0             	cmp    %rdx,%rax
 105ea87:	0f 83 d6 08 00 00    	jae    105f363 <my.interpreter::execute+0x1593>
 105ea8d:	48 89 c7             	mov    %rax,%rdi
 105ea90:	48 6b c7 38          	imul   $0x38,%rdi,%rax
 105ea94:	83 7c 01 20 09       	cmpl   $0x9,0x20(%rcx,%rax,1)
 105ea99:	0f 85 a8 0a 00 00    	jne    105f547 <my.interpreter::execute+0x1777>
 105ea9f:	48 01 c8             	add    %rcx,%rax
 105eaa2:	48 83 c0 20          	add    $0x20,%rax
 105eaa6:	48 8b 40 10          	mov    0x10(%rax),%rax
 105eaaa:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105eaae:	48 39 d6             	cmp    %rdx,%rsi
 105eab1:	0f 83 d1 08 00 00    	jae    105f388 <my.interpreter::execute+0x15b8>
 105eab7:	49 8b 46 78          	mov    0x78(%r14),%rax
 105eabb:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105eac2:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105eac6:	48 39 d6             	cmp    %rdx,%rsi
 105eac9:	0f 83 db 08 00 00    	jae    105f3aa <my.interpreter::execute+0x15da>
 105eacf:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
 105ead3:	c5 f8 11 45 00       	vmovups %xmm0,0x0(%rbp)
 105ead8:	4c 89 9d 00 01 00 00 	mov    %r11,0x100(%rbp)
 105eadf:	41 0f b6 c2          	movzbl %r10b,%eax
 105eae3:	e9 64 03 00 00       	jmp    105ee4c <my.interpreter::execute+0x107c>
 105eae8:	31 db                	xor    %ebx,%ebx
 105eaea:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105eaf1:	48 89 c6             	mov    %rax,%rsi
 105eaf4:	48 ff ce             	dec    %rsi
 105eaf7:	0f 80 36 0a 00 00    	jo     105f533 <my.interpreter::execute+0x1763>
 105eafd:	49 8b 46 78          	mov    0x78(%r14),%rax
 105eb01:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105eb05:	48 39 d6             	cmp    %rdx,%rsi
 105eb08:	0f 83 0e 08 00 00    	jae    105f31c <my.interpreter::execute+0x154c>
 105eb0e:	48 89 f1             	mov    %rsi,%rcx
 105eb11:	4c 89 44 24 28       	mov    %r8,0x28(%rsp)
 105eb16:	48 c1 e1 04          	shl    $0x4,%rcx
 105eb1a:	80 7c 08 20 03       	cmpb   $0x3,0x20(%rax,%rcx,1)
 105eb1f:	0f 85 d1 03 00 00    	jne    105eef6 <my.interpreter::execute+0x1126>
 105eb25:	4c 8b 7c 08 28       	mov    0x28(%rax,%rcx,1),%r15
 105eb2a:	49 8b 06             	mov    (%r14),%rax
 105eb2d:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105eb31:	4c 89 f9             	mov    %r15,%rcx
 105eb34:	49 39 d7             	cmp    %rdx,%r15
 105eb37:	0f 83 01 08 00 00    	jae    105f33e <my.interpreter::execute+0x156e>
 105eb3d:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 105eb41:	83 7c 08 20 06       	cmpl   $0x6,0x20(%rax,%rcx,1)
 105eb46:	0f 85 aa 03 00 00    	jne    105eef6 <my.interpreter::execute+0x1126>
 105eb4c:	48 89 7c 24 48       	mov    %rdi,0x48(%rsp)
 105eb51:	48 8d bc 24 b0 0a 00 	lea    0xab0(%rsp),%rdi
 105eb58:	00 
 105eb59:	4c 89 f6             	mov    %r14,%rsi
 105eb5c:	48 8b 54 24 20       	mov    0x20(%rsp),%rdx
 105eb61:	e8 4a 4b 00 00       	call   10636b0 <my.heap::allocate_class>
 105eb66:	48 8b 8c 24 b0 0a 00 	mov    0xab0(%rsp),%rcx
 105eb6d:	00 
 105eb6e:	49 8b 46 78          	mov    0x78(%r14),%rax
 105eb72:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105eb79:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105eb7d:	48 39 d6             	cmp    %rdx,%rsi
 105eb80:	0f 83 ac 06 00 00    	jae    105f232 <my.interpreter::execute+0x1462>
 105eb86:	48 89 f7             	mov    %rsi,%rdi
 105eb89:	48 c1 e7 04          	shl    $0x4,%rdi
 105eb8d:	48 c7 44 38 20 03 00 	movq   $0x3,0x20(%rax,%rdi,1)
 105eb94:	00 00 
 105eb96:	48 89 4c 38 28       	mov    %rcx,0x28(%rax,%rdi,1)
 105eb9b:	49 89 46 78          	mov    %rax,0x78(%r14)
 105eb9f:	49 8b b6 80 00 00 00 	mov    0x80(%r14),%rsi
 105eba6:	48 89 f2             	mov    %rsi,%rdx
 105eba9:	48 ff c2             	inc    %rdx
 105ebac:	0f 80 ea 08 00 00    	jo     105f49c <my.interpreter::execute+0x16cc>
 105ebb2:	48 8d 0c 38          	lea    (%rax,%rdi,1),%rcx
 105ebb6:	48 83 c1 20          	add    $0x20,%rcx
 105ebba:	49 89 96 80 00 00 00 	mov    %rdx,0x80(%r14)
 105ebc1:	0f b6 01             	movzbl (%rcx),%eax
 105ebc4:	83 f8 03             	cmp    $0x3,%eax
 105ebc7:	0f 85 1f 08 00 00    	jne    105f3ec <my.interpreter::execute+0x161c>
 105ebcd:	48 8b 71 08          	mov    0x8(%rcx),%rsi
 105ebd1:	49 83 ff ff          	cmp    $0xffffffffffffffff,%r15
 105ebd5:	48 89 6c 24 18       	mov    %rbp,0x18(%rsp)
 105ebda:	4c 89 6c 24 58       	mov    %r13,0x58(%rsp)
 105ebdf:	4c 89 7c 24 50       	mov    %r15,0x50(%rsp)
 105ebe4:	48 89 34 24          	mov    %rsi,(%rsp)
 105ebe8:	74 7c                	je     105ec66 <my.interpreter::execute+0xe96>
 105ebea:	4c 89 f7             	mov    %r14,%rdi
 105ebed:	4c 89 fa             	mov    %r15,%rdx
 105ebf0:	e8 bb b3 00 00       	call   1069fb0 <my.heap::inherit_class_methods>
 105ebf5:	49 8b 96 a8 00 00 00 	mov    0xa8(%r14),%rdx
 105ebfc:	48 8d bc 24 20 0e 00 	lea    0xe20(%rsp),%rdi
 105ec03:	00 
 105ec04:	b9 01 00 00 00       	mov    $0x1,%ecx
 105ec09:	4c 89 f6             	mov    %r14,%rsi
 105ec0c:	e8 9f cf 00 00       	call   106bbb0 <my.interpreter::new_env>
 105ec11:	4c 8b a4 24 20 0e 00 	mov    0xe20(%rsp),%r12
 105ec18:	00 
 105ec19:	4c 89 f7             	mov    %r14,%rdi
 105ec1c:	4c 89 e6             	mov    %r12,%rsi
 105ec1f:	31 d2                	xor    %edx,%edx
 105ec21:	b9 03 00 00 00       	mov    $0x3,%ecx
 105ec26:	4d 89 f8             	mov    %r15,%r8
 105ec29:	e8 12 d1 00 00       	call   106bd40 <my.heap::set_env_slot>
 105ec2e:	4d 8b be a8 00 00 00 	mov    0xa8(%r14),%r15
 105ec35:	49 8b 86 b0 00 00 00 	mov    0xb0(%r14),%rax
 105ec3c:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105ec40:	48 3b 48 10          	cmp    0x10(%rax),%rcx
 105ec44:	0f 83 2c 06 00 00    	jae    105f276 <my.interpreter::execute+0x14a6>
 105ec4a:	4c 89 7c c8 20       	mov    %r15,0x20(%rax,%rcx,8)
 105ec4f:	48 ff c1             	inc    %rcx
 105ec52:	48 89 48 08          	mov    %rcx,0x8(%rax)
 105ec56:	49 89 86 b0 00 00 00 	mov    %rax,0xb0(%r14)
 105ec5d:	4d 89 a6 a8 00 00 00 	mov    %r12,0xa8(%r14)
 105ec64:	eb 07                	jmp    105ec6d <my.interpreter::execute+0xe9d>
 105ec66:	4d 8b a6 a8 00 00 00 	mov    0xa8(%r14),%r12
 105ec6d:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105ec72:	4c 8b 68 08          	mov    0x8(%rax),%r13
 105ec76:	4d 85 ed             	test   %r13,%r13
 105ec79:	48 8b 5c 24 30       	mov    0x30(%rsp),%rbx
 105ec7e:	0f 84 0f 01 00 00    	je     105ed93 <my.interpreter::execute+0xfc3>
 105ec84:	31 ed                	xor    %ebp,%ebp
 105ec86:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105ec8d:	0f 1f 84 00 00 00 00 
 105ec94:	00 
 105ec95:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105ec9c:	0f 1f 84 00 00 00 00 
 105eca3:	00 
 105eca4:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105ecab:	0f 1f 84 00 00 00 00 
 105ecb2:	00 
 105ecb3:	66 66 66 66 2e 0f 1f 	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 105ecba:	84 00 00 00 00 00 
 105ecc0:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 105ecc5:	48 8b 74 e8 20       	mov    0x20(%rax,%rbp,8),%rsi
 105ecca:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 105ecce:	48 89 f0             	mov    %rsi,%rax
 105ecd1:	48 39 d6             	cmp    %rdx,%rsi
 105ecd4:	0f 83 97 00 00 00    	jae    105ed71 <my.interpreter::execute+0xfa1>
 105ecda:	48 8d 04 80          	lea    (%rax,%rax,4),%rax
 105ecde:	48 c1 e0 04          	shl    $0x4,%rax
 105ece2:	4c 8b 7c 03 48       	mov    0x48(%rbx,%rax,1),%r15
 105ece7:	4d 3b 7e 40          	cmp    0x40(%r14),%r15
 105eceb:	48 c7 84 24 a0 00 00 	movq   $0xa,0xa0(%rsp)
 105ecf2:	00 0a 00 00 00 
 105ecf7:	48 89 b4 24 a8 00 00 	mov    %rsi,0xa8(%rsp)
 105ecfe:	00 
 105ecff:	4c 89 bc 24 b0 00 00 	mov    %r15,0xb0(%rsp)
 105ed06:	00 
 105ed07:	4c 89 a4 24 b8 00 00 	mov    %r12,0xb8(%rsp)
 105ed0e:	00 
 105ed0f:	0f 94 84 24 c0 00 00 	sete   0xc0(%rsp)
 105ed16:	00 
 105ed17:	48 8d bc 24 58 0d 00 	lea    0xd58(%rsp),%rdi
 105ed1e:	00 
 105ed1f:	4c 89 f6             	mov    %r14,%rsi
 105ed22:	48 8d 94 24 a0 00 00 	lea    0xa0(%rsp),%rdx
 105ed29:	00 
 105ed2a:	e8 71 b6 ff ff       	call   105a3a0 <my.heap::allocate>
 105ed2f:	4c 8b a4 24 58 0d 00 	mov    0xd58(%rsp),%r12
 105ed36:	00 
 105ed37:	4c 89 f7             	mov    %r14,%rdi
 105ed3a:	4c 89 fe             	mov    %r15,%rsi
 105ed3d:	e8 9e a5 00 00       	call   10692e0 <my.heap::string_hash>
 105ed42:	4c 89 f7             	mov    %r14,%rdi
 105ed45:	48 8b 34 24          	mov    (%rsp),%rsi
 105ed49:	4c 89 fa             	mov    %r15,%rdx
 105ed4c:	89 c1                	mov    %eax,%ecx
 105ed4e:	41 b8 03 00 00 00    	mov    $0x3,%r8d
 105ed54:	4d 89 e1             	mov    %r12,%r9
 105ed57:	e8 34 b4 00 00       	call   106a190 <my.heap::set_class_method>
 105ed5c:	4d 8b a6 a8 00 00 00 	mov    0xa8(%r14),%r12
 105ed63:	48 ff c5             	inc    %rbp
 105ed66:	49 39 ed             	cmp    %rbp,%r13
 105ed69:	0f 85 51 ff ff ff    	jne    105ecc0 <my.interpreter::execute+0xef0>
 105ed6f:	eb 22                	jmp    105ed93 <my.interpreter::execute+0xfc3>
 105ed71:	48 89 f0             	mov    %rsi,%rax
 105ed74:	48 c1 f8 3f          	sar    $0x3f,%rax
 105ed78:	48 21 d0             	and    %rdx,%rax
 105ed7b:	48 01 f0             	add    %rsi,%rax
 105ed7e:	48 39 d0             	cmp    %rdx,%rax
 105ed81:	0f 82 53 ff ff ff    	jb     105ecda <my.interpreter::execute+0xf0a>
 105ed87:	48 8d 3d d2 37 02 00 	lea    0x237d2(%rip),%rdi        # 1082560 <core_durable_error.verbs+0x2e50>
 105ed8e:	e8 6d 59 fc ff       	call   1024700 <myl_core_trap>
 105ed93:	48 8b 5c 24 50       	mov    0x50(%rsp),%rbx
 105ed98:	48 83 fb ff          	cmp    $0xffffffffffffffff,%rbx
 105ed9c:	48 8b 6c 24 18       	mov    0x18(%rsp),%rbp
 105eda1:	4c 8b 6c 24 58       	mov    0x58(%rsp),%r13
 105eda6:	74 27                	je     105edcf <my.interpreter::execute+0xfff>
 105eda8:	49 8b 86 b0 00 00 00 	mov    0xb0(%r14),%rax
 105edaf:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105edb3:	48 85 c9             	test   %rcx,%rcx
 105edb6:	0f 84 31 07 00 00    	je     105f4ed <my.interpreter::execute+0x171d>
 105edbc:	48 8b 54 c8 18       	mov    0x18(%rax,%rcx,8),%rdx
 105edc1:	48 ff c9             	dec    %rcx
 105edc4:	48 89 48 08          	mov    %rcx,0x8(%rax)
 105edc8:	49 89 96 a8 00 00 00 	mov    %rdx,0xa8(%r14)
 105edcf:	4c 89 f7             	mov    %r14,%rdi
 105edd2:	48 8b 74 24 20       	mov    0x20(%rsp),%rsi
 105edd7:	48 8b 54 24 60       	mov    0x60(%rsp),%rdx
 105eddc:	e8 af 83 00 00       	call   1067190 <my.interpreter::define>
 105ede1:	49 8b 86 80 00 00 00 	mov    0x80(%r14),%rax
 105ede8:	48 89 c6             	mov    %rax,%rsi
 105edeb:	48 ff ce             	dec    %rsi
 105edee:	0f 80 d1 06 00 00    	jo     105f4c5 <my.interpreter::execute+0x16f5>
 105edf4:	49 89 b6 80 00 00 00 	mov    %rsi,0x80(%r14)
 105edfb:	49 8b 46 78          	mov    0x78(%r14),%rax
 105edff:	48 8b 50 08          	mov    0x8(%rax),%rdx
 105ee03:	48 39 d6             	cmp    %rdx,%rsi
 105ee06:	4c 8b 5c 24 48       	mov    0x48(%rsp),%r11
 105ee0b:	48 8b 7c 24 28       	mov    0x28(%rsp),%rdi
 105ee10:	0f 83 3e 04 00 00    	jae    105f254 <my.interpreter::execute+0x1484>
 105ee16:	48 83 fb ff          	cmp    $0xffffffffffffffff,%rbx
 105ee1a:	74 1c                	je     105ee38 <my.interpreter::execute+0x1068>
 105ee1c:	48 89 f0             	mov    %rsi,%rax
 105ee1f:	48 ff c8             	dec    %rax
 105ee22:	0f 80 d5 06 00 00    	jo     105f4fd <my.interpreter::execute+0x172d>
 105ee28:	49 89 86 80 00 00 00 	mov    %rax,0x80(%r14)
 105ee2f:	48 39 d0             	cmp    %rdx,%rax
 105ee32:	0f 83 54 04 00 00    	jae    105f28c <my.interpreter::execute+0x14bc>
 105ee38:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
 105ee3c:	c5 f8 11 45 00       	vmovups %xmm0,0x0(%rbp)
 105ee41:	4c 89 9d 00 01 00 00 	mov    %r11,0x100(%rbp)
 105ee48:	40 0f b6 c7          	movzbl %dil,%eax
 105ee4c:	48 89 85 08 01 00 00 	mov    %rax,0x108(%rbp)
 105ee53:	4c 89 ad 10 01 00 00 	mov    %r13,0x110(%rbp)
 105ee5a:	48 89 e8             	mov    %rbp,%rax
 105ee5d:	48 81 c4 e8 0e 00 00 	add    $0xee8,%rsp
 105ee64:	5b                   	pop    %rbx
 105ee65:	41 5c                	pop    %r12
 105ee67:	41 5d                	pop    %r13
 105ee69:	41 5e                	pop    %r14
 105ee6b:	41 5f                	pop    %r15
 105ee6d:	5d                   	pop    %rbp
 105ee6e:	c3                   	ret
 105ee6f:	48 89 f3             	mov    %rsi,%rbx
 105ee72:	b8 01 00 00 00       	mov    $0x1,%eax
 105ee77:	31 f6                	xor    %esi,%esi
 105ee79:	31 d2                	xor    %edx,%edx
 105ee7b:	e9 79 f0 ff ff       	jmp    105def9 <my.interpreter::execute+0x129>
 105ee80:	c5 f8 10 84 24 88 08 	vmovups 0x888(%rsp),%xmm0
 105ee87:	00 00 
 105ee89:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105ee8e:	48 8d 3d bb 19 02 00 	lea    0x219bb(%rip),%rdi        # 1080850 <core_durable_error.verbs+0x1140>
 105ee95:	4c 89 d8             	mov    %r11,%rax
 105ee98:	e8 63 7c ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 105ee9d:	48 c7 45 00 01 00 00 	movq   $0x1,0x0(%rbp)
 105eea4:	00 
 105eea5:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 105eeaa:	c5 f8 11 45 08       	vmovups %xmm0,0x8(%rbp)
 105eeaf:	48 89 85 00 01 00 00 	mov    %rax,0x100(%rbp)
 105eeb6:	e9 16 fb ff ff       	jmp    105e9d1 <my.interpreter::execute+0xc01>
 105eebb:	41 0f b6 c7          	movzbl %r15b,%eax
 105eebf:	c5 f8 10 84 24 40 05 	vmovups 0x540(%rsp),%xmm0
 105eec6:	00 00 
 105eec8:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105eecd:	48 8d 3d 0c 1a 02 00 	lea    0x21a0c(%rip),%rdi        # 10808e0 <core_durable_error.verbs+0x11d0>
 105eed4:	e9 07 01 00 00       	jmp    105efe0 <my.interpreter::execute+0x1210>
 105eed9:	48 8d 3d 20 36 02 00 	lea    0x23620(%rip),%rdi        # 1082500 <core_durable_error.verbs+0x2df0>
 105eee0:	e8 1b 7c ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 105eee5:	48 8d 3d 44 18 02 00 	lea    0x21844(%rip),%rdi        # 1080730 <core_durable_error.verbs+0x1020>
 105eeec:	e8 0f 7c ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 105eef1:	e9 38 f0 ff ff       	jmp    105df2e <my.interpreter::execute+0x15e>
 105eef6:	49 89 fe             	mov    %rdi,%r14
 105eef9:	48 8d 3d 40 34 fb ff 	lea    -0x4cbc0(%rip),%rdi        # 1012340 <core_number_pairs+0xb0e0>
 105ef00:	e8 fb 52 fc ff       	call   1024200 <myl_core_owned_octets_copy>
 105ef05:	48 8d 3d 84 63 02 00 	lea    0x26384(%rip),%rdi        # 1085290 <core_durable_error.verbs+0x5b80>
 105ef0c:	e8 af 7b ff ff       	call   1056ac0 <myl_core_err_trace_origin_preserve_most>
 105ef11:	4c 8b 44 24 28       	mov    0x28(%rsp),%r8
 105ef16:	e9 07 01 00 00       	jmp    105f022 <my.interpreter::execute+0x1252>
 105ef1b:	40 0f b6 c7          	movzbl %dil,%eax
 105ef1f:	c5 f8 10 84 24 a0 09 	vmovups 0x9a0(%rsp),%xmm0
 105ef26:	00 00 
 105ef28:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105ef2d:	48 8d 3d bc 18 02 00 	lea    0x218bc(%rip),%rdi        # 10807f0 <core_durable_error.verbs+0x10e0>
 105ef34:	4c 89 d9             	mov    %r11,%rcx
 105ef37:	e8 c4 7b ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 105ef3c:	48 c7 45 00 01 00 00 	movq   $0x1,0x0(%rbp)
 105ef43:	00 
 105ef44:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 105ef49:	c5 f8 11 45 08       	vmovups %xmm0,0x8(%rbp)
 105ef4e:	48 89 8d 00 01 00 00 	mov    %rcx,0x100(%rbp)
 105ef55:	e9 f2 fe ff ff       	jmp    105ee4c <my.interpreter::execute+0x107c>
 105ef5a:	c5 f8 10 84 24 10 03 	vmovups 0x310(%rsp),%xmm0
 105ef61:	00 00 
 105ef63:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105ef68:	48 8d 3d 01 1a 02 00 	lea    0x21a01(%rip),%rdi        # 1080970 <core_durable_error.verbs+0x1260>
 105ef6f:	e8 8c 7b ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 105ef74:	48 8b 44 24 18       	mov    0x18(%rsp),%rax
 105ef79:	48 c7 00 01 00 00 00 	movq   $0x1,(%rax)
 105ef80:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 105ef85:	c5 f8 11 40 08       	vmovups %xmm0,0x8(%rax)
 105ef8a:	e9 73 f9 ff ff       	jmp    105e902 <my.interpreter::execute+0xb32>
 105ef8f:	48 8b 8c 24 00 02 00 	mov    0x200(%rsp),%rcx
 105ef96:	00 
 105ef97:	48 8d 3d 02 1a 02 00 	lea    0x21a02(%rip),%rdi        # 10809a0 <core_durable_error.verbs+0x1290>
 105ef9e:	4c 89 da             	mov    %r11,%rdx
 105efa1:	e8 5a 7b ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 105efa6:	48 8b 6c 24 18       	mov    0x18(%rsp),%rbp
 105efab:	48 c7 45 00 01 00 00 	movq   $0x1,0x0(%rbp)
 105efb2:	00 
 105efb3:	48 89 45 08          	mov    %rax,0x8(%rbp)
 105efb7:	48 89 4d 10          	mov    %rcx,0x10(%rbp)
 105efbb:	48 89 95 00 01 00 00 	mov    %rdx,0x100(%rbp)
 105efc2:	e9 0a fa ff ff       	jmp    105e9d1 <my.interpreter::execute+0xc01>
 105efc7:	41 0f b6 c7          	movzbl %r15b,%eax
 105efcb:	c5 f8 10 84 24 28 04 	vmovups 0x428(%rsp),%xmm0
 105efd2:	00 00 
 105efd4:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105efd9:	48 8d 3d 60 19 02 00 	lea    0x21960(%rip),%rdi        # 1080940 <core_durable_error.verbs+0x1230>
 105efe0:	e8 1b 7b ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 105efe5:	48 c7 45 00 01 00 00 	movq   $0x1,0x0(%rbp)
 105efec:	00 
 105efed:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 105eff2:	c5 f8 11 45 08       	vmovups %xmm0,0x8(%rbp)
 105eff7:	48 89 9d 00 01 00 00 	mov    %rbx,0x100(%rbp)
 105effe:	e9 49 fe ff ff       	jmp    105ee4c <my.interpreter::execute+0x107c>
 105f003:	49 89 fe             	mov    %rdi,%r14
 105f006:	48 8b 84 24 e0 00 00 	mov    0xe0(%rsp),%rax
 105f00d:	00 
 105f00e:	48 8b 9c 24 e8 00 00 	mov    0xe8(%rsp),%rbx
 105f015:	00 
 105f016:	48 8d 3d 13 62 02 00 	lea    0x26213(%rip),%rdi        # 1085230 <core_durable_error.verbs+0x5b20>
 105f01d:	e8 de 7a ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 105f022:	48 8d 3d 07 35 02 00 	lea    0x23507(%rip),%rdi        # 1082530 <core_durable_error.verbs+0x2e20>
 105f029:	e8 d2 7a ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 105f02e:	48 8d 3d 2b 17 02 00 	lea    0x2172b(%rip),%rdi        # 1080760 <core_durable_error.verbs+0x1050>
 105f035:	e8 c6 7a ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 105f03a:	48 c7 45 00 01 00 00 	movq   $0x1,0x0(%rbp)
 105f041:	00 
 105f042:	48 89 45 08          	mov    %rax,0x8(%rbp)
 105f046:	48 89 5d 10          	mov    %rbx,0x10(%rbp)
 105f04a:	4c 89 b5 00 01 00 00 	mov    %r14,0x100(%rbp)
 105f051:	4c 89 85 08 01 00 00 	mov    %r8,0x108(%rbp)
 105f058:	e9 f6 fd ff ff       	jmp    105ee53 <my.interpreter::execute+0x1083>
 105f05d:	c5 f8 10 84 24 80 0b 	vmovups 0xb80(%rsp),%xmm0
 105f064:	00 00 
 105f066:	c5 f8 29 44 24 30    	vmovaps %xmm0,0x30(%rsp)
 105f06c:	c5 f8 10 84 24 80 0c 	vmovups 0xc80(%rsp),%xmm0
 105f073:	00 00 
 105f075:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105f07a:	48 8d 3d 8f 18 02 00 	lea    0x2188f(%rip),%rdi        # 1080910 <core_durable_error.verbs+0x1200>
 105f081:	4c 89 d8             	mov    %r11,%rax
 105f084:	e8 77 7a ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 105f089:	48 c7 45 00 01 00 00 	movq   $0x1,0x0(%rbp)
 105f090:	00 
 105f091:	c5 f8 28 44 24 30    	vmovaps 0x30(%rsp),%xmm0
 105f097:	c5 f8 11 45 08       	vmovups %xmm0,0x8(%rbp)
 105f09c:	48 89 85 00 01 00 00 	mov    %rax,0x100(%rbp)
 105f0a3:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 105f0a8:	e9 33 f8 ff ff       	jmp    105e8e0 <my.interpreter::execute+0xb10>
 105f0ad:	48 8d 3d fc 17 02 00 	lea    0x217fc(%rip),%rdi        # 10808b0 <core_durable_error.verbs+0x11a0>
 105f0b4:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 105f0b9:	e8 42 7a ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 105f0be:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 105f0c3:	e9 ca f8 ff ff       	jmp    105e992 <my.interpreter::execute+0xbc2>
 105f0c8:	48 89 f3             	mov    %rsi,%rbx
 105f0cb:	48 8b 8c 24 e8 00 00 	mov    0xe8(%rsp),%rcx
 105f0d2:	00 
 105f0d3:	48 8d 3d f6 60 02 00 	lea    0x260f6(%rip),%rdi        # 10851d0 <core_durable_error.verbs+0x5ac0>
 105f0da:	e8 21 7a ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 105f0df:	ba 01 00 00 00       	mov    $0x1,%edx
 105f0e4:	40 b6 01             	mov    $0x1,%sil
 105f0e7:	e9 0d ee ff ff       	jmp    105def9 <my.interpreter::execute+0x129>
 105f0ec:	4c 89 e0             	mov    %r12,%rax
 105f0ef:	48 c1 f8 3f          	sar    $0x3f,%rax
 105f0f3:	48 21 d0             	and    %rdx,%rax
 105f0f6:	4c 01 e0             	add    %r12,%rax
 105f0f9:	48 39 d0             	cmp    %rdx,%rax
 105f0fc:	0f 82 07 ed ff ff    	jb     105de09 <my.interpreter::execute+0x39>
 105f102:	48 8d 3d f7 15 02 00 	lea    0x215f7(%rip),%rdi        # 1080700 <core_durable_error.verbs+0xff0>
 105f109:	4c 89 e6             	mov    %r12,%rsi
 105f10c:	e8 ef 55 fc ff       	call   1024700 <myl_core_trap>
 105f111:	48 89 c1             	mov    %rax,%rcx
 105f114:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105f118:	48 21 d1             	and    %rdx,%rcx
 105f11b:	48 01 c1             	add    %rax,%rcx
 105f11e:	48 39 d1             	cmp    %rdx,%rcx
 105f121:	0f 82 84 ef ff ff    	jb     105e0ab <my.interpreter::execute+0x2db>
 105f127:	48 8d 3d 62 16 02 00 	lea    0x21662(%rip),%rdi        # 1080790 <core_durable_error.verbs+0x1080>
 105f12e:	48 89 c6             	mov    %rax,%rsi
 105f131:	e8 ca 55 fc ff       	call   1024700 <myl_core_trap>
 105f136:	48 89 f0             	mov    %rsi,%rax
 105f139:	48 c1 f8 3f          	sar    $0x3f,%rax
 105f13d:	48 21 d0             	and    %rdx,%rax
 105f140:	48 01 f0             	add    %rsi,%rax
 105f143:	48 39 d0             	cmp    %rdx,%rax
 105f146:	0f 82 14 f0 ff ff    	jb     105e160 <my.interpreter::execute+0x390>
 105f14c:	48 8d 3d cd 16 02 00 	lea    0x216cd(%rip),%rdi        # 1080820 <core_durable_error.verbs+0x1110>
 105f153:	e8 a8 55 fc ff       	call   1024700 <myl_core_trap>
 105f158:	48 89 74 24 20       	mov    %rsi,0x20(%rsp)
 105f15d:	be 08 00 00 00       	mov    $0x8,%esi
 105f162:	48 89 c7             	mov    %rax,%rdi
 105f165:	48 89 54 24 10       	mov    %rdx,0x10(%rsp)
 105f16a:	e8 11 3b fc ff       	call   1022c80 <myl_core_list_grow>
 105f16f:	48 8b 74 24 20       	mov    0x20(%rsp),%rsi
 105f174:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 105f179:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105f17d:	e9 11 ed ff ff       	jmp    105de93 <my.interpreter::execute+0xc3>
 105f182:	4c 89 e0             	mov    %r12,%rax
 105f185:	48 c1 f8 3f          	sar    $0x3f,%rax
 105f189:	48 21 d0             	and    %rdx,%rax
 105f18c:	4c 01 e0             	add    %r12,%rax
 105f18f:	48 39 d0             	cmp    %rdx,%rax
 105f192:	0f 82 3a ed ff ff    	jb     105ded2 <my.interpreter::execute+0x102>
 105f198:	48 8d 3d 01 60 02 00 	lea    0x26001(%rip),%rdi        # 10851a0 <core_durable_error.verbs+0x5a90>
 105f19f:	4c 89 e6             	mov    %r12,%rsi
 105f1a2:	e8 59 55 fc ff       	call   1024700 <myl_core_trap>
 105f1a7:	48 89 f7             	mov    %rsi,%rdi
 105f1aa:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105f1ae:	48 21 d7             	and    %rdx,%rdi
 105f1b1:	48 01 f7             	add    %rsi,%rdi
 105f1b4:	48 39 d7             	cmp    %rdx,%rdi
 105f1b7:	0f 82 17 f0 ff ff    	jb     105e1d4 <my.interpreter::execute+0x404>
 105f1bd:	48 8d 3d 6c 18 02 00 	lea    0x2186c(%rip),%rdi        # 1080a30 <core_durable_error.verbs+0x1320>
 105f1c4:	e8 37 55 fc ff       	call   1024700 <myl_core_trap>
 105f1c9:	48 89 c6             	mov    %rax,%rsi
 105f1cc:	48 c1 fe 3f          	sar    $0x3f,%rsi
 105f1d0:	48 21 d6             	and    %rdx,%rsi
 105f1d3:	48 01 c6             	add    %rax,%rsi
 105f1d6:	48 39 d6             	cmp    %rdx,%rsi
 105f1d9:	0f 82 e0 f6 ff ff    	jb     105e8bf <my.interpreter::execute+0xaef>
 105f1df:	48 8d 3d 9a 19 02 00 	lea    0x2199a(%rip),%rdi        # 1080b80 <core_durable_error.verbs+0x1470>
 105f1e6:	48 89 c6             	mov    %rax,%rsi
 105f1e9:	e8 12 55 fc ff       	call   1024700 <myl_core_trap>
 105f1ee:	49 89 f0             	mov    %rsi,%r8
 105f1f1:	49 c1 f8 3f          	sar    $0x3f,%r8
 105f1f5:	49 21 d0             	and    %rdx,%r8
 105f1f8:	49 01 f0             	add    %rsi,%r8
 105f1fb:	49 39 d0             	cmp    %rdx,%r8
 105f1fe:	0f 82 f6 ed ff ff    	jb     105dffa <my.interpreter::execute+0x22a>
 105f204:	48 8d 3d b5 18 02 00 	lea    0x218b5(%rip),%rdi        # 1080ac0 <core_durable_error.verbs+0x13b0>
 105f20b:	e8 f0 54 fc ff       	call   1024700 <myl_core_trap>
 105f210:	48 89 f7             	mov    %rsi,%rdi
 105f213:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105f217:	48 21 d7             	and    %rdx,%rdi
 105f21a:	48 01 f7             	add    %rsi,%rdi
 105f21d:	48 39 d7             	cmp    %rdx,%rdi
 105f220:	0f 82 70 f2 ff ff    	jb     105e496 <my.interpreter::execute+0x6c6>
 105f226:	48 8d 3d f3 18 02 00 	lea    0x218f3(%rip),%rdi        # 1080b20 <core_durable_error.verbs+0x1410>
 105f22d:	e8 ce 54 fc ff       	call   1024700 <myl_core_trap>
 105f232:	48 89 f7             	mov    %rsi,%rdi
 105f235:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105f239:	48 21 d7             	and    %rdx,%rdi
 105f23c:	48 01 f7             	add    %rsi,%rdi
 105f23f:	48 39 d7             	cmp    %rdx,%rdi
 105f242:	0f 82 41 f9 ff ff    	jb     105eb89 <my.interpreter::execute+0xdb9>
 105f248:	48 8d 3d 41 33 02 00 	lea    0x23341(%rip),%rdi        # 1082590 <core_durable_error.verbs+0x2e80>
 105f24f:	e8 ac 54 fc ff       	call   1024700 <myl_core_trap>
 105f254:	48 89 f0             	mov    %rsi,%rax
 105f257:	48 c1 f8 3f          	sar    $0x3f,%rax
 105f25b:	48 21 d0             	and    %rdx,%rax
 105f25e:	48 01 f0             	add    %rsi,%rax
 105f261:	48 39 d0             	cmp    %rdx,%rax
 105f264:	0f 82 ac fb ff ff    	jb     105ee16 <my.interpreter::execute+0x1046>
 105f26a:	48 8d 3d af 33 02 00 	lea    0x233af(%rip),%rdi        # 1082620 <core_durable_error.verbs+0x2f10>
 105f271:	e8 8a 54 fc ff       	call   1024700 <myl_core_trap>
 105f276:	be 08 00 00 00       	mov    $0x8,%esi
 105f27b:	48 89 c7             	mov    %rax,%rdi
 105f27e:	e8 fd 39 fc ff       	call   1022c80 <myl_core_list_grow>
 105f283:	48 8b 48 08          	mov    0x8(%rax),%rcx
 105f287:	e9 be f9 ff ff       	jmp    105ec4a <my.interpreter::execute+0xe7a>
 105f28c:	48 89 c1             	mov    %rax,%rcx
 105f28f:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105f293:	48 21 d1             	and    %rdx,%rcx
 105f296:	48 01 c1             	add    %rax,%rcx
 105f299:	48 39 d1             	cmp    %rdx,%rcx
 105f29c:	0f 82 96 fb ff ff    	jb     105ee38 <my.interpreter::execute+0x1068>
 105f2a2:	48 8d 3d d7 33 02 00 	lea    0x233d7(%rip),%rdi        # 1082680 <core_durable_error.verbs+0x2f70>
 105f2a9:	48 89 c6             	mov    %rax,%rsi
 105f2ac:	e8 4f 54 fc ff       	call   1024700 <myl_core_trap>
 105f2b1:	48 89 f1             	mov    %rsi,%rcx
 105f2b4:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105f2b8:	48 21 d1             	and    %rdx,%rcx
 105f2bb:	48 01 f1             	add    %rsi,%rcx
 105f2be:	48 39 d1             	cmp    %rdx,%rcx
 105f2c1:	0f 82 ea f4 ff ff    	jb     105e7b1 <my.interpreter::execute+0x9e1>
 105f2c7:	48 8d 3d a2 19 02 00 	lea    0x219a2(%rip),%rdi        # 1080c70 <core_durable_error.verbs+0x1560>
 105f2ce:	e8 2d 54 fc ff       	call   1024700 <myl_core_trap>
 105f2d3:	48 89 f1             	mov    %rsi,%rcx
 105f2d6:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105f2da:	48 21 d1             	and    %rdx,%rcx
 105f2dd:	48 01 f1             	add    %rsi,%rcx
 105f2e0:	48 39 d1             	cmp    %rdx,%rcx
 105f2e3:	0f 82 84 f5 ff ff    	jb     105e86d <my.interpreter::execute+0xa9d>
 105f2e9:	48 8d 3d c0 18 02 00 	lea    0x218c0(%rip),%rdi        # 1080bb0 <core_durable_error.verbs+0x14a0>
 105f2f0:	e8 0b 54 fc ff       	call   1024700 <myl_core_trap>
 105f2f5:	48 89 d8             	mov    %rbx,%rax
 105f2f8:	48 c1 f8 3f          	sar    $0x3f,%rax
 105f2fc:	48 21 d0             	and    %rdx,%rax
 105f2ff:	48 01 d8             	add    %rbx,%rax
 105f302:	48 39 d0             	cmp    %rdx,%rax
 105f305:	0f 82 e5 f0 ff ff    	jb     105e3f0 <my.interpreter::execute+0x620>
 105f30b:	48 8d 3d 4e 5f 02 00 	lea    0x25f4e(%rip),%rdi        # 1085260 <core_durable_error.verbs+0x5b50>
 105f312:	48 8b 74 24 28       	mov    0x28(%rsp),%rsi
 105f317:	e8 e4 53 fc ff       	call   1024700 <myl_core_trap>
 105f31c:	48 89 f1             	mov    %rsi,%rcx
 105f31f:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105f323:	48 21 d1             	and    %rdx,%rcx
 105f326:	48 01 f1             	add    %rsi,%rcx
 105f329:	48 39 d1             	cmp    %rdx,%rcx
 105f32c:	0f 82 df f7 ff ff    	jb     105eb11 <my.interpreter::execute+0xd41>
 105f332:	48 8d 3d b7 5f 02 00 	lea    0x25fb7(%rip),%rdi        # 10852f0 <core_durable_error.verbs+0x5be0>
 105f339:	e8 c2 53 fc ff       	call   1024700 <myl_core_trap>
 105f33e:	4c 89 f9             	mov    %r15,%rcx
 105f341:	48 c1 f9 3f          	sar    $0x3f,%rcx
 105f345:	48 21 d1             	and    %rdx,%rcx
 105f348:	4c 01 f9             	add    %r15,%rcx
 105f34b:	48 39 d1             	cmp    %rdx,%rcx
 105f34e:	0f 82 e9 f7 ff ff    	jb     105eb3d <my.interpreter::execute+0xd6d>
 105f354:	48 8d 3d a5 7f 02 00 	lea    0x27fa5(%rip),%rdi        # 1087300 <core_durable_error.verbs+0x7bf0>
 105f35b:	4c 89 fe             	mov    %r15,%rsi
 105f35e:	e8 9d 53 fc ff       	call   1024700 <myl_core_trap>
 105f363:	48 89 c7             	mov    %rax,%rdi
 105f366:	48 c1 ff 3f          	sar    $0x3f,%rdi
 105f36a:	48 21 d7             	and    %rdx,%rdi
 105f36d:	48 01 c7             	add    %rax,%rdi
 105f370:	48 39 d7             	cmp    %rdx,%rdi
 105f373:	0f 82 17 f7 ff ff    	jb     105ea90 <my.interpreter::execute+0xcc0>
 105f379:	48 8d 3d 30 33 02 00 	lea    0x23330(%rip),%rdi        # 10826b0 <core_durable_error.verbs+0x2fa0>
 105f380:	48 89 c6             	mov    %rax,%rsi
 105f383:	e8 78 53 fc ff       	call   1024700 <myl_core_trap>
 105f388:	48 89 f0             	mov    %rsi,%rax
 105f38b:	48 c1 f8 3f          	sar    $0x3f,%rax
 105f38f:	48 21 d0             	and    %rdx,%rax
 105f392:	48 01 f0             	add    %rsi,%rax
 105f395:	48 39 d0             	cmp    %rdx,%rax
 105f398:	0f 82 19 f7 ff ff    	jb     105eab7 <my.interpreter::execute+0xce7>
 105f39e:	48 8d 3d 6b 33 02 00 	lea    0x2336b(%rip),%rdi        # 1082710 <core_durable_error.verbs+0x3000>
 105f3a5:	e8 56 53 fc ff       	call   1024700 <myl_core_trap>
 105f3aa:	48 89 f0             	mov    %rsi,%rax
 105f3ad:	48 c1 f8 3f          	sar    $0x3f,%rax
 105f3b1:	48 21 d0             	and    %rdx,%rax
 105f3b4:	48 01 f0             	add    %rsi,%rax
 105f3b7:	48 39 d0             	cmp    %rdx,%rax
 105f3ba:	0f 82 0f f7 ff ff    	jb     105eacf <my.interpreter::execute+0xcff>
 105f3c0:	48 8d 3d f9 13 02 00 	lea    0x213f9(%rip),%rdi        # 10807c0 <core_durable_error.verbs+0x10b0>
 105f3c7:	e8 34 53 fc ff       	call   1024700 <myl_core_trap>
 105f3cc:	48 8d 3d fd 18 02 00 	lea    0x218fd(%rip),%rdi        # 1080cd0 <core_durable_error.verbs+0x15c0>
 105f3d3:	ba 01 00 00 00       	mov    $0x1,%edx
 105f3d8:	48 89 c6             	mov    %rax,%rsi
 105f3db:	e8 20 53 fc ff       	call   1024700 <myl_core_trap>
 105f3e0:	48 8d 3d 29 60 02 00 	lea    0x26029(%rip),%rdi        # 1085410 <core_durable_error.verbs+0x5d00>
 105f3e7:	e8 94 a6 fc ff       	call   1029a80 <myl_core_assert_fail>
 105f3ec:	83 f8 01             	cmp    $0x1,%eax
 105f3ef:	0f 84 b8 00 00 00    	je     105f4ad <my.interpreter::execute+0x16dd>
 105f3f5:	85 c0                	test   %eax,%eax
 105f3f7:	0f 85 bc 00 00 00    	jne    105f4b9 <my.interpreter::execute+0x16e9>
 105f3fd:	48 8d 3d 1c 5f 02 00 	lea    0x25f1c(%rip),%rdi        # 1085320 <core_durable_error.verbs+0x5c10>
 105f404:	e8 77 a6 fc ff       	call   1029a80 <myl_core_assert_fail>
 105f409:	48 8d 3d f0 5d 02 00 	lea    0x25df0(%rip),%rdi        # 1085200 <core_durable_error.verbs+0x5af0>
 105f410:	31 f6                	xor    %esi,%esi
 105f412:	31 d2                	xor    %edx,%edx
 105f414:	e8 e7 52 fc ff       	call   1024700 <myl_core_trap>
 105f419:	48 8d 3d 40 16 02 00 	lea    0x21640(%rip),%rdi        # 1080a60 <core_durable_error.verbs+0x1350>
 105f420:	ba 01 00 00 00       	mov    $0x1,%edx
 105f425:	e8 d6 52 fc ff       	call   1024700 <myl_core_trap>
 105f42a:	48 8d 3d ff 18 02 00 	lea    0x218ff(%rip),%rdi        # 1080d30 <core_durable_error.verbs+0x1620>
 105f431:	ba 01 00 00 00       	mov    $0x1,%edx
 105f436:	48 89 c6             	mov    %rax,%rsi
 105f439:	e8 c2 52 fc ff       	call   1024700 <myl_core_trap>
 105f43e:	48 8d 3d cb 17 02 00 	lea    0x217cb(%rip),%rdi        # 1080c10 <core_durable_error.verbs+0x1500>
 105f445:	ba 01 00 00 00       	mov    $0x1,%edx
 105f44a:	48 89 c6             	mov    %rax,%rsi
 105f44d:	e8 ae 52 fc ff       	call   1024700 <myl_core_trap>
 105f452:	48 8d 3d f7 16 02 00 	lea    0x216f7(%rip),%rdi        # 1080b50 <core_durable_error.verbs+0x1440>
 105f459:	ba 01 00 00 00       	mov    $0x1,%edx
 105f45e:	e8 9d 52 fc ff       	call   1024700 <myl_core_trap>
 105f463:	48 8d 3d 26 16 02 00 	lea    0x21626(%rip),%rdi        # 1080a90 <core_durable_error.verbs+0x1380>
 105f46a:	ba 01 00 00 00       	mov    $0x1,%edx
 105f46f:	48 89 c6             	mov    %rax,%rsi
 105f472:	e8 89 52 fc ff       	call   1024700 <myl_core_trap>
 105f477:	48 8d 3d 72 16 02 00 	lea    0x21672(%rip),%rdi        # 1080af0 <core_durable_error.verbs+0x13e0>
 105f47e:	ba 01 00 00 00       	mov    $0x1,%edx
 105f483:	48 89 c6             	mov    %rax,%rsi
 105f486:	e8 75 52 fc ff       	call   1024700 <myl_core_trap>
 105f48b:	48 8d 3d fe 18 02 00 	lea    0x218fe(%rip),%rdi        # 1080d90 <core_durable_error.verbs+0x1680>
 105f492:	ba 01 00 00 00       	mov    $0x1,%edx
 105f497:	e8 64 52 fc ff       	call   1024700 <myl_core_trap>
 105f49c:	48 8d 3d 1d 31 02 00 	lea    0x2311d(%rip),%rdi        # 10825c0 <core_durable_error.verbs+0x2eb0>
 105f4a3:	ba 01 00 00 00       	mov    $0x1,%edx
 105f4a8:	e8 53 52 fc ff       	call   1024700 <myl_core_trap>
 105f4ad:	48 8d 3d 9c 5e 02 00 	lea    0x25e9c(%rip),%rdi        # 1085350 <core_durable_error.verbs+0x5c40>
 105f4b4:	e8 c7 a5 fc ff       	call   1029a80 <myl_core_assert_fail>
 105f4b9:	48 8d 3d c0 5e 02 00 	lea    0x25ec0(%rip),%rdi        # 1085380 <core_durable_error.verbs+0x5c70>
 105f4c0:	e8 bb a5 fc ff       	call   1029a80 <myl_core_assert_fail>
 105f4c5:	48 8d 3d 24 31 02 00 	lea    0x23124(%rip),%rdi        # 10825f0 <core_durable_error.verbs+0x2ee0>
 105f4cc:	ba 01 00 00 00       	mov    $0x1,%edx
 105f4d1:	48 89 c6             	mov    %rax,%rsi
 105f4d4:	e8 27 52 fc ff       	call   1024700 <myl_core_trap>
 105f4d9:	48 8d 3d f0 14 02 00 	lea    0x214f0(%rip),%rdi        # 10809d0 <core_durable_error.verbs+0x12c0>
 105f4e0:	ba 01 00 00 00       	mov    $0x1,%edx
 105f4e5:	48 89 c6             	mov    %rax,%rsi
 105f4e8:	e8 13 52 fc ff       	call   1024700 <myl_core_trap>
 105f4ed:	48 8d 3d 0c 5d 02 00 	lea    0x25d0c(%rip),%rdi        # 1085200 <core_durable_error.verbs+0x5af0>
 105f4f4:	31 f6                	xor    %esi,%esi
 105f4f6:	31 d2                	xor    %edx,%edx
 105f4f8:	e8 03 52 fc ff       	call   1024700 <myl_core_trap>
 105f4fd:	48 8d 3d 4c 31 02 00 	lea    0x2314c(%rip),%rdi        # 1082650 <core_durable_error.verbs+0x2f40>
 105f504:	ba 01 00 00 00       	mov    $0x1,%edx
 105f509:	e8 f2 51 fc ff       	call   1024700 <myl_core_trap>
 105f50e:	48 8d 3d 8b 17 02 00 	lea    0x2178b(%rip),%rdi        # 1080ca0 <core_durable_error.verbs+0x1590>
 105f515:	ba 01 00 00 00       	mov    $0x1,%edx
 105f51a:	e8 e1 51 fc ff       	call   1024700 <myl_core_trap>
 105f51f:	48 8d 3d ba 16 02 00 	lea    0x216ba(%rip),%rdi        # 1080be0 <core_durable_error.verbs+0x14d0>
 105f526:	ba 01 00 00 00       	mov    $0x1,%edx
 105f52b:	48 89 c6             	mov    %rax,%rsi
 105f52e:	e8 cd 51 fc ff       	call   1024700 <myl_core_trap>
 105f533:	48 8d 3d 86 5d 02 00 	lea    0x25d86(%rip),%rdi        # 10852c0 <core_durable_error.verbs+0x5bb0>
 105f53a:	ba 01 00 00 00       	mov    $0x1,%edx
 105f53f:	48 89 c6             	mov    %rax,%rsi
 105f542:	e8 b9 51 fc ff       	call   1024700 <myl_core_trap>
 105f547:	48 8d 3d 92 31 02 00 	lea    0x23192(%rip),%rdi        # 10826e0 <core_durable_error.verbs+0x2fd0>
 105f54e:	e8 2d a5 fc ff       	call   1029a80 <myl_core_assert_fail>

Disassembly of section .plt:
