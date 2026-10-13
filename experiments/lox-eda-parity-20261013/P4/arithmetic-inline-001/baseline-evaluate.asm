
.tmp/lox-eda-parity/P4/arithmetic-inline-001/baseline/lox:     file format elf64-x86-64


Disassembly of section .text:

0000000001064fd0 <my.interpreter::evaluate>:
 1064fd0:	55                   	push   %rbp
 1064fd1:	41 57                	push   %r15
 1064fd3:	41 56                	push   %r14
 1064fd5:	41 55                	push   %r13
 1064fd7:	41 54                	push   %r12
 1064fd9:	53                   	push   %rbx
 1064fda:	48 81 ec b8 04 00 00 	sub    $0x4b8,%rsp
 1064fe1:	48 89 d3             	mov    %rdx,%rbx
 1064fe4:	48 89 f5             	mov    %rsi,%rbp
 1064fe7:	49 89 fe             	mov    %rdi,%r14
 1064fea:	48 8b b4 24 10 05 00 	mov    0x510(%rsp),%rsi
 1064ff1:	00 
 1064ff2:	48 8b 55 08          	mov    0x8(%rbp),%rdx
 1064ff6:	48 39 d6             	cmp    %rdx,%rsi
 1064ff9:	0f 83 88 1a 00 00    	jae    1066a87 <my.interpreter::evaluate+0x1ab7>
 1064fff:	48 89 f0             	mov    %rsi,%rax
 1065002:	44 0f b6 ac 24 00 05 	movzbl 0x500(%rsp),%r13d
 1065009:	00 00 
 106500b:	4c 8b bc 24 08 05 00 	mov    0x508(%rsp),%r15
 1065012:	00 
 1065013:	4c 8b 9c 24 f8 04 00 	mov    0x4f8(%rsp),%r11
 106501a:	00 
 106501b:	48 6b d0 70          	imul   $0x70,%rax,%rdx
 106501f:	48 8d 04 2a          	lea    (%rdx,%rbp,1),%rax
 1065023:	48 83 c0 20          	add    $0x20,%rax
 1065027:	8b 74 15 20          	mov    0x20(%rbp,%rdx,1),%esi
 106502b:	48 83 fe 0a          	cmp    $0xa,%rsi
 106502f:	0f 87 54 0b 00 00    	ja     1065b89 <my.interpreter::evaluate+0xbb9>
 1065035:	48 8b bc 24 18 05 00 	mov    0x518(%rsp),%rdi
 106503c:	00 
 106503d:	4c 8b a4 24 f0 04 00 	mov    0x4f0(%rsp),%r12
 1065044:	00 
 1065045:	48 8d 15 30 26 fa ff 	lea    -0x5d9d0(%rip),%rdx        # 100767c <core_number_pairs+0x41c>
 106504c:	48 63 34 b2          	movslq (%rdx,%rsi,4),%rsi
 1065050:	48 01 d6             	add    %rdx,%rsi
 1065053:	4c 89 44 24 10       	mov    %r8,0x10(%rsp)
 1065058:	ff e6                	jmp    *%rsi
 106505a:	48 8b 50 20          	mov    0x20(%rax),%rdx
 106505e:	48 89 54 24 48       	mov    %rdx,0x48(%rsp)
 1065063:	48 8b 50 30          	mov    0x30(%rax),%rdx
 1065067:	48 89 54 24 30       	mov    %rdx,0x30(%rsp)
 106506c:	48 89 da             	mov    %rbx,%rdx
 106506f:	48 8b 58 40          	mov    0x40(%rax),%rbx
 1065073:	48 8b 70 48          	mov    0x48(%rax),%rsi
 1065077:	48 89 74 24 28       	mov    %rsi,0x28(%rsp)
 106507c:	45 0f b6 d5          	movzbl %r13b,%r10d
 1065080:	48 8d 7c 24 58       	lea    0x58(%rsp),%rdi
 1065085:	48 89 ee             	mov    %rbp,%rsi
 1065088:	4d 89 cd             	mov    %r9,%r13
 106508b:	ff b4 24 18 05 00 00 	push   0x518(%rsp)
 1065092:	ff 70 38             	push   0x38(%rax)
 1065095:	41 57                	push   %r15
 1065097:	41 52                	push   %r10
 1065099:	41 53                	push   %r11
 106509b:	41 54                	push   %r12
 106509d:	e8 2e ff ff ff       	call   1064fd0 <my.interpreter::evaluate>
 10650a2:	48 83 c4 30          	add    $0x30,%rsp
 10650a6:	c5 f8 10 84 24 58 01 	vmovups 0x158(%rsp),%xmm0
 10650ad:	00 00 
 10650af:	4c 8b a4 24 68 01 00 	mov    0x168(%rsp),%r12
 10650b6:	00 
 10650b7:	80 7c 24 58 01       	cmpb   $0x1,0x58(%rsp)
 10650bc:	c5 f8 29 44 24 10    	vmovaps %xmm0,0x10(%rsp)
 10650c2:	0f 84 62 15 00 00    	je     106662a <my.interpreter::evaluate+0x165a>
 10650c8:	48 83 fb ff          	cmp    $0xffffffffffffffff,%rbx
 10650cc:	0f 84 bb 10 00 00    	je     106618d <my.interpreter::evaluate+0x11bd>
 10650d2:	49 8b b5 a8 00 00 00 	mov    0xa8(%r13),%rsi
 10650d9:	48 85 db             	test   %rbx,%rbx
 10650dc:	0f 8e 3f 0e 00 00    	jle    1065f21 <my.interpreter::evaluate+0xf51>
 10650e2:	49 8b 45 00          	mov    0x0(%r13),%rax
 10650e6:	48 8b 50 08          	mov    0x8(%rax),%rdx
 10650ea:	48 83 c0 20          	add    $0x20,%rax
 10650ee:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10650f5:	0f 1f 84 00 00 00 00 
 10650fc:	00 
 10650fd:	0f 1f 00             	nopl   (%rax)
 1065100:	48 39 d6             	cmp    %rdx,%rsi
 1065103:	73 22                	jae    1065127 <my.interpreter::evaluate+0x157>
 1065105:	48 89 f1             	mov    %rsi,%rcx
 1065108:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 106510c:	83 3c 08 09          	cmpl   $0x9,(%rax,%rcx,1)
 1065110:	0f 85 c4 1d 00 00    	jne    1066eda <my.interpreter::evaluate+0x1f0a>
 1065116:	48 01 c1             	add    %rax,%rcx
 1065119:	48 8b 71 08          	mov    0x8(%rcx),%rsi
 106511d:	48 ff cb             	dec    %rbx
 1065120:	75 de                	jne    1065100 <my.interpreter::evaluate+0x130>
 1065122:	e9 fa 0d 00 00       	jmp    1065f21 <my.interpreter::evaluate+0xf51>
 1065127:	48 89 f1             	mov    %rsi,%rcx
 106512a:	48 c1 f9 3f          	sar    $0x3f,%rcx
 106512e:	48 21 d1             	and    %rdx,%rcx
 1065131:	48 01 f1             	add    %rsi,%rcx
 1065134:	48 39 d1             	cmp    %rdx,%rcx
 1065137:	72 cf                	jb     1065108 <my.interpreter::evaluate+0x138>
 1065139:	48 8d 3d a0 02 02 00 	lea    0x202a0(%rip),%rdi        # 10853e0 <core_durable_error.verbs+0x5cd0>
 1065140:	e8 bb f5 fb ff       	call   1024700 <myl_core_trap>
 1065145:	45 0f b6 d5          	movzbl %r13b,%r10d
 1065149:	4d 89 dd             	mov    %r11,%r13
 106514c:	49 89 fb             	mov    %rdi,%r11
 106514f:	48 8d bc 24 a0 03 00 	lea    0x3a0(%rsp),%rdi
 1065156:	00 
 1065157:	48 89 ee             	mov    %rbp,%rsi
 106515a:	48 89 da             	mov    %rbx,%rdx
 106515d:	41 53                	push   %r11
 106515f:	ff 70 08             	push   0x8(%rax)
 1065162:	41 57                	push   %r15
 1065164:	41 52                	push   %r10
 1065166:	41 55                	push   %r13
 1065168:	41 54                	push   %r12
 106516a:	e8 61 fe ff ff       	call   1064fd0 <my.interpreter::evaluate>
 106516f:	48 83 c4 30          	add    $0x30,%rsp
 1065173:	0f b6 84 24 a0 03 00 	movzbl 0x3a0(%rsp),%eax
 106517a:	00 
 106517b:	c5 f9 10 84 24 a8 03 	vmovupd 0x3a8(%rsp),%xmm0
 1065182:	00 00 
 1065184:	48 8b 8c 24 a0 04 00 	mov    0x4a0(%rsp),%rcx
 106518b:	00 
 106518c:	0f b6 94 24 a8 04 00 	movzbl 0x4a8(%rsp),%edx
 1065193:	00 
 1065194:	48 8b b4 24 b0 04 00 	mov    0x4b0(%rsp),%rsi
 106519b:	00 
 106519c:	48 83 f8 01          	cmp    $0x1,%rax
 10651a0:	0f 84 19 14 00 00    	je     10665bf <my.interpreter::evaluate+0x15ef>
 10651a6:	49 89 06             	mov    %rax,(%r14)
 10651a9:	c4 c1 79 11 46 08    	vmovupd %xmm0,0x8(%r14)
 10651af:	49 89 8e 00 01 00 00 	mov    %rcx,0x100(%r14)
 10651b6:	49 89 96 08 01 00 00 	mov    %rdx,0x108(%r14)
 10651bd:	49 89 b6 10 01 00 00 	mov    %rsi,0x110(%r14)
 10651c4:	e9 56 18 00 00       	jmp    1066a1f <my.interpreter::evaluate+0x1a4f>
 10651c9:	48 8b 78 30          	mov    0x30(%rax),%rdi
 10651cd:	49 8b 09             	mov    (%r9),%rcx
 10651d0:	49 8b b1 a8 00 00 00 	mov    0xa8(%r9),%rsi
 10651d7:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 10651db:	48 85 ff             	test   %rdi,%rdi
 10651de:	0f 8e 25 0a 00 00    	jle    1065c09 <my.interpreter::evaluate+0xc39>
 10651e4:	4c 8d 41 20          	lea    0x20(%rcx),%r8
 10651e8:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10651ef:	0f 1f 84 00 00 00 00 
 10651f6:	00 
 10651f7:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 10651fe:	00 00 
 1065200:	48 39 d6             	cmp    %rdx,%rsi
 1065203:	73 23                	jae    1065228 <my.interpreter::evaluate+0x258>
 1065205:	49 89 f2             	mov    %rsi,%r10
 1065208:	49 6b f2 38          	imul   $0x38,%r10,%rsi
 106520c:	41 83 3c 30 09       	cmpl   $0x9,(%r8,%rsi,1)
 1065211:	0f 85 93 1c 00 00    	jne    1066eaa <my.interpreter::evaluate+0x1eda>
 1065217:	4c 01 c6             	add    %r8,%rsi
 106521a:	48 8b 76 08          	mov    0x8(%rsi),%rsi
 106521e:	48 ff cf             	dec    %rdi
 1065221:	75 dd                	jne    1065200 <my.interpreter::evaluate+0x230>
 1065223:	e9 e1 09 00 00       	jmp    1065c09 <my.interpreter::evaluate+0xc39>
 1065228:	49 89 f2             	mov    %rsi,%r10
 106522b:	49 c1 fa 3f          	sar    $0x3f,%r10
 106522f:	49 21 d2             	and    %rdx,%r10
 1065232:	49 01 f2             	add    %rsi,%r10
 1065235:	49 39 d2             	cmp    %rdx,%r10
 1065238:	72 ce                	jb     1065208 <my.interpreter::evaluate+0x238>
 106523a:	48 8d 3d 9f 01 02 00 	lea    0x2019f(%rip),%rdi        # 10853e0 <core_durable_error.verbs+0x5cd0>
 1065241:	e8 ba f4 fb ff       	call   1024700 <myl_core_trap>
 1065246:	4c 89 74 24 08       	mov    %r14,0x8(%rsp)
 106524b:	48 8b 50 28          	mov    0x28(%rax),%rdx
 106524f:	48 89 54 24 28       	mov    %rdx,0x28(%rsp)
 1065254:	4c 8b 70 38          	mov    0x38(%rax),%r14
 1065258:	45 0f b6 d5          	movzbl %r13b,%r10d
 106525c:	49 89 fb             	mov    %rdi,%r11
 106525f:	48 8d 7c 24 58       	lea    0x58(%rsp),%rdi
 1065264:	48 89 ee             	mov    %rbp,%rsi
 1065267:	48 89 5c 24 30       	mov    %rbx,0x30(%rsp)
 106526c:	48 89 da             	mov    %rbx,%rdx
 106526f:	48 89 cb             	mov    %rcx,%rbx
 1065272:	4d 89 cd             	mov    %r9,%r13
 1065275:	41 53                	push   %r11
 1065277:	ff 70 08             	push   0x8(%rax)
 106527a:	41 57                	push   %r15
 106527c:	41 52                	push   %r10
 106527e:	ff b4 24 18 05 00 00 	push   0x518(%rsp)
 1065285:	41 54                	push   %r12
 1065287:	e8 44 fd ff ff       	call   1064fd0 <my.interpreter::evaluate>
 106528c:	48 83 c4 30          	add    $0x30,%rsp
 1065290:	48 8b 84 24 58 01 00 	mov    0x158(%rsp),%rax
 1065297:	00 
 1065298:	0f b6 8c 24 60 01 00 	movzbl 0x160(%rsp),%ecx
 106529f:	00 
 10652a0:	4c 8b 94 24 68 01 00 	mov    0x168(%rsp),%r10
 10652a7:	00 
 10652a8:	80 7c 24 58 01       	cmpb   $0x1,0x58(%rsp)
 10652ad:	0f 84 29 13 00 00    	je     10665dc <my.interpreter::evaluate+0x160c>
 10652b3:	4d 8b 7e 08          	mov    0x8(%r14),%r15
 10652b7:	4d 85 ff             	test   %r15,%r15
 10652ba:	0f 84 2f 0e 00 00    	je     10660ef <my.interpreter::evaluate+0x111f>
 10652c0:	45 31 e4             	xor    %r12d,%r12d
 10652c3:	4c 8b 44 24 10       	mov    0x10(%rsp),%r8
 10652c8:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10652cf:	0f 1f 84 00 00 00 00 
 10652d6:	00 
 10652d7:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10652de:	0f 1f 84 00 00 00 00 
 10652e5:	00 
 10652e6:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10652ed:	0f 1f 84 00 00 00 00 
 10652f4:	00 
 10652f5:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 10652fc:	00 00 00 00 
 1065300:	44 0f b6 d9          	movzbl %cl,%r11d
 1065304:	48 8d bc 24 70 01 00 	lea    0x170(%rsp),%rdi
 106530b:	00 
 106530c:	48 89 ee             	mov    %rbp,%rsi
 106530f:	48 8b 54 24 30       	mov    0x30(%rsp),%rdx
 1065314:	48 89 d9             	mov    %rbx,%rcx
 1065317:	4d 89 e9             	mov    %r13,%r9
 106531a:	ff b4 24 18 05 00 00 	push   0x518(%rsp)
 1065321:	43 ff 74 e6 20       	push   0x20(%r14,%r12,8)
 1065326:	41 52                	push   %r10
 1065328:	41 53                	push   %r11
 106532a:	50                   	push   %rax
 106532b:	ff b4 24 18 05 00 00 	push   0x518(%rsp)
 1065332:	e8 99 fc ff ff       	call   1064fd0 <my.interpreter::evaluate>
 1065337:	48 83 c4 30          	add    $0x30,%rsp
 106533b:	48 8b 84 24 70 02 00 	mov    0x270(%rsp),%rax
 1065342:	00 
 1065343:	0f b6 8c 24 78 02 00 	movzbl 0x278(%rsp),%ecx
 106534a:	00 
 106534b:	4c 8b 94 24 80 02 00 	mov    0x280(%rsp),%r10
 1065352:	00 
 1065353:	80 bc 24 70 01 00 00 	cmpb   $0x1,0x170(%rsp)
 106535a:	01 
 106535b:	0f 84 9a 14 00 00    	je     10667fb <my.interpreter::evaluate+0x182b>
 1065361:	49 ff c4             	inc    %r12
 1065364:	4d 39 e7             	cmp    %r12,%r15
 1065367:	4c 8b 44 24 10       	mov    0x10(%rsp),%r8
 106536c:	75 92                	jne    1065300 <my.interpreter::evaluate+0x330>
 106536e:	4d 8b 5e 08          	mov    0x8(%r14),%r11
 1065372:	4c 8b a4 24 f0 04 00 	mov    0x4f0(%rsp),%r12
 1065379:	00 
 106537a:	e9 78 0d 00 00       	jmp    10660f7 <my.interpreter::evaluate+0x1127>
 106537f:	48 8b 50 28          	mov    0x28(%rax),%rdx
 1065383:	48 89 54 24 48       	mov    %rdx,0x48(%rsp)
 1065388:	48 8b 50 38          	mov    0x38(%rax),%rdx
 106538c:	48 89 54 24 30       	mov    %rdx,0x30(%rsp)
 1065391:	45 0f b6 d5          	movzbl %r13b,%r10d
 1065395:	4d 89 dd             	mov    %r11,%r13
 1065398:	49 89 fb             	mov    %rdi,%r11
 106539b:	48 8d 7c 24 58       	lea    0x58(%rsp),%rdi
 10653a0:	48 89 ee             	mov    %rbp,%rsi
 10653a3:	48 89 da             	mov    %rbx,%rdx
 10653a6:	41 53                	push   %r11
 10653a8:	ff 70 08             	push   0x8(%rax)
 10653ab:	41 57                	push   %r15
 10653ad:	41 52                	push   %r10
 10653af:	41 55                	push   %r13
 10653b1:	41 54                	push   %r12
 10653b3:	4c 89 cb             	mov    %r9,%rbx
 10653b6:	e8 15 fc ff ff       	call   1064fd0 <my.interpreter::evaluate>
 10653bb:	48 83 c4 30          	add    $0x30,%rsp
 10653bf:	c5 f8 10 84 24 58 01 	vmovups 0x158(%rsp),%xmm0
 10653c6:	00 00 
 10653c8:	4c 8b a4 24 68 01 00 	mov    0x168(%rsp),%r12
 10653cf:	00 
 10653d0:	80 7c 24 58 01       	cmpb   $0x1,0x58(%rsp)
 10653d5:	c5 f8 29 44 24 10    	vmovaps %xmm0,0x10(%rsp)
 10653db:	0f 84 0c 12 00 00    	je     10665ed <my.interpreter::evaluate+0x161d>
 10653e1:	48 8b 83 80 00 00 00 	mov    0x80(%rbx),%rax
 10653e8:	48 89 c6             	mov    %rax,%rsi
 10653eb:	48 ff ce             	dec    %rsi
 10653ee:	0f 80 d0 1b 00 00    	jo     1066fc4 <my.interpreter::evaluate+0x1ff4>
 10653f4:	48 89 df             	mov    %rbx,%rdi
 10653f7:	48 8b 43 78          	mov    0x78(%rbx),%rax
 10653fb:	48 8b 50 08          	mov    0x8(%rax),%rdx
 10653ff:	48 39 d6             	cmp    %rdx,%rsi
 1065402:	4c 89 74 24 08       	mov    %r14,0x8(%rsp)
 1065407:	0f 83 8e 17 00 00    	jae    1066b9b <my.interpreter::evaluate+0x1bcb>
 106540d:	49 89 f5             	mov    %rsi,%r13
 1065410:	49 c1 e5 04          	shl    $0x4,%r13
 1065414:	4e 8b 74 28 20       	mov    0x20(%rax,%r13,1),%r14
 1065419:	41 0f b6 ce          	movzbl %r14b,%ecx
 106541d:	83 f9 03             	cmp    $0x3,%ecx
 1065420:	0f 85 26 0f 00 00    	jne    106634c <my.interpreter::evaluate+0x137c>
 1065426:	4e 8b 7c 28 28       	mov    0x28(%rax,%r13,1),%r15
 106542b:	48 8b 07             	mov    (%rdi),%rax
 106542e:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065432:	4c 89 f9             	mov    %r15,%rcx
 1065435:	49 39 d7             	cmp    %rdx,%r15
 1065438:	0f 83 0a 18 00 00    	jae    1066c48 <my.interpreter::evaluate+0x1c78>
 106543e:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 1065442:	83 7c 08 20 07       	cmpl   $0x7,0x20(%rax,%rcx,1)
 1065447:	0f 85 ff 0e 00 00    	jne    106634c <my.interpreter::evaluate+0x137c>
 106544d:	4c 89 64 24 28       	mov    %r12,0x28(%rsp)
 1065452:	48 8b 6c 24 30       	mov    0x30(%rsp),%rbp
 1065457:	48 89 ee             	mov    %rbp,%rsi
 106545a:	49 89 fc             	mov    %rdi,%r12
 106545d:	e8 7e 3e 00 00       	call   10692e0 <my.heap::string_hash>
 1065462:	89 c3                	mov    %eax,%ebx
 1065464:	4c 89 e7             	mov    %r12,%rdi
 1065467:	4c 89 fe             	mov    %r15,%rsi
 106546a:	48 89 ea             	mov    %rbp,%rdx
 106546d:	89 c1                	mov    %eax,%ecx
 106546f:	e8 4c 44 00 00       	call   10698c0 <my.heap::instance_field>
 1065474:	3c 01                	cmp    $0x1,%al
 1065476:	0f 85 16 0b 00 00    	jne    1065f92 <my.interpreter::evaluate+0xfc2>
 106547c:	31 c0                	xor    %eax,%eax
 106547e:	49 3b 84 24 80 00 00 	cmp    0x80(%r12),%rax
 1065485:	00 
 1065486:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 106548b:	0f 80 8f 1c 00 00    	jo     1067120 <my.interpreter::evaluate+0x2150>
 1065491:	49 8b 44 24 78       	mov    0x78(%r12),%rax
 1065496:	4a 8d 34 28          	lea    (%rax,%r13,1),%rsi
 106549a:	48 83 c6 20          	add    $0x20,%rsi
 106549e:	0f b6 d2             	movzbl %dl,%edx
 10654a1:	4a 89 54 28 20       	mov    %rdx,0x20(%rax,%r13,1)
 10654a6:	c5 f9 28 44 24 10    	vmovapd 0x10(%rsp),%xmm0
 10654ac:	e9 7c 0b 00 00       	jmp    106602d <my.interpreter::evaluate+0x105d>
 10654b1:	48 8b 50 28          	mov    0x28(%rax),%rdx
 10654b5:	48 89 54 24 50       	mov    %rdx,0x50(%rsp)
 10654ba:	48 8b 50 38          	mov    0x38(%rax),%rdx
 10654be:	48 89 54 24 28       	mov    %rdx,0x28(%rsp)
 10654c3:	48 8b 50 40          	mov    0x40(%rax),%rdx
 10654c7:	48 89 54 24 48       	mov    %rdx,0x48(%rsp)
 10654cc:	45 0f b6 d5          	movzbl %r13b,%r10d
 10654d0:	49 89 fb             	mov    %rdi,%r11
 10654d3:	48 8d 7c 24 58       	lea    0x58(%rsp),%rdi
 10654d8:	48 89 ee             	mov    %rbp,%rsi
 10654db:	49 89 dd             	mov    %rbx,%r13
 10654de:	48 89 da             	mov    %rbx,%rdx
 10654e1:	48 89 cb             	mov    %rcx,%rbx
 10654e4:	41 53                	push   %r11
 10654e6:	ff 70 08             	push   0x8(%rax)
 10654e9:	41 57                	push   %r15
 10654eb:	41 52                	push   %r10
 10654ed:	ff b4 24 18 05 00 00 	push   0x518(%rsp)
 10654f4:	41 54                	push   %r12
 10654f6:	4d 89 cf             	mov    %r9,%r15
 10654f9:	e8 d2 fa ff ff       	call   1064fd0 <my.interpreter::evaluate>
 10654fe:	48 83 c4 30          	add    $0x30,%rsp
 1065502:	4c 8b 9c 24 58 01 00 	mov    0x158(%rsp),%r11
 1065509:	00 
 106550a:	48 8b 84 24 60 01 00 	mov    0x160(%rsp),%rax
 1065511:	00 
 1065512:	44 0f b6 c0          	movzbl %al,%r8d
 1065516:	4c 8b 94 24 68 01 00 	mov    0x168(%rsp),%r10
 106551d:	00 
 106551e:	80 7c 24 58 01       	cmpb   $0x1,0x58(%rsp)
 1065523:	0f 84 e6 10 00 00    	je     106660f <my.interpreter::evaluate+0x163f>
 1065529:	49 8b 87 80 00 00 00 	mov    0x80(%r15),%rax
 1065530:	48 89 c6             	mov    %rax,%rsi
 1065533:	48 ff ce             	dec    %rsi
 1065536:	0f 80 9c 1a 00 00    	jo     1066fd8 <my.interpreter::evaluate+0x2008>
 106553c:	4d 89 f9             	mov    %r15,%r9
 106553f:	4d 89 d7             	mov    %r10,%r15
 1065542:	4c 89 44 24 30       	mov    %r8,0x30(%rsp)
 1065547:	49 8b 41 78          	mov    0x78(%r9),%rax
 106554b:	48 8b 50 08          	mov    0x8(%rax),%rdx
 106554f:	48 39 d6             	cmp    %rdx,%rsi
 1065552:	4c 8b 44 24 10       	mov    0x10(%rsp),%r8
 1065557:	48 89 d9             	mov    %rbx,%rcx
 106555a:	0f 83 5d 16 00 00    	jae    1066bbd <my.interpreter::evaluate+0x1bed>
 1065560:	48 89 f7             	mov    %rsi,%rdi
 1065563:	4d 89 ea             	mov    %r13,%r10
 1065566:	48 c1 e7 04          	shl    $0x4,%rdi
 106556a:	80 7c 38 20 03       	cmpb   $0x3,0x20(%rax,%rdi,1)
 106556f:	0f 85 08 0e 00 00    	jne    106637d <my.interpreter::evaluate+0x13ad>
 1065575:	48 8b 74 38 28       	mov    0x28(%rax,%rdi,1),%rsi
 106557a:	49 8b 01             	mov    (%r9),%rax
 106557d:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065581:	48 39 d6             	cmp    %rdx,%rsi
 1065584:	0f 83 e3 16 00 00    	jae    1066c6d <my.interpreter::evaluate+0x1c9d>
 106558a:	48 89 f7             	mov    %rsi,%rdi
 106558d:	48 6b d7 38          	imul   $0x38,%rdi,%rdx
 1065591:	83 7c 10 20 07       	cmpl   $0x7,0x20(%rax,%rdx,1)
 1065596:	0f 85 e1 0d 00 00    	jne    106637d <my.interpreter::evaluate+0x13ad>
 106559c:	48 8d bc 24 70 01 00 	lea    0x170(%rsp),%rdi
 10655a3:	00 
 10655a4:	48 89 ee             	mov    %rbp,%rsi
 10655a7:	4c 89 d2             	mov    %r10,%rdx
 10655aa:	ff b4 24 18 05 00 00 	push   0x518(%rsp)
 10655b1:	ff 74 24 50          	push   0x50(%rsp)
 10655b5:	41 57                	push   %r15
 10655b7:	ff 74 24 48          	push   0x48(%rsp)
 10655bb:	41 53                	push   %r11
 10655bd:	41 54                	push   %r12
 10655bf:	4c 89 cb             	mov    %r9,%rbx
 10655c2:	e8 09 fa ff ff       	call   1064fd0 <my.interpreter::evaluate>
 10655c7:	48 83 c4 30          	add    $0x30,%rsp
 10655cb:	48 8b ac 24 70 02 00 	mov    0x270(%rsp),%rbp
 10655d2:	00 
 10655d3:	44 0f b6 84 24 78 02 	movzbl 0x278(%rsp),%r8d
 10655da:	00 00 
 10655dc:	4c 8b 94 24 80 02 00 	mov    0x280(%rsp),%r10
 10655e3:	00 
 10655e4:	80 bc 24 70 01 00 00 	cmpb   $0x1,0x170(%rsp)
 10655eb:	01 
 10655ec:	0f 84 b4 11 00 00    	je     10667a6 <my.interpreter::evaluate+0x17d6>
 10655f2:	48 8b b3 80 00 00 00 	mov    0x80(%rbx),%rsi
 10655f9:	48 89 f0             	mov    %rsi,%rax
 10655fc:	48 ff c8             	dec    %rax
 10655ff:	0f 80 74 1a 00 00    	jo     1067079 <my.interpreter::evaluate+0x20a9>
 1065605:	48 89 c6             	mov    %rax,%rsi
 1065608:	48 ff ce             	dec    %rsi
 106560b:	0f 80 79 1a 00 00    	jo     106708a <my.interpreter::evaluate+0x20ba>
 1065611:	48 89 df             	mov    %rbx,%rdi
 1065614:	48 8b 43 78          	mov    0x78(%rbx),%rax
 1065618:	48 8b 50 08          	mov    0x8(%rax),%rdx
 106561c:	48 39 d6             	cmp    %rdx,%rsi
 106561f:	0f 83 03 17 00 00    	jae    1066d28 <my.interpreter::evaluate+0x1d58>
 1065625:	48 89 f1             	mov    %rsi,%rcx
 1065628:	4c 89 54 24 10       	mov    %r10,0x10(%rsp)
 106562d:	4c 89 44 24 30       	mov    %r8,0x30(%rsp)
 1065632:	48 c1 e1 04          	shl    $0x4,%rcx
 1065636:	0f b6 54 08 20       	movzbl 0x20(%rax,%rcx,1),%edx
 106563b:	83 fa 03             	cmp    $0x3,%edx
 106563e:	0f 85 e2 18 00 00    	jne    1066f26 <my.interpreter::evaluate+0x1f56>
 1065644:	48 8b 5c 08 28       	mov    0x28(%rax,%rcx,1),%rbx
 1065649:	48 8b 74 24 28       	mov    0x28(%rsp),%rsi
 106564e:	49 89 fd             	mov    %rdi,%r13
 1065651:	e8 8a 3c 00 00       	call   10692e0 <my.heap::string_hash>
 1065656:	49 8b 8d 80 00 00 00 	mov    0x80(%r13),%rcx
 106565d:	48 89 ce             	mov    %rcx,%rsi
 1065660:	48 ff ce             	dec    %rsi
 1065663:	0f 80 4d 1a 00 00    	jo     10670b6 <my.interpreter::evaluate+0x20e6>
 1065669:	4c 89 ef             	mov    %r13,%rdi
 106566c:	49 8b 4d 78          	mov    0x78(%r13),%rcx
 1065670:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 1065674:	48 39 d6             	cmp    %rdx,%rsi
 1065677:	0f 83 cd 16 00 00    	jae    1066d4a <my.interpreter::evaluate+0x1d7a>
 106567d:	49 89 f0             	mov    %rsi,%r8
 1065680:	49 c1 e0 04          	shl    $0x4,%r8
 1065684:	46 0f b6 7c 01 20    	movzbl 0x20(%rcx,%r8,1),%r15d
 106568a:	4e 8b 64 01 28       	mov    0x28(%rcx,%r8,1),%r12
 106568f:	48 89 de             	mov    %rbx,%rsi
 1065692:	48 8b 54 24 28       	mov    0x28(%rsp),%rdx
 1065697:	89 c1                	mov    %eax,%ecx
 1065699:	45 89 f8             	mov    %r15d,%r8d
 106569c:	4d 89 e1             	mov    %r12,%r9
 106569f:	e8 ec 43 00 00       	call   1069a90 <my.heap::set_instance_field>
 10656a4:	49 8b 85 80 00 00 00 	mov    0x80(%r13),%rax
 10656ab:	48 89 c6             	mov    %rax,%rsi
 10656ae:	48 ff ce             	dec    %rsi
 10656b1:	0f 80 13 1a 00 00    	jo     10670ca <my.interpreter::evaluate+0x20fa>
 10656b7:	4c 89 ef             	mov    %r13,%rdi
 10656ba:	49 89 b5 80 00 00 00 	mov    %rsi,0x80(%r13)
 10656c1:	49 8b 4d 78          	mov    0x78(%r13),%rcx
 10656c5:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 10656c9:	48 39 d6             	cmp    %rdx,%rsi
 10656cc:	4c 8b 44 24 30       	mov    0x30(%rsp),%r8
 10656d1:	4c 8b 54 24 10       	mov    0x10(%rsp),%r10
 10656d6:	0f 83 90 16 00 00    	jae    1066d6c <my.interpreter::evaluate+0x1d9c>
 10656dc:	48 89 f0             	mov    %rsi,%rax
 10656df:	48 ff c8             	dec    %rax
 10656e2:	0f 80 f6 19 00 00    	jo     10670de <my.interpreter::evaluate+0x210e>
 10656e8:	48 39 d0             	cmp    %rdx,%rax
 10656eb:	0f 83 9d 16 00 00    	jae    1066d8e <my.interpreter::evaluate+0x1dbe>
 10656f1:	48 89 c6             	mov    %rax,%rsi
 10656f4:	48 c1 e6 04          	shl    $0x4,%rsi
 10656f8:	4c 89 7c 31 20       	mov    %r15,0x20(%rcx,%rsi,1)
 10656fd:	4c 89 64 31 28       	mov    %r12,0x28(%rcx,%rsi,1)
 1065702:	48 89 4f 78          	mov    %rcx,0x78(%rdi)
 1065706:	31 c0                	xor    %eax,%eax
 1065708:	e9 cb 10 00 00       	jmp    10667d8 <my.interpreter::evaluate+0x1808>
 106570d:	4c 89 74 24 08       	mov    %r14,0x8(%rsp)
 1065712:	0f b6 50 10          	movzbl 0x10(%rax),%edx
 1065716:	48 89 54 24 28       	mov    %rdx,0x28(%rsp)
 106571b:	48 8b 50 28          	mov    0x28(%rax),%rdx
 106571f:	48 89 54 24 48       	mov    %rdx,0x48(%rsp)
 1065724:	48 8b 50 38          	mov    0x38(%rax),%rdx
 1065728:	48 89 54 24 10       	mov    %rdx,0x10(%rsp)
 106572d:	49 89 ce             	mov    %rcx,%r14
 1065730:	45 0f b6 d5          	movzbl %r13b,%r10d
 1065734:	49 89 fd             	mov    %rdi,%r13
 1065737:	48 8d 7c 24 58       	lea    0x58(%rsp),%rdi
 106573c:	48 89 ee             	mov    %rbp,%rsi
 106573f:	48 89 da             	mov    %rbx,%rdx
 1065742:	48 89 5c 24 30       	mov    %rbx,0x30(%rsp)
 1065747:	4c 89 c3             	mov    %r8,%rbx
 106574a:	41 55                	push   %r13
 106574c:	ff 70 08             	push   0x8(%rax)
 106574f:	41 57                	push   %r15
 1065751:	41 52                	push   %r10
 1065753:	41 53                	push   %r11
 1065755:	41 54                	push   %r12
 1065757:	4d 89 cd             	mov    %r9,%r13
 106575a:	e8 71 f8 ff ff       	call   1064fd0 <my.interpreter::evaluate>
 106575f:	48 83 c4 30          	add    $0x30,%rsp
 1065763:	4c 8b 94 24 58 01 00 	mov    0x158(%rsp),%r10
 106576a:	00 
 106576b:	0f b6 84 24 60 01 00 	movzbl 0x160(%rsp),%eax
 1065772:	00 
 1065773:	4c 8b bc 24 68 01 00 	mov    0x168(%rsp),%r15
 106577a:	00 
 106577b:	80 7c 24 58 01       	cmpb   $0x1,0x58(%rsp)
 1065780:	0f 84 bf 0e 00 00    	je     1066645 <my.interpreter::evaluate+0x1675>
 1065786:	48 8d bc 24 70 01 00 	lea    0x170(%rsp),%rdi
 106578d:	00 
 106578e:	48 89 ee             	mov    %rbp,%rsi
 1065791:	48 8b 54 24 30       	mov    0x30(%rsp),%rdx
 1065796:	4c 89 f1             	mov    %r14,%rcx
 1065799:	49 89 d8             	mov    %rbx,%r8
 106579c:	4d 89 e9             	mov    %r13,%r9
 106579f:	ff b4 24 18 05 00 00 	push   0x518(%rsp)
 10657a6:	ff 74 24 18          	push   0x18(%rsp)
 10657aa:	41 57                	push   %r15
 10657ac:	50                   	push   %rax
 10657ad:	41 52                	push   %r10
 10657af:	41 54                	push   %r12
 10657b1:	e8 1a f8 ff ff       	call   1064fd0 <my.interpreter::evaluate>
 10657b6:	48 83 c4 30          	add    $0x30,%rsp
 10657ba:	4c 8b 94 24 70 02 00 	mov    0x270(%rsp),%r10
 10657c1:	00 
 10657c2:	44 0f b6 9c 24 78 02 	movzbl 0x278(%rsp),%r11d
 10657c9:	00 00 
 10657cb:	4c 8b bc 24 80 02 00 	mov    0x280(%rsp),%r15
 10657d2:	00 
 10657d3:	80 bc 24 70 01 00 00 	cmpb   $0x1,0x170(%rsp)
 10657da:	01 
 10657db:	0f 84 75 0f 00 00    	je     1066756 <my.interpreter::evaluate+0x1786>
 10657e1:	4c 89 7c 24 10       	mov    %r15,0x10(%rsp)
 10657e6:	4d 8b 85 80 00 00 00 	mov    0x80(%r13),%r8
 10657ed:	4d 89 c7             	mov    %r8,%r15
 10657f0:	49 ff cf             	dec    %r15
 10657f3:	41 0f 90 c4          	seto   %r12b
 10657f7:	0f 80 40 18 00 00    	jo     106703d <my.interpreter::evaluate+0x206d>
 10657fd:	4c 89 fe             	mov    %r15,%rsi
 1065800:	48 ff ce             	dec    %rsi
 1065803:	0f 80 48 18 00 00    	jo     1067051 <my.interpreter::evaluate+0x2081>
 1065809:	4c 89 eb             	mov    %r13,%rbx
 106580c:	49 8b 4d 78          	mov    0x78(%r13),%rcx
 1065810:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 1065814:	48 39 d6             	cmp    %rdx,%rsi
 1065817:	0f 83 72 14 00 00    	jae    1066c8f <my.interpreter::evaluate+0x1cbf>
 106581d:	48 89 f7             	mov    %rsi,%rdi
 1065820:	48 c1 e7 04          	shl    $0x4,%rdi
 1065824:	0f b6 44 39 20       	movzbl 0x20(%rcx,%rdi,1),%eax
 1065829:	48 8b 6c 39 28       	mov    0x28(%rcx,%rdi,1),%rbp
 106582e:	4c 89 fe             	mov    %r15,%rsi
 1065831:	49 39 d7             	cmp    %rdx,%r15
 1065834:	0f 83 77 14 00 00    	jae    1066cb1 <my.interpreter::evaluate+0x1ce1>
 106583a:	48 83 c1 20          	add    $0x20,%rcx
 106583e:	48 c1 e6 04          	shl    $0x4,%rsi
 1065842:	44 0f b6 34 31       	movzbl (%rcx,%rsi,1),%r14d
 1065847:	4c 8b 6c 31 08       	mov    0x8(%rcx,%rsi,1),%r13
 106584c:	48 8b 74 24 28       	mov    0x28(%rsp),%rsi
 1065851:	48 83 fe 0c          	cmp    $0xc,%rsi
 1065855:	0f 84 20 0a 00 00    	je     106627b <my.interpreter::evaluate+0x12ab>
 106585b:	83 fe 0e             	cmp    $0xe,%esi
 106585e:	0f 85 3f 0a 00 00    	jne    10662a3 <my.interpreter::evaluate+0x12d3>
 1065864:	3c 02                	cmp    $0x2,%al
 1065866:	0f 84 9f 0b 00 00    	je     106640b <my.interpreter::evaluate+0x143b>
 106586c:	0f b6 c0             	movzbl %al,%eax
 106586f:	83 f8 01             	cmp    $0x1,%eax
 1065872:	0f 84 75 0b 00 00    	je     10663ed <my.interpreter::evaluate+0x141d>
 1065878:	85 c0                	test   %eax,%eax
 106587a:	0f 85 b0 0b 00 00    	jne    1066430 <my.interpreter::evaluate+0x1460>
 1065880:	45 84 f6             	test   %r14b,%r14b
 1065883:	41 0f 94 c5          	sete   %r13b
 1065887:	e9 b5 0b 00 00       	jmp    1066441 <my.interpreter::evaluate+0x1471>
 106588c:	c5 f9 10 40 08       	vmovupd 0x8(%rax),%xmm0
 1065891:	49 8b 41 78          	mov    0x78(%r9),%rax
 1065895:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 106589c:	48 8b 50 08          	mov    0x8(%rax),%rdx
 10658a0:	48 39 d6             	cmp    %rdx,%rsi
 10658a3:	0f 83 00 12 00 00    	jae    1066aa9 <my.interpreter::evaluate+0x1ad9>
 10658a9:	48 89 f1             	mov    %rsi,%rcx
 10658ac:	c5 f9 54 05 2c eb f9 	vandpd -0x614d4(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 10658b3:	ff 
 10658b4:	48 c1 e1 04          	shl    $0x4,%rcx
 10658b8:	c5 f9 11 44 08 20    	vmovupd %xmm0,0x20(%rax,%rcx,1)
 10658be:	49 89 41 78          	mov    %rax,0x78(%r9)
 10658c2:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 10658c9:	48 89 f0             	mov    %rsi,%rax
 10658cc:	48 ff c0             	inc    %rax
 10658cf:	0f 81 bc 03 00 00    	jno    1065c91 <my.interpreter::evaluate+0xcc1>
 10658d5:	48 8d 3d a4 d0 01 00 	lea    0x1d0a4(%rip),%rdi        # 1082980 <core_durable_error.verbs+0x3270>
 10658dc:	ba 01 00 00 00       	mov    $0x1,%edx
 10658e1:	e8 1a ee fb ff       	call   1024700 <myl_core_trap>
 10658e6:	4c 89 74 24 08       	mov    %r14,0x8(%rsp)
 10658eb:	44 0f b6 70 10       	movzbl 0x10(%rax),%r14d
 10658f0:	48 8b 50 38          	mov    0x38(%rax),%rdx
 10658f4:	48 89 54 24 28       	mov    %rdx,0x28(%rsp)
 10658f9:	45 0f b6 d5          	movzbl %r13b,%r10d
 10658fd:	4d 89 dd             	mov    %r11,%r13
 1065900:	49 89 fb             	mov    %rdi,%r11
 1065903:	48 8d 7c 24 58       	lea    0x58(%rsp),%rdi
 1065908:	48 89 ee             	mov    %rbp,%rsi
 106590b:	48 89 5c 24 30       	mov    %rbx,0x30(%rsp)
 1065910:	48 89 da             	mov    %rbx,%rdx
 1065913:	48 89 cb             	mov    %rcx,%rbx
 1065916:	41 53                	push   %r11
 1065918:	ff 70 08             	push   0x8(%rax)
 106591b:	41 57                	push   %r15
 106591d:	41 52                	push   %r10
 106591f:	41 55                	push   %r13
 1065921:	4d 89 e5             	mov    %r12,%r13
 1065924:	41 54                	push   %r12
 1065926:	4d 89 cc             	mov    %r9,%r12
 1065929:	e8 a2 f6 ff ff       	call   1064fd0 <my.interpreter::evaluate>
 106592e:	48 83 c4 30          	add    $0x30,%rsp
 1065932:	48 8b bc 24 58 01 00 	mov    0x158(%rsp),%rdi
 1065939:	00 
 106593a:	48 8b 84 24 60 01 00 	mov    0x160(%rsp),%rax
 1065941:	00 
 1065942:	44 0f b6 f8          	movzbl %al,%r15d
 1065946:	4c 8b 94 24 68 01 00 	mov    0x168(%rsp),%r10
 106594d:	00 
 106594e:	80 7c 24 58 01       	cmpb   $0x1,0x58(%rsp)
 1065953:	0f 84 07 0d 00 00    	je     1066660 <my.interpreter::evaluate+0x1690>
 1065959:	49 8b 84 24 80 00 00 	mov    0x80(%r12),%rax
 1065960:	00 
 1065961:	48 89 c6             	mov    %rax,%rsi
 1065964:	48 ff ce             	dec    %rsi
 1065967:	0f 80 7f 16 00 00    	jo     1066fec <my.interpreter::evaluate+0x201c>
 106596d:	4d 89 e1             	mov    %r12,%r9
 1065970:	49 8b 44 24 78       	mov    0x78(%r12),%rax
 1065975:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065979:	48 89 f1             	mov    %rsi,%rcx
 106597c:	48 39 d6             	cmp    %rdx,%rsi
 106597f:	4d 89 eb             	mov    %r13,%r11
 1065982:	4c 8b 44 24 10       	mov    0x10(%rsp),%r8
 1065987:	0f 83 55 12 00 00    	jae    1066be2 <my.interpreter::evaluate+0x1c12>
 106598d:	48 c1 e1 04          	shl    $0x4,%rcx
 1065991:	0f b6 54 08 20       	movzbl 0x20(%rax,%rcx,1),%edx
 1065996:	83 fa 01             	cmp    $0x1,%edx
 1065999:	0f 84 8c 08 00 00    	je     106622b <my.interpreter::evaluate+0x125b>
 106599f:	85 d2                	test   %edx,%edx
 10659a1:	0f 85 c8 08 00 00    	jne    106626f <my.interpreter::evaluate+0x129f>
 10659a7:	41 83 fe 1e          	cmp    $0x1e,%r14d
 10659ab:	0f 85 94 08 00 00    	jne    1066245 <my.interpreter::evaluate+0x1275>
 10659b1:	49 89 b1 80 00 00 00 	mov    %rsi,0x80(%r9)
 10659b8:	48 89 f8             	mov    %rdi,%rax
 10659bb:	48 8d bc 24 70 01 00 	lea    0x170(%rsp),%rdi
 10659c2:	00 
 10659c3:	48 89 ee             	mov    %rbp,%rsi
 10659c6:	48 8b 54 24 30       	mov    0x30(%rsp),%rdx
 10659cb:	48 89 d9             	mov    %rbx,%rcx
 10659ce:	ff b4 24 18 05 00 00 	push   0x518(%rsp)
 10659d5:	ff 74 24 30          	push   0x30(%rsp)
 10659d9:	41 52                	push   %r10
 10659db:	41 57                	push   %r15
 10659dd:	50                   	push   %rax
 10659de:	41 53                	push   %r11
 10659e0:	e8 eb f5 ff ff       	call   1064fd0 <my.interpreter::evaluate>
 10659e5:	48 83 c4 30          	add    $0x30,%rsp
 10659e9:	0f b6 84 24 70 01 00 	movzbl 0x170(%rsp),%eax
 10659f0:	00 
 10659f1:	c5 f9 10 84 24 78 01 	vmovupd 0x178(%rsp),%xmm0
 10659f8:	00 00 
 10659fa:	48 8b bc 24 70 02 00 	mov    0x270(%rsp),%rdi
 1065a01:	00 
 1065a02:	44 0f b6 bc 24 78 02 	movzbl 0x278(%rsp),%r15d
 1065a09:	00 00 
 1065a0b:	4c 8b 94 24 80 02 00 	mov    0x280(%rsp),%r10
 1065a12:	00 
 1065a13:	48 83 f8 01          	cmp    $0x1,%rax
 1065a17:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 1065a1c:	0f 85 2a 08 00 00    	jne    106624c <my.interpreter::evaluate+0x127c>
 1065a22:	c5 f9 29 44 24 10    	vmovapd %xmm0,0x10(%rsp)
 1065a28:	48 89 f9             	mov    %rdi,%rcx
 1065a2b:	48 8d 3d ae ff 01 00 	lea    0x1ffae(%rip),%rdi        # 10859e0 <core_durable_error.verbs+0x62d0>
 1065a32:	e9 44 0c 00 00       	jmp    106667b <my.interpreter::evaluate+0x16ab>
 1065a37:	48 89 da             	mov    %rbx,%rdx
 1065a3a:	4c 89 f3             	mov    %r14,%rbx
 1065a3d:	44 0f b6 70 08       	movzbl 0x8(%rax),%r14d
 1065a42:	48 8b 70 20          	mov    0x20(%rax),%rsi
 1065a46:	48 89 74 24 10       	mov    %rsi,0x10(%rsp)
 1065a4b:	45 0f b6 d5          	movzbl %r13b,%r10d
 1065a4f:	4d 89 dd             	mov    %r11,%r13
 1065a52:	49 89 fb             	mov    %rdi,%r11
 1065a55:	48 8d 7c 24 58       	lea    0x58(%rsp),%rdi
 1065a5a:	48 89 ee             	mov    %rbp,%rsi
 1065a5d:	41 53                	push   %r11
 1065a5f:	ff 70 30             	push   0x30(%rax)
 1065a62:	41 57                	push   %r15
 1065a64:	41 52                	push   %r10
 1065a66:	41 55                	push   %r13
 1065a68:	41 54                	push   %r12
 1065a6a:	4d 89 cd             	mov    %r9,%r13
 1065a6d:	e8 5e f5 ff ff       	call   1064fd0 <my.interpreter::evaluate>
 1065a72:	48 83 c4 30          	add    $0x30,%rsp
 1065a76:	c5 f9 10 84 24 58 01 	vmovupd 0x158(%rsp),%xmm0
 1065a7d:	00 00 
 1065a7f:	4c 8b bc 24 68 01 00 	mov    0x168(%rsp),%r15
 1065a86:	00 
 1065a87:	80 7c 24 58 01       	cmpb   $0x1,0x58(%rsp)
 1065a8c:	0f 84 0d 0c 00 00    	je     106669f <my.interpreter::evaluate+0x16cf>
 1065a92:	49 8b 85 80 00 00 00 	mov    0x80(%r13),%rax
 1065a99:	48 89 c6             	mov    %rax,%rsi
 1065a9c:	48 ff ce             	dec    %rsi
 1065a9f:	0f 80 5b 15 00 00    	jo     1067000 <my.interpreter::evaluate+0x2030>
 1065aa5:	4d 89 e8             	mov    %r13,%r8
 1065aa8:	49 8b 45 78          	mov    0x78(%r13),%rax
 1065aac:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065ab0:	48 39 d6             	cmp    %rdx,%rsi
 1065ab3:	0f 83 4b 11 00 00    	jae    1066c04 <my.interpreter::evaluate+0x1c34>
 1065ab9:	48 89 f7             	mov    %rsi,%rdi
 1065abc:	48 c1 e7 04          	shl    $0x4,%rdi
 1065ac0:	48 8d 0c 38          	lea    (%rax,%rdi,1),%rcx
 1065ac4:	48 83 c1 20          	add    $0x20,%rcx
 1065ac8:	0f b6 74 38 20       	movzbl 0x20(%rax,%rdi,1),%esi
 1065acd:	48 8b 54 38 28       	mov    0x28(%rax,%rdi,1),%rdx
 1065ad2:	41 83 fe 0b          	cmp    $0xb,%r14d
 1065ad6:	0f 85 8c 04 00 00    	jne    1065f68 <my.interpreter::evaluate+0xf98>
 1065adc:	40 84 f6             	test   %sil,%sil
 1065adf:	49 89 de             	mov    %rbx,%r14
 1065ae2:	0f 84 01 08 00 00    	je     10662e9 <my.interpreter::evaluate+0x1319>
 1065ae8:	40 0f b6 f6          	movzbl %sil,%esi
 1065aec:	83 fe 01             	cmp    $0x1,%esi
 1065aef:	0f 85 f8 07 00 00    	jne    10662ed <my.interpreter::evaluate+0x131d>
 1065af5:	f6 d2                	not    %dl
 1065af7:	80 e2 01             	and    $0x1,%dl
 1065afa:	e9 f0 07 00 00       	jmp    10662ef <my.interpreter::evaluate+0x131f>
 1065aff:	48 8b 58 48          	mov    0x48(%rax),%rbx
 1065b03:	4c 8b 78 58          	mov    0x58(%rax),%r15
 1065b07:	48 8b 40 60          	mov    0x60(%rax),%rax
 1065b0b:	49 8b 39             	mov    (%r9),%rdi
 1065b0e:	49 8b b1 a8 00 00 00 	mov    0xa8(%r9),%rsi
 1065b15:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 1065b19:	48 89 f1             	mov    %rsi,%rcx
 1065b1c:	48 85 c0             	test   %rax,%rax
 1065b1f:	0f 8e 91 01 00 00    	jle    1065cb6 <my.interpreter::evaluate+0xce6>
 1065b25:	4c 8d 47 20          	lea    0x20(%rdi),%r8
 1065b29:	49 89 c3             	mov    %rax,%r11
 1065b2c:	48 89 f1             	mov    %rsi,%rcx
 1065b2f:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1065b36:	0f 1f 84 00 00 00 00 
 1065b3d:	00 
 1065b3e:	66 90                	xchg   %ax,%ax
 1065b40:	48 39 d1             	cmp    %rdx,%rcx
 1065b43:	73 23                	jae    1065b68 <my.interpreter::evaluate+0xb98>
 1065b45:	49 89 ca             	mov    %rcx,%r10
 1065b48:	49 6b ca 38          	imul   $0x38,%r10,%rcx
 1065b4c:	41 83 3c 08 09       	cmpl   $0x9,(%r8,%rcx,1)
 1065b51:	0f 85 5f 13 00 00    	jne    1066eb6 <my.interpreter::evaluate+0x1ee6>
 1065b57:	4c 01 c1             	add    %r8,%rcx
 1065b5a:	48 8b 49 08          	mov    0x8(%rcx),%rcx
 1065b5e:	49 ff cb             	dec    %r11
 1065b61:	75 dd                	jne    1065b40 <my.interpreter::evaluate+0xb70>
 1065b63:	e9 4e 01 00 00       	jmp    1065cb6 <my.interpreter::evaluate+0xce6>
 1065b68:	49 89 ca             	mov    %rcx,%r10
 1065b6b:	49 c1 fa 3f          	sar    $0x3f,%r10
 1065b6f:	49 21 d2             	and    %rdx,%r10
 1065b72:	49 01 ca             	add    %rcx,%r10
 1065b75:	49 39 d2             	cmp    %rdx,%r10
 1065b78:	72 ce                	jb     1065b48 <my.interpreter::evaluate+0xb78>
 1065b7a:	48 8d 3d 5f f8 01 00 	lea    0x1f85f(%rip),%rdi        # 10853e0 <core_durable_error.verbs+0x5cd0>
 1065b81:	48 89 ce             	mov    %rcx,%rsi
 1065b84:	e8 77 eb fb ff       	call   1024700 <myl_core_trap>
 1065b89:	48 8b 78 38          	mov    0x38(%rax),%rdi
 1065b8d:	48 83 ff ff          	cmp    $0xffffffffffffffff,%rdi
 1065b91:	0f 84 ab 04 00 00    	je     1066042 <my.interpreter::evaluate+0x1072>
 1065b97:	48 8b 70 40          	mov    0x40(%rax),%rsi
 1065b9b:	49 8b 09             	mov    (%r9),%rcx
 1065b9e:	49 8b 81 a8 00 00 00 	mov    0xa8(%r9),%rax
 1065ba5:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 1065ba9:	48 85 ff             	test   %rdi,%rdi
 1065bac:	0f 8e ea 02 00 00    	jle    1065e9c <my.interpreter::evaluate+0xecc>
 1065bb2:	4c 8d 41 20          	lea    0x20(%rcx),%r8
 1065bb6:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 1065bbd:	00 00 00 
 1065bc0:	48 39 d0             	cmp    %rdx,%rax
 1065bc3:	73 23                	jae    1065be8 <my.interpreter::evaluate+0xc18>
 1065bc5:	49 89 c2             	mov    %rax,%r10
 1065bc8:	49 6b c2 38          	imul   $0x38,%r10,%rax
 1065bcc:	41 83 3c 00 09       	cmpl   $0x9,(%r8,%rax,1)
 1065bd1:	0f 85 f7 12 00 00    	jne    1066ece <my.interpreter::evaluate+0x1efe>
 1065bd7:	4c 01 c0             	add    %r8,%rax
 1065bda:	48 8b 40 08          	mov    0x8(%rax),%rax
 1065bde:	48 ff cf             	dec    %rdi
 1065be1:	75 dd                	jne    1065bc0 <my.interpreter::evaluate+0xbf0>
 1065be3:	e9 b4 02 00 00       	jmp    1065e9c <my.interpreter::evaluate+0xecc>
 1065be8:	49 89 c2             	mov    %rax,%r10
 1065beb:	49 c1 fa 3f          	sar    $0x3f,%r10
 1065bef:	49 21 d2             	and    %rdx,%r10
 1065bf2:	49 01 c2             	add    %rax,%r10
 1065bf5:	49 39 d2             	cmp    %rdx,%r10
 1065bf8:	72 ce                	jb     1065bc8 <my.interpreter::evaluate+0xbf8>
 1065bfa:	48 8d 3d df f7 01 00 	lea    0x1f7df(%rip),%rdi        # 10853e0 <core_durable_error.verbs+0x5cd0>
 1065c01:	48 89 c6             	mov    %rax,%rsi
 1065c04:	e8 f7 ea fb ff       	call   1024700 <myl_core_trap>
 1065c09:	48 8b 40 38          	mov    0x38(%rax),%rax
 1065c0d:	48 39 d6             	cmp    %rdx,%rsi
 1065c10:	0f 83 b5 0e 00 00    	jae    1066acb <my.interpreter::evaluate+0x1afb>
 1065c16:	48 89 f7             	mov    %rsi,%rdi
 1065c19:	48 6b d7 38          	imul   $0x38,%rdi,%rdx
 1065c1d:	83 7c 11 20 09       	cmpl   $0x9,0x20(%rcx,%rdx,1)
 1065c22:	0f 85 3b 13 00 00    	jne    1066f63 <my.interpreter::evaluate+0x1f93>
 1065c28:	48 01 d1             	add    %rdx,%rcx
 1065c2b:	48 83 c1 20          	add    $0x20,%rcx
 1065c2f:	48 8b 49 10          	mov    0x10(%rcx),%rcx
 1065c33:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 1065c37:	48 39 d0             	cmp    %rdx,%rax
 1065c3a:	0f 83 d2 0e 00 00    	jae    1066b12 <my.interpreter::evaluate+0x1b42>
 1065c40:	48 89 c6             	mov    %rax,%rsi
 1065c43:	48 c1 e6 04          	shl    $0x4,%rsi
 1065c47:	c5 f9 10 44 31 20    	vmovupd 0x20(%rcx,%rsi,1),%xmm0
 1065c4d:	49 8b 41 78          	mov    0x78(%r9),%rax
 1065c51:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 1065c58:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065c5c:	48 39 d6             	cmp    %rdx,%rsi
 1065c5f:	0f 83 d2 0e 00 00    	jae    1066b37 <my.interpreter::evaluate+0x1b67>
 1065c65:	48 89 f1             	mov    %rsi,%rcx
 1065c68:	c5 f9 54 05 70 e7 f9 	vandpd -0x61890(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 1065c6f:	ff 
 1065c70:	48 c1 e1 04          	shl    $0x4,%rcx
 1065c74:	c5 f9 11 44 08 20    	vmovupd %xmm0,0x20(%rax,%rcx,1)
 1065c7a:	49 89 41 78          	mov    %rax,0x78(%r9)
 1065c7e:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 1065c85:	48 89 f0             	mov    %rsi,%rax
 1065c88:	48 ff c0             	inc    %rax
 1065c8b:	0f 80 ea 12 00 00    	jo     1066f7b <my.interpreter::evaluate+0x1fab>
 1065c91:	49 89 81 80 00 00 00 	mov    %rax,0x80(%r9)
 1065c98:	49 c7 06 00 00 00 00 	movq   $0x0,(%r14)
 1065c9f:	4d 89 9e 00 01 00 00 	mov    %r11,0x100(%r14)
 1065ca6:	41 0f b6 c5          	movzbl %r13b,%eax
 1065caa:	49 89 86 08 01 00 00 	mov    %rax,0x108(%r14)
 1065cb1:	e9 48 08 00 00       	jmp    10664fe <my.interpreter::evaluate+0x152e>
 1065cb6:	48 39 d1             	cmp    %rdx,%rcx
 1065cb9:	0f 83 2e 0e 00 00    	jae    1066aed <my.interpreter::evaluate+0x1b1d>
 1065cbf:	49 89 c8             	mov    %rcx,%r8
 1065cc2:	49 6b c8 38          	imul   $0x38,%r8,%rcx
 1065cc6:	83 7c 0f 20 09       	cmpl   $0x9,0x20(%rdi,%rcx,1)
 1065ccb:	0f 85 9e 12 00 00    	jne    1066f6f <my.interpreter::evaluate+0x1f9f>
 1065cd1:	48 01 f9             	add    %rdi,%rcx
 1065cd4:	48 83 c1 20          	add    $0x20,%rcx
 1065cd8:	4c 8b 41 10          	mov    0x10(%rcx),%r8
 1065cdc:	49 83 78 08 00       	cmpq   $0x0,0x8(%r8)
 1065ce1:	0f 84 72 0e 00 00    	je     1066b59 <my.interpreter::evaluate+0x1b89>
 1065ce7:	48 89 c1             	mov    %rax,%rcx
 1065cea:	48 ff c9             	dec    %rcx
 1065ced:	0f 80 99 12 00 00    	jo     1066f8c <my.interpreter::evaluate+0x1fbc>
 1065cf3:	48 83 c7 20          	add    $0x20,%rdi
 1065cf7:	41 0f b6 40 20       	movzbl 0x20(%r8),%eax
 1065cfc:	4d 8b 60 28          	mov    0x28(%r8),%r12
 1065d00:	48 85 c9             	test   %rcx,%rcx
 1065d03:	7e 7d                	jle    1065d82 <my.interpreter::evaluate+0xdb2>
 1065d05:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1065d0c:	0f 1f 84 00 00 00 00 
 1065d13:	00 
 1065d14:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1065d1b:	0f 1f 84 00 00 00 00 
 1065d22:	00 
 1065d23:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1065d2a:	0f 1f 84 00 00 00 00 
 1065d31:	00 
 1065d32:	66 66 66 66 66 2e 0f 	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1065d39:	1f 84 00 00 00 00 00 
 1065d40:	48 39 d6             	cmp    %rdx,%rsi
 1065d43:	73 1f                	jae    1065d64 <my.interpreter::evaluate+0xd94>
 1065d45:	49 89 f0             	mov    %rsi,%r8
 1065d48:	49 6b f0 38          	imul   $0x38,%r8,%rsi
 1065d4c:	83 3c 37 09          	cmpl   $0x9,(%rdi,%rsi,1)
 1065d50:	0f 85 6c 11 00 00    	jne    1066ec2 <my.interpreter::evaluate+0x1ef2>
 1065d56:	48 01 fe             	add    %rdi,%rsi
 1065d59:	48 8b 76 08          	mov    0x8(%rsi),%rsi
 1065d5d:	48 ff c9             	dec    %rcx
 1065d60:	75 de                	jne    1065d40 <my.interpreter::evaluate+0xd70>
 1065d62:	eb 1e                	jmp    1065d82 <my.interpreter::evaluate+0xdb2>
 1065d64:	49 89 f0             	mov    %rsi,%r8
 1065d67:	49 c1 f8 3f          	sar    $0x3f,%r8
 1065d6b:	49 21 d0             	and    %rdx,%r8
 1065d6e:	49 01 f0             	add    %rsi,%r8
 1065d71:	49 39 d0             	cmp    %rdx,%r8
 1065d74:	72 d2                	jb     1065d48 <my.interpreter::evaluate+0xd78>
 1065d76:	48 8d 3d 63 f6 01 00 	lea    0x1f663(%rip),%rdi        # 10853e0 <core_durable_error.verbs+0x5cd0>
 1065d7d:	e8 7e e9 fb ff       	call   1024700 <myl_core_trap>
 1065d82:	48 39 d6             	cmp    %rdx,%rsi
 1065d85:	0f 83 de 0d 00 00    	jae    1066b69 <my.interpreter::evaluate+0x1b99>
 1065d8b:	48 89 f1             	mov    %rsi,%rcx
 1065d8e:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 1065d92:	83 3c 0f 09          	cmpl   $0x9,(%rdi,%rcx,1)
 1065d96:	0f 85 04 12 00 00    	jne    1066fa0 <my.interpreter::evaluate+0x1fd0>
 1065d9c:	48 01 cf             	add    %rcx,%rdi
 1065d9f:	48 8b 4f 10          	mov    0x10(%rdi),%rcx
 1065da3:	48 83 79 08 00       	cmpq   $0x0,0x8(%rcx)
 1065da8:	0f 84 dd 0d 00 00    	je     1066b8b <my.interpreter::evaluate+0x1bbb>
 1065dae:	48 89 5c 24 30       	mov    %rbx,0x30(%rsp)
 1065db3:	3c 03                	cmp    $0x3,%al
 1065db5:	0f 85 2b 11 00 00    	jne    1066ee6 <my.interpreter::evaluate+0x1f16>
 1065dbb:	0f b6 69 20          	movzbl 0x20(%rcx),%ebp
 1065dbf:	48 8b 41 28          	mov    0x28(%rcx),%rax
 1065dc3:	48 89 44 24 10       	mov    %rax,0x10(%rsp)
 1065dc8:	4c 89 cf             	mov    %r9,%rdi
 1065dcb:	4c 89 fe             	mov    %r15,%rsi
 1065dce:	4d 89 cd             	mov    %r9,%r13
 1065dd1:	e8 0a 35 00 00       	call   10692e0 <my.heap::string_hash>
 1065dd6:	4c 89 eb             	mov    %r13,%rbx
 1065dd9:	4c 89 ef             	mov    %r13,%rdi
 1065ddc:	4c 89 e6             	mov    %r12,%rsi
 1065ddf:	4c 89 fa             	mov    %r15,%rdx
 1065de2:	89 c1                	mov    %eax,%ecx
 1065de4:	e8 b7 3d 00 00       	call   1069ba0 <my.heap::class_method>
 1065de9:	3c 01                	cmp    $0x1,%al
 1065deb:	0f 85 d2 08 00 00    	jne    10666c3 <my.interpreter::evaluate+0x16f3>
 1065df1:	80 fa 03             	cmp    $0x3,%dl
 1065df4:	44 0f b6 a4 24 00 05 	movzbl 0x500(%rsp),%r12d
 1065dfb:	00 00 
 1065dfd:	0f 85 03 11 00 00    	jne    1066f06 <my.interpreter::evaluate+0x1f36>
 1065e03:	49 89 c8             	mov    %rcx,%r8
 1065e06:	40 0f b6 d5          	movzbl %bpl,%edx
 1065e0a:	48 8d 7c 24 58       	lea    0x58(%rsp),%rdi
 1065e0f:	48 89 de             	mov    %rbx,%rsi
 1065e12:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
 1065e17:	e8 74 a3 00 00       	call   1070190 <my.interpreter::bind>
 1065e1c:	48 8b 44 24 58       	mov    0x58(%rsp),%rax
 1065e21:	48 8b 4b 78          	mov    0x78(%rbx),%rcx
 1065e25:	48 8b b3 80 00 00 00 	mov    0x80(%rbx),%rsi
 1065e2c:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 1065e30:	48 89 f7             	mov    %rsi,%rdi
 1065e33:	48 39 d6             	cmp    %rdx,%rsi
 1065e36:	0f 83 ea 0d 00 00    	jae    1066c26 <my.interpreter::evaluate+0x1c56>
 1065e3c:	48 c1 e7 04          	shl    $0x4,%rdi
 1065e40:	48 c7 44 39 20 03 00 	movq   $0x3,0x20(%rcx,%rdi,1)
 1065e47:	00 00 
 1065e49:	48 89 44 39 28       	mov    %rax,0x28(%rcx,%rdi,1)
 1065e4e:	48 89 f0             	mov    %rsi,%rax
 1065e51:	48 ff c0             	inc    %rax
 1065e54:	48 8b 8c 24 f8 04 00 	mov    0x4f8(%rsp),%rcx
 1065e5b:	00 
 1065e5c:	0f 80 ca 11 00 00    	jo     106702c <my.interpreter::evaluate+0x205c>
 1065e62:	48 89 83 80 00 00 00 	mov    %rax,0x80(%rbx)
 1065e69:	31 c0                	xor    %eax,%eax
 1065e6b:	49 89 06             	mov    %rax,(%r14)
 1065e6e:	49 89 5e 08          	mov    %rbx,0x8(%r14)
 1065e72:	49 89 56 10          	mov    %rdx,0x10(%r14)
 1065e76:	49 89 8e 00 01 00 00 	mov    %rcx,0x100(%r14)
 1065e7d:	41 0f b6 c4          	movzbl %r12b,%eax
 1065e81:	49 89 86 08 01 00 00 	mov    %rax,0x108(%r14)
 1065e88:	48 8b 84 24 08 05 00 	mov    0x508(%rsp),%rax
 1065e8f:	00 
 1065e90:	49 89 86 10 01 00 00 	mov    %rax,0x110(%r14)
 1065e97:	e9 83 0b 00 00       	jmp    1066a1f <my.interpreter::evaluate+0x1a4f>
 1065e9c:	48 39 d0             	cmp    %rdx,%rax
 1065e9f:	0f 83 0e 0f 00 00    	jae    1066db3 <my.interpreter::evaluate+0x1de3>
 1065ea5:	48 89 c7             	mov    %rax,%rdi
 1065ea8:	48 6b c7 38          	imul   $0x38,%rdi,%rax
 1065eac:	83 7c 01 20 09       	cmpl   $0x9,0x20(%rcx,%rax,1)
 1065eb1:	0f 85 38 12 00 00    	jne    10670ef <my.interpreter::evaluate+0x211f>
 1065eb7:	48 01 c8             	add    %rcx,%rax
 1065eba:	48 83 c0 20          	add    $0x20,%rax
 1065ebe:	48 8b 40 10          	mov    0x10(%rax),%rax
 1065ec2:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065ec6:	48 39 d6             	cmp    %rdx,%rsi
 1065ec9:	0f 83 09 0f 00 00    	jae    1066dd8 <my.interpreter::evaluate+0x1e08>
 1065ecf:	48 89 f1             	mov    %rsi,%rcx
 1065ed2:	48 c1 e1 04          	shl    $0x4,%rcx
 1065ed6:	c5 f9 10 44 08 20    	vmovupd 0x20(%rax,%rcx,1),%xmm0
 1065edc:	49 8b 41 78          	mov    0x78(%r9),%rax
 1065ee0:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 1065ee7:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065eeb:	48 89 f1             	mov    %rsi,%rcx
 1065eee:	48 39 d6             	cmp    %rdx,%rsi
 1065ef1:	0f 83 03 0f 00 00    	jae    1066dfa <my.interpreter::evaluate+0x1e2a>
 1065ef7:	48 c1 e1 04          	shl    $0x4,%rcx
 1065efb:	c5 f9 54 05 dd e4 f9 	vandpd -0x61b23(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 1065f02:	ff 
 1065f03:	c5 f9 11 44 08 20    	vmovupd %xmm0,0x20(%rax,%rcx,1)
 1065f09:	48 89 f0             	mov    %rsi,%rax
 1065f0c:	48 ff c0             	inc    %rax
 1065f0f:	0f 80 e6 11 00 00    	jo     10670fb <my.interpreter::evaluate+0x212b>
 1065f15:	49 89 81 80 00 00 00 	mov    %rax,0x80(%r9)
 1065f1c:	e9 a6 01 00 00       	jmp    10660c7 <my.interpreter::evaluate+0x10f7>
 1065f21:	49 8b 8d 80 00 00 00 	mov    0x80(%r13),%rcx
 1065f28:	48 89 c8             	mov    %rcx,%rax
 1065f2b:	48 ff c8             	dec    %rax
 1065f2e:	0f 80 d8 11 00 00    	jo     106710c <my.interpreter::evaluate+0x213c>
 1065f34:	49 8b 4d 78          	mov    0x78(%r13),%rcx
 1065f38:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 1065f3c:	48 39 d0             	cmp    %rdx,%rax
 1065f3f:	0f 83 d7 0e 00 00    	jae    1066e1c <my.interpreter::evaluate+0x1e4c>
 1065f45:	49 89 c1             	mov    %rax,%r9
 1065f48:	49 c1 e1 04          	shl    $0x4,%r9
 1065f4c:	4e 8b 44 09 28       	mov    0x28(%rcx,%r9,1),%r8
 1065f51:	42 8b 4c 09 20       	mov    0x20(%rcx,%r9,1),%ecx
 1065f56:	4c 89 ef             	mov    %r13,%rdi
 1065f59:	48 8b 54 24 28       	mov    0x28(%rsp),%rdx
 1065f5e:	e8 dd 5d 00 00       	call   106bd40 <my.heap::set_env_slot>
 1065f63:	e9 bc 02 00 00       	jmp    1066224 <my.interpreter::evaluate+0x1254>
 1065f68:	40 80 fe 02          	cmp    $0x2,%sil
 1065f6c:	49 89 de             	mov    %rbx,%r14
 1065f6f:	0f 85 45 04 00 00    	jne    10663ba <my.interpreter::evaluate+0x13ea>
 1065f75:	48 be 00 00 00 00 00 	movabs $0x8000000000000000,%rsi
 1065f7c:	00 00 80 
 1065f7f:	48 31 f2             	xor    %rsi,%rdx
 1065f82:	48 c7 01 02 00 00 00 	movq   $0x2,(%rcx)
 1065f89:	48 89 51 08          	mov    %rdx,0x8(%rcx)
 1065f8d:	e9 67 03 00 00       	jmp    10662f9 <my.interpreter::evaluate+0x1329>
 1065f92:	4c 89 e7             	mov    %r12,%rdi
 1065f95:	4c 89 fe             	mov    %r15,%rsi
 1065f98:	e8 13 3a 00 00       	call   10699b0 <my.heap::instance_class>
 1065f9d:	4d 89 e5             	mov    %r12,%r13
 1065fa0:	4c 89 e7             	mov    %r12,%rdi
 1065fa3:	48 89 c6             	mov    %rax,%rsi
 1065fa6:	48 89 ea             	mov    %rbp,%rdx
 1065fa9:	89 d9                	mov    %ebx,%ecx
 1065fab:	e8 f0 3b 00 00       	call   1069ba0 <my.heap::class_method>
 1065fb0:	3c 01                	cmp    $0x1,%al
 1065fb2:	0f 85 c2 08 00 00    	jne    106687a <my.interpreter::evaluate+0x18aa>
 1065fb8:	80 fa 03             	cmp    $0x3,%dl
 1065fbb:	0f 85 82 0f 00 00    	jne    1066f43 <my.interpreter::evaluate+0x1f73>
 1065fc1:	49 89 c8             	mov    %rcx,%r8
 1065fc4:	41 0f b6 d6          	movzbl %r14b,%edx
 1065fc8:	48 8d bc 24 70 01 00 	lea    0x170(%rsp),%rdi
 1065fcf:	00 
 1065fd0:	4c 89 ee             	mov    %r13,%rsi
 1065fd3:	4c 89 f9             	mov    %r15,%rcx
 1065fd6:	e8 b5 a1 00 00       	call   1070190 <my.interpreter::bind>
 1065fdb:	49 8b 85 80 00 00 00 	mov    0x80(%r13),%rax
 1065fe2:	48 89 c6             	mov    %rax,%rsi
 1065fe5:	48 ff ce             	dec    %rsi
 1065fe8:	0f 80 65 11 00 00    	jo     1067153 <my.interpreter::evaluate+0x2183>
 1065fee:	4d 89 ec             	mov    %r13,%r12
 1065ff1:	48 8b 8c 24 70 01 00 	mov    0x170(%rsp),%rcx
 1065ff8:	00 
 1065ff9:	49 8b 45 78          	mov    0x78(%r13),%rax
 1065ffd:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1066001:	48 39 d6             	cmp    %rdx,%rsi
 1066004:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 1066009:	c5 f9 28 44 24 10    	vmovapd 0x10(%rsp),%xmm0
 106600f:	0f 83 2c 0e 00 00    	jae    1066e41 <my.interpreter::evaluate+0x1e71>
 1066015:	48 89 f7             	mov    %rsi,%rdi
 1066018:	48 c1 e7 04          	shl    $0x4,%rdi
 106601c:	48 8d 34 38          	lea    (%rax,%rdi,1),%rsi
 1066020:	48 83 c6 20          	add    $0x20,%rsi
 1066024:	48 c7 44 38 20 03 00 	movq   $0x3,0x20(%rax,%rdi,1)
 106602b:	00 00 
 106602d:	48 89 4e 08          	mov    %rcx,0x8(%rsi)
 1066031:	49 89 44 24 78       	mov    %rax,0x78(%r12)
 1066036:	31 c0                	xor    %eax,%eax
 1066038:	4c 8b 64 24 28       	mov    0x28(%rsp),%r12
 106603d:	e9 ba 09 00 00       	jmp    10669fc <my.interpreter::evaluate+0x1a2c>
 1066042:	4c 8b 68 20          	mov    0x20(%rax),%r13
 1066046:	48 8b 58 30          	mov    0x30(%rax),%rbx
 106604a:	4d 8b 79 30          	mov    0x30(%r9),%r15
 106604e:	4d 8b 61 38          	mov    0x38(%r9),%r12
 1066052:	4c 89 cf             	mov    %r9,%rdi
 1066055:	48 89 de             	mov    %rbx,%rsi
 1066058:	4c 89 cd             	mov    %r9,%rbp
 106605b:	e8 80 32 00 00       	call   10692e0 <my.heap::string_hash>
 1066060:	4c 89 ff             	mov    %r15,%rdi
 1066063:	4c 89 e6             	mov    %r12,%rsi
 1066066:	48 89 da             	mov    %rbx,%rdx
 1066069:	89 c1                	mov    %eax,%ecx
 106606b:	e8 60 31 00 00       	call   10691d0 <my.table::get>
 1066070:	3c 01                	cmp    $0x1,%al
 1066072:	0f 85 72 08 00 00    	jne    10668ea <my.interpreter::evaluate+0x191a>
 1066078:	48 8b 7d 78          	mov    0x78(%rbp),%rdi
 106607c:	48 8b b5 80 00 00 00 	mov    0x80(%rbp),%rsi
 1066083:	48 8b 47 08          	mov    0x8(%rdi),%rax
 1066087:	49 89 f0             	mov    %rsi,%r8
 106608a:	48 39 c6             	cmp    %rax,%rsi
 106608d:	0f 83 d0 0d 00 00    	jae    1066e63 <my.interpreter::evaluate+0x1e93>
 1066093:	49 c1 e0 04          	shl    $0x4,%r8
 1066097:	0f b6 c2             	movzbl %dl,%eax
 106609a:	4a 89 44 07 20       	mov    %rax,0x20(%rdi,%r8,1)
 106609f:	4a 89 4c 07 28       	mov    %rcx,0x28(%rdi,%r8,1)
 10660a4:	48 89 f0             	mov    %rsi,%rax
 10660a7:	48 ff c0             	inc    %rax
 10660aa:	4c 8b 9c 24 f8 04 00 	mov    0x4f8(%rsp),%r11
 10660b1:	00 
 10660b2:	4c 8b bc 24 08 05 00 	mov    0x508(%rsp),%r15
 10660b9:	00 
 10660ba:	0f 80 a7 10 00 00    	jo     1067167 <my.interpreter::evaluate+0x2197>
 10660c0:	48 89 85 80 00 00 00 	mov    %rax,0x80(%rbp)
 10660c7:	31 c0                	xor    %eax,%eax
 10660c9:	49 89 06             	mov    %rax,(%r14)
 10660cc:	49 89 5e 08          	mov    %rbx,0x8(%r14)
 10660d0:	4d 89 6e 10          	mov    %r13,0x10(%r14)
 10660d4:	4d 89 9e 00 01 00 00 	mov    %r11,0x100(%r14)
 10660db:	0f b6 84 24 00 05 00 	movzbl 0x500(%rsp),%eax
 10660e2:	00 
 10660e3:	49 89 86 08 01 00 00 	mov    %rax,0x108(%r14)
 10660ea:	e9 0f 04 00 00       	jmp    10664fe <my.interpreter::evaluate+0x152e>
 10660ef:	45 31 db             	xor    %r11d,%r11d
 10660f2:	4c 8b 44 24 10       	mov    0x10(%rsp),%r8
 10660f7:	48 83 ec 08          	sub    $0x8,%rsp
 10660fb:	44 0f b6 f1          	movzbl %cl,%r14d
 10660ff:	48 8d bc 24 90 02 00 	lea    0x290(%rsp),%rdi
 1066106:	00 
 1066107:	48 89 ee             	mov    %rbp,%rsi
 106610a:	48 8b 54 24 38       	mov    0x38(%rsp),%rdx
 106610f:	48 89 d9             	mov    %rbx,%rcx
 1066112:	4d 89 e9             	mov    %r13,%r9
 1066115:	ff b4 24 20 05 00 00 	push   0x520(%rsp)
 106611c:	ff 74 24 38          	push   0x38(%rsp)
 1066120:	41 53                	push   %r11
 1066122:	41 52                	push   %r10
 1066124:	41 56                	push   %r14
 1066126:	50                   	push   %rax
 1066127:	41 54                	push   %r12
 1066129:	e8 02 93 00 00       	call   106f430 <my.interpreter::call_value>
 106612e:	48 83 c4 40          	add    $0x40,%rsp
 1066132:	0f b6 94 24 88 02 00 	movzbl 0x288(%rsp),%edx
 1066139:	00 
 106613a:	c5 f9 10 84 24 90 02 	vmovupd 0x290(%rsp),%xmm0
 1066141:	00 00 
 1066143:	48 8b 84 24 88 03 00 	mov    0x388(%rsp),%rax
 106614a:	00 
 106614b:	0f b6 8c 24 90 03 00 	movzbl 0x390(%rsp),%ecx
 1066152:	00 
 1066153:	4c 8b 94 24 98 03 00 	mov    0x398(%rsp),%r10
 106615a:	00 
 106615b:	48 83 fa 01          	cmp    $0x1,%rdx
 106615f:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 1066164:	0f 84 2d 06 00 00    	je     1066797 <my.interpreter::evaluate+0x17c7>
 106616a:	49 89 16             	mov    %rdx,(%r14)
 106616d:	c4 c1 79 11 46 08    	vmovupd %xmm0,0x8(%r14)
 1066173:	49 89 86 00 01 00 00 	mov    %rax,0x100(%r14)
 106617a:	49 89 8e 08 01 00 00 	mov    %rcx,0x108(%r14)
 1066181:	4d 89 96 10 01 00 00 	mov    %r10,0x110(%r14)
 1066188:	e9 92 08 00 00       	jmp    1066a1f <my.interpreter::evaluate+0x1a4f>
 106618d:	49 8b 5d 30          	mov    0x30(%r13),%rbx
 1066191:	4d 8b 7d 38          	mov    0x38(%r13),%r15
 1066195:	4c 89 ef             	mov    %r13,%rdi
 1066198:	48 8b 6c 24 30       	mov    0x30(%rsp),%rbp
 106619d:	48 89 ee             	mov    %rbp,%rsi
 10661a0:	e8 3b 31 00 00       	call   10692e0 <my.heap::string_hash>
 10661a5:	48 89 df             	mov    %rbx,%rdi
 10661a8:	4c 89 fe             	mov    %r15,%rsi
 10661ab:	48 89 ea             	mov    %rbp,%rdx
 10661ae:	89 c1                	mov    %eax,%ecx
 10661b0:	e8 1b 30 00 00       	call   10691d0 <my.table::get>
 10661b5:	3c 01                	cmp    $0x1,%al
 10661b7:	0f 85 ba 07 00 00    	jne    1066977 <my.interpreter::evaluate+0x19a7>
 10661bd:	49 8b 85 80 00 00 00 	mov    0x80(%r13),%rax
 10661c4:	48 89 c6             	mov    %rax,%rsi
 10661c7:	48 ff ce             	dec    %rsi
 10661ca:	0f 80 a8 0f 00 00    	jo     1067178 <my.interpreter::evaluate+0x21a8>
 10661d0:	4c 89 ef             	mov    %r13,%rdi
 10661d3:	49 8b 45 78          	mov    0x78(%r13),%rax
 10661d7:	48 8b 50 08          	mov    0x8(%rax),%rdx
 10661db:	48 39 d6             	cmp    %rdx,%rsi
 10661de:	0f 83 a4 0c 00 00    	jae    1066e88 <my.interpreter::evaluate+0x1eb8>
 10661e4:	48 89 f1             	mov    %rsi,%rcx
 10661e7:	48 c1 e1 04          	shl    $0x4,%rcx
 10661eb:	48 8b 5c 08 28       	mov    0x28(%rax,%rcx,1),%rbx
 10661f0:	8b 6c 08 20          	mov    0x20(%rax,%rcx,1),%ebp
 10661f4:	4c 8b 6c 24 30       	mov    0x30(%rsp),%r13
 10661f9:	4c 89 ee             	mov    %r13,%rsi
 10661fc:	49 89 ff             	mov    %rdi,%r15
 10661ff:	e8 dc 30 00 00       	call   10692e0 <my.heap::string_hash>
 1066204:	49 8b 7f 30          	mov    0x30(%r15),%rdi
 1066208:	49 8b 77 38          	mov    0x38(%r15),%rsi
 106620c:	4c 89 ea             	mov    %r13,%rdx
 106620f:	89 c1                	mov    %eax,%ecx
 1066211:	41 89 e8             	mov    %ebp,%r8d
 1066214:	49 89 d9             	mov    %rbx,%r9
 1066217:	e8 a4 31 00 00       	call   10693c0 <my.table::set>
 106621c:	49 89 57 30          	mov    %rdx,0x30(%r15)
 1066220:	49 89 4f 38          	mov    %rcx,0x38(%r15)
 1066224:	31 c0                	xor    %eax,%eax
 1066226:	e9 cb 07 00 00       	jmp    10669f6 <my.interpreter::evaluate+0x1a26>
 106622b:	48 01 c8             	add    %rcx,%rax
 106622e:	48 83 c0 20          	add    $0x20,%rax
 1066232:	41 83 fe 1e          	cmp    $0x1e,%r14d
 1066236:	0f 95 c1             	setne  %cl
 1066239:	32 48 08             	xor    0x8(%rax),%cl
 106623c:	f6 c1 01             	test   $0x1,%cl
 106623f:	0f 84 6c f7 ff ff    	je     10659b1 <my.interpreter::evaluate+0x9e1>
 1066245:	31 c0                	xor    %eax,%eax
 1066247:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 106624c:	49 89 06             	mov    %rax,(%r14)
 106624f:	c4 c1 79 11 46 08    	vmovupd %xmm0,0x8(%r14)
 1066255:	49 89 be 00 01 00 00 	mov    %rdi,0x100(%r14)
 106625c:	4d 89 be 08 01 00 00 	mov    %r15,0x108(%r14)
 1066263:	4d 89 96 10 01 00 00 	mov    %r10,0x110(%r14)
 106626a:	e9 b0 07 00 00       	jmp    1066a1f <my.interpreter::evaluate+0x1a4f>
 106626f:	41 83 fe 1e          	cmp    $0x1e,%r14d
 1066273:	0f 85 38 f7 ff ff    	jne    10659b1 <my.interpreter::evaluate+0x9e1>
 1066279:	eb ca                	jmp    1066245 <my.interpreter::evaluate+0x1275>
 106627b:	3c 02                	cmp    $0x2,%al
 106627d:	0f 84 c5 01 00 00    	je     1066448 <my.interpreter::evaluate+0x1478>
 1066283:	0f b6 c0             	movzbl %al,%eax
 1066286:	83 f8 01             	cmp    $0x1,%eax
 1066289:	0f 84 6d 01 00 00    	je     10663fc <my.interpreter::evaluate+0x142c>
 106628f:	85 c0                	test   %eax,%eax
 1066291:	0f 85 d6 01 00 00    	jne    106646d <my.interpreter::evaluate+0x149d>
 1066297:	45 84 f6             	test   %r14b,%r14b
 106629a:	41 0f 94 c5          	sete   %r13b
 106629e:	e9 db 01 00 00       	jmp    106647e <my.interpreter::evaluate+0x14ae>
 10662a3:	89 c1                	mov    %eax,%ecx
 10662a5:	80 f1 02             	xor    $0x2,%cl
 10662a8:	c4 e1 f9 6e c5       	vmovq  %rbp,%xmm0
 10662ad:	44 89 f2             	mov    %r14d,%edx
 10662b0:	80 f2 02             	xor    $0x2,%dl
 10662b3:	c4 c1 f9 6e cd       	vmovq  %r13,%xmm1
 10662b8:	08 ca                	or     %cl,%dl
 10662ba:	0f 94 c1             	sete   %cl
 10662bd:	83 fe 07             	cmp    $0x7,%esi
 10662c0:	75 5e                	jne    1066320 <my.interpreter::evaluate+0x1350>
 10662c2:	84 c9                	test   %cl,%cl
 10662c4:	0f 84 40 02 00 00    	je     106650a <my.interpreter::evaluate+0x153a>
 10662ca:	c5 fb 58 c1          	vaddsd %xmm1,%xmm0,%xmm0
 10662ce:	c4 e1 f9 7e c2       	vmovq  %xmm0,%rdx
 10662d3:	b0 02                	mov    $0x2,%al
 10662d5:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 10662da:	41 f6 c4 01          	test   $0x1,%r12b
 10662de:	0f 84 b5 01 00 00    	je     1066499 <my.interpreter::evaluate+0x14c9>
 10662e4:	e9 c2 02 00 00       	jmp    10665ab <my.interpreter::evaluate+0x15db>
 10662e9:	b2 01                	mov    $0x1,%dl
 10662eb:	eb 02                	jmp    10662ef <my.interpreter::evaluate+0x131f>
 10662ed:	31 d2                	xor    %edx,%edx
 10662ef:	48 c7 01 01 00 00 00 	movq   $0x1,(%rcx)
 10662f6:	88 51 08             	mov    %dl,0x8(%rcx)
 10662f9:	49 89 40 78          	mov    %rax,0x78(%r8)
 10662fd:	31 c9                	xor    %ecx,%ecx
 10662ff:	49 89 0e             	mov    %rcx,(%r14)
 1066302:	49 89 46 08          	mov    %rax,0x8(%r14)
 1066306:	49 89 56 10          	mov    %rdx,0x10(%r14)
 106630a:	c5 f9 54 05 0e e0 f9 	vandpd -0x61ff2(%rip),%xmm0,%xmm0        # 1004320 <__anon_2217+0x60>
 1066311:	ff 
 1066312:	c4 c1 79 11 86 00 01 	vmovupd %xmm0,0x100(%r14)
 1066319:	00 00 
 106631b:	e9 de 01 00 00       	jmp    10664fe <my.interpreter::evaluate+0x152e>
 1066320:	4c 89 5c 24 30       	mov    %r11,0x30(%rsp)
 1066325:	4d 89 d5             	mov    %r10,%r13
 1066328:	84 c9                	test   %cl,%cl
 106632a:	0f 84 04 07 00 00    	je     1066a34 <my.interpreter::evaluate+0x1a64>
 1066330:	40 0f b6 fe          	movzbl %sil,%edi
 1066334:	4d 89 c6             	mov    %r8,%r14
 1066337:	e8 94 90 00 00       	call   106f3d0 <my.interpreter::arithmetic>
 106633c:	4d 89 f0             	mov    %r14,%r8
 106633f:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 1066344:	4d 89 ea             	mov    %r13,%r10
 1066347:	e9 50 02 00 00       	jmp    106659c <my.interpreter::evaluate+0x15cc>
 106634c:	48 8d 3d ed bd fa ff 	lea    -0x54213(%rip),%rdi        # 1012140 <core_number_pairs+0xaee0>
 1066353:	e8 a8 de fb ff       	call   1024200 <myl_core_owned_octets_copy>
 1066358:	48 89 c3             	mov    %rax,%rbx
 106635b:	48 8d 3d fe f4 01 00 	lea    0x1f4fe(%rip),%rdi        # 1085860 <core_durable_error.verbs+0x6150>
 1066362:	e8 59 07 ff ff       	call   1056ac0 <myl_core_err_trace_origin_preserve_most>
 1066367:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 106636c:	48 8b 4c 24 48       	mov    0x48(%rsp),%rcx
 1066371:	48 8d 3d 88 c4 01 00 	lea    0x1c488(%rip),%rdi        # 1082800 <core_durable_error.verbs+0x30f0>
 1066378:	e9 6f 06 00 00       	jmp    10669ec <my.interpreter::evaluate+0x1a1c>
 106637d:	4c 89 dd             	mov    %r11,%rbp
 1066380:	48 8d 3d f9 bd fa ff 	lea    -0x54207(%rip),%rdi        # 1012180 <core_number_pairs+0xaf20>
 1066387:	e8 74 de fb ff       	call   1024200 <myl_core_owned_octets_copy>
 106638c:	48 8d 3d 0d f7 01 00 	lea    0x1f70d(%rip),%rdi        # 1085aa0 <core_durable_error.verbs+0x6390>
 1066393:	e8 28 07 ff ff       	call   1056ac0 <myl_core_err_trace_origin_preserve_most>
 1066398:	c5 fa 7e 44 24 50    	vmovq  0x50(%rsp),%xmm0
 106639e:	c4 e1 f9 6e c8       	vmovq  %rax,%xmm1
 10663a3:	c5 f1 6c c0          	vpunpcklqdq %xmm0,%xmm1,%xmm0
 10663a7:	c5 f9 7f 44 24 10    	vmovdqa %xmm0,0x10(%rsp)
 10663ad:	4c 8b 44 24 30       	mov    0x30(%rsp),%r8
 10663b2:	4d 89 fa             	mov    %r15,%r10
 10663b5:	e9 07 04 00 00       	jmp    10667c1 <my.interpreter::evaluate+0x17f1>
 10663ba:	40 0f b6 c6          	movzbl %sil,%eax
 10663be:	83 f8 01             	cmp    $0x1,%eax
 10663c1:	c5 f9 29 44 24 30    	vmovapd %xmm0,0x30(%rsp)
 10663c7:	48 8d 3d 92 be fa ff 	lea    -0x5416e(%rip),%rdi        # 1012260 <core_number_pairs+0xb000>
 10663ce:	0f 84 66 04 00 00    	je     106683a <my.interpreter::evaluate+0x186a>
 10663d4:	85 c0                	test   %eax,%eax
 10663d6:	0f 85 6c 04 00 00    	jne    1066848 <my.interpreter::evaluate+0x1878>
 10663dc:	e8 1f de fb ff       	call   1024200 <myl_core_owned_octets_copy>
 10663e1:	48 8d 3d 18 fa 01 00 	lea    0x1fa18(%rip),%rdi        # 1085e00 <core_durable_error.verbs+0x66f0>
 10663e8:	e9 67 04 00 00       	jmp    1066854 <my.interpreter::evaluate+0x1884>
 10663ed:	41 80 fe 01          	cmp    $0x1,%r14b
 10663f1:	75 38                	jne    106642b <my.interpreter::evaluate+0x145b>
 10663f3:	41 31 ed             	xor    %ebp,%r13d
 10663f6:	41 80 f5 01          	xor    $0x1,%r13b
 10663fa:	eb 45                	jmp    1066441 <my.interpreter::evaluate+0x1471>
 10663fc:	41 80 fe 01          	cmp    $0x1,%r14b
 1066400:	75 66                	jne    1066468 <my.interpreter::evaluate+0x1498>
 1066402:	41 31 ed             	xor    %ebp,%r13d
 1066405:	41 80 f5 01          	xor    $0x1,%r13b
 1066409:	eb 73                	jmp    106647e <my.interpreter::evaluate+0x14ae>
 106640b:	41 80 fe 02          	cmp    $0x2,%r14b
 106640f:	75 1a                	jne    106642b <my.interpreter::evaluate+0x145b>
 1066411:	c4 e1 f9 6e c5       	vmovq  %rbp,%xmm0
 1066416:	c4 c1 f9 6e cd       	vmovq  %r13,%xmm1
 106641b:	c5 fb c2 c1 00       	vcmpeqsd %xmm1,%xmm0,%xmm0
 1066420:	c4 c1 f9 7e c5       	vmovq  %xmm0,%r13
 1066425:	41 83 e5 01          	and    $0x1,%r13d
 1066429:	eb 16                	jmp    1066441 <my.interpreter::evaluate+0x1471>
 106642b:	45 31 ed             	xor    %r13d,%r13d
 106642e:	eb 11                	jmp    1066441 <my.interpreter::evaluate+0x1471>
 1066430:	41 80 fe 03          	cmp    $0x3,%r14b
 1066434:	0f 94 c0             	sete   %al
 1066437:	4c 39 ed             	cmp    %r13,%rbp
 106643a:	41 0f 94 c5          	sete   %r13b
 106643e:	41 20 c5             	and    %al,%r13b
 1066441:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 1066446:	eb 3e                	jmp    1066486 <my.interpreter::evaluate+0x14b6>
 1066448:	41 80 fe 02          	cmp    $0x2,%r14b
 106644c:	75 1a                	jne    1066468 <my.interpreter::evaluate+0x1498>
 106644e:	c4 e1 f9 6e c5       	vmovq  %rbp,%xmm0
 1066453:	c4 c1 f9 6e cd       	vmovq  %r13,%xmm1
 1066458:	c5 fb c2 c1 00       	vcmpeqsd %xmm1,%xmm0,%xmm0
 106645d:	c4 c1 f9 7e c5       	vmovq  %xmm0,%r13
 1066462:	41 83 e5 01          	and    $0x1,%r13d
 1066466:	eb 16                	jmp    106647e <my.interpreter::evaluate+0x14ae>
 1066468:	45 31 ed             	xor    %r13d,%r13d
 106646b:	eb 11                	jmp    106647e <my.interpreter::evaluate+0x14ae>
 106646d:	41 80 fe 03          	cmp    $0x3,%r14b
 1066471:	0f 94 c0             	sete   %al
 1066474:	4c 39 ed             	cmp    %r13,%rbp
 1066477:	41 0f 94 c5          	sete   %r13b
 106647b:	41 20 c5             	and    %al,%r13b
 106647e:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 1066483:	41 f6 d5             	not    %r13b
 1066486:	41 0f b6 d5          	movzbl %r13b,%edx
 106648a:	83 e2 01             	and    $0x1,%edx
 106648d:	b0 01                	mov    $0x1,%al
 106648f:	41 f6 c4 01          	test   $0x1,%r12b
 1066493:	0f 85 12 01 00 00    	jne    10665ab <my.interpreter::evaluate+0x15db>
 1066499:	4c 89 bb 80 00 00 00 	mov    %r15,0x80(%rbx)
 10664a0:	48 8b 7b 78          	mov    0x78(%rbx),%rdi
 10664a4:	48 8b 4f 08          	mov    0x8(%rdi),%rcx
 10664a8:	49 39 cf             	cmp    %rcx,%r15
 10664ab:	0f 83 25 08 00 00    	jae    1066cd6 <my.interpreter::evaluate+0x1d06>
 10664b1:	4c 89 fe             	mov    %r15,%rsi
 10664b4:	48 ff ce             	dec    %rsi
 10664b7:	0f 80 a8 0b 00 00    	jo     1067065 <my.interpreter::evaluate+0x2095>
 10664bd:	48 39 ce             	cmp    %rcx,%rsi
 10664c0:	0f 83 38 08 00 00    	jae    1066cfe <my.interpreter::evaluate+0x1d2e>
 10664c6:	49 89 f0             	mov    %rsi,%r8
 10664c9:	4c 8b 7c 24 10       	mov    0x10(%rsp),%r15
 10664ce:	49 c1 e0 04          	shl    $0x4,%r8
 10664d2:	0f b6 c0             	movzbl %al,%eax
 10664d5:	4a 89 44 07 20       	mov    %rax,0x20(%rdi,%r8,1)
 10664da:	4a 89 54 07 28       	mov    %rdx,0x28(%rdi,%r8,1)
 10664df:	48 89 7b 78          	mov    %rdi,0x78(%rbx)
 10664e3:	31 c9                	xor    %ecx,%ecx
 10664e5:	49 89 0e             	mov    %rcx,(%r14)
 10664e8:	49 89 46 08          	mov    %rax,0x8(%r14)
 10664ec:	49 89 56 10          	mov    %rdx,0x10(%r14)
 10664f0:	4d 89 96 00 01 00 00 	mov    %r10,0x100(%r14)
 10664f7:	4d 89 9e 08 01 00 00 	mov    %r11,0x108(%r14)
 10664fe:	4d 89 be 10 01 00 00 	mov    %r15,0x110(%r14)
 1066505:	e9 15 05 00 00       	jmp    1066a1f <my.interpreter::evaluate+0x1a4f>
 106650a:	4c 89 5c 24 30       	mov    %r11,0x30(%rsp)
 106650f:	4c 89 54 24 28       	mov    %r10,0x28(%rsp)
 1066514:	44 0f b6 e0          	movzbl %al,%r12d
 1066518:	48 89 df             	mov    %rbx,%rdi
 106651b:	44 89 e6             	mov    %r12d,%esi
 106651e:	48 89 ea             	mov    %rbp,%rdx
 1066521:	e8 5a 8e 00 00       	call   106f380 <my.interpreter::is_string>
 1066526:	a8 01                	test   $0x1,%al
 1066528:	0f 84 28 05 00 00    	je     1066a56 <my.interpreter::evaluate+0x1a86>
 106652e:	45 0f b6 fe          	movzbl %r14b,%r15d
 1066532:	48 89 df             	mov    %rbx,%rdi
 1066535:	44 89 fe             	mov    %r15d,%esi
 1066538:	4c 89 ea             	mov    %r13,%rdx
 106653b:	e8 40 8e 00 00       	call   106f380 <my.interpreter::is_string>
 1066540:	a8 01                	test   $0x1,%al
 1066542:	0f 84 0e 05 00 00    	je     1066a56 <my.interpreter::evaluate+0x1a86>
 1066548:	44 89 e7             	mov    %r12d,%edi
 106654b:	48 89 ee             	mov    %rbp,%rsi
 106654e:	e8 ad 57 00 00       	call   106bd00 <my.interpreter::as_obj>
 1066553:	49 89 c4             	mov    %rax,%r12
 1066556:	44 89 ff             	mov    %r15d,%edi
 1066559:	4c 89 ee             	mov    %r13,%rsi
 106655c:	e8 9f 57 00 00       	call   106bd00 <my.interpreter::as_obj>
 1066561:	48 8d bc 24 88 02 00 	lea    0x288(%rsp),%rdi
 1066568:	00 
 1066569:	48 89 de             	mov    %rbx,%rsi
 106656c:	4c 89 e2             	mov    %r12,%rdx
 106656f:	48 89 c1             	mov    %rax,%rcx
 1066572:	e8 c9 72 00 00       	call   106d840 <my.lox_strings::concat>
 1066577:	48 8b 94 24 88 02 00 	mov    0x288(%rsp),%rdx
 106657e:	00 
 106657f:	b0 03                	mov    $0x3,%al
 1066581:	4c 8b 83 80 00 00 00 	mov    0x80(%rbx),%r8
 1066588:	4d 89 c7             	mov    %r8,%r15
 106658b:	49 ff cf             	dec    %r15
 106658e:	41 0f 90 c4          	seto   %r12b
 1066592:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 1066597:	4c 8b 54 24 28       	mov    0x28(%rsp),%r10
 106659c:	4c 8b 5c 24 30       	mov    0x30(%rsp),%r11
 10665a1:	41 f6 c4 01          	test   $0x1,%r12b
 10665a5:	0f 84 ee fe ff ff    	je     1066499 <my.interpreter::evaluate+0x14c9>
 10665ab:	48 8d 3d fe f0 01 00 	lea    0x1f0fe(%rip),%rdi        # 10856b0 <core_durable_error.verbs+0x5fa0>
 10665b2:	ba 01 00 00 00       	mov    $0x1,%edx
 10665b7:	4c 89 c6             	mov    %r8,%rsi
 10665ba:	e8 41 e1 fb ff       	call   1024700 <myl_core_trap>
 10665bf:	48 8d 3d 6a c2 01 00 	lea    0x1c26a(%rip),%rdi        # 1082830 <core_durable_error.verbs+0x3120>
 10665c6:	c5 f9 29 44 24 10    	vmovapd %xmm0,0x10(%rsp)
 10665cc:	e8 2f 05 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 10665d1:	c5 f9 28 44 24 10    	vmovapd 0x10(%rsp),%xmm0
 10665d7:	e9 ca eb ff ff       	jmp    10651a6 <my.interpreter::evaluate+0x1d6>
 10665dc:	48 8d 54 24 60       	lea    0x60(%rsp),%rdx
 10665e1:	48 8d 3d b8 f1 01 00 	lea    0x1f1b8(%rip),%rdi        # 10857a0 <core_durable_error.verbs+0x6090>
 10665e8:	e9 1d 02 00 00       	jmp    106680a <my.interpreter::evaluate+0x183a>
 10665ed:	48 8b 5c 24 60       	mov    0x60(%rsp),%rbx
 10665f2:	48 8b 4c 24 68       	mov    0x68(%rsp),%rcx
 10665f7:	48 8d 3d 32 f2 01 00 	lea    0x1f232(%rip),%rdi        # 1085830 <core_durable_error.verbs+0x6120>
 10665fe:	e8 fd 04 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 1066603:	48 8d 3d f6 c1 01 00 	lea    0x1c1f6(%rip),%rdi        # 1082800 <core_durable_error.verbs+0x30f0>
 106660a:	e9 dd 03 00 00       	jmp    10669ec <my.interpreter::evaluate+0x1a1c>
 106660f:	4c 89 dd             	mov    %r11,%rbp
 1066612:	c5 fa 6f 44 24 60    	vmovdqu 0x60(%rsp),%xmm0
 1066618:	c5 f9 7f 44 24 10    	vmovdqa %xmm0,0x10(%rsp)
 106661e:	48 8d 3d 4b f4 01 00 	lea    0x1f44b(%rip),%rdi        # 1085a70 <core_durable_error.verbs+0x6360>
 1066625:	e9 92 01 00 00       	jmp    10667bc <my.interpreter::evaluate+0x17ec>
 106662a:	48 8b 5c 24 60       	mov    0x60(%rsp),%rbx
 106662f:	48 8b 4c 24 68       	mov    0x68(%rsp),%rcx
 1066634:	48 8d 3d 05 ee 01 00 	lea    0x1ee05(%rip),%rdi        # 1085440 <core_durable_error.verbs+0x5d30>
 106663b:	e8 c0 04 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 1066640:	e9 a0 03 00 00       	jmp    10669e5 <my.interpreter::evaluate+0x1a15>
 1066645:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
 106664a:	48 8b 44 24 60       	mov    0x60(%rsp),%rax
 106664f:	48 8b 54 24 68       	mov    0x68(%rsp),%rdx
 1066654:	48 8d 3d 05 ef 01 00 	lea    0x1ef05(%rip),%rdi        # 1085560 <core_durable_error.verbs+0x5e50>
 106665b:	e9 12 01 00 00       	jmp    1066772 <my.interpreter::evaluate+0x17a2>
 1066660:	48 89 f9             	mov    %rdi,%rcx
 1066663:	48 8d 3d 46 f3 01 00 	lea    0x1f346(%rip),%rdi        # 10859b0 <core_durable_error.verbs+0x62a0>
 106666a:	c5 f9 10 44 24 60    	vmovupd 0x60(%rsp),%xmm0
 1066670:	c5 f9 29 44 24 10    	vmovapd %xmm0,0x10(%rsp)
 1066676:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 106667b:	e8 80 04 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 1066680:	48 8d 3d d9 c1 01 00 	lea    0x1c1d9(%rip),%rdi        # 1082860 <core_durable_error.verbs+0x3150>
 1066687:	e8 74 04 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 106668c:	b8 01 00 00 00       	mov    $0x1,%eax
 1066691:	48 89 cf             	mov    %rcx,%rdi
 1066694:	c5 f9 28 44 24 10    	vmovapd 0x10(%rsp),%xmm0
 106669a:	e9 ad fb ff ff       	jmp    106624c <my.interpreter::evaluate+0x127c>
 106669f:	c5 f9 29 44 24 30    	vmovapd %xmm0,0x30(%rsp)
 10666a5:	48 8b 44 24 60       	mov    0x60(%rsp),%rax
 10666aa:	48 8b 54 24 68       	mov    0x68(%rsp),%rdx
 10666af:	48 8d 3d 1a f7 01 00 	lea    0x1f71a(%rip),%rdi        # 1085dd0 <core_durable_error.verbs+0x66c0>
 10666b6:	e8 45 04 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 10666bb:	49 89 de             	mov    %rbx,%r14
 10666be:	e9 9b 01 00 00       	jmp    106685e <my.interpreter::evaluate+0x188e>
 10666c3:	48 89 df             	mov    %rbx,%rdi
 10666c6:	4c 89 fe             	mov    %r15,%rsi
 10666c9:	e8 22 2a 00 00       	call   10690f0 <my.heap::string_chars>
 10666ce:	48 89 c3             	mov    %rax,%rbx
 10666d1:	48 8d 3d 28 c0 fa ff 	lea    -0x53fd8(%rip),%rdi        # 1012700 <core_number_pairs+0xb4a0>
 10666d8:	48 89 c6             	mov    %rax,%rsi
 10666db:	e8 a0 86 fc ff       	call   102ed80 <myl_core_bytes_concat>
 10666e0:	4d 89 f4             	mov    %r14,%r12
 10666e3:	49 89 c6             	mov    %rax,%r14
 10666e6:	48 89 df             	mov    %rbx,%rdi
 10666e9:	e8 92 d2 fb ff       	call   1023980 <myl_core_drop_owned>
 10666ee:	48 8d 35 0b ba fa ff 	lea    -0x545f5(%rip),%rsi        # 1012100 <core_number_pairs+0xaea0>
 10666f5:	4c 89 f7             	mov    %r14,%rdi
 10666f8:	e8 83 86 fc ff       	call   102ed80 <myl_core_bytes_concat>
 10666fd:	49 89 c7             	mov    %rax,%r15
 1066700:	4c 89 f7             	mov    %r14,%rdi
 1066703:	4d 89 e6             	mov    %r12,%r14
 1066706:	e8 75 d2 fb ff       	call   1023980 <myl_core_drop_owned>
 106670b:	4c 89 ff             	mov    %r15,%rdi
 106670e:	e8 ed da fb ff       	call   1024200 <myl_core_owned_octets_copy>
 1066713:	48 89 c3             	mov    %rax,%rbx
 1066716:	4c 89 ff             	mov    %r15,%rdi
 1066719:	e8 62 d2 fb ff       	call   1023980 <myl_core_drop_owned>
 106671e:	48 8d 3d 1b f6 01 00 	lea    0x1f61b(%rip),%rdi        # 1085d40 <core_durable_error.verbs+0x6630>
 1066725:	e8 96 03 ff ff       	call   1056ac0 <myl_core_err_trace_origin_preserve_most>
 106672a:	48 8d 3d 8f c1 01 00 	lea    0x1c18f(%rip),%rdi        # 10828c0 <core_durable_error.verbs+0x31b0>
 1066731:	e8 ca 03 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 1066736:	b8 01 00 00 00       	mov    $0x1,%eax
 106673b:	48 8b 8c 24 f8 04 00 	mov    0x4f8(%rsp),%rcx
 1066742:	00 
 1066743:	44 0f b6 a4 24 00 05 	movzbl 0x500(%rsp),%r12d
 106674a:	00 00 
 106674c:	48 8b 54 24 30       	mov    0x30(%rsp),%rdx
 1066751:	e9 15 f7 ff ff       	jmp    1065e6b <my.interpreter::evaluate+0xe9b>
 1066756:	4c 89 5c 24 30       	mov    %r11,0x30(%rsp)
 106675b:	48 8b 84 24 78 01 00 	mov    0x178(%rsp),%rax
 1066762:	00 
 1066763:	48 8b 94 24 80 01 00 	mov    0x180(%rsp),%rdx
 106676a:	00 
 106676b:	48 8d 3d 1e ee 01 00 	lea    0x1ee1e(%rip),%rdi        # 1085590 <core_durable_error.verbs+0x5e80>
 1066772:	e8 89 03 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 1066777:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 106677c:	48 8d 3d 1d c0 01 00 	lea    0x1c01d(%rip),%rdi        # 10827a0 <core_durable_error.verbs+0x3090>
 1066783:	e8 78 03 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 1066788:	b9 01 00 00 00       	mov    $0x1,%ecx
 106678d:	4c 8b 5c 24 30       	mov    0x30(%rsp),%r11
 1066792:	e9 4e fd ff ff       	jmp    10664e5 <my.interpreter::evaluate+0x1515>
 1066797:	c5 f9 29 44 24 10    	vmovapd %xmm0,0x10(%rsp)
 106679d:	48 8d 3d 5c f0 01 00 	lea    0x1f05c(%rip),%rdi        # 1085800 <core_durable_error.verbs+0x60f0>
 10667a4:	eb 73                	jmp    1066819 <my.interpreter::evaluate+0x1849>
 10667a6:	c5 fa 6f 84 24 78 01 	vmovdqu 0x178(%rsp),%xmm0
 10667ad:	00 00 
 10667af:	c5 f9 7f 44 24 10    	vmovdqa %xmm0,0x10(%rsp)
 10667b5:	48 8d 3d 14 f3 01 00 	lea    0x1f314(%rip),%rdi        # 1085ad0 <core_durable_error.verbs+0x63c0>
 10667bc:	e8 3f 03 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 10667c1:	48 8d 3d c8 c0 01 00 	lea    0x1c0c8(%rip),%rdi        # 1082890 <core_durable_error.verbs+0x3180>
 10667c8:	e8 33 03 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 10667cd:	b8 01 00 00 00       	mov    $0x1,%eax
 10667d2:	c5 f9 28 44 24 10    	vmovapd 0x10(%rsp),%xmm0
 10667d8:	49 89 06             	mov    %rax,(%r14)
 10667db:	c4 c1 79 11 46 08    	vmovupd %xmm0,0x8(%r14)
 10667e1:	49 89 ae 00 01 00 00 	mov    %rbp,0x100(%r14)
 10667e8:	4d 89 86 08 01 00 00 	mov    %r8,0x108(%r14)
 10667ef:	4d 89 96 10 01 00 00 	mov    %r10,0x110(%r14)
 10667f6:	e9 24 02 00 00       	jmp    1066a1f <my.interpreter::evaluate+0x1a4f>
 10667fb:	48 8d 3d ce ef 01 00 	lea    0x1efce(%rip),%rdi        # 10857d0 <core_durable_error.verbs+0x60c0>
 1066802:	48 8d 94 24 78 01 00 	lea    0x178(%rsp),%rdx
 1066809:	00 
 106680a:	c5 f9 10 02          	vmovupd (%rdx),%xmm0
 106680e:	c5 f9 29 44 24 10    	vmovapd %xmm0,0x10(%rsp)
 1066814:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 1066819:	e8 e2 02 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 106681e:	48 8d 3d ab bf 01 00 	lea    0x1bfab(%rip),%rdi        # 10827d0 <core_durable_error.verbs+0x30c0>
 1066825:	e8 d6 02 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 106682a:	ba 01 00 00 00       	mov    $0x1,%edx
 106682f:	c5 f9 28 44 24 10    	vmovapd 0x10(%rsp),%xmm0
 1066835:	e9 30 f9 ff ff       	jmp    106616a <my.interpreter::evaluate+0x119a>
 106683a:	e8 c1 d9 fb ff       	call   1024200 <myl_core_owned_octets_copy>
 106683f:	48 8d 3d ea f5 01 00 	lea    0x1f5ea(%rip),%rdi        # 1085e30 <core_durable_error.verbs+0x6720>
 1066846:	eb 0c                	jmp    1066854 <my.interpreter::evaluate+0x1884>
 1066848:	e8 b3 d9 fb ff       	call   1024200 <myl_core_owned_octets_copy>
 106684d:	48 8d 3d 0c f6 01 00 	lea    0x1f60c(%rip),%rdi        # 1085e60 <core_durable_error.verbs+0x6750>
 1066854:	e8 67 02 ff ff       	call   1056ac0 <myl_core_err_trace_origin_preserve_most>
 1066859:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
 106685e:	48 8d 3d 8b c0 01 00 	lea    0x1c08b(%rip),%rdi        # 10828f0 <core_durable_error.verbs+0x31e0>
 1066865:	e8 96 02 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 106686a:	b9 01 00 00 00       	mov    $0x1,%ecx
 106686f:	c5 f9 28 44 24 30    	vmovapd 0x30(%rsp),%xmm0
 1066875:	e9 85 fa ff ff       	jmp    10662ff <my.interpreter::evaluate+0x132f>
 106687a:	4c 89 ef             	mov    %r13,%rdi
 106687d:	48 89 ee             	mov    %rbp,%rsi
 1066880:	e8 6b 28 00 00       	call   10690f0 <my.heap::string_chars>
 1066885:	48 89 c3             	mov    %rax,%rbx
 1066888:	48 8d 3d 71 be fa ff 	lea    -0x5418f(%rip),%rdi        # 1012700 <core_number_pairs+0xb4a0>
 106688f:	48 89 c6             	mov    %rax,%rsi
 1066892:	e8 e9 84 fc ff       	call   102ed80 <myl_core_bytes_concat>
 1066897:	49 89 c6             	mov    %rax,%r14
 106689a:	48 89 df             	mov    %rbx,%rdi
 106689d:	e8 de d0 fb ff       	call   1023980 <myl_core_drop_owned>
 10668a2:	48 8d 35 57 b8 fa ff 	lea    -0x547a9(%rip),%rsi        # 1012100 <core_number_pairs+0xaea0>
 10668a9:	4c 89 f7             	mov    %r14,%rdi
 10668ac:	e8 cf 84 fc ff       	call   102ed80 <myl_core_bytes_concat>
 10668b1:	49 89 c7             	mov    %rax,%r15
 10668b4:	4c 89 f7             	mov    %r14,%rdi
 10668b7:	e8 c4 d0 fb ff       	call   1023980 <myl_core_drop_owned>
 10668bc:	4c 89 ff             	mov    %r15,%rdi
 10668bf:	e8 3c d9 fb ff       	call   1024200 <myl_core_owned_octets_copy>
 10668c4:	48 89 c3             	mov    %rax,%rbx
 10668c7:	4c 89 ff             	mov    %r15,%rdi
 10668ca:	e8 b1 d0 fb ff       	call   1023980 <myl_core_drop_owned>
 10668cf:	48 8d 3d ba ef 01 00 	lea    0x1efba(%rip),%rdi        # 1085890 <core_durable_error.verbs+0x6180>
 10668d6:	e8 e5 01 ff ff       	call   1056ac0 <myl_core_err_trace_origin_preserve_most>
 10668db:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 10668e0:	4c 8b 64 24 28       	mov    0x28(%rsp),%r12
 10668e5:	e9 82 fa ff ff       	jmp    106636c <my.interpreter::evaluate+0x139c>
 10668ea:	48 89 ef             	mov    %rbp,%rdi
 10668ed:	48 89 de             	mov    %rbx,%rsi
 10668f0:	e8 fb 27 00 00       	call   10690f0 <my.heap::string_chars>
 10668f5:	48 89 c3             	mov    %rax,%rbx
 10668f8:	48 8d 3d c1 b7 fa ff 	lea    -0x5483f(%rip),%rdi        # 10120c0 <core_number_pairs+0xae60>
 10668ff:	48 89 c6             	mov    %rax,%rsi
 1066902:	e8 79 84 fc ff       	call   102ed80 <myl_core_bytes_concat>
 1066907:	4d 89 f4             	mov    %r14,%r12
 106690a:	49 89 c6             	mov    %rax,%r14
 106690d:	48 89 df             	mov    %rbx,%rdi
 1066910:	e8 6b d0 fb ff       	call   1023980 <myl_core_drop_owned>
 1066915:	48 8d 35 e4 b7 fa ff 	lea    -0x5481c(%rip),%rsi        # 1012100 <core_number_pairs+0xaea0>
 106691c:	4c 89 f7             	mov    %r14,%rdi
 106691f:	e8 5c 84 fc ff       	call   102ed80 <myl_core_bytes_concat>
 1066924:	49 89 c7             	mov    %rax,%r15
 1066927:	4c 89 f7             	mov    %r14,%rdi
 106692a:	4d 89 e6             	mov    %r12,%r14
 106692d:	e8 4e d0 fb ff       	call   1023980 <myl_core_drop_owned>
 1066932:	4c 89 ff             	mov    %r15,%rdi
 1066935:	e8 c6 d8 fb ff       	call   1024200 <myl_core_owned_octets_copy>
 106693a:	48 89 c3             	mov    %rax,%rbx
 106693d:	4c 89 ff             	mov    %r15,%rdi
 1066940:	e8 3b d0 fb ff       	call   1023980 <myl_core_drop_owned>
 1066945:	48 8d 3d a4 f5 01 00 	lea    0x1f5a4(%rip),%rdi        # 1085ef0 <core_durable_error.verbs+0x67e0>
 106694c:	e8 6f 01 ff ff       	call   1056ac0 <myl_core_err_trace_origin_preserve_most>
 1066951:	48 8d 3d c8 bf 01 00 	lea    0x1bfc8(%rip),%rdi        # 1082920 <core_durable_error.verbs+0x3210>
 1066958:	e8 a3 01 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 106695d:	b8 01 00 00 00       	mov    $0x1,%eax
 1066962:	4c 8b 9c 24 f8 04 00 	mov    0x4f8(%rsp),%r11
 1066969:	00 
 106696a:	4c 8b bc 24 08 05 00 	mov    0x508(%rsp),%r15
 1066971:	00 
 1066972:	e9 52 f7 ff ff       	jmp    10660c9 <my.interpreter::evaluate+0x10f9>
 1066977:	4c 89 ef             	mov    %r13,%rdi
 106697a:	48 8b 74 24 30       	mov    0x30(%rsp),%rsi
 106697f:	e8 6c 27 00 00       	call   10690f0 <my.heap::string_chars>
 1066984:	48 89 c3             	mov    %rax,%rbx
 1066987:	48 8d 3d 32 b7 fa ff 	lea    -0x548ce(%rip),%rdi        # 10120c0 <core_number_pairs+0xae60>
 106698e:	48 89 c6             	mov    %rax,%rsi
 1066991:	e8 ea 83 fc ff       	call   102ed80 <myl_core_bytes_concat>
 1066996:	4d 89 f5             	mov    %r14,%r13
 1066999:	49 89 c6             	mov    %rax,%r14
 106699c:	48 89 df             	mov    %rbx,%rdi
 106699f:	e8 dc cf fb ff       	call   1023980 <myl_core_drop_owned>
 10669a4:	48 8d 35 55 b7 fa ff 	lea    -0x548ab(%rip),%rsi        # 1012100 <core_number_pairs+0xaea0>
 10669ab:	4c 89 f7             	mov    %r14,%rdi
 10669ae:	e8 cd 83 fc ff       	call   102ed80 <myl_core_bytes_concat>
 10669b3:	49 89 c7             	mov    %rax,%r15
 10669b6:	4c 89 f7             	mov    %r14,%rdi
 10669b9:	4d 89 ee             	mov    %r13,%r14
 10669bc:	e8 bf cf fb ff       	call   1023980 <myl_core_drop_owned>
 10669c1:	4c 89 ff             	mov    %r15,%rdi
 10669c4:	e8 37 d8 fb ff       	call   1024200 <myl_core_owned_octets_copy>
 10669c9:	48 89 c3             	mov    %rax,%rbx
 10669cc:	4c 89 ff             	mov    %r15,%rdi
 10669cf:	e8 ac cf fb ff       	call   1023980 <myl_core_drop_owned>
 10669d4:	48 8d 3d 95 ea 01 00 	lea    0x1ea95(%rip),%rdi        # 1085470 <core_durable_error.verbs+0x5d60>
 10669db:	e8 e0 00 ff ff       	call   1056ac0 <myl_core_err_trace_origin_preserve_most>
 10669e0:	48 8b 4c 24 48       	mov    0x48(%rsp),%rcx
 10669e5:	48 8d 3d 84 bd 01 00 	lea    0x1bd84(%rip),%rdi        # 1082770 <core_durable_error.verbs+0x3060>
 10669ec:	e8 0f 01 ff ff       	call   1056b00 <myl_core_err_trace_append_preserve_most>
 10669f1:	b8 01 00 00 00       	mov    $0x1,%eax
 10669f6:	c5 f9 28 44 24 10    	vmovapd 0x10(%rsp),%xmm0
 10669fc:	49 89 06             	mov    %rax,(%r14)
 10669ff:	49 89 5e 08          	mov    %rbx,0x8(%r14)
 1066a03:	49 89 4e 10          	mov    %rcx,0x10(%r14)
 1066a07:	c5 f9 54 05 11 d9 f9 	vandpd -0x626ef(%rip),%xmm0,%xmm0        # 1004320 <__anon_2217+0x60>
 1066a0e:	ff 
 1066a0f:	c4 c1 79 11 86 00 01 	vmovupd %xmm0,0x100(%r14)
 1066a16:	00 00 
 1066a18:	4d 89 a6 10 01 00 00 	mov    %r12,0x110(%r14)
 1066a1f:	4c 89 f0             	mov    %r14,%rax
 1066a22:	48 81 c4 b8 04 00 00 	add    $0x4b8,%rsp
 1066a29:	5b                   	pop    %rbx
 1066a2a:	41 5c                	pop    %r12
 1066a2c:	41 5d                	pop    %r13
 1066a2e:	41 5e                	pop    %r14
 1066a30:	41 5f                	pop    %r15
 1066a32:	5d                   	pop    %rbp
 1066a33:	c3                   	ret
 1066a34:	48 8d 3d 85 b7 fa ff 	lea    -0x5487b(%rip),%rdi        # 10121c0 <core_number_pairs+0xaf60>
 1066a3b:	e8 c0 d7 fb ff       	call   1024200 <myl_core_owned_octets_copy>
 1066a40:	48 8d 3d a9 eb 01 00 	lea    0x1eba9(%rip),%rdi        # 10855f0 <core_durable_error.verbs+0x5ee0>
 1066a47:	e8 74 00 ff ff       	call   1056ac0 <myl_core_err_trace_origin_preserve_most>
 1066a4c:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 1066a51:	4d 89 ea             	mov    %r13,%r10
 1066a54:	eb 22                	jmp    1066a78 <my.interpreter::evaluate+0x1aa8>
 1066a56:	48 8d 3d a3 b7 fa ff 	lea    -0x5485d(%rip),%rdi        # 1012200 <core_number_pairs+0xafa0>
 1066a5d:	e8 9e d7 fb ff       	call   1024200 <myl_core_owned_octets_copy>
 1066a62:	48 8d 3d 57 eb 01 00 	lea    0x1eb57(%rip),%rdi        # 10855c0 <core_durable_error.verbs+0x5eb0>
 1066a69:	e8 52 00 ff ff       	call   1056ac0 <myl_core_err_trace_origin_preserve_most>
 1066a6e:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 1066a73:	4c 8b 54 24 28       	mov    0x28(%rsp),%r10
 1066a78:	4c 8b 7c 24 10       	mov    0x10(%rsp),%r15
 1066a7d:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
 1066a82:	e9 f5 fc ff ff       	jmp    106677c <my.interpreter::evaluate+0x17ac>
 1066a87:	48 89 f0             	mov    %rsi,%rax
 1066a8a:	48 c1 f8 3f          	sar    $0x3f,%rax
 1066a8e:	48 21 d0             	and    %rdx,%rax
 1066a91:	48 01 f0             	add    %rsi,%rax
 1066a94:	48 39 d0             	cmp    %rdx,%rax
 1066a97:	0f 82 65 e5 ff ff    	jb     1065002 <my.interpreter::evaluate+0x32>
 1066a9d:	48 8d 3d 9c bc 01 00 	lea    0x1bc9c(%rip),%rdi        # 1082740 <core_durable_error.verbs+0x3030>
 1066aa4:	e8 57 dc fb ff       	call   1024700 <myl_core_trap>
 1066aa9:	48 89 f1             	mov    %rsi,%rcx
 1066aac:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066ab0:	48 21 d1             	and    %rdx,%rcx
 1066ab3:	48 01 f1             	add    %rsi,%rcx
 1066ab6:	48 39 d1             	cmp    %rdx,%rcx
 1066ab9:	0f 82 ed ed ff ff    	jb     10658ac <my.interpreter::evaluate+0x8dc>
 1066abf:	48 8d 3d 8a be 01 00 	lea    0x1be8a(%rip),%rdi        # 1082950 <core_durable_error.verbs+0x3240>
 1066ac6:	e8 35 dc fb ff       	call   1024700 <myl_core_trap>
 1066acb:	48 89 f7             	mov    %rsi,%rdi
 1066ace:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1066ad2:	48 21 d7             	and    %rdx,%rdi
 1066ad5:	48 01 f7             	add    %rsi,%rdi
 1066ad8:	48 39 d7             	cmp    %rdx,%rdi
 1066adb:	0f 82 38 f1 ff ff    	jb     1065c19 <my.interpreter::evaluate+0xc49>
 1066ae1:	48 8d 3d c8 bb 01 00 	lea    0x1bbc8(%rip),%rdi        # 10826b0 <core_durable_error.verbs+0x2fa0>
 1066ae8:	e8 13 dc fb ff       	call   1024700 <myl_core_trap>
 1066aed:	49 89 c8             	mov    %rcx,%r8
 1066af0:	49 c1 f8 3f          	sar    $0x3f,%r8
 1066af4:	49 21 d0             	and    %rdx,%r8
 1066af7:	49 01 c8             	add    %rcx,%r8
 1066afa:	49 39 d0             	cmp    %rdx,%r8
 1066afd:	0f 82 bf f1 ff ff    	jb     1065cc2 <my.interpreter::evaluate+0xcf2>
 1066b03:	48 8d 3d a6 bb 01 00 	lea    0x1bba6(%rip),%rdi        # 10826b0 <core_durable_error.verbs+0x2fa0>
 1066b0a:	48 89 ce             	mov    %rcx,%rsi
 1066b0d:	e8 ee db fb ff       	call   1024700 <myl_core_trap>
 1066b12:	48 89 c6             	mov    %rax,%rsi
 1066b15:	48 c1 fe 3f          	sar    $0x3f,%rsi
 1066b19:	48 21 d6             	and    %rdx,%rsi
 1066b1c:	48 01 c6             	add    %rax,%rsi
 1066b1f:	48 39 d6             	cmp    %rdx,%rsi
 1066b22:	0f 82 1b f1 ff ff    	jb     1065c43 <my.interpreter::evaluate+0xc73>
 1066b28:	48 8d 3d e1 bb 01 00 	lea    0x1bbe1(%rip),%rdi        # 1082710 <core_durable_error.verbs+0x3000>
 1066b2f:	48 89 c6             	mov    %rax,%rsi
 1066b32:	e8 c9 db fb ff       	call   1024700 <myl_core_trap>
 1066b37:	48 89 f1             	mov    %rsi,%rcx
 1066b3a:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066b3e:	48 21 d1             	and    %rdx,%rcx
 1066b41:	48 01 f1             	add    %rsi,%rcx
 1066b44:	48 39 d1             	cmp    %rdx,%rcx
 1066b47:	0f 82 1b f1 ff ff    	jb     1065c68 <my.interpreter::evaluate+0xc98>
 1066b4d:	48 8d 3d 5c be 01 00 	lea    0x1be5c(%rip),%rdi        # 10829b0 <core_durable_error.verbs+0x32a0>
 1066b54:	e8 a7 db fb ff       	call   1024700 <myl_core_trap>
 1066b59:	48 8d 3d b0 bb 01 00 	lea    0x1bbb0(%rip),%rdi        # 1082710 <core_durable_error.verbs+0x3000>
 1066b60:	31 f6                	xor    %esi,%esi
 1066b62:	31 d2                	xor    %edx,%edx
 1066b64:	e8 97 db fb ff       	call   1024700 <myl_core_trap>
 1066b69:	48 89 f1             	mov    %rsi,%rcx
 1066b6c:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066b70:	48 21 d1             	and    %rdx,%rcx
 1066b73:	48 01 f1             	add    %rsi,%rcx
 1066b76:	48 39 d1             	cmp    %rdx,%rcx
 1066b79:	0f 82 0f f2 ff ff    	jb     1065d8e <my.interpreter::evaluate+0xdbe>
 1066b7f:	48 8d 3d 2a bb 01 00 	lea    0x1bb2a(%rip),%rdi        # 10826b0 <core_durable_error.verbs+0x2fa0>
 1066b86:	e8 75 db fb ff       	call   1024700 <myl_core_trap>
 1066b8b:	48 8d 3d 7e bb 01 00 	lea    0x1bb7e(%rip),%rdi        # 1082710 <core_durable_error.verbs+0x3000>
 1066b92:	31 f6                	xor    %esi,%esi
 1066b94:	31 d2                	xor    %edx,%edx
 1066b96:	e8 65 db fb ff       	call   1024700 <myl_core_trap>
 1066b9b:	49 89 f5             	mov    %rsi,%r13
 1066b9e:	49 c1 fd 3f          	sar    $0x3f,%r13
 1066ba2:	49 21 d5             	and    %rdx,%r13
 1066ba5:	49 01 f5             	add    %rsi,%r13
 1066ba8:	49 39 d5             	cmp    %rdx,%r13
 1066bab:	0f 82 5f e8 ff ff    	jb     1065410 <my.interpreter::evaluate+0x440>
 1066bb1:	48 8d 3d 38 ed 01 00 	lea    0x1ed38(%rip),%rdi        # 10858f0 <core_durable_error.verbs+0x61e0>
 1066bb8:	e8 43 db fb ff       	call   1024700 <myl_core_trap>
 1066bbd:	48 89 f7             	mov    %rsi,%rdi
 1066bc0:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1066bc4:	48 21 d7             	and    %rdx,%rdi
 1066bc7:	48 01 f7             	add    %rsi,%rdi
 1066bca:	48 39 d7             	cmp    %rdx,%rdi
 1066bcd:	4d 89 ea             	mov    %r13,%r10
 1066bd0:	0f 82 90 e9 ff ff    	jb     1065566 <my.interpreter::evaluate+0x596>
 1066bd6:	48 8d 3d 53 ef 01 00 	lea    0x1ef53(%rip),%rdi        # 1085b30 <core_durable_error.verbs+0x6420>
 1066bdd:	e8 1e db fb ff       	call   1024700 <myl_core_trap>
 1066be2:	48 89 f1             	mov    %rsi,%rcx
 1066be5:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066be9:	48 21 d1             	and    %rdx,%rcx
 1066bec:	48 01 f1             	add    %rsi,%rcx
 1066bef:	48 39 d1             	cmp    %rdx,%rcx
 1066bf2:	0f 82 95 ed ff ff    	jb     106598d <my.interpreter::evaluate+0x9bd>
 1066bf8:	48 8d 3d 41 ee 01 00 	lea    0x1ee41(%rip),%rdi        # 1085a40 <core_durable_error.verbs+0x6330>
 1066bff:	e8 fc da fb ff       	call   1024700 <myl_core_trap>
 1066c04:	48 89 f7             	mov    %rsi,%rdi
 1066c07:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1066c0b:	48 21 d7             	and    %rdx,%rdi
 1066c0e:	48 01 f7             	add    %rsi,%rdi
 1066c11:	48 39 d7             	cmp    %rdx,%rdi
 1066c14:	0f 82 a2 ee ff ff    	jb     1065abc <my.interpreter::evaluate+0xaec>
 1066c1a:	48 8d 3d 9f f2 01 00 	lea    0x1f29f(%rip),%rdi        # 1085ec0 <core_durable_error.verbs+0x67b0>
 1066c21:	e8 da da fb ff       	call   1024700 <myl_core_trap>
 1066c26:	48 89 f7             	mov    %rsi,%rdi
 1066c29:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1066c2d:	48 21 d7             	and    %rdx,%rdi
 1066c30:	48 01 f7             	add    %rsi,%rdi
 1066c33:	48 39 d7             	cmp    %rdx,%rdi
 1066c36:	0f 82 00 f2 ff ff    	jb     1065e3c <my.interpreter::evaluate+0xe6c>
 1066c3c:	48 8d 3d 2d f1 01 00 	lea    0x1f12d(%rip),%rdi        # 1085d70 <core_durable_error.verbs+0x6660>
 1066c43:	e8 b8 da fb ff       	call   1024700 <myl_core_trap>
 1066c48:	4c 89 f9             	mov    %r15,%rcx
 1066c4b:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066c4f:	48 21 d1             	and    %rdx,%rcx
 1066c52:	4c 01 f9             	add    %r15,%rcx
 1066c55:	48 39 d1             	cmp    %rdx,%rcx
 1066c58:	0f 82 e0 e7 ff ff    	jb     106543e <my.interpreter::evaluate+0x46e>
 1066c5e:	48 8d 3d bb ce 01 00 	lea    0x1cebb(%rip),%rdi        # 1083b20 <core_durable_error.verbs+0x4410>
 1066c65:	4c 89 fe             	mov    %r15,%rsi
 1066c68:	e8 93 da fb ff       	call   1024700 <myl_core_trap>
 1066c6d:	48 89 f7             	mov    %rsi,%rdi
 1066c70:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1066c74:	48 21 d7             	and    %rdx,%rdi
 1066c77:	48 01 f7             	add    %rsi,%rdi
 1066c7a:	48 39 d7             	cmp    %rdx,%rdi
 1066c7d:	0f 82 0a e9 ff ff    	jb     106558d <my.interpreter::evaluate+0x5bd>
 1066c83:	48 8d 3d 96 ce 01 00 	lea    0x1ce96(%rip),%rdi        # 1083b20 <core_durable_error.verbs+0x4410>
 1066c8a:	e8 71 da fb ff       	call   1024700 <myl_core_trap>
 1066c8f:	48 89 f7             	mov    %rsi,%rdi
 1066c92:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1066c96:	48 21 d7             	and    %rdx,%rdi
 1066c99:	48 01 f7             	add    %rsi,%rdi
 1066c9c:	48 39 d7             	cmp    %rdx,%rdi
 1066c9f:	0f 82 7b eb ff ff    	jb     1065820 <my.interpreter::evaluate+0x850>
 1066ca5:	48 8d 3d d4 e9 01 00 	lea    0x1e9d4(%rip),%rdi        # 1085680 <core_durable_error.verbs+0x5f70>
 1066cac:	e8 4f da fb ff       	call   1024700 <myl_core_trap>
 1066cb1:	4c 89 fe             	mov    %r15,%rsi
 1066cb4:	48 c1 fe 3f          	sar    $0x3f,%rsi
 1066cb8:	48 21 d6             	and    %rdx,%rsi
 1066cbb:	4c 01 fe             	add    %r15,%rsi
 1066cbe:	48 39 d6             	cmp    %rdx,%rsi
 1066cc1:	0f 82 73 eb ff ff    	jb     106583a <my.interpreter::evaluate+0x86a>
 1066cc7:	48 8d 3d 42 ea 01 00 	lea    0x1ea42(%rip),%rdi        # 1085710 <core_durable_error.verbs+0x6000>
 1066cce:	4c 89 fe             	mov    %r15,%rsi
 1066cd1:	e8 2a da fb ff       	call   1024700 <myl_core_trap>
 1066cd6:	4c 89 fe             	mov    %r15,%rsi
 1066cd9:	48 c1 fe 3f          	sar    $0x3f,%rsi
 1066cdd:	48 21 ce             	and    %rcx,%rsi
 1066ce0:	4c 01 fe             	add    %r15,%rsi
 1066ce3:	48 39 ce             	cmp    %rcx,%rsi
 1066ce6:	0f 82 c5 f7 ff ff    	jb     10664b1 <my.interpreter::evaluate+0x14e1>
 1066cec:	48 8d 3d ed e9 01 00 	lea    0x1e9ed(%rip),%rdi        # 10856e0 <core_durable_error.verbs+0x5fd0>
 1066cf3:	4c 89 fe             	mov    %r15,%rsi
 1066cf6:	48 89 ca             	mov    %rcx,%rdx
 1066cf9:	e8 02 da fb ff       	call   1024700 <myl_core_trap>
 1066cfe:	49 89 f0             	mov    %rsi,%r8
 1066d01:	49 c1 f8 3f          	sar    $0x3f,%r8
 1066d05:	49 21 c8             	and    %rcx,%r8
 1066d08:	49 01 f0             	add    %rsi,%r8
 1066d0b:	49 39 c8             	cmp    %rcx,%r8
 1066d0e:	4c 8b 7c 24 10       	mov    0x10(%rsp),%r15
 1066d13:	0f 82 b5 f7 ff ff    	jb     10664ce <my.interpreter::evaluate+0x14fe>
 1066d19:	48 8d 3d 50 ea 01 00 	lea    0x1ea50(%rip),%rdi        # 1085770 <core_durable_error.verbs+0x6060>
 1066d20:	48 89 ca             	mov    %rcx,%rdx
 1066d23:	e8 d8 d9 fb ff       	call   1024700 <myl_core_trap>
 1066d28:	48 89 f1             	mov    %rsi,%rcx
 1066d2b:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066d2f:	48 21 d1             	and    %rdx,%rcx
 1066d32:	48 01 f1             	add    %rsi,%rcx
 1066d35:	48 39 d1             	cmp    %rdx,%rcx
 1066d38:	0f 82 ea e8 ff ff    	jb     1065628 <my.interpreter::evaluate+0x658>
 1066d3e:	48 8d 3d 7b ee 01 00 	lea    0x1ee7b(%rip),%rdi        # 1085bc0 <core_durable_error.verbs+0x64b0>
 1066d45:	e8 b6 d9 fb ff       	call   1024700 <myl_core_trap>
 1066d4a:	49 89 f0             	mov    %rsi,%r8
 1066d4d:	49 c1 f8 3f          	sar    $0x3f,%r8
 1066d51:	49 21 d0             	and    %rdx,%r8
 1066d54:	49 01 f0             	add    %rsi,%r8
 1066d57:	49 39 d0             	cmp    %rdx,%r8
 1066d5a:	0f 82 20 e9 ff ff    	jb     1065680 <my.interpreter::evaluate+0x6b0>
 1066d60:	48 8d 3d b9 ee 01 00 	lea    0x1eeb9(%rip),%rdi        # 1085c20 <core_durable_error.verbs+0x6510>
 1066d67:	e8 94 d9 fb ff       	call   1024700 <myl_core_trap>
 1066d6c:	48 89 f0             	mov    %rsi,%rax
 1066d6f:	48 c1 f8 3f          	sar    $0x3f,%rax
 1066d73:	48 21 d0             	and    %rdx,%rax
 1066d76:	48 01 f0             	add    %rsi,%rax
 1066d79:	48 39 d0             	cmp    %rdx,%rax
 1066d7c:	0f 82 5a e9 ff ff    	jb     10656dc <my.interpreter::evaluate+0x70c>
 1066d82:	48 8d 3d f7 ee 01 00 	lea    0x1eef7(%rip),%rdi        # 1085c80 <core_durable_error.verbs+0x6570>
 1066d89:	e8 72 d9 fb ff       	call   1024700 <myl_core_trap>
 1066d8e:	48 89 c6             	mov    %rax,%rsi
 1066d91:	48 c1 fe 3f          	sar    $0x3f,%rsi
 1066d95:	48 21 d6             	and    %rdx,%rsi
 1066d98:	48 01 c6             	add    %rax,%rsi
 1066d9b:	48 39 d6             	cmp    %rdx,%rsi
 1066d9e:	0f 82 50 e9 ff ff    	jb     10656f4 <my.interpreter::evaluate+0x724>
 1066da4:	48 8d 3d 35 ef 01 00 	lea    0x1ef35(%rip),%rdi        # 1085ce0 <core_durable_error.verbs+0x65d0>
 1066dab:	48 89 c6             	mov    %rax,%rsi
 1066dae:	e8 4d d9 fb ff       	call   1024700 <myl_core_trap>
 1066db3:	48 89 c7             	mov    %rax,%rdi
 1066db6:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1066dba:	48 21 d7             	and    %rdx,%rdi
 1066dbd:	48 01 c7             	add    %rax,%rdi
 1066dc0:	48 39 d7             	cmp    %rdx,%rdi
 1066dc3:	0f 82 df f0 ff ff    	jb     1065ea8 <my.interpreter::evaluate+0xed8>
 1066dc9:	48 8d 3d e0 b8 01 00 	lea    0x1b8e0(%rip),%rdi        # 10826b0 <core_durable_error.verbs+0x2fa0>
 1066dd0:	48 89 c6             	mov    %rax,%rsi
 1066dd3:	e8 28 d9 fb ff       	call   1024700 <myl_core_trap>
 1066dd8:	48 89 f1             	mov    %rsi,%rcx
 1066ddb:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066ddf:	48 21 d1             	and    %rdx,%rcx
 1066de2:	48 01 f1             	add    %rsi,%rcx
 1066de5:	48 39 d1             	cmp    %rdx,%rcx
 1066de8:	0f 82 e4 f0 ff ff    	jb     1065ed2 <my.interpreter::evaluate+0xf02>
 1066dee:	48 8d 3d 1b b9 01 00 	lea    0x1b91b(%rip),%rdi        # 1082710 <core_durable_error.verbs+0x3000>
 1066df5:	e8 06 d9 fb ff       	call   1024700 <myl_core_trap>
 1066dfa:	48 89 f1             	mov    %rsi,%rcx
 1066dfd:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066e01:	48 21 d1             	and    %rdx,%rcx
 1066e04:	48 01 f1             	add    %rsi,%rcx
 1066e07:	48 39 d1             	cmp    %rdx,%rcx
 1066e0a:	0f 82 e7 f0 ff ff    	jb     1065ef7 <my.interpreter::evaluate+0xf27>
 1066e10:	48 8d 3d 09 f1 01 00 	lea    0x1f109(%rip),%rdi        # 1085f20 <core_durable_error.verbs+0x6810>
 1066e17:	e8 e4 d8 fb ff       	call   1024700 <myl_core_trap>
 1066e1c:	49 89 c1             	mov    %rax,%r9
 1066e1f:	49 c1 f9 3f          	sar    $0x3f,%r9
 1066e23:	49 21 d1             	and    %rdx,%r9
 1066e26:	49 01 c1             	add    %rax,%r9
 1066e29:	49 39 d1             	cmp    %rdx,%r9
 1066e2c:	0f 82 16 f1 ff ff    	jb     1065f48 <my.interpreter::evaluate+0xf78>
 1066e32:	48 8d 3d 97 e6 01 00 	lea    0x1e697(%rip),%rdi        # 10854d0 <core_durable_error.verbs+0x5dc0>
 1066e39:	48 89 c6             	mov    %rax,%rsi
 1066e3c:	e8 bf d8 fb ff       	call   1024700 <myl_core_trap>
 1066e41:	48 89 f7             	mov    %rsi,%rdi
 1066e44:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1066e48:	48 21 d7             	and    %rdx,%rdi
 1066e4b:	48 01 f7             	add    %rsi,%rdi
 1066e4e:	48 39 d7             	cmp    %rdx,%rdi
 1066e51:	0f 82 c1 f1 ff ff    	jb     1066018 <my.interpreter::evaluate+0x1048>
 1066e57:	48 8d 3d 22 eb 01 00 	lea    0x1eb22(%rip),%rdi        # 1085980 <core_durable_error.verbs+0x6270>
 1066e5e:	e8 9d d8 fb ff       	call   1024700 <myl_core_trap>
 1066e63:	49 89 f0             	mov    %rsi,%r8
 1066e66:	49 c1 f8 3f          	sar    $0x3f,%r8
 1066e6a:	49 21 c0             	and    %rax,%r8
 1066e6d:	49 01 f0             	add    %rsi,%r8
 1066e70:	49 39 c0             	cmp    %rax,%r8
 1066e73:	0f 82 1a f2 ff ff    	jb     1066093 <my.interpreter::evaluate+0x10c3>
 1066e79:	48 8d 3d 00 f1 01 00 	lea    0x1f100(%rip),%rdi        # 1085f80 <core_durable_error.verbs+0x6870>
 1066e80:	48 89 c2             	mov    %rax,%rdx
 1066e83:	e8 78 d8 fb ff       	call   1024700 <myl_core_trap>
 1066e88:	48 89 f1             	mov    %rsi,%rcx
 1066e8b:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066e8f:	48 21 d1             	and    %rdx,%rcx
 1066e92:	48 01 f1             	add    %rsi,%rcx
 1066e95:	48 39 d1             	cmp    %rdx,%rcx
 1066e98:	0f 82 49 f3 ff ff    	jb     10661e7 <my.interpreter::evaluate+0x1217>
 1066e9e:	48 8d 3d 8b e6 01 00 	lea    0x1e68b(%rip),%rdi        # 1085530 <core_durable_error.verbs+0x5e20>
 1066ea5:	e8 56 d8 fb ff       	call   1024700 <myl_core_trap>
 1066eaa:	48 8d 3d 5f e5 01 00 	lea    0x1e55f(%rip),%rdi        # 1085410 <core_durable_error.verbs+0x5d00>
 1066eb1:	e8 ca 2b fc ff       	call   1029a80 <myl_core_assert_fail>
 1066eb6:	48 8d 3d 53 e5 01 00 	lea    0x1e553(%rip),%rdi        # 1085410 <core_durable_error.verbs+0x5d00>
 1066ebd:	e8 be 2b fc ff       	call   1029a80 <myl_core_assert_fail>
 1066ec2:	48 8d 3d 47 e5 01 00 	lea    0x1e547(%rip),%rdi        # 1085410 <core_durable_error.verbs+0x5d00>
 1066ec9:	e8 b2 2b fc ff       	call   1029a80 <myl_core_assert_fail>
 1066ece:	48 8d 3d 3b e5 01 00 	lea    0x1e53b(%rip),%rdi        # 1085410 <core_durable_error.verbs+0x5d00>
 1066ed5:	e8 a6 2b fc ff       	call   1029a80 <myl_core_assert_fail>
 1066eda:	48 8d 3d 2f e5 01 00 	lea    0x1e52f(%rip),%rdi        # 1085410 <core_durable_error.verbs+0x5d00>
 1066ee1:	e8 9a 2b fc ff       	call   1029a80 <myl_core_assert_fail>
 1066ee6:	0f b6 c0             	movzbl %al,%eax
 1066ee9:	83 f8 01             	cmp    $0x1,%eax
 1066eec:	0f 84 ba 00 00 00    	je     1066fac <my.interpreter::evaluate+0x1fdc>
 1066ef2:	85 c0                	test   %eax,%eax
 1066ef4:	0f 85 be 00 00 00    	jne    1066fb8 <my.interpreter::evaluate+0x1fe8>
 1066efa:	48 8d 3d 1f e4 01 00 	lea    0x1e41f(%rip),%rdi        # 1085320 <core_durable_error.verbs+0x5c10>
 1066f01:	e8 7a 2b fc ff       	call   1029a80 <myl_core_assert_fail>
 1066f06:	0f b6 c2             	movzbl %dl,%eax
 1066f09:	83 f8 01             	cmp    $0x1,%eax
 1066f0c:	0f 84 02 01 00 00    	je     1067014 <my.interpreter::evaluate+0x2044>
 1066f12:	85 c0                	test   %eax,%eax
 1066f14:	0f 85 06 01 00 00    	jne    1067020 <my.interpreter::evaluate+0x2050>
 1066f1a:	48 8d 3d ff e3 01 00 	lea    0x1e3ff(%rip),%rdi        # 1085320 <core_durable_error.verbs+0x5c10>
 1066f21:	e8 5a 2b fc ff       	call   1029a80 <myl_core_assert_fail>
 1066f26:	83 fa 01             	cmp    $0x1,%edx
 1066f29:	0f 84 6f 01 00 00    	je     106709e <my.interpreter::evaluate+0x20ce>
 1066f2f:	85 d2                	test   %edx,%edx
 1066f31:	0f 85 73 01 00 00    	jne    10670aa <my.interpreter::evaluate+0x20da>
 1066f37:	48 8d 3d e2 e3 01 00 	lea    0x1e3e2(%rip),%rdi        # 1085320 <core_durable_error.verbs+0x5c10>
 1066f3e:	e8 3d 2b fc ff       	call   1029a80 <myl_core_assert_fail>
 1066f43:	0f b6 c2             	movzbl %dl,%eax
 1066f46:	83 f8 01             	cmp    $0x1,%eax
 1066f49:	0f 84 ec 01 00 00    	je     106713b <my.interpreter::evaluate+0x216b>
 1066f4f:	85 c0                	test   %eax,%eax
 1066f51:	0f 85 f0 01 00 00    	jne    1067147 <my.interpreter::evaluate+0x2177>
 1066f57:	48 8d 3d c2 e3 01 00 	lea    0x1e3c2(%rip),%rdi        # 1085320 <core_durable_error.verbs+0x5c10>
 1066f5e:	e8 1d 2b fc ff       	call   1029a80 <myl_core_assert_fail>
 1066f63:	48 8d 3d 76 b7 01 00 	lea    0x1b776(%rip),%rdi        # 10826e0 <core_durable_error.verbs+0x2fd0>
 1066f6a:	e8 11 2b fc ff       	call   1029a80 <myl_core_assert_fail>
 1066f6f:	48 8d 3d 6a b7 01 00 	lea    0x1b76a(%rip),%rdi        # 10826e0 <core_durable_error.verbs+0x2fd0>
 1066f76:	e8 05 2b fc ff       	call   1029a80 <myl_core_assert_fail>
 1066f7b:	48 8d 3d 5e ba 01 00 	lea    0x1ba5e(%rip),%rdi        # 10829e0 <core_durable_error.verbs+0x32d0>
 1066f82:	ba 01 00 00 00       	mov    $0x1,%edx
 1066f87:	e8 74 d7 fb ff       	call   1024700 <myl_core_trap>
 1066f8c:	48 8d 3d 7d ed 01 00 	lea    0x1ed7d(%rip),%rdi        # 1085d10 <core_durable_error.verbs+0x6600>
 1066f93:	ba 01 00 00 00       	mov    $0x1,%edx
 1066f98:	48 89 c6             	mov    %rax,%rsi
 1066f9b:	e8 60 d7 fb ff       	call   1024700 <myl_core_trap>
 1066fa0:	48 8d 3d 39 b7 01 00 	lea    0x1b739(%rip),%rdi        # 10826e0 <core_durable_error.verbs+0x2fd0>
 1066fa7:	e8 d4 2a fc ff       	call   1029a80 <myl_core_assert_fail>
 1066fac:	48 8d 3d 9d e3 01 00 	lea    0x1e39d(%rip),%rdi        # 1085350 <core_durable_error.verbs+0x5c40>
 1066fb3:	e8 c8 2a fc ff       	call   1029a80 <myl_core_assert_fail>
 1066fb8:	48 8d 3d c1 e3 01 00 	lea    0x1e3c1(%rip),%rdi        # 1085380 <core_durable_error.verbs+0x5c70>
 1066fbf:	e8 bc 2a fc ff       	call   1029a80 <myl_core_assert_fail>
 1066fc4:	48 8d 3d f5 e8 01 00 	lea    0x1e8f5(%rip),%rdi        # 10858c0 <core_durable_error.verbs+0x61b0>
 1066fcb:	ba 01 00 00 00       	mov    $0x1,%edx
 1066fd0:	48 89 c6             	mov    %rax,%rsi
 1066fd3:	e8 28 d7 fb ff       	call   1024700 <myl_core_trap>
 1066fd8:	48 8d 3d 21 eb 01 00 	lea    0x1eb21(%rip),%rdi        # 1085b00 <core_durable_error.verbs+0x63f0>
 1066fdf:	ba 01 00 00 00       	mov    $0x1,%edx
 1066fe4:	48 89 c6             	mov    %rax,%rsi
 1066fe7:	e8 14 d7 fb ff       	call   1024700 <myl_core_trap>
 1066fec:	48 8d 3d 1d ea 01 00 	lea    0x1ea1d(%rip),%rdi        # 1085a10 <core_durable_error.verbs+0x6300>
 1066ff3:	ba 01 00 00 00       	mov    $0x1,%edx
 1066ff8:	48 89 c6             	mov    %rax,%rsi
 1066ffb:	e8 00 d7 fb ff       	call   1024700 <myl_core_trap>
 1067000:	48 8d 3d 89 ee 01 00 	lea    0x1ee89(%rip),%rdi        # 1085e90 <core_durable_error.verbs+0x6780>
 1067007:	ba 01 00 00 00       	mov    $0x1,%edx
 106700c:	48 89 c6             	mov    %rax,%rsi
 106700f:	e8 ec d6 fb ff       	call   1024700 <myl_core_trap>
 1067014:	48 8d 3d 35 e3 01 00 	lea    0x1e335(%rip),%rdi        # 1085350 <core_durable_error.verbs+0x5c40>
 106701b:	e8 60 2a fc ff       	call   1029a80 <myl_core_assert_fail>
 1067020:	48 8d 3d 59 e3 01 00 	lea    0x1e359(%rip),%rdi        # 1085380 <core_durable_error.verbs+0x5c70>
 1067027:	e8 54 2a fc ff       	call   1029a80 <myl_core_assert_fail>
 106702c:	48 8d 3d 6d ed 01 00 	lea    0x1ed6d(%rip),%rdi        # 1085da0 <core_durable_error.verbs+0x6690>
 1067033:	ba 01 00 00 00       	mov    $0x1,%edx
 1067038:	e8 c3 d6 fb ff       	call   1024700 <myl_core_trap>
 106703d:	48 8d 3d dc e5 01 00 	lea    0x1e5dc(%rip),%rdi        # 1085620 <core_durable_error.verbs+0x5f10>
 1067044:	ba 01 00 00 00       	mov    $0x1,%edx
 1067049:	4c 89 c6             	mov    %r8,%rsi
 106704c:	e8 af d6 fb ff       	call   1024700 <myl_core_trap>
 1067051:	48 8d 3d f8 e5 01 00 	lea    0x1e5f8(%rip),%rdi        # 1085650 <core_durable_error.verbs+0x5f40>
 1067058:	ba 01 00 00 00       	mov    $0x1,%edx
 106705d:	4c 89 fe             	mov    %r15,%rsi
 1067060:	e8 9b d6 fb ff       	call   1024700 <myl_core_trap>
 1067065:	48 8d 3d d4 e6 01 00 	lea    0x1e6d4(%rip),%rdi        # 1085740 <core_durable_error.verbs+0x6030>
 106706c:	ba 01 00 00 00       	mov    $0x1,%edx
 1067071:	4c 89 fe             	mov    %r15,%rsi
 1067074:	e8 87 d6 fb ff       	call   1024700 <myl_core_trap>
 1067079:	48 8d 3d e0 ea 01 00 	lea    0x1eae0(%rip),%rdi        # 1085b60 <core_durable_error.verbs+0x6450>
 1067080:	ba 01 00 00 00       	mov    $0x1,%edx
 1067085:	e8 76 d6 fb ff       	call   1024700 <myl_core_trap>
 106708a:	48 8d 3d ff ea 01 00 	lea    0x1eaff(%rip),%rdi        # 1085b90 <core_durable_error.verbs+0x6480>
 1067091:	ba 01 00 00 00       	mov    $0x1,%edx
 1067096:	48 89 c6             	mov    %rax,%rsi
 1067099:	e8 62 d6 fb ff       	call   1024700 <myl_core_trap>
 106709e:	48 8d 3d ab e2 01 00 	lea    0x1e2ab(%rip),%rdi        # 1085350 <core_durable_error.verbs+0x5c40>
 10670a5:	e8 d6 29 fc ff       	call   1029a80 <myl_core_assert_fail>
 10670aa:	48 8d 3d cf e2 01 00 	lea    0x1e2cf(%rip),%rdi        # 1085380 <core_durable_error.verbs+0x5c70>
 10670b1:	e8 ca 29 fc ff       	call   1029a80 <myl_core_assert_fail>
 10670b6:	48 8d 3d 33 eb 01 00 	lea    0x1eb33(%rip),%rdi        # 1085bf0 <core_durable_error.verbs+0x64e0>
 10670bd:	ba 01 00 00 00       	mov    $0x1,%edx
 10670c2:	48 89 ce             	mov    %rcx,%rsi
 10670c5:	e8 36 d6 fb ff       	call   1024700 <myl_core_trap>
 10670ca:	48 8d 3d 7f eb 01 00 	lea    0x1eb7f(%rip),%rdi        # 1085c50 <core_durable_error.verbs+0x6540>
 10670d1:	ba 01 00 00 00       	mov    $0x1,%edx
 10670d6:	48 89 c6             	mov    %rax,%rsi
 10670d9:	e8 22 d6 fb ff       	call   1024700 <myl_core_trap>
 10670de:	48 8d 3d cb eb 01 00 	lea    0x1ebcb(%rip),%rdi        # 1085cb0 <core_durable_error.verbs+0x65a0>
 10670e5:	ba 01 00 00 00       	mov    $0x1,%edx
 10670ea:	e8 11 d6 fb ff       	call   1024700 <myl_core_trap>
 10670ef:	48 8d 3d ea b5 01 00 	lea    0x1b5ea(%rip),%rdi        # 10826e0 <core_durable_error.verbs+0x2fd0>
 10670f6:	e8 85 29 fc ff       	call   1029a80 <myl_core_assert_fail>
 10670fb:	48 8d 3d 4e ee 01 00 	lea    0x1ee4e(%rip),%rdi        # 1085f50 <core_durable_error.verbs+0x6840>
 1067102:	ba 01 00 00 00       	mov    $0x1,%edx
 1067107:	e8 f4 d5 fb ff       	call   1024700 <myl_core_trap>
 106710c:	48 8d 3d 8d e3 01 00 	lea    0x1e38d(%rip),%rdi        # 10854a0 <core_durable_error.verbs+0x5d90>
 1067113:	ba 01 00 00 00       	mov    $0x1,%edx
 1067118:	48 89 ce             	mov    %rcx,%rsi
 106711b:	e8 e0 d5 fb ff       	call   1024700 <myl_core_trap>
 1067120:	48 be 00 00 00 00 00 	movabs $0x8000000000000000,%rsi
 1067127:	00 00 80 
 106712a:	48 8d 3d ef e7 01 00 	lea    0x1e7ef(%rip),%rdi        # 1085920 <core_durable_error.verbs+0x6210>
 1067131:	ba 01 00 00 00       	mov    $0x1,%edx
 1067136:	e8 c5 d5 fb ff       	call   1024700 <myl_core_trap>
 106713b:	48 8d 3d 0e e2 01 00 	lea    0x1e20e(%rip),%rdi        # 1085350 <core_durable_error.verbs+0x5c40>
 1067142:	e8 39 29 fc ff       	call   1029a80 <myl_core_assert_fail>
 1067147:	48 8d 3d 32 e2 01 00 	lea    0x1e232(%rip),%rdi        # 1085380 <core_durable_error.verbs+0x5c70>
 106714e:	e8 2d 29 fc ff       	call   1029a80 <myl_core_assert_fail>
 1067153:	48 8d 3d f6 e7 01 00 	lea    0x1e7f6(%rip),%rdi        # 1085950 <core_durable_error.verbs+0x6240>
 106715a:	ba 01 00 00 00       	mov    $0x1,%edx
 106715f:	48 89 c6             	mov    %rax,%rsi
 1067162:	e8 99 d5 fb ff       	call   1024700 <myl_core_trap>
 1067167:	48 8d 3d 42 ee 01 00 	lea    0x1ee42(%rip),%rdi        # 1085fb0 <core_durable_error.verbs+0x68a0>
 106716e:	ba 01 00 00 00       	mov    $0x1,%edx
 1067173:	e8 88 d5 fb ff       	call   1024700 <myl_core_trap>
 1067178:	48 8d 3d 81 e3 01 00 	lea    0x1e381(%rip),%rdi        # 1085500 <core_durable_error.verbs+0x5df0>
 106717f:	ba 01 00 00 00       	mov    $0x1,%edx
 1067184:	48 89 c6             	mov    %rax,%rsi
 1067187:	e8 74 d5 fb ff       	call   1024700 <myl_core_trap>

Disassembly of section .plt:
