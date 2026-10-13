
.tmp/lox-eda-parity/P4/atom-operands-001/candidate/lox:     file format elf64-x86-64


Disassembly of section .text:

00000000010650d0 <my.interpreter::evaluate>:
 10650d0:	55                   	push   %rbp
 10650d1:	41 57                	push   %r15
 10650d3:	41 56                	push   %r14
 10650d5:	41 55                	push   %r13
 10650d7:	41 54                	push   %r12
 10650d9:	53                   	push   %rbx
 10650da:	48 81 ec d8 06 00 00 	sub    $0x6d8,%rsp
 10650e1:	49 89 cd             	mov    %rcx,%r13
 10650e4:	48 89 d3             	mov    %rdx,%rbx
 10650e7:	48 89 f5             	mov    %rsi,%rbp
 10650ea:	49 89 fe             	mov    %rdi,%r14
 10650ed:	48 8b b4 24 30 07 00 	mov    0x730(%rsp),%rsi
 10650f4:	00 
 10650f5:	48 8b 55 08          	mov    0x8(%rbp),%rdx
 10650f9:	48 39 d6             	cmp    %rdx,%rsi
 10650fc:	0f 83 9d 17 00 00    	jae    106689f <my.interpreter::evaluate+0x17cf>
 1065102:	48 89 f0             	mov    %rsi,%rax
 1065105:	0f b6 bc 24 20 07 00 	movzbl 0x720(%rsp),%edi
 106510c:	00 
 106510d:	4c 8b bc 24 28 07 00 	mov    0x728(%rsp),%r15
 1065114:	00 
 1065115:	4c 8b 9c 24 18 07 00 	mov    0x718(%rsp),%r11
 106511c:	00 
 106511d:	48 6b c8 70          	imul   $0x70,%rax,%rcx
 1065121:	48 8d 04 29          	lea    (%rcx,%rbp,1),%rax
 1065125:	48 83 c0 20          	add    $0x20,%rax
 1065129:	8b 4c 0d 20          	mov    0x20(%rbp,%rcx,1),%ecx
 106512d:	48 83 f9 0a          	cmp    $0xa,%rcx
 1065131:	0f 87 d2 09 00 00    	ja     1065b09 <my.interpreter::evaluate+0xa39>
 1065137:	48 8b b4 24 38 07 00 	mov    0x738(%rsp),%rsi
 106513e:	00 
 106513f:	4c 8b a4 24 10 07 00 	mov    0x710(%rsp),%r12
 1065146:	00 
 1065147:	48 8d 15 2e 25 fa ff 	lea    -0x5dad2(%rip),%rdx        # 100767c <core_number_pairs+0x41c>
 106514e:	48 63 0c 8a          	movslq (%rdx,%rcx,4),%rcx
 1065152:	48 01 d1             	add    %rdx,%rcx
 1065155:	4c 89 04 24          	mov    %r8,(%rsp)
 1065159:	ff e1                	jmp    *%rcx
 106515b:	48 8b 48 20          	mov    0x20(%rax),%rcx
 106515f:	48 89 4c 24 48       	mov    %rcx,0x48(%rsp)
 1065164:	48 8b 48 30          	mov    0x30(%rax),%rcx
 1065168:	48 89 4c 24 18       	mov    %rcx,0x18(%rsp)
 106516d:	48 89 da             	mov    %rbx,%rdx
 1065170:	48 8b 58 40          	mov    0x40(%rax),%rbx
 1065174:	48 8b 48 48          	mov    0x48(%rax),%rcx
 1065178:	48 89 4c 24 28       	mov    %rcx,0x28(%rsp)
 106517d:	44 0f b6 d7          	movzbl %dil,%r10d
 1065181:	48 8d 7c 24 60       	lea    0x60(%rsp),%rdi
 1065186:	48 89 ee             	mov    %rbp,%rsi
 1065189:	4c 89 e9             	mov    %r13,%rcx
 106518c:	4d 89 cd             	mov    %r9,%r13
 106518f:	ff b4 24 38 07 00 00 	push   0x738(%rsp)
 1065196:	ff 70 38             	push   0x38(%rax)
 1065199:	41 57                	push   %r15
 106519b:	41 52                	push   %r10
 106519d:	41 53                	push   %r11
 106519f:	41 54                	push   %r12
 10651a1:	e8 2a ff ff ff       	call   10650d0 <my.interpreter::evaluate>
 10651a6:	48 83 c4 30          	add    $0x30,%rsp
 10651aa:	c5 f8 10 84 24 60 01 	vmovups 0x160(%rsp),%xmm0
 10651b1:	00 00 
 10651b3:	4c 8b a4 24 70 01 00 	mov    0x170(%rsp),%r12
 10651ba:	00 
 10651bb:	80 7c 24 60 01       	cmpb   $0x1,0x60(%rsp)
 10651c0:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 10651c5:	0f 84 fd 12 00 00    	je     10664c8 <my.interpreter::evaluate+0x13f8>
 10651cb:	48 83 fb ff          	cmp    $0xffffffffffffffff,%rbx
 10651cf:	0f 84 19 10 00 00    	je     10661ee <my.interpreter::evaluate+0x111e>
 10651d5:	49 8b b5 a8 00 00 00 	mov    0xa8(%r13),%rsi
 10651dc:	48 85 db             	test   %rbx,%rbx
 10651df:	0f 8e ba 0c 00 00    	jle    1065e9f <my.interpreter::evaluate+0xdcf>
 10651e5:	49 8b 45 00          	mov    0x0(%r13),%rax
 10651e9:	48 8b 50 08          	mov    0x8(%rax),%rdx
 10651ed:	48 83 c0 20          	add    $0x20,%rax
 10651f1:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10651f8:	0f 1f 84 00 00 00 00 
 10651ff:	00 
 1065200:	48 39 d6             	cmp    %rdx,%rsi
 1065203:	73 22                	jae    1065227 <my.interpreter::evaluate+0x157>
 1065205:	48 89 f1             	mov    %rsi,%rcx
 1065208:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 106520c:	83 3c 08 09          	cmpl   $0x9,(%rax,%rcx,1)
 1065210:	0f 85 40 1a 00 00    	jne    1066c56 <my.interpreter::evaluate+0x1b86>
 1065216:	48 01 c1             	add    %rax,%rcx
 1065219:	48 8b 71 08          	mov    0x8(%rcx),%rsi
 106521d:	48 ff cb             	dec    %rbx
 1065220:	75 de                	jne    1065200 <my.interpreter::evaluate+0x130>
 1065222:	e9 78 0c 00 00       	jmp    1065e9f <my.interpreter::evaluate+0xdcf>
 1065227:	48 89 f1             	mov    %rsi,%rcx
 106522a:	48 c1 f9 3f          	sar    $0x3f,%rcx
 106522e:	48 21 d1             	and    %rdx,%rcx
 1065231:	48 01 f1             	add    %rsi,%rcx
 1065234:	48 39 d1             	cmp    %rdx,%rcx
 1065237:	72 cf                	jb     1065208 <my.interpreter::evaluate+0x138>
 1065239:	48 8d 3d 60 07 02 00 	lea    0x20760(%rip),%rdi        # 10859a0 <core_durable_error.verbs+0x5cd0>
 1065240:	e8 bb f5 fb ff       	call   1024800 <myl_core_trap>
 1065245:	44 0f b6 d7          	movzbl %dil,%r10d
 1065249:	48 8d bc 24 e0 03 00 	lea    0x3e0(%rsp),%rdi
 1065250:	00 
 1065251:	49 89 f3             	mov    %rsi,%r11
 1065254:	48 89 ee             	mov    %rbp,%rsi
 1065257:	48 89 da             	mov    %rbx,%rdx
 106525a:	4c 89 e9             	mov    %r13,%rcx
 106525d:	41 53                	push   %r11
 106525f:	ff 70 08             	push   0x8(%rax)
 1065262:	41 57                	push   %r15
 1065264:	41 52                	push   %r10
 1065266:	ff b4 24 38 07 00 00 	push   0x738(%rsp)
 106526d:	41 54                	push   %r12
 106526f:	e8 5c fe ff ff       	call   10650d0 <my.interpreter::evaluate>
 1065274:	48 83 c4 30          	add    $0x30,%rsp
 1065278:	0f b6 84 24 e0 03 00 	movzbl 0x3e0(%rsp),%eax
 106527f:	00 
 1065280:	c5 f8 10 84 24 e8 03 	vmovups 0x3e8(%rsp),%xmm0
 1065287:	00 00 
 1065289:	48 8b 8c 24 e0 04 00 	mov    0x4e0(%rsp),%rcx
 1065290:	00 
 1065291:	0f b6 94 24 e8 04 00 	movzbl 0x4e8(%rsp),%edx
 1065298:	00 
 1065299:	48 8b b4 24 f0 04 00 	mov    0x4f0(%rsp),%rsi
 10652a0:	00 
 10652a1:	48 83 f8 01          	cmp    $0x1,%rax
 10652a5:	0f 85 df 05 00 00    	jne    106588a <my.interpreter::evaluate+0x7ba>
 10652ab:	48 8d 3d 3e db 01 00 	lea    0x1db3e(%rip),%rdi        # 1082df0 <core_durable_error.verbs+0x3120>
 10652b2:	e9 33 12 00 00       	jmp    10664ea <my.interpreter::evaluate+0x141a>
 10652b7:	48 89 fb             	mov    %rdi,%rbx
 10652ba:	48 8b 78 30          	mov    0x30(%rax),%rdi
 10652be:	49 8b 09             	mov    (%r9),%rcx
 10652c1:	49 8b b1 a8 00 00 00 	mov    0xa8(%r9),%rsi
 10652c8:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 10652cc:	48 85 ff             	test   %rdi,%rdi
 10652cf:	0f 8e b4 08 00 00    	jle    1065b89 <my.interpreter::evaluate+0xab9>
 10652d5:	4c 8d 41 20          	lea    0x20(%rcx),%r8
 10652d9:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10652e0:	0f 1f 84 00 00 00 00 
 10652e7:	00 
 10652e8:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10652ef:	0f 1f 84 00 00 00 00 
 10652f6:	00 
 10652f7:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 10652fe:	00 00 
 1065300:	48 39 d6             	cmp    %rdx,%rsi
 1065303:	73 23                	jae    1065328 <my.interpreter::evaluate+0x258>
 1065305:	49 89 f2             	mov    %rsi,%r10
 1065308:	49 6b f2 38          	imul   $0x38,%r10,%rsi
 106530c:	41 83 3c 30 09       	cmpl   $0x9,(%r8,%rsi,1)
 1065311:	0f 85 0f 19 00 00    	jne    1066c26 <my.interpreter::evaluate+0x1b56>
 1065317:	4c 01 c6             	add    %r8,%rsi
 106531a:	48 8b 76 08          	mov    0x8(%rsi),%rsi
 106531e:	48 ff cf             	dec    %rdi
 1065321:	75 dd                	jne    1065300 <my.interpreter::evaluate+0x230>
 1065323:	e9 61 08 00 00       	jmp    1065b89 <my.interpreter::evaluate+0xab9>
 1065328:	49 89 f2             	mov    %rsi,%r10
 106532b:	49 c1 fa 3f          	sar    $0x3f,%r10
 106532f:	49 21 d2             	and    %rdx,%r10
 1065332:	49 01 f2             	add    %rsi,%r10
 1065335:	49 39 d2             	cmp    %rdx,%r10
 1065338:	72 ce                	jb     1065308 <my.interpreter::evaluate+0x238>
 106533a:	48 8d 3d 5f 06 02 00 	lea    0x2065f(%rip),%rdi        # 10859a0 <core_durable_error.verbs+0x5cd0>
 1065341:	e8 ba f4 fb ff       	call   1024800 <myl_core_trap>
 1065346:	4c 89 74 24 20       	mov    %r14,0x20(%rsp)
 106534b:	48 8b 48 28          	mov    0x28(%rax),%rcx
 106534f:	48 89 4c 24 18       	mov    %rcx,0x18(%rsp)
 1065354:	4c 8b 70 38          	mov    0x38(%rax),%r14
 1065358:	44 0f b6 d7          	movzbl %dil,%r10d
 106535c:	48 8d 7c 24 60       	lea    0x60(%rsp),%rdi
 1065361:	49 89 f3             	mov    %rsi,%r11
 1065364:	48 89 ee             	mov    %rbp,%rsi
 1065367:	48 89 5c 24 30       	mov    %rbx,0x30(%rsp)
 106536c:	48 89 da             	mov    %rbx,%rdx
 106536f:	4c 89 eb             	mov    %r13,%rbx
 1065372:	4c 89 e9             	mov    %r13,%rcx
 1065375:	4d 89 cd             	mov    %r9,%r13
 1065378:	41 53                	push   %r11
 106537a:	ff 70 08             	push   0x8(%rax)
 106537d:	41 57                	push   %r15
 106537f:	41 52                	push   %r10
 1065381:	ff b4 24 38 07 00 00 	push   0x738(%rsp)
 1065388:	41 54                	push   %r12
 106538a:	e8 41 fd ff ff       	call   10650d0 <my.interpreter::evaluate>
 106538f:	48 83 c4 30          	add    $0x30,%rsp
 1065393:	48 8b 84 24 60 01 00 	mov    0x160(%rsp),%rax
 106539a:	00 
 106539b:	0f b6 8c 24 68 01 00 	movzbl 0x168(%rsp),%ecx
 10653a2:	00 
 10653a3:	4c 8b 94 24 70 01 00 	mov    0x170(%rsp),%r10
 10653aa:	00 
 10653ab:	80 7c 24 60 01       	cmpb   $0x1,0x60(%rsp)
 10653b0:	0f 84 bf 10 00 00    	je     1066475 <my.interpreter::evaluate+0x13a5>
 10653b6:	4d 8b 7e 08          	mov    0x8(%r14),%r15
 10653ba:	4d 85 ff             	test   %r15,%r15
 10653bd:	0f 84 8e 0d 00 00    	je     1066151 <my.interpreter::evaluate+0x1081>
 10653c3:	45 31 e4             	xor    %r12d,%r12d
 10653c6:	4c 8b 04 24          	mov    (%rsp),%r8
 10653ca:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10653d1:	0f 1f 84 00 00 00 00 
 10653d8:	00 
 10653d9:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10653e0:	0f 1f 84 00 00 00 00 
 10653e7:	00 
 10653e8:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 10653ef:	0f 1f 84 00 00 00 00 
 10653f6:	00 
 10653f7:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
 10653fe:	00 00 
 1065400:	44 0f b6 d9          	movzbl %cl,%r11d
 1065404:	48 8d bc 24 78 01 00 	lea    0x178(%rsp),%rdi
 106540b:	00 
 106540c:	48 89 ee             	mov    %rbp,%rsi
 106540f:	48 8b 54 24 30       	mov    0x30(%rsp),%rdx
 1065414:	48 89 d9             	mov    %rbx,%rcx
 1065417:	4d 89 e9             	mov    %r13,%r9
 106541a:	ff b4 24 38 07 00 00 	push   0x738(%rsp)
 1065421:	43 ff 74 e6 20       	push   0x20(%r14,%r12,8)
 1065426:	41 52                	push   %r10
 1065428:	41 53                	push   %r11
 106542a:	50                   	push   %rax
 106542b:	ff b4 24 38 07 00 00 	push   0x738(%rsp)
 1065432:	e8 99 fc ff ff       	call   10650d0 <my.interpreter::evaluate>
 1065437:	48 83 c4 30          	add    $0x30,%rsp
 106543b:	48 8b 84 24 78 02 00 	mov    0x278(%rsp),%rax
 1065442:	00 
 1065443:	0f b6 8c 24 80 02 00 	movzbl 0x280(%rsp),%ecx
 106544a:	00 
 106544b:	4c 8b 94 24 88 02 00 	mov    0x288(%rsp),%r10
 1065452:	00 
 1065453:	80 bc 24 78 01 00 00 	cmpb   $0x1,0x178(%rsp)
 106545a:	01 
 106545b:	0f 84 b8 11 00 00    	je     1066619 <my.interpreter::evaluate+0x1549>
 1065461:	49 ff c4             	inc    %r12
 1065464:	4d 39 e7             	cmp    %r12,%r15
 1065467:	4c 8b 04 24          	mov    (%rsp),%r8
 106546b:	75 93                	jne    1065400 <my.interpreter::evaluate+0x330>
 106546d:	4d 8b 5e 08          	mov    0x8(%r14),%r11
 1065471:	4c 8b a4 24 10 07 00 	mov    0x710(%rsp),%r12
 1065478:	00 
 1065479:	e9 da 0c 00 00       	jmp    1066158 <my.interpreter::evaluate+0x1088>
 106547e:	48 8b 48 28          	mov    0x28(%rax),%rcx
 1065482:	48 89 4c 24 28       	mov    %rcx,0x28(%rsp)
 1065487:	48 8b 48 38          	mov    0x38(%rax),%rcx
 106548b:	48 89 4c 24 18       	mov    %rcx,0x18(%rsp)
 1065490:	44 0f b6 d7          	movzbl %dil,%r10d
 1065494:	48 8d 7c 24 60       	lea    0x60(%rsp),%rdi
 1065499:	49 89 f3             	mov    %rsi,%r11
 106549c:	48 89 ee             	mov    %rbp,%rsi
 106549f:	48 89 da             	mov    %rbx,%rdx
 10654a2:	4c 89 e9             	mov    %r13,%rcx
 10654a5:	41 53                	push   %r11
 10654a7:	ff 70 08             	push   0x8(%rax)
 10654aa:	41 57                	push   %r15
 10654ac:	41 52                	push   %r10
 10654ae:	ff b4 24 38 07 00 00 	push   0x738(%rsp)
 10654b5:	41 54                	push   %r12
 10654b7:	4c 89 cb             	mov    %r9,%rbx
 10654ba:	e8 11 fc ff ff       	call   10650d0 <my.interpreter::evaluate>
 10654bf:	48 83 c4 30          	add    $0x30,%rsp
 10654c3:	c5 f8 10 84 24 60 01 	vmovups 0x160(%rsp),%xmm0
 10654ca:	00 00 
 10654cc:	4c 8b a4 24 70 01 00 	mov    0x170(%rsp),%r12
 10654d3:	00 
 10654d4:	80 7c 24 60 01       	cmpb   $0x1,0x60(%rsp)
 10654d9:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 10654de:	0f 84 a2 0f 00 00    	je     1066486 <my.interpreter::evaluate+0x13b6>
 10654e4:	48 8b 83 80 00 00 00 	mov    0x80(%rbx),%rax
 10654eb:	48 89 c6             	mov    %rax,%rsi
 10654ee:	48 ff ce             	dec    %rsi
 10654f1:	0f 80 6e 18 00 00    	jo     1066d65 <my.interpreter::evaluate+0x1c95>
 10654f7:	48 89 df             	mov    %rbx,%rdi
 10654fa:	48 8b 43 78          	mov    0x78(%rbx),%rax
 10654fe:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065502:	48 39 d6             	cmp    %rdx,%rsi
 1065505:	4c 89 74 24 20       	mov    %r14,0x20(%rsp)
 106550a:	0f 83 c5 14 00 00    	jae    10669d5 <my.interpreter::evaluate+0x1905>
 1065510:	49 89 f5             	mov    %rsi,%r13
 1065513:	49 c1 e5 04          	shl    $0x4,%r13
 1065517:	4e 8b 74 28 20       	mov    0x20(%rax,%r13,1),%r14
 106551c:	41 0f b6 ce          	movzbl %r14b,%ecx
 1065520:	83 f9 03             	cmp    $0x3,%ecx
 1065523:	0f 85 ad 0e 00 00    	jne    10663d6 <my.interpreter::evaluate+0x1306>
 1065529:	4e 8b 7c 28 28       	mov    0x28(%rax,%r13,1),%r15
 106552e:	48 8b 07             	mov    (%rdi),%rax
 1065531:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065535:	4c 89 f9             	mov    %r15,%rcx
 1065538:	49 39 d7             	cmp    %rdx,%r15
 106553b:	0f 83 1c 15 00 00    	jae    1066a5d <my.interpreter::evaluate+0x198d>
 1065541:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 1065545:	83 7c 08 20 07       	cmpl   $0x7,0x20(%rax,%rcx,1)
 106554a:	0f 85 86 0e 00 00    	jne    10663d6 <my.interpreter::evaluate+0x1306>
 1065550:	4c 89 64 24 30       	mov    %r12,0x30(%rsp)
 1065555:	48 8b 6c 24 18       	mov    0x18(%rsp),%rbp
 106555a:	48 89 ee             	mov    %rbp,%rsi
 106555d:	49 89 fc             	mov    %rdi,%r12
 1065560:	e8 bb 3a 00 00       	call   1069020 <my.heap::string_hash>
 1065565:	89 c3                	mov    %eax,%ebx
 1065567:	4c 89 e7             	mov    %r12,%rdi
 106556a:	4c 89 fe             	mov    %r15,%rsi
 106556d:	48 89 ea             	mov    %rbp,%rdx
 1065570:	89 c1                	mov    %eax,%ecx
 1065572:	e8 89 40 00 00       	call   1069600 <my.heap::instance_field>
 1065577:	3c 01                	cmp    $0x1,%al
 1065579:	0f 85 73 0a 00 00    	jne    1065ff2 <my.interpreter::evaluate+0xf22>
 106557f:	31 c0                	xor    %eax,%eax
 1065581:	49 3b 84 24 80 00 00 	cmp    0x80(%r12),%rax
 1065588:	00 
 1065589:	4c 8b 74 24 20       	mov    0x20(%rsp),%r14
 106558e:	0f 80 dd 18 00 00    	jo     1066e71 <my.interpreter::evaluate+0x1da1>
 1065594:	49 8b 44 24 78       	mov    0x78(%r12),%rax
 1065599:	4a 8d 34 28          	lea    (%rax,%r13,1),%rsi
 106559d:	48 83 c6 20          	add    $0x20,%rsi
 10655a1:	0f b6 d2             	movzbl %dl,%edx
 10655a4:	4a 89 54 28 20       	mov    %rdx,0x20(%rax,%r13,1)
 10655a9:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 10655ae:	e9 d9 0a 00 00       	jmp    106608c <my.interpreter::evaluate+0xfbc>
 10655b3:	48 8b 48 28          	mov    0x28(%rax),%rcx
 10655b7:	48 89 4c 24 48       	mov    %rcx,0x48(%rsp)
 10655bc:	48 8b 48 38          	mov    0x38(%rax),%rcx
 10655c0:	48 89 4c 24 18       	mov    %rcx,0x18(%rsp)
 10655c5:	48 89 da             	mov    %rbx,%rdx
 10655c8:	48 8b 48 40          	mov    0x40(%rax),%rcx
 10655cc:	48 89 4c 24 28       	mov    %rcx,0x28(%rsp)
 10655d1:	44 0f b6 d7          	movzbl %dil,%r10d
 10655d5:	48 8d 7c 24 60       	lea    0x60(%rsp),%rdi
 10655da:	4c 89 db             	mov    %r11,%rbx
 10655dd:	49 89 f3             	mov    %rsi,%r11
 10655e0:	48 89 ee             	mov    %rbp,%rsi
 10655e3:	48 89 54 24 30       	mov    %rdx,0x30(%rsp)
 10655e8:	4c 89 e9             	mov    %r13,%rcx
 10655eb:	41 53                	push   %r11
 10655ed:	ff 70 08             	push   0x8(%rax)
 10655f0:	41 57                	push   %r15
 10655f2:	41 52                	push   %r10
 10655f4:	53                   	push   %rbx
 10655f5:	41 54                	push   %r12
 10655f7:	4d 89 cf             	mov    %r9,%r15
 10655fa:	e8 d1 fa ff ff       	call   10650d0 <my.interpreter::evaluate>
 10655ff:	48 83 c4 30          	add    $0x30,%rsp
 1065603:	48 8b 9c 24 60 01 00 	mov    0x160(%rsp),%rbx
 106560a:	00 
 106560b:	48 8b 84 24 68 01 00 	mov    0x168(%rsp),%rax
 1065612:	00 
 1065613:	44 0f b6 d0          	movzbl %al,%r10d
 1065617:	4c 8b 9c 24 70 01 00 	mov    0x170(%rsp),%r11
 106561e:	00 
 106561f:	80 7c 24 60 01       	cmpb   $0x1,0x60(%rsp)
 1065624:	0f 84 7e 0e 00 00    	je     10664a8 <my.interpreter::evaluate+0x13d8>
 106562a:	49 8b 87 80 00 00 00 	mov    0x80(%r15),%rax
 1065631:	48 89 c6             	mov    %rax,%rsi
 1065634:	48 ff ce             	dec    %rsi
 1065637:	0f 80 3c 17 00 00    	jo     1066d79 <my.interpreter::evaluate+0x1ca9>
 106563d:	4d 89 f9             	mov    %r15,%r9
 1065640:	49 8b 47 78          	mov    0x78(%r15),%rax
 1065644:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065648:	48 39 d6             	cmp    %rdx,%rsi
 106564b:	4c 8b 04 24          	mov    (%rsp),%r8
 106564f:	0f 83 a2 13 00 00    	jae    10669f7 <my.interpreter::evaluate+0x1927>
 1065655:	48 89 f1             	mov    %rsi,%rcx
 1065658:	48 c1 e1 04          	shl    $0x4,%rcx
 106565c:	80 7c 08 20 03       	cmpb   $0x3,0x20(%rax,%rcx,1)
 1065661:	0f 85 a0 0d 00 00    	jne    1066407 <my.interpreter::evaluate+0x1337>
 1065667:	48 8b 74 08 28       	mov    0x28(%rax,%rcx,1),%rsi
 106566c:	49 8b 01             	mov    (%r9),%rax
 106566f:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065673:	48 39 d6             	cmp    %rdx,%rsi
 1065676:	0f 83 06 14 00 00    	jae    1066a82 <my.interpreter::evaluate+0x19b2>
 106567c:	48 89 f1             	mov    %rsi,%rcx
 106567f:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 1065683:	83 7c 08 20 07       	cmpl   $0x7,0x20(%rax,%rcx,1)
 1065688:	0f 85 79 0d 00 00    	jne    1066407 <my.interpreter::evaluate+0x1337>
 106568e:	48 8d bc 24 78 01 00 	lea    0x178(%rsp),%rdi
 1065695:	00 
 1065696:	48 89 ee             	mov    %rbp,%rsi
 1065699:	48 8b 54 24 30       	mov    0x30(%rsp),%rdx
 106569e:	4c 89 e9             	mov    %r13,%rcx
 10656a1:	ff b4 24 38 07 00 00 	push   0x738(%rsp)
 10656a8:	ff 74 24 30          	push   0x30(%rsp)
 10656ac:	41 53                	push   %r11
 10656ae:	41 52                	push   %r10
 10656b0:	53                   	push   %rbx
 10656b1:	41 54                	push   %r12
 10656b3:	4c 89 cb             	mov    %r9,%rbx
 10656b6:	e8 15 fa ff ff       	call   10650d0 <my.interpreter::evaluate>
 10656bb:	48 83 c4 30          	add    $0x30,%rsp
 10656bf:	48 8b 84 24 78 02 00 	mov    0x278(%rsp),%rax
 10656c6:	00 
 10656c7:	48 89 04 24          	mov    %rax,(%rsp)
 10656cb:	44 0f b6 94 24 80 02 	movzbl 0x280(%rsp),%r10d
 10656d2:	00 00 
 10656d4:	4c 8b a4 24 88 02 00 	mov    0x288(%rsp),%r12
 10656db:	00 
 10656dc:	80 bc 24 78 01 00 00 	cmpb   $0x1,0x178(%rsp)
 10656e3:	01 
 10656e4:	0f 84 d3 0e 00 00    	je     10665bd <my.interpreter::evaluate+0x14ed>
 10656ea:	48 8b b3 80 00 00 00 	mov    0x80(%rbx),%rsi
 10656f1:	48 89 f0             	mov    %rsi,%rax
 10656f4:	48 ff c8             	dec    %rax
 10656f7:	0f 80 cd 16 00 00    	jo     1066dca <my.interpreter::evaluate+0x1cfa>
 10656fd:	48 89 c6             	mov    %rax,%rsi
 1065700:	48 ff ce             	dec    %rsi
 1065703:	0f 80 d2 16 00 00    	jo     1066ddb <my.interpreter::evaluate+0x1d0b>
 1065709:	48 89 df             	mov    %rbx,%rdi
 106570c:	48 8b 43 78          	mov    0x78(%rbx),%rax
 1065710:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065714:	48 39 d6             	cmp    %rdx,%rsi
 1065717:	0f 83 87 13 00 00    	jae    1066aa4 <my.interpreter::evaluate+0x19d4>
 106571d:	48 89 f1             	mov    %rsi,%rcx
 1065720:	4c 89 64 24 30       	mov    %r12,0x30(%rsp)
 1065725:	48 c1 e1 04          	shl    $0x4,%rcx
 1065729:	0f b6 54 08 20       	movzbl 0x20(%rax,%rcx,1),%edx
 106572e:	83 fa 03             	cmp    $0x3,%edx
 1065731:	0f 85 6b 15 00 00    	jne    1066ca2 <my.interpreter::evaluate+0x1bd2>
 1065737:	4c 89 d5             	mov    %r10,%rbp
 106573a:	48 8b 5c 08 28       	mov    0x28(%rax,%rcx,1),%rbx
 106573f:	48 8b 74 24 18       	mov    0x18(%rsp),%rsi
 1065744:	49 89 fd             	mov    %rdi,%r13
 1065747:	e8 d4 38 00 00       	call   1069020 <my.heap::string_hash>
 106574c:	49 8b 8d 80 00 00 00 	mov    0x80(%r13),%rcx
 1065753:	48 89 ce             	mov    %rcx,%rsi
 1065756:	48 ff ce             	dec    %rsi
 1065759:	0f 80 a8 16 00 00    	jo     1066e07 <my.interpreter::evaluate+0x1d37>
 106575f:	4c 89 ef             	mov    %r13,%rdi
 1065762:	49 8b 4d 78          	mov    0x78(%r13),%rcx
 1065766:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 106576a:	48 39 d6             	cmp    %rdx,%rsi
 106576d:	0f 83 53 13 00 00    	jae    1066ac6 <my.interpreter::evaluate+0x19f6>
 1065773:	49 89 f0             	mov    %rsi,%r8
 1065776:	49 c1 e0 04          	shl    $0x4,%r8
 106577a:	46 0f b6 7c 01 20    	movzbl 0x20(%rcx,%r8,1),%r15d
 1065780:	4e 8b 64 01 28       	mov    0x28(%rcx,%r8,1),%r12
 1065785:	48 89 de             	mov    %rbx,%rsi
 1065788:	48 8b 54 24 18       	mov    0x18(%rsp),%rdx
 106578d:	89 c1                	mov    %eax,%ecx
 106578f:	45 89 f8             	mov    %r15d,%r8d
 1065792:	4d 89 e1             	mov    %r12,%r9
 1065795:	e8 36 40 00 00       	call   10697d0 <my.heap::set_instance_field>
 106579a:	49 8b 85 80 00 00 00 	mov    0x80(%r13),%rax
 10657a1:	48 89 c6             	mov    %rax,%rsi
 10657a4:	48 ff ce             	dec    %rsi
 10657a7:	0f 80 6e 16 00 00    	jo     1066e1b <my.interpreter::evaluate+0x1d4b>
 10657ad:	4c 89 ef             	mov    %r13,%rdi
 10657b0:	49 89 b5 80 00 00 00 	mov    %rsi,0x80(%r13)
 10657b7:	49 8b 4d 78          	mov    0x78(%r13),%rcx
 10657bb:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 10657bf:	48 39 d6             	cmp    %rdx,%rsi
 10657c2:	48 8b 1c 24          	mov    (%rsp),%rbx
 10657c6:	49 89 ea             	mov    %rbp,%r10
 10657c9:	4c 8b 44 24 30       	mov    0x30(%rsp),%r8
 10657ce:	0f 83 14 13 00 00    	jae    1066ae8 <my.interpreter::evaluate+0x1a18>
 10657d4:	48 89 f0             	mov    %rsi,%rax
 10657d7:	48 ff c8             	dec    %rax
 10657da:	0f 80 4f 16 00 00    	jo     1066e2f <my.interpreter::evaluate+0x1d5f>
 10657e0:	48 39 d0             	cmp    %rdx,%rax
 10657e3:	0f 83 21 13 00 00    	jae    1066b0a <my.interpreter::evaluate+0x1a3a>
 10657e9:	48 89 c6             	mov    %rax,%rsi
 10657ec:	48 c1 e6 04          	shl    $0x4,%rsi
 10657f0:	4c 89 7c 31 20       	mov    %r15,0x20(%rcx,%rsi,1)
 10657f5:	4c 89 64 31 28       	mov    %r12,0x28(%rcx,%rsi,1)
 10657fa:	48 89 4f 78          	mov    %rcx,0x78(%rdi)
 10657fe:	31 c0                	xor    %eax,%eax
 1065800:	e9 f1 0d 00 00       	jmp    10665f6 <my.interpreter::evaluate+0x1526>
 1065805:	c5 fc 10 40 08       	vmovups 0x8(%rax),%ymm0
 106580a:	c5 fe 6f 48 20       	vmovdqu 0x20(%rax),%ymm1
 106580f:	c5 fe 7f 8c 24 a8 02 	vmovdqu %ymm1,0x2a8(%rsp)
 1065816:	00 00 
 1065818:	c5 fc 11 84 24 90 02 	vmovups %ymm0,0x290(%rsp)
 106581f:	00 00 
 1065821:	44 0f b6 d7          	movzbl %dil,%r10d
 1065825:	48 8d bc 24 f8 04 00 	lea    0x4f8(%rsp),%rdi
 106582c:	00 
 106582d:	48 89 f0             	mov    %rsi,%rax
 1065830:	48 89 ee             	mov    %rbp,%rsi
 1065833:	48 89 da             	mov    %rbx,%rdx
 1065836:	4c 89 e9             	mov    %r13,%rcx
 1065839:	50                   	push   %rax
 106583a:	48 8d 84 24 98 02 00 	lea    0x298(%rsp),%rax
 1065841:	00 
 1065842:	50                   	push   %rax
 1065843:	41 57                	push   %r15
 1065845:	41 52                	push   %r10
 1065847:	41 53                	push   %r11
 1065849:	41 54                	push   %r12
 106584b:	c5 f8 77             	vzeroupper
 106584e:	e8 1d 63 00 00       	call   106bb70 <my.interpreter::binary>
 1065853:	48 83 c4 30          	add    $0x30,%rsp
 1065857:	0f b6 84 24 f8 04 00 	movzbl 0x4f8(%rsp),%eax
 106585e:	00 
 106585f:	c5 f8 10 84 24 00 05 	vmovups 0x500(%rsp),%xmm0
 1065866:	00 00 
 1065868:	48 8b 8c 24 f8 05 00 	mov    0x5f8(%rsp),%rcx
 106586f:	00 
 1065870:	0f b6 94 24 00 06 00 	movzbl 0x600(%rsp),%edx
 1065877:	00 
 1065878:	48 8b b4 24 08 06 00 	mov    0x608(%rsp),%rsi
 106587f:	00 
 1065880:	48 83 f8 01          	cmp    $0x1,%rax
 1065884:	0f 84 59 0c 00 00    	je     10664e3 <my.interpreter::evaluate+0x1413>
 106588a:	49 89 06             	mov    %rax,(%r14)
 106588d:	c4 c1 78 11 46 08    	vmovups %xmm0,0x8(%r14)
 1065893:	49 89 8e 00 01 00 00 	mov    %rcx,0x100(%r14)
 106589a:	49 89 96 08 01 00 00 	mov    %rdx,0x108(%r14)
 10658a1:	49 89 b6 10 01 00 00 	mov    %rsi,0x110(%r14)
 10658a8:	e9 b1 0f 00 00       	jmp    106685e <my.interpreter::evaluate+0x178e>
 10658ad:	c5 f8 10 40 08       	vmovups 0x8(%rax),%xmm0
 10658b2:	49 8b 41 78          	mov    0x78(%r9),%rax
 10658b6:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 10658bd:	48 8b 50 08          	mov    0x8(%rax),%rdx
 10658c1:	48 39 d6             	cmp    %rdx,%rsi
 10658c4:	0f 83 f7 0f 00 00    	jae    10668c1 <my.interpreter::evaluate+0x17f1>
 10658ca:	48 89 f1             	mov    %rsi,%rcx
 10658cd:	c5 f8 54 05 0b eb f9 	vandps -0x614f5(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 10658d4:	ff 
 10658d5:	48 c1 e1 04          	shl    $0x4,%rcx
 10658d9:	c5 f8 11 44 08 20    	vmovups %xmm0,0x20(%rax,%rcx,1)
 10658df:	49 89 41 78          	mov    %rax,0x78(%r9)
 10658e3:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 10658ea:	48 89 f0             	mov    %rsi,%rax
 10658ed:	48 ff c0             	inc    %rax
 10658f0:	0f 80 e9 13 00 00    	jo     1066cdf <my.interpreter::evaluate+0x1c0f>
 10658f6:	49 89 81 80 00 00 00 	mov    %rax,0x80(%r9)
 10658fd:	49 c7 06 00 00 00 00 	movq   $0x0,(%r14)
 1065904:	4d 89 9e 00 01 00 00 	mov    %r11,0x100(%r14)
 106590b:	40 0f b6 c7          	movzbl %dil,%eax
 106590f:	49 89 86 08 01 00 00 	mov    %rax,0x108(%r14)
 1065916:	e9 af 0a 00 00       	jmp    10663ca <my.interpreter::evaluate+0x12fa>
 106591b:	4c 89 7c 24 18       	mov    %r15,0x18(%rsp)
 1065920:	4c 89 5c 24 28       	mov    %r11,0x28(%rsp)
 1065925:	4c 89 74 24 20       	mov    %r14,0x20(%rsp)
 106592a:	4c 8b 70 08          	mov    0x8(%rax),%r14
 106592e:	48 8b 48 38          	mov    0x38(%rax),%rcx
 1065932:	48 89 4c 24 50       	mov    %rcx,0x50(%rsp)
 1065937:	0f b6 40 10          	movzbl 0x10(%rax),%eax
 106593b:	48 89 44 24 48       	mov    %rax,0x48(%rsp)
 1065940:	48 83 ec 08          	sub    $0x8,%rsp
 1065944:	48 8d bc 24 d0 02 00 	lea    0x2d0(%rsp),%rdi
 106594b:	00 
 106594c:	48 89 ee             	mov    %rbp,%rsi
 106594f:	48 89 da             	mov    %rbx,%rdx
 1065952:	4c 89 e9             	mov    %r13,%rcx
 1065955:	4d 89 c7             	mov    %r8,%r15
 1065958:	41 56                	push   %r14
 106595a:	4d 89 cc             	mov    %r9,%r12
 106595d:	e8 1e 9e 00 00       	call   106f780 <my.interpreter::try_push_atom>
 1065962:	48 83 c4 10          	add    $0x10,%rsp
 1065966:	f6 84 24 c8 02 00 00 	testb  $0x1,0x2c8(%rsp)
 106596d:	01 
 106596e:	4c 89 6c 24 58       	mov    %r13,0x58(%rsp)
 1065973:	48 89 5c 24 30       	mov    %rbx,0x30(%rsp)
 1065978:	0f 84 68 05 00 00    	je     1065ee6 <my.interpreter::evaluate+0xe16>
 106597e:	0f b6 bc 24 20 07 00 	movzbl 0x720(%rsp),%edi
 1065985:	00 
 1065986:	4d 89 e5             	mov    %r12,%r13
 1065989:	e9 cf 05 00 00       	jmp    1065f5d <my.interpreter::evaluate+0xe8d>
 106598e:	48 89 da             	mov    %rbx,%rdx
 1065991:	4c 89 74 24 20       	mov    %r14,0x20(%rsp)
 1065996:	44 0f b6 70 08       	movzbl 0x8(%rax),%r14d
 106599b:	48 8b 48 20          	mov    0x20(%rax),%rcx
 106599f:	48 89 0c 24          	mov    %rcx,(%rsp)
 10659a3:	44 0f b6 d7          	movzbl %dil,%r10d
 10659a7:	48 8d 7c 24 60       	lea    0x60(%rsp),%rdi
 10659ac:	4c 89 db             	mov    %r11,%rbx
 10659af:	49 89 f3             	mov    %rsi,%r11
 10659b2:	48 89 ee             	mov    %rbp,%rsi
 10659b5:	4c 89 e9             	mov    %r13,%rcx
 10659b8:	41 53                	push   %r11
 10659ba:	ff 70 30             	push   0x30(%rax)
 10659bd:	41 57                	push   %r15
 10659bf:	41 52                	push   %r10
 10659c1:	53                   	push   %rbx
 10659c2:	41 54                	push   %r12
 10659c4:	4d 89 cd             	mov    %r9,%r13
 10659c7:	e8 04 f7 ff ff       	call   10650d0 <my.interpreter::evaluate>
 10659cc:	48 83 c4 30          	add    $0x30,%rsp
 10659d0:	c5 f8 10 84 24 60 01 	vmovups 0x160(%rsp),%xmm0
 10659d7:	00 00 
 10659d9:	4c 8b bc 24 70 01 00 	mov    0x170(%rsp),%r15
 10659e0:	00 
 10659e1:	80 7c 24 60 01       	cmpb   $0x1,0x60(%rsp)
 10659e6:	0f 84 12 0b 00 00    	je     10664fe <my.interpreter::evaluate+0x142e>
 10659ec:	49 8b 85 80 00 00 00 	mov    0x80(%r13),%rax
 10659f3:	48 89 c6             	mov    %rax,%rsi
 10659f6:	48 ff ce             	dec    %rsi
 10659f9:	0f 80 8e 13 00 00    	jo     1066d8d <my.interpreter::evaluate+0x1cbd>
 10659ff:	4d 89 e8             	mov    %r13,%r8
 1065a02:	49 8b 45 78          	mov    0x78(%r13),%rax
 1065a06:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065a0a:	48 39 d6             	cmp    %rdx,%rsi
 1065a0d:	0f 83 06 10 00 00    	jae    1066a19 <my.interpreter::evaluate+0x1949>
 1065a13:	48 89 f7             	mov    %rsi,%rdi
 1065a16:	48 c1 e7 04          	shl    $0x4,%rdi
 1065a1a:	48 8d 0c 38          	lea    (%rax,%rdi,1),%rcx
 1065a1e:	48 83 c1 20          	add    $0x20,%rcx
 1065a22:	0f b6 74 38 20       	movzbl 0x20(%rax,%rdi,1),%esi
 1065a27:	48 8b 54 38 28       	mov    0x28(%rax,%rdi,1),%rdx
 1065a2c:	41 83 fe 0b          	cmp    $0xb,%r14d
 1065a30:	0f 85 90 05 00 00    	jne    1065fc6 <my.interpreter::evaluate+0xef6>
 1065a36:	40 84 f6             	test   %sil,%sil
 1065a39:	4c 8b 74 24 20       	mov    0x20(%rsp),%r14
 1065a3e:	0f 84 54 09 00 00    	je     1066398 <my.interpreter::evaluate+0x12c8>
 1065a44:	40 0f b6 f6          	movzbl %sil,%esi
 1065a48:	83 fe 01             	cmp    $0x1,%esi
 1065a4b:	0f 85 4b 09 00 00    	jne    106639c <my.interpreter::evaluate+0x12cc>
 1065a51:	f6 d2                	not    %dl
 1065a53:	80 e2 01             	and    $0x1,%dl
 1065a56:	e9 43 09 00 00       	jmp    106639e <my.interpreter::evaluate+0x12ce>
 1065a5b:	48 8b 58 48          	mov    0x48(%rax),%rbx
 1065a5f:	4c 8b 78 58          	mov    0x58(%rax),%r15
 1065a63:	48 8b 40 60          	mov    0x60(%rax),%rax
 1065a67:	49 8b 39             	mov    (%r9),%rdi
 1065a6a:	49 8b b1 a8 00 00 00 	mov    0xa8(%r9),%rsi
 1065a71:	48 8b 57 08          	mov    0x8(%rdi),%rdx
 1065a75:	48 89 f1             	mov    %rsi,%rcx
 1065a78:	48 85 c0             	test   %rax,%rax
 1065a7b:	0f 8e b4 01 00 00    	jle    1065c35 <my.interpreter::evaluate+0xb65>
 1065a81:	4c 8d 47 20          	lea    0x20(%rdi),%r8
 1065a85:	49 89 c3             	mov    %rax,%r11
 1065a88:	48 89 f1             	mov    %rsi,%rcx
 1065a8b:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1065a92:	0f 1f 84 00 00 00 00 
 1065a99:	00 
 1065a9a:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1065aa1:	0f 1f 84 00 00 00 00 
 1065aa8:	00 
 1065aa9:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1065ab0:	0f 1f 84 00 00 00 00 
 1065ab7:	00 
 1065ab8:	0f 1f 84 00 00 00 00 	nopl   0x0(%rax,%rax,1)
 1065abf:	00 
 1065ac0:	48 39 d1             	cmp    %rdx,%rcx
 1065ac3:	73 23                	jae    1065ae8 <my.interpreter::evaluate+0xa18>
 1065ac5:	49 89 ca             	mov    %rcx,%r10
 1065ac8:	49 6b ca 38          	imul   $0x38,%r10,%rcx
 1065acc:	41 83 3c 08 09       	cmpl   $0x9,(%r8,%rcx,1)
 1065ad1:	0f 85 5b 11 00 00    	jne    1066c32 <my.interpreter::evaluate+0x1b62>
 1065ad7:	4c 01 c1             	add    %r8,%rcx
 1065ada:	48 8b 49 08          	mov    0x8(%rcx),%rcx
 1065ade:	49 ff cb             	dec    %r11
 1065ae1:	75 dd                	jne    1065ac0 <my.interpreter::evaluate+0x9f0>
 1065ae3:	e9 4d 01 00 00       	jmp    1065c35 <my.interpreter::evaluate+0xb65>
 1065ae8:	49 89 ca             	mov    %rcx,%r10
 1065aeb:	49 c1 fa 3f          	sar    $0x3f,%r10
 1065aef:	49 21 d2             	and    %rdx,%r10
 1065af2:	49 01 ca             	add    %rcx,%r10
 1065af5:	49 39 d2             	cmp    %rdx,%r10
 1065af8:	72 ce                	jb     1065ac8 <my.interpreter::evaluate+0x9f8>
 1065afa:	48 8d 3d 9f fe 01 00 	lea    0x1fe9f(%rip),%rdi        # 10859a0 <core_durable_error.verbs+0x5cd0>
 1065b01:	48 89 ce             	mov    %rcx,%rsi
 1065b04:	e8 f7 ec fb ff       	call   1024800 <myl_core_trap>
 1065b09:	48 8b 78 38          	mov    0x38(%rax),%rdi
 1065b0d:	48 83 ff ff          	cmp    $0xffffffffffffffff,%rdi
 1065b11:	0f 84 8a 05 00 00    	je     10660a1 <my.interpreter::evaluate+0xfd1>
 1065b17:	48 8b 70 40          	mov    0x40(%rax),%rsi
 1065b1b:	49 8b 09             	mov    (%r9),%rcx
 1065b1e:	49 8b 81 a8 00 00 00 	mov    0xa8(%r9),%rax
 1065b25:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 1065b29:	48 85 ff             	test   %rdi,%rdi
 1065b2c:	0f 8e e8 02 00 00    	jle    1065e1a <my.interpreter::evaluate+0xd4a>
 1065b32:	4c 8d 41 20          	lea    0x20(%rcx),%r8
 1065b36:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 1065b3d:	00 00 00 
 1065b40:	48 39 d0             	cmp    %rdx,%rax
 1065b43:	73 23                	jae    1065b68 <my.interpreter::evaluate+0xa98>
 1065b45:	49 89 c2             	mov    %rax,%r10
 1065b48:	49 6b c2 38          	imul   $0x38,%r10,%rax
 1065b4c:	41 83 3c 00 09       	cmpl   $0x9,(%r8,%rax,1)
 1065b51:	0f 85 f3 10 00 00    	jne    1066c4a <my.interpreter::evaluate+0x1b7a>
 1065b57:	4c 01 c0             	add    %r8,%rax
 1065b5a:	48 8b 40 08          	mov    0x8(%rax),%rax
 1065b5e:	48 ff cf             	dec    %rdi
 1065b61:	75 dd                	jne    1065b40 <my.interpreter::evaluate+0xa70>
 1065b63:	e9 b2 02 00 00       	jmp    1065e1a <my.interpreter::evaluate+0xd4a>
 1065b68:	49 89 c2             	mov    %rax,%r10
 1065b6b:	49 c1 fa 3f          	sar    $0x3f,%r10
 1065b6f:	49 21 d2             	and    %rdx,%r10
 1065b72:	49 01 c2             	add    %rax,%r10
 1065b75:	49 39 d2             	cmp    %rdx,%r10
 1065b78:	72 ce                	jb     1065b48 <my.interpreter::evaluate+0xa78>
 1065b7a:	48 8d 3d 1f fe 01 00 	lea    0x1fe1f(%rip),%rdi        # 10859a0 <core_durable_error.verbs+0x5cd0>
 1065b81:	48 89 c6             	mov    %rax,%rsi
 1065b84:	e8 77 ec fb ff       	call   1024800 <myl_core_trap>
 1065b89:	48 8b 40 38          	mov    0x38(%rax),%rax
 1065b8d:	48 39 d6             	cmp    %rdx,%rsi
 1065b90:	0f 83 4d 0d 00 00    	jae    10668e3 <my.interpreter::evaluate+0x1813>
 1065b96:	48 89 f7             	mov    %rsi,%rdi
 1065b99:	48 6b d7 38          	imul   $0x38,%rdi,%rdx
 1065b9d:	83 7c 11 20 09       	cmpl   $0x9,0x20(%rcx,%rdx,1)
 1065ba2:	0f 85 48 11 00 00    	jne    1066cf0 <my.interpreter::evaluate+0x1c20>
 1065ba8:	48 01 d1             	add    %rdx,%rcx
 1065bab:	48 83 c1 20          	add    $0x20,%rcx
 1065baf:	48 8b 49 10          	mov    0x10(%rcx),%rcx
 1065bb3:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 1065bb7:	48 39 d0             	cmp    %rdx,%rax
 1065bba:	0f 83 6a 0d 00 00    	jae    106692a <my.interpreter::evaluate+0x185a>
 1065bc0:	48 89 c6             	mov    %rax,%rsi
 1065bc3:	48 c1 e6 04          	shl    $0x4,%rsi
 1065bc7:	c5 f8 10 44 31 20    	vmovups 0x20(%rcx,%rsi,1),%xmm0
 1065bcd:	49 8b 41 78          	mov    0x78(%r9),%rax
 1065bd1:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 1065bd8:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065bdc:	48 39 d6             	cmp    %rdx,%rsi
 1065bdf:	0f 83 6a 0d 00 00    	jae    106694f <my.interpreter::evaluate+0x187f>
 1065be5:	48 89 f1             	mov    %rsi,%rcx
 1065be8:	c5 f8 54 05 f0 e7 f9 	vandps -0x61810(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 1065bef:	ff 
 1065bf0:	48 c1 e1 04          	shl    $0x4,%rcx
 1065bf4:	c5 f8 11 44 08 20    	vmovups %xmm0,0x20(%rax,%rcx,1)
 1065bfa:	49 89 41 78          	mov    %rax,0x78(%r9)
 1065bfe:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 1065c05:	48 89 f0             	mov    %rsi,%rax
 1065c08:	48 ff c0             	inc    %rax
 1065c0b:	0f 80 f7 10 00 00    	jo     1066d08 <my.interpreter::evaluate+0x1c38>
 1065c11:	49 89 81 80 00 00 00 	mov    %rax,0x80(%r9)
 1065c18:	49 c7 06 00 00 00 00 	movq   $0x0,(%r14)
 1065c1f:	4d 89 9e 00 01 00 00 	mov    %r11,0x100(%r14)
 1065c26:	0f b6 c3             	movzbl %bl,%eax
 1065c29:	49 89 86 08 01 00 00 	mov    %rax,0x108(%r14)
 1065c30:	e9 95 07 00 00       	jmp    10663ca <my.interpreter::evaluate+0x12fa>
 1065c35:	48 39 d1             	cmp    %rdx,%rcx
 1065c38:	0f 83 c7 0c 00 00    	jae    1066905 <my.interpreter::evaluate+0x1835>
 1065c3e:	49 89 c8             	mov    %rcx,%r8
 1065c41:	49 6b c8 38          	imul   $0x38,%r8,%rcx
 1065c45:	83 7c 0f 20 09       	cmpl   $0x9,0x20(%rdi,%rcx,1)
 1065c4a:	0f 85 ac 10 00 00    	jne    1066cfc <my.interpreter::evaluate+0x1c2c>
 1065c50:	48 01 f9             	add    %rdi,%rcx
 1065c53:	48 83 c1 20          	add    $0x20,%rcx
 1065c57:	4c 8b 41 10          	mov    0x10(%rcx),%r8
 1065c5b:	49 83 78 08 00       	cmpq   $0x0,0x8(%r8)
 1065c60:	0f 84 0b 0d 00 00    	je     1066971 <my.interpreter::evaluate+0x18a1>
 1065c66:	48 89 c1             	mov    %rax,%rcx
 1065c69:	48 ff c9             	dec    %rcx
 1065c6c:	0f 80 a7 10 00 00    	jo     1066d19 <my.interpreter::evaluate+0x1c49>
 1065c72:	48 83 c7 20          	add    $0x20,%rdi
 1065c76:	41 0f b6 40 20       	movzbl 0x20(%r8),%eax
 1065c7b:	4d 8b 60 28          	mov    0x28(%r8),%r12
 1065c7f:	48 85 c9             	test   %rcx,%rcx
 1065c82:	7e 7e                	jle    1065d02 <my.interpreter::evaluate+0xc32>
 1065c84:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1065c8b:	0f 1f 84 00 00 00 00 
 1065c92:	00 
 1065c93:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1065c9a:	0f 1f 84 00 00 00 00 
 1065ca1:	00 
 1065ca2:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1065ca9:	0f 1f 84 00 00 00 00 
 1065cb0:	00 
 1065cb1:	66 66 66 66 66 66 2e 	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1065cb8:	0f 1f 84 00 00 00 00 
 1065cbf:	00 
 1065cc0:	48 39 d6             	cmp    %rdx,%rsi
 1065cc3:	73 1f                	jae    1065ce4 <my.interpreter::evaluate+0xc14>
 1065cc5:	49 89 f0             	mov    %rsi,%r8
 1065cc8:	49 6b f0 38          	imul   $0x38,%r8,%rsi
 1065ccc:	83 3c 37 09          	cmpl   $0x9,(%rdi,%rsi,1)
 1065cd0:	0f 85 68 0f 00 00    	jne    1066c3e <my.interpreter::evaluate+0x1b6e>
 1065cd6:	48 01 fe             	add    %rdi,%rsi
 1065cd9:	48 8b 76 08          	mov    0x8(%rsi),%rsi
 1065cdd:	48 ff c9             	dec    %rcx
 1065ce0:	75 de                	jne    1065cc0 <my.interpreter::evaluate+0xbf0>
 1065ce2:	eb 1e                	jmp    1065d02 <my.interpreter::evaluate+0xc32>
 1065ce4:	49 89 f0             	mov    %rsi,%r8
 1065ce7:	49 c1 f8 3f          	sar    $0x3f,%r8
 1065ceb:	49 21 d0             	and    %rdx,%r8
 1065cee:	49 01 f0             	add    %rsi,%r8
 1065cf1:	49 39 d0             	cmp    %rdx,%r8
 1065cf4:	72 d2                	jb     1065cc8 <my.interpreter::evaluate+0xbf8>
 1065cf6:	48 8d 3d a3 fc 01 00 	lea    0x1fca3(%rip),%rdi        # 10859a0 <core_durable_error.verbs+0x5cd0>
 1065cfd:	e8 fe ea fb ff       	call   1024800 <myl_core_trap>
 1065d02:	48 39 d6             	cmp    %rdx,%rsi
 1065d05:	0f 83 76 0c 00 00    	jae    1066981 <my.interpreter::evaluate+0x18b1>
 1065d0b:	48 89 f1             	mov    %rsi,%rcx
 1065d0e:	48 6b c9 38          	imul   $0x38,%rcx,%rcx
 1065d12:	83 3c 0f 09          	cmpl   $0x9,(%rdi,%rcx,1)
 1065d16:	0f 85 11 10 00 00    	jne    1066d2d <my.interpreter::evaluate+0x1c5d>
 1065d1c:	48 01 cf             	add    %rcx,%rdi
 1065d1f:	48 8b 4f 10          	mov    0x10(%rdi),%rcx
 1065d23:	48 83 79 08 00       	cmpq   $0x0,0x8(%rcx)
 1065d28:	0f 84 75 0c 00 00    	je     10669a3 <my.interpreter::evaluate+0x18d3>
 1065d2e:	48 89 5c 24 30       	mov    %rbx,0x30(%rsp)
 1065d33:	3c 03                	cmp    $0x3,%al
 1065d35:	0f 85 27 0f 00 00    	jne    1066c62 <my.interpreter::evaluate+0x1b92>
 1065d3b:	0f b6 69 20          	movzbl 0x20(%rcx),%ebp
 1065d3f:	48 8b 41 28          	mov    0x28(%rcx),%rax
 1065d43:	48 89 04 24          	mov    %rax,(%rsp)
 1065d47:	4c 89 cf             	mov    %r9,%rdi
 1065d4a:	4c 89 fe             	mov    %r15,%rsi
 1065d4d:	4d 89 cd             	mov    %r9,%r13
 1065d50:	e8 cb 32 00 00       	call   1069020 <my.heap::string_hash>
 1065d55:	4c 89 eb             	mov    %r13,%rbx
 1065d58:	4c 89 ef             	mov    %r13,%rdi
 1065d5b:	4c 89 e6             	mov    %r12,%rsi
 1065d5e:	4c 89 fa             	mov    %r15,%rdx
 1065d61:	89 c1                	mov    %eax,%ecx
 1065d63:	e8 78 3b 00 00       	call   10698e0 <my.heap::class_method>
 1065d68:	3c 01                	cmp    $0x1,%al
 1065d6a:	0f 85 b4 07 00 00    	jne    1066524 <my.interpreter::evaluate+0x1454>
 1065d70:	80 fa 03             	cmp    $0x3,%dl
 1065d73:	44 0f b6 a4 24 20 07 	movzbl 0x720(%rsp),%r12d
 1065d7a:	00 00 
 1065d7c:	0f 85 00 0f 00 00    	jne    1066c82 <my.interpreter::evaluate+0x1bb2>
 1065d82:	49 89 c8             	mov    %rcx,%r8
 1065d85:	40 0f b6 d5          	movzbl %bpl,%edx
 1065d89:	48 8d 7c 24 60       	lea    0x60(%rsp),%rdi
 1065d8e:	48 89 de             	mov    %rbx,%rsi
 1065d91:	48 8b 0c 24          	mov    (%rsp),%rcx
 1065d95:	e8 c6 a9 00 00       	call   1070760 <my.interpreter::bind>
 1065d9a:	48 8b 44 24 60       	mov    0x60(%rsp),%rax
 1065d9f:	48 8b 4b 78          	mov    0x78(%rbx),%rcx
 1065da3:	48 8b b3 80 00 00 00 	mov    0x80(%rbx),%rsi
 1065daa:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 1065dae:	48 89 f7             	mov    %rsi,%rdi
 1065db1:	48 39 d6             	cmp    %rdx,%rsi
 1065db4:	0f 83 81 0c 00 00    	jae    1066a3b <my.interpreter::evaluate+0x196b>
 1065dba:	48 c1 e7 04          	shl    $0x4,%rdi
 1065dbe:	48 c7 44 39 20 03 00 	movq   $0x3,0x20(%rcx,%rdi,1)
 1065dc5:	00 00 
 1065dc7:	48 89 44 39 28       	mov    %rax,0x28(%rcx,%rdi,1)
 1065dcc:	48 89 f0             	mov    %rsi,%rax
 1065dcf:	48 ff c0             	inc    %rax
 1065dd2:	0f 80 e1 0f 00 00    	jo     1066db9 <my.interpreter::evaluate+0x1ce9>
 1065dd8:	48 89 83 80 00 00 00 	mov    %rax,0x80(%rbx)
 1065ddf:	31 c0                	xor    %eax,%eax
 1065de1:	49 89 06             	mov    %rax,(%r14)
 1065de4:	49 89 5e 08          	mov    %rbx,0x8(%r14)
 1065de8:	49 89 4e 10          	mov    %rcx,0x10(%r14)
 1065dec:	48 8b 84 24 18 07 00 	mov    0x718(%rsp),%rax
 1065df3:	00 
 1065df4:	49 89 86 00 01 00 00 	mov    %rax,0x100(%r14)
 1065dfb:	41 0f b6 c4          	movzbl %r12b,%eax
 1065dff:	49 89 86 08 01 00 00 	mov    %rax,0x108(%r14)
 1065e06:	48 8b 84 24 28 07 00 	mov    0x728(%rsp),%rax
 1065e0d:	00 
 1065e0e:	49 89 86 10 01 00 00 	mov    %rax,0x110(%r14)
 1065e15:	e9 44 0a 00 00       	jmp    106685e <my.interpreter::evaluate+0x178e>
 1065e1a:	48 39 d0             	cmp    %rdx,%rax
 1065e1d:	0f 83 0c 0d 00 00    	jae    1066b2f <my.interpreter::evaluate+0x1a5f>
 1065e23:	48 89 c7             	mov    %rax,%rdi
 1065e26:	48 6b c7 38          	imul   $0x38,%rdi,%rax
 1065e2a:	83 7c 01 20 09       	cmpl   $0x9,0x20(%rcx,%rax,1)
 1065e2f:	0f 85 0b 10 00 00    	jne    1066e40 <my.interpreter::evaluate+0x1d70>
 1065e35:	48 01 c8             	add    %rcx,%rax
 1065e38:	48 83 c0 20          	add    $0x20,%rax
 1065e3c:	48 8b 40 10          	mov    0x10(%rax),%rax
 1065e40:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065e44:	48 39 d6             	cmp    %rdx,%rsi
 1065e47:	0f 83 07 0d 00 00    	jae    1066b54 <my.interpreter::evaluate+0x1a84>
 1065e4d:	48 89 f1             	mov    %rsi,%rcx
 1065e50:	48 c1 e1 04          	shl    $0x4,%rcx
 1065e54:	c5 f8 10 44 08 20    	vmovups 0x20(%rax,%rcx,1),%xmm0
 1065e5a:	49 8b 41 78          	mov    0x78(%r9),%rax
 1065e5e:	49 8b b1 80 00 00 00 	mov    0x80(%r9),%rsi
 1065e65:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065e69:	48 89 f1             	mov    %rsi,%rcx
 1065e6c:	48 39 d6             	cmp    %rdx,%rsi
 1065e6f:	0f 83 01 0d 00 00    	jae    1066b76 <my.interpreter::evaluate+0x1aa6>
 1065e75:	48 c1 e1 04          	shl    $0x4,%rcx
 1065e79:	c5 f8 54 05 5f e5 f9 	vandps -0x61aa1(%rip),%xmm0,%xmm0        # 10043e0 <__anon_2214+0xb0>
 1065e80:	ff 
 1065e81:	c5 f8 11 44 08 20    	vmovups %xmm0,0x20(%rax,%rcx,1)
 1065e87:	48 89 f0             	mov    %rsi,%rax
 1065e8a:	48 ff c0             	inc    %rax
 1065e8d:	0f 80 b9 0f 00 00    	jo     1066e4c <my.interpreter::evaluate+0x1d7c>
 1065e93:	49 89 81 80 00 00 00 	mov    %rax,0x80(%r9)
 1065e9a:	e9 87 02 00 00       	jmp    1066126 <my.interpreter::evaluate+0x1056>
 1065e9f:	49 8b 8d 80 00 00 00 	mov    0x80(%r13),%rcx
 1065ea6:	48 89 c8             	mov    %rcx,%rax
 1065ea9:	48 ff c8             	dec    %rax
 1065eac:	0f 80 ab 0f 00 00    	jo     1066e5d <my.interpreter::evaluate+0x1d8d>
 1065eb2:	49 8b 4d 78          	mov    0x78(%r13),%rcx
 1065eb6:	48 8b 51 08          	mov    0x8(%rcx),%rdx
 1065eba:	48 39 d0             	cmp    %rdx,%rax
 1065ebd:	0f 83 d5 0c 00 00    	jae    1066b98 <my.interpreter::evaluate+0x1ac8>
 1065ec3:	49 89 c1             	mov    %rax,%r9
 1065ec6:	49 c1 e1 04          	shl    $0x4,%r9
 1065eca:	4e 8b 44 09 28       	mov    0x28(%rcx,%r9,1),%r8
 1065ecf:	42 8b 4c 09 20       	mov    0x20(%rcx,%r9,1),%ecx
 1065ed4:	4c 89 ef             	mov    %r13,%rdi
 1065ed7:	48 8b 54 24 28       	mov    0x28(%rsp),%rdx
 1065edc:	e8 5f 5b 00 00       	call   106ba40 <my.heap::set_env_slot>
 1065ee1:	e9 9f 03 00 00       	jmp    1066285 <my.interpreter::evaluate+0x11b5>
 1065ee6:	0f b6 84 24 20 07 00 	movzbl 0x720(%rsp),%eax
 1065eed:	00 
 1065eee:	0f b6 c0             	movzbl %al,%eax
 1065ef1:	48 8d 7c 24 60       	lea    0x60(%rsp),%rdi
 1065ef6:	48 89 ee             	mov    %rbp,%rsi
 1065ef9:	48 89 da             	mov    %rbx,%rdx
 1065efc:	4c 89 e9             	mov    %r13,%rcx
 1065eff:	4d 89 f8             	mov    %r15,%r8
 1065f02:	4d 89 e5             	mov    %r12,%r13
 1065f05:	4d 89 e1             	mov    %r12,%r9
 1065f08:	ff b4 24 38 07 00 00 	push   0x738(%rsp)
 1065f0f:	41 56                	push   %r14
 1065f11:	ff b4 24 38 07 00 00 	push   0x738(%rsp)
 1065f18:	50                   	push   %rax
 1065f19:	ff b4 24 38 07 00 00 	push   0x738(%rsp)
 1065f20:	ff b4 24 38 07 00 00 	push   0x738(%rsp)
 1065f27:	e8 a4 f1 ff ff       	call   10650d0 <my.interpreter::evaluate>
 1065f2c:	48 83 c4 30          	add    $0x30,%rsp
 1065f30:	48 8b 84 24 60 01 00 	mov    0x160(%rsp),%rax
 1065f37:	00 
 1065f38:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
 1065f3d:	48 8b bc 24 68 01 00 	mov    0x168(%rsp),%rdi
 1065f44:	00 
 1065f45:	48 8b 84 24 70 01 00 	mov    0x170(%rsp),%rax
 1065f4c:	00 
 1065f4d:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
 1065f52:	80 7c 24 60 01       	cmpb   $0x1,0x60(%rsp)
 1065f57:	0f 84 f9 06 00 00    	je     1066656 <my.interpreter::evaluate+0x1586>
 1065f5d:	4c 8b 74 24 20       	mov    0x20(%rsp),%r14
 1065f62:	4d 89 e9             	mov    %r13,%r9
 1065f65:	49 8b 85 80 00 00 00 	mov    0x80(%r13),%rax
 1065f6c:	48 89 c6             	mov    %rax,%rsi
 1065f6f:	48 ff ce             	dec    %rsi
 1065f72:	4c 8b 6c 24 28       	mov    0x28(%rsp),%r13
 1065f77:	4c 8b 7c 24 30       	mov    0x30(%rsp),%r15
 1065f7c:	0f 80 cf 0d 00 00    	jo     1066d51 <my.interpreter::evaluate+0x1c81>
 1065f82:	49 8b 41 78          	mov    0x78(%r9),%rax
 1065f86:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1065f8a:	49 89 f0             	mov    %rsi,%r8
 1065f8d:	48 39 d6             	cmp    %rdx,%rsi
 1065f90:	4c 8b 64 24 58       	mov    0x58(%rsp),%r12
 1065f95:	0f 83 18 0a 00 00    	jae    10669b3 <my.interpreter::evaluate+0x18e3>
 1065f9b:	49 c1 e0 04          	shl    $0x4,%r8
 1065f9f:	42 0f b6 54 00 20    	movzbl 0x20(%rax,%r8,1),%edx
 1065fa5:	83 fa 01             	cmp    $0x1,%edx
 1065fa8:	0f 84 de 02 00 00    	je     106628c <my.interpreter::evaluate+0x11bc>
 1065fae:	85 d2                	test   %edx,%edx
 1065fb0:	0f 85 ef 02 00 00    	jne    10662a5 <my.interpreter::evaluate+0x11d5>
 1065fb6:	83 7c 24 48 1e       	cmpl   $0x1e,0x48(%rsp)
 1065fbb:	0f 84 eb 02 00 00    	je     10662ac <my.interpreter::evaluate+0x11dc>
 1065fc1:	e9 30 03 00 00       	jmp    10662f6 <my.interpreter::evaluate+0x1226>
 1065fc6:	40 80 fe 02          	cmp    $0x2,%sil
 1065fca:	4c 8b 74 24 20       	mov    0x20(%rsp),%r14
 1065fcf:	0f 85 6d 04 00 00    	jne    1066442 <my.interpreter::evaluate+0x1372>
 1065fd5:	48 be 00 00 00 00 00 	movabs $0x8000000000000000,%rsi
 1065fdc:	00 00 80 
 1065fdf:	48 31 f2             	xor    %rsi,%rdx
 1065fe2:	48 c7 01 02 00 00 00 	movq   $0x2,(%rcx)
 1065fe9:	48 89 51 08          	mov    %rdx,0x8(%rcx)
 1065fed:	e9 b6 03 00 00       	jmp    10663a8 <my.interpreter::evaluate+0x12d8>
 1065ff2:	4c 89 e7             	mov    %r12,%rdi
 1065ff5:	4c 89 fe             	mov    %r15,%rsi
 1065ff8:	e8 f3 36 00 00       	call   10696f0 <my.heap::instance_class>
 1065ffd:	4d 89 e5             	mov    %r12,%r13
 1066000:	4c 89 e7             	mov    %r12,%rdi
 1066003:	48 89 c6             	mov    %rax,%rsi
 1066006:	48 89 ea             	mov    %rbp,%rdx
 1066009:	89 d9                	mov    %ebx,%ecx
 106600b:	e8 d0 38 00 00       	call   10698e0 <my.heap::class_method>
 1066010:	3c 01                	cmp    $0x1,%al
 1066012:	0f 85 a2 06 00 00    	jne    10666ba <my.interpreter::evaluate+0x15ea>
 1066018:	80 fa 03             	cmp    $0x3,%dl
 106601b:	0f 85 9e 0c 00 00    	jne    1066cbf <my.interpreter::evaluate+0x1bef>
 1066021:	49 89 c8             	mov    %rcx,%r8
 1066024:	41 0f b6 d6          	movzbl %r14b,%edx
 1066028:	48 8d bc 24 78 01 00 	lea    0x178(%rsp),%rdi
 106602f:	00 
 1066030:	4c 89 ee             	mov    %r13,%rsi
 1066033:	4c 89 f9             	mov    %r15,%rcx
 1066036:	e8 25 a7 00 00       	call   1070760 <my.interpreter::bind>
 106603b:	49 8b 85 80 00 00 00 	mov    0x80(%r13),%rax
 1066042:	48 89 c6             	mov    %rax,%rsi
 1066045:	48 ff ce             	dec    %rsi
 1066048:	0f 80 56 0e 00 00    	jo     1066ea4 <my.interpreter::evaluate+0x1dd4>
 106604e:	4d 89 ec             	mov    %r13,%r12
 1066051:	48 8b 8c 24 78 01 00 	mov    0x178(%rsp),%rcx
 1066058:	00 
 1066059:	49 8b 45 78          	mov    0x78(%r13),%rax
 106605d:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1066061:	48 39 d6             	cmp    %rdx,%rsi
 1066064:	4c 8b 74 24 20       	mov    0x20(%rsp),%r14
 1066069:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 106606e:	0f 83 49 0b 00 00    	jae    1066bbd <my.interpreter::evaluate+0x1aed>
 1066074:	48 89 f7             	mov    %rsi,%rdi
 1066077:	48 c1 e7 04          	shl    $0x4,%rdi
 106607b:	48 8d 34 38          	lea    (%rax,%rdi,1),%rsi
 106607f:	48 83 c6 20          	add    $0x20,%rsi
 1066083:	48 c7 44 38 20 03 00 	movq   $0x3,0x20(%rax,%rdi,1)
 106608a:	00 00 
 106608c:	48 89 4e 08          	mov    %rcx,0x8(%rsi)
 1066090:	49 89 44 24 78       	mov    %rax,0x78(%r12)
 1066095:	31 c0                	xor    %eax,%eax
 1066097:	4c 8b 64 24 30       	mov    0x30(%rsp),%r12
 106609c:	e9 9a 07 00 00       	jmp    106683b <my.interpreter::evaluate+0x176b>
 10660a1:	4c 8b 68 20          	mov    0x20(%rax),%r13
 10660a5:	48 8b 58 30          	mov    0x30(%rax),%rbx
 10660a9:	4d 8b 79 30          	mov    0x30(%r9),%r15
 10660ad:	4d 8b 61 38          	mov    0x38(%r9),%r12
 10660b1:	4c 89 cf             	mov    %r9,%rdi
 10660b4:	48 89 de             	mov    %rbx,%rsi
 10660b7:	4c 89 cd             	mov    %r9,%rbp
 10660ba:	e8 61 2f 00 00       	call   1069020 <my.heap::string_hash>
 10660bf:	4c 89 ff             	mov    %r15,%rdi
 10660c2:	4c 89 e6             	mov    %r12,%rsi
 10660c5:	48 89 da             	mov    %rbx,%rdx
 10660c8:	89 c1                	mov    %eax,%ecx
 10660ca:	e8 41 2e 00 00       	call   1068f10 <my.table::get>
 10660cf:	3c 01                	cmp    $0x1,%al
 10660d1:	0f 85 53 06 00 00    	jne    106672a <my.interpreter::evaluate+0x165a>
 10660d7:	48 8b 7d 78          	mov    0x78(%rbp),%rdi
 10660db:	48 8b b5 80 00 00 00 	mov    0x80(%rbp),%rsi
 10660e2:	48 8b 47 08          	mov    0x8(%rdi),%rax
 10660e6:	49 89 f0             	mov    %rsi,%r8
 10660e9:	48 39 c6             	cmp    %rax,%rsi
 10660ec:	0f 83 ed 0a 00 00    	jae    1066bdf <my.interpreter::evaluate+0x1b0f>
 10660f2:	49 c1 e0 04          	shl    $0x4,%r8
 10660f6:	0f b6 c2             	movzbl %dl,%eax
 10660f9:	4a 89 44 07 20       	mov    %rax,0x20(%rdi,%r8,1)
 10660fe:	4a 89 4c 07 28       	mov    %rcx,0x28(%rdi,%r8,1)
 1066103:	48 89 f0             	mov    %rsi,%rax
 1066106:	48 ff c0             	inc    %rax
 1066109:	4c 8b 9c 24 18 07 00 	mov    0x718(%rsp),%r11
 1066110:	00 
 1066111:	4c 8b bc 24 28 07 00 	mov    0x728(%rsp),%r15
 1066118:	00 
 1066119:	0f 80 99 0d 00 00    	jo     1066eb8 <my.interpreter::evaluate+0x1de8>
 106611f:	48 89 85 80 00 00 00 	mov    %rax,0x80(%rbp)
 1066126:	31 c0                	xor    %eax,%eax
 1066128:	49 89 06             	mov    %rax,(%r14)
 106612b:	49 89 5e 08          	mov    %rbx,0x8(%r14)
 106612f:	4d 89 6e 10          	mov    %r13,0x10(%r14)
 1066133:	4d 89 9e 00 01 00 00 	mov    %r11,0x100(%r14)
 106613a:	0f b6 84 24 20 07 00 	movzbl 0x720(%rsp),%eax
 1066141:	00 
 1066142:	0f b6 c0             	movzbl %al,%eax
 1066145:	49 89 86 08 01 00 00 	mov    %rax,0x108(%r14)
 106614c:	e9 79 02 00 00       	jmp    10663ca <my.interpreter::evaluate+0x12fa>
 1066151:	45 31 db             	xor    %r11d,%r11d
 1066154:	4c 8b 04 24          	mov    (%rsp),%r8
 1066158:	48 83 ec 08          	sub    $0x8,%rsp
 106615c:	44 0f b6 f1          	movzbl %cl,%r14d
 1066160:	48 8d bc 24 d0 02 00 	lea    0x2d0(%rsp),%rdi
 1066167:	00 
 1066168:	48 89 ee             	mov    %rbp,%rsi
 106616b:	48 8b 54 24 38       	mov    0x38(%rsp),%rdx
 1066170:	48 89 d9             	mov    %rbx,%rcx
 1066173:	4d 89 e9             	mov    %r13,%r9
 1066176:	ff b4 24 40 07 00 00 	push   0x740(%rsp)
 106617d:	ff 74 24 28          	push   0x28(%rsp)
 1066181:	41 53                	push   %r11
 1066183:	41 52                	push   %r10
 1066185:	41 56                	push   %r14
 1066187:	50                   	push   %rax
 1066188:	41 54                	push   %r12
 106618a:	e8 71 98 00 00       	call   106fa00 <my.interpreter::call_value>
 106618f:	48 83 c4 40          	add    $0x40,%rsp
 1066193:	0f b6 94 24 c8 02 00 	movzbl 0x2c8(%rsp),%edx
 106619a:	00 
 106619b:	c5 f8 10 84 24 d0 02 	vmovups 0x2d0(%rsp),%xmm0
 10661a2:	00 00 
 10661a4:	48 8b 84 24 c8 03 00 	mov    0x3c8(%rsp),%rax
 10661ab:	00 
 10661ac:	0f b6 8c 24 d0 03 00 	movzbl 0x3d0(%rsp),%ecx
 10661b3:	00 
 10661b4:	4c 8b 94 24 d8 03 00 	mov    0x3d8(%rsp),%r10
 10661bb:	00 
 10661bc:	48 83 fa 01          	cmp    $0x1,%rdx
 10661c0:	4c 8b 74 24 20       	mov    0x20(%rsp),%r14
 10661c5:	0f 84 e4 03 00 00    	je     10665af <my.interpreter::evaluate+0x14df>
 10661cb:	49 89 16             	mov    %rdx,(%r14)
 10661ce:	c4 c1 78 11 46 08    	vmovups %xmm0,0x8(%r14)
 10661d4:	49 89 86 00 01 00 00 	mov    %rax,0x100(%r14)
 10661db:	49 89 8e 08 01 00 00 	mov    %rcx,0x108(%r14)
 10661e2:	4d 89 96 10 01 00 00 	mov    %r10,0x110(%r14)
 10661e9:	e9 70 06 00 00       	jmp    106685e <my.interpreter::evaluate+0x178e>
 10661ee:	49 8b 5d 30          	mov    0x30(%r13),%rbx
 10661f2:	4d 8b 7d 38          	mov    0x38(%r13),%r15
 10661f6:	4c 89 ef             	mov    %r13,%rdi
 10661f9:	48 8b 6c 24 18       	mov    0x18(%rsp),%rbp
 10661fe:	48 89 ee             	mov    %rbp,%rsi
 1066201:	e8 1a 2e 00 00       	call   1069020 <my.heap::string_hash>
 1066206:	48 89 df             	mov    %rbx,%rdi
 1066209:	4c 89 fe             	mov    %r15,%rsi
 106620c:	48 89 ea             	mov    %rbp,%rdx
 106620f:	89 c1                	mov    %eax,%ecx
 1066211:	e8 fa 2c 00 00       	call   1068f10 <my.table::get>
 1066216:	3c 01                	cmp    $0x1,%al
 1066218:	0f 85 99 05 00 00    	jne    10667b7 <my.interpreter::evaluate+0x16e7>
 106621e:	49 8b 85 80 00 00 00 	mov    0x80(%r13),%rax
 1066225:	48 89 c6             	mov    %rax,%rsi
 1066228:	48 ff ce             	dec    %rsi
 106622b:	0f 80 98 0c 00 00    	jo     1066ec9 <my.interpreter::evaluate+0x1df9>
 1066231:	4c 89 ef             	mov    %r13,%rdi
 1066234:	49 8b 45 78          	mov    0x78(%r13),%rax
 1066238:	48 8b 50 08          	mov    0x8(%rax),%rdx
 106623c:	48 39 d6             	cmp    %rdx,%rsi
 106623f:	0f 83 bf 09 00 00    	jae    1066c04 <my.interpreter::evaluate+0x1b34>
 1066245:	48 89 f1             	mov    %rsi,%rcx
 1066248:	48 c1 e1 04          	shl    $0x4,%rcx
 106624c:	48 8b 5c 08 28       	mov    0x28(%rax,%rcx,1),%rbx
 1066251:	8b 6c 08 20          	mov    0x20(%rax,%rcx,1),%ebp
 1066255:	4c 8b 6c 24 18       	mov    0x18(%rsp),%r13
 106625a:	4c 89 ee             	mov    %r13,%rsi
 106625d:	49 89 ff             	mov    %rdi,%r15
 1066260:	e8 bb 2d 00 00       	call   1069020 <my.heap::string_hash>
 1066265:	49 8b 7f 30          	mov    0x30(%r15),%rdi
 1066269:	49 8b 77 38          	mov    0x38(%r15),%rsi
 106626d:	4c 89 ea             	mov    %r13,%rdx
 1066270:	89 c1                	mov    %eax,%ecx
 1066272:	41 89 e8             	mov    %ebp,%r8d
 1066275:	49 89 d9             	mov    %rbx,%r9
 1066278:	e8 83 2e 00 00       	call   1069100 <my.table::set>
 106627d:	49 89 57 30          	mov    %rdx,0x30(%r15)
 1066281:	49 89 4f 38          	mov    %rcx,0x38(%r15)
 1066285:	31 c0                	xor    %eax,%eax
 1066287:	e9 aa 05 00 00       	jmp    1066836 <my.interpreter::evaluate+0x1766>
 106628c:	4c 01 c0             	add    %r8,%rax
 106628f:	48 83 c0 20          	add    $0x20,%rax
 1066293:	83 7c 24 48 1e       	cmpl   $0x1e,0x48(%rsp)
 1066298:	0f 95 c2             	setne  %dl
 106629b:	32 50 08             	xor    0x8(%rax),%dl
 106629e:	f6 c2 01             	test   $0x1,%dl
 10662a1:	74 09                	je     10662ac <my.interpreter::evaluate+0x11dc>
 10662a3:	eb 51                	jmp    10662f6 <my.interpreter::evaluate+0x1226>
 10662a5:	83 7c 24 48 1e       	cmpl   $0x1e,0x48(%rsp)
 10662aa:	74 4a                	je     10662f6 <my.interpreter::evaluate+0x1226>
 10662ac:	49 89 b1 80 00 00 00 	mov    %rsi,0x80(%r9)
 10662b3:	48 83 ec 08          	sub    $0x8,%rsp
 10662b7:	48 89 7c 24 50       	mov    %rdi,0x50(%rsp)
 10662bc:	48 8d bc 24 18 06 00 	lea    0x618(%rsp),%rdi
 10662c3:	00 
 10662c4:	48 89 ee             	mov    %rbp,%rsi
 10662c7:	4c 89 fa             	mov    %r15,%rdx
 10662ca:	4c 89 e1             	mov    %r12,%rcx
 10662cd:	4c 8b 44 24 08       	mov    0x8(%rsp),%r8
 10662d2:	ff 74 24 58          	push   0x58(%rsp)
 10662d6:	4c 89 cb             	mov    %r9,%rbx
 10662d9:	e8 a2 94 00 00       	call   106f780 <my.interpreter::try_push_atom>
 10662de:	48 8b 7c 24 58       	mov    0x58(%rsp),%rdi
 10662e3:	4c 8b 44 24 10       	mov    0x10(%rsp),%r8
 10662e8:	48 83 c4 10          	add    $0x10,%rsp
 10662ec:	f6 84 24 10 06 00 00 	testb  $0x1,0x610(%rsp)
 10662f3:	01 
 10662f4:	74 08                	je     10662fe <my.interpreter::evaluate+0x122e>
 10662f6:	40 0f b6 c7          	movzbl %dil,%eax
 10662fa:	31 c9                	xor    %ecx,%ecx
 10662fc:	eb 72                	jmp    1066370 <my.interpreter::evaluate+0x12a0>
 10662fe:	49 89 d9             	mov    %rbx,%r9
 1066301:	40 0f b6 c7          	movzbl %dil,%eax
 1066305:	48 8d bc 24 78 01 00 	lea    0x178(%rsp),%rdi
 106630c:	00 
 106630d:	48 89 ee             	mov    %rbp,%rsi
 1066310:	4c 89 fa             	mov    %r15,%rdx
 1066313:	4c 89 e1             	mov    %r12,%rcx
 1066316:	ff b4 24 38 07 00 00 	push   0x738(%rsp)
 106631d:	ff 74 24 58          	push   0x58(%rsp)
 1066321:	ff 74 24 28          	push   0x28(%rsp)
 1066325:	50                   	push   %rax
 1066326:	41 55                	push   %r13
 1066328:	ff b4 24 38 07 00 00 	push   0x738(%rsp)
 106632f:	e8 9c ed ff ff       	call   10650d0 <my.interpreter::evaluate>
 1066334:	48 83 c4 30          	add    $0x30,%rsp
 1066338:	0f b6 8c 24 78 01 00 	movzbl 0x178(%rsp),%ecx
 106633f:	00 
 1066340:	c5 f8 10 84 24 80 01 	vmovups 0x180(%rsp),%xmm0
 1066347:	00 00 
 1066349:	4c 8b ac 24 78 02 00 	mov    0x278(%rsp),%r13
 1066350:	00 
 1066351:	0f b6 84 24 80 02 00 	movzbl 0x280(%rsp),%eax
 1066358:	00 
 1066359:	48 8b 94 24 88 02 00 	mov    0x288(%rsp),%rdx
 1066360:	00 
 1066361:	48 89 54 24 18       	mov    %rdx,0x18(%rsp)
 1066366:	48 83 f9 01          	cmp    $0x1,%rcx
 106636a:	0f 84 03 05 00 00    	je     1066873 <my.interpreter::evaluate+0x17a3>
 1066370:	49 89 0e             	mov    %rcx,(%r14)
 1066373:	c4 c1 78 11 46 08    	vmovups %xmm0,0x8(%r14)
 1066379:	4d 89 ae 00 01 00 00 	mov    %r13,0x100(%r14)
 1066380:	49 89 86 08 01 00 00 	mov    %rax,0x108(%r14)
 1066387:	48 8b 44 24 18       	mov    0x18(%rsp),%rax
 106638c:	49 89 86 10 01 00 00 	mov    %rax,0x110(%r14)
 1066393:	e9 c6 04 00 00       	jmp    106685e <my.interpreter::evaluate+0x178e>
 1066398:	b2 01                	mov    $0x1,%dl
 106639a:	eb 02                	jmp    106639e <my.interpreter::evaluate+0x12ce>
 106639c:	31 d2                	xor    %edx,%edx
 106639e:	48 c7 01 01 00 00 00 	movq   $0x1,(%rcx)
 10663a5:	88 51 08             	mov    %dl,0x8(%rcx)
 10663a8:	49 89 40 78          	mov    %rax,0x78(%r8)
 10663ac:	31 c9                	xor    %ecx,%ecx
 10663ae:	49 89 0e             	mov    %rcx,(%r14)
 10663b1:	49 89 46 08          	mov    %rax,0x8(%r14)
 10663b5:	49 89 56 10          	mov    %rdx,0x10(%r14)
 10663b9:	c5 f8 54 05 5f df f9 	vandps -0x620a1(%rip),%xmm0,%xmm0        # 1004320 <__anon_2217+0x60>
 10663c0:	ff 
 10663c1:	c4 c1 78 11 86 00 01 	vmovups %xmm0,0x100(%r14)
 10663c8:	00 00 
 10663ca:	4d 89 be 10 01 00 00 	mov    %r15,0x110(%r14)
 10663d1:	e9 88 04 00 00       	jmp    106685e <my.interpreter::evaluate+0x178e>
 10663d6:	48 8d 3d e3 bd fa ff 	lea    -0x5421d(%rip),%rdi        # 10121c0 <core_number_pairs+0xaf60>
 10663dd:	e8 1e df fb ff       	call   1024300 <myl_core_owned_octets_copy>
 10663e2:	48 89 c3             	mov    %rax,%rbx
 10663e5:	48 8d 3d 34 fa 01 00 	lea    0x1fa34(%rip),%rdi        # 1085e20 <core_durable_error.verbs+0x6150>
 10663ec:	e8 cf 07 ff ff       	call   1056bc0 <myl_core_err_trace_origin_preserve_most>
 10663f1:	4c 8b 74 24 20       	mov    0x20(%rsp),%r14
 10663f6:	48 8b 4c 24 28       	mov    0x28(%rsp),%rcx
 10663fb:	48 8d 3d be c9 01 00 	lea    0x1c9be(%rip),%rdi        # 1082dc0 <core_durable_error.verbs+0x30f0>
 1066402:	e9 25 04 00 00       	jmp    106682c <my.interpreter::evaluate+0x175c>
 1066407:	4d 89 dc             	mov    %r11,%r12
 106640a:	48 8d 3d ef bd fa ff 	lea    -0x54211(%rip),%rdi        # 1012200 <core_number_pairs+0xafa0>
 1066411:	4d 89 d7             	mov    %r10,%r15
 1066414:	e8 e7 de fb ff       	call   1024300 <myl_core_owned_octets_copy>
 1066419:	4d 89 fa             	mov    %r15,%r10
 106641c:	48 8d 3d 3d fc 01 00 	lea    0x1fc3d(%rip),%rdi        # 1086060 <core_durable_error.verbs+0x6390>
 1066423:	e8 98 07 ff ff       	call   1056bc0 <myl_core_err_trace_origin_preserve_most>
 1066428:	c5 fa 7e 44 24 48    	vmovq  0x48(%rsp),%xmm0
 106642e:	c4 e1 f9 6e c8       	vmovq  %rax,%xmm1
 1066433:	c5 f1 6c c0          	vpunpcklqdq %xmm0,%xmm1,%xmm0
 1066437:	c5 f9 7f 44 24 30    	vmovdqa %xmm0,0x30(%rsp)
 106643d:	e9 9a 01 00 00       	jmp    10665dc <my.interpreter::evaluate+0x150c>
 1066442:	40 0f b6 c6          	movzbl %sil,%eax
 1066446:	83 f8 01             	cmp    $0x1,%eax
 1066449:	c5 f8 29 44 24 30    	vmovaps %xmm0,0x30(%rsp)
 106644f:	48 8d 3d 8a be fa ff 	lea    -0x54176(%rip),%rdi        # 10122e0 <core_number_pairs+0xb080>
 1066456:	0f 84 1f 02 00 00    	je     106667b <my.interpreter::evaluate+0x15ab>
 106645c:	85 c0                	test   %eax,%eax
 106645e:	0f 85 25 02 00 00    	jne    1066689 <my.interpreter::evaluate+0x15b9>
 1066464:	e8 97 de fb ff       	call   1024300 <myl_core_owned_octets_copy>
 1066469:	48 8d 3d 50 ff 01 00 	lea    0x1ff50(%rip),%rdi        # 10863c0 <core_durable_error.verbs+0x66f0>
 1066470:	e9 20 02 00 00       	jmp    1066695 <my.interpreter::evaluate+0x15c5>
 1066475:	48 8d 54 24 68       	lea    0x68(%rsp),%rdx
 106647a:	48 8d 3d df f8 01 00 	lea    0x1f8df(%rip),%rdi        # 1085d60 <core_durable_error.verbs+0x6090>
 1066481:	e9 a2 01 00 00       	jmp    1066628 <my.interpreter::evaluate+0x1558>
 1066486:	48 8b 5c 24 68       	mov    0x68(%rsp),%rbx
 106648b:	48 8b 4c 24 70       	mov    0x70(%rsp),%rcx
 1066490:	48 8d 3d 59 f9 01 00 	lea    0x1f959(%rip),%rdi        # 1085df0 <core_durable_error.verbs+0x6120>
 1066497:	e8 64 07 ff ff       	call   1056c00 <myl_core_err_trace_append_preserve_most>
 106649c:	48 8d 3d 1d c9 01 00 	lea    0x1c91d(%rip),%rdi        # 1082dc0 <core_durable_error.verbs+0x30f0>
 10664a3:	e9 84 03 00 00       	jmp    106682c <my.interpreter::evaluate+0x175c>
 10664a8:	4d 89 dc             	mov    %r11,%r12
 10664ab:	c5 fa 6f 44 24 68    	vmovdqu 0x68(%rsp),%xmm0
 10664b1:	c5 f9 7f 44 24 30    	vmovdqa %xmm0,0x30(%rsp)
 10664b7:	48 8d 3d 72 fb 01 00 	lea    0x1fb72(%rip),%rdi        # 1086030 <core_durable_error.verbs+0x6360>
 10664be:	e8 3d 07 ff ff       	call   1056c00 <myl_core_err_trace_append_preserve_most>
 10664c3:	e9 14 01 00 00       	jmp    10665dc <my.interpreter::evaluate+0x150c>
 10664c8:	48 8b 5c 24 68       	mov    0x68(%rsp),%rbx
 10664cd:	48 8b 4c 24 70       	mov    0x70(%rsp),%rcx
 10664d2:	48 8d 3d 27 f5 01 00 	lea    0x1f527(%rip),%rdi        # 1085a00 <core_durable_error.verbs+0x5d30>
 10664d9:	e8 22 07 ff ff       	call   1056c00 <myl_core_err_trace_append_preserve_most>
 10664de:	e9 42 03 00 00       	jmp    1066825 <my.interpreter::evaluate+0x1755>
 10664e3:	48 8d 3d 76 c8 01 00 	lea    0x1c876(%rip),%rdi        # 1082d60 <core_durable_error.verbs+0x3090>
 10664ea:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 10664ef:	e8 0c 07 ff ff       	call   1056c00 <myl_core_err_trace_append_preserve_most>
 10664f4:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 10664f9:	e9 8c f3 ff ff       	jmp    106588a <my.interpreter::evaluate+0x7ba>
 10664fe:	c5 f8 29 44 24 30    	vmovaps %xmm0,0x30(%rsp)
 1066504:	48 8b 44 24 68       	mov    0x68(%rsp),%rax
 1066509:	48 8b 54 24 70       	mov    0x70(%rsp),%rdx
 106650e:	48 8d 3d 7b fe 01 00 	lea    0x1fe7b(%rip),%rdi        # 1086390 <core_durable_error.verbs+0x66c0>
 1066515:	e8 e6 06 ff ff       	call   1056c00 <myl_core_err_trace_append_preserve_most>
 106651a:	4c 8b 74 24 20       	mov    0x20(%rsp),%r14
 106651f:	e9 7a 01 00 00       	jmp    106669e <my.interpreter::evaluate+0x15ce>
 1066524:	48 89 df             	mov    %rbx,%rdi
 1066527:	4c 89 fe             	mov    %r15,%rsi
 106652a:	e8 01 29 00 00       	call   1068e30 <my.heap::string_chars>
 106652f:	48 89 c3             	mov    %rax,%rbx
 1066532:	48 8d 3d 47 c2 fa ff 	lea    -0x53db9(%rip),%rdi        # 1012780 <core_number_pairs+0xb520>
 1066539:	48 89 c6             	mov    %rax,%rsi
 106653c:	e8 3f 89 fc ff       	call   102ee80 <myl_core_bytes_concat>
 1066541:	4d 89 f4             	mov    %r14,%r12
 1066544:	49 89 c6             	mov    %rax,%r14
 1066547:	48 89 df             	mov    %rbx,%rdi
 106654a:	e8 31 d5 fb ff       	call   1023a80 <myl_core_drop_owned>
 106654f:	48 8d 35 2a bc fa ff 	lea    -0x543d6(%rip),%rsi        # 1012180 <core_number_pairs+0xaf20>
 1066556:	4c 89 f7             	mov    %r14,%rdi
 1066559:	e8 22 89 fc ff       	call   102ee80 <myl_core_bytes_concat>
 106655e:	49 89 c7             	mov    %rax,%r15
 1066561:	4c 89 f7             	mov    %r14,%rdi
 1066564:	4d 89 e6             	mov    %r12,%r14
 1066567:	e8 14 d5 fb ff       	call   1023a80 <myl_core_drop_owned>
 106656c:	4c 89 ff             	mov    %r15,%rdi
 106656f:	e8 8c dd fb ff       	call   1024300 <myl_core_owned_octets_copy>
 1066574:	48 89 c3             	mov    %rax,%rbx
 1066577:	4c 89 ff             	mov    %r15,%rdi
 106657a:	e8 01 d5 fb ff       	call   1023a80 <myl_core_drop_owned>
 106657f:	48 8d 3d 7a fd 01 00 	lea    0x1fd7a(%rip),%rdi        # 1086300 <core_durable_error.verbs+0x6630>
 1066586:	e8 35 06 ff ff       	call   1056bc0 <myl_core_err_trace_origin_preserve_most>
 106658b:	48 8d 3d ee c8 01 00 	lea    0x1c8ee(%rip),%rdi        # 1082e80 <core_durable_error.verbs+0x31b0>
 1066592:	e8 69 06 ff ff       	call   1056c00 <myl_core_err_trace_append_preserve_most>
 1066597:	b8 01 00 00 00       	mov    $0x1,%eax
 106659c:	44 0f b6 a4 24 20 07 	movzbl 0x720(%rsp),%r12d
 10665a3:	00 00 
 10665a5:	48 8b 4c 24 30       	mov    0x30(%rsp),%rcx
 10665aa:	e9 32 f8 ff ff       	jmp    1065de1 <my.interpreter::evaluate+0xd11>
 10665af:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 10665b4:	48 8d 3d 05 f8 01 00 	lea    0x1f805(%rip),%rdi        # 1085dc0 <core_durable_error.verbs+0x60f0>
 10665bb:	eb 79                	jmp    1066636 <my.interpreter::evaluate+0x1566>
 10665bd:	c5 fa 6f 84 24 80 01 	vmovdqu 0x180(%rsp),%xmm0
 10665c4:	00 00 
 10665c6:	c5 f9 7f 44 24 30    	vmovdqa %xmm0,0x30(%rsp)
 10665cc:	48 8d 3d bd fa 01 00 	lea    0x1fabd(%rip),%rdi        # 1086090 <core_durable_error.verbs+0x63c0>
 10665d3:	e8 28 06 ff ff       	call   1056c00 <myl_core_err_trace_append_preserve_most>
 10665d8:	48 8b 1c 24          	mov    (%rsp),%rbx
 10665dc:	48 8d 3d 6d c8 01 00 	lea    0x1c86d(%rip),%rdi        # 1082e50 <core_durable_error.verbs+0x3180>
 10665e3:	e8 18 06 ff ff       	call   1056c00 <myl_core_err_trace_append_preserve_most>
 10665e8:	b8 01 00 00 00       	mov    $0x1,%eax
 10665ed:	4d 89 e0             	mov    %r12,%r8
 10665f0:	c5 f8 28 44 24 30    	vmovaps 0x30(%rsp),%xmm0
 10665f6:	49 89 06             	mov    %rax,(%r14)
 10665f9:	c4 c1 78 11 46 08    	vmovups %xmm0,0x8(%r14)
 10665ff:	49 89 9e 00 01 00 00 	mov    %rbx,0x100(%r14)
 1066606:	4d 89 96 08 01 00 00 	mov    %r10,0x108(%r14)
 106660d:	4d 89 86 10 01 00 00 	mov    %r8,0x110(%r14)
 1066614:	e9 45 02 00 00       	jmp    106685e <my.interpreter::evaluate+0x178e>
 1066619:	48 8d 3d 70 f7 01 00 	lea    0x1f770(%rip),%rdi        # 1085d90 <core_durable_error.verbs+0x60c0>
 1066620:	48 8d 94 24 80 01 00 	lea    0x180(%rsp),%rdx
 1066627:	00 
 1066628:	c5 f8 10 02          	vmovups (%rdx),%xmm0
 106662c:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 1066631:	4c 8b 74 24 20       	mov    0x20(%rsp),%r14
 1066636:	e8 c5 05 ff ff       	call   1056c00 <myl_core_err_trace_append_preserve_most>
 106663b:	48 8d 3d 4e c7 01 00 	lea    0x1c74e(%rip),%rdi        # 1082d90 <core_durable_error.verbs+0x30c0>
 1066642:	e8 b9 05 ff ff       	call   1056c00 <myl_core_err_trace_append_preserve_most>
 1066647:	ba 01 00 00 00       	mov    $0x1,%edx
 106664c:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 1066651:	e9 75 fb ff ff       	jmp    10661cb <my.interpreter::evaluate+0x10fb>
 1066656:	40 0f b6 c7          	movzbl %dil,%eax
 106665a:	48 8d 3d 0f f9 01 00 	lea    0x1f90f(%rip),%rdi        # 1085f70 <core_durable_error.verbs+0x62a0>
 1066661:	c5 f8 10 44 24 68    	vmovups 0x68(%rsp),%xmm0
 1066667:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 106666c:	4c 8b 74 24 20       	mov    0x20(%rsp),%r14
 1066671:	4c 8b 6c 24 28       	mov    0x28(%rsp),%r13
 1066676:	e9 04 02 00 00       	jmp    106687f <my.interpreter::evaluate+0x17af>
 106667b:	e8 80 dc fb ff       	call   1024300 <myl_core_owned_octets_copy>
 1066680:	48 8d 3d 69 fd 01 00 	lea    0x1fd69(%rip),%rdi        # 10863f0 <core_durable_error.verbs+0x6720>
 1066687:	eb 0c                	jmp    1066695 <my.interpreter::evaluate+0x15c5>
 1066689:	e8 72 dc fb ff       	call   1024300 <myl_core_owned_octets_copy>
 106668e:	48 8d 3d 8b fd 01 00 	lea    0x1fd8b(%rip),%rdi        # 1086420 <core_durable_error.verbs+0x6750>
 1066695:	e8 26 05 ff ff       	call   1056bc0 <myl_core_err_trace_origin_preserve_most>
 106669a:	48 8b 14 24          	mov    (%rsp),%rdx
 106669e:	48 8d 3d 0b c8 01 00 	lea    0x1c80b(%rip),%rdi        # 1082eb0 <core_durable_error.verbs+0x31e0>
 10666a5:	e8 56 05 ff ff       	call   1056c00 <myl_core_err_trace_append_preserve_most>
 10666aa:	b9 01 00 00 00       	mov    $0x1,%ecx
 10666af:	c5 f8 28 44 24 30    	vmovaps 0x30(%rsp),%xmm0
 10666b5:	e9 f4 fc ff ff       	jmp    10663ae <my.interpreter::evaluate+0x12de>
 10666ba:	4c 89 ef             	mov    %r13,%rdi
 10666bd:	48 89 ee             	mov    %rbp,%rsi
 10666c0:	e8 6b 27 00 00       	call   1068e30 <my.heap::string_chars>
 10666c5:	48 89 c3             	mov    %rax,%rbx
 10666c8:	48 8d 3d b1 c0 fa ff 	lea    -0x53f4f(%rip),%rdi        # 1012780 <core_number_pairs+0xb520>
 10666cf:	48 89 c6             	mov    %rax,%rsi
 10666d2:	e8 a9 87 fc ff       	call   102ee80 <myl_core_bytes_concat>
 10666d7:	49 89 c6             	mov    %rax,%r14
 10666da:	48 89 df             	mov    %rbx,%rdi
 10666dd:	e8 9e d3 fb ff       	call   1023a80 <myl_core_drop_owned>
 10666e2:	48 8d 35 97 ba fa ff 	lea    -0x54569(%rip),%rsi        # 1012180 <core_number_pairs+0xaf20>
 10666e9:	4c 89 f7             	mov    %r14,%rdi
 10666ec:	e8 8f 87 fc ff       	call   102ee80 <myl_core_bytes_concat>
 10666f1:	49 89 c7             	mov    %rax,%r15
 10666f4:	4c 89 f7             	mov    %r14,%rdi
 10666f7:	e8 84 d3 fb ff       	call   1023a80 <myl_core_drop_owned>
 10666fc:	4c 89 ff             	mov    %r15,%rdi
 10666ff:	e8 fc db fb ff       	call   1024300 <myl_core_owned_octets_copy>
 1066704:	48 89 c3             	mov    %rax,%rbx
 1066707:	4c 89 ff             	mov    %r15,%rdi
 106670a:	e8 71 d3 fb ff       	call   1023a80 <myl_core_drop_owned>
 106670f:	48 8d 3d 3a f7 01 00 	lea    0x1f73a(%rip),%rdi        # 1085e50 <core_durable_error.verbs+0x6180>
 1066716:	e8 a5 04 ff ff       	call   1056bc0 <myl_core_err_trace_origin_preserve_most>
 106671b:	4c 8b 74 24 20       	mov    0x20(%rsp),%r14
 1066720:	4c 8b 64 24 30       	mov    0x30(%rsp),%r12
 1066725:	e9 cc fc ff ff       	jmp    10663f6 <my.interpreter::evaluate+0x1326>
 106672a:	48 89 ef             	mov    %rbp,%rdi
 106672d:	48 89 de             	mov    %rbx,%rsi
 1066730:	e8 fb 26 00 00       	call   1068e30 <my.heap::string_chars>
 1066735:	48 89 c3             	mov    %rax,%rbx
 1066738:	48 8d 3d 01 ba fa ff 	lea    -0x545ff(%rip),%rdi        # 1012140 <core_number_pairs+0xaee0>
 106673f:	48 89 c6             	mov    %rax,%rsi
 1066742:	e8 39 87 fc ff       	call   102ee80 <myl_core_bytes_concat>
 1066747:	4d 89 f4             	mov    %r14,%r12
 106674a:	49 89 c6             	mov    %rax,%r14
 106674d:	48 89 df             	mov    %rbx,%rdi
 1066750:	e8 2b d3 fb ff       	call   1023a80 <myl_core_drop_owned>
 1066755:	48 8d 35 24 ba fa ff 	lea    -0x545dc(%rip),%rsi        # 1012180 <core_number_pairs+0xaf20>
 106675c:	4c 89 f7             	mov    %r14,%rdi
 106675f:	e8 1c 87 fc ff       	call   102ee80 <myl_core_bytes_concat>
 1066764:	49 89 c7             	mov    %rax,%r15
 1066767:	4c 89 f7             	mov    %r14,%rdi
 106676a:	4d 89 e6             	mov    %r12,%r14
 106676d:	e8 0e d3 fb ff       	call   1023a80 <myl_core_drop_owned>
 1066772:	4c 89 ff             	mov    %r15,%rdi
 1066775:	e8 86 db fb ff       	call   1024300 <myl_core_owned_octets_copy>
 106677a:	48 89 c3             	mov    %rax,%rbx
 106677d:	4c 89 ff             	mov    %r15,%rdi
 1066780:	e8 fb d2 fb ff       	call   1023a80 <myl_core_drop_owned>
 1066785:	48 8d 3d 24 fd 01 00 	lea    0x1fd24(%rip),%rdi        # 10864b0 <core_durable_error.verbs+0x67e0>
 106678c:	e8 2f 04 ff ff       	call   1056bc0 <myl_core_err_trace_origin_preserve_most>
 1066791:	48 8d 3d 48 c7 01 00 	lea    0x1c748(%rip),%rdi        # 1082ee0 <core_durable_error.verbs+0x3210>
 1066798:	e8 63 04 ff ff       	call   1056c00 <myl_core_err_trace_append_preserve_most>
 106679d:	b8 01 00 00 00       	mov    $0x1,%eax
 10667a2:	4c 8b 9c 24 18 07 00 	mov    0x718(%rsp),%r11
 10667a9:	00 
 10667aa:	4c 8b bc 24 28 07 00 	mov    0x728(%rsp),%r15
 10667b1:	00 
 10667b2:	e9 71 f9 ff ff       	jmp    1066128 <my.interpreter::evaluate+0x1058>
 10667b7:	4c 89 ef             	mov    %r13,%rdi
 10667ba:	48 8b 74 24 18       	mov    0x18(%rsp),%rsi
 10667bf:	e8 6c 26 00 00       	call   1068e30 <my.heap::string_chars>
 10667c4:	48 89 c3             	mov    %rax,%rbx
 10667c7:	48 8d 3d 72 b9 fa ff 	lea    -0x5468e(%rip),%rdi        # 1012140 <core_number_pairs+0xaee0>
 10667ce:	48 89 c6             	mov    %rax,%rsi
 10667d1:	e8 aa 86 fc ff       	call   102ee80 <myl_core_bytes_concat>
 10667d6:	4d 89 f5             	mov    %r14,%r13
 10667d9:	49 89 c6             	mov    %rax,%r14
 10667dc:	48 89 df             	mov    %rbx,%rdi
 10667df:	e8 9c d2 fb ff       	call   1023a80 <myl_core_drop_owned>
 10667e4:	48 8d 35 95 b9 fa ff 	lea    -0x5466b(%rip),%rsi        # 1012180 <core_number_pairs+0xaf20>
 10667eb:	4c 89 f7             	mov    %r14,%rdi
 10667ee:	e8 8d 86 fc ff       	call   102ee80 <myl_core_bytes_concat>
 10667f3:	49 89 c7             	mov    %rax,%r15
 10667f6:	4c 89 f7             	mov    %r14,%rdi
 10667f9:	4d 89 ee             	mov    %r13,%r14
 10667fc:	e8 7f d2 fb ff       	call   1023a80 <myl_core_drop_owned>
 1066801:	4c 89 ff             	mov    %r15,%rdi
 1066804:	e8 f7 da fb ff       	call   1024300 <myl_core_owned_octets_copy>
 1066809:	48 89 c3             	mov    %rax,%rbx
 106680c:	4c 89 ff             	mov    %r15,%rdi
 106680f:	e8 6c d2 fb ff       	call   1023a80 <myl_core_drop_owned>
 1066814:	48 8d 3d 15 f2 01 00 	lea    0x1f215(%rip),%rdi        # 1085a30 <core_durable_error.verbs+0x5d60>
 106681b:	e8 a0 03 ff ff       	call   1056bc0 <myl_core_err_trace_origin_preserve_most>
 1066820:	48 8b 4c 24 48       	mov    0x48(%rsp),%rcx
 1066825:	48 8d 3d 04 c5 01 00 	lea    0x1c504(%rip),%rdi        # 1082d30 <core_durable_error.verbs+0x3060>
 106682c:	e8 cf 03 ff ff       	call   1056c00 <myl_core_err_trace_append_preserve_most>
 1066831:	b8 01 00 00 00       	mov    $0x1,%eax
 1066836:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 106683b:	49 89 06             	mov    %rax,(%r14)
 106683e:	49 89 5e 08          	mov    %rbx,0x8(%r14)
 1066842:	49 89 4e 10          	mov    %rcx,0x10(%r14)
 1066846:	c5 f8 54 05 d2 da f9 	vandps -0x6252e(%rip),%xmm0,%xmm0        # 1004320 <__anon_2217+0x60>
 106684d:	ff 
 106684e:	c4 c1 78 11 86 00 01 	vmovups %xmm0,0x100(%r14)
 1066855:	00 00 
 1066857:	4d 89 a6 10 01 00 00 	mov    %r12,0x110(%r14)
 106685e:	4c 89 f0             	mov    %r14,%rax
 1066861:	48 81 c4 d8 06 00 00 	add    $0x6d8,%rsp
 1066868:	5b                   	pop    %rbx
 1066869:	41 5c                	pop    %r12
 106686b:	41 5d                	pop    %r13
 106686d:	41 5e                	pop    %r14
 106686f:	41 5f                	pop    %r15
 1066871:	5d                   	pop    %rbp
 1066872:	c3                   	ret
 1066873:	c5 f8 29 04 24       	vmovaps %xmm0,(%rsp)
 1066878:	48 8d 3d 21 f7 01 00 	lea    0x1f721(%rip),%rdi        # 1085fa0 <core_durable_error.verbs+0x62d0>
 106687f:	e8 7c 03 ff ff       	call   1056c00 <myl_core_err_trace_append_preserve_most>
 1066884:	48 8d 3d 95 c5 01 00 	lea    0x1c595(%rip),%rdi        # 1082e20 <core_durable_error.verbs+0x3150>
 106688b:	e8 70 03 ff ff       	call   1056c00 <myl_core_err_trace_append_preserve_most>
 1066890:	b9 01 00 00 00       	mov    $0x1,%ecx
 1066895:	c5 f8 28 04 24       	vmovaps (%rsp),%xmm0
 106689a:	e9 d1 fa ff ff       	jmp    1066370 <my.interpreter::evaluate+0x12a0>
 106689f:	48 89 f0             	mov    %rsi,%rax
 10668a2:	48 c1 f8 3f          	sar    $0x3f,%rax
 10668a6:	48 21 d0             	and    %rdx,%rax
 10668a9:	48 01 f0             	add    %rsi,%rax
 10668ac:	48 39 d0             	cmp    %rdx,%rax
 10668af:	0f 82 50 e8 ff ff    	jb     1065105 <my.interpreter::evaluate+0x35>
 10668b5:	48 8d 3d 44 c4 01 00 	lea    0x1c444(%rip),%rdi        # 1082d00 <core_durable_error.verbs+0x3030>
 10668bc:	e8 3f df fb ff       	call   1024800 <myl_core_trap>
 10668c1:	48 89 f1             	mov    %rsi,%rcx
 10668c4:	48 c1 f9 3f          	sar    $0x3f,%rcx
 10668c8:	48 21 d1             	and    %rdx,%rcx
 10668cb:	48 01 f1             	add    %rsi,%rcx
 10668ce:	48 39 d1             	cmp    %rdx,%rcx
 10668d1:	0f 82 f6 ef ff ff    	jb     10658cd <my.interpreter::evaluate+0x7fd>
 10668d7:	48 8d 3d 32 c6 01 00 	lea    0x1c632(%rip),%rdi        # 1082f10 <core_durable_error.verbs+0x3240>
 10668de:	e8 1d df fb ff       	call   1024800 <myl_core_trap>
 10668e3:	48 89 f7             	mov    %rsi,%rdi
 10668e6:	48 c1 ff 3f          	sar    $0x3f,%rdi
 10668ea:	48 21 d7             	and    %rdx,%rdi
 10668ed:	48 01 f7             	add    %rsi,%rdi
 10668f0:	48 39 d7             	cmp    %rdx,%rdi
 10668f3:	0f 82 a0 f2 ff ff    	jb     1065b99 <my.interpreter::evaluate+0xac9>
 10668f9:	48 8d 3d 70 c3 01 00 	lea    0x1c370(%rip),%rdi        # 1082c70 <core_durable_error.verbs+0x2fa0>
 1066900:	e8 fb de fb ff       	call   1024800 <myl_core_trap>
 1066905:	49 89 c8             	mov    %rcx,%r8
 1066908:	49 c1 f8 3f          	sar    $0x3f,%r8
 106690c:	49 21 d0             	and    %rdx,%r8
 106690f:	49 01 c8             	add    %rcx,%r8
 1066912:	49 39 d0             	cmp    %rdx,%r8
 1066915:	0f 82 26 f3 ff ff    	jb     1065c41 <my.interpreter::evaluate+0xb71>
 106691b:	48 8d 3d 4e c3 01 00 	lea    0x1c34e(%rip),%rdi        # 1082c70 <core_durable_error.verbs+0x2fa0>
 1066922:	48 89 ce             	mov    %rcx,%rsi
 1066925:	e8 d6 de fb ff       	call   1024800 <myl_core_trap>
 106692a:	48 89 c6             	mov    %rax,%rsi
 106692d:	48 c1 fe 3f          	sar    $0x3f,%rsi
 1066931:	48 21 d6             	and    %rdx,%rsi
 1066934:	48 01 c6             	add    %rax,%rsi
 1066937:	48 39 d6             	cmp    %rdx,%rsi
 106693a:	0f 82 83 f2 ff ff    	jb     1065bc3 <my.interpreter::evaluate+0xaf3>
 1066940:	48 8d 3d 89 c3 01 00 	lea    0x1c389(%rip),%rdi        # 1082cd0 <core_durable_error.verbs+0x3000>
 1066947:	48 89 c6             	mov    %rax,%rsi
 106694a:	e8 b1 de fb ff       	call   1024800 <myl_core_trap>
 106694f:	48 89 f1             	mov    %rsi,%rcx
 1066952:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066956:	48 21 d1             	and    %rdx,%rcx
 1066959:	48 01 f1             	add    %rsi,%rcx
 106695c:	48 39 d1             	cmp    %rdx,%rcx
 106695f:	0f 82 83 f2 ff ff    	jb     1065be8 <my.interpreter::evaluate+0xb18>
 1066965:	48 8d 3d 04 c6 01 00 	lea    0x1c604(%rip),%rdi        # 1082f70 <core_durable_error.verbs+0x32a0>
 106696c:	e8 8f de fb ff       	call   1024800 <myl_core_trap>
 1066971:	48 8d 3d 58 c3 01 00 	lea    0x1c358(%rip),%rdi        # 1082cd0 <core_durable_error.verbs+0x3000>
 1066978:	31 f6                	xor    %esi,%esi
 106697a:	31 d2                	xor    %edx,%edx
 106697c:	e8 7f de fb ff       	call   1024800 <myl_core_trap>
 1066981:	48 89 f1             	mov    %rsi,%rcx
 1066984:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066988:	48 21 d1             	and    %rdx,%rcx
 106698b:	48 01 f1             	add    %rsi,%rcx
 106698e:	48 39 d1             	cmp    %rdx,%rcx
 1066991:	0f 82 77 f3 ff ff    	jb     1065d0e <my.interpreter::evaluate+0xc3e>
 1066997:	48 8d 3d d2 c2 01 00 	lea    0x1c2d2(%rip),%rdi        # 1082c70 <core_durable_error.verbs+0x2fa0>
 106699e:	e8 5d de fb ff       	call   1024800 <myl_core_trap>
 10669a3:	48 8d 3d 26 c3 01 00 	lea    0x1c326(%rip),%rdi        # 1082cd0 <core_durable_error.verbs+0x3000>
 10669aa:	31 f6                	xor    %esi,%esi
 10669ac:	31 d2                	xor    %edx,%edx
 10669ae:	e8 4d de fb ff       	call   1024800 <myl_core_trap>
 10669b3:	49 89 f0             	mov    %rsi,%r8
 10669b6:	49 c1 f8 3f          	sar    $0x3f,%r8
 10669ba:	49 21 d0             	and    %rdx,%r8
 10669bd:	49 01 f0             	add    %rsi,%r8
 10669c0:	49 39 d0             	cmp    %rdx,%r8
 10669c3:	0f 82 d2 f5 ff ff    	jb     1065f9b <my.interpreter::evaluate+0xecb>
 10669c9:	48 8d 3d 30 f6 01 00 	lea    0x1f630(%rip),%rdi        # 1086000 <core_durable_error.verbs+0x6330>
 10669d0:	e8 2b de fb ff       	call   1024800 <myl_core_trap>
 10669d5:	49 89 f5             	mov    %rsi,%r13
 10669d8:	49 c1 fd 3f          	sar    $0x3f,%r13
 10669dc:	49 21 d5             	and    %rdx,%r13
 10669df:	49 01 f5             	add    %rsi,%r13
 10669e2:	49 39 d5             	cmp    %rdx,%r13
 10669e5:	0f 82 28 eb ff ff    	jb     1065513 <my.interpreter::evaluate+0x443>
 10669eb:	48 8d 3d be f4 01 00 	lea    0x1f4be(%rip),%rdi        # 1085eb0 <core_durable_error.verbs+0x61e0>
 10669f2:	e8 09 de fb ff       	call   1024800 <myl_core_trap>
 10669f7:	48 89 f1             	mov    %rsi,%rcx
 10669fa:	48 c1 f9 3f          	sar    $0x3f,%rcx
 10669fe:	48 21 d1             	and    %rdx,%rcx
 1066a01:	48 01 f1             	add    %rsi,%rcx
 1066a04:	48 39 d1             	cmp    %rdx,%rcx
 1066a07:	0f 82 4b ec ff ff    	jb     1065658 <my.interpreter::evaluate+0x588>
 1066a0d:	48 8d 3d dc f6 01 00 	lea    0x1f6dc(%rip),%rdi        # 10860f0 <core_durable_error.verbs+0x6420>
 1066a14:	e8 e7 dd fb ff       	call   1024800 <myl_core_trap>
 1066a19:	48 89 f7             	mov    %rsi,%rdi
 1066a1c:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1066a20:	48 21 d7             	and    %rdx,%rdi
 1066a23:	48 01 f7             	add    %rsi,%rdi
 1066a26:	48 39 d7             	cmp    %rdx,%rdi
 1066a29:	0f 82 e7 ef ff ff    	jb     1065a16 <my.interpreter::evaluate+0x946>
 1066a2f:	48 8d 3d 4a fa 01 00 	lea    0x1fa4a(%rip),%rdi        # 1086480 <core_durable_error.verbs+0x67b0>
 1066a36:	e8 c5 dd fb ff       	call   1024800 <myl_core_trap>
 1066a3b:	48 89 f7             	mov    %rsi,%rdi
 1066a3e:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1066a42:	48 21 d7             	and    %rdx,%rdi
 1066a45:	48 01 f7             	add    %rsi,%rdi
 1066a48:	48 39 d7             	cmp    %rdx,%rdi
 1066a4b:	0f 82 69 f3 ff ff    	jb     1065dba <my.interpreter::evaluate+0xcea>
 1066a51:	48 8d 3d d8 f8 01 00 	lea    0x1f8d8(%rip),%rdi        # 1086330 <core_durable_error.verbs+0x6660>
 1066a58:	e8 a3 dd fb ff       	call   1024800 <myl_core_trap>
 1066a5d:	4c 89 f9             	mov    %r15,%rcx
 1066a60:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066a64:	48 21 d1             	and    %rdx,%rcx
 1066a67:	4c 01 f9             	add    %r15,%rcx
 1066a6a:	48 39 d1             	cmp    %rdx,%rcx
 1066a6d:	0f 82 ce ea ff ff    	jb     1065541 <my.interpreter::evaluate+0x471>
 1066a73:	48 8d 3d 66 d6 01 00 	lea    0x1d666(%rip),%rdi        # 10840e0 <core_durable_error.verbs+0x4410>
 1066a7a:	4c 89 fe             	mov    %r15,%rsi
 1066a7d:	e8 7e dd fb ff       	call   1024800 <myl_core_trap>
 1066a82:	48 89 f1             	mov    %rsi,%rcx
 1066a85:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066a89:	48 21 d1             	and    %rdx,%rcx
 1066a8c:	48 01 f1             	add    %rsi,%rcx
 1066a8f:	48 39 d1             	cmp    %rdx,%rcx
 1066a92:	0f 82 e7 eb ff ff    	jb     106567f <my.interpreter::evaluate+0x5af>
 1066a98:	48 8d 3d 41 d6 01 00 	lea    0x1d641(%rip),%rdi        # 10840e0 <core_durable_error.verbs+0x4410>
 1066a9f:	e8 5c dd fb ff       	call   1024800 <myl_core_trap>
 1066aa4:	48 89 f1             	mov    %rsi,%rcx
 1066aa7:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066aab:	48 21 d1             	and    %rdx,%rcx
 1066aae:	48 01 f1             	add    %rsi,%rcx
 1066ab1:	48 39 d1             	cmp    %rdx,%rcx
 1066ab4:	0f 82 66 ec ff ff    	jb     1065720 <my.interpreter::evaluate+0x650>
 1066aba:	48 8d 3d bf f6 01 00 	lea    0x1f6bf(%rip),%rdi        # 1086180 <core_durable_error.verbs+0x64b0>
 1066ac1:	e8 3a dd fb ff       	call   1024800 <myl_core_trap>
 1066ac6:	49 89 f0             	mov    %rsi,%r8
 1066ac9:	49 c1 f8 3f          	sar    $0x3f,%r8
 1066acd:	49 21 d0             	and    %rdx,%r8
 1066ad0:	49 01 f0             	add    %rsi,%r8
 1066ad3:	49 39 d0             	cmp    %rdx,%r8
 1066ad6:	0f 82 9a ec ff ff    	jb     1065776 <my.interpreter::evaluate+0x6a6>
 1066adc:	48 8d 3d fd f6 01 00 	lea    0x1f6fd(%rip),%rdi        # 10861e0 <core_durable_error.verbs+0x6510>
 1066ae3:	e8 18 dd fb ff       	call   1024800 <myl_core_trap>
 1066ae8:	48 89 f0             	mov    %rsi,%rax
 1066aeb:	48 c1 f8 3f          	sar    $0x3f,%rax
 1066aef:	48 21 d0             	and    %rdx,%rax
 1066af2:	48 01 f0             	add    %rsi,%rax
 1066af5:	48 39 d0             	cmp    %rdx,%rax
 1066af8:	0f 82 d6 ec ff ff    	jb     10657d4 <my.interpreter::evaluate+0x704>
 1066afe:	48 8d 3d 3b f7 01 00 	lea    0x1f73b(%rip),%rdi        # 1086240 <core_durable_error.verbs+0x6570>
 1066b05:	e8 f6 dc fb ff       	call   1024800 <myl_core_trap>
 1066b0a:	48 89 c6             	mov    %rax,%rsi
 1066b0d:	48 c1 fe 3f          	sar    $0x3f,%rsi
 1066b11:	48 21 d6             	and    %rdx,%rsi
 1066b14:	48 01 c6             	add    %rax,%rsi
 1066b17:	48 39 d6             	cmp    %rdx,%rsi
 1066b1a:	0f 82 cc ec ff ff    	jb     10657ec <my.interpreter::evaluate+0x71c>
 1066b20:	48 8d 3d 79 f7 01 00 	lea    0x1f779(%rip),%rdi        # 10862a0 <core_durable_error.verbs+0x65d0>
 1066b27:	48 89 c6             	mov    %rax,%rsi
 1066b2a:	e8 d1 dc fb ff       	call   1024800 <myl_core_trap>
 1066b2f:	48 89 c7             	mov    %rax,%rdi
 1066b32:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1066b36:	48 21 d7             	and    %rdx,%rdi
 1066b39:	48 01 c7             	add    %rax,%rdi
 1066b3c:	48 39 d7             	cmp    %rdx,%rdi
 1066b3f:	0f 82 e1 f2 ff ff    	jb     1065e26 <my.interpreter::evaluate+0xd56>
 1066b45:	48 8d 3d 24 c1 01 00 	lea    0x1c124(%rip),%rdi        # 1082c70 <core_durable_error.verbs+0x2fa0>
 1066b4c:	48 89 c6             	mov    %rax,%rsi
 1066b4f:	e8 ac dc fb ff       	call   1024800 <myl_core_trap>
 1066b54:	48 89 f1             	mov    %rsi,%rcx
 1066b57:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066b5b:	48 21 d1             	and    %rdx,%rcx
 1066b5e:	48 01 f1             	add    %rsi,%rcx
 1066b61:	48 39 d1             	cmp    %rdx,%rcx
 1066b64:	0f 82 e6 f2 ff ff    	jb     1065e50 <my.interpreter::evaluate+0xd80>
 1066b6a:	48 8d 3d 5f c1 01 00 	lea    0x1c15f(%rip),%rdi        # 1082cd0 <core_durable_error.verbs+0x3000>
 1066b71:	e8 8a dc fb ff       	call   1024800 <myl_core_trap>
 1066b76:	48 89 f1             	mov    %rsi,%rcx
 1066b79:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066b7d:	48 21 d1             	and    %rdx,%rcx
 1066b80:	48 01 f1             	add    %rsi,%rcx
 1066b83:	48 39 d1             	cmp    %rdx,%rcx
 1066b86:	0f 82 e9 f2 ff ff    	jb     1065e75 <my.interpreter::evaluate+0xda5>
 1066b8c:	48 8d 3d 4d f9 01 00 	lea    0x1f94d(%rip),%rdi        # 10864e0 <core_durable_error.verbs+0x6810>
 1066b93:	e8 68 dc fb ff       	call   1024800 <myl_core_trap>
 1066b98:	49 89 c1             	mov    %rax,%r9
 1066b9b:	49 c1 f9 3f          	sar    $0x3f,%r9
 1066b9f:	49 21 d1             	and    %rdx,%r9
 1066ba2:	49 01 c1             	add    %rax,%r9
 1066ba5:	49 39 d1             	cmp    %rdx,%r9
 1066ba8:	0f 82 18 f3 ff ff    	jb     1065ec6 <my.interpreter::evaluate+0xdf6>
 1066bae:	48 8d 3d db ee 01 00 	lea    0x1eedb(%rip),%rdi        # 1085a90 <core_durable_error.verbs+0x5dc0>
 1066bb5:	48 89 c6             	mov    %rax,%rsi
 1066bb8:	e8 43 dc fb ff       	call   1024800 <myl_core_trap>
 1066bbd:	48 89 f7             	mov    %rsi,%rdi
 1066bc0:	48 c1 ff 3f          	sar    $0x3f,%rdi
 1066bc4:	48 21 d7             	and    %rdx,%rdi
 1066bc7:	48 01 f7             	add    %rsi,%rdi
 1066bca:	48 39 d7             	cmp    %rdx,%rdi
 1066bcd:	0f 82 a4 f4 ff ff    	jb     1066077 <my.interpreter::evaluate+0xfa7>
 1066bd3:	48 8d 3d 66 f3 01 00 	lea    0x1f366(%rip),%rdi        # 1085f40 <core_durable_error.verbs+0x6270>
 1066bda:	e8 21 dc fb ff       	call   1024800 <myl_core_trap>
 1066bdf:	49 89 f0             	mov    %rsi,%r8
 1066be2:	49 c1 f8 3f          	sar    $0x3f,%r8
 1066be6:	49 21 c0             	and    %rax,%r8
 1066be9:	49 01 f0             	add    %rsi,%r8
 1066bec:	49 39 c0             	cmp    %rax,%r8
 1066bef:	0f 82 fd f4 ff ff    	jb     10660f2 <my.interpreter::evaluate+0x1022>
 1066bf5:	48 8d 3d 44 f9 01 00 	lea    0x1f944(%rip),%rdi        # 1086540 <core_durable_error.verbs+0x6870>
 1066bfc:	48 89 c2             	mov    %rax,%rdx
 1066bff:	e8 fc db fb ff       	call   1024800 <myl_core_trap>
 1066c04:	48 89 f1             	mov    %rsi,%rcx
 1066c07:	48 c1 f9 3f          	sar    $0x3f,%rcx
 1066c0b:	48 21 d1             	and    %rdx,%rcx
 1066c0e:	48 01 f1             	add    %rsi,%rcx
 1066c11:	48 39 d1             	cmp    %rdx,%rcx
 1066c14:	0f 82 2e f6 ff ff    	jb     1066248 <my.interpreter::evaluate+0x1178>
 1066c1a:	48 8d 3d cf ee 01 00 	lea    0x1eecf(%rip),%rdi        # 1085af0 <core_durable_error.verbs+0x5e20>
 1066c21:	e8 da db fb ff       	call   1024800 <myl_core_trap>
 1066c26:	48 8d 3d a3 ed 01 00 	lea    0x1eda3(%rip),%rdi        # 10859d0 <core_durable_error.verbs+0x5d00>
 1066c2d:	e8 4e 2f fc ff       	call   1029b80 <myl_core_assert_fail>
 1066c32:	48 8d 3d 97 ed 01 00 	lea    0x1ed97(%rip),%rdi        # 10859d0 <core_durable_error.verbs+0x5d00>
 1066c39:	e8 42 2f fc ff       	call   1029b80 <myl_core_assert_fail>
 1066c3e:	48 8d 3d 8b ed 01 00 	lea    0x1ed8b(%rip),%rdi        # 10859d0 <core_durable_error.verbs+0x5d00>
 1066c45:	e8 36 2f fc ff       	call   1029b80 <myl_core_assert_fail>
 1066c4a:	48 8d 3d 7f ed 01 00 	lea    0x1ed7f(%rip),%rdi        # 10859d0 <core_durable_error.verbs+0x5d00>
 1066c51:	e8 2a 2f fc ff       	call   1029b80 <myl_core_assert_fail>
 1066c56:	48 8d 3d 73 ed 01 00 	lea    0x1ed73(%rip),%rdi        # 10859d0 <core_durable_error.verbs+0x5d00>
 1066c5d:	e8 1e 2f fc ff       	call   1029b80 <myl_core_assert_fail>
 1066c62:	0f b6 c0             	movzbl %al,%eax
 1066c65:	83 f8 01             	cmp    $0x1,%eax
 1066c68:	0f 84 cb 00 00 00    	je     1066d39 <my.interpreter::evaluate+0x1c69>
 1066c6e:	85 c0                	test   %eax,%eax
 1066c70:	0f 85 cf 00 00 00    	jne    1066d45 <my.interpreter::evaluate+0x1c75>
 1066c76:	48 8d 3d 63 ec 01 00 	lea    0x1ec63(%rip),%rdi        # 10858e0 <core_durable_error.verbs+0x5c10>
 1066c7d:	e8 fe 2e fc ff       	call   1029b80 <myl_core_assert_fail>
 1066c82:	0f b6 c2             	movzbl %dl,%eax
 1066c85:	83 f8 01             	cmp    $0x1,%eax
 1066c88:	0f 84 13 01 00 00    	je     1066da1 <my.interpreter::evaluate+0x1cd1>
 1066c8e:	85 c0                	test   %eax,%eax
 1066c90:	0f 85 17 01 00 00    	jne    1066dad <my.interpreter::evaluate+0x1cdd>
 1066c96:	48 8d 3d 43 ec 01 00 	lea    0x1ec43(%rip),%rdi        # 10858e0 <core_durable_error.verbs+0x5c10>
 1066c9d:	e8 de 2e fc ff       	call   1029b80 <myl_core_assert_fail>
 1066ca2:	83 fa 01             	cmp    $0x1,%edx
 1066ca5:	0f 84 44 01 00 00    	je     1066def <my.interpreter::evaluate+0x1d1f>
 1066cab:	85 d2                	test   %edx,%edx
 1066cad:	0f 85 48 01 00 00    	jne    1066dfb <my.interpreter::evaluate+0x1d2b>
 1066cb3:	48 8d 3d 26 ec 01 00 	lea    0x1ec26(%rip),%rdi        # 10858e0 <core_durable_error.verbs+0x5c10>
 1066cba:	e8 c1 2e fc ff       	call   1029b80 <myl_core_assert_fail>
 1066cbf:	0f b6 c2             	movzbl %dl,%eax
 1066cc2:	83 f8 01             	cmp    $0x1,%eax
 1066cc5:	0f 84 c1 01 00 00    	je     1066e8c <my.interpreter::evaluate+0x1dbc>
 1066ccb:	85 c0                	test   %eax,%eax
 1066ccd:	0f 85 c5 01 00 00    	jne    1066e98 <my.interpreter::evaluate+0x1dc8>
 1066cd3:	48 8d 3d 06 ec 01 00 	lea    0x1ec06(%rip),%rdi        # 10858e0 <core_durable_error.verbs+0x5c10>
 1066cda:	e8 a1 2e fc ff       	call   1029b80 <myl_core_assert_fail>
 1066cdf:	48 8d 3d 5a c2 01 00 	lea    0x1c25a(%rip),%rdi        # 1082f40 <core_durable_error.verbs+0x3270>
 1066ce6:	ba 01 00 00 00       	mov    $0x1,%edx
 1066ceb:	e8 10 db fb ff       	call   1024800 <myl_core_trap>
 1066cf0:	48 8d 3d a9 bf 01 00 	lea    0x1bfa9(%rip),%rdi        # 1082ca0 <core_durable_error.verbs+0x2fd0>
 1066cf7:	e8 84 2e fc ff       	call   1029b80 <myl_core_assert_fail>
 1066cfc:	48 8d 3d 9d bf 01 00 	lea    0x1bf9d(%rip),%rdi        # 1082ca0 <core_durable_error.verbs+0x2fd0>
 1066d03:	e8 78 2e fc ff       	call   1029b80 <myl_core_assert_fail>
 1066d08:	48 8d 3d 91 c2 01 00 	lea    0x1c291(%rip),%rdi        # 1082fa0 <core_durable_error.verbs+0x32d0>
 1066d0f:	ba 01 00 00 00       	mov    $0x1,%edx
 1066d14:	e8 e7 da fb ff       	call   1024800 <myl_core_trap>
 1066d19:	48 8d 3d b0 f5 01 00 	lea    0x1f5b0(%rip),%rdi        # 10862d0 <core_durable_error.verbs+0x6600>
 1066d20:	ba 01 00 00 00       	mov    $0x1,%edx
 1066d25:	48 89 c6             	mov    %rax,%rsi
 1066d28:	e8 d3 da fb ff       	call   1024800 <myl_core_trap>
 1066d2d:	48 8d 3d 6c bf 01 00 	lea    0x1bf6c(%rip),%rdi        # 1082ca0 <core_durable_error.verbs+0x2fd0>
 1066d34:	e8 47 2e fc ff       	call   1029b80 <myl_core_assert_fail>
 1066d39:	48 8d 3d d0 eb 01 00 	lea    0x1ebd0(%rip),%rdi        # 1085910 <core_durable_error.verbs+0x5c40>
 1066d40:	e8 3b 2e fc ff       	call   1029b80 <myl_core_assert_fail>
 1066d45:	48 8d 3d f4 eb 01 00 	lea    0x1ebf4(%rip),%rdi        # 1085940 <core_durable_error.verbs+0x5c70>
 1066d4c:	e8 2f 2e fc ff       	call   1029b80 <myl_core_assert_fail>
 1066d51:	48 8d 3d 78 f2 01 00 	lea    0x1f278(%rip),%rdi        # 1085fd0 <core_durable_error.verbs+0x6300>
 1066d58:	ba 01 00 00 00       	mov    $0x1,%edx
 1066d5d:	48 89 c6             	mov    %rax,%rsi
 1066d60:	e8 9b da fb ff       	call   1024800 <myl_core_trap>
 1066d65:	48 8d 3d 14 f1 01 00 	lea    0x1f114(%rip),%rdi        # 1085e80 <core_durable_error.verbs+0x61b0>
 1066d6c:	ba 01 00 00 00       	mov    $0x1,%edx
 1066d71:	48 89 c6             	mov    %rax,%rsi
 1066d74:	e8 87 da fb ff       	call   1024800 <myl_core_trap>
 1066d79:	48 8d 3d 40 f3 01 00 	lea    0x1f340(%rip),%rdi        # 10860c0 <core_durable_error.verbs+0x63f0>
 1066d80:	ba 01 00 00 00       	mov    $0x1,%edx
 1066d85:	48 89 c6             	mov    %rax,%rsi
 1066d88:	e8 73 da fb ff       	call   1024800 <myl_core_trap>
 1066d8d:	48 8d 3d bc f6 01 00 	lea    0x1f6bc(%rip),%rdi        # 1086450 <core_durable_error.verbs+0x6780>
 1066d94:	ba 01 00 00 00       	mov    $0x1,%edx
 1066d99:	48 89 c6             	mov    %rax,%rsi
 1066d9c:	e8 5f da fb ff       	call   1024800 <myl_core_trap>
 1066da1:	48 8d 3d 68 eb 01 00 	lea    0x1eb68(%rip),%rdi        # 1085910 <core_durable_error.verbs+0x5c40>
 1066da8:	e8 d3 2d fc ff       	call   1029b80 <myl_core_assert_fail>
 1066dad:	48 8d 3d 8c eb 01 00 	lea    0x1eb8c(%rip),%rdi        # 1085940 <core_durable_error.verbs+0x5c70>
 1066db4:	e8 c7 2d fc ff       	call   1029b80 <myl_core_assert_fail>
 1066db9:	48 8d 3d a0 f5 01 00 	lea    0x1f5a0(%rip),%rdi        # 1086360 <core_durable_error.verbs+0x6690>
 1066dc0:	ba 01 00 00 00       	mov    $0x1,%edx
 1066dc5:	e8 36 da fb ff       	call   1024800 <myl_core_trap>
 1066dca:	48 8d 3d 4f f3 01 00 	lea    0x1f34f(%rip),%rdi        # 1086120 <core_durable_error.verbs+0x6450>
 1066dd1:	ba 01 00 00 00       	mov    $0x1,%edx
 1066dd6:	e8 25 da fb ff       	call   1024800 <myl_core_trap>
 1066ddb:	48 8d 3d 6e f3 01 00 	lea    0x1f36e(%rip),%rdi        # 1086150 <core_durable_error.verbs+0x6480>
 1066de2:	ba 01 00 00 00       	mov    $0x1,%edx
 1066de7:	48 89 c6             	mov    %rax,%rsi
 1066dea:	e8 11 da fb ff       	call   1024800 <myl_core_trap>
 1066def:	48 8d 3d 1a eb 01 00 	lea    0x1eb1a(%rip),%rdi        # 1085910 <core_durable_error.verbs+0x5c40>
 1066df6:	e8 85 2d fc ff       	call   1029b80 <myl_core_assert_fail>
 1066dfb:	48 8d 3d 3e eb 01 00 	lea    0x1eb3e(%rip),%rdi        # 1085940 <core_durable_error.verbs+0x5c70>
 1066e02:	e8 79 2d fc ff       	call   1029b80 <myl_core_assert_fail>
 1066e07:	48 8d 3d a2 f3 01 00 	lea    0x1f3a2(%rip),%rdi        # 10861b0 <core_durable_error.verbs+0x64e0>
 1066e0e:	ba 01 00 00 00       	mov    $0x1,%edx
 1066e13:	48 89 ce             	mov    %rcx,%rsi
 1066e16:	e8 e5 d9 fb ff       	call   1024800 <myl_core_trap>
 1066e1b:	48 8d 3d ee f3 01 00 	lea    0x1f3ee(%rip),%rdi        # 1086210 <core_durable_error.verbs+0x6540>
 1066e22:	ba 01 00 00 00       	mov    $0x1,%edx
 1066e27:	48 89 c6             	mov    %rax,%rsi
 1066e2a:	e8 d1 d9 fb ff       	call   1024800 <myl_core_trap>
 1066e2f:	48 8d 3d 3a f4 01 00 	lea    0x1f43a(%rip),%rdi        # 1086270 <core_durable_error.verbs+0x65a0>
 1066e36:	ba 01 00 00 00       	mov    $0x1,%edx
 1066e3b:	e8 c0 d9 fb ff       	call   1024800 <myl_core_trap>
 1066e40:	48 8d 3d 59 be 01 00 	lea    0x1be59(%rip),%rdi        # 1082ca0 <core_durable_error.verbs+0x2fd0>
 1066e47:	e8 34 2d fc ff       	call   1029b80 <myl_core_assert_fail>
 1066e4c:	48 8d 3d bd f6 01 00 	lea    0x1f6bd(%rip),%rdi        # 1086510 <core_durable_error.verbs+0x6840>
 1066e53:	ba 01 00 00 00       	mov    $0x1,%edx
 1066e58:	e8 a3 d9 fb ff       	call   1024800 <myl_core_trap>
 1066e5d:	48 8d 3d fc eb 01 00 	lea    0x1ebfc(%rip),%rdi        # 1085a60 <core_durable_error.verbs+0x5d90>
 1066e64:	ba 01 00 00 00       	mov    $0x1,%edx
 1066e69:	48 89 ce             	mov    %rcx,%rsi
 1066e6c:	e8 8f d9 fb ff       	call   1024800 <myl_core_trap>
 1066e71:	48 be 00 00 00 00 00 	movabs $0x8000000000000000,%rsi
 1066e78:	00 00 80 
 1066e7b:	48 8d 3d 5e f0 01 00 	lea    0x1f05e(%rip),%rdi        # 1085ee0 <core_durable_error.verbs+0x6210>
 1066e82:	ba 01 00 00 00       	mov    $0x1,%edx
 1066e87:	e8 74 d9 fb ff       	call   1024800 <myl_core_trap>
 1066e8c:	48 8d 3d 7d ea 01 00 	lea    0x1ea7d(%rip),%rdi        # 1085910 <core_durable_error.verbs+0x5c40>
 1066e93:	e8 e8 2c fc ff       	call   1029b80 <myl_core_assert_fail>
 1066e98:	48 8d 3d a1 ea 01 00 	lea    0x1eaa1(%rip),%rdi        # 1085940 <core_durable_error.verbs+0x5c70>
 1066e9f:	e8 dc 2c fc ff       	call   1029b80 <myl_core_assert_fail>
 1066ea4:	48 8d 3d 65 f0 01 00 	lea    0x1f065(%rip),%rdi        # 1085f10 <core_durable_error.verbs+0x6240>
 1066eab:	ba 01 00 00 00       	mov    $0x1,%edx
 1066eb0:	48 89 c6             	mov    %rax,%rsi
 1066eb3:	e8 48 d9 fb ff       	call   1024800 <myl_core_trap>
 1066eb8:	48 8d 3d b1 f6 01 00 	lea    0x1f6b1(%rip),%rdi        # 1086570 <core_durable_error.verbs+0x68a0>
 1066ebf:	ba 01 00 00 00       	mov    $0x1,%edx
 1066ec4:	e8 37 d9 fb ff       	call   1024800 <myl_core_trap>
 1066ec9:	48 8d 3d f0 eb 01 00 	lea    0x1ebf0(%rip),%rdi        # 1085ac0 <core_durable_error.verbs+0x5df0>
 1066ed0:	ba 01 00 00 00       	mov    $0x1,%edx
 1066ed5:	48 89 c6             	mov    %rax,%rsi
 1066ed8:	e8 23 d9 fb ff       	call   1024800 <myl_core_trap>

Disassembly of section .plt:
