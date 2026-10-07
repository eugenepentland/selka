 1033307:	xor    %r11d,%r11d
 103330a:	mov    0x10(%rsp),%r10
 103330f:	mov    %rax,0x40(%rsp)
 1033314:	movabs $0x100000000000001,%r12
 103331e:	vxorps %xmm1,%xmm1,%xmm1
 1033322:	xor    %ebp,%ebp
 1033324:	xor    %edx,%edx
 1033326:	lea    0x26843(%rip),%r9        # 1059b70 <myl_core_free_lists>
 103332d:	mov    0x8(%rsp),%r8
 1033332:	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033340:	mov    0x30(%rsp),%rax
 1033345:	add    %rdx,%rax
 1033348:	mov    %rax,0x60(%rsp)
 103334d:	jo     103426c <main+0x166c>
 1033353:	mov    0x8(%r9),%r13
 1033357:	test   %r13,%r13
 103335a:	je     1033a7c <main+0xe7c>
 1033360:	mov    0x0(%r13),%rax
 1033364:	mov    %rax,0x8(%r9)
 1033368:	mov    %r12,0x0(%r13)
 103336c:	vmovups %xmm1,0x8(%r13)
 1033372:	movq   $0x0,0x18(%r13)
 103337a:	mov    0x8(%r9),%rcx
 103337e:	test   %rcx,%rcx
 1033381:	lea    -0x2ed78(%rip),%r15        # 1004610 <core_number_pairs+0xe0>
 1033388:	je     1033ab1 <main+0xeb1>
 103338e:	mov    (%rcx),%rax
 1033391:	mov    %rax,0x8(%r9)
 1033395:	mov    %r12,(%rcx)
 1033398:	vmovups %xmm1,0x8(%rcx)
 103339d:	mov    %rcx,0x18(%rsp)
 10333a2:	movq   $0x0,0x18(%rcx)
 10333aa:	mov    0x10(%r9),%rdi
 10333ae:	test   %rdi,%rdi
 10333b1:	je     1033ae8 <main+0xee8>
 10333b7:	mov    (%rdi),%rax
 10333ba:	mov    %rax,0x10(%r9)
 10333be:	vmovaps -0x2fce6(%rip),%ymm0        # 10036e0 <core_io_raw_layout+0x160>
 10333c6:	vmovups %ymm0,(%rdi)
 10333ca:	mov    $0x4,%ecx
 10333cf:	xor    %esi,%esi
 10333d1:	movq   $0x0,0x20(%rdi,%rsi,8)
 10333da:	inc    %rsi
 10333dd:	mov    %rsi,0x8(%rdi)
 10333e1:	cmp    %rcx,%rsi
 10333e4:	jae    1033b46 <main+0xf46>
 10333ea:	movq   $0x0,0x20(%rdi,%rsi,8)
 10333f3:	inc    %rsi
 10333f6:	mov    %rsi,0x8(%rdi)
 10333fa:	cmpq   $0x0,0x8(%r10)
 10333ff:	je     1033c2e <main+0x102e>
 1033405:	mov    %rbp,0x38(%rsp)
 103340a:	mov    %rdx,0x58(%rsp)
 103340f:	xor    %esi,%esi
 1033411:	xor    %eax,%eax
 1033413:	mov    %rax,%rbp
 1033416:	jmp    1033487 <main+0x887>
 1033418:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033427:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
 1033436:	cs nopw 0x0(%rax,%rax,1)
 1033440:	mov    0x8(%r13),%rax
 1033444:	cmp    0x10(%r13),%rax
 1033448:	jae    10337da <main+0xbda>
 103344e:	mov    %rax,%rcx
 1033451:	shl    $0x4,%rcx
 1033455:	movq   $0x0,0x20(%r13,%rcx,1)
 103345e:	mov    %r14,0x28(%r13,%rcx,1)
 1033463:	inc    %rax
 1033466:	mov    %rax,0x8(%r13)
 103346a:	mov    0x8(%r10),%rdx
 103346e:	mov    %rbp,%rsi
 1033471:	sar    $0x3f,%rsi
 1033475:	and    %rdx,%rsi
 1033478:	add    %rbp,%rsi
 103347b:	mov    %rbp,%rax
 103347e:	cmp    %rdx,%rsi
 1033481:	jae    1033c32 <main+0x1032>
 1033487:	inc    %rbp
 103348a:	jo     1033d13 <main+0x1113>
 1033490:	shl    $0x4,%rsi
 1033494:	mov    (%rbx,%rsi,1),%rcx
 1033498:	mov    0x8(%rbx,%rsi,1),%r14
 103349d:	cmp    $0x4,%rcx
 10334a1:	ja     1033577 <main+0x977>
 10334a7:	movslq (%r15,%rcx,4),%rax
 10334ab:	add    %r15,%rax
 10334ae:	jmp    *%rax
 10334b0:	mov    0x8(%r13),%rax
 10334b4:	cmp    0x10(%r13),%rax
 10334b8:	jae    1033814 <main+0xc14>
 10334be:	mov    %rax,%rcx
 10334c1:	shl    $0x4,%rcx
 10334c5:	movq   $0x0,0x20(%r13,%rcx,1)
 10334ce:	mov    0x60(%rsp),%rdx
 10334d3:	mov    %rdx,0x28(%r13,%rcx,1)
 10334d8:	jmp    1033463 <main+0x863>
 10334da:	mov    0x8(%r13),%rdx
 10334de:	test   %rdx,%rdx
 10334e1:	je     1033d39 <main+0x1139>
 10334e7:	dec    %rdx
 10334ea:	mov    %rdx,%rax
 10334ed:	shl    $0x4,%rax
 10334f1:	movzbl 0x20(%r13,%rax,1),%ecx
 10334f7:	mov    0x28(%r13,%rax,1),%rax
 10334fc:	mov    %rdx,0x8(%r13)
 1033500:	mov    0x8(%rdi),%rdx
 1033504:	mov    %r14,%rsi
 1033507:	sar    $0x3f,%rsi
 103350b:	and    %rdx,%rsi
 103350e:	add    %r14,%rsi
 1033511:	cmp    %rdx,%rsi
 1033514:	jae    1033d2a <main+0x112a>
 103351a:	test   %rcx,%rcx
 103351d:	cmovne %r11,%rax
 1033521:	mov    %rax,0x20(%rdi,%rsi,8)
 1033526:	jmp    103346a <main+0x86a>
 103352b:	mov    0x8(%rdi),%rdx
 103352f:	mov    %r14,%rsi
 1033532:	sar    $0x3f,%rsi
 1033536:	and    %rdx,%rsi
 1033539:	add    %r14,%rsi
 103353c:	cmp    %rdx,%rsi
 103353f:	jae    1033d4c <main+0x114c>
 1033545:	mov    0x20(%rdi,%rsi,8),%r14
 103354a:	jmp    1033440 <main+0x840>
 103354f:	mov    0x8(%r13),%rax
 1033553:	cmp    0x10(%r13),%rax
 1033557:	jae    103384e <main+0xc4e>
 103355d:	mov    %rax,%rcx
 1033560:	shl    $0x4,%rcx
 1033564:	movq   $0x0,0x20(%r13,%rcx,1)
 103356d:	mov    %r8,0x28(%r13,%rcx,1)
 1033572:	jmp    1033463 <main+0x863>
 1033577:	lea    -0x5(%rcx),%rax
 103357b:	cmp    $0x5,%rax
 103357f:	jae    10335a8 <main+0x9a8>
 1033581:	mov    0x8(%r13),%rcx
 1033585:	test   %rcx,%rcx
 1033588:	je     1033d6e <main+0x116e>
 103358e:	lea    -0x1(%rcx),%rdx
 1033592:	mov    %rdx,%rsi
 1033595:	shl    $0x4,%rsi
 1033599:	cmpb   $0x0,0x20(%r13,%rsi,1)
 103359f:	jne    10335ff <main+0x9ff>
 10335a1:	mov    0x28(%r13,%rsi,1),%r14
 10335a6:	jmp    1033602 <main+0xa02>
 10335a8:	add    $0xfffffffffffffff6,%rcx
 10335ac:	cmp    $0x3,%rcx
 10335b0:	ja     1033980 <main+0xd80>
 10335b6:	lea    -0x2ef99(%rip),%rdx        # 1004624 <core_number_pairs+0xf4>
 10335bd:	movslq (%rdx,%rcx,4),%rax
 10335c1:	add    %rdx,%rax
 10335c4:	jmp    *%rax
 10335c6:	mov    0x8(%r13),%rax
 10335ca:	test   %rax,%rax
 10335cd:	je     10341e8 <main+0x15e8>
 10335d3:	dec    %rax
 10335d6:	mov    %rax,%rcx
 10335d9:	shl    $0x4,%rcx
 10335dd:	movzbl 0x20(%r13,%rcx,1),%edx
 10335e3:	mov    0x28(%r13,%rcx,1),%rcx
 10335e8:	mov    %rax,0x8(%r13)
 10335ec:	test   $0x1,%cl
 10335ef:	cmove  %r14,%rbp
 10335f3:	cmp    $0x1,%dl
 10335f6:	cmovne %r14,%rbp
 10335fa:	jmp    103346a <main+0x86a>
 10335ff:	xor    %r14d,%r14d
 1033602:	mov    %rdx,0x8(%r13)
 1033606:	test   %rdx,%rdx
 1033609:	je     1033d5b <main+0x115b>
 103360f:	mov    %rcx,%rdx
 1033612:	shl    $0x4,%rdx
 1033616:	cmpb   $0x0,0x0(%r13,%rdx,1)
 103361c:	jne    1033625 <main+0xa25>
 103361e:	mov    0x8(%r13,%rdx,1),%r12
 1033623:	jmp    1033628 <main+0xa28>
 1033625:	xor    %r12d,%r12d
 1033628:	add    $0xfffffffffffffffe,%rcx
 103362c:	mov    %rcx,0x8(%r13)
 1033630:	cmp    $0x3,%rax
 1033634:	ja     103375b <main+0xb5b>
 103363a:	lea    -0x2f00d(%rip),%rdx        # 1004634 <core_number_pairs+0x104>
 1033641:	movslq (%rdx,%rax,4),%rax
 1033645:	add    %rdx,%rax
 1033648:	jmp    *%rax
 103364a:	mov    %r12,%r15
 103364d:	add    %r14,%r15
 1033650:	jno    103371a <main+0xb1a>
 1033656:	jmp    1034237 <main+0x1637>
 103365b:	mov    0x18(%rsp),%rax
 1033660:	mov    0x8(%rax),%rcx
 1033664:	cmp    0x10(%rax),%rcx
 1033668:	jae    1033888 <main+0xc88>
 103366e:	mov    %rbp,0x20(%rax,%rcx,8)
 1033673:	inc    %rcx
 1033676:	mov    %rax,0x18(%rsp)
 103367b:	mov    %rcx,0x8(%rax)
 103367f:	mov    %r14,%rbp
 1033682:	jmp    103346a <main+0x86a>
 1033687:	mov    0x18(%rsp),%rcx
 103368c:	mov    0x8(%rcx),%rax
 1033690:	test   %rax,%rax
 1033693:	je     10341fb <main+0x15fb>
 1033699:	mov    0x18(%rcx,%rax,8),%rbp
 103369e:	dec    %rax
 10336a1:	mov    %rax,0x8(%rcx)
 10336a5:	jmp    103346a <main+0x86a>
 10336aa:	mov    %r14,%rbp
 10336ad:	jmp    103346a <main+0x86a>
 10336b2:	test   %r14,%r14
 10336b5:	je     1034223 <main+0x1623>
 10336bb:	cmp    $0xffffffffffffffff,%r14
 10336bf:	mov    %r14,%rsi
 10336c2:	mov    $0x1,%eax
 10336c7:	cmove  %rax,%rsi
 10336cb:	mov    %r12,%rax
 10336ce:	or     %rsi,%rax
 10336d1:	shr    $0x20,%rax
 10336d5:	je     103378a <main+0xb8a>
 10336db:	mov    %r12,%rax
 10336de:	cqto
 10336e0:	idiv   %rsi
 10336e3:	jmp    1033791 <main+0xb91>
 10336e8:	cmp    0x10(%r13),%rcx
 10336ec:	jae    10338bf <main+0xcbf>
 10336f2:	mov    %rcx,%rax
 10336f5:	shl    $0x4,%rax
 10336f9:	cmp    %r14,%r12
 10336fc:	movq   $0x1,0x20(%r13,%rax,1)
 1033705:	setl   0x28(%r13,%rax,1)
 103370b:	jmp    103377e <main+0xb7e>
 103370d:	mov    %r12,%r15
 1033710:	imul   %r14,%r15
 1033714:	jo     103420e <main+0x160e>
 103371a:	cmp    0x10(%r13),%rcx
 103371e:	jb     10337b2 <main+0xbb2>
 1033724:	mov    $0x10,%esi
 1033729:	mov    %rdi,%r14
 103372c:	mov    %r13,%rdi
 103372f:	vzeroupper
 1033732:	call   1009130 <myl_core_list_grow>
 1033737:	vxorps %xmm1,%xmm1,%xmm1
 103373b:	xor    %r11d,%r11d
 103373e:	mov    0x10(%rsp),%r10
 1033743:	mov    0x8(%rsp),%r8
 1033748:	lea    0x26421(%rip),%r9        # 1059b70 <myl_core_free_lists>
 103374f:	mov    %r14,%rdi
 1033752:	mov    %rax,%r13
 1033755:	mov    0x8(%rax),%rcx
 1033759:	jmp    10337b2 <main+0xbb2>
 103375b:	cmp    0x10(%r13),%rcx
 103375f:	jae    10338fd <main+0xcfd>
 1033765:	mov    %rcx,%rax
 1033768:	shl    $0x4,%rax
 103376c:	cmp    %r14,%r12
 103376f:	movq   $0x1,0x20(%r13,%rax,1)
 1033778:	sete   0x28(%r13,%rax,1)
 103377e:	inc    %rcx
 1033781:	mov    %rcx,0x8(%r13)
 1033785:	jmp    103346a <main+0x86a>
 103378a:	mov    %r12d,%eax
 103378d:	xor    %edx,%edx
 103378f:	div    %esi
 1033791:	mov    %rdx,%r15
 1033794:	xor    %r14,%r15
 1033797:	sar    $0x3f,%r15
 103379b:	and    %r14,%r15
 103379e:	test   %rdx,%rdx
 10337a1:	cmove  %rdx,%r15
 10337a5:	cmp    0x10(%r13),%rcx
 10337a9:	jae    103393b <main+0xd3b>
 10337af:	add    %rdx,%r15
 10337b2:	mov    %rcx,%rax
 10337b5:	shl    $0x4,%rax
 10337b9:	movq   $0x0,0x20(%r13,%rax,1)
 10337c2:	mov    %r15,0x28(%r13,%rax,1)
 10337c7:	inc    %rcx
 10337ca:	mov    %rcx,0x8(%r13)
 10337ce:	lea    -0x2f1c5(%rip),%r15        # 1004610 <core_number_pairs+0xe0>
 10337d5:	jmp    103346a <main+0x86a>
 10337da:	mov    $0x10,%esi
 10337df:	mov    %rdi,%r12
 10337e2:	mov    %r13,%rdi
 10337e5:	vzeroupper
 10337e8:	call   1009130 <myl_core_list_grow>
 10337ed:	vxorps %xmm1,%xmm1,%xmm1
 10337f1:	xor    %r11d,%r11d
 10337f4:	mov    0x10(%rsp),%r10
 10337f9:	mov    0x8(%rsp),%r8
 10337fe:	lea    0x2636b(%rip),%r9        # 1059b70 <myl_core_free_lists>
 1033805:	mov    %r12,%rdi
 1033808:	mov    %rax,%r13
 103380b:	mov    0x8(%rax),%rax
 103380f:	jmp    103344e <main+0x84e>
 1033814:	mov    $0x10,%esi
 1033819:	mov    %rdi,%r14
 103381c:	mov    %r13,%rdi
 103381f:	vzeroupper
 1033822:	call   1009130 <myl_core_list_grow>
 1033827:	vxorps %xmm1,%xmm1,%xmm1
 103382b:	xor    %r11d,%r11d
 103382e:	mov    0x10(%rsp),%r10
 1033833:	mov    0x8(%rsp),%r8
 1033838:	lea    0x26331(%rip),%r9        # 1059b70 <myl_core_free_lists>
 103383f:	mov    %r14,%rdi
 1033842:	mov    %rax,%r13
 1033845:	mov    0x8(%rax),%rax
 1033849:	jmp    10334be <main+0x8be>
 103384e:	mov    $0x10,%esi
 1033853:	mov    %rdi,%r14
 1033856:	mov    %r13,%rdi
 1033859:	vzeroupper
 103385c:	call   1009130 <myl_core_list_grow>
 1033861:	vxorps %xmm1,%xmm1,%xmm1
 1033865:	xor    %r11d,%r11d
 1033868:	mov    0x10(%rsp),%r10
 103386d:	mov    0x8(%rsp),%r8
 1033872:	lea    0x262f7(%rip),%r9        # 1059b70 <myl_core_free_lists>
 1033879:	mov    %r14,%rdi
 103387c:	mov    %rax,%r13
 103387f:	mov    0x8(%rax),%rax
 1033883:	jmp    103355d <main+0x95d>
 1033888:	mov    $0x8,%esi
 103388d:	mov    %rdi,%r12
 1033890:	mov    %rax,%rdi
 1033893:	vzeroupper
 1033896:	call   1009130 <myl_core_list_grow>
 103389b:	vxorps %xmm1,%xmm1,%xmm1
 103389f:	xor    %r11d,%r11d
 10338a2:	mov    0x10(%rsp),%r10
 10338a7:	mov    0x8(%rsp),%r8
 10338ac:	lea    0x262bd(%rip),%r9        # 1059b70 <myl_core_free_lists>
 10338b3:	mov    %r12,%rdi
 10338b6:	mov    0x8(%rax),%rcx
 10338ba:	jmp    103366e <main+0xa6e>
 10338bf:	mov    $0x10,%esi
 10338c4:	mov    %rdi,0x20(%rsp)
 10338c9:	mov    %r13,%rdi
 10338cc:	vzeroupper
 10338cf:	call   1009130 <myl_core_list_grow>
 10338d4:	vxorps %xmm1,%xmm1,%xmm1
 10338d8:	xor    %r11d,%r11d
 10338db:	mov    0x10(%rsp),%r10
 10338e0:	mov    0x8(%rsp),%r8
 10338e5:	lea    0x26284(%rip),%r9        # 1059b70 <myl_core_free_lists>
 10338ec:	mov    0x20(%rsp),%rdi
 10338f1:	mov    %rax,%r13
 10338f4:	mov    0x8(%rax),%rcx
 10338f8:	jmp    10336f2 <main+0xaf2>
 10338fd:	mov    $0x10,%esi
 1033902:	mov    %rdi,0x20(%rsp)
 1033907:	mov    %r13,%rdi
 103390a:	vzeroupper
 103390d:	call   1009130 <myl_core_list_grow>
 1033912:	vxorps %xmm1,%xmm1,%xmm1
 1033916:	xor    %r11d,%r11d
 1033919:	mov    0x10(%rsp),%r10
 103391e:	mov    0x8(%rsp),%r8
 1033923:	lea    0x26246(%rip),%r9        # 1059b70 <myl_core_free_lists>
 103392a:	mov    0x20(%rsp),%rdi
 103392f:	mov    %rax,%r13
 1033932:	mov    0x8(%rax),%rcx
 1033936:	jmp    1033765 <main+0xb65>
 103393b:	mov    $0x10,%esi
 1033940:	mov    %rdi,%r12
 1033943:	mov    %r13,%rdi
 1033946:	mov    %rdx,%r14
 1033949:	vzeroupper
 103394c:	call   1009130 <myl_core_list_grow>
 1033951:	vxorps %xmm1,%xmm1,%xmm1
 1033955:	xor    %r11d,%r11d
 1033958:	mov    0x10(%rsp),%r10
 103395d:	mov    0x8(%rsp),%r8
 1033962:	lea    0x26207(%rip),%r9        # 1059b70 <myl_core_free_lists>
 1033969:	mov    %r12,%rdi
 103396c:	mov    %r14,%rdx
 103396f:	mov    %rax,%r13
 1033972:	mov    0x8(%rax),%rcx
 1033976:	jmp    10337af <main+0xbaf>
 103397b:	nopl   0x0(%rax,%rax,1)
 1033980:	movzbl 0x7(%rdi),%eax
 1033984:	test   %rax,%rax
 1033987:	je     1033b7d <main+0xf7d>
 103398d:	cmpq   $0x0,0x18(%rdi)
 1033992:	jne    1033b7d <main+0xf7d>
 1033998:	mov    (%r9,%rax,8),%rcx
 103399c:	mov    %rcx,(%rdi)
 103399f:	mov    %rdi,(%r9,%rax,8)
 10339a3:	movabs $0x100000000000001,%r12
 10339ad:	mov    0x38(%rsp),%rbp
 10339b2:	mov    0x18(%rsp),%rdi
 10339b7:	movzbl 0x7(%rdi),%eax
 10339bb:	test   %rax,%rax
 10339be:	je     1033ba2 <main+0xfa2>
 10339c4:	cmpq   $0x0,0x18(%rdi)
 10339c9:	jne    1033ba2 <main+0xfa2>
 10339cf:	mov    (%r9,%rax,8),%rcx
 10339d3:	mov    %rcx,(%rdi)
 10339d6:	mov    %rdi,(%r9,%rax,8)
 10339da:	mov    0x8(%r13),%rax
 10339de:	test   %rax,%rax
 10339e1:	je     1034280 <main+0x1680>
 10339e7:	dec    %rax
 10339ea:	mov    %rax,%rcx
 10339ed:	shl    $0x4,%rcx
 10339f1:	movzbl 0x20(%r13,%rcx,1),%r15d
 10339f7:	mov    0x28(%r13,%rcx,1),%r14
 10339fc:	mov    %rax,0x8(%r13)
 1033a00:	movzbl 0x7(%r13),%eax
 1033a05:	test   %rax,%rax
 1033a08:	je     1033bc7 <main+0xfc7>
 1033a0e:	cmpq   $0x0,0x18(%r13)
 1033a13:	jne    1033bc7 <main+0xfc7>
 1033a19:	mov    (%r9,%rax,8),%rcx
 1033a1d:	mov    %rcx,0x0(%r13)
 1033a21:	mov    %r13,(%r9,%rax,8)
 1033a25:	test   %r15,%r15
 1033a28:	cmovne %r11,%r14
 1033a2c:	test   %r14,%r14
 1033a2f:	js     1033bfb <main+0xffb>
 1033a35:	mov    %rbp,%r15
 1033a38:	add    %r14,%r15
 1033a3b:	jo     1034293 <main+0x1693>
 1033a41:	mov    %r15,%rdx
 1033a44:	movabs $0x89705f3112a28fe5,%rax
 1033a4e:	mulx   %rax,%rax,%rax
 1033a53:	shr    $0x1d,%rax
 1033a57:	imul   $0x3b9aca07,%rax,%rax
 1033a5e:	sub    %rax,%r15
 1033a61:	mov    0x58(%rsp),%rdx
 1033a66:	inc    %rdx
 1033a69:	mov    %r15,%rbp
 1033a6c:	cmp    0x50(%rsp),%rdx
 1033a71:	jne    1033340 <main+0x740>
 1033a77:	jmp    1033c1d <main+0x101d>
 1033a7c:	mov    $0x10,%esi
 1033a81:	xor    %edi,%edi
 1033a83:	mov    %rdx,%r14
 1033a86:	vzeroupper
 1033a89:	call   10090c0 <myl_core_list_new_slow>
 1033a8e:	vxorps %xmm1,%xmm1,%xmm1
 1033a92:	mov    %r14,%rdx
 1033a95:	xor    %r11d,%r11d
 1033a98:	mov    0x10(%rsp),%r10
 1033a9d:	mov    0x8(%rsp),%r8
 1033aa2:	lea    0x260c7(%rip),%r9        # 1059b70 <myl_core_free_lists>
 1033aa9:	mov    %rax,%r13
 1033aac:	jmp    103337a <main+0x77a>
 1033ab1:	mov    $0x8,%esi
 1033ab6:	xor    %edi,%edi
 1033ab8:	mov    %rdx,%r14
 1033abb:	vzeroupper
 1033abe:	call   10090c0 <myl_core_list_new_slow>
 1033ac3:	vxorps %xmm1,%xmm1,%xmm1
 1033ac7:	mov    %r14,%rdx
 1033aca:	xor    %r11d,%r11d
 1033acd:	mov    0x10(%rsp),%r10
 1033ad2:	mov    0x8(%rsp),%r8
 1033ad7:	lea    0x26092(%rip),%r9        # 1059b70 <myl_core_free_lists>
 1033ade:	mov    %rax,0x18(%rsp)
 1033ae3:	jmp    10333aa <main+0x7aa>
 1033ae8:	mov    %rdx,%r14
 1033aeb:	mov    $0x2,%edi
 1033af0:	mov    $0x8,%esi
 1033af5:	vzeroupper
 1033af8:	call   10090c0 <myl_core_list_new_slow>
 1033afd:	mov    %rax,%rdi
 1033b00:	mov    0x8(%rax),%rsi
 1033b04:	mov    0x10(%rax),%rcx
 1033b08:	cmp    %rcx,%rsi
 1033b0b:	jb     1033bef <main+0xfef>
 1033b11:	mov    $0x8,%esi
 1033b16:	call   1009130 <myl_core_list_grow>
 1033b1b:	mov    0x8(%rax),%rsi
 1033b1f:	mov    0x10(%rax),%rcx
 1033b23:	lea    0x26046(%rip),%r9        # 1059b70 <myl_core_free_lists>
 1033b2a:	mov    %rax,%rdi
 1033b2d:	mov    0x8(%rsp),%r8
 1033b32:	mov    0x10(%rsp),%r10
 1033b37:	xor    %r11d,%r11d
 1033b3a:	mov    %r14,%rdx
 1033b3d:	vxorps %xmm1,%xmm1,%xmm1
 1033b41:	jmp    10333d1 <main+0x7d1>
 1033b46:	mov    $0x8,%esi
 1033b4b:	mov    %rdx,%r14
 1033b4e:	vzeroupper
 1033b51:	call   1009130 <myl_core_list_grow>
 1033b56:	vxorps %xmm1,%xmm1,%xmm1
 1033b5a:	mov    %r14,%rdx
 1033b5d:	xor    %r11d,%r11d
 1033b60:	mov    0x10(%rsp),%r10
 1033b65:	mov    0x8(%rsp),%r8
 1033b6a:	lea    0x25fff(%rip),%r9        # 1059b70 <myl_core_free_lists>
 1033b71:	mov    %rax,%rdi
 1033b74:	mov    0x8(%rax),%rsi
 1033b78:	jmp    10333ea <main+0x7ea>
 1033b7d:	vzeroupper
 1033b80:	call   10323d0 <myl_core_free_block>
 1033b85:	vxorps %xmm1,%xmm1,%xmm1
 1033b89:	xor    %r11d,%r11d
 1033b8c:	mov    0x10(%rsp),%r10
 1033b91:	mov    0x8(%rsp),%r8
 1033b96:	lea    0x25fd3(%rip),%r9        # 1059b70 <myl_core_free_lists>
 1033b9d:	jmp    10339a3 <main+0xda3>
 1033ba2:	vzeroupper
 1033ba5:	call   10323d0 <myl_core_free_block>
 1033baa:	vxorps %xmm1,%xmm1,%xmm1
 1033bae:	xor    %r11d,%r11d
 1033bb1:	mov    0x10(%rsp),%r10
 1033bb6:	mov    0x8(%rsp),%r8
 1033bbb:	lea    0x25fae(%rip),%r9        # 1059b70 <myl_core_free_lists>
 1033bc2:	jmp    10339da <main+0xdda>
 1033bc7:	mov    %r13,%rdi
 1033bca:	vzeroupper
 1033bcd:	call   10323d0 <myl_core_free_block>
 1033bd2:	vxorps %xmm1,%xmm1,%xmm1
 1033bd6:	xor    %r11d,%r11d
 1033bd9:	mov    0x10(%rsp),%r10
 1033bde:	mov    0x8(%rsp),%r8
 1033be3:	lea    0x25f86(%rip),%r9        # 1059b70 <myl_core_free_lists>
 1033bea:	jmp    1033a25 <main+0xe25>
 1033bef:	lea    0x25f7a(%rip),%r9        # 1059b70 <myl_core_free_lists>
 1033bf6:	jmp    1033b2d <main+0xf2d>
 1033bfb:	mov    (%r10),%eax
 1033bfe:	mov    $0x2,%ebx
 1033c03:	cmp    $0xffffffff,%eax
 1033c06:	je     1033ced <main+0x10ed>
 1033c0c:	dec    %eax
 1033c0e:	mov    0x28(%rsp),%r14
 1033c13:	je     1033c41 <main+0x1041>
 1033c15:	mov    %eax,(%r10)
 1033c18:	jmp    1033cf2 <main+0x10f2>
 1033c1d:	mov    (%r10),%eax
 1033c20:	cmp    $0xffffffff,%eax
 1033c23:	je     1033c8e <main+0x108e>
 1033c25:	dec    %eax
 1033c27:	je     1033c6a <main+0x106a>
 1033c29:	mov    %eax,(%r10)
 1033c2c:	jmp    1033c8e <main+0x108e>
 1033c2e:	xor    %edx,%edx
 1033c30:	xor    %esi,%esi
 1033c32:	lea    0x1d47(%rip),%rdi        # 1035980 <core_io_file_error.verbs+0x1a0>
 1033c39:	vzeroupper
 1033c3c:	call   10097c0 <myl_core_trap>
 1033c41:	movzbl 0x7(%r10),%eax
 1033c46:	test   %rax,%rax
 1033c49:	je     103424c <main+0x164c>
 1033c4f:	cmpq   $0x0,0x18(%r10)
 1033c54:	jne    103424c <main+0x164c>
 1033c5a:	mov    (%r9,%rax,8),%rcx
 1033c5e:	mov    %rcx,(%r10)
 1033c61:	mov    %r10,(%r9,%rax,8)
 1033c65:	jmp    1033cf2 <main+0x10f2>
 1033c6a:	movzbl 0x7(%r10),%eax
 1033c6f:	test   %rax,%rax
 1033c72:	je     103425c <main+0x165c>
 1033c78:	cmpq   $0x0,0x18(%r10)
 1033c7d:	jne    103425c <main+0x165c>
 1033c83:	mov    (%r9,%rax,8),%rcx
 1033c87:	mov    %rcx,(%r10)
 1033c8a:	mov    %r10,(%r9,%rax,8)
 1033c8e:	lea    0x1c2b(%rip),%rdi        # 10358c0 <core_io_file_error.verbs+0xe0>
 1033c95:	vzeroupper
 1033c98:	call   100a100 <myl_core_io_at>
 1033c9d:	mov    0x48(%rsp),%rdi
 1033ca2:	call   1022070 <myl_core_host_check>
