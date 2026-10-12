
.tmp/text-gaps/span-index/proof-native:     file format elf64-x86-64


Disassembly of section .text:

0000000001040310 <main>:
 1040310:	55                   	push   %rbp
 1040311:	41 57                	push   %r15
 1040313:	41 56                	push   %r14
 1040315:	41 54                	push   %r12
 1040317:	53                   	push   %rbx
 1040318:	48 83 ec 10          	sub    $0x10,%rsp
 104031c:	48 89 f3             	mov    %rsi,%rbx
 104031f:	89 fd                	mov    %edi,%ebp
 1040321:	e8 5a 4e ff ff       	call   1035180 <myl_core_start>
 1040326:	89 ef                	mov    %ebp,%edi
 1040328:	48 89 de             	mov    %rbx,%rsi
 104032b:	e8 d0 d3 fc ff       	call   100d700 <myl_core_args>
 1040330:	48 8b 50 08          	mov    0x8(%rax),%rdx
 1040334:	48 85 d2             	test   %rdx,%rdx
 1040337:	0f 84 31 03 00 00    	je     104066e <main+0x35e>
 104033d:	48 89 c3             	mov    %rax,%rbx
 1040340:	48 8b 78 20          	mov    0x20(%rax),%rdi
 1040344:	48 8b 77 08          	mov    0x8(%rdi),%rsi
 1040348:	41 be 02 00 00 00    	mov    $0x2,%r14d
 104034e:	48 85 f6             	test   %rsi,%rsi
 1040351:	0f 84 e0 03 00 00    	je     1040737 <main+0x427>
 1040357:	48 83 c7 20          	add    $0x20,%rdi
 104035b:	0f b6 07             	movzbl (%rdi),%eax
 104035e:	8d 48 d5             	lea    -0x2b(%rax),%ecx
 1040361:	45 31 c0             	xor    %r8d,%r8d
 1040364:	f6 c1 fd             	test   $0xfd,%cl
 1040367:	0f 94 c1             	sete   %cl
 104036a:	41 0f 95 c2          	setne  %r10b
 104036e:	44 8d 48 d0          	lea    -0x30(%rax),%r9d
 1040372:	41 80 f9 0a          	cmp    $0xa,%r9b
 1040376:	41 0f 93 c3          	setae  %r11b
 104037a:	44 0f b6 4c 37 ff    	movzbl -0x1(%rdi,%rsi,1),%r9d
 1040380:	45 84 d3             	test   %r10b,%r11b
 1040383:	75 2b                	jne    10403b0 <main+0xa0>
 1040385:	45 8d 51 d0          	lea    -0x30(%r9),%r10d
 1040389:	41 80 fa 0a          	cmp    $0xa,%r10b
 104038d:	73 21                	jae    10403b0 <main+0xa0>
 104038f:	41 88 c8             	mov    %cl,%r8b
 1040392:	48 89 f1             	mov    %rsi,%rcx
 1040395:	4c 29 c1             	sub    %r8,%rcx
 1040398:	48 83 f9 08          	cmp    $0x8,%rcx
 104039c:	0f 87 a7 01 00 00    	ja     1040549 <main+0x239>
 10403a2:	49 01 f8             	add    %rdi,%r8
 10403a5:	48 83 f9 08          	cmp    $0x8,%rcx
 10403a9:	75 1c                	jne    10403c7 <main+0xb7>
 10403ab:	4d 8b 00             	mov    (%r8),%r8
 10403ae:	eb 39                	jmp    10403e9 <main+0xd9>
 10403b0:	3c 21                	cmp    $0x21,%al
 10403b2:	0f 82 91 01 00 00    	jb     1040549 <main+0x239>
 10403b8:	41 80 f9 21          	cmp    $0x21,%r9b
 10403bc:	0f 83 75 03 00 00    	jae    1040737 <main+0x427>
 10403c2:	e9 82 01 00 00       	jmp    1040549 <main+0x239>
 10403c7:	48 83 f9 04          	cmp    $0x4,%rcx
 10403cb:	0f 86 bf 00 00 00    	jbe    1040490 <main+0x180>
 10403d1:	45 8b 08             	mov    (%r8),%r9d
 10403d4:	4c 8d 51 fc          	lea    -0x4(%rcx),%r10
 10403d8:	45 8b 44 08 fc       	mov    -0x4(%r8,%rcx,1),%r8d
 10403dd:	41 c1 e2 03          	shl    $0x3,%r10d
 10403e1:	c4 42 a9 f7 c0       	shlx   %r10,%r8,%r8
 10403e6:	4d 09 c8             	or     %r9,%r8
 10403e9:	c1 e1 03             	shl    $0x3,%ecx
 10403ec:	41 89 c9             	mov    %ecx,%r9d
 10403ef:	41 f6 d9             	neg    %r9b
 10403f2:	c4 42 b1 f7 c0       	shlx   %r9,%r8,%r8
 10403f7:	41 b1 40             	mov    $0x40,%r9b
 10403fa:	41 28 c9             	sub    %cl,%r9b
 10403fd:	48 b9 30 30 30 30 30 	movabs $0x30303030303030,%rcx
 1040404:	30 30 00 
 1040407:	c4 e2 b0 f5 c9       	bzhi   %r9,%rcx,%rcx
 104040c:	4c 09 c1             	or     %r8,%rcx
 104040f:	49 b8 d0 cf cf cf cf 	movabs $0xcfcfcfcfcfcfcfd0,%r8
 1040416:	cf cf cf 
 1040419:	49 01 c8             	add    %rcx,%r8
 104041c:	49 b9 46 46 46 46 46 	movabs $0x4646464646464646,%r9
 1040423:	46 46 46 
 1040426:	49 01 c9             	add    %rcx,%r9
 1040429:	4d 09 c1             	or     %r8,%r9
 104042c:	48 b9 80 80 80 80 80 	movabs $0x8080808080808080,%rcx
 1040433:	80 80 80 
 1040436:	49 85 c9             	test   %rcx,%r9
 1040439:	0f 94 c1             	sete   %cl
 104043c:	4f 8d 0c 80          	lea    (%r8,%r8,4),%r9
 1040440:	49 c1 e8 08          	shr    $0x8,%r8
 1040444:	4f 8d 04 48          	lea    (%r8,%r9,2),%r8
 1040448:	4d 89 c1             	mov    %r8,%r9
 104044b:	49 c1 e9 10          	shr    $0x10,%r9
 104044f:	49 ba ff 00 00 00 ff 	movabs $0xff000000ff,%r10
 1040456:	00 00 00 
 1040459:	4d 21 d0             	and    %r10,%r8
 104045c:	4d 21 d1             	and    %r10,%r9
 104045f:	49 ba 64 00 00 00 40 	movabs $0xf424000000064,%r10
 1040466:	42 0f 00 
 1040469:	4d 0f af d0          	imul   %r8,%r10
 104046d:	49 b8 01 00 00 00 10 	movabs $0x271000000001,%r8
 1040474:	27 00 00 
 1040477:	4d 0f af c1          	imul   %r9,%r8
 104047b:	4d 01 d0             	add    %r10,%r8
 104047e:	49 c1 e8 20          	shr    $0x20,%r8
 1040482:	f6 c1 01             	test   $0x1,%cl
 1040485:	0f 85 a1 00 00 00    	jne    104052c <main+0x21c>
 104048b:	e9 b9 00 00 00       	jmp    1040549 <main+0x239>
 1040490:	4c 8d 49 ff          	lea    -0x1(%rcx),%r9
 1040494:	49 83 f9 03          	cmp    $0x3,%r9
 1040498:	0f 87 a1 00 00 00    	ja     104053f <main+0x22f>
 104049e:	4c 8d 15 bb 55 fc ff 	lea    -0x3aa45(%rip),%r10        # 1005a60 <core_number_pairs+0xe0>
 10404a5:	4f 63 0c 8a          	movslq (%r10,%r9,4),%r9
 10404a9:	4d 01 d1             	add    %r10,%r9
 10404ac:	41 ff e1             	jmp    *%r9
 10404af:	45 0f b6 00          	movzbl (%r8),%r8d
 10404b3:	eb 1b                	jmp    10404d0 <main+0x1c0>
 10404b5:	45 0f b7 08          	movzwl (%r8),%r9d
 10404b9:	45 0f b6 40 02       	movzbl 0x2(%r8),%r8d
 10404be:	41 c1 e0 10          	shl    $0x10,%r8d
 10404c2:	45 09 c8             	or     %r9d,%r8d
 10404c5:	eb 09                	jmp    10404d0 <main+0x1c0>
 10404c7:	45 8b 00             	mov    (%r8),%r8d
 10404ca:	eb 04                	jmp    10404d0 <main+0x1c0>
 10404cc:	45 0f b7 00          	movzwl (%r8),%r8d
 10404d0:	c1 e1 03             	shl    $0x3,%ecx
 10404d3:	41 89 c9             	mov    %ecx,%r9d
 10404d6:	41 f6 d9             	neg    %r9b
 10404d9:	c4 42 31 f7 c0       	shlx   %r9d,%r8d,%r8d
 10404de:	41 b1 20             	mov    $0x20,%r9b
 10404e1:	41 28 c9             	sub    %cl,%r9b
 10404e4:	b9 30 30 30 00       	mov    $0x303030,%ecx
 10404e9:	c4 e2 30 f5 c9       	bzhi   %r9d,%ecx,%ecx
 10404ee:	44 09 c1             	or     %r8d,%ecx
 10404f1:	44 8d 81 d0 cf cf cf 	lea    -0x30303030(%rcx),%r8d
 10404f8:	81 c1 46 46 46 46    	add    $0x46464646,%ecx
 10404fe:	44 09 c1             	or     %r8d,%ecx
 1040501:	f7 c1 80 80 80 80    	test   $0x80808080,%ecx
 1040507:	0f 94 c1             	sete   %cl
 104050a:	45 69 c0 01 0a 00 00 	imul   $0xa01,%r8d,%r8d
 1040511:	41 c1 e8 08          	shr    $0x8,%r8d
 1040515:	41 81 e0 ff 00 ff 00 	and    $0xff00ff,%r8d
 104051c:	45 69 c0 01 00 64 00 	imul   $0x640001,%r8d,%r8d
 1040523:	41 c1 e8 10          	shr    $0x10,%r8d
 1040527:	f6 c1 01             	test   $0x1,%cl
 104052a:	74 1d                	je     1040549 <main+0x239>
 104052c:	4d 89 c6             	mov    %r8,%r14
 104052f:	49 f7 de             	neg    %r14
 1040532:	3c 2d                	cmp    $0x2d,%al
 1040534:	4d 0f 45 f0          	cmovne %r8,%r14
 1040538:	4c 89 74 24 08       	mov    %r14,0x8(%rsp)
 104053d:	eb 25                	jmp    1040564 <main+0x254>
 104053f:	31 c9                	xor    %ecx,%ecx
 1040541:	45 31 c0             	xor    %r8d,%r8d
 1040544:	f6 c1 01             	test   $0x1,%cl
 1040547:	75 e3                	jne    104052c <main+0x21c>
 1040549:	48 8d 54 24 08       	lea    0x8(%rsp),%rdx
 104054e:	e8 6d 55 fe ff       	call   1025ac0 <myl_core_span_parse_int>
 1040553:	84 c0                	test   %al,%al
 1040555:	0f 84 dc 01 00 00    	je     1040737 <main+0x427>
 104055b:	4c 8b 74 24 08       	mov    0x8(%rsp),%r14
 1040560:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 1040564:	48 83 fa 02          	cmp    $0x2,%rdx
 1040568:	0f 82 10 01 00 00    	jb     104067e <main+0x36e>
 104056e:	48 8b 43 28          	mov    0x28(%rbx),%rax
 1040572:	48 8b 48 08          	mov    0x8(%rax),%rcx
 1040576:	48 85 c9             	test   %rcx,%rcx
 1040579:	74 10                	je     104058b <main+0x27b>
 104057b:	48 83 f9 04          	cmp    $0x4,%rcx
 104057f:	73 12                	jae    1040593 <main+0x283>
 1040581:	45 31 ff             	xor    %r15d,%r15d
 1040584:	31 d2                	xor    %edx,%edx
 1040586:	e9 04 01 00 00       	jmp    104068f <main+0x37f>
 104058b:	45 31 ff             	xor    %r15d,%r15d
 104058e:	e9 0c 01 00 00       	jmp    104069f <main+0x38f>
 1040593:	48 83 f9 10          	cmp    $0x10,%rcx
 1040597:	73 0a                	jae    10405a3 <main+0x293>
 1040599:	31 d2                	xor    %edx,%edx
 104059b:	45 31 ff             	xor    %r15d,%r15d
 104059e:	e9 84 00 00 00       	jmp    1040627 <main+0x317>
 10405a3:	48 89 ca             	mov    %rcx,%rdx
 10405a6:	48 83 e2 f0          	and    $0xfffffffffffffff0,%rdx
 10405aa:	c5 f9 ef c0          	vpxor  %xmm0,%xmm0,%xmm0
 10405ae:	31 f6                	xor    %esi,%esi
 10405b0:	c5 f1 ef c9          	vpxor  %xmm1,%xmm1,%xmm1
 10405b4:	c5 e9 ef d2          	vpxor  %xmm2,%xmm2,%xmm2
 10405b8:	c5 e1 ef db          	vpxor  %xmm3,%xmm3,%xmm3
 10405bc:	0f 1f 40 00          	nopl   0x0(%rax)
 10405c0:	c4 e2 7d 32 64 30 20 	vpmovzxbq 0x20(%rax,%rsi,1),%ymm4
 10405c7:	c5 fd d4 c4          	vpaddq %ymm4,%ymm0,%ymm0
 10405cb:	c4 e2 7d 32 64 30 24 	vpmovzxbq 0x24(%rax,%rsi,1),%ymm4
 10405d2:	c5 f5 d4 cc          	vpaddq %ymm4,%ymm1,%ymm1
 10405d6:	c4 e2 7d 32 64 30 28 	vpmovzxbq 0x28(%rax,%rsi,1),%ymm4
 10405dd:	c5 ed d4 d4          	vpaddq %ymm4,%ymm2,%ymm2
 10405e1:	c4 e2 7d 32 64 30 2c 	vpmovzxbq 0x2c(%rax,%rsi,1),%ymm4
 10405e8:	c5 e5 d4 dc          	vpaddq %ymm4,%ymm3,%ymm3
 10405ec:	48 83 c6 10          	add    $0x10,%rsi
 10405f0:	48 39 f2             	cmp    %rsi,%rdx
 10405f3:	75 cb                	jne    10405c0 <main+0x2b0>
 10405f5:	c5 f5 d4 c0          	vpaddq %ymm0,%ymm1,%ymm0
 10405f9:	c5 ed d4 c0          	vpaddq %ymm0,%ymm2,%ymm0
 10405fd:	c5 e5 d4 c0          	vpaddq %ymm0,%ymm3,%ymm0
 1040601:	c4 e3 7d 39 c1 01    	vextracti128 $0x1,%ymm0,%xmm1
 1040607:	c5 f9 d4 c1          	vpaddq %xmm1,%xmm0,%xmm0
 104060b:	c5 f9 70 c8 ee       	vpshufd $0xee,%xmm0,%xmm1
 1040610:	c5 f9 d4 c1          	vpaddq %xmm1,%xmm0,%xmm0
 1040614:	c4 c1 f9 7e c7       	vmovq  %xmm0,%r15
 1040619:	48 39 d1             	cmp    %rdx,%rcx
 104061c:	0f 84 7d 00 00 00    	je     104069f <main+0x38f>
 1040622:	f6 c1 0c             	test   $0xc,%cl
 1040625:	74 68                	je     104068f <main+0x37f>
 1040627:	48 89 d6             	mov    %rdx,%rsi
 104062a:	48 89 ca             	mov    %rcx,%rdx
 104062d:	48 83 e2 fc          	and    $0xfffffffffffffffc,%rdx
 1040631:	c4 c1 f9 6e c7       	vmovq  %r15,%xmm0
 1040636:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
 104063d:	00 00 00 
 1040640:	c4 e2 7d 32 4c 30 20 	vpmovzxbq 0x20(%rax,%rsi,1),%ymm1
 1040647:	c5 fd d4 c1          	vpaddq %ymm1,%ymm0,%ymm0
 104064b:	48 83 c6 04          	add    $0x4,%rsi
 104064f:	48 39 f2             	cmp    %rsi,%rdx
 1040652:	75 ec                	jne    1040640 <main+0x330>
 1040654:	c4 e3 7d 39 c1 01    	vextracti128 $0x1,%ymm0,%xmm1
 104065a:	c5 f9 d4 c1          	vpaddq %xmm1,%xmm0,%xmm0
 104065e:	c5 f9 70 c8 ee       	vpshufd $0xee,%xmm0,%xmm1
 1040663:	c5 f9 d4 c1          	vpaddq %xmm1,%xmm0,%xmm0
 1040667:	c4 c1 f9 7e c7       	vmovq  %xmm0,%r15
 104066c:	eb 2c                	jmp    104069a <main+0x38a>
 104066e:	48 8d 3d 4b 19 00 00 	lea    0x194b(%rip),%rdi        # 1041fc0 <core_durable_error.verbs+0x30>
 1040675:	31 f6                	xor    %esi,%esi
 1040677:	31 d2                	xor    %edx,%edx
 1040679:	e8 82 d4 fc ff       	call   100db00 <myl_core_trap>
 104067e:	48 8d 3d 6b 19 00 00 	lea    0x196b(%rip),%rdi        # 1041ff0 <core_durable_error.verbs+0x60>
 1040685:	be 01 00 00 00       	mov    $0x1,%esi
 104068a:	e8 71 d4 fc ff       	call   100db00 <myl_core_trap>
 104068f:	0f b6 74 10 20       	movzbl 0x20(%rax,%rdx,1),%esi
 1040694:	49 01 f7             	add    %rsi,%r15
 1040697:	48 ff c2             	inc    %rdx
 104069a:	48 39 d1             	cmp    %rdx,%rcx
 104069d:	75 f0                	jne    104068f <main+0x37f>
 104069f:	48 8d 35 fa 54 fc ff 	lea    -0x3ab06(%rip),%rsi        # 1005ba0 <core_number_pairs+0x220>
 10406a6:	bf 01 00 00 00       	mov    $0x1,%edi
 10406ab:	c5 f8 77             	vzeroupper
 10406ae:	e8 cd ae fc ff       	call   100b580 <myl_core_print_str>
 10406b3:	bf 01 00 00 00       	mov    $0x1,%edi
 10406b8:	e8 43 af fc ff       	call   100b600 <myl_core_print_sep>
 10406bd:	bf 01 00 00 00       	mov    $0x1,%edi
 10406c2:	4c 89 fe             	mov    %r15,%rsi
 10406c5:	e8 36 ea fc ff       	call   100f100 <myl_core_print_i64>
 10406ca:	bf 01 00 00 00       	mov    $0x1,%edi
 10406cf:	e8 6c af fc ff       	call   100b640 <myl_core_print_end>
 10406d4:	48 8b 53 08          	mov    0x8(%rbx),%rdx
 10406d8:	4d 85 f6             	test   %r14,%r14
 10406db:	74 2a                	je     1040707 <main+0x3f7>
 10406dd:	48 83 fa 01          	cmp    $0x1,%rdx
 10406e1:	76 71                	jbe    1040754 <main+0x444>
 10406e3:	4c 8b 7b 28          	mov    0x28(%rbx),%r15
 10406e7:	4d 8b 67 08          	mov    0x8(%r15),%r12
 10406eb:	49 83 c7 20          	add    $0x20,%r15
 10406ef:	4c 89 ff             	mov    %r15,%rdi
 10406f2:	4c 89 e6             	mov    %r12,%rsi
 10406f5:	4c 89 f2             	mov    %r14,%rdx
 10406f8:	e8 43 1a ff ff       	call   1032140 <myl_core_span_bytes_index_offset>
 10406fd:	4c 39 e0             	cmp    %r12,%rax
 1040700:	73 63                	jae    1040765 <main+0x455>
 1040702:	49 01 c7             	add    %rax,%r15
 1040705:	eb 15                	jmp    104071c <main+0x40c>
 1040707:	48 83 fa 01          	cmp    $0x1,%rdx
 104070b:	76 6a                	jbe    1040777 <main+0x467>
 104070d:	4c 8b 7b 28          	mov    0x28(%rbx),%r15
 1040711:	49 83 7f 08 00       	cmpq   $0x0,0x8(%r15)
 1040716:	74 70                	je     1040788 <main+0x478>
 1040718:	49 83 c7 20          	add    $0x20,%r15
 104071c:	41 0f b6 37          	movzbl (%r15),%esi
 1040720:	bf 01 00 00 00       	mov    $0x1,%edi
 1040725:	e8 d6 e9 fc ff       	call   100f100 <myl_core_print_i64>
 104072a:	bf 01 00 00 00       	mov    $0x1,%edi
 104072f:	e8 0c af fc ff       	call   100b640 <myl_core_print_end>
 1040734:	45 31 f6             	xor    %r14d,%r14d
 1040737:	48 89 df             	mov    %rbx,%rdi
 104073a:	e8 41 c6 fc ff       	call   100cd80 <myl_core_drop_owned>
 104073f:	4c 89 f7             	mov    %r14,%rdi
 1040742:	e8 79 de fc ff       	call   100e5c0 <myl_core_exit>
 1040747:	48 83 c4 10          	add    $0x10,%rsp
 104074b:	5b                   	pop    %rbx
 104074c:	41 5c                	pop    %r12
 104074e:	41 5e                	pop    %r14
 1040750:	41 5f                	pop    %r15
 1040752:	5d                   	pop    %rbp
 1040753:	c3                   	ret
 1040754:	48 8d 3d f5 18 00 00 	lea    0x18f5(%rip),%rdi        # 1042050 <core_durable_error.verbs+0xc0>
 104075b:	be 01 00 00 00       	mov    $0x1,%esi
 1040760:	e8 9b d3 fc ff       	call   100db00 <myl_core_trap>
 1040765:	48 8d 3d 44 19 00 00 	lea    0x1944(%rip),%rdi        # 10420b0 <core_durable_error.verbs+0x120>
 104076c:	4c 89 f6             	mov    %r14,%rsi
 104076f:	4c 89 e2             	mov    %r12,%rdx
 1040772:	e8 89 d3 fc ff       	call   100db00 <myl_core_trap>
 1040777:	48 8d 3d a2 18 00 00 	lea    0x18a2(%rip),%rdi        # 1042020 <core_durable_error.verbs+0x90>
 104077e:	be 01 00 00 00       	mov    $0x1,%esi
 1040783:	e8 78 d3 fc ff       	call   100db00 <myl_core_trap>
 1040788:	48 8d 3d f1 18 00 00 	lea    0x18f1(%rip),%rdi        # 1042080 <core_durable_error.verbs+0xf0>
 104078f:	31 f6                	xor    %esi,%esi
 1040791:	31 d2                	xor    %edx,%edx
 1040793:	e8 68 d3 fc ff       	call   100db00 <myl_core_trap>

Disassembly of section .plt:
